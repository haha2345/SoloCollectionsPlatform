# Configuration / 配置说明

The distributed template is `conf/transmog.conf.dist`. Copy the installed
template into the AzerothCore modules configuration directory; do not edit or
publish a file that contains runtime secrets.

## SoloCollections backend

```ini
SoloCollections.Backend = Cpp
SoloCollections.ShadowReportPath = "logs/solo-collections-shadow.jsonl"
SoloCollections.Preview.Enabled = 1
```

| Value | Meaning | Production |
| --- | --- | --- |
| `Lua` | Legacy ALE/SC1 owns actions; C++ collection runtime is passive | No |
| `Compare` | Legacy path owns actions; C++ loads read-only state and writes shadow comparisons | Migration only |
| `Cpp` | C++/SC2 owns actions, persistence, and success deltas | Yes |

Never run ALE/SC1 and C++/SC2 as parallel writers or success responders.
`ShadowReportPath` is only used in `Compare`; use an empty value to disable its
file export. `Preview.Enabled` controls read-only mount/companion model priming
and does not enable a legacy backend.

Mount and companion favorites are account-scoped server preferences. The
database stores their authoritative category IDs (10 and 11); SC2 exposes
internal projection IDs 16 and 17. Those projections synchronize state only
and must not be counted as journal pages, collection totals, or progress.

Wardrobe `Y QUOTE`/`APPLY` bills each actually changed non-hide slot with the
same formula as NPC/handbook transmog: `max(source item sellPrice, 1g)` via
`GetSpecialPrice`, times `Transmogrification.ScaledCostModifier`, plus
`Transmogrification.CopperCost`. Hide and clear are free. `0` is a legal fee
and must still be returned on `U`. The AddOn must not estimate gold.

`SoloCollections.Transmog.ApplyBaseCopper` and `ApplySlotCopper` are unused
legacy keys; do not restore them as the wardrobe price.

`SoloCollections.Transmog.MixedArmor` only affects collected wardrobe apply
(`CanApplyCollectedVisual`). It does not change NPC transmog. That path does
not run NPC `SuitableForTransmogrification` on the equipped target, so wearing
an armor type without the matching skill cannot block a collected visual.

```ini
# same  = cloth/leather/mail/plate must match
# lower = allow lower armor tiers the player can wear
# any   = cloth/leather/mail/plate interchangeable
# Invalid values fail closed to same.
SoloCollections.Transmog.MixedArmor = any
```

NPC vendor mixing still uses `Transmogrification.AllowMixedArmorTypes` and
`Transmogrification.AllowLowerTiers` (distributed default off).

Type 18 (`character-applied`) and type 19 (`account-outfit`) are internal
projections. They are advertised only to AddOns whose HELLO `clientBuild`
contains `-w1`. Deploy the module before the wardrobe AddOn.

## Transmogrification

The same template contains inherited, adapted transmogrification settings:

- `Transmogrification.Enable`
- `Transmogrification.UseCollectionSystem`
- `Transmogrification.UseVendorInterface`
- quality, armor, weapon, race/class/skill restrictions
- cost and optional token settings
- saved outfit and portable NPC settings

Start from conservative defaults. A broader item/weapon rule changes gameplay
authorization, not merely UI appearance.

## 中文说明

生产收藏后端使用 `SoloCollections.Backend = Cpp`。`Compare` 只用于从旧 ALE/SC1
迁移时做只读对照，`Lua` 只保留旧路线。任何时候都不能让两条路线同时写账号收藏
或向客户端返回动作成功。

`SoloCollections.Preview.Enabled` 只控制坐骑/宠物只读模型预热，不会切换后端。
坐骑与小宠物偏好由服务端按账号持久化：数据库保存底层 type 10/11，SC2 使用内部
投影 type 16/17 同步状态；内部投影不参与页面导航、收藏总数或完成度。
幻化室批量应用按外观源物品卖价计价（至少 1 金，再乘
`Transmogrification.ScaledCostModifier` 并可加 `CopperCost`），隐藏和清除为
0，不读客户端数字。`ApplyBaseCopper` / `ApplySlotCopper` 已废弃。收藏室跨甲只读
`SoloCollections.Transmog.MixedArmor`（`same` / `lower` / `any`，默认 `any`，
无效值按 `same`），不改 NPC 幻化台的 `AllowMixedArmorTypes`。type 18/19
只对 HELLO `clientBuild` 带 `-w1` 的插件宣告；必须先部署模块再部署新 AddOn。
外观写在装备实例上，换装不自动套到新物品。
幻化配置会影响费用、物品品质、护甲/武器类型和玩家权限；修改前应备份运行配置，
逐项确认，不要把视觉兼容改动误当作无风险 UI 设置。

启动后用 `.solocollections status` 和结构化日志确认 backend、schema、provider、
build metadata 与 mapping hash。幻化室报价/应用会打
`event=wardrobe_quote` / `event=wardrobe_intent`（`module.solocollections.wardrobe`），
字段包括 `status`、`copper`、`entries`、`source`。解析失败的 `Y` 会在
`event=protocol_reject` 上带 `kind=Y`。
