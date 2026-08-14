# ezCollections 外观物品页迁移实施方案

**目标：** 外观页的“物品”标签完整采用 ezCollections 的页面和模型显示；目录、收藏状态、权限与应用操作继续使用 SoloCollections/SC2。

**范围：** 只处理外观页的物品标签。套装标签保留现状，幻化页不处理，外层收藏窗口和底部主导航不更换。

## 当前基线

> 本节记录 2026-08-13 启动迁移时的基线。2026-08-14 的武器实现由“迭代 8”接管，护甲实现由“迭代 11”接管；其中固定预览 Creature、ezCollections 物品镜头和“DLL 不参与物品卡”的旧结论不再是当前边界。

当前不是从零迁移，已经具备以下 ezCollections 显示能力：

- 18 张固定复用模型卡和 6 列 × 3 行分页。
- 78×104 的 ezCollections 卡片尺寸。
- `EzCollectionsCamera.lua` 中的 Classic 种族、性别、装备部位镜头表。
- ezCollections 武器分类镜头查找表。
- 护甲卡片通过玩家模型、`TryOn` 和静态动画帧显示。
- 武器卡片已开始使用固定预览 Creature 和 `TryOn`。
- 同一护甲部位翻页时保留镜头的缓存与恢复逻辑。
- 板甲、锁甲、皮甲、布甲筛选，以及按当前角色职业选择默认护甲类型的逻辑。

当前仍是 SoloCollections 页面与部分 ez 模型代码混合运行，尚未完整迁移：

- ezCollections 的 `SetType(player/main/off)` 模型类型状态机。
- ezCollections 的 `Reload()` 和跨类型状态清理。
- 完整的武器主手/副手生命周期。
- ezCollections 物品页 XML、卡片交互、筛选器和页面显示。
- ez 页面与现有 Catalog/Bridge 之间的专用薄适配器。

实施时复用已经正确的镜头表、卡片尺寸和护甲翻页成果；替换不完整的混合生命周期，不重复重写现有 SoloCollections 数据层。

## 固定边界

- ezCollections 负责：页面布局、18 张物品卡、筛选控件和卡片状态；不再驱动物品卡的 3D 模型。
- Transmorpher 负责全部物品卡的显示语义：玩家 `DressUpModel`、原生 `Undress/TryOn`、种族/性别/部位或武器子类构图、朝向和动画序列。
- 单一 SoloCam DLL 只提供本地武器预览桥；不得复制 Transmorpher 完整 DLL，也不得取得收藏状态、权限或应用动作的控制权。
- SoloCollections 负责：本地目录查询、`collectionId`、已收集状态、收藏进度、搜索条件和 SC2 动作。
- 现有板甲、锁甲、皮甲、布甲筛选完整保留；只迁移筛选控件外观，不改变 SoloCollections 的筛选结果和语义。
- SC2/C++ 继续负责：账号收藏、权限、revision、持久化和最终应用。
- 页面刷新和翻页不得请求服务端重新发送展示数据；静态展示数据继续从 AddOn 本地目录读取。
- 不接入 ezCollections 的收藏数据库、服务端消息、商店、幻化或套装后端。
- 固定预览 Creature、`PREVIEWCREATURE:WEAPON` 握手、ezCollections 武器镜头、旧 M2 镜头和镜头工作台不得再驱动物品卡。

## 迭代 1：整理当前部分迁移基线（已完成）

- [x] 列出已经迁移的 ez 镜头表、卡片尺寸、固定模型池、TryOn 和镜头恢复代码。
- [x] 保留当前分支中已经稳定的装备翻页镜头修改。
- [x] 记录当前未提交文件和差异，避免迁移时覆盖已有成果。
- [x] 将当前混合生命周期与可复用的 ez 代码分开，停止继续追加临时镜头补丁。

**完成条件：** 明确哪些现有代码直接复用、哪些由完整 ez 生命周期替换，并保留可回退版本。

### 迭代 1 实施记录

