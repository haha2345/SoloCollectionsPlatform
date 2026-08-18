#ifndef SOLO_COLLECTIONS_CREATURE_PREVIEW_SERVICE_H
#define SOLO_COLLECTIONS_CREATURE_PREVIEW_SERVICE_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <string>

class Player;

namespace SoloCollections
{
struct CreaturePreviewResult
{
    std::string Status = "INVALID_REQUEST";
    std::uint32_t CreatureEntry = 0;
    bool QueryQueued = false;
};

class CreaturePreviewService final
{
public:
    [[nodiscard]] CreaturePreviewResult Execute(
        Player* player, CollectionTypeId typeId, CollectionId collectionId) const;
};

[[nodiscard]] bool IsCreaturePreviewEnabled();
CreaturePreviewService const& GetCreaturePreviewService();
}

#endif
