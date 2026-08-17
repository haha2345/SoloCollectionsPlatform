#include "SoloCollectionsProtocolServer.h"

#include "SoloCollectionsTransmogProjection.h"

#include "Log.h"

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
constexpr double QuoteBucketCapacity = 5.0;
constexpr double QuoteTokensPerSecond = 5.0;
constexpr double ApplyBucketCapacity = 2.0;
constexpr double ApplyTokensPerSecond = 0.5;
constexpr double OutfitBucketCapacity = 1.0;
constexpr double OutfitTokensPerSecond = 1.0;
constexpr std::uint64_t ReplayLifetimeMs = 30'000;
constexpr std::size_t MaxReplayEntries = 128;
constexpr std::size_t MaxOutboundPackets = 512;

bool IsActionStatus(std::string_view value)
{
    constexpr std::string_view values[] = {
        "ACCEPTED", "DISMISSED", "LOADING", "NOT_OWNED", "FAVORITE_NOT_OWNED",
        "CATALOG_MISMATCH", "ASSET_MISMATCH",
        "UNKNOWN_IDENTITY", "CLASS_RESTRICTED", "RACE_RESTRICTED", "SKILL_REQUIRED",
        "WEAPON_TYPE", "ARMOR_TYPE",
        "INVALID_TARGET_SLOT", "DB_UNAVAILABLE", "RATE_LIMITED", "INVALID_REQUEST", "UNSUPPORTED",
        "NOT_ENOUGH_MONEY", "NOT_ENOUGH_TOKENS",
        "IN_COMBAT", "DEAD", "IN_VEHICLE", "ON_TAXI", "INDOORS", "FLYING_NOT_ALLOWED",
        "MAP_RESTRICTED", "BATTLEGROUND_RESTRICTED", "SHAPESHIFT_RESTRICTED", "CAST_FAILED",
        "NO_MOUNTS", "NO_USABLE_MOUNTS",
        "INSUFFICIENT_FUNDS", "OUTFIT_LIMIT", "OUTFIT_EMPTY", "COST_CHANGED", "NOTHING_EQUIPPED",
    };
    return std::find(std::begin(values), std::end(values), value) != std::end(values);
}

std::string WarningMaskHex(std::uint32_t mask)
{
    std::ostringstream stream;
    stream << std::hex << std::setfill('0') << std::setw(8) << mask;
    return stream.str();
}

std::string DefaultRawPayload(CollectionTypeId typeId)
{
    if (typeId == CharacterAppliedCollectionTypeId)
        return EncodeWardrobeSlots({});
    return "-";
}

void LogWardrobe(std::string_view event, AccountId account, AccountSessionId sessionId,
    Sc2Message const& message, std::string_view status, std::uint32_t copper,
    std::uint32_t warningMask, std::uint64_t revision, std::string_view source)
{
    LOG_INFO("module.solocollections.wardrobe",
        "event={} account={} character={} request={} op={} slots={} entries={} "
        "status={} copper={} warning={} revision={} source={}",
        event, account.Value(), sessionId.Value(), message.RequestId, message.Op,
        static_cast<unsigned>(message.SlotCount), message.Entries, status, copper,
        warningMask, revision, source);
}

