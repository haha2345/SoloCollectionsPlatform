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
local ITEM_FIRST_CENTER_X = -238
local ITEM_FIRST_TOP_Y = -85
local SET_COLUMNS = 4
local SET_PAGE_SIZE = 8
local SET_WIDTH = 129
local SET_HEIGHT = 186
local SET_GAP_X = 13
local SET_GAP_Y = 14
local SET_FIRST_LEFT_X = 50
local SET_FIRST_TOP_Y = -50
local STANDALONE_ITEM_SLOTS = { MAINHAND = true, OFFHAND = true }
local WEAPON_FILTERS = {
    { key = "ONE_HAND_AXE", label = "单手斧", main = true, off = true },
    { key = "TWO_HAND_AXE", label = "双手斧", main = true },
    { key = "BOW", label = "弓", main = true },
    { key = "GUN", label = "枪械", main = true },
    { key = "ONE_HAND_MACE", label = "单手锤", main = true, off = true },
    { key = "TWO_HAND_MACE", label = "双手锤", main = true },
    { key = "POLEARM", label = "长柄武器", main = true },
    { key = "ONE_HAND_SWORD", label = "单手剑", main = true, off = true },
    { key = "TWO_HAND_SWORD", label = "双手剑", main = true },
    { key = "STAFF", label = "法杖", main = true },
    { key = "FIST_WEAPON", label = "拳套", main = true, off = true },
    { key = "DAGGER", label = "匕首", main = true, off = true },
    { key = "THROWN", label = "投掷武器", main = true },
    { key = "CROSSBOW", label = "弩", main = true },
    { key = "WAND", label = "魔杖", main = true },
    { key = "FISHING_POLE", label = "钓鱼竿", main = true },
    { key = "SHIELD", label = "盾牌", off = true },
    { key = "OFFHAND_ITEM", label = "副手物品", off = true },
}
local ARMOR_FILTER_SLOTS = (SC.EzWardrobe and SC.EzWardrobe.DataProvider and
    SC.EzWardrobe.DataProvider.ARMOR_FILTER_SLOTS) or {
    HEAD = true, SHOULDER = true, CHEST = true, WRIST = true,
    HANDS = true, WAIST = true, LEGS = true, FEET = true,
}

local function weaponOptionSupportsSlot(option, slotKey)
    return (slotKey == "MAINHAND" and option.main) or (slotKey == "OFFHAND" and option.off)
end

