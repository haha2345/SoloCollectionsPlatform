local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog
local Identity = SC.IdentityRegistry

local ITEM_ROWS = 3
local ITEM_COLUMNS = 6
local ITEM_PAGE_SIZE = ITEM_ROWS * ITEM_COLUMNS
local ITEM_MODEL_WIDTH = 132
local ITEM_MODEL_HEIGHT = 164
local ITEM_MODEL_GAP_X = 10
local ITEM_MODEL_GAP_Y = 12
local VISIBLE_SET_ROWS = 8
local SET_ROW_HEIGHT = 52
local SET_ROW_SPACING = 3
local SET_PIECE_SIZE = 40
local SET_PIECE_SPACING = 5
local DEFAULT_ROTATION = 0.18
-- SoloCam v4 reserves this numeric range for direct CreatureDisplayInfo IDs.
-- Stock SetCreature interprets ordinary values as Creature entries; the
-- client bridge decodes base + displayId and supplies the persistent internal
-- creature-cache record required by PlayerModel.
local DIRECT_DISPLAY_REQUEST_BASE = 0x6F000000
local CUSTOM_CAMERA_HUMAN_FEMALE = {
    HEAD = 0x5341,
    SHOULDER = 0x5342,
    BACK = 0x5349,
    CHEST = 0x5343,
    WRIST = 0x5344,
    HANDS = 0x5345,
    WAIST = 0x5346,
    LEGS = 0x5347,
    FEET = 0x5348,
}

local EQUIPMENT_SLOT_BY_APPEARANCE_SLOT = {
    HEAD = 0,
    SHOULDER = 2,
    SHIRT = 3,
    CHEST = 4,
    WAIST = 5,
    LEGS = 6,
    FEET = 7,
    WRIST = 8,
    HANDS = 9,
    BACK = 14,
    MAINHAND = 15,
    OFFHAND = 16,
    TABARD = 18,
}

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

-- Retail obtains an appearance-specific UI camera from client data. That API
-- does not exist in 3.3.5, so the same 18-model layout uses slot-specific
-- camera profiles built from the WotLK DressUpModel API. SetCamera establishes
-- the client's native framing first; scale and position below are then applied
-- relative to that native state instead of replacing it with guessed absolute
-- values.
--
-- WotLK player models expose only camera 0 (portrait) and camera 1
-- (dressing-room). Adding a third camera to the player M2 crashes the client,
-- so the client-extension PoC uses a slot-specific SetCamera handshake. The
-- extension recognizes the nine sentinels below and applies an independent
-- render-time camera for the corresponding human-female equipment slot;
-- the immediately following camera 1 call is a safe stock-client fallback.
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

local CLASS_FILTERS = Identity.GetClassFilterOptions()

local ARMOR_TYPE_FILTERS = {
    { key = "PLATE", label = "板甲" },
    { key = "MAIL", label = "锁甲" },
    { key = "LEATHER", label = "皮甲" },
    { key = "CLOTH", label = "布甲" },
}

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

-- Coordinates come from the Retail UiTextureAtlasMember rows for atlas 610
-- (FileDataID 1116940). The full Blizzard texture is bundled byte-for-byte;
-- WotLK has no SetAtlas, so each button selects its original rectangle.
local SLOT_ATLAS_SIZE = 512
local SLOT_ATLAS_REGIONS = {
    back = { 145, 180, 369, 406 },
    chest = { 105, 140, 409, 446 },
    feet = { 142, 177, 409, 446 },
    hands = { 105, 140, 448, 485 },
    head = { 142, 177, 448, 485 },
    legs = { 203, 238, 115, 152 },
    mainhand = { 240, 275, 115, 152 },
    secondaryhand = { 277, 312, 115, 152 },
    shoulder = { 351, 386, 115, 152 },
    waist = { 425, 460, 115, 152 },
    wrist = { 462, 497, 115, 152 },
    selected = { 381, 426, 65, 112 },
}

local ROUND_HIGHLIGHT_SIZE = { 512, 256 }
local ROUND_HIGHLIGHT_REGION = { 261, 297, 166, 202 }

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

local STABLE_SLOT_ORDER = {
    INVTYPE_HEAD = 1,
    INVTYPE_SHOULDER = 2,
    INVTYPE_CLOAK = 3,
    INVTYPE_CHEST = 4,
    INVTYPE_ROBE = 4,
    INVTYPE_WRIST = 5,
    INVTYPE_HAND = 6,
    INVTYPE_WAIST = 7,
    INVTYPE_LEGS = 8,
    INVTYPE_FEET = 9,
    INVTYPE_WEAPON = 10,
    INVTYPE_2HWEAPON = 10,
    INVTYPE_WEAPONMAINHAND = 10,
    INVTYPE_WEAPONOFFHAND = 11,
    INVTYPE_SHIELD = 11,
    INVTYPE_HOLDABLE = 11,
    INVTYPE_RANGED = 12,
    INVTYPE_RANGEDRIGHT = 12,
}

-- All bundled tier-one records use this source order. It keeps TryOn ordering
-- deterministic even before the local item cache can report equip locations.
local SET_INDEX_FALLBACK_ORDER = { 7, 5, 1, 9, 6, 8, 2, 4 }

local function filterLabel(options, current)
    for _, option in ipairs(options) do
        if option.key == current then
            return option.label
        end
    end
    return options[1].label
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

local function getDefaultArmorType()
    return Identity.GetDefaultArmorType() or "AUTO"
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

local function isStandaloneItemRecord(record)
    return record
        and STANDALONE_ITEM_SLOTS[record.slot]
        and ((type(record.creatureDisplayId) == "number" and record.creatureDisplayId > 0)
            or (type(record.modelPath) == "string" and record.modelPath ~= ""))
end

-- A stable camera key lets one in-game adjustment apply to every sample of a
-- weapon family. A record may supply a more specific key when two M2 files in
-- the same visual class are mirrored (for example the two Azzinoth glaives).
local function getM2CameraTuningKey(record)
    if record and type(record.cameraTuningKey) == "string" and record.cameraTuningKey ~= "" then
        return record.cameraTuningKey
    end
    if record and type(record.weaponType) == "string" and record.weaponType ~= "" then
        return record.weaponType
    end
    return record and record.id
end

local function getSavedM2CameraPose(record)
    if not record or not SC.db or type(SC.db.m2CameraTuning) ~= "table" then
        return nil
    end
    local tuningKey = getM2CameraTuningKey(record)
    local saved = SC.db.m2CameraTuning[tuningKey]
    if type(saved) ~= "table" or not SC.M2Camera or not SC.M2Camera.NormalizePose then
        return nil
    end
    return SC.M2Camera.NormalizePose(saved)
end

local function getEffectiveM2CameraPose(model)
    if not model or not model.scRecord then
        return nil
    end
    return model.scCameraPoseOverride
        or getSavedM2CameraPose(model.scRecord)
        or model.scRecord.m2Camera
end

local function isM2CameraTunableRecord(record)
    return isStandaloneItemRecord(record)
        and type(record.m2Camera) == "table"
        and SC.M2Camera
        and SC.M2Camera.NormalizePose
end

