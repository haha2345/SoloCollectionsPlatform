# 2026-08-18 收藏系统 + 幻化系统验收记录

记录日期：2026-08-18。维护者 Woden 确认：**收藏手册与独立幻化室均已验收通过**，可按已实现范围上线使用。

本文是当前结论的入口。逐步截图、SavedVariables 和问题清单仍以 `_work/qa-framework/results/` 当次运行为准，不要把套件总体 FAIL 直接当成产品失败。

## 1. 结论

| 系统 | 结论 | 依据 |
| --- | --- | --- |
| 幻化协议 / 落库 | **PASS** | 三端 19 步全过，`run-20260818-074736` |
| 幻化室 UI | **可上线**（S2 已修清零） | `run-20260818-115511` + U1/U2/U6 热修验收 |
| 收藏手册 | **已实现范围可上线** | `run-20260818-144015` 复核 + 后续 U1/U2/U4 / GAP 修复 |
| 整套（手册 + 幻化室） | **验收通过** | 2026-08-18 维护者确认 |

生产权威仍是 `mod-solo-collections` 的 C++/SC2（`SoloCollections.Backend = Cpp`）。AddOn 只负责 UI、缓存和协议收发，不决定所有权。

## 2. 系统构成

```text
玩家客户端
  SoloCollections          收藏手册 + 独立幻化室
  SoloCollections_WardrobeData   外观/套装目录（LoadOnDemand）
  SoloCollections_EzUI     可选视觉素材
  SoloCollections_RetailUI 可选本地 Retail 素材
        │  SC2
        ▼
mod-solo-collections       账号收藏、授权、revision、动作、幻化写入
        │
        ▼
characters 库              account 收藏表 + character_sc_transmog + outfit
```

手册入口：`/sc` 或 `UI.ShowJournal()`。上线页签：坐骑、小宠物、外观（只浏览）。
玩具箱与头衔页已从主线卸下，分别停在 `feat/deferred-toy-box` 与
`feat/deferred-title-journal`。

幻化室是独立窗口，由单独按钮打开，与手册互斥。写入路径只走幻化室：待定、报价、Apply、HideVisual、Outfit。

账号级范围：同一登录账号下的全部角色共享坐骑 / 小宠物 / 玩具 / 外观 / 套装。头衔跟角色。不同账号禁止共享。

## 3. 验收证据链

### 3.1 幻化协议与落库 — `run-20260818-074736`

方案：`_work/qa-framework/README.md` 的 `suites/transmog.lua`。

qa1（圣骑士）、qa2 / qa3（战士）各 19 步 **PASS**：

- 插件 `stable` 渠道、调试命令门禁、SC2 握手 READY
- 类别 13 / 18 / 19 Ready
- 跨 `/reload` 持久化 MATCHED
- 合法 Apply `ACCEPTED`（或 `ACCEPTED_VIA_PUSH`）
- 非法 Apply 被拒（`CLASS_RESTRICTED` / `NOT_OWNED`）
- 报价（qa1 1 金；低级战士 0 铜）
- 衣柜写入、清除、恢复
- Outfit 存 / 改名 / 删
- 手册内存约 20MB（预算 30MB）

三路证据一致：客户端 SavedVariables、Server.log（零错误、零失败事务）、数据库（`character_sc_transmog`、`custom_transmogrification`、套装无残留）。

### 3.2 幻化室 UI — `run-20260818-115511` 及热修

方案：`_work/qa-framework/UI-ACCEPTANCE.md`，对标军团 7.3.5 幻化室。

已对齐并通过：独立窗口 965×606、ESC、DressUp 预览、点槽换网格、已收集待定报价、未收集可预览不可应用、Hide Visual、空槽红叉、主手/副手拿反提示、物品/套装页签、开窗默认本职业、与手册互斥、关后再开。

套件总体 FAIL 是 3.3.5 `IsEnabled()` 返回 `0/1`、`0` 在 Lua 为真，**不是**未收藏外观能点应用。

| 编号 | 级 | 状态 |
| --- | --- | --- |
| U1 失败原因看不见 | S2 | 已修。状态字常显在模型脚下。证据 `accept-u1u2-20260818-135757` |
| U2 默认板甲下已收藏卡报价 NOT_OWNED | S2 | 已修。AUTO 甲种跟当前槽位穿着走。同上 |
| U6 套装页左侧无紫蚂蚁 | S2 | 已修。`Slots.lua` pending 判定补 preset。证据 `spot-ants-20260818-132917` |
| U3 搜索仍剩隐藏/当前外观钉住卡 | S3 | 接受。军团也会钉住 |
| U4 开窗内存 37–47MB | S3 | 接受。衣柜数据约 12MB，在 60MB 预算内 |
| U5 空远程槽不能切过去 | S3 | 接受。空槽不可幻化 |

**S2 清零后，幻化室客户端 UI 达到上线水平。**

### 3.3 收藏手册 — `run-20260818-144015` 及修复

方案：`_work/qa-framework/COLLECTIONS-ACCEPTANCE.md`。本轮不测独立幻化室写入。

已实现且复核可用：开窗 / 五页签 / 768↔703、已收集坐骑预览与召唤、未收集召唤拦截、小宠物、玩具使用拦截、手册外观浏览（物品网格 / 套装列表 / 职业过滤分岔）、ESC 开关。

