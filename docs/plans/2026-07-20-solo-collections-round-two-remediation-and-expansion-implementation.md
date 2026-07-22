# SoloCollections 第二轮展示修复与目录扩充实施方案

日期：2026-07-20

状态：待实施

设计与实施基线：

- [统一收藏后端设计](2026-07-19-solo-collections-unified-backend-design.md)
- [统一收藏后端第一轮实施方案](2026-07-19-solo-collections-unified-backend-implementation.md)

## 1. 本轮目标与完成定义

第一轮已经完成统一 C++ 收藏后端、SC2、账号级状态、五类 provider 和首批真实纵切。本轮不重做后端，而是在保留单一权威后端的前提下，修复生成目录切换后暴露出的展示回归，并把首批样本目录扩展为可审核、可重复生成的当前游戏目录。

本轮必须交付：

1. 坐骑与小宠物使用各自的原生图标，不再由 `Catalog.lua` 写死全局占位图标。
2. 在 `Backend=Cpp` 且 ALE 关闭时，坐骑和小宠物预览通过 SC2 完成 Creature Query 预热；全新客户端缓存不再出现“少数能显示、大多数空白”。
3. 坐骑、小宠物和玩具的收藏状态边框统一为细边，选中态与收藏态分层表达；玩具三列网格在内容区内对称居中。
4. 恢复第一轮目录切换前已经实机验证的 21 个独立武器模型，并禁止主副手在展示资源缺失时静默回退成“角色 + 武器”。
5. 以当前人类女性精调参数为参考，为 10 个原生种族、2 个性别、9 个外观部位生成首轮比例相机，并保留逐项人工校准能力。
6. 建立小宠物、玩具和 ItemSet 的证据提取、审核、稳定 ID 分配、生成与排除报告；不再依赖手写的 24/4/8 条首批样本。
7. 治理外观目录中的测试、废弃、内部和无可靠展示来源条目，避免 `Monster`、`Deprecated`、`TEST` 等内部内容直接暴露给玩家。
8. 所有静态测试、C++ 编译和真实 3.3.5 客户端验收都有可追溯证据；自动化通过不能替代模型、相机和像素布局验收。

本轮完成的判断标准不是“代码路径存在”，而是：

- 两个源代码仓库可从干净 checkout 加一个在 F 盘固定、带 SHA-256 manifest 的 evidence pack 重建全部生成物；外部 DBC/M2/数据库快照不伪装成 Git 内输入；
- C++ 仍是唯一生产动作与收藏写入 owner；
- 当前 281 个坐骑与本轮正式接受的小宠物，在空 WDB/首次预览条件下无空模型；
- 当前正式目录不存在统一占位图标；
- 21 个已验证武器只显示武器；
- 20 个种族/性别组合的 9 个部位、共 180 项全部完成第一轮可用性验收；
- 宠物、玩具和套装的每个候选都有 accepted、excluded 或 deferred 结论，而不是只增加一个未经审计的数量。

## 2. 当前基线与审计事实

审计日期为 2026-07-20。开始实施前必须再次记录实际 HEAD；以下是编写本方案时的基线：

| 仓库 | 审计 HEAD | 说明 |
|---|---|---|
| `SoloCollections` | `5c47e6e` | 第一轮统一后端实施方案已关闭 |
| `mod-solo-collections` | `c7504c3` | C++ 单写后端与五类 provider 已落地 |
| `azerothcore-wotlk` | `4cc67a3` | 当前 NPCBots/Core 集成基线；本轮优先不修改 Core |

实施开始前执行：

```powershell
git -C F:\1_projects\wow_projects\SoloCollectionsPlatform\SoloCollections status --short --branch
git -C F:\1_projects\wow_projects\SoloCollectionsPlatform\mod-solo-collections status --short --branch
git -C F:\1_projects\wow_projects\azerothcore-wotlk status --short --branch
```

Core 工作树中现有的未跟踪文件或用户修改不属于本轮，不得暂存、覆盖或清理。生成报告、临时 DBC 解包、构建目录和真实客户端资源均留在明确的 F 盘工作目录或既有部署位置，不进入源代码仓库。

### 2.1 当前目录规模

| 类别 | 当前正式目录 | 审计候选或现有资源 | 结论 |
|---|---:|---:|---|
| 坐骑 | 281 | 281 条均有 World 模板和客户端 Display 资源 | 目录规模不是空模型根因 |
| 小宠物 | 24 | 当前部署快照约 201 个资源就绪原始候选 | 24 是人工审核首批，不是 UI 上限 |
| 玩具 | 4 | 旧 SC1 原型 36 条 | 4 是四种动作语义样例，不是完整玩具箱 |
| canonical 外观 | 18,190 | 主副手组约 5,957，独立武器资源仅 21 个 | 收藏目录与独立展示资源规模不同 |
| 套装 | 8 | `ItemSet.dbc` 509 个原始审核单元；475/466/约465/约438 是 nonempty/mapped/distinct-signature/full 的诊断漏斗 | 8 是手写 T1 首批，并漏掉牧师 T1 |

“约 201 个宠物”是当前快照的候选基线；套装的审核分母是 509 个 ItemSet DBC 行，约 465/438 只是去重签名/完整映射诊断值。它们都不是预先承诺的最终正式数量；证据 Hash、排除策略或数据版本变化时必须重新审核。

### 2.2 已确认根因

| 问题 | 当前代码事实 | 根因分类 |
|---|---|---|
| 坐骑图标相同 | `Core/Catalog.lua` 为所有生成坐骑写入 `Ability_Mount_RidingHorse` | 生成目录丢失展示元数据 |
| 宠物图标相同 | `Core/Catalog.lua` 为所有生成宠物写入 `INV_Box_PetCarrier_01` | 生成目录丢失展示元数据 |
| 坐骑/宠物模型大面积空白 | `Bridge.lua` 的预览仍发送 SC1 `MODEL/PET_MODEL`，而 C++ 模式禁用 ALE；UI 又忽略失败结果 | 后端切换遗漏只读预览链路 |
| 武器显示角色 | canonical 外观投影没有保留 `modelPath`、synthetic display、缩放和 M2 相机，主副手被判定为 `BODY` | 生成目录切换回归 |
| 其他种族相机错误 | Lua 和 SoloCam 仅有人类女性精调表，其余使用同一通用 fallback | 相机身份矩阵未实现 |
| 粗黄框 | 64×64 状态框素材每边有 10px 不透明带，被拉伸覆盖小图标 | UI 素材使用方式错误 |
| 玩具首列贴边 | 848px 网格中三列固定占 846px，只剩左右各 1px | 固定魔法数布局 |
| 宠物/玩具/套装数量少 | 原计划明确只上线 24/4/8 首批目录 | 内容审核流水线尚未扩充 |

### 2.3 现有测试为何没有阻止问题

- `test_addon_contract.py` 冻结了玩具 `TILE_WIDTH=282`，但没有验证左右 margin。
- `test_sc2_client_contract.py` 只检查存在 `displayCreatureId`，没有检查该字段的 ID 语义或 C++ 预热可用性。
- `test_set_catalog.py` 和 `test_catalog_contract.py` 明确断言套装数量等于 8。
- 图标合同只允许占位字段存在，没有要求正式 WotLK 目录零占位。
- 武器测试验证独立渲染器仍存在，但没有验证 canonical 适配后展示字段仍能到达渲染器。
- 静态测试无法发现空 WDB、UI Scale、模型加载时序或真实相机裁切问题。

## 3. 范围、非目标与强制不变量

### 3.1 本轮范围

- `SoloCollections`：目录源、证据提取器、生成器、AddOn 适配层、页面 UI、SoloCam 配置生成、合同测试和验收文档。
- `mod-solo-collections`：SC2 预览动作、可信 Creature Entry 解析、查询预热、目录读取和对应原生/合同测试。
- 当前 3.3.5.12340 客户端数据与当前 World DB：只作为固定版本的提取输入和真实运行验收环境。
- 现有 281 个坐骑、已接受及新增小宠物、审核后的旧玩具候选、当前游戏 ItemSet，以及第一批 21 个独立武器展示资源。

### 3.2 本轮明确不做

- 不重新启用 ALE 作为生产动作后端或模型预览后端。
- 不建立第二套收藏数据库、revision、owned 状态或并行写入服务。
- 不让客户端提交 spellId、Creature Entry、DisplayInfo ID、source itemId 或 owned 位来决定服务端动作。
- 不在本轮为全部约 5,957 个主副手 canonical 外观生成独立 M2/DBC/MPQ 资源；本轮只恢复 21 个已验证资源并建立后续可扩展合同。
- 不把所有拥有 Use Spell 的物品自动归类为玩具。
- 不把约 201 个宠物候选或 509 个 ItemSet 审核单元未经逐项审核直接全部设为 active。
- 不导入高版本坐骑、宠物、玩具、套装或 HD 模型。
- 不把提取的 Blizzard DBC、M2、BLP、MPQ、客户端 DLL/EXE 或数据库转储提交到 Git。
- 不自动推送远程、创建发布或修改正式数据库；这些需要后续明确授权。

### 3.3 强制不变量

1. **单写不变**：C++ 继续独占生产收藏写入和动作执行；预览是只读能力，不产生 unlock、revision、数据库或游戏世界副作用。限流计数、replay cache、结构化日志和协议响应属于必要的瞬时可观测性，不在“无收藏/世界副作用”之列。
2. **逻辑 ID 不变**：SC2 请求仍只携带 `typeId + collectionId + actionId + target`；服务端从自身目录解析一切运行 ID。
3. **稳定 ID 不变**：现有 collection ID 不重排、不复用；被移除条目保留 tombstone。新增宠物不能占用已有玩具的 `100305..100308`。
4. **数据版本可重建**：所有提取输入记录 build、SHA-256、候选 Hash 和审核策略 Hash；输入漂移时生成器 fail closed。
5. **展示失败隔离**：图标、相机、模型或独立武器资源缺失只能禁用该条目的展示，不得让 worldserver、整个收藏页或其他 provider 失败。
6. **身份可扩展**：相机和套装资格使用逻辑 race/class key、sex key、capability/profile，不把 3.3.5 固定枚举散落进 UI 与业务逻辑。
7. **真实客户端验收**：模型、相机、边框、武器隔离和分页必须在真实客户端验证；“编译成功”与“hook 已安装”都不是最终视觉验收。

### 3.4 术语、生命周期与状态边界

为避免实施者依赖第一轮口头上下文，本方案统一使用以下术语：

| 术语 | 本方案中的唯一含义 |
|---|---|
| ALE | 第一轮遗留的 AzerothCore Lua Engine 服务端脚本；本轮保持禁用，既不写收藏也不提供正式模型预览 |
| SC1 | 旧 Lua/ALE 消息路径，包含 `MODEL/PET_MODEL`；只作迁移证据，不是生产入口 |
| SC2 | 当前 `Q/R` envelope、握手、快照、delta 和动作协议；C++ 是服务端实现 |
| provider/category ready | C++ provider 已加载、schema 正常且该类别 mapping hash 与客户端声明一致，允许处理该类请求 |
| canonical appearance | type 13 的稳定外观身份；多个来源物品可以归并到同一个 canonical collection |
| type 13 / type 14 | type 13 是外观 owned 的持久身份；type 14 是由 type 13 即时推导的套装完成投影，不单独写 owned |
| mapping hash | 对服务端会解释或授权的规范化字段计算的 SHA-256；不一致时对应 SC2 category 动作 fail closed |
| presentation hash | 对客户端只读展示投影计算的 SHA-256；用于生成、组包和本地部署一致性，不授权服务端动作 |
| asset manifest hash | 对 SoloCam DLL、synthetic DBC、M2/skin/texture 等实际文件的相对路径、大小和 SHA-256 规范化后再计算的 SHA-256 |
| protocol/metadata/assetPack version | `protocolVersion` 标识 wire layout；`metadataVersion` 标识服务端可解释的目录合同；`assetPackVersion` 标识客户端 DLL/DBC/M2 配套包，三者不得互相代替 |
| presentation status | `ready/verified/unavailable`；ready 表示字段完整，verified 表示已过对应实机证据，unavailable 表示只显示安全 fallback |
| sentinel | AddOn 与 SoloCam 间选择相机 profile 的私有数值请求码，不是 collection ID、DisplayInfo ID 或协议字段 |
| logical px | WoW UI 坐标中的 1 单位；最终物理像素宽度受游戏 UI Scale 与本窗体 scale 影响，因此还需截图验收 |
| fixed evidence pack | F 盘只读目录，包含被允许的 DBC/M2/脱敏 DB 快照或其解析产物及 `evidence-manifest.json`；不提交 Git |

生命周期拆成两列，禁止用一个模糊 `lifecycle` 同时控制 UI 和服务端动作：

| `catalogLifecycle` | mount/companion PREVIEW | SUMMON/USE/APPLY | ID/owned |
|---|---|---|---|
| `ACTIVE` | 允许 | 按 owned/资格继续校验 | 保留 |
| `PREVIEW_ONLY` | 允许 | 拒绝 `UNSUPPORTED` | 保留 |
| `DISABLED` | 拒绝 `UNSUPPORTED` | 拒绝 `UNSUPPORTED` | 保留 |
| `TOMBSTONE` | 拒绝 `INVALID_REQUEST` | 拒绝 `INVALID_REQUEST` | ID 永久保留，owned 行不删 |

`uiLifecycle` 只决定普通目录可见性：`public` 与 `unobtainable` 可以进入玩家目录；`hidden_internal/deprecated/test/deferred` 只进入审核或 QA 投影。正常 AddOn 不为后五类发 PREVIEW。若某条需要“可看不可用”，必须显式组合 `uiLifecycle=public|unobtainable` 与 `catalogLifecycle=PREVIEW_ONLY`，不能靠名称猜测。

## 4. 目标数据与协议契约

本轮把同一条收藏记录拆成两个清晰平面：

| 平面 | 责任 | 权威性 |
|---|---|---|
| 收藏/动作平面 | collection ID、owned、revision、资格、spell/item/handler 解析、费用和副作用 | C++/数据库权威 |
| 客户端展示平面 | 图标、预览 Creature Entry、展示 item、M2/DBC 资源、相机、边框和名称 | 只读投影，不授权动作 |

客户端展示字段可以来自同一固定证据源，但不能被服务端动作入口信任。

### 4.1 Creature 类展示字段

生成目录目标字段：

```json
{
  "typeKey": "mount",
  "collectionId": 100001,
  "previewCreatureEntry": 12345,
  "iconSpellId": 67890,
  "iconTexture": "Interface\\Icons\\Ability_Mount_Example",
  "presentationStatus": "ready"
}
```

规则：

- 将当前误导性的 `displayCreatureId` 重命名为 `previewCreatureEntry`。坐骑 `creatureIds` 与宠物 `creatureId` 都是 Creature Entry，不是 `CreatureDisplayInfo.dbc` ID。
- `previewDisplayInfoId` 如未来需要，必须使用另一个独立字段，禁止复用 Entry 字段名。
- `iconSpellId` 用于证据追踪；`iconTexture` 是客户端直接显示值。正式 WotLK active 条目必须有非空图标。
- 为兼容一个 metadata 过渡版本，生成器可以同时输出旧 `displayCreatureId` alias；所有 Lua 消费者迁移后立即删除 alias，不长期维护双字段。

### 4.2 SC2 `PREVIEW` 动作

沿用现有 `Q/R` wire envelope，不增加第二套协议：

```text
Q|nonce|requestId|10|mountCollectionId|PREVIEW|-
Q|nonce|requestId|11|companionCollectionId|PREVIEW|-
R|nonce|requestId|ACCEPTED|typeId|collectionId|revision
```

语义：

- `PREVIEW` 不要求已收藏，未收藏条目也允许在收藏日志中预览。
- 请求仍受 nonce、重放、限流、类别 ready 和 mapping hash 保护。
- 服务端只接受 mount/companion 类型和 `target="-"`，从对应 C++ 目录解析可信 Creature Entry。
- 服务端确认 `CreatureTemplate` 与至少一个显示模型存在，先向当前 session 发送 Creature Query 响应，再返回 `ACCEPTED`。
- 成功状态复用现有 `ACCEPTED`，避免仅为成功文案升级 wire 布局；失败复用 `INVALID_REQUEST`、`ASSET_MISMATCH`、`DB_UNAVAILABLE`、`RATE_LIMITED` 等稳定状态。
- 预览不得调用召唤 service、不得检查 owned、不得施法、不得生成实体、不得写 DB 或 revision。

