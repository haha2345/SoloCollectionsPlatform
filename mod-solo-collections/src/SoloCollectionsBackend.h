#ifndef SOLO_COLLECTIONS_BACKEND_H
#define SOLO_COLLECTIONS_BACKEND_H

#include <cstdint>
#include <string>
#include <string_view>

namespace SoloCollections
{
enum class BackendMode : std::uint8_t
{
    Lua = 1,
    Compare = 2,
    Cpp = 3,
};

void InitializeBackendConfiguration();
[[nodiscard]] BackendMode GetBackendMode() noexcept;
[[nodiscard]] std::string_view BackendModeName(BackendMode mode) noexcept;
[[nodiscard]] bool IsCppBackendOwner() noexcept;
[[nodiscard]] bool IsShadowComparisonEnabled() noexcept;
[[nodiscard]] std::string const& GetShadowReportPath() noexcept;
}

#endif
