local SC = SoloCollections

-- Lua-facing controller for the SoloCam v7 item-camera bridge.  The encoded
-- requests are private transport; callers only provide a pose relative to the
-- active M2 camera 0.
local M2Camera = SC.M2Camera or {}
SC.M2Camera = M2Camera

M2Camera.VERSION = 2

-- 以下是 Lua 与 SoloCam.dll 的私有传输协议；外观数据不要直接使用这些常量，
-- 只需填写下方 M2Camera.Apply 的 pose 参数。
local REQUEST_YAW_PITCH = 0x51000000
local REQUEST_DISTANCE_TARGET_Z = 0x52000000
local REQUEST_TARGET_XY = 0x53000000
local REQUEST_ACTIVATE = 0x54000000
local REQUEST_ROLL = 0x55000000
-- Body profile deltas use a separate 0x7 command family.  It is deliberately
-- outside generated character sentinels, the 0x5 item-camera transport, and
-- the 0x6F direct-display request base.
local REQUEST_BODY_BEGIN = 0x71000000
local REQUEST_BODY_HASH_CHUNK = 0x72000000
local REQUEST_BODY_VERTICAL_HORIZONTAL = 0x73000000
local REQUEST_BODY_DISTANCE_MINIMUM = 0x74000000
local REQUEST_BODY_YAW = 0x75000000
local REQUEST_BODY_ACTIVATE = 0x76000000
local QUANTIZATION = 4095
local PAIR_FACTOR = 4096
local PI = math.pi
-- 与 DLL 保持一致的输入限制。超出范围不会报错，而是被钳制到边界。
local PITCH_LIMIT = 1.20
local MINIMUM_DISTANCE_SCALE = 0.25
local MAXIMUM_DISTANCE_SCALE = 4.00
local MAXIMUM_TARGET_OFFSET = 4.00
local BODY_PROTOCOL_VERSION = 1
local BODY_MINIMUM_SOLOCAM_VERSION = 7
local BODY_HASH_CHUNK_COUNT = 13
local BODY_HASH_CHUNK_FACTOR = 1048576
local BODY_HASH_CHUNK_MAX = BODY_HASH_CHUNK_FACTOR - 1
local BODY_OFFSET_DELTA_LIMIT = 2.00
local BODY_MINIMUM_DISTANCE_DELTA_LIMIT = 2.00
local BODY_MINIMUM_DISTANCE_SCALE_MULTIPLIER = 0.50
local BODY_MAXIMUM_DISTANCE_SCALE_MULTIPLIER = 2.00

M2Camera.BODY_PROTOCOL_VERSION = BODY_PROTOCOL_VERSION
M2Camera.BODY_MINIMUM_SOLOCAM_VERSION = BODY_MINIMUM_SOLOCAM_VERSION
-- A new AddOn load begins without an attested native transport.  This must
-- remain process-local so a later stock-client launch cannot inherit write
-- access from SavedVariables.
M2Camera._bodyCameraRuntimeCapability = nil

-- Public limits for the in-game tuning panel. Keep these in the same Lua file
-- as the binary transport limits so a slider can never create a pose that the
-- SoloCam v7 decoder would clamp differently.
M2Camera.Limits = {
    yaw = { minimum = -PI, maximum = PI, step = 0.01 },
    pitch = { minimum = -PITCH_LIMIT, maximum = PITCH_LIMIT, step = 0.01 },
    roll = { minimum = -PI, maximum = PI, step = 0.01 },
    distanceScale = {
        minimum = MINIMUM_DISTANCE_SCALE,
        maximum = MAXIMUM_DISTANCE_SCALE,
        step = 0.01,
    },
    target = {
        minimum = -MAXIMUM_TARGET_OFFSET,
        maximum = MAXIMUM_TARGET_OFFSET,
        step = 0.01,
    },
}

