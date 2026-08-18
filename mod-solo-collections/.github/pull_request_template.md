## Purpose

Describe one focused server-side problem and the player-visible result.

## Scope

- [ ] Account state, revision, or SQL
- [ ] Provider or server action
- [ ] SC2 (link matching SoloCollections PR)
- [ ] Transmogrification compatibility
- [ ] AzerothCore build/API compatibility
- [ ] Documentation

## Evidence

- Source/static:
- Build:
- Server runtime:
- Client runtime:

List only evidence actually collected. Mark live validation as pending when it
was not performed.

## Safety

- [ ] C++ remains the only production writer
- [ ] Database/revision invariants remain intact
- [ ] No credentials, runtime configs, dumps, logs, binaries, or local paths are included
- [ ] Generated catalog changes link their canonical source and matching client PR
- [ ] Agent-assisted changes, if any, were human-reviewed
