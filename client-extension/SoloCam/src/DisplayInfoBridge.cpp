#include "DisplayInfoBridge.hpp"

bool TryDecodeDisplayInfoRequest(std::uint32_t request, std::uint32_t& displayId)
{
    if (request <= kDisplayInfoRequestBase
        || request > kDisplayInfoRequestBase + kMaximumDisplayInfoId)
    {
        return false;
    }

    displayId = request - kDisplayInfoRequestBase;
    return true;
}
