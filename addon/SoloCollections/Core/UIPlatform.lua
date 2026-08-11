local SC = SoloCollections

local Platform = SC.UIPlatform or {}
SC.UIPlatform = Platform

Platform.API_VERSION = 1
Platform.WINDOW_POSITION_KEY = "solocollections-journal"
Platform.requiredCapabilities = {
    "chrome.panel",
    "chrome.persist",
    "chrome.position-migration",
    "modules.feature-registry",
}

local function copyPosition(source)
    if type(source) ~= "table" then return nil end
    return {
        point = source.point,
        relativePoint = source.relativePoint or source.relPoint,
        x = tonumber(source.x) or 0,
        y = tonumber(source.y) or 0,
    }
end

function Platform:ShowError(reason)
    if self.errorShown then return end
    self.errorShown = true
    local message = "|cffff5555SoloCollections UI disabled:|r DragonUI_NewEra Public API unavailable"
    if reason then message = message .. " (" .. tostring(reason) .. ")" end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

function Platform:Initialize()
    local public = DragonUI_NewEra and DragonUI_NewEra.Public
    if not public or type(public.Require) ~= "function" then
        self.ready = false
        self.reason = "public-api"
        return false, self.reason
    end
    local ok, missing = public.Require(self.API_VERSION, self.requiredCapabilities)
    if not ok then
        self.ready = false
        self.reason = missing or "capability"
        return false, self.reason
    end
    self.public = public
    self.ready = true
    self.reason = nil
    return true
end

function Platform:IsReady()
    if self.ready == nil then self:Initialize() end
    return self.ready == true
end

function Platform:CanCreateUI()
    if self:IsReady() then return true end
    self:ShowError(self.reason)
    return false
end

function Platform:GetPublic()
    if not self:IsReady() then return nil end
    return self.public
end

function Platform:GetShellMode()
    local settings = SC.db and SC.db.uiPlatform
    local mode = settings and settings.uiShell or SC.DEFAULT_UI_SHELL
    if mode ~= "LEGACY" then return "DRAGONUI" end
    return "LEGACY"
end

function Platform:IsDragonUIShell()
    return self:IsReady() and self:GetShellMode() == "DRAGONUI"
end

function Platform:SetShellMode(mode)
    if not SC.db then return false end
    mode = string.upper(tostring(mode or ""))
    if mode ~= "LEGACY" and mode ~= "DRAGONUI" then return false end
    SC.db.uiPlatform = SC.db.uiPlatform or {}
    SC.db.uiPlatform.uiShell = mode
    return true
end

function Platform:GetLegacyFramePosition()
    local settings = SC.db and SC.db.uiPlatform
    return copyPosition((settings and settings.legacyFrameBackup) or (SC.db and SC.db.frame))
end

function Platform:PersistWindow(frame, dragHandle)
    if not (frame and self:IsDragonUIShell()) then return false end
    local public = self.public
    local settings = SC.db.uiPlatform
    if not settings.positionMigrated then
        local legacy = copyPosition(SC.db.frame)
        if legacy then
            settings.legacyFrameBackup = settings.legacyFrameBackup or legacy
            public.Chrome:MigrateWindowPosition(self.WINDOW_POSITION_KEY, legacy)
        end
        settings.positionMigrated = true
        SC.db.frame = nil
    end
    local fallback = settings.legacyFrameBackup or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    return public.Chrome:PersistWindowPosition(frame, self.WINDOW_POSITION_KEY, {
        point = fallback.point,
        relPoint = fallback.relativePoint,
        x = fallback.x,
        y = fallback.y,
    }, dragHandle)
end

function Platform:RestoreWindow(frame)
    if not (frame and self:IsDragonUIShell()) then return false end
    local fallback = self:GetLegacyFramePosition() or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    return self.public.Chrome:RestoreWindowPosition(frame, self.WINDOW_POSITION_KEY, {
        point = fallback.point,
        relPoint = fallback.relativePoint,
        x = fallback.x,
        y = fallback.y,
    })
end

function Platform:ResetWindowPosition()
    if self:IsReady() then self.public.Chrome:ResetWindowPosition(self.WINDOW_POSITION_KEY) end
    if SC.db and SC.db.uiPlatform then
        SC.db.uiPlatform.positionMigrated = false
        SC.db.uiPlatform.legacyFrameBackup = nil
    end
end

function Platform:RegisterFeature()
    if self.featureRegistered or not self:IsReady() then return self.featureRegistered == true end
    local UI = SC.UI
    local module, reason = self.public.Modules:RegisterFeature({
        id = "solocollections",
        title = "Solo Collections",
        description = "Server-authoritative collection journal.",
        open = UI.ToggleJournal,
        close = UI.HideJournal,
        refresh = UI.RefreshActivePage,
    })
    if not module then
        self.reason = reason or "feature-registration"
        self:ShowError(self.reason)
        return false
    end
    self.featureRegistered = true
    return true
end

Platform:Initialize()
