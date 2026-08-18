local SC = SoloCollections
local UI = SC.UI
local MountJournal = UI.DragonUI and UI.DragonUI.MountJournal

local DESIGN_SCREEN_WIDTH = 1920
local DESIGN_SCREEN_HEIGHT = 1080
local COLLECTION_WIDTH = 703
local COMPANION_JOURNAL_WIDTH = 768
local JOURNAL_HEIGHT = 606
local MIN_SCALE = 0.72

local TAB_DEFINITIONS = {
    { key = "MOUNTS", label = "坐骑", title = "坐骑", cutoff = true },
    { key = "PETS", label = "小宠物", title = "小宠物", cutoff = true },
    { key = "TITLES", label = "头衔", title = "头衔（只读）" },
    { key = "WARDROBE", label = "外观", title = "外观" },
}

local function isTabAvailable(key)
    return true
end

local function getResponsiveScale()
    local widthScale = UIParent:GetWidth() / DESIGN_SCREEN_WIDTH
    local heightScale = UIParent:GetHeight() / DESIGN_SCREEN_HEIGHT
    return math.max(MIN_SCALE, math.min(1, widthScale, heightScale))
end

local function clampFrame(frame)
    frame:SetScale(getResponsiveScale())
    frame:SetClampRectInsets(0, 0, 0, -44)
    frame:SetClampedToScreen(false)
    frame:SetClampedToScreen(true)
end

local function applyJournalSize(frame, key)
    local width
    if key == "MOUNTS" or key == "PETS" or key == "WARDROBE" then
        width = COMPANION_JOURNAL_WIDTH
    else
        width = COLLECTION_WIDTH
    end
    frame:SetWidth(width)
    frame:SetHeight(JOURNAL_HEIGHT)
    frame.scJournalWidth = width
    if UI.EzCollections then
        UI.EzCollections:UpdateBodyCanvas(frame)
        UI.EzCollections:LayoutJournalTabs(frame, frame.scMainTabOrder)
    end
    clampFrame(frame)
end

local function applyJournalControlLayout(frame, key)
    local host = frame.scSearchFilterHost
    local search = frame.scSearchBox
    local filter = frame.scFilterButton
    local companionFilter = frame.scCompanionFilterButton
    if not (host and search and filter) then return end
    if CloseDropDownMenus then CloseDropDownMenus() end
    if frame.scFilterPopup then frame.scFilterPopup:Hide() end
    host:ClearAllPoints()
    search:ClearAllPoints()
    filter:ClearAllPoints()
    if (key == "MOUNTS" or key == "PETS") and companionFilter then
        filter:Hide()
        if frame.scFilterPopup then frame.scFilterPopup:Hide() end
        companionFilter:Show()
        host:SetWidth(276)
        host:SetHeight(20)
        host:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -68)
        search:SetWidth(194)
        search:SetPoint("LEFT", host, "LEFT", 0, 0)
        companionFilter:ClearAllPoints()
        companionFilter:SetSize(76, 20)
        companionFilter:SetPoint("LEFT", search, "RIGHT", 4, 0)
    else
        if companionFilter then companionFilter:Hide() end
        filter:Show()
        if key == "TITLES" or key == "WARDROBE" then
            host:SetWidth(210)
            host:SetHeight(22)
            host:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -34)
            search:SetWidth(115)
            search:SetPoint("LEFT", host, "LEFT", 0, -1)
            filter:SetPoint("LEFT", search, "RIGHT", 2, 1)
        else
            host:SetWidth(240)
            host:SetHeight(22)
            host:SetPoint("TOPLEFT", frame, "TOPLEFT", 19, -69)
            search:SetWidth(145)
            search:SetPoint("LEFT", host, "LEFT", 0, 0)
            filter:SetPoint("LEFT", search, "RIGHT", 2, 0)
        end
    end
end

