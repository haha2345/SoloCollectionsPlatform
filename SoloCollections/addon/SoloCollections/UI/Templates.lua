local SC = SoloCollections

SC.UI = SC.UI or {}

local UI = SC.UI
local MEDIA_ROOT = "Interface\\AddOns\\SoloCollections\\Media\\"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

local function platformPublic()
    local platform = SC.UIPlatform
    if platform and platform:IsDragonUIShell() then return platform:GetPublic() end
    return nil
end

function UI.IsDragonUIShell()
    return platformPublic() ~= nil
end

function UI.CreateInset(parent, options)
    local inset = CreateFrame("Frame", nil, parent)
    inset:SetPoint("TOPLEFT", parent, "TOPLEFT", (options and options.left) or 0, -((options and options.top) or 0))
    inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -((options and options.right) or 0), (options and options.bottom) or 0)
    UI.ApplyNineSlice(inset, UI.Media.border, 16)
    return inset
end

UI.Media = {
    background = MEDIA_ROOT .. "Backgrounds\\collection-bg.tga",
    border = MEDIA_ROOT .. "Borders\\collection-border.tga",
    collectedFrame = MEDIA_ROOT .. "Borders\\collected-frame.tga",
    uncollectedFrame = MEDIA_ROOT .. "Borders\\uncollected-frame.tga",
    launcher = MEDIA_ROOT .. "Icons\\launcher.tga",
    collectionsLauncher = MEDIA_ROOT .. "Icons\\collections-micro.tga",
    mountPortrait = MEDIA_ROOT .. "Icons\\mount-portrait.tga",
    wardrobeSlotAtlas = MEDIA_ROOT .. "Icons\\WardrobeSlots\\slot-atlas.tga",
    roundHighlightAtlas = MEDIA_ROOT .. "Icons\\WardrobeSlots\\round-highlight.tga",
    stock = {
        searchLeft = "Interface\\FriendsFrame\\UI-SearchBoxBG-left",
        searchMiddle = "Interface\\FriendsFrame\\UI-SearchBoxBG-mid",
        searchRight = "Interface\\FriendsFrame\\UI-SearchBoxBG-right",
        searchIcon = "Interface\\Common\\UI-Searchbox-Icon",
        progressFill = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
        progressBorder = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder",
        tabInactive = "Interface\\HelpFrame\\HelpFrameTab-Inactive",
        tabActive = "Interface\\HelpFrame\\HelpFrameTab-Active",
        tabHighlight = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
    },
    tabs = {
        MOUNTS = MEDIA_ROOT .. "Tabs\\mounts.tga",
        PETS = MEDIA_ROOT .. "Tabs\\pets.tga",
        TOYS = MEDIA_ROOT .. "Tabs\\toys.tga",
        WARDROBE = MEDIA_ROOT .. "Tabs\\wardrobe.tga",
    },
}

local COLORS = {
    gold = { 1.00, 0.82, 0.20 },
    parchment = { 0.075, 0.055, 0.04, 0.98 },
    bronze = { 0.30, 0.22, 0.13 },
    cream = { 0.90, 0.83, 0.69 },
    muted = { 0.50, 0.47, 0.42 },
}

local BUTTON_TEXTURES = {
    previous = {
        normal = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
        pushed = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
    },
    next = {
        normal = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
        pushed = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
    },
}

local function setAllPoints(texture, owner, inset)
    inset = inset or 0
    texture:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
end

local function createSolidTexture(owner, layer, r, g, b, a)
    local texture = owner:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture(WHITE_TEXTURE)
    texture:SetVertexColor(r, g, b, a or 1)
    return texture
end

local function createLabel(owner, font, text, color)
    local label = owner:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    label:SetText(text or "")
    if color then
        label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    return label
end

local function registerSpecialFrameOnce(frameName)
    if not UISpecialFrames then
        return
    end
    for _, registeredName in ipairs(UISpecialFrames) do
        if registeredName == frameName then
            return
        end
    end
    table.insert(UISpecialFrames, frameName)
end

function UI.MediaPath(relativePath)
    return MEDIA_ROOT .. relativePath
end

function UI.SetFallbackTexture(texture)
    if texture then
        texture:SetTexture(FALLBACK_TEXTURE)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(0.72, 0.66, 0.54, 1)
    end
end

function UI.SetIconTexture(texture, path)
    if not texture then
        return
    end
    if path and path ~= "" then
        texture:SetTexture(path)
        texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        texture:SetVertexColor(1, 1, 1, 1)
    else
        UI.SetFallbackTexture(texture)
    end
end

function UI.SetCollectedVisual(texture, collected, uncollectedAlpha)
    if not texture then
        return
    end
    SetDesaturation(texture, not collected)
    if uncollectedAlpha then
        texture:SetAlpha(collected and 1 or uncollectedAlpha)
    end
end

function UI.CreateThinCardBorder(parent, thickness)
    local border = CreateFrame("Frame", nil, parent)
    border:SetAllPoints(parent)
    border:SetFrameLevel(parent:GetFrameLevel() + 1)

    local size = thickness or 1
    local top = border:CreateTexture(nil, "OVERLAY")
    top:SetTexture(WHITE_TEXTURE)
    top:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    top:SetHeight(size)

    local bottom = border:CreateTexture(nil, "OVERLAY")
    bottom:SetTexture(WHITE_TEXTURE)
    bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(size)

    local left = border:CreateTexture(nil, "OVERLAY")
    left:SetTexture(WHITE_TEXTURE)
    left:SetPoint("TOPLEFT", border, "TOPLEFT", 0, -size)
    left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, size)
    left:SetWidth(size)

    local right = border:CreateTexture(nil, "OVERLAY")
    right:SetTexture(WHITE_TEXTURE)
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
            self:SetBorderColor(0.38, 0.39, 0.40, 1)
        end
    end

    return border
end

function UI.CreateCollectionCardBorders(parent)
    local collection = UI.CreateThinCardBorder(parent, 1)
    collection:SetCollected(false)
    local selected = UI.CreateThinCardBorder(parent, 2)
    selected:SetBorderColor(1.00, 0.78, 0.14, 1)
    selected:Hide()
    return collection, selected
end

