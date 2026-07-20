local SC = SoloCollections

local CS = SC.CollectionState or {}
SC.CollectionState = CS

CS.protocolVersion = 1
CS.state = "Loading"
CS.authoritative = false
CS.sessionNonce = nil
CS.accountRevision = "0"
CS.categories = CS.categories or {}
CS.pendingTransfers = {}
CS.queuedDeltas = {}

local MAX_BODY_BYTES = 240
local MAX_CHUNK_BYTES = 160
local MAX_SNAPSHOT_CHUNKS = 256
local MAX_SNAPSHOT_BYTES = 32768
local TRANSFER_TIMEOUT = 5
local MAX_RESYNC_REQUESTS = 3
local sender = nil
local changedCallback = nil
local expectedMappingCount = 0
local receivedMappingCount = 0
local lastResyncAt = -100
local resyncCount = 0

local CATEGORY_TYPE_KEYS = {
    MOUNTS = "mount",
    PETS = "companion",
    TOYS = "toy",
    APPEARANCES = "appearance",
    SETS = "set",
}

local typeDefinitions = {}
local typeIdByKey = {}
local expectedHashByTypeId = {}

local function rebuildTypeDefinitions()
    typeDefinitions = {}
    typeIdByKey = {}
    expectedHashByTypeId = {}
    local generated = SC.GeneratedCatalog or {}
    for _, definition in ipairs(generated.collectionTypes or {}) do
        local typeId = tonumber(definition.typeId)
        if typeId and typeId > 0 and typeId == math.floor(typeId) and type(definition.typeKey) == "string" then
            typeDefinitions[typeId] = definition
            typeIdByKey[definition.typeKey] = typeId
            if generated.typeMappingHashes then
                expectedHashByTypeId[typeId] = generated.typeMappingHashes[definition.typeKey]
            end
        end
    end
end

rebuildTypeDefinitions()

local function notifyChanged(typeId)
    if type(changedCallback) == "function" then
        pcall(changedCallback, CS.state, typeId)
    end
    if SC.UI and SC.UI.RefreshActivePage then
        SC.UI.RefreshActivePage()
    end
end

local function setGlobalState(state, typeId)
    if CS.state ~= state then
        CS.state = state
        notifyChanged(typeId)
    elseif typeId then
        notifyChanged(typeId)
    end
end

local function splitFields(message)
    local fields = {}
    local start = 1
    while true do
        local separator = string.find(message, "|", start, true)
        if not separator then
            table.insert(fields, string.sub(message, start))
            return fields
        end
        table.insert(fields, string.sub(message, start, separator - 1))
        start = separator + 1
    end
end

local function isCanonicalDecimal(value, maxDigits)
    if type(value) ~= "string" or value == "" or #value > maxDigits or not string.match(value, "^%d+$") then
        return false
    end
    return value == "0" or string.sub(value, 1, 1) ~= "0"
end

local function parseBoundedInteger(value, maxDigits, minimum, maximum)
    if not isCanonicalDecimal(value, maxDigits) then
        return nil
    end
    local number = tonumber(value)
    if not number or number < minimum or number > maximum or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function isLowerHex(value, size)
    return type(value) == "string" and #value == size and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function isToken(value)
    return type(value) == "string" and #value >= 1 and #value <= 32 and
        string.match(value, "^[A-Za-z0-9._~%-]+$") ~= nil
end

local function compareDecimal(left, right)
    left = tostring(left or "0")
    right = tostring(right or "0")
    if #left ~= #right then
        return #left < #right and -1 or 1
    end
    if left == right then
        return 0
    end
    return left < right and -1 or 1
end

local function incrementDecimal(value)
    local digits = {}
    for index = 1, #value do
        digits[index] = string.byte(value, index) - 48
    end
    local carry = 1
    for index = #digits, 1, -1 do
        local digit = digits[index] + carry
        digits[index] = digit % 10
        carry = math.floor(digit / 10)
        if carry == 0 then
            break
        end
    end
    if carry > 0 then
        table.insert(digits, 1, carry)
    end
    local result = ""
    for _, digit in ipairs(digits) do
        result = result .. tostring(digit)
    end
    return result
end

local function adler32Hex(payload)
    local first = 1
    local second = 0
    for index = 1, #payload do
        first = (first + string.byte(payload, index)) % 65521
        second = (second + first) % 65521
    end
    return string.format("%08x", second * 65536 + first)
