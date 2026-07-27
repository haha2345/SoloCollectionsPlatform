#include "CameraProfile.hpp"
#include "BodyCameraBridge.hpp"
#include "ClientAddresses.hpp"
#include "DisplayInfoBridge.hpp"
#include "ItemCameraBridge.hpp"
#include "InlineHook.hpp"

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#include <cstddef>
#include <cstdint>

namespace
{
using SetCameraByIndexFn = void(__thiscall*)(void* simpleModel, std::uint32_t index);
using RenderSimpleModelFn = void(__cdecl*)(void* simpleModel);
using PlayerModelSetCreatureLuaFn = int(__cdecl*)(void* luaState);
using ResolveScriptObjectFn = void*(__cdecl*)(std::uint32_t typeToken);
using LuaIsNumberFn = int(__cdecl*)(void* luaState, int index);
using LuaToIntegerFn = std::uint32_t(__cdecl*)(void* luaState, int index);
using PlayerModelSetCreatureRecordFn =
    void(__thiscall*)(void* playerModel, SyntheticCreatureRecord* creatureRecord);
using DataMgrGetCoordFn = void(__cdecl*)(void* camera, std::uint32_t slot, CameraVector* value);
using DataMgrSetCoordFn = void(__cdecl*)(
    void* camera,
    std::uint32_t slot,
    const CameraVector* value,
    std::uint32_t componentMask
);
using DataMgrGetScalarFn = float(__cdecl*)(void* camera, std::uint32_t slot);
using DataMgrSetScalarFn = void(__cdecl*)(
    void* camera,
    std::uint32_t slot,
    float value
);

SetCameraByIndexFn g_originalSetCameraByIndex = nullptr;
RenderSimpleModelFn g_originalRenderSimpleModel = nullptr;
PlayerModelSetCreatureLuaFn g_originalPlayerModelSetCreature = nullptr;

constexpr std::size_t kMaximumTrackedModels = 64;

struct TrackedModel
{
    void* model = nullptr;
    const CharacterCameraProfile* profile = nullptr;
    bool waitingForFallback = false;
    ItemCameraPose pendingItemPose{};
    ItemCameraPose activeItemPose{};
    bool itemCameraActive = false;
    PendingBodyCamera pendingBodyCamera{};
    BodyCameraDelta activeBodyDelta{};
    bool bodyCameraActive = false;
};

TrackedModel g_trackedModels[kMaximumTrackedModels]{};

struct DirectDisplayModel
{
    void* model = nullptr;
    SyntheticCreatureRecord record{};
};

// PlayerModel stores this pointer at +0x378, so the backing record must outlive
// the Lua call. Keep one stable record per model instead of using stack memory.
DirectDisplayModel g_directDisplayModels[kMaximumTrackedModels]{};
CRITICAL_SECTION g_trackingLock{};

TrackedModel* FindTrackedModel(void* model, bool create)
{
    TrackedModel* empty = nullptr;
    for (auto& tracked : g_trackedModels)
    {
        if (tracked.model == model)
        {
            return &tracked;
        }
        if (!tracked.model && !empty)
        {
            empty = &tracked;
        }
    }

    if (create && empty)
    {
        empty->model = model;
        return empty;
    }
    return nullptr;
}

SyntheticCreatureRecord* AcquireDirectDisplayRecord(
    void* model,
    std::uint32_t displayId
)
{
    SyntheticCreatureRecord* result = nullptr;
    EnterCriticalSection(&g_trackingLock);

    DirectDisplayModel* empty = nullptr;
    for (auto& direct : g_directDisplayModels)
    {
        if (direct.model == model)
        {
            direct.record.displayId = displayId;
            result = &direct.record;
            break;
        }
        if (!direct.model && !empty)
        {
            empty = &direct;
        }
    }

    if (!result && empty)
    {
        empty->model = model;
        empty->record = SyntheticCreatureRecord{};
        empty->record.displayId = displayId;
        result = &empty->record;
    }

    LeaveCriticalSection(&g_trackingLock);
    return result;
}

void ActivateCharacterProfile(void* model, const CharacterCameraProfile* profile)
{
    EnterCriticalSection(&g_trackingLock);
    if (auto* tracked = FindTrackedModel(model, true))
    {
        tracked->profile = profile;
        tracked->waitingForFallback = true;
        tracked->itemCameraActive = false;
        tracked->bodyCameraActive = false;
        ResetBodyCameraPending(tracked->pendingBodyCamera);
    }
    LeaveCriticalSection(&g_trackingLock);
}

bool ApplyItemCameraRequest(
    void* model,
    ItemCameraCommand command,
    std::uint32_t payload
)
{
    bool accepted = false;
    EnterCriticalSection(&g_trackingLock);
    if (auto* tracked = FindTrackedModel(model, true))
    {
        tracked->profile = nullptr;
        tracked->waitingForFallback = false;
        tracked->bodyCameraActive = false;
        ResetBodyCameraPending(tracked->pendingBodyCamera);
        accepted = ApplyItemCameraCommand(tracked->pendingItemPose, command, payload);
        if (accepted && command == ItemCameraCommand::Activate)
        {
            tracked->activeItemPose = tracked->pendingItemPose;
            tracked->itemCameraActive = true;
        }
    }
    LeaveCriticalSection(&g_trackingLock);
    return accepted;
}

bool ApplyBodyCameraRequest(
    void* model,
    BodyCameraCommand command,
    std::uint32_t payload
)
{
    bool accepted = false;
    EnterCriticalSection(&g_trackingLock);
    if (auto* tracked = FindTrackedModel(model, true))
    {
        // A body request can only follow a generated profile sentinel.  This
        // makes a synthetic item request or an unknown stock camera index
        // unable to opt into profile-level rendering accidentally.
        if (tracked->profile
            && ApplyBodyCameraCommand(tracked->pendingBodyCamera, command, payload))
        {
            if (command == BodyCameraCommand::Begin)
            {
                tracked->bodyCameraActive = false;
                accepted = true;
            }
            else if (command == BodyCameraCommand::Activate)
            {
                if (IsBodyCameraPendingComplete(
                        tracked->pendingBodyCamera,
                        GetCharacterCameraProfileHash()))
                {
                    tracked->activeBodyDelta = tracked->pendingBodyCamera.delta;
                    tracked->bodyCameraActive = true;
                    // Lua sends a same-tick camera 1 fallback after activate.
                    // Preserve the already validated body delta while consuming
                    // that fallback so stock clients remain safe and no model
                    // leaks its pose into a later pooled render.
                    tracked->waitingForFallback = true;
                    accepted = true;
                }
            }
            else
            {
                accepted = true;
            }
        }
    }
    LeaveCriticalSection(&g_trackingLock);
    return accepted;
}

bool ConsumeFallback(void* model, std::uint32_t index)
{
    bool consumed = false;
    EnterCriticalSection(&g_trackingLock);
    if (auto* tracked = FindTrackedModel(model, false))
    {
        if (tracked->profile
            && tracked->waitingForFallback
            && index == Client12340::NativeDressingRoomCamera)
        {
            tracked->waitingForFallback = false;
            consumed = true;
        }
    }
    LeaveCriticalSection(&g_trackingLock);
    return consumed;
}

void DeactivateCustomCamera(void* model)
{
    EnterCriticalSection(&g_trackingLock);
    if (auto* tracked = FindTrackedModel(model, false))
    {
        *tracked = TrackedModel{};
    }
    LeaveCriticalSection(&g_trackingLock);
}

struct CameraOverride
{
    const CharacterCameraProfile* characterProfile = nullptr;
    BodyCameraDelta bodyDelta{};
    bool bodyCameraActive = false;
    ItemCameraPose itemPose{};
    bool itemCameraActive = false;
};

bool GetCameraOverride(void* model, CameraOverride& override)
{
    bool hasOverride = false;
    EnterCriticalSection(&g_trackingLock);
    if (auto* tracked = FindTrackedModel(model, false))
    {
        if (tracked->profile && tracked->bodyCameraActive)
        {
            override.characterProfile = tracked->profile;
            override.bodyDelta = tracked->activeBodyDelta;
            override.bodyCameraActive = true;
            hasOverride = true;
        }
        else if (tracked->profile && !tracked->waitingForFallback)
        {
            override.characterProfile = tracked->profile;
            hasOverride = true;
        }
        else if (tracked->itemCameraActive)
        {
            override.itemPose = tracked->activeItemPose;
            override.itemCameraActive = true;
            hasOverride = true;
        }
    }
    LeaveCriticalSection(&g_trackingLock);
    return hasOverride;
}

void __fastcall HookSetCameraByIndex(void* simpleModel, void*, std::uint32_t index)
{
    if (IsBodyCameraRequest(index))
    {
        BodyCameraCommand command{};
        std::uint32_t payload = 0;
        if (!TryDecodeBodyCameraRequest(index, command, payload)
            || !ApplyBodyCameraRequest(simpleModel, command, payload))
        {
            // Body deltas are all-or-nothing.  A missing chunk, unknown
            // version, mismatched full profile hash, or stale model state must
            // return to the native dressing-room camera rather than applying
            // a partial profile correction.
            DeactivateCustomCamera(simpleModel);
            g_originalSetCameraByIndex(
                simpleModel,
                Client12340::NativeDressingRoomCamera
            );
            return;
        }

        if (command == BodyCameraCommand::Activate)
        {
            g_originalSetCameraByIndex(
                simpleModel,
                Client12340::NativeDressingRoomCamera
            );
        }
        return;
    }

    if (IsItemCameraRequest(index))
    {
        ItemCameraCommand command{};
        std::uint32_t payload = 0;
        if (!TryDecodeItemCameraRequest(index, command, payload)
            || !ApplyItemCameraRequest(simpleModel, command, payload))
        {
            // Never pass a malformed reserved request to the stock camera
            // index path; reset to camera 0 instead of risking an invalid M2
            // camera lookup.
            DeactivateCustomCamera(simpleModel);
            g_originalSetCameraByIndex(simpleModel, 0);
            return;
        }

        if (command == ItemCameraCommand::Activate)
        {
            // M2 camera 0 remains the model-specific baseline. The render
            // hook below applies the Lua pose relative to its coordinates.
            g_originalSetCameraByIndex(simpleModel, 0);
        }
        return;
    }

    if (const auto* profile = FindCharacterCameraProfile(index))
    {
        ActivateCharacterProfile(simpleModel, profile);
        g_originalSetCameraByIndex(simpleModel, Client12340::NativeDressingRoomCamera);
        return;
    }

    if (ConsumeFallback(simpleModel, index))
    {
        g_originalSetCameraByIndex(simpleModel, Client12340::NativeDressingRoomCamera);
        return;
    }

    DeactivateCustomCamera(simpleModel);
    g_originalSetCameraByIndex(simpleModel, index);
}

void __cdecl HookRenderSimpleModel(void* simpleModel)
{
    CameraOverride override{};
    if (!GetCameraOverride(simpleModel, override))
    {
        g_originalRenderSimpleModel(simpleModel);
        return;
    }

    auto* cameraSlot = reinterpret_cast<void**>(
        static_cast<std::uint8_t*>(simpleModel) + Client12340::SimpleModelCameraOffset
    );
    void* camera = *cameraSlot;
    if (!camera)
    {
        g_originalRenderSimpleModel(simpleModel);
        return;
    }

    const auto dataMgrGetCoord = reinterpret_cast<DataMgrGetCoordFn>(Client12340::DataMgrGetCoord);
    const auto dataMgrSetCoord = reinterpret_cast<DataMgrSetCoordFn>(Client12340::DataMgrSetCoord);
    const auto dataMgrGetScalar = reinterpret_cast<DataMgrGetScalarFn>(
        Client12340::DataMgrGetScalar
    );
    const auto dataMgrSetScalar = reinterpret_cast<DataMgrSetScalarFn>(
        Client12340::DataMgrSetScalar
    );

    CameraVector nativePosition{};
    CameraVector nativeTarget{};
    dataMgrGetCoord(camera, Client12340::CameraPositionSlot, &nativePosition);
    dataMgrGetCoord(camera, Client12340::CameraTargetSlot, &nativeTarget);

    CameraVector position{};
    CameraVector target{};
    const bool cameraBuilt = override.characterProfile
        ? (override.bodyCameraActive
            ? BuildBodyCharacterCamera(
                *override.characterProfile,
                override.bodyDelta,
                nativePosition,
                nativeTarget,
                position,
                target)
            : BuildCharacterCamera(
                *override.characterProfile,
                nativePosition,
                nativeTarget,
                position,
                target))
        : BuildItemM2Camera(
            override.itemPose,
            nativePosition,
            nativeTarget,
            position,
            target);
    float nativeRoll = 0.0f;
    float roll = 0.0f;
    bool rollBuilt = true;
    if (override.itemCameraActive)
    {
        nativeRoll = dataMgrGetScalar(camera, Client12340::CameraRollSlot);
        rollBuilt = BuildItemM2CameraRoll(override.itemPose, nativeRoll, roll);
    }
    if (!cameraBuilt || !rollBuilt)
    {
        g_originalRenderSimpleModel(simpleModel);
        return;
    }

    dataMgrSetCoord(camera, Client12340::CameraPositionSlot, &position, 0);
    dataMgrSetCoord(camera, Client12340::CameraTargetSlot, &target, 0);
    if (override.itemCameraActive)
    {
        // Scalar property 5 is the native M2 roll. It must be set before the
        // stock renderer consumes camera data, then restored for other models.
        dataMgrSetScalar(camera, Client12340::CameraRollSlot, roll);
    }
    g_originalRenderSimpleModel(simpleModel);
    if (override.itemCameraActive)
    {
        dataMgrSetScalar(camera, Client12340::CameraRollSlot, nativeRoll);
    }
    dataMgrSetCoord(camera, Client12340::CameraPositionSlot, &nativePosition, 0);
    dataMgrSetCoord(camera, Client12340::CameraTargetSlot, &nativeTarget, 0);
}

std::uint32_t EnsurePlayerModelTypeToken()
{
    auto* token = reinterpret_cast<std::uint32_t*>(Client12340::PlayerModelTypeToken);
    if (*token == 0)
    {
        auto* nextToken = reinterpret_cast<std::uint32_t*>(
            Client12340::NextScriptObjectTypeToken
        );
        ++(*nextToken);
        *token = *nextToken;
    }
    return *token;
}

int __cdecl HookPlayerModelSetCreature(void* luaState)
{
    const auto luaIsNumber = reinterpret_cast<LuaIsNumberFn>(Client12340::LuaIsNumber);
    const auto luaToInteger = reinterpret_cast<LuaToIntegerFn>(Client12340::LuaToInteger);

    if (luaIsNumber(luaState, 2))
    {
        const std::uint32_t request = luaToInteger(luaState, 2);
        std::uint32_t displayId = 0;
        if (TryDecodeDisplayInfoRequest(request, displayId))
        {
            const auto resolveScriptObject = reinterpret_cast<ResolveScriptObjectFn>(
                Client12340::ResolveScriptObject
            );
            void* playerModel = resolveScriptObject(EnsurePlayerModelTypeToken());
            if (playerModel)
            {
                // A PlayerModel frame is reused for many cards. Do not let a
                // previous item's pose affect the next direct display while
                // its M2 camera is still loading.
                DeactivateCustomCamera(playerModel);
                SyntheticCreatureRecord* record =
                    AcquireDirectDisplayRecord(playerModel, displayId);
                if (record)
                {
                    const auto setCreatureRecord =
                        reinterpret_cast<PlayerModelSetCreatureRecordFn>(
                            Client12340::PlayerModelSetCreatureRecord
                        );
                    setCreatureRecord(playerModel, record);
                }
            }
            return 0;
        }
    }

    return g_originalPlayerModelSetCreature(luaState);
}

bool ValidateSupportedClient()
{
    return ValidateCodeBytes(
               Client12340::SetCameraByIndex,
               Client12340::SetCameraByIndexBytes,
               Client12340::SetCameraByIndexLength)
        && ValidateCodeBytes(
               Client12340::RenderSimpleModel,
               Client12340::RenderSimpleModelBytes,
               Client12340::RenderSimpleModelLength)
        && ValidateCodeBytes(
               Client12340::DataMgrGetScalar,
               Client12340::DataMgrGetScalarBytes,
               Client12340::DataMgrGetScalarLength)
        && ValidateCodeBytes(
               Client12340::DataMgrSetScalar,
               Client12340::DataMgrSetScalarBytes,
               Client12340::DataMgrSetScalarLength)
        && ValidateCodeBytes(
               Client12340::PlayerModelSetCreature,
               Client12340::PlayerModelSetCreatureBytes,
               Client12340::PlayerModelSetCreatureLength)
        && ValidateCodeBytes(
               Client12340::PlayerModelSetCreatureRecord,
               Client12340::PlayerModelSetCreatureRecordBytes,
               Client12340::PlayerModelSetCreatureRecordLength);
}

DWORD WINAPI InstallHooks(void*)
{
    if (!ValidateSupportedClient())
    {
        OutputDebugStringA("SoloCam: unsupported client bytes; hooks were not installed.\n");
        return 1;
    }

    InitializeCriticalSection(&g_trackingLock);

    void* setCameraGateway = nullptr;
    if (!InstallInlineHook(
            Client12340::SetCameraByIndex,
            Client12340::SetCameraByIndexBytes,
            Client12340::SetCameraByIndexLength,
            reinterpret_cast<void*>(&HookSetCameraByIndex),
            &setCameraGateway))
    {
        OutputDebugStringA("SoloCam: SetCamera hook installation failed.\n");
        return 2;
    }
    g_originalSetCameraByIndex = reinterpret_cast<SetCameraByIndexFn>(setCameraGateway);

    void* renderGateway = nullptr;
    if (!InstallInlineHook(
            Client12340::RenderSimpleModel,
            Client12340::RenderSimpleModelBytes,
            Client12340::RenderSimpleModelLength,
            reinterpret_cast<void*>(&HookRenderSimpleModel),
            &renderGateway))
    {
        OutputDebugStringA("SoloCam: render hook installation failed.\n");
        return 3;
    }

    g_originalRenderSimpleModel = reinterpret_cast<RenderSimpleModelFn>(renderGateway);

    void* setCreatureGateway = nullptr;
    if (!InstallInlineHook(
            Client12340::PlayerModelSetCreature,
            Client12340::PlayerModelSetCreatureBytes,
            Client12340::PlayerModelSetCreatureLength,
            reinterpret_cast<void*>(&HookPlayerModelSetCreature),
            &setCreatureGateway))
    {
        OutputDebugStringA("SoloCam: PlayerModel SetCreature hook installation failed.\n");
        return 4;
    }
    g_originalPlayerModelSetCreature = reinterpret_cast<PlayerModelSetCreatureLuaFn>(
        setCreatureGateway
    );

    OutputDebugStringA(
        "SoloCam: body-profile, multi-axis M2 camera and direct display-info bridge enabled.\n"
    );
    return 0;
}
}

extern "C" __declspec(dllexport) std::uint32_t SoloCamPocVersion()
{
    return 7;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(module);
        const HANDLE thread = CreateThread(nullptr, 0, &InstallHooks, nullptr, 0, nullptr);
        if (thread)
        {
            CloseHandle(thread);
        }
    }
    return TRUE;
}
