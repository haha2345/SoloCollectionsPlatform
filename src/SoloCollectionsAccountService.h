#ifndef SOLO_COLLECTIONS_ACCOUNT_SERVICE_H
#define SOLO_COLLECTIONS_ACCOUNT_SERVICE_H

#include "SoloCollectionsAccountStore.h"

#include <optional>
#include <vector>

namespace SoloCollections
{
class AccountCollectionService
{
public:
    [[nodiscard]] CollectionResult Evaluate(AccountId accountId, CollectionKey const& key) const;
    [[nodiscard]] std::optional<std::vector<CollectionId>> OwnedByType(
        AccountId accountId, CollectionTypeId typeId) const;
    [[nodiscard]] MutationStartResult TryUnlock(AccountId accountId, CollectionKey const& key,
        CollectionSourceKind sourceKind, std::uint64_t sourceId, std::uint32_t characterGuid,
        std::uint32_t actorAccountId = 0, std::uint32_t actorGuid = 0);
    [[nodiscard]] bool IsReady(AccountId accountId) const;
};

AccountCollectionService& GetAccountCollectionService();
}

#endif