end

CS.adler32Hex = adler32Hex

local function base36Digit(character)
    local byte = string.byte(character)
    if byte >= 48 and byte <= 57 then
        return byte - 48
    end
    if byte >= 97 and byte <= 122 then
        return byte - 87
    end
    return nil
end

local function toBase36(value)
    local alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    if value == 0 then
        return "0"
    end
    local result = ""
    while value > 0 do
        local digit = value % 36
        result = string.sub(alphabet, digit + 1, digit + 1) .. result
        value = math.floor(value / 36)
    end
    return result
end

local function parseBase36(value)
    if type(value) ~= "string" or value == "" or not string.match(value, "^[0-9a-z]+$") then
        return nil
    end
    local result = 0
    for index = 1, #value do
        local digit = base36Digit(string.sub(value, index, index))
        if not digit or result > math.floor((4294967295 - digit) / 36) then
            return nil
        end
        result = result * 36 + digit
    end
    if toBase36(result) ~= value then
        return nil
    end
    return result
end

local function parseOwnedPayload(payload)
    local owned = {}
    if payload == "-" then
        return owned
    end
    if type(payload) ~= "string" or payload == "" or not string.match(payload, "^[0-9a-z,]+$") then
        return nil
    end
    local previous = -1
    local start = 1
    while true do
        local separator = string.find(payload, ",", start, true)
        local token = separator and string.sub(payload, start, separator - 1) or string.sub(payload, start)
        local collectionId = parseBase36(token)
        if not collectionId or collectionId <= previous then
            return nil
        end
        owned[collectionId] = true
        previous = collectionId
        if not separator then
            break
        end
        start = separator + 1
    end
    return owned
end

CS.parseOwnedPayload = parseOwnedPayload

local function categoryFor(typeId)
    return CS.categories[typeId]
end

local function hasPendingTransfers()
    return next(CS.pendingTransfers) ~= nil
end

local function requestResync(reason, typeId, now)
    if not CS.sessionNonce or type(sender) ~= "function" then
        return false
    end
    now = tonumber(now) or 0
    if resyncCount >= MAX_RESYNC_REQUESTS or now - lastResyncAt < 0.5 then
        return false
    end
    resyncCount = resyncCount + 1
    lastResyncAt = now
    local body = table.concat({
        "S", CS.sessionNonce, reason, tostring(typeId or 0), CS.accountRevision,
    }, "|")
    pcall(sender, body)
    return true
end

CS.requestResync = requestResync

local function applyDelta(delta)
    local category = categoryFor(delta.typeId)
    if not category or category.state ~= "Ready" then
        return false
    end
    if delta.operation == "A" then
        category.owned[delta.collectionId] = true
    else
        category.owned[delta.collectionId] = nil
    end
    CS.accountRevision = delta.revision
    notifyChanged(delta.typeId)
    return true
end

local function applyQueuedDeltas()
    while true do
        local expected = incrementDecimal(CS.accountRevision)
        local delta = CS.queuedDeltas[expected]
        if not delta or not applyDelta(delta) then
            return
        end
        CS.queuedDeltas[expected] = nil
    end
end

local function refreshGlobalState(typeId)
    local loading = false
    local ready = false
    local mismatch = false
    local failed = false
    for _, category in pairs(CS.categories) do
        if category.enabled then
            loading = loading or category.state == "Loading"
            ready = ready or category.state == "Ready"
            mismatch = mismatch or category.state == "Mismatch"
            failed = failed or category.state == "Failed"
        end
    end
    if loading then
        setGlobalState("Loading", typeId)
    elseif ready then
        setGlobalState("Ready", typeId)
    elseif mismatch then
        setGlobalState("Mismatch", typeId)
    elseif failed then
        setGlobalState("Failed", typeId)
    elseif receivedMappingCount >= expectedMappingCount then
        setGlobalState("Ready", typeId)
    end
end

local function failTransfer(transfer, reason, now)
    CS.pendingTransfers[transfer.transferId] = nil
    local category = categoryFor(transfer.typeId)
    if category then
        category.lastError = reason
        if not category.hasSnapshot then
            category.state = "Failed"
        end
    end
    requestResync(reason, transfer.typeId, now)
    refreshGlobalState(transfer.typeId)
end

