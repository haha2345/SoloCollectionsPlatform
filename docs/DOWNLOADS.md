# 下载、网盘和版本对应

## 下载入口

> **GitHub Release：[SoloCollections v0.1.0](https://github.com/haha2345/SoloCollections/releases/tag/v0.1.0)**  
> **网盘主链接：[百度网盘下载](https://pan.baidu.com/s/1XyCl8PaimIVPPSTNUDaIOg?pwd=j8sk)**  
> **提取码：`j8sk`**  
> **对应项目版本：`v0.1.0`**  
> **网盘包版本：未单独标注，以网盘内文件名和说明为准**

## GitHub 与网盘分别提供什么

| 渠道 | 内容 | 不应包含 |
| --- | --- | --- |
| GitHub 源码 | Lua/C++/Python/PowerShell、测试、文档、自制占位素材 | EXE、MPQ、客户端提取素材、编译产物 |
| GitHub Release | 不含 `Media/Retail` 的插件 ZIP、ALE Lua、项目自行编译的 DLL、补丁器、经权利审计后允许发布的两个 MPQ、安装说明和校验清单 | 游戏原版 EXE；权利不明确的素材或 MPQ 不应上传 |
| 网盘 | 正式服风格完整素材包、客户端覆盖包；维护者自行决定是否提供客户端文件 | 密码、账号数据、未说明版本的混合客户端 |
| 本地 `release` | 插件、Lua、DLL、补丁器、两个 MPQ 和双语说明的完整发布候选 | 该目录整体被 Git 忽略，不能误当源码提交 |

## 下载后的安全检查

1. 先确认压缩包声明兼容的 Git 标签和网盘包版本。
2. 使用 Release 内 `SHA256SUMS.txt` 核对文件。
3. 对 EXE、DLL 和压缩包进行本地安全扫描。
4. 备份客户端 `Wow.exe`、`Interface/AddOns/SoloCollections` 以及所有同名 MPQ。
5. 不要把不同作者的整合包相互覆盖；先在纯净客户端验证。

## 网盘包推荐结构

```text
SoloCollections-Media-<pack-version>/
├─ media-pack.json
├─ SHA256SUMS.txt
├─ Interface/AddOns/SoloCollections/Media/...
├─ Data/...                         # 可选客户端素材补丁
└─ README.zh-CN.md
```

如果网盘中提供客户端 EXE，应单独放置并写明：来源、支持的 build、SHA-256、
是否已经修补，以及下载者必须自行确认拥有合法使用权。不要让一个来历不明的
EXE 静默覆盖用户原文件。

## 覆盖方法

将网盘包中从 `Interface` 或 `Data` 开始的目录复制到 WoW 客户端根目录，选择
合并目录并仅覆盖 SoloCollections 明确列出的路径。覆盖前后都保存 SHA-256
清单；卸载时按清单删除，不要删除用户其他模组文件。
