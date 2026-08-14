local SC = SoloCollections

SC.WardrobeUI = SC.WardrobeUI or {}
local ItemPresenter = {}
SC.WardrobeUI.ItemPresenter = ItemPresenter

function ItemPresenter:AttachBody(model, panelCheck)
    if model.scWardrobeBodyPresenter then return model.scWardrobeBodyPresenter end
    model.scWardrobeBodyPresenter = SC.ModelProvider.Create("DRESSUP", model, { panelCheck = panelCheck })
    return model.scWardrobeBodyPresenter
end

function ItemPresenter:PresentBody(model, itemString, onReady, panelCheck)
    local presenter = self:AttachBody(model, panelCheck)
    return presenter:Present({
        unit = "player",
        undress = true,
        settleTicks = 2,
        items = itemString and { itemString } or {},
        onReady = onReady,
    })
end

function ItemPresenter:ClearBody(model, reason)
    if model.scWardrobeBodyPresenter then model.scWardrobeBodyPresenter:Clear(reason or "ITEM_INVALIDATED") end
end

function ItemPresenter:AttachSet(model, panelCheck)
    if model.scWardrobeSetPresenter then return model.scWardrobeSetPresenter end
    model.scWardrobeSetPresenter = SC.ModelProvider.Create("DRESSUP", model, {
        controls = true,
        panelCheck = panelCheck,
    })
    return model.scWardrobeSetPresenter
end
