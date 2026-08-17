#include "SoloCollectionsAccountCache.h"

#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

namespace SoloCollections
{
AccountCollectionCache::AccountCollectionCache(std::uint64_t evictionDelayMs)
    : _evictionDelayMs(evictionDelayMs)
{
}

LoginGeneration AccountCollectionCache::NextGeneration()
{
    if (_lastGeneration == std::numeric_limits<std::uint64_t>::max())
        throw std::overflow_error("SoloCollections login generation exhausted.");
    return LoginGeneration(++_lastGeneration);
}

AccountSessionOpenResult AccountCollectionCache::OpenSession(
    AccountId accountId, AccountSessionId sessionId, std::uint64_t /*nowMs*/)
{
    std::scoped_lock lock(_mutex);
    ++_openRequests;
    if (!accountId.IsValid() || !sessionId.IsValid())
        return {};

    auto existing = _entries.find(accountId);
    if (existing != _entries.end())
    {
        ++_cacheHits;
        existing->second.Sessions.insert(sessionId);
        existing->second.EvictAfterMs.reset();
        return { true, false, existing->second.Generation, existing->second.State, CollectionReasonCode::Ok };
    }

    ++_cacheMisses;
    Entry entry;
    entry.Generation = NextGeneration();
    entry.Sessions.insert(sessionId);
    LoginGeneration generation = entry.Generation;
    _entries.emplace(accountId, std::move(entry));
    return { true, true, generation, AccountCacheLoadState::Loading, CollectionReasonCode::Ok };
}

bool AccountCollectionCache::CloseSession(
    AccountId accountId, AccountSessionId sessionId, std::uint64_t nowMs)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.Sessions.erase(sessionId) == 0)
        return false;

    if (entry->second.Sessions.empty())
    {
        if (nowMs > std::numeric_limits<std::uint64_t>::max() - _evictionDelayMs)
            entry->second.EvictAfterMs = std::numeric_limits<std::uint64_t>::max();
        else
            entry->second.EvictAfterMs = nowMs + _evictionDelayMs;
    }
    return true;
}

void AccountCollectionCache::ApplyDelta(Entry& entry, CollectionDelta const& delta)
{
    if (delta.Kind == CollectionDeltaKind::Unlock)
        entry.Owned.insert(delta.Key);
    else
        entry.Owned.erase(delta.Key);

    if (delta.Revision.Value() > entry.Revision.Value())
        entry.Revision = delta.Revision;
}

bool AccountCollectionCache::CompleteLoad(AccountId accountId, LoginGeneration generation,
    std::set<CollectionKey> owned, CollectionRevision revision)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.Generation != generation ||
        entry->second.State != AccountCacheLoadState::Loading)
        return false;

    entry->second.Owned = std::move(owned);
    entry->second.Revision = revision;
    std::vector<CollectionDelta> pending;
    pending.reserve(entry->second.PendingDeltas.size());
    for (auto const& [key, delta] : entry->second.PendingDeltas)
    {
        (void)key;
        pending.push_back(delta);
    }
    std::sort(pending.begin(), pending.end(), [](CollectionDelta const& left, CollectionDelta const& right)
    {
        if (left.Revision != right.Revision)
            return left.Revision < right.Revision;
        return left.Key < right.Key;
    });
    for (CollectionDelta const& delta : pending)
    {
        if (delta.Revision.Value() > revision.Value())
        {
            ApplyDelta(entry->second, delta);
            entry->second.ReadyDeltas.push_back(delta);
        }
    }
    entry->second.PendingDeltas.clear();
    entry->second.State = AccountCacheLoadState::Ready;
    return true;
}

bool AccountCollectionCache::FailLoad(AccountId accountId, LoginGeneration generation)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.Generation != generation ||
        entry->second.State != AccountCacheLoadState::Loading)
        return false;

    entry->second.State = AccountCacheLoadState::Failed;
    return true;
}

std::optional<LoginGeneration> AccountCollectionCache::RetryFailed(AccountId accountId)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.State != AccountCacheLoadState::Failed ||
        entry->second.Sessions.empty())
        return std::nullopt;

    entry->second.Generation = NextGeneration();
    entry->second.State = AccountCacheLoadState::Loading;
    entry->second.Owned.clear();
    entry->second.Revision = CollectionRevision();
    return entry->second.Generation;
}

std::optional<LoginGeneration> AccountCollectionCache::BeginReload(AccountId accountId)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.Sessions.empty())
        return std::nullopt;

    entry->second.Generation = NextGeneration();
    entry->second.State = AccountCacheLoadState::Loading;
    entry->second.Owned.clear();
    entry->second.ReadyDeltas.clear();
    entry->second.Revision = CollectionRevision();
    return entry->second.Generation;
}

DeltaQueueResult AccountCollectionCache::QueueDelta(AccountId accountId, CollectionDelta delta)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || !delta.Key.TypeId.IsValid() || !delta.Key.Id.IsValid() ||
        !delta.Revision.IsValid())
        return DeltaQueueResult::Rejected;

    if (entry->second.State != AccountCacheLoadState::Ready)
    {
        auto pending = entry->second.PendingDeltas.find(delta.Key);
        if (pending != entry->second.PendingDeltas.end() &&
            pending->second.Revision.Value() > delta.Revision.Value())
            return DeltaQueueResult::Rejected;
        entry->second.PendingDeltas[delta.Key] = std::move(delta);
        return DeltaQueueResult::Deferred;
    }

    if (delta.Revision.Value() < entry->second.Revision.Value())
        return DeltaQueueResult::Rejected;

    ApplyDelta(entry->second, delta);
    entry->second.ReadyDeltas.push_back(std::move(delta));
    return DeltaQueueResult::Applied;
}

