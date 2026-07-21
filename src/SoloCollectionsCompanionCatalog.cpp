#include "SoloCollectionsCompanionCatalog.h"

#include <stdexcept>
#include <utility>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsCompanionCatalog.inc"
}

CompanionCatalog::CompanionCatalog(std::vector<CompanionCollectionDefinition> collections)
    : _collections(std::move(collections))
{
    for (std::size_t index = 0; index < _collections.size(); ++index)
    {
        CompanionCollectionDefinition const& definition = _collections[index];
        if (!definition.Id.IsValid() || definition.Key.empty() || definition.SpellId == 0 || definition.CreatureId == 0 ||
            definition.PreviewCreatureEntry == 0 ||
            !_byCollection.emplace(definition.Id, index).second || !_bySpell.emplace(definition.SpellId, index).second)
            throw std::runtime_error("invalid or duplicate SoloCollections companion catalog entry");
    }
}

CompanionCollectionDefinition const* CompanionCatalog::Find(CollectionId collectionId) const
{
    auto found = _byCollection.find(collectionId);
    return found == _byCollection.end() ? nullptr : &_collections[found->second];
}

CompanionCollectionDefinition const* CompanionCatalog::FindBySpell(std::uint32_t spellId) const
{
    auto found = _bySpell.find(spellId);
    return found == _bySpell.end() ? nullptr : &_collections[found->second];
}

CompanionCatalog const& GetCompanionCatalog()
{
    static CompanionCatalog catalog(LoadGeneratedCompanionCollections());
    return catalog;
}
}
