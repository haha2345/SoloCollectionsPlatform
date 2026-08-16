local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local SLOT_POINTS = {
    HEAD = { "TOP", -121, -41 },
    SHOULDER = { "TOP", -121, -94 },
    BACK = { "TOP", -121, -147 },
    CHEST = { "TOP", -121, -200 },
    SHIRT = { "TOP", -121, -253 },
    TABARD = { "TOP", -121, -306 },
    WRIST = { "TOP", -121, -359 },
    HANDS = { "TOP", 123, -118 },
    WAIST = { "TOP", 123, -171 },
    LEGS = { "TOP", 123, -224 },
    FEET = { "TOP", 123, -277 },
    MAINHAND = { "BOTTOM", -26, 45 },
    OFFHAND = { "BOTTOM", 27, 45 },
    RANGED = { "BOTTOM", 90, 45 },
}

local SLOT_FALLBACKS = {
    HEAD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
    SHOULDER = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    BACK = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    CHEST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    SHIRT = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shirt",
    TABARD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Tabard",
    WRIST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
    HANDS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
    WAIST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
    LEGS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
    FEET = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    MAINHAND = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
    OFFHAND = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
    RANGED = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ranged",
}

function Lab.CreateSlots(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host:SetFrameLevel(parent:GetFrameLevel() + 4)
    host.buttons = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local button = CreateFrame("Button", nil, host)
        button:SetWidth(43)
        button:SetHeight(43)
        local point = SLOT_POINTS[definition.key]
        button:SetPoint(point[1], host, point[1], point[2], point[3])
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        UI.EzCollections:CreateTransmogSlotChrome(button)
        button.scSlotKey = definition.key
        button.scDefinition = definition
        button:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" and state:IsSlotDirty(self.scSlotKey) then
                if state.presetRecord then state:ClearDraft() else state:ClearDraft(self.scSlotKey) end
                if Lab.PlaySound then Lab.PlaySound("revert") end
            elseif mouseButton == "RightButton" and state.CanClearAppliedSlot
                and state:CanClearAppliedSlot(self.scSlotKey) then
                if Lab.ConfirmRestoreOriginal then
                    Lab.ConfirmRestoreOriginal(state, self.scSlotKey)
                else
                    state:ClearApplied(self.scSlotKey)
                    if Lab.PlaySound then Lab.PlaySound("revert") end
                end
            else
                state:SelectSlot(self.scSlotKey)
                if Lab.PlaySound then Lab.PlaySound("slot") end
            end
        end)
        button:SetScript("OnEnter", function(self)
            local hidden = state.IsSlotHidden and state:IsSlotHidden(self.scSlotKey)
            local itemId, pending = state:GetSlotPreviewItemId(self.scSlotKey)
            local invSlot = self.scDefinition.inventorySlot + 1
            local equippedId = state.equippedBySlot and state.equippedBySlot[self.scSlotKey]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local name, r, g, b, occupied
            if Lab.EquippedItemTitle then
                name, r, g, b, occupied = Lab.EquippedItemTitle(invSlot, equippedId)
            end
            if name then
                GameTooltip:SetText(name, r or 1, g or 0.82, b or 0.18)
            else
                GameTooltip:SetText(self.scDefinition.label, 1, 0.82, 0.18)
                if not hidden and not occupied then
                    GameTooltip:AddLine("该装备栏里没有装备物品。", 1, 0.12, 0.12, true)
                end
            end
            if hidden then
                Lab.AppendTransmogLines(GameTooltip, "隐藏", pending, true)
            elseif pending then
                if itemId then
                    local record = Lab.FindAppearanceRecord and Lab.FindAppearanceRecord(nil, itemId)
                    local appearanceName = (record and record.name)
                        or (GetItemInfo and GetItemInfo(itemId))
                        or ("物品 " .. tostring(itemId))
                    Lab.AppendTransmogLines(GameTooltip, appearanceName, true, false)
                end
            elseif (name or occupied) and Lab.AddInventoryTransmogTooltip then
                Lab.AddInventoryTransmogTooltip(GameTooltip, invSlot)
            end
            if pending then
                GameTooltip:AddLine("右键撤销", 1, 0.5, 1)
            elseif state.CanClearAppliedSlot and state:CanClearAppliedSlot(self.scSlotKey) then
                GameTooltip:AddLine("右键恢复原样（需确认）", 1, 0.5, 1)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        host.buttons[definition.key] = button
    end
    function host:Refresh()
        for slotKey, button in pairs(self.buttons) do
            local itemId = state:GetSlotPreviewItemId(slotKey)
            local texture = itemId and GetItemIcon and GetItemIcon(itemId)
            button.scIcon:SetTexture(texture or SLOT_FALLBACKS[slotKey] or "Interface\\Icons\\INV_Misc_QuestionMark")
            if button.scIcon.SetDesaturated then button.scIcon:SetDesaturated(itemId == nil) end
            button:SetSlotSelected(state.selectedSlot == slotKey)
            button:SetSlotPending(state:IsSlotDirty(slotKey))
            if button.SetSlotHidden then
                button:SetSlotHidden(state.IsSlotHidden and state:IsSlotHidden(slotKey))
            end
        end
    end

    local function createEnchantButton(x)
        local button = CreateFrame("Button", nil, host)
        button:SetWidth(27)
        button:SetHeight(27)
        button:SetPoint("CENTER", host, "CENTER", x, -203)
        button:SetFrameLevel(host:GetFrameLevel() + 6)
        button:Disable()
        button:EnableMouse(true)
        if UI.EzCollections and UI.EzCollections.CreateTransmogEnchantChrome then
            UI.EzCollections:CreateTransmogEnchantChrome(button)
        end
        local tip = CreateFrame("Frame", nil, button)
        tip:SetAllPoints(button)
        tip:SetFrameLevel(button:GetFrameLevel() + 1)
        tip:EnableMouse(true)
        tip:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("武器附魔", 1, 0.82, 0.18)
            GameTooltip:AddLine("附魔幻化尚未接入服务端，当前不能预览或应用。", 0.72, 0.72, 0.72, true)
            GameTooltip:Show()
        end)
        tip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return button
    end
    host.scMainHandEnchant = createEnchantButton(-26)
    host.scOffHandEnchant = createEnchantButton(27)
    return host
end