### 4.3 独立武器展示字段

```json
{
  "appearanceId": 200000,
  "presentationKey": "weapon.item.19364",
  "renderMode": "STANDALONE",
  "syntheticDisplayId": 40000,
  "modelPath": "Item\\ObjectComponents\\SoloCollections\\Example.m2",
  "modelScale": 0.82,
  "cameraTuningKey": "TWO_HAND_SWORD",
  "m2Camera": {},
  "assetPackVersion": "wotlk-3.3.5a-local-1",
  "presentationStatus": "verified"
}
```

`renderMode` 只允许：

- `BODY`：护甲、披风等角色试穿展示；
- `STANDALONE`：具有经过验证的独立模型资源；
- `UNAVAILABLE`：主副手没有独立资源，只显示图标和明确提示。

主副手不得因为字段缺失自动回退为 `BODY`。

### 4.4 角色相机字段

单一 JSON 源生成 Lua 查找表和 C++ `inc`：

```json
{
  "assetPackVersion": "wotlk-3.3.5a-stock-1",
  "clientAssetProfile": "race.tauren",
  "sexKey": "female",
  "slot": "HEAD",
  "sentinel": 123456,
  "status": "scaled",
  "verticalOffset": 0.0,
  "distanceScale": 1.0,
  "minimumDistance": 0.0,
  "horizontalOffset": 0.0,
  "yawOffset": 0.0,
  "sourceProfile": "race.human:female:HEAD"
}
```

- 主键为四元组 `(assetPackVersion, clientAssetProfile, sexKey, slot)`，四项缺一不可；运行时通过 `IdentityRegistry` 的逻辑 race key 解析，不直接以易漂移的 runtime race ID 作为持久键。
- `status` 为 `reference`、`scaled` 或 `verified`。
- human/female 的 9 条现有值必须逐位保持不变，作为 reference。
- 未知、自定义或 asset profile 不匹配时回退原生 camera 1，不得猜测最近种族。

### 4.5 套装资格字段

将单值：

```json
{"classToken": "MAGE"}
```

迁移为：

```json
{"classPolicy": {"mode": "ALLOW_LIST", "allowedClassKeys": ["mage"]}}
```

不限职业必须写成 `{"mode":"ANY","allowedClassKeys":[]}`；不能只靠空数组猜 mode。过渡期生成器可以读取旧 `classToken`，但新输出、Lua 过滤和 C++ 资格检查只使用完整 `classPolicy`。难度、配色、阵营或同模型变体只能由显式 override 合并，不根据名称猜测。

### 4.6 Hash 与版本规则

所有 Hash 都使用 UTF-8、LF、按 schema 声明的稳定键排序、无无意义空白的 canonical JSON，再计算小写 SHA-256。绝对路径、时间戳、数据库连接信息和机器名不得进入 Hash 输入。

| 合同 | 规范化输入 | 生成/存放 | 消费方与 mismatch 行为 |
|---|---|---|---|
| type mapping hash | `typeId`、collection ID/key、`catalogLifecycle`、服务端 action identity；mount/companion 还包含 `previewCreatureEntry` | `catalog-manifest.json`、AddOn generated constants、`SoloCollectionsProtocolCatalog.inc` | SC2 握手/category map；不一致时该类 PREVIEW/SUMMON/USE/APPLY 返回 `CATALOG_MISMATCH` |
| presentation hash | collection ID/key、名称/描述、icon、`uiLifecycle`、`renderMode`、presentation status、客户端预览字段；`previewCreatureEntry` 因客户端也消费而在此重复出现 | `catalog-manifest.json`、`Generated/Catalog.lua` 常量、release manifest | `generate_catalog.py --check` 与组包/安装脚本；不一致时拒绝组包或切到该条 `UNAVAILABLE`，不改变 owned |
| camera profile hash | 四元主键、sentinel、全部展开后的浮点参数和 profile status | Lua/C++ 生成表与 release manifest | AddOn/SoloCam build contract；不一致时相机回退 `Native` |
| asset manifest hash | 资源相对路径、大小、单文件 SHA-256、`assetPackVersion` | 本地 asset manifest 与 release manifest | 组包、安装和启动前本地 verifier；不一致时独立武器/相机资源 fail closed |
| evidence/review-policy hash | 输入文件 SHA-256、提取器版本、审核决定与理由 | review evidence/report | 生成器；漂移时必须重新审核，禁止自动改 active 目录 |

版本提升规则：

- collection identity、目录数量、`catalogLifecycle`、服务端动作映射或 `previewCreatureEntry` 变化：提升 `metadataVersion` 并重算受影响 type mapping hash。`previewCreatureEntry` 进入 mount/companion mapping，因为服务端预热和客户端 `SetCreature` 必须指向同一个 Entry。
- 纯图标、名称、描述、`uiLifecycle`、边框或布局变化不改变动作 mapping hash；数据字段变化重算 `presentationHash`，纯代码布局变化只改变 commit/release manifest。
- SoloCam DLL、synthetic DBC、M2/材质或相机 profile 与资源包耦合变化：提升 `assetPackVersion` 并重算 camera/asset hash。
- `ASSET_MISMATCH` 只表示 SC2 握手中客户端声明的 `assetPackVersion` 与服务器要求不兼容；服务器无法验证玩家磁盘上的 DLL/MPQ。磁盘文件缺失或 SHA 不符由本地 bundle verifier/SoloCam build metadata 判定并在 UI 显示 `UNAVAILABLE`，不得伪称服务端已验证。
- `PREVIEW` 复用现有 Q/R 布局时不提升 `protocolVersion`；若实际实现改变 wire 字段或状态编码，必须提升协议版本并保留最多一个过渡握手版本。

## 5. 阶段 0：冻结证据并建立失败基线

阶段目标：在修改行为前固定当前数据版本、生成物、错误路径和真实客户端复现条件，防止后续把“缓存碰巧已有模型”误判为修复。

### 任务 0.1：记录两仓库和运行数据基线

- [x] 已完成（2026-07-22）。已冻结 AddOn/module/Core commit、版本与目录 Hash、正式 `281/24/4/8` 分母、9 个 DBC 输入、21 个独立武器、人类女性 9 条相机、玩具网格/TGA alpha 测量和空 WDB 六点失败截图；生成脱敏 evidence pack `round2-20260722-baseline-v2c` 与固定工具链 manifest，详情见 `docs/reports/2026-07-20-round-two-audit-baseline.md`。

仓库：`SoloCollections`、`mod-solo-collections`

新增建议：

```text
docs/reports/2026-07-20-round-two-audit-baseline.md
```

报告至少记录：

- 两个仓库和 Core 的 commit；
- `versions.json`、目录 mapping hash、mount action hash、当前数据库/DBC 证据 Hash；
- 当前 281/24/4/8 条正式记录；
- 21 个旧独立武器 itemId、synthetic display ID、M2 path、相机 key 和资源包 Hash；
- 当前人类女性 9 个 sentinel/profile 的逐值快照；
- 当前玩具网格几何值和两张状态框 TGA 的 alpha 边带测量；
- 当前空 WDB 条件下首、中、末坐骑/宠物预览结果。

同时新增一个不含凭据的工具链/evidence manifest：

```text
docs/reports/2026-07-20-round-two-toolchain-manifest.json
F:\1_projects\wow_projects\SoloCollectionsPlatform\SoloCollections\_work\evidence\<evidenceId>\evidence-manifest.json
```

前者只记录 Python、CMake、CTest、MSVC x86/x64、可选 Lua 5.1 `luac`、DBC/M2/MPQ 解析器的版本和 SHA-256，以及 evidence ID；后者记录 F 盘 evidence pack 内每个输入的相对路径、大小、SHA-256、客户端 build/locale、World 快照查询版本和脱敏状态。生成器只接受 `--evidence-root` 指向该 manifest 所在目录；缺文件、Hash 漂移或路径落到 C 盘时 fail closed。21 个已验证武器的 resource manifest 也必须作为 evidence pack 的命名成员被定位，不能靠实施者记忆寻找。

不得把数据库口令、完整 DBC、客户端缓存、截图临时路径或客户端二进制写入报告。

### 任务 0.2：建立可重复的失败用例

- [x] 已完成（2026-07-22）。阶段 1–9 均先以 fail-closed 合同覆盖默认图标、SC1 依赖、失败 callback、缺资源 BODY、玩具 margin、相机 sentinel、宠物/玩具/套装身份与动作、外观可见性和 release 安装恢复，再随对应修复转为长期回归；Addon 239 项、module 133 项与 native 2 项最终通过。

每个修复任务先在工作分支中补一个会失败的合同测试，再与修复一起提交；不得把“当前错误行为”写成长期通过的测试。

最低失败用例：

- active 坐骑/宠物展示记录禁止全部使用单一默认图标；
- C++ backend 模式下预览不得依赖 `B.connected`、`SC1 MODEL` 或 `PET_MODEL`；
- 预览 callback 返回失败时，`Mounts.lua`/`Pets.lua` 不得调用 `SetCreature`；
- canonical 主副手缺少独立展示资源时不得进入 `BODY`；
- 玩具网格左右 margin 差不得超过 1 logical px；
- 相机源必须覆盖 10×2×9 并保持 human/female reference 精确不变；
- 套装合同不得把“数量等于 8”作为正确性条件。

### 任务 0.3：定义空缓存验收方法

- [x] 已完成（2026-07-22）。已实现 fail-closed 的备份/恢复状态机、逐步 append-only journal、测试期间新 WDB 隔离清单和幂等恢复；4 个自动测试通过，并在 `D:\Games\wow335\World of Warcraft11` 的实际 `zhCN` WDB 上完成 9 文件备份后原样恢复与 Hash 核对。实际冷启动扫描结果继续记录在任务 0.1 基线报告和阶段 2 实机验收中。

- 实现 `tools/runtime/Backup-ClientWdb.ps1` 与 `Restore-ClientWdb.ps1`。脚本接收显式 `-ClientRoot`、`-Locale` 和 F 盘 `-BackupRoot`，解析并验证目标位于 `<ClientRoot>\Cache\WDB\<locale>` 内；先复制并生成 SHA-256 manifest，再把原目录改名为同根的 `.cold-test-<timestamp>`，不直接递归删除不明目录。
- 验收命令合同：

  ```powershell
  $clientRoot = 'F:\<实际测试客户端根目录>'
  $backupRoot = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\SoloCollections\_work\wdb-backups\<timestamp>'
  & .\tools\runtime\Backup-ClientWdb.ps1 -ClientRoot $clientRoot -Locale enUS -BackupRoot $backupRoot
  # 完成冷缓存验收并关闭客户端后
  & .\tools\runtime\Restore-ClientWdb.ps1 -ClientRoot $clientRoot -Locale enUS -BackupRoot $backupRoot
  ```

  `<实际测试客户端根目录>` 是运行时参数，不得把个人客户端绝对路径写入 Git。脚本必须拒绝客户端仍在运行、备份 manifest 不匹配或目标不在显式 F 盘根目录的情况。

恢复必须是可恢复的状态机，而不是覆盖：

