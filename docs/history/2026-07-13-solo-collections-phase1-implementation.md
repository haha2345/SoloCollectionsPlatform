# SoloCollections Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and deploy a standalone WoW 3.3.5a `SoloCollections` AddOn with retail-style mounts, non-battle pets, toys, wardrobe items, wardrobe sets, real 3D previews, fixed demo collection states, and a passive `SC1` mod-ale handshake.

**Architecture:** Keep Phase 1 client-driven: static verified 3.3.5 catalog data flows through one catalog service into five reusable UI views. Add a separate mod-ale Lua bridge that only negotiates protocol/version state; if it is absent, the AddOn remains fully functional in demo mode. Package compatible retail-inspired textures inside the AddOn and never modify FrameXML or MPQs.

**Tech Stack:** WoW 3.3.5 Lua/FrameXML API, AzerothCore mod-ale Lua, Python 3.10 contract tests, PowerShell deployment and SHA-256 verification, local Wrath DBC/DB data, local retail UI source/CASC assets.

---

## Preflight constraints

- Design source: `F:\1_projects\wow_projects\docs\plans\2026-07-13-solo-collections-phase1-design.md`.
- AddOn source: `F:\1_projects\wow_projects\插件\SoloCollections`.
- AddOn live target: `D:\Games\wow335\world of warcraft 3.3.5a hd\Interface\AddOns\SoloCollections`.
- Server Lua source: `F:\1_projects\wow_projects\mod-ale\lua_scripts\solo_collections.lua`.
- Server Lua live target: `D:\AzerothCore_NPCBots_Clean\lua_scripts\solo_collections.lua`.
- Retail UI reference: `F:\1_projects\wow_projects\_work\main_quest_marker\reference\wow-ui-source\Interface\AddOns\Blizzard_Collections`.
- Retail data root: `F:\Games\World of Warcraft\_retail_`.
- Wrath DBC root: `D:\AzerothCore_NPCBots_Clean\Data\dbc`.
- The workspace root currently has an empty `.git` directory and is not a valid Git repository. Do not initialize, repair, or commit without explicit user authorization. Use test reports and SHA-256 manifests as implementation checkpoints. The `mod-ale` subrepository may only receive a commit if its worktree is clean and the user later authorizes commits.

### Task 1: Freeze the Phase 1 contracts with failing tests — COMPLETE

**Files:**
- Create: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_catalog_contract.py`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_bridge_contract.py`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_media_contract.py`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_deployment_contract.py`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\README.md`

**Step 1: Write the failing AddOn structure test**

Assert all of the following:

```python
assert "## Interface: 30300" in toc
assert "## SavedVariables: SoloCollectionsDB" in toc
assert toc_files == expected_load_order
assert forbidden_api not in all_lua
assert all_lua.count("SoloCollections = SoloCollections or {}") == 1
```

`forbidden_api` must include `C_MountJournal`, `C_PetJournal`, `C_ToyBox`, `C_TransmogCollection`, `CreateScrollBoxListLinearView`, `SetAtlas`, `ModelScene`, and `Mixin`.

**Step 2: Write the failing catalog tests**

Parse the five data files and require exact counts:

```python
EXPECTED_COUNTS = {
    "mounts": 24,
    "pets": 24,
    "toys": 36,
    "appearances": 48,
    "sets": 8,
}
```

Require unique IDs, non-empty Chinese fallback names, valid icon fields, collection state on every record, both collected/uncollected states in every category, and complete set item lists.

**Step 3: Write the failing bridge tests**

Require prefix `SC1`, request `HELLO|1`, response `HELLO_ACK|1|DEMO`, `CHAT_MSG_ADDON` registration, a finite timeout, and a no-server demo fallback. Reject SQL calls, `LearnSpell`, `CastSpell`, item deletion, and `mod-transmog` calls in the Phase 1 server Lua.

**Step 4: Write the failing media and deployment tests**

Require `Media/assets.json`, referenced files, SHA-256 entries, supported `.blp`/`.tga` extensions, source/live manifest parity, and no files outside `SoloCollections` plus the single server Lua target.

**Step 5: Run the focused suite and confirm failure**

Run:

```powershell
python -m unittest discover -s F:\1_projects\wow_projects\tools\solo_collections\tests -p "test_*.py" -v
```

Expected: FAIL because the AddOn, data, bridge, media manifest, and deployment manifests do not exist.

**Step 6: Record checkpoint**

Save the failure summary in `F:\1_projects\wow_projects\_work\solo_collections_phase1\test-baseline.txt`. If Git is restored later, commit with `test: define SoloCollections phase 1 contracts`.

### Task 2: Create the isolated AddOn shell and persistent state — COMPLETE

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\SoloCollections.toc`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\SoloCollections.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Bootstrap.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Catalog.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Bridge.lua`

**Step 1: Add the TOC in deterministic load order**

Use `Interface: 30300`, title `Solo Collections`, version `0.1.0`, `SavedVariables: SoloCollectionsDB`, and load Data before Core services, templates, pages, frame, launcher, and bootstrap.

**Step 2: Create one namespace**

Only `SoloCollections.lua` may create the global:

```lua
SoloCollections = SoloCollections or {}
local SC = SoloCollections
SC.VERSION = "0.1.0"
SC.PROTOCOL = "SC1"
```

Every other file starts with `local SC = SoloCollections` and defines fields below that table.

**Step 3: Normalize SavedVariables**

`Bootstrap.lua` creates versioned defaults for launcher point, frame point, main tab, wardrobe tab, query text, filters, favorites, debug flag, and bridge state. Invalid or old values are replaced field-by-field, never by erasing the whole table.

**Step 4: Register events and slash commands**

Register `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_LOGOUT`, `CHAT_MSG_ADDON`, and `PLAYER_ENTERING_WORLD`. Add `/sc`, `/collections`, `/sc reset`, and `/sc debug`; reset only the AddOn positions and filters.

**Step 5: Run the structure tests**

Run:

```powershell
python -m unittest F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py -v
```

Expected: structural assertions pass; page/catalog assertions remain failing.

**Step 6: Record checkpoint**

Create a SHA-256 file list under `F:\1_projects\wow_projects\_work\solo_collections_phase1\checkpoints\task02.sha256`. Conditional commit message: `feat: scaffold SoloCollections addon`.

### Task 3: Build and verify the fixed 3.3.5 demo catalogs — COMPLETE

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Data\Mounts.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Data\Pets.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Data\Toys.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Data\Appearances.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Data\Sets.lua`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\catalog_manifest.json`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\verify_catalog.ps1`

