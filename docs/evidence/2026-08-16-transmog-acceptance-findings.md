# 2026-08-16 幻化验收：未通过项原因

静态对照源码与本轮计划。2026-08-17 用三张实机图核对了上次留下的问题。
**没有**再改代码。世界服报价日志仍未抓。

部署基线：模块 `worldserver` SHA-256 `39abe24bd686b560…`，
`SoloCollections.Transmog.MixedArmor = any`，套装 mapping hash `39aef8fc…`。
客户端 AddOn 已单文件覆盖。

## 已通过

- 开窗默认当前职业 / 甲种；甲种下拉能切到别的甲或全部。
- 套装已收集在前；方向键能翻，ESC 能关，WASD 能走。

这两条与本轮实现一致，不再展开。

## 2026-08-17 实机图核对

三张图分别回答上次问的「小卡还是左侧」「跨甲点的是不是已收藏」「手册套装是整页空白还是只有散件」。

### 图 1：幻化室远程槽，下拉「弓」

- 左侧矮人 **有** 3D 人物，远程槽金边，手里是枪。
- 右侧 18 张卡 **全是 2D 图标**，不是武器模型。第 1 张隐藏外观；第 2 张枪（对勾，当前穿着钉住的原物，不受「弓」过滤）；第 3 张弓（对勾）；其余弓标「未收集」。
- 进度 `1 / 147`，页 `1 / 9`。应用灰，金币 `0`。

结论：用户说的「还是显示图标」指 **右侧小卡**，左侧预览正常。
弓 / 枪 / 弩小卡走 `IsIconOnlyCard` 是本轮按计划做的，但实机上弓卡全是图标，和护甲卡的 3D 不一致，这条产品决定应收回。
图 1 不能单独证明跨甲报价；远程槽当前穿着是枪，没点进一张已收藏弓的待定时，应用灰、金币 0 是预期。

### 图 2：幻化室腿部，下拉「布甲」

- 左侧人物已换成选中的补丁布裤，腿部槽金边，槽图标与选中卡一致。
- 选中卡有对勾（已收藏）和黄边；同排还有另外几张已收藏布裤的 3D 卡。
- 进度 `4 / 366`，页 `1 / 21`。应用仍灰，金币仍是 `0`。

结论：已收藏的跨甲外观 **能预览、能进待定**，但报价没有变成 `READY`。
免费服报价成功也会显示 0 铜，但那时应用钮应能点。钮是灰的，说明 `GetDraftApplyState()` 为假。
`scStateText` 被做成 `SetWidth(1)` 且 `Hide()`，屏幕上看不到「不兼容 / 未收藏」；原因只在应用钮和金币条的 tooltip 里。
图 2 把跨甲问题钉在「客户端预览成功，服务端报价没 READY」。

### 图 3：收藏手册套装页，猎人「T9 · 风行者的战甲」

- 左侧列表、名称、分类、阵营、5 个散件图标、`0 / 5` 都在。
- 右侧人物区 **整块黑空**，不是裸模。
- 「应用套装」灰是对的（`0 / 5` 未收齐）。「重置视角」仍可点。

`风行者的战甲`（itemSetId 859）只有头 / 肩 / 胸 / 手 / 腿 5 件，**没有**走散件补全。
所以手册套装空白与本轮 23 套补鞋无关，是整页预览路径的问题。

## 对照

| 现象 | 归类 | 主因 |
| --- | --- | --- |
| 幻化室弓 / 枪 / 弩小卡是图标 | 按计划做了，实机不可接受 | `Lab.IsIconOnlyCard`；左侧 `PlayDressUp` 正常 |
| 手册主手 / 副手没有弓枪弩 | 按计划实现；这三张图没覆盖手册物品页 | `hideRangedWeapons` + 手册没有远程槽 |
| 手册套装页右侧黑空 | 实机确认，不是散件 | 手册仍走 `SafeDressUp`（等 `GetModel()`） |
| 已收藏布甲预览成功但应用灰、金币 0 | 实机确认跨甲报价未 READY | `Y QUOTE` 失败被写成 `CLASS_RESTRICTED`，`quoteStatus` 关钮；状态字被藏起来了 |

---

## 1. 衬衣 / 战袍 / 枪 / 弓 / 弩「还是显示图标」

### 计划里写的是什么

本轮明确要求：**幻化室小卡只显示图标**，左侧大预览仍 `TryOn`。
文档也写成这样：`docs/architecture/06-外观页和套装页.md`。

所以小卡是图标，本身不是漏改，是按计划做的。

