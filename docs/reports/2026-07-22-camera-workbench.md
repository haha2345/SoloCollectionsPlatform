# 阶段 4：武器镜头工作台与批量导出检查点

日期：2026-07-22

状态：已完成。阶段 4 的布局、21 条运行时相机回归、三层覆盖和导出→审核→临时生成→清空 SavedVariables round-trip 均已以真实客户端证据闭合；production `STANDALONE` 仍保持 21 条，未因本阶段扩大。

## 范围

- 本检查点仅修改 AddOn、appearance presentation 生成器、审核导入器、测试和证据构造工具；module、Core、数据库、DLL、MPQ 与 WDB 均未修改。
- 客户端 AddOn 部署前备份：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\addon-backups\20260722-stage4-camera-workbench\SoloCollections`。
- 当前已部署并实测的文件为 `Core\Bootstrap.lua` 和 `UI\Wardrobe.lua`；测试客户端为 `D:\Games\wow335\World of Warcraft11\Wow.exe`。

## 已实现的工作流

- `Bootstrap.lua` 将旧的 `m2CameraTuning` 迁移到版本化的 `cameraTuning`：支持 `weaponFamily`、`model`、`appearance` 和保留的 `bodyProfile` 域，保存 legacy 备份，并拒绝未知 scope、非法键、非有限数和越界 pose。未写入 override 时不新建条目；各域有条目上限。
- `CameraTuning.Get/Set/Reset` 保持稀疏存储。解析优先级固定为 `appearance > model > weaponFamily > autoCamera`，编辑某一 scope 时只继承更低层，重置只影响当前 scope。
- appearance presentation v2 为每个 standalone record 投影稳定 `modelSignature` 与 `autoCamera`。它们属于 presentation，不进入 canonical identity mapping；21 条当前 verified 记录与 source 的 camera 值逐字段一致。
- 工作台已从 DIALOG 改为物品页右侧检查器：打开时 6 列卡片池重排为 4 列，关闭恢复 6×3 和原分页。检查器含 scope、七个 pose 字段、数值框、细调/粗调、身份元数据、dirty 状态、上一/下一条、未校准导航、重置、丢弃确认、单条/批次 JSONL 导出。
- `camera_tuning_import.py` 只生成待审核候选，不会改写 canonical source。它检查导出 header、版本、asset pack、presentation hash、appearance/model/family 身份对应、pose 范围及重复冲突。

## 静态与生成验证

在 AddOn worktree 中执行：

```powershell
Push-Location tools\collections\tests
python -m unittest -v `
  test_camera_workbench_contract `
  test_camera_tuning_import `
  test_appearance_presentations `
  test_appearance_catalog `
  test_wardrobe_camera_set_contract
```

结果为 **33/33 通过**。覆盖了迁移/稀疏上限、层级解析、v2 projection、21 条基线零漂移、布局控制、JSONL 导入的成功与失败路径，以及既有目录/套装合同。

以下生成器检查也通过：

```powershell
python tools\catalog\appearance_presentations.py `
  --source catalog\source\appearance_presentations.json `
  --appearance-sources catalog\generated\appearance-sources.json `
  --evidence-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\stage4-camera-workbench-fixed-inputs `
  --output catalog\generated\appearance-presentation-report.json --check
```

结果：source/report 均为 21 条、appearance 集合一致、`cameraDriftAppearanceIds=[]`、共 21 个 model signature。`git diff --check` 与 25 个 AddOn Lua 文件的 Lua 5.1 语法检查亦通过。

## 真实客户端验证

在 2042×1200 客户端中完成以下实际交互：

- verified 武器 `207278` 的自动 pose 为 `yaw=1.04`；细调到 `1.05` 后“重置当前层”恢复 `1.04`。
- family override 从 `207278` 切换到同属 `TWO_HAND_SWORD` 的 `206762` 后仍生效；重置 family 后回到两者各自 auto baseline。
- model override 从 `206762` 切到不同 `modelSignature` 的 `207278` 不串值；appearance override 同样只作用于当前 appearance。两种临时 override 随后均已在工作台中重置。
- “复制当前”和“复制本次全部修改”都会选中 EditBox，真实按下 `Ctrl+C` 后客户端聊天记录确认；“加入批次”、丢弃确认和 `/reload` 均可用。
- 使用等价的已捕获 JSONL 输入 `client-round-trip\camera-export-207278.jsonl` 运行导入器，成功生成 `camera-review-candidates-207278.json`；`--check` 通过。该候选是审核输出，未自动扩大或改写 production `STANDALONE`。
- 打开/关闭工作台、翻页、切换 Items/Sets、切换武器记录和 `/reload` 后均未观察到遮挡或状态串扰。unavailable record 的禁用与原因展示见 `stage4-camera-workbench-unavailable-live.jpg`，verified inspector 见 `stage4-camera-workbench-verified-live.jpg`。

## 2026-07-23 补充闭合证据

- 布局矩阵：真实客户端分别以 `1024×768`、`1920×1080` 和 `3440×1440` 配置打开工作台。证据位于 `runtime-audit/stage4-layout/layout-20260723-042000/`。在当前显示环境中，最后一档实际截图为 `2537×1062`（保持超宽宽高比）；报告保留该实际尺寸而不将其误称为原生 3440 像素。三档中检查器、卡片、分页和关闭按钮均完整可见，测试前的 `Config.wtf` 与 `SoloCollections.lua` 已按 SHA-256 恢复。
- 21 条运行时回归：`runtime-audit/stage4-weapon-camera/weapon-camera-20260723-041440/verification.json` 记录 3 页、21/21 条模型路径与 canonical presentation 一致，且每条均已在真实客户端接受 M2 相机应用；审计范围包含公开衣橱刻意隐藏、但仍属于 reviewed baseline 的 Frostmourne 记录。临时审计 AddOn 已移出客户端目录。
- 审核 round-trip：`tools/catalog/camera_tuning_round_trip.py` 只在传入的 F 盘临时目录投影审核候选，不改写 canonical source。207278 的已捕获 JSONL 候选将 yaw 从 baseline `1.04` 投影为 `1.05`；生成后模型仍为 `1.05`，source hash 未变。真实客户端加载临时 Catalog、清空 `cameraTuning` 后退出，`runtime-audit/stage4-round-trip/SoloCollections.round-trip-after.lua` 记录 `autoYaw=1.05` 和 `hasOverride=false`。临时 Catalog 与测试 SavedVariables 均已按 SHA-256 恢复。
- 工作台截图：`runtime-audit/stage4-round-trip/round-trip-207278-workbench.jpg` 显示清空覆盖后的内嵌检查器处于可用状态；该截图同时保留了真实客户端的 “截图完成” 提示。

因此阶段 4 已闭合；后续阶段只可在本阶段已固定的 21 条基线和严格审核投影之上扩展，不得把临时候选直接写入 production presentation。
