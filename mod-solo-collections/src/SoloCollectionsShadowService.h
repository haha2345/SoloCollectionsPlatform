#ifndef SOLO_COLLECTIONS_SHADOW_SERVICE_H
#define SOLO_COLLECTIONS_SHADOW_SERVICE_H

class Player;

namespace SoloCollections
{
void ShadowComparisonOnPlayerLogin(Player* player);
void ShadowComparisonOnPlayerLogout(Player* player);
void ShadowComparisonOnPlayerUpdate(Player* player);
}

#endif
