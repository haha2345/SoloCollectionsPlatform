#include "SoloCollectionsProtocolScript.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsBackend.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsCompanionService.h"
#include "SoloCollectionsCreaturePreviewService.h"
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
#include "Log.h"
#include "Player.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <chrono>
#include <charconv>
#include <string_view>
#include <utility>

namespace SoloCollections
{
namespace
{
// Generated build identity; touching this include site makes build-info refreshes explicit to MSBuild.
#include "SoloCollectionsBuildInfo.inc"
#include "generated/SoloCollectionsProtocolCatalog.inc"

constexpr std::string_view BackendBuild = "0.2.0";
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
                (provider->Descriptor().Storage == CollectionStorageMode::External ||
                 provider->Descriptor().Storage == CollectionStorageMode::Derived);
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
        if (delta.Key.TypeId == SetAppearanceDependencyTypeId)
            GetSc2Server().OnDerivedOwnedChanged(accountId, SetCollectionTypeId,
                GetSetCatalog().CompletedByAccount(accountId), delta.Revision);
    }

    void OnCollectionMutationFailed(
        AccountId /*accountId*/, CollectionKey const& /*key*/, CollectionReasonCode /*reason*/) override
    {
        // Action requests return their immediate server result. No SC2
        // correlation token is retained for a later asynchronous store failure;
        // diagnostics and an explicit resync remain the recovery path.
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

std::uint32_t Sc2CatalogSchemaVersion()
{
    return GeneratedCatalogSchemaVersion;
}

std::string_view Sc2CatalogVersion()
{
    return GeneratedCatalogVersion;
}

std::string_view Sc2IdentityVersion()
{
    return GeneratedIdentityVersion;
}

std::string_view Sc2MetadataVersion()
{
    return GeneratedSc2MetadataVersion;
}

std::string_view Sc2AssetPackVersion()
{
    return GeneratedSc2AssetPackVersion;
}

void Sc2ProtocolOpenSession(Player* player)
{
    if (!IsCppBackendOwner() || !player || !player->GetSession())
        return;
    GetSc2Server().OpenSession(AccountId(player->GetSession()->GetAccountId()), SessionId(player));
    GetSc2Server().SetExternalOwned(
        SessionId(player), TitleCollectionTypeId, GetTitleService().OwnedByPlayer(player));
    GetSc2Server().SetExternalOwned(
        SessionId(player), SetCollectionTypeId, GetSetCatalog().CompletedByAccount(
            AccountId(player->GetSession()->GetAccountId())));
}

void Sc2ProtocolCloseSession(Player* player)
{
    if (IsCppBackendOwner() && player)
        GetSc2Server().CloseSession(SessionId(player));
}

bool Sc2ProtocolCanUsePrivateChat(
    Player* player, std::uint32_t type, std::uint32_t language, std::string& message, Player* receiver)
{
    if (!IsCppBackendOwner())
        return true;
    if (!player || !player->GetSession() || type != CHAT_MSG_WHISPER || language != LANG_ADDON ||
        receiver != player || !std::string_view(message).starts_with(WirePrefix))
        return true;

    std::string_view body(message.data() + WirePrefix.size(), message.size() - WirePrefix.size());
    Sc2DecodeResult decoded = DecodeSc2Body(body);
    if (!decoded.Success)
    {
        LOG_WARN("module.solocollections.protocol",
            "event=protocol_reject result=bad_message account={} character={} bytes={}",
            player->GetSession()->GetAccountId(), player->GetGUID().GetCounter(), body.size());
    }
    GetSc2Server().SetExternalOwned(
        SessionId(player), TitleCollectionTypeId, GetTitleService().OwnedByPlayer(player));
    GetSc2Server().SetExternalOwned(
        SessionId(player), SetCollectionTypeId, GetSetCatalog().CompletedByAccount(
            AccountId(player->GetSession()->GetAccountId())));
    (void)GetSc2Server().HandleInbound(SessionId(player), body, MonotonicMilliseconds(),
        [player](AccountId accountId, Sc2Message const& request)
        {
            auto actionStarted = std::chrono::steady_clock::now();
            auto finish = [&](std::string_view actionKind, std::string status, std::uint32_t entry = 0)
            {
                std::uint64_t elapsedMicroseconds = static_cast<std::uint64_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(
                        std::chrono::steady_clock::now() - actionStarted).count());
                LOG_INFO("module.solocollections.performance",
                    "event=action_timing account={} character={} type={} collection={} action={} entry={} status={} elapsed_us={}",
                    accountId.Value(), player->GetGUID().GetCounter(), request.TypeId,
                    request.CollectionId, actionKind, entry, status, elapsedMicroseconds);
                return status;
            };
            if (!player->GetSession() || accountId.Value() != player->GetSession()->GetAccountId())
                return finish("invalid", "INVALID_REQUEST");
            if (request.TypeId == MountCollectionTypeId.Value())
            {
                if (request.ActionId == "RANDOM_SUMMON")
                {
                    if (request.CollectionId != MountRandomActionCollectionId.Value() || request.Target != "-")
                        return finish("mount_random", "INVALID_REQUEST");
                    return finish("mount_random", GetMountCollectionService().ExecuteRandomSummon(player));
                }
                if (request.ActionId == "SET_FAVORITE")
                {
                    if (request.Target != "0" && request.Target != "1")
                        return finish("mount_favorite", "INVALID_REQUEST");
                    MountCollectionDefinition const* definition =
                        GetMountCatalog().Find(CollectionId(request.CollectionId));
                    if (!definition || definition->Lifecycle != CatalogLifecycle::Active ||
                        !definition->JournalVisible || !definition->Actionable)
                        return finish("mount_favorite", "UNSUPPORTED");

                    std::optional<AccountCacheSnapshot> snapshot =
                        GetAccountCollectionCache().Snapshot(accountId);
                    if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
                        return finish("mount_favorite", "LOADING");
                    CollectionKey mountKey { MountCollectionTypeId, CollectionId(request.CollectionId) };
                    if (!GetAccountCollectionCache().IsOwned(accountId, mountKey))
                        return finish("mount_favorite", "FAVORITE_NOT_OWNED");

                    AccountCollectionMutation mutation;
                    mutation.Account = accountId;
                    mutation.Generation = snapshot->Generation;
                    mutation.Key = { MountFavoriteCollectionTypeId, CollectionId(request.CollectionId) };
                    mutation.Kind = request.Target == "1" ?
                        CollectionMutationKind::Grant : CollectionMutationKind::Revoke;
                    mutation.SourceKind = CollectionSourceKind::Gameplay;
                    mutation.CharacterGuid = player->GetGUID().GetCounter();
                    mutation.ActorAccountId = accountId.Value();
                    mutation.ActorGuid = player->GetGUID().GetCounter();
                    MutationStartResult started =
                        GetAccountCollectionStore().BeginPreferenceMutation(std::move(mutation));
                    if (started.Accepted)
                        return finish("mount_favorite", "ACCEPTED");
                    switch (started.Reason)
                    {
                        case CollectionReasonCode::NotOwned:
                            return finish("mount_favorite", "FAVORITE_NOT_OWNED");
                        case CollectionReasonCode::NotReady:
                            return finish("mount_favorite", "LOADING");
                        case CollectionReasonCode::DatabaseError:
                        case CollectionReasonCode::ReadOnly:
                            return finish("mount_favorite", "DB_UNAVAILABLE");
                        case CollectionReasonCode::PendingOperation:
                            return finish("mount_favorite", "RATE_LIMITED");
                        default:
                            return finish("mount_favorite", "INVALID_REQUEST");
                    }
                }
                if (request.ActionId == "PREVIEW")
                {
                    if (request.Target != "-")
                        return finish("preview", "INVALID_REQUEST");
                    CreaturePreviewResult result = GetCreaturePreviewService().Execute(
                        player, MountCollectionTypeId, CollectionId(request.CollectionId));
                    return finish("preview", std::move(result.Status), result.CreatureEntry);
                }
                if (request.ActionId != "SUMMON" || request.Target != "-")
                    return finish("mount", "INVALID_REQUEST");
                return finish("mount", GetMountCollectionService().ExecuteSummon(
                    player, CollectionId(request.CollectionId)));
            }
            if (request.TypeId == CompanionCollectionTypeId.Value())
            {
                if (request.ActionId == "RANDOM_SUMMON")
                {
                    if (request.CollectionId != CompanionRandomActionCollectionId.Value() || request.Target != "-")
                        return finish("companion_random", "INVALID_REQUEST");
                    return finish("companion_random", GetCompanionCollectionService().ExecuteRandomSummon(player));
                }
                if (request.ActionId == "SET_FAVORITE")
                {
                    if (request.Target != "0" && request.Target != "1")
                        return finish("companion_favorite", "INVALID_REQUEST");
                    CompanionCollectionDefinition const* definition =
                        GetCompanionCatalog().Find(CollectionId(request.CollectionId));
                    if (!definition || definition->Lifecycle != CatalogLifecycle::Active ||
                        !definition->JournalVisible || !definition->Actionable)
                        return finish("companion_favorite", "UNSUPPORTED");

                    std::optional<AccountCacheSnapshot> snapshot =
                        GetAccountCollectionCache().Snapshot(accountId);
                    if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
                        return finish("companion_favorite", "LOADING");
                    CollectionKey companionKey { CompanionCollectionTypeId, CollectionId(request.CollectionId) };
                    if (!GetAccountCollectionCache().IsOwned(accountId, companionKey))
                        return finish("companion_favorite", "FAVORITE_NOT_OWNED");

                    AccountCollectionMutation mutation;
                    mutation.Account = accountId;
                    mutation.Generation = snapshot->Generation;
                    mutation.Key = { CompanionFavoriteCollectionTypeId, CollectionId(request.CollectionId) };
                    mutation.Kind = request.Target == "1" ?
                        CollectionMutationKind::Grant : CollectionMutationKind::Revoke;
                    mutation.SourceKind = CollectionSourceKind::Gameplay;
                    mutation.CharacterGuid = player->GetGUID().GetCounter();
                    mutation.ActorAccountId = accountId.Value();
                    mutation.ActorGuid = player->GetGUID().GetCounter();
                    MutationStartResult started =
                        GetAccountCollectionStore().BeginPreferenceMutation(std::move(mutation));
                    if (started.Accepted)
                        return finish("companion_favorite", "ACCEPTED");
                    switch (started.Reason)
                    {
                        case CollectionReasonCode::NotOwned:
                            return finish("companion_favorite", "FAVORITE_NOT_OWNED");
                        case CollectionReasonCode::NotReady:
                            return finish("companion_favorite", "LOADING");
                        case CollectionReasonCode::DatabaseError:
                        case CollectionReasonCode::ReadOnly:
                            return finish("companion_favorite", "DB_UNAVAILABLE");
                        case CollectionReasonCode::PendingOperation:
                            return finish("companion_favorite", "RATE_LIMITED");
                        default:
                            return finish("companion_favorite", "INVALID_REQUEST");
                    }
                }
                if (request.ActionId == "PREVIEW")
                {
                    if (request.Target != "-")
                        return finish("preview", "INVALID_REQUEST");
                    CreaturePreviewResult result = GetCreaturePreviewService().Execute(
                        player, CompanionCollectionTypeId, CollectionId(request.CollectionId));
                    return finish("preview", std::move(result.Status), result.CreatureEntry);
                }
                if (request.ActionId != "SUMMON" || request.Target != "-")
                    return finish("companion", "INVALID_REQUEST");
                return finish("companion", GetCompanionCollectionService().ExecuteSummon(
                    player, CollectionId(request.CollectionId)));
            }
            if (request.TypeId == ToyCollectionTypeId.Value())
            {
                if (request.ActionId != "USE" || (request.Target != "-" && request.Target != "1"))
                    return finish("toy", "INVALID_REQUEST");
                return finish("toy", GetToyCollectionService().ExecuteUse(
                    player, CollectionId(request.CollectionId), request.Target == "1"));
            }
            if (request.TypeId == AppearanceCollectionTypeId.Value())
            {
                std::uint32_t encodedSlot = 0;
                auto parsed = std::from_chars(request.Target.data(),
                    request.Target.data() + request.Target.size(), encodedSlot);
                if (request.ActionId != "APPLY" || parsed.ec != std::errc {} ||
                    parsed.ptr != request.Target.data() + request.Target.size() ||
                    encodedSlot == 0 || encodedSlot > EQUIPMENT_SLOT_END)
                    return finish("appearance", "INVALID_TARGET_SLOT");
                TransmogApplyResult result = GetAppearanceService().TryApplyCanonicalAppearance(
                    player, CollectionId(request.CollectionId), static_cast<std::uint8_t>(encodedSlot - 1),
                    ObjectGuid::Empty, TransmogApplySource::Addon, false);
                return finish("appearance", AppearanceApplyStatus(result));
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
                        return finish("set", "INVALID_REQUEST");
                }
                if (request.ActionId != "APPLY")
                    return finish("set", "INVALID_REQUEST");
                TransmogApplyResult result = GetSetService().TryApply(
                    player, CollectionId(request.CollectionId), variantIndex,
                    ObjectGuid::Empty, TransmogApplySource::Addon);
                return finish("set", AppearanceApplyStatus(result));
            }
            return finish("unknown", "INVALID_REQUEST");
        });
    return false;
}

