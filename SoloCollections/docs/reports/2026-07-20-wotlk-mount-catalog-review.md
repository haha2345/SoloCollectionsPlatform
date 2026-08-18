# WotLK 坐骑目录审核报告

- 数据版本：`3.3.5.12340`
- 候选 Hash：`ba414a13d43783698251b283ccd3d19030560f44b3e3238931b83e1a73d0249e`
- 正式动作法术：295
- 正式逻辑坐骑：281
- 排除法术：101
- 分组规则：`EXACT_CREATURE_ENTRY_ONLY`（只合并 mounted creature entry 完全相同的动作，不按名称或速度合并）

## 审核边界

正式 allowlist 必须同时满足玩家坐骑 SkillLine 777、CreatureTemplate 存在、当前客户端 Display 资源存在，并通过固定人工排除表。
候选 Hash 发生变化时生成器会失败，必须重新审核并更新 review-policy；数据库凭据不会写入证据文件。

## 排除统计

- `INTERNAL_VARIANT_NOT_LEARNED`：3
- `NOT_PLAYER_MOUNT_SKILL_LINE`：87
- `NPC_OR_TEST_MOUNT`：2
- `SUPERSEDED_LEGACY_VARIANT`：3
- `SUPERSEDED_UNUSED_VARIANT`：1
- `TEST_SPELL`：1
- `UNUSED_LEGACY_NO_ACQUISITION_SOURCE`：2
- `UNUSED_PROFESSION_TEST_VARIANT`：1
- `UNUSED_TEST_VARIANT`：1

## 输出

- `catalog/generated/mount-candidates.csv`：全部候选与逐项决策。
- `catalog/generated/mount-exclusions.csv`：排除原因。
- `catalog/source/collections/mounts.csv`：正式逻辑坐骑目录。
- `catalog/source/mount_actions.json`：服务端动作/解锁映射。
