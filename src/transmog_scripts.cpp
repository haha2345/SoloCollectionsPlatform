/*
5.0
Transmogrification 3.3.5a - Gossip menu
By Rochet2

ScriptName for NPC:
Creature_Transmogrify

TODO:
Make DB saving even better (Deleting)? What about coding?

Fix the cost formula
-- Too much data handling, use default costs

Are the qualities right?
Blizzard might have changed the quality requirements.
(TC handles it with stat checks)

Cant transmogrify rediculus items // Foereaper: would be fun to stab people with a fish
-- Cant think of any good way to handle this easily, could rip flagged items from cata DB
*/
#include "Transmogrification.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsOutfitService.h"
#include "Chat.h"
#include "ScriptedCreature.h"
#include "ItemTemplate.h"
#include "DatabaseEnv.h"
#include "WorldPacket.h"
#include "Opcodes.h"

#define sT sTransmogrification

static inline const std::string& Tstr(WorldSession* session, uint32 id)
{
    return *session->GetModuleString("mod-transmog", id);
}



const uint32 FALLBACK_HIDE_ITEM_VENDOR_ID   = 9172; //Invisibility potion
const uint32 FALLBACK_REMOVE_TMOG_VENDOR_ID = 1049; //Tablet of Purge
const uint32 CUSTOM_HIDE_ITEM_VENDOR_ID     = 57575;//Custom Hide Item item
const uint32 CUSTOM_REMOVE_TMOG_VENDOR_ID   = 57576;//Custom Remove Transmog item


uint32 GetTransmogPrice (ItemTemplate const* sourceItem)
{
    uint32 price = sT->GetSpecialPrice(sourceItem);
    price *= sT->GetScaledCostModifier();
    price += sT->GetCopperCost();
    return price;
}

std::string GetTransmogPriceText(uint32 price)
{
    if (!price)
        return {};

    uint32 gold = price / 10000;
    uint32 silver = (price % 10000) / 100;
    uint32 copper = price % 100;
    std::ostringstream text;
    text << std::endl << std::endl;
    if (gold)
        text << gold << " |TInterface/MoneyFrame/UI-GoldIcon:14:14:2:0|t ";
    if (silver)
        text << silver << " |TInterface/MoneyFrame/UI-SilverIcon:14:14:2:0|t ";
    if (copper)
        text << copper << " |TInterface/MoneyFrame/UI-CopperIcon:14:14:2:0|t";
    return text.str();
}

bool ValidForTransmog(Player* player, Item* target, ItemTemplate const* sourceTemplate, bool hasSearch, std::string const& searchTerm)
{
    if (!target || !sourceTemplate || !player)
        return false;
    ItemTemplate const* targetTemplate = target->GetTemplate();
    if (!targetTemplate)
        return false;

    if (!sT->CanTransmogrifyItemWithItem(player, targetTemplate, sourceTemplate))
        return false;
    if (sT->GetFakeEntry(target->GetGUID()) == sourceTemplate->ItemId)
        return false;
    if (hasSearch && sourceTemplate->Name1.find(searchTerm) == std::string::npos)
        return false;
    return true;
}

bool CmpTmog(ItemTemplate const* i1, ItemTemplate const* i2)
{
    const int q1 = 7 - i1->Quality;
    const int q2 = 7 - i2->Quality;
    return std::tie(q1, i1->Name1) < std::tie(q2, i2->Name1);
}

std::vector<ItemTemplate const*> GetValidTransmogs(Player* player, Item* target, bool hasSearch, std::string const& searchTerm)
{
    std::vector<ItemTemplate const*> allowedItems;
    if (!target) return allowedItems;

    if (sT->GetUseCollectionSystem())
    {
        uint32 accountId = player->GetSession()->GetAccountId();
        for (uint32 itemId : SoloCollections::GetAppearanceService().CollectedSources(
                SoloCollections::AccountId(accountId)))
        {
            ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(itemId);
            if (!sourceTemplate)
                continue;
            if (ValidForTransmog(player, target, sourceTemplate, hasSearch, searchTerm))
                allowedItems.push_back(sourceTemplate);
        }
    }
    else
    {
        for (uint8 i = INVENTORY_SLOT_ITEM_START; i < INVENTORY_SLOT_ITEM_END; ++i)
        {
            Item* srcItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, i);
            ItemTemplate const* sourceTemplate = srcItem ? srcItem->GetTemplate() : nullptr;
            if (ValidForTransmog(player, target, sourceTemplate, hasSearch, searchTerm))
                allowedItems.push_back(sourceTemplate);
        }
        for (uint8 i = INVENTORY_SLOT_BAG_START; i < INVENTORY_SLOT_BAG_END; ++i)
        {
            Bag* bag = player->GetBagByPos(i);
            if (!bag)
                continue;
            for (uint32 j = 0; j < bag->GetBagSize(); ++j)
            {
                Item* srcItem = player->GetItemByPos(i, j);
                ItemTemplate const* sourceTemplate = srcItem ? srcItem->GetTemplate() : nullptr;
                if (ValidForTransmog(player, target, sourceTemplate, hasSearch, searchTerm))
                    allowedItems.push_back(sourceTemplate);
            }
        }
    }

    if (sConfigMgr->GetOption<bool>("Transmogrification.EnableSortByQualityAndName", true)) {
        sort(allowedItems.begin(), allowedItems.end(), CmpTmog);
    }

    return allowedItems;
}

