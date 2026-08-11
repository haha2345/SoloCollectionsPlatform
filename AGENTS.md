# SoloClientSuite Agent Guide

本仓库只负责完整客户端 AddOn 套件的集成、构建、来源锁定与回退；不拥有 SoloCollections 业务源码、SC2 协议或服务端数据库。

## Source ownership

- `Interface/AddOns/!!!ClassicAPI`：上游兼容层快照。
- `Interface/AddOns/DragonUI`、`DragonUI_Options`：上游基础 UI 快照。
- `Interface/AddOns/DragonUI_NewEra`：项目维护的 UI 平台分支。
- `Interface/AddOns/SoloCollections`：由 sibling `../SoloCollections/addon/SoloCollections` 生成，禁止手工修改。
- `build/Interface/AddOns/SoloCollections_EzUI`：由参数化导入器从用户授权的本地 ezCollections 2.2 快照生成，只含媒体与来源标记，不进入 Git。
- `build/`：可删除的本地构建产物，不进入 Git。

任何同步都必须更新 `upstream/suite-lock.json` 中的 commit、目录 Hash、同步日期和 patch 状态。不得把第三方文件统一声明为 SoloCollections GPL。

This repository owns integration, provenance, build output, and rollback only. Product logic remains in the sibling SoloCollections repository, and server authority remains in mod-solo-collections.