local function commitSnapshot(transfer, payload)
    local owned = parseOwnedPayload(payload)
    if not owned then
        return false
    end
    local category = categoryFor(transfer.typeId)
    if not category or category.state == "Mismatch" then
        return false
    end
    category.owned = owned
    category.hasSnapshot = true
    category.state = "Ready"
    category.revision = transfer.baseRevision
    category.lastError = nil
    if compareDecimal(transfer.baseRevision, CS.accountRevision) >= 0 then
        CS.accountRevision = transfer.baseRevision
    end
    CS.pendingTransfers[transfer.transferId] = nil
    applyQueuedDeltas()
    refreshGlobalState(transfer.typeId)
    return true
end

CS.commitSnapshot = commitSnapshot

local function handleHelloAck(fields)
    if #fields ~= 9 or fields[2] ~= "1" or not isLowerHex(fields[3], 16) or
        not isCanonicalDecimal(fields[4], 20) or not isLowerHex(fields[5], 8) or
        not isToken(fields[6]) or not isToken(fields[7]) or not isToken(fields[8]) then
        return nil
    end
    local categoryCount = parseBoundedInteger(fields[9], 3, 0, 255)
    if not categoryCount then
        return nil
    end

    rebuildTypeDefinitions()
    CS.authoritative = true
    CS.sessionNonce = fields[3]
    CS.accountRevision = fields[4]
    CS.enabledCategoryFlags = fields[5]
    CS.metadataVersion = fields[6]
    CS.assetPackVersion = fields[7]
    CS.backendBuild = fields[8]
    CS.metadataMismatch = CS.metadataVersion ~= tostring((SC.GeneratedCatalog or {}).metadataVersion or "")
    CS.assetMismatch = CS.assetPackVersion ~= tostring((SC.GeneratedCatalog or {}).assetPackVersion or "")
    CS.pendingTransfers = {}
    CS.queuedDeltas = {}
    expectedMappingCount = categoryCount
    receivedMappingCount = 0
    resyncCount = 0
    lastResyncAt = -100
    for typeId, definition in pairs(typeDefinitions) do
        local previous = CS.categories[typeId]
        CS.categories[typeId] = {
            typeId = typeId,
            typeKey = definition.typeKey,
            enabled = false,
            state = "Disabled",
            owned = previous and previous.owned or {},
            hasSnapshot = previous and previous.hasSnapshot or false,
            revision = previous and previous.revision or "0",
        }
    end
    setGlobalState("Loading")
    if categoryCount == 0 then
        refreshGlobalState()
    end
    return "HELLO_ACK"
end

local function handleCategoryMap(fields)
    if #fields ~= 4 or fields[2] ~= CS.sessionNonce then
        return nil
    end
    local typeId = parseBoundedInteger(fields[3], 5, 1, 65535)
    if not typeId or not isLowerHex(fields[4], 64) then
        return nil
    end
    local category = CS.categories[typeId]
    if not category then
        category = { typeId = typeId, typeKey = "unknown", owned = {}, hasSnapshot = false }
        CS.categories[typeId] = category
    end
    if category.mappingHash then
        if category.mappingHash ~= fields[4] then
            category.state = "Mismatch"
            category.lastError = "CATALOG_MISMATCH"
            requestResync("CATALOG_MISMATCH", typeId, 0)
        end
        return "CATEGORY_MAP"
    end
    category.enabled = true
    category.mappingHash = fields[4]
    receivedMappingCount = receivedMappingCount + 1
    if expectedHashByTypeId[typeId] == fields[4] then
        category.state = "Loading"
    else
        category.state = "Mismatch"
        category.lastError = "CATALOG_MISMATCH"
    end
    refreshGlobalState(typeId)
    return "CATEGORY_MAP"
end

