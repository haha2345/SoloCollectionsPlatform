local SC = SoloCollections

SC.UI = SC.UI or {}
SC.UI.EzCollections = SC.UI.EzCollections or {}

local UI = SC.UI
local Ez = UI.EzCollections
local Assets = SC.EzCollectionsUI
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MountJournal = UI.DragonUI and UI.DragonUI.MountJournal

local PORTRAITS = {
    MOUNTS = {
        texture = "Interface\\AddOns\\DragonUI\\Textures\\Collections\\MountPortrait.tga",
        fallback = function() return UI.Media and UI.Media.mountPortrait end,
        texCoord = { 0, 1, 0, 1 },
        precut = true,
        dragonUI = true,
    },
    PETS = {
        fallback = "Interface\\Icons\\INV_Misc_Rabbit",
        texCoord = { 0.07, 0.93, 0.07, 0.93 },
    },
    TOYS = {
        fallback = "Interface\\Icons\\Trade_Archaeology_ChestofTinyGlassAnimals",
        texCoord = { 0.07, 0.93, 0.07, 0.93 },
    },
    TITLES = {
        fallback = "Interface\\Icons\\INV_Misc_Note_05",
        texCoord = { 0.07, 0.93, 0.07, 0.93 },
    },
    WARDROBE = {
        texture = function()
            if SC.RetailUI and type(SC.RetailUI.GetWardrobePortraitPath) == "function" then
                return SC.RetailUI.GetWardrobePortraitPath()
            end
            return "Interface\\Icons\\inv_chest_cloth_17"
        end,
        fallback = function()
            if Assets and type(Assets.Path) == "function" then
                return Assets.Path("Textures\\UI-MicroButton-Transmogrify-Up.tga")
            end
            return "Interface\\Icons\\INV_Misc_QuestionMark"
        end,
        texCoord = { 0, 1, 0, 1 },
        precut = true,
        dragonUI = true,
    },
    TRANSMOG_LAB = {
        texture = function()
            if Assets and type(Assets.Path) == "function" then
                return Assets.Path("Textures\\UI-MicroButton-Transmogrify-Up.tga")
            end
            if SC.RetailUI and type(SC.RetailUI.GetWardrobePortraitPath) == "function" then
                return SC.RetailUI.GetWardrobePortraitPath()
            end
            return "Interface\\Icons\\INV_Chest_Cloth_17"
        end,
        fallback = "Interface\\Icons\\INV_Chest_Cloth_17",
        texCoord = { 0, 1, 0, 1 },
        precut = true,
    },
}

local function resolveFallback(value)
    if type(value) == "function" then return value() end
    return value
end

function Ez:AssetPath(relative, fallback)
    if Assets and type(Assets.Path) == "function" then
        local path = Assets.Path(relative)
        if path then return path end
    end
    return resolveFallback(fallback)
end

function Ez:MediaPath(group, name, fallback)
    if Assets and type(Assets.MediaPath) == "function" then
        local path = Assets.MediaPath(group, name)
        if path then return path end
    end
    return resolveFallback(fallback)
end

function Ez:CreateBodyCanvas(frame)
    if not frame then return nil end
    if frame.scEzCollectionsBody then return frame.scEzCollectionsBody end

    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -22)
    texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    local path = self:MediaPath("Collections", "CollectionsBackgroundTile.tga")
    if path then
        texture:SetTexture(path)
        texture:SetHorizTile(true)
        texture:SetVertTile(true)
        texture.scEzCollectionsPath = path
    else
        texture:SetTexture(WHITE_TEXTURE)
        texture:SetVertexColor(0.035, 0.030, 0.024, 0.98)
    end
    frame.scEzCollectionsBody = texture
    self:UpdateBodyCanvas(frame)
    return texture
end

function Ez:UpdateBodyCanvas(frame)
    local texture = frame and frame.scEzCollectionsBody
    if not texture then return end
    if texture.scEzCollectionsPath then
        local width = math.max(1, (frame:GetWidth() or 1) - 8)
        local height = math.max(1, (frame:GetHeight() or 1) - 26)
        texture:SetTexCoord(0, width / 256, 0, height / 256)
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function hideInsetTiles(inset)
    if not inset or not inset.tiles then return end
    for index = 1, #inset.tiles do
        inset.tiles[index]:Hide()
    end
end

local function insetFrameSize(frame)
    local width = frame:GetWidth() or 0
    local height = frame:GetHeight() or 0
    if width < 1 or height < 1 then
        local left, right = frame:GetLeft(), frame:GetRight()
        local bottom, top = frame:GetBottom(), frame:GetTop()
        if left and right then width = right - left end
        if top and bottom then height = top - bottom end
    end
    return width, height
end

