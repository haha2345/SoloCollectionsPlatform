local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog

local VISIBLE_TILES = 18
local GRID_COLUMNS = 3
local GRID_PADDING_X = 16
local GRID_PADDING_TOP = 12
local GRID_COLUMN_GAP = 6
local TILE_HEIGHT = 72
local COLLECTED_NAME_COLOR = { 1.00, 0.82, 0.18 }
local UNCOLLECTED_NAME_COLOR = { 0.46, 0.43, 0.39 }
local MACRO_PREFIX = "SCT"

local TOY_ERROR_MESSAGES = {
    BRIDGE_UNAVAILABLE = "玩具服务尚未连接，请稍后再试。",
    INVALID_TOY_ID = "无效的玩具编号。",
    UNKNOWN_TOY = "服务端没有登记这个玩具。",
    NOT_COLLECTED = "尚未解锁这个玩具。",
    RATE_LIMITED = "操作过于频繁，请稍后再试。",
    DEAD = "死亡状态下不能使用玩具。",
    IN_VEHICLE = "载具状态下不能使用玩具。",
    CAST_FAILED = "玩具效果施放失败。",
    TIMEOUT = "玩具服务响应超时。",
}

local function showNotice(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

local function setFilter(key, value, page)
    if not SC.db or not SC.db.filters then
        return
    end
    SC.db.filters[key] = value
    page.scPage = 1
    page:Refresh()
    page:SyncFilters()
end

local function showToyTooltip(tile, record)
    if not record then
        return
    end
    local itemName, itemLink = GetItemInfo(record.itemId)
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        GameTooltip:SetText(itemName or record.name or "未知玩具", 1, 0.82, 0.18)
    end
    GameTooltip:AddLine("来源：" .. (record.source or "未知"), 0.94, 0.82, 0.58, true)
    GameTooltip:AddLine(record.description or "暂无说明。", 0.72, 0.68, 0.60, true)
    if record.collected then
        GameTooltip:AddLine("已解锁", 0.38, 0.90, 0.30)
        GameTooltip:AddLine("左键使用 · 拖动到动作栏", 1.00, 0.82, 0.18)
        GameTooltip:AddLine("右键查看更多操作", 0.78, 0.74, 0.64)
    else
        GameTooltip:AddLine("尚未解锁，无法使用", 0.58, 0.55, 0.50)
    end
    GameTooltip:Show()
end

local function useToy(record)
    if not record then
        return
    end
    if not record.collected then
        showNotice("尚未解锁这个玩具，无法使用。")
        return
    end
    if not SC.Bridge or type(SC.Bridge.UseToy) ~= "function" then
        showNotice(TOY_ERROR_MESSAGES.BRIDGE_UNAVAILABLE)
        return
    end
    SC.Bridge.UseToy(record.id, function(ok, reason)
        if ok == false then
            showNotice(TOY_ERROR_MESSAGES[reason] or "玩具使用请求失败。")
        end
    end)
end

local function getToyMacroBody(record)
    return "/sc toy " .. record.id
end

local function findToyMacro(body)
    if not GetNumMacros or not GetMacroInfo then
        return nil
    end
    local globalCount, characterCount = GetNumMacros()
    globalCount = tonumber(globalCount) or 0
    characterCount = tonumber(characterCount) or 0
    for index = 1, globalCount do
        local _, _, macroBody = GetMacroInfo(index)
        if macroBody == body then
            return index
        end
    end
    local characterStart = (tonumber(MAX_ACCOUNT_MACROS) or 36) + 1
    for offset = 0, characterCount - 1 do
        local index = characterStart + offset
        local _, _, macroBody = GetMacroInfo(index)
        if macroBody == body then
            return index
        end
    end
    return nil
end

local function createOrUpdateToyMacro(record)
    if not record or not record.collected then
        showNotice("尚未解锁这个玩具，不能拖到动作栏。")
        return nil
    end
    if InCombatLockdown and InCombatLockdown() then
        showNotice("战斗中不能创建或拖动玩具动作。")
        return nil
    end
    if not CreateMacro or not EditMacro or not PickupMacro then
        showNotice("当前客户端不支持玩具动作栏拖拽。")
        return nil
    end

    local body = getToyMacroBody(record)
    local icon = GetItemIcon(record.itemId) or record.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    local name = MACRO_PREFIX .. string.format("%03d", record.id)
    local macroIndex = findToyMacro(body)
    if macroIndex then
        pcall(function()
            EditMacro(macroIndex, name, icon, body)
        end)
    else
        local created, result = pcall(function()
            return CreateMacro(name, icon, body, 1)
        end)
        if created then
            macroIndex = tonumber(result)
        end
        if not macroIndex or macroIndex <= 0 then
            created, result = pcall(function()
                return CreateMacro(name, icon, body, nil)
            end)
            if created then
                macroIndex = tonumber(result)
            end
        end
    end

    if not macroIndex or macroIndex <= 0 then
        showNotice("宏栏已满，无法创建玩具动作。请先删除一个不用的宏。")
        return nil
    end
    PickupMacro(macroIndex)
    return macroIndex
end

function UI.CreateToysPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scCategory = "TOYS"
    page.scPage = 1
    page.scTotalPages = 1
    page.scTiles = {}
    page.scSelectedId = nil

    local grid = CreateFrame("Frame", nil, page)
    grid:SetPoint("TOPLEFT", page, "TOPLEFT", 5, -8)
    grid:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -5, 46)
    UI.ApplyNineSlice(grid, UI.Media.border, 18)

    local gridBackground = grid:CreateTexture(nil, "BACKGROUND")
    gridBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    gridBackground:SetPoint("TOPLEFT", grid, "TOPLEFT", 5, -5)
    gridBackground:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", -5, 5)
    gridBackground:SetVertexColor(0.025, 0.019, 0.013, 0.94)

    local empty = UI.CreateEmptyState(grid, "没有符合条件的玩具")
    empty:SetPoint("CENTER", grid, "CENTER", 0, 10)
    empty:Hide()

    local contextMenu = CreateFrame(
        "Frame",
        "SoloCollectionsToyContextMenu",
        page,
        "UIDropDownMenuTemplate"
    )

    local function selectRecord(record)
        page.scSelectedId = record and record.id or nil
        for _, tile in ipairs(page.scTiles) do
            tile:SetSelected(tile.scRecord and tile.scRecord.id == page.scSelectedId)
        end
    end

    local function openContextMenu(anchor, record)
        if not record then
            return
        end
        page.scContextRecord = record
        selectRecord(record)
        ToggleDropDownMenu(1, nil, contextMenu, anchor, 0, 0)
    end

    UIDropDownMenu_Initialize(contextMenu, function()
        local record = page.scContextRecord
        if not record then
            return
        end

        local useInfo = UIDropDownMenu_CreateInfo()
        useInfo.text = "使用玩具"
        useInfo.notCheckable = 1
        useInfo.func = function()
            useToy(record)
        end
        if not record.collected then
            useInfo.disabled = 1
            useInfo.tooltipTitle = "尚未解锁"
            useInfo.tooltipText = "未解锁的玩具不能使用。"
        end
        UIDropDownMenu_AddButton(useInfo)

        local favoriteInfo = UIDropDownMenu_CreateInfo()
        favoriteInfo.text = record.favorite and "取消偏好" or "设为偏好"
        favoriteInfo.notCheckable = 1
        favoriteInfo.func = function()
            Catalog.ToggleDemoFavorite("TOYS", record.id)
            page:Refresh()
        end
        UIDropDownMenu_AddButton(favoriteInfo)
    end, "MENU")

    for index = 1, VISIBLE_TILES do
        local tile = UI.CreateIconTile(grid, 1, TILE_HEIGHT, selectRecord)
        tile.scIcon:ClearAllPoints()
        tile.scIcon:SetWidth(52)
        tile.scIcon:SetHeight(52)
        tile.scIcon:SetPoint("LEFT", tile, "LEFT", 9, 0)
        tile.scName:ClearAllPoints()
        tile.scName:SetPoint("LEFT", tile.scIcon, "RIGHT", 11, 0)
        tile.scName:SetPoint("RIGHT", tile, "RIGHT", -10, 0)
        tile.scName:SetHeight(48)
        tile.scName:SetJustifyH("LEFT")
        tile.scName:SetJustifyV("MIDDLE")

        tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        tile:RegisterForDrag("LeftButton")
        tile:SetScript("OnClick", function(self, button)
            local record = self.scRecord
            if not record then
                return
            end
            if button == "RightButton" then
                openContextMenu(self, record)
            else
                selectRecord(record)
                useToy(record)
            end
        end)
        tile:SetScript("OnDragStart", function(self)
            local record = self.scRecord
            if not record or not record.collected then
                if record then
                    showNotice("尚未解锁这个玩具，不能拖到动作栏。")
                end
                return
            end
            createOrUpdateToyMacro(record)
        end)
        tile:HookScript("OnEnter", function(self)
            showToyTooltip(self, self.scRecord)
        end)
        tile:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        page.scTiles[index] = tile
    end

    local function layoutTiles()
        local gridWidth = math.floor((grid:GetWidth() or 0) + 0.5)
        if gridWidth <= (2 * GRID_PADDING_X) then
            return
        end
        local tileWidth = math.floor(
            (gridWidth - (2 * GRID_PADDING_X) - ((GRID_COLUMNS - 1) * GRID_COLUMN_GAP))
                / GRID_COLUMNS
        )
        local blockWidth = (GRID_COLUMNS * tileWidth) + ((GRID_COLUMNS - 1) * GRID_COLUMN_GAP)
        local leftMargin = math.floor((gridWidth - blockWidth) / 2)
        for index, tile in ipairs(page.scTiles) do
            local column = (index - 1) % GRID_COLUMNS
            local row = math.floor((index - 1) / GRID_COLUMNS)
            tile:ClearAllPoints()
            tile:SetWidth(tileWidth)
            tile:SetPoint(
                "TOPLEFT",
                grid,
                "TOPLEFT",
                leftMargin + (column * (tileWidth + GRID_COLUMN_GAP)),
                -(GRID_PADDING_TOP + (row * TILE_HEIGHT))
            )
        end
        page.scTileWidth = tileWidth
        page.scGridLeftMargin = leftMargin
        page.scGridRightMargin = gridWidth - leftMargin - blockWidth
    end

    grid:SetScript("OnSizeChanged", layoutTiles)
    layoutTiles()

    local controls = UI.CreatePageControls(page, function()
        page.scPage = math.max(1, page.scPage - 1)
        page:Refresh()
    end, function()
        page.scPage = math.min(page.scTotalPages or 1, page.scPage + 1)
        page:Refresh()
    end)
    controls:SetPoint("BOTTOM", page, "BOTTOM", 0, 7)

    local interactionHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    interactionHint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, 14)
    interactionHint:SetText("左键使用 · 拖动到动作栏 · 右键更多操作")
    interactionHint:SetTextColor(0.62, 0.56, 0.46)

    function page:ClearSelection()
        self.scSelectedId = nil
        self.scContextRecord = nil
        for _, tile in ipairs(self.scTiles) do
            tile:SetSelected(false)
        end
        GameTooltip:Hide()
        CloseDropDownMenus()
    end

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scFilterPopup or not SC.db or SC.db.mainTab ~= "TOYS" then
            return
        end
        local filters = SC.db.filters
        frame.scFilterPopup:SetOptions({
            { label = "已解锁", checked = filters.collected, onClick = function()
                setFilter("collected", not filters.collected, self)
            end },
            { label = "未解锁", checked = filters.uncollected, onClick = function()
                setFilter("uncollected", not filters.uncollected, self)
            end },
            { label = "仅显示偏好", checked = filters.favorites, onClick = function()
                setFilter("favorites", not filters.favorites, self)
            end },
        })
    end

    function page:Refresh()
        if not SC.db then
            return
        end
        local records, currentPage, totalPages = Catalog.Query("TOYS", SC.db.query, SC.db.filters, self.scPage, VISIBLE_TILES)
        self.scPage = currentPage
        self.scTotalPages = totalPages
        controls:SetPage(currentPage, totalPages)

        local selectionStillVisible = false
        for index, tile in ipairs(self.scTiles) do
            local record = records[index]
            tile:SetRecord(record)
            if record then
                local cachedIcon = GetItemIcon(record.itemId)
                if cachedIcon then
                    UI.SetIconTexture(tile.scIcon, cachedIcon)
                    UI.SetCollectedVisual(tile.scIcon, record.collected, 0.52)
                end
                if record.collected then
                    tile.scName:SetTextColor(unpack(COLLECTED_NAME_COLOR))
                else
                    tile.scName:SetTextColor(unpack(UNCOLLECTED_NAME_COLOR))
                end
                if record.id == self.scSelectedId then
                    selectionStillVisible = true
                end
            end
            tile:SetSelected(record and record.id == self.scSelectedId)
        end

        local collected, total = Catalog.GetProgress("TOYS", SC.db.filters)
        if UI.CollectionsFrame and UI.CollectionsFrame.scProgress then
            UI.CollectionsFrame.scProgress:SetProgress(collected, total)
        end

        if #records == 0 then
            self:ClearSelection()
            UI.ShowEmptyState(empty, self, "没有符合条件的玩具", "调整搜索文字或过滤条件后再试。")
        else
            UI.HideEmptyState(empty)
            if not selectionStillVisible then
                selectRecord(records[1])
            end
        end
        self:SyncFilters()
    end

    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:SetScript("OnEvent", function(self)
        if self:IsShown() then
            self:Refresh()
        end
    end)
    page:SetScript("OnHide", function(self)
        self:ClearSelection()
        self.scPage = 1
    end)

    page.scGrid = grid
    page.scLayoutTiles = layoutTiles
    page.scGridBackground = gridBackground
    page.scControls = controls
    page.scInteractionHint = interactionHint
    page.scContextMenu = contextMenu
    page.scEmpty = empty
    return page
end
