# SoloCollections client camera PoC

第二版处理一个种族/性别组合：WoW 3.3.5a build 12340、当前锁定的客户端、
人类女性，以及外观目录当前开放的头、肩、背、胸、腕、手、腰、腿、脚 9 个角色部位。
主手和副手卡片则由插件使用独立 `Model` 帧显示 ItemDisplayInfo 模型，
不创建或显示角色模型。

## 边界

- 不修改 Character M2。
- 不修改 MPQ。
- 不覆盖原始 `Wow.exe`。
- 不启用 WotLK-Extensions 的其他补丁。
- 插件使用 `0x5341..0x5349` 中明确声明的 9 个哨兵值 + `SetCamera(1)`
  作为部位握手；没有 DLL
  时第二次调用会恢复 3.3.5 原生全身相机。
- DLL 只在对应卡片绘制期间临时调整相机，绘制结束立即还原原始坐标。

## 构建与部署

```powershell
& .\client-extension\SoloCam\scripts\deploy-poc.ps1 `
  -ClientDirectory 'D:\path\to\your\WoW-3.3.5a'
```

脚本优先使用环境变量 `SOLOCOLLECTIONS_VCVARS` 指定的
`vcvarsall.bat`，其次检查本机既有的 `D:\vs\buildtools`，最后尝试通过
Visual Studio Installer 的 `vswhere` 查找工具链。所有中间文件和产物位于
本组件的 `build` 目录。部署只会在指定客户端目录增加：

- `Wow-SoloCam-PoC.exe`
- `SoloCam.dll`

部署完成后使用客户端目录里的 `Wow-SoloCam-PoC.exe` 启动。当前验收范围仅为：

1. 登录人类女性角色。
2. 打开收藏 → 外观 → 物品。
3. 依次切换头、肩、背、胸、腕、手、腰、腿、脚 9 个角色部位。
4. 检查每种卡片是否稳定聚焦对应身体区域；拖动收藏窗口时，模型大小和宽高比例不应变化。
5. 切换主手和副手，确认卡片只显示武器/盾牌模型，不显示角色。

普通 `Wow.exe` 不会加载本 PoC，仍保留为回退入口。

原始客户端的 SHA256 必须是：

`AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8`

任何补丁点原字节不一致时，部署脚本都会拒绝继续。

## 主手与副手独立模型

3.3.5 的普通 `Model` 控件不会从 `ItemDisplayInfo.dbc` 自动绑定
`OBJECT_SKIN` 替换贴图。使用下面的命令会从客户端 `common-2.MPQ`
只读提取演示武器的 M2/skin，生成收藏专用模型副本，并部署为独立的
`Data\Patch-W.MPQ`：

```powershell
$env:SOLOCOLLECTIONS_STORM_MPQ = 'D:\path\to\StormMpq.ps1'
$env:SOLOCOLLECTIONS_STORM_DLL = 'D:\path\to\StormLib.dll'
& .\client-extension\SoloCam\scripts\build-weapon-models.ps1 `
  -ClientDirectory 'D:\path\to\your\WoW-3.3.5a' `
  -Locale zhCN -LocalePatchNumber 6
```

转换过程不会修改原武器模型或 BLP。构建、临时文件、回读文件与校验清单
全部写到仓库忽略的 `_work\weapon-models`；客户端新增当前配置的资源补丁。
StormLib 路径必须显式通过参数或上述环境变量提供，不属于本仓库。

先不加 `-Deploy`，确认回读校验 CSV 全部通过后再部署。非 zhCN 客户端必须
把 `-Locale` 改成自己的语言；脚本会生成 `patch-enUS-6.MPQ`、
`patch-zhTW-6.MPQ` 等对应文件，不能直接使用 zhCN DBC 补丁。完整步骤见
`docs/BUILD_MPQ.zh-CN.md`。

部署完成后会从最终 MPQ 回读全部 5 个 M2 和 5 个 skin，并逐个比较
SHA256。删除部署时生成的专用补丁并恢复脚本创建的备份即可回滚。公开发行前
还要把当前通用补丁名改为项目专用名称，防止覆盖其他模组；见
`docs/ASSETS.md`。