local function saveFramePosition(frame)
    if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() then return end
    if not SC.db then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    SC.db.frame = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function restoreFramePosition(frame)
    if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() then
        SC.UIPlatform:RestoreWindow(frame)
        clampFrame(frame)
        return
    end
    local saved = SC.db and SC.db.frame
    frame:ClearAllPoints()
    frame:SetPoint(
        (saved and saved.point) or "CENTER",
        UIParent,
        (saved and saved.relativePoint) or "CENTER",
        (saved and saved.x) or 0,
        (saved and saved.y) or 0
    )
    clampFrame(frame)
end

local function refreshPage()
    if UI.scSuppressRefresh then
        return
    end
    if UI.RefreshActivePage then
        UI.RefreshActivePage()
    end
end

function UI.RefreshActivePage()
    local frame = UI.CollectionsFrame
    if not frame or not frame.scPages or not SC.db then
        return
    end
    local activeKey = SC.db.mainTab or "MOUNTS"
    for key, page in pairs(frame.scPages) do
        if key == activeKey then
            page:Show()
            if page.Refresh then
                page:Refresh()
            end
        else
            page:Hide()
        end
    end
end

function UI.SyncJournalFromDatabase()
    local frame = UI.CollectionsFrame
    if not frame or not SC.db then
        return
    end

    UI.scSuppressRefresh = true
    frame.scSearchBox:SetText(SC.db.query or "")
    if frame.scFilterPopup then frame.scFilterPopup:Hide() end
    if CloseDropDownMenus then CloseDropDownMenus() end
    if frame.scFilterButton.scArrow then
        frame.scFilterButton.scArrow:SetTexCoord(0, 1, 0, 1)
    end
    if UI.SyncFilterControls then
        UI.SyncFilterControls()
    end
    UI.SetWardrobeTab(SC.db.wardrobeTab)
    UI.SetMainTab(SC.db.mainTab)
    UI.scSuppressRefresh = nil
    refreshPage()
end

function UI.SetWardrobeTab(key)
    if key ~= "ITEMS" and key ~= "SETS" then
        key = "ITEMS"
    end
    SC.db.wardrobeTab = key
    local frame = UI.CollectionsFrame
    if not frame then
        return
    end
    frame.scWardrobeItemTab:SetSelected(key == "ITEMS")
    frame.scWardrobeSetTab:SetSelected(key == "SETS")
    refreshPage()
end

local TAB_UI_STATE_KEYS = {
    MOUNTS = true, PETS = true, WARDROBE = true, TITLES = true,
}

local function defaultTabUiSlice()
    return { query = "", collected = true, uncollected = true, favorites = false }
end

local function ensureTabUiSlice(tab)
    if not SC.db or not TAB_UI_STATE_KEYS[tab] then
        return nil
    end
    if type(SC.db.tabUiState) ~= "table" then
        SC.db.tabUiState = {}
    end
    local slice = SC.db.tabUiState[tab]
    if type(slice) ~= "table" then
        slice = defaultTabUiSlice()
        SC.db.tabUiState[tab] = slice
    end
    return slice
end

local function captureTabUiState(tab)
    local slice = ensureTabUiSlice(tab)
    if not slice then
        return
    end
    slice.query = SC.db.query or ""
    local filters = SC.db.filters
    if type(filters) ~= "table" then
        filters = {}
        SC.db.filters = filters
    end
    slice.collected = filters.collected ~= false
    slice.uncollected = filters.uncollected ~= false
    slice.favorites = filters.favorites and true or false
end

local function restoreTabUiState(tab)
    local slice = ensureTabUiSlice(tab)
    if not slice then
        return
    end
    SC.db.query = slice.query or ""
    if type(SC.db.filters) ~= "table" then
        SC.db.filters = {}
    end
    SC.db.filters.collected = slice.collected ~= false
    SC.db.filters.uncollected = slice.uncollected ~= false
    SC.db.filters.favorites = slice.favorites and true or false
end

