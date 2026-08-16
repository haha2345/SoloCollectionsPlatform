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

local SOURCE_KIND_LABELS = {
    drop = "掉落",
    quest = "任务",
    vendor = "商人",
    crafted = "专业",
}

local function appearanceSourceKindLabel(record)
    if not record or not record.sourceKind then return nil end
    local kinds = SC.Catalog and SC.Catalog.APPEARANCE_SOURCE_KINDS
    if kinds then
        for _, kind in ipairs(kinds) do
            if kind.key == record.sourceKind then
                return kind.label
            end
        end
    end
    return SOURCE_KIND_LABELS[record.sourceKind]
end

local function addAppearanceSourceTooltip(record)
    local kindLabel = appearanceSourceKindLabel(record)
    if kindLabel then
        GameTooltip:AddLine("来源类型：" .. kindLabel, 0.82, 0.78, 0.70)
    end
    local text = record.source
    if type(text) == "string" and text ~= "" and text ~= "获取方式未记录" then
        GameTooltip:AddLine(text, 0.94, 0.82, 0.58, true)
    end
end

local function usableSourceLabel(value)
    if type(value) ~= "string" or value == "" then return nil end
    if value == "NONE" or value == "UNKNOWN" then return nil end
    return value
end

local function adjustedDisplayIndex(index, numEntries, columns, key)
    if numEntries < 1 then return nil end
    if not index or index < 1 then index = 1 end
    if key == "LEFT" then
        index = index - 1
        if index < 1 then index = numEntries end
    elseif key == "RIGHT" then
        index = index + 1
        if index > numEntries then index = 1 end
    elseif key == "DOWN" then
        local newIndex = index + columns
        if newIndex > numEntries then
            index = index == numEntries and 1 or numEntries
        else
            index = newIndex
        end
    elseif key == "UP" then
        local newIndex = index - columns
        if newIndex < 1 then
            index = index == 1 and numEntries or 1
        else
            index = newIndex
        end
    end
    return index
end

local function recordCoversItem(record, itemId)
    itemId = tonumber(itemId)
    if not record or not itemId then return false end
    if tonumber(record.itemId) == itemId then return true end
    for _, sourceItemId in ipairs(record.itemIds or {}) do
        if tonumber(sourceItemId) == itemId then return true end
    end
    return false
end

local function pinEquippedAppearance(matches, state)
    local equippedId = state.equippedBySlot and state.equippedBySlot[state.selectedSlot]
    if not (Lab.GetEquippedAppearanceRecord and equippedId) then
        return matches
    end
    local equipped = Lab.GetEquippedAppearanceRecord(state.selectedSlot, equippedId)
    if not equipped then return matches end
    for index = #matches, 1, -1 do
        local record = matches[index]
        if record and not (Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record)) then
            if record.id == equipped.id or recordCoversItem(record, equippedId) then
                table.remove(matches, index)
            end
        end
    end
    local insertAt = 1
    if matches[1] and Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(matches[1]) then
        insertAt = 2
    end
    table.insert(matches, insertAt, equipped)
    return matches
end

