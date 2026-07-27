# mod-solo-collections：SoloCollections 的 AzerothCore 核心模块

[English](README.en.md) ·
[客户端 AddOn](https://github.com/haha2345/SoloCollections) ·
[配置说明](docs/CONFIGURATION.md) ·
[开发说明](docs/DEVELOPMENT.md) ·
[参与贡献](CONTRIBUTING.md)

`mod-solo-collections` 是
[SoloCollections](https://github.com/haha2345/SoloCollections) 的
AzerothCore WotLK C++ 权威后端。它负责账号级收藏状态、数据库 revision、
SC2 同步、服务端授权与动作，并保留经过适配的 `mod-transmog` 功能。

![SoloCollections 套装页与试衣间](https://raw.githubusercontent.com/haha2345/SoloCollections/main/docs/images/wardrobe-sets.png)

## 它负责什么

- mount、companion、toy、appearance、set 和 title provider；
- 账号收藏快照、增量 revision、持久化与审计；
- AddOn/C++ 之间的 SC2 HELLO、分片同步、重同步和动作结果；
- 坐骑/宠物预览与召唤、玩具使用、外观/套装应用；
- 收集物品、学习法术、任务奖励、拾取等服务器侧解锁事件；
- 兼容的幻化 NPC、收藏外观和配置。

客户端只负责展示和发送稳定 identity，不能决定玩家是否拥有收藏。

## 两个仓库必须匹配

| 仓库 | 内容 | 许可证 |
| --- | --- | --- |
| [`SoloCollections`](https://github.com/haha2345/SoloCollections) | AddOn、canonical 目录、SC2 schema、生成器、可选 SoloCam | GPL-3.0-or-later |
| `mod-solo-collections` | C++ 权威后端、SQL、动作与 AddOn 对应的生成目录 | AGPL-3.0 |

匹配发布至少要记录 AddOn、模块和 AzerothCore commit，以及 metadata、
asset pack、mapping hash、presentation hash 和 SC2 版本。不能混用不同版本的
生成目录。

## 编译环境

Windows 构建请以
[AzerothCore 官方 requirements](https://www.azerothcore.org/wiki/windows-requirements)
和[核心安装文档](https://www.azerothcore.org/wiki/windows-core-installation)
为准。当前官方基线包括：

- Windows 10 或更新版本；
- Visual Studio 2022，安装 **Desktop development with C++**；
- CMake 3.27 或更新版本；
- Boost 1.78 或更新版本；
- MySQL 8.0 或更新版本（官方推荐 8.4）；
- OpenSSL 3.x；
- Git。

模块由 AzerothCore 的模块系统一起编译，不单独生成可运行服务器。客户端环境是
WoW 3.3.5a build 12340；AddOn 与可选 SoloCam 的安装/编译见
[客户端仓库 README](https://github.com/haha2345/SoloCollections#readme)。

## 快速安装与编译

### 1. 放入 AzerothCore 模块目录

```powershell
git clone https://github.com/azerothcore/azerothcore-wotlk.git
git clone https://github.com/haha2345/mod-solo-collections.git `
  .\azerothcore-wotlk\modules\mod-solo-collections
```

目录必须是：

```text
<AzerothCore>/modules/mod-solo-collections/include.sh
```

### 2. 生成匹配的 build metadata

源码可以使用 `UNPINNED` fallback 完成开发构建，但可发布/可部署构建应从匹配
的 AddOn 仓库生成精确 commit 和目录 hash：

```powershell
& <SoloCollections>\tools\release\New-SoloCollectionsBuildInfo.ps1 `
  -AddonRoot <SoloCollections> `
  -ModuleRoot <AzerothCore>\modules\mod-solo-collections `
  -CoreRoot <AzerothCore> `
  -CoreBuildRoot <AzerothCore-build>
```

生成文件为被 Git 忽略的
`src/generated/SoloCollectionsBuildInfo.inc`，不要提交个人构建 metadata。

### 3. 配置与编译 Core

在 CMake 中设置：

```text
MODULES=static
CMAKE_INSTALL_PREFIX=<runtime directory>
```

Windows 命令行示例：

```powershell
cmake -S <AzerothCore> -B <AzerothCore-build> `
  -G "Visual Studio 17 2022" -A x64 `
  -DMODULES=static `
  -DCMAKE_INSTALL_PREFIX=<AzerothCore-runtime>

cmake --build <AzerothCore-build> --config RelWithDebInfo `
  --target authserver worldserver
```

修改模块列表或加入本模块后必须重新运行 CMake。部署时使用同一次构建产生的
Core 和模块，不能只复制零散对象文件。

### 4. 数据库

先备份 auth、characters 和 world 数据库。模块的 `include.sh` 会把 SQL 路径
注册给 AzerothCore 数据库更新器：

- 新 characters 数据库：
  `data/sql/db-characters/solo_collections_schema_v1.sql`；
- 已有 characters 数据库：
  `data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql`；
- RBAC：`data/sql/db-auth/solo_collections_rbac.sql`；
- 可选幻化 NPC/文本/物品：`data/sql/db-world/`。

不要把同一个 schema 基线和 migration 重复手工导入。完整事务不变量见
[账号收藏 schema](docs/schema/account-collections-v1.md)。

### 5. 配置

把安装产物中的 `transmog.conf.dist` 复制为运行时配置文件，保存到 Core 配置
的 modules 目录。生产收藏后端至少设置：

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

`Compare` 只用于迁移对照，`Lua` 只用于旧 ALE/SC1。不能让 ALE/SC1 与 C++/SC2
同时写收藏或返回生产动作成功。所有选项见[配置说明](docs/CONFIGURATION.md)。

### 6. 安装 AddOn 并启动

按客户端仓库说明安装匹配的 `addon/SoloCollections`。启动 `worldserver` 后检查：

```text
event=startup_versions
event=build_info
event=schema_check result=ready
event=provider_registry result=ready
```

游戏内管理员可执行：

```text
.solocollections status
```

若 build metadata、mapping hash 或 schema 不匹配，应先停止部署并修正版本，
不要让客户端绕过错误。

## 文档

- [配置模式和常用选项](docs/CONFIGURATION.md)
- [源码结构、生成目录和跨仓库开发](docs/DEVELOPMENT.md)
- [账号数据库 schema 与 revision 不变量](docs/schema/account-collections-v1.md)
- [上游 fork 基线](UPSTREAM_BASE.md)
- [第三方来源](THIRD_PARTY_NOTICES.md)
- [客户端安装、镜头与 Agent 开发](https://github.com/haha2345/SoloCollections#readme)

## 已知问题与欢迎贡献

物品页局部镜头和独立武器 framing 位于客户端仓库；不同种族、性别、HD/自定义
模型与极端武器仍需要参数贡献。模块仓库尤其欢迎：

- provider、账号缓存、revision 和并发安全改进；
- SC2 兼容性、限流、重同步与诊断；
- 解锁来源覆盖、动作错误语义和迁移工具；
- AzerothCore 新版 API 适配、Linux 编译和文档；
- 安全、性能和 SQL 审核。

贡献前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。使用 Coding Agent 时，让它先读
根目录 [AGENTS.md](AGENTS.md) 和 [开发说明](docs/DEVELOPMENT.md)，限制到一个
明确问题，并由人类审查 SQL、权限、数据库写入、部署和发布。

## 许可证与来源

本仓库继承 AzerothCore `mod-transmog` 的 Git 历史，并以 **GNU AGPL-3.0**
发布，见 [LICENSE](LICENSE)。上游基线、原作者和修改边界见
[UPSTREAM_BASE.md](UPSTREAM_BASE.md) 与
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目是非官方社区项目，与 Blizzard Entertainment 或 AzerothCore 官方无
隶属或背书关系。
