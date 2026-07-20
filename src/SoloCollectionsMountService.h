#ifndef SOLO_COLLECTIONS_MOUNT_SERVICE_H
#define SOLO_COLLECTIONS_MOUNT_SERVICE_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <memory>

class Player;

namespace SoloCollections
{
class MountCollectionService final
{
public:
    MountCollectionService();
    ~MountCollectionService();

    MountCollectionService(MountCollectionService const&) = delete;
    MountCollectionService& operator=(MountCollectionService const&) = delete;

    void OnPlayerLogin(Player* player);
    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId);
    void OnPlayerUpdate(Player* player);

private:
    class Impl;
    std::unique_ptr<Impl> _impl;
};

MountCollectionService& GetMountCollectionService();
}

#endif