-- The source image contains a complete 128px journal border. These nine
-- sampled regions remain crisp when the frame is resized by the page shell.
function UI.ApplyNineSlice(owner, texturePath, size)
    texturePath = texturePath or UI.Media.border
    size = size or 28

    local slices = {}
    local function part(key, left, right, top, bottom)
        local texture = owner:CreateTexture(nil, "BORDER")
        texture:SetTexture(texturePath)
        texture:SetTexCoord(left, right, top, bottom)
        texture:SetVertexColor(0.43, 0.36, 0.26, 1)
        slices[key] = texture
        return texture
    end

    local topLeft = part("topLeft", 0, 0.25, 0, 0.25)
    topLeft:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    topLeft:SetWidth(size)
    topLeft:SetHeight(size)

    local topRight = part("topRight", 0.75, 1, 0, 0.25)
    topRight:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
    topRight:SetWidth(size)
    topRight:SetHeight(size)

    local bottomLeft = part("bottomLeft", 0, 0.25, 0.75, 1)
    bottomLeft:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
    bottomLeft:SetWidth(size)
    bottomLeft:SetHeight(size)

    local bottomRight = part("bottomRight", 0.75, 1, 0.75, 1)
    bottomRight:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
    bottomRight:SetWidth(size)
    bottomRight:SetHeight(size)

    local top = part("top", 0.25, 0.75, 0, 0.25)
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT", 0, 0)
    top:SetHeight(size)

    local bottom = part("bottom", 0.25, 0.75, 0.75, 1)
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
    bottom:SetHeight(size)

    local left = part("left", 0, 0.25, 0.25, 0.75)
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
    left:SetWidth(size)

    local right = part("right", 0.75, 1, 0.25, 0.75)
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 0, 0)
    right:SetWidth(size)

    local center = part("center", 0.25, 0.75, 0.25, 0.75)
    center:SetPoint("TOPLEFT", topLeft, "BOTTOMRIGHT", 0, 0)
    center:SetPoint("BOTTOMRIGHT", bottomRight, "TOPLEFT", 0, 0)
    center:SetAlpha(0.07)

    owner.scNineSlice = slices
    return slices
end

local YAHEI_BOLD_PATHS = {
    "Interface\\AddOns\\SoloCollections\\Media\\Fonts\\msyhbd.ttf",
    "Fonts\\msyhbd.ttf",
    "Fonts\\msyh.ttf",
}

local function applyYaHeiBold(fontString, size)
    if not (fontString and fontString.SetFont) then
        return
    end
    size = size or 12
    for _, path in ipairs(YAHEI_BOLD_PATHS) do
        local ok = pcall(function()
            fontString:SetFont(path, size, "")
        end)
        if ok and fontString.GetFont then
            local used = fontString:GetFont()
            if type(used) == "string" and used:lower():find("msyh", 1, true) then
                return
            end
        end
    end
    if STANDARD_TEXT_FONT then
        pcall(function()
            fontString:SetFont(STANDARD_TEXT_FONT, size, "")
        end)
    end
end

function UI.AttachAuthorCredit(frame)
    if not frame or frame.scAuthorCredit then
        return frame and frame.scAuthorCredit
    end
    local host = CreateFrame("Frame", nil, frame)
    host:SetSize(220, 16)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 8)
    host:SetFrameLevel(frame:GetFrameLevel() + 80)
    host:EnableMouse(false)
    local credit = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    credit:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    credit:SetJustifyH("RIGHT")
    applyYaHeiBold(credit, 12)
    credit:SetText("本项目由woden开发")
    credit:SetTextColor(1, 1, 1)
    frame.scAuthorCredit = credit
    frame.scAuthorCreditHost = host
    return credit
end

function UI.CreateJournalFrame(parent, name, width, height, options)
    options = type(options) == "table" and options or {}
    local titleText = options.title or "收藏"
    local portraitPath = options.portrait or UI.Media.mountPortrait
    local frame = CreateFrame("Frame", name, parent or UIParent)
    frame:SetWidth(width or 920)
    frame:SetHeight(height or 793)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    local public = platformPublic()
    if public then
        public.Chrome:Apply(frame, {
            layout = "PortraitFrameTemplate",
            title = titleText,
            portrait = portraitPath,
            portraitOpts = {
                -- Match ezCollections' PortraitFrameTemplate geometry. The
                -- native SetPortraitToTexture call supplies the round crop.
                size = 60,
                anchor = { "TOPLEFT", -5, 8 },
                mask = false,
            },
        })
        if frame.Bg and frame.Bg.Hide then frame.Bg:Hide() end
        frame.scBackground = UI.EzCollections and UI.EzCollections:CreateBodyCanvas(frame) or frame.Bg
        frame.scHeaderBackground = frame.TitleContainer or frame.TitleBand
        frame.scPlatformShell = "DRAGONUI"
        UI.AttachAuthorCredit(frame)
        return frame
    end

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.035, 0.035, 0.032, 0.99)
    frame:SetBackdropBorderColor(0.40, 0.40, 0.38, 1)

    local shadow = createSolidTexture(frame, "BACKGROUND", 0, 0, 0, 0.66)
    shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -6)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 7, -9)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(UI.Media.background)
    background:SetHorizTile(true)
    background:SetVertTile(true)
    setAllPoints(background, frame, 8)
    background:SetVertexColor(0.18, 0.17, 0.15, 0.88)

    local innerShade = createSolidTexture(frame, "ARTWORK", 0.016, 0.016, 0.015, 0.58)
    setAllPoints(innerShade, frame, 9)

    local header = createSolidTexture(frame, "ARTWORK", 1, 1, 1, 1)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    header:SetHeight(44)
    header:SetGradientAlpha("VERTICAL", 0.075, 0.078, 0.078, 0.98, 0.19, 0.19, 0.18, 0.98)
    local headerLine = createSolidTexture(frame, "OVERLAY", 0.43, 0.43, 0.40, 0.82)
    headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)

    frame.scBackground = background
    frame.scInnerShade = innerShade
    frame.scHeaderBackground = header
    frame.scHeaderLine = headerLine
    if UI.EzCollections then
        background:Hide()
        frame.scBackground = UI.EzCollections:CreateBodyCanvas(frame)
    end
    UI.AttachAuthorCredit(frame)
    return frame
end

