# GPL-3.0-or-later 许可证与发布边界

> 这不是法律意见。涉及游戏客户端、正式服素材或第三方补丁代码时，应由项目
> 维护者根据所在地法律和实际来源自行确认。

## 已采用：GPL-3.0-or-later

SoloCollections 自有代码已经采用 **`GPL-3.0-or-later`**，根目录
`LICENSE` 包含完整 GPLv3 许可证文本。选择该许可证的原因：

1. ALE/mod-ale 当前采用 GPLv3，服务端脚本与其生态方向一致；
2. AzerothCore 的大量历史代码头为 GPLv2-or-later，GPLv3 是“or later”允许的
   选择；
3. 强 copyleft 适合“让全球网友共同完善”的目标：分发修改版时需要提供对应
   源码、保留许可和说明修改；
4. GPLv3 包含明确的专利授权和安装信息要求，比 MIT 更能防止改进被闭源拿走。

不推荐 MIT 作为整个项目的默认许可证，因为它允许其他人把改进闭源再分发；
也暂不推荐 AGPL，因为本项目主要是本地 AddOn/DLL/服务端脚本，不是以网络服务
条款为核心，而且会增加与现有 WoW 模拟器代码的许可判断复杂度。

GNU 官方说明：GPLv2-only 与 GPLv3 不兼容，但 GPLv2-or-later 可以选择 GPLv3。
因此任何实际复制进本仓库的第三方代码仍必须逐文件确认，不能只看项目名字。

## 仍需完成的第三方来源审计

根目录许可证只覆盖项目维护者和贡献者有权许可的自有代码，不会把第三方代码
自动变成 GPL。`poc_patch.py` 明确提到参考过 WotLK-Extensions 补丁器，因此公开
发布前仍应完成：

1. 对 SoloCam、补丁偏移和加载器代码做来源对照；
2. 确认所有复制或改写片段的原许可证与署名要求；
3. 更新 `THIRD_PARTY_NOTICES.md`；
4. 为新建或大幅修改的源码逐步补充 SPDX 文件头；
5. 如果发现不兼容或无法确认来源的片段，重写或移除，而不是擅自换许可证。

## 代码许可证不覆盖的内容

以下内容不自动成为 GPL：

- Blizzard 客户端 EXE、MPQ、DBC、M2、SKIN、BLP 和正式服素材；
- 网盘中的完整素材包和客户端文件；
- StormLib、capstone、pefile 等第三方依赖；
- 商标、游戏名称和截图中的第三方美术。

这些内容必须分别遵守原权利人的条款。GitHub 源码通过 `.gitignore` 排除客户端
提取素材、MPQ、EXE 和本地 `release` 成品目录。

## 建议逐步补充的文件头

```text
SPDX-FileCopyrightText: <year> SoloCollections contributors
SPDX-License-Identifier: GPL-3.0-or-later
```

不要给第三方文件擅自更换 SPDX 标识。

## 参考资料

- [GNU GPL 常见问题：许可证兼容性](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Choose a License：GPL-3.0](https://choosealicense.com/licenses/gpl-3.0/)
- [AzerothCore mod-ale](https://github.com/azerothcore/mod-ale)
- [AzerothCore 主仓库许可证](https://github.com/azerothcore/azerothcore-wotlk/blob/master/LICENSE)
