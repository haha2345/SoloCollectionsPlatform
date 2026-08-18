#include "SoloCollectionsSetCatalog.h"

#include "SoloCollectionsAccountCache.h"

#include <stdexcept>
#include <unordered_set>
#include <utility>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsSetCatalog.inc"
}

SetCatalog::SetCatalog(std::vector<SetCollectionDefinition> collections) : _collections(std::move(collections))
{
    for (std::size_t index = 0; index < _collections.size(); ++index)
    {
        SetCollectionDefinition const& definition = _collections[index];
        if (!definition.Id.IsValid() || definition.Key.empty() || definition.ItemSetId == 0 ||
            definition.ClassPolicy == SetClassPolicyMode::Unresolved || definition.Variants.empty() ||
            !_byCollection.emplace(definition.Id, index).second)
            throw std::runtime_error("invalid or duplicate SoloCollections set catalog entry");

        if ((definition.ClassPolicy == SetClassPolicyMode::AllowList) != !definition.AllowedClassKeys.empty())
            throw std::runtime_error("invalid SoloCollections set class policy");

        std::unordered_set<std::string> variantKeys;
        std::unordered_set<std::uint32_t> variantOrdinals;
        std::uint32_t activeDefaults = 0;
        for (SetVariantDefinition const& variant : definition.Variants)
        {
            if (variant.Key.empty() || variant.Ordinal == 0 || !variantKeys.emplace(variant.Key).second ||
                !variantOrdinals.emplace(variant.Ordinal).second)
                throw std::runtime_error("invalid or duplicate SoloCollections set variant");
            if (variant.Lifecycle == SetVariantLifecycle::Active && variant.IsDefault)
                ++activeDefaults;
            std::unordered_set<std::string> memberKeys;
            std::uint32_t required = 0;
            for (SetMemberDefinition const& member : variant.Members)
            {
                if (member.Key.empty() || member.SlotKey.empty() || member.AppearanceAlternatives.empty() ||
                    !memberKeys.emplace(member.Key).second)
                    throw std::runtime_error("invalid or duplicate SoloCollections set member");
                if (member.Required)
                    ++required;
            }
            if (variant.Lifecycle == SetVariantLifecycle::Active && required == 0)
                throw std::runtime_error("enabled SoloCollections set variant has no required members");
        }
        if (activeDefaults != 1)
            throw std::runtime_error("SoloCollections set needs exactly one active default variant");
    }
}

SetVariantDefinition const* SetCatalog::FindVariant(
    SetCollectionDefinition const& definition, std::uint32_t variantOrdinal) const
{
    for (SetVariantDefinition const& variant : definition.Variants)
        if (variant.Ordinal == variantOrdinal && variant.Lifecycle == SetVariantLifecycle::Active)
            return &variant;
    return nullptr;
}

SetVariantDefinition const* SetCatalog::DefaultVariant(SetCollectionDefinition const& definition) const
{
    for (SetVariantDefinition const& variant : definition.Variants)
        if (variant.IsDefault && variant.Lifecycle == SetVariantLifecycle::Active)
            return &variant;
    return nullptr;
}

SetCollectionDefinition const* SetCatalog::Find(CollectionId collectionId) const
{
    auto found = _byCollection.find(collectionId);
    return found == _byCollection.end() ? nullptr : &_collections[found->second];
}

SetVariantProgress SetCatalog::ProgressVariant(AccountId accountId, SetVariantDefinition const& variant)
{
    SetVariantProgress progress;
    if (variant.Lifecycle != SetVariantLifecycle::Active)
        return progress;

    for (SetMemberDefinition const& member : variant.Members)
    {
        if (!member.Required)
            continue;
        ++progress.Required;
        bool owned = false;
        for (CollectionId appearanceId : member.AppearanceAlternatives)
            if (GetAccountCollectionCache().IsOwned(accountId,
                    { SetAppearanceDependencyTypeId, appearanceId }))
            {
                owned = true;
                break;
            }
        if (owned)
            ++progress.OwnedRequired;
    }
    progress.Complete = progress.Required > 0 && progress.OwnedRequired == progress.Required;
    return progress;
}

SetVariantProgress SetCatalog::Progress(AccountId accountId, CollectionId collectionId) const
{
    SetCollectionDefinition const* definition = Find(collectionId);
    if (!definition)
        return {};
    SetVariantProgress best;
    for (SetVariantDefinition const& variant : definition->Variants)
    {
        SetVariantProgress current = ProgressVariant(accountId, variant);
        if (current.Complete)
            return current;
        if (current.Required > 0 && (best.Required == 0 ||
            current.OwnedRequired * best.Required > best.OwnedRequired * current.Required))
            best = current;
    }
    return best;
}

bool SetCatalog::IsComplete(AccountId accountId, CollectionId collectionId) const
{
    SetCollectionDefinition const* definition = Find(collectionId);
    if (!definition)
        return false;
    for (SetVariantDefinition const& variant : definition->Variants)
        if (ProgressVariant(accountId, variant).Complete)
            return true;
    return false;
}

std::vector<CollectionId> SetCatalog::CompletedByAccount(AccountId accountId) const
{
    std::vector<CollectionId> result;
    for (SetCollectionDefinition const& definition : _collections)
        if (IsComplete(accountId, definition.Id))
            result.push_back(definition.Id);
    return result;
}

SetCatalog const& GetSetCatalog()
{
    static SetCatalog catalog(LoadGeneratedSetCollections());
    return catalog;
}
}