**Step 1: Define stable record shapes**

Use these fields:

```lua
-- mount/pet
{ id, creatureId, spellId, name, icon, source, description, collected, favorite }

-- toy
{ id, itemId, name, icon, source, description, collected, favorite }

-- appearance
{ id, itemId, slot, classMask, name, icon, source, collected, favorite }

-- set
{ id, classToken, name, icon, itemIds, collected, favorite }
```

Do not store Retail-only species, battle-pet, visual-source, account, or transmog API identifiers.

**Step 2: Curate only local Wrath records**

Verify creature/spell/item/set IDs against `D:\AzerothCore_NPCBots_Clean\Data\dbc` and the local world database. Select recognizable entries distributed across Classic, TBC, and Wrath. Avoid event-only records that are absent from the local world DB unless their model/item exists and can be previewed.

**Step 3: Make demo status deterministic**

Set fixed mixed states in source data; do not randomize at runtime. Ensure every category has at least 25% collected and 25% uncollected. Set a small fixed subset as favorites.

**Step 4: Write the catalog verifier**

`verify_catalog.ps1` checks source files, counts, duplicate IDs, required fields, referenced item/spell/creature IDs, and emits `catalog_manifest.json` with selected IDs and verification sources.

**Step 5: Run catalog tests**

Run:

```powershell
& F:\1_projects\wow_projects\tools\solo_collections\verify_catalog.ps1
python -m unittest F:\1_projects\wow_projects\tools\solo_collections\tests\test_catalog_contract.py -v
```

Expected: 24 mounts, 24 pets, 36 toys, 48 appearances, 8 sets; no duplicates or missing required fields.

**Step 6: Record checkpoint**

Conditional commit message: `feat: add verified Wrath collection demo catalogs`.

### Task 4: Recreate the retail collection chrome with 3.3.5-safe media — COMPLETE

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\assets.json`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Backgrounds\collection-bg.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Borders\collection-border.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Borders\collected-frame.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Borders\uncollected-frame.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Tabs\mounts.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Tabs\pets.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Tabs\toys.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Tabs\wardrobe.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Icons\launcher.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Templates.lua`

**Step 1: Map the visual reference**

Use `Blizzard_Collections/Mainline` and `Blizzard_Collections/Wrath` only to document frame proportions, tabs, progress bars, search/filter placement, selected/unselected states, and wardrobe sub-tabs. Record source paths and the local UI-source commit in `assets.json`.

