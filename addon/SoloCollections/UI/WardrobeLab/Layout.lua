local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local SLOT_LABELS = {
    "头部", "肩部", "背部", "胸部", "手腕", "手部",
    "腰部", "腿部", "脚部", "主手", "副手",
}

local function addPanel(parent, width, left, title)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(width)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -58)
    panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left, 12)
    UI.CreateInset(panel, { left = 0, top = 0, right = 0, bottom = 0 })

    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -13)
    heading:SetText(title)
    heading:SetTextColor(1.00, 0.82, 0.24)
    return panel
end

function Lab.CreateLayout(page)
    local badge = CreateFrame("Frame", nil, page)
    badge:SetWidth(58)
    badge:SetHeight(22)
    badge:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -7)
    local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
    badgeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    badgeBg:SetAllPoints(badge)
    badgeBg:SetVertexColor(0.34, 0.12, 0.50, 0.92)
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER")
    badgeText:SetText("实验")
    badgeText:SetTextColor(0.92, 0.76, 1.00)

    local state = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    state:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -10)
    state:SetTextColor(1.00, 0.68, 0.18)
    page.scStateText = state

    local capability = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    capability:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -31)
    capability:SetPoint("RIGHT", page, "RIGHT", -80, 0)
    capability:SetJustifyH("LEFT")
    capability:SetTextColor(0.72, 0.68, 0.60)
    page.scCapabilityText = capability

    local left = addPanel(page, 190, 0, "外观方案")
    local center = addPanel(page, 310, 200, "角色预览与槽位")
    local right = addPanel(page, 328, 520, "候选来源")

    local emptyOutfits = left:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyOutfits:SetPoint("TOPLEFT", left, "TOPLEFT", 14, -46)
    emptyOutfits:SetPoint("RIGHT", left, "RIGHT", -14, 0)
    emptyOutfits:SetJustifyH("LEFT")
    emptyOutfits:SetText("方案列表将在交互骨架阶段接入。\n\n切换方案前会显式处理未保存草稿。")

    local modelPlaceholder = CreateFrame("Frame", nil, center)
    modelPlaceholder:SetPoint("TOPLEFT", center, "TOPLEFT", 58, -45)
    modelPlaceholder:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -58, 210)
    local modelBg = modelPlaceholder:CreateTexture(nil, "BACKGROUND")
    modelBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    modelBg:SetAllPoints(modelPlaceholder)
    modelBg:SetVertexColor(0.015, 0.018, 0.024, 0.94)
    local modelText = modelPlaceholder:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    modelText:SetPoint("CENTER")
    modelText:SetText("中央模型预览\n后续接入")
    modelText:SetJustifyH("CENTER")

    for index, label in ipairs(SLOT_LABELS) do
        local slot = CreateFrame("Frame", nil, center)
        slot:SetWidth(86)
        slot:SetHeight(25)
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        slot:SetPoint("BOTTOMLEFT", center, "BOTTOMLEFT", 12 + column * 96, 88 - row * 31)
        local slotBg = slot:CreateTexture(nil, "BACKGROUND")
        slotBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        slotBg:SetAllPoints(slot)
        slotBg:SetVertexColor(0.07, 0.065, 0.055, 0.92)
        local slotText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotText:SetPoint("CENTER")
        slotText:SetText(label)
    end

    local emptySources = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptySources:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -46)
    emptySources:SetPoint("RIGHT", right, "RIGHT", -14, 0)
    emptySources:SetJustifyH("LEFT")
    emptySources:SetText("候选来源仍将使用 SoloCollections Catalog。\n\n当前空页面不会读取 C_TransmogCollection，也不会发送服务端动作。")

    local save = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    save:SetWidth(170)
    save:SetHeight(26)
    save:SetPoint("BOTTOM", right, "BOTTOM", 0, 18)
    save:SetText("保存整套（等待服务端原子方案）")
    save:Disable()
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if public then public.Components:SkinButton(save) end

    page.scPanels = { left = left, center = center, right = right }
    page.scExperimentalBadge = badge
    page.scMultiSaveButton = save
end