1. backup manifest 记录原目录、`.cold-test-<timestamp>` 名称、旧缓存逐文件 Hash 和状态 `BACKED_UP`。
2. 客户端冷启动后若在原路径生成了新 WDB，`Restore-ClientWdb.ps1` 先将这套新目录同卷改名并移动到 `$BackupRoot\generated-during-test\<timestamp>\`，生成独立 Hash manifest；不得覆盖、合并或删除。
3. 再把 manifest 指定的旧 `.cold-test-*` 目录同卷改回原路径并逐文件核对旧 Hash；只有旧改名目录丢失时才允许从 backup copy 恢复。
4. 成功后把 journal 状态原子更新为 `RESTORED`。重复执行 restore 只核对已恢复 Hash并返回成功；发现 `RESTORING`、部分移动、目标冲突或 Hash 不同则保留所有目录、返回失败并输出人工恢复步骤，绝不递归清理。
5. Backup/restore 的每一次 rename/move 都先写 append-only operation journal，确保断电后能判断哪个目录是旧缓存、哪个是测试缓存。
- 验收记录必须说明客户端 build、locale、AddOn commit、module commit、DLL/资源包 Hash 和 WDB 状态。
- 分别记录“首次点击”“快速连续切换”“返回前一个条目”“`/reload`”“重登”结果。
- 不允许先访问 NPC、召唤坐骑或用旧客户端预热缓存后再宣称预览通过。

阶段出口：

- 基线报告完整且不含敏感数据或外部资产；
- 每个已知问题都有可重复的自动或实机复现步骤；
- 生成器 `--check` 通过，两个项目仓库工作树除本方案/报告外无非预期修改。

建议提交：

```text
docs: record round two regression baseline
```

## 6. 阶段 1：补齐客户端展示投影与原生图标

阶段目标：把展示元数据作为明确、可审核的只读投影生成出来，首先修复坐骑和宠物图标，并消除 Creature Entry/DisplayInfo 命名混淆。

### 任务 1.1：生成 Creature 类展示证据

- [x] 已完成（2026-07-22）。新增 fail-closed `creature_presentations.py`，以命名 evidence pack 输入解析 `Spell.dbc`/`SpellIcon.dbc`，并从只读 World 查询生成 24/24 READY 的宠物 CreatureTemplate/Display 证据；正式投影为 281 个坐骑 101 个不同图标、24 个宠物 23 个不同图标，零缺失。

仓库：`SoloCollections`

主要文件：

```text
tools/catalog/mount_catalog.py
tools/catalog/creature_presentations.py              # 新增建议
catalog/review/mounts/evidence.json
catalog/review/companions/evidence.json
catalog/source/creature_presentations.json           # 新增建议
```

实现：

- 从当前固定 `Spell.dbc` 的 spell 记录取得 `SpellIconID`，联接 `SpellIcon.dbc` 得到原生纹理路径。
- 坐骑使用每个逻辑组的 canonical action spell 作为图标证据；小宠物使用审核 action spell。
- 同时写入 `iconSpellId`、`iconTexture`、`previewCreatureEntry`、来源 build 和源文件 SHA-256。
- 纹理路径只用于客户端显示；不得把 icon spell 当作召唤 spell，也不得加入 SC2 动作参数。
- active WotLK 条目缺图标、缺 CreatureTemplate 或缺 Display 资源时生成失败；disabled/excluded 条目记录原因。
- 当前快照预期 281 个坐骑零图标缺失、约 101 个不同图标；现有 24 个宠物零缺失、约 23 个不同图标。不同条目合法共享图标不视为错误。

### 任务 1.2：扩展主目录生成器

- [x] 已完成（2026-07-22）。`generate_catalog.py` 已按 `(typeKey, collectionId)` 联接 305 条 presentation，输出 `previewCreatureEntry`、原生图标字段、`presentationStatus`、独立 presentation hash 和单版本 deprecated alias；`metadataVersion` 提升至 `2026.07.22.1`，asset pack 未变化，并用合同测试证明纯图标变更不污染 mapping hash。

主要文件：

```text
tools/catalog/generate_catalog.py
addon/SoloCollections/Data/Generated/Catalog.lua
catalog/generated/catalog-manifest.json
catalog/source/versions.json
```

实现：

- `generate_catalog.py` 按 `(typeKey, collectionId)` 联接 `creature_presentations.json`。
- 客户端 Lua 投影输出 `previewCreatureEntry`、`iconSpellId`、`iconTexture` 和 `presentationStatus`。
- 过渡版可以同时输出 `displayCreatureId = previewCreatureEntry`，但生成报告必须把它标记为 deprecated alias。
- `previewCreatureEntry` 进入现有 type mapping hash；纯 `iconTexture` 等客户端显示字段进入独立 `presentationHash`。原始绝对数据路径和数据库连接信息不参与任一 Hash。
- 提升 `metadataVersion`。只有 collection/preview Entry 映射变化时才重算 mount/companion type mapping hash；纯图标修复只更新 presentation hash。只在实际客户端资源包变化时提升 `assetPackVersion`。

### 任务 1.3：迁移 AddOn 适配层

- [x] 已完成（2026-07-22）。生成目录分支已改用逐条 `iconTexture` 和 `previewCreatureEntry`，保留 3.3.5 图标裁切且不再出现整类马/宠物笼图标；冷 WDB 实机覆盖坐骑代表类别与全部 24 个宠物，列表/详情和 `/reload` 均通过。模型预览明确仍留给阶段 2，证据见 `docs/reports/2026-07-22-stage1-creature-presentations.md`。

主要文件：

```text
addon/SoloCollections/Core/Catalog.lua
addon/SoloCollections/UI/Mounts.lua
addon/SoloCollections/UI/Pets.lua
addon/SoloCollections/UI/Templates.lua
```

实现：

- `Catalog.lua` 使用 `collection.iconTexture`，不再为整类写死马或宠物笼图标。
- UI record 内部把 `creatureId` 逐步改名为 `previewCreatureEntry`；兼容读取只保留一个 metadata 过渡版本。
- 占位图仅作为单条 disabled/unavailable 记录的视觉 fallback，不能让 active 目录整体悄悄通过。
- 图标裁切继续使用 `SetTexCoord(0.07, 0.93, 0.07, 0.93)`。

### 自动测试

- active mount/companion 展示记录全部具有可解析的 `iconTexture` 和正数 `previewCreatureEntry`；
- 禁止 `Catalog.lua` 在生成目录分支出现全局硬编码的 `Ability_Mount_RidingHorse` 或 `INV_Box_PetCarrier_01`；
- DBC Hash 或 review-policy Hash 改变时生成失败；
- 同一输入连续生成字节一致；
- 客户端目录不包含可用于服务端召唤授权的 action spell 字段；
- compatibility alias 删除后测试确保没有 Lua 消费者继续读取 `displayCreatureId`。

### 真实客户端验收

- 坐骑至少抽样地面、飞行、机械、龙类、职业坐骑和同图标合法重复组；
- 现有 24 个宠物全部滚动检查图标；
- 搜索、过滤、已收集/未收集、详情图标与列表图标一致；
- `/reload` 和物品/法术冷缓存条件下不退回全局占位图。

阶段出口：图标回归完成，字段语义明确，尚未声称模型预览已修复。

建议提交：

```text
catalog: generate native collection presentation icons
addon: consume typed creature presentation metadata
```

## 7. 阶段 2：将模型预览迁移到 C++/SC2

阶段目标：在不恢复 ALE、不建立第二后端的前提下，为坐骑和宠物提供只读、可信、可限流的模型预热路径。

### 任务 2.1：增加服务端 Creature Preview service

- [x] 已完成（2026-07-22）。新增只接收 `Player/typeId/collectionId` 的只读 preview service，以同源 generated catalog 解析可信 Entry，复用审计 commit `4cc67a3` 的 Creature Query handler；实际配置支持 `.transmog reload` 热关闭/恢复，clean Core x64 RelWithDebInfo 已构建并部署验证。

仓库：`mod-solo-collections`

新增建议：

```text
src/SoloCollectionsCreaturePreviewService.h
src/SoloCollectionsCreaturePreviewService.cpp
```

修改：

```text
../SoloCollections/tools/catalog/generate_catalog.py
src/SoloCollectionsMountCatalog.h
src/SoloCollectionsMountCatalog.cpp
src/SoloCollectionsCompanionCatalog.h
src/SoloCollectionsCompanionCatalog.cpp
src/generated/SoloCollectionsMountCatalog.inc
src/generated/SoloCollectionsCompanionCatalog.inc
src/SoloCollectionsProtocolScript.cpp
src/SoloCollectionsProtocol.cpp
tests/native/CMakeLists.txt
tests/native/SoloCollectionsProtocolTests.cpp
tests/native/SoloCollectionsDomainTests.cpp
tests/test_phase5_protocol_contract.py
tests/test_phase6_mount_unlock_contract.py
tests/test_phase7_companion_toy_contract.py
```

service 输入只能是：

```cpp
Player* player;
CollectionTypeId typeId;
CollectionId collectionId;
```

处理顺序：

1. 验证 session/account 与当前 Player 一致。
2. 只接受 mount/companion provider 且类别 ready。
3. 从 `SoloCollectionsMountCatalog` 或 `SoloCollectionsCompanionCatalog` 查找 logical collection，并按 3.4 的 `catalogLifecycle` 矩阵决定 PREVIEW 是否允许。
4. 从服务端生成目录的 `PreviewCreatureEntry` 解析可信 Creature Entry，不接受客户端传入 Entry 或 Display ID。mount/companion C++ definition、两个 generated inc 和 Lua 投影必须由同一次 `generate_catalog.py` 运行产生。
5. 验证 `sObjectMgr->GetCreatureTemplate(entry)` 和至少一个模型。
6. 复用当前 Core 的 Creature Query 生成路径向该 session 发送响应。
7. 查询包排队后返回 `ACCEPTED`；任何目录/资源失败返回稳定 reason，且不产生收藏持久化或游戏世界副作用。replay cache、token 消耗、日志和发包仍正常发生。

当前 Core 分支公开 `WorldSession::HandleCreatureQueryOpcode(WorldPacket&)`。模块优先通过一个很薄的 adapter 构造包含可信 Entry 与空 GUID 的内部 Creature Query，并调用现有 handler；禁止在模块里复制整段 `SMSG_CREATURE_QUERY_RESPONSE` 字段布局。只有当前 Core 无法安全复用该路径且编译证据证明必须修改时，才另行提出最小 Core helper 补丁，本方案不预先授权 Core 改动。

adapter 实施前必须逐行核对审计 commit `4cc67a3` 上 handler 的输入读取顺序，并在基线报告记录函数签名、请求 opcode、Entry/GUID 字段宽度和源码行；集成测试用一个已知 Entry 与一个不存在 Entry 抓取响应，证明没有 ABI 假设或错位包。若 Core HEAD 已漂移，重新审计后再编译，不能把旧 packet 布局硬编码进模块。

在 `conf/transmog.conf.dist` 增加分发默认值：

```ini
SoloCollections.Preview.Enabled = 1
```

安装脚本必须把该项合并到部署 profile 明确指定的实际运行文件 `<server-config-root>\modules\transmog.conf`，而不是只修改 `.dist`。当前模块已有 `.transmog reload`，所以纯配置回滚流程为：把实际运行文件设为 `0`，在 worldserver 控制台执行 `.transmog reload`，再用 `.solocollections status` 和一条 PREVIEW 验证 `UNSUPPORTED`；若新增 service 的配置缓存没有接入现有 reload 路径，则必须重启 worldserver 并在报告中说明。实际配置路径只保存在 Git 忽略的 `_work/deployment-profile.local.json`。

关闭时只让 PREVIEW 返回 `UNSUPPORTED`；不得因此启用 ALE 或影响 SUMMON/USE/APPLY。

### 任务 2.2：接入现有 SC2 Q/R

- [x] 已完成（2026-07-22）。SC2 Q 已接入 PREVIEW，所有动作执行 metadata 总闸门、PREVIEW 另执行 asset pack 闸门，并复用 nonce/replay/burst 12 + 6 token/s/结构化日志；native 测试证明未收藏 PREVIEW 可用而 SUMMON 仍为 `NOT_OWNED`，无持久化或实体副作用。

请求：

- mount：`typeId=10, actionId=PREVIEW, target=-`
- companion：`typeId=11, actionId=PREVIEW, target=-`

修改 `SoloCollectionsProtocolScript.cpp`：

- 对 `PREVIEW` 调用 preview service；
- 对现有 `SUMMON` 保持原 owned、资格和动作校验；
- `PREVIEW` 与 `SUMMON` 不共享能改变实体或收藏状态的函数；
- 继续使用 nonce、replay cache、token bucket 和 category ready；
- 记录结构化日志：account、character、type、collection、entry、status、elapsed，不记录玩家输入的伪造运行 ID。

补齐现有 H/A/M 与 Q 的服务端闭环：`SessionState` 保存 HELLO 中的 client metadataVersion/assetPackVersion；任一 Q 先要求 client metadataVersion 与服务器完全一致，否则返回 `CATALOG_MISMATCH`。AddOn 仍比较对应 `M CATEGORY_MAP` 与本地 type hash并在 mismatch 时不发送 Q；服务端无法从 v1 Q 得知客户端本地 per-type hash，因此用 metadataVersion 作为恶意或过期客户端的服务端总闸门。PREVIEW 还要求 assetPackVersion 兼容，否则返回 `ASSET_MISMATCH`。这只是客户端声明值的协议校验，本地文件 SHA 仍由 bundle verifier 负责。

限流与时序固定为可测试合同：PREVIEW 复用现有每 session burst 12、补充 6 token/s 的 SC2 bucket，不另建可绕过总限流的桶；RuntimeAudit 主动限制为最多 4 PREVIEW/s。客户端 Q/R 超时保持 5 秒，不自动重发协议请求；`ACCEPTED` 后允许一次初始 `SetCreature` 加 0.10/0.25/0.50 秒三次本地加载重试，总模型判定窗口 2 秒，generation 一旦变化立即取消。任何放宽必须有真实客户端慢盘证据和对应限流测试。

协议布局不变，因此 `protocolVersion` 保持 1。更新 `schema.json` 的动作语义说明与 golden vector，加入 PREVIEW 请求和 `ACCEPTED/CATALOG_MISMATCH/ASSET_MISMATCH` 结果。`CATALOG_MISMATCH` 表示该 type mapping 不同；`ASSET_MISMATCH` 只来自现有握手声明的 assetPackVersion 不兼容，不能用它声称服务器检查了客户端磁盘文件。

### 任务 2.3：迁移客户端 Bridge

- [x] 已完成（2026-07-22）。正式 AddOn 已删除 SC1 模型 pending/ready 路径，坐骑/宠物仅在 SC2 成功且 generation 匹配后加载；5 秒 Q/R 超时、2 秒模型窗口和 0.10/0.25/0.50 重试均固定为合同。冷 WDB QA 全扫 `305/305 READY`、零失败，详情见 `docs/reports/2026-07-22-stage2-sc2-creature-preview.md`。

仓库：`SoloCollections`

主要文件：

```text
addon/SoloCollections/Core/Bridge.lua
addon/SoloCollections/UI/Mounts.lua
addon/SoloCollections/UI/Pets.lua
protocol/sc2/schema.json
protocol/sc2/golden-vectors.json
tools/collections/tests/test_bridge_contract.py
tools/collections/tests/test_sc2_client_contract.py
```

实现：

- 新增通用 `RequestCreaturePreview(typeId, collectionId, callback)`，内部调用 `RequestSC2Action(..., "PREVIEW", nil, callback)`。
- `RequestModel`/`RequestPetModel` 暂作兼容 wrapper，但在 C++ backend 下只委托新函数，不检查 `B.connected`，不发送 SC1。
- `Mounts.lua`、`Pets.lua` callback 必须接收 `(ok, reason)`；仅当 `ok=true` 且 generation 仍匹配时才延后一帧调用 `SetCreature`。
- 失败时停止重试、清空模型并显示“模型预览暂不可用”；不得忽略失败后继续加载。
- 保留已有 generation cancellation、稳定帧检查和快速切换保护。
- C++ 实机验收通过后删除 `pendingModels`、`pendingPetModels`、SC1 `MODEL_READY/PET_MODEL_READY` 处理器；ALE 仅保留历史/诊断代码时也不能被正式 AddOn 调用。

### 自动测试

- 未收藏记录可以 PREVIEW，但同一记录 SUMMON 仍返回 `NOT_OWNED`；
- 伪造 collection、type、target、Creature Entry 或 Display ID 均不能影响解析；
- PREVIEW 不产生数据库写入、revision、delta、spell cast 或实体；允许并必须测试 replay/限流的瞬时 session 状态和结构化日志；
- 服务端先排队 Creature Query，再发送 `R ACCEPTED`；
- Bridge 失败 callback 不调用 `SetCreature`；过期 generation 的成功结果也不调用；
- replay、rate limit、backend loading、资源缺失均有稳定结果；
- 当前 Core/NPCBots 分支 Release/RelWithDebInfo 编译通过。

### 真实客户端验收

- 在空 WDB 下扫描全部 281 个坐骑和当前全部宠物，记录零空模型；
- 验证未收藏条目、首条/末条、快速滚动、连续点击、前后切换、`/reload`、重登；
- 客户端断开 SC2 或故意制造 mapping mismatch 时显示 unavailable，不出现无限重试或 Lua 错误；
- 召唤、宠物 toggle、玩具和外观动作回归不受影响。

阶段出口：C++ backend 独立完成模型预热；mount/companion C++ generated catalog 已含同源 `PreviewCreatureEntry/catalogLifecycle`；正式 AddOn 不再依赖 SC1/ALE 预览；生命周期、5 秒超时、12/6 限流和本地 2 秒模型判定窗口均有合同测试。

回滚：优先修改实际运行 `transmog.conf` 后执行 `.transmog reload` 关闭 PREVIEW；若回退二进制，则恢复上一套完整 module + generated catalog + AddOn bundle，而不是只回退一份 metadata 文件。不得以重新启用 ALE 作为回滚手段。

建议配套提交：

```text
feat: add authoritative SC2 creature preview priming
addon: migrate collection previews from SC1 to SC2
```

## 8. 阶段 3：恢复独立武器展示

阶段目标：恢复原有 21 个已验证武器的纯模型展示，并把“是否具有独立资源”从旧 Lua 样例数据提升为 canonical 外观的正式展示合同。

### 任务 3.1：迁移 21 个展示描述

- [x] 已完成（2026-07-22）。21 个 verified presentation 已迁入 canonical source，唯一覆盖 `40000..40020`；生成器对 canonical 联接、source alias、M2/skin/BLP 与命名 evidence Hash fail closed，旧 demo id 不成为 identity。证据见 `docs/reports/2026-07-22-stage3-standalone-weapon-presentations.md`。

仓库：`SoloCollections`

新增建议：

```text
catalog/source/appearance_presentations.json
tools/catalog/appearance_presentations.py
catalog/generated/appearance-presentation-report.json
```

迁移来源：

```text
addon/SoloCollections/Data/Appearances.lua
```

工具按 source itemId 联接 `appearance-sources.json`，解析到唯一 canonical appearanceId，并迁移：

- `syntheticDisplayId=40000..40020`；
- `modelPath`；
- `modelScale`；
- `weaponType/weaponCategory`；
- `cameraTuningKey`；
- `m2Camera`；
- `assetPackVersion` 和 `presentationStatus=verified`。

生成时必须断言：

- 21 个 itemId 均映射到且只映射到一个 canonical appearance；
- synthetic display ID 唯一；
- M2、材质、DBC 映射与资源 manifest Hash 对应；
- 源物品 alias 仍可追溯；
- 旧 demo id 50..70 不成为新的权威 identity。

### 任务 3.2：让 canonical 投影保留展示字段

- [x] 已完成（2026-07-22）。生成目录与 AddOn 投影已保留正式展示字段，明确生成 `BODY=12233`、`STANDALONE=21`、`UNAVAILABLE=5936`；展示数据不进入服务端授权 mapping hash，`creatureDisplayId` 仅在 renderer adapter 临时翻译且不进入 schema。

修改：

```text
tools/catalog/generate_catalog.py
addon/SoloCollections/Core/Catalog.lua
addon/SoloCollections/Data/Generated/Catalog.lua
```

- 生成器把 `appearance_presentations.json` 联接到客户端 appearance 记录。
- generated presentation 与 `Catalog.lua` 只使用 `syntheticDisplayId`、`modelPath`、`modelScale`、`m2Camera` 和 camera key；旧 `creatureDisplayId` 只允许在 renderer adapter 最后一层临时翻译为 `SetCreature(DIRECT_DISPLAY_REQUEST_BASE + syntheticDisplayId)`，不得出现在新的 schema 中。它与 mount/companion 的 `previewCreatureEntry`、未来可能的 `previewDisplayInfoId` 是三种不同 ID。
- 护甲默认为 `BODY`；具有 verified presentation 的主副手为 `STANDALONE`；其他主副手为 `UNAVAILABLE`。
- 收藏 owned、应用资格和 source item 解析仍只来自 canonical 服务端目录，presentation 不进入服务端授权。

### 任务 3.3：封闭错误 fallback

- [x] 已完成（2026-07-22）。正式衣橱按显式 renderMode 渲染；缺资源记录隐藏角色并显示 unavailable。新增 2 秒 `GetModel()`/canonical path 就绪闸门，stock `Wow.exe` 缺 SoloCam 时也安全转 unavailable；真实客户端证明独立武器仅显示武器且无角色回退。

修改：

```text
addon/SoloCollections/UI/Wardrobe.lua
client-extension/SoloCam/tests/test_wardrobe_integration.py
tools/collections/tests/test_appearance_catalog.py
```

- `Wardrobe.lua` 按显式 `renderMode` 选择 renderer，不再通过字段是否碰巧存在来把主副手降级成 BODY。
- `STANDALONE` 使用现有 direct display/M2 bridge。
- `UNAVAILABLE` 隐藏 PlayerModel，显示物品图标、名称和“独立模型资源尚未生成”。
- 不创建 NPC placeholder，不使用 `SetUnit("player") + TryOn` 假装独立武器预览。

### 验收

- 21 个样例逐个确认只见武器、不见角色；主副手、盾牌、远程、拳套、魔杖、钓鱼竿均覆盖。
- 旋转、缩放、保存相机调整、翻页复用和 `/reload` 正常。
- 任意没有独立资源的 canonical 主副手显示 unavailable，不出现角色。
- stock client 缺 SoloCam/资源包时安全降级为 unavailable，不崩客户端。

阶段出口：回归恢复且建立可扩展展示表；全量武器资源生成仍留到后续。

建议提交：

```text
catalog: restore verified standalone weapon presentations
addon: forbid body fallback for standalone weapon slots
```

## 9. 阶段 4：收敛边框与玩具网格布局

阶段目标：在不改变收藏状态语义的情况下，统一三页的图标状态边并修复玩具首列贴边。

### 任务 4.1：抽取公共细边组件

- [x] 已完成（2026-07-22）。`UI.CreateThinCardBorder()` 与 `UI.CreateCollectionCardBorders()` 已抽到先加载的 `Templates.lua`；坐骑/宠物列表、详情、玩具和衣橱共享 1px 收藏边与独立 2px 选中边，active 模板不再引用粗 TGA 状态框。状态颜色、厚度和 `SetSelected()` 不改收藏边均有自动测试与真实客户端证据。

主要文件：

```text
addon/SoloCollections/UI/Templates.lua
addon/SoloCollections/UI/Wardrobe.lua
addon/SoloCollections/UI/Mounts.lua
addon/SoloCollections/UI/Pets.lua
addon/SoloCollections/UI/Toys.lua
```

实现：

- 将 `Wardrobe.lua` 的 `createThinCardBorder()` 抽到先加载的 `Templates.lua`。
- 收藏状态边：1 logical px。
  - 已收集：`0.58, 0.43, 0.16, 1`
  - 未收集：`0.38, 0.39, 0.40, 1`
- 选中边独立为 2 logical px：`1.00, 0.78, 0.14, 1`。
- 坐骑/宠物列表、右侧详情、玩具卡片统一使用 helper。
- 选中态不得改变收藏态颜色；hover、selected、collected 是三个独立状态。
- 不缩小旧 TGA 的 `±3/±5` 锚点来“修”粗框，因为这会让 10px 不透明色带进一步侵入图标。
- 不修改页面外层 `ApplyNineSlice`；它不是图标框。

推荐方案不再让 active 模板使用 `collected-frame.tga`/`uncollected-frame.tga` 覆盖图标，因此无需重绘或重新提交媒体。如果选择重绘素材，必须另行更新 `Media/assets.json` Hash 和像素合同。

### 任务 4.2：玩具网格改为约束布局

- [x] 已完成（2026-07-22）。玩具网格改为 3×6 动态约束布局，848 logical px 容器得到 268px tile、16/16 左右 margin 和 6px 列间距；1/2/4/18 条、满页/残页、hover/selected/collected 独立状态及两次 `/reload` 已在七档分辨率/UI Scale 矩阵通过。证据见 `docs/reports/2026-07-22-stage4-thin-borders-and-toy-grid.md`。

`Toys.lua` 目标常量：

```lua
local GRID_COLUMNS = 3
local VISIBLE_TILES = 18
local GRID_PADDING_X = 16
local GRID_PADDING_TOP = 12
local GRID_COLUMN_GAP = 6
local TILE_HEIGHT = 72
```

列宽：

```text
floor((gridWidth - 2*GRID_PADDING_X
       - (GRID_COLUMNS-1)*GRID_COLUMN_GAP) / GRID_COLUMNS)
