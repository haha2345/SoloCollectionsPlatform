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
- Version/build tokens contain 1–64 ASCII letters, digits, `.`, `_`, `~`, or `-`.
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
Y|sessionNonce|requestId|op|slotCount|entries
U|sessionNonce|requestId|status|copper|warningMask
O|sessionNonce|requestId|op|uid|nameHex|entries
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

Type `10` is the authoritative set of account-owned mount collection IDs, and
type `11` is the corresponding authoritative companion set. Internal types
`16` (`mount-favorite`) and `17` (`companion-favorite`) carry favorite
membership using the stable IDs of types 10 and 11 respectively. Types 16 and
17 are internal projections: they are not navigation categories and never
contribute to collection totals or progress.

Internal types `18` (`character-applied`) and `19` (`account-outfit`) are
wardrobe projections. Their `M` mapping hashes are syntax/slot-order hashes,
not the appearance catalog hash. Bit `17` / `18` of `enabledCategoryFlags`
announce them. They use `B/C/E` snapshot replace only; `D` is illegal for
these types because a delta has no slot field.

Type 18 payload is a fixed 14-segment list in `Lab.SLOTS` order:
`HEAD,SHOULDER,BACK,CHEST,SHIRT,TABARD,WRIST,HANDS,WAIST,LEGS,FEET,MAINHAND,OFFHAND,RANGED`.
Empty is `-`, HideVisual is reserved collection ID `2`, otherwise the
appearance collection ID in canonical decimal. Type 13 catalogs must never
assign collection IDs `1–9`.

Type 19 payload is `-` when the account has no outfits, otherwise
`uid:nameHex:slotCsv` rows separated by `;`. `nameHex` is UTF-8 lowercase
hex of a name at most 48 bytes (hex length 2–96). Slot CSV uses the same
14-segment grammar as type 18. The account may store at most 10 outfits.

`Y` is the wardrobe intent. `op` is `QUOTE`, `APPLY`, or `CLEAR`.
`QUOTE`/`APPLY` entries are `slotPlus1:collectionId` comma lists (at most
14 unique equipment slots). HideVisual uses collection ID `2`. `CLEAR`
entries are `slotPlus1` values, or `slotCount=0` and `entries=-` to clear
every applied slot. `U` is the quote result: `copper` is authoritative
(including `0`) and `warningMask` is eight lowercase hex bits. Quote copper
is the sum of each actually changed non-hide slot using
`max(source item sellPrice, 1g) * ScaledCostModifier + CopperCost`. Hide and
clear are `0`. Stable
warning bits are `REPLACES_EXISTING` (`00000001`), `INCLUDES_HIDE`
(`00000002`), and `NO_ITEM_IN_SLOT` (`00000004`). The AddOn localizes
those bits; the server never sends free-form text.

`O` writes account outfits (`SAVE` / `RENAME`). `uid=0` on `SAVE` creates
a new outfit; a non-zero `uid` overwrites that row. `LOAD` is not a wire
action: the AddOn copies a type 19 snapshot into the local draft and then
sends `Y APPLY`. `DELETE` keeps the existing `Q` shape:
`Q|...|19|uid|DELETE|-`.

`Q`/`R` field tables are unchanged. Handbook single-slot APPLY (type 13)
and set APPLY (type 14) stay on `Q`. Wardrobe dirty slots and Ready set
presets use one `Y APPLY`.
Type 14 success must also update the type 18 projection.

New stable statuses include `INSUFFICIENT_FUNDS`, `OUTFIT_LIMIT`,
`OUTFIT_EMPTY`, `COST_CHANGED`, and `NOTHING_EQUIPPED`. Empty-slot APPLY
fails; empty-slot HideVisual is a no-op and may set `NO_ITEM_IN_SLOT`.
`QUOTE` is read-only. `APPLY` revalidates before deducting; a stale quote
or changed copper returns `COST_CHANGED` and the client must quote again.

Old clients that do not advertise wardrobe support in `clientBuild` (the
`-w1` suffix) keep receiving only types 10–17. A server that does not
implement `Y`/`U`/`O` must reject those codes as `UNSUPPORTED` / unknown
message, never as success.

`Q ...|10|collectionId|SET_FAVORITE|1` and
`Q ...|11|collectionId|SET_FAVORITE|1` set favorites; target `0` removes them.
The server validates ownership and the active, visible, actionable catalog
before persisting, then emits an `A` or `R` delta for type 16 or 17. The AddOn
must not update its star optimistically.

`Q ...|10|1|RANDOM_SUMMON|-` and `Q ...|11|1|RANDOM_SUMMON|-` use reserved
control collection ID `1`. The server alone builds the owned, favorite and
currently usable pool; ID `1` is forbidden in both generated catalogs. A
different control ID is `INVALID_REQUEST`.

Client spell `150544` is the persistent native action-bar representation of
the same random-mount operation. Its server SpellScript invokes the same
authoritative random service, carries no client-selected mount identity, and
does not add a new SC2 wire shape. Recasting it while mounted returns the same
successful `DISMISSED` toggle result as the SC2 action.

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
4. Commit is an atomic replacement of that category's payload at
   `baseRevision`. Owned-set types replace the sorted unique ID set. Types 18
   and 19 replace their slot/outfit payload and never update `accountRevision`.
   Deltas arriving during a transfer are queued and then applied in contiguous
   revision order; types 18 and 19 never use `D`.
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

The stable action status set includes `ACCEPTED`, `DISMISSED`, `LOADING`, `NOT_OWNED`,
`FAVORITE_NOT_OWNED`, `NO_MOUNTS`, `NO_USABLE_MOUNTS`, `NO_COMPANIONS`,
`NO_USABLE_COMPANIONS`,
`CATALOG_MISMATCH`, `ASSET_MISMATCH`, `UNKNOWN_IDENTITY`, class/race/skill
restrictions, `INVALID_TARGET_SLOT`, `DB_UNAVAILABLE`, `RATE_LIMITED`,
`INVALID_REQUEST`, `UNSUPPORTED`, `INSUFFICIENT_FUNDS`, `OUTFIT_LIMIT`,
`OUTFIT_EMPTY`, `COST_CHANGED`, and `NOTHING_EQUIPPED`. `DISMISSED` is a successful idempotent
companion toggle result. Mount actions additionally distinguish
`IN_COMBAT`, `DEAD`, `IN_VEHICLE`, `ON_TAXI`, `INDOORS`,
`FLYING_NOT_ALLOWED`, `MAP_RESTRICTED`, `BATTLEGROUND_RESTRICTED`,
`SHAPESHIFT_RESTRICTED`, and `CAST_FAILED`. Transport errors also use stable codes,
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
