local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog
local Identity = SC.IdentityRegistry
local EzModel = SC.EzWardrobe.Model
local EzItems = SC.EzWardrobe.Items

local ITEM_PAGE_SIZE = EzItems.PAGE_SIZE
local EZ_LAYOUT = {
    itemWidth = EzItems.LAYOUT.itemWidth,
    itemHeight = EzItems.LAYOUT.itemHeight,
    itemGapX = EzItems.LAYOUT.itemGapX,
    itemGapY = EzItems.LAYOUT.itemGapY,
    -- The ezCollections grid is 548px wide. Wardrobe now uses the same 768px
    -- journal width as mounts, so keep the copied six-column grid centered.
    itemStartX = EzItems.LAYOUT.itemStartX,
    itemStartY = EzItems.LAYOUT.itemStartY,
    setColumns = 4,
    setWidth = 129,
    setHeight = 186,
    setGapX = 13,
    setGapY = 14,
    setStartX = 50,
    setStartY = 50,
}
local VISIBLE_SET_ROWS = 8
local SET_ROW_HEIGHT = 52
local SET_ROW_SPACING = 3
local SET_PIECE_SIZE = 40
local SET_PIECE_SPACING = 5
local SET_PIECE_COLUMNS = 8
local SET_PIECE_POOL_LIMIT = 12
local DEFAULT_ROTATION = 0.18
local function showAppearanceActionResult(ok, reason)
    local message
    if ok then
        message = "外观已应用。"
    elseif reason == "NOT_ENOUGH_MONEY" then
        message = "你没有足够的钱。"
    elseif reason == "NOT_ENOUGH_TOKENS" then
        message = "你的筹码不够。"
    elseif reason == "NOT_OWNED" then
        message = "尚未收藏此外观。"
    elseif reason == "INVALID_TARGET_SLOT" then
        message = "对应装备栏没有可幻化物品。"
    else
        message = "外观应用失败：" .. tostring(reason or "UNKNOWN")
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, ok and 0.35 or 1, ok and 1 or 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

local function showSetActionResult(ok, reason)
    local message
    if ok then
        message = "套装外观已原子应用。"
    elseif reason == "NOT_OWNED" then
        message = "尚未收集完整套装。"
    elseif reason == "INVALID_TARGET_SLOT" then
        message = "需要先在套装的每个目标栏位装备物品。"
    elseif reason == "CLASS_RESTRICTED" then
        message = "当前角色无法使用这个套装外观。"
    elseif reason == "NOT_ENOUGH_MONEY" then
        message = "你没有足够的钱。"
    elseif reason == "NOT_ENOUGH_TOKENS" then
        message = "你的筹码不够。"
    elseif reason == "BRIDGE_UNAVAILABLE" then
        message = "统一收藏服务尚未就绪。"
    else
        message = "套装应用失败：" .. tostring(reason or "UNKNOWN")
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, ok and 0.35 or 1, ok and 1 or 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

--[=[ Reference-only legacy SoloCam/workbench profiles. This long-commented
-- block is deliberately excluded from the active runtime chunk; item cards
-- have no callable fallback to it.
--
-- WotLK player models expose only camera 0 (portrait) and camera 1
-- (dressing-room). Adding a third camera to the player M2 crashes the client,
-- so SoloCam uses a generated race/sex/slot SetCamera handshake. The
-- immediately following camera 1 call is a safe stock-client fallback.
-- Legacy DressUpModel frames also keep the same fixed rectangle as their
-- cards: the 3.3.5 renderer does not safely clip oversized 3D viewports.
local WARDROBE_MODEL_PROFILES = {
    DEFAULT = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
    HEAD = { camera = 0, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.50 },
    SHOULDER = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.50 },
    BACK = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 3.14 },
    CHEST = { camera = 1, scaleMultiplier = 2.40, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = -0.30, rotation = 0.08 },
    WRIST = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = -0.62 },
    HANDS = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = -0.62 },
    WAIST = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
    LEGS = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
    FEET = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
}
--]=]

local CLASS_FILTERS = Identity.GetClassFilterOptions()

local ARMOR_TYPE_FILTERS = SC.EzWardrobe.DataProvider.ARMOR_OPTIONS

local SLOT_FILTERS = {
    { key = "HEAD", label = "头部", atlas = "head" },
    { key = "SHOULDER", label = "肩部", atlas = "shoulder" },
    { key = "BACK", label = "背部", atlas = "back" },
    { key = "CHEST", label = "胸部", atlas = "chest" },
    { key = "WRIST", label = "手腕", atlas = "wrist", gapAfter = 18 },
    { key = "HANDS", label = "手部", atlas = "hands" },
    { key = "WAIST", label = "腰部", atlas = "waist" },
    { key = "LEGS", label = "腿部", atlas = "legs" },
    { key = "FEET", label = "脚部", atlas = "feet", gapAfter = 18 },
    { key = "MAINHAND", label = "主手武器", atlas = "mainhand" },
    { key = "OFFHAND", label = "副手武器", atlas = "secondaryhand" },
}

local SLOT_ATLAS_SIZE = 512
local SLOT_ATLAS_REGIONS = {
    back = { 152, 187, 460, 497 },
    chest = { 231, 266, 48, 85 },
    feet = { 268, 303, 48, 85 },
    hands = { 305, 340, 48, 85 },
    head = { 342, 377, 48, 85 },
    legs = { 379, 414, 48, 85 },
    mainhand = { 416, 451, 48, 85 },
    secondaryhand = { 453, 488, 48, 85 },
    shoulder = { 228, 263, 88, 125 },
    waist = { 302, 337, 88, 125 },
    wrist = { 339, 374, 88, 125 },
    selected = { 105, 150, 460, 507 },
}

local ROUND_HIGHLIGHT_SIZE = { 256, 256 }
local ROUND_HIGHLIGHT_REGION = { 42, 78, 176, 212 }

-- Only categories present in the 3.3.5 ItemSubclass tables are exposed.
-- Warglaive models retain their own camera key, but filter as one-handed
-- swords because WotLK has no separate warglaive weapon subclass.
local WEAPON_FILTERS = {
    { key = "ONE_HAND_AXE", label = "单手斧", main = true, off = true },
    { key = "TWO_HAND_AXE", label = "双手斧", main = true },
    { key = "BOW", label = "弓", main = true },
    { key = "GUN", label = "枪械", main = true },
    { key = "ONE_HAND_MACE", label = "单手锤", main = true, off = true },
    { key = "TWO_HAND_MACE", label = "双手锤", main = true },
    { key = "POLEARM", label = "长柄武器", main = true },
    { key = "ONE_HAND_SWORD", label = "单手剑", main = true, off = true },
    { key = "TWO_HAND_SWORD", label = "双手剑", main = true },
    { key = "STAFF", label = "法杖", main = true },
    { key = "FIST_WEAPON", label = "拳套", main = true, off = true },
    { key = "DAGGER", label = "匕首", main = true, off = true },
    { key = "THROWN", label = "投掷武器", main = true },
    { key = "CROSSBOW", label = "弩", main = true },
    { key = "WAND", label = "魔杖", main = true },
    { key = "FISHING_POLE", label = "钓鱼竿", main = true },
    { key = "SHIELD", label = "盾牌", off = true },
    { key = "OFFHAND_ITEM", label = "副手物品", off = true },
}

local STANDALONE_ITEM_SLOTS = {
    MAINHAND = true,
    OFFHAND = true,
}

-- ItemSet evidence already expresses member slots. Keep preview ordering in
-- that domain rather than asking GetItemInfo for a cache-dependent inventory
-- type while DressUpModel is being rebuilt.
local SET_MEMBER_SLOT_ORDER = {
    HEAD = 1,
    SHOULDER = 2,
    BACK = 3,
    CHEST = 4,
    WRIST = 5,
    HANDS = 6,
    WAIST = 7,
    LEGS = 8,
    FEET = 9,
    MAINHAND = 10,
    OFFHAND = 11,
}

local function filterLabel(options, current)
    for _, option in ipairs(options) do
        if option.key == current then
            return option.label
        end
    end
    return options[1].label
end

