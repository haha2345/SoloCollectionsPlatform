# SoloCollections 第二轮整改与扩展审计基线

审计日：2026-07-22（Asia/Shanghai）

本报告冻结行为修改前的数据、工具链、客户端资产和空 WDB 失败表现。报告不包含数据库凭据、客户端二进制、DBC/M2/BLP/MPQ/WDB 内容、数据库转储或个人客户端绝对路径。

## 1. 仓库与运行基线

| 组件 | 审计 commit | 说明 |
|---|---|---|
| SoloCollections 原实施基线 | `5c47e6e` | 第一轮统一后端收口提交 |
| SoloCollections 审计工作头 | `1f8ce29` | 已加入可恢复空 WDB 工作流，尚未修改收藏行为 |
| mod-solo-collections | `c7504c3` | 第二轮模块工作树的起点 |
| AzerothCore | `4cc67a316d2bec9faf27c3392634282e70cacbe0` | 当前静态模块 Core 基线 |

当前运行配置为 `SoloCollections.Backend = Cpp`。运行中的静态模块 `worldserver.exe` 为 x64，SHA-256 为 `8cdad8fc572b116feb0f347bbe97f6f2a9de2ea33b7e9c29fe325ba8bd0e8683`；其版本字符串包含 Core commit `4cc67a316d2b`。Core 构建缓存合同为 `Visual Studio 18 2026`、`x64`、`MODULES=static`、`SCRIPTS=static`。

客户端 build 为 `3.3.5.12340`，locale 为 `zhCN`。部署插件的 `SoloCollections.toc`、`Core/Bridge.lua`、`UI/Mounts.lua`、`UI/Pets.lua` 和 `Data/Generated/Catalog.lua` 均与上述 AddOn 基线逐文件同 Hash。

## 2. 目录版本、数量与 Hash

`catalog/source/versions.json` 冻结为：

- `metadataVersion`: `2026.07.20.2`
- `assetPackVersion`: `wotlk-3.3.5a-local-1`
- `policyVersion`: `1`
- `protocolVersion`: `1`

正式目录共 18,507 条：281 坐骑、24 宠物、4 玩具、18,190 外观、8 套装。第二轮开始时要求保持的正式烟雾分母为 `281/24/4/8`。

| 证据 | SHA-256 / mapping hash |
|---|---|
| `catalog/generated/catalog-manifest.json` | `6552ea6efd23f68bdf3c1a7f8ac13049adf8a241b4686ac470756544f6a668ff` |
| 全目录 mapping hash | `9781ece5bd2d290c0b04ec9c233a5b8925fe18748f7db46a5853676b9203e86d` |
| mount type mapping hash | `6801854cfc6bd1107424d0910a66183bfee100f328d6f468d8a4007f8b7e54b9` |
| companion type mapping hash | `e854b1b83a01f3f1672a0907099c5f912caab741bba304c2660c0ccbf0bb9efc` |
| toy type mapping hash | `b7d2d5feecc85d98de6f97c12851938514d6020997ed62a40be80cfa007ecfb5` |
| appearance type mapping hash | `ac32696a412e0667392840518e10f025bbd5de36311cd16d29c2f43518202e53` |
| set type mapping hash | `3b4c4653b4b118bdb7c5ebb6727a7cdfedd4826044f16c09c4a5c752edb8a9ad` |
| `catalog/source/mount_actions.json` | `7eee961423d300cb7952f1fdc87e46fdb2c010386e615794e4b66991c1e49fa4` |
| `catalog/source/companion_actions.json` | `b49661d2544b97c21da10c51aa72e224a28d0bf093c8e069fcab00a1c4d4dfba` |
| mount review evidence | `5f5db38a2a9b7e3934681b479023a2e50d14e0374764902f3d7fcfa21d7f0fe4` |
| mount candidate hash（396 条） | `ba414a13d43783698251b283ccd3d19030560f44b3e3238931b83e1a73d0249e` |

冻结的 mount World/DBC 查询合同为 `mount-catalog-exact-entry-v1` / `EXACT_CREATURE_ENTRY_ONLY`。World 来源只记录为 runtime World DB，凭据已省略，未复制数据库转储。该历史候选证据使用的 DBC Hash 为：

| DBC | SHA-256 |
|---|---|
| CreatureDisplayInfo.dbc | `1f1a4f5d9d8ed1af1a0be65e8171ed962f2c3e12e213de748e2850515bd3f68b` |
| SkillLineAbility.dbc | `b7c054a6efa2d9f7ffe853756f7c0ad7a6d98fe6ff545a46dc61cc98768bccd0` |
| Spell.dbc | `7d269a6bd3ce5a55ca255a76e5a34595771ec3546ba192f9b1de6ff61b4aca0c` |

