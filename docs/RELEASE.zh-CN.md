# SoloCollectionsPlatform v0.3.0 发布包说明

本页说明 GitHub Release 里每个压缩包是什么、装到哪里。源码仓库不包含游戏 EXE、完整客户端 MPQ，也不包含 `_work` 中间产物。

## 下载清单

| 文件 | 用途 |
| --- | --- |
| `SoloCollections-v0.3.0-addon.zip` | 收藏手册 + 独立幻化室 AddOn（含项目自制 TGA 素材） |
| `SoloCollections-v0.3.0-sql.zip` | 账号库 / 世界库 / 权限 SQL |
| `SoloCollections-v0.3.0-mpq.zip` | 本项目专用客户端补丁：`Patch-W.MPQ` + `patch-zhCN-6.MPQ` |
| `SoloCollections-v0.3.0-solocam.zip` | 可选镜头扩展 `SoloCam.dll` |
| `SoloCollections-v0.3.0-module-source.zip` | `mod-solo-collections` 源码，放入 AzerothCore `modules/` 后随 Core 编译 |
| `SoloCollections-v0.3.0-client-runtime.zip` | 上面客户端三件套的合并包（AddOn + MPQ + DLL） |
| `SHA256SUMS.txt` | 校验上述文件 |

## MPQ 只含本项目内容

`Patch-W.MPQ` 只有收藏专用武器模型副本（`Item\ObjectComponents\SoloCollections\...`）。  
`patch-zhCN-6.MPQ` 只有为这些模型追加的 `CreatureModelData.dbc` / `CreatureDisplayInfo.dbc`。

不要把客户端里其它补丁打进本包：`Patch-X/Y/Z`、`patch-zhCN-z.MPQ`、`patch-zhCN-9.MPQ`、CQM / SMQ 备份都不是本项目发布物。

安装前先备份同名文件：

```text
<WoW>\Data\Patch-W.MPQ
<WoW>\Data\zhCN\patch-zhCN-6.MPQ
```

然后把发布包里的两个 MPQ 拷到对应位置。未装 MPQ 时，手册与幻化室仍可用，只是部分独立武器预览会降级。

## 客户端安装

1. 解压 `addon.zip`，得到 `SoloCollections` 目录，放到 `<WoW>\Interface\AddOns\`。
2. （可选）解压 `mpq.zip`，按上面路径覆盖两个项目补丁。
3. （可选）把 `SoloCam.dll` 放到客户端根目录，配合已有的 SoloCam 启动器使用。
4. 游戏内 `/reload`，用 `/sc` 打开手册，`/tmog` 打开幻化室。

## 服务端安装

1. 解压 `module-source.zip` 到 `<AzerothCore>/modules/mod-solo-collections`，确认存在 `include.sh`。
2. 重新 CMake（`MODULES=static`）并编译 `worldserver`。
3. 新库导入 `sql/db-characters/solo_collections_schema_v1.sql`；已有库只跑 `sql/updates/` 里尚未应用的 migration。世界库字符串与 NPC 在 `sql/db-world/`，权限在 `sql/db-auth/`。
4. 运行时配置 `SoloCollections.Backend = Cpp`。
