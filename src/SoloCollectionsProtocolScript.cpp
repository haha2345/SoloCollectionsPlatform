#include "SoloCollectionsProtocolScript.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsMountService.h"
#include "SoloCollectionsProtocolServer.h"
#include "SoloCollectionsProvider.h"

#include "Chat.h"
#include "Player.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <chrono>
#include <string_view>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsProtocolCatalog.inc"

constexpr std::string_view BackendBuild = "phase5-dev";
constexpr std::string_view WirePrefix = "SC2\t";

std::uint64_t MonotonicMilliseconds()
{
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

AccountSessionId SessionId(Player* player)
{
    return AccountSessionId(player->GetGUID().GetCounter());
}

Sc2Server& GetSc2Server()
{
    static Sc2Server server = []
    {
        std::vector<Sc2CategoryDefinition> categories = LoadGeneratedSc2Categories();
        CollectionProviderRegistry& providers = GetCollectionProviderRegistry();
        for (Sc2CategoryDefinition& category : categories)
        {
            CollectionProviderRuntimeState const* state = providers.State(category.TypeId);
            category.Enabled = state && state->Mode != CollectionProviderMode::Disabled;
        }
        return Sc2Server(GetAccountCollectionCache(), std::string(GeneratedSc2MetadataVersion),
            std::string(GeneratedSc2AssetPackVersion), std::string(BackendBuild), std::move(categories));
    }();
    return server;
}

class Sc2AccountEventSink final : public AccountCollectionEventSink
{
public:
    void OnCollectionDeltaCommitted(AccountId accountId, CollectionDelta const& delta) override
    {
        GetSc2Server().OnCollectionDeltaCommitted(accountId, delta);
    }

    void OnCollectionMutationFailed(
        AccountId /*accountId*/, CollectionKey const& /*key*/, CollectionReasonCode /*reason*/) override
    {
        // Real action requests are intentionally disabled in phase 5, so there is
        // no pending SC2 request to correlate with a store-side failure yet.
    }

    bool OnAccountResyncRequested(AccountId accountId) override
    {
        return GetSc2Server().OnAccountResyncRequested(accountId);
    }
};

Sc2AccountEventSink& GetSc2EventSink()
{
    static Sc2AccountEventSink sink;
    return sink;
}
}

void Sc2ProtocolOpenSession(Player* player)
{
    if (!player || !player->GetSession())
        return;
    GetSc2Server().OpenSession(AccountId(player->GetSession()->GetAccountId()), SessionId(player));
}

void Sc2ProtocolCloseSession(Player* player)
{
    if (player)
        GetSc2Server().CloseSession(SessionId(player));
}

bool Sc2ProtocolCanUsePrivateChat(
    Player* player, std::uint32_t type, std::uint32_t language, std::string& message, Player* receiver)
{
    if (!player || !player->GetSession() || type != CHAT_MSG_WHISPER || language != LANG_ADDON ||
        receiver != player || !std::string_view(message).starts_with(WirePrefix))
        return true;

    std::string_view body(message.data() + WirePrefix.size(), message.size() - WirePrefix.size());
    (void)GetSc2Server().HandleInbound(SessionId(player), body, MonotonicMilliseconds(),
        [player](AccountId accountId, Sc2Message const& request)
        {
            if (!player->GetSession() || accountId.Value() != player->GetSession()->GetAccountId() ||
                request.TypeId != MountCollectionTypeId.Value() || request.ActionId != "SUMMON" || request.Target != "-")
                return std::string("INVALID_REQUEST");
            return GetMountCollectionService().ExecuteSummon(player, CollectionId(request.CollectionId));
        });
    return false;
}

void Sc2ProtocolPumpAndSend(Player* player)
{
    if (!player || !player->GetSession())
        return;
    AccountSessionId sessionId = SessionId(player);
    GetSc2Server().PumpSession(sessionId, MonotonicMilliseconds());
    for (std::string const& body : GetSc2Server().DrainOutbound(sessionId, Sc2Limits::MaxPacketsPerTick))
    {
        WorldPacket packet;
        ChatHandler::BuildChatPacket(packet, CHAT_MSG_WHISPER, LANG_ADDON, player, player,
            std::string(WirePrefix) + body);
        player->SendDirectMessage(&packet);
    }
}
}

void AddSC_solo_collections_protocol()
{
    SoloCollections::GetAccountCollectionStore().SetEventSink(&SoloCollections::GetSc2EventSink());
}
