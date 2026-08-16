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
local ITEM_START_X = -235
local ITEM_START_Y = -71
local SET_COLUMNS = 4
local SET_PAGE_SIZE = 8
local SET_WIDTH = 129
local SET_HEIGHT = 186
local SET_GAP_X = 13
local SET_GAP_Y = 14
local SET_START_X = 50
local SET_START_Y = 50

local function anchorModelToCard(model, card, width, height)
    model:ClearAllPoints()
    model:SetWidth(width)
    model:SetHeight(height)
    model:SetPoint("CENTER", card, "CENTER", 0, 0)
end

local function copyFilters(slotKey)
    local filters = {}
    for key, value in pairs((SC.db and SC.db.filters) or {}) do filters[key] = value end
    filters.slot = slotKey
    -- Transmog uses journal collected/uncollected, but not the favorites-only toggle.
    filters.favorites = false
    if SC.Catalog and SC.Catalog.IsWeaponFilterSlot and SC.Catalog.IsWeaponFilterSlot(slotKey) then
        SC.Catalog.EnsureWeaponTypeForSlot(filters, slotKey)
        if SC.db and SC.db.filters then
            SC.db.filters.weaponType = filters.weaponType
        end
    end
    return filters
end

local function copySetFilters()
    local filters = {}
    for key, value in pairs((SC.db and SC.db.filters) or {}) do filters[key] = value end
    filters.slot = "ALL"
    filters.favorites = false
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
    local frame = (UI.TransmogFrame and UI.TransmogFrame:IsShown() and UI.TransmogFrame)
        or UI.CollectionsFrame
    if not (frame and frame.scProgress) then return end
    local collected, total = SC.Catalog.GetProgress(category, filters)
    frame.scProgress:SetProgress(collected, total)
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
    -- Explicit size: two-point anchors often report GetWidth()==0 on 3.3.5
    -- before first layout, which leaves the marble tile at native 256px.
    body:SetWidth(652)
    body:SetHeight(541)
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -60)
    body:SetFrameLevel(host:GetFrameLevel() + 1)
    local bodyInset = UI.EzCollections:ApplyInset(body)
    UI.EzCollections:AddShadowOverlay(body)
    local function layoutBody()
        local width = host:GetWidth() or 0
        local height = host:GetHeight() or 0
        if width < 1 then width = 662 end
        if height < 1 then height = 606 end
        body:SetWidth(math.max(1, width - 10))
        body:SetHeight(math.max(1, height - 65))
        if UI.EzCollections.UpdateInset then UI.EzCollections:UpdateInset(body) end
    end
    host:HookScript("OnSizeChanged", layoutBody)
    host:HookScript("OnShow", layoutBody)
    layoutBody()

    local itemsView = CreateFrame("Frame", nil, host)
    itemsView:SetAllPoints(body)
    itemsView:SetFrameLevel(host:GetFrameLevel() + 5)
    itemsView:EnableMouseWheel(true)

    local setsView = CreateFrame("Frame", nil, host)
    setsView:SetAllPoints(body)
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
            "TOP", itemsView, "TOP",
            ITEM_START_X + column * (ITEM_WIDTH + ITEM_GAP_X),
            ITEM_START_Y - row * (ITEM_HEIGHT + ITEM_GAP_Y)
        )
        local background = card:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(card)
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0, 0, 0, 1)

        local model = CreateFrame("DressUpModel", nil, card)
        anchorModelToCard(model, card, ITEM_WIDTH, ITEM_HEIGHT)
        model:EnableMouse(false)
        local objectModel = CreateFrame("PlayerModel", nil, card)
        anchorModelToCard(objectModel, card, ITEM_WIDTH, ITEM_HEIGHT)
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

        -- DressUpModel Present() resets alpha to 1, so ownership cannot live on
        -- the actor. Keep it on the hit frame, same as the journal item cards.
        local uncollectedShade = hit:CreateTexture(nil, "BACKGROUND")
        uncollectedShade:SetTexture("Interface\\Buttons\\WHITE8X8")
        uncollectedShade:SetAllPoints(hit)
        uncollectedShade:SetVertexColor(0, 0, 0, 0.5)
        uncollectedShade:Hide()

        local uncollectedBadge = CreateFrame("Frame", nil, hit)
        uncollectedBadge:SetWidth(58)
        uncollectedBadge:SetHeight(15)
        uncollectedBadge:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -4, -4)
        uncollectedBadge:SetFrameLevel(hit:GetFrameLevel() + 3)
        local uncollectedBadgeBg = uncollectedBadge:CreateTexture(nil, "BACKGROUND")
        uncollectedBadgeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        uncollectedBadgeBg:SetAllPoints(uncollectedBadge)
        uncollectedBadgeBg:SetVertexColor(0.02, 0.02, 0.02, 0.78)
        local uncollectedBadgeText = uncollectedBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        uncollectedBadgeText:SetAllPoints(uncollectedBadge)
        uncollectedBadgeText:SetJustifyH("CENTER")
        uncollectedBadgeText:SetText("未收集")
        uncollectedBadgeText:SetTextColor(0.72, 0.73, 0.74)
        uncollectedBadge:Hide()

        local collectedMark = CreateFrame("Frame", nil, hit)
        collectedMark:SetWidth(20)
        collectedMark:SetHeight(20)
        collectedMark:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -3, -3)
        collectedMark:SetFrameLevel(hit:GetFrameLevel() + 3)
        local collectedIcon = collectedMark:CreateTexture(nil, "OVERLAY")
        collectedIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        collectedIcon:SetAllPoints(collectedMark)
        collectedMark:Hide()

        local function applyOwnership(record)
            if not record or (Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record)) then
                uncollectedShade:Hide()
                uncollectedBadge:Hide()
                collectedMark:Hide()
                return
            end
            border:SetCollected(record.collected)
            if record.collected then
                uncollectedShade:Hide()
                uncollectedBadge:Hide()
                collectedMark:Show()
            else
                uncollectedShade:Show()
                uncollectedBadge:Show()
                collectedMark:Hide()
            end
        end

        model.scCard = card
        model.scObjectModel = objectModel
        model.scUnavailable = unavailable
        model.scUnavailableIcon = unavailableIcon
        model.scUnavailableText = unavailableText
        if itemRenderer then itemRenderer:Attach(model, objectModel) end

        local function stopCardModels()
            local lifecycle = model.scEzWardrobeLifecycle
            if lifecycle then
                lifecycle.generation = (lifecycle.generation or 0) + 1
                lifecycle.activeGeneration = lifecycle.generation
                lifecycle.record = nil
                lifecycle.recordKey = nil
                lifecycle.pendingItemRender = nil
                lifecycle.transmorpherSetup = nil
                lifecycle.weaponDescriptor = nil
                model:SetScript("OnUpdate", nil)
            end
            if model.ClearModel then model:ClearModel() end
            model:Hide()
            if objectModel.ClearModel then objectModel:ClearModel() end
            objectModel:Hide()
            if unavailable then unavailable:Hide() end
        end

        function card:SetRecord(record)
            local changed = not record or self.scRecordId ~= record.id
            if changed then self.scGeneration = (self.scGeneration or 0) + 1 end
            self.scRecord = record
            if not record then
                self.scRecordId = nil
                applyOwnership(nil)
                if hit.SetHideVisual then hit:SetHideVisual(false) end
                if itemRenderer then
                    itemRenderer:Clear(model, self.scGeneration)
                else
                    model:ClearModel()
                    objectModel:ClearModel()
                    self:Hide()
                end
                return
            end
            self:Show()
            self.scRecordId = record.id
            if Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record) then
                -- ItemCardRenderer:Clear also hides the card frame. Keep the
                -- empty collected tile visible and only stop the 3D presenter.
                stopCardModels()
                border:SetCollected(true)
                applyOwnership(record)
                if favorite then favorite:Hide() end
                if hit.SetHideVisual then hit:SetHideVisual(true) end
                return
            end
            if hit.SetHideVisual then hit:SetHideVisual(false) end
            if itemRenderer then itemRenderer:Present(model, record, self.scGeneration or 1) end
            if not itemRenderer then model:Show() end
            applyOwnership(record)
            if record.favorite then favorite:Show() else favorite:Hide() end
        end

        function card:ClearRenderer()
            self.scGeneration = (self.scGeneration or 0) + 1
            self.scRecord = nil
            self.scRecordId = nil
            applyOwnership(nil)
            if hit.SetHideVisual then hit:SetHideVisual(false) end
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
            if Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record) then
                if mouseButton ~= "RightButton" then
                    state:SetDraft(state.selectedSlot, record)
                end
                return
            end
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
            if Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record) then
                GameTooltip:AddLine("从预览中隐藏该部位外观。", 0.72, 0.72, 0.72, true)
                GameTooltip:AddLine("仅本地预览，当前不能应用到装备。", 1, 0.35, 0.25, true)
            else
                GameTooltip:AddLine(record.collected and "已收藏" or "未收藏 · 仅可预览", record.collected and 0.4 or 0.7, record.collected and 1 or 0.7, 0.4)
                GameTooltip:AddLine("左键写入所选槽位草稿 · 右键偏好", 0.75, 0.72, 0.66)
            end
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
            SET_START_X + column * (SET_WIDTH + SET_GAP_X),
            -SET_START_Y - row * (SET_HEIGHT + SET_GAP_Y)
        )
        local background = card:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(card)
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0, 0, 0, 1)

        local model = CreateFrame("DressUpModel", nil, card)
        anchorModelToCard(model, card, SET_WIDTH, SET_HEIGHT)
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

        local uncollectedShade = hit:CreateTexture(nil, "BACKGROUND")
        uncollectedShade:SetTexture("Interface\\Buttons\\WHITE8X8")
        uncollectedShade:SetAllPoints(hit)
        uncollectedShade:SetVertexColor(0, 0, 0, 0.5)
        uncollectedShade:Hide()

        local uncollectedBadge = CreateFrame("Frame", nil, hit)
        uncollectedBadge:SetWidth(58)
        uncollectedBadge:SetHeight(15)
        uncollectedBadge:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -4, -4)
        uncollectedBadge:SetFrameLevel(hit:GetFrameLevel() + 3)
        local uncollectedBadgeBg = uncollectedBadge:CreateTexture(nil, "BACKGROUND")
        uncollectedBadgeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        uncollectedBadgeBg:SetAllPoints(uncollectedBadge)
        uncollectedBadgeBg:SetVertexColor(0.02, 0.02, 0.02, 0.78)
        local uncollectedBadgeText = uncollectedBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        uncollectedBadgeText:SetAllPoints(uncollectedBadge)
        uncollectedBadgeText:SetJustifyH("CENTER")
        uncollectedBadgeText:SetText("未收集")
        uncollectedBadgeText:SetTextColor(0.72, 0.73, 0.74)
        uncollectedBadge:Hide()

        local collectedMark = CreateFrame("Frame", nil, hit)
        collectedMark:SetWidth(20)
        collectedMark:SetHeight(20)
        collectedMark:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -3, -3)
        collectedMark:SetFrameLevel(hit:GetFrameLevel() + 3)
        local collectedIcon = collectedMark:CreateTexture(nil, "OVERLAY")
        collectedIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        collectedIcon:SetAllPoints(collectedMark)
        collectedMark:Hide()

        local function applySetOwnership(record)
            if not record then
                uncollectedShade:Hide()
                uncollectedBadge:Hide()
                collectedMark:Hide()
                return
            end
            border:SetCollected(record.collected)
            if record.collected then
                uncollectedShade:Hide()
                uncollectedBadge:Hide()
                collectedMark:Show()
            else
                uncollectedShade:Show()
                uncollectedBadge:Show()
                collectedMark:Hide()
            end
        end

        function card:SetRecord(record)
            local changed = not record or self.scRecordId ~= record.id
            self.scRecord = record
            if not record then
                self.scRecordId = nil
                applySetOwnership(nil)
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
                            applySetOwnership(card.scRecord)
                        end
                    end,
                })
                self.scRecordId = record.id
            end
            applySetOwnership(record)
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
    applySet:SetText("应用套装")
    applySet:SetScript("OnClick", function() state:BeginApplySet() end)
    applySet:Hide()

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
        if UI.SyncTransmogFilterChrome then
            UI.SyncTransmogFilterChrome(mode, true)
        end
        self:Refresh()
    end

    function host:Refresh()
        if self.scFilterSlot ~= state.selectedSlot then
            self.scFilterSlot = state.selectedSlot
            self.itemPage = 1
        end
        local query = (SC.db and SC.db.query) or ""
        local filters = copyFilters(state.selectedSlot)
        local request = state.requestState or {}
        if UI.SyncTransmogWeaponDropDown then
            UI.SyncTransmogWeaponDropDown(state.selectedSlot, self.mode)
        end
        if self.mode == "SETS" then
            if UI.EnsureDefaultSetClassFilter then UI.EnsureDefaultSetClassFilter() end
            if UI.SyncTransmogClassDropDown then UI.SyncTransmogClassDropDown(self.mode) end
            filters = copySetFilters()
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
                selectedSetName:SetText("选择套装后可直接应用")
            end
            local canApplySet = false
            if state.GetSetApplyState then
                canApplySet = state:GetSetApplyState()
            elseif state.presetRecord and state.presetRecord.collected
                and request.status ~= "REQUESTING" then
                canApplySet = true
            end
            if canApplySet then applySet:Enable() else applySet:Disable() end
            setProgress("SETS", filters)
        else
            if UI.SyncTransmogClassDropDown then UI.SyncTransmogClassDropDown(self.mode) end
            local matches = SC.Catalog.QueryAll("APPEARANCES", query, filters)
            if Lab.CreateHideVisualRecord then
                table.insert(matches, 1, Lab.CreateHideVisualRecord(state.selectedSlot))
            end
            local total = #matches
            local totalPages = math.max(1, math.ceil(total / ITEM_PAGE_SIZE))
            self.itemPage = math.max(1, math.min(self.itemPage or 1, totalPages))
            local firstIndex = ((self.itemPage - 1) * ITEM_PAGE_SIZE) + 1
            local records = {}
            for index = firstIndex, math.min(total, firstIndex + ITEM_PAGE_SIZE - 1) do
                records[#records + 1] = matches[index]
            end
            local page = self.itemPage
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
