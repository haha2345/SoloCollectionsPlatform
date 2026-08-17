#include "SoloCollectionsTransmogService.h"

#include "Categories/Appearance/SoloCollectionsAppearanceCatalog.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsAccountService.h"
#include "Transmogrification.h"

#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QueryResult.h"
#include "SharedDefines.h"

#include <algorithm>
#include <chrono>
#include <sstream>
#include <utility>

namespace SoloCollections
{
namespace
{
constexpr std::uint16_t AuditApply = 20;
constexpr std::uint16_t AuditClear = 21;
constexpr std::uint16_t AuditSave = 22;
constexpr std::uint16_t AuditRename = 23;
constexpr std::uint16_t AuditDelete = 24;
constexpr std::uint64_t QuoteCacheMs = 3000;

std::uint64_t NowMs()
{
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

std::uint32_t CharacterGuid(Player* player)
{
    return player ? player->GetGUID().GetCounter() : 0;
}

char const* OwnedSourceFailureStatus(Player* player, CollectionId appearanceId)
{
    AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().Find(appearanceId);
    if (!player || !definition)
        return "SKILL_REQUIRED";
    std::uint32_t classMask = player->getClassMask();
    bool sawTemplate = false;
    for (std::uint32_t sourceItemId : definition->SourceItemIds)
    {
        ItemTemplate const* source = sObjectMgr->GetItemTemplate(sourceItemId);
        if (!source)
            continue;
        sawTemplate = true;
        if (source->AllowableClass == 0 || source->AllowableClass == static_cast<std::uint32_t>(-1)
            || (source->AllowableClass & classMask) != 0)
            return "SKILL_REQUIRED";
    }
    return sawTemplate ? "CLASS_RESTRICTED" : "SKILL_REQUIRED";
}

char const* CollectedApplyFailureStatus(Player* player, CollectionId appearanceId, ItemTemplate const* target)
{
    AppearanceCollectionDefinition const* definition = GetAppearanceCatalog().Find(appearanceId);
    if (!player || !definition || !target)
        return "SKILL_REQUIRED";
    bool weaponBlock = false;
    bool armorBlock = false;
    for (std::uint32_t sourceItemId : definition->SourceItemIds)
    {
        ItemTemplate const* source = sObjectMgr->GetItemTemplate(sourceItemId);
        if (!source)
            continue;
        if (sTransmogrification->CanApplyCollectedVisual(player, target, source))
            return "SKILL_REQUIRED";
        if (source->Class == ITEM_CLASS_WEAPON && target->Class == ITEM_CLASS_WEAPON)
            weaponBlock = true;
        else if (source->Class == ITEM_CLASS_ARMOR && target->Class == ITEM_CLASS_ARMOR)
            armorBlock = true;
    }
    if (weaponBlock)
        return "WEAPON_TYPE";
    if (armorBlock)
        return "ARMOR_TYPE";
    return OwnedSourceFailureStatus(player, appearanceId);
}

std::uint32_t AccountOf(Player* player)
{
    return player && player->GetSession() ? player->GetSession()->GetAccountId() : 0;
}

Sc2WardrobeOutcome Failure(std::string status, std::uint16_t typeId = CharacterAppliedCollectionTypeId.Value(),
    std::uint32_t collectionId = 1, std::uint32_t warningMask = 0, std::uint32_t copper = 0)
{
    Sc2WardrobeOutcome outcome;
    outcome.Status = std::move(status);
    outcome.TypeId = typeId;
    outcome.CollectionId = collectionId;
    outcome.WarningMask = warningMask;
    outcome.Copper = copper;
    return outcome;
}

std::optional<std::map<std::uint8_t, std::uint32_t>> ParseApplyEntries(std::string_view entries)
{
    std::map<std::uint8_t, std::uint32_t> requests;
    std::size_t begin = 0;
    while (begin < entries.size())
    {
        std::size_t comma = entries.find(',', begin);
        std::string_view token = entries.substr(begin,
            (comma == std::string_view::npos ? entries.size() : comma) - begin);
        std::size_t colon = token.find(':');
        if (colon == std::string_view::npos)
            return std::nullopt;
        std::uint32_t slotPlus1 = 0;
        std::uint32_t collectionId = 0;
        try
        {
            slotPlus1 = static_cast<std::uint32_t>(std::stoul(std::string(token.substr(0, colon))));
            collectionId = static_cast<std::uint32_t>(std::stoul(std::string(token.substr(colon + 1))));
        }
        catch (...)
        {
            return std::nullopt;
        }
        if (slotPlus1 == 0 || collectionId == 0)
            return std::nullopt;
        std::uint8_t inventorySlot = static_cast<std::uint8_t>(slotPlus1 - 1);
        if (!WardrobeIndexForInventorySlot(inventorySlot) || requests.contains(inventorySlot))
            return std::nullopt;
        requests.emplace(inventorySlot, collectionId);
        if (comma == std::string_view::npos)
            break;
        begin = comma + 1;
    }
    return requests;
}

std::optional<std::vector<std::size_t>> ParseClearIndices(std::string_view entries)
{
    std::vector<std::size_t> indices;
    if (entries == "-")
    {
        for (std::size_t index = 0; index < WardrobeSlotCount; ++index)
            indices.push_back(index);
        return indices;
    }
    std::size_t begin = 0;
    while (begin < entries.size())
    {
        std::size_t comma = entries.find(',', begin);
        std::string_view token = entries.substr(begin,
            (comma == std::string_view::npos ? entries.size() : comma) - begin);
        std::uint32_t slotPlus1 = 0;
        try
        {
            slotPlus1 = static_cast<std::uint32_t>(std::stoul(std::string(token)));
        }
        catch (...)
        {
            return std::nullopt;
        }
        if (slotPlus1 == 0)
            return std::nullopt;
        auto index = WardrobeIndexForInventorySlot(static_cast<std::uint8_t>(slotPlus1 - 1));
        if (!index)
            return std::nullopt;
        if (std::find(indices.begin(), indices.end(), *index) != indices.end())
            return std::nullopt;
        indices.push_back(*index);
        if (comma == std::string_view::npos)
            break;
        begin = comma + 1;
    }
    return indices;
}

bool SlotsEqual(WardrobeSlotValues const& left, WardrobeSlotValues const& right)
{
    return left == right;
}

// Same formula as Transmogrification::PreflightApply: max(source sellPrice, 1g) *
// ScaledCostModifier + CopperCost. Hide is billed separately as 0.
std::uint32_t SlotSellPriceCopper(ItemTemplate const* source)
{
    if (!source)
        return 0;
    double configuredCost = static_cast<double>(sTransmogrification->GetSpecialPrice(source)) *
        static_cast<double>(sTransmogrification->GetScaledCostModifier()) +
        static_cast<double>(sTransmogrification->GetCopperCost());
    if (configuredCost <= 0.0)
        return 0;
    if (configuredCost > static_cast<double>(MAX_MONEY_AMOUNT))
        return static_cast<std::uint32_t>(MAX_MONEY_AMOUNT);
    return static_cast<std::uint32_t>(configuredCost);
}

void AddSlotCopper(std::uint64_t& copper, std::uint32_t slotCopper)
{
    if (copper >= MAX_MONEY_AMOUNT)
    {
        copper = MAX_MONEY_AMOUNT;
        return;
    }
    if (slotCopper > MAX_MONEY_AMOUNT - copper)
        copper = MAX_MONEY_AMOUNT;
    else
        copper += slotCopper;
}
}

TransmogProjectionService::AppliedState const* TransmogProjectionService::FindApplied(
    ObjectGuid characterGuid) const
{
    auto found = _applied.find(characterGuid.GetCounter());
    return found == _applied.end() ? nullptr : &found->second;
}

TransmogProjectionService::AppliedState& TransmogProjectionService::EnsureApplied(ObjectGuid characterGuid)
{
    return _applied[characterGuid.GetCounter()];
}

TransmogProjectionService::AccountOutfits& TransmogProjectionService::EnsureOutfits(std::uint32_t accountId)
{
    return _outfits[accountId];
}

void TransmogProjectionService::LoadCharacter(ObjectGuid characterGuid)
{
    if (!characterGuid)
        return;
    AppliedState loaded;
    loaded.Loaded = true;
    QueryResult result = CharacterDatabase.Query(
        "SELECT revision, slot_0, slot_1, slot_2, slot_3, slot_4, slot_5, slot_6, "
        "slot_7, slot_8, slot_9, slot_10, slot_11, slot_12, slot_13 "
        "FROM character_sc_transmog WHERE guid = {}", characterGuid.GetCounter());
    if (result)
    {
        Field* fields = result->Fetch();
        loaded.Revision = fields[0].Get<std::uint64_t>();
        for (std::size_t index = 0; index < WardrobeSlotCount; ++index)
            loaded.Slots[index] = fields[index + 1].Get<std::uint32_t>();
    }
    std::scoped_lock lock(_mutex);
    _applied[characterGuid.GetCounter()] = std::move(loaded);
}

void TransmogProjectionService::UnloadCharacter(ObjectGuid characterGuid)
{
    std::scoped_lock lock(_mutex);
    _applied.erase(characterGuid.GetCounter());
    _quotes.erase(characterGuid.GetCounter());
}

void TransmogProjectionService::EnsureCharacterLoaded(ObjectGuid characterGuid)
{
    {
        std::scoped_lock lock(_mutex);
        auto found = _applied.find(characterGuid.GetCounter());
        if (found != _applied.end() && found->second.Loaded)
            return;
    }
    LoadCharacter(characterGuid);
}

void TransmogProjectionService::EnsureAccountLoaded(std::uint32_t accountId)
{
    {
        std::scoped_lock lock(_mutex);
        auto found = _outfits.find(accountId);
        if (found != _outfits.end() && found->second.Loaded)
            return;
    }
    LoadAccount(accountId);
}

void TransmogProjectionService::LoadAccount(std::uint32_t accountId)
{
    if (accountId == 0)
        return;
    AccountOutfits loaded;
    loaded.Loaded = true;
    QueryResult result = CharacterDatabase.Query(
        "SELECT uid, name_hex, slot_blob, revision FROM account_sc_outfit "
        "WHERE account_id = {} ORDER BY uid", accountId);
    if (result)
    {
        do
        {
            Field* fields = result->Fetch();
            AccountOutfitRecord outfit;
            outfit.Uid = fields[0].Get<std::uint32_t>();
            outfit.NameHex = fields[1].Get<std::string>();
            std::optional<WardrobeSlotValues> slots = DecodeWardrobeSlots(fields[2].Get<std::string>());
            if (!slots || outfit.Uid < 1 || outfit.Uid > MaxAccountOutfits)
                continue;
            outfit.Slots = *slots;
            outfit.Revision = fields[3].Get<std::uint64_t>();
            loaded.Revision = std::max(loaded.Revision, outfit.Revision);
            loaded.Outfits.push_back(std::move(outfit));
        } while (result->NextRow());
    }
    std::scoped_lock lock(_mutex);
    _outfits[accountId] = std::move(loaded);
}

std::string TransmogProjectionService::AppliedPayload(ObjectGuid characterGuid) const
{
    std::scoped_lock lock(_mutex);
    AppliedState const* state = FindApplied(characterGuid);
    return EncodeWardrobeSlots(state ? state->Slots : WardrobeSlotValues {});
}

std::uint64_t TransmogProjectionService::AppliedRevision(ObjectGuid characterGuid) const
{
    std::scoped_lock lock(_mutex);
    AppliedState const* state = FindApplied(characterGuid);
    return state ? state->Revision : 0;
}

std::string TransmogProjectionService::OutfitPayload(std::uint32_t accountId) const
{
    std::scoped_lock lock(_mutex);
    auto found = _outfits.find(accountId);
    return EncodeAccountOutfits(found == _outfits.end() ? std::vector<AccountOutfitRecord> {} : found->second.Outfits);
}

std::uint64_t TransmogProjectionService::OutfitRevision(std::uint32_t accountId) const
{
    std::scoped_lock lock(_mutex);
    auto found = _outfits.find(accountId);
    return found == _outfits.end() ? 0 : found->second.Revision;
}

void TransmogProjectionService::TakePendingPushes(std::vector<PendingWardrobePush>& out)
{
    std::scoped_lock lock(_mutex);
    out.swap(_pendingPushes);
    _pendingPushes.clear();
}

void TransmogProjectionService::EnqueueAppliedPush(ObjectGuid characterGuid, std::uint32_t accountId)
{
    PendingWardrobePush push;
    push.Session = AccountSessionId(characterGuid.GetCounter());
    push.Account = AccountId(accountId);
    push.Character = characterGuid;
    push.Applied = true;
    _pendingPushes.push_back(push);
}

void TransmogProjectionService::EnqueueOutfitPush(std::uint32_t accountId)
{
    PendingWardrobePush push;
    push.Account = AccountId(accountId);
    push.OutfitsToAccount = true;
    _pendingPushes.push_back(push);
}

void TransmogProjectionService::AppendAppliedSql(CharacterDatabaseTransaction& transaction,
    ObjectGuid characterGuid, WardrobeSlotValues const& slots, std::uint64_t revision) const
{
    transaction->Append(
        "INSERT INTO character_sc_transmog (guid, revision, slot_0, slot_1, slot_2, slot_3, slot_4, "
        "slot_5, slot_6, slot_7, slot_8, slot_9, slot_10, slot_11, slot_12, slot_13) "
        "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}) "
        "ON DUPLICATE KEY UPDATE revision=VALUES(revision), slot_0=VALUES(slot_0), slot_1=VALUES(slot_1), "
        "slot_2=VALUES(slot_2), slot_3=VALUES(slot_3), slot_4=VALUES(slot_4), slot_5=VALUES(slot_5), "
        "slot_6=VALUES(slot_6), slot_7=VALUES(slot_7), slot_8=VALUES(slot_8), slot_9=VALUES(slot_9), "
        "slot_10=VALUES(slot_10), slot_11=VALUES(slot_11), slot_12=VALUES(slot_12), slot_13=VALUES(slot_13)",
        characterGuid.GetCounter(), revision,
        slots[0], slots[1], slots[2], slots[3], slots[4], slots[5], slots[6],
        slots[7], slots[8], slots[9], slots[10], slots[11], slots[12], slots[13]);
}

void TransmogProjectionService::AppendAuditSql(CharacterDatabaseTransaction& transaction,
    std::uint32_t accountId, std::uint16_t typeId, std::uint32_t collectionId, std::uint16_t actionKind,
    std::uint32_t characterGuid, std::uint64_t revision) const
{
    transaction->Append(
        "INSERT INTO sc_collection_audit(account_id, type_id, collection_id, action_kind, source_kind, source_id, "
        "character_guid, actor_account_id, actor_guid, revision, result_code) "
        "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
        accountId, typeId, collectionId, actionKind, 1, 0, characterGuid, accountId, characterGuid, revision, 0);
}

bool TransmogProjectionService::CommitTransaction(CharacterDatabaseTransaction& transaction) const
{
    bool committed = false;
    try
    {
        TransactionCallback callback = CharacterDatabase.AsyncCommitTransaction(transaction);
        committed = callback.m_future.get();
    }
    catch (std::exception const& exception)
    {
        LOG_ERROR("module.solocollections.wardrobe",
            "event=wardrobe_transaction result=exception what={}", exception.what());
    }
    return committed;
}

void TransmogProjectionService::RememberQuote(ObjectGuid characterGuid, std::string_view entries,
    std::uint32_t copper)
{
    std::scoped_lock lock(_mutex);
    _quotes[characterGuid.GetCounter()] = QuoteCache { std::string(entries), copper, NowMs() };
}

std::optional<std::uint32_t> TransmogProjectionService::CachedQuoteCopper(ObjectGuid characterGuid,
    std::string_view entries) const
{
    std::scoped_lock lock(_mutex);
    auto found = _quotes.find(characterGuid.GetCounter());
    if (found == _quotes.end() || found->second.Entries != entries)
        return std::nullopt;
    if (NowMs() - found->second.AtMs > QuoteCacheMs)
        return std::nullopt;
    return found->second.Copper;
}

TransmogProjectionService::ParsedIntent TransmogProjectionService::EvaluateIntent(Player* player,
    std::string_view entries) const
{
    ParsedIntent intent;
    auto parsed = ParseApplyEntries(entries);
    if (!parsed || parsed->empty())
    {
        intent.Status = "INVALID_REQUEST";
        return intent;
    }

    std::uint64_t copper = 0;
    for (auto const& [inventorySlot, collectionId] : *parsed)
    {
        intent.Requests.emplace(inventorySlot, collectionId);
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, inventorySlot);
        if (IsHideVisualId(collectionId))
        {
            intent.WarningMask |= WarningIncludesHide;
            if (!item)
            {
                intent.WarningMask |= WarningNoItemInSlot;
                continue;
            }
            if (!sTransmogrification->GetAllowHiddenTransmog())
            {
                intent.Status = "UNSUPPORTED";
                return intent;
            }
            continue;
        }
        if (IsReservedAppearanceId(collectionId))
        {
            intent.Status = "UNKNOWN_IDENTITY";
            return intent;
        }
        if (!item)
        {
            intent.Status = "INVALID_TARGET_SLOT";
            return intent;
        }
        AccountId accountId(AccountOf(player));
        bool owned = GetAccountCollectionService().Evaluate(
            accountId, { AppearanceCollectionTypeId, CollectionId(collectionId) }).IsSuccess();
        if (!owned)
        {
            intent.Status = "NOT_OWNED";
            return intent;
        }
        std::optional<std::uint32_t> sourceItemId = GetAppearanceService().ResolveOwnedSource(
            player, CollectionId(collectionId), inventorySlot);
        if (!sourceItemId)
        {
            intent.Status = CollectedApplyFailureStatus(player, CollectionId(collectionId), item->GetTemplate());
            return intent;
        }
        std::uint32_t currentFake = sTransmogrification->GetFakeEntry(item->GetGUID());
        if (currentFake != 0)
            intent.WarningMask |= WarningReplacesExisting;
        if (currentFake != *sourceItemId)
            AddSlotCopper(copper, SlotSellPriceCopper(sObjectMgr->GetItemTemplate(*sourceItemId)));
    }

