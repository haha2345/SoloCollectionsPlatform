# DragonUI migration Task 13 — visual correction baseline

Date: 2026-08-11

State: `IMPLEMENTED_LOCAL`. This record freezes the rejected visual baseline and branch boundary. It does not claim a corrected client build or visual acceptance.

## Git and rollback boundary

- Rejected-but-runnable source commit: `b8b59e92a909a12becbbe85d938425506b61e5e4`.
- Preserved rollback branch: `feat/dragonui-collections-shell`.
- Corrective implementation branch: `feat/ezcollections-ui-rehost`.
- Corrective worktree: project-local F-drive `_work/ezcollections-ui-rehost`; the main checkout was not switched.
- The real client was not modified by Task 13.

## Frozen client evidence

Nine screenshots were copied into the ignored `_work/evidence/ezcollections-ui-rehost` directory: seven page observations plus the two user-selected rejection examples. They are local review evidence and are not public release inputs.

| Evidence | SHA-256 |
| --- | --- |
| `current-mounts.png` | `A97F34D4A762E87D1F7FCBEAEE3910B59DEAD2F0FE3EFAE0755A59C439DBFB0E` |
| `current-pets.png` | `DF09519F90759A15A210C65EB26372613059A4AA786229CC4A804169E66138E5` |
| `current-toys.png` | `E35FEDF6D207D584F844091A4DE3975E10EE64F0A58F6D2AFEAAB5ADD2C9EEEB` |
| `current-wardrobe-items.png` | `69BDBAD2052184CB3DC0FE1D919AF203F7C0AD0E509A4D4452D4F3F2AE50CCFE` |
| `current-wardrobe-sets.png` | `7310E8A57642ED4F1B01221A753A6B9532C1C6DB243DDE9234D8D0349FEE84E2` |
| `current-transmog-lab.png` | `BD54F3E3095AD378A6F079F000CB9DDED4C03CD77C643A9FF037F2E22261E041` |
| `current-titles.png` | `28EFFC8750803243F6061CBFD0BE975EB616DA266EA408863E965439F23A9161` |
| `user-rejected-mounts.png` | `6BB4364966A06615B154549DA0D86C5663B78F45CA3E7DB38BEC7DA44C3636DC` |
| `user-rejected-transmog.png` | `31E91EB6DC152856872725552F2B1B0880CBDAE9AE0A2733FA9EEF7A7696F731` |

## Rejection findings

1. The `920 x 793` canvas and suspended main tabs exceed the visible client area at the observed UI scale.
2. Applying NewEra generic rock/inset/card styling to every inner panel produces a uniform black/brown workspace instead of an ezCollections collection journal.
3. Mounts and pets retain the correct data and model behavior, but their internal geometry and visual hierarchy are not ezCollections-derived.
4. The Transmog Lab is an original three-column prototype; it does not use ezCollections `WardrobeFrame`, `WardrobeTransmogFrame`, slot-button geometry, or the reparented `WardrobeCollectionFrame` browser.
5. Large red bottom buttons, the purple experimental badge, and explanatory paragraphs compete with the collection content.

## Corrective visual contract

| Layer | Owner |
| --- | --- |
| Top-level metal NineSlice, title band, portrait cutout, close button, window persistence | DragonUI_NewEra Public Chrome |
| Collection page geometry, inset panels, lists, cards, tabs, slot buttons, search/filter and paging | ezCollections 2.2 UI master adapted under SoloCollections names |
| Catalog, filtering, ownership projection, draft state and model identities | SoloCollections |
| Authorization, prices, revision, persistence and action result | mod-solo-collections C++ / SC2 |

The target collection journal is `703 x 606`. The target transmog workbench is `965 x 606`, composed of the ezCollections 300px transmog/model region and 662px collection browser. The existing eleven-slot boundary remains unchanged.
