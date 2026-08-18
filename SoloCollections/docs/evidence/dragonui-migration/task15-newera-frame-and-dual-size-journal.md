# Task 15 — NewEra outer frame and dual-size journal

**Status:** `IMPLEMENTED_LOCAL` on 2026-08-11. This task changed source and the ignored SoloClientSuite build only; it did not deploy to the real client.

## Visual ownership implemented

DragonUI_NewEra now owns only the top-level journal chrome:

- outer NineSlice and title band;
- portrait and close button;
- drag, persisted position, migration and screen clamping;
- the existing model-presenter API, which is behavioral rather than page chrome.

The journal body, main tabs, search/filter controls, progress/count controls, page insets, page buttons and scrollbars no longer call DragonUI_NewEra `Theme` or `Components`. The former `components.*` capability requirements were removed from `Core/UIPlatform.lua`. Compatibility hook names remain so existing page presenters do not need data-layer changes, but those hooks no longer apply NewEra textures or component skins.

## ezCollections journal shell

`UI/EzCollections/Templates.lua` provides a namespaced local adaptation of the locked ezCollections 2.2 journal shell:

- tiled `Interface/Collections/CollectionsBackgroundTile.tga` body canvas beneath the NewEra outer border;
- native 3.3.5 `CharacterFrameTabButtonTemplate` tabs;
- first-tab anchor `(11, 2)`, normal `-16px` overlaps and the ezCollections final-tab cutoff spacing;
- `UI-Character-ActiveTabCutoff.tga` selected-tab media for mounts, pets and transmog;
- ezCollections mount/wardrobe portrait media with stock-client pet, toy and title fallbacks;
- opaque fail-closed content overlay when the generated asset AddOn is absent or its locked hashes do not match.

The main-tab order is now mounts, pets, toys, titles, wardrobe and transmog. The title page occupies the upstream heirloom slot because ezCollections 2.2 has no title journal.

## Size contract

`UI.SetMainTab` applies the size before page refresh:

| Active page | Width | Height |
| --- | ---: | ---: |
| Mounts, pets, toys, titles, wardrobe | 703 | 606 |
| Transmog | 965 | 606 |

The tab labels have bounded 70–142px widths. At the 703px collection width, the six Chinese labels plus the ezCollections overlaps occupy less than the available width, so the tab strip remains within the outer frame geometry. The body tiling coordinates and tab anchors are recomputed whenever the width changes.

## Revision and build evidence

- SoloCollections implementation commit: `ad5215b642548b8942e6b098428835137f7eee5a`.
- SoloClientSuite lock commit: `21e6515ef2cb6c34502319bb38ef8a8c13dfee51`.
- Locked SoloCollections directory hash: `04594bc381652e85a44643b3de656051786245b610b775bb871786a533cfcd60`.
- Locked ezCollections source-tree hash: `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`.
- Locked 222-file media projection hash: `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53`.

The parameterized SoloClientSuite build completed and revalidated five checked-in roots plus the generated `SoloCollections_EzUI` root. `git diff --check` passed, the TOC loads `Core/EzCollectionsUI.lua` before `UI/EzCollections/Templates.lua` and the generic UI templates, and a targeted source scan found no remaining NewEra `Theme`/`Components` page-skin calls.

This evidence covers the shell contract only. Page-specific ezCollections geometry remains Tasks 16–19, and real-client rendering/interaction acceptance remains Task 20.