local function availableWeaponFilters(slotKey)
    local result = {}
    local identity = SC.IdentityRegistry
    local allowed = identity and identity.GetWeaponTypes and identity.GetWeaponTypes(slotKey) or {}
    for _, option in ipairs(WEAPON_FILTERS) do
        if weaponOptionSupportsSlot(option, slotKey) and allowed[option.key] then
            result[#result + 1] = option
        end
    end
    return result
end

local function weaponFilterLabel(weaponType)
    if not weaponType or weaponType == "AUTO" or weaponType == "ALL" then
        return "全部可用武器"
    end
    for _, option in ipairs(WEAPON_FILTERS) do
        if option.key == weaponType then return option.label end
    end
    return nil
end

local function ensureWeaponFilterForSlot(filters, slotKey)
    if not filters or not STANDALONE_ITEM_SLOTS[slotKey] then return nil end
    local selected = filters.weaponType
    if not selected or selected == "" or selected == "AUTO" or selected == "ALL" then
        filters.weaponType = "AUTO"
        return filters.weaponType
    end
    local options = availableWeaponFilters(slotKey)
    for _, option in ipairs(options) do
        if selected == option.key then return option.key end
    end
    filters.weaponType = "AUTO"
    return filters.weaponType
end

local function armorFilterApplies(slotKey)
    return ARMOR_FILTER_SLOTS[slotKey] == true
end

local function copyFilters(slotKey)
    local filters = {}
    for key, value in pairs((SC.db and SC.db.filters) or {}) do filters[key] = value end
    filters.slot = slotKey
    if not armorFilterApplies(slotKey) then filters.armorType = "ALL" end
    ensureWeaponFilterForSlot(filters, slotKey)
    return filters
end

local function copySetFilters()
    local filters = {}
    for key, value in pairs((SC.db and SC.db.filters) or {}) do filters[key] = value end
    filters.slot = "ALL"
    filters.armorType = "ALL"
    filters.weaponType = "ALL"
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

local function setRecordKey(record)
    if type(record) ~= "table" then return nil end
    local variant = selectedVariant(record)
    local ordinal = tonumber((variant and variant.variantOrdinal) or record.selectedVariantOrdinal) or 0
    return tostring(record.id or record.collectionId or "") .. ":" .. tostring(ordinal)
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

local function memberContainsItem(member, itemId)
    if type(member) ~= "table" or not itemId then return false end
    if tonumber(member.previewSourceItemId) == itemId then return true end
    for _, sourceItemId in ipairs(member.sourceItemIds or {}) do
        if tonumber(sourceItemId) == itemId then return true end
    end
    return false
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
    local itemDataProvider = SC.EzWardrobe and SC.EzWardrobe.DataProvider
        and SC.EzWardrobe.DataProvider:Create(host) or nil

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
            "TOP", itemsView, "TOP",
            ITEM_FIRST_CENTER_X + column * (ITEM_WIDTH + ITEM_GAP_X),
            ITEM_FIRST_TOP_Y - row * (ITEM_HEIGHT + ITEM_GAP_Y)
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
                selected:Hide()
                favorite:Hide()
                if not itemRenderer then
                    model:ClearModel()
                    objectModel:ClearModel()
                end
                self:Hide()
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
            end
            selected:Hide()
            favorite:Hide()
            self:Hide()
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
            if record.source and record.source ~= "" then
                GameTooltip:AddLine("来源：" .. tostring(record.source), 0.94, 0.82, 0.58, true)
            end
            if state:IsRequestPending() then
                GameTooltip:AddLine("应用请求处理中，暂不能改动本地草稿。", 1, 0.76, 0.32, true)
            elseif record.collected then
                GameTooltip:AddLine("左键写入所选槽位草稿 · 右键偏好", 0.75, 0.72, 0.66)
            else
                GameTooltip:AddLine("左键仅加入本地预览 · 右键偏好", 0.75, 0.72, 0.66)
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
            SET_FIRST_LEFT_X + column * (SET_WIDTH + SET_GAP_X),
            SET_FIRST_TOP_Y - row * (SET_HEIGHT + SET_GAP_Y)
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
            local recordKey = setRecordKey(record)
            local changed = not record or self.scRecordKey ~= recordKey
            self.scRecord = record
            if not record then
                self.scRecordId = nil
                self.scRecordKey = nil
                presenter:Clear("LAB_SET_EMPTY")
                model:ClearModel()
                selected:Hide()
                favorite:Hide()
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
                        if card.scGeneration == generation and card.scRecordKey == recordKey then
                            card.scReadyGeneration = generation
                        end
                    end,
                })
                self.scRecordId = record.id
                self.scRecordKey = recordKey
            end
            border:SetCollected(record.collected)
            model:SetAlpha(record.collected and 1 or 0.48)
            if record.favorite then favorite:Show() else favorite:Hide() end
        end

        function card:SetSelected(value)
            if value then selected:Show() else selected:Hide() end
        end

        function card:ClearRenderer(reason)
            self.scRecord = nil
            self.scRecordId = nil
            self.scRecordKey = nil
            presenter:Clear(reason or "LAB_SET_CLEARED")
            model:ClearModel()
            selected:Hide()
            favorite:Hide()
            self:Hide()
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
            if record.source and record.source ~= "" then
                GameTooltip:AddLine("来源：" .. tostring(record.source), 0.94, 0.82, 0.58, true)
            end
            local pendingSwitch = state.requestState and state.requestState.status == "CONFIRM_SET_PRESET"
                and setRecordKey(state.requestState.record) == setRecordKey(record)
            if state:IsRequestPending() then
                GameTooltip:AddLine("应用请求处理中，暂不能切换套装预设。", 1, 0.76, 0.32, true)
            elseif pendingSwitch then
                GameTooltip:AddLine("再次点击同一套装确认切换预设。", 1, 0.76, 0.32, true)
            else
                GameTooltip:AddLine("左键加载本地套装预设 · 右键偏好", 0.75, 0.72, 0.66)
            end
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
    applySet:Hide()
    local function showApplySetTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local record = state.presetRecord
        local canApply, reason, variantOwned, variantRequired = false, nil, nil, nil
        if state.GetSetApplyState then
            canApply, reason, variantOwned, variantRequired = state:GetSetApplyState()
            record = state.presetRecord
        end
        GameTooltip:SetText("应用套装预设", 1, 0.82, 0.18)
        if not record then
            GameTooltip:AddLine("先在套装页选择一个套装预设。", 0.72, 0.72, 0.72, true)
        elseif canApply then
            GameTooltip:AddLine(tostring(record.name or "所选套装"), 1, 1, 1, true)
            GameTooltip:AddLine("通过 SC2 请求服务端原子应用套装。", 0.72, 0.72, 0.72, true)
        elseif reason == "NOT_OWNED" then
            local owned = tonumber(variantOwned) or tonumber(record.collectedCount) or 0
            local required = tonumber(variantRequired) or tonumber(record.requiredCount) or #(record.itemIds or {})
            GameTooltip:AddLine("当前版本尚未收集完整：" .. owned .. " / " .. required, 1, 0.35, 0.25, true)
        elseif reason == "BRIDGE_UNAVAILABLE" then
            GameTooltip:AddLine("SC2 套装服务尚未就绪，暂不能提交应用。", 1, 0.35, 0.25, true)
        elseif reason == "REQUEST_PENDING" then
            GameTooltip:AddLine("已有应用请求正在处理。", 1, 0.76, 0.32, true)
        else
            GameTooltip:AddLine("当前套装预设暂不能提交应用。", 1, 0.35, 0.25, true)
        end
        GameTooltip:Show()
    end
    applySet:SetScript("OnEnter", showApplySetTooltip)
    applySet:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local applySetDisabledTip = CreateFrame("Frame", nil, applySet)
    applySetDisabledTip:SetAllPoints(applySet)
    applySetDisabledTip:SetFrameLevel(applySet:GetFrameLevel() + 1)
    applySetDisabledTip:EnableMouse(true)
    applySetDisabledTip:SetScript("OnEnter", showApplySetTooltip)
    applySetDisabledTip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    applySetDisabledTip:Hide()

    local selectedSetName = setsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedSetName:SetPoint("BOTTOMLEFT", setsView, "BOTTOMLEFT", 16, 16)
    selectedSetName:SetWidth(210)
    selectedSetName:SetJustifyH("LEFT")
    selectedSetName:Hide()

    local selectedItemName = itemsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedItemName:SetPoint("BOTTOMLEFT", itemsView, "BOTTOMLEFT", 16, 16)
    selectedItemName:SetWidth(260)
    selectedItemName:SetJustifyH("LEFT")
    selectedItemName:Hide()

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
                card:ClearRenderer("LAB_SET_VIEW_HIDDEN")
            end
        else
            itemsView:Hide()
            setsView:Show()
            for _, card in ipairs(self.itemCards) do
                card:ClearRenderer()
            end
        end
        self:Refresh()
        self:SyncFilters()
    end

    function host:SetFilter(key, value)
        if not (SC.db and SC.db.filters) then return end
        if key == "classToken" then
            SC.db.filters.classToken = tostring(value or "ALL")
        elseif key == "weaponType" or key == "armorType" then
            SC.db.filters[key] = tostring(value or "AUTO")
        else
            SC.db.filters[key] = value and true or false
        end
        self.itemPage = 1
        self.setPage = 1
        self:Refresh()
        self:SyncFilters()
    end

    function host:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scFilterPopup or not SC.db or SC.db.mainTab ~= "TRANSMOG_LAB" then
            return
        end
        if frame.scFilterButton and frame.scFilterButton.SetText then
            frame.scFilterButton:SetText(self.mode == "ITEMS" and "来源" or "过滤器")
        end
        local filters = SC.db.filters or {}
        ensureWeaponFilterForSlot(filters, state.selectedSlot)
        local collectedLabel = self.mode == "SETS" and "已完成套装" or "已收藏外观"
        local uncollectedLabel = self.mode == "SETS" and "未完成套装" or "未收藏外观"
        local options = {
            { label = collectedLabel, checked = filters.collected, onClick = function()
                host:SetFilter("collected", not filters.collected)
            end },
            { label = uncollectedLabel, checked = filters.uncollected, onClick = function()
                host:SetFilter("uncollected", not filters.uncollected)
            end },
            { label = "仅显示偏好", checked = filters.favorites, onClick = function()
                host:SetFilter("favorites", not filters.favorites)
            end },
        }
        if self.mode == "ITEMS" and STANDALONE_ITEM_SLOTS[state.selectedSlot] then
            options[#options + 1] = {
                label = "武器：全部可用",
                checked = not filters.weaponType or filters.weaponType == "AUTO" or filters.weaponType == "ALL",
                onClick = function() host:SetFilter("weaponType", "AUTO") end,
            }
            for _, weaponOption in ipairs(availableWeaponFilters(state.selectedSlot)) do
                local optionRef = weaponOption
                options[#options + 1] = {
                    label = "武器：" .. optionRef.label,
                    checked = filters.weaponType == optionRef.key,
                    onClick = function() host:SetFilter("weaponType", optionRef.key) end,
                }
            end
        elseif self.mode == "ITEMS" and armorFilterApplies(state.selectedSlot) then
            local armorOptions = (SC.EzWardrobe and SC.EzWardrobe.DataProvider
                and SC.EzWardrobe.DataProvider.ARMOR_OPTIONS) or {}
            local storedArmorType = filters.armorType or "AUTO"
            options[#options + 1] = {
                label = "护甲：职业默认",
                checked = not storedArmorType or storedArmorType == "AUTO" or storedArmorType == "ALL",
                onClick = function() host:SetFilter("armorType", "AUTO") end,
            }
            for _, armorOption in ipairs(armorOptions) do
                local optionRef = armorOption
                options[#options + 1] = {
                    label = "护甲：" .. optionRef.label,
                    checked = storedArmorType == optionRef.key,
                    onClick = function() host:SetFilter("armorType", optionRef.key) end,
                }
            end
        elseif self.mode == "SETS" then
            local identity = SC.IdentityRegistry
            local classOptions = identity and identity.GetClassFilterOptions and
                identity.GetClassFilterOptions() or {}
            local currentClass = filters.classToken or "ALL"
            for _, classOption in ipairs(classOptions) do
                local optionRef = classOption
                options[#options + 1] = {
                    label = "职业：" .. optionRef.label,
                    checked = currentClass == optionRef.key,
                    onClick = function() host:SetFilter("classToken", optionRef.key) end,
                }
            end
        end
        frame.scFilterPopup:SetOptions(options)
    end

    function host:Refresh()
        if SC.db and SC.db.filters then
            ensureWeaponFilterForSlot(SC.db.filters, state.selectedSlot)
        end
        local query = (SC.db and SC.db.query) or ""
        if self.scLastQuery ~= query then
            self.itemPage = 1
            self.setPage = 1
            self.scLastQuery = query
        end
        local request = state.requestState or {}
        if self.mode == "SETS" then
            local filters = copySetFilters()
            local records, page, totalPages = SC.Catalog.Query("SETS", query, filters, self.setPage, SET_PAGE_SIZE)
            self.setPage, self.setTotalPages = page, totalPages
            setControls:SetPage(page, totalPages)
            if state.presetRecord and state.RefreshPresetRecord then
                state:RefreshPresetRecord()
            end
            for index, card in ipairs(self.setCards) do
                local record = records[index]
                card:SetRecord(record)
                card:SetSelected(record and state.presetRecord and
                    setRecordKey(record) == setRecordKey(state.presetRecord))
            end
            if #records == 0 then
                UI.ShowEmptyState(setEmpty, host, "没有符合条件的套装", "调整搜索、职业或收藏过滤后再试。")
            else
                UI.HideEmptyState(setEmpty)
            end
            local canApplySet, _, variantOwned, variantRequired = false, nil, nil, nil
            if state.GetSetApplyState then
                canApplySet, _, variantOwned, variantRequired = state:GetSetApplyState(true)
            end
            if state.presetRecord then
                local owned = tonumber(variantOwned) or tonumber(state.presetRecord.collectedCount) or 0
                local required = tonumber(variantRequired) or tonumber(state.presetRecord.requiredCount) or #(state.presetRecord.itemIds or {})
                selectedSetName:SetText(tostring(state.presetRecord.name or ("套装 " .. tostring(state.presetRecord.id))) ..
                    "  " .. owned .. "/" .. required)
            else
                selectedSetName:SetText("选择套装以建立本地预设")
            end
            if canApplySet then
                applySet:Enable()
                applySetDisabledTip:Hide()
            else
                applySet:Disable()
                applySetDisabledTip:Show()
            end
            setProgress("SETS", filters)
        else
            local filters = copyFilters(state.selectedSlot)
            local records, page, totalPages
            if itemDataProvider then
                records, page, totalPages = itemDataProvider:QueryItems(
                    self.itemPage,
                    ITEM_PAGE_SIZE,
                    { slot = state.selectedSlot }
                )
            else
                records, page, totalPages = SC.Catalog.Query(
                    "APPEARANCES",
                    query,
                    filters,
                    self.itemPage,
                    ITEM_PAGE_SIZE
                )
            end
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
            local slot = Lab.SLOT_BY_KEY and Lab.SLOT_BY_KEY[state.selectedSlot]
            local weaponLabel = STANDALONE_ITEM_SLOTS[state.selectedSlot]
                and weaponFilterLabel(filters.weaponType) or nil
            local armorLabel
            if armorFilterApplies(state.selectedSlot) and itemDataProvider then
                local _, effectiveArmorType = itemDataProvider:GetArmorState(state.selectedSlot)
                for _, option in ipairs(SC.EzWardrobe.DataProvider.ARMOR_OPTIONS or {}) do
                    if option.key == effectiveArmorType then
                        armorLabel = option.label
                        break
                    end
                end
            end
            local slotText = (slot and slot.label or "所选槽位") ..
                (weaponLabel and (" · " .. weaponLabel) or (armorLabel and (" · " .. armorLabel) or ""))
            if selected then
                selectedItemName:SetText(slotText .. "：" .. tostring(selected.name or ("外观 " .. tostring(selected.id))))
            else
                selectedItemName:SetText(slotText .. "：选择外观以建立本地草稿")
            end
            if itemDataProvider then
                local collected, total = itemDataProvider:GetProgress({ slot = state.selectedSlot })
                if UI.CollectionsFrame and UI.CollectionsFrame.scProgress then
                    UI.CollectionsFrame.scProgress:SetProgress(collected, total)
                end
            else
                setProgress("APPEARANCES", filters)
            end
        end
    end

    function host:ClearPresenters(reason)
        for _, card in ipairs(self.itemCards) do
            card:ClearRenderer()
        end
        for _, card in ipairs(self.setCards) do
            card:ClearRenderer(reason or "LAB_HIDDEN")
        end
    end

    function host:ContainsVisibleItem(itemId)
        itemId = tonumber(itemId)
        if not itemId then return false end
        if self.mode == "ITEMS" then
            for _, card in ipairs(self.itemCards) do
                local record = card:IsShown() and card.scRecord or nil
                if record and tonumber(record.itemId) == itemId then return true end
            end
        elseif self.mode == "SETS" then
            for _, card in ipairs(self.setCards) do
                local record = card:IsShown() and card.scRecord or nil
                local variant = selectedVariant(record)
                for _, member in ipairs((variant and variant.members) or {}) do
                    if memberContainsItem(member, itemId) then return true end
                end
            end
        end
        return false
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
    host.scApplySetDisabledTip = applySetDisabledTip
    host.scSelectedItemName = selectedItemName
    host.scSelectedSetName = selectedSetName
    itemTab:SetSelected(true)
    setTab:SetSelected(false)
    return host
end