### 小卡

`UI/WardrobeLab/Sources.lua` 的 `Lab.IsIconOnlyCard`：

- 槽位 `SHIRT` / `TABARD`
- 或 `weaponType` 为 `GUN` / `BOW` / `CROSSBOW`

命中后 `stopCardModels()`，`GetItemIcon` 画 48×48 图标，**不再**走 `ItemCardRenderer:Present`。

### 左侧大预览

左侧 **没有** 走 `IsIconOnlyCard`。点卡后 `SetDraft` → `RefreshDraft` → `GetPreviewItemIds` → `Lab.PlayDressUp` → 分帧 `TryOn`。

左侧人物纸娃娃槽位按钮本来就是图标（`Slots.lua` 用 `GetItemIcon`），和右侧小卡不是同一块。

图 1 已确认：左侧人物是 3D，问题只在右侧小卡。衬衣 / 战袍这两张图没拍，先不要和弓枪弩绑在一起改。

### 建议

弓 / 枪 / 弩小卡改回 `ItemCardRenderer:Present`（3D）。
`IsIconOnlyCard` 若还留，只留给衬衣 / 战袍，或整段删掉。

---

## 2. 手册主手 / 副手为什么没有弓 / 枪 / 弩

### 不是目录丢了，是本轮故意藏的

计划原文：手册物品页不显示枪 / 弓 / 弩，下拉也不列这三项。
实现有三处，只打手册，不打幻化室远程槽：

1. `UI/EzWardrobe/DataProvider.lua` `GetQueryFilters()` 设 `hideRangedWeapons = true`。
2. `Core/Catalog.lua` 查询外观时丢掉 `BOW` / `GUN` / `CROSSBOW`。
3. 手册本地 `WEAPON_FILTERS`（`UI/Wardrobe.lua`）删了这三项。`Catalog.WEAPON_FILTERS` 仍保留，幻化室远程槽还能筛。

### 为什么会从手册里完全消失

手册物品页部位只有头到脚 + **主手 / 副手**，**没有远程槽**（`SLOT_FILTERS`）。
更早的公共 UI 说明也写过：弓 / 枪 / 弩属于远程，主手下拉本来就不该列它们。

本轮之前，这三种往往挂在主手列表里（`weaponType` 是弓枪弩，但手册只有主手可点）。
藏主手里的弓枪弩之后，手册没有任何入口能再看到它们。幻化室远程槽仍在。

### 建议（产品二选一）

- **要手册也能收弓枪弩**：手册加远程部位，或把这三种留在主手。不要只藏不给槽。
- **手册只收近战 / 副手**：保持现状，但要在手册里写清「弓枪弩在幻化室远程槽」。

这不是服务端丢数据，也不是 hash 对不上。

---

## 3. 收藏手册套装页不显示模型

这里说的是 **收藏手册套装页右侧大预览**，不是幻化室套装卡。
手册套装是列表 + 右侧一个 `DressUpModel`，列表行本身没有角色模型。

### 散件补全解释不了「整页没模型」

`tools/catalog/set_extras.py` 只给 **23** 套补了缺的腕 / 腰 / 鞋 / 背。
例如「黑暗符印战甲」现在有 `FEET` / `46326`，成员结构仍是
`appearanceIds` + `sourceItemIds` + `required = true`，手册预览读的就是这些字段。

其余四百多套成员没变。若 **所有** 套装右侧都是空的，原因不在散件。

### 手册和幻化室走的不是同一条预览

| 窗口 | 路径 | 是否等 `GetModel()` |
| --- | --- | --- |
| 幻化室左侧 / 套装卡 | `Lab.PlayDressUp` | 否（本轮已按这个修过空白） |
| 手册套装右侧 | `ItemPresenter:AttachSet` → `ModelProvider` `SafeDressUp` | 是 |

`SafeDressUp` 会先把模型 alpha 置 0，`ClearModel` / `SetUnit` 后再等 `GetModel()`。
父级隐藏时 OnLoad `SetUnit` 会留下空 actor；等不到路径就一直透明，看起来就是「不显示模型」。
`onUnavailable` 只清 pending，**不会**给用户看「模型预览不可用」。

本轮 **没有** 改 `ItemPresenter.lua` / `ModelProvider.lua`。
手册这条路径在幻化室修空白之前就存在。

图 3 已确认：未补散件的 T9 五件套也是整块黑空，散件图标在、人物不在。
不是裸模，是 presenter 没把 actor 画出来。

### 建议

