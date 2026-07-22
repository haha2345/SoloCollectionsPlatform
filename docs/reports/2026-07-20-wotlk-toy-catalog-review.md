# WotLK 玩具目录审核、动作扩充与真实客户端验收

日期：2026-07-22  
阶段：Round Two / 阶段 7  
结论：通过

## 1. 阶段结论

本阶段把旧 `Toys.lua` 的 36 条原型升级为固定证据、逐项审核、稳定 ID、Lua/C++ 双投影和真实客户端闭环的正式目录：

- 审核池：36；
- accepted：9；
- deferred：27；
- excluded：0；
- 原有 4 条 `100305..100308` 的 collection ID、key 和动作语义保持不变；
- 新增 5 条为 `100486..100490`，ordinal 为 `18684..18688`；
- 正式数量由审核接受数决定，没有把 4 或 36 写成永久合同；
- catalog mapping hash：`7685657b8a7a4d5e8e7c873c98fb793289151668231a2239c967424b960331d5`。

36 个候选的客户端 item/display 资源均存在，但资源存在没有被当成动作安全证明。传送、经济、生成物品、持久世界对象、材料、节日、区域和复杂战斗语义均保持 deferred。

## 2. 证据与审核器

`tools/catalog/toy_catalog.py` 提供 `extract/generate/check` 三个显式动作，并执行以下 fail-closed 校验：

- 输入必须是命名 evidence pack，Windows 下 evidence root 必须位于 F 盘；
- 固定 `Spell.dbc`、`Item.dbc`、`ItemDisplayInfo.dbc` 和 World DB 快照证据；
- 36 个候选逐项要求 accepted/excluded/deferred 和非空理由；
- accepted 记录必须完整声明 unlock、action、target、cooldown、replay、risk 和 lifecycle；
- candidate hash、review policy、生成 CSV、DBC Hash 或 evidence pack canonical hash 漂移均拒绝生成；
- 重新打包后的 evidence 必须能反向核对 Git 中审核文件。

候选 hash：

```text
4b7ba78809fd3e7f4bdafd48f880138c4db5359cc429dc74da82b3c74982496d
```

最终命名证据包：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-addon\_work\evidence\round2-20260722-stage7-toys-v2
canonical pack hash: 1331607af39fc61398fa49da9fbda7f9044b56476721310aa02feff52ba2e221
files: 94
```

首个 `round2-20260722-stage7-toys` 包暴露了再次打包时 `extract/` 前缀被剥离的问题。该包按 append-only 证据规则保留但不再作为生成输入；`New-RoundTwoEvidencePack.ps1` 已改为保留已规范化的 `extract/` 路径，v2 包已通过完整反向校验。

关键审核文件 SHA-256：

| 文件 | SHA-256 |
|---|---|
| `catalog/review/toys/evidence.json` | `0d1f9e7dc3ef551a1459548143c0030329413d1e10ef164470347eefb0edcd1c` |
| `catalog/review/toys/review-policy.json` | `408e48691cac13f7d54da978f09dd0e1a758a804139f3d0026fa835f6e8c505e` |
| `catalog/generated/toy-candidates.csv` | `2d19285c66727d9cc5316577982f8ff60637dc9d394ee77486b40bc440aa02e3` |
| `catalog/generated/toy-exclusions.csv` | `5c7a4fa220db2402760579df617c49a54886fc6c9563dfda3742e73d47a99207` |
| `catalog/source/toy_actions.json` | `bfcfbca5b0247f605cc69127978ec30ce459fda249f526ea08e046ea88ce6c21` |

## 3. 正式动作清单

| collection | item | spell | action | target | cooldown |
|---|---:|---:|---|---|---|
| `100305 toy.orb_of_the_sindorei` | 35275 | 46354 | SPELL_SELF | SELF | CHARACTER |
| `100306 toy.elunes_candle` | 21713 | 26374 | SPELL_TARGET | REQUIRED_UNIT | CHARACTER |
| `100307 toy.fishing_chair` | 33223 | 42766 | ITEM_USE | SELF | HANDLER_NATIVE |
| `100308 toy.unusual_compass` | 45984 | 64385 | CUSTOM_HANDLER | SELF | ACCOUNT 5s |
| `100486 toy.decahedral_dwarven_dice` | 36863 | 47770 | SPELL_SELF | SELF | ACCOUNT 10s |
| `100487 toy.super_simian_sphere` | 37254 | 48332 | SPELL_SELF | SELF | ACCOUNT 3600s |
| `100488 toy.iron_boot_flask` | 43499 | 58501 | SPELL_SELF | SELF | ACCOUNT 3600s |
| `100489 toy.titanium_seal_of_dalaran` | 44430 | 60458 | SPELL_SELF | SELF | ACCOUNT 10s |
| `100490 toy.muradins_favor` | 52201 | 73320 | SPELL_SELF | SELF | ACCOUNT 1800s |

所有记录以 `ITEM_ACQUIRED` 解锁，第一批全部 `consumesMaterial=false`、`catalogLifecycle=ACTIVE`、`replayPolicy=REJECT_DUPLICATE`。唯一 custom handler 是已编译的 `unusual_compass`；C++ 构造器对未知或缺失 handler fail closed。客户端只发送 logical collection ID 和当前目标是否存在，spell、item、target policy、cooldown 和 handler 均由服务端目录解析。

## 4. 自动化、原生构建与 clean Core

回归结果：

- AddOn Python contracts：226 项通过，2 项按既有可选条件跳过；
- module Python contracts：130 项通过；
- module native：2/2 通过；
- SoloCam Python contracts：34 项通过，9 项按既有可选条件跳过；
- `generate_catalog.py --check` 使用 stage7 v2 evidence 成功，精确输出 36/9/27/0；
- evidence pack contracts：3 项通过；
- AddOn/module `git diff --check` 通过；
- clean Core x64 Release `worldserver.exe` 构建通过：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\build\round-two-core\bin\Release\worldserver.exe`；
- 最终客户端 `/reload` 成功，验证 `Toys.lua` 宏图标兼容修复可被 3.3.5 Lua 运行时加载。

