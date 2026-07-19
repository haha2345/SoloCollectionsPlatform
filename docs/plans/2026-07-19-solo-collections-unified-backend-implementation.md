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

## 7. 阶段 2：统一收藏核心骨架

### 任务 2.1：引入稳定基础类型

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

### 任务 3.1：创建版本化 schema

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

实现：

- `.solocollections status`
- `.solocollections account`
- `.solocollections grant/revoke`
- `.solocollections reload`
- `.solocollections resync`
- `.solocollections import/reconcile --dry-run`

所有写命令检查 RBAC 并写审计。未知 ID、未知类别和 DB 未 ready 时安全失败。

建议提交：

```text
feat: add collection diagnostics and audited admin commands
```

## 9. 阶段 4：目录生成器和身份扩展

### 任务 4.1：建立单一目录源

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
- 同一源数据可重新生成两仓库配套输出且 diff 确定。

## 10. 阶段 5：SC2 和客户端真实状态层

### 任务 5.1：固定 wire schema 和 golden vectors

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

建议提交：

```text
protocol: define versioned SC2 wire contract
```

### 任务 5.2：实现服务端 codec 和限流

仓库：`mod-solo-collections`

实现：

- 严格字段数量、字符集、数字长度、总分片和总内存限制。
- token bucket 限流。
- nonce 和短期 replay cache。
- 多 tick 出站队列。
- 只接受约定的 AddOn whisper/self channel。
- 未 ready 时返回 LOADING，不返回空 owned 集合。

建议提交：

```text
feat: implement hardened SC2 server protocol
```

### 任务 5.3：升级客户端 Bridge

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

### 任务 6.1：生成 WotLK 坐骑候选和审核目录

- 从 Spell/SkillLineAbility/Creature 等当前数据生成候选。
- 只将经过规则和人工审核的条目加入正式 allowlist。
- 排除 NPC 测试法术、非玩家坐骑、重复速度版本误合并和缺失资源条目。
- 一个逻辑坐骑可以关联多个阵营/速度/角色动作来源。

输出：

- 候选报告。
- 已接受目录。
- 排除列表及原因。
- 客户端/服务端映射和 Hash。

### 任务 6.2：实现坐骑解锁

- `OnPlayerLearnSpell` 只处理新学习事件。
- 首次迁移在 `OnPlayerLogin` 法术加载完成后扫描已有有效法术。
- migration marker 防止每次登录反复导入。
- 遗忘法术不自动撤销账号收藏。
- 同账号所有在线角色收到一个连续 revision delta。

### 任务 6.3：实现安全召唤

- 客户端只提交逻辑 mount collectionId。
- 服务端解析当前角色动作法术。
- 检查 owned、identity、骑术、地图、室内、飞行、战斗、死亡、载具、出租飞行、战场和形态。
- 新坐骑检查成功前不卸下现有坐骑。
- 返回真实、稳定的失败 reason code。

阶段验收：

- 同账号角色 A 解锁，在线 B 立即可见；离线 C 登录可见。
- 不同账号不共享。
- 重启后保留。
- 伪造 spellId 和 owned 状态无效。
- 不可用目标不会移除当前坐骑。

建议配套提交：

```text
feat: deliver authoritative account-wide mount collection
```

## 12. 阶段 7：小宠物和玩具

### 任务 7.1：小宠物 provider

- 候选只来自 companion/critter allowlist。
- 排除猎人宠物、术士宠物、guardian 和任务临时召唤。
- 实现账号解锁、召唤、替换、同一宠物 toggle 和状态校正。
- 传送、地图切换、死亡、登出后不误操作战斗宠物。

建议提交：

```text
feat: add account-wide companion collection
```

### 任务 7.2：玩具 provider 和 action registry

- 不从“存在 Use Spell”自动推断玩具。
- 人工目录声明 `SPELL_SELF`、`SPELL_TARGET`、`ITEM_USE` 或 `CUSTOM_HANDLER`。
- 每个 handler 明确冷却、目标、区域、节日、专业、战斗和材料语义。
- 传送、生成物品、经济变化和持久对象动作要求幂等/replay 防护。
- 冷却采用角色级或账号级必须由每条目录明确声明。

建议提交：

```text
feat: add explicit toy catalog and safe action handlers
```

## 13. 阶段 8：将外观完整迁入统一服务

### 任务 8.1：建立 `AppearanceService`

- 将已加固的 `mod-transmog` 规则、显示和持久化代码移动到 `Categories/Appearance` 与 `Transmog`。
- 所有收藏查询经过 `AccountCollectionService`。
- 移除外部对 `collectionCache` 的直接访问。
- 旧 Gossip、vendor 和命令调用统一 facade。
- 模块未 ready 时外观类别只读/禁用，其他类别继续工作。

### 任务 8.2：建立 canonical appearance

