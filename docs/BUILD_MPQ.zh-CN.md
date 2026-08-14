# 在任意语言纯净 3.3.5a 客户端自建两个 MPQ

## 1. 两个 MPQ 分别是什么

| 文件 | 内容 | 是否与语言有关 |
| --- | --- | --- |
| `Data/Patch-W.MPQ` | 收藏专用武器 M2、SKIN 和 BLP | 通常无关，但必须来自兼容的纯净 3.3.5a 数据 |
| `Data/<locale>/patch-<locale>-N.MPQ` | 扩展后的 `CreatureModelData.dbc` 与 `CreatureDisplayInfo.dbc` | 有关，必须从自己的语言客户端生成 |

旧 `v0.1.0` Release 中的 `patch-zhCN-6.MPQ` 不能给 enUS、zhTW、deDE、frFR
等客户端使用；`v0.2.0` 源码发布不包含任何 MPQ。

## 2. 前提

- 纯净 WoW 3.3.5a 客户端；
- Python 3.10；
- PowerShell 5.1/7 x64；
- [StormLib 官方项目](https://github.com/ladislav-zezula/StormLib)的 x64
  `StormLib.dll`；
- 本仓库源码。

脚本只读客户端原始 MPQ，并把所有中间文件写到仓库 `_work/weapon-models`。
不要对正在运行游戏的客户端执行部署。

## 3. 准备 StormLib

可以下载 StormLib 官方 Release，或使用 Visual Studio 2022/CMake 构建共享库。
将 x64 `StormLib.dll` 放到非系统盘工具目录，例如：

```text
<工具目录>\StormLib\StormLib.dll
```

然后设置：

```powershell
$env:SOLOCOLLECTIONS_STORM_DLL = '<工具目录>\StormLib\StormLib.dll'
```

仓库已经包含 `tools/mpq/StormMpq.ps1`，无需再设置包装脚本路径；如需替换，
可设置 `SOLOCOLLECTIONS_STORM_MPQ`。

## 4. 自动识别语言并只构建

以英文客户端为例：

```powershell
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-enUS>' `
  -Locale enUS `
  -LocalePatchNumber 6
```

先不要添加 `-Deploy`。脚本会：

1. 从客户端模型档案链提取经过验证的武器 M2、SKIN 和贴图；
2. 从目标语言最高优先级且同时含两张表的语言 MPQ 提取
   `CreatureModelData.dbc`、`CreatureDisplayInfo.dbc`；
3. 生成收藏专用模型副本和 DBC 行；
4. 创建 `Patch-W.MPQ` 与 `patch-enUS-6.MPQ`；
5. 从新 MPQ 回读每个文件并逐项比较 SHA-256；
6. 写出 `weapon-model-verification.csv`。

如果 `WTF/Config.wtf` 中有正确的 `SET locale`，可以省略 `-Locale`。检测到多个
语言目录时必须显式指定。

## 5. 不同语言示例

```powershell
# 简体中文
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-zhCN>' -Locale zhCN -LocalePatchNumber 6

# 繁体中文
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-zhTW>' -Locale zhTW -LocalePatchNumber 6

# 德文
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-deDE>' -Locale deDE -LocalePatchNumber 6
```

结果中的第二个文件会分别命名为 `patch-zhCN-6.MPQ`、
`patch-zhTW-6.MPQ`、`patch-deDE-6.MPQ`。

## 6. 显式指定 DBC 来源 MPQ

如果客户端语言目录结构特殊，或自动扫描找不到两张 DBC，可以先用 MPQ 工具
确认哪个档案同时含有：

```text
DBFilesClient\CreatureModelData.dbc
DBFilesClient\CreatureDisplayInfo.dbc
```

然后执行：

```powershell
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-enUS>' `
  -Locale enUS `
  -LocaleDbcArchive '<WoW-enUS>\Data\enUS\locale-enUS.MPQ' `
  -LocalePatchNumber 6
```

## 7. 选择语言补丁编号

`N` 允许 2 到 9。先检查 `Data/<locale>`：

- 如果 `patch-enUS-6.MPQ` 不存在，可用 6；
- 如果已经属于其他模组，选择 7、8 或 9；
- 不要覆盖来历不明的现有补丁；
- 同一 DBC 被多个高优先级补丁修改时可能互相覆盖，整合客户端需要合并 DBC，
  不是简单增加另一个编号。

这也是只承诺“纯净客户端可直接构建”的原因。

## 8. 检查构建结果

脚本输出类似：

```text
_work/weapon-models/build_<timestamp>/Patch-W.MPQ
_work/weapon-models/build_<timestamp>/patch-enUS-6.MPQ
_work/weapon-models/build_<timestamp>/weapon-model-verification.csv
```

确认 CSV 中所有 `Match` 均为 `True`。没有完成回读校验的 MPQ 不应部署或发布。

## 9. 部署

确认客户端关闭且同名文件已备份后：

```powershell
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory '<WoW-enUS>' `
  -Locale enUS `
  -LocalePatchNumber 6 `
  -Deploy
```

脚本会把旧同名文件备份到 `_work/weapon-models/backups/<timestamp>`，再复制并
从客户端最终路径回读校验。

## 10. 手工理解构建链

自动脚本等价于以下操作：

1. 用 `tools/mpq/StormMpq.ps1 extract` 从原始档案提取模型、SKIN、BLP 和 DBC；
2. 用 `patch_item_m2_textures.py` 修正收藏模型的纹理引用；
3. 用 `append_item_camera.py` 添加独立物品镜头数据；
4. 用 `build_creature_weapon_assets.py` 复制模型并向两张 DBC 追加保留 ID 行；
5. 将 `Item/...` 写入资源 MPQ；
6. 将 `DBFilesClient/...` 写入语言 MPQ；
7. 回读、比较长度与 SHA-256。

建议使用总控脚本，避免漏掉 SKIN、贴图或其中一张 DBC。

## 11. 回滚

关闭客户端，恢复 `_work/weapon-models/backups/<timestamp>` 中的旧文件；如果安装
前不存在同名文件，则删除新建的两个补丁。不要触碰 `common.MPQ`、
`common-2.MPQ`、`lichking.MPQ` 等原始档案。

### CLIENT-20260812-089 坐骑动作变更集回滚

坐骑偏好、随机技能与能力解析必须作为同一版本恢复，不能只回退客户端或只回退服务端：

1. 停止 WoW 客户端和 worldserver。
2. 若 schema/data 需要降级，先导出 `solo_collection_preference`；追加表可在兼容回滚中保留，但旧 worldserver 不得把它当作另一套生产权威。
3. 恢复同一 manifest 中的 worldserver、模块配置与匹配核心钩子。
4. 恢复该 worldserver 对应的服务端 `Spell.dbc`、`SkillLineAbility.dbc`。
5. 恢复部署前的 `SoloCollections` AddOn 备份，包括匹配的 catalog、SC2 schema 和 build metadata。
6. 恢复部署前的客户端语言 MPQ；使用 StormLib 从最终 MPQ 回读 DBC 并核对备份/manifest SHA-256。
7. 重启后确认技能 `150544`、mount mapping hash、type 10/type 16 schema 与 worldserver build 属于同一版本；若旧版本不含 `150544`，仅通过受控角色迁移清理未知动作栏槽。

上述 Spell/SkillLineAbility DBC 和客户端 MPQ 是本地私有变更，不进入公共源码仓库或 Release，也不得作为可再分发客户端资源发布。
