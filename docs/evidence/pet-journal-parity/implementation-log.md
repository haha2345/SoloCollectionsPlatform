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

## Task 4 - AddOn/module journal projection

- Catalog mapping hash: `ea9c46e76154da493c64a0b2f79c1399a83f3852ea3ad6c228edc9494f1a8d42`.
- Companion type mapping hash: `15e24a2e506652232dd862bf328203df761d7654296a05233c5df5d4457f4ff7`.
- AddOn projection includes reviewed display metadata and execution eligibility flags.
- Module JSON/C++ projections contain execution identity and eligibility only; no source or description strings are emitted to C++.
- `--companion-journal-only` and `--check` use the shared production renderer and synchronize both repositories.
- Direct checks: projection check passed; catalog generator 19 tests passed with 1 external-evidence check skipped; companion catalog 13 tests passed with 1 optional named-pack check skipped; both repository diffs passed whitespace checks.

## Task 5 - SC2 companion favorite/random protocol

- Type 11 remains the authoritative owned companion set.
- Type 17 is the internal companion-favorite projection over type 11 IDs and is excluded from navigation and progress.
- `SET_FAVORITE` and `RANDOM_SUMMON` now allow owned types 10 and 11; projection mapping is explicit as 10 -> 16 and 11 -> 17.
- Added stable `NO_COMPANIONS` and `NO_USABLE_COMPANIONS` result tokens.
- Added golden packets for type 17 snapshot/delta, companion favorite on/off, random summon, not-owned rejection and invalid random control ID.
- Existing mount packets remain present and unchanged.
- Direct checks: 8 SC2 protocol tests and 9 client contract tests passed; `git diff --check` passed.

## Task 6 - Server-side companion favorite persistence

- Added internal companion-favorite projection type 17 with an explicit 17 -> 11 persistence mapping; the existing mount mapping remains 16 -> 10.
- Account loads now project stored type 10/11 preference rows into SC2 type 16/17 state.
- Preference mutations reject every internal type outside the two explicit mappings and require ownership of the corresponding type 10/11 collection before writing.
- Registered the dependency-only `companion-favorite` provider; navigation, totals, and progress remain controlled by the canonical SC2 schema, where type 17 is internal.
- Type 11 `SET_FAVORITE` uses the existing asynchronous database commit, account revision, cache delta, and connected-session notification route.
- The existing append-only `2026_08_12_00_mount_preferences.sql` already creates the generic table required by upgraded installations. The clean-install schema snapshot lacked it, so the same generic table definition was added there; no new SQL update was created and no executed migration semantics were changed.
- Direct checks: required source searches and `git diff --check` passed. Full AzerothCore compilation remains deferred to the plan's build gate.
- Module commit: `ca6abfe feat(companions): persist account favorites`.

## Task 7 - Authoritative random companion summon

- Specified and random companion summons converge on one internal executor for alive, combat, vehicle, taxi, map, cast, and toggle checks.
- Random candidates are derived only from the server catalog, type 11 ownership, and type 17 favorites.
- No owned type 11 entries returns `NO_COMPANIONS`; owned but no active/visible/actionable/random-eligible entries returns `NO_USABLE_COMPANIONS`.
- A non-empty favorite pool is authoritative; otherwise the eligible owned pool is used. When more than one candidate exists, the currently summoned companion is removed from the pool; a single current candidate retains the existing dismiss toggle.
- Type 11 `RANDOM_SUMMON` requires control collection ID 1 and target `-` before entering the service.
- Direct checks: required source searches and `git diff --check` passed. Full AzerothCore compilation remains deferred to the plan's build gate.
- Module commit: `b03ccd1 feat(companions): add authoritative random summon`.

## Task 8 - AddOn bridge and legacy pet favorite migration

