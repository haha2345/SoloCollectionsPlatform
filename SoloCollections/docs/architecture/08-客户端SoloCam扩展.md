# 08 客户端 SoloCam 扩展

## 1. 作用与边界

WoW 3.3.5a 的 AddOn API 可以创建 `PlayerModel`/`DressUpModel`，但外观页还需要
身体镜头、direct-display 兼容和不受 Lua 类型检查影响的本地武器试穿。SoloCam
v11 在同一个 DLL 中提供三个受限 bridge：

- **BodyCameraBridge**：按 race、sex、slot 应用身体部位镜头；
- **ItemCameraBridge**：为独立武器/副手模型绑定 display 和镜头参数。
- **PreviewItemBridge**：把保留的 `SetCreature` 请求转成当前卡片模型上的原生
  `Undress/TryOn`，供 Transmorpher 武器卡路径使用。

SoloCam 只负责显示。收藏状态、账号授权、数据库和服务端动作均由
`mod-solo-collections` 负责。

## 2. 严格客户端边界

当前源码只支持：

```text
World of Warcraft 3.3.5a build 12340
x86 process
Original Wow.exe SHA-256:
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

任何 hash、PE 架构或补丁点原字节不匹配都必须停止。禁止把地址“试着套用”
到其他客户端，不给角色 M2 增加 camera，也不覆盖原始 `Wow.exe`。

源码位置：

```text
client-extension/SoloCam/
├─ src/
│  ├─ SoloCam.cpp
│  ├─ BodyCameraBridge.*
│  ├─ CameraProfile.*
│  ├─ DisplayInfoBridge.*
│  ├─ ItemCameraBridge.*
│  ├─ PreviewItemBridge.*
│  └─ ClientAddresses.hpp
├─ tests/
├─ scripts/
└─ README.md
```

仓库不包含构建后的 DLL、补丁 EXE、MPQ、DBC、M2、SKIN 或 BLP。

## 3. 身体部位镜头

AddOn 用受控 sentinel 表达“当前卡片要查看哪个部位”，SoloCam 在目标模型的
镜头设置阶段解析当前 race、sex、slot，然后对原生 dressing-room camera 做
临时变换：

```mermaid
sequenceDiagram
    participant Lua as Wardrobe.lua
    participant Model as 3.3.5 Model API
    participant DLL as SoloCam.dll
    participant Render as Client render path

    Lua->>Model: SetCamera(slot sentinel)
    DLL->>DLL: Capture frame and identity
    Lua->>Model: SetCamera(1) fallback
    Render->>DLL: Apply model camera
    DLL->>DLL: Resolve race/sex/slot profile
    DLL->>Render: Apply temporary transform
    DLL->>Render: Restore original state