**Step 2: Extract or recreate only required textures**

Extract source textures from `F:\Games\World of Warcraft\_retail_` using the locally validated CascLib route. Flatten Atlas regions to standalone TGA/BLP files. Convert only files the 3.3.5 client cannot load; preserve alpha and power-of-two dimensions.

**Step 3: Implement reusable templates**

`Templates.lua` provides functions for the nine-slice journal frame, bottom tab, top sub-tab, search box, filter popup, progress bar, list row, icon tile, page controls, empty state, and fallback texture. It may use only `CreateFrame`, `Texture`, `FontString`, `UIPanelButtonTemplate`, `UIDropDownMenuTemplate`, and 3.3.5-safe APIs.

**Step 4: Validate media**

Run:

```powershell
python -m unittest F:\1_projects\wow_projects\tools\solo_collections\tests\test_media_contract.py -v
```

Expected: every manifest file exists, hash matches, extension is supported, and no modern Atlas call remains.

**Step 5: Record checkpoint**

Conditional commit message: `feat: add 3.3.5 collection journal media`.

### Task 5: Implement the launcher and main journal frame — COMPLETE

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Launcher.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\CollectionsFrame.lua`

**Step 1: Write/extend failing frame contract assertions**

Require a bottom-right launcher, drag handlers, clamped saved position, lazy journal construction, close button, four main tabs, wardrobe sub-tab state, and no global frame names outside the `SoloCollections` prefix.

**Step 2: Build the launcher**

Create a round 42–48 px button anchored to `BOTTOMRIGHT`, with tooltip `收藏`, left-click toggle, drag-on-left-button, screen clamping, saved point, and `/sc reset` support. Do not attach it to the minimap or action bars.

**Step 3: Build the journal shell**

Create the frame lazily on first open. Add title, portrait, close button, progress header, page title, shared search/filter host, content host, and bottom tabs in this order: 坐骑、小宠物、玩具箱、外观.

**Step 4: Add responsive scaling**

Use the 1920×1080 design dimensions, calculate a capped scale from `UIParent:GetWidth()/designWidth` and `UIParent:GetHeight()/designHeight`, and keep close/search/tabs visible at 1024×768. Clamp the final frame on every show and after display-size changes.

**Step 5: Run focused tests**

Run:

```powershell
python -m unittest F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py -v
```

Expected: launcher/main-frame contracts pass; page-specific contracts remain pending.

**Step 6: Record checkpoint**

Conditional commit message: `feat: add collection launcher and journal shell`.

### Task 6: Implement the catalog service, filtering, pagination, and empty states — COMPLETE

**Files:**
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Catalog.lua`
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Templates.lua`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_catalog_contract.py`

**Step 1: Write executable model tests for catalog behavior**

Mirror the intended Lua semantics in Python fixtures and cover case-insensitive search, collected/uncollected toggles, favorites, class/slot filters, stable sorting, page clamping, progress counts, and zero-result behavior.

**Step 2: Implement the pure catalog API**

Provide:

```lua
SC.Catalog.Get(category)
SC.Catalog.Query(category, query, filters, page, pageSize)
SC.Catalog.GetProgress(category, filters)
SC.Catalog.ToggleDemoFavorite(category, id)
SC.Catalog.ResetFilters(category)
```

Return new result arrays; never mutate fixed source records except demo favorite state stored in `SoloCollectionsDB`.

**Step 3: Implement shared controls**

Search changes refresh only the active page. Filters close on outside click/escape. Page buttons clamp to valid range. Empty results clear the selected item and model before showing the empty-state text.

**Step 4: Run model and source tests**

Expected: all search/filter/page cases pass, including all filters off and page number beyond the last page.

**Step 5: Record checkpoint**

Conditional commit message: `feat: add collection catalog filtering`.