- Added type 11 `SetPetFavorite` and control-ID-1 `SummonRandomPet` SC2 wrappers; no display spell, creature, or local ownership bit is sent.
- CollectionState recognizes type 17 through an internal projection definition whose mapping hash is inherited from companion type 11. It is absent from page category keys and therefore cannot enter navigation or progress.
- Generalized the existing mount migration driver into two explicit migrations: MOUNTS 10 -> 16 and PETS 11 -> 17.
- PETS migration queues only legacy `true` entries that are currently owned in type 11 and absent from type 17. An accepted request does not complete an item; the driver advances only after authoritative type 17 state is observed.
- Completion is persisted as `migrations.petFavoritesToServer = 1`; the legacy PETS table is retained for rollback but is no longer read after that marker.
- Added stable zhCN text for companion action results, including the two new empty-pool statuses.
- SavedVariables schema is now version 7. `filters.pets.hiddenSources` is repaired in place and unrelated filter values are preserved.
- Checks: 30 bridge contracts and 10 SC2 client contracts passed; `git diff --check` passed. The bridge test's existing preview locator was updated to recognize both direct and presenter-based safe-failure implementations.
- AddOn commit: `823f20f feat(addon): bridge companion preferences and random summon`.

## Task 9 - Companion catalog query semantics

- Companion records now read generated `sourceText`, `sourceType`, `descriptionZhCN`, journal visibility, actionability, and random eligibility. The fixed account/source placeholder text was removed.
- PETS favorites resolve exclusively from internal type 17 when collected; uncollected records are always non-favorites.
- The mount presentation comparator was generalized and is shared by MOUNTS/PETS: favorite-collected, collected, uncollected, localized name, then stable collection ID. The mount rank and tie-break behavior is unchanged.
- PETS source filtering reads only `filters.pets.hiddenSources`; mount filters remain isolated.
- The generated companion source admits only active journal-visible records, so QueryAll and GetProgress share the same visible universe.
- Production-connected UI no longer mutates demo PETS preferences. The legacy toggle is reachable only in explicit offline demo mode.
- Focused checks: the new companion query contract passed; all 14 companion catalog checks passed with 1 optional evidence-pack check skipped; `git diff --check` passed.
- The plan's full `test_addon_contract.py` run remains red on numerous pre-existing DragonUI/NewEra assertions outside Task 9 (layout, presenter, TOC, wardrobe and toy expectations). These are retained for Tasks 10-15 integration cleanup rather than masking them here.
- AddOn commit: `a20aea5 feat(addon): align companion catalog query semantics`.

## Task 10 - Generic DragonUI random collection control

- Added `CreateRandomCollectionButton(parent, spec)` with caller-provided label, icon, fallback icon, tooltip, click handler, and optional drag handler.
- Preserved `CreateRandomMountButton` as a compatibility alias with the exact existing mount icon default.
- Both `components.random-collection` and `components.random-mount` capabilities are advertised.
- The generic control retains the accepted icon crop, thin action border, pushed texture, and additive highlight. It contains no collection selection, favorite state, macro creation, or `/script` behavior.
- Public API documentation now assigns state and action authority to the consuming AddOn/server bridge.
- Checks: `Inspect-ClientSuiteLayout.ps1` passed; source search confirmed both capabilities/entry points and no macro behavior in the component; `git diff --check` passed.
- SoloClientSuite commit: `77bcb8e feat(newera): generalize random collection control`.

## Task 11 - Shared mount/pet journal shell

- Exposed the existing `MountJournal` adapter as the compatible `CompanionJournal` alias and retained every mount entry point.
- Added `CreateRandomCompanionButton`, backed by the new `components.random-collection` capability while preserving `components.random-mount`.
- MOUNTS and PETS now both use a 768 x 606 frame and the same bands, inset geometry, side padding, gap, bottom inset, row height, and ten-row layout.
- PETS rows and FauxScrollFrame begin at `ROW_START_Y = 3`; ten 46px rows fit the 466px list viewport.
- Replaced the mount-only shell filter control with a MOUNTS/PETS companion control that routes to the active page. `scMountFilterButton` remains as a compatibility alias.
- PETS owns the named `SoloCollectionsPetFilterMenu` UIDropDownMenu frame and no longer writes options into the legacy shared popup.
- Existing DragonUI journal tabs remain the only bottom-tab implementation.
- Focused shell contract and `git diff --check` passed. The required full AddOn contract command ran 63 tests but remains at 21 failures/1 error from the previously recorded stale cross-feature expectations; no new Task 11 focused assertion failed.
- AddOn commit: `210ed9d feat(ui): align pet journal shell with mounts`.