```

哨兵只传递意图，不是 M2 camera 索引。DLL 缺失、profile 未知或 hook 未安装时，
紧随其后的原生 `SetCamera(1)` 仍应提供安全回退。

当前生成数据覆盖 20 个基础 race/sex 页面、每页九个装备部位，共 180 个基础
profile。HD/自定义模型、不同体型和少数部位仍需要社区实机校准。

## 4. Transmorpher 武器预览桥

外观物品页的武器卡是玩家 `DressUpModel`，不再创建固定 Creature 或独立武器
actor。Lua 保留 Transmorpher 的装备栏打包值携带 itemId：

```text
16 = Lua Main Hand carrier → native model slot 15
17 = Lua Off-hand carrier → native model slot 16
18 = Lua Ranged carrier → native InventoryType auto slot
```

Transmorpher 3.0.0 把 Lua 装备栏 16/17/18 误称为底层引擎槽并原样传入
`0x00597FC0`。对 build 12340 的 `DressUpModel:TryOn` 与 `0x005980D0`
分发器反汇编确认：模型只使用零基武器槽 15/16，盾牌 `INVTYPE_SHIELD=14`
必须进入模型槽 16。v11 只纠正这层语义映射，其余 sentinel、模型、构图和
原生 TryOn 路径保持 Transmorpher 结构。

Hook 先通过 `widgetTable[0]` 取得发出请求的真实模型对象，再调用 build 12340
原生 `Undress`/`TryOn`。它不调用真实角色换装，不发送服务器动作，也不改变
收藏状态。AddOn 端按 Transmorpher 顺序执行：

```text
Reset → Undress → SetPosition → SetFacing → TryOn → SetSequence
```

种族、性别、实际渲染槽位和武器子类参数来自 Transmorpher 3.0.0 Classic 数据。
完整 Transmorpher DLL 与 SoloCam 都会 Hook `PlayerModel:SetCreature`，因此只能
部署合并后的 SoloCam，不能让两个 DLL 并列加载。详细边界见
[09-武器与副手独立模型.md](09-武器与副手独立模型.md)。

## 5. 构建

需要 Windows 10/11、Visual Studio 2022 Desktop development with C++、
MSVC v143 x86 工具链和 Windows SDK。

```powershell
$env:SOLOCOLLECTIONS_VCVARS = '<Visual Studio>\VC\Auxiliary\Build\vcvarsall.bat'
& .\client-extension\SoloCam\scripts\build.ps1
```

脚本以 x86 构建，并把中间文件、检查程序和 `SoloCam.dll` 放在被 Git 忽略的
`client-extension/SoloCam/build/`。环境变量未设置时可通过 `vswhere` 查找
Visual Studio。

## 6. 本地部署与回退

先关闭客户端并保留完整客户端备份，再显式指定目标目录：

```powershell
& .\client-extension\SoloCam\scripts\deploy-poc.ps1 `
  -ClientDirectory '<WoW-3.3.5a directory>'
```

部署路径只创建或更新：

```text
Wow-SoloCam-PoC.exe
SoloCam.dll
```

原始 `Wow.exe` 必须保持不变，作为回退入口。若部署脚本拒绝 hash/字节检查，
不要手工绕过。回退时关闭客户端，恢复部署前备份或删除本 PoC 创建且 hash
已确认的文件。

武器资源脚本默认先构建、回读并报告 hash；不要在首次执行时使用 `-Deploy`。
具体命令见 [`client-extension/SoloCam/README.md`](../../client-extension/SoloCam/README.md)。

## 7. 镜头参数贡献

身体镜头 identity 是 `(raceId, sex, slot)`；武器参数由 Transmorpher Classic
的 `(raceFileName, sex, renderSlot, subclass)` 决定。不要在 C++ 中堆叠物品特例。

每份镜头贡献至少应包含：

- WoW build、locale、原始/HD/自定义模型说明；
- race、sex、slot 或武器 appearance/model/family identity；
- 修改前后参数；
- 固定窗口尺寸下的修改前/后截图；
- 翻页、切页、移动窗口和关闭重开的结果；
- 长武器、盾牌或极端模型的完整边界截图。

完整字段、导入工具和 PR 格式见
[`docs/CAMERA_CONTRIBUTIONS.md`](../CAMERA_CONTRIBUTIONS.md)。

## 8. 不变量和验收

- Hook 只在目标模型绘制期间生效，结束后恢复 camera/render 状态；
- 窗口位置不能参与镜头计算；
- generation 变化后旧异步回调不能覆盖新卡片；
- 未识别 sentinel/profile/display/preview request 必须安全回退或明确不可用；
- Transmorpher 完整 Hook DLL 不得与 SoloCam 同时加载；
- 同一模型连续翻页不能闪烁、放大或泄漏到世界画面；
- 构建/加载成功只证明技术链路，镜头是否正常必须由真实客户端截图确认。

Agent 继续开发前应同时阅读
[`docs/AGENT_DEVELOPMENT.md`](../AGENT_DEVELOPMENT.md) 和仓库根目录
[`AGENTS.md`](../../AGENTS.md)，并把客户端部署、数据库写入和 GitHub 发布留给
明确授权的人工步骤。
