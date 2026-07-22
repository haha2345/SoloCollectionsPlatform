# WotLK companion 目录审核、生成与真实客户端验收

日期：2026-07-22  
阶段：Round Two / 阶段 6  
结论：通过

## 1. 阶段结论

本阶段把原有 24 条人工 companion 样本升级为固定证据、逐项审核、稳定 ID、Lua/C++ 双投影和真实客户端闭环的正式目录：

- SkillLine 778：205 个法术；
- 正向 `SPELL_EFFECT_SUMMON`：203 个法术；
- 按精确 Creature Entry 合并后：201 个候选；
- 资源就绪候选：201；
- 审核结论：accepted 201、excluded 0、deferred 0；
- 正式 companion 数量：201；
- 原 24 条 `100281..100304` 的 collection ID 与 key 全部保留；
- 新增 177 条由 registry append-only 分配为 `100309..100485`，没有占用 toy 的 `100305..100308`；
- 新 reservation ordinal 为 `18507..18683`；
- 正式 AddOn/module mapping hash：`5c104b479934bd17a1eb7cf26fa64a9eb284d5a6b22c605d0a57b04e3df22ffd`。

证据提取基于当前部署匹配的 3.3.5.12340 客户端 DBC、当前 World DB 与已命名 evidence pack；原始客户端资产仍只位于 F 盘 evidence 目录，不进入 Git。

## 2. 提取与审核

提取器 `tools/catalog/companion_catalog.py` 提供 `extract/generate/check` 三个显式动作：

- `extract` 读取 `Spell.dbc`、`SkillLineAbility.dbc`、`SpellIcon.dbc`、`CreatureDisplayInfo.dbc` 与 World DB；
- 只按 SkillLine 778、正向 summon effect 和精确 Creature Entry 建立候选；
- 名字只用于展示，不参与 identity 合并；
- 每个候选必须在 review policy 中得到 accepted/excluded/deferred；
- candidate hash 或 evidence pack hash 漂移时，`check` fail closed；
- `generate` 同时维护 collection source、action schema、presentation、稳定 ID、候选/排除 CSV 与 Lua/C++ 投影。

本轮 candidate hash：

```text
a6eed7c0c62af9c34b509b6e663c8423b4bf093240c5f6a7c7943f77d49c61af
```

命名 evidence pack `round2-20260722-stage6-companions` 的 pack hash 为 `d105efd20fd8ed64e94ad0a078f2fe3d37f1a62dcd1d1ef3381c2cec900d4e14`；`check --evidence-root` 会同时验证 manifest、四个 DBC Hash、review policy 和候选/排除 CSV。

两条 SkillLine 记录没有正向 summon effect，因此在进入候选池前明确拒绝：spell 17468（Pet Fish）和 17469（Pet Rock）。201 个正式候选均有当前 World template、Display 资源、原生 icon、canonical spell、至少一个 unlock spell，审核中未发现职业战斗宠物、guardian、任务临时召唤或测试/废弃 identity。

关键审核文件 SHA-256：

| 文件 | SHA-256 |
|---|---|
| `catalog/review/companions/evidence.json` | `e8e06380fe51ce249a7875e5ea9796be1d1b6cc542dd81dc077ffa7120e34f20` |
| `catalog/review/companions/review-policy.json` | `106e8130e42120b1f181826d9e8fe5ff3795645d989199fabbbe667f63ce3dac` |
| `catalog/generated/companion-candidates.csv` | `4eb8b0d3df078b4de09dd782e64375905303221fd16a4fa77746dff2be9aa5d5` |
| `catalog/generated/companion-exclusions.csv` | `929bbd7cd4a4ea1e1f03237599426d4b93cd9e3cf915609366e84ab9628c680c` |

## 3. Action schema v2

`catalog/source/companion_actions.json` 已升级为 schema 2。每条记录显式包含：

```text
canonicalSpellId
unlockSpellIds
previewCreatureEntry
catalogLifecycle
uiLifecycle
```

服务端 `FindBySpell()` 索引全部 unlock variants；登录迁移检查全部 variants；召唤只使用审核后的 canonical spell。两个重复 spell identity 为：

| collection | Creature Entry | canonical | unlock variants |
|---|---:|---:|---|
| `100339 companion.spotted_rabbit` | 7559 | 10712 | 10712, 35157 |
| `100373 companion.murki` | 15361 | 25018 | 24987, 25018 |

action source SHA-256：`c89727c9b011e15e841e4721f8fcce17875947a6b2af13eb23c1edbc7329a316`。生成器、C++ catalog、登录迁移和 summon service 都对 canonical 必须属于 unlock variants、spell 不得跨 identity 重复、preview entry 必须精确一致执行 fail-closed 校验。

## 4. 生成与编译门槛

只读生成检查全部通过：

