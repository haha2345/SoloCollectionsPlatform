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

enum class SetClassPolicyMode : std::uint8_t
{
    Any = 0,
    AllowList = 1,
    Unresolved = 2,
};

enum class SetVariantLifecycle : std::uint8_t
{
    Active = 0,
    Disabled = 1,
    Deferred = 2,
};

struct SetMemberDefinition
{
    std::string Key;
    std::string SlotKey;
    bool Required = true;
    std::vector<CollectionId> AppearanceAlternatives;
    std::vector<std::uint32_t> SourceItemIds;
};

struct SetVariantDefinition
{
    std::string Key;
    std::uint32_t Ordinal = 0;
    bool IsDefault = false;
    SetVariantLifecycle Lifecycle = SetVariantLifecycle::Disabled;
    std::vector<SetMemberDefinition> Members;
};

struct SetCollectionDefinition
{
    CollectionId Id;
    std::string Key;
    std::uint32_t ItemSetId = 0;
    SetClassPolicyMode ClassPolicy = SetClassPolicyMode::Unresolved;
    std::vector<std::string> AllowedClassKeys;
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
    [[nodiscard]] SetVariantDefinition const* FindVariant(
        SetCollectionDefinition const& definition, std::uint32_t variantOrdinal) const;
    [[nodiscard]] SetVariantDefinition const* DefaultVariant(SetCollectionDefinition const& definition) const;
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
