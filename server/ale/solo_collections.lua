-- SoloCollections V4 authenticated collection action bridge.

local function isEnabled(value)
    if value == nil or value == "" then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    if type(value) == "string" and string.lower(value) == "false" then
        return false
    end
    return true
end

local function getBackendMode()
    local value = GetConfigValue("SoloCollections.Backend")
    if value == nil or value == "" then
        return "compare"
    end
    return string.lower(tostring(value))
end

local BACKEND = getBackendMode()
local ENABLED = isEnabled(GetConfigValue("SoloCollections.Enabled")) and BACKEND ~= "cpp"
local PREFIX = "SC1"
local REQUEST = "HELLO|1"
local RESPONSE = "HELLO_ACK|1|DEMO"
local CHAT_MSG_WHISPER = 7
local SUMMON_ACCEPTED = "ACCEPTED"
local TOTAL_LIMIT_PER_SECOND = 20
local MODEL_LIMIT_PER_SECOND = 8
local SUMMON_LIMIT_PER_SECOND = 2
local PET_MODEL_LIMIT_PER_SECOND = 8
local PET_SUMMON_LIMIT_PER_SECOND = 2
local TOY_USE_LIMIT_PER_SECOND = 4

local function logInfo(message)
    if type(PrintInfo) == "function" then
        PrintInfo("[SoloCollections] " .. tostring(message))
    end
end

logInfo("event=sc1_bridge_load enabled=" .. tostring(ENABLED) .. " backend=" .. BACKEND)

local MOUNTS = {
    [1] = { creatureId = 24379, spellId = 43688, collected = true },
    [2] = { creatureId = 18545, spellId = 40192, collected = false },
    [3] = { creatureId = 14334, spellId = 22719, collected = true },
    [4] = { creatureId = 30542, spellId = 17481, collected = true },
    [5] = { creatureId = 24488, spellId = 43927, collected = false },
    [6] = { creatureId = 28302, spellId = 48778, collected = true },
    [7] = { creatureId = 18357, spellId = 32239, collected = true },
    [8] = { creatureId = 21354, spellId = 36702, collected = false },
    [9] = { creatureId = 24653, spellId = 44153, collected = true },
    [10] = { creatureId = 23455, spellId = 41513, collected = false },
    [11] = { creatureId = 15090, spellId = 24242, collected = true },
    [12] = { creatureId = 23408, spellId = 41252, collected = false },
    [13] = { creatureId = 17266, spellId = 30174, collected = true },
    [14] = { creatureId = 27153, spellId = 48025, collected = false },
    [15] = { creatureId = 29596, spellId = 54753, collected = true },
    [16] = { creatureId = 29929, spellId = 55531, collected = false },
    [17] = { creatureId = 31694, spellId = 59567, collected = true },
    [18] = { creatureId = 31717, spellId = 59569, collected = true },
    [19] = { creatureId = 31851, spellId = 59791, collected = false },
    [20] = { creatureId = 31902, spellId = 59961, collected = true },
    [21] = { creatureId = 32153, spellId = 60002, collected = false },
    [22] = { creatureId = 34187, spellId = 64731, collected = true },
    [23] = { creatureId = 38545, spellId = 72286, collected = false },
    [24] = { creatureId = 40625, spellId = 75614, collected = true },
}

local PETS = {
    [1] = { creatureId = 10259, spellId = 15999, collected = true },
    [2] = { creatureId = 10598, spellId = 16450, collected = false },
    [3] = { creatureId = 7545, spellId = 10698, collected = true },
    [4] = { creatureId = 28513, spellId = 51851, collected = false },
    [5] = { creatureId = 23274, spellId = 40990, collected = true },
    [6] = { creatureId = 23909, spellId = 42609, collected = true },
    [7] = { creatureId = 25062, spellId = 45082, collected = false },
    [8] = { creatureId = 16547, spellId = 28738, collected = true },
    [9] = { creatureId = 26119, spellId = 46599, collected = false },
    [10] = { creatureId = 29147, spellId = 53316, collected = true },
    [11] = { creatureId = 7391, spellId = 10682, collected = false },
    [12] = { creatureId = 15429, spellId = 25162, collected = true },
    [13] = { creatureId = 16548, spellId = 28739, collected = true },
    [14] = { creatureId = 12419, spellId = 19772, collected = false },
    [15] = { creatureId = 25110, spellId = 45127, collected = true },
    [16] = { creatureId = 21076, spellId = 36034, collected = false },
    [17] = { creatureId = 11327, spellId = 17709, collected = true },
    [18] = { creatureId = 11325, spellId = 17707, collected = false },
    [19] = { creatureId = 28883, spellId = 52615, collected = true },
    [20] = { creatureId = 23234, spellId = 40549, collected = false },
    [21] = { creatureId = 29726, spellId = 55068, collected = true },
    [22] = { creatureId = 31575, spellId = 59250, collected = false },
    [23] = { creatureId = 32791, spellId = 61725, collected = true },
    [24] = { creatureId = 36607, spellId = 69002, collected = false },
}