function UI.CreateThreeSlice(parent, leftTexture, middleTexture, rightTexture, height, leftWidth, rightWidth)
    height = height or 28
    leftWidth = leftWidth or height
    rightWidth = rightWidth or leftWidth

    local left = parent:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(leftTexture)
    left:SetWidth(leftWidth)
    left:SetHeight(height)
    left:SetPoint("LEFT", parent, "LEFT", 0, 0)

    local right = parent:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(rightTexture)
    right:SetWidth(rightWidth)
    right:SetHeight(height)
    right:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local middle = parent:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(middleTexture)
    middle:SetHeight(height)
    middle:SetPoint("LEFT", left, "RIGHT", 0, 0)
    middle:SetPoint("RIGHT", right, "LEFT", 0, 0)
    middle:SetHorizTile(true)

    return {
        scLeft = left,
        scMiddle = middle,
        scRight = right,
    }
end

function UI.CreateRetailBottomTab(parent, labelText, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(128)
    button:SetHeight(40)
    button:RegisterForClicks("LeftButtonUp")

    -- HelpFrame tab artwork only provides the metal edge. The journal tabs
    -- live outside the main frame, so they also need an opaque base or the
    -- game world shows through the transparent middle of the stock texture.
    local inactiveFill = createSolidTexture(button, "BACKGROUND", 0.035, 0.028, 0.018, 1)
    inactiveFill:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    inactiveFill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -7, 5)
    inactiveFill:SetGradientAlpha("VERTICAL", 0.025, 0.021, 0.016, 1, 0.13, 0.085, 0.028, 1)

    local inactiveChrome = UI.CreateThreeSlice(
        button,
        UI.Media.stock.tabInactive,
        UI.Media.stock.tabInactive,
        UI.Media.stock.tabInactive,
        40,
        16,
        16
    )
    inactiveChrome.scLeft:SetTexCoord(0, 0.25, 0, 1)
    inactiveChrome.scMiddle:SetTexCoord(0.25, 0.75, 0, 1)
    inactiveChrome.scRight:SetTexCoord(0.75, 1, 0, 1)
    inactiveChrome.scLeft:SetVertexColor(0.64, 0.59, 0.49, 0.96)
    inactiveChrome.scMiddle:SetVertexColor(0.64, 0.59, 0.49, 0.96)
    inactiveChrome.scRight:SetVertexColor(0.64, 0.59, 0.49, 0.96)

    local activeChrome = UI.CreateThreeSlice(
        button,
        UI.Media.stock.tabActive,
        UI.Media.stock.tabActive,
        UI.Media.stock.tabActive,
        40,
        16,
        16
    )
    activeChrome.scLeft:SetTexCoord(0, 0.25, 0, 1)
    activeChrome.scMiddle:SetTexCoord(0.25, 0.75, 0, 1)
    activeChrome.scRight:SetTexCoord(0.75, 1, 0, 1)
    activeChrome.scLeft:SetVertexColor(1, 0.82, 0.30, 1)
    activeChrome.scMiddle:SetVertexColor(1, 0.82, 0.30, 1)
    activeChrome.scRight:SetVertexColor(1, 0.82, 0.30, 1)
    activeChrome.scLeft:Hide()
    activeChrome.scMiddle:Hide()
    activeChrome.scRight:Hide()

    local selectedGradient = createSolidTexture(button, "ARTWORK", 1, 1, 1, 1)
    selectedGradient:SetPoint("TOPLEFT", button, "TOPLEFT", 9, -7)
    selectedGradient:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -9, 7)
    selectedGradient:SetGradientAlpha("VERTICAL", 0.23, 0.095, 0.012, 0.95, 0.92, 0.55, 0.055, 0.82)
    selectedGradient:Hide()

    local edgeTextures = {}
    local function edge(pointA, relativePointA, xA, yA, pointB, relativePointB, xB, yB)
        local texture = createSolidTexture(button, "OVERLAY", 0.30, 0.22, 0.11, 1)
        texture:SetPoint(pointA, button, relativePointA, xA, yA)
        texture:SetPoint(pointB, button, relativePointB, xB, yB)
        table.insert(edgeTextures, texture)
        return texture
    end
    local topEdge = edge("TOPLEFT", "TOPLEFT", 9, -5, "TOPRIGHT", "TOPRIGHT", -9, -5)
    topEdge:SetHeight(1)
    local bottomEdge = edge("BOTTOMLEFT", "BOTTOMLEFT", 9, 5, "BOTTOMRIGHT", "BOTTOMRIGHT", -9, 5)
    bottomEdge:SetHeight(1)
    local leftEdge = edge("TOPLEFT", "TOPLEFT", 7, -6, "BOTTOMLEFT", "BOTTOMLEFT", 7, 6)
    leftEdge:SetWidth(1)
    local rightEdge = edge("TOPRIGHT", "TOPRIGHT", -7, -6, "BOTTOMRIGHT", "BOTTOMRIGHT", -7, 6)
    rightEdge:SetWidth(1)

    local label = createLabel(button, "GameFontNormal", labelText, COLORS.gold)
    label:SetPoint("CENTER", button, "CENTER", 0, 1)

    local connectionGlow = createSolidTexture(button, "OVERLAY", 1, 0.74, 0.14, 0.95)
    connectionGlow:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 11, 4)
    connectionGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -11, 4)
    connectionGlow:SetHeight(3)
    connectionGlow:Hide()

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 9, -7)
    highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -9, 7)
    highlight:SetVertexColor(1, 0.68, 0.16, 0.16)
    highlight:SetBlendMode("ADD")

    button:SetScript("OnClick", function(self)
        if onClick then
            onClick(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not self.scSelected then
            label:SetTextColor(1, 0.93, 0.58)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if not self.scSelected then
            label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        end
    end)
    function button:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then
            inactiveChrome.scLeft:Hide()
            inactiveChrome.scMiddle:Hide()
            inactiveChrome.scRight:Hide()
            activeChrome.scLeft:Show()
            activeChrome.scMiddle:Show()
            activeChrome.scRight:Show()
            selectedGradient:Show()
            connectionGlow:Show()
            for _, texture in ipairs(edgeTextures) do
                texture:SetVertexColor(0.92, 0.61, 0.12, 1)
            end
            label:SetTextColor(1, 1, 0.72)
        else
            activeChrome.scLeft:Hide()
            activeChrome.scMiddle:Hide()
            activeChrome.scRight:Hide()
            inactiveChrome.scLeft:Show()
            inactiveChrome.scMiddle:Show()
            inactiveChrome.scRight:Show()
            selectedGradient:Hide()
            connectionGlow:Hide()
            for _, texture in ipairs(edgeTextures) do
                texture:SetVertexColor(0.30, 0.22, 0.11, 1)
            end
            label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        end
    end

    button.scLabel = label
    button.scInactiveChrome = inactiveChrome
    button.scActiveChrome = activeChrome
    button.scInactiveFill = inactiveFill
    button.scEdgeTextures = edgeTextures
    button.scSelectedTexture = selectedGradient
    button.scSelectedLine = connectionGlow
    return button
end

function UI.CreateBottomTab(parent, labelText, iconPath, onClick)
    -- V3 intentionally uses Retail-style text-only journal tabs. Keep the
    -- legacy iconPath argument in the public signature for older callers;
    -- the tab icon media remains available to other legacy page controls.
    return UI.CreateRetailBottomTab(parent, labelText, onClick)
end

function UI.CreateTopSubTab(parent, labelText, onClick)
    UI.scWardrobeTabSerial = (UI.scWardrobeTabSerial or 0) + 1
    local name = "SoloCollectionsWardrobeTab" .. UI.scWardrobeTabSerial
    local button = CreateFrame("Button", name, parent, "TabButtonTemplate")
    button:SetID(UI.scWardrobeTabSerial)
    button:SetText(labelText or "")
    button.minWidth = 57
    if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 0, nil) end

    -- Blizzard_Wardrobe.xml keeps at least 57 pixels for the stretchable
    -- middle piece after PanelTemplates_TabResize.  This is the exact
    -- ezCollections item/set tab composition, not OptionsFrame chrome.
    local left = button.Left or _G[name .. "Left"]
    local middle = button.Middle or _G[name .. "Middle"]
    local middleDisabled = button.MiddleDisabled or _G[name .. "MiddleDisabled"]
    local sideWidth = left and (2 * left:GetWidth()) or 32
    if button:GetWidth() - sideWidth < button.minWidth then
        local tabWidth = button.minWidth + sideWidth
        if middle then middle:SetWidth(button.minWidth) end
        if middleDisabled then middleDisabled:SetWidth(button.minWidth) end
        button:SetWidth(tabWidth)
        local highlight = button.HighlightTexture or _G[name .. "HighlightTexture"]
        if highlight then highlight:SetWidth(tabWidth) end
    end

    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
        if PlaySound then PlaySound("igCharacterInfoTab") end
    end)
    function button:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then
            if PanelTemplates_SelectTab then PanelTemplates_SelectTab(self) else self:Disable() end
        else
            if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(self) else self:Enable() end
        end
    end
    button.scLabel = button.Text or _G[name .. "Text"]
    button.scEzCollectionsWardrobeTab = true
    return button
