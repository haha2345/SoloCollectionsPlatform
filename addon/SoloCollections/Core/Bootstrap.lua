local SC = SoloCollections

local DEFAULTS = {
    schemaVersion = 4,
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
    debug = false,
    bridge = {
        status = "idle",
        connected = false,
        demoMode = true,
        features = {},
        sc2 = {
            status = "idle",
            connected = false,
            state = "Loading",
            revision = "0",
            backendBuild = "",
        },
    },
}

local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local VALID_MAIN_TABS = { MOUNTS = true, PETS = true, TOYS = true, WARDROBE = true, TITLES = true }
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
local VALID_SC2_STATUS = {
    idle = true, waiting = true, connected = true, fallback = true,
    loading = true, failed = true, mismatch = true,
}
local VALID_SC2_STATE = { Loading = true, Ready = true, Failed = true, Mismatch = true }
local CAMERA_TUNING_SCHEMA_VERSION = 2
local MAX_CAMERA_TUNING_SCOPE_ENTRIES = 512
local MAX_LEGACY_CAMERA_TUNING_BACKUP_ENTRIES = 128

local function isFiniteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

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

local function isValidWeaponFamilyKey(key)
    return type(key) == "string" and key:match("^[A-Z][A-Z0-9_]*$") ~= nil
end

local function isValidModelSignature(key)
    return type(key) == "string" and key:match("^m2:[a-f0-9][a-f0-9]+$") ~= nil
end

local function isValidAppearanceKey(key)
    return type(key) == "string" and key:match("^appearance:%d+$") ~= nil
end

local function isValidBodyProfileKey(key)
    return type(key) == "string" and key:match("^[a-z_]+:[a-z]+:[A-Z_]+$") ~= nil
end

local function cameraScopeKeyIsValid(scope, key)
    if scope == "weaponFamily" then return isValidWeaponFamilyKey(key) end
    if scope == "model" then return isValidModelSignature(key) end
    if scope == "appearance" then return isValidAppearanceKey(key) end
    if scope == "bodyProfile" then return isValidBodyProfileKey(key) end
    return false
end

local function normalizeCameraPose(pose)
    if not SC.M2Camera or not SC.M2Camera.NormalizePose then return nil end
    return SC.M2Camera.NormalizePose(pose)
end

local function normalizeBodyCameraDelta(delta)
    if not SC.M2Camera or not SC.M2Camera.NormalizeBodyDelta then return nil end
    return SC.M2Camera.NormalizeBodyDelta(delta)
end

local function bodyDeltaEquals(left, right)
    if not SC.M2Camera or not SC.M2Camera.BodyDeltaEquals then return false end
    return SC.M2Camera.BodyDeltaEquals(left, right)
end

local function normalizedCameraScope(entries, scope, maximum)
    local keys = {}
    if type(entries) == "table" then
        for key, pose in pairs(entries) do
            if cameraScopeKeyIsValid(scope, key) and type(pose) == "table" then
                table.insert(keys, key)
            end
        end
    end
    table.sort(keys)
    local normalized = {}
    for index, key in ipairs(keys) do
        if index > maximum then break end
        local pose = normalizeCameraPose(entries[key])
        if pose then normalized[key] = pose end
    end
    return normalized
end

local function normalizedBodyCameraScope(entries, maximum)
    local keys = {}
    if type(entries) == "table" then
        for key, delta in pairs(entries) do
            if isValidBodyProfileKey(key) and type(delta) == "table" then
                table.insert(keys, key)
            end
        end
    end
    table.sort(keys)
    local normalized = {}
    for index, key in ipairs(keys) do
        if index > maximum then break end
        local delta = normalizeBodyCameraDelta(entries[key])
        if delta and not bodyDeltaEquals(delta, {}) then normalized[key] = delta end
    end
    return normalized
end

local function tableHasEntries(entries)
    return type(entries) == "table" and next(entries) ~= nil
end

local function poseEquals(left, right)
    left = normalizeCameraPose(left)
    right = normalizeCameraPose(right)
    if not left or not right then return false end
    local epsilon = 0.0001
    local function same(a, b)
        return isFiniteNumber(a) and isFiniteNumber(b) and math.abs(a - b) <= epsilon
    end
    return same(left.yaw, right.yaw)
        and same(left.pitch, right.pitch)
        and same(left.roll, right.roll)
        and same(left.distanceScale, right.distanceScale)
        and same(left.target[1], right.target[1])
        and same(left.target[2], right.target[2])
        and same(left.target[3], right.target[3])
end

