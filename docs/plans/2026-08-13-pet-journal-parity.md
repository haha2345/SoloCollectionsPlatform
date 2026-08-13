# 小宠物日志与坐骑页一致性 Implementation Plan

> **执行约束（覆盖 `writing-plans` 的默认执行模板）：** 按工作区 `AGENTS.md` 使用直接、敏捷、逐项迭代的方式实施；不启用 TDD、子代理开发、独立代码审查或完整验证门。每个有边界的逻辑功能完成后运行与该功能直接相关的检查并单独提交，真实客户端与视觉验收保持为独立状态。

**Goal:** 将 SoloCollections 小宠物页改造成与已验收坐骑页尺寸、布局、排序、筛选、详情、按钮和模型交互一致的小宠物日志，并补齐可追溯的中文来源/描述、服务端权威偏好与随机召唤。

**Architecture:** SoloCollections 仓库继续拥有目录、SC2 协议和 AddOn 页面逻辑；`mod-solo-collections` 继续拥有账号收藏、偏好持久化、随机候选选择和召唤授权；SoloClientSuite 的 DragonUI_NewEra 公共 API 只提供视觉组件。客户端只提交稳定的 `typeId + collectionId + actionId`，不得本地决定所有权、偏好真值或随机结果。

**Tech Stack:** WoW 3.3.5a Lua/FrameXML、DragonUI_NewEra Public API、SC2 AddOnMessage 协议、AzerothCore C++20 模块、MySQL characters 数据库、Python 目录生成器、PowerShell 7 客户端套件构建脚本。

---

## 0. 计划状态、基线与执行纪律

计划状态：`PLAN_ONLY`。本文创建时不修改 Lua、C++、数据库或真实客户端。

### 0.1 已审计基线

| 仓库 | 实施分支起点 | 当前职责 |
|---|---|---|
| SoloCollections | `79572c385dbe` | 目录源、目录生成器、SC2 schema、AddOn 页面与桥接 |
| mod-solo-collections | `6a747c46` | 服务端收藏、偏好、随机选择、召唤动作与数据库 |
| SoloClientSuite | `a9c09a0` | DragonUI_NewEra 公共视觉组件、集成锁与本地构建 |
| AzerothCore | 不新建功能分支 | 本阶段预计不修改核心 |

上述 commit 只表示本计划的审计起点。开始实施时必须先确认它们仍是预期祖先，不能用 reset、checkout 或清理命令覆盖现有工作。

### 0.2 已知工作树状态

SoloCollections 功能 worktree 中已有其他坐骑计划和证据文档；SoloClientSuite 中已有未跟踪的证据目录。这些内容属于现有工作，实施小宠物页时必须保留，禁止 `git clean`、禁止批量删除、禁止把无关文件混入小宠物提交。

### 0.3 完成标记规则

- [ ] 只有源码改动完成并通过该任务列出的直接检查后，才能把对应任务标记为完成。
- [ ] `SOURCE_COMPLETE`：规范源、审计文件和生成器已完成。
- [ ] `STATIC_VALIDATED`：生成器、协议/契约检查和套件布局检查通过。
- [ ] `SERVER_VALIDATED`：模块编译成功，数据库迁移和 worldserver 启动日志正常。
- [ ] `REAL_CLIENT_ACCEPTED`：国服 3.3.5a 客户端实际交互与视觉由真实客户端验收通过。
- [ ] Git 提交、服务端部署、客户端安装和真实客户端验收必须分别记录，不能互相替代。

### 0.4 明确不做

- 不加入宠物对战等级、品质、技能、队伍或战斗系统。
- 不实现按获取日期排序；与坐骑页一致，统一使用“偏好/已收集分组 + 中文名称 + collectionId”排序。
- 不为随机小宠物按钮或列表图标实现宏、`/script` 或技能栏拖拽；本需求没有提出该能力，且 DragonUI/EZ 的宏方案不是服务端权威动作。
- 不修改 AzerothCore 核心来实现小宠物日志；若模块 API 已足够，不扩大边界。
- 不把 DBC、DB2、MPQ、客户端二进制、SavedVariables、账号信息或机器绝对路径提交到 Git。
- 不手工编辑生成文件作为最终修复；先改规范源/生成器，再重新生成。

---

## 1. 最终页面与行为契约

### 1.1 页面几何

小宠物页复用已验收坐骑页的几何契约，不再保留当前 703px 旧页面：

| 项目 | 最终值 |
|---|---:|
| 日志宽度 | 768 |
| 日志高度 | 606 |
| 顶部带高度 | 40 |
| 底部带高度 | 40 |
| 顶部控件 Y | 68 |
| 列表顶部 | 96 |
| 底部内缩 | 44 |
| 左右边距 | 14 |
| 列表宽度 | 260 |
| 列表与详情间距 | 24 |
| 行高 | 46 |
| 首行 Y | 3 |
| 可见行数 | 10 |
| 底部动作按钮 | 180 × 26 |
| 普通/选中底部标签高度 | 36 / 42 |

这些值继续来自 `addon/SoloCollections/UI/DragonUI/MountJournal.lua` 的共享布局副本；不得在 `Pets.lua` 再维护一套不同常量。

### 1.2 列表排序

固定排序键如下，禁止加入获取日期：

1. 已收集且设为偏好；
2. 已收集但未设为偏好；
3. 未收集；
4. 同一组内按国服中文名称升序；
5. 名称相同按稳定 `collectionId` 升序。

未收集的小宠物不能设为偏好，也不能进入随机召唤候选池。

### 1.3 筛选

小宠物页使用与坐骑页同样的 DragonUI 红色“筛选”按钮和独立命名下拉菜单，但菜单项按小宠物调整：

- 收集状态：已收集、未收集；
- 偏好：仅显示偏好；
- 来源：掉落、任务、商人、专业、宠物对战、成就、世界事件、促销、集换式卡牌、游戏商城、探索、其他；
- 来源菜单只显示当前规范目录中实际存在的类别，保持上面的稳定顺序；
- 不显示坐骑专用的陆地、飞行、水栖或当前不可用选项；
- 小宠物来源筛选状态保存在 `filters.pets.hiddenSources`，不能污染坐骑筛选状态。

