# SoloCollections 衣橱图标、全量武器镜头工作台与套装体验实施方案

日期：2026-07-22

状态：待实施（问题诊断与真实客户端复核已完成，代码尚未修改）

上游基线：

- [统一收藏后端设计](2026-07-19-solo-collections-unified-backend-design.md)
- [统一收藏后端第一轮实施方案](2026-07-19-solo-collections-unified-backend-implementation.md)
- [第二轮展示修复与目录扩充实施方案](2026-07-20-solo-collections-round-two-remediation-and-expansion-implementation.md)
- [阶段 3：独立武器展示验收记录](../reports/2026-07-22-stage3-standalone-weapon-presentations.md)
- [阶段 5：角色相机矩阵验收记录](../reports/2026-07-22-character-camera-profile-generation-and-runtime-matrix.md)
- [阶段 8：ItemSet 目录审核记录](../reports/2026-07-20-wotlk-itemset-catalog-review.md)

本方案承接第二轮已经关闭的实现，不重开已完成阶段，也不改变统一收藏后端。它专门处理 2026-07-22 真实客户端测试发现的衣橱图标、收藏入口、武器展示与镜头校准、套装排序与试穿、套装滚动条问题，并把第二轮明确留到后续的全量武器资源生成纳入一个可审计、可回滚的实施批次。

## 0. 方案使用规则

1. 本文所有实施项初始为 `- [ ]`。完成一项后立即改为 `- [x]`，在同一行追加完成日期、提交、测试或实机证据路径。
2. “代码已写”“测试已绿”“DLL 已加载”都不能单独视为视觉任务完成；涉及图标、模型、镜头、套装和滚动条的任务必须有真实 3.3.5 客户端证据。
3. 每个阶段只有在阶段出口全部满足后才能标记完成。部分子项完成时，只勾选对应子项，不提前勾选阶段出口。
4. 实施文件、临时解包、DBC、M2、SKIN、BLP、MPQ、DLL、截图、录像和运行审计必须放在 F 盘工作目录或既有 D 盘客户端部署目录；不得在 C 盘创建新的工作输出。
5. 当前用户截图位于临时目录，只能作为诊断输入。阶段 0 必须把需要长期保留的证据复制到 F 盘 evidence root，并记录 SHA-256；不得把 C 盘临时路径写成长期验收依赖。
6. 本方案不授权远程 push、公开发布、修改正式数据库、删除用户缓存或覆盖未识别的 MPQ。需要这些动作时必须另行取得明确授权。

## 1. 本轮目标与完成定义

本轮必须交付：

1. 外观页 11 个部位分类按钮在干净发布包中均有可见图标、选中态和 hover 状态，不再依赖未随包发布的 Retail 资源。
2. 悬浮收藏入口使用随基础 AddOn 发布的项目自有图标；没有可选媒体包时也不能只剩蓝色按钮底图。
3. 套装列表的滚轮、分页按钮、滑块拖动和页码保持同向：列表向下时滑块向下，第一页在顶部，最后一页在底部。
4. 套装预览使用干净角色基底，只穿当前选中 variant 实际包含的部件；上一套、玩家自身装备和套装未包含槽位不得残留。
5. 套装默认按资料片、团队层级、难度和物品等级排序；巫妖王之怒后期团队套装，尤其 ICC/T10 高难度版本，位于列表前部。
6. 把现有武器相机调节器改成不遮挡卡片的“镜头工作台”，支持武器类别、模型签名、单件外观三层覆盖，并能复制当前记录或批量导出本次全部修改。
7. 护甲外观页也能调节并导出镜头，但默认作用域为“客户端角色资产 profile + 性别 + 部位”，避免要求玩家逐件调整所有护甲。
8. 将现有 21 个已验证独立武器路线扩展为自动提取、去重、稳定 ID 分配和聚合打包流水线。所有具备可验证源 M2/SKIN/纹理的公开主副手外观都进入独立模型展示；真正缺失或不兼容的条目保留明确失败原因。
9. 干净 checkout、固定 evidence pack、生成目录、SoloCam、客户端资产包和发布 bundle 可重复构建，部署与回滚有逐文件 Hash 和备份清单。

本轮完成的判断标准：

- 基础 AddOn bundle 不包含任何“生产 UI 必需但包内不存在”的媒体路径；
- 11 个槽位图标、收藏入口和相关 fallback 在 stock 3.3.5 AddOn 环境可见；
- 套装第一页滑块位于顶部，向下滚动时滑块和列表同向；
- 任意套装切换后只显示该 variant 的展示成员，连续快速切换不串装；
- 465 个 active ItemSet 都有确定、稳定的展示排序字段；
- 当前 21 个武器零回归，镜头导出可 round-trip；
- 180 个角色相机 profile 可通过工作台生成差量并导出，未知 DLL/未知 profile 安全回退；
- 3,690 个公开主副手外观全部获得终态：`READY` 或带明确 `reasonCode` 的 `UNAVAILABLE`；不得继续依赖“只有 21 个 ID”这一硬编码上限；
- 所有可解析并验证资源的公开武器均为 `STANDALONE`，其余条目不得显示角色占位、空模型或错误 NPC；
- 真实客户端覆盖冷/热缓存、`/reload`、快速翻页、快速切换、不同分辨率/UI Scale 和 stock client 无 SoloCam fallback。

## 2. 当前基线与已确认事实

### 2.1 仓库与客户端基线

| 层 | 当前基线 | 本轮默认修改权限 |
|---|---|---|
| `SoloCollections` AddOn/目录/SoloCam 工作树 | `4ca746b`，分支 `codex/round-two-remediation` | 本轮主要修改层 |
| `mod-solo-collections` | `ac56258` | 默认不修改；只有展示字段被错误纳入服务端授权时才评估 |
| `azerothcore-wotlk` | `4cc67a316` | 不修改 |
| 真实客户端 | `D:\Games\wow335\World of Warcraft11` | 仅通过现有部署/备份工具安装与验证 |

实施开始前重新记录：

```powershell
$scAddonRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-addon'
$scModuleRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-module'
$scCoreRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-core'
git -C $scAddonRepo status --short --branch
git -C $scModuleRepo status --short --branch
git -C $scCoreRepo status --short --branch
```

任何已有用户修改都不属于本轮，不能覆盖、暂存或清理。若实施需要触碰与用户改动重叠的文件，应停止并报告冲突。

### 2.2 当前目录规模

| 指标 | 当前值 | 说明 |
|---|---:|---|
| canonical 外观 | 18,190 | 授权身份总目录 |
| `BODY` | 12,233 | 角色换装渲染 |
| `STANDALONE` | 21 | 全目录中已有独立武器 presentation |
| `UNAVAILABLE` | 5,936 | 主副手缺独立 presentation |
| 普通玩家可见外观 | 13,831 | `uiLifecycle=public` |
| 普通玩家可见主副手 | 3,690 | 本轮全量武器展示的 UI 分母 |
| 公开 `STANDALONE` | 20 | 主手 18、副手 2；另 1 条 verified presentation 非 public |
| 公开 `UNAVAILABLE` | 3,670 | 主手 2,943、副手 727 |
| ItemSet 原始审核单元 | 509 | DBC 分母 |
| active ItemSet | 465 | 当前生产套装目录 |
| 角色相机 profile | 180 | 10 原生种族 × 2 性别 × 9 部位 |

“3,690”是公开 UI 分母，不代表在提取前承诺 3,690 条都必然具有完整客户端源文件。正式成功分母必须由阶段 6 的资源提取报告得出；所有可验证资源必须转成 `READY`，缺失或不兼容资源必须给出稳定失败原因。

### 2.3 五类问题的精确根因

| 问题 | 代码/发布事实 | 根因 |
|---|---|---|
| 分类小图标不可见 | `UI.Media.wardrobeSlotAtlas` 和 `roundHighlightAtlas` 指向 `Media\Retail`；发布脚本排除整个目录；客户端实际没有该目录 | 基础 UI 错把可选外部媒体当成必需资源，测试只验证“被声明为 external”而不验证生产引用可用性 |
| 收藏按钮图标不可见 | `UI.Media.launcher` 指向被排除的 Retail BLP；项目已有 `Media\Icons\launcher.tga` 却未使用 | 同一媒体合同缺陷 |
| 绝大多数武器不显示 | `generate_catalog.py` 只给 presentation manifest 中 21 条标记 `STANDALONE`，其他主副手主动标记 `UNAVAILABLE`；验证器又要求 synthetic display 恰好为 `40000..40020` | 第二轮只恢复样本，未实现全量资源生成；不是随机加载失败 |
| 套装排序与残留装备 | ItemSet importer 不提取 item level/难度并按 ItemSetID 升序；`Catalog.QueryAll()` 不排序；预览 `SetUnit("player")` 后直接 `TryOn`，没有稳定后 `Undress()` | 展示排序元数据缺失；预览状态机以玩家装备为基底 |
| 套装滚动条反向 | `scSetOffset` 向下递增，但滑块同步和 `OnValueChanged` 都用 `maxOffset - value` | 对 3.3.5 垂直 Slider 方向判断错误，导致第一页滑块在底部 |

