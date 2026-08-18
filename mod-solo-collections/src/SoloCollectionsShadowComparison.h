#ifndef SOLO_COLLECTIONS_SHADOW_COMPARISON_H
#define SOLO_COLLECTIONS_SHADOW_COMPARISON_H

#include "SoloCollectionsAccountCache.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace SoloCollections
{
struct LegacyShadowCategoryDefinition
{
    CollectionTypeId TypeId;
    std::string TypeKey;
    std::string LegacyMappingHash;
    std::string CanonicalMappingHash;
    std::size_t LegacyEntryCount = 0;
    std::size_t MappedEntryCount = 0;
};

struct LegacyShadowEntryDefinition
{
    CollectionTypeId TypeId;
    std::uint32_t LegacyId = 0;
    CollectionId CanonicalId;
    bool LegacyOwned = false;
    bool LegacyCatalogKnown = false;
    bool LegacyAssetReady = false;
};

struct ShadowObservedState
{
    CollectionKey Key;
    bool Owned = false;
    bool CatalogKnown = false;
    bool AssetReady = false;
};

struct ShadowDifference
{
    CollectionTypeId TypeId;
    std::uint32_t LegacyId = 0;
    CollectionId CanonicalId;
    bool Unmapped = false;
    bool CatalogMismatch = false;
    bool OwnedMismatch = false;
    bool AvailabilityMismatch = false;
    bool ExtraCanonicalOwned = false;
};

struct ShadowComparisonReport
{
    std::size_t LegacyEntryCount = 0;
    std::size_t MappedEntryCount = 0;
    std::size_t UnmappedEntryCount = 0;
    std::size_t LegacyOwnedCount = 0;
    std::size_t CanonicalOwnedCount = 0;
    std::size_t CategoryHashMismatchCount = 0;
    std::size_t CatalogMismatchCount = 0;
    std::size_t OwnedMismatchCount = 0;
    std::size_t AvailabilityMismatchCount = 0;
    std::vector<CollectionKey> LegacyOwnedIds;
    std::vector<CollectionKey> CanonicalOwnedIds;
    std::vector<ShadowDifference> Differences;

    [[nodiscard]] bool ExactMatch() const noexcept;
};

[[nodiscard]] ShadowComparisonReport CompareLegacyShadow(
    std::vector<LegacyShadowCategoryDefinition> const& categories,
    std::vector<LegacyShadowEntryDefinition> const& legacy,
    std::vector<ShadowObservedState> const& canonical);
}

#endif
