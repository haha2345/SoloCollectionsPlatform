# Camera parameter contributions / 镜头参数贡献

The item-page camera is intentionally open for community calibration.
物品页镜头仍欢迎社区提供可复现的参数和截图。

> 当前物品卡已切换为 ezCollections Classic/武器镜头，旧 SoloCam 镜头工作台
> 暂不驱动物品卡。下文工作台流程保留为历史资料；新的卡片修正应以
> `addon/SoloCollections/Data/EzCollectionsCamera.lua` 为基线，并附真实
> 3.3.5a 客户端截图后再进入适配层。

## 中文

### 为什么仍需要贡献

当前目录覆盖 20 个基础 race/sex 模型、9 个身体部位和大量独立武器展示，但
一个 profile 不可能自然适配所有 HD 模型、自定义骨架、特效 bounds 和极端长宽
比。常见问题包括：

- 头盔、肩甲、靴子被卡片裁切；
- 胸、腕、手、腰或腿的主体偏离中心；
- 矮小/高大种族沿用错误距离；
- 背部没有转到正确方向；
- 武器因为 header bounds 含特效而缩得过小；
- 盾牌、拳套、副手书、弓枪或超长武器过近/过远。

提交参数比只说“镜头不对”更有价值。项目内置镜头工作台，能够导出带稳定身份
和基线 hash 的 JSONL。

### 两套镜头系统

#### 身体部位

身份键是：

```text
raceId + sex + slot
```

九个 slot 为 `HEAD`、`SHOULDER`、`BACK`、`CHEST`、`WRIST`、`HANDS`、
`WAIST`、`LEGS`、`FEET`。工作台调整的是相对 canonical profile 的：

- `verticalOffsetDelta`
- `horizontalOffsetDelta`
- `distanceScaleMultiplier`
- `minimumDistanceDelta`
- `yawOffsetDelta`

canonical 输入在 `catalog/source/camera_profiles.json`，经过批准的差量在
`catalog/source/overrides/camera_profiles.json`。生成结果不要手工修改。

#### 独立武器与副手

镜头优先级固定为：

```text
appearance > model > weaponFamily > autoCamera
```

可调字段是 `yaw`、`pitch`、`roll`、`distanceScale` 和 target XYZ。

- 同 family 都有相同问题：选择 `weaponFamily`。
- 共享同一 M2 的多件物品都有问题：选择 `model`。
- 只有一个 appearance 有特殊材质/轮廓问题：选择 `appearance`。
- 自动 bounds 已正常：不要添加 override。

model override 源为
`catalog/source/overrides/weapon_model_camera_overrides.json`。不要上传 M2；
以 `modelSignature`、输入 hash、原因码和截图说明问题。

### 实机调参流程

1. 使用 WoW 3.3.5a build 12340，并记录 `Wow.exe` SHA-256、locale、
   分辨率、UI Scale 和是否使用 HD/自定义模型。
2. 安装与模块 metadata 匹配的 AddOn。局部镜头需要受支持的 SoloCam。
3. 打开“收藏 → 外观 → 物品”，选择目标护甲部位或武器类型。
4. 点击筛选栏旁的“镜头工作台”。
5. 一次只选择一个 scope；先调距离，再调上下/左右，最后才调整角度。
6. 普通轮廓、小型轮廓和极端轮廓至少各检查一个。
7. 点击“加入批次”和“复制本次修改”，按 `Ctrl+C` 复制 JSONL。
8. 把 JSONL 保存到仓库忽略的 `_work` 目录，生成 review-only 候选。
9. 执行 `/reload`，翻页、过滤、快速切换相邻卡片，确认没有串模型。
10. 关闭/移走 SoloCam 再检查失败关闭；不要让未知版本继续使用固定地址。

武器 JSONL 校验示例：

