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

-- ez 2.2 WeaponHandWarning: model BOTTOM y=5, height 46, orange Search glow.
-- Shown only for MAINHAND / OFFHAND. Text is the ez enUS (Chinese) string.
local function createWeaponHandWarning(model)
    local warning = CreateFrame("Frame", nil, model)
    warning:SetHeight(46)
    warning:SetPoint("LEFT", model, "LEFT", 5, 0)
    warning:SetPoint("RIGHT", model, "RIGHT", -5, 0)
    warning:SetPoint("BOTTOM", model, "BOTTOM", 0, 5)
    warning:SetFrameLevel((model.GetFrameLevel and model:GetFrameLevel() or 0) + 8)
    warning:SetAlpha(0)
    warning:Hide()

    local searchPath = UI.EzCollections:MediaPath("Common", "Search.tga")
        or UI.EzCollections:MediaPath("Common", "Search.blp")
    local function addGlow(parent, layer)
        local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
        if searchPath then
            tex:SetTexture(searchPath)
            if tex.SetBlendMode then tex:SetBlendMode("ADD") end
            tex:SetVertexColor(1, 0.5, 0, 1)
        else
            tex:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
            tex:SetVertexColor(1, 0.45, 0, 0.55)
        end
        return tex
    end

    local bottom = addGlow(warning)
    bottom:SetHeight(2)
    bottom:SetPoint("LEFT")
    bottom:SetPoint("RIGHT")
    bottom:SetPoint("BOTTOM")
    if searchPath then bottom:SetTexCoord(0.001953125, 0.501953125, 0.5859375, 0.6015625) end

    local bottomGlow = addGlow(warning)
    bottomGlow:SetAllPoints(bottom)
    if searchPath then bottomGlow:SetTexCoord(0.001953125, 0.501953125, 0.5859375, 0.6015625) end

    local fill = addGlow(warning)
    fill:SetPoint("TOP")
    fill:SetPoint("LEFT")
    fill:SetPoint("RIGHT")
    fill:SetPoint("BOTTOM", bottom, "TOP")
    if searchPath then fill:SetTexCoord(0.001953125, 0.501953125, 0.421875, 0.5859375) end

    local fillGlow = addGlow(warning)
    fillGlow:SetAllPoints(fill)
    if searchPath then fillGlow:SetTexCoord(0.001953125, 0.501953125, 0.421875, 0.5859375) end

    local text = warning:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("TOP")
    text:SetPoint("LEFT", warning, "LEFT", 5, 0)
    text:SetPoint("RIGHT", warning, "RIGHT", -5, 0)
    text:SetPoint("BOTTOM", warning, "BOTTOM", 0, 5)
    if text.SetJustifyV then text:SetJustifyV("BOTTOM") end
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(true) end
    text:SetText("武器可能会出现在错误的手中")
    warning.Text = text
    warning.scWantShown = false

    warning:SetScript("OnUpdate", function(self, elapsed)
        local alpha = self:GetAlpha() or 0
        elapsed = elapsed or 0
        if self.scWantShown then
            if alpha < 1 then
                self:SetAlpha(math.min(1, alpha + elapsed * 2))
            end
        elseif alpha > 0 then
            alpha = alpha - elapsed * 2
            if alpha <= 0 then
                self:SetAlpha(0)
                self:Hide()
            else
                self:SetAlpha(alpha)
            end
        end
    end)

    function warning:SetActive(active)
        self.scWantShown = not not active
        if active then
            if not self:IsShown() then
                self:SetAlpha(0)
                self:Show()
            end
        end
    end

    return warning
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
    local weaponWarning = createWeaponHandWarning(preview)

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

    -- Legion: SmallMoneyFrameTemplate on the chrome. Only show the last U.copper
    -- quote, including a visible 0 copper; never estimate gold on the client.
    local moneyFrame
    local created = pcall(function()
        moneyFrame = CreateFrame(
            "Frame",
            "SoloCollectionsWardrobeMoneyFrame",
            left,
            "SmallMoneyFrameTemplate"
        )
    end)
    if not (created and moneyFrame) then
        moneyFrame = nil
    end
    local moneyText
    if moneyFrame then
        moneyFrame:ClearAllPoints()
        moneyFrame:SetPoint("RIGHT", moneyRight, "RIGHT", 6, 0)
        moneyFrame:SetFrameLevel(left:GetFrameLevel() + 8)
        if SmallMoneyFrame_OnLoad then pcall(SmallMoneyFrame_OnLoad, moneyFrame) end
        if MoneyFrame_SetType then pcall(MoneyFrame_SetType, moneyFrame, "STATIC") end
        if Lab.UpdateQuotedMoney then
            Lab.UpdateQuotedMoney(moneyFrame, 0)
        elseif MoneyFrame_Update then
            pcall(MoneyFrame_Update, moneyFrame:GetName(), 0)
        end
    else
        moneyText = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        moneyText:SetPoint("RIGHT", moneyRight, "RIGHT", 2, 0)
        moneyText:SetText("0")
        moneyText:SetTextColor(1, 0.82, 0.18)
    end
    local moneyHit = CreateFrame("Frame", nil, left)
    moneyHit:SetPoint("TOPLEFT", moneyLeft, "TOPLEFT", 0, 0)
    moneyHit:SetPoint("BOTTOMRIGHT", moneyRight, "BOTTOMRIGHT", 0, 0)
    moneyHit:SetFrameLevel(left:GetFrameLevel() + 12)
    moneyHit:EnableMouse(true)
    moneyHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("幻化费用", 1, 0.82, 0.18)
        local canApply, reason = false, nil
        if state.presetRecord and state.GetSetApplyState then
            canApply, reason = state:GetSetApplyState()
        elseif state.GetDraftApplyState then
            canApply, reason = state:GetDraftApplyState()
        end
        if not canApply and reason and reason ~= "NO_DRAFT" and Lab.ApplyReasonText then
            GameTooltip:AddLine(Lab.ApplyReasonText(reason, {
                set = state.presetRecord ~= nil,
                owned = state.presetRecord and state.presetRecord.collectedCount,
                required = state.presetRecord and state.presetRecord.requiredCount,
            }), 1, 0.35, 0.25, true)
        else
            GameTooltip:AddLine("只显示最近一次服务端报价。0 铜是合法报价，也会显示；没有可应用的待定时同样按 0。客户端不估算金币。", 0.72, 0.72, 0.72, true)
        end
        GameTooltip:Show()
    end)
    moneyHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local apply = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    apply:SetWidth(112)
    apply:SetHeight(22)
    apply:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, -22)
    apply:SetText("应用")
    apply:SetFrameLevel(left:GetFrameLevel() + 16)
    apply:SetScript("OnClick", function()
        if Lab.BeginApplyWithWarnings then
            Lab.BeginApplyWithWarnings(state)
        else
            state:BeginApplyAll()
        end
    end)

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
            else
                local owned = tonumber(variantOwned) or tonumber(state.presetRecord.collectedCount) or 0
                local required = tonumber(variantRequired) or tonumber(state.presetRecord.requiredCount) or #(state.presetRecord.itemIds or {})
                GameTooltip:AddLine(Lab.ApplyReasonText and Lab.ApplyReasonText(reason, {
                    set = true, owned = owned, required = required,
                }) or "当前套装预设暂不能提交应用。", 1, 0.35, 0.25, true)
            end
        else
            local canApply, reason = false, nil
            if state.GetDraftApplyState then
                canApply, reason = state:GetDraftApplyState()
            end
            if canApply then
                GameTooltip:AddLine("应用当前待定外观；每个槽位仍由 SC2 服务端验证。", 0.72, 0.72, 0.72, true)
            else
                GameTooltip:AddLine(
                    (Lab.ApplyReasonText and Lab.ApplyReasonText(reason)) or "当前待定外观暂不能提交应用。",
                    1, 0.35, 0.25, true
                )
            end
        end
        GameTooltip:Show()
    end
    apply:SetScript("OnEnter", showApplyTooltip)
    apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local applyDisabledTip = createDisabledTooltipOverlay(apply, showApplyTooltip)
    applyDisabledTip:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" and Lab.BeginApplyWithWarnings then
            Lab.BeginApplyWithWarnings(state)
        end
    end)

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
    page.scMoneyFrame = moneyFrame
    page.scMoneyText = moneyText
    page.scWeaponHandWarning = weaponWarning
    page.scClearAllButton = outfits.scClearButton
    page.scLeftBackground = leftInset.background
end