- **直接复用：** `Data/EzCollectionsCamera.lua` 的 Classic 种族/性别/部位镜头表、19 组武器镜头、`14307` 预览 Creature 默认值；`Wardrobe.lua` 的 6×3 固定池、78×104 卡片、`SetUnit/TryOn`、同部位镜头缓存和 `RetainRecordCamera` 恢复。
- **由新生命周期替换：** `Wardrobe.lua` 内从 `applyItemModelRecord` 到 `ItemCardRenderer` 的混合装备/武器状态，以及分散的 `queueItemModelView`、`clearEzItemModelState` 和跨类型重建逻辑。后续不再向这些函数追加临时镜头补丁。
- **明确停用：** 物品卡运行时的 `CameraWorkbench`、旧 `ModelProvider` DISPLAY 武器桥、`M2Camera` 和 SoloCam 路线；套装页仍按原有边界保留自己的 `ModelProvider`。
- **未提交基线：** 保留 `EzCollectionsCamera.lua`、`Wardrobe.lua`、架构文档和 `test_wardrobe_camera_set_contract.py` 的已有修改；tracked 回退对象为 `bf0359f488d3ea708b9f580c4d8588b8d76bbd57`，初始方案 blob 为 `5abdd53b9457e423a1c2fd507fd2342519934f14`。
- **部署/实机：** `SC-EZITEMS-20260813-ITER1` 已部署 56 个文件，树 SHA-256 为 `317DB403F9AE41D084EFCA3572D87F8B55D9119FC4F184FAC3A7EB6FEC4955D2`；旧 AddOn 完整备份到客户端 `_codex_backups`。真实 3.3.5a 客户端已观察物品页首次显示与同一头部分类从第 1 页翻到第 2 页，18 张卡片保持部位构图，未观察到全身镜头复位或上一页残影。

## 迭代 2：为现有 SoloCollections 数据层增加 ez 页面适配器（已完成）

**新增：** `addon/SoloCollections/UI/EzWardrobe/DataProvider.lua`

- [x] 不改写现有 `Catalog`、`CollectionState` 和 `Bridge`，只在其上增加薄适配器。
- [x] 将 `Catalog.Query/QueryAll` 的外观记录转换为 ez 页面需要的物品记录。
- [x] 每条记录保留 `collectionId`、`itemId`、slot、武器类型、名称和收集状态。
- [x] 分页、搜索、护甲类型、装备位置、武器类型和收集状态仍调用 SoloCollections 目录逻辑。
- [x] 保留 `AUTO/PLATE/MAIL/LEATHER/CLOTH` 内部状态和板甲、锁甲、皮甲、布甲四个用户选项。
- [x] 首次打开或状态为 `AUTO` 时，继续按当前角色职业选择默认护甲类型。
- [x] 切换护甲类型后回到第 1 页、清除当前选择、重新查询目录并更新收藏进度。
- [x] 护甲类型只过滤护甲记录，不改变主手、副手武器分类结果。
- [x] 收藏进度继续读取 SoloCollections 结果。
- [x] 点击已收集物品时只调用 `SC.Bridge.ApplyAppearance(collectionId, slot)`。
- [x] 未收集物品允许本地预览，但不得发送越权动作。

**完成条件：** ez 页面只读取 DataProvider，不直接调用 `C_TransmogCollection` 或 ezCollections 后端。

### 迭代 2 实施记录

- 新增 `UI/EzWardrobe/DataProvider.lua`，由它唯一封装物品页的 `Catalog.Query/QueryAll/GetProgress`、收藏偏好和 `Bridge.ApplyAppearance`；未修改 `Catalog.lua`、`CollectionState.lua` 或 `Bridge.lua`。
- 适配记录同时保留稳定 `collectionId` 与展示 `itemId`，并保留 slot、武器类型、名称、收集状态及后续模型生命周期需要的展示字段；护甲/武器分别标记为 `player/main/off`。
- `AUTO` 保留为持久内部值，查询副本才解析为当前职业默认护甲；下拉框仍只有板甲、锁甲、皮甲、布甲四项。切换筛选统一重置页码和选择。
- 未收集记录在适配器内拒绝应用并返回 `NOT_OWNED`；已收集记录只把 `collectionId` 与 11 个生产 slot 对应的装备栏交给 SC2 Bridge。
- 静态边界检查通过：TOC 顺序正确，物品页不再直接调用外观 Catalog 查询/进度或 Bridge 应用，也不存在 `C_Transmog*` 依赖。既有 20 项 Wardrobe 合同中 17 项通过；3 项失败属于迭代前未提交基线中的旧套装预览/旧武器不可用文案合同，本迭代未触碰相应函数。
- `SC-EZITEMS-20260813-ITER2` 已部署 57 个文件，树 SHA-256 为 `47777DADB8648F2F03D22CCDEE02F1C3DEDC0DAC563D168C8229A86A781FCCDB`。真实客户端确认死亡骑士 `AUTO` 首次显示板甲；切换布甲后回到第 1 页、进度从 `0/270` 更新为 `1/344`；保持布甲状态切到主手仍得到 `1/198`、11 页的武器结果，证明护甲筛选未排除武器。

## 迭代 3：补齐 ezCollections 模型生命周期（已完成）

**新增：** `addon/SoloCollections/UI/EzWardrobe/Model.lua`

**调整：** `addon/SoloCollections/Data/EzCollectionsCamera.lua`

