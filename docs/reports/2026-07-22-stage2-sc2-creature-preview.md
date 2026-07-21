# 阶段 2：SC2 Creature Preview 实施与验收记录

日期：2026-07-22

## 结论

阶段 2 已完成。正式 AddOn 的坐骑/宠物预览不再发送 SC1，也不依赖 ALE；服务端只接收 logical `typeId + collectionId`，从同一份生成目录解析可信 `PreviewCreatureEntry`，复用 Core Creature Query handler 给当前 session 预热客户端缓存。冷 WDB 全量扫描结果为坐骑 `281/281 READY`、宠物 `24/24 READY`、失败 `0`。

## Core ABI 审计与构建

- 审计 Core commit：`4cc67a316d2bec9faf27c3392634282e70cacbe0`。
- 请求 opcode：`CMSG_CREATURE_QUERY = 0x060`，位于 `Opcodes.h:126`。
- handler 签名：`void WorldSession::HandleCreatureQueryOpcode(WorldPacket&)`，声明位于 `WorldSession.h:748`，实现位于 `QueryHandler.cpp:127`。
- handler 读取顺序：`uint32 entry` 后接 raw `ObjectGuid`（该分支为 8 字节），位于 `QueryHandler.cpp:129-131`；adapter 因而构造 12 字节内部请求并写入可信 Entry 与 `ObjectGuid::Empty`。
- adapter 不复制 `SMSG_CREATURE_QUERY_RESPONSE` 布局。不存在或无模型的 Entry 在调用 Core handler 前由 `ObjectMgr` 拒绝；冷缓存实机扫描的 305 个已知 Entry 均实际经过 Core handler 并收到可加载模型。
- clean Core x64 RelWithDebInfo 静态模块构建通过；`worldserver.exe` 大小 `40,760,832`，SHA-256 `af67c59743cb93b31248263d1353feac70da84fe7c181523b49b6f8ddcbcc582`。生成的 ModulesLoader 调用 `Addmod_solo_collectionsScripts()`，PE 为 x64 Windows CUI。

## 服务端与协议边界

- 新增 `SoloCollectionsCreaturePreviewService`；公开输入严格为 `Player*`、`CollectionTypeId`、`CollectionId`。
- 仅接受 ready/enabled 的 mount、companion provider，按 `catalogLifecycle` 决定可预览性；客户端不能提交 Creature Entry 或 Display ID。
- `CreatureTemplate` 和至少一个模型存在后，才调用现有 Core handler；该 service 无数据库写入、revision/delta、施法、召唤或世界实体修改。
- HELLO 声明的 `metadataVersion` 对所有 Q 做完全一致校验；PREVIEW 另校验 `assetPackVersion`。协议版本仍为 1。
- PREVIEW 复用每 session burst `12`、补充 `6 token/s` 的共享 SC2 token bucket，并保留 nonce、replay cache、category ready、结构化日志和关联响应。
- 实际运行配置为 `D:\AzerothCore_NPCBots_Clean\configs\modules\transmog.conf`；`SoloCollections.Preview.Enabled = 1`。配置置 `0` 后 `.transmog reload` 立即使状态变为 `preview=0` 且客户端显示“模型预览暂不可用”；恢复 `1` 并 reload 后无需重启即可继续预览。

## 客户端边界

- `RequestCreaturePreview(typeId, collectionId, callback)` 只调用 SC2 `PREVIEW`；兼容 wrapper 只委托该函数。
- SC1 `pendingModels`、`pendingPetModels`、`MODEL_READY`、`PET_MODEL_READY` 已删除。
- 协议 Q/R 超时为 5 秒且不自动重发；成功后本地模型加载窗口为 2 秒，重试点为 `0.10/0.25/0.50` 秒。
- 失败立即清空模型并显示明确 unavailable；成功也必须 generation 仍匹配。快速切换产生的旧回调由 generation guard 丢弃。

## 部署与回滚演练

- 部署 ID：`20260722-021232-010`。
- 部署前 PE SHA-256：`8cdad8fc572b116feb0f347bbe97f6f2a9de2ea33b7e9c29fe325ba8bd0e8683`；部署后运行 PE 与构建产物同为 `af67c597...bcc582`。
- 完整旧 PE、实际配置和部署 manifest 保存在 `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\runtime-backups\20260722-021232-010`。
- AddOn 部署备份：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\addon-backups\20260722-021250-011-51a494ffa59c4bb9a278b9d9d202e907`。
- 配置关闭/恢复分别生成 F 盘备份 `config-20260722-021406-153`、`config-20260722-022426-676`；两次 `.transmog reload` 均成功，证明无需重启即可回滚 PREVIEW，且不会启用 ALE。

## 冷 WDB 全量实机证据

- 审计 run ID：`20260722-023638-896`。
- 审计工具只发送 PREVIEW，主动限速 `4/s`，逐条要求 `GetModel()` 连续两帧稳定；不包含 SUMMON/USE/APPLY。
- 结果：`305/305 READY`、`0 failed`，其中 `281` 坐骑、`24` 宠物；全部 preview status 为 `ACCEPTED`，过期 generation 丢弃探针为 true。
- CSV：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage2-full-scan\20260722-023638-896\runtime-audit.csv`；SHA-256 `f06dfad8db6771380635f2422364e92bd2d9e0c48b40fafbd3e4b71c042bbf45`。
- summary、原始 SavedVariables 与首/中/末截图保存在同一 run 目录。首条/第二条坐骑、首条宠物、配置关闭提示的交互截图保存在 `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage2-preview`。
- 冷测试生成的 9 个 WDB 文件已隔离到 F 盘，原缓存按逐文件 SHA-256 恢复；manifest 最终状态为 `RESTORED`，时间 `2026-07-21T18:47:49.3824380Z`。临时 QA AddOn 已从客户端移回 run 目录，可恢复但不进入正式 bundle。

## 自动验证

- AddOn Python：`197` 项通过，`3` 项因外部兼容媒体/本地部署 manifest 条件跳过。
- module Python：`130` 项通过。
- Lua 5.1：`25` 个正式/QA Lua 文件全部通过语法检查。
- module native：domain/protocol `2/2` 通过，覆盖未收藏 PREVIEW/同项 SUMMON `NOT_OWNED`、metadata/asset gate、replay 和共享限流。
- 目录生成器带命名 evidence pack 执行 `--check` 通过；mapping hash 为 `1fc77655c08118c89e7bfb31e9a2cfd95cdc068ba473d8615adb6e1ff3706a7a`。
- clean Core x64 worldserver 增量复编通过，运行目录 PE 哈希与构建产物一致。

## 回滚

首选把实际 `transmog.conf` 的 `SoloCollections.Preview.Enabled` 设为 `0` 并执行 `.transmog reload`。若必须回退二进制，则使用上述部署备份同时恢复 worldserver、module generated catalog 与匹配的 AddOn bundle；不得重新启用 ALE。
