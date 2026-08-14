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
    background:SetTexCoord(0, 1, 0, 1)
    background:SetHorizTile(false)
    background:SetVertTile(false)
end

function Lab.CreateLayout(page, state)
    local left = CreateFrame("Frame", nil, page)
    left:SetWidth(300)
    left:SetHeight(495)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -86)
    local leftInset = UI.EzCollections:ApplyInset(left)
    applyRaceBackground(left, leftInset.background)

    local right = CreateFrame("Frame", nil, page)
    right:SetWidth(662)
    right:SetHeight(606)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

    local preview = Lab.CreatePreview(left, state)
    local slots = Lab.CreateSlots(preview, state)
    local outfits = Lab.CreateOutfits(left, state)
    local sources = Lab.CreateSources(right, state)

    local stateText = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stateText:SetPoint("BOTTOM", left, "BOTTOM", 0, 5)
    stateText:SetWidth(270)
    stateText:SetJustifyH("CENTER")
    stateText:SetTextColor(1, 0.72, 0.24)

    local apply = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    apply:SetWidth(112)
    apply:SetHeight(22)
    apply:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, -22)
    apply:SetText("应用所选槽位")
    apply:SetFrameLevel(left:GetFrameLevel() + 16)
    apply:SetScript("OnClick", function() state:BeginApply() end)

    local save = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    save:SetWidth(160)
    save:SetHeight(22)
    save:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, -22)
    save:SetText("保存整套（待原子协议）")
    save:SetFrameLevel(left:GetFrameLevel() + 16)
    save:Disable()
    save:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("多槽自定义保存尚未开放", 1, 0.82, 0.18)
        GameTooltip:AddLine("等待服务端提供多槽原子保存合同；现有套装预设仍可通过右侧套装页应用。", 0.72, 0.72, 0.72, true)
        GameTooltip:Show()
    end)
    save:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page.scStateText = stateText
    page.scPanels = { left = left, right = right }
    page.scOutfits = outfits
    page.scPreview = preview
    page.scSlots = slots
    page.scSources = sources
    page.scApplySlot = apply
    page.scApplySet = sources.scApplySet
    page.scMultiSaveButton = save
    page.scClearAllButton = outfits.scClearButton
    page.scLeftBackground = leftInset.background
end
