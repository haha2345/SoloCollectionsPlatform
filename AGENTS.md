# Agent instructions

Read `README.md`, `docs/DEVELOPMENT.md`, `docs/CONFIGURATION.md`, and the
nearest source before editing.

- Treat this module as the authoritative production writer. Never grant
  ownership from client display data or SavedVariables.
- Preserve the account revision/transaction invariant documented in
  `docs/schema/account-collections-v1.md`.
- SC2 and generated-catalog changes require matching work in the sibling
  `SoloCollections` repository. Do not hand-edit generated `.inc` files.
- Keep ALE/SC1 migration modes separate from the C++/SC2 production path.
- Do not commit credentials, runtime configs, database dumps, logs, build
  products, game binaries, or extracted client assets.
- Do not mutate a real database, deploy a server, push, release, or change the
  user's client without explicit authorization.
- Keep changes focused. Report source checks, build results, server runtime,
  client runtime, and visual acceptance as separate states; never infer one
  from another.
- Ask before starting a long full-Core build unless the user requested it.

For cross-repository work, identify both repositories and record the required
commit/merge order in the handoff.
