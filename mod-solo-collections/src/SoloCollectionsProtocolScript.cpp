#include "SoloCollectionsProtocolScript.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountService.h"
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
#include "SoloCollectionsTransmogProjection.h"
#include "SoloCollectionsTransmogService.h"
#include "Transmogrification.h"

#include "Chat.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <chrono>
#include <charconv>
#include <memory>
#include <optional>
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
        categories.push_back({ CharacterAppliedCollectionTypeId, CharacterAppliedMappingHash, true, true, true });
        categories.push_back({ AccountOutfitCollectionTypeId, AccountOutfitMappingHash, true, true, true });
        categories.push_back({ AppearanceNewCollectionTypeId, AppearanceNewMappingHash, true, false, false });
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
        if (delta.Key.TypeId == AppearanceCollectionTypeId &&
            delta.Kind == CollectionDeltaKind::Revoke)
            GetAppearanceService().QueueNewClear(accountId, delta.Key.Id);
    }

    void OnOwnedSnapshotReplaced(
        AccountId accountId, CollectionTypeId typeId, CollectionRevision revision) override
    {
        GetSc2Server().QueueOwnedSnapshotReplaceForAccount(accountId, typeId, revision);
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
    // Both loads are asynchronous; the initial raw snapshots below may still
    // be empty, and the load completions enqueue wardrobe pushes that replace
    // them once the DB rows arrive.
    GetTransmogProjectionService().LoadCharacter(
        player->GetGUID(), player->GetSession()->GetAccountId());
    GetTransmogProjectionService().LoadAccount(player->GetSession()->GetAccountId());
    GetSc2Server().SetRawSnapshot(SessionId(player), CharacterAppliedCollectionTypeId,
        GetTransmogProjectionService().AppliedRevision(player->GetGUID()),
        GetTransmogProjectionService().AppliedPayload(player->GetGUID()));
    GetSc2Server().SetRawSnapshot(SessionId(player), AccountOutfitCollectionTypeId,
        GetTransmogProjectionService().OutfitRevision(player->GetSession()->GetAccountId()),
        GetTransmogProjectionService().OutfitPayload(player->GetSession()->GetAccountId()));
}

void FlushWardrobeSnapshots()
{
    std::vector<PendingWardrobePush> pushes;
    GetTransmogProjectionService().TakePendingPushes(pushes);
    for (PendingWardrobePush const& push : pushes)
    {
        if (push.Applied && push.Session.IsValid())
        {
            // SetRawSnapshot covers sessions that have not completed the SC2
            // hello yet (async login prefetch resolving before the handshake);
            // the replace additionally queues a delta for active sessions.
            GetSc2Server().SetRawSnapshot(push.Session, CharacterAppliedCollectionTypeId,
                GetTransmogProjectionService().AppliedRevision(push.Character),
                GetTransmogProjectionService().AppliedPayload(push.Character));
            GetSc2Server().QueueRawSnapshotReplace(push.Session, CharacterAppliedCollectionTypeId,
                GetTransmogProjectionService().AppliedRevision(push.Character),
                GetTransmogProjectionService().AppliedPayload(push.Character));
        }
        if (push.OutfitsToAccount && push.Account.IsValid())
            GetSc2Server().QueueRawSnapshotReplaceForAccount(push.Account, AccountOutfitCollectionTypeId,
                GetTransmogProjectionService().OutfitRevision(push.Account.Value()),
                GetTransmogProjectionService().OutfitPayload(push.Account.Value()));
    }
}

