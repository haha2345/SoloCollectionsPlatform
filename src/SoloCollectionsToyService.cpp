#include "SoloCollectionsToyService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsToyCatalog.h"

#include "Item.h"
#include "Log.h"
#include "Player.h"
#include "Spell.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <chrono>
#include <deque>
#include <functional>
#include <map>
#include <mutex>
#include <set>

namespace SoloCollections
{
namespace
{
struct PendingGrant
{
    CollectionId Collection;
    std::uint32_t ItemId = 0;
    std::uint32_t CharacterGuid = 0;
};

struct AccountState
{
    LoginGeneration Generation;
    std::set<CollectionId> QueuedCollections;
    std::deque<PendingGrant> Pending;
};

AccountId PlayerAccount(Player* player)
{
    return AccountId(player->GetSession()->GetAccountId());
}

std::uint64_t MonotonicMilliseconds()
{
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
}

class ToyCollectionService::Impl
{
public:
    Impl()
    {
        _customHandlers.emplace("unusual_compass",
            [](Player* player, ToyCollectionDefinition const& definition, Unit* target)
            {
                SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(definition.SpellId);
                return spellInfo ? player->CastSpell(target, spellInfo, TRIGGERED_NONE) : SPELL_FAILED_SPELL_UNAVAILABLE;
            });
    }

    void OnPlayerLogin(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        std::scoped_lock lock(_mutex);
        AccountState& state = _accounts[PlayerAccount(player)];
        for (ToyCollectionDefinition const& definition : GetToyCatalog().Collections())
            if (player->HasItemCount(definition.ItemId, 1, true))
                QueueGrant(state, definition, player->GetGUID().GetCounter());
    }

    void OnItemAcquired(Player* player, std::uint32_t itemId)
    {
        if (!player || !player->GetSession())
            return;
        ToyCollectionDefinition const* definition = GetToyCatalog().FindByItem(itemId);
        if (!definition)
            return;
        std::scoped_lock lock(_mutex);
        QueueGrant(_accounts[PlayerAccount(player)], *definition, player->GetGUID().GetCounter());
        LOG_INFO("module.solocollections.toy",
            "event=toy_item_acquired account={} character={} item={} collection={}",
            player->GetSession()->GetAccountId(), player->GetGUID().GetCounter(), itemId, definition->Id.Value());
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
            Advance(account, state);
        }
    }

    std::string ExecuteUse(Player* player, CollectionId collectionId, bool currentTargetRequested)
    {
        if (!player || !player->GetSession() || !collectionId.IsValid())
            return "INVALID_REQUEST";
        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            return "LOADING";
        if (snapshot->State == AccountCacheLoadState::Failed)
            return "DB_UNAVAILABLE";
        ToyCollectionDefinition const* definition = GetToyCatalog().Find(collectionId);
        if (!definition)
            return "INVALID_REQUEST";
        if (!GetAccountCollectionCache().IsOwned(account, { ToyCollectionTypeId, collectionId }))
            return "NOT_OWNED";
        bool targetExpected = definition->TargetPolicy == ToyTargetPolicy::CurrentTarget;
        if (targetExpected != currentTargetRequested)
            return "INVALID_REQUEST";
        if (!player->IsAlive())
            return "DEAD";
        if (!definition->AllowInCombat && player->IsInCombat())
            return "IN_COMBAT";
        if (player->GetVehicle())
            return "IN_VEHICLE";
        if (player->IsInFlight())
            return "ON_TAXI";

        Unit* target = targetExpected ? player->GetSelectedUnit() : player;
        if (!target)
            return "TARGET_REQUIRED";
        std::uint64_t now = MonotonicMilliseconds();
        if (definition->CooldownScope == ToyCooldownScope::Account)
        {
            std::scoped_lock lock(_mutex);
            auto accountCooldown = _accountCooldowns.find(account);
            if (accountCooldown != _accountCooldowns.end())
            {
                auto cooldown = accountCooldown->second.find(collectionId);
                if (cooldown != accountCooldown->second.end() && cooldown->second > now)
                    return "COOLDOWN";
            }
        }
        if (player->HasSpellCooldown(definition->SpellId))
            return "COOLDOWN";
        SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(definition->SpellId);
        if (!spellInfo)
            return "CAST_FAILED";
        if (spellInfo->CheckLocation(player->GetMapId(), player->GetZoneId(), player->GetAreaId(), player, true) != SPELL_CAST_OK)
            return "MAP_RESTRICTED";

        SpellCastResult castResult = SPELL_CAST_OK;
        switch (definition->ActionKind)
        {
            case ToyActionKind::SpellSelf:
            case ToyActionKind::SpellTarget:
                castResult = player->CastSpell(target, spellInfo, TRIGGERED_NONE);
                break;
            case ToyActionKind::ItemUse:
            {
                Item* item = player->GetItemByEntry(definition->ItemId);
                if (!item)
                    return "ITEM_REQUIRED";
                if (player->CanUseItem(item) != EQUIP_ERR_OK)
                    return "ITEM_UNUSABLE";
                SpellCastTargets targets;
                targets.SetUnitTarget(target);
                player->CastItemUseSpell(item, targets, 1, 0);
                break;
            }
            case ToyActionKind::CustomHandler:
            {
                auto handler = _customHandlers.find(definition->CustomHandler);
                if (handler == _customHandlers.end())
                    return "HANDLER_UNAVAILABLE";
                castResult = handler->second(player, *definition, target);
                break;
            }
        }
        if (castResult != SPELL_CAST_OK)
            return "CAST_FAILED";
        if (definition->CooldownScope == ToyCooldownScope::Account)
        {
            std::scoped_lock lock(_mutex);
            _accountCooldowns[account][collectionId] = now + definition->AccountCooldownMs;
        }
        LOG_INFO("module.solocollections.toy",
            "event=toy_action result=accepted account={} character={} collection={} item={} spell={} kind={} risks={}",
            account.Value(), player->GetGUID().GetCounter(), collectionId.Value(), definition->ItemId,
            definition->SpellId, static_cast<unsigned>(definition->ActionKind), definition->RiskFlags.size());
        return "ACCEPTED";
    }

private:
    using CustomHandler = std::function<SpellCastResult(Player*, ToyCollectionDefinition const&, Unit*)>;

