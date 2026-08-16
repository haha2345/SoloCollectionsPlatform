local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

-- Item cards already render because EzWardrobe does ClearModel / SetUnit /
-- Undress / TryOn on the model's own later frames and does not wait for
-- GetModel(). SafeDressUp shared that wait and left the hidden-created
-- left preview and set cards at alpha 0. This dresser copies the item-card
-- timing onto the target DressUpModel.
function Lab.StopDressUp(model)
    if not model then return end
    model.scDressGeneration = (model.scDressGeneration or 0) + 1
    model.scDressState = nil
    model:SetScript("OnUpdate", nil)
    if model.SetAlpha then pcall(model.SetAlpha, model, 0) end
end

function Lab.PlayDressUp(model, spec)
    if not model then return false end
    spec = spec or {}
    local items = spec.items or {}
    local undress = spec.undress
    local onReady = spec.onReady
    local onUnavailable = spec.onUnavailable
    model.scDressGeneration = (model.scDressGeneration or 0) + 1
    local generation = model.scDressGeneration
    model.scDressState = "prep"
    model.scDressWait = 0
    model.scDressItemIndex = 1
    if model.SetAlpha then pcall(model.SetAlpha, model, 0) end
    model:Show()
    model:SetScript("OnUpdate", function(frame)
        if frame.scDressGeneration ~= generation then
            frame:SetScript("OnUpdate", nil)
            return
        end
        local state = frame.scDressState
        if state == "prep" then
            if frame.SetAutoDress then pcall(frame.SetAutoDress, frame, true) end
            if frame.SetDoBlend then pcall(frame.SetDoBlend, frame, true) end
            if frame.SetKeepModelOnHide then pcall(frame.SetKeepModelOnHide, frame, false) end
            if frame.SetModelScale then pcall(frame.SetModelScale, frame, 1) end
            if frame.SetPosition then pcall(frame.SetPosition, frame, 0, 0, 0) end
            if frame.SetFacing then pcall(frame.SetFacing, frame, 0.61) end
            frame.scDressState = "clear"
            return
        end
        if state == "clear" then
            if frame.ClearModel then pcall(frame.ClearModel, frame) end
            frame.scDressState = "unit"
            return
        end
        if state == "unit" then
            local ok = frame.SetUnit and pcall(frame.SetUnit, frame, "player")
            if not ok then
                frame:SetScript("OnUpdate", nil)
                if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
                if type(onUnavailable) == "function" then pcall(onUnavailable, "set-unit") end
                return
            end
            if frame.SetLight then
                pcall(frame.SetLight, frame, 1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64)
            end
            if frame.SetRotation then pcall(frame.SetRotation, frame, 0.61) end
            frame.scDressState = "dress"
            return
        end
        if state == "dress" then
            -- One frame after SetUnit, same as EzWardrobe rebuildPhase "dress".
            -- Do not require GetModel(); that check is what left these actors
            -- invisible after a hidden OnLoad SetUnit.
            if undress and frame.Undress then pcall(frame.Undress, frame) end
            frame.scDressItemIndex = 1
            frame.scDressState = "tryon"
            return
        end
        if state == "tryon" then
            local item = items[frame.scDressItemIndex]
            if item then
                if frame.TryOn then pcall(frame.TryOn, frame, item) end
                frame.scDressItemIndex = frame.scDressItemIndex + 1
                return
            end
            if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
            frame.scDressState = "idle"
            frame:SetScript("OnUpdate", nil)
            if type(onReady) == "function" then pcall(onReady) end
        end
    end)
    return true
end

function Lab.CreatePreview(parent, state)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetWidth(294)
    model:SetHeight(488)
    model:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -4)
    model:SetFrameLevel(parent:GetFrameLevel() + 2)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    if model.SetAlpha then pcall(model.SetAlpha, model, 0) end
    local unavailable = model:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    unavailable:SetPoint("CENTER"); unavailable:SetText("模型预览不可用"); unavailable:Hide()
    function model:RefreshDraft()
        local items = {}
        for _, itemId in ipairs(state:GetPreviewItemIds()) do
            items[#items + 1] = "item:" .. tostring(itemId)
        end
        local hidden = state.GetHiddenSlots and state:GetHiddenSlots() or {}
        local needUndress = next(hidden) ~= nil
        local signature = table.concat(items, ",")
        if needUndress then signature = signature .. "|H" end
        if self.scDressSignature == signature and self.scDressReady and self.scDressState == "idle" then
            if self.SetAlpha then pcall(self.SetAlpha, self, 1) end
            unavailable:Hide()
            return
        end
        self.scDressSignature = signature
        self.scDressReady = false
        Lab.PlayDressUp(self, {
            items = items,
            undress = needUndress,
            onReady = function()
                model.scDressReady = true
                unavailable:Hide()
            end,
            onUnavailable = function()
                model.scDressReady = false
                unavailable:Show()
            end,
        })
        self.scPreviewItemCount = #items
    end
    model.scUnavailable = unavailable
    return model
end