## Task 12 - Reviewed companion detail presentation

- Replaced the manual pet icon/name/source/description group with the same `CreateCollectionInfoHeader` component and geometry used by the mount journal.
- Companion icons use the shared 0.08-0.92 crop and gold ornament. The generated zhCN `sourceText` is rendered directly, including font-height inline currency textures.
- Companion descriptions use generated `descriptionZhCN`; an empty value now shows the explicit `暂无可核验的中文描述` gap marker and never invents fallback prose.
- The favorite/reset controls remain anchored inside the detail inset; the summon control is now the centered 180 x 26 shared red action in the bottom band.
- Generated companion projections now retain spell action identity so the UI can compare the current native CRITTER companion and switch between summon/dismiss labels.
- Clearing selection or hiding the page clears header, model, selection border, and button state. `COMPANION_UPDATE` refreshes the current summon label.
- Focused detail contract and `git diff --check` passed. The direct placeholder search now finds only the known demo-only PETS toggle and unrelated TOYS/APPEARANCES placeholder records; the generated companion source contains neither old placeholder.
- AddOn commit: `971d224 feat(ui): add reviewed companion detail presentation`.

## Task 13 - Continuous companion model rotation and recovery

- Pet model buttons and drag updates now share the mount journal's wrapped heading state and use `SetFacing`; `SetRotation(rotation, false)` is only the API fallback.
- Drag updates are attached only while captured by the left mouse interaction and are removed on release, selection changes, model resets, and page hide.
- Wheel zoom retains the native loaded scale and the same bounded 0.35-2.5 multiplier used by mounts; the reset path restores the shared default orientation.
- Every preview request records both a generation and selected collection ID. Preview, ready, and unavailable callbacks are ignored unless both still match.
- Type 11 bridge state is checked before preview. Pending requests retry only when type 11 becomes Ready and the same record remains selected and visible; mismatch has a dedicated state message.
- Refreshing an unchanged ready selection no longer reloads the model. Hidden/filtered selections invalidate pending callbacks and clear the old model.
- Focused rotation/recovery contract and `git diff --check` passed. The required full AddOn contract run executed 65 tests and remains at the same 21 stale cross-feature failures plus 1 stale scheduler error; both new Task 12/13 contracts passed.
- AddOn commit: `b905b72 fix(ui): keep companion model animation continuous while rotating`.

## Task 14 - Authoritative companion journal interactions

- The PETS filter menu now exposes collected, uncollected, favorites, and a second-level source menu derived only from source types present in the generated companion catalog.
- Favorite clicks and context actions call `Bridge.SetPetFavorite`; the selected row is disabled while pending and UI sorting/text changes only after the authoritative type 17 delta is observed.
- Uncollected favorites remain disabled in both the detail button and context menu. The production PETS UI no longer calls `ToggleDemoFavorite`.
- Added the generic top-band random companion button. It sends only `Bridge.SummonRandomPet`; all selection remains server-side and failures use the stable zhCN bridge messages.
- The random control's presentation icon prefers a collected favorite eligible record, then any collected eligible record, then the question-mark fallback. This is display-only and never selects the summoned collection.
- The bottom and context summon actions call `Bridge.SummonPet`; native CRITTER state switches their label between summon and dismiss while the server retains toggle authority.
- Refresh keeps the selected row scrolled into view, falls back to the first sorted record when filtered out, and uses the unfiltered journal-visible universe for progress/count totals.
- Checks: 4 focused companion AddOn contracts, all 30 bridge contracts, all 16 catalog contracts, direct authority/source searches, and `git diff --check` passed.
- AddOn commit: `4bf1347 feat(ui): complete companion journal interactions`.
