-- DragonUI_NewEra/compat/C_Container.lua
-- Fills the C_Container.* symbols !!!ClassicAPI does NOT define:
--   GetContainerItemCooldown, GetContainerItemQuestInfo.
--
-- DOWNPORT: Classic 1.15 namespaced the container API under C_Container and changed
-- GetContainerItemInfo to return a TABLE. !!!ClassicAPI is a HARD dependency and loads
-- first, providing the table-returning GetContainerItemInfo plus GetContainerItemID /
-- GetContainerItemLink / GetContainerNumSlots / GetContainerNumFreeSlots /
-- UseContainerItem / PickupContainerItem. It marks GetContainerItemCooldown and
-- GetContainerItemQuestInfo as INCOMPLETE (it exposes GetItemCooldown, not the
-- container variant, and no quest-info accessor), so we fill those two — both of which
-- v1's ItemGrid uses (cooldown swipe + quest-item border).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

C_Container = C_Container or {}
local C = C_Container

-- GetContainerItemCooldown(bag, slot) -> start, duration, enable. ClassicAPI does not
-- define this (it ships GetItemCooldown instead); forward to the 3.3.5a global.
if not C.GetContainerItemCooldown then
    C.GetContainerItemCooldown = GetContainerItemCooldown
end

-- GetContainerItemQuestInfo(bag, slot) -> table  (retail shape). ClassicAPI does not
-- define this. 3.3.5: GetContainerItemQuestInfo returns isQuestItem, questId, isActive
-- (positional). v1 only reads .isQuestItem / .questId, so adapt positional -> table; if
-- the global is absent, return a safe empty table (no quest item) and record the partial.
if not C.GetContainerItemQuestInfo then
    if type(GetContainerItemQuestInfo) == "function" then
        function C.GetContainerItemQuestInfo(bag, slot)
            local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
            return {
                isQuestItem = isQuestItem,
                questID     = questId,
                questId     = questId,        -- tolerate both casings
                isActive    = isActive,
            }
        end
    else
        function C.GetContainerItemQuestInfo(bag, slot)
            return { isQuestItem = nil, questID = nil, questId = nil, isActive = nil }
        end
        NE.compat.RecordStub("C_Container.GetContainerItemQuestInfo",
            "no native GetContainerItemQuestInfo on this client; returns empty (no quest item)")
    end
end

NE.compat.container = true
