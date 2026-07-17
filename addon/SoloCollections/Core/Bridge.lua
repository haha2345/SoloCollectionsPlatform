local SC = SoloCollections

local B = SC.Bridge or {}
SC.Bridge = B

B.prefix = "SC1"
B.version = 1
B.request = "HELLO|1"
B.response = "HELLO_ACK|1|DEMO"
B.timeout = 3
B.connected = false
B.demoMode = true
B.features = {}
B.waiting = false
B.attempted = false

local requestTimeout = 5
local requestSerial = 0
local pendingModels = {}
local pendingSummons = {}
local pendingPetModels = {}
local pendingPetSummons = {}
local pendingToyUses = {}
local timerFrame = CreateFrame("Frame")
local prefixRegistered = false

local function isPositiveInteger(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function ensurePrefixRegistered()
    if prefixRegistered then
        return true
    end
    if not RegisterAddonMessagePrefix then
        prefixRegistered = true
        return true
    end
    local ok, registered = pcall(RegisterAddonMessagePrefix, B.prefix)
    if ok and registered ~= false then
        prefixRegistered = true
    end
    return prefixRegistered
end

local function saveState(status)
    if not SC.db then
        return
    end
    if type(SC.db.bridge) ~= "table" then
        SC.db.bridge = {}
    end
    SC.db.bridge.status = status
    SC.db.bridge.connected = B.connected
    SC.db.bridge.demoMode = B.demoMode
    local savedFeatures = {}
    for feature, enabled in pairs(B.features) do
        if enabled == true then
            savedFeatures[feature] = true
        end
    end
    SC.db.bridge.features = savedFeatures
end

function B.Finish(connected, status)
    B.waiting = false
    B.connected = connected and true or false
    B.demoMode = true
    B.features = B.connected and { DEMO = true } or {}
    saveState(status)
end

local function expirePendingRequests(now)
    for requestId, pending in pairs(pendingModels) do
        if now >= pending.deadline then
            pendingModels[requestId] = nil
            if type(pending.callback) == "function" then
                pcall(pending.callback, false, "TIMEOUT")
            end
        end
    end
    for requestId, pending in pairs(pendingSummons) do
        if now >= pending.deadline then
            pendingSummons[requestId] = nil
            if type(pending.callback) == "function" then
                pcall(pending.callback, false, "TIMEOUT")
            end
        end
    end
    for requestId, pending in pairs(pendingPetModels) do
        if now >= pending.deadline then
            pendingPetModels[requestId] = nil
            if type(pending.callback) == "function" then
                pcall(pending.callback, false, "TIMEOUT")
            end
        end
    end
    for requestId, pending in pairs(pendingPetSummons) do
        if now >= pending.deadline then
            pendingPetSummons[requestId] = nil
            if type(pending.callback) == "function" then
                pcall(pending.callback, false, "TIMEOUT")
            end
        end
    end
    for requestId, pending in pairs(pendingToyUses) do
        if now >= pending.deadline then
            pendingToyUses[requestId] = nil
            if type(pending.callback) == "function" then
                pcall(pending.callback, false, "TIMEOUT")
            end
        end
    end
end

local function onTimerUpdate(self, elapsed)
    if B.waiting then
        B.elapsed = B.elapsed + elapsed
        if B.elapsed >= B.timeout then
            B.Finish(false, "fallback")
        end
    end
    expirePendingRequests(GetTime())
end

timerFrame:SetScript("OnUpdate", onTimerUpdate)

function B.Connect(force)
    if B.attempted and not force then
        return
    end

    B.attempted = true
    B.waiting = true
    B.connected = false
    B.demoMode = true
    B.features = {}
    B.elapsed = 0

    if not ensurePrefixRegistered() then
        B.Finish(false, "fallback")
        return
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        B.Finish(false, "fallback")
        return
    end

    saveState("waiting")
    SendAddonMessage(B.prefix, B.request, "WHISPER", playerName)
end

function B.OnLogin()
    B.attempted = false
    B.Connect()
end

function B.RequestModel(mountId, callback)
    if not isPositiveInteger(mountId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_MOUNT_ID")
        end
        return nil
    end
    if not B.connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    requestSerial = requestSerial + 1
    local requestId = requestSerial
    pendingModels[requestId] = {
        mountId = mountId,
        deadline = GetTime() + requestTimeout,
        callback = callback,
    }
    SendAddonMessage(B.prefix, "MODEL|" .. requestId .. "|" .. mountId, "WHISPER", playerName)
    return requestId
end

function B.SummonMount(mountId, callback)
    if not isPositiveInteger(mountId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_MOUNT_ID")
        end
        return nil
    end
    if not B.connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    requestSerial = requestSerial + 1
    local requestId = requestSerial
    pendingSummons[requestId] = {
        mountId = mountId,
        deadline = GetTime() + requestTimeout,
        callback = callback,
    }
    SendAddonMessage(B.prefix, "SUMMON|" .. requestId .. "|" .. mountId, "WHISPER", playerName)
    return requestId
end

function B.RequestPetModel(petId, callback)
    if not isPositiveInteger(petId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_PET_ID")
        end
        return nil
    end
    if not B.connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    requestSerial = requestSerial + 1
    local requestId = requestSerial
    pendingPetModels[requestId] = {
        petId = petId,
        deadline = GetTime() + requestTimeout,
        callback = callback,
    }
    SendAddonMessage(B.prefix, "PET_MODEL|" .. requestId .. "|" .. petId, "WHISPER", playerName)
    return requestId
end

function B.SummonPet(petId, callback)
    if not isPositiveInteger(petId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_PET_ID")
        end
        return nil
    end
    if not B.connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    requestSerial = requestSerial + 1
    local requestId = requestSerial
    pendingPetSummons[requestId] = {
        petId = petId,
        deadline = GetTime() + requestTimeout,
        callback = callback,
    }
    SendAddonMessage(B.prefix, "PET_SUMMON|" .. requestId .. "|" .. petId, "WHISPER", playerName)
    return requestId
end

function B.UseToy(toyId, callback)
    if not isPositiveInteger(toyId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_TOY_ID")
        end
        return nil
    end
    if not B.connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end

    requestSerial = requestSerial + 1
    local requestId = requestSerial
    pendingToyUses[requestId] = {
        toyId = toyId,
        deadline = GetTime() + requestTimeout,
        callback = callback,
    }
    SendAddonMessage(B.prefix, "TOY_USE|" .. requestId .. "|" .. toyId, "WHISPER", playerName)
    return requestId
end

local function handleModelReady(requestIdText, mountIdText)
    local requestId = tonumber(requestIdText)
    local mountId = tonumber(mountIdText)
    if not isPositiveInteger(requestId) or not isPositiveInteger(mountId) then
        return
    end

    local pending = pendingModels[requestId]
    if not pending or pending.mountId ~= mountId then
        return
    end
    pendingModels[requestId] = nil
    if type(pending.callback) == "function" then
        pcall(pending.callback, true, mountId)
    end
end

local function handleSummonResult(requestIdText, status, payload)
    local requestId = tonumber(requestIdText)
    if not isPositiveInteger(requestId) then
        return
    end

    local pending = pendingSummons[requestId]
    if not pending then
        return
    end

    if status == "ACCEPTED" then
        if type(payload) ~= "string" or not string.match(payload, "^%d+$") then
            return
        end
        local mountId = tonumber(payload)
        if not isPositiveInteger(mountId) or pending.mountId ~= mountId then
            return
        end
        pendingSummons[requestId] = nil
        if type(pending.callback) == "function" then
            pcall(pending.callback, true, "ACCEPTED")
        end
        return
    end

    if status == "ERROR" then
        if type(payload) ~= "string" or not string.match(payload, "^[A-Z_]+$") then
            return
        end
        pendingSummons[requestId] = nil
        if type(pending.callback) == "function" then
            pcall(pending.callback, false, payload)
        end
    end
end

local function handlePetModelReady(requestIdText, petIdText)
    local requestId = tonumber(requestIdText)
    local petId = tonumber(petIdText)
    if not isPositiveInteger(requestId) or not isPositiveInteger(petId) then
        return
    end

    local pending = pendingPetModels[requestId]
    if not pending or pending.petId ~= petId then
        return
    end
    pendingPetModels[requestId] = nil
    if type(pending.callback) == "function" then
        pcall(pending.callback, true, petId)
    end
end

local function handlePetSummonResult(requestIdText, status, payload)
    local requestId = tonumber(requestIdText)
    if not isPositiveInteger(requestId) then
        return
    end

    local pending = pendingPetSummons[requestId]
    if not pending then
        return
    end

    if status == "ACCEPTED" then
        if type(payload) ~= "string" or not string.match(payload, "^%d+$") then
            return
        end
        local petId = tonumber(payload)
        if not isPositiveInteger(petId) or pending.petId ~= petId then
            return
        end
        pendingPetSummons[requestId] = nil
        if type(pending.callback) == "function" then
            pcall(pending.callback, true, "ACCEPTED")
        end
        return
    end

    if status == "ERROR" then
        if type(payload) ~= "string" or not string.match(payload, "^[A-Z_]+$") then
            return
        end
        pendingPetSummons[requestId] = nil
        if type(pending.callback) == "function" then
            pcall(pending.callback, false, payload)
        end
    end
end

local function handleToyUseResult(requestIdText, status, payload)
    local requestId = tonumber(requestIdText)
    if not isPositiveInteger(requestId) then
        return
    end

    local pending = pendingToyUses[requestId]
    if not pending then
        return
    end

    if status == "ACCEPTED" then
        if type(payload) ~= "string" or not string.match(payload, "^%d+$") then
            return
        end
        local toyId = tonumber(payload)
        if not isPositiveInteger(toyId) or pending.toyId ~= toyId then
            return
        end
        pendingToyUses[requestId] = nil
        if type(pending.callback) == "function" then
            pcall(pending.callback, true, "ACCEPTED")
        end
        return
    end

    if status == "ERROR" then
        if type(payload) ~= "string" or not string.match(payload, "^[A-Z_]+$") then
            return
        end
        pendingToyUses[requestId] = nil
        if type(pending.callback) == "function" then
            pcall(pending.callback, false, payload)
        end
    end
end

function B.OnMessage(prefix, message, channel, sender)
    if B.prefix ~= prefix then
        return
    end
    if channel ~= "WHISPER" then
        return
    end
    if sender ~= UnitName("player") then
        return
    end
    if type(message) ~= "string" then
        return
    end

    local modelRequestId, modelMountId = string.match(message, "^MODEL_READY|(%d+)|(%d+)$")
    if modelRequestId then
        handleModelReady(modelRequestId, modelMountId)
        return
    end

    local summonRequestId, summonResult = string.match(message, "^SUMMON_RESULT|(%d+)|(.+)$")
    if summonRequestId then
        local status, payload = string.match(summonResult, "^([A-Z_]+)|([A-Z0-9_]+)$")
        if status then
            handleSummonResult(summonRequestId, status, payload)
        end
        return
    end

    local petModelRequestId, petModelId = string.match(message, "^PET_MODEL_READY|(%d+)|(%d+)$")
    if petModelRequestId then
        handlePetModelReady(petModelRequestId, petModelId)
        return
    end

    local petSummonRequestId, petSummonResult = string.match(message, "^PET_SUMMON_RESULT|(%d+)|(.+)$")
    if petSummonRequestId then
        local status, payload = string.match(petSummonResult, "^([A-Z_]+)|([A-Z0-9_]+)$")
        if status then
            handlePetSummonResult(petSummonRequestId, status, payload)
        end
        return
    end

    local toyUseRequestId, toyUseResult = string.match(message, "^TOY_USE_RESULT|(%d+)|(.+)$")
    if toyUseRequestId then
        local status, payload = string.match(toyUseResult, "^([A-Z_]+)|([A-Z0-9_]+)$")
        if status then
            handleToyUseResult(toyUseRequestId, status, payload)
        end
        return
    end

    if not B.waiting then
        return
    end
    if message ~= B.response then
        return
    end
    B.Finish(true, "connected")
end