    intent.Copper = static_cast<std::uint32_t>(copper);
    intent.Status = "ACCEPTED";
    return intent;
}

Sc2WardrobeOutcome TransmogProjectionService::Quote(Player* player, std::string_view entries)
{
    if (!player || !player->GetSession())
        return Failure("INVALID_REQUEST");
    if (auto cached = CachedQuoteCopper(player->GetGUID(), entries))
    {
        ParsedIntent intent = EvaluateIntent(player, entries);
        Sc2WardrobeOutcome outcome = Failure(intent.Status, CharacterAppliedCollectionTypeId.Value(), 1,
            intent.WarningMask, intent.Status == "ACCEPTED" ? *cached : 0);
        if (intent.Status == "ACCEPTED")
            outcome.Copper = *cached;
        return outcome;
    }
    ParsedIntent intent = EvaluateIntent(player, entries);
    if (intent.Status == "ACCEPTED")
        RememberQuote(player->GetGUID(), entries, intent.Copper);
    return Failure(intent.Status, CharacterAppliedCollectionTypeId.Value(), 1, intent.WarningMask, intent.Copper);
}

Sc2WardrobeOutcome TransmogProjectionService::Apply(Player* player, std::string_view entries)
{
    if (!player || !player->GetSession())
        return Failure("INVALID_REQUEST");

    ParsedIntent intent = EvaluateIntent(player, entries);
    if (intent.Status != "ACCEPTED")
        return Failure(intent.Status, CharacterAppliedCollectionTypeId.Value(), 1, intent.WarningMask, intent.Copper);

    if (auto quoted = CachedQuoteCopper(player->GetGUID(), entries); quoted && *quoted != intent.Copper)
        return Failure("COST_CHANGED", CharacterAppliedCollectionTypeId.Value(), 1, intent.WarningMask, intent.Copper);
    if (intent.Copper && !player->HasEnoughMoney(intent.Copper))
        return Failure("INSUFFICIENT_FUNDS", CharacterAppliedCollectionTypeId.Value(), 1, intent.WarningMask, intent.Copper);

    EnsureCharacterLoaded(player->GetGUID());
    WardrobeSlotValues current {};
    {
        std::scoped_lock lock(_mutex);
        current = EnsureApplied(player->GetGUID()).Slots;
    }

    WardrobeSlotValues next = current;
    std::map<std::uint8_t, std::uint32_t> itemEntries;
    bool anyProjectionChange = false;
    for (auto const& [inventorySlot, collectionId] : intent.Requests)
    {
        auto index = WardrobeIndexForInventorySlot(inventorySlot);
        if (!index)
            continue;
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, inventorySlot);
        if (IsHideVisualId(collectionId))
        {
            if (!item)
                continue;
            if (next[*index] != HideVisualCollectionId)
            {
                next[*index] = HideVisualCollectionId;
                anyProjectionChange = true;
            }
            if (sTransmogrification->GetFakeEntry(item->GetGUID()) != HIDDEN_ITEM_ID)
                itemEntries.emplace(inventorySlot, HIDDEN_ITEM_ID);
            continue;
        }
        if (next[*index] != collectionId)
        {
            next[*index] = collectionId;
            anyProjectionChange = true;
        }
        std::optional<std::uint32_t> sourceItemId = GetAppearanceService().ResolveOwnedSource(
            player, CollectionId(collectionId), inventorySlot);
        if (sourceItemId && item && sTransmogrification->GetFakeEntry(item->GetGUID()) != *sourceItemId)
            itemEntries.emplace(inventorySlot, *sourceItemId);
    }

