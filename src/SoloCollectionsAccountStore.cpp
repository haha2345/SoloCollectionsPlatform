#include "SoloCollectionsAccountStore.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsMountCatalog.h"

#include "AsyncCallbackProcessor.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "QueryResult.h"
#include "StringFormat.h"

#include <algorithm>
#include <chrono>
#include <limits>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace SoloCollections
{
namespace
{
struct DeferredLoad
{
    AccountId Account;
    std::uint32_t PlayerGuid = 0;
    LoginGeneration Generation;
};

struct PreferenceTypeMapping
{
    CollectionTypeId ProjectionType;
    CollectionTypeId OwnedType;
};

[[nodiscard]] std::optional<PreferenceTypeMapping> PreferenceMappingForProjection(
    CollectionTypeId projectionType)
{
    if (projectionType == MountFavoriteCollectionTypeId)
        return PreferenceTypeMapping { MountFavoriteCollectionTypeId, MountCollectionTypeId };
    if (projectionType == CompanionFavoriteCollectionTypeId)
        return PreferenceTypeMapping { CompanionFavoriteCollectionTypeId, CompanionCollectionTypeId };
    return std::nullopt;
}

[[nodiscard]] std::uint16_t StableMutationKind(CollectionMutationKind kind)
{
    return static_cast<std::uint16_t>(kind);
}

[[nodiscard]] std::uint16_t StableSourceKind(CollectionSourceKind kind)
{
    return static_cast<std::uint16_t>(kind);
}
}

class AccountCollectionStore::Impl
{
public:
    void Initialize()
    {
        if (_initialized)
            return;

        _initialized = true;
        std::string schemaQuery =
            "SELECT CASE WHEN COUNT(*) = 5 THEN 1 ELSE 0 END "
            "FROM information_schema.tables "
            "WHERE table_schema = DATABASE() AND table_name IN "
            "('sc_account_state','sc_collection_unlock','sc_collection_audit','sc_migration_marker',"
            "'solo_collection_preference')";
        _queryCallbacks.AddCallback(CharacterDatabase.AsyncQuery(schemaQuery).WithCallback(
            [this](QueryResult result)
            {
                bool ready = result && (*result)[0].Get<uint64>() == 1;
                _diagnostics.SchemaState = ready ? AccountStoreSchemaState::Ready : AccountStoreSchemaState::Failed;
                if (!ready)
                {
                    LOG_ERROR("module.solocollections.database",
                        "event=schema_check result=failed expected_version={} pending_loads={}",
                        AccountStoreSchemaVersion, _deferredLoads.size());
                    for (auto const& [accountId, load] : _deferredLoads)
                    {
                        (void)accountId;
                        (void)GetAccountCollectionCache().FailLoad(load.Account, load.Generation);
                        ++_diagnostics.FailedLoads;
                    }
                    _deferredLoads.clear();
                    return;
                }

                LOG_INFO("module.solocollections.store", "event=schema_check result=ready schema_version={}",
                    AccountStoreSchemaVersion);
                std::vector<DeferredLoad> deferred;
                deferred.reserve(_deferredLoads.size());
                for (auto const& [accountId, load] : _deferredLoads)
                {
                    (void)accountId;
                    deferred.push_back(load);
                }
                _deferredLoads.clear();
                for (DeferredLoad const& load : deferred)
                    BeginLoadNow(load);
            }));
    }

    void Update()
    {
        _queryCallbacks.ProcessReadyCallbacks();
        _transactionCallbacks.ProcessReadyCallbacks();
    }

    void BeginLoad(DeferredLoad load)
    {
        if (!load.Account.IsValid() || !load.Generation.IsValid())
            return;

        if (_diagnostics.SchemaState == AccountStoreSchemaState::Checking)
        {
            _deferredLoads[load.Account] = load;
            return;
        }

        if (_diagnostics.SchemaState == AccountStoreSchemaState::Failed)
        {
            (void)GetAccountCollectionCache().FailLoad(load.Account, load.Generation);
            ++_diagnostics.FailedLoads;
            return;
        }

        BeginLoadNow(load);
    }

    void BeginLoadNow(DeferredLoad load)
    {
        if (!_loadingAccounts.insert(load.Account).second)
            return;

        std::string query = Acore::StringFormat(
            "SELECT 0 AS row_kind, COALESCE(s.revision, 0) AS revision, 0 AS type_id, 0 AS collection_id "
            "FROM (SELECT 1) seed LEFT JOIN sc_account_state s ON s.account_id = {} "
            "UNION ALL "
            "SELECT 1 AS row_kind, u.revision, u.type_id, u.collection_id "
            "FROM sc_collection_unlock u WHERE u.account_id = {} "
            "UNION ALL "
            "SELECT 2 AS row_kind, COALESCE(s.revision, 0) AS revision, "
            "CASE p.type_id WHEN 10 THEN 16 WHEN 11 THEN 17 END AS type_id, p.collection_id "
            "FROM solo_collection_preference p "
            "LEFT JOIN sc_account_state s ON s.account_id = p.account_id "
            "WHERE p.account_id = {} AND p.type_id IN (10, 11) AND p.favorite = 1 "
            "ORDER BY row_kind, type_id, collection_id",
            load.Account.Value(), load.Account.Value(), load.Account.Value());

        ++_diagnostics.LoadQueryCount;
        auto loadStarted = std::chrono::steady_clock::now();
        _queryCallbacks.AddCallback(CharacterDatabase.AsyncQuery(query).WithCallback(
            [this, accountId = load.Account, playerGuid = load.PlayerGuid, generation = load.Generation,
                loadStarted](QueryResult result)
            {
                std::uint64_t elapsedMicroseconds = static_cast<std::uint64_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(
                        std::chrono::steady_clock::now() - loadStarted).count());
                _diagnostics.LastLoadMicroseconds = elapsedMicroseconds;
                _diagnostics.MaxLoadMicroseconds = std::max(
                    _diagnostics.MaxLoadMicroseconds, elapsedMicroseconds);
                _diagnostics.TotalLoadMicroseconds += elapsedMicroseconds;
                _loadingAccounts.erase(accountId);
                std::set<CollectionKey> owned;
                CollectionRevision revision;
                bool valid = static_cast<bool>(result);
                bool sawSentinel = false;
                std::size_t loadedPreferenceRows = 0;
                if (result)
                {
                    do
                    {
                        Field* fields = result->Fetch();
                        uint64 rowKind = fields[0].Get<uint64>();
                        uint64 rowRevision = fields[1].Get<uint64>();
                        if (rowKind == 0)
                        {
                            if (sawSentinel)
                            {
                                valid = false;
                                break;
                            }
                            sawSentinel = true;
                            revision = CollectionRevision(rowRevision);
                            continue;
                        }

                        uint64 typeId = fields[2].Get<uint64>();
                        uint64 collectionId = fields[3].Get<uint64>();
                        if ((rowKind != 1 && rowKind != 2) || typeId == 0 ||
                            typeId > std::numeric_limits<std::uint16_t>::max() ||
                            collectionId == 0 || collectionId > std::numeric_limits<std::uint32_t>::max() ||
                            rowRevision > revision.Value() ||
                            (rowKind == 2 && !PreferenceMappingForProjection(CollectionTypeId(
                                static_cast<std::uint16_t>(typeId))).has_value()))
                        {
                            valid = false;
                            break;
                        }
                        CollectionKey key {
                            CollectionTypeId(static_cast<std::uint16_t>(typeId)),
                            CollectionId(static_cast<std::uint32_t>(collectionId))
                        };
                        owned.insert(key);
                        if (rowKind == 2)
                            ++loadedPreferenceRows;
                    } while (result->NextRow());
                }

                if (!valid || !sawSentinel)
                {
                    (void)GetAccountCollectionCache().FailLoad(accountId, generation);
                    ++_diagnostics.FailedLoads;
                    LOG_ERROR("module.solocollections.database",
                        "event=account_load result=failed account={} character={} generation={}",
                        accountId.Value(), playerGuid, generation.Value());
                    return;
                }

                std::size_t loadedUnlockRows = owned.size();
                bool accepted = GetAccountCollectionCache().CompleteLoad(
                    accountId, generation, std::move(owned), revision);
                if (accepted)
                {
                    _diagnostics.LoadedUnlockRows += loadedUnlockRows - loadedPreferenceRows;
                    _diagnostics.LoadedPreferenceRows += loadedPreferenceRows;
                    ++_diagnostics.SuccessfulLoads;
                    LOG_INFO("module.solocollections.performance",
                        "event=account_load result=ready account={} character={} generation={} revision={} "
                        "queries=1 unlock_rows={} preference_rows={} elapsed_us={}",
                        accountId.Value(), playerGuid, generation.Value(), revision.Value(),
                        loadedUnlockRows - loadedPreferenceRows, loadedPreferenceRows, elapsedMicroseconds);
                }
                else
                {
                    LOG_DEBUG("module.solocollections.store",
                        "event=account_load result=stale account={} character={} generation={}",
                        accountId.Value(), playerGuid, generation.Value());
                }
            }));
    }

    MutationStartResult BeginMutation(AccountCollectionMutation mutation)
    {
        if (!_writesEnabled)
            return { false, CollectionReasonCode::ReadOnly, {} };
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready || !mutation.Account.IsValid() ||
            !mutation.Generation.IsValid() || !mutation.Key.TypeId.IsValid() || !mutation.Key.Id.IsValid() ||
            StableSourceKind(mutation.SourceKind) == 0)
            return { false, _diagnostics.SchemaState == AccountStoreSchemaState::Ready ?
                CollectionReasonCode::InvalidArgument : CollectionReasonCode::DatabaseError, {} };

        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(mutation.Account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready || snapshot->Generation != mutation.Generation)
            return { false, CollectionReasonCode::NotReady, {} };
        if (_pendingMutations.contains(mutation.Account))
            return { false, CollectionReasonCode::PendingOperation, {} };

        bool owned = GetAccountCollectionCache().IsOwned(mutation.Account, mutation.Key);
        if (mutation.Kind == CollectionMutationKind::Grant && owned)
        {
            ++_diagnostics.DuplicateGrantRequests;
            return { false, CollectionReasonCode::AlreadyOwned, snapshot->Revision };
        }
        if (mutation.Kind == CollectionMutationKind::Revoke && !owned)
            return { false, CollectionReasonCode::NotOwned, snapshot->Revision };
        if (snapshot->Revision.Value() == std::numeric_limits<std::uint64_t>::max())
            return { false, CollectionReasonCode::RevisionConflict, snapshot->Revision };

        CollectionRevision nextRevision(snapshot->Revision.Value() + 1);
        CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
        transaction->Append(
            "INSERT INTO sc_account_state(account_id, revision, schema_version) VALUES ({}, 0, 2) "
            "ON DUPLICATE KEY UPDATE schema_version = schema_version",
            mutation.Account.Value());

        bool requireExisting = mutation.Kind == CollectionMutationKind::Revoke;
        transaction->Append(
            "UPDATE sc_account_state SET revision = IF(revision = {} AND {}EXISTS("
            "SELECT 1 FROM sc_collection_unlock u WHERE u.account_id = {} AND u.type_id = {} AND u.collection_id = {}"
            "), {}, NULL) WHERE account_id = {}",
            snapshot->Revision.Value(), requireExisting ? "" : "NOT ", mutation.Account.Value(),
            mutation.Key.TypeId.Value(), mutation.Key.Id.Value(), nextRevision.Value(), mutation.Account.Value());

        if (mutation.Kind == CollectionMutationKind::Grant)
        {
            transaction->Append(
                "INSERT INTO sc_collection_unlock(account_id, type_id, collection_id, revision, source_kind, source_id, character_guid) "
                "VALUES ({}, {}, {}, {}, {}, {}, {})",
                mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(), nextRevision.Value(),
                StableSourceKind(mutation.SourceKind), mutation.SourceId, mutation.CharacterGuid);
        }
        else
        {
            transaction->Append(
                "DELETE FROM sc_collection_unlock WHERE account_id = {} AND type_id = {} AND collection_id = {}",
                mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value());
        }

        transaction->Append(
            "INSERT INTO sc_collection_audit(account_id, type_id, collection_id, action_kind, source_kind, source_id, "
            "character_guid, actor_account_id, actor_guid, revision, result_code) "
            "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
            mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
            StableMutationKind(mutation.Kind), StableSourceKind(mutation.SourceKind), mutation.SourceId,
            mutation.CharacterGuid, mutation.ActorAccountId, mutation.ActorGuid, nextRevision.Value(),
            ToStableReasonCode(CollectionReasonCode::Ok));

        _pendingMutations.emplace(mutation.Account, mutation);
        TransactionCallback& callback = _transactionCallbacks.AddCallback(
            CharacterDatabase.AsyncCommitTransaction(transaction));
        callback.AfterComplete(
            [this, mutation, nextRevision](bool committed)
            {
                _pendingMutations.erase(mutation.Account);
                if (!committed)
                {
                    ++_diagnostics.FailedMutations;
                    LOG_ERROR("module.solocollections.database",
                        "event=mutation_commit result=failed account={} type={} collection={} generation={} revision={}",
                        mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                        mutation.Generation.Value(), nextRevision.Value());
                    if (_eventSink)
                        _eventSink->OnCollectionMutationFailed(
                            mutation.Account, mutation.Key, CollectionReasonCode::DatabaseError);
                    return;
                }

                CollectionDelta delta {
                    mutation.Key,
                    mutation.Kind == CollectionMutationKind::Grant ?
                        CollectionDeltaKind::Unlock : CollectionDeltaKind::Revoke,
                    nextRevision
                };
                std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(mutation.Account);
                DeltaQueueResult cacheResult = DeltaQueueResult::Rejected;
                if (snapshot && snapshot->Generation == mutation.Generation)
                    cacheResult = GetAccountCollectionCache().QueueDelta(mutation.Account, delta);

                ++_diagnostics.SuccessfulMutations;
                LOG_INFO("module.solocollections.store",
                    "event=mutation_commit result=success account={} type={} collection={} generation={} revision={} cache_result={}",
                    mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                    mutation.Generation.Value(), nextRevision.Value(), static_cast<std::uint8_t>(cacheResult));
                if (_eventSink && cacheResult != DeltaQueueResult::Rejected)
                    _eventSink->OnCollectionDeltaCommitted(mutation.Account, delta);
            });

        return { true, CollectionReasonCode::Ok, nextRevision };
    }

    MutationStartResult BeginPreferenceMutation(AccountCollectionMutation mutation)
    {
        if (!_writesEnabled)
            return { false, CollectionReasonCode::ReadOnly, {} };
        std::optional<PreferenceTypeMapping> mapping = PreferenceMappingForProjection(mutation.Key.TypeId);
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready || !mutation.Account.IsValid() ||
            !mutation.Generation.IsValid() || !mapping || !mutation.Key.Id.IsValid() ||
            StableSourceKind(mutation.SourceKind) == 0)
            return { false, _diagnostics.SchemaState == AccountStoreSchemaState::Ready ?
                CollectionReasonCode::InvalidArgument : CollectionReasonCode::DatabaseError, {} };

        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(mutation.Account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready || snapshot->Generation != mutation.Generation)
            return { false, CollectionReasonCode::NotReady, {} };
        if (_pendingMutations.contains(mutation.Account))
            return { false, CollectionReasonCode::PendingOperation, {} };

        CollectionKey ownedKey { mapping->OwnedType, mutation.Key.Id };
        if (!GetAccountCollectionCache().IsOwned(mutation.Account, ownedKey))
            return { false, CollectionReasonCode::NotOwned, snapshot->Revision };

        bool favorite = GetAccountCollectionCache().IsOwned(mutation.Account, mutation.Key);
        if ((mutation.Kind == CollectionMutationKind::Grant && favorite) ||
            (mutation.Kind == CollectionMutationKind::Revoke && !favorite))
            return { true, CollectionReasonCode::Ok, snapshot->Revision };
        if (snapshot->Revision.Value() == std::numeric_limits<std::uint64_t>::max())
            return { false, CollectionReasonCode::RevisionConflict, snapshot->Revision };

        CollectionRevision nextRevision(snapshot->Revision.Value() + 1);
        CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
        transaction->Append(
            "INSERT INTO sc_account_state(account_id, revision, schema_version) VALUES ({}, 0, 2) "
            "ON DUPLICATE KEY UPDATE schema_version = GREATEST(schema_version, 2)",
            mutation.Account.Value());

        bool requireExisting = mutation.Kind == CollectionMutationKind::Revoke;
        transaction->Append(
            "UPDATE sc_account_state SET revision = IF(revision = {} AND {}EXISTS("
            "SELECT 1 FROM solo_collection_preference p WHERE p.account_id = {} AND p.type_id = {} "
            "AND p.collection_id = {} AND p.favorite = 1), {}, NULL) WHERE account_id = {}",
            snapshot->Revision.Value(), requireExisting ? "" : "NOT ", mutation.Account.Value(),
            mapping->OwnedType.Value(), mutation.Key.Id.Value(), nextRevision.Value(), mutation.Account.Value());

        if (mutation.Kind == CollectionMutationKind::Grant)
        {
            transaction->Append(
                "INSERT INTO solo_collection_preference(account_id, type_id, collection_id, favorite) "
                "VALUES ({}, {}, {}, 1)",
                mutation.Account.Value(), mapping->OwnedType.Value(), mutation.Key.Id.Value());
        }
        else
        {
            transaction->Append(
                "DELETE FROM solo_collection_preference WHERE account_id = {} AND type_id = {} AND collection_id = {}",
                mutation.Account.Value(), mapping->OwnedType.Value(), mutation.Key.Id.Value());
        }

        transaction->Append(
            "INSERT INTO sc_collection_audit(account_id, type_id, collection_id, action_kind, source_kind, source_id, "
            "character_guid, actor_account_id, actor_guid, revision, result_code) "
            "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
            mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
            StableMutationKind(mutation.Kind), StableSourceKind(mutation.SourceKind), mutation.SourceId,
            mutation.CharacterGuid, mutation.ActorAccountId, mutation.ActorGuid, nextRevision.Value(),
            ToStableReasonCode(CollectionReasonCode::Ok));

        _pendingMutations.emplace(mutation.Account, mutation);
        TransactionCallback& callback = _transactionCallbacks.AddCallback(
            CharacterDatabase.AsyncCommitTransaction(transaction));
        callback.AfterComplete(
            [this, mutation, nextRevision](bool committed)
            {
                _pendingMutations.erase(mutation.Account);
                if (!committed)
                {
                    ++_diagnostics.FailedMutations;
                    LOG_ERROR("module.solocollections.database",
                        "event=preference_commit result=failed account={} type={} collection={} generation={} revision={}",
                        mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                        mutation.Generation.Value(), nextRevision.Value());
                    if (_eventSink)
                        _eventSink->OnCollectionMutationFailed(
                            mutation.Account, mutation.Key, CollectionReasonCode::DatabaseError);
                    return;
                }

                CollectionDelta delta {
                    mutation.Key,
                    mutation.Kind == CollectionMutationKind::Grant ?
                        CollectionDeltaKind::Unlock : CollectionDeltaKind::Revoke,
                    nextRevision
                };
                std::optional<AccountCacheSnapshot> current = GetAccountCollectionCache().Snapshot(mutation.Account);
                DeltaQueueResult cacheResult = DeltaQueueResult::Rejected;
                if (current && current->Generation == mutation.Generation)
                    cacheResult = GetAccountCollectionCache().QueueDelta(mutation.Account, delta);

                ++_diagnostics.SuccessfulMutations;
                LOG_INFO("module.solocollections.store",
                    "event=preference_commit result=success account={} type={} collection={} generation={} revision={} cache_result={}",
                    mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                    mutation.Generation.Value(), nextRevision.Value(), static_cast<std::uint8_t>(cacheResult));
                if (_eventSink && cacheResult != DeltaQueueResult::Rejected)
                    _eventSink->OnCollectionDeltaCommitted(mutation.Account, delta);
            });

        return { true, CollectionReasonCode::Ok, nextRevision };
    }

    MutationStartResult BeginClearType(AccountCollectionMutation mutation)
    {
        if (!_writesEnabled)
            return { false, CollectionReasonCode::ReadOnly, {} };
        if (mutation.Key.TypeId != AppearanceNewCollectionTypeId)
            return { false, CollectionReasonCode::InvalidArgument, {} };
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready || !mutation.Account.IsValid() ||
            !mutation.Generation.IsValid() || StableSourceKind(mutation.SourceKind) == 0)
            return { false, _diagnostics.SchemaState == AccountStoreSchemaState::Ready ?
                CollectionReasonCode::InvalidArgument : CollectionReasonCode::DatabaseError, {} };

        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(mutation.Account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready || snapshot->Generation != mutation.Generation)
            return { false, CollectionReasonCode::NotReady, {} };
        if (_pendingMutations.contains(mutation.Account))
            return { false, CollectionReasonCode::PendingOperation, {} };

        std::optional<std::vector<CollectionId>> owned =
            GetAccountCollectionCache().OwnedByType(mutation.Account, mutation.Key.TypeId);
        if (!owned)
            return { false, CollectionReasonCode::NotReady, snapshot->Revision };
        if (owned->empty())
            return { true, CollectionReasonCode::Ok, snapshot->Revision };
        if (snapshot->Revision.Value() == std::numeric_limits<std::uint64_t>::max())
            return { false, CollectionReasonCode::RevisionConflict, snapshot->Revision };

        CollectionRevision nextRevision(snapshot->Revision.Value() + 1);
        CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
        transaction->Append(
            "INSERT INTO sc_account_state(account_id, revision, schema_version) VALUES ({}, 0, 2) "
            "ON DUPLICATE KEY UPDATE schema_version = schema_version",
            mutation.Account.Value());
        transaction->Append(
            "UPDATE sc_account_state SET revision = IF(revision = {}, {}, NULL) WHERE account_id = {}",
            snapshot->Revision.Value(), nextRevision.Value(), mutation.Account.Value());
        transaction->Append(
            "DELETE FROM sc_collection_unlock WHERE account_id = {} AND type_id = {}",
            mutation.Account.Value(), mutation.Key.TypeId.Value());
        transaction->Append(
            "INSERT INTO sc_collection_audit(account_id, type_id, collection_id, action_kind, source_kind, source_id, "
            "character_guid, actor_account_id, actor_guid, revision, result_code) "
            "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
            mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
            StableMutationKind(CollectionMutationKind::Revoke), StableSourceKind(mutation.SourceKind),
            mutation.SourceId, mutation.CharacterGuid, mutation.ActorAccountId, mutation.ActorGuid,
            nextRevision.Value(), ToStableReasonCode(CollectionReasonCode::Ok));

        _pendingMutations.emplace(mutation.Account, mutation);
        TransactionCallback& callback = _transactionCallbacks.AddCallback(
            CharacterDatabase.AsyncCommitTransaction(transaction));
        callback.AfterComplete(
            [this, mutation, nextRevision](bool committed)
            {
                _pendingMutations.erase(mutation.Account);
                if (!committed)
                {
                    ++_diagnostics.FailedMutations;
                    LOG_ERROR("module.solocollections.database",
                        "event=clear_type_commit result=failed account={} type={} generation={} revision={}",
                        mutation.Account.Value(), mutation.Key.TypeId.Value(),
                        mutation.Generation.Value(), nextRevision.Value());
                    if (_eventSink)
                        _eventSink->OnCollectionMutationFailed(
                            mutation.Account, mutation.Key, CollectionReasonCode::DatabaseError);
                    return;
                }

                bool cacheUpdated = GetAccountCollectionCache().ClearOwnedType(
                    mutation.Account, mutation.Key.TypeId, nextRevision);
                ++_diagnostics.SuccessfulMutations;
                LOG_INFO("module.solocollections.store",
                    "event=clear_type_commit result=success account={} type={} generation={} revision={} cache={}",
                    mutation.Account.Value(), mutation.Key.TypeId.Value(),
                    mutation.Generation.Value(), nextRevision.Value(), cacheUpdated ? 1 : 0);
                if (_eventSink && cacheUpdated)
                    _eventSink->OnOwnedSnapshotReplaced(
                        mutation.Account, mutation.Key.TypeId, nextRevision);
            });

        return { true, CollectionReasonCode::Ok, nextRevision };
    }

    bool RetryLoad(AccountId accountId, std::uint32_t playerGuid)
    {
        std::optional<LoginGeneration> generation = GetAccountCollectionCache().RetryFailed(accountId);
        if (!generation)
            return false;
        BeginLoad({ accountId, playerGuid, *generation });
        return true;
    }

    bool ReloadAccount(AccountId accountId, std::uint32_t playerGuid)
    {
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready ||
            _pendingMutations.contains(accountId) || _loadingAccounts.contains(accountId))
            return false;

        std::optional<LoginGeneration> generation = GetAccountCollectionCache().BeginReload(accountId);
        if (!generation)
            return false;
        BeginLoad({ accountId, playerGuid, *generation });
        return true;
    }

    bool RecordRejectedMutation(AccountCollectionMutation const& mutation, CollectionReasonCode reason)
    {
        if (!_writesEnabled)
        {
            LOG_DEBUG("module.solocollections.audit",
                "event=rejected_mutation_audit result=shadow_suppressed account={} type={} collection={} reason={}",
                mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                ToStableReasonCode(reason));
            return false;
        }
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready || !mutation.Account.IsValid())
        {
            LOG_ERROR("module.solocollections.database",
                "event=rejected_mutation_audit result=unavailable account={} type={} collection={} reason={}",
                mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                ToStableReasonCode(reason));
            return false;
        }

        CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
        transaction->Append(
            "INSERT INTO sc_collection_audit(account_id, type_id, collection_id, action_kind, source_kind, source_id, "
            "character_guid, actor_account_id, actor_guid, revision, result_code) "
            "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, 0, {})",
            mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
            StableMutationKind(mutation.Kind), StableSourceKind(mutation.SourceKind), mutation.SourceId,
            mutation.CharacterGuid, mutation.ActorAccountId, mutation.ActorGuid, ToStableReasonCode(reason));

        ++_pendingAudits;
        TransactionCallback& callback = _transactionCallbacks.AddCallback(
            CharacterDatabase.AsyncCommitTransaction(transaction));
        callback.AfterComplete([this, mutation, reason](bool committed)
        {
            --_pendingAudits;
            if (!committed)
            {
                LOG_ERROR("module.solocollections.database",
                    "event=rejected_mutation_audit result=failed account={} type={} collection={} reason={}",
                    mutation.Account.Value(), mutation.Key.TypeId.Value(), mutation.Key.Id.Value(),
                    ToStableReasonCode(reason));
                return;
            }
            LOG_INFO("module.solocollections.audit",
                "event=rejected_mutation_audit result=committed account={} type={} collection={} reason={}",
                mutation.Account.Value(), mutation.Key.TypeId.Value(),
                mutation.Key.Id.Value(), ToStableReasonCode(reason));
        });
        return true;
    }

    bool RequestResync(AccountId accountId)
    {
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
        return snapshot && snapshot->State == AccountCacheLoadState::Ready && _eventSink &&
            _eventSink->OnAccountResyncRequested(accountId);
    }

    bool HasPendingMutation(AccountId accountId) const
    {
        return _pendingMutations.contains(accountId);
    }

    bool CheckMigrationMarker(MigrationMarkerRequest request, MigrationCheckCallback callback)
    {
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready || !request.Account.IsValid() ||
            request.MigrationId == 0 || request.MigrationVersion == 0 || !callback)
            return false;
        auto key = std::make_pair(request.Account, request.MigrationId);
        if (!_pendingMigrationChecks.insert(key).second)
            return false;

        std::string sourceQuery;
        if (request.SourceKind == MigrationMarkerRequest::Source::CharacterSpell)
            sourceQuery = Acore::StringFormat(
                "SELECT 1 AS row_kind, cs.spell AS value FROM character_spell cs "
                "INNER JOIN characters c ON c.guid = cs.guid WHERE c.account = {} ", request.Account.Value());
        else if (request.SourceKind == MigrationMarkerRequest::Source::LegacyAppearance)
            sourceQuery = Acore::StringFormat(
                "SELECT 1 AS row_kind, item_template_id AS value FROM custom_unlocked_appearances "
                "WHERE account_id = {} ", request.Account.Value());
        else
        {
            _pendingMigrationChecks.erase(key);
            return false;
        }

        std::string query = Acore::StringFormat(
            "SELECT 0 AS row_kind, CASE WHEN EXISTS(SELECT 1 FROM sc_migration_marker "
            "WHERE account_id = {} AND migration_id = {} AND migration_version >= {}) THEN 1 ELSE 0 END AS value "
            "UNION ALL {}"
            "AND NOT EXISTS(SELECT 1 FROM sc_migration_marker WHERE account_id = {} AND migration_id = {} "
            "AND migration_version >= {})",
            request.Account.Value(), request.MigrationId, request.MigrationVersion, sourceQuery,
            request.Account.Value(), request.MigrationId, request.MigrationVersion);
        _queryCallbacks.AddCallback(CharacterDatabase.AsyncQuery(query).WithCallback(
            [this, key, callback = std::move(callback)](QueryResult result) mutable
            {
                _pendingMigrationChecks.erase(key);
                bool succeeded = static_cast<bool>(result);
                bool completed = false;
                bool sawSentinel = false;
                std::vector<std::uint32_t> sourceIds;
                if (result)
                {
                    do
                    {
                        Field* fields = result->Fetch();
                        std::uint64_t rowKind = fields[0].Get<std::uint64_t>();
                        std::uint64_t value = fields[1].Get<std::uint64_t>();
                        if (rowKind == 0 && !sawSentinel)
                        {
                            sawSentinel = true;
                            completed = value == 1;
                        }
                        else if (rowKind == 1 && value > 0 && value <= std::numeric_limits<std::uint32_t>::max())
                            sourceIds.push_back(static_cast<std::uint32_t>(value));
                        else
                            succeeded = false;
                    } while (succeeded && result->NextRow());
                }
                succeeded = succeeded && sawSentinel;
                callback(succeeded, completed, std::move(sourceIds));
            }));
        return true;
    }

    bool CompleteMigrationMarker(MigrationMarkerCompletion completion, MigrationCompleteCallback callback)
    {
        if (!_writesEnabled)
            return false;
        if (_diagnostics.SchemaState != AccountStoreSchemaState::Ready || !completion.Account.IsValid() ||
            completion.MigrationId == 0 || completion.MigrationVersion == 0 || !callback)
            return false;
        auto key = std::make_pair(completion.Account, completion.MigrationId);
        if (!_pendingMigrationMarkers.insert(key).second)
            return false;

        CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
        transaction->Append(
            "INSERT INTO sc_migration_marker(account_id, migration_id, migration_version, completed_revision, imported_count, rejected_count) "
            "VALUES ({}, {}, {}, {}, {}, {}) ON DUPLICATE KEY UPDATE migration_version=VALUES(migration_version), "
            "completed_revision=VALUES(completed_revision), imported_count=VALUES(imported_count), "
            "rejected_count=VALUES(rejected_count), completed_at=CURRENT_TIMESTAMP(3)",
            completion.Account.Value(), completion.MigrationId, completion.MigrationVersion,
            completion.CompletedRevision.Value(), completion.ImportedCount, completion.RejectedCount);
        TransactionCallback& transactionCallback = _transactionCallbacks.AddCallback(
            CharacterDatabase.AsyncCommitTransaction(transaction));
        transactionCallback.AfterComplete([this, key, callback = std::move(callback)](bool committed) mutable
        {
            _pendingMigrationMarkers.erase(key);
            callback(committed);
        });
        return true;
    }

    AccountStoreDiagnostics Diagnostics() const
    {
        AccountStoreDiagnostics result = _diagnostics;
        result.WritesEnabled = _writesEnabled;
        result.PendingLoads = _loadingAccounts.size() + _deferredLoads.size();
        result.PendingMutations = _pendingMutations.size();
        result.PendingAudits = _pendingAudits;
        result.PendingMigrationChecks = _pendingMigrationChecks.size();
        result.PendingMigrationMarkers = _pendingMigrationMarkers.size();
        return result;
    }

    bool IsSchemaReady() const
    {
        return _diagnostics.SchemaState == AccountStoreSchemaState::Ready;
    }

    void SetEventSink(AccountCollectionEventSink* sink)
    {
        _eventSink = sink;
    }

    void SetWritesEnabled(bool enabled)
    {
        _writesEnabled = enabled;
    }

    bool WritesEnabled() const
    {
        return _writesEnabled;
    }

