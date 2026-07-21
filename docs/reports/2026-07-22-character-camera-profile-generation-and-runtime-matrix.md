# Character camera profile generation and runtime matrix

Date: 2026-07-22

## Result

Phase 5 now has one generated camera-profile source for the 10 native races, two sexes and nine wardrobe slots. The canonical matrix contains 180 globally unique private sentinels. The final real-client run reviewed all 180 rows and passed the stage exit criteria: the target slot is visible, the model remains inside the card safe frame, no profile crosses into another race or slot, and no crash or unbounded zoom occurred.

The final profile hash is:

```text
5f7ec4dde75364cbd1e9886aed139a9855c4facc11766b44be40223e7c0013b1
```

The checked-in row-level review is `catalog/review/cameras/runtime-matrix.csv`.

## Inputs and reproducibility

External client assets remain outside Git. The extraction evidence is stored on F: at:

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage5-camera\20260722-053942-630
```

Evidence hash:

```text
c23c1248774272190326c28c0826d9f6e6e4ad20cff05945753defad7317f306
```

DBC inputs:

| Input | Records | SHA-256 |
|---|---:|---|
| `ChrRaces.dbc` | 21 | `32aceb7165030764e048ef596ecd99eea582b6a11edca3933a069fbb6a5adbf6` |
| `CreatureDisplayInfo.dbc` | 24,262 | `1f1a4f5d9d8ed1af1a0be65e8171ed962f2c3e12e213de748e2850515bd3f68b` |
| `CreatureModelData.dbc` | 1,331 | `8ad2af18b3266f81043fed2d3a7c248d1b3c0c746d8d0b2b80f85962a1ca9f88` |

Twenty native M2 models were extracted and hashed. The generated canonical source retains only normalized bounds, source archive provenance, hashes, model paths and deterministic preview display IDs; it does not contain M2 or DBC asset bytes.

Generation follows the implementation plan exactly:

- normalize `verticalOffset`, `horizontalOffset` and `minimumDistance` against the human-female reference dimensions;
- restore those normalized values using each target M2 bounding box;
- retain dimensionless `distanceScale` and `yawOffset`;
- apply only explicit, checked-in overrides;
- reject any DBC/M2 hash drift before generation or `--check`.

The human-female reference keeps the existing nine sentinels `0x5341..0x5349` and all five camera values byte-for-byte. The other 171 sentinels are allocated from the private generated range and are checked against camera 0/1, the reference range and the independent item-camera reserved range.

## Runtime preview selection

`CreatureModelData.dbc` and `CreatureDisplayInfo.dbc` are joined by model-data ID. The extractor chooses a deterministic display row with a non-zero extended display-info ID and scale nearest to 1.0. These display IDs let the QA addon create textured native player models without checking client assets into Git.

The representative appearance items used for each page were:

| Slot | Item ID |
|---|---:|
| HEAD | 16795 |
| SHOULDER | 16807 |
| BACK | 17102 |
| CHEST | 16809 |
| WRIST | 16799 |
| HANDS | 16801 |
| WAIST | 16802 |
| LEGS | 16796 |
| FEET | 16800 |

The QA addon renders a 3x3 `DressUpModel` page for each race/sex combination, applies the generated sentinel, immediately returns through camera 1 as required by the private command protocol, and reapplies the camera after the asynchronous `TryOn` update settles.

## Overrides and rejected diagnostic runs

Tauren, troll, undead and gnome were priority-review families. The proportional profiles were sufficient for tauren, troll and undead. Gnome required per-slot vertical corrections; shoulder and back stay on the proportional baseline, while chest, wrist, hands, waist, legs and feet use progressively lower centers. These entries remain `scaled`, because this stage verifies functional framing rather than claiming pixel-perfect tuning.

Rejected diagnostics are intentionally retained in the external evidence tree:

- `20260722-055451-814`: QA Lua used unavailable `math.mod`; no visual evidence.
- `20260722-055746-389`: untextured direct M2 preview; objective loading only.
- `20260722-060601-228`: direct-display preview still inadequate for appearance review.
- `20260722-061001-871`: representative item lookup used the wrong projection.
- `20260722-061423-759`: textured 180-row diagnostic exposed asynchronous troll camera resets and gnome framing defects.
- `20260722-062334-317`: verified the asynchronous reapply fix, but rejected an over-large uniform gnome correction.

None of these runs is used as acceptance evidence.

## Accepted real-client evidence

Accepted run:

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage5-camera\20260722-053942-630\runtime\20260722-063149-157
```

Results:

- 20 race/sex pages and 180 row records;
- 180/180 expected M2 paths loaded;
- 180/180 visual rows reviewed as pass;
- 21 screenshots, including the post-`/reload` persistence frame;
- screenshot SHA-256 manifest saved as `screenshots.sha256.csv` beside the evidence;
- synthetic race, unknown sex and client-asset-profile mismatch all return no private sentinel and fall back to camera 1;
- profile hash in SavedVariables equals the generated Lua and C++ projection hash;
- human-female reference values and visual result show no regression.

The checked-in review CSV records, for every race/sex/slot row, its sentinel, generated status, page and screenshot, preview display and item, expected model, safe-frame result, target visibility and centering, clipping result, override requirement, and final review result.

## Verification commands

```powershell
python -B tools\catalog\character_camera_profiles.py --evidence-root <evidence-root> check
python -B -m unittest discover -s tools\collections\tests -p "test_*.py" -v
python -B -m unittest discover -s client-extension\SoloCam\tests -p "test_*.py" -v
& .\client-extension\SoloCam\scripts\build.ps1
```

The final verification requires an x86 (`0x014c`) `SoloCam.dll`; a successful hook or asset load alone is not runtime acceptance.
