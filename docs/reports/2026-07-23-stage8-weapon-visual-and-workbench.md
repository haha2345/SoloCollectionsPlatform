# 阶段 8：武器视觉抽样、镜头工作台与 model outlier 闭环

日期：2026-07-23

本记录覆盖阶段 8.4 的视觉与工作台闭环，以及随后完成的一个真实 model-scope outlier 修复与 v2 实机回归。性能门槛另见独立报告；阶段 9 的发布候选与最终人工矩阵仍未关闭。

## 生产身份

- bundleId / assetPackVersion：`round-two-stage8-weapon-presentation-v1`
- public contract：`3,541 READY + 149 UNAVAILABLE = 3,690`
- mapping hash：`fd5bfff27abddd0781065652c19e49e98786dbb80d7a098adf3cfb27237b35e1`
- presentation hash：`595f072f31f3cda3d0722a2caf11e2390cb3bf36971f7040cca230ddbe7ac402`
- presentation source hash：`964d4c13359ae75a609ff115597ac16b83d51c7c5ba1324d2107b93a6fb38e9f`

## 视觉抽样

抽样计划和实机产物位于：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-visual-sample-v1\stage8-weapon-visual-hot-20260723-115834-805`

- 计划：134 条（131 READY、3 UNAVAILABLE），计划 SHA-256：`8640e8560a5b68c1f41b62d5ed5f28ed6a4fd81bc9bf36771891aa3d81576af3`。
- 每个 weapon family 覆盖首/中/末、最小/最大 bounds、共享模型不同纹理、主手/副手；共 19 个 family、18 个共享模型不同纹理 family。
- 专项覆盖盾牌、书本/副手、拳套、弓、弩、枪、魔杖、投掷和钓鱼竿。
- 真实生产衣橱以固定 18 卡池完成 8 页截图，CSV 为 `131 READY / 3 UNAVAILABLE / 0 failed`，CSV SHA-256：`de141482e665bc1be97f444b773a53a0b38b4c81e3039c435fbede590fe5c47d`。

已人工复核截图 01、02、04、06、08：所有 READY 均显示为预期的 standalone M2；UNAVAILABLE 仍显示原物品信息和原因，不存在角色/NPC fallback、黑模或空模型。

## 非阻塞构图记录

计划中有 11 条几何极端比例或超大 radius 的视觉 outlier。它们在实机中均加载了 canonical M2；少数会出现较紧的裁切或留白，属于后续镜头构图优化，而不是资源失败。因此当前不把它们改标为 `UNAVAILABLE`，也不批量写入逐件 appearance override。

## 真实工作台导出与隔离重建

真实客户端工作台导出保存于：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-workbench-v1\workbench-export-20260723-1207\model-scope-export.jsonl`

- 对 appearance `200065`（source item `1958`）选择 `model` scope，得到稳定模型键 `m2:bddab4f732892c1474dce944b14a6c41db7397f88c2d360553f8df7ebb695754`。
- 在工作台作小幅 yaw 调整后，以“加入批次 → 复制本次修改”导出真实 JSONL；不是手工构造的 JSON。
- `camera_tuning_import.py` 生成仅审核候选；`camera_tuning_round_trip.py --approve` 只在 F 盘 scratch 中应用并重建，不会写回 canonical source。
- 隔离重建证明该 model scope 影响 7 个共享该模型的 appearance，且 canonical `appearance_presentations.json` hash 保持 `964d4c...e9f` 不变。

此闭环也发现并修复了两个兼容问题：工作台审核器现在接受 schema 3 的 `READY` 状态；批准模拟会同步 staged `m2Camera` 与 generator 实际读取的 `autoCamera`，避免重建回退到旧姿势。

## SavedVariables 边界

工作台测试前备份的生产 SavedVariables 与当前文件 SHA-256 一致：

`73ba019b93a5da520792d0db541dfe3ea4fce3b81c51bffa50d719e2d4d563ef`

因此本次记录未把测试调整留在玩家生产配置中。

## v2：真实 model-scope outlier 闭环

`appearanceId 217942`（source item `50709`，`TWO_HAND_AXE`）是旧 21 条基线中唯一需要本次处理的资源异常。它的 canonical 模型键为
`m2:aaa7aada31fc60e9b2625d3353003bdb9b1b3debd1dc4a2f74c25261efa333e5`，旧 M2 header bounds 把特效纳入半径，导致安全自动构图把真实斧身缩得过小。处理只在模型层发生，未添加 appearance override：

