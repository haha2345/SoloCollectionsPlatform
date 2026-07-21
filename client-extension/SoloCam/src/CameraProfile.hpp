#pragma once

#include <cstddef>
#include <cstdint>

struct CameraVector
{
    float x;
    float y;
    float z;
};

struct CharacterCameraProfile
{
    std::uint32_t sentinel;
    float verticalOffset;
    float distanceScale;
    float minimumDistance;
    float horizontalOffset;
    float yawOffset;
};

// A per-model pose applied relative to the active M2 camera.  The Lua API
// supplies these values through SoloCam's private SetCamera request protocol;
// they never use UI-frame or screen coordinates.
struct ItemCameraPose
{
    // Horizontal orbit around M2-local Z, in radians. Lua range: [-pi, pi].
    float yawOffset = 0.0f;

    // Elevation relative to the authored M2 camera, in radians. Lua range:
    // [-1.20, 1.20]; positive values raise the camera.
    float pitchOffset = 0.0f;

    // Rotation around the active camera view axis, in radians. Lua range:
    // [-pi, pi]; this maps to the native M2 camera roll scalar.
    float rollOffset = 0.0f;

    // Multiplier for authored camera-to-target distance. Lua range:
    // [0.25, 4.00]; values above one zoom out.
    float distanceScale = 1.0f;

    // M2-local world-unit translation of the camera rig and target together.
    // Lua range: [-4.00, 4.00] per component; this is not screen-space XYZ.
    CameraVector targetOffset{};
};

const CharacterCameraProfile* FindCharacterCameraProfile(std::uint32_t sentinel);
std::size_t GetCharacterCameraProfileCount();
std::uint32_t GetCharacterCameraProfileVersion();
const char* GetCharacterCameraProfileHash();

// The native dressing-room camera supplies orientation. A slot profile moves
// the target vertically/horizontally, changes the distance and can orbit the
// view around the model, while remaining independent of UI frame position.
bool BuildCharacterCamera(
    const CharacterCameraProfile& profile,
    const CameraVector& nativePosition,
    const CameraVector& nativeTarget,
    CameraVector& position,
    CameraVector& target
);

// Apply an item-camera pose relative to M2 camera 0.  The native M2 camera
// remains the per-model baseline, which preserves each weapon's bounds and
// original framing while allowing Lua to orbit, zoom, and retarget it.
bool BuildItemM2Camera(
    const ItemCameraPose& pose,
    const CameraVector& nativePosition,
    const CameraVector& nativeTarget,
    CameraVector& position,
    CameraVector& target
);

// Apply the pose's screen-plane roll to the authored M2 camera roll scalar.
// The scalar is independent from position/target and is applied only during
// the corresponding PlayerModel render call.
bool BuildItemM2CameraRoll(
    const ItemCameraPose& pose,
    float nativeRoll,
    float& roll
);
