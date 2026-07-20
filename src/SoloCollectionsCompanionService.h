#ifndef SOLO_COLLECTIONS_COMPANION_SERVICE_H
#define SOLO_COLLECTIONS_COMPANION_SERVICE_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <memory>
#include <string>

class Player;

namespace SoloCollections
{
class CompanionCollectionService final
{
public:
    CompanionCollectionService();
    ~CompanionCollectionService();

    CompanionCollectionService(CompanionCollectionService const&) = delete;
    CompanionCollectionService& operator=(CompanionCollectionService const&) = delete;

    void OnPlayerLogin(Player* player);
    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId);
    void Update();
    [[nodiscard]] std::string ExecuteSummon(Player* player, CollectionId collectionId);

private:
    class Impl;
    std::unique_ptr<Impl> _impl;
};

CompanionCollectionService& GetCompanionCollectionService();
}

#endif
