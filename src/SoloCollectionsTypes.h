#ifndef SOLO_COLLECTIONS_TYPES_H
#define SOLO_COLLECTIONS_TYPES_H

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>
#include <type_traits>

namespace SoloCollections
{
template <typename Tag, typename Storage>
class StableId final
{
    static_assert(std::is_integral_v<Storage> && std::is_unsigned_v<Storage>,
        "Stable IDs require an explicitly sized unsigned integer storage type.");

public:
    using ValueType = Storage;

    constexpr StableId() noexcept = default;
    explicit constexpr StableId(Storage value) noexcept : _value(value) { }

    [[nodiscard]] constexpr Storage Value() const noexcept { return _value; }
    [[nodiscard]] constexpr bool IsValid() const noexcept { return _value != 0; }

    friend constexpr bool operator==(StableId left, StableId right) noexcept
    {
        return left._value == right._value;
    }

    friend constexpr bool operator!=(StableId left, StableId right) noexcept
    {
        return !(left == right);
    }

    friend constexpr bool operator<(StableId left, StableId right) noexcept
    {
        return left._value < right._value;
    }

private:
    Storage _value = 0;
};

struct CollectionTypeIdTag;
struct CollectionIdTag;
struct LogicalClassIdTag;
struct LogicalRaceIdTag;
struct CollectionRevisionTag;
struct AccountIdTag;
struct AccountSessionIdTag;
struct LoginGenerationTag;

using CollectionTypeId = StableId<CollectionTypeIdTag, std::uint16_t>;
using CollectionId = StableId<CollectionIdTag, std::uint32_t>;
using LogicalClassId = StableId<LogicalClassIdTag, std::uint16_t>;
using LogicalRaceId = StableId<LogicalRaceIdTag, std::uint16_t>;
using CollectionRevision = StableId<CollectionRevisionTag, std::uint64_t>;
using AccountId = StableId<AccountIdTag, std::uint32_t>;
using AccountSessionId = StableId<AccountSessionIdTag, std::uint64_t>;
using LoginGeneration = StableId<LoginGenerationTag, std::uint64_t>;

template <typename Id>
struct StableIdHash
{
    [[nodiscard]] std::size_t operator()(Id value) const noexcept
    {
        return static_cast<std::size_t>(value.Value());
    }
};

enum class StableIdLifecycle : std::uint8_t
{
    Active = 1,
    Tombstone = 2,
};

template <typename Id>
struct StableIdReservation
{
    Id Value;
    StableIdLifecycle Lifecycle = StableIdLifecycle::Active;

    [[nodiscard]] constexpr bool IsTombstone() const noexcept
    {
        return Lifecycle == StableIdLifecycle::Tombstone;
    }

