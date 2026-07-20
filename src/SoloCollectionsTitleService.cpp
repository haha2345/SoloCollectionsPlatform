#include "SoloCollectionsTitleService.h"

#include "DBCStores.h"
#include "DBCStructure.h"
#include "Player.h"

namespace SoloCollections
{
namespace
{
CharTitlesEntry const* FindByCollectionId(CollectionId collectionId)
{
    if (!collectionId.IsValid())
        return nullptr;
    std::uint32_t bitIndex = collectionId.Value() - 1;
    for (std::uint32_t row = 0; row < sCharTitlesStore.GetNumRows(); ++row)
        if (CharTitlesEntry const* title = sCharTitlesStore.LookupEntry(row))
            if (title->bit_index == bitIndex)
                return title;
    return nullptr;
}
}

CollectionResult TitleService::Evaluate(CollectionId collectionId) const
{
    CollectionResult result;
    bool known = FindByCollectionId(collectionId) != nullptr;
    result.Availability.CatalogKnown = known;
    result.Availability.AssetReady = known;
    result.Reason = known ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
    return result;
}

std::vector<CollectionId> TitleService::OwnedByPlayer(Player const* player) const
{
    std::vector<CollectionId> owned;
    if (!player)
        return owned;
    for (std::uint32_t row = 0; row < sCharTitlesStore.GetNumRows(); ++row)
        if (CharTitlesEntry const* title = sCharTitlesStore.LookupEntry(row))
            if (player->HasTitle(title))
                owned.emplace_back(title->bit_index + 1);
    return owned;
}

TitleService const& GetTitleService()
{
    static TitleService const service;
    return service;
}
}
