local NE = DragonUI_NewEra
local Public = NE and NE.Public
if not Public then return end

Public.Model = Public.Model or {}

function Public.Model:CreatePresenter()
    return nil, "model-presenter-not-installed"
end

function Public.Model:AttachControls()
    return nil, "model-controls-not-installed"
end

-- Task 7 installs the shared presenter service and flips these capabilities.
Public._SetCapability("model.presenter", false)
Public._SetCapability("model.controls", false)