void PerformTransmogrification(Player* player, Creature* creature, uint32 itemEntry, TransmogApplySource source)
{
    WorldSession* session = player->GetSession();
    auto selection = sT->selectionCache.find(player->GetGUID());
    if (selection == sT->selectionCache.end())
    {
        ChatHandler(session).SendNotification(Tstr(session, LANG_TRANSMOG_INVALID_SLOT));
        return;
    }

    uint8 slot = selection->second;
    ObjectGuid playerGuid = player->GetGUID();
    SoloCollections::GetAppearanceService().TryApplyCollectedAppearance(
        player, itemEntry, slot, creature->GetGUID(), source, false,
        [playerGuid, slot](TransmogApplyResult result)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(playerGuid);
            if (!player || !player->GetSession())
                return;
            WorldSession* session = player->GetSession();
            if (result.IsSuccess())
            {
                session->SendAreaTriggerMessage("{}", Tstr(session, LANG_TRANSMOG_OK));

                if (sT->ShowSetDisclaimer &&
                    !player->GetPlayerSetting("mod-transmog", SETTING_HIDE_SET_DISCLAIMER).value)
                {
                    if (Item* destItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                    {
                        ItemTemplate const* destTemplate = destItem->GetTemplate();
                        if (destTemplate && destTemplate->ItemSet)
                            ChatHandler(session).PSendSysMessage("{}", Tstr(session, LANG_TRANSMOG_SET_DISCLAIMER));
                    }
                }
            }
            else
                ChatHandler(session).SendNotification(Tstr(session, result.Code));
        });
}

void RemoveTransmogrification (Player* player)
{
    WorldSession* session = player->GetSession();
    auto selection = sT->selectionCache.find(player->GetGUID());
    if (selection == sT->selectionCache.end())
    {
        ChatHandler(session).SendNotification(Tstr(session, LANG_TRANSMOG_INVALID_SLOT));
        return;
    }

    uint8 slot = selection->second;
    if (Item* newItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
    {
        if (sT->GetFakeEntry(newItem->GetGUID()))
        {
            sT->DeleteFakeEntry(player, slot, newItem);
            session->SendAreaTriggerMessage("{}", Tstr(session, LANG_TRANSMOG_UNTRANSMOG_OK));
        }
        else
            ChatHandler(session).SendNotification(Tstr(session, LANG_TRANSMOG_UNTRANSMOG_NO_TRANSMOGS));
    }
}

class npc_transmogrifier : public CreatureScript
{
public:
    npc_transmogrifier() : CreatureScript("npc_transmogrifier") { }

    struct npc_transmogrifierAI : ScriptedAI
    {
        npc_transmogrifierAI(Creature* creature) : ScriptedAI(creature) { };

        bool CanBeSeen(Player const* player) override
        {
            Player* target = ObjectAccessor::FindConnectedPlayer(player->GetGUID());

            if (sT->IsPortableNPCEnabled)
            {
                if (TempSummon* summon = me->ToTempSummon())
                {
                    return summon->GetOwner() == player;
                }
            }

            return sTransmogrification->IsEnabled() && (target && !target->GetPlayerSetting("mod-transmog", SETTING_HIDE_TRANSMOG).IsEnabled());
        }
    };

    CreatureAI* GetAI(Creature* creature) const override
    {
        return new npc_transmogrifierAI(creature);
    }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        WorldSession* session = player->GetSession();

        // Clear the search string for the player
        sT->searchStringByPlayer.erase(player->GetGUID().GetCounter());

        if (sT->GetEnableTransmogInfo())
            AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/INV_Misc_Book_11:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_HOWWORKS), EQUIPMENT_SLOT_END + 9, 0);
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            if (const char* slotName = sT->GetSlotName(slot, session))
            {
                Item* newItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
                uint32 entry = newItem ? sT->GetFakeEntry(newItem->GetGUID()) : 0;
                std::string icon = entry ? sT->GetItemIcon(entry, 30, 30, -18, 0) : sT->GetSlotIcon(slot, 30, 30, -18, 0);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, icon + std::string(slotName), EQUIPMENT_SLOT_END, slot);
            }
        }
#ifdef PRESETS
        if (sT->GetEnableSets())
            AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/RAIDFRAME/UI-RAIDFRAME-MAINASSIST:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_MANAGESETS), EQUIPMENT_SLOT_END + 4, 0);
