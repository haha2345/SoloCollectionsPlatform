#include "SoloCollectionsIdentity.h"

#include <algorithm>
#include <cctype>
#include <utility>

namespace SoloCollections
{
namespace
{
std::string NormalizeIdentityKey(std::string_view value)
{
    std::string normalized;
    normalized.reserve(value.size());
    for (unsigned char character : value)
    {
        if (character == '-' || character == ' ')
            normalized.push_back('_');
        else if (std::isalnum(character) || character == '_')
            normalized.push_back(static_cast<char>(std::tolower(character)));
    }
    return normalized;
}

template <typename Definition>
IdentityResolution<Definition> Found(Definition const& definition)
{
    return { IdentityResolutionCode::Ok, &definition };
}

#include "generated/SoloCollectionsIdentityData.inc"
}

IdentityRegistry::IdentityRegistry(
    std::vector<ClassIdentityDefinition> classes,
    std::vector<RaceIdentityDefinition> races)
    : _classes(std::move(classes)), _races(std::move(races))
{
    for (std::size_t index = 0; index < _classes.size(); ++index)
    {
        ClassIdentityDefinition const& definition = _classes[index];
        if (!definition.LogicalId.IsValid() || definition.RuntimeClassId == 0 || definition.ClassKey.empty())
        {
            Invalidate("class identity contains an empty stable field");
            continue;
        }
        if (!_classesByRuntimeId.emplace(definition.RuntimeClassId, index).second ||
            !_classesByLogicalId.emplace(definition.LogicalId.Value(), index).second)
            Invalidate("duplicate class runtime or logical ID");
        auto bindKey = [&](std::string_view key)
        {
            std::string normalized = NormalizeIdentityKey(key);
            if (normalized.empty())
            {
                Invalidate("duplicate or empty class key/alias");
                return;
            }
            auto const [iterator, inserted] = _classesByKey.emplace(std::move(normalized), index);
            if (!inserted && iterator->second != index)
                Invalidate("duplicate or empty class key/alias");
        };
        bindKey(definition.ClassKey);
        for (std::string const& alias : definition.Aliases)
            bindKey(alias);
    }

    for (std::size_t index = 0; index < _races.size(); ++index)
    {
        RaceIdentityDefinition const& definition = _races[index];
        if (!definition.LogicalId.IsValid() || definition.RuntimeRaceId == 0 || definition.RaceKey.empty())
        {
            Invalidate("race identity contains an empty stable field");
            continue;
        }
        if (!_racesByRuntimeId.emplace(definition.RuntimeRaceId, index).second ||
            !_racesByLogicalId.emplace(definition.LogicalId.Value(), index).second)
            Invalidate("duplicate race runtime or logical ID");
        auto bindKey = [&](std::string_view key)
        {
            std::string normalized = NormalizeIdentityKey(key);
            if (normalized.empty())
            {
                Invalidate("duplicate or empty race key/alias");
                return;
            }
            auto const [iterator, inserted] = _racesByKey.emplace(std::move(normalized), index);
            if (!inserted && iterator->second != index)
                Invalidate("duplicate or empty race key/alias");
        };
        bindKey(definition.RaceKey);
        for (std::string const& alias : definition.Aliases)
            bindKey(alias);
    }
}

void IdentityRegistry::Invalidate(std::string message)
{
    _valid = false;
    if (_validationError.empty())
        _validationError = std::move(message);
}

IdentityResolution<ClassIdentityDefinition> IdentityRegistry::ResolveClass(std::uint32_t runtimeClassId) const
{
    auto const iterator = _classesByRuntimeId.find(runtimeClassId);
    return iterator == _classesByRuntimeId.end() ? IdentityResolution<ClassIdentityDefinition>{} : Found(_classes[iterator->second]);
}

IdentityResolution<ClassIdentityDefinition> IdentityRegistry::ResolveClass(std::string_view keyOrAlias) const
{
    auto const iterator = _classesByKey.find(NormalizeIdentityKey(keyOrAlias));
    return iterator == _classesByKey.end() ? IdentityResolution<ClassIdentityDefinition>{} : Found(_classes[iterator->second]);
}

IdentityResolution<ClassIdentityDefinition> IdentityRegistry::ResolveLogicalClass(LogicalClassId logicalId) const
{
    auto const iterator = _classesByLogicalId.find(logicalId.Value());
    return iterator == _classesByLogicalId.end() ? IdentityResolution<ClassIdentityDefinition>{} : Found(_classes[iterator->second]);
}

IdentityResolution<RaceIdentityDefinition> IdentityRegistry::ResolveRace(std::uint32_t runtimeRaceId) const
{
    auto const iterator = _racesByRuntimeId.find(runtimeRaceId);
    return iterator == _racesByRuntimeId.end() ? IdentityResolution<RaceIdentityDefinition>{} : Found(_races[iterator->second]);
}

IdentityResolution<RaceIdentityDefinition> IdentityRegistry::ResolveRace(std::string_view keyOrAlias) const
{
    auto const iterator = _racesByKey.find(NormalizeIdentityKey(keyOrAlias));
    return iterator == _racesByKey.end() ? IdentityResolution<RaceIdentityDefinition>{} : Found(_races[iterator->second]);
}

IdentityResolution<RaceIdentityDefinition> IdentityRegistry::ResolveLogicalRace(LogicalRaceId logicalId) const
{
    auto const iterator = _racesByLogicalId.find(logicalId.Value());
    return iterator == _racesByLogicalId.end() ? IdentityResolution<RaceIdentityDefinition>{} : Found(_races[iterator->second]);
}

std::string_view IdentityRegistry::ResolveCameraProfile(IdentityResolution<RaceIdentityDefinition> const& race) const noexcept
{
    if (!race.IsKnown() || race.Identity->CameraProfile.empty())
        return "global";
    return race.Identity->CameraProfile;
}

RacePresentationResolution IdentityRegistry::ResolveRacePresentation(
    IdentityResolution<RaceIdentityDefinition> const& race,
    RacePresentationResources const& resources) const noexcept
{
    RacePresentationResolution resolution;
    resolution.CameraProfile = ResolveCameraProfile(race);
    if (!race.IsKnown())
        return resolution;

    resolution.AppearanceOverrideProfile = race.Identity->AppearanceOverrideProfile;
    resolution.ModelProfile = race.Identity->ModelProfile;
    if (race.Identity->ClientAssetVersion.empty() ||
        resources.ClientAssetVersion != race.Identity->ClientAssetVersion)
    {
        resolution.Code = RacePresentationCode::AssetVersionMismatch;
        return resolution;
    }
    if (race.Identity->ModelProfile.empty() || !resources.ModelAvailable)
    {
        resolution.Code = RacePresentationCode::ModelMissing;
        return resolution;
    }
    if (!resources.TextureAvailable)
    {
        resolution.Code = RacePresentationCode::TextureMissing;
        return resolution;
    }

    resolution.Code = RacePresentationCode::Ok;
    resolution.PreviewEnabled = true;
    resolution.ActionEnabled = true;
    return resolution;
}

IdentityRegistry const& GetIdentityRegistry()
{
    static IdentityRegistry const registry(LoadGeneratedClassIdentities(), LoadGeneratedRaceIdentities());
    return registry;
}
}
