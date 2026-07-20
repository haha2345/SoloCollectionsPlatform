# SC2 wire contract v1

SC2 is the server-authoritative SoloCollections AddOn protocol. The registered
AddOn prefix is `SC2`; every body is ASCII, uses `|` as its separator, and is
sent only as an AddOn whisper from the player to itself. The body limit is 240
bytes, leaving 15 bytes of headroom below the Core 255-byte ceiling.

The machine-readable contract is `protocol/sc2/schema.json`. The normative
cross-language examples are `protocol/sc2/golden-vectors.json`; Python, Lua,
and C++ codecs must reproduce those bytes exactly.

## Canonical fields

- All integers use canonical unsigned decimal: `0` or a non-zero digit followed
  by digits. Leading zeroes and signs are rejected.
- A nonce is exactly 16 lowercase hexadecimal characters. A new client HELLO
  nonce creates a new server session nonce; reconnect, relog, and `/reload`
  invalidate old transfers, deltas, requests, and results.
- Mapping hashes are full lowercase SHA-256 values. Snapshot checksums are
  lowercase eight-character Adler-32 values over the reassembled ASCII payload.
- Version/build tokens contain 1–32 ASCII letters, digits, `.`, `_`, `~`, or `-`.
- Collection snapshots encode sorted unique uint32 IDs in lowercase base36,
  separated by commas. `-` is the canonical empty set.
- Free-form server text is never legal. Stable status/reason codes are localized
  by the AddOn.

## Messages

The one-letter code is part of the protocol and is followed by the exact fields
shown below. Extra, missing, empty, noncanonical, or oversized fields reject the
entire packet.

```text
H|protocolVersion|clientNonce|clientBuild|metadataVersion|assetPackVersion
A|protocolVersion|sessionNonce|accountRevision|enabledCategoryFlags|metadataVersion|assetPackVersion|backendBuild|categoryCount
M|sessionNonce|typeId|mappingHash

B|sessionNonce|transferId|typeId|total|baseRevision|checksum|payloadBytes
C|sessionNonce|transferId|seq|payload
E|sessionNonce|transferId|checksum
D|sessionNonce|typeId|revision|operation|collectionId

Q|sessionNonce|requestId|typeId|collectionId|actionId|target
R|sessionNonce|requestId|status|typeId|collectionId|revision
S|sessionNonce|reason|typeId|revision
X|sessionNonce|requestId|reason
```

`enabledCategoryFlags` is an eight-digit lowercase hexadecimal bitset. Bit
`typeId - 1` announces that a category is enabled. The ACK is followed by
exactly `categoryCount` `M` packets, one for each enabled category. Sending full
hashes separately keeps the ACK well below the transport limit and allows one
category to degrade without disabling the others.

`operation` is `A` (add) or `R` (remove). `target` is `-` when absent or a
bounded uint32 selected by the action schema. An action request identifies only
stable collection/action IDs; spell, item, display, handler, and arbitrary
script identifiers are never accepted from the client.

## Snapshot state machine

1. After `A` and all expected `M` packets, the server emits one `B/C.../E`
   transfer per enabled category. A chunk payload is at most 160 bytes; a
   transfer is at most 256 chunks and 32 KiB.
2. The receiver indexes chunks by `(sessionNonce, transferId)`. Duplicate chunks
   are allowed only when their bytes are identical. Sequence order on the wire
   is irrelevant.
3. `E` commits only when every sequence from 1 through `total` exists, the byte
   count matches, both checksums match, the category mapping hash matches, and
   the complete payload is canonical.
4. Commit is an atomic replacement of that category's owned set at
   `baseRevision`. Deltas arriving during a transfer are queued and then applied
   in contiguous revision order.
5. A missing chunk, conflicting duplicate, checksum failure, mapping mismatch,
   timeout, or revision gap keeps the last good state and sends bounded `S`.
   Packets with an old nonce are silently discarded.

The server must return `LOADING` while the account cache is not ready; an empty
snapshot means a confirmed empty owned set, never an unknown or failed load.

## Limits and replay rules

The receiver validates body size before splitting, then exact field count,
ASCII character classes, decimal digit length, numeric range, and enum values.
Inbound requests pass a per-session token bucket. Completed `requestId` values
remain in a short bounded replay cache, and replay returns `REPLAYED_REQUEST`
without repeating an action. Outbound snapshot packets are queued across world
ticks rather than emitted in a single burst.

The stable action status set includes `ACCEPTED`, `LOADING`, `NOT_OWNED`,
`CATALOG_MISMATCH`, `ASSET_MISMATCH`, `UNKNOWN_IDENTITY`, class/race/skill
restrictions, `INVALID_TARGET_SLOT`, `DB_UNAVAILABLE`, `RATE_LIMITED`,
`INVALID_REQUEST`, and `UNSUPPORTED`. Transport errors also use stable codes,
including `LOADING`, `DB_UNAVAILABLE`, `RATE_LIMITED`, and replay/version errors.
Exact enum lists live in the schema.

## Reference verification

Run from the SoloCollections repository root:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s tools\collections\tests -p "test_sc2_protocol.py" -v
```

The reference codec is `tools/protocol/sc2_codec.py`. It is specification and
test tooling, not a production network endpoint.