```

当前 `gridWidth=848` 时得到 268px。锚点：

```text
x = paddingX + column * (tileWidth + gap)
y = -(paddingTop + row * tileHeight)
```

“居中”指整个三列卡片块在 grid 内居中；图标仍位于卡片左侧，右侧保留名称，不把图标移到每张卡片的水平中心。

### 自动测试

- 删除对固定 `TILE_WIDTH=282` 的断言，改为 padding/gap/对称 margin 合同；
- 保留 3 列、6 行、18 个复用 tile；
- active 模板状态边 1px、选中边 2px；
- `SetSelected()` 不改变收藏边；
- 玩具第一列和第三列 margin 差不超过 1 logical px；
- 公共 helper 抽取后同步调整 SoloCam 的 Wardrobe 集成测试。

### 真实客户端验收

- [x] 已完成（2026-07-22）。1024×768、1366×768、1920×1080（1.00/0.80/0.64）、2560×1440、3440×1440 均生成目标像素尺寸截图并写出两轮 READY 记录；3440 档使用临时 3840×2160 DSR 与 DPI-aware 审计进程，结束后恢复桌面模式。

分辨率/UI Scale 至少覆盖：

- 1024×768 / 1.00；
- 1366×768 / 1.00；
- 1920×1080 / 1.00、0.80、0.64；
- 2560×1440；
- 3440×1440。

每档检查坐骑/宠物列表与详情、玩具首末列、已收集/未收集/选中/hover、满页/残页、搜索后 1/2/4 条记录以及 `/reload` 状态恢复。

阶段出口：三个页面 active 图标不再使用粗 TGA 状态框；1px 状态边与 2px 选中边合同通过；玩具三列在全部分辨率/UI Scale 下左右误差不超过 1 logical px；现有 4 个玩具动作回归通过。该出口是阶段 7 的强制前置条件。

建议提交：

```text
ui: unify thin collection borders and center toy grid
```

## 10. 阶段 5：建立种族、性别、部位相机矩阵

阶段目标：保留已调好的人类女性效果，用可重复的模型比例算法生成其他原生种族/性别的首轮近似值，再逐项覆盖，而不是把同一组绝对值复制给所有模型。

### 任务 5.1：建立单一相机 profile 源

- [x] 已完成（2026-07-22）。新增单一 canonical/override 源、DBC/M2 fail-closed 提取器和 Lua/C++ 双投影；20 个原生角色模型、3 个 DBC、归一化 bounds、preview display 与 SHA-256 均写入外部 evidence manifest，客户端资产本体不进 Git。详情见 `docs/reports/2026-07-22-character-camera-profile-generation-and-runtime-matrix.md`。

新增建议：

```text
catalog/source/camera_profiles.json
catalog/source/overrides/camera_profiles.json
tools/catalog/character_camera_profiles.py
addon/SoloCollections/Data/Generated/CameraProfiles.lua
client-extension/SoloCam/src/generated/CharacterCameraProfiles.inc
docs/reports/2026-07-20-character-camera-profile-generation.md
```

生成输入：

- `catalog/source/races.json` 的 logical race 与 `clientAssetProfile`；
- 当前客户端 `ChrRaces.dbc`、`CreatureDisplayInfo.dbc`、`CreatureModelData.dbc`；
- 对应男女角色 M2 的 bounding box；
- 当前 C++ human/female 9 个 reference profile；
- 显式人工 override。

外部 DBC/M2 只作输入，不进入 Git。报告保存路径、build、SHA-256、解析结果和归一化尺寸，不保存客户端资产本体。

### 任务 5.2：生成首轮比例 profile

- [x] 已完成（2026-07-22）。按 human/female reference 尺寸生成 10×2×9 共 180 条 profile，171 个新 sentinel 为 `0x6000..0x60AA` 且与所有保留区间无冲突；human/female 9 条逐值保留，侏儒按槽位使用显式 offset override，其余优先种族保持可审计 `scaled` 基线。

对每个模型计算：

```text
height  = maxZ - minZ
width   = max(maxX-minX, maxY-minY)
centerZ = (maxZ + minZ) / 2
```

从 human/female reference 计算归一化量：

- `verticalOffset / humanHeight`；
- `horizontalOffset / humanWidth`；
- `minimumDistance / max(humanHeight, humanWidth)`。

目标种族首轮值：

- vertical、horizontal、minimum distance 按目标模型尺寸还原；
- `distanceScale` 与 `yawOffset` 作为无量纲值先沿用 reference；
- `centerZCorrection` 和部位特殊偏移只从显式 override 加入；
- 生成状态标记为 `scaled`；完成实机调整后才改为 `verified`。

牛头人、巨魔、亡灵和侏儒优先准备 override，因为体型、站姿和模型原点最容易破坏纯比例结果。HD 模型或自定义种族使用不同 `clientAssetProfile`，不得复用原版 verified 结果。

### 任务 5.3：泛化 SoloCam profile 查找

- [x] 已完成（2026-07-22）。SoloCam 已泛化为生成表唯一 sentinel 查找，AddOn 按 logical race/client asset profile、sex、slot 选择；四种迁移模式、Lua/C++ version/hash 一致性、同 tick camera 1 fail-safe、x86 native 构建与部署均通过。

修改：

```text
client-extension/SoloCam/src/CameraProfile.hpp
client-extension/SoloCam/src/CameraProfile.cpp
client-extension/SoloCam/src/SoloCam.cpp          # 具体 hook 文件按现有实现确认
addon/SoloCollections/UI/Wardrobe.lua
catalog/source/races.json
client-extension/SoloCam/tests/CameraProfileTests.cpp
client-extension/SoloCam/tests/test_wardrobe_integration.py
```

- `HumanFemaleCameraProfile` 泛化为 `CharacterCameraProfile`。
- `FindHumanFemaleCameraProfile` 泛化为按唯一 sentinel 查找生成表。
- profile 的 9 个部位固定枚举为 `HEAD/SHOULDER/BACK/CHEST/WRIST/HANDS/WAIST/LEGS/FEET`，生成器与 UI 不得各自维护不同顺序。
- 10×2×9 共 180 条 profile 的 sentinel 全局唯一；其中 human/female 9 条保留现有 `0x5341..0x5349` 作为预留兼容值，只为其余 171 条分配新值。sentinel 只在 Lua/DLL 私有握手中使用，不成为收藏 identity。
- 生成器必须验证 171 个新增 sentinel 不与 camera 0/1、预留 human/female `0x5341..0x5349`、彼此或独立武器私有相机命令区间冲突；再验证包含预留 9 条后的 180 条整体唯一。
- Lua 通过 logical race/client asset profile、`UnitSex` 和 slot 选择 sentinel。
- human/female 9 条 reference 的 sentinel 与数值保持兼容，避免已调结果漂移。
- 找不到 profile、DLL 版本不匹配或 profile 非法时，在同一 Lua tick 安全回退 `SetCamera(1)`。
- `races.json` 不再让 9 个原生非人类种族统一指向 `cameraProfile=global`；它们指向各自 profile family。

迁移期提供开发模式 `LegacyHumanFemale | Compare | Generated | Native`：

- `LegacyHumanFemale` 继续使用原 9 条，只用于零漂移基线；
- `Compare` 只计算/记录生成 profile，画面仍由旧人类女性或 native 路径负责；
- `Generated` 使用完整生成表；
- `Native` 强制 camera 1，用于紧急回退。

Compare 不得改变画面或保存第二份可变配置。全部 180 条切换完成后，正式包只保留 Generated 与 Native 回退；旧人类女性表降为生成器回归 fixture。

### 自动测试

- 10 个原生种族 × 2 性别 × 9 部位完整覆盖；
- 180 个 sentinel 唯一、数值有限且在安全范围；
- human/female 9 条逐位等于当前 reference；
- 生成器相同输入字节一致，M2/DBC Hash 漂移时拒绝静默重算；
- synthetic 新种族、未知 sex、HD asset profile mismatch 都回退 camera 1；
- Lua 与 C++ 生成表的 profile version/hash 完全一致；
- x86 SoloCam native 测试和 DLL 构建通过。

### 真实客户端验收

- [x] 已完成（2026-07-22）。接受运行 `20260722-063149-157` 覆盖 20 页、180 行和 21 张截图：180/180 模型路径与视觉审阅通过，human/female 无回归，巨魔异步换装后相机重应用稳定，侏儒按槽位校准；`/reload`、未知种族、未知 sex 和 asset mismatch 回退全部通过。逐行记录见 `catalog/review/cameras/runtime-matrix.csv`。

第一闸门：20 个种族/性别组合逐一验证 `HEAD/CHEST/FEET`，用于尽早发现尺寸算法失败，不能替代完整验收。

第二闸门：第一闸门通过后覆盖全部 9 部位，即 180 个组合。每条记录：

- 是否完整落在卡片内；
- 目标部位是否位于视觉中心；
- 是否裁掉头顶、脚底、肩部或武器；
- 是否需要 override；
- profile 状态由 `scaled` 升为 `verified` 的证据截图编号。

阶段出口：180 个 race/sex/slot 组合全部完成真实客户端首轮验收，均满足“目标部位可见、主体不越出卡片安全区、无串 profile/崩溃/无限缩放”；human/female 逐值与画面无回归；未知模型安全回退。除 human/female 外可以保持 `scaled`，像素级精调为 `verified` 留到后续，但“仅记录未通过”不能关闭本阶段。

建议提交：

```text
catalog: generate race sex slot camera profiles
solocam: support generated character camera matrix
addon: select wardrobe camera by logical identity
```

## 11. 阶段 6：扩充小宠物目录

前置条件：阶段 1 图标合同和阶段 2 SC2 PREVIEW 已在现有 24 条宠物上完成实机闭环。不得用扩充目录掩盖预览链路仍然失效。

阶段目标：把当前 24 条人工样本升级为完整的提取、审核和生成流水线，并只上线经过证据审查的当前游戏 companion。

### 任务 6.1：建立 companion 提取器

- [x] 已完成（2026-07-22）。新增 `companion_catalog.py` 的 extract/generate/check 流水线，以命名 evidence pack 固定 DBC/World DB 输入；205 个 SkillLine 778 法术中得到 203 个正向 summon、201 个精确 Creature Entry 候选，201 条均有逐项 accepted 决定，candidate/review Hash 漂移 fail closed。详情见 `docs/reports/2026-07-22-wotlk-companion-catalog-review.md`。

新增建议：

```text
tools/catalog/companion_catalog.py
catalog/review/companions/evidence.json
catalog/review/companions/review-policy.json
catalog/generated/companion-candidates.csv
catalog/generated/companion-exclusions.csv
docs/reports/2026-07-20-wotlk-companion-catalog-review.md
tools/collections/tests/test_companion_catalog.py
```

固定输入：

- `Spell.dbc`；
- `SkillLineAbility.dbc`，SkillLine 778；
- `SpellIcon.dbc`；
- `CreatureDisplayInfo.dbc`；
- 当前 World DB 的 `creature_template` 与 model 映射；
- 现有 24 条正式目录和 `catalog/ids.json`。

当前匹配部署快照的原始基线为：

- SkillLine 778 共 205 个法术；
- 203 个正向 Creature Summon；
- 按 Creature Entry 去重后约 201 个资源就绪候选；
- 另一数据快照可能得到约 195 个，因此报告必须以实际 Hash 为准，不把 201 写成永久常量。

每个候选必须得到 `accepted`、`excluded` 或 `deferred`，且三者之和覆盖全部候选。排除/延后原因至少包括：

- 猎人、术士或其他职业战斗宠物；
- guardian、临时战斗单位和任务专用召唤；
- 测试、废弃、内部或无稳定获取路径记录；
- 缺 World 模板、缺 Display 资源或客户端资源版本不匹配；
- 仅同名但 Creature Entry 不同，不能按名字误合并；
- 同一生物的重复召唤法术尚未明确 canonical/unlock 语义。

### 任务 6.2：升级 companion action schema

- [x] 已完成（2026-07-22）。正式 action source 已升级为 schema 2；C++ `FindBySpell()` 索引全部 unlock variants，登录迁移检查全部 variants，召唤仅使用 reviewed canonical spell。两组重复法术 identity 已在 native 与真实客户端证明分别固定为 canonical 10712、25018。

当前每条记录只有单一 spell。升级建议：

```json
{
  "schemaVersion": 2,
  "entries": [
    {
      "collectionId": 100281,
      "collectionKey": "companion.worg_pup",
      "canonicalSpellId": 15999,
      "unlockSpellIds": [15999],
      "previewCreatureEntry": 10259,
      "catalogLifecycle": "ACTIVE",
      "uiLifecycle": "public"
    }
  ]
}
```

修改：

```text
catalog/source/companion_actions.json
tools/catalog/generate_catalog.py
mod-solo-collections/src/SoloCollectionsCompanionCatalog.h
mod-solo-collections/src/SoloCollectionsCompanionCatalog.cpp
mod-solo-collections/src/generated/SoloCollectionsCompanionCatalog.inc
mod-solo-collections/src/SoloCollectionsCompanionService.cpp
```

规则：

- `FindBySpell()` 索引全部 `unlockSpellIds`；
- 召唤只使用审核后的 `canonicalSpellId`；
- 多个 spell 只有在 `previewCreatureEntry` 和审核 identity 完全相同且有明确证据时才进入一个逻辑宠物；
- 现有 24 条先迁移为单元素数组，证明 ID、解锁和召唤行为逐项等价后，才加入新候选。

### 任务 6.3：稳定 ID 与生成切换

- [x] 已完成（2026-07-22）。原 24 条 `100281..100304` 与 key 逐项保留；177 个新增 ID 由全局 registry append-only 分配为 `100309..100485`，未占用 toy `100305..100308`；AddOn/module 同步切换到 mapping hash `5c104b479934bd17a1eb7cf26fa64a9eb284d5a6b22c605d0a57b04e3df22ffd`。

- 保留 `100281..100304` 和现有 collection key。
- `100305..100308` 已属于玩具，新增宠物必须由 `catalog/ids.json` 的全局未使用值分配，禁止手写“下一号”。
- 新 ID append-only；排除或撤回条目保留 tombstone。
- accepted 记录同时生成 collection CSV、action map、展示图标、客户端 Lua 和 C++ inc。
- candidate/review Hash 变化时禁止 `--check` 静默更新生产目录。
- 扩充后的 companion mapping hash 变化要求 AddOn 与 module 配套部署；旧版本忽略未知 DB 行但不得删除它们。

### 自动测试

- 现有 24 条 schema v2 等价性；
- `accepted + excluded + deferred = candidate total`；
- accepted 条目均有 icon、CreatureTemplate、Display 资源、canonical spell 和至少一个 unlock spell；
- spell、Creature identity、collection ID 和 key 无冲突；
- 所有新增 ID 来自 registry 且不占用 toy/其他类别 ID；
- 不再断言正式数量等于 24，改为固定证据 Hash、审核覆盖率、已知条目和稳定 ID；
- C++ `FindBySpell` 覆盖全部 unlock variants，召唤只走 canonical spell；
- 未收藏预览成功、未收藏召唤拒绝；
- 相同输入生成字节一致。

### 真实客户端验收

- [x] 已完成（2026-07-22）。UI 实际滚动从 `1-12 / 201` 到 `201-201 / 201`；冷、热缓存各完成 281 mount + 201 companion 的 482/482 READY 扫描。重复 unlock、canonical summon、同宠物 toggle、不同宠物替换、跨地图、死亡/复活、登出/重登、同账号跨角色、不同账号隔离与 worldserver 重启恢复均通过；测试 grant 最终残留为 0。

- 完整滚动超过 24 条，确认 UI 对象池不是总数上限；
- 对本轮全部 accepted 条目执行受限速的冷/热缓存模型扫描；
- 抽样验证重复 unlock spell、召唤、替换、同宠物 toggle、传送、地图切换、死亡、登出和重登；
- 不影响猎人/术士宠物、guardian 和任务召唤物；
- 同账号解锁同步、不同账号隔离、服务器重启恢复保持第一轮语义。

阶段出口：每个候选都有决定，正式数量等于审核接受数而不是预设目标；所有 active 记录图标和模型可用。

建议配套提交：

```text
catalog: add reviewed WotLK companion pipeline
feat: support companion unlock spell variants
```

## 12. 阶段 7：扩充玩具目录

前置条件：四个现有玩具动作回归仍通过，玩具网格和边框阶段已经完成。扩充目录不得与 UI 修复混在同一提交。

阶段目标：以旧 36 条原型为审核池，逐项确定获取语义和动作语义；优先上线现有安全 action registry 能完整表达的条目。

### 任务 7.1：建立玩具证据与审核器

- [x] 已完成（2026-07-22）。新增 `toy_catalog.py` 的 extract/generate/check 流水线，以命名 evidence pack 固定 DBC/World DB 输入；旧 36 条原型全部得到逐项结论：accepted 9、deferred 27、excluded 0，candidate/review/pack Hash 漂移 fail closed。详情见 `docs/reports/2026-07-20-wotlk-toy-catalog-review.md`。

新增建议：

```text
tools/catalog/toy_catalog.py
catalog/review/toys/evidence.json
catalog/review/toys/review-policy.json
catalog/generated/toy-candidates.csv
catalog/generated/toy-exclusions.csv
docs/reports/2026-07-20-wotlk-toy-catalog-review.md
tools/collections/tests/test_toy_catalog.py
```

审核池以旧 `addon/SoloCollections/Data/Toys.lua` 和 `legacy-sc1-shadow.json` 的 36 条记录为起点。物品和显示资源存在只证明可以显示，不证明动作安全。

每条 accepted 记录必须显式声明：

```text
itemId
unlockSource = ITEM_ACQUIRED
actionKind = SPELL_SELF | SPELL_TARGET | ITEM_USE | CUSTOM_HANDLER
spellId
targetPolicy
cooldownScope
accountCooldownMs
allowInCombat
consumesMaterial
customHandler
replayPolicy
riskFlags
catalogLifecycle
```

字段枚举合同：

| 字段 | 允许值与语义 |
|---|---|
| `targetPolicy` | `NONE/SELF/OPTIONAL_UNIT/REQUIRED_UNIT`；客户端只传“是否存在当前目标”，实际目标仍由服务端 Player/session 解析 |
| `cooldownScope` | `NONE/CHARACTER/ACCOUNT/HANDLER_NATIVE`；`ACCOUNT` 必须配非负 `accountCooldownMs` |
| `replayPolicy` | `REJECT_DUPLICATE/IDEMPOTENT`；不能证明幂等时只能 reject duplicate |
| `riskFlags` | `TELEPORT/ECONOMY/ITEM_CREATE/WORLD_OBJECT/MATERIAL/SEASONAL/AREA/COMBAT` 的去重数组；空数组表示审核未发现这些风险，不表示免除测试 |
| `customHandler` | 只有 `actionKind=CUSTOM_HANDLER` 时允许非空，并必须匹配编译进 C++ registry 的 key；缺失、未知或 disabled handler 使目录加载 fail closed |
| `catalogLifecycle` | 使用 3.4 的 `ACTIVE/PREVIEW_ONLY/DISABLED/TOMBSTONE`，不得另造小写近义枚举 |

不得从 `item_template` 存在 Use Spell 自动推断玩具。下列类型默认 `deferred`，直到有独立 handler、幂等设计和真实验收：

- 传送或地图切换；
- 生成物品、货币或经济变化；
- 生成持久世界对象；
- 消耗材料或专业条件；
- 需要节日、区域、队伍或复杂目标；
- 重放可能造成重复对象、副作用或冷却绕过。

### 任务 7.2：保持获取与使用边界

- [x] 已完成（2026-07-22）。账号解锁仍只来自服务端 item acquisition/login scan；AddOn 只发送 logical collection 和目标存在位，C++ 解析完整 action schema、ITEM_USE 持有检查、账号/角色/native 冷却及编译 handler allowlist，未知 handler 在目录构造时 fail closed。

主要文件：

```text
catalog/source/toy_actions.json
addon/SoloCollections/Core/Catalog.lua
addon/SoloCollections/UI/Toys.lua
mod-solo-collections/src/SoloCollectionsToyCatalog.h
mod-solo-collections/src/SoloCollectionsToyCatalog.cpp
mod-solo-collections/src/SoloCollectionsToyService.cpp
mod-solo-collections/src/SoloCollectionsProtocolScript.cpp
```

规则：

- 账号解锁仍由 `OnItemAcquired` 和登录持有物品扫描触发，客户端不能自行 grant。
- `FindByItem` 只映射经过审核的正式 item；重复 item identity 生成失败。
- 使用动作仍只提交 logical collectionId 和是否有当前目标；spell、item、handler 均由 C++ 目录解析。
- `ITEM_USE` 继续要求角色实际持有可用物品；获得收藏不等于凭空生成消耗性物品。
- 每个新增 `CUSTOM_HANDLER` 单独提交、单独测试、单独实机验收，不用一个通用脚本解释器执行目录字符串。
- 玩具图标优先来自生成的 `displayItemId`/item icon；冷缓存时监听 `GET_ITEM_INFO_RECEIVED`，最终失败显示单条 fallback。

### 任务 7.3：分批启用

- [x] 已完成（2026-07-22）。原 `100305..100308` 逐项无回归，新增 5 条安全动作 append-only 为 `100486..100490`；未拥有、目标、冷却、重放、重登、重启、跨角色、账号隔离和清理均通过，20 条 QA fixture 的 18/页、残页、搜索、右键、动作栏拖放与 `/reload` 完成实机验收。

1. 保留现有 `100305..100308` 不变并通过完整回归。
2. 对旧 36 条完成全覆盖审核报告。
3. 第一批只启用 `SPELL_SELF`、`SPELL_TARGET` 和能完整验证的 `ITEM_USE`。
4. 特殊 handler 每次只上线一类风险语义。
5. 正式数量等于审核 accepted 数；不把“必须达到 36”作为验收。

### 自动测试

- 36 条审核池每条都有 accepted/excluded/deferred 和理由；
- accepted action schema 字段完整、枚举合法、item/spell/template 存在；
- action registry 不存在重复 item、collection、handler key；
- 未拥有、缺目标、多余目标、战斗限制、死亡、载具、冷却、材料不足和 replay 分支；
- item acquisition grant 幂等、revision 连续、不同账号隔离；
- 自定义 handler 不存在时目录加载 fail closed；
- 现有四条 ID/动作逐项无回归；
- 不再断言目录数量等于 4。

### 真实客户端验收

- 每个新增玩具分别验证获得物品、账号解锁、使用、目标、冷却、重复请求、重登和重启；
- 生成对象类玩具检查重复请求不产生第二个对象，离开场景/登出后清理正确；
- 材料、传送或经济类条目必须附带失败注入和副作用核对；
- 满 18 条、跨页、最后一页、搜索、右键菜单、拖到动作栏与 `/reload`；
- 未收藏记录显示但不可使用，客户端伪造 collected 无效。

回滚：将问题条目的 `catalogLifecycle` 改为 `DISABLED/TOMBSTONE` 并配套更新 mapping；不删除已写入的账号收藏行、不复用 ID。紧急情况下禁用单个 handler 或 Toy provider，不启用 ALE。

阶段出口：旧 36 条审核池达到 `accepted + excluded + deferred = 36`；现有 4 条逐项无回归；每个新增 accepted 条目均具有完整 action schema、自动测试和真实客户端证据；所有高风险或语义不完整项保持 deferred。该阶段不以目录达到 36 条为目标。

建议提交：

```text
catalog: add reviewed WotLK toy pipeline
feat: expand safe toy action registry
```

## 13. 阶段 8：导入并审核当前游戏套装

阶段目标：以当前客户端 `ItemSet.dbc` 和 World DB 为证据，生成当前游戏的可见套装目录；保留现有 8 套 identity，补入牧师 T1，并支持单职业、多职业和不限职业。

### 任务 8.1：消除两份手工事实源

- [x] 已完成（2026-07-22）。已建立 `itemset_import.py`、正式 normalized schema、review/evidence/override、generated 输出与全局 registry view；`sets.json` 退役为说明，`sets.csv` 改为生成投影，生产身份和成员只来自 normalized model。详情见 `docs/reports/2026-07-20-wotlk-itemset-catalog-review.md`。

当前同时维护：

```text
catalog/source/sets.json
catalog/source/collections/sets.csv
```

两者都只有 8 条。全量导入后不能继续双写。目标管线：

```text
ItemSet.dbc + item_template snapshot
          + canonical appearance mapping
          + catalog/ids.json global append-only ID registry
          + curated overrides
                      |
                      v
          normalized-itemsets.json
              /                 \
             v                   v
  generate_catalog.py       set_catalog.py
             |              /           \
             v             v             v
 Generated/Catalog.lua  Data/Sets.lua   C++ generated inc
