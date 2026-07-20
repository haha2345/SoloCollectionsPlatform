# SoloCollections 统一收藏后端实施方案

日期：2026-07-19

状态：实施中

设计依据：[2026-07-19-solo-collections-unified-backend-design.md](2026-07-19-solo-collections-unified-backend-design.md)

## 1. 实施目标

本方案把已确认的设计拆成可逐步编译、验证、回滚和提交的工程任务。最终交付物是：

- 继续由 Lua 实现的 `SoloCollections` 客户端 AddOn；
- 一个由 `mod-transmog` fork 并重构而来的 `mod-solo-collections` C++ 后端；
- 一个账号级收藏状态真相；
- 一套版本化 SC2 协议；
- 可注册的收藏类别、种族、职业、能力和资格策略；
- 坐骑、小宠物、玩具、外观和套装的真实目录、解锁、同步和动作闭环；
- 为后续高版本内容和新收藏类别准备的生成、迁移和测试流程。

实施遵循“先加固旧幻化，再建收藏核心，再完成一个纵切，最后逐类迁移”的顺序。任何阶段失败都不能迫使项目同时维护两个生产写入后端。

## 2. 当前基线

工作区：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\
├─ SoloCollections\
└─ mod-solo-collections\
```

当前基线提交：

| 仓库 | 基线 | 说明 |
|---|---|---|
| `SoloCollections` | `f78fe74` | 已提交统一后端设计 |
| `mod-solo-collections` | `33ac64b` | 从本地 `mod-transmog` 克隆 |
| `azerothcore-wotlk` | `bdb39abddb319eac0cd0755eedb3bffdb6490930` | 当前审计 Core 基线 |

`mod-solo-collections` 当前只配置：

```text
upstream = https://github.com/azerothcore/mod-transmog.git
```

在用户明确创建项目远程仓库之前，不自动添加或推送新的 `origin`。

## 3. 全程执行规则

### 3.1 仓库边界

- AddOn、目录源、目录生成器、协议 golden vectors、客户端测试和发布编排放在 `SoloCollections`。
- AzerothCore 模块源码、SQL、服务端配置、服务端测试和上游补丁记录放在 `mod-solo-collections`。
- 父目录 `SoloCollectionsPlatform` 只是工作区容器，不初始化第三个 Git 仓库。
- 原始 `F:\1_projects\wow_projects\mod-transmog` 保持未修改，只作参考和上游差异核对。
- 不把 AzerothCore、客户端资源、MPQ、DBC、模型、贴图或构建产物提交进这两个源码仓库。

### 3.2 提交规则

- 每个任务形成一个可编译或纯文档提交。
- 安全修复、结构重构和新功能不得混在同一提交。
- 数据库 migration 与使用它的代码可以在同一功能提交，但必须提供旧库升级测试。
- 跨仓库协议变更使用相同的协议版本说明，并在两个提交信息中写明配套 commit。
- 每个阶段打本地里程碑 tag 前必须完成对应自动测试和运行验收。

### 3.3 单写原则

- 任意时刻只有 ALE Lua 或 C++ 中的一方可以处理生产 SC2 动作和写账号收藏表。
- shadow 模式只读、只比较、只记录差异，不写数据库、不执行动作、不广播成功。
- C++ 切换为主后，ALE 脚本必须显式关闭，不依赖“玩家通常不会触发两个入口”。

### 3.4 质量门槛

每个阶段至少通过：

1. `git diff --check`；
2. SoloCollections Python contract tests；
3. Lua 5.1 语法检查；
4. AzerothCore 干净配置和编译；
5. SQL 在空库与升级库上执行；
6. 当前阶段对应的真实 worldserver/client 验收；
7. 两仓库工作树和配套 commit 记录核对。

## 4. 目标源码结构

### 4.1 `SoloCollections`

```text
SoloCollections/
├─ addon/SoloCollections/
│  ├─ Core/
│  │  ├─ Bridge.lua
│  │  ├─ CollectionState.lua
│  │  ├─ PageRegistry.lua
│  │  ├─ IdentityRegistry.lua
│  │  └─ Catalog.lua
│  ├─ Data/
│  │  └─ Generated/
│  └─ UI/
├─ catalog/
│  ├─ source/
│  │  ├─ classes.json
│  │  ├─ races.json
│  │  ├─ collection_types.json
│  │  ├─ collections/
│  │  ├─ policies/
│  │  └─ overrides/
│  ├─ ids.json
│  └─ generated/
├─ protocol/
│  ├─ sc2-schema.json
│  └─ golden-vectors.json
├─ tools/
│  ├─ catalog/
│  ├─ backend/
│  └─ collections/tests/
└─ docs/
```

### 4.2 `mod-solo-collections`

```text
mod-solo-collections/
├─ conf/
├─ data/sql/
├─ src/
│  ├─ Collections/
│  │  ├─ CollectionTypes.h
│  │  ├─ CollectionResult.h
│  │  ├─ CollectionProvider.h
│  │  ├─ CollectionProviderRegistry.*
│  │  ├─ CollectionCatalogMgr.*
│  │  ├─ AccountCollectionService.*
│  │  ├─ AccountCollectionStore.*
│  │  ├─ AccountCollectionCache.*
│  │  ├─ IdentityRegistry.*
│  │  ├─ EligibilityPolicy.*
│  │  ├─ CollectionProtocol.*
│  │  ├─ CollectionScripts.cpp
│  │  └─ CollectionCommands.cpp
│  ├─ Categories/
│  │  ├─ Mount/
│  │  ├─ Companion/
│  │  ├─ Toy/
│  │  ├─ Appearance/
│  │  └─ Set/
│  ├─ Transmog/
│  └─ mod_solo_collections_loader.cpp
├─ tests/
└─ docs/
```

最终文件名可按 Core module 构建约定微调，但组件边界不可重新合并成一个全局 manager。

## 5. 阶段 0：建立可维护 fork 和构建基线

阶段状态：✅ 已完成（2026-07-19）

### 任务 0.1：记录 fork 来源

状态：✅ 已完成（`mod-solo-collections` `55e0cd5`）

仓库：`mod-solo-collections`

变更：

- 添加 `UPSTREAM_BASE.md`，记录上游 URL、基线 commit、Core 基线和审计日期。
- 添加或扩充 `THIRD_PARTY_NOTICES.md`，保留 `mod-transmog` 作者、许可证和修改说明。
- 保留原始 `LICENSE`。
- 确认自有分支策略：项目开发分支使用 `main`，官方上游继续跟踪 `upstream/master`。
- 在创建新 `origin` 前不修改远程发布状态。

验证：

- `git log --oneline --decorate -5`
- `git remote -v`
- `git diff --check`

建议提交：

```text
chore: establish mod-solo-collections fork metadata
```

### 任务 0.2：建立安全的 Core 开发接入

状态：✅ 已完成（`SoloCollections` `f61ac44`）

仓库：`SoloCollections`

新增：

- `tools/backend/install-module-link.ps1`
- `tools/backend/remove-module-link.ps1`
- `tools/backend/verify-module-link.ps1`

规则：

- 开发环境默认在 `azerothcore-wotlk/modules/mod-solo-collections` 创建指向平台仓库的 Windows junction，保持单一工作树。
- 创建前解析源、目标和 Core 根目录，拒绝目标已存在、路径重叠、目标逃出 Core `modules`。
- 删除脚本只移除经过验证且目标正确的 junction，不递归删除真实仓库。
- CI 和公开构建使用正常 Git checkout，不依赖 junction。

验证：

- 创建、验证、移除、再次创建 junction。
- Core `git status --short` 只出现预期 module 路径状态。
- 验证脚本打印源 commit、模块 commit 和 resolved target。

建议提交：

```text
tools: add safe backend module workspace linking
```

### 任务 0.3：编译未改造上游基线

状态：✅ 已完成（fork bootstrap `17568dc`；构建记录 `64996e4`）

执行说明：上游 `33ac64b` 的 loader 名称仍为 `Addmod_transmogScripts`，
无法以 `mod-solo-collections` 目录名通过 Core 最终链接。经确认后先以独立
bootstrap 提交将入口改为 `Addmod_solo_collectionsScripts`，其余上游源码不变，
再完成干净基线编译。

仓库：`mod-solo-collections`

步骤：

- 将模块接入当前 `azerothcore-wotlk/modules`。
- 使用当前 Core 配置完成一次干净 configure/build。
- 记录编译器、架构、Core commit、模块 commit 和配置选项。
- 不安装 SQL、不启动生产数据库，仅验证基线可编译。

验收：

- worldserver 和 authserver 构建成功。
- 模块 loader 被链接。
- `_work` 或 Core build 目录不进入任一项目仓库。

输出记录：

```text
mod-solo-collections/docs/baselines/2026-07-19-upstream-build.md
```

建议提交：

```text
docs: record upstream module build baseline
```

## 6. 阶段 1：在扩展功能前修复 P0 问题

### 任务 1.1：封闭幻化执行入口

状态：✅ 已完成（`mod-solo-collections` `c25f3f3`）

主要文件：

- `src/Transmogrification.h`
- `src/Transmogrification.cpp`
- `src/transmog_scripts.cpp`
- `src/cs_transmog.cpp`

变更：

- 新增唯一安全 facade：`TryApplyCollectedAppearance`。
- facade 从 `WorldSession` 取得账号，重新验证收藏、目录、来源、目标槽、角色资格、NPC/AddOn 会话和费用。
- 原 `Transmogrify(player, itemEntry, slot)` 降为内部实现，不允许协议、vendor 或普通命令直接调用。
- fake-vendor hook 在最终应用前执行完整交互和收藏检查；无法证明安全时默认关闭 vendor interface。
- AddOn 永远不能直接提交 spellId、displayId 或任意 source itemId。

测试：

- 伪造未收藏 item ID。
- 远距离/错误 NPC/错误会话 vendor 请求。
- 正常已收藏来源。
- 已拥有 canonical appearance 但请求未授权别名来源。

验收：

- 所有生产入口只有一条到达最终应用函数的调用链。
- 未收藏请求没有费用、物品、数据库和可见外观副作用。

建议提交：

```text
fix: enforce collected appearance authorization at apply boundary
```

### 任务 1.2：修复模板空指针和对象所有权

状态：✅ 已完成（`mod-solo-collections` `4876632`）

变更：

- 所有 item、quest reward、spell、creature 和 template lookup 增加显式空值处理。
- `OnPlayerAfterStoreOrEquipNewItem` 对空 `Item*` 安全返回并记录上下文。
- 将仅用于规则判断的临时 `Item::CreateItem` 改为 `ItemTemplate const*` 算法。
- 必须创建临时对象时使用明确 RAII 所有权，不保留裸指针容器。
- 全量候选列表不再构造游戏对象。

测试：

- 缺失 item_template。
- 任务奖励条目缺失。
- Store/Equip hook 收到空 item。
- 连续打开外观列表和应用外观的内存增长。

建议提交：

```text
fix: make transmog template handling null safe and leak free
```

### 任务 1.3：原子化费用和多槽应用

状态：✅ 已完成（`mod-solo-collections` `87f3d3e`）

变更：

- 建立 `PreflightApply`，计算目标、来源、兼容性、金币、token 和总费用。
- 预检成功前不扣除任何资源。
- 单槽应用和整套应用使用统一结果类型。
- 多槽操作任一槽失败时全部不执行。
- 数据库和内存更新顺序可确认成功/失败。

测试：

- 金币不足、token 不足、目标槽缺失。
- 第一个槽合法、第二个槽非法。
- 数据库提交失败。
- 重复请求。

建议提交：

```text
fix: make transmog costs and outfit application atomic
```

### 任务 1.4：修复缓存 reload

状态：✅ 已完成（`mod-solo-collections` `ef07e94`）

变更：

- `LoadCollections`、Allowed、NotAllowed 和其他目录缓存先构建新状态，成功后 swap。
- reload 查询失败时保留旧缓存并设置明确健康状态。
- 从 DB 删除或 revoke 的条目在成功 reload 后消失。
- 禁止外部代码直接写 `collectionCache`。

建议提交：

```text
fix: replace transmog caches atomically on reload
```

阶段出口：

- 未加入任何新收藏类别。
- 当前幻化功能可编译、可运行且安全基线测试通过。
- 形成 `security-baseline` tag，后续重构可与其比较。

运行部署状态：✅ worldserver、SQL updater、模块字符串、收藏缓存、NPCBots
兼容性以及真实客户端 NPC/越权拒绝/费用/token/多槽/reload 验收全部通过。
运行验收额外修复了 Gossip Core 预扣款（`c455d68`）和磁盘模块配置未真实
reload（`bd7aa3e`）。已在 `mod-solo-collections` 提交 `17c1cdc` 创建注释标签
`security-baseline`。完整证据记录在
`mod-solo-collections/docs/baselines/2026-07-19-p0-security-runtime.md`。

## 7. 阶段 2：统一收藏核心骨架

阶段状态：✅ 已完成（任务 2.1–2.3）

### 任务 2.1：引入稳定基础类型

状态：✅ 已完成（`mod-solo-collections` `be9f68e`）

新增：

- `CollectionTypeId`
- `CollectionId`
- `LogicalClassId`
- `LogicalRaceId`
- `CollectionRevision`
- `CollectionResult`
- 稳定 reason code 枚举
- `Owned / UsableNow / CatalogKnown / AssetReady` 独立状态

要求：

- 持久化和协议不直接使用 C++ enum 顺序。
- ID 使用显式宽度无符号整数。
- 删除值保留 tombstone，不复用。
- reason code 可以稳定映射到 AddOn 本地化文字。

建议提交：

```text
refactor: introduce stable collection domain types
```

### 任务 2.2：建立 provider 注册表

状态：✅ 已完成（mod-solo-collections `4ab2246`）

新增 `CollectionProvider` 接口和 `CollectionProviderRegistry`：

- 重复 typeId/typeKey 注册时启动失败。
- provider 依赖构成无环图。
- 缺失依赖时该类别降级为 disabled/read-only。
- provider 不能自行写账号缓存。
- 注册顺序不影响持久化 ID 和协议 ID。

先注册一个无动作的 synthetic provider，证明核心不依赖固定五类 switch。

建议提交：

```text
feat: add collection provider registry
```

### 任务 2.3：建立账号缓存和状态机

状态：✅ 已完成（mod-solo-collections `b3b2fb3`）

实现：

- `Loading / Ready / Failed`。
- 在线账号懒加载。
- 登录 generation。
- 同账号会话集合。
- pending unlock/delta。
- 最后会话登出后的延迟淘汰。
- world-thread 串行或明确锁策略。

测试：

- 同账号两角色同时登录。
- 查询回调返回前角色登出。
- 加载期间发生新解锁。
- 最后会话登出后重新登录。

建议提交：

```text
feat: add account collection cache state machine
```

## 8. 阶段 3：数据库、revision 和审计

阶段状态：✅ 已完成（任务 3.1–3.3）

### 任务 3.1：创建版本化 schema

状态：✅ 已完成（mod-solo-collections `821fcae`）

角色库表：

- `sc_account_state`
- `sc_collection_unlock`
- `sc_collection_audit`
- `sc_migration_marker`

规则：

- 唯一键 `(account_id, type_id, collection_id)`。
- revision 在同一事务中分配。
- 数字 ID 使用 `INT UNSIGNED` 或设计要求的更宽类型。
- 审计表记录来源、角色、GM actor、结果和时间。
- migration 文件有明确版本，不修改已经发布的历史 migration。

查询安全：

- 第一阶段 SQL 参数全部为验证过的数字和固定枚举。
- 未来 Outfit 名称等文本必须限长并正确转义；在确认模块 prepared statement 扩展机制前不加入任意用户文本写入。

建议提交：

```text
feat: add versioned account collection schema
```

### 任务 3.2：实现异步 store

状态：✅ 已完成（mod-solo-collections `a6536bd`）

实现：

- 登录使用 `CharacterDatabase.AsyncQuery`。
- 写入使用可取得提交结果的异步事务。
- 回调捕获 accountId、playerGuid、generation，不捕获裸 `Player*`。
- 事务成功后更新缓存和广播。
- 查询/事务错误产生结构化日志和明确失败状态。

测试：

- 新库、已有数据、重复 INSERT。
- 模拟 DB 失败和重试。
- 提交成功后 worldserver 重启恢复。
- 双会话并发新增同一收藏。

建议提交：

```text
feat: persist account collections with confirmed async transactions
```

### 任务 3.3：GM 和诊断命令骨架

状态：✅ 已完成（mod-solo-collections `642879d`）

实现：

- `.solocollections status`
- `.solocollections account`
- `.solocollections grant/revoke`
- `.solocollections reload`
- `.solocollections resync`
- `.solocollections import/reconcile --dry-run`

所有写命令检查 RBAC 并写审计。未知 ID、未知类别和 DB 未 ready 时安全失败。

运行验收：真实 3.3.5 客户端完成 status/account、grant/revoke、reload、
resync 安全失败和 import/reconcile dry-run；生产库确认 RBAC `5:5`、成功与
拒绝审计、revision 1–4、worldserver 重启后 revision 3 恢复。测试 unlock
已通过正式 revoke 清理，审计历史按设计保留。完整证据记录在
`mod-solo-collections/docs/baselines/2026-07-20-phase3-runtime.md`。

建议提交：

```text
feat: add collection diagnostics and audited admin commands
```

## 9. 阶段 4：目录生成器和身份扩展

阶段状态：✅ 已完成（任务 4.1–4.3）

### 任务 4.1：建立单一目录源

状态：✅ 已完成（SoloCollections `d291b5f`；mod-solo-collections `fe29c27`）

仓库：`SoloCollections`

新增：

- `catalog/source/collection_types.json`
- `catalog/source/classes.json`
- `catalog/source/races.json`
- `catalog/source/collections/*.csv`
- `catalog/source/policies/*.json`
- `catalog/source/overrides/*.json`
- `catalog/ids.json`

生成器要求：

- 确定性输出。
- 稳定 ID 和 ordinal 只追加。
- 检测 ID 重复、复用、alias 环、依赖环和非法 policy。
- 分别生成 mapping hash、metadata version、asset pack version。
- 生成客户端 Lua、服务端 world seed/manifest 和资源缺失报告。
- 支持显式 `--module-root`，跨仓库写入前打印目标并验证目标确为 `mod-solo-collections`。

建议提交：

```text
feat: add deterministic collection catalog generator
```

### 任务 4.2：实现 `IdentityRegistry`

状态：✅ 已完成（SoloCollections `a67b5e7`；mod-solo-collections `e289ad9`）

仓库：两个仓库配套修改。

实现：

- `logicalClassId/classKey` 与 `runtimeClassId` 分离。
- `logicalRaceId/raceKey` 与 `runtimeRaceId` 分离。
- 支持 aliases、sourceBuild、能力标签、compatibility profile 和 client asset profile。
- AddOn 生成职业/种族名称、图标、顺序和默认过滤 profile。
- 未知 runtime ID 映射到 `UNKNOWN_IDENTITY`，不默认成人类或战士。

测试样本：

- synthetic class ID 超出当前预设范围。
- synthetic race ID 使用全局镜头 fallback。
- runtime ID 改变但逻辑 ID 和收藏不变。

建议配套提交：

```text
feat: add extensible class and race identity registry
```

### 任务 4.3：实现资格策略

状态：✅ 已完成（mod-solo-collections `f38f1a1`）

实现：

- required/any/forbidden capabilities。
- allowed/denied race 和 class keys。
- faction、level、skills、custom policy。
- hard resource deny、exact override、declarative policy、legacy fallback、runtime condition 的固定顺序。
- 原始 AllowableRace/Class 只作为 legacy 导入和 fallback。

测试：

- 新职业复用既有护甲/武器 profile。
- exact allow 不得绕过缺失资源。
- exact deny 优先于普通能力允许。
- 未知身份只允许查看不受限目录。

建议提交：

```text
feat: evaluate collection eligibility through identity policies
```

阶段出口：

- 新增普通目录条目不改业务 C++。
- 新增 synthetic 职业/种族不改五个类别实现。

验证记录：目录生成器 `--check` 无漂移，mapping hash 为
`bb891f9c9fdf5a4f795488cc49a3a1ed73bfe4e985116be5e6b3aa07b9af53ac`；
AddOn 137 项 Python 测试、模块 53 项 Python 测试和 MSVC 原生测试通过；
当前 AzerothCore `worldserver` 已重新配置并成功编译，新增 identity/eligibility
源文件进入真实模块构建。构建产物已部署，运行文件 SHA-256 为
`82D166136ABA69E662811A56CD5B5BC1F98BFE4D73065982B9600BB01B7C639C`，
启动日志确认 worldserver ready、provider/cache 初始化和 schema ready。两个真实
客户端 AddOn 目录均已部署且 parity 校验无缺失、差异或多余文件。完全退出并重启
真实客户端后，游戏内自检返回 `IdentityRegistry=table`、`/sc` 处理器为 `function`、
职业筛选项共 11 项；`/sc` 收藏界面和外观页正常打开，生成的“全部职业 + 10 个
职业”下拉完整显示，当前角色正确识别为战士，未出现 Lua 错误框。
- 同一源数据可重新生成两仓库配套输出且 diff 确定。

## 10. 阶段 5：SC2 和客户端真实状态层

阶段状态：✅ 已完成（任务 5.1–5.3）

### 任务 5.1：固定 wire schema 和 golden vectors

状态：✅ 已完成

仓库：`SoloCollections`

定义：

- HELLO/HELLO_ACK。
- 类别功能位和每类 mapping hash。
- snapshot begin/chunk/end。
- delta。
- action request/result。
- resync/error。
- nonce、requestId、transferId、seq/total、revision 和 checksum。

生成 golden vectors，供 Python、Lua 和 C++ 使用相同输入输出验证。单包按不超过 Core 255 字节限制设计，并预留前缀、频道和字段开销。

验证记录：已落地 `protocol/sc2/schema.json`、跨语言共用
`golden-vectors.json`、严格 Python 参考 codec 和 wire contract 文档；SC2 body
上限固定为 240 字节、chunk payload 上限为 160 字节，11 类消息的 round-trip、
checksum、确定性分片、非规范字段和超长包拒绝测试通过。

建议提交：

```text
protocol: define versioned SC2 wire contract
```

### 任务 5.2：实现服务端 codec 和限流

状态：✅ 已完成（mod-solo-collections `9c52a35`）

仓库：`mod-solo-collections`

实现：

- 严格字段数量、字符集、数字长度、总分片和总内存限制。
- token bucket 限流。
- nonce 和短期 replay cache。
- 多 tick 出站队列。
- 只接受约定的 AddOn whisper/self channel。
- 未 ready 时返回 LOADING，不返回空 owned 集合。

验证记录：C++ codec 与 Python golden vectors 字节一致；原生测试覆盖 confirmed
empty snapshot、`LOADING`、分 tick 队列、旧 nonce、重复 requestId 和 token bucket。
模块 57 项 Python 测试与两个 MSVC 原生测试目标通过。真实 AzerothCore 已重新配置
并编译成功，新协议源文件进入 `modules.vcxproj`；worldserver 构建产物 SHA-256 为
`ADDFE74CA3BA95090D31DDB797E8B91EFAEA95F57AECB119E8F3DA1B35DC5E07`。

建议提交：

```text
feat: implement hardened SC2 server protocol
```

### 任务 5.3：升级客户端 Bridge

状态：✅ 已完成（SoloCollections `3e6df74`）

主要文件：

- `addon/SoloCollections/Core/Bridge.lua`
- 新增 `CollectionState.lua`
- `Bootstrap.lua`
- `Catalog.lua`

实现：

- SC1 保持只读兼容或明确退役，不与 SC2 共用请求表。
- 客户端主动 HELLO。
- 分片暂存、校验、原子 swap。
- revision delta 和跳号 resync。
- Loading/Ready/Failed/Mismatch 状态。
- SavedVariables 不覆盖服务端 owned。
- category 级降级，不因外观不可用而禁用全部页面。

完成记录：客户端现以独立 `SC2` 前缀主动握手，按类别暂存并原子提交快照，
对 revision 跳号、超时、缺片、冲突重复和旧 nonce 执行有界 resync/静默丢弃。
目录查询通过 `CollectionState.ResolveOwned` 叠加权威 owned，SavedVariables 只保存
连接诊断，不保存 owned。148 项 Python 回归、Lua 5.2 语法检查与协议 harness
通过；两套客户端部署校验均为 40/40。真实客户端账号 `admin`、角色“啊啊水电费”
首次登录和两次 `/reload` 均返回 `Ready`、revision `4`、空 synthetic 快照、
`SoloCollectionsDB.owned == nil`，且无 Lua 错误。运行 worldserver SHA-256 为
`ADDFE74CA3BA95090D31DDB797E8B91EFAEA95F57AECB119E8F3DA1B35DC5E07`。

建议提交：

```text
feat: consume authoritative SC2 collection state
```

阶段出口：

- 空收藏账号可以完成登录快照。
- `/reload` 后无需重新登录即可恢复。
- 乱序、重复、缺片和旧 nonce 不污染当前状态。
- 暂时不开放真实收藏动作也可通过协议验收。

## 11. 阶段 6：第一个完整纵切——坐骑

阶段状态：✅ 已完成（任务 6.1–6.3；2026-07-20 实机验收通过）

### 任务 6.1：生成 WotLK 坐骑候选和审核目录

状态：✅ 已完成（SoloCollections `d3b6ce4`；mod-solo-collections `f325385`）

- 从 Spell/SkillLineAbility/Creature 等当前数据生成候选。
- 只将经过规则和人工审核的条目加入正式 allowlist。
- 排除 NPC 测试法术、非玩家坐骑、重复速度版本误合并和缺失资源条目。
- 一个逻辑坐骑可以关联多个阵营/速度/角色动作来源。

输出：

- 候选报告。
- 已接受目录。
- 排除列表及原因。
- 客户端/服务端映射和 Hash。

完成记录：从当前 `3.3.5.12340` 的 `Spell.dbc`、`SkillLineAbility.dbc`、
`CreatureDisplayInfo.dbc` 和运行 World DB 提取 396 个 mount aura 候选，生成的
证据已脱敏且候选 Hash 固定为
`ba414a13d43783698251b283ccd3d19030560f44b3e3238931b83e1a73d0249e`。
审核接受 295 个玩家动作法术并按 mounted creature entry 完全一致规则归并为
281 个逻辑坐骑；101 个 NPC/测试/非玩家/旧变体条目逐项记录排除原因。目录生成器
要求 review-policy Hash 精确匹配，来源数据漂移时拒绝生成；稳定 ID、候选覆盖、
同名不同 creature 不误合并、生成确定性和客户端/服务端 Hash 一致性测试通过。
正式目录 mapping Hash 为
`50aaa024cce18a1cc7f2c903f876341a790f2c0bdb5363d6000177dc32ddf505`，
坐骑动作 mapping Hash 为
`17c52b9646bf66082de182a2e728abf664c049a2da3c69a1ccd07baf765dd91f`。

### 任务 6.2：实现坐骑解锁

状态：✅ 已完成（mod-solo-collections `5ffa2ce`；NPCBots 架构兼容修复 `993ebb8`；
跨线程运行时修复 `75d83b7`；账号隔离测试 `9cb568a`）

- `OnPlayerLearnSpell` 只处理新学习事件。
- 首次迁移在 `OnPlayerLogin` 法术加载完成后扫描已有有效法术。
- migration marker 防止每次登录反复导入。
- 遗忘法术不自动撤销账号收藏。
- 同账号所有在线角色收到一个连续 revision delta。

完成记录：生产 allowlist 已生成原生 C++ 双向索引，只有审核通过的 spellId 能映射
到 mount collectionId。`OnPlayerLearnSpell` 仅处理 Core 确认新加入 spellbook 的事件
并只发起 Grant；没有遗忘法术撤销路径。首次登录等待账号缓存 Ready 和角色法术加载
完成后，以当前角色 `HasSpell` 和同账号离线角色的 `character_spell` 合集执行一次迁移；
当前 NPCBots 字符库不含 `disabled` 列，查询以该分支实际持久化架构为准。
`sc_migration_marker` 版本命中时不再返回或扫描法术。账号内迁移和实时
学习共用单一串行 mutation 队列，每次成功提交沿用账号当前 revision + 1，并通过已有
SC2 account event sink 向所有在线 session 广播 delta。迁移全部成功/明确拒绝后才写
marker，数据库失败不会伪造完成。首轮实机登录捕获到地图工作线程读取账号缓存时触发
owner-thread 断言；账号缓存、SC2 session 和迁移状态随后改为显式互斥同步，既保留账号级
单写入语义，也允许 Player map worker 安全读取。64 项 Python 契约测试、两个 MSVC 原生
测试目标和真实 AzerothCore `worldserver` RelWithDebInfo 编译通过；最终部署构建产物
SHA-256 为
`0331077277AD373386BB56BC178EE5CED2DD441528BCE870A36C78A2743051B7`。

### 任务 6.3：实现安全召唤

状态：✅ 已完成（SoloCollections `2c1db61`；mod-solo-collections `b139237`）

- 客户端只提交逻辑 mount collectionId。
- 服务端解析当前角色动作法术。
- 检查 owned、identity、骑术、地图、室内、飞行、战斗、死亡、载具、出租飞行、战场和形态。
- 新坐骑检查成功前不卸下现有坐骑。
- 返回真实、稳定的失败 reason code。

完成记录：客户端正式坐骑目录只保留逻辑 collectionId 和展示 creatureId，不再暴露
action spellId；召唤请求固定为 SC2 `typeId=10`、逻辑 collectionId、`SUMMON` 和空目标。
服务端在 nonce、限流、重放和账号缓存检查之后才调用动作处理器，并重新核对 session
account、类型、动作和目标；客户端伪造 spellId、creatureId 或 owned 状态均不能参与解析。
服务端从生成目录选择满足当前角色种族、职业、骑术和地图限制的动作法术，并显式检查
死亡、战斗、载具、出租飞行、战场、形态和室内状态；失败返回稳定 reason code。
代码中不存在预先 `Dismount`，只有全部检查通过后才以 Core 的 mounted/vehicle 兼容触发标志
施放新坐骑。154 项客户端 Python 测试、64 项模块 Python 测试、两个 MSVC 原生测试目标、
23 个 Lua 文件语法检查和真实 AzerothCore `worldserver` RelWithDebInfo 编译通过；最终部署
构建产物 SHA-256 为
`0331077277AD373386BB56BC178EE5CED2DD441528BCE870A36C78A2743051B7`。

阶段验收：

- 同账号角色 A 解锁，在线 B 立即可见；离线 C 登录可见。
- 不同账号不共享。
- 重启后保留。
- 伪造 spellId 和 owned 状态无效。
- 不可用目标不会移除当前坐骑。

完成记录：账号 1 的离线圣骑士已有 `spellId=13819`，登录角色触发一次迁移后写入逻辑
`mount collectionId=100261`，账号 revision 提升到 5；战士角色收到 `SC2 Ready 5 true`，
但召唤按职业限制稳定返回 `CLASS_RESTRICTED`。切换到同账号圣骑士后仍收到同一 revision
和 owned 集合，召唤返回 `SUMMON true ACCEPTED` 并实际骑上军马。额外原生协议测试建立同账号
两个活动 SC2 session 和另一个账号 session，断言前两者都收到同一 delta、不同账号收不到；
真实账号库中账号 `1/2/3/5/6` 仅账号 1 存在该 unlock，未发现跨账号共享。

保持骑乘时提交带 `target=13819` 的伪造 spellId 请求，服务端返回
`SPOOF false INVALID_REQUEST`；再把客户端内存中的未拥有 `collectionId=100001` 临时改为
owned 并请求召唤，服务端返回 `FORGE false NOT_OWNED`，两次拒绝后当前坐骑均未被移除，且
临时客户端状态已清理。随后停止并重新启动同一 SHA-256 的 worldserver，端口恢复监听，
圣骑士重新登录后返回 `RESTART Ready 5 true`，数据库仍保持 revision 5 和唯一 unlock，证明
重启持久化。实机期间发现的首次登录崩溃已由 `75d83b7` 修复并重新完成全量编译、部署、
启动和角色登录验证。

建议配套提交：

```text
feat: deliver authoritative account-wide mount collection
```

## 12. 阶段 7：小宠物和玩具

### 任务 7.1：小宠物 provider

状态：✅ 已完成（SoloCollections `71ebe41`；mod-solo-collections `d53de36`；
toggle 状态修复 `0a0dc42` / `ad183c4`）

- 候选只来自 companion/critter allowlist。
- 排除猎人宠物、术士宠物、guardian 和任务临时召唤。
- 实现账号解锁、召唤、替换、同一宠物 toggle 和状态校正。
- 传送、地图切换、死亡、登出后不误操作战斗宠物。

完成记录：正式目录只接受 24 条人工审核的 companion spell allowlist，生成稳定
`collectionId=100281..100304` 的客户端/服务端目录；猎人宠物、术士宠物、guardian
和任务临时召唤没有推断或兜底入口。账号解锁复用统一 mutation 队列、revision、SC2 delta
和数据库表；召唤动作仅接受逻辑 collectionId，并由服务端解析 allowlist spell。实机在账号 1
上验证了未拥有 `100283` 返回 `NOT_OWNED` 且不影响当前宠物；`100281` 召唤座狼幼崽后，
`100282` 成功替换为烟网小蜘蛛；再次召唤同一宠物返回 `DISMISSED` 且实体消失。服务重启并
重新登录后收到 `Ready 6 true`，已有宠物收藏仍可召唤，数据库最终保存两个宠物 unlock。

建议提交：

```text
feat: add account-wide companion collection
```

### 任务 7.2：玩具 provider 和 action registry

状态：✅ 已完成（SoloCollections `71ebe41`；mod-solo-collections `d53de36`）

- 不从“存在 Use Spell”自动推断玩具。
- 人工目录声明 `SPELL_SELF`、`SPELL_TARGET`、`ITEM_USE` 或 `CUSTOM_HANDLER`。
- 每个 handler 明确冷却、目标、区域、节日、专业、战斗和材料语义。
- 传送、生成物品、经济变化和持久对象动作要求幂等/replay 防护。
- 冷却采用角色级或账号级必须由每条目录明确声明。

完成记录：首批四条显式目录分别覆盖 `SPELL_SELF`（辛多雷宝珠，`100305`）、
`SPELL_TARGET`（艾露恩的蜡烛，`100306`）、`ITEM_USE`（钓鱼椅，`100307`）和
`CUSTOM_HANDLER`（不寻常的指南针，`100308`）；每条记录独立声明 item、spell、目标、
冷却作用域和处理器，不存在从 Use Spell 自动收录的路径。动作入口在服务端完成 owned、
目录 hash、nonce、目标、冷却和 replay 校验后再执行。实机确认四条收藏把账号 revision
从 7 连续提升到 11；辛多雷宝珠产生血精灵幻象，蜡烛无目标返回 `INVALID_REQUEST`、有目标
返回 `ACCEPTED`，钓鱼椅完成施法并生成可见座椅，再次请求稳定拒绝且不生成第二个对象，
指南针返回 `ACCEPTED` 并执行旋转效果；不存在的 `100309` 返回 `INVALID_REQUEST`。
数据库最终保存四条 `typeId=12` unlock，revision 分别为 8、9、10、11。

阶段验收：✅ 已完成。155 项 SoloCollections Python 测试、71 项模块 Python 测试、两个
MSVC 原生测试目标、目录生成确定性与 hash 校验、真实 AzerothCore Release worldserver
全量编译均通过。最终部署二进制 SHA-256 为
`8ED6F6B74C1818F91D26BD201656D47EF86BF066EB9211C3C9A866C7D76DD427`；实机覆盖账号级
解锁、服务重启恢复、小宠物召唤/替换/toggle、四类玩具动作以及未拥有、缺目标、重复请求和
无效逻辑 ID 的稳定失败语义。账号 1 的 `sc_account_state.revision=11`，对应宠物与玩具六条
unlock 按 revision 6..11 连续持久化。

建议提交：

```text
feat: add explicit toy catalog and safe action handlers
```

## 13. 阶段 8：将外观完整迁入统一服务

阶段状态：✅ 已完成（任务 8.1–8.4）

### 任务 8.1：建立 `AppearanceService`

状态：✅ 已完成（`mod-solo-collections` `e5e0802`）

实现记录：旧 transmog 收藏缓存、持久化和应用行为已收口到
`Categories/Appearance/SoloCollectionsAppearanceService`；Gossip、vendor、preset、GM 命令和
最终 apply preflight 均只经过 facade，外部不再直接访问旧 `collectionCache`。独立
`AppearanceCollectionProvider` 已注册为 type 13，并保持类别级 ready/disabled 语义。

- 将已加固的 `mod-transmog` 规则、显示和持久化代码移动到 `Categories/Appearance` 与 `Transmog`。
- 所有收藏查询经过 `AccountCollectionService`。
- 移除外部对 `collectionCache` 的直接访问。
- 旧 Gossip、vendor 和命令调用统一 facade。
- 模块未 ready 时外观类别只读/禁用，其他类别继续工作。

### 任务 8.2：建立 canonical appearance

状态：✅ 已完成（`SoloCollections` `f3b9403`，`mod-solo-collections` `d241b59`）

实现记录：基于当前 world `item_template` 生成 18,190 个 canonical appearance 和 27,082 个
唯一 source item，稳定映射哈希为
`f418b28486adc98ba8b2d59fd98059a99ba31c9f44f4366189e151264a92f92b`。分组签名包含
display、归一化 slot family、item class/subclass compatibility family，并预留显式 source override
表。服务端目录采用扁平只读数组，MSVC 编译由十分钟级降至约 16 秒；客户端实机可打开
canonical 外观物品页并正常分页、筛选和预览，同一 group 只显示一条且 aliases 保留全部来源。

- 生成 `appearanceId -> source itemIds`。
- 分组至少包含 display、slot family 和 compatibility family。
- 复杂例外进入显式覆盖表。
- 当前角色使用时从已拥有 group 中选择真实且兼容的 source。
- UI 对同一 canonical appearance 只显示一条，来源仍可追溯。

### 任务 8.3：迁移旧收藏

状态：✅ 已完成（`mod-solo-collections` `d241b59`）

运行证据（账号 1，角色“啊啊水电费”）：迁移前旧表 65 条、账号 revision 11；dry-run 分类为
63 条有效 source、62 个 canonical group、1 条合并、2 条未知（不可见的戒指/饰品
`42991`、`50255`）、0 条缺模板、0 条冲突。正式迁移写入 type 13 共 62 条，revision 连续为
12..73；`sc_migration_marker` migration 3/version 1 记录 `completed_revision=73`、
`imported_count=62`、`rejected_count=2`。逐项 reconcile 证明 62 个有效 canonical group 全部 owned，
旧表 65 条完整保留且无生产写入。

- 以 `custom_unlocked_appearances` 为旧数据唯一来源。
- migration dry-run 输出：有效、合并、未知、禁用、缺模板和冲突。
- 正式迁移幂等，并写 migration marker。
- 迁移后比较旧 source item 集合与新 canonical owned 结果。
- 失败时保留旧表，不立即删除。

### 任务 8.4：统一所有解锁 hook

状态：✅ 已完成（`SoloCollections` `7e8b884`，
`mod-solo-collections` `86f3062`）

实现记录：装备、拾取、制造、实际任务奖励、vendor/store、团队掷骰和历史扫描统一进入账号级
幂等队列，最终串行调用 `AccountCollectionService::TryUnlock`；mail、trade、auction、buyback 和
GM delivery 通过共享 store hook 与 5 秒低频 inventory reconcile 收敛。可退款物品、BOP 可交易
窗口和未绑定 BoE 采用显式延迟策略；旧的“解锁全部任务选择候选”逻辑与旧表 INSERT 已删除。
SC2 apply 只接收 canonical appearanceId 和装备槽，服务端重新校验 owned、选择真实兼容 source
并执行费用/角色/目标槽检查。静态测试、Release 构建和真实客户端闭环均已通过。

运行证据（账号 1，角色“啊啊水电费”）：部署二进制 SHA-256 为
`5780649F92D8F10083051353C5182E7FF9D96D5043840C1F9250ECD8CDFD892A`。以尚未拥有的
canonical appearance `201194`（唯一 source item `2037`，脚部/锁甲兼容族）请求脚部槽位 7，
客户端返回 `SCAPPLY false NOT_OWNED`；前后 `sc_account_state.revision=73`、owned=0、audit=0，
装备 GUID 1411 无 `custom_transmogrification` 行，证明拒绝路径零副作用。随后通过真实 GM
delivery 获得 item 2037，统一 store/acquisition hook 写入 type 13、revision 74、
`source_kind=Gameplay`、`source_id=2037`、`character_guid=14` 的唯一 unlock/audit；再次请求返回
`SCAPPLY true ACCEPTED`，角色脚部模型立即变化，装备 GUID 1411 的 `FakeEntry=2037`。账号最终
type 13 共 63 条、revision 12..74 连续，重复 `(account,type,collection)` 行为 0。

- 装备、拾取、制造、任务、商店、邮件、交易、拍卖、回购、GM 和历史扫描最终进入幂等 `TryUnlock`。
- BoE、可退款和 BOP 可交易窗口采用明确绑定政策。
- 任务选择奖励只执行已确定的产品规则，不隐式解锁全部候选。

阶段验收：

- 未收藏 source 无法通过 AddOn、NPC、vendor 或普通命令应用。
- 相同显示但不同兼容族不会错误合并。
- source 从 world DB 删除不会崩溃。
- 当前角色不可用不影响账号已拥有显示。

验收结果：✅ 全部通过。AddOn 未收藏 canonical 请求已在本阶段实机返回 `NOT_OWNED` 且零副作用；
NPC/vendor/普通命令的同一安全 facade、越权拒绝和错误会话路径已由阶段 1 的真实客户端安全基线
覆盖。18,190 组目录测试验证 `(displayId, slotFamily, compatibilityFamily)` 签名唯一，并存在同
display 的多兼容族样本；`ResolveOwnedSource` 对每个运行时 `item_template` 显式空值跳过，缺失来源
只返回稳定失败而不解引用；账号 owned snapshot 与当前角色的 source 可用性分离，实机 canonical
目录可显示账号收藏，兼容 source 只在最终 apply 时解析。最终回归为 AddOn 160 项、模块 84 项全部
通过，两个工作树均保持干净。

建议提交序列：

```text
refactor: move transmog behavior behind appearance service
feat: add canonical appearance catalog
feat: migrate legacy appearance collections
feat: route appearance unlocks through collection service
```

## 14. 阶段 9：套装和玩家 Outfit

阶段状态：✅ 已完成（任务 9.1–9.3 均已完成）

### 任务 9.1：套装目录和进度

状态：✅ 已完成（`SoloCollections` `351f4bc`、`02d9457`，
`mod-solo-collections` `d6e03a6`）

实现记录：新增声明式套装源目录、稳定 ID 预留和独立生成器，首批覆盖 8 个真实 T1 套装
（logical set ID `300000..300007`）。每个成员都引用 type 13 canonical appearance，目录结构显式
保留 variant、color、difficulty、lifecycle、required、同槽替代 source 等字段；生成映射哈希为
`3f32527e1a67aa71ec878381751907258f99a1ec6dc049fce1a5caba92a8ff66`。客户端和服务端都只从
required active appearance member group 动态计算分子/分母；type 14 provider 是只读派生投影，
不会调用 `TryUnlock`，数据库也不保存 `set_collected` 或任何 type 14 unlock 行。套装列表、详情和
成员图标统一读取相同的 type 13 派生状态，替代件和重复 source 不会重复增加分母。

运行证据（账号 1，角色“啊啊水电费”）：初始 `SCSETSTATE Ready false`，战士“力量套装”列表与
详情均为 `0/8`。直接获得 item `16864` 时，因其为 60 级装备后绑定物品且当前角色仅 3 级、物品
尚未绑定，绑定策略正确延迟解锁，revision 保持 74。随后通过统一后端 GM grant 写入同一 canonical
appearance `206898`，账号 revision 变为 75，唯一持久化行为是
`(type_id=13, collection_id=206898, source_kind=GameMaster)`；`type_id=14` 行数仍为 0。SC2 delta
到达后套装列表实时变为 `1/8`。实机同时发现并修复详情旧快照问题，重载后列表、成员图标和详情
全部一致显示 `1/8`，无 Lua 错误。最终 AddOn 164 项、模块 87 项测试通过，目录 `--check`、Release
worldserver 构建和六 provider 启动注册均已通过。

- 套装成员引用 canonical appearance。
- 支持替代件、同槽多件、配色/难度变体和禁用成员。
- required appearance 作为分母，重复 source item 不增加分母。
- 套装完成度动态派生，不保存 `set_collected`。

### 任务 9.2：原子应用套装

状态：✅ 已完成（`SoloCollections` `c5adbf7`，`mod-solo-collections` `fc70a9d`）

实现记录：type 14 目录现在发布 `APPLY` action，并由 AddOn `ApplySet` 桥接到 SC2。服务端新增
`SetService`，按 logical set ID、角色 logical class 和可选 variant 解析完整套装；required member
只从账号已拥有的 type 13 canonical appearance 中选择兼容 source。HEAD/SHOULDER/SHIRT、
CHEST/ROBE、WAIST/LEGS/FEET/WRIST/HANDS/BACK、MAINHAND/OFFHAND/TABARD 均使用显式槽位映射，
未知槽、同一物理槽重复成员、缺少目标装备或不兼容 source 全部 fail closed。套装解析结果一次性进入
共享 `TryApplyCollectedAppearances` 管线；该管线统一完成目标装备、收藏授权、identity/兼容性、隐藏外观、
双手/副手、长袍/胸甲、金币和 token 预检，并且只调用一次数据库事务提交。任一预检或事务失败都发生在
扣费和运行时 fake-entry 修改之前。客户端仅在动态派生的套装完成状态为真时启用“应用套装”按钮。

运行证据（账号 1，角色“啊啊水电费”）：在力量套装保持 `1/8` 时直接调用 type 14 APPLY，返回
`SCSETAPPLY false NOT_OWNED`；金币保持 `990268`、`custom_transmogrification` 仍为原有两行
`(1410,6084)`、`(1411,2037)`，type 14 unlock 行仍为 0。随后使用正式 GM grant 临时补齐其余 7 个
canonical appearance，SC2 delta 将列表、成员和详情实时更新为 `8/8`，按钮同步启用。点击应用后，
3 级角色的锁甲目标与 60 级板甲 source 被兼容性预检拒绝，返回
`SCSETFULL false CLASS_RESTRICTED`；金币、两行既有幻化和 type 14 行数再次保持不变，证明没有部分应用
或扣费。7 个临时授权均通过正式 revoke 回滚，账号最终 revision 为 89，力量套装和按钮实时恢复为
`1/8`/禁用。AddOn 165 项、模块 89 项测试通过，目录 `--check`、Release worldserver 构建、部署哈希
`38E2B2086DDDDA9F5E1B4C3B22D1A6F98D80BC326C69A3D8AFEDFDBE4C548DAE` 和六 provider 启动注册均已通过。

- 预检全部目标槽、目标装备、source、identity、兼容性、金币和 token。
- 无目标装备的槽位不能生成装备。
- 处理双手/副手、长袍/胸甲、隐藏槽和变体选择。
- 任一失败时零扣费、零部分外观修改。

### 任务 9.3：分离 Outfit

状态：✅ 已完成（`mod-solo-collections` `859df87`）

- 新增独立 `OutfitService`，以角色 `ObjectGuid` 为唯一缓存和持久化边界；继续兼容
  `custom_transmogrification_sets`，但不引用账号 ID、`TryUnlock`、通用 unlock 表或套装派生
  provider，因此 Outfit 既不是正式套装，也不会授予收藏。
- 首版名称限制为 48 个 UTF-8 字节；拒绝空白名、控制字符和非法 UTF-8，并在写入前调用
  `CharacterDatabase.EscapeString`。旧记录加载和新记录保存都验证 Outfit ID、最多 19 个槽位、
  槽位范围、重复槽位及物品模板；无效旧记录 fail closed，不进入运行缓存。
- 保存和删除使用可确认结果的数据库事务，只有提交成功后才更新内存和扣费；原 Gossip 代码只负责
  展示和路由，不再拼接玩家输入 SQL，也不再直接维护公开 preset map。
- Outfit 应用统一调用
  `TryApplyCollectedAppearances(..., TransmogApplySource::Outfit, true)`，与正式套装复用同一套
  `PreflightApply` / `CommitApplyPlan` 原子批量管线。

运行证据（账号 1，角色“啊啊水电费”）：通过 Warpweaver 保存两槽 Outfit
`O'Brien\测试`，数据库按 UTF-8 精确保存名称（HEX
`4F27427269656E5CE6B58BE8AF95`）和 `SetData = '6 6084 7 2037 '`；退出并重新进入角色后，
Gossip 仍能显示相同名称和两个成员。验收中将原两条幻化记录可逆移动到保留 owner，确认角色登录
时两槽均无幻化，再由该 Outfit 一次应用恢复 `1410 -> 6084`、`1411 -> 2037`；应用没有额外扣费，
账号 revision 保持 89，`type_id = 14` 始终为 0。最终精确删除测试 Outfit、恢复 6 金保存费用并
重新进入角色；收尾状态为 Outfit 0 条、金币 990268、原两条幻化完整、保留 owner 0 条、revision 89、
type 14 行数 0。模块 95 项测试、CMake 重新生成、Release worldserver 构建、六 provider 启动均通过；
部署 worldserver SHA256 为
`C11D738FD5DE16702F5A1B5E5B7CF3FC69B8B28B0B6966760BB1C3BF53809755`。

- Outfit 是玩家保存方案，不是正式套装，也不授予收藏。
- 明确首版保存范围：角色级；以后若改账号级必须单独 migration。
- 名称限长、正确转义并验证槽位数量。
- 应用 Outfit 与套装共用原子 preflight/apply 管线。

建议提交：

```text
feat: derive set completion from canonical appearances
feat: apply sets and outfits atomically
```

## 15. 阶段 10：验证未来扩展合同

阶段状态：✅ 已完成（任务 10.1–10.4）

### 任务 10.1：synthetic 新职业

状态：✅ 已完成（`mod-solo-collections` `35cd087`）

实现记录：新增 `BuildClassEligibilityContext`，将 `IdentityRegistry` 的职业解析结果转换为 provider
统一消费的 capability-first 上下文，并保留稳定 `LogicalClassId`。未知 runtime ID 只生成
`IdentityKnown = false` 的空能力上下文，不注入 warrior 或任何其他 WotLK 默认职业。测试专用
`chronomancer` 不进入正式生成目录：它独立使用 logicalClassId `501`、初始 runtime ID `101`、
`class.caster` 兼容 profile 和 `class.chronomancer` 客户端资源 profile，并显式授予
`armor.cloth`、`weapon.staff`、`appearance.timeweave` 三项能力。

原生合同分别验证三项显式策略允许，`armor.plate` 拒绝，未注册 policy 返回空并 fail closed，未知
runtime `999` 不获得 warrior 能力。随后将同一 logical class 的 runtime ID 从 `101` 重映射为
`202`；旧 runtime 映射立即失效，而 logicalClassId 与 classKey 保持不变。账号缓存预先加载稳定
目录键 `(typeId=13, collectionId=260001)`，重映射后 ownership 和按类型返回的 catalog ID 均保持
不变，证明 runtime 身份不进入账号收藏主键。验证结果：模块 98 项 Python 合同测试全部通过，
原生 domain/protocol 两个 C++ 测试目标通过，Release `worldserver` 重新编译通过。

- 注册一个不属于当前 WotLK 列表的测试职业。
- 分配独立 logicalClassId、runtime 测试映射和能力 profile。
- 允许其通过能力使用明确指定的护甲/武器和外观。
- 验证未配置规则时 fail closed，而不是默认战士。
- 测试 runtime ID 改变不影响账号收藏和目录 ID。

### 任务 10.2：synthetic 新种族

状态：✅ 已完成（`SoloCollections` `ce75075`；`mod-solo-collections` `bd72dd9`）

实现记录：测试专用 `earthen` 注册为 logicalRaceId `601`、runtime ID `102`，并验证重映射为
`302` 后旧 runtime 失效且 logical identity 不变。组合资格上下文现在保留 logicalRaceId、raceKey、
factionKey 和种族能力；`earthen` 的 `ALLIANCE` 阵营与 `appearance.stoneform` 能力通过声明式策略。
身份生成器为每个种族确定性生成 `appearanceOverrideProfile`、`clientAssetVersion` 和 `modelProfile`，
新种族可覆盖默认 profile，而不需要修改类别 provider。

服务端与 AddOn 新增一致的种族展示资源解析：缺少专属镜头时返回 `global`；资源包版本不匹配、模型
缺失或贴图缺失时分别返回明确原因，并保持 preview/action 均禁用。只有版本、模型和贴图全部就绪
才启用展示和动作。客户端实现对 nil/未知 identity 与缺失 resource table 安全返回，不调用模型 API，
因此不会把缺资源升级为客户端崩溃。

验证结果：新目录 mapping hash 为
`68dc8d9b0f275bde0e56f398f2e9a1a28cee16407b2247bba835cd505e268c4e`；AddOn/目录 167 项、模块
101 项 Python 测试、两个原生 C++ 测试目标和 Release `worldserver` 构建全部通过。部署校验为
source 39、target 39、matched 40、missing/mismatched/target-only 均为 0。真实客户端 `/reload` 后无
Lua 错误；synthetic 调用依次返回 `MODEL_MISSING global false false`、
`TEXTURE_MISSING global false false` 和 `OK global true true`。

- 注册独立 logicalRaceId 和 runtime 测试映射。
- 验证阵营、外观 override、客户端资源版本和模型 profile。
- 缺少专属镜头时按 global fallback 工作。
- 缺少模型/贴图时禁用相关预览或动作，不崩客户端。

### 任务 10.3：synthetic 新收藏 provider

状态：✅ 已完成（`mod-solo-collections` `adc4baa`）

实现记录：provider descriptor 新增显式 `PERSISTED`、`DERIVED`、`EXTERNAL` 存储模式。账号服务按
模式路由：EXTERNAL 直接读取 provider 的权威状态，不要求账号缓存或通用 unlock 行；DERIVED 只读
provider 投影，不回落到同 type 的通用 unlock 行；只有运行状态为 Enabled 且存储模式为 PERSISTED
的 provider 可以进入统一 `TryUnlock` mutation。未知目录 ID、Disabled、ReadOnly、Derived 和
External 的写请求均在数据库调用前 fail closed。正式套装 provider 已明确标记为 DERIVED，继续只从
canonical appearance 计算完成度。

原生测试注册 type 30 只读 EXTERNAL provider：账号 77 可以读取 collection `300001`，同时独立
通用账号缓存中不存在该键，证明展示不依赖 `account_collection_unlock`。type 31 最小 PERSISTED
provider 复用相同账号缓存、revision `10 -> 11` 和 SC2 delta，线包包含
`type=31, revision=11, op=A, collection=310001`。另两个 provider 分别因缺依赖降级为 Disabled 和
ReadOnly，type 30/31 仍保持 Enabled，证明故障隔离。模块 105 项 Python 测试、两个原生 C++ 测试
目标和 Release `worldserver` 构建全部通过。

- 增加一个只读 EXTERNAL provider，证明不写通用 unlock 表也能显示。
- 增加一个最小账号持久化 provider，证明可以复用 unlock/revision/sync。
- 禁用 provider 后其他类别继续工作。
- provider 依赖缺失时安全降级。

### 任务 10.4：首个真实扩展类别

状态：✅ 已完成（`SoloCollections` `59998c6`、`83b5d52`；`mod-solo-collections`
`972df2e`、`c22fdb7`）

实现记录：选择方案 2“只读头衔视图”，一次只实现一个真实扩展类别。服务端注册 type `15` 的
`EXTERNAL` 只读 provider，直接复用当前角色的 Core 头衔状态；它不进入通用 `TryUnlock`，不写
`account_collection_unlock`，也不引入新的 SC2 envelope 字段。客户端在现有收藏日志框架中新增
“头衔（只读）”页，目录共 143 项，并分别显示目录可见、角色拥有、当前可用和资源已安装状态；
页面不会授予或切换头衔。

真实客户端首次对照发现服务端把 `CharTitlesEntry::bit_index + 1` 当成客户端目录 ID，导致授予
“列兵”后统一后端错位显示“下士”。现已统一以 `CharTitlesEntry::ID` 作为 canonical collection ID；
`bit_index` 仅用于 Core 的玩家已知头衔位图。修复后授予 title `1` 的探针返回
`FIX1 1 true false`：客户端已知“列兵”、provider 的 ID `1` 为已拥有、ID `2` 保持未拥有；只读页
首行显示“已拥有 / 当前可用（只读）”，次行显示“未拥有 / 当前不可用”。删除测试头衔并
`/reload` 后探针返回 `FIX0 0 false false`，临时角色数据已完全清理。

验证结果：AddOn/目录 170 项、模块 109 项 Python 测试全部通过，两个原生 C++ 测试目标通过，
catalog mapping hash 为
`9781ece5bd2d290c0b04ec9c233a5b8925fe18748f7db46a5853676b9203e86d`；RelWithDebInfo
`worldserver` 已重新生成、编译、部署并完成真实客户端验收。新类别未修改通用账号表和 SC2
envelope，满足阶段出口。

推荐二选一作为框架样板：

1. 武器附魔幻象：可验证账号解锁、外观应用和资格策略。
2. 只读头衔视图：可验证 EXTERNAL provider 和现有 Core 状态复用。

第一项更能验证动作管线，第二项风险更低。实施时一次只选一个，不同时展开。

阶段出口：

- 新类别不需要修改通用账号表和 SC2 envelope。
- 新职业/种族不需要在五个 provider 中复制数值判断。
- 真实客户端清楚区分“目录可见、账号拥有、当前可用、资源已安装”。

## 16. 阶段 11：Lua 到 C++ 切换

阶段状态：✅ 已完成（任务 11.1–11.3 已完成）

### 任务 11.1：shadow 比较

状态：✅ 已完成（`SoloCollections` `d597812`、`4c91302`；`mod-solo-collections`
`b7f3b6b`、`b432533`）

实现记录：新增显式 `Lua | Compare | Cpp` 后端模式；`Compare` 下 C++ 只加载同一账号状态和由
SC1 Lua 生成的只读目录投影，比较目录 Hash、owned ID/数量和可用性，并把结果同时写入服务端
结构化日志与 `logs/solo-collections-shadow.jsonl`。写入、动作和成功 delta 均由统一配置守卫关闭；
SC2 协议只在 `Cpp` owner 模式注册。SC1 Lua 增加启动与握手可观测日志，但不增加数据库或背包
写入路径。

真实集成构建使用 `azerothcore-wotlk/build-npcbots-clean-vs18`，同时包含 ALE、NPCBots 和当前
`mod-solo-collections`；部署二进制 SHA-256 为
`16007D36FE0AAAFBF30DFF7CDE47D31524A1E8671EDF830AFA7E54562B0D2B84`。启动日志确认
`mode=Compare writes_enabled=0 actions_enabled=0 shadow_enabled=1`，真实客户端探针返回
`SHADOW true false connected fallback`，证明 ALE SC1 是生产入口而 C++ SC2 未取得 owner。

账号 1、角色 14 登录比较得到 legacy 84 项、映射 52 项、未映射 32 项；legacy owned 47、
canonical owned 7、catalog mismatch 0、owned mismatch 29、availability mismatch 0，报告 JSON
可解析且日志明确记录 `writes=0 actions=0 success_deltas=0`。登录前后数据库快照完全一致：
`sc_account_state=1/rev89`、`sc_collection_unlock=71/rev75`、
`sc_collection_audit=91/rev89/max_audit_id91`、`sc_migration_marker=3/rev73`。AddOn/目录
171 项、模块 114 项 Python 测试通过，目录生成器 `--check`、`git diff --check` 和集成
RelWithDebInfo `worldserver` 构建通过。

- ALE Lua 保持当前生产动作 owner。
- C++ 只读同一目录和账号状态。
- 登录时比较 owned 数量、ID、目录 Hash 和可用性结果。
- 差异写入结构化日志和可导出的报告。
- shadow 模式禁止写 DB、执行动作和发送成功 delta。

### 任务 11.2：切换前演练

状态：✅ 已完成（`SoloCollections` `a2c6393`；`mod-solo-collections` `8b2c80b`）

实现记录：ALE SC1 现在读取与 C++ 相同的 `SoloCollections.Backend`，仅在 `Lua` 和 `Compare`
注册事件 30；`Cpp` 模式明确不注册 SC1。模块合同测试同时约束 C++：只有 `Cpp` 允许账号写入、
动作和 SC2，`Compare` 仅允许只读 shadow，`Lua` 不取得 C++ 生产 owner，从代码层消除双入口。

切换前备份存放于
`D:\AzerothCore_NPCBots_Clean\_codex_backups\phase11-switch-rehearsal\20260720-190728`：
auth、characters、world 必要数据共 12 个非空 SQL 文件、161344 字节，并生成逐文件 SHA-256
`manifest.json`。覆盖账号/RBAC、四张 `sc_*` 表、旧外观/幻化表、账号角色和物品，以及模块命令、
字符串、NPC 和 fake vendor item 行；运行二进制、PDB、Lua 和配置另有 `runtime-pre-matrix` 备份。

账号 1 的 `import --dry-run` 与 `reconcile --dry-run` 结果一致：legacy 65、valid 63、canonical
62、merged 1、unknown 2、disabled 0、missing template 0、conflicts 0、`writes=0`。真实服务端
依次完成三模式启动与客户端验收：`Lua` 为 `writes/actions/shadow=0/0/0`，探针
`ROLLBACK true false connected fallback`；`Compare` 为 `0/0/1`，探针
`SHADOW true false connected fallback`；`Cpp` 为 `1/1/0`，探针
`OWNER false true fallback connected`。全程任一时刻只有一个协议 owner。

从 `Cpp` 回滚到 `Lua` 后五张兼容表仍可读取，SC1 握手恢复。演练前后账号快照完全一致：
state `1/rev89`、unlock `71/rev75`、audit `91/rev89/max_audit_id91`、migration `3/rev73`；
Cpp 登录也未产生新的幂等迁移或收藏写入。AddOn/目录 171 项、模块 115 项 Python 测试、目录
生成器 `--check`、`git diff --check` 和集成 RelWithDebInfo `worldserver` 构建通过。

- 备份 auth/characters/world 必要表。
- 对账号收藏和外观旧表运行 dry-run migration/reconcile。
- 测试 Lua owner、C++ shadow、C++ owner 三种配置互斥。
- 验证回滚时 C++ 停止写入后 Lua 可以读取兼容 schema。

### 任务 11.3：单写切换

状态：✅ 已完成（`SoloCollections` `851e519`；`mod-solo-collections` `f61e300`、
`069800f`）

实现记录：生产配置已固定为 `SoloCollections.Backend = Cpp`，C++ 成为收藏、权限、revision、
同步和动作的唯一 owner。ALE 在 `Cpp` 模式不注册 SC1 生产入口；AddOn 仅对严格匹配的旧
`SC1 HELLO` 返回 `UPGRADE_REQUIRED|2`，其余旧请求不执行动作。SC2 协议在解码前验证消息，
拒绝日志只记录账号、角色和字节数，不写入任意客户端文本。

切换前运行文件备份位于
`D:\AzerothCore_NPCBots_Clean\_codex_backups\phase11-single-writer\20260720-193011`；数据库
迁移备份继续保留于 `phase11-switch-rehearsal\20260720-190728`，未删除旧兼容读取代码。最终部署
`worldserver.exe` SHA-256 为
`12CA1350AE6A109FC81D056B40B4A01B23E1086CB68B78C1AB82B25B269EDE09`。

真实客户端验收覆盖同账号两角色与第二账号：账号 1 的“啊啊水电费”和 `Arthillin`，以及账号 7
的 `Scqatest` 均返回 `SC1=false`、`SC2=true`、`upgrade_required`、`connected`。账号 1 两角色
切换时 generation 从 1 增至 2、revision 保持 89；登出后缓存归零。账号 7 登录后服务端为
`state=ready generation=3 revision=0 sessions=1`，数据库中 unlock/audit 均为 0，账号 1 的 71 条
unlock 未串入；只产生三个零导入 migration marker，证明账号隔离。

重启、断线和重新进入后 SC2 均恢复；篡改请求被记录为
`event=protocol_reject result=bad_message account=1 character=14 bytes=37`，数据库四类快照前后不变，
服务仍为 ready 且 pending 全为 0。AddOn/目录 171 项、模块 116 项 Python 测试、目录生成器
`--check`、`git diff --check` 和集成 RelWithDebInfo `worldserver` 构建通过。

- 将 C++ 设为唯一 owner。
- 停用 `server/ale/solo_collections.lua` 的生产入口。
- 旧 SC1 只返回升级提示或明确关闭。
- 完成两角色、不同账号、重启、断线和篡改请求验收。
- 稳定观察期结束前不删除迁移备份和旧兼容读取代码。

建议配套提交：

```text
feat: add read-only Lua to C++ shadow comparison
release: switch SoloCollections backend ownership to C++
```

## 17. 阶段 12：性能、监控和发布

### 任务 12.1：性能基线

服务端测量：

- 账号登录加载查询数量和耗时。
- 缓存命中、淘汰和内存占用。
- 快照分片数量和发送时间。
- 重复解锁和 transaction retry。
- 17k 级外观目录加载、筛选和应用。

客户端测量：

- 首次打开各页面。
- 搜索和翻页。
- 固定模型卡片池的帧时间。
- 分片重组和大账号收藏状态内存。
- 页面隐藏后的模型任务和 OnUpdate 是否停止。

性能验收必须基于当前真实客户端和 worldserver 记录，不以静态代码推断代替。

### 任务 12.2：诊断和健康状态

- 模块启动打印 schema、catalog、identity、protocol 和 asset versions。
- `.solocollections status` 显示 provider ready 状态、在线账号缓存和 pending 写入。
- DB 错误、目录错误、协议滥用和 provider 异常使用不同日志类别。
- 日志不输出完整大快照、密码、数据库凭据或任意客户端文本。

### 任务 12.3：发布编排

SoloCollections 发布包记录：

- AddOn commit。
- module commit。
- Core commit。
- SC2 protocol version。
- per-category mapping hash。
- asset pack version。
- SQL schema/migration version。
- SHA-256 清单。

公开发布前：

- 两仓库分别执行 clean-checkout CI。
- 不包含提取的游戏资产、客户端 EXE/DLL、数据库凭据和本地路径。
- 保留 GPL/AGPL 和第三方 notice。
- 安装文档明确 AddOn、C++ module、SQL 和客户端资源的独立边界。

## 18. 自动测试布局

### `SoloCollections`

复用并扩展：

```text
tools/collections/tests/
```

新增测试建议：

- `test_catalog_generator.py`
- `test_stable_ids.py`
- `test_identity_registry.py`
- `test_policy_contract.py`
- `test_sc2_protocol.py`
- `test_snapshot_reassembly.py`
- `test_category_registry.py`
- `test_release_compatibility.py`

继续使用：

```powershell
python -m unittest discover -s tools\collections\tests -p "test_*.py" -v
```

### `mod-solo-collections`

- 纯 ID、policy、dependency graph 和 codec 逻辑尽量与 Core 对象解耦，放入独立 CMake/CTest 测试目标。
- 需要 Player/WorldSession/Database 的部分通过当前 Core `BUILD_TESTING`/GoogleTest 接入方式或运行集成测试覆盖。
- Core hook 和数据库事务不能只靠 mock；必须保留真实 worldserver 测试角色和失败注入步骤。

最低服务端测试组：

- `CollectionIdTests`
- `ProviderRegistryTests`
- `EligibilityPolicyTests`
- `IdentityRegistryTests`
- `SC2CodecTests`
- `AccountStateMachineTests`
- `AppearanceAuthorizationTests`
- `OutfitPreflightTests`

## 19. 手工验收矩阵

| 场景 | 预期 |
|---|---|
| 同账号 A 解锁，B 在线 | B 收到连续 revision delta |
| 同账号 B 离线 | 下次登录快照包含解锁 |
| 不同账号同角色名 | 不共享 |
| 同账号双开重复解锁 | 一行 DB、一个有效 revision |
| DB 断开/死锁 | 不产生仅缓存拥有状态 |
| 快照第 N 片断线 | 不显示半份收藏，重连重同步 |
| 快照期间新解锁 | delta 在 base revision 后正确应用 |
| 目录 Hash 不同 | 对应类别禁用动作，其他匹配类别可用 |
| 伪造 spell/item/display/account ID | 无副作用并受限流 |
| 坐骑不可用 | 保留当前坐骑 |
| 小宠物切换 | 不影响战斗宠物和任务召唤物 |
| 玩具请求重放 | 不重复扣费、传送或生成物品 |
| 未收藏外观 | 所有入口都拒绝 |
| 整套一槽不合法 | 零扣费、零部分应用 |
| 新职业 runtime ID 改变 | 逻辑身份和收藏不变 |
| 新种族缺模型 profile | 安全 fallback 或禁用，不崩客户端 |
| 新 provider 被禁用 | 其他类别继续工作 |
| 17k 外观搜索和翻页 | 固定卡片池，无逐帧全量复制 |
| 服务器重启 | DB、缓存、revision 恢复一致 |

## 20. 回滚策略

每个阶段必须有明确回滚点：

- 代码：回退到上一个已编译 tag，不使用 `git reset --hard` 覆盖未确认工作。
- 数据库：新表优先采用向前兼容；破坏性 migration 延后，旧表在稳定观察期内保留。
- 协议：AddOn 支持当前版和最多一个过渡版握手，但只允许一个动作 owner。
- 目录：mapping ID 不复用；旧目录回滚后未知新 ID 保持 tombstone。
- 外观：迁移前保存旧表快照，canonical migration 先 dry-run。
- 部署：模块 junction、AddOn 副本和数据库操作分别记录；回滚不删除无关 Core module 或客户端文件。

触发回滚的条件包括：

- 出现未收藏外观越权；
- DB 提交和缓存出现不可自动 reconcile 的分歧；
- 同账号跨角色串号或不同账号共享；
- worldserver 崩溃可由目录坏条目稳定复现；
- 资源扣除后应用失败且不能事务补偿；
- 高版本资源导致客户端稳定崩溃。

## 21. 推荐执行批次

为了控制风险，实际编码按以下批次推进：

1. 阶段 0：fork 元数据、开发接入、基线编译。
2. 阶段 1：只修 `mod-transmog` P0，不加收藏功能。
3. 阶段 2-3：收藏核心、数据库和诊断。
4. 阶段 4-5：目录、身份、策略和 SC2。
5. 阶段 6：只交付坐骑真实纵切并进行实际游戏验收。
6. 阶段 7：宠物和玩具。
7. 阶段 8：外观迁移。
8. 阶段 9：套装和 Outfit。
9. 阶段 10：新职业、新种族和新 provider 扩展验证。
10. 阶段 11-12：单写切换、性能和发布。

不要同时开始坐骑、玩具、外观和高版本内容导入。每一批只有在数据库、协议、客户端和真实运行验收全部闭环后才进入下一批。

## 22. 第一轮实际执行清单

下一次开始编码时只执行以下内容：

- [x] 在 `mod-solo-collections` 记录 upstream/Core 基线和许可证归属。（`55e0cd5`）
- [x] 建立安全 module junction 脚本并验证可恢复。（`f61ac44`）
- [x] 编译基于 `33ac64b` 的 fork bootstrap 基线。（`17568dc`、`64996e4`）
- [x] 为现有收藏越权路径编写失败测试/复现测试。（`c25f3f3`）
- [x] 新增安全 `TryApplyCollectedAppearance` facade。（`c25f3f3`）
- [x] 让 vendor、Gossip 和命令入口统一调用 facade。（`c25f3f3`；当前普通命令无应用入口）
- [x] 修复空模板和临时 Item 所有权。（`4876632`）
- [x] 修复金币/token 预检和多槽部分提交。（`87f3d3e`）
- [x] 修复 reload 原子替换。（`ef07e94`）
- [x] 完成 P0 回归并打安全基线 tag。（`mod-solo-collections`
  `security-baseline` -> `17c1cdc`）

第一轮明确不做：

- 不创建完整坐骑目录。
- 不迁移账号收藏 SQL。
- 不升级 AddOn 到 SC2。
- 不导入高版本资源。
- 不移植新职业或新种族。
- 不删除原始 `mod-transmog` 参考仓库。

第一轮结束后重新审计调用图、构建结果和真实 NPC 幻化，再批准进入收藏核心实现。

## 23. 总体验收定义

只有同时满足以下条件，统一收藏后端才算完成：

- C++ 是唯一生产写入和动作后端，ALE Lua 已停止对应职责。
- 坐骑、小宠物、玩具、外观和套装使用同一账号 service、revision 和 SC2 envelope。
- 所有 AddOn/NPC/命令入口都不能绕过收藏验证。
- 数据库提交、缓存和客户端通知顺序一致，可从失败中恢复。
- 新目录条目不要求修改业务 C++。
- synthetic 新职业、新种族和新 provider 测试通过。
- 高版本资源缺失只禁用相关条目，不崩 worldserver 或客户端。
- 同账号跨角色、不同账号隔离、重启、断线、并发和篡改矩阵通过。
- 17k 级外观目录在客户端和服务端均不存在逐项对象创建和逐帧全量扫描。
- 两仓库的配套 commit、协议、目录、资源、SQL 和哈希可从干净 checkout 重建。
