#ifndef SOLO_COLLECTIONS_ACCOUNT_STORE_H
#define SOLO_COLLECTIONS_ACCOUNT_STORE_H

#include "SoloCollectionsAccountCache.h"

#include <cstddef>
#include <cstdint>
#include <memory>

namespace SoloCollections
{
enum class CollectionMutationKind : std::uint8_t
{
    Grant = 1,
    Revoke = 2,
};

enum class CollectionSourceKind : std::uint16_t
{
    Gameplay = 1,
    Migration = 2,
    GameMaster = 3,
    Reconcile = 4,
    System = 5,
};

enum class AccountStoreSchemaState : std::uint8_t
{
    Checking = 1,
    Ready = 2,
    Failed = 3,
};

struct AccountCollectionMutation
{
    AccountId Account;
    LoginGeneration Generation;
    CollectionKey Key;
    CollectionMutationKind Kind = CollectionMutationKind::Grant;
    CollectionSourceKind SourceKind = CollectionSourceKind::Gameplay;
    std::uint64_t SourceId = 0;
    std::uint32_t CharacterGuid = 0;
    std::uint32_t ActorAccountId = 0;
    std::uint32_t ActorGuid = 0;
};

struct MutationStartResult
{
    bool Accepted = false;
    CollectionReasonCode Reason = CollectionReasonCode::InvalidArgument;
    CollectionRevision PendingRevision;
};

struct AccountStoreDiagnostics
{
    AccountStoreSchemaState SchemaState = AccountStoreSchemaState::Checking;
    std::size_t PendingLoads = 0;
    std::size_t PendingMutations = 0;
    std::uint64_t SuccessfulLoads = 0;
    std::uint64_t FailedLoads = 0;
    std::uint64_t SuccessfulMutations = 0;
    std::uint64_t FailedMutations = 0;
};

class AccountCollectionEventSink
{
public:
    virtual ~AccountCollectionEventSink() = default;
    virtual void OnCollectionDeltaCommitted(AccountId accountId, CollectionDelta const& delta) = 0;
    virtual void OnCollectionMutationFailed(
        AccountId accountId, CollectionKey const& key, CollectionReasonCode reason) = 0;
};

class AccountCollectionStore
{
public:
    AccountCollectionStore();
    ~AccountCollectionStore();

    AccountCollectionStore(AccountCollectionStore const&) = delete;
    AccountCollectionStore& operator=(AccountCollectionStore const&) = delete;

    void Initialize();
    void Update();
    void BeginLoad(AccountId accountId, std::uint32_t playerGuid, LoginGeneration generation);
    [[nodiscard]] bool RetryLoad(AccountId accountId, std::uint32_t playerGuid);
    [[nodiscard]] MutationStartResult BeginMutation(AccountCollectionMutation mutation);
    void SetEventSink(AccountCollectionEventSink* sink);

    [[nodiscard]] AccountStoreDiagnostics Diagnostics() const;
    [[nodiscard]] bool IsSchemaReady() const;

private:
    class Impl;
    std::unique_ptr<Impl> _impl;
};

AccountCollectionStore& GetAccountCollectionStore();
}

#endif
