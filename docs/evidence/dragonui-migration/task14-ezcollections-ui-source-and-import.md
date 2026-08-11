# Task 14 — ezCollections UI source and local asset import

**Status:** `IMPLEMENTED_LOCAL` on 2026-08-11. No real-client files were modified in this task.

## Locked source

- Source: user-provided local ezCollections AddOn snapshot.
- TOC identity: ezCollections 2.2, author `ZEUStiger`.
- Community source page: <https://ezwow.org/topic/131942-ezcollections-262-addon-dlia-transmogrifikatcii-i-kollektcij-na/page-1>.
- Explicit licence file found: no.
- Public redistribution: blocked pending explicit licence and provenance review.
- Source path: deliberately not stored in Git; the build accepts it only as a parameter.
- Directory-hash algorithm: `sha256(sorted relative-path + NUL + lowercase file-sha256 + LF)`.
- Locked source-tree hash: `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`.

| Key reference file | SHA-256 |
| --- | --- |
| `ezCollections.toc` | `eb7c70619885a2311d3fea84509c2a538cc12f03f0e69ee8fe2857d9c5dc528a` |
| `Blizzard_Collections.xml` | `b3885904754987c7c251d82a556cda044bd00b52b33f786237b5e8f44903b35d` |
| `Blizzard_MountCollection.xml` | `82715b8dbc4e31e5fcd65791e38ee94c3e1815bc618b60177e2e5e8a9fbe8f07` |
| `Blizzard_PetCollection.xml` | `39835c0ec059d9ef7972f6ef45fe1863111e2c54b9bde30b83b171ced02633e4` |
| `Blizzard_ToyBox.xml` | `41762b00662695a6bc6a2df01e4a7a86874687791b53b2744ea93877d05825bf` |
| `Blizzard_Wardrobe.xml` | `67caa7284c7e32175bd4eeb93aad0a7f8ede076d0ee6954ff24da97320d1926d` |
| `Blizzard_Wardrobe.lua` | `27d58536f64838633abb0365de2f775bb58dd9609273aa9d0de359acef843657` |
| `WardrobeOutfits.xml` | `8a66703869d4ba8a2b3fd1f7ac69f0bfbed039b031a480814dffbb73b885c260` |
| `WardrobeOutfits.lua` | `b14ea11c76ccf508fb9f41dc04834c1b81b90570886f1593c1e2e30631cad0bb` |

The full machine-readable record is `SoloClientSuite/upstream/ezCollections-reference.json`.

## Complete media projection

The user explicitly authorized use of all media in the snapshot. The parameterized SoloClientSuite importer therefore projects every media file, preserving its source-relative path:

| Format | Files |
| --- | ---: |
| BLP | 55 |
| TGA | 161 |
| WAV | 6 |
| **Total** | **222** |

The media projection hash is `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53`.

The ignored build output is a sixth AddOn, `SoloCollections_EzUI`. It contains those 222 media files, `SoloCollections_EzUI.toc`, a generated `Assets.lua` handshake, and `EZUI-PROVENANCE.json`. Inspection found zero unexpected copied Lua/XML files. The source repository tracks none of the generated BLP/TGA/WAV files.

## Runtime boundary

- SoloCollections commit `3c904dd6b697a713a8836614717fcbb2bb9fdba7` adds `Core/EzCollectionsUI.lua`, `OptionalDeps: SoloCollections_EzUI`, and `/sc assets` status output.
- SoloClientSuite commit `7429d506b223b0b3ff135a5b56a0ff052187d881` adds the parameterized importer, six-root local build inspection, provenance locks, package-manifest support, and LF-stable DragonUI_NewEra deployed bytes.
- The adapter requires schema 1, ezCollections 2.2, the locked source hash, the locked media hash, and the exact generated AddOn root before it returns a media path.
- Missing or mismatched media creates an opaque explanatory overlay that intercepts the page; it does not silently leave empty or clickable invisible controls.
- ezCollections Lua/XML, `C_Transmog*`, server Lua, and the ezCollections message protocol are excluded. SoloCollections catalog/state/bridge and mod-solo-collections remain authoritative.

## Local checks performed

- All five affected PowerShell scripts parsed successfully under PowerShell 7.
- Both provenance JSON files parsed successfully.
- The five checked-in suite roots matched `suite-lock.json`.
- The local build produced five base roots plus `SoloCollections_EzUI` and revalidated all directory/media hashes.
- The generated media tree contained 55 BLP, 161 TGA, 6 WAV, one generated Lua marker, one TOC, and one provenance JSON; unexpected copied code files: 0.
- No generated media or `SoloCollections_EzUI` path is tracked by Git.

This is source/build evidence only. Page rendering begins in Task 15, and real-client visual acceptance remains Task 20.
