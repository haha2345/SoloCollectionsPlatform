#include "SoloCollectionsProtocolScript.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsCompanionService.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsMountService.h"
#include "SoloCollectionsProtocolServer.h"
#include "SoloCollectionsProvider.h"
#include "SoloCollectionsSetCatalog.h"
#include "SoloCollectionsSetService.h"
#include "SoloCollectionsToyCatalog.h"
#include "SoloCollectionsToyService.h"
#include "SoloCollectionsTitleService.h"
#include "Transmogrification.h"

#include "Chat.h"
#include "Player.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <chrono>
#include <charconv>
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

std::string AppearanceApplyStatus(TransmogApplyResult const& result)
{
    switch (result.Code)
    {
        case LANG_TRANSMOG_OK: return "ACCEPTED";
        case LANG_TRANSMOG_NOT_ENOUGH_MONEY: return "NOT_ENOUGH_MONEY";
        case LANG_TRANSMOG_NOT_ENOUGH_TOKENS: return "NOT_ENOUGH_TOKENS";
        case LANG_TRANSMOG_INVALID_SLOT:
        case LANG_TRANSMOG_MISSING_DEST_ITEM: return "INVALID_TARGET_SLOT";
        case LANG_TRANSMOG_MISSING_SRC_ITEM: return "NOT_OWNED";
        case LANG_TRANSMOG_INVALID_ITEMS: return "CLASS_RESTRICTED";
        default: return "UNSUPPORTED";
    }
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
            CollectionProvider const* provider = providers.Find(category.TypeId);
            category.External = provider &&
                provider->Descriptor().Storage == CollectionStorageMode::External;
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
    GetSc2Server().SetExternalOwned(
        SessionId(player), TitleCollectionTypeId, GetTitleService().OwnedByPlayer(player));
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
    GetSc2Server().SetExternalOwned(
        SessionId(player), TitleCollectionTypeId, GetTitleService().OwnedByPlayer(player));
    (void)GetSc2Server().HandleInbound(SessionId(player), body, MonotonicMilliseconds(),
        [player](AccountId accountId, Sc2Message const& request)
        {
            if (!player->GetSession() || accountId.Value() != player->GetSession()->GetAccountId())
                return std::string("INVALID_REQUEST");
            if (request.TypeId == MountCollectionTypeId.Value())
            {
                if (request.ActionId != "SUMMON" || request.Target != "-")
                    return std::string("INVALID_REQUEST");
                return GetMountCollectionService().ExecuteSummon(player, CollectionId(request.CollectionId));
            }
            if (request.TypeId == CompanionCollectionTypeId.Value())
            {
                if (request.ActionId != "SUMMON" || request.Target != "-")
                    return std::string("INVALID_REQUEST");
                return GetCompanionCollectionService().ExecuteSummon(player, CollectionId(request.CollectionId));
            }
            if (request.TypeId == ToyCollectionTypeId.Value())
            {
                if (request.ActionId != "USE" || (request.Target != "-" && request.Target != "1"))
                    return std::string("INVALID_REQUEST");
                return GetToyCollectionService().ExecuteUse(
                    player, CollectionId(request.CollectionId), request.Target == "1");
            }
            if (request.TypeId == AppearanceCollectionTypeId.Value())
            {
                std::uint32_t encodedSlot = 0;
                auto parsed = std::from_chars(request.Target.data(),
                    request.Target.data() + request.Target.size(), encodedSlot);
                if (request.ActionId != "APPLY" || parsed.ec != std::errc {} ||
                    parsed.ptr != request.Target.data() + request.Target.size() ||
                    encodedSlot == 0 || encodedSlot > EQUIPMENT_SLOT_END)
                    return std::string("INVALID_TARGET_SLOT");
                TransmogApplyResult result = GetAppearanceService().TryApplyCanonicalAppearance(
                    player, CollectionId(request.CollectionId), static_cast<std::uint8_t>(encodedSlot - 1),
                    ObjectGuid::Empty, TransmogApplySource::Addon, false);
                return AppearanceApplyStatus(result);
            }
            if (request.TypeId == SetCollectionTypeId.Value())
            {
                std::uint32_t variantIndex = 0;
                if (request.Target != "-")
                {
                    auto parsed = std::from_chars(request.Target.data(),
                        request.Target.data() + request.Target.size(), variantIndex);
                    if (parsed.ec != std::errc {} ||
                        parsed.ptr != request.Target.data() + request.Target.size() || variantIndex == 0)
                        return std::string("INVALID_REQUEST");
                }
                if (request.ActionId != "APPLY")
                    return std::string("INVALID_REQUEST");
                TransmogApplyResult result = GetSetService().TryApply(
                    player, CollectionId(request.CollectionId), variantIndex,
                    ObjectGuid::Empty, TransmogApplySource::Addon);
                return AppearanceApplyStatus(result);
            }
            return std::string("INVALID_REQUEST");
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
