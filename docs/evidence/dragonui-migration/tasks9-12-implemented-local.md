# DragonUI migration Tasks 9-12 — IMPLEMENTED_LOCAL

Date: 2026-08-11

This record is source/build evidence only. No files were copied to a real WoW client, and no claim is made for `CLIENT_RUNTIME_OBSERVED`, `VISUAL_ACCEPTED`, `SERVER_ACCEPTED`, or `RELEASED`.

## Task 9 — wardrobe item page

- [x] Split production responsibilities into `UI/Wardrobe/Layout.lua`, `ItemPresenter.lua`, `Filters.lua`, and `CameraWorkbench.lua`.
- [x] Kept the fixed 3 x 6 card pool and the eleven HEAD through OFFHAND slot filters.
- [x] BODY cards use the generation-safe DRESSUP presenter; standalone MAINHAND/OFFHAND records retain the DISPLAY presenter and explicit unavailable fallback.
- [x] Added workbench A/B selection between the stock/NewEra SetPosition baseline and the existing generated body profile/SoloCam route.
- [x] Preserved item-page retry/invalidation, page generations, workbench JSONL export, camera identity `(raceId, sex, slot)`, and `appearance > model > weaponFamily > autoCamera` precedence.
- [x] Kept authoritative ownership in CollectionState and the existing single-slot Bridge.ApplyAppearance action.

## Task 10 — wardrobe set page

- [x] Applied shared NewEra panel, row, scrollbar, button, and ItemButton styling.
- [x] Replaced the local set TryOn loop with the DRESSUP presenter using two settle ticks, Undress, ordered items, and generation cancellation.
- [x] Kept deterministic piece order, class filtering, collection progress, scrolling/paging, variantOrdinal, and Bridge.ApplySet semantics.
- [x] Switching to items, hiding the page, or changing the player invalidates the previous set presenter generation.

## Task 11 — toys and titles

- [x] Retained the fixed eighteen-toy object pool and pagination while applying the shared NewEra card/panel skin.
- [x] Retained toy Use, drag-to-action-bar macro, right-click, and favorite behavior.
- [x] Styled the title panel and rows through the same layout source while retaining current-title and authoritative ownership text.
- [x] Removed the unreferenced 289-line legacy `UI.CreateCompanionPageBase` implementation; production mounts and pets keep their shared NewEra helpers.

## Task 12 — integrated delivery

- [x] SoloCollections public release builder retains `project-authored-files-only` media and can optionally emit a separate full client UI archive using `--client-suite-root` plus `--suite-lock`.
- [x] SoloClientSuite now produces a one-install `Interface/AddOns` ZIP and a JSON manifest containing the suite lock, every file SHA-256, and the archive SHA-256.
- [x] README, architecture, asset, and third-party documents distinguish public SoloCollections source from the locally authorized integrated UI delivery.
- [x] The suite lock records pinned upstream commits, TOC versions, project patch state, and deterministic AddOn directory hashes.
- [x] No real-client directory was modified.

## Source and package evidence

- SoloCollections implementation commit: `0e92ed2c163d8116671dd2a271c1971d34c95181` (`feat/dragonui-collections-shell`).
- SoloClientSuite implementation commit: `ef2f79e9a6de3a9866cfba98a720a0dfc6718401` (`feat/bootstrap-ui-platform`).
- DragonUI_NewEra directory SHA-256 tree hash: `3bb269eff8b47a2b2b884f7c5124a44ac92caec6967c08ad8013a830ba1dd8ac`.
- SoloCollections AddOn directory SHA-256 tree hash: `9438bafbfa5600f54c883525f8da0defd60d50f66f3acc287eb04e75f4ca6c3a`.
- Integrated archive: `SoloClientSuite/build/packages/SoloClientSuite-dragonui-migration-local-20260811-r2-integrated-ui.zip`.
- Archive SHA-256: `246213551734976cdc0e1a4857b21395e7d9bef1b572aec73aa6d9625aba3f0a`.
- Archive inspection: 1,902 files, five AddOn roots, five root TOCs, 1,065 BLP files; manifest file count 1,902 and archive hash match `true`.
- Targeted Lua 5.1 parse: all 38 SoloCollections AddOn Lua files parsed successfully with `luaparse 0.3.1`.
- `Inspect-ClientSuiteLayout.ps1 -VerifyLock`: passed for source and built AddOns trees.
- `python -m py_compile tools/release/build_unified_release.py`: passed.
- PowerShell parser for `tools/Package-ClientSuite.ps1`: no parse errors.