local function normalizeCameraTuning(db)
    local legacy = type(db.m2CameraTuning) == "table" and db.m2CameraTuning or nil
    local tuning = type(db.cameraTuning) == "table" and db.cameraTuning or nil
    local hasLegacy = tableHasEntries(legacy)
    if not tuning and not hasLegacy then
        db.m2CameraTuning = nil
        return
    end

    tuning = tuning or {}
    local legacyFamilies = normalizedCameraScope(
        legacy,
        "weaponFamily",
        MAX_LEGACY_CAMERA_TUNING_BACKUP_ENTRIES
    )
    tuning.weaponFamily = normalizedCameraScope(
        tuning.weaponFamily,
        "weaponFamily",
        MAX_CAMERA_TUNING_SCOPE_ENTRIES
    )
    if tableHasEntries(legacyFamilies) then
        -- Preserve exactly one normalized v1 snapshot for recovery, while the
        -- live values move to the explicit weaponFamily scope below.
        if not tableHasEntries(tuning.legacyM2CameraTuningV1) then
            tuning.legacyM2CameraTuningV1 = legacyFamilies
        else
            tuning.legacyM2CameraTuningV1 = normalizedCameraScope(
                tuning.legacyM2CameraTuningV1,
                "weaponFamily",
                MAX_LEGACY_CAMERA_TUNING_BACKUP_ENTRIES
            )
        end
        for familyKey, pose in pairs(legacyFamilies) do
            if not tuning.weaponFamily[familyKey] then
                tuning.weaponFamily[familyKey] = pose
            end
        end
    elseif tableHasEntries(tuning.legacyM2CameraTuningV1) then
        tuning.legacyM2CameraTuningV1 = normalizedCameraScope(
            tuning.legacyM2CameraTuningV1,
            "weaponFamily",
            MAX_LEGACY_CAMERA_TUNING_BACKUP_ENTRIES
        )
    else
        tuning.legacyM2CameraTuningV1 = nil
    end

    tuning.model = normalizedCameraScope(tuning.model, "model", MAX_CAMERA_TUNING_SCOPE_ENTRIES)
    tuning.appearance = normalizedCameraScope(tuning.appearance, "appearance", MAX_CAMERA_TUNING_SCOPE_ENTRIES)
    tuning.bodyProfile = normalizedBodyCameraScope(
        tuning.bodyProfile,
        MAX_CAMERA_TUNING_SCOPE_ENTRIES
    )
    tuning.schemaVersion = CAMERA_TUNING_SCHEMA_VERSION
    db.m2CameraTuning = nil

    if tableHasEntries(tuning.weaponFamily) or tableHasEntries(tuning.model)
        or tableHasEntries(tuning.appearance) or tableHasEntries(tuning.bodyProfile)
        or tableHasEntries(tuning.legacyM2CameraTuningV1) then
        db.cameraTuning = tuning
    else
        -- Do not create SavedVariables for an untouched camera workbench.
        db.cameraTuning = nil
    end
end

local CameraTuning = SC.CameraTuning or {}
SC.CameraTuning = CameraTuning
CameraTuning.SCHEMA_VERSION = CAMERA_TUNING_SCHEMA_VERSION
-- Runtime-only revision used by the wardrobe pose cache.  SavedVariables
-- remain the authoritative tuning store; this value simply invalidates the
-- small visible-card cache after an edit or reset.
CameraTuning.revision = tonumber(CameraTuning.revision) or 0

local function isM2CameraScopeKeyValid(scope, key)
    return (scope == "weaponFamily" or scope == "model" or scope == "appearance")
        and cameraScopeKeyIsValid(scope, key)
end

function CameraTuning.Get(scope, key)
    if not isM2CameraScopeKeyValid(scope, key) or not SC.db
        or type(SC.db.cameraTuning) ~= "table" then
        return nil
    end
    local entries = SC.db.cameraTuning[scope]
    if type(entries) ~= "table" then return nil end
    -- An absent override must remain absent. Normalizing nil would manufacture
    -- a zero/default pose, which incorrectly outranks the generated autoCamera
    -- baseline in the effective precedence resolver.
    local stored = entries[key]
    if type(stored) ~= "table" then return nil end
    return normalizeCameraPose(stored)
end

function CameraTuning.PoseEquals(left, right)
    return poseEquals(left, right)
end

function CameraTuning.Set(scope, key, pose, lowerScopePose)
    if not isM2CameraScopeKeyValid(scope, key) or not SC.db then return false end
    local normalized = normalizeCameraPose(pose)
    if not normalized then return false end
    local tuning = SC.db.cameraTuning
    if type(tuning) ~= "table" then
        tuning = { schemaVersion = CAMERA_TUNING_SCHEMA_VERSION }
        SC.db.cameraTuning = tuning
    end
    tuning.schemaVersion = CAMERA_TUNING_SCHEMA_VERSION
    tuning[scope] = type(tuning[scope]) == "table" and tuning[scope] or {}
    if lowerScopePose and poseEquals(normalized, lowerScopePose) then
        tuning[scope][key] = nil
    else
        tuning[scope][key] = normalized
    end
    normalizeCameraTuning(SC.db)
    CameraTuning.revision = CameraTuning.revision + 1
    return true
