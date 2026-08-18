local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog
local MountJournal = UI.DragonUI and UI.DragonUI.MountJournal

local JOURNAL_LAYOUT = MountJournal and MountJournal:GetLayout() or {}
local VISIBLE_ROWS = JOURNAL_LAYOUT.visibleRows or 10
local ROW_HEIGHT = JOURNAL_LAYOUT.rowHeight or 46
local ROW_START_Y = JOURNAL_LAYOUT.rowStartY or 3
local DEFAULT_ROTATION = 0.32
local DEFAULT_MODEL_SCALE = 1
local MIN_MODEL_SCALE = 0.35
local MAX_MODEL_SCALE = 2.5
local TWO_PI = math.pi * 2
local DRAG_ROTATION_CONSTANT = tonumber(MODELFRAME_DRAG_ROTATION_CONSTANT) or 0.010
local RANDOM_MOUNT_SPELL_ID = 150544
local RANDOM_MOUNT_ICON = "Interface\\Icons\\SoloCollections_RandomMount"

local MOUNT_ACTION_MESSAGES = {
    LOADING = "收藏数据仍在加载，请稍后再试。",
    NOT_OWNED = "你尚未收集该坐骑。",
    FAVORITE_NOT_OWNED = "只有已获得的坐骑才能设为偏好。",
    NO_MOUNTS = "尚未获得可召唤的坐骑。",
    NO_USABLE_MOUNTS = "当前没有可在此处召唤的坐骑。",
    CATALOG_MISMATCH = "客户端与服务端的坐骑目录版本不一致。",
    ASSET_MISMATCH = "客户端坐骑资源版本与服务端不一致。",
    UNKNOWN_IDENTITY = "服务端无法识别当前角色。",
    CLASS_RESTRICTED = "当前职业不能使用这只坐骑。",
    RACE_RESTRICTED = "当前种族不能使用这只坐骑。",
    SKILL_REQUIRED = "当前骑术等级不足，无法召唤这只坐骑。",
    INVALID_TARGET_SLOT = "当前目标栏位无效。",
    NOT_ENOUGH_MONEY = "金币不足，无法完成该操作。",
    NOT_ENOUGH_TOKENS = "所需代币不足，无法完成该操作。",
    DB_UNAVAILABLE = "收藏数据库暂时不可用。",
    RATE_LIMITED = "操作过于频繁，请稍后再试。",
    INVALID_REQUEST = "坐骑召唤请求无效。",
    UNSUPPORTED = "当前坐骑暂不支持召唤。",
    IN_COMBAT = "战斗中不能召唤坐骑。",
    DEAD = "死亡状态下不能召唤坐骑。",
    IN_VEHICLE = "乘坐载具时不能召唤坐骑。",
    ON_TAXI = "正在使用飞行路线时不能召唤坐骑。",
    INDOORS = "室内不能召唤坐骑。",
    FLYING_NOT_ALLOWED = "当前等级或区域尚未开放飞行。",
    MAP_RESTRICTED = "当前地图不能使用这只坐骑。",
    BATTLEGROUND_RESTRICTED = "战场中不能通过收藏系统召唤坐骑。",
    SHAPESHIFT_RESTRICTED = "当前非人形状态不能召唤坐骑。",
    CAST_FAILED = "坐骑召唤失败，请检查当前角色状态。",
    BRIDGE_UNAVAILABLE = "收藏服务尚未连接。",
    TIMEOUT = "坐骑召唤请求超时，请重试。",
}

local function getMountActionMessage(reason)
    return MOUNT_ACTION_MESSAGES[reason] or "坐骑召唤请求失败。"