实际 evidence pack 还固定了当前客户端可见的 9 个 DBC 输入：

| DBC | SHA-256 |
|---|---|
| ChrRaces.dbc | `32aceb7165030764e048ef596ecd99eea582b6a11edca3933a069fbb6a5adbf6` |
| CreatureDisplayInfo.dbc | `1f1a4f5d9d8ed1af1a0be65e8171ed962f2c3e12e213de748e2850515bd3f68b` |
| CreatureModelData.dbc | `8ad2af18b3266f81043fed2d3a7c248d1b3c0c746d8d0b2b80f85962a1ca9f88` |
| Item.dbc | `d455bc30b59bc368b2a972a913864dd092d50695140b9513582100dc56ed777d` |
| ItemDisplayInfo.dbc | `42d2c67fb12cb79e1e62fee2839f5f8f8239abe4ecfd45ed6fee1021642d19bc` |
| ItemSet.dbc | `ca290f7d828e859c2816421b4631cc5caad224f18a2e1e7ae74005a01c0bf50f` |
| SkillLineAbility.dbc | `4154b833d6a26b9b9ce53851d56cb594f0813c0936a72ec89f933cc69abe42c3` |
| Spell.dbc | `df44e75ef1730e363dc06f1bc5ae064299b08d2d0047e663c0a1782ed4c8d10f` |
| SpellIcon.dbc | `2b12326641dba1554878b3f53c993e1211e50b3839ccdbeca378a23e7b3248db` |

历史候选证据和当前客户端 DBC 中 `SkillLineAbility.dbc`、`Spell.dbc` 的 Hash 不同，因此后续生成器不得混用这两套输入。

## 3. 固定 evidence pack 与工具链

最终 evidence ID 为 `round2-20260722-baseline-v2c`，包含 86 个输入，pack Hash 为 `dde997dcf72e087c3baf159d6a9ddbd268d2c983f312f8d223c389658b116720`，`evidence-manifest.json` SHA-256 为 `c452bc0da890eceda84a33953ec0131078a5e65932eec521d145a0ecf555dcc8`。

pack 只使用相对路径，并明确记录 `credentialsIncluded=false`、`databaseDumpIncluded=false`、`absoluteSourcePathsIncluded=false`。已验证武器清单是命名成员 `weapon-resources/weapon-creature-build.json`，SHA-256 为 `7c866d9384d80ee20fcf3c06d08b8445647a0e5899675cbee46b3cc3f815368c`；其源路径已转换为 pack 内可移植相对路径。完整工具版本与 Hash 见 [2026-07-20-round-two-toolchain-manifest.json](2026-07-20-round-two-toolchain-manifest.json)。

## 4. 21 个独立武器快照

下表固定旧记录 ID 50–70 的 itemId、synthetic display ID、独立 M2 路径与相机 key。