function UI.SetMainTab(key)
    local selected = "MOUNTS"
    for _, definition in ipairs(TAB_DEFINITIONS) do
        if definition.key == key and isTabAvailable(key) then
            selected = key
            break
        end
    end
    if SC.db then
        captureTabUiState(SC.db.mainTab)
        SC.db.mainTab = selected
        restoreTabUiState(selected)
    end

    local frame = UI.CollectionsFrame
    if not frame then
        return
    end
    applyJournalSize(frame, selected)
    applyJournalControlLayout(frame, selected)
    for tabKey, button in pairs(frame.scMainTabs) do
        button:SetSelected(tabKey == selected)
    end
    frame.scPageTitle:SetText(frame.scTabTitles[selected])
    if frame.scSearchBox then
        local previousSuppress = UI.scSuppressRefresh
        UI.scSuppressRefresh = true
        frame.scSearchBox:SetText((SC.db and SC.db.query) or "")
        UI.scSuppressRefresh = previousSuppress
    end
    if UI.EzCollections then
        UI.EzCollections:SetPortraitForTab(frame, selected)
    elseif selected == "MOUNTS" then
        frame.scPortrait:SetTexture(UI.Media.mountPortrait)
        frame.scPortrait:SetTexCoord(0, 1, 0, 1)
    else
        frame.scPortrait:SetTexture(UI.Media.tabs[selected] or UI.Media.launcher)
        frame.scPortrait:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if selected == "MOUNTS" or selected == "PETS" or selected == "TITLES" then
        frame.scCollectionCount:Show()
        if selected == "MOUNTS" then
            frame.scCollectionCount:SetLabel("所有坐骑")
        elseif selected == "PETS" then
            frame.scCollectionCount:SetLabel("所有小宠物")
        else
            frame.scCollectionCount:SetLabel("已获头衔")
        end
        if selected ~= "TITLES" and SC.Catalog and SC.Catalog.GetProgress then
            local collected, total = SC.Catalog.GetProgress(selected)
            frame.scCollectionCount:SetCount(collected, total)
            frame.scProgress:SetProgress(collected, total)
        end
    else
        frame.scCollectionCount:Hide()
    end
    if selected == "WARDROBE" then
        frame.scWardrobeTabs:Show()
        UI.SetWardrobeTab(SC.db.wardrobeTab)
    else
        frame.scWardrobeTabs:Hide()
        refreshPage()
    end
end

