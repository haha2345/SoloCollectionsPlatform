# 参与 SoloCollections 开发 / Contributing

## 中文流程

### 1. 开始之前

1. 阅读根目录 README 和与你修改部分对应的 `docs/architecture` 文档。
2. 在 Issue 中说明问题、预期结果和准备修改的组件。
3. Fork 仓库，从最新 `main` 创建分支：

```powershell
git switch main
git pull --ff-only
git switch -c fix/short-description
```

推荐分支前缀：`fix/`、`feature/`、`docs/`、`test/`、`build/`。

### 2. 源码边界

- AddOn：`addon/SoloCollections`
- ALE：`server/ale`
- SoloCam：`client-extension/SoloCam`
- MPQ 工具：`tools/mpq` 与 SoloCam `scripts`
- 测试：`tools/collections/tests`、`client-extension/SoloCam/tests`
- 文档：`docs`

仓库是唯一源码源头。不要在游戏目录修改后把整个目录覆盖回仓库。

### 3. 禁止提交

- `Wow.exe`、修补后的 EXE 或其他游戏二进制；
- MPQ、DBC、M2、SKIN、客户端提取 BLP 和完整素材包；
- `SoloCam.dll`、OBJ、PDB、测试 EXE 和编译目录；
- 数据库、账号数据、真实服务器地址、密钥、令牌和密码；
- 未说明来源或无权再分发的代码与图片。

项目自制占位素材可以提交，但必须在 `Media/assets.json` 记录作者、来源、格式和
SHA-256。

### 4. 测试

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s tools\collections\tests -p 'test_*.py' -v
python -m unittest discover -s client-extension\SoloCam\tests -p 'test_*.py' -v
```

修改 SoloCam C++ 时还要运行：

```powershell
& .\client-extension\SoloCam\scripts\build.ps1
```

修改 MPQ 构建链时，必须在纯净客户端完成“不部署构建、回读哈希、部署后回读”
三步验证，并附 `weapon-model-verification.csv` 摘要，但不要提交生成的 MPQ。

### 5. 提交信息

使用简短、可检索的信息，例如：

```text
feat(addon): add appearance source filter
fix(solocam): reject unsupported display request
docs(mpq): document zhTW build path
test(bridge): cover malformed summon payload
```

每个提交应能独立解释，避免把格式化、素材替换和功能修改混在一起。

### 6. Pull Request 必填内容

- 修改目的和用户可见结果；
- 涉及的组件；
- WoW build、`Wow.exe` SHA-256、语言；
- AzerothCore/ALE 版本；
- 自动测试结果；
- 游戏内手工验证步骤；
- 修改前后截图，放在 PR，不要包含个人信息；
- 是否改变协议、DBC 保留 ID、MPQ 路径或 SavedVariables；
- 素材和第三方代码的来源/许可证。

维护者可能要求拆分 PR、补测试或移除无法确认来源的文件。

## English summary

Fork the repository, branch from current `main`, make one focused change, add
or update tests, run both Python suites, and run the x86 native build for C++
changes. A pull request must state the client build/hash/locale, server and ALE
versions, automated and in-game validation, screenshots, protocol/DBC changes,
and provenance for every third-party asset or code fragment.

Never commit game executables, MPQs, extracted client media, compiled output,
databases, secrets, or private media packs. Installed client/server directories
are deployment targets, not alternate source trees.

## License and contributor statement

Project-authored code is licensed under GPL-3.0-or-later. By opening a PR,
contributors certify that they wrote the contribution or have the right to
submit it under GPL-3.0-or-later. Do not submit code under incompatible terms.
Third-party code and assets must retain their original license and attribution;
the project license does not override those terms.
