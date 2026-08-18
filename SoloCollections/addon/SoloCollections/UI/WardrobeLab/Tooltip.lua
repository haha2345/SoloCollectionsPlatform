local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

-- Equipped-item tooltips follow Legion / ez: keep the real item name
-- (quality color) and append "幻化为:" plus the appearance in
-- TRANSMOGRIFY pink (1, 0.5, 1). Bind the type 18 slot map to the item
-- that was equipped when the snapshot arrived so a later swap does not
-- inherit the previous item's appearance line.

local trustedItemBySlot = {}
local ignoredSlots = {}

local function equippedItemId(definition)
    if not definition then return nil end
    local invSlot = definition.inventorySlot + 1
    local itemId = Lab.PositiveItemId and Lab.PositiveItemId(GetInventoryItemID and GetInventoryItemID("player", invSlot))
    if itemId then return itemId end
    local link = Lab.InventoryItemLink and Lab.InventoryItemLink(invSlot)
    return link and (Lab.PositiveItemId and Lab.PositiveItemId(string.match(link, "item:(%d+)"))) or nil
end

local function inventoryLink(inventorySlotId)
    if Lab.InventoryItemLink then
        return Lab.InventoryItemLink(inventorySlotId)
    end
    if not GetInventoryItemLink then return nil end
    local link = GetInventoryItemLink("player", inventorySlotId)
    if type(link) ~= "string" or link == "" then return nil end
    return link
end

local function inventoryItemId(inventorySlotId, knownItemId)
    if Lab.PositiveItemId then
        knownItemId = Lab.PositiveItemId(knownItemId)
        if knownItemId then return knownItemId end
        local itemId = Lab.PositiveItemId(GetInventoryItemID and GetInventoryItemID("player", inventorySlotId))
        if itemId then return itemId end
        local link = inventoryLink(inventorySlotId)
        return link and Lab.PositiveItemId(string.match(link, "item:(%d+)")) or nil
    end
    knownItemId = tonumber(knownItemId)
    if knownItemId and knownItemId > 0 then return knownItemId end
    local itemId = GetInventoryItemID and GetInventoryItemID("player", inventorySlotId)
    itemId = tonumber(itemId)
    if itemId and itemId > 0 then return itemId end
    local link = inventoryLink(inventorySlotId)
    return link and tonumber(string.match(link, "item:(%d+)")) or nil
end

local function inventoryOccupied(inventorySlotId, itemId)
    if Lab.IsInventoryOccupied then
        return Lab.IsInventoryOccupied(inventorySlotId, itemId)
    end
    if tonumber(itemId) then return true end
    if inventoryLink(inventorySlotId) then return true end
    if GetInventoryItemTexture and GetInventoryItemTexture("player", inventorySlotId) then
        return true
    end
    if GetInventoryItemCount and (GetInventoryItemCount("player", inventorySlotId) or 0) > 0 then
        return true
    end
    return false
end

local function nameFromLink(link)
    if type(link) ~= "string" or link == "" then return nil end
    local name = string.match(link, "|h%[(.-)%]|h") or string.match(link, "%[([^%]]+)%]")
    if name and name ~= "" then return name end
    return nil
end

local function colorFromLink(link)
    if type(link) ~= "string" then return nil end
    local hex = string.match(link, "^|c(%x%x%x%x%x%x%x%x)")
    if not hex then return nil end
    local rr = tonumber(string.sub(hex, 3, 4), 16)
    local gg = tonumber(string.sub(hex, 5, 6), 16)
    local bb = tonumber(string.sub(hex, 7, 8), 16)
    if not (rr and gg and bb) then return nil end
    return rr / 255, gg / 255, bb / 255
end

