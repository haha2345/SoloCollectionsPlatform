# Agent instructions for SoloCollections

These instructions apply to the complete repository.

## Read first

Before editing, read:

1. `README.en.md` or `README.md`;
2. `docs/DEVELOPMENT.md`;
3. the architecture document for the affected component;
4. `docs/CAMERA_CONTRIBUTIONS.md` for any model or camera change;
5. `docs/ASSETS.md` for media, MPQ, or release work.

## Repository responsibility

This repository owns the WoW 3.3.5a AddOn, canonical catalog sources and review
data, SC2 protocol schema/vectors, catalog/release tooling, and the optional
SoloCam source. The authoritative C++ backend lives in the sibling
`mod-solo-collections` repository.

Never make client display data authoritative. The server owns collection
state, authorization, revision ordering, and actions.

## Source-of-truth rules

- Edit catalog inputs under `catalog/source` and review decisions under
  `catalog/review`.
- Regenerate projections; do not hand-edit
  `addon/SoloCollections/Data/Generated/Catalog.lua` as the source of a change.
- Keep the Lua and C++ projections on the same metadata and mapping hashes.
- Preserve stable IDs. Do not recycle or reorder an existing public identity.
- Maintain WoW 3.3.5 Lua 5.1 compatibility. Retail-only APIs are unavailable.
- Missing capabilities, unknown identities, and version/asset mismatches must
  fail closed.

## Camera work

- Follow `docs/CAMERA_CONTRIBUTIONS.md`.
- Body camera keys are `(raceId, sex, slot)`.
- Weapon precedence is `appearance > model > weaponFamily > autoCamera`.
- Prefer the broadest verified scope that describes the actual cause; do not
  add one appearance override for a shared-model problem.
- Never claim visual completion from source inspection or a build alone. Ask
  the user for the documented real-client screenshots and matrix when they are
  not available.

## Safety and publication boundary

Do not add or download game executables, patched executables, DLL/PDB build
outputs, MPQs, DBC/DB2, M2/SKIN/BLP, WDB, extracted client assets, database
dumps, credentials, SavedVariables, or complete runtime logs.

Do not modify a real game installation, server runtime, production database, or
GitHub release unless the task explicitly authorizes that action. Prefer a
repository-local change and provide deployment steps for the user.

Keep generated work below ignored `build`, `_work`, or `release` directories.
Do not hard-code a maintainer's absolute paths.

## Working method

1. Inspect `git status` and keep unrelated user changes intact.
2. Make one bounded change.
3. Update the matching documentation and generated contract when applicable.
4. Run only the checks relevant to the edited area.
5. Report separately:
   - source/static checks;
   - build results;
   - server runtime results;
   - real-client visual results.
6. Do not mark a runtime or visual result complete when it was not observed.

For cross-repository changes, state the required AddOn and module commits and
their merge/deployment order.
