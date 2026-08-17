local SC = SoloCollections
local UI = SC.UI

local COLLECTION_DEFAULT = { point = "BOTTOMRIGHT", x = -28, y = 150 }
local TRANSMOG_DEFAULT = { point = "BOTTOMRIGHT", x = -82, y = 150 }

local function savedPosition(key, defaults)
    local saved = SC.db and SC.db[key]
    return {
        point = (saved and saved.point) or defaults.point,
        relativePoint = (saved and saved.relativePoint) or defaults.point,
        x = (saved and saved.x) or defaults.x,
        y = (saved and saved.y) or defaults.y,
    }
end

local function applySavedPosition(button, key, defaults)
    local saved = savedPosition(key, defaults)
    button:ClearAllPoints()
    button:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    button:SetClampedToScreen(true)
end

local function savePosition(button, key, defaults)
    if not SC.db then
        return
    end
    local point, _, relativePoint, x, y = button:GetPoint(1)
    SC.db[key] = {
        point = point or defaults.point,
        relativePoint = relativePoint or defaults.point,
        x = math.floor((x or defaults.x) + 0.5),
        y = math.floor((y or defaults.y) + 0.5),
    }
end

local MICRO_BUTTON_ICON_COORD = { 0.08, 0.92, 0.50, 0.98 }
local SQUARE_ICON_COORD = { 0.08, 0.92, 0.08, 0.92 }

local function createLauncherButton(name, iconTexture, tooltipTitle, tooltipBody, onClick, positionKey, defaults, iconTexCoord)
    local button = CreateFrame("Button", name, UIParent)
    button:SetWidth(46)
    button:SetHeight(46)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(20)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local shadow = button:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture("Interface\\Buttons\\WHITE8X8")
    shadow:SetVertexColor(0, 0, 0, 0.48)
    shadow:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -6)
    shadow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 2)

    local plate = button:CreateTexture(nil, "BACKGROUND")
    plate:SetTexture("Interface\\Buttons\\WHITE8X8")
    plate:SetVertexColor(0.025, 0.025, 0.022, 0.98)
    plate:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
    plate:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(iconTexture)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -6)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 6)
    icon:SetTexCoord(unpack(iconTexCoord or SQUARE_ICON_COORD))

    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    ring:SetVertexColor(0.92, 0.78, 0.43, 1)

    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(tooltipTitle)
        GameTooltip:AddLine(tooltipBody, 0.82, 0.72, 0.52, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self.scWasDragged = true
        self:StartMoving()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetClampedToScreen(true)
        savePosition(self, positionKey, defaults)
    end)
    button:SetScript("OnClick", function(self)
        if self.scWasDragged then
            self.scWasDragged = nil
            return
        end
        onClick()
    end)

    applySavedPosition(button, positionKey, defaults)
    return button
end

local function transmogIconPath()
    if UI.EzCollections and UI.EzCollections.AssetPath then
        local path = UI.EzCollections:AssetPath(
            "Textures\\UI-MicroButton-Transmogrify-Up.tga",
            "Interface\\Icons\\INV_Chest_Cloth_17"
        )
        if path then return path end
    end
    if SC.RetailUI and type(SC.RetailUI.GetWardrobePortraitPath) == "function" then
        local path = SC.RetailUI.GetWardrobePortraitPath()
        if path then return path end
    end
    return "Interface\\Icons\\INV_Chest_Cloth_17"
end

function UI.CreateLauncher()
    if SC.UIPlatform and not SC.UIPlatform:CanCreateUI() then return nil end

    if not UI.Launcher then
        UI.Launcher = createLauncherButton(
            "SoloCollectionsLauncher",
            UI.Media.collectionsLauncher,
            "收藏",
            "点击打开收藏日志，拖动可改变位置。",
            function()
                SC:ToggleJournal()
            end,
            "launcher",
            COLLECTION_DEFAULT,
            MICRO_BUTTON_ICON_COORD
        )
    end

    if not UI.TransmogLauncher then
        UI.TransmogLauncher = createLauncherButton(
            "SoloCollectionsTransmogLauncher",
            transmogIconPath(),
            "幻化",
            "点击打开幻化室，拖动可改变位置。",
            function()
                if SC.ToggleTransmog then
                    SC:ToggleTransmog()
                elseif UI.ToggleTransmog then
                    UI.ToggleTransmog()
                end
            end,
            "transmogLauncher",
            TRANSMOG_DEFAULT,
            MICRO_BUTTON_ICON_COORD
        )
    end

    return UI.Launcher
end

function UI.ResetPositions()
    if UI.Launcher then
        applySavedPosition(UI.Launcher, "launcher", COLLECTION_DEFAULT)
    end
    if UI.TransmogLauncher then
        applySavedPosition(UI.TransmogLauncher, "transmogLauncher", TRANSMOG_DEFAULT)
    end
    if UI.CollectionsFrame then
        if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() then
            SC.UIPlatform:RestoreWindow(UI.CollectionsFrame)
        elseif SC.db and SC.db.frame then
            local saved = SC.db.frame
            UI.CollectionsFrame:ClearAllPoints()
            UI.CollectionsFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
            UI.CollectionsFrame:SetClampedToScreen(true)
        end
    end
    if UI.TransmogFrame then
        if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() and SC.UIPlatform.RestoreTransmogWindow then
            SC.UIPlatform:RestoreTransmogWindow(UI.TransmogFrame)
        elseif SC.db and SC.db.transmogFrame then
            local saved = SC.db.transmogFrame
            UI.TransmogFrame:ClearAllPoints()
            UI.TransmogFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
            UI.TransmogFrame:SetClampedToScreen(true)
        end
    end
    if UI.SyncJournalFromDatabase then
        UI.SyncJournalFromDatabase()
    end
end
