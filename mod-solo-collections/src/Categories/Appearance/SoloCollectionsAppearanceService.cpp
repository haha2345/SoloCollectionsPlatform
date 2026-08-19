#include "Categories/Appearance/SoloCollectionsAppearanceService.h"

#include "Categories/Appearance/SoloCollectionsAppearanceCatalog.h"
#include "SoloCollectionsAccountService.h"
#include "SoloCollectionsProvider.h"
#include "Transmogrification.h"

#include "Bag.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QueryResult.h"

#include <algorithm>

namespace SoloCollections
{
namespace
{
constexpr std::uint32_t AppearanceMigrationId = 3;
constexpr std::uint16_t AppearanceMigrationVersion = 1;
constexpr std::uint32_t InventoryReconcileIntervalMs = 5000;

char const* UnlockTriggerName(AppearanceUnlockTrigger trigger)
{
    switch (trigger)
    {
        case AppearanceUnlockTrigger::Equipment: return "equipment";
        case AppearanceUnlockTrigger::Loot: return "loot";
        case AppearanceUnlockTrigger::Craft: return "craft";
        case AppearanceUnlockTrigger::QuestReward: return "quest_reward";
        case AppearanceUnlockTrigger::InventoryStore: return "inventory_store";
        case AppearanceUnlockTrigger::Vendor: return "vendor";
        case AppearanceUnlockTrigger::GroupRoll: return "group_roll";
        case AppearanceUnlockTrigger::HistoricalReconcile: return "historical_reconcile";
        case AppearanceUnlockTrigger::GameMaster: return "game_master";
    }
    return "unknown";
}

struct AnalyzedMigration
{
    AppearanceMigrationReport Report;
    std::vector<std::pair<CollectionId, std::uint32_t>> CanonicalSources;
};

AnalyzedMigration AnalyzeLegacySources(std::vector<std::uint32_t> const& sourceIds)
{
    AnalyzedMigration analyzed;
    analyzed.Report.Ready = true;
    analyzed.Report.LegacySources = static_cast<std::uint32_t>(sourceIds.size());
    std::map<CollectionId, std::uint32_t> canonical;
    CollectionProviderRuntimeState const* providerState =
        GetCollectionProviderRegistry().State(AppearanceCollectionTypeId);

    for (std::uint32_t sourceItemId : sourceIds)
    {
        if (!sObjectMgr->GetItemTemplate(sourceItemId))
        {
            ++analyzed.Report.MissingTemplates;
            continue;
        }
        AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().FindBySource(sourceItemId);
        if (!definition)
        {
            ++analyzed.Report.UnknownSources;
            continue;
        }
        if (!providerState || providerState->Mode != CollectionProviderMode::Enabled)
        {
            ++analyzed.Report.DisabledSources;
            continue;
        }
        ++analyzed.Report.ValidSources;
        canonical.emplace(definition->Id, sourceItemId);
    }

    analyzed.Report.CanonicalGroups = static_cast<std::uint32_t>(canonical.size());
    analyzed.Report.MergedSources = analyzed.Report.ValidSources - analyzed.Report.CanonicalGroups;
    analyzed.CanonicalSources.assign(canonical.begin(), canonical.end());
    return analyzed;
}
}

void AppearanceService::OnPlayerLogin(Player* player)
{
    if (!player || !player->GetSession())
        return;
    {
        std::scoped_lock lock(_mutex);
        MigrationState& state = _migrations[AccountId(player->GetSession()->GetAccountId())];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        _inventoryReconcileElapsed[player->GetGUID().GetCounter()] = 0;
    }
    ScanHistoricalInventory(player);
}

void AppearanceService::OnPlayerUpdate(Player* player, std::uint32_t diff)
{
    if (!player || !player->GetSession())
        return;
    bool shouldScan = false;
    {
        std::scoped_lock lock(_mutex);
        std::uint32_t& elapsed = _inventoryReconcileElapsed[player->GetGUID().GetCounter()];
        elapsed = diff >= InventoryReconcileIntervalMs - std::min(elapsed, InventoryReconcileIntervalMs) ?
            InventoryReconcileIntervalMs : elapsed + diff;
        if (elapsed >= InventoryReconcileIntervalMs)
        {
            elapsed = 0;
            shouldScan = true;
        }
    }
    if (shouldScan)
        ScanHistoricalInventory(player);
}

void AppearanceService::OnPlayerLogout(Player* player)
{
    if (!player)
        return;
    std::scoped_lock lock(_mutex);
    _inventoryReconcileElapsed.erase(player->GetGUID().GetCounter());
}

void AppearanceService::Update()
{
    std::scoped_lock lock(_mutex);
    for (auto& [accountId, state] : _migrations)
    {
        if (!GetAccountCollectionService().IsReady(accountId))
            continue;
        if (state.Phase == MigrationPhase::AwaitingReady)
            BeginMigrationCheck(accountId, state);
        if (state.Phase == MigrationPhase::Importing)
            AdvanceMigration(accountId, state);
    }
    AdvanceQueuedUnlocks();
    AdvanceNewClears();
    AdvanceNewFlags();
}

bool AppearanceService::ShouldMarkAppearanceNew(
    CollectionSourceKind sourceKind, AppearanceUnlockTrigger trigger)
{
    if (trigger == AppearanceUnlockTrigger::HistoricalReconcile)
        return false;
    return sourceKind == CollectionSourceKind::Gameplay ||
        sourceKind == CollectionSourceKind::GameMaster;
}

void AppearanceService::EnqueueNewFlagLocked(AccountId accountId, CollectionId appearanceId,
    std::uint32_t characterGuid, std::uint32_t actorAccountId, std::uint32_t actorGuid)
{
    if (!accountId.IsValid() || !appearanceId.IsValid())
        return;
    if (GetAccountCollectionService().Evaluate(
            accountId, { AppearanceNewCollectionTypeId, appearanceId }).IsSuccess())
        return;
    if (!_queuedNewFlagIds[accountId].insert(appearanceId).second)
        return;
    _pendingNewFlags[accountId].push_back({ appearanceId, characterGuid, actorAccountId, actorGuid });
}

void AppearanceService::QueueNewFlag(AccountId accountId, CollectionId appearanceId,
    std::uint32_t characterGuid, std::uint32_t actorAccountId, std::uint32_t actorGuid)
{
    std::scoped_lock lock(_mutex);
    EnqueueNewFlagLocked(accountId, appearanceId, characterGuid, actorAccountId, actorGuid);
}

void AppearanceService::QueueNewClear(AccountId accountId, CollectionId appearanceId)
{
    if (!accountId.IsValid() || !appearanceId.IsValid())
        return;
    std::scoped_lock lock(_mutex);
    _pendingNewClears[accountId].push_back(appearanceId);
}

void AppearanceService::AdvanceNewFlags()
{
    for (auto account = _pendingNewFlags.begin(); account != _pendingNewFlags.end();)
    {
        AccountId accountId = account->first;
        std::deque<PendingNewFlag>& queue = account->second;
        if (queue.empty())
        {
            _queuedNewFlagIds.erase(accountId);
            account = _pendingNewFlags.erase(account);
            continue;
        }
        if (!GetAccountCollectionService().IsReady(accountId) ||
            GetAccountCollectionStore().HasPendingMutation(accountId))
        {
            ++account;
            continue;
        }

        PendingNewFlag const& pending = queue.front();
        if (GetAccountCollectionService().Evaluate(
                accountId, { AppearanceNewCollectionTypeId, pending.Appearance }).IsSuccess())
        {
            _queuedNewFlagIds[accountId].erase(pending.Appearance);
            queue.pop_front();
            continue;
        }
        if (!GetAccountCollectionService().Evaluate(
                accountId, { AppearanceCollectionTypeId, pending.Appearance }).IsSuccess())
        {
            ++account;
            continue;
        }
        MutationStartResult started = GetAccountCollectionService().TryUnlock(accountId,
            { AppearanceNewCollectionTypeId, pending.Appearance }, CollectionSourceKind::System,
            0, pending.CharacterGuid, pending.ActorAccountId, pending.ActorGuid);
        if (started.Accepted || started.Reason == CollectionReasonCode::PendingOperation ||
            started.Reason == CollectionReasonCode::NotReady)
        {
            ++account;
            continue;
        }
        _queuedNewFlagIds[accountId].erase(pending.Appearance);
        queue.pop_front();
    }
}

void AppearanceService::AdvanceNewClears()
{
    for (auto account = _pendingNewClears.begin(); account != _pendingNewClears.end();)
    {
        AccountId accountId = account->first;
        std::deque<CollectionId>& queue = account->second;
        if (queue.empty())
        {
            account = _pendingNewClears.erase(account);
            continue;
        }
        if (!GetAccountCollectionService().IsReady(accountId) ||
            GetAccountCollectionStore().HasPendingMutation(accountId))
        {
            ++account;
            continue;
        }

        CollectionId appearanceId = queue.front();
        if (!GetAccountCollectionService().Evaluate(
                accountId, { AppearanceNewCollectionTypeId, appearanceId }).IsSuccess())
        {
            queue.pop_front();
            continue;
        }
        MutationStartResult started = GetAccountCollectionService().TryRevoke(accountId,
            { AppearanceNewCollectionTypeId, appearanceId }, CollectionSourceKind::System,
            0, 0, 0, 0);
        if (started.Accepted || started.Reason == CollectionReasonCode::PendingOperation ||
            started.Reason == CollectionReasonCode::NotReady)
        {
            ++account;
            continue;
        }
        queue.pop_front();
    }
}

AppearanceUnlockQueueResult AppearanceService::QueueCanonicalUnlock(AccountId accountId,
    std::uint32_t characterGuid, std::uint32_t sourceItemId, CollectionSourceKind sourceKind,
    AppearanceUnlockTrigger trigger, std::uint32_t actorAccountId, std::uint32_t actorGuid)
{
    AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().FindBySource(sourceItemId);
    if (!accountId.IsValid() || !definition)
        return AppearanceUnlockQueueResult::Rejected;
    if (GetAccountCollectionService().Evaluate(
            accountId, { AppearanceCollectionTypeId, definition->Id }).IsSuccess())
        return AppearanceUnlockQueueResult::AlreadyOwned;

    std::scoped_lock lock(_mutex);
    if (!_queuedAppearanceIds[accountId].insert(definition->Id).second)
        return AppearanceUnlockQueueResult::Queued;
    _pendingUnlocks[accountId].push_back({ definition->Id, sourceItemId, characterGuid,
        sourceKind, trigger, actorAccountId, actorGuid });
    return AppearanceUnlockQueueResult::Queued;
}

AppearanceUnlockQueueResult AppearanceService::OnItemAcquired(
    Player* player, Item* item, AppearanceUnlockTrigger trigger)
{
    if (!player || !player->GetSession() || !item)
        return AppearanceUnlockQueueResult::Rejected;
    ItemTemplate const* itemTemplate = item->GetTemplate();
    if (!itemTemplate || (itemTemplate->Class != ITEM_CLASS_ARMOR && itemTemplate->Class != ITEM_CLASS_WEAPON))
        return AppearanceUnlockQueueResult::Rejected;
    if (item->HasFlag(ITEM_FIELD_FLAGS, ITEM_FIELD_FLAG_REFUNDABLE) ||
        (item->HasFlag(ITEM_FIELD_FLAGS, ITEM_FIELD_FLAG_BOP_TRADEABLE) && !sTransmogrification->GetAllowTradeable()) ||
        (itemTemplate->Bonding != ItemBondingType::BIND_WHEN_PICKED_UP && !item->IsSoulBound()))
        return AppearanceUnlockQueueResult::DeferredByBindingPolicy;
    if (!sTransmogrification->GetTrackUnusableItems() &&
        !sTransmogrification->SuitableForTransmogrification(player, itemTemplate))
        return AppearanceUnlockQueueResult::Rejected;

    return QueueCanonicalUnlock(AccountId(player->GetSession()->GetAccountId()),
        player->GetGUID().GetCounter(), itemTemplate->ItemId, CollectionSourceKind::Gameplay, trigger);
}

AppearanceUnlockQueueResult AppearanceService::QueueGameMasterUnlock(AccountId accountId,
    std::uint32_t characterGuid, std::uint32_t sourceItemId,
    std::uint32_t actorAccountId, std::uint32_t actorGuid)
{
    if (!GetAccountCollectionService().IsReady(accountId))
        return AppearanceUnlockQueueResult::Rejected;
    return QueueCanonicalUnlock(accountId, characterGuid, sourceItemId,
        CollectionSourceKind::GameMaster, AppearanceUnlockTrigger::GameMaster,
        actorAccountId, actorGuid);
}

void AppearanceService::ScanHistoricalInventory(Player* player)
{
    if (!player || !player->GetSession() || !sTransmogrification->GetUseCollectionSystem())
        return;
    auto scan = [this, player](Item* item)
    {
        if (item)
            (void)OnItemAcquired(player, item, AppearanceUnlockTrigger::HistoricalReconcile);
    };
    for (std::uint8_t slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        scan(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
    for (std::uint8_t slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        scan(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
    for (std::uint8_t bagPos = INVENTORY_SLOT_BAG_START; bagPos < INVENTORY_SLOT_BAG_END; ++bagPos)
        if (Bag* bag = player->GetBagByPos(bagPos))
            for (std::uint32_t slot = 0; slot < bag->GetBagSize(); ++slot)
                scan(player->GetItemByPos(bagPos, slot));
    for (std::uint8_t slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
        scan(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
    for (std::uint8_t bagPos = BANK_SLOT_BAG_START; bagPos < BANK_SLOT_BAG_END; ++bagPos)
        if (Bag* bag = player->GetBagByPos(bagPos))
            for (std::uint32_t slot = 0; slot < bag->GetBagSize(); ++slot)
                scan(player->GetItemByPos(bagPos, slot));
}

void AppearanceService::AdvanceQueuedUnlocks()
{
    for (auto account = _pendingUnlocks.begin(); account != _pendingUnlocks.end();)
    {
        AccountId accountId = account->first;
        std::deque<PendingUnlock>& queue = account->second;
        if (queue.empty())
        {
            _queuedAppearanceIds.erase(accountId);
            account = _pendingUnlocks.erase(account);
            continue;
        }
        if (!GetAccountCollectionService().IsReady(accountId) ||
            GetAccountCollectionStore().HasPendingMutation(accountId))
        {
            ++account;
            continue;
        }

        PendingUnlock const& pending = queue.front();
        CollectionResult owned = GetAccountCollectionService().Evaluate(
            accountId, { AppearanceCollectionTypeId, pending.Appearance });
        if (owned.IsSuccess())
        {
            _queuedAppearanceIds[accountId].erase(pending.Appearance);
            queue.pop_front();
            continue;
        }
        MutationStartResult started = GetAccountCollectionService().TryUnlock(accountId,
            { AppearanceCollectionTypeId, pending.Appearance }, pending.SourceKind,
            pending.SourceItemId, pending.CharacterGuid, pending.ActorAccountId, pending.ActorGuid);
        if (started.Accepted)
        {
            if (ShouldMarkAppearanceNew(pending.SourceKind, pending.Trigger))
                EnqueueNewFlagLocked(accountId, pending.Appearance, pending.CharacterGuid,
                    pending.ActorAccountId, pending.ActorGuid);
            ++account;
            continue;
        }
        if (started.Reason == CollectionReasonCode::PendingOperation ||
            started.Reason == CollectionReasonCode::NotReady)
        {
            ++account;
            continue;
        }
        _queuedAppearanceIds[accountId].erase(pending.Appearance);
        queue.pop_front();
    }
}

void AppearanceService::BeginMigrationCheck(AccountId accountId, MigrationState& state)
{
    state.Phase = MigrationPhase::CheckingMarker;
    MigrationMarkerRequest request;
    request.Account = accountId;
    request.MigrationId = AppearanceMigrationId;
    request.MigrationVersion = AppearanceMigrationVersion;
    request.SourceKind = MigrationMarkerRequest::Source::LegacyAppearance;
    if (!GetAccountCollectionStore().CheckMigrationMarker(request,
        [this, accountId](bool succeeded, bool completed, std::vector<std::uint32_t> sourceIds)
        {
            std::scoped_lock callbackLock(_mutex);
            auto found = _migrations.find(accountId);
            if (found == _migrations.end())
                return;
            MigrationState& current = found->second;
            if (!succeeded)
            {
                current.Phase = MigrationPhase::Failed;
                return;
            }
            if (completed)
            {
                current.Phase = MigrationPhase::Complete;
                return;
            }

            AnalyzedMigration analyzed = AnalyzeLegacySources(sourceIds);
            current.Report = analyzed.Report;
            current.Pending.clear();
            current.ExpectedCanonicalGroups.clear();
            for (auto const& [appearanceId, sourceItemId] : analyzed.CanonicalSources)
            {
                current.Pending.push_back({ appearanceId, sourceItemId, false });
                current.ExpectedCanonicalGroups.push_back(appearanceId);
            }
            current.FailedCount = current.Report.UnknownSources + current.Report.DisabledSources +
                current.Report.MissingTemplates + current.Report.Conflicts;
            current.Phase = MigrationPhase::Importing;
        }))
        state.Phase = MigrationPhase::AwaitingReady;
}

void AppearanceService::AdvanceMigration(AccountId accountId, MigrationState& state)
{
    if (state.Pending.empty())
    {
        std::uint32_t missingCanonicalGroups = 0;
        for (CollectionId appearanceId : state.ExpectedCanonicalGroups)
            if (!GetAccountCollectionService().Evaluate(
                    accountId, { AppearanceCollectionTypeId, appearanceId }).IsSuccess())
                ++missingCanonicalGroups;
        if (missingCanonicalGroups != 0)
        {
            state.Report.Conflicts += missingCanonicalGroups;
            state.FailedCount += missingCanonicalGroups;
            state.Phase = MigrationPhase::Failed;
            return;
        }

        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        MigrationMarkerCompletion completion;
        completion.Account = accountId;
        completion.MigrationId = AppearanceMigrationId;
        completion.MigrationVersion = AppearanceMigrationVersion;
        completion.CompletedRevision = snapshot->Revision;
        completion.ImportedCount = state.ImportedCount;
        completion.RejectedCount = state.FailedCount;
        state.Phase = MigrationPhase::WritingMarker;
        if (!GetAccountCollectionStore().CompleteMigrationMarker(completion,
            [this, accountId](bool committed)
            {
                std::scoped_lock callbackLock(_mutex);
                auto found = _migrations.find(accountId);
                if (found != _migrations.end())
                    found->second.Phase = committed ? MigrationPhase::Complete : MigrationPhase::Failed;
            }))
            state.Phase = MigrationPhase::Importing;
        return;
    }

    PendingAppearance& pending = state.Pending.front();
    CollectionResult owned = GetAccountCollectionService().Evaluate(
        accountId, { AppearanceCollectionTypeId, pending.Appearance });
    if (owned.IsSuccess())
    {
        ++state.ImportedCount;
        state.Pending.pop_front();
        return;
    }
    if (GetAccountCollectionStore().HasPendingMutation(accountId))
        return;

    MutationStartResult started = GetAccountCollectionService().TryUnlock(
        accountId, { AppearanceCollectionTypeId, pending.Appearance }, CollectionSourceKind::Migration,
        pending.SourceItemId, state.LoginCharacterGuid);
    if (started.Accepted)
    {
        pending.Started = true;
        return;
    }
    if (started.Reason == CollectionReasonCode::AlreadyOwned)
    {
        ++state.ImportedCount;
        state.Pending.pop_front();
    }
    else if (started.Reason != CollectionReasonCode::PendingOperation &&
        started.Reason != CollectionReasonCode::NotReady)
    {
        ++state.FailedCount;
        state.Pending.pop_front();
    }
}

bool AppearanceService::LoadLegacyCollections()
{
    if (!sTransmogrification->GetUseCollectionSystem())
    {
        std::scoped_lock lock(_mutex);
        _legacyCollections.clear();
        _health = AppearanceRepositoryHealth::Disabled;
        return true;
    }

    QueryResult result = CharacterDatabase.Query(
        "SELECT 0 AS row_kind, 0 AS account_id, 0 AS item_template_id "
        "UNION ALL "
        "SELECT 1 AS row_kind, account_id, item_template_id FROM custom_unlocked_appearances");
    if (!result)
    {
        std::scoped_lock lock(_mutex);
        _health = AppearanceRepositoryHealth::QueryFailed;
        return false;
    }

    LegacyCollectionCache refreshed;
    do
    {
        Field* fields = result->Fetch();
        if (fields[0].Get<std::uint32_t>() == 0)
            continue;
        refreshed[fields[1].Get<std::uint32_t>()].insert(fields[2].Get<std::uint32_t>());
    } while (result->NextRow());

    std::scoped_lock lock(_mutex);
    _legacyCollections.swap(refreshed);
    _health = AppearanceRepositoryHealth::Healthy;
    return true;
}

bool AppearanceService::HasCollectedSource(AccountId accountId, std::uint32_t sourceItemId) const
{
    if (AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().FindBySource(sourceItemId))
    {
        CollectionResult result = GetAccountCollectionService().Evaluate(
            accountId, { AppearanceCollectionTypeId, definition->Id });
        if (result.IsSuccess())
            return true;
    }

    std::scoped_lock lock(_mutex);
    auto account = _legacyCollections.find(accountId.Value());
    return account != _legacyCollections.end() && account->second.contains(sourceItemId);
}

std::unordered_set<std::uint32_t> AppearanceService::CollectedSources(AccountId accountId) const
{
    std::unordered_set<std::uint32_t> sources;
    {
        std::scoped_lock lock(_mutex);
        auto account = _legacyCollections.find(accountId.Value());
        if (account != _legacyCollections.end())
            sources = account->second;
    }
    if (std::optional<std::vector<CollectionId>> owned =
            GetAccountCollectionService().OwnedByType(accountId, AppearanceCollectionTypeId))
        for (CollectionId appearanceId : *owned)
            if (AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().Find(appearanceId))
                sources.insert(definition->SourceItemIds.begin(), definition->SourceItemIds.end());
    return sources;
}

AppearanceRepositoryHealth AppearanceService::RepositoryHealth() const
{
    std::scoped_lock lock(_mutex);
    return _health;
}

AppearanceMigrationReport AppearanceService::BuildMigrationDryRun(AccountId accountId) const
{
    std::vector<std::uint32_t> sources;
    {
        std::scoped_lock lock(_mutex);
        if (_health != AppearanceRepositoryHealth::Healthy)
            return {};
        auto account = _legacyCollections.find(accountId.Value());
        if (account != _legacyCollections.end())
            sources.assign(account->second.begin(), account->second.end());
    }
    return AnalyzeLegacySources(sources).Report;
}

CollectionResult AppearanceService::Evaluate(CollectionId appearanceId) const
{
    CollectionResult result;
    bool known = GetAppearanceCatalog().Find(appearanceId) != nullptr;
    result.Reason = known ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
    result.Availability.CatalogKnown = known;
    result.Availability.AssetReady = known;
    return result;
}

std::optional<std::uint32_t> AppearanceService::ResolveOwnedSource(
    Player* player, CollectionId appearanceId, std::uint8_t slot) const
{
    if (!player || !player->GetSession() || slot >= EQUIPMENT_SLOT_END)
        return std::nullopt;
    AccountId accountId(player->GetSession()->GetAccountId());
    if (!GetAccountCollectionService().Evaluate(
            accountId, { AppearanceCollectionTypeId, appearanceId }).IsSuccess())
        return std::nullopt;
    AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().Find(appearanceId);
    Item* target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
    ItemTemplate const* targetTemplate = target ? target->GetTemplate() : nullptr;
    if (!definition || !targetTemplate)
        return std::nullopt;

    for (std::uint32_t sourceItemId : definition->SourceItemIds)
        if (ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(sourceItemId))
            if (sTransmogrification->CanTransmogrifyItemWithItem(player, targetTemplate, sourceTemplate)
                || sTransmogrification->CanApplyCollectedVisual(player, targetTemplate, sourceTemplate))
                return sourceItemId;
    return std::nullopt;
}

void AppearanceService::TryApplyCollectedAppearance(Player* player,
    std::uint32_t sourceItemEntry, std::uint8_t slot, ObjectGuid interactionGuid,
    TransmogApplySource source, bool noCost, ApplyCompletion completion)
{
    sTransmogrification->TryApplyCollectedAppearance(
        player, sourceItemEntry, slot, interactionGuid, source, noCost, std::move(completion));
}

void AppearanceService::TryApplyCollectedAppearances(Player* player,
    std::map<std::uint8_t, std::uint32_t> const& appearances, ObjectGuid interactionGuid,
    TransmogApplySource source, bool noCost, ApplyCompletion completion)
{
    sTransmogrification->TryApplyCollectedAppearances(
        player, appearances, interactionGuid, source, noCost, {}, std::move(completion));
}

void AppearanceService::TryApplyCanonicalAppearance(Player* player,
    CollectionId appearanceId, std::uint8_t slot, ObjectGuid interactionGuid,
    TransmogApplySource source, bool noCost, ApplyCompletion completion)
{
    TryApplyCanonicalAppearances(
        player, { { slot, appearanceId } }, interactionGuid, source, noCost, std::move(completion));
}

void AppearanceService::TryApplyCanonicalAppearances(Player* player,
    std::map<std::uint8_t, CollectionId> const& appearances, ObjectGuid interactionGuid,
    TransmogApplySource source, bool noCost, ApplyCompletion completion)
{
    std::map<std::uint8_t, std::uint32_t> resolved;
    for (auto const& [slot, appearanceId] : appearances)
    {
        std::optional<std::uint32_t> sourceItemId = ResolveOwnedSource(player, appearanceId, slot);
        if (!sourceItemId)
        {
            if (completion)
                completion({ LANG_TRANSMOG_MISSING_SRC_ITEM });
            return;
        }
        resolved.emplace(slot, *sourceItemId);
    }
    TryApplyCollectedAppearances(player, resolved, interactionGuid, source, noCost, std::move(completion));
}

AppearanceService& GetAppearanceService()
{
    static AppearanceService service;
    return service;
}
}