| 记录 | itemId | display ID | M2 path | camera key |
|---:|---:|---:|---|---|
| 50 | 19364 | 40000 | `Item/ObjectComponents/SoloCollections/SC_Sword_2H_Blackwing_A_02_19364.m2` | `TWO_HAND_SWORD` |
| 51 | 19019 | 40001 | `Item/ObjectComponents/SoloCollections/SC_Sword_2H_Ashbringer02_19019.m2` | `TWO_HAND_SWORD` |
| 52 | 32837 | 40002 | `Item/ObjectComponents/SoloCollections/SC_Glave_1H_DualBlade_D_02_32837.m2` | `WAR_GLAIVE_MAINHAND` |
| 53 | 32838 | 40003 | `Item/ObjectComponents/SoloCollections/SC_Glave_1H_DualBlade_D_02left_32838.m2` | `WAR_GLAIVE_OFFHAND` |
| 54 | 32375 | 40004 | `Item/ObjectComponents/SoloCollections/SC_Shield_2H_OutlandRaid_D_06_32375.m2` | `SHIELD` |
| 55 | 50737 | 40005 | `Item/ObjectComponents/SoloCollections/SC_Axe_1H_IcecrownRaid_D_01_50737.m2` | `ONE_HAND_AXE` |
| 56 | 50709 | 40006 | `Item/ObjectComponents/SoloCollections/SC_Axe_2H_IcecrownRaid_D_02_50709.m2` | `TWO_HAND_AXE` |
| 57 | 50638 | 40007 | `Item/ObjectComponents/SoloCollections/SC_Bow_1H_IcecrownRaid_D_01_50638.m2` | `BOW` |
| 58 | 50444 | 40008 | `Item/ObjectComponents/SoloCollections/SC_Firearm_2H_Rifle_IcecrownRaid_D_01_50444.m2` | `GUN` |
| 59 | 50734 | 40009 | `Item/ObjectComponents/SoloCollections/SC_Mace_1H_IcecrownRaid_D_04_50734.m2` | `ONE_HAND_MACE` |
| 60 | 50603 | 40010 | `Item/ObjectComponents/SoloCollections/SC_Mace_2H_IcecrownRaid_D_01_50603.m2` | `TWO_HAND_MACE` |
| 61 | 50735 | 40011 | `Item/ObjectComponents/SoloCollections/SC_Polearm_2H_IcecrownRaid_D_01_50735.m2` | `POLEARM` |
| 62 | 32466 | 40012 | `Item/ObjectComponents/SoloCollections/SC_Sword_1H_Crystal_C_02_32466.m2` | `ONE_HAND_SWORD` |
| 63 | 33350 | 40013 | `Item/ObjectComponents/SoloCollections/SC_Sword_2H_Frostmourne_D_01_33350.m2` | `TWO_HAND_SWORD` |
| 64 | 50731 | 40014 | `Item/ObjectComponents/SoloCollections/SC_Stave_2H_IcecrownRaid_D_02_50731.m2` | `STAFF` |
| 65 | 50692 | 40015 | `Item/ObjectComponents/SoloCollections/SC_Hand_1H_IcecrownRaid_D_02Right_50692.m2` | `FIST_WEAPON` |
| 66 | 50736 | 40016 | `Item/ObjectComponents/SoloCollections/SC_Knife_1H_IcecrownRaid_D_03_50736.m2` | `DAGGER` |
| 67 | 50474 | 40017 | `Item/ObjectComponents/SoloCollections/SC_Thrown_1H_Shuriken_A_02_50474.m2` | `THROWN` |
| 68 | 50733 | 40018 | `Item/ObjectComponents/SoloCollections/SC_Bow_2H_Crossbow_IcecrownRaid_D_01_50733.m2` | `CROSSBOW` |
| 69 | 50631 | 40019 | `Item/ObjectComponents/SoloCollections/SC_Wand_1H_IcecrownRaid_D_02_50631.m2` | `WAND` |
| 70 | 43651 | 40020 | `Item/ObjectComponents/SoloCollections/SC_Misc_2H_FishingPole_A_01_43651.m2` | `FISHING_POLE` |

当前实际客户端资产三件套为 `SoloCam.dll`、`Data/Patch-W.MPQ` 和 locale DBC patch。它们的相对路径、大小、逐文件 Hash 规范化后的资产 manifest Hash 为 `067f76f4624874ee547e4e0ee54dbf6d536a4cd18110de2b4f92128c947f8e2a`。逐文件 Hash：

- `SoloCam.dll`: `5ae6974c210607be03a0adebe1178333fdaf3986280367f52cebed116e26d1db`
- `Data/Patch-W.MPQ`: `7fa8cdc3e05cd52e09d63a94e5f23a60175d6a984496371de4c451a45ceee34e`
- locale DBC patch: `9de6a2ab9d71aa2854a48fc7548d8fbb207adaa60571ac953062518f92b372ff`

二进制和游戏资产未写入 Git。

## 5. 人类女性相机零漂移快照

字段顺序固定为 `verticalOffset / distanceScale / minimumDistance / horizontalOffset / yawOffset`。

| 部位 | sentinel | 五元值 |
|---|---:|---|
| HEAD | `0x5341` | `0.55 / 0.32 / 0.55 / 0.00 / 0.00` |
| SHOULDER | `0x5342` | `0.40 / 0.16 / 0.52 / 0.10 / 0.00` |
| BACK | `0x5349` | `0.25 / 0.27 / 0.65 / 0.00 / 3.14159265` |
| CHEST | `0x5343` | `0.25 / 0.27 / 0.58 / 0.00 / 0.00` |
| WRIST | `0x5344` | `0.12 / 0.20 / 0.48 / 0.10 / 0.00` |
| HANDS | `0x5345` | `0.08 / 0.24 / 0.48 / 0.10 / 0.00` |
| WAIST | `0x5346` | `0.10 / 0.27 / 0.58 / 0.00 / 0.00` |
| LEGS | `0x5347` | `-0.02 / 0.27 / 0.58 / 0.00 / 0.00` |
| FEET | `0x5348` | `-0.38 / 0.30 / 0.68 / 0.00 / 0.00` |

