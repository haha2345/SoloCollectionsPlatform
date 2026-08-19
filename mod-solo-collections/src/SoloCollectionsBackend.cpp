#include "SoloCollectionsBackend.h"

#include "Config.h"

#include <algorithm>
#include <cctype>

namespace SoloCollections
{
namespace
{
BackendMode Mode = BackendMode::Cpp;
std::string ShadowReportPath = "logs/solo-collections-shadow.jsonl";
}

std::string_view BackendModeName(BackendMode mode) noexcept
{
    switch (mode)
    {
        case BackendMode::Lua: return "Lua";
        case BackendMode::Compare: return "Compare";
        case BackendMode::Cpp: return "Cpp";
    }
    return "Lua";
}

void InitializeBackendConfiguration()
{
    std::string configured = sConfigMgr->GetOption<std::string>("SoloCollections.Backend", "Cpp");
    std::transform(configured.begin(), configured.end(), configured.begin(), [](unsigned char value)
    {
        return static_cast<char>(std::tolower(value));
    });
    if (configured == "lua")
        Mode = BackendMode::Lua;
    else if (configured == "compare")
        Mode = BackendMode::Compare;
    else if (configured == "cpp")
        Mode = BackendMode::Cpp;
    else
    {
        Mode = BackendMode::Lua;
    }
    ShadowReportPath = sConfigMgr->GetOption<std::string>(
        "SoloCollections.ShadowReportPath", "logs/solo-collections-shadow.jsonl");
}

BackendMode GetBackendMode() noexcept
{
    return Mode;
}

bool IsCppBackendOwner() noexcept
{
    return Mode == BackendMode::Cpp;
}

bool IsShadowComparisonEnabled() noexcept
{
    return Mode == BackendMode::Compare;
}

std::string const& GetShadowReportPath() noexcept
{
    return ShadowReportPath;
}
}