- 生成 `appearanceId -> source itemIds`。
- 分组至少包含 display、slot family 和 compatibility family。
- 复杂例外进入显式覆盖表。
- 当前角色使用时从已拥有 group 中选择真实且兼容的 source。
- UI 对同一 canonical appearance 只显示一条，来源仍可追溯。

### 任务 8.3：迁移旧收藏

- 以 `custom_unlocked_appearances` 为旧数据唯一来源。
- migration dry-run 输出：有效、合并、未知、禁用、缺模板和冲突。
- 正式迁移幂等，并写 migration marker。
- 迁移后比较旧 source item 集合与新 canonical owned 结果。
- 失败时保留旧表，不立即删除。

### 任务 8.4：统一所有解锁 hook

- 装备、拾取、制造、任务、商店、邮件、交易、拍卖、回购、GM 和历史扫描最终进入幂等 `TryUnlock`。
- BoE、可退款和 BOP 可交易窗口采用明确绑定政策。
- 任务选择奖励只执行已确定的产品规则，不隐式解锁全部候选。

阶段验收：

- 未收藏 source 无法通过 AddOn、NPC、vendor 或普通命令应用。
- 相同显示但不同兼容族不会错误合并。
- source 从 world DB 删除不会崩溃。
- 当前角色不可用不影响账号已拥有显示。

建议提交序列：

```text
refactor: move transmog behavior behind appearance service
feat: add canonical appearance catalog
feat: migrate legacy appearance collections
feat: route appearance unlocks through collection service
```

## 14. 阶段 9：套装和玩家 Outfit

### 任务 9.1：套装目录和进度

- 套装成员引用 canonical appearance。
- 支持替代件、同槽多件、配色/难度变体和禁用成员。
- required appearance 作为分母，重复 source item 不增加分母。
- 套装完成度动态派生，不保存 `set_collected`。

### 任务 9.2：原子应用套装

- 预检全部目标槽、目标装备、source、identity、兼容性、金币和 token。
- 无目标装备的槽位不能生成装备。
- 处理双手/副手、长袍/胸甲、隐藏槽和变体选择。
- 任一失败时零扣费、零部分外观修改。

### 任务 9.3：分离 Outfit

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

### 任务 10.1：synthetic 新职业

- 注册一个不属于当前 WotLK 列表的测试职业。
- 分配独立 logicalClassId、runtime 测试映射和能力 profile。
- 允许其通过能力使用明确指定的护甲/武器和外观。
- 验证未配置规则时 fail closed，而不是默认战士。
- 测试 runtime ID 改变不影响账号收藏和目录 ID。

### 任务 10.2：synthetic 新种族

- 注册独立 logicalRaceId 和 runtime 测试映射。
- 验证阵营、外观 override、客户端资源版本和模型 profile。
- 缺少专属镜头时按 global fallback 工作。
- 缺少模型/贴图时禁用相关预览或动作，不崩客户端。

### 任务 10.3：synthetic 新收藏 provider

- 增加一个只读 EXTERNAL provider，证明不写通用 unlock 表也能显示。
- 增加一个最小账号持久化 provider，证明可以复用 unlock/revision/sync。
- 禁用 provider 后其他类别继续工作。
- provider 依赖缺失时安全降级。

### 任务 10.4：首个真实扩展类别

推荐二选一作为框架样板：

1. 武器附魔幻象：可验证账号解锁、外观应用和资格策略。
2. 只读头衔视图：可验证 EXTERNAL provider 和现有 Core 状态复用。

第一项更能验证动作管线，第二项风险更低。实施时一次只选一个，不同时展开。

阶段出口：

- 新类别不需要修改通用账号表和 SC2 envelope。
- 新职业/种族不需要在五个 provider 中复制数值判断。
- 真实客户端清楚区分“目录可见、账号拥有、当前可用、资源已安装”。

## 16. 阶段 11：Lua 到 C++ 切换

### 任务 11.1：shadow 比较

- ALE Lua 保持当前生产动作 owner。
- C++ 只读同一目录和账号状态。
- 登录时比较 owned 数量、ID、目录 Hash 和可用性结果。
- 差异写入结构化日志和可导出的报告。
- shadow 模式禁止写 DB、执行动作和发送成功 delta。

### 任务 11.2：切换前演练

- 备份 auth/characters/world 必要表。
- 对账号收藏和外观旧表运行 dry-run migration/reconcile。
- 测试 Lua owner、C++ shadow、C++ owner 三种配置互斥。
- 验证回滚时 C++ 停止写入后 Lua 可以读取兼容 schema。

### 任务 11.3：单写切换

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
- [ ] 为现有收藏越权路径编写失败测试/复现测试。
- [ ] 新增安全 `TryApplyCollectedAppearance` facade。
- [ ] 让 vendor、Gossip 和命令入口统一调用 facade。
- [ ] 修复空模板和临时 Item 所有权。
- [ ] 修复金币/token 预检和多槽部分提交。
- [ ] 修复 reload 原子替换。
- [ ] 完成 P0 回归并打安全基线 tag。

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
