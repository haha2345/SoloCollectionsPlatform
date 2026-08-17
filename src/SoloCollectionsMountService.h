#ifndef SOLO_COLLECTIONS_MOUNT_SERVICE_H
#define SOLO_COLLECTIONS_MOUNT_SERVICE_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <memory>
#include <string>

class Player;
class SpellInfo;

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
    void ReconcileCharacterMountActions(Player* player);
    void ReconcileNativeMountState(Player* player);
    void Update();
    [[nodiscard]] std::string ExecuteSummon(Player* player, CollectionId collectionId);
    [[nodiscard]] std::string ExecuteRandomSummon(Player* player);
    [[nodiscard]] bool CanUseFlyingMountAsGround(Player* player, SpellInfo const* spellInfo,
        std::uint32_t mapId, std::uint32_t zoneId, std::uint32_t areaId);
    [[nodiscard]] bool CanReplaceMount(Player* player, SpellInfo const* spellInfo);
    void FinalizeNativeMountCast(Player* player, SpellInfo const* spellInfo);

private:
    class Impl;
    std::unique_ptr<Impl> _impl;
};

MountCollectionService& GetMountCollectionService();
}

#endif
