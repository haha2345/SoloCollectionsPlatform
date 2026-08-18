local NE = DragonUI_NewEra
if not NE then return end

NE.model = NE.model or {}
local Model = NE.model
Model.implementations = Model.implementations or {}

local Presenter = {}
Presenter.__index = Presenter

function Model.Register(kind, implementation)
    if type(kind) ~= "string" or type(implementation) ~= "table" then return false end
    Model.implementations[string.upper(kind)] = implementation
    return true
end

function Model.Create(kind, frame, options)
    kind = string.upper(tostring(kind or ""))
    local implementation = Model.implementations[kind]
    if not implementation or not frame then return nil, "presenter-unavailable:" .. kind end
    return setmetatable({
        kind = kind, frame = frame, options = options or {}, implementation = implementation,
        generation = 0, state = "IDLE", destroyed = false,
    }, Presenter)
end

function Presenter:IsCurrent(generation)
    return not self.destroyed and self.generation == generation
end

function Presenter:Schedule(generation, delay, callback)
    return Model.Lifecycle:Schedule(self, generation, delay, callback)
end

function Presenter:SetState(state, reason)
    self.state, self.reason = state, reason
    local callback = self.options.onState
    if type(callback) == "function" then pcall(callback, self, state, reason) end
end

function Presenter:Present(request)
    if self.destroyed then return false, "destroyed" end
    self.generation = self.generation + 1
    local generation = self.generation
    Model.Lifecycle:Cancel(self)
    self.request = request or {}
    self:SetState("LOADING")
    local ok, reason = pcall(self.implementation.Begin, self.implementation, self, self.request, generation)
    if not ok then
        self:SetState("FAILED", reason)
        local callback = self.request.onUnavailable or self.options.onUnavailable
        if type(callback) == "function" then pcall(callback, reason) end
        return false, reason
    end
    return true, generation
end

function Presenter:Ready(generation)
    if not self:IsCurrent(generation) then return false end
    self:SetState("READY")
    local callback = self.request and (self.request.onReady or self.options.onReady)
    if type(callback) == "function" then pcall(callback, self) end
    return true
end

function Presenter:Fail(generation, reason)
    if not self:IsCurrent(generation) then return false end
    self:SetState("FAILED", reason)
    if self.frame and self.frame.ClearModel then pcall(self.frame.ClearModel, self.frame) end
    local callback = self.request and (self.request.onUnavailable or self.options.onUnavailable)
    if type(callback) == "function" then pcall(callback, reason) end
    return true
end

function Presenter:Clear(reason)
    self.generation = self.generation + 1
    Model.Lifecycle:Cancel(self)
    if self.implementation.Clear then pcall(self.implementation.Clear, self.implementation, self) end
    if self.frame and self.frame.ClearModel then pcall(self.frame.ClearModel, self.frame) end
    self.request = nil
    self:SetState("IDLE", reason)
end

function Presenter:ResetView()
    if self.implementation.ResetView then return self.implementation:ResetView(self) end
    return Model.Controls:Reset(self.frame)
end

function Presenter:Destroy()
    self:Clear("DESTROYED"); self.destroyed = true; self.frame = nil
end

Model.Presenter = Presenter
