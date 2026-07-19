local SC = SoloCollections

local DEFAULTS = {
    schemaVersion = 3,
    launcher = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -28, y = 150 },
    frame = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    mainTab = "MOUNTS",
    wardrobeTab = "ITEMS",
    query = "",
    filters = {
        collected = true,
        uncollected = true,
        favorites = false,
        classToken = "ALL",
        armorType = "AUTO",
        slot = "HEAD",
        weaponType = "AUTO",
    },
    favorites = {},
    -- Per-category temporary M2 poses created by the in-game camera panel.
    -- They survive /reload so a player can refine one weapon family over
    -- several sessions, then export the final table into Data/Appearances.lua.
    m2CameraTuning = {},
    debug = false,
    bridge = {
        status = "idle",
        connected = false,
        demoMode = true,
        features = {},
    },
}

local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local VALID_MAIN_TABS = { MOUNTS = true, PETS = true, TOYS = true, WARDROBE = true }
local VALID_WARDROBE_TABS = { ITEMS = true, SETS = true }
local VALID_CLASS_TOKENS = SC.IdentityRegistry.GetValidClassTokens()
local VALID_SLOTS = {
    ALL = true, HEAD = true, SHOULDER = true, BACK = true, CHEST = true,
    WRIST = true, HANDS = true, WAIST = true, LEGS = true, FEET = true,
    MAINHAND = true, OFFHAND = true,
}
local VALID_ARMOR_TYPES = {
    AUTO = true, PLATE = true, MAIL = true, LEATHER = true, CLOTH = true,
}
local VALID_WEAPON_TYPES = {
    AUTO = true,
    ONE_HAND_AXE = true, TWO_HAND_AXE = true, BOW = true, GUN = true,
    ONE_HAND_MACE = true, TWO_HAND_MACE = true, POLEARM = true,
    ONE_HAND_SWORD = true, TWO_HAND_SWORD = true, STAFF = true,
    FIST_WEAPON = true, DAGGER = true, THROWN = true, CROSSBOW = true,
    WAND = true, FISHING_POLE = true, SHIELD = true, OFFHAND_ITEM = true,
}
local VALID_BRIDGE_STATUS = { idle = true, waiting = true, connected = true, fallback = true }

local function repairScalar(target, key, expectedType, default)
    if type(target[key]) ~= expectedType then
        target[key] = default
    end
end

local function repairEnum(target, key, validValues, default)
    if type(target[key]) ~= "string" or not validValues[target[key]] then
        target[key] = default
    end
end

local function normalizePosition(db, key, defaults)
    repairScalar(db, key, "table", {})
    local position = db[key]
    repairEnum(position, "point", VALID_POINTS, defaults.point)
    repairEnum(position, "relativePoint", VALID_POINTS, defaults.relativePoint)
    repairScalar(position, "x", "number", defaults.x)
    repairScalar(position, "y", "number", defaults.y)
end

local function isValidM2CameraTuningKey(key)
    -- Camera defaults are now permanently keyed by weapon family (or by an
    -- explicit per-model key such as WAR_GLAIVE_MAINHAND). Drop legacy numeric
    -- per-appearance entries: otherwise an old experiment would override the
    -- fixed pose supplied by Data/Appearances.lua after a reload.
    return type(key) == "string" and key:match("^[A-Z][A-Z0-9_]*$") ~= nil
end

local function normalizeM2CameraTuning(db)
    repairScalar(db, "m2CameraTuning", "table", {})
    for tuningKey, pose in pairs(db.m2CameraTuning) do
        if not isValidM2CameraTuningKey(tuningKey) or type(pose) ~= "table" then
            db.m2CameraTuning[tuningKey] = nil
        elseif SC.M2Camera and SC.M2Camera.NormalizePose then
            -- Rebuild the table to drop unknown/corrupt SavedVariables fields
            -- and to keep all persisted values inside the DLL protocol range.
            db.m2CameraTuning[tuningKey] = SC.M2Camera.NormalizePose(pose)
        end
    end
end

