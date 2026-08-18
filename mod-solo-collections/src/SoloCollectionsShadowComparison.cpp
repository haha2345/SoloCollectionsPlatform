#include "SoloCollectionsShadowComparison.h"

#include <algorithm>
#include <map>
#include <set>

namespace SoloCollections
{
namespace
{
using OwnedSet = std::set<CollectionKey>;

void SortAndUnique(std::vector<CollectionKey>& values)
{
    std::sort(values.begin(), values.end());
    values.erase(std::unique(values.begin(), values.end()), values.end());
}
}

bool ShadowComparisonReport::ExactMatch() const noexcept
{
    return UnmappedEntryCount == 0 && CategoryHashMismatchCount == 0 &&
        CatalogMismatchCount == 0 && OwnedMismatchCount == 0 &&
        AvailabilityMismatchCount == 0 && Differences.empty();
}

ShadowComparisonReport CompareLegacyShadow(
    std::vector<LegacyShadowCategoryDefinition> const& categories,
    std::vector<LegacyShadowEntryDefinition> const& legacy,
    std::vector<ShadowObservedState> const& canonical)
{
    ShadowComparisonReport report;
    std::map<CollectionKey, ShadowObservedState> observedByKey;
    OwnedSet canonicalOwned;
    for (ShadowObservedState const& observed : canonical)
    {
        if (!observed.Key.TypeId.IsValid() || !observed.Key.Id.IsValid())
            continue;
        observedByKey[observed.Key] = observed;
        if (observed.Owned)
            canonicalOwned.insert(observed.Key);
    }
    report.CanonicalOwnedIds.assign(canonicalOwned.begin(), canonicalOwned.end());
    report.CanonicalOwnedCount = report.CanonicalOwnedIds.size();

    for (LegacyShadowCategoryDefinition const& category : categories)
        if (category.LegacyMappingHash != category.CanonicalMappingHash)
            ++report.CategoryHashMismatchCount;

    OwnedSet legacyOwned;
    OwnedSet mappedKeys;
    for (LegacyShadowEntryDefinition const& entry : legacy)
    {
        ++report.LegacyEntryCount;
        if (entry.LegacyOwned)
            ++report.LegacyOwnedCount;

        ShadowDifference difference;
        difference.TypeId = entry.TypeId;
        difference.LegacyId = entry.LegacyId;
        difference.CanonicalId = entry.CanonicalId;
        if (!entry.CanonicalId.IsValid())
        {
            difference.Unmapped = true;
            ++report.UnmappedEntryCount;
            report.Differences.push_back(difference);
            continue;
        }

        ++report.MappedEntryCount;
        CollectionKey key { entry.TypeId, entry.CanonicalId };
        mappedKeys.insert(key);
        if (entry.LegacyOwned)
            legacyOwned.insert(key);
        auto observed = observedByKey.find(key);
        bool catalogKnown = observed != observedByKey.end() && observed->second.CatalogKnown;
        bool owned = observed != observedByKey.end() && observed->second.Owned;
        bool assetReady = observed != observedByKey.end() && observed->second.AssetReady;
        difference.CatalogMismatch = entry.LegacyCatalogKnown != catalogKnown;
        difference.OwnedMismatch = entry.LegacyOwned != owned;
        difference.AvailabilityMismatch = entry.LegacyAssetReady != assetReady;
        if (difference.CatalogMismatch)
            ++report.CatalogMismatchCount;
        if (difference.OwnedMismatch)
            ++report.OwnedMismatchCount;
        if (difference.AvailabilityMismatch)
            ++report.AvailabilityMismatchCount;
        if (difference.CatalogMismatch || difference.OwnedMismatch || difference.AvailabilityMismatch)
            report.Differences.push_back(difference);
    }

    report.LegacyOwnedIds.assign(legacyOwned.begin(), legacyOwned.end());
    SortAndUnique(report.LegacyOwnedIds);
    for (CollectionKey const& key : canonicalOwned)
    {
        if (mappedKeys.contains(key))
            continue;
        ShadowDifference difference;
        difference.TypeId = key.TypeId;
        difference.CanonicalId = key.Id;
        difference.OwnedMismatch = true;
        difference.ExtraCanonicalOwned = true;
        ++report.OwnedMismatchCount;
        report.Differences.push_back(difference);
    }
    return report;
}
}
