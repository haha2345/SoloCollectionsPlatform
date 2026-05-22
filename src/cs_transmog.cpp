/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "Chat.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Transmogrification.h"
#include "Tokenize.h"
#include "DatabaseEnv.h"
#include "SpellMgr.h"

using namespace Acore::ChatCommands;

class transmog_commandscript : public CommandScript
{
public:
    transmog_commandscript() : CommandScript("transmog_commandscript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable addCollectionTable =
        {
            { "set", HandleAddTransmogItemSet,    SEC_MODERATOR, Console::Yes },
            { "",    HandleAddTransmogItem,       SEC_MODERATOR, Console::Yes },
        };

        static ChatCommandTable transmogTable =
        {
            { "add",        addCollectionTable                                              },
            { "check",      HandleCheckTransmog,           SEC_GAMEMASTER,    Console::Yes },
            { "",           HandleDisableTransMogVisual,   SEC_PLAYER,        Console::No  },
            { "sync",       HandleSyncTransMogCommand,     SEC_PLAYER,        Console::No  },
            { "portable",   HandleTransmogPortableCommand, SEC_PLAYER,        Console::No  },
            { "interface",  HandleInterfaceOption,         SEC_PLAYER,        Console::No  },
            { "disclaimer", HandleDisclaimerOption,        SEC_PLAYER,        Console::No  },
            { "reload",     HandleReloadTransmogConfig,    SEC_ADMINISTRATOR, Console::Yes }
        };

        static ChatCommandTable commandTable =
        {
            { "transmog", transmogTable },
        };

        return commandTable;
    }

    static bool HandleSyncTransMogCommand(ChatHandler* handler)
    {
        Player* player = handler->GetPlayer();
        uint32 accountId = player->GetSession()->GetAccountId();
        handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_BEGIN_SYNC);

        for (uint32 itemId : sTransmogrification->collectionCache[accountId])
            handler->PSendSysMessage("TRANSMOG_SYNC:{}", itemId);

        handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_COMPLETE_SYNC);
        return true;
    }

    static bool HandleDisableTransMogVisual(ChatHandler* handler, bool hide)
    {
        Player* player = handler->GetPlayer();

        if (hide)
        {
            player->UpdatePlayerSetting("mod-transmog", SETTING_HIDE_TRANSMOG, 0);
            handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_SHOW);
        }
        else
        {
            player->UpdatePlayerSetting("mod-transmog", SETTING_HIDE_TRANSMOG, 1);
            handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_HIDE);
        }

        player->UpdateObjectVisibility();
        return true;
    }

    static bool HandleAddTransmogItem(ChatHandler* handler, Optional<PlayerIdentifier> player, ItemTemplate const* itemTemplate)
    {
        if (!sTransmogrification->GetUseCollectionSystem())
            return true;

        if (!sObjectMgr->GetItemTemplate(itemTemplate->ItemId))
        {
            handler->PSendSysMessage(LANG_COMMAND_ITEMIDINVALID, itemTemplate->ItemId);
            handler->SetSentErrorMessage(true);
            return false;
        }

        if (!player)
            player = PlayerIdentifier::FromTargetOrSelf(handler);

        if (!player)
            return false;

        Player* target = player->GetConnectedPlayer();
        bool isNotConsole = handler->GetSession();
        bool suitableForTransmog;

        if (target)
            suitableForTransmog = sTransmogrification->SuitableForTransmogrification(target, itemTemplate);
        else
            suitableForTransmog = sTransmogrification->SuitableForTransmogrification(player->GetGUID(), itemTemplate);

        if (!sTransmogrification->GetTrackUnusableItems() && !suitableForTransmog)
        {
            handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_ADD_UNSUITABLE);
            handler->SetSentErrorMessage(true);
            return true;
        }

        if (itemTemplate->Class != ITEM_CLASS_ARMOR && itemTemplate->Class != ITEM_CLASS_WEAPON)
        {
            handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_ADD_FORBIDDEN);
            handler->SetSentErrorMessage(true);
            return true;
        }

        auto guid = player->GetGUID();
        uint32 accountId = sCharacterCache->GetCharacterAccountIdByGuid(guid);
        uint32 itemId = itemTemplate->ItemId;

        std::stringstream tempStream;
        tempStream << std::hex << ItemQualityColors[itemTemplate->Quality];
        std::string itemQuality = tempStream.str();
        std::string itemName = itemTemplate->Name1;

        if (target) {
            // get locale item name
            int loc_idex = target->GetSession()->GetSessionDbLocaleIndex();
            if (ItemLocale const* il = sObjectMgr->GetItemLocale(itemId))
                ObjectMgr::GetLocaleString(il->Name, loc_idex, itemName);
        }

        std::string playerName = player->GetName();
        std::string nameLink = handler->playerLink(playerName);

        if (sTransmogrification->AddCollectedAppearance(accountId, itemId))
        {
            // Notify target of new item in appearance collection
            if (target && !(target->GetPlayerSetting("mod-transmog", SETTING_HIDE_TRANSMOG).value) && !sTransmogrification->CanNeverTransmog(itemTemplate))
                ChatHandler(target->GetSession()).PSendSysMessage(R"(|c{}|Hitem:{}:0:0:0:0:0:0:0:0|h[{}]|h|r has been added to your appearance collection.)", itemQuality.c_str(), itemId, itemName.c_str());

            // Feedback of successful command execution to GM
            if (isNotConsole && target != handler->GetPlayer())
                handler->PSendSysMessage(R"(|c{}|Hitem:{}:0:0:0:0:0:0:0:0|h[{}]|h|r has been added to the appearance collection of Player {}.)", itemQuality.c_str(), itemId, itemName.c_str(), nameLink);

            CharacterDatabase.Execute("INSERT INTO custom_unlocked_appearances (account_id, item_template_id) VALUES ({}, {})", accountId, itemId);
        }
        else
        {
            // Feedback of failed command execution to GM
            if (isNotConsole)
            {
                handler->PSendSysMessage(R"(Player {} already has item |c{}|Hitem:{}:0:0:0:0:0:0:0:0|h[{}]|h|r in the appearance collection.)", nameLink, itemQuality.c_str(), itemId, itemName.c_str());
                handler->SetSentErrorMessage(true);
            }
        }

        return true;
    }

    static bool HandleAddTransmogItemSet(ChatHandler* handler, Optional<PlayerIdentifier> player, Variant<Hyperlink<itemset>, uint32> itemSetId)
    {
        if (!sTransmogrification->GetUseCollectionSystem())
            return true;

        if (!*itemSetId)
        {
            handler->PSendSysMessage(LANG_NO_ITEMS_FROM_ITEMSET_FOUND, uint32(itemSetId));
            handler->SetSentErrorMessage(true);
            return false;
        }

        if (!player)
            player = PlayerIdentifier::FromTargetOrSelf(handler);

        if (!player)
            return false;

        Player* target = player->GetConnectedPlayer();
        ItemSetEntry const* set = sItemSetStore.LookupEntry(uint32(itemSetId));
        bool isNotConsole = handler->GetSession();

        if (!set)
        {
            handler->PSendSysMessage(LANG_NO_ITEMS_FROM_ITEMSET_FOUND, uint32(itemSetId));
            handler->SetSentErrorMessage(true);
            return false;
        }

        auto guid = player->GetGUID();
        CharacterCacheEntry const* playerData = sCharacterCache->GetCharacterCacheByGuid(guid);
        if (!playerData)
            return false;

        bool added = false;
        uint32 error = 0; // holds a TransmogStrings id, 0 = no error
        uint32 itemId;
        uint32 accountId = playerData->AccountId;

        for (uint32 i = 0; i < MAX_ITEM_SET_ITEMS; ++i)
        {
            itemId = set->itemId[i];
            if (itemId)
            {
                ItemTemplate const* itemTemplate = sObjectMgr->GetItemTemplate(itemId);
                if (itemTemplate)
                {
                    if (!sTransmogrification->GetTrackUnusableItems() && (
                            (target && !sTransmogrification->SuitableForTransmogrification(target, itemTemplate)) ||
                            !sTransmogrification->SuitableForTransmogrification(guid, itemTemplate)
                            ))
                    {
                        error = LANG_TRANSMOG_CMD_ADD_UNSUITABLE;
                        continue;
                    }
                    if (itemTemplate->Class != ITEM_CLASS_ARMOR && itemTemplate->Class != ITEM_CLASS_WEAPON)
                    {
                        error = LANG_TRANSMOG_CMD_ADD_FORBIDDEN;
                        continue;
                    }

                    if (sTransmogrification->AddCollectedAppearance(accountId, itemId))
                    {
                        CharacterDatabase.Execute("INSERT INTO custom_unlocked_appearances (account_id, item_template_id) VALUES ({}, {})", accountId, itemId);
                        added = true;
                    }
                }
            }
        }

        if (!added && error > 0)
        {
            handler->PSendModuleSysMessage("mod-transmog", error);
            handler->SetSentErrorMessage(true);
            return true;
        }

        int locale = handler->GetSessionDbcLocale();
        std::string setName = set->name[locale];
        std::string nameLink = handler->playerLink(player->GetName());

        // Feedback of command execution to GM
        if (isNotConsole)
        {
            // Failed command execution
            if (!added)
            {
                handler->PSendSysMessage("Player {} already has ItemSet |cffffffff|Hitemset:{}|h[{} {}]|h|r in the appearance collection.", nameLink, uint32(itemSetId), setName.c_str(), localeNames[locale]);
                handler->SetSentErrorMessage(true);
                return true;
            }

            // Successful command execution
            if (target != handler->GetPlayer())
                handler->PSendSysMessage("ItemSet |cffffffff|Hitemset:{}|h[{} {}]|h|r has been added to the appearance collection of Player {}.", uint32(itemSetId), setName.c_str(), localeNames[locale], nameLink);
        }

        // Notify target of new item in appearance collection
        if (target && !(target->GetPlayerSetting("mod-transmog", SETTING_HIDE_TRANSMOG).value))
            ChatHandler(target->GetSession()).PSendSysMessage("ItemSet |cffffffff|Hitemset:%d|h[{} {}]|h|r has been added to your appearance collection.", uint32(itemSetId), setName.c_str(), localeNames[locale]);

        return true;
    }

    static bool HandleTransmogPortableCommand(ChatHandler* handler)
    {
        if (!sTransmogrification->IsPortableNPCEnabled)
        {
            handler->SendErrorMessage("The portable transmogrification NPC is disabled.");
            return true;
        }

        if (!sTransmogrification->IsTransmogPlusEnabled)
        {
            handler->SendErrorMessage("The portable transmogrification NPC is a plus feature. Plus features are currently disabled.");
            return true;
        }

        Player* player = PlayerIdentifier::FromSelf(handler)->GetConnectedPlayer();

        if (!sTransmogrification->IsPlusFeatureEligible(player->GetGUID(), PLUS_FEATURE_PET))
        {
            handler->SendErrorMessage("You are not eligible for the portable transmogrification NPC. Please check your subscription level.");
            return true;
        }

        if (!sSpellMgr->GetSpellInfo(sTransmogrification->PetSpellId))
        {
            handler->SendErrorMessage("The portable transmogrification NPC spell is not available.");
            return true;
        }

        player->CastSpell((Unit*)nullptr, sTransmogrification->PetSpellId, true);
        return true;
    };

    static bool HandleInterfaceOption(ChatHandler* handler, bool enable)
    {
        handler->GetPlayer()->UpdatePlayerSetting("mod-transmog", SETTING_VENDOR_INTERFACE, enable);
        handler->PSendModuleSysMessage("mod-transmog", enable ? LANG_TRANSMOG_CMD_VENDOR_INTERFACE_ENABLE : LANG_TRANSMOG_CMD_VENDOR_INTERFACE_DISABLE);
        return true;
    }

    static bool HandleDisclaimerOption(ChatHandler* handler, bool enable)
    {
        Player* player = handler->GetPlayer();
        if (enable)
        {
            player->UpdatePlayerSetting("mod-transmog", SETTING_HIDE_SET_DISCLAIMER, 0);
            handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_DISCLAIMER_ON);
        }
        else
        {
            player->UpdatePlayerSetting("mod-transmog", SETTING_HIDE_SET_DISCLAIMER, 1);
            handler->PSendModuleSysMessage("mod-transmog", LANG_TRANSMOG_CMD_DISCLAIMER_OFF);
        }
        return true;
    }

    static bool HandleCheckTransmog(ChatHandler* handler, PlayerIdentifier playerIdent, ItemTemplate const* destItem, ItemTemplate const* srcItem)
    {
        static constexpr char const* MOD = "mod-transmog";

        WorldSession* gSession = handler->GetSession();
        auto itemDisplay = [&](uint32 itemId) -> std::string
        {
            if (gSession)
                return sTransmogrification->GetItemLink(itemId, gSession);
            ItemTemplate const* tpl = sObjectMgr->GetItemTemplate(itemId);
            return tpl ? Acore::StringFormat("{} (ID: {})", tpl->Name1, itemId)
                       : Acore::StringFormat("ID: {}", itemId);
        };

        // Header
        handler->PSendModuleSysMessage(MOD, LANG_TRANSMOG_CHECK_HEADER);
        handler->PSendModuleSysMessage(MOD, LANG_TRANSMOG_CHECK_DEST,   itemDisplay(destItem->ItemId));
        handler->PSendModuleSysMessage(MOD, LANG_TRANSMOG_CHECK_SRC,    itemDisplay(srcItem->ItemId));
        handler->PSendModuleSysMessage(MOD, LANG_TRANSMOG_CHECK_PLAYER, playerIdent.GetName());

        // Resolve player
        ObjectGuid playerGuid = playerIdent.GetGUID();
        Player*    player     = playerIdent.GetConnectedPlayer();

        CharacterCacheEntry const* cache = sCharacterCache->GetCharacterCacheByGuid(playerGuid);
        if (!cache)
        {
            handler->PSendModuleSysMessage(MOD, LANG_TRANSMOG_CHECK_PLAYER_NOT_FOUND, playerIdent.GetName());
            return true;
        }

        uint32 rawGuid     = static_cast<uint32>(playerGuid.GetCounter());
        uint8  playerRace  = cache->Race;
        uint32 playerLevel = cache->Level;
        uint32 raceMask    = 1u << (playerRace - 1);
        uint32 classMask   = 1u << (cache->Class - 1);
        TeamId teamId      = Player::TeamIdForRace(playerRace);

        std::unordered_map<uint32, uint32> offlineSkills;
        if (!player)
        {
            if (QueryResult res = CharacterDatabase.Query(
                    "SELECT `skill`, `value` FROM `character_skills` WHERE `guid` = {}", rawGuid))
            {
                do {
                    Field* f = res->Fetch();
                    offlineSkills[f[0].Get<uint16>()] = f[1].Get<uint16>();
                } while (res->NextRow());
            }
        }

        auto skillValue = [&](uint32 skillId) -> uint32
        {
            if (player) return player->GetSkillValue(skillId);
            auto it = offlineSkills.find(skillId);
            return it != offlineSkills.end() ? it->second : 0u;
        };

        auto hasSpellFn = [&](uint32 spellId) -> bool
        {
            if (player) return player->HasSpell(spellId);
            return static_cast<bool>(CharacterDatabase.Query(
                "SELECT `spell` FROM `character_spell` WHERE `guid` = {} AND `spell` = {}",
                rawGuid, spellId));
        };

        // Section: collects failure messages; skips are silently ignored
        struct Section {
            bool ok          = true;
            bool whitelisted = false;
            std::vector<std::string> fails;

            void check(bool passed, std::string failMsg)
            {
                if (!passed) { ok = false; fails.push_back(std::move(failMsg)); }
            }
        };

        // Render one section line: "label  [+] All checks passed" or "label  [-] fail1; fail2"
        std::string okMsg = handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_SECTION_OK);
        auto printSection = [&](std::string const& label, Section const& sec, std::string const& whitelistMsg = "")
        {
            std::string line = label + "  ";
            if (sec.whitelisted)
            {
                line += "[~] " + whitelistMsg;
            }
            else if (sec.ok)
            {
                line += "[+] " + okMsg;
            }
            else
            {
                line += "[-] ";
                for (size_t i = 0; i < sec.fails.size(); ++i)
                {
                    if (i) line += "; ";
                    line += sec.fails[i];
                }
            }
            handler->SendSysMessage(line);
        };

        // ----------------------------------------------------------------
        // Pair checks
        // ----------------------------------------------------------------
        Section pair;

        pair.check(srcItem->ItemId != destItem->ItemId,
            handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_IDS_SAME));
        pair.check(srcItem->DisplayInfoID != destItem->DisplayInfoID,
            handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_DISP_SAME));
        pair.check(srcItem->Class == destItem->Class,
            handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_CLASS_FAIL));

        auto isForbiddenType = [](uint32 t) -> bool
        {
            return t == INVTYPE_BAG    || t == INVTYPE_RELIC   || t == INVTYPE_FINGER ||
                   t == INVTYPE_TRINKET || t == INVTYPE_AMMO  || t == INVTYPE_QUIVER;
        };

        pair.check(!isForbiddenType(destItem->InventoryType),
            handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_DEST_TYPE_FAIL));
        pair.check(!isForbiddenType(srcItem->InventoryType),
            handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_SRC_TYPE_FAIL));

        {
            bool srcRanged  = sTransmogrification->IsRangedWeapon(srcItem->Class,  srcItem->SubClass);
            bool destRanged = sTransmogrification->IsRangedWeapon(destItem->Class, destItem->SubClass);
            pair.check(srcRanged == destRanged,
                handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_RANGED_FAIL));
        }

        if (srcItem->SubClass != destItem->SubClass)
            pair.check(sTransmogrification->IsSubclassMismatchAllowed(player, srcItem, destItem),
                handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_SUB_DENIED));

        if (srcItem->InventoryType != destItem->InventoryType)
            pair.check(sTransmogrification->IsInvTypeMismatchAllowed(srcItem, destItem),
                handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_PAIR_INV_DENIED));

        // ----------------------------------------------------------------
        // Per-item checks  (collect into a section, print later)
        // ----------------------------------------------------------------
        auto gatherItemChecks = [&](ItemTemplate const* proto, Section& sec)
        {
            if (sTransmogrification->IsAllowed(proto->ItemId))
            {
                sec.whitelisted = true;
                return;
            }

            {
                bool ok = proto->Class == ITEM_CLASS_ARMOR || proto->Class == ITEM_CLASS_WEAPON;
                sec.check(ok, handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_CLASS_FAIL));
                if (!ok)
                    return;
            }

            sec.check(!sTransmogrification->IsNotAllowed(proto->ItemId),
                handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_BLACKLISTED));

            sec.check(sTransmogrification->IsAllowedQuality(proto->Quality, playerGuid),
                handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_QUALITY_FAIL));

            if (proto->Class == ITEM_CLASS_WEAPON && proto->SubClass == ITEM_SUBCLASS_WEAPON_FISHING_POLE)
                sec.check(sTransmogrification->AllowFishingPoles,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_POLE_FAIL));

            if (proto->HolidayId)
                sec.check(sTransmogrification->IgnoreReqEvent || IsHolidayActive((HolidayIds)proto->HolidayId),
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_EVENT_FAIL));

            if (!sTransmogrification->IgnoreReqStats && !proto->RandomProperty && !proto->RandomSuffix && proto->StatsCount > 0)
            {
                bool hasStats = false;
                for (uint8 i = 0; i < proto->StatsCount; ++i)
                    if (proto->ItemStat[i].ItemStatValue != 0) { hasStats = true; break; }
                sec.check(hasStats, handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_STAT_FAIL));
            }

            {
                uint32 subclassSkill = proto->GetSkill();
                if (proto->SubClass > 0 && subclassSkill)
                {
                    uint32 sv = skillValue(subclassSkill);
                    bool ok;
                    if (proto->Class == ITEM_CLASS_ARMOR)
                        ok = sv > 0 || sTransmogrification->AllowMixedArmorTypes;
                    else
                        ok = sv > 0 || sTransmogrification->AllowMixedWeaponTypes == MIXED_WEAPONS_LOOSE;
                    sec.check(ok, handler->PGetParseModuleString(MOD,
                        LANG_TRANSMOG_CHECK_ITEM_PROF_FAIL, subclassSkill));
                }
            }

            if (proto->HasFlag2(ITEM_FLAG2_FACTION_HORDE))
                sec.check(teamId == TEAM_HORDE,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_FACTION_FAIL));
            else if (proto->HasFlag2(ITEM_FLAG2_FACTION_ALLIANCE))
                sec.check(teamId == TEAM_ALLIANCE,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_FACTION_FAIL));

            if (!sTransmogrification->IgnoreReqClass)
                sec.check((proto->AllowableClass & classMask) != 0,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_CLASS_REQ_FAIL));

            if (!sTransmogrification->IgnoreReqRace)
                sec.check((proto->AllowableRace & raceMask) != 0,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_RACE_REQ_FAIL));

            if (!sTransmogrification->IgnoreReqSkill && proto->RequiredSkill != 0)
            {
                uint32 sv = skillValue(proto->RequiredSkill);
                sec.check(sv >= proto->RequiredSkillRank,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_SKILL_FAIL,
                        proto->RequiredSkill, proto->RequiredSkillRank, sv));
            }

            if (!sTransmogrification->IgnoreLevelRequirement(playerGuid))
                sec.check(playerLevel >= proto->RequiredLevel,
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_LEVEL_FAIL,
                        proto->RequiredLevel, playerLevel));

            bool skipSpell = sTransmogrification->AllowLowerTiers &&
                             sTransmogrification->TierAvailable(player, rawGuid, proto->SubClass);
            if (!sTransmogrification->IgnoreReqSpell && proto->RequiredSpell != 0 && !skipSpell)
                sec.check(hasSpellFn(proto->RequiredSpell),
                    handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_SPELL_FAIL, proto->RequiredSpell));
        };

        Section destSec, srcSec;
        gatherItemChecks(destItem, destSec);
        gatherItemChecks(srcItem, srcSec);

        // ----------------------------------------------------------------
        // Collection check
        // ----------------------------------------------------------------
        bool collOk = true;
        std::string collLine = handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_SECTION_COLL) + "  ";
        if (!sTransmogrification->GetUseCollectionSystem())
        {
            collLine += "[~] " + handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_COLL_DISABLED);
        }
        else
        {
            uint32 accountId = sCharacterCache->GetCharacterAccountIdByGuid(playerGuid);
            auto const& collCache = sTransmogrification->collectionCache[accountId];
            bool inCollection = collCache.find(srcItem->ItemId) != collCache.end();
            collOk = inCollection;
            collLine += inCollection
                ? "[+] " + okMsg
                : "[-] " + handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_COLL_NOT_FOUND);
        }

        // ----------------------------------------------------------------
        // Print all section results, then final verdict
        // ----------------------------------------------------------------
        std::string whitelistMsg = handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_ITEM_WHITELISTED);
        printSection(handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_SECTION_PAIR), pair);
        printSection(handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_SECTION_ITEM, itemDisplay(destItem->ItemId)), destSec, whitelistMsg);
        printSection(handler->PGetParseModuleString(MOD, LANG_TRANSMOG_CHECK_SECTION_ITEM, itemDisplay(srcItem->ItemId)),  srcSec,  whitelistMsg);
        handler->SendSysMessage(collLine);

        bool overallOk = pair.ok && destSec.ok && srcSec.ok && collOk;
        handler->PSendModuleSysMessage(MOD, overallOk ? LANG_TRANSMOG_CHECK_RESULT_OK : LANG_TRANSMOG_CHECK_RESULT_FAIL);

        return true;
    }

    static bool HandleReloadTransmogConfig(ChatHandler* handler)
    {
        sTransmogrification->LoadConfig(true);
        handler->SendSysMessage("Transmog configs reloaded.");
        sTransmogrification->LoadCollections();
        handler->SendSysMessage("Transmog collections reloaded.");
        return true;
    }
};

void AddSC_transmog_commandscript()
{
    new transmog_commandscript();
}
