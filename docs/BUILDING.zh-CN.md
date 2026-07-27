# SoloCollections 编译与开发环境

## 1. 组件与工具链

| 组件 | 环境 | 是否编译 |
| --- | --- | --- |
| AddOn | WoW 3.3.5 Lua 5.1/FrameXML | 否 |
| 目录/协议工具 | Python 3.10 | 运行生成器和检查 |
| SoloCam | Windows 10/11、VS 2022、MSVC v143 x86、Windows SDK | 是 |
| C++ 后端 | AzerothCore 官方依赖，x64 Core build | 随 Core 编译 |
| 客户端资源 | PowerShell、Python、x64 StormLib、用户自己的纯净客户端 | 只在本机构建 |

AzerothCore 当前 Windows 官方要求包括 CMake 3.27+、Visual Studio 2022
Desktop C++、Boost 1.78+、MySQL 8.0+ 和 OpenSSL 3.x。版本可能变化，以
[官方 requirements](https://www.azerothcore.org/wiki/windows-requirements)
为准。

## 2. 获取源码

```powershell
git clone https://github.com/haha2345/SoloCollections.git
git clone https://github.com/haha2345/mod-solo-collections.git
Set-Location .\SoloCollections
git switch -c feature/my-change
```

建议两个仓库放在同一父目录，但不要放到游戏安装或 worldserver 运行目录。

## 3. Python 环境

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r .\client-extension\SoloCam\requirements-dev.txt
```

把临时目录放在仓库忽略的 `_work`：

```powershell
$tempRoot = Join-Path $PWD '_work\python-temp'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$env:TEMP = $tempRoot
$env:TMP = $tempRoot
$env:PYTHONDONTWRITEBYTECODE = '1'
```

## 4. AddOn

AddOn 不需要编译。开发副本位于 `addon/SoloCollections`。可以运行：

```powershell
python -m unittest discover -s .\tools\collections\tests -p "test_*.py" -v
```

如果系统安装了 Lua 5.1/`luac`，还可以对 `addon/SoloCollections` 下的 Lua
逐个执行 `luac -p`。不要用 Lua 5.4 的行为替代 3.3.5 客户端验证。

复制到测试客户端前确认目标路径，并保留原 AddOn 备份。真实客户端中的
SavedVariables 和截图属于测试输出，不提交到 Git。

## 5. 目录生成

最终 AddOn 目录文件由 canonical source 和 review data 生成。生成器入口：

```powershell
python .\tools\catalog\generate_catalog.py --help
```

典型 check：

```powershell
python .\tools\catalog\generate_catalog.py `
  --module-root ..\mod-solo-collections `
  --evidence-root <合法外部evidence目录> `
  --check
```

`evidence-root` 可能包含从用户自己的 DBC、数据库或客户端模型提取的结构证据，
不得提交。仓库只保留 canonical CSV/JSON、审核决定、hash 和生成投影。

目录变更应同时更新：

- `catalog/source`；
- 对应 `catalog/review`；
- `catalog/generated`；
- `addon/SoloCollections/Data/Generated`；
- module 的 `data/generated` 与 `src/generated`。

不要手工改生成 Lua 作为唯一修改。

## 6. 编译 SoloCam

安装 Visual Studio 2022 Desktop development with C++，包含 MSVC v143 的
x86/x64 工具和 Windows SDK。构建脚本会使用 `SOLOCOLLECTIONS_VCVARS` 或
Visual Studio Installer：

```powershell
$env:SOLOCOLLECTIONS_VCVARS = '<VS>\VC\Auxiliary\Build\vcvarsall.bat'
& .\client-extension\SoloCam\scripts\build.ps1
```

产物位于被忽略的：

```text
client-extension/SoloCam/build/Release/SoloCam.dll
client-extension/SoloCam/build/Tests/
```

Portable Python 检查：

```powershell
python -m unittest discover -s .\client-extension\SoloCam\tests -p "test_*.py" -v
```

依赖真实 EXE 的检查只读取用户显式设置的文件：

```powershell
$env:SOLOCOLLECTIONS_WOW_EXE = '<WoW>\Wow.exe'
```

没有变量时应跳过二进制依赖项，不能自动下载或伪造 EXE。

## 7. 编译服务端模块

模块的完整步骤位于
[`mod-solo-collections` README](https://github.com/haha2345/mod-solo-collections#readme)。
把模块放到 `<AzerothCore>/modules/mod-solo-collections`，重新配置
`MODULES=static`，再编译 `authserver` 和 `worldserver`。

独立模块可以使用 fallback build metadata 编译。制作成套候选时，先生成精确
AddOn/module/Core 信息：

```powershell
& .\tools\release\New-SoloCollectionsBuildInfo.ps1 `
  -AddonRoot $PWD `
  -ModuleRoot ..\mod-solo-collections `
  -CoreRoot <AzerothCore源码> `
  -CoreBuildRoot <AzerothCore构建目录> `
  -Configuration RelWithDebInfo
```

生成的 `src/generated/SoloCollectionsBuildInfo.inc` 是本地构建输入，被模块
`.gitignore` 排除。

## 8. 统一源码包

所有仓库应先有明确 commit。输出目录必须在仓库外或忽略目录：

```powershell
python .\tools\release\build_unified_release.py `
  --version <version> `
  --addon-repo $PWD `
  --module-repo ..\mod-solo-collections `
  --core-repo <AzerothCore源码> `
  --output-dir (Join-Path $PWD '_work\release-candidate')
```

生成器只允许项目源码、清单和许可证；EXE、DLL、MPQ、PDB、数据库、凭据和
客户端提取素材会被拒绝。公开 GitHub Release 仍需要单独的许可证和来源审核。

## 9. 客户端资源

独立武器资源构建见 [BUILD_MPQ.zh-CN.md](BUILD_MPQ.zh-CN.md)。先生成到临时
目录并回读 hash；只有明确要求时才部署。任何同名客户端文件都要先识别和备份。
