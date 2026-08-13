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
        if (!definition.Id.IsValid() || definition.Key.empty() || definition.CanonicalSpellId == 0 ||
            definition.UnlockSpellIds.empty() || definition.PreviewCreatureEntry == 0 ||
            !_byCollection.emplace(definition.Id, index).second)
            throw std::runtime_error("invalid or duplicate SoloCollections companion catalog entry");
        if ((definition.Actionable && !definition.JournalVisible) ||
            (definition.RandomEligible && (!definition.JournalVisible || !definition.Actionable)) ||
            (definition.Actionable && definition.CanonicalActionSpellId != definition.CanonicalSpellId) ||
            (!definition.Actionable && definition.CanonicalActionSpellId != 0))
            throw std::runtime_error("invalid generated companion journal/action contract");

        bool hasCanonical = false;
        for (std::uint32_t spellId : definition.UnlockSpellIds)
        {
            if (spellId == 0 || !_bySpell.emplace(spellId, index).second)
                throw std::runtime_error("invalid or duplicate SoloCollections companion unlock spell");
            hasCanonical = hasCanonical || spellId == definition.CanonicalSpellId;
        }
        if (!hasCanonical)
            throw std::runtime_error("SoloCollections companion canonical spell is not an unlock variant");
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
