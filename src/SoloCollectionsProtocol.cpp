#include "SoloCollectionsProtocol.h"

#include <algorithm>
#include <charconv>
#include <iomanip>
#include <limits>
#include <set>
#include <sstream>
#include <stdexcept>

namespace SoloCollections
{
namespace
{
bool IsLowerHex(std::string_view value, std::size_t size)
{
    return value.size() == size && std::all_of(value.begin(), value.end(), [](char character)
    {
        return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f');
    });
}

bool IsToken(std::string_view value)
{
    return !value.empty() && value.size() <= Sc2Limits::MaxTokenBytes && std::all_of(value.begin(), value.end(), [](char character)
    {
        return (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') ||
            (character >= '0' && character <= '9') || character == '.' || character == '_' ||
            character == '~' || character == '-';
    });
}

bool IsAction(std::string_view value)
{
    if (value.empty() || value.size() > 32 || value.front() < 'A' || value.front() > 'Z')
        return false;
    return std::all_of(value.begin() + 1, value.end(), [](char character)
    {
        return (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character == '_';
    });
}

bool IsChunkChar(char character)
{
    return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'z') ||
        character == ',' || character == '-' || character == ':' || character == ';';
}

bool IsChunk(std::string_view value)
{
    return !value.empty() && value.size() <= Sc2Limits::MaxChunkPayloadBytes &&
        std::all_of(value.begin(), value.end(), IsChunkChar);
}

bool IsNameHex(std::string_view value)
{
    return value.size() >= 2 && value.size() <= 96 && (value.size() % 2) == 0 &&
        std::all_of(value.begin(), value.end(), [](char character)
        {
            return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f');
        });
}

template <typename Integer>
bool ParseUnsigned(std::string_view text, Integer minimum, Integer maximum, Integer& output)
{
    if (text.empty() || (text.size() > 1 && text.front() == '0') || text.front() == '+' || text.front() == '-')
        return false;
    Integer parsed = 0;
    auto conversion = std::from_chars(text.data(), text.data() + text.size(), parsed);
    if (conversion.ec != std::errc() || conversion.ptr != text.data() + text.size() ||
        parsed < minimum || parsed > maximum)
        return false;
    output = parsed;
    return true;
}

bool IsWardrobeApplyEntries(std::string_view value)
{
    if (value.empty() || value.size() > 200)
        return false;
    std::size_t items = 1;
    std::size_t begin = 0;
    while (begin < value.size())
    {
        std::size_t colon = value.find(':', begin);
        std::size_t comma = value.find(',', begin);
        if (colon == std::string_view::npos || (comma != std::string_view::npos && colon > comma))
            return false;
        std::uint32_t slot = 0;
        std::uint32_t collectionId = 0;
        if (!ParseUnsigned(value.substr(begin, colon - begin), std::uint32_t { 1 },
                std::numeric_limits<std::uint32_t>::max(), slot))
            return false;
        std::size_t idEnd = comma == std::string_view::npos ? value.size() : comma;
        if (!ParseUnsigned(value.substr(colon + 1, idEnd - colon - 1), std::uint32_t { 1 },
                std::numeric_limits<std::uint32_t>::max(), collectionId))
            return false;
        if (comma == std::string_view::npos)
            break;
        ++items;
        if (items > 14)
            return false;
        begin = comma + 1;
    }
    return items >= 1 && items <= 14;
}

bool IsWardrobeClearEntries(std::string_view value)
{
    if (value == "-")
        return true;
    if (value.empty() || value.size() > 80)
        return false;
    std::size_t items = 1;
    std::size_t begin = 0;
    while (begin < value.size())
    {
        std::size_t comma = value.find(',', begin);
        std::uint32_t slot = 0;
        std::size_t end = comma == std::string_view::npos ? value.size() : comma;
        if (!ParseUnsigned(value.substr(begin, end - begin), std::uint32_t { 1 },
                std::numeric_limits<std::uint32_t>::max(), slot))
            return false;
        if (comma == std::string_view::npos)
            break;
        ++items;
        if (items > 14)
            return false;
        begin = comma + 1;
    }
    return items >= 1 && items <= 14;
}

bool IsOutfitEntries(std::string_view value)
{
    if (value == "-")
        return true;
    std::size_t items = 1;
    std::size_t begin = 0;
    while (begin < value.size())
    {
        std::size_t comma = value.find(',', begin);
        std::string_view token = value.substr(begin, (comma == std::string_view::npos ? value.size() : comma) - begin);
        if (token != "-")
        {
            std::uint32_t collectionId = 0;
            if (!ParseUnsigned(token, std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), collectionId))
                return false;
        }
        if (comma == std::string_view::npos)
            break;
        ++items;
        begin = comma + 1;
    }
    return items == 14;
}

std::size_t CountListItems(std::string_view value)
{
    if (value.empty() || value == "-")
        return 0;
    return static_cast<std::size_t>(std::count(value.begin(), value.end(), ',')) + 1;
}

std::vector<std::string_view> Split(std::string_view body)
{
    std::vector<std::string_view> fields;
    std::size_t begin = 0;
    while (true)
    {
        std::size_t separator = body.find('|', begin);
        if (separator == std::string_view::npos)
        {
            fields.push_back(body.substr(begin));
            break;
        }
        fields.push_back(body.substr(begin, separator - begin));
        begin = separator + 1;
    }
    return fields;
}

bool IsOneOf(std::string_view value, std::initializer_list<std::string_view> values)
{
    return std::find(values.begin(), values.end(), value) != values.end();
}

Sc2DecodeResult Failure(std::string message)
{
    Sc2DecodeResult result;
    result.Error = std::move(message);
    return result;
}

std::string Join(std::initializer_list<std::string> fields)
{
    std::string result;
    for (std::string const& field : fields)
    {
        if (!result.empty())
            result.push_back('|');
        result += field;
    }
    if (result.size() > Sc2Limits::MaxBodyBytes)
        throw std::invalid_argument("SC2 packet exceeds body limit");
    return result;
}

std::string Number(std::uint64_t value)
{
    return std::to_string(value);
}
}

std::string Sc2Adler32Hex(std::string_view payload)
{
    constexpr std::uint32_t Modulus = 65521;
    std::uint32_t first = 1;
    std::uint32_t second = 0;
    for (unsigned char byte : payload)
    {
        first = (first + byte) % Modulus;
        second = (second + first) % Modulus;
    }
    std::ostringstream stream;
    stream << std::hex << std::setfill('0') << std::setw(8) << ((second << 16) | first);
    return stream.str();
}

std::string Sc2ToBase36(std::uint32_t value)
{
    constexpr std::string_view Alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
    if (value == 0)
        return "0";
    std::string result;
    while (value != 0)
    {
        result.push_back(Alphabet[value % 36]);
        value /= 36;
    }
    std::reverse(result.begin(), result.end());
    return result;
}

std::string Sc2CanonicalOwnedPayload(std::vector<std::uint32_t> values)
{
    std::sort(values.begin(), values.end());
    values.erase(std::unique(values.begin(), values.end()), values.end());
    if (values.empty())
        return "-";
    std::string result;
    for (std::uint32_t value : values)
    {
        if (!result.empty())
            result.push_back(',');
        result += Sc2ToBase36(value);
    }
    return result;
}

std::vector<std::string> Sc2ChunkPayload(std::string_view payload)
{
    if (!IsChunk(payload) && !(payload.size() > Sc2Limits::MaxChunkPayloadBytes &&
        std::all_of(payload.begin(), payload.end(), IsChunkChar)))
        throw std::invalid_argument("invalid SC2 snapshot payload");
    if (payload.size() > Sc2Limits::MaxSnapshotBytes)
        throw std::invalid_argument("SC2 snapshot exceeds byte limit");
    std::vector<std::string> chunks;
    for (std::size_t offset = 0; offset < payload.size(); offset += Sc2Limits::MaxChunkPayloadBytes)
        chunks.emplace_back(payload.substr(offset, Sc2Limits::MaxChunkPayloadBytes));
    if (chunks.empty() || chunks.size() > Sc2Limits::MaxSnapshotChunks)
        throw std::invalid_argument("SC2 snapshot exceeds chunk limit");
    return chunks;
}

Sc2DecodeResult DecodeSc2Body(std::string_view body)
{
    if (body.empty() || body.size() > Sc2Limits::MaxBodyBytes ||
        !std::all_of(body.begin(), body.end(), [](unsigned char character) { return character <= 0x7f; }))
        return Failure("invalid body length or encoding");
    std::vector<std::string_view> fields = Split(body);
    if (fields.empty() || fields[0].size() != 1)
        return Failure("invalid message code");

    Sc2Message message;
    auto nonce = [&fields, &message](std::size_t index)
    {
        if (index >= fields.size() || !IsLowerHex(fields[index], 16))
            return false;
        message.SessionNonce = fields[index];
        return true;
    };
    auto typeId = [&fields, &message](std::size_t index, std::uint16_t minimum = 1)
    {
        return index < fields.size() && ParseUnsigned(fields[index], minimum,
            std::numeric_limits<std::uint16_t>::max(), message.TypeId);
    };
    auto revision = [&fields, &message](std::size_t index)
    {
        return index < fields.size() && ParseUnsigned(fields[index], std::uint64_t { 0 },
            std::numeric_limits<std::uint64_t>::max(), message.Revision);
    };

    switch (fields[0][0])
    {
        case 'H':
            if (fields.size() != 6 || !ParseUnsigned(fields[1], std::uint16_t { 1 }, std::uint16_t { 999 }, message.ProtocolVersion) ||
                !IsLowerHex(fields[2], 16) || !IsToken(fields[3]) || !IsToken(fields[4]) || !IsToken(fields[5]))
                return Failure("invalid HELLO");
            message.Kind = Sc2MessageKind::Hello;
            message.ClientNonce = fields[2];
            message.ClientBuild = fields[3];
            message.MetadataVersion = fields[4];
            message.AssetPackVersion = fields[5];
            break;
        case 'A':
        {
            std::uint64_t accountRevision = 0;
            if (fields.size() != 9 || !ParseUnsigned(fields[1], std::uint16_t { 1 }, std::uint16_t { 999 }, message.ProtocolVersion) ||
                !nonce(2) || !ParseUnsigned(fields[3], std::uint64_t { 0 }, std::numeric_limits<std::uint64_t>::max(), accountRevision) ||
                !IsLowerHex(fields[4], 8) || !IsToken(fields[5]) || !IsToken(fields[6]) || !IsToken(fields[7]) ||
                !ParseUnsigned(fields[8], std::uint8_t { 0 }, std::numeric_limits<std::uint8_t>::max(), message.CategoryCount))
                return Failure("invalid HELLO_ACK");
            message.Kind = Sc2MessageKind::HelloAck;
            message.Revision = accountRevision;
            message.EnabledCategoryFlags = fields[4];
            message.MetadataVersion = fields[5];
            message.AssetPackVersion = fields[6];
            message.BackendBuild = fields[7];
            break;
        }
        case 'M':
            if (fields.size() != 4 || !nonce(1) || !typeId(2) || !IsLowerHex(fields[3], 64))
                return Failure("invalid CATEGORY_MAP");
            message.Kind = Sc2MessageKind::CategoryMap;
            message.MappingHash = fields[3];
            break;
        case 'B':
            if (fields.size() != 8 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.TransferId) ||
                !typeId(3) || !ParseUnsigned(fields[4], std::uint16_t { 1 }, static_cast<std::uint16_t>(Sc2Limits::MaxSnapshotChunks), message.Total) ||
                !revision(5) || !IsLowerHex(fields[6], 8) ||
                !ParseUnsigned(fields[7], std::uint32_t { 1 }, static_cast<std::uint32_t>(Sc2Limits::MaxSnapshotBytes), message.PayloadBytes))
                return Failure("invalid SNAPSHOT_BEGIN");
            message.Kind = Sc2MessageKind::SnapshotBegin;
            message.Checksum = fields[6];
            break;
        case 'C':
            if (fields.size() != 5 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.TransferId) ||
                !ParseUnsigned(fields[3], std::uint16_t { 1 }, static_cast<std::uint16_t>(Sc2Limits::MaxSnapshotChunks), message.Seq) ||
                !IsChunk(fields[4]))
                return Failure("invalid SNAPSHOT_CHUNK");
            message.Kind = Sc2MessageKind::SnapshotChunk;
            message.Payload = fields[4];
            break;
        case 'E':
            if (fields.size() != 4 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.TransferId) ||
                !IsLowerHex(fields[3], 8))
                return Failure("invalid SNAPSHOT_END");
            message.Kind = Sc2MessageKind::SnapshotEnd;
            message.Checksum = fields[3];
            break;
        case 'D':
            if (fields.size() != 6 || !nonce(1) || !typeId(2) || !revision(3) ||
                !IsOneOf(fields[4], { "A", "R" }) || !ParseUnsigned(fields[5], std::uint32_t { 1 },
                    std::numeric_limits<std::uint32_t>::max(), message.CollectionId))
                return Failure("invalid DELTA");
            message.Kind = Sc2MessageKind::Delta;
            message.Operation = fields[4];
            break;
        case 'Q':
            if (fields.size() != 7 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.RequestId) ||
                !typeId(3) || !ParseUnsigned(fields[4], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.CollectionId) ||
                !IsAction(fields[5]) || !(fields[6] == "-" || [&fields]()
                {
                    std::uint32_t target = 0;
                    return ParseUnsigned(fields[6], std::uint32_t { 0 }, std::numeric_limits<std::uint32_t>::max(), target);
                }()))
                return Failure("invalid ACTION_REQUEST");
            message.Kind = Sc2MessageKind::ActionRequest;
            message.ActionId = fields[5];
            message.Target = fields[6];
            break;
        case 'R':
            if (fields.size() != 7 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.RequestId) ||
                !IsOneOf(fields[3], { "ACCEPTED", "DISMISSED", "LOADING", "NOT_OWNED", "FAVORITE_NOT_OWNED",
                    "CATALOG_MISMATCH", "ASSET_MISMATCH",
                    "UNKNOWN_IDENTITY", "CLASS_RESTRICTED", "RACE_RESTRICTED", "SKILL_REQUIRED",
                    "WEAPON_TYPE", "ARMOR_TYPE", "INVALID_TARGET_SLOT",
                    "NOT_ENOUGH_MONEY", "NOT_ENOUGH_TOKENS",
                    "DB_UNAVAILABLE", "RATE_LIMITED", "INVALID_REQUEST", "UNSUPPORTED", "IN_COMBAT", "DEAD",
                    "IN_VEHICLE", "ON_TAXI", "INDOORS", "FLYING_NOT_ALLOWED", "MAP_RESTRICTED",
                    "BATTLEGROUND_RESTRICTED", "SHAPESHIFT_RESTRICTED", "CAST_FAILED", "NO_MOUNTS", "NO_USABLE_MOUNTS",
                    "INSUFFICIENT_FUNDS", "OUTFIT_LIMIT", "OUTFIT_EMPTY", "COST_CHANGED", "NOTHING_EQUIPPED" }) ||
                !typeId(4) || !ParseUnsigned(fields[5], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.CollectionId) ||
                !revision(6))
                return Failure("invalid ACTION_RESULT");
            message.Kind = Sc2MessageKind::ActionResult;
            message.Status = fields[3];
            break;
        case 'S':
            if (fields.size() != 5 || !nonce(1) ||
                !IsOneOf(fields[2], { "CLIENT_REQUEST", "REVISION_GAP", "CHECKSUM_MISMATCH", "CATALOG_MISMATCH", "TRANSFER_TIMEOUT" }) ||
                !typeId(3, 0) || !revision(4))
                return Failure("invalid RESYNC");
            message.Kind = Sc2MessageKind::Resync;
            message.Reason = fields[2];
            break;
        case 'X':
            if (fields.size() != 4 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 0 }, std::numeric_limits<std::uint32_t>::max(), message.RequestId) ||
                !IsOneOf(fields[3], { "BAD_MESSAGE", "BAD_NONCE", "RATE_LIMITED", "LOADING", "UNSUPPORTED_VERSION",
                    "REPLAYED_REQUEST", "SNAPSHOT_TOO_LARGE", "DB_UNAVAILABLE" }))
                return Failure("invalid ERROR");
            message.Kind = Sc2MessageKind::Error;
            message.Reason = fields[3];
            break;
        case 'Y':
        {
            std::uint8_t slotCount = 0;
            if (fields.size() != 6 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.RequestId) ||
                !IsOneOf(fields[3], { "QUOTE", "APPLY", "CLEAR" }) ||
                !ParseUnsigned(fields[4], std::uint8_t { 0 }, std::uint8_t { 14 }, slotCount))
                return Failure("invalid WARDROBE_INTENT");
            if (fields[3] == "CLEAR")
            {
                if (!IsWardrobeClearEntries(fields[5]) || CountListItems(fields[5]) != slotCount)
                    return Failure("invalid WARDROBE_INTENT");
            }
            else if (!IsWardrobeApplyEntries(fields[5]) || CountListItems(fields[5]) != slotCount)
                return Failure("invalid WARDROBE_INTENT");
            message.Kind = Sc2MessageKind::WardrobeIntent;
            message.Op = fields[3];
            message.SlotCount = slotCount;
            message.Entries = fields[5];
            break;
        }
        case 'U':
            if (fields.size() != 6 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.RequestId) ||
                !IsOneOf(fields[3], { "ACCEPTED", "DISMISSED", "LOADING", "NOT_OWNED", "FAVORITE_NOT_OWNED",
                    "CATALOG_MISMATCH", "ASSET_MISMATCH",
                    "UNKNOWN_IDENTITY", "CLASS_RESTRICTED", "RACE_RESTRICTED", "SKILL_REQUIRED",
                    "WEAPON_TYPE", "ARMOR_TYPE", "INVALID_TARGET_SLOT",
                    "NOT_ENOUGH_MONEY", "NOT_ENOUGH_TOKENS",
                    "DB_UNAVAILABLE", "RATE_LIMITED", "INVALID_REQUEST", "UNSUPPORTED", "IN_COMBAT", "DEAD",
                    "IN_VEHICLE", "ON_TAXI", "INDOORS", "FLYING_NOT_ALLOWED", "MAP_RESTRICTED",
                    "BATTLEGROUND_RESTRICTED", "SHAPESHIFT_RESTRICTED", "CAST_FAILED", "NO_MOUNTS", "NO_USABLE_MOUNTS",
                    "INSUFFICIENT_FUNDS", "OUTFIT_LIMIT", "OUTFIT_EMPTY", "COST_CHANGED", "NOTHING_EQUIPPED" }) ||
                !ParseUnsigned(fields[4], std::uint32_t { 0 }, std::numeric_limits<std::uint32_t>::max(), message.Copper) ||
                !IsLowerHex(fields[5], 8))
                return Failure("invalid WARDROBE_QUOTE");
            message.Kind = Sc2MessageKind::WardrobeQuote;
            message.Status = fields[3];
            message.WarningMask = fields[5];
            break;
        case 'O':
            if (fields.size() != 7 || !nonce(1) ||
                !ParseUnsigned(fields[2], std::uint32_t { 1 }, std::numeric_limits<std::uint32_t>::max(), message.RequestId) ||
                !IsOneOf(fields[3], { "SAVE", "RENAME" }) ||
                !ParseUnsigned(fields[4], std::uint32_t { 0 }, std::numeric_limits<std::uint32_t>::max(), message.Uid) ||
                !IsNameHex(fields[5]) || !IsOutfitEntries(fields[6]))
                return Failure("invalid OUTFIT_WRITE");
            if ((fields[3] == "RENAME" && fields[6] != "-") || (fields[3] == "SAVE" && fields[6] == "-"))
                return Failure("invalid OUTFIT_WRITE");
            message.Kind = Sc2MessageKind::OutfitWrite;
            message.Op = fields[3];
            message.NameHex = fields[5];
            message.Entries = fields[6];
            break;
        default:
            return Failure("unknown message code");
    }
    Sc2DecodeResult result;
    result.Success = true;
    result.Message = std::move(message);
    return result;
}

