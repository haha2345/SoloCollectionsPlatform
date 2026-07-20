local SC = SoloCollections
local generated = SC.GeneratedIdentityData or { classes = {}, races = {}, aliases = {} }

SC.IdentityRegistry = SC.IdentityRegistry or {}
local Identity = SC.IdentityRegistry

local classesByRuntimeId = {}
local classesByLogicalId = {}
local classesByKey = {}
local racesByRuntimeId = {}
local racesByLogicalId = {}
local racesByKey = {}

local function normalizeKey(value)
    if type(value) ~= "string" then
        return nil
    end
    return string.lower((string.gsub((string.gsub(value, "[- ]", "_")), "[^%w_]", "")))
end

local function addLookup(target, key, value)
    local normalized = normalizeKey(key)
    if normalized and normalized ~= "" then
        target[normalized] = value
    end
end

local function prepareClass(entry)
    entry.known = true
    entry.reason = "OK"
    entry.filterToken = entry.aliases and entry.aliases[1] or string.upper(entry.classKey)
    classesByRuntimeId[entry.runtimeClassId] = entry
    classesByLogicalId[entry.logicalClassId] = entry
    addLookup(classesByKey, entry.classKey, entry)
    for _, alias in ipairs(entry.aliases or {}) do
        addLookup(classesByKey, alias, entry)
    end
end

local function prepareRace(entry)
    entry.known = true
    entry.reason = "OK"
    racesByRuntimeId[entry.runtimeRaceId] = entry
    racesByLogicalId[entry.logicalRaceId] = entry
    addLookup(racesByKey, entry.raceKey, entry)
    for _, alias in ipairs(entry.aliases or {}) do
        addLookup(racesByKey, alias, entry)
    end
end

for _, entry in ipairs(generated.classes or {}) do
    prepareClass(entry)
end
for _, entry in ipairs(generated.races or {}) do
    prepareRace(entry)
end
for _, alias in ipairs(generated.aliases or {}) do
    if alias.kind == "class" then
        addLookup(classesByKey, alias.alias, classesByKey[normalizeKey(alias.target)])
    elseif alias.kind == "race" then
        addLookup(racesByKey, alias.alias, racesByKey[normalizeKey(alias.target)])
    end
end

local function unknown(kind, runtimeId)
    return {
        known = false,
        reason = "UNKNOWN_IDENTITY",
        kind = kind,
        runtimeId = runtimeId,
        cameraProfile = "global",
    }
end

function Identity.ResolveClass(runtimeId)
    return classesByRuntimeId[tonumber(runtimeId)] or unknown("class", runtimeId)
end

function Identity.ResolveRace(runtimeId)
    return racesByRuntimeId[tonumber(runtimeId)] or unknown("race", runtimeId)
end

function Identity.GetClassByKey(key)
    return classesByKey[normalizeKey(key)] or unknown("class", key)
end

function Identity.GetRaceByKey(key)
    return racesByKey[normalizeKey(key)] or unknown("race", key)
end

function Identity.GetClassByLogicalId(logicalId)
    return classesByLogicalId[tonumber(logicalId)] or unknown("class", logicalId)
end

function Identity.GetRaceByLogicalId(logicalId)
    return racesByLogicalId[tonumber(logicalId)] or unknown("race", logicalId)
end

function Identity.ResolvePlayer()
    local _, classToken, runtimeClassId = UnitClass("player")
    local _, raceToken, runtimeRaceId = UnitRace("player")
    local classIdentity = runtimeClassId and Identity.ResolveClass(runtimeClassId) or Identity.GetClassByKey(classToken)
    local raceIdentity = runtimeRaceId and Identity.ResolveRace(runtimeRaceId) or Identity.GetRaceByKey(raceToken)
    return {
        known = classIdentity.known and raceIdentity.known,
        reason = (classIdentity.known and raceIdentity.known) and "OK" or "UNKNOWN_IDENTITY",
        classIdentity = classIdentity,
        raceIdentity = raceIdentity,
    }
end

function Identity.GetPlayerClass()
    return Identity.ResolvePlayer().classIdentity
end

function Identity.GetPlayerRace()
    return Identity.ResolvePlayer().raceIdentity
end

function Identity.GetClassFilterOptions()
    local options = { { key = "ALL", label = "全部职业" } }
    for _, entry in ipairs(generated.classes or {}) do
        table.insert(options, { key = entry.filterToken, label = entry.name.zhCN or entry.name.enUS, identity = entry })
    end
    return options
end

function Identity.GetValidClassTokens()
    local values = { ALL = true }
    for _, entry in ipairs(generated.classes or {}) do
        values[entry.filterToken] = true
    end
    return values
end

function Identity.GetLegacyClassBit(key)
    local entry = Identity.GetClassByKey(key)
    return entry.known and entry.legacyMaskBit or nil
end

function Identity.GetDefaultArmorType(classIdentity)
    local entry = classIdentity or Identity.GetPlayerClass()
    return entry.known and entry.defaultFilterProfile and entry.defaultFilterProfile.armorType or nil
end

function Identity.GetWeaponTypes(slot, classIdentity)
    local entry = classIdentity or Identity.GetPlayerClass()
    local result = {}
    if not entry.known or not entry.defaultFilterProfile then
        return result
    end
    local source = slot == "OFFHAND" and entry.defaultFilterProfile.offhand or entry.defaultFilterProfile.mainhand
    for _, weaponType in ipairs(source or {}) do
        result[weaponType] = true
    end
    return result
end

function Identity.ResolveCameraProfile(raceIdentity)
    local entry = raceIdentity or Identity.GetPlayerRace()
    return entry.cameraProfile or "global"
end

function Identity.ResolveRacePresentation(raceIdentity, resourceState)
    local entry = raceIdentity or Identity.GetPlayerRace()
    local resources = type(resourceState) == "table" and resourceState or {}
    local result = {
        reason = "UNKNOWN_IDENTITY",
        cameraProfile = Identity.ResolveCameraProfile(entry),
        appearanceOverrideProfile = nil,
        modelProfile = nil,
        previewEnabled = false,
        actionEnabled = false,
    }
    if not entry or not entry.known then
        return result
    end

    result.appearanceOverrideProfile = entry.appearanceOverrideProfile
    result.modelProfile = entry.modelProfile
    if type(entry.clientAssetVersion) ~= "string"
        or entry.clientAssetVersion == ""
        or resources.clientAssetVersion ~= entry.clientAssetVersion then
        result.reason = "ASSET_VERSION_MISMATCH"
        return result
    end
    if type(entry.modelProfile) ~= "string"
        or entry.modelProfile == ""
        or resources.modelAvailable ~= true then
        result.reason = "MODEL_MISSING"
        return result
    end
    if resources.textureAvailable ~= true then
        result.reason = "TEXTURE_MISSING"
        return result
    end

    result.reason = "OK"
    result.previewEnabled = true
    result.actionEnabled = true
    return result
end