end

function UI.CreateRetailSearchBox(parent, width, onTextChanged)
    local editBox = CreateFrame("EditBox", nil, parent)
    editBox:SetWidth(width or 220)
    editBox:SetHeight(20)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetTextInsets(24, 21, 0, 0)
    editBox:SetMaxLetters(60)

    local chrome = UI.CreateThreeSlice(
        editBox,
        UI.Media.stock.searchLeft,
        UI.Media.stock.searchMiddle,
        UI.Media.stock.searchRight,
        20,
        13,
        13
    )

    local icon = editBox:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(UI.Media.stock.searchIcon)
    icon:SetWidth(14)
    icon:SetHeight(14)
    icon:SetPoint("LEFT", editBox, "LEFT", 6, 0)

    local placeholder = createLabel(editBox, "GameFontDisableSmall", "搜索")
    placeholder:SetPoint("LEFT", editBox, "LEFT", 24, 0)

    local clear = CreateFrame("Button", nil, editBox)
    clear:SetWidth(17)
    clear:SetHeight(17)
    clear:SetPoint("RIGHT", editBox, "RIGHT", -3, 0)
    clear:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    clear:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    clear:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
    end)
    clear:Hide()

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        local hasText = self:GetText() ~= ""
        if hasText then
            placeholder:Hide()
            clear:Show()
        else
            placeholder:Show()
            clear:Hide()
        end
        if onTextChanged then
            onTextChanged(self:GetText(), self)
        end
    end)

    editBox.scChrome = chrome
    editBox.scIcon = icon
    editBox.scPlaceholder = placeholder
    editBox.scClearButton = clear
    return editBox
end

function UI.CreateSearchBox(parent, width, onTextChanged)
    return UI.CreateRetailSearchBox(parent, width, onTextChanged)
end