### 2.4 真实客户端失败基线

2026-07-22 使用 computer-use 在当前客户端复核：

- 外观槽位按钮保留点击区域，但图形为空；
- 悬浮收藏按钮只显示按钮底图；
- 套装第 `1/20` 页时滑块位于轨道底部；
- 向下滚动列表时滑块朝相反方向移动；
- “角斗士”等套装预览保留了套装未包含的肩、腰、武器等玩家装备；
- 公开武器页绝大多数条目显示明确 unavailable，只有既有调校样本能显示独立模型；
- 当前 286×351 镜头面板覆盖右侧约两列卡片。

阶段 0 应把这些现象重新采集为 F 盘固定基线，并记录客户端 build、AddOn commit、SoloCam DLL Hash、asset pack version、UI Scale、分辨率和时间。

## 3. 范围、非目标与强制不变量

### 3.1 本轮修改范围

- AddOn：`UI/Templates.lua`、`UI/Launcher.lua`、`UI/Wardrobe.lua`、`Core/Catalog.lua`、`Core/Bootstrap.lua`、`Core/M2Camera.lua` 及生成数据消费者。
- 目录工具：`appearance_presentations.py`、`generate_catalog.py`、`itemset_import.py`、`set_catalog.py`，以及本轮新增的媒体、套装展示顺序、武器 presentation 和镜头导入工具。
- SoloCam：角色相机 profile、物品相机 bridge、direct display bridge、生成表、native tests 和 x86 构建脚本。
- 客户端资产：M2/SKIN/BLP 转换、CreatureModelData/CreatureDisplayInfo DBC 投影、聚合 MPQ、manifest 和部署验证器。
- 发布工具：clean-checkout 媒体合同、asset pack manifest、bundle 安装/回滚和 installed verifier。
- 文档与证据：阶段报告、候选/排除报告、运行矩阵和最终实施方案勾选状态。

### 3.2 本轮明确不做

- 不建立第二套收藏 owned、revision、数据库或服务端动作后端。
- 不让 AddOn 提交 itemId、DisplayInfo ID、M2 路径或镜头参数来决定服务端收藏授权。
- 不用 `SetUnit("player") + TryOn`、NPC placeholder 或原生 `SetCreature(displayId)` 冒充独立武器模型。
- 不把全部 `UNAVAILABLE` 无条件改成 `STANDALONE`。
- 不为每件武器创建一个 MPQ，也不为重复模型复制一套相同 M2/SKIN/BLP。
- 不通过名称包含“冰冠”“英雄”等字符串来猜套装层级或难度。
- 不要求玩家逐件校准 3,690 件武器或 13,831 件护甲外观。
- 不导入高版本模型、正式服新资料片内容、HD 角色模型或新的游戏玩法。
- 不提交 Blizzard 提取资产、客户端 DLL/EXE、DBC、MPQ、WDB、数据库转储或凭据到 Git。
- 不修改 Core；若发现必须修改 Core 才能完成，应停止、记录证据并先修订方案。

### 3.3 强制不变量

1. **单一权威后端**：本轮字段全部属于展示平面，不改变 C++ 对 owned、revision、资格和动作的唯一权威。
2. **稳定身份**：canonical appearance collection ID、ItemSet collection ID 和 variantOrdinal 不变；展示 synthetic ID 使用追加式注册表，不重排、不复用。
3. **合法资源边界**：基础 AddOn 必须只依赖项目自有、获许可或 3.3.5 stock 路径。外部 Retail 媒体只能是可选覆盖，不能成为基础 UI 的隐式依赖。
4. **失败隔离**：单条武器、相机或媒体资源失败只影响该 presentation；不能阻止整个衣橱打开，也不能导致崩溃、黑模、NPC 或角色串入。
5. **可重建**：外部输入由 F 盘 evidence manifest 固定相对路径、大小和 SHA-256；生成器遇到 Hash 或 schema 漂移时 fail closed。
6. **可复制校准**：玩家导出的镜头记录必须携带身份和版本，不能只导出七个裸浮点数。
7. **真实客户端验收**：所有视觉阶段必须使用真实客户端；截图仅是证据，运行审计还需记录模型路径、状态、generation 和 Hash。
8. **无 C 盘输出**：构建、临时文件和证据放在 F 盘，既有客户端部署继续使用 D 盘；不得新增 C 盘工作目录。

## 4. 层边界与预期文件

| 层 | 责任 | 允许的变化 | 禁止承担的责任 |
|---|---|---|---|
| AddOn UI | 图标、过滤、网格、滚动、镜头工作台、导出文本 | UI 状态和只读展示参数 | 生成 M2/DBC、授权收藏、验证玩家 owned |
| AddOn Catalog adapter | 读取生成 presentation、排序展示记录 | 只读排序与 presentation 选择 | 修改 canonical identity 或服务器 mapping |
| Catalog generator | 联接 ItemDisplayInfo/ItemSet/审核/注册表，生成 Lua/C++ 投影 | 生成确定性元数据与报告 | 直接写客户端、从名称猜语义 |
| SoloCam DLL | direct display 和相机运行时覆写 | 解码已版本化私有请求、应用安全差量 | 收藏授权、任意路径加载、信任 Lua 传入磁盘路径 |
| 客户端资产构建 | 转换 M2 纹理类型、追加/复用相机、生成 DBC/MPQ | 根据固定 evidence 生成文件 | 修改源客户端文件、无备份覆盖现有 MPQ |
| Release/install | 媒体/资产/Hash/commit 验证，事务安装与回滚 | 复制已验证 bundle | 猜测冲突文件、递归删除缓存或客户端目录 |
| Module/Core | 保持现有收藏与动作语义 | 默认零变化 | 接收镜头 pose 或展示资源路径 |

预期新增或演进的源/生成文件：

```text
addon/SoloCollections/Media/Slots/*
addon/SoloCollections/Media/assets.json
catalog/source/overrides/weapon_camera_overrides.json
catalog/source/overrides/set_presentation_overrides.json
catalog/generated/weapon-presentation-candidates.json
catalog/generated/weapon-presentation-registry.json
catalog/generated/weapon-presentation-exclusions.csv
catalog/generated/set-presentation-order.json
catalog/review/weapons/review-policy.json
tools/catalog/weapon_presentations.py
tools/catalog/camera_tuning_import.py
tools/catalog/set_presentations.py
tools/collections/tests/test_weapon_presentations.py
tools/collections/tests/test_camera_tuning_import.py
tools/collections/tests/test_set_presentations.py
```

名称可在实施时按现有工具布局微调，但必须坚持“一份 canonical source/registry，多份生成投影”，不能同时保留两份可变生产事实源。

## 5. 目标数据与运行契约

### 5.1 基础媒体合同

`Media/assets.json` 从“文件 Hash 清单”升级为带消费语义的合同：

```json
{
  "schemaVersion": 2,
  "roles": {
    "launcher": {
      "path": "Icons/launcher.tga",
      "requiredForBaseUI": true,
      "width": 64,
      "height": 64
    },
    "wardrobeSlots": {
      "path": "Slots/wardrobe-slots.tga",
      "requiredForBaseUI": true,
      "width": 512,
      "height": 512
    }
  },
  "files": {},
  "optionalExternalFiles": {}
}
```

规则：

- `requiredForBaseUI=true` 的路径必须被 Git 跟踪、进入干净 bundle、Hash 一致并能由 3.3.5 读取；
- production Lua 默认引用不得只由 `optionalExternalFiles` 满足；
- launcher 直接使用现有项目自有 `Media\Icons\launcher.tga`；
- 11 个槽位使用新项目自有图标或经审计的 3.3.5 stock texture，不再默认引用 `Media\Retail`；
- `mountPortrait` 等相邻引用一并审核，防止同类空白留到下一轮；
- 外部媒体包若继续保留，只能覆盖明确的 skin 角色，缺失时基础 UI 不变；
- release verifier 必须扫描 Lua 中的 AddOn media 引用并与“实际 bundle 文件表”比较，不能仅因为路径声明为 external 就放行。

### 5.2 武器 presentation 与稳定资源注册表

每个公开主副手 canonical appearance 生成一条候选：

```json
{
  "schemaVersion": 1,
  "appearanceId": 200001,
  "collectionKey": "appearance.example",
  "sourceItemId": 12345,
  "nativeDisplayId": 6789,
  "slot": "MAINHAND",
  "weaponType": "TWO_HAND_SWORD",
  "sourceModelPath": "Item/ObjectComponents/Weapon/example.m2",
  "sourceSkinPath": "Item/ObjectComponents/Weapon/example00.skin",
  "sourceTexturePaths": ["Item/ObjectComponents/Weapon/example.blp"],
  "geometryKey": "sha256-or-normalized-source-key",
  "textureKey": "sha256",
  "displayKey": "geometry+texture+flags",
  "modelSignature": "stable-model-signature",
  "syntheticModelId": 50000,
  "syntheticDisplayId": 40021,
  "renderMode": "STANDALONE",
  "presentationStatus": "ready",
  "reasonCode": "",
  "cameraTuningKey": "TWO_HAND_SWORD",
  "autoCamera": {},
  "assetHashes": {}
}
```