M2Camera.BodyLimits = {
    verticalOffsetDelta = {
        minimum = -BODY_OFFSET_DELTA_LIMIT,
        maximum = BODY_OFFSET_DELTA_LIMIT,
        step = 0.01,
    },
    horizontalOffsetDelta = {
        minimum = -BODY_OFFSET_DELTA_LIMIT,
        maximum = BODY_OFFSET_DELTA_LIMIT,
        step = 0.01,
    },
    distanceScaleMultiplier = {
        minimum = BODY_MINIMUM_DISTANCE_SCALE_MULTIPLIER,
        maximum = BODY_MAXIMUM_DISTANCE_SCALE_MULTIPLIER,
        step = 0.01,
    },
    minimumDistanceDelta = {
        minimum = -BODY_MINIMUM_DISTANCE_DELTA_LIMIT,
        maximum = BODY_MINIMUM_DISTANCE_DELTA_LIMIT,
        step = 0.01,
    },
    yawOffsetDelta = { minimum = -PI, maximum = PI, step = 0.01 },
}

local function finiteNumber(value, fallback)
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function quantize(value, minimum, maximum)
    local normalized = (clamp(value, minimum, maximum) - minimum) / (maximum - minimum)
    return math.floor(normalized * QUANTIZATION + 0.5)
end

local function packPair(lowValue, lowMinimum, lowMaximum, highValue, highMinimum, highMaximum)
    local low = quantize(lowValue, lowMinimum, lowMaximum)
    local high = quantize(highValue, highMinimum, highMaximum)
    return low + high * PAIR_FACTOR
end

local function targetComponent(target, index, key)
    if type(target) ~= "table" then return 0 end
    return finiteNumber(target[key], finiteNumber(target[index], 0))
end

-- Return a fresh, bounded pose suitable for UI state or SavedVariables. This
-- deliberately never mutates the record's m2Camera table: several records may
-- share one default table, while the tuning panel must adjust one record only.
function M2Camera.NormalizePose(pose)
    pose = type(pose) == "table" and pose or {}
    local target = pose.target
    return {
        yaw = clamp(finiteNumber(pose.yaw, 0), -PI, PI),
        pitch = clamp(finiteNumber(pose.pitch, 0), -PITCH_LIMIT, PITCH_LIMIT),
        roll = clamp(finiteNumber(pose.roll, 0), -PI, PI),
        distanceScale = clamp(
            finiteNumber(pose.distanceScale, 1),
            MINIMUM_DISTANCE_SCALE,
            MAXIMUM_DISTANCE_SCALE
        ),
        target = {
            clamp(targetComponent(target, 1, "x"), -MAXIMUM_TARGET_OFFSET, MAXIMUM_TARGET_OFFSET),
            clamp(targetComponent(target, 2, "y"), -MAXIMUM_TARGET_OFFSET, MAXIMUM_TARGET_OFFSET),
            clamp(targetComponent(target, 3, "z"), -MAXIMUM_TARGET_OFFSET, MAXIMUM_TARGET_OFFSET),
        },
    }
end

-- Body calibration is a compact delta relative to a generated profile, never
-- a copied five-field canonical profile.  Missing values normalize to the
-- identity correction so an untouched profile stays sparse in SavedVariables.
function M2Camera.NormalizeBodyDelta(delta)
    delta = type(delta) == "table" and delta or {}
    return {
        verticalOffsetDelta = clamp(
            finiteNumber(delta.verticalOffsetDelta, 0),
            -BODY_OFFSET_DELTA_LIMIT,
            BODY_OFFSET_DELTA_LIMIT
        ),
        horizontalOffsetDelta = clamp(
            finiteNumber(delta.horizontalOffsetDelta, 0),
            -BODY_OFFSET_DELTA_LIMIT,
            BODY_OFFSET_DELTA_LIMIT
        ),
        distanceScaleMultiplier = clamp(
            finiteNumber(delta.distanceScaleMultiplier, 1),
            BODY_MINIMUM_DISTANCE_SCALE_MULTIPLIER,
            BODY_MAXIMUM_DISTANCE_SCALE_MULTIPLIER
        ),
        minimumDistanceDelta = clamp(
            finiteNumber(delta.minimumDistanceDelta, 0),
            -BODY_MINIMUM_DISTANCE_DELTA_LIMIT,
            BODY_MINIMUM_DISTANCE_DELTA_LIMIT
        ),
        yawOffsetDelta = clamp(finiteNumber(delta.yawOffsetDelta, 0), -PI, PI),
    }
