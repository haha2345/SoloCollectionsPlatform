# SoloClientSuite

SoloClientSuite 把 `!!!ClassicAPI`、DragonUI、DragonUI_Options、项目维护的 DragonUI_NewEra 与 sibling SoloCollections 组合为一个 WoW 3.3.5a AddOns 套件。仓库不修改真实客户端；构建只写入忽略的 `build/Interface/AddOns`。

## Build / 构建

```powershell
pwsh -File .\tools\Sync-SoloCollections.ps1
pwsh -File .\tools\Inspect-ClientSuiteLayout.ps1 -SourceRoot .\Interface\AddOns -VerifyLock
pwsh -File .\tools\Build-ClientSuite.ps1
pwsh -File .\tools\Package-ClientSuite.ps1 -Version development
```

构建必须恰好包含五个 AddOn 根目录，并且每个根目录直接包含自己的 `.toc`。脚本会拒绝多套一层、缺少 TOC 或与 `upstream/suite-lock.json` 不一致的上游输入。

## Delivery boundary / 交付边界

- SoloCollections 公共源码包：由 sibling 仓库维护，不包含第三方完整资源。
- 完整集成客户端 UI 包：由本仓库构建，保留每个上游 notice、commit 与 Hash。
- 当前仅为本地集成源码；部署真实客户端必须另行备份、授权和记录。

`Package-ClientSuite.ps1` 生成一次安装的 `Interface/AddOns` ZIP，以及逐文件 SHA-256 JSON。manifest 内嵌 `suite-lock.json`，记录 ClassicAPI、DragonUI、DragonUI_Options、DragonUI_NewEra 和 SoloCollections 的上游 commit、项目 patch 状态与目录 Hash。输出仅写入忽略的 `build/packages`，不会触碰真实客户端。

See `docs/architecture/dependency-layers.md` and `docs/architecture/update-and-rollback.md`.