local function createThinCardBorder(parent, thickness)
    local border = CreateFrame("Frame", nil, parent)
    border:SetAllPoints(parent)
    border:SetFrameLevel(parent:GetFrameLevel() + 1)

    local size = thickness or 1
    local top = border:CreateTexture(nil, "OVERLAY")
    top:SetTexture("Interface\\Buttons\\WHITE8X8")
    top:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    top:SetHeight(size)

    local bottom = border:CreateTexture(nil, "OVERLAY")
    bottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(size)

    local left = border:CreateTexture(nil, "OVERLAY")
    left:SetTexture("Interface\\Buttons\\WHITE8X8")
    left:SetPoint("TOPLEFT", border, "TOPLEFT", 0, -size)
    left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, size)
    left:SetWidth(size)

    local right = border:CreateTexture(nil, "OVERLAY")
    right:SetTexture("Interface\\Buttons\\WHITE8X8")
    right:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, -size)
    right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, size)
    right:SetWidth(size)

    border.scEdges = { top, bottom, left, right }

    function border:SetBorderColor(red, green, blue, alpha)
        for _, edge in ipairs(self.scEdges) do
            edge:SetVertexColor(red, green, blue, alpha or 1)
        end
    end

    function border:SetCollected(collected)
        if collected then
            self:SetBorderColor(0.58, 0.43, 0.16, 1)
        else
            -- Retail distinguishes an uncollected appearance with its border;
            -- it does not cover the model with a broad gray veil.
            self:SetBorderColor(0.38, 0.39, 0.40, 1)
        end
    end

    return border
end

-- Retail set-list icons use a restrained glass rim rather than the broad
-- yellow collected-frame texture used by the original prototype. Keeping this
-- row local to Wardrobe avoids changing the visual language of mount/pet rows.
local function createSetListRow(parent, width, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(width or 330)
    row:SetHeight(SET_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetAllPoints(row)
    background:SetVertexColor(0.018, 0.016, 0.014, 0.78)

    local selected = row:CreateTexture(nil, "BORDER")
    selected:SetTexture("Interface\\Buttons\\WHITE8X8")
    selected:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    selected:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    selected:SetGradientAlpha("HORIZONTAL", 0.46, 0.22, 0.045, 0.72, 0.17, 0.075, 0.02, 0.34)
    selected:Hide()

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    hover:SetGradientAlpha("HORIZONTAL", 0.72, 0.48, 0.13, 0.24, 0.42, 0.24, 0.06, 0.08)
    row:SetHighlightTexture(hover)

    local separator = row:CreateTexture(nil, "BORDER")
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
    separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
    separator:SetHeight(1)
    separator:SetVertexColor(0.34, 0.29, 0.22, 0.34)

    local iconHolder = CreateFrame("Frame", nil, row)
    iconHolder:SetWidth(42)
    iconHolder:SetHeight(42)
    iconHolder:SetPoint("LEFT", row, "LEFT", 5, 0)
    iconHolder:SetFrameLevel(row:GetFrameLevel() + 1)

    local iconBackground = iconHolder:CreateTexture(nil, "BACKGROUND")
    iconBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconBackground:SetAllPoints(iconHolder)
    iconBackground:SetVertexColor(0.018, 0.021, 0.024, 0.92)

    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -2, 2)
    UI.SetFallbackTexture(icon)

    local glass = iconHolder:CreateTexture(nil, "OVERLAY")
    glass:SetTexture("Interface\\Buttons\\WHITE8X8")
    glass:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 2, -2)
    glass:SetPoint("TOPRIGHT", iconHolder, "TOPRIGHT", -2, -2)
    glass:SetHeight(17)
    glass:SetGradientAlpha("VERTICAL", 0.80, 0.88, 0.94, 0.02, 0.92, 0.96, 1.00, 0.18)

    local iconBorder = createThinCardBorder(iconHolder, 1)
    iconBorder:SetBorderColor(0.44, 0.46, 0.48, 0.92)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 10, -5)
    name:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    name:SetJustifyH("LEFT")
    name:SetTextColor(0.93, 0.77, 0.26)

    local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMRIGHT", 10, 5)
    detail:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(0.49, 0.48, 0.46)

    local star = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    star:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    star:SetText("★")
    star:SetTextColor(1.00, 0.82, 0.18)
    star:Hide()

    row:SetScript("OnClick", function(self)
        if onClick and self.scRecord then
            onClick(self, self.scRecord)
        end
    end)

    function row:SetRecord(record)
        self.scRecord = record
        if not record then
            selected:Hide()
            star:Hide()
            name:SetText("")
            detail:SetText("")
            self:Hide()
            return
        end

        UI.SetIconTexture(icon, record.icon)
        UI.SetCollectedVisual(icon, record.collected, 0.52)
        name:SetText(record.name or "未知套装")
        name:SetTextColor(record.collected and 0.96 or 0.59, record.collected and 0.79 or 0.59, record.collected and 0.28 or 0.57)
        local owned = tonumber(record.collectedCount) or 0
        local required = tonumber(record.requiredCount) or #(record.itemIds or {})
        detail:SetText(filterLabel(CLASS_FILTERS, record.classToken) .. "  ·  " .. owned .. "/" .. required .. " 外观")
        if record.collected then
            iconBorder:SetBorderColor(0.66, 0.52, 0.24, 0.96)
        else
            iconBorder:SetBorderColor(0.39, 0.41, 0.43, 0.86)
        end
        if record.favorite then star:Show() else star:Hide() end
        self:Show()
    end

    function row:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then selected:Show() else selected:Hide() end
    end

    row.scIcon = icon
    row.scIconBorder = iconBorder
    row.scName = name
    row.scDetail = detail
    row.scStar = star
    return row
end

local function applyStandaloneItemTransform(model)
    local record = model and model.scRecord
    if not record then return false end
    if model.SetModelScale then
        pcall(function() model:SetModelScale(record.modelScale or 1.00) end)
    end
    if model.SetPosition then
        local position = record.modelPosition or { 0, 0, 0 }
        pcall(function() model:SetPosition(position[1] or 0, position[2] or 0, position[3] or 0) end)
    end
    -- When a record owns M2 camera 0 through SoloCam, orientation belongs to
    -- the camera pose. Keep the actor unrotated so SetRotation cannot mask or
    -- double the camera adjustment. Legacy records still retain their old
    -- modelRotation/modelFacing fallback.
    local rotation = 0
    if not record.m2Camera then
        rotation = record.modelRotation or record.modelFacing or 0
    end
    -- Standalone cards use PlayerModel + SetCreature through the direct
    -- CreatureDisplayInfo bridge. In 3.3.5 its visible actor is rotated by
    -- CharacterModelBase:SetRotation; generic Model:SetFacing does not rotate
    -- that SetCreature result even though the inherited method is present.
    if model.SetRotation then
        pcall(function() model:SetRotation(rotation) end)
    elseif model.SetFacing then
        pcall(function() model:SetFacing(rotation) end)
    end
    return true
end

local function applyStandaloneItemLighting(model)
    if not model or not model.SetLight then return false end
    -- A plain 3.3.5 Model widget does not inherit the lit dressing-room
    -- environment used by DressUpModel. Without an explicit ambient/diffuse
    -- light, opaque weapon passes render as a black silhouette while additive
    -- effects remain visible. This is the legacy Model:SetLight signature:
    -- enabled, omni, direction xyz, ambient intensity/rgb, diffuse intensity/rgb.
    return pcall(function()
        model:SetLight(
            true, false,
            -1.0, -0.7, -0.5,
            0.82, 1.0, 1.0, 1.0,
            0.72, 1.0, 0.95, 0.88
        )
    end)
end

local function applyStandaloneItemView(model)
    applyStandaloneItemLighting(model)
    local appliedM2Camera = false
    local cameraPose = getEffectiveM2CameraPose(model)
    if model and cameraPose
        and SC.M2Camera and SC.M2Camera.Apply then
        appliedM2Camera = SC.M2Camera.Apply(model, cameraPose)
    end
    if not appliedM2Camera and model and model.SetCamera then
        pcall(function() model:SetCamera(0) end)
    end
    return applyStandaloneItemTransform(model)
end

local STANDALONE_TRANSFORM_SETTLE_FRAMES = 6

local function cancelStandaloneItemTransformQueue(model)
    if not model then return end
    model.scStandaloneTransformQueued = nil
    model.scStandaloneTransformFrames = nil
    model:SetScript("OnUpdate", nil)
end