end

function M2Camera.BodyDeltaEquals(left, right)
    left = M2Camera.NormalizeBodyDelta(left)
    right = M2Camera.NormalizeBodyDelta(right)
    local epsilon = 0.0001
    return math.abs(left.verticalOffsetDelta - right.verticalOffsetDelta) <= epsilon
        and math.abs(left.horizontalOffsetDelta - right.horizontalOffsetDelta) <= epsilon
        and math.abs(left.distanceScaleMultiplier - right.distanceScaleMultiplier) <= epsilon
        and math.abs(left.minimumDistanceDelta - right.minimumDistanceDelta) <= epsilon
        and math.abs(left.yawOffsetDelta - right.yawOffsetDelta) <= epsilon
end

-- Produce the exact single-line table accepted by an appearance record. The
-- camera panel selects this text in an EditBox so it can be copied into
-- Data/Appearances.lua once the in-game composition is approved.
function M2Camera.FormatPose(pose)
    local normalized = M2Camera.NormalizePose(pose)
    return string.format(
        "m2Camera = { yaw = %.2f, pitch = %.2f, roll = %.2f, distanceScale = %.2f, target = { %.2f, %.2f, %.2f } }",
        normalized.yaw,
        normalized.pitch,
        normalized.roll,
        normalized.distanceScale,
        normalized.target[1],
        normalized.target[2],
        normalized.target[3]
    )
end

