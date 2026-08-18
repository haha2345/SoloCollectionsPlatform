# Upstream Base

`mod-solo-collections` is a project fork of AzerothCore's `mod-transmog` module.
The fork keeps the original Git history and license so upstream changes remain
auditable.

| Field | Value |
|---|---|
| Upstream repository | <https://github.com/azerothcore/mod-transmog.git> |
| Upstream branch | `upstream/master` |
| Fork base commit | `33ac64b2c305eb1b6fbc97310a7ecbc30c2ba4ef` |
| Audited AzerothCore commit | `bdb39abddb319eac0cd0755eedb3bffdb6490930` |
| Audit date | 2026-07-19 |

## Branch and remote policy

- `upstream/master` tracks the official `mod-transmog` repository.
- `main` is the long-lived branch for this project's own development.
- Task work is prepared on feature branches and merged into `main` only after
  review.
- `origin/main` tracks this project's public repository.

## Modification scope

The fork hardened the inherited transmogrification implementation and extended
it into the authoritative C++ backend for SoloCollections. Project changes are
tracked in Git after the base commit above; upstream history remains the
auditable reference.