    if (!anyProjectionChange && itemEntries.empty())
    {
        Sc2WardrobeOutcome outcome = Failure("ACCEPTED", CharacterAppliedCollectionTypeId.Value(), 1,
            intent.WarningMask, 0);
        outcome.Revision = AppliedRevision(player->GetGUID());
        return outcome;
    }

    std::uint64_t revision = 0;
    {
        std::scoped_lock lock(_mutex);
        revision = EnsureApplied(player->GetGUID()).Revision + 1;
    }

    bool committed = false;
    if (!itemEntries.empty())
    {
        TransmogApplyResult result = sTransmogrification->TryApplyCollectedAppearances(
            player, itemEntries, ObjectGuid::Empty, TransmogApplySource::Wardrobe, true,
            [this, player, &next, revision](CharacterDatabaseTransaction& transaction)
            {
                AppendAppliedSql(transaction, player->GetGUID(), next, revision);
                AppendAuditSql(transaction, AccountOf(player), CharacterAppliedCollectionTypeId.Value(),
                    1, AuditApply, CharacterGuid(player), revision);
            });
        committed = result.IsSuccess();
        if (!committed)
            return Failure(result.Code == LANG_TRANSMOG_DATABASE_ERROR ? "DB_UNAVAILABLE" : "INVALID_REQUEST",
                CharacterAppliedCollectionTypeId.Value(), 1, intent.WarningMask, intent.Copper);
    }
    else
    {
        CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
        AppendAppliedSql(transaction, player->GetGUID(), next, revision);
        AppendAuditSql(transaction, AccountOf(player), CharacterAppliedCollectionTypeId.Value(),
            1, AuditApply, CharacterGuid(player), revision);
        committed = CommitTransaction(transaction);
        if (!committed)
            return Failure("DB_UNAVAILABLE", CharacterAppliedCollectionTypeId.Value(), 1,
                intent.WarningMask, intent.Copper);
    }

