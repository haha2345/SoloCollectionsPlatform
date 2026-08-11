local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

function Lab.CreateSlots(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -430)
    host:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 72)
    host.buttons = {}
    for index, definition in ipairs(Lab.SLOTS) do
        local button = CreateFrame("Button", nil, host)
        button:SetWidth(86); button:SetHeight(29)
        button:SetPoint("TOPLEFT", host, "TOPLEFT", ((index - 1) % 3) * 94, -(math.floor((index - 1) / 3) * 34))
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Buttons\\WHITE8X8"); background:SetAllPoints(button)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER"); label:SetText(definition.label)
        button.scBackground, button.scLabel, button.scSlotKey = background, label, definition.key
        button:SetScript("OnClick", function(self) state:SelectSlot(self.scSlotKey) end)
        host.buttons[definition.key] = button
    end
    function host:Refresh()
        for slotKey, button in pairs(self.buttons) do
            local dirty = state.dirtySlots[slotKey]
            if state.selectedSlot == slotKey then button.scBackground:SetVertexColor(0.72, 0.34, 0.07, 0.92)
            elseif dirty then button.scBackground:SetVertexColor(0.32, 0.12, 0.46, 0.92)
            else button.scBackground:SetVertexColor(0.07, 0.065, 0.055, 0.92) end
            button.scLabel:SetText((dirty and "* " or "") .. Lab.SLOT_BY_KEY[slotKey].label)
        end
    end
    return host
end