规则：

- 现有 21 个 `sourceItemId -> syntheticDisplayId 40000..40020` 映射逐项保留；
- 新 synthetic model/display ID 只追加，不因排序、重建或条目隐藏而变化；
- `geometryKey` 至少包含规范化源 M2、源 SKIN 和转换器版本；
- `textureKey` 使用内容 SHA-256，而不是只用文件名；
- `displayKey` 由几何、纹理、必要渲染 flags 组成；相机 pose 不进入 DBC display 去重键；
- 同源 M2 只生成一份转换后几何；同 Hash 纹理只写一份；相同 displayKey 复用 `CreatureDisplayInfo`；
- AddOn 不再验证 `40000 <= syntheticDisplayId <= 40020`，而是验证 manifest/registry 中的合法 ID 和 renderer 能力；
- `DisplayInfoBridge` 保留 `0x00FFFFFF` 上限和请求 base，不改变原生 `SetCreature` 语义；
- 对无法解析的记录生成固定 `reasonCode`，例如 `NO_ITEM_DISPLAY_INFO`、`NO_MODEL_PATH`、`NO_SKIN`、`NO_TEXTURE`、`UNSUPPORTED_TEXTURE_LAYOUT`、`UNSUPPORTED_CAMERA_LAYOUT`、`ASSET_HASH_MISMATCH`；
- 失败记录仍保留 canonical owned 和图标展示，不降级为角色 TryOn。

### 5.3 武器镜头覆盖与导出合同

运行时优先级固定为：

```text
appearance override
  > modelSignature override
  > weaponFamily preset
  > M2 bounds auto-fit
```

SavedVariables 目标结构：

```lua
cameraTuning = {
    schemaVersion = 2,
    weaponFamily = {},
    model = {},
    appearance = {},
    bodyProfile = {},
}
```

规则：

- legacy `m2CameraTuning` 只迁移到 `weaponFamily`；迁移成功前不删除原表；
- 键使用稳定字符串，如 `family:TWO_HAND_SWORD`、`model:<signature>`、`appearance:<collectionId>`；
- 只保存玩家实际修改过的覆盖，不为 3,690 条预先写 SavedVariables；
- 每次导出包含 schemaVersion、scope、appearanceId、sourceItemId、nativeDisplayId、syntheticDisplayId、modelSignature、weaponType、slot、pose、metadataVersion、assetPackVersion 和 presentation hash；
- 批量导出一行一条记录，第一行包含版本/Hash header；同一键只导出最后值；
- AddOn 不能直接写系统剪贴板。按钮将 EditBox 聚焦并全选，玩家用 `Ctrl+C` 复制；
- `camera_tuning_import.py` 能读取导出文本、验证版本/身份/范围、拒绝重复冲突，并把批准记录写入 canonical override source；
- 任何来自玩家的记录都只进入待审核文件，不能在未验证模型身份和 asset version 时自动成为生产默认。

### 5.4 护甲/角色相机差量合同

护甲默认调整作用域：

```text
clientAssetProfile + sex + slot
```

字段：

```json
{
  "kind": "bodyProfile",
  "profileKey": "human:female:CHEST",
  "sentinel": 21315,
  "verticalOffsetDelta": 0.0,
  "horizontalOffsetDelta": 0.0,
  "distanceScaleMultiplier": 1.0,
  "minimumDistanceDelta": 0.0,
  "yawOffsetDelta": 0.0,
  "cameraProfileVersion": 1,
  "cameraProfileHash": "..."
}
```

规则：

- 差量相对于已生成的 180 条 profile，不复制整表；
- AddOn 在选中护甲卡片时显示当前 profile 范围，例如“人类 / 女性 / 胸部”，避免用户误认为只调整这一件胸甲；
- 角色相机请求使用新的已版本化 SoloCam 私有命令族；具体数值区间由冲突检查器分配，不在方案中手猜常量；
- 请求必须与现有 sentinel、item-camera request、direct-display request 互不冲突；
- DLL 缺失、命令版本不支持或 profile hash 不匹配时，保持现有 sentinel + camera 1 安全回退；
- 模型池复用、页面隐藏或切换记录时清除 pending override，禁止上一张卡片差量串到下一张；
- 第一轮不建立逐护甲 appearance override。只有 profile 级调整无法解决、且有重复实机证据的异常肩部/披风，才另立后续例外合同。

### 5.5 套装展示排序合同

为每个 active ItemSet 生成只读 presentation：

```json
{
  "itemSetId": 901,
  "collectionId": 300464,
  "expansionKey": "WRATH",
  "expansionRank": 3,
  "contentTierKey": "ICC_T10",
  "contentTierRank": 10,
  "difficultyKey": "HEROIC_25",
  "difficultyRank": 4,
  "itemLevelMin": 277,
  "itemLevelMax": 277,
  "itemLevelMedian": 277,
  "acquisitionRank": 100,
  "sourceKind": "RAID_TOKEN",
  "sortKeyVersion": 1
}
```

默认比较器：

```text
expansionRank DESC
contentTierRank DESC
difficultyRank DESC
itemLevelMax DESC
acquisitionRank DESC
itemSetId ASC
```

规则：

- importer 从 `item_template` 增加 `ItemLevel`、`Quality` 和必要的稳定字段；
- 团本层级、难度和获取方式来自审核后的 override/evidence，不从名称字符串推断；
- 不能可靠确定的记录使用显式 `UNKNOWN` 和最低 rank，并进入审核报告；
- 排序字段只进入 presentation hash，不进入服务端 owned/mapping hash；
- `set_catalog.py` 把字段投影到 AddOn；C++ set action 不需要消费排序字段；
- UI 默认采用“推荐排序”，后续可增加“名称/等级/收集进度”选项，但本轮不以额外排序 UI 阻塞默认修复。

### 5.6 套装预览成员合同

- 预览来源必须是 `record.selectedVariant.members`，不能继续盲用 default `record.itemIds`；
- 每个成员生成或选择确定的 `previewSourceItemId`；同一输入重复生成必须一致；
- 只对当前 active variant 中 `previewEnabled ~= false` 的成员调用 TryOn；omission、其他 variant、玩家装备和上一套装备不得进入；
- `SetUnit("player")` 只用于获得当前种族/性别身体，不得把玩家装备作为预览基底；
- 状态机顺序固定为：增加 generation → ClearModel → SetUnit → 等待模型稳定 → Undress → 按稳定槽位顺序 TryOn 当前成员 → 等待 settle → 应用模型视图；
- 快速切换时旧 generation 的异步回调全部丢弃；
- 模型隐藏/页面切换时清空 pending items、generation、drag/zoom 和临时回调。

### 5.7 滚动条映射合同

```text
sliderMin = 0
sliderMax = maxOffset
sliderValue = scSetOffset
```

- 第一条记录：offset 0，滑块顶部；
- 向下滚一行：offset +1，滑块向下；
- 最后一页：offset maxOffset，滑块底部；
- 拖动滑块：`scSetOffset = round(value)`；
- 上滚轮 `delta > 0`：offset -1；下滚轮 `delta < 0`：offset +1；
- 分页按钮按 `VISIBLE_SET_ROWS` 增减 offset；
- 过滤后 clamp offset，空列表回到 0；
- 所有输入路径最终调用同一个 `setSetOffset()`，避免页码、滑块和列表分别维护状态。

## 6. 阶段 0：冻结证据与建立红测试

阶段目标：把当前五类问题变成可重复失败的自动化/实机基线，在任何修复前固定输入、版本和回滚点。

### 任务 0.1：记录仓库、生成目录和部署状态

- [x] 记录 AddOn/module/Core commit、分支、dirty 状态和未跟踪文件；确认不覆盖用户修改。（2026-07-22；`evidence-manifest.json` 的 `repositories`）
- [x] 记录 `metadataVersion`、`assetPackVersion`、appearance presentation hash、camera profile hash、set mapping/presentation hash。（2026-07-22；`evidence-manifest.json` 的 `catalog`）
- [x] 记录部署 AddOn、SoloCam DLL、MPQ、locale DBC patch、worldserver 的相对路径、大小和 SHA-256。（2026-07-22；`evidence-manifest.json` 的 `deployments`）
- [x] 在 F 盘建立本轮 evidence root 和 `evidence-manifest.json`，只使用相对路径。（2026-07-22；`F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set`）

### 任务 0.2：固定媒体失败

- [x] 导出干净 bundle 文件清单，证明 `Media\Retail` 不存在而 production Lua 仍引用相关路径。（2026-07-22；同 commit clean bundle 36 个 AddOn 文件、Retail 目录为 0，`mediaFailureBaseline`）
- [x] 增加红测试：任何 `requiredForBaseUI` 或 production 默认引用不能只由 external 声明满足。（2026-07-22；`test_wardrobe_camera_set_contract.py`，修复前失败）
- [x] 增加红测试：release bundle 必须包含所有基础媒体角色指向的文件。（2026-07-22；同一合同的 bundle tool 断言，修复前失败）
- [x] 记录 11 个槽位按钮和 launcher 的真实客户端失败截图。（2026-07-22；`stage0-missing-wardrobe-slot-icons.jpg`、`stage0-missing-launcher-icon.jpg`）