local TOYS = {
    [1] = { itemId = 17712, spellId = 21848, collected = true },
    [2] = { itemId = 18660, spellId = 23126, collected = false },
    [3] = { itemId = 18986, spellId = 23453, collected = true },
    [4] = { itemId = 19026, spellId = 11544, collected = false },
    [5] = { itemId = 21540, spellId = 26265, collected = true },
    [6] = { itemId = 21589, spellId = 26333, collected = false },
    [7] = { itemId = 21713, spellId = 26374, collected = true },
    [8] = { itemId = 23767, spellId = 30261, collected = true },
    [9] = { itemId = 23821, spellId = 30427, collected = false },
    [10] = { itemId = 30542, spellId = 36890, collected = true },
    [11] = { itemId = 32542, spellId = 40527, collected = false },
    [12] = { itemId = 33223, spellId = 42766, collected = true },
    [13] = { itemId = 34480, spellId = 45094, collected = true },
    [14] = { itemId = 35275, spellId = 46354, collected = false },
    [15] = { itemId = 36863, spellId = 47770, collected = true },
    [16] = { itemId = 37254, spellId = 48332, collected = false },
    [17] = { itemId = 38301, spellId = 50317, collected = true },
    [18] = { itemId = 38506, spellId = 52172, collected = false },
    [19] = { itemId = 38578, spellId = 51640, collected = true },
    [20] = { itemId = 40768, spellId = 54710, collected = true },
    [21] = { itemId = 43499, spellId = 58501, collected = false },
    [22] = { itemId = 43824, spellId = 59317, collected = true },
    [23] = { itemId = 44430, spellId = 60458, collected = false },
    [24] = { itemId = 44606, spellId = 61031, collected = true },
    [25] = { itemId = 45063, spellId = 62985, collected = true },
    [26] = { itemId = 46780, spellId = 65783, collected = false },
    [27] = { itemId = 48933, spellId = 67833, collected = true },
    [28] = { itemId = 49703, spellId = 30161, collected = false },
    [29] = { itemId = 50471, spellId = 71909, collected = true },
    [30] = { itemId = 52201, spellId = 73320, collected = false },
    [31] = { itemId = 54651, spellId = 75531, collected = true },
    [32] = { itemId = 46779, spellId = 65745, collected = false },
    [33] = { itemId = 40769, spellId = 54711, collected = true },
    [34] = { itemId = 49040, spellId = 67826, collected = false },
    [35] = { itemId = 45984, spellId = 64385, collected = true },
    [36] = { itemId = 45057, spellId = 62949, collected = false },
}

local RATE_LIMITS = {}
local lastRateCleanup = 0

local function parsePositiveInteger(value)
    if type(value) ~= "string" then
        return nil
    end
    if not string.match(value, "^%d+$") then
        return nil
    end
    local number = tonumber(value)
    if not number or number <= 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function checkRateLimit(sender, operation, limit)
    local guid = sender:GetGUIDLow()
    local now = os.time()

    if now - lastRateCleanup >= 60 then
        for playerGuid, bucket in pairs(RATE_LIMITS) do
            if bucket.second < now - 1 then
                RATE_LIMITS[playerGuid] = nil
            end
        end
        lastRateCleanup = now
    end

    local bucket = RATE_LIMITS[guid]
    if not bucket or bucket.second ~= now then
        bucket = { second = now, counts = {} }
        RATE_LIMITS[guid] = bucket
    end

    local count = bucket.counts[operation] or 0
    if count >= limit then
        return false
    end
    bucket.counts[operation] = count + 1
    return true
end

