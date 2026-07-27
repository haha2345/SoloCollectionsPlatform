local SC = SoloCollections
local UI = SC.UI
local CS = SC.CollectionState

local DESIGN_SCREEN_WIDTH = 1920
local DESIGN_SCREEN_HEIGHT = 1080
local JOURNAL_WIDTH = 920
local JOURNAL_HEIGHT = 793
local MIN_SCALE = 0.72
local TITLE_VISIBLE_ROWS = 16
local TITLE_ROW_HEIGHT = 35

local TAB_DEFINITIONS = {
    { key = "MOUNTS", label = "坐骑", title = "坐骑" },
    { key = "PETS", label = "小宠物", title = "小宠物" },
    { key = "TOYS", label = "玩具箱", title = "玩具箱" },
    { key = "WARDROBE", label = "外观", title = "外观" },
    { key = "TITLES", label = "头衔", title = "头衔（只读）" },
}

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
    page.scOffset = 0
    page.scRows = {}
    page:EnableMouseWheel(true)

    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", page, "TOPLEFT", 5, -8)
    panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -5, 10)
    UI.ApplyNineSlice(panel, UI.Media.border, 18)

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    background:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -5, 5)
    background:SetVertexColor(0.025, 0.019, 0.013, 0.94)

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 11)
    note:SetText("只读视图：头衔拥有状态来自服务端角色数据；本页不会授予或切换头衔。")
    note:SetTextColor(0.72, 0.68, 0.60)

    for index = 1, TITLE_VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(TITLE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12 - (index - 1) * TITLE_ROW_HEIGHT)
        row:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
        stripe:SetVertexColor(index % 2 == 0 and 0.10 or 0.06, 0.055, 0.04, 0.65)
        local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("LEFT", row, "LEFT", 10, 0)
        local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.scName = name
        row.scStatus = status
        page.scRows[index] = row
    end

    function page:Refresh()
        local records, total = titleRecords()
        local maximumOffset = math.max(0, #records - TITLE_VISIBLE_ROWS)
        self.scOffset = math.max(0, math.min(self.scOffset, maximumOffset))
        local ownedCount = 0
        for titleIndex = 1, total do
            local owned = CS.ResolveOwned("TITLES", titleIndex, false)
            if owned then ownedCount = ownedCount + 1 end
        end
        if UI.CollectionsFrame then
            UI.CollectionsFrame.scCollectionCount:SetCount(ownedCount, total)
            UI.CollectionsFrame.scProgress:SetProgress(ownedCount, total)
        end
        local current = type(GetCurrentTitle) == "function" and tonumber(GetCurrentTitle()) or 0
        for index, row in ipairs(self.scRows) do
            local record = records[self.scOffset + index]
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

    page:SetScript("OnMouseWheel", function(self, delta)
        self.scOffset = math.max(0, self.scOffset - delta * 3)
        self:Refresh()
    end)
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

local function saveFramePosition(frame)
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
        if definition.key == key then
            selected = key
            break
        end
    end
    SC.db.mainTab = selected

    local frame = UI.CollectionsFrame
    if not frame then
        return
    end
    for tabKey, button in pairs(frame.scMainTabs) do
        button:SetSelected(tabKey == selected)
    end
    frame.scPageTitle:SetText(frame.scTabTitles[selected])
    if selected == "MOUNTS" then
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

    local frame = UI.CreateJournalFrame(UIParent, "SoloCollectionsJournal", JOURNAL_WIDTH, JOURNAL_HEIGHT)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        clampFrame(self)
        saveFramePosition(self)
    end)
    frame:SetScript("OnShow", function(self)
        clampFrame(self)
        UI.RefreshActivePage()
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -9)

    local progress = UI.CreateRetailProgressBar(frame, 286)
    progress:SetPoint("TOP", frame, "TOP", 0, -51)

    local pageTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pageTitle:SetPoint("TOP", frame, "TOP", 0, -17)
    pageTitle:SetTextColor(1, 0.82, 0.18)

    local portraitFrame = CreateFrame("Frame", nil, frame)
    portraitFrame:SetWidth(80)
    portraitFrame:SetHeight(80)
    portraitFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -7, 5)
    portraitFrame:SetFrameLevel(frame:GetFrameLevel() + 4)

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetWidth(62)
    portrait:SetHeight(62)
    portrait:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
    portrait:SetTexture(UI.Media.mountPortrait)
    portrait:SetTexCoord(0, 1, 0, 1)

    local portraitRing = portraitFrame:CreateTexture(nil, "OVERLAY")
    portraitRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    portraitRing:SetWidth(80)
    portraitRing:SetHeight(80)
    portraitRing:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
    -- MiniMap-TrackingBorder stores its complete ring in the top-left 40px
    -- of a 64px texture. Crop that region before stretching so the ring is
    -- centered and fully encloses the pre-masked 62px circular portrait.
    portraitRing:SetTexCoord(0, 0.625, 0, 0.625)

    local collectionCount = UI.CreateCollectionCount(frame)
    collectionCount:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -42)

    local searchFilterHost = CreateFrame("Frame", nil, frame)
    searchFilterHost:SetHeight(32)
    searchFilterHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 31, -84)
    searchFilterHost:SetWidth(338)

    local search = UI.CreateRetailSearchBox(searchFilterHost, 210, function(value)
        if SC.db then
            SC.db.query = value or ""
        end
        refreshPage()
    end)
    search:SetPoint("LEFT", searchFilterHost, "LEFT", 0, 0)

    local filterButton, filterPopup = UI.CreateFilterPopup(searchFilterHost, 116)
    filterButton:SetPoint("LEFT", search, "RIGHT", 7, 0)

    local wardrobeTabs = CreateFrame("Frame", nil, frame)
    wardrobeTabs:SetWidth(240)
    wardrobeTabs:SetHeight(32)
    wardrobeTabs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -31, -84)
    local itemTab = UI.CreateTopSubTab(wardrobeTabs, "物品", function()
        UI.SetWardrobeTab("ITEMS")
    end)
    itemTab:SetPoint("LEFT", wardrobeTabs, "LEFT", 0, 0)
    local setTab = UI.CreateTopSubTab(wardrobeTabs, "套装", function()
        UI.SetWardrobeTab("SETS")
    end)
    setTab:SetPoint("LEFT", itemTab, "RIGHT", 6, 0)
    wardrobeTabs:Hide()

    local contentHost = CreateFrame("Frame", nil, frame)
    contentHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 31, -122)
    contentHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -31, 24)

    frame.scMainTabs = {}
    frame.scTabTitles = {}
    local previousTab
    for _, definition in ipairs(TAB_DEFINITIONS) do
        local tabKey = definition.key
        local button = UI.CreateRetailBottomTab(frame, definition.label, function()
            UI.SetMainTab(tabKey)
        end)
        if previousTab then
            button:SetPoint("TOPLEFT", previousTab, "TOPRIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        end
        frame.scMainTabs[tabKey] = button
        frame.scTabTitles[tabKey] = definition.title
        previousTab = button
    end

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
    frame.scPages = {
        MOUNTS = UI.CreateMountsPage(contentHost),
        PETS = UI.CreatePetsPage(contentHost),
        TOYS = UI.CreateToysPage(contentHost),
        WARDROBE = UI.CreateWardrobePage(contentHost),
        TITLES = UI.CreateTitlesPage(contentHost),
    }

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
    if frame:IsShown() then
        frame:Hide()
    else
        restoreFramePosition(frame)
        frame:Show()
    end
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
