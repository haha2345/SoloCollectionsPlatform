#include "SoloCollectionsTitleService.h"

#include "DBCStores.h"
#include "DBCStructure.h"
#include "Player.h"

namespace SoloCollections
{
namespace
{
// The 3.3.5 client title APIs use CharTitlesEntry::ID as their catalog index.
// bit_index belongs only to the player's known-title bit mask and is not a collection ID.
CharTitlesEntry const* FindByCollectionId(CollectionId collectionId)
{
    if (!collectionId.IsValid())
        return nullptr;
    for (std::uint32_t row = 0; row < sCharTitlesStore.GetNumRows(); ++row)
        if (CharTitlesEntry const* title = sCharTitlesStore.LookupEntry(row))
            if (title->ID == collectionId.Value())
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
                owned.emplace_back(title->ID);
    return owned;
}

TitleService const& GetTitleService()
{
    static TitleService const service;
    return service;
}
}