```

新增建议：

```text
tools/catalog/itemset_import.py
catalog/schema/normalized-itemsets.schema.json
catalog/review/sets/evidence.json
catalog/review/sets/review-policy.json
catalog/source/overrides/sets.json
catalog/generated/normalized-itemsets.json
catalog/generated/set-id-registry-view.json
catalog/generated/itemset-candidates.csv
catalog/generated/itemset-exclusions.csv
docs/reports/2026-07-20-wotlk-itemset-catalog-review.md
```

完成切换后，旧 `sets.json`/`sets.csv` 只保留迁移 fixture 或退役说明，不再是生产 identity/成员事实源。

`catalog/ids.json` 是所有 collection ID 的唯一全局权威；不得再引入可独立编辑的 `set_id_registry.json`。`set-id-registry-view.json` 只是从全局 registry 生成的套装子集，`--check` 时反向证明现有 `300000..300007` 和所有新增 ID 没有跨类别冲突。

### 任务 8.2：建立 normalized ItemSet 模型

- [x] 已完成（2026-07-22）。509 个 `itemset:<ItemSetId>` 审核单元逐项闭合为 accepted 465、excluded 34、deferred 10；exact counters、source evidence Hash、classPolicy、variant lifecycle、members/omissions 与 mapping/presentation Hash 均进入 schema 2 和 fail-closed 校验。

输入证据：

- `ItemSet.dbc` SHA-256；
- World DB `item_template.entry/itemset/AllowableClass/InventoryType` 的脱敏快照 Hash；
- canonical appearance mapping hash；
- ID registry 和人工 override Hash。

`normalized-itemsets.json` 必须通过以下正式 schema；`classPolicy` 与 `allowedClassKeys` 不得分别散落成两套字段：

```json
{
  "schemaVersion": 2,
  "sourceEvidence": {
    "itemSetDbcSha256": "...",
    "itemTemplateSnapshotSha256": "...",
    "appearanceMappingHash": "...",
    "reviewPolicyHash": "..."
  },
  "sets": [
    {
      "collectionId": 300008,
      "collectionKey": "set.itemset.202",
      "ordinal": 18507,
      "itemSetId": 202,
      "catalogLifecycle": "ACTIVE",
      "uiLifecycle": "public",
      "classPolicy": {
        "mode": "ALLOW_LIST",
        "allowedClassKeys": ["priest"]
      },
      "variants": [
        {
          "variantKey": "default",
          "variantOrdinal": 1,
          "isDefault": true,
          "lifecycle": "ACTIVE",
          "members": [
            {
              "memberKey": "head",
              "slotKey": "HEAD",
              "required": true,
              "appearanceIds": [200000],
              "sourceItemIds": [16813]
            }
          ],
          "omissions": []
        }
      ]
    }
  ]
}
```

`classPolicy.mode` 只允许 `ANY/ALLOW_LIST/UNRESOLVED`：`ANY` 必须配空数组；`ALLOW_LIST` 必须配一个以上无重复 logical class key；`UNRESOLVED` 必须配空数组并 fail closed。variant lifecycle 只允许 `ACTIVE/DISABLED/DEFERRED`。`variantOrdinal` 是 collection 内从 1 开始、append-only、不复用的逻辑 ID；每个 collection 恰有一个 active `isDefault=true` variant。

默认收录规则：

- 至少两个不同的 active、可见 canonical appearance；
- 戒指、项链、饰品等非外观成员进入 `omissions`，不进入完成度分母；
- 同一物理 slot 的多个来源或 alternatives 只计一个 required slot；
- 可见成员缺 canonical mapping 时不得静默删除，进入 partial/deferred 报告；
- 默认一个 ItemSet DBC 行对应一个 collection/default variant；
- 难度、配色、阵营或同模型变体只通过显式 override 合并，不按名称猜测；
- 测试、废弃、内部或不可获取套装使用明确 `uiLifecycle`；需要禁用服务端派生/应用时另设 `catalogLifecycle`，不直接进入玩家目录。

审核单元固定为 `candidateKey=itemset:<ItemSetId>`，当前 evidence pack 预期 509 个；一个 DBC 行默认生成一个 collection，显式 variant 仍属于同一审核单元。本轮禁止把不同 ItemSetId 合并为同一个 collection。canonical appearance 去重只发生在同一个 member 的 `appearanceIds[]` 内，用于消除相同显示的来源 alias；`distinct-signature` 只是一项报告统计，不改变 509 个审核分母。

审计基线：509 条 ItemSet 即 509 个原始审核单元；其中 475 条至少两个成员、466 条至少两个已映射可见成员、约 465 个不同 canonical appearance signature、约 438 条完整映射。后四项是诊断漏斗，不改变 509 的审核覆盖分母；最终 active collection 数由 509 项审核结论决定。

### 任务 8.3：迁移职业资格契约

- [x] 已完成（2026-07-22）。AddOn/C++ 已统一使用 `ANY/ALLOW_LIST/UNRESOLVED` classPolicy，覆盖单职业 326、双职业 11、三职业 3 与 ANY 125；type 14 snapshot/delta 由 provider 从 type 13 同 revision 派生，不创建第二 revision 或套装 unlock 行。

将 `classToken` 改为上述 `classPolicy` 对象：

- `mode=ANY, allowedClassKeys=[]`：不限职业；
- `mode=ALLOW_LIST` 且一项：单职业；
- `mode=ALLOW_LIST` 且多项：多职业；
- 无法解析或成员资格矛盾：`mode=UNRESOLVED, allowedClassKeys=[]`，fail closed。

职业推导：

- 将每个来源物品的 `AllowableClass` 转成 logical class key；
- 同一 required slot 的 alternatives 先对可装备职业求并集，因为拥有任一 alternative 即可满足该槽；
- 再对全部 required slot 的并集结果求交集，得到能完成整套的职业集合；
- 全职业字段按当前 AzerothCore schema 明确归一化；
- 不根据套装名字、护甲类型或职业印象猜测；
- 最终每件装备仍经过现有 C++ compatibility/preflight，套装级 allow list 不是最终授权替代品。

修改：

```text
tools/catalog/set_catalog.py
tools/catalog/generate_catalog.py
addon/SoloCollections/Core/Catalog.lua
addon/SoloCollections/Data/Sets.lua
addon/SoloCollections/UI/Wardrobe.lua
mod-solo-collections/src/SoloCollectionsSetCatalog.h
mod-solo-collections/src/SoloCollectionsSetCatalog.cpp
mod-solo-collections/src/SoloCollectionsSetService.cpp
mod-solo-collections/src/SoloCollectionsProtocolServer.h
mod-solo-collections/src/SoloCollectionsProtocolServer.cpp
mod-solo-collections/src/SoloCollectionsProtocolScript.cpp
mod-solo-collections/tests/native/SoloCollectionsProtocolTests.cpp
mod-solo-collections/tests/native/SoloCollectionsDomainTests.cpp
```

type 14 继续是 type 13 外观拥有状态的派生投影，不增加 type 14 unlock 表写入。精确定义：

- 对每个 `lifecycle=ACTIVE` variant，逐个 required member 检查账号 type 13 owned 集合与该 member 的 `appearanceIds[]` 是否有非空交集；全部 required member 满足时该 variant 完成。
- 一个 type 14 collection 只要至少一个 active variant 完成即为 completed；UI 显示的 `ownedCount/requiredCount` 按当前选择的 variant 计算，不把不同 variant 的部件混成一套。
- type 13 mutation 只增加一次现有账号全局 revision；提交后用新 type 13 快照重算受影响 type 14，若派生状态变化，则在同一 revision 的 SC2 delta/snapshot 中携带 type 14 变化，不再创建第二个 revision 或数据库行。
- 当前 `Sc2Server::QueueSnapshots` 对非 external category 直接读取 persisted cache，不能正确代表 derived type 14；本阶段必须让 snapshot 通过 provider 的 `OwnedByAccount` 取得套装投影。每个活动 session 缓存上次发送的 type 14 ID 集合；收到 type 13 committed delta 后重算、与该集合求差，使用同一 revision 发送 type 14 `A/R` delta 并更新 session cache。
- metadata/lifecycle/variant 变化通过新的 metadataVersion 和 type 14 mapping hash 生效；`DISABLED/DEFERRED` variant 不参与派生。目录回滚可能让派生条目暂时不可见，但不得改写 type 13 owned。

type 14 mapping hash 的 canonical 输入明确为：

```text
collectionId, collectionKey, itemSetId, catalogLifecycle,
classPolicy.mode, sorted(classPolicy.allowedClassKeys),
variants sorted by variantOrdinal:
  variantOrdinal, variantKey, isDefault, lifecycle,
  members sorted by (slotKey, memberKey):
    memberKey, slotKey, required, ordered appearanceIds[]
  omissions sorted by (itemId, reason):
    itemId, reason, slotKey-if-present