### 1.4 详情区

详情区与坐骑页使用同一套 DragonUI 公共组件，必须包含：

- 小宠物图标、品质边框/选中边框、国服中文名；
- “已收集/未收集”状态；
- 正确的中文来源块，支持商人、地区、费用、任务、掉落、成就、专业、活动、促销/绝版等多行信息；
- 正确的中文描述；
- 可旋转、可滚轮缩放的模型；
- “设为偏好/取消偏好”按钮，仅已收集时可用；
- 底部居中的“召唤小宠物/解散小宠物”红色按钮。

费用行继续使用 WoW 内联金币纹理，字号为 0 并由字体行高决定尺寸，避免图标与数字上下错位；不得用独立 FontString/Texture 拼成两行。

### 1.5 随机召唤

- 顶部右侧加入“随机召唤收藏小宠物”按钮，位置和视觉与坐骑页随机按钮一致；
- 图标优先使用一个已收集偏好小宠物的真实图标，其次使用首个已收集可随机小宠物图标，最后回退到 `Interface\\Icons\\Ability_Hunter_BeastCall`；
- 服务端优先从“已收集且偏好且可召唤”的候选池随机；没有偏好候选时从全部“已收集且可召唤”的候选池随机；
- 候选数大于 1 时尽量避开当前已召唤的小宠物；只有一个候选且它当前已召唤时，沿用单宠物按钮的解散语义；
- 随机按钮不能让未收集、隐藏、内部、测试、重复或不可执行条目进入候选池；
- 客户端不能本地生成随机结果，只发送 SC2 动作并等待服务端结果。

### 1.6 模型交互

- 使用模型 provider 和 generation token，旧响应不得覆盖新选择；
- 拖动旋转优先调用 `PlayerModel:SetFacing`，只在客户端没有该方法时才回退 `SetRotation(..., false)`；
- 拖动时不能重新播放模型动画；
- 滚轮缩放范围、默认朝向、重置视角和模型加载恢复逻辑直接对齐坐骑页；
- SC2/模型 provider 从未就绪变为 Ready 时，当前选择自动重试一次；
- 切换条目、隐藏页面或清空选择时取消旧交互状态。

---

## 2. 目录与中文数据契约

### 2.1 规范文件

