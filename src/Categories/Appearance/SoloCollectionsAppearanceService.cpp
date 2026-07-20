#include "Categories/Appearance/SoloCollectionsAppearanceService.h"

#include "Transmogrification.h"

#include "DatabaseEnv.h"
#include "Log.h"
#include "QueryResult.h"

namespace SoloCollections
{
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
    std::scoped_lock lock(_mutex);
    auto account = _legacyCollections.find(accountId.Value());
    return account != _legacyCollections.end() && account->second.contains(sourceItemId);
}

std::unordered_set<std::uint32_t> AppearanceService::CollectedSources(AccountId accountId) const
{
    std::scoped_lock lock(_mutex);
    auto account = _legacyCollections.find(accountId.Value());
    return account == _legacyCollections.end() ? std::unordered_set<std::uint32_t> {} : account->second;
}

AppearanceRepositoryHealth AppearanceService::RepositoryHealth() const
{
    std::scoped_lock lock(_mutex);
    return _health;
}

CollectionResult AppearanceService::Evaluate(CollectionId appearanceId) const
{
    CollectionResult result;
    result.Reason = appearanceId.IsValid() ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
    result.Availability.CatalogKnown = appearanceId.IsValid();
    result.Availability.AssetReady = appearanceId.IsValid();
    return result;
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

AppearanceService& GetAppearanceService()
{
    static AppearanceService service;
    return service;
}
}
