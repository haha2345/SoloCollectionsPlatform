#include "SoloCollectionsAccountService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsProvider.h"

namespace SoloCollections
{
CollectionResult AccountCollectionService::Evaluate(AccountId accountId, CollectionKey const& key) const
{
    CollectionResult result;
    std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
    if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
    {
        result.Reason = CollectionReasonCode::NotReady;
        return result;
    }
    if (snapshot->State == AccountCacheLoadState::Failed)
    {
        result.Reason = CollectionReasonCode::LoadFailed;
        return result;
    }

    result.Revision = snapshot->Revision;
    CollectionProvider const* provider = GetCollectionProviderRegistry().Find(key.TypeId);
    std::optional<bool> derived = provider ? provider->IsOwned(accountId, key.Id) : std::nullopt;
    result.Availability.Owned = derived.value_or(GetAccountCollectionCache().IsOwned(accountId, key));
    result.Reason = result.Availability.Owned ? CollectionReasonCode::Ok : CollectionReasonCode::NotOwned;
    return result;
}

std::optional<std::vector<CollectionId>> AccountCollectionService::OwnedByType(
    AccountId accountId, CollectionTypeId typeId) const
{
    if (CollectionProvider const* provider = GetCollectionProviderRegistry().Find(typeId))
        if (std::optional<std::vector<CollectionId>> derived = provider->OwnedByAccount(accountId))
            return derived;
    return GetAccountCollectionCache().OwnedByType(accountId, typeId);
}

MutationStartResult AccountCollectionService::TryUnlock(AccountId accountId, CollectionKey const& key,
    CollectionSourceKind sourceKind, std::uint64_t sourceId, std::uint32_t characterGuid,
    std::uint32_t actorAccountId, std::uint32_t actorGuid)
{
    std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
    if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
        return { false, snapshot && snapshot->State == AccountCacheLoadState::Failed ?
            CollectionReasonCode::LoadFailed : CollectionReasonCode::NotReady, {} };

    AccountCollectionMutation mutation;
    mutation.Account = accountId;
    mutation.Generation = snapshot->Generation;
    mutation.Key = key;
    mutation.Kind = CollectionMutationKind::Grant;
    mutation.SourceKind = sourceKind;
    mutation.SourceId = sourceId;
    mutation.CharacterGuid = characterGuid;
    mutation.ActorAccountId = actorAccountId;
    mutation.ActorGuid = actorGuid;
    return GetAccountCollectionStore().BeginMutation(mutation);
}

bool AccountCollectionService::IsReady(AccountId accountId) const
{
    std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(accountId);
    return GetAccountCollectionStore().IsSchemaReady() && snapshot &&
        snapshot->State == AccountCacheLoadState::Ready;
}

AccountCollectionService& GetAccountCollectionService()
{
    static AccountCollectionService service;
    return service;
}
}