void Sc2ProtocolCloseSession(Player* player)
{
    if (IsCppBackendOwner() && player)
    {
        GetTransmogProjectionService().UnloadCharacter(player->GetGUID());
        GetSc2Server().CloseSession(SessionId(player));
    }
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
            "event=protocol_reject result=bad_message account={} character={} bytes={} kind={}",
            player->GetSession()->GetAccountId(), player->GetGUID().GetCounter(), body.size(),
            body.empty() ? '-' : body.front());
    }
    GetSc2Server().SetExternalOwned(
        SessionId(player), TitleCollectionTypeId, GetTitleService().OwnedByPlayer(player));
    GetSc2Server().SetExternalOwned(
        SessionId(player), SetCollectionTypeId, GetSetCatalog().CompletedByAccount(
            AccountId(player->GetSession()->GetAccountId())));
    (void)GetSc2Server().HandleInbound(SessionId(player), body, MonotonicMilliseconds(),
        [player](AccountId accountId, Sc2Message const& request) -> std::optional<std::string>
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
                if (request.ActionId == "MARK_SEEN")
                {
                    if (request.Target != "-")
                        return finish("appearance_seen", "INVALID_REQUEST");
                    CollectionId appearanceId(request.CollectionId);
                    if (!GetAppearanceService().Evaluate(appearanceId).Availability.CatalogKnown)
                        return finish("appearance_seen", "UNKNOWN_IDENTITY");
                    if (!GetAccountCollectionCache().IsOwned(accountId,
                        { AppearanceCollectionTypeId, appearanceId }))
                        return finish("appearance_seen", "NOT_OWNED");
                    if (!GetAccountCollectionCache().IsOwned(accountId,
                        { AppearanceNewCollectionTypeId, appearanceId }))
                        return finish("appearance_seen", "ACCEPTED");
                    MutationStartResult started = GetAccountCollectionService().TryRevoke(accountId,
                        { AppearanceNewCollectionTypeId, appearanceId }, CollectionSourceKind::Gameplay,
                        0, player->GetGUID().GetCounter(), accountId.Value(),
                        player->GetGUID().GetCounter());
                    if (started.Accepted)
                        return finish("appearance_seen", "ACCEPTED");
                    switch (started.Reason)
                    {
                        case CollectionReasonCode::NotOwned:
                            return finish("appearance_seen", "ACCEPTED");
                        case CollectionReasonCode::NotReady:
                            return finish("appearance_seen", "LOADING");
                        case CollectionReasonCode::DatabaseError:
                        case CollectionReasonCode::ReadOnly:
                            return finish("appearance_seen", "DB_UNAVAILABLE");
                        case CollectionReasonCode::PendingOperation:
                            return finish("appearance_seen", "RATE_LIMITED");
                        default:
                            return finish("appearance_seen", "INVALID_REQUEST");
                    }
                }
                if (request.ActionId == "MARK_ALL_SEEN")
                {
                    if (request.CollectionId != 1 || request.Target != "-")
                        return finish("appearance_seen_all", "INVALID_REQUEST");
                    MutationStartResult started = GetAccountCollectionService().TryClearType(accountId,
                        AppearanceNewCollectionTypeId, CollectionSourceKind::Gameplay,
                        player->GetGUID().GetCounter(), accountId.Value(),
                        player->GetGUID().GetCounter());
                    if (started.Accepted)
                        return finish("appearance_seen_all", "ACCEPTED");
                    switch (started.Reason)
                    {
                        case CollectionReasonCode::NotReady:
                            return finish("appearance_seen_all", "LOADING");
                        case CollectionReasonCode::DatabaseError:
                        case CollectionReasonCode::ReadOnly:
                            return finish("appearance_seen_all", "DB_UNAVAILABLE");
                        case CollectionReasonCode::PendingOperation:
                            return finish("appearance_seen_all", "RATE_LIMITED");
                        default:
                            return finish("appearance_seen_all", "INVALID_REQUEST");
                    }
                }
                std::uint32_t encodedSlot = 0;
                auto parsed = std::from_chars(request.Target.data(),
                    request.Target.data() + request.Target.size(), encodedSlot);
                if (request.ActionId != "APPLY" || parsed.ec != std::errc {} ||
                    parsed.ptr != request.Target.data() + request.Target.size() ||
                    encodedSlot == 0 || encodedSlot > EQUIPMENT_SLOT_END)
                    return finish("appearance", "INVALID_TARGET_SLOT");
                // Async commit: if the completion fires synchronously
                // (validation failure) return inline, otherwise defer the
                // ActionResult until the DB callback resolves.
                auto inlineStatus = std::make_shared<std::optional<std::string>>();
                auto handlerReturned = std::make_shared<bool>(false);
                AccountSessionId sessionId = SessionId(player);
                ObjectGuid characterGuid = player->GetGUID();
                std::uint32_t requestId = request.RequestId;
                std::uint32_t collectionId = request.CollectionId;
                std::uint8_t slot = static_cast<std::uint8_t>(encodedSlot - 1);
                GetAppearanceService().TryApplyCanonicalAppearance(
                    player, CollectionId(request.CollectionId), slot,
                    ObjectGuid::Empty, TransmogApplySource::Addon, false,
                    [inlineStatus, handlerReturned, sessionId, characterGuid, requestId,
                        collectionId, slot](TransmogApplyResult result)
                    {
                        if (result.IsSuccess())
                            if (Player* current = ObjectAccessor::FindConnectedPlayer(characterGuid))
                                GetTransmogProjectionService().SyncLegacyApplied(current, {
                                    { slot, collectionId }
                                });
                        std::string status = AppearanceApplyStatus(result);
                        if (!*handlerReturned)
                            *inlineStatus = std::move(status);
                        else
                            GetSc2Server().CompleteDeferredAction(sessionId, requestId, std::move(status));
                    });
                *handlerReturned = true;
                if (*inlineStatus)
                    return finish("appearance", std::move(**inlineStatus));
                (void)finish("appearance", "DEFERRED");
                return std::nullopt;
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
                auto inlineStatus = std::make_shared<std::optional<std::string>>();
                auto handlerReturned = std::make_shared<bool>(false);
                AccountSessionId sessionId = SessionId(player);
                std::uint32_t requestId = request.RequestId;
                GetSetService().TryApply(
                    player, CollectionId(request.CollectionId), variantIndex,
                    ObjectGuid::Empty, TransmogApplySource::Addon,
                    [inlineStatus, handlerReturned, sessionId, requestId](TransmogApplyResult result)
                    {
                        std::string status = AppearanceApplyStatus(result);
                        if (!*handlerReturned)
                            *inlineStatus = std::move(status);
                        else
                            GetSc2Server().CompleteDeferredAction(sessionId, requestId, std::move(status));
                    });
                *handlerReturned = true;
                if (*inlineStatus)
                    return finish("set", std::move(**inlineStatus));
                (void)finish("set", "DEFERRED");
                return std::nullopt;
            }
            if (request.TypeId == AccountOutfitCollectionTypeId.Value())
            {
                if (request.ActionId != "DELETE" || request.Target != "-")
                    return finish("outfit", "INVALID_REQUEST");
                auto inlineStatus = std::make_shared<std::optional<std::string>>();
                auto handlerReturned = std::make_shared<bool>(false);
                AccountSessionId sessionId = SessionId(player);
                std::uint32_t requestId = request.RequestId;
                GetTransmogProjectionService().DeleteOutfit(player, request.CollectionId,
                    [inlineStatus, handlerReturned, sessionId, requestId](Sc2WardrobeOutcome outcome)
                    {
                        if (!*handlerReturned)
                            *inlineStatus = std::move(outcome.Status);
                        else
                            GetSc2Server().CompleteDeferredAction(
                                sessionId, requestId, std::move(outcome.Status));
                    });
                *handlerReturned = true;
                if (*inlineStatus)
                    return finish("outfit", std::move(**inlineStatus));
                (void)finish("outfit", "DEFERRED");
                return std::nullopt;
            }
            return finish("unknown", "INVALID_REQUEST");
        },
        [player](AccountId accountId, Sc2Message const& request) -> std::optional<Sc2WardrobeOutcome>
        {
            Sc2WardrobeOutcome outcome;
            if (!player->GetSession() || accountId.Value() != player->GetSession()->GetAccountId())
            {
                outcome.Status = "INVALID_REQUEST";
                return outcome;
            }
            if (request.Kind == Sc2MessageKind::WardrobeIntent && request.Op == "QUOTE")
                return GetTransmogProjectionService().Quote(player, request.Entries);

            // Write flows are asynchronous. If the completion fires
            // synchronously (validation failure) return inline, otherwise
            // defer the reply until the DB callback resolves.
            auto inlineOutcome = std::make_shared<std::optional<Sc2WardrobeOutcome>>();
            auto handlerReturned = std::make_shared<bool>(false);
            AccountSessionId sessionId = SessionId(player);
            std::uint32_t requestId = request.RequestId;
            auto complete = [inlineOutcome, handlerReturned, sessionId, requestId](Sc2WardrobeOutcome result)
            {
                if (!*handlerReturned)
                    *inlineOutcome = std::move(result);
                else
                    GetSc2Server().CompleteDeferredWardrobe(sessionId, requestId, std::move(result));
            };
            bool dispatched = false;
            if (request.Kind == Sc2MessageKind::WardrobeIntent)
            {
                if (request.Op == "APPLY")
                {
                    GetTransmogProjectionService().Apply(player, request.Entries, complete);
                    dispatched = true;
                }
                else if (request.Op == "CLEAR")
                {
                    GetTransmogProjectionService().Clear(player, request.Entries, complete);
                    dispatched = true;
                }
            }
            else if (request.Kind == Sc2MessageKind::OutfitWrite)
            {
                if (request.Op == "SAVE")
                {
                    GetTransmogProjectionService().SaveOutfit(
                        player, request.Uid, request.NameHex, request.Entries, complete);
                    dispatched = true;
                }
                else if (request.Op == "RENAME")
                {
                    GetTransmogProjectionService().RenameOutfit(
                        player, request.Uid, request.NameHex, complete);
                    dispatched = true;
                }
            }
            if (!dispatched)
            {
                outcome.Status = "INVALID_REQUEST";
                return outcome;
            }
            *handlerReturned = true;
            if (*inlineOutcome)
                return std::move(**inlineOutcome);
            return std::nullopt;
        });
    FlushWardrobeSnapshots();
    return false;
}

void Sc2ProtocolPumpAndSend(Player* player)
{
    if (!IsCppBackendOwner() || !player || !player->GetSession())
        return;
    AccountSessionId sessionId = SessionId(player);
    // Deferred (async commit) completions enqueue pushes outside HandleInbound;
    // flush them here so they reach clients on the next pump.
    FlushWardrobeSnapshots();
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
