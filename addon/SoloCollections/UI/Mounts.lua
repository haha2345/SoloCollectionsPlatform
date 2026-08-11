local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog

local VISIBLE_ROWS = 10
local ROW_HEIGHT = 46
local DEFAULT_ROTATION = 0.32
local DEFAULT_MODEL_SCALE = 1
local MIN_MODEL_SCALE = 0.35
local MAX_MODEL_SCALE = 2.5
local TWO_PI = math.pi * 2
local DRAG_ROTATION_CONSTANT = tonumber(MODELFRAME_DRAG_ROTATION_CONSTANT) or 0.010

local function createDetailLabel(parent, font, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetTextColor(color[1], color[2], color[3])
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function alignSourceInlineIcons(text)
    -- ezCollections source strings use :0 textures, whose native baseline is
    -- several pixels below Chinese GameFontHighlight on this 3.3.5a client.
    -- Give every source currency icon an explicit text-line size and lift it
    -- two pixels so the amount and icon read as one horizontal cost row.
    return (tostring(text or ""):gsub("|T([^|]-):0|t", "|T%1:13:13:0:2|t"))
end

local function showNotice(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

function UI.CreateMountsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scCategory = "MOUNTS"
    page.scRows = {}
    page.scRecords = {}
    page.scSelectedId = nil
    page.scModelGeneration = 0
    page.scModelReady = false

    local list = CreateFrame("Frame", nil, page)
    list:SetWidth(260)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
    list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 26)
    local listInset = UI.EzCollections:ApplyInset(list)
    local listBackground = listInset.background

    local detail = CreateFrame("Frame", nil, page)
    detail:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -60)
    detail:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 20, 0)
    UI.EzCollections:ApplyInset(detail)

    local detailBackground = detail:CreateTexture(nil, "BACKGROUND")
    detailBackground:SetTexture(UI.EzCollections:AssetPath("Interface\\PetBattles\\MountJournal-BG.blp", "Interface\\Buttons\\WHITE8X8"))
    detailBackground:SetPoint("TOPLEFT", detail, "TOPLEFT", 3, -3)
    detailBackground:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -3, 3)
    detailBackground:SetTexCoord(0, 0.78515625, 0, 1)
    UI.EzCollections:AddShadowOverlay(detail)
    UI.StyleNewEraCompanionLayout(page, list, detail, listBackground, detailBackground)

    local model = CreateFrame("PlayerModel", nil, detail)
    model:SetPoint("TOPLEFT", detail, "TOPLEFT", 3, -163)
    model:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -3, 31)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.rotation = DEFAULT_ROTATION
    model.scZoom = DEFAULT_MODEL_SCALE
    model.scBaseScale = nil
    local presenter = SC.ModelProvider and SC.ModelProvider.Create("CREATURE", model, {
        controls = false,
        panelCheck = function() return page:IsShown() end,
    }) or nil
    local function applyModelFacing(rotation)
        -- On this 3.3.5a client PlayerModel:SetRotation restarts the active
        -- animation sequence. SetFacing changes only the actor heading, which
        -- keeps idle animation time continuous while the mouse is moving.
        if model.SetFacing then
            model:SetFacing(rotation)
        elseif model.SetRotation then
            model:SetRotation(rotation, false)
        end
    end
    local function rotateModel(delta)
        model.rotation = (model.rotation or DEFAULT_ROTATION) + delta
        if model.rotation < 0 then model.rotation = model.rotation + TWO_PI end
        if model.rotation > TWO_PI then model.rotation = model.rotation - TWO_PI end
        applyModelFacing(model.rotation)
    end
    local rotateLeft, rotateRight = UI.EzCollections:CreateRotationButtons(model, function()
        rotateModel(-0.18)
    end, function()
        rotateModel(0.18)
    end)

    local modelShade = model:CreateTexture(nil, "BACKGROUND")
    modelShade:SetTexture("Interface\\Buttons\\WHITE8X8")
    modelShade:SetAllPoints(model)
    modelShade:SetVertexColor(0, 0, 0, 0.10)

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
    infoButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 9, -29)
    infoButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local infoIcon = infoButton:CreateTexture(nil, "ARTWORK")
    infoIcon:SetAllPoints(infoButton)
    UI.SetFallbackTexture(infoIcon)
    local infoBorder, infoSelectedBorder = UI.EzCollections:CreateCollectionIconFrames(infoButton)

    local randomSummon = CreateFrame("Button", nil, detail)
    randomSummon:SetWidth(33)
    randomSummon:SetHeight(33)
    randomSummon:SetPoint("CENTER", page, "TOPRIGHT", -24, -42)
    randomSummon:RegisterForClicks("LeftButtonUp")
    randomSummon:SetNormalTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    randomSummon:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    randomSummon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local randomIcon = randomSummon:GetNormalTexture()
    if randomIcon then randomIcon:SetAllPoints(randomSummon) end
    local randomPushed = randomSummon:GetPushedTexture()
    if randomPushed then randomPushed:SetAllPoints(randomSummon) end
    local randomBorder = randomSummon:CreateTexture(nil, "OVERLAY")
    randomBorder:SetTexture(UI.EzCollections:AssetPath(
        "Interface\\Buttons\\ActionBarFlyoutButton.blp",
        "Interface\\Buttons\\UI-Quickslot2"
    ))
    randomBorder:SetTexCoord(0.015625, 0.671875, 0.3984375, 0.7265625)
    randomBorder:SetSize(35, 35)
    randomBorder:SetPoint("CENTER", randomSummon, "CENTER", 0, 0)

    local randomLabel = randomSummon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    randomLabel:SetWidth(170)
    randomLabel:SetJustifyH("RIGHT")
    randomLabel:SetPoint("RIGHT", randomBorder, "LEFT", -2, 0)
    randomLabel:SetText("召唤随机偏好坐骑")

    local name = createDetailLabel(detail, "GameFontHighlightLarge", { 1, 1, 1 })
    name:SetPoint("TOPLEFT", infoButton, "TOPRIGHT", 12, -1)
    name:SetPoint("RIGHT", randomSummon, "LEFT", -8, 0)

    local collectionState = createDetailLabel(detail, "GameFontHighlight", { 0.45, 0.9, 0.35 })
    collectionState:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -7)

    local source = createDetailLabel(detail, "GameFontHighlight", { 1, 1, 1 })
    source:SetPoint("TOPLEFT", infoButton, "BOTTOMLEFT", 0, -11)
    source:SetPoint("RIGHT", detail, "RIGHT", -20, 0)

    local description = createDetailLabel(detail, "GameFontNormal", { 1, 0.82, 0.18 })
    description:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -7)
    description:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
    description:SetHeight(38)

    local favorite = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    favorite:SetWidth(104)
    favorite:SetHeight(22)
    favorite:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -8, 5)
    favorite:SetText("设为偏好")

    local reset = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    reset:SetWidth(104)
    reset:SetHeight(22)
    reset:SetPoint("RIGHT", favorite, "LEFT", -8, 0)
    reset:SetText("重置视角")

    local summon = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    summon:SetWidth(140)
    summon:SetHeight(22)
    summon:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    summon:SetText("召唤坐骑")
    UI.RegisterNewEraCompanionAction(page, favorite)
    UI.RegisterNewEraCompanionAction(page, reset)
    UI.RegisterNewEraCompanionAction(page, summon)

    local empty = UI.CreateEmptyState(list, "没有符合条件的坐骑")
    empty:SetPoint("CENTER", list, "CENTER", -10, 15)
    empty:Hide()

    local scrollHint = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scrollHint:SetPoint("BOTTOM", list, "BOTTOM", 0, 13)
    scrollHint:SetText("滚轮或拖动滚动条查看更多坐骑")
    scrollHint:SetTextColor(0.62, 0.56, 0.46)
    scrollHint:Hide()

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "SoloCollectionsMountScrollFrame",
        list,
        "FauxScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -36)
    scrollFrame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 5)
    scrollFrame:EnableMouseWheel(true)
    UI.EzCollections:SkinTrimScrollFrame(scrollFrame)

    local contextMenu = CreateFrame(
        "Frame",
        "SoloCollectionsMountContextMenu",
        page,
        "UIDropDownMenuTemplate"
    )

    local function clearDragState()
        model.scDragging = nil
        model.scLastCursorX = nil
        model:SetScript("OnUpdate", nil)
    end

    local function updateModelDrag(self)
        if not self.scDragging or not IsMouseButtonDown("LeftButton") then
            clearDragState()
            return
        end
        local cursorX = GetCursorPosition()
        local previousX = self.scLastCursorX or cursorX
        self.scLastCursorX = cursorX
        local delta = (cursorX - previousX) * DRAG_ROTATION_CONSTANT
        if delta == 0 then return end
        self.rotation = (self.rotation or DEFAULT_ROTATION) + delta
        if self.rotation < 0 then self.rotation = self.rotation + TWO_PI end
        if self.rotation > TWO_PI then self.rotation = self.rotation - TWO_PI end
        applyModelFacing(self.rotation)
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

    local function clearModelInteraction()
        clearDragState()
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
            showNotice("尚未收集该坐骑，无法召唤。")
            return
        end
        if not SC.Bridge or type(SC.Bridge.SummonMount) ~= "function" then
            showNotice("召唤桥接尚未安装；当前只能浏览坐骑。")
            return
        end
        SC.Bridge.SummonMount(record.id, function(ok, reason)
            if ok == false then
                showNotice(reason or "坐骑召唤请求失败。")
            end
        end)
    end

    local function getRandomOwnedMount()
        local owned = {}
        local favorites = {}
        for _, record in ipairs(Catalog.QueryAll("MOUNTS")) do
            if record.collected then
                owned[#owned + 1] = record
                if record.favorite then favorites[#favorites + 1] = record end
            end
        end
        local pool = #favorites > 0 and favorites or owned
        if #pool == 0 then return nil end
        if #pool > 1 and page.scLastRandomMountId then
            for _ = 1, 4 do
                local candidate = pool[math.random(1, #pool)]
                if candidate.id ~= page.scLastRandomMountId then return candidate end
            end
        end
        return pool[math.random(1, #pool)]
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
        summonInfo.text = "召唤坐骑"
        summonInfo.notCheckable = 1
        summonInfo.func = function()
            summonRecord(record)
        end
        if not record.collected then
            summonInfo.disabled = 1
            summonInfo.tooltipTitle = "无法召唤"
            summonInfo.tooltipText = "尚未收集该坐骑。"
        elseif not SC.Bridge or type(SC.Bridge.SummonMount) ~= "function" then
            summonInfo.disabled = 1
            summonInfo.tooltipTitle = "召唤桥接不可用"
            summonInfo.tooltipText = "Task 5 的客户端/服务端桥接尚未实现。"
        end
        UIDropDownMenu_AddButton(summonInfo)

        local favoriteInfo = UIDropDownMenu_CreateInfo()
        favoriteInfo.text = record.favorite and "取消收藏" or "收藏"
        favoriteInfo.notCheckable = 1
        favoriteInfo.func = function()
            Catalog.ToggleDemoFavorite("MOUNTS", record.id)
            page:Refresh()
        end
        if not record.collected then
            favoriteInfo.disabled = 1
            favoriteInfo.tooltipTitle = "尚未收集"
            favoriteInfo.tooltipText = "未收集的坐骑不能设为偏好。"
        end
        UIDropDownMenu_AddButton(favoriteInfo)
    end, "MENU")

    local function requestModel(record)
        page.scModelGeneration = (page.scModelGeneration or 0) + 1
        local generation = page.scModelGeneration
        clearModelInteraction()
        resetModelState()
        model:ClearModel()
        unavailable:Hide()

        if not presenter or not SC.Bridge or type(SC.Bridge.RequestCreaturePreview) ~= "function" then
            unavailable:SetText("模型预览暂不可用")
            unavailable:Show()
            rotateHint:Hide()
            return
        end
        presenter:Present({
            creatureEntry = record.previewCreatureEntry,
            rotation = DEFAULT_ROTATION,
            preview = function(done)
                SC.Bridge.RequestCreaturePreview(10, record.id, function(ok, reason)
                    if page.scModelGeneration == generation then done(ok, reason) end
                end)
            end,
            onReady = function()
                if page.scModelGeneration ~= generation then return end
                model.scBaseScale = getNativeModelScale()
                model.scZoom = DEFAULT_MODEL_SCALE
                page.scModelReady = true
                unavailable:Hide(); rotateHint:Show()
            end,
            onUnavailable = function(reason)
                if page.scModelGeneration ~= generation then return end
                model.scUnavailableReason = reason
                unavailable:SetText("模型预览暂不可用")
                unavailable:Show(); rotateHint:Hide()
            end,
        })
    end

    local function selectRecord(record)
        if not record then
            page:ClearSelection()
            return
        end
        local modelChanged = page.scSelectedId ~= record.id or not page.scModelReady
        page.scSelectedId = record.id
        page.scSelectedRecord = record
        UI.SetIconTexture(infoIcon, record.icon)
        UI.SetCollectedVisual(infoIcon, record.collected)
        infoBorder:SetCollected(record.collected)
        infoSelectedBorder:Show()
        name:SetText(record.name or "未知坐骑")
        source:SetText("来源：" .. alignSourceInlineIcons(record.source or "未知"))
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
        if modelChanged then requestModel(record) end
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
            scrollHint:SetText("滚轮或拖动滚动条查看更多坐骑  " .. first .. "-" .. last .. " / " .. #records)
        else
            scrollHint:SetText("共 " .. #records .. " 个坐骑")
        end
    end

    local function scrollByWheel(self, delta)
        local currentOffset = FauxScrollFrame_GetOffset(self) or 0
        local maxOffset = math.max(0, #(page.scRecords or {}) - VISIBLE_ROWS)
        local newOffset = math.max(0, math.min(maxOffset, currentOffset - delta))
        FauxScrollFrame_OnVerticalScroll(self, newOffset * ROW_HEIGHT, ROW_HEIGHT, refreshRows)
    end

    for index = 1, VISIBLE_ROWS do
        local row = UI.CreateMountListRow(list, 208, 46, function(_, record)
            selectRecord(record)
        end, function(anchor, record)
            openContextMenu(anchor, record)
        end)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 47, -(36 + ((index - 1) * ROW_HEIGHT)))
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
        infoBorder:SetCollected(false)
        infoSelectedBorder:Hide()
        unavailable:Hide()
        clearModelInteraction()
        resetModelState()
        if presenter then presenter:Clear("NO_SELECTION") else model:ClearModel() end
        for _, row in ipairs(self.scRows) do
            row:SetSelected(false)
        end
    end

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scFilterPopup or not SC.db or SC.db.mainTab ~= "MOUNTS" then
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
        local records = Catalog.QueryAll("MOUNTS", SC.db.query, SC.db.filters)
        self.scRecords = records
        FauxScrollFrame_Update(scrollFrame, #records, VISIBLE_ROWS, ROW_HEIGHT)

        local selectedRecord
        for _, record in ipairs(records) do
            if record.id == self.scSelectedId then
                selectedRecord = record
                break
            end
        end

        local collected, total = Catalog.GetProgress("MOUNTS", SC.db.filters)
        if UI.CollectionsFrame and UI.CollectionsFrame.scProgress then
            UI.CollectionsFrame.scProgress:SetProgress(collected, total)
        end
        if UI.CollectionsFrame and UI.CollectionsFrame.scMountCount then
            local allCollected, allTotal = Catalog.GetProgress("MOUNTS")
            UI.CollectionsFrame.scMountCount:SetCount(allCollected, allTotal)
        end

        if #records == 0 then
            self:ClearSelection()
            refreshRows()
            UI.ShowEmptyState(empty, self, "没有符合条件的坐骑", "调整搜索文字或过滤条件后再试。")
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
        Catalog.ToggleDemoFavorite("MOUNTS", record.id)
        page:Refresh()
    end)

    reset:SetScript("OnClick", function()
        model.rotation = DEFAULT_ROTATION
        if presenter and presenter.ResetView then presenter:ResetView()
        elseif page.scSelectedRecord then requestModel(page.scSelectedRecord) end
    end)

    summon:SetScript("OnClick", function() summonRecord(page.scSelectedRecord) end)

    randomSummon:SetScript("OnClick", function()
        local record = getRandomOwnedMount()
        if not record then
            showNotice("尚未收集可召唤的坐骑。")
            return
        end
        page.scLastRandomMountId = record.id
        summonRecord(record)
    end)
    randomSummon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("召唤随机坐骑", 1, 0.82, 0.18)
        GameTooltip:AddLine("优先从已收集的偏好坐骑中随机选择；没有偏好时从全部已收集坐骑中选择。", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    randomSummon:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
            self.scLastCursorX = GetCursorPosition()
            self:SetScript("OnUpdate", updateModelDrag)
        end
    end)
    model:SetScript("OnMouseUp", function()
        clearDragState()
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        if not page.scModelReady or not self.SetModelScale or not self.GetModelScale then
            return
        end
        if not self.scBaseScale then
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
        if presenter then presenter:Clear("PAGE_HIDDEN") else model:ClearModel() end
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
    page.scInfoBorder = infoBorder
    page.scInfoSelectedBorder = infoSelectedBorder
    page.scName = name
    page.scSource = source
    page.scDescription = description
    page.scCollectionState = collectionState
    page.scFavorite = favorite
    page.scReset = reset
    page.scSummon = summon
    page.scRandomSummon = randomSummon
    page.scPresenter = presenter
    page.scRotateLeft = rotateLeft
    page.scRotateRight = rotateRight
    page.scScrollFrame = scrollFrame
    page.scScrollHint = scrollHint
    page.scContextMenu = contextMenu
    page.scEmpty = empty
    return page
end