- [x] 迁移 `TransmogModelMixin:SetType(player/main/off)`。
- [x] 迁移 `WardrobeItemsModelMixin:Reload()`。
- [x] 复用已经导入的 Classic 镜头表和武器镜头表，不重复复制同一份参数。
- [x] 复用已经稳定的护甲翻页镜头恢复逻辑，并纳入新的类型状态机。
- [x] 补齐装备、主手、副手的缩放、动画和静态帧规则。
- [x] 装备使用玩家模型和 ezCollections Classic 的种族、性别、部位镜头。
- [x] 武器使用固定预览 Creature、主手动画 51、副手动画 63 和 ezCollections 武器镜头。
- [x] 武器镜头按 `inventoryType + itemSubclass` 选择，并保留单件特殊镜头入口。
- [x] `player/main/off` 每次跨类型切换时清理旧相机、动画、缩放、TryOn 和异步状态。
- [x] 武器返回装备时强制重建玩家模型，模型就绪后再应用装备镜头。

**完成条件：** 装备和武器可以反复切换，二者镜头不互相污染。

### 迭代 3 实施记录

- 新增命名空间隔离的 `EzWardrobe.Model`，移植 `SetType/RefreshType/Reload`，统一 `player/main/off` 的模型、缩放、动画、TryOn、镜头与清理顺序。
- 将 `SetUnit/SetCreature -> 模型连续就绪两帧 -> Undress/TryOn -> 镜头` 纳入 generation 约束的异步状态机；页面隐藏、切到套装页或新记录到达时可取消旧任务。
- `EzCollectionsCamera` 增加单件外观镜头注册入口，并继续复用同一份 Classic/武器镜头表、装备镜头保持逻辑和 `14307` 固定预览 Creature。
- 静态契约和 `git diff --check` 通过。历史 20 项契约脚本中，本轮前已有的 3 项套装/不可用文案偏差未扩大；旧护甲实现断言将在最终整理时改指向新模型文件。
- 部署 `SC-EZITEMS-20260813-ITER3B`：58 个文件，树 SHA256 `4885CE08B48A85C68B299B1603BAC0209796E58BF74D31631F9D698C937AE4B5`；上一客户端包备份于 `D:\Games\wow335\World of Warcraft11\Interface\AddOns\_codex_backups\SC-EZITEMS-20260813-ITER3B`。
- 真实客户端按副手 -> 头部装备 -> 装备第 2 页反复检查，副手固定 Creature、装备玩家模型均可见；武器返回装备会重建玩家模型，翻页后未观察到旧武器模型、缩放或镜头残留。

## 迭代 4：迁移 ezCollections 物品页显示（已完成）

**新增：**

- `addon/SoloCollections/UI/EzWardrobe/Items.lua`
- `addon/SoloCollections/UI/EzWardrobe/Items.xml`
- `addon/SoloCollections/UI/EzWardrobe/Assets.lua`

**调整：**

- `addon/SoloCollections/SoloCollections.toc`
- `addon/SoloCollections/UI/Wardrobe.lua`

- [x] 复制并命名空间隔离 ezCollections 的物品页模板、18 张模型卡和物品页控制逻辑。
- [x] 使用 ezCollections 的 6 列 × 3 行布局、78×104 卡片、间距、背景、边框、hover 和选中效果。
- [x] 通过现有 `SoloCollections_EzUI` 导入物品页实际使用的纹理和声音资源，并记录来源和源树 hash；资源保留在本地集成包，不写入公共源码包。
- [x] 迁移物品/套装页签、进度、搜索、装备位置、武器分类和筛选器的显示样式。
- [x] 把板甲、锁甲、皮甲、布甲筛选控件换成 ezCollections 风格，但继续写入现有 `SC.db.filters.armorType`。
- [x] “物品”页签显示新的 ez 物品页；“套装”页签继续打开现有 SoloCollections 套装内容。
- [x] 保留 SoloCollections 外层窗口、左上角入口和底部收藏分类导航。
- [x] 删除界面代码对 ezCollections 全局 Frame、商店、幻化和服务器 API 的依赖。

**完成条件：** 物品标签的可见结构和交互与 ezCollections 一致，套装页现有功能不受影响。

### 迭代 4 实施记录

