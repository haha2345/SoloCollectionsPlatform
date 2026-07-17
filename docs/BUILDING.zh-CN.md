# 源码开发、测试与编译环境

## 1. 推荐系统

- Windows 10/11 x64；
- PowerShell 5.1 或 PowerShell 7；
- Git 2.40+；
- Python 3.10；
- Visual Studio 2022 Build Tools；
- 工作目录放在空间充足的非系统盘。

## 2. 获取源码

```powershell
git clone https://github.com/haha2345/SoloCollections.git SoloCollections
Set-Location .\SoloCollections
git switch -c feature/my-change
```

不要在 `Interface/AddOns` 中长期开发。仓库是源码源头，客户端和服务器只是
部署目标。

## 3. AddOn

AddOn 使用 WoW 3.3.5 的 Lua 5.1/FrameXML API，不需要编译。不能直接使用
Retail 的 `C_MountJournal`、`SetAtlas`、`ModelScene` 等现代 API。

运行契约测试：

```powershell
$temp = Join-Path $PWD '_work\test-temp\collections'
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$env:TEMP = $temp
$env:TMP = $temp
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s tools\collections\tests -p 'test_*.py' -v
```

部署到测试客户端前先使用 `-WhatIf`：

```powershell
& .\tools\collections\deploy_phase1.ps1 `
  -AddonTarget 'D:\path\to\WoW\Interface\AddOns\SoloCollections' `
  -ServerLuaTarget 'D:\path\to\server\lua_scripts\solo_collections.lua' `
  -WhatIf
```

确认输出后移除 `-WhatIf`。

## 4. ALE Lua

`server/ale/solo_collections.lua` 无需单独编译，但运行环境必须安装 ALE/mod-ale。
修改 API 调用前，应对照目标 ALE 版本的接口和其他本地脚本。测试不能代替实际
世界服日志与游戏内验收。

## 5. Python 依赖

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r .\client-extension\SoloCam\requirements-dev.txt
```

运行 SoloCam 测试：

```powershell
$env:SOLOCOLLECTIONS_WOW_EXE = 'D:\path\to\supported\Wow.exe'
python -m unittest discover -s client-extension\SoloCam\tests -p 'test_*.py' -v
```

没有设置真实 EXE 时，依赖客户端二进制的测试会跳过，其余测试仍运行。

## 6. 编译 SoloCam.dll

安装 Visual Studio 2022 Build Tools，并勾选：

- Desktop development with C++；
- MSVC v143 C++ x64/x86 build tools；
- Windows 10 或 Windows 11 SDK。

构建脚本先读取 `SOLOCOLLECTIONS_VCVARS`，然后检查现有 D 盘工具链，最后通过
Visual Studio Installer 的 `vswhere` 自动查找：

```powershell
$env:SOLOCOLLECTIONS_VCVARS = 'D:\path\to\VC\Auxiliary\Build\vcvarsall.bat'
& .\client-extension\SoloCam\scripts\build.ps1
```

产物：

```text
client-extension/SoloCam/build/Release/SoloCam.dll
client-extension/SoloCam/build/Tests/*.exe
```

脚本编译并执行 CameraProfile、DisplayInfoBridge、ItemCameraBridge 三组 x86
原生测试。不要把 `build` 目录提交到 Git。

## 7. 构建 MPQ

需要 x64 StormLib 和纯净客户端，见[MPQ 自建指南](BUILD_MPQ.zh-CN.md)。MPQ
构建不修改源档案；只有显式添加 `-Deploy` 才会备份并复制到客户端。

## 8. 生成本地 Release

本地 Release 包含二进制和客户端补丁，因此整个 `release` 目录被 Git 忽略。

```powershell
& .\packaging\assemble-local-release.ps1 `
  -Version '0.1.0' `
  -ClientDirectory 'D:\path\to\WoW' `
  -Locale zhCN `
  -LocalePatchNumber 6
```

生成后检查 `release/v0.1.0/SHA256SUMS.txt` 和压缩包内部路径，再手工上传允许
分发的文件。
