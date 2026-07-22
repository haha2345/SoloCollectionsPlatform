# 衣橱、镜头与套装体验：修复前基线

日期：2026-07-22
范围：AddOn 体验层与生成 presentation；本报告不修改 module、Core、数据库、客户端安装或 WDB。

## 可复核证据

- 总清单：[evidence-manifest.json](../../../evidence/round3-wardrobe-camera-set/evidence-manifest.json)。
- 固定客户端/DBC/既有武器输入包：[fixed-inputs/evidence-manifest.json](../../../evidence/round3-wardrobe-camera-set/fixed-inputs/evidence-manifest.json)。
- 当前客户端截图位于 client-baseline/；自动红合同测试基线位于 automated-baseline/。清单只保留这些文件的相对路径、大小和 SHA-256，不含凭据、绝对源路径、客户端资产正文或数据库转储。
- 生成基线记录 AddOn/module/Core 的 commit、分支、tracked dirty 和未跟踪文件。开始时 AddOn 为 4ca746b9c8c9d045064351d059a244513f5a4a5a，module 为 ac5625801b49dae9d62b5ffd2fc70349ef20c032，Core 为 4cc67a316d2bec9faf27c3392634282e70cacbe0；所有用户既有改动均保留。

## 固定目录与部署合同

| 字段 | 基线值 |
| --- | --- |
| metadataVersion | 2026.07.22.4 |
| assetPackVersion | wotlk-3.3.5a-local-1 |
| appearance presentation hash | a0e6886fbe1fe11a515c92157f73590a9c0cebc548c184f1941e56ba3bf29815 |
| camera profile hash | c23c1248774272190326c28c0826d9f6e6e4ad20cff05945753defad7317f306 |
| set mapping hash | 2110892144adcdf60834c30785569ef38b5af7980cbdb62d684846cf44cc87cf |
| set presentation hash | d976a654145dab3ff06d26c6c2657fc715d5bd8482ce3e7d1953b4f1fe0a9bf1 |

清单还固定了实际部署 AddOn 树、SoloCam DLL、MPQ/locale patch 与 worldserver 的部署根相对路径、文件长度和 SHA-256。

当前 appearance 目录统计为：

| 范围 | BODY | STANDALONE | UNAVAILABLE |
| --- | ---: | ---: | ---: |
| 全目录 | 12,233 | 21 | 5,936 |
| public | 10,141 | 20 | 3,670 |

21 条 verified standalone presentation 的 source item、synthetic display、M2/SKIN/BLP 哈希、camera key 与 pose 已逐条写入证据清单。

## 已复现的问题

| 问题 | 固定证据 | 当前根因 |
| --- | --- | --- |
| 基础媒体缺失 | stage0-missing-wardrobe-slot-icons.jpg、stage0-missing-launcher-icon.jpg | 干净 bundle 没有 Media/Retail，但 Templates.lua 的 launcher、mount portrait、slot atlas 和 highlight 仍引用该目录。 |
| 套装滚动反向 | stage0-set-scroll-reversed.jpg | slider 写入/读取均使用 maxOffset - scSetOffset。 |
| 套装保留玩家装备 | stage0-set-preview-player-gear-residual.jpg | previewSet() 在 SetUnit("player") 后直接 TryOn，没有 generation、稳定 render tick 或 Undress() 阶段。 |
| 相机工作台遮挡 | stage0-camera-panel-overlays-cards.jpg | 351px DIALOG panel 锚定 page 右上方，覆盖物品网格；调节只按 weapon family 保存，无法单件优先覆盖。 |
| 全量武器未完成 shadow | 证据清单的 appearanceStatistics 和 verifiedStandaloneWeapons | validator 硬编码 21 个 manifest 条目及 40000..40020 synthetic range；其余主副手被明确投影为 UNAVAILABLE。 |

已有同 commit 的 clean bundle 基线 round2-20260722T052746Z-4ca746b-ac56258-4cc67a3 共有 36 个 AddOn 文件且没有 Media/Retail/ 条目；它同时证明 production Lua 仍引用四个 Retail 相对路径。对当前 clean Core build 再次组包会 fail closed：其 worldserver.exe SHA-256 与 build metadata 不一致。该失败留作阶段 9 的干净重建验收项，不通过伪造或替换构建输入绕过。

## 红测试

执行：

~~~powershell
$env:TEMP = 'F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\temp\round3-contract-tests'
$env:TMP = $env:TEMP
python -m unittest discover -s tools\collections\tests -p test_wardrobe_camera_set_contract.py
~~~

结果：10 项中 9 项如预期失败。合同覆盖基础媒体/Bundle、直接 scroll mapping、selected variant + Undress generation、registry 型 standalone、appearance/model/family/auto 镜头优先级，以及工作台不应为 DIALOG 浮层。唯一已通过的输入统一性合同确认现有 wheel/page helpers 已委派给 setSetOffset()；slider callback 仍绕开该函数，故整体交互合同保持红色。

## 回滚

修复开始前创建仅本地可见的 baseline tag，指向 4ca746b；不 push。后续阶段只在对应自动合同、生成检查和真实客户端验收都通过后更新本报告关联的实施计划勾选。
