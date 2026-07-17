# SoloCollections Mount Journal V3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the SoloCollections mount journal and bottom tabs to match the Retail CollectionsJournal while remaining executable on the 3.3.5 client.

**Architecture:** Keep the existing fixed catalogs and page router, replace the common journal chrome and mount page with 3.3.5-native controls, and extend the SC1 bridge for cache priming and server-validated summon requests. Retail artwork is flattened to standalone TGA media so no modern Atlas, ScrollBox, Mixin, or ModelScene API is required.

**Tech Stack:** WoW 3.3.5 FrameXML/Lua, FauxScrollFrameTemplate, PlayerModel, UIDropDownMenuTemplate, ALE/Eluna server Lua, Python unittest structural contracts, PowerShell deployment/hash verification.

---

### Task 1: Freeze V3 contracts and create a source backup

**Files:**
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_addon_contract.py`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_bridge_contract.py`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_media_contract.py`
- Create: `F:\1_projects\wow_projects\_work\solo_collections_v3\backups\<timestamp>\...`

**Step 1: Run the current baseline**

Run:

```powershell
python -m unittest discover -s F:\1_projects\wow_projects\tools\solo_collections\tests -p "test_*.py" -v
```

Expected: the existing suite passes before V3 edits.

**Step 2: Back up mutable sources**

Copy `插件\SoloCollections`, `mod-ale\lua_scripts\solo_collections.lua`, the live server Lua, and both installed AddOn directories into a timestamped V3 backup without deleting anything.

**Step 3: Add failing UI contracts**

Require the source to contain `FauxScrollFrameTemplate`, `FauxScrollFrame_Update`, `FauxScrollFrame_GetOffset`, `EnableMouseWheel`, right-click registration, `UIDropDownMenuTemplate`, `OnMouseWheel`, `SetCreature`, request-generation checking, four external bottom tabs, and no mount pagination controls.

**Step 4: Add failing bridge contracts**

Require `MODEL`, `MODEL_READY`, `SUMMON`, `SUMMON_RESULT`, strict numeric parsing, creature/spell allowlists, `PrimeCreatureQuery`, and a validated summon handler. Reject an implementation that casts a client-supplied spell before allowlist validation.

**Step 5: Run focused tests and verify failure**

Run:

```powershell
python -m unittest tools.solo_collections.tests.test_addon_contract tools.solo_collections.tests.test_bridge_contract -v
```

Expected: the new V3 assertions fail against the old implementation.

### Task 2: Add Retail-compatible standalone media and templates

**Files:**
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\Media\assets.json`
- Create/Modify: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Icons\launcher.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Icons\mount-journal-portrait.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Backgrounds\mount-journal-bg.tga`
- Create: `F:\1_projects\wow_projects\插件\SoloCollections\Media\Borders\mount-portrait-ring.tga`
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Templates.lua`

**Step 1: Locate the source artwork**

Use the local Retail UI source/CASC export tree to locate the Collections micro-menu icon, `MountJournalPortrait`, `MountJournal-BG`, search box segments, status bar segments, list selection/highlight, and panel-tab states. Record each provenance path in `assets.json`.

**Step 2: Export only required slices**

Flatten atlas regions to power-of-two TGA files with alpha. If an exact asset is already a directly loadable file, copy/convert it without redrawing.

**Step 3: Implement non-stretching templates**

Add or replace helpers with 3.3.5-safe APIs:

```lua
UI.CreateRetailSearchBox(parent, width, onTextChanged)
UI.CreateRetailProgressBar(parent, width)
UI.CreateRetailBottomTab(parent, label, onClick)
UI.CreateMountCount(parent)
UI.CreateMountListRow(parent, width, height, onSelect, onContext)
```

Search/progress/tab backgrounds must use left/middle/right textures or gradient regions, never a single bordered texture stretched across the full control.

**Step 4: Run media/template tests**

Run:

```powershell
python -m unittest tools.solo_collections.tests.test_media_contract -v
```

Expected: all files exist and no modern API token is present.

### Task 3: Rebuild the journal shell and external bottom tabs

**Files:**
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\UI\CollectionsFrame.lua`
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Launcher.lua`

**Step 1: Change the logical frame geometry**

Set the main frame to `920×793`, create a dark metal header/body, and place the circular mount portrait partially outside the top-left corner. Keep dragging, responsive scale, saved position, close handling, and `UISpecialFrames` support.

**Step 2: Build the page-aware header**

For mounts, show the circular portrait, mount-count capsule and centered progress bar. Keep shared search/filter controls but place them in the mount left inset. Other pages retain functional fallback placement until their later redesign.

**Step 3: Anchor tabs outside the frame**

Create four tabs under `frame`, anchor the first with its top edge at the frame bottom and subsequent tabs to the previous tab. `SetSelected(true)` shows a gold gradient and connection glow; unselected tabs use dark metal.

**Step 4: Replace the launcher art**

Use the standalone Retail Collections micro-menu texture while preserving drag, saved position, tooltip and left-click toggle.

**Step 5: Run shell contracts**

Expected: V3 frame/tab/launcher assertions pass while mount-list assertions remain failing.

### Task 4: Replace mount pagination with a Retail-style scroll list and context menu

**Files:**
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Catalog.lua`
- Rewrite: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Mounts.lua`

**Step 1: Add an unpaged query route**

Provide a stable filtered/sorted result list for scroll consumers without changing the paged behavior used by toys, pets and wardrobe.

**Step 2: Build the FauxScrollFrame list**

Pool eight mount rows. On refresh:

