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
            collection.CreatureIds.empty() || collection.UnlockSpellIds.empty() || collection.ActionVariants.empty() ||
            collection.PreviewCreatureEntry == 0)
            throw std::invalid_argument("invalid generated mount collection definition");
        if ((collection.Actionable && !collection.JournalVisible) ||
            (collection.Draggable && !collection.Actionable) ||
            (collection.RandomEligible && (!collection.JournalVisible || !collection.Actionable)) ||
            ((collection.ExclusionReason == MountExclusionReason::None) != collection.JournalVisible) ||
            (collection.Draggable && collection.CanonicalActionSpellId != collection.CanonicalSpellId) ||
            (!collection.Draggable && collection.CanonicalActionSpellId != 0))
            throw std::invalid_argument("invalid generated mount journal/action contract");
        if (!_byCollection.emplace(collection.Id, index).second)
            throw std::invalid_argument("duplicate generated mount collection ID");
        for (std::uint32_t spellId : collection.UnlockSpellIds)
            if (spellId == 0 || !_byUnlockSpell.emplace(spellId, index).second)
                throw std::invalid_argument("duplicate or invalid generated mount unlock spell");
        if (collection.CanonicalActionSpellId != 0 &&
            !_byActionSpell.emplace(collection.CanonicalActionSpellId, index).second)
            throw std::invalid_argument("duplicate generated mount action spell");
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

MountCollectionDefinition const* MountCatalog::FindByActionSpell(std::uint32_t spellId) const
{
    auto found = _byActionSpell.find(spellId);
    return found == _byActionSpell.end() ? nullptr : &_collections[found->second];
}

MountCatalog const& GetMountCatalog()
{
    static MountCatalog catalog(LoadGeneratedMountCollections());
    return catalog;
}
}
