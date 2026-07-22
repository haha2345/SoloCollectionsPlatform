# 阶段 3：ItemSet 展示排序检查点

日期：2026-07-22  
状态：排序数据、生成投影和关键客户端筛选路径已完成；全量搜索、分页、重登和跨角色矩阵仍待完成。

## 范围与提交

- AddOn/目录提交：`b7abdea`（`feat: rank wardrobe sets by reviewed presentation`）。
- 本检查点没有修改 module、Core、数据库、DLL、MPQ 或 WDB。`set_catalog.py` 只有显式传入 `--include-module` 才允许写 module 投影；本次未使用该选项。
- 固定输入包：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\stage3-fixed-inputs`。
- 客户端部署前备份：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\addon-backups\20260722-stage3-set-presentation\SoloCollections`。

## 数据与排序合同

- `itemset_import.py` 读取 `ItemLevel` 与 `Quality`，为候选成员记录缺失等级并聚合 min/max/median item level；evidence schema 升至 3，旧输入不满足新 schema 时 fail closed。
- canonical identity mapping hash 保持为 `2110892144adcdf60834c30785569ef38b5af7980cbdb62d684846cf44cc87cf`；展示排序字段不进入 owned、ItemSet identity 或 variantOrdinal。
- `catalog/source/overrides/set_presentations.json` 以 ItemSet ID 范围审核 T7--T10：T7 `787--805`、T8 `820--838`、T9 `843--880`、T10 `883--901`。未有经审阅规则的 active 项明确输出为 `UNKNOWN`，不按本地化名称猜测。
- `set_presentations.py` 为 509 个 review units（465 active）生成 JSON/CSV；当前 presentation hash 为 `62caf760deb2edab3372c6e5f9e4418c4ec8c9346d3faf084b54f84a64d9584b`。
- `Catalog.QueryAll("SETS")` 采用固定 presentation comparator，最后以 `itemSetId` 和 collection ID 作为稳定 tie-breaker；过滤后仍在同一比较器下排序。

## 验证

以下测试为 17/17 通过：

```powershell
python -m unittest -v tools.collections.tests.test_itemset_import tools.collections.tests.test_set_catalog tools.collections.tests.test_set_presentations
python tools\catalog\itemset_import.py check --repo-root . --evidence-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\stage3-fixed-inputs
python tools\catalog\set_presentations.py check --repo-root .
python tools\catalog\set_catalog.py --module-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-module --evidence-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\stage3-fixed-inputs --check
```

所有 AddOn Lua 文件也通过 Lua 5.1 syntax check。数据库输入只通过本地 MySQL 的只读导入命令采集，未执行写入。

## 真实客户端证据

证据目录：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\client-stage1`。

- `stage3-wrath-t10-first-page.jpg`：默认套装页 `1/59` 的首屏为 T10 血法等后期 Wrath 团队套装。
- `stage3-paladin-t10-first-page.jpg`：选择 `PALADIN` 后结果为 175 套、22 页，首屏为 T10 光誓套装，确认职业过滤后仍沿用排序比较器。

客户端 `/reload` 后没有 AddOn Lua error。测试结束后已恢复原有 SavedVariables 会话筛选，并关闭衣橱。

## 尚未关闭的验收

- 当前规则审计覆盖 509 个 review units，但未实现同层级 hero/normal 的完整差异化难度排序；未审阅项安全地保留 `UNKNOWN`。
- 尚未形成搜索、分页、重登和不同职业角色的完整实机矩阵。
- 因为上述验收尚缺，阶段 3 仍不是完成状态。
