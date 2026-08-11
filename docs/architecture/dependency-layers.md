# Dependency layers / 依赖分层

1. `!!!ClassicAPI` owns generic modern-API compatibility only.
2. DragonUI owns the base HUD, profile, options, edit mode, and the authoritative front-end ModuleRegistry.
3. DragonUI_NewEra owns versioned panel chrome, components, callbacks, and model presentation APIs.
4. SoloCollections owns catalog/query/page state and calls only `DragonUI_NewEra.Public` for platform UI.
5. mod-solo-collections remains the only authority for ownership, permissions, prices, revision, persistence, and action results.

依赖方向固定为 `ClassicAPI -> DragonUI -> DragonUI_NewEra -> SoloCollections`。ezCollections 只读参考，不进入运行依赖。客户端显示数据不得成为收藏权威。

