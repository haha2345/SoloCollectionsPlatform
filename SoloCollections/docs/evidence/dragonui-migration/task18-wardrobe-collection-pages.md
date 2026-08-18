# Task 18 — ezCollections wardrobe collection pages

**Status:** `IMPLEMENTED_LOCAL` on 2026-08-11. The real client was not modified in this task.

## Wardrobe journal structure

The wardrobe collection now occupies the full 703×606 journal body rather than the corrective branch's legacy inset. Its page shell follows the locked ezCollections 2.2 `WardrobeCollectionFrame` contract:

- native `OptionsFrameTabButtonTemplate` item/set tabs overlap the journal title edge at the upstream top-left position;
- the shared 115px search and 93px silver filter controls use the top-right CollectionsJournal position;
- item and set modes each use one full ezCollections marble inset and shadow overlay;
- armor, class, weapon and eleven slot controls remain in the inset header and the slot glyphs come from the imported `Transmogrify.tga` atlas;
- previous/next controls and mouse-wheel input move by one whole visible page.

## Appearance item gallery

The item page now mirrors the ezCollections Wardrobe item geometry:

- 18 visible model cards arranged as 3 rows by 6 columns;
- each card is 78×104, starting at `(70, -85)` with 16px horizontal and 24px vertical gaps;
- collected, uncollected, selected, hover and favorite chrome use exact regions from imported `Transmogrify.tga` and `Collections.tga` media;
- the former brown captions and collection badges are hidden so model and atlas state own the card surface;
- opening the in-window camera workbench retains its existing 12-card, four-column layout and selection-preserving pagination.

## Set gallery and detail strip

The set page replaces the prior large-preview/list composition with the selected ezCollections set-card structure:

- eight visible 129×186 DRESSUP cards arranged as 2 rows by 4 columns;
- collected, uncollected, selected and hover chrome use exact `TransmogSetsVendor.tga` atlas regions;
- the selected set name, progress and apply action remain in a bottom detail strip sourced from `TransmogSets.tga`;
- left click selects, Shift+left click applies a collected set, right click toggles favorite, and wheel input moves by eight records;
- presenter callbacks are guarded by both card generation and record identity, and replaced cards clear their presenter before accepting a new record.

## Preserved product semantics

The visual and layout layer changed without replacing the SoloCollections ownership or action routes:

- all eleven equipment-slot filters remain available;
- standalone displays still use the `DISPLAY` presenter path and set cards use `DRESSUP`;
- appearance application still calls `Bridge.ApplyAppearance` with the resolved equipment slot;
- set application still calls `Bridge.ApplySet` with the selected variant ordinal;
- `Catalog`, `CollectionState`, server-provided collected state, item/set generations and the M2 camera workbench remain authoritative;
- no multi-slot custom-save contract was introduced.

## Revision and build evidence

- SoloCollections implementation commit: `1c5f4d1a651c84fce36b6f92df99defe761b6172`.
- SoloClientSuite lock commit: `44571ba70bfb99b71e121bdd838950dc283f63b9`.
- Locked SoloCollections directory hash: `de061377ed276cccde52e4142b3709cdce10b2f4862af2ae50f21efef50ccc66`.
- Locked ezCollections source-tree hash: `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`.
- Locked media projection hash: `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53` (222 files).

`git diff --check` passed. The four modified Lua files compile with the local Lua 5.1 validator; that check also caught and removed a WotLK upvalue-limit violation before the implementation commit. The parameterized six-AddOn local build completed with the updated suite lock and revalidated the source and media hashes.

This is source/build evidence only. Atlas alignment, frame strata, model crop quality, hit regions, tab overlap and both paging directions still require the Task 20 real-client pass before `VISUAL_ACCEPTED` or `REAL_CLIENT_ACCEPTED` can be claimed.
