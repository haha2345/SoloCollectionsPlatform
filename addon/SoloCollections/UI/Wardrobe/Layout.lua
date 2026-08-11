local SC = SoloCollections

SC.WardrobeUI = SC.WardrobeUI or {}
local Layout = {}
SC.WardrobeUI.Layout = Layout

function Layout:StylePanel(frame, background)
    frame.scEzCollectionsPanel = background
    return false
end

function Layout:StyleCard(card, background, border)
    card.scEzCollectionsCard = { background = background, border = border }
    return false
end

function Layout:StyleListRow(row, background, selected)
    row.scEzCollectionsRow = { background = background, selected = selected }
    return false
end

function Layout:StyleItemButton(button, quality)
    button.scEzCollectionsQuality = quality
    return false
end