- 新增 `EzWardrobe/Assets.lua`、`Items.xml` 和 `Items.lua`；虚拟模板统一使用 `SoloCollectionsEzWardrobe*` 前缀，18 张 `DressUpModel` 卡片由独立固定池创建，`Wardrobe.lua` 只保留 SoloCollections 数据/动作回调。
- 卡片池继续使用 ezCollections 6×3、78×104、16/24 间距和本地 Transmogrify/Collections 图集；背景、收集边框、hover、选中与偏好状态均复用本地素材适配层。
- 素材来源锁定 ezCollections 2.2（ZEUStiger），源树 SHA-256 `218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6`，媒体投影 SHA-256 `4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53`；纹理/声音仍只存在 `SoloCollections_EzUI` 本地集成包，未写入公共源码。
- 外层日志原有的 ez 风格页签、进度、搜索、装备位置与武器筛选继续复用；护甲下拉仍只写 `SC.db.filters.armorType`。新模块未引用 ezCollections 全局 Frame、`C_Transmog*`、商店或服务端消息 API。
- `SC-EZITEMS-20260813-ITER4` 已部署 61 个文件，树 SHA-256 为 `12E04098976C80BF7C64041EF9DCAF70CC882AD507278FC2F0C678C2CF85A357`，旧包完整备份于客户端 `_codex_backups`。真实客户端确认 XML 正常加载、18 卡片显示、物品/套装往返正常，外层窗口与底部导航未被替换。

## 迭代 5：接入收藏状态与交互

- [x] SC2 初始快照完成后刷新卡片收集状态和进度。
- [x] SC2 增量 revision 到达时只更新受影响的卡片，不重建整页模型。
- [x] 已收集、未收集、选中、hover 和 tooltip 映射到 SoloCollections 状态。
- [x] 搜索、筛选和翻页只重绑固定的 18 张卡片。
- [x] 页面隐藏或切到套装页时取消旧 generation，禁止上一页异步 TryOn 写回。
- [x] 所有服务端动作继续使用稳定 `collectionId`，模型显示使用 `itemId`。

**完成条件：** 显示来自 ez，状态和动作来自 SC2，两个 ID 不混用。

### 迭代 5 实施记录

- `CollectionState` 的变更回调现在携带 `DELTA` 的 `collectionId`、operation 和 revision；外观物品页只更新命中的可见卡片，收集/未收集排他筛选时才重绑同一批 18 张卡片。套装页仍沿用完整刷新以更新套装完成度。
- 卡片状态由 `Items.lua` 统一映射收集、未收集、选中、hover 与 tooltip；动作 ID 保持为稳定 `collectionId`，`DressUpModel` 仍只接收 `itemId`。页面隐藏、切套装和重新绑定都会推进 generation，旧异步任务不能写回。
- `SC-EZITEMS-20260813-ITER5` 已部署 61 个文件，树 SHA-256 为 `130CBC9E2EDA7E4441EB4EB356636675C71E6F93429106E8F05E50144465DC51`，旧包完整备份于客户端 `_codex_backups`。真实客户端确认 SC2 初始快照完成后显示 `1 / 344`，18 卡片布局与既有外层窗口正常；DELTA 路径以只读源码边界核对留证，未伪造服务端收藏状态。

## 迭代 6：固定武器预览 Creature 并停用旧路线

- [ ] 检查当前 `14307` 是否能够稳定承担全部武器预览。
- [ ] 若不可用，在 `mod-solo-collections` 中加入项目自有的 Creature 模板和 SQL。
- [x] 预览 Creature entry 只在启动时读取一次，不在翻页时通信。
- [x] 从物品页移除 `CameraWorkbench`、旧 `ModelProvider` 武器桥、M2 camera 和 SoloCam 镜头调用。
- [x] 旧代码保留在 Git 历史或参考分支，不作为运行时 fallback。
- [x] ez 武器显示不可用时明确显示不可用，不退回旧武器镜头。

**完成条件：** 物品页只有一条装备/武器模型路径，DLL 不参与物品卡显示。

### 迭代 6 实施记录

- `EzWardrobe.Model` 在模块加载时一次性缓存 `weaponPreviewCreatureEntry = 14307`；卡片与常驻 1×1 preloader 都只使用这个缓存值。翻页和刷新只复用 actor、重绑 `TryOn(itemId)` 与相机 tuple，不读取 SC2 配置或发送通信。
- `CameraWorkbench.lua` 已从活动树和 TOC 移除；旧物品 presenter、M2/SoloCam 调参器以 reference-only long comment 排除在 Lua 活动 chunk 之外。`ModelProvider` 仅保留给既有套装 DressUpModel，不再进入物品卡路径。不可用状态由 `EzWardrobe.Model:setUnavailable` 明确呈现，不存在旧镜头 fallback。
- `SC-EZITEMS-20260813-ITER6` 已部署 60 个文件，逐文件清单树 SHA-256 为 `4A72C14B17F31FC25DC2139B670267E014008EE0A52BD5B33C49AD3B4D955232`；上一 61 文件包完整备份于客户端 `_codex_backups/SC-EZITEMS-20260813-ITER6`。真实客户端确认 AddOn 加载、头部→主手→副手切换及 `14307` 主/副手模型异步装载正常；所有武器类别继续在迭代 7 矩阵验收。

> 2026-08-14 复开：用户实机确认武器显示仍未达到要求，因此撤回 `14307` 全武器预览稳定及武器客户端验收结论。上面的迭代 6 记录只保留为当次观察证据，不再代表当前验收状态。