end

function CameraTuning.Reset(scope, key)
    if not isM2CameraScopeKeyValid(scope, key) or not SC.db
        or type(SC.db.cameraTuning) ~= "table" then
        return false
    end
    local entries = SC.db.cameraTuning[scope]
    if type(entries) ~= "table" or entries[key] == nil then return false end
    entries[key] = nil
    normalizeCameraTuning(SC.db)
    CameraTuning.revision = CameraTuning.revision + 1
    return true
end

-- Body deltas share the versioned cameraTuning SavedVariables root but use a
-- distinct value contract.  Keeping this API separate prevents a seven-axis
-- M2 pose from ever being interpreted as a five-axis character-profile delta.
local BodyCameraTuning = SC.BodyCameraTuning or {}
SC.BodyCameraTuning = BodyCameraTuning
BodyCameraTuning.SCHEMA_VERSION = CAMERA_TUNING_SCHEMA_VERSION

function BodyCameraTuning.Get(profileKey)
    if not isValidBodyProfileKey(profileKey) or not SC.db
        or type(SC.db.cameraTuning) ~= "table" then
        return nil
    end
    local entries = SC.db.cameraTuning.bodyProfile
    local stored = type(entries) == "table" and entries[profileKey] or nil
    if type(stored) ~= "table" then return nil end
    return normalizeBodyCameraDelta(stored)
end

function BodyCameraTuning.DeltaEquals(left, right)
    return bodyDeltaEquals(left, right)
end

function BodyCameraTuning.Set(profileKey, delta)
    if not isValidBodyProfileKey(profileKey) or not SC.db then return false end
    local normalized = normalizeBodyCameraDelta(delta)
    if not normalized then return false end
    local tuning = SC.db.cameraTuning
    if type(tuning) ~= "table" then
        tuning = { schemaVersion = CAMERA_TUNING_SCHEMA_VERSION }
        SC.db.cameraTuning = tuning
    end
    tuning.schemaVersion = CAMERA_TUNING_SCHEMA_VERSION
    tuning.bodyProfile = type(tuning.bodyProfile) == "table" and tuning.bodyProfile or {}
    if bodyDeltaEquals(normalized, {}) then
        tuning.bodyProfile[profileKey] = nil
    else
        tuning.bodyProfile[profileKey] = normalized
    end
    normalizeCameraTuning(SC.db)
    return true
end

function BodyCameraTuning.Reset(profileKey)
    if not isValidBodyProfileKey(profileKey) or not SC.db
        or type(SC.db.cameraTuning) ~= "table" then
        return false
    end
    local entries = SC.db.cameraTuning.bodyProfile
    if type(entries) ~= "table" or entries[profileKey] == nil then return false end
    entries[profileKey] = nil
    normalizeCameraTuning(SC.db)
    return true
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
    normalizeCameraTuning(db)
    -- Capability attestation is deliberately process-local in M2Camera.lua.
    -- Remove an experimental pre-v7 saved marker so a stock client always
    -- opens the BODY workbench in its safe read-only state.
    db.bodyCameraRuntimeCapability = nil
    repairScalar(db, "debug", "boolean", DEFAULTS.debug)

    repairScalar(db, "bridge", "table", {})
    repairEnum(db.bridge, "status", VALID_BRIDGE_STATUS, DEFAULTS.bridge.status)
    repairScalar(db.bridge, "connected", "boolean", DEFAULTS.bridge.connected)
    repairScalar(db.bridge, "demoMode", "boolean", DEFAULTS.bridge.demoMode)
    repairScalar(db.bridge, "features", "table", {})
    repairScalar(db.bridge, "sc2", "table", {})
    repairEnum(db.bridge.sc2, "status", VALID_SC2_STATUS, DEFAULTS.bridge.sc2.status)
    repairScalar(db.bridge.sc2, "connected", "boolean", DEFAULTS.bridge.sc2.connected)
    repairEnum(db.bridge.sc2, "state", VALID_SC2_STATE, DEFAULTS.bridge.sc2.state)
    if type(db.bridge.sc2.revision) ~= "string" or not string.match(db.bridge.sc2.revision, "^%d+$") then
        db.bridge.sc2.revision = DEFAULTS.bridge.sc2.revision
    end
    repairScalar(db.bridge.sc2, "backendBuild", "string", DEFAULTS.bridge.sc2.backendBuild)
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
        if SC.Bridge.ConnectSC2 then
            SC.Bridge.ConnectSC2(true)
        end
    else
        SC:ToggleJournal()
    end
end
