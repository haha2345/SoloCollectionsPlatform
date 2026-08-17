#include "Categories/Appearance/SoloCollectionsAppearanceCatalog.h"

#include <stdexcept>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsAppearanceCatalog.inc"

std::vector<AppearanceCollectionDefinition> LoadGeneratedAppearanceCollections()
{
    std::vector<AppearanceCollectionDefinition> collections;
    collections.reserve(sizeof(GeneratedAppearanceGroups) / sizeof(GeneratedAppearanceGroups[0]));

    for (GeneratedAppearanceGroup const& generated : GeneratedAppearanceGroups)
    {
        std::uint32_t const* sourcesBegin = GeneratedAppearanceSources + generated.SourceOffset;
        collections.push_back({ CollectionId{generated.Id}, generated.DisplayId, generated.SlotFamily,
            generated.ItemClass, generated.ItemSubclass, generated.PrimarySourceItemId,
            { sourcesBegin, sourcesBegin + generated.SourceCount } });
    }

    return collections;
}
}

AppearanceCatalog::AppearanceCatalog() : _collections(LoadGeneratedAppearanceCollections())
{
    for (std::size_t index = 0; index < _collections.size(); ++index)
    {
        AppearanceCollectionDefinition const& definition = _collections[index];
        if (!definition.Id.IsValid() || definition.Id.Value() < 10 || definition.DisplayId == 0 ||
            definition.SlotFamily == 0 ||
            definition.PrimarySourceItemId == 0 || definition.SourceItemIds.empty() ||
            !_byId.emplace(definition.Id.Value(), index).second)
            throw std::runtime_error("Invalid or duplicate generated canonical appearance definition.");

        for (std::uint32_t sourceItemId : definition.SourceItemIds)
            if (sourceItemId == 0 || !_bySource.emplace(sourceItemId, index).second)
                throw std::runtime_error("Appearance source item is mapped to multiple canonical groups.");
    }
}

AppearanceCollectionDefinition const* AppearanceCatalog::Find(CollectionId id) const
{
    auto found = _byId.find(id.Value());
    return found == _byId.end() ? nullptr : &_collections[found->second];
}

AppearanceCollectionDefinition const* AppearanceCatalog::FindBySource(std::uint32_t sourceItemId) const
{
    auto found = _bySource.find(sourceItemId);
    return found == _bySource.end() ? nullptr : &_collections[found->second];
}

AppearanceCatalog const& GetAppearanceCatalog()
{
    static AppearanceCatalog catalog;
    return catalog;
}
}
