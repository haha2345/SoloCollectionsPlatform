local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local ITEM_COLUMNS = 6
local ITEM_PAGE_SIZE = 18
local ITEM_WIDTH = 78
local ITEM_HEIGHT = 104
local ITEM_GAP_X = 16
local ITEM_GAP_Y = 24
local SET_COLUMNS = 4
local SET_PAGE_SIZE = 8
local SET_WIDTH = 129
local SET_HEIGHT = 186
local SET_GAP_X = 13
local SET_GAP_Y = 14

local function copyFilters(slotKey)
    local filters = {}
    for key, value in pairs((SC.db and SC.db.filters) or {}) do filters[key] = value end
    filters.slot = slotKey
    return filters
end

local function selectedVariant(record)
    if type(record) ~= "table" then return nil end
    if type(record.selectedVariant) == "table" then return record.selectedVariant end
    local requested = tonumber(record.selectedVariantOrdinal)
    local fallback
    for _, variant in ipairs(record.variants or {}) do
        if not fallback or variant.isDefault then fallback = variant end
        if requested and tonumber(variant.variantOrdinal) == requested then return variant end
    end
    return fallback
end

local function setItemStrings(record)
    local strings, seenSlots = {}, {}
    local variant = selectedVariant(record)
    for _, member in ipairs((variant and variant.members) or {}) do
        local slotKey = member.slotKey or member.memberKey or ("member-" .. tostring(#strings + 1))
        local itemId = tonumber(member.previewSourceItemId)
        for _, sourceItemId in ipairs(member.sourceItemIds or {}) do
            sourceItemId = tonumber(sourceItemId)
            if sourceItemId and (not itemId or sourceItemId < itemId) then itemId = sourceItemId end
        end
        if itemId and not seenSlots[slotKey] then
            seenSlots[slotKey] = true
            strings[#strings + 1] = "item:" .. tostring(itemId)
        end
    end
    return strings
end

local function setProgress(category, filters)
    if not (UI.CollectionsFrame and UI.CollectionsFrame.scProgress) then return end
    local collected, total = SC.Catalog.GetProgress(category, filters)
    UI.CollectionsFrame.scProgress:SetProgress(collected, total)
end

function Lab.CreateSources(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host.mode = "ITEMS"
    host.itemPage = 1
    host.setPage = 1
    host.itemCards = {}
    host.setCards = {}
    local itemRenderer = SC.WardrobeUI and SC.WardrobeUI.ItemCardRenderer

    local body = CreateFrame("Frame", nil, host)
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -60)
    body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -6, 5)
    body:SetFrameLevel(host:GetFrameLevel() + 1)
    local bodyInset = UI.EzCollections:ApplyInset(body)
    UI.EzCollections:AddShadowOverlay(body)

    local itemsView = CreateFrame("Frame", nil, host)
    itemsView:SetAllPoints(host)
    itemsView:SetFrameLevel(host:GetFrameLevel() + 5)
    itemsView:EnableMouseWheel(true)

    local setsView = CreateFrame("Frame", nil, host)
    setsView:SetAllPoints(host)
    setsView:SetFrameLevel(host:GetFrameLevel() + 5)
    setsView:EnableMouseWheel(true)
    setsView:Hide()

    local itemTab = UI.CreateTopSubTab(host, "物品", function() host:SetMode("ITEMS") end)
    itemTab:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -28)
    itemTab:SetFrameLevel(host:GetFrameLevel() + 20)
    local setTab = UI.CreateTopSubTab(host, "套装", function() host:SetMode("SETS") end)
    setTab:SetPoint("LEFT", itemTab, "RIGHT", 0, 0)
    setTab:SetFrameLevel(host:GetFrameLevel() + 20)

    local function scrollItems(delta)
        if not delta or delta == 0 then return end
        if delta > 0 then
            host.itemPage = math.max(1, host.itemPage - 1)
        else
            host.itemPage = math.min(host.itemTotalPages or 1, host.itemPage + 1)
        end
        host:Refresh()
    end

    local function scrollSets(delta)
        if not delta or delta == 0 then return end
        if delta > 0 then
            host.setPage = math.max(1, host.setPage - 1)
        else
            host.setPage = math.min(host.setTotalPages or 1, host.setPage + 1)
        end
        host:Refresh()
    end

    itemsView:SetScript("OnMouseWheel", function(_, delta) scrollItems(delta) end)
    setsView:SetScript("OnMouseWheel", function(_, delta) scrollSets(delta) end)

    for index = 1, ITEM_PAGE_SIZE do
        local column = (index - 1) % ITEM_COLUMNS
        local row = math.floor((index - 1) / ITEM_COLUMNS)
        local card = CreateFrame("Frame", nil, itemsView)
        card:SetWidth(ITEM_WIDTH)
        card:SetHeight(ITEM_HEIGHT)
        card:SetPoint(
            "TOPLEFT", itemsView, "TOPLEFT",
            57 + column * (ITEM_WIDTH + ITEM_GAP_X),
            -71 - row * (ITEM_HEIGHT + ITEM_GAP_Y)
        )
        local background = card:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(card)
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0, 0, 0, 1)

        local model = CreateFrame("DressUpModel", nil, card)
        model:SetAllPoints(card)
        model:EnableMouse(false)
        local objectModel = CreateFrame("PlayerModel", nil, card)
        objectModel:SetAllPoints(card)
        objectModel:EnableMouse(false)
        objectModel:Hide()

        local unavailable = CreateFrame("Frame", nil, card)
        unavailable:SetAllPoints(card)
        unavailable:SetFrameLevel(model:GetFrameLevel() + 1)
        local unavailableIcon = unavailable:CreateTexture(nil, "ARTWORK")
        unavailableIcon:SetWidth(32)
        unavailableIcon:SetHeight(32)
        unavailableIcon:SetPoint("CENTER", unavailable, "CENTER", 0, 9)
        local unavailableText = unavailable:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        unavailableText:SetPoint("TOPLEFT", unavailable, "TOPLEFT", 4, -68)
        unavailableText:SetPoint("TOPRIGHT", unavailable, "TOPRIGHT", -4, -68)
        unavailableText:SetJustifyH("CENTER")
        unavailableText:SetText("资源未就绪")
        unavailable:Hide()

        local hit = CreateFrame("Button", nil, card)
        hit:SetAllPoints(card)
        hit:SetFrameLevel(model:GetFrameLevel() + 2)
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hit:EnableMouseWheel(true)
        local border, selected, favorite = UI.EzCollections:CreateWardrobeItemChrome(hit)

        model.scCard = card
        model.scObjectModel = objectModel
        model.scUnavailable = unavailable
        model.scUnavailableIcon = unavailableIcon
        model.scUnavailableText = unavailableText
        if itemRenderer then itemRenderer:Attach(model, objectModel) end

        function card:SetRecord(record)
            local changed = not record or self.scRecordId ~= record.id
            if changed then self.scGeneration = (self.scGeneration or 0) + 1 end
            self.scRecord = record
            if itemRenderer then itemRenderer:Present(model, record, self.scGeneration or 1) end
            if not record then
                self.scRecordId = nil
                if not itemRenderer then
                    model:ClearModel()
                    objectModel:ClearModel()
                    self:Hide()
                end
                return
            end
            self:Show()
            if not itemRenderer then model:Show() end
            self.scRecordId = record.id
            border:SetCollected(record.collected)
            model:SetAlpha(record.collected and 1 or 0.48)
            objectModel:SetAlpha(record.collected and 1 or 0.48)
            if record.favorite then favorite:Show() else favorite:Hide() end
        end

        function card:ClearRenderer()
            self.scGeneration = (self.scGeneration or 0) + 1
            self.scRecord = nil
            self.scRecordId = nil
            if itemRenderer then
                itemRenderer:Clear(model, self.scGeneration)
            else
                model:ClearModel()
                objectModel:ClearModel()
                self:Hide()
            end
        end

        function card:SetSelected(value)
            if value then selected:Show() else selected:Hide() end
        end

        hit:SetScript("OnClick", function(_, mouseButton)
            local record = card.scRecord
            if not record then return end
            if mouseButton == "RightButton" then
                SC.Catalog.ToggleDemoFavorite("APPEARANCES", record.id)
                host:Refresh()
            else
                state:SetDraft(state.selectedSlot, record)
            end
        end)
        hit:SetScript("OnMouseWheel", function(_, delta) scrollItems(delta) end)
        hit:SetScript("OnEnter", function(self)
            local record = card.scRecord
            if not record then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(record.name or "未知外观", 1, 0.82, 0.18)
            GameTooltip:AddLine(record.collected and "已收藏" or "未收藏 · 仅可预览", record.collected and 0.4 or 0.7, record.collected and 1 or 0.7, 0.4)
            GameTooltip:AddLine("左键写入所选槽位草稿 · 右键偏好", 0.75, 0.72, 0.66)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

        card.scModel = model
        card.scObjectModel = objectModel
        card.scHitFrame = hit
        card.scBorder = border
        card.scSelected = selected
        card.scFavorite = favorite
        card:Hide()
        host.itemCards[index] = card
    end

    for index = 1, SET_PAGE_SIZE do
        local column = (index - 1) % SET_COLUMNS
        local row = math.floor((index - 1) / SET_COLUMNS)
        local card = CreateFrame("Frame", nil, setsView)
        card:SetWidth(SET_WIDTH)
        card:SetHeight(SET_HEIGHT)
        card:SetPoint(
            "TOPLEFT", setsView, "TOPLEFT",
            50 + column * (SET_WIDTH + SET_GAP_X),
            -50 - row * (SET_HEIGHT + SET_GAP_Y)
        )
        local background = card:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(card)
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0, 0, 0, 1)

        local model = CreateFrame("DressUpModel", nil, card)
        model:SetAllPoints(card)
        model:EnableMouse(false)
        local presenter = SC.ModelProvider.Create("DRESSUP", model, {
            panelCheck = function()
                return host:IsShown() and host.mode == "SETS" and card:IsShown()
            end,
        })

        local hit = CreateFrame("Button", nil, card)
        hit:SetAllPoints(card)
        hit:SetFrameLevel(model:GetFrameLevel() + 2)
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hit:EnableMouseWheel(true)
        local border, selected, favorite = UI.EzCollections:CreateWardrobeSetChrome(hit)

        function card:SetRecord(record)
            local changed = not record or self.scRecordId ~= record.id
            self.scRecord = record
            if not record then
                self.scRecordId = nil
                presenter:Clear("LAB_SET_EMPTY")
                model:ClearModel()
                self:Hide()
                return
            end
            self:Show()
            model:Show()
            if changed then
                self.scGeneration = (self.scGeneration or 0) + 1
                local generation = self.scGeneration
                presenter:Clear("LAB_SET_REPLACED")
                presenter:Present({
                    unit = "player",
                    undress = true,
                    settleTicks = 2,
                    items = setItemStrings(record),
                    onReady = function()
                        if card.scGeneration == generation and card.scRecord and card.scRecord.id == record.id then
                            card.scReadyGeneration = generation
                        end
                    end,
                })
                self.scRecordId = record.id
            end
            border:SetCollected(record.collected)
            model:SetAlpha(record.collected and 1 or 0.48)
            if record.favorite then favorite:Show() else favorite:Hide() end
        end

        function card:SetSelected(value)
            if value then selected:Show() else selected:Hide() end
        end

        hit:SetScript("OnClick", function(_, mouseButton)
            local record = card.scRecord
            if not record then return end
            if mouseButton == "RightButton" then
                SC.Catalog.ToggleDemoFavorite("SETS", record.id)
                host:Refresh()
            else
                state:SetPreset(record)
            end
        end)
        hit:SetScript("OnMouseWheel", function(_, delta) scrollSets(delta) end)
        hit:SetScript("OnEnter", function(self)
            local record = card.scRecord
            if not record then return end
            local owned = tonumber(record.collectedCount) or 0
            local required = tonumber(record.requiredCount) or #(record.itemIds or {})
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(record.name or "未知套装", 1, 0.82, 0.18)
            GameTooltip:AddLine("收集进度：" .. owned .. " / " .. required, 0.45, 0.90, 0.34)
            GameTooltip:AddLine("左键加载本地套装预设 · 右键偏好", 0.75, 0.72, 0.66)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

        card.scModel = model
        card.scPresenter = presenter
        card.scHitFrame = hit
        card.scBorder = border
        card.scSelected = selected
        card.scFavorite = favorite
        card:Hide()
        host.setCards[index] = card
    end

    local itemControls = UI.CreatePageControls(itemsView, function()
        host.itemPage = math.max(1, host.itemPage - 1)
        host:Refresh()
    end, function()
        host.itemPage = math.min(host.itemTotalPages or 1, host.itemPage + 1)
        host:Refresh()
    end)
    itemControls:SetPoint("BOTTOM", itemsView, "BOTTOM", 22, 38)

    local setControls = UI.CreatePageControls(setsView, function()
        host.setPage = math.max(1, host.setPage - 1)
        host:Refresh()
    end, function()
        host.setPage = math.min(host.setTotalPages or 1, host.setPage + 1)
        host:Refresh()
    end)
    setControls:SetPoint("BOTTOM", setsView, "BOTTOM", 22, 38)

    local applySet = CreateFrame("Button", nil, setsView, "UIPanelButtonTemplate")
    applySet:SetWidth(112)
    applySet:SetHeight(22)
    applySet:SetPoint("BOTTOMRIGHT", setsView, "BOTTOMRIGHT", -10, 10)
    applySet:SetText("应用套装预设")
    applySet:SetScript("OnClick", function() state:BeginApplySet() end)

    local selectedSetName = setsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedSetName:SetPoint("BOTTOMLEFT", setsView, "BOTTOMLEFT", 16, 16)
    selectedSetName:SetWidth(210)
    selectedSetName:SetJustifyH("LEFT")

    local itemEmpty = UI.CreateEmptyState(itemsView, "没有符合条件的外观")
    itemEmpty:SetPoint("CENTER", itemsView, "CENTER", 0, 10)
    itemEmpty:Hide()
    local setEmpty = UI.CreateEmptyState(setsView, "没有符合条件的套装")
    setEmpty:SetPoint("CENTER", setsView, "CENTER", 0, 10)
    setEmpty:Hide()

    function host:SetMode(mode)
        mode = mode == "SETS" and "SETS" or "ITEMS"
        if self.mode ~= mode then
            self.mode = mode
            if mode == "ITEMS" then self.itemPage = 1 else self.setPage = 1 end
        end
        itemTab:SetSelected(mode == "ITEMS")
        setTab:SetSelected(mode == "SETS")
        if mode == "ITEMS" then
            itemsView:Show()
            setsView:Hide()
            for _, card in ipairs(self.setCards) do
                card.scPresenter:Clear("LAB_SET_VIEW_HIDDEN")
                card.scRecordId = nil
            end
        else
            itemsView:Hide()
            setsView:Show()
            for _, card in ipairs(self.itemCards) do
                card:ClearRenderer()
            end
        end
        self:Refresh()
    end

    function host:Refresh()
        local query = (SC.db and SC.db.query) or ""
        local filters = copyFilters(state.selectedSlot)
        local request = state.requestState or {}
        if self.mode == "SETS" then
            local records, page, totalPages = SC.Catalog.Query("SETS", query, filters, self.setPage, SET_PAGE_SIZE)
            self.setPage, self.setTotalPages = page, totalPages
            setControls:SetPage(page, totalPages)
            for index, card in ipairs(self.setCards) do
                local record = records[index]
                if record and state.presetRecord and record.id == state.presetRecord.id then
                    state.presetRecord = record
                end
                card:SetRecord(record)
                card:SetSelected(record and state.presetRecord and record.id == state.presetRecord.id)
            end
            if #records == 0 then
                UI.ShowEmptyState(setEmpty, host, "没有符合条件的套装", "调整搜索、职业或收藏过滤后再试。")
            else
                UI.HideEmptyState(setEmpty)
            end
            if state.presetRecord then
                selectedSetName:SetText(state.presetRecord.name or ("套装 " .. tostring(state.presetRecord.id)))
            else
                selectedSetName:SetText("选择套装以建立本地预设")
            end
            if state.presetRecord and state.presetRecord.collected
                and request.status ~= "REQUESTING" and request.status ~= "WAITING_STATE" then
                applySet:Enable()
            else
                applySet:Disable()
            end
            setProgress("SETS", filters)
        else
            local records, page, totalPages = SC.Catalog.Query(
                "APPEARANCES", query, filters, self.itemPage, ITEM_PAGE_SIZE
            )
            self.itemPage, self.itemTotalPages = page, totalPages
            itemControls:SetPage(page, totalPages)
            local selected = state.draftBySlot[state.selectedSlot]
            for index, card in ipairs(self.itemCards) do
                local record = records[index]
                if record and selected and record.id == selected.id then
                    selected = record
                    state.draftBySlot[state.selectedSlot] = record
                end
                card:SetRecord(record)
                card:SetSelected(record and selected and record.id == selected.id)
            end
            if #records == 0 then
                UI.ShowEmptyState(itemEmpty, host, "没有符合条件的外观", "调整搜索、来源或收藏过滤后再试。")
            else
                UI.HideEmptyState(itemEmpty)
            end
            setProgress("APPEARANCES", filters)
        end
    end

    function host:ClearPresenters(reason)
        for _, card in ipairs(self.itemCards) do
            card:ClearRenderer()
        end
        for _, card in ipairs(self.setCards) do
            card.scPresenter:Clear(reason or "LAB_HIDDEN")
            card.scRecordId = nil
        end
    end

    host.scBody = body
    host.scBodyBackground = bodyInset.background
    host.scItemsView = itemsView
    host.scSetsView = setsView
    host.scItemTab = itemTab
    host.scSetTab = setTab
    host.scItemControls = itemControls
    host.scSetControls = setControls
    host.scApplySet = applySet
    host.scSelectedSetName = selectedSetName
    itemTab:SetSelected(true)
    setTab:SetSelected(false)
    return host
end