合同覆盖完整 schema、重复 item/collection、未知 handler、target policy、冷却、未拥有、死亡/载具/战斗、获取幂等、旧四条无漂移和目录数量不固定为 4。

## 5. 真实客户端与服务端动作验收

运行证据位于：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage7-toys
```

真实运行结果：

- grant 前新增 5 条全部返回 `NOT_OWNED`；客户端伪造 collected 不能越过服务端授权；
- 逐件 `.additem` 触发唯一账号 mutation，revision 从 109 连续至 113；重复获得 item 36863 没有第二次 mutation；
- 新增 5 条首次均 `ACCEPTED`，立即重放均 `COOLDOWN`；
- 旧 Orb、Candle、Fishing Chair、Unusual Compass 四条逐项成功；Candle 缺失/无效目标失败，合法目标成功；
- 长账号冷却经过重登仍生效；worldserver 重启后 owned 从数据库恢复；
- 同账号第二角色可使用，数据库证明新 unlock 只属于 account 1；
- Fishing Chair 仍要求角色实际持有 item，收藏状态不会凭空生成或绕过物品使用；
- 生产目录显示 9/9；临时 QA 目录证明 20 条下的 18/页、最后 2 条、搜索、右键菜单和 `/reload`；QA AddOn 测完后已禁用并移到 F 盘证据目录；
- 真实拖放创建动作栏宏成功。3.3.5 客户端拒绝 `GetItemIcon()` 返回的路径作为 `CreateMacro` 图标，因此实现先尝试 item icon，再以数值图标 1 兼容回退；动作栏测试后宏和 slot 均已清理。

代表截图 SHA-256：

| 截图 | SHA-256 |
|---|---|
| `production-after-reload.png` | `9d03b0f1dd351165d35b3ff8044c1d382b166f2c1eacc25285fd6ae08faf7fad` |
| `qa-page1-18-of-20.png` | `550c175a05d034fe3bc6c86aa250db0259b8383875087104ec173ca2754a6c26` |
| `qa-page2-last-2-of-20.png` | `d651c197f4edaed3c476df6f858221dee9232ac51e9e8aa40f7cdbf71d693a9b` |
| `qa-search-single-result.png` | `e389e0a137ab6da186f3c275e946ab0cb0aa177391945b3742eb7ba4f1f371ee` |
| `qa-context-menu.png` | `4346751164d5e5f929ee5923f92d0dea07f0ecdb7ef15aa14b6a36b6522d70c9` |
| `unowned-not-owned.png` | `38912f96e033ade92da8af773ad649aabd8d25e2c63428f6a4f61e9e2d9fa705` |
| `new-toy-actions-and-cooldowns.png` | `4796ece138dab28c143a5cebc2b0ae79f2d919bc665374e821f8255aa294a24f` |
| `toy-grid-owned-9.png` | `e53ae53ed006975801b448c7a8b8dc78ca18c1102b8511be5f9c2c642da603ba` |

## 6. 清理与阶段出口

测试物品已用精确负数量移除，新增 5 条 unlock 已经由权威 `.solocollections revoke` 撤回。最终状态：

```text
account cache revision=126 pending_deltas=0
NEW_UNLOCK_ROWS=0
ORIGINAL_UNLOCK_ROWS=4
TEST_ITEMS=0
client progress=4/9
```

`cleanup-verification.txt` SHA-256 为 `c6f6220fabe94b621ea7b530f9cac8824a4d868725b80af6273e3e16fba7f4c1`。旧 36 条审核池满足 `accepted + excluded + deferred = 36`；现有 4 条无回归；新增 5 条均有完整 schema、自动测试、真实客户端证据和清理闭环；高风险及语义不完整项目全部保持 deferred。