### 任务 0.3：固定套装失败

- [x] 增加滚动映射单元测试：offset 0 对应 slider value 0，maxOffset 对应 maxOffset。（2026-07-22；`test_set_scroll_uses_a_direct_offset_slider_mapping`，修复前失败）
- [x] 增加滚轮/分页/拖动经过同一状态函数的合同测试。（2026-07-22；`test_set_scroll_inputs_share_the_single_offset_state_transition`）
- [x] 增加套装预览红测试：`preparePlayerModel` 后必须在 TryOn 前进入 Undress 状态。（2026-07-22；`test_set_preview_is_generation_aware_and_undresses_before_tryon`，修复前失败）
- [x] 增加 selectedVariant 测试：预览成员来自 selected variant，不来自旧 default itemIds。（2026-07-22；`test_set_preview_uses_only_the_selected_variant_members`，修复前失败）
- [x] 保存第一页滑块位于底部、向下滚动滑块反向、套装残留装备的实机证据。（2026-07-22；`stage0-set-scroll-reversed.jpg`、`stage0-set-preview-player-gear-residual.jpg`）

### 任务 0.4：固定武器与镜头基线

- [x] 生成当前全目录和公开目录的 BODY/STANDALONE/UNAVAILABLE 统计，固定 21/5,936 与公开 20/3,670 基线。（2026-07-22；`catalog.appearanceStatistics`）
- [x] 固定现有 21 个 synthetic ID、源 item、M2/SKIN/BLP Hash、camera key 和 pose。（2026-07-22；`catalog.verifiedStandaloneWeapons`）
- [x] 增加红测试：standalone validator 不得再把合法 ID 集合硬编码为恰好 `40000..40020`。（2026-07-22；`test_standalone_validation_is_registry_based_not_a_fixed_21_id_range`，修复前失败）
- [x] 增加红测试：单件 appearance override 必须优先于 family pose。（2026-07-22；`test_weapon_camera_resolves_appearance_then_model_then_family_then_auto`，修复前失败）
- [x] 保存镜头面板遮挡卡片和类别级调整无法单件覆盖的实机证据。（2026-07-22；`stage0-camera-panel-overlays-cards.jpg`）

### 任务 0.5：阶段出口

- [x] 所有当前问题都有至少一个自动红测试或稳定的运行断言。（2026-07-22；10 项合同中 9 项修复前失败，另 1 项固定既有统一输入行为）
- [x] evidence manifest 不含凭据、绝对源路径、客户端资产正文或数据库转储。（2026-07-22；生成器与复核命令均 fail closed）
- [x] 生成当前失败基线报告 `docs/reports/2026-07-22-wardrobe-camera-set-baseline.md`。（2026-07-22）
- [x] 创建本地可回滚基线 tag；不 push。（2026-07-22；`round3-wardrobe-camera-set-baseline-20260722` → `4ca746b`）

## 7. 阶段 1：修复基础媒体与发布合同

阶段目标：先关闭图标回归，使干净 AddOn bundle 在没有外部 Retail 媒体时仍完整可用。

### 任务 1.1：确定项目自有槽位图标方案

- [x] 为 HEAD、SHOULDER、BACK、CHEST、WRIST、HANDS、WAIST、LEGS、FEET、MAINHAND、OFFHAND 制作或选用 11 个可再发布图标。（2026-07-22：`bdbd597`，见阶段 1 报告。）
- [x] 若使用新图集，固定尺寸、TexCoord、alpha、颜色空间和 SHA-256；若使用逐图标文件，固定每个角色路径和尺寸。（2026-07-22：`bdbd597`。）
- [x] 确认选中环和 hover 高亮使用项目自有/stock 资源，不引用可选 Retail atlas。（2026-07-22：`bdbd597`。）
- [x] 更新 `Media/assets.json` provenance，明确每个基础文件来源和许可状态。（2026-07-22：`bdbd597`。）

### 任务 1.2：修复生产媒体引用

- [x] `UI.Media.launcher` 改用已跟踪的 `Media\Icons\launcher.tga`。（2026-07-22：`bdbd597`。）
- [x] `wardrobeSlotAtlas`/逐槽图标改用基础 bundle 内项目自有资源。（2026-07-22：`bdbd597`。）
- [x] `roundHighlightAtlas` 改用基础 bundle 内项目自有或 stock 资源。（2026-07-22：`bdbd597`。）
- [x] 审计 `mountPortrait` 和其他 `UI.Media` 字段，消除相同的隐式 external 依赖。（2026-07-22：`bdbd597`。）
- [x] 保留可选外部媒体只作为明确 skin 覆盖，不影响默认可见性。（2026-07-22：`bdbd597`。）

### 任务 1.3：强化媒体与 release 测试

- [x] `test_media_contract.py` 区分 `requiredForBaseUI` 与 `optionalExternalFiles`。（2026-07-22：`bdbd597`。）
- [x] 增加 production Lua 引用扫描：默认引用 external-only 路径时 fail。（2026-07-22：`bdbd597`。）
- [x] `New-RoundTwoBundle.ps1` 生成 bundle 后重新扫描 AddOn 媒体引用和实际文件。（2026-07-22：`bdbd597`。）
- [x] `Test-RoundTwoBundle.ps1` 对基础媒体逐文件验证 Hash、尺寸和文件类型。（2026-07-22：`bdbd597`。）
- [x] 从干净 checkout 构建 AddOn，确认不依赖开发机本地 `Media\Retail`。（2026-07-22：`bdbd597`。）

### 任务 1.4：真实客户端验收

- [x] 11 个槽位图标全部可见、可点击、tooltip 正确。（2026-07-22：`stage1-slots-fresh-client.jpg`、`stage1-slot-tooltip-verified.jpg`。）
- [x] selected、hover、未选中状态互不覆盖，图标不模糊、不越界。（2026-07-22：`stage1-slot-selected-hover.jpg`。）
- [ ] launcher 在 normal、hover、drag 后和 `/reload` 后均可见。
- [ ] 1024×768 到 3440×1440 的既有 UI Scale 矩阵至少抽查窄屏、1080p、超宽三档。
- [ ] 没有外部媒体包时验收通过；安装可选媒体覆盖时不得破坏基础 UI。

### 任务 1.5：阶段出口

- [x] 媒体红测试全部转绿。（2026-07-22：`test_media_contract.py` 5/5。）
- [x] clean bundle 中不存在缺失的基础媒体引用。（2026-07-22：`round3-media-clean-20260722T222620`。）
- [x] 真实客户端截图与运行记录存入 F 盘 evidence，并生成阶段报告。（2026-07-22：`2026-07-22-wardrobe-base-media-contract.md`。）
- [ ] 在本文勾选任务并记录提交；本阶段不修改 module/Core。

## 8. 阶段 2：修复套装滚动与干净试穿

阶段目标：在不改变 ItemSet 身份、owned、variantOrdinal 或服务端 APPLY 的前提下，修正列表交互和预览状态。

### 任务 2.1：统一滚动状态

- [ ] 删除 `maxOffset - value` 双向反转，Slider value 与 `scSetOffset` 直接对应。
- [ ] 滚轮、分页按钮、滑块拖动、过滤重置全部调用同一 `setSetOffset()`。
- [ ] 修正过滤/搜索后 offset clamp、页码和选中记录同步。
- [ ] 空列表、单页、刚好一页、多页、最后残页全部覆盖。

### 任务 2.2：实现套装预览 generation 状态机

- [ ] `previewSet()` 每次选择增加 `scSetPreviewGeneration`。
- [ ] `ClearModel`、`SetUnit` 后等待模型路径稳定至少两个 render tick，再调用 `Undress()`。
- [ ] 从 `selectedVariant.members` 构造当前预览列表，按稳定槽位顺序 TryOn。
- [ ] 旧 generation、旧 OnUpdateModel 和延迟 item cache callback 不得影响新选择。
- [ ] 页面隐藏、切回物品 tab、角色/性别变化时清理 pending state。
- [ ] 保留旋转、缩放和重置交互，但切换套装时恢复已定义的默认视图。

### 任务 2.3：明确预览成员选择

- [ ] 为 member 生成或选择稳定 `previewSourceItemId`，不依赖 `GetItemInfo` 返回顺序。
- [ ] 只穿当前 variant 中允许展示的 members；omissions 和其他 variant 不参与。
- [ ] 处理两件同槽 alternative：只选一个确定 preview source，不能同槽连续 TryOn 多件造成结果依赖调用顺序。
- [ ] 预览选择逻辑与 APPLY 的 owned alternative 逻辑分离；预览不伪装为服务端实际选择。

### 任务 2.4：自动测试