void Sc2ProtocolPumpAndSend(Player* player)
{
    if (!IsCppBackendOwner() || !player || !player->GetSession())
        return;
    AccountSessionId sessionId = SessionId(player);
    GetSc2Server().SetExternalOwned(
        sessionId, SetCollectionTypeId, GetSetCatalog().CompletedByAccount(
            AccountId(player->GetSession()->GetAccountId())));
    GetSc2Server().PumpSession(sessionId, MonotonicMilliseconds());
    std::vector<std::string> bodies = GetSc2Server().DrainOutbound(sessionId, Sc2Limits::MaxPacketsPerTick);
    auto started = std::chrono::steady_clock::now();
    std::size_t bytes = 0;
    for (std::string const& body : bodies)
    {
        bytes += body.size();
        WorldPacket packet;
        ChatHandler::BuildChatPacket(packet, CHAT_MSG_WHISPER, LANG_ADDON, player, player,
            std::string(WirePrefix) + body);
        player->SendDirectMessage(&packet);
    }
    if (!bodies.empty())
    {
        std::uint64_t elapsedMicroseconds = static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now() - started).count());
        GetSc2Server().RecordSendBatch(bodies.size(), bytes, elapsedMicroseconds);
    }
}

Sc2ServerDiagnostics Sc2ProtocolDiagnostics()
{
    return GetSc2Server().Diagnostics();
}
}