local function arrangeAppearanceMatches(matches, state)
    local collected, uncollected = {}, {}
    for _, record in ipairs(matches or {}) do
        if record and record.collected then
            collected[#collected + 1] = record
        else
            uncollected[#uncollected + 1] = record
        end
    end
    local arranged = {}
    for _, record in ipairs(collected) do
        arranged[#arranged + 1] = record
    end
    for _, record in ipairs(uncollected) do
        arranged[#arranged + 1] = record
    end
    if Lab.CreateHideVisualRecord then
        table.insert(arranged, 1, Lab.CreateHideVisualRecord(state.selectedSlot))
    end
    pinEquippedAppearance(arranged, state)
    return arranged
end

local function findRecordIndex(matches, recordId)
    recordId = tonumber(recordId) or recordId
    if recordId == nil then return nil end
    for index, record in ipairs(matches or {}) do
        if record and (record.id == recordId or tonumber(record.id) == recordId) then
            return index
        end
    end
    return nil
end

local function addSetSourceTooltip(record)
    local presentation = record and record.presentation
    local label = usableSourceLabel(record.source)
    if not label and presentation then
        if presentation.acquisition == "PVP" then
            label = "PvP"
        else
            label = usableSourceLabel(presentation.displayLabel)
                or usableSourceLabel(presentation.raidTier)
        end
    end
    if label then
        GameTooltip:AddLine("来源：" .. label, 0.94, 0.82, 0.58, true)
    end
end

function Lab.CreateSources(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host.mode = "ITEMS"
    host.itemPage = 1
    host.setPage = 1
    host.itemCards = {}
    host.setCards = {}
    host.scSetQueue = {}
    host.scSetPresenting = false
    local itemRenderer = SC.WardrobeUI and SC.WardrobeUI.ItemCardRenderer

    function host:ResetSetPresentQueue()
        self.scSetQueue = {}
        self.scSetPresenting = false
        self.scSetActiveCard = nil
        self.scSetActiveGeneration = nil
    end

    function host:PumpSetPresent()
        if self.scSetPresenting then return end
        while true do
            local job = table.remove(self.scSetQueue, 1)
            if not job then return end
            if job.generation == job.card.scGeneration and job.card.scRecord and job.card.RunSetPresent then
                self.scSetPresenting = true
                self.scSetActiveCard = job.card
                self.scSetActiveGeneration = job.generation
                job.card:RunSetPresent(job.record, job.generation, function()
                    self.scSetPresenting = false
                    self.scSetActiveCard = nil
                    self.scSetActiveGeneration = nil
                    self:PumpSetPresent()
                end)
                return
            end
        end
    end

    function host:EnqueueSetPresent(card, record)
        local generation = card.scGeneration
        if self.scSetPresenting and self.scSetActiveCard == card and self.scSetActiveGeneration == generation then
            return
        end
        for index, job in ipairs(self.scSetQueue) do
            if job.card == card then
                self.scSetQueue[index] = { card = card, record = record, generation = generation }
                self:PumpSetPresent()
                return
            end
        end
        self.scSetQueue[#self.scSetQueue + 1] = { card = card, record = record, generation = generation }
        self:PumpSetPresent()
    end

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
        if SC.ModelProvider and SC.ModelProvider.ArmDressUpFrame then
            SC.ModelProvider.ArmDressUpFrame(model)
        end
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
                self:SetApplied(false)
                self:SetUndo(false)
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
                self:SetUndo(false)
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
            self:SetApplied(false)
            self:SetUndo(false)
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

        function card:SetApplied(value)
            if hit.SetApplied then hit:SetApplied(value and true or false) end
        end

        function card:SetUndo(value)
            if hit.SetUndo then hit:SetUndo(value and true or false) end
        end

        hit:SetScript("OnClick", function(_, mouseButton)
            local record = card.scRecord
            if not record then return end
            if mouseButton == "RightButton" then
                if Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record) then
                    return
                end
                SC.Catalog.ToggleDemoFavorite("APPEARANCES", record.id)
                host:Refresh()
                return
            end
            host:SelectItemRecord(record, true)
        end)
        hit:SetScript("OnMouseWheel", function(_, delta) scrollItems(delta) end)
        hit:SetScript("OnEnter", function(self)
            local record = card.scRecord
            if not record then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(record.name or "未知外观", 1, 0.82, 0.18)
            if Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record) then
                GameTooltip:AddLine("从预览中隐藏该部位外观。", 0.72, 0.72, 0.72, true)
                if Lab.IsAppliedReady and Lab.IsAppliedReady() then
                    GameTooltip:AddLine("点应用后写入当前角色，该部位不再显示模型。", 0.72, 0.72, 0.72, true)
                else
                    GameTooltip:AddLine("仅本地预览，当前不能应用到装备。", 1, 0.35, 0.25, true)
                end
            else
                if record.isEquippedBase then
                    GameTooltip:AddLine("当前穿着的原装备外观", 0.82, 0.78, 0.70, true)
                end
                GameTooltip:AddLine(record.collected and "已收藏" or "未收藏 · 仅可预览", record.collected and 0.4 or 0.7, record.collected and 1 or 0.7, 0.4)
                addAppearanceSourceTooltip(record)
                if state.IsAppearanceUndoTarget and state:IsAppearanceUndoTarget(state.selectedSlot, record) then
                    GameTooltip:AddLine("左键恢复该部位的原装备外观（需确认）", 1, 0.82, 0.18)
                else
                    GameTooltip:AddLine("左键写入所选槽位草稿 · 右键偏好", 0.75, 0.72, 0.66)
                end
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
        if model.SetAlpha then pcall(model.SetAlpha, model, 0) end

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

        function card:RunSetPresent(record, generation, done)
            local finished = false
            local function finish()
                if finished then return end
                finished = true
                if done then done() end
            end
            local ok = Lab.PlayDressUp and Lab.PlayDressUp(model, {
                undress = true,
                items = setItemStrings(record),
                onReady = function()
                    if card.scGeneration == generation and card.scRecord and card.scRecord.id == record.id then
                        card.scReadyGeneration = generation
                        applySetOwnership(card.scRecord)
                    end
                    finish()
                end,
                onUnavailable = function()
                    finish()
                end,
            })
            if not ok then finish() end
        end

        function card:SetRecord(record)
            local changed = not record or self.scRecordId ~= record.id
            self.scRecord = record
            if not record then
                self.scRecordId = nil
                applySetOwnership(nil)
                if Lab.StopDressUp then Lab.StopDressUp(model) end
                if model.ClearModel then model:ClearModel() end
                self:Hide()
                return
            end
            self:Show()
            model:Show()
            if changed then
                self.scGeneration = (self.scGeneration or 0) + 1
                self.scRecordId = record.id
                host:EnqueueSetPresent(self, record)
            elseif self.scReadyGeneration ~= self.scGeneration then
                host:EnqueueSetPresent(self, record)
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
                if Lab.PlaySound then Lab.PlaySound("item") end
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
            addSetSourceTooltip(record)
            GameTooltip:AddLine("左键加载本地套装预设 · 右键偏好", 0.75, 0.72, 0.66)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

        card.scModel = model
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
            self:ResetSetPresentQueue()
            for _, card in ipairs(self.setCards) do
                if Lab.StopDressUp then Lab.StopDressUp(card.scModel) end
                if card.scModel and card.scModel.ClearModel then card.scModel:ClearModel() end
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

    function host:SelectItemRecord(record, allowUndo)
        if type(record) ~= "table" then return false end
        local slotKey = state.selectedSlot
        if allowUndo and state.IsAppearanceUndoTarget and state:IsAppearanceUndoTarget(slotKey, record) then
            if Lab.ConfirmRestoreOriginal then
                Lab.ConfirmRestoreOriginal(state, slotKey)
            end
            return true
        end
        if record.isEquippedBase and type(record.id) ~= "number" then
            if state.IsSlotDirty and state:IsSlotDirty(slotKey) then
                state:ClearDraft(slotKey)
            end
            return true
        end
        state:SetDraft(slotKey, record)
        if Lab.PlaySound then Lab.PlaySound("item") end
        return true
    end

    function host:HandleVisualKey(key)
        if key == "PAGEUP" or key == "PAGEDOWN" then
            if self.mode == "SETS" then
                local totalPages = self.setTotalPages or 1
                if key == "PAGEUP" then
                    self.setPage = math.max(1, (self.setPage or 1) - 1)
                else
                    self.setPage = math.min(totalPages, (self.setPage or 1) + 1)
                end
            else
                local totalPages = self.itemTotalPages or 1
                if key == "PAGEUP" then
                    self.itemPage = math.max(1, (self.itemPage or 1) - 1)
                else
                    self.itemPage = math.min(totalPages, (self.itemPage or 1) + 1)
                end
            end
            self:Refresh()
            return true
        end
        if key ~= "LEFT" and key ~= "RIGHT" and key ~= "UP" and key ~= "DOWN" then
            return false
        end
        if self.mode == "SETS" then
            local matches = self.scSetMatches or {}
            if #matches == 0 then return false end
            local current = state.presetRecord and findRecordIndex(matches, state.presetRecord.id)
            local nextIndex
            if current then
                nextIndex = adjustedDisplayIndex(current, #matches, SET_COLUMNS, key)
            else
                nextIndex = 1
            end
            local record = matches[nextIndex]
            if not record then return false end
            self.setPage = math.floor((nextIndex - 1) / SET_PAGE_SIZE) + 1
            state:SetPreset(record)
            if Lab.PlaySound then Lab.PlaySound("item") end
            return true
        end
        local matches = self.scItemMatches or {}
        if #matches == 0 then return false end
        local selected = state.draftBySlot and state.draftBySlot[state.selectedSlot]
        local currentId = selected and selected.id
        if not currentId and state.GetAppliedCollectionId then
            currentId = state:GetAppliedCollectionId(state.selectedSlot)
        end
        local current = findRecordIndex(matches, currentId)
        local nextIndex
        if current then
            nextIndex = adjustedDisplayIndex(current, #matches, ITEM_COLUMNS, key)
        else
            nextIndex = 1
        end
        local record = matches[nextIndex]
        if not record then return false end
        self.itemPage = math.floor((nextIndex - 1) / ITEM_PAGE_SIZE) + 1
        return self:SelectItemRecord(record)
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
            local matches = SC.Catalog.QueryAll("SETS", query, filters)
            self.scSetMatches = matches
            local total = #matches
            local totalPages = math.max(1, math.ceil(total / SET_PAGE_SIZE))
            self.setPage = math.max(1, math.min(self.setPage or 1, totalPages))
            local firstIndex = ((self.setPage - 1) * SET_PAGE_SIZE) + 1
            local records = {}
            for index = firstIndex, math.min(total, firstIndex + SET_PAGE_SIZE - 1) do
                records[#records + 1] = matches[index]
            end
            local page = self.setPage
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
            local matches = arrangeAppearanceMatches(
                SC.Catalog.QueryAll("APPEARANCES", query, filters),
                state
            )
            self.scItemMatches = matches
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
                local isApplied = record and state.IsAppearanceAppliedToSlot
                    and state:IsAppearanceAppliedToSlot(state.selectedSlot, record)
                local isUndo = record and state.IsAppearanceUndoTarget
                    and state:IsAppearanceUndoTarget(state.selectedSlot, record)
                card:SetApplied(isApplied)
                card:SetUndo(isUndo)
                -- Official: current-transmogged wins over pending selected.
                card:SetSelected(record and selected and record.id == selected.id and not isApplied)
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
        self:ResetSetPresentQueue()
        for _, card in ipairs(self.itemCards) do
            card:ClearRenderer()
        end
        for _, card in ipairs(self.setCards) do
            if Lab.StopDressUp then Lab.StopDressUp(card.scModel) end
            if card.scModel and card.scModel.ClearModel then card.scModel:ClearModel() end
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
