# Dependency layers / 依赖分层

1. `!!!ClassicAPI` owns generic modern-API compatibility only.
2. DragonUI owns the base HUD, profile, options, edit mode, and the authoritative front-end ModuleRegistry.
3. DragonUI_NewEra owns versioned panel chrome, components, callbacks, and model presentation APIs.
4. SoloCollections owns catalog/query/page state and calls only `DragonUI_NewEra.Public` for platform UI.
5. mod-solo-collections remains the only authority for ownership, permissions, prices, revision, persistence, and action results.

依赖方向固定为 `ClassicAPI -> DragonUI -> DragonUI_NewEra -> SoloCollections`。ezCollections 只读参考，不进入运行依赖。客户端显示数据不得成为收藏权威。

## Delivery layers / 交付分层

- Public source delivery is built by the SoloCollections repository and excludes vendored DragonUI media.
- Integrated client UI delivery is built here and contains exactly five AddOn roots under one `Interface/AddOns` tree.
- `upstream/suite-lock.json` is the provenance boundary: upstream commits, project patch state, TOC versions, and deterministic directory hashes must match before packaging.
- Ownership and actions remain authoritative in mod-solo-collections; the integrated archive changes presentation and install shape only.
