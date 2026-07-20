#include "SoloCollectionsAccountService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsProvider.h"

namespace SoloCollections
{
CollectionResult AccountCollectionService::Evaluate(AccountId accountId, CollectionKey const& key) const
{
    CollectionResult result;
    CollectionProviderRegistry const& registry = GetCollectionProviderRegistry();
    CollectionProvider const* provider = registry.Find(key.TypeId);
    CollectionProviderRuntimeState const* providerState = registry.State(key.TypeId);
    if (!provider || !providerState)
    {
        result.Reason = CollectionReasonCode::UnknownType;
        return result;
    }

    result = provider->Evaluate(key.Id);
    if (!result.Availability.CatalogKnown)
        return result;
    if (providerState->Mode == CollectionProviderMode::Disabled)
    {
        result.Reason = CollectionReasonCode::Disabled;
        return result;
    }

    CollectionStorageMode storage = provider->Descriptor().Storage;
    if (storage == CollectionStorageMode::External)
    {
        result.Availability.Owned = provider->IsOwned(accountId, key.Id).value_or(false);
        result.Reason = result.Availability.Owned ? CollectionReasonCode::Ok : CollectionReasonCode::NotOwned;
        return result;
    }

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
    if (storage == CollectionStorageMode::Derived)
        result.Availability.Owned = provider->IsOwned(accountId, key.Id).value_or(false);
    else
        result.Availability.Owned = GetAccountCollectionCache().IsOwned(accountId, key);
    result.Reason = result.Availability.Owned ? CollectionReasonCode::Ok : CollectionReasonCode::NotOwned;
    return result;
}

std::optional<std::vector<CollectionId>> AccountCollectionService::OwnedByType(
    AccountId accountId, CollectionTypeId typeId) const
{
    CollectionProviderRegistry const& registry = GetCollectionProviderRegistry();
    if (CollectionProvider const* provider = registry.Find(typeId))
    {
        CollectionProviderRuntimeState const* state = registry.State(typeId);
        if (!state || state->Mode == CollectionProviderMode::Disabled)
            return std::vector<CollectionId> {};
        if (std::optional<std::vector<CollectionId>> derived = provider->OwnedByAccount(accountId))
            return derived;
        if (provider->Descriptor().Storage != CollectionStorageMode::Persisted)
            return std::vector<CollectionId> {};
    }
    return GetAccountCollectionCache().OwnedByType(accountId, typeId);
}

MutationStartResult AccountCollectionService::TryUnlock(AccountId accountId, CollectionKey const& key,
    CollectionSourceKind sourceKind, std::uint64_t sourceId, std::uint32_t characterGuid,
    std::uint32_t actorAccountId, std::uint32_t actorGuid)
{
    CollectionProviderRegistry const& registry = GetCollectionProviderRegistry();
    CollectionProvider const* provider = registry.Find(key.TypeId);
    CollectionProviderRuntimeState const* providerState = registry.State(key.TypeId);
    if (!provider || !providerState)
        return { false, CollectionReasonCode::UnknownType, {} };
    if (providerState->Mode == CollectionProviderMode::Disabled)
        return { false, CollectionReasonCode::Disabled, {} };
    if (!provider->Evaluate(key.Id).Availability.CatalogKnown)
        return { false, CollectionReasonCode::UnknownCollection, {} };
    if (providerState->Mode == CollectionProviderMode::ReadOnly ||
        provider->Descriptor().Storage != CollectionStorageMode::Persisted)
        return { false, CollectionReasonCode::ReadOnly, {} };

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