void AddSC_solo_collections_protocol()
{
    LOG_INFO("module.solocollections",
        "event=build_info addon_commit={} module_commit={} core_commit={} metadata_version={} asset_pack_version={} "
        "mapping_hash={} presentation_hash={} mount_hash={} companion_hash={} toy_hash={} appearance_hash={} set_hash={}",
        SoloCollections::SoloCollectionsBuildInfo::addonCommit,
        SoloCollections::SoloCollectionsBuildInfo::moduleCommit,
        SoloCollections::SoloCollectionsBuildInfo::coreCommit,
        SoloCollections::SoloCollectionsBuildInfo::metadataVersion,
        SoloCollections::SoloCollectionsBuildInfo::assetPackVersion,
        SoloCollections::SoloCollectionsBuildInfo::mappingHash,
        SoloCollections::SoloCollectionsBuildInfo::presentationHash,
        SoloCollections::SoloCollectionsBuildInfo::mountMappingHash,
        SoloCollections::SoloCollectionsBuildInfo::companionMappingHash,
        SoloCollections::SoloCollectionsBuildInfo::toyMappingHash,
        SoloCollections::SoloCollectionsBuildInfo::appearanceMappingHash,
        SoloCollections::SoloCollectionsBuildInfo::setMappingHash);
    SoloCollections::GetAccountCollectionStore().SetEventSink(&SoloCollections::GetSc2EventSink());
}
