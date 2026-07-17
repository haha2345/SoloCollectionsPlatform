local SC = SoloCollections

-- Lua-facing controller for the SoloCam v6 item-camera bridge.  The encoded
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
local QUANTIZATION = 4095
local PAIR_FACTOR = 4096
local PI = math.pi
-- 与 DLL 保持一致的输入限制。超出范围不会报错，而是被钳制到边界。
local PITCH_LIMIT = 1.20
local MINIMUM_DISTANCE_SCALE = 0.25
local MAXIMUM_DISTANCE_SCALE = 4.00
local MAXIMUM_TARGET_OFFSET = 4.00

-- Public limits for the in-game tuning panel. Keep these in the same Lua file
-- as the binary transport limits so a slider can never create a pose that the
-- SoloCam v6 decoder would clamp differently.
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

function M2Camera.Reset(model)
    -- Reset only selects the unmodified M2 camera 0. Call this for a record
    -- without m2Camera, or when a pooled PlayerModel stops displaying a card.
    if not model or type(model.SetCamera) ~= "function" then
        return false
    end
    return pcall(function() model:SetCamera(0) end)
end
