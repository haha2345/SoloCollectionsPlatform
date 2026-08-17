#ifndef SOLO_COLLECTIONS_TRANSMOG_SERVICE_H
#define SOLO_COLLECTIONS_TRANSMOG_SERVICE_H

#include "SoloCollectionsProtocolServer.h"
#include "SoloCollectionsTransmogProjection.h"

#include "DatabaseEnv.h"
#include "ObjectGuid.h"

#include <cstdint>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

class Player;

namespace SoloCollections
{
struct PendingWardrobePush
{
    AccountSessionId Session;
    AccountId Account;
    ObjectGuid Character;
    bool Applied = false;
    bool OutfitsToAccount = false;
};

class TransmogProjectionService
{
public:
    void LoadCharacter(ObjectGuid characterGuid);
    void UnloadCharacter(ObjectGuid characterGuid);
    void LoadAccount(std::uint32_t accountId);

    [[nodiscard]] std::string AppliedPayload(ObjectGuid characterGuid) const;
    [[nodiscard]] std::uint64_t AppliedRevision(ObjectGuid characterGuid) const;
    [[nodiscard]] std::string OutfitPayload(std::uint32_t accountId) const;
    [[nodiscard]] std::uint64_t OutfitRevision(std::uint32_t accountId) const;

    [[nodiscard]] Sc2WardrobeOutcome Quote(Player* player, std::string_view entries);
    [[nodiscard]] Sc2WardrobeOutcome Apply(Player* player, std::string_view entries);
    [[nodiscard]] Sc2WardrobeOutcome Clear(Player* player, std::string_view entries);
    [[nodiscard]] Sc2WardrobeOutcome SaveOutfit(Player* player, std::uint32_t uid,
        std::string_view nameHex, std::string_view entries);
    [[nodiscard]] Sc2WardrobeOutcome RenameOutfit(Player* player, std::uint32_t uid,
        std::string_view nameHex);
    [[nodiscard]] Sc2WardrobeOutcome DeleteOutfit(Player* player, std::uint32_t uid);

    void SyncLegacyApplied(Player* player, std::map<std::uint8_t, std::uint32_t> const& slotToCollectionId);
    [[nodiscard]] bool PrepareLegacyMerge(Player* player,
        std::map<std::uint8_t, std::uint32_t> const& slotToCollectionId,
        WardrobeSlotValues& outSlots, std::uint64_t& outRevision);
    void AppendAppliedSql(CharacterDatabaseTransaction& transaction, ObjectGuid characterGuid,
        WardrobeSlotValues const& slots, std::uint64_t revision) const;
    void CommitLegacyAppliedCache(Player* player, WardrobeSlotValues const& slots, std::uint64_t revision);

    void TakePendingPushes(std::vector<PendingWardrobePush>& out);

private:
    struct AppliedState
    {
        WardrobeSlotValues Slots {};
        std::uint64_t Revision = 0;
        bool Loaded = false;
    };

    struct AccountOutfits
    {
        std::vector<AccountOutfitRecord> Outfits;
        std::uint64_t Revision = 0;
        bool Loaded = false;
    };

    struct QuoteCache
    {
        std::string Entries;
        std::uint32_t Copper = 0;
        std::uint64_t AtMs = 0;
    };

    struct ParsedIntent
    {
        std::map<std::uint8_t, std::uint32_t> Requests;
        std::uint32_t WarningMask = 0;
        std::uint32_t Copper = 0;
        std::string Status;
    };

    void EnsureCharacterLoaded(ObjectGuid characterGuid);
    void EnsureAccountLoaded(std::uint32_t accountId);
    [[nodiscard]] ParsedIntent EvaluateIntent(Player* player, std::string_view entries) const;
    [[nodiscard]] AppliedState const* FindApplied(ObjectGuid characterGuid) const;
    AppliedState& EnsureApplied(ObjectGuid characterGuid);
    AccountOutfits& EnsureOutfits(std::uint32_t accountId);
    void AppendAuditSql(CharacterDatabaseTransaction& transaction, std::uint32_t accountId,
        std::uint16_t typeId, std::uint32_t collectionId, std::uint16_t actionKind,
        std::uint32_t characterGuid, std::uint64_t revision) const;
    void EnqueueAppliedPush(ObjectGuid characterGuid, std::uint32_t accountId);
    void EnqueueOutfitPush(std::uint32_t accountId);
    [[nodiscard]] bool CommitTransaction(CharacterDatabaseTransaction& transaction) const;
    void RememberQuote(ObjectGuid characterGuid, std::string_view entries, std::uint32_t copper);
    [[nodiscard]] std::optional<std::uint32_t> CachedQuoteCopper(ObjectGuid characterGuid,
        std::string_view entries) const;

    mutable std::mutex _mutex;
    std::unordered_map<std::uint32_t, AppliedState> _applied;
    std::unordered_map<std::uint32_t, AccountOutfits> _outfits;
    std::unordered_map<std::uint32_t, QuoteCache> _quotes;
    std::vector<PendingWardrobePush> _pendingPushes;
};

TransmogProjectionService& GetTransmogProjectionService();
}

#endif
