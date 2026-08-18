#ifndef SOLO_COLLECTIONS_PROTOCOL_SERVER_H
#define SOLO_COLLECTIONS_PROTOCOL_SERVER_H

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsProtocol.h"

#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <random>
#include <string>
#include <vector>

namespace SoloCollections
{
struct Sc2CategoryDefinition
{
    CollectionTypeId TypeId;
    std::string MappingHash;
    bool Enabled = false;
    bool External = false;
    bool RawSnapshot = false;
};

struct Sc2WardrobeOutcome
{
    std::string Status = "INVALID_REQUEST";
    std::uint32_t Copper = 0;
    std::uint32_t WarningMask = 0;
    std::uint16_t TypeId = 0;
    std::uint32_t CollectionId = 1;
    std::uint64_t Revision = 0;
};

struct Sc2ServerDiagnostics
{
    std::size_t SessionCount = 0;
    std::size_t OutboundPacketCount = 0;
    std::uint64_t SnapshotTransfers = 0;
    std::uint64_t SnapshotChunks = 0;
    std::uint64_t SnapshotPayloadBytes = 0;
    std::uint64_t LastSnapshotQueueMicroseconds = 0;
    std::uint64_t MaxSnapshotQueueMicroseconds = 0;
    std::uint64_t SentPackets = 0;
    std::uint64_t SentBytes = 0;
    std::uint64_t LastSendMicroseconds = 0;
    std::uint64_t MaxSendMicroseconds = 0;
};

class Sc2Server
{
public:
    // Handlers may return std::nullopt to defer the reply: the request stays
    // pending (ApplyInFlight / DeferredResult) until CompleteDeferredAction /
    // CompleteDeferredWardrobe queues the result, or the deadline in
    // PumpSession expires with DB_UNAVAILABLE. Handlers run while the server
    // mutex is held, so completions must never be invoked synchronously from
    // inside a handler.
    using ActionHandler = std::function<std::optional<std::string>(AccountId, Sc2Message const&)>;
    using WardrobeHandler = std::function<std::optional<Sc2WardrobeOutcome>(AccountId, Sc2Message const&)>;
    Sc2Server(AccountCollectionCache& cache, std::string metadataVersion,
        std::string assetPackVersion, std::string backendBuild,
        std::vector<Sc2CategoryDefinition> categories);

    void OpenSession(AccountId accountId, AccountSessionId sessionId);
    void CloseSession(AccountSessionId sessionId);
    void SetExternalOwned(AccountSessionId sessionId, CollectionTypeId typeId,
        std::vector<CollectionId> owned);
    void SetRawSnapshot(AccountSessionId sessionId, CollectionTypeId typeId,
        std::uint64_t revision, std::string payload);
    void QueueRawSnapshotReplace(AccountSessionId sessionId, CollectionTypeId typeId,
        std::uint64_t revision, std::string payload);
    void QueueRawSnapshotReplaceForAccount(AccountId accountId, CollectionTypeId typeId,
        std::uint64_t revision, std::string payload);
    void QueueOwnedSnapshotReplaceForAccount(AccountId accountId, CollectionTypeId typeId,
        CollectionRevision revision);
    void OnDerivedOwnedChanged(AccountId accountId, CollectionTypeId typeId,
        std::vector<CollectionId> owned, CollectionRevision revision);
    [[nodiscard]] bool HandleInbound(
        AccountSessionId sessionId, std::string_view body, std::uint64_t nowMs,
        ActionHandler const& actionHandler = {},
        WardrobeHandler const& wardrobeHandler = {});
    void PumpSession(AccountSessionId sessionId, std::uint64_t nowMs);
    // Resolves a deferred ActionRequest with the final status. Ignored when
    // the session is gone or a different request is pending.
    void CompleteDeferredAction(AccountSessionId sessionId, std::uint32_t requestId, std::string status);
    // Resolves a deferred WardrobeIntent / OutfitWrite with the final outcome.
    void CompleteDeferredWardrobe(AccountSessionId sessionId, std::uint32_t requestId,
        Sc2WardrobeOutcome outcome);
    [[nodiscard]] std::vector<std::string> DrainOutbound(
        AccountSessionId sessionId, std::size_t maximum = Sc2Limits::MaxPacketsPerTick);
    [[nodiscard]] std::string SessionNonce(AccountSessionId sessionId) const;
    [[nodiscard]] Sc2ServerDiagnostics Diagnostics() const;
    void RecordSendBatch(std::size_t packets, std::size_t bytes, std::uint64_t elapsedMicroseconds);

