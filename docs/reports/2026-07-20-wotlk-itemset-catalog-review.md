# WotLK ItemSet 目录审核、派生状态与真实客户端验收

日期：2026-07-22  
阶段：Round Two / 阶段 8  
结论：通过

## 1. 阶段结论

本阶段已用当前客户端 `ItemSet.dbc`、只读 World DB 快照、canonical appearance mapping、全局 append-only ID registry 与人工 override，替换原两份手工套装事实源：

- 原始 DBC 行与审核单元：509 / 509；
- accepted：465；
- excluded：34（空或不足两个可见成员）；
- deferred：10（可见成员 mapping 不完整或职业资格不能安全闭合）；
- 正式 active collection：465；
- full / partial / unresolved：465 / 0 / 43；
- variant：465；
- 不同 canonical signature：380。

`catalog/generated/normalized-itemsets.json` 是生产套装事实源；`catalog/source/sets.json` 只保留退役说明，`catalog/source/collections/sets.csv` 是生成投影。`catalog/ids.json` 继续是所有类别 collection ID 的唯一权威，`set-id-registry-view.json` 仅作只读子集证明。

## 2. 证据、模型与稳定 identity

最终命名 evidence pack：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-addon\_work\evidence\round2-20260722-stage8-itemsets
files: 101
canonical pack hash: 22d30f9ee6a88be8840f8619483d494345543bbdd10bbb2da05617e165bf2dd6
```

关键 Hash：

```text
ItemSet candidate hash: 76fc2e726733e926fda234767b24baf60942c0abf3d711af0e7db67653e9e883
appearance mapping evidence: f418b28486adc98ba8b2d59fd98059a99ba31c9f44f4366189e151264a92f92b
type 14 mapping hash: 2110892144adcdf60834c30785569ef38b5af7980cbdb62d684846cf44cc87cf
global catalog mapping hash: a2ac7463945f681ca4d4f9b4b7ab72c6e32674a1e2955a2589b03b757e1d8e27
metadataVersion: 2026.07.22.3
```

现有 8 套 `300000..300007` 的 collection ID、key、ordinal 与成员逐项保留；新 ID 从 `300008` 追加。`Manual8` 已冻结为 `catalog/fixtures/sets/manual8.normalized.json`，并可用以下 runbook 形式在 F 盘重建：

```powershell
python tools\catalog\itemset_import.py --profile manual8 --output F:\...\manual8.normalized.json
```

牧师 T1 `ItemSetId=202`“预言”作为首个新增 fixture，包含 8 个 required visible member，职业策略为 priest allow-list。classPolicy 分布为：

| 策略 | active collection |
|---|---:|
| `ANY` | 125 |
| 单职业 `ALLOW_LIST` | 326 |
| 双职业 `ALLOW_LIST` | 11 |
| 三职业 `ALLOW_LIST` | 3 |

每个 active collection 恰有一个 active default variant；variantOrdinal、collection ID 与 ordinal 均稳定且不以数组下标表达。

## 3. type 14 派生与 APPLY 契约

type 14 仍是 type 13 appearance owned 的纯派生投影：

- snapshot 通过 provider 重算，不读取或写入 type 14 unlock 表；
- type 13 提交后，用同一 revision 对活动 session 发送 type 14 集合差分；
- UI 进度与服务端完成度都按同一 stable variantOrdinal 计算；
- `-` 只表示唯一 active default variant，正整数表示稳定 variantOrdinal；
- classPolicy、owned alternatives、目标装备、费用与全部成员先完整 preflight，再一次性提交；
- appearance priority 由生成表顺序固定，客户端不发送成员、物品或 spell 事实；
- disabled/deferred variant、伪造 ordinal、跨 collection ordinal 和 mapping mismatch 均 fail closed。

UI 已由固定 8 图标改为受上限约束的动态对象池和 8 列换行布局；当前 active 数据最大 required visible slots 为 8，但实现不再把 8 写成完整性合同。

## 4. 自动化、原生构建与生成漂移

最终回归结果：

- AddOn Python contracts：230 项通过，4 项按既有可选外部证据条件跳过；
- module Python contracts：131 项通过；
- module native：2/2 通过；
- `itemset_import.py check`、`set_catalog.py --check`、`generate_catalog.py --check` 全部通过；
- exact 509 审核覆盖、Manual8 零漂移、牧师 T1、single/multi/ANY、alternatives、omissions、mapping hash 单字段漂移、stable variant 和原子失败均有合同测试；
- clean Core x64 Release `worldserver.exe` 构建并部署成功。

clean Core 固定为 `4cc67a316d2bec9faf27c3392634282e70cacbe0`，部署 PE：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\build\round-two-core\bin\Release\worldserver.exe
SHA-256: aef38f11626040c0c777b731b29cca5bdb90841bfdcd1b1e5778a8244c609d85
```

