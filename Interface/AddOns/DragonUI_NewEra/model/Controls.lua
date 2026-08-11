local NE = DragonUI_NewEra
if not NE then return end

NE.model = NE.model or {}
NE.model.Controls = NE.model.Controls or {}

function NE.model.Controls:Attach(model, options)
    local builder = NE.charpanel and NE.charpanel.BuildModelControls
    if type(builder) ~= "function" then return nil, "controls-not-loaded" end
    local ok, result = pcall(builder, model, options or {})
    if not ok then return nil, tostring(result) end
    return result or (model and model._neControlBar), nil
end

function NE.model.Controls:Reset(model)
    if not model then return false end
    if model.SetRotation then pcall(model.SetRotation, model, 0.61); model.rotation = 0.61 end
    if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
    if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
    if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
    return true
end

