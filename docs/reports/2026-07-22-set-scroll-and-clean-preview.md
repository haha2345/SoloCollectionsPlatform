# 阶段 2：套装滚动与干净试穿检查点

日期：2026-07-22 至 2026-07-23
状态：完成。

## 范围

- 基础滚动和 generation 状态机来自 AddOn 提交 `8be7240`（`fix: make set scroll and preview deterministic`）。
- 本轮补齐了 `Wardrobe.lua` 的固定 12 格部件池、静态合同测试，以及仅用于真实客户端验收的 `SoloCollectionsSetAudit` 和离线验收器。
- 不修改 ItemSet identity、owned、`variantOrdinal`、服务端 APPLY、module、Core、数据库、DLL、MPQ 或 WDB。
- 真实客户端测试使用的是临时 AddOn；完成后已还原原始 `Wardrobe.lua` 和 `SoloCollections.lua`，并把临时 AddOn/SavedVariables 移入 F 盘证据目录。

## 实现结果

- `scSetOffset` 与竖向 Slider 直接一一对应；滚轮、分页、拖动和过滤重置均经由 `setSetOffset()`，结果集变化时会 clamp。
- 每次 `previewSet()` 都递增 generation。模型经 `ClearModel`、`SetUnit`、两个 render tick 后才 `Undress()`，随后仅按稳定槽位顺序 `TryOn` 当前 selected variant 的确定成员。
- 原目录当前最大 active variant 只有 8 件；UI 仍预分配固定的 12 格可复用部件池，使将来的 9 件套不会截断，也让 synthetic 9 件 fixture 能覆盖真实的显示路径。该池不改目录数据或任何服务端映射。
- 页面隐藏、切回物品页、角色/性别模型变化和重新进入世界都会取消 pending preview；旧 generation、旧 `OnUpdate` 和延迟 item-cache 回调不能写回新选择。

## 静态验证

在 AddOn worktree 执行：

```powershell
python -m unittest discover -s tools\collections\tests -p 'test_*.py' -q
```

结果：286 通过，3 个已指定跳过项；其中包含滚动直接映射、统一输入转换、末页 clamp、selected-variant-only、stable slot order、generation 拒绝和 fixed 12-slot pool 的合同测试。

使用 F 盘现有 Lua 5.1 校验器对 25 个 AddOn Lua 文件和临时审计 AddOn 的 1 个 Lua 文件执行 `luac51 -p`：26/26 通过。`git diff --check` 也通过。

## 真实客户端验收

证据根目录：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-addon\runtime-audit\stage2-set-preview\stage2-20260723-053314`。

临时 `SoloCollectionsSetAudit` 在真实客户端中调用生产套装页，并以 `Undress`/`TryOn` hook 记录实际调用序列；其 synthetic 数据仅在测试会话内注入，不写回生产目录。验收结果为：

- 分页覆盖空列表、单页、恰好 8 条、多页和最后残页：`0/1/8/17` 条；17 条场景落在 offset `9`、第 `3/3` 页、8 条可见。
- 中部拖动后的 offset 为 `228`；一次向下滚轮后为 `229`，页码、可见记录和滑块同向连续，没有跳变。
- 选择 2、3、5、8 件真实套装及 9 件 synthetic selected variant；每个记录的实际 `TryOn` 列表都等于该 variant 的稳定去重成员列表。
- 先注入肩、衬衣、战袍、腰带和武器的预穿戴状态后，二件套预览先执行 `Undress`，未包含槽位没有残留。
- 连续快速选择 20 个套装，以及对全部 465 个 active 套装的自动扫描，均无 generation 串装、空模型或 Lua error；每一项都有非空且一致的 expected/actual 调用记录。
- 第二次 `/reload` 后审计状态仍为 `READY`，`reloadObserved=true` 已保存到磁盘。

离线复核命令：

```powershell
python tools\catalog\check_set_preview_audit.py `
  --saved-variables runtime-audit\stage2-set-preview\stage2-20260723-053314\SoloCollectionsSetAudit.ready-persisted.lua `
  --screenshot-directory runtime-audit\stage2-set-preview\stage2-20260723-053314\client-screenshots
```

输出：`{"mode":"sets","paginationCases":4,"reloadObserved":true,"samples":7,"sets":465,"syntheticNinePiece":true}`。

截图：

- `client-screenshots\pagination-last-partial.jpg`：17 条 synthetic 查询的最后残页（`3/3`）。
- `client-screenshots\pregear-clear.jpg`：预穿戴清空测试正在运行。
- `client-screenshots\reload-ready.jpg`：reload 后 `Stage 2 set audit: reload persistence READY`。

## 客户端回收

验收结束后，客户端 `Wardrobe.lua` 已恢复到 SHA-256 `C839DDC9BF9498587D9B499469B5C8D5299D0DAD3ECCDB7665262D61E18AF805`，`SoloCollections.lua` 已恢复到 SHA-256 `899CE1E22523928BF03D685D0356282C99096BD35CA3FFD7FF805F0092A11B47`。临时审计 AddOn 和其 SavedVariables 已从客户端移除并归档到上述证据目录。