function UI.CreateFilterPopup(parent, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width or 112)
    button:SetHeight(28)
    local buttonBackground = createSolidTexture(button, "BACKGROUND", 0.05, 0.05, 0.047, 0.98)
    setAllPoints(buttonBackground, button, 1)
    local buttonBorder = createSolidTexture(button, "BORDER", 0.40, 0.34, 0.24, 0.90)
    setAllPoints(buttonBorder, button, 0)
    local buttonInner = createSolidTexture(button, "ARTWORK", 0.035, 0.035, 0.032, 1)
    setAllPoints(buttonInner, button, 2)
    local buttonLabel = createLabel(button, "GameFontNormalSmall", "过滤器", COLORS.gold)
    buttonLabel:SetPoint("CENTER", button, "CENTER", -7, 0)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetWidth(14)
    arrow:SetHeight(14)
    arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)

    UI.scFilterPopupSerial = (UI.scFilterPopupSerial or 0) + 1
    local serial = UI.scFilterPopupSerial
    local popupName = "SoloCollectionsFilterPopup" .. serial
    local dismissName = "SoloCollectionsFilterDismiss" .. serial

    local dismiss = CreateFrame("Button", dismissName, UIParent)
    dismiss:SetAllPoints(UIParent)
    dismiss:SetFrameStrata("DIALOG")
    dismiss:EnableMouse(true)
    dismiss:Hide()

    local popup = CreateFrame("Frame", popupName, parent)
    popup:SetWidth(190)
    popup:SetHeight(48)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
    local background = createSolidTexture(popup, "BACKGROUND", 0.025, 0.025, 0.02, 0.97)
    setAllPoints(background, popup, 0)
    UI.ApplyNineSlice(popup, UI.Media.border, 16)
    popup:Hide()
    popup.scRows = {}

    dismiss:SetScript("OnClick", function()
        popup:Hide()
    end)
    popup:SetScript("OnShow", function()
        if UI.scActiveFilterPopup and UI.scActiveFilterPopup ~= popup then
            UI.scActiveFilterPopup:Hide()
        end
        UI.scActiveFilterPopup = popup
        dismiss:Show()
        arrow:SetTexCoord(0, 1, 1, 0)
    end)
    popup:SetScript("OnHide", function()
        if UI.scActiveFilterPopup == popup then
            UI.scActiveFilterPopup = nil
        end
        dismiss:Hide()
        arrow:SetTexCoord(0, 1, 0, 1)
    end)
    registerSpecialFrameOnce(popupName)

    function popup:SetOptions(options)
        for _, row in ipairs(self.scRows) do
            row:Hide()
        end
        local count = 0
        for index, option in ipairs(options or {}) do
            local row = self.scRows[index]
            if not row then
                row = CreateFrame("Button", nil, self)
                row:SetHeight(24)
                row:SetPoint("LEFT", self, "LEFT", 12, 0)
                row:SetPoint("RIGHT", self, "RIGHT", -12, 0)
                row.check = row:CreateTexture(nil, "ARTWORK")
                row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                row.check:SetWidth(20)
                row.check:SetHeight(20)
                row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.label = createLabel(row, "GameFontHighlightSmall", "", COLORS.cream)
                row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                self.scRows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -12 - ((index - 1) * 24))
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -12, -12 - ((index - 1) * 24))
            row.label:SetText(option.label or "")
            if option.checked then row.check:Show() else row.check:Hide() end
            local optionRef = option
            row:SetScript("OnClick", function()
                if optionRef.onClick then optionRef.onClick(optionRef) end
            end)
            row:Show()
            count = index
        end
        self:SetHeight(math.max(48, 24 + count * 24))
    end

    button:SetScript("OnClick", function(self)
        local wardrobeDropDown = self.scWardrobeDropDown
        if wardrobeDropDown and ToggleDropDownMenu then
            popup:Hide()
            arrow:SetTexCoord(0, 1, 0, 1)
            if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
            ToggleDropDownMenu(1, nil, wardrobeDropDown, self, 74, 15)
            return
        end
        if popup:IsShown() then
            popup:Hide()
        else
            popup:Show()
        end
    end)
    popup.scButton = button
    button.scPopup = popup
    button.scLabel = buttonLabel
    button.scArrow = arrow
    button.scBackground = buttonBackground
    button.scBorder = buttonBorder
    button.scInner = buttonInner
    function button:SetWardrobeDropDown(dropDown)
        self.scWardrobeDropDown = dropDown
    end
    return button, popup
end

function UI.RefreshDropDownCheckMarks()
    -- 3.3.5 UIDropDownMenu_Refresh does not re-run function-style info.checked.
    if not UIDROPDOWNMENU_MAXBUTTONS then return end
    for level = 1, 2 do
        for index = 1, UIDROPDOWNMENU_MAXBUTTONS do
            local button = _G["DropDownList" .. level .. "Button" .. index]
            local check = _G["DropDownList" .. level .. "Button" .. index .. "Check"]
            if button and check then
                local checked = button:IsShown() and type(button.checked) == "function"
                    and button.checked()
                if checked then check:Show() else check:Hide() end
            end
        end
    end
end

function UI.GetAppearanceSourceFilters()
    if not SC.db then return nil end
    SC.db.filters = SC.db.filters or {}
    SC.db.filters.appearances = SC.db.filters.appearances or {}
    local filters = SC.db.filters.appearances
    if type(filters.hiddenSources) ~= "table" then
        filters.hiddenSources = {}
    end
    return filters
end

local function playerClassFilterToken()
    local Identity = SC.IdentityRegistry
    local classIdentity = Identity and Identity.GetPlayerClass and Identity.GetPlayerClass()
    local token = classIdentity and classIdentity.known and classIdentity.filterToken
    if not token then return nil end
    local options = Identity.GetClassFilterOptions and Identity.GetClassFilterOptions() or {}
    for _, option in ipairs(options) do
        if option.key == token then
            return token
        end
    end
    return nil
end

function UI.EnsureDefaultSetClassFilter()
    if UI.scSetClassDefaultApplied then return false end
    if not (SC.db and SC.db.filters) then return false end
    UI.scSetClassDefaultApplied = true
    if SC.db.filters.classToken and SC.db.filters.classToken ~= "ALL" then
        return false
    end
    local token = playerClassFilterToken()
    if not token then return false end
    SC.db.filters.classToken = token
    return true
end

function UI.ApplyTransmogOpenFilters()
    if not (SC.db and SC.db.filters) then return false end
    local changed = false
    local token = playerClassFilterToken()
    if token and SC.db.filters.classToken ~= token then
        SC.db.filters.classToken = token
        changed = true
    end
    -- AUTO tracks the equipped item's armor class per slot; forcing the
    -- class's endgame armor type here would hide low-level appearances the
    -- server actually accepts.
    if SC.db.filters.armorType ~= "AUTO" then
        SC.db.filters.armorType = "AUTO"
        changed = true
    end
    return changed
end

function UI.AddCollectedStateMenuButtons(level, onChanged)
    if not (SC.db and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton) then
        return
    end
    SC.db.filters = SC.db.filters or {}
    local filters = SC.db.filters
    local options = {
        { key = "collected", label = "已收集" },
        { key = "uncollected", label = "未收集" },
    }
    for _, option in ipairs(options) do
        local key = option.key
        local info = UIDropDownMenu_CreateInfo()
        info.isNotRadio = true
        info.keepShownOnClick = true
        info.text = option.label
        info.checked = function()
            return filters[key] ~= false
        end
        info.func = function(_, _, _, checked)
            if checked == nil then
                checked = not (filters[key] ~= false)
            end
            filters[key] = checked and true or false
            if onChanged then onChanged() end
            UI.RefreshDropDownCheckMarks()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

