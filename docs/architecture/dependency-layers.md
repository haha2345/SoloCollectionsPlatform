# Dependency layers / 依赖分层

1. `!!!ClassicAPI` owns generic modern-API compatibility only.
2. DragonUI owns the base HUD, profile, options, edit mode, and the authoritative front-end ModuleRegistry.
3. DragonUI_NewEra owns versioned panel chrome, components, callbacks, and model presentation APIs.
4. SoloCollections owns catalog/query/page state and calls only `DragonUI_NewEra.Public` for platform UI.
5. Generated `SoloCollections_EzUI` owns no behavior; it exposes the hash-locked local ezCollections media root to SoloCollections.
6. mod-solo-collections remains the only authority for ownership, permissions, prices, revision, persistence, and action results.

基础依赖方向固定为 `ClassicAPI -> DragonUI -> DragonUI_NewEra -> SoloCollections`。本地视觉能力另由 `SoloCollections_EzUI -> SoloCollections` 提供；它是可选素材 AddOn，不包含 ezCollections 运行代码，也不得成为收藏权威。素材缺失或 Hash 不匹配时，SoloCollections 必须遮罩并阻断依赖该素材的页面，不能留下空白按钮。

## Delivery layers / 交付分层

- Public source delivery is built by the SoloCollections repository and excludes vendored DragonUI media.
- The repository source tree contains exactly five base AddOn roots. A user-authorized local build may add generated `SoloCollections_EzUI` as the sixth root under the ignored `build/` tree.
- `upstream/suite-lock.json` is the provenance boundary: upstream commits, project patch state, TOC versions, and deterministic directory hashes must match before packaging.
- `upstream/ezCollections-reference.json` separately locks the 2.2 source and complete media projection. It records no machine-local source path and does not authorize public redistribution.
- Ownership and actions remain authoritative in mod-solo-collections; the integrated archive changes presentation and install shape only.
