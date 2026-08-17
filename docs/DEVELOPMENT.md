# Development / 开发说明

## Source map

```text
src/SoloCollectionsCore.cpp                 lifecycle hooks and providers
src/SoloCollectionsAccount*.{h,cpp}         account cache, store, revisions
src/SoloCollectionsProtocol*.{h,cpp}        SC2 codec, server, runtime bridge
src/Categories/Appearance/                  canonical appearance service
src/SoloCollections{Mount,Companion,Toy}*   category catalogs and actions
src/SoloCollectionsSet*                     derived set ownership/application
src/SoloCollectionsTransmog*                type 18/19 wardrobe projections
src/Transmogrification.*                    adapted upstream transmog
src/generated/*.inc                         generated catalog projections
data/sql/                                   base SQL and append-only updates
conf/transmog.conf.dist                     public configuration template
tests/                                      portable/native contracts
```

The canonical catalog and SC2 schema live in the sibling
[`SoloCollections`](https://github.com/haha2345/SoloCollections) repository.
Its generator writes the server projections under `src/generated/`. Change the
canonical source/review input, regenerate both sides, and commit matching
outputs. Do not patch generated rows manually.

## Build metadata

`src/SoloCollectionsBuildInfo.inc` is a tracked wrapper. It includes the
ignored `src/generated/SoloCollectionsBuildInfo.inc` when present and otherwise
logs `UNPINNED` values so a clean development checkout can compile.

Use the AddOn repository's
`tools/release/New-SoloCollectionsBuildInfo.ps1` before a deployable build.
The runtime `.solocollections status` and startup log expose the exact values.

## Invariants

- The server, never the AddOn, authorizes ownership and actions.
- `Cpp` is the only production writer.
- One successful mutation advances the account revision exactly once.
- Database commit precedes cache and connected-session updates.
- Duplicate, rejected, or failed mutations do not create cache-only state.
- Set ownership is derived from its appearance dependencies.
- Preference mutations accept only the explicit 16-to-10 and 17-to-11 mappings,
  require ownership of the underlying collection, and commit before emitting a delta.
- Favorite projection providers are internal SC2 state and are excluded from journal
  navigation, totals, and completion semantics by the canonical protocol schema.
- Unknown identity, catalog mismatch, or protocol mismatch fails closed.
- Wardrobe Y APPLY/CLEAR is one request, one transaction, one fee. Type 14
  success writes type 18 in the same item transaction. Deploy this module
  before the AddOn that sends `-w1` / Y / O.

## Cross-repository changes

| Change | Required work |
| --- | --- |
| UI only | Client repository |
| Catalog identity/policy | Client canonical source + regenerated module `.inc` |
| SC2 wire | Schema/golden vectors + AddOn + module |
| Database/provider/action | Module; document client effect |
| Camera/framing | Client repository, normally no module change |

## Evidence language

Report these independently:

- **source/static**: review, generated consistency, diff checks;
- **build**: module contracts or AzerothCore compilation;
- **server runtime**: startup logs, schema, commands, actions;
- **client runtime**: SC2 handshake and gameplay interaction;
- **visual acceptance**: real-client screenshots for model/camera work.

## 中文摘要

本仓库维护服务端权威逻辑；客户端仓库维护 canonical 目录、SC2 schema 和生成器。
涉及 identity、policy 或协议时必须同时更新两仓库，不能直接手改生成 `.inc`。

账号写入必须保持“数据库一次 revision 提交成功后，再更新缓存和在线会话”的
顺序。客户端显示字段、SavedVariables、图标或 display ID 不能授权。

使用 Agent 时，把任务限制在一个 provider/协议/数据库问题，要求它列出跨仓库
依赖和未完成的运行验收；真实数据库、服务端部署和发布仍由人类控制。
