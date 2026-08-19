# SoloCollectionsPlatform v0.3.2 怎么用

相对 v0.3.1：收藏模块不再打玩法 `LOG_*`；`worldserver` 加载完成后用和 AzerothCore 同款的 `SOLO` / `COLLECTIONS` 花字提示署名；登录聊天一行写「本服务端已加载 SoloCollections 模块，此模块模拟军团再临版本的收藏系统和幻化系统」（`SoloCollections` 金色）；署名含作者、QQ 群、邮箱、仓库 `https://github.com/haha2345/SoloCollectionsPlatform` 和学习交流声明；右下角署名先设字体再写字，避免 `SetText(): Font not set`。world 库 `sc_module_credits` 增加 `repository`（玩法不读这张表）。

这不是完整游戏包。你必须自己已有：

- World of Warcraft **3.3.5a build 12340**（32 位客户端）
- 能编译、能跑的 **AzerothCore WotLK** 服务端和 MySQL

没有这两样，只解压 Release 编不出可玩的一套。

先用 `SHA256SUMS.txt` 校验下载文件。

## 1. 每个包做什么

| 文件 | 必须？ | 放到哪 / 怎么用 |
| --- | --- | --- |
| `addon.zip` | 客户端必须 | 解压出 `SoloCollections`，放到 `<WoW>\Interface\AddOns\` |
| `sql.zip` | 服务端必须 | 导入 MySQL，见下文 |
| `module-source.zip` | 服务端必须 | 解压到 `<AzerothCore>\modules\mod-solo-collections`，**随 Core 一起编译 worldserver** |
| `mpq.zip` | 可选 | `Patch-W.MPQ` → `<WoW>\Data\`；`patch-zhCN-6.MPQ` → `<WoW>\Data\zhCN\` |
| `solocam.zip` | 可选 | 只含 `SoloCam.dll`。**不能**只拷 DLL 就生效，见第 4 节 |
| `client-runtime.zip` | 可选 | 上面客户端三件套的合并包，等价于 addon + mpq + dll |

`client-runtime.zip` 解压后对应关系：

```text
Interface/AddOns/SoloCollections/   →  拷到客户端同名目录
Data/Patch-W.MPQ                    →  <WoW>\Data\
Data/zhCN/patch-zhCN-6.MPQ          →  <WoW>\Data\zhCN\
SoloCam.dll                         →  客户端根目录（仍要自己的启动器，见第 4 节）
```

## 2. 客户端（手册 / 幻化室）

1. 关掉魔兽。
2. 安装 `addon.zip`（或 runtime 包里的 AddOn）。
3. （可选）安装两个项目 MPQ。先备份客户端里同名文件再覆盖。
4. 用**平时那套私服**登录。游戏内：
   - `/sc` 或 `/collections`：收藏手册
   - `/tmog` 或 `/幻化`：独立幻化室
   - `/reload`：热重载插件

未装 MPQ 时手册和幻化室能开，部分独立武器预览会降级。  
`Patch-X/Y/Z`、`patch-zhCN-z`、`patch-zhCN-9` **不要**当本项目补丁安装。

## 3. 服务端（必须编译进 AzerothCore）

Release **没有**现成的 `worldserver.exe`。

1. 解压 `module-source.zip`，目录里要有 `include.sh`：

   ```text
   <AzerothCore>/modules/mod-solo-collections/include.sh
   ```

2. CMake 加 `MODULES=static`，重新生成并编译 `authserver` / `worldserver`。
3. 导入 `sql.zip`：
   - **新 characters 库**：`sql/db-characters/solo_collections_schema_v1.sql`
   - **已有库**：只跑 `sql/updates/` 里还没打过的 migration，不要和新库 snapshot 重复导入
   - 世界库：`sql/db-world/`
   - 权限：`sql/db-auth/`
4. 运行时配置（`transmog.conf` / 模块 conf）：

   ```ini
   SoloCollections.Backend = Cpp
   ```

5. 启动编好的 `worldserver`，确认日志里加载了 `mod-solo-collections`。

插件只负责界面和发请求；没编进模块、没导 SQL、Backend 不是 Cpp，界面会显示未就绪或无法应用幻化。

## 4. SoloCam（可选，默认不用）

收藏和幻化 **不依赖** SoloCam。没有它，部位特写和部分武器预览走原生镜头。

### 只把 `SoloCam.dll` 放到客户端根目录够不够？

**不够。** 原版 `Wow.exe` 不会加载这个 DLL。

要用镜头扩展，本机还要有 `Wow-SoloCam-PoC.exe`，并且和 `SoloCam.dll` 放在同一目录，用这份启动器进游戏。

### `Wow-SoloCam-PoC.exe` 能不能直接分享给别人用？

**不能。** 它是从你自己的 `Wow.exe` **复制后打补丁**得到的客户端副本：

- 里面含有暴雪客户端代码，不能作为 Release 附件分发
- 只认固定的 3.3.5a build 12340、原始 `Wow.exe` SHA-256  
  `AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8`
- 别人的客户端若是 HD、改过 EXE、哈希不同，你这份启动器也跑不起来

别人要自己在本机生成：

```powershell
& .\SoloCollections\client-extension\SoloCam\scripts\deploy-poc.ps1 `
  -ClientDirectory '<自己的-WoW-3.3.5a>'
```

脚本只新增/更新 `Wow-SoloCam-PoC.exe` 和 `SoloCam.dll`，不覆盖原版 `Wow.exe`。  
没有 Visual Studio 时，也可以把 Release 里的 `SoloCam.dll` 拷到客户端根目录，再用仓库里的 `poc_patch.py` 对自己的 `Wow.exe` 生成启动器。

## 5. 装完仍不能用时

| 现象 | 先查 |
| --- | --- |
| 插件没有 / 命令无效 | AddOn 是否在 `Interface\AddOns\SoloCollections`，TOC 是否存在 |
| 「服务尚未就绪」 | worldserver 是否编进了模块、Backend 是否 Cpp、SC2 是否握手成功 |
| 能预览不能应用 | 角色对应栏是否穿着装备、金币、服务端拦截原因 |
| 镜头没有特写 | 是否用 `Wow-SoloCam-PoC.exe` 启动，DLL 是否在根目录，EXE 哈希是否匹配 |