#endif
        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/INV_Enchant_Disenchant:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_REMOVETRANSMOG), EQUIPMENT_SLOT_END + 2, 0, Tstr(session, LANG_TRANSMOG_REMOVETRANSMOG_ASK), 0, false);
        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/PaperDollInfoFrame/UI-GearManager-Undo:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_UPDATEMENU), EQUIPMENT_SLOT_END + 1, 0);
        SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
    {
        player->PlayerTalkClass->ClearMenus();
        WorldSession* session = player->GetSession();
        // Next page
        if (sender > EQUIPMENT_SLOT_END + 10)
        {
            ShowTransmogItemsInGossipMenu(player, creature, action, sender);
            return true;
        }
        switch (sender)
        {
            case EQUIPMENT_SLOT_END: // Show items you can use
            {
                sT->selectionCache[player->GetGUID()] = action;

                bool useVendorInterface = player->GetPlayerSetting("mod-transmog", SETTING_VENDOR_INTERFACE).IsEnabled();

                if (sT->GetUseVendorInterface() || useVendorInterface)
                    ShowTransmogItemsInFakeVendor(player, creature, action);
                else
                    ShowTransmogItemsInGossipMenu(player, creature, action, sender);

                break;
            }
            case EQUIPMENT_SLOT_END + 1: // Main menu
                OnGossipHello(player, creature);
                break;
            case EQUIPMENT_SLOT_END + 2: // Remove Transmogrifications
            {
                bool removed = false;
                auto trans = CharacterDatabase.BeginTransaction();
                for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
                {
                    if (Item* newItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                    {
                        if (!sT->GetFakeEntry(newItem->GetGUID()))
                            continue;
                        sT->DeleteFakeEntry(player, slot, newItem, &trans);
                        removed = true;
                    }
                }
                if (removed)
                {
                    session->SendAreaTriggerMessage("{}", Tstr(session, LANG_TRANSMOG_UNTRANSMOG_OK));
                    CharacterDatabase.CommitTransaction(trans);
                }
                else
                    ChatHandler(session).SendNotification(Tstr(session, LANG_TRANSMOG_UNTRANSMOG_NO_TRANSMOGS));
                OnGossipHello(player, creature);
            } break;
            case EQUIPMENT_SLOT_END + 3: // Remove Transmogrification from single item
            {
                RemoveTransmogrification(player);
                OnGossipSelect(player, creature, EQUIPMENT_SLOT_END, action);
            } break;
    #ifdef PRESETS
            case EQUIPMENT_SLOT_END + 4: // Presets menu
            {
                if (!sT->GetEnableSets())
                {
                    OnGossipHello(player, creature);
                    return true;
                }
                if (sT->GetEnableSetInfo())
                    AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/INV_Misc_Book_11:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_HOWSETSWORK), EQUIPMENT_SLOT_END + 10, 0);
                SoloCollections::OutfitService::OutfitMap const& outfits =
                    SoloCollections::GetOutfitService().List(player->GetGUID());
                for (auto const& [outfitId, outfit] : outfits)
                    AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG,
                        "|TInterface/ICONS/INV_Misc_Statue_02:30:30:-18:0|t" + outfit.Name,
                        EQUIPMENT_SLOT_END + 6, outfitId);

                if (outfits.size() < sT->GetMaxSets())
                    AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/GuildBankFrame/UI-GuildBankFrame-NewTab:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_SAVESET), EQUIPMENT_SLOT_END + 8, 0);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/Ability_Spy:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_BACK), EQUIPMENT_SLOT_END + 1, 0);
                SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
            } break;
            case EQUIPMENT_SLOT_END + 5: // Use preset
            {
                if (!sT->GetEnableSets())
                {
                    OnGossipHello(player, creature);
                    return true;
                }
                {
                    ObjectGuid playerGuid = player->GetGUID();
                    ObjectGuid creatureGuid = creature->GetGUID();
                    SoloCollections::GetOutfitService().Apply(
                        player, static_cast<uint8>(action), creature->GetGUID(),
                        [this, playerGuid, creatureGuid, action](TransmogApplyResult result)
                        {
                            Player* player = ObjectAccessor::FindConnectedPlayer(playerGuid);
                            if (!player || !player->GetSession())
                                return;
                            if (!result.IsSuccess())
                                ChatHandler(player->GetSession()).SendNotification(
                                    Tstr(player->GetSession(), result.Code));
                            if (Creature* creature = ObjectAccessor::GetCreature(*player, creatureGuid))
                                OnGossipSelect(player, creature, EQUIPMENT_SLOT_END + 6, action);
                        });
                }
            } break;
            case EQUIPMENT_SLOT_END + 6: // view preset
            {
                if (!sT->GetEnableSets())
                {
                    OnGossipHello(player, creature);
                    return true;
                }
                SoloCollections::OutfitRecord const* outfit =
                    SoloCollections::GetOutfitService().Find(player->GetGUID(), static_cast<uint8>(action));
                if (!outfit)
                {
                    ChatHandler(session).SendNotification(Tstr(session, LANG_TRANSMOG_INVALID_SRC_ENTRY));
                    OnGossipSelect(player, creature, EQUIPMENT_SLOT_END + 4, 0);
                    return true;
                }
                for (auto const& [slot, entry] : outfit->Appearances)
                {
                    (void)slot;
                    AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG,
                        sT->GetItemIcon(entry, 30, 30, -18, 0) + sT->GetItemLink(entry, session), sender, action);
                }

                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/INV_Misc_Statue_02:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_USESET), EQUIPMENT_SLOT_END + 5, action, Tstr(session, LANG_TRANSMOG_CONFIRM_USESET) + outfit->Name, 0, false);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/PaperDollInfoFrame/UI-GearManager-LeaveItem-Opaque:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_DELETESET), EQUIPMENT_SLOT_END + 7, action, Tstr(session, LANG_TRANSMOG_CONFIRM_DELETESET) + outfit->Name + "?", 0, false);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/Ability_Spy:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_BACK), EQUIPMENT_SLOT_END + 4, 0);
                SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
            } break;
            case EQUIPMENT_SLOT_END + 7: // Delete preset
            {
                if (!sT->GetEnableSets())
                {
                    OnGossipHello(player, creature);
                    return true;
                }
                {
                    ObjectGuid playerGuid = player->GetGUID();
                    ObjectGuid creatureGuid = creature->GetGUID();
                    SoloCollections::GetOutfitService().Delete(
                        player, static_cast<uint8>(action),
                        [this, playerGuid, creatureGuid](TransmogApplyResult result)
                        {
                            Player* player = ObjectAccessor::FindConnectedPlayer(playerGuid);
                            if (!player || !player->GetSession())
                                return;
                            if (!result.IsSuccess())
                                ChatHandler(player->GetSession()).SendNotification(
                                    Tstr(player->GetSession(), result.Code));
                            if (Creature* creature = ObjectAccessor::GetCreature(*player, creatureGuid))
                                OnGossipSelect(player, creature, EQUIPMENT_SLOT_END + 4, 0);
                        });
                }
            } break;
            case EQUIPMENT_SLOT_END + 8: // Save preset
            {
                if (!sT->GetEnableSets() ||
                    SoloCollections::GetOutfitService().List(player->GetGUID()).size() >= sT->GetMaxSets())
                {
                    OnGossipHello(player, creature);
                    return true;
                }
                uint32 cost = 0;
                bool canSave = false;
                for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
                {
                    if (!sT->GetSlotName(slot, session))
                        continue;
                    if (Item* newItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                    {
                        uint32 entry = sT->GetFakeEntry(newItem->GetGUID());
                        if (!entry)
                            continue;
                        const ItemTemplate* temp = sObjectMgr->GetItemTemplate(entry);
                        if (!temp)
                            continue;
                        if (!sT->SuitableForTransmogrification(player, temp)) // no need to check?
                            continue;
                        cost += sT->GetSpecialPrice(temp);
                        canSave = true;
                        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, sT->GetItemIcon(entry, 30, 30, -18, 0) + sT->GetItemLink(entry, session), EQUIPMENT_SLOT_END + 8, 0);
                    }
                }
                if (canSave)
                    AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/GuildBankFrame/UI-GuildBankFrame-NewTab:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_SAVESET), 0, 0, Tstr(session, LANG_TRANSMOG_INSERTSETNAME), cost*sT->GetSetCostModifier() + sT->GetSetCopperCost(), true);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/PaperDollInfoFrame/UI-GearManager-Undo:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_UPDATEMENU), sender, action);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/Ability_Spy:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_BACK), EQUIPMENT_SLOT_END + 4, 0);
                SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
            } break;
            case EQUIPMENT_SLOT_END + 10: // Set info
            {
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/Ability_Spy:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_BACK), EQUIPMENT_SLOT_END + 4, 0);
                SendGossipMenuFor(player, sT->GetSetNpcText(), creature->GetGUID());
            } break;
    #endif
            case EQUIPMENT_SLOT_END + 9: // Transmog info
            {
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/Ability_Spy:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_BACK), EQUIPMENT_SLOT_END + 1, 0);
                SendGossipMenuFor(player, sT->GetTransmogNpcText(), creature->GetGUID());
            } break;
            default: // Transmogrify
            {
                if (!sender && !action)
                {
                    OnGossipHello(player, creature);
                    return true;
                }
                PerformTransmogrification(player, creature, action, TransmogApplySource::Gossip);
                CloseGossipMenuFor(player); // Wait for SetMoney to get fixed, issue #10053
            } break;
        }
        return true;
    }

