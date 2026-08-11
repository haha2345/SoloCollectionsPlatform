local SC = SoloCollections
local UI = SC.UI

-- Shared NewEra composition used by the production mount and pet pages.
-- Their data queries, presenters, and Bridge actions remain page-owned.
function UI.StyleNewEraCompanionLayout(page, list, detail, listBackground, detailBackground)
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if not public then return false end
    local inset = public.Theme:GetToken("insetBackground")
    if listBackground and inset then listBackground:SetVertexColor(inset[1], inset[2], inset[3], inset[4]) end
    if detailBackground then
        detailBackground:SetTexture(public.Theme:GetTexture("rock"))
        detailBackground:SetTexCoord(0, 1, 0, 1)
        detailBackground:SetVertexColor(0.34, 0.25, 0.16, 0.96)
    end
    page.scNewEraLayout = { list = list, detail = detail, actions = {} }
    return true
end

function UI.RegisterNewEraCompanionAction(page, button)
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if public and button then public.Components:SkinButton(button) end
    if page.scNewEraLayout and button then
        page.scNewEraLayout.actions[#page.scNewEraLayout.actions + 1] = button
    end
end
