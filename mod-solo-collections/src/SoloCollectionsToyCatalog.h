#ifndef SOLO_COLLECTIONS_TOY_CATALOG_H
#define SOLO_COLLECTIONS_TOY_CATALOG_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace SoloCollections
{
inline constexpr CollectionTypeId ToyCollectionTypeId { std::uint16_t { 12 } };

enum class ToyActionKind : std::uint8_t
{
    SpellSelf = 1,
    SpellTarget = 2,
    ItemUse = 3,
    CustomHandler = 4,
};

enum class ToyTargetPolicy : std::uint8_t
{
    None = 1,
    Self = 2,
    OptionalUnit = 3,
    RequiredUnit = 4,
};

enum class ToyCooldownScope : std::uint8_t
{
    None = 1,
    Character = 2,
    Account = 3,
    HandlerNative = 4,
};

enum class ToyReplayPolicy : std::uint8_t
{
    RejectDuplicate = 1,
    Idempotent = 2,
};

enum class ToyCatalogLifecycle : std::uint8_t
{
    Active = 1,
    PreviewOnly = 2,
    Disabled = 3,
    Tombstone = 4,
};

inline bool IsCompiledToyCustomHandler(std::string_view key)
{
    return key == "unusual_compass";
}

struct ToyCollectionDefinition
{
    CollectionId Id;
    std::string Key;
    std::uint32_t ItemId = 0;
    ToyActionKind ActionKind = ToyActionKind::SpellSelf;
    std::uint32_t SpellId = 0;
    ToyTargetPolicy TargetPolicy = ToyTargetPolicy::Self;
    ToyCooldownScope CooldownScope = ToyCooldownScope::Character;
    std::uint32_t AccountCooldownMs = 0;
    bool AllowInCombat = false;
    bool ConsumesMaterial = false;
    std::string CustomHandler;
    ToyReplayPolicy ReplayPolicy = ToyReplayPolicy::RejectDuplicate;
    std::vector<std::string> RiskFlags;
    ToyCatalogLifecycle Lifecycle = ToyCatalogLifecycle::Active;
};

class ToyCatalog final
{
public:
    explicit ToyCatalog(std::vector<ToyCollectionDefinition> collections);

    [[nodiscard]] ToyCollectionDefinition const* Find(CollectionId collectionId) const;
    [[nodiscard]] ToyCollectionDefinition const* FindByItem(std::uint32_t itemId) const;
    [[nodiscard]] std::vector<ToyCollectionDefinition> const& Collections() const { return _collections; }

private:
    std::vector<ToyCollectionDefinition> _collections;
    std::map<CollectionId, std::size_t> _byCollection;
    std::map<std::uint32_t, std::size_t> _byItem;
};

ToyCatalog const& GetToyCatalog();
}

#endif
