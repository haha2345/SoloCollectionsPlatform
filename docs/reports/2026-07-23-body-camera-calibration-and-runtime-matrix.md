# 阶段 5：角色相机差量校准与运行矩阵验收

日期：2026-07-23

状态：完成。

本记录承接 [2026-07-22 角色相机 profile 基线](2026-07-22-character-camera-profile-generation-and-runtime-matrix.md)。本轮没有重写 180 条 canonical profile 的来源模型或 sentinel 分配；只为经过审核的一条 body-camera 差量建立了可导出、可审核、可回放的闭环，并重新运行了基础矩阵和三轮廓矩阵。

## 实现边界

- `SoloCam` 的 body-camera 私有协议使用版本 `1` 与 `0x71..0x76` 命令族。完整 profile SHA-256 以 13 个 20-bit 分片传输；五个 delta 载荷和激活命令都齐全且 hash、范围有效时才提交。未知命令、版本、hash、部分事务和非法数值均丢弃，原生 camera 1 fallback 不受影响。
- pending/active body override 是每个模型实例的状态；模型隐藏、池复用、renderer 切换、profile 改变和异步重建都会清理或按当前 generation 重放，不使用跨模型可变 pose。
- AddOn 的 BODY 检查器显示 asset profile、sex、slot、sentinel、profile hash 和五个 body 字段，不复用武器的 pitch/roll/target 控件。运行时能力只在当前进程内有效，缺少匹配 `SoloCam` 时检查器是只读，普通预览继续走 camera 1。
- `body_camera_tuning_import.py` 只产生候选；`body_camera_tuning_review.py` 对 base/proposed、幅度和受影响 profile 做审核；批准后由 `character_camera_profiles.py` 同时重建 Lua/C++ 投影和 hash。

## 已批准的差量闭环

来自真实客户端的 `human:female:HEAD` 导出经过候选、审核和明确批准后合并。它相对于旧 hash `5f7ec4dde75364cbd1e9886aed139a9855c4facc11766b44be40223e7c0013b1` 的五项差量为：

| 字段 | 已批准值 |
|---|---:|
| `verticalOffsetDelta` | `0.0500` |
| `horizontalOffsetDelta` | `0.0600` |
| `distanceScaleMultiplier` | `1.0100` |
| `minimumDistanceDelta` | `0.0100` |
| `yawOffsetDelta` | `0.0084` |

重建后的 canonical hash 为：

```text
792f1654ce058b3241eb9bbf9d3cc23ccd106b08071ef77a97868fa9f3bda5a4
```

Lua、C++ 生成投影、AddOn manifest 和运行时 SavedVariables 均使用该 hash。没有批准差量的其余 human/female 八个槽位保持其既有值。

导出、候选、审核和 preview-merge 证据位于：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage5-camera\stage5-camera-20260723-025203-061
```

批准后的 AddOn/DLL 测试部署记录位于：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage5-camera\stage5-camera-20260723-031559-185
```

该部署的 AddOn tree SHA-256 为 `794e93cc9743340a4c46790043ce741dbb25162e0948c75b19d02ddf04641d04`，x86 `SoloCam.dll` SHA-256 为 `5e601ab663e17fe57b0c26b035f728f33fea02d363ae03005a620f5ced14d093`。

## 真实客户端验收

### 基础 180 profile 回归

`body-camera-matrix-20260723-031654-044` 运行加载 20 个 race/sex 页面与全部九个槽位，得到 180 条记录、20 页、`ready=true`，并在 `/reload` 后持久化。更新后的 `catalog/review/cameras/runtime-matrix.csv` 记录新的 canonical hash、逐行 sentinel、期望/实际模型路径和人工视觉状态；唯一改动的 `human:female:HEAD` 以 `approved_delta` 重新检查。

### small / normal / large 三轮廓矩阵

临时审计 AddOn 增加三套显式代表装备：cloth/light（SMALL）、leather/chain（NORMAL）和 plate（LARGE）。每套都在所有 20 个 race/sex 页面上重放九槽位 sentinel；因此验收总数是 `20 × 3 × 9 = 540`。

接受的实机 run：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage5-camera\body-camera-silhouettes-20260723-034000
```

- 客户端界面显示 `540/540 READY - reload to persist`，reload 后显示 `540 rows / 60 pages`。
- 保存的审计结果为 `completed=true`、`ready=true`、`reloadObserved=true`，每种轮廓均为 180 条记录。
- 61 张截图（60 个矩阵页加一张 reload 页）与 SHA-256 manifest 位于该 run 的 `screenshots/` 和 `run-summary.json`；来源客户端截图仅复制到 F 盘证据包，未提交到 Git。
- `tools/catalog/check_camera_silhouette_audit.py` 校验 canonical hash、540 个唯一 `(profile, silhouette)`、全部模型路径和 sentinel、60 页 ready 状态、三组各 180 条以及 reload 截图。该 run 的 `verification.json` 为通过结果。
- 临时审计 AddOn 和其 SavedVariables 已从测试客户端移回该证据包；`cleanup.json` 证明原本不存在的客户端状态已恢复为不存在。

### 无 DLL 回退

使用原始 `Wow.exe`（未使用 `Wow-CQM-SoloCam.exe` 注入器）登录并打开衣橱。SysWOW64 模块探针确认没有加载 `SoloCam.dll` 或 `ClientQuestMarkers.dll`；衣橱仍稳定显示 body 卡片，未出现崩溃、无限缩放或黑模。截图及模块探针记录位于：

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\runtime-audit\stage5-camera\stock-client-fallback-20260723-033604
```

## 验证

以下检查在 AddOn worktree 通过：

```powershell
python -m unittest discover -s tools\collections\tests -p 'test_*.py' -q
python tools\catalog\character_camera_profiles.py --repo-root . check
python tools\catalog\check_camera_silhouette_audit.py `
  --saved-variables <run>\SoloCollectionsCameraAudit.lua `
  --canonical catalog\source\camera_profiles.json `
  --screenshot-directory <run>\screenshots
& .\client-extension\SoloCam\scripts\build.ps1
```

`BodyCameraBridgeTests` 覆盖协议区间、未知 version/command、分片缺失或 hash 不符、半套事务、每模型隔离、清理和 180 profile identity；生成器和 AddOn 合同测试覆盖五字段、只读能力、导出身份、审核合并以及非批准 human/female 槽位不漂移。

## 非范围项

本阶段没有把任意 player-local tuning 直接写入 canonical、没有部署 MPQ/DBC/WDB/数据库、没有扩大 production weapon 目录，也没有向远程仓库推送任何内容。
