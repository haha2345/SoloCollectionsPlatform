# Downloads and version matching / 下载与版本匹配

## Current source line / 当前源码线

The current `main` branch is newer than the historical `v0.1.0` package and
uses the separate C++ server module:

- AddOn: <https://github.com/haha2345/SoloCollections>
- Module: <https://github.com/haha2345/mod-solo-collections>

当前 `main` 比历史 `v0.1.0` 安装包更新，生产后端是独立 C++ 模块。源码用户
必须使用匹配的 AddOn/module commits 和 catalog metadata。

## Historical release / 历史发布

The old prerelease remains available for archival and migration reference:

<https://github.com/haha2345/SoloCollections/releases/tag/v0.1.0>

`v0.1.0` is an ALE/SC1 development preview. Do not install its server bridge or
client package beside the current C++/SC2 source and assume they are compatible.

`v0.1.0` 是 ALE/SC1 开发预览。不能把它的服务端桥或客户端包与当前 C++/SC2
源码混装后宣称兼容。

## Client resources / 客户端资源

The source repositories intentionally do not distribute game executables,
patched executables, MPQ/DBC/DB2/M2/SKIN/BLP/WDB files, extracted client media,
or database dumps. Users build optional SoloCam and client-resource components
locally from material they are entitled to use.

两个源码仓库不发布游戏 EXE、补丁 EXE、MPQ/DBC/DB2/M2/SKIN/BLP/WDB、
客户端提取素材或数据库。可选 SoloCam 和客户端资源由用户在本地从有权使用的
材料构建。

Before using any future release, verify:

1. AddOn, module, and AzerothCore commits;
2. SC2 protocol and metadata version;
3. asset pack token and per-category mapping hashes;
4. SQL schema/migration version;
5. file SHA-256 and license/provenance notes.