手册套装预览改走 `PlayDressUp`，与幻化室左侧对齐。不要再等 `GetModel()`。

---

## 4. 不同甲选外观，应用按钮是灰的

跨甲配置已经写进世界服，而且 **只影响收藏室应用**。
按钮灰发生在 **客户端先判断能不能点**，不是点下去才被服务端拒。

### 按钮谁关的

`Controller.lua`：`canClickApply = 不在 REQUESTING 且 GetDraftApplyState()`。
`GetDraftApplyState` 来自 `GetDraftBlockReason`：

- 没有待定 → `NO_DRAFT`（只切了甲种下拉、没点已收藏卡，也会灰）
- 未收藏 → `NOT_OWNED`（「你尚未收集此外观。」）
- 空槽 → `INVALID_TARGET_SLOT`
- 报价状态既不是 `READY` 也不是 `UNAVAILABLE` → **直接用报价原因**

选卡后 `SetDraft` 会 `ScheduleQuote()`。`Y QUOTE` 失败时
`quoteStatus = CLASS_RESTRICTED`，应用钮变灰。

`Layout.lua` 里的 `scStateText` 是 `SetWidth(1)` 且 `Hide()`，屏幕上 **看不到**
「不兼容 / 未收藏」。原因只在应用钮和金币条的 tooltip。
图 2 因此只能从「已收藏 + 预览已换装 + 钮灰 + 金币仍 0」反推报价没 READY。

### 服务端并不是「MixedArmor=any 就一定过」

报价 / 应用走 `EvaluateIntent` → `AppearanceService::ResolveOwnedSource`。
解析失败（找不到一件能套到当前装备上的源物品）时，**一律**回 `CLASS_RESTRICTED`。
这个名字包含甲种不兼容、库存类型不对、目标装备不适合幻化等，不单指职业。

`ResolveOwnedSource` 会对每个源物品试：

1. `CanTransmogrifyItemWithItem`（NPC 规则；`AllowMixedArmorTypes` 默认关）
2. 不行再试 `CanApplyCollectedVisual`（才读 `SoloCollections.Transmog.MixedArmor`）

`CanApplyCollectedVisual` 在放行布 / 皮 / 锁 / 板互幻之前，仍要求：

- 源和目标都是护甲或都是武器
- `SuitableForTransmogrification(player, **target**)` 通过
- 库存类型相同，或袍 / 胸这种已允许的例外

`SuitableForTransmogrification` 在目标护甲技能为 0 且
`Transmogrification.AllowMixedArmorTypes = 0` 时会失败。
MixedArmor **不管** 这条。例如板甲职业穿着布衣（3.3.5 能穿），
目标布甲技能为 0，跨甲外观会在「目标不适合」这里被拒，报价变 `CLASS_RESTRICTED`，按钮变灰。

板甲职业穿着板甲、点已收藏的布 / 皮 / 锁外观，按代码应能过 `any`。
若这时仍然灰，优先查：是不是未收藏、报价是否真的回了 `CLASS_RESTRICTED`、世界服日志里的 `wardrobe_quote`。

### 客户端不知道 MixedArmor

AddOn 不读 `SoloCollections.Transmog.MixedArmor`。
它不会因为「现在允许跨甲」自己点亮按钮，只听收藏态和报价。

### 建议

1. `CanApplyCollectedVisual` 不要再用 NPC 的 `SuitableForTransmogrification(target)` 甲技能门槛卡收藏室。
2. 报价失败原因不要一律叫 `CLASS_RESTRICTED`；至少把「未解析到源物品」和职业限制分开。
3. 修好后看 `event=wardrobe_quote`。不要为了收藏室去开 `Transmogrification.AllowMixedArmorTypes`。
4. 可选：把 `scStateText` 重新显示出来，避免再靠 tooltip 猜为什么钮是灰的。

---

## 证据边界

| 层 | 状态 |
| --- | --- |
| 源码 / 静态对照 | 已完成 |
| 模块编译 / 部署 | 本轮已部署；本文不再重编 |
| 世界服报价日志 | 未抓 |
| 实机画面 | 三张图已核对；未标完成 |

## 建议的改动顺序（未做）

1. 弓 / 枪 / 弩小卡改回 3D；衬衣 / 战袍这两张图没拍，先不动或另说。
2. 手册套装预览改 `PlayDressUp`。
3. 收藏室跨甲：放宽 `CanApplyCollectedVisual` 的目标甲技能检查，并分开报价失败原因。
4. 手册物品页弓枪弩仍缺远程槽；这三张图没覆盖，单独定产品。
