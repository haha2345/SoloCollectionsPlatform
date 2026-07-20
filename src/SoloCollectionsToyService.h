#ifndef SOLO_COLLECTIONS_TOY_SERVICE_H
#define SOLO_COLLECTIONS_TOY_SERVICE_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <memory>
#include <string>

class Player;

namespace SoloCollections
{
class ToyCollectionService final
{
public:
    ToyCollectionService();
    ~ToyCollectionService();

    ToyCollectionService(ToyCollectionService const&) = delete;
    ToyCollectionService& operator=(ToyCollectionService const&) = delete;

    void OnPlayerLogin(Player* player);
    void OnItemAcquired(Player* player, std::uint32_t itemId);
    void Update();
    [[nodiscard]] std::string ExecuteUse(Player* player, CollectionId collectionId, bool currentTargetRequested);

private:
    class Impl;
    std::unique_ptr<Impl> _impl;
};

ToyCollectionService& GetToyCollectionService();
}

#endif
