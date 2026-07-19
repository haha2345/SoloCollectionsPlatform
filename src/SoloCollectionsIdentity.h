#ifndef SOLO_COLLECTIONS_IDENTITY_H
#define SOLO_COLLECTIONS_IDENTITY_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace SoloCollections
{
enum class IdentityResolutionCode : std::uint8_t
{
    Ok = 0,
    UnknownIdentity = 1,
};

template <typename Definition>
struct IdentityResolution
{
    IdentityResolutionCode Code = IdentityResolutionCode::UnknownIdentity;
    Definition const* Identity = nullptr;

    [[nodiscard]] bool IsKnown() const noexcept
    {
        return Code == IdentityResolutionCode::Ok && Identity != nullptr;
    }
};

struct ClassIdentityDefinition
{
    LogicalClassId LogicalId;
    std::string ClassKey;
    std::uint32_t RuntimeClassId = 0;
    std::vector<std::string> Aliases;
    std::vector<std::string> Capabilities;
    std::string CompatibilityProfile;
    std::string ClientAssetProfile;
    std::uint32_t LegacyMaskBit = 0;
    std::string ArmorType;
    std::vector<std::string> MainhandWeaponTypes;
    std::vector<std::string> OffhandWeaponTypes;
};

struct RaceIdentityDefinition
{
    LogicalRaceId LogicalId;
    std::string RaceKey;
    std::uint32_t RuntimeRaceId = 0;
    std::vector<std::string> Aliases;
    std::vector<std::string> Capabilities;
    std::string FactionKey;
    std::string CompatibilityProfile;
    std::string ClientAssetProfile;
    std::string CameraProfile;
};

class IdentityRegistry final
{
public:
    IdentityRegistry(
        std::vector<ClassIdentityDefinition> classes,
        std::vector<RaceIdentityDefinition> races);

    [[nodiscard]] bool IsValid() const noexcept { return _valid; }
    [[nodiscard]] std::string const& ValidationError() const noexcept { return _validationError; }

    [[nodiscard]] IdentityResolution<ClassIdentityDefinition> ResolveClass(std::uint32_t runtimeClassId) const;
    [[nodiscard]] IdentityResolution<ClassIdentityDefinition> ResolveClass(std::string_view keyOrAlias) const;
    [[nodiscard]] IdentityResolution<ClassIdentityDefinition> ResolveLogicalClass(LogicalClassId logicalId) const;
    [[nodiscard]] IdentityResolution<RaceIdentityDefinition> ResolveRace(std::uint32_t runtimeRaceId) const;
    [[nodiscard]] IdentityResolution<RaceIdentityDefinition> ResolveRace(std::string_view keyOrAlias) const;
    [[nodiscard]] IdentityResolution<RaceIdentityDefinition> ResolveLogicalRace(LogicalRaceId logicalId) const;
    [[nodiscard]] std::string_view ResolveCameraProfile(IdentityResolution<RaceIdentityDefinition> const& race) const noexcept;

    [[nodiscard]] std::vector<ClassIdentityDefinition> const& Classes() const noexcept { return _classes; }
    [[nodiscard]] std::vector<RaceIdentityDefinition> const& Races() const noexcept { return _races; }

private:
    void Invalidate(std::string message);

    std::vector<ClassIdentityDefinition> _classes;
    std::vector<RaceIdentityDefinition> _races;
    std::unordered_map<std::uint32_t, std::size_t> _classesByRuntimeId;
    std::unordered_map<std::uint16_t, std::size_t> _classesByLogicalId;
    std::unordered_map<std::string, std::size_t> _classesByKey;
    std::unordered_map<std::uint32_t, std::size_t> _racesByRuntimeId;
    std::unordered_map<std::uint16_t, std::size_t> _racesByLogicalId;
    std::unordered_map<std::string, std::size_t> _racesByKey;
    bool _valid = true;
    std::string _validationError;
};

[[nodiscard]] IdentityRegistry const& GetIdentityRegistry();
}

#endif
