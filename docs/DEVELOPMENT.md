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