function UI.AddAppearanceSourceMenuButtons(level, onChanged)
    local kinds = SC.Catalog and SC.Catalog.APPEARANCE_SOURCE_KINDS
    if not (kinds and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton) then
        return
    end
    local function sourceFilters()
        return UI.GetAppearanceSourceFilters()
    end

    local all = UIDropDownMenu_CreateInfo()
    all.notCheckable = true
    all.keepShownOnClick = true
    all.text = "全部勾选"
    all.func = function()
        local filters = sourceFilters()
        if filters then filters.hiddenSources = {} end
        if onChanged then onChanged() end
        UI.RefreshDropDownCheckMarks()
    end
    UIDropDownMenu_AddButton(all, level)

    local none = UIDropDownMenu_CreateInfo()
    none.notCheckable = true
    none.keepShownOnClick = true
    none.text = "全部取消"
    none.func = function()
        local filters = sourceFilters()
        if filters then
            local hidden = {}
            for _, kind in ipairs(kinds) do
                hidden[kind.key] = true
            end
            filters.hiddenSources = hidden
        end
        if onChanged then onChanged() end
        UI.RefreshDropDownCheckMarks()
    end
    UIDropDownMenu_AddButton(none, level)

    for _, kind in ipairs(kinds) do
        local key = kind.key
        local info = UIDropDownMenu_CreateInfo()
        info.isNotRadio = true
        info.keepShownOnClick = true
        info.text = kind.label
        info.checked = function()
            local filters = sourceFilters()
            local hidden = filters and filters.hiddenSources
            return not (hidden and hidden[key])
        end
        info.func = function(_, _, _, checked)
            local filters = sourceFilters()
            if not filters then return end
            local hidden = filters.hiddenSources
            if checked == nil then
                checked = not hidden[key]
            end
            if checked then
                hidden[key] = nil
            else
                hidden[key] = true
            end
            if onChanged then onChanged() end
            UI.RefreshDropDownCheckMarks()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

function UI.CreateRetailProgressBar(parent, width)
    local barWidth = width or 330
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(barWidth + 9)
    holder:SetHeight(27)

    -- This is the stock 3.3.5 skills-bar composition: a 14px StatusBar
    -- inside the complete 27px border texture. Treating that border as a
    -- stretchable three-slice is what previously let the fill escape it.
    local statusBar = CreateFrame("StatusBar", nil, holder)
    statusBar:SetWidth(barWidth)
    statusBar:SetHeight(14)
    statusBar:SetPoint("CENTER", holder, "CENTER", 0, 0)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:SetStatusBarTexture(UI.Media.stock.progressFill)
    statusBar:SetStatusBarColor(0.12, 0.68, 0.10, 1)

    local background = statusBar:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    setAllPoints(background, statusBar, 0)
    background:SetVertexColor(0.018, 0.026, 0.018, 1)

    -- Textures on the holder render below its child StatusBar in 3.3.5.
    -- Put both the border and label on a higher child frame so the green
    -- fill cannot cover either one.
    local borderHost = CreateFrame("Frame", nil, holder)
    borderHost:SetAllPoints(holder)
    borderHost:SetFrameLevel(statusBar:GetFrameLevel() + 1)

    local border = borderHost:CreateTexture(nil, "ARTWORK")
    border:SetTexture(UI.Media.stock.progressBorder)
    border:SetWidth(barWidth + 9)
    border:SetHeight(27)
    border:SetPoint("LEFT", statusBar, "LEFT", -5, 0)

    local label = createLabel(borderHost, "GameFontHighlightSmall", "0 / 0", { 1, 1, 1 })
    label:SetPoint("CENTER", statusBar, "CENTER", 0, 0)

    function holder:SetProgress(current, total)
        current = tonumber(current) or 0
        total = math.max(0, tonumber(total) or 0)
        current = math.max(0, math.min(current, total))
        statusBar:SetMinMaxValues(0, math.max(1, total))
        statusBar:SetValue(current)
        label:SetText(current .. " / " .. total)
    end
    holder.scStatusBar = statusBar
    holder.scBackground = background
    holder.scBorderHost = borderHost
    holder.scBorder = border
    holder.scLabel = label
    return holder
end

function UI.CreateProgressBar(parent, width)
    return UI.CreateRetailProgressBar(parent, width)
end

function UI.CreateCollectionCount(parent)
    local count = CreateFrame("Frame", nil, parent)
    count:SetWidth(130)
    count:SetHeight(20)

    local chrome = UI.CreateThreeSlice(
        count,
        UI.Media.stock.searchLeft,
        UI.Media.stock.searchMiddle,
        UI.Media.stock.searchRight,
        20,
        10,
        10
    )
    chrome.scLeft:SetVertexColor(0.72, 0.62, 0.40, 0.92)
    chrome.scMiddle:SetVertexColor(0.72, 0.62, 0.40, 0.92)
    chrome.scRight:SetVertexColor(0.72, 0.62, 0.40, 0.92)

    local title = createLabel(count, "GameFontNormalSmall", "所有坐骑", COLORS.gold)
    title:SetPoint("LEFT", count, "LEFT", 12, 0)
    local value = createLabel(count, "GameFontHighlight", "0", { 1, 1, 1 })
    value:SetPoint("RIGHT", count, "RIGHT", -12, 0)

    function count:SetLabel(label)
        title:SetText(tostring(label or ""))
    end

    function count:SetCount(collected, total)
        collected = math.max(0, tonumber(collected) or 0)
        total = math.max(0, tonumber(total) or 0)
        self.scCollected = collected
        self.scTotal = total
        value:SetText(tostring(collected))
    end

    count.scChrome = chrome
    count.scTitle = title
    count.scValue = value
    return count
end

function UI.CreateMountCount(parent)
    return UI.CreateCollectionCount(parent)
end

