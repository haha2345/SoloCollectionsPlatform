local NE = DragonUI_NewEra
if not (NE and NE.model) then return end

local Creature = {}

local function modelPath(frame)
    if not (frame and frame.GetModel) then return nil end
    local ok, value = pcall(frame.GetModel, frame)
    return ok and value and value ~= "" and value or nil
end

function Creature:Begin(presenter, request, generation)
    local frame = presenter.frame
    pcall(frame.ClearModel, frame)
    local function load()
        if not presenter:IsCurrent(generation) then return end
        local entry = tonumber(request.creatureEntry or request.creatureID)
        if not entry or not frame.SetCreature then presenter:Fail(generation, "creature-entry") return end
        local ok = pcall(frame.SetCreature, frame, entry)
        if not ok then presenter:Fail(generation, "set-creature") return end
        local attempts = 0
        local function verify()
            if not presenter:IsCurrent(generation) then return end
            attempts = attempts + 1
            if modelPath(frame) then
                if request.rotation and frame.SetRotation then
                    pcall(frame.SetRotation, frame, request.rotation); frame.rotation = request.rotation
                end
                presenter:Ready(generation)
            elseif attempts < 7 then presenter:Schedule(generation, 0.12, verify)
            else presenter:Fail(generation, "model-ready-timeout") end
        end
        presenter:Schedule(generation, 0, verify)
    end
    if type(request.preview) == "function" then
        local completed = false
        local ok, reason = pcall(request.preview, function(accepted, failure)
            if completed or not presenter:IsCurrent(generation) then return end
            completed = true
            if accepted then presenter:Schedule(generation, 0, load)
            else presenter:Fail(generation, failure or "preview-rejected") end
        end)
        if not ok then presenter:Fail(generation, reason) end
    else load() end
end

NE.model.Register("CREATURE", Creature)