套件总体 FAIL 只来自 `title_id_audit`：`IsTitleKnown(i) and true` 把 `0` 当成已知。界面 Ready 路径走 SC2，1 级号 0/143 全灰与「身上没有头衔」一致，**不是产品 S1**。

首次走查留下、随后已按 `COLLECTIONS-FIX-PLAN.md` 修进源码：

| 编号 | 内容 | 源码状态 |
| --- | --- | --- |
| U1 / U4 | 搜索与已收集过滤跨页残留 | `tabUiState` 按主页签隔离 |
| U2 | 手册外观露出应用钮 | `scApplySet` 创建后 Hide |
| GAP-TOY-4 | 未解锁玩具仍可设偏好 | 菜单禁用 + Catalog 拒绝 |
| GAP-TOY-7 | 玩具页藏了件数 | 玩具页显示 `scCollectionCount` |
| GAP-TITLE-3 | `IsTitleKnown` 把 0 当已知 | 改为 `== 1` |

U3（未收集坐骑 3D 不换模型）维护者实机确认为 QA `Pick()` 假阳性，预览路径未改。

## 4. 当前功能面

### 收藏手册

| 页 | 已验收能力 | 仍属缺口 / 说明级 |
| --- | --- | --- |
| 坐骑 | 列表、模型、召唤、未收集拦截、偏好走服务端 type 16、随机 150544 | 骑术等级矩阵全图未单独测 |
| 小宠物 | 与坐骑对齐的非战斗宠物页 | 不是军团战宠图鉴 |
| 玩具 | 9 条已审核玩具：网格、使用、未解锁拦截、已解锁可拖宏 | 目录只有 9 条故有空格；偏好仍是本机 SavedVariables（GAP-TOY-3）；无冷却扫光 |
| 头衔 | 只读列表、拥有态跟 SC2 / `IsTitleKnown==1` | 不能点击启用；无来源跳转 |
| 外观 | 物品/套装浏览、收藏态、部位/职业过滤 | 写入入口已藏，不走 Apply |

### 独立幻化室

已验收：开窗、13 槽、预览、待定、报价、应用、撤销、Hide Visual、物品/套装、搜索/过滤/翻页、方案增删改、与手册互斥、服务端所有权校验、幻化对其它玩家可见（`SetVisibleItemSlot`）、孤儿幻化行清理。

外观写在**当前穿着的物品实例**上。换一件新装备后该槽幻化不会自动跟着走，与军团 item-GUID 绑定一致，需要在 UI 上保持这个预期。

### 服务端

- 生产后端：`SoloCollections.Backend = Cpp`
- 账号快照 + revision 增量；APPLY 校验已解锁源
- 坐骑 / 宠物偏好持久化；幻化 Outfit（type 18/19）
- 插件构建渠道：`X-SoloCollections-BuildChannel: stable`

## 5. 不挡上线的遗留

这些不是本轮否决项，后续若做要单独开范围：

1. 玩具偏好尚未做成服务端账号投影（GAP-TOY-3）。同账号换角色可能碰巧还在（SV 按 WTF 账号目录），别的玩家账号不得看见。
2. 头衔点击启用、来源、人物面板联动未做。
3. 已审核玩具只有 9 条。
4. 同账号多角色共享、异账号不串数据，本轮没有单独编排步骤。
5. 登录后约 30 秒内，异步写操作的插件 5 秒超时可能误报；服务端实际成功，授权推送会纠正界面。
6. 点「当前穿着」钉住卡再报价，服务端会以 NOT_OWNED 拒绝重复应用。
7. 物品页镜头仍可能因种族、性别、HD/自定义模型或极端武器构图需要 profile。见 [CAMERA_CONTRIBUTIONS.md](../CAMERA_CONTRIBUTIONS.md)。

## 6. 客户端测试插件清理（同日）

验收通过后，真实客户端不再需要收藏/幻化测试插件。已从共享 AddOns 目录移除：

| 已移除 | 原用途 |
| --- | --- |
| `SoloCollectionsQaRunner` | 游戏内步骤执行器 |
| `SoloCollectionsLaunchAudit` | 一次性启动探针 |
| `SoloCollectionsAssetMismatchAudit` | 资源对账（toc 已 disabled） |
| `SoloCollectionsStage9SoakAudit` | Stage9 浸泡（toc 已 disabled） |
| `SoloCollectionsStage9StatusAudit` | Stage9 状态（toc 已 disabled） |

三端 AddOns 是同一目录，删一次即全部干净。生产插件保留：`SoloCollections`、`SoloCollections_WardrobeData`、`SoloCollections_EzUI`、`SoloCollections_RetailUI`。

框架源码仍在 `_work/qa-framework/addon/SoloCollectionsQaRunner` 与 `_work/launch-audit/addon/`，以后要复验再部署，测完再卸。

未动：`RetailAssetPreview`、`IdTip`（不是收藏/幻化验收插件）。

## 7. 目录规模（生成清单，不是运行时数据库）

19,146 条 canonical：坐骑 281、非战斗小宠物 201、已审核玩具 9、外观 18,190、套装 465。metadata `2026.07.23.2`。手册空闲内存约 19–22MB；打开幻化室约 37–47MB。
