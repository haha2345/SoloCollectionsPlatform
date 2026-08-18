# Continuing development with an agent / 使用 Agent 继续开发

This guide is for contributors using Codex, Claude Code, Copilot, or another
repository-aware coding agent. It does not replace human review or real-client
acceptance.

## 中文

### 推荐目录

把两个仓库放成同级目录，Agent 才能看清协议和生成投影的边界：

```text
collections-workspace/
├─ SoloCollections/
└─ mod-solo-collections/
```

不要把仓库直接克隆到 `Interface/AddOns` 或正在运行的 AzerothCore 目录。源码、
部署目标和运行数据应分开。

### 每次任务的开始方式

先让 Agent：

1. 阅读当前仓库的 `AGENTS.md`；
2. 阅读 `README.md`、`docs/DEVELOPMENT.md` 和相关架构文档；
3. 查看两个仓库的 `git status`、当前分支和远端；
4. 说明修改属于 AddOn、目录、协议、SoloCam 还是服务端模块；
5. 列出不会修改的边界；
6. 只在功能分支中工作。

一个好的初始提示：

```text
你在两个同级仓库 SoloCollections 和 mod-solo-collections 中工作。
先完整阅读两个仓库的 AGENTS.md，以及 SoloCollections/docs/DEVELOPMENT.md。
目标：<一个具体问题>。
先检查现有实现、生成源和相关文档，说明权威源在哪里。
保持 C++ 服务端为唯一权威，不提交客户端二进制、提取素材、数据库或运行日志。
只做完成目标所需的最小修改；把自动检查、编译、服务器运行和真实客户端视觉
验收分开报告。需要真实客户端截图时给我明确步骤，不要假装已经看过。
```

### 适合交给 Agent 的任务

- Lua 5.1 UI bug、过滤、分页和固定对象池优化；
- Python 目录生成器、schema、review-only 导入器；
- SC2 schema/golden vectors 与 AddOn/C++ 的同步改动；
- C++ domain、provider、cache、协议解析和命令；
- 文档、英文界面和安全边界；
- 根据已提供的镜头 JSONL 和截图制作最小参数 PR。

### 必须由人控制的部分

- 登录账号、选择角色和真实客户端视觉判断；
- 提供或安装合法客户端资源；
- 生产数据库 migration 和运行配置；
- 覆盖 EXE/DLL/MPQ/DBC、清理 WDB 或部署 worldserver；
- GitHub Release、公开二进制和第三方资源许可证判断；
- 最终决定镜头参数是否“更正常”。

Agent 可以生成操作步骤和检查清单，但没有明确授权时不应执行这些动作。

### 镜头任务提示模板

```text
阅读 AGENTS.md 和 docs/CAMERA_CONTRIBUTIONS.md。
输入是我提供的 workbench JSONL、修改前后截图和客户端信息。
目标只处理 <race/sex/slot 或 appearance/model/family>。
验证 scope 是否正确，优先使用 model 或 weaponFamily，单件异常才用 appearance。
不要修改其他 profile，不要上传或读取游戏资源。
更新 canonical override、受影响的生成合同和文档。
最后列出我需要在真实客户端检查的普通/极端样本、/reload、翻页和 fallback。
```

### 跨仓库协议任务提示模板

```text
先读取 protocol/sc2/schema.json、golden-vectors.json、AddOn Bridge 和模块协议代码。
目标：<协议变更>。
保持消息长度、canonical 数字、nonce、revision 和失败关闭规则。
分别在两个仓库创建配套修改，给出合并顺序和匹配 commit 要求。
不要让旧客户端字段成为服务端授权依据。
```

### 如何审查 Agent 的结果

至少检查：

- `git diff` 是否只包含目标范围；
- 是否出现绝对个人路径、秘密或客户端资源；
- 是否直接修改 generated output 而没有源/审核变更；
- AddOn 与模块的 metadata/mapping 是否一致；
- README 和相关文档是否同步；
- “通过”是否明确区分静态、编译、服务器和真实客户端；
- 镜头视觉结论是否有实际截图，而不是推断。

## English

### Workspace and startup

Clone `SoloCollections` and `mod-solo-collections` as sibling repositories,
outside the live client and server runtime. At the beginning of each task, ask
the agent to read both `AGENTS.md` files, inspect Git status and branches,
identify the authoritative source layer, state what it will not change, and
work on a feature branch.

Use a bounded prompt:

```text
You are working in sibling SoloCollections and mod-solo-collections repos.
Read both AGENTS.md files and SoloCollections/docs/DEVELOPMENT.md first.
Goal: <one concrete issue>.
Identify the source of truth before editing. Preserve the C++ server as the
sole authority. Do not add client binaries, extracted assets, databases, or
runtime logs. Make the smallest complete change. Report source checks, builds,
server runtime, and real-client visual acceptance separately. If real-client
evidence is required, give me exact steps instead of claiming it was observed.
```

Agents are well suited to bounded Lua/Python/C++ changes, schema and golden
vector updates, documentation, and turning supplied camera JSONL plus
screenshots into a reviewable parameter patch.

Humans must retain control of login credentials, visual judgment, legally
obtained client assets, production databases, runtime deployment, binary/MPQ
replacement, public releases, and licensing decisions.

Before accepting the result, review the complete diff, source/generated
relationship, cross-repository metadata, documentation, publication boundary,
and the evidence behind every completion claim.
