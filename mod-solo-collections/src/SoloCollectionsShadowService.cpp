#include "SoloCollectionsShadowService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountService.h"
#include "SoloCollectionsBackend.h"
#include "SoloCollectionsShadowComparison.h"

#include "Log.h"
#include "Player.h"
#include "WorldSession.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsLegacyShadowCatalog.inc"

std::mutex ShadowMutex;
std::set<AccountSessionId> PendingSessions;

std::string JsonEscape(std::string_view value)
{
    std::string result;
    result.reserve(value.size() + 8);
    for (char character : value)
    {
        switch (character)
        {
            case '\\': result += "\\\\"; break;
            case '"': result += "\\\""; break;
            case '\n': result += "\\n"; break;
            case '\r': result += "\\r"; break;
            case '\t': result += "\\t"; break;
            default: result += character; break;
        }
    }
    return result;
}

void AppendKeys(std::ostringstream& output, std::vector<CollectionKey> const& keys)
{
    output << '[';
    for (std::size_t index = 0; index < keys.size(); ++index)
    {
        if (index)
            output << ',';
        output << "{\"type\":" << keys[index].TypeId.Value()
               << ",\"id\":" << keys[index].Id.Value() << '}';
    }
    output << ']';
}

std::string RenderJsonLine(AccountId accountId, std::uint32_t characterGuid,
    ShadowComparisonReport const& report)
{
    std::ostringstream output;
    output << "{\"event\":\"shadow_compare\",\"mode\":\"Compare\""
           << ",\"account\":" << accountId.Value()
           << ",\"character\":" << characterGuid
           << ",\"legacySourceHash\":\"" << JsonEscape(GeneratedLegacySc1SourceHash) << '"'
           << ",\"legacyMappingHash\":\"" << JsonEscape(GeneratedLegacySc1MappingHash) << '"'
           << ",\"canonicalMappingHash\":\"" << JsonEscape(GeneratedCanonicalMappingHash) << '"'
           << ",\"legacyEntries\":" << report.LegacyEntryCount
           << ",\"mappedEntries\":" << report.MappedEntryCount
           << ",\"unmappedEntries\":" << report.UnmappedEntryCount
           << ",\"legacyOwned\":" << report.LegacyOwnedCount
           << ",\"canonicalOwned\":" << report.CanonicalOwnedCount
           << ",\"categoryHashMismatches\":" << report.CategoryHashMismatchCount
           << ",\"catalogMismatches\":" << report.CatalogMismatchCount
           << ",\"ownedMismatches\":" << report.OwnedMismatchCount
           << ",\"availabilityMismatches\":" << report.AvailabilityMismatchCount
           << ",\"exactMatch\":" << (report.ExactMatch() ? "true" : "false")
           << ",\"legacyOwnedIds\":";
    AppendKeys(output, report.LegacyOwnedIds);
    output << ",\"canonicalOwnedIds\":";
    AppendKeys(output, report.CanonicalOwnedIds);
    output << ",\"differences\":[";
    for (std::size_t index = 0; index < report.Differences.size(); ++index)
    {
        if (index)
            output << ',';
        ShadowDifference const& difference = report.Differences[index];
        output << "{\"type\":" << difference.TypeId.Value()
               << ",\"legacyId\":" << difference.LegacyId
               << ",\"canonicalId\":" << difference.CanonicalId.Value()
               << ",\"unmapped\":" << (difference.Unmapped ? "true" : "false")
               << ",\"catalog\":" << (difference.CatalogMismatch ? "true" : "false")
               << ",\"owned\":" << (difference.OwnedMismatch ? "true" : "false")
               << ",\"availability\":" << (difference.AvailabilityMismatch ? "true" : "false")
               << ",\"extraCanonicalOwned\":" << (difference.ExtraCanonicalOwned ? "true" : "false")
               << '}';
    }
    output << "]}";
    return output.str();
}

void ExportReport(std::string const& jsonLine)
{
    std::string const& path = GetShadowReportPath();
    if (path.empty())
        return;
    try
    {
        std::filesystem::path reportPath(path);
        std::filesystem::path parent = reportPath.parent_path();
        if (!parent.empty())
        {
            std::error_code error;
            std::filesystem::create_directories(parent, error);
            if (error)
            {
                LOG_ERROR("module.solocollections.shadow",
                    "event=shadow_report_export result=directory_failed path={} error={}",
                    path, error.message());
                return;
            }
        }
        std::ofstream output(path, std::ios::out | std::ios::app);
        if (!output)
        {
            LOG_ERROR("module.solocollections.shadow",
                "event=shadow_report_export result=open_failed path={}", path);
            return;
        }
        output << jsonLine << '\n';
        if (!output)
            LOG_ERROR("module.solocollections.shadow",
                "event=shadow_report_export result=write_failed path={}", path);
    }
    catch (...)
    {
        LOG_ERROR("module.solocollections.shadow",
            "event=shadow_report_export result=exception path={}", path);
    }
}