    if (intent.Copper)
        player->ModifyMoney(-static_cast<int32>(intent.Copper), false);

    {
        std::scoped_lock lock(_mutex);
        AppliedState& state = EnsureApplied(player->GetGUID());
        state.Slots = next;
        state.Revision = revision;
        state.Loaded = true;
        EnqueueAppliedPush(player->GetGUID(), AccountOf(player));
    }

    Sc2WardrobeOutcome outcome = Failure("ACCEPTED", CharacterAppliedCollectionTypeId.Value(), 1,
        intent.WarningMask, intent.Copper);
    outcome.Revision = revision;
    return outcome;
}

Sc2WardrobeOutcome TransmogProjectionService::Clear(Player* player, std::string_view entries)
{
    if (!player || !player->GetSession())
        return Failure("INVALID_REQUEST");
    auto indices = ParseClearIndices(entries);
    if (!indices || indices->empty())
        return Failure("INVALID_REQUEST");

    EnsureCharacterLoaded(player->GetGUID());

    WardrobeSlotValues current {};
    std::uint64_t revision = 0;
    {
        std::scoped_lock lock(_mutex);
        AppliedState& state = EnsureApplied(player->GetGUID());
        current = state.Slots;
        revision = state.Revision + 1;
    }

    WardrobeSlotValues next = current;
    std::vector<Item*> clearedItems;
    bool any = false;
    for (std::size_t index : *indices)
    {
        std::uint8_t slot = WardrobeSlots[index].InventorySlot;
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        if (item && sTransmogrification->GetFakeEntry(item->GetGUID()) != 0)
        {
            any = true;
            clearedItems.push_back(item);
        }
        if (next[index] != 0)
        {
            any = true;
            next[index] = 0;
        }
    }
    if (!any)
        return Failure("NOTHING_EQUIPPED");

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    for (Item* item : clearedItems)
        sTransmogrification->DeleteFakeFromDB(item->GetGUID().GetCounter(), &transaction);
    AppendAppliedSql(transaction, player->GetGUID(), next, revision);
    AppendAuditSql(transaction, AccountOf(player), CharacterAppliedCollectionTypeId.Value(),
        1, AuditClear, CharacterGuid(player), revision);
    if (!CommitTransaction(transaction))
        return Failure("DB_UNAVAILABLE");

    for (Item* item : clearedItems)
        sTransmogrification->UpdateItem(player, item);

    {
        std::scoped_lock lock(_mutex);
        AppliedState& state = EnsureApplied(player->GetGUID());
        state.Slots = next;
        state.Revision = revision;
        state.Loaded = true;
        EnqueueAppliedPush(player->GetGUID(), AccountOf(player));
    }

    Sc2WardrobeOutcome outcome = Failure("ACCEPTED");
    outcome.Revision = revision;
    return outcome;
}

