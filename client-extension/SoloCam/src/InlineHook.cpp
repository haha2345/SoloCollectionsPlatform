#include "InlineHook.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>

#include <cstring>
#include <limits>

namespace
{
bool WriteRelativeJump(std::uint8_t* source, const void* destination)
{
    const auto sourceAfterJump = reinterpret_cast<std::intptr_t>(source + 5);
    const auto target = reinterpret_cast<std::intptr_t>(destination);
    const auto delta = target - sourceAfterJump;
    if (delta < std::numeric_limits<std::int32_t>::min()
        || delta > std::numeric_limits<std::int32_t>::max())
    {
        return false;
    }

    source[0] = 0xE9;
    const auto relative = static_cast<std::int32_t>(delta);
    std::memcpy(source + 1, &relative, sizeof(relative));
    return true;
}
}

bool ValidateCodeBytes(
    std::uintptr_t address,
    const std::uint8_t* expected,
    std::size_t length
)
{
    return std::memcmp(reinterpret_cast<const void*>(address), expected, length) == 0;
}

bool InstallInlineHook(
    std::uintptr_t address,
    const std::uint8_t* expected,
    std::size_t length,
    void* detour,
    void** trampoline
)
{
    if (!trampoline || length < 5 || !ValidateCodeBytes(address, expected, length))
    {
        return false;
    }

    auto* gateway = static_cast<std::uint8_t*>(VirtualAlloc(
        nullptr,
        length + 5,
        MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE
    ));
    if (!gateway)
    {
        return false;
    }

    auto* target = reinterpret_cast<std::uint8_t*>(address);
    std::memcpy(gateway, target, length);
    if (!WriteRelativeJump(gateway + length, target + length))
    {
        VirtualFree(gateway, 0, MEM_RELEASE);
        return false;
    }

    DWORD previousProtection = 0;
    if (!VirtualProtect(target, length, PAGE_EXECUTE_READWRITE, &previousProtection))
    {
        VirtualFree(gateway, 0, MEM_RELEASE);
        return false;
    }

    std::memset(target, 0x90, length);
    const bool jumpWritten = WriteRelativeJump(target, detour);
    DWORD ignoredProtection = 0;
    VirtualProtect(target, length, previousProtection, &ignoredProtection);
    FlushInstructionCache(GetCurrentProcess(), target, length);

    if (!jumpWritten)
    {
        VirtualFree(gateway, 0, MEM_RELEASE);
        return false;
    }

    *trampoline = gateway;
    return true;
}
