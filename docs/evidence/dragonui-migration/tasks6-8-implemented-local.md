# Tasks 6–8 implementation evidence — 2026-08-11

Evidence state: `IMPLEMENTED_LOCAL`. The wardrobe draft interaction, shared model presentation service, and mount/pet presenter migration are implemented in source. No real-client deployment, visual acceptance, or server action acceptance was performed.

## Task 6 — wardrobe interaction skeleton

- Added separate `State`, `Slots`, `Sources`, `Outfits`, and `Preview` modules instead of importing the ezCollections XML monolith.
- State owns `equippedBySlot`, `draftBySlot`, `selectedSlot`, `dirtySlots`, and `requestState` for exactly 11 supported slots.
- Candidate rows query `SC.Catalog` directly and never call `C_TransmogCollection` or ezCollections APIs/messages.
- Selecting a candidate changes only the local draft and rebuilds the DressUp preview.
- Closing preserves dirty draft state; switching to current equipment or clearing a draft requires an explicit second confirmation click.
- The selected owned appearance reuses `SC.Bridge.ApplyAppearance`; accepted requests remain `WAITING_STATE` until an SC2 authoritative revision refresh. The client does not synthesize owned/applied state.
- Multi-slot save remains disabled and labels the missing server atomic contract.

## Task 7 — shared model presentation service

- DragonUI_NewEra now exposes Public Model API capabilities for `CREATURE`, `DRESSUP`, and `DISPLAY` presenters.
- One shared lifecycle scheduler owns asynchronous presenter tasks. Every presentation increments a generation token, and stale scheduled work is discarded.
- The existing NewEra control implementation is exposed through `Public.Model:AttachControls`, retaining left-drag rotation, right-drag pan, wheel/button zoom, and reset.
- SoloCollections `ModelProvider` is the only owner of the SoloCam direct display request range; pages no longer emit synthetic display requests.
- `/sc model [creature|dressup|display] newera|legacy` supplies per-provider development A/B and rollback selection.
- Presenter controls are attached only to large models; the 18 wardrobe cards do not receive 18 control-bar watchers.

## Task 8 — mounts and pets

- Mount and pet pages retain `SC.Catalog`, `CollectionState`, `Bridge.SummonMount`, `Bridge.SummonPet`, and `Bridge.RequestCreaturePreview` ownership.
- Both pages use the shared NewEra list/detail/action styling, shared `CREATURE` presenter, and NewEra model controls.
- Mounts now expose an explicit bottom summon action alongside reset and favorite, matching the pet layout.
- Uncollected/custom entries still request the SoloCollections preview provider; failure shows a clear unavailable state instead of assuming NewEra learned-only data.
- The obsolete page-local model timer drivers and direct `SetCreature` loading paths were removed from the production mount/pet pages.

## Targeted checks

- Lua 5.1-compatible parse: `LUA51_PARSE_OK=23` changed Lua files.
- Wardrobe Lab slot definitions: `11`.
- Lab forbidden runtime dependencies (`C_Transmog*`, `SendAddonMessage`, ezCollections): none.
- Direct DragonUI_NewEra internal access from SoloCollections: none.
- Synthetic display request constants outside `Core/ModelProvider.lua`: none.
- Shared presenter scheduler frame count in `DragonUI_NewEra/model`: one.
- Changes to `Core/Bridge.lua` or `Data/Generated`: none.
- Five-root lock inspection and deterministic suite build: passed.
- Directory hashes:
  - DragonUI_NewEra: `28cd1941fa40126c89ff873ef744d0844af180c22ca676bc33aeaea6cc7fb500`
  - SoloCollections addon: `9217aa6d969c61b6f50ba6be9c3d0d59ce1a77b40dac8a7dfb9a4640f480a051`
- DragonUI_NewEra model service commit: `a032220e435d78423e531478739c6aa4dbb8bbfe`.

## Deferred acceptance

The plan prohibits modifying the real client during these implementation batches. Consequently model rendering, rapid switching, drag/pan/zoom/reset, draft interaction, single-slot SC2 action, mount/pet summon behavior, and screenshots remain `CLIENT_RUNTIME_PENDING`, `VISUAL_PENDING`, and where applicable `SERVER_PENDING`.