function Ez:ScheduleInsetUpdate(frame)
    if not frame then return end
    if not frame.scEzCollectionsInsetUpdater then
        local updater = CreateFrame("Frame", nil, frame)
        updater:Hide()
        updater:SetScript("OnUpdate", function(self)
            self:Hide()
            Ez:UpdateInset(frame)
        end)
        frame.scEzCollectionsInsetUpdater = updater
    end
    frame.scEzCollectionsInsetUpdater:Show()
end

function Ez:UpdateInset(frame)
    local inset = frame and frame.scEzCollectionsInset
    local background = inset and inset.background
    if not background then return end
    -- 3.3.5 often cannot wrap a single tiled texture, so HorizTile+TexCoord
    -- leaves a native-size strip. Repeat native 256px pieces instead.
    if not background.scEzCollectionsTiled then
        hideInsetTiles(inset)
        background:Show()
        return
    end
    local width, height = insetFrameSize(frame)
    if width < 1 or height < 1 then
        self:ScheduleInsetUpdate(frame)
        return
    end
    local tile = background.scEzCollectionsTileSize or 256
    local path = background.scEzCollectionsPath
    if not path then return end
    background:Hide()
    inset.tiles = inset.tiles or {}
    local index = 0
    local row = 0
    while row * tile < height do
        local col = 0
        while col * tile < width do
            index = index + 1
            local tex = inset.tiles[index]
            if not tex then
                tex = frame:CreateTexture(nil, "BACKGROUND")
                inset.tiles[index] = tex
            end
            local tw = math.min(tile, width - col * tile)
            local th = math.min(tile, height - row * tile)
            tex:ClearAllPoints()
            tex:SetTexture(path)
            if tex.SetHorizTile then tex:SetHorizTile(false) end
            if tex.SetVertTile then tex:SetVertTile(false) end
            tex:SetWidth(tw)
            tex:SetHeight(th)
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", col * tile, -row * tile)
            tex:SetTexCoord(0, tw / tile, 0, th / tile)
            tex:Show()
            col = col + 1
        end
        row = row + 1
    end
    for extra = index + 1, #inset.tiles do
        inset.tiles[extra]:Hide()
    end
end

local function tabLabel(button)
    local name = button and button:GetName()
    return (button and button.Text) or (name and _G[name .. "Text"])
end

local function setTabWidth(button)
    local label = tabLabel(button)
    local textWidth = label and label:GetStringWidth() or 40
    button:SetWidth(math.max(70, math.min(142, textWidth + 30)))
    button:SetHeight(32)
end

function Ez:CreateJournalTab(parent, index, labelText, onClick, cutoff)
    if MountJournal and MountJournal.CreateJournalTab then
        return MountJournal:CreateJournalTab(parent, index, labelText, onClick, cutoff)
    end
    local name = "SoloCollectionsJournalTab" .. tostring(index)
    local button = CreateFrame("Button", name, parent, "CharacterFrameTabButtonTemplate")
    button:SetID(index)
    button:SetText(labelText or "")
    setTabWidth(button)

    if cutoff then
        local cutoffPath = self:AssetPath("Textures\\UI-Character-ActiveTabCutoff.tga")
        if cutoffPath then
            for _, suffix in ipairs({ "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
                local texture = _G[name .. suffix]
                if texture then texture:SetTexture(cutoffPath) end
            end
        end
        button:SetFrameLevel(button:GetFrameLevel() + 4)
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

    button.scEzCollectionsTab = true
    button.scCutoff = cutoff and true or false
    return button
end

function Ez:LayoutJournalTabs(frame, tabs)
    if MountJournal and MountJournal.LayoutJournalTabs then
        return MountJournal:LayoutJournalTabs(frame, tabs)
    end
    local previous
    local count = #(tabs or {})
    for index, button in ipairs(tabs or {}) do
        button:ClearAllPoints()
        if not previous then
            button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        else
            local overlap = (index == 6 and count == 6) and 0 or -16
            button:SetPoint("LEFT", previous, "RIGHT", overlap, 0)
        end
        previous = button
    end
end

function Ez:SetPortraitForTab(frame, key)
    local portrait = frame and frame.scPortrait
    if not portrait then return end
    local definition = PORTRAITS[key] or PORTRAITS.MOUNTS
    local texture = resolveFallback(definition.texture)
        or (definition.relative and self:AssetPath(definition.relative, definition.fallback))
        or resolveFallback(definition.fallback)
    texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark"
    local function apply(candidate)
        if not candidate then return false end
        if definition.precut then
            portrait:SetTexture(candidate)
            portrait:SetTexCoord(unpack(definition.texCoord))
        elseif SetPortraitToTexture then
            local ok = pcall(SetPortraitToTexture, portrait, candidate)
            if not ok then
                portrait:SetTexture(candidate)
                portrait:SetTexCoord(unpack(definition.texCoord))
            end
        else
            portrait:SetTexture(candidate)
            portrait:SetTexCoord(unpack(definition.texCoord))
        end
        return not portrait.GetTexture or portrait:GetTexture() ~= nil
    end
    local applied = apply(texture)
    local fallback = resolveFallback(definition.fallback)
    if not applied and fallback ~= texture then
        applied = apply(fallback)
    end
    if not applied then
        portrait:SetTexture(0.08, 0.07, 0.06, 1)
        portrait:SetTexCoord(0, 1, 0, 1)
    end
    portrait:SetAlpha(1)
    portrait:SetVertexColor(1, 1, 1, 1)
    portrait:Show()
    portrait:ClearAllPoints()
    if definition.dragonUI then
        -- DragonUI collections/window.lua values measured against the opaque
        -- opening of PortraitFrameTemplate's gold corner atlas.
        portrait:SetSize(58, 58)
        portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 6)
    else
        portrait:SetSize(60, 60)
        portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 8)
    end