```text
companion review: candidates=201 accepted=201 excluded=0 deferred=0
creature presentation hash: 2bdb261203a9377c14fdde676c5a1307a28fa96bd4a440712289b10fab003d91
catalog mapping hash: 5c104b479934bd17a1eb7cf26fa64a9eb284d5a6b22c605d0a57b04e3df22ffd
```

回归结果：

- AddOn Python contracts：222 项通过，2 项按既有可选本地条件跳过；命名 companion evidence pack 校验已实际启用；
- SoloCam Python contracts：34 项通过，9 项按既有可选本地条件跳过；
- module Python contracts：130 项通过；
- module native：2/2 通过；
- Lua 5.1：32 个 tracked Lua 文件全部通过；
- 当前固定 clean Core 的 x64 RelWithDebInfo `worldserver` 构建通过；
- 构建产物和实际部署 `worldserver.exe` SHA-256 均为 `70e3346d29b28f1c7992d32ec8b79516fc9626db1dff2098813e908fb86db1da`。

## 5. 冷/热缓存全目录扫描

RuntimeAudit 不再硬编码 24/305，而是从生成目录读取 mount/companion 数量和 mapping hash。冷、热缓存各执行一次受限速扫描；每条都要求 SC2 PREVIEW 返回 `ACCEPTED`、`PlayerModel:GetModel()` 连续稳定、generation probe 丢弃过期回调。

| 运行 | mount | companion | READY | failed | CSV SHA-256 |
|---|---:|---:|---:|---:|---|
| cold `20260722-072127-165` | 281 | 201 | 482 | 0 | `5540169210b4a98d7b888d8f924654d0a4ee2f91d5540cbcedf007f10267fb17` |
| hot `20260722-072552-718` | 281 | 201 | 482 | 0 | `cefb11c764cb67f2114ac58bff6a5582e38fc5a5fe463765de57a322cbb55ae5` |

运行目录：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage6-companions\cold\20260722-072127-165
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage6-companions\hot\20260722-072552-718
```

测试前 `Cache/WDB/zhCN` 已由 append-only journal 备份；完成后状态为 `RESTORED`，测试生成 WDB 被移动到 F 盘 quarantine，原缓存逐文件 Hash 验证恢复。RuntimeAudit QA AddOn 也已移到 F 盘隔离目录，原 SavedVariables 已恢复。

## 6. UI、动作和生命周期实机验收

真实客户端打开 companion 页后：

- 顶部截图显示 `1-12 / 201`；
- 滚动到底截图显示 `201-201 / 201`；
- 最后一条模型正常渲染，旧 24 条不再是对象池或滚动上限。

截图证据：

| 截图 | SHA-256 |
|---|---|
| `WoWScrnShot_072226_074313.jpg` | `83b629bea34af2db1df265b98cb01c3dcec7b4f444f045933ab17e1368ade00c` |
| `WoWScrnShot_072226_074319.jpg` | `36916d62a865d0febbf93423d9621efca6f1ee4e95b21b8d563221da4cac61e4` |

结构化服务端动作日志确认：

- 未收藏 PREVIEW 可用，而 summon 仍受 owned 校验；
- `100339` 首次 summon 为 `ACCEPTED spell=10712`，再次点击为 `DISMISSED`；
- 再次召唤 `100339` 后切换 `100373`，后者为 `ACCEPTED spell=25018`；
- 跨地图传送后 `100373` 重新召唤为 `ACCEPTED`，没有把旧 GUID 误判为 toggle；
- 死亡时动作返回 `DEAD`；服务端复活后重登恢复为 `ACCEPTED`；
- 登出、另一个同账号角色、worldserver 重启后，revision/owned 均恢复且只使用 canonical spell；
- 两条测试 grant 在 DB 中只出现于 account 1，不泄漏到其他账号；
- 最终 revoke 后 `residual_test_unlocks=0`，没有留下测试收藏。

F 盘证据：

```text
runtime-audit\stage6-companions\actions\server-action-audit.log
  SHA-256 e5fc2edac4b0c2cc00abbfbaaeac46f8423c8fdf67da0f130b6bb0eb7683bf72
runtime-audit\stage6-companions\actions\account-isolation-before-cleanup.tsv
  SHA-256 67bb908904cd15a456f306f290e3df13c019447b25fb4a24624672e9417650f8
runtime-audit\stage6-companions\actions\cleanup-verification.tsv
  SHA-256 f8b790e498075643b3566d2b6892d36bd5e7cdd1a8444f6326e157bddf8a6e12
```

## 7. 阶段出口

阶段 6 的候选覆盖、schema v2、稳定 ID、双仓库生成、原生服务端、冷/热缓存、完整滚动、canonical/toggle/替换、地图、死亡、重登、重启和账号隔离均已闭环。正式数量由实际 evidence hash 和审核接受数决定，不把 201 当作永久常量。
