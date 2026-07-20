#include "SoloCollectionsMountCatalog.h"

#include <stdexcept>
#include <utility>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsMountCatalog.inc"
}

MountCatalog::MountCatalog(std::vector<MountCollectionDefinition> collections)
    : _collections(std::move(collections))
{
    for (std::size_t index = 0; index < _collections.size(); ++index)
    {
        MountCollectionDefinition const& collection = _collections[index];
        if (!collection.Id.IsValid() || collection.Key.empty() || collection.CanonicalSpellId == 0 ||
            collection.CreatureIds.empty() || collection.UnlockSpellIds.empty() || collection.ActionVariants.empty())
            throw std::invalid_argument("invalid generated mount collection definition");
        if (!_byCollection.emplace(collection.Id, index).second)
            throw std::invalid_argument("duplicate generated mount collection ID");
        for (std::uint32_t spellId : collection.UnlockSpellIds)
            if (spellId == 0 || !_byUnlockSpell.emplace(spellId, index).second)
                throw std::invalid_argument("duplicate or invalid generated mount unlock spell");
    }
}

MountCollectionDefinition const* MountCatalog::Find(CollectionId collectionId) const
{
    auto found = _byCollection.find(collectionId);
    return found == _byCollection.end() ? nullptr : &_collections[found->second];
}

MountCollectionDefinition const* MountCatalog::FindByUnlockSpell(std::uint32_t spellId) const
{
    auto found = _byUnlockSpell.find(spellId);
    return found == _byUnlockSpell.end() ? nullptr : &_collections[found->second];
}

MountCatalog const& GetMountCatalog()
{
    static MountCatalog catalog(LoadGeneratedMountCollections());
    return catalog;
}
}
