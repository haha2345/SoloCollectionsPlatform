local SC = SoloCollections
local UI = SC.UI
local CS = SC.CollectionState

local TITLE_VISIBLE_ROWS = 10
local TITLE_ROW_HEIGHT = 46

local function titleRecords()
    local records = {}
    local count = type(GetNumTitles) == "function" and tonumber(GetNumTitles()) or 0
    local query = SC.db and string.lower(SC.db.query or "") or ""
    local filters = SC.db and SC.db.filters or {}
    for titleIndex = 1, count do
        local ok, name = pcall(GetTitleName, titleIndex)
        if ok and type(name) == "string" and name ~= "" then
            name = string.gsub(name, "%%s", UnitName("player") or "")
            local nativeKnown = type(IsTitleKnown) == "function" and IsTitleKnown(titleIndex) == 1
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