local function queueStandaloneItemTransform(model)
    if not model or not model.scRecord then return end
    model.scStandaloneTransformQueued = true
    model.scStandaloneTransformFrames = 0
    model:SetScript("OnUpdate", function(self)
        if not self.scStandaloneTransformQueued or not self.scRecord then
            cancelStandaloneItemTransformQueue(self)
            return
        end

        self.scStandaloneTransformFrames = self.scStandaloneTransformFrames + 1
        -- SetCreature and SetCamera rebuild the legacy model asynchronously.
        -- Reapply the item transform for several frames so the late camera
        -- rebuild cannot restore the default diagonal.
        if self.scStandaloneTransformFrames >= 2 then
            applyStandaloneItemLighting(self)
            applyStandaloneItemTransform(self)
        end
        if self.scStandaloneTransformFrames >= STANDALONE_TRANSFORM_SETTLE_FRAMES then
            cancelStandaloneItemTransformQueue(self)
        end
    end)
end

local function applyStandaloneItemRecord(model, record)
    if not model then return end
    cancelStandaloneItemTransformQueue(model)
    if not record then
        model.scRecord = nil
        model.scRecordId = nil
        model.scCameraPoseOverride = nil
        model:ClearModel()
        model:Hide()
        return
    end

    local unchanged = model.scRecordId == record.id
        and model.scRecord
        and model.scRecord.creatureDisplayId == record.creatureDisplayId
        and model.scRecord.modelPath == record.modelPath
    model.scRecord = record
    -- A pooled PlayerModel may have shown another record on the previous page.
    -- The persisted pose is looked up by record ID in getEffectiveM2CameraPose;
    -- clear the transient slider reference before assigning this new record.
    model.scCameraPoseOverride = nil
    model:Show()
    if not unchanged then
        model.scRecordId = record.id
        model:ClearModel()
        if record.creatureDisplayId and model.SetCreature then
            pcall(function()
                model:SetCreature(DIRECT_DISPLAY_REQUEST_BASE + record.creatureDisplayId)
            end)
        else
            pcall(function() model:SetModel(record.modelPath) end)
        end
    end
    applyStandaloneItemView(model)
    queueStandaloneItemTransform(model)
end

local function getHumanFemaleCameraSentinel(model)
    if not model or not model.scRecord then
        return nil
    end
    local sentinel = CUSTOM_CAMERA_HUMAN_FEMALE[model.scRecord.slot]
    if not sentinel then
        return nil
    end
    local _, raceToken = UnitRace("player")
    if raceToken == "Human" and UnitSex("player") == 3 then
        return sentinel
    end
    return nil
end

local function selectItemModelCamera(model)
    local profile = model.scProfile or WARDROBE_MODEL_PROFILES.DEFAULT
    model.scClientCameraSentinel = getHumanFemaleCameraSentinel(model)
    model.scUsesClientCamera = model.scClientCameraSentinel ~= nil
    if model.SetCamera then
        if model.scUsesClientCamera then
            pcall(function()
                -- Safe capability handshake: an unextended stock client treats
                -- the sentinel as invalid, then the second call restores its
                -- native dressing-room camera in the same Lua tick.
                model:SetCamera(model.scClientCameraSentinel)
                model:SetCamera(1)
            end)
        else
            pcall(function() model:SetCamera(profile.camera) end)
        end
    end
end

local function captureItemModelBaseline(model)
    if model.scBaselineGeneration == model.scAppearanceGeneration
        and type(model.scNativeScale) == "number"
        and type(model.scNativeHorizontal) == "number"
        and type(model.scNativeVertical) == "number"
        and type(model.scNativeDepth) == "number" then
        return true
    end
    if not model.GetModelScale or not model.GetPosition then
        return false
    end

    local scaleOk, nativeScale = pcall(function() return model:GetModelScale() end)
    local positionOk, nativeHorizontal, nativeVertical, nativeDepth = pcall(function() return model:GetPosition() end)
    if not scaleOk or type(nativeScale) ~= "number" or nativeScale <= 0
        or not positionOk or type(nativeHorizontal) ~= "number"
        or type(nativeVertical) ~= "number" or type(nativeDepth) ~= "number" then
        return false
    end

    model.scNativeScale = nativeScale
    model.scNativeHorizontal = nativeHorizontal
    model.scNativeVertical = nativeVertical
    model.scNativeDepth = nativeDepth
    model.scBaselineGeneration = model.scAppearanceGeneration
    return true
end

local function applyItemModelTransform(model)
    local profile = model.scProfile or WARDROBE_MODEL_PROFILES.DEFAULT
    if not captureItemModelBaseline(model) then
        return false
    end
    local nativeScale = model.scNativeScale
    local nativeHorizontal = model.scNativeHorizontal
    local nativeVertical = model.scNativeVertical
    local nativeDepth = model.scNativeDepth
    if model.scUsesClientCamera then
        -- The DLL owns slot framing. Keep the model's native transform so the
        -- legacy scale/translation does not double-zoom the custom camera.
        if model.SetModelScale then
            pcall(function() model:SetModelScale(nativeScale) end)
        end
        if model.SetPosition then
            pcall(function() model:SetPosition(nativeHorizontal, nativeVertical, nativeDepth) end)
        end
    else
        if model.SetModelScale then
            pcall(function() model:SetModelScale(nativeScale * (profile.scaleMultiplier or 1.00)) end)
        end
        if model.SetPosition then
            pcall(function() model:SetPosition(nativeHorizontal + (profile.horizontalOffset or 0), nativeVertical + (profile.verticalOffset or 0), nativeDepth + (profile.depthOffset or 0)) end)
        end
    end
    if model.SetRotation then
        pcall(function() model:SetRotation(profile.rotation) end)
    end
    return true
end

local function queueItemModelView(model, force)
    if not model.scRecord or model.scApplyingAppearance or model.scApplyingView then
        return false
    end
    if not force then
        if model.scViewStage then
            return false
        end
        if model.scViewAppliedGeneration == model.scAppearanceGeneration then
            return false
        end
    end
    model.scViewStage = "CAMERA"
    model.scViewFrames = 0
    if model.scUpdateHandler then
        model:SetScript("OnUpdate", model.scUpdateHandler)
    end
    return true
end

-- SetUnit and TryOn both rebuild the model asynchronously. Selecting camera 1
-- and translating the model in the same update lets the later camera rebuild
-- overwrite our transform. Keep camera selection and the final body-part
-- transform in separate render ticks so scale, position and rotation survive.
local function finishPendingItemModelView(model)
    if not model.scViewStage or model.scPendingItemString or model.scApplyingAppearance or model.scApplyingView then
        return false
    end

    if model.scViewStage == "CAMERA" then
        model.scApplyingView = true
        selectItemModelCamera(model)
        model.scApplyingView = nil
        model.scViewStage = "SETTLE"
        model.scViewFrames = 0
        return true
    end

    if model.scViewStage == "SETTLE" then
        model.scViewFrames = model.scViewFrames + 1
        if model.scViewFrames < 2 then
            return true
        end
        model.scViewStage = "TRANSFORM"
        return true
    end

    if model.scViewStage == "TRANSFORM" then
        model.scApplyingView = true
        applyItemModelTransform(model)
        model.scApplyingView = nil
        model.scViewStage = nil
        model.scViewFrames = nil
        model.scViewAppliedGeneration = model.scAppearanceGeneration
        return true
    end

    model.scViewStage = nil
    model.scViewFrames = nil
    return false
end

local function finishPendingItemModel(model)
    if not model.scPendingItemString or model.scApplyingAppearance then
        return false
    end

    if model.GetModel then
        local loaded, modelPath = pcall(function() return model:GetModel() end)
        if not loaded or type(modelPath) ~= "string" or modelPath == "" then
            model.scModelReadyFrames = 0
            return false
        end
    end

    model.scModelReadyFrames = (model.scModelReadyFrames or 0) + 1
    if model.scModelReadyFrames < 2 then
        return false
    end

    local itemString = model.scPendingItemString
    model.scPendingItemString = nil
    model.scModelReadyFrames = nil
    model.scApplyingAppearance = true
    if model.Undress then
        pcall(function() model:Undress() end)
    end
    pcall(function() model:TryOn(itemString) end)
    model.scApplyingAppearance = nil
    queueItemModelView(model, true)
    return true
