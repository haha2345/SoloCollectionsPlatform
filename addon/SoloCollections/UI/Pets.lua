local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog

local VISIBLE_ROWS = 12
local ROW_HEIGHT = 50
local DEFAULT_ROTATION = 0.32
local DEFAULT_MODEL_SCALE = 1
local MIN_MODEL_SCALE = 0.35
local MAX_MODEL_SCALE = 2.5
local MODEL_RETRY_DELAYS = { 0.1, 0.25, 0.5 }

local function createDetailLabel(parent, font, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetTextColor(color[1], color[2], color[3])
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function showNotice(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

function UI.CreatePetsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scCategory = "PETS"
    page.scRows = {}
    page.scRecords = {}
    page.scSelectedId = nil
    page.scModelGeneration = 0
    page.scModelTasks = {}
    page.scModelReady = false

    local modelTimerDriver = CreateFrame("Frame", nil, page)

    local list = CreateFrame("Frame", nil, page)
    list:SetWidth(342)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 4)
    UI.ApplyNineSlice(list, UI.Media.border, 14)

    local listBackground = list:CreateTexture(nil, "BACKGROUND")
    listBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    listBackground:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -5)
    listBackground:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -5, 5)
    listBackground:SetVertexColor(0.018, 0.014, 0.01, 0.97)

    local detail = CreateFrame("Frame", nil, page)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 17, 0)
    detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 4)
    UI.ApplyNineSlice(detail, UI.Media.border, 18)

    local detailBackground = detail:CreateTexture(nil, "BACKGROUND")
    detailBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    detailBackground:SetPoint("TOPLEFT", detail, "TOPLEFT", 5, -5)
    detailBackground:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -5, 5)
    detailBackground:SetVertexColor(0.19, 0.055, 0.032, 0.96)

    local model = CreateFrame("PlayerModel", nil, detail)
    model:SetPoint("TOPLEFT", detail, "TOPLEFT", 9, -112)
    model:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -9, 47)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.rotation = DEFAULT_ROTATION
    model.scZoom = DEFAULT_MODEL_SCALE
    model.scBaseScale = nil

    local modelShade = model:CreateTexture(nil, "BACKGROUND")
    modelShade:SetTexture("Interface\\Buttons\\WHITE8X8")
    modelShade:SetAllPoints(model)
    modelShade:SetVertexColor(0.11, 0.025, 0.018, 0.56)

    local unavailable = model:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    unavailable:SetPoint("CENTER", model, "CENTER", 0, 0)
    unavailable:SetText("无法预览")
    unavailable:SetTextColor(0.82, 0.68, 0.56)
    unavailable:Hide()

    local rotateHint = model:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rotateHint:SetPoint("BOTTOM", model, "BOTTOM", 0, 7)
    rotateHint:SetText("按住鼠标左键拖动旋转 · 滚轮缩放")

    local infoButton = CreateFrame("Button", nil, detail)
    infoButton:SetWidth(38)
    infoButton:SetHeight(38)
    infoButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 20, -18)
    infoButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local infoIcon = infoButton:CreateTexture(nil, "ARTWORK")
    infoIcon:SetAllPoints(infoButton)
    UI.SetFallbackTexture(infoIcon)

    local infoBorder = infoButton:CreateTexture(nil, "OVERLAY")
    infoBorder:SetTexture(UI.Media.uncollectedFrame)
    infoBorder:SetPoint("TOPLEFT", infoButton, "TOPLEFT", -3, 3)
    infoBorder:SetPoint("BOTTOMRIGHT", infoButton, "BOTTOMRIGHT", 3, -3)

    local name = createDetailLabel(detail, "GameFontNormalLarge", { 1, 0.82, 0.18 })
    name:SetPoint("TOPLEFT", infoButton, "TOPRIGHT", 12, -1)
    name:SetPoint("RIGHT", detail, "RIGHT", -20, 0)

    local collectionState = createDetailLabel(detail, "GameFontHighlight", { 0.45, 0.9, 0.35 })
    collectionState:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -7)

    local source = createDetailLabel(detail, "GameFontHighlightSmall", { 0.94, 0.82, 0.58 })
    source:SetPoint("TOPLEFT", infoButton, "BOTTOMLEFT", 0, -11)
    source:SetPoint("RIGHT", detail, "RIGHT", -20, 0)

    local description = createDetailLabel(detail, "GameFontDisableSmall", { 0.74, 0.68, 0.59 })
    description:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -7)
    description:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
    description:SetHeight(38)

    local favorite = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    favorite:SetWidth(104)
    favorite:SetHeight(25)
    favorite:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -18, 15)
    favorite:SetText("设为偏好")

    local reset = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    reset:SetWidth(104)
    reset:SetHeight(25)
    reset:SetPoint("RIGHT", favorite, "LEFT", -8, 0)
    reset:SetText("重置视角")

    local summon = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    summon:SetWidth(104)
    summon:SetHeight(25)
    summon:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    summon:SetText("召唤小宠物")

    local empty = UI.CreateEmptyState(list, "没有符合条件的小宠物")
    empty:SetPoint("CENTER", list, "CENTER", -10, 15)
    empty:Hide()

    local scrollHint = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scrollHint:SetPoint("BOTTOM", list, "BOTTOM", 0, 13)
    scrollHint:SetText("滚轮或拖动滚动条查看更多小宠物")
    scrollHint:SetTextColor(0.62, 0.56, 0.46)

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "SoloCollectionsPetScrollFrame",
        list,
        "FauxScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", list, "TOPLEFT", 9, -9)
    scrollFrame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -30, 31)
    scrollFrame:EnableMouseWheel(true)

    local contextMenu = CreateFrame(
        "Frame",
        "SoloCollectionsPetContextMenu",
        page,
        "UIDropDownMenuTemplate"
    )

    local function clearDragState()
        model.scDragging = nil
        model.scLastCursorX = nil
    end

    local function getModelPath()
        local checked, modelPath = pcall(function()
            return model:GetModel()
        end)
        if checked and modelPath and modelPath ~= "" then
            return modelPath
        end
        return nil
    end

    local function getNativeModelScale()
        if not model.GetModelScale then
            return nil
        end
        local checked, scale = pcall(function()
            return model:GetModelScale()
        end)
        scale = checked and tonumber(scale) or nil
        if scale and scale > 0 then
            return scale
        end
        return nil
    end

    local function stopModelTimers()
        page.scModelTasks = {}
        modelTimerDriver:SetScript("OnUpdate", nil)
    end

    local function clearModelInteraction()
        clearDragState()
        stopModelTimers()
    end

    local function onModelTimerUpdate(self, elapsed)
        local readyCallbacks = {}
        for index = #page.scModelTasks, 1, -1 do
            local task = page.scModelTasks[index]
            if page.scModelGeneration ~= task.generation then
                table.remove(page.scModelTasks, index)
            else
                task.remaining = task.remaining - elapsed
                if task.remaining <= 0 then
                    table.remove(page.scModelTasks, index)
                    table.insert(readyCallbacks, 1, task.callback)
                end
            end
        end
        if #page.scModelTasks == 0 then
            self:SetScript("OnUpdate", nil)
        end
        for _, callback in ipairs(readyCallbacks) do
            callback()
        end
    end

    local function scheduleModel(delay, generation, callback)
        table.insert(page.scModelTasks, {
            remaining = tonumber(delay) or 0,
            generation = generation,
            callback = callback,
        })
        modelTimerDriver:SetScript("OnUpdate", onModelTimerUpdate)
    end

    local function resetModelState()
        model.rotation = DEFAULT_ROTATION
        model.scZoom = DEFAULT_MODEL_SCALE
        model.scBaseScale = nil
        page.scModelReady = false
        clearDragState()
    end

    local function summonRecord(record)
        if not record then
            return
        end
        if not record.collected then
            showNotice("尚未收集该小宠物，无法召唤。")
            return
        end
        if not SC.Bridge or type(SC.Bridge.SummonPet) ~= "function" then
            showNotice("小宠物召唤桥接不可用。")
            return
        end
        SC.Bridge.SummonPet(record.id, function(ok, reason)
            if ok == false then
                showNotice(reason or "小宠物召唤请求失败。")
            end
        end)
    end

    local function openContextMenu(anchor, record)
        if not record then
            return
        end
        page.scContextRecord = record
        ToggleDropDownMenu(1, nil, contextMenu, anchor, 0, 0)
    end

    UIDropDownMenu_Initialize(contextMenu, function()
        local record = page.scContextRecord
        if not record then
            return
        end

        local summonInfo = UIDropDownMenu_CreateInfo()
        summonInfo.text = "召唤小宠物"
        summonInfo.notCheckable = 1
        summonInfo.func = function()
            summonRecord(record)
        end
        if not record.collected then
            summonInfo.disabled = 1
            summonInfo.tooltipTitle = "无法召唤"
            summonInfo.tooltipText = "尚未收集该小宠物。"
        elseif not SC.Bridge or type(SC.Bridge.SummonPet) ~= "function" then
            summonInfo.disabled = 1
            summonInfo.tooltipTitle = "召唤桥接不可用"
            summonInfo.tooltipText = "客户端与服务端的小宠物桥接尚未连接。"
        end
        UIDropDownMenu_AddButton(summonInfo)

        local favoriteInfo = UIDropDownMenu_CreateInfo()
        favoriteInfo.text = record.favorite and "取消偏好" or "设为偏好"
        favoriteInfo.notCheckable = 1
        favoriteInfo.func = function()
            Catalog.ToggleDemoFavorite("PETS", record.id)
            page:Refresh()
        end
        if not record.collected then
            favoriteInfo.disabled = 1
            favoriteInfo.tooltipTitle = "尚未收集"
            favoriteInfo.tooltipText = "未收集的小宠物不能设为偏好。"
        end
        UIDropDownMenu_AddButton(favoriteInfo)
    end, "MENU")

    local function applyModel(record, generation)
        if page.scModelGeneration ~= generation then
            return
        end
        clearModelInteraction()
        model:ClearModel()
        unavailable:Hide()
        resetModelState()

        local retryIndex = 0
        local setCreatureAndVerify

        local function failModel()
            stopModelTimers()
            resetModelState()
            model:ClearModel()
            unavailable:Show()
        end

        setCreatureAndVerify = function()
            if page.scModelGeneration ~= generation then
                return
            end
            local loaded = record.creatureId and pcall(function()
                model:ClearModel()
                model:SetCreature(record.creatureId)
            end)
            if not loaded then
                failModel()
                return
            end

            scheduleModel(0.35, generation, function()
                if page.scModelGeneration ~= generation then
                    return
                end
                if getModelPath() then
                    model.scBaseScale = getNativeModelScale()
                    model.scZoom = DEFAULT_MODEL_SCALE
                    model.rotation = DEFAULT_ROTATION
                    model:SetRotation(DEFAULT_ROTATION)
                    page.scModelReady = true
                    unavailable:Hide()
                    return
                end
                retryIndex = retryIndex + 1
                if retryIndex <= #MODEL_RETRY_DELAYS then
                    scheduleModel(MODEL_RETRY_DELAYS[retryIndex], generation, setCreatureAndVerify)
                else
                    failModel()
                end
            end)
        end

        setCreatureAndVerify()
    end

    local function requestModel(record)
        page.scModelGeneration = (page.scModelGeneration or 0) + 1
        local generation = page.scModelGeneration
        clearModelInteraction()
        resetModelState()
        model:ClearModel()
        unavailable:Hide()

        if SC.Bridge and type(SC.Bridge.RequestPetModel) == "function" then
            SC.Bridge.RequestPetModel(record.id, function()
                if page.scModelGeneration == generation then
                    scheduleModel(0, generation, function()
                        applyModel(record, generation)
                    end)
                end
            end)
        else
            scheduleModel(0, generation, function()
                applyModel(record, generation)
            end)
        end
    end

    local function selectRecord(record)
        if not record then
            page:ClearSelection()
            return
        end
        page.scSelectedId = record.id
        page.scSelectedRecord = record
        UI.SetIconTexture(infoIcon, record.icon)
        UI.SetCollectedVisual(infoIcon, record.collected)
        infoBorder:SetTexture(record.collected and UI.Media.collectedFrame or UI.Media.uncollectedFrame)
        name:SetText(record.name or "未知小宠物")
        source:SetText("来源：" .. (record.source or "未知"))
        description:SetText(record.description or "暂无说明。")
        if record.collected then
            collectionState:SetText("已收集")
            collectionState:SetTextColor(0.38, 0.9, 0.30)
            favorite:Enable()
            summon:Enable()
            favorite:SetText(record.favorite and "取消偏好" or "设为偏好")
        else
            collectionState:SetText("未收集")
            collectionState:SetTextColor(0.72, 0.59, 0.52)
            favorite:Disable()
            summon:Disable()
            favorite:SetText("尚未收集")
        end
        for _, row in ipairs(page.scRows) do
            row:SetSelected(row.scRecord and row.scRecord.id == record.id)
        end
        requestModel(record)
    end

    local function refreshRows()
        local records = page.scRecords or {}
        FauxScrollFrame_Update(scrollFrame, #records, VISIBLE_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        for index, row in ipairs(page.scRows) do
            local record = records[offset + index]
            row:SetRecord(record)
            row:SetSelected(record and record.id == page.scSelectedId)
        end
        if #records > VISIBLE_ROWS then
            local first = math.min(#records, offset + 1)
            local last = math.min(#records, offset + VISIBLE_ROWS)
            scrollHint:SetText("滚轮或拖动滚动条查看更多小宠物  " .. first .. "-" .. last .. " / " .. #records)
        else
            scrollHint:SetText("共 " .. #records .. " 个小宠物")
        end
    end

    local function scrollByWheel(self, delta)
        local currentOffset = FauxScrollFrame_GetOffset(self) or 0
        local maxOffset = math.max(0, #(page.scRecords or {}) - VISIBLE_ROWS)
        local newOffset = math.max(0, math.min(maxOffset, currentOffset - delta))
        FauxScrollFrame_OnVerticalScroll(self, newOffset * ROW_HEIGHT, ROW_HEIGHT, refreshRows)
    end

    for index = 1, VISIBLE_ROWS do
        local row = UI.CreateMountListRow(list, 302, 48, function(_, record)
            selectRecord(record)
        end, function(anchor, record)
            openContextMenu(anchor, record)
        end)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 9, -(9 + ((index - 1) * ROW_HEIGHT)))
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            scrollByWheel(scrollFrame, delta)
        end)
        page.scRows[index] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refreshRows)
    end)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollByWheel(self, delta)
    end)

    function page:ClearSelection()
        self.scSelectedId = nil
        self.scSelectedRecord = nil
        self.scModelGeneration = (self.scModelGeneration or 0) + 1
        name:SetText("")
        source:SetText("")
        description:SetText("")
        collectionState:SetText("")
        favorite:SetText("设为偏好")
        favorite:Disable()
        summon:Disable()
        UI.SetFallbackTexture(infoIcon)
        unavailable:Hide()
        clearModelInteraction()
        resetModelState()
        model:ClearModel()
        for _, row in ipairs(self.scRows) do
            row:SetSelected(false)
        end
    end

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scFilterPopup or not SC.db or SC.db.mainTab ~= "PETS" then
            return
        end
        local filters = SC.db.filters
        local function toggleFilter(key)
            filters[key] = not filters[key]
            self:Refresh()
            self:SyncFilters()
        end
        frame.scFilterPopup:SetOptions({
            { label = "已收集", checked = filters.collected, onClick = function()
                toggleFilter("collected")
            end },
            { label = "未收集", checked = filters.uncollected, onClick = function()
                toggleFilter("uncollected")
            end },
            { label = "仅显示偏好", checked = filters.favorites, onClick = function()
                toggleFilter("favorites")
            end },
        })
    end

    function page:Refresh()
        if not SC.db then
            return
        end
        local records = Catalog.QueryAll("PETS", SC.db.query, SC.db.filters)
        self.scRecords = records
        FauxScrollFrame_Update(scrollFrame, #records, VISIBLE_ROWS, ROW_HEIGHT)

        local selectedRecord
        for _, record in ipairs(records) do
            if record.id == self.scSelectedId then
                selectedRecord = record
                break
            end
        end

        local collected, total = Catalog.GetProgress("PETS", SC.db.filters)
        if UI.CollectionsFrame and UI.CollectionsFrame.scProgress then
            UI.CollectionsFrame.scProgress:SetProgress(collected, total)
        end
        if UI.CollectionsFrame then
            local count = UI.CollectionsFrame.scCollectionCount or UI.CollectionsFrame.scMountCount
            if count then
                local allCollected, allTotal = Catalog.GetProgress("PETS")
                count:SetCount(allCollected, allTotal)
            end
        end

        if #records == 0 then
            self:ClearSelection()
            refreshRows()
            UI.ShowEmptyState(empty, self, "没有符合条件的小宠物", "调整搜索文字或过滤条件后再试。")
        else
            UI.HideEmptyState(empty)
            selectRecord(selectedRecord or records[1])
            refreshRows()
        end
        self:SyncFilters()
    end

    favorite:SetScript("OnClick", function()
        local record = page.scSelectedRecord
        if not record or not record.collected then
            return
        end
        Catalog.ToggleDemoFavorite("PETS", record.id)
        page:Refresh()
    end)

    summon:SetScript("OnClick", function()
        summonRecord(page.scSelectedRecord)
    end)

    reset:SetScript("OnClick", function()
        local record = page.scSelectedRecord
        if record then
            requestModel(record)
        end
    end)

    infoButton:SetScript("OnClick", function(self, button)
        local record = page.scSelectedRecord
        if button == "RightButton" then
            openContextMenu(self, record)
        else
            summonRecord(record)
        end
    end)

    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.scDragging = true
            local cursorX = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            self.scLastCursorX = cursorX / scale
        end
    end)

    model:SetScript("OnMouseUp", function()
        clearDragState()
    end)

    model:SetScript("OnUpdate", function(self)
        if not self.scDragging then
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            clearDragState()
            return
        end
        local cursorX = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cursorX = cursorX / scale
        local previousX = self.scLastCursorX or cursorX
        self.scLastCursorX = cursorX
        self.rotation = (self.rotation or DEFAULT_ROTATION) + ((cursorX - previousX) * 0.012)
        self:SetRotation(self.rotation)
    end)

    model:SetScript("OnMouseWheel", function(self, delta)
        if not page.scModelReady or not self.SetModelScale or not self.scBaseScale then
            return
        end
        local zoom = (self.scZoom or DEFAULT_MODEL_SCALE) + (delta * 0.10)
        zoom = math.max(MIN_MODEL_SCALE, math.min(MAX_MODEL_SCALE, zoom))
        self.scZoom = zoom
        self:SetModelScale(self.scBaseScale * zoom)
    end)

    page:SetScript("OnHide", function(self)
        self.scModelGeneration = (self.scModelGeneration or 0) + 1
        clearModelInteraction()
        resetModelState()
        model:ClearModel()
        unavailable:Hide()
        CloseDropDownMenus()
    end)

    page.scList = list
    page.scListBackground = listBackground
    page.scDetail = detail
    page.scModel = model
    page.scUnavailable = unavailable
    page.scInfoButton = infoButton
    page.scInfoIcon = infoIcon
    page.scName = name
    page.scSource = source
    page.scDescription = description
    page.scCollectionState = collectionState
    page.scFavorite = favorite
    page.scSummon = summon
    page.scReset = reset
    page.scScrollFrame = scrollFrame
    page.scScrollHint = scrollHint
    page.scContextMenu = contextMenu
    page.scEmpty = empty
    return page
end
