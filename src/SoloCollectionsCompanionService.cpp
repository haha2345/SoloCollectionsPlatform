#include "SoloCollectionsCompanionService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsCompanionCatalog.h"

#include "Creature.h"
#include "Log.h"
#include "Player.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <utility>

namespace SoloCollections
{
namespace
{
constexpr std::uint32_t CompanionSpellMigrationId = 2;
constexpr std::uint16_t CompanionSpellMigrationVersion = 1;

enum class MigrationPhase : std::uint8_t
{
    AwaitingReady = 1,
    CheckingMarker = 2,
    Importing = 3,
    WritingMarker = 4,
    Complete = 5,
    Failed = 6,
};

struct PendingGrant
{
    CollectionId Collection;
    std::uint32_t SpellId = 0;
    std::uint32_t CharacterGuid = 0;
    CollectionSourceKind SourceKind = CollectionSourceKind::Gameplay;
    bool Started = false;
};

struct AccountState
{
    MigrationPhase Phase = MigrationPhase::AwaitingReady;
    LoginGeneration Generation;
    std::uint32_t LoginCharacterGuid = 0;
    std::set<std::uint32_t> CandidateSpells;
    std::set<CollectionId> QueuedCollections;
    std::deque<PendingGrant> Pending;
    std::uint32_t ImportedCount = 0;
    std::uint32_t RejectedCount = 0;
};

AccountId PlayerAccount(Player* player)
{
    return AccountId(player->GetSession()->GetAccountId());
}
}

class CompanionCollectionService::Impl
{
public:
    void OnPlayerLogin(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        std::scoped_lock lock(_mutex);
        AccountState& state = _accounts[PlayerAccount(player)];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        for (CompanionCollectionDefinition const& definition : GetCompanionCatalog().Collections())
            if (player->HasSpell(definition.SpellId))
                state.CandidateSpells.insert(definition.SpellId);
    }

    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
    {
        if (!player || !player->GetSession())
            return;
        CompanionCollectionDefinition const* definition = GetCompanionCatalog().FindBySpell(spellId);
        if (!definition)
            return;
        std::scoped_lock lock(_mutex);
        AccountId account = PlayerAccount(player);
        AccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        QueueGrant(state, *definition, spellId, state.LoginCharacterGuid, CollectionSourceKind::Gameplay);
        LOG_INFO("module.solocollections.companion",
            "event=companion_spell_learned account={} character={} spell={} collection={}",
            account.Value(), state.LoginCharacterGuid, spellId, definition->Id.Value());
    }

    void Update()
    {
        std::scoped_lock lock(_mutex);
        for (auto& [account, state] : _accounts)
        {
            std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
            if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
                continue;
            state.Generation = snapshot->Generation;
            if (state.Phase == MigrationPhase::AwaitingReady)
                BeginMigrationCheck(account, state);
            Advance(account, state);
        }
    }

    std::string ExecuteSummon(Player* player, CollectionId collectionId)
    {
        if (!player || !player->GetSession() || !collectionId.IsValid())
            return "INVALID_REQUEST";
        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            return "LOADING";
        if (snapshot->State == AccountCacheLoadState::Failed)
            return "DB_UNAVAILABLE";
        CompanionCollectionDefinition const* definition = GetCompanionCatalog().Find(collectionId);
        if (!definition)
            return "INVALID_REQUEST";
        if (definition->Lifecycle == CatalogLifecycle::Tombstone)
            return "INVALID_REQUEST";
        if (!CatalogLifecycleAllowsAction(definition->Lifecycle))
            return "UNSUPPORTED";
        if (!GetAccountCollectionCache().IsOwned(account, { CompanionCollectionTypeId, collectionId }))
            return "NOT_OWNED";
        if (!player->IsAlive())
            return "DEAD";
        if (player->IsInCombat())
            return "IN_COMBAT";
        if (player->GetVehicle())
            return "IN_VEHICLE";
        if (player->IsInFlight())
            return "ON_TAXI";

        // Core owns companion lifetime. Query the live minipet slot instead of
        // retaining a stale service-side GUID across map changes or logout.
        if (Creature* current = player->GetCompanionPet())
        {
            if (current->GetUInt32Value(UNIT_CREATED_BY_SPELL) == definition->SpellId)
            {
                current->DespawnOrUnsummon();
                LOG_INFO("module.solocollections.companion",
                    "event=companion_toggle result=dismissed account={} character={} collection={} spell={}",
                    account.Value(), player->GetGUID().GetCounter(), collectionId.Value(), definition->SpellId);
                return "DISMISSED";
            }
        }

        SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(definition->SpellId);
        if (!spellInfo)
            return "CAST_FAILED";
        if (spellInfo->CheckLocation(player->GetMapId(), player->GetZoneId(), player->GetAreaId(), player, true) != SPELL_CAST_OK)
            return "MAP_RESTRICTED";
        SpellCastResult result = player->CastSpell(player, spellInfo, TRIGGERED_NONE);
        if (result != SPELL_CAST_OK)
            return "CAST_FAILED";
        LOG_INFO("module.solocollections.companion",
            "event=companion_summon result=accepted account={} character={} collection={} spell={}",
            account.Value(), player->GetGUID().GetCounter(), collectionId.Value(), definition->SpellId);
        return "ACCEPTED";
    }

private:
    static void QueueGrant(AccountState& state, CompanionCollectionDefinition const& definition,
        std::uint32_t spellId, std::uint32_t characterGuid, CollectionSourceKind sourceKind)
    {
        if (state.QueuedCollections.insert(definition.Id).second)
            state.Pending.push_back({ definition.Id, spellId, characterGuid, sourceKind, false });
    }

