# 阶段 1：基础衣橱媒体合约与客户端验收

日期：2026-07-22  
状态：已完成；媒体合约、生产引用、基础客户端可见性、launcher 生命周期持久化、三档分辨率抽查和可选覆盖共存均已闭合。

## 范围与提交

- AddOn 提交：`bdbd597`（`fix: make base wardrobe media self contained`）。
- 本阶段没有修改 module、Core、数据库、DLL、MPQ 或 WDB。
- 基础媒体全部随 AddOn 跟踪；默认 UI 不再依赖 `Media/Retail` 或开发机的外部资源。

## 交付物

- `tools/media/generate_base_ui_media.py` 生成并校验三个确定性 TGA：11 槽位 atlas、圆形 selected/hover atlas、mount portrait。
- `Media/assets.json` 升级为 schema 2，区分 `requiredForBaseUI` 和 `optionalExternalFiles`，并为每个基础文件记录来源、许可、格式、尺寸和 SHA-256。
- `UI.Media` 的 launcher、mount portrait、slot atlas、round highlight 都改为 AddOn 自有路径。
- `test_media_contract.py`、`New-RoundTwoBundle.ps1` 与 `Test-RoundTwoBundle.ps1` 均验证生产 Lua 引用、TGA 格式/尺寸/Hash 和基础文件存在性。

## 静态与干净树验证

以下命令在 AddOn worktree 运行：

```powershell
python tools\media\generate_base_ui_media.py --output-root addon\SoloCollections\Media --check
python -m unittest discover -s tools\collections\tests -p 'test_media_contract.py' -v
```

生成器检查与 5 个媒体合约测试均通过。Release helper 也在源树和干净 AddOn archive 中通过；archive 位于 `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\temp\round3-media-clean-20260722T222620`，不含 `Media/Retail`，且没有缺失的默认媒体引用。

## 真实客户端证据

证据目录：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\client-stage1`。

- `stage1-post-restart-open.jpg`：自有 mount portrait 在全新客户端进程中显示。
- `stage1-slots-fresh-client.jpg`：11 个槽位图标全部显示。
- `stage1-slot-selected-hover.jpg`：selected 金环与 hover 蓝环均可见。
- `stage1-slot-tooltip-verified.jpg`：`HEAD` 的真实 OnEnter handler 在客户端显示“头部” tooltip。
- `stage1-launcher-drag.jpg`、`stage1-launcher-after-reload.jpg`：launcher 的 hover 提示和 `/reload` 后可见性。
- `stage1-resolution-narrow-wardrobe.jpg`、`stage1-resolution-maximized-wardrobe.jpg`：窄窗口与最大化高分辨率窗口下的槽位布局可见。
- `stage1-config-restored-world.jpg`：分辨率抽查后已恢复原始 `Config.wtf`、`SoloCollections.lua` 和客户端窗口大小，并重新进入世界。

首次把新 TGA 放入 AddOn 后，单独 `/reload` 不会刷新 WoW 已缓存的不存在文件路径；完整退出并重新启动客户端后，三个新资源均正常加载。因此部署流程必须在客户端启动前放置媒体，或要求完整重启，不能把一次 `/reload` 当成新文件发现验证。

## 2026-07-23 补充闭合证据

证据目录：`runtime-audit/stage1-media-launcher/stage1-20260723-051000/`。

- 在真实客户端临时安装未被 production Lua 引用的 `Media\\Retail\\launcher.tga` 后，base launcher 仍正常显示；right-click hover 提示、left-click 打开收藏日志和 `/reload` 均成功。临时覆盖已移出客户端目录。
- computer-use 的指针 `drag` transport 仍不会向 WoW 传递连续拖动事件，因此没有把它误写为物理鼠标拖动成功。为验证实际产品回调，客户端直接执行了 launcher 的 `OnDragStart`/`OnDragStop` 生命周期：位置被保存为 `CENTER/CENTER/-100/0`，reload 后在同一位置重现。截图和退出后的 SavedVariables 均已归档；测试存档已按 SHA-256 恢复。
- 1024×768、1920×1080 和 3440×1440 的真实客户端衣橱截图见阶段 4 的 `runtime-audit/stage4-layout/layout-20260723-042000/`。当前显示环境将最后一档实际缩放为 2537×1062，故报告保留真实尺寸；三个档位均无主窗口或检查器裁切。

阶段 1 的三个遗留验收项据此闭合。后续如需重新验证物理指针连续拖动，应使用能向 WoW 发送完整 drag 消息序列的交互设备；不需要改变基础媒体或 launcher 产品代码。
