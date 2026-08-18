local NE = DragonUI_NewEra
if not (NE and NE.model) then return end

local Display = {}

function Display:Begin(presenter, request, generation)
    local frame = presenter.frame
    pcall(frame.ClearModel, frame)
    local loader = request.loadDisplay or presenter.options.loadDisplay
    if type(loader) ~= "function" then presenter:Fail(generation, "display-loader") return end
    local completed = false
    local ok, reason = pcall(loader, frame, request, function(accepted, failure)
        if completed or not presenter:IsCurrent(generation) then return end
        completed = true
        if not accepted then presenter:Fail(generation, failure or "display-rejected") return end
        local attempts = 0
        local function verify()
            if not presenter:IsCurrent(generation) then return end
            attempts = attempts + 1
            local ready = true
            if frame.GetModel then
                local got, path = pcall(frame.GetModel, frame)
                ready = got and path and path ~= ""
            end
            if ready then
                if type(request.applyCamera) == "function" then pcall(request.applyCamera, frame, request.cameraPose) end
                presenter:Ready(generation)
            elseif attempts < 12 then presenter:Schedule(generation, 0.08, verify)
            else presenter:Fail(generation, "display-ready-timeout") end
        end
        presenter:Schedule(generation, 0, verify)
    end)
    if not ok then presenter:Fail(generation, reason) end
end

NE.model.Register("DISPLAY", Display)
