local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local function addPanel(parent, width, left, title)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(width); panel:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -58)
    panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left, 12)
    UI.CreateInset(panel, { left = 0, top = 0, right = 0, bottom = 0 })
    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -13); heading:SetText(title)
    heading:SetTextColor(1.00, 0.82, 0.24)
    return panel
end

function Lab.CreateLayout(page, state)
    local badge = CreateFrame("Frame", nil, page)
    badge:SetWidth(58); badge:SetHeight(22); badge:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -7)
    local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
    badgeBg:SetTexture("Interface\\Buttons\\WHITE8X8"); badgeBg:SetAllPoints(badge)
    badgeBg:SetVertexColor(0.34, 0.12, 0.50, 0.92)
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER"); badgeText:SetText("实验"); badgeText:SetTextColor(0.92, 0.76, 1.00)

    local stateText = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stateText:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -10); stateText:SetTextColor(1.00, 0.68, 0.18)
    local capability = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    capability:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -31)
    capability:SetPoint("RIGHT", page, "RIGHT", -80, 0); capability:SetJustifyH("LEFT")
    capability:SetTextColor(0.72, 0.68, 0.60)

    local left = addPanel(page, 190, 0, "外观方案")
    local center = addPanel(page, 310, 200, "角色预览与 11 槽位")
    local right = addPanel(page, 328, 520, "候选来源")
    local outfits = Lab.CreateOutfits(left, state)
    local preview = Lab.CreatePreview(center, state)
    local slots = Lab.CreateSlots(center, state)
    local sources = Lab.CreateSources(right, state)

    local apply = CreateFrame("Button", nil, center, "UIPanelButtonTemplate")
    apply:SetWidth(124); apply:SetHeight(26); apply:SetPoint("BOTTOMLEFT", center, "BOTTOMLEFT", 13, 18)
    apply:SetText("应用所选槽位"); apply:SetScript("OnClick", function() state:BeginApply() end)
    local save = CreateFrame("Button", nil, center, "UIPanelButtonTemplate")
    save:SetWidth(150); save:SetHeight(26); save:SetPoint("LEFT", apply, "RIGHT", 8, 0)
    save:SetText("保存整套（待原子协议）"); save:Disable()
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if public then public.Components:SkinButton(apply); public.Components:SkinButton(save) end

    page.scStateText, page.scCapabilityText = stateText, capability
    page.scPanels = { left = left, center = center, right = right }
    page.scOutfits, page.scPreview, page.scSlots, page.scSources = outfits, preview, slots, sources
    page.scApplySlot, page.scMultiSaveButton, page.scExperimentalBadge = apply, save, badge
end
