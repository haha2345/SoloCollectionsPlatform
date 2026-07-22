# 阶段 2：套装滚动与干净试穿检查点

日期：2026-07-22  
状态：部分完成；滚动方向和预览状态机已经实现并在真实客户端验证关键路径，完整的压力与覆盖矩阵仍待完成。

## 范围与提交

- AddOn 提交：`8be7240`（`fix: make set scroll and preview deterministic`）。
- 本检查点只修改 AddOn 和其测试；module、Core、数据库、DLL、MPQ 与 WDB 均未修改。
- 客户端部署前备份：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\deploy\addon-backups\20260722-stage2-set-preview\SoloCollections`。

## 已实现的行为

- `scSetOffset` 与垂直 Slider 采用直接映射；滚轮、分页、拖动和过滤重置都经由同一个 `setSetOffset()`，并在结果集变化时 clamp。
- 套装预览每次选择递增 generation；模型先 `ClearModel`、`SetUnit`，等待两个 render tick 后 `Undress()`，再按稳定槽位顺序只 `TryOn` 当前 `selectedVariant.members` 的确定 source item。
- 页面隐藏、切回物品页、模型变更和重新进入世界都会取消 pending preview，过期 generation 不能写回新选择。

## 静态验证

在 AddOn worktree 中，以下 7 个针对性合同测试均通过：

```powershell
Push-Location tools\collections\tests
python -m unittest -v `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_scroll_uses_a_direct_offset_slider_mapping `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_scroll_inputs_share_the_single_offset_state_transition `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_scroll_clamps_filter_resets_and_last_partial_page_in_one_transition `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_preview_is_generation_aware_and_undresses_before_tryon `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_preview_uses_only_the_selected_variant_members `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_preview_rejects_stale_work_and_cleans_pending_state `
  test_wardrobe_camera_set_contract.WardrobeCameraSetContractTests.test_set_preview_selects_one_deterministic_source_per_member_slot
```

Lua 5.1 syntax check also passed for all AddOn Lua files。完整 `test_wardrobe_camera_set_contract` 当时为 10 通过、3 个预期后续阶段失败（镜头工作台、全量 weapon registry、相机覆盖优先级），因此不把它记为完整阶段绿灯。

## 真实客户端证据

证据目录：`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set\client-stage1`。

- `stage2-sets-all-initial.jpg`：套装页初始为第一页，滑块位于顶部。
- `stage2-sets-page2.jpg`：分页前进保持同向。
- `stage2-sets-last-page-drag.jpg`：滑块拖到最后页，页码为 `59/59`。
- `stage2-sets-wheel-scroll.jpg`：从最后页滚轮向上后变为 `58/59`，列表和滑块同向。
- `stage2-sets-late-page-selection.jpg`：后段页的套装选择显示正确成员。
- `stage2-sets-clean-two-piece-preview.jpg`：两件套只保留该套装实际成员，之前的五件预览没有残留。

## 尚未关闭的验收

- 尚未形成中部拖动后再滚轮的无跳变证据。
- 尚未覆盖 3、8、9 件套，以及先装备肩、衬衣、战袍、腰带和武器后的清空矩阵。
- 尚未完成连续 20 次快速切换和 465 个 active ItemSet 的自动扫描。

这些项目仍保留为实施计划中的未勾选项；本检查点不把阶段 2 视为完成。