## 迭代 7：性能整理与客户端验收

- [x] 固定复用 18 个 `DressUpModel`，翻页不创建新模型框架。
- [x] record 未变化时只更新收藏状态，不重复 `SetUnit/SetCreature/TryOn`。
- [x] 同一装备部位翻页复用同一装备镜头；切换部位才选择新镜头。
- [x] 同一武器类别复用 Creature；武器类别变化时只更新必要的类型、镜头和 TryOn。
- [x] 用 generation 丢弃过期模型任务，页面隐藏时停止任务。
- [x] 检查进入页面、装备翻页、切部位、装备到武器、武器翻页、武器回装备、关闭重开和 `/reload`。
- [x] 分别检查板甲、锁甲、皮甲、布甲筛选的结果、职业默认值、页码重置和进度统计。
- [ ] 分别检查至少一个主手、一个副手、盾牌、远程武器和副手物品。

**完成条件：** 页面连续操作无镜头复位、串模型、上一页残影或明显持续卡顿。

### 迭代 7 实施记录

- `EzWardrobe.Items` 固定创建并循环复用 18 张模型卡；未变化 record 返回 `UNCHANGED`，收藏增量只改状态层，不重复执行 `SetUnit/SetCreature/TryOn`。装备镜头按 slot、武器 Creature 与镜头按 category 复用；generation 在重绑、翻页、切页和隐藏时递增，过期异步任务不会写回。
- 真实客户端完成进入页面、装备翻页、头部→肩部、装备→主手/副手武器→装备、关闭重开和 `/reload`；检查主手单手斧 `1 / 198`、副手单手斧 `0 / 13`、盾牌 `2 / 362`、弓 `0 / 147`、副手物品 `1 / 267`。板甲、布甲、锁甲、皮甲分别得到 `0 / 281`、`0 / 257`、`0 / 248`、`1 / 253`，切换筛选与重开均重置到第 1 页并保持正确进度；未观察到 Lua 弹窗、镜头复位、串模型、上一页残影或明显持续卡顿。
- `SC-EZITEMS-20260813-ITER7` 最终部署保持 60 个文件，逐文件清单树 SHA-256 仍为 `4A72C14B17F31FC25DC2139B670267E014008EE0A52BD5B33C49AD3B4D955232`；源码与客户端逐文件对比无差异，部署前副本完整备份于客户端 `_codex_backups/SC-EZITEMS-20260813-ITER7`，客户端已停止。

## 迭代 8：按 Transmorpher 路径重做武器显示

> 本迭代取代迭代 3、6、7 中与固定预览 Creature 和 ezCollections 武器镜头有关的实现结论；旧记录只作为历史证据保留。

- [x] 静态审计 Transmorpher 3.0.0 的 AddOn、TryOn Hook、DLL 注入边界和本地源码，确认完整 DLL 会与 SoloCam 争用 `PlayerModel:SetCreature` Hook，不能并列加载。
- [x] 将 Transmorpher 的原生 `TryOn/Undress` 调用合并到唯一的 SoloCam v10 DLL，并使用 `widgetTable[0]` 解析当前卡片的真实模型对象。
- [x] 严格沿用 Transmorpher sentinel，预览请求直接携带引擎槽位 16、17、18；DLL 只接受这三个强制试穿槽位。
- [x] 由 SoloCam 在 WoW UI 线程定时发布 `previewTryOnV1` 能力，使首次加载和 `/reload` 都不依赖手工 `/run` 握手。
- [x] 精确投影 Transmorpher 3.0.0 的 Classic 种族、性别、槽位和武器子类预览配置，并记录源 commit 与源文件 SHA-256。
- [x] 将武器卡改为玩家 `DressUpModel`，按 `Reset → Undress → SetPosition → SetFacing → TryOn → SetSequence` 渲染，并在 `OnUpdateModel` 只恢复 Transmorpher 序列。
- [x] 删除 `14307`/固定 Creature、常驻 preloader、双持 resetter、`PREVIEWCREATURE:WEAPON` 客户端握手、ezCollections 武器镜头和旧注释 presenter。
- [x] 完成 Lua/TOC 静态检查、Transmorpher Classic 数据逐行一致性检查和 SoloCam x86 `/W4 /WX` 构建检查。
- [x] 备份并部署新的 AddOn 与单一 SoloCam v10 DLL；确认客户端目录中不存在第二个 Transmorpher Hook DLL。
- [ ] 在真实客户端检查单手、双手、主手、副手、盾牌、弓、弩、枪、魔杖、投掷、长柄、法杖、拳套、匕首和 `/reload` 恢复。