```powershell
$scratch = Join-Path $PWD '_work\camera-contribution'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

python .\tools\catalog\camera_tuning_import.py `
  --input (Join-Path $scratch 'weapon-camera-export.jsonl') `
  --appearance-report .\catalog\generated\appearance-presentation-report.json `
  --output (Join-Path $scratch 'weapon-camera-candidates.json')
```

身体 profile JSONL 校验与只读 review 示例：

```powershell
python .\tools\catalog\body_camera_tuning_import.py `
  --input (Join-Path $scratch 'body-camera-export.jsonl') `
  --camera-profiles .\catalog\source\camera_profiles.json `
  --output (Join-Path $scratch 'body-camera-candidates.json')

python .\tools\catalog\body_camera_tuning_review.py `
  --candidates (Join-Path $scratch 'body-camera-candidates.json') `
  --camera-profiles .\catalog\source\camera_profiles.json `
  --review-output (Join-Path $scratch 'body-camera-review.json')
```

这两个 import 默认不会改 canonical source。先把候选和截图放进 PR，由维护者
审核 scope 和身份后再合并 override。

### 截图与 PR 最低信息

请同时提供：

- 修改前与修改后，尽量使用同一分辨率、UI Scale、装备和窗口位置；
- 角色：`raceId`、sex、slot、profileKey；
- 武器：appearance ID、source item ID、weapon family、model signature；
- 客户端 build/hash/locale、HD/自定义模型说明；
- 工作台 JSONL 和 review-only 候选；
- 至少 3 个代表样本的结果；
- `/reload`、翻页、快速切换、无 SoloCam fallback 的结果。

截图可以提交压缩后的 PNG/JPEG；不要提交客户端资源、M2、DBC、MPQ、
SavedVariables 或包含账号/服务器隐私的完整画面。

### 验收目标

- `HEAD`：完整头盔、颈部和少量肩线，不裁顶部。
- `SHOULDER`：主肩甲居中，另一侧不是主体。
- `CHEST`：领口到胸甲下沿完整。
- `BACK`：从背面观察，披风主体无遮挡。
- `WRIST/HANDS`：手腕和手套分别有清晰主体。
- `WAIST`：腰带和挂件有纵向空间。
- `LEGS`：胯部到膝部完整，不把大腿塞满卡片。
- `FEET`：双脚和小腿下部完整。
- 武器：模型填充合理，无关键裁切，无角色/NPC fallback，无上一张卡残影。

## English

### Scope

The checked-in baseline covers the stock race/sex pages and nine body slots,
but HD models, custom skeletons, effect-heavy bounds, and unusual weapons still
need calibrated contributions.

Body identities use `(raceId, sex, slot)` and expose deltas for vertical and
horizontal offset, distance scale, minimum distance, and yaw. Canonical input
is `catalog/source/camera_profiles.json`; approved deltas live in
`catalog/source/overrides/camera_profiles.json`.

Standalone weapon precedence is:

```text
appearance > model > weaponFamily > autoCamera
```

Choose `weaponFamily` for a family-wide problem, `model` for every appearance
sharing one M2, and `appearance` only for a genuine one-record exception.
Never upload the model itself.

### Contribution loop

1. Record the 3.3.5a build, executable hash, locale, resolution, UI scale, and
   stock/HD/custom model status.
2. Use a matched AddOn/module metadata set and the supported SoloCam build when
   local framing is required.
3. Open Collections → Appearances → Items and click the camera workbench.
4. Tune one scope at a time: distance first, position second, rotation last.
5. Check normal, small, and extreme silhouettes.
6. Add the record to the batch and copy the workbench JSONL.
7. Run the review-only import commands shown above.
8. Recheck `/reload`, pagination, filters, fast card switching, and the
   no-SoloCam fail-closed path.

A camera pull request must include stable identities, the JSONL and review
candidate, before/after screenshots, client details, representative samples,
and fallback results. Screenshots are welcome; extracted M2/DBC/MPQ data,
SavedVariables, and private account/server information are not.