std::vector<ShadowObservedState> ObserveCanonical(AccountId accountId,
    std::vector<LegacyShadowCategoryDefinition> const& categories,
    std::vector<LegacyShadowEntryDefinition> const& legacy)
{
    std::map<CollectionKey, ShadowObservedState> observed;
    for (LegacyShadowCategoryDefinition const& category : categories)
    {
        std::optional<std::vector<CollectionId>> owned =
            GetAccountCollectionService().OwnedByType(accountId, category.TypeId);
        if (!owned)
            continue;
        for (CollectionId collectionId : *owned)
        {
            CollectionKey key { category.TypeId, collectionId };
            CollectionResult result = GetAccountCollectionService().Evaluate(accountId, key);
            observed[key] = { key, true, result.Availability.CatalogKnown, result.Availability.AssetReady };
        }
    }
    for (LegacyShadowEntryDefinition const& entry : legacy)
    {
        if (!entry.CanonicalId.IsValid())
            continue;
        CollectionKey key { entry.TypeId, entry.CanonicalId };
        if (observed.contains(key))
            continue;
        CollectionResult result = GetAccountCollectionService().Evaluate(accountId, key);
        observed[key] = { key, result.Availability.Owned,
            result.Availability.CatalogKnown, result.Availability.AssetReady };
    }
    std::vector<ShadowObservedState> values;
    values.reserve(observed.size());
    for (auto const& [key, value] : observed)
    {
        (void)key;
        values.push_back(value);
    }
    return values;
}
}

void ShadowComparisonOnPlayerLogin(Player* player)
{
    if (!IsShadowComparisonEnabled() || !player || !player->GetSession())
        return;
    std::scoped_lock lock(ShadowMutex);
    PendingSessions.insert(AccountSessionId(player->GetGUID().GetCounter()));
}

void ShadowComparisonOnPlayerLogout(Player* player)
{
    if (!player)
        return;
    std::scoped_lock lock(ShadowMutex);
    PendingSessions.erase(AccountSessionId(player->GetGUID().GetCounter()));
}

void ShadowComparisonOnPlayerUpdate(Player* player)
{
    if (!IsShadowComparisonEnabled() || !player || !player->GetSession())
        return;
    AccountSessionId sessionId(player->GetGUID().GetCounter());
    {
        std::scoped_lock lock(ShadowMutex);
        if (!PendingSessions.contains(sessionId))
            return;
    }

    AccountId accountId(player->GetSession()->GetAccountId());
    std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
    if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
        return;
    {
        std::scoped_lock lock(ShadowMutex);
        PendingSessions.erase(sessionId);
    }
    if (snapshot->State != AccountCacheLoadState::Ready)
    {
        LOG_ERROR("module.solocollections.shadow",
            "event=shadow_compare result=load_failed mode=Compare account={} character={} generation={}",
            accountId.Value(), player->GetGUID().GetCounter(), snapshot->Generation.Value());
        return;
    }

    std::vector<LegacyShadowCategoryDefinition> categories = LoadGeneratedLegacyShadowCategories();
    std::vector<LegacyShadowEntryDefinition> legacy = LoadGeneratedLegacyShadowEntries();
    ShadowComparisonReport report = CompareLegacyShadow(
        categories, legacy, ObserveCanonical(accountId, categories, legacy));
    LOG_INFO("module.solocollections.shadow",
        "event=shadow_compare result={} mode=Compare account={} character={} generation={} revision={} "
        "legacy_entries={} mapped_entries={} unmapped_entries={} legacy_owned={} canonical_owned={} "
        "hash_mismatches={} catalog_mismatches={} owned_mismatches={} availability_mismatches={} "
        "writes=0 actions=0 success_deltas=0 legacy_source_hash={} legacy_mapping_hash={} canonical_mapping_hash={}",
        report.ExactMatch() ? "match" : "difference", accountId.Value(), player->GetGUID().GetCounter(),
        snapshot->Generation.Value(), snapshot->Revision.Value(), report.LegacyEntryCount,
        report.MappedEntryCount, report.UnmappedEntryCount, report.LegacyOwnedCount,
        report.CanonicalOwnedCount, report.CategoryHashMismatchCount, report.CatalogMismatchCount,
        report.OwnedMismatchCount, report.AvailabilityMismatchCount, GeneratedLegacySc1SourceHash,
        GeneratedLegacySc1MappingHash, GeneratedCanonicalMappingHash);

    std::size_t logged = 0;
    for (ShadowDifference const& difference : report.Differences)
    {
        if (logged >= 64)
            break;

        ++logged;
        LOG_INFO("module.solocollections.shadow",
            "event=shadow_difference account={} character={} type={} legacy_id={} canonical_id={} "
            "unmapped={} catalog={} owned={} availability={} extra_canonical_owned={}",
            accountId.Value(), player->GetGUID().GetCounter(), difference.TypeId.Value(),
            difference.LegacyId, difference.CanonicalId.Value(), difference.Unmapped ? 1 : 0,
            difference.CatalogMismatch ? 1 : 0, difference.OwnedMismatch ? 1 : 0,
            difference.AvailabilityMismatch ? 1 : 0, difference.ExtraCanonicalOwned ? 1 : 0);
    }
    if (report.Differences.size() > logged)
        LOG_INFO("module.solocollections.shadow",
            "event=shadow_difference_truncated account={} character={} total={} logged={}",
            accountId.Value(), player->GetGUID().GetCounter(), report.Differences.size(), logged);
    ExportReport(RenderJsonLine(accountId, player->GetGUID().GetCounter(), report));
}
}
