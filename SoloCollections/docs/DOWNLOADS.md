# Downloads and version matching / 下载与版本匹配

## Latest release / 最新发布

SoloCollections `v0.2.0` is the current matched C++/SC2 source release:

<https://github.com/haha2345/SoloCollections/releases/tag/v0.2.0>

SoloCollections `v0.2.0` 是当前匹配的 C++/SC2 成套源码发布。

| Asset / 资产 | Purpose / 用途 |
| --- | --- |
| `SoloCollections-v0.2.0-unified-source.zip` | Recommended matched bundle / 推荐成套包 |
| `SoloCollections-v0.2.0-addon.zip` | Runtime WoW AddOn / 可直接安装的 AddOn |
| `mod-solo-collections-v0.2.0-source.zip` | AzerothCore module source / 随 Core 编译的模块源码 |
| `release-manifest.json` | Exact commits, SC2, catalog, asset, and SQL versions / 精确版本清单 |
| `RELEASE_SHA256SUMS.txt` | Public asset checksums / 公开资产校验 |

Read [RELEASE_USAGE.zh-CN.md](RELEASE_USAGE.zh-CN.md) or
[RELEASE_USAGE.en.md](RELEASE_USAGE.en.md) before installation.

安装前阅读 [中文使用说明](RELEASE_USAGE.zh-CN.md) 或
[English usage guide](RELEASE_USAGE.en.md)。

## Version matching / 版本匹配

Use the `v0.2.0` tag in both repositories. The release manifest pins:

1. AddOn, module, and AzerothCore commits;
2. SC2 protocol and metadata version;
3. asset-pack token and per-category mapping hashes;
4. SQL schema and migration version;
5. distribution exclusions and provenance boundaries.

两个仓库都使用 `v0.2.0` 标签。不能只替换 AddOn 或只替换模块后继续沿用不同
版本的生成目录。

## Historical release / 历史发布

The old prerelease remains available only for archival and migration reference:

<https://github.com/haha2345/SoloCollections/releases/tag/v0.1.0>

`v0.1.0` is an incompatible ALE/SC1 development preview. Do not install its
server bridge, catalog, MPQ, or DLL beside `v0.2.0` and assume compatibility.

`v0.1.0` 是不兼容的 ALE/SC1 开发预览。不能把它的服务端桥、目录、MPQ 或 DLL
与 `v0.2.0` 混装后宣称兼容。

## Client resources / 客户端资源

The `v0.2.0` source release intentionally contains no game executable, patched
executable, DLL, MPQ/DBC/DB2/M2/SKIN/BLP/WDB, extracted client media, database
dump, or credential. Build optional SoloCam and client-resource components
locally from material you are entitled to use.

`v0.2.0` 源码发布不包含游戏 EXE、补丁 EXE、DLL、MPQ/DBC/DB2/M2/SKIN/BLP/WDB、
客户端提取素材、数据库或凭据。可选 SoloCam 和客户端资源由用户从自己有权使用
的材料在本地构建。
