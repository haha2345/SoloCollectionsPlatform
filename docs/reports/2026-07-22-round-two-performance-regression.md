# SoloCollections 第二轮性能回归

验收日期：2026-07-22（Asia/Shanghai）

## 固定压力分母

性能探针固定同时覆盖 18,190 个 canonical appearance、201 个宠物审核候选和 509 个 ItemSet shadow 审核单元。正式目录仍使用审核后的 active 数，压力分母不会通过减少正式内容来规避回归。

AddOn `SC.Diagnostics.RunPerformanceBaseline()` 现在输出：五个主页的首开/刷新耗时；18,190 外观的 load/filter/page 计时；18,190/201/509 联合只读索引、搜索和分页计时；快照 reassembly 字节数、分块、耗时和峰值内存；隐藏页面待处理模型任务、残留 OnUpdate 和固定模型池大小。

C++ `.solocollections benchmark` 使用 18,190 外观上界，并在稳定 `key=value` 结果中同时记录 `shadow_sets=509`、`companion_candidates=201`、目录 materialize/filter/Find 索引耗时。appearance catalog 和 set catalog 继续在启动时构造只读索引；SC2 PREVIEW 只做目录解析与 Core creature query，不访问账号或 World 数据库。

## 验收结果

- 自动合同确认宠物、玩具、套装使用固定/受上限约束的对象池；隐藏卡片无残留逐帧 OnUpdate。
- 第 8 阶段 Computer Use 实机在 465 套正式目录下完成职业筛选、搜索、1/59→2/59 翻页和 `/reload`，未出现逐帧全目录构造或可感知卡顿。
- 原生目录/协议测试使用只读索引并通过；module Python 性能与健康合同继续覆盖登录查询、快照 chunk、队列、内存、重复 unlock 和失败分类。
- 配套二进制安装后通过 Computer Use 在真实 3.3.5 客户端重新运行 `SC.Diagnostics.RunPerformanceBaseline()`：展开规模加载 `22.407 ms`、506 页、峰值约 `6865.3 KiB`，快照重组 `8.623 ms`；隐藏页面没有 pending model 或 active card OnUpdate 残留。
- `.solocollections benchmark` 实机结果为 `scale=18190 shadow_sets=509 companion_candidates=201 catalog_entries=18190 materialized=18190 filtered=18190 found=18190 load_us=55 filter_us=49 lookup_us=350`。本轮压力基线通过，没有通过删减正式数据规避回归。
