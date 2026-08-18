local NE = DragonUI_NewEra
local Public = NE and NE.Public
if not Public then return end

Public.Model = Public.Model or {}

function Public.Model:CreatePresenter(kind, frame, options)
    if not (NE.model and type(NE.model.Create) == "function") then
        return nil, "model-presenter-not-installed"
    end
    return NE.model.Create(kind, frame, options)
end

function Public.Model:AttachControls(model, options)
    if not (NE.model and NE.model.Controls and type(NE.model.Controls.Attach) == "function") then
        return nil, "model-controls-not-installed"
    end
    return NE.model.Controls:Attach(model, options)
end

function Public.Model:GetPendingTaskCount()
    return NE.model and NE.model.Lifecycle and NE.model.Lifecycle:GetPendingCount() or 0
end

Public._SetCapability("model.presenter", NE.model and type(NE.model.Create) == "function")
Public._SetCapability("model.controls", NE.model and NE.model.Controls and type(NE.model.Controls.Attach) == "function")
Public._SetCapability("model.generation-safe", NE.model and NE.model.Lifecycle ~= nil)
