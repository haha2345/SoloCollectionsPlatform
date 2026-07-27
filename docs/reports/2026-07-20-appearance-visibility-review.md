# WotLK 外观可见性审核

审核日期：2026-07-22（Asia/Shanghai）

## 结论

本轮对 18,190 个 canonical appearance 逐项建立了独立 `uiLifecycle`，没有删除或重分配任何 canonical ID，也没有改写账号 owned 数据。服务端授权继续只由 `catalogLifecycle` 决定；`uiLifecycle` 仅控制正式衣柜是否展示条目。

| uiLifecycle | 数量 |
|---|---:|
| `public` | 13,831 |
| `hidden_internal` | 1,375 |
| `deprecated` | 139 |
| `test` | 242 |
| `unobtainable` | 2,603 |
| `deferred` | 0 |
| 合计 | 18,190 |

审核 evidence ID 为 `round2-20260722-appearance-visibility`，decision hash 为 `1605226c302a7884420756e8a1c9760815abff242035f8ce8d1272f0d32a2785`。输入 canonical appearance mapping hash 为 `f418b28486adc98ba8b2d59fd98059a99ba31c9f44f4366189e151264a92f92b`，输入文件 SHA-256 为 `19a89e3fd40df6e1554d1769d4cc0e8bd9a007f7e13ed1597934b24f6c4f63fa`。

## 证据和判断

每个审核单元固定记录 `item_template` 是否存在、display 是否匹配、class/subclass/inventory type、quality、bonding、flags/FlagsExtra，以及是否在 vendor、loot 或 quest 奖励来源中出现。名称中的 `TEST`、`Monster`、`Deprecated`、`OLD` 等只先记录为风险信号，再按固定 review policy 分类；人工结论可通过 `catalog/source/overrides/appearance_visibility.json` 显式覆盖并留下 reason code。

默认规则为：证据缺失或 display 漂移进入 `deferred`；测试、内部和废弃信号分别进入 `test`、`hidden_internal`、`deprecated`；有可追溯来源的正常条目进入 `public`；World 中存在但本轮来源表未发现获取路径的条目进入 `unobtainable`。这个来源检查是保守的 shadow 证据，不把名称信号或缺少已知来源解释为 canonical identity 删除。

## 投影边界

- `catalog/review/appearances/visibility-evidence.json` 保存完整逐项证据和决定。
- `catalog/generated/appearance-visibility-report.csv` 是便于人工抽查的扁平报告。
- generated AddOn/module manifest 携带 `uiLifecycle`；正式衣柜只枚举 `public` 外观。
- C++ appearance provider、type 13 owned、APPLY 授权和 canonical source resolution 继续使用全部 `catalogLifecycle=ACTIVE` 条目。
- mapping canonicalization 从本版起排除 `uiLifecycle` 和 `presentationHash`；展示分类后续变化不会伪装成授权映射变化。该合同调整与 metadata `2026.07.22.4` 配套发布。

## 验证

`appearance_visibility.py check` 会重新读取当前 World 数据库并逐字节核对 evidence/CSV；目录生成器要求 18,190 项一一覆盖、identity 与 `catalogLifecycle` 相等，并拒绝未知 lifecycle、重复 ID 或未知 override。合同测试同时验证非 public 条目不会进入正式衣柜且 canonical ID 集合零丢失。