function UI.CreateMountListRow(parent, width, height, onSelect, onContext)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(width or 208)
    row:SetHeight(height or 46)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if row.SetHitRectInsets then row:SetHitRectInsets(-44, 0, 0, 0) end

    local listTexture = UI.EzCollections and UI.EzCollections:MediaPath("Buttons", "ListButtons.tga", WHITE_TEXTURE)
        or WHITE_TEXTURE
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(row)
    background:SetTexture(listTexture)
    background:SetTexCoord(0.00390625, 0.8203125, 0.00390625, 0.18359375)
    local collectedTint = createSolidTexture(row, "BORDER", 1, 1, 1, 0)
    collectedTint:SetAllPoints(row)
    collectedTint:Hide()
    local selected = row:CreateTexture(nil, "ARTWORK")
    selected:SetAllPoints(row)
    selected:SetTexture(listTexture)
    selected:SetTexCoord(0.00390625, 0.8203125, 0.37890625, 0.55859375)
    selected:Hide()

    local faction = row:CreateTexture(nil, "BORDER")
    faction:SetTexture(UI.EzCollections and UI.EzCollections:AssetPath(
        "Interface\\PetBattles\\MountJournalIcons.blp",
        "Interface\\Buttons\\WHITE8X8"
    ) or "Interface\\Buttons\\WHITE8X8")
    faction:SetWidth(46)
    faction:SetHeight(44)
    faction:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    faction:SetAlpha(0.42)
    faction:Hide()

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture(listTexture)
    highlight:SetTexCoord(0.00390625, 0.8203125, 0.19140625, 0.37109375)

    local iconHolder = CreateFrame("Frame", nil, row)
    iconHolder:SetWidth(38)
    iconHolder:SetHeight(38)
    iconHolder:SetPoint("LEFT", row, "LEFT", -42, 0)
    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconHolder)
    UI.SetFallbackTexture(icon)
    local dragButton = CreateFrame("Button", nil, row)
    dragButton:SetWidth(38)
    dragButton:SetHeight(38)
    dragButton:SetPoint("CENTER", iconHolder, "CENTER", 0, 0)
    dragButton:SetFrameLevel(row:GetFrameLevel() + 4)
    dragButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    dragButton:RegisterForDrag("LeftButton")

    local collectionBorder = CreateFrame("Frame", nil, iconHolder)
    collectionBorder:SetAllPoints(iconHolder)
    local iconFrame = collectionBorder:CreateTexture(nil, "OVERLAY")
    iconFrame:SetAllPoints(collectionBorder)
    iconFrame:SetTexture(UI.EzCollections and UI.EzCollections:MediaPath("Common", "WhiteIconFrame.blp", WHITE_TEXTURE)
        or WHITE_TEXTURE)
    function collectionBorder:SetCollected(value)
        self.scCollected = value and true or false
        if self.scCollected then
            iconFrame:SetVertexColor(1.00, 0.82, 0.24, 0.92)
        else
            iconFrame:SetVertexColor(0.46, 0.46, 0.46, 0.72)
        end
    end
    local selectedBorder = CreateFrame("Frame", nil, iconHolder)
    selectedBorder:SetAllPoints(iconHolder)
    local selectedIconFrame = selectedBorder:CreateTexture(nil, "OVERLAY")
    selectedIconFrame:SetAllPoints(selectedBorder)
    selectedIconFrame:SetTexture(UI.EzCollections and UI.EzCollections:MediaPath("Common", "WhiteIconFrame.blp", WHITE_TEXTURE)
        or WHITE_TEXTURE)
    selectedIconFrame:SetVertexColor(1.00, 0.90, 0.30, 1)
    selectedIconFrame:SetBlendMode("ADD")
    selectedBorder:Hide()

    local name = createLabel(row, "GameFontNormal", "", { 1, 1, 1 })
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -5)
    name:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    name:SetHeight(25)
    name:SetJustifyH("LEFT")
    local source = createLabel(row, "GameFontDisableSmall", "", COLORS.muted)
    source:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 5)
    source:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    source:SetJustifyH("LEFT")
    source:Hide()
    local star = row:CreateTexture(nil, "OVERLAY")
    star:SetTexture(UI.EzCollections and UI.EzCollections:MediaPath("Common", "FavoritesIcon.tga", WHITE_TEXTURE)
        or WHITE_TEXTURE)
    star:SetWidth(25)
    star:SetHeight(25)
    star:SetTexCoord(0.03125, 0.8125, 0.03125, 0.8125)
    star:SetPoint("TOPLEFT", icon, "TOPLEFT", -8, 8)
    star:Hide()

    row:SetScript("OnClick", function(self, button)
        local record = self.scRecord
        if button == "RightButton" then
            if onContext and record then
                onContext(self, record)
            end
        elseif onSelect and record then
            onSelect(self, record)
        end
    end)

    function row:SetRecord(record)
        self.scRecord = record
        if not record then
            self.scRecord = nil
            self.scSelected = nil
            selected:Hide()
            star:Hide()
            faction:Hide()
            collectedTint:Hide()
            name:SetText("")
            source:SetText("")
            self:Hide()
            return
        end
        UI.SetIconTexture(icon, record.icon)
        UI.SetCollectedVisual(icon, record.collected)
        name:SetText(record.name or "未知坐骑")
        source:SetText(record.source or record.description or "")
        collectionBorder:SetCollected(record.collected)
        collectedTint:Hide()
        if record.favorite then star:Show() else star:Hide() end
        if record.faction == "ALLIANCE" then
            faction:SetTexCoord(1 / 128, 47 / 128, 1 / 64, 45 / 64)
            faction:Show()
        elseif record.faction == "HORDE" then
            faction:SetTexCoord(49 / 128, 95 / 128, 1 / 64, 45 / 64)
            faction:Show()
        else
            faction:Hide()
        end
        self:Show()
    end

    function row:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then
            selected:Show()
            selectedBorder:Show()
        else
            selected:Hide()
            selectedBorder:Hide()
        end
    end

    row.scBackground = background
    row.scCollectedTint = collectedTint
    row.scSelectedTexture = selected
    row.scIcon = icon
    row.scDragButton = dragButton
    row.scIconFrame = collectionBorder
    row.scCollectionBorder = collectionBorder
    row.scSelectionBorder = selectedBorder
    row.scName = name
    row.scDetail = source
    row.scStar = star
    row.scFaction = faction
    return row
end

function UI.CreateListRow(parent, width, height, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(width or 310)
    row:SetHeight(height or 56)
    row:RegisterForClicks("LeftButtonUp")

    local background = createSolidTexture(row, "BACKGROUND", 0.035, 0.028, 0.02, 0.84)
    setAllPoints(background, row, 1)
    local selected = createSolidTexture(row, "BORDER", 0.58, 0.29, 0.045, 0.52)
    setAllPoints(selected, row, 1)
    selected:Hide()

    local iconHolder = CreateFrame("Frame", nil, row)
    iconHolder:SetWidth((height or 56) - 10)
    iconHolder:SetHeight((height or 56) - 10)
    iconHolder:SetPoint("LEFT", row, "LEFT", 5, 0)
    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -1, 1)
    UI.SetFallbackTexture(icon)
    local collectionBorder, selectedBorder = UI.CreateCollectionCardBorders(iconHolder)

    local name = createLabel(row, "GameFontNormal", "", COLORS.gold)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, -6)
    name:SetPoint("RIGHT", row, "RIGHT", -26, 0)
    name:SetJustifyH("LEFT")
    local detail = createLabel(row, "GameFontDisableSmall", "", COLORS.muted)
    detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 7)
    detail:SetPoint("RIGHT", row, "RIGHT", -26, 0)
    detail:SetJustifyH("LEFT")
    local star = createLabel(row, "GameFontNormalLarge", "★", COLORS.gold)
    star:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -5)
    star:Hide()

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnClick", function(self)
        if onClick then onClick(self, self.scRecord) end
    end)
    function row:SetRecord(record)
        self.scRecord = record
        if not record then self:Hide() return end
        UI.SetIconTexture(icon, record.icon)
        name:SetText(record.name or "未知收藏")
        detail:SetText(record.source or record.description or "")
        collectionBorder:SetCollected(record.collected)
        UI.SetCollectedVisual(icon, record.collected)
        if record.favorite then star:Show() else star:Hide() end
        self:Show()
    end
    function row:SetSelected(value)
        if value then
            selected:Show()
            selectedBorder:Show()
        else
            selected:Hide()
            selectedBorder:Hide()
        end
    end
    row.scIcon = icon
    row.scIconFrame = collectionBorder
    row.scCollectionBorder = collectionBorder
    row.scSelectionBorder = selectedBorder
    row.scName = name
    row.scDetail = detail
    row.scStar = star
    return row
