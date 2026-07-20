#ifndef SOLO_COLLECTIONS_APPEARANCE_SERVICE_H
#define SOLO_COLLECTIONS_APPEARANCE_SERVICE_H

#include "SoloCollectionsTypes.h"

#include "ObjectGuid.h"

#include <cstdint>
#include <map>
#include <mutex>
#include <unordered_map>
#include <unordered_set>

class Player;
enum class TransmogApplySource : std::uint8_t;
struct TransmogApplyResult;

namespace SoloCollections
{
inline constexpr CollectionTypeId AppearanceCollectionTypeId { std::uint16_t { 13 } };

enum class AppearanceRepositoryHealth : std::uint8_t
{
    Uninitialized,
    Healthy,
    QueryFailed,
    Disabled,
};

class AppearanceService
{
public:
    [[nodiscard]] bool LoadLegacyCollections();
    [[nodiscard]] bool TryUnlockLegacy(AccountId accountId, std::uint32_t sourceItemId);
    [[nodiscard]] bool HasCollectedSource(AccountId accountId, std::uint32_t sourceItemId) const;
    [[nodiscard]] std::unordered_set<std::uint32_t> CollectedSources(AccountId accountId) const;
    [[nodiscard]] AppearanceRepositoryHealth RepositoryHealth() const;
    [[nodiscard]] CollectionResult Evaluate(CollectionId appearanceId) const;

    [[nodiscard]] TransmogApplyResult TryApplyCollectedAppearance(Player* player,
        std::uint32_t sourceItemEntry, std::uint8_t slot, ObjectGuid interactionGuid,
        TransmogApplySource source, bool noCost = false);
    [[nodiscard]] TransmogApplyResult TryApplyCollectedPreset(Player* player,
        std::map<std::uint8_t, std::uint32_t> const& appearances, ObjectGuid interactionGuid);

private:
    using LegacyCollectionCache = std::unordered_map<std::uint32_t, std::unordered_set<std::uint32_t>>;

    mutable std::mutex _mutex;
    LegacyCollectionCache _legacyCollections;
    AppearanceRepositoryHealth _health = AppearanceRepositoryHealth::Uninitialized;
};

AppearanceService& GetAppearanceService();
}

#endif
