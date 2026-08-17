#include "SoloCollectionsOutfitService.h"

#include "Categories/Appearance/SoloCollectionsAppearanceService.h"

#include "DatabaseEnv.h"
#include "Item.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Util.h"

#include <algorithm>
#include <exception>
#include <limits>
#include <optional>
#include <sstream>
#include <string>

namespace SoloCollections
{
namespace
{
std::optional<std::string> NormalizeOutfitName(std::string_view requested)
{
    while (!requested.empty() && (requested.front() == ' ' || requested.front() == '\t'))
        requested.remove_prefix(1);
    while (!requested.empty() && (requested.back() == ' ' || requested.back() == '\t'))
        requested.remove_suffix(1);
    if (requested.empty() || requested.size() > OutfitNameMaxBytes)
        return std::nullopt;
    for (unsigned char value : requested)
        if (value < 0x20 || value == 0x7f)
            return std::nullopt;
    std::wstring wide;
    if (!Utf8toWStr(requested, wide) || wide.empty())
        return std::nullopt;
    return std::string(requested);
}

std::optional<std::map<std::uint8_t, std::uint32_t>> ParseOutfitData(std::string const& data)
{
    std::istringstream stream(data);
    std::map<std::uint8_t, std::uint32_t> appearances;
    std::uint32_t rawSlot = 0;
    std::uint32_t entry = 0;
    while (stream >> rawSlot)
    {
        if (!(stream >> entry) || rawSlot >= EQUIPMENT_SLOT_END ||
            appearances.size() >= OutfitSlotMaxCount ||
            (entry != HIDDEN_ITEM_ID && !sObjectMgr->GetItemTemplate(entry)) ||
            !appearances.emplace(static_cast<std::uint8_t>(rawSlot), entry).second)
            return std::nullopt;
    }
    if (!stream.eof() || appearances.empty())
        return std::nullopt;
    return appearances;
}

void CommitOutfitTransactionAsync(CharacterDatabaseTransaction const& transaction, ObjectGuid characterGuid,
    std::string_view operation, std::function<void(bool)> completion)
{
    sTransmogrification->EnqueueDbCommit(transaction,
        [characterGuid, operation = std::string(operation), completion = std::move(completion)](bool committed)
        {
            if (!committed)
                LOG_ERROR("module", "SoloCollections outfit {} failed for character {}.",
                    operation, characterGuid.ToString());
            if (completion)
                completion(committed);
        });
}
}

void OutfitService::Load(ObjectGuid characterGuid)
{
    OutfitMap loaded;
    QueryResult result = CharacterDatabase.Query(
        "SELECT `PresetID`, `SetName`, `SetData` FROM `custom_transmogrification_sets` WHERE `Owner` = {}",
        characterGuid.GetCounter());
    if (result)
    {
        do
        {
            std::uint8_t outfitId = (*result)[0].Get<std::uint8_t>();
            std::optional<std::string> name = NormalizeOutfitName((*result)[1].Get<std::string>());
            std::optional<std::map<std::uint8_t, std::uint32_t>> appearances =
                ParseOutfitData((*result)[2].Get<std::string>());
            if (outfitId >= sTransmogrification->GetMaxSets() || !name || !appearances || !loaded.emplace(outfitId,
                    OutfitRecord { outfitId, std::move(*name), std::move(*appearances) }).second)
            {
                LOG_WARN("module", "SoloCollections ignored invalid legacy outfit {} for character {}.",
                    static_cast<std::uint32_t>(outfitId), characterGuid.ToString());
            }
        } while (result->NextRow());
    }
    _byCharacter[characterGuid] = std::move(loaded);
}

void OutfitService::Unload(ObjectGuid characterGuid)
{
    _byCharacter.erase(characterGuid);
}

OutfitService::OutfitMap const& OutfitService::List(ObjectGuid characterGuid) const
{
    static OutfitMap const empty;
    auto found = _byCharacter.find(characterGuid);
    return found == _byCharacter.end() ? empty : found->second;
}

OutfitRecord const* OutfitService::Find(ObjectGuid characterGuid, std::uint8_t outfitId) const
{
    OutfitMap const& outfits = List(characterGuid);
    auto found = outfits.find(outfitId);
    return found == outfits.end() ? nullptr : &found->second;
}

void OutfitService::Save(Player* player, std::string_view requestedName, OutfitCompletion completion)
{
    auto fail = [&completion](TransmogApplyResult result)
    {
        if (completion)
            completion(result);
    };

    if (!player || !player->GetSession() || !sTransmogrification->GetEnableSets())
        return fail({ LANG_TRANSMOG_INVALID_SRC_ENTRY });
    std::optional<std::string> name = NormalizeOutfitName(requestedName);
    if (!name)
        return fail({ LANG_TRANSMOG_PRESET_ERR_INVALID_NAME });

    OutfitMap& outfits = _byCharacter[player->GetGUID()];
    if (outfits.size() >= sTransmogrification->GetMaxSets())
        return fail({ LANG_TRANSMOG_INVALID_SRC_ENTRY });
    std::optional<std::uint8_t> outfitId;
    for (std::uint16_t candidate = 0; candidate < sTransmogrification->GetMaxSets(); ++candidate)
        if (!outfits.contains(static_cast<std::uint8_t>(candidate)))
        {
            outfitId = static_cast<std::uint8_t>(candidate);
            break;
        }
    if (!outfitId)
        return fail({ LANG_TRANSMOG_INVALID_SRC_ENTRY });

    std::map<std::uint8_t, std::uint32_t> appearances;
    std::uint64_t baseCost = 0;
    for (std::uint8_t slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
    {
        if (!sTransmogrification->GetSlotName(slot, player->GetSession()))
            continue;
        Item* target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        if (!target)
            continue;
        std::uint32_t entry = sTransmogrification->GetFakeEntry(target->GetGUID());
        if (!entry)
            continue;
        if (entry != HIDDEN_ITEM_ID)
        {
            ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(entry);
            if (!sourceTemplate || !sTransmogrification->SuitableForTransmogrification(player, sourceTemplate))
                continue;
            baseCost += sTransmogrification->GetSpecialPrice(sourceTemplate);
        }
        if (appearances.size() >= OutfitSlotMaxCount || !appearances.emplace(slot, entry).second)
            return fail({ LANG_TRANSMOG_INVALID_SLOT });
    }
    if (appearances.empty())
        return fail({ LANG_TRANSMOG_INVALID_SRC_ENTRY });

    double configuredCost = static_cast<double>(baseCost) *
        static_cast<double>(sTransmogrification->GetSetCostModifier()) +
        static_cast<double>(sTransmogrification->GetSetCopperCost());
    if (configuredCost < 0.0)
        configuredCost = 0.0;
    if (configuredCost > static_cast<double>(MAX_MONEY_AMOUNT))
        return fail({ LANG_TRANSMOG_NOT_ENOUGH_MONEY });
    std::uint32_t cost = static_cast<std::uint32_t>(configuredCost);
    if (cost && !player->HasEnoughMoney(cost))
        return fail({ LANG_TRANSMOG_NOT_ENOUGH_MONEY });

    std::ostringstream serialized;
    for (auto const& [slot, entry] : appearances)
        serialized << static_cast<std::uint32_t>(slot) << ' ' << entry << ' ';
    std::string escapedName = *name;
    std::string escapedData = serialized.str();
    CharacterDatabase.EscapeString(escapedName);
    CharacterDatabase.EscapeString(escapedData);
    ObjectGuid characterGuid = player->GetGUID();
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append(
        "REPLACE INTO `custom_transmogrification_sets` (`Owner`, `PresetID`, `SetName`, `SetData`) "
        "VALUES ({}, {}, '{}', '{}')",
        characterGuid.GetCounter(), static_cast<std::uint32_t>(*outfitId), escapedName, escapedData);
    CommitOutfitTransactionAsync(transaction, characterGuid, "save",
        [this, characterGuid, outfitId = *outfitId, name = std::move(*name),
            appearances = std::move(appearances), cost, completion = std::move(completion)](bool committed) mutable
        {
            if (!committed)
            {
                if (completion)
                    completion({ LANG_TRANSMOG_DATABASE_ERROR });
                return;
            }

            auto found = _byCharacter.find(characterGuid);
            if (found != _byCharacter.end())
                found->second.emplace(outfitId,
                    OutfitRecord { outfitId, std::move(name), std::move(appearances) });
            if (cost)
                if (Player* player = ObjectAccessor::FindConnectedPlayer(characterGuid))
                    player->ModifyMoney(-static_cast<std::int32_t>(cost), false);
            if (completion)
                completion({ LANG_TRANSMOG_OK, static_cast<std::uint32_t>(outfitId) + 1 });
        });
}

void OutfitService::Delete(Player* player, std::uint8_t outfitId, OutfitCompletion completion)
{
    if (!player || !player->GetSession() || !Find(player->GetGUID(), outfitId))
    {
        if (completion)
            completion({ LANG_TRANSMOG_INVALID_SRC_ENTRY });
        return;
    }
    ObjectGuid characterGuid = player->GetGUID();
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append("DELETE FROM `custom_transmogrification_sets` WHERE `Owner` = {} AND `PresetID` = {}",
        characterGuid.GetCounter(), static_cast<std::uint32_t>(outfitId));
    CommitOutfitTransactionAsync(transaction, characterGuid, "delete",
        [this, characterGuid, outfitId, completion = std::move(completion)](bool committed)
        {
            if (!committed)
            {
                if (completion)
                    completion({ LANG_TRANSMOG_DATABASE_ERROR });
                return;
            }
            auto found = _byCharacter.find(characterGuid);
            if (found != _byCharacter.end())
                found->second.erase(outfitId);
            if (completion)
                completion({ LANG_TRANSMOG_OK, 1 });
        });
}

void OutfitService::Apply(Player* player, std::uint8_t outfitId,
    ObjectGuid interactionGuid, OutfitCompletion completion) const
{
    auto fail = [&completion](TransmogApplyResult result)
    {
        if (completion)
            completion(result);
    };

    if (!player || !player->GetSession())
        return fail({ LANG_TRANSMOG_INVALID_SRC_ENTRY });
    OutfitRecord const* outfit = Find(player->GetGUID(), outfitId);
    if (!outfit || outfit->Appearances.empty() || outfit->Appearances.size() > OutfitSlotMaxCount)
        return fail({ LANG_TRANSMOG_INVALID_SRC_ENTRY });
    GetAppearanceService().TryApplyCollectedAppearances(
        player, outfit->Appearances, interactionGuid, TransmogApplySource::Outfit, true, std::move(completion));
}

OutfitService& GetOutfitService()
{
    static OutfitService service;
    return service;
}
}