启动日志确认 Win64 Release static module、Cpp backend、`metadataVersion=2026.07.22.3`、18190 appearances、7 providers 与 schema ready。

## 5. 真实客户端验收

使用 Computer Use 操作 `D:\Games\wow335\World of Warcraft11\Wow.exe`，账号角色为一级亡灵牧师 `Asgas`。实际结果：

- 牧师默认筛选显示 `0/165`，全部职业显示 `0/465`；
- 职业下拉完整列出十个 logical class 与全部职业；
- “预言”搜索在牧师筛选返回牧师 T1，在全部职业筛选同时返回牧师“预言”和萨满“预言者套装”；
- 牧师 T1 8 个部件图标、0/8 进度和禁用应用按钮正确；
- 完整目录 page 1/59 与 page 2/59 翻页、固定可见行池和滚动条正常，无明显卡顿；
- 临时逐件 grant 形成 1/8、7/8、8/8；7/8 时最后一件灰显且应用禁用，8/8 时派生 type 14 立即变为已收藏并启用应用；
- 一级角色缺少目标装备栏时点击应用，世界角色外观保持原样，没有部分应用；
- 8 个临时 appearance unlock 按 2 秒间隔逐条 revoke，revision 连续推进至 152，客户端恢复 0/8；
- `/reload` 后仍为 0/8，搜索、职业筛选、分页和 Lua 加载均正常。

代表截图：

| 截图 | SHA-256 |
|---|---|
| `priest-prophecy-8-piece-unowned.png` | `3fd1ea1165f5cb2a6b06ae434a84b3797776c8cc5f55f0fa6fd0c42b5795d810` |
| `set-class-filter-options.png` | `a64fe4e78f6ae1c0c1c335a5f7839f94460d5a2fc835596798460cf1648a9b26` |
| `all-classes-full-catalog-465-page1-of59.png` | `969070ac29934cf9d8a068092a4ee5f0a2e0cc4196031df94266dd0e72139879` |
| `all-classes-full-catalog-page2-of59.png` | `2d438af01838d3487a7545cc837769987f9320a0fe406bc206964437df68a7e3` |
| `priest-prophecy-missing-one-7-of8.png` | `d4472117885a58659bd348e59833edfcc54bf4e65c5c162d235fb68caa19130e` |
| `priest-prophecy-complete-8-of8-apply-enabled.png` | `0d08bdb783e987633436b9b0af2e2cdfec8c2d2c2e1e23f65b5a8c7bc5088df0` |
| `priest-prophecy-apply-failed-zero-partial-world-model.png` | `58cd472bc568bd273e26e0c8e8277c0e107fc97d7255f063bd0f3c7011810d8c` |
| `post-reload-priest-prophecy-cleanup-0-of8.png` | `16a14a9545cbf65432c6d08ba5b36780f6f63dd3e89701c1078450f25eddf5b7` |

## 6. 清理与阶段出口

测试中产生的 8 个 type 13 appearance unlock 已全部通过权威 revoke 清理，最终客户端与派生投影均为 0/8；没有创建 type 14 持久化行。双手工事实源已退役，509 个审核单元全部有 accepted/excluded/deferred 结论，全局 registry、normalized schema、Lua/C++ 投影、派生 delta、stable variant 与动态 UI 容量已经完成自动化、clean Core 和真实客户端闭环。
