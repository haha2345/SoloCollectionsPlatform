local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

function Lab.CreatePreview(parent, state)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetWidth(294)
    model:SetHeight(488)
    model:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -4)
    model:SetFrameLevel(parent:GetFrameLevel() + 2)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    local unavailable = model:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    unavailable:SetPoint("CENTER"); unavailable:SetText("模型预览不可用"); unavailable:Hide()
    local presenter = SC.ModelProvider and SC.ModelProvider.Create and
        SC.ModelProvider.Create("DRESSUP", model, { controls = true }) or nil
    function model:RefreshDraft()
        self.scGeneration = (self.scGeneration or 0) + 1
        local expectedGeneration = self.scGeneration
        local items = {}
        for _, itemId in ipairs(state:GetPreviewItemIds()) do
            items[#items + 1] = "item:" .. tostring(itemId)
        end
        if presenter then
            presenter:Present({
                unit = "player",
                items = items,
                settleTicks = 2,
                onReady = function()
                    if model.scGeneration == expectedGeneration then unavailable:Hide() end
                end,
                onUnavailable = function()
                    if model.scGeneration == expectedGeneration then unavailable:Show() end
                end,
            })
        else
            self:ClearModel(); pcall(self.SetUnit, self, "player")
            for _, item in ipairs(items) do pcall(self.TryOn, self, item) end
        end
        self.scPreviewItemCount = #items
    end
    model.scPresenter, model.scUnavailable = presenter, unavailable
    return model
end
