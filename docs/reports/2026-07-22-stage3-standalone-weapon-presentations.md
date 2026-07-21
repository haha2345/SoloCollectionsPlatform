# 阶段 3：独立武器展示实施与验收记录

日期：2026-07-22

## 结论

阶段 3 已完成。21 个既有武器展示已从旧样例数据迁入 canonical presentation 合同；外观投影按 `BODY/STANDALONE/UNAVAILABLE` 显式选择 renderer。真实客户端逐项资源审计为 `21/21 READY`、失败 `0`；正式衣橱确认独立武器只显示武器，缺资源主副手和 stock client 缺 SoloCam 时均显示 unavailable，不再出现角色模型或空白卡片。

## Canonical 展示合同

- 权威源：`catalog/source/appearance_presentations.json`，共 21 条；`syntheticDisplayId` 完整且唯一覆盖 `40000..40020`。
- 每条记录保存 source item alias、canonical appearanceId、M2、scale、weapon type/category、camera key、`m2Camera`、asset pack version 与 `presentationStatus=verified`。
- 资源 manifest SHA-256：`7c866d9384d80ee20fcf3c06d08b8445647a0e5899675cbee46b3cc3f815368c`；验证 CSV SHA-256：`0b431aeb35436c2adb6bd2a129624ddb748251093b6689e9861d74ac6012ab56`。
- 生成器 fail closed 校验一对一 canonical 联接、alias 可追溯、M2/skin/BLP 长度与 Hash、相机字段和 synthetic ID；旧 demo id `50..70` 不进入 authoritative identity。
- 生成目录统计：`BODY=12233`、`STANDALONE=21`、`UNAVAILABLE=5936`。presentation 字段不进入服务端授权 mapping hash，mapping hash 仍为 `1fc77655c08118c89e7bfb31e9a2cfd95cdc068ba473d8615adb6e1ff3706a7a`。

## Renderer 边界

- `Catalog.lua` 仅投影 `syntheticDisplayId/modelPath/modelScale/m2Camera/cameraTuningKey` 等展示字段。
- `creatureDisplayId` 不存在于新 schema 或 generated catalog；只在 `Wardrobe.lua` 最后一层用 `DIRECT_DISPLAY_REQUEST_BASE + syntheticDisplayId` 调用 direct display bridge。
- 护甲固定为 `BODY`；verified 主副手为 `STANDALONE`；其余主副手为 `UNAVAILABLE`。
- `UNAVAILABLE` 清空并隐藏 PlayerModel/DressUpModel，只显示图标、名称和“独立模型资源尚未生成”；不存在 `SetUnit("player") + TryOn` 或 NPC placeholder fallback。
- 独立模型有 120 帧（约 2 秒）就绪窗口；`GetModel()` 未匹配 canonical `modelPath` 时切换 unavailable。该检查使 stock client 或缺资源包环境安全降级，而不是留下空白模型卡。

## 真实客户端证据

证据根：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage3-weapons\20260722-031006-184`。

- WeaponAudit：21 个 synthetic display 全部逐项得到稳定且与 manifest 一致的 `GetModel()`；`21 ready / 0 failed`。CSV SHA-256：`34624d71b1392800ab959ed91b343b7de9d00bfbb6cfa4499791ab2933c36113`。
- 正式衣橱 + SoloCam：collection `217674`、item `50012`、synthetic display `40005` 加载 `SC_Axe_1H_IcecrownRaid_D_01_50737.m2`；`objectVisible=true`、`characterVisible=false`、`unavailableVisible=false`。截图 `formal-standalone-after-fallback.png`。
- 缺资源主手斧：正式衣橱仅显示图标和独立模型 unavailable 文案，无角色模型。截图 `formal-unavailable.png`。
- stock `Wow.exe`：同一 verified presentation 在无 direct display bridge 时于窗口结束后转为 unavailable；`objectVisible=false`、`characterVisible=false`、`unavailableVisible=true`。截图 `formal-stock-fallback.png`。
- 21 项扫描覆盖双手剑、战刃、盾牌、单/双手斧、弓、枪、单/双手锤、长柄、单手剑、霜之哀伤、法杖、拳套、匕首、投掷、弩、魔杖和钓鱼竿。逐项应用 M2 camera/scale；正式页第 21/22 页验证对象池翻页复用，重新登录验证冷启动恢复。
- 临时 WeaponAudit/UI Audit 插件均已从客户端移回证据目录，不进入正式 bundle。

## 构建、部署与自动验证

- Core/module 部署 ID：`20260722-030806-294`；x64 RelWithDebInfo `worldserver.exe` SHA-256 `566354a5d2e08428a62befa6648766f1e265928949a4058cc0128f54e2d2e354`。
- AddOn 阶段 3 初始备份：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\addon-backups\20260722-030815-stage3`；stock fallback 补丁备份：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\addon-backups\20260722-stage3-stock-fallback`。
- AddOn Python：203 项通过、2 项按外部可选条件跳过；SoloCam Python：34 项通过、9 项按外部工具条件跳过；module Python：130 项通过。
- Lua 5.1：27 个正式/QA Lua 文件通过语法检查；目录生成器带命名 evidence pack 执行 `--check` 通过。
- SoloCam x86 原生 CameraProfile、DisplayInfoBridge、ItemCameraBridge 三组测试通过；DLL/loader/process probe 均为 x86。`SoloCam.dll` SHA-256 `ba0014cb292a120fb7c68aab96f4aa65d1a8ec401a2be052d377cb22e8b8efac`。

## 回滚

presentation、generated catalog、module metadata 与 AddOn renderer 必须成套回退。优先使用上述 AddOn 备份恢复 `Core/Catalog.lua`、generated catalog 和 `UI/Wardrobe.lua`；若回退服务端目录，则同时恢复匹配的 worldserver/module 版本。不得重新启用旧 demo identity、NPC placeholder 或角色模型 fallback。