local function normalizeDatabase(db)
    repairScalar(db, "schemaVersion", "number", DEFAULTS.schemaVersion)
    if db.schemaVersion ~= DEFAULTS.schemaVersion then
        db.schemaVersion = DEFAULTS.schemaVersion
    end

    normalizePosition(db, "launcher", DEFAULTS.launcher)
    normalizePosition(db, "frame", DEFAULTS.frame)
    repairEnum(db, "mainTab", VALID_MAIN_TABS, DEFAULTS.mainTab)
    repairEnum(db, "wardrobeTab", VALID_WARDROBE_TABS, DEFAULTS.wardrobeTab)
    repairScalar(db, "query", "string", DEFAULTS.query)

    repairScalar(db, "filters", "table", {})
    repairScalar(db.filters, "collected", "boolean", DEFAULTS.filters.collected)
    repairScalar(db.filters, "uncollected", "boolean", DEFAULTS.filters.uncollected)
    repairScalar(db.filters, "favorites", "boolean", DEFAULTS.filters.favorites)
    repairEnum(db.filters, "classToken", VALID_CLASS_TOKENS, DEFAULTS.filters.classToken)
    repairEnum(db.filters, "armorType", VALID_ARMOR_TYPES, DEFAULTS.filters.armorType)
    repairEnum(db.filters, "slot", VALID_SLOTS, DEFAULTS.filters.slot)
    repairEnum(db.filters, "weaponType", VALID_WEAPON_TYPES, DEFAULTS.filters.weaponType)

    repairScalar(db, "favorites", "table", {})
    normalizeM2CameraTuning(db)
    repairScalar(db, "debug", "boolean", DEFAULTS.debug)

    repairScalar(db, "bridge", "table", {})
    repairEnum(db.bridge, "status", VALID_BRIDGE_STATUS, DEFAULTS.bridge.status)
    repairScalar(db.bridge, "connected", "boolean", DEFAULTS.bridge.connected)
    repairScalar(db.bridge, "demoMode", "boolean", DEFAULTS.bridge.demoMode)
    repairScalar(db.bridge, "features", "table", {})
end

function SC:InitializeDatabase()
    if type(SoloCollectionsDB) ~= "table" then
        SoloCollectionsDB = {}
    end
    normalizeDatabase(SoloCollectionsDB)
    self.db = SoloCollectionsDB
end

function SC:ResetLayoutAndFilters()
    if type(SoloCollectionsDB) ~= "table" then
        SoloCollectionsDB = {}
    end
    SoloCollectionsDB.launcher = nil
    SoloCollectionsDB.frame = nil
    SoloCollectionsDB.mainTab = nil
    SoloCollectionsDB.wardrobeTab = nil
    SoloCollectionsDB.query = nil
    SoloCollectionsDB.filters = nil
    normalizeDatabase(SoloCollectionsDB)
    self.db = SoloCollectionsDB
    if self.UI.ResetPositions then
        self.UI.ResetPositions()
    end
end

function SC:ToggleJournal()
    if self.UI.ToggleJournal then
        self.UI.ToggleJournal()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= SC.NAME then
            return
        end
        SC:InitializeDatabase()
        if SC.UI.CreateLauncher then
            SC.UI.CreateLauncher()
        end
    elseif event == "PLAYER_LOGIN" then
        if SC.Bridge and SC.Bridge.OnLogin then
            SC.Bridge.OnLogin()
        end
    elseif event == "CHAT_MSG_ADDON" then
        if SC.Bridge and SC.Bridge.OnMessage then
            SC.Bridge.OnMessage(...)
        end
    end
end)

SLASH_SOLOCOLLECTIONS1 = "/sc"
SLASH_SOLOCOLLECTIONS2 = "/collections"
SlashCmdList.SOLOCOLLECTIONS = function(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    local toyId = string.match(command, "^toy%s+(%d+)$")
    if toyId and SC.Bridge and SC.Bridge.UseToy then
        SC.Bridge.UseToy(tonumber(toyId), function(ok, reason)
            if ok == false and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffff9f40SoloCollections:|r 玩具使用失败：" .. tostring(reason or "UNKNOWN")
                )
            end
        end)
    elseif command == "reset" then
        SC:ResetLayoutAndFilters()
    elseif command == "debug" then
        SC.db.debug = not SC.db.debug
        DEFAULT_CHAT_FRAME:AddMessage("SoloCollections debug: " .. (SC.db.debug and "on" or "off"))
    elseif command == "reconnect" and SC.Bridge and SC.Bridge.Connect then
        SC.Bridge.Connect(true)
    else
        SC:ToggleJournal()
    end
end