private:
    QueryCallbackProcessor _queryCallbacks;
    AsyncCallbackProcessor<TransactionCallback> _transactionCallbacks;
    std::map<AccountId, DeferredLoad> _deferredLoads;
    std::set<AccountId> _loadingAccounts;
    std::map<AccountId, AccountCollectionMutation> _pendingMutations;
    std::set<std::pair<AccountId, std::uint32_t>> _pendingMigrationChecks;
    std::set<std::pair<AccountId, std::uint32_t>> _pendingMigrationMarkers;
    std::size_t _pendingAudits = 0;
    AccountCollectionEventSink* _eventSink = nullptr;
    AccountStoreDiagnostics _diagnostics;
    bool _initialized = false;
    bool _writesEnabled = false;
};

AccountCollectionStore::AccountCollectionStore() : _impl(std::make_unique<Impl>()) { }
AccountCollectionStore::~AccountCollectionStore() = default;

void AccountCollectionStore::Initialize()
{
    _impl->Initialize();
}

void AccountCollectionStore::Update()
{
    _impl->Update();
}

void AccountCollectionStore::BeginLoad(
    AccountId accountId, std::uint32_t playerGuid, LoginGeneration generation)
{
    _impl->BeginLoad({ accountId, playerGuid, generation });
}

bool AccountCollectionStore::RetryLoad(AccountId accountId, std::uint32_t playerGuid)
{
    return _impl->RetryLoad(accountId, playerGuid);
}

