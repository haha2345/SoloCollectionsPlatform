#ifndef SOLO_COLLECTIONS_APPEARANCE_CATALOG_H
#define SOLO_COLLECTIONS_APPEARANCE_CATALOG_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace SoloCollections
{
struct AppearanceCollectionDefinition
{
    CollectionId Id;
    std::uint32_t DisplayId = 0;
    std::uint32_t SlotFamily = 0;
    std::uint32_t ItemClass = 0;
    std::uint32_t ItemSubclass = 0;
    std::uint32_t PrimarySourceItemId = 0;
    std::vector<std::uint32_t> SourceItemIds;
};

class AppearanceCatalog
{
public:
    AppearanceCatalog();

    [[nodiscard]] AppearanceCollectionDefinition const* Find(CollectionId id) const;
    [[nodiscard]] AppearanceCollectionDefinition const* FindBySource(std::uint32_t sourceItemId) const;
    [[nodiscard]] std::vector<AppearanceCollectionDefinition> const& Collections() const { return _collections; }

private:
    std::vector<AppearanceCollectionDefinition> _collections;
    std::unordered_map<std::uint32_t, std::size_t> _byId;
    std::unordered_map<std::uint32_t, std::size_t> _bySource;
};

AppearanceCatalog const& GetAppearanceCatalog();
}

#endif
