# 阶段 9：自动化集成、干净构建与候选演练

日期：2026-07-23

## 结论与边界

阶段 9 的自动化部分已完成：使用 F: 上的独立 worktree、临时目录和安装沙箱构建、验证并回滚候选包。没有推送、没有创建公开 release，也没有把候选安装到正在使用的客户端或服务端。

本报告不替代阶段 9.4 的真实客户端矩阵，也不替代用户最终验收；这些项目继续保持未完成。

## 冻结版本与 Hash

- AddOn：`94031f87d4fad5bcdf41097312b59809a5a3414e`
- module：`6955c1a62c67eb222f7b49e34273a347ac0deddf`（仅刷新 ItemSet 源证据 hash）
- Core：`4cc67a316d2bec9faf27c3392634282e70cacbe0`
- `metadataVersion`：`2026.07.23.2`
- `assetPackVersion`：`round-two-stage8-weapon-presentation-v2`
- catalog mapping hash：`fd5bfff27abddd0781065652c19e49e98786dbb80d7a098adf3cfb27237b35e1`
- aggregate presentation hash：`09586daae28fb421ac20f5b1abeb5ec966a15c1850ed38913020c6215a5c6ad5`
- set presentation hash：`44c7748c2c60e8b748cc415260637329492ac797d46d9780ed054eadd7897192`
- camera profile hash：`792f1654ce058b3241eb9bbf9d3cc23ccd106b08071ef77a97868fa9f3bda5a4`
- weapon registry hash：`c4969969b36daead6b8ae124aa7cb40bf19da76ead30892bd8bf90d14a4d50f9`
- Stage 8 weapon manifest hash：`976572e29d1d2ce8b5272a75b47d6c1ab1b73d019961fc1c4ad4533a71f9910d`
- Stage 8 manifest-file SHA-256：`eecc2731c24624e7c44467853d57c6b6ff3134a388c3e2b38257afed70200c56`

clean x64 `worldserver.exe` 的 SHA-256 为 `b25343e3b2d7ba95ef0c54642ab4d352e9504a78352b2835518548785e7ba507`，PE machine 为 `0x8664`，配置为 static modules。

## 干净检出与重建

干净根目录为：

`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-clean-r2-20260723`

该根目录的 `TEMP`、`TMP`、Python cache 和 CMake build 均位于 F:。CMake 配置为 Visual Studio 18 2026 / x64 / `MODULES=static`；首次并行编译遇到 MSVC PCH 内存资源错误后，以 `/m:1` 重新执行，成功生成上述二进制。

通过的检查包括：

- `generate_catalog.py --check`、`itemset_import.py check`、`set_catalog.py --include-module --check`；ItemSet 为 `509` review / `465` active。
- `weapon_bundle.py check`：`3,542` appearance、`5,805` stage 文件，manifest 完整闭合。
- Lua 5.1 语法检查、SoloCam x86 native build/bridge/probe。
- AddOn unittest：`318` passed（`4` skipped）；SoloCam unittest：`35` passed（`9` skipped）。
- 八个 AddOn/module 生成输出与开发工作树 SHA-256 完全一致，其中包括 Catalog.lua、CameraProfiles.lua、Sets.lua、normalized ItemSets 以及 module C++/JSON projection。
- repository hygiene（要求 tracked tree clean）通过；Core 中三个上游 MySQL 工具和 `deps/gsoap/stdsoap2.cpp` 的受控精确 allowlist 被显式记录，扫描本身没有关闭。

固定 evidence pack 为 `round2-20260723-stage9-current-v2`，pack hash 为 `129cc933bf6718544e7f662f06f7a54563f4764428b9c1ce6b9dc66971d3c84f`。从冻结 Stage 8 重放 MPQ 打包后，`5,805` 个条目重新 extract/hash 验证；assets 和 locale archive SHA-256 分别仍为 `55f1e316d384368369fdbec247a3c031bb56e58f4f6098e944ebaea1a6d4b5ec` 与 `3e610c0391b317ff14140f4a45f8889155433e98443257ff559e8d693764a5bc`。

## 候选包、fail-closed 与回滚

已生成并验证两个本地候选：

- `round2-20260723T092019Z-94031f8-6955c1a-4cc67a3`
- `round2-20260723T092934Z-94031f8-6955c1a-4cc67a3`

两者均有 `71` 个 manifest 成员，包含基础媒体、AddOn generated 数据、x86 `SoloCam.dll`、两份 MPQ、固定 evidence manifest 和 x64 `worldserver.exe` provenance。`Test-RoundTwoBundle.ps1` 通过 required media、PE、文件 SHA-256、构建 metadata、AddOn 常量与三仓 commit 校验。

在 F: 隔离安装沙箱中，profile 的 server/client/addon/DLL/MPQ 目标均为测试文件。第一次候选故意锁定 `patch-zhCN-z.MPQ`：安装在该目标失败后，已写入的 AddOn、worldserver、DLL 和首个 MPQ 自动回滚，六个原始目标均恢复为 SHA-256 `c28285cdd9183f12de164aca0bf9d73b774bd479f3a0b7ac5e77ad4d28dfa944`，且原本不存在的 AddOn 文件没有残留。

随后第一候选成功安装、通过 `-Installed` verifier 并完整恢复；第二候选在恢复后重新安装、再次通过 verifier、再次恢复。每次成功安装记录 `44` 个操作，恢复均验证原文件 hash。

另对第一候选临时篡改 `metadataVersion`，release verifier 明确失败为 `Build metadata mismatch: metadataVersion`；恢复 manifest 后正常 verifier 再次通过。这证明发布边界的版本不配套会 fail closed。真实客户端内的用户可见提示仍属于阶段 9.4 实机矩阵。

## 证据位置

- clean build、evidence、候选与沙箱：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-clean-r2-20260723`
- 当前 fixed evidence pack：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-clean-20260723\evidence-current-v2`
- Stage 8 全量 weapon stage：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723\stage8-production-v2`
- Stage 8 已安装 MPQ / AddOn / runtime audit 证据：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-weapon-bundles-20260723`