**完成条件：** 武器页只存在 Transmorpher 玩家模型显示路径；卡片显示真实武器模型而不是图标，且没有固定 Creature 或第二个 DLL Hook 竞争。

### 迭代 8 实施记录（源码、构建与部署阶段）

- Transmorpher Classic 配置逐行比对 6,162 行一致；源文件 SHA-256 为 `B550F596C7FE94D5B3844D9ECD2D5A0B44BAD2E6E2B2525C3A6A92FCD3D039B4`，源 commit 为 `8a8140fa54e424699da00d3a21359b43b79efddc`。
- 复核 `DressingRoom.lua` 与 `StealthMorpher/src/Utils.cpp` 后，sentinel 已严格改为直接携带引擎槽位 16、17、18；此前的 0、1、2 紧凑码中间实现已撤回。武器卡在 `TryOn` 后只设置 sequence，不再重复位置和朝向。
- 本次触及的 6 个 Lua 文件以 Lua 5.1 语法解析通过，`Items.xml` 可解析，TOC 顺序为预览数据 → 原生桥 → 模型生命周期，`git diff --check` 通过。
- SoloCam v10 以 MSVC x86、`/W4 /WX` 构建成功，DLL 大小 118,272 字节，SHA-256 为 `200F64EFABBB4634977397CE38B1DE7892D0DCA33E16774547ABF45710601453`；这只标记 `VALIDATED_LOCAL`，尚未标记真实客户端武器显示通过。
- 客户端停止后部署 62 个 AddOn 文件，树 SHA-256 为 `2B3C462798F569EE9B7B1201F153E6C2B8F7FB8E49036895B75C6B9ABB9AB8B2`；DLL 与构建产物 hash 一致。紧凑码中间版完整备份在 `D:\SoloCollectionsBackups\SC-TRANSMORPHER-EXACT-20260814-095650`，合并前版本仍保存在 `D:\SoloCollectionsBackups\SC-TRANSMORPHER-MERGE-20260814-094651`；客户端根目录只存在一个 `SoloCam.dll`，未发现第二个 Transmorpher Hook DLL。
- `Wow-CQM-SoloCam.exe` 已启动到客户端登录界面；运行进程实际加载一份 `SoloCam.dll`，模块 SHA-256 为 `200F64EFABBB4634977397CE38B1DE7892D0DCA33E16774547ABF45710601453`，未加载 Transmorpher/StealthMorph 第二 Hook 模块。尚未登录角色，因此真实武器类别矩阵继续保持未完成。

## 迭代 9：盾牌材质翻页生命周期修复

- [x] 记录用户实机结果：普通武器模型显示正常；盾牌会变成纯绿色或蓝白方块，向后翻页后可能恢复，返回已翻过页面时再次丢失材质。
- [x] 用目录记录定位盾牌第 4 页 18 个 item/display/BLP 映射，并用 StormLib 从当前客户端 `common.MPQ` 只读提取代表纹理。
- [x] 确认当前客户端 `Buckler_Oval_A_01Green.blp` 与正常样本 SHA-256 一致，排除资源缺失、纹理损坏或补丁错误覆盖。
- [x] 投影 Transmorpher `QueryItem.lua`：隐藏 tooltip 发起未缓存物品查询，并在 `GetItemInfo` 就绪后才进入 TryOn 生命周期。
- [x] 保持 Transmorpher 的 `DressUpModel`、原生 Undress/TryOn、镜头和序列路径；武器卡恢复其默认 AutoDress/DoBlend/KeepModelOnHide 状态。
- [x] 将可见武器卡的 TryOn 调度为每个 UI 帧最多一个，并用 lifecycle generation、record key 和可见性丢弃翻页后的过期任务。
- [x] 禁止页面级 `GET_ITEM_INFO_RECEIVED` 再把 18 张已缓存武器卡集中重放到同一帧；tooltip 更新保持不变。
- [x] 完成 Lua 5.1 语法、TOC 加载顺序和 `git diff --check` 静态检查。
- [x] 客户端停止后备份并部署 63 文件 AddOn；单一 SoloCam v10 DLL 保持不变。
- [ ] 在真实客户端连续检查盾牌前翻、后翻、返回已访问页、关闭重开和 `/reload` 后的材质恢复。

### 迭代 9 实施记录（源码、资源核对与部署阶段）

