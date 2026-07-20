#include "SoloCollectionsMountService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsMountCatalog.h"

#include "Log.h"
#include "Player.h"
#include "WorldSession.h"

#include <deque>
#include <map>
#include <set>
#include <utility>

namespace SoloCollections
{
namespace
{
constexpr std::uint32_t MountSpellMigrationId = 1;
constexpr std::uint16_t MountSpellMigrationVersion = 1;

enum class MigrationPhase : std::uint8_t
{
    AwaitingReady = 1,
    CheckingMarker = 2,
    Importing = 3,
    WritingMarker = 4,
    Complete = 5,
    Failed = 6,
};

struct PendingMountGrant
{
    CollectionId Collection;
    std::uint32_t SpellId = 0;
    std::uint32_t CharacterGuid = 0;
    CollectionSourceKind SourceKind = CollectionSourceKind::Gameplay;
    bool Started = false;
};

struct MountAccountState
{
    MigrationPhase Phase = MigrationPhase::AwaitingReady;
    LoginGeneration Generation;
    std::uint32_t LoginCharacterGuid = 0;
    std::set<std::uint32_t> CandidateSpells;
    std::set<CollectionId> QueuedCollections;
    std::deque<PendingMountGrant> Pending;
    std::uint32_t ImportedCount = 0;
    std::uint32_t RejectedCount = 0;
};

AccountId PlayerAccount(Player* player)
{
    return AccountId(player->GetSession()->GetAccountId());
}
}

class MountCollectionService::Impl
{
public:
    void OnPlayerLogin(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        AccountId account = PlayerAccount(player);
        MountAccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
    }

    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
    {
        if (!player || !player->GetSession())
            return;
        MountCollectionDefinition const* definition = GetMountCatalog().FindByUnlockSpell(spellId);
        if (!definition)
            return;
        AccountId account = PlayerAccount(player);
        MountAccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        QueueGrant(state, *definition, spellId, state.LoginCharacterGuid, CollectionSourceKind::Gameplay);
        LOG_INFO("module.solocollections.mount",
            "event=mount_spell_learned account={} character={} spell={} collection={}",
            account.Value(), state.LoginCharacterGuid, spellId, definition->Id.Value());
    }

    void OnPlayerUpdate(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        AccountId account = PlayerAccount(player);
        auto found = _accounts.find(account);
        if (found == _accounts.end())
            return;
        MountAccountState& state = found->second;
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        state.Generation = snapshot->Generation;

        if (state.Phase == MigrationPhase::AwaitingReady)
            BeginMigrationCheck(player, account, state);
        Advance(account, state);
    }

private:
    static void QueueGrant(MountAccountState& state, MountCollectionDefinition const& definition,
        std::uint32_t spellId, std::uint32_t characterGuid, CollectionSourceKind sourceKind)
    {
        if (!state.QueuedCollections.insert(definition.Id).second)
            return;
        state.Pending.push_back({ definition.Id, spellId, characterGuid, sourceKind, false });
    }

    void BeginMigrationCheck(Player* player, AccountId account, MountAccountState& state)
    {
        for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
            for (std::uint32_t spellId : definition.UnlockSpellIds)
                if (player->HasSpell(spellId))
                    state.CandidateSpells.insert(spellId);

        state.Phase = MigrationPhase::CheckingMarker;
        bool started = GetAccountCollectionStore().CheckMigrationMarker(
            { account, MountSpellMigrationId, MountSpellMigrationVersion },
            [this, account](bool succeeded, bool completed, std::vector<std::uint32_t> databaseSpells)
            {
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                MountAccountState& current = found->second;
                if (!succeeded)
                {
                    current.Phase = MigrationPhase::Failed;
                    LOG_ERROR("module.solocollections.mount",
                        "event=mount_migration_check result=failed account={}", account.Value());
                    return;
                }
                if (completed)
                {
                    current.Phase = MigrationPhase::Complete;
                    current.CandidateSpells.clear();
                    LOG_DEBUG("module.solocollections.mount",
                        "event=mount_migration_check result=already_complete account={}", account.Value());
                    return;
                }
                current.CandidateSpells.insert(databaseSpells.begin(), databaseSpells.end());
                for (std::uint32_t spellId : current.CandidateSpells)
                    if (MountCollectionDefinition const* definition = GetMountCatalog().FindByUnlockSpell(spellId))
                        QueueGrant(current, *definition, spellId, current.LoginCharacterGuid, CollectionSourceKind::Migration);
                current.CandidateSpells.clear();
                current.Phase = MigrationPhase::Importing;
                LOG_INFO("module.solocollections.mount",
                    "event=mount_migration_check result=import account={} queued={}",
                    account.Value(), current.Pending.size());
            });
        if (!started)
            state.Phase = MigrationPhase::AwaitingReady;
    }

    void Advance(AccountId account, MountAccountState& state)
    {
        AccountCollectionStore& store = GetAccountCollectionStore();
        if (store.HasPendingMutation(account))
            return;

        while (!state.Pending.empty())
        {
            PendingMountGrant& grant = state.Pending.front();
            CollectionKey key { MountCollectionTypeId, grant.Collection };
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
            if (result.Reason == CollectionReasonCode::AlreadyOwned)
            {
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }
            if (grant.SourceKind == CollectionSourceKind::Migration)
                ++state.RejectedCount;
            LOG_ERROR("module.solocollections.mount",
                "event=mount_unlock result=rejected account={} spell={} collection={} reason={}",
                account.Value(), grant.SpellId, grant.Collection.Value(), ToStableReasonCode(result.Reason));
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
            { { account, MountSpellMigrationId, MountSpellMigrationVersion }, snapshot->Revision,
                state.ImportedCount, state.RejectedCount },
            [this, account](bool committed)
            {
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                found->second.Phase = committed ? MigrationPhase::Complete : MigrationPhase::Failed;
                LOG_INFO("module.solocollections.mount",
                    "event=mount_migration_marker result={} account={} imported={} rejected={}",
                    committed ? "complete" : "failed", account.Value(),
                    found->second.ImportedCount, found->second.RejectedCount);
            });
        if (!started)
            state.Phase = MigrationPhase::Importing;
    }

    std::map<AccountId, MountAccountState> _accounts;
};

MountCollectionService::MountCollectionService() : _impl(std::make_unique<Impl>()) { }
MountCollectionService::~MountCollectionService() = default;

void MountCollectionService::OnPlayerLogin(Player* player)
{
    _impl->OnPlayerLogin(player);
}

void MountCollectionService::OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
{
    _impl->OnPlayerLearnSpell(player, spellId);
}

void MountCollectionService::OnPlayerUpdate(Player* player)
{
    _impl->OnPlayerUpdate(player);
}

MountCollectionService& GetMountCollectionService()
{
    static MountCollectionService service;
    return service;
}
}
