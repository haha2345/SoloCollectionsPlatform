# SoloClientSuite

SoloClientSuite 把 `!!!ClassicAPI`、DragonUI、DragonUI_Options、项目维护的 DragonUI_NewEra 与 sibling SoloCollections 组合为一个 WoW 3.3.5a AddOns 套件。可选的 `SoloCollections_EzUI` 由用户授权的 ezCollections 2.2 本地快照生成，只包含素材和来源标记。仓库不修改真实客户端；构建只写入忽略的 `build/Interface/AddOns`。

## Build / 构建

```powershell
pwsh -File .\tools\Sync-SoloCollections.ps1
pwsh -File .\tools\Inspect-ClientSuiteLayout.ps1 -SourceRoot .\Interface\AddOns -VerifyLock
pwsh -File .\tools\Build-ClientSuite.ps1
pwsh -File .\tools\Package-ClientSuite.ps1 -Version development
```

仓库源树必须恰好包含锁文件列出的 17 个 AddOn 根目录，并且每个根目录直接包含自己的 `.toc`。其中 `DragonUI_NewEra` 只保留公共层，11 个重模块位于独立的 `LoadOnDemand` sibling AddOn；脚本会拒绝多套一层、缺少 TOC 或与 `upstream/suite-lock.json` 不一致的上游输入。

要构建用户授权的完整 ezCollections 素材投影，显式传入两个源码目录；脚本不记录机器本地路径：

```powershell
pwsh -File .\tools\Build-ClientSuite.ps1 `
  -SoloCollectionsSource <SoloCollections-AddOn-root> `
  -EzCollectionsSource <ezCollections-2.2-AddOn-root>
```

该构建包含锁文件中的基础层、NewEra 的 11 个按需 sibling AddOn，以及一个生成的 `SoloCollections_EzUI`（若用户显式提供授权素材源）。导入器锁定版本、完整来源目录 Hash、九个关键 UI 文件 Hash，以及全部 222 个 `.blp`、`.tga`、`.wav` 素材的投影 Hash；任何不匹配都会停止构建。它不会导入 ezCollections 的 Lua、XML、`C_Transmog*`、插件消息或服务端逻辑。

NewEra 的基础层加载 `/neprofile` 启动 profiling；按需模块只能由对应的客户端入口或事件路由加载。目录、TOC 和锁文件只描述套件源码，不代表真实客户端已经部署或被验收。

## Delivery boundary / 交付边界

- SoloCollections 公共源码包：由 sibling 仓库维护，不包含第三方完整资源。
- 完整本地集成客户端 UI 包：由本仓库构建，保留每个上游 notice、commit 与 Hash；生成的 ezCollections 素材投影不得作为公共发布物上传。
- 当前仅为本地集成源码；部署真实客户端必须另行备份、授权和记录。

`Package-ClientSuite.ps1` 生成一次安装的 `Interface/AddOns` ZIP，以及逐文件 SHA-256 JSON。manifest 内嵌 `suite-lock.json`；本地素材构建还会嵌入 `EZUI-PROVENANCE.json`。输出仅写入忽略的 `build/packages`，不会触碰真实客户端。

See `docs/architecture/dependency-layers.md` and `docs/architecture/update-and-rollback.md`.