- 审核后的模型覆盖源为 `catalog/source/overrides/weapon_model_camera_overrides.json`，SHA-256：`d5302ad11f701621e63714eeecf9ffa8b616d0247696e03ab5fa20e42f906724`。
- 覆盖策略为 `VERTEX_MESH_BOUNDS_CAMERA`，原因码为 `HEADER_BOUNDS_INCLUDE_EFFECTS`；有效 pose 保持 yaw/pitch/roll/target，只把 distance scale 从自动 fallback 的 `0.72` 收到 `0.60`。
- 生成器同时以顶点网格 bounds 重写该 M2 的可见 bounds；原输入 M2 hash 为 `aaa7…333e5`，受控输出 hash 为 `bca7f99a94d7e00015a58a4a07c620fc191f50df50760992645f6e30cebd85a2`。
- 运行时发现 `generatedModelCameraOverride` 已进入 generated catalog、但没有被 `Core/Catalog.lua` 投影到 AddOn record；已修复该字段投影并为 target 加入合同测试。工作台当前选择的是 family scope，因此编辑栏仍展示其可编辑的 `0.72` fallback；运行时审计的 `poseSource=generatedModel` 是实际生效值。

v2 生产身份如下：

- bundleId / assetPackVersion：`round-two-stage8-weapon-presentation-v2`
- bundle manifest：`976572e29d1d2ce8b5272a75b47d6c1ab1b73d019961fc1c4ad4533a71f9910d`
- appearance presentation hash：`6b67de7eafcd76500541b44cc547dd89f03e8a14ba0a7c8a7ac542de4bacf336`
- presentation source hash：`e91762e95a8d3e2b7814533e6af311536bfd5cca8c607e9b33fc0967b1cb98ee`
- mapping hash 仍为 `fd5bfff27abddd0781065652c19e49e98786dbb80d7a098adf3cfb27237b35e1`。

资产安装证据为
`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-mpq-install-v2\weapon-shadow-install-20260723-155357-784\installation-manifest.json`；修复投影后的 AddOn 部署证据为
`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-addon-deploy-v3\stage8-presentation-addon-20260723-160559-133\deployment-manifest.json`。

## v2：旧基线与全量实机回归

旧基线计划位于
`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-legacy-regression-v2\legacy-baseline-visual-plan.json`。

- 选择器对全部 21 条旧基线逐条锁定 `syntheticDisplayId`、`modelPath` 与 `m2Camera` 零漂移；其中 20 条仍为公开衣橱卡，`212036` 被明确保留为 `RETAINED_BASELINE / NONPUBLIC_BASELINE`，不应进入公开 UI。
- 20 条公开旧样本在热缓存真实客户端审计中为 `20 READY / 0 UNAVAILABLE / 0 failed`，CSV SHA-256：`34697dcc88416fd631b90ceb65f137a934c35a0592abc12a491df2ac504cd570`。截图 `screenshots/weapon-visual-sample-02.jpg` 可见 `217942` 的完整斧身；这不是仅靠静态 M2 检查的结论。
- `217942` 的实机行记录为 `READY`、synthetic display `40006`、canonical model path 匹配、`poseSource=generatedModel`、`stableTicks=3`、`readyMilliseconds=16`；其 data-layer `m2Camera` 仍为旧基线 `0.72`，额外 model-scope pose 是针对 header-bounds 缺陷的显式、可审计例外。
- 全量 v2 热缓存审计位于
  `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-runtime-audit-v2\stage8-wardrobe-runtime-hot-20260723-162349-573`：`3,541 READY / 149 UNAVAILABLE / 0 failed`。导出的 CSV SHA-256 为 `d8f49e8c64d04f8ad79f8b31cd205c566d3ce26d1181be4c8dc5eb7fe84ce8ab`，并记录 presentation source、report 与 catalog manifest hash。

因此此 outlier 已按“model override 优先、appearance override 仅在确有单件必要时使用”的规则关闭；该模型当前只有一个 appearance，所以没有凭空扩大覆盖范围。

## 尚未关闭的事项

- 阶段 9 的干净检出、发布候选、安装/回滚演练和最终人工客户端矩阵。