    [[nodiscard]] constexpr bool CanBind() const noexcept
    {
        return Lifecycle == StableIdLifecycle::Active;
    }
};

// Values are protocol and persistence identifiers. Never renumber or reuse a
// retired value; add a new explicit value and keep the old one as a tombstone.
enum class CollectionReasonCode : std::uint16_t
{
    Ok = 0x0000,
    Disabled = 0x0100,
    ReadOnly = 0x0101,
    NotReady = 0x0200,
    LoadFailed = 0x0201,
    UnknownType = 0x0300,
    UnknownCollection = 0x0301,
    NotOwned = 0x0400,
    NotUsable = 0x0401,
    CatalogMissing = 0x0402,
    AssetMissing = 0x0403,
    AlreadyOwned = 0x0404,
    DependencyMissing = 0x0500,
    DuplicateProvider = 0x0501,
    DependencyCycle = 0x0502,
    Tombstoned = 0x0600,
    InvalidArgument = 0x0700,
    DatabaseError = 0x0701,
    RevisionConflict = 0x0702,
    PendingOperation = 0x0703,
    InternalError = 0x7FFF,
};

[[nodiscard]] constexpr std::uint16_t ToStableReasonCode(CollectionReasonCode reason) noexcept
{
    switch (reason)
    {
        case CollectionReasonCode::Ok: return 0x0000;
        case CollectionReasonCode::Disabled: return 0x0100;
        case CollectionReasonCode::ReadOnly: return 0x0101;
        case CollectionReasonCode::NotReady: return 0x0200;
        case CollectionReasonCode::LoadFailed: return 0x0201;
        case CollectionReasonCode::UnknownType: return 0x0300;
        case CollectionReasonCode::UnknownCollection: return 0x0301;
        case CollectionReasonCode::NotOwned: return 0x0400;
        case CollectionReasonCode::NotUsable: return 0x0401;
        case CollectionReasonCode::CatalogMissing: return 0x0402;
        case CollectionReasonCode::AssetMissing: return 0x0403;
        case CollectionReasonCode::AlreadyOwned: return 0x0404;
        case CollectionReasonCode::DependencyMissing: return 0x0500;
        case CollectionReasonCode::DuplicateProvider: return 0x0501;
        case CollectionReasonCode::DependencyCycle: return 0x0502;
        case CollectionReasonCode::Tombstoned: return 0x0600;
        case CollectionReasonCode::InvalidArgument: return 0x0700;
        case CollectionReasonCode::DatabaseError: return 0x0701;
        case CollectionReasonCode::RevisionConflict: return 0x0702;
        case CollectionReasonCode::PendingOperation: return 0x0703;
        case CollectionReasonCode::InternalError: return 0x7FFF;
    }
    return 0x7FFF;
}

[[nodiscard]] constexpr std::optional<CollectionReasonCode> ParseStableReasonCode(std::uint16_t value) noexcept
{
    switch (value)
    {
        case 0x0000: return CollectionReasonCode::Ok;
        case 0x0100: return CollectionReasonCode::Disabled;
        case 0x0101: return CollectionReasonCode::ReadOnly;
        case 0x0200: return CollectionReasonCode::NotReady;
        case 0x0201: return CollectionReasonCode::LoadFailed;
        case 0x0300: return CollectionReasonCode::UnknownType;
        case 0x0301: return CollectionReasonCode::UnknownCollection;
        case 0x0400: return CollectionReasonCode::NotOwned;
        case 0x0401: return CollectionReasonCode::NotUsable;
        case 0x0402: return CollectionReasonCode::CatalogMissing;
        case 0x0403: return CollectionReasonCode::AssetMissing;
        case 0x0404: return CollectionReasonCode::AlreadyOwned;
        case 0x0500: return CollectionReasonCode::DependencyMissing;
        case 0x0501: return CollectionReasonCode::DuplicateProvider;
        case 0x0502: return CollectionReasonCode::DependencyCycle;
        case 0x0600: return CollectionReasonCode::Tombstoned;
        case 0x0700: return CollectionReasonCode::InvalidArgument;
        case 0x0701: return CollectionReasonCode::DatabaseError;
        case 0x0702: return CollectionReasonCode::RevisionConflict;
        case 0x0703: return CollectionReasonCode::PendingOperation;
        case 0x7FFF: return CollectionReasonCode::InternalError;
        default: return std::nullopt;
    }
}

[[nodiscard]] constexpr std::string_view ReasonCodeLocalizationKey(CollectionReasonCode reason) noexcept
{
    switch (reason)
    {
        case CollectionReasonCode::Ok: return "SC_REASON_OK";
        case CollectionReasonCode::Disabled: return "SC_REASON_DISABLED";
        case CollectionReasonCode::ReadOnly: return "SC_REASON_READ_ONLY";
        case CollectionReasonCode::NotReady: return "SC_REASON_NOT_READY";
        case CollectionReasonCode::LoadFailed: return "SC_REASON_LOAD_FAILED";
        case CollectionReasonCode::UnknownType: return "SC_REASON_UNKNOWN_TYPE";
        case CollectionReasonCode::UnknownCollection: return "SC_REASON_UNKNOWN_COLLECTION";
        case CollectionReasonCode::NotOwned: return "SC_REASON_NOT_OWNED";
        case CollectionReasonCode::NotUsable: return "SC_REASON_NOT_USABLE";
        case CollectionReasonCode::CatalogMissing: return "SC_REASON_CATALOG_MISSING";
        case CollectionReasonCode::AssetMissing: return "SC_REASON_ASSET_MISSING";
        case CollectionReasonCode::AlreadyOwned: return "SC_REASON_ALREADY_OWNED";
        case CollectionReasonCode::DependencyMissing: return "SC_REASON_DEPENDENCY_MISSING";
        case CollectionReasonCode::DuplicateProvider: return "SC_REASON_DUPLICATE_PROVIDER";
        case CollectionReasonCode::DependencyCycle: return "SC_REASON_DEPENDENCY_CYCLE";
        case CollectionReasonCode::Tombstoned: return "SC_REASON_TOMBSTONED";
        case CollectionReasonCode::InvalidArgument: return "SC_REASON_INVALID_ARGUMENT";
        case CollectionReasonCode::DatabaseError: return "SC_REASON_DATABASE_ERROR";
        case CollectionReasonCode::RevisionConflict: return "SC_REASON_REVISION_CONFLICT";
        case CollectionReasonCode::PendingOperation: return "SC_REASON_PENDING_OPERATION";
        case CollectionReasonCode::InternalError: return "SC_REASON_INTERNAL_ERROR";
    }
    return "SC_REASON_INTERNAL_ERROR";
}

struct CollectionAvailability
{
    bool Owned = false;
    bool UsableNow = false;
    bool CatalogKnown = false;
    bool AssetReady = false;
};

struct CollectionResult
{
    CollectionReasonCode Reason = CollectionReasonCode::InternalError;
    CollectionAvailability Availability;
    CollectionRevision Revision;

    [[nodiscard]] constexpr bool IsSuccess() const noexcept
    {
        return Reason == CollectionReasonCode::Ok;
    }
};
}

#endif