local function setClassLabel(record)
    local policy = record and record.classPolicy
    if not policy then
        return filterLabel(CLASS_FILTERS, record and record.classToken)
    end
    if policy.mode == "ANY" then return "全部职业" end
    if policy.mode ~= "ALLOW_LIST" then return "职业未解析" end
    local labels = {}
    for _, classKey in ipairs(policy.allowedClassKeys or {}) do
        labels[#labels + 1] = filterLabel(CLASS_FILTERS, string.upper(classKey))
    end
    return table.concat(labels, "/")
end

local function hasFilterValue(options, current)
    for _, option in ipairs(options) do
        if option.key == current then
            return true
        end
    end
    return false
end

local function setAtlasRegion(texture, texturePath, atlasWidth, atlasHeight, region)
    texture:SetTexture(texturePath)
    texture:SetTexCoord(
        region[1] / atlasWidth,
        region[2] / atlasWidth,
        region[3] / atlasHeight,
        region[4] / atlasHeight
    )
end

local function getPlayerClassToken()
    local classIdentity = Identity.GetPlayerClass()
    return classIdentity.known and classIdentity.filterToken or nil
end

local function weaponOptionSupportsSlot(option, slot)
    return (slot == "MAINHAND" and option.main) or (slot == "OFFHAND" and option.off)
end

local function getAvailableWeaponFilters(slot)
    local result = {}
    local allowed = Identity.GetWeaponTypes(slot)
    for _, option in ipairs(WEAPON_FILTERS) do
        if weaponOptionSupportsSlot(option, slot) and allowed[option.key] then
            table.insert(result, option)
        end
    end
    return result
end

local function ensureWeaponTypeForSlot(filters, slot)
    local options = getAvailableWeaponFilters(slot)
    for _, option in ipairs(options) do
        if filters.weaponType == option.key then
            return option.key
        end
    end
    filters.weaponType = options[1] and options[1].key or "AUTO"
    return filters.weaponType
end

local function showItemTooltip(owner, record)
    if not record or not record.itemId then
        return
    end
    local itemName, itemLink = GetItemInfo(record.itemId)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        GameTooltip:SetText(itemName or record.name or "未知外观", 1, 0.82, 0.18)
    end
    if record.source then
        GameTooltip:AddLine("来源：" .. record.source, 0.94, 0.82, 0.58, true)
    end
    if record.weaponTypeLabel then
        GameTooltip:AddLine("武器类型：" .. record.weaponTypeLabel, 0.52, 0.82, 1.00, true)
    end
    GameTooltip:AddLine(record.collected and "已收集" or "未收集 · 仍可预览", record.collected and 0.38 or 0.62, record.collected and 0.90 or 0.58, 0.32)
    if record.collected then
        GameTooltip:AddLine("Shift + 左键：应用到当前装备", 1.00, 0.82, 0.18)
    end
    GameTooltip:Show()
end

local function showPieceTooltip(owner, itemId)
    if not itemId then return end
    local itemName, itemLink = GetItemInfo(itemId)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        GameTooltip:SetText(itemName or "套装部件")
    end
    GameTooltip:Show()
end

local function resolveTryOnItem(itemId)
    local _, itemLink = GetItemInfo(itemId)
    return itemLink or ("item:" .. itemId)
end


local function applyItemModelRecord(model, record, pageGeneration, force)
    pageGeneration = pageGeneration or ((model.scItemGeneration or 0) + 1)
    return EzModel:Present(model, record, pageGeneration, force)
end

SC.WardrobeUI.ItemCardRenderer = SC.WardrobeUI.ItemCardRenderer or {}
local ItemCardRenderer = SC.WardrobeUI.ItemCardRenderer

function ItemCardRenderer:Attach(model, objectModel)
    if model.scWardrobeItemCardRenderer then return end
    model.scWardrobeItemCardRenderer = true
    EzModel:Attach(model, objectModel)
end

function ItemCardRenderer:Present(model, record, generation)
    return applyItemModelRecord(model, record, generation)
end

function ItemCardRenderer:Clear(model, generation)
    return applyItemModelRecord(model, nil, generation)
end

function UI.CreateWardrobePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scItemPage = 1
    page.scSetPage = 1
    page.scSetOffset = 0
    page.scSetRecordCount = 0
    page.scSetPreviewGeneration = 0
    page.scDefaultSetClassApplied = false
    page.scItemModels = {}
    page.scItemPageSize = ITEM_PAGE_SIZE
    page.scSetRows = {}
    page.scSetCards = {}
    page.scPieceIcons = {}
    local setSetOffset
    local itemDataProvider = SC.EzWardrobe.DataProvider:Create(page)
    local wardrobeFilters = SC.WardrobeUI.Filters:Create(page, Catalog, itemDataProvider)
    local filterBar = CreateFrame("Frame", nil, page)
    filterBar:SetHeight(78)
    filterBar:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
    filterBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -60)
    filterBar:SetFrameLevel(page:GetFrameLevel() + 8)

    local armorDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeArmorDropdown", filterBar, "UIDropDownMenuTemplate")
    armorDropdown:SetPoint("TOPLEFT", filterBar, "TOPLEFT", -12, -6)
    UIDropDownMenu_SetWidth(armorDropdown, 148)

    -- Sets remain class-owned data in 3.3.5. Retail places this selector above
    -- the preview side, so it deliberately does not reuse the item filter's
    -- upper-left position.
    local classDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeClassDropdown", filterBar, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", 12, -6)
    UIDropDownMenu_SetWidth(classDropdown, 148)

    local slotsFrame = CreateFrame("Frame", nil, filterBar)
    slotsFrame:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 181, -20)
    slotsFrame:SetWidth(430)
    slotsFrame:SetHeight(42)
    page.scSlotButtons = {}

    local weaponDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeWeaponDropdown", filterBar, "UIDropDownMenuTemplate")
    weaponDropdown:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", 12, -40)
    UIDropDownMenu_SetWidth(weaponDropdown, 164)
    weaponDropdown:Hide()

    local function chooseDedicatedFilter(key, value)
        if not SC.db or not SC.db.filters then return end
        wardrobeFilters:Set(key, value)
        if key == "slot" and STANDALONE_ITEM_SLOTS[value] then
            ensureWeaponTypeForSlot(SC.db.filters, value)
        end
        page.scItemSelectedId = nil
        page.scSetSelectedId = nil
        page.scItemPage = 1
        setSetOffset(0, true)
        page:Refresh()
    end

    UIDropDownMenu_Initialize(armorDropdown, function()
        for _, option in ipairs(ARMOR_TYPE_FILTERS) do
            local armorOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = armorOption.label
            info.value = armorOption.key
            info.checked = SC.db and SC.db.filters.armorType == armorOption.key
            info.func = function()
                chooseDedicatedFilter("armorType", armorOption.key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(classDropdown, function()
        for _, option in ipairs(CLASS_FILTERS) do
            local classOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = classOption.label
            info.value = classOption.key
            info.checked = SC.db and SC.db.filters.classToken == classOption.key
            info.func = function()
                chooseDedicatedFilter("classToken", classOption.key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(weaponDropdown, function()
        if not SC.db or not SC.db.filters then return end
        for _, option in ipairs(getAvailableWeaponFilters(SC.db.filters.slot)) do
            local weaponOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = weaponOption.label
            info.value = weaponOption.key
            info.checked = SC.db.filters.weaponType == weaponOption.key
            info.func = function()
                chooseDedicatedFilter("weaponType", weaponOption.key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local xOffset = 0
    for _, option in ipairs(SLOT_FILTERS) do
        local slotOption = option
        local button = CreateFrame("Button", nil, slotsFrame)
        button:SetWidth(31)
        button:SetHeight(31)
        button:SetPoint("TOPLEFT", slotsFrame, "TOPLEFT", xOffset, 0)

        local normal = button:CreateTexture(nil, "ARTWORK")
        normal:SetWidth(35)
        normal:SetHeight(37)
        normal:SetPoint("CENTER", button, "CENTER", 0, 0)
        setAtlasRegion(
            normal,
            UI.EzCollections:MediaPath("Transmogrify", "Transmogrify.tga", UI.Media.wardrobeSlotAtlas),
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_REGIONS[slotOption.atlas]
        )
        button:SetNormalTexture(normal)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetWidth(31)
        highlight:SetHeight(31)
        highlight:SetPoint("CENTER", button, "CENTER", 0, 1)
        highlight:SetBlendMode("ADD")
        setAtlasRegion(
            highlight,
            UI.EzCollections:AssetPath("Interface\\ContainerFrame\\Bags.tga", UI.Media.roundHighlightAtlas),
            ROUND_HIGHLIGHT_SIZE[1],
            ROUND_HIGHLIGHT_SIZE[2],
            ROUND_HIGHLIGHT_REGION
        )
        button:SetHighlightTexture(highlight)

        local selected = button:CreateTexture(nil, "OVERLAY")
        selected:SetWidth(45)
        selected:SetHeight(47)
        selected:SetPoint("CENTER", button, "CENTER", 0, 0)
        setAtlasRegion(
            selected,
            UI.EzCollections:MediaPath("Transmogrify", "Transmogrify.tga", UI.Media.wardrobeSlotAtlas),
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_REGIONS.selected
        )
        selected:Hide()

        button:SetScript("OnClick", function()
            chooseDedicatedFilter("slot", slotOption.key)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slotOption.label, 1.00, 0.82, 0.18)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button.scSlot = slotOption.key
        button.scSelected = selected
        page.scSlotButtons[slotOption.key] = button
        xOffset = xOffset + 33 + (slotOption.gapAfter or 0)
    end

    local itemsPanel, itemsInset = EzItems:CreatePanel(page)

    local setsPanel = CreateFrame("Frame", nil, page)
    setsPanel:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
    setsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 5)
    local setsInset = UI.EzCollections:ApplyInset(setsPanel)
    UI.EzCollections:AddShadowOverlay(setsPanel)
    SC.WardrobeUI.Layout:StylePanel(setsPanel, setsInset.background)
    setsPanel:Hide()

    local preview = CreateFrame("Frame", nil, setsPanel)
    preview:SetAllPoints(setsPanel)
    preview:SetFrameLevel(setsPanel:GetFrameLevel() + 5)
    local previewBackground = preview:CreateTexture(nil, "BACKGROUND")
    previewBackground:SetTexture(UI.EzCollections:MediaPath(
        "Transmogrify",
        "TransmogSets.tga",
        "Interface\\Buttons\\WHITE8X8"
    ))
    previewBackground:SetWidth(418)
    previewBackground:SetHeight(64)
    previewBackground:SetPoint("BOTTOM", preview, "BOTTOM", 0, 3)
    previewBackground:SetTexCoord(0.001953125, 0.818359375, 0.70703125, 0.95703125)
    SC.WardrobeUI.Layout:StylePanel(preview, previewBackground)
    preview:Hide()

    local model = CreateFrame("DressUpModel", nil, preview)
    model:SetPoint("TOPLEFT", preview, "TOPLEFT", 9, -84)
    model:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -9, 76)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:Hide()
    local setPresenter = SC.WardrobeUI.ItemPresenter:AttachSet(model, function()
        return page:IsShown() and SC.db and SC.db.wardrobeTab == "SETS"
    end)

    local name = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 16, 43)
    name:SetWidth(190)
    name:SetJustifyH("LEFT")
    name:SetTextColor(1, 0.82, 0.18)

    local detail = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 16, 27)
    detail:SetWidth(190)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(0.82, 0.75, 0.62)

    local setProgress = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setProgress:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 16, 11)
    setProgress:SetTextColor(0.45, 0.90, 0.34)
    setProgress:Hide()
    page.scSetProgress = setProgress

    local reset = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
    reset:SetWidth(104)
    reset:SetHeight(25)
    reset:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -14, 13)
    reset:SetText("重置视角")
    reset:Hide()

    local applySet = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
    applySet:SetWidth(104)
    applySet:SetHeight(25)
    applySet:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -14, 13)
    applySet:SetText("应用套装")
    applySet:Disable()
    page.scApplySet = applySet
    local pieces = CreateFrame("Frame", nil, preview)
    pieces:SetPoint("TOP", name, "BOTTOM", 0, -8)
    -- The production catalogue currently tops out at eight pieces, but the
    -- preview contract must also cover nine-piece variants (and leave room for
    -- a reviewed future set) without rebuilding UI frames after the catalog
    -- has already loaded.  Keep the fixed pool bounded by the existing
    -- twelve-piece safety limit instead of sizing it from today's data.
    local piecePoolSize = SET_PIECE_POOL_LIMIT
    local poolColumns = math.min(SET_PIECE_COLUMNS, piecePoolSize)
    local poolRows = math.ceil(piecePoolSize / SET_PIECE_COLUMNS)
    pieces:SetWidth((poolColumns * SET_PIECE_SIZE) + (math.max(0, poolColumns - 1) * SET_PIECE_SPACING))
    pieces:SetHeight((poolRows * SET_PIECE_SIZE) + (math.max(0, poolRows - 1) * SET_PIECE_SPACING))
    pieces:Hide()
    for index = 1, piecePoolSize do
        local piece = CreateFrame("Button", nil, pieces)
        piece:SetWidth(SET_PIECE_SIZE)
        piece:SetHeight(SET_PIECE_SIZE)
        if index == 1 then
            piece:SetPoint("TOPLEFT", pieces, "TOPLEFT", 0, 0)
        elseif (index - 1) % SET_PIECE_COLUMNS == 0 then
            piece:SetPoint("TOPLEFT", page.scPieceIcons[index - SET_PIECE_COLUMNS], "BOTTOMLEFT", 0, -SET_PIECE_SPACING)
        else
            piece:SetPoint("LEFT", page.scPieceIcons[index - 1], "RIGHT", SET_PIECE_SPACING, 0)
        end

        local iconBackground = piece:CreateTexture(nil, "BACKGROUND")
        iconBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        iconBackground:SetAllPoints(piece)
        iconBackground:SetVertexColor(0.012, 0.014, 0.018, 0.94)

        local icon = piece:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", piece, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", piece, "BOTTOMRIGHT", -2, 2)
        UI.SetFallbackTexture(icon)

        local glass = piece:CreateTexture(nil, "OVERLAY")
        glass:SetTexture("Interface\\Buttons\\WHITE8X8")
        glass:SetPoint("TOPLEFT", piece, "TOPLEFT", 2, -2)
        glass:SetPoint("TOPRIGHT", piece, "TOPRIGHT", -2, -2)
        glass:SetHeight(15)
        glass:SetGradientAlpha("VERTICAL", 0.72, 0.82, 0.92, 0.015, 0.90, 0.95, 1.00, 0.16)

        local border = UI.CreateThinCardBorder(piece, 1)
        border:SetBorderColor(0.46, 0.47, 0.49, 0.92)

        local highlight = piece:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
        highlight:SetPoint("TOPLEFT", piece, "TOPLEFT", 2, -2)
        highlight:SetPoint("BOTTOMRIGHT", piece, "BOTTOMRIGHT", -2, 2)
        highlight:SetVertexColor(1.00, 0.88, 0.52, 0.14)
        piece:SetHighlightTexture(highlight)

        piece:SetScript("OnEnter", function(self)
            if self.scItemId then
                showPieceTooltip(self, self.scItemId)
            end
        end)
        piece:SetScript("OnLeave", function() GameTooltip:Hide() end)
        piece.scIcon = icon
        piece.scBorder = border
        SC.WardrobeUI.Layout:StyleItemButton(piece, nil)
        piece:Hide()
        page.scPieceIcons[index] = piece
    end

    local function clearDragState()
        model.scDragging = nil
        model.scLastCursorX = nil
    end

    local function resetModelView()
        clearDragState()
        model.scRotation = DEFAULT_ROTATION
        model.scZoom = 0
        model:SetRotation(DEFAULT_ROTATION)
        if model.SetPosition then
            pcall(function() model:SetPosition(0, 0, 0) end)
        end
    end

    local function preparePlayerModel()
        model:ClearModel()
        resetModelView()
        pcall(function() model:SetUnit("player") end)
    end

    local function deriveSetPieceState(record)
        local state = {}
        local variant = record and record.selectedVariant
        for _, member in ipairs(variant and variant.members or {}) do
            local collected = false
            for _, appearanceId in ipairs(member.appearanceIds or {}) do
                if SC.CollectionState and SC.CollectionState.IsOwnedByType and
                    SC.CollectionState.IsOwnedByType(13, appearanceId) then
                    collected = true
                    break
                end
            end
            for _, itemId in ipairs(member.sourceItemIds or {}) do
                state[itemId] = collected
            end
        end
        return state
    end

    local function updateSetPieceVisual(piece, itemId, collected)
        local icon = GetItemIcon(itemId)
        UI.SetIconTexture(piece.scIcon, icon)
        UI.SetCollectedVisual(piece.scIcon, collected, 0.50)

        -- Item quality may arrive asynchronously. Use a neutral glass rim until
        -- GET_ITEM_INFO_RECEIVED supplies the real quality colour.
        local quality = select(3, GetItemInfo(itemId))
        local red, green, blue = 0.46, 0.47, 0.49
        if quality and GetItemQualityColor then
            red, green, blue = GetItemQualityColor(quality)
        end
        piece.scBorder:SetBorderColor(red, green, blue, collected and 1.00 or 0.74)
        piece.scQuality = quality
        piece.scCollected = collected and true or false
        SC.WardrobeUI.Layout:StyleItemButton(piece, quality)
    end

    -- Preview uses exactly one deterministic source item per selected-variant
    -- member. This is intentionally separate from the server-side owned
    -- alternative resolver used by APPLY: a local DressUpModel preview must
    -- not imply which source item the server would eventually choose.
    local function getSelectedVariantPreviewItems(record)
        local result = {}
        local seenSlots = {}
        local variant = record and record.selectedVariant
        for memberIndex, member in ipairs(variant and variant.members or {}) do
            if member.required then
                local previewSourceItemId = tonumber(member.previewSourceItemId)
                if not previewSourceItemId or previewSourceItemId <= 0 then
                    for _, sourceItemId in ipairs(member.sourceItemIds or {}) do
                        sourceItemId = tonumber(sourceItemId)
                        if sourceItemId and sourceItemId > 0 and
                            (not previewSourceItemId or sourceItemId < previewSourceItemId) then
                            previewSourceItemId = sourceItemId
                        end
                    end
                end
                local slotKey = tostring(member.slotKey or member.memberKey or "")
                local uniqueSlot = slotKey ~= "" and slotKey or ("member:" .. memberIndex)
                if previewSourceItemId and not seenSlots[uniqueSlot] then
                    seenSlots[uniqueSlot] = true
                    table.insert(result, {
                        memberIndex = memberIndex,
                        memberKey = tostring(member.memberKey or uniqueSlot),
                        slotKey = slotKey,
                        previewSourceItemId = previewSourceItemId,
                        order = SET_MEMBER_SLOT_ORDER[slotKey] or (100 + memberIndex),
                    })
                end
            end
        end
        table.sort(result, function(left, right)
            if left.order == right.order then
                if left.memberKey == right.memberKey then
                    return left.previewSourceItemId < right.previewSourceItemId
                end
                return left.memberKey < right.memberKey
            end
            return left.order < right.order
        end)
        return result
    end

    local function cancelSetPreview()
        page.scSetPreviewGeneration = (page.scSetPreviewGeneration or 0) + 1
        page.scSetPreviewPending = nil
        page.scAdvanceSetPreview = nil
        model.scSetPreviewGeneration = page.scSetPreviewGeneration
        model.scSetPreviewPending = nil
        if setPresenter then setPresenter:Clear("SET_PREVIEW_INVALIDATED") end
        for _, card in ipairs(page.scSetCards or {}) do
            if card.scPresenter then card.scPresenter:Clear("SET_GRID_INVALIDATED") end
        end
    end

    local function queueSetPreview(record)
        local generation = (page.scSetPreviewGeneration or 0) + 1
        local previewItems = getSelectedVariantPreviewItems(record)
        local pending = {
            generation = generation,
            recordId = record and record.id,
            items = previewItems,
            renderTicks = 0,
        }
        page.scSetPreviewGeneration = generation
        page.scSetPreviewPending = pending
        model.scSetPreviewGeneration = generation
        model.scSetPreviewPending = pending
        local itemStrings = {}
        for _, previewItem in ipairs(previewItems) do
            itemStrings[#itemStrings + 1] = resolveTryOnItem(previewItem.previewSourceItemId)
        end
        setPresenter:Present({
            unit = "player",
            undress = true,
            settleTicks = 2,
            items = itemStrings,
            onReady = function()
                if page.scSetPreviewPending == pending and page.scSetSelectedId == pending.recordId then
                    page.scSetPreviewPending = nil
                    model.scSetPreviewPending = nil
                end
            end,
        })
        return previewItems
    end

    local function previewSet(record)
        if not record then return end
        page.scSetSelectedRecord = record
        if record.collected then applySet:Enable() else applySet:Disable() end
        model:Hide()
        local previewItems = getSelectedVariantPreviewItems(record)
        name:SetText(record.name or "未知套装")
        local collectedPieces = tonumber(record.collectedCount) or 0
        local requiredPieces = tonumber(record.requiredCount) or #previewItems
        detail:SetText("职业：" .. setClassLabel(record) .. "  ·  " .. collectedPieces .. "/" .. requiredPieces .. " 外观")
        pieces:Hide()
        for index, piece in ipairs(page.scPieceIcons) do
            piece.scItemId = nil
            piece:Hide()
        end
        setProgress:SetText(record.collected and "已收集 · 可应用" or "未完整收集 · 仅本地预览")
        setProgress:Show()
    end

    if SC.ModelProvider.GetMode("DRESSUP") == "legacy" then
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.scDragging = true
            self.scLastCursorX = GetCursorPosition()
        end
    end)
    model:SetScript("OnMouseUp", function() clearDragState() end)
    model:SetScript("OnUpdate", function(self)
        if self.scDragging and IsMouseButtonDown("LeftButton") then
            local cursorX = GetCursorPosition()
            local delta = cursorX - (self.scLastCursorX or cursorX)
            self.scRotation = (self.scRotation or DEFAULT_ROTATION) + delta * 0.012
            self:SetRotation(self.scRotation)
            self.scLastCursorX = cursorX
        elseif self.scDragging then
            clearDragState()
        end
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        if model.SetPosition then
            self.scZoom = math.max(-0.7, math.min(0.7, (self.scZoom or 0) + delta * 0.08))
            pcall(function() self:SetPosition(0, 0, self.scZoom) end)
        end
    end)
    end
    reset:SetScript("OnClick", function()
        if setPresenter and setPresenter.ResetView then setPresenter:ResetView() else resetModelView() end
    end)
    applySet:SetScript("OnClick", function()
        local record = page.scSetSelectedRecord
        if not record or not record.collected then
            showSetActionResult(false, "NOT_OWNED")
        elseif not SC.Bridge or not SC.Bridge.ApplySet then
            showSetActionResult(false, "BRIDGE_UNAVAILABLE")
        else
            local variant = record.selectedVariant
            SC.Bridge.ApplySet(record.id, variant and variant.variantOrdinal or nil, showSetActionResult)
        end
    end)

    local function selectItem(record)
        page.scItemSelectedId = record and record.id or nil
        for _, itemModel in ipairs(page.scItemModels) do
            local selected = itemModel.scRecord and itemModel.scRecord.id == page.scItemSelectedId
            if selected then
                itemModel.scSelected:Show()
            else
                itemModel.scSelected:Hide()
            end
        end
    end