- [ ] offset/value 双向 round-trip。
- [ ] 上/下滚轮方向、分页步长、拖动和 clamp。
- [ ] selected variant 与 default variant 不同的 synthetic fixture。
- [ ] 连续 A→B→A 套装选择时 generation 只保留最终 A。
- [ ] 玩家装备包含套装未含肩、腰、武器时，最终调用序列先 Undress 再只 TryOn 套装成员。
- [ ] Lua 5.1 语法和现有 set action 合同无回归。

### 任务 2.5：真实客户端验收

- [ ] 第 1 页滑块顶部，第 20/20 或最后一页滑块底部。
- [ ] 向下滚动时列表与滑块同时向下，向上同理。
- [ ] 拖动到中部时页码、记录和滑块一致；滚轮接管后无跳变。
- [ ] 选择 2、3、5、8、9 件套，模型只穿套装包含部位。
- [ ] 玩家预先装备肩、衬衣、战袍、腰带、武器后再预览，未包含槽位全部清空。
- [ ] 快速连续点击至少 20 个套装，无上一套残留、空模或 Lua error。

### 任务 2.6：阶段出口

- [ ] 滚动和预览红测试全部转绿。
- [ ] 465 个 active 套装完成自动快速切换扫描，零 generation 串装。
- [ ] 真实客户端证据与阶段报告完成。
- [ ] 本阶段只修改 AddOn/生成 presentation；module/Core 零变化。

## 9. 阶段 3：建立套装等级、难度与获取排序

阶段目标：为 465 个 active ItemSet 建立可审核的展示排序，使 ICC/T10 等后期高难度套装默认位于列表前部。

### 任务 3.1：扩展 ItemSet evidence

- [ ] `itemset_import.py` 查询加入 `ItemLevel`、`Quality` 和排序所需稳定字段。
- [ ] 更新 snapshot canonical hash；旧 evidence pack 不满足新 schema 时 fail closed。
- [ ] 为每套聚合 min/max/median item level，并记录成员缺失或等级不一致。
- [ ] 不把 item level 加入 canonical identity 或 owned mapping basis。

### 任务 3.2：建立 presentation 审核表

- [ ] 新建套装 presentation override/review source，覆盖 509 个审核单元或明确继承规则。
- [ ] 为 Classic/TBC/Wrath、PvE/PvP、主要团队层级和难度定义稳定 enum/rank。
- [ ] ICC/T10、ToC/T9、Ulduar/T8、Naxx/T7 等通过 item/source 证据映射，不通过中文/英文名称猜测。
- [ ] 无法确定层级或获取方式的条目标记 `UNKNOWN`，进入 exclusions/review report，不伪造精度。
- [ ] 旧 8 套和新增 457 套身份、成员、classPolicy、variantOrdinal 零漂移。

### 任务 3.3：生成与消费排序字段

- [ ] 新增 `set_presentations.py` 或等价单一生成器，输出 JSON/CSV 审核报告和 presentation hash。
- [ ] `set_catalog.py` 把排序字段投影到 AddOn `Data/Sets.lua`。
- [ ] `Catalog.QueryAll("SETS")` 使用固定比较器；相同 rank 使用稳定 ItemSetID tie-breaker，显示语言不影响顺序。
- [ ] 排序只改变 UI 顺序，不改变 C++ set collection 表或 APPLY 语义。
- [ ] 搜索、职业过滤、收藏过滤后继续保持同一比较器。

### 任务 3.4：测试与验收

- [ ] 465 条 active set 都有完整 presentation 或明确 UNKNOWN；不得缺记录。
- [ ] 生成器重复运行 byte-for-byte 稳定。
- [ ] presentation 字段变化不改变 set mapping hash，必须改变 set presentation hash。
- [ ] ICC/T10 fixture 排在 ToC/T9、Ulduar/T8、Naxx/T7 和低等级旧资料片套装之前。
- [ ] 同层级英雄/高难度版本排在普通版本之前；item level/tie-breaker 稳定。
- [ ] 真实客户端职业过滤下第一页出现当前职业的后期 Wrath 团本套装。
- [ ] `/reload`、重登、不同职业角色顺序一致。

### 任务 3.5：阶段出口

- [ ] 509 个 review units 的 presentation 决定闭合。
- [ ] 465 active 套装排序、搜索、过滤和页码实机通过。
- [ ] mapping hash/owned/variantOrdinal 零变化证据完成。
- [ ] 生成阶段报告并勾选本阶段所有任务。

## 10. 阶段 4：重构武器镜头工作台与批量导出

阶段目标：先在现有 21 个 verified 武器上完成可用、可复制、可扩展的调参工作流，再用于全量武器。

### 任务 4.1：SavedVariables schema 与迁移

- [ ] 在 `Bootstrap.lua` 增加 `cameraTuning.schemaVersion=2` 结构与值域修复。
- [ ] 将 legacy `m2CameraTuning` 字符串 family key 复制到 `weaponFamily`；保留 legacy 备份至少一个稳定版本。
- [ ] model/appearance/bodyProfile 使用稳定字符串键；拒绝 NaN、Infinity、超界值和未知 scope。
- [ ] 未修改记录不写入 SavedVariables；迁移后文件大小有上限测试。

### 任务 4.2：实现层级解析

- [ ] `getEffectiveM2CameraPose()` 按 appearance > model > family > auto 顺序解析。
- [ ] generator 为每个 standalone record 提供 `modelSignature` 和 `autoCamera`。
- [ ] 同一模型不同纹理默认共享 model override；单件异常用 appearance override。
- [ ] family 修改可实时应用到所有使用该 family 且没有更高层 override 的可见卡片。
- [ ] 重置只删除当前 scope，不误删其他层。

### 任务 4.3：重做工作台布局

- [ ] 将当前 DIALOG 浮层改成主窗口内固定右侧检查器；打开时物品网格从 6 列重排为 4 列或按可用宽度动态计算。
- [ ] 检查器不覆盖卡片、页码、Items/Sets tab、武器 dropdown 或窗口关闭按钮。
- [ ] “镜头工作台”按钮放在过滤工具栏明确位置，显示打开/关闭状态。
- [ ] 1024×768 下检查器完整可见；不得锚到主窗体外导致裁切。
- [ ] 关闭工作台后恢复 6×3 固定模型池和原分页，不销毁/重建不必要模型。

### 任务 4.4：改进调参交互

- [ ] 增加 scope 选择：“武器类别 / 此模型 / 此外观”。
- [ ] 每项同时提供 Slider、数值 EditBox、细调和粗调；输入后 clamp 并即时预览。
- [ ] 保留 yaw、pitch、roll、distanceScale、target XYZ 七项。
- [ ] 显示当前 appearanceId、itemId、native/synthetic display、modelSignature、family 和最终生效来源。
- [ ] 增加“上一条/下一条”“上一条未校准/下一条未校准”和当前 dirty 状态。
- [ ] unavailable 武器禁用调参并显示具体资源失败原因，不能让玩家调整看不见的模型。

### 任务 4.5：导出与导入工具

- [ ] “复制当前”生成一条带完整身份和版本的记录并全选 EditBox。
- [ ] “加入批次”把当前 dirty override 放入去重批次。
- [ ] “复制本次全部修改”生成 header + 多行记录，顺序稳定。
- [ ] “重置当前层”只删除当前 scope；另提供明确确认的“放弃本次未导出修改”。
- [ ] 新增 `camera_tuning_import.py` 验证并转换导出文本为审核候选。
- [ ] 导入器检查 appearance/model/family 对应关系、assetPackVersion、presentation hash、pose 范围和重复冲突。

### 任务 4.6：现有 21 武器验收

- [ ] 21/21 旧 pose 在无 override 时逐值零漂移。
- [ ] family 修改影响同类样本；model override 只影响同模型；appearance override 只影响单件。
- [ ] 导出→导入→生成→清空 SavedVariables 后，最终 pose 与原调校一致。
- [ ] 工作台打开/关闭、翻页、换武器类型、切 Items/Sets、`/reload` 无遮挡和状态串扰。
- [ ] 导出文本能由玩家实际 `Ctrl+C` 复制，并能在 F 盘导入工具解析。

### 任务 4.7：阶段出口

- [ ] 当前 21 个 verified 武器零视觉回归。
- [ ] 工作台布局通过窄屏/1080p/超宽抽查。
- [ ] 三层覆盖、批量导出和 round-trip 自动/实机测试通过。
- [ ] 生成阶段报告；在全量武器管线完成前不扩大 production `STANDALONE`。

## 11. 阶段 5：为护甲开放角色相机校准与导出

阶段目标：让玩家在护甲卡片上调整现有 180 条角色相机 profile 的差量，并导出可合并记录，而不是逐件调整护甲。

### 任务 5.1：分配和验证 SoloCam 私有协议

- [ ] 为 body-camera delta 分配版本化命令族，自动检查与 180 sentinel、item camera、direct display base 的区间冲突。
- [ ] 定义 vertical、horizontal、distanceScale、minimumDistance、yaw 五项编码精度、范围和失败语义。
- [ ] 未完成全部命令或激活请求时不得应用半套 pose。
- [ ] 未知命令/version/profile hash 安全失败，不影响原生 camera 1 fallback。