#ifdef PRESETS
    bool OnGossipSelectCode(Player* player, Creature* creature, uint32 sender, uint32 action, const char* code) override
    {
        player->PlayerTalkClass->ClearMenus();
        if (sender)
        {
            // "sender" is an equipment slot for a search - execute the search
            std::string searchString(code);
            if (searchString.length() > MAX_SEARCH_STRING_LENGTH)
                searchString = searchString.substr(0, MAX_SEARCH_STRING_LENGTH);
            sT->searchStringByPlayer.erase(player->GetGUID().GetCounter());
            sT->searchStringByPlayer.insert({player->GetGUID().GetCounter(), searchString});
            OnGossipSelect(player, creature, EQUIPMENT_SLOT_END, sender - 1);
            return true;
        }
        if (action)
            return true; // should never happen
        if (!sT->GetEnableSets())
        {
            OnGossipHello(player, creature);
            return true;
        }
        {
            ObjectGuid playerGuid = player->GetGUID();
            SoloCollections::GetOutfitService().Save(player, code,
                [playerGuid](TransmogApplyResult result)
                {
                    Player* player = ObjectAccessor::FindConnectedPlayer(playerGuid);
                    if (!player || !player->GetSession())
                        return;
                    if (!result.IsSuccess())
                        ChatHandler(player->GetSession()).SendNotification(
                            Tstr(player->GetSession(), result.Code));
                });
        }
        //OnGossipSelect(player, creature, EQUIPMENT_SLOT_END+4, 0);
        CloseGossipMenuFor(player); // Wait for SetMoney to get fixed, issue #10053
        return true;
    }
