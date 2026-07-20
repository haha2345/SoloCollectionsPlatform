#ifndef SOLO_COLLECTIONS_APPEARANCE_SERVICE_H
#define SOLO_COLLECTIONS_APPEARANCE_SERVICE_H

#include "SoloCollectionsTypes.h"

#include "ObjectGuid.h"

#include <cstdint>
#include <deque>
#include <map>
#include <mutex>
#include <optional>
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
    void Update();
    [[nodiscard]] bool LoadLegacyCollections();
    [[nodiscard]] bool TryUnlockLegacy(AccountId accountId, std::uint32_t sourceItemId);
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
    [[nodiscard]] TransmogApplyResult TryApplyCollectedPreset(Player* player,
        std::map<std::uint8_t, std::uint32_t> const& appearances, ObjectGuid interactionGuid);
    [[nodiscard]] TransmogApplyResult TryApplyCanonicalAppearance(Player* player,
        CollectionId appearanceId, std::uint8_t slot, ObjectGuid interactionGuid,
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

    void BeginMigrationCheck(AccountId accountId, MigrationState& state);
    void AdvanceMigration(AccountId accountId, MigrationState& state);

    mutable std::mutex _mutex;
    LegacyCollectionCache _legacyCollections;
    std::map<AccountId, MigrationState> _migrations;
    AppearanceRepositoryHealth _health = AppearanceRepositoryHealth::Uninitialized;
};

AppearanceService& GetAppearanceService();
}

#endif
