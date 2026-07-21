# 阶段 1：Creature 展示投影与原生图标验收

日期：2026-07-22

结论：阶段 1 的图标回归通过。正式目录中的 281 个坐骑与 24 个小宠物都生成了可审核的原生图标和 `previewCreatureEntry`；AddOn 已消费这些展示字段，不再为整个坐骑或宠物类型使用同一张占位图。此结论不包含模型预览修复，模型链路仍由阶段 2 负责。

## 固定输入与生成结果

- evidence pack：`round2-20260722-stage1-presentations`
- evidence pack hash：`befe7234c5a121de64640a05f67d4cc8cf80b97afed799e8bf8fa5665eb980f7`
- presentation evidence hash：`77397654b86df41635e37a8dd94a3c75eb93f9da312404a43f4dd2b9becbb5f7`
- presentation hash：`f2864da12fab5371b76de9605d54cb82a7678cd611da2b98022271c75865d695`
- metadata version：`2026.07.22.1`
- overall mapping hash：`98fb49094bcb45a2efa143b3c49e3c8f3c752856de0c59068808ba0831b04b00`
- mount mapping hash：`742d6e4fdff57cc001ed6ad491c4f1e630c5b10c26fa46625ba82d5a679e8386`
- companion mapping hash：`f7a2316404395ecc63debdb836dde8ea59736d38343e24c1a1d1e22137fbf4bf`
- 坐骑：281/281 READY，101 个不同的原生图标。
- 小宠物：24/24 READY，23 个不同的原生图标。

`creature_presentations.py` 会验证 evidence pack 内每个成员的长度和 SHA-256，并重算 pack hash；DBC、审核策略或数据库提取证据漂移时均 fail closed。客户端投影不包含服务端动作授权字段，纯图标变化只影响 presentation hash，不影响 type mapping hash。

## 自动验证

- `python -B -m unittest discover -s tools/collections/tests -p 'test_*.py' -q`：192 项通过，2 项因未安装可选外部媒体/本地部署清单而跳过。
- Lua 5.1 语法验证：24 个 AddOn Lua 文件全部通过 `luac51 -p`。
- 主目录 `--check`、Creature presentation `check`、set catalog `--check` 均通过。
- 隔离模块工作树通过 `SOLOCOLLECTIONS_MODULE_ROOT` 显式选择；测试和生成器不再依赖固定目录名。

## 冷 WDB 真实客户端验收

客户端在备份原有 WDB 后以空 `Cache/WDB/zhCN` 启动，使用 `admin` 测试账号进入世界并打开 `/sc`：

- 坐骑首屏同时覆盖职业坐骑、地面坐骑、机械坐骑、龙类/飞行坐骑和合法共享图标组，未退回全局马图标。
- 小宠物按 `1-12/24`、`12-23/24`、`13-24/24` 三个视图滚动覆盖全部 24 条；所有条目都有原生图标，合法重复仅出现在共享图标证据允许的条目。
- 保存的精确搜索“奥妮克希亚幼龙”只返回一个条目并显示其原生图标；清除搜索后恢复完整目录。
- 切换选中条目后，列表图标与详情图标一致。
- 执行 `/reload` 后，坐骑图标差异化和详情一致性保持不变。
- 账号当前为 0 条已收集记录，因此真实客户端只能覆盖未收集状态；已收集/未收集共用同一展示 record 的不变式由 AddOn 合同测试覆盖，阶段 2 的服务端状态闭环会再次做双状态实机验收。
- 冷缓存下 Creature 模型仍为空，这是阶段 0 已冻结的失败基线；本阶段没有把图标通过误报为模型预览通过。

客户端截图存放在忽略目录 `_work/runtime-audit/stage1-icons`：

| 截图 | 内容 | SHA-256 |
|---|---|---|
| `WoWScrnShot_072226_010040.jpg` | 宠物 1-12/24 | `65f7377a84c24bc26df5111db6572fe4f8432a2dbab4b328b85bc8222426fa33` |
| `WoWScrnShot_072226_010101.jpg` | 宠物 12-23/24 | `78cd042a9909fcaab642f387d8d8e7aee31dd1fd98d0c91a69433796b9e4f236` |
| `WoWScrnShot_072226_010116.jpg` | 宠物 13-24/24 | `c9dd2754063ff36ef14e5b1834bf114a85820b65cd88160d62ded7ede20ff2b7` |
| `WoWScrnShot_072226_010133.jpg` | 坐骑类别与共享图标抽样 | `8d8a966823aa87b6ceba952196f356f6055ebc09a2f36ca5e146cb58afc2bf16` |
| `WoWScrnShot_072226_010148.jpg` | 坐骑列表/详情图标一致 | `500db55d00c3b9a8946ca02173e9bbf1958259787dd1d04b8c1785c82ebb1558` |
| `WoWScrnShot_072226_010254.jpg` | `/reload` 后图标保持 | `3bf91c7bb0a256276157bea9f37d08cab042ceb295c9c438c51db2d6827e3eee` |

客户端退出后恢复状态为 `RESTORED`：原有 9 个 WDB 文件逐个按 SHA-256 验证恢复，测试期间生成的 9 个 WDB 文件保留在隔离清单和 append-only journal 中，没有覆盖或删除原缓存证据。
