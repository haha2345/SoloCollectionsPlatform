# Task 16 — ezCollections mount and pet pages

**Status:** `IMPLEMENTED_LOCAL` on 2026-08-11. The real client was not modified in this task.

## Page structure copied and adapted

The mount and pet pages now follow the locked ezCollections 2.2 `Blizzard_MountCollection` and `Blizzard_PetCollection` page tree instead of the former NewEra two-card layout:

| Region | Implemented geometry |
| --- | --- |
| Left inset | 260px wide; top-left `(4, -60)`; bottom-left `(4, 26)` |
| Right inset | top-right `(-6, -60)`; bottom-left 20px right of the left inset |
| Search | 145×20 at the upstream absolute position derived from the left inset |
| Filter | 93×22, 2px after search |
| List row | 208×46, upstream 44px row offset represented by a 47px page offset and a -42px icon offset |
| Model region | starts 160px below the right display header and preserves a bottom action/control strip |

Both pages use the imported ezCollections media for marble insets, `UI-Frame` inner borders, `ListButtons` normal/highlight/selected states, `FavoritesIcon`, `WhiteIconFrame`, `MountJournal-BG`, four-sided shadow overlays, silver filter chrome and native rotation controls. The previous brown/black NewEra inner panels and wide list rows are no longer used.

The global journal controls were moved to the upstream mount/pet coordinates. A full-frame host is used by migrated pages; a temporary legacy host keeps Tasks 17–19 isolated until their own migrations.

## Preserved behavior

Only presentation and visible-row geometry changed. The following remain on their existing SoloCollections ownership paths:

- `Catalog.QueryAll` search/filter results and progress counts;
- `CollectionState` authoritative ownership projection;
- selected record, favorite state and right-click menu behavior;
- `Bridge.SummonMount`, `Bridge.SummonPet` and preview requests;
- generation checks that discard stale model callbacks;
- existing drag-to-rotate, wheel zoom, presenter reset and unavailable states.

The added ezCollections rotation buttons operate on the same model frame and do not replace the presenter or preview protocol.

## Revision and build evidence

- SoloCollections implementation commit: `9cd92a4d7bcb13ca538dd3efb2d39d4ffacba57b`.
- SoloClientSuite lock commit: `c3bc1695c9de77f14aec5d8955ec82d7d8c74c35`.
- Locked SoloCollections directory hash: `5dc94cd2079c0923daaf9e2233ebfc0345e6bf1828e0a113e1a80c8a843768bc`.
- Locked ezCollections source-tree hash: `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`.
- Locked media projection hash: `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53` (222 files).

`git diff --check` passed. A targeted scan found no old 342px companion columns, 50px companion rows, or NewEra inner `Theme`/`Components` calls. The parameterized six-AddOn local build completed and revalidated the suite and media hashes.

This is source/build evidence. Model rendering, list clipping, action controls and click regions still require the Task 20 real-client pass before `VISUAL_ACCEPTED` or `REAL_CLIENT_ACCEPTED` can be claimed.