Sc2CategoryDefinition const* FindCategory(std::vector<Sc2CategoryDefinition> const& categories,
    CollectionTypeId typeId)
{
    for (Sc2CategoryDefinition const& category : categories)
        if (category.TypeId == typeId)
            return &category;
    return nullptr;
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

void Sc2Server::SetRawSnapshot(AccountSessionId sessionId, CollectionTypeId typeId,
    std::uint64_t revision, std::string payload)
{
    std::scoped_lock lock(_mutex);
    auto session = _sessions.find(sessionId);
    if (session == _sessions.end() || !typeId.IsValid())
        return;
    session->second.RawSnapshots[typeId] = RawSnapshotState { revision, std::move(payload) };
}

void Sc2Server::QueueRawSnapshotReplace(AccountSessionId sessionId, CollectionTypeId typeId,
    std::uint64_t revision, std::string payload)
{
    std::scoped_lock lock(_mutex);
    auto session = _sessions.find(sessionId);
    if (session == _sessions.end() || !session->second.Active || !typeId.IsValid())
        return;
    if (!ClientBuildHasWardrobe(session->second.ClientBuild))
        return;
    session->second.RawSnapshots[typeId] = RawSnapshotState { revision, payload };
    QueueRawCategorySnapshot(session->second, typeId, revision, std::move(payload));
}

void Sc2Server::QueueRawSnapshotReplaceForAccount(AccountId accountId, CollectionTypeId typeId,
    std::uint64_t revision, std::string payload)
{
    std::scoped_lock lock(_mutex);
    if (!accountId.IsValid() || !typeId.IsValid())
        return;
    for (auto& [sessionId, session] : _sessions)
    {
        (void)sessionId;
        if (session.Account != accountId)
            continue;
        session.RawSnapshots[typeId] = RawSnapshotState { revision, payload };
        if (!session.Active || !ClientBuildHasWardrobe(session.ClientBuild))
            continue;
        QueueRawCategorySnapshot(session, typeId, revision, payload);
    }
}

void Sc2Server::QueueOwnedSnapshotReplaceForAccount(AccountId accountId, CollectionTypeId typeId,
    CollectionRevision revision)
{
    std::scoped_lock lock(_mutex);
    Sc2CategoryDefinition const* category = FindCategory(_categories, typeId);
    if (!accountId.IsValid() || !category || !revision.IsValid())
        return;
    std::optional<std::vector<CollectionId>> owned = _cache.OwnedByType(accountId, typeId);
    if (!owned)
        return;
    for (auto& [sessionId, session] : _sessions)
    {
        (void)sessionId;
        if (!session.Active || session.Account != accountId || !CategoryVisible(session, *category))
            continue;
        QueueCategorySnapshot(session, *category, revision.Value(), *owned);
    }
}

void Sc2Server::OnDerivedOwnedChanged(AccountId accountId, CollectionTypeId typeId,
    std::vector<CollectionId> owned, CollectionRevision revision)
{
    std::scoped_lock lock(_mutex);
    std::sort(owned.begin(), owned.end());
    owned.erase(std::unique(owned.begin(), owned.end()), owned.end());
    for (auto& [sessionId, session] : _sessions)
    {
        (void)sessionId;
        if (!session.Active || session.Account != accountId)
            continue;
        std::vector<CollectionId> previous = session.ExternalOwned[typeId];
        std::sort(previous.begin(), previous.end());
        std::vector<CollectionId> added;
        std::vector<CollectionId> removed;
        std::set_difference(owned.begin(), owned.end(), previous.begin(), previous.end(),
            std::back_inserter(added));
        std::set_difference(previous.begin(), previous.end(), owned.begin(), owned.end(),
            std::back_inserter(removed));
        auto queueDelta = [&](CollectionId collectionId, std::string operation)
        {
            Sc2Message message;
            message.Kind = Sc2MessageKind::Delta;
            message.SessionNonce = session.Nonce;
            message.TypeId = typeId.Value();
            message.Revision = revision.Value();
            message.Operation = std::move(operation);
            message.CollectionId = collectionId.Value();
            Queue(session, std::move(message));
        };
        for (CollectionId collectionId : added)
            queueDelta(collectionId, "A");
        for (CollectionId collectionId : removed)
            queueDelta(collectionId, "R");
        session.ExternalOwned[typeId] = owned;
    }
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

bool Sc2Server::ConsumeBucket(TokenBucket& bucket, double capacity, double rate, std::uint64_t nowMs)
{
    if (nowMs > bucket.LastRefillMs)
    {
        double elapsedSeconds = static_cast<double>(nowMs - bucket.LastRefillMs) / 1000.0;
        bucket.Tokens = std::min(capacity, bucket.Tokens + elapsedSeconds * rate);
        bucket.LastRefillMs = nowMs;
    }
    if (bucket.Tokens < 1.0)
        return false;
    bucket.Tokens -= 1.0;
    return true;
}

bool Sc2Server::CategoryVisible(SessionState const& session, Sc2CategoryDefinition const& category) const
{
    if (!category.Enabled)
        return false;
    if (category.TypeId == CharacterAppliedCollectionTypeId ||
        category.TypeId == AccountOutfitCollectionTypeId)
        return ClientBuildHasWardrobe(session.ClientBuild);
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
        if (!CategoryVisible(session, category))
            continue;
        ++categoryCount;
        if (category.TypeId.Value() >= 1 && category.TypeId.Value() <= 32)
            flags |= (std::uint32_t { 1 } << (category.TypeId.Value() - 1));
    }
    std::ostringstream flagStream;
    flagStream << std::hex << std::setfill('0') << std::setw(8) << flags;

    Sc2Message acknowledgement;
    acknowledgement.Kind = Sc2MessageKind::HelloAck;
    acknowledgement.ProtocolVersion = Sc2ProtocolVersion;
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
        if (!CategoryVisible(session, category))
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
    auto started = std::chrono::steady_clock::now();
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
    std::uint64_t elapsedMicroseconds = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started).count());
    ++_diagnostics.SnapshotTransfers;
    _diagnostics.SnapshotChunks += chunks.size();
    _diagnostics.SnapshotPayloadBytes += payload.size();
    _diagnostics.LastSnapshotQueueMicroseconds = elapsedMicroseconds;
    _diagnostics.MaxSnapshotQueueMicroseconds = std::max(
        _diagnostics.MaxSnapshotQueueMicroseconds, elapsedMicroseconds);
}

