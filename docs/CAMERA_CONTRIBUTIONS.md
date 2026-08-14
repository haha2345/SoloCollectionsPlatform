# Camera parameter contributions / 镜头参数贡献

The item-page camera is intentionally open for community calibration.
物品页镜头仍欢迎社区提供可复现的参数和截图。

> 当前物品卡已统一切换为 Transmorpher 3.0.0 Classic preview setup；旧
> ezCollections 镜头和 SoloCam 镜头工作台均不驱动物品卡。下文工作台流程只作
> 历史资料；新的卡片修正应以
> `addon/SoloCollections/Data/TransmorpherPreviewSetup.lua` 为基线，并附真实
> 3.3.5a 客户端截图后再设计最小 override。

## 中文

### 为什么仍需要贡献

当前 Transmorpher 投影覆盖 20 个基础 race/sex 模型、9 个身体部位和大量武器
子类，但
一个 profile 不可能自然适配所有 HD 模型、自定义骨架、特效 bounds 和极端长宽
比。常见问题包括：

- 头盔、肩甲、靴子被卡片裁切；
- 胸、腕、手、腰或腿的主体偏离中心；
- 矮小/高大种族沿用错误距离；
- 背部没有转到正确方向；
- 武器因为 header bounds 含特效而缩得过小；
- 盾牌、拳套、副手书、弓枪或超长武器过近/过远。

提交明确身份、原 setup、期望差量和前后截图，比只说“镜头不对”更有价值。
旧镜头工作台能够导出历史 profile 的 JSONL，但该输出不会直接驱动现行卡片。

### 现行身份与历史调参资料

#### 身体部位

现行 Transmorpher 身份键是：

```text
raceFileName + sex + Armor + slot
```

九个 slot 为 `HEAD`、`SHOULDER`、`BACK`、`CHEST`、`WRIST`、`HANDS`、
`WAIST`、`LEGS`、`FEET`。旧工作台曾调整相对 canonical profile 的：

- `verticalOffsetDelta`
- `horizontalOffsetDelta`
- `distanceScaleMultiplier`
- `minimumDistanceDelta`
- `yawOffsetDelta`

这些 canonical/override 文件现在仅保留为历史资料，不是 Transmorpher 卡片的
参数来源。

#### 独立武器与副手

旧独立武器工作台的优先级是：

```text
appearance > model > weaponFamily > autoCamera
```

可调字段是 `yaw`、`pitch`、`roll`、`distanceScale` 和 target XYZ。

- 同 family 都有相同问题：选择 `weaponFamily`。
- 共享同一 M2 的多件物品都有问题：选择 `model`。
- 只有一个 appearance 有特殊材质/轮廓问题：选择 `appearance`。
- 自动 bounds 已正常：不要添加 override。

该 model override 源为
`catalog/source/overrides/weapon_model_camera_overrides.json`。不要上传 M2；
以 `modelSignature`、输入 hash、原因码和截图说明问题。

现行武器卡按 `raceFileName + sex + render slot + weapon subclass` 读取
Transmorpher setup，不读取上述旧优先级。

### 实机调参流程

1. 使用 WoW 3.3.5a build 12340，并记录 `Wow.exe` SHA-256、locale、
   分辨率、UI Scale 和是否使用 HD/自定义模型。
2. 安装与模块 metadata 匹配的 AddOn；武器页使用受支持的 SoloCam v11，护甲
   不需要 DLL 强制槽位桥。
3. 打开“收藏 → 外观 → 物品”，选择目标护甲部位或武器类型。
4. 记录当前 `raceFileName`、sex、稳定 slot、物品 ID 和命中的 Transmorpher
   setup；不要让旧镜头工作台改写运行时。
5. 一次只分析一个身份；先比较距离，再比较上下/左右，最后比较朝向和 sequence。
6. 普通轮廓、小型轮廓和极端轮廓至少各检查一个。
7. 保存相同窗口位置、分辨率和 UI Scale 下的修改前后截图。
8. 把候选差量和证据保存到仓库忽略的 `_work` 目录，先做 review-only 设计。
9. 执行 `/reload`，翻页、过滤、快速切换相邻卡片，确认没有串模型。
10. 关闭/移走 SoloCam 再检查失败关闭；不要让未知版本继续使用固定地址。

以下 JSONL 命令只用于核对历史工作台候选，不会修改现行 Transmorpher setup。

武器历史 JSONL 校验示例：

```powershell
$scratch = Join-Path $PWD '_work\camera-contribution'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

python .\tools\catalog\camera_tuning_import.py `
  --input (Join-Path $scratch 'weapon-camera-export.jsonl') `
  --appearance-report .\catalog\generated\appearance-presentation-report.json `
  --output (Join-Path $scratch 'weapon-camera-candidates.json')
```

身体历史 profile JSONL 校验与只读 review 示例：

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

这两个 import 默认不会改 canonical source，也不会改变现行卡片。任何新的
Transmorpher override 都应先单独设计并由维护者审核身份、来源和截图。

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

The active baseline is the checked-in Transmorpher 3.0.0 Classic preview
projection. It covers the stock race/sex pages, nine armor slots, and weapon
subclasses, but HD models, custom skeletons, effect-heavy bounds, and unusual
weapons can still need calibrated contributions.

Active body identities use `(raceFileName, sex, Armor, slot)`. The canonical
and override profile files under `catalog/source` are retained as historical
workbench material and do not drive item cards.

The historical standalone weapon workbench precedence is:

```text
appearance > model > weaponFamily > autoCamera
```

The active weapon cards instead select a Transmorpher setup by race, sex,
render slot, and weapon subclass. For historical workbench evidence, choose
`weaponFamily` for a family-wide problem, `model` for every appearance
sharing one M2, and `appearance` only for a genuine one-record exception.
Never upload the model itself.

### Contribution loop

1. Record the 3.3.5a build, executable hash, locale, resolution, UI scale, and
   stock/HD/custom model status.
2. Use a matched AddOn/module metadata set and SoloCam v11 for weapon slots;
   armor uses the native TryOn path.
3. Open Collections → Appearances → Items and record the active Transmorpher
   identity and setup. Do not use the historical workbench to mutate runtime.
4. Analyze one identity at a time: distance first, position second, rotation
   and sequence last.
5. Check normal, small, and extreme silhouettes.
6. Capture before/after evidence at the same window position and UI scale.
7. Keep any candidate override review-only until its identity and provenance
   have been approved.
8. Recheck `/reload`, pagination, filters, fast card switching, and the
   no-SoloCam fail-closed path.

A camera pull request must include stable identities, the JSONL and review
candidate, before/after screenshots, client details, representative samples,
and fallback results. Screenshots are welcome; extracted M2/DBC/MPQ data,
SavedVariables, and private account/server information are not.