-- Compact slot title: quality-colored equipped name. Do not call
-- SetInventoryItem here; that dumps armor/stats the wardrobe tooltip must omit.
-- Fifth return is occupancy: a missing/uncached link is not an empty slot.
function Lab.EquippedItemTitle(inventorySlotId, knownItemId)
    inventorySlotId = tonumber(inventorySlotId)
    if not inventorySlotId then return nil, 1, 0.82, 0.18, false end
    local link = inventoryLink(inventorySlotId)
    local itemId = inventoryItemId(inventorySlotId, knownItemId)
    local occupied = inventoryOccupied(inventorySlotId, itemId)
    local name = nameFromLink(link)
    local r, g, b = colorFromLink(link)
    if not r then
        r, g, b = 1, 0.82, 0.18
    end
    if (not name or name == "") and itemId then
        if Lab.ItemQualityColor then
            local qr, qg, qb, qname = Lab.ItemQualityColor(itemId)
            if qname and qname ~= "" then
                name, r, g, b = qname, qr, qg, qb
            end
        elseif GetItemInfo then
            local infoName, _, quality = GetItemInfo(itemId)
            if infoName and infoName ~= "" then
                name = infoName
                if GetItemQualityColor and quality then
                    r, g, b = GetItemQualityColor(quality)
                end
            end
        end
        if not name or name == "" then
            name = "物品 " .. tostring(itemId)
        end
    end
    if name == "" then name = nil end
    return name, r, g, b, occupied
end

local function syncEquippedTrust()
    for _, definition in ipairs(Lab.SLOTS) do
        local itemId = equippedItemId(definition)
        if trustedItemBySlot[definition.key] == nil then
            trustedItemBySlot[definition.key] = itemId
        elseif trustedItemBySlot[definition.key] ~= itemId then
            ignoredSlots[definition.key] = true
        end
    end
end

local function appliedCollectionId(slotKey)
    if ignoredSlots[slotKey] then return nil end
    if not (SC.CollectionState and SC.CollectionState.IsAppliedReady and SC.CollectionState.IsAppliedReady()) then
        return nil
    end
    local applied = SC.CollectionState.GetAppliedSlots and SC.CollectionState.GetAppliedSlots()
    if type(applied) ~= "table" then return nil end
    return tonumber(applied[slotKey])
end

local function appearanceSourceItemId(record)
    if type(record) ~= "table" then return nil end
    return tonumber(record.itemId or (record.itemIds and record.itemIds[1]))
end

local function appearanceMatchesItem(record, itemId)
    if not record or not itemId then return false end
    if tonumber(record.itemId) == itemId then return true end
    for _, sourceItemId in ipairs(record.itemIds or {}) do
        if tonumber(sourceItemId) == itemId then return true end
    end
    return false
end

function Lab.AddInventoryTransmogTooltip(tooltip, inventorySlotId)
    inventorySlotId = tonumber(inventorySlotId)
    if not tooltip or not inventorySlotId then return end
    syncEquippedTrust()
    local equipmentSlot = inventorySlotId - 1
    local definition
    for _, candidate in ipairs(Lab.SLOTS) do
        if candidate.inventorySlot == equipmentSlot then
            definition = candidate
            break
        end
    end
    if not definition then return end
    local collectionId = appliedCollectionId(definition.key)
    if not collectionId or collectionId <= 0 then return end
    local itemId = equippedItemId(definition)
    if not itemId or trustedItemBySlot[definition.key] ~= itemId then return end
    local name, hidden = Lab.AppearanceDisplayName(collectionId, appearanceSourceItemId(Lab.FindAppearanceRecord(collectionId)))
    if not name then return end
    if not hidden then
        local record = Lab.FindAppearanceRecord(collectionId)
        if appearanceMatchesItem(record, itemId) then return end
    end
    Lab.AppendTransmogLines(tooltip, name, false, hidden)
    if tooltip.Show then tooltip:Show() end
end

local function hookTooltip(tooltip)
    if not tooltip or tooltip.scTransmogHooked or type(tooltip.SetInventoryItem) ~= "function" then
        return
    end
    tooltip.scTransmogHooked = true
    hooksecurefunc(tooltip, "SetInventoryItem", function(self, unit, slot)
        if unit ~= "player" then return end
        Lab.AddInventoryTransmogTooltip(self, slot)
    end)
end

hookTooltip(GameTooltip)
hookTooltip(ItemRefTooltip)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:SetScript("OnEvent", function()
    syncEquippedTrust()
end)

if SC.Bridge and SC.Bridge.RegisterStateListener then
    SC.Bridge.RegisterStateListener(function(_, typeId)
        if tonumber(typeId) ~= 18 then return end
        for _, definition in ipairs(Lab.SLOTS) do
            local itemId = equippedItemId(definition)
            if trustedItemBySlot[definition.key] == nil then
                trustedItemBySlot[definition.key] = itemId
            elseif trustedItemBySlot[definition.key] == itemId then
                ignoredSlots[definition.key] = nil
            end
        end
    end)
end