#endif

    void ShowTransmogItemsInGossipMenu(Player* player, Creature* creature, uint8 slot, uint16 gossipPageNumber) // Only checks bags while can use an item from anywhere in inventory
    {
        WorldSession* session = player->GetSession();
        Item* oldItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        bool hasSearchString;

        uint16 pageNumber = 0;
        uint32 startValue = 0;
        uint32 endValue = MAX_OPTIONS - 4;
        bool lastPage = true;
        if (gossipPageNumber > EQUIPMENT_SLOT_END + 10)
        {
            pageNumber = gossipPageNumber - EQUIPMENT_SLOT_END - 10;
            startValue = (pageNumber * (MAX_OPTIONS - 2));
            endValue = (pageNumber + 1) * (MAX_OPTIONS - 2) - 1;
        }

        if (oldItem)
        {
            std::ostringstream ss;
            if (sT->GetRequireToken())
                ss << std::endl << std::endl << sT->GetTokenAmount() << " x " << sT->GetItemLink(sT->GetTokenEntry(), session);
            std::string tokenSuffix = ss.str();
            std::string hiddenLineEnd = sT->GetHiddenTransmogIsFree() ? std::string() : GetTransmogPriceText(GetTransmogPrice(oldItem->GetTemplate()));

            std::unordered_map<uint32, std::string>::iterator searchStringIterator = sT->searchStringByPlayer.find(player->GetGUID().GetCounter());
            hasSearchString = !(searchStringIterator == sT->searchStringByPlayer.end());
            std::string searchDisplayValue(hasSearchString ? searchStringIterator->second : Tstr(session, LANG_TRANSMOG_SEARCH));
            std::vector<ItemTemplate const*> allowedItems = GetValidTransmogs(player, oldItem, hasSearchString, searchDisplayValue);

            if (allowedItems.size() > 0)
            {
                lastPage = false;
                // Offset values to add Search gossip item
                if (pageNumber == 0)
                {
                    if (hasSearchString)
                    {
                        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, sT->GetItemIcon(30620, 30, 30, -18, 0) + Tstr(session, LANG_TRANSMOG_SEARCHING_FOR) + searchDisplayValue, slot + 1, 0, Tstr(session, LANG_TRANSMOG_SEARCH_FOR_ITEM), 0, true);
                    }
                    else
                    {
                        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, sT->GetItemIcon(30620, 30, 30, -18, 0) + Tstr(session, LANG_TRANSMOG_SEARCH), slot + 1, 0, Tstr(session, LANG_TRANSMOG_SEARCH_FOR_ITEM), 0, true);
                    }
                }
                else
                {
                    startValue--;
                }
                if (sT->GetAllowHiddenTransmog())
                {
                    // Offset the start and end values to make space for invisible item entry
                    endValue--;
                    if (pageNumber != 0)
                    {
                        startValue--;
                    }
                    else
                    {
                        // Add invisible item entry
                        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/inv_misc_enggizmos_27:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_HIDESLOT), slot, UINT_MAX, Tstr(session, LANG_TRANSMOG_CONFIRM_HIDE_ITEM) + hiddenLineEnd, 0, false);
                    }
                }
                for (uint32 i = startValue; i <= endValue; i++)
                {
                    if (allowedItems.empty() || i > allowedItems.size() - 1)
                    {
                        lastPage = true;
                        break;
                    }
                    ItemTemplate const* sourceTemplate = allowedItems.at(i);
                    std::string lineEnd = GetTransmogPriceText(GetTransmogPrice(sourceTemplate)) + tokenSuffix;
                    // BoxMoney must remain zero: AzerothCore deducts it before the
                    // script callback, which would charge rejected stale/forged
                    // gossip requests. CommitApplyPlan owns all resource changes.
                    AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, sT->GetItemIcon(sourceTemplate->ItemId, 30, 30, -18, 0) + sT->GetItemLink(sourceTemplate->ItemId, session), slot, sourceTemplate->ItemId, Tstr(session, LANG_TRANSMOG_CONFIRM_USEITEM) + sT->GetItemIcon(sourceTemplate->ItemId, 40, 40, -15, -10) + sT->GetItemLink(sourceTemplate->ItemId, session) + lineEnd, 0, false);
                }
            }
            if (gossipPageNumber == EQUIPMENT_SLOT_END + 11)
            {
                AddGossipItemFor(player, GOSSIP_ICON_CHAT, Tstr(session, LANG_TRANSMOG_PREVIOUS_PAGE), EQUIPMENT_SLOT_END, slot);
                if (!lastPage)
                    AddGossipItemFor(player, GOSSIP_ICON_CHAT, Tstr(session, LANG_TRANSMOG_NEXT_PAGE), gossipPageNumber + 1, slot);
            }
            else if (gossipPageNumber > EQUIPMENT_SLOT_END + 11)
            {
                AddGossipItemFor(player, GOSSIP_ICON_CHAT, Tstr(session, LANG_TRANSMOG_PREVIOUS_PAGE), gossipPageNumber - 1, slot);
                if (!lastPage)
                    AddGossipItemFor(player, GOSSIP_ICON_CHAT, Tstr(session, LANG_TRANSMOG_NEXT_PAGE), gossipPageNumber + 1, slot);
            }
            else if (!lastPage)
            {
                AddGossipItemFor(player, GOSSIP_ICON_CHAT, Tstr(session, LANG_TRANSMOG_NEXT_PAGE), EQUIPMENT_SLOT_END + 11, slot);
            }

            AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/INV_Enchant_Disenchant:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_REMOVETRANSMOG), EQUIPMENT_SLOT_END + 3, slot, Tstr(session, LANG_TRANSMOG_REMOVETRANSMOG_SLOT), 0, false);
            AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/PaperDollInfoFrame/UI-GearManager-Undo:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_UPDATEMENU), EQUIPMENT_SLOT_END, slot);
        }
        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "|TInterface/ICONS/Ability_Spy:30:30:-18:0|t" + Tstr(session, LANG_TRANSMOG_BACK), EQUIPMENT_SLOT_END + 1, 0);
        SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
    }

    static std::vector<ItemTemplate const*> GetSpoofedVendorItems (Item* target)
    {
        std::vector<ItemTemplate const*> spoofedItems;
        uint32 existingTransmog = sT->GetFakeEntry(target->GetGUID());
        if (sT->AllowHiddenTransmog && !existingTransmog)
        {
            ItemTemplate const* _hideSlotButton = sObjectMgr->GetItemTemplate(CUSTOM_HIDE_ITEM_VENDOR_ID);
            if (!_hideSlotButton)
                _hideSlotButton = sObjectMgr->GetItemTemplate(FALLBACK_HIDE_ITEM_VENDOR_ID);

            if (_hideSlotButton)
                spoofedItems.push_back(_hideSlotButton);
            else
                LOG_WARN("module", "Transmogrification::GetSpoofedVendorItems - Hide-item templates {} and {} are both missing.", CUSTOM_HIDE_ITEM_VENDOR_ID, FALLBACK_HIDE_ITEM_VENDOR_ID);
        }
        if (existingTransmog)
        {
            ItemTemplate const* _removeTransmogButton = sObjectMgr->GetItemTemplate(CUSTOM_REMOVE_TMOG_VENDOR_ID);
            if (!_removeTransmogButton)
                _removeTransmogButton = sObjectMgr->GetItemTemplate(FALLBACK_REMOVE_TMOG_VENDOR_ID);

            if (_removeTransmogButton)
                spoofedItems.push_back(_removeTransmogButton);
            else
                LOG_WARN("module", "Transmogrification::GetSpoofedVendorItems - Remove-item templates {} and {} are both missing.", CUSTOM_REMOVE_TMOG_VENDOR_ID, FALLBACK_REMOVE_TMOG_VENDOR_ID);
        }
        return spoofedItems;
    }

    static uint32 GetSpoofedItemPrice (uint32 itemId, ItemTemplate const* target)
    {
        switch (itemId)
        {
            case CUSTOM_HIDE_ITEM_VENDOR_ID:
            case FALLBACK_HIDE_ITEM_VENDOR_ID:
                return sT->HiddenTransmogIsFree ? 0 : sT->GetSpecialPrice(target);
            default:
                return 0;
        }
    }

    static void EncodeItemToPacket (WorldPacket& data, ItemTemplate const* proto, uint8& slot, uint32 price)
    {
        if (!proto)
            return;

        data << uint32(slot + 1);
        data << uint32(proto->ItemId);
        data << uint32(proto->DisplayInfoID);
        data << int32 (-1); //Infinite Stock
        data << uint32(price);
        data << uint32(proto->MaxDurability);
        data << uint32(1);  //Buy Count of 1
        data << uint32(0);
        slot++;
    }

    //The actual vendor options are handled in the player script below, OnBeforeBuyItemFromVendor
    static void ShowTransmogItemsInFakeVendor (Player* player, Creature* creature, uint8 slot)
    {
        Item* targetItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        if (!targetItem)
        {
            ChatHandler(player->GetSession()).SendNotification(Tstr(player->GetSession(), LANG_TRANSMOG_MISSING_DEST_ITEM));
            CloseGossipMenuFor(player);
            return;
        }
        ItemTemplate const* targetTemplate = targetItem->GetTemplate();

        std::vector<ItemTemplate const*> itemList = GetValidTransmogs(player, targetItem, false, "");
        std::vector<ItemTemplate const*> spoofedItems = GetSpoofedVendorItems(targetItem);

        uint32 itemCount = itemList.size();
        uint32 spoofCount = spoofedItems.size();
        uint32 totalItems = itemCount + spoofCount;

        WorldPacket data(SMSG_LIST_INVENTORY, 8 + 1 + totalItems * 8 * 4);
        data << uint64(creature->GetGUID().GetRawValue());

        uint8 count = 0;
        size_t count_pos = data.wpos();
        data << uint8(count);

        for (uint32 i = 0; i < spoofCount && count < MAX_VENDOR_ITEMS; ++i)
        {
            EncodeItemToPacket (
                data, spoofedItems[i], count,
                GetSpoofedItemPrice(spoofedItems[i]->ItemId, targetTemplate)
            );
        }
        for (uint32 i = 0; i < itemCount && count < MAX_VENDOR_ITEMS; ++i)
        {
            ItemTemplate const* sourceTemplate = itemList[i];
            if (sourceTemplate)
                EncodeItemToPacket(data, sourceTemplate, count, GetTransmogPrice(sourceTemplate));
        }

        data.put(count_pos, count);
        player->GetSession()->SendPacket(&data);
    }
};

