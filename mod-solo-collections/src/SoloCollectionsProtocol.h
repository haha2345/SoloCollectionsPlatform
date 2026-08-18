#ifndef SOLO_COLLECTIONS_PROTOCOL_H
#define SOLO_COLLECTIONS_PROTOCOL_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace SoloCollections
{
inline constexpr std::uint16_t Sc2ProtocolVersion = 1;

struct Sc2Limits
{
    static constexpr std::size_t MaxBodyBytes = 240;
    static constexpr std::size_t MaxTokenBytes = 64;
    static constexpr std::size_t MaxChunkPayloadBytes = 160;
    static constexpr std::size_t MaxSnapshotChunks = 256;
    static constexpr std::size_t MaxSnapshotBytes = 32768;
    static constexpr std::size_t MaxPacketsPerTick = 4;
};

enum class Sc2MessageKind : std::uint8_t
{
    Hello,
    HelloAck,
    CategoryMap,
    SnapshotBegin,
    SnapshotChunk,
    SnapshotEnd,
    Delta,
    ActionRequest,
    ActionResult,
    WardrobeIntent,
    WardrobeQuote,
    OutfitWrite,
    Resync,
    Error,
};

struct Sc2Message
{
    Sc2MessageKind Kind = Sc2MessageKind::Error;
    std::uint16_t ProtocolVersion = 0;
    std::string ClientNonce;
    std::string SessionNonce;
    std::string ClientBuild;
    std::string MetadataVersion;
    std::string AssetPackVersion;
    std::string BackendBuild;
    std::string EnabledCategoryFlags;
    std::string MappingHash;
    std::string Checksum;
    std::string Payload;
    std::string Operation;
    std::string ActionId;
    std::string Target;
    std::string Status;
    std::string Reason;
    std::string Op;
    std::string Entries;
    std::string NameHex;
    std::string WarningMask;
    std::uint16_t TypeId = 0;
    std::uint16_t Total = 0;
    std::uint16_t Seq = 0;
    std::uint8_t CategoryCount = 0;
    std::uint32_t TransferId = 0;
    std::uint32_t RequestId = 0;
    std::uint32_t CollectionId = 0;
    std::uint32_t PayloadBytes = 0;
    std::uint32_t Copper = 0;
    std::uint32_t Uid = 0;
    std::uint8_t SlotCount = 0;
    std::uint64_t Revision = 0;
};

struct Sc2DecodeResult
{
    bool Success = false;
    Sc2Message Message;
    std::string Error;
};

[[nodiscard]] Sc2DecodeResult DecodeSc2Body(std::string_view body);
[[nodiscard]] std::string EncodeSc2Message(Sc2Message const& message);
[[nodiscard]] std::string Sc2Adler32Hex(std::string_view payload);
[[nodiscard]] std::string Sc2ToBase36(std::uint32_t value);
[[nodiscard]] std::string Sc2CanonicalOwnedPayload(std::vector<std::uint32_t> values);
[[nodiscard]] std::vector<std::string> Sc2ChunkPayload(std::string_view payload);
}

#endif
