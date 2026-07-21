# SoloCollections 阶段 4：细边框与玩具网格验收报告

日期：2026-07-22

## 结论

阶段 4 已通过。坐骑、宠物、玩具与衣橱使用同一公共细边 helper；收藏状态边为 1 logical px，选中边为独立 2 logical px。玩具页使用 3 列、6 行、18 个复用 tile 的约束布局，在全部七档真实客户端矩阵中均得到 268px tile、16/16 左右 margin 与 6px 列间距。

## 实现结果

- `UI.CreateThinCardBorder(parent, thickness)` 从 `Wardrobe.lua` 抽到先加载的 `Templates.lua`。
- `UI.CreateCollectionCardBorders(parent)` 同时创建 1px 收藏边与 2px 选中边；选中、hover、收藏状态分别由不同 frame/texture 表达。
- 已收集颜色为 `0.58, 0.43, 0.16, 1`，未收集为 `0.38, 0.39, 0.40, 1`，选中为 `1.00, 0.78, 0.14, 1`。
- 坐骑/宠物列表与详情、玩具卡片均不再引用 `UI.Media.collectedFrame` 或 `UI.Media.uncollectedFrame`；页面外层 `ApplyNineSlice` 未改动。
- 玩具固定 `TILE_WIDTH=282` 已移除；宽度由容器宽度、16px padding 和 6px gap 动态计算，并在出现舍入余数时将整个三列 block 居中。
- `OnSizeChanged` 会重新布局，页面同时公开只读审计字段用于记录实际 tile、margin 与 gap。

## 自动回归

- SoloCollections：`205` 项通过，`3` 项因可选外部资源/本地部署条件跳过。
- SoloCam Python：`34` 项通过，`9` 项因可选 native/runtime 条件跳过。
- mod-solo-collections：`130` 项通过；包含现有 4 个玩具映射及 action schema/handler/cooldown/replay 合同。
- `git diff --check`：通过。
- Lua 5.1 运行时加载：七档客户端均完成两轮审计且没有 FrameXML/Lua 阻断错误。

## 真实客户端矩阵

证据根目录：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage4-layout\20260722-045634-440`

| 分辨率 / UI Scale | 截图像素 | 两轮 READY | reload 恢复 | tile | 左/右 margin | gap |
|---|---:|---:|---:|---:|---:|---:|
| 1024×768 / 1.00 | 1024×768 | 是 | 是 | 268 | 16 / 16 | 6 |
| 1366×768 / 1.00 | 1366×768 | 是 | 是 | 268 | 16 / 16 | 6 |
| 1920×1080 / 1.00 | 1920×1080 | 是 | 是 | 268 | 16 / 16 | 6 |
| 1920×1080 / 0.80 | 1920×1080 | 是 | 是 | 268 | 16 / 16 | 6 |
| 1920×1080 / 0.64 | 1920×1080 | 是 | 是 | 268 | 16 / 16 | 6 |
| 2560×1440 / 1.00 | 2560×1440 | 是 | 是 | 268 | 16 / 16 | 6 |
| 3440×1440 / 1.00 | 3440×1440 | 是 | 是 | 268 | 16 / 16 | 6 |

每档同时验证：坐骑/宠物列表与详情的 1px/2px 合同、收藏颜色在 `SetSelected()` 前后不变、玩具首末列、collected/uncollected/selected/hover 四种视觉、1/2/4/18 条可见记录、18 个复用 tile 和两次 `/reload`。截图中的 18 条为临时审计记录；正式目录仍显示当前 4/4 玩具，未修改权威目录或 owned 状态。

3440×1440 档最初被 Windows 工作区和 150% DPI 虚拟化限制。正式证据使用显卡已公开的临时 3840×2160 DSR 模式，并让审计进程与 WoW 进程声明 DPI aware；最终截图为真实 3440×1440。脚本在 `finally` 中恢复显示模式、兼容层环境变量和客户端 `Config.wtf`。被拒绝的受限截图仍留在证据根目录的带原因后缀目录中，未计入通过矩阵。

## 证据校验

- `matrix-summary.csv` SHA-256：`03f76c2235ab78f2044caf3db09d306bc117f0a8440f204250457d5fed263013`
- `matrix-summary.json` SHA-256：`0d53f668a5a45d93738afb5a43913c2a50cab42c0e6b8aa41a7e2b1c385609b3`
- 1920×1080 / 0.80 主截图 SHA-256：`b671e3fd6774d9b56a8ca460f432d1ff2ad67493f62bf9a38641b79ed925668f`
- 3440×1440 主截图 SHA-256：`03f903c393a34be9eae70f9b2031c30968045b225d79d8486232412092bcf902`

矩阵汇总记录每档的 SavedVariables 与截图 Hash，可独立核对每一轮结果。运行脚本不保存明文凭据，所有临时编译目录与证据均位于 F 盘。