Sc2WardrobeOutcome TransmogProjectionService::SaveOutfit(Player* player, std::uint32_t uid,
    std::string_view nameHex, std::string_view entries)
{
    if (!player || !player->GetSession())
        return Failure("INVALID_REQUEST", AccountOutfitCollectionTypeId.Value());
    std::optional<WardrobeSlotValues> slots = DecodeWardrobeSlots(entries);
    if (!slots)
        return Failure("INVALID_REQUEST", AccountOutfitCollectionTypeId.Value());
    bool empty = std::all_of(slots->begin(), slots->end(), [](std::uint32_t value) { return value == 0; });
    if (empty)
        return Failure("OUTFIT_EMPTY", AccountOutfitCollectionTypeId.Value(), uid == 0 ? 1 : uid);
    for (std::uint32_t value : *slots)
        if (value != 0 && !IsHideVisualId(value) && IsReservedAppearanceId(value))
            return Failure("UNKNOWN_IDENTITY", AccountOutfitCollectionTypeId.Value(), uid == 0 ? 1 : uid);

    std::uint32_t accountId = AccountOf(player);
    EnsureAccountLoaded(accountId);
    AccountOutfitRecord stored;
    std::uint64_t revision = 0;
    {
        std::scoped_lock lock(_mutex);
        AccountOutfits& account = EnsureOutfits(accountId);
        if (uid == 0)
        {
            if (account.Outfits.size() >= MaxAccountOutfits)
                return Failure("OUTFIT_LIMIT", AccountOutfitCollectionTypeId.Value());
            std::array<bool, MaxAccountOutfits + 1> used {};
            for (AccountOutfitRecord const& outfit : account.Outfits)
                if (outfit.Uid >= 1 && outfit.Uid <= MaxAccountOutfits)
                    used[outfit.Uid] = true;
            for (std::uint32_t candidate = 1; candidate <= MaxAccountOutfits; ++candidate)
                if (!used[candidate])
                {
                    uid = candidate;
                    break;
                }
            if (uid == 0)
                return Failure("OUTFIT_LIMIT", AccountOutfitCollectionTypeId.Value());
        }
        else
        {
            bool exists = false;
            for (AccountOutfitRecord const& outfit : account.Outfits)
                if (outfit.Uid == uid)
                    exists = true;
            if (!exists && account.Outfits.size() >= MaxAccountOutfits)
                return Failure("OUTFIT_LIMIT", AccountOutfitCollectionTypeId.Value(), uid);
        }
        stored.Uid = uid;
        stored.NameHex = std::string(nameHex);
        stored.Slots = *slots;
        revision = account.Revision + 1;
        stored.Revision = revision;
    }

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append(
        "INSERT INTO account_sc_outfit (account_id, uid, name_hex, slot_blob, revision) "
        "VALUES ({}, {}, '{}', '{}', {}) "
        "ON DUPLICATE KEY UPDATE name_hex=VALUES(name_hex), slot_blob=VALUES(slot_blob), revision=VALUES(revision)",
        accountId, stored.Uid, stored.NameHex, EncodeWardrobeSlots(stored.Slots), revision);
    AppendAuditSql(transaction, accountId, AccountOutfitCollectionTypeId.Value(), stored.Uid,
        AuditSave, CharacterGuid(player), revision);
    if (!CommitTransaction(transaction))
        return Failure("DB_UNAVAILABLE", AccountOutfitCollectionTypeId.Value(), stored.Uid);

    {
        std::scoped_lock lock(_mutex);
        AccountOutfits& account = EnsureOutfits(accountId);
        bool replaced = false;
        for (AccountOutfitRecord& outfit : account.Outfits)
            if (outfit.Uid == stored.Uid)
            {
                outfit = stored;
                replaced = true;
                break;
            }
        if (!replaced)
            account.Outfits.push_back(stored);
        std::sort(account.Outfits.begin(), account.Outfits.end(),
            [](AccountOutfitRecord const& left, AccountOutfitRecord const& right) { return left.Uid < right.Uid; });
        account.Revision = revision;
        account.Loaded = true;
        EnqueueOutfitPush(accountId);
    }

    Sc2WardrobeOutcome outcome = Failure("ACCEPTED", AccountOutfitCollectionTypeId.Value(), stored.Uid);
    outcome.Revision = revision;
    return outcome;
}

