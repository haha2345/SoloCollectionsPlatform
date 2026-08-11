local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local PAGE_SIZE = 9

local function sourceFilters(slotKey)
    return {
        collected = true, uncollected = true, favorites = false,
        slot = slotKey, armorType = "AUTO", weaponType = "ALL", class = "ALL",
    }
end

function Lab.CreateSources(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -44)
    host:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 46)
    host.rows, host.page = {}, 1
    for index = 1, PAGE_SIZE do
        local row = UI.CreateListRow(host, 300, 44, function(_, record)
            if record then state:SetDraft(state.selectedSlot, record) end
        end)
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -((index - 1) * 47))
        host.rows[index] = row
    end
    local controls = UI.CreatePageControls(parent, function()
        host.page = math.max(1, host.page - 1); host:Refresh()
    end, function()
        host.page = math.min(host.totalPages or 1, host.page + 1); host:Refresh()
    end)
    controls:SetPoint("BOTTOM", parent, "BOTTOM", 0, 12)
    host.controls = controls
    function host:Refresh()
        local records, page, totalPages = SC.Catalog.Query(
            "APPEARANCES", "", sourceFilters(state.selectedSlot), self.page, PAGE_SIZE
        )
        self.page, self.totalPages, self.records = page, totalPages, records
        controls:SetPage(page, totalPages)
        local selected = state.draftBySlot[state.selectedSlot]
        for index, row in ipairs(self.rows) do
            local record = records[index]
            row:SetRecord(record)
            row:SetSelected(record and selected and record.id == selected.id)
        end
    end
    return host
end

