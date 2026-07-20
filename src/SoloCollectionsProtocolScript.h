#ifndef SOLO_COLLECTIONS_PROTOCOL_SCRIPT_H
#define SOLO_COLLECTIONS_PROTOCOL_SCRIPT_H

#include <cstdint>
#include <string>

#include "SoloCollectionsProtocolServer.h"

class Player;

namespace SoloCollections
{
void Sc2ProtocolOpenSession(Player* player);
void Sc2ProtocolCloseSession(Player* player);
void Sc2ProtocolPumpAndSend(Player* player);
[[nodiscard]] Sc2ServerDiagnostics Sc2ProtocolDiagnostics();
[[nodiscard]] bool Sc2ProtocolCanUsePrivateChat(
    Player* player, std::uint32_t type, std::uint32_t language, std::string& message, Player* receiver);
}

void AddSC_solo_collections_protocol();

#endif