end

-- The original grid left an OnUpdate callback attached to every visible
-- DressUpModel forever. A page can show 18 models, so even a no-op callback
-- multiplied into every frame adds avoidable Lua work. Keep the updater awake
-- only while SetUnit/TryOn or the camera handshake is still settling.
local function updatePendingItemModel(self)
    local appearanceApplied = finishPendingItemModel(self)
    if not appearanceApplied then
        finishPendingItemModelView(self)
    end
    if not self.scPendingItemString and not self.scViewStage then
        self:SetScript("OnUpdate", nil)
    end
end

local function applyItemModelRecord(model, record)
    local objectModel = model.scObjectModel
    if not record then
        model.scRecord = nil
        model.scRecordId = nil
        model.scProfile = nil
        model.scClientCameraSentinel = nil
        model.scUsesClientCamera = nil
        model.scPendingItemString = nil
        model.scModelReadyFrames = nil
        model.scApplyingAppearance = nil
        model.scAppearanceGeneration = nil
        model.scViewAppliedGeneration = nil
        model.scViewStage = nil
        model.scViewFrames = nil
        model.scApplyingView = nil
        model.scNativeScale = nil
        model.scNativeHorizontal = nil
        model.scNativeVertical = nil
        model.scNativeDepth = nil
        model.scBaselineGeneration = nil
        model.scRenderKind = nil
        model:SetScript("OnUpdate", nil)
        model:ClearModel()
        model:Hide()
        applyStandaloneItemRecord(objectModel, nil)
        if model.scCard then model.scCard:Hide() end
        return
    end

    local profile = WARDROBE_MODEL_PROFILES[record.slot] or WARDROBE_MODEL_PROFILES.DEFAULT
    local renderKind = isStandaloneItemRecord(record) and "STANDALONE" or "BODY"
    local unchanged = model.scRecordId == record.id
        and model.scProfile == profile
        and model.scRenderKind == renderKind
    model.scRecord = record
    model.scProfile = profile
    if model.scCard then model.scCard:Show() end

    if renderKind == "STANDALONE" then
        model.scRecordId = record.id
        model.scRenderKind = renderKind
        model.scClientCameraSentinel = nil
        model.scUsesClientCamera = nil
        model.scPendingItemString = nil
        model.scModelReadyFrames = nil
        model.scApplyingAppearance = nil
        model.scViewAppliedGeneration = nil
        model.scViewStage = nil
        model.scViewFrames = nil
        model.scApplyingView = nil
        model.scNativeScale = nil
        model.scNativeHorizontal = nil
        model.scNativeVertical = nil
        model.scNativeDepth = nil
        model.scBaselineGeneration = nil
        model:SetScript("OnUpdate", nil)
        model:ClearModel()
        model:Hide()
        applyStandaloneItemRecord(objectModel, record)
        return
    end

    applyStandaloneItemRecord(objectModel, nil)
    model.scRenderKind = renderKind
    model:Show()

    if not unchanged then
        model.scRecordId = record.id
        model.scPendingItemString = resolveTryOnItem(record.itemId)
        model.scModelReadyFrames = 0
        model.scAppearanceGeneration = (model.scAppearanceGeneration or 0) + 1
        model.scViewAppliedGeneration = nil
        model.scNativeScale = nil
        model.scNativeHorizontal = nil
        model.scNativeVertical = nil
        model.scNativeDepth = nil
        model.scBaselineGeneration = nil
        model.scViewStage = nil
        model.scViewFrames = nil
        model.scApplyingAppearance = true
        model:ClearModel()
        pcall(function() model:SetUnit("player") end)
        model.scApplyingAppearance = nil
        queueItemModelView(model, true)
    end
end

local function stableSetItems(record)
    local ordered = {}
    for index, itemId in ipairs(record.itemIds or {}) do
        local equipLoc = select(9, GetItemInfo(itemId))
        table.insert(ordered, {
            itemId = itemId,
            order = STABLE_SLOT_ORDER[equipLoc] or SET_INDEX_FALLBACK_ORDER[index] or (100 + index),
            original = index,
        })
    end
    table.sort(ordered, function(left, right)
        if left.order == right.order then
            return left.original < right.original
        end
        return left.order < right.order
    end)
    local result = {}
    for _, entry in ipairs(ordered) do
        table.insert(result, entry.itemId)
    end
    return result
end

