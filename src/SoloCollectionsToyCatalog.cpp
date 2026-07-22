#include "SoloCollectionsToyCatalog.h"

#include <stdexcept>
#include <utility>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsToyCatalog.inc"
}

ToyCatalog::ToyCatalog(std::vector<ToyCollectionDefinition> collections) : _collections(std::move(collections))
{
    for (std::size_t index = 0; index < _collections.size(); ++index)
    {
        ToyCollectionDefinition const& definition = _collections[index];
        bool customValid = definition.ActionKind == ToyActionKind::CustomHandler ?
            IsCompiledToyCustomHandler(definition.CustomHandler) : definition.CustomHandler.empty();
        bool cooldownValid = definition.CooldownScope != ToyCooldownScope::Account || definition.AccountCooldownMs > 0;
        bool targetValid = definition.ActionKind == ToyActionKind::SpellTarget ?
            definition.TargetPolicy == ToyTargetPolicy::OptionalUnit || definition.TargetPolicy == ToyTargetPolicy::RequiredUnit :
            definition.ActionKind != ToyActionKind::SpellSelf ||
                definition.TargetPolicy == ToyTargetPolicy::None || definition.TargetPolicy == ToyTargetPolicy::Self;
        if (!definition.Id.IsValid() || definition.Key.empty() || definition.ItemId == 0 || definition.SpellId == 0 ||
            !customValid || !cooldownValid || !targetValid || definition.ConsumesMaterial ||
            !_byCollection.emplace(definition.Id, index).second ||
            !_byItem.emplace(definition.ItemId, index).second)
            throw std::runtime_error("invalid or duplicate SoloCollections toy catalog entry");
    }
}

ToyCollectionDefinition const* ToyCatalog::Find(CollectionId collectionId) const
{
    auto found = _byCollection.find(collectionId);
    return found == _byCollection.end() ? nullptr : &_collections[found->second];
}

ToyCollectionDefinition const* ToyCatalog::FindByItem(std::uint32_t itemId) const
{
    auto found = _byItem.find(itemId);
    return found == _byItem.end() ? nullptr : &_collections[found->second];
}

ToyCatalog const& GetToyCatalog()
{
    static ToyCatalog catalog(LoadGeneratedToyCollections());
    return catalog;
}
}
