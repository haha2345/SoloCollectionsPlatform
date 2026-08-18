# Task 0 implementation baseline — 2026-08-11

Evidence state: `IMPLEMENTED_LOCAL` for the source/evidence baseline only. No new UI was deployed, no database was changed, and nothing was pushed.

## Repository state

| Repository | Commit / state | Branch / status | Remote |
| --- | --- | --- | --- |
| SoloCollections | `df7e873059fcaeb8c3af6496b3c49b5a1f5fd818` | baseline `main`; implementation branch `feat/dragonui-collections-shell`; pre-existing untracked `docs/plans/` | `https://github.com/haha2345/SoloCollections.git` |
| SoloClientSuite | absent at baseline; initialized locally for this plan | `feat/bootstrap-ui-platform` | no remote configured |
| mod-solo-collections | directory exists but is empty and is not a Git repository | no Git baseline available | none |

## Locked upstream source

| Component | Commit | Source |
| --- | --- | --- |
| !!!ClassicAPI | `1ffaa484f62f225052de69dd82d97f78bf723fd7` | `https://gitlab.com/Tsoukie/classicapi.git` |
| DragonUI + DragonUI_Options | `9c7e5b189f438391e3de8731b4fc62fc2a0f0839` | `https://github.com/NeticSoul/DragonUI.git` |
| DragonUI_NewEra | `8f3d1007952abd532c6d5b736b7d43d30a9b4719` | `https://github.com/ghbset/DragonUI_NewEra.git` |

The complete Git trees were exported from those exact commits. The prior DragonUI_NewEra audit checkout was sparse and was not treated as a complete source package.

## Rollback snapshot

- Archive: `F:\1_projects\wow_projects\_backups\DragonUI_Collections_Migration_20260811\task0-source-baseline-before-implementation.tar`
- Entries: `3922`
- Bytes: `325543936`
- SHA-256: `B84256B6EBD759D2FF027CD264ECE521B456FBEDFBC19D3FA95657DB0352C89C`
- Scope: SoloCollections (including Git metadata), the empty mod-solo-collections directory, and the three locked upstream audit repositories. The real client installation directory is excluded.

## Before screenshots

- `before-20260811/01-mounts.png`
- `before-20260811/02-pets.png`
- `before-20260811/03-toys.png`
- `before-20260811/04-wardrobe-items.png`
- `before-20260811/05-wardrobe-sets.png`
- `before-20260811/06-titles.png`

These are current legacy UI baselines, not acceptance evidence for the DragonUI migration.
