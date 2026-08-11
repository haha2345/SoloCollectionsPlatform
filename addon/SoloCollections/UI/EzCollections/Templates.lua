local SC = SoloCollections

SC.UI = SC.UI or {}
SC.UI.EzCollections = SC.UI.EzCollections or {}

local UI = SC.UI
local Ez = UI.EzCollections
local Assets = SC.EzCollectionsUI
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local PORTRAITS = {
    MOUNTS = {
        relative = "Interface\\Icons\\MountJournalPortrait.blp",
        fallback = function() return UI.Media and UI.Media.mountPortrait end,
        texCoord = { 0, 1, 0, 1 },
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
        relative = "Interface\\Icons\\INV_Arcane_Orb.blp",
        fallback = function() return UI.Media and UI.Media.tabs and UI.Media.tabs.WARDROBE end,
        texCoord = { 0.07, 0.93, 0.07, 0.93 },
    },
    TRANSMOG_LAB = {
        relative = "Interface\\Icons\\INV_Arcane_Orb.blp",
        fallback = function() return UI.Media and UI.Media.tabs and UI.Media.tabs.TRANSMOG_LAB end,
        texCoord = { 0.07, 0.93, 0.07, 0.93 },
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
    local texture = definition.relative and self:AssetPath(definition.relative, definition.fallback)
        or resolveFallback(definition.fallback)
    portrait:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    portrait:SetTexCoord(unpack(definition.texCoord))
end

function Ez:Guard(parent, context)
    if Assets and type(Assets.Guard) == "function" then
        return Assets.Guard(parent, context)
    end
    return false, "asset-addon-missing"
end
