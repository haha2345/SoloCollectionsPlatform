local SC = SoloCollections
local UI = SC.UI
UI.DragonUI = UI.DragonUI or {}

local MountJournal = UI.DragonUI.MountJournal or {}
UI.DragonUI.MountJournal = MountJournal
UI.DragonUI.CompanionJournal = MountJournal

-- Shared geometry and visual adapter for mount/companion journals. Keep the
-- historical MountJournal table and methods as stable compatibility aliases.
MountJournal.LAYOUT = {
    width = 768,
    height = 606,
    topBandHeight = 40,
    bottomBandHeight = 40,
    topControlsY = 68,
    randomDetailGap = 6,
    listTop = 96,
    bottomInset = 44,
    sidePad = 14,
    listWidth = 260,
    gap = 24,
    rightPad = 14,
    actionWidth = 180,
    actionHeight = 26,
    filterWidth = 76,
    controlHeight = 20,
    rowHeight = 46,
    rowStartY = 3,
    visibleRows = 10,
    tabHeight = 36,
    selectedTabHeight = 42,
}

local REQUIRED = {
    "components.collection-header",
    "components.journal-filter",
    "components.random-collection",
    "components.random-mount",
    "components.red-action",
    "components.journal-tabs",
}

local function components()
    local platform = SC.UIPlatform
    if not (platform and platform:CanCreateUI()) then return nil end
    local public = platform:GetPublic()
    local value = public and public.Components
    if not value then
        if platform then platform:ShowError("components") end
        return nil
    end
    for _, capability in ipairs(REQUIRED) do
        if not public.HasCapability or not public.HasCapability(capability) then
            platform:ShowError(capability)
            return nil
        end
    end
    return value
end

function MountJournal:GetLayout()
    local copy = {}
    for key, value in pairs(self.LAYOUT) do copy[key] = value end
    return copy
end

function MountJournal:CreateCollectionInfoHeader(parent, spec)
    local c = components()
    if not c then return nil end
    return c:CreateCollectionInfoHeader(parent, spec or {})
end

-- Semantic companion alias: both journals intentionally share the same
-- icon crop, gold ornament, name origin, and source/description widths.
function MountJournal:CreateCompanionInfoHeader(parent, spec)
    return self:CreateCollectionInfoHeader(parent, spec or {})
end

function MountJournal:CreateJournalFilterButton(parent, spec)
    local c = components()
    if not c then return nil end
    return c:CreateJournalFilterButton(parent, spec or {})
end

function MountJournal:CreateRandomMountButton(parent, spec)
    local c = components()
    if not c then return nil end
    return c:CreateRandomMountButton(parent, spec or {})
end

function MountJournal:CreateRandomCompanionButton(parent, spec)
    local c = components()
    if not c then return nil end
    return c:CreateRandomCollectionButton(parent, spec or {})
end

function MountJournal:SkinRedActionButton(button, spec)
    local c = components()
    if not c then return false end
    return c:SkinRedActionButton(button, spec or {})
end

function MountJournal:CreateJournalTab(parent, index, labelText, onClick, cutoff)
    local c = components()
    if not c then return nil end
    return c:CreateJournalTab(parent, {
        index = index,
        label = labelText,
        onClick = onClick,
        cutoff = cutoff and true or false,
        height = self.LAYOUT.tabHeight,
        selectedHeight = self.LAYOUT.selectedTabHeight,
    })
end

function MountJournal:SetJournalTabSelected(button, selected)
    local c = components()
    if not c then return false end
    return c:SetJournalTabSelected(button, selected)
end

function MountJournal:LayoutJournalTabs(parent, tabs)
    local c = components()
    if not c then return false end
    return c:LayoutJournalTabs(parent, tabs, {
        startX = self.LAYOUT.sidePad,
        startY = 2,
        gap = 1,
        minWidth = 70,
        textPadding = 30,
    })
end

function MountJournal:CreateBands(page)
    local layout = self.LAYOUT
    local bands = {}
    bands.top = CreateFrame("Frame", nil, page)
    bands.top:SetPoint("TOPLEFT", page, "TOPLEFT", layout.sidePad, -layout.topControlsY)
    bands.top:SetPoint("TOPRIGHT", page, "TOPRIGHT", -layout.rightPad, -layout.topControlsY)
    bands.top:SetHeight(layout.topBandHeight)

    bands.bottom = CreateFrame("Frame", nil, page)
    bands.bottom:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", layout.sidePad, 4)
    bands.bottom:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -layout.rightPad, 4)
    bands.bottom:SetHeight(layout.bottomBandHeight)
    return bands
end

function MountJournal:LayoutInset(frame, side)
    if not frame then return end
    local layout = self.LAYOUT
    local parent = frame:GetParent()
    frame:ClearAllPoints()
    if side == "left" then
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", layout.sidePad, -layout.listTop)
        frame:SetWidth(layout.listWidth)
        frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", layout.sidePad, layout.bottomInset)
    else
        frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -layout.rightPad, -layout.listTop)
        frame:SetWidth(layout.width - layout.sidePad - layout.listWidth - layout.gap - layout.rightPad)
        frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -layout.rightPad, layout.bottomInset)
    end
end
