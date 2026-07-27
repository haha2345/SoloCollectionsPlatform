# SoloCollections v0.2.0 发布包使用说明

[English](RELEASE_USAGE.en.md) ·
[完整安装与回滚](INSTALLATION.zh-CN.md) ·
[服务端模块](https://github.com/haha2345/mod-solo-collections)

`v0.2.0` 是第一套使用独立 `mod-solo-collections` C++/SC2 权威后端的公开源码
发布。它不能与旧 `v0.1.0` 的 ALE/SC1 服务端桥、旧目录或客户端补丁混装。

## 应该下载哪个文件

| 文件 | 用途 |
| --- | --- |
| `SoloCollections-v0.2.0-unified-source.zip` | 推荐下载；包含 AddOn、模块源码、清单、双语说明和许可证 |
| `SoloCollections-v0.2.0-addon.zip` | 只安装 WoW AddOn 时使用 |
| `mod-solo-collections-v0.2.0-source.zip` | 放入 AzerothCore 源码树并随 Core 编译 |
| `release-manifest.json` | 精确记录 AddOn、模块、AzerothCore、SC2、目录和 SQL 版本 |
| `RELEASE_SHA256SUMS.txt` | 校验公开下载资产 |

GitHub 自动生成的 `Source code` 压缩包适合开发者；普通安装者优先下载
`unified-source.zip`。

## 发布包不包含什么

发布包不包含 `Wow.exe`、补丁 EXE、DLL、MPQ、DBC、DB2、M2、SKIN、BLP、
WDB、数据库 dump、密码或从游戏客户端提取的素材。AddOn 的基础 UI 素材是项目
自制内容。SoloCam 和独立武器资源是可选本地构建项，不是运行收藏状态与基础 UI
的前置条件。

## 1. 下载后先校验

把 `RELEASE_SHA256SUMS.txt` 与下载资产放在同一目录，使用 PowerShell：

```powershell
Get-FileHash .\SoloCollections-v0.2.0-unified-source.zip -Algorithm SHA256
Get-Content .\RELEASE_SHA256SUMS.txt
```

结果必须与清单中对应文件一致。解压统一包后，还可以用其中的
`SHA256SUMS.txt` 校验内部文件。

## 2. 安装并编译服务端模块

先停止 `worldserver`，备份 auth、characters、world 数据库、模块配置和当前
服务端文件。将：

```text
mod-solo-collections-v0.2.0-source.zip
```

解压为：

```text
<AzerothCore source>/modules/mod-solo-collections/include.sh
```

重新运行 CMake，并随 AzerothCore 编译：

```powershell
cmake -S <AzerothCore> -B <AzerothCore-build> `
  -G "Visual Studio 17 2022" -A x64 `
  -DMODULES=static `
  -DCMAKE_INSTALL_PREFIX=<AzerothCore-runtime>

cmake --build <AzerothCore-build> --config RelWithDebInfo `
  --target authserver worldserver
```

模块通过 `include.sh` 注册 SQL。新 characters 数据库使用 schema snapshot，
已有数据库使用 append-only migration；不要对同一数据库手工重复导入两者。

将安装后的 `transmog.conf.dist` 复制为运行时 `transmog.conf`，至少确认：

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

`Compare` 只用于迁移对照，`Lua` 是旧后端。生产环境不能同时运行 ALE/SC1 与
C++/SC2 两个收藏写入者。

## 3. 安装 AddOn

解压 `SoloCollections-v0.2.0-addon.zip`，把其中的 `SoloCollections` 目录复制
到：

```text
<WoW>/Interface/AddOns/SoloCollections/
```

最终必须存在：

```text
<WoW>/Interface/AddOns/SoloCollections/SoloCollections.toc
```

在角色选择页启用 `Solo Collections`。AddOn 无需编译。

## 4. 启动后检查

启动新编译的 `worldserver`，检查日志：

```text
event=startup_versions
event=build_info
event=schema_check result=ready
event=provider_registry result=ready
```

管理员在游戏中执行：

```text
.solocollections status
```

确认 backend 为 `Cpp`、schema/provider ready、SC2 握手完成，并且 metadata、
asset token 或 mapping hash 不匹配时会失败关闭。

然后依次检查坐骑、小宠物、玩具、外观和套装五个页面，并进行一次 `/reload`
和重新登录。

## 5. 可选 SoloCam

没有 SoloCam 时，收藏状态、同步和大部分 UI 仍可使用；局部身体镜头与部分独立
武器预览会使用原生 fallback 或显示 `UNAVAILABLE`。

SoloCam 只支持原始 x86 WoW 3.3.5a build 12340，且要求 `Wow.exe` SHA-256：

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

哈希不同必须停止。请从发布标签源码自行编译，并遵循
[SoloCam README](../client-extension/SoloCam/README.md) 的副本、备份和回滚
流程。

## 6. 从 v0.1.0 升级

不要直接把 `v0.2.0` 覆盖到仍运行 ALE/SC1 的 `v0.1.0` 环境：

1. 记录并备份旧 AddOn、ALE 脚本、客户端同名文件和数据库；
2. 停止旧 ALE/SC1 收藏动作响应；
3. 恢复或识别旧版安装的 MPQ/DLL/补丁 EXE，不要盲删同名文件；
4. 部署 C++ 模块、SQL、配置和匹配 AddOn；
5. 用 `.solocollections status` 确认唯一生产后端为 `Cpp`。

## 7. 已知问题和贡献

物品页镜头尚未对所有种族、性别、HD/自定义模型和极端比例武器达到一致构图。
这不影响服务端收藏权威，但可能造成模型过近、过远、偏移或裁切。参数贡献请按
[镜头贡献指南](CAMERA_CONTRIBUTIONS.md) 提供客户端 build/hash、目标身份、
修改前后截图和工作台 JSONL。

完整环境、数据库、验收和回滚边界见
[INSTALLATION.zh-CN.md](INSTALLATION.zh-CN.md)。