local function jsonQuote(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("[\r\n]", " ")
    return '"' .. value .. '"'
end

local function profileHashChunks(profileHash)
    if type(profileHash) ~= "string" or #profileHash ~= 64
        or profileHash:match("^[a-fA-F0-9]+$") == nil then
        return nil
    end
    local function hexValue(character)
        local byte = string.byte(character)
        if byte >= 48 and byte <= 57 then return byte - 48 end
        if byte >= 65 and byte <= 70 then return byte - 65 + 10 end
        return byte - 97 + 10
    end
    local chunks = {}
    for index = 0, BODY_HASH_CHUNK_COUNT - 1 do
        local offset = index * 5 + 1
        local width = math.min(5, #profileHash - offset + 1)
        local value = 0
        for position = 0, width - 1 do
            value = value * 16 + hexValue(string.sub(profileHash, offset + position, offset + position))
        end
        if width < 5 then value = value * 16 end
        if value < 0 or value > BODY_HASH_CHUNK_MAX then return nil end
        chunks[index + 1] = value
    end
    return chunks
end

-- A stock 3.3.5 client cannot report whether an injected DLL accepted a
-- private SetCamera request.  Keep body editing deny-by-default: deployment
-- tooling (or an explicit local diagnostic command) must attest the exact
-- protocol/SoloCam/profile tuple before the AddOn sends the 0x7 request family.
function M2Camera.GetBodyProfileCapability(profile)
    if type(profile) ~= "table" then return false, "PROFILE_UNAVAILABLE" end
    -- Do not persist this attestation in SavedVariables.  A persisted marker
    -- would make a later stock-client launch appear writable after its DLL had
    -- been removed.  Deployment/test tooling must attest each running client.
    local runtime = M2Camera._bodyCameraRuntimeCapability
    if type(runtime) ~= "table" then return false, "DLL_CAPABILITY_MISSING" end
    if runtime.protocolVersion ~= BODY_PROTOCOL_VERSION then return false, "PROTOCOL_VERSION_MISMATCH" end
    if runtime.soloCamVersion ~= BODY_MINIMUM_SOLOCAM_VERSION then return false, "SOLOCAM_VERSION_MISMATCH" end
    if runtime.profileVersion ~= profile.profileVersion then return false, "PROFILE_VERSION_MISMATCH" end
    if runtime.profileHash ~= profile.profileHash then return false, "PROFILE_HASH_MISMATCH" end
    return true, "READY"
end

function M2Camera.SetBodyProfileRuntimeCapability(capability)
    if type(capability) ~= "table" then return false end
    local profileVersion = tonumber(capability.profileVersion)
    local soloCamVersion = tonumber(capability.soloCamVersion)
    local profileHash = capability.profileHash
    if capability.protocolVersion ~= BODY_PROTOCOL_VERSION
        or soloCamVersion ~= BODY_MINIMUM_SOLOCAM_VERSION
        or profileVersion == nil or profileVersion < 1
        or type(profileHash) ~= "string" or #profileHash ~= 64
        or profileHash:match("^[a-fA-F0-9]+$") == nil then
        return false
    end
    M2Camera._bodyCameraRuntimeCapability = {
        protocolVersion = BODY_PROTOCOL_VERSION,
        soloCamVersion = BODY_MINIMUM_SOLOCAM_VERSION,
        profileVersion = math.floor(profileVersion),
        profileHash = string.lower(profileHash),
    }
    return true
end

function M2Camera.ClearBodyProfileRuntimeCapability()
    M2Camera._bodyCameraRuntimeCapability = nil
    return true
end

function M2Camera.FormatBodyTuningExportHeader(metadataVersion, assetPackVersion, profile)
    profile = type(profile) == "table" and profile or {}
    return string.format(
        '{"kind":"SoloCollectionsBodyCameraTuningExport","schemaVersion":1,"metadataVersion":%s,"assetPackVersion":%s,"cameraProfileVersion":%d,"cameraProfileHash":%s}',
        jsonQuote(metadataVersion),
        jsonQuote(assetPackVersion),
        math.max(0, math.floor(tonumber(profile.profileVersion) or 0)),
        jsonQuote(profile.profileHash)
    )
end

function M2Camera.FormatBodyTuningExportRecord(metadata, delta)
    metadata = type(metadata) == "table" and metadata or {}
    local normalized = M2Camera.NormalizeBodyDelta(delta)
    return string.format(
        '{"scope":"bodyProfile","profileKey":%s,"sentinel":%d,"raceToken":%s,"clientAssetProfile":%s,"sex":%s,"slot":%s,"cameraProfileVersion":%d,"cameraProfileHash":%s,"metadataVersion":%s,"assetPackVersion":%s,"delta":{"verticalOffsetDelta":%.4f,"horizontalOffsetDelta":%.4f,"distanceScaleMultiplier":%.4f,"minimumDistanceDelta":%.4f,"yawOffsetDelta":%.4f}}',
        jsonQuote(metadata.profileKey),
        math.max(0, math.floor(tonumber(metadata.sentinel) or 0)),
        jsonQuote(metadata.raceToken),
        jsonQuote(metadata.clientAssetProfile),
        jsonQuote(metadata.sex),
        jsonQuote(metadata.slot),
        math.max(0, math.floor(tonumber(metadata.profileVersion) or 0)),
        jsonQuote(metadata.profileHash),
        jsonQuote(metadata.metadataVersion),
        jsonQuote(metadata.assetPackVersion),
        normalized.verticalOffsetDelta,
        normalized.horizontalOffsetDelta,
        normalized.distanceScaleMultiplier,
        normalized.minimumDistanceDelta,
        normalized.yawOffsetDelta
    )
end

-- Camera workbench exports are JSON Lines rather than Lua snippets.  That
-- makes the copied text unambiguous, versioned and safe for the offline
-- importer to validate before anyone edits canonical presentation data.
function M2Camera.FormatTuningExportHeader(metadataVersion, assetPackVersion, appearancePresentationHash)
    return string.format(
        '{"kind":"SoloCollectionsCameraTuningExport","schemaVersion":2,"metadataVersion":%s,"assetPackVersion":%s,"appearancePresentationHash":%s}',
        jsonQuote(metadataVersion),
        jsonQuote(assetPackVersion),
        jsonQuote(appearancePresentationHash)
    )
end

function M2Camera.FormatTuningExportRecord(metadata, pose)
    metadata = type(metadata) == "table" and metadata or {}
    local normalized = M2Camera.NormalizePose(pose)
    return string.format(
        '{"scope":%s,"key":%s,"appearanceId":%d,"sourceItemId":%d,"nativeDisplayId":%d,"syntheticDisplayId":%d,"modelSignature":%s,"weaponFamily":%s,"weaponType":%s,"slot":%s,"metadataVersion":%s,"assetPackVersion":%s,"appearancePresentationHash":%s,"pose":{"yaw":%.4f,"pitch":%.4f,"roll":%.4f,"distanceScale":%.4f,"target":{"x":%.4f,"y":%.4f,"z":%.4f}}}',
        jsonQuote(metadata.scope),
        jsonQuote(metadata.key),
        math.max(0, math.floor(tonumber(metadata.appearanceId) or 0)),
        math.max(0, math.floor(tonumber(metadata.sourceItemId) or 0)),
        math.max(0, math.floor(tonumber(metadata.nativeDisplayId) or 0)),
        math.max(0, math.floor(tonumber(metadata.syntheticDisplayId) or 0)),
        jsonQuote(metadata.modelSignature),
        jsonQuote(metadata.weaponFamily),
        jsonQuote(metadata.weaponType),
        jsonQuote(metadata.slot),
        jsonQuote(metadata.metadataVersion),
        jsonQuote(metadata.assetPackVersion),
        jsonQuote(metadata.appearancePresentationHash),
        normalized.yaw,
        normalized.pitch,
        normalized.roll,
        normalized.distanceScale,
        normalized.target[1],
        normalized.target[2],
        normalized.target[3]
    )
end

local function sendCameraRequest(model, request)
    return pcall(function() model:SetCamera(request) end)
end

-- Apply a camera pose relative to M2 camera 0. The accepted pose fields are:
--
--   yaw (radians, -pi .. pi)
--     Horizontal orbit around the M2-local vertical axis.  0 preserves the
--     authored camera 0; use small increments (about 0.05) to correct which
--     endpoint is the lower-left hilt and which is the upper-right blade.
--
--   pitch (radians, -1.20 .. 1.20)
--     Camera elevation relative to camera 0.  Positive values lift the camera
--     and can make a long weapon look more vertical; tune in 0.05 increments.
--
--   roll（弧度，-pi .. pi）
--     沿当前相机视线轴的原生 M2 滚转。这是此前缺少的“画面内斜率”轴：
--     它只改变刀柄到刀刃的斜向，不会绕武器环绕，也不会改动 M2 原始构图。
--     请先按 +/- 0.05 试调；正负屏幕方向由客户端原生坐标决定，以游戏内
--     实际显示为准。
--
--   distanceScale (0.25 .. 4.00)
--     Multiplier for camera 0's authored distance.  Values above 1 zoom out
--     (smaller model/more margin); values below 1 zoom in.
--
--   target = { x, y, z } or { [1] = x, [2] = y, [3] = z } (-4 .. 4 each)
--     Translation in M2-local world units. It moves the complete camera rig
--     to pan the model in its card; these are not screen-space X/Y axes, so
--     their apparent direction depends on the active M2 camera.
--
-- 缺失或非有限数值会回退为 yaw/pitch/roll/target = 0、distanceScale = 1。
-- 最后的 activate 请求选择 M2 camera 0；SoloCam 只在此控件渲染期间覆盖
-- position、target 与原生 roll，随后立即恢复原始值。
function M2Camera.Apply(model, pose)
    if not model or type(model.SetCamera) ~= "function" then
        return false
    end

    local normalized = M2Camera.NormalizePose(pose)
    local target = normalized.target
    local yaw = normalized.yaw
    local pitch = normalized.pitch
    local roll = normalized.roll
    local distanceScale = normalized.distanceScale
    local targetX = target[1]
    local targetY = target[2]
    local targetZ = target[3]

    local yawPitch = REQUEST_YAW_PITCH + packPair(
        yaw, -PI, PI,
        pitch, -PITCH_LIMIT, PITCH_LIMIT
    )
    local distanceTargetZ = REQUEST_DISTANCE_TARGET_Z + packPair(
        distanceScale, MINIMUM_DISTANCE_SCALE, MAXIMUM_DISTANCE_SCALE,
        targetZ, -MAXIMUM_TARGET_OFFSET, MAXIMUM_TARGET_OFFSET
    )
    local targetXY = REQUEST_TARGET_XY + packPair(
        targetX, -MAXIMUM_TARGET_OFFSET, MAXIMUM_TARGET_OFFSET,
        targetY, -MAXIMUM_TARGET_OFFSET, MAXIMUM_TARGET_OFFSET
    )
    local rollRequest = REQUEST_ROLL + quantize(roll, -PI, PI)

    local yawPitchApplied = sendCameraRequest(model, yawPitch)
    local distanceApplied = yawPitchApplied and sendCameraRequest(model, distanceTargetZ)
    local targetApplied = distanceApplied and sendCameraRequest(model, targetXY)
    local rollApplied = targetApplied and sendCameraRequest(model, rollRequest)
    local activated = rollApplied and sendCameraRequest(model, REQUEST_ACTIVATE)
    return activated and true or false
end

-- Presenter-facing adapter: pages pass camera intent without reaching into the
-- legacy M2 implementation. A nil pose deliberately leaves the provider's native framing.
function M2Camera.ApplyPresenterPose(model, pose)
    if not pose then return false, "NO_POSE" end
    return M2Camera.Apply(model, pose)
end

-- Send a complete transactional body-profile correction.  The DLL will not
-- activate it until all full-hash chunks and all five delta fields have been
-- accepted for this model.  The final camera 1 request is intentional: it is
-- a same-tick stock-client fallback and is consumed by SoloCam only after a
-- valid body activation.
function M2Camera.ApplyBodyProfile(model, profile, delta)
    if not model or type(model.SetCamera) ~= "function" then
        return false, "MODEL_UNAVAILABLE"
    end
    if type(profile) ~= "table" or type(profile.sentinel) ~= "number"
        or profile.sentinel <= 1 then
        return false, "PROFILE_UNAVAILABLE"
    end
    local capability, capabilityReason = M2Camera.GetBodyProfileCapability(profile)
    if not capability then return false, capabilityReason end
    local chunks = profileHashChunks(profile.profileHash)
    if not chunks then return false, "PROFILE_HASH_INVALID" end

    local normalized = M2Camera.NormalizeBodyDelta(delta)
    local function request(value)
        return sendCameraRequest(model, value)
    end
    local accepted = request(math.floor(profile.sentinel))
    accepted = accepted and request(REQUEST_BODY_BEGIN + BODY_PROTOCOL_VERSION * 65536)
    for index, chunk in ipairs(chunks) do
        accepted = accepted and request(
            REQUEST_BODY_HASH_CHUNK + (index - 1) * BODY_HASH_CHUNK_FACTOR + chunk
        )
    end
    accepted = accepted and request(REQUEST_BODY_VERTICAL_HORIZONTAL + packPair(
        normalized.verticalOffsetDelta,
        -BODY_OFFSET_DELTA_LIMIT,
        BODY_OFFSET_DELTA_LIMIT,
        normalized.horizontalOffsetDelta,
        -BODY_OFFSET_DELTA_LIMIT,
        BODY_OFFSET_DELTA_LIMIT
    ))
    accepted = accepted and request(REQUEST_BODY_DISTANCE_MINIMUM + packPair(
        normalized.distanceScaleMultiplier,
        BODY_MINIMUM_DISTANCE_SCALE_MULTIPLIER,
        BODY_MAXIMUM_DISTANCE_SCALE_MULTIPLIER,
        normalized.minimumDistanceDelta,
        -BODY_MINIMUM_DISTANCE_DELTA_LIMIT,
        BODY_MINIMUM_DISTANCE_DELTA_LIMIT
    ))
    accepted = accepted and request(REQUEST_BODY_YAW + quantize(normalized.yawOffsetDelta, -PI, PI))
    accepted = accepted and request(REQUEST_BODY_ACTIVATE)
    -- Never leave an unsupported or rejected command selected on the stock
    -- client.  A matching SoloCam v7 hook consumes this after activation.
    request(1)
    return accepted and true or false, accepted and "READY" or "REQUEST_REJECTED"
end

function M2Camera.Reset(model)
    -- Reset only selects the unmodified M2 camera 0. Call this for a record
    -- without m2Camera, or when a pooled PlayerModel stops displaying a card.
    if not model or type(model.SetCamera) ~= "function" then
        return false
    end
    return pcall(function() model:SetCamera(0) end)
end