class PS_Transmogrification : public PlayerScript
{
public:
    PS_Transmogrification() : PlayerScript("Player_Transmogrify", {
        PLAYERHOOK_ON_AFTER_SET_VISIBLE_ITEM_SLOT,
        PLAYERHOOK_ON_AFTER_MOVE_ITEM_FROM_INVENTORY,
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_BEFORE_BUY_ITEM_FROM_VENDOR
    }) { }

    void OnPlayerAfterSetVisibleItemSlot(Player* player, uint8 slot, Item *item) override
    {
        if (!item)
            return;

        if (uint32 entry = sT->GetFakeEntry(item->GetGUID()))
        {
            // item_template has no entry 1. Writing HIDDEN_ITEM_ID leaves the
            // real item on the player model; hide must use visible item 0.
            player->SetUInt32Value(PLAYER_VISIBLE_ITEM_1_ENTRYID + (slot * 2),
                entry == HIDDEN_ITEM_ID ? 0 : entry);
        }
    }

    void OnPlayerAfterMoveItemFromInventory(Player* /*player*/, Item* it, uint8 /*bag*/, uint8 /*slot*/, bool /*update*/) override
    {
        if (it)
            sT->DeleteFakeFromDB(it->GetGUID().GetCounter());
    }

    void OnPlayerLogin(Player* player) override
    {
        ObjectGuid playerGUID = player->GetGUID();
        sT->entryMap.erase(playerGUID);
        QueryResult result = CharacterDatabase.Query("SELECT GUID, FakeEntry FROM custom_transmogrification WHERE Owner = {}", player->GetGUID().GetCounter());
        if (result)
        {
            do
            {
                ObjectGuid itemGUID = ObjectGuid::Create<HighGuid::Item>((*result)[0].Get<uint32>());
                uint32 fakeEntry = (*result)[1].Get<uint32>();
                if (fakeEntry == HIDDEN_ITEM_ID || sObjectMgr->GetItemTemplate(fakeEntry))
                {
                    sT->dataMap[itemGUID] = playerGUID;
                    sT->entryMap[playerGUID][itemGUID] = fakeEntry;
                }
            } while (result->NextRow());

            for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            {
                if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                    player->SetVisibleItemSlot(slot, item);
            }
        }

#ifdef PRESETS
        if (sT->GetEnableSets())
            sT->LoadPlayerSets(playerGUID);
#endif
    }

