local SC = SoloCollections

SC.WardrobeUI = SC.WardrobeUI or {}
local Layout = {}
SC.WardrobeUI.Layout = Layout

local function publicComponents()
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    return public, public and public.Components
end

function Layout:StylePanel(frame, background)
    local public, components = publicComponents()
    if not public then return false end
    if components and components.CreateInset then
        frame.scNewEraInset = frame.scNewEraInset or components:CreateInset(frame, { left = 2, top = 2, right = 2, bottom = 2 })
    end
    if background then
        background:SetTexture(public.Theme:GetTexture("rock"))
        background:SetVertexColor(0.31, 0.23, 0.15, 0.96)
    end
    frame.scNewEraStyled = true
    return true
end

function Layout:StyleCard(card, background, border)
    local public, components = publicComponents()
    if not public then return false end
    local token = public.Theme:GetToken("insetBackground")
    if background and token then
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(token[1], token[2], token[3], token[4] or 1)
    end
    if border and border.SetBorderColor then border:SetBorderColor(0.55, 0.43, 0.24, 0.92) end
    if components and components.ApplyItemQuality and card and card.scQuality then
        components:ApplyItemQuality(card, card.scQuality)
    end
    card.scNewEraStyled = true
    return true
end

function Layout:StyleListRow(row, background, selected)
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if not public then return false end
    local token = public.Theme:GetToken("insetBackground")
    if background and token then background:SetVertexColor(token[1], token[2], token[3], token[4] or 0.92) end
    if selected then selected:SetVertexColor(0.82, 0.48, 0.10, 0.42) end
    row.scNewEraStyled = true
    return true
end

function Layout:StyleItemButton(button, quality)
    local _, components = publicComponents()
    if not components then return false end
    components:ApplyItemQuality(button, quality)
    button.scNewEraItemButton = true
    return true
end

