local SC = SoloCollections
local UI = SC.UI
local CS = SC.CollectionState

local DESIGN_SCREEN_WIDTH = 1920
local DESIGN_SCREEN_HEIGHT = 1080
local COLLECTION_WIDTH = 703
local TRANSMOG_WIDTH = 965
local JOURNAL_HEIGHT = 606
local MIN_SCALE = 0.72
local TITLE_VISIBLE_ROWS = 10
local TITLE_ROW_HEIGHT = 46

local TAB_DEFINITIONS = {
    { key = "MOUNTS", label = "坐骑", title = "坐骑", cutoff = true },
    { key = "PETS", label = "小宠物", title = "小宠物", cutoff = true },
    { key = "TOYS", label = "玩具箱", title = "玩具箱" },
    { key = "TITLES", label = "头衔", title = "头衔（只读）" },
    { key = "WARDROBE", label = "外观", title = "外观" },
    { key = "TRANSMOG_LAB", label = "幻化", title = "幻化", cutoff = true },
}

local function isTabAvailable(key)
    if key == "TRANSMOG_LAB" then
        return SC.db and SC.db.experimental and SC.db.experimental.transmogLabEnabled == true
    end
    return true
end

local function titleRecords()
    local records = {}
    local count = type(GetNumTitles) == "function" and tonumber(GetNumTitles()) or 0
    local query = SC.db and string.lower(SC.db.query or "") or ""
    local filters = SC.db and SC.db.filters or {}
    for titleIndex = 1, count do
        local ok, name = pcall(GetTitleName, titleIndex)
        if ok and type(name) == "string" and name ~= "" then
            name = string.gsub(name, "%%s", UnitName("player") or "")
            local nativeKnown = type(IsTitleKnown) == "function" and IsTitleKnown(titleIndex) and true or false
            local owned, authoritative, state = CS.ResolveOwned("TITLES", titleIndex, nativeKnown)
            local matchesQuery = query == "" or string.find(string.lower(name), query, 1, true) ~= nil
            local matchesOwned = (owned and filters.collected ~= false) or
                (not owned and filters.uncollected ~= false)
            if matchesQuery and matchesOwned then
                table.insert(records, {
                    id = titleIndex,
                    name = name,
                    owned = owned,
                    authoritative = authoritative,
                    state = state,
                    assetReady = true,
                })
            end
        end
    end
    return records, count
end

function UI.CreateTitlesPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scRows = {}

    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
    panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 5)
    local panelInset = UI.EzCollections:ApplyInset(panel)
    UI.EzCollections:AddShadowOverlay(panel)
    SC.WardrobeUI.Layout:StylePanel(panel, panelInset.background)

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
    note:SetText("只读视图：头衔拥有状态来自服务端角色数据；本页不会授予或切换头衔。")
    note:SetTextColor(0.72, 0.68, 0.60)

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "SoloCollectionsTitleScrollFrame",
        panel,
        "FauxScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -36)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 29)
    scrollFrame:EnableMouseWheel(true)
    UI.EzCollections:SkinTrimScrollFrame(scrollFrame)

    local listTexture = UI.EzCollections:MediaPath(
        "Buttons",
        "ListButtons.tga",
        "Interface\\Buttons\\WHITE8X8"
    )
    for index = 1, TITLE_VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetHeight(TITLE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 7, -(36 + (index - 1) * TITLE_ROW_HEIGHT))
        row:SetPoint("RIGHT", panel, "RIGHT", -22, 0)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(row)
        background:SetTexture(listTexture)
        background:SetTexCoord(0.00390625, 0.8203125, 0.00390625, 0.18359375)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(row)
        highlight:SetTexture(listTexture)
        highlight:SetTexCoord(0.00390625, 0.8203125, 0.19140625, 0.37109375)
        local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("LEFT", row, "LEFT", 12, 0)
        name:SetJustifyH("LEFT")
        local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetWidth(370)
        status:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        status:SetJustifyH("RIGHT")
        name:SetPoint("RIGHT", status, "LEFT", -10, 0)
        row.scName = name
        row.scStatus = status
        row.scBackground = background
        page.scRows[index] = row
    end

    local function refreshRows()
        local records = page.scRecords or {}
        FauxScrollFrame_Update(scrollFrame, #records, TITLE_VISIBLE_ROWS, TITLE_ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        local current = type(GetCurrentTitle) == "function" and tonumber(GetCurrentTitle()) or 0
        for index, row in ipairs(page.scRows) do
            local record = records[offset + index]
            if record then
                row.scName:SetText(record.name)
                row.scName:SetTextColor(record.owned and 1.00 or 0.50, record.owned and 0.82 or 0.47, 0.24)
                if not record.authoritative then
                    row.scStatus:SetText("目录可见 · 拥有状态加载中 · 资源已安装")
                elseif record.id == current then
                    row.scStatus:SetText("目录可见 · 已拥有 · 当前可用（已启用） · 资源已安装")
                elseif record.owned then
                    row.scStatus:SetText("目录可见 · 已拥有 · 当前可用（只读） · 资源已安装")
                else
                    row.scStatus:SetText("目录可见 · 未拥有 · 当前不可用 · 资源已安装")
                end
                row:Show()
            else
                row:Hide()
            end
        end
    end

    local function scrollByWheel(self, delta)
        local currentOffset = FauxScrollFrame_GetOffset(self) or 0
        local maximumOffset = math.max(0, #(page.scRecords or {}) - TITLE_VISIBLE_ROWS)
        local newOffset = math.max(0, math.min(maximumOffset, currentOffset - delta))
        FauxScrollFrame_OnVerticalScroll(
            self,
            newOffset * TITLE_ROW_HEIGHT,
            TITLE_ROW_HEIGHT,
            refreshRows
        )
    end

    for _, row in ipairs(page.scRows) do
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            scrollByWheel(scrollFrame, delta)
        end)
    end
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, TITLE_ROW_HEIGHT, refreshRows)
    end)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollByWheel(self, delta)
    end)

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not (frame and frame.scFilterPopup and SC.db and SC.db.filters) then return end
        frame.scFilterPopup:SetOptions({
            {
                label = "已收集",
                checked = SC.db.filters.collected ~= false,
                onClick = function()
                    SC.db.filters.collected = not (SC.db.filters.collected ~= false)
                    page:Refresh()
                end,
            },
            {
                label = "未收集",
                checked = SC.db.filters.uncollected ~= false,
                onClick = function()
                    SC.db.filters.uncollected = not (SC.db.filters.uncollected ~= false)
                    page:Refresh()
                end,
            },
        })
    end

    function page:Refresh()
        local records, total = titleRecords()
        self.scRecords = records
        local ownedCount = 0
        for titleIndex = 1, total do
            local owned = CS.ResolveOwned("TITLES", titleIndex, false)
            if owned then ownedCount = ownedCount + 1 end
        end
        if UI.CollectionsFrame then
            UI.CollectionsFrame.scCollectionCount:SetCount(ownedCount, total)
            UI.CollectionsFrame.scProgress:SetProgress(ownedCount, total)
        end
        refreshRows()
        self:SyncFilters()
    end

    page.scPanel = panel
    page.scPanelBackground = panelInset.background
    page.scScrollFrame = scrollFrame
    page.scNote = note
    return page