## 6. 玩具网格与状态框测量

当前 journal 宽 920 logical px，content host 左右各缩进 31，得到 858；玩具 grid 再左右各缩进 5，内部名义宽 848。三列固定 `TILE_WIDTH=282`，合计 846，所以名义左右余量各 1 px、差值 0。代码没有列间 gap，第一列从 nine-slice 外框原点开始，视觉上仍会贴近外边框。

两张状态框均为 64×64 TGA；沿水平和垂直中线测得四边 non-zero alpha 边带均为 10 px，中心 alpha 为 0。

| 资源 | SHA-256 | alpha 边带 |
|---|---|---|
| `collected-frame.tga` | `027fcb6174ac196e579bcc680526ea79eba47814ac747b11287a64cffdc608bd` | 上/右/下/左均 10 px |
| `uncollected-frame.tga` | `deafbc2f8b2d15c6c2fea85e50ab04c18908bd6be0e3f5dd90956622d2e14f82` | 上/右/下/左均 10 px |

## 7. 空 WDB 真实客户端失败基线

操作顺序：客户端关闭时复制并 Hash 原 `zhCN` WDB，记录 journal 后同卷改名；直接登录角色并打开 `/sc`，未访问 NPC、未召唤坐骑，也未预热缓存。随后按目录 ordinal 搜索首、中、末条目。

| 类别/ordinal | 条目 | 当前结果 | 截图 SHA-256 |
|---|---|---|---|
| mount 1/281 | Acherus Deathcharger | 条目与详情文字存在，模型区空白 | `066f9ca5add0ed1a891adaae50870c4ca49f3268247b8df5cd5305f92a33d858` |
| mount 141/281 | Obsidian Raptor | 条目与详情文字存在，模型区空白 | `0b9ae764d38bd8a878b307b7292c144a458bed43b8f5b9346a2af1eb154cafbe` |
| mount 281/281 | Yellow Qiraji Battle Tank | 条目与详情文字存在，模型区空白 | `959a755b09b0589f208840f0107287db0beea7337a5939e7d6ab0e3c73e7eed0` |
| companion 1/24 | Worg Pup | 条目与详情文字存在，模型区空白 | `ee1780ba542d6d62cf30cf4d14b44351a395fa05695ea82dbb1cde8ad7011e60` |
| companion 13/24 | Mr. Wiggles | 条目与详情文字存在，模型区空白 | `ba18677658e2820e2c84db4b88a2917e8af99c44dac99c460f52855323a82285` |
| companion 24/24 | Onyxian Whelpling | 条目与详情文字存在，模型区空白 | `510fdce852a4e5d2cc06a737cd5933009ba661ea4568ebcbad0bbb878d8ce4be` |

失败时未显示明确的 preview 错误；UI 只是静默保留空模型区。当前坐骑列表大量记录使用同一马头默认图标，宠物列表大量记录使用同一笼子默认图标，和模型空白是两个独立问题。

客户端关闭后，恢复状态机先把本次生成的 9 个 WDB 隔离到 F 盘，再把原 9 个 WDB 同卷改回并逐文件核对。最终状态为 `RESTORED`，原缓存 bundle Hash 为 `6066da1166193a19d41e2511407a2fdc9eb97160b94ba2b898591415361fed34`；最终恢复 manifest SHA-256 为 `452dc9300afc99991a72db6d80546c4f1578e4a669b362171b24000e099e1e53`。

本节只冻结“首次点击”的已知失败。快速连续切换、返回前一个条目、`/reload` 和重登必须在阶段 2 的 SC2 PREVIEW 修复后以同一空缓存工作流重新验收；它们不能用当前静默失败冒充通过。

## 8. 基线结论

1. 空 WDB 下六个代表性坐骑/宠物均不能显示模型，证明当前实现依赖已存在的客户端缓存或旧预览路径。
2. C++ backend 已启用，但当前 AddOn 预览链仍未形成独立 SC2 PREVIEW 闭环。
3. 图标投影、预览协议、武器 canonical 化、玩具网格、180 条相机矩阵和 ItemSet 全量审核应按方案顺序修复；阶段 1–4 完成实机回归前不扩大正式内容。
4. 后续所有生成器输入必须绑定本报告的 evidence ID/Hash；任一文件缺失或 Hash 漂移应 fail closed。