local function handleSnapshotBegin(fields, now)
    if #fields ~= 8 or fields[2] ~= CS.sessionNonce then
        return nil
    end
    local transferId = parseBoundedInteger(fields[3], 10, 1, 4294967295)
    local typeId = parseBoundedInteger(fields[4], 5, 1, 65535)
    local total = parseBoundedInteger(fields[5], 3, 1, MAX_SNAPSHOT_CHUNKS)
    local baseRevision = isCanonicalDecimal(fields[6], 20) and fields[6] or nil
    local payloadBytes = parseBoundedInteger(fields[8], 5, 1, MAX_SNAPSHOT_BYTES)
    local category = typeId and categoryFor(typeId) or nil
    if not transferId or not typeId or not total or not baseRevision or not isLowerHex(fields[7], 8) or
        not payloadBytes or not category or not category.enabled or category.state == "Mismatch" then
        return nil
    end
    local existing = CS.pendingTransfers[transferId]
    if existing then
        if existing.typeId ~= typeId or existing.total ~= total or existing.baseRevision ~= baseRevision or
            existing.checksum ~= fields[7] or existing.payloadBytes ~= payloadBytes then
            failTransfer(existing, "CHECKSUM_MISMATCH", now)
        end
        return "SNAPSHOT_BEGIN"
    end
    CS.pendingTransfers[transferId] = {
        transferId = transferId,
        typeId = typeId,
        total = total,
        baseRevision = baseRevision,
        checksum = fields[7],
        payloadBytes = payloadBytes,
        chunks = {},
        received = 0,
        deadline = now + TRANSFER_TIMEOUT,
    }
    return "SNAPSHOT_BEGIN"
end

local function handleSnapshotChunk(fields, now)
    if #fields ~= 5 or fields[2] ~= CS.sessionNonce then
        return nil
    end
    local transferId = parseBoundedInteger(fields[3], 10, 1, 4294967295)
    local seq = parseBoundedInteger(fields[4], 3, 1, MAX_SNAPSHOT_CHUNKS)
    local payload = fields[5]
    local transfer = transferId and CS.pendingTransfers[transferId] or nil
    if not transfer or not seq or seq > transfer.total or #payload < 1 or #payload > MAX_CHUNK_BYTES or
        not string.match(payload, "^[0-9a-z,%-]+$") then
        return nil
    end
    if transfer.chunks[seq] then
        if transfer.chunks[seq] ~= payload then
            failTransfer(transfer, "CHECKSUM_MISMATCH", now)
        end
        return "SNAPSHOT_CHUNK"
    end
    transfer.chunks[seq] = payload
    transfer.received = transfer.received + 1
    transfer.deadline = now + TRANSFER_TIMEOUT
    return "SNAPSHOT_CHUNK"
end

local function handleSnapshotEnd(fields, now)
    if #fields ~= 4 or fields[2] ~= CS.sessionNonce then
        return nil
    end
    local transferId = parseBoundedInteger(fields[3], 10, 1, 4294967295)
    local transfer = transferId and CS.pendingTransfers[transferId] or nil
    if not transfer or not isLowerHex(fields[4], 8) then
        return nil
    end
    if transfer.received ~= transfer.total or fields[4] ~= transfer.checksum then
        failTransfer(transfer, "CHECKSUM_MISMATCH", now)
        return "SNAPSHOT_END"
    end
    local chunks = {}
    for seq = 1, transfer.total do
        if not transfer.chunks[seq] then
            failTransfer(transfer, "CHECKSUM_MISMATCH", now)
            return "SNAPSHOT_END"
        end
        chunks[seq] = transfer.chunks[seq]
    end
    local payload = table.concat(chunks)
    if #payload ~= transfer.payloadBytes or adler32Hex(payload) ~= transfer.checksum or
        not commitSnapshot(transfer, payload) then
        failTransfer(transfer, "CHECKSUM_MISMATCH", now)
    end
    return "SNAPSHOT_END"
end

local function handleDelta(fields, now)
    if #fields ~= 6 or fields[2] ~= CS.sessionNonce then
        return nil
    end
    local typeId = parseBoundedInteger(fields[3], 5, 1, 65535)
    local revision = isCanonicalDecimal(fields[4], 20) and fields[4] or nil
    local operation = (fields[5] == "A" or fields[5] == "R") and fields[5] or nil
    local collectionId = parseBoundedInteger(fields[6], 10, 1, 4294967295)
    if not typeId or not revision or not operation or not collectionId then
        return nil
    end
    if compareDecimal(revision, CS.accountRevision) <= 0 then
        return "DELTA"
    end
    local delta = { typeId = typeId, revision = revision, operation = operation, collectionId = collectionId }
    if hasPendingTransfers() then
        local existing = CS.queuedDeltas[revision]
        if existing and (existing.typeId ~= typeId or existing.operation ~= operation or existing.collectionId ~= collectionId) then
            requestResync("REVISION_GAP", typeId, now)
            return "DELTA"
        end
        CS.queuedDeltas[revision] = delta
        return "DELTA"
    end
    if incrementDecimal(CS.accountRevision) ~= revision or not applyDelta(delta) then
        requestResync("REVISION_GAP", typeId, now)
    end
    return "DELTA"