```

`appearanceIds[]` 的顺序同时是 APPLY 选择优先级，所以参与 Hash；`sourceItemIds` 若只作证据/显示则进入 evidence/presentation hash，若服务端实现实际读取它，必须提升 schema 并纳入 type 14 hash。名称、图标和 `uiLifecycle` 只进 presentation hash。任何影响完成度、职业资格、variant 选择或 APPLY 的字段都不得遗漏在 type 14 hash 外。

### 任务 8.4：定义可信 variant APPLY

- [x] 已完成（2026-07-22）。SC2 v1 Q 布局保持不变，`-` 与稳定正整数 variantOrdinal 语义已在 AddOn/C++ 双端落地；服务端重做 class、owned alternative、目标槽、费用和全量 preflight，伪造/跨 collection/deferred ordinal fail closed，任一成员失败零部分提交。

SC2 v1 Q 布局不变，type 14 的 `target` 明确定义为：

- `"-"`：请求生成目录中唯一 `isDefault=true` 的 active variant；
- 正十进制整数：collection 内稳定的 `variantOrdinal`，不是数组下标、ItemSetId、appearanceId 或 source itemId。

AddOn 只能从同一 generated catalog 发送 `(collectionId, variantOrdinal)`；服务端按该 pair 查找 active variant，并重新执行 classPolicy、owned、目标装备、费用和全部原子 preflight。客户端不得发送成员 appearance/source item。一个 member 有多个 owned `appearanceIds[]` 时，服务端按生成表顺序筛选“owned 且对目标槽兼容”的第一项；生成器用显式 override priority 排序，未覆盖时按 appearanceId 升序，保证 AddOn/C++ 字节一致。任一 required member 无候选时整套失败，费用和外观均不部分提交。

UI 的“当前 variant”、进度分母、部件图标和 APPLY target 必须使用同一个 `variantOrdinal`。不存在、disabled/deferred、非十进制或属于另一 collection 的 ordinal 返回 `INVALID_REQUEST`；mapping mismatch 先于 variant 解析 fail closed。自动测试至少覆盖默认 variant、显式非默认 variant、重排后 ordinal 稳定、多 owned alternatives 的确定性选择和伪造 ordinal。

### 任务 8.5：稳定 ID 和首个新增 fixture

- [x] 已完成（2026-07-22）。原 8 套 `300000..300007` 的 ID/key/ordinal/成员零漂移；牧师 T1 `ItemSetId=202` 作为 8 部件新增 fixture 通过，后续 ID 从 `300008` append-only 分配；Manual8 fixture 与 runbook flag 形式重建合同已落地。

- 保留现有 `300000..300007`、collection key 和 ordinal。
- 首先补入牧师 T1 `ItemSetId=202`“预言套装”，作为 importer 的第一个新增正确性 fixture。
- 后续 ID 只从 registry 追加；显示排序与 collection ID 分离。
- 撤回条目把 `catalogLifecycle` 改为 `TOMBSTONE` 并同步设置合适的 `uiLifecycle`，ID 仍永久保留。
- AddOn 与 module 使用同一个 normalized model 和同一个 type 14 mapping hash。

### 任务 8.6：套装 UI 容量

- [x] 已完成（2026-07-22）。详情区改为受上限约束的动态部件对象池和 8 列换行布局，不再以固定 8 个对象截断完整性；成员按稳定 slot 顺序显示，完整 465 目录筛选、搜索、1/59→2/59 翻页与 `/reload` 实机通过。

现有详情区固定创建 8 个部件图标。实现二选一，但必须在启用完整目录前明确完成：

1. 推荐：改为按 `maxActiveVisibleSlots` 建立受上限约束的动态对象池和换行布局；或
2. 过渡：生成器断言所有 active set 的 required visible slots 不超过 8，超过者保持 deferred。

不得截断第 9 个成员后仍把套装显示为完整。成员排序固定按 HEAD、SHOULDER、BACK、CHEST、WRIST、HANDS、WAIST、LEGS、FEET、武器槽及稳定 fallback。

### 自动测试

- 固定 evidence manifest 中保存 `rawRows/reviewUnits/nonempty/mapped/distinctSignatures/full/partial/unresolved/variants` 的精确整数 expected counters；`rawRows=reviewUnits=509`，每个 review unit 必有 accepted/excluded/deferred；测试逐项读取并精确比较。`475/466/约465/约438` 只作为本方案的人工诊断漏斗，自动测试中禁止使用“约”；
- 牧师 T1 ItemSet 202 存在且 8 个可见成员映射正确；
- 原 8 套 ID/key/ordinal/成员零漂移；
- ID、key、ordinal 唯一且 registry append-only；
- alternatives 不重复增加 required count，非外观成员不进入分母；
- variantOrdinal append-only 且每套恰有一个 active default；默认/显式 variant 请求、伪造 ordinal、跨 collection ordinal 和多 owned alternative 的确定性选择均覆盖；
- 对 classPolicy、variant lifecycle、member required/slot/appearance 顺序和 omissions 各做一次单字段漂移，type 14 mapping hash 必须变化；
- partial/unresolved 不得 active 应用；
- `ANY/ALLOW_LIST/UNRESOLVED` 与单/多职业均覆盖；
- type 14 完成度只读 type 13，数据库无 type 14 unlock 写入；
- 一件缺失或不兼容时整套原子失败；
- `generate_catalog.py --check` 和 `set_catalog.py --check` 发现任一生成物漂移；
- 删除 `len == 8` 合同，改为证据 Hash、已知套装、不变量和审核覆盖率。

### 真实客户端验收

- 牧师 T1、单职业套装、多职业 PvP 套装、不限职业套装、ICC 套装和含非外观成员的套装；
- 职业过滤、搜索、分页、进度、收藏状态、variant 和应用按钮；
- 缺一件、目标槽不兼容或费用失败时零部分应用；
- `/reload`、重登、worldserver 重启后进度一致；
- 完整目录下翻页和筛选没有逐帧全量构造或明显卡顿。

`Manual8` 不是口头开关：在迁移前把当前 8 套冻结为 `catalog/fixtures/sets/manual8.normalized.json`，记录来源 commit 和 mapping hash，并要求 `itemset_import.py --profile manual8 --output <F盘临时目录>` 可重建旧 Lua/C++ 投影。fixture 只用于等价性测试和紧急回滚，不再接受生产编辑。

回滚：用已验收 release bundle 中的 Manual8 Lua/C++ 生成投影成对恢复，或用上述 profile 在 F 盘 clean worktree 重建后核对 Hash；type 13 owned 数据不变，新增 type 14 ID 保留 tombstone。AddOn/module 必须配套回滚，mapping mismatch 时动作 fail closed。

阶段出口：single normalized schema 已取代双手工事实源；全局 `catalog/ids.json` 是唯一 ID 权威；现有 8 套逐项等价、牧师 T1 fixture 通过；每个候选都有 accepted/excluded/deferred；exact counters、alternatives 职业算法、type 14 派生/delta 和 UI 容量均通过自动化与真实客户端验收。

建议配套提交：

```text
catalog: import reviewed WotLK item sets
feat: support multi-class set policies
ui: scale set member presentation safely
```

## 14. 阶段 9：目录可见性治理、集成回归与发布

阶段目标：在扩大目录之后统一处理内部/测试/废弃内容，验证所有投影、协议、DLL 与模块版本匹配，并形成可回滚的本地候选包。本阶段不自动发布远程版本。

### 任务 9.1：建立外观可见性证据

- [x] 已完成（2026-07-22）。18,190 条 canonical appearance 全覆盖审核为 public 13,831、hidden_internal 1,375、deprecated 139、test 242、unobtainable 2,603、deferred 0；独立 `uiLifecycle` 不改变 canonical identity、owned 或服务端授权，Computer Use 实机确认客户端只投影 13,831 条 public 外观。详情见 `docs/reports/2026-07-20-appearance-visibility-review.md`。

新增建议：

```text
catalog/review/appearances/visibility-evidence.json
catalog/review/appearances/visibility-policy.json
catalog/source/overrides/appearance_visibility.json
catalog/generated/appearance-visibility-report.csv
docs/reports/2026-07-20-appearance-visibility-review.md
```

每条 canonical appearance 增加独立的 UI lifecycle：

```text
public
hidden_internal
deprecated
test
unobtainable
deferred
```

判断必须综合：

- World `item_template` 与显示资源存在性；
- 是否有可追溯来源或获取路径；
- flags、inventory type、quality、bonding 和显式 DB 状态；
- 名称中的 `Monster/Deprecated/TEST` 等只作为风险信号，不能单独作为删除依据；
- 人工 allow/deny override。

先生成 shadow 报告并逐项抽查，不直接删除 canonical identity。隐藏或撤回条目仍保留 collection ID 和已有账号 owned 行；动作是否禁用由 `catalogLifecycle` 明确决定，`uiLifecycle` 不得暗中改变服务端授权。

### 任务 9.2：增加运行时目录审计工具

- [x] 已完成（2026-07-22，随阶段 2 提前落地）。新增独立 QA AddOn、显式启动/导出脚本和 fail-closed 合同测试；以 4 PREVIEW/s 上限完成冷 WDB `281+24` 全扫，记录逐项状态、稳定 `GetModel()`、重试、耗时和 stale generation 探针，CSV/JSON 仅输出到 F 盘 `_work/runtime-audit`，正式 bundle 不包含该工具。

新增一个不随正式 AddOn 发布的 QA 工具：

```text
tools/runtime/SoloCollectionsRuntimeAudit/
```

能力：

- 以不超过每秒 4 次的速率遍历 mount/companion PREVIEW；
- 记录 typeId、collectionId、previewCreatureEntry、PREVIEW 状态、`GetModel()`、重试次数和耗时；
- 记录过期 generation 是否被正确丢弃；
- 生成 CSV/日志到 F 盘 `_work/runtime-audit/`；
- 不发送 SUMMON/USE/APPLY，不修改收藏状态；
- 默认不进入发行包，必须显式 QA 构建才加载。

### 任务 9.3：跨仓库版本与生成物核对

- [x] 已完成（2026-07-22）。release/runbook 八个脚本、deployment profile schema、x64 PE/依赖/provenance 校验、逐文件 Hash、事务备份/恢复、配置合并、installed verifier、startup/status build-info 和仓库卫生门禁均落地；真实 D 盘安装覆盖 41 个既有文件并保留完整 backup manifest，锁定 MPQ 的首次尝试已自动回滚，未执行远程发布。

本阶段必须实现以下 release/runbook 工具，而不是只在文档里写“配套部署”：

```text
tools/release/deployment-profile.schema.json
tools/release/Initialize-RoundTwoEnvironment.ps1
tools/release/New-SoloCollectionsBuildInfo.ps1
tools/release/New-RoundTwoBundle.ps1
tools/release/Test-RoundTwoBundle.ps1
tools/release/Install-RoundTwoBundle.ps1
tools/release/Restore-RoundTwoBundle.ps1
tools/release/Test-RepositoryHygiene.ps1
```

Git 忽略的 `_work/deployment-profile.local.json` 至少显式声明 `serverRoot`、`worldserverExeTarget`、`worldserverWorkingDirectory`、`worldserverDependencyTargets[]`、`runtimeModuleConfig`、`addonRoot`、`clientRoot`、`soloCamDllTarget`、`assetPatchTargets[]`、`wdbRoots[]`、`backupRoot` 和 `serverControl`。安装/恢复脚本必须先解析绝对路径，拒绝任何 C 盘目标，拒绝越出各自声明根目录的路径，拒绝通配符目标；每次覆盖前把原文件复制到 `_work/releases/<bundleId>/backup/` 并生成 manifest。源码库内只提交 schema 和脚本，不提交这份本地 profile。

`serverControl` 只允许：

- `WINDOWS_SERVICE`：配置明确 `serviceName` 和 `expectedExecutable`；脚本用服务配置反查 executable，只有规范化路径等于 `worldserverExeTarget` 才允许 stop/start，并等待服务进入目标状态；
- `EXTERNAL_COMMAND`：配置明确的 F/D 盘 stop/start 脚本、SHA-256 和工作目录；脚本返回非零立即终止；
- `MANUAL`：安装脚本不执行 kill，只在操作者已关闭进程且 `worldserverExeTarget` 可独占打开时继续。

禁止按进程名批量 `Stop-Process`、禁止猜 PID、禁止停止路径不匹配的服务。

生成和核对：

- AddOn generated catalog；
- module mount/companion/toy/appearance/set generated inc/json；
- SC2 schema/golden vectors；
- camera profile Lua/C++ mapping hash；
- SoloCam DLL build metadata；
- local MPQ/DBC asset manifest；
- release manifest 中的 commit、metadataVersion、assetPackVersion、mapping hash 和 SHA-256。

bundle 固定布局：

```text
_work/releases/<bundleId>/
  release-manifest.json
  addon/SoloCollections/
  server/worldserver.exe             # MODULES=static，本轮 C++ 已编入此 PE
  server/runtime-dependencies/       # 仅收集非系统且确实需要配套替换的 DLL
  server/config/transmog.conf.dist
  server/module-build-metadata.json
  server/symbols/worldserver.pdb.sha256  # 只记录本地符号文件 Hash/位置；PDB 不默认部署
  client/SoloCam.dll
  client/assets/<批准的 patch 文件>
  evidence/evidence-manifest.json
  backup/                         # 安装时创建，不进入发布归档
  reports/
