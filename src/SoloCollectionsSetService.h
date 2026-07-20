#ifndef SOLO_COLLECTIONS_SET_SERVICE_H
#define SOLO_COLLECTIONS_SET_SERVICE_H

#include "SoloCollectionsTypes.h"

#include "ObjectGuid.h"

#include <cstdint>

class Player;
enum class TransmogApplySource : std::uint8_t;
struct TransmogApplyResult;

namespace SoloCollections
{
class SetService final
{
public:
    [[nodiscard]] TransmogApplyResult TryApply(Player* player, CollectionId collectionId,
        std::uint32_t variantIndex, ObjectGuid interactionGuid, TransmogApplySource source) const;
};

SetService const& GetSetService();
}

#endif
