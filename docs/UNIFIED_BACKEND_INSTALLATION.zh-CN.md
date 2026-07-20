# SoloCollections 统一后端安装边界

统一后端发布包把四个层次明确分开。C++ module 是收藏、权限、revision、同步和动作的唯一生产后端；旧 ALE Lua 仅用于历史迁移/对照，不得与 C++ 后端同时写入或响应收藏动作。

## 1. AddOn

解压 `SoloCollections-<version>-addon.zip`，得到 `SoloCollections/`，复制到：

```text
<WoW>/Interface/AddOns/SoloCollections/
```

AddOn 只负责 UI、客户端缓存和 SC2 收发，不是权威收藏数据库。AddOn commit 与服务端 module commit 必须和 `release-manifest.json` 一致。

## 2. C++ module

解压 `mod-solo-collections-<version>-source.zip` 到 AzerothCore 源码树：

```text
<AzerothCore source>/modules/mod-solo-collections/
```

重新运行 CMake 并完整编译 `worldserver`。复制 `conf/transmog.conf.dist` 到运行时配置目录后按需修改；不要把含密码的实际 `.conf` 放回源码或发布包。`release-manifest.json` 中的 AzerothCore commit 是已验收的 Core 基线。

## 3. SQL

新数据库使用 module 中的 schema snapshot：

```text
data/sql/db-characters/solo_collections_schema_v1.sql
```

已有数据库只应用 append-only migration：

```text
data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql
```

其余 auth/world SQL 仍按 module 的 `data/sql/db-auth`、`data/sql/db-world` 边界导入。不要把数据库用户名、密码或连接串写入发布清单。启动后必须看到 `event=schema_check result=ready`。

## 4. 客户端资源

代码发布包不包含客户端 EXE、DLL 或 MPQ，也不包含从游戏客户端提取的资源。与 `assetPackVersion` 匹配的客户端资源由维护者在权利审核后单独分发；安装前关闭客户端、备份同名文件，并按资源包自己的 SHA-256 清单核验。

缺失或版本不匹配的资源必须使预览/动作 fail closed，不能由 AddOn 绕过服务端授权。

## 5. 验收

1. 核对 `SHA256SUMS.txt` 中每个文件。
2. 核对 `release-manifest.json` 的 AddOn、module、AzerothCore commits、SC2 版本、每类别 mapping hash、asset pack 和 SQL 版本。
3. 启动 `worldserver`，确认 `event=startup_versions`、provider ready 和 schema ready。
4. 登录角色后执行 `.solocollections status`，确认 `online_accounts`、`cache_entries` 和 `pending_writes` 合理。
5. 确认旧 ALE Lua 没有生产写入或 SC1/SC2 动作响应。

GPL、AGPL 和第三方归属分别保存在发布包的 `LICENSES/` 目录及两个源码压缩包内。