```

Core 使用 `MODULES=static`，因此不存在可单独复制的 module DLL。clean build 在编译前生成 `src/generated/SoloCollectionsBuildInfo.inc`，写入 AddOn、module、Core commit、metadataVersion、assetPackVersion 和 type mapping hashes；这些常量由 `.solocollections status` 与 startup log 输出。构建结束后 `module-build-metadata.json` 记录同一组值、CMakeCache SHA-256、generator/platform、MSVC version、配置、`worldserver.exe` SHA-256 和本地 PDB SHA-256。

为此需修改 `mod-solo-collections/src/SoloCollectionsCommands.cpp`、`SoloCollectionsProtocolScript.cpp` 和启动日志注册点，读取 generated build info；状态命令输出必须有稳定、可机器解析的 `key=value` 行，供 installed verifier 比较，不能只输出自由文本。

`New-RoundTwoBundle.ps1` 只接受显式 `-WorldserverPath`，要求它位于传入的 clean Core build root、修改时间晚于本次 build start 且 PE 为 x64；然后用固定的 PE import 检查区分 Windows 系统 DLL、部署环境已固定依赖和必须随包更新的非系统 DLL。当前 static module 预期没有 SoloCollections 专用 DLL；任何新增非系统依赖都必须在 release manifest 和 `worldserverDependencyTargets[]` 一一列出，禁止复制整个 build `bin` 目录。

`Test-RoundTwoBundle.ps1` 逐文件重算 SHA-256，确认 `worldserver.exe` 是 x64 PE，交叉比较 AddOn generated constants、module build metadata、release manifest、camera hash、assetPackVersion 和三个 commit；安装后的健康检查再比较 `.solocollections status` 中的编译常量。缺少外部资产时可以构造不含该能力的 bundle，但 manifest 必须标记 `UNAVAILABLE`，不能保留 `verified`。

部署/健康检查命令合同：

```powershell
$repo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\SoloCollections'
$profile = Join-Path $repo '_work\deployment-profile.local.json'
# $cleanAddon/$cleanModule/$cleanCore/$cleanCoreBuild/$cleanWorldserver/$evidence 由 15.4 固定
$utc = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$addon7 = (git -C $cleanAddon rev-parse --short=7 HEAD).Trim()
$module7 = (git -C $cleanModule rev-parse --short=7 HEAD).Trim()
$core7 = (git -C $cleanCore rev-parse --short=7 HEAD).Trim()
$bundleId = "round2-$utc-$addon7-$module7-$core7"
$bundle = Join-Path $repo "_work\releases\$bundleId"

& "$repo\tools\release\New-RoundTwoBundle.ps1" `
  -BundleId $bundleId `
  -AddonRoot $cleanAddon `
  -ModuleRoot $cleanModule `
  -CoreRoot $cleanCore `
  -CoreBuildRoot $cleanCoreBuild `
  -WorldserverPath $cleanWorldserver `
  -EvidenceRoot $evidence `
  -OutputRoot $bundle
& "$repo\tools\release\Test-RoundTwoBundle.ps1" -BundleRoot $bundle
& "$repo\tools\release\Install-RoundTwoBundle.ps1" -BundleRoot $bundle -Profile $profile -StopServer
# 在 worldserver 控制台检查：
# .solocollections status
# .transmog reload                 # 仅配置变更时
& "$repo\tools\release\Test-RoundTwoBundle.ps1" -BundleRoot $bundle -Profile $profile -Installed
```

部署顺序：

1. 停服并记录当前模块、AddOn、DLL、MPQ、DBC 和数据库状态。
2. 备份并部署 bundle 中已静态编入 module 的 `worldserver.exe`、明确列出的非系统 runtime dependencies、实际 `transmog.conf` 合并项与生成目录；installer 的服务端目标就是 profile 中的 `worldserverExeTarget`，不是 metadata 文件。
3. 部署匹配的 AddOn、SoloCam 和客户端资源。
4. 启动 worldserver，检查 provider/mapping/asset 健康状态。
5. 执行空 WDB 与热 WDB 客户端矩阵。
6. 完成后再标记本地 release candidate；未经明确授权不推送 GitHub 或创建公开 release。

恢复合同：

```powershell
& "$repo\tools\release\Restore-RoundTwoBundle.ps1" `
  -BackupManifest (Join-Path $bundle 'backup\backup-manifest.json') `
  -Profile $profile `
  -StopServer
```

恢复脚本先校验 backup SHA-256，再成套恢复 module/AddOn/DLL/asset/config；恢复后要求 `.solocollections status`、一条 PREVIEW 和原 281/24/4/8 smoke matrix 通过。不得通过递归删除客户端或覆盖整个服务端根目录回滚。

### 任务 9.4：性能回归

- [x] 已完成（2026-07-22）。Addon 与 C++ 均固定 18,190 appearance、201 companion candidate、509 ItemSet shadow 压力分母；真实客户端首开/过滤/分页保持固定对象池，展开加载 22.407 ms、峰值约 6.7 MiB、快照重组 8.623 ms，服务器只读索引 benchmark 为 load/filter/lookup 55/49/350 μs，无 DB 查询或逐次全目录扫描。详情见 `docs/reports/2026-07-22-round-two-performance-regression.md`。

- 扩充后的宠物、玩具和套装继续使用固定 UI 对象池，不逐帧复制全目录。
- catalog load、搜索、过滤、分页和集合进度增加基线计时。
- C++ 目录保持只读索引；PREVIEW 不做 DB 查询，不逐次扫描全目录。
- 以 509 条套装 shadow 上界、约 201 条宠物候选和现有 18k 外观同时加载做压力基线；登录快照、UI 首开和翻页不得出现明显回退。正式 active 数仍以审核结果为准。
- 性能失败必须定位到 provider/生成投影/UI，而不是通过减少正式数据数量掩盖。

阶段出口：可见性审核完成；所有版本和 Hash 匹配；本地候选包通过干净检出、编译、自动化和真实客户端验收；未发生未授权发布。

建议提交：

```text
catalog: add reviewed appearance visibility lifecycle
tools: add read-only runtime collection audit
docs: record round two integrated acceptance
```

## 15. 自动测试布局与命令

所有生成、Python cache、native build 和临时输出放在 F 盘仓库内的 `_work`/`_build` 或显式 F 盘目录，不向 C 盘写入。

先在每个新 PowerShell 进程执行环境初始化；脚本创建目录后设置 `TEMP/TMP/PYTHONPYCACHEPREFIX/PIP_CACHE_DIR`，并在任一解析值位于 C 盘时终止：

```powershell
$addonRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\SoloCollections'
$moduleRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\mod-solo-collections'
$repo = $addonRepo
$workRoot = Join-Path $addonRepo '_work\round-two'
& "$addonRepo\tools\release\Initialize-RoundTwoEnvironment.ps1" -WorkRoot $workRoot
```

不得在验收命令中临时 `pip install` 或下载工具；Python、CMake、MSVC、Lua 5.1 和资产解析器必须来自阶段 0 已固定的 toolchain manifest。若某工具只能读取 C 盘已安装程序，可以读取，但输出和缓存仍必须被重定向到 F 盘。

### 15.1 `SoloCollections`

目录生成漂移：

```powershell
Set-Location -LiteralPath $addonRepo
$env:PYTHONDONTWRITEBYTECODE = '1'
$evidence = Join-Path $repo '_work\evidence\<evidenceId>'

python tools\catalog\generate_catalog.py `
  --module-root ..\mod-solo-collections `
  --evidence-root $evidence `
  --check

python tools\catalog\set_catalog.py `
  --module-root ..\mod-solo-collections `
  --evidence-root $evidence `
  --check
```

新增生成器统一实现四个子命令，避免“只有 `--check`、没有如何生成”的缺口：

```powershell
$evidence = Join-Path $repo '_work\evidence\<evidenceId>'
$reviewOut = Join-Path $repo '_work\round-two\review'

python tools\catalog\creature_presentations.py extract --evidence-root $evidence --out "$reviewOut\creatures"
python tools\catalog\companion_catalog.py extract --evidence-root $evidence --out "$reviewOut\companions"
python tools\catalog\toy_catalog.py extract --evidence-root $evidence --out "$reviewOut\toys"
python tools\catalog\itemset_import.py extract --evidence-root $evidence --out "$reviewOut\sets"
python tools\catalog\appearance_presentations.py extract --evidence-root $evidence --out "$reviewOut\weapons"
python tools\catalog\character_camera_profiles.py extract --evidence-root $evidence --out "$reviewOut\camera"

# 审核人将决定写入各 catalog\review\<category>\decisions.json 后：
python tools\catalog\generate_catalog.py --module-root ..\mod-solo-collections --evidence-root $evidence --validate-review
python tools\catalog\generate_catalog.py --module-root ..\mod-solo-collections --evidence-root $evidence --generate
python tools\catalog\generate_catalog.py --module-root ..\mod-solo-collections --evidence-root $evidence --check
```

`extract` 只写 F 盘 `_work`，不改生产源；`--validate-review` 要求 accepted/excluded/deferred 全覆盖且理由合法；只有显式 `--generate` 更新 Git 内规范源/投影；`--check` 只读并要求字节一致。主 `generate_catalog.py` 必须覆盖 companion、toy、ItemSet、presentation 和 camera 子生成器。

合同测试：

```powershell
python -B -m unittest discover `
  -s tools\collections\tests `
  -p "test_*.py" `
  -v
```

SoloCam Python 与 x86 native/DLL：

```powershell
python -B -m unittest discover `
  -s client-extension\SoloCam\tests `
  -p "test_*.py" `
  -v

& .\client-extension\SoloCam\scripts\build.ps1
```

该脚本已经通过 `vcvarsall.bat x86` 编译，不使用默认 CMake architecture。扩展脚本在结束前执行 PE header 校验，要求 `SoloCam.dll` 和 loader probes 的 machine 为 `0x014c (x86)`，否则构建失败。脚本把 x86 tests、DLL、obj 和临时文件写入 `client-extension/SoloCam/build`，并把进程 `TEMP/TMP` 指向该 F 盘目录；不要改回系统临时目录。

最低新增测试文件：

```text
tools/collections/tests/test_companion_catalog.py
tools/collections/tests/test_toy_catalog.py
tools/collections/tests/test_itemset_import.py
tools/collections/tests/test_presentation_catalog.py
tools/collections/tests/test_camera_catalog.py
tools/collections/tests/test_preview_contract.py
```

### 15.2 `mod-solo-collections`

Python contracts：

```powershell
Set-Location -LiteralPath $moduleRepo
$env:PYTHONDONTWRITEBYTECODE = '1'
python -B -m unittest discover -s tests -p "test_*.py" -v
```

Native tests：

```powershell
Set-Location -LiteralPath $moduleRepo
$nativeBuild = Join-Path $PWD '_build\native-round-two'
cmake -S tests\native -B $nativeBuild -G "Visual Studio 18 2026" -A x64
cmake --build $nativeBuild --config Release
ctest --test-dir $nativeBuild -C Release --output-on-failure
```

必须扩展：

- `SoloCollectionsProtocolTests`：PREVIEW、未收藏、replay、limit、失败状态和零 revision；
- `SoloCollectionsDomainTests`：可信 collection→Creature Entry、companion unlock variants、toy action、set class policy；
- phase 5/6/7/9 Python contracts：生成文件、handler 分支和禁止项；
- 当前 AzerothCore/NPCBots Core 的真实 Release 或 RelWithDebInfo `worldserver` 构建。

开发阶段的快速集成门槛可以使用当前已审计的 F 盘 VS18 x64 build tree；它只证明当前工作环境可编译，不能作为最终 RC 的 provenance。不运行 `install` target，避免写入其 D 盘 install prefix：

```powershell
$coreRoot = 'F:\1_projects\wow_projects\azerothcore-wotlk'
$coreBuild = Join-Path $coreRoot 'build-npcbots-vs18'
cmake --build $coreBuild --config RelWithDebInfo --target worldserver
```

若 `CMakeCache.txt` 的 Core commit、generator 或 `CMAKE_GENERATOR_PLATFORM` 不是阶段 0 记录的 `Visual Studio 18 2026/x64`，先在新的 F 盘 build tree 重新 configure；不得复用不明旧缓存。新 `SoloCollectionsCreaturePreviewService.cpp` 必须显式加入 `tests/native/CMakeLists.txt` 对应 test target，并通过真实 worldserver build 证明 AzerothCore module auto-discovery 已将它编入模块。

### 15.3 通用质量门槛

每个提交在两个仓库分别执行，不得只在当前目录运行一次：

```powershell
$addonRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\SoloCollections'
$moduleRepo = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\mod-solo-collections'
git -C $addonRepo diff --check
git -C $addonRepo status --short --branch
git -C $moduleRepo diff --check
git -C $moduleRepo status --short --branch

& "$addonRepo\tools\release\Test-RepositoryHygiene.ps1" -RepoRoot $addonRepo
& "$addonRepo\tools\release\Test-RepositoryHygiene.ps1" -RepoRoot $moduleRepo
```

每个阶段出口还必须：

- Lua 5.1 语法检查。`$env:SOLOCOLLECTIONS_LUAC51` 必须指向阶段 0 已固定的 F/D 盘 `luac.exe`；逐个执行 `luac -p`，变量缺失时失败而不是跳过；
- 主目录与 set/presentation/camera 生成 `--check`；
- 两仓库配套 mapping/version 检查；
- `Test-RepositoryHygiene.ps1` 扫描凭据模式、未批准二进制、数据库 dump、DBC/M2/BLP/MPQ/DLL/EXE/WDB 和超大文件；允许版本化 SQL migration，但拒绝未列入 allowlist 的 dump；
- 对阶段对应的真实客户端结果建立报告。

Lua 语法命令合同：

```powershell
$luac51 = $env:SOLOCOLLECTIONS_LUAC51
if (-not (Test-Path -LiteralPath $luac51 -PathType Leaf)) { throw 'Lua 5.1 luac not pinned' }
git -C $addonRepo ls-files '*.lua' | ForEach-Object {
  & $luac51 -p (Join-Path $addonRepo $_)
  if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $_" }
}
```

### 15.4 干净检出重建

“clean checkout”必须与固定 evidence pack 配对。最终 RC 使用 F 盘临时 worktree，不从 C 盘或开发工作树偷取生成物：

