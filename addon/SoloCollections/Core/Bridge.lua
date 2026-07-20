local SC = SoloCollections

local B = SC.Bridge or {}
SC.Bridge = B
local CS = SC.CollectionState

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
B.sc2Prefix = "SC2"
B.sc2Version = 1
B.sc2Timeout = 5
B.sc2Connected = false
B.sc2Waiting = false
B.sc2Attempted = false

local requestTimeout = 5
local requestSerial = 0
local pendingModels = {}
local pendingSummons = {}
local pendingPetModels = {}
local pendingPetSummons = {}
local pendingToyUses = {}
local sc2PendingActions = {}
local timerFrame = CreateFrame("Frame")
local prefixRegistered = false
local sc2PrefixRegistered = false

local function isPositiveInteger(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function isActionToken(value)
    return type(value) == "string" and string.len(value) <= 32 and
        string.match(value, "^[A-Z][A-Z0-9_]*$") ~= nil
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

local function ensureSC2PrefixRegistered()
    if sc2PrefixRegistered then
        return true
    end
    if not RegisterAddonMessagePrefix then
        sc2PrefixRegistered = true
        return true
    end
    local ok, registered = pcall(RegisterAddonMessagePrefix, B.sc2Prefix)
    if ok and registered ~= false then
        sc2PrefixRegistered = true
    end
    return sc2PrefixRegistered
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

local function saveSC2State(status)
    if not SC.db then
        return
    end
    if type(SC.db.bridge) ~= "table" then
        SC.db.bridge = {}
    end
    if type(SC.db.bridge.sc2) ~= "table" then
        SC.db.bridge.sc2 = {}
    end
    local state = SC.db.bridge.sc2
    state.status = status
    state.connected = B.sc2Connected
    state.state = CS and CS.GetState and CS.GetState() or "Failed"
    state.revision = CS and CS.GetRevision and CS.GetRevision() or "0"
    state.backendBuild = CS and CS.backendBuild or ""
end

local function newClientNonce()
    local high = math.floor((time and time() or 0) % 4294967296)
    local low = math.floor(((GetTime and GetTime() or 0) * 1000 + math.random(0, 2147483647)) % 4294967296)
    return string.format("%08x%08x", high, low)
end

if CS then
    CS.SetSender(function(body)
        local playerName = UnitName("player")
        if playerName and playerName ~= "" then
            SendAddonMessage(B.sc2Prefix, body, "WHISPER", playerName)
        end
    end)
    CS.SetChangedCallback(function(state)
        B.sc2Connected = CS.HasAuthority and CS.HasAuthority() and state ~= "Failed"
        saveSC2State(state == "Ready" and "connected" or string.lower(state or "failed"))
    end)
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
    for requestId, pending in pairs(sc2PendingActions) do
        if now >= pending.deadline then
            sc2PendingActions[requestId] = nil
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
    if B.sc2Waiting then
        B.sc2Elapsed = B.sc2Elapsed + elapsed
        if B.sc2Elapsed >= B.sc2Timeout then
            B.sc2Waiting = false
            B.sc2Connected = false
            if CS and CS.MarkUnavailable then
                CS.MarkUnavailable()
            end
            saveSC2State("fallback")
        end
    end
    if CS and CS.Update then
        CS.Update(GetTime())
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

function B.ConnectSC2(force)
    if B.sc2Attempted and not force then
        return
    end
    B.sc2Attempted = true
    B.sc2Waiting = true
    B.sc2Connected = false
    B.sc2Elapsed = 0

    if not CS or not ensureSC2PrefixRegistered() then
        B.sc2Waiting = false
        saveSC2State("fallback")
        return
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        B.sc2Waiting = false
        saveSC2State("fallback")
        return
    end

    local generated = SC.GeneratedCatalog or {}
    local clientNonce = newClientNonce()
    CS.BeginConnect(clientNonce)
    local body = table.concat({
        "H",
        tostring(B.sc2Version),
        clientNonce,
        tostring(SC.VERSION or "unknown"),
        tostring(generated.metadataVersion or "unknown"),
        tostring(generated.assetPackVersion or "unknown"),
    }, "|")
    saveSC2State("waiting")
    SendAddonMessage(B.sc2Prefix, body, "WHISPER", playerName)
end

function B.Reconnect()
    B.Connect(true)
    B.ConnectSC2(true)
end

function B.OnLogin()
    B.attempted = false
    B.sc2Attempted = false
    B.Connect()
    B.ConnectSC2()
end

function B.RequestSC2Action(typeId, collectionId, actionId, target, callback)
    if not B.sc2Connected or not CS or not CS.sessionNonce or
        not isPositiveInteger(typeId) or not isPositiveInteger(collectionId) or
        not isActionToken(actionId) or not CS.categories[typeId] or
        CS.categories[typeId].state ~= "Ready" then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end
    if target ~= nil and not isPositiveInteger(target) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_TARGET_SLOT")
        end
        return nil
    end
    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        return nil
    end
    requestSerial = requestSerial + 1
    local requestId = requestSerial
    sc2PendingActions[requestId] = {
        deadline = GetTime() + requestTimeout,
        typeId = typeId,
        collectionId = collectionId,
        callback = callback,
    }
    local body = table.concat({
        "Q", CS.sessionNonce, tostring(requestId), tostring(typeId), tostring(collectionId),
        tostring(actionId), target and tostring(target) or "-",
    }, "|")
    SendAddonMessage(B.sc2Prefix, body, "WHISPER", playerName)
    return requestId
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

function B.SummonMount(collectionId, callback)
    if not isPositiveInteger(collectionId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_COLLECTION_ID")
        end
        return nil
    end
    if not B.sc2Connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end
    -- collectionId is the stable logical ID. No spellId, creatureId, or
    -- client-owned bit is ever sent to the authoritative action endpoint.
    return B.RequestSC2Action(10, collectionId, "SUMMON", nil, callback)
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

function B.SummonPet(collectionId, callback)
    if not isPositiveInteger(collectionId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_PET_ID")
        end
        return nil
    end
    if not B.sc2Connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end
    return B.RequestSC2Action(11, collectionId, "SUMMON", nil, callback)
end

function B.UseToy(collectionId, callback)
    if not isPositiveInteger(collectionId) then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_TOY_ID")
        end
        return nil
    end
    if not B.sc2Connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end
    local target = nil
    for _, collection in ipairs((SC.GeneratedCatalog or {}).collections or {}) do
        if collection.typeKey == "toy" and collection.collectionId == collectionId then
            if collection.requiresTarget then
                target = 1
            end
            break
        end
    end
    return B.RequestSC2Action(12, collectionId, "USE", target, callback)
end

function B.ApplyAppearance(collectionId, equipmentSlot, callback)
    if not isPositiveInteger(collectionId) or type(equipmentSlot) ~= "number" or
        equipmentSlot ~= math.floor(equipmentSlot) or equipmentSlot < 0 or equipmentSlot > 18 then
        if type(callback) == "function" then
            pcall(callback, false, "INVALID_TARGET_SLOT")
        end
        return nil
    end
    if not B.sc2Connected then
        if type(callback) == "function" then
            pcall(callback, false, "BRIDGE_UNAVAILABLE")
        end
        return nil
    end
    -- Target is encoded as slot + 1 because '-' is reserved for actions with
    -- no target and the SC2 numeric target grammar is strictly positive.
    return B.RequestSC2Action(13, collectionId, "APPLY", equipmentSlot + 1, callback)
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
    if prefix == B.sc2Prefix then
        if channel ~= "WHISPER" or sender ~= UnitName("player") or type(message) ~= "string" or not CS then
            return
        end
        local event, detail, reason = CS.HandleMessage(message, GetTime())
        if event == "HELLO_ACK" then
            B.sc2Waiting = false
            B.sc2Connected = true
            saveSC2State("connected")
        elseif event == "ACTION_RESULT" then
            local fields = detail
            local requestId = tonumber(fields[3])
            local pending = requestId and sc2PendingActions[requestId] or nil
            if pending and pending.typeId == tonumber(fields[5]) and pending.collectionId == tonumber(fields[6]) then
                sc2PendingActions[requestId] = nil
                if type(pending.callback) == "function" then
                    local status = fields[4]
                    pcall(pending.callback, status == "ACCEPTED" or status == "DISMISSED", status)
                end
            end
        elseif event == "ERROR" then
            local requestId = tonumber(detail)
            local pending = requestId and sc2PendingActions[requestId] or nil
            if pending then
                sc2PendingActions[requestId] = nil
                if type(pending.callback) == "function" then
                    pcall(pending.callback, false, reason)
                end
            end
            saveSC2State(reason == "LOADING" and "waiting" or "failed")
        end
        return
    end
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
