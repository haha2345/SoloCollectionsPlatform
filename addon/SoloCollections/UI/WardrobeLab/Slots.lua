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
}

local UNSUPPORTED_SLOT_POINTS = {
    RANGED = { "BOTTOM", 90, 45, false, "远程" },
    MAINHAND_ENCHANT = { "CENTER", -26, -203, true, "主手附魔" },
    OFFHAND_ENCHANT = { "CENTER", 27, -203, true, "副手附魔" },
}

local SLOT_FALLBACKS = {
    HEAD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
    SHOULDER = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    BACK = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Back",
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
    MAINHAND_ENCHANT = "Interface\\Icons\\Spell_Holy_GreaterHeal",
    OFFHAND_ENCHANT = "Interface\\Icons\\Spell_Holy_GreaterHeal",
}

local function createSmallEnchantChrome(button)
    local transmog = UI.EzCollections:MediaPath("Transmogrify", "Transmogrify.tga", "Interface\\Buttons\\WHITE8X8")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "BORDER")
    border:SetWidth(40)
    border:SetHeight(40)
    border:SetPoint("CENTER")
    border:SetTexture(transmog)
    border:SetTexCoord(0.736328125, 0.814453125, 0.001953125, 0.080078125)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetWidth(38)
    highlight:SetHeight(38)
    highlight:SetPoint("CENTER")
    highlight:SetTexture(transmog)
    highlight:SetTexCoord(0.814453125, 0.888671875, 0.001953125, 0.076171875)
    highlight:SetBlendMode("ADD")
    button.scIcon = icon
    button.scBorder = border
    return icon, border
end

local function createUnsupportedSlot(host, key, point)
    local button = CreateFrame("Button", nil, host)
    local small = point[4]
    button:SetWidth(small and 27 or 43)
    button:SetHeight(small and 27 or 43)
    button:SetPoint(point[1], host, point[1], point[2], point[3])
    button:EnableMouse(true)
    local icon, border
    if small then
        icon, border = createSmallEnchantChrome(button)
    else
        icon, border = UI.EzCollections:CreateTransmogSlotChrome(button)
    end
    icon:SetTexture(SLOT_FALLBACKS[key] or "Interface\\Icons\\INV_Misc_QuestionMark")
    if icon.SetDesaturated then icon:SetDesaturated(true) end
    if border and border.SetAlpha then border:SetAlpha(0.45) end
    button:SetAlpha(0.65)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(point[5] or key, 1, 0.82, 0.18)
        GameTooltip:AddLine("按 ezCollections 布局保留的占位；当前 SoloCollections 数据和 SC2 动作尚未接入此槽位。", 0.72, 0.72, 0.72, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

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
                if state:IsRequestPending() then
                    state:Notify("REQUEST_PENDING_BLOCKED")
                    return
                end
                state:ClearDraft(self.scSlotKey)
            else
                state:SelectSlot(self.scSlotKey)
            end
        end)
        button:SetScript("OnEnter", function(self)
            local itemId, pending, source = state:GetSlotPreviewItemId(self.scSlotKey)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.scDefinition.label, 1, 0.82, 0.18)
            if itemId then
                local name = GetItemInfo and GetItemInfo(itemId)
                GameTooltip:AddLine(name or ("物品 " .. tostring(itemId)), 1, 1, 1)
            else
                GameTooltip:AddLine("当前槽位为空", 0.62, 0.62, 0.62)
            end
            if pending then
                if state:IsRequestPending() then
                    GameTooltip:AddLine("应用请求处理中 · 暂不能撤销", 1, 0.76, 0.32)
                elseif state.presetRecord then
                    GameTooltip:AddLine("套装预设 · 右键移除此槽位并转为本地草稿", 0.82, 0.42, 1)
                else
                    GameTooltip:AddLine("本地草稿 · 右键撤销当前槽位", 0.82, 0.42, 1)
                end
            elseif source == "APPLIED" then
                GameTooltip:AddLine("服务端已确认的已应用外观", 0.45, 0.90, 0.34)
            elseif source == "EQUIPPED" then
                GameTooltip:AddLine("当前装备槽位", 0.72, 0.72, 0.72)
            end
            GameTooltip:AddLine("左键选择并浏览右侧候选", 0.72, 0.72, 0.72)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        host.buttons[definition.key] = button
    end
    host.unsupportedButtons = {}
    for key, point in pairs(UNSUPPORTED_SLOT_POINTS) do
        host.unsupportedButtons[key] = createUnsupportedSlot(host, key, point)
    end
    function host:Refresh()
        for slotKey, button in pairs(self.buttons) do
            local itemId, pending, source = state:GetSlotPreviewItemId(slotKey)
            local texture = itemId and GetItemIcon and GetItemIcon(itemId)
            button.scIcon:SetTexture(texture or SLOT_FALLBACKS[slotKey] or "Interface\\Icons\\INV_Misc_QuestionMark")
            if button.scIcon.SetDesaturated then button.scIcon:SetDesaturated(itemId == nil) end
            button:SetSlotSelected(state.selectedSlot == slotKey)
            button:SetSlotPending(pending)
            if button.SetSlotApplied then button:SetSlotApplied(source == "APPLIED") end
        end
    end
    return host
end
