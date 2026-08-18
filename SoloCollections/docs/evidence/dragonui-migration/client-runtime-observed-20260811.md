# DragonUI migration client smoke test — CLIENT_RUNTIME_OBSERVED

Date: 2026-08-11

This is a real-client smoke-test record. It advances the seven collection pages to `CLIENT_RUNTIME_OBSERVED`, but does not claim `VISUAL_ACCEPTED`, `SERVER_ACCEPTED`, or `RELEASED`.

## Deployment and rollback

- [x] Closed the previously running client before replacing AddOn roots.
- [x] Created an intact rollback archive before deployment:
  `F:\1_projects\wow_projects\_backups\DragonUI_Collections_Migration_20260811\client-runtime-test\AddOns-before-dragonui-runtime-test-20260811-1621.tar`
- [x] Rollback archive size: `1,892,426,240` bytes.
- [x] Rollback archive SHA-256: `86F3338DEADE1DD391F385EF278C9FF3E7CE48202AFF55D893E2F5D0226DF415`.
- [x] Deployed exactly five roots: `!!!ClassicAPI`, `DragonUI`, `DragonUI_Options`, `DragonUI_NewEra`, and `SoloCollections`.
- [x] Verified deployed directory hashes against the suite lock:
  - `!!!ClassicAPI`: `7a0d42527efbe47c27a2ee789a9c29a0a8ee61e96ea7395ded27520dff047c10`
  - `DragonUI`: `ce2c28c9bbe7e21be17fec45efb9d5b1a9936240e15256a6879dac3660f2fb1c`
  - `DragonUI_Options`: `f3e96465b67183b44e3811192b0c0369bad24dd5fc886d5f3b35382ea202181e`
  - `DragonUI_NewEra`: `3bb269eff8b47a2b2b884f7c5124a44ac92caec6967c08ad8013a830ba1dd8ac`
  - `SoloCollections`: `9438bafbfa5600f54c883525f8da0defd60d50f66f3acc287eb04e75f4ca6c3a`

## Runtime observations

- [x] Launched through `Start-WowLogin.ps1`, authenticated, selected the character, and entered the world.
- [x] `/sc` opened the migrated collection shell.
- [x] Mounts: authoritative count/list, selection, NewEra controls, and 3D mount model rendered.
- [x] Pets: authoritative count/list, selection, NewEra controls, and 3D pet model rendered.
- [x] Toys: fixed three-column catalog cards and progress rendered.
- [x] Wardrobe items: eleven slot filters and the fixed 3 x 6 model-card pool rendered.
- [x] Wardrobe sets: set list, progress, piece buttons, and full DRESSUP model rendered.
- [x] Titles: authoritative catalog and availability wording rendered.
- [x] Transmog Lab: explicit experimental/local-preview wording, eleven-slot draft, candidate sources, and player model rendered.
- [x] `/reload` completed; reopening `/sc` restored the last Pets page and rendered its list, count, detail, controls, and model again.

Screenshots were retained only as local test artifacts under `F:\1_projects\wow_projects\_tmp`; they are not public release inputs.

## Acceptance boundaries and observed defect

- [ ] `VISUAL_ACCEPTED`: not reached. At the tested resolution/UI Scale, the collection frame extends below the viewport. `/sc reset` and repositioning do not expose the bottom tab strip, so page navigation is partially cropped.
- [ ] `SERVER_ACCEPTED`: not exercised. No summon, use, favorite, apply appearance, apply set, or transmog commit action was sent, avoiding unintended account/character state changes.
- [ ] `RELEASED`: not claimed.

One pre-existing FrameXML error was visible with timestamp 16:28:47:

`Interface\FrameXML\Localization.lua:34: attempt to index field '?' (a nil value)`

Its stack is rooted in `LocalizeFrames` / `UIParent.lua`, it occurred before opening `/sc`, and it contains no SoloCollections or DragonUI frame. No migration-specific Lua error was observed while switching collection pages or after `/reload`.
