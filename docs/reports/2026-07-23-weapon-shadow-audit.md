# Stage 6 — weapon resource shadow audit

Status: complete for the non-production shadow gate. No production
appearance_presentations.json projection, client DBC, MPQ, AddOn asset, or
client installation was changed.

## Frozen inputs

- Named evidence root:
  F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-shadow-20260723-stage6-stormbatch
- Input hash:
  be8a520c2b59aba96cf3f2c8bf75c362bddd2bf05a4580a411d9557cd55041a6
- Fixed client DBC evidence was copied and SHA-256 checked from the Stage 0
  fixed-input pack. The captured set includes Item.dbc, ItemDisplayInfo.dbc,
  and the related DBC evidence.
- The sanitized world item_template snapshot includes entry, class, subclass,
  displayId, InventoryType, quality, and ItemLevel. Every selected row was
  cross-checked against the canonical appearance visibility evidence before it
  was accepted.
- Eleven current-client MPQs were listed and hashed. The evidence root stores
  only their manifests, request lists, parsed facts, and the externally held
  source cache; no client asset body is committed to this repository.

## Results

| Measure | Result |
| --- | ---: |
| All canonical main/offhand appearances | 5,957 |
| Public denominator | 3,690 |
| Public terminal READY | 3,542 |
| Public terminal UNAVAILABLE | 148 |
| Non-public terminal rows | 2,267 |
| Immutable current presentations imported | 21 |
| Newly allocated public appearances | 3,522 |
| Unique new geometry groups | 1,119 |
| Unique new display rows | 3,087 |
| Geometry reuses | 2,403 |
| Display reuses | 435 |
| Estimated unique referenced source assets | 4,693 / 128,664,773 bytes |

The 21 current entries retain their exact source item, model ID, synthetic
display ID, verified transformed-asset hashes, and pose evidence. One legacy
entry is non-public in the current visibility review; it remains an immutable
reserved registry entry rather than being silently removed. A current verified
presentation whose raw expansion source has an unresolved texture remains
INHERITED_VERIFIED; its source-asset fact is still reported separately.

Public terminal failures are explicit: 146 unresolved M2 texture references,
two missing/invalid display textures, and two missing texture assets. Including
the inherited current presentation's raw-source finding, the raw-source
texture-reference count is 147. These rows stay unavailable for Stage 7 until
their source paths are resolved; they are not candidates for batch deployment.

## Parsing, routing, and camera baseline

- ItemDisplayInfo records preserve left/right models, textures, inventory side,
  inventory icon, geoset/visual/effect fields, and source display ID.
- Main hand, offhand weapon, shield, held-in-offhand, and ranged paths are
  routed separately. An offhand falls back to the complete left pair only when
  the DBC has no complete right pair; that decision is stored in the shadow
  plan.
- Each resolved source has an M2, its 00.skin, the display BLP, parsed M2
  texture descriptors, replaceable-texture lookup, SHA-256, byte size, and
  camera layout. The 5,740 parseable WotLK item M2s in this input are
  CAMERALESS; this is recorded instead of blindly appending camera 0.
- geometryKey, textureKey, displayKey, and modelSignature are stable
  content-derived keys. New model/display IDs append after the immutable
  4000–4020 / 40000–40020 reserve. Registry replay is byte-for-byte stable;
  the registry code also preserves prior active IDs as tombstones rather than
  recycling them.
- The automatic camera baseline uses M2 center, extents, radius, and minimum
  distance. It selects a current-family preset rather than baking one pose
  into every item. The source has 19 preset keys: the documented 18 families
  plus the intentional main/offhand War Glaive directional split. The outlier
  report contains 820 rows using the recorded aspect/radius thresholds.

## Independent source spot checks

The route-stratified rows below were independently read from the fixed
ItemDisplayInfo.dbc and checked against the extracted M2/SKIN/BLP paths and
MPQ provenance. Full seeded + family/route samples are in
catalog/review/weapons/shadow-samples.csv.

| Route | Appearance | Source item / level | Native display | DBC model / texture | Resolved source assets |
| --- | ---: | ---: | ---: | --- | --- |
| MAINHAND | 200045 | 25 / 2 | 1542 | Sword_1H_Short_A_02.mdx / Sword_1H_Short_A_02Rusty | Weapon/Sword_1H_Short_A_02.m2, 00.skin, Rusty.blp |
| SHIELD | 200053 | 1204 / 41 | 1644 | Shield_Rectangle_B_01.mdx / Shield_rectangle_B_01Green | Shield/Shield_Rectangle_B_01.m2, 00.skin, Green.blp |
| RANGED | 200136 | 2777 / 13 | 2787 | Bow_1H_Standard_A_01.mdx / Bow_1H_Standard_A_01Purple | Weapon/Bow_1H_Standard_A_01.m2, 00.skin, Purple.blp |
| HELD_IN_OFFHAND | 200208 | 3360 / 30 | 3573 | Misc_1H_Bone_A_01.mdx / Misc_1H_Bone_A_01Black | Weapon/Misc_1H_Bone_A_01.m2, 00.skin, Black.blp |
| OFFHAND_WEAPON | 200491 | 18392 / 62 | 6443 | Knife_1H_Dagger_B_01.mdx / Knife_1H_Dagger_B_01Green | Weapon/Knife_1H_Dagger_B_01.m2, 00.skin, Green.blp |

## Verification

Run:

    python tools\catalog\weapon_shadow.py check --evidence-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-shadow-20260723-stage6-stormbatch --output-dir catalog\review\weapons

    python tools\catalog\check_weapon_shadow.py --evidence-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-shadow-20260723-stage6-stormbatch --review-root catalog\review\weapons

The checker verified 5,957 rows, 3,690 public rows, five route strata, 43
source samples, all 21 reserved IDs, and terminal coverage. It reported
registry hash
838cf367532ca929729c31d75e9e73655755f6dbe2a8839ecf0de27992c19edc
and summary hash
bb2d8d96bcedc602e609ffa517f1b1bb5d380c35f9417386368de246652be443.