void Sc2Server::QueueRawCategorySnapshot(SessionState& session, Sc2CategoryDefinition const& category)
{
    auto stored = session.RawSnapshots.find(category.TypeId);
    std::uint64_t revision = stored == session.RawSnapshots.end() ? 0 : stored->second.Revision;
    std::string payload = stored == session.RawSnapshots.end() || stored->second.Payload.empty() ?
        DefaultRawPayload(category.TypeId) : stored->second.Payload;
    QueueRawCategorySnapshot(session, category.TypeId, revision, std::move(payload));
}

void Sc2Server::QueueRawCategorySnapshot(SessionState& session, CollectionTypeId typeId,
    std::uint64_t revision, std::string payload)
{
    Sc2CategoryDefinition const* category = FindCategory(_categories, typeId);
    if (!category || !CategoryVisible(session, *category))
        return;
    if (payload.empty())
        payload = DefaultRawPayload(typeId);
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
    begin.TypeId = typeId.Value();
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
        if (!CategoryVisible(session, category))
            continue;
        if (category.RawSnapshot)
        {
            QueueRawCategorySnapshot(session, category);
            continue;
        }
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
    ActionHandler const& actionHandler, WardrobeHandler const& wardrobeHandler)
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
        session.ClientBuild = message.ClientBuild;
        session.ClientMetadataVersion = message.MetadataVersion;
        session.ClientAssetPackVersion = message.AssetPackVersion;
        session.Nonce = NewNonce();
        session.NextTransferId = 1;
        session.ApplyInFlight = false;
        session.Bucket = TokenBucket { BucketCapacity, nowMs };
        session.QuoteBucket = TokenBucket { QuoteBucketCapacity, nowMs };
        session.ApplyBucket = TokenBucket { ApplyBucketCapacity, nowMs };
        session.OutfitBucket = TokenBucket { OutfitBucketCapacity, nowMs };
        session.Replays.clear();
        session.Outbound.clear();
        if (message.ProtocolVersion != Sc2ProtocolVersion)
        {
            QueueError(session, 0, "UNSUPPORTED_VERSION");
            return true;
        }
        QueueHandshake(session);
        QueueCurrentState(session);
        return true;
    }

    if (!session.Active || message.SessionNonce != session.Nonce)
    {
        if (message.Kind == Sc2MessageKind::WardrobeIntent)
            LogWardrobe(message.Op == "QUOTE" ? "wardrobe_quote" : "wardrobe_intent",
                session.Account, sessionId, message,
                session.Active ? "BAD_NONCE" : "INACTIVE", 0, 0, 0, "dropped");
        return true;
    }
    if (!ConsumeToken(session, nowMs))
    {
        QueueError(session, message.RequestId, "RATE_LIMITED");
        if (message.Kind == Sc2MessageKind::WardrobeIntent)
            LogWardrobe(message.Op == "QUOTE" ? "wardrobe_quote" : "wardrobe_intent",
                session.Account, sessionId, message, "RATE_LIMITED", 0, 0, 0, "session_bucket");
        return true;
    }

    if (message.Kind == Sc2MessageKind::WardrobeIntent || message.Kind == Sc2MessageKind::OutfitWrite)
    {
        CleanupReplays(session, nowMs);
        if (session.Replays.contains(message.RequestId))
        {
            QueueError(session, message.RequestId, "REPLAYED_REQUEST");
            if (message.Kind == Sc2MessageKind::WardrobeIntent)
                LogWardrobe(message.Op == "QUOTE" ? "wardrobe_quote" : "wardrobe_intent",
                    session.Account, sessionId, message, "REPLAYED_REQUEST", 0, 0, 0, "replay");
            return true;
        }

        bool quote = message.Kind == Sc2MessageKind::WardrobeIntent && message.Op == "QUOTE";
        bool applyOrClear = message.Kind == Sc2MessageKind::WardrobeIntent && !quote;
        TokenBucket& wardrobeBucket = quote ? session.QuoteBucket :
            (applyOrClear ? session.ApplyBucket : session.OutfitBucket);
        double capacity = quote ? QuoteBucketCapacity :
            (applyOrClear ? ApplyBucketCapacity : OutfitBucketCapacity);
        double rate = quote ? QuoteTokensPerSecond :
            (applyOrClear ? ApplyTokensPerSecond : OutfitTokensPerSecond);
        if (!ConsumeBucket(wardrobeBucket, capacity, rate, nowMs) ||
            (applyOrClear && session.ApplyInFlight))
        {
            if (quote)
            {
                Sc2Message limited;
                limited.Kind = Sc2MessageKind::WardrobeQuote;
                limited.SessionNonce = session.Nonce;
                limited.RequestId = message.RequestId;
                limited.Status = "RATE_LIMITED";
                limited.Copper = 0;
                limited.WarningMask = "00000000";
                Queue(session, std::move(limited));
            }
            else
            {
                Sc2Message limited;
                limited.Kind = Sc2MessageKind::ActionResult;
                limited.SessionNonce = session.Nonce;
                limited.RequestId = message.RequestId;
                limited.Status = "RATE_LIMITED";
                limited.TypeId = applyOrClear ? CharacterAppliedCollectionTypeId.Value() :
                    AccountOutfitCollectionTypeId.Value();
                limited.CollectionId = applyOrClear ? 1 : (message.Uid == 0 ? 1 : message.Uid);
                limited.Revision = 0;
                Queue(session, std::move(limited));
            }
            if (message.Kind == Sc2MessageKind::WardrobeIntent)
                LogWardrobe(quote ? "wardrobe_quote" : "wardrobe_intent",
                    session.Account, sessionId, message, "RATE_LIMITED", 0, 0, 0,
                    applyOrClear && session.ApplyInFlight ? "apply_in_flight" : "wardrobe_bucket");
            return true;
        }

        session.Replays.emplace(message.RequestId, nowMs);
        std::optional<AccountCacheSnapshot> snapshot = _cache.Snapshot(session.Account);
        Sc2WardrobeOutcome outcome;
        outcome.TypeId = applyOrClear ? CharacterAppliedCollectionTypeId.Value() :
            AccountOutfitCollectionTypeId.Value();
        outcome.CollectionId = applyOrClear ? 1 : (message.Uid == 0 ? 1 : message.Uid);
        if (session.ClientMetadataVersion != _metadataVersion)
            outcome.Status = "CATALOG_MISMATCH";
        else if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            outcome.Status = "LOADING";
        else if (snapshot->State == AccountCacheLoadState::Failed)
            outcome.Status = "DB_UNAVAILABLE";
        else if (wardrobeHandler)
        {
            if (applyOrClear)
                session.ApplyInFlight = true;
            outcome = wardrobeHandler(session.Account, message);
            if (applyOrClear)
                session.ApplyInFlight = false;
            if (!IsActionStatus(outcome.Status))
                outcome.Status = "INVALID_REQUEST";
            if (outcome.TypeId == 0)
                outcome.TypeId = applyOrClear ? CharacterAppliedCollectionTypeId.Value() :
                    AccountOutfitCollectionTypeId.Value();
            if (outcome.CollectionId == 0)
                outcome.CollectionId = 1;
        }
        else
            outcome.Status = "UNSUPPORTED";

        if (quote)
        {
            Sc2Message result;
            result.Kind = Sc2MessageKind::WardrobeQuote;
            result.SessionNonce = session.Nonce;
            result.RequestId = message.RequestId;
            result.Status = outcome.Status;
            result.Copper = outcome.Copper;
            result.WarningMask = WarningMaskHex(outcome.WarningMask);
            Queue(session, std::move(result));
        }
        else
        {
            Sc2Message result;
            result.Kind = Sc2MessageKind::ActionResult;
            result.SessionNonce = session.Nonce;
            result.RequestId = message.RequestId;
            result.Status = outcome.Status;
            result.TypeId = outcome.TypeId;
            result.CollectionId = outcome.CollectionId;
            result.Revision = outcome.Revision;
            Queue(session, std::move(result));
        }
        if (message.Kind == Sc2MessageKind::WardrobeIntent)
            LogWardrobe(quote ? "wardrobe_quote" : "wardrobe_intent",
                session.Account, sessionId, message, outcome.Status, outcome.Copper,
                outcome.WarningMask, outcome.Revision,
                session.ClientMetadataVersion != _metadataVersion ? "catalog" :
                    (!snapshot || snapshot->State == AccountCacheLoadState::Loading) ? "loading" :
                    (snapshot->State == AccountCacheLoadState::Failed) ? "store" :
                    (wardrobeHandler ? "handler" : "unsupported"));
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
        if (session.ClientMetadataVersion != _metadataVersion)
            result.Status = "CATALOG_MISMATCH";
        else if (message.ActionId == "PREVIEW" && session.ClientAssetPackVersion != _assetPackVersion)
            result.Status = "ASSET_MISMATCH";
        else if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
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

Sc2ServerDiagnostics Sc2Server::Diagnostics() const
{
    std::scoped_lock lock(_mutex);
    Sc2ServerDiagnostics result = _diagnostics;
    result.SessionCount = _sessions.size();
    for (auto const& [sessionId, session] : _sessions)
    {
        (void)sessionId;
        result.OutboundPacketCount += session.Outbound.size();
    }
    return result;
}

void Sc2Server::RecordSendBatch(
    std::size_t packets, std::size_t bytes, std::uint64_t elapsedMicroseconds)
{
    std::scoped_lock lock(_mutex);
    _diagnostics.SentPackets += packets;
    _diagnostics.SentBytes += bytes;
    _diagnostics.LastSendMicroseconds = elapsedMicroseconds;
    _diagnostics.MaxSendMicroseconds = std::max(
        _diagnostics.MaxSendMicroseconds, elapsedMicroseconds);
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
