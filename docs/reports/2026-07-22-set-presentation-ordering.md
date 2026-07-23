# 阶段 3：ItemSet 展示排序检查点

日期：2026-07-22 至 2026-07-23
状态：完成。

## 范围与边界

- 基础 presentation 生成和 AddOn 投影来自 `b7abdea`（`feat: rank wardrobe sets by reviewed presentation`）。
- 本轮补齐了同层级高 item-level cohort、`HEROIC` 预留 rank、真实客户端排序审计器和离线验收器。
- 排序仍是 AddOn-only presentation 投影；不会进入 ItemSet identity、owned、`variantOrdinal`、服务端 APPLY 或 module/Core。`set_catalog.py` 本次没有传 `--include-module`。
- canonical mapping hash 保持 `2110892144adcdf60834c30785569ef38b5af7980cbdb62d684846cf44cc87cf`；新的 presentation hash 为 `44c7748c2c60e8b748cc415260637329492ac797d46d9780ed054eadd7897192`。

## 可审核的高难度排序

- 比较器固定为 expansion、acquisition、tier、difficulty、median item level、max item level、ItemSetID、collection ID。最后两个字段提供语言无关的稳定 tie-breaker。
- T8 的经审阅 item-level evidence 把 median `226` 的 cohort 标为 `HIGH`，排在同 T8 的 median `219` `RAID` cohort 前；T7 同理把 median `213` 排在 median `200` 前。对应 reason code 明确写入生成审核表，不从中文或英文名称猜测。
- `HEROIC` rank 保留在 `HIGH` 之上，且有 synthetic policy fixture 证明其优先级；当前原始 evidence 中 19 个 T10 均为 median `251`、38 个 T9 均为 median `232`，没有可审计的 heroic/normal 区分，因此没有伪造这两个层级的难度标签。
- 生成后的首段顺序为 T10 ItemSet `883--901`、T9 `843--880`；T8 高 item-level entries（包括 `821`、`822`）位于 T8 normal entry `820` 前，等 rank 时仍按 ItemSetID 升序稳定。

## 静态验证

执行：

```powershell
python -m unittest discover -s tools\collections\tests -p 'test_*.py' -q
python tools\catalog\set_presentations.py check --repo-root .
python tools\catalog\set_catalog.py --module-root F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-module --check
```

结果：290 通过、3 个已指定跳过项。完整 AddOn 加临时 Stage 3 审计器的 Lua 5.1 syntax check 为 26/26；生成器与 AddOn 投影均 byte-stable，module 输出保持 unchanged，`git diff --check` 通过。

## 真实客户端验收

证据目录：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-addon\runtime-audit\stage3-set-ordering\stage3-20260723-061301`。

临时 `SoloCollectionsSetOrderAudit` 在生产套装页上通过实际搜索框、职业过滤和滚动条运行，并把全部 465 个 ItemSetID 的完整排序签名保存到 SavedVariables。它验证：

- PALADIN 与 PRIEST 两名实际角色均得到 465 个全量套装，且两份全量排序签名相同；跨职业结果为 `differentClassPass=true`。
- PALADIN 的职业过滤结果为 175 条，PRIEST 为 165 条；两者均在同一比较器下有序。审计还通过真实搜索框搜索首条 T10 记录，结果非空、有序且在可见行中。
- 首页 offset `0`、第 `1/59` 页与最后 offset `457`、第 `59/59` 页均与实际可见行一致；T10 prefix 和 T7/T8 高 item-level cohort 顺序均通过。
- `/reload` 后 `reloadPass=true`；登记重登签名后使用客户端内置 `/logout`、再次进入同一圣骑士，`relogPass=true`。审计器不从 AddOn 强行调用 `Logout()`，以保证该步骤是真实角色会话转换。

离线验收：

```powershell
python tools\catalog\check_set_order_audit.py `
  --saved-variables runtime-audit\stage3-set-ordering\stage3-20260723-061301\SoloCollectionsSetOrderAudit.ready.lua `
  --screenshot-directory runtime-audit\stage3-set-ordering\stage3-20260723-061301
```

输出：`{"classes":["PALADIN","PRIEST"],"crossClass":true,"mode":"set-ordering","reload":true,"relog":true,"runs":2,"sets":465}`。

截图：

- `paladin-reload-ready.jpg`：圣骑士 reload 后审计 READY。
- `paladin-relog-ready.jpg`：受控重登后圣骑士审计 READY。
- `second-class-ready.jpg`：第二个实际角色 PRIEST 的审计 READY。

## 客户端回收

验收结束后，客户端 `Wardrobe.lua` 已恢复至 SHA-256 `C839DDC9BF9498587D9B499469B5C8D5299D0DAD3ECCDB7665262D61E18AF805`，`SoloCollections.lua` 已恢复至 SHA-256 `899CE1E22523928BF03D685D0356282C99096BD35CA3FFD7FF805F0092A11B47`。临时排序审计 AddOn 和其 SavedVariables 已从客户端移除并归档到证据目录。
