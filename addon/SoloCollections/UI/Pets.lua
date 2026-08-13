local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog
local CompanionJournal = UI.DragonUI and (UI.DragonUI.CompanionJournal or UI.DragonUI.MountJournal)

local JOURNAL_LAYOUT = CompanionJournal and CompanionJournal:GetLayout() or {}
local VISIBLE_ROWS = JOURNAL_LAYOUT.visibleRows or 10
local ROW_HEIGHT = JOURNAL_LAYOUT.rowHeight or 46
local ROW_START_Y = JOURNAL_LAYOUT.rowStartY or 3
local DEFAULT_ROTATION = 0.32
local DEFAULT_MODEL_SCALE = 1
local MIN_MODEL_SCALE = 0.35
local MAX_MODEL_SCALE = 2.5
local TWO_PI = math.pi * 2
local DRAG_ROTATION_CONSTANT = tonumber(MODELFRAME_DRAG_ROTATION_CONSTANT) or 0.010
local RANDOM_PET_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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

local function getPetActionMessage(reason)
    if SC.Bridge and type(SC.Bridge.GetPetActionMessage) == "function" then
        return SC.Bridge.GetPetActionMessage(reason)
    end
    return reason or "小宠物操作失败，请稍后再试。"
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
    page.scModelReady = false

    local bands = CompanionJournal and CompanionJournal:CreateBands(page)
    local list = CreateFrame("Frame", nil, page)
    if CompanionJournal then
        CompanionJournal:LayoutInset(list, "left")
    else
        list:SetWidth(260)
        list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
        list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 26)
    end
    local listInset = UI.EzCollections:ApplyInset(list)
    local listBackground = listInset.background

    local detail = CreateFrame("Frame", nil, page)
    if CompanionJournal then
        CompanionJournal:LayoutInset(detail, "right")
    else
        detail:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -60)
        detail:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 20, 0)
    end
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

    local infoHeader = CompanionJournal and CompanionJournal:CreateCollectionInfoHeader(detail, {
        x = 4,
        y = 4,
        width = 420,
        height = 124,
        textWidth = 320,
    })
    local infoButton = infoHeader and infoHeader.button or CreateFrame("Button", nil, detail)
    if not infoHeader then
        infoButton:SetSize(40, 40)
        infoButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 9, -29)
        infoButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    local infoIcon = infoHeader and infoHeader.icon or infoButton:CreateTexture(nil, "ARTWORK")
    if not infoHeader then
        infoIcon:SetAllPoints(infoButton)
        UI.SetFallbackTexture(infoIcon)
    end
    local infoBorder, infoSelectedBorder
    if not infoHeader then
        infoBorder, infoSelectedBorder = UI.EzCollections:CreateCollectionIconFrames(infoButton)
    end

    local randomHost = CreateFrame("Frame", nil, (bands and bands.top) or detail)
    randomHost:SetSize(190, 30)
    randomHost:SetPoint("BOTTOMRIGHT", detail, "TOPRIGHT", -8, JOURNAL_LAYOUT.randomDetailGap or 6)
    local randomSummon = CompanionJournal and CompanionJournal:CreateRandomCompanionButton(randomHost, {
        label = "随机召唤小宠物",
        icon = RANDOM_PET_FALLBACK_ICON,
        fallbackIcon = RANDOM_PET_FALLBACK_ICON,
        tooltip = "优先从已收集的偏好小宠物中随机选择；没有偏好时由服务端从全部可用小宠物中选择。",
    }) or CreateFrame("Button", nil, randomHost)
    randomSummon:SetSize(30, 30)
    randomSummon:SetPoint("RIGHT", randomHost, "RIGHT", 0, 0)

    local name = infoHeader and infoHeader.name or createDetailLabel(detail, "GameFontHighlightLarge", { 1, 1, 1 })
    if not infoHeader then
        name:SetPoint("TOPLEFT", infoButton, "TOPRIGHT", 12, -1)
        name:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
    end

    local collectionState = createDetailLabel(detail, "GameFontHighlight", { 0.45, 0.9, 0.35 })
    collectionState:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -7)

    local source = infoHeader and infoHeader.source or createDetailLabel(detail, "GameFontHighlight", { 1, 1, 1 })
    if not infoHeader then
        source:SetPoint("TOPLEFT", infoButton, "BOTTOMLEFT", 0, -11)
        source:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
    end

    local description = infoHeader and infoHeader.description or createDetailLabel(detail, "GameFontNormal", { 0.82, 0.82, 0.82 })
    if not infoHeader then
        description:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -7)
        description:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
        description:SetHeight(38)
    end

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

    local summon = CreateFrame("Button", nil, (bands and bands.bottom) or page, "UIPanelButtonTemplate")
    summon:SetWidth(180)
    summon:SetHeight(26)
    summon:SetPoint("CENTER", (bands and bands.bottom) or page, "CENTER", 0, 0)
    summon:SetText("召唤小宠物")
    if CompanionJournal then CompanionJournal:SkinRedActionButton(summon) end
    UI.RegisterNewEraCompanionAction(page, favorite)
    UI.RegisterNewEraCompanionAction(page, reset)
    UI.RegisterNewEraCompanionAction(page, summon)

    local empty = UI.CreateEmptyState(list, "没有符合条件的小宠物")
    empty:SetPoint("CENTER", list, "CENTER", -10, 15)
    empty:Hide()

    local scrollHint = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scrollHint:SetPoint("BOTTOM", list, "BOTTOM", 0, 13)
    scrollHint:SetText("滚轮或拖动滚动条查看更多小宠物")
    scrollHint:SetTextColor(0.62, 0.56, 0.46)
    scrollHint:Hide()

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "SoloCollectionsPetScrollFrame",
        list,
        "FauxScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -ROW_START_Y)
    scrollFrame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, ROW_START_Y)
    scrollFrame:EnableMouseWheel(true)
    UI.EzCollections:SkinTrimScrollFrame(scrollFrame)

    local contextMenu = CreateFrame(
        "Frame",
        "SoloCollectionsPetContextMenu",
        page,
        "UIDropDownMenuTemplate"
    )
    local filterMenu = _G.SoloCollectionsPetFilterMenu
    if not filterMenu then
        filterMenu = CreateFrame(
            "Frame", "SoloCollectionsPetFilterMenu", UIParent, "UIDropDownMenuTemplate"
        )
    end
    local function refreshFilterMenu()
        if filterMenu and UIDropDownMenu_Refresh then
            pcall(UIDropDownMenu_Refresh, filterMenu, nil, 1)
        end
    end
    local function petFilters()
        if not SC.db then return nil end
        SC.db.filters = SC.db.filters or {}
        SC.db.filters.pets = SC.db.filters.pets or {}
        local filters = SC.db.filters.pets
        if type(filters.hiddenSources) ~= "table" then filters.hiddenSources = {} end
        return filters
    end
    local function filterMenuInit(self, level)
        level = level or 1
        if not SC.db then return end
        local filters = SC.db.filters
        if level == 1 then
            local function addToggle(label, key)
                local info = UIDropDownMenu_CreateInfo()
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.text = label
                info.checked = function() return filters[key] and true or false end
                info.func = function(_, _, _, checked)
                    filters[key] = checked == nil and not filters[key] or checked and true or false
                    page:Refresh()
                    refreshFilterMenu()
                end
                UIDropDownMenu_AddButton(info, level)
            end
            addToggle("已收集", "collected")
            addToggle("未收集", "uncollected")
            addToggle("仅显示偏好", "favorites")

            local sources = UIDropDownMenu_CreateInfo()
            sources.text = "来源"
            sources.notCheckable = true
            sources.hasArrow = true
            sources.value = "sources"
            UIDropDownMenu_AddButton(sources, level)
        elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "sources" then
            local all = UIDropDownMenu_CreateInfo()
            all.notCheckable = true
            all.keepShownOnClick = true
            all.text = "显示全部来源"
            all.func = function()
                petFilters().hiddenSources = {}
                page:Refresh()
                refreshFilterMenu()
            end
            UIDropDownMenu_AddButton(all, level)

            local none = UIDropDownMenu_CreateInfo()
            none.notCheckable = true
            none.keepShownOnClick = true
            none.text = "隐藏全部来源"
            none.func = function()
                local state = petFilters()
                state.hiddenSources = {}
                for _, sourceType in ipairs(Catalog.GetPetSourceOrder()) do
                    state.hiddenSources[sourceType] = true
                end
                page:Refresh()
                refreshFilterMenu()
            end
            UIDropDownMenu_AddButton(none, level)

            for _, sourceType in ipairs(Catalog.GetPetSourceOrder()) do
                local sourceKey = sourceType
                local info = UIDropDownMenu_CreateInfo()
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.text = Catalog.PetSourceLabel(sourceKey)
                info.checked = function() return not petFilters().hiddenSources[sourceKey] end
                info.func = function(_, _, _, checked)
                    local state = petFilters()
                    if checked == nil then checked = not state.hiddenSources[sourceKey] end
                    state.hiddenSources[sourceKey] = checked and nil or true
                    page:Refresh()
                    refreshFilterMenu()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(filterMenu, filterMenuInit, "MENU")
    end

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

    local refreshSummonButton
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
                showNotice(getPetActionMessage(reason))
            end
            refreshSummonButton(record)
        end)
    end

    local function isRecordSummoned(record)
        local wantedSpellId = record and tonumber(record.canonicalActionSpellId or record.spellId)
        if not wantedSpellId or type(GetNumCompanions) ~= "function" or
            type(GetCompanionInfo) ~= "function" then
            return false
        end
        for index = 1, (GetNumCompanions("CRITTER") or 0) do
            local _, _, spellId, _, active = GetCompanionInfo("CRITTER", index)
            if tonumber(spellId) == wantedSpellId and active then
                return true
            end
        end
        return false
    end

    refreshSummonButton = function(record)
        summon:SetText(isRecordSummoned(record) and "解散小宠物" or "召唤小宠物")
    end

    local function setFavoriteRecord(record)
        if not record or not record.collected then
            showNotice(getPetActionMessage("FAVORITE_NOT_OWNED"))
            return
        end
        if not SC.Bridge or type(SC.Bridge.SetPetFavorite) ~= "function" or
            SC.Bridge.GetCategoryState(17) ~= "Ready" then
            showNotice("小宠物偏好正在同步，请稍后再试。")
            return
        end
        page.scPendingFavoriteId = record.id
        favorite:Disable()
        SC.Bridge.SetPetFavorite(record.id, not record.favorite, function(ok, reason)
            if ok == false then
                page.scPendingFavoriteId = nil
                showNotice(getPetActionMessage(reason))
                page:Refresh()
            end
        end)
    end

    local function summonRandomPet()
        if not SC.Bridge or type(SC.Bridge.SummonRandomPet) ~= "function" then
            showNotice(getPetActionMessage("BRIDGE_UNAVAILABLE"))
            return
        end
        SC.Bridge.SummonRandomPet(function(ok, reason)
            if ok == false then showNotice(getPetActionMessage(reason)) end
            refreshSummonButton(page.scSelectedRecord)
        end)
    end

    local function updateRandomPetIcon()
        local preferred, eligible
        for _, record in ipairs(Catalog.Get("PETS")) do
            if record.collected and record.actionable and record.randomEligible then
                if record.favorite and not preferred then preferred = record end
                if not eligible then eligible = record end
            end
        end
        local iconRecord = preferred or eligible
        local icon = randomSummon._neIcon or randomSummon._tex
        if icon then UI.SetIconTexture(icon, iconRecord and iconRecord.icon or RANDOM_PET_FALLBACK_ICON) end
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
        summonInfo.text = isRecordSummoned(record) and "解散小宠物" or "召唤小宠物"
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
            setFavoriteRecord(record)
        end
        if not record.collected then
            favoriteInfo.disabled = 1
            favoriteInfo.tooltipTitle = "尚未收集"
            favoriteInfo.tooltipText = "未收集的小宠物不能设为偏好。"
        elseif not SC.Bridge or SC.Bridge.GetCategoryState(17) ~= "Ready" then
            favoriteInfo.disabled = 1
            favoriteInfo.tooltipTitle = "偏好正在同步"
            favoriteInfo.tooltipText = "服务端偏好状态就绪后才能修改。"
        end
        UIDropDownMenu_AddButton(favoriteInfo)
    end, "MENU")

    local function requestModel(record, force)
        page.scModelGeneration = (page.scModelGeneration or 0) + 1
        local generation = page.scModelGeneration
        local selectedId = record and record.id
        clearModelInteraction()
        resetModelState()
        model:ClearModel()
        unavailable:Hide()

        local bridgeState = SC.Bridge and SC.Bridge.GetCategoryState
            and SC.Bridge.GetCategoryState(11)
            or "Disconnected"
        if not force and bridgeState ~= "Ready" then
            page.scPendingModelId = selectedId
            if bridgeState == "Loading" or bridgeState == "Disconnected" then
                unavailable:SetText("正在连接收藏服务…")
            elseif bridgeState == "Mismatch" then
                unavailable:SetText("小宠物目录版本不匹配")
            else
                unavailable:SetText("小宠物模型服务不可用")
            end
            unavailable:Show()
            rotateHint:Hide()
            return
        end
        page.scPendingModelId = nil

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
                SC.Bridge.RequestCreaturePreview(11, record.id, function(ok, reason)
                    if page.scModelGeneration == generation and page.scSelectedId == selectedId then
                        done(ok, reason)
                    end
                end)
            end,
            onReady = function()
                if page.scModelGeneration ~= generation or page.scSelectedId ~= selectedId then return end
                page.scPendingModelId = nil
                model.scBaseScale = getNativeModelScale()
                model.scZoom = DEFAULT_MODEL_SCALE
                page.scModelReady = true
                unavailable:Hide(); rotateHint:Show()
            end,
            onUnavailable = function(reason)
                if page.scModelGeneration ~= generation or page.scSelectedId ~= selectedId then return end
                model.scUnavailableReason = reason
                if reason == "BRIDGE_UNAVAILABLE" or reason == "TIMEOUT" then
                    page.scPendingModelId = selectedId
                    unavailable:SetText("正在连接收藏服务…")
                else
                    unavailable:SetText("模型预览暂不可用")
                end
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
        infoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        UI.SetCollectedVisual(infoIcon, record.collected)
        if infoBorder then infoBorder:SetCollected(record.collected) end
        if infoSelectedBorder then infoSelectedBorder:Show() end
        name:SetText(record.name or "未知小宠物")
        source:SetText(record.source or "来源未知")
        local descriptionText = record.description and record.description ~= "" and record.description
            or "暂无可核验的中文描述"
        description:SetText(descriptionText)
        description:Show()
        refreshSummonButton(record)
        if record.collected then
            collectionState:SetText("已收集")
            collectionState:SetTextColor(0.38, 0.9, 0.30)
            if SC.Bridge and SC.Bridge.GetCategoryState(17) == "Ready" and
                page.scPendingFavoriteId ~= record.id then
                favorite:Enable()
            else
                favorite:Disable()
            end
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
            scrollHint:SetText("滚轮或拖动滚动条查看更多小宠物  " .. first .. "-" .. last .. " / " .. #records)
        else
            scrollHint:SetText("共 " .. #records .. " 个小宠物")
        end
    end

    local function scrollSelectionIntoView(records, selectedId)
        if not selectedId then return end
        local selectedIndex
        for index, record in ipairs(records) do
            if record.id == selectedId then selectedIndex = index; break end
        end
        if not selectedIndex then return end
        local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
        local newOffset = offset
        if selectedIndex <= offset then
            newOffset = selectedIndex - 1
        elseif selectedIndex > offset + VISIBLE_ROWS then
            newOffset = selectedIndex - VISIBLE_ROWS
        end
        newOffset = math.max(0, math.min(math.max(0, #records - VISIBLE_ROWS), newOffset))
        if newOffset ~= offset then
            FauxScrollFrame_OnVerticalScroll(scrollFrame, newOffset * ROW_HEIGHT, ROW_HEIGHT, refreshRows)
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
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 47, -(ROW_START_Y + ((index - 1) * ROW_HEIGHT)))
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
        self.scPendingModelId = nil
        name:SetText("")
        source:SetText("")
        description:SetText("")
        description:Hide()
        collectionState:SetText("")
        favorite:SetText("设为偏好")
        favorite:Disable()
        summon:SetText("召唤小宠物")
        summon:Disable()
        UI.SetFallbackTexture(infoIcon)
        infoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if infoBorder then infoBorder:SetCollected(false) end
        if infoSelectedBorder then infoSelectedBorder:Hide() end
        unavailable:Hide()
        clearModelInteraction()
        resetModelState()
        if presenter then presenter:Clear("NO_SELECTION") else model:ClearModel() end
        for _, row in ipairs(self.scRows) do
            row:SetSelected(false)
        end
    end

    function page:SyncFilters()
        if not SC.db or SC.db.mainTab ~= "PETS" then return end
        refreshFilterMenu()
    end

    function page:OpenFilterMenu(anchor)
        if not filterMenu or not ToggleDropDownMenu then return end
        self:SyncFilters()
        ToggleDropDownMenu(1, nil, filterMenu, anchor or self, 0, 0)
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

        local collected, total = Catalog.GetProgress("PETS")
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
            scrollSelectionIntoView(records, selectedRecord and selectedRecord.id or records[1].id)
            selectRecord(selectedRecord or records[1])
            refreshRows()
        end
        updateRandomPetIcon()
        self:SyncFilters()
    end

    favorite:SetScript("OnClick", function()
        local record = page.scSelectedRecord
        if not record or not record.collected then
            return
        end
        setFavoriteRecord(record)
    end)

    summon:SetScript("OnClick", function()
        local record = page.scSelectedRecord
        summonRecord(record)
        refreshSummonButton(record)
    end)

    randomSummon:SetScript("OnClick", summonRandomPet)

    reset:SetScript("OnClick", function()
        model.rotation = DEFAULT_ROTATION
        if presenter and presenter.ResetView then presenter:ResetView()
        elseif page.scSelectedRecord then requestModel(page.scSelectedRecord) end
    end)

    if SC.Bridge and type(SC.Bridge.RegisterStateListener) == "function" then
        page.scBridgeStateListener = SC.Bridge.RegisterStateListener(function(_, typeId)
            typeId = tonumber(typeId)
            if typeId ~= nil and typeId ~= 11 and typeId ~= 17 then return end
            local record = page.scSelectedRecord
            if typeId == 17 then page.scPendingFavoriteId = nil end
            if not page:IsShown() then return end
            page:Refresh()
            record = page.scSelectedRecord
            if typeId == 17 or not record then return end
            local state = SC.Bridge.GetCategoryState and SC.Bridge.GetCategoryState(11)
            if state == "Ready" and page.scPendingModelId == record.id then
                requestModel(record, true)
            elseif state == "Mismatch" and page.scPendingModelId == record.id then
                unavailable:SetText("小宠物目录版本不匹配")
                unavailable:Show(); rotateHint:Hide()
            end
        end)
    end

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
        self:ClearSelection()
        CloseDropDownMenus()
    end)

    page:RegisterEvent("COMPANION_UPDATE")
    page:SetScript("OnEvent", function()
        refreshSummonButton(page.scSelectedRecord)
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
    page.scSummon = summon
    page.scRandomSummon = randomSummon
    page.scReset = reset
    page.scPresenter = presenter
    page.scRotateLeft = rotateLeft
    page.scRotateRight = rotateRight
    page.scScrollFrame = scrollFrame
    page.scScrollHint = scrollHint
    page.scContextMenu = contextMenu
    page.scFilterMenu = filterMenu
    page.scEmpty = empty
    return page
end
