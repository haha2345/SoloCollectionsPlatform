local SC = SoloCollections
local UI = SC.UI

SC.EzWardrobe = SC.EzWardrobe or {}
local Items = SC.EzWardrobe.Items or {}
SC.EzWardrobe.Items = Items

local Assets = SC.EzWardrobe.Assets

Items.ROWS = 3
Items.COLUMNS = 6
Items.PAGE_SIZE = Items.ROWS * Items.COLUMNS
Items.LAYOUT = {
    itemWidth = 78,
    itemHeight = 104,
    itemGapX = 16,
    itemGapY = 24,
    itemStartX = 102,
    itemStartY = 85,
}

function Items:CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "SoloCollectionsEzWardrobeItemsPanelTemplate")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -60)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 5)
    local inset = Assets:ApplyItemsPanel(panel)
    panel:EnableMouseWheel(true)
    return panel, inset
end

function Items:LayoutCardPool(models, columns, startX)
    columns = columns or self.COLUMNS
    startX = startX or self.LAYOUT.itemStartX
    for index, itemModel in ipairs(models or {}) do
        local card = itemModel.scCard
        if card then
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            card:ClearAllPoints()
            card:SetPoint(
                "TOPLEFT",
                card:GetParent(),
                "TOPLEFT",
                startX + column * (self.LAYOUT.itemWidth + self.LAYOUT.itemGapX),
                -self.LAYOUT.itemStartY - row * (self.LAYOUT.itemHeight + self.LAYOUT.itemGapY)
            )
        end
    end
end

local function createCard(parent, index, callbacks)
    local itemCard = CreateFrame("Frame", nil, parent, "SoloCollectionsEzWardrobeItemCardTemplate")

    local itemModel = CreateFrame("DressUpModel", nil, itemCard)
    itemModel:SetAllPoints(itemCard)
    itemModel.scCard = itemCard

    -- Hidden compatibility object for existing set/item presenter contracts.
    -- The active appearance path is always the DressUpModel above.
    local itemObjectModel = CreateFrame("PlayerModel", nil, itemCard)
    itemObjectModel:SetAllPoints(itemCard)
    itemObjectModel:Hide()

    local unavailable = CreateFrame("Frame", nil, itemCard)
    unavailable:SetAllPoints(itemCard)
    unavailable:SetFrameLevel(itemModel:GetFrameLevel() + 1)
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

    local hit = CreateFrame("Button", nil, itemCard, "SoloCollectionsEzWardrobeItemHitTemplate")
    hit:SetAllPoints(itemCard)
    hit:SetFrameLevel(itemModel:GetFrameLevel() + 2)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:EnableMouseWheel(true)

    local background = itemCard:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetAllPoints(itemCard)
    background:SetVertexColor(0, 0, 0, 1)

    local border, selected, favorite, hover = UI.EzCollections:CreateWardrobeItemChrome(hit)

    local name = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("BOTTOMLEFT", hit, "BOTTOMLEFT", 5, 5)
    name:SetPoint("BOTTOMRIGHT", hit, "BOTTOMRIGHT", -5, 5)
    name:SetHeight(18)
    name:SetJustifyH("CENTER")
    name:SetJustifyV("MIDDLE")
    name:Hide()

    local collectionState = CreateFrame("Frame", nil, hit)
    collectionState:SetWidth(58)
    collectionState:SetHeight(15)
    collectionState:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -4, -4)
    collectionState:SetFrameLevel(hit:GetFrameLevel() + 3)
    local stateBackground = collectionState:CreateTexture(nil, "BACKGROUND")
    stateBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    stateBackground:SetAllPoints(collectionState)
    stateBackground:SetVertexColor(0.02, 0.02, 0.02, 0.78)
    local stateLabel = collectionState:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stateLabel:SetAllPoints(collectionState)
    stateLabel:SetJustifyH("CENTER")
    stateLabel:SetText("未收集")
    stateLabel:SetTextColor(0.72, 0.73, 0.74)
    collectionState:Hide()

    hit:SetScript("OnClick", function(_, button)
        if callbacks and callbacks.onClick then callbacks.onClick(itemModel, button) end
    end)
    hit:SetScript("OnEnter", function(self)
        if callbacks and callbacks.onEnter then callbacks.onEnter(self, itemModel) end
    end)
    hit:SetScript("OnLeave", function()
        if callbacks and callbacks.onLeave then callbacks.onLeave(itemModel) end
    end)
    hit:SetScript("OnMouseWheel", function(_, delta)
        if callbacks and callbacks.onMouseWheel then callbacks.onMouseWheel(delta) end
    end)

    itemModel.scObjectModel = itemObjectModel
    itemObjectModel.scHostModel = itemModel
    itemModel.scUnavailable = unavailable
    itemModel.scUnavailableIcon = unavailableIcon
    itemModel.scUnavailableText = unavailableText
    itemModel.scHitFrame = hit
    itemModel.scBorder = border
    itemModel.scSelected = selected
    itemModel.scName = name
    itemModel.scFavorite = favorite
    itemModel.scHover = hover
    itemModel.scCollectionState = collectionState
    itemModel.scPoolIndex = index
    SC.WardrobeUI.Layout:StyleCard(itemCard, background, border)
    itemCard:Hide()
    itemModel:Hide()
    return itemModel
end

function Items:CreateCardPool(parent, callbacks)
    local models = {}
    for index = 1, self.PAGE_SIZE do
        models[index] = createCard(parent, index, callbacks)
    end
    self:LayoutCardPool(models)
    return models
end

function Items:UpdateCardState(itemModel, selectedId)
    local record = itemModel and itemModel.scRecord
    if not record then
        if itemModel then
            itemModel.scName:SetText("")
            itemModel.scFavorite:Hide()
            itemModel.scCollectionState:Hide()
            itemModel.scSelected:Hide()
        end
        return
    end
    itemModel.scName:SetText(record.name or "未知外观")
    itemModel.scName:SetTextColor(record.collected and 1.00 or 0.62, record.collected and 0.82 or 0.62, record.collected and 0.18 or 0.60)
    itemModel.scCollectionState:Hide()
    itemModel.scBorder:SetCollected(record.collected)
    if record.favorite then itemModel.scFavorite:Show() else itemModel.scFavorite:Hide() end
    if record.collectionId == selectedId or record.id == selectedId then
        itemModel.scSelected:Show()
    else
        itemModel.scSelected:Hide()
    end
end

function Items:ApplyCollectionDelta(models, collectionId, collected, selectedId)
    collectionId = tonumber(collectionId)
    local updated = 0
    for _, itemModel in ipairs(models or {}) do
        local record = itemModel.scRecord
        if record and tonumber(record.collectionId or record.id) == collectionId then
            record.collected = collected and true or false
            self:UpdateCardState(itemModel, selectedId)
            updated = updated + 1
        end
    end
    return updated
end

function Items:ApplyJournalChrome()
    Assets:ApplyWardrobeControls(UI.CollectionsFrame)
end
