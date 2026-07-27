# SoloCollections 安装与回滚

## 1. 适用环境

- World of Warcraft 3.3.5a build 12340，x86；
- AzerothCore WotLK；
- `SoloCollections` AddOn 与 `mod-solo-collections` C++ 模块；
- MySQL、Core 数据文件和其他依赖按 AzerothCore 官方文档配置；
- 可选 SoloCam 只支持 README 中列出的精确 EXE hash。

`v0.2.0` 不能和旧 `v0.1.0` 的 ALE 演示包混装。优先使用
[发布包使用说明](RELEASE_USAGE.zh-CN.md)中的成套资产，并核对 AddOn commit、
module commit、metadata 和资源包版本。

## 2. 准备和备份

1. 停止 `worldserver` 和 WoW 客户端。
2. 备份 characters/auth/world 数据库。
3. 记录 AzerothCore、模块和 AddOn commit。
4. 备份现有的模块配置和 `Interface/AddOns/SoloCollections`。
5. 如要安装客户端扩展，先记录同名 EXE/DLL/MPQ 的路径和 SHA-256。

不要直接覆盖来源不明的同名 MPQ 或客户端文件。

## 3. 安装核心模块

把模块放入：

```text
<AzerothCore source>/modules/mod-solo-collections/
```

重新运行 CMake，确保 `MODULES=static`，然后编译并安装 `authserver` 和
`worldserver`。详细环境和命令见
[模块仓库 README](https://github.com/haha2345/mod-solo-collections#readme)。

模块的 `include.sh` 会向 AzerothCore 注册 SQL snapshot/update 目录。新数据库
使用 `data/sql/db-characters/solo_collections_schema_v1.sql`；已有数据库使用
append-only update `data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql`。
不要对同一数据库同时手工导入 snapshot 和 update。

## 4. 配置唯一后端

将编译安装后的 `transmog.conf.dist` 复制成运行时 `transmog.conf`，至少确认：

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

`Compare` 只用于受控迁移对照；`Lua` 是旧后端。生产环境选择 `Cpp` 后，不要再
让 ALE/SC1 脚本响应收藏动作。

其他 `Transmogrification.*` 选项按服务器规则调整。不要把包含私有运行设置的
实际 `.conf` 提交到 Git。

## 5. 安装 AddOn

复制：

```text
<SoloCollections repo>/addon/SoloCollections/
    -> <WoW>/Interface/AddOns/SoloCollections/
```

确认没有多套一层目录，最终文件是：

```text
<WoW>/Interface/AddOns/SoloCollections/SoloCollections.toc
```

启动客户端，在角色选择页启用 `Solo Collections`。

## 6. 第一次启动检查

启动 `worldserver`，检查：

```text
event=startup_versions
event=schema_check result=ready
```

管理员登录后执行：

```text
.solocollections status
```

重点确认：

- backend 为 `Cpp`；
- schema 为 ready；
- provider 没有失败；
- `pending_writes` 会回到合理值；
- AddOn SC2 握手完成；
- metadata/asset mismatch 没有被忽略。

## 7. 可选 SoloCam

SoloCam 只接受原始 `Wow.exe` SHA-256：

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

先阅读 [SoloCam README](../client-extension/SoloCam/README.md)。部署脚本创建
`Wow-SoloCam-PoC.exe` 副本和 `SoloCam.dll`，不覆盖原文件。哈希不同、字节
签名不同或客户端并非 build 12340 时必须停止。

武器独立模型还需要用户从自己合法取得的客户端构建资源。仓库不提供游戏
M2/SKIN/BLP/DBC/MPQ。流程见 [BUILD_MPQ.zh-CN.md](BUILD_MPQ.zh-CN.md)。

## 8. 客户端验收

1. 打开全部五个页面。
2. 重新登录和 `/reload` 后确认收藏状态一致。
3. 检查坐骑/宠物动作、玩具结果、外观收藏和套装进度。
4. 在不同装备部位切换物品页，确认模型不会串到相邻卡片。
5. 关闭 SoloCam 验证原生 fallback 或明确 `UNAVAILABLE`。
6. 修改 asset token 做隔离环境检查时，必须看到 fail closed。

镜头质量应按 [CAMERA_CONTRIBUTIONS.md](CAMERA_CONTRIBUTIONS.md) 记录实际
种族、性别、部位、分辨率、UI Scale 和截图。

## 9. 回滚

1. 停止客户端和世界服。
2. 恢复上一个 `worldserver`、模块配置和对应 AddOn。
3. 恢复客户端同名文件的精确备份，或删除本次新增且安装前不存在的文件。
4. 数据库 schema v1 是 append-only；不要在没有独立数据库备份和迁移方案时
   直接删除收藏表。
5. 启动旧版本前确认它理解当前 schema/revision；不确定时先在数据库副本验证。
6. 核对恢复后的文件 hash、后端模式和 `.solocollections status`。