--[=[ Reference-only in-game M2 camera tuner. The active item page neither
-- creates these frames nor exposes a toggle/fallback path.
    -- In-game M2 camera tuner -------------------------------------------------
    -- This intentionally lives on the item page rather than in the ordinary
    -- options UI: a pose only makes sense while its exact weapon card is
    -- visible. The values are persisted by weapon type, never written into the
    -- catalog record, and can later be exported into Appearances.lua.
    local cameraTuningButton
    local cameraTuningPanel = CreateFrame("Frame", "SoloCollectionsM2CameraTuningPanel", page)
    cameraTuningPanel:SetWidth(286)
    cameraTuningPanel:SetHeight(486)
    cameraTuningPanel:SetPoint("TOPRIGHT", itemsPanel, "TOPRIGHT", -4, -4)
    -- The item cards are children of itemsPanel and therefore may sit above a
    -- sibling frame whose level is derived only from page.  Keep the workbench
    -- in the normal frame strata, but place it explicitly above the cards so
    -- it remains visible on the stock 3.3.5 client.
    cameraTuningPanel:SetFrameLevel(itemsPanel:GetFrameLevel() + 12)
    cameraTuningPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    cameraTuningPanel:SetBackdropColor(0.025, 0.022, 0.018, 0.98)
    cameraTuningPanel:SetBackdropBorderColor(0.68, 0.49, 0.18, 1)
    cameraTuningPanel:Hide()
    cameraTuningPanel.scControls = {}
    cameraTuningPanel.scBodyControls = {}
    cameraTuningPanel.scScope = "weaponFamily"
    cameraTuningPanel.scMode = "weapon"
    cameraTuningPanel.scSessionBefore = {}
    cameraTuningPanel.scBatch = {}
    cameraTuningPanel.scBodySessionBefore = {}
    cameraTuningPanel.scBodyBatch = {}

    local tuningTitle = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tuningTitle:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -10)
    tuningTitle:SetText("镜头工作台")
    tuningTitle:SetTextColor(1.00, 0.82, 0.20)

    local tuningRecord = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tuningRecord:SetPoint("TOPLEFT", tuningTitle, "BOTTOMLEFT", 0, -4)
    tuningRecord:SetPoint("RIGHT", cameraTuningPanel, "RIGHT", -96, 0)
    tuningRecord:SetJustifyH("LEFT")
    tuningRecord:SetTextColor(0.80, 0.74, 0.63)

    local tuningScopeDropdown = CreateFrame("Frame", "SoloCollectionsM2CameraScopeDropdown", cameraTuningPanel, "UIDropDownMenuTemplate")
    tuningScopeDropdown:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -18, -17)
    UIDropDownMenu_SetWidth(tuningScopeDropdown, 74)

    local tuningMetadata = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tuningMetadata:SetPoint("TOPLEFT", tuningRecord, "BOTTOMLEFT", 0, -3)
    tuningMetadata:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -12, -47)
    tuningMetadata:SetHeight(37)
    tuningMetadata:SetJustifyH("LEFT")
    tuningMetadata:SetJustifyV("TOP")
    tuningMetadata:SetTextColor(0.63, 0.59, 0.51)

    local tuningStrategy = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningStrategy:SetWidth(118)
    tuningStrategy:SetHeight(21)
    tuningStrategy:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -70)
    local function syncTuningStrategyLabel()
        local strategy = page.scCameraWorkbench and page.scCameraWorkbench.strategy
        tuningStrategy:SetText(strategy == "NEWERA_POSITION" and "A: NewEra 位移" or "B: Profile/SoloCam")
    end
    tuningStrategy:SetScript("OnClick", function()
        page.scCameraWorkbench:ToggleStrategy()
        syncTuningStrategyLabel()
        page:Refresh()
    end)
    syncTuningStrategyLabel()

    local tuningClose = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelCloseButton")
    tuningClose:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", 2, 2)

    local tuningHint = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tuningHint:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -294)
    tuningHint:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -12, -294)
    tuningHint:SetHeight(28)
    tuningHint:SetJustifyH("LEFT")
    tuningHint:SetJustifyV("TOP")
    tuningHint:SetText("范围：武器类别 / 此模型 / 此外观。数值会立即预览；导出仅生成待审核候选。")
    tuningHint:SetTextColor(0.62, 0.58, 0.49)

    local tuningPrevious = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningPrevious:SetWidth(78)
    tuningPrevious:SetHeight(22)
    tuningPrevious:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -327)
    tuningPrevious:SetText("上一条")

    local tuningNext = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningNext:SetWidth(78)
    tuningNext:SetHeight(22)
    tuningNext:SetPoint("LEFT", tuningPrevious, "RIGHT", 6, 0)
    tuningNext:SetText("下一条")

    local tuningPreviousUncalibrated = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningPreviousUncalibrated:SetWidth(122)
    tuningPreviousUncalibrated:SetHeight(22)
    tuningPreviousUncalibrated:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -353)
    tuningPreviousUncalibrated:SetText("上一条未校准")

    local tuningNextUncalibrated = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningNextUncalibrated:SetWidth(122)
    tuningNextUncalibrated:SetHeight(22)
    tuningNextUncalibrated:SetPoint("LEFT", tuningPreviousUncalibrated, "RIGHT", 6, 0)
    tuningNextUncalibrated:SetText("下一条未校准")

    -- A 3.3.5 EditBox is not clipped by its own height. Keep the review JSONL
    -- in a ScrollFrame so long records cannot paint over the sliders above it.
    local tuningExportScroll = CreateFrame("ScrollFrame", nil, cameraTuningPanel)
    tuningExportScroll:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 12)
    tuningExportScroll:SetPoint("BOTTOMRIGHT", cameraTuningPanel, "BOTTOMRIGHT", -12, 12)
    tuningExportScroll:SetHeight(42)
    tuningExportScroll:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tuningExportScroll:SetBackdropColor(0.015, 0.012, 0.010, 0.88)
    tuningExportScroll:SetBackdropBorderColor(0.40, 0.30, 0.16, 0.85)
    tuningExportScroll:EnableMouseWheel(true)

    local tuningExport = CreateFrame("EditBox", nil, tuningExportScroll, "InputBoxTemplate")
    tuningExport:SetWidth(254)
    tuningExport:SetHeight(512)
    if tuningExport.SetMultiLine then tuningExport:SetMultiLine(true) end
    tuningExport:SetAutoFocus(false)
    tuningExport:SetFontObject("ChatFontNormal")
    tuningExport:SetTextColor(0.92, 0.84, 0.62)
    tuningExportScroll:SetScrollChild(tuningExport)
    tuningExportScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, tuningExport:GetHeight() - self:GetHeight())
        local nextScroll = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 20))
        self:SetVerticalScroll(nextScroll)
    end)
    tuningExport:SetScript("OnTextChanged", function()
        tuningExportScroll:SetVerticalScroll(0)
    end)
    tuningExport:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local tuningReset = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningReset:SetWidth(84)
    tuningReset:SetHeight(22)
    tuningReset:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 61)
    tuningReset:SetText("恢复当前层")

    local tuningCopy = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningCopy:SetWidth(78)
    tuningCopy:SetHeight(22)
    tuningCopy:SetPoint("LEFT", tuningReset, "RIGHT", 4, 0)
    tuningCopy:SetText("复制当前")

    local tuningBatch = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningBatch:SetWidth(78)
    tuningBatch:SetHeight(22)
    tuningBatch:SetPoint("LEFT", tuningCopy, "RIGHT", 4, 0)
    tuningBatch:SetText("加入批次")

    local tuningCopyAll = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningCopyAll:SetWidth(84)
    tuningCopyAll:SetHeight(22)
    tuningCopyAll:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 86)
    tuningCopyAll:SetText("复制本次修改")

    local tuningDiscard = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningDiscard:SetWidth(98)
    tuningDiscard:SetHeight(22)
    tuningDiscard:SetPoint("LEFT", tuningCopyAll, "RIGHT", 6, 0)
    tuningDiscard:SetText("放弃未导出")

    local function updateTuningValueLabel(control, value)
        control.value:SetText(string.format("%.2f", value))
    end

    local applyCameraTuning
    local applyBodyCameraTuning
    local updateCameraTuningExport

    local function getCameraTuningScopeKey(record, scope)
        if scope == "appearance" then return getAppearanceCameraKey(record) end
        if scope == "model" then return getModelCameraKey(record) end
        return getWeaponFamilyCameraKey(record)
    end

    local CAMERA_TUNING_SCOPES = {
        { key = "weaponFamily", label = "武器类别" },
        { key = "model", label = "此模型" },
        { key = "appearance", label = "此外观" },
    }

    local function cameraTuningScopeLabel(scope)
        for _, option in ipairs(CAMERA_TUNING_SCOPES) do
            if option.key == scope then return option.label end
        end
        return "武器类别"
    end

    local function cameraTuningSourceLabel(source)
        if source == "auto" then return "自动基线" end
        if source == "generatedModel" then return "已审核模型基线" end
        return cameraTuningScopeLabel(source)
    end

    UIDropDownMenu_Initialize(tuningScopeDropdown, function()
        for _, option in ipairs(CAMERA_TUNING_SCOPES) do
            local scopeOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = scopeOption.label
            info.value = scopeOption.key
            info.checked = cameraTuningPanel.scScope == scopeOption.key
            info.func = function()
                local record = cameraTuningPanel.scRecord
                if scopeOption.key == "model" and not getModelCameraKey(record) then
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前外观没有稳定模型签名，不能使用模型范围。")
                    end
                    return
                end
                cameraTuningPanel.scScope = scopeOption.key
                UIDropDownMenu_SetSelectedValue(tuningScopeDropdown, scopeOption.key)
                UIDropDownMenu_SetText(tuningScopeDropdown, scopeOption.label)
                if record then page:SyncCameraTuningPanel(record) end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local function createCameraTuningSlider(index, key, labelText, limits, targetIndex)
        local row = CreateFrame("Frame", nil, cameraTuningPanel)
        row:SetWidth(262)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -96 - ((index - 1) * 27))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 2)
        label:SetWidth(48)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        label:SetTextColor(0.88, 0.78, 0.58)

        local sliderName = "SoloCollectionsM2Camera" .. key .. "Slider"
        -- Do not use OptionsSliderTemplate here.  Its settings-panel scripts can
        -- assign a zero/default value when an ancestor frame becomes visible,
        -- which races the workbench's autoCamera baseline.  This small local
        -- slider owns only the visuals and has no hidden configuration state.
        local slider = CreateFrame("Slider", sliderName, row)
        slider:SetPoint("LEFT", label, "RIGHT", 2, 0)
        slider:SetWidth(76)
        slider:SetHeight(16)
        slider:SetOrientation("HORIZONTAL")
        local sliderTrack = slider:CreateTexture(nil, "BACKGROUND")
        sliderTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
        sliderTrack:SetHeight(3)
        sliderTrack:SetPoint("LEFT", slider, "LEFT", 2, 0)
        sliderTrack:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
        sliderTrack:SetVertexColor(0.36, 0.27, 0.15, 1)
        local sliderThumb = slider:CreateTexture(nil, "OVERLAY")
        sliderThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        sliderThumb:SetWidth(12)
        sliderThumb:SetHeight(16)
        slider:SetThumbTexture(sliderThumb)
        slider:SetMinMaxValues(limits.minimum, limits.maximum)
        slider:SetValueStep(limits.step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local value = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        value:SetPoint("LEFT", slider, "RIGHT", 3, 0)
        value:SetWidth(39)
        value:SetHeight(18)
        value:SetAutoFocus(false)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(1.00, 0.85, 0.34)

        local control = {
            key = key,
            targetIndex = targetIndex,
            slider = slider,
            value = value,
            limits = limits,
            buttons = {},
            row = row,
        }
        table.insert(cameraTuningPanel.scControls, control)

        local function applyDelta(delta)
            slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, slider:GetValue() + delta)))
        end

        local function createStepButton(offset, text, delta)
            local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            button:SetWidth(15)
            button:SetHeight(18)
            button:SetPoint("LEFT", value, "RIGHT", offset, 0)
            button:SetText(text)
            button:SetScript("OnClick", function() applyDelta(delta) end)
            table.insert(control.buttons, button)
        end
        createStepButton(3, "-", -limits.step)
        createStepButton(20, "--", -limits.step * 5)
        createStepButton(37, "+", limits.step)
        createStepButton(54, "++", limits.step * 5)

        value:SetScript("OnEnterPressed", function(self)
            local parsed = tonumber(self:GetText())
            if parsed then
                slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, parsed)))
            else
                updateTuningValueLabel(control, slider:GetValue())
            end
            self:ClearFocus()
        end)
        value:SetScript("OnEscapePressed", function(self)
            updateTuningValueLabel(control, slider:GetValue())
            self:ClearFocus()
        end)
        slider:SetScript("OnValueChanged", function(_, valueChanged)
            updateTuningValueLabel(control, valueChanged)
            if cameraTuningPanel.scSyncing or not cameraTuningPanel.scRecord
                or not SC.db or not SC.M2Camera or not SC.M2Camera.NormalizePose then
                return
            end
            local pose = SC.M2Camera.NormalizePose(cameraTuningPanel.scPose)
            if targetIndex then
                pose.target[targetIndex] = valueChanged
            else
                pose[key] = valueChanged
            end
            pose = SC.M2Camera.NormalizePose(pose)
            cameraTuningPanel.scPose = pose
            local scope = cameraTuningPanel.scScope or "weaponFamily"
            local tuningKey = getCameraTuningScopeKey(cameraTuningPanel.scRecord, scope)
            local lowerScopePose = select(1, resolveM2CameraScopePose(cameraTuningPanel.scRecord, scope))
            if not tuningKey or not SC.CameraTuning or not SC.CameraTuning.Set then return end
            local sessionKey = scope .. "\031" .. tuningKey
            if cameraTuningPanel.scSessionBefore[sessionKey] == nil then
                local previous = SC.CameraTuning.Get and SC.CameraTuning.Get(scope, tuningKey) or nil
                cameraTuningPanel.scSessionBefore[sessionKey] = previous or false
            end
            SC.CameraTuning.Set(scope, tuningKey, pose, lowerScopePose)
            cameraTuningPanel.scCurrentDirty = true
            if cameraTuningPanel.scBatch[sessionKey] then
                cameraTuningPanel.scBatch[sessionKey].pose = pose
            end
            applyCameraTuning(cameraTuningPanel.scRecord)
            updateCameraTuningExport()
        end)
        return control
    end

    local cameraLimits = (SC.M2Camera and SC.M2Camera.Limits) or {
        yaw = { minimum = -math.pi, maximum = math.pi, step = 0.01 },
        pitch = { minimum = -1.20, maximum = 1.20, step = 0.01 },
        roll = { minimum = -math.pi, maximum = math.pi, step = 0.01 },
        distanceScale = { minimum = 0.25, maximum = 4.00, step = 0.01 },
        target = { minimum = -4.00, maximum = 4.00, step = 0.01 },
    }
    createCameraTuningSlider(1, "yaw", "Yaw 环绕", cameraLimits.yaw)
    createCameraTuningSlider(2, "pitch", "Pitch 俯仰", cameraLimits.pitch)
    createCameraTuningSlider(3, "roll", "Roll 滚转", cameraLimits.roll)
    createCameraTuningSlider(4, "distanceScale", "Distance 距离", cameraLimits.distanceScale)
    createCameraTuningSlider(5, "targetX", "Target X", cameraLimits.target, 1)
    createCameraTuningSlider(6, "targetY", "Target Y", cameraLimits.target, 2)
    createCameraTuningSlider(7, "targetZ", "Target Z", cameraLimits.target, 3)

    local function createBodyCameraTuningSlider(index, key, labelText, limits)
        local row = CreateFrame("Frame", nil, cameraTuningPanel)
        row:SetWidth(262)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -96 - ((index - 1) * 27))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 2)
        label:SetWidth(48)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        label:SetTextColor(0.72, 0.84, 0.96)

        local slider = CreateFrame("Slider", "SoloCollectionsBodyCamera" .. key .. "Slider", row)
        slider:SetPoint("LEFT", label, "RIGHT", 2, 0)
        slider:SetWidth(76)
        slider:SetHeight(16)
        slider:SetOrientation("HORIZONTAL")
        local sliderTrack = slider:CreateTexture(nil, "BACKGROUND")
        sliderTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
        sliderTrack:SetHeight(3)
        sliderTrack:SetPoint("LEFT", slider, "LEFT", 2, 0)
        sliderTrack:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
        sliderTrack:SetVertexColor(0.16, 0.32, 0.48, 1)
        local sliderThumb = slider:CreateTexture(nil, "OVERLAY")
        sliderThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        sliderThumb:SetWidth(12)
        sliderThumb:SetHeight(16)
        slider:SetThumbTexture(sliderThumb)
        slider:SetMinMaxValues(limits.minimum, limits.maximum)
        slider:SetValueStep(limits.step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local value = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        value:SetPoint("LEFT", slider, "RIGHT", 3, 0)
        value:SetWidth(39)
        value:SetHeight(18)
        value:SetAutoFocus(false)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(0.48, 0.84, 1.00)

        local control = { key = key, slider = slider, value = value, limits = limits, buttons = {}, row = row }
        table.insert(cameraTuningPanel.scBodyControls, control)
        local function update(valueChanged)
            value:SetText(string.format("%.2f", valueChanged))
        end
        local function applyDelta(delta)
            slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, slider:GetValue() + delta)))
        end
        local function createStepButton(offset, text, delta)
            local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            button:SetWidth(15)
            button:SetHeight(18)
            button:SetPoint("LEFT", value, "RIGHT", offset, 0)
            button:SetText(text)
            button:SetScript("OnClick", function() applyDelta(delta) end)
            table.insert(control.buttons, button)
        end
        createStepButton(3, "-", -limits.step)
        createStepButton(20, "--", -limits.step * 5)
        createStepButton(37, "+", limits.step)
        createStepButton(54, "++", limits.step * 5)
        value:SetScript("OnEnterPressed", function(self)
            local parsed = tonumber(self:GetText())
            if parsed then
                slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, parsed)))
            else
                update(slider:GetValue())
            end
            self:ClearFocus()
        end)
        value:SetScript("OnEscapePressed", function(self)
            update(slider:GetValue())
            self:ClearFocus()
        end)
        slider:SetScript("OnValueChanged", function(_, valueChanged)
            update(valueChanged)
            if cameraTuningPanel.scSyncing or cameraTuningPanel.scMode ~= "body"
                or not cameraTuningPanel.scBodyProfile or not SC.M2Camera
                or not SC.M2Camera.NormalizeBodyDelta or not SC.BodyCameraTuning then
                return
            end
            local delta = SC.M2Camera.NormalizeBodyDelta(cameraTuningPanel.scBodyDelta)
            delta[key] = valueChanged
            delta = SC.M2Camera.NormalizeBodyDelta(delta)
            local profile = cameraTuningPanel.scBodyProfile
            local sessionKey = profile.profileKey
            if cameraTuningPanel.scBodySessionBefore[sessionKey] == nil then
                local previous = SC.BodyCameraTuning.Get and SC.BodyCameraTuning.Get(sessionKey) or nil
                cameraTuningPanel.scBodySessionBefore[sessionKey] = previous or false
            end
            if not SC.BodyCameraTuning.Set or not SC.BodyCameraTuning.Set(sessionKey, delta) then return end
            cameraTuningPanel.scBodyDelta = delta
            cameraTuningPanel.scCurrentDirty = true
            if cameraTuningPanel.scBodyBatch[sessionKey] then
                cameraTuningPanel.scBodyBatch[sessionKey].delta = delta
            end
            applyBodyCameraTuning(profile)
            updateCameraTuningExport()
        end)
        row:Hide()
        return control
    end

    local bodyLimits = (SC.M2Camera and SC.M2Camera.BodyLimits) or {
        verticalOffsetDelta = { minimum = -2.00, maximum = 2.00, step = 0.01 },
        horizontalOffsetDelta = { minimum = -2.00, maximum = 2.00, step = 0.01 },
        distanceScaleMultiplier = { minimum = 0.50, maximum = 2.00, step = 0.01 },
        minimumDistanceDelta = { minimum = -2.00, maximum = 2.00, step = 0.01 },
        yawOffsetDelta = { minimum = -math.pi, maximum = math.pi, step = 0.01 },
    }
    createBodyCameraTuningSlider(1, "verticalOffsetDelta", "Vertical 高度", bodyLimits.verticalOffsetDelta)
    createBodyCameraTuningSlider(2, "horizontalOffsetDelta", "Horizontal 横移", bodyLimits.horizontalOffsetDelta)
    createBodyCameraTuningSlider(3, "distanceScaleMultiplier", "Distance 倍率", bodyLimits.distanceScaleMultiplier)
    createBodyCameraTuningSlider(4, "minimumDistanceDelta", "Minimum 最小", bodyLimits.minimumDistanceDelta)
    createBodyCameraTuningSlider(5, "yawOffsetDelta", "Yaw 环绕", bodyLimits.yawOffsetDelta)

    local function getTuningPose(record)
        return resolveM2CameraScopePose(record, cameraTuningPanel.scScope or "weaponFamily")
    end

    applyCameraTuning = function(record)
        if not record then return end
        for _, itemModel in ipairs(page.scItemModels) do
            local objectModel = itemModel.scObjectModel
            if itemModel.scRecord and itemModel.scRenderKind == "STANDALONE"
                and objectModel and isM2CameraTunableRecord(itemModel.scRecord) then
                applyStandaloneItemView(objectModel)
                queueStandaloneItemTransform(objectModel)
            end
        end
    end

    applyBodyCameraTuning = function(profile)
        if not profile then return end
        for _, itemModel in ipairs(page.scItemModels) do
            local visibleProfile = itemModel.scRecord
                and getCharacterCameraProfileForSlot(itemModel.scRecord.slot) or nil
            if itemModel.scRecord and itemModel.scRenderKind == "BODY"
                and visibleProfile and visibleProfile.profileKey == profile.profileKey then
                -- Re-enter the existing SetUnit/TryOn generation state machine.
                -- It chooses the profile sentinel, replays the complete body
                -- transaction after asynchronous rebuild, and keeps all other
                -- slot/race profiles untouched.
                queueItemModelView(itemModel, true)
            end
        end
    end

    local function navigateCameraTuning(step, onlyUncalibrated)
        if not SC.db or not cameraTuningPanel.scRecord then return false end
        local records = itemDataProvider:QueryAllItems()
        if #records == 0 then return false end
        local currentIndex = 1
        for index, record in ipairs(records) do
            if record.id == cameraTuningPanel.scRecord.id then
                currentIndex = index
                break
            end
        end
        for offset = 1, #records do
            local index = ((currentIndex - 1 + step * offset) % #records) + 1
            local candidate = records[index]
            local bodyMode = cameraTuningPanel.scMode == "body"
            local candidateProfile = bodyMode and getCharacterCameraProfileForSlot(candidate.slot) or nil
            local source = nil
            if not bodyMode then
                local _, resolvedSource = resolveM2CameraPose(candidate)
                source = resolvedSource
            end
            local candidateIsTunable = bodyMode
                and isBodyCameraTunableRecord(candidate)
                or (not bodyMode and isM2CameraTunableRecord(candidate))
            local uncalibrated = bodyMode
                and candidateProfile and not getBodyCameraDelta(candidateProfile)
                or (not bodyMode and source == "auto")
            if candidateIsTunable and (not onlyUncalibrated or uncalibrated) then
                page.scItemSelectedId = candidate.id
                local itemPageSize = page.scItemPageSize or ITEM_PAGE_SIZE
                page.scItemPage = math.floor((index - 1) / itemPageSize) + 1
                page:Refresh()
                return true
            end
        end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前筛选中没有符合条件的镜头条目。")
        end
        return false
    end

    local function formatCameraTuningExportRecord(record, scope, tuningKey, pose)
        if not record or not scope or not tuningKey or not SC.M2Camera
            or not SC.M2Camera.FormatTuningExportRecord then
            return nil
        end
        return SC.M2Camera.FormatTuningExportRecord({
            scope = scope,
            key = tuningKey,
            appearanceId = record.id,
            sourceItemId = record.itemId,
            nativeDisplayId = record.nativeDisplayId,
            syntheticDisplayId = record.syntheticDisplayId,
            modelSignature = record.modelSignature,
            weaponFamily = getWeaponFamilyCameraKey(record),
            weaponType = record.weaponType,
            slot = record.slot,
            metadataVersion = (SC.GeneratedCatalog or {}).metadataVersion,
            assetPackVersion = (SC.GeneratedCatalog or {}).assetPackVersion,
            appearancePresentationHash = (SC.GeneratedCatalog or {}).appearancePresentationHash,
        }, pose)
    end

    local function buildCameraTuningExport(records)
        if not SC.M2Camera or not SC.M2Camera.FormatTuningExportHeader then return "" end
        local generated = SC.GeneratedCatalog or {}
        local lines = {
            SC.M2Camera.FormatTuningExportHeader(
                generated.metadataVersion or "",
                generated.assetPackVersion or "",
                generated.appearancePresentationHash or ""
            ),
        }
        for _, entry in ipairs(records or {}) do
            local line = formatCameraTuningExportRecord(entry.record, entry.scope, entry.key, entry.pose)
            if line then table.insert(lines, line) end
        end
        return table.concat(lines, "\n")
    end

    local function formatBodyCameraTuningExportRecord(profile, delta)
        if not profile or not SC.M2Camera or not SC.M2Camera.FormatBodyTuningExportRecord then
            return nil
        end
        local generated = SC.GeneratedCatalog or {}
        return SC.M2Camera.FormatBodyTuningExportRecord({
            profileKey = profile.profileKey,
            sentinel = profile.sentinel,
            raceToken = profile.raceToken,
            clientAssetProfile = profile.cameraProfile,
            sex = profile.sex,
            slot = profile.slot,
            profileVersion = profile.profileVersion,
            profileHash = profile.profileHash,
            metadataVersion = generated.metadataVersion,
            assetPackVersion = generated.assetPackVersion,
        }, delta)
    end

    local function buildBodyCameraTuningExport(records)
        local first = records and records[1]
        if not first or not first.profile or not SC.M2Camera
            or not SC.M2Camera.FormatBodyTuningExportHeader then
            return ""
        end
        local generated = SC.GeneratedCatalog or {}
        local lines = {
            SC.M2Camera.FormatBodyTuningExportHeader(
                generated.metadataVersion or "",
                generated.assetPackVersion or "",
                first.profile
            ),
        }
        for _, entry in ipairs(records) do
            local line = formatBodyCameraTuningExportRecord(entry.profile, entry.delta)
            if line then table.insert(lines, line) end
        end
        return table.concat(lines, "\n")
    end

    updateCameraTuningExport = function()
        if cameraTuningPanel.scMode == "body" then
            local profile = cameraTuningPanel.scBodyProfile
            local delta = cameraTuningPanel.scBodyDelta
            if not profile or not delta then
                tuningExport:SetText("")
                return
            end
            tuningExport:SetText(buildBodyCameraTuningExport({ { profile = profile, delta = delta } }))
            return
        end
        if not cameraTuningPanel.scRecord or not cameraTuningPanel.scPose
            or not SC.M2Camera or not SC.M2Camera.FormatTuningExportHeader
            or not SC.M2Camera.FormatTuningExportRecord then
            tuningExport:SetText("")
            return
        end
        local record = cameraTuningPanel.scRecord
        local scope = cameraTuningPanel.scScope or "weaponFamily"
        local tuningKey = getCameraTuningScopeKey(record, scope)
        if not tuningKey then
            tuningExport:SetText("")
            return
        end
        tuningExport:SetText(buildCameraTuningExport({ {
            record = record,
            scope = scope,
            key = tuningKey,
            pose = cameraTuningPanel.scPose,
        } }))
    end

    local function setCameraTuningControlsEnabled(enabled)
        local function setWidgetEnabled(widget, value)
            if not widget then return end
            -- WotLK Slider/EditBox widgets inherit EnableMouse but do not all
            -- expose the Button-only Enable/Disable methods. Keep the panel
            -- usable on the stock 3.3.5 UI while still visually disabling
            -- widgets that do support the richer button API.
            if value then
                if widget.Enable then widget:Enable() end
                if widget.EnableMouse then widget:EnableMouse(true) end
            else
                if widget.Disable then widget:Disable() end
                if widget.EnableMouse then widget:EnableMouse(false) end
            end
        end
        local bodyMode = cameraTuningPanel.scMode == "body"
        for _, control in ipairs(cameraTuningPanel.scControls) do
            if control.row then
                if bodyMode then control.row:Hide() else control.row:Show() end
            end
            setWidgetEnabled(control.slider, enabled and not bodyMode)
            setWidgetEnabled(control.value, enabled and not bodyMode)
            for _, button in ipairs(control.buttons) do setWidgetEnabled(button, enabled and not bodyMode) end
        end
        for _, control in ipairs(cameraTuningPanel.scBodyControls) do
            if control.row then
                if bodyMode then control.row:Show() else control.row:Hide() end
            end
            setWidgetEnabled(control.slider, enabled and bodyMode)
            setWidgetEnabled(control.value, enabled and bodyMode)
            for _, button in ipairs(control.buttons) do setWidgetEnabled(button, enabled and bodyMode) end
        end
        setWidgetEnabled(tuningPrevious, enabled)
        setWidgetEnabled(tuningNext, enabled)
        setWidgetEnabled(tuningPreviousUncalibrated, enabled)
        setWidgetEnabled(tuningNextUncalibrated, enabled)
        setWidgetEnabled(tuningReset, enabled)
        setWidgetEnabled(tuningCopy, enabled)
        setWidgetEnabled(tuningBatch, enabled)
        setWidgetEnabled(tuningCopyAll, enabled)
        setWidgetEnabled(tuningDiscard, enabled)
        if bodyMode then tuningScopeDropdown:Hide() else tuningScopeDropdown:Show() end
        tuningScopeDropdown:EnableMouse(enabled and not bodyMode)
    end

    function page:SyncCameraTuningPanel(record)
        if not cameraTuningPanel.scRequested then
            return
        end
        if isBodyCameraTunableRecord(record) then
            local profile = getCharacterCameraProfileForSlot(record.slot)
            if not profile then return end
            cameraTuningPanel.scMode = "body"
            cameraTuningPanel.scRecord = record
            cameraTuningPanel.scBodyProfile = profile
            cameraTuningPanel.scBodyDelta = getBodyCameraDelta(profile)
                or SC.M2Camera.NormalizeBodyDelta({})
            local bodyEnabled, bodyReason = SC.M2Camera.GetBodyProfileCapability(profile)
            cameraTuningPanel.scSyncing = true
            cameraTuningPanel:Show()
            setCameraTuningControlsEnabled(bodyEnabled)
            for _, control in ipairs(cameraTuningPanel.scBodyControls) do
                local value = cameraTuningPanel.scBodyDelta[control.key]
                control.slider:SetValue(value)
                control.value:SetText(string.format("%.2f", value))
            end
            cameraTuningPanel.scSyncing = nil
            tuningTitle:SetText("角色 Profile 相机")
            tuningRecord:SetText("角色相机：" .. (record.name or ("外观 " .. tostring(record.id))))
            local compactHash = string.sub(tostring(profile.profileHash or ""), 1, 16)
            if #(profile.profileHash or "") > #compactHash then compactHash = compactHash .. "..." end
            tuningMetadata:SetText(string.format(
                "%s · sentinel 0x%04X · %s\n%s · profile v%s · %s",
                tostring(profile.profileKey or "未知 profile"),
                tonumber(profile.sentinel) or 0,
                tostring(profile.cameraProfile or "未知资源"),
                tostring(profile.sex or "未知性别"),
                tostring(profile.profileVersion or "?"),
                compactHash
            ))
            if bodyEnabled then
                tuningHint:SetText(next(cameraTuningPanel.scBodySessionBefore)
                    and "当前 profile 有未导出差量；同 profile 的可见护甲会同步更新。"
                    or "调节作用于当前种族/性别/部位 profile，不是单件护甲。导出仅生成待审核候选。")
            else
                tuningHint:SetText("只读：需要匹配的 SoloCam v7 与 profile capability（" .. tostring(bodyReason) .. "）。普通预览保持安全回退。")
            end
            updateCameraTuningExport()
            if cameraTuningButton then cameraTuningButton:SetText("关闭工作台") end
            return
        end
        cameraTuningPanel.scMode = "weapon"
        cameraTuningPanel.scBodyProfile = nil
        cameraTuningPanel.scBodyDelta = nil
        tuningTitle:SetText("武器 M2 相机构图")
        if cameraTuningPanel.scScope == "model" and not getModelCameraKey(record) then
            cameraTuningPanel.scScope = "weaponFamily"
        end
        if not isM2CameraTunableRecord(record) then
            cameraTuningPanel.scRecord = record
            cameraTuningPanel.scPose = nil
            setCameraTuningControlsEnabled(false)
            tuningRecord:SetText(record and (record.name or ("外观 " .. tostring(record.id))) or "请选择一件武器")
            local reason = record and (
                record.presentationReasonCode
                or (record.renderMode == "UNAVAILABLE" and "NO_VERIFIED_STANDALONE_PRESENTATION")
                or record.presentationStatus
            ) or "NO_SELECTION"
            tuningMetadata:SetText("此条目没有可调的 verified standalone 模型。\n原因：" .. tostring(reason or "UNAVAILABLE"))
            tuningHint:SetText("不可用武器只显示资源失败原因；不会把空模型或角色占位当作可调对象。")
            tuningExport:SetText("")
            cameraTuningPanel:Show()
            if cameraTuningButton then cameraTuningButton:SetText("关闭工作台") end
            return
        end
        local pose, editedSource = getTuningPose(record)
        if not pose then return end
        local _, activeSource = resolveM2CameraPose(record)
        cameraTuningPanel.scRecord = record
        cameraTuningPanel.scPose = pose
        cameraTuningPanel.scScope = cameraTuningPanel.scScope or "weaponFamily"
        -- Enabling a stock 3.3.5 slider may emit its current (zero) value.
        -- Enter sync mode before enabling controls, otherwise that framework
        -- event can overwrite the resolved autoCamera pose.
        cameraTuningPanel.scSyncing = true
        -- Show the parent before applying values.  FrameXML children receive
        -- their default-value callbacks as their hidden parent is shown; doing
        -- this first lets the explicit pose writes below win deterministically.
        cameraTuningPanel:Show()
        setCameraTuningControlsEnabled(true)
        UIDropDownMenu_SetSelectedValue(tuningScopeDropdown, cameraTuningPanel.scScope)
        UIDropDownMenu_SetText(tuningScopeDropdown, cameraTuningScopeLabel(cameraTuningPanel.scScope))
        for _, control in ipairs(cameraTuningPanel.scControls) do
            local value = control.targetIndex and pose.target[control.targetIndex] or pose[control.key]
            control.slider:SetValue(value)
            updateTuningValueLabel(control, value)
        end
        cameraTuningPanel.scSyncing = nil
        tuningRecord:SetText("武器类型：" .. (record.weaponTypeLabel or "未分类") .. " · " .. (record.name or ("外观 " .. tostring(record.id))))
        local modelSignature = tostring(record.modelSignature or "未提供")
        local compactModelSignature = string.sub(modelSignature, 1, 16)
        if #modelSignature > #compactModelSignature then compactModelSignature = compactModelSignature .. "..." end
        tuningMetadata:SetText(string.format(
            "外观 %s · Item %s · display %s/%s\nM2 %s · %s · %s",
            tostring(record.id or "?"),
            tostring(record.itemId or "?"),
            tostring(record.nativeDisplayId or "?"),
            tostring(record.syntheticDisplayId or "?"),
            compactModelSignature,
            tostring(getWeaponFamilyCameraKey(record) or "未分类"),
            activeSource == "appearance" and "此外观" or activeSource == "model" and "此模型"
                or activeSource == "generatedModel" and "已审核模型基线"
                or activeSource == "weaponFamily" and "武器类别" or "自动基线"
        ))
        tuningHint:SetText(cameraTuningPanel.scCurrentDirty
            and "当前会话有未导出修改；可加入批次、复制或明确放弃。"
            or "编辑值来源：" .. cameraTuningSourceLabel(editedSource) .. "。数值会立即预览；导出仅生成待审核候选。")
        updateCameraTuningExport()
        if cameraTuningButton then cameraTuningButton:SetText("关闭工作台") end
    end

    function page:ToggleCameraTuning()
        cameraTuningPanel.scRequested = not cameraTuningPanel.scRequested
        self:UpdateCameraWorkbenchLayout()
        if not cameraTuningPanel.scRequested then
            cameraTuningPanel:Hide()
            cameraTuningButton:SetText("镜头工作台")
            self:Refresh()
            return
        end
        self:Refresh()
    end

    tuningClose:SetScript("OnClick", function() page:ToggleCameraTuning() end)

    local function selectCameraTuningExport(text, message)
        tuningExport:SetText(text or "")
        tuningExport:SetFocus()
        tuningExport:HighlightText()
        if DEFAULT_CHAT_FRAME and message then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：" .. message)
        end
    end

    tuningCopy:SetScript("OnClick", function()
        updateCameraTuningExport()
        selectCameraTuningExport(tuningExport:GetText(), "当前镜头 JSONL 记录已选中，可按 Ctrl+C 复制。")
    end)

    tuningBatch:SetScript("OnClick", function()
        if cameraTuningPanel.scMode == "body" then
            local profile = cameraTuningPanel.scBodyProfile
            local delta = profile and getBodyCameraDelta(profile) or nil
            if not profile or not delta then
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前 profile 没有差量 override，无需加入批次。")
                end
                return
            end
            cameraTuningPanel.scBodyBatch[profile.profileKey] = { profile = profile, delta = delta }
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：已加入角色 profile 导出批次。")
            end
            return
        end
        local record = cameraTuningPanel.scRecord
        local scope = cameraTuningPanel.scScope or "weaponFamily"
        local tuningKey = getCameraTuningScopeKey(record, scope)
        if not record or not tuningKey or not SC.CameraTuning or not SC.CameraTuning.Get then return end
        local pose = SC.CameraTuning.Get(scope, tuningKey)
        if not pose then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前范围没有差量 override，无需加入批次。")
            end
            return
        end
        local sessionKey = scope .. "\031" .. tuningKey
        cameraTuningPanel.scBatch[sessionKey] = {
            record = record,
            scope = scope,
            key = tuningKey,
            pose = pose,
        }
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：已加入镜头导出批次。")
        end
    end)

    tuningCopyAll:SetScript("OnClick", function()
        if cameraTuningPanel.scMode == "body" then
            local batchKeys = {}
            for batchKey in pairs(cameraTuningPanel.scBodyBatch) do table.insert(batchKeys, batchKey) end
            table.sort(batchKeys)
            if #batchKeys == 0 then
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：本次角色 profile 批次为空。先修改并点击“加入批次”。")
                end
                return
            end
            local records = {}
            for _, batchKey in ipairs(batchKeys) do
                local entry = cameraTuningPanel.scBodyBatch[batchKey]
                if entry then table.insert(records, entry) end
            end
            selectCameraTuningExport(buildBodyCameraTuningExport(records), "本次角色 profile JSONL 已选中，可按 Ctrl+C 复制。")
            return
        end
        local batchKeys = {}
        for batchKey in pairs(cameraTuningPanel.scBatch) do table.insert(batchKeys, batchKey) end
        table.sort(batchKeys)
        if #batchKeys == 0 then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：本次批次为空。先修改并点击“加入批次”。")
            end
            return
        end
        local records = {}
        for _, batchKey in ipairs(batchKeys) do
            local entry = cameraTuningPanel.scBatch[batchKey]
            if entry then table.insert(records, entry) end
        end
        selectCameraTuningExport(buildCameraTuningExport(records), "本次批量镜头 JSONL 已选中，可按 Ctrl+C 复制。")
    end)

    local function discardUnexportedCameraTuning()
        if cameraTuningPanel.scMode == "body" then
            for profileKey, previous in pairs(cameraTuningPanel.scBodySessionBefore) do
                if SC.BodyCameraTuning then
                    if previous == false then
                        if SC.BodyCameraTuning.Reset then SC.BodyCameraTuning.Reset(profileKey) end
                    elseif SC.BodyCameraTuning.Set then
                        SC.BodyCameraTuning.Set(profileKey, previous)
                    end
                end
            end
            cameraTuningPanel.scBodySessionBefore = {}
            cameraTuningPanel.scBodyBatch = {}
            cameraTuningPanel.scCurrentDirty = nil
            applyBodyCameraTuning(cameraTuningPanel.scBodyProfile)
            page:SyncCameraTuningPanel(cameraTuningPanel.scRecord)
            return
        end
        for sessionKey, previous in pairs(cameraTuningPanel.scSessionBefore) do
            local scope, tuningKey = string.match(sessionKey, "^(.-)\031(.*)$")
            if scope and tuningKey and SC.CameraTuning then
                if previous == false then
                    if SC.CameraTuning.Reset then SC.CameraTuning.Reset(scope, tuningKey) end
                elseif SC.CameraTuning.Set then
                    SC.CameraTuning.Set(scope, tuningKey, previous)
                end
            end
        end
        cameraTuningPanel.scSessionBefore = {}
        cameraTuningPanel.scBatch = {}
        cameraTuningPanel.scCurrentDirty = nil
        applyCameraTuning(cameraTuningPanel.scRecord)
        page:SyncCameraTuningPanel(cameraTuningPanel.scRecord)
    end
    cameraTuningPanel.scDiscardUnexported = discardUnexportedCameraTuning

    tuningDiscard:SetScript("OnClick", function()
        local pending = cameraTuningPanel.scMode == "body"
            and cameraTuningPanel.scBodySessionBefore or cameraTuningPanel.scSessionBefore
        if not next(pending) then return end
        if StaticPopupDialogs then
            if not StaticPopupDialogs.SOLOCOLLECTIONS_CAMERA_DISCARD_V2 then
                StaticPopupDialogs.SOLOCOLLECTIONS_CAMERA_DISCARD_V2 = {
                    text = "放弃本次尚未导出的镜头修改？此操作会恢复打开工作台前的覆盖值。",
                    button1 = "放弃修改",
                    button2 = CANCEL,
                    OnAccept = function(_, data)
                        if data and data.scDiscardUnexported then data.scDiscardUnexported() end
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
            end
            StaticPopup_Show("SOLOCOLLECTIONS_CAMERA_DISCARD_V2", nil, nil, cameraTuningPanel)
        else
            discardUnexportedCameraTuning()
        end
    end)
    tuningReset:SetScript("OnClick", function()
        if cameraTuningPanel.scMode == "body" then
            local profile = cameraTuningPanel.scBodyProfile
            if not profile or not SC.BodyCameraTuning or not SC.BodyCameraTuning.Reset then return end
            SC.BodyCameraTuning.Reset(profile.profileKey)
            applyBodyCameraTuning(profile)
            page:SyncCameraTuningPanel(cameraTuningPanel.scRecord)
            return
        end
        local record = cameraTuningPanel.scRecord
        if not record or not SC.CameraTuning or not SC.CameraTuning.Reset then return end
        local scope = cameraTuningPanel.scScope or "weaponFamily"
        local tuningKey = getCameraTuningScopeKey(record, scope)
        if tuningKey then SC.CameraTuning.Reset(scope, tuningKey) end
        applyCameraTuning(record)
        page:SyncCameraTuningPanel(record)
    end)
    tuningPrevious:SetScript("OnClick", function() navigateCameraTuning(-1, false) end)
    tuningNext:SetScript("OnClick", function() navigateCameraTuning(1, false) end)
    tuningPreviousUncalibrated:SetScript("OnClick", function() navigateCameraTuning(-1, true) end)
    tuningNextUncalibrated:SetScript("OnClick", function() navigateCameraTuning(1, true) end)

    cameraTuningButton = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    cameraTuningButton:SetWidth(92)
    cameraTuningButton:SetHeight(22)
    cameraTuningButton:SetPoint("RIGHT", weaponDropdown, "LEFT", -4, 0)
    cameraTuningButton:SetText("镜头工作台")
    cameraTuningButton:SetScript("OnClick", function() page:ToggleCameraTuning() end)
--]=]

    local function scrollItemPage(delta)
        if not delta or delta == 0 then return end
        local totalPages = page.scItemTotalPages or 1
        if delta > 0 then
            page.scItemPage = math.max(1, (page.scItemPage or 1) - 1)
        else
            page.scItemPage = math.min(totalPages, (page.scItemPage or 1) + 1)
        end
        page:Refresh()
    end

    itemsPanel:SetScript("OnMouseWheel", function(_, delta) scrollItemPage(delta) end)

    page.scItemModels = EzItems:CreateCardPool(itemsPanel, {
        onClick = function(itemModel, button)
            if not itemModel.scRecord then return end
            if button == "RightButton" then
                itemDataProvider:ToggleFavorite(itemModel.scRecord.collectionId)
                page:Refresh()
            elseif IsShiftKeyDown() then
                itemDataProvider:ApplyAppearance(itemModel.scRecord, showAppearanceActionResult)
            else
                selectItem(itemModel.scRecord)
            end
        end,
        onEnter = function(owner, itemModel) showItemTooltip(owner, itemModel.scRecord) end,
        onLeave = function() GameTooltip:Hide() end,
        onMouseWheel = scrollItemPage,
    })
    for _, itemModel in ipairs(page.scItemModels) do
        ItemCardRenderer:Attach(itemModel, itemModel.scObjectModel)
    end

    local function getMaxSetOffset()
        local count = page.scSetRecordCount or 0
        if count <= 0 then return 0 end
        return math.max(0, math.floor((count - 1) / VISIBLE_SET_ROWS) * VISIBLE_SET_ROWS)
    end

    setSetOffset = function(value, suppressRefresh)
        local target = math.max(0, math.min(math.floor(tonumber(value) or 0), getMaxSetOffset()))
        local changed = target ~= (page.scSetOffset or 0)
        page.scSetOffset = target
        page.scSetPage = math.floor(target / VISIBLE_SET_ROWS) + 1
        if changed and not suppressRefresh then
            page:Refresh()
        end
        return target
    end

    local function scrollSetList(delta)
        if not delta or delta == 0 then return end
        setSetOffset((page.scSetOffset or 0) + (delta > 0 and -VISIBLE_SET_ROWS or VISIBLE_SET_ROWS))
    end

    local setScrollbar = CreateFrame("Slider", nil, setsPanel)
    setScrollbar:SetWidth(14)
    setScrollbar:SetPoint("TOPRIGHT", setsPanel, "TOPRIGHT", -1, -3)
    setScrollbar:SetPoint("BOTTOMRIGHT", setsPanel, "BOTTOMRIGHT", -1, 37)
    setScrollbar:SetOrientation("VERTICAL")
    setScrollbar:SetMinMaxValues(0, 0)
    setScrollbar:SetValueStep(1)
    setScrollbar:EnableMouseWheel(true)

    local setScrollbarTrack = setScrollbar:CreateTexture(nil, "BACKGROUND")
    setScrollbarTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
    setScrollbarTrack:SetPoint("TOPLEFT", setScrollbar, "TOPLEFT", 4, -1)
    setScrollbarTrack:SetPoint("BOTTOMRIGHT", setScrollbar, "BOTTOMRIGHT", -4, 1)
    setScrollbarTrack:SetVertexColor(0.025, 0.027, 0.030, 0.76)

    local setScrollbarThumb = setScrollbar:CreateTexture(nil, "OVERLAY")
    setScrollbarThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    setScrollbarThumb:SetWidth(16)
    setScrollbarThumb:SetHeight(24)
    setScrollbar:SetThumbTexture(setScrollbarThumb)
    local setScrollbarBorder = UI.CreateThinCardBorder(setScrollbar, 1)
    setScrollbarBorder:SetBorderColor(0.33, 0.34, 0.35, 0.62)
    setScrollbar:SetScript("OnValueChanged", function(self, value)
        if page.scSyncingSetScrollbar then return end
        setSetOffset(value)
    end)
    setScrollbar:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)
    setScrollbar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("套装列表", 1.00, 0.82, 0.18)
        GameTooltip:AddLine("拖动滚动条或使用鼠标滚轮浏览。", 0.82, 0.78, 0.70, true)
        GameTooltip:Show()
    end)
    setScrollbar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    setScrollbar:Hide()

    setsPanel:EnableMouseWheel(true)
    setsPanel:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)

    for index = 1, VISIBLE_SET_ROWS do
        local column = (index - 1) % EZ_LAYOUT.setColumns
        local row = math.floor((index - 1) / EZ_LAYOUT.setColumns)
        local card = CreateFrame("Frame", nil, setsPanel)
        card:SetWidth(EZ_LAYOUT.setWidth)
        card:SetHeight(EZ_LAYOUT.setHeight)
        card:SetPoint(
            "TOPLEFT",
            setsPanel,
            "TOPLEFT",
            EZ_LAYOUT.setStartX + column * (EZ_LAYOUT.setWidth + EZ_LAYOUT.setGapX),
            -EZ_LAYOUT.setStartY - row * (EZ_LAYOUT.setHeight + EZ_LAYOUT.setGapY)
        )

        local cardBackground = card:CreateTexture(nil, "BACKGROUND")
        cardBackground:SetAllPoints(card)
        cardBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        cardBackground:SetVertexColor(0, 0, 0, 1)

        local setModel = CreateFrame("DressUpModel", nil, card)
        setModel:SetAllPoints(card)
        setModel:EnableMouse(false)
        local cardPresenter = SC.ModelProvider.Create("DRESSUP", setModel, {
            panelCheck = function()
                return card:IsShown() and page:IsShown() and SC.db and SC.db.wardrobeTab == "SETS"
            end,
        })

        local hit = CreateFrame("Button", nil, card)
        hit:SetAllPoints(card)
        hit:SetFrameLevel(setModel:GetFrameLevel() + 2)
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hit:EnableMouseWheel(true)
        local border, selected, favorite, hover = UI.EzCollections:CreateWardrobeSetChrome(hit)

        function card:SetRecord(record)
            self.scGeneration = (self.scGeneration or 0) + 1
            self.scReadyGeneration = nil
            self.scRecord = record
            cardPresenter:Clear("SET_CARD_REPLACED")
            if not record then
                selected:Hide()
                favorite:Hide()
                setModel:ClearModel()
                self:Hide()
                return
            end

            local itemStrings = {}
            for _, previewItem in ipairs(getSelectedVariantPreviewItems(record)) do
                itemStrings[#itemStrings + 1] = resolveTryOnItem(previewItem.previewSourceItemId)
            end
            self:Show()
            setModel:Show()
            local expectedGeneration = self.scGeneration
            local expectedRecordId = record.id
            cardPresenter:Present({
                unit = "player",
                undress = true,
                settleTicks = 2,
                items = itemStrings,
                onReady = function()
                    if card.scGeneration == expectedGeneration and
                        card.scRecord and card.scRecord.id == expectedRecordId then
                        card.scReadyGeneration = expectedGeneration
                    end
                end,
            })
            border:SetCollected(record.collected)
            setModel:SetAlpha(record.collected and 1 or 0.48)
            if record.favorite then favorite:Show() else favorite:Hide() end
        end

        function card:SetSelected(value)
            self.scSelected = value and true or false
            if self.scSelected then selected:Show() else selected:Hide() end
        end

        hit:SetScript("OnClick", function(_, button)
            local record = card.scRecord
            if not record then return end
            if button == "RightButton" then
                Catalog.ToggleDemoFavorite("SETS", record.id)
                page:Refresh()
            elseif IsShiftKeyDown() then
                if not record.collected then
                    showSetActionResult(false, "NOT_OWNED")
                elseif not SC.Bridge or not SC.Bridge.ApplySet then
                    showSetActionResult(false, "BRIDGE_UNAVAILABLE")
                else
                    local variant = record.selectedVariant
                    SC.Bridge.ApplySet(record.id, variant and variant.variantOrdinal or nil, showSetActionResult)
                end
            else
                page.scSetSelectedId = record.id
                previewSet(record)
                for _, setCard in ipairs(page.scSetCards) do
                    setCard:SetSelected(setCard.scRecord and setCard.scRecord.id == page.scSetSelectedId)
                end
            end
        end)
        hit:SetScript("OnEnter", function(self)
            local record = card.scRecord
            if not record then return end
            local owned = tonumber(record.collectedCount) or 0
            local required = tonumber(record.requiredCount) or #(record.itemIds or {})
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(record.name or "未知套装", 1, 0.82, 0.18)
            GameTooltip:AddLine("职业：" .. setClassLabel(record), 0.82, 0.78, 0.70)
            GameTooltip:AddLine("收集进度：" .. owned .. " / " .. required, 0.45, 0.90, 0.34)
            GameTooltip:AddLine("左键选择 · Shift+左键应用 · 右键偏好", 0.78, 0.74, 0.64)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hit:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)

        card.scModel = setModel
        card.scPresenter = cardPresenter
        card.scHitFrame = hit
        card.scBorder = border
        card.scSelected = selected
        card.scFavorite = favorite
        card.scHover = hover
        SC.WardrobeUI.Layout:StyleCard(card, cardBackground, border)
        card:Hide()
        page.scSetCards[index] = card
    end

    local itemControls = UI.CreatePageControls(itemsPanel, function()
        page.scItemPage = math.max(1, page.scItemPage - 1)
        page:Refresh()
    end, function()
        page.scItemPage = math.min(page.scItemTotalPages or 1, page.scItemPage + 1)
        page:Refresh()
    end)
    itemControls:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 22, 38)

    local setControls = UI.CreatePageControls(setsPanel, function()
        setSetOffset((page.scSetOffset or 0) - VISIBLE_SET_ROWS)
    end, function()
        setSetOffset((page.scSetOffset or 0) + VISIBLE_SET_ROWS)
    end)
    setControls:SetPoint("BOTTOM", setsPanel, "BOTTOM", 0, 5)
    setControls:SetFrameLevel(preview:GetFrameLevel() + 1)

    local itemEmpty = UI.CreateEmptyState(itemsPanel, "没有符合条件的外观")
    itemEmpty:SetPoint("CENTER", itemsPanel, "CENTER", 0, 20)
    itemEmpty:Hide()
    local setEmpty = UI.CreateEmptyState(setsPanel, "没有符合条件的套装")
    setEmpty:SetPoint("CENTER", setsPanel, "CENTER", 0, 20)
    setEmpty:Hide()

    function page:ClearSelection()
        cancelSetPreview()
        self.scItemSelectedId = nil
        self.scSetSelectedId = nil
        self.scSetSelectedRecord = nil
        applySet:Disable()
        for _, itemModel in ipairs(self.scItemModels) do
            itemModel.scSelected:Hide()
        end
        for _, row in ipairs(self.scSetRows) do row:SetSelected(false) end
        for _, card in ipairs(self.scSetCards) do card:SetSelected(false) end
        name:SetText("")
        detail:SetText("")
        setProgress:Hide()
        pieces:Hide()
        clearDragState()
        model:ClearModel()
        GameTooltip:Hide()
    end

    function page:SyncDedicatedFilters()
        if not SC.db or not SC.db.filters then return end
        local filters = SC.db.filters

        -- On the first set-page visit, mirror Retail by starting on the
        -- character's own class. Afterwards an explicit "全部职业" choice is
        -- respected for the rest of the UI session.
        if SC.db.wardrobeTab == "SETS" and not self.scDefaultSetClassApplied then
            self.scDefaultSetClassApplied = true
            local playerClass = getPlayerClassToken()
            if hasFilterValue(CLASS_FILTERS, playerClass) then
                filters.classToken = playerClass
                setSetOffset(0, true)
                self.scSetSelectedId = nil
            end
        end

        local storedArmorType, effectiveArmorType = itemDataProvider:GetArmorState()
        if filters.armorType ~= storedArmorType then filters.armorType = storedArmorType end
        if filters.slot == "ALL" or not page.scSlotButtons[filters.slot] then
            filters.slot = "HEAD"
        end

        UIDropDownMenu_SetSelectedValue(armorDropdown, effectiveArmorType)
        UIDropDownMenu_SetText(armorDropdown, filterLabel(ARMOR_TYPE_FILTERS, effectiveArmorType))
        UIDropDownMenu_SetSelectedValue(classDropdown, filters.classToken)
        UIDropDownMenu_SetText(classDropdown, filterLabel(CLASS_FILTERS, filters.classToken))

        for slotKey, button in pairs(page.scSlotButtons) do
            if slotKey == filters.slot then
                button.scSelected:Show()
            else
                button.scSelected:Hide()
            end
        end

        if SC.db.wardrobeTab == "ITEMS" then
            armorDropdown:Show()
            classDropdown:Hide()
            slotsFrame:Show()
            if STANDALONE_ITEM_SLOTS[filters.slot] then
                ensureWeaponTypeForSlot(filters, filters.slot)
                UIDropDownMenu_SetSelectedValue(weaponDropdown, filters.weaponType)
                UIDropDownMenu_SetText(weaponDropdown, filterLabel(getAvailableWeaponFilters(filters.slot), filters.weaponType))
                weaponDropdown:Show()
            else
                weaponDropdown:Hide()
            end
        else
            armorDropdown:Hide()
            classDropdown:Show()
            slotsFrame:Hide()
            weaponDropdown:Hide()
        end
    end

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scWardrobeFilterDropDown or not SC.db or SC.db.mainTab ~= "WARDROBE" then return end
        local filters = SC.db.filters
        local dropDown = frame.scWardrobeFilterDropDown
        if frame.scFilterPopup then frame.scFilterPopup:Hide() end
        if dropDown.scSoloCollectionsInitialized then return end

        local function setFilter(key, value)
            filters[key] = value and true or false
            self.scItemPage = 1
            setSetOffset(0, true)
            self:Refresh()
        end

        UIDropDownMenu_Initialize(dropDown, function(_, level)
            if level ~= 1 then return end
            local options = {
                { label = "已收集", key = "collected" },
                { label = "未收集", key = "uncollected" },
                { label = "仅显示偏好", key = "favorites" },
            }
            for _, option in ipairs(options) do
                local optionKey = option.key
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.label
                info.keepShownOnClick = true
                info.isNotRadio = true
                info.checked = function() return filters[optionKey] and true or false end
                info.func = function(_, _, _, checked) setFilter(optionKey, checked) end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        dropDown.scSoloCollectionsInitialized = true
    end

    local function refreshItems()
        EzItems:ApplyJournalChrome()
        cancelSetPreview()
        page.scRuntimeAuditActive = nil
        page.scItemGeneration = (page.scItemGeneration or 0) + 1
        local pageGeneration = page.scItemGeneration
        itemsPanel:Show()
        setsPanel:Hide()
        preview:Hide()
        local itemPageSize = page.scItemPageSize or ITEM_PAGE_SIZE
        local records, currentPage, totalPages = wardrobeFilters:QueryItems(page.scItemPage, itemPageSize)
        page.scItemPage = currentPage
        page.scItemTotalPages = totalPages
        itemControls:SetPage(currentPage, totalPages)
        local selected
        for index, itemModel in ipairs(page.scItemModels) do
            local record = records[index]
            applyItemModelRecord(itemModel, record, pageGeneration)
            EzItems:UpdateCardState(itemModel, page.scItemSelectedId)
            if record and record.id == page.scItemSelectedId then selected = record end
        end
        local collected, total = itemDataProvider:GetProgress()
        page.scItemCollected = collected
        page.scItemTotal = total
        page.scItemRevision = itemDataProvider:GetRevision()
        if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(collected, total) end
        if #records == 0 then
            UI.ShowEmptyState(itemEmpty, page, "没有符合条件的外观", "调整搜索、护甲类型、部位或武器类型后再试。")
        else
            UI.HideEmptyState(itemEmpty)
            selectItem(selected or records[1])
        end
    end

    -- The temporary runtime-audit AddOn uses this narrow entry point to drive
    -- the production 18-card pool without changing filters, collection state,
    -- or any persisted UI setting.  It deliberately delegates to the same
    -- applyItemModelRecord path as refreshItems, so the audit observes the same
    -- DressUpModel/preview-Creature route rather than a second renderer.
    function page:LoadRuntimeAuditAppearanceRecords(records)
        records = records or {}
        if #records > #self.scItemModels then
            return nil, "AUDIT_RECORD_COUNT_EXCEEDS_CARD_POOL"
        end

        cancelSetPreview()
        self.scRuntimeAuditActive = true
        self.scItemGeneration = (self.scItemGeneration or 0) + 1
        local pageGeneration = self.scItemGeneration
        self.scItemSelectedId = nil
        self.scItemPage = 1
        self.scItemTotalPages = 1
        itemsPanel:Show()
        setsPanel:Hide()
        preview:Hide()
        itemControls:SetPage(1, 1)

        local visible = 0
        for index, itemModel in ipairs(self.scItemModels) do
            local record = records[index]
            applyItemModelRecord(itemModel, record, pageGeneration)
            if record then
                visible = visible + 1
            end
            EzItems:UpdateCardState(itemModel, nil)
        end

        if visible == 0 then
            UI.ShowEmptyState(itemEmpty, page, "没有可审计的外观", "运行时审计未收到公开外观记录。")
        else
            UI.HideEmptyState(itemEmpty)
        end
        return pageGeneration, visible
    end

    local function refreshSets()
        itemsPanel:Hide()
        -- Release the pooled ez model lifecycle when the set page takes over.
        -- Returning to items will rebuild the correct player/weapon actor,
        -- redress the record, and then reapply its camera tuple.
        for _, itemModel in ipairs(page.scItemModels) do
            ItemCardRenderer:Clear(itemModel)
        end
        setsPanel:Show()
        preview:Show()
        local allRecords, setFilters = wardrobeFilters:QuerySets()
        page.scSetRecordCount = #allRecords
        local maxOffset = #allRecords > 0
            and math.floor((#allRecords - 1) / VISIBLE_SET_ROWS) * VISIBLE_SET_ROWS or 0
        setSetOffset(page.scSetOffset, true)

        local records = {}
        local firstIndex = page.scSetOffset + 1
        local lastIndex = math.min(#allRecords, firstIndex + VISIBLE_SET_ROWS - 1)
        for index = firstIndex, lastIndex do
            table.insert(records, allRecords[index])
        end

        local totalPages = math.max(1, math.ceil(#allRecords / VISIBLE_SET_ROWS))
        local currentPage = math.max(1, math.min(totalPages, math.ceil((page.scSetOffset + VISIBLE_SET_ROWS) / VISIBLE_SET_ROWS)))
        page.scSetPage = currentPage
        page.scSetTotalPages = totalPages
        setControls:SetPage(currentPage, totalPages)

        page.scSyncingSetScrollbar = true
        setScrollbar:SetMinMaxValues(0, maxOffset)
        setScrollbar:SetValue(page.scSetOffset)
        setScrollbar:SetAlpha(maxOffset > 0 and 1.00 or 0.28)
        page.scSyncingSetScrollbar = nil

        local selected
        for _, record in ipairs(records) do
            if record.id == page.scSetSelectedId then
                selected = record
                break
            end
        end
        for index, card in ipairs(page.scSetCards) do
            local record = records[index]
            card:SetRecord(record)
            card:SetSelected(record and record.id == page.scSetSelectedId)
        end
        local collected, total = Catalog.GetProgress("SETS", setFilters)
        if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(collected, total) end
        if #records == 0 then
            UI.ShowEmptyState(setEmpty, page, "没有符合条件的套装", "调整搜索或职业过滤后再试。")
        else
            UI.HideEmptyState(setEmpty)
            local record = selected or records[1] or allRecords[1]
            page.scSetSelectedId = record.id
            previewSet(record)
            for _, card in ipairs(page.scSetCards) do
                card:SetSelected(card.scRecord and card.scRecord.id == record.id)
            end
        end
    end

    function page:Refresh()
        if not SC.db then return end
        self.scRuntimeAuditActive = nil
        self:SyncDedicatedFilters()
        if SC.db.wardrobeTab == "ITEMS" then
            refreshItems()
        elseif SC.db.wardrobeTab == "SETS" then
            refreshSets()
        end
        self:SyncFilters()
    end

    function page:ApplyAppearanceCollectionChange(change)
        if not change or change.kind ~= "DELTA" or not change.collectionId then return false end
        if self.scRuntimeAuditActive then return true end
        if self:IsShown() and SC.db and SC.db.wardrobeTab == "SETS" then
            -- Set completeness is derived from appearance ownership; let the
            -- existing active-page refresh update the unchanged Sets view.
            return false
        end

        local collected = itemDataProvider:IsOwned(change.collectionId, change.operation == "A")
        local filters = SC.db and SC.db.filters or nil
        local ownershipChangesMembership = filters and not (filters.collected and filters.uncollected)
        if self:IsShown() and SC.db and SC.db.wardrobeTab == "ITEMS" then
            if ownershipChangesMembership then
                -- Rebind the same 18-frame pool because an exclusive ownership
                -- filter can add/remove a row; unchanged records skip Reload.
                refreshItems()
            else
                EzItems:ApplyCollectionDelta(self.scItemModels, change.collectionId, collected, self.scItemSelectedId)
                local owned, total = itemDataProvider:GetProgress()
                self.scItemCollected = owned
                self.scItemTotal = total
                self.scItemRevision = change.revision
                if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(owned, total) end
            end
        end
        return true
    end

    if SC.Bridge and type(SC.Bridge.RegisterStateListener) == "function" then
        page.scBridgeStateListener = SC.Bridge.RegisterStateListener(function(_, typeId, change)
            local appearanceTypeId = itemDataProvider:GetAppearanceTypeId()
            if appearanceTypeId and tonumber(typeId) == tonumber(appearanceTypeId) and change and change.kind == "DELTA" then
                return page:ApplyAppearanceCollectionChange(change)
            end
            return false
        end)
    end

    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:RegisterEvent("PLAYER_ENTERING_WORLD")
    page:RegisterEvent("UNIT_MODEL_CHANGED")
    page:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            cancelSetPreview()
            if self:IsShown() and SC.db and SC.db.wardrobeTab == "SETS" then
                self:Refresh()
            end
            return
        end
        if event == "UNIT_MODEL_CHANGED" then
            local unit = ...
            if unit == "player" then
                cancelSetPreview()
                if self:IsShown() and SC.db and SC.db.wardrobeTab == "SETS" then
                    self:Refresh()
                end
            end
            return
        end
        if not self:IsShown() then return end
        if self.scRuntimeAuditActive then return end
        local itemId, success = ...
        if success == false or not itemId then return end
        itemId = tonumber(itemId) or itemId

        for _, itemModel in ipairs(self.scItemModels) do
            if itemModel.scCard and itemModel.scCard:IsShown()
                and itemModel.scRecord and itemModel.scRecord.itemId == itemId then
                -- TransmorpherItemQuery owns readiness for every item card and
                -- feeds the shared generation-safe render queue. Replaying a
                -- cached armor or weapon page here would collapse 18 exact
                -- Reset/Undress/TryOn lifecycles back into one frame.
                if itemModel.scRenderKind ~= "TRANSMORPHER_ARMOR"
                    and itemModel.scRenderKind ~= "TRANSMORPHER_WEAPON" then
                    applyItemModelRecord(itemModel, itemModel.scRecord, self.scItemGeneration, true)
                end
                if itemModel.scHitFrame and GameTooltip:IsOwned(itemModel.scHitFrame) then
                    showItemTooltip(itemModel.scHitFrame, itemModel.scRecord)
                end
            end
        end

        for _, piece in ipairs(self.scPieceIcons) do
            if piece:IsShown() and piece.scItemId == itemId then
                updateSetPieceVisual(piece, itemId, appearanceState[itemId] and true or false)
                if GameTooltip:IsOwned(piece) then
                    showPieceTooltip(piece, itemId)
                end
            end
        end
    end)
    page:SetScript("OnHide", function(self)
        self.scRuntimeAuditActive = nil
        self:ClearSelection()
        self.scItemPage = 1
        setSetOffset(0, true)
        self.scSetRecordCount = 0
        for _, itemModel in ipairs(self.scItemModels) do
            ItemCardRenderer:Clear(itemModel)
        end
        model:ClearModel()
        GameTooltip:Hide()
    end)

    page.scModel = model
    page.scItemsPanel = itemsPanel
    page.scSetsPanel = setsPanel
    page.scItemsBackground = itemsInset.background
    page.scSetsBackground = setsInset.background
    page.scSetDetail = preview
    page.scItemControls = itemControls
    page.scSetControls = setControls
    page.scSetScrollbar = setScrollbar
    page.scArmorDropdown = armorDropdown
    page.scClassDropdown = classDropdown
    page.scWeaponDropdown = weaponDropdown
    page.scSlotsFrame = slotsFrame
    return page
end
