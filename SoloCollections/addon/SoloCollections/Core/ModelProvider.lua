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
        if ok and request.undress and frame.Undress then pcall(frame.Undress, frame) end
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

-- 3.3.5a interpolates M2 animation tracks after the current Lua call returns.
-- ClearModel + SetUnit/TryOn/SetSequence in the same frame can leave EDX as a
-- freed track table and crash at 0x008310AC (ERROR #132). Hide first, then
-- split destroy/rebuild across later OnUpdate ticks and wait for GetModel().
local SafeDressUp = {}
SafeDressUp.__index = SafeDressUp

local dressUpTasks = {}
local dressUpDriver = CreateFrame("Frame")
dressUpDriver:RegisterEvent("PLAYER_ENTERING_WORLD")
dressUpDriver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Provider.playerEnteredAt = GetTime and GetTime() or 0
    end
end)

local function modelPath(frame)
    if not (frame and frame.GetModel) then return nil end
    local ok, value = pcall(frame.GetModel, frame)
    return ok and value and value ~= "" and value or nil
end

local function frameVisible(frame)
    if not frame then return false end
    if frame.IsVisible then
        local ok, value = pcall(frame.IsVisible, frame)
        if ok then return not not value end
    end
    return true
end

local function playerPreviewReady()
    if UnitExists and not UnitExists("player") then return false end
    local entered = Provider.playerEnteredAt
    -- /reload also fires PLAYER_ENTERING_WORLD. A 1.5s lock left every
    -- DressUpModel at alpha 0 after the tooltip reload.
    if entered and GetTime and (GetTime() - entered) < 0.25 then return false end
    return true
end

function Provider.ArmDressUpFrame(frame)
    if not frame then return end
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
    frame.scDressUpArmed = true
end

local function hideModel(frame)
    if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
end

local function showModel(frame)
    if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
end

local function armDressUp(presenter)
    dressUpTasks[presenter] = true
    if not dressUpDriver:GetScript("OnUpdate") then
        dressUpDriver:SetScript("OnUpdate", function(self)
            local active = 0
            for task in pairs(dressUpTasks) do
                if task.destroyed or not task.frame then
                    dressUpTasks[task] = nil
                else
                    task:Step()
                    if task.phase == "idle" and not task.pendingClear then
                        dressUpTasks[task] = nil
                    else
                        active = active + 1
                    end
                end
            end
            if active == 0 then self:SetScript("OnUpdate", nil) end
        end)
    end
end

function SafeDressUp:Step()
    if self.hold then
        self.hold = false
        return
    end
    local frame = self.frame
    if self.pendingClear and (self.phase == "idle" or self.phase == "clearing") then
        if frame.ClearModel then pcall(frame.ClearModel, frame) end
        self.pendingClear = false
        return
    end
    local request = self.request or {}
    if self.phase == "waitvisible" then
        if frameVisible(frame) then
            self.phase = "hide"
        end
        return
    end
    if self.phase == "hide" then
        self.phase = "clear"
        return
    end
    if self.phase == "clear" then
        if frame.ClearModel then pcall(frame.ClearModel, frame) end
        self.phase = "setunit"
        return
    end
    if self.phase == "setunit" then
        if not frameVisible(frame) then
            self.phase = "waitvisible"
            return
        end
        if not playerPreviewReady() then return end
        local ok = frame.SetUnit and pcall(frame.SetUnit, frame, request.unit or "player")
        if not ok then
            showModel(frame)
            self.phase = "idle"
            if type(request.onUnavailable) == "function" then pcall(request.onUnavailable, "set-unit") end
            return
        end
        self.rebuilt = true
        self.phase = "waitmodel"
        self.verifyAttempts = 0
        return
    end
    if self.phase == "waitmodel" then
        self.verifyAttempts = (self.verifyAttempts or 0) + 1
        if modelPath(frame) then
            self.rebuilt = true
            showModel(frame)
            self.phase = "settle"
            return
        end
        if self.verifyAttempts >= 24 then
            if (self.setUnitRetries or 0) > 0 then
                self.setUnitRetries = self.setUnitRetries - 1
                self.verifyAttempts = 0
                -- OnLoad SetUnit while hidden leaves an empty actor. SetUnit
                -- again without ClearModel will not rebuild it on 3.3.5.
                self.phase = "hide"
                return
            end
            showModel(frame)
            self.phase = "idle"
            if type(request.onUnavailable) == "function" then pcall(request.onUnavailable, "model-ready-timeout") end
        end
        return
    end
    if self.phase == "settle" then
        if (self.settleLeft or 0) > 0 then
            self.settleLeft = self.settleLeft - 1
            return
        end
        self.phase = "undress"
        return
    end
    if self.phase == "undress" then
        if request.undress and frame.Undress then pcall(frame.Undress, frame) end
        self.phase = "tryon"
        self.itemIndex = 1
        return
    end
    if self.phase == "tryon" then
        local items = request.items or {}
        local item = items[self.itemIndex]
        if item then
            if frame.TryOn then pcall(frame.TryOn, frame, item) end
            self.itemIndex = self.itemIndex + 1
            return
        end
        if type(request.applyCamera) == "function" then
            pcall(request.applyCamera, frame, request.cameraPose)
        end
        showModel(frame)
        self.phase = "idle"
        if type(request.onReady) == "function" then pcall(request.onReady, self) end
    end