    static void QueueGrant(AccountState& state, ToyCollectionDefinition const& definition, std::uint32_t characterGuid)
    {
        if (state.QueuedCollections.insert(definition.Id).second)
            state.Pending.push_back({ definition.Id, definition.ItemId, characterGuid });
    }

    void Advance(AccountId account, AccountState& state)
    {
        AccountCollectionStore& store = GetAccountCollectionStore();
        if (store.HasPendingMutation(account))
            return;
        while (!state.Pending.empty())
        {
            PendingGrant& grant = state.Pending.front();
            CollectionKey key { ToyCollectionTypeId, grant.Collection };
            if (GetAccountCollectionCache().IsOwned(account, key))
            {
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }
            AccountCollectionMutation mutation;
            mutation.Account = account;
            mutation.Generation = state.Generation;
            mutation.Key = key;
            mutation.Kind = CollectionMutationKind::Grant;
            mutation.SourceKind = CollectionSourceKind::Gameplay;
            mutation.SourceId = grant.ItemId;
            mutation.CharacterGuid = grant.CharacterGuid;
            MutationStartResult result = store.BeginMutation(mutation);
            if (result.Accepted || result.Reason == CollectionReasonCode::PendingOperation ||
                result.Reason == CollectionReasonCode::NotReady)
                return;
            state.QueuedCollections.erase(grant.Collection);
            state.Pending.pop_front();
        }
    }

    std::map<AccountId, AccountState> _accounts;
    std::map<AccountId, std::map<CollectionId, std::uint64_t>> _accountCooldowns;
    std::map<std::string, CustomHandler> _customHandlers;
    std::mutex _mutex;
};

ToyCollectionService::ToyCollectionService() : _impl(std::make_unique<Impl>()) { }
ToyCollectionService::~ToyCollectionService() = default;
void ToyCollectionService::OnPlayerLogin(Player* player) { _impl->OnPlayerLogin(player); }
void ToyCollectionService::OnItemAcquired(Player* player, std::uint32_t itemId) { _impl->OnItemAcquired(player, itemId); }
void ToyCollectionService::Update() { _impl->Update(); }
std::string ToyCollectionService::ExecuteUse(Player* player, CollectionId collectionId, bool currentTargetRequested)
{
    return _impl->ExecuteUse(player, collectionId, currentTargetRequested);
}

ToyCollectionService& GetToyCollectionService()
{
    static ToyCollectionService service;
    return service;
}
}