bool AccountCollectionStore::ReloadAccount(AccountId accountId, std::uint32_t playerGuid)
{
    return _impl->ReloadAccount(accountId, playerGuid);
}

MutationStartResult AccountCollectionStore::BeginMutation(AccountCollectionMutation mutation)
{
    return _impl->BeginMutation(std::move(mutation));
}

MutationStartResult AccountCollectionStore::BeginPreferenceMutation(AccountCollectionMutation mutation)
{
    return _impl->BeginPreferenceMutation(std::move(mutation));
}

MutationStartResult AccountCollectionStore::BeginClearType(AccountCollectionMutation mutation)
{
    return _impl->BeginClearType(std::move(mutation));
}

bool AccountCollectionStore::RecordRejectedMutation(
    AccountCollectionMutation const& mutation, CollectionReasonCode reason)
{
    return _impl->RecordRejectedMutation(mutation, reason);
}

bool AccountCollectionStore::RequestResync(AccountId accountId)
{
    return _impl->RequestResync(accountId);
}

bool AccountCollectionStore::HasPendingMutation(AccountId accountId) const
{
    return _impl->HasPendingMutation(accountId);
}

bool AccountCollectionStore::CheckMigrationMarker(
    MigrationMarkerRequest request, MigrationCheckCallback callback)
{
    return _impl->CheckMigrationMarker(request, std::move(callback));
}

bool AccountCollectionStore::CompleteMigrationMarker(
    MigrationMarkerCompletion completion, MigrationCompleteCallback callback)
{
    return _impl->CompleteMigrationMarker(completion, std::move(callback));
}

void AccountCollectionStore::SetWritesEnabled(bool enabled)
{
    _impl->SetWritesEnabled(enabled);
}

bool AccountCollectionStore::WritesEnabled() const
{
    return _impl->WritesEnabled();
}

void AccountCollectionStore::SetEventSink(AccountCollectionEventSink* sink)
{
    _impl->SetEventSink(sink);
}

AccountStoreDiagnostics AccountCollectionStore::Diagnostics() const
{
    return _impl->Diagnostics();
}

bool AccountCollectionStore::IsSchemaReady() const
{
    return _impl->IsSchemaReady();
}

AccountCollectionStore& GetAccountCollectionStore()
{
    static AccountCollectionStore store;
    return store;
}
}
