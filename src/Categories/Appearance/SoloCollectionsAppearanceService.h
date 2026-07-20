#ifndef SOLO_COLLECTIONS_APPEARANCE_SERVICE_H
#define SOLO_COLLECTIONS_APPEARANCE_SERVICE_H

#include "SoloCollectionsTypes.h"
#include "SoloCollectionsAccountStore.h"

#include "ObjectGuid.h"

#include <cstdint>
#include <deque>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class Item;
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

enum class AppearanceUnlockTrigger : std::uint8_t
{
    Equipment = 1,
    Loot = 2,
    Craft = 3,
    QuestReward = 4,
    InventoryStore = 5,
    Vendor = 6,
    GroupRoll = 7,
    HistoricalReconcile = 8,
    GameMaster = 9,
};

enum class AppearanceUnlockQueueResult : std::uint8_t
{
    Queued = 1,
    AlreadyOwned = 2,
    DeferredByBindingPolicy = 3,
    Rejected = 4,
};

struct AppearanceMigrationReport
{
    bool Ready = false;
    std::uint32_t LegacySources = 0;
    std::uint32_t ValidSources = 0;
    std::uint32_t CanonicalGroups = 0;
    std::uint32_t MergedSources = 0;
    std::uint32_t UnknownSources = 0;
    std::uint32_t DisabledSources = 0;
    std::uint32_t MissingTemplates = 0;
    std::uint32_t Conflicts = 0;
};

class AppearanceService
{
public:
    void OnPlayerLogin(Player* player);
    void OnPlayerLogout(Player* player);
    void OnPlayerUpdate(Player* player, std::uint32_t diff);
    void Update();
    [[nodiscard]] bool LoadLegacyCollections();
    [[nodiscard]] AppearanceUnlockQueueResult OnItemAcquired(
        Player* player, Item* item, AppearanceUnlockTrigger trigger);
    [[nodiscard]] AppearanceUnlockQueueResult QueueGameMasterUnlock(AccountId accountId,
        std::uint32_t characterGuid, std::uint32_t sourceItemId,
        std::uint32_t actorAccountId, std::uint32_t actorGuid);
    void ScanHistoricalInventory(Player* player);
    [[nodiscard]] bool HasCollectedSource(AccountId accountId, std::uint32_t sourceItemId) const;
    [[nodiscard]] std::unordered_set<std::uint32_t> CollectedSources(AccountId accountId) const;
    [[nodiscard]] AppearanceRepositoryHealth RepositoryHealth() const;
    [[nodiscard]] AppearanceMigrationReport BuildMigrationDryRun(AccountId accountId) const;
    [[nodiscard]] CollectionResult Evaluate(CollectionId appearanceId) const;
    [[nodiscard]] std::optional<std::uint32_t> ResolveOwnedSource(
        Player* player, CollectionId appearanceId, std::uint8_t slot) const;

    [[nodiscard]] TransmogApplyResult TryApplyCollectedAppearance(Player* player,
        std::uint32_t sourceItemEntry, std::uint8_t slot, ObjectGuid interactionGuid,
        TransmogApplySource source, bool noCost = false);
    [[nodiscard]] TransmogApplyResult TryApplyCollectedAppearances(Player* player,
        std::map<std::uint8_t, std::uint32_t> const& appearances, ObjectGuid interactionGuid,
        TransmogApplySource source, bool noCost = false);
    [[nodiscard]] TransmogApplyResult TryApplyCollectedPreset(Player* player,
        std::map<std::uint8_t, std::uint32_t> const& appearances, ObjectGuid interactionGuid);
    [[nodiscard]] TransmogApplyResult TryApplyCanonicalAppearance(Player* player,
        CollectionId appearanceId, std::uint8_t slot, ObjectGuid interactionGuid,
        TransmogApplySource source, bool noCost = false);
    [[nodiscard]] TransmogApplyResult TryApplyCanonicalAppearances(Player* player,
        std::map<std::uint8_t, CollectionId> const& appearances, ObjectGuid interactionGuid,
        TransmogApplySource source, bool noCost = false);

private:
    using LegacyCollectionCache = std::unordered_map<std::uint32_t, std::unordered_set<std::uint32_t>>;

    enum class MigrationPhase : std::uint8_t
    {
        AwaitingReady,
        CheckingMarker,
        Importing,
        WritingMarker,
        Complete,
        Failed,
    };

    struct PendingAppearance
    {
        CollectionId Appearance;
        std::uint32_t SourceItemId = 0;
        bool Started = false;
    };

    struct MigrationState
    {
        MigrationPhase Phase = MigrationPhase::AwaitingReady;
        std::uint32_t LoginCharacterGuid = 0;
        AppearanceMigrationReport Report;
        std::deque<PendingAppearance> Pending;
        std::vector<CollectionId> ExpectedCanonicalGroups;
        std::uint32_t ImportedCount = 0;
        std::uint32_t FailedCount = 0;
    };

    struct PendingUnlock
    {
        CollectionId Appearance;
        std::uint32_t SourceItemId = 0;
        std::uint32_t CharacterGuid = 0;
        CollectionSourceKind SourceKind = CollectionSourceKind::Gameplay;
        AppearanceUnlockTrigger Trigger = AppearanceUnlockTrigger::InventoryStore;
        std::uint32_t ActorAccountId = 0;
        std::uint32_t ActorGuid = 0;
    };

    void BeginMigrationCheck(AccountId accountId, MigrationState& state);
    void AdvanceMigration(AccountId accountId, MigrationState& state);
    void AdvanceQueuedUnlocks();
    [[nodiscard]] AppearanceUnlockQueueResult QueueCanonicalUnlock(AccountId accountId,
        std::uint32_t characterGuid, std::uint32_t sourceItemId,
        CollectionSourceKind sourceKind, AppearanceUnlockTrigger trigger,
        std::uint32_t actorAccountId = 0, std::uint32_t actorGuid = 0);

    mutable std::mutex _mutex;
    LegacyCollectionCache _legacyCollections;
    std::map<AccountId, MigrationState> _migrations;
    std::map<AccountId, std::deque<PendingUnlock>> _pendingUnlocks;
    std::map<AccountId, std::set<CollectionId>> _queuedAppearanceIds;
    std::map<std::uint32_t, std::uint32_t> _inventoryReconcileElapsed;
    AppearanceRepositoryHealth _health = AppearanceRepositoryHealth::Uninitialized;
};

AppearanceService& GetAppearanceService();
}

#endif
