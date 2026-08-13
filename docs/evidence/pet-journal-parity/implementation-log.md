# Pet Journal Parity Implementation Log

## Task 1 - Baseline freeze

- Recorded at: 2026-08-13 Asia/Shanghai
- SoloCollections branch: `feat/pet-journal-parity`
- SoloCollections start: `e4ce90157438b64e2e5b56d72f34a929ea955d0d`
- SoloCollections audited ancestor: `79572c385dbe` (`merge-base --is-ancestor`: passed)
- mod-solo-collections branch: `feat/pet-journal-parity`
- mod-solo-collections start: `6a747c46a1024373c766d98ba32b81c86267c447`
- mod-solo-collections audited ancestor: `6a747c46` (`merge-base --is-ancestor`: passed)
- SoloClientSuite branch: `feat/pet-journal-parity`
- SoloClientSuite start: `a9c09a0f25e25c00cc6641ef82ecb93ecb4e6995`
- SoloClientSuite audited ancestor: `a9c09a0` (`merge-base --is-ancestor`: passed)
- Catalog mapping hash: `8397010166c3cd9946a840e8cb4a9755751c5e9b4955360c045e5d316f88d5c0`
- Companion mapping hash: `73d3e45693ff2a9178371026bd26081f98f5188a517460d95b12006a5134442a`

Known pre-existing, unrelated work was preserved:

- SoloCollections: modified DragonUI migration plan plus untracked mount-journal plans/evidence.
- mod-solo-collections: clean.
- SoloClientSuite: untracked `docs/evidence/`.

Task 1 direct checks passed. No cleanup command was used.

## Task 2 - Companion identity and source audit

- Evidence ID: `pet-journal-parity-20260813`
- Evidence pack hash: `632c36121fd462083d0a43aa9a75a0047797785e716fd3e05c9a8abcbe95b736`
- Candidate hash: `98900e63c77dcfdc1fdc0931182dfacbd638c45b6c6fd8ccf41e13f228a6c933`
- Identity pipeline: 205 SkillLine rows -> 203 positive summon spells -> 201 canonical creatures.
- Identity comparison with the previous reviewed evidence: exact creature/spell/name match; no stable ID drift.
- World relations: item 177, quest 84, vendor 67, loot 85, achievement 9, profession 12, event 30.
- Read-only PetData cross-reference matches: 343 rows from two separately hashed sources.
- Duplicate merge groups: 2; hidden non-summon placeholders: 2.
- Visible/actionable/random-eligible canonical companions: 201/201/201.
- zhCN source gaps recorded: 20; zhCN description gaps recorded: 201.
- Direct checks: companion generator check passed; 10 focused tests passed with 1 optional named-pack check skipped because no review-pack environment variable was supplied; `git diff --check` passed.

## Task 3 - zhCN journal metadata

- Metadata coverage: 201/201 canonical companion actions.
- Reviewed zhCN names: 201; missing names: 0.
- Reviewed world-backed source blocks: 103.
- Reviewed category cross-reference source blocks: 77.
- Explicit source gaps: 21.
- Verified zhCN lore descriptions found: 0; all 201 records retain an empty description with `descriptionStatus=MISSING`.
- Description provenance records the attempted spell/creature/name lookup keys and does not copy English PetData lore.
- Currency lines use only inline `UI-GoldIcon.blp:0` textures; source line breaks use `|n`.
- Direct checks: deterministic catalog check passed; 13 focused tests passed with 1 optional named-pack check skipped; `git diff --check` passed.