function UI.CreateCollectionsFrame()
    if UI.CollectionsFrame then
        return UI.CollectionsFrame
    end

    if SC.UIPlatform and not SC.UIPlatform:CanCreateUI() then return nil end
    local frame = UI.CreateJournalFrame(UIParent, "SoloCollectionsJournal", COLLECTION_WIDTH, JOURNAL_HEIGHT)
    local dragonShell = UI.IsDragonUIShell and UI.IsDragonUIShell()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:Hide()

    if not dragonShell then
        frame:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            clampFrame(self)
            saveFramePosition(self)
        end)
    end
    frame:SetScript("OnShow", function(self)
        clampFrame(self)
        UI.RefreshActivePage()
    end)

    if dragonShell and SC.UIPlatform then SC.UIPlatform:PersistWindow(frame, frame) end

    local closeButton = dragonShell and frame.CloseButton or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    if not dragonShell then closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -9) end
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local progress = UI.CreateRetailProgressBar(frame, 194)
    progress:SetWidth(210)
    progress:SetHeight(20)
    progress:SetPoint("TOP", frame, "TOP", 0, -35)
    progress.scStatusBar:SetWidth(194)
    progress.scStatusBar:SetHeight(10)
    progress.scBorder:Hide()
    UI.EzCollections:ApplyInputBorder(progress)

    local pageTitle = dragonShell and frame.Title or frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if not dragonShell then pageTitle:SetPoint("TOP", frame, "TOP", 0, -17) end
    pageTitle:SetTextColor(1, 0.82, 0.18)

    local portraitFrame
    local portrait
    local portraitRing
    if dragonShell and frame.portrait then
        portraitFrame = frame
        portrait = frame.portrait
        portraitRing = frame.portraitRing or frame.PortraitFrame
        if SetPortraitToTexture then
            SetPortraitToTexture(portrait, UI.Media.mountPortrait)
        else
            portrait:SetTexture(UI.Media.mountPortrait)
            portrait:SetTexCoord(0, 1, 0, 1)
        end
    else
        portraitFrame = CreateFrame("Frame", nil, frame)
        portraitFrame:SetWidth(80)
        portraitFrame:SetHeight(80)
        portraitFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -7, 5)
        portraitFrame:SetFrameLevel(frame:GetFrameLevel() + 4)

        portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
        portrait:SetWidth(62)
        portrait:SetHeight(62)
        portrait:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
        if SetPortraitToTexture then
            SetPortraitToTexture(portrait, UI.Media.mountPortrait)
        else
            portrait:SetTexture(UI.Media.mountPortrait)
            portrait:SetTexCoord(0, 1, 0, 1)
        end

        portraitRing = portraitFrame:CreateTexture(nil, "OVERLAY")
        portraitRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        portraitRing:SetWidth(80)
        portraitRing:SetHeight(80)
        portraitRing:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
        portraitRing:SetTexCoord(0, 0.625, 0, 0.625)
    end

    local collectionCount = UI.CreateCollectionCount(frame)
    collectionCount:SetWidth(130)
    collectionCount:SetHeight(20)
    collectionCount:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -35)
    UI.EzCollections:ApplyInputBorder(collectionCount)

    local searchFilterHost = CreateFrame("Frame", nil, frame)
    searchFilterHost:SetHeight(22)
    searchFilterHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 19, -69)
    searchFilterHost:SetWidth(240)
    searchFilterHost:SetFrameLevel(frame:GetFrameLevel() + 20)

    local search = UI.CreateRetailSearchBox(searchFilterHost, 145, function(value)
        if SC.db then
            SC.db.query = value or ""
        end
        refreshPage()
    end)
    search:SetPoint("LEFT", searchFilterHost, "LEFT", 0, 0)
    UI.EzCollections:SkinSearchBox(search)

    local filterButton, filterPopup = UI.CreateFilterPopup(searchFilterHost, 93)
    local wardrobeFilterDropDown = CreateFrame(
        "Frame",
        "SoloCollectionsWardrobeFilterDropDown",
        searchFilterHost,
        "UIDropDownMenuTemplate"
    )
    wardrobeFilterDropDown:Hide()
    filterButton:SetWardrobeDropDown(wardrobeFilterDropDown)
    filterButton:SetHeight(22)
    filterButton:SetPoint("LEFT", search, "RIGHT", 2, 0)
    UI.EzCollections:SkinSilverMenuButton(filterButton)

    local companionFilterButton = MountJournal and MountJournal:CreateJournalFilterButton(searchFilterHost, {
        label = "筛选",
        width = 76,
        height = 20,
    })
    if not companionFilterButton then
        companionFilterButton = CreateFrame("Button", nil, searchFilterHost, "UIPanelButtonTemplate")
        companionFilterButton:SetText("筛选")
        UI.EzCollections:SkinSilverMenuButton(companionFilterButton)
    end
    companionFilterButton:SetSize(76, 20)
    companionFilterButton:SetScript("OnClick", function(self)
        local key = SC.db and SC.db.mainTab
        local page = UI.CollectionsFrame and UI.CollectionsFrame.scPages and UI.CollectionsFrame.scPages[key]
        if page and page.OpenFilterMenu then page:OpenFilterMenu(self) end
    end)
    companionFilterButton:Hide()

    local wardrobeTabs = CreateFrame("Frame", nil, frame)
    wardrobeTabs:SetWidth(150)
    wardrobeTabs:SetHeight(32)
    wardrobeTabs:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -28)
    wardrobeTabs:SetFrameLevel(frame:GetFrameLevel() + 20)
    local itemTab = UI.CreateTopSubTab(wardrobeTabs, "物品", function()
        UI.SetWardrobeTab("ITEMS")
    end)
    itemTab:SetPoint("TOPLEFT", wardrobeTabs, "TOPLEFT", 0, 0)
    local setTab = UI.CreateTopSubTab(wardrobeTabs, "套装", function()
        UI.SetWardrobeTab("SETS")
    end)
    setTab:SetPoint("LEFT", itemTab, "RIGHT", 0, 0)
    wardrobeTabs:Hide()

    local contentHost = CreateFrame("Frame", nil, frame)
    contentHost:SetAllPoints(frame)
    local legacyContentHost = CreateFrame("Frame", nil, contentHost)
    legacyContentHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 31, -122)
    legacyContentHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -31, 24)

    frame.scMainTabs = {}
    frame.scMainTabOrder = {}
    frame.scTabTitles = {}
    local tabIndex = 0
    for _, definition in ipairs(TAB_DEFINITIONS) do
        if isTabAvailable(definition.key) then
            tabIndex = tabIndex + 1
            local tabKey = definition.key
            local button = UI.EzCollections:CreateJournalTab(frame, tabIndex, definition.label, function()
                UI.SetMainTab(tabKey)
            end, definition.cutoff)
            frame.scMainTabs[tabKey] = button
            frame.scMainTabOrder[#frame.scMainTabOrder + 1] = button
            frame.scTabTitles[tabKey] = definition.title
        end
    end
    UI.EzCollections:LayoutJournalTabs(frame, frame.scMainTabOrder)

    frame.scTitle = pageTitle
    frame.scPortraitFrame = portraitFrame
    frame.scPortrait = portrait
    frame.scPortraitRing = portraitRing
    frame.scCollectionCount = collectionCount
    frame.scMountCount = collectionCount
    frame.scCloseButton = closeButton
    frame.scProgress = progress
    frame.scPageTitle = pageTitle
    frame.scSearchFilterHost = searchFilterHost
    frame.scSearchBox = search
    frame.scFilterButton = filterButton
    frame.scFilterPopup = filterPopup
    frame.scCompanionFilterButton = companionFilterButton
    frame.scMountFilterButton = companionFilterButton
    frame.scWardrobeFilterDropDown = wardrobeFilterDropDown
    frame.scWardrobeTabs = wardrobeTabs
    frame.scWardrobeItemTab = itemTab
    frame.scWardrobeSetTab = setTab
    frame.scContentHost = contentHost
    frame.scLegacyContentHost = legacyContentHost
    frame.scPages = {
        MOUNTS = UI.CreateMountsPage(contentHost),
        PETS = UI.CreatePetsPage(contentHost),
        TITLES = UI.CreateTitlesPage(contentHost),
        WARDROBE = UI.CreateWardrobePage(contentHost),
    }
    UI.EzCollections:Guard(contentHost, "收藏日志内页已锁定到 ezCollections 2.2 素材")

    UI.CollectionsFrame = frame
    search:SetText((SC.db and SC.db.query) or "")
    restoreFramePosition(frame)
    UI.SetMainTab((SC.db and SC.db.mainTab) or "MOUNTS")

    if UISpecialFrames then
        table.insert(UISpecialFrames, "SoloCollectionsJournal")
    end
    return frame
end

function UI.ToggleJournal()
    local frame = UI.CreateCollectionsFrame()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        if UI.HideTransmog then UI.HideTransmog() end
        restoreFramePosition(frame)
        frame:Show()
    end
end

function UI.ShowJournal()
    local frame = UI.CreateCollectionsFrame()
    if not frame then return end
    if UI.HideTransmog then UI.HideTransmog() end
    if not frame:IsShown() then
        restoreFramePosition(frame)
        frame:Show()
    end
end

function UI.HideJournal()
    if UI.CollectionsFrame then UI.CollectionsFrame:Hide() end
end

local displayWatcher = CreateFrame("Frame")
displayWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
displayWatcher:RegisterEvent("UI_SCALE_CHANGED")
displayWatcher:SetScript("OnEvent", function()
    if UI.CollectionsFrame then
        restoreFramePosition(UI.CollectionsFrame)
    end
    if UI.Launcher then
        UI.Launcher:SetClampedToScreen(true)
    end
    if UI.TransmogLauncher then
        UI.TransmogLauncher:SetClampedToScreen(true)
    end
end)
