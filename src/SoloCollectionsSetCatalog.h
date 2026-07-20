#ifndef SOLO_COLLECTIONS_SET_CATALOG_H
#define SOLO_COLLECTIONS_SET_CATALOG_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace SoloCollections
{
inline constexpr CollectionTypeId SetCollectionTypeId { std::uint16_t { 14 } };
inline constexpr CollectionTypeId SetAppearanceDependencyTypeId { std::uint16_t { 13 } };

struct SetMemberDefinition
{
    std::string Key;
    std::string SlotKey;
    bool Required = true;
    bool Enabled = true;
    std::vector<CollectionId> AppearanceAlternatives;
    std::vector<std::uint32_t> SourceItemIds;
};

struct SetVariantDefinition
{
    std::string Key;
    bool Enabled = true;
    std::vector<SetMemberDefinition> Members;
};

struct SetCollectionDefinition
{
    CollectionId Id;
    std::string Key;
    std::uint32_t ItemSetId = 0;
    std::string ClassToken;
    std::vector<SetVariantDefinition> Variants;
};

struct SetVariantProgress
{
    std::uint32_t OwnedRequired = 0;
    std::uint32_t Required = 0;
    bool Complete = false;
};

class SetCatalog final
{
public:
    explicit SetCatalog(std::vector<SetCollectionDefinition> collections);

    [[nodiscard]] SetCollectionDefinition const* Find(CollectionId collectionId) const;
    [[nodiscard]] SetVariantProgress Progress(AccountId accountId, CollectionId collectionId) const;
    [[nodiscard]] bool IsComplete(AccountId accountId, CollectionId collectionId) const;
    [[nodiscard]] std::vector<CollectionId> CompletedByAccount(AccountId accountId) const;
    [[nodiscard]] std::vector<SetCollectionDefinition> const& Collections() const { return _collections; }

private:
    [[nodiscard]] static SetVariantProgress ProgressVariant(AccountId accountId,
        SetVariantDefinition const& variant);

    std::vector<SetCollectionDefinition> _collections;
    std::map<CollectionId, std::size_t> _byCollection;
};

SetCatalog const& GetSetCatalog();
}

#endif