- 新增 `Core/TransmorpherItemQuery.lua`，保持 Transmorpher 的 0.1 秒轮询和 180 秒上限；`EzWardrobe.Model` 的武器路径只在物品数据就绪后进入 generation-safe 队列，队列每帧最多提交一个有效 TryOn。
- 当前客户端 `common.MPQ` 中 `Item\\ObjectComponents\\Shield\\Buckler_Oval_A_01Green.blp` 的 SHA-256 为 `9D43F5A0B272030836AAEA9FF621F48CBA1A3B638B753C8F2A5E56E4EBCE3EBD`，与正常样本一致；可见绿色/棋盘不是素材文件本身的内容。
- 修正版部署 63 个 AddOn 文件，源码、暂存目录和客户端目录树 SHA-256 均为 `DF6DDC533C8F9266994107ED5EB4087D1F38B9FB12AB58252AE73B9ABCC7161E`。部署前 AddOn 与当前 DLL 备份于 `D:\SoloCollectionsBackups\SC-SHIELD-TEXTURE-20260814-102021`；DLL 仍为 `200F64EFABBB4634977397CE38B1DE7892D0DCA33E16774547ABF45710601453`。
- 本迭代当前为 `VALIDATED_LOCAL + DEPLOYED`；盾牌翻页和 `/reload` 的真实客户端视觉验收仍未标记完成。

> 2026-08-14 用户复测：盾牌仍为纯绿色或蓝白方块，因此迭代 9 的调度修正不构成问题修复；已部署记录只保留为被否定的排查证据，视觉验收继续未完成。

## 迭代 10：校正 Transmorpher 装备栏与底层模型槽映射

- [x] 记录迭代 9 实机复测失败，不再把盾牌问题归因于同帧 TryOn 或物品缓存。
- [x] 反汇编当前 build 12340 客户端的 `DressUpModel:TryOn`（`0x00598830`）、TryOn 入口（`0x00597FC0`）和 InventoryType 分发器（`0x005980D0`）。
- [x] 确认原生 Lua TryOn 传入 `-1` 自动槽；盾牌 `INVTYPE_SHIELD=14` 被分发到内部模型槽 16。
- [x] 确认 Transmorpher 3.0.0 将 Lua 装备栏 16/17/18 原样传给底层，副手盾牌因此错误进入不存在的模型槽 17。
- [x] 保留 Transmorpher sentinel 打包格式与构图逻辑，在 SoloCam v11 中转换为主手模型槽 15、副手模型槽 16、远程原生自动判槽。
- [x] 更新 AddOn 能力版本与架构文档，并完成 MSVC x86 `/W4 /WX` 构建。
- [x] 备份并部署 SoloCam v11 DLL 与匹配 AddOn。
- [x] 在真实客户端复测 SoloCam v11 武器路径；用户确认“武器部分可以了”。

**完成条件：** 盾牌使用正确的内部模型槽绑定替换纹理，不再出现纯绿色或蓝白棋盘；主手、副手和远程没有槽位回归。

### 迭代 10 实施记录（机器码核对、构建与部署阶段）

- build 12340 的原生 Lua TryOn 在 `0x00598870` 依次传入槽位 `-1`、零和 itemId 后调用 `0x00597FC0`；`0x005980D0` 的 InventoryType 分发器在 `0x00598563..0x00598582` 将盾牌、远程、Held in Off-hand 和副手物品解析到内部模型槽 `0x10`（16）。
- SoloCam v11 保留 Transmorpher 的 `0x18000000 + equipmentSlot * 0x00100000 + itemId` 载体；解码后把主手 16 映射到模型槽 15、副手 17 映射到模型槽 16、远程 18 改用 `-1` 原生自动判槽。
- MSVC x86、`/W4 /WX` 构建成功；DLL 大小 118,784 字节，SHA-256 为 `86715FD9E476A9361883B751F1796EE20D2B524D63340404474256EB20D5ED20`，`LoadLibraryExW` 探针接受该 DLL。
- 客户端停止后部署 63 个 AddOn 文件，源码/客户端树 SHA-256 为 `4AED21B731D655EC1386D4E067CD39B1A40EB3EF88FF541EEC7B90643C150EF7`；部署前 AddOn 与 v10 DLL 完整备份于 `D:\SoloCollectionsBackups\SC-SHIELD-SLOT-MAP-20260814-104131`。
- `Wow-CQM-SoloCam.exe` 已重新启动到登录界面；运行中的 `Wow-SoloCam-PoC.exe` 只加载客户端根目录这一份 `SoloCam.dll`，磁盘 SHA-256 为 `86715FD9E476A9361883B751F1796EE20D2B524D63340404474256EB20D5ED20`。
- 用户在该版本实机复测后确认“武器部分可以了”；SoloCam v11 武器路径由 `VALIDATED_LOCAL + DEPLOYED` 提升为 `REAL_CLIENT_ACCEPTED`。迭代 9 的失败记录继续保留，不回写成成功证据。

## 迭代 11：按 Transmorpher 路径重做护甲显示（已完成）

> 本迭代取代迭代 1、3、7 中与 ezCollections Classic 护甲镜头、scale 10、
> 静态逐帧冻结和护甲镜头保持有关的实现结论；旧记录只作为历史证据保留。

