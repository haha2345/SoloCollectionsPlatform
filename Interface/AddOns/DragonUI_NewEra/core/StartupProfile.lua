local NE = DragonUI_NewEra
if not NE then return end

local function database()
    return _G.DragonUI_NewEraDB or NE.db
end

local function profilingEnabled()
    local db = database()
    return type(db) == "table" and db.debugStartupProfile == true
end

-- Lightweight, opt-in startup evidence. The default path has no event watcher,
-- no per-frame work, and no SavedVariables mutation.
local Profile = {
    startedAt = type(debugprofilestop) == "function" and debugprofilestop() or 0,
    events = {},
    counts = {},
    initialized = false,
}
NE.StartupProfile = Profile

function Profile:IsEnabled()
    return profilingEnabled()
end

function Profile:Mark(kind, id, detail)
    if not self:IsEnabled() then return end
    self.events[#self.events + 1] = {
        at = (type(debugprofilestop) == "function" and debugprofilestop() or 0) - self.startedAt,
        kind = kind,
        id = id,
        detail = detail,
    }
    self.counts[kind] = (self.counts[kind] or 0) + 1
end

function Profile:SaveSample(reason)
    if not self:IsEnabled() then return end
    local db = database()
    if type(db) ~= "table" then return end

    db.startupProfile = type(db.startupProfile) == "table" and db.startupProfile or {}
    local samples = db.startupProfile.samples
    if type(samples) ~= "table" then
        samples = {}
        db.startupProfile.samples = samples
    end

    local events = {}
    for i, event in ipairs(self.events) do
        events[i] = {
            at = event.at,
            kind = event.kind,
            id = event.id,
            detail = event.detail,
        }
    end
    local counts = {}
    for kind, count in pairs(self.counts) do counts[kind] = count end

    samples[#samples + 1] = {
        reason = reason,
        elapsedMs = (type(debugprofilestop) == "function" and debugprofilestop() or 0) - self.startedAt,
        events = events,
        counts = counts,
    }
    while #samples > 20 do table.remove(samples, 1) end
end

function Profile:Report()
    if not self:IsEnabled() then
        return { "Startup profile disabled; set DragonUI_NewEraDB.debugStartupProfile = true and /reload." }
    end
    local lines = {
        string.format("NewEra startup profile: %.1f ms, %d lifecycle events", (type(debugprofilestop) == "function" and debugprofilestop() or 0) - self.startedAt, #self.events),
    }
    for _, event in ipairs(self.events) do
        lines[#lines + 1] = string.format("  +%.1fms %-8s %s", event.at, event.kind, tostring(event.id or ""))
    end
    return lines
end

function Profile:Initialize()
    if self.initialized then return self:IsEnabled() end
    self.initialized = true
    if not self:IsEnabled() then return false end

    self:Mark("event", "ADDON_LOADED", NE.name)
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
        watcher:RegisterEvent(event)
    end
    watcher:SetScript("OnEvent", function(_, event, addonName)
        Profile:Mark("event", event, addonName)
        if event == "PLAYER_ENTERING_WORLD" then
            Profile:SaveSample(event)
        end
    end)
    Profile.watcher = watcher
    return true
end

SLASH_DRAGONUINEWPROFILE1 = "/neprofile"
SlashCmdList.DRAGONUINEWPROFILE = function()
    for _, line in ipairs(Profile:Report()) do
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff55ddffDragonUI_NewEra|r " .. line) end
    end
end