end

function Ez:Guard(parent, context)
    if Assets and type(Assets.Guard) == "function" then
        return Assets.Guard(parent, context)
    end
    return false, "asset-addon-missing"
end

local function makeTexture(parent, layer, path, width, height, texCoord)
    local texture = parent:CreateTexture(nil, layer or "BORDER")
    texture:SetTexture(path)
    if width then texture:SetWidth(width) end
    if height then texture:SetHeight(height) end
    if texCoord then texture:SetTexCoord(unpack(texCoord)) end
    return texture
end

function Ez:ApplyInset(frame)
    if not frame then return nil end
    if frame.scEzCollectionsInset then return frame.scEzCollectionsInset end

    local marble = self:AssetPath("Interface\\FrameGeneral\\UI-Background-Marble.tga", WHITE_TEXTURE)
    local frameAtlas = self:AssetPath("Interface\\FrameGeneral\\UI-Frame.tga", WHITE_TEXTURE)
    local horizontalAtlas = self:AssetPath("Interface\\FrameGeneral\\_UI-Frame.tga", WHITE_TEXTURE)
    local verticalAtlas = self:AssetPath("Interface\\FrameGeneral\\!UI-Frame.tga", WHITE_TEXTURE)

    local background = makeTexture(frame, "BACKGROUND", marble)
    background:SetAllPoints(frame)
    background:SetHorizTile(true)
    background:SetVertTile(true)
    background.scEzCollectionsPath = marble
    if marble == WHITE_TEXTURE then
        background:SetVertexColor(0.08, 0.07, 0.055, 0.98)
        background.scEzCollectionsTiled = false
    else
        background.scEzCollectionsTiled = true
        background.scEzCollectionsTileSize = 256
    end

    local topLeft = makeTexture(frame, "BORDER", frameAtlas, 6, 6, {
        0.63281250, 0.67968750, 0.54687500, 0.59375000,
    })
    topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    local topRight = makeTexture(frame, "BORDER", frameAtlas, 6, 6, {
        0.90625000, 0.95312500, 0.21875000, 0.26562500,
    })
    topRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    local bottomLeft = makeTexture(frame, "BORDER", frameAtlas, 6, 6, {
        0.69531250, 0.74218750, 0.54687500, 0.59375000,
    })
    bottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, -1)
    local bottomRight = makeTexture(frame, "BORDER", frameAtlas, 6, 6, {
        0.75781250, 0.80468750, 0.54687500, 0.59375000,
    })
    bottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -1)

    local top = makeTexture(frame, "BORDER", horizontalAtlas, nil, 3, { 0, 1, 0.08593750, 0.10937500 })
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT", 0, 0)
    top:SetHorizTile(true)
    local bottom = makeTexture(frame, "BORDER", horizontalAtlas, nil, 3, { 0, 1, 0.00781250, 0.03125000 })
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
    bottom:SetHorizTile(true)
    local left = makeTexture(frame, "BORDER", verticalAtlas, 3, nil, { 0.09375000, 0.14062500, 0, 1 })
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
    left:SetVertTile(true)
    local right = makeTexture(frame, "BORDER", verticalAtlas, 3, nil, { 0.01562500, 0.06250000, 0, 1 })
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 0, 0)
    right:SetVertTile(true)

    frame.scEzCollectionsInset = {
        background = background,
        topLeft = topLeft,
        topRight = topRight,
        bottomLeft = bottomLeft,
        bottomRight = bottomRight,
        top = top,
        bottom = bottom,
        left = left,
        right = right,
    }
    if not frame.scEzCollectionsInsetHooked then
        frame.scEzCollectionsInsetHooked = true
        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function(self)
                Ez:UpdateInset(self)
            end)
            frame:HookScript("OnShow", function(self)
                Ez:UpdateInset(self)
            end)
        end
    end
    self:UpdateInset(frame)
    return frame.scEzCollectionsInset
end