    void OnPlayerLogout(Player* player) override
    {
        ObjectGuid pGUID = player->GetGUID();
        for (Transmogrification::transmog2Data::const_iterator it = sT->entryMap[pGUID].begin(); it != sT->entryMap[pGUID].end(); ++it)
            sT->dataMap.erase(it->first);
        sT->entryMap.erase(pGUID);
        sT->selectionCache.erase(pGUID);

#ifdef PRESETS
        if (sT->GetEnableSets())
            sT->UnloadPlayerSets(pGUID);
#endif
    }

    void OnPlayerBeforeBuyItemFromVendor(Player* player, ObjectGuid vendorguid, uint32 /*vendorslot*/, uint32& itemEntry, uint8 /*count*/, uint8 /*bag*/, uint8 /*slot*/) override
    {
        Creature* vendor = player->GetMap()->GetCreature(vendorguid);
        if (!vendor)
            return;

        if (!sT->IsTransmogVendor(vendor->GetEntry()))
            return;

        auto selection = sT->selectionCache.find(player->GetGUID());
        if (selection == sT->selectionCache.end())
        {
            itemEntry = 0;
            return;
        }

        uint8 slot = selection->second;

        if (itemEntry == CUSTOM_HIDE_ITEM_VENDOR_ID || itemEntry == FALLBACK_HIDE_ITEM_VENDOR_ID)
        {
            PerformTransmogrification(player, vendor, UINT_MAX, TransmogApplySource::Vendor);
        }
        else if (itemEntry == CUSTOM_REMOVE_TMOG_VENDOR_ID || itemEntry == FALLBACK_REMOVE_TMOG_VENDOR_ID)
        {
            RemoveTransmogrification(player);
        }
        else
        {
            PerformTransmogrification(player, vendor, itemEntry, TransmogApplySource::Vendor);
        }
        npc_transmogrifier::ShowTransmogItemsInFakeVendor(player, vendor, slot); //Refresh menu
        itemEntry = 0; //Prevents the handler from proceeding to core vendor handling
    }
};

