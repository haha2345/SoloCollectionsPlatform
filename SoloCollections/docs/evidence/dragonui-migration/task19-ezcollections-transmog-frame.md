# Task 19 — ezCollections WardrobeFrame transmog page

**Status:** `IMPLEMENTED_LOCAL` on 2026-08-11. The real client was not modified in this task.

## Replaced page structure

The corrective branch's custom “outfit / character / source” three-column workbench and purple experiment badge were removed. The 965×606 page now follows the locked ezCollections 2.2 `WardrobeFrame` and `WardrobeTransmogFrame` split:

- a 300×495 left transmog frame anchored at `(4, -86)`;
- a 294×488 DRESSUP model over the imported race-specific `TransmogBackground*.tga` surface;
- a 662×606 WardrobeCollectionFrame-style browser anchored to the top-right;
- item/set tabs at the right frame's upstream top-left position and the shared search/filter pair at the window's top-right position;
- no legacy corrective-branch inset host or three-column headings remain.

## Eleven-slot transmog model

All eleven SoloCollections equipment slots are now 43×43 buttons arranged around the character model using the ezCollections transmog composition:

- head, shoulder, back, chest and wrist on the left;
- hands, waist, legs and feet on the right;
- main hand and off hand at the bottom;
- exact `Transmogrify.tga` frame, selected, pink-status and highlighted atlas regions;
- exact `Textures.tga` pending glow and revert icon regions;
- current equipment icons, selected-slot state, local-draft state and right-click rollback are independent layers.

Selecting a slot automatically returns the right browser to item mode and filters `Catalog.Query("APPEARANCES")` to that slot.

## Item and set candidate browser

The former nine-row text source list was replaced by the same model-card contracts used by the collection wardrobe:

- item mode shows 18 cards in a 3×6 grid at the ezCollections WardrobeTransmog geometry;
- item cards reuse the production `ItemCardRenderer`, retaining BODY and standalone DISPLAY routing, M2 camera profiles, unavailable fallbacks and generation checks;
- set mode shows eight 129×186 DRESSUP cards in a 2×4 grid using `TransmogSetsVendor.tga` chrome;
- both modes use exact collected, uncollected, selected, hover and favorite media, page buttons and mouse-wheel paging;
- global search and collection filters continue to query SoloCollections Catalog and CollectionState rather than ezCollections runtime data.

## Draft and authoritative action layers

The state model now distinguishes two mutually exclusive local preview types:

1. a per-slot appearance draft, applied only through `Bridge.ApplyAppearance` for the selected equipment slot;
2. a complete set preset, applied only through `Bridge.ApplySet` with its selected variant ordinal.

Both paths carry a request token, enter `REQUESTING`, wait in `WAITING_STATE`, and clear their relevant local draft only after the CollectionState revision changes. Uncollected records can be previewed but cannot be applied. The imported revert button retains the two-click clear confirmation, closing the page preserves unapplied local state, and stale callbacks cannot overwrite a newer draft.

The visible “保存整套（待原子协议）” control remains disabled. Task 19 did not invent a multi-slot custom-save request or reuse the set contract for a different payload.

## Revision and build evidence

- SoloCollections implementation commit: `982ef1766a800532f84727b7d907368b21727eec`.
- SoloClientSuite lock commit: `ece4d7a3ca3812983ed8a8b07fd5ae0b5a9918d2`.
- Locked SoloCollections directory hash: `b5a4a7cef4052ee575e88e2d7de3580e25d7f811e7e0b43213ccabeeb5538697`.
- Locked ezCollections source-tree hash: `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`.
- Locked media projection hash: `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53` (222 files).

`git diff --check` passed. All ten modified Lua files compile with the local Lua 5.1 validator. The source scan confirmed eleven slot definitions, the 300/662 width split, 18/8 candidate pools, both Bridge action routes and the disabled custom-save label. The parameterized six-AddOn local build completed with the updated suite lock.

This is source/build evidence only. Race background selection, slot hit regions, model camera quality, card strata, tab/search overlap, draft rollback and 965/703 width switching still require the Task 20 real-client pass before `VISUAL_ACCEPTED` or `REAL_CLIENT_ACCEPTED` can be claimed.
