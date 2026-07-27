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
幻化配置会影响费用、物品品质、护甲/武器类型和玩家权限；修改前应备份运行配置，
逐项确认，不要把视觉兼容改动误当作无风险 UI 设置。

启动后用 `.solocollections status` 和结构化日志确认 backend、schema、provider、
build metadata 与 mapping hash。