新增 `catalog/source/companion_journal_metadata.json`，每个规范小宠物必须恰好有一条记录：

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "collectionId": 200000,
      "spellId": 10673,
      "journalNameZhCN": "烟网小蜘蛛",
      "sourceType": 1,
      "source": "|cFFFFD200任务：|r……|n|cFFFFD200地区：|r……",
      "descriptionZhCN": "……",
      "descriptionKey": 10673,
      "descriptionStatus": "OFFICIAL_ZHCN_CLIENT",
      "acquisitionClass": "STANDARD",
      "journalVisible": true,
      "actionable": true,
      "randomEligible": true,
      "canonicalActionSpellId": 10673,
      "visibilityReason": null,
      "exclusionReason": null
    }
  ]
}
```

字段约束：

- `collectionId`、`spellId` 必须与 `companion_actions.json` 一致；
- `journalNameZhCN` 必须使用国服名称，不得用英文占位；
- `sourceType` 使用当前坐骑目录和 DragonUI/EZ 原始行一致的 0..11 编号（掉落=0、任务=1、商人=2……其他=11），中文标签由 SoloCollections 提供；
- `source` 为已审阅的中文显示字符串；
- `descriptionZhCN` 只能来自有记录的中文客户端/数据库或人工核对翻译，禁止 AI 生成；
- 无可核验文案时使用空字符串与 `descriptionStatus=MISSING`，UI 显示“暂无可核验的中文描述”；
- `journalVisible=false` 的内部/测试/临时/重复条目不进入用户列表；
- `actionable` 和 `randomEligible` 分开记录，服务端按这两个字段执行；
- 促销、绝版、集换式卡牌小宠物可以显示和收藏，只要身份链唯一且不是内部/测试条目。

### 2.2 数据证据优先级

1. 合法取得的国服客户端本地化数据：Spell、Item、Quest、Creature、Achievement、后续客户端 BattlePetSpecies 等；
2. 当前 AzerothCore world 数据库中的任务奖励、商人、掉落、专业和事件关系；
3. DragonUI_NewEra_Collections `Data.lua` 与 ezCollections PetData，仅作为身份、字段和英文来源交叉参考；
4. 其他可追溯数据库作为缺口补充，必须记录来源版本和键；
5. 无法核验的内容保持缺失，不编造。

原始 DBC/DB2/数据库导出留在仓库外 evidence 目录。Git 只保存规范化中文字段、审阅决定、证据清单和 SHA-256，不保存原始客户端资源。

### 2.3 可见性与去重规则

新增 `catalog/review/companions/journal-visibility-policy.json` 和 `catalog/review/companions/duplicate-audit.json`：

- 同一规范召唤身份的多个学习法术合并到一个 `collectionId`，其余保留在 `unlockSpellIds`；
- 以 canonical summon spell、preview creature、国服名称和来源链交叉识别重复；
- 飞行点/交通工具、任务临时跟随物、职业技能临时守护物、GM/测试宠物、占位法术不属于小宠物收藏；
- 绝版、促销、TCG、活动奖励可正常显示，但未拥有时不可召唤/偏好；
- 每个隐藏条目必须有稳定 `visibilityReason`/`exclusionReason`；
- 生成 `catalog/generated/companion-journal-audit.json`，记录总数、显示数、可执行数、随机候选数、隐藏原因数、重复合并数和中文数据缺口数。

---

## 3. 服务端与协议契约

### 3.1 类型与动作

| 类型/动作 | 值 | 语义 |
|---|---:|---|
| 小宠物收藏 | SC2 type 11 | 账号已拥有的小宠物 `collectionId` |
| 小宠物偏好投影 | SC2 type 17 | 使用 type 11 的 `collectionId`，不参与导航和进度 |
| `SUMMON` | type 11 + collectionId | 召唤指定已拥有小宠物；再次点当前宠物则解散 |
| `SET_FAVORITE` | type 11 + collectionId + 0/1 | 服务端校验拥有状态并持久化偏好 |
| `RANDOM_SUMMON` | type 11 + collectionId 1 | 服务端从权威候选池选择并召唤 |
| `PREVIEW` | type 11 + collectionId | 仅预热/请求模型资源，不授权收藏动作 |

`collectionId=1` 只在 `RANDOM_SUMMON` 控制动作中保留，不是目录小宠物。

### 3.2 偏好持久化

复用现有通用表 `solo_collection_preference`：

- 小宠物偏好以底层 `type_id=11` 保存；
- SC2 快照/增量投影为内部 `type_id=17`；
- `BeginPreferenceMutation` 同时支持 mount 16→10 和 companion 17→11；
- 只能为已拥有的小宠物写入偏好；
- 删除收藏或目录失效时，偏好投影不能继续对客户端显示；
- 旧 `SoloCollectionsDB.favorites.PETS` 只做一次幂等迁移，收到 type 17 权威 delta 后才标记该条迁移完成。

现有表结构能满足需求时不新增表。只有干净安装基线缺少该通用表时，才新增 append-only `IF NOT EXISTS` SQL，并同步基线 schema；不得修改已执行迁移的语义。

### 3.3 服务端随机算法

```text
owned = type 11 权威收藏
eligible = owned ∩ journalVisible ∩ actionable ∩ randomEligible
favorite = eligible ∩ type 17 偏好
pool = favorite 非空 ? favorite : eligible
若 pool 为空：返回 NO_COMPANIONS / NO_USABLE_COMPANIONS
若 pool 大于 1：排除当前已召唤 collectionId 后随机
调用与指定召唤相同的中央执行器
返回 ACCEPTED 或 DISMISSED，并由现有 SC2 结果刷新客户端
```

随机与指定召唤必须共享同一组死亡、战斗、载具、飞行点和动作有效性检查，避免出现两个不同的授权路径。

### 3.4 客户端中文提示

AddOn 至少映射：

| 服务端状态 | 中文提示 |
|---|---|
| `NOT_OWNED` | 尚未收集该小宠物。 |
| `FAVORITE_NOT_OWNED` | 只有已收集的小宠物才能设为偏好。 |
| `NO_COMPANIONS` | 尚未获得可召唤的小宠物。 |
| `NO_USABLE_COMPANIONS` | 当前没有可召唤的小宠物。 |
| `IN_COMBAT` | 战斗中无法召唤小宠物。 |
| `DEAD` | 死亡状态下无法召唤小宠物。 |
| `IN_VEHICLE` | 乘坐载具时无法召唤小宠物。 |
| `ON_TAXI` | 使用飞行点时无法召唤小宠物。 |
| `CAST_FAILED` | 小宠物召唤失败，请稍后重试。 |

协议仍传稳定英文 token；中文只在客户端展示层转换。

---

## 4. 分任务实施清单

### Task 1：建立隔离分支并冻结基线

**Files:** 无源码修改。

**Steps:**

1. [x] 在三个实际仓库分别运行 `git status --short`、`git branch --show-current`、`git rev-parse HEAD`。
2. [x] 记录现有未提交文件，确认它们与小宠物功能无重叠；有重叠时停止并先处理所有权。
3. [x] 从第 0.1 节所列祖先创建或确认三个 `feat/pet-journal-parity` 功能分支；不清理现有 worktree。
4. [x] 在实施日志记录三个起点 commit 与当前目录生成 hash。

**Direct check:**

```powershell
git merge-base --is-ancestor <audited-base> HEAD
git status --short
```

**Expected:** merge-base 返回 0；状态中只有已知文件，没有实施者不认识的新修改。

**Commit:** 无。

---

### Task 2：生成小宠物来源、可见性和重复审计

**Files:**

- Modify: `tools/catalog/companion_catalog.py:187-509`
- Modify: `catalog/review/companions/review-policy.json`
- Modify: `catalog/review/companions/evidence.json`
- Create: `catalog/review/companions/journal-visibility-policy.json`
- Create: `catalog/review/companions/duplicate-audit.json`
- Create: `catalog/generated/companion-journal-audit.json`
- Modify: `tools/collections/tests/test_companion_catalog.py`

**Steps:**

1. [x] 扩展 evidence 提取，输出 item、quest、vendor、loot、achievement、profession/event 等来源关系以及国服名称键。
2. [x] 将 DragonUI/EZ `PetData` 解析为只读交叉参考，不让它覆盖国服数据库中更高优先级的身份和中文字段。
3. [x] 为每个候选计算 canonical summon spell、unlock aliases、preview creature、来源类型、可见性分类和重复组。
4. [x] 明确排除交通/飞行点、任务临时实体、职业临时召唤、内部/测试/占位法术。
5. [x] 保留合法绝版、促销、活动、TCG 小宠物为可见目录项。
6. [x] 生成重复审计；同一 canonical identity 只能分配一个 collectionId。
7. [x] 生成汇总审计并列出每个中文来源/描述缺口，禁止用默认句子填满缺口。
8. [x] 更新已有 companion catalog 直接检查，覆盖飞行点排除、重复合并、促销/绝版可见和无 AI 占位文案。

**Commands:**

```powershell
python .\tools\catalog\companion_catalog.py extract `
  --repo-root . `
  --evidence-root <ExternalEvidenceRoot> `
  --out <ExternalWorkingRoot>\companion-evidence.json `
  --mysql <MySqlClient> `
  --worldserver-config <WorldserverConfig>

python .\tools\catalog\companion_catalog.py generate `
  --repo-root . `
  --evidence <ExternalWorkingRoot>\companion-evidence.json

python -m unittest discover -s .\tools\collections\tests -p "test_companion_catalog.py" -v
```

**Expected:** accepted/hidden/duplicate totals与审计一致；没有重复 canonical identity；排除原因非空；测试通过。

**Commit:** `feat(catalog): audit companion journal identities`

---

### Task 3：建立可追溯的国服中文来源与描述

