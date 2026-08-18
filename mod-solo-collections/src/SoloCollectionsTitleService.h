#ifndef SOLO_COLLECTIONS_TITLE_SERVICE_H
#define SOLO_COLLECTIONS_TITLE_SERVICE_H

#include "SoloCollectionsTypes.h"

#include <vector>

class Player;

namespace SoloCollections
{
inline constexpr CollectionTypeId TitleCollectionTypeId { std::uint16_t { 15 } };

class TitleService final
{
public:
    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const;
    [[nodiscard]] std::vector<CollectionId> OwnedByPlayer(Player const* player) const;
};

[[nodiscard]] TitleService const& GetTitleService();
}

#endif
