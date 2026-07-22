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
    using ActionHandler = std::function<std::string(AccountId, Sc2Message const&)>;
    Sc2Server(AccountCollectionCache& cache, std::string metadataVersion,
        std::string assetPackVersion, std::string backendBuild,
        std::vector<Sc2CategoryDefinition> categories);

    void OpenSession(AccountId accountId, AccountSessionId sessionId);
    void CloseSession(AccountSessionId sessionId);
    void SetExternalOwned(AccountSessionId sessionId, CollectionTypeId typeId,
        std::vector<CollectionId> owned);
    void OnDerivedOwnedChanged(AccountId accountId, CollectionTypeId typeId,
        std::vector<CollectionId> owned, CollectionRevision revision);
    [[nodiscard]] bool HandleInbound(
        AccountSessionId sessionId, std::string_view body, std::uint64_t nowMs,
        ActionHandler const& actionHandler = {});
    void PumpSession(AccountSessionId sessionId, std::uint64_t nowMs);
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

    struct SessionState
    {
        AccountId Account;
        bool Active = false;
        bool AwaitingSnapshot = false;
        std::string ClientNonce;
        std::string ClientMetadataVersion;
        std::string ClientAssetPackVersion;
        std::string Nonce;
        std::uint32_t NextTransferId = 1;
        TokenBucket Bucket;
        ReplayCache Replays;
        OutboundQueue Outbound;
        std::map<CollectionTypeId, std::vector<CollectionId>> ExternalOwned;
    };

    [[nodiscard]] bool ConsumeToken(SessionState& session, std::uint64_t nowMs);
    void CleanupReplays(SessionState& session, std::uint64_t nowMs);
    void Queue(SessionState& session, Sc2Message message);
    void QueueError(SessionState& session, std::uint32_t requestId, std::string reason);
    void QueueHandshake(SessionState& session);
    void QueueCurrentState(SessionState& session);
    void QueueSnapshots(SessionState& session, AccountCacheSnapshot const& snapshot);
    void QueueCategorySnapshot(SessionState& session, Sc2CategoryDefinition const& category,
        std::uint64_t revision, std::vector<CollectionId> const& owned);
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