```powershell
$coreRepo = 'F:\1_projects\wow_projects\azerothcore-wotlk'
$cleanRoot = Join-Path $repo '_work\clean-checkout\<bundleId>'
New-Item -ItemType Directory -Force -Path $cleanRoot | Out-Null

$addonCommit = (git -C $addonRepo rev-parse HEAD).Trim()
$moduleCommit = (git -C $moduleRepo rev-parse HEAD).Trim()
$coreCommit = (git -C $coreRepo rev-parse HEAD).Trim()
$cleanAddon = Join-Path $cleanRoot 'SoloCollections'
$cleanModule = Join-Path $cleanRoot 'mod-solo-collections'
$cleanCore = Join-Path $cleanRoot 'azerothcore-wotlk'
$cleanCoreBuild = Join-Path $cleanRoot 'core-build'

git -C $addonRepo worktree add --detach $cleanAddon $addonCommit
git -C $moduleRepo worktree add --detach $cleanModule $moduleCommit
git -C $coreRepo worktree add --detach $cleanCore $coreCommit

$moduleLink = Join-Path $cleanCore 'modules\mod-solo-collections'
if (Test-Path -LiteralPath $moduleLink) { throw "Unexpected module path: $moduleLink" }
New-Item -ItemType Junction -Path $moduleLink -Target $cleanModule | Out-Null

python "$cleanAddon\tools\catalog\generate_catalog.py" `
  --module-root $cleanModule `
  --evidence-root $evidence `
  --check

& "$cleanAddon\tools\release\New-SoloCollectionsBuildInfo.ps1" `
  -AddonRoot $cleanAddon `
  -ModuleRoot $cleanModule `
  -CoreRoot $cleanCore `
  -EvidenceRoot $evidence `
  -OutputFile "$cleanModule\src\generated\SoloCollectionsBuildInfo.inc"

cmake -S $cleanCore -B $cleanCoreBuild `
  -G "Visual Studio 18 2026" -A x64 `
  -DMODULES=static -DSCRIPTS=static -DTOOLS_BUILD=none `
  "-DCMAKE_INSTALL_PREFIX=$cleanRoot\install"
cmake --build $cleanCoreBuild --config RelWithDebInfo --target worldserver

$cleanWorldserver = Join-Path $cleanCoreBuild 'bin\RelWithDebInfo\worldserver.exe'
if (-not (Test-Path -LiteralPath $cleanWorldserver -PathType Leaf)) { throw 'Clean worldserver build missing' }
```

`New-SoloCollectionsBuildInfo.ps1` 是唯一允许在 clean module worktree 产生的额外文件；它从三个已固定 HEAD、生成 catalog、evidence manifest 生成确定性常量，生成后再次运行 module tests。报告要求 `git status --short` 除该文件外为空。随后在三个 worktree 执行全部 Python、native、Lua、hygiene 和 bundle 构建，并把 `$cleanWorldserver` 传给 `New-RoundTwoBundle.ps1`。验收报告记录三个 commit、CMakeCache Hash、evidence ID、worldserver PE/PDB Hash 和所有目录 Hash；worktree 在报告签字前保留。

清理时分别用三个源仓库的 `git worktree remove` 指向已验证位于 `_work\clean-checkout\<bundleId>` 下的精确目录；先删除已验证的 junction 本身而不跟随 target，再移除 Core worktree。不得递归删除宽泛根目录。

## 16. 真实客户端验收矩阵

### 16.1 功能矩阵

| 问题域 | 必验条件 | 通过标准 | 证据 |
|---|---|---|---|
| 坐骑图标 | 当前 281 条、冷启动、搜索/筛选 | active 条目零全局占位，合法重复保留 | 图标审计报告 + 抽样截图 |
| 坐骑模型 | 空 WDB、未收藏、快速切换 | 281 条 PREVIEW accepted 且限定窗口内 `GetModel()` 非空 | RuntimeAudit CSV + 失败为 0 |
| 宠物图标/模型 | 全部正式 accepted 条目 | 图标可区分、冷/热缓存均零空模型 | RuntimeAudit + 全目录滚动 |
| 宠物动作 | 召唤、替换、同宠物 toggle、重登 | 不影响战斗/任务宠物，owned 权威 | worldserver/客户端日志 |
| 边框 | collected/uncollected/selected/hover | 状态边约 1px、选中边约 2px、无粗黄带 | 多分辨率截图 |
| 玩具布局 | 满页、残页、搜索 1/2/4 条 | 左右 margin 对称，首列不压外框 | 像素/逻辑坐标记录 |
| 玩具动作 | 每个新增 accepted 条目 | 目标、冷却、材料、重放和清理符合声明 | 逐项验收表 |
| 独立武器 | 21 个 verified 资源 + 缺资源样例 | verified 只见武器；缺资源只见图标提示 | 21 项截图/录像 |
| 角色相机 | 10 race × 2 sex × 9 slot | human/female 零回归；其余可用且无串 profile | 180 项矩阵 |
| 套装 | 牧师 T1、多职业、不限职业、partial | 筛选、进度和原子应用正确 | 套装验收报告 |
| 可见性 | public/internal/test/deprecated 抽样 | 内部条目不进入普通玩家目录，ID/owned 不丢 | shadow/active 对比 |

### 16.2 分辨率/UI Scale

| 分辨率 | UI Scale | 重点 |
|---|---:|---|
| 1024×768 | 1.00 | 窗体最小缩放、1px 边不丢失 |
| 1366×768 | 1.00 | 三列网格不挤压、左右对称 |
| 1920×1080 | 1.00 | 设计基准、模型与相机构图 |
| 1920×1080 | 0.80 / 0.64 | 半像素、模糊和锚点漂移 |
| 2560×1440 | 常用值 | 窗体上限与网格居中 |
| 3440×1440 | 常用值 | 超宽屏位置恢复和 margin |

### 16.3 状态与时序

每个需要模型或相机的页面至少覆盖：

- 首次登录与热缓存登录；
- `/reload`；
- 关闭/重新打开收藏窗；
- 快速连续切换 20 条记录；
- 翻页、过滤和返回上页；
- SC2 断开、mapping mismatch、握手 assetPackVersion mismatch，以及本地 verifier 制造的 DLL/MPQ SHA mismatch；二者证据分开记录；
- AddOn 新/旧与 module 新/旧的受控不匹配；
- worldserver 重启；
- 同账号另一个角色和不同账号。

任何空模型、黑模、棋盘格、角色串入武器卡片、上一种族相机残留或无限重试都属于失败，不得以“多数正常”关闭阶段。

## 17. 回滚策略

### 17.1 代码与部署

- 每个阶段保留上一组已编译、已验收的 AddOn/module/DLL/资源 manifest 和 SHA-256。
- 不使用 `git reset --hard`、递归删除或覆盖用户工作树作为回滚手段。
- 跨仓库协议/目录变更使用配套 commit；回滚时 AddOn 与 module 同步恢复，否则让 mapping mismatch 主动 fail closed。
- 客户端 AddOn、SoloCam、MPQ、DBC patch 是一个匹配 bundle；不能只回滚其中一个文件后继续验收。

### 17.2 分类回滚

| 分类 | 回滚方式 | 必须保留 |
|---|---|---|
| 图标/展示字段 | 回退 metadata 和生成投影；单条缺失显示 fallback | collection ID、owned |
| PREVIEW | 关闭 `SoloCollections.Preview.Enabled` 或回退配套 module/AddOn | ALE 继续关闭；SUMMON 权限不变 |
| 独立武器 | 回退 presentation manifest；资源不匹配时使用合法 `renderMode=UNAVAILABLE` | 21 个 synthetic ID tombstone、canonical owned |
| 相机 | generated profile 切回 human-female reference/native camera 1 | human/female 9 条 reference、profile ID |
| UI | 回退独立 UI commit | 目录和收藏状态不变 |
| 宠物/玩具/套装 | `catalogLifecycle=DISABLED/TOMBSTONE` 或回退已验收旧 bundle | 新 ID 与数据库行不删除、不复用 |
| 可见性 | 切回 shadow 或上一审核策略 | canonical ID、owned、审核记录 |

### 17.3 数据库

- PREVIEW、图标、边框、相机、武器 presentation 和套装派生进度不需要 SQL migration。
- 新增宠物/玩具可能产生新的通用 unlock 行；回滚版本必须忽略未知 ID，不删除这些行。
- type 14 套装继续由 type 13 派生，不产生独立 unlock 行，因此套装目录回滚不做逆向 SQL。
- 如果错误目录已授予收藏，先设置 `catalogLifecycle=DISABLED` 并保留审计，再单独编写可预览的修复 migration；本方案不授权直接删除生产行。

### 17.4 触发回滚条件

- PREVIEW 能造成实体、spell、DB、revision 或越权副作用；
- 未收藏 SUMMON/USE/APPLY 因本轮改动被接受；
- AddOn/module mapping 相同却解析到不同 collection 或 Creature Entry；
- 客户端稳定崩溃、黑模、无限放大或跨卡片串相机；
- 原 281 坐骑、24 宠物、4 玩具、8 套或 21 武器出现已知功能回归；
- 新目录 ID 重排/复用，或候选没有完整审核决定；
- 目录/资源无法从干净 checkout 加固定 evidence pack 重建。

## 18. 推荐执行批次与提交边界

不得同时开始大规模宠物、玩具、套装和全量武器资源生成。推荐批次：

1. **批次 A：冻结与回归修复**

   - 阶段 0：基线报告和失败用例；
   - 阶段 1：展示字段与图标；
   - 阶段 2：SC2 PREVIEW；
   - 阶段 3：恢复 21 个独立武器；
   - 阶段 4：细边框与玩具网格。

   只有当前 281/24/4/8 数据在真实客户端重新通过，才能进入内容扩充。

2. **批次 B：相机矩阵**

   - 先把 human/female 迁移到生成源且零漂移；
   - 再生成其他 19 个组合的 scaled profile；
   - 先验收 HEAD/CHEST/FEET 作为早期闸门，再让全部 9 部位逐项通过首轮可用标准；
   - AddOn、DLL、profile manifest 作为一个包切换。

3. **批次 C：内容扩充**

   - 阶段 6：companion schema v2、现有 24 等价、审核新增；
   - 阶段 7：审核旧 36 玩具并分风险批次启用；
   - 阶段 8：ItemSet importer shadow、牧师 T1、职业契约、完整目录切换。

   三个类别按顺序完成数据库、生成、模块、AddOn 和实机闭环，不并行切换生产 mapping。

   批次 C 的 evidence 提取和 shadow 报告可以在批次 B 后半段只读并行，但任何生产目录/mapping 切换都必须等批次 B 的 180 项相机阶段出口关闭；不得让 AddOn 目录、SoloCam profile 和三个内容类别同时处于迁移态。

4. **批次 D：治理与候选发布**

   - 阶段 9：外观可见性、RuntimeAudit、性能、干净检出和本地 release candidate。

提交边界：

- 证据/报告、生成器、协议/后端、AddOn 消费者、UI、客户端 DLL、内容数据分别提交；
- 跨仓库 SC2 或 mapping 变更在提交信息中记录配套 commit；
- 目录扩充不与 handler 新功能混为一个巨大提交；特殊玩具 handler 一项一个提交；
- 每个提交保持测试绿色；red 测试与对应修复同提交，不在主分支长期保留 expected failure；
- 每个批次完成后打本地、可回退的里程碑 tag，再进入下一批。

本地 tag 命令合同（示例中的值由实际 bundle manifest 替换）：

```powershell
$bundleId = '<bundleId>'
$batch = 'a'  # a/b/c/d
git -C $addonRepo tag -a "solo-collections/round2-$batch-$bundleId" -m "Round 2 batch $batch; paired module commit <sha>"
git -C $moduleRepo tag -a "solo-collections/round2-$batch-$bundleId" -m "Round 2 batch $batch; paired addon commit <sha>"
```

tag 只在对应批次全部闸门通过后创建；本方案不授权 push。回滚脚本按 release manifest 中记录的 commit/Hash 和 backup manifest 恢复，不靠“最新 tag”猜版本。

## 19. 本轮总体验收定义

以下全部满足后，本轮才算完成：

- [x] `Catalog.lua` 不再为 active 坐骑/宠物批量写死默认图标。
- [x] Creature Entry 与 DisplayInfo ID 使用不同字段名和不同验证规则。
- [x] `Backend=Cpp`、ALE 关闭、空 WDB 下，281 个坐骑和全部正式宠物零空模型。
- [x] PREVIEW 未收藏可查看，但 SUMMON/USE/APPLY 仍由 C++ owned/资格校验；PREVIEW 零 DB/revision/实体副作用。
- [x] UI 仅在 PREVIEW 成功且 generation 匹配时加载模型，失败有明确提示。
- [x] 坐骑、宠物、玩具状态边为细边，选中态独立；玩具三列左右 margin 对称。（2026-07-22；七档真实客户端矩阵全部 READY，见阶段 4 报告。）
- [x] 原 21 个武器只显示武器；其余缺资源主副手不显示角色。（2026-07-22；21/21 READY、正式衣橱与 stock fallback 证据见阶段 3 报告。）
- [x] human/female 相机逐值无回归；10 种族×2 性别×9 部位共 180 项全部通过首轮“可见、居中、无危险裁切/串 profile”标准并完成矩阵记录；`scaled` 可留待后续像素级 `verified`。（2026-07-22；接受运行 `20260722-063149-157`，见阶段 5 报告与逐行审阅 CSV。）
- [x] 宠物候选逐项 accepted/excluded/deferred；现有 24 ID 不变，新增 ID append-only。（2026-07-22；201/201 候选已审核，冷/热 482/482 READY，动作/隔离/重启闭环与清理证据见阶段 6 报告。）
- [x] 旧 36 玩具全部有审核结论；现有四条无回归；新增 handler 逐项验收。（2026-07-22；accepted 9、deferred 27、excluded 0，自动化、真实客户端、重启/隔离及清理证据见阶段 7 报告。）
- [x] ItemSet 单一 normalized model 取代双手工事实源；牧师 T1 存在；单/多/不限职业正确；最终 active 数有完整审核依据。（2026-07-22；509 项全审核、465 active、Manual8 零漂移与真实客户端证据见阶段 8 报告。）
- [x] type 14 仍只从 type 13 派生，不新增套装 unlock 写入；UI 与服务端按稳定 variantOrdinal 选择同一 variant，alternatives 确定且原子应用。（2026-07-22；1/8→7/8→8/8→0/8 同 revision 派生链路、缺目标槽零部分结果与清理闭环见阶段 8 报告。）
- [x] 内部/测试/废弃外观不再直接进入普通玩家目录，canonical ID 和已有 owned 不丢失。（2026-07-22；18,190 条全覆盖，实机 `public=13831/nonpublic=4359`。）
- [x] 所有生成器 `--check`、Python tests、Lua 5.1、SoloCam x86 native、module native 和真实 AzerothCore worldserver 构建通过。（2026-07-22；最终命令与结果见集成验收报告。）
- [x] 分辨率/UI Scale、冷/热缓存、快速切换、重载、重登、重启和账号隔离矩阵通过。（2026-07-22；阶段 1–8 实机报告和阶段 9 性能补证共同闭合。）
- [x] AddOn、module、Core 三个 commit与实际部署的 x64 `worldserver.exe`、客户端 bundle、metadataVersion、assetPackVersion、mapping hash 与 SHA-256 可追溯。（2026-07-22；release manifest、module build metadata 与 startup build-info 三方一致。）
- [x] 源代码仓库不包含凭据、数据库转储、DBC/M2/BLP/MPQ、DLL/EXE、WDB 或构建产物。（2026-07-22；`Test-RepositoryHygiene.ps1` 对 AddOn/module/Core 通过；固定 Core commit 的 3 个既有 upstream MySQL CLI 和 1 个 gSOAP 误报文件以精确相对路径显式批准，外部证据与 bundle 仅在 Git 忽略的 F 盘 `_work`。）

## 20. 明确留到后续的工作

- 为全部约 5,957 个主副手 canonical 外观批量生成独立 M2/skin/texture/synthetic DBC 资源；本轮只恢复 21 个 verified 样例并建立 manifest/失败语义。
- 将所有 `scaled` 相机逐项人工升级为像素级 `verified`；本轮先保证 20 个组合有可用基线并完成矩阵记录。
- 导入高版本坐骑、战宠、玩具、套装、传家宝、幻象、附魔外观或 HD 角色模型。
- 自动推断或实现高风险玩具的传送、经济、生成物品和持久对象 handler。
- 按资料片、团队层级、PvP 赛季、阵营、配色和难度为套装建立更丰富的 UX 分组；任何语义合并仍需显式证据。
- 为大目录增加更丰富的来源、资料片、稀有度、阵营和获取方式过滤器。
- 公开发布、远程推送和正式生产数据库部署；这些必须在本轮本地候选验收完成后另行授权。
