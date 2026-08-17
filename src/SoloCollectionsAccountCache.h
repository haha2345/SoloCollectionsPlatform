#ifndef SOLO_COLLECTIONS_ACCOUNT_CACHE_H
#define SOLO_COLLECTIONS_ACCOUNT_CACHE_H

#include "SoloCollectionsTypes.h"

#include <cstddef>
#include <cstdint>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <vector>

namespace SoloCollections
{
enum class AccountCacheLoadState : std::uint8_t
{
    Loading = 1,
    Ready = 2,
    Failed = 3,
};

struct CollectionKey
{
    CollectionTypeId TypeId;
    CollectionId Id;

    friend constexpr bool operator==(CollectionKey const& left, CollectionKey const& right) noexcept
    {
        return left.TypeId == right.TypeId && left.Id == right.Id;
    }

    friend constexpr bool operator<(CollectionKey const& left, CollectionKey const& right) noexcept
    {
        if (left.TypeId != right.TypeId)
            return left.TypeId < right.TypeId;
        return left.Id < right.Id;
    }
};

enum class CollectionDeltaKind : std::uint8_t
{
    Unlock = 1,
    Revoke = 2,
};

struct CollectionDelta
{
    CollectionKey Key;
    CollectionDeltaKind Kind = CollectionDeltaKind::Unlock;
    CollectionRevision Revision;
};

enum class DeltaQueueResult : std::uint8_t
{
    Rejected = 0,
    Deferred = 1,
    Applied = 2,
};

struct AccountSessionOpenResult
{
    bool Accepted = false;
    bool ShouldStartLoad = false;
    LoginGeneration Generation;
    AccountCacheLoadState State = AccountCacheLoadState::Failed;
    CollectionReasonCode Reason = CollectionReasonCode::InvalidArgument;
};

struct AccountCacheSnapshot
{
    AccountCacheLoadState State = AccountCacheLoadState::Failed;
    LoginGeneration Generation;
    std::size_t SessionCount = 0;
    std::size_t PendingDeltaCount = 0;
    CollectionRevision Revision;
    bool EvictionScheduled = false;
};

struct AccountCacheDiagnostics
{
    std::size_t EntryCount = 0;
    std::size_t LoadingCount = 0;
    std::size_t ReadyCount = 0;
    std::size_t FailedCount = 0;
    std::size_t SessionCount = 0;
    std::size_t PendingDeltaCount = 0;
    std::size_t EvictionScheduledCount = 0;
    std::size_t OwnedEntryCount = 0;
    std::size_t ReadyDeltaCount = 0;
    std::uint64_t OpenRequests = 0;
    std::uint64_t CacheHits = 0;
    std::uint64_t CacheMisses = 0;
    std::uint64_t TotalEvictions = 0;
    std::uint64_t EstimatedBytes = 0;
};

// Player hooks can run on map workers while database callbacks and maintenance
// run on the world thread. Every cache entry is therefore protected by one
// explicit mutex; callers never rely on single-player server timing.
class AccountCollectionCache
{
public:
    explicit AccountCollectionCache(std::uint64_t evictionDelayMs = 30'000);

    [[nodiscard]] AccountSessionOpenResult OpenSession(
        AccountId accountId, AccountSessionId sessionId, std::uint64_t nowMs);
    [[nodiscard]] bool CloseSession(
        AccountId accountId, AccountSessionId sessionId, std::uint64_t nowMs);

    [[nodiscard]] bool CompleteLoad(AccountId accountId, LoginGeneration generation,
        std::set<CollectionKey> owned, CollectionRevision revision);
    [[nodiscard]] bool FailLoad(AccountId accountId, LoginGeneration generation);
    [[nodiscard]] std::optional<LoginGeneration> RetryFailed(AccountId accountId);
    [[nodiscard]] std::optional<LoginGeneration> BeginReload(AccountId accountId);

    [[nodiscard]] DeltaQueueResult QueueDelta(AccountId accountId, CollectionDelta delta);
    [[nodiscard]] bool ClearOwnedType(
        AccountId accountId, CollectionTypeId typeId, CollectionRevision revision);
    [[nodiscard]] std::vector<CollectionDelta> DrainReadyDeltas(AccountId accountId);
    [[nodiscard]] std::size_t EvictExpired(std::uint64_t nowMs);

    [[nodiscard]] std::optional<AccountCacheSnapshot> Snapshot(AccountId accountId) const;
    [[nodiscard]] std::optional<std::vector<CollectionId>> OwnedByType(
        AccountId accountId, CollectionTypeId typeId) const;
    [[nodiscard]] AccountCacheDiagnostics Diagnostics() const;
    [[nodiscard]] bool IsOwned(AccountId accountId, CollectionKey const& key) const;

private:
    struct Entry
    {
        AccountCacheLoadState State = AccountCacheLoadState::Loading;
        LoginGeneration Generation;
        std::set<AccountSessionId> Sessions;
        std::set<CollectionKey> Owned;
        std::map<CollectionKey, CollectionDelta> PendingDeltas;
        std::vector<CollectionDelta> ReadyDeltas;
        CollectionRevision Revision;
        std::optional<std::uint64_t> EvictAfterMs;
    };

    [[nodiscard]] LoginGeneration NextGeneration();
    static void ApplyDelta(Entry& entry, CollectionDelta const& delta);

    std::map<AccountId, Entry> _entries;
    mutable std::mutex _mutex;
    std::uint64_t _evictionDelayMs;
    std::uint64_t _lastGeneration = 0;
    std::uint64_t _openRequests = 0;
    std::uint64_t _cacheHits = 0;
    std::uint64_t _cacheMisses = 0;
    std::uint64_t _totalEvictions = 0;
};

AccountCollectionCache& GetAccountCollectionCache();
}

#endif