end

function SafeDressUp:Present(request)
    if self.destroyed then return false, "destroyed" end
    self.generation = (self.generation or 0) + 1
    self.request = request or {}
    self.pendingClear = false
    self.itemIndex = 1
    self.settleLeft = math.max(0, tonumber(self.request.settleTicks) or 2)
    local phase = self.phase
    local inFlight = phase and phase ~= "idle" and phase ~= "clearing"
    -- Visible actor: only change clothes. Item cards prove ClearModel+SetUnit
    -- works; the left/set DressUpModels are created on a hidden parent, so
    -- OnLoad SetUnit leaves no GetModel path. Re-SetUnit without ClearModel
    -- does not rebuild that empty actor.
    if modelPath(self.frame) then
        self.rebuilt = true
        self.hold = false
        self.verifyAttempts = 0
        showModel(self.frame)
        if inFlight and (phase == "setunit" or phase == "waitmodel") then
            self.phase = "settle"
        else
            self.phase = "undress"
        end
        armDressUp(self)
        return true, self.generation
    end
    if inFlight and (phase == "waitvisible" or phase == "hide" or phase == "clear"
        or phase == "setunit" or phase == "waitmodel") then
        self.hold = false
        armDressUp(self)
        return true, self.generation
    end
    self.hold = true
    self.verifyAttempts = 0
    self.setUnitRetries = 2
    self.rebuilt = false
    hideModel(self.frame)
    if frameVisible(self.frame) then
        self.phase = "hide"
    else
        self.phase = "waitvisible"
    end
    armDressUp(self)
    return true, self.generation
end

function SafeDressUp:Clear(reason)
    self.generation = (self.generation or 0) + 1
    self.request = nil
    self.phase = "idle"
    self.hold = true
    if reason == "PAGE_HIDDEN" or reason == "KEEP_ACTOR" then
        self.pendingClear = false
        return
    end
    self.pendingClear = true
    hideModel(self.frame)
    armDressUp(self)
end

function SafeDressUp:ResetView()
    if self.frame.SetRotation then pcall(self.frame.SetRotation, self.frame, 0.61) end
    if self.frame.SetPosition then pcall(self.frame.SetPosition, self.frame, 0, 0, 0) end
    return true
end

function SafeDressUp:Destroy()
    self:Clear()
    self.destroyed = true
    self.frame = nil
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
    if kind == "DRESSUP" then
        Provider.ArmDressUpFrame(frame)
        if frame.SetKeepModelOnHide then pcall(frame.SetKeepModelOnHide, frame, true) end
        local presenter = setmetatable({
            kind = kind,
            frame = frame,
            options = options,
            generation = 0,
            phase = "idle",
        }, SafeDressUp)
        if options.controls then
            local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
            if public and public.Model and public.Model.AttachControls then
                public.Model:AttachControls(frame, { rotateButtons = {}, panelCheck = options.panelCheck })
            end
        end
        return presenter
    end
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
