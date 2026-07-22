# SoloCollections 第二轮集成验收

验收日期：2026-07-22（Asia/Shanghai）  
范围：实施方案阶段 0–9；仅本地候选包，不创建 GitHub release。

## 结论

第二轮修复与扩展已全部实现并通过自动化、x86/x64 native、真实 AzerothCore worldserver、事务部署/恢复和真实 3.3.5 客户端验收。一个实际安装尝试因运行中的客户端锁定 MPQ 而 fail closed，并完整回滚；关闭客户端后同一候选包成功安装。正式账户的阶段 8 临时 grant/revoke 已清理，阶段 9 可见性审核不删除 canonical identity 或 owned 数据。

## 目录与版本

- metadataVersion：`2026.07.22.4`
- assetPackVersion：`wotlk-3.3.5a-local-1`
- global mapping hash：`fd5bfff27abddd0781065652c19e49e98786dbb80d7a098adf3cfb27237b35e1`
- presentation hash：`35cb282c84bf1cd7106d96214f3834d4a330efca2ba0bda763781991859eb840`
- type hashes：mount `dc0d6150…`、companion `73d3e456…`、toy `ad88d614…`、appearance `7d49a257…`、set `2110892144…`
- 外观审核：18,190 = public 13,831 + hidden_internal 1,375 + deprecated 139 + test 242 + unobtainable 2,603；deferred 0
- 外观可见性决定 hash：`1605226c302a7884420756e8a1c9760815abff242035f8ce8d1272f0d32a2785`
- ItemSet：509 个审核单元；accepted 465、excluded 34、deferred 10；正式 variant 465

## 构建与候选包证据

实机验收候选：`round2-20260722T050144Z-b0fba80-ac56258-4cc67a3`

- AddOn commit：`b0fba801f0c8b2e6619daa48d25118f776c90cb0`
- module commit：`ac5625801b49dae9d62b5ffd2fc70349ef20c032`
- Core commit：`4cc67a316d2bec9faf27c3392634282e70cacbe0`
- 配置：Visual Studio x64 `Release`、`MODULES=static`
- `worldserver.exe`：PE `0x8664`，SHA-256 `36e80b06d401ce253fdf6460e6ebbee0d15a7e89f7d5a6c6fb3e8cf49ab70fd1`
- bundle 共 56 个受 Hash 保护的文件，含正式 AddOn、x64 worldserver、配置模板、构建元数据、SoloCam.dll、Patch-W.MPQ、`Data/zhCN/patch-zhCN-6.MPQ` 与脱敏 evidence manifest。
- startup `event=build_info`、`.solocollections status`、module build metadata 与 release manifest 的 commit/version/hash 一致。

安装器在覆盖前生成 41 项 append-only backup 和 staged config。首次安装遇到客户端锁定 MPQ 时事务回滚；第二次安装成功，`Test-RoundTwoBundle.ps1 -Installed` 逐文件重算通过。独立 sandbox 还完成 install → installed verify → restore，38 个文件恢复后无残留。恢复脚本按 manifest 校验备份 Hash，不递归删除客户端或服务端目录。

## 自动化与 native 回归

- AddOn Python：239 passed，4 个明确标记的外部可选项 skipped。
- module Python：133 passed。
- module native：2/2 passed（Release x64）。
- SoloCam：x86 build/tests 与 `0x014c` PE 检查通过。
- Lua 5.1：版本化 Lua 全量 `luac -p` 通过。
- 主 catalog、set、presentation、camera 和阶段 6–9 子生成器 `--check` 均无漂移。
- clean Core x64 Release `worldserver` 完整构建通过，实际部署的 PE 来自该 build root。
- AddOn/module/Core 的 `git diff --check` 与仓库卫生检查通过；固定 Core commit 的三个既有 upstream MySQL CLI（`mysql.exe`、`mysqldump.exe`、`mysqlimport.exe`）和只命中变量名的 `deps/gsoap/stdsoap2.cpp` 以精确相对路径显式批准，其余凭据、dump、DBC/M2/BLP/MPQ、DLL/EXE、WDB 或 build artifact 均被拒绝。

## 真实客户端与运行时

使用 Computer Use 驱动 `D:\Games\wow335\World of Warcraft11\Wow.exe`，账号/角色进入世界后完成阶段 1–9 矩阵。关键最终补证：

- UI 外观生成表统计 `SC_VIS public 13831 nonpublic 4359`，普通目录只消费 `uiLifecycle=public`；canonical 18,190 与服务端授权 mapping 不变。
- 第 8 阶段牧师 T1：0/8 → 7/8 → 8/8，APPLY 从 disabled 到 enabled；故意失败时零部分提交，revoke/reload 后恢复 0/8。
- AddOn 压力基线：18,190 appearance、201 companion candidate、509 set shadow；load 22.407 ms、506 页、峰值约 6865.3 KiB、snapshot reassembly 8.623 ms，隐藏页无 pending model/OnUpdate。
- worldserver benchmark：`load_us=55 filter_us=49 lookup_us=350`，materialized/filtered/found 均为 18,190。
- 阶段 1–8 报告覆盖七档分辨率/UI Scale、冷/热 WDB、快速切换、两次 reload、重登、worldserver 重启、跨角色与跨账号隔离。

## 发布边界

本轮只生成并安装本地 release candidate。没有推送远程分支、创建 tag、GitHub release 或上传客户端资产。最终候选包的 `release-manifest.json` 是已部署二进制与源码 commit 的权威追溯记录；本报告和计划勾选属于验收后文档提交，不改变已实机验证的运行逻辑与 catalog 内容。