Sc2WardrobeOutcome TransmogProjectionService::RenameOutfit(Player* player, std::uint32_t uid,
    std::string_view nameHex)
{
    if (!player || !player->GetSession() || uid == 0)
        return Failure("INVALID_REQUEST", AccountOutfitCollectionTypeId.Value(), uid == 0 ? 1 : uid);
    std::uint32_t accountId = AccountOf(player);
    EnsureAccountLoaded(accountId);
    std::uint64_t revision = 0;
    {
        std::scoped_lock lock(_mutex);
        AccountOutfits& account = EnsureOutfits(accountId);
        bool exists = false;
        for (AccountOutfitRecord const& outfit : account.Outfits)
            if (outfit.Uid == uid)
                exists = true;
        if (!exists)
            return Failure("UNKNOWN_IDENTITY", AccountOutfitCollectionTypeId.Value(), uid);
        revision = account.Revision + 1;
    }

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append(
        "UPDATE account_sc_outfit SET name_hex = '{}', revision = {} WHERE account_id = {} AND uid = {}",
        std::string(nameHex), revision, accountId, uid);
    AppendAuditSql(transaction, accountId, AccountOutfitCollectionTypeId.Value(), uid,
        AuditRename, CharacterGuid(player), revision);
    if (!CommitTransaction(transaction))
        return Failure("DB_UNAVAILABLE", AccountOutfitCollectionTypeId.Value(), uid);

    {
        std::scoped_lock lock(_mutex);
        AccountOutfits& account = EnsureOutfits(accountId);
        for (AccountOutfitRecord& outfit : account.Outfits)
            if (outfit.Uid == uid)
            {
                outfit.NameHex = std::string(nameHex);
                outfit.Revision = revision;
            }
        account.Revision = revision;
        EnqueueOutfitPush(accountId);
    }
    Sc2WardrobeOutcome outcome = Failure("ACCEPTED", AccountOutfitCollectionTypeId.Value(), uid);
    outcome.Revision = revision;
    return outcome;
}

