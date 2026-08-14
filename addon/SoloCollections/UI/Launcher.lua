local SC = SoloCollections
local UI = SC.UI

local DEFAULT_POINT = "BOTTOMRIGHT"
local DEFAULT_X = -28
local DEFAULT_Y = 150

local function applySavedPosition(button)
    local saved = SC.db and SC.db.launcher
    button:ClearAllPoints()
    button:SetPoint(
        (saved and saved.point) or DEFAULT_POINT,
        UIParent,
        (saved and saved.relativePoint) or DEFAULT_POINT,
        (saved and saved.x) or DEFAULT_X,
        (saved and saved.y) or DEFAULT_Y
    )
    button:SetClampedToScreen(true)
end

local function savePosition(button)
    if not SC.db then
        return
    end
    local point, _, relativePoint, x, y = button:GetPoint(1)
    SC.db.launcher = {
        point = point or DEFAULT_POINT,
        relativePoint = relativePoint or DEFAULT_POINT,
        x = math.floor((x or DEFAULT_X) + 0.5),
        y = math.floor((y or DEFAULT_Y) + 0.5),
    }
end

function UI.CreateLauncher()
    if UI.Launcher then
        return UI.Launcher
    end
    if SC.UIPlatform and not SC.UIPlatform:CanCreateUI() then return nil end

    local button = CreateFrame("Button", "SoloCollectionsLauncher", UIParent)
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
    icon:SetTexture(UI.Media.launcher)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -6)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    ring:SetVertexColor(0.92, 0.78, 0.43, 1)

    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("收藏")
        GameTooltip:AddLine("点击打开收藏日志，拖动可改变位置。", 0.82, 0.72, 0.52, true)
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
        savePosition(self)
    end)
    button:SetScript("OnClick", function(self)
        if self.scWasDragged then
            self.scWasDragged = nil
            return
        end
        SC:ToggleJournal()
    end)

    UI.Launcher = button
    applySavedPosition(button)
    return button
end

function UI.ResetPositions()
    if UI.Launcher then
        applySavedPosition(UI.Launcher)
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
    if UI.SyncJournalFromDatabase then
        UI.SyncJournalFromDatabase()
    end
end
