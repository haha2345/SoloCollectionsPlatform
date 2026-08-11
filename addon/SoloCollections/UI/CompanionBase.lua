local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog

local VISIBLE_ROWS = 8
local DEFAULT_ROTATION = 0.32

-- Shared Task 8 layout skin. Data and actions stay owned by each SoloCollections
-- page; this only standardizes the NewEra list/detail/action composition.
function UI.StyleNewEraCompanionLayout(page, list, detail, listBackground, detailBackground)
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if not public then return false end
    local inset = public.Theme:GetToken("insetBackground")
    if listBackground and inset then listBackground:SetVertexColor(inset[1], inset[2], inset[3], inset[4]) end
    if detailBackground then
        detailBackground:SetTexture(public.Theme:GetTexture("rock"))
        detailBackground:SetTexCoord(0, 1, 0, 1)
        detailBackground:SetVertexColor(0.34, 0.25, 0.16, 0.96)
    end
    page.scNewEraLayout = { list = list, detail = detail, actions = {} }
    return true
end

function UI.RegisterNewEraCompanionAction(page, button)
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if public and button then public.Components:SkinButton(button) end
    if page.scNewEraLayout and button then
        page.scNewEraLayout.actions[#page.scNewEraLayout.actions + 1] = button
    end
end

local function setFilter(category, key, value, page)
    if not SC.db or not SC.db.filters then
        return
    end
    SC.db.filters[key] = value
    page.scPage = 1
    page:Refresh()
    page:SyncFilters()
end

local function createDetailLabel(parent, font, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetTextColor(color[1], color[2], color[3])
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

function UI.CreateCompanionPageBase(category, parent, emptyMessage)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scCategory = category
    page.scPage = 1
    page.scRows = {}
    page.scSelectedId = nil

    local list = CreateFrame("Frame", nil, page)
    list:SetWidth(315)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 42)

    local detail = CreateFrame("Frame", nil, page)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 18, 0)
    detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 4)
    UI.ApplyNineSlice(detail, UI.Media.border, 18)

    local detailBackground = detail:CreateTexture(nil, "BACKGROUND")
    detailBackground:SetTexture(UI.Media.background)
    detailBackground:SetPoint("TOPLEFT", detail, "TOPLEFT", 5, -5)
    detailBackground:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -5, 5)
    detailBackground:SetVertexColor(0.58, 0.43, 0.25, 0.82)

    -- SetCreature is reliable on the 3.3.5 PlayerModel widget. DressUpModel is
    -- reserved for the wardrobe player preview and can stay blank for creatures.
    local model = CreateFrame("PlayerModel", nil, detail)
    model:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -10)
    model:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -10, 145)
    model:EnableMouse(true)
    model.rotation = DEFAULT_ROTATION
    if model.SetCamera then
        model:SetCamera(0)
    end
    if model.SetModelScale then
        model:SetModelScale(1)
    end
    if model.SetPosition then
        model:SetPosition(0, 0, 0)
    end
    model:SetRotation(DEFAULT_ROTATION)
    local presenter = SC.ModelProvider and SC.ModelProvider.Create("CREATURE", model, {
        controls = true, panelCheck = function() return page:IsShown() end,
    }) or nil

    local unavailable = model:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    unavailable:SetPoint("CENTER", model, "CENTER", 0, 0)
    unavailable:SetText("无法预览")
    unavailable:SetTextColor(0.72, 0.68, 0.58)
    unavailable:Hide()

    local function clearDragState()
        model.scDragging = nil
        model.scLastCursorX = nil
    end

    local function clearModelInteraction()
        clearDragState()
        model.scModelCheckElapsed = nil
    end

    local rotateHint = model:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rotateHint:SetPoint("BOTTOM", model, "BOTTOM", 0, 7)
    rotateHint:SetText("按住鼠标左键拖动旋转")

    local name = createDetailLabel(detail, "GameFontNormalLarge", { 1, 0.82, 0.18 })
    name:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 12, -10)
    name:SetPoint("RIGHT", detail, "RIGHT", -150, 0)

    local collectionState = createDetailLabel(detail, "GameFontHighlight", { 0.45, 0.9, 0.35 })
    collectionState:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -20, -374)

    local source = createDetailLabel(detail, "GameFontHighlightSmall", { 0.94, 0.82, 0.58 })
    source:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -9)
    source:SetPoint("RIGHT", detail, "RIGHT", -18, 0)

    local description = createDetailLabel(detail, "GameFontDisableSmall", { 0.65, 0.60, 0.51 })
    description:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -8)
    description:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -18, 48)

    local favorite = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    favorite:SetWidth(104)
    favorite:SetHeight(25)
    favorite:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -18, 16)
    favorite:SetText("设为偏好")

    local reset = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    reset:SetWidth(104)
    reset:SetHeight(25)
    reset:SetPoint("RIGHT", favorite, "LEFT", -8, 0)
    reset:SetText("重置视角")

    local empty = UI.CreateEmptyState(list, emptyMessage or "没有符合条件的收藏")
    empty:SetPoint("CENTER", list, "CENTER", 0, 15)
    empty:Hide()

    local function selectRecord(record)
        if not record then
            page:ClearSelection()
            return
        end
        page.scSelectedId = record.id
        page.scSelectedRecord = record
        name:SetText(record.name or "未知收藏")
        source:SetText("来源：" .. (record.source or "未知"))
        description:SetText(record.description or "暂无说明。")
        if record.collected then
            collectionState:SetText("已收集")
            collectionState:SetTextColor(0.38, 0.9, 0.30)
        else
            collectionState:SetText("未收集")
            collectionState:SetTextColor(0.60, 0.57, 0.52)
        end
        favorite:SetText(record.favorite and "取消偏好" or "设为偏好")
        for _, row in ipairs(page.scRows) do
            row:SetSelected(row.scRecord and row.scRecord.id == record.id)
        end
        clearModelInteraction()
        if presenter then
            presenter:Present({ creatureEntry = record.previewCreatureEntry, rotation = DEFAULT_ROTATION,
                onReady = function() unavailable:Hide() end,
                onUnavailable = function() unavailable:Show() end })
        else unavailable:Show() end
    end

    for index = 1, VISIBLE_ROWS do
        local row = UI.CreateListRow(list, 315, 52, function(_, record)
            selectRecord(record)
        end)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((index - 1) * 54))
        page.scRows[index] = row
    end

    local controls = UI.CreatePageControls(page, function()
        page.scPage = math.max(1, page.scPage - 1)
        page:Refresh()
    end, function()
        page.scPage = math.min(page.scTotalPages or 1, page.scPage + 1)
        page:Refresh()
    end)
    controls:SetPoint("BOTTOM", list, "BOTTOM", 0, -36)

    function page:ClearSelection()
        self.scSelectedId = nil
        self.scSelectedRecord = nil
        name:SetText("")
        source:SetText("")
        description:SetText("")
        collectionState:SetText("")
        favorite:SetText("设为偏好")
        unavailable:Hide()
        clearModelInteraction()
        if presenter then presenter:Clear("NO_SELECTION") else model:ClearModel() end
        for _, row in ipairs(self.scRows) do
            row:SetSelected(false)
        end
    end

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scFilterPopup or SC.db.mainTab ~= self.scCategory then
            return
        end
        local filters = SC.db.filters
        frame.scFilterPopup:SetOptions({
            { label = "已收集", checked = filters.collected, onClick = function()
                setFilter(category, "collected", not filters.collected, self)
            end },
            { label = "未收集", checked = filters.uncollected, onClick = function()
                setFilter(category, "uncollected", not filters.uncollected, self)
            end },
            { label = "仅显示偏好", checked = filters.favorites, onClick = function()
                setFilter(category, "favorites", not filters.favorites, self)
            end },
        })
    end

    function page:Refresh()
        if not SC.db then
            return
        end
        local records, currentPage, totalPages = Catalog.Query(
            category,
            SC.db.query,
            SC.db.filters,
            self.scPage,
            VISIBLE_ROWS
        )
        self.scPage = currentPage
        self.scTotalPages = totalPages
        controls:SetPage(currentPage, totalPages)

        local selectedRecord
        for index, row in ipairs(self.scRows) do
            local record = records[index]
            row:SetRecord(record)
            row:SetSelected(record and record.id == self.scSelectedId)
            if record and record.id == self.scSelectedId then
                selectedRecord = record
            end
        end

        local collected, total = Catalog.GetProgress(category, SC.db.filters)
        if UI.CollectionsFrame and UI.CollectionsFrame.scProgress then
            UI.CollectionsFrame.scProgress:SetProgress(collected, total)
        end

        if #records == 0 then
            UI.ShowEmptyState(empty, self, emptyMessage, "调整搜索文字或过滤条件后再试。")
        else
            UI.HideEmptyState(empty)
            selectRecord(selectedRecord or records[1])
        end
        self:SyncFilters()
    end

    favorite:SetScript("OnClick", function()
        local record = page.scSelectedRecord
        if not record then
            return
        end
        Catalog.ToggleDemoFavorite(category, record.id)
        page:Refresh()
    end)

    reset:SetScript("OnClick", function()
        if presenter and presenter.ResetView then presenter:ResetView()
        else model.rotation = DEFAULT_ROTATION; model:SetRotation(DEFAULT_ROTATION) end
    end)

    if not SC.ModelProvider or SC.ModelProvider.GetMode("CREATURE") == "legacy" then
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.scDragging = true
            self.scLastCursorX = GetCursorPosition()
        end
    end)
    model:SetScript("OnMouseUp", function(self)
        clearDragState()
    end)
    model:SetScript("OnUpdate", function(self, elapsed)
        if self.scModelCheckElapsed then
            self.scModelCheckElapsed = self.scModelCheckElapsed + elapsed
            if self.scModelCheckElapsed >= 0.5 then
                self.scModelCheckElapsed = nil
                local checked, modelPath = pcall(function()
                    return self:GetModel()
                end)
                if checked and modelPath and modelPath ~= "" then
                    unavailable:Hide()
                else
                    unavailable:Show()
                end
            end
        end
        if self.scDragging then
            if not IsMouseButtonDown("LeftButton") then
                clearDragState()
            else
                local cursorX = GetCursorPosition()
                local previousX = self.scLastCursorX or cursorX
                self.scLastCursorX = cursorX
                self.rotation = (self.rotation or DEFAULT_ROTATION) + ((cursorX - previousX) * 0.012)
                self:SetRotation(self.rotation)
            end
        end
    end)
    end

    page:SetScript("OnHide", function(self)
        clearModelInteraction()
        self:ClearSelection()
        self.scPage = 1
    end)

    page.scList = list
    page.scDetail = detail
    page.scModel = model
    page.scPresenter = presenter
    page.scUnavailable = unavailable
    page.scName = name
    page.scSource = source
    page.scDescription = description
    page.scCollectionState = collectionState
    page.scFavorite = favorite
    page.scControls = controls
    page.scEmpty = empty
    return page
end
