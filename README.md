# SoloCollections：WoW 3.3.5a 独立收藏系统

[English](README.en.md) | [完整中文说明](README.zh-CN.md) | [下载与网盘](docs/DOWNLOADS.md)

SoloCollections 为纯净的 World of Warcraft 3.3.5a build 12340 客户端补充一套
接近正式服收藏手册的界面和交互，将坐骑、非战斗小宠物、玩具、装备外观和套装
集中在一个独立插件中。项目同时提供 AzerothCore ALE 服务端桥、可选的 SoloCam
客户端镜头扩展，以及主手/副手独立模型所需的 MPQ 构建工具。

> 当前版本为开发预览版。界面、静态目录和演示动作已经可用；账号级永久收藏、
> 完整解锁钩子、全量同步和生产级外观后端仍在开发中。

## 界面预览

| 坐骑 | 非战斗小宠物 |
| --- | --- |
| ![坐骑收藏与模型预览](docs/images/mounts.png) | ![非战斗小宠物收藏与模型预览](docs/images/pets.png) |

| 玩具箱 | 物品外观 |
| --- | --- |
| ![玩具箱与物品提示](docs/images/toys.png) | ![物品外观与部位筛选](docs/images/wardrobe-items.png) |

![套装收藏与试衣间预览](docs/images/wardrobe-sets.png)


## 项目包含什么

| 部分 | 用途 | 是否必需 | 安装位置 |
| --- | --- | --- | --- |
| `addon/SoloCollections` | 收藏手册 UI 与静态目录 | 必需 | `Interface/AddOns/SoloCollections` |
| `server/ale/solo_collections.lua` | 握手、模型缓存和演示动作桥 | 联机功能需要 | ALE 的 `lua_scripts` 目录 |
| `client-extension/SoloCam` | 3D 局部镜头与武器显示桥 | 可选 | DLL 与补丁后的 EXE 位于客户端根目录 |
| `Patch-W.MPQ` | 收藏专用武器 M2/SKIN/BLP | 武器独立模型需要 | 客户端 `Data` |
| `patch-<locale>-6.MPQ` | 两张 Creature DBC 的收藏扩展行 | 武器独立模型需要 | `Data/<locale>` |
| 网盘完整素材包 | 正式服风格素材和可选客户端文件 | 完整视觉需要 | 按压缩包原路径覆盖客户端 |

当前静态目录基线：24 个坐骑、24 个非战斗小宠物、36 个玩具、70 个外观、
8 套套装。

## 下载

GitHub 源码不上传客户端提取素材、游戏 EXE、MPQ、编译产物或私有完整包。
本地 `release/v0.1.0` 已整理好插件、Lua、DLL 和两个 MPQ，可从中选择权利清楚的
文件作为 GitHub Release 附件；正式服素材和客户端文件通过网盘单独提供。两个
MPQ 含客户端衍生数据，公开上传前仍需由维护者确认有权分发。

> **网盘主链接：[百度网盘下载](https://pan.baidu.com/s/1XyCl8PaimIVPPSTNUDaIOg?pwd=j8sk)**  
> **提取码：`j8sk`**

版本对应关系、校验和与覆盖方法见[下载说明](docs/DOWNLOADS.md)。

## 最快安装方法

1. 备份纯净 3.3.5a 客户端，关闭游戏。
2. 将 Release 中的插件 ZIP 解压到 `Interface/AddOns`。
3. 将 `solo_collections.lua` 复制到服务器 ALE `lua_scripts` 目录并重启世界服。
4. 将 `Patch-W.MPQ` 复制到 `Data`。
5. 只使用与你客户端语言相同的 DBC 补丁：
   - 简体中文：`Data/zhCN/patch-zhCN-6.MPQ`
   - 英文：自行构建 `Data/enUS/patch-enUS-6.MPQ`
   - 繁体中文：自行构建 `Data/zhTW/patch-zhTW-6.MPQ`
6. 如需 SoloCam，将 `SoloCam.dll` 和 `poc_patch.py` 放到客户端根目录，使用用户
   自己合法取得且哈希匹配的 `Wow.exe` 生成 `Wow-SoloCam-PoC.exe`。
7. 下载网盘素材包，核对版本与 SHA-256 后，按原路径覆盖到客户端根目录。

详细步骤见[安装指南](docs/INSTALLATION.zh-CN.md)。非国服客户端不要安装
`patch-zhCN-6.MPQ`，请阅读[跨语言 MPQ 自建指南](docs/BUILD_MPQ.zh-CN.md)。

## 开发与编译环境

| 组件 | 环境 | 构建命令 |
| --- | --- | --- |
| AddOn | 文本编辑器；WoW 3.3.5 Lua 5.1 API | 无需编译 |
| ALE Lua | AzerothCore + [mod-ale](https://github.com/azerothcore/mod-ale) | 无需编译，复制后重启/重载 |
| Python 测试/补丁器 | Python 3.10，`capstone==5.0.6`、`pefile==2024.8.26` | `python -m unittest ...` |
| SoloCam DLL | Windows 10/11、VS 2022 Build Tools、MSVC C++、Windows SDK、x86 工具链 | `client-extension/SoloCam/scripts/build.ps1` |
| MPQ | PowerShell 5.1/7、Python 3.10、x64 StormLib、纯净 3.3.5a 客户端 | `build-weapon-models.ps1` |

完整环境安装、命令和产物位置见[构建指南](docs/BUILDING.zh-CN.md)。

## SoloCam 的严格边界

SoloCam 只支持 x86 WoW 3.3.5a build 12340，并锁定原始 `Wow.exe` SHA-256：

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

补丁器只创建 `Wow-SoloCam-PoC.exe`，不覆盖原文件。其他客户端版本、汉化修改
过的 EXE 或不同哈希会被拒绝。项目源码和 GitHub Release 不应包含游戏 EXE；
网盘中若提供客户端文件，下载者和发布者都必须自行确认拥有合法使用与分发权限。

## 如何参与开发

本仓库是唯一源码源头。不要直接修改游戏安装目录后再反向覆盖仓库。

1. Fork 仓库并从 `main` 创建功能分支。
2. 一次 PR 只处理一个明确功能或问题。
3. 不提交游戏 EXE、MPQ、客户端提取素材、数据库密码或编译缓存。
4. 修改行为时同步更新测试和文档。
5. 运行 122 项收藏系统契约测试、SoloCam Python 测试；修改 C++ 时再运行 x86
   原生构建测试。
6. PR 中写明客户端哈希、服务端版本、验证步骤、结果和截图。

详细规则见[贡献指南](CONTRIBUTING.md)。

## 许可证

SoloCollections 自有代码采用 **GNU GPL-3.0-or-later**，完整许可证见
[LICENSE](LICENSE)。分发修改版时必须继续提供对应源码、保留许可证和修改说明。
客户端提取素材、游戏 EXE、MPQ 内容和第三方库不自动获得本项目代码许可证，
必须分别遵守其原有条款。详见[许可证说明](docs/LICENSING.md)。

## 免责声明

本项目是非官方、非商业的兼容性研究和社区开发项目，与 Blizzard Entertainment
或 AzerothCore 官方无隶属或背书关系。游戏名称、商标和客户端资源归各自权利人
所有。请仅使用自己有权使用的客户端和素材。
