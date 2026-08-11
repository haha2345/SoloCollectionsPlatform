local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

function Lab.CreatePreview(parent, state)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -44)
    model:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 188)
    local unavailable = model:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    unavailable:SetPoint("CENTER"); unavailable:SetText("模型预览不可用"); unavailable:Hide()
    local presenter = SC.ModelProvider and SC.ModelProvider.Create and
        SC.ModelProvider.Create("DRESSUP", model, { controls = true }) or nil
    local function itemString(record)
        local itemId = record and (record.itemId or (record.itemIds and record.itemIds[1]))
        return itemId and ("item:" .. tostring(itemId)) or nil
    end
    function model:RefreshDraft()
        local items = {}
        for _, definition in ipairs(Lab.SLOTS) do
            local item = itemString(state.draftBySlot[definition.key])
            if item then items[#items + 1] = item end
        end
        if presenter then
            presenter:Present({ unit = "player", items = items,
                onReady = function() unavailable:Hide() end,
                onUnavailable = function() unavailable:Show() end })
        else
            self:ClearModel(); pcall(self.SetUnit, self, "player")
            for _, item in ipairs(items) do pcall(self.TryOn, self, item) end
        end
    end
    model.scPresenter, model.scUnavailable = presenter, unavailable
    return model
end
