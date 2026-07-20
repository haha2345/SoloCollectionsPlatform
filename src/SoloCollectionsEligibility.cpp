#include "SoloCollectionsEligibility.h"

#include <algorithm>
#include <utility>

namespace SoloCollections
{
namespace
{
#include "generated/SoloCollectionsPolicyData.inc"

bool Contains(std::vector<std::string> const& values, std::string const& value)
{
    return std::find(values.begin(), values.end(), value) != values.end();
}

EligibilityResult Denied(EligibilityReason reason)
{
    return { reason };
}

EligibilityResult EvaluateDeclarativePolicy(
    EligibilityPolicyDefinition const& policy,
    EligibilityIdentityContext const& identity,
    CustomEligibilityPolicy const& customPolicy)
{
    for (std::string const& capability : policy.RequiredCapabilities)
        if (!identity.Capabilities.contains(capability))
            return Denied(EligibilityReason::RequiredCapabilityMissing);

    if (!policy.AnyCapabilities.empty())
    {
        bool found = false;
        for (std::string const& capability : policy.AnyCapabilities)
            found = found || identity.Capabilities.contains(capability);
        if (!found)
            return Denied(EligibilityReason::AnyCapabilityMissing);
    }

    for (std::string const& capability : policy.ForbiddenCapabilities)
        if (identity.Capabilities.contains(capability))
            return Denied(EligibilityReason::ForbiddenCapability);

    if (!policy.AllowedRaceKeys.empty() && !Contains(policy.AllowedRaceKeys, identity.RaceKey))
        return Denied(EligibilityReason::RaceNotAllowed);
    if (Contains(policy.DeniedRaceKeys, identity.RaceKey))
        return Denied(EligibilityReason::RaceDenied);
    if (!policy.AllowedClassKeys.empty() && !Contains(policy.AllowedClassKeys, identity.ClassKey))
        return Denied(EligibilityReason::ClassNotAllowed);
    if (Contains(policy.DeniedClassKeys, identity.ClassKey))
        return Denied(EligibilityReason::ClassDenied);
    if (!policy.FactionPolicy.empty() && policy.FactionPolicy != "ANY" && policy.FactionPolicy != identity.FactionKey)
        return Denied(EligibilityReason::FactionDenied);
    if (identity.Level < policy.MinimumLevel)
        return Denied(EligibilityReason::LevelTooLow);
    for (auto const& [skillKey, requiredRank] : policy.RequiredSkills)
    {
        auto const skill = identity.Skills.find(skillKey);
        if (skill == identity.Skills.end() || skill->second < requiredRank)
            return Denied(EligibilityReason::SkillTooLow);
    }
    if (!policy.CustomPolicyKey.empty() && (!customPolicy || !customPolicy(policy.CustomPolicyKey, identity)))
        return Denied(EligibilityReason::CustomPolicyDenied);
    return { EligibilityReason::Ok };
}
}

EligibilityPolicyRegistry::EligibilityPolicyRegistry(std::vector<EligibilityPolicyDefinition> policies)
    : _policies(std::move(policies))
{
    for (std::size_t index = 0; index < _policies.size(); ++index)
    {
        EligibilityPolicyDefinition const& policy = _policies[index];
        if (policy.PolicyKey.empty() || !_byKey.emplace(policy.PolicyKey, index).second)
        {
            _valid = false;
            if (_validationError.empty())
                _validationError = "duplicate or empty eligibility policy key";
        }
    }
    if (_byKey.find("unrestricted") == _byKey.end())
    {
        _valid = false;
        if (_validationError.empty())
            _validationError = "unrestricted eligibility policy is missing";
    }
}

EligibilityPolicyDefinition const* EligibilityPolicyRegistry::Find(std::string_view policyKey) const
{
    auto const iterator = _byKey.find(std::string(policyKey));
    return iterator == _byKey.end() ? nullptr : &_policies[iterator->second];
}

EligibilityPolicyRegistry const& GetEligibilityPolicyRegistry()
{
    static EligibilityPolicyRegistry const registry(LoadGeneratedEligibilityPolicies());
    return registry;
}

EligibilityIdentityContext BuildClassEligibilityContext(
    IdentityResolution<ClassIdentityDefinition> const& classIdentity,
    std::uint32_t level,
    std::unordered_map<std::string, std::uint32_t> skills)
{
    EligibilityIdentityContext context;
    context.Level = level;
    context.Skills = std::move(skills);
    if (!classIdentity.IsKnown())
        return context;

    context.IdentityKnown = true;
    context.LogicalClass = classIdentity.Identity->LogicalId;
    context.ClassKey = classIdentity.Identity->ClassKey;
    context.Capabilities.insert(
        classIdentity.Identity->Capabilities.begin(), classIdentity.Identity->Capabilities.end());
    return context;
}

EligibilityResult EvaluateEligibility(EligibilityRequest const& request)
{
    if (!request.Resources.CatalogKnown)
        return Denied(EligibilityReason::CatalogMissing);
    if (!request.Resources.TemplateValid)
        return Denied(EligibilityReason::TemplateMissing);
    if (!request.Resources.AssetReady)
        return Denied(EligibilityReason::AssetMissing);
    if (!request.Resources.Enabled)
        return Denied(EligibilityReason::Disabled);
    if (request.ExactOverride == ExactEligibilityOverride::Deny)
        return Denied(EligibilityReason::ExactDenied);
    if (!request.Policy || !request.Identity)
        return Denied(EligibilityReason::UnknownIdentity);

    EligibilityPolicyDefinition const& policy = *request.Policy;
    EligibilityIdentityContext const& identity = *request.Identity;
    if (!identity.IdentityKnown)
    {
        if (request.Mode != EligibilityMode::View || policy.PolicyKey != "unrestricted")
            return Denied(EligibilityReason::UnknownIdentity);
    }
    else if (request.ExactOverride != ExactEligibilityOverride::Allow)
    {
        EligibilityResult declarative = EvaluateDeclarativePolicy(policy, identity, request.CustomPolicy);
        if (!declarative.IsAllowed())
            return declarative;
        if (policy.LegacyFallback && (!request.LegacyFallback || !request.LegacyFallback(identity)))
            return Denied(EligibilityReason::LegacyFallbackDenied);
    }

    if (request.RuntimeCondition && !request.RuntimeCondition(identity))
        return Denied(EligibilityReason::RuntimeConditionDenied);
    return { EligibilityReason::Ok };
}
}
