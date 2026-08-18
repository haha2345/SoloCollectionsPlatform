#include "CameraProfile.hpp"
#include "BodyCameraBridge.hpp"
#include "ClientAddresses.hpp"
#include "DisplayInfoBridge.hpp"
#include "ItemCameraBridge.hpp"
#include "InlineHook.hpp"
#include "PreviewItemBridge.hpp"

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#include <cstddef>
#include <cstdint>

namespace
{
using SetCameraByIndexFn = void(__thiscall*)(void* simpleModel, std::uint32_t index);
using RenderSimpleModelFn = void(__cdecl*)(void* simpleModel);
using PlayerModelSetCreatureLuaFn = int(__cdecl*)(void* luaState);
using LuaIsNumberFn = int(__cdecl*)(void* luaState, int index);
using LuaToIntegerFn = std::uint32_t(__cdecl*)(void* luaState, int index);
using LuaRawGetIFn = void(__cdecl*)(void* luaState, int index, int key);
using LuaToUserDataFn = void*(__cdecl*)(void* luaState, int index);
using LuaSetTopFn = void(__cdecl*)(void* luaState, int index);
using PlayerModelSetCreatureRecordFn =
    void(__thiscall*)(void* playerModel, SyntheticCreatureRecord* creatureRecord);
using PlayerModelTryOnFn =
    void(__thiscall*)(void* playerModel, int itemId, int unknown, int slotId);
using PlayerModelUndressFn = void(__thiscall*)(void* playerModel);
using FrameScriptExecuteFn = int(__cdecl*)(const char* script, const char* source, int unknown);
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
HWND g_wowWindow = nullptr;
UINT_PTR g_capabilityTimer = 0;

constexpr UINT_PTR kCapabilityTimerId = 0x53434E50;
constexpr UINT kCapabilityTimerIntervalMs = 1000;
constexpr std::uint32_t kSoloCamVersion = 11;

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

void* ResolveLuaWidgetObject(void* luaState, int index)
{
    if (!luaState)
    {
        return nullptr;
    }

    const auto rawGetI = reinterpret_cast<LuaRawGetIFn>(Client12340::LuaRawGetI);
    const auto toUserData = reinterpret_cast<LuaToUserDataFn>(Client12340::LuaToUserData);
    const auto setTop = reinterpret_cast<LuaSetTopFn>(Client12340::LuaSetTop);
    void* object = nullptr;
    __try
    {
        rawGetI(luaState, index, 0);
        object = toUserData(luaState, -1);
        setTop(luaState, -2);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return nullptr;
    }
    return reinterpret_cast<std::uintptr_t>(object) >= 0x10000 ? object : nullptr;
}

int __cdecl HookPlayerModelSetCreature(void* luaState)
{
    const auto luaIsNumber = reinterpret_cast<LuaIsNumberFn>(Client12340::LuaIsNumber);
    const auto luaToInteger = reinterpret_cast<LuaToIntegerFn>(Client12340::LuaToInteger);

    if (luaIsNumber(luaState, 2))
    {
        const std::uint32_t request = luaToInteger(luaState, 2);
        const PreviewItemRequest preview = DecodePreviewItemRequest(request);
        if (preview.command != PreviewItemCommand::None)
        {
            void* playerModel = ResolveLuaWidgetObject(luaState, 1);
            if (playerModel)
            {
                // A card may have been an armour model on its previous page.
                // Drop SoloCam's old M2-camera state before following the
                // Transmorpher DressUpModel path on this same widget.
                DeactivateCustomCamera(playerModel);
                __try
                {
                    if (preview.command == PreviewItemCommand::Undress)
                    {
                        reinterpret_cast<PlayerModelUndressFn>(
                            Client12340::PlayerModelUndress
                        )(playerModel);
                    }
                    else if (preview.command == PreviewItemCommand::TryOnAuto)
                    {
                        reinterpret_cast<PlayerModelTryOnFn>(Client12340::PlayerModelTryOn)(
                            playerModel,
                            static_cast<int>(preview.itemId),
                            0,
                            -1
                        );
                    }
                    else if (preview.command == PreviewItemCommand::TryOnSlot)
                    {
                        reinterpret_cast<PlayerModelTryOnFn>(Client12340::PlayerModelTryOn)(
                            playerModel,
                            static_cast<int>(preview.itemId),
                            0,
                            ResolvePreviewModelSlotId(preview.equipmentSlotId)
                        );
                    }
                }
                __except (EXCEPTION_EXECUTE_HANDLER)
                {
                    OutputDebugStringA("SoloCam: preview item request failed closed.\n");
                }
            }
            // Invalid values inside the reserved preview family are consumed
            // and never forwarded to the stock creature-cache lookup.
            return 0;
        }

        std::uint32_t displayId = 0;
        if (TryDecodeDisplayInfoRequest(request, displayId))
        {
            void* playerModel = ResolveLuaWidgetObject(luaState, 1);
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

bool IsWindowOwnedByCurrentProcess(HWND window)
{
    DWORD processId = 0;
    GetWindowThreadProcessId(window, &processId);
    return processId == GetCurrentProcessId();
}

HWND FindOwnedWowWindow()
{
    constexpr const char* classes[] = {"GxWindowClass", "GxWindowClassD3d"};
    for (const char* className : classes)
    {
        HWND candidate = nullptr;
        while ((candidate = FindWindowExA(nullptr, candidate, className, nullptr)) != nullptr)
        {
            if (IsWindowOwnedByCurrentProcess(candidate))
            {
                return candidate;
            }
        }
    }
    return nullptr;
}

void CALLBACK CapabilityTimerProc(HWND, UINT, UINT_PTR, DWORD)
{
    constexpr const char* script =
        "if SoloCollections and SoloCollections.NativePreview then "
        "SoloCollections.NativePreview:SetRuntimeCapability({"
        "soloCamVersion=11,previewProtocolVersion=1,features={"
        "directDisplayV1=true,previewTryOnV1=true}}) end";
    __try
    {
        reinterpret_cast<FrameScriptExecuteFn>(Client12340::FrameScriptExecute)(
            script,
            "SoloCam",
            0
        );
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        OutputDebugStringA("SoloCam: capability announcement failed closed.\n");
    }
}

bool InstallCapabilityTimer()
{
    constexpr DWORD maximumWaitMs = 60000;
    constexpr DWORD pollMs = 250;
    DWORD waited = 0;
    while (waited < maximumWaitMs)
    {
        g_wowWindow = FindOwnedWowWindow();
        if (g_wowWindow)
        {
            g_capabilityTimer = SetTimer(
                g_wowWindow,
                kCapabilityTimerId,
                kCapabilityTimerIntervalMs,
                &CapabilityTimerProc
            );
            return g_capabilityTimer != 0;
        }
        Sleep(pollMs);
        waited += pollMs;
    }
    return false;
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
               Client12340::PlayerModelSetCreatureRecordLength)
        && ValidateCodeBytes(
               Client12340::PlayerModelTryOn,
               Client12340::PlayerModelTryOnBytes,
               Client12340::PlayerModelTryOnLength)
        && ValidateCodeBytes(
               Client12340::PlayerModelUndress,
               Client12340::PlayerModelUndressBytes,
               Client12340::PlayerModelUndressLength)
        && ValidateCodeBytes(
               Client12340::LuaRawGetI,
               Client12340::LuaRawGetIBytes,
               Client12340::LuaRawGetILength)
        && ValidateCodeBytes(
               Client12340::LuaToUserData,
               Client12340::LuaToUserDataBytes,
               Client12340::LuaToUserDataLength)
        && ValidateCodeBytes(
               Client12340::LuaSetTop,
               Client12340::LuaSetTopBytes,
               Client12340::LuaSetTopLength)
        && ValidateCodeBytes(
               Client12340::FrameScriptExecute,
               Client12340::FrameScriptExecuteBytes,
               Client12340::FrameScriptExecuteLength);
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

    if (!InstallCapabilityTimer())
    {
        OutputDebugStringA("SoloCam: preview hook enabled, capability timer unavailable.\n");
        return 5;
    }

    OutputDebugStringA(
        "SoloCam: v11 corrected Transmorpher slot mapping, camera and direct display bridges enabled.\n"
    );
    return 0;
}
}

extern "C" __declspec(dllexport) std::uint32_t SoloCamPocVersion()
{
    return kSoloCamVersion;
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
    else if (reason == DLL_PROCESS_DETACH && g_capabilityTimer && g_wowWindow)
    {
        KillTimer(g_wowWindow, g_capabilityTimer);
        g_capabilityTimer = 0;
        g_wowWindow = nullptr;
    }
    return TRUE;
}