### 任务 5.2：SoloCam 运行时实现

- [ ] 在每个模型实例上跟踪 pending body override，不能使用跨模型全局可变 pose。
- [ ] 相机生成以 canonical profile 为基础应用 delta，并验证有限数和正距离。
- [ ] 模型更新、SetUnit/TryOn 异步重建后按 generation 重新应用同一 profile。
- [ ] 模型隐藏、池复用、切换 renderer 时清除 override。
- [ ] 新增 native tests 覆盖解码边界、profile 应用、未知值、清理和 180 profile 回归。

### 任务 5.3：AddOn 工作台集成

- [ ] BODY 记录选中时工作台切换为角色 profile 模式，显示 race asset profile、sex、slot、sentinel 和 profile hash。
- [ ] 调节项使用角色相机五字段，不显示武器专用 pitch/roll/target XYZ。
- [ ] 同 profile 的可见护甲卡片实时更新；其他种族/性别/部位不受影响。
- [ ] 导出记录包含 profileKey、sentinel、base version/hash 和 delta。
- [ ] DLL 不支持时工作台显示“只读/需 SoloCam 新版本”，普通预览继续使用安全 fallback。

### 任务 5.4：审核与合并流程

- [ ] 导入器把 body profile 导出写入待审核候选，不直接覆盖 `camera_profiles.json`。
- [ ] 审核脚本可生成 base vs proposed 差异、幅度和受影响 profile 列表。
- [ ] 通过批准的 delta 合并回 canonical override 后重新生成 Lua/C++ 双投影和 profile hash。
- [ ] human/female 既有九项无批准 override 时逐值不变。

### 任务 5.5：180 profile 实机矩阵

- [ ] 先验收 HEAD/CHEST/FEET 三个锚点，再覆盖全部九部位。
- [ ] 每个 profile 至少使用小型、普通、大型轮廓代表物品检查裁切。
- [ ] 导出至少一条 profile 调整，完成 round-trip 后清空 SavedVariables 验证结果一致。
- [ ] 快速切换种族/性别/槽位或重新登录时不串 profile。
- [ ] stock client 无新 DLL 时不崩溃、不无限缩放，回退 camera 1。

### 任务 5.6：阶段出口

- [ ] 180/180 profile 的基础预览零回归。
- [ ] 至少一条每种字段类型的 delta 完成导出、审核、合并和重建闭环。
- [ ] AddOn/DLL/profile manifest 版本与 Hash 一致。
- [ ] 生成阶段报告和更新后的 runtime matrix。

## 12. 阶段 6：建立全量武器资源提取与审核 shadow

阶段目标：在不切换生产目录和不部署新 MPQ 的情况下，为 3,690 个公开主副手建立完整候选、资源解析、去重和稳定 ID 计划。

### 任务 6.1：固定客户端输入

- [ ] evidence pack 固定 Item.dbc、ItemDisplayInfo.dbc 及所需关联 DBC 的 build、locale、大小和 SHA-256。
- [ ] 固定当前客户端 MPQ 文件清单和每个源 archive Hash；只记录允许的清单/解析产物，不提交资产正文。
- [ ] 固定 World `item_template` 中 source item → displayid/InventoryType/ItemLevel 等脱敏快照 Hash。
- [ ] 生成器只接受命名 evidence root，不从开发者任意客户端路径隐式读取。

### 任务 6.2：解析 ItemDisplayInfo 和源资产

- [ ] 从 canonical appearance 的 source item/displayId 解析 left/right model、texture 和 inventory side。
- [ ] 主手、副手、盾牌和 held-in-offhand 分别路由；盾牌不能盲用普通 Weapon 路径。
- [ ] 解析 M2、对应 SKIN、replaceable texture lookup 和实际 BLP；支持共享纹理。
- [ ] 记录 item visual/effect 信息，即使本轮不完全重建特效，也不能静默丢失事实。
- [ ] 对 camera-less、已有 camera、异常 camera layout 分别判定；不无条件重复追加 camera 0。
- [ ] 每个失败候选生成稳定 reasonCode 和具体缺失相对路径。

### 任务 6.3：建立去重键和追加式注册表

- [ ] 计算 geometryKey、textureKey、displayKey、modelSignature。
- [ ] 把现有 21 条注册表作为不可变保留区导入，逐项验证 Hash 和 ID。
- [ ] 相同 geometryKey 复用生成 M2/SKIN；相同 texture Hash 复用 BLP；相同 displayKey 复用 display row。
- [ ] 为新 geometry/display 追加分配未冲突 model/display ID；重复生成稳定。
- [ ] tombstone 保留旧 ID，不因条目改为 hidden/unavailable 而回收。

### 任务 6.4：生成相机自动基线

- [ ] 复用现有 M2 bounding box 中心、radius 和 minimum distance 算法。
- [ ] 增加 extents/长轴/宽高比分类，区分长柄、短刃、盾牌、书本/副手、远程武器。
- [ ] 以现有 18 个 WotLK 武器 family pose 作为 family preset，不把单一样本 pose 烘焙给所有模型。
- [ ] 为几何异常值生成 outlier 报告：极端长宽比、超大 radius、近零 bounds、非有限值。
- [ ] 自动相机只生成 baseline；人工覆盖继续走阶段 4 的层级合同。

### 任务 6.5：审核报告与 shadow 闸门

- [ ] 输出 3,690 条公开候选的 READY/UNAVAILABLE 统计、reasonCode 分布和资源去重比例。
- [ ] 输出全 5,957 主副手 canonical 的 shadow 报告，区分 public 与非 public，不混淆分母。
- [ ] 每条候选都有唯一终态；不允许 missing decision。
- [ ] 随机抽取和按武器 family 分层抽取源路径，人工核对 ItemDisplayInfo 与提取资源。
- [ ] shadow 阶段不修改 `appearance_presentations.json` production 投影，不部署 DBC/MPQ。

### 任务 6.6：阶段出口

- [ ] 3,690/3,690 公开武器候选全部有终态。
- [ ] 现有 21 个 ID/资源/pose 零漂移。
- [ ] 去重注册表重复生成 byte-for-byte 稳定。
- [ ] READY 分母、UNAVAILABLE 原因和预计资产体积经人工审核后记录；未达到该出口不得开始批量部署。

## 13. 阶段 7：批量生成、去重并打包武器客户端资源

阶段目标：把阶段 6 的 READY 候选转换为可部署的聚合 M2/SKIN/BLP、DBC 和 manifest，分批验证后再全量切换。

### 任务 7.1：重构资产构建器

- [ ] `build_creature_weapon_assets.py` 从手写 21 配置升级为读取生成 registry。
- [ ] 构建器按 geometry/texture/display cache 只写唯一资源。
- [ ] OBJECT_SKIN→MONSTER_SKIN_1 转换、camera 处理和纹理 lookup 均带 converter version。
- [ ] 每个输出先写临时文件，再原子替换；构建失败不留下半文件。
- [ ] 输出逐文件 SHA-256、源键、目标相对路径、DBC row 和引用 appearance 列表。

### 任务 7.2：DBC 和 direct-display 验证

- [ ] CreatureModelData/CreatureDisplayInfo 追加行不覆盖 baseline ID。
- [ ] model/display ID 唯一、引用存在、字段布局和字符串表合法。
- [ ] `syntheticDisplayId <= 0x00FFFFFF`，加 request base 后不溢出且不进入其他保留区。
- [ ] AddOn、registry、DBC、SoloCam bridge 对同一 synthetic ID 一致。
- [ ] stock client 不认识 synthetic DBC/无 SoloCam 时安全显示 unavailable，不尝试原生错误 Creature entry。

### 任务 7.3：聚合 MPQ 与碰撞处理

- [ ] 所有生成武器资源进入一个聚合客户端 patch，locale DBC 进入一个 locale patch；不得每件一个 MPQ。
- [ ] 构建前识别目标同名 MPQ 是否由 SoloCollections 管理；未知所有者时停止，不覆盖。
- [ ] 若集成客户端同名包承载其他资源，使用受审计 merge 流程或经验证的新 patch 名；不盲目 `Copy-Item -Force`。
- [ ] 备份 manifest 记录每个被替换文件原 Hash、大小、时间和恢复路径。
- [ ] 构建后重新打开 MPQ，逐文件读取并核对 manifest Hash。

### 任务 7.4：分批部署

- [ ] 批次 1：保留 21 + 每个 family 至少 2 个新模型，覆盖盾牌、书本、拳套、远程和长柄。
- [ ] 批次 2：按 registry 选择约 250 个分层代表，覆盖共享几何/不同纹理和不同几何/共享纹理。
- [ ] 批次 3：全部 READY 候选。
- [ ] 每批使用独立 bundleId、assetPackVersion、backup manifest 和本地 tag。
- [ ] 每批只有在模型/纹理/相机/切换/回滚实机通过后才能进入下一批。

### 任务 7.5：自动与离线验证

