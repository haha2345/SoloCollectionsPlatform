# Update and rollback / 更新与回退

## Update

1. 在独立上游 clone 中取得明确 commit，不使用“最新版”。
2. 运行 `tools/Sync-Upstream.ps1`，输入三个 clone 路径和明确 commit。
3. 更新 `upstream/suite-lock.json` 的 commit、TOC、目录 Hash、日期与 patch 状态。
4. 运行布局检查，再构建到 `build/`。
5. 不在此流程中部署真实客户端。

## Rollback

- 源码回退：切回已记录的集成仓库 commit；第三方 vendor tree 随 commit 回退。
- 构建回退：删除仓库内忽略的 `build/`，重新从旧 commit 构建。
- 客户端回退：必须在另行授权的部署步骤中先备份目标 AddOns，再以 manifest 校验恢复；本仓库工具不直接写真实客户端。

