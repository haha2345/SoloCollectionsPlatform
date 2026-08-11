local NE = DragonUI_NewEra
if not NE then return end

NE.model = NE.model or {}
local Lifecycle = NE.model.Lifecycle or {}
NE.model.Lifecycle = Lifecycle

Lifecycle.tasks = Lifecycle.tasks or {}
Lifecycle.driver = Lifecycle.driver or CreateFrame("Frame")

local function update(self, elapsed)
    local ready = {}
    for index = #Lifecycle.tasks, 1, -1 do
        local task = Lifecycle.tasks[index]
        if not task.presenter or task.presenter.destroyed or
            task.presenter.generation ~= task.generation then
            table.remove(Lifecycle.tasks, index)
        else
            task.remaining = task.remaining - elapsed
            if task.remaining <= 0 then
                table.remove(Lifecycle.tasks, index)
                ready[#ready + 1] = task
            end
        end
    end
    if #Lifecycle.tasks == 0 then self:SetScript("OnUpdate", nil) end
    for index = #ready, 1, -1 do
        local task = ready[index]
        if task.presenter.generation == task.generation then pcall(task.callback, task.presenter) end
    end
end

function Lifecycle:Schedule(presenter, generation, delay, callback)
    if not presenter or type(callback) ~= "function" then return false end
    self.tasks[#self.tasks + 1] = {
        presenter = presenter, generation = generation,
        remaining = math.max(0, tonumber(delay) or 0), callback = callback,
    }
    self.driver:SetScript("OnUpdate", update)
    return true
end

function Lifecycle:Cancel(presenter)
    for index = #self.tasks, 1, -1 do
        if self.tasks[index].presenter == presenter then table.remove(self.tasks, index) end
    end
    if #self.tasks == 0 then self.driver:SetScript("OnUpdate", nil) end
end

function Lifecycle:GetPendingCount() return #self.tasks end

