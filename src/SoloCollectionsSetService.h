#ifndef SOLO_COLLECTIONS_SET_SERVICE_H
#define SOLO_COLLECTIONS_SET_SERVICE_H

#include "SoloCollectionsTypes.h"

#include "ObjectGuid.h"

#include <cstdint>
#include <functional>

class Player;
enum class TransmogApplySource : std::uint8_t;
struct TransmogApplyResult;

namespace SoloCollections
{
class SetService final
{
public:
    // Asynchronous: the completion runs on the world update thread after the
    // database commit resolves, or synchronously on validation failure.
    void TryApply(Player* player, CollectionId collectionId,
        std::uint32_t variantIndex, ObjectGuid interactionGuid, TransmogApplySource source,
        std::function<void(TransmogApplyResult)> completion) const;
};

SetService const& GetSetService();
}

#endif
