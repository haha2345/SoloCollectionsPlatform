# 阶段 8：武器 model outlier 修复证据

日期：2026-07-23

## 结论

公开武器 `appearanceId 217942`（source item `50709`）已从“header bounds 包含特效导致构图过小”的 outlier，收敛为一个模型范围的、可重放的镜头与 M2 bounds 修复。没有引入 appearance scope 覆盖，也没有改变服务端 appearance mapping。

## 有效输入与限定范围

- model signature：`m2:aaa7aada31fc60e9b2625d3353003bdb9b1b3debd1dc4a2f74c25261efa333e5`
- canonical path：`Item\ObjectComponents\SoloCollections\SC_Axe_2H_IcecrownRaid_D_02_50709.m2`
- native display / synthetic display：`64879 / 40006`
- 覆盖源：`catalog/source/overrides/weapon_model_camera_overrides.json`
- 覆盖源 SHA-256：`d5302ad11f701621e63714eeecf9ffa8b616d0247696e03ab5fa20e42f906724`
- 策略：`VERTEX_MESH_BOUNDS_CAMERA`，理由：`HEADER_BOUNDS_INCLUDE_EFFECTS`
- 有效 pose：`yaw=1.0, pitch=-0.32, roll=0.96, distanceScale=0.60, target=(-0.35,-0.05,0)`。

输入 M2 SHA-256 为 `aaa7aada31fc60e9b2625d3353003bdb9b1b3debd1dc4a2f74c25261efa333e5`，生成后的受控 M2 SHA-256 为 `bca7f99a94d7e00015a58a4a07c620fc191f50df50760992645f6e30cebd85a2`。变更仅修正可见网格 bounds；model path、synthetic display 和旧 `m2Camera` 数据保持基线值。

## 运行时投影修复

生成 catalog 已带 `generatedModelCameraOverride`，但 AddOn 的 `Core/Catalog.lua` 曾在 record 投影时遗漏该字段。修复后，运行时优先级为 appearance > player model > generated model > weapon family > auto。对应静态测试同时验证生成数据、Lua 投影和目标模型的 `0.60` distance scale。

工作台选择的是可编辑 scope，而不是“effective renderer source”；因此选择 `weaponFamily` 时界面字段显示 `0.72` fallback 并不代表 runtime 忽略了 generated model 覆盖。运行审计中的 `poseSource` 是有效值的证据。

## 实机证据

v2 资产安装 manifest：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-mpq-install-v2\weapon-shadow-install-20260723-155357-784\installation-manifest.json`

AddOn v3 部署 manifest：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-addon-deploy-v3\stage8-presentation-addon-20260723-160559-133\deployment-manifest.json`

旧基线视觉审计（20 条公开旧样本）输出 `20 READY / 0 UNAVAILABLE / 0 failed`；它的截图和 CSV 位于：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-legacy-regression-v2\stage8-weapon-visual-hot-20260723-161944-413`

全量生产热缓存审计输出 `3,541 READY / 149 UNAVAILABLE / 0 failed`，目标行记录 `poseSource=generatedModel`、`stableTicks=3`：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-runtime-audit-v2\stage8-wardrobe-runtime-hot-20260723-162349-573`

全量 CSV SHA-256：`d8f49e8c64d04f8ad79f8b31cd205c566d3ce26d1181be4c8dc5eb7fe84ce8ab`。
