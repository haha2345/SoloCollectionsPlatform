# Development guide / 开发指南

## Repository map / 仓库结构

```text
addon/SoloCollections/             WoW 3.3.5a AddOn
catalog/source/                    canonical catalog inputs
catalog/review/                    reviewed decisions and reproducible evidence metadata
catalog/generated/                 generated manifests and review projections
protocol/sc2/                      machine-readable SC2 schema and golden vectors
client-extension/SoloCam/          optional x86 camera extension
server/ale/                        retired SC1 migration/reference bridge
tools/catalog/                     catalog and camera import/generation tools
tools/collections/tests/           AddOn/catalog/protocol contracts
tools/release/                     matched AddOn/module source packaging
tools/runtime/                     opt-in real-client audit helpers
docs/architecture/                 implementation notes
docs/images/                       selected public screenshots
```

The authoritative server backend lives in the sibling
[`mod-solo-collections`](https://github.com/haha2345/mod-solo-collections)
repository.

## 中文开发流程

### 1. 先确定修改属于哪一层

| 修改 | 源头 |
| --- | --- |
| UI、过滤、分页、模型卡片 | `addon/SoloCollections` |
| canonical identity、动作或名称 | `catalog/source` |
| 审核结论、可见性、profile | `catalog/review` 或明确的 override source |
| SC2 消息格式 | `protocol/sc2`，并同步 AddOn 与模块 |
| 权限、账号状态、数据库、服务端动作 | `mod-solo-collections` |
| 固定客户端地址、局部镜头 | `client-extension/SoloCam` |

不要从游戏安装目录反向覆盖源码。客户端和世界服是部署/验收目标，不是权威源。

### 2. 保持单一服务端权威

生产后端为：

```ini
SoloCollections.Backend = Cpp
```

AddOn 只能请求稳定 collection/action identity。图标、模型路径、display ID、
本地收藏状态或 SavedVariables 不能授权动作。SC1/ALE 不能与 SC2/C++ 同时写入
或返回成功。

### 3. 目录修改

正常顺序是：

```text
合法外部输入
-> catalog/source 与 catalog/review
-> 生成器
-> catalog/generated
-> AddOn Lua projection
-> module C++/JSON projection
```

目录生成需要维护者自己合法取得的 DBC、数据库快照或模型结构 evidence。它们
放在仓库外的临时目录，只提交脱敏后的审核决定、hash 和生成结果。不要手工编辑
20 MB 的生成 `Catalog.lua` 代替源数据变更。

### 4. 镜头修改

物品页提供内嵌“镜头工作台”。工作台的输出先成为 review-only JSONL，不会直接
写入 canonical source。完整流程、scope 选择和 PR 证据见
[CAMERA_CONTRIBUTIONS.md](CAMERA_CONTRIBUTIONS.md)。

### 5. 输出状态要分开

报告结果时明确区分：

- source/static：源码和生成合同；
- build：Python、Lua syntax、SoloCam 或 Core 编译；
- server runtime：worldserver 日志、schema、命令；
- client runtime：真实 3.3.5a 登录和交互；
- visual acceptance：截图/视频与指定矩阵。

编译成功不能替代服务器运行；自动检查或 DLL 加载不能替代镜头视觉验收。

## English workflow

Choose the source layer before editing. UI changes belong in the AddOn;
canonical identities belong in `catalog/source`; review decisions belong in
`catalog/review`; SC2 wire changes must update the schema, golden vectors,
AddOn, and module; server authorization and persistence belong in the module.

Keep the C++ backend as the sole writer. Client display fields and
SavedVariables never authorize an action. Do not run SC1/ALE and SC2/C++ as
parallel production responders.

Catalog work flows from legally obtained external inputs to canonical
source/review data, then through generators to the Lua and C++ projections.
External DBC, database, and model evidence remains outside Git. Never edit the
large generated `Catalog.lua` as a substitute for changing its source.

Camera workbench exports are review-only. Follow
[CAMERA_CONTRIBUTIONS.md](CAMERA_CONTRIBUTIONS.md) and distinguish source
checks, builds, server runtime, client runtime, and visual acceptance.

## Common commands

```powershell
# Python dependencies
python -m pip install -r .\client-extension\SoloCam\requirements-dev.txt

# AddOn/catalog/protocol contracts
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s .\tools\collections\tests -p "test_*.py" -v

# SoloCam portable contracts
python -m unittest discover -s .\client-extension\SoloCam\tests -p "test_*.py" -v

# SoloCam x86 build and native checks
& .\client-extension\SoloCam\scripts\build.ps1

# Formatting sanity
git diff --check
```

Catalog generation and matched release commands are documented in
[BUILDING.zh-CN.md](BUILDING.zh-CN.md) and
[BUILDING.en.md](BUILDING.en.md).

## SC2 wardrobe expansion deploy order

Type 18/19 and `Y`/`U`/`O` stay on protocol version 1. Old AddOns keep using
type 13/14. New AddOns advertise `clientBuild` `0.2.0-w1`.

1. Deploy `mod-solo-collections` first (SQL update, provider, Y/U/O, type 18/19).
   Old AddOns still only speak 13/14 and must not receive type 18/19 mappings.
2. Deploy this AddOn second. HELLO uses `SC.VERSION .. "-w1"`; `SC.VERSION`
   remains `0.2.0`.
3. Ship a matched metadata/mapping-hash set. Type 18/19 hashes are slot-grammar
   hashes, not the appearance catalog hash.

Do not mark real-client wardrobe items complete without observing quote, atomic
apply, hide persistence, clear-applied, and a second character seeing account
outfits.

Wardrobe `Y`/`U` now emit `event=wardrobe_quote` and `event=wardrobe_intent` on
`module.solocollections.wardrobe` (status, copper, entries, source). A rejected
`Y` body also sets `kind=Y` on `event=protocol_reject`. Use those lines to tell
a missing client send from a server-side quote/apply result.

Collected wardrobe apply uses `CanApplyCollectedVisual` so an owned appearance
is not blocked by the source item's `AllowableClass`. Hide still stores FakeEntry
`1`, but `OnPlayerAfterSetVisibleItemSlot` writes visible item `0`. The wardrobe
preview reads type 18 after apply only while the same item is still equipped;
swapping gear falls back to the real item. `U.copper` is
`max(source item sellPrice, 1g) * ScaledCostModifier + CopperCost` per changed
non-hide slot. Hide and clear are free. An applied, non-pending slot
right-click sends `Y CLEAR` for that item instance (including hide). Set
presets quote and apply through the same `Y` path when type 18 is Ready. `ApplyBaseCopper` / `ApplySlotCopper`
are unused. `UpdateQuotedMoney` only forces the copper button when the quote
is `0`; a 1g+ quote must keep the gold denomination. Wardrobe slot tooltips show the quality-colored equipped name plus
pink official transmog lines (`幻化为:` / `你将要幻化为:` and the
appearance in `1, 0.5, 1`). Pending replaces the applied line; hidden
uses `隐藏`. The official empty-slot sentence is only for a truly empty
inventory slot — an uncached 3.3.5 `GetInventoryItemLink` or a worn item
with no applied transmog is not empty. They must not dump item stats via
`SetInventoryItem`.
`SafeDressUp` reuses the OnLoad unit and must not stay
at alpha 0 after `/reload`, apply, or set-card present.

## Branch and pull-request practice

1. Start from the latest `main`.
2. Keep a feature branch focused on one issue.
3. Preserve unrelated working-tree changes.
4. Update documentation with behavior changes.
5. Do not commit ignored build/runtime output.
6. For cross-repository changes, state both commits and the required merge
   order.
7. Include real-client evidence for UI/model/camera claims, or explicitly mark
   it as pending.

Agent-assisted development must also follow [AGENTS.md](../AGENTS.md) and
[AGENT_DEVELOPMENT.md](AGENT_DEVELOPMENT.md).
