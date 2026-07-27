# SoloCam: optional 3.3.5a camera extension

[中文](#中文) · [English](#english)

## 中文

SoloCam 是 SoloCollections 的可选 32 位客户端扩展。它为物品页的九个身体部位
提供局部镜头，并为独立武器/副手模型提供受限的 display 和 camera bridge。
收藏状态、授权和服务端动作不依赖 SoloCam。

### 严格支持边界

- 仅 x86 World of Warcraft 3.3.5a build 12340；
- 原始 `Wow.exe` SHA-256 必须为：

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

- 不修改 Character M2；
- 不覆盖原始 `Wow.exe`；
- 补丁点原字节或哈希不一致立即停止；
- DLL 只在目标模型绘制期间应用镜头，结束后恢复原状态；
- 未知 sentinel/profile/model 必须回退或显示明确不可用。

源码仓库不包含 `Wow.exe`、补丁 EXE、编译 DLL、MPQ 或客户端提取资源。

### 编译

需要 Windows 10/11、Visual Studio 2022 Desktop C++、MSVC v143 x86 工具链
和 Windows SDK：

```powershell
$env:SOLOCOLLECTIONS_VCVARS = '<VS>\VC\Auxiliary\Build\vcvarsall.bat'
& .\client-extension\SoloCam\scripts\build.ps1
```

产物位于被忽略的 `client-extension/SoloCam/build`。脚本同时编译并执行本组件
的原生检查程序。

### 本地部署

先在客户端外保留完整备份：

```powershell
& .\client-extension\SoloCam\scripts\deploy-poc.ps1 `
  -ClientDirectory '<WoW-3.3.5a>'
```

部署只创建/更新项目自己的：

```text
Wow-SoloCam-PoC.exe
SoloCam.dll
```

普通 `Wow.exe` 保持回退入口。任何同名文件都要先识别来源和备份。

### 武器资源

3.3.5 的普通 `Model` 控件不会自动完成所有 `ItemDisplayInfo` 贴图绑定。资源
构建脚本可以从用户自己的客户端只读提取所需结构，生成本地专用模型副本和
locale DBC patch：

```powershell
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-3.3.5a>' `
  -Locale zhCN `
  -LocalePatchNumber 6
```

先不使用 `-Deploy`，检查回读 hash 后再决定是否安装。非 zhCN 客户端必须使用
自己的 locale。StormLib 不属于本仓库，路径必须显式提供。

详细资源边界见 `docs/BUILD_MPQ.zh-CN.md` 和 `docs/ASSETS.md`。

### 镜头贡献

当前 profile 已覆盖基础 20 个 race/sex 页面和九部位，但 HD/自定义模型与极端
武器仍可能不理想。不要直接在 C++ 写个人特例；先使用 AddOn 镜头工作台导出
稳定身份 JSONL，按
[`docs/CAMERA_CONTRIBUTIONS.md`](../../docs/CAMERA_CONTRIBUTIONS.md)
提交参数、截图和客户端信息。

## English

SoloCam is an optional 32-bit extension for local body framing and constrained
standalone weapon/off-hand display on the SoloCollections item page. It does
not own collection state, authorization, or server actions.

It supports only x86 WoW 3.3.5a build 12340 with the exact executable SHA-256
shown above. The patch path creates `Wow-SoloCam-PoC.exe` and keeps the
original executable as the rollback entry. Any hash or byte-signature mismatch
must stop. Unknown profiles and models must fall back safely or report an
explicit unavailable state.

Build with Visual Studio 2022 Desktop C++, the MSVC v143 x86 toolchain, and a
Windows SDK by running `client-extension/SoloCam/scripts/build.ps1`.
Generated DLL/test output remains ignored.

Optional weapon-resource tooling reads only client files supplied by the user
and must be run without deployment first. The repository does not distribute
game executables, MPQs, or extracted model/DBC content.

Camera contributions should use the in-game workbench and follow
[`docs/CAMERA_CONTRIBUTIONS.md`](../../docs/CAMERA_CONTRIBUTIONS.md).
