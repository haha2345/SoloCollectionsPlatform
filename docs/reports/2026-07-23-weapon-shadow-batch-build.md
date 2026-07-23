# Stage 7 — weapon batch build and runtime-safety gate

Status: complete. This stage builds and verifies deployable client assets only;
it does not switch the production `appearance_presentations.json` projection.

## Runtime safety correction

Stage 6 proved that appearance `217059` (item `46017`, model `5048`, synthetic
display `42884`) was structurally complete. The Stage 7 isolated real-client
audit proved that its transformed M2 instead triggers WoW 3.3.5 `ERROR #132`
(`ACCESS_VIOLATION`) when it is loaded through the direct-display bridge. The
same client and audit route accepted the immediately preceding `5047` record.

The source shadow review is immutable. A separate runtime projection therefore
changes only this record to `UNAVAILABLE / CLIENT_RUNTIME_CRASH_132`, retains
its source identity and moves its allocated model/display IDs to a permanent
registry tombstone. The ID pair cannot be recycled.

| Runtime projection value | Result |
| --- | --- |
| Quarantine policy hash | `51ed10427db34e36a85582929267fcab9b58d9e564d0255b990e73674173d772` |
| Runtime projection hash | `0cdf53e9b500d6def07fa97dea513543a90bbfed1dc671401b6641ca37f198fe` |
| Runtime registry hash | `c4969969b36daead6b8ae124aa7cb40bf19da76ead30892bd8bf90d14a4d50f9` |
| Public terminal state | `3,541 READY + 149 UNAVAILABLE = 3,690` |
| Tombstone | `217059 / 5048 / 42884 / CLIENT_RUNTIME_CRASH_132` |

The signed client crash text and dump are named members of the quarantine
policy, under evidence root
`round3-weapon-bundles-20260723/client-runtime-audit/stage7-shadow-audit-isolate-r8-3319/`.
Their SHA-256 values are checked before the projection can be rebuilt.

## Deterministic batches and aggregate MPQs

All stages consume the fixed Stage 6 evidence input hash
`be8a520c2b59aba96cf3f2c8bf75c362bddd2bf05a4580a411d9557cd55041a6`.
Each stage was built atomically, passed `weapon_bundle.py check`, and was then
rebuilt in a separate output directory with the identical manifest hash.

| Batch | Presentations | Models | Displays | Files | Stage manifest hash | MPQ pack hash |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| 1 | 56 | 50 | 56 | 164 | `a5d5fdecd400a2f77fe883630301848c3c24cd44db709e6ffb0a7f00ea5fa00d` | `9e40559ab2debe3d800aeed12caf0bd06086cd9c37a3674eaa32986703beab4f` |
| 2 | 250 | 59 | 203 | 329 | `481becd22b7beded6dbb631d720ac0e3a7c06fdb794556bd7c7bac443cebaea2` | `1ad700979458c39ecfd58e9e415e9f6e2739b3b24b3a5365251876e0d3c7637a` |
| 3 | 3,542 | 1,139 | 3,107 | 5,805 | `de61f221552df12d36525c0732e775e58693fac8292d905b78d9b83fb682ee43` | `1873a6e6547fdbdc12d86e63b998fd83962322c42d3ef727b341f02f6cd21258` |

Batch 1 and 2 contain exactly the same presentation rows and output file
hashes as their already accepted pre-quarantine `v3` runs: the unsafe
appearance is absent from both selections. Batch 3 removes its M2, SKIN,
display BLP, generated DBC rows, and all references while retaining its ID as
a tombstone.

The full stage contains 21 reserved baseline entries and 3,521 active runtime
safe entries. Its de-duplicated outputs are 1,139 M2s, 1,139 SKINs, 3,107
display textures, 418 hard-coded M2 texture dependencies, 21 preserved
baseline textures, and two appended DBC files. Every MPQ was reopened and
every declared member re-extracted and SHA-256 checked (164, 329, and 5,805
members respectively).

## Client deployment and full audit

The aggregate Batch 3 package was installed into the dedicated test targets
`Data/Patch-Y.MPQ` and `Data/zhCN/patch-zhCN-z.MPQ` with an owned-target
install manifest. Both archive hashes were checked before and after copy, then
the exact installation manifest restored both targets to their prior absent
state. No production patch was overwritten.

The real 3.3.5 client then completed the single full audit run:

| Check | Result |
| --- | --- |
| Bundle | `stage7-weapon-batch3-v4-runtime-safe` |
| Projection rows | 3,542 |
| READY / failed | `3,542 / 0` |
| Unique synthetic displays | 3,107 |
| Saved audit CSV SHA-256 | `4a62d0809406bfe93e0b0dd1802d28662aa543d5f2623c8cbb2136587cd01efd` |
| Aggregate CSV SHA-256 | `75dc5e41da5ff5c83686f930ecb00a58503fb90bcac6cbc905e6062fdfb3e10f` |

The complete screen is recorded as
`client-runtime-audit/stage7-shadow-audit-20260723-095907-583/live-complete-3542-ready.jpg`
(SHA-256 `83d846cb0e0a7156ae9a767e8849fbd44b7bb9124960e79918a144b4b18f3f86`).
The adjacent JSON/CSV artifacts bind it to the stage manifest and run ID.

## Offline and native checks

- `weapon_shadow.py runtime-check` regenerated the same runtime projection
  from its frozen base review, quarantine policy, and hashed crash evidence.
- `weapon_bundle.py check` verified output closure, append-only DBC IDs,
  generated DBC row presence, bridge request range, output hashes, and the
  absence of unmanifested files for every original and replay stage.
- `tools/collections/tests/test_weapon_shadow.py` passed 12 tests, including
  runtime tombstone, bounded-slice, and audit identity regressions.
- The x86 SoloCam build completed all C++ bridge tests. The supported stock
  `Wow.exe` address and M2 parser tests passed (14 tests), and the x86
  `LoadLibraryExW` probe accepted the rebuilt DLL
  (`AAD29F164CEE6AC9C4833E5B2E31471E36426E66388A030ECA07E240010559F9`).

The temporary audit runner now records `bundleId` for new runs, remains able to
export early run metadata that only named the validated stage, and asks its
temporary AddOn to logout only after a completed audit so SavedVariables can
be flushed without a timeout loop.

## Stage 8 boundary

No production presentation, generated catalog, permanent AddOn data, or
client MPQ remains installed after this stage. Stage 8 must consume the
runtime-safe review projection, render all 3,690 public records as either
`STANDALONE` or explicit `UNAVAILABLE`, and validate the large-catalog AddOn
path.
