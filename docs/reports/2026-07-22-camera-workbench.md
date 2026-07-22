# 阶段 4：武器镜头工作台与批量导出检查点

日期：2026-07-22

状态：核心工作流已实现并完成 21 条 verified 武器的关键路径验收；窄屏/超宽分辨率矩阵和 21 条逐一视觉回归仍未关闭。

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

## 尚未关闭的验收

- 尚未在 1024×768、1080p、超宽三档完成正式布局抽查。
- 尚未形成当前 21 条 verified 武器逐条视觉回归的完整人工证据矩阵。

因此阶段 4 保持“进行中”；实施计划只勾选已有实现与证据支撑的子项。