end

function UI.CreateIconTile(parent, width, height, onClick)
    local tile = CreateFrame("Button", nil, parent)
    tile:SetWidth(width or 50)
    tile:SetHeight(height or 50)
    tile:RegisterForClicks("LeftButtonUp")

    local hover = tile:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hover:SetWidth(48)
    hover:SetHeight(48)
    hover:SetPoint("CENTER", tile, "CENTER", 0, 2)
    hover:SetBlendMode("ADD")
    local icon = tile:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(42)
    icon:SetHeight(42)
    icon:SetPoint("CENTER", tile, "CENTER", 0, 1)
    icon:SetTexCoord(0.04347826, 0.95652173, 0.04347826, 0.95652173)
    UI.SetFallbackTexture(icon)
    local border, selectedBorder = UI.EzCollections:CreateCollectionIconFrames(tile)
    local name = createLabel(tile, "GameFontNormal", "", COLORS.cream)
    name:SetPoint("LEFT", tile, "RIGHT", 9, 3)
    name:SetWidth(135)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    local star = tile:CreateTexture(nil, "OVERLAY")
    star:SetTexture(UI.EzCollections:MediaPath("Collections", "Collections.tga", WHITE_TEXTURE))
    star:SetWidth(31)
    star:SetHeight(33)
    star:SetTexCoord(0.181640625, 0.2421875, 0.013671875, 0.078125)
    star:SetPoint("TOPLEFT", tile, "TOPLEFT", -12, 13)
    star:Hide()

    tile:SetScript("OnClick", function(self)
        if onClick then onClick(self, self.scRecord) end
    end)
    function tile:SetRecord(record)
        self.scRecord = record
        if not record then self:Hide() return end
        UI.SetIconTexture(icon, record.icon)
        name:SetText(record.name or "未知收藏")
        border:SetCollected(record.collected)
        UI.SetCollectedVisual(icon, record.collected, 0.18)
        if record.favorite then star:Show() else star:Hide() end
        self:Show()
    end
    function tile:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then
            selectedBorder:Show()
        else
            selectedBorder:Hide()
        end
    end
    tile.scIcon = icon
    tile.scBorder = border
    tile.scSelectionBorder = selectedBorder
    tile.scHover = hover
    tile.scName = name
    tile.scStar = star
    return tile
end

function UI.CreatePageControls(parent, onPrevious, onNext)
    local controls = CreateFrame("Frame", nil, parent)
    controls:SetWidth(170)
    controls:SetHeight(32)
    local previous = CreateFrame("Button", nil, controls)
    previous:SetWidth(32)
    previous:SetHeight(32)
    previous:SetNormalTexture(BUTTON_TEXTURES.previous.normal)
    previous:SetPushedTexture(BUTTON_TEXTURES.previous.pushed)
    previous:SetDisabledTexture(BUTTON_TEXTURES.previous.disabled)
    previous:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    previous:SetPoint("LEFT", controls, "LEFT", 0, 0)
    previous:SetScript("OnClick", function() if onPrevious then onPrevious() end end)
    local nextButton = CreateFrame("Button", nil, controls)
    nextButton:SetWidth(32)
    nextButton:SetHeight(32)
    nextButton:SetNormalTexture(BUTTON_TEXTURES.next.normal)
    nextButton:SetPushedTexture(BUTTON_TEXTURES.next.pushed)
    nextButton:SetDisabledTexture(BUTTON_TEXTURES.next.disabled)
    nextButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextButton:SetPoint("RIGHT", controls, "RIGHT", 0, 0)
    nextButton:SetScript("OnClick", function() if onNext then onNext() end end)
    local label = createLabel(controls, "GameFontHighlightSmall", "1 / 1", COLORS.cream)
    label:SetPoint("CENTER", controls, "CENTER", 0, 0)
    function controls:SetPage(page, totalPages)
        page = tonumber(page) or 1
        totalPages = math.max(1, tonumber(totalPages) or 1)
        page = math.max(1, math.min(page, totalPages))
        label:SetText(page .. " / " .. totalPages)
        if page <= 1 then previous:Disable() else previous:Enable() end
        if page >= totalPages then nextButton:Disable() else nextButton:Enable() end
    end
    controls.scPrevious = previous
    controls.scNext = nextButton
    controls.scLabel = label
    return controls
end

function UI.CreateEmptyState(parent, message)
    local state = CreateFrame("Frame", nil, parent)
    state:SetWidth(360)
    state:SetHeight(120)
    local ornament = createLabel(state, "GameFontNormalHuge", "◆", COLORS.bronze)
    ornament:SetPoint("TOP", state, "TOP", 0, -8)
    local title = createLabel(state, "GameFontNormalLarge", message or "没有符合条件的收藏", COLORS.gold)
    title:SetPoint("TOP", ornament, "BOTTOM", 0, -7)
    local hint = createLabel(state, "GameFontDisableSmall", "调整搜索文字或过滤条件后再试。", COLORS.muted)
    hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
    state.scTitle = title
    state.scHint = hint
    function state:SetMessage(text, detail)
        title:SetText(text or "没有符合条件的收藏")
        hint:SetText(detail or "调整搜索文字或过滤条件后再试。")
    end
    return state
end

function UI.ShowEmptyState(state, page, message, detail)
    if page and page.ClearSelection then
        page:ClearSelection()
    end
    if page and page.scModel and page.scModel.ClearModel then
        page.scModel:ClearModel()
    end
    if state then
        state:SetMessage(message, detail)
        state:Show()
    end
end

function UI.HideEmptyState(state)
    if state then
        state:Hide()
    end
end