end

local function getResponsiveScale()
    local widthScale = UIParent:GetWidth() / DESIGN_SCREEN_WIDTH
    local heightScale = UIParent:GetHeight() / DESIGN_SCREEN_HEIGHT
    return math.max(MIN_SCALE, math.min(1, widthScale, heightScale))
end

local function clampFrame(frame)
    frame:SetScale(getResponsiveScale())
    frame:SetClampRectInsets(0, 0, 0, -40)
    frame:SetClampedToScreen(false)
    frame:SetClampedToScreen(true)
end

local function applyJournalSize(frame, key)
    local width = key == "TRANSMOG_LAB" and TRANSMOG_WIDTH or COLLECTION_WIDTH
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
    if not (host and search and filter) then return end
    host:ClearAllPoints()
    search:ClearAllPoints()
    filter:ClearAllPoints()
    if key == "TOYS" or key == "TITLES" or key == "WARDROBE" then
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
    local activeKey = SC.db.mainTab
    if SC.db.mainTab == "MOUNTS" then
        activeKey = "MOUNTS"
    elseif SC.db.mainTab == "PETS" then
        activeKey = "PETS"
    elseif SC.db.mainTab == "TOYS" then
        activeKey = "TOYS"
    elseif SC.db.mainTab == "WARDROBE" then
        activeKey = "WARDROBE"
    elseif SC.db.mainTab == "TRANSMOG_LAB" then
        activeKey = "TRANSMOG_LAB"
    elseif SC.db.mainTab == "TITLES" then
        activeKey = "TITLES"
    end
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
    frame.scFilterPopup:Hide()
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

function UI.SetMainTab(key)
    local selected = "MOUNTS"
    for _, definition in ipairs(TAB_DEFINITIONS) do
        if definition.key == key and isTabAvailable(key) then
            selected = key
            break
        end
    end
    SC.db.mainTab = selected

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
        portrait:SetTexture(UI.Media.mountPortrait)
        portrait:SetTexCoord(0, 1, 0, 1)
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
        portrait:SetTexture(UI.Media.mountPortrait)
        portrait:SetTexCoord(0, 1, 0, 1)

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
    filterButton:SetHeight(22)
    filterButton:SetPoint("LEFT", search, "RIGHT", 2, 0)
    UI.EzCollections:SkinSilverMenuButton(filterButton)

    local wardrobeTabs = CreateFrame("Frame", nil, frame)
    wardrobeTabs:SetWidth(150)
    wardrobeTabs:SetHeight(24)
    wardrobeTabs:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -28)
    wardrobeTabs:SetFrameLevel(frame:GetFrameLevel() + 20)
    local itemTab = UI.CreateTopSubTab(wardrobeTabs, "物品", function()
        UI.SetWardrobeTab("ITEMS")
    end)
    itemTab:SetPoint("LEFT", wardrobeTabs, "LEFT", 0, 0)
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
    frame.scWardrobeTabs = wardrobeTabs
    frame.scWardrobeItemTab = itemTab
    frame.scWardrobeSetTab = setTab
    frame.scContentHost = contentHost
    frame.scLegacyContentHost = legacyContentHost
    frame.scPages = {
        MOUNTS = UI.CreateMountsPage(contentHost),
        PETS = UI.CreatePetsPage(contentHost),
        TOYS = UI.CreateToysPage(contentHost),
        WARDROBE = UI.CreateWardrobePage(contentHost),
        TITLES = UI.CreateTitlesPage(contentHost),
    }
    if isTabAvailable("TRANSMOG_LAB") and SC.WardrobeLab and SC.WardrobeLab.CreatePage then
        frame.scPages.TRANSMOG_LAB = SC.WardrobeLab.CreatePage(legacyContentHost)
    end
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
end)
