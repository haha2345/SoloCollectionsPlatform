# SoloCam: optional 3.3.5a camera extension

[中文](#中文) · [English](#english)

## 中文

SoloCam 是 SoloCollections 的可选 32 位客户端扩展。v11 在同一个 DLL 中保留
身体镜头和 direct-display 能力，并合并 Transmorpher 的本地预览桥：武器卡仍是
玩家 `DressUpModel`，DLL 只把保留的 `SetCreature` 请求转成客户端原生
`Undress/TryOn`。收藏状态、授权和服务端动作不依赖 SoloCam。

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
- `PlayerModel:SetCreature` 只能由这一份 SoloCam Hook 拥有，不能同时加载
  Transmorpher 的完整 Hook DLL；
- 武器预览只允许调用当前卡片模型的原生 `Undress/TryOn`，不能修改真实角色装备；
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

### 武器预览

外观物品页不再使用固定 Creature、独立武器 M2、NPC 占位或 ezCollections
武器镜头。AddOn 复用 Transmorpher 3.0.0 的 Classic 预览配置，顺序固定为：

```text
Reset → Undress → SetPosition → SetFacing → TryOn → SetSequence
```

主手、副手、远程继续接受 Transmorpher 打包的 Lua 装备栏 16、17、18，但它们
不是底层模型槽位。v11 按 build 12340 的实际 `0x005980D0` 分发器转换为主手
模型槽 15、副手模型槽 16；远程交回原生 InventoryType 自动判槽。这个转换
避免盾牌几何体挂上后，替换纹理却被送到不存在的模型槽 17。SoloCam 每秒从 WoW UI
线程重新发布一次能力，因此 `/reload` 不需要手工 `/run`。旧
`build-weapon-models.ps1` 等资源工具仅供历史独立模型
实验，不是现行物品卡依赖。

### 镜头贡献

当前身体 profile 已覆盖基础 20 个 race/sex 页面和九部位；武器构图来自
Transmorpher Classic 的 race/sex/render-slot/subclass 数据。不要在 C++ 写物品
特例；身体镜头贡献按
[`docs/CAMERA_CONTRIBUTIONS.md`](../../docs/CAMERA_CONTRIBUTIONS.md)
提交参数、截图和客户端信息。

## English

SoloCam is an optional 32-bit extension for local body framing, direct-display
compatibility, and the merged Transmorpher preview bridge. Weapon cards remain
player DressUpModels; v11 converts a reserved SetCreature request into the
client's native Undress/TryOn call on that exact widget. It does not own
collection state, authorization, or server actions.

The packed Transmorpher values 16/17/18 are Lua equipment slots, not the
zero-based slots consumed by the native model method. v11 maps main hand to
model slot 15, off-hand to model slot 16, and lets the stock InventoryType
dispatcher resolve ranged items.

It supports only x86 WoW 3.3.5a build 12340 with the exact executable SHA-256
shown above. The patch path creates `Wow-SoloCam-PoC.exe` and keeps the
original executable as the rollback entry. Any hash or byte-signature mismatch
must stop. Unknown profiles and models must fall back safely or report an
explicit unavailable state.

Build with Visual Studio 2022 Desktop C++, the MSVC v143 x86 toolchain, and a
Windows SDK by running `client-extension/SoloCam/scripts/build.ps1`.
Generated DLL/test output remains ignored.

The full Transmorpher hook DLL must not be loaded alongside SoloCam because both
would own PlayerModel:SetCreature. Legacy weapon-resource tooling is not part
of the active wardrobe path. The repository does not distribute game
executables, MPQs, or extracted model/DBC content.

Camera contributions should use the in-game workbench and follow
[`docs/CAMERA_CONTRIBUTIONS.md`](../../docs/CAMERA_CONTRIBUTIONS.md).