    void OnCollectionDeltaCommitted(AccountId accountId, CollectionDelta const& delta);
    [[nodiscard]] bool OnAccountResyncRequested(AccountId accountId);

private:
    struct TokenBucket
    {
        double Tokens = 12.0;
        std::uint64_t LastRefillMs = 0;
    };

    using ReplayCache = std::map<std::uint32_t, std::uint64_t>;
    using OutboundQueue = std::deque<std::string>;

    struct RawSnapshotState
    {
        std::uint64_t Revision = 0;
        std::string Payload;
    };

    struct DeferredResult
    {
        bool Active = false;
        std::uint32_t RequestId = 0;
        std::uint64_t DeadlineMs = 0;
        // Prebuilt result template (kind, nonce, request id, type/collection
        // defaults); completion only fills the outcome fields.
        Sc2Message Template;
        bool ApplyOrClear = false;
    };

    struct SessionState
    {
        AccountId Account;
        bool Active = false;
        bool AwaitingSnapshot = false;
        bool ApplyInFlight = false;
        DeferredResult Deferred;
        std::string ClientNonce;
        std::string ClientBuild;
        std::string ClientMetadataVersion;
        std::string ClientAssetPackVersion;
        std::string Nonce;
        std::uint32_t NextTransferId = 1;
        TokenBucket Bucket;
        TokenBucket QuoteBucket;
        TokenBucket ApplyBucket;
        TokenBucket OutfitBucket;
        ReplayCache Replays;
        OutboundQueue Outbound;
        std::map<CollectionTypeId, std::vector<CollectionId>> ExternalOwned;
        std::map<CollectionTypeId, RawSnapshotState> RawSnapshots;
        // Index of the next category to send while a full snapshot cycle is
        // paused by outbound backpressure (AwaitingSnapshot == true).
        std::size_t SnapshotCursor = 0;
    };

    [[nodiscard]] bool ConsumeToken(SessionState& session, std::uint64_t nowMs);
    [[nodiscard]] bool ConsumeBucket(TokenBucket& bucket, double capacity, double rate, std::uint64_t nowMs);
    [[nodiscard]] bool CategoryVisible(SessionState const& session, Sc2CategoryDefinition const& category) const;
    void CleanupReplays(SessionState& session, std::uint64_t nowMs);
    void Queue(SessionState& session, Sc2Message message);
    void QueueError(SessionState& session, std::uint32_t requestId, std::string reason);
    void QueueHandshake(SessionState& session);
    void QueueCurrentState(SessionState& session);
    void QueueSnapshots(SessionState& session, AccountCacheSnapshot const& snapshot);
    // Snapshot queueing returns false when the whole transfer does not fit in
    // the outbound queue; callers keep AwaitingSnapshot set and retry after
    // the queue drains (backpressure instead of clearing the queue).
    bool QueueCategorySnapshot(SessionState& session, Sc2CategoryDefinition const& category,
        std::uint64_t revision, std::vector<CollectionId> const& owned);
    bool QueueRawCategorySnapshot(SessionState& session, Sc2CategoryDefinition const& category);
    bool QueueRawCategorySnapshot(SessionState& session, CollectionTypeId typeId,
        std::uint64_t revision, std::string payload);
    [[nodiscard]] std::string NewNonce();

    AccountCollectionCache& _cache;
    std::string _metadataVersion;
    std::string _assetPackVersion;
    std::string _backendBuild;
    std::vector<Sc2CategoryDefinition> _categories;
    std::map<AccountSessionId, SessionState> _sessions;
    std::mt19937_64 _random;
    mutable std::mutex _mutex;
    Sc2ServerDiagnostics _diagnostics;
};
}

#endif