**Files:**

- Create: `catalog/source/companion_journal_metadata.json`
- Create: `catalog/source/companion_source_zhCN.json`
- Create: `catalog/review/companions/text-provenance.json`
- Modify: `tools/catalog/companion_catalog.py:343-509`
- Modify: `tools/collections/tests/test_companion_catalog.py`

**Steps:**

1. [x] 为全部规范小宠物建立一一对应的 journal metadata 记录。
2. [x] 从国服 Spell/Item/Quest/Creature/Achievement 和 world 数据库生成中文来源块。
3. [x] 从合法取得的国服客户端/数据库提取描述，按 spell/creature/name 三键核对。
4. [x] 记录每条描述的 `descriptionStatus` 与 provenance reference；来源冲突进入 review 文件，不自动猜测。
5. [x] 金币费用统一输出 `数字|TInterface\\MoneyFrame\\UI-GoldIcon.blp:0|t`；多行使用 `|n`。
6. [x] 缺少可核验描述时保留空值和 `MISSING`，不写“账号收藏”或“服务端权威目录提供”等模板文案。
7. [x] 检查所有可见记录都有国服中文名、稳定来源类型和明确描述状态。

**Commands:**

```powershell
python .\tools\catalog\companion_catalog.py check --repo-root .
python -m unittest discover -s .\tools\collections\tests -p "test_companion_catalog.py" -v
```

**Expected:** journal metadata 覆盖率 100%；所有可见条目中文名非空；`MISSING` 数量在审计中明确；不存在 AI/模板占位句。

**Commit:** `feat(catalog): add reviewed zhCN companion journal metadata`

---

### Task 4：把小宠物日志字段投影到 AddOn 与模块

**Files:**

- Modify: `tools/catalog/generate_catalog.py:298-347`
- Modify: `tools/catalog/generate_catalog.py:706-833`
- Modify: `tools/catalog/generate_catalog.py:1067-1092`
- Modify: `tools/catalog/generate_catalog.py:1182-1270`
- Modify: `tools/catalog/generate_catalog.py:1333-1483`
- Modify: `addon/SoloCollections/Data/Generated/Catalog.lua`（生成）
- Modify: `mod-solo-collections/data/generated/solo_collections_companion_actions.json`（生成）
- Modify: `mod-solo-collections/src/generated/SoloCollectionsCompanionCatalog.inc`（生成，实际路径以现有 renderer 为准）
- Modify: `tools/collections/tests/test_catalog_generator.py`
- Modify: `tools/collections/tests/test_companion_catalog.py`

**Steps:**

1. [x] 新增 `_apply_companion_journal_contract`，要求 metadata 与 companion action collectionId 完全等集。
2. [x] AddOn 投影加入 `sourceText`、`sourceType`、`descriptionZhCN`、`descriptionStatus`、`journalVisible`、`actionable`、`randomEligible`、`canonicalActionSpellId`、`acquisitionClass` 和排除原因。
3. [x] 模块投影只加入执行所需的 `Actionable`、`RandomEligible`、`JournalVisible`、`CanonicalActionSpellId`，不把整段显示文案写进 C++。
4. [x] 为 companion journal 增加与 mount journal 相同的 `--companion-journal-only` / `--check` 轻量投影入口。
5. [x] 生成器拒绝 collectionId/spellId 漂移、覆盖不全、随机条目不可执行、隐藏条目仍可随机等错误。
6. [x] 重新生成 AddOn 与 module 投影，禁止手工调整生成文件。

**Commands:**

```powershell
python .\tools\catalog\generate_catalog.py --companion-journal-only
python .\tools\catalog\generate_catalog.py --companion-journal-only --check
$testPatterns = @("test_catalog_generator.py", "test_companion_catalog.py")
foreach ($pattern in $testPatterns) {
  python -m unittest discover -s .\tools\collections\tests -p $pattern -v
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

完整跨仓投影在有合法 evidence root 时运行：

```powershell
python .\tools\catalog\generate_catalog.py `
  --module-root <ModSoloCollectionsRoot> `
  --evidence-root <ExternalEvidenceRoot>
