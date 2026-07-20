#include "Categories/Appearance/SoloCollectionsAppearanceService.h"

#include "Categories/Appearance/SoloCollectionsAppearanceCatalog.h"
#include "SoloCollectionsAccountService.h"
#include "SoloCollectionsProvider.h"
#include "Transmogrification.h"

#include "DatabaseEnv.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QueryResult.h"

namespace SoloCollections
{
namespace
{
constexpr std::uint32_t AppearanceMigrationId = 3;
constexpr std::uint16_t AppearanceMigrationVersion = 1;

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
    std::scoped_lock lock(_mutex);
    MigrationState& state = _migrations[AccountId(player->GetSession()->GetAccountId())];
    state.LoginCharacterGuid = player->GetGUID().GetCounter();
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
            LOG_INFO("module.solocollections.appearance",
                "event=migration_dry_run account={} legacy={} valid={} canonical={} merged={} unknown={} disabled={} missing={} conflicts={}",
                accountId.Value(), current.Report.LegacySources, current.Report.ValidSources,
                current.Report.CanonicalGroups, current.Report.MergedSources, current.Report.UnknownSources,
                current.Report.DisabledSources, current.Report.MissingTemplates, current.Report.Conflicts);
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
            LOG_ERROR("module.solocollections.appearance",
                "event=migration_reconcile account={} expected={} missing={} result=failed",
                accountId.Value(), state.ExpectedCanonicalGroups.size(), missingCanonicalGroups);
            return;
        }

        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        LOG_INFO("module.solocollections.appearance",
            "event=migration_reconcile account={} expected={} missing=0 result=success",
            accountId.Value(), state.ExpectedCanonicalGroups.size());
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
                LOG_INFO("module.solocollections.appearance",
                    "event=migration_marker account={} result={}", accountId.Value(), committed ? "success" : "failed");
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
        LOG_ERROR("module.solocollections.appearance",
            "event=legacy_load result=failed previous_accounts={}", _legacyCollections.size());
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
    LOG_INFO("module.solocollections.appearance",
        "event=legacy_load result=ready accounts={}", _legacyCollections.size());
    return true;
}

bool AppearanceService::TryUnlockLegacy(AccountId accountId, std::uint32_t sourceItemId)
{
    if (!accountId.IsValid() || sourceItemId == 0)
        return false;

    {
        std::scoped_lock lock(_mutex);
        if (_health != AppearanceRepositoryHealth::Healthy ||
            !_legacyCollections[accountId.Value()].insert(sourceItemId).second)
            return false;
    }

    CharacterDatabase.Execute(
        "INSERT IGNORE INTO custom_unlocked_appearances (account_id, item_template_id) VALUES ({}, {})",
        accountId.Value(), sourceItemId);
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
            if (sTransmogrification->CanTransmogrifyItemWithItem(player, targetTemplate, sourceTemplate))
                return sourceItemId;
    return std::nullopt;
}

TransmogApplyResult AppearanceService::TryApplyCollectedAppearance(Player* player,
    std::uint32_t sourceItemEntry, std::uint8_t slot, ObjectGuid interactionGuid,
    TransmogApplySource source, bool noCost)
{
    return sTransmogrification->TryApplyCollectedAppearance(
        player, sourceItemEntry, slot, interactionGuid, source, noCost);
}

TransmogApplyResult AppearanceService::TryApplyCollectedPreset(Player* player,
    std::map<std::uint8_t, std::uint32_t> const& appearances, ObjectGuid interactionGuid)
{
#ifdef PRESETS
    return sTransmogrification->TryApplyCollectedPreset(player, appearances, interactionGuid);
#else
    (void)player;
    (void)appearances;
    (void)interactionGuid;
    return { LANG_TRANSMOG_INVALID_SRC_ENTRY };
#endif
}

TransmogApplyResult AppearanceService::TryApplyCanonicalAppearance(Player* player,
    CollectionId appearanceId, std::uint8_t slot, ObjectGuid interactionGuid,
    TransmogApplySource source, bool noCost)
{
    std::optional<std::uint32_t> sourceItemId = ResolveOwnedSource(player, appearanceId, slot);
    if (!sourceItemId)
        return { LANG_TRANSMOG_MISSING_SRC_ITEM };
    return sTransmogrification->TryApplyCollectedAppearance(
        player, *sourceItemId, slot, interactionGuid, source, noCost);
}

AppearanceService& GetAppearanceService()
{
    static AppearanceService service;
    return service;
}
}
