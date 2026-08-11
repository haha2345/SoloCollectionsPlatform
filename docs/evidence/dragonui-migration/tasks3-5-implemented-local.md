# Tasks 3–5 implementation evidence — 2026-08-11

Evidence state: `IMPLEMENTED_LOCAL`. The platform adapter, DragonUI journal shell, and experimental Transmog Lab empty page are implemented in source. This is not real-client, runtime, visual, or server acceptance evidence.

## Implemented scope

- Task 3: SoloCollections now requires DragonUI_NewEra, checks Public API v1 capabilities before creating UI, registers through `Public.Modules:RegisterFeature`, delegates existing `UI.Create*` facades to public components, and migrates the journal position once into DragonUI_NewEra persistence.
- Task 4: the existing 920×793 journal keeps its production pages and business routing while using the NewEra PortraitFrame chrome, shared search/filter/progress/count controls, and six fitting bottom tabs. `/sc shell legacy|dragonui` remains the local rollback switch; `DRAGONUI` is the default.
- Task 5: the development build exposes a separate `TRANSMOG_LAB` tab with an experimental badge, capability text, a three-column empty layout, and exactly 11 slot placeholders. Stable builds default the feature flag off when their TOC build-channel metadata is `stable`.

## Targeted checks

- Lua 5.1-compatible parse (`luaparse`, default Lua 5.1 mode): `LUA51_PARSE_OK=12`.
- Five-root suite lock inspection: passed for `!!!ClassicAPI`, `DragonUI`, `DragonUI_Options`, `DragonUI_NewEra`, and `SoloCollections`.
- Deterministic directory hashes:
  - DragonUI_NewEra: `29744054735998f390fdc9e7716e2fd473fa2f9b8b1969c8cd83ef98803c90fa`
  - SoloCollections addon: `5b29eae7de05ab61b240288f438bae9201fe673d24834bd604bb394be4fc6140`
- Suite build completed at the ignored local output `SoloClientSuite/build/Interface/AddOns` and passed the lock inspection again.
- Direct access from SoloCollections to DragonUI_NewEra internals: none; use is confined to `DragonUI_NewEra.Public`.
- New runtime authority calls in `UI/WardrobeLab`: none (`SC.Bridge`, `SendAddonMessage`, and `C_TransmogCollection.*`).
- Changes to `Core/Bridge.lua` or `Data/Generated`: none.
- DragonUI_NewEra public extension commit: `d87b89c83e3f3802c87a8bd01b4bd3da45a24931`.

## Deferred acceptance

No addon files were copied into the real client and no login was performed for this batch. Screenshots at 1920×1080/lower resolution, UI Scale checks, drag/reopen/reload persistence, five-page behavior parity, and interactive Transmog Lab switching remain `RUNTIME_PENDING` / `VISUAL_PENDING` until a later deployment-and-client-observation task.