function UI.CreateWardrobePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scItemPage = 1
    page.scSetPage = 1
    page.scSetOffset = 0
    page.scSetRecordCount = 0
    page.scDefaultSetClassApplied = false
    page.scItemModels = {}
    page.scSetRows = {}
    page.scPieceIcons = {}

    local filterBar = CreateFrame("Frame", nil, page)
    filterBar:SetHeight(78)
    filterBar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    filterBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

    local armorDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeArmorDropdown", filterBar, "UIDropDownMenuTemplate")
    armorDropdown:SetPoint("TOPLEFT", filterBar, "TOPLEFT", -12, -1)
    UIDropDownMenu_SetWidth(armorDropdown, 148)

    -- Sets remain class-owned data in 3.3.5. Retail places this selector above
    -- the preview side, so it deliberately does not reuse the item filter's
    -- upper-left position.
    local classDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeClassDropdown", filterBar, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", 12, -1)
    UIDropDownMenu_SetWidth(classDropdown, 148)

    local slotsFrame = CreateFrame("Frame", nil, filterBar)
    slotsFrame:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 181, -1)
    slotsFrame:SetWidth(430)
    slotsFrame:SetHeight(42)
    page.scSlotButtons = {}

    local weaponDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeWeaponDropdown", filterBar, "UIDropDownMenuTemplate")
    weaponDropdown:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", 12, -40)
    UIDropDownMenu_SetWidth(weaponDropdown, 164)
    weaponDropdown:Hide()

    local function chooseDedicatedFilter(key, value)
        if not SC.db or not SC.db.filters then return end
        SC.db.filters[key] = value
        if key == "slot" and STANDALONE_ITEM_SLOTS[value] then
            ensureWeaponTypeForSlot(SC.db.filters, value)
        end
        page.scItemSelectedId = nil
        page.scSetSelectedId = nil
        page.scItemPage = 1
        page.scSetPage = 1
        page.scSetOffset = 0
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
        setAtlasRegion(normal, UI.Media.wardrobeSlotAtlas, SLOT_ATLAS_SIZE, SLOT_ATLAS_SIZE, SLOT_ATLAS_REGIONS[slotOption.atlas])
        button:SetNormalTexture(normal)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetWidth(31)
        highlight:SetHeight(31)
        highlight:SetPoint("CENTER", button, "CENTER", 0, 1)
        highlight:SetBlendMode("ADD")
        setAtlasRegion(highlight, UI.Media.roundHighlightAtlas, ROUND_HIGHLIGHT_SIZE[1], ROUND_HIGHLIGHT_SIZE[2], ROUND_HIGHLIGHT_REGION)
        button:SetHighlightTexture(highlight)

        local selected = button:CreateTexture(nil, "OVERLAY")
        selected:SetWidth(45)
        selected:SetHeight(47)
        selected:SetPoint("CENTER", button, "CENTER", 0, 0)
        setAtlasRegion(selected, UI.Media.wardrobeSlotAtlas, SLOT_ATLAS_SIZE, SLOT_ATLAS_SIZE, SLOT_ATLAS_REGIONS.selected)
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

    local itemsPanel = CreateFrame("Frame", nil, page)
    itemsPanel:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -3)
    itemsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    local setsPanel = CreateFrame("Frame", nil, page)
    setsPanel:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -3)
    setsPanel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    setsPanel:SetWidth(350)
    setsPanel:Hide()

    local preview = CreateFrame("Frame", nil, page)
    preview:SetPoint("TOPLEFT", setsPanel, "TOPRIGHT", 16, 0)
    preview:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    UI.ApplyNineSlice(preview, UI.Media.border, 18)
    local previewBackground = preview:CreateTexture(nil, "BACKGROUND")
    previewBackground:SetTexture(UI.Media.background)
    previewBackground:SetPoint("TOPLEFT", preview, "TOPLEFT", 5, -5)
    previewBackground:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -5, 5)
    previewBackground:SetVertexColor(0.48, 0.34, 0.18, 0.88)
    preview:Hide()

    local model = CreateFrame("DressUpModel", nil, preview)
    model:SetPoint("TOPLEFT", preview, "TOPLEFT", 9, -84)
    model:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -9, 76)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)

    local name = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", preview, "TOPLEFT", 16, -13)
    name:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -16, -13)
    name:SetJustifyH("CENTER")
    name:SetTextColor(1, 0.82, 0.18)

    local detail = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 16, 43)
    detail:SetPoint("RIGHT", preview, "RIGHT", -14, 0)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(0.82, 0.75, 0.62)

    local setProgress = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setProgress:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 16, 18)
    setProgress:SetTextColor(0.45, 0.90, 0.34)
    setProgress:Hide()
    page.scSetProgress = setProgress

    local reset = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
    reset:SetWidth(104)
    reset:SetHeight(25)
    reset:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -14, 13)
    reset:SetText("重置视角")

    local pieces = CreateFrame("Frame", nil, preview)
    pieces:SetPoint("TOP", name, "BOTTOM", 0, -8)
    pieces:SetWidth((8 * SET_PIECE_SIZE) + (7 * SET_PIECE_SPACING))
    pieces:SetHeight(SET_PIECE_SIZE)
    for index = 1, 8 do
        local piece = CreateFrame("Button", nil, pieces)
        piece:SetWidth(SET_PIECE_SIZE)
        piece:SetHeight(SET_PIECE_SIZE)
        if index == 1 then
            piece:SetPoint("LEFT", pieces, "LEFT", 0, 0)
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

        local border = createThinCardBorder(piece, 1)
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
    end

    local function previewSet(record)
        if not record then return end
        model:ClearAllPoints()
        model:SetPoint("TOPLEFT", preview, "TOPLEFT", 9, -84)
        model:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -9, 76)
        preparePlayerModel()
        local orderedItems = stableSetItems(record)
        for _, itemId in ipairs(orderedItems) do
            local itemString = resolveTryOnItem(itemId)
            pcall(function() model:TryOn(itemString) end)
        end
        name:SetText(record.name or "未知套装")
        detail:SetText("职业：" .. filterLabel(CLASS_FILTERS, record.classToken))
        pieces:Show()
        local pieceState = deriveSetPieceState(record)
        local pieceCount = math.min(#orderedItems, #page.scPieceIcons)
        local piecesWidth = (pieceCount * SET_PIECE_SIZE) + (math.max(0, pieceCount - 1) * SET_PIECE_SPACING)
        pieces:SetWidth(math.max(1, piecesWidth))
        for index, piece in ipairs(page.scPieceIcons) do
            piece:ClearAllPoints()
            if index == 1 then
                piece:SetPoint("LEFT", pieces, "LEFT", 0, 0)
            else
                piece:SetPoint("LEFT", page.scPieceIcons[index - 1], "RIGHT", SET_PIECE_SPACING, 0)
            end

            local itemId = orderedItems[index]
            piece.scItemId = itemId
            if itemId then
                local collected = pieceState[itemId] and true or false
                updateSetPieceVisual(piece, itemId, collected)
                piece:Show()
            else
                piece:Hide()
            end
        end
        local collectedPieces = tonumber(record.collectedCount) or 0
        local requiredPieces = tonumber(record.requiredCount) or #(record.itemIds or {})
        setProgress:SetText("套装收集进度：" .. collectedPieces .. " / " .. requiredPieces)
        setProgress:Show()
    end

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
    reset:SetScript("OnClick", resetModelView)

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
        if page.SyncCameraTuningPanel then
            page:SyncCameraTuningPanel(record)
        end
    end

    -- In-game M2 camera tuner -------------------------------------------------
    -- This intentionally lives on the item page rather than in the ordinary
    -- options UI: a pose only makes sense while its exact weapon card is
    -- visible. The values are persisted by weapon type, never written into the
    -- catalog record, and can later be exported into Appearances.lua.
    local cameraTuningButton
    local cameraTuningPanel = CreateFrame("Frame", "SoloCollectionsM2CameraTuningPanel", page)
    cameraTuningPanel:SetWidth(286)
    cameraTuningPanel:SetHeight(351)
    cameraTuningPanel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -5, -42)
    cameraTuningPanel:SetFrameStrata("DIALOG")
    cameraTuningPanel:SetFrameLevel(page:GetFrameLevel() + 20)
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

    local tuningTitle = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tuningTitle:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -10)
    tuningTitle:SetText("武器 M2 相机构图")
    tuningTitle:SetTextColor(1.00, 0.82, 0.20)

    local tuningRecord = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tuningRecord:SetPoint("TOPLEFT", tuningTitle, "BOTTOMLEFT", 0, -4)
    tuningRecord:SetPoint("RIGHT", cameraTuningPanel, "RIGHT", -26, 0)
    tuningRecord:SetJustifyH("LEFT")
    tuningRecord:SetTextColor(0.80, 0.74, 0.63)

    local tuningClose = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelCloseButton")
    tuningClose:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", 2, 2)

    local tuningHint = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tuningHint:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -253)
    tuningHint:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -12, -253)
    tuningHint:SetHeight(30)
    tuningHint:SetJustifyH("LEFT")
    tuningHint:SetJustifyV("TOP")
    tuningHint:SetText("拖动滑条即时预览；数值会按武器类型保存，同类样本共用。导出后可固定到 Lua 记录。")
    tuningHint:SetTextColor(0.62, 0.58, 0.49)

    local tuningExport = CreateFrame("EditBox", nil, cameraTuningPanel, "InputBoxTemplate")
    tuningExport:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 12)
    tuningExport:SetPoint("BOTTOMRIGHT", cameraTuningPanel, "BOTTOMRIGHT", -12, 12)
    tuningExport:SetHeight(20)
    tuningExport:SetAutoFocus(false)
    tuningExport:SetFontObject("ChatFontNormal")
    tuningExport:SetTextColor(0.92, 0.84, 0.62)
    tuningExport:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local tuningReset = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningReset:SetWidth(102)
    tuningReset:SetHeight(22)
    tuningReset:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 39)
    tuningReset:SetText("恢复记录")

    local tuningCopy = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningCopy:SetWidth(102)
    tuningCopy:SetHeight(22)
    tuningCopy:SetPoint("BOTTOMRIGHT", cameraTuningPanel, "BOTTOMRIGHT", -12, 39)
    tuningCopy:SetText("导出 Lua")

    local function updateTuningValueLabel(control, value)
        control.value:SetText(string.format("%.2f", value))
    end

    local applyCameraTuning
    local updateCameraTuningExport

    local function createCameraTuningSlider(index, key, labelText, limits, targetIndex)
        local row = CreateFrame("Frame", nil, cameraTuningPanel)
        row:SetWidth(260)
        row:SetHeight(25)
        row:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -49 - ((index - 1) * 29))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 2)
        label:SetWidth(72)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        label:SetTextColor(0.88, 0.78, 0.58)

        local sliderName = "SoloCollectionsM2Camera" .. key .. "Slider"
        local slider = CreateFrame("Slider", sliderName, row, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", label, "RIGHT", 2, 0)
        slider:SetWidth(136)
        slider:SetHeight(16)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(limits.minimum, limits.maximum)
        slider:SetValueStep(limits.step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local sliderLow = _G[sliderName .. "Low"]
        local sliderHigh = _G[sliderName .. "High"]
        local sliderText = _G[sliderName .. "Text"]
        if sliderLow then sliderLow:SetText("") end
        if sliderHigh then sliderHigh:SetText("") end
        if sliderText then sliderText:SetText("") end

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", 0, 2)
        value:SetWidth(44)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(1.00, 0.85, 0.34)

        local control = {
            key = key,
            targetIndex = targetIndex,
            slider = slider,
            value = value,
        }
        table.insert(cameraTuningPanel.scControls, control)
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
            SC.db.m2CameraTuning = SC.db.m2CameraTuning or {}
            SC.db.m2CameraTuning[getM2CameraTuningKey(cameraTuningPanel.scRecord)] = pose
            applyCameraTuning(cameraTuningPanel.scRecord, pose)
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

    local function getTuningPose(record)
        return getSavedM2CameraPose(record)
            or (SC.M2Camera and SC.M2Camera.NormalizePose and SC.M2Camera.NormalizePose(record and record.m2Camera))
    end

    applyCameraTuning = function(record, pose)
        local tuningKey = getM2CameraTuningKey(record)
        for _, itemModel in ipairs(page.scItemModels) do
            if itemModel.scRecord and getM2CameraTuningKey(itemModel.scRecord) == tuningKey then
                local objectModel = itemModel.scObjectModel
                if objectModel then
                    objectModel.scCameraPoseOverride = pose
                    applyStandaloneItemView(objectModel)
                    queueStandaloneItemTransform(objectModel)
                end
            end
        end
    end

    updateCameraTuningExport = function()
        if not cameraTuningPanel.scRecord or not cameraTuningPanel.scPose
            or not SC.M2Camera or not SC.M2Camera.FormatPose then
            tuningExport:SetText("")
            return
        end
        local tuningKey = getM2CameraTuningKey(cameraTuningPanel.scRecord)
        if cameraTuningPanel.scRecord.cameraTuningKey then
            tuningExport:SetText(string.format('cameraTuningKey = "%s", %s', tuningKey, SC.M2Camera.FormatPose(cameraTuningPanel.scPose)))
        elseif type(cameraTuningPanel.scRecord.weaponType) == "string" then
            tuningExport:SetText(string.format('weaponType = "%s", %s', tuningKey, SC.M2Camera.FormatPose(cameraTuningPanel.scPose)))
        else
            tuningExport:SetText(SC.M2Camera.FormatPose(cameraTuningPanel.scPose))
        end
    end

    function page:SyncCameraTuningPanel(record)
        if not cameraTuningPanel.scRequested then
            return
        end
        if not isM2CameraTunableRecord(record) then
            cameraTuningPanel.scRecord = nil
            cameraTuningPanel:Hide()
            if cameraTuningButton then cameraTuningButton:SetText("调相机") end
            return
        end
        local pose = getTuningPose(record)
        if not pose then return end
        cameraTuningPanel.scRecord = record
        cameraTuningPanel.scPose = pose
        cameraTuningPanel.scSyncing = true
        for _, control in ipairs(cameraTuningPanel.scControls) do
            local value = control.targetIndex and pose.target[control.targetIndex] or pose[control.key]
            control.slider:SetValue(value)
            updateTuningValueLabel(control, value)
        end
        cameraTuningPanel.scSyncing = nil
        tuningRecord:SetText("武器类型：" .. (record.weaponTypeLabel or "未分类") .. " · " .. (record.name or ("外观 " .. tostring(record.id))))
        updateCameraTuningExport()
        cameraTuningPanel:Show()
        if cameraTuningButton then cameraTuningButton:SetText("收起相机") end
    end

    function page:ToggleCameraTuning()
        cameraTuningPanel.scRequested = not cameraTuningPanel.scRequested
        if not cameraTuningPanel.scRequested then
            cameraTuningPanel:Hide()
            cameraTuningButton:SetText("调相机")
            return
        end
        local selected
        for _, itemModel in ipairs(self.scItemModels) do
            if itemModel.scRecord and itemModel.scRecord.id == self.scItemSelectedId then
                selected = itemModel.scRecord
                break
            end
        end
        self:SyncCameraTuningPanel(selected)
    end

    tuningClose:SetScript("OnClick", function() page:ToggleCameraTuning() end)
    tuningCopy:SetScript("OnClick", function()
        updateCameraTuningExport()
        tuningExport:SetFocus()
        tuningExport:HighlightText()
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：Lua 相机 pose 已选中，可按 Ctrl+C 复制。")
        end
    end)
    tuningReset:SetScript("OnClick", function()
        local record = cameraTuningPanel.scRecord
        if not record or not SC.db or type(SC.db.m2CameraTuning) ~= "table" then return end
        local tuningKey = getM2CameraTuningKey(record)
        SC.db.m2CameraTuning[tuningKey] = nil
        if tuningKey ~= record.id then
            -- A reset must not unexpectedly restore an old per-card value.
            SC.db.m2CameraTuning[record.id] = nil
        end
        applyCameraTuning(record, getTuningPose(record))
        page:SyncCameraTuningPanel(record)
    end)

    cameraTuningButton = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    cameraTuningButton:SetWidth(82)
    cameraTuningButton:SetHeight(22)
    cameraTuningButton:SetPoint("RIGHT", filterBar, "RIGHT", -5, 0)
    cameraTuningButton:SetText("调相机")
    cameraTuningButton:SetScript("OnClick", function() page:ToggleCameraTuning() end)

    for index = 1, ITEM_PAGE_SIZE do
        local column = (index - 1) % ITEM_COLUMNS
        local row = math.floor((index - 1) / ITEM_COLUMNS)
        local itemCard = CreateFrame("Frame", nil, itemsPanel)
        itemCard:SetWidth(ITEM_MODEL_WIDTH)
        itemCard:SetHeight(ITEM_MODEL_HEIGHT)
        itemCard:SetPoint(
            "TOPLEFT",
            itemsPanel,
            "TOPLEFT",
            4 + column * (ITEM_MODEL_WIDTH + ITEM_MODEL_GAP_X),
            -4 - row * (ITEM_MODEL_HEIGHT + ITEM_MODEL_GAP_Y)
        )

        local itemModel = CreateFrame("DressUpModel", nil, itemCard)
        itemModel:SetAllPoints(itemCard)

        -- A WotLK PlayerModel can resolve CreatureDisplayInfo replacement
        -- skins. Generic Model cannot bind an equipment OBJECT_SKIN and turns
        -- weapon surfaces black, so custom client-only creature display rows
        -- provide the independent weapon renderer used by these cards.
        local itemObjectModel = CreateFrame("PlayerModel", nil, itemCard)
        itemObjectModel:SetAllPoints(itemCard)
        itemObjectModel:Hide()

        local itemHitFrame = CreateFrame("Button", nil, itemCard)
        itemHitFrame:SetAllPoints(itemCard)
        itemHitFrame:SetFrameLevel(itemModel:GetFrameLevel() + 2)
        itemHitFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local cardBackground = itemCard:CreateTexture(nil, "BACKGROUND")
        cardBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        cardBackground:SetAllPoints(itemCard)
        cardBackground:SetVertexColor(0.02, 0.015, 0.01, 0.94)

        local border = createThinCardBorder(itemHitFrame, 1)
        border:SetCollected(false)

        local selected = createThinCardBorder(itemHitFrame, 2)
        selected:SetBorderColor(1.00, 0.78, 0.14, 1)
        selected:Hide()

        local hover = itemHitFrame:CreateTexture(nil, "HIGHLIGHT")
        hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        hover:SetAllPoints(itemHitFrame)
        hover:SetVertexColor(0.80, 0.58, 0.18, 0.12)
        hover:SetBlendMode("ADD")

        local itemName = itemHitFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemName:SetPoint("BOTTOMLEFT", itemHitFrame, "BOTTOMLEFT", 5, 5)
        itemName:SetPoint("BOTTOMRIGHT", itemHitFrame, "BOTTOMRIGHT", -5, 5)
        itemName:SetHeight(18)
        itemName:SetJustifyH("CENTER")
        itemName:SetJustifyV("MIDDLE")

        local favorite = itemHitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        favorite:SetPoint("TOPLEFT", itemHitFrame, "TOPLEFT", 2, 3)
        favorite:SetText("★")
        favorite:SetTextColor(1.00, 0.82, 0.18)
        favorite:Hide()

        -- An explicit but unobtrusive state badge supplements the cool-gray
        -- uncollected border. It remains outside the model's focal area and
        -- avoids the muddy translucent rectangles used by the first version.
        local collectionState = CreateFrame("Frame", nil, itemHitFrame)
        collectionState:SetWidth(58)
        collectionState:SetHeight(15)
        collectionState:SetPoint("TOPRIGHT", itemHitFrame, "TOPRIGHT", -4, -4)
        collectionState:SetFrameLevel(itemHitFrame:GetFrameLevel() + 3)
        local collectionStateBackground = collectionState:CreateTexture(nil, "BACKGROUND")
        collectionStateBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        collectionStateBackground:SetAllPoints(collectionState)
        collectionStateBackground:SetVertexColor(0.02, 0.02, 0.02, 0.78)
        local collectionStateLabel = collectionState:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        collectionStateLabel:SetAllPoints(collectionState)
        collectionStateLabel:SetJustifyH("CENTER")
        collectionStateLabel:SetText("未收集")
        collectionStateLabel:SetTextColor(0.72, 0.73, 0.74)
        collectionState:Hide()

        itemModel:SetScript("OnUpdateModel", function(self)
            -- SetUnit/TryOn may finish after our first transform and silently
            -- restore the native full-body view. Force the same generation's
            -- relative framing to be applied again after every late rebuild.
            queueItemModelView(self, true)
        end)
        itemModel.scUpdateHandler = updatePendingItemModel
        itemObjectModel:SetScript("OnUpdateModel", function(self)
            applyStandaloneItemView(self)
            queueStandaloneItemTransform(self)
        end)
        itemHitFrame:SetScript("OnClick", function(_, button)
            if not itemModel.scRecord then return end
            if button == "RightButton" then
                Catalog.ToggleDemoFavorite("APPEARANCES", itemModel.scRecord.id)
                page:Refresh()
            elseif IsShiftKeyDown() then
                local record = itemModel.scRecord
                local equipmentSlot = EQUIPMENT_SLOT_BY_APPEARANCE_SLOT[record.slot]
                if not record.collected then
                    showAppearanceActionResult(false, "NOT_OWNED")
                elseif not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
                    showAppearanceActionResult(false, "BRIDGE_UNAVAILABLE")
                elseif equipmentSlot == nil then
                    showAppearanceActionResult(false, "INVALID_TARGET_SLOT")
                else
                    SC.Bridge.ApplyAppearance(record.id, equipmentSlot, showAppearanceActionResult)
                end
            else
                selectItem(itemModel.scRecord)
            end
        end)
        itemHitFrame:SetScript("OnEnter", function(self) showItemTooltip(self, itemModel.scRecord) end)
        itemHitFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        itemModel.scCard = itemCard
        itemModel.scObjectModel = itemObjectModel
        itemModel.scHitFrame = itemHitFrame
        itemModel.scBorder = border
        itemModel.scSelected = selected
        itemModel.scName = itemName
        itemModel.scFavorite = favorite
        itemModel.scCollectionState = collectionState
        itemCard:Hide()
        itemModel:Hide()
        page.scItemModels[index] = itemModel
    end

    local function getMaxSetOffset()
        return math.max(0, (page.scSetRecordCount or 0) - VISIBLE_SET_ROWS)
    end

    local function setSetOffset(value)
        local target = math.max(0, math.min(math.floor(tonumber(value) or 0), getMaxSetOffset()))
        if target == (page.scSetOffset or 0) then return end
        page.scSetOffset = target
        page.scSetPage = math.floor(target / VISIBLE_SET_ROWS) + 1
        page:Refresh()
    end

    local function scrollSetList(delta)
        if not delta or delta == 0 then return end
        setSetOffset((page.scSetOffset or 0) + (delta > 0 and -1 or 1))
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
    local setScrollbarBorder = createThinCardBorder(setScrollbar, 1)
    setScrollbarBorder:SetBorderColor(0.33, 0.34, 0.35, 0.62)

    setScrollbar:SetScript("OnValueChanged", function(self, value)
        if page.scSyncingSetScrollbar then return end
        local target = getMaxSetOffset() - math.floor((tonumber(value) or 0) + 0.5)
        if target ~= (page.scSetOffset or 0) then
            page.scSetOffset = math.max(0, math.min(target, getMaxSetOffset()))
            page.scSetPage = math.floor(page.scSetOffset / VISIBLE_SET_ROWS) + 1
            page:Refresh()
        end
    end)
    setScrollbar:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)
    setScrollbar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("套装列表", 1.00, 0.82, 0.18)
        GameTooltip:AddLine("拖动滚动条或使用鼠标滚轮浏览。", 0.82, 0.78, 0.70, true)
        GameTooltip:Show()
    end)
    setScrollbar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    setsPanel:EnableMouseWheel(true)
    setsPanel:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)

    for index = 1, VISIBLE_SET_ROWS do
        local row = createSetListRow(setsPanel, 330, function(_, record)
            page.scSetSelectedId = record and record.id or nil
            previewSet(record)
            for _, setRow in ipairs(page.scSetRows) do
                setRow:SetSelected(setRow.scRecord and setRow.scRecord.id == page.scSetSelectedId)
            end
        end)
        row:SetPoint("TOPLEFT", setsPanel, "TOPLEFT", 3, -((index - 1) * (SET_ROW_HEIGHT + SET_ROW_SPACING)))
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)
        page.scSetRows[index] = row
    end

    local itemControls = UI.CreatePageControls(itemsPanel, function()
        page.scItemPage = math.max(1, page.scItemPage - 1)
        page:Refresh()
    end, function()
        page.scItemPage = math.min(page.scItemTotalPages or 1, page.scItemPage + 1)
        page:Refresh()
    end)
    itemControls:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 0, 5)

    local setControls = UI.CreatePageControls(setsPanel, function()
        setSetOffset((page.scSetOffset or 0) - VISIBLE_SET_ROWS)
    end, function()
        setSetOffset((page.scSetOffset or 0) + VISIBLE_SET_ROWS)
    end)
    setControls:SetPoint("BOTTOM", setsPanel, "BOTTOM", 0, 5)

    local itemEmpty = UI.CreateEmptyState(itemsPanel, "没有符合条件的外观")
    itemEmpty:SetPoint("CENTER", itemsPanel, "CENTER", 0, 20)
    itemEmpty:Hide()
    local setEmpty = UI.CreateEmptyState(setsPanel, "没有符合条件的套装")
    setEmpty:SetPoint("CENTER", setsPanel, "CENTER", 0, 20)
    setEmpty:Hide()

    function page:ClearSelection()
        self.scItemSelectedId = nil
        self.scSetSelectedId = nil
        for _, itemModel in ipairs(self.scItemModels) do
            itemModel.scSelected:Hide()
        end
        for _, row in ipairs(self.scSetRows) do row:SetSelected(false) end
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
                self.scSetPage = 1
                self.scSetOffset = 0
                self.scSetSelectedId = nil
            end
        end

        if filters.armorType == "AUTO" or not hasFilterValue(ARMOR_TYPE_FILTERS, filters.armorType) then
            filters.armorType = getDefaultArmorType()
        end
        if filters.slot == "ALL" or not page.scSlotButtons[filters.slot] then
            filters.slot = "HEAD"
        end

        UIDropDownMenu_SetSelectedValue(armorDropdown, filters.armorType)
        UIDropDownMenu_SetText(armorDropdown, filterLabel(ARMOR_TYPE_FILTERS, filters.armorType))
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
        if not frame or not frame.scFilterPopup or not SC.db or SC.db.mainTab ~= "WARDROBE" then return end
        local filters = SC.db.filters
        local options = {
            { label = "已收集", checked = filters.collected, onClick = function()
                filters.collected = not filters.collected
                self.scItemPage = 1
                self.scSetPage = 1
                self.scSetOffset = 0
                self:Refresh()
            end },
            { label = "未收集", checked = filters.uncollected, onClick = function()
                filters.uncollected = not filters.uncollected
                self.scItemPage = 1
                self.scSetPage = 1
                self.scSetOffset = 0
                self:Refresh()
            end },
            { label = "仅显示偏好", checked = filters.favorites, onClick = function()
                filters.favorites = not filters.favorites
                self.scItemPage = 1
                self.scSetPage = 1
                self.scSetOffset = 0
                self:Refresh()
            end },
        }
        frame.scFilterPopup:SetOptions(options)
    end

    local function refreshItems()
        itemsPanel:Show()
        setsPanel:Hide()
        preview:Hide()
        if STANDALONE_ITEM_SLOTS[SC.db.filters.slot] then
            cameraTuningButton:Show()
        else
            cameraTuningPanel:Hide()
            cameraTuningButton:Hide()
        end
        local records, currentPage, totalPages = Catalog.Query("APPEARANCES", SC.db.query, SC.db.filters, page.scItemPage, ITEM_PAGE_SIZE)
        page.scItemPage = currentPage
        page.scItemTotalPages = totalPages
        itemControls:SetPage(currentPage, totalPages)
        local selected
        for index, itemModel in ipairs(page.scItemModels) do
            local record = records[index]
            applyItemModelRecord(itemModel, record)
            if record then
                itemModel.scName:SetText(record.name or "未知外观")
                if record.collected then
                    itemModel.scName:SetTextColor(1.00, 0.82, 0.18)
                    itemModel.scCollectionState:Hide()
                else
                    itemModel.scName:SetTextColor(0.62, 0.62, 0.60)
                    itemModel.scCollectionState:Show()
                end
                itemModel.scBorder:SetCollected(record.collected)
                if record.favorite then itemModel.scFavorite:Show() else itemModel.scFavorite:Hide() end
                if record.id == page.scItemSelectedId then selected = record end
            else
                itemModel.scName:SetText("")
                itemModel.scFavorite:Hide()
                itemModel.scCollectionState:Hide()
            end
            if record and record.id == page.scItemSelectedId then
                itemModel.scSelected:Show()
            else
                itemModel.scSelected:Hide()
            end
        end
        local collected, total = Catalog.GetProgress("APPEARANCES", SC.db.filters)
        if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(collected, total) end
        if #records == 0 then
            UI.ShowEmptyState(itemEmpty, page, "没有符合条件的外观", "调整搜索、护甲类型、部位或武器类型后再试。")
        else
            UI.HideEmptyState(itemEmpty)
            selectItem(selected or records[1])
        end
    end

    local function refreshSets()
        itemsPanel:Hide()
        -- The tuner applies only to standalone weapon PlayerModels. Do not
        -- leave its overlay or toggle visible above a DressUpModel set view.
        cameraTuningPanel:Hide()
        cameraTuningButton:Hide()
        -- A hidden DressUpModel can discard its temporary TryOn state while
        -- keeping our Lua-side record cache. Invalidate that cache whenever
        -- the set page takes over so returning to items always Undresses and
        -- reapplies the appearance instead of showing the player's gear.
        for _, itemModel in ipairs(page.scItemModels) do
            itemModel.scRecordId = nil
        end
        setsPanel:Show()
        preview:Show()
        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", setsPanel, "TOPRIGHT", 16, 0)
        preview:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        local setFilters = {}
        for key, value in pairs(SC.db.filters) do
            setFilters[key] = value
        end
        setFilters.slot = "ALL"
        local allRecords = Catalog.QueryAll("SETS", SC.db.query, setFilters)
        page.scSetRecordCount = #allRecords
        local maxOffset = math.max(0, #allRecords - VISIBLE_SET_ROWS)
        page.scSetOffset = math.max(0, math.min(math.floor(page.scSetOffset or 0), maxOffset))

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
        -- A vertical Slider's maximum value sits at the top. Reverse the data
        -- offset so zero records skipped corresponds to a top-positioned thumb.
        setScrollbar:SetValue(maxOffset - page.scSetOffset)
        setScrollbar:SetAlpha(maxOffset > 0 and 1.00 or 0.28)
        page.scSyncingSetScrollbar = nil

        local selected
        for _, record in ipairs(allRecords) do
            if record.id == page.scSetSelectedId then
                selected = record
                break
            end
        end
        for index, row in ipairs(page.scSetRows) do
            local record = records[index]
            row:SetRecord(record)
            row:SetSelected(record and record.id == page.scSetSelectedId)
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
            for _, row in ipairs(page.scSetRows) do row:SetSelected(row.scRecord and row.scRecord.id == record.id) end
        end
    end

    function page:Refresh()
        if not SC.db then return end
        self:SyncDedicatedFilters()
        if SC.db.wardrobeTab == "ITEMS" then
            refreshItems()
        elseif SC.db.wardrobeTab == "SETS" then
            refreshSets()
        end
        self:SyncFilters()
    end

    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:SetScript("OnEvent", function(self, event, ...)
        if not self:IsShown() then return end
        local itemId, success = ...
        if success == false or not itemId then return end
        itemId = tonumber(itemId) or itemId

        for _, itemModel in ipairs(self.scItemModels) do
            if itemModel.scCard and itemModel.scCard:IsShown()
                and itemModel.scRecord and itemModel.scRecord.itemId == itemId then
                itemModel.scRecordId = nil
                applyItemModelRecord(itemModel, itemModel.scRecord)
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
        self:ClearSelection()
        self.scItemPage = 1
        self.scSetPage = 1
        self.scSetOffset = 0
        self.scSetRecordCount = 0
        for _, itemModel in ipairs(self.scItemModels) do
            itemModel.scRecord = nil
            itemModel.scRecordId = nil
            itemModel.scProfile = nil
            itemModel.scClientCameraSentinel = nil
            itemModel.scUsesClientCamera = nil
            itemModel.scPendingItemString = nil
            itemModel.scModelReadyFrames = nil
            itemModel.scApplyingAppearance = nil
            itemModel.scAppearanceGeneration = nil
            itemModel.scViewAppliedGeneration = nil
            itemModel.scViewStage = nil
            itemModel.scViewFrames = nil
            itemModel.scApplyingView = nil
            itemModel.scNativeScale = nil
            itemModel.scNativeHorizontal = nil
            itemModel.scNativeVertical = nil
            itemModel.scNativeDepth = nil
            itemModel.scBaselineGeneration = nil
            itemModel.scRenderKind = nil
            itemModel:SetScript("OnUpdate", nil)
            itemModel:ClearModel()
            itemModel:Hide()
            applyStandaloneItemRecord(itemModel.scObjectModel, nil)
            if itemModel.scCard then itemModel.scCard:Hide() end
        end
        model:ClearModel()
        GameTooltip:Hide()
    end)

    page.scModel = model
    page.scItemsPanel = itemsPanel
    page.scSetsPanel = setsPanel
    page.scItemControls = itemControls
    page.scSetControls = setControls
    page.scSetScrollbar = setScrollbar
    page.scArmorDropdown = armorDropdown
    page.scClassDropdown = classDropdown
    page.scWeaponDropdown = weaponDropdown
    page.scSlotsFrame = slotsFrame
    return page
end
