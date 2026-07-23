# 阶段 8：全量武器目录性能实测

日期：2026-07-23

## 范围与判定

- bundleId / assetPackVersion：`round-two-stage8-weapon-presentation-v1`
- public contract：`3,541 READY + 149 UNAVAILABLE = 3,690`
- appearance presentation hash：`595f072f31f3cda3d0722a2caf11e2390cb3bf36971f7040cca230ddbe7ac402`
- 本次审计复用正式 `Wardrobe.lua` 的固定 18 卡片/模型池；临时 QA AddOn 仅驱动和记录，不引入第二套渲染器。

性能审计连续扫描全目录两轮（每轮 205 页、共 410 页），并在最后执行主手/副手和筛选器的四次快速双 generation 切换。所有原始 SavedVariables、CSV、JSON、临时 QA AddOn 和 WDB journal 都只保存在 F 盘 evidence root。

## 实机结果

| 缓存 | runId | 首页加载 | 第 1 / 2 轮 | Lua 峰值（第 1 → 第 2 轮） | 工作集 | 登录至完成 |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| 真冷 WDB | `stage8-wardrobe-performance-cold-20260723-123811-360` | 20 ms | 26,379 / 26,583 ms | 197,186.698 → 194,496.598 KiB | 352,763,904 B | 82,175 ms |
| 热缓存 | `stage8-wardrobe-performance-hot-20260723-123959-901` | 19 ms | 26,526 / 26,584 ms | 197,198.718 → 194,415.536 KiB | 352,718,848 B | 82,042 ms |

两个 run 均为 `3,541 READY / 149 UNAVAILABLE / 0 failed`。第二轮 Lua peak 和 end memory 都低于第一轮，满足不超过第二轮基线 20% 的门槛；不存在随目录扫描持续增长的证据。

`weapon-presentation-performance-filters.csv` 对四个快速场景均记录 18 条当前页记录、generation delta `2`、`crossContamination=false`：

- MAINHAND / AUTO / page 2；
- OFFHAND / AUTO / page 2；
- MAINHAND / ONE_HAND_SWORD / page 2；
- OFFHAND / SHIELD / page 2。

固定卡池为 18，观测到的最大常驻 OnUpdate 为 18；model ready window 固定 3 秒、需要连续 3 个 stable tick，因此失败条目没有无限 retry 路径。

## 冷缓存与恢复边界

冷缓存 run 由 `Start-SoloCollectionsWeaponPresentationAudit.ps1` 调用 append-only WDB 状态机：在客户端关闭时备份并同卷隔离 `Cache/WDB/zhCN`，测试结束后隔离新生成的 WDB 并逐文件恢复原目录。其 `wdb-backup-manifest.json` 最终状态为 `RESTORED`，有 1 份 generated-during-test quarantine 记录。

两个 run 的生产 `SoloCollections.lua` 均恢复到启动前 SHA-256：`d8d052c238fae8fc06b4faaec33a1ebbc9d28feebe4af15fef763a4debeeea10`。已安装资产包合计 153,229,030 B（assets 151,000,743 B，locale 2,228,287 B），hash 由安装 manifest 与每次 run 的 `client-performance.json` 复核。

先前仅标记为 `cold`、但未执行 WDB 状态切换的两次尝试不作为冷缓存证据；启动器现已拒绝将这种标签替代真实冷缓存操作。

## 证据根目录

- 冷：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-performance-v1\stage8-wardrobe-performance-cold-20260723-123811-360`
- 热：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-performance-v1\stage8-wardrobe-performance-hot-20260723-123959-901`

每个根目录都包含 runtime audit CSV/summary、页/轮/筛选性能 CSV、client performance、SavedVariables 前后副本与 hash；冷 run 另包含 WDB backup manifest、journal 和生成缓存隔离清单。

## 尚未关闭的阶段 8 项

- 对一个明确视觉 outlier 完成真实工作台 model/appearance scope 调校复核。
- 对保留的 21 个旧样本进行单独的真实视觉与 pose 回归扫描。
