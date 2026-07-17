# SoloCollections v{{VERSION}} 发布包

本目录包含可安装插件、ALE Lua、SoloCam DLL/补丁器和客户端 MPQ。安装前关闭
客户端与服务器，并备份所有同名文件。

## 网盘

> 主链接：[百度网盘下载](https://pan.baidu.com/s/1XyCl8PaimIVPPSTNUDaIOg?pwd=j8sk)  
> 提取码：`j8sk`  
> 对应素材包版本：未单独标注，以网盘内文件名和说明为准

网盘提供正式服风格完整素材及维护者说明的其他客户端文件。下载后先校验哈希，
再按原路径覆盖。任何游戏 EXE 都必须由使用者自行确认合法来源和使用权。

GitHub 发布包里的 AddOn 默认不含 `Media/Retail` 正式服提取素材；没有安装网盘
素材包时，相关按钮和预览位置可能显示为空白，但项目自制占位素材仍会保留。

## 安装顺序

1. 解压 `addon/SoloCollections-v{{VERSION}}.zip` 到 `<WoW>/Interface/AddOns`。
2. 复制 `server/solo_collections.lua` 到 ALE `lua_scripts`，重启世界服。
3. 复制 `client-patches/Data/Patch-W.MPQ` 到 `<WoW>/Data`。
4. 只有 `{{LOCALE}}` 客户端才能直接使用 `client-patches/Data/{{LOCALE}}/{{LOCALE_PATCH}}`。
5. 其他语言必须从自己的纯净客户端构建 `patch-<locale>-6.MPQ`。
6. 将 `client-extension/SoloCam.dll` 和 `poc_patch.py` 放在客户端根目录。
7. 仅当原 `Wow.exe` SHA-256 为
   `AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8`
   时运行：

```powershell
python .\poc_patch.py .\Wow.exe .\Wow-SoloCam-PoC.exe
```

8. 使用 `Wow-SoloCam-PoC.exe` 启动，保留原 `Wow.exe`。
9. 安装网盘素材，进入游戏验收坐骑、宠物、玩具、外观、套装和武器预览。

## 重要边界

- `patch-zhCN-6.MPQ` 不能给 enUS/zhTW/deDE 等语言使用。
- 已存在同名 MPQ 时先备份，可能属于其他模组。
- 当前 ALE 是演示/动作桥，不是完整账号级持久化收藏服务。
- 项目自有代码使用 `GPL-3.0-or-later`，详见同目录和 AddOn ZIP 内的 `LICENSE`。
- 项目不授权游戏 EXE 或第三方素材的再分发。
- 使用 `SHA256SUMS.txt` 检查发布包文件。
