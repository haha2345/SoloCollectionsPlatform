local SC = SoloCollections
local Lab = SC.WardrobeLab
if not Lab then return end

local DEFAULT_ROTATION = 0.61
local TWO_PI = math.pi * 2
local DRAG_ROTATION_CONSTANT = tonumber(MODELFRAME_DRAG_ROTATION_CONSTANT) or 0.010
local MIN_ZOOM = -0.7
local MAX_ZOOM = 0.7
local ZOOM_STEP = 0.08

-- Item cards already render because EzWardrobe does ClearModel / SetUnit /
-- Undress / TryOn on the model's own later frames and does not wait for
-- GetModel(). SafeDressUp shared that wait and left the hidden-created
-- left preview and set cards at alpha 0. This dresser copies the item-card
-- timing onto the target DressUpModel.

local function applyPreviewCamera(model)
    if not model then return end
    local rotation = model.scRotation or DEFAULT_ROTATION
    local zoom = model.scZoom or 0
    if model.SetFacing then
        pcall(model.SetFacing, model, rotation)
    elseif model.SetRotation then
        pcall(model.SetRotation, model, rotation, false)
    end
    if model.SetPosition then
        pcall(model.SetPosition, model, 0, 0, zoom)
    end
end

local function stepPreviewDrag(frame)
    if not frame.scDragging or not IsMouseButtonDown("LeftButton") then
        frame.scDragging = nil
        frame.scLastCursorX = nil
        return
    end
    local cursorX = GetCursorPosition()
    local previousX = frame.scLastCursorX or cursorX
    frame.scLastCursorX = cursorX
    local delta = (cursorX - previousX) * DRAG_ROTATION_CONSTANT
    if delta == 0 then return end
    frame.scRotation = (frame.scRotation or DEFAULT_ROTATION) + delta
    if frame.scRotation < 0 then frame.scRotation = frame.scRotation + TWO_PI end
    if frame.scRotation > TWO_PI then frame.scRotation = frame.scRotation - TWO_PI end
    applyPreviewCamera(frame)
end

function Lab.StepDressUp(frame)
    if not frame then return end
    if frame.scDressGeneration ~= frame.scDressToken then
        if not frame.scPreviewDriver then
            frame:SetScript("OnUpdate", nil)
        end
        return
    end
    local state = frame.scDressState
    local items = frame.scDressItems or {}
    local undress = frame.scDressUndress
    local onReady = frame.scDressOnReady
    local onUnavailable = frame.scDressOnUnavailable
    if state == "prep" then
        if frame.SetAutoDress then pcall(frame.SetAutoDress, frame, true) end
        if frame.SetDoBlend then pcall(frame.SetDoBlend, frame, true) end
        if frame.SetKeepModelOnHide then pcall(frame.SetKeepModelOnHide, frame, false) end
        if frame.SetModelScale then pcall(frame.SetModelScale, frame, 1) end
        if not frame.scPreviewDriver then
            if frame.SetPosition then pcall(frame.SetPosition, frame, 0, 0, 0) end
            if frame.SetFacing then pcall(frame.SetFacing, frame, DEFAULT_ROTATION) end
        end
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
            if not frame.scPreviewDriver then
                frame:SetScript("OnUpdate", nil)
            end
            if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
            if type(onUnavailable) == "function" then pcall(onUnavailable, "set-unit") end
            return
        end
        if frame.SetLight then
            pcall(frame.SetLight, frame, 1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64)
        end
        if not frame.scPreviewDriver and frame.SetRotation then
            pcall(frame.SetRotation, frame, DEFAULT_ROTATION)
        end
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
        if frame.scPreviewDriver then
            applyPreviewCamera(frame)
        end
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
        frame.scDressState = "idle"
        if not frame.scPreviewDriver then
            frame:SetScript("OnUpdate", nil)
        end
        if type(onReady) == "function" then pcall(onReady) end
    end
end

function Lab.StopDressUp(model)
    if not model then return end
    model.scDressGeneration = (model.scDressGeneration or 0) + 1
    model.scDressState = nil
    if not model.scPreviewDriver then
        model:SetScript("OnUpdate", nil)
    end
    if model.SetAlpha then pcall(model.SetAlpha, model, 0) end
end

function Lab.PlayDressUp(model, spec)
    if not model then return false end
    spec = spec or {}
    model.scDressGeneration = (model.scDressGeneration or 0) + 1
    model.scDressToken = model.scDressGeneration
    model.scDressItems = spec.items or {}
    model.scDressUndress = spec.undress
    model.scDressOnReady = spec.onReady
    model.scDressOnUnavailable = spec.onUnavailable
    model.scDressState = "prep"
    model.scDressWait = 0
    model.scDressItemIndex = 1
    if model.SetAlpha then pcall(model.SetAlpha, model, 0) end
    model:Show()
    if not model.scPreviewDriver then
        model:SetScript("OnUpdate", function(frame)
            Lab.StepDressUp(frame)
        end)
    end
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
    model.scPreviewDriver = true
    model.scRotation = DEFAULT_ROTATION
    model.scZoom = 0
    if model.SetAlpha then pcall(model.SetAlpha, model, 0) end
    local unavailable = model:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    unavailable:SetPoint("CENTER"); unavailable:SetText("模型预览不可用"); unavailable:Hide()

    function model:ResetCamera()
        self.scDragging = nil
        self.scLastCursorX = nil
        self.scRotation = DEFAULT_ROTATION
        self.scZoom = 0
        applyPreviewCamera(self)
    end

    model:SetScript("OnUpdate", function(frame)
        if frame.scDressState and frame.scDressState ~= "idle" then
            Lab.StepDressUp(frame)
            return
        end
        if frame.scDragging then
            stepPreviewDrag(frame)
        end
    end)
    model:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self.scDragging = true
        self.scLastCursorX = GetCursorPosition()
    end)
    model:SetScript("OnMouseUp", function(self)
        self.scDragging = nil
        self.scLastCursorX = nil
    end)
    model:SetScript("OnHide", function(self)
        self.scDragging = nil
        self.scLastCursorX = nil
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        self.scZoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, (self.scZoom or 0) + delta * ZOOM_STEP))
        applyPreviewCamera(self)
    end)

    local reset = CreateFrame("Button", nil, parent)
    reset:SetWidth(32)
    reset:SetHeight(32)
    reset:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT", 2, 6)
    reset:SetFrameLevel(parent:GetFrameLevel() + 20)
    reset:SetNormalTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
    reset:SetPushedTexture("Interface\\Buttons\\UI-RotationRight-Button-Down")
    reset:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    reset:SetScript("OnClick", function()
        model:ResetCamera()
    end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("重置镜头", 1, 0.82, 0.18)
        GameTooltip:AddLine("恢复默认朝向和距离。换装后仍会记住你刚才的拖转和缩放。", 0.72, 0.72, 0.72, true)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
            applyPreviewCamera(self)
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
    model.scResetCamera = reset
    return model
end
