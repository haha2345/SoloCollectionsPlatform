local NE = DragonUI_NewEra
local Public = NE and NE.Public
if not Public then return end

local Callbacks = Public.Callbacks or { events = {} }
Public.Callbacks = Callbacks

function Callbacks:Register(event, owner, callback)
    if not event or owner == nil or type(callback) ~= "function" then return false end
    local list = self.events[event] or {}
    self.events[event] = list
    list[#list + 1] = { owner = owner, callback = callback }
    return true
end

function Callbacks:UnregisterOwner(owner)
    for event, list in pairs(self.events) do
        local kept = {}
        for _, entry in ipairs(list) do
            if entry.owner ~= owner then kept[#kept + 1] = entry end
        end
        self.events[event] = kept
    end
end

function Callbacks:Fire(event, ...)
    for _, entry in ipairs(self.events[event] or {}) do
        local ok, err = pcall(entry.callback, entry.owner, ...)
        if not ok and NE._warn then NE._warn("callback " .. tostring(event) .. " failed: " .. tostring(err)) end
    end
end

Public._SetCapability("callbacks.owner-scoped", true)

local Modules = Public.Modules or {}
Public.Modules = Modules

function Modules:RegisterFeature(spec)
    if type(spec) ~= "table" or not spec.id then return nil, "feature-id" end
    if not NE.RegisterPanel then return nil, "register-panel" end
    return NE.RegisterPanel({
        id = spec.id,
        title = spec.title,
        desc = spec.description or spec.desc,
        frame = spec.frame,
        openFn = spec.open,
        closeFn = spec.close,
        refreshFn = spec.refresh,
        defaultPoint = spec.defaultPoint,
        order = spec.order,
    })
end

function Modules:IsEnabled(id)
    return NE.modules and NE.modules.IsEnabled and NE.modules.IsEnabled(id) or false
end

Public._SetCapability("modules.feature-registry", type(NE.RegisterPanel) == "function")

