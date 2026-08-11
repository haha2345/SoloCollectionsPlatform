local SC = SoloCollections

local Provider = SC.ModelProvider or {}
SC.ModelProvider = Provider

Provider.DIRECT_DISPLAY_REQUEST_BASE = 0x6F000000

local Disabled = {}
Disabled.__index = Disabled
function Disabled:Present(request)
    local callback = request and request.onUnavailable
    if type(callback) == "function" then pcall(callback, self.reason) end
    return false, self.reason
end
function Disabled:Clear() end
function Disabled:ResetView() return false end
function Disabled:Destroy() end

local Legacy = {}
Legacy.__index = Legacy
function Legacy:Present(request)
    self.generation = self.generation + 1
    local frame, generation = self.frame, self.generation
    request = request or {}
    if frame.ClearModel then pcall(frame.ClearModel, frame) end
    local ok = false
    if self.kind == "CREATURE" then
        local function load()
            if self.generation ~= generation then return end
            ok = request.creatureEntry and frame.SetCreature and pcall(frame.SetCreature, frame, request.creatureEntry)
            local callback = ok and request.onReady or request.onUnavailable
            if type(callback) == "function" then pcall(callback, ok and self or "set-creature") end
        end
        if type(request.preview) == "function" then
            request.preview(function(accepted, reason)
                if accepted then load()
                elseif type(request.onUnavailable) == "function" then request.onUnavailable(reason) end
            end)
        else load() end
    elseif self.kind == "DRESSUP" then
        ok = frame.SetUnit and pcall(frame.SetUnit, frame, request.unit or "player")
        for _, item in ipairs(request.items or {}) do if frame.TryOn then pcall(frame.TryOn, frame, item) end end
        local callback = ok and request.onReady or request.onUnavailable
        if type(callback) == "function" then pcall(callback, ok and self or "set-unit") end
    elseif self.kind == "DISPLAY" then
        ok = request.displayId and frame.SetCreature and
            pcall(frame.SetCreature, frame, Provider.DIRECT_DISPLAY_REQUEST_BASE + request.displayId)
        local callback = ok and request.onReady or request.onUnavailable
        if type(callback) == "function" then pcall(callback, ok and self or "set-display") end
    end
    return ok, generation
end
function Legacy:Clear()
    self.generation = self.generation + 1
    if self.frame and self.frame.ClearModel then pcall(self.frame.ClearModel, self.frame) end
end
function Legacy:ResetView()
    if self.frame.SetRotation then pcall(self.frame.SetRotation, self.frame, 0.61) end
    if self.frame.SetPosition then pcall(self.frame.SetPosition, self.frame, 0, 0, 0) end
    return true
end
function Legacy:Destroy() self:Clear(); self.frame = nil end

local function mode(kind)
    local experimental = SC.db and SC.db.experimental
    local value = experimental and experimental.modelProviderByKind and experimental.modelProviderByKind[kind]
        or (experimental and experimental.modelProvider)
    return value == "legacy" and "legacy" or "newera"
end

local function displayLoader(frame, request, done)
    local displayId = tonumber(request.displayId)
    if not displayId or not frame.SetCreature then done(false, "display-id") return end
    local ok, reason = pcall(frame.SetCreature, frame, Provider.DIRECT_DISPLAY_REQUEST_BASE + displayId)
    done(ok, ok and nil or reason)
end

function Provider.Create(kind, frame, options)
    kind = string.upper(tostring(kind or ""))
    options = options or {}
    if mode(kind) == "legacy" then
        return setmetatable({ kind = kind, frame = frame, generation = 0 }, Legacy)
    end
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if not (public and public.Model and type(public.Model.CreatePresenter) == "function") then
        return setmetatable({ reason = "public-model-api" }, Disabled)
    end
    if kind == "DISPLAY" and not options.loadDisplay then options.loadDisplay = displayLoader end
    local presenter, reason = public.Model:CreatePresenter(kind, frame, options)
    if not presenter then return setmetatable({ reason = reason or ("provider-" .. kind) }, Disabled) end
    if options.controls and public.Model.AttachControls then
        public.Model:AttachControls(frame, { rotateButtons = {}, panelCheck = options.panelCheck })
    end
    return presenter
end

function Provider.GetMode(kind) return mode(string.upper(tostring(kind or ""))) end
