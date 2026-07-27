# SoloCollections source status / 源码状态

Snapshot date / 快照日期：2026-07-27

## 中文

### 当前定位

- 当前源码线使用 `mod-solo-collections` 的 C++/SC2 后端作为唯一生产权威。
- AddOn 负责 UI、客户端缓存和协议收发，不负责决定收藏所有权。
- `server/ale/solo_collections.lua` 是旧 SC1 兼容/迁移参考；生产模式为
  `SoloCollections.Backend = Cpp` 时它不会成为第二个写入者。
- `v0.2.0` 是已发布的 C++/SC2 成套源码版本；它不声称提供稳定的游戏
  二进制或客户端提取资源包。

### 当前生成目录

| 类别 | canonical 条数 |
| --- | ---: |
| 坐骑 | 281 |
| 非战斗小宠物 | 201 |
| 已审核玩具 | 9 |
| 外观 | 18,190 |
| 套装 | 465 |
| 合计 | 19,146 |

当前 metadata 为 `2026.07.23.2`，asset pack token 为
`round-two-stage8-weapon-presentation-v2`。公开武器候选为 3,690 条：
3,541 `READY`、149 `UNAVAILABLE`。资源缺失和不匹配保持明确不可用，不回退为
未授权的角色/NPC/任意模型。

### 已有本地证据的范围

- SC2 账号状态、快照和 revision 流程；
- 20 个 race/sex 页面、9 个装备部位，共 180 个角色镜头 profile；
- 套装滚动、预览清理和进度展示；
- 3,690 条武器展示终态扫描和代表 family 抽样；
- 参考客户端分辨率/UI Scale 布局检查；
- 无 SoloCam、错误 asset token 和冷/热缓存的失败关闭行为。

这些结论只说明当时参考客户端与对应源码/资源组合通过。新的客户端修改、HD
模型、不同 EXE、不同资源包或目录变更都需要重新验收。

### 已知限制与欢迎贡献

- 物品页镜头并未对所有种族、性别、HD/自定义模型达到一致构图；
- 极端比例、特效 bounds 异常或共享模型不同纹理的武器仍可能需要 profile；
- SoloCam 只支持一个精确的 x86 build-12340 EXE hash；
- 英文 UI 和更多 locale 仍可继续完善；
- `v0.2.0` 只发布可审核源码、清单与说明，不重新分发旧 `v0.1.0` 中的
  MPQ、DLL 或客户端补丁。

镜头工作请从 [CAMERA_CONTRIBUTIONS.md](CAMERA_CONTRIBUTIONS.md) 开始。

## English

### Current position

- `mod-solo-collections` in C++/SC2 mode is the sole production authority.
- The AddOn owns UI, client cache, and protocol transport, not collection
  authorization.
- `server/ale/solo_collections.lua` remains a legacy SC1 migration/reference
  path and must not become a second writer when the backend is `Cpp`.
- `v0.2.0` is the published matched C++/SC2 source release. It is not a claim
  that stable game binaries or extracted client-resource packages are
  distributed.

The generated catalog contains 19,146 canonical records: 281 mounts, 201
companions, 9 reviewed toys, 18,190 appearances, and 465 sets. Metadata is
`2026.07.23.2`; the asset token is
`round-two-stage8-weapon-presentation-v2`. The public weapon baseline is 3,541
`READY` plus 149 `UNAVAILABLE`.

The maintainer's matched reference environment recorded SC2 state/revision
behavior, 180 race/sex/slot body profiles, set preview behavior, a terminal
scan of 3,690 weapon presentations, representative layout checks, and
fail-closed behavior for missing SoloCam, bad asset tokens, and cache changes.
Those results do not automatically transfer to a modified executable, HD
model, different resource pack, or changed catalog.

Known contribution areas are body and weapon framing across more models,
extreme weapon bounds, English/locale coverage, and a future matched source
update. `v0.2.0` intentionally does not redistribute the MPQs, DLL, or client
patches from `v0.1.0`. Start camera work with
[CAMERA_CONTRIBUTIONS.md](CAMERA_CONTRIBUTIONS.md).