Sc2WardrobeOutcome TransmogProjectionService::DeleteOutfit(Player* player, std::uint32_t uid)
{
    if (!player || !player->GetSession() || uid == 0)
        return Failure("INVALID_REQUEST", AccountOutfitCollectionTypeId.Value(), uid == 0 ? 1 : uid);
    std::uint32_t accountId = AccountOf(player);
    EnsureAccountLoaded(accountId);
    std::uint64_t revision = 0;
    {
        std::scoped_lock lock(_mutex);
        AccountOutfits& account = EnsureOutfits(accountId);
        bool exists = false;
        for (AccountOutfitRecord const& outfit : account.Outfits)
            if (outfit.Uid == uid)
                exists = true;
        if (!exists)
            return Failure("UNKNOWN_IDENTITY", AccountOutfitCollectionTypeId.Value(), uid);
        revision = account.Revision + 1;
    }

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append("DELETE FROM account_sc_outfit WHERE account_id = {} AND uid = {}", accountId, uid);
    AppendAuditSql(transaction, accountId, AccountOutfitCollectionTypeId.Value(), uid,
        AuditDelete, CharacterGuid(player), revision);
    if (!CommitTransaction(transaction))
        return Failure("DB_UNAVAILABLE", AccountOutfitCollectionTypeId.Value(), uid);

    {
        std::scoped_lock lock(_mutex);
        AccountOutfits& account = EnsureOutfits(accountId);
        account.Outfits.erase(std::remove_if(account.Outfits.begin(), account.Outfits.end(),
            [uid](AccountOutfitRecord const& outfit) { return outfit.Uid == uid; }), account.Outfits.end());
        account.Revision = revision;
        EnqueueOutfitPush(accountId);
    }
    Sc2WardrobeOutcome outcome = Failure("ACCEPTED", AccountOutfitCollectionTypeId.Value(), uid);
    outcome.Revision = revision;
    return outcome;
}

