-- DragonUI_NewEra/core/LoadOnDemandRoutes.lua
--
-- The base addon owns only the small route table. Heavy panel code is loaded
-- after an explicit user action or the business event that needs it.

local NE = DragonUI_NewEra
if not NE then return end

local Routes = NE.LoadOnDemandRoutes or {}
NE.LoadOnDemandRoutes = Routes
Routes.loaded = Routes.loaded or {}
Routes.booted = Routes.booted or {}
Routes.originals = Routes.originals or {}
Routes.wrappers = Routes.wrappers or {}

local SPECS = {
    Character = { addon = "DragonUI_NewEra_Character", namespace = "charpanel", profile = "character", default = false },
    Collections = { addon = "DragonUI_NewEra_Collections", namespace = "collections", default = false },
    Spellbook = { addon = "DragonUI_NewEra_Spellbook", namespace = "spellbook", default = true },
    Talents = { addon = "DragonUI_NewEra_Talents", namespace = "talents", default = true },
    Bags = { addon = "DragonUI_NewEra_Bags", namespace = "combinedbag", profile = "combinedbag", default = false },
    Professions = { addon = "DragonUI_NewEra_Professions", namespace = "profcraft", default = true },
    AuctionHouse = { addon = "DragonUI_NewEra_AuctionHouse", namespace = "ah", default = true },
    Social = { addon = "DragonUI_NewEra_Social", namespace = "social", default = true },
    Guild = { addon = "DragonUI_NewEra_Social", namespace = "guild", default = true },
    LFG = { addon = "DragonUI_NewEra_Social", namespace = "lfg", default = true },
    EncounterJournal = { addon = "DragonUI_NewEra_EncounterJournal", namespace = "ej", default = true },
    CooldownViewer = { addon = "DragonUI_NewEra_CooldownViewer", namespace = "cooldownviewer", default = false },
    LevelUp = { addon = "DragonUI_NewEra_LevelUp", namespace = "levelup", default = false },
}

local function log(message)
    if NE.Log then
        NE.Log("LOD", message)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [LOD]: " .. tostring(message))
    end
end

local function profileEnabled(id, fallback)
    local modules = NE.modules
    local tableRef = modules and modules._dragonModulesTable and modules._dragonModulesTable(false)
    local profileId = (SPECS[id] and SPECS[id].profile) or id
    local key = modules and modules.CanonicalName and modules.CanonicalName(profileId) or ("ne_" .. profileId)
    local row = tableRef and tableRef[key]
    if row and row.enabled ~= nil then return row.enabled and true or false end
    return fallback and true or false
end

local function isLoaded(addon)
    return type(IsAddOnLoaded) == "function" and IsAddOnLoaded(addon) and true or false
end

function Routes.Load(id)
    local spec = SPECS[id]
    if not spec then return false, "unknown-route" end
    if Routes.loaded[id] or isLoaded(spec.addon) then
        Routes.loaded[id] = true
        return true
    end
    if type(LoadAddOn) ~= "function" then return false, "LoadAddOn-unavailable" end
    local ok, reason = LoadAddOn(spec.addon)
    if not ok and not isLoaded(spec.addon) then
        log("LoadAddOn failed for " .. spec.addon .. ": " .. tostring(reason))
        return false, reason or "load-failed"
    end
    Routes.loaded[id] = true
    return true
end

local function invoke(object, method, ...)
    if not (object and type(object[method]) == "function") then
        return false, "entry-missing"
    end
    local ok, result = pcall(object[method], ...)
    if not ok then
        log("route " .. tostring(method) .. " failed: " .. tostring(result))
        return false, result
    end
    return true, result
end

local function bootOnce(id)
    if Routes.booted[id] then return true end
    local spec = SPECS[id]
    local object = spec and NE[spec.namespace]
    local boot = object and object.Boot
    if type(boot) == "function" then
        local ok, err = pcall(boot, "PLAYER_LOGIN")
        if not ok then
            log("boot " .. id .. " failed: " .. tostring(err))
            return false, err
        end
    end
    Routes.booted[id] = true
    return true
end

