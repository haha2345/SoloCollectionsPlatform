-- DragonUI_NewEra/bootstrap.lua
-- Namespace + DragonUI handshake + SavedVariables. Loads before everything else.
--
-- CONVENTION (downport rule): every ported NewEra file begins with
--     local NE = DragonUI_NewEra
-- instead of NewEra's original `NE = NE or {}` global. This keeps NewEra's
-- pervasive `NE.*` references working with a one-line change per file, while
-- staying collision-safe (no global `NE` leak).

local ADDON = ...

DragonUI_NewEra = DragonUI_NewEra or {}
local NE = DragonUI_NewEra
NE.name    = ADDON
NE.version = "0.2.0"

-- Hard dependency on the base HUD addon. The TOC `## Dependencies: DragonUI`
-- guarantees DragonUI's files have run by the time we parse.
NE.dragon = _G.DragonUI
if not NE.dragon then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555DragonUI_NewEra|r requires DragonUI; not loading.")
    end
    NE.disabled = true
    return
end

-- Optional shim library. compat/ refines this and degrades gracefully if absent.
NE.hasClassicAPI = _G["!!!ClassicAPI"] ~= nil

-- Stable per-character key for per-char data inside the account-wide DB
-- (equipment sets, talent prefs). Mirrors NewEra's NE.CharKey(). Only valid
-- after PLAYER_LOGIN.
function NE.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

-- Simple registry the QA harness reads: panels append { name=, frame=, open=, close= }.
NE.qa = NE.qa or { modules = {} }

-- Localization seam. Keys ARE the English text: NE.L["Retail bags"] returns a registered
-- translation if a locale file set one, else the English key itself. All user-facing NewEra
-- strings should route through NE.L (or, when WoW already ships a localized GLOBAL string like
-- SEARCH/BACKPACK/CHARACTER, prefer that global with an English literal fallback). A future
-- locale file, loaded after this, translates by assigning into it:
--   local L = DragonUI_NewEra.L; if GetLocale() == "deDE" then L["Retail bags"] = "…" end
NE.L = NE.L or setmetatable({}, { __index = function(_, k) return k end })

-- SavedVariables. Our OWN db holds panel-internal per-char state (equipment sets, talent prefs)
-- plus account-wide window positions (db.windowPos[key], see FrameUtil.PersistWindowPosition).
-- Panel ENABLE flags live only in DragonUI's canonical profile.modules.ne_* entries.
-- profile.newera is reserved for panel-internal settings and one-time migration metadata.
local CURRENT_SCHEMA = 3
NE.migrations = NE.migrations or {}
NE.migrations[1] = function(db)
    db.equipmentSets = db.equipmentSets or {}   -- [charKey] = sets
    db.talents       = db.talents       or {}   -- [charKey] = talent prefs
end
NE.migrations[2] = function(db)
    db.companionFavorites = db.companionFavorites or {}  -- [charKey][filterType..":"..creatureID] = true
    db.guildChat = db.guildChat or {}   -- [realm-guildName] = rolling chat log (modules/guild/Chat.lua)
end
NE.migrations[3] = function(db)
    -- Level-up unlocks learned from the live server (modules/levelup/Harvest.lua). Keyed by REALM
    -- first: one installed copy of this addon is expected to be used across several servers, and
    -- what a private server teaches at level 40 must not leak into another's banner.
    db.levelup = db.levelup or {}
    db.levelup.realms = db.levelup.realms or {}   -- [realm] = { classes, bgs, dungeons, talentTotals }
end

local function applyMigrations(db)
    db.schema = db.schema or 0
    while db.schema < CURRENT_SCHEMA do
        local step = NE.migrations[db.schema + 1]
        if not step then break end
        step(db)
        db.schema = db.schema + 1
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    DragonUI_NewEraDB = DragonUI_NewEraDB or {}
    applyMigrations(DragonUI_NewEraDB)
    NE.db = DragonUI_NewEraDB
    NE.ready = true
    if NE.OnReady then NE.OnReady() end   -- integration/Register.lua sets this
    self:UnregisterAllEvents()
end)
