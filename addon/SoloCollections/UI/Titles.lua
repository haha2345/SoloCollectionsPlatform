local SC = SoloCollections
local UI = SC.UI
local CS = SC.CollectionState

local VISIBLE_ROWS = 16
local ROW_HEIGHT = 35

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

    for index = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12 - (index - 1) * ROW_HEIGHT)
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
        local maximumOffset = math.max(0, #records - VISIBLE_ROWS)
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