end

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
    local summonRecord, setFavoriteRecord, summonRandomMount, openContextMenu, pickupRandomMountSpell
    local companionIndexBySpell = {}

    local function rebuildCompanionIndex()
        companionIndexBySpell = {}
        if type(GetNumCompanions) ~= "function" or type(GetCompanionInfo) ~= "function" then return end
        for index = 1, (GetNumCompanions("MOUNT") or 0) do
            local _, _, spellId = GetCompanionInfo("MOUNT", index)
            spellId = tonumber(spellId)
            if spellId and spellId > 0 then companionIndexBySpell[spellId] = index end
        end
    end

    local function pickupMountCompanion(record)
        if not record or not record.collected then
            showNotice("尚未获得该坐骑，不能拖到动作条。")
            return false
        end
        local spellId = tonumber(record.canonicalActionSpellId)
        if not spellId or spellId <= 0 then
            showNotice("该坐骑暂不支持动作条拖拽。")
            return false
        end
        local index = companionIndexBySpell[spellId]
        if not index then
            rebuildCompanionIndex()
            index = companionIndexBySpell[spellId]
        end
        if not index or type(PickupCompanion) ~= "function" then
            showNotice("坐骑技能正在同步，请稍后再试。")
            return false
        end
        PickupCompanion("MOUNT", index)
        return true
    end

    local function insertMountLink(record)
        local spellId = record and tonumber(record.canonicalActionSpellId)
        local link = spellId and GetSpellLink and GetSpellLink(spellId)
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    end

    local bands = MountJournal and MountJournal:CreateBands(page)
    local list = CreateFrame("Frame", nil, page)
    if MountJournal then
        MountJournal:LayoutInset(list, "left")
    else
        list:SetWidth(260)
        list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
        list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 26)
    end
    local listInset = UI.EzCollections:ApplyInset(list)
    local listBackground = listInset.background

    local detail = CreateFrame("Frame", nil, page)
    if MountJournal then
        MountJournal:LayoutInset(detail, "right")
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

    local infoHeader = MountJournal and MountJournal:CreateCollectionInfoHeader(detail, {
        x = 4,
        y = 4,
        width = 420,
        height = 124,
        textWidth = 320,
        onClick = function(self, button)
            local record = page.scSelectedRecord
            if button == "RightButton" then
                openContextMenu(self, record)
            else
                summonRecord(record)
            end
        end,
    })
    local infoButton = infoHeader and infoHeader.button or CreateFrame("Button", nil, detail)
    if not infoHeader then
        infoButton:SetSize(40, 40)
        infoButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 9, -29)
        infoButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    infoButton:RegisterForDrag("LeftButton")
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
    local randomSummon = MountJournal and MountJournal:CreateRandomMountButton(randomHost, {
        icon = RANDOM_MOUNT_ICON,
        onClick = function()
            summonRandomMount()
        end,
        onDragStart = function()
            pickupRandomMountSpell()
        end,
    }) or CreateFrame("Button", nil, randomHost)
    randomSummon:SetSize(30, 30)
    randomSummon:SetPoint("RIGHT", randomHost, "RIGHT", 0, 0)
    randomSummon:RegisterForDrag("LeftButton")

    local function findRandomMountSpellBookSlot()
        if type(GetNumSpellTabs) ~= "function" then return nil end
        for tab = 1, (GetNumSpellTabs() or 0) do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
                local spellType, spellId = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
                if spellType == "SPELL" and tonumber(spellId) == RANDOM_MOUNT_SPELL_ID then
                    return slot
                end
                local link = GetSpellLink and GetSpellLink(slot, BOOKTYPE_SPELL)
                if link and tonumber(link:match("spell:(%d+)")) == RANDOM_MOUNT_SPELL_ID then
                    return slot
                end
            end
        end
        return nil
    end

    pickupRandomMountSpell = function()
        local slot = findRandomMountSpellBookSlot()
        if not slot or type(PickupSpell) ~= "function" then
            showNotice("随机坐骑技能正在同步，请稍后再试。")
            return false
        end
        PickupSpell(slot, BOOKTYPE_SPELL)
        return true
    end

    local randomLabel = randomHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    randomLabel:SetWidth(150)
    randomLabel:SetJustifyH("RIGHT")
    randomLabel:SetPoint("RIGHT", randomSummon, "LEFT", -6, 0)
    randomLabel:SetText("随机骑乘收藏坐骑")

    local name = infoHeader and infoHeader.name or createDetailLabel(detail, "GameFontHighlightLarge", { 1, 1, 1 })
    if not infoHeader then
        name:SetPoint("TOPLEFT", infoButton, "TOPRIGHT", 12, -1)
        name:SetPoint("RIGHT", randomSummon, "LEFT", -8, 0)
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
    summon:SetText("召唤坐骑")
    if MountJournal then MountJournal:SkinRedActionButton(summon) end
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
    scrollFrame:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -ROW_START_Y)
    scrollFrame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, ROW_START_Y)
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

    summonRecord = function(record)
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
                showNotice(getMountActionMessage(reason))
            end
        end)
    end

    setFavoriteRecord = function(record)
        if not record or not record.collected then
            showNotice(MOUNT_ACTION_MESSAGES.FAVORITE_NOT_OWNED)
            return
        end
        if not SC.Bridge or type(SC.Bridge.SetMountFavorite) ~= "function" or
            SC.Bridge.GetCategoryState(16) ~= "Ready" then
            showNotice("坐骑偏好正在同步，请稍后再试。")
            return
        end
        favorite:Disable()
        SC.Bridge.SetMountFavorite(record.id, not record.favorite, function(ok, reason)
            if ok == false then showNotice(getMountActionMessage(reason)) end
            page:Refresh()
        end)
    end

    summonRandomMount = function()
        if not SC.Bridge or type(SC.Bridge.SummonRandomMount) ~= "function" then
            showNotice(MOUNT_ACTION_MESSAGES.BRIDGE_UNAVAILABLE)
            return
        end
        SC.Bridge.SummonRandomMount(function(ok, reason)
            if ok == false then showNotice(getMountActionMessage(reason)) end
        end)
    end

    openContextMenu = function(anchor, record)
        if not record then
            return
        end
        page.scContextRecord = record
        ToggleDropDownMenu(1, nil, contextMenu, anchor, 0, 0)
    end

    local filterMenu
    local function mountFilters()
        if not SC.db then return nil end
        SC.db.filters = SC.db.filters or {}
        SC.db.filters.mounts = SC.db.filters.mounts or {}
        local filters = SC.db.filters.mounts
        if type(filters.hiddenSources) ~= "table" then filters.hiddenSources = {} end
        return filters
    end

    local function refreshFilterMenu()
        if filterMenu and UIDropDownMenu_Refresh then
            pcall(UIDropDownMenu_Refresh, filterMenu, nil, 1)
        end
        if not UIDROPDOWNMENU_MAXBUTTONS then return end
        for level = 1, 2 do
            for index = 1, UIDROPDOWNMENU_MAXBUTTONS do
                local button = _G["DropDownList" .. level .. "Button" .. index]
                local check = _G["DropDownList" .. level .. "Button" .. index .. "Check"]
                if button and check then
                    local checked = button:IsShown() and type(button.checked) == "function"
                        and button.checked()
                    if checked then check:Show() else check:Hide() end
                end
            end
        end
    end

    local function filterMenuInit(self, level)
        level = level or 1
        local filters = SC.db and SC.db.filters or {}
        local mount = filters.mounts or {}
        if level == 1 then
            local function addToggle(label, key, target)
                local info = UIDropDownMenu_CreateInfo()
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.text = label
                info.checked = function()
                    local values = target and mount or filters
                    return values[key] and true or false
                end
                info.func = function(_, _, _, checked)
                    local values = target and mount or filters
                    values[key] = checked == nil and not values[key] or checked and true or false
                    page:Refresh()
                    page:SyncFilters()
                    refreshFilterMenu()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            addToggle("已收集", "collected")
            addToggle("未收集", "uncollected")
            addToggle("仅显示偏好", "favorites")
            addToggle("显示当前不可用", "unusable", true)

            local title = UIDropDownMenu_CreateInfo()
            title.text = "坐骑类型"
            title.isTitle = true
            title.notCheckable = true
            UIDropDownMenu_AddButton(title, level)
            addToggle("地面", "ground", true)
            addToggle("飞行", "flying", true)
            addToggle("水栖", "aquatic", true)

            if UIDropDownMenu_AddSpace then pcall(UIDropDownMenu_AddSpace, level) end

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
                local state = mountFilters()
                state.hiddenSources = {}
                page:Refresh()
                page:SyncFilters()
                refreshFilterMenu()
            end
            UIDropDownMenu_AddButton(all, level)

            local none = UIDropDownMenu_CreateInfo()
            none.notCheckable = true
            none.keepShownOnClick = true
            none.text = "隐藏全部来源"
            none.func = function()
                local state = mountFilters()
                state.hiddenSources = {}
                local sourceOrder = Catalog.GetMountSourceOrder and Catalog.GetMountSourceOrder()
                    or Catalog.MOUNT_SOURCE_ORDER
                    or {}
                for _, sourceType in ipairs(sourceOrder) do
                    state.hiddenSources[sourceType] = true
                end
                page:Refresh()
                page:SyncFilters()
                refreshFilterMenu()
            end
            UIDropDownMenu_AddButton(none, level)

            local sourceOrder = Catalog.GetMountSourceOrder and Catalog.GetMountSourceOrder()
                or Catalog.MOUNT_SOURCE_ORDER
                or {}
            for _, sourceType in ipairs(sourceOrder) do
                local info = UIDropDownMenu_CreateInfo()
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.text = Catalog.MountSourceLabel(sourceType)
                info.checked = function()
                    local state = mountFilters()
                    return not state.hiddenSources[sourceType]
                end
                info.func = function(_, _, _, checked)
                    local state = mountFilters()
                    if checked == nil then checked = not state.hiddenSources[sourceType] end
                    state.hiddenSources[sourceType] = checked and nil or true
                    page:Refresh()
                    page:SyncFilters()
                    refreshFilterMenu()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end

    -- WoW 3.3.5a's UIDropDownMenu_Initialize concatenates GetName()
    -- with the template region suffixes when displayMode is "MENU".  An
    -- anonymous frame therefore fails at FrameXML/UIDropDownMenu.lua:75.
    -- Reuse the named frame as well, so a later page-construction error does
    -- not create a second global dropdown while the journal singleton is
    -- still incomplete.
    filterMenu = _G.SoloCollectionsMountFilterMenu
    if not filterMenu then
        filterMenu = CreateFrame(
            "Frame",
            "SoloCollectionsMountFilterMenu",
            UIParent,
            "UIDropDownMenuTemplate"
        )
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(filterMenu, filterMenuInit, "MENU")
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
        favoriteInfo.text = record.favorite and "取消偏好" or "设为偏好"
        favoriteInfo.notCheckable = 1
        favoriteInfo.func = function()
            setFavoriteRecord(record)
        end
        if not record.collected then
            favoriteInfo.disabled = 1
            favoriteInfo.tooltipTitle = "尚未收集"
            favoriteInfo.tooltipText = "未收集的坐骑不能设为偏好。"
        elseif not SC.Bridge or SC.Bridge.GetCategoryState(16) ~= "Ready" then
            favoriteInfo.disabled = 1
            favoriteInfo.tooltipTitle = "偏好正在同步"
            favoriteInfo.tooltipText = "服务端偏好状态就绪后才能修改。"
        end
        UIDropDownMenu_AddButton(favoriteInfo)
    end, "MENU")

    local function requestModel(record, force)
        page.scModelGeneration = (page.scModelGeneration or 0) + 1
        local generation = page.scModelGeneration
        clearModelInteraction()
        resetModelState()
        model:ClearModel()
        unavailable:Hide()

        local bridgeState = SC.Bridge and SC.Bridge.GetCategoryState
            and SC.Bridge.GetCategoryState(10)
            or "Disconnected"
        if not force and bridgeState ~= "Ready" then
            page.scPendingModelId = record and record.id or nil
            if bridgeState == "Loading" or bridgeState == "Disconnected" then
                unavailable:SetText("正在连接收藏服务…")
            elseif bridgeState == "Mismatch" then
                unavailable:SetText("坐骑目录版本不匹配")
            else
                unavailable:SetText("坐骑模型服务不可用")
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
                SC.Bridge.RequestCreaturePreview(10, record.id, function(ok, reason)
                    if page.scModelGeneration == generation then done(ok, reason) end
                end)
            end,
            onReady = function()
                if page.scModelGeneration ~= generation then return end
                page.scPendingModelId = nil
                model.scBaseScale = getNativeModelScale()
                model.scZoom = DEFAULT_MODEL_SCALE
                page.scModelReady = true
                unavailable:Hide(); rotateHint:Show()
            end,
            onUnavailable = function(reason)
                if page.scModelGeneration ~= generation then return end
                model.scUnavailableReason = reason
                if reason == "BRIDGE_UNAVAILABLE" or reason == "TIMEOUT" then
                    page.scPendingModelId = record.id
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
        name:SetText(record.name or "未知坐骑")
        local acquisition = record.acquisitionClass
        local acquisitionText = acquisition == "LEGACY" and "|cffffd200获取类型：|r绝版|n"
            or acquisition == "PROMOTION" and "|cffffd200获取类型：|r促销|n"
            or ""
        source:SetText(acquisitionText .. "来源：" .. (record.source or "未知"))
        local descriptionText = Catalog.ResolveMountDescription and Catalog.ResolveMountDescription(record)
        if descriptionText and descriptionText ~= "" then
            description:SetText(descriptionText)
            description:Show()
        else
            description:SetText("")
            description:Hide()
            if Catalog.RecordMountDescriptionGap then Catalog.RecordMountDescriptionGap(record) end
        end
        if record.collected then
            collectionState:SetText("已收集")
            collectionState:SetTextColor(0.38, 0.9, 0.30)
            if SC.Bridge and SC.Bridge.GetCategoryState(16) == "Ready" then
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
            favorite:SetText("设为偏好")
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

    local function scrollSelectionIntoView(records, selectedId)
        if not selectedId then return end
        local selectedIndex
        for index, record in ipairs(records) do
            if record.id == selectedId then
                selectedIndex = index
                break
            end
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
        row.scDragButton:SetScript("OnDragStart", function(self)
            pickupMountCompanion(row.scRecord)
        end)
        row.scDragButton:SetScript("OnClick", function(self, button)
            local record = row.scRecord
            if button == "RightButton" then
                openContextMenu(self, record)
            elseif IsShiftKeyDown and IsShiftKeyDown() then
                insertMountLink(record)
            elseif record then
                selectRecord(record)
            end
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
        description:Hide()
        collectionState:SetText("")
        favorite:SetText("设为偏好")
        favorite:Disable()
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
        if not SC.db or SC.db.mainTab ~= "MOUNTS" then
            return
        end
        mountFilters()
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
            scrollSelectionIntoView(records, selectedRecord and selectedRecord.id or records[1].id)
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
        setFavoriteRecord(record)
    end)

    reset:SetScript("OnClick", function()
        model.rotation = DEFAULT_ROTATION
        if presenter and presenter.ResetView then presenter:ResetView()
        elseif page.scSelectedRecord then requestModel(page.scSelectedRecord) end
    end)

    summon:SetScript("OnClick", function() summonRecord(page.scSelectedRecord) end)

    randomSummon:SetScript("OnClick", function()
        summonRandomMount()
    end)
    randomSummon:SetScript("OnDragStart", function()
        pickupRandomMountSpell()
    end)
    randomSummon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("召唤随机坐骑", 1, 0.82, 0.18)
        GameTooltip:AddLine("优先从已收集的偏好坐骑中随机选择；没有偏好时从全部已收集坐骑中选择。", 1, 1, 1, true)
        GameTooltip:AddLine("拖动到动作条可放置真实随机坐骑技能。", 0.35, 0.85, 1, true)
        local bridgeState = SC.Bridge and SC.Bridge.GetCategoryState and SC.Bridge.GetCategoryState(10)
        if bridgeState ~= "Ready" then
            GameTooltip:AddLine("收藏状态正在同步。", 1, 0.45, 0.2, true)
        elseif not findRandomMountSpellBookSlot() then
            GameTooltip:AddLine("随机坐骑技能正在同步。", 1, 0.45, 0.2, true)
        end
        GameTooltip:Show()
    end)
    randomSummon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if SC.Bridge and type(SC.Bridge.RegisterStateListener) == "function" then
        page.scBridgeStateListener = SC.Bridge.RegisterStateListener(function(_, typeId)
            if typeId ~= nil and tonumber(typeId) ~= 10 then return end
            if not page:IsShown() or not page.scSelectedRecord then return end
            local state = SC.Bridge.GetCategoryState and SC.Bridge.GetCategoryState(10)
            if state == "Ready" and page.scPendingModelId == page.scSelectedRecord.id then
                requestModel(page.scSelectedRecord, true)
            elseif page.scPendingModelId == page.scSelectedRecord.id and state == "Mismatch" then
                unavailable:SetText("坐骑目录版本不匹配")
                unavailable:Show(); rotateHint:Hide()
            end
        end)
    end

    infoButton:SetScript("OnClick", function(self, button)
        local record = page.scSelectedRecord
        if button == "RightButton" then
            openContextMenu(self, record)
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            insertMountLink(record)
        else
            summonRecord(record)
        end
    end)
    infoButton:SetScript("OnDragStart", function()
        pickupMountCompanion(page.scSelectedRecord)
    end)

    page:RegisterEvent("COMPANION_LEARNED")
    page:RegisterEvent("COMPANION_UNLEARNED")
    page:RegisterEvent("COMPANION_UPDATE")
    page:RegisterEvent("SPELLS_CHANGED")
    page:RegisterEvent("LEARNED_SPELL_IN_TAB")
    page:SetScript("OnEvent", function()
        rebuildCompanionIndex()
    end)
    rebuildCompanionIndex()

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
        self.scPendingModelId = nil
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
    page.scFilterMenu = filterMenu
    page.scEmpty = empty
    return page
end
