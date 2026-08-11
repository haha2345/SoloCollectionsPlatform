local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

local SLOT_POINTS = {
    HEAD = { "TOP", -121, -41 },
    SHOULDER = { "TOP", -121, -94 },
    BACK = { "TOP", -121, -147 },
    CHEST = { "TOP", -121, -200 },
    WRIST = { "TOP", -121, -253 },
    HANDS = { "TOP", 123, -118 },
    WAIST = { "TOP", 123, -171 },
    LEGS = { "TOP", 123, -224 },
    FEET = { "TOP", 123, -277 },
    MAINHAND = { "BOTTOM", -26, 45 },
    OFFHAND = { "BOTTOM", 27, 45 },
}

local SLOT_FALLBACKS = {
    HEAD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
    SHOULDER = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    BACK = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    CHEST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    WRIST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
    HANDS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
    WAIST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
    LEGS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
    FEET = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    MAINHAND = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
    OFFHAND = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
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
            else
                state:SelectSlot(self.scSlotKey)
            end
        end)
        button:SetScript("OnEnter", function(self)
            local itemId, pending = state:GetSlotPreviewItemId(self.scSlotKey)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.scDefinition.label, 1, 0.82, 0.18)
            if itemId then
                local name = GetItemInfo and GetItemInfo(itemId)
                GameTooltip:AddLine(name or ("物品 " .. tostring(itemId)), 1, 1, 1)
            else
                GameTooltip:AddLine("当前槽位为空", 0.62, 0.62, 0.62)
            end
            if pending then GameTooltip:AddLine("本地草稿 · 右键撤销", 0.82, 0.42, 1) end
            GameTooltip:AddLine("左键选择并浏览右侧候选", 0.72, 0.72, 0.72)
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
        end
    end
    return host
end