- [x] 静态审计 Transmorpher 3.0.0 的 `PreviewList.lua`、`DressingRoom.lua`、`QueryItem.lua`、`PreviewSetupAPI.lua` 和 Classic 预览数据。
- [x] 确认现有 `TransmorpherPreviewSetup.lua` 已包含 20 个种族/性别页及 HEAD、SHOULDER、BACK、CHEST、WRIST、HANDS、WAIST、LEGS、FEET 九个护甲部位。
- [x] 将 SoloCollections 稳定护甲 slot 映射到 Transmorpher `Armor` setup。
- [x] 用 `Reset → Undress → SetPosition → SetFacing → TryOn → SetSequence` 完整替换当前护甲渲染顺序。
- [x] 护甲卡恢复 Transmorpher 默认 AutoDress、DoBlend、KeepModelOnHide、灯光和模型 scale。
- [x] 移除物品卡对 ezCollections 护甲镜头、scale 10、`SetSequenceTime` 逐帧冻结和 `OnUpdateModel` 镜头重放的活动依赖。
- [x] 护甲与武器共用物品查询和 generation-safe 单帧渲染队列；护甲使用原生 TryOn，武器继续使用 SoloCam v11 强制槽位桥。
- [x] 保留 18 张卡片池、78×104 外层卡片、筛选、分页、收藏状态、SC2 权限和应用动作。
- [x] 更新架构、来源声明与静态合同，并完成 Lua 5.1、TOC 和差异格式检查。
- [x] 备份并部署 AddOn，使用项目登录脚本启动客户端并提交登录。
- [x] 用户在真实客户端完成九个护甲部位、翻页、武器往返、关闭重开和
  `/reload` 的视觉验收。

**完成条件：** 护甲卡只存在 Transmorpher 玩家模型路径；九个护甲部位按
Transmorpher Classic 构图显示，翻页和武器往返不再进入 ezCollections 护甲镜头
或逐帧冻结路径。源码与部署完成只标记 `VALIDATED_LOCAL + DEPLOYED`，用户确认前
不得标记 `REAL_CLIENT_ACCEPTED`。

### 迭代 11 实施记录（源码、部署与实机验收）

- `EzWardrobe.Model` 将 `HEAD/SHOULDER/BACK/CHEST/WRIST/HANDS/WAIST/LEGS/FEET`
  映射到 Transmorpher `Armor` setup；护甲改为原生
  `Reset → Undress → SetPosition → SetFacing → TryOn → SetSequence`，武器保持
  SoloCam v11 强制槽位 TryOn。
- 护甲与武器共用 `TransmorpherItemQuery` 和 generation-safe 单帧队列；
  `OnUpdateModel` 只恢复 sequence。活动树已删除 `EzCollectionsCamera.lua` 及其
  TOC 入口，不再存在 scale 10、`SetSequenceTime` 或逐帧护甲镜头重放。
- Lua 5.1 语法、`Items.xml`、TOC 加载顺序、三项护甲静态合同和
  `git diff --check` 均通过；这只标记 `VALIDATED_LOCAL`。
- 客户端停止后部署 62 个 AddOn 文件，源码、暂存目录和客户端目录树 SHA-256
  均为 `ABD9FD7951468D27DB5F910650C1ADEF6D59076DDF853F7F33587FDA1E04010B`；部署前
  63 文件 AddOn 与当前 DLL 完整备份于
  `D:\SoloCollectionsBackups\SC-TRANSMORPHER-ARMOR-20260814-111747`。
- SoloCam v11 DLL 未修改，SHA-256 仍为
  `86715FD9E476A9361883B751F1796EE20D2B524D63340404474256EB20D5ED20`。项目登录
  脚本已启动 `Wow-SoloCam-PoC.exe` 并提交登录，运行进程只加载一份该 DLL。
- 2026-08-14 用户实机确认“护甲卡片和武器卡片都验收通过”。迭代 11 由
  `VALIDATED_LOCAL + DEPLOYED` 提升为 `REAL_CLIENT_ACCEPTED`；武器路径继续沿用
  迭代 10 已通过的 SoloCam v11 实现，护甲路径采用本迭代的 Transmorpher 原生
  TryOn 实现。

## 实施顺序

```text
数据适配层
→ ez 模型生命周期
→ ez 物品页显示
→ SC2 状态与动作接入
→ 固定武器 Creature
→ 停用旧路线
→ 性能整理和实机验收
→ Transmorpher 单 DLL 武器路径重做
→ 盾牌材质翻页生命周期修复
→ 校正 Transmorpher 装备栏与底层模型槽映射
→ Transmorpher 护甲显示路径重做
```

每完成一个迭代就部署一次可运行版本并验收当前范围；当前迭代稳定后再进入下一项。