    void BeginMigrationCheck(AccountId account, AccountState& state)
    {
        state.Phase = MigrationPhase::CheckingMarker;
        bool started = GetAccountCollectionStore().CheckMigrationMarker(
            { account, CompanionSpellMigrationId, CompanionSpellMigrationVersion },
            [this, account](bool succeeded, bool completed, std::vector<std::uint32_t> databaseSpells)
            {
                std::scoped_lock lock(_mutex);
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                AccountState& current = found->second;
                if (!succeeded)
                {
                    current.Phase = MigrationPhase::Failed;
                    LOG_ERROR("module.solocollections.companion",
                        "event=companion_migration_check result=failed account={}", account.Value());
                    return;
                }
                if (completed)
                {
                    current.Phase = MigrationPhase::Complete;
                    current.CandidateSpells.clear();
                    return;
                }
                current.CandidateSpells.insert(databaseSpells.begin(), databaseSpells.end());
                for (std::uint32_t spellId : current.CandidateSpells)
                    if (CompanionCollectionDefinition const* definition = GetCompanionCatalog().FindBySpell(spellId))
                        QueueGrant(current, *definition, spellId, current.LoginCharacterGuid, CollectionSourceKind::Migration);
                current.CandidateSpells.clear();
                current.Phase = MigrationPhase::Importing;
                LOG_INFO("module.solocollections.companion",
                    "event=companion_migration_check result=import account={} queued={}",
                    account.Value(), current.Pending.size());
            });
        if (!started)
            state.Phase = MigrationPhase::AwaitingReady;
    }

    void Advance(AccountId account, AccountState& state)
    {
        AccountCollectionStore& store = GetAccountCollectionStore();
        if (store.HasPendingMutation(account))
            return;
        while (!state.Pending.empty())
        {
            PendingGrant& grant = state.Pending.front();
            CollectionKey key { CompanionCollectionTypeId, grant.Collection };
            if (GetAccountCollectionCache().IsOwned(account, key))
            {
                if (grant.Started && grant.SourceKind == CollectionSourceKind::Migration)
                    ++state.ImportedCount;
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }
            AccountCollectionMutation mutation;
            mutation.Account = account;
            mutation.Generation = state.Generation;
            mutation.Key = key;
            mutation.Kind = CollectionMutationKind::Grant;
            mutation.SourceKind = grant.SourceKind;
            mutation.SourceId = grant.SpellId;
            mutation.CharacterGuid = grant.CharacterGuid;
            MutationStartResult result = store.BeginMutation(mutation);
            if (result.Accepted)
            {
                grant.Started = true;
                return;
            }
            if (result.Reason == CollectionReasonCode::PendingOperation || result.Reason == CollectionReasonCode::NotReady)
                return;
            if (grant.SourceKind == CollectionSourceKind::Migration)
                ++state.RejectedCount;
            state.QueuedCollections.erase(grant.Collection);
            state.Pending.pop_front();
        }
        if (state.Phase != MigrationPhase::Importing)
            return;
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        state.Phase = MigrationPhase::WritingMarker;
        bool started = store.CompleteMigrationMarker(
            { { account, CompanionSpellMigrationId, CompanionSpellMigrationVersion }, snapshot->Revision,
                state.ImportedCount, state.RejectedCount },
            [this, account](bool committed)
            {
                std::scoped_lock lock(_mutex);
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                found->second.Phase = committed ? MigrationPhase::Complete : MigrationPhase::Failed;
                LOG_INFO("module.solocollections.companion",
                    "event=companion_migration_marker result={} account={} imported={} rejected={}",
                    committed ? "complete" : "failed", account.Value(),
                    found->second.ImportedCount, found->second.RejectedCount);
            });
        if (!started)
            state.Phase = MigrationPhase::Importing;
    }

    std::map<AccountId, AccountState> _accounts;
    std::mutex _mutex;
};

CompanionCollectionService::CompanionCollectionService() : _impl(std::make_unique<Impl>()) { }
CompanionCollectionService::~CompanionCollectionService() = default;
void CompanionCollectionService::OnPlayerLogin(Player* player) { _impl->OnPlayerLogin(player); }
void CompanionCollectionService::OnPlayerLearnSpell(Player* player, std::uint32_t spellId) { _impl->OnPlayerLearnSpell(player, spellId); }
void CompanionCollectionService::Update() { _impl->Update(); }
std::string CompanionCollectionService::ExecuteSummon(Player* player, CollectionId collectionId)
{
    return _impl->ExecuteSummon(player, collectionId);
}

CompanionCollectionService& GetCompanionCollectionService()
{
    static CompanionCollectionService service;
    return service;
}
}
