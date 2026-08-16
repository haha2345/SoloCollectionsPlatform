local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local RACE_BACKGROUND = {
    Human = "Human",
    Dwarf = "Dwarf",
    NightElf = "NightElf",
    Gnome = "Gnome",
    Draenei = "Draenei",
    Orc = "Orc",
    Scourge = "Undead",
    Tauren = "Tauren",
    Troll = "Troll",
    BloodElf = "BloodElf",
}

local function applyRaceBackground(panel, background)
    if not background then return end
    local _, raceFile = UnitRace("player")
    local suffix = RACE_BACKGROUND[raceFile] or "Human"
    local path = UI.EzCollections:MediaPath(
        "Transmogrify",
        "TransmogBackground" .. suffix .. ".tga"
    )
    if not path then return end
    background:ClearAllPoints()
    background:SetWidth(294)
    background:SetHeight(494)
    background:SetPoint("TOP", panel, "TOP", 0, -1)
    background:SetTexture(path)
    -- Files are 512×512; art lives in the top-left 294×494 (ez Inset.BG).
    background:SetTexCoord(0, 294 / 512, 0, 494 / 512)
    background:SetHorizTile(false)
    background:SetVertTile(false)
    background.scEzCollectionsTiled = false
    if UI.EzCollections.UpdateInset then UI.EzCollections:UpdateInset(panel) end
end

local function createDisabledTooltipOverlay(button, onEnter)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 1)
    overlay:EnableMouse(true)
    overlay:SetScript("OnEnter", onEnter)
    overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
    overlay:Hide()
    return overlay
end