bool AccountCollectionCache::ClearOwnedType(
    AccountId accountId, CollectionTypeId typeId, CollectionRevision revision)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.State != AccountCacheLoadState::Ready ||
        !typeId.IsValid() || !revision.IsValid())
        return false;
    if (revision.Value() < entry->second.Revision.Value())
        return false;

    for (auto owned = entry->second.Owned.begin(); owned != entry->second.Owned.end();)
    {
        if (owned->TypeId == typeId)
            owned = entry->second.Owned.erase(owned);
        else
            ++owned;
    }
    for (auto pending = entry->second.PendingDeltas.begin();
        pending != entry->second.PendingDeltas.end();)
    {
        if (pending->first.TypeId == typeId)
            pending = entry->second.PendingDeltas.erase(pending);
        else
            ++pending;
    }
    entry->second.Revision = revision;
    return true;
}

std::vector<CollectionDelta> AccountCollectionCache::DrainReadyDeltas(AccountId accountId)
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.State != AccountCacheLoadState::Ready)
        return {};

    std::vector<CollectionDelta> deltas = std::move(entry->second.ReadyDeltas);
    entry->second.ReadyDeltas.clear();
    return deltas;
}

std::size_t AccountCollectionCache::EvictExpired(std::uint64_t nowMs)
{
    std::scoped_lock lock(_mutex);
    std::size_t evicted = 0;
    for (auto entry = _entries.begin(); entry != _entries.end();)
    {
        if (entry->second.Sessions.empty() && entry->second.EvictAfterMs &&
            *entry->second.EvictAfterMs <= nowMs)
        {
            entry = _entries.erase(entry);
            ++evicted;
        }
        else
            ++entry;
    }
    _totalEvictions += evicted;
    return evicted;
}

std::optional<AccountCacheSnapshot> AccountCollectionCache::Snapshot(AccountId accountId) const
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end())
        return std::nullopt;

    return AccountCacheSnapshot {
        entry->second.State,
        entry->second.Generation,
        entry->second.Sessions.size(),
        entry->second.PendingDeltas.size(),
        entry->second.Revision,
        entry->second.EvictAfterMs.has_value(),
    };
}

std::optional<std::vector<CollectionId>> AccountCollectionCache::OwnedByType(
    AccountId accountId, CollectionTypeId typeId) const
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    if (entry == _entries.end() || entry->second.State != AccountCacheLoadState::Ready || !typeId.IsValid())
        return std::nullopt;

    std::vector<CollectionId> owned;
    for (CollectionKey const& key : entry->second.Owned)
        if (key.TypeId == typeId)
            owned.push_back(key.Id);
    return owned;
}

AccountCacheDiagnostics AccountCollectionCache::Diagnostics() const
{
    std::scoped_lock lock(_mutex);
    AccountCacheDiagnostics diagnostics;
    diagnostics.EntryCount = _entries.size();
    diagnostics.OpenRequests = _openRequests;
    diagnostics.CacheHits = _cacheHits;
    diagnostics.CacheMisses = _cacheMisses;
    diagnostics.TotalEvictions = _totalEvictions;
    diagnostics.EstimatedBytes = sizeof(*this) + (_entries.size() * sizeof(Entry));
    for (auto const& [accountId, entry] : _entries)
    {
        (void)accountId;
        switch (entry.State)
        {
            case AccountCacheLoadState::Loading: ++diagnostics.LoadingCount; break;
            case AccountCacheLoadState::Ready: ++diagnostics.ReadyCount; break;
            case AccountCacheLoadState::Failed: ++diagnostics.FailedCount; break;
        }
        diagnostics.SessionCount += entry.Sessions.size();
        diagnostics.PendingDeltaCount += entry.PendingDeltas.size();
        diagnostics.OwnedEntryCount += entry.Owned.size();
        diagnostics.ReadyDeltaCount += entry.ReadyDeltas.size();
        diagnostics.EstimatedBytes += entry.Sessions.size() * sizeof(AccountSessionId);
        diagnostics.EstimatedBytes += entry.Owned.size() * sizeof(CollectionKey);
        diagnostics.EstimatedBytes += entry.PendingDeltas.size() * sizeof(CollectionDelta);
        diagnostics.EstimatedBytes += entry.ReadyDeltas.size() * sizeof(CollectionDelta);
        if (entry.EvictAfterMs)
            ++diagnostics.EvictionScheduledCount;
    }
    return diagnostics;
}

bool AccountCollectionCache::IsOwned(AccountId accountId, CollectionKey const& key) const
{
    std::scoped_lock lock(_mutex);
    auto entry = _entries.find(accountId);
    return entry != _entries.end() && entry->second.State == AccountCacheLoadState::Ready &&
        entry->second.Owned.contains(key);
}

AccountCollectionCache& GetAccountCollectionCache()
{
    static AccountCollectionCache cache;
    return cache;
}
}
