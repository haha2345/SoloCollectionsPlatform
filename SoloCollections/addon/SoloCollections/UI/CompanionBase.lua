local SC = SoloCollections
local UI = SC.UI

-- Compatibility hooks retained for the existing mount and pet presenters.
-- Page chrome is now owned by the ezCollections template layer; DragonUI is
-- intentionally limited to the outer journal frame.
function UI.StyleNewEraCompanionLayout(page, list, detail, listBackground, detailBackground)
    page.scEzCollectionsLayout = {
        list = list,
        detail = detail,
        listBackground = listBackground,
        detailBackground = detailBackground,
        actions = {},
    }
    return true
end

function UI.RegisterNewEraCompanionAction(page, button)
    if page.scEzCollectionsLayout and button then
        page.scEzCollectionsLayout.actions[#page.scEzCollectionsLayout.actions + 1] = button
    end
end