function Lab.CreateLayout(page, state)
    local left = CreateFrame("Frame", nil, page)
    left:SetWidth(300)
    left:SetHeight(495)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -86)
    local leftInset = UI.EzCollections:ApplyInset(left)
    applyRaceBackground(left, leftInset.background)

    -- ez 2.2 SetContainer(WardrobeFrame): 662×606 TOPRIGHT (0, 0).
    -- Header controls (tabs / progress / search) live in this frame; the
    -- marble inset and item grid start at y=-60 so they stay below them.
    local right = CreateFrame("Frame", nil, page)
    right:SetWidth(662)
    right:SetHeight(606)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

    local preview = Lab.CreatePreview(left, state)
    local slots = Lab.CreateSlots(preview, state)
    local outfits = Lab.CreateOutfits(left, state)
    local sources = Lab.CreateSources(right, state)

    local stateText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stateText:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    stateText:SetWidth(1)
    stateText:SetJustifyH("LEFT")
    stateText:SetTextColor(1, 0.72, 0.24)
    stateText:Hide()

    local moneyPath = UI.EzCollections:MediaPath(
        "Common",
        "MoneyFrame.tga",
        "Interface\\Tooltips\\UI-Tooltip-Background"
    )
    local moneyLeft = left:CreateTexture(nil, "ARTWORK")
    moneyLeft:SetWidth(8)
    moneyLeft:SetHeight(20)
    moneyLeft:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", -3, -22)
    moneyLeft:SetTexture(moneyPath)
    moneyLeft:SetTexCoord(0.9375, 1, 0, 0.3125)
    local moneyMiddle = left:CreateTexture(nil, "ARTWORK")
    moneyMiddle:SetWidth(154)
    moneyMiddle:SetHeight(20)
    moneyMiddle:SetPoint("LEFT", moneyLeft, "RIGHT", 0, 0)
    moneyMiddle:SetTexture(moneyPath)
    moneyMiddle:SetTexCoord(0, 1, 0.3125, 0.6250)
    local moneyRight = left:CreateTexture(nil, "ARTWORK")
    moneyRight:SetWidth(8)
    moneyRight:SetHeight(20)
    moneyRight:SetPoint("LEFT", moneyMiddle, "RIGHT", 0, 0)
    moneyRight:SetTexture(moneyPath)
    moneyRight:SetTexCoord(0, 0.0625, 0, 0.3125)

    local moneyText = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moneyText:SetPoint("RIGHT", moneyRight, "RIGHT", 2, 0)
    moneyText:SetText("0")
    moneyText:SetTextColor(1, 0.82, 0.18)

    local apply = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    apply:SetWidth(112)
    apply:SetHeight(22)
    apply:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, -22)
    apply:SetText("应用")
    apply:SetFrameLevel(left:GetFrameLevel() + 16)
    apply:SetScript("OnClick", function()
        local sound = UI.EzCollections:MediaPath("Sounds", "UI_Transmogrify_Apply.wav")
        if sound and PlaySoundFile then PlaySoundFile(sound) end
        state:BeginApplyAll()
    end)

    local spec = CreateFrame("Button", nil, left, "UIMenuButtonStretchTemplate")
    spec:SetWidth(22)
    spec:SetHeight(22)
    spec:SetPoint("RIGHT", apply, "LEFT", 1, 0)
    spec:SetFrameLevel(left:GetFrameLevel() + 16)
    spec:Disable()
    local specIcon = spec:CreateTexture(nil, "ARTWORK")
    specIcon:SetWidth(12)
    specIcon:SetHeight(12)
    specIcon:SetPoint("CENTER", spec, "CENTER", 0, 0)
    specIcon:SetTexture(UI.EzCollections:MediaPath(
        "Buttons",
        "SquareButtonTextures.tga",
        "Interface\\Buttons\\UI-OptionsButton"
    ))
    specIcon:SetTexCoord(0.453125, 0.640625, 0.203125, 0.015625)
    if spec.SetHighlightTexture then spec:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD") end
    local specTip = createDisabledTooltipOverlay(spec, function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("专精应用", 1, 0.82, 0.18)
        GameTooltip:AddLine("当前 SoloCollections 后端按角色应用幻化，暂未开放正式服的专精独立应用。", 0.72, 0.72, 0.72, true)
        GameTooltip:Show()
    end)
    specTip:Show()

    local function showApplyTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("应用", 1, 0.82, 0.18)
        if state.presetRecord then
            local canApply, reason, variantOwned, variantRequired = false, nil, nil, nil
            if state.GetSetApplyState then
                canApply, reason, variantOwned, variantRequired = state:GetSetApplyState()
            end
            if canApply then
                GameTooltip:AddLine("通过 SC2 请求服务端应用当前套装预设。", 0.72, 0.72, 0.72, true)
            elseif reason == "NOT_OWNED" then
                local owned = tonumber(variantOwned) or tonumber(state.presetRecord.collectedCount) or 0
                local required = tonumber(variantRequired) or tonumber(state.presetRecord.requiredCount) or #(state.presetRecord.itemIds or {})
                GameTooltip:AddLine("当前版本尚未收集完整：" .. owned .. " / " .. required, 1, 0.35, 0.25, true)
            elseif reason == "BRIDGE_UNAVAILABLE" then
                GameTooltip:AddLine("SC2 套装服务尚未就绪，暂不能提交应用。", 1, 0.35, 0.25, true)
            elseif reason == "REQUEST_PENDING" then
                GameTooltip:AddLine("已有应用请求正在处理。", 1, 0.76, 0.32, true)
            else
                GameTooltip:AddLine("当前套装预设暂不能提交应用。", 1, 0.35, 0.25, true)
            end
        else
            local canApply, reason = false, nil
            if state.GetDraftApplyState then
                canApply, reason = state:GetDraftApplyState()
            end
            if canApply then
                GameTooltip:AddLine("应用当前待定外观；每个槽位仍由 SC2 服务端验证。", 0.72, 0.72, 0.72, true)
            elseif reason == "NO_DRAFT" then
                GameTooltip:AddLine("先在右侧选择外观，建立待定幻化。", 0.72, 0.72, 0.72, true)
            elseif reason == "HIDE_VISUAL_UNSUPPORTED" then
                GameTooltip:AddLine("隐藏外观只能本地预览，当前没有可写入装备的 hide 源。", 1, 0.35, 0.25, true)
            elseif reason == "NOT_OWNED" then
                GameTooltip:AddLine("待定外观中包含未收藏项，只能本地预览。", 1, 0.35, 0.25, true)
            elseif reason == "BRIDGE_UNAVAILABLE" then
                GameTooltip:AddLine("SC2 外观服务尚未就绪，暂不能提交应用。", 1, 0.35, 0.25, true)
            elseif reason == "REQUEST_PENDING" then
                GameTooltip:AddLine("已有应用请求正在处理。", 1, 0.76, 0.32, true)
            else
                GameTooltip:AddLine("当前待定外观暂不能提交应用。", 1, 0.35, 0.25, true)
            end
        end
        GameTooltip:Show()
    end
    apply:SetScript("OnEnter", showApplyTooltip)
    apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local applyDisabledTip = createDisabledTooltipOverlay(apply, showApplyTooltip)

    page.scStateText = stateText
    page.scPanels = { left = left, right = right }
    page.scOutfits = outfits
    page.scPreview = preview
    page.scSlots = slots
    page.scSources = sources
    page.scApplyButton = apply
    page.scApplySlot = apply
    page.scApplyDisabledTip = applyDisabledTip
    page.scApplySet = sources.scApplySet
    page.scMoneyFrameTextures = { moneyLeft, moneyMiddle, moneyRight }
    page.scMoneyText = moneyText
    page.scSpecButton = spec
    page.scSpecDisabledTip = specTip
    page.scClearAllButton = outfits.scClearButton
    page.scLeftBackground = leftInset.background
end
