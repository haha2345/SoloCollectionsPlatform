#include "DisplayInfoBridge.hpp"

#include <cstdint>
#include <iostream>

namespace
{
int g_failures = 0;

void Expect(bool condition, const char* message)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << message << '\n';
        ++g_failures;
    }
}
}

int main()
{
    SyntheticCreatureRecord record{};
    record.displayId = 28400;
    Expect(
        reinterpret_cast<const std::uint8_t*>(&record.displayId)
                - reinterpret_cast<const std::uint8_t*>(&record)
            == 0x24,
        "synthetic creature record must expose display ID at offset 0x24"
    );
    Expect(
        record.displayId == 28400,
        "synthetic creature record must retain the requested display ID"
    );

    std::uint32_t displayId = 0;
    Expect(
        TryDecodeDisplayInfoRequest(kDisplayInfoRequestBase + 28400, displayId)
            && displayId == 28400,
        "valid display-info request should return its numeric id"
    );

    displayId = 123;
    Expect(
        !TryDecodeDisplayInfoRequest(28400, displayId),
        "ordinary SetCreature values must not enter the custom display path"
    );
    Expect(
        !TryDecodeDisplayInfoRequest(kDisplayInfoRequestBase, displayId),
        "display id zero must be rejected"
    );
    Expect(
        !TryDecodeDisplayInfoRequest(kDisplayInfoRequestBase + kMaximumDisplayInfoId + 1, displayId),
        "values outside the reserved request range must be rejected"
    );

    if (g_failures != 0)
    {
        return 1;
    }

    std::cout << "DisplayInfoBridgeTests: all checks passed\n";
    return 0;
}
