#ifndef SOLO_COLLECTIONS_ELIGIBILITY_H
#define SOLO_COLLECTIONS_ELIGIBILITY_H

#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace SoloCollections
{
enum class EligibilityMode : std::uint8_t
{
    View = 0,
    Use = 1,
};

enum class ExactEligibilityOverride : std::uint8_t
{
    None = 0,
    Allow = 1,
    Deny = 2,
};

enum class EligibilityReason : std::uint16_t
{
    Ok = 0,
    CatalogMissing,
    TemplateMissing,
    AssetMissing,
    Disabled,
    ExactDenied,
    UnknownIdentity,
    RequiredCapabilityMissing,
    AnyCapabilityMissing,
    ForbiddenCapability,
    RaceNotAllowed,
    RaceDenied,
    ClassNotAllowed,
    ClassDenied,
    FactionDenied,
    LevelTooLow,
    SkillTooLow,
    CustomPolicyDenied,
    LegacyFallbackDenied,
    RuntimeConditionDenied,
};

struct EligibilityResourceState
{
    bool CatalogKnown = true;
    bool TemplateValid = true;
    bool AssetReady = true;
    bool Enabled = true;
};

struct EligibilityIdentityContext
{
    bool IdentityKnown = false;
    std::string ClassKey;
    std::string RaceKey;
    std::string FactionKey;
    std::unordered_set<std::string> Capabilities;
    std::uint32_t Level = 0;
    std::unordered_map<std::string, std::uint32_t> Skills;
};

struct EligibilityPolicyDefinition
{
    std::string PolicyKey;
    std::vector<std::string> RequiredCapabilities;
    std::vector<std::string> AnyCapabilities;
    std::vector<std::string> ForbiddenCapabilities;
    std::vector<std::string> AllowedRaceKeys;
    std::vector<std::string> DeniedRaceKeys;
    std::vector<std::string> AllowedClassKeys;
    std::vector<std::string> DeniedClassKeys;
    std::string FactionPolicy;
    std::uint32_t MinimumLevel = 0;
    std::unordered_map<std::string, std::uint32_t> RequiredSkills;
    std::string CustomPolicyKey;
    bool LegacyFallback = false;
};

using CustomEligibilityPolicy = std::function<bool(std::string_view, EligibilityIdentityContext const&)>;
using EligibilityCondition = std::function<bool(EligibilityIdentityContext const&)>;

struct EligibilityRequest
{
    EligibilityResourceState Resources;
    EligibilityMode Mode = EligibilityMode::Use;
    ExactEligibilityOverride ExactOverride = ExactEligibilityOverride::None;
    EligibilityPolicyDefinition const* Policy = nullptr;
    EligibilityIdentityContext const* Identity = nullptr;
    CustomEligibilityPolicy CustomPolicy;
    // Category providers may adapt imported AllowableRace/AllowableClass here;
    // legacy masks are never treated as the primary identity model.
    EligibilityCondition LegacyFallback;
    EligibilityCondition RuntimeCondition;
};

struct EligibilityResult
{
    EligibilityReason Reason = EligibilityReason::RuntimeConditionDenied;

    [[nodiscard]] bool IsAllowed() const noexcept { return Reason == EligibilityReason::Ok; }
};

class EligibilityPolicyRegistry final
{
public:
    explicit EligibilityPolicyRegistry(std::vector<EligibilityPolicyDefinition> policies);

    [[nodiscard]] bool IsValid() const noexcept { return _valid; }
    [[nodiscard]] std::string const& ValidationError() const noexcept { return _validationError; }
    [[nodiscard]] EligibilityPolicyDefinition const* Find(std::string_view policyKey) const;

private:
    std::vector<EligibilityPolicyDefinition> _policies;
    std::unordered_map<std::string, std::size_t> _byKey;
    bool _valid = true;
    std::string _validationError;
};

[[nodiscard]] EligibilityPolicyRegistry const& GetEligibilityPolicyRegistry();
[[nodiscard]] EligibilityResult EvaluateEligibility(EligibilityRequest const& request);
}

#endif
