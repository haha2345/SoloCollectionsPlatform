local NE = DragonUI_NewEra
if not (NE and NE.model) then return end

local DressUp = {}

function DressUp:Begin(presenter, request, generation)
    local frame = presenter.frame
    pcall(frame.ClearModel, frame)
    if not frame.SetUnit then presenter:Fail(generation, "set-unit") return end
    local ok = pcall(frame.SetUnit, frame, request.unit or "player")
    if not ok then presenter:Fail(generation, "set-unit") return end
    local items, index = request.items or {}, 1
    local function advance()
        if not presenter:IsCurrent(generation) then return end
        local item = items[index]
        if item then
            if frame.TryOn then pcall(frame.TryOn, frame, item) end
            index = index + 1
            presenter:Schedule(generation, 0, advance)
        else
            if type(request.applyCamera) == "function" then pcall(request.applyCamera, frame, request.cameraPose) end
            presenter:Ready(generation)
        end
    end
    presenter:Schedule(generation, 0, advance)
end

NE.model.Register("DRESSUP", DressUp)

