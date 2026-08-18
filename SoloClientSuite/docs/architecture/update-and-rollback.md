# Update and rollback / 更新与回退

## Update

1. 在独立上游 clone 中取得明确 commit，不使用“最新版”。
2. 运行 `tools/Sync-Upstream.ps1`，输入三个 clone 路径和明确 commit。
3. 更新 `upstream/suite-lock.json` 的 commit、TOC、目录 Hash、日期与 patch 状态。
4. 运行布局检查，再构建到 `build/`。
5. 如需 ezCollections 视觉素材，使用 `-EzCollectionsSource <root>` 显式生成本地 `SoloCollections_EzUI`；导入器必须通过来源树、关键文件和完整媒体投影三层 Hash。
6. 运行 `tools/Package-ClientSuite.ps1 -Version <id>`，保留 ZIP 的 SHA-256 输出和逐文件 JSON manifest。
7. 不在此流程中部署真实客户端。

## Rollback

- 源码回退：切回已记录的集成仓库 commit；第三方 vendor tree 随 commit 回退。
- 构建回退：删除仓库内忽略的 `build/`，重新从旧 commit 构建。
- 素材回退：`SoloCollections_EzUI` 只存在于忽略的本地构建；移除该生成目录或从旧的 Hash 锁定快照重建。缺失时 SoloCollections 明确 fail closed。
- 客户端回退：必须在另行授权的部署步骤中先备份目标 AddOns，再以 manifest 校验恢复；本仓库工具不直接写真实客户端。

项目 patch commit 由本仓库 Git 历史记录；上游 commit 和每个 AddOn 的目录 Hash 由 suite lock 记录。更新后必须同时提交 vendor 变更、lock 变更和相关文档，不能只改 Hash。
