# SoloCollections 架构文档索引

本目录记录当前 AddOn、目录、客户端镜头和武器展示的实现边界。先阅读仓库根目录
`AGENTS.md` 和 [开发指南](../DEVELOPMENT.md)，再按修改范围选择文档。

## 阅读顺序

1. [01-收藏系统总体架构.md](01-收藏系统总体架构.md)
2. [02-正式服风格公共UI.md](02-正式服风格公共UI.md)
3. [03-坐骑页实现.md](03-坐骑页实现.md)
4. [04-小宠物页实现.md](04-小宠物页实现.md)
5. [05-玩具箱实现.md](05-玩具箱实现.md)（上线暂不启用，实现停在 `feat/deferred-toy-box`）
6. [06-外观页和套装页.md](06-外观页和套装页.md)
7. [07-外观各部位镜头参数.md](07-外观各部位镜头参数.md)
8. [08-客户端SoloCam扩展.md](08-客户端SoloCam扩展.md)
9. [09-武器与副手独立模型.md](09-武器与副手独立模型.md)
10. [10-性能优化与避坑.md](10-性能优化与避坑.md)

## 当前架构边界

| 层 | 权威职责 |
| --- | --- |
| AddOn | UI、过滤、固定卡片池、客户端缓存、SC2 收发 |
| Catalog | stable identity、审核决定、生成映射和客户端展示 metadata |
| `mod-solo-collections` | 账号收藏、权限、revision、同步和服务端动作 |
| SoloCam | 一个精确 3.3.5a x86 客户端的可选局部镜头/display bridge |
| 客户端资源 | 用户本地、独立许可、版本化且可回滚的可选输入 |

生产环境只有 C++/SC2 后端可以写入和返回收藏动作成功。`server/ale` 只保留旧版
迁移/协议参考。

## 当前实现概况

- 坐骑、小宠物、玩具、外观和套装都由生成目录与 SC2 权威状态驱动。
- 角色物品页使用 20 个基础 race/sex 页面、九部位共 180 个 profile。
- 武器/副手使用独立模型、稳定 synthetic display identity 和分层镜头覆盖。
- 物品页内置镜头工作台，导出先进入 review-only 流程。
- 目录规模不应增加模型 frame 或常驻 `OnUpdate` 数量；页面使用固定对象池。

最新数量、已验证范围和限制见 [STATUS.md](../STATUS.md)。
2026-08-18 收藏手册 + 幻化室验收见
[2026-08-18-collections-transmog-acceptance.md](../evidence/2026-08-18-collections-transmog-acceptance.md)。
镜头贡献请直接阅读
[CAMERA_CONTRIBUTIONS.md](../CAMERA_CONTRIBUTIONS.md)。

## 阅读旧实现细节时的规则

各篇保留了有用的算法和失败路线，但源码始终是当前事实。若文档中的函数名或
路径与代码不一致，以 `addon/SoloCollections`、`client-extension/SoloCam`、
`catalog` 和模块仓库当前文件为准，并在修改中同步修正文档。

不要把编译或自动检查当作真实客户端视觉验收；模型、镜头和 UI 结论必须说明
实际客户端证据是否存在。