```

**Expected:** 无 drift；AddOn 只包含显示/稳定身份，模块只包含动作契约；映射 hash 按规则更新且两仓一致。

**Commit:** `feat(catalog): project companion journal contract`

---

### Task 5：扩展 SC2 小宠物偏好与随机动作

**Files:**

- Modify: `protocol/sc2/schema.json:1-116`
- Modify: `docs/protocol/sc2-wire-v1.md`
- Modify: `protocol/sc2/golden-vectors.json`（以实际文件名为准）
- Modify: `tools/collections/tests/test_sc2_protocol.py`
- Modify: `tools/collections/tests/test_sc2_client_contract.py`

**Steps:**

1. [x] 在 `projectionTypes` 加入 type 11 所有权和内部 type 17 偏好投影。
2. [x] 将 `SET_FAVORITE` 的合法 typeIds 扩展为 `[10, 11]`，明确 10→16、11→17。
3. [x] 将 `RANDOM_SUMMON` 的合法 typeIds 扩展为 `[10, 11]`，两者都使用控制 collectionId 1。
4. [x] 加入 `NO_COMPANIONS`、`NO_USABLE_COMPANIONS`，保留现有坐骑状态兼容性。
5. [x] 为 type 11 favorite on/off、random summon、未拥有偏好和非法控制 ID 增加 golden vectors。
6. [x] 更新协议文档，声明 type 17 不参与导航、总数或进度。

**Commands:**

```powershell
$testPatterns = @("test_sc2_protocol.py", "test_sc2_client_contract.py")
foreach ($pattern in $testPatterns) {
  python -m unittest discover -s .\tools\collections\tests -p $pattern -v
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

**Expected:** schema/golden vectors 一致；旧 mount vectors 不变；非法 type/action 仍被拒绝。

**Commit:** `feat(protocol): add companion favorites and random summon`

---

### Task 6：服务端持久化小宠物偏好投影

**Files (mod-solo-collections):**

- Modify: `src/SoloCollectionsCompanionCatalog.h:1-30`
- Modify: `src/SoloCollectionsAccountStore.cpp:120-410`
- Modify: `src/SoloCollectionsAccountStore.h:100-145`
- Modify: `src/SoloCollectionsCore.cpp:130-180,330-360`
- Modify: `src/SoloCollectionsProtocolScript.cpp:200-290`
- Modify: `data/sql/db-characters/solo_collections_schema_v1.sql`（仅在干净安装基线缺表时）
- Create: `data/sql/updates/char/2026_08_13_00_companion_preferences.sql`（仅在确有基线缺口时）
- Modify: `docs/CONFIGURATION.md`
- Modify: `docs/DEVELOPMENT.md`

**Steps:**

1. [x] 定义 `CompanionFavoriteCollectionTypeId {17}`，标记为 internal projection。
2. [x] 将 AccountStore 偏好读取从 mount-only 泛化为底层 type 10/11，并映射到 16/17。
3. [x] 将 preference mutation 映射写成显式函数，拒绝其他内部类型。
4. [x] 写入偏好前校验对应 type 11 collectionId 已拥有。
5. [x] 注册 `companion-favorite` provider，但不加入导航和完成度。
6. [x] 在 type 11 协议分支处理 `SET_FAVORITE`，沿用异步提交、revision 和 delta 语义。
7. [x] 审核现有 `solo_collection_preference` 是否已覆盖干净安装；只有确有缺口时新增幂等 SQL。

**Direct checks:**

```powershell
rg -n "CompanionFavoriteCollectionTypeId|type_id = 11|type_id=11" .\src .\data
git diff --check
```

在用户授权模块构建后：

```powershell
cmake --build <AzerothCoreBuildRoot> --config RelWithDebInfo --target worldserver
```

**Expected:** C++ 编译通过；type 17 出现在 SC2 状态但不出现在页面导航/总数；未拥有写偏好返回 `FAVORITE_NOT_OWNED`。

**Commit:** `feat(companions): persist account favorites`

---

### Task 7：服务端实现权威随机召唤

**Files (mod-solo-collections):**

- Modify: `src/SoloCollectionsCompanionService.h:1-40`
- Modify: `src/SoloCollectionsCompanionService.cpp:90-310`
- Modify: `src/SoloCollectionsProtocolScript.cpp:270-310`
- Modify: `src/generated/SoloCollectionsCompanionCatalog.inc`（由 Task 4 生成）

**Steps:**

1. [x] 把指定召唤的条件检查与实际执行整理为内部中央执行器，不改变现有 `SUMMON` 成功/解散语义。
2. [x] 新增 `ExecuteRandomSummon(Player*)`，只读取服务端目录、type 11 ownership 和 type 17 favorite。
3. [x] 按第 3.3 节建立 eligible/favorite/fallback pool。
4. [x] 候选多于一个时排除当前宠物；只剩当前一个时允许走解散语义。
5. [x] 在 type 11 协议分支处理 `RANDOM_SUMMON`，返回新的稳定状态 token。
6. [x] 确认随机与指定召唤都不会绕过死亡、战斗、载具和飞行点检查。

**Direct checks:**

```powershell
rg -n "ExecuteRandomSummon|NO_COMPANIONS|NO_USABLE_COMPANIONS|RandomEligible" .\src
git diff --check
```

在用户授权模块构建后：

```powershell
cmake --build <AzerothCoreBuildRoot> --config RelWithDebInfo --target worldserver
```

**Expected:** 编译通过；随机只从权威拥有池选择；有偏好时不选择非偏好；无偏好时正常回退全部 eligible。

**Commit:** `feat(companions): add authoritative random summon`

---

### Task 8：扩展 AddOn Bridge 与本地偏好迁移

**Files:**

- Modify: `addon/SoloCollections/Core/Bridge.lua:360-500`
- Modify: `addon/SoloCollections/Core/Bridge.lua:650-745`
- Modify: `addon/SoloCollections/Core/CollectionState.lua`
- Modify: `addon/SoloCollections/Core/Bootstrap.lua:1-35,430-455`
- Modify: `tools/collections/tests/test_bridge_contract.py`
- Modify: `tools/collections/tests/test_sc2_client_contract.py`

**Steps:**

1. [x] 新增 `SetPetFavorite(collectionId, favorite, callback)`，发送 type 11 `SET_FAVORITE`。
2. [x] 新增 `SummonRandomPet(callback)`，发送 type 11 / collectionId 1 `RANDOM_SUMMON`。
3. [x] 将 type 17 加入 CollectionState 内部投影识别，但不加入进度。
4. [x] 实现 `SoloCollectionsDB.favorites.PETS` 的幂等迁移队列：只迁移已拥有条目，只在观察到 type 17 delta 后记完成。
5. [x] 迁移完成后不再读取本地 PETS 偏好作为权威真值；保留数据直到整轮迁移完成，便于回滚。
6. [x] 加入小宠物状态 token 的中文映射。
7. [x] 在 `Bootstrap.lua` 增加 `filters.pets.hiddenSources` 修复与 schema version 迁移，不清空其他筛选。

**Commands:**

```powershell
$testPatterns = @("test_bridge_contract.py", "test_sc2_client_contract.py")
foreach ($pattern in $testPatterns) {
  python -m unittest discover -s .\tools\collections\tests -p $pattern -v
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

**Expected:** bridge 只发送 type 11 action；偏好真值来自 type 17；迁移可重入且不会为未拥有小宠物写偏好。

**Commit:** `feat(addon): bridge companion preferences and random summon`

---

### Task 9：把目录查询切换为小宠物权威字段和一致排序

**Files:**

- Modify: `addon/SoloCollections/Core/Catalog.lua:120-190`
- Modify: `addon/SoloCollections/Core/Catalog.lua:400-455`
- Modify: `addon/SoloCollections/Core/Catalog.lua:700-830`
- Modify: `addon/SoloCollections/Core/Catalog.lua:960-995`
- Modify: `tools/collections/tests/test_addon_contract.py`
- Modify: `tools/collections/tests/test_companion_catalog.py`

**Steps:**

1. [x] 删除小宠物固定“账号收藏”和固定服务端描述，读取生成目录的 `sourceText`/`descriptionZhCN`。
2. [x] `PETS` 偏好读取 type 17；未收集记录强制 `favorite=false`。
3. [x] 将 mount-only comparator 泛化为 collection presentation comparator，MOUNTS/PETS 共用且保持坐骑结果不变。
4. [x] 按“偏好已收集 → 已收集 → 未收集 → 中文名 → collectionId”排序。
5. [x] 在筛选逻辑中加入 `filters.pets.hiddenSources`，只对 PETS 生效。
6. [x] `journalVisible=false` 条目在 QueryAll/GetProgress 均不出现；总数与列表一致。
7. [x] 将旧 `ToggleDemoFavorite("PETS")` 路径移出生产 UI；demo mode 仅在明确离线演示时使用。

**Commands:**

```powershell
$testPatterns = @("test_addon_contract.py", "test_companion_catalog.py")
foreach ($pattern in $testPatterns) {
  python -m unittest discover -s .\tools\collections\tests -p $pattern -v
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

**Expected:** 小宠物列表无模板文案、无隐藏/重复项；排序与坐骑页一致；未收集项永远不显示为偏好。

**Commit:** `feat(addon): align companion catalog query semantics`

---

### Task 10：泛化 DragonUI 随机收藏视觉组件

**Files (SoloClientSuite):**

- Modify: `Interface/AddOns/DragonUI_NewEra/public/Components.lua:114-230,320-330`
- Modify: `Interface/AddOns/DragonUI_NewEra/docs/PUBLIC_API.md:1-70`
- Reference only: `Interface/AddOns/DragonUI_NewEra_Collections/modules/collections/Journal.lua:642-735`
- Reference only: `Interface/AddOns/DragonUI_NewEra_Collections/modules/collections/Assets.lua`

**Steps:**

1. [x] 新增 `Components:CreateRandomCollectionButton(parent, spec)`，允许调用方传 label、icon、fallbackIcon、tooltip 和 onClick。
2. [x] 保留 `CreateRandomMountButton` 作为兼容别名，确保已验收坐骑页视觉不变。
3. [x] 新增 capability `components.random-collection`，保留 `components.random-mount`。
4. [x] 宠物按钮沿用 DragonUI 图标裁切、边框、按下纹理和高亮；不复制 Journal.lua 的宏创建/`/script` 行为。
5. [x] 更新 Public API 文档，强调组件只负责视觉，随机与收藏状态仍由调用 AddOn/服务端负责。

**Commands:**

```powershell
pwsh -File .\tools\Inspect-ClientSuiteLayout.ps1
git diff --check
```

**Expected:** 布局检查通过；旧 `components.random-mount` 仍可用；新组件不包含收藏业务或宏。

**Commit:** `feat(newera): generalize random collection control`

---

### Task 11：让小宠物页复用坐骑页尺寸、带区和筛选按钮

**Files:**

- Modify: `addon/SoloCollections/UI/DragonUI/MountJournal.lua:8-90`
- Modify: `addon/SoloCollections/Core/UIPlatform.lua`
- Modify: `addon/SoloCollections/UI/CollectionsFrame.lua:1-20,232-280,550-655`
- Modify: `addon/SoloCollections/UI/Pets.lua:1-180`
- Modify: `addon/SoloCollections/SoloCollections.toc`（仅在新增文件时）
- Modify: `tools/collections/tests/test_addon_contract.py`

**Steps:**

1. [x] 将 `MountJournal` 的布局说明泛化为 companion journal 兼容适配器，但保留现有表名/方法别名，避免坐骑页回归。
2. [x] 增加 `CreateRandomCompanionButton`，内部使用 `components.random-collection`。
3. [x] `applyJournalSize` 对 MOUNTS/PETS 都使用 768 × 606。
4. [x] 将 `scMountFilterButton` 泛化为 companion filter button；点击时路由到当前 MOUNTS/PETS 页的 `OpenFilterMenu`。
5. [x] 小宠物页使用相同 top/bottom band、left/detail inset、sidePad、gap 和 bottomInset。
6. [x] 列表 scroll frame 顶部改为 `ROW_START_Y=3`，首行不再从 36px 开始，10 行全部落在容器内。
7. [x] 使用独立、具名的 `UIDropDownMenuTemplate` frame，避免 nil name 错误；不再使用旧共享 popup。
8. [x] 底部标签继续使用已验收的 DragonUI journal tab 样式，不复制新材质。

**Commands:**

```powershell
python -m unittest discover -s .\tools\collections\tests -p "test_addon_contract.py" -v
```

**Expected:** 静态契约确认 PETS 与 MOUNTS 宽高相同、列表 rowStartY=3、过滤菜单独立命名、旧坐骑组件兼容。

**Commit:** `feat(ui): align pet journal shell with mounts`

---

### Task 12：重建小宠物详情头、来源与按钮布局

**Files:**

- Modify: `addon/SoloCollections/UI/Pets.lua:90-340`
- Modify: `addon/SoloCollections/UI/DragonUI/MountJournal.lua`
- Modify: `addon/SoloCollections/UI/Templates.lua`（仅复用 helper，不新增业务状态）

**Steps:**

1. [x] 用 `CreateCollectionInfoHeader` 替换当前手工 icon/name/source/description 布局。
2. [x] 图标裁切、金色边框、选中状态、名称起点和文本宽度与坐骑详情一致。
3. [x] 显示目录中的国服中文来源；金币图标使用内联纹理并与数字同行垂直居中。
4. [x] 优先显示 `descriptionZhCN`；空值显示“暂无可核验的中文描述”，不回退 AI/模板句。
5. [x] `favorite` 按钮放在详情右下，与模型说明/重置按钮不重叠；未收集时禁用。
6. [x] 创建底部居中的 180 × 26 红色按钮，使用 `SkinRedActionButton`。
7. [x] 根据当前选择和当前召唤状态显示“召唤小宠物”或“解散小宠物”。
8. [x] 切换页面/无选择时清空头部、模型和按钮状态。

**Direct checks:**

```powershell
rg -n "账号收藏|服务端权威目录提供|ToggleDemoFavorite" .\addon\SoloCollections\UI\Pets.lua .\addon\SoloCollections\Core\Catalog.lua
git diff --check
```

**Expected:** 搜索不到生产路径中的旧占位文案；详情组件锚点来自共享布局；按钮不与底边框重叠。

**Commit:** `feat(ui): add reviewed companion detail presentation`

---

### Task 13：实现平滑模型旋转与加载恢复

**Files:**

- Modify: `addon/SoloCollections/UI/Pets.lua:50-90,500-560`
- Reference: `addon/SoloCollections/UI/Mounts.lua:153-190`
- Modify: `tools/collections/tests/test_addon_contract.py`

**Steps:**

1. [x] 将每次拖动的 `SetRotation` 改为坐骑页同款 `SetFacing` 路径。
2. [x] 仅在没有 `SetFacing` 时调用 `SetRotation(rotation, false)`。
3. [x] 复用坐骑页默认朝向、滚轮缩放、重置视角和鼠标捕获清理。
4. [x] 选择变化时递增 generation；回调只接受当前 generation 和当前 selectedId。
5. [x] provider/bridge Ready 后仅对当前仍选中的条目重试模型请求。
6. [x] 页面隐藏或记录不可见时停止拖动并清空旧模型。

**Commands:**

```powershell
python -m unittest discover -s .\tools\collections\tests -p "test_addon_contract.py" -v
rg -n "SetFacing|SetRotation\(rotation, false\)|generation" .\addon\SoloCollections\UI\Pets.lua
```

**Expected:** 静态契约不再允许拖动热路径直接 `SetRotation(model.rotation)`；模型回调有 generation guard。

**Commit:** `fix(ui): keep companion model animation continuous while rotating`

---

### Task 14：接入偏好、筛选、随机和召唤交互

**Files:**

- Modify: `addon/SoloCollections/UI/Pets.lua:180-560`
- Modify: `addon/SoloCollections/UI/CollectionsFrame.lua:245-280,560-590`
- Modify: `addon/SoloCollections/Core/Catalog.lua`
- Modify: `addon/SoloCollections/Core/Bridge.lua`

**Steps:**

1. [ ] `OpenFilterMenu` 构造收集状态、偏好和实际来源类别，改变状态后立即刷新。
2. [ ] 点击“设为偏好”调用 `Bridge.SetPetFavorite`；等待 type 17 delta 后更新排序和按钮文案。
3. [ ] 未收集记录的偏好按钮禁用，右键菜单也不能绕过该限制。
4. [ ] 顶部随机按钮调用 `Bridge.SummonRandomPet`，显示中文失败原因并在成功后刷新当前召唤状态。
5. [ ] 随机图标按“偏好已收集 → 已收集 eligible → fallback”更新，不使用未收集图标作为首选。
6. [ ] 底部按钮调用 `Bridge.SummonPet`，当前已召唤同一宠物时显示并执行解散。
7. [ ] 列表选择、筛选和偏好变更后保持选择可见；被过滤掉时选择排序后的第一条。
8. [ ] 刷新时进度总数只统计 journalVisible；筛选不改变全目录总数显示。

**Direct checks:**

```powershell
rg -n "SetPetFavorite|SummonRandomPet|SummonPet|OpenFilterMenu" .\addon\SoloCollections\UI\Pets.lua .\addon\SoloCollections\Core\Bridge.lua
git diff --check
```

**Expected:** 生产 UI 不调用本地 PETS favorite 真值；随机结果不在 Lua 中选择；菜单状态与排序刷新正确衔接。

**Commit:** `feat(ui): complete companion journal interactions`

---

### Task 15：跨仓相关检查与本地套件构建

**Files:**

- Modify only if required: `upstream/suite-lock.json`
- Generated only: `build/Interface/AddOns/*`（ignored）
- Generated only: `build/packages/*`（ignored）

**Steps:**

1. [ ] SoloCollections 运行 companion catalog、catalog generator、SC2、bridge、AddOn contract 的直接检查。
2. [ ] mod-solo-collections 在用户授权后生成 matching build metadata 并编译 worldserver。
3. [ ] SoloClientSuite 更新 SoloCollections sibling commit 与 DragonUI_NewEra hash 锁。
4. [ ] 运行 suite layout inspection。
5. [ ] 构建到仓库内 ignored `build/`；不直接覆盖真实客户端。
6. [ ] 检查构建 manifest 中的 AddOn commit、module build、mapping hash、metadataVersion、assetPackVersion 相互一致。

**Commands:**

```powershell
# SoloCollections
python .\tools\catalog\companion_catalog.py check --repo-root .
python .\tools\catalog\generate_catalog.py --companion-journal-only --check
$testPatterns = @(
  "test_companion_catalog.py",
  "test_catalog_generator.py",
  "test_sc2_protocol.py",
  "test_sc2_client_contract.py",
  "test_bridge_contract.py",
  "test_addon_contract.py"
)
foreach ($pattern in $testPatterns) {
  python -m unittest discover -s .\tools\collections\tests -p $pattern -v
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# SoloClientSuite
pwsh -File .\tools\Inspect-ClientSuiteLayout.ps1
pwsh -File .\tools\Build-ClientSuite.ps1 `
  -SoloCollectionsSource <SoloCollectionsAddonRoot> `
  -EzCollectionsSource <AuthorizedEzCollectionsRoot>
```

**Expected:** 所列相关检查全部通过；构建只写 ignored `build/`；锁文件和构建 manifest 指向最终逻辑提交。

**Commit (SoloClientSuite):** `chore(suite): lock pet journal parity build`

---

### Task 16：服务端部署门（需用户明确授权）

**Files/targets:** worldserver 二进制、characters SQL update（若 Task 6 确认需要）。

**Steps:**

1. [ ] 确认客户端已退出、worldserver 已停止，记录目标路径和现有二进制 SHA-256。
2. [ ] 创建可恢复备份；不得覆盖唯一副本。
3. [ ] 如有 append-only SQL，先确认目标数据库和 schema version，再应用迁移。
4. [ ] 安装新 worldserver/module 构建，记录新 SHA-256。
5. [ ] 启动 worldserver，检查模块注册、schema、mapping hash、目录数量和 SC2 capability 日志。
6. [ ] 登录一个已有收藏账号，确认 type 11/type 17 快照均可同步且没有加载错误。

**Expected:** worldserver 正常启动；无 schema/catalog mismatch；可随时恢复备份。

**State after success:** `SERVER_VALIDATED`，不是 `REAL_CLIENT_ACCEPTED`。

---

### Task 17：真实客户端功能与视觉验收

真实客户端验收逐项记录，不以截图之外的静态检查代替：

#### A. 启动与稳定性

- [ ] 登录或 `/reload` 不自动打开 DragonUI_NewEra 的其他窗口。
- [ ] 无 Lua 报错、UIDropDownMenu nil-name 报错、Localization.lua 报错或模型 provider 报错。
- [ ] 收藏窗口首次打开时间与已验收坐骑页同级，不出现明显长时间卡顿。

#### B. 页面与列表

- [ ] 小宠物页与坐骑页外框都是 768 × 606，标题、头像、进度、底部标签对齐。
- [ ] 搜索框和筛选按钮不越界。
- [ ] 10 个列表卡片全部位于列表容器内，首行/末行无裁切和溢出。
- [ ] 排序为偏好已收集 → 已收集 → 未收集，同组按国服中文名。
- [ ] 列表没有重复小宠物、交通工具、任务临时实体或职业临时召唤物。
- [ ] 绝版、促销、TCG、活动小宠物按审计结果正常显示。

#### C. 筛选与偏好

- [ ] 已收集、未收集、仅偏好筛选正确。
- [ ] 来源筛选类别和结果正确，不出现坐骑类型菜单。
- [ ] 已收集宠物可设置/取消偏好，重新登录仍保留。
- [ ] 未收集宠物的偏好按钮禁用，无法通过其他入口设置。
- [ ] 偏好变化后列表立即按既定顺序重排。

#### D. 详情与模型

- [ ] 图标、金色边框、名称和来源起点与坐骑页一致。
- [ ] 国服中文名、来源、费用和描述正确；金币数字与图标在同一行垂直居中。
- [ ] 无可核验描述时显示明确缺失文案，不出现 AI/账号收藏模板。
- [ ] 已收集和未收集状态正确。
- [ ] 模型可见，连续拖动旋转不重播动画、不出现一卡一卡的感觉。
- [ ] 滚轮缩放、重置视角、快速切换列表均正常；旧模型不会覆盖当前选择。

#### E. 召唤与随机

- [ ] 底部“召唤小宠物”按钮样式、尺寸、位置与坐骑页一致且不压边框。
- [ ] 召唤已收集宠物成功，再点同一宠物可解散。
- [ ] 未收集宠物不能召唤，提示中文。
- [ ] 随机按钮位于详情区右上方、图标正确、不与边框重叠。
- [ ] 有偏好时随机只从已收集偏好 eligible 池选择。
- [ ] 无偏好时随机从全部已收集 eligible 池选择。
- [ ] 多个候选时不会连续选择当前宠物；切换后只保留一个小宠物。
- [ ] 战斗、死亡、载具、飞行点等受限状态显示中文提示。

全部通过后，附客户端 build、AddOn/module commit、时间和证据路径，将本计划状态改为 `REAL_CLIENT_ACCEPTED`。

---

## 5. 逻辑功能提交与合并顺序

所有提交按“逻辑功能”组织，禁止一个提交混合目录、协议、服务端、UI 和套件锁：

1. SoloCollections `feat(catalog): audit companion journal identities`
2. SoloCollections `feat(catalog): add reviewed zhCN companion journal metadata`
3. SoloCollections `feat(catalog): project companion journal contract`
4. SoloCollections `feat(protocol): add companion favorites and random summon`
5. mod-solo-collections `feat(companions): persist account favorites`
6. mod-solo-collections `feat(companions): add authoritative random summon`
7. SoloClientSuite `feat(newera): generalize random collection control`
8. SoloCollections `feat(addon): bridge companion preferences and random summon`
9. SoloCollections `feat(addon): align companion catalog query semantics`
10. SoloCollections `feat(ui): align pet journal shell with mounts`
11. SoloCollections `feat(ui): add reviewed companion detail presentation`
12. SoloCollections `fix(ui): keep companion model animation continuous while rotating`
13. SoloCollections `feat(ui): complete companion journal interactions`
14. SoloClientSuite `chore(suite): lock pet journal parity build`

合并/部署依赖顺序：

```text
目录与协议规范
  → 模块生成投影、偏好和随机服务
  → DragonUI 公共视觉组件
  → AddOn Bridge、查询与页面
  → SoloClientSuite 最终锁定和本地构建
  → 服务端部署
  → 真实客户端验收
```

每次提交前只暂存该逻辑功能涉及的文件，并运行：

```powershell
git diff --cached --name-only
git diff --cached --check
git status --short
```

发现无关文件时取消暂存该文件，不修改或删除用户已有内容。

---

## 6. 最终交付记录模板

实施完成后在本文末尾追加，不覆盖计划正文：

```markdown
## Implementation Record

- SOURCE_COMPLETE: YES/NO
- STATIC_VALIDATED: YES/NO
- SERVER_VALIDATED: YES/NO
- REAL_CLIENT_ACCEPTED: YES/NO
- SoloCollections commit: <sha>
- mod-solo-collections commit: <sha>
- SoloClientSuite commit: <sha>
- AzerothCore commit/build: <sha-or-build-id>
- Catalog mapping hash: <hash>
- Module binary SHA-256: <hash>
- Client package SHA-256: <hash>
- Database migration applied: <none-or-file>
- Rollback backup: <external evidence id, no private absolute path>
- Real-client evidence: <external evidence id>
- Remaining known issues: <none-or-list>
```

只有 `REAL_CLIENT_ACCEPTED: YES` 才表示小宠物页已经达到用户可见验收；源码检查、编译成功或安装完成均不能单独声明验收通过。
