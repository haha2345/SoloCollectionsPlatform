# Task 17 — ezCollections toy and title pages

**Status:** `IMPLEMENTED_LOCAL` on 2026-08-11. The real client was not modified in this task.

## Toy Box structure

The Toy Box now uses the geometry and media contract from the locked ezCollections 2.2 `Blizzard_ToyBox` page:

- one full journal inset from `(4, -60)` to `(-6, 5)` with the imported marble, frame and shadow media;
- 18 visible entries arranged as 3 columns by 6 rows;
- 50×50 collection buttons starting at `(40, -53)`, with 208px column and 66px row steps;
- 42×42 cropped icons, `WhiteIconFrame` collected/selected states, the upstream `Collections.tga` favorite overlay and an 18% uncollected icon alpha;
- 115px search plus 93px silver filter at the upstream top-right position;
- 32px spellbook previous/next page buttons and mouse-wheel paging.

The former responsive brown card layout and NewEra inner black frame are no longer part of the Toy Box.

## Title page structure

ezCollections has no title journal page, so the page was built from the same CollectionsJournal primitives used by its companion lists:

- one full journal marble inset and four-sided shadow overlay;
- ten 46px `ListButtons.tga` rows with normal and hover atlas states;
- a `FauxScrollFrameTemplate` scrollbar with wheel scrolling;
- the same top-right search/filter geometry as the Toy Box;
- the existing read-only note retained at the bottom of the inset.

## Preserved behavior

Presentation and visible-row geometry changed while the existing product paths remain intact:

- toy left-click still calls `Bridge.UseToy`;
- collected toys still create/reuse the `/sc toy` macro and use `PickupMacro` for action-bar drag;
- right-click favorite state still uses `Catalog.ToggleDemoFavorite`;
- toy filtering, paging and progress still use `Catalog`;
- title ownership still resolves through `CollectionState.ResolveOwned` and the page still does not grant or activate titles.

## Revision and build evidence

- SoloCollections implementation commit: `b812532f6223120e804a259f5a572345c83bab03`.
- SoloClientSuite lock commit: `b60ee262e8c4825423426694c676803dd91a8c6f`.
- Locked SoloCollections directory hash: `b520f1db7bbcb19398e65a250fa745cb0f18d4619dfbf8eaae0361722fe3f779`.
- Locked ezCollections source-tree hash: `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`.
- Locked media projection hash: `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53` (222 files).

`git diff --check` and the targeted source-contract scan passed. The parameterized six-AddOn local build completed with the updated suite lock and revalidated the ezCollections source/media hashes.

This is source/build evidence only. Card spacing, hit regions, scroll clipping, tooltip layering, page-wheel direction and the title status column still require the Task 20 real-client pass before `VISUAL_ACCEPTED` or `REAL_CLIENT_ACCEPTED` can be claimed.
