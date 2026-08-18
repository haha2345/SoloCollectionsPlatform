#ifndef SOLO_COLLECTIONS_COMPANION_CATALOG_H
#define SOLO_COLLECTIONS_COMPANION_CATALOG_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace SoloCollections
{
inline constexpr CollectionTypeId CompanionCollectionTypeId { std::uint16_t { 11 } };
// Internal SC2 projection of account preferences; not a journal/navigation category.
inline constexpr CollectionTypeId CompanionFavoriteCollectionTypeId { std::uint16_t { 17 } };
inline constexpr CollectionId CompanionRandomActionCollectionId { std::uint32_t { 1 } };

struct CompanionCollectionDefinition
{
    CollectionId Id;
    std::string Key;
    std::uint32_t CanonicalSpellId = 0;
    std::vector<std::uint32_t> UnlockSpellIds;
    std::uint32_t PreviewCreatureEntry = 0;
    CatalogLifecycle Lifecycle = CatalogLifecycle::Disabled;
    bool JournalVisible = false;
    bool Actionable = false;
    bool RandomEligible = false;
    std::uint32_t CanonicalActionSpellId = 0;
};

class CompanionCatalog final
{
public:
    explicit CompanionCatalog(std::vector<CompanionCollectionDefinition> collections);

    [[nodiscard]] CompanionCollectionDefinition const* Find(CollectionId collectionId) const;
    [[nodiscard]] CompanionCollectionDefinition const* FindBySpell(std::uint32_t spellId) const;
    [[nodiscard]] std::vector<CompanionCollectionDefinition> const& Collections() const { return _collections; }

private:
    std::vector<CompanionCollectionDefinition> _collections;
    std::map<CollectionId, std::size_t> _byCollection;
    std::map<std::uint32_t, std::size_t> _bySpell;
};

CompanionCatalog const& GetCompanionCatalog();
}

#endif