```lua
local offset = FauxScrollFrame_GetOffset(scrollFrame)
local record = records[offset + rowIndex]
FauxScrollFrame_Update(scrollFrame, #records, VISIBLE_ROWS, ROW_HEIGHT)
```

Enable the wheel and forward it through `FauxScrollFrame_OnVerticalScroll`. Remove mount page controls and page-number state.

**Step 3: Implement row interactions**

Left-click selects. Right-click row or icon opens a `UIDropDownMenuTemplate` menu containing summon and set/cancel favorite. Disable summon for uncollected records or when the bridge is unavailable.

**Step 4: Preserve filters and selection**

Search/filter changes keep the selected record when it remains visible; otherwise select the first result. Empty results clear the detail and model.

**Step 5: Run focused UI tests**

Expected: scroll/no-pagination/context-menu contracts pass.

### Task 5: Make the mount detail and model preview reliable

**Files:**
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\UI\Mounts.lua`
- Modify: `F:\1_projects\wow_projects\插件\SoloCollections\Core\Bridge.lua`

**Step 1: Build the official information hierarchy**

Place a clickable 38px icon and mount name at the detail top, followed by source, description and collection state. Put the model behind that overlay and keep a reset-view button near the bottom edge.

**Step 2: Add request-based model priming**

Expose:

```lua
SC.Bridge.RequestModel(mountId, callback)
SC.Bridge.SummonMount(mountId, callback)
```

Each request uses an increasing ID and a timeout. The server maps `mountId` to creature/spell IDs; dispatch responses only when both request ID and mount ID match.

**Step 3: Apply the model after readiness**

On `MODEL_READY`, defer one frame, then call `ClearModel`, `SetCreature`, `SetCamera(0)`, `SetModelScale`, `SetPosition`, and `SetRotation`. If `GetModel()` is empty, retry after 0.1/0.25/0.5 seconds and then show the fallback label.

**Step 4: Implement interaction**

Scale cursor deltas by `UIParent:GetEffectiveScale()` during drag. Clamp wheel zoom to `0.35..2.5`. Reset restores rotation, scale, position and camera.

**Step 5: Run bridge/UI tests**

Expected: generation checks, retry schedule, drag, zoom and reset assertions pass.

### Task 6: Extend the ALE server Lua with validated model and summon operations

**Files:**
- Modify: `F:\1_projects\wow_projects\mod-ale\lua_scripts\solo_collections.lua`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\tests\test_bridge_contract.py`

**Step 1: Generate explicit allowlists from the fixed catalog**

Add a mount ID map containing creature ID, spell ID and collected state for exactly the records present in `Data\Mounts.lua`. Do not accept creature/spell IDs from AddOn messages.

**Step 2: Implement MODEL**

Validate `requestId` and `mountId`, resolve the allowlisted creature ID, call `sender:PrimeCreatureQuery(creatureId)`, and return `MODEL_READY|requestId|mountId` to the same sender.

**Step 3: Implement SUMMON**

Validate `requestId`, mount allowlist and fixed collected state. Reject death, combat, vehicle or flying state. Dismount an existing mount when appropriate, call `sender:CastSpell(sender, spellId, false)` only with the server-resolved spell, and return `SUMMON_RESULT|requestId|ACCEPTED|mountId`; do not claim confirmed spell success because the binding does not return `SpellCastResult`.

**Step 4: Verify server Lua syntax/API usage**

Use the configured Lua compiler/interpreter if available and compare the method signatures with existing local mod-ale scripts before deployment.

**Step 5: Run bridge contracts**

Expected: strict validation and message-response tests pass with zero arbitrary-cast paths.

### Task 7: Full verification, deployment and runtime handoff

**Files:**
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\deploy_phase1.ps1`
- Modify: `F:\1_projects\wow_projects\tools\solo_collections\verify_phase1.ps1`
- Create: `F:\1_projects\wow_projects\_work\solo_collections_v3\verification_report.md`

**Step 1: Run the full automated suite**

Run:

```powershell
python -m unittest discover -s F:\1_projects\wow_projects\tools\solo_collections\tests -p "test_*.py" -v
```

Expected: all tests pass.

**Step 2: Deploy additively**

Back up and copy the source AddOn to:

```text
D:\Games\wow335\world of warcraft 3.3.5a hd\Interface\AddOns\SoloCollections
D:\Games\wow335\World of Warcraft11\Interface\AddOns\SoloCollections
```

Copy the server Lua to `D:\AzerothCore_NPCBots_Clean\lua_scripts\solo_collections.lua`. Do not delete unrelated files.

**Step 3: Verify hashes**

Compare every source/deployed relative path, size and SHA-256. Expected: zero missing and zero mismatch.

**Step 4: Restart worldserver if required**

Use the existing local restart procedure, then inspect logs for server Lua registration errors and SC1 message-handler errors.

**Step 5: Write the verification report**

Record test count, backup path, source/live hashes, server restart status, automated PASS/FAIL, and manual checks still requiring the game client.

**Step 6: Manual acceptance handoff**

Ask the user to `/reload`, open the journal, select several mounts, rotate/zoom, right-click summon, and provide one screenshot plus any Lua error text. Treat that screenshot as the final visual acceptance gate.

---

## Execution notes

- The workspace has no valid Git repository; replace commit checkpoints with timestamped backups and SHA-256 manifests.
- Use `subagent-driven-development` in this session: implement each task sequentially, then perform specification and quality reviews before advancing.
- Do not redesign the pets, toys or wardrobe page bodies in this V3 pass.
- Stop deployment if the full automated suite fails or if server Lua syntax/API validation cannot be completed.