function Ez:AddShadowOverlay(frame)
    if not frame then return nil end
    if frame.scEzCollectionsShadow then return frame.scEzCollectionsShadow end
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 2)
    overlay:EnableMouse(false)

    local cornerPath = self:MediaPath("Common", "ShadowOverlay-Corner.blp", WHITE_TEXTURE)
    local topPath = self:MediaPath("Common", "ShadowOverlay-Top.blp", WHITE_TEXTURE)
    local bottomPath = self:MediaPath("Common", "ShadowOverlay-Bottom.blp", WHITE_TEXTURE)
    local leftPath = self:MediaPath("Common", "ShadowOverlay-Left.blp", WHITE_TEXTURE)
    local rightPath = self:MediaPath("Common", "ShadowOverlay-Right.blp", WHITE_TEXTURE)
    local topLeft = makeTexture(overlay, "OVERLAY", cornerPath, 64, 64)
    topLeft:SetPoint("TOPLEFT")
    local topRight = makeTexture(overlay, "OVERLAY", cornerPath, 64, 64)
    topRight:SetPoint("TOPRIGHT")
    topRight:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    local bottomLeft = makeTexture(overlay, "OVERLAY", cornerPath, 64, 64)
    bottomLeft:SetPoint("BOTTOMLEFT")
    bottomLeft:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    local bottomRight = makeTexture(overlay, "OVERLAY", cornerPath, 64, 64)
    bottomRight:SetPoint("BOTTOMRIGHT")
    bottomRight:SetTexCoord(1, 1, 1, 0, 0, 1, 0, 0)
    local top = makeTexture(overlay, "OVERLAY", topPath, nil, 64)
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT")
    top:SetHorizTile(true)
    local bottom = makeTexture(overlay, "OVERLAY", bottomPath, nil, 64)
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT")
    bottom:SetHorizTile(true)
    local left = makeTexture(overlay, "OVERLAY", leftPath, 64)
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT")
    left:SetVertTile(true)
    local right = makeTexture(overlay, "OVERLAY", rightPath, 64)
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT")
    right:SetVertTile(true)
    frame.scEzCollectionsShadow = overlay
    return overlay
end

function Ez:ApplyInputBorder(frame)
    if not frame then return nil end
    if frame.scEzCollectionsInputBorder then return frame.scEzCollectionsInputBorder end
    if frame.scChrome then
        for _, texture in pairs(frame.scChrome) do
            if texture and texture.Hide then texture:Hide() end
        end
    end
    local path = "Interface\\Common\\Common-Input-Border"
    local slices = {}
    local function piece(key, width, height, coord)
        local texture = makeTexture(frame, "BORDER", path, width, height, coord)
        slices[key] = texture
        return texture
    end
    local topLeft = piece("topLeft", 8, 8, { 0, 0.0625, 0, 0.25 })
    topLeft:SetPoint("TOPLEFT")
    local topRight = piece("topRight", 8, 8, { 0.9375, 1, 0, 0.25 })
    topRight:SetPoint("TOPRIGHT")
    local bottomLeft = piece("bottomLeft", 8, 8, { 0, 0.0625, 0.375, 0.625 })
    bottomLeft:SetPoint("BOTTOMLEFT")
    local bottomRight = piece("bottomRight", 8, 8, { 0.9375, 1, 0.375, 0.625 })
    bottomRight:SetPoint("BOTTOMRIGHT")
    local top = piece("top", nil, 8, { 0.0625, 0.9375, 0, 0.25 })
    top:SetPoint("LEFT", topLeft, "RIGHT")
    top:SetPoint("RIGHT", topRight, "LEFT")
    local bottom = piece("bottom", nil, 8, { 0.0625, 0.9375, 0.375, 0.625 })
    bottom:SetPoint("LEFT", bottomLeft, "RIGHT")
    bottom:SetPoint("RIGHT", bottomRight, "LEFT")
    local left = piece("left", 8, nil, { 0, 0.0625, 0.25, 0.375 })
    left:SetPoint("TOP", topLeft, "BOTTOM")
    left:SetPoint("BOTTOM", bottomLeft, "TOP")
    local right = piece("right", 8, nil, { 0.9375, 1, 0.25, 0.375 })
    right:SetPoint("TOP", topRight, "BOTTOM")
    right:SetPoint("BOTTOM", bottomRight, "TOP")
    local background = makeTexture(frame, "BACKGROUND", path, nil, nil, { 0.0625, 0.9375, 0.25, 0.375 })
    background:SetPoint("TOPLEFT", topLeft, "BOTTOMRIGHT")
    background:SetPoint("BOTTOMRIGHT", bottomRight, "TOPLEFT")
    slices.background = background
    frame.scEzCollectionsInputBorder = slices
    return slices
end

