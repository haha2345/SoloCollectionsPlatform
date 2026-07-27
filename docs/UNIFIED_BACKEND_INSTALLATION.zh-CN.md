# SoloCollections 成套源码包安装边界

统一源码包严格分开 AddOn、C++ module、SQL 和客户端资源。C++ module 是收藏、
权限、revision、同步和动作的唯一生产后端；旧 ALE Lua 只能用于历史迁移或
只读对照，不能成为第二个写入者。

## 1. AddOn

将 `SoloCollections-<version>-addon.zip` 解压到：

```text
<WoW>/Interface/AddOns/SoloCollections/
```

AddOn 只负责 UI、客户端缓存和 SC2 收发。它的 commit、metadata、mapping hash
与 module 必须和 `release-manifest.json` 一致。

## 2. C++ module

将 `mod-solo-collections-<version>-source.zip` 解压到：

```text
<AzerothCore source>/modules/mod-solo-collections/
```

重新配置 `MODULES=static` 并编译 Core。复制安装后的
`conf/transmog.conf.dist` 为运行时 `transmog.conf`，生产环境使用：

```ini
SoloCollections.Backend = Cpp
```

## 3. SQL

新 characters 数据库使用：

```text
data/sql/db-characters/solo_collections_schema_v1.sql
```

已有数据库使用 append-only migration：

```text
data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql
```

其余 auth/world SQL 由 module 的注册目录导入。不能在发布包中保存数据库连接、
密码或数据库 dump。启动后必须看到 `event=schema_check result=ready`。

## 4. 客户端资源

统一源码包不包含客户端 EXE、DLL 或 MPQ，也不包含 DBC、DB2、M2、SKIN、BLP、
WDB 或从游戏客户端提取的资源。可选 SoloCam DLL 必须由源码构建；可选模型资源
必须由用户从自己有权使用的客户端在本地生成。

资源缺失或 `assetPackVersion` 不匹配时，预览必须失败关闭，不能由 AddOn 绕过
服务端授权。

## 5. 安装核对

1. 校验 `SHA256SUMS.txt`。
2. 核对 `release-manifest.json` 中 AddOn、module、AzerothCore commits、SC2
   version、metadata、asset token、per-category mapping hash 和 SQL version。
3. 启动 `worldserver`，检查 `event=startup_versions`、provider 和 schema。
4. 登录后执行 `.solocollections status`。
5. 确认没有旧 ALE/SC1 生产响应。

许可证分别保存在两个源码包及 `LICENSES` 目录；成套版本匹配不改变第三方资源的
许可证。