- [ ] 每个 READY presentation 的 M2、SKIN、纹理和 DBC row 都存在且 Hash 匹配。
- [ ] 没有未引用输出和引用不存在输出；允许的共享资源引用计数正确。
- [ ] 资产包大小、唯一几何数、唯一纹理数、唯一 display 数和去重节省比例进入报告。
- [ ] 转换器对异常/恶意长度、越界 offset、非有限 bounds 和已有 camera 输入 fail closed。
- [ ] x86 SoloCam native tests、LoadLibrary probe 和 client address tests 全部通过。

### 任务 7.6：阶段出口

- [ ] 三个批次均能从固定 evidence root 重建。
- [ ] 聚合包部署与恢复至少各演练一次，原文件 Hash 完整恢复。
- [ ] 全部 READY 资产离线验证通过，零缺文件/重复冲突 ID。
- [ ] 生成阶段报告；production 目录切换仍留到阶段 8。

## 14. 阶段 8：切换全量公开武器 presentation 并优化运行性能

阶段目标：让所有阶段 7 READY 公开武器进入正式衣橱，保留明确 unavailable 条目，并证明大目录不会引入模型池、翻页和内存回归。

### 任务 8.1：取消 21 条硬上限

- [ ] `appearance_presentations.py` 不再要求 presentationCount 恰好 21 或 display IDs 恰好 `40000..40020`。
- [ ] validator 改为验证 registry、append-only 保留、唯一性、资源 Hash 和状态闭合。
- [ ] `Wardrobe.lua:isStandaloneItemRecord` 不再检查 `40000..40020`，改为显式 presentation/registry 能力验证。
- [ ] `generate_catalog.py` 对 READY 候选生成 `STANDALONE`，对明确失败生成 `UNAVAILABLE`。
- [ ] presentation 变化不污染服务端 appearance mapping hash；assetPackVersion/presentation hash 按合同升级。

### 任务 8.2：AddOn 大目录消费

- [ ] 保持 18 个卡片/模型对象池，不为全目录创建 3,690 个 PlayerModel。
- [ ] 只有当前页 standalone 卡片激活 direct display 和相机 updater；离页立即清理。
- [ ] unavailable 卡片显示原物品图标、名称和具体友好原因，不显示统一问号作为唯一信息。
- [ ] family/model/appearance pose 缓存按版本失效，不在每帧扫描全目录。
- [ ] 快速翻页、过滤、切主副手时 generation 防止上一页模型串入。

### 任务 8.3：运行审计全扫

- [ ] RuntimeAudit 遍历全部 3,690 公开武器，记录 appearanceId、status、GetModel path、synthetic display、pose source、ready 时间和失败原因。
- [ ] READY 条目要求 `GetModel()` 与 registry canonical path 匹配并稳定多个采样 tick。
- [ ] UNAVAILABLE 条目要求模型控件隐藏，图标/原因可见，无角色、NPC、黑模或空白卡片。
- [ ] 审计输出到 F 盘 `_work/runtime-audit`，不进入正式 AddOn bundle。
- [ ] 冷启动、热缓存、`/reload` 各运行一次；结果按 bundleId 关联。

### 任务 8.4：视觉抽样与相机众包工作流

- [ ] 每个 weapon family 抽取 first/middle/last、最大/最小 bounds、共享模型不同纹理、主手/副手代表。
- [ ] 盾牌正面、书本/副手、拳套、弓弩枪、魔杖、投掷、钓鱼竿专项验收。
- [ ] 使用工作台记录 outlier，优先添加 model override，只有单件异常才使用 appearance override。
- [ ] 导出一批真实玩家调校记录，完成审核合并并重建，证明无需逐件手工调整。
- [ ] 记录仍需后续人工优化的非阻塞 outlier，不把安全可见的轻微构图差异误报为资源失败。

### 任务 8.5：性能门槛

- [ ] 页面保持固定模型池，常驻 OnUpdate 数量不随目录规模增长。
- [ ] 目录加载、过滤、分页和 Lua 内存与第二轮基线比较；超过基线 20% 时分析并处理。
- [ ] 模型 ready timeout/retry 有界，不对失败条目无限重试。
- [ ] MPQ/DBC 首次加载时间、客户端内存和资产包体积进入报告。
- [ ] 连续翻阅全部页不崩溃、不出现模型交叉污染或持续内存增长。

### 任务 8.6：阶段出口

- [ ] 3,690 条公开主副手运行审计全部闭合为 READY 或明确 UNAVAILABLE。
- [ ] 所有离线 READY 条目在真实客户端零空模型、零角色/NPC fallback。
- [ ] 当前 21 个旧样本视觉和 pose 零回归。
- [ ] 性能门槛、冷/热缓存和工作台导出闭环通过。
- [ ] 生成阶段报告并更新本文完成状态。

## 15. 阶段 9：集成、干净构建、发布候选与最终实机验收

阶段目标：把媒体、套装、镜头和全量武器作为一个可追溯 bundle 集成，完成安装/回滚演练；不自动公开发布。

### 任务 9.1：版本与 Hash 收口

- [ ] 冻结 AddOn/module/Core commit；module/Core 若零变化也明确记录。
- [ ] 冻结 metadataVersion、assetPackVersion、appearance/set presentation hash、camera profile hash、weapon registry hash。
- [ ] release manifest 记录基础媒体、SoloCam DLL、MPQ、DBC、AddOn generated 数据和 worldserver provenance。
- [ ] AddOn/DLL/asset pack 任一版本不配套时，能力 fail closed 并显示明确提示。

### 任务 9.2：干净检出重建

- [ ] 使用 F 盘 `TEMP/TMP` 和干净 worktree 运行全部生成器、测试和构建。
- [ ] clean checkout 加固定 evidence pack 能重建媒体清单、套装排序、camera profiles、weapon registry 和客户端资产。
- [ ] 比较开发工作树与干净构建输出；除允许的时间/容器元数据外内容 Hash 一致。
- [ ] repository hygiene 确认无凭据、绝对本机路径、客户端资产、DLL/EXE/MPQ/DBC/WDB 或数据库转储进入 Git。

### 任务 9.3：bundle 安装与回滚

- [ ] `New-RoundTwoBundle.ps1` 或后继脚本生成新的本地候选，文件清单和 SHA-256 完整。
- [ ] `Test-RoundTwoBundle.ps1` 验证 required media、DLL PE、资产 registry、MPQ/DBC 和三仓 commit。
- [ ] `Install-RoundTwoBundle.ps1` 识别目标、备份、安装并执行 installed verifier。
- [ ] 模拟一个锁定/Hash 不匹配失败，确认自动回滚且原文件完整。
- [ ] `Restore-RoundTwoBundle.ps1` 完整恢复旧 AddOn/DLL/MPQ/DBC；重装新 bundle 后再次验证。

### 任务 9.4：最终真实客户端矩阵

- [ ] 图标：11 槽位、launcher、mount portrait、hover/selected。
- [ ] 套装：排序、职业过滤、搜索、滚轮、分页、拖动、2/3/5/8/9 件预览、快速切换。
- [ ] 武器：全部 READY 自动全扫、全部 UNAVAILABLE 状态检查、family 视觉抽样。
- [ ] 镜头：武器三层覆盖、body profile 差量、批量导出、清空 SavedVariables 后 round-trip。
- [ ] 状态：冷/热缓存、`/reload`、登出/重登、worldserver 重启、DLL 缺失、asset mismatch。
- [ ] 分辨率/UI Scale：1024×768、1366×768、1920×1080 多档 scale、2560×1440、3440×1440。
- [ ] 稳定性：快速翻页/切换 10 分钟，无 Lua error、崩溃、黑模、NPC、角色串入、无限重试或持续内存增长。

### 任务 9.5：最终阶段出口

- [ ] 所有阶段报告、截图、录像、CSV/JSON 运行审计和 manifest 以 bundleId 关联。
- [ ] 本文所有已完成子项逐项改为 `[x]` 并附日期/证据；未完成项保持 `[ ]`，不得用总体验收掩盖。
- [ ] 建立本地候选 tag 和完整回滚说明；不 push、不创建公开 release。
- [ ] 用户完成最终客户端验收后，本方案状态改为“已完成”。

## 16. 自动测试与建议命令

所有命令从 AddOn 仓库根目录运行。实施时使用实际 evidence/module 路径替换示例变量：

```powershell
$scRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-addon'
$scModule = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\round-two-module'
$scEvidence = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\evidence\round3-wardrobe-camera-set'
$scTemp = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\temp\round3'
New-Item -ItemType Directory -Force -Path $scTemp | Out-Null
$env:TEMP = $scTemp
$env:TMP = $scTemp
Set-Location -LiteralPath $scRepo
```

### 16.1 AddOn/目录测试

```powershell
python -m unittest discover -s tools\collections\tests -p 'test_*.py'
python tools\catalog\generate_catalog.py --module-root $scModule --evidence-root $scEvidence --check
python tools\catalog\itemset_import.py check --repo-root $scRepo --evidence-root $scEvidence
python tools\catalog\set_catalog.py --module-root $scModule --evidence-root $scEvidence --check
$scLuac = 'F:\1_projects\wow_projects\_work\lua-5.1.5-validator\luac51.exe'
Get-ChildItem -LiteralPath 'addon\SoloCollections' -Recurse -File -Filter '*.lua' | ForEach-Object {
    & $scLuac -p $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($_.FullName)" }
}
```