bool TransmogProjectionService::PrepareLegacyMerge(Player* player,
    std::map<std::uint8_t, std::uint32_t> const& slotToCollectionId,
    WardrobeSlotValues& outSlots, std::uint64_t& outRevision)
{
    if (!player || slotToCollectionId.empty())
        return false;
    EnsureCharacterLoaded(player->GetGUID());
    std::scoped_lock lock(_mutex);
    AppliedState& state = EnsureApplied(player->GetGUID());
    outSlots = state.Slots;
    for (auto const& [slot, collectionId] : slotToCollectionId)
        if (auto index = WardrobeIndexForInventorySlot(slot))
            outSlots[*index] = collectionId;
    if (SlotsEqual(outSlots, state.Slots))
        return false;
    outRevision = state.Revision + 1;
    return true;
}

void TransmogProjectionService::CommitLegacyAppliedCache(Player* player, WardrobeSlotValues const& slots,
    std::uint64_t revision)
{
    if (!player)
        return;
    std::scoped_lock lock(_mutex);
    AppliedState& state = EnsureApplied(player->GetGUID());
    state.Slots = slots;
    state.Revision = revision;
    state.Loaded = true;
    EnqueueAppliedPush(player->GetGUID(), AccountOf(player));
}

void TransmogProjectionService::SyncLegacyApplied(Player* player,
    std::map<std::uint8_t, std::uint32_t> const& slotToCollectionId)
{
    WardrobeSlotValues slots {};
    std::uint64_t revision = 0;
    if (!PrepareLegacyMerge(player, slotToCollectionId, slots, revision))
        return;
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    AppendAppliedSql(transaction, player->GetGUID(), slots, revision);
    AppendAuditSql(transaction, AccountOf(player), CharacterAppliedCollectionTypeId.Value(),
        1, AuditApply, CharacterGuid(player), revision);
    if (!CommitTransaction(transaction))
        return;
    CommitLegacyAppliedCache(player, slots, revision);
}

TransmogProjectionService& GetTransmogProjectionService()
{
    static TransmogProjectionService service;
    return service;
}
}