end

local function handleError(fields)
    if #fields ~= 4 or fields[2] ~= CS.sessionNonce or
        not parseBoundedInteger(fields[3], 10, 0, 4294967295) or not string.match(fields[4], "^[A-Z_]+$") then
        return nil
    end
    if fields[4] == "LOADING" then
        setGlobalState("Loading")
    elseif fields[4] == "DB_UNAVAILABLE" then
        for _, category in pairs(CS.categories) do
            if category.enabled and category.state == "Loading" then
                category.state = "Failed"
                category.lastError = fields[4]
            end
        end
        setGlobalState("Failed")
    end
    return "ERROR", fields[3], fields[4]
end

local function handleActionResult(fields)
    if #fields ~= 7 or fields[2] ~= CS.sessionNonce or
        not parseBoundedInteger(fields[3], 10, 1, 4294967295) or
        not string.match(fields[4], "^[A-Z_]+$") or
        not parseBoundedInteger(fields[5], 5, 1, 65535) or
        not parseBoundedInteger(fields[6], 10, 1, 4294967295) or
        not isCanonicalDecimal(fields[7], 20) then
        return nil
    end
    return "ACTION_RESULT", fields
end

function CS.SetSender(callback)
    sender = callback
end

function CS.SetChangedCallback(callback)
    changedCallback = callback
end

function CS.BeginConnect(clientNonce)
    CS.clientNonce = clientNonce
    CS.sessionNonce = nil
    CS.pendingTransfers = {}
    CS.queuedDeltas = {}
    expectedMappingCount = 0
    receivedMappingCount = 0
    resyncCount = 0
    setGlobalState("Loading")
end

function CS.MarkUnavailable()
    if not CS.authoritative then
        setGlobalState("Failed")
    end
end

function CS.HandleMessage(message, now)
    now = tonumber(now) or 0
    if type(message) ~= "string" or #message < 1 or #message > MAX_BODY_BYTES or
        string.find(message, "[^%w|%._~,%-%:]" ) then
        return nil
    end
    local fields = splitFields(message)
    local code = fields[1]
    if code == "A" then
        return handleHelloAck(fields)
    end
    if not CS.sessionNonce then
        return nil
    end
    if code == "M" then return handleCategoryMap(fields) end
    if code == "B" then return handleSnapshotBegin(fields, now) end
    if code == "C" then return handleSnapshotChunk(fields, now) end
    if code == "E" then return handleSnapshotEnd(fields, now) end
    if code == "D" then return handleDelta(fields, now) end
    if code == "R" then return handleActionResult(fields) end
    if code == "X" then return handleError(fields) end
    return nil
end

function CS.Update(now)
    now = tonumber(now) or 0
    local expired = {}
    for _, transfer in pairs(CS.pendingTransfers) do
        if now >= transfer.deadline then
            table.insert(expired, transfer)
        end
    end
    for _, transfer in ipairs(expired) do
        failTransfer(transfer, "TRANSFER_TIMEOUT", now)
    end
end

function CS.HasAuthority()
    return CS.authoritative == true
end

function CS.GetState()
    return CS.state
end

function CS.GetRevision()
    return CS.accountRevision
end

function CS.GetCategoryState(category)
    local typeKey = CATEGORY_TYPE_KEYS[category] or category
    local typeId = typeIdByKey[typeKey]
    local state = typeId and CS.categories[typeId] or nil
    return state and state.state or (CS.authoritative and "Disabled" or "Demo")
end

function CS.ResolveOwned(category, collectionId, fallback)
    local typeKey = CATEGORY_TYPE_KEYS[category] or category
    local typeId = typeIdByKey[typeKey]
    if not CS.authoritative then
        return fallback and true or false, false, "Demo"
    end
    local state = typeId and CS.categories[typeId] or nil
    if not state or state.state ~= "Ready" then
        return false, false, state and state.state or "Disabled"
    end
    return state.owned[tonumber(collectionId)] == true, true, "Ready"
end

function CS.IsOwnedByType(typeId, collectionId)
    local category = CS.categories[tonumber(typeId)]
    return category and category.state == "Ready" and category.owned[tonumber(collectionId)] == true or false
end