新增工具至少支持 `--check` 或等价 read-only mode，并纳入同一 unittest discovery：

```powershell
python tools\catalog\weapon_presentations.py check --repo-root $scRepo --evidence-root $scEvidence
python tools\catalog\set_presentations.py check --repo-root $scRepo --evidence-root $scEvidence
python tools\catalog\camera_tuning_import.py check --repo-root $scRepo --input <export-file>
```

具体 CLI 在实现时可按现有工具风格调整，但最终方案和报告必须更新为真实可运行命令，不能保留伪命令。

### 16.2 SoloCam 测试

```powershell
& .\client-extension\SoloCam\scripts\build.ps1
python -m unittest discover -s client-extension\SoloCam\tests -p 'test_*.py'
```

native tests 至少覆盖：

- `CameraProfileTests`：180 profiles、body delta、未知 profile 和边界；
- `ItemCameraBridgeTests`：七轴 pose、版本、清理和范围；
- `DisplayInfoBridgeTests`：追加 display IDs、上限、synthetic record 生命周期；
- LoadLibrary/process probe：真实 x86 DLL 能加载并命中固定客户端地址合同。

### 16.3 Release 与仓库卫生

```powershell
& .\tools\release\Test-RepositoryHygiene.ps1
& .\tools\release\Test-RoundTwoBundle.ps1 -BundleRoot <bundle-root>
```

安装和回滚命令只对明确 bundle/target 执行，并使用脚本自身的 backup manifest；不得手工递归删除或覆盖客户端目录。

## 17. 真实客户端验收记录格式

每次运行至少记录：

```text
runId
bundleId
timestampUtc
clientBuild / locale
resolution / uiScale
addonCommit / moduleCommit / coreCommit
metadataVersion / assetPackVersion
appearancePresentationHash
setPresentationHash
cameraProfileHash
weaponRegistryHash
SoloCamDllSha256
patchMpqSha256 / localePatchSha256
cacheState = cold | warm | reload
result = READY | FAILED
failureReason
evidenceRelativePaths[]
```

武器逐条记录增加：

```text
appearanceId, sourceItemId, slot, weaponType,
presentationStatus, syntheticDisplayId, expectedModelPath,
actualModelPath, cameraScope, cameraKey, readyMilliseconds,
failureReason
```

套装逐条/抽样记录增加：

```text
collectionId, itemSetId, sortRank fields, page/offset/sliderValue,
selectedVariantOrdinal, expectedPreviewSlots, actualPreviewSlots,
staleGenerationObserved
```

## 18. 回滚策略

### 18.1 AddOn 媒体/UI 回滚

- 媒体路径、滚动映射、套装预览和工作台分别提交，能够按提交回退。
- 新媒体文件删除前先确认没有 Lua/manifest 引用；不得让回滚版本引用不存在文件。
- SavedVariables schema 2 保留 legacy 读取和降级路径；回滚旧 AddOn 时不主动删除新表。

### 18.2 套装排序回滚

- 排序字段是只读 presentation，可回退为旧源顺序而不迁移 DB、owned 或 variantOrdinal。
- presentation hash 随 bundle 回退；mapping hash 保持不变。
- 若排序 evidence 有误，只禁用新比较器，不回滚 ItemSet identity。

### 18.3 SoloCam/镜头回滚

- AddOn、DLL、camera profile manifest 作为配套版本切换。
- DLL 不匹配时 AddOn 禁用可写工作台并使用现有安全相机，不发送未知命令。
- 旧 21 weapon pose 和 180 body profiles 保留为已知良好 fallback。

### 18.4 武器资产回滚

- 每次部署前备份 AddOn、DLL、聚合 MPQ、locale patch 和相关 manifest。
- 恢复按 backup manifest 的精确路径和 Hash 执行，不按通配符删除。
- 新 synthetic IDs 即使回滚也保留 registry/tombstone，不重新分配给其他资源。
- 资源不匹配时目录降级为 `UNAVAILABLE`，canonical owned 不删除。

### 18.5 触发立即回滚的条件

- 客户端崩溃、错误 NPC、角色进入武器卡、黑模或无限模型重试；
- 原 21 个武器、180 profiles、465 套装或基础媒体出现已知回归；
- clean bundle 缺少基础 UI 资源；
- synthetic ID 冲突、registry 重排、DBC 覆盖 baseline 行；
- AddOn/DLL/MPQ/presentation hash 不一致却仍尝试加载；
- 套装预览出现上一套或玩家装备残留；
- 滚动条、页码和实际 offset 再次不同步；
- 构建/部署在 C 盘产生新工作输出，或覆盖未识别客户端文件；
- 固定 evidence pack 无法重建生成物。

## 19. 推荐提交与里程碑边界

推荐按以下边界提交，不做一个巨型提交：

1. **A：媒体合同与基础图标**
   - media schema、项目自有图标、Lua 引用、release tests、实机证据。
2. **B：套装滚动与干净预览**
   - Slider 映射、generation 状态机、selectedVariant 成员、实机证据。
3. **C：套装 presentation 排序**
   - evidence、review、generator、AddOn sort、报告。
4. **D：武器镜头工作台**
   - SavedVariables schema、三层覆盖、dock layout、批量导出/导入。
5. **E：角色相机差量协议**
   - SoloCam native、AddOn BODY mode、180 profile 验收。
6. **F：全量武器 shadow 提取与注册表**
   - evidence、candidate、dedup、append-only registry，不切生产。
7. **G：批量客户端资产**
   - 构建器、DBC/MPQ、分批 bundle、部署/回滚证据。
8. **H：正式目录切换与性能**
   - 取消 21 条硬限制、全量运行审计、工作台众包闭环。
9. **I：集成候选**
   - clean checkout、release bundle、最终实机矩阵和文档收口。

每个提交必须保持相关测试绿色。跨 AddOn/DLL/asset pack 的提交信息记录配套 commit/Hash；只有对应阶段出口关闭后才创建本地里程碑 tag。本方案不授权推送这些 tag。

## 20. 总体验收清单

- [ ] 基础 AddOn bundle 中所有 production 媒体引用都有实际文件和合法 provenance。
- [ ] 11 个外观槽位图标、launcher 和相邻 portrait 在无外部 Retail 媒体时可见。
- [ ] 套装第一页滑块顶部，最后一页底部，滚轮/分页/拖动方向与列表一致。
- [ ] 套装预览只穿 selected variant 成员；玩家装备、上一套和 omitted 成员零残留。
- [ ] 465 个 active ItemSet 有稳定展示排序；ICC/T10 高难度/高等级套装位于前部。
- [ ] 套装 presentation 不改变 collection ID、owned、mapping hash 或 variantOrdinal。
- [ ] 武器镜头工作台不遮挡卡片，支持 family/model/appearance 三层覆盖。
- [ ] 玩家能复制当前镜头和批量导出本次全部修改；导出记录带完整身份和版本。
- [ ] 护甲镜头按 asset profile + sex + slot 调整并导出；180 profiles 安全回退和 round-trip 通过。
- [ ] 现有 21 个 verified 武器资源、ID、模型和 pose 零回归。
- [ ] 3,690 个公开主副手全部有 READY 或明确 UNAVAILABLE 终态。
- [ ] 所有具有可验证源资源的公开武器使用独立模型，不显示角色/NPC/黑模/空白卡。
- [ ] 全量武器生成实现几何、纹理、display 三级去重和追加式 ID 注册表。
- [ ] 聚合 MPQ/locale DBC 构建、回读、安装和恢复均通过 Hash 验证。
- [ ] 大目录仍只使用固定模型池，无无限 OnUpdate、持续内存增长或翻页串模。
- [ ] 冷/热缓存、`/reload`、重登、stock client fallback、分辨率/UI Scale 矩阵通过。
- [ ] clean checkout + F 盘 fixed evidence pack 可重建全部生成物和本地 bundle。
- [ ] Git 不包含凭据、绝对本机路径、客户端资产、DLL/EXE/MPQ/DBC/WDB 或数据库转储。
- [ ] 所有完成项已在本文逐项标记 `[x]` 并附日期、提交和证据。

## 21. 明确留到后续的工作

- 对每一件武器做人工像素级精调；本轮使用自动构图、family/model override 和 outlier 众包，避免逐件工作量。
- 为个别护甲 appearance 建立单件相机覆盖；只有 profile 级方案确实无法覆盖的异常物品才另立合同。
- 重建所有物品附魔光效、Retail 粒子特效或高版本 appearance camera 数据。
- 新增套装按资料片/来源/配色的完整分组浏览和额外排序下拉 UI；本轮先保证默认推荐排序正确。
- 导入高版本武器、套装、坐骑、玩具、HD 模型或新的 renderer。
- 远程 push、公开 GitHub release、正式生产数据库部署或对外分发客户端资产；需要单独授权和资源许可审核。
