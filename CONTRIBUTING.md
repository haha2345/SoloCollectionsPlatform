# 参与 SoloCollections / Contributing

[中文](#中文) · [English](#english)

## 中文

感谢你愿意帮助改进 SoloCollections。这里欢迎代码、目录审核、镜头参数、文档、
翻译和可复现的问题报告。

### 开始之前

1. Fork 仓库，从最新 `main` 创建功能分支。
2. 阅读 [开发指南](docs/DEVELOPMENT.md) 和与修改相关的架构文档。
3. 如果修改镜头，先阅读[镜头参数贡献指南](docs/CAMERA_CONTRIBUTIONS.md)。
4. 如果使用 AI/Agent，先让它阅读 [AGENTS.md](AGENTS.md) 和
   [Agent 开发指南](docs/AGENT_DEVELOPMENT.md)。
5. 一次 Pull Request 只解决一个清晰问题；不要顺手重构无关代码。

### 仓库边界

- 本仓库负责 AddOn、目录源、SC2 schema、生成器和可选 SoloCam。
- 服务端权威逻辑属于
  [`mod-solo-collections`](https://github.com/haha2345/mod-solo-collections)。
- 协议或目录 identity 变更通常需要两个仓库的配套 PR，并写明合并顺序。
- `catalog/source` 与 `catalog/review` 是可审核输入；不要手工修改
  `addon/SoloCollections/Data/Generated/Catalog.lua` 来绕过生成器。
- 游戏安装和服务端运行目录只是部署目标，不是源码源头。

### 禁止提交

- `Wow.exe`、补丁后的 EXE、DLL、PDB、MPQ、DBC、DB2、M2、SKIN、BLP 或 WDB；
- 从 Blizzard 客户端提取的素材；
- 数据库备份、真实配置、密码、token、SavedVariables、完整日志；
- `build`、`release`、`_work`、`__pycache__`、IDE 缓存或临时审计输出；
- 仅对某台电脑有效的绝对路径和个人目录。

项目自制或许可证允许再分发的素材必须更新
`addon/SoloCollections/Media/assets.json`，记录用途、来源、许可证、尺寸和
SHA-256。

### 代码修改

- 保持 WoW 3.3.5 Lua 5.1 兼容，不使用 Retail-only API。
- 客户端显示字段不能成为授权依据。
- SC2 消息只携带稳定、受限的 ID；不接受任意客户端脚本、法术或物品动作。
- 未知 identity、版本不匹配和资源缺失必须失败关闭。
- 保持固定对象池和有界 `OnUpdate`；不要让目录规模直接增加每帧工作。
- 改变行为时同步更新文档和相关检查。

### 镜头参数 PR

请在 PR 中提供：

- 客户端 build、`Wow.exe` SHA-256、locale，以及是否使用 HD/自定义模型；
- 角色 `raceId/sex/slot/profileKey`，或武器
  `appearanceId/modelSignature/weaponFamily`；
- 修改前和修改后截图，分辨率与 UI Scale；
- 镜头工作台导出的 JSONL；
- 选择 `bodyProfile`、`weaponFamily`、`model` 或 `appearance` scope 的理由；
- 至少一个普通轮廓和一个极端轮廓样本；
- `/reload`、翻页、快速切换和缺少 SoloCam 时的结果。

优先级固定为：

```text
appearance > model > weaponFamily > autoCamera
```

可共享问题优先使用 `model` 或 `weaponFamily`；只有单件确实异常时才使用
`appearance`。

### 可运行的检查

从仓库根目录执行：

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s tools\collections\tests -p "test_*.py" -v
python -m unittest discover -s client-extension\SoloCam\tests -p "test_*.py" -v
```

修改 SoloCam C++ 时：

```powershell
& .\client-extension\SoloCam\scripts\build.ps1
```

修改生成目录时，必须同时提交 canonical source、审核决定和所有受影响的生成
投影，并在 PR 中写明合法外部 evidence 的版本/hash；不能提交 evidence 中的
客户端资源或数据库内容。

### Pull Request 内容

PR 描述至少应包含：

- 问题和影响；
- 修改范围及未修改范围；
- 客户端、服务端和模块版本；
- 执行过的命令与结果；
- 真实客户端检查和截图，或明确说明尚未执行；
- 数据库/客户端文件是否变化以及回滚方法；
- 若使用 Agent，说明使用范围和人工复核过的部分。

提交信息建议使用简短的动词前缀，例如：

```text
fix: correct dwarf female chest camera
catalog: review off-hand presentation overrides
docs: explain clean module build
```

## English

Thank you for contributing code, catalog review, camera parameters,
documentation, translations, or reproducible issue reports.

### Before opening a pull request

1. Fork the repository and branch from the latest `main`.
2. Read [DEVELOPMENT.md](docs/DEVELOPMENT.md) and the relevant architecture
   document.
3. Camera changes must follow
   [CAMERA_CONTRIBUTIONS.md](docs/CAMERA_CONTRIBUTIONS.md).
4. Agent-assisted work must start by reading [AGENTS.md](AGENTS.md) and
   [AGENT_DEVELOPMENT.md](docs/AGENT_DEVELOPMENT.md).
5. Keep each pull request focused on one problem.

This repository owns the AddOn, catalog sources, SC2 schema, generators, and
optional SoloCam code. Authoritative server work belongs in
[`mod-solo-collections`](https://github.com/haha2345/mod-solo-collections).
Protocol or catalog-identity changes normally need coordinated pull requests.

Do not commit game executables, patched executables, DLL/PDB build outputs,
MPQ/DBC/DB2/M2/SKIN/BLP/WDB files, extracted client media, database dumps,
runtime configuration, credentials, SavedVariables, full logs, build caches,
or personal absolute paths.

Preserve WoW 3.3.5 Lua 5.1 compatibility and server authority. Unknown
identities, version mismatches, and missing assets must fail closed. Do not edit
generated Lua directly to bypass canonical sources and review decisions.

Camera pull requests must state the client build/hash/locale, model type,
race/sex/slot or weapon identity, resolution/UI scale, selected scope,
workbench JSONL, before/after screenshots, representative samples, and
reload/fallback results. Prefer `model` or `weaponFamily` scope for shared
problems and reserve `appearance` for true one-record outliers.

Run the relevant Python contracts and the x86 SoloCam build when applicable.
The pull request must distinguish automated checks from real-client
observation. If an agent was used, state its scope and what was reviewed by a
human.

Contributions are accepted under this repository's
GPL-3.0-or-later license. By submitting a pull request, you confirm that you
have the right to contribute the material under those terms.
