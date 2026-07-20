#include "SoloCollectionsProtocolServer.h"

#include <algorithm>
#include <chrono>
#include <iomanip>
#include <iterator>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace SoloCollections
{
namespace
{
constexpr double BucketCapacity = 12.0;
constexpr double TokensPerSecond = 6.0;
constexpr std::uint64_t ReplayLifetimeMs = 30'000;
constexpr std::size_t MaxReplayEntries = 128;
constexpr std::size_t MaxOutboundPackets = 512;

bool IsActionStatus(std::string_view value)
{
    constexpr std::string_view values[] = {
        "ACCEPTED", "DISMISSED", "LOADING", "NOT_OWNED", "CATALOG_MISMATCH", "ASSET_MISMATCH",
        "UNKNOWN_IDENTITY", "CLASS_RESTRICTED", "RACE_RESTRICTED", "SKILL_REQUIRED",
        "INVALID_TARGET_SLOT", "DB_UNAVAILABLE", "RATE_LIMITED", "INVALID_REQUEST", "UNSUPPORTED",
        "NOT_ENOUGH_MONEY", "NOT_ENOUGH_TOKENS",
        "IN_COMBAT", "DEAD", "IN_VEHICLE", "ON_TAXI", "INDOORS", "FLYING_NOT_ALLOWED",
        "MAP_RESTRICTED", "BATTLEGROUND_RESTRICTED", "SHAPESHIFT_RESTRICTED", "CAST_FAILED",
    };
    return std::find(std::begin(values), std::end(values), value) != std::end(values);
}
}

Sc2Server::Sc2Server(AccountCollectionCache& cache, std::string metadataVersion,
    std::string assetPackVersion, std::string backendBuild,
    std::vector<Sc2CategoryDefinition> categories)
    : _cache(cache), _metadataVersion(std::move(metadataVersion)),
      _assetPackVersion(std::move(assetPackVersion)), _backendBuild(std::move(backendBuild)),
      _categories(std::move(categories))
{
    std::random_device randomDevice;
    std::seed_seq seed {
        randomDevice(), randomDevice(), randomDevice(), randomDevice(),
        static_cast<unsigned int>(std::chrono::steady_clock::now().time_since_epoch().count())
    };
    _random.seed(seed);
    std::sort(_categories.begin(), _categories.end(), [](Sc2CategoryDefinition const& left,
        Sc2CategoryDefinition const& right) { return left.TypeId < right.TypeId; });
}

void Sc2Server::OpenSession(AccountId accountId, AccountSessionId sessionId)
{
    std::scoped_lock lock(_mutex);
    if (!accountId.IsValid() || !sessionId.IsValid())
        return;
    SessionState& session = _sessions[sessionId];
    session = SessionState {};
    session.Account = accountId;
}

void Sc2Server::CloseSession(AccountSessionId sessionId)
{
    std::scoped_lock lock(_mutex);
    _sessions.erase(sessionId);
}

void Sc2Server::SetExternalOwned(AccountSessionId sessionId, CollectionTypeId typeId,
    std::vector<CollectionId> owned)
{
    std::scoped_lock lock(_mutex);
    auto session = _sessions.find(sessionId);
    if (session == _sessions.end() || !typeId.IsValid())
        return;
    std::sort(owned.begin(), owned.end());
    owned.erase(std::unique(owned.begin(), owned.end()), owned.end());
    session->second.ExternalOwned[typeId] = std::move(owned);
}

bool Sc2Server::ConsumeToken(SessionState& session, std::uint64_t nowMs)
{
    if (nowMs > session.Bucket.LastRefillMs)
    {
        double elapsedSeconds = static_cast<double>(nowMs - session.Bucket.LastRefillMs) / 1000.0;
        session.Bucket.Tokens = std::min(BucketCapacity,
            session.Bucket.Tokens + elapsedSeconds * TokensPerSecond);
        session.Bucket.LastRefillMs = nowMs;
    }
    if (session.Bucket.Tokens < 1.0)
        return false;
    session.Bucket.Tokens -= 1.0;
    return true;
}

void Sc2Server::CleanupReplays(SessionState& session, std::uint64_t nowMs)
{
    for (auto replay = session.Replays.begin(); replay != session.Replays.end();)
    {
        if (nowMs >= replay->second && nowMs - replay->second >= ReplayLifetimeMs)
            replay = session.Replays.erase(replay);
        else
            ++replay;
    }
    while (session.Replays.size() > MaxReplayEntries)
        session.Replays.erase(session.Replays.begin());
}

void Sc2Server::Queue(SessionState& session, Sc2Message message)
{
    std::string packet = EncodeSc2Message(message);
    if (packet.size() > Sc2Limits::MaxBodyBytes)
        throw std::logic_error("SC2 encoder produced an oversized packet");
    if (session.Outbound.size() >= MaxOutboundPackets)
    {
        session.Outbound.clear();
        session.AwaitingSnapshot = true;
        return;
    }
    session.Outbound.push_back(std::move(packet));
}

void Sc2Server::QueueError(SessionState& session, std::uint32_t requestId, std::string reason)
{
    Sc2Message message;
    message.Kind = Sc2MessageKind::Error;
    message.SessionNonce = session.Nonce;
    message.RequestId = requestId;
    message.Reason = std::move(reason);
    Queue(session, std::move(message));
}

std::string Sc2Server::NewNonce()
{
    std::uint64_t value = 0;
    while (value == 0)
        value = _random();
    std::ostringstream stream;
    stream << std::hex << std::setfill('0') << std::setw(16) << value;
    return stream.str();
}

void Sc2Server::QueueHandshake(SessionState& session)
{
    std::optional<AccountCacheSnapshot> snapshot = _cache.Snapshot(session.Account);
    std::uint32_t flags = 0;
    std::uint8_t categoryCount = 0;
    for (Sc2CategoryDefinition const& category : _categories)
    {
        if (!category.Enabled)
            continue;
        ++categoryCount;
        if (category.TypeId.Value() >= 1 && category.TypeId.Value() <= 32)
            flags |= (std::uint32_t { 1 } << (category.TypeId.Value() - 1));
    }
    std::ostringstream flagStream;
    flagStream << std::hex << std::setfill('0') << std::setw(8) << flags;

    Sc2Message acknowledgement;
    acknowledgement.Kind = Sc2MessageKind::HelloAck;
    acknowledgement.ProtocolVersion = 1;
    acknowledgement.SessionNonce = session.Nonce;
    acknowledgement.Revision = snapshot ? snapshot->Revision.Value() : 0;
    acknowledgement.EnabledCategoryFlags = flagStream.str();
    acknowledgement.MetadataVersion = _metadataVersion;
    acknowledgement.AssetPackVersion = _assetPackVersion;
    acknowledgement.BackendBuild = _backendBuild;
    acknowledgement.CategoryCount = categoryCount;
    Queue(session, std::move(acknowledgement));

    for (Sc2CategoryDefinition const& category : _categories)
    {
        if (!category.Enabled)
            continue;
        Sc2Message mapping;
        mapping.Kind = Sc2MessageKind::CategoryMap;
        mapping.SessionNonce = session.Nonce;
        mapping.TypeId = category.TypeId.Value();
        mapping.MappingHash = category.MappingHash;
        Queue(session, std::move(mapping));
    }
}

void Sc2Server::QueueCategorySnapshot(SessionState& session,
    Sc2CategoryDefinition const& category, std::uint64_t revision,
    std::vector<CollectionId> const& owned)
{
    std::vector<std::uint32_t> values;
    values.reserve(owned.size());
    for (CollectionId collectionId : owned)
        values.push_back(collectionId.Value());
    std::string payload = Sc2CanonicalOwnedPayload(std::move(values));
    if (payload.size() > Sc2Limits::MaxSnapshotBytes)
    {
        QueueError(session, 0, "SNAPSHOT_TOO_LARGE");
        return;
    }
    std::vector<std::string> chunks = Sc2ChunkPayload(payload);
    std::string checksum = Sc2Adler32Hex(payload);
    std::uint32_t transferId = session.NextTransferId++;
    if (transferId == 0)
        transferId = session.NextTransferId++;

    Sc2Message begin;
    begin.Kind = Sc2MessageKind::SnapshotBegin;
    begin.SessionNonce = session.Nonce;
    begin.TransferId = transferId;
    begin.TypeId = category.TypeId.Value();
    begin.Total = static_cast<std::uint16_t>(chunks.size());
    begin.Revision = revision;
    begin.Checksum = checksum;
    begin.PayloadBytes = static_cast<std::uint32_t>(payload.size());
    Queue(session, std::move(begin));

    for (std::size_t index = 0; index < chunks.size(); ++index)
    {
        Sc2Message chunk;
        chunk.Kind = Sc2MessageKind::SnapshotChunk;
        chunk.SessionNonce = session.Nonce;
        chunk.TransferId = transferId;
        chunk.Seq = static_cast<std::uint16_t>(index + 1);
        chunk.Payload = std::move(chunks[index]);
        Queue(session, std::move(chunk));
    }

    Sc2Message end;
    end.Kind = Sc2MessageKind::SnapshotEnd;
    end.SessionNonce = session.Nonce;
    end.TransferId = transferId;
    end.Checksum = checksum;
    Queue(session, std::move(end));
}

void Sc2Server::QueueSnapshots(SessionState& session, AccountCacheSnapshot const& snapshot)
{
    for (Sc2CategoryDefinition const& category : _categories)
    {
        if (!category.Enabled)
            continue;
        std::optional<std::vector<CollectionId>> owned;
        if (category.External)
        {
            auto external = session.ExternalOwned.find(category.TypeId);
            owned = external == session.ExternalOwned.end() ?
                std::vector<CollectionId> {} : external->second;
        }
        else
            owned = _cache.OwnedByType(session.Account, category.TypeId);
        if (!owned)
        {
            QueueError(session, 0, "LOADING");
            session.AwaitingSnapshot = true;
            return;
        }
        QueueCategorySnapshot(session, category, snapshot.Revision.Value(), *owned);
    }
    session.AwaitingSnapshot = false;
}

void Sc2Server::QueueCurrentState(SessionState& session)
{
    std::optional<AccountCacheSnapshot> snapshot = _cache.Snapshot(session.Account);
    if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
    {
        QueueError(session, 0, "LOADING");
        session.AwaitingSnapshot = true;
        return;
    }
    if (snapshot->State == AccountCacheLoadState::Failed)
    {
        QueueError(session, 0, "DB_UNAVAILABLE");
        session.AwaitingSnapshot = false;
        return;
    }
    QueueSnapshots(session, *snapshot);
}

bool Sc2Server::HandleInbound(AccountSessionId sessionId, std::string_view body, std::uint64_t nowMs,
    ActionHandler const& actionHandler)
{
    std::scoped_lock lock(_mutex);
    auto found = _sessions.find(sessionId);
    if (found == _sessions.end())
        return false;
    SessionState& session = found->second;
    Sc2DecodeResult decoded = DecodeSc2Body(body);
    if (!decoded.Success)
    {
        if (session.Active)
            QueueError(session, 0, "BAD_MESSAGE");
        return true;
    }

    Sc2Message const& message = decoded.Message;
    if (message.Kind == Sc2MessageKind::Hello)
    {
        session.Active = true;
        session.AwaitingSnapshot = false;
        session.ClientNonce = message.ClientNonce;
        session.Nonce = NewNonce();
        session.NextTransferId = 1;
        session.Bucket = TokenBucket { BucketCapacity, nowMs };
        session.Replays.clear();
        session.Outbound.clear();
        if (message.ProtocolVersion != 1)
        {
            QueueError(session, 0, "UNSUPPORTED_VERSION");
            return true;
        }
        QueueHandshake(session);
        QueueCurrentState(session);
        return true;
    }

    if (!session.Active || message.SessionNonce != session.Nonce)
        return true;
    if (!ConsumeToken(session, nowMs))
    {
        QueueError(session, message.RequestId, "RATE_LIMITED");
        return true;
    }

    if (message.Kind == Sc2MessageKind::ActionRequest)
    {
        CleanupReplays(session, nowMs);
        if (session.Replays.contains(message.RequestId))
        {
            QueueError(session, message.RequestId, "REPLAYED_REQUEST");
            return true;
        }
        session.Replays.emplace(message.RequestId, nowMs);
        std::optional<AccountCacheSnapshot> snapshot = _cache.Snapshot(session.Account);
        Sc2Message result;
        result.Kind = Sc2MessageKind::ActionResult;
        result.SessionNonce = session.Nonce;
        result.RequestId = message.RequestId;
        result.TypeId = message.TypeId;
        result.CollectionId = message.CollectionId;
        result.Revision = snapshot ? snapshot->Revision.Value() : 0;
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            result.Status = "LOADING";
        else if (snapshot->State == AccountCacheLoadState::Failed)
            result.Status = "DB_UNAVAILABLE";
        else if (actionHandler)
        {
            result.Status = actionHandler(session.Account, message);
            if (!IsActionStatus(result.Status))
                result.Status = "INVALID_REQUEST";
        }
        else
            result.Status = "UNSUPPORTED";
        Queue(session, std::move(result));
        return true;
    }

    if (message.Kind == Sc2MessageKind::Resync)
    {
        QueueCurrentState(session);
        return true;
    }

    QueueError(session, message.RequestId, "BAD_MESSAGE");
    return true;
}

void Sc2Server::PumpSession(AccountSessionId sessionId, std::uint64_t /*nowMs*/)
{
    std::scoped_lock lock(_mutex);
    auto found = _sessions.find(sessionId);
    if (found != _sessions.end() && found->second.Active && found->second.AwaitingSnapshot)
    {
        std::optional<AccountCacheSnapshot> snapshot = _cache.Snapshot(found->second.Account);
        if (snapshot && snapshot->State != AccountCacheLoadState::Loading)
            QueueCurrentState(found->second);
    }
}

std::vector<std::string> Sc2Server::DrainOutbound(AccountSessionId sessionId, std::size_t maximum)
{
    std::scoped_lock lock(_mutex);
    std::vector<std::string> packets;
    auto found = _sessions.find(sessionId);
    if (found == _sessions.end() || maximum == 0)
        return packets;
    maximum = std::min(maximum, MaxOutboundPackets);
    packets.reserve(std::min(maximum, found->second.Outbound.size()));
    while (!found->second.Outbound.empty() && packets.size() < maximum)
    {
        packets.push_back(std::move(found->second.Outbound.front()));
        found->second.Outbound.pop_front();
    }
    return packets;
}

std::string Sc2Server::SessionNonce(AccountSessionId sessionId) const
{
    std::scoped_lock lock(_mutex);
    auto found = _sessions.find(sessionId);
    return found == _sessions.end() ? std::string {} : found->second.Nonce;
}

void Sc2Server::OnCollectionDeltaCommitted(AccountId accountId, CollectionDelta const& delta)
{
    std::scoped_lock lock(_mutex);
    for (auto& [sessionId, session] : _sessions)
    {
        (void)sessionId;
        if (!session.Active || session.Account != accountId)
            continue;
        Sc2Message message;
        message.Kind = Sc2MessageKind::Delta;
        message.SessionNonce = session.Nonce;
        message.TypeId = delta.Key.TypeId.Value();
        message.Revision = delta.Revision.Value();
        message.Operation = delta.Kind == CollectionDeltaKind::Unlock ? "A" : "R";
        message.CollectionId = delta.Key.Id.Value();
        Queue(session, std::move(message));
    }
}

bool Sc2Server::OnAccountResyncRequested(AccountId accountId)
{
    std::scoped_lock lock(_mutex);
    bool queued = false;
    for (auto& [sessionId, session] : _sessions)
    {
        (void)sessionId;
        if (!session.Active || session.Account != accountId)
            continue;
        QueueCurrentState(session);
        queued = true;
    }
    return queued;
}
}