std::string EncodeSc2Message(Sc2Message const& message)
{
    switch (message.Kind)
    {
        case Sc2MessageKind::Hello:
            return Join({ "H", Number(message.ProtocolVersion), message.ClientNonce, message.ClientBuild,
                message.MetadataVersion, message.AssetPackVersion });
        case Sc2MessageKind::HelloAck:
            return Join({ "A", Number(message.ProtocolVersion), message.SessionNonce, Number(message.Revision),
                message.EnabledCategoryFlags, message.MetadataVersion, message.AssetPackVersion,
                message.BackendBuild, Number(message.CategoryCount) });
        case Sc2MessageKind::CategoryMap:
            return Join({ "M", message.SessionNonce, Number(message.TypeId), message.MappingHash });
        case Sc2MessageKind::SnapshotBegin:
            return Join({ "B", message.SessionNonce, Number(message.TransferId), Number(message.TypeId),
                Number(message.Total), Number(message.Revision), message.Checksum, Number(message.PayloadBytes) });
        case Sc2MessageKind::SnapshotChunk:
            return Join({ "C", message.SessionNonce, Number(message.TransferId), Number(message.Seq), message.Payload });
        case Sc2MessageKind::SnapshotEnd:
            return Join({ "E", message.SessionNonce, Number(message.TransferId), message.Checksum });
        case Sc2MessageKind::Delta:
            return Join({ "D", message.SessionNonce, Number(message.TypeId), Number(message.Revision),
                message.Operation, Number(message.CollectionId) });
        case Sc2MessageKind::ActionRequest:
            return Join({ "Q", message.SessionNonce, Number(message.RequestId), Number(message.TypeId),
                Number(message.CollectionId), message.ActionId, message.Target });
        case Sc2MessageKind::ActionResult:
            return Join({ "R", message.SessionNonce, Number(message.RequestId), message.Status,
                Number(message.TypeId), Number(message.CollectionId), Number(message.Revision) });
        case Sc2MessageKind::Resync:
            return Join({ "S", message.SessionNonce, message.Reason, Number(message.TypeId), Number(message.Revision) });
        case Sc2MessageKind::Error:
            return Join({ "X", message.SessionNonce, Number(message.RequestId), message.Reason });
        case Sc2MessageKind::WardrobeIntent:
            return Join({ "Y", message.SessionNonce, Number(message.RequestId), message.Op,
                Number(message.SlotCount), message.Entries });
        case Sc2MessageKind::WardrobeQuote:
            return Join({ "U", message.SessionNonce, Number(message.RequestId), message.Status,
                Number(message.Copper), message.WarningMask });
        case Sc2MessageKind::OutfitWrite:
            return Join({ "O", message.SessionNonce, Number(message.RequestId), message.Op,
                Number(message.Uid), message.NameHex, message.Entries });
    }
    throw std::invalid_argument("unknown SC2 message kind");
}
}