### Task 7: Implement mounts and non-battle-pet pages with real models — COMPLETE (static/automated)

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Mounts.lua`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Pets.lua`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py`

**Step 1: Add failing page assertions**

Require 24-row data contracts, pooled visible list rows, selection, source/description text, collected/uncollected visual state, progress labels, real model calls, rotate controls, and page/model cleanup on hide.

**Step 2: Implement the shared companion-page base**

Use one constructor for mounts and pets. It owns list row pooling, search/filter refresh, selected record, detail labels, favorite state, previous/next page, and a single `DressUpModel`/`PlayerModel` preview.

**Step 3: Load real models**

Use the verified `creatureId` and the 3.3.5 `SetCreature` route already used by `PetPaperDollFrame.lua`. Clear the model before loading a new record. Provide mouse drag rotation and reset rotation. If the model fails, show `无法预览` and keep metadata visible.

**Step 4: Exclude battle-pet behavior**

The pets page must not contain pet level, rarity, abilities, health, loadout slots, revive, cage, release, or battle search controls.

**Step 5: Run focused tests and deploy to a staging AddOn directory**

Expected: source contracts pass; staging load requires manual in-game model verification before proceeding.

**Step 6: Record checkpoint**

Conditional commit message: `feat: add mount and companion collection pages`.

### Task 8: Implement the toy box grid — COMPLETE (static/automated)

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Toys.lua`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py`

**Step 1: Add failing toy-box assertions**

Require an 18-item visible grid, 36 total records, two pages, search/filter/favorites, item tooltip, gray uncollected state, selected state, and no item-use API.

**Step 2: Implement the reusable grid**

Pool exactly 18 tile buttons. Each tile displays icon, name, star, collected border, desaturation/alpha, and tooltip metadata. The second page reuses the same buttons.

**Step 3: Add item metadata fallback**

Use fixed fallback name/icon immediately. If `GetItemInfo`/`GetItemIcon` returns data, enrich the tooltip and refresh on `GET_ITEM_INFO_RECEIVED`. Never call `UseItemByName`, `PickupItem`, `CastSpell`, or server execution in Phase 1.

**Step 4: Verify behavior**

Run the contract suite and manually verify both pages, zero results, missing item cache, and selected/hover/collected states.

**Step 5: Record checkpoint**

Conditional commit message: `feat: add demo toy box page`.

### Task 9: Implement wardrobe items and sets — COMPLETE (static/automated)

**Files:**
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Wardrobe.lua`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py`

**Step 1: Add failing wardrobe assertions**

Require one main 外观 tab, two sub-tabs 物品/套装, 48 item records, 8 set records, class and slot filters, selected/uncollected visuals, item tooltips, one shared player preview model, and no transmog execution.

**Step 2: Implement the item sub-page**

Build an 18-item visible grid with pagination. On selection, reset the preview with `SetUnit("player")`, then `TryOn(itemId)`. Apply class and slot filters before pagination. Uncollected demo entries remain previewable.

**Step 3: Implement the set sub-page**

Build a pooled left list. On selection, reset the player model and call `TryOn` for each set item in stable equipment-slot order. Show the set-piece icon row and collected progress without offering save/apply/delete actions.

**Step 4: Add model controls and cleanup**

Support rotation, zoom if the 3.3.5 model API proves stable, reset view, and model clearing on page hide. Do not create 18 active model frames for item tiles; only the detail preview is 3D in Phase 1.

**Step 5: Verify behavior**

Run the contract suite and manually verify class switching, slot switching, all pages, set item order, player race/gender model, and repeated tab switches.

**Step 6: Record checkpoint**

Conditional commit message: `feat: add wardrobe item and set views`.

### Task 10: Implement the passive SC1 mod-ale bridge — IMPLEMENTED (static/automated PASS; hot-reload runtime ACK FAIL)

**Files:**
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Bridge.lua`
- Create: `F:\1_projects\wow_projects\mod-ale\lua_scripts\solo_collections.lua`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_bridge_contract.py`

**Step 1: Implement the client handshake**

On `PLAYER_LOGIN`, register prefix `SC1`, send `HELLO|1` to the player through an AddOn whisper, and start a short non-blocking timeout. On `HELLO_ACK|1|DEMO`, store bridge availability and feature bits. On timeout, set demo mode and stop retrying until the next login or `/sc reconnect`.

**Step 2: Implement the server responder**

Register mod-ale AddOn event 30. Accept only prefix `SC1`, the exact Phase 1 `HELLO|1` message, and the sender as the response receiver. Respond with `HELLO_ACK|1|DEMO` through `Player:SendAddonMessage`.

**Step 3: Enforce Phase 1 safety**

The Lua file must not import collection data, query databases, grant spells/items, cast spells, mutate money, call transmog code, or persist player state. Add a config constant at the top and return without responding when disabled.

**Step 4: Run bridge tests**

Run:

```powershell
python -m unittest F:\1_projects\wow_projects\tools\solo_collections\tests\test_bridge_contract.py -v
```

Expected: handshake and fallback contracts pass; prohibited mutation scan returns zero hits.

**Step 5: Record checkpoint**

If the `mod-ale` worktree is clean and commits are authorized, commit only the server Lua there with `feat: add SoloCollections demo handshake`; otherwise record its hash in the workspace checkpoint.

### Task 11: Add safe deployment and hash verification — COMPLETE

**Files:**
- Create: `F:\1_projects\wow_projects\tools\solo_collections\deploy_phase1.ps1`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\verify_phase1.ps1`
- Create: `F:\1_projects\wow_projects\tools\solo_collections\phase1_manifest.json`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_deployment_contract.py`

**Step 1: Write deployment safety tests**

Require resolved source/target paths, copying only the `SoloCollections` directory and one server Lua file, no recursive deletion, no wildcard target deletion, and a dry-run mode.

**Step 2: Implement dry-run deployment**

The script validates all absolute paths, builds a source manifest, prints create/update/unchanged operations, and performs no writes under `-WhatIf`.

**Step 3: Implement additive deployment**

Create the target AddOn directory if missing, copy source files with `Copy-Item -LiteralPath`, copy the server Lua to its exact target, and leave unrelated files untouched. Before overwriting an existing `SoloCollections` target, make a timestamped backup under `F:\1_projects\wow_projects\_work\solo_collections_phase1\backups`.

**Step 4: Verify source/live parity**

`verify_phase1.ps1` compares relative path, size, and SHA-256 for every AddOn file plus the server Lua, writes `phase1_manifest.json`, and fails on missing or mismatched files.

**Step 5: Run tests and dry-run**

Run:

```powershell
python -m unittest F:\1_projects\wow_projects\tools\solo_collections\tests\test_deployment_contract.py -v
& F:\1_projects\wow_projects\tools\solo_collections\deploy_phase1.ps1 -WhatIf
```

Expected: tests PASS; dry-run lists only `SoloCollections` and `solo_collections.lua` operations.

**Step 6: Deploy and verify**

Run the script without `-WhatIf`, then run `verify_phase1.ps1`. Expected: zero missing files and zero hash mismatches.

### Task 12: Complete automated and in-game acceptance — PARTIAL (63/63 automated PASS; UI NOT TESTED; SC1 hot-reload FAIL)

**Files:**
- Create: `F:\1_projects\wow_projects\_work\solo_collections_phase1\manual_acceptance.md`
- Create: `F:\1_projects\wow_projects\_work\solo_collections_phase1\verification_report.md`
- Modify: `F:\1_projects\wow_projects\docs\plans\2026-07-13-solo-collections-phase1-implementation.md`

**Step 1: Run the full automated suite**

Run:

```powershell
python -m unittest discover -s F:\1_projects\wow_projects\tools\solo_collections\tests -p "test_*.py" -v
```

Expected: all tests PASS.

**Step 2: Start the server with SC1 enabled**

Confirm the Lua loads without errors and the client bridge changes from waiting to demo-connected. Record relevant log lines without exposing credentials.

**Step 3: Complete the five-page manual pass**

Verify launcher drag/reset, open/close, four main tabs, two wardrobe sub-tabs, exact demo counts, search, filters, favorites, page transitions, empty states, real mount/pet models, wardrobe item/set TryOn, tooltips, and no action execution.

**Step 4: Complete compatibility passes**

Test with existing AddOns enabled; run `/reload`; relog; disable/remove server Lua and confirm client demo fallback; test 1024×768 and 1920×1080 or equivalent window sizes; inspect `FrameXML.log` and Lua error output.

**Step 5: Repair only failed acceptance items**

Add a regression test before each repair, apply the smallest fix, rerun the focused test, then rerun the full suite and the affected manual check.

**Step 6: Finalize evidence**

Write source/live hashes, test counts, verified model IDs, unverified limitations, backup path, live AddOn path, and live Lua path to `verification_report.md`. Mark implementation tasks complete only after automated checks pass and every manual item has an explicit PASS/FAIL/NOT TESTED state.

**Step 7: Conditional final commit**

If a valid workspace Git repository has been restored and the user authorized commits, commit with `feat: add SoloCollections phase 1 UI`. Otherwise preserve the final SHA-256 manifest as the delivery checkpoint and report that no commit was possible.

---

## Execution order and stop conditions

Execute Tasks 1–12 sequentially. Do not begin real collection persistence, item pickup unlocks, proxy spells, action-bar drag/drop, transmog application, or C++ module work. Stop and report if the 3.3.5 client cannot load the selected retail textures after compatible conversion, if verified creature IDs do not render through `SetCreature`, or if the AddOn message handshake conflicts with an existing prefix; in each case preserve the working AddOn shell and test evidence before changing architecture.