class WS_Transmogrification : public WorldScript
{
public:
    WS_Transmogrification() : WorldScript("WS_Transmogrification", {
        WORLDHOOK_ON_STARTUP,
        WORLDHOOK_ON_UPDATE
    }) { }

    void OnUpdate(uint32 /*diff*/) override
    {
        // Resolves finished async transmog DB commits (money, cache updates,
        // completion callbacks) on the world thread.
        sTransmogrification->ProcessPendingCommits();
    }

    void OnStartup() override
    {
        sT->LoadConfig(false);
        //sLog->outInfo(LOG_FILTER_SERVER_LOADING, "Deleting non-existing transmogrification entries...");
        CharacterDatabase.Execute("DELETE FROM custom_transmogrification WHERE NOT EXISTS (SELECT 1 FROM item_instance WHERE item_instance.guid = custom_transmogrification.GUID)");

#ifdef PRESETS
        // Clean even if disabled
        // Dont delete even if player has more presets than should
        CharacterDatabase.Execute("DELETE FROM `custom_transmogrification_sets` WHERE NOT EXISTS(SELECT 1 FROM characters WHERE characters.guid = custom_transmogrification_sets.Owner)");
#endif

        (void)SoloCollections::GetAppearanceService().LoadLegacyCollections();
    }
};

class global_transmog_script : public GlobalScript
{
public:
    global_transmog_script() : GlobalScript("global_transmog_script", {
        GLOBALHOOK_ON_ITEM_DEL_FROM_DB,
        GLOBALHOOK_ON_MIRRORIMAGE_DISPLAY_ITEM
    }) { }

    void OnItemDelFromDB(CharacterDatabaseTransaction trans, ObjectGuid::LowType itemGuid) override
    {
        sT->DeleteFakeFromDB(itemGuid, &trans);
    }

    void OnMirrorImageDisplayItem(const Item *item, uint32 &display) override
    {
        if (!item)
            return;

        if (uint32 entry = sTransmogrification->GetFakeEntry(item->GetGUID()))
        {
            if (entry == HIDDEN_ITEM_ID)
            {
                display = 0;
            }
            else
            {
                if (ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(entry))
                    display = sourceTemplate->DisplayInfoID;
                else
                    LOG_WARN("module", "Transmogrification::OnMirrorImageDisplayItem - Fake entry {} has no item template.", entry);
            }
        }
    }
};

class unit_transmog_script : public UnitScript
{
public:
    unit_transmog_script() : UnitScript("unit_transmog_script", true, {
        UNITHOOK_SHOULD_TRACK_VALUES_UPDATE_POS_BY_INDEX,
        UNITHOOK_ON_PATCH_VALUES_UPDATE
    }) { }

    bool ShouldTrackValuesUpdatePosByIndex(Unit const* unit, uint8 /*updateType*/, uint16 index) override
    {
        return unit->IsPlayer() && index >= PLAYER_VISIBLE_ITEM_1_ENTRYID && index <= PLAYER_VISIBLE_ITEM_19_ENTRYID && (index & 1);
    }

    void OnPatchValuesUpdate(Unit const* unit, ByteBuffer& valuesUpdateBuf, BuildValuesCachePosPointers& posPointers, Player* target) override
    {
        if (!unit->IsPlayer())
            return;

        for (auto it = posPointers.other.begin(); it != posPointers.other.end(); ++it)
        {
            uint16 index = it->first;
            if (index >= PLAYER_VISIBLE_ITEM_1_ENTRYID && index <= PLAYER_VISIBLE_ITEM_19_ENTRYID && (index & 1))
                if (Item* item = unit->ToPlayer()->GetItemByPos(INVENTORY_SLOT_BAG_0, ((index - PLAYER_VISIBLE_ITEM_1_ENTRYID) / 2U)))
                    if (!sTransmogrification->IsEnabled() || target->GetPlayerSetting("mod-transmog", SETTING_HIDE_TRANSMOG).value)
                        valuesUpdateBuf.put(it->second, item->GetEntry());
        }
    }
};

void AddSC_Transmog()
{
    new global_transmog_script();
    new unit_transmog_script();
    new npc_transmogrifier();
    new PS_Transmogrification();
    new WS_Transmogrification();
}
