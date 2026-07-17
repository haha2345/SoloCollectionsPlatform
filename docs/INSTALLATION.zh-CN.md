# SoloCollections 完整安装指南

## 1. 适用范围

- World of Warcraft 3.3.5a build 12340；
- 推荐纯净、未整合其他客户端 DBC/M2 修改的客户端；
- AddOn 可独立运行演示界面；
- ALE Lua 提供服务端握手和演示动作；
- SoloCam 与两个 MPQ 用于完整的局部镜头和武器独立模型。

## 2. Release 文件说明

```text
release/v0.1.0/
├─ addon/SoloCollections-v0.1.0.zip
├─ server/solo_collections.lua
├─ client-extension/SoloCam.dll
├─ client-extension/poc_patch.py
├─ client-extension/requirements-dev.txt
├─ client-patches/Data/Patch-W.MPQ
├─ client-patches/Data/zhCN/patch-zhCN-6.MPQ
├─ README.zh-CN.md
├─ README.en.md
└─ SHA256SUMS.txt
```

## 3. 安装 AddOn

1. 关闭游戏。
2. 解压 `SoloCollections-v0.1.0.zip`。
3. 确认最终结构为：

```text
<WoW>/Interface/AddOns/SoloCollections/SoloCollections.toc
```

4. 登录角色，在插件列表中启用 `Solo Collections`。
5. 如果只安装 AddOn，收藏页仍能显示静态演示数据；依赖服务端的召唤/使用动作
   会保持演示或不可用状态。

## 4. 安装 ALE 服务端脚本

前提：服务器已经安装与当前 AzerothCore 兼容的 ALE/mod-ale。

1. 将 `server/solo_collections.lua` 复制到服务器的 ALE 脚本目录，例如：

```text
<AzerothCore runtime>/lua_scripts/solo_collections.lua
```

2. 保留旧文件备份。
3. 重启 `worldserver`；仅在你的 ALE 版本明确支持安全热重载时才使用热重载。
4. 查看世界服日志，确认脚本加载且没有 Lua 语法/API 错误。
5. 登录游戏打开收藏窗口，确认客户端收到 `SC1` 握手结果。

当前脚本不是完整持久化收藏数据库，只提供协议、白名单、限流、模型缓存和
演示动作桥。

## 5. 安装两个 MPQ

### zhCN 简体中文客户端

关闭游戏后复制：

```text
release/v0.1.0/client-patches/Data/Patch-W.MPQ
    -> <WoW>/Data/Patch-W.MPQ

release/v0.1.0/client-patches/Data/zhCN/patch-zhCN-6.MPQ
    -> <WoW>/Data/zhCN/patch-zhCN-6.MPQ
```

如果目标已存在，先备份，不能直接假设它属于 SoloCollections。

### enUS、zhTW、deDE 等客户端

`Patch-W.MPQ` 的模型资源可以用于纯净的同版本客户端，但
`patch-zhCN-6.MPQ` 只允许用于 zhCN。其他语言必须从自己的纯净客户端 DBC
生成：

```text
Data/enUS/patch-enUS-6.MPQ
Data/zhTW/patch-zhTW-6.MPQ
Data/deDE/patch-deDE-6.MPQ
```

具体命令见[跨语言 MPQ 自建指南](BUILD_MPQ.zh-CN.md)。

## 6. 安装 SoloCam

SoloCam 仅支持原始 EXE SHA-256：

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

1. 将 `SoloCam.dll` 和 `poc_patch.py` 放到客户端根目录。
2. 用 PowerShell 检查自己的 `Wow.exe`：

```powershell
Get-FileHash -LiteralPath '.\Wow.exe' -Algorithm SHA256
```

3. 哈希完全一致后执行：

```powershell
python .\poc_patch.py .\Wow.exe .\Wow-SoloCam-PoC.exe
```

4. 使用 `Wow-SoloCam-PoC.exe` 启动；原 `Wow.exe` 保留为回退入口。
5. 哈希不同必须停止，不能强行修改脚本地址。

`poc_patch.py` 本身只使用 Python 标准库；`requirements-dev.txt` 主要供地址分析
和测试使用。

## 7. 安装网盘素材

1. 从[下载说明](DOWNLOADS.md)中的维护者链接取得与 `v0.1.0` 对应的素材包。
2. 核对 SHA-256 和包内 `media-pack.json`。
3. 将包内 `Interface`、`Data` 等目录复制到 WoW 根目录。
4. 只覆盖清单列出的 SoloCollections 路径。
5. 若包中含客户端 EXE，先备份并核对哈希；项目不保证用户有权再分发游戏文件。

## 8. 推荐安装顺序

```text
纯净客户端备份
-> AddOn
-> 与语言匹配的两个 MPQ
-> 网盘完整素材
-> SoloCam DLL/PoC EXE
-> ALE Lua
-> 登录验收
```

## 9. 卸载与回滚

- 删除 `Interface/AddOns/SoloCollections`；
- 删除 `SoloCam.dll` 和 `Wow-SoloCam-PoC.exe`，不要删除原 `Wow.exe`；
- 恢复安装前备份的 `Patch-W.MPQ` 和语言补丁；若原来没有同名文件，再删除；
- 删除/恢复服务器 `solo_collections.lua` 后重启世界服；
- 网盘素材按其 SHA-256 清单逐项回滚。
