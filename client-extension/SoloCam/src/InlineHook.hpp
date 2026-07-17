#pragma once

#include <cstddef>
#include <cstdint>

bool ValidateCodeBytes(
    std::uintptr_t address,
    const std::uint8_t* expected,
    std::size_t length
);

bool InstallInlineHook(
    std::uintptr_t address,
    const std::uint8_t* expected,
    std::size_t length,
    void* detour,
    void** trampoline
);
