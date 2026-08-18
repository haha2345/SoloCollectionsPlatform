# Contributing / 参与贡献

[中文](#中文) · [English](#english)

## 中文

欢迎贡献 C++、SQL、SC2、AzerothCore 兼容性、性能和文档。

### 先选对仓库

- UI、Lua、canonical 目录、SC2 schema、生成器和 SoloCam：
  [`SoloCollections`](https://github.com/haha2345/SoloCollections)；
- 权限、账号状态、数据库、provider、服务端动作和幻化：本仓库；
- SC2 或 generated catalog 变更：必须同时链接两个仓库的 PR/commit。

### 提交流程

1. Fork 后从最新 `main` 建立功能分支；
2. 一次 PR 只解决一个可描述的问题；
3. 不手工修改 `src/generated/*.inc`，应从客户端仓库 canonical source 重新生成；
4. SQL 只允许可审计、可回滚的 append-only migration；
5. 更新行为相关文档；
6. 列出实际完成的 source/static、build、server runtime 和 client runtime 证据；
7. 未完成的真实服务端/客户端验收要明确写成 pending。

不要提交数据库凭据、`worldserver.conf`、运行日志、数据库 dump、构建目录、
EXE/DLL/PDB、客户端资源或本机绝对路径。

### 重点审查

- 客户端字段/SavedVariables 不得授权；
- `Cpp` 模式必须是唯一写入者；
- 成功 mutation 只推进一次 revision，并在缓存/会话更新前提交数据库；
- 重复、失败或过期请求不能留下 cache-only unlock；
- SC2 变更保持 schema、golden vectors、AddOn 和模块一致；
- 日志不包含密码、token 或个人数据。

### Agent 辅助开发

在 prompt 中要求 Agent 先读 `AGENTS.md`、`docs/DEVELOPMENT.md` 和目标源码，
只处理一个范围。让它报告假设、修改文件、未完成验收和跨仓库依赖。人类必须
审查 SQL、授权、数据库写入、Core 部署和 GitHub 发布。

## English

Contributions to C++, SQL, SC2, AzerothCore compatibility, performance, and
documentation are welcome.

Use the client repository for UI, Lua, canonical catalog, SC2 schema,
generators, and SoloCam. Use this repository for authorization, account state,
database code, providers, server actions, and transmogrification. A protocol
or generated-catalog change must link the matching work in both repositories.

Create a focused branch from current `main`; do not edit generated `.inc`
files by hand; use append-only, auditable SQL migrations; update relevant
documentation; and report source/static, build, server-runtime, and
client-runtime evidence separately. Mark any missing live acceptance as
pending.

Do not commit credentials, runtime configuration, logs, database dumps, build
output, binaries, extracted client assets, or personal absolute paths.

Review carefully that the client cannot authorize an action, C++ remains the
sole production writer, one successful mutation advances one revision, failed
requests cannot leave cache-only state, and SC2 stays synchronized across
schema, golden vectors, AddOn, and module.

For Agent-assisted work, require the Agent to read `AGENTS.md`,
`docs/DEVELOPMENT.md`, and the target code first. Keep its task focused and
retain human review of SQL, authorization, database writes, Core deployment,
and GitHub publication.