function Routes.Open(id, method, ...)
    local spec = SPECS[id]
    if not spec then return false, "unknown-route" end
    if not profileEnabled(id, spec.default) then return false, "disabled" end
    local ok, err = Routes.Load(id)
    if not ok then return false, err end
    ok, err = bootOnce(id)
    if not ok then return false, err end
    local object = NE[spec.namespace]
    return invoke(object, method or "Toggle", ...)
end

function Routes.Close(id)
    local spec = SPECS[id]
    if not spec or not Routes.loaded[id] then return false end
    return invoke(NE[spec.namespace], "Hide")
end

local function wrapGlobal(name, id, method)
    local original = _G[name]
    if Routes.wrappers[name] == original then return end
    if type(original) ~= "function" then return end
    Routes.originals[name] = original
    local routed = function(...)
        if profileEnabled(id, SPECS[id].default) then
            local ok = Routes.Open(id, method, ...)
            if ok then return end
        end
        return original(...)
    end
    Routes.wrappers[name] = routed
    _G[name] = routed
end

local function installRoutes()
    local originalCharacter = _G.ToggleCharacter
    if Routes.wrappers.ToggleCharacter ~= originalCharacter and type(originalCharacter) == "function" then
        Routes.originals.ToggleCharacter = originalCharacter
        local routedCharacter = function(whichTab)
            if profileEnabled("Character", SPECS.Character.default) then
                local ok = Routes.Open("Character", "Toggle", true, whichTab)
                if ok then return end
            end
            return originalCharacter(whichTab)
        end
        Routes.wrappers.ToggleCharacter = routedCharacter
        _G.ToggleCharacter = routedCharacter
    end
    wrapGlobal("ToggleSpellBook", "Spellbook", "Toggle")
    wrapGlobal("ToggleTalentFrame", "Talents", "Toggle")
    wrapGlobal("ToggleTalentUI", "Talents", "Toggle")
    wrapGlobal("ToggleBackpack", "Bags", "Toggle")
    wrapGlobal("ToggleAllBags", "Bags", "Toggle")
    wrapGlobal("OpenAllBags", "Bags", "Show")
    wrapGlobal("OpenBackpack", "Bags", "Show")
    wrapGlobal("ToggleFriendsFrame", "Social", "Toggle")
    wrapGlobal("ToggleGuildFrame", "Guild", "Toggle")
    wrapGlobal("ToggleLFDParentFrame", "LFG", "Toggle")
    wrapGlobal("ToggleLFRParentFrame", "LFG", "Toggle")
    if type(_G.ToggleEncounterJournal) ~= "function" then
        _G.ToggleEncounterJournal = function() Routes.Open("EncounterJournal", "Toggle") end
    else
        wrapGlobal("ToggleEncounterJournal", "EncounterJournal", "Toggle")
    end

    -- Explicit project entry points for modules whose classic client has no
    -- stable global toggle (collections and the profession event route).
    _G.SLASH_NEWERACOLLECTIONS1 = "/necollections"
    SlashCmdList["NEWERACOLLECTIONS"] = function() Routes.Open("Collections", "Toggle") end
    _G.SLASH_NELEVELUP1 = _G.SLASH_NELEVELUP1 or "/nelevelup"
end

local function bootHudIfEnabled(id)
    local spec = SPECS[id]
    if not profileEnabled(id, spec.default) then return end
    if Routes.Load(id) then bootOnce(id) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("CRAFT_SHOW")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("CRAFT_CLOSE")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        installRoutes()
        -- Event-driven HUDs are intentionally opt-in. A user action can still
        -- load them later through the same route table.
        bootHudIfEnabled("CooldownViewer")
        bootHudIfEnabled("LevelUp")
        return
    end

    if event == "AUCTION_HOUSE_SHOW" then
        Routes.Open("AuctionHouse", "Show")
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Routes.Close("AuctionHouse")
    elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        if not profileEnabled("Professions", SPECS.Professions.default) then return end
        local ok = Routes.Load("Professions")
        if ok then
            bootOnce("Professions")
            local craft = NE.profcraft
            if craft then
                craft.mode = event == "CRAFT_SHOW" and "craft" or "tradeskill"
                invoke(craft, "Show")
            end
        end
    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        Routes.Close("Professions")
    end
end)