local function sendSummonError(sender, requestId, reason)
    sender:SendAddonMessage(
        PREFIX,
        "SUMMON_RESULT|" .. requestId .. "|ERROR|" .. reason,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function sendSummonAccepted(sender, requestId, mountId)
    sender:SendAddonMessage(
        PREFIX,
        "SUMMON_RESULT|" .. requestId .. "|" .. SUMMON_ACCEPTED .. "|" .. mountId,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function sendPetSummonError(sender, requestId, reason)
    sender:SendAddonMessage(
        PREFIX,
        "PET_SUMMON_RESULT|" .. requestId .. "|ERROR|" .. reason,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function sendPetSummonAccepted(sender, requestId, petId)
    sender:SendAddonMessage(
        PREFIX,
        "PET_SUMMON_RESULT|" .. requestId .. "|" .. SUMMON_ACCEPTED .. "|" .. petId,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function sendToyUseError(sender, requestId, reason)
    sender:SendAddonMessage(
        PREFIX,
        "TOY_USE_RESULT|" .. requestId .. "|ERROR|" .. reason,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function sendToyUseAccepted(sender, requestId, toyId)
    sender:SendAddonMessage(
        PREFIX,
        "TOY_USE_RESULT|" .. requestId .. "|" .. SUMMON_ACCEPTED .. "|" .. toyId,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function handleModel(sender, requestIdText, mountIdText)
    local requestId = parsePositiveInteger(requestIdText)
    local mountId = parsePositiveInteger(mountIdText)
    if not requestId or not mountId then
        return
    end

    local mount = MOUNTS[mountId]
    if not mount then
        return
    end
    if not checkRateLimit(sender, "MODEL", MODEL_LIMIT_PER_SECOND) then
        return
    end

    local ok, primed = pcall(function()
        return sender:PrimeCreatureQuery(mount.creatureId)
    end)
    if not ok or primed ~= true then
        return
    end

    sender:SendAddonMessage(
        PREFIX,
        "MODEL_READY|" .. requestId .. "|" .. mountId,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function handleSummon(sender, requestIdText, mountIdText)
    local requestId = parsePositiveInteger(requestIdText)
    local mountId = parsePositiveInteger(mountIdText)
    if not requestId then
        return
    end
    if not mountId then
        sendSummonError(sender, requestId, "INVALID_MOUNT_ID")
        return
    end

    local mount = MOUNTS[mountId]
    if not mount then
        sendSummonError(sender, requestId, "UNKNOWN_MOUNT")
        return
    end
    if not mount.collected then
        sendSummonError(sender, requestId, "NOT_COLLECTED")
        return
    end
    if not checkRateLimit(sender, "SUMMON", SUMMON_LIMIT_PER_SECOND) then
        sendSummonError(sender, requestId, "RATE_LIMITED")
        return
    end
    if sender:IsDead() then
        sendSummonError(sender, requestId, "DEAD")
        return
    end
    if sender:IsInCombat() then
        sendSummonError(sender, requestId, "IN_COMBAT")
        return
    end
    if sender:IsOnVehicle() then
        sendSummonError(sender, requestId, "IN_VEHICLE")
        return
    end
    if sender:IsFlying() then
        sendSummonError(sender, requestId, "FLYING")
        return
    end

    if sender:IsMounted() then
        sender:Dismount()
    end

    local spellId = mount.spellId
    local accepted = pcall(function()
        sender:CastSpell(sender, spellId, false)
    end)
    if not accepted then
        sendSummonError(sender, requestId, "CAST_FAILED")
        return
    end

    sendSummonAccepted(sender, requestId, mountId)
end

local function handlePetModel(sender, requestIdText, petIdText)
    local requestId = parsePositiveInteger(requestIdText)
    local petId = parsePositiveInteger(petIdText)
    if not requestId or not petId then
        return
    end

    local pet = PETS[petId]
    if not pet then
        return
    end
    if not checkRateLimit(sender, "PET_MODEL", PET_MODEL_LIMIT_PER_SECOND) then
        return
    end

    local ok, primed = pcall(function()
        return sender:PrimeCreatureQuery(pet.creatureId)
    end)
    if not ok or primed ~= true then
        return
    end

    sender:SendAddonMessage(
        PREFIX,
        "PET_MODEL_READY|" .. requestId .. "|" .. petId,
        CHAT_MSG_WHISPER,
        sender
    )
end

local function handlePetSummon(sender, requestIdText, petIdText)
    local requestId = parsePositiveInteger(requestIdText)
    local petId = parsePositiveInteger(petIdText)
    if not requestId then
        return
    end
    if not petId then
        sendPetSummonError(sender, requestId, "INVALID_PET_ID")
        return
    end

    local pet = PETS[petId]
    if not pet then
        sendPetSummonError(sender, requestId, "UNKNOWN_PET")
        return
    end
    if not pet.collected then
        sendPetSummonError(sender, requestId, "NOT_COLLECTED")
        return
    end
    if not checkRateLimit(sender, "PET_SUMMON", PET_SUMMON_LIMIT_PER_SECOND) then
        sendPetSummonError(sender, requestId, "RATE_LIMITED")
        return
    end
    if sender:IsDead() then
        sendPetSummonError(sender, requestId, "DEAD")
        return
    end
    if sender:IsInCombat() then
        sendPetSummonError(sender, requestId, "IN_COMBAT")
        return
    end
    if sender:IsOnVehicle() then
        sendPetSummonError(sender, requestId, "IN_VEHICLE")
        return
    end
    if sender:IsFlying() then
        sendPetSummonError(sender, requestId, "FLYING")
        return
    end

    local spellId = pet.spellId
    local accepted = pcall(function()
        sender:CastSpell(sender, spellId, false)
    end)
    if not accepted then
        sendPetSummonError(sender, requestId, "CAST_FAILED")
        return
    end

    sendPetSummonAccepted(sender, requestId, petId)
end

local function handleToyUse(sender, requestIdText, toyIdText)
    local requestId = parsePositiveInteger(requestIdText)
    local toyId = parsePositiveInteger(toyIdText)
    if not requestId then
        return
    end
    if not toyId then
        sendToyUseError(sender, requestId, "INVALID_TOY_ID")
        return
    end

    local toy = TOYS[toyId]
    if not toy then
        sendToyUseError(sender, requestId, "UNKNOWN_TOY")
        return
    end
    if not toy.collected then
        sendToyUseError(sender, requestId, "NOT_COLLECTED")
        return
    end
    if not checkRateLimit(sender, "TOY_USE", TOY_USE_LIMIT_PER_SECOND) then
        sendToyUseError(sender, requestId, "RATE_LIMITED")
        return
    end
    if sender:IsDead() then
        sendToyUseError(sender, requestId, "DEAD")
        return
    end
    if sender:IsOnVehicle() then
        sendToyUseError(sender, requestId, "IN_VEHICLE")
        return
    end

    local spellId = toy.spellId
    local accepted = pcall(function()
        sender:CastSpell(sender, spellId, false)
    end)
    if not accepted then
        sendToyUseError(sender, requestId, "CAST_FAILED")
        return
    end

    sendToyUseAccepted(sender, requestId, toyId)
end

local function onAddonMessage(event, sender, messageType, prefix, message, target)
    if prefix == PREFIX and message == REQUEST then
        logInfo("event=sc1_handshake result=received enabled=" .. tostring(ENABLED))
    end
    if not ENABLED then
        return true
    end
    if not sender then
        return true
    end
    if prefix ~= PREFIX then
        return true
    end
    if type(message) ~= "string" then
        return true
    end
    if not checkRateLimit(sender, "TOTAL", TOTAL_LIMIT_PER_SECOND) then
        return true
    end

    if message == REQUEST then
        sender:SendAddonMessage(PREFIX, RESPONSE, CHAT_MSG_WHISPER, sender)
        logInfo("event=sc1_handshake result=accepted")
        return true
    end

    local modelRequestId, modelMountId = string.match(message, "^MODEL|(%d+)|(%d+)$")
    if modelRequestId then
        handleModel(sender, modelRequestId, modelMountId)
        return true
    end

    local summonRequestId, summonMountId = string.match(message, "^SUMMON|(%d+)|(%d+)$")
    if summonRequestId then
        handleSummon(sender, summonRequestId, summonMountId)
        return true
    end

    local petModelRequestId, petModelId = string.match(message, "^PET_MODEL|(%d+)|(%d+)$")
    if petModelRequestId then
        handlePetModel(sender, petModelRequestId, petModelId)
        return true
    end

    local petSummonRequestId, petSummonId = string.match(message, "^PET_SUMMON|(%d+)|(%d+)$")
    if petSummonRequestId then
        handlePetSummon(sender, petSummonRequestId, petSummonId)
        return true
    end


    local toyUseRequestId, toyUseId = string.match(message, "^TOY_USE|(%d+)|(%d+)$")
    if toyUseRequestId then
        handleToyUse(sender, toyUseRequestId, toyUseId)
        return true
    end

    return true
end

if ENABLED then
    RegisterServerEvent(30, onAddonMessage)
else
    logInfo("event=sc1_bridge_register result=disabled backend=" .. BACKEND)
end