function Ez:SkinSearchBox(editBox)
    if not editBox then return end
    if editBox.scIcon then
        editBox.scIcon:SetTexture(self:MediaPath("Common", "UI-Searchbox-Icon.tga", "Interface\\Common\\UI-Searchbox-Icon"))
    end
    if editBox.scClearButton then
        editBox.scClearButton:SetNormalTexture(self:AssetPath("Interface\\FriendsFrame\\ClearBroadcastIcon.tga", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"))
    end
end

function Ez:SkinSilverMenuButton(button)
    if not button or button.scEzCollectionsSilver then return end
    for _, texture in ipairs({ button.scBackground, button.scBorder, button.scInner }) do
        if texture and texture.Hide then texture:Hide() end
    end
    if button.scLabel then button.scLabel:SetTextColor(1, 1, 1) end
    if button.scArrow then
        button.scArrow:SetWidth(10)
        button.scArrow:SetHeight(12)
        button.scArrow:ClearAllPoints()
        button.scArrow:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    end
    local up = self:MediaPath("Buttons", "UI-Silver-Button-Up.tga")
    local down = self:MediaPath("Buttons", "UI-Silver-Button-Down.tga", up)
    local highlightPath = self:MediaPath("Buttons", "UI-Silver-Button-Highlight.tga", up)
    if not up then return end
    local definitions = {
        { "topLeft", 12, 6, { 0, 0.09375, 0, 0.1875 }, "TOPLEFT" },
        { "topRight", 12, 6, { 0.53125, 0.625, 0, 0.1875 }, "TOPRIGHT" },
        { "bottomLeft", 12, 6, { 0, 0.09375, 0.625, 0.8125 }, "BOTTOMLEFT" },
        { "bottomRight", 12, 6, { 0.53125, 0.625, 0.625, 0.8125 }, "BOTTOMRIGHT" },
    }
    local parts = {}
    for _, definition in ipairs(definitions) do
        local texture = makeTexture(button, "BACKGROUND", up, definition[2], definition[3], definition[4])
        texture:SetPoint(definition[5])
        parts[definition[1]] = texture
    end
    local top = makeTexture(button, "BACKGROUND", up, nil, 6, { 0.09375, 0.53125, 0, 0.1875 })
    top:SetPoint("TOPLEFT", parts.topLeft, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", parts.topRight, "TOPLEFT")
    parts.top = top
    local bottom = makeTexture(button, "BACKGROUND", up, nil, 6, { 0.09375, 0.53125, 0.625, 0.8125 })
    bottom:SetPoint("BOTTOMLEFT", parts.bottomLeft, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", parts.bottomRight, "BOTTOMLEFT")
    parts.bottom = bottom
    local left = makeTexture(button, "BACKGROUND", up, 12, nil, { 0, 0.09375, 0.1875, 0.625 })
    left:SetPoint("TOP", parts.topLeft, "BOTTOM")
    left:SetPoint("BOTTOM", parts.bottomLeft, "TOP")
    parts.left = left
    local right = makeTexture(button, "BACKGROUND", up, 12, nil, { 0.53125, 0.625, 0.1875, 0.625 })
    right:SetPoint("TOP", parts.topRight, "BOTTOM")
    right:SetPoint("BOTTOM", parts.bottomRight, "TOP")
    parts.right = right
    local middle = makeTexture(button, "BACKGROUND", up, nil, nil, { 0.09375, 0.53125, 0.1875, 0.625 })
    middle:SetPoint("TOPLEFT", parts.topLeft, "BOTTOMRIGHT")
    middle:SetPoint("BOTTOMRIGHT", parts.bottomRight, "TOPLEFT")
    parts.middle = middle
    local highlight = makeTexture(button, "HIGHLIGHT", highlightPath)
    highlight:SetAllPoints(button)
    highlight:SetTexCoord(0, 1, 0.03, 0.7175)
    highlight:SetBlendMode("ADD")

    local function setPath(path)
        for _, texture in pairs(parts) do texture:SetTexture(path) end
    end
    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() == 1 then setPath(down) end
    end)
    button:SetScript("OnMouseUp", function(self)
        if self:IsEnabled() == 1 then setPath(up) end
    end)
    button.scEzCollectionsSilver = parts
end

function Ez:SkinTrimScrollFrame(scrollFrame)
    if not scrollFrame or scrollFrame.scEzCollectionsScroll then return end
    local name = scrollFrame:GetName()
    local scrollBar = name and _G[name .. "ScrollBar"]
    if not scrollBar then return end
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(WHITE_TEXTURE)
    track:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 4, -17)
    track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", -4, 17)
    track:SetVertexColor(0, 0, 0, 0.75)
    scrollFrame.scEzCollectionsScroll = { scrollBar = scrollBar, track = track }
end

function Ez:CreateCollectionIconFrames(parent)
    local border = CreateFrame("Frame", nil, parent)
    border:SetAllPoints(parent)
    local borderTexture = border:CreateTexture(nil, "OVERLAY")
    borderTexture:SetAllPoints(border)
    borderTexture:SetTexture(self:MediaPath("Common", "WhiteIconFrame.blp", WHITE_TEXTURE))
    function border:SetCollected(value)
        self.scCollected = value and true or false
        if self.scCollected then
            borderTexture:SetVertexColor(1.00, 0.82, 0.24, 0.92)
        else
            borderTexture:SetVertexColor(0.46, 0.46, 0.46, 0.72)
        end
    end

    local selected = CreateFrame("Frame", nil, parent)
    selected:SetAllPoints(parent)
    local selectedTexture = selected:CreateTexture(nil, "OVERLAY")
    selectedTexture:SetAllPoints(selected)
    selectedTexture:SetTexture(self:MediaPath("Common", "WhiteIconFrame.blp", WHITE_TEXTURE))
    selectedTexture:SetVertexColor(1.00, 0.90, 0.30, 1)
    selectedTexture:SetBlendMode("ADD")
    selected:Hide()
    return border, selected
end

local function setAtlasPixels(texture, path, atlasWidth, atlasHeight, left, right, top, bottom)
    texture:SetTexture(path or WHITE_TEXTURE)
    texture:SetTexCoord(
        left / atlasWidth,
        right / atlasWidth,
        top / atlasHeight,
        bottom / atlasHeight
    )
end

function Ez:CreateWardrobeItemChrome(parent)
    local transmog = self:MediaPath("Transmogrify", "Transmogrify.tga", WHITE_TEXTURE)
    local collections = self:MediaPath("Collections", "Collections.tga", WHITE_TEXTURE)

    local border = CreateFrame("Frame", nil, parent)
    border:SetAllPoints(parent)
    border:SetFrameLevel(parent:GetFrameLevel() + 1)
    local borderTexture = border:CreateTexture(nil, "OVERLAY")
    borderTexture:SetPoint("CENTER", border, "CENTER", 0, -3)
    function border:SetCollected(value)
        self.scCollected = value and true or false
        if self.scCollected then
            borderTexture:SetWidth(96)
            borderTexture:SetHeight(122)
            setAtlasPixels(borderTexture, transmog, 512, 512, 1, 97, 131, 253)
        else
            borderTexture:SetWidth(96)
            borderTexture:SetHeight(122)
            setAtlasPixels(borderTexture, transmog, 512, 512, 1, 97, 255, 377)
        end
    end

    local selected = CreateFrame("Frame", nil, parent)
    selected:SetAllPoints(parent)
    selected:SetFrameLevel(parent:GetFrameLevel() + 2)
    local selectedTexture = selected:CreateTexture(nil, "OVERLAY")
    selectedTexture:SetWidth(102)
    selectedTexture:SetHeight(128)
    selectedTexture:SetPoint("CENTER")
    selectedTexture:SetBlendMode("ADD")
    setAtlasPixels(selectedTexture, transmog, 512, 512, 1, 103, 1, 129)
    selected:Hide()

    local highlight = parent:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetWidth(84)
    highlight:SetHeight(110)
    highlight:SetPoint("CENTER")
    highlight:SetBlendMode("ADD")
    setAtlasPixels(highlight, transmog, 512, 512, 105, 189, 225, 335)

    local favorite = CreateFrame("Frame", nil, parent)
    favorite:SetWidth(31)
    favorite:SetHeight(33)
    favorite:SetPoint("TOPLEFT", parent, "TOPLEFT", -12, 13)
    favorite:SetFrameLevel(parent:GetFrameLevel() + 5)
    local favoriteTexture = favorite:CreateTexture(nil, "OVERLAY")
    favoriteTexture:SetAllPoints(favorite)
    setAtlasPixels(favoriteTexture, collections, 512, 512, 93, 124, 7, 40)
    favorite:Hide()

    local hideVisual = CreateFrame("Frame", nil, parent)
    hideVisual:SetWidth(36)
    hideVisual:SetHeight(30)
    hideVisual:SetPoint("TOPLEFT", parent, "TOPLEFT", -12, 13)
    hideVisual:SetFrameLevel(parent:GetFrameLevel() + 5)
    local hideTexture = hideVisual:CreateTexture(nil, "OVERLAY")
    hideTexture:SetAllPoints(hideVisual)
    setAtlasPixels(hideTexture, transmog, 512, 512, 412, 448, 88, 118)
    hideVisual:Hide()

    function parent:SetHideVisual(value)
        if value then hideVisual:Show() else hideVisual:Hide() end
    end

    border:SetCollected(false)
    border.scTexture = borderTexture
    selected.scTexture = selectedTexture
    favorite.scTexture = favoriteTexture
    parent.scHideVisual = hideVisual
    return border, selected, favorite, highlight
end

function Ez:CreateWardrobeSetChrome(parent)
    local transmogSets = self:MediaPath("Transmogrify", "TransmogSetsVendor.tga", WHITE_TEXTURE)
    local collections = self:MediaPath("Collections", "Collections.tga", WHITE_TEXTURE)

    local border = CreateFrame("Frame", nil, parent)
    border:SetAllPoints(parent)
    border:SetFrameLevel(parent:GetFrameLevel() + 1)
    local borderTexture = border:CreateTexture(nil, "OVERLAY")
    borderTexture:SetPoint("CENTER", border, "CENTER", 0, -6)
    function border:SetCollected(value)
        self.scCollected = value and true or false
        if self.scCollected then
            borderTexture:SetWidth(152)
            borderTexture:SetHeight(208)
            setAtlasPixels(borderTexture, transmogSets, 512, 512, 1, 153, 1, 209)
        else
            borderTexture:SetWidth(144)
            borderTexture:SetHeight(200)
            setAtlasPixels(borderTexture, transmogSets, 512, 512, 155, 299, 1, 201)
        end
    end

    local selected = CreateFrame("Frame", nil, parent)
    selected:SetAllPoints(parent)
    selected:SetFrameLevel(parent:GetFrameLevel() + 2)
    local selectedTexture = selected:CreateTexture(nil, "OVERLAY")
    selectedTexture:SetWidth(150)
    selectedTexture:SetHeight(206)
    selectedTexture:SetPoint("CENTER")
    selectedTexture:SetBlendMode("ADD")
    setAtlasPixels(selectedTexture, transmogSets, 512, 512, 1, 151, 211, 417)
    selected:Hide()

    local highlight = parent:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetWidth(132)
    highlight:SetHeight(188)
    highlight:SetPoint("CENTER")
    highlight:SetBlendMode("ADD")
    setAtlasPixels(highlight, transmogSets, 512, 512, 289, 421, 203, 391)

    local favorite = parent:CreateTexture(nil, "OVERLAY")
    favorite:SetWidth(33)
    favorite:SetHeight(31)
    favorite:SetPoint("TOPLEFT", parent, "TOPLEFT", -12, 13)
    setAtlasPixels(favorite, collections, 512, 512, 93, 124, 7, 40)
    favorite:Hide()

    border:SetCollected(false)
    border.scTexture = borderTexture
    selected.scTexture = selectedTexture
    return border, selected, favorite, highlight
end

local function animateTexCoords(texture, textureWidth, textureHeight, frameWidth, frameHeight, numFrames, elapsed, throttle)
    if not texture then return end
    texture.scAntsThrottle = (texture.scAntsThrottle or 0) + elapsed
    if texture.scAntsThrottle < (throttle or 0.01) then return end
    texture.scAntsThrottle = 0
    local frame = (texture.scAntsFrame or 0) + 1
    if frame > numFrames then frame = 1 end
    texture.scAntsFrame = frame
    local columns = math.floor(textureWidth / frameWidth)
    if columns < 1 then return end
    local column = (frame - 1) % columns
    local row = math.floor((frame - 1) / columns)
    local left = (column * frameWidth) / textureWidth
    local right = ((column + 1) * frameWidth) / textureWidth
    local top = (row * frameHeight) / textureHeight
    local bottom = ((row + 1) * frameHeight) / textureHeight
    texture:SetTexCoord(left, right, top, bottom)
end

function Ez:CreateTransmogSlotChrome(parent)
    local transmog = self:MediaPath("Transmogrify", "Transmogrify.tga", WHITE_TEXTURE)
    local textures = self:MediaPath("Transmogrify", "Textures.tga", WHITE_TEXTURE)

    local icon = parent:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(36)
    icon:SetHeight(36)
    icon:SetPoint("CENTER")

    local border = parent:CreateTexture(nil, "BORDER")
    border:SetWidth(58)
    border:SetHeight(57)
    border:SetPoint("CENTER")
    border:SetTexture(transmog)
    border:SetTexCoord(0.205078125, 0.318359375, 0.783203125, 0.89453125)

    local status = parent:CreateTexture(nil, "OVERLAY")
    status:SetWidth(44)
    status:SetHeight(43)
    status:SetPoint("CENTER")
    status:SetTexture(transmog)
    status:SetTexCoord(0.466796875, 0.552734375, 0.001953125, 0.0859375)
    status:Hide()

    local selected = parent:CreateTexture(nil, "OVERLAY")
    selected:SetWidth(62)
    selected:SetHeight(62)
    selected:SetPoint("TOP", parent, "TOP", 0, 9)
    selected:SetTexture(transmog)
    selected:SetTexCoord(0.205078125, 0.326171875, 0.658203125, 0.779296875)
    selected:Hide()

    local pendingGlow = parent:CreateTexture(nil, "OVERLAY")
    pendingGlow:SetWidth(58)
    pendingGlow:SetHeight(57)
    pendingGlow:SetPoint("CENTER")
    pendingGlow:SetTexture(textures)
    pendingGlow:SetTexCoord(0.5234375, 0.9765625, 0.38476563, 0.49609375)
    pendingGlow:SetBlendMode("ADD")
    pendingGlow:Hide()

    -- Legion/ez PendingFrame.Ants: 44×44, AnimateTexCoords 256/48 ×22.
    -- 3.3.5 FrameXML has no AnimateTexCoords; keep a local copy.
    local antsPath = self:MediaPath("Transmogrify", "PurpleIconAlertAnts.tga")
        or self:MediaPath("Transmogrify", "PurpleIconAlertAnts.blp")
    local ants = parent:CreateTexture(nil, "OVERLAY")
    ants:SetWidth(44)
    ants:SetHeight(44)
    ants:SetPoint("CENTER")
    if antsPath then ants:SetTexture(antsPath) end
    ants:Hide()
    local antsDriver = CreateFrame("Frame", nil, parent)
    antsDriver:Hide()
    antsDriver:SetScript("OnUpdate", function(_, elapsed)
        if not (ants:IsShown() and antsPath) then return end
        animateTexCoords(ants, 256, 256, 48, 48, 22, elapsed, 0.01)
    end)

    local undo = parent:CreateTexture(nil, "OVERLAY")
    undo:SetWidth(24)
    undo:SetHeight(22)
    undo:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 13, 12)
    undo:SetTexture(textures)
    undo:SetTexCoord(0.1796875, 0.3671875, 0.58203125, 0.625)
    undo:Hide()

    local highlight = parent:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetWidth(44)
    highlight:SetHeight(41)
    highlight:SetPoint("CENTER")
    highlight:SetTexture(transmog)
    highlight:SetTexCoord(0.646484375, 0.732421875, 0.001953125, 0.08203125)
    highlight:SetBlendMode("ADD")

    function parent:SetSlotSelected(value)
        if value then selected:Show() else selected:Hide() end
    end

    function parent:SetSlotPending(value)
        if value then
            status:Show()
            pendingGlow:Show()
            undo:Show()
            if antsPath then
                ants:Show()
                antsDriver:Show()
            end
        else
            status:Hide()
            pendingGlow:Hide()
            undo:Hide()
            ants:Hide()
            antsDriver:Hide()
        end
    end

    local hiddenCover = parent:CreateTexture(nil, "ARTWORK")
    hiddenCover:SetWidth(46)
    hiddenCover:SetHeight(45)
    hiddenCover:SetPoint("CENTER")
    setAtlasPixels(hiddenCover, transmog, 512, 512, 191, 237, 1, 46)
    hiddenCover:SetAlpha(0.6)
    hiddenCover:Hide()

    local hiddenIcon = parent:CreateTexture(nil, "ARTWORK")
    hiddenIcon:SetWidth(36)
    hiddenIcon:SetHeight(30)
    hiddenIcon:SetPoint("CENTER")
    setAtlasPixels(hiddenIcon, transmog, 512, 512, 412, 448, 88, 118)
    hiddenIcon:SetAlpha(0.7)
    hiddenIcon:Hide()

    function parent:SetSlotHidden(value)
        if value then
            hiddenCover:Show()
            hiddenIcon:Show()
        else
            hiddenCover:Hide()
            hiddenIcon:Hide()
        end
    end

    parent.scIcon = icon
    parent.scBorder = border
    parent.scStatusBorder = status
    parent.scSelectedTexture = selected
    parent.scPendingGlow = pendingGlow
    parent.scPendingAnts = ants
    parent.scUndoTexture = undo
    parent.scHiddenCover = hiddenCover
    parent.scHiddenIcon = hiddenIcon
    return icon, border, selected, status, pendingGlow, undo
end

function Ez:CreateTransmogEnchantChrome(parent)
    local transmog = self:MediaPath("Transmogrify", "Transmogrify.tga", WHITE_TEXTURE)

    local icon = parent:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetPoint("CENTER")
    icon:Hide()

    local border = parent:CreateTexture(nil, "BORDER")
    border:SetWidth(40)
    border:SetHeight(40)
    border:SetPoint("CENTER")
    setAtlasPixels(border, transmog, 512, 512, 377, 417, 1, 41)
    border:SetAlpha(0.55)

    parent.scIcon = icon
    parent.scBorder = border
    return icon, border
end

function Ez:CreateRotationButtons(model, onLeft, onRight)
    local left = CreateFrame("Button", nil, model)
    left:SetWidth(35)
    left:SetHeight(35)
    left:SetPoint("BOTTOMRIGHT", model, "BOTTOM", -5, 15)
    left:SetNormalTexture("Interface\\Buttons\\UI-RotationLeft-Button-Up")
    left:SetPushedTexture("Interface\\Buttons\\UI-RotationLeft-Button-Down")
    left:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
    left:SetScript("OnClick", function() if onLeft then onLeft() end end)

    local right = CreateFrame("Button", nil, model)
    right:SetWidth(35)
    right:SetHeight(35)
    right:SetPoint("BOTTOMLEFT", model, "BOTTOM", 5, 15)
    right:SetNormalTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
    right:SetPushedTexture("Interface\\Buttons\\UI-RotationRight-Button-Down")
    right:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
    right:SetScript("OnClick", function() if onRight then onRight() end end)
    return left, right
end
