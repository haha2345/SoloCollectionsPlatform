# Cooldown Manager — Port Plan (Build Contract)

Downport of `ReferenceAddons/NewEra/CooldownViewer/` + `CooldownViewerSettings/` (Classic 1.15 /
TBC 2.5.x) onto 3.3.5a. Read `CONTRACTS.md` §0 first — every global convention there applies.

**Status: the port is complete.** Phases 0-4a, 4b-1 through 4b-5, 4c (the Settings tab), 5a (on-use
trinkets), 6 (loose ends), 7 (the tracked-aura catalog), 8 (the art) and 9 (the guide audit) are
implemented — the whole of both phasing tables except the deliberate cuts. Offline harnesses pass
(`qa/offline/`, 635 boot assertions). Phases 1-3 and the 4b-1 window shell are confirmed working
in-game; 4b-2 and 4b-3 are confirmed in-game (three faults found and fixed, §G.7.1/§G.7.2).

**Phase 8 is DONE** (§H.2), one item at a time: **8a** registered six atlases the viewers had been
setting by name and that existed nowhere, so every one rendered as an invisible texture — which is why
the icons looked like bare spellbook icons. **8c** lights a spell's frame gold while its own buff is
up, closing the last headline feature the retail guide lists and we did not have. **8d** is the bar
3-slice and **8e** the pandemic ring. **8b** — the gold cooldown swipe — was measured, attempted and
declined (§H.2.11): the ClassicAPI capture rig it needs is unexercised code that costs ~200 frames and
takes our countdown numbers out with it, for a capability 8c already substitutes for.

**Phase 9 is DONE** (§H.3): every feature the retail guide describes now has a verdict. Two of its
three open items had already been paid for by earlier phases — the buffed-spell glow by 8c, and target
DoT timers by Phase 7, which is what made `ScanTargetTrackedAuras` reachable at all. The third was
the "Not Displayed" rename, which is the only code Phase 9 shipped.

Phase 7 is **DONE** (§H.1, notes in §H.1.1): the Tracked Buffs tab now has two real sources — a
generated per-class catalog gated on the player's actual talents, and a registry of auras the scan has
met.

Also outstanding: consumables (§G.9, parked as a stretch goal by the owner — blocked on a generator
pass, not on effort), and three items needing the game rather than the harness — §F4 taint under a
combat restack, §F5's four-movers-versus-one call, and an in-game pass over 4b-4, 4b-5, 5a and 4c. See
the end of §G.13.

---

## A. What the source actually is

Retail's Cooldown Manager is `C_CooldownViewer` / `C_CooldownViewerSettings` — client-side C++ added
in 11.0 (TWW). That API does **not** exist on 3.3.5a, and it does not exist on Classic Era or TBC
Classic either: `C_CooldownViewer.IsCooldownViewerAvailable()` returns false there.

So NewEra never ported Blizzard's Lua. It built a **visual port with a custom data driver** — retail's
frame stack (icon viewers, cooldown swipe, GCD flash, out-of-range shadow) fed by hand-curated
per-class spell lists plus live `GetSpellCooldown` / `UNIT_AURA` / `GetInventoryItemCooldown` reads.
The source header states this explicitly (`CooldownViewer.lua:1-17`).

**This is the single most important fact for planning:** the hard part — inventing a cooldown data
model for a client with no spec system and no curated cooldown sets — is already solved and shipped.
`CdmSeedTBC.lua` is a working precedent for layering one flavour's data on top of the vanilla base,
which is exactly the shape WotLK needs. Our work is the **platform gap**, not the design.

Size: **5,444 lines** across 12 files in `CooldownViewer/`, plus **2,139 lines** in
`CooldownViewerSettings/`.

| File | Lines | Ports as-is? |
|---|---|---|
| `CooldownViewer.lua` | 1,715 | mostly — `getOpt` retarget + `RegisterUnitEvent` |
| `ItemMixins.lua` | 1,289 | mostly — mask + swipe strip |
| `Alerts.lua` | 520 | partial — pandemic FX unportable (§E6) |
| `ClassData.lua` | 392 | yes (vanilla base) |
| `SoundAlertData.lua` | 349 | partial — kit IDs inert, ships extracted OGGs (§E6) |
| `EditModeRegister.lua` | 213 | **no — replace wholesale** |
| `CooldownViewerEquip.lua` | 182 | yes |
| `CdmSeedTBC.lua` | 131 | template for a new WotLK seed |
| `AlertData.lua` | 100 | regenerated for WotLK, not copied (§E6) |
| `RacialsTBC.lua` | 55 | template |
| `Assets.lua` | 50 | partial (swipe art unused in v1) |
| `CooldownViewer.xml` | 448 | needs `MaskTexture` + `GridLayoutFrame` surgery |

---

## B. Architect decisions (locked — flag before deviating)

### B1. No Edit Mode. Movers + options tab instead.

`EditModeRegister.lua` is written against `NE.editmode` — a **6,441-line retail Edit Mode
reimplementation** (`ReferenceAddons/NewEra/EditMode/`) that this addon does not have and will not
port. It uses `EM.Register` with a full settings codec (`system` / `systemIndex` / `defaultSettings` /
`settings` / `options`), `EM.GetFrameSettingStored`, `EM.const.StoredToDisplay`,
`EM.RegisterBottomManaged`, `EM.UpdateBottomManagedFrames`, `EM.RegisterToggleableFrames`,
`EM.ShouldShowActivity`, `EM.RepositionHandle`, `EM.AtLogin`.

DragonUI's equivalent is **position-only**: `core/movers.lua` is a drag handle that persists a point
string; `modules/editor_mode.lua` adds a grid overlay and a reset button. No per-frame settings popup,
no options metadata, no bottom-managed stack, no settings codec. **DragonUI is read-only** (CONTRACTS
§0) so we cannot extend it.

> **CORRECTION — found on the first in-game test, after this section was written.** DragonUI has
> **two independent** positioning systems and only one is what `/dui edit` drives:
>
> | system | registered via | shown by |
> |---|---|---|
> | `addon.MoversSystem` (`core/movers.lua`) | `NE.RegisterPanel` | **nothing** — `ToggleConfigMode` sits behind a dead `elseif` in `core/commands.lua:31`; `addon.EditorMode` always exists and wins the first branch |
> | `addon.EditableFrames` (`core/api.lua:551`) | `addon:RegisterEditableFrame` | `/dui edit` → `EditorMode:Show` → `addon:ShowAllEditableFrames` |
>
> An always-on HUD frame MUST use the second, or it registers cleanly and is then silently never
> shown. `NE.RegisterHUDFrame` (integration/Register.lua) is the seam; `NE.RegisterPanel` stays
> correct for toggled WINDOWS, where a MoversSystem handle is fine.
>
> **And `RegisterEditableFrame` alone is not enough** — it only records metadata. The drag
> affordances (`RegisterForDrag`, `OnDragStart`/`OnDragStop` with its auto-save, the green nineslice
> overlay, the label) are attached by DragonUI's frame FACTORY, `addon.CreateUIFrame`
> (`core/api.lua:255`). `addon.HideUIFrame`, which the editor calls on each registered frame, only
> does `SetMovable(true)` / `EnableMouse(true)` and shows an overlay a plain `CreateFrame` does not
> have. So the required pattern — the one `modules/castbar.lua` uses with `CastbarModule.anchor` —
> is: build a `CreateUIFrame` **anchor**, register the ANCHOR, and pin the real content to it.
> `NE.RegisterHUDFrame` does this and keeps the anchor's size synced to the content via
> `OnSizeChanged`.
>
> Two further gotchas found with it: DragonUI's `ApplyUIFramePosition` reads `x`/`y` gated on an
> `override` flag that nothing sets, while `SaveUIFramePosition` writes `anchor`/`posX`/`posY` —
> they do not round-trip, so position restore is ours. And registration must happen at
> `PLAYER_LOGIN`, not file load, matching every other NewEra module.

**Decision:** delete `EditModeRegister.lua`. Replace with:
- one DragonUI mover per viewer, via the existing `NE.RegisterPanel` path in `integration/Register.lua`
- the ten settings rendered in the DragonUI_Options "New Era" tab

`getOpt` (`CooldownViewer.lua:141`) is the single chokepoint every setting reads through, so
retargeting it at our own DB table is a contained change. The whole `M.CDV_CODEC` retail-int mapping
(`CooldownViewer.lua:126-139`) and the `sliderToStored` / `StoredToDisplay` conversions go away —
we store display values directly.

Cost: ~300 lines of new glue instead of 6,441 lines of ported Edit Mode.

**Note on precedent:** `modules/character/EditModeRegister.lua` declines Edit Mode on the grounds
that it is "scoped to always-on HUD frames, NOT toggled windows." The Cooldown Manager *is* a
persistent HUD frame — it is the first module that rule would say *should* have one. We are declining
anyway, because the cost is the entire Edit Mode system and DragonUI's movers cover the actual need
(position + scale). Revisit only if per-viewer settings prove unusable in the options tab.

### B2. Four independent frames, not a combined group.

Follow the source's current SPLIT model (`CooldownViewer.lua:240-245`): Essential / Utility /
BuffIcon / BuffBar are four independently positioned frames. The older combined-container approach is
already reverted upstream; do not resurrect it. Default anchors (BOTTOM of UIParent):
Utility y=240, Essential y=310, BuffIcon y=370, BuffBar x=420 y=430.

### B3. No bottom-managed stacking.

`EM.RegisterBottomManaged` reflows the viewers above the action-bar tower as bars are added. There is
no DragonUI equivalent. Viewers sit where the user puts them. Drop the `OnSizeChanged` restack hook
(`EditModeRegister.lua:159-164`) with it.

---

## C. Platform gaps (verified against ClassicAPI + DragonUI, 2026-07-25)

### C1. `GridLayoutFrame` — MISSING, must build

All four viewer frames inherit it (`CooldownViewer.xml:348,374,400,427`). The layout code depends on
`:Layout()`, `layoutIndex`, `stride`, `childXPadding`/`childYPadding`, `layoutFramesGoingRight`,
`layoutFramesGoingUp`, `alwaysUpdateLayout`, `ignoreInLayout`, `ResizeLayout`.

ClassicAPI ships `AnchorUtil.CreateGridLayout` / `GridLayoutMixin` **helpers** (`Util/AnchorUtil.lua:49-101`)
but **not** the `GridLayoutFrame` XML template. Grep confirms the only occurrence of the string in the
whole AddOns tree is the NewEra source XML itself.

→ Write `core/GridLayout.lua` (~150 lines) implementing LayoutFrame / GridLayoutFrame mixin semantics,
applied in Lua at frame creation rather than via XML `inherits`. Reusable by any future HUD module.

### C2. `<MaskTexture>` — MISSING, cannot polyfill

Used in all four item templates for the rounded icon mask (`CooldownViewer.xml:56,134,208,279`).
MaskTexture is a Legion widget. It does not exist on 3.3.5a, no polyfill is possible in Lua, and an
unknown XML node risks failing the entire file's parse. CONTRACTS §0 already lists `SetMask` as a hard
rule, and `qa/staticcheck.sh` greps for it.

→ Drop the mask. Keep the `iconoverlay` art layered on top, crop the icon with `SetTexCoord`
(~0.07–0.93). `core/ButtonSkin.lua` already establishes this pattern.

### C3. `Cooldown:SetSwipeTexture` / `SetEdgeTexture` / `SetUseCircularEdge` — MISSING

WoD+ APIs, called at `ItemMixins.lua:70-71,917-918`. ClassicAPI's `Util/Cooldown.lua` is a private
quadrant-based `CooldownCapture` renderer reached through `Private`, **not** a widget-method polyfill —
it exports nothing that satisfies these calls.

→ Accept the engine's built-in sweep. Guard the calls (`if self.Cooldown.SetSwipeTexture then`) — the
source already does at line 70. The DF swipe/edge art registered in `Assets.lua` (FDIDs 6731092,
5423465) goes unused in v1. Cosmetic only.

**Unverified:** whether 3.3.5a's Cooldown widget has `SetDrawEdge`. ClassicAPI's `CooldownFrame_Set`
calls it unconditionally (`Util/Cooldown.lua:12`). Confirm before relying on it.

### C4. `self:RegisterUnitEvent(...)` — MISSING as a widget method

Called throughout the viewer `OnLoad`s (`CooldownViewer.lua:307-324`, `1321`). ClassicAPI provides
`EventHandler.RegisterUnitEvent(Object, Event, ...)` as a **namespaced function**
(`Util/EventHandler.lua:189`, exported at `:270`), not a method on the frame metatable.

→ Small shim in `compat/Compat.lua` adding the method to a frame, delegating to the ClassicAPI
dispatcher. Cheap and reusable.

### C5. `CooldownFlash` flipbook — ALREADY SOLVED

Good news: `ItemMixins.lua:463` implements the flipbook as a hand-rolled OnUpdate texcoord stepper,
written precisely because Era lacked retail's animation system. Ports as-is.

### C6. Present and usable

`NE.tex` / `RegisterLocal` / `SetAtlas` (`core/Texture.lua`), `NE.FrameUtil.PinPixelPerfect`,
`NE.Log`, `NE.flavor`, `CreateFromMixins` (ClassicAPI `Util/Mixin.lua`), `C_Timer`, `C_Item`,
`C_Container`. The settings panel builds on `ButtonFrameTemplate`, which ClassicAPI provides
(`Templates/UIPanelTemplates.xml`).

### C7. Missing NewEra helpers — small substitutions

| Symbol | Used for | Substitution |
|---|---|---|
| `NE.EV_LEARNED_SPELL` | learn-spell event name | one-line const, `LEARNED_SPELL_IN_TAB` |
| `NE.spellbook.SPELLID` | rank expansion (`CdmSeedTBC.lua:95-109`) | build by scanning the spellbook at login — do **not** ship a db2 dump |
| `NE.actionbar1.procglow` | proc/activation glow (`CooldownViewer.lua:1026-1028`) | LibCustomGlow (already embedded, see `modules/spellbook/Spellbook.lua`) + 3.3.5a's `IsSpellOverlayed` / `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` |
| `NE_CDM_HIDDEN` | generated all-cooldowns superset | optional — code fails open (`CooldownViewer.lua:622`) |
| `NE_SPELL_RACEMASK` | race-gating (`CooldownViewer.lua:654`) | optional — fails open by design |

---

## D. Data work (WotLK)

The engineering above is bounded; **this is the main authoring cost.**

`CdmSeedTBC.lua` (131 lines) + `RacialsTBC.lua` (55) are the templates. Both are flavour-guarded
(`if not (NE and NE.flavor == "tbc") then return end`) and purely additive over the vanilla
`ClassData.lua` base. A `CdmSeedWotLK.lua` follows the identical shape.

Needed:
- **Death Knight in full** — absent from every table; new class in 3.3.5a.
- **WotLK additions for the other nine.** Non-exhaustive: Warrior Bladestorm/Shockwave; Paladin
  Divine Storm/Hand of Protection-Freedom-Sacrifice; Hunter Explosive Shot/Call of the Wild; Rogue
  Fan of Knives/Killing Spree/Shadow Dance; Priest Penance/Dispersion/Hymn of Hope; Mage Deep
  Freeze/Mirror Image/Living Bomb; Warlock Metamorphosis/Haunt/Demonic Circle; Shaman Feral
  Spirit/Thunderstorm/Riptide; Druid Starfall/Berserk/Wild Growth/Survival Instincts.
- **Buff-viewer seed.** Per `CdmSeedTBC.lua:83-89`, seed only *permanent state toggles* (armors,
  aspects, forms, shields) as `icon`. The ≤120s auto-window (`BUFF_TRACK_MAX_DURATION`,
  `CooldownViewer.lua:1115`) handles short procs. Do **not** seed long maintenance buffs — upstream
  removed those as clutter.

**Sourcing rule (CLAUDE.md prime directive, restated in `CdmSeedTBC.lua:21-26`):** every spellID must
come from the 3.3.5a client data, not memory. Store one representative rank per ability; the runtime
rank resolver (`highestKnownRankID`) picks the learned rank live.

---

## E. Phasing

| Phase | Scope | Exit criterion |
|---|---|---|
| **0** | `core/GridLayout.lua`; `RegisterUnitEvent` shim; `EV_LEARNED_SPELL`; spellbook rank table. No CDM code. | A throwaway grid of 12 test frames lays out, wraps at stride, and reflows on padding change. |
| **1** | Essential + Utility viewers. Mask and swipe stripped. One mover each. Settings in options tab. | Icons appear, swipe on cast, timer counts down, `/dnetest` PASS. The "does it feel right" checkpoint. |
| **2** | `CdmSeedWotLK.lua` + `RacialsWotLK.lua` + Death Knight. | Every class shows a sensible default set at 80. |
| **3** | ~~BuffIcon + BuffBar (aura-driven; more moving parts).~~ **DONE** — see §E2. | Buff bars track, auto-window catches procs, no empty-row churn. |
| **4a** | `Alerts.lua` + `SoundAlertData.lua` + `AlertData.lua` — the ENGINE and its stores. **DONE** — see §E6. | Assigning an alert or sound programmatically makes it fire. |
| **4b** | The `CooldownViewerSettings/` panel: spell picker, per-spell alert/sound assignment, drag reorder, presets. Re-scoped in §E6. | Alerts, sounds and spell visibility are all settable from the UI. |

Phases 1 and 2 are the shippable unit. Phase 3 onward is optional polish.

---

## E1. Implementation notes (added after building Phases 0–1)

Three things the scope did not anticipate, all resolved:

1. **`GetSpellInfo` position 7 is `castTime` on 3.3.5a, not `spellID`.** The WotLK signature is
   `name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange` (confirmed by
   `!!!ClassicAPI/Util/C_Spell.lua:39`). The source's `highestKnownRankID` is built entirely on
   `select(7, GetSpellInfo(name))`, so ported verbatim it would return e.g. `1500` for a 1.5s cast
   and use it as a spell ID — silently, since that is a plausible-looking number. This promoted
   `core/SpellRanks.lua` from a convenience to **load-bearing**: it is the only correct source of
   "highest rank the player knows" on this client.

2. **`RegisterUnitEvent` could not be delegated.** !!!ClassicAPI implements the semantics
   (`Util/EventHandler.lua:189`) but only inside its `Private` namespace — never exported — so
   `compat/Events.lua` implements it on the Frame metatable instead (RegisterEvent + a per-frame
   allow-set enforced by wrapping that frame's OnEvent).

3. **`Rebuild → RefreshLayout → UpdateVisibility → Show → OnShow → Rebuild` is a re-entrancy
   cycle.** The client only fires `OnShow` on a hidden→shown transition, so it settles at depth two
   rather than recursing forever — but that is an implicit dependency on client behaviour. Guarded
   explicitly in `Viewers.lua:Rebuild`.

Also deferred deliberately in Phase 1: `CooldownViewerEquip.lua` (trinket/potion discovery) is
stubbed to return empty, with the consuming loop left in place so the Phase 2 port drops in.

## E2. Phase 3 notes (aura viewers)

Built out of order, ahead of Phase 2, because the buff viewers need **no class data**: they read
live auras, not curated cooldown lists. Three parts:

- `AuraItemMixins.lua` — the BuffIcon tile (reverse swipe = aura elapsed, stack count, dispel
  border) and the BuffBar row (depleting StatusBar + pip, driven by a per-frame OnUpdate off cached
  expiration/duration rather than a per-frame aura scan).
- `BuffViewers.lua` — both viewer frames plus the shared aura-scan rebuild.
- Tracked-aura pool in `CooldownViewer.lua` — ONE pool as retail models it: each aura is `icon`,
  `bar` or `hidden`, so a bar-assigned aura never also renders as an icon.

Model: any player buff with `0 < duration <= 120s` auto-tracks, which is what makes trinket, potion
and proc buffs work without enumerating them. Longer buffs and permanent toggles are excluded, so
the viewers stay quiet out of combat. Explicit assignments override the window in both directions.
Target auras are a secondary source for EXPLICITLY tracked entries only — never the auto window,
which would flood the viewer with every enemy debuff.

**The trap worth naming:** the 1.15 source scans with
`local name, icon, count, _, duration, expiration, _, _, _, spellID = UnitBuff("player", i)` — the
MODERN return layout. On 3.3.5a `rank` occupies index 2 and shifts everything after it, so ported
verbatim `icon` receives the rank string and `duration` the caster. All scanning here goes through
`NE.aura` (core/AuraSnapshot.lua), which owns the correction in one place. `test_boot.lua` asserts
the icon comes from index 3 specifically, as a regression guard.

Two stride subtleties preserved from upstream, both of which otherwise wrap the stack into a
phantom extra column: `GetStride` counts LAYOUT children (has `layoutIndex`, not `ignoreInLayout`)
rather than SHOWN ones, and `BuffBarItem:UpdateShownState` keeps `ignoreInLayout` mirroring
visibility.

## E3. Phase 2 notes (WotLK data)

131 abilities across all ten classes, including the whole of Death Knight (9 Essential, 15 Utility)
which had no vanilla base at all. Additive appends onto `ClassData.lua`, same shape as
`CdmSeedTBC.lua`.

**Every ID is generated from this client's own data, not typed from memory** — see
`tools/cdm-spellgen/`. `Spell.dbc` and `SkillLineAbility.dbc` are extracted from the locale MPQs
(`Data/enUS/`, not the base archives), spells are attributed to classes via each skill line's
ClassMask, and each authored ability NAME resolves to the rank-1 castable ID. "Castable" is defined
as the lowest-rank, lowest-ID entry carrying a real cooldown (> 1.5s) — which is what separates an
ability from its triggered sub-spells: Penance resolves to 47540, not its 47666/47750 heal and
damage triggers; Death Grip to 49576, not 49560/49575.

Only the curation is hand-authored: which ability is Essential vs Utility. An unresolvable name is
a hard error rather than a silent omission, and `verify.py` independently re-reads the DBC to assert
every emitted ID exists, matches its comment, has a cooldown, is rank 1, and is unique. That gate
caught three entries that had no business in a pressable-cooldown list — Immolation Aura and Demon
Charge (rank `Demon`, Metamorphosis-form only) and Reincarnation (rank `Passive`).

Column positions were located empirically rather than assumed: `Spell.dbc` name 136, rank 153,
RecoveryTime 29, CategoryRecoveryTime 30 (cooldown is the max of the last two). An early attempt to
find the cooldown column by matching remembered durations failed outright — a small reminder of why
the sourcing rule exists.

**Known gap:** `Data/patch-4.MPQ` and `Data/patch-S.mpq` are encrypted and unreadable. If the server
overrides spell data there, these IDs reflect the stock client. Repeated in the generated file's
header.

## E4. Learn-gate fix (after first in-game test of Phases 2-3)

Reported: a Disc priest's **Penance** and a Holy priest's **Guardian Spirit** never appeared despite
both talents being taken, and **Divine Hymn** never appeared on a level-squished server where the
character knows it at 60. All three are one fault — the learn-gate, not the data.

The source checks `IsSpellKnown(spellID)` then falls back to `GetSpellInfo(name)`. Both fail here:

- `IsSpellKnown(id)` tests **one exact rank**. Our curated lists key each ability by its rank-1 id,
  so the check goes false the moment the player trains rank 2 — which is most talent abilities.
- `GetSpellInfo(name)` is a spell-database lookup on this client, not a membership test.
- Neither consults the spellbook, and neither is level-aware — which matters on a squished server.

Fixed by asking the **spellbook, by name** (`SB.IsSpellNameKnown`, core/SpellRanks.lua). That is
authoritative, rank-agnostic and level-agnostic. The name set is built from `GetSpellBookItemName`
alone — deliberately without id resolution — so an entry whose `GetSpellLink` can't be parsed still
counts as known. The old checks remain as fallbacks, so the change can only widen what shows.

Two supporting changes: the rank table now builds lazily on first use (viewers rebuild on
`PLAYER_ENTERING_WORLD`, which can precede the deferred `SPELLS_CHANGED` build), and
`SB.OnRebuilt` lets the viewers re-source after training or a spec switch.

`/necdm` prints the gate's decision per curated spell — book / IsSpellKnown / byName — so the next
report of a missing icon doesn't need guesswork.

## E5. Custom-list shadowing (the second half of the "missing abilities" report)

The learn-gate fix in §E4 was necessary but not sufficient. `/necdm` then showed the real fault:

```
hidden Holy Fire  id=14914  book=true  IsSpellKnown=true  byName=true
```

Every check passing, still hidden — so the gate was never the filter. `10 curated, 3 shown` was the
tell.

`M.GetItemMeta` is a read-only query, called from `ItemMixins:SetSpell` for **every icon on every
rebuild** — and it called `GetEditableList`, which SEEDS AND PERSISTS a custom list from the curated
defaults. So the first time any viewer built, it froze the then-current spell list into
SavedVariables; `GetActiveSpellList` took the `custom` branch from then on and ignored the curated
tables permanently. Every ability added later — the entire WotLK seed — was invisible on any
character that had run an earlier build.

Fixes:
1. `GetItemMeta` now uses `GetCustomList` (read-only). **A query must never pin persistent state.**
2. `M.MigrateStaleCustomLists`, versioned and run once at boot, clears lists that were never
   deliberately authored. Until the Phase 4 picker exists there is no way to author one, so every
   stored list is an artifact and clearing it loses nothing the user chose.
3. `/necdm` now reports when a custom list is shadowing the curated table. Its absence from the
   first version is exactly why this took two rounds to find.

Upstream carries the same guarded one-time reset, for the same reason — its boot block notes a
stale snapshot was "hiding the new defaults". That block was dropped along with
`EditModeRegister.lua`; this restores its intent.

## E6. Phase 4a notes (alerts, sounds, and the assignment menu)

§F2 asked for a re-scope before committing. Doing it changed the shape of the phase.

**What did not port: the pandemic border FX** (~130 of `Alerts.lua`'s 520 lines). Upstream renders
the `refresh` alert with a 1:1 port of retail's `CooldownPandemicFXTemplate` — a ring plus three
cascading glows, every one clipped to the ring by a `MaskTexture`. Two independent blockers:

- MaskTexture is not merely missing here. ClassicAPI defines `CreateMaskTexture` / `AddMaskTexture`
  as `Private.Void` ("potentially impossible to implement", `WidgetAPI.lua:279/302/476`) and Cell's
  polyfill returns an inert dummy. The calls would *succeed and clip nothing*, leaving three
  full-quad glows scaling to 1.5x as square smears across the icon and its neighbours — worse than
  no FX, and silently so.
- `Animation:SetTarget` does not exist on 3.3.5a either (zero occurrences in the whole AddOns tree).
  Animations act on the region owning the AnimationGroup, so one-group-drives-three-textures has no
  equivalent.

The atlases are absent too. So `refresh` renders through LibCustomGlow — already embedded, already
in the TOC, and what §C7 nominated for the proc-glow substitution — tinted pandemic-orange to keep
the one legible part of the retail look.

**What the sound port actually required.** Upstream's fallback path, `PlaySound(kit)`, is *dead* on
3.3.5a: this client's `PlaySound` takes a name string, and `PlaySoundKitID` takes a 3.3.5a kit index,
not a six-digit TWW id. Nothing retail-numbered can make a sound. The only working route is playing
audio by file path, so the 67 OGGs upstream extracted are shipped in `Sounds/cdm/` and played with
`PlaySoundFile` (`.ogg` is fine here — DBM has shipped them on this client for years). The retail kit
id survives purely as the stable assignment key. The whole `Short` category (26 entries) is dropped:
upstream never had extractable audio for it, so here it could only ever be 26 menu entries that play
nothing.

**`AlertData.lua` is regenerated, not copied.** Upstream's tables are vanilla-only. WotLK adds Kill
Shot (a genuine third execute ability) and Victory Rush, and *removes* Mongoose Bite's dodge gate in
3.1.0 — listing it would flash the icon every time it came up, the exact behaviour the data gate
exists to prevent. `tools/cdm-spellgen/gen_alertdata.py` resolves every rank from the client DBCs.
Two impostor classes had to be filtered, both found by inspecting output rather than by assumption:

- Rank text cannot discriminate. 3.3.5a gives Overpower rank 1 (7384) an **empty** rank string while
  its ranks 2-4 are labelled — and those higher ranks appear in no skill line at all, so Overpower is
  single-rank on this client. A "keep the ranked rows" filter drops the real ability and keeps four
  NPC copies of Riposte.
- `SkillLineAbility` class attribution fixes both. Applied *first*, the "drop unranked siblings" rule
  then safely removes triggered sub-spells like Execute's damage component (20647).

**The bug the harness caught: preferences were keyed on a moving id.** `ItemMixin.spellID` holds the
*learned rank*, not the listed one — Mind Blast's tile reports 10947, not the curated 8092. Keying
alerts and sounds on it would have silently orphaned every assignment the moment the player trained
the next rank. `_baseSpellID` / `GetSettingsKey()` now carries the stable id, and the harness asserts
the two differ. This is the same rank gotcha the cooldown path already documents, resurfacing in a
new place.

**The assignment surface was tried as a right-click menu, and removed.** Alerts and sounds are
strictly opt-in per spell, so 4a otherwise ships dormant. `ItemMenu.lua` put the choices on the icon
itself. It did not open in-game, and rather than debug a surface the Phase 4b panel replaces, the
owner called it: delete it and do assignment in the settings panel. So the ENGINE and its stores
ship here and nothing drives them yet — the options tab says so rather than advertising a way in
that does not exist.

`M.SetSpellEnabled` / `M.IsSpellEnabled` survive that removal and are the panel's seam for showing
and hiding a spell. `SetSpellEnabled` is the only caller of `GetEditableList`, which is the point of
the §E5 fix: seeding a custom list is correct exactly when the user has just chosen something.

**Phase 4b, re-scoped.** `CooldownViewerSettings/` is 2,139 lines across six files, and its retail
dependencies are heavier than §F3 assumed: `MenuUtil` (absent), `GLOBAL_MOUSE_UP` (retail 9.x,
absent — `Reorder.lua` is built entirely on it), `LargeSideTabButtonTemplate` (absent), clipboard
export (no `CopyToClipboard` on 3.3.5a), and the CDM side-tab art. It is a phase in its own right,
not a tail on this one. The per-spell menu covers the assignment need in the meantime.

## E7. Faults found on the first in-game tests of Phase 4a

All of these predate this phase. Each had been invisible because a harness stub was more generous
than the real client — a pattern worth noting in its own right: every one of these was found by a
player looking at the screen, not by the 156 assertions.

1. **Every icon rendered grey.** `RefreshIconColor` called `IsUsableSpell(self.spellID)`. On 3.3.5a
   that function takes a spell NAME, or a spellbook INDEX with a bookType — never a spellID. Given
   one it reads it as an index far past the end of the book and returns **nil**, without erroring.
   nil is neither usable nor out-of-mana, so every icon fell through to `ICON_UNUSABLE` and the
   whole viewer dimmed to 40%. DragonUI's own action bars pass a name
   (`modules/actionbars/extrabar.lua:1049`). The harness stub returned a blanket `true` regardless
   of argument, which is exactly why it never caught this; it now mimics the client.

2. **The ready flash never played, for two compounding reasons.** `NE.tex.GetAtlasRect` returns four
   NUMBERS, not a table, and the flipbook stepper indexed the result as `atlas.right` — so `atlas`
   was the number `left` and every access inside an OnUpdate was an error waiting to happen. It
   never got that far, because the "art not shipped, degrade quietly" guard was
   `if not getFlashAtlas()`, and `GetAtlasRect` returns `0, 1, 0, 1` for an unknown atlas — `0` is
   truthy in Lua, so the guard passed precisely when the art was missing and `ScheduleFlash` bailed
   for the wrong reason. `NE.tex.HasAtlas` is the correct test. The retail GCD flipbook is not
   registered on this client, so the sprite path stays dormant and an undecorated alpha pulse on
   `Interface\Buttons\ButtonHilight-Square` (a base texture DragonUI itself uses) provides the cue.
   The sprite path takes over automatically if the atlas is ever registered.

3. **Icons went grey on cast and STAYED grey.** Distinct from fault 1, and only visible once that
   was fixed. Every event the viewer listens for — `SPELL_UPDATE_COOLDOWN`, `UNIT_SPELLCAST_*`,
   `BAG_UPDATE_COOLDOWN` — marks a cooldown STARTING or changing. **3.3.5a fires nothing when one
   expires** (`Alerts.lua`'s header already said so, in the course of explaining why the ready
   transition has to be polled). The swipe still completed, because the Cooldown widget animates
   itself in C, but no Lua re-ran, so the `SetDesaturated(true)` from the start of the cooldown
   persisted until some unrelated event refreshed the tile — usually the player's next cast. Each
   item now schedules its own refresh for the moment its cooldown ends, keyed on the end time so
   repeated refreshes during one cooldown don't stack timers.

   The harness could not have caught this: its `C_Timer.After` stub ran every callback immediately
   at the next drain, regardless of delay, so a scheduled refresh would have "worked" no matter
   what. The stub now honours the delay, and the regression test asserts the tile un-desaturates
   **with no event fired at all**.

4. **The ready flash was too faint to notice.** Fixing the plumbing (fault 2) was not enough: an
   alpha blink on an icon-sized quad barely registers against the icon art beneath it. The fallback
   burst now snaps to full brightness and expands to ~1.7x the icon while fading, in warm gold on an
   ADD blend, and sits two frame levels above the Cooldown swipe it plays over.

5. **`AceLocale: Missing entry for 'CooldownViewerBuffBar'` on every login.** DragonUI's
   `CreateUIFrame` labels the editor handle with `addon.L[frameName]`, and AceLocale's read metatable
   fires a non-breaking error for any undefined key. Harmless but noisy, once per registered frame.
   The table `GetLocale` returns has an `__index` hook but **no `__newindex`**, so `NE.RegisterHUDFrame`
   now seeds its own key — a plain assignment into a runtime table, not a change to DragonUI — which
   both silences the warning and upgrades the handle's label from `CooldownViewerBuffBar` to
   "Buff Bars".

## F. Open questions / unverified

1. ~~**`Cooldown:SetDrawEdge` on 3.3.5a**~~ — **answered on the evidence, and `/necdm` now prints the
   runtime answer.** ClassicAPI stubs `SetEdgeTexture` / `SetEdgeColor` / `SetEdgeScale` as
   "Incompatible (3.3.5)" (`Util/WidgetAPI.lua:1024-1026`) but does NOT stub `SetDrawEdge`, and its own
   cooldown-capture path calls `Self:GetDrawEdge()` unguarded (`Util/Cooldown.lua:204`) on every
   captured cooldown's OnShow — which would error constantly on every action button if the method were
   missing. `Process` injects unconditionally rather than filling gaps (`WidgetAPI.lua:1338`), so an
   absence from its table means native, not forgotten. Both call sites of ours guard anyway
   (`ItemMixins.lua:81`), so nothing depends on the answer; the `/necdm` line settles it rather than
   leaving an inference from someone else's code standing as fact.
2. ~~`Alerts.lua` and `SoundAlertData.lua` not dependency-mapped.~~ **Done — see §E6.**
3. ~~`CooldownViewerSettings/` blockers named but not designed.~~ **Done — scoped in §G.** Two of
   the blockers §E6 listed were wrong; see §G.1.
4. **Taint.** The viewers are pure display frames with no secure attributes, and `EnsureGroup`
   reparents them freely, so taint should be a non-issue — but Phase 1 must verify no combat-lockdown
   errors on `SetPoint` during a live restack.
5. **Whether four separate movers is tolerable UX** in DragonUI's editor mode versus one grouped
   handle. Decide during Phase 1 with the frames on screen.

---

# G. Phase 4b — the settings panel (`/cdm`)

Scope for porting `ReferenceAddons/NewEra/CooldownViewerSettings/` (2,139 lines / 6 files) as a
**standalone window opened with `/cdm`**, matching upstream's own choice of a free dialog rather
than a managed UIPanel.

This is where spell picking and per-spell alert/sound assignment live. Phase 4a shipped the engines
and their stores with nothing driving them; this closes that.

## G.1. Corrections to §E6

Two blockers named there do not exist. Checking beats remembering:

- **`LargeSideTabButtonTemplate` is not a problem.** Upstream synthesized it because Era lacks it —
  and so did we, already, for another module: `NE.tabs.MakeSideTab` (`core/Tabs.lua:222`) is the
  same substitution, complete with tooltip wiring. The Spells/Auras side tabs use it as-is.
- **Clipboard export is not a problem.** `CopyToClipboard` appears nowhere in the source. Export
  goes through a `StaticPopup` with a pre-selected edit box (`Presets.lua:260`) — the classic
  manual-copy pattern, native on 3.3.5a.

Also better than expected: **no `WowScrollBox` / `ScrollUtil` anywhere.** The body is a plain
`UIPanelScrollFrameTemplate` with a `SetScrollChild` (`Panel.lua:377`), which is native here and
which `NE.scrollbar.Reskin` already knows how to restyle.

## G.2. What already exists

| Need | Have | Where |
|---|---|---|
| Side tabs | `NE.tabs.MakeSideTab` | `core/Tabs.lua:222` |
| Window chrome | `NE.chrome.Apply` | `core/PanelChrome.lua:277`; precedent `modules/collections/Window.lua:264` |
| Scrollbar restyle | `NE.scrollbar.Reskin` | `core/ScrollbarReskin.lua:156` |
| Portrait cutout | `NE.portrait.ApplyCutout` | `core/Portrait.lua` |
| Open/close sounds | `NE.FrameUtil.WirePanelSounds` | `core/FrameUtil.lua:246` |
| Templates | `ButtonFrameTemplate`, `SearchBoxTemplate` (ClassicAPI); `UIPanelScrollFrameTemplate`, `UIPanelButtonTemplate`, `StaticPopupDialogs` (native) | — |
| Panel background art | `character-panel-background` (5882640) already registered | `modules/character/Assets.lua:35` |
| Alert + sound stores | shipped in Phase 4a | `Alerts.lua`, `SoundAlertData.lua` |
| Show/hide a spell | `M.SetSpellEnabled` / `M.IsSpellEnabled` | `CooldownViewer.lua` |
| ESC-to-close, slash command | `UISpecialFrames` + `SLASH_*` | precedent `modules/encounterjournal:643` |

## G.3. What must be built

1. **`core/Menu.lua` — a MenuUtil-shaped builder over `UIDropDownMenu`.** The highest-leverage
   piece by far. All three menu sites (`Categories.lua:42` item menu, `Panel.lua:192` settings menu,
   `Presets.lua:348` layout menu) are written against MenuUtil's builder API — `root:CreateTitle`,
   `CreateButton`, `CreateRadio`, `CreateDivider`, arbitrarily nested. Reimplementing that API over
   3.3.5a's `UIDropDownMenu` (~120 lines) lets all three port close to verbatim, instead of
   rewriting each by hand. Use ClassicAPI's `C_UIDropDownMenu`, which grows
   `C_UIDROPDOWNMENU_MAXLEVELS` on demand — the sound menu needs four levels
   (item → Ready Sound → category → entry) and the native one caps at two.

   This is also the correct home for the Phase 4a right-click menu that was deleted: upstream's
   `showItemMenu` already carries Move-to / Remove / Ready Sound / Alert (type, FX, window), and it
   maps onto the 4a API almost one-to-one. Only the FX enum differs — upstream uses `1 = ants`,
   `6 = flash`; ours is `1/2/3` over LibCustomGlow (`AL.FX`), so drive the submenu off `AL.FX`.

2. **Drag reorder without `GLOBAL_MOUSE_UP`** (`Reorder.lua`, 6 uses). That event is retail 9.x.
   The file already runs an `OnUpdate` driver while a drag is active, so the substitution is to
   watch `IsMouseButtonDown` transitions there and call the existing `endChange` / `CancelOrderChange`
   on release. ~30 lines changed, not a rewrite. `GetMouseFoci` → `GetMouseFocus` is already
   fallback-handled at `Reorder.lua:23`.

3. **`NE.listheader`** — the collapsible category header. Absent, but with in-repo precedent:
   `modules/character/Reputation.lua:68` notes the same gap and builds one inline.

4. **Small shims:** `NE.button.Skin` and `NE.dropdown.SkinStyle` (cosmetic — may no-op initially),
   `NE.OpenOptions` (point at our `NE.optionSections` tab), `SetShown` → the local `setShown`
   helper (10 sites, CONTRACTS §0).

5. **Art:** copy `7289697-cdmadvanced.blp` from the reference `Art/CooldownViewerSettings/`. Only
   two of its three glyphs are needed (`icon_cooldownmanager`, `icon_trackedbuffs`).

## G.4. Deliberate cuts

- **The Group Buffs side tab.** 12 references to `NE.groupbuff.filter`, a module this addon does not
  have. Two tabs, not three — `CDS.UpdateGroupBuffsTabState` goes with it.
- ~~**`NE.editmode.Toggle` / `SelectFrame`** (4 refs)~~ — **routed, in Phase 6 (§G.13).** Upstream's cog
  menu carried an "Edit Mode" entry that hid the window and toggled retail Edit Mode
  (`Panel.lua:211`); ours is a **per-viewer** "Position this viewer" button on the Settings tab, going
  through the new `NE.OpenFrameEditor` seam. Per viewer rather than once globally because DragonUI's
  editor can be told which frame to select, so the button under Buff Bars' sliders opens the editor
  with Buff Bars selected. The fourth ref, `RepositionHandle` (`CooldownViewer.lua:977` — re-anchor the
  drag rect as items come and go), needs no port: `RegisterHUDFrame` syncs the anchor to the content's
  size from the content's own `OnSizeChanged`.
- **`NE.OpenOptions`** (upstream's "Show Options" jump out to the addon's option surface) — **not
  ported, and now pointless.** The traffic runs the other way since §G.12: DragonUI's section is an
  enable toggle and a button that opens `/cdm`. A link back to a page holding one checkbox would be
  worse than its absence.
- ~~**Presets / layouts**~~ — deferred to last as planned, and **shipped as 4b-5** (§G.11) once the
  picker it sits on top of was working.

**Resolved — the Equip categories. DONE for trinkets (§G.9).** Owner's call was to port
`CooldownViewerEquip.lua` so on-use trinkets and potions are trackable. Trinkets shipped as Phase 5a
with one source pool ("Trinkets"), not two: the passive pool is cut because on this client it can
only ever contain on-use trinkets already listed in the active pool. Consumables are deferred on a
**data** blocker, not effort — `Item.dbc` carries neither item names nor item→spell links, so a
bucketed potion list cannot be generated from client data. §G.9 scopes the route through.

## G.5. Phasing

| Step | Scope | Exit criterion |
|---|---|---|
| **4b-1** | Window shell: chrome, Spells/Auras side tabs, scroll body, search box, `/cdm` toggle, ESC-close. **DONE** | `/cdm` opens and closes a correctly-chromed empty window |
| **4b-2** | `SettingsAdapter` + `SettingsCategories` grids, read-only. **DONE** | All categories render the player's real spells |
| **4b-3** | `core/Menu.lua` + the item context menu. **DONE** | **The payoff.** Spell visibility, alerts and sounds are all settable, and Phase 4a stops being dormant |
| **4b-4** | Drag reorder. **DONE** | Items can be dragged between categories and reordered |
| **4b-5** | Presets / import / export, and the snapshot pair that makes Revert real (§G.11). **DONE** | Layouts save, load, import and export; Revert undoes an apply |
| **5a** | On-use trinket discovery + the Trinkets source pool (§G.9). **DONE** | An equipped on-use trinket appears in `/cdm`, drags into Essential, and shows on the bar |
| **4c** | Third `/cdm` tab hosting every viewer setting; the DragonUI section shrinks to an enable toggle plus an Open button (§G.10 scope, §G.12 notes). **DONE** | Every setting is editable from `/cdm`, and no stored value is rendered in two windows |
| **6** | Loose ends (§G.13): the edit-mode affordance §G.4 never decided, §F1, and the 4b-1 vestiges. **DONE** | Every viewer is positionable from `/cdm`; no open question left that offline work can close |
| **5b** | Consumables, via a generated Spell.dbc effect table (§G.9) | **Parked as a stretch goal** (owner, this pass). Blocked on the generator, not on effort |

4b-3 is the milestone that matters; 4b-4 and 4b-5 are polish. Rough size: ~1,400 lines adapted from
the source plus ~200 of new shim, against 2,139 in the original — the difference being the Group
Buffs tab, Edit Mode wiring, and the retail menu framework.

## G.6. 4b-2 notes (adapter + grids)

**The Hidden section needed data that did not exist.** Upstream's Hidden is the opt-in catalog, and
it is driven by a generated `NE_CDM_HIDDEN` global — every class ability with a real cooldown.
Without an equivalent, Hidden could only ever re-offer spells the player had removed, which is an
undo list, not a picker. `tools/cdm-spellgen/gen_arsenal.py` emits `CdmArsenal.lua`
(`M.ARSENAL_BY_CLASS`, 303 abilities across ten classes) from the same `resolved.json` the Phase 2
seed came from, so it costs one thin emitter rather than new analysis.

Expect Hidden to look SHORT in game. Our curation is deliberately broad, so most of a class's
cooldown abilities already sit in Essential or Utility; what remains is the difference. That is the
intended behaviour — the section fills up as the player moves things out.

**`NE.listheader` substituted inline**, the same call `modules/character/Reputation.lua` made for the
same missing Core helper, using the client's own +/- collapse buttons.

**Bug worth recording: a tri-state predicate that only ever returned two.** `listHasEnabled` answers
"is this spell listed and enabled?" with true / false / **nil**, where nil means *not mentioned* and
is what sends `isPlaced` to the curated defaults. It returned `false` for a missing list instead of
nil, so the curated fallback was unreachable and every curated spell appeared in Hidden alongside
itself. Caught by asserting the two sets do not overlap — a property that is obvious to state and
was not obvious to eyeball.

## G.7. 4b-3 notes (the menu shim and the item menu)

**`core/Menu.lua` reimplements the MenuUtil builder API, not the menus.** Every menu in the source
is written as a generator that receives a root description and calls `root:CreateTitle`,
`CreateButton`, `CreateRadio`, `CreateCheckbox`, `CreateDivider`, nesting by adding children to a
returned description. Rebuilding that API once over `UIDropDownMenu` (~250 lines) means the three
menu sites port close to verbatim. Rewriting each by hand into the init-callback idiom would have
been more code in total and a fresh chance to get the level plumbing wrong at every site.

**Why ClassicAPI's `C_UIDropDownMenu` and not the native one.** The native 3.3.5a
`UIDROPDOWNMENU_MAXLEVELS` is a hard 2. The ready-sound menu is three deep — item → Ready Sound →
category → entry — and the alert menu is three as well (item → Alert → FX Style). ClassicAPI's copy
grows the cap inside `C_UIDropDownMenu_CreateFrames`. The native API is kept as a fallback (same
shape, different list-frame name prefix), so the shim still works two levels deep if ClassicAPI is
ever absent. `compat/COVERAGE.md` previously recorded this symbol as having "no current consumer";
`core/Menu.lua` is now that consumer.

**The tree is built separately from the render.** `NE.menu.BuildRoot` runs a generator and returns a
plain node tree with no widget touched. That is what makes menu CONTENT testable offline: the
harness builds the item menu, walks it, and invokes a leaf's callback to assert that selecting
"Cat" writes kit 316401 and previews it — none of `UIDropDownMenu` is stubbed. The 4b-3 block adds
26 assertions on that basis.

**Two client-behaviour traps in `UIDropDownMenu`, both worth remembering.**

1. *A submenu parent must be `notClickable`, not a no-op `func`.* `UIDropDownMenuButton_OnClick`
   toggles the row's Check texture **before** it looks at `func`, so a clickable-but-inert parent
   paints a stray checkmark on itself. Disabling the row leaves `OnEnter` — which is what actually
   opens the submenu — firing normally.
2. *`C_UIDropDownMenu_Refresh` cannot refresh our radios.* It keys off
   `frame.selectedName/selectedID/selectedValue`, which say nothing about a function-valued
   `checked`. Calling it would hide every check. The shim repaints a level's marks itself, from the
   predicates, after any radio or checkbox fires.

**One deliberate divergence from upstream: the FX enum.** Upstream's fx values index
`NE.groupbuff.VISUAL_ALERT` (`1` = marching ants, `6` = flash), an enum this addon does not have.
Ours is `AL.FX` — 1/2/3 over LibCustomGlow. The FX submenu is therefore *generated from* `AL.FX`
rather than hardcoding upstream's pair; porting those two lines verbatim would have silently
written `6`, for which there is no renderer. Pinned by a test that compares the submenu against
`AL.FX` rather than against a literal.

**The grid now shows its own state.** A tile with an alert or a ready sound configured carries a
corner badge, and its tooltip names both. Without that, the only way to read the configuration is
to right-click every icon in turn. Upstream's `common-icon-visual` glyph is not registered here, so
the badge uses upstream's own fallback (a gold dot) — asked via `HasAtlas` rather than by letting
`SetAtlas` fail, because a failed `SetAtlas` logs an ATLAS MISS and this runs once per tile per
rebuild.

**Both cog resets confirm first.** "Reset Spell Lists" and "Clear All Alerts" are irreversible until
4b-5 brings a snapshot store, so both route through a `StaticPopup`. The harness asserts the click
raises the popup rather than acting, then drives `OnAccept` separately.

### G.7.1 In-game faults found on the 4b-3 pass

Three reports, three unrelated causes. All three were invisible to the harness as it stood, and all
three are now covered — including negative checks confirming each new assertion fails against the
unfixed code.

**"Icons in the cooldown manager window are all greyed out."** Not the learn tint, and not the icon
textures: **alpha 0.25 on every tile, from the search filter.** ClassicAPI's `SearchBoxTemplate` has
**no `Instructions` FontString** — its placeholder *is* the edit box's text (`SearchBoxTemplate_OnLoad`
does `SetText(SEARCH)`, and `OnEditFocusLost` puts it back). So an untouched box reads back
`"Search"`, `RefreshLayout` handed that straight to `ApplyItemFilter`, and every tile whose spell is
not named "Search" dimmed. The 4b-1 line `if f.search.Instructions then … end` was a no-op guarding
a field that never exists, which is exactly why it looked fine. Every read now goes through
`CDS.GetSearchText`, which maps the placeholder to `""`. The harness sets `SEARCH` and seeds the box
with it before asserting the tiles stay at full alpha.

**"The selected alert or sound doesn't get reflected in the menu on reopening."** A **Lua idiom bug
in ClassicAPI's `C_UIDropDownMenu_AddButton`**:

```lua
local checked = type(info.checked) == "function" and info.checked() or info.checked
```

When the predicate returns **false**, `(true and false)` is false, so the `or` falls through to
`info.checked` — the function object, which is truthy. Every function-valued radio therefore
rendered as selected, and a menu where *everything* is ticked communicates nothing. DragonUI and
ClassicAPI are read-only (§0), so the fix is on our side: `core/Menu.lua` snapshots the predicate to
a **boolean** at build time. Nothing is lost — the tree is rebuilt from the generator on every open,
and `refreshChecks` re-reads the predicate on every click. Pinned by two assertions: exactly one
radio in a group reads selected, and `info.checked` is never a function *at any rendered level*
(the first version of that check scanned level 1 only, which holds no radios, and passed
vacuously).

**Panel size.** Owner asked for +30%. Applied as `PinPixelPerfect(f, 1.3)` — a **scale**, not larger
`PANEL_W`/`PANEL_H`. The grid geometry (38px tiles, 46px pitch, 7 per row, 344-wide category) is
upstream's probe-confirmed layout; growing the frame around unchanged tiles would only add margin.
`PinPixelPerfect` folds the multiplier into its pixel-snap target and re-applies it whenever the UI
scale changes.

**What this cost, and the lesson.** The harness could assert menu *content* but nothing about
*rendering*, so it could not have caught either of the first two. It now carries a small
`C_UIDropDownMenu` stand-in — deliberately **not** a reimplementation. Copying ClassicAPI's `and`/`or`
bug into a stub in order to "catch" it would be circular. What the stub records is the shape of the
`info` tables *we* produce, and the invariant that keeps us clear of the bug ("never hand the client
a predicate") is checkable without reproducing it.

### G.7.2 Alert engine faults (second in-game pass)

**"The FX come out green when actually used on the bars."** The preview was lying. `AL.Preview`
hardcoded the alert type `"usable"`, so every preview flashed the usable YELLOW regardless of which
event the player had just chosen — then the live icon glowed in that event's real tint (available
green, refresh pandemic-orange). `Preview` now takes the type and the menu passes the one being
configured. A preview whose whole job is "see it before you commit" has to show the colour you will
actually get.

**"The only FX Alert type that seems to do anything is available."** Two compounding causes.

1. **`IsUsableSpell(spellID)` again, in `Alerts.lua:262`.** The same fault fixed in
   `ItemMixins.lua:545` — 3.3.5a's `IsUsableSpell` takes a NAME or a spellbook index, never an id;
   given an id it reads it as an index past the end of the book and returns nil. `isSpellUsableNow`
   therefore returned false unconditionally, so the Usable event could never fire for anybody. The
   ItemMixins fix did not sweep for other call sites. It should have.

2. **The curated gate made Usable a dead entry for six classes.** `inUsableState` returned false for
   any spell not in AlertData's EXECUTE or REACTIVE tables — eight abilities across Hunter, Paladin,
   Warrior and Rogue. A Priest or a Mage could select "Usable" and nothing could ever happen. That
   gate is defensible upstream, where the alert can be attached to spells with no cooldown at all;
   here it contradicts the label. **Semantics changed:** Usable now means castable right now.
   EXECUTE stays as the stricter condition where it applies, because target health is something
   `IsUsableSpell` knows nothing about — without it Kill Shot would glow all fight instead of in
   execute range. `A.IsReactive` is no longer consulted at all: the client already reports Overpower
   and Revenge as unusable outside their proc window, so the curated check only restated it.
   `A.REACTIVE` stays in AlertData as data with no reader.

**The test that shielded the bug.** The 4a suite asserted, in as many words, *"a spell with no
execute/reactive entry never glows on 'usable'"* — and it passed, for the wrong reason: with
`isSpellUsableNow` hard-false, nothing glowed whatever the data said. The assertion agreed with the
bug and hid it until the owner reported the feature did nothing. **A test that encodes "this feature
is off here" cannot tell you the feature is broken.** Where the intended behaviour is negative,
assert the positive case somewhere too, or the negative one proves nothing.

## G.8. 4b-4 notes (drag reorder)

**The one real downport is the drag's ending.** `GLOBAL_MOUSE_UP` is retail 9.x and upstream uses it
six times. But a drag already runs an `OnUpdate` to follow the cursor, so the release is detected
there instead, by watching `IsMouseButtonDown` transitions: left down→up commits, right down at any
point cancels. Same two outcomes, no event. `GetMouseFoci` → `GetMouseFocus` was already
fallback-handled upstream. Nothing else about the file needed changing.

**`Adapter.ReorderTo` / `Adapter.AssignAt` are new.** Our storage model keeps a per-category editable
list of `{spellID, enabled}`, so ordering is that list's order; the aura pool orders itself the same
way, which lets one function serve both. `AssignAt` is `Assign` followed by a `ReorderTo`, which is
what carries the drop POSITION across a category boundary — dropping onto a tile inserts at that
caret rather than appending.

**The off-by-one that every drag reorder has.** `ReorderTo` must recompute the target index AFTER
removing the dragged entry: pulling it out shifts everything below it up by one, so an index taken
beforehand overshoots by one whenever the item moved DOWN the list. Both drop-direction assertions
fail against the pre-removal version, which is the point of having two.

**Cuts.** `CDS.SetDragActive`, which illuminates the "+" drop slots this panel does not have. (The
equip-token branches were also cut here and have since been restored by §G.9.) The
consequence is that dropping on empty space does nothing; drop onto a TILE, or onto a category's
HEADER, which resolves to that category on the walk up. Enabling mouse on the category container
would make empty-area drops work too, but it risks the scroll frame's wheel handling for an
affordance the header already provides.

**Sounds.** 3.3.5a's `SOUNDKIT` (ClassicAPI `Util/SoundKit.lua`) is a dozen entries and carries none
of retail's cursor kits. The three names used here are confirmed present in this client's own
FrameXML, and each play is `pcall`ed and checks the `willPlay` return, so an unknown name is silence
rather than an error.

**Panel close cancels the drag**, hooked on `OnHide` rather than in `CDS.HidePanel`: the close button
and ESC both call `Hide()` directly. Without it a closed window would strand the cursor icon
(parented to UIParent) and leave the source tile dimmed and locked. The offline harness now fires
`OnHide` on a shown→hidden transition, matching the client — it previously fired only `OnShow`, so
this whole class of teardown bug was invisible to it.

## G.9. Phase 5a notes (on-use trinkets)

Port of `CooldownViewerEquip.lua` (182 lines) â†’ `modules/cooldownviewer/Equip.lua`. This is the
owner-approved item of Â§G.4, and it lands the *trinket* half in full.

**The model is opt-in, and that is the point.** An item cooldown has no viewer by default. It is
discovered, keyed by a stable token (`item:<itemID>`), and parked in a source pool â€” the "Trinkets"
section in `/cdm` â€” showing nowhere on screen until the player drags it into Essential or Utility.
Assignment is persisted per token in `cooldownviewer.equipAssign`, so re-equipping the same trinket
restores the choice. `"hidden"` has to be a *stored* value rather than a synonym for unassigned:
`GetEquipAssignment` falls back to the class default only when a token is genuinely absent, so an
explicit hide must occupy the key.

**Trinkets cost nothing in curation.** `GetInventoryItemID` gives the item in each trinket slot and
`GetItemSpell` gives its on-use spell; both come from the client at runtime. Nothing is typed.

### The token is the move key, not the spellID

`Adapter.GetItems` now returns a **mixed** list â€” numbers are spellIDs, tables are equip entries.
That is upstream's shape and it keeps the change small: a tile handed a table calls `SetEquipEntry`,
a tile handed a number calls `SetSpell`, and the menu and drag paths branch on `item.token`. The
alternative (promoting every spell to an entry table) would have touched the menu, the drag path,
the filter and the tests for no gain.

Routing an equip row through the spellID path is not a near-miss, it is a data corruption: it would
write the trinket's use-spell into the editable spell list, where it *survives unequipping the
trinket* and points at nothing. `Adapter.Assign` therefore refuses outright when either side of the
move is a source pool, and there is an assertion on that refusal.

**Pooled tiles must drop the binding.** A tile that held a trinket can be handed a plain spell on
the next rebuild. `clearEquipBinding` runs at the top of both `SetSpell` bodies; without it the
stale token keeps routing that row's right-click and drag through the equip path.

**An empty source pool is not rendered at all** â€” not as "(empty)". A player with no on-use trinket
should not be told about a Trinkets section; that would read as a broken feature rather than an
absent input. Stored categories still show when empty, because there an empty list is a state the
player chose.

**Reorder does not apply to an equip row.** It has no stored position â€” the viewer appends
discovered items after the spells â€” so dropping one inside its own category is a deliberate no-op.
Dragging a *spell* onto an equip row is also a no-op for the same reason: there is no index to
reorder against. Cross-category drops work normally.

**Events.** `UNIT_INVENTORY_CHANGED` triggers a full `Rebuild` on the viewers (a swap changes the
discovered set, not just a cooldown) and a `RefreshLayout` on the panel.

### Cut: the passive pool, for a data reason

Upstream's `GetEquipPassiveItems` walks the same two trinket slots and surfaces each one's **use**
spell as a trackable aura. So a proc trinket â€” the only kind for which a passive aura row would mean
anything â€” returns nil from `GetItemSpell` and never appears, and the pool can only ever contain
on-use trinkets that are already rows in the active pool. Upstream flags this itself ("Era has no
on-equip-aura data layer", `TODO(hydrate)`). Shipping it would add a second source section whose
contents duplicate the first. `equipPassive` and its half of the legal-target matrix go with it.

### Deferred: consumables (potions, healthstones, runes)

Upstream's `M.POTION_CATEGORIES` is a hand-curated table of ~45 **vanilla** item ids bucketed into
Healing / Mana / Healthstone / Soulstone / Combat, best-rank-first, so the runtime can show one slot
per bucket for the best item held. WotLK adds a tier to every one of those buckets. Typing those ids
in violates the prime directive, and **the 3.3.5a client cannot supply them**: `Item.dbc` carries no
item names and no itemâ†’spell link â€” both live server-side in `item_template` â€” so there is nothing
to generate a bucketed list *from*.

The way through is to classify at runtime by the use-spell's **effect**, which *is* client data:

1. Extend `tools/cdm-spellgen/dbc.py` to keep `Effect[0..2]` and `EffectBasePoints[0..2]` alongside
   the name/rank columns it already parses. It reads every field as `uint32` today, so this is a
   wider tuple, not a new parser. Locate the columns the way `name_col` is located â€” empirically,
   against anchors (spell 2050 Lesser Heal has `SPELL_EFFECT_HEAL`).
2. Emit `M.CONSUMABLE_SPELLS = { [spellID] = { bucket = "health"|"mana", magnitude = <basepoints> } }`
   for every spell whose effect is Heal (10) or Energize (30, mana).
3. At runtime, scan the bags once per `BAG_UPDATE` (dirty-flagged), map each item through
   `GetItemSpell` â†’ spellID â†’ that table, and keep the highest-magnitude item per bucket.

That covers health/mana potions, healthstones and runes across every tier automatically, with no id
typed anywhere. Combat potions (Free Action, Mighty Rage) apply auras rather than heals and are not
reachable this way; they would need either a third bucket keyed on aura-applying effects or a
deliberate cut. `M.DEFAULT_EQUIP_BY_CLASS` is already in place and empty so that the Warlock
Healthstone/Soulstone defaults become a data change rather than a code change.

## G.10. Scope: a third `/cdm` tab for the viewer settings

**Where the settings live today.** Every non-per-spell setting is in the DragonUI options panel,
registered by `modules/cooldownviewer/Register.lua` as section `cooldownviewer`. That is a different
window, reached by a different path, and it is the one thing about the current `/cdm` that does not
match retail â€” retail's Cooldown Manager settings sit *in* the Cooldown Manager.

**What the tab would host.** Everything currently in the options section: per-viewer enable, scale,
opacity, orientation/stride, visibility mode (always / in combat), show-timer and show-tooltip
toggles, plus the "Show Unlearned" checkbox that is presently in the cog menu. Frame *position*
stays with the movers (`/dui edit`) â€” Â§B1's decision, unchanged.

**The pieces already exist, which is why this is small.**

- `NE.tabs.MakeSideTab` builds the tab; `f.tabButtons` is already a list and `SetDisplayMode`
  already iterates it. Adding a third entry is three lines plus an anchor.
- The panel body is a `ScrollFrame` over `f.content`. `CDS.RefreshLayout` fills it from
  `Adapter.MODE_ORDER[mode]`, which has no entry for a settings mode.
- The side-tab glyph is the one asset gap: `SettingsAssets.lua` registers two
  (`icon_cooldownmanager`, `icon_trackedbuffs`) from the reference sheet, which carries a third.

**The one real decision â€” and the reason this is scoped rather than done.** The current body is
owned end-to-end by the category grids: `RefreshLayout` rebuilds `f.content` from the adapter on
every call, and there is nowhere for a page of controls that is *not* a category list to live. Two
ways out:

- **(a) A second content frame.** Build a `f.settingsContent` sibling, and have `SetDisplayMode`
  show one and hide the other via `f.scroll:SetScrollChild`. `RefreshLayout` early-returns for the
  settings mode and never touches it. Cheap, and no risk to the grids.
- **(b) A "category" whose renderer is a control list.** More uniform, but it puts widget layout
  behind an adapter whose whole contract is "return a list of spellIDs", and every consumer
  (`ApplyItemFilter`, the drag path, `RestackCategories`) would need a "not a grid" branch.

**(a) is the recommendation** â€” the settings page has nothing in common with a grid of tiles, and
pretending otherwise buys uniformity at the cost of a branch in four files.

Two smaller consequences fall out of (a) and should be handled with it: the **search box and cog**
are meaningless on a settings page and should hide with the grids, and the panel is 399x609 at 1.3
scale, so a long control list needs the scroll frame it already has rather than a taller window.

**Duplication is the thing to decide, not the layout.** The options section cannot simply be moved:
DragonUI's options panel is where a user goes to turn the module *off*, and it is read-only to us
(CONTRACTS Â§0 â€” we register a section, we do not own the window). So either

- the tab and the options section both read and write the same `NE.Config().cooldownviewer` store
  and stay in sync by construction (each rebuilds on show; no shared widget state), or
- the options section shrinks to an enable toggle plus an "Open Cooldown Manager" button, and the
  tab becomes the single home for the rest.

The second is retail's shape and the better end state. It is also the one that changes behaviour a
user may already rely on, so it is an owner's call rather than an implementation detail.

**RESOLVED (owner): the second.** The options section keeps the master enable toggle and an "Open
Cooldown Manager" button; everything else moved to the tab. Implementation notes in §G.12.

**Estimated size:** ~40 lines of panel wiring, ~180 lines for the control page (reusing the same
slider/checkbox helpers `Register.lua` already builds for the options section), plus harness
coverage that the tab switches modes and that a write from the tab is visible to the options
section. No new platform gap â€” nothing here needs an API 3.3.5a lacks.


## G.11. 4b-5 notes (layouts, import/export, and the real Revert)

Downport of `CooldownViewerSettings/Presets.lua` (378 lines) â†’ `SettingsPresets.lua`.

**The snapshot pair came with it, and that is the point.** Upstream's `Panel.lua` owns
`snapshotState`/`restoreState` and exposes them as `CDS.SnapshotState` / `CDS.RestoreState` /
`CDS.DeepCopy`; 4b-1 deferred the Revert button precisely because that pair did not exist. It lives
here now, so Revert is real. Applying a layout and undoing one are the same operation with a
different source snapshot â€” building two mechanisms for that would have been the mistake.

A layout is the five editable leaves plus the class it was captured on: `customLists`,
`trackedAura`, `equipAssign`, `alerts`, `sounds`, `class`. Restore is **whole-leaf assignment, not a
merge**: a layout is a complete state, so a spell the snapshot does not mention has to end up
unmentioned rather than surviving from whatever was there before.

`InvalidateCuratedCache` on restore is load-bearing. `GetActiveSpellList` caches the resolved curated
list, and replacing `customLists` underneath it leaves the viewers rendering the *previous* layout
until something else happens to dirty the cache â€” the same shape as the Â§E5 shadowing bug.

**Undo is one step, and only for this session.** The panel's edits are individually reversible by
hand (move it back, pick None), so what a player actually needs is "undo the layout I just applied",
not a history. The snapshot is taken before any apply / starter / import, and cleared on `OnHide`:
reverting an hour-old change is not an undo. The selected layout NAME is tracked *beside* the
snapshot rather than inside it â€” it is session bookkeeping, and putting it in the snapshot would bake
it into every export string, so a shared layout would arrive carrying the name of the layout its
author happened to have selected.

### Downport changes

**No `WowStyle1DropdownTemplate`.** The footer control is a plain `UIPanelButtonTemplate` opening
`CDS.BuildLayoutMenu` through `core/Menu.lua`. Same menu tree; only the widget differs. Its label is
the selected layout's name, so the footer still answers "which layout am I on" at a glance.

**Import is class-checked, which upstream is not.** A snapshot's spell lists are keyed by class, so
restoring a Priest layout on a Mage writes into the Priest's slot and appears to do *nothing at all*.
A silent no-op is the worst outcome for a paste, because the player cannot tell it from a broken
feature. `Decode` now refuses with a reason naming the class the layout was built for.

**Nothing else.** The codec is upstream's and was already 3.3.5a-clean â€” `string.byte`/`char`,
`math.floor`, `string.find`, no `bit` library anywhere.

### Safety

Import never executes pasted input: a hand-rolled typed reader, no `loadstring`, no `setfenv`, every
parse wrapped in `pcall`. Strings are length-prefixed so a spell name containing a tag character is
still safe. Plain SavedVariables plus StaticPopups throughout â€” nothing here can taint the combat
path.

**Two bad-input findings, both from writing the negative test rather than the guard:**

1. **The over-long string length is the one bad input that would pass silently.** `string.sub` clamps,
   so `t1;s5:class` + `s99:PRIEST` parses as `{ class = "PRIEST" }` â€” a well-formed layout built from a
   truncated read â€” and every later check (is it a table, is `.class` a string, does the class match)
   then passes. The explicit bounds check in the `s` branch is what stops it. The test pairs it with
   the same payload at the correct length, so the rejection is provably about the length and not the
   shape.

2. **The table pair-count cap was dead code, and was removed.** A header claiming a billion pairs is
   the obvious DoS shape, so the first version capped `count`. The negative test showed the cap
   changed nothing: every loop iteration must consume at least one byte of payload or raise, so the
   parser is self-limiting and such a header fails on the first pair. The assertion now states *that*
   â€” which is what lets the cap stay out instead of sitting there as a guard no input can reach.

Both are the Â§G.7.2 lesson again: a guard whose test passes with the guard removed is telling you
something, and it is usually that the guard or the test is wrong.

## G.12. 4c notes (the Settings tab)

§G.10 scoped this; the owner picked the second option, so the DragonUI options section is now an
enable toggle and an "Open Cooldown Manager" button, and every viewer setting lives on a third `/cdm`
tab. Two new files: `SettingsControls.lua` (the widget kit) and `SettingsOptions.lua` (the page).

**Option (a) as scoped: a second scroll child.** `panel.settingsContent` is a sibling of
`panel.content`, and `SetDisplayMode` swaps which one the ScrollFrame holds. The category grids own
`panel.content` end to end — `RefreshLayout` rebuilds it from the adapter on every call — so a page of
controls could not have shared it without an adapter category whose "list of spellIDs" contract it
cannot satisfy.

`CDS.RefreshLayout` gained a settings-mode early return, and that guard is load-bearing rather than an
optimisation. The panel refreshes on `SPELL_UPDATE_ICON`, `GET_ITEM_INFO_RECEIVED` and
`UNIT_INVENTORY_CHANGED` whenever it is shown; `MODE_ORDER` has no `settings` entry, so without the
return each of those events would walk the deactivate loop, switch every category off, and find
nothing to switch back on — leaving the grids empty behind a page the player is not looking at, to be
discovered on the next tab switch.

### Why a widget kit at all

DragonUI's `Controls:AddToggle` / `AddSlider` / `AddDropdown` are AceGUI widgets that call
`parent:AddChild(...)` and lay themselves out only inside an AceGUI container. Our body is a plain
Frame in a plain ScrollFrame, and DragonUI is read-only (CONTRACTS §0), so the choice was a kit or an
AceGUI container inside our panel. The kit is ~330 lines over the client's own
`UICheckButtonTemplate` and `OptionsSliderTemplate`, and it keeps the page looking like the rest of
the window rather than like the options tab embedded in it.

**Three downport points inside the kit:**

1. **No `WowStyle1DropdownTemplate`** — same absence the footer works around (§G.11). A dropdown is a
   button labelled with the current value, opening a radio menu through `core/Menu.lua`. It also takes
   an ORDERED array where the options tab takes a `value -> label` map: AceGUI sorts a map for you, and
   a radio menu has to choose. "Always / In Combat / Hidden" is a progression; alphabetised, Hidden
   lands in the middle.

2. **`SetObeyStepOnDrag` does not exist here**, and `SetValueStep` alone only governs the arrow keys,
   so a drag delivers continuous values. The kit snaps on the way in — the same thing Blizzard's own
   option sliders do in their `OnValueChanged`.

3. **The write gate on that same handler.** A drag fires `OnValueChanged` on every mouse move, and
   every write runs `M.SetOpt`, which re-runs the viewer's `RefreshLayout` and relays out every icon.
   Only a value that crosses into the next step may write. Verified by removing it: the "stays inside
   one step" assertion goes from 0 writes to 2.

### What is NOT on the page

**Frame position.** Still the movers (`/dui edit`), §B1's decision unchanged. It is the one setting
that is not a value in this store.

**Hide When Inactive on Essential and Utility.** Retail's templates for those two do not set
`allowHideWhenInactive`, so `UpdateShownState` ignores the setting and they always show every known
cooldown. The options tab shipped the control anyway with a description explaining that it did
nothing. The page offers it only where `GetOpt(frameID, "allowHideWhenInactive")` is true: a control
that has to explain its own inertness is worse than an absent one.

**The master enable.** It stays in DragonUI's options and appears nowhere here. That panel is where a
player goes to turn a module off, and nobody looks inside a window for the way to make that window's
frames stop existing.

### Duplication: values versus actions

The rule the §G.10 decision enforces is that no stored VALUE has two editors. A setting with two
editors is consistent only while both rebuild on show, and the first time one does not, the player is
reading a stale control and cannot tell that from a setting that failed to apply. Hence exactly one
home for each of the ten per-viewer settings, the two bar-only ones, and buff auto-tracking.

The two resets are deliberately in two places — the cog menu and the page's Reset section. They are
ACTIONS routed to the same `StaticPopup`s, with no stored state to fall out of sync: the cog is at
hand while working the lists, and a player looking for a reset looks under Settings. "Show Unlearned"
stays in the cog alone, because it filters the grids rather than configuring a viewer, which is also
why the cog and the search box both hide on this tab.

### Art

The tab glyph is the client's own `questlog-icon-setting` at 18px, not a third glyph from the CDM
sheet. That sheet's spare is `icon_buffreorder` — "reorder group buffs" — which would be a lie here,
and reusing the cog ties the tab to the cog beside the search box, which is what a player already
reads as "options for this window". `SettingsAssets.lua` now registers that rect itself rather than
depending on `modules/spellbook/Assets.lua` having loaded; the harness asserts it resolves, because an
unregistered atlas is a transparent gap rather than an error.

### Harness

47 new/changed assertions (382 at that point; 394 after Phase 6). Five guards were confirmed by removal: the slider write gate,
the step snap, the settings-mode return in `RefreshLayout`, the `allowHideWhenInactive` gate, and the
chrome hiding. Two stub notes:

- `frameMeta:SetValue` now fires `OnValueChanged` on a real change, as the client does. The sliders
  re-seat their own thumb from inside that handler and re-read their getter on every page refresh, so
  a stub that swallowed those calls could not tell a working re-entrancy guard from a missing one.
- `SetObeyStepOnDrag` is deliberately still absent from the stub. Adding it would hide the reason the
  kit snaps values itself.

The control finder in the test scopes by section title as well as label, and that is not tidiness:
"Icon size" exists four times, once per viewer, so an unscoped search always answers with Essential's
row — and a test meaning to prove Buff Bars' slider works would have proved nothing. Same failure
shape as §G.7.2 and the 5a pooled-tile test.

## G.13. Phase 6 notes (loose ends)

With 4c shipped and consumables parked as a stretch goal, both phasing tables were complete and there
was no next *port* phase — what remained was a short list of things the plan had deferred rather than
decided. This closes them.

### 1. The edit-mode affordance (§G.4, undecided since the §G scope was written)

`NE.editmode.Toggle` / `SelectFrame` were listed as "drop the affordance or route it at `/dui edit`",
and neither was ever chosen — so the Settings tab shipped in 4c telling players to type `/dui edit`.
Routed now, through a new integration seam:

```
NE.OpenFrameEditor(frame) -> true | false, reason
```

**It lives in `integration/Register.lua`, not in the module** (CONTRACTS §4: panel modules never reach
into DragonUI internals directly), and **it takes the CONTENT frame while selecting the ANCHOR.** That
is the trap the seam exists for. `RegisterHUDFrame` registers the `CreateUIFrame` anchor as the editable
frame and hangs the viewer off it, so DragonUI's editor knows the anchor and nothing at all about the
viewer. Handing `SelectEditorFrame` a content frame would put the coordinate readout and the Reset
button on a frame the editor cannot move — and it would look like it worked. `.editorAnchor`, which
`RegisterHUDFrame` already set, is the bridge.

**Failure returns a reason instead of printing one**, because the caller knows where its message
belongs. Two of the three failure paths matter:

- **In combat.** `EditorMode:Show()` returns silently in combat — an empty branch, no message
  (`DragonUI/modules/editor_mode.lua:334`) — so a button wired straight to it appears to do nothing
  mid-fight. `OpenFrameEditor` re-checks `IsActive()` rather than trusting the call, and the explicit
  combat branch exists purely to name combat in the reason. That distinction is now asserted: without
  the branch the refusal still happens, but the player is told "editor mode declined to open", which is
  not actionable. A guard whose only product is a better message still needs a test that reads the
  message.
- **No `EditorMode` at all**, on a DragonUI build that predates it. Returns a reason; does not error.

**Per viewer, not once globally.** Upstream's version was a single cog-menu entry. Because DragonUI's
editor takes a frame to select, ours is a "Position this viewer" button inside each viewer's section, so
the one under Buff Bars' sliders opens the editor with Buff Bars selected. The panel closes only on
success — hiding first and then failing would take away the only surface the reason could appear on.

The fourth upstream ref, `RepositionHandle` (`CooldownViewer.lua:977`, re-anchor the drag rect as items
are learned), needs no port at all: `RegisterHUDFrame` syncs the anchor to the content's footprint from
the content's own `OnSizeChanged`.

### 2. §F1, `Cooldown:SetDrawEdge`

Open since Phase 0. The static evidence is strong enough to call it — ClassicAPI stubs the three
`SetEdge*` methods as "Incompatible (3.3.5)" but not `SetDrawEdge`, injects unconditionally rather than
filling gaps, and calls `GetDrawEdge` unguarded on every captured cooldown's OnShow — but that is an
inference from someone else's code, so `/necdm` now prints the runtime answer for the four cooldown
methods we care about. Both of our call sites guard regardless, so nothing depends on it; what changes
is that the question stops being open.

The probe frame is created on demand and cached, not at load: frames cannot be destroyed, so a
diagnostic-only frame should not exist on a character who never runs the diagnostic.

`/necdm` is also now smoke-tested. It is ~70 lines of formatting that nothing else touches, and a bad
`select()` or a nil in a format string would otherwise surface only when someone reached for it to debug
something else — the worst possible moment.

### 3. 4b-1 vestiges

The "Spell list coming in the next step." placeholder outlived 4b-2 by four phases: still built, still
anchored, hidden on the first `RefreshLayout` and never seen again, with two live references keeping it
alive. Removed, along with the stub `RefreshLayout` body that painted it. The stub itself stays as a
genuine no-op, so a load failure in `SettingsCategories.lua` costs the grids rather than every
`SetDisplayMode` call.

Also corrected: `SettingsAssets.lua` now registers sheet 5684744 itself instead of relying on
`modules/spellbook/Assets.lua` having shipped it. The side-tab BODY has depended on that all along and
worked, because both files load from the same TOC — but the dependency was implicit and the harness was
quietly logging the sheet as unshipped. One path registered twice, not one file shipped twice.

### What is left, and it is not code

Three items, all needing the game rather than the harness:

- **§F4 taint.** The viewers are unsecure display frames with no attributes, so `SetPoint` during a live
  restack should be a non-issue — but "should be" is what §F4 asks to confirm, and only a combat restack
  confirms it.
- **§F5, whether four separate movers is tolerable** versus one grouped handle. An owner call with the
  frames on screen. The new per-viewer Position buttons make the four-mover shape easier to live with,
  which is worth re-judging before changing it.
- **In-game confirmation of 4b-4, 4b-5, 5a and 4c.** 1-3, 4b-1, 4b-2 and 4b-3 have had a pass; the four
  most recent phases have not. Every in-game pass so far has found something (§G.7.1, §G.7.2), and none
  of those faults were the kind an offline harness can reach — three of them were art and event-order
  problems visible only on a real frame.

---

# H. Phases 7-9 — the Tracked Buffs tab, retail theming, and the guide audit

Written after an in-game report ("Tracked buffs never shows anything") and a re-read of Wowhead's
current Cooldown Manager guide (`wowhead.com/guide/ui/cooldown-manager-setup`, updated 2026-06-16).
Consumables stay parked (§G.9).

## H.1. Phase 7 — the Tracked Buffs tab is structurally empty — **DONE**

**The report is not a rendering fault. The tab cannot ever show anything.**

`store().trackedAura[CLASS]` is an OVERRIDE registry, and its header says so: "It starts EMPTY by
design: the auto window provides the defaults, this is the override registry"
(`CooldownViewer.lua:534`). The Auras tab renders that registry and nothing else — all three of its
categories are one filtered pass over the same list:

```
trackedBuff -> entries with assignment == "icon"
trackedBar  -> entries with assignment == "bar"
hiddenAura  -> entries with assignment == "hidden"
```

The only writer is `M.SetAuraAssignment`, whose only caller is `Adapter.Assign` — reached by dragging
or right-clicking **a row on that tab**. So the registry is a store whose sole editor is a view of the
store: nothing can enter it, because entering requires a row that only entry could create. Three
empty sections, forever, on every character.

**It disables a second feature too.** `ScanTargetTrackedAuras` deliberately honours explicit
assignments only, never the auto window (`BuffViewers.lua:171`) — which is the right call, since
auto-tracking every debuff on your target would be noise. But its input is the same unreachable
registry, so **target DoT tracking has never been reachable either.** The guide lists DoT timers as a
headline feature.

Note what is NOT broken: the buff *viewers* work. The auto-track window drives them off a live scan
that never consults this registry, so Buff Icons and Buff Bars have been showing procs correctly all
along. The bug is confined to the picker and to overrides.

### Why upstream doesn't have this bug, and we do

Retail's Buffs menu lists a Blizzard-curated per-spec aura set from `C_CooldownViewer` — the guide's
categories are populated before the player touches anything, and the comments complain about exactly
that ("You can only pick from the list Blizzard feels are the relevant abilities"). Upstream on Era
has no such data either, so it drives the viewers from the auto window — but it also never had to make
the *picker* work, because §G.4 cut its Group Buffs tab and its aura tab inherits the same emptiness.
We shipped the tab; the data source was never built.

### 7a. A seen-aura registry (the fix)

`rebuildFromAuras` already walks every player buff on `UNIT_AURA` and asks `ShouldTrackBuff` about
each one. Record what it sees:

```
store().seenAura[CLASS] = { [spellID] = { name =, icon =, duration =, last = <GetTime()> } }
```

- **Recorded before the include/exclude decision, not after.** An aura the player has hidden must stay
  in the list or Hidden becomes a one-way door — hide it, the row vanishes, and there is nothing left
  to unhide.
- **Record the name and icon, not just the id.** `GetSpellInfo(spellID)` fails for auras whose id the
  client doesn't know, and a nameless row cannot be searched or labelled.
- **Cap it** (~60/class) with eviction by `last`. Unbounded, a long-lived character accumulates every
  proc, trinket and consumable buff it has ever carried into a SavedVariables table that is also
  copied into every layout snapshot (§G.11).
- **Bound it by the same window the auto-tracker uses**, so permanent toggles and hour-long food buffs
  never enter — matching the guide's "does not track out-of-combat buffs such as food buffs, phials
  and flasks, world events, zone buffs".
- Cost is one table write in a path that already runs, gated on `last` being stale enough to bother.

### 7b. Category contents become "override ∪ seen"

`Adapter.GetItems` for an aura category returns explicit entries as today, plus seen auras with no
explicit assignment routed by the auto-track destination (`M.AutoTrackDest`): `both` puts a row in each
of Tracked Buffs and Tracked Bars, `icon`/`bar` in one. That makes the tab a description of what the
bars are actually doing, which is what a player opening it is asking.

Auto rows need to read as auto — retail has no equivalent because its list is curated, so this is ours
to design. Cheapest honest option: the existing unlearned-tint machinery already proves per-tile state
is easy; a tooltip line plus a subtle desaturation is enough, and `_applyAlertBadge` shows where a
corner badge would go if that reads better in practice.

**Dragging an auto row is what makes it explicit.** No new write path: the drag already calls
`SetAuraAssignment`, which is exactly "stop auto-deciding this one".

### 7c. An empty state, not three "(empty)" sections

A character who has not had a short buff yet should get one line — "Buffs you've had appear here.
Nothing tracked yet." — rather than three empty headers, which is what the report describes and reads
as broken. §G.9 already established the pattern for this (an empty *source* pool is skipped outright
rather than shown empty); the same judgement applies.

### 7d. A generated per-class aura catalog (the retail shape)

**Promoted from optional to primary by the owner, and built first** — which reverses the ordering
argued below. See §H.1.1 for what the data turned out to be.

7a-7c fix the tab with zero new data, but they are retrospective: the list is what you have had, not
what you *can* have. Retail's is a catalog. The same generator that produced `CdmArsenal.lua` can
produce one: `Spell.dbc` effect `ApplyAura` + a duration via `DurationIndex` → `SpellDuration.dbc`,
filtered to the class's own spells and to durations inside the auto window.

Two unknowns, both the kind §E3 already solved once: the effect and DurationIndex column positions
(locate empirically against known anchors, never assume), and whether a self-buff can be distinguished
from a debuff by effect target without guessing. Worth a spike before committing, and strictly after
7a-7c — a catalog is a nicer picker, but the empty tab is the bug.

### Verification

- Offline: assert the tab is non-empty after a simulated `UNIT_AURA` carrying one short buff; assert a
  hidden aura stays listed under Hidden (the one-way-door regression); assert the cap evicts oldest
  first; assert `ScanTargetTrackedAuras` now has reachable input.
- Negative: remove the "record before the decision" ordering and the Hidden test must fail.
- In-game: log in, take any short buff, open `/cdm` → Tracked Buffs.

### H.1.1 What shipped, and what the data turned out to be — **DONE**

Built as one phase rather than 7a-7c-then-maybe-7d: the owner asked for the catalog up front ("It
should be curated for spec, I think its worth generating a catalog"), which makes 7d the primary
source and the seen registry the safety net rather than the other way round.

**The two unknowns the plan flagged were both answered by measurement, and the first answer was
wrong in the way that matters.** `locate()` — one column per anchor set, ambiguity is a hard error —
reported *no* match for `DurationIndex` and `Effect[0]` on the first run. The columns were right
(40 and 71); the ANCHORS were wrong. Bloodrage has no duration of its own, because its aura lives on
the spell it triggers (`29131`), and its first effect is ENERGIZE rather than APPLY_AURA. Anchoring on
a spell that looks ordinary and is not would have "disproved" two correct columns — which is the whole
argument for locating rather than assuming, arriving from the opposite direction to the usual one.

Located, each proved against 3-6 independently-known anchors: `DurationIndex` 40, `Effect[]` 71-73
(contiguity checked, not assumed), `EffectImplicitTargetA[]` 86, `EffectApplyAuraName[]` 95,
`EffectTriggerSpell[]` 116, `SkillLine.Name` 3, `TalentTab.ClassMask` 20 / `OrderIndex` 22.

**Self-buff vs debuff was answered by effect target, as hoped:** `EffectImplicitTargetA == 1`
(UNIT_CASTER). No guessing needed.

**Three filters the plan did not anticipate, all found by reading output:**

- **Channelled spells read as buffs.** A channel's duration sits in the same column as an aura's, so
  Blizzard, Evocation, Mind Control, Tranquility and Arcane Missiles all arrived as 3-60s "self
  buffs". `AttributesEx & 0x44` (CHANNELED_1 | CHANNELED_2) separates them, verified clean across 19
  spells in both directions.
- **The skill-line class vote drags in `GENERIC (DND)`.** resolve.py's majority vote is fine there
  because its >1.5s cooldown filter hides the collateral; here it produced Grovel and Honorless
  Target for every class, from skill line 183, whose rows carry a class mask of 0 and vote ~10% for
  each of the ten classes. Fixed by preferring the per-ROW class mask and only falling back to the
  line's vote when the line is >=90% one class. Marksmanship (85 rows, all HUNTER) qualifies; the
  racial lines, First Aid, Cloth and Engineering do not.
- **A racial can wear a class mask.** Blood Fury's SkillLineAbility row carries a WARRIOR bit, so it
  survived the rule above and would have been offered to every warrior alive. Race-gating is not
  something a per-class catalog can express, so the six racial skill lines are excluded outright and
  the generator's verify pass now asserts no racial reached the output. Racials are covered by the
  seen registry instead, which is exactly what a safety net is for.
- **A floor as well as a ceiling.** Heroic Fury's aura lasts 100ms: real, self-targeted, inside the
  window, and unreadable as a bar. Anything under a second is a mechanic, not a buff.

**Spec attribution beat the plan's own idea.** §H.1 proposed a per-class catalog; what shipped is
per-TALENT, which on this client is strictly better — it follows respecs and dual spec, where a
static per-spec list cannot. `Talent.dbc` → `TalentTab.dbc` gives each talent's class and tree, and
the runtime asks `GetTalentInfo` whether the player actually has it. 96 of 162 rows are gated.

The tie-break that decides it was settled by measurement rather than by argument. An aura is often
reachable BOTH as a talent's triggered proc AND as a row in a class skill line — the client indexes
Lock and Load under Survival, Improved Steady Shot under Marksmanship — so "it is in a skill line" is
not evidence of being baseline. Preferring the ungated reading left HUNTER with 1 gated row out of 18.
Preferring the talent reading was checked by printing all 35 both-ways conflicts and reading them:
every single one is a genuine talent (Fingers of Frost, Bloodsurge→`Slam!`, Arcane
Concentration→Clearcasting, Martyrdom→Focused Casting, Ice Barrier, Metamorphosis, Flurry). Not one
false gate, so the rule is empirical, not merely plausible.

**The gate fails OPEN.** An empty talent table means the API has not answered yet — early login, or a
build without the globals — not that the player has spent nothing. Reading it the other way would hide
every gated row and reproduce the exact bug this phase exists to fix. Confirmed by mutation.

**Matching became name-based, which is the catalog's price.** A catalog row holds the rank-1 id; the
aura the player gets is whatever rank they cast. So `GetBuffOverrides` now keys include/exclude by id
AND by lowercased name in the same table (numbers and strings cannot collide), `ShouldTrackBuff` takes
an optional trailing `name`, and `ScanTargetTrackedAuras` accepts both key types. This also fixes a
pre-existing latent fault: before, an aura assigned at one rank and re-cast at another silently stopped
matching. `ScanTargetTrackedAuras` had already been forced into name matching for DoTs; this makes it
the rule rather than the exception.

**Where an unassigned candidate lands depends on what is actually happening to it** (7b): with
auto-track on it appears wherever `AutoTrackDest` sends it, marked `auto` and desaturated; with
auto-track off it appears under **Hidden**, because that is the truth and it gives that section a
purpose beyond force-excludes. Dragging one out is what makes it explicit — no new write path, since
the drag already calls `SetAuraAssignment`.

**Show Unlearned is reused rather than twinned.** It already means "show me what I cannot use yet" for
spells; a second setting saying the same thing about auras is how a settings page stops making sense.
A revealed spec-gated row tints red and its tooltip names the talent required, because "Not yet
learned" on a proc you can only get by respeccing is not actionable.

**A test that proved nothing, twice.** The one-way-door assertion — a hidden aura must stay listed —
passed with the guard removed, so the guard looked decorative. It was the test: `ResetTracking`
rebuilds the shown viewers itself, so the aura was scanned and recorded while the pool was still empty,
before the hidden assignment existed. Fixed by clearing the auras first, resetting through `settle`
(NE.aura caches its snapshot per frame, so a same-frame rebuild re-reads auras that are already down),
and only then raising an aura that was hidden before it was ever seen. All five new guards are now
confirmed by mutation: the record-before-decide ordering, the fail-open gate, name matching, candidate
dedupe, and the aura/equip tile dispatch.

**Known limitation, deliberate:** a newly seen aura does not appear in an open picker until the next
refresh. The panel does not listen to `UNIT_AURA` — it is the hottest event in the game and
`RefreshLayout` rebuilds every grid — and with a catalog carrying the list, a row arriving a tab-switch
later is a nicety rather than the feature.

**Also worth knowing:** the offline harness keeps its own file list, separate from the .toc. The
catalog was in the .toc and passing for a whole run before I noticed the harness had never loaded it —
`GetAuraCatalog` was returning `{}` and every assertion was green. A file added to one and not the
other is silently untested.

## H.2. Phase 8 — theming, to match retail

**The core finding: the art is already asked for, and nothing ships it.** Three atlases are set by name
in the viewer code and registered nowhere, so every `SetAtlas` returns false and the region renders as
nothing at all:

| Atlas | Sheet | Used by | Effect of its absence |
|---|---|---|---|
| `UI-HUD-CoolDownManager-IconOverlay` | 6704514 | `ItemMixins:38`, `AuraItemMixins:178`, both `BuffViewers` item shapes | **No icon frame.** This is why the icons read as bare spellbook icons rather than Cooldown Manager tiles — the single biggest visual difference |
| `UI-CooldownManager-OORshadow` | 6685874 | `ItemMixins:39` | No out-of-range shading |
| `UI-HUD-ActionBar-GCD-Flipbook` | 5199404 | `ItemMixins:46` | No ready-flash (guarded by `HasAtlas`, so it silently no-ops) |

Every BLP is already on disk in `ReferenceAddons/NewEra/Art/Common/`, alongside two more the port never
wired: `6731092-ui-hud-cooldownmanager-icon-swipe` and `5423465-ui-hud-actionbar-secondarycooldown`.

**Why they were missed:** upstream only needs `RegisterLocal` on the sheet FDID at the CALL SITE.
Classic Era ships the atlas *names* in client data even when the art differs, so `C_Texture.GetAtlasInfo`
supplies the rect there. 3.3.5a has no atlas database at all, so our port must supply both — and for
these three, only the `SetAtlas` calls were ported, not the data behind them. Nothing errored, because a
missed atlas is an invisible texture.

**CORRECTION (found while building 8a):** the sentence above originally read "upstream never registers
rects for them". That is false, and it mattered — `Generated/AtlasData.lua` carries rects for all six,
and they are NOT full-file rects. 6704514 is a shared 256x128 sheet with the icon overlay in its left
third and the three bar pieces down its right, so the 0→1 rect this section guessed at would have
stretched the overlay across the bar art. The rects were transcribed from that file and then verified
arithmetically against each BLP's real dimensions; see §H.2.1.

### 8a. Ship and register the art — **DONE**

Copy the BLPs to `Textures/CooldownViewer/`, `RegisterLocal` each FDID, and add the rects. The rects
must be **derived, not assumed**: each of these is a single-purpose sheet, so a full-file 0→1 rect is
likely, but "likely" is how you ship a texture stretched to the wrong aspect. Decode each BLP for its
real dimensions first (`node` + ImageMagick, per the repo's BLP workflow) and record the measured size
as the atlas `width`/`height`.

Harness: `HasAtlas` assertions for all five, mirroring the side-tab-art assertions that caught
`core/Tabs.lua`'s stale "sheet not shipped" note. That check is exactly what would have caught this.

### H.2.1 What 8a actually took

Shipped as `modules/cooldownviewer/Assets.lua` (the viewers' art; `SettingsAssets.lua` remains the
/cdm window's own) plus three BLPs under `Textures/CooldownViewer/`. **Six** atlases, not three — the
three bar pieces `AuraItemMixins` sets on the BuffBar were unregistered for the same reason and live on
a sheet 8a ships anyway, so registering them was three lines. What remains of 8d is the visual
judgement (nine-slice insets, colour), not the data.

**The rects came from upstream's generated data, and the check that matters is that they belong to the
sheets WE ship.** Each BLP's header was read for its real dimensions and the rect fractions multiplied
back out: every product lands on the declared atlas size to the pixel (6704514 = 256x128 → 86x86,
124x10, 132x19, 10x46; 6685874 = 512x1024 → 43x43; 5199404 = 2048x1024 → 94x517). The harness now
asserts that arithmetic, and mutating the overlay rect to 0→1 fails it with "rect gives 256.0x128.0,
declares 86x86" — the precise mistake this section had been braced for.

That check is also the guard against the failure `SettingsAssets.lua` records: retail repacked sheet
7289697, so Era-generated rects were wrong for the 12.1.0 BLP. Transcription alone would not have
caught it; transcription plus arithmetic does.

**Size:** 10.5MB for three sheets, of which 8.4MB is the GCD flipbook (2048x1024 uncompressed ARGB for
a 94x517 strip). Kept whole rather than cropped and re-encoded: the repo already ships 861 BLPs / 237MB
including a 16MB roleicons sheet and 4MB Professions flipbooks of exactly this kind, so cropping would
be a bespoke BLP *encoder* and a divergence from upstream's rects, in service of a size this repo does
not treat as a problem.

**One behaviour change, and it turns on code that had never run.** Registering the flipbook flips
`hasFlipbook()` true, retiring the fallback ready-flash burst in favour of the 22-frame sprite stepper
— a path dormant since Phase 1 because the atlas it gates on was never registered. Its frame maths is
consistent with the art (94/2 = 517/11 = 47), and the harness now drives the stepper at four points
across the flash and asserts each texcoord is inside the strip, exactly one cell, and grid-aligned. If
it still looks wrong in game, deleting the one flipbook registration reverts to the fallback with no
other change — the fallback was written as a permanent alternative, not a stopgap.

**Three harness stub gaps, found because 8a made real code paths reachable.**
`NE.tex.SetAtlasOnStatusBar` had never executed — it bails when its atlas is unknown — and the moment
the bar atlas was registered it hit `SetAlpha` on a string. The stub's `GetStatusBarTexture` returned
the *path* it had been handed; the real API always returns a texture OBJECT. That one is worth noting
beyond the harness, because `AuraItemMixins:193` anchors the Pip to that return value. Also added:
`GetMinMaxValues`, `GetVertexColor`, `GetStatusBarColor`, `hooksecurefunc`, and texcoord recording.

**THE FIT, found on the first in-game look at 8a.** With the overlay finally visible, the icons read as
too large for their frames — the reported words were "the icons are just too large and so sit outside
the new framing", and they were exactly right.

The cause is the other thing the removed MaskTexture was doing. Retail anchors the Icon with
`setAllPoints` and masks it with 6707800; it is natural to read that mask as "rounds the corners", but
decoding it shows its outer **3px of 64 are fully transparent**. So it also insets the icon by
3/64 = 4.7% on every side, and only then rounds what is left, at a corner radius of 4/64.

§C2 recorded that the mask could not be polyfilled and the port moved on. What went unnoticed is that
the *inset* needs no mask at all — it is an anchor offset. In tile coordinates, for a 50px Essential
tile:

| | spans |
|---|---|
| IconOverlay's crisp border line | 2.07 .. 4.44 (art x 14-19 of the 86px cell, through the -9/+8 anchor) |
| a MASKED icon (retail) | 2.34 .. 47.66 — edge sits inside the border band, so the frame overlaps it |
| an UNMASKED icon (ours) | 0 .. 50 — overshoots the line by ~4px into the soft halo |

Fixed with `M.AnchorMaskedIcon` (ItemMixins.lua), applied to all four tile shapes. The corner rounding
is still absent and turns out to be the cheap half: at radius 4/64 a square corner overshoots the arc
by 4*(1-1/√2) = 1.17px of 64, under a pixel on a real tile. The four missing pixels of inset were the
whole visible problem.

The harness asserts the border line lands ON the icon's edge, derived from the art rather than
restated, and the magnitude is mutation-checked as well as the presence — 1/64 instead of 3/64 fails.
This was unassertable before: the stub discarded texture anchors entirely, so a texture's geometry
could not be seen. It records them now.

**SECOND PASS, from the next look in game: "still 1px too large in all directions", and the swipe
"sits at the old icon sizes".** Both right, and they are two different faults.

*The swipe* was mine to have caught. Upstream anchors the Cooldown, the out-of-range shade and the
flash to the TILE with `setAllPoints`, and I kept that, reasoning that retail's mask only masks the
Icon. It does — but retail's swipe and shadow are themselves rounded art cut to the masked icon, while
ours are the engine's plain sweep, a flat shade and a squarish sprite. At tile size each one draws
proud of the inset icon and re-advertises the old footprint. All three now anchor to the icon's rect;
this is a deliberate divergence from upstream's anchors, for a reason that only exists on this client.

*The pixel* is the more interesting one, because the mask value was not wrong. Re-measured, the mask's
edge is HARD — texels 3..60 of 64 at alpha 255, nothing in between — so 3/64 is exact, not a reading off
a ramp. What was wrong is that the mask is SQUARE while the overlay is anchored **±9 horizontally and
±8 vertically**, so the border band sits at a different tile offset per axis:

| tile | axis | border band | mask inset alone | +1px |
|---|---|---|---|---|
| essential | x | 2.07..6.02 | 2.34 in | 3.34 in |
| essential | y | 2.74..6.58 | 2.34 **out** | 3.34 in |
| utility | y | 1.51..3.84 | 1.41 **out** | 2.41 in |
| buffIcon | y | 1.79..4.93 | 1.88 in | 2.88 in |
| bar icon | y | 1.51..3.84 | 1.41 **out** | 2.41 in |

On three of the four shapes the icon's top and bottom edges were outside their band — the icon
overshot the frame line vertically while sitting correctly inside it horizontally, which is precisely
"1px too large in all directions" to look at. `M.ICON_ROUNDING_INSET = 1` puts every shape inside the
band on both axes, and it is kept as a SEPARATE constant from `ICON_MASK_INSET` because it is a
judgement (it also absorbs our square corners reading harder than retail's rounded ones), not a
derivation. Mutating it to 0 fails the vertical assertion specifically.

**The harness had checked one axis.** The first version of the fit assertion derived the band from the
art and compared the horizontal one only, so it went green with the vertical edges still outside. It
now checks per axis, and separately that each icon-space overlay shares the icon's rect — the
assertion the swipe fault needed. Four mutations confirm the lot.

**And a note on the ready flash, since it reads as unchanged.** The retail GCD flipbook is a thin pale
rounded-square OUTLINE that traces the tile edge over 22 frames — not a burst. It is genuinely subtler
than the gold expanding highlight it replaced, so "that still looks like the fallback" is a fair
reading of a correctly working sprite. `/necdm` now reports which path is live, so the question is
answerable without guessing.

**A generalised assertion, because the specific one would not have caught the original fault.** Listing
six names and checking each is registered only tests the names someone thought to list — and the fault
was six names nobody had listed anywhere. So the harness reads the atlas names back out of the viewer
sources (skipping comment lines, since these files also name atlases in prose to explain why they are
absent) and requires every one to resolve. A seventh `SetAtlas` added later fails without anyone
remembering to update a list. First attempt at this matched on the function name and found 3 of 6: the
call sites go through a local alias, `local set = NE.tex.SetAtlas`.

### 8b. The cooldown swipe

§C3 recorded `SetSwipeTexture` / `SetEdgeTexture` / `SetUseCircularEdge` as MISSING. That was right
about the native widget and wrong about the platform: **ClassicAPI implements `SetSwipeTexture` and
`SetUseCircularEdge`** over a four-quadrant ScrollFrame capture rig (`Util/WidgetAPI.lua:1076-1135`,
`Util/Cooldown.lua`), and only `SetEdgeTexture`/`SetEdgeColor`/`SetEdgeScale` are stubbed as
"Incompatible (3.3.5)". So the retail radial sweep is reachable.

It is not free: the rig builds five frames and a rotating animation per cooldown, and it hijacks
`SetAlpha` on the Cooldown frame. Wire it behind a setting, default on, measured on a full Essential
row before it is trusted — §C3's caution was about the wrong thing but it was not baseless.

### H.2.11 The 8b measurement — **DO NOT ADOPT** (investigated, declined)

The plan above set the gate: *measured before it is trusted*. Measured. It should not be wired, and
"default on" would have been actively wrong. Five findings, in descending order of how decisive:

**1. It deletes the countdown numbers.** `CooldownCaptureShow` calls `SetCooldownAlpha(Self, 0)` on
the Cooldown frame to hide the native sweep it is replacing (`Util/Cooldown.lua:210`). Our countdown
FontString is created ON that frame (`core/CooldownNumbers.lua:151-156`, deliberately — "parented to
the cooldown itself so it inherits the cooldown's show/hide and frame level"), and frame alpha is
inherited by regions. So the timer reads alpha 0 for the entire cooldown, restored to 1 only in the
bling branch as it ends. The number on the tile is the single most important thing a Cooldown Manager
draws, and this rig turns it off for exactly the interval it matters.

**2. Zero callers, anywhere.** `SetSwipeTexture` is invoked by nothing in the whole AddOns tree
outside ClassicAPI's own definition of it. This is not a well-worn path with a known quirk; it is
unexercised code, and we would be its first user on this client.

**3. The cost is ten frames per Cooldown, not five.** `CooldownCapture` builds the Swipe (1), four
quadrants that are a ScrollFrame *plus* an Anchor frame each (8), and the Wedge (1) — plus an
AnimationGroup and a Rotation. With `DrawEdge` on, two more frames and another AnimationGroup. At our
defaults (Essential 12, Utility 7, plus the BuffIcon pool) that is roughly 190-250 frames for a
feature the client already draws natively.

**4. It fights the icon inset.** `Swipe:SetParent(Self:GetParent())` then `Swipe:SetAllPoints(Attach)`
anchors the sweep to the TILE, not to the Cooldown's icon-inset rect. That reintroduces precisely the
artefact §H.2.7 removed — a sweep sitting proud of the icon, betraying the larger footprint.
Workaroundable by re-anchoring `cd._Swipe` after capture, but that is reaching into ClassicAPI's
internals to undo its own layout.

**5. And the headline capability is not what it looks like.** `SetSwipeTexture(path, ...)` forces
`SetVertexColor(0, 0, 0, .65)` on all five textures and discards the r/g/b/a you passed
(`Util/WidgetAPI.lua:1128-1136`). Retail's swipe art therefore comes through as a black 65%
silhouette — which is what the native 3.3.5a sweep already is. We also do not ship 6731092, and
Assets.lua deliberately did not ("shipping art ahead of the code that uses it").

**What the rig genuinely adds is one thing: `SetSwipeTexture("", r, g, b, a)`, a solid COLOURED
sweep.** That is the capability §C3 and 8c wanted and could not have, because `SetSwipeColor` is
WoD+. But 8c already shipped a substitute for it — the static gold halo (§H.2.2) — and the owner has
it in game and approved it. So the one real gain is a second solution to a solved problem, bought
with ~200 frames, a hijacked `SetAlpha`, an unexercised code path and the loss of the timers unless
two pieces of shared code are reworked first.

**Decision: keep the native sweep.** §C3's original answer — "accept the engine's built-in sweep" —
was right, for a better reason than it knew.

If the gold *swipe* is ever wanted over the gold *halo*, the shape of that work is recorded here so
it does not need re-deriving: reparent `_neText` off the Cooldown frame, re-anchor `cd._Swipe` to the
Cooldown's own rect, enable capture only on tiles whose aura is up, and leave every other tile on the
native sweep. It would be opt-in and default off.

### 8c. The glow on a buffed spell — **DONE**

The guide's second headline feature: "Tracks combat buffs and puts glow effects around buffed spells."

We have half of it. `ItemMixins:568-580` already gives an active self-aura precedence over the
cooldown, showing the aura's remaining time on the spell's own icon — the behaviour one commenter
describes on Keg Smash. What is missing is the visual distinction: retail tints that swipe gold, and
`SetSwipeColor` is WoD+ (the file says so at line 13).

LibCustomGlow is already a dependency and already drives the alert FX (§E6), so a glow while a linked
aura is active is a small, contained addition — and it substitutes for the colour we cannot set rather
than approximating it.

### H.2.2 What 8c shipped, and why it is not LibCustomGlow

The plan above nominated LibCustomGlow because it was already there. Building it made the objection
obvious: **every glow that library renders moves.** Marching ants, a pulsing button glow, orbiting
sparkles — and on this addon motion already has a meaning. It is the alert vocabulary (§E6): something
needs attention *now*. "Your buff is up" is a steady state, and retail draws it as one, with a flat
gold swipe tint. Reusing the alert language for it would make every buffed spell read as an alarm, and
would collide visually with a real alert on the same tile.

What shipped instead is a **static gold halo on the tile**: one texture, no OnUpdate where the lib's
renderers each drive one, and no possible collision with an alert glow because it is not the same
mechanism.

#### The first version rendered nothing, and the art says why

It drew a gold additive copy of the tile's **own `IconOverlay` art**, in the same rect — the reasoning
being that lighting the existing frame would align to the pixel at both tile sizes for free, with no
constant to get wrong. Reported from the game as "I dont see this in effect", and it was not a wiring
fault. Decoding the cell:

```
mid-row across the left border, 6704514 overlay cell (86x86 at 1,1):
  x0..13  (0,0,0) a1 -> a48        the soft outer falloff
  x14     (0,0,0) a104             the "crisp border line" 8a measured
  x15..19 (0,0,0) a93 -> a7
  x20+    (255,255,255) a0         fully transparent interior
cell texels with alpha>8: 2795;  mean effective luminance: 0.0 / 255
```

**Every texel is pure black.** The frame is a *drop shadow*, not a metal border — the "crisp line" 8a
found at art x14-19 is just where the black is least transparent. `ADD` blending emits `src.rgb x
alpha`, so a black source emits zero light no matter what vertex colour is multiplied over it. The
atlas resolved, the region was shown, the blend was `ADD`, the tint was gold, and the arithmetic
produced an invisible texture — 8a's exact failure mode reached by a completely different route.

The replacement is `Interface\Buttons\UI-ActionButton-Border`, the stock 3.3.5a soft-glow ring this
repo already uses for the bag rarity glow, the auction detail ring and the profession reagent slots
(`modules/bags/BagSkin.lua:29`). Its rect is **oversized by 35%** of the tile edge — the figure those
three call sites converged on, because the texture carries a wide transparent margin and at a tight
rect the visible ring falls inside the icon rather than on its edge. That is the reverse of the 8a
rule (anchor to the *icon* rect) and of the first version's rule (match the frame), so it is a
constant, `M.BUFF_GLOW_OVERSIZE`, with the reasoning next to it.

**What the harness now asserts is the source, not the mechanism.** Everything about the broken version
passed — atlas resolved, region shown, blend `ADD`, tint gold — because each of those was true. The
assertion that catches it is that an additive region is given art that can *carry* light, expressed
as: the glow's texture is the stock ring, and is not from the CoolDownManager sheet at all. Mutating
it back to a sheet path fails on exactly that line.

Deliberately **not** aura-only: the totem branch (`RefreshCooldown` 1b) glows too. A live totem is not
an aura, but it is the same state — this tile's effect is currently up — and that branch already
carries `COLOR_AURA` for exactly that reason. Glowing one and not the other would leave a shaman's
totem tiles as the only active tiles on screen that look inactive.

Two clears matter more than the light itself, and both are pinned by a named assertion:

1. **The cooldown path.** The aura branch returns early, so a glow left un-cleared there would stay up
   for the rest of the session. One `SetBuffGlow(false)` sits below both precedence branches rather
   than being repeated in each of the paths under it.
2. **The pooling loop** (`Viewers.lua`). `RefreshCooldown` returns early with no `spellID`, so nothing
   on the refresh path can clear a recycled tile — the next spell to reuse it would inherit a gold
   frame from the spell that used to live there.

Settings: "Glow while buffed" under a new **Buffed spells** section, default ON (it is a retail
feature, not an addition of ours). `SetBuffGlowEnabled` refreshes rather than waiting to be noticed —
turning it off has to reach a tile glowing *right now*, and for a buff already up the next natural
refresh can be a minute away.

`/necdm` reports the glow: on/off, the texture path, and how many of the shown tiles are lit right
now. The glow has two innocent ways to look broken — the setting is off, or nothing is currently in
the aura branch — and neither is distinguishable from a fault by looking. The first version added a
third, which is why the texture is named in the output.

Harness: 19 assertions, and two stub fidelity fixes — `SetBlendMode` and `SetDrawLayer` were both
discarding their argument, and both carry meaning here (without `ADD` the copy *darkens* the tile
instead of lighting it; without the sublevel it draws under the art it is meant to light). Seven
guards confirmed load-bearing by removal, each failing on its own named assertion: the aura-branch
light, the cooldown-path clear, the pooling clear, the setting's live refresh, the additive blend,
the glow's source art, and the oversized rect.

### H.2.3 The in-game pass on 8c — four bugs and two features

Six items off one session in the game. Two were about 8c itself, two were older faults that 8c's
attention surfaced, and two were features the port had simply never had.

**The glow was drawing over the icon** ("icon glow effect inside frame"). `UI-ActionButton-Border` is
not a hollow ring — it is a filled square glow, brightest near its edge — so drawn over the tile it
washes light straight across the icon art. Fixed by DRAW LAYER rather than by geometry: the region
moved to `BACKGROUND`, where the opaque icon masks its interior and only the halo that reaches past
the icon survives. That is also the closest this client has to the mask it does not have, and it makes
the oversize forgiving — too small now shows less halo instead of veiling the icon.

**"Icons too large still and no rounded edges."** The third report on this, at the third value, which
is the signal that it is not a number to be found. The mask inset is faithful to retail and retail's
icon is ROUNDED; ours cannot be (§C2), and a square corner reads larger than its own edge does. So it
became a setting — with a measured ceiling. Decoding the overlay's aperture (the first fully
transparent texel inward of the border line) puts it at art 20 of 86:

| tile | anchor | aperture x | aperture y | as a fraction |
|---|---|---|---|---|
| essential 50px | -9/+8 | 6.81 | 7.35 | 13.6% |
| buffIcon 40px | -8/+7 | 5.02 | 5.24 | 12.6% |
| utility 30px | -6/+5 | 3.77 | 4.30 | 12.6% |

Inset that far and the icon clears the frame's opening entirely, so every square corner sits inside
the rounded aperture — the closest this gets to rounded edges, at the cost of a visibly smaller icon.
The slider spans from retail-faithful to that limit.

The correction inside the correction: the extra had to become a **fraction of the tile**, not flat
pixels. The frame art scales with the tile, so its opening does too, and a flat budget generous enough
for a 50px Essential tile pushes a 30px Utility icon clean through its own opening. The first draft
used flat pixels and the harness failed on exactly that — utility at 3.41 against an inner limit of
3.28. The invariant it now checks is not a value but a range: the frame always covers the icon's edge,
and the icon never shrinks past the opening, at every legal setting on every shape.

**Prayer of Mending showed the 30s buff, not the cooldown.** Retail puts the aura's remaining time on
a buffed tile because tinting that swipe gold is its ONLY way to say "buffed" — it has no spare
channel. Since 8c we do, so the number is free to be the useful one. Aura precedence became a setting
defaulting to the cooldown, and the glow carries the signal on both settings. This is the first thing
8c has paid for rather than cost.

It also moved a guard. `SetBuffGlow(false)` used to sit below both precedence branches, on the
reasoning that everything past them meant "no effect of ours is up" — which stopped being true the
moment the timer became optional, since a genuinely buffed spell now falls straight through to the
cooldown path. One call above both branches covers both readings.

**Old-spec abilities stayed in the window until touched.** Nothing the viewers listened for fires on a
talent-group change, and any interaction that rebuilt a viewer hid it. `ACTIVE_TALENT_GROUP_CHANGED`
and `PLAYER_TALENT_UPDATE` now rebuild and invalidate both the curated-list cache and the talent gate.

**Per-spec layouts (new).** Dual talent specialisation is a 3.1 feature this port had ignored: one
character genuinely wants Mind Blast on Essential in Discipline and not in Holy. The three tables that
describe a layout — spell lists, aura assignments, trinket placement — moved into a per-talent-group
bucket. Deliberately NOT bucketed: `seenAura`, which is knowledge rather than layout (an aura met in
Holy is still an aura this character can get), and everything under `frames`, since a viewer that
jumped across the screen on a respec would read as broken — retail's Edit Mode is not spec-aware
either. Keyed by talent GROUP, not by inferred spec name: the group is what the client actually gives
us, and inferring "Discipline" from the heaviest tree would be a guess that changes mid-levelling and
collides outright when two groups share a tree.

The harness caught a real one here. The first draft stored buckets under `cd.layouts` — which is
already SettingsPresets' saved-layout table, so `ResetTracking` silently deleted every layout the
player had saved. Renamed to `specLayouts`, with an assertion that a saved layout survives a tracking
reset.

**New buffs are hidden by default (new).** Auto-track flipped OFF. A newly met aura is still recorded
and still listed under Hidden — discovery is worth keeping — but nothing reaches the screen until it
is assigned. On by default meant a raid arrived as other people's cooldowns, food and flasks on a
viewer the player had carefully curated.

Harness: 519 → 565. Two stub fidelity fixes: `CreateTexture` was discarding its LAYER argument, so a
region created on the wrong layer was unassertable, and `SetDrawLayer`/`SetBlendMode` now record.
Eight guards confirmed load-bearing. Two mutations came back green first time and both were the test's
fault, not the guard's: the spec-swap test set its scene with `SetSpellEnabled`, which rebuilds the
viewer itself, so the scene-setting was doing the work the event was meant to do; and the glow-layer
test could not see `CreateTexture`'s argument at all. Both rewritten, both now load-bearing.

### H.2.4 The frame is an inner shadow, and that inverts the icon fit

"It looks like the icon border is missing?" — after a pass whose whole point was to make the icons fit
their frames better. Rendering the overlay cell instead of measuring it in columns explains it, and
overturns the rule three previous passes had been working to.

```
6704514 overlay cell, 86x86:  BLACK throughout, alpha only.
  dark core on a line at art x=14, peak alpha 108/255 = 42%
  soft falloff outward to x=0, fading inward to 0 at x=20
  corner radius of the core ~4 art px
```

It is an **inner shadow**, not a frame in the sense of a drawn border. A shadow shows only where there
is something beneath it to darken. So insetting the icon does not tighten the frame around it — it
slides the icon out from under the shadow, and black-at-42%-over-the-world is nothing at all. Every
round of "the icons are too large, inset them further" was quietly *deleting* the frame, and the last
one crossed the line where the dark core sat entirely off the icon.

|  | icon edge | dark core | band | covered |
|---|---|---|---|---|
| essential x, shipped default | 2.34 | 2.07 | 2.07 – 6.02 | 93% |
| essential x, at +4% (last pass) | 4.34 | 2.07 | 2.07 – 6.02 | **42%** |
| utility x, at +4% | 2.61 | 0.84 | 0.84 – 3.28 | **27%** |

The harness had this exactly backwards. Its assertion was that the icon's edge must land INSIDE the
border band — which is what drove the shrinking, and which is satisfied most comfortably by the
settings that hide the frame. It now asserts the opposite and measures it as **coverage**: how much of
the dark band has icon under it, ≥70% at the shipped default. "Some overlap" is not enough to
distinguish the two states — at +4% the Essential tile still overlapped the band, and that is the
state that was reported as missing.

So the inset default went back to 0 — retail-faithful — and its ceiling dropped to +4%, where the
shadow is weak but not gone.

**Frame strength** is the actual answer to both "the border is missing" and "no rounded edges". The
art tops out at 42% black, which reads as a bevel rather than a border, and its rounded corners are
far too faint to stop a square icon announcing itself. `SetAlpha` only scales down, so the alpha
cannot be raised — but the texture can be drawn more than once: stacking N copies gives 1-(1-a)^N, so
42% becomes **66%** at two and **80%** at three. Same art, same rect, same corner radius, just deeper,
and the corners deepen with it. Default 2, exposed as a 1-3 slider next to the inset.

This is the third distinct fault in this port traceable to reading a texture's *metadata* instead of
its *pixels* — after the six unregistered atlases (§H.2.1) and the black additive glow (§H.2.2). All
three were invisible to every assertion that checked wiring. Rendering the cell to a PNG and looking
at it took two minutes and would have pre-empted all three.

### H.2.5 The spec swap is an ORDER problem, not a staleness one

"Switched from Holy to Disc and can still see Circle of Healing. It only disappears when I try to
move it." The previous pass had already added `ACTIVE_TALENT_GROUP_CHANGED` handling, and it was
working — the fault is that it runs too EARLY.

`core/SpellRanks.lua` owns the learn gate's source of truth, and rebuilds its table on a **deferred**
timer (`C_Timer.After(0)`), because SPELLS_CHANGED bursts during login and talent swaps and a full
book walk is ~200 string matches. So the sequence on a dual-spec swap was:

1. `ACTIVE_TALENT_GROUP_CHANGED` fires; consumers refresh **from the old book**
2. `SPELLS_CHANGED` fires; a rebuild is queued for the next frame
3. next frame: the table catches up, and `SB._onRebuilt` fires

The viewers subscribe at step 3 (`Register.lua`), so they self-corrected. **The picker never
subscribed** — it refreshed at step 1 and then had no reason to look again. Dragging a tile refreshes
the layout, which is why interacting with it "fixed" it.

Three changes, and the ordering one is the real fix:

- `SpellRanks` now also rebuilds on `ACTIVE_TALENT_GROUP_CHANGED`. SPELLS_CHANGED does fire for a
  swap, but its order against the talent event is not guaranteed, and consumers refreshing on the
  talent event were reading a table that had not been told yet. The coalescing already there means
  the extra registration costs nothing when both arrive together.
- The settings panel subscribes to `OnRebuilt`, like the viewers do.
- The viewers' subscription also drops the talent-gate cache, which it should have been doing.

The test worth keeping is the one that models the ORDER rather than the outcome: fire the talent
event, assert the gate still passes (that is the stale window, and it is correct at that instant),
then drain the deferred timers and assert it flips — with no interaction. Written as "after a swap
the spell is gone" it would have passed against the broken build, because the harness drains timers
between most steps anyway.

One guard here is deliberately NOT load-bearing: the panel's own `InvalidateCuratedCache`. Register's
subscription runs first and already clears it — but "first" holds only while those two register in
their current order, and a refresh reading a stale cache is the exact failure this callback exists to
prevent. Noted in place rather than dressed up as verified.

### H.2.6 Halo alignment, and cut corners tried and rejected

"Is there any way to improve the alignment of the icon to the gold background?"

The halo was anchored to the TILE, which is the larger rect, so it sat wide of the icon it was meant
to be lighting. It now anchors to the **icon's own region**, which makes the two concentric by
construction and means it follows the inset slider without being told about it.

**Cut corners: attempted, and reverted at the owner's call.** "Can we make the corners not square? The
spellbook successfully does this." The spellbook does — and not by masking. §C2 still holds
(`CreateMaskTexture` is dead; `modules/spellbook/Spellbook.lua:160` says so outright). It covers the
corners with something **opaque**: its frame is solid metal with cut corners drawn over the icon's
edge, so the square underneath never shows.

That also explains why the previous pass's frame-strength work could not finish this. Our frame is a
translucent shadow, 42% at its darkest; stacking makes the corners *darker* and cannot make them
*absent*. No see-through texture hides a corner.

Building it confirmed the mechanism works — the square talent-node socket (`talents-node-square-gray`,
alpha 0 at the corner texel, 255 along the mid-edge) turns the tile into a clean octagon. Sizing had
one real decision, since its band is 13 texels of 80, 16.3% of the edge: flush with the icon costs
that much of the art around the rim, while growing it so its opening clears the art overhangs the
*tile* by the same amount and makes neighbouring icons collide. Flush was the better of the two, and
is what the spellbook itself does.

**Rejected on look** — the spellbook's socket is a heavier, greyer frame than the Cooldown Manager's
own art, and next to the CDM shadow it reads as a different UI. Reverted whole; the halo change was
kept. What this leaves on the table is that cut corners ARE achievable here — the blocker is art that
suits these tiles, not the technique. If retail's own CDM sheet turns out to carry an opaque frame
cell, that is the piece to look for.

### H.2.6 Two rejected passes at the glow, and where it actually stands

**Cut corners — built, reverted.** The spellbook makes square icons stop looking square without a
mask (§C2 holds; `CreateMaskTexture` is dead) by covering the corners with something OPAQUE. That is
also why frame strength could not finish the job: our frame is translucent, so stacking makes corners
darker and never absent. The square talent-node socket does work, and flush with the icon is the right
sizing — growing it so its band clears the art overhangs the tile by 16% and collides neighbouring
icons. Rejected on look: it reads as a different UI beside the CDM art. The blocker is art that suits
these tiles, not the technique.

**The flat edge ring — built, reverted.** Reported as "the glow doesn't align to the top or right hand
sides". The diagnosis was right and worth keeping: both glow versions were anchored symmetrically, so
the RECT was always centred; what was not centred was what you could SEE, because a soft glow's
visible extent is wherever its falloff survives whatever is drawn over it — here the frame shadow at
66% black across the whole border band. What escaped was a gold edge on the two sides where the shadow
had faded most.

The fix I built — four flat strips on the icon's rect, above the shadow and above the sweep — solved
the alignment completely and looked considerably worse: a hand-drawn rectangle where Blizzard's art
had been. Owner's verdict, and correct. **I optimised for the property I could assert over the one
that mattered**, and shipped it without rendering it first, having twice that same session established
that rendering the art was the thing that settled these questions.

**Where it stands, after the owner asked the obvious question I had talked myself out of:** on
`UI-ActionButton-Border`, anchored to the icon's rect, drawn at **OVERLAY sublevel 7** — on top of the
frame's shadow and its stacked copies.

It spent two passes on BACKGROUND because of a claim I made and never checked. When the halo was
first reported as appearing "inside the frame", I concluded the texture must be a FILLED square glow
that washes light across the icon, and moved it behind so the opaque icon would mask its middle. It is
not filled. It is a **ring with a transparent centre** — which the repo's own notes say in three
places, and which four other modules rely on by drawing this exact texture straight over an item icon;
`modules/professions/Crafting.lua:463` uses this precise layer and sublevel. The real cause of "inside
the frame" was the ring landing too far in, which is a SIZE question, and the oversize constant already
existed for it.

Having put it behind the shadow, I then diagnosed the shadow suppressing it as an inherent trade-off
between frame strength and glow evenness, and proposed knobs for balancing two things that never
needed balancing. The trade-off was manufactured by the previous mistake.

Kept from the reverted work: the harness now records frame levels. "This draws above that" was
unassertable, the same way `CreateTexture`'s dropped LAYER argument made "this draws behind that"
unassertable. Three stub parameters accepted and quietly forgotten have each now hidden something real.

### H.2.7 A sliver on one side: the inset was landing on a half pixel

Reported as icon art escaping to the left and right of the frame, and — the more diagnostic half —
"with the cooldown swipe the right hand side is great and the swipe covers the glow correctly. However
the left hand side the swipe doesn't cover the glow." Guessed at the time to be mask fallout. It is
not; it is arithmetic, and it is fixable.

The derived inset is fractional: `50 x 3/64 = 2.34375`. Anchored at that, the icon's left edge sits at
2.34 and its right edge at `50 - 2.34 = 47.66`, and the renderer resolves each to a whole pixel
**independently** — 2 on one side, 48 on the other. The two margins end up a pixel apart, against a
frame whose own anchors (+-9 / +-8) are integers. One side shows a sliver of icon and the other does
not.

The swipe follows exactly because it is *supposed* to: §H.2.1 pinned it to the icon's rect through the
shared helper, so it inherits the same split. Half a pixel is the entire difference between "covers
the glow" and "doesn't", which is why that was the clearest symptom of the two.

`M.IconInset` now snaps to whole pixels. Not "whole pixels at the current UI scale" — iconSize is
applied with `SetScale`, so a tile can sit at a fractional scale regardless, and chasing that needs the
effective scale at anchor time plus a re-anchor on every scale change. At scale 1, where this was
reported, integer offsets land on integer pixels on both edges.

Two harness changes fall out. The "inset is a fraction of the tile, not flat pixels" assertion — which
exists because a flat budget pushes a 30px tile through its own opening — would forbid snapping if
left as exact equality, so it now asserts the inset tracks the fraction to within half a pixel. And a
new one asserts the result is integral, on the tile AND on every region that shares its rect, which is
the property that actually fixes the artefact.

Retail's mask is not what we lost here. A mask clips an icon that was already anchored on whole
pixels; it does not centre anything. What we lost was the snapping, and that we could always have had.

### H.2.8 The glow was under the sweep the whole time

Four passes were spent on this glow, and every reported symptom had one cause.

**`Cooldown` is a CHILD FRAME of the tile, and a child frame draws above EVERY layer of its parent.**
BACKGROUND, OVERLAY 0, OVERLAY 7 — all of them are below it. The halo was under the rotating sweep no
matter which draw layer it was given, and the sweep is a *wedge*, so which part of the halo survived
depended on where the sweep had got to. Read back with that in hand, the reports are one fault:

| reported | actually |
|---|---|
| "icon glow effect inside frame" | the swept wedge covering part of the ring |
| "doesn't align to the top or right hand sides" | the wedge's current position, not an anchor |
| "the swipe covers the glow on the right but not the left" | said outright, and I read it as two faults |
| pixel-snapping "didn't fix anything" | correct: pixels were never this one's problem |

The third row is the uncomfortable one. The owner described the mechanism exactly, and I treated the
swipe and the glow as two separate misalignments to be reconciled rather than one drawing over the
other.

The fix is a **sibling frame with a higher frame level**, which is the only thing that outranks a
child frame. Art, blend and rect are unchanged from the version that was already there. Note this is
the same structural insight as the reverted flat-ring experiment (§H.2.6) — that version hosted its
strips in a frame *and* replaced the art, so when the art was rejected the insight went with it. It
was the frame that mattered.

What the detours were worth keeping: the region is on top of the frame shadow rather than behind it
(§H.2.6 — a ring with a transparent middle, not a filled glow), and the icon inset snaps to whole
pixels (§H.2.7 — a genuine artefact, just not this one).

The assertion that closes it compares the glow's frame level against the Cooldown's. A draw-layer
assertion could never have caught this, because the layer was never wrong in the terms it could see.

### 8d. Bar theming

The bar rows are functional: icon, name, depleting fill. Against retail they want the fill texture, the
spark, and the name/timer typography and alignment checked side by side. Lowest-confidence item here,
because it is the one that needs a screenshot comparison rather than a code reading — scope it after
8a, when the icons are right and the bars are the remaining mismatch.

### H.2.9 What 8d actually took

**Three of the four questions closed by looking, and the fourth was a real defect.** The owner's
screenshots (edit mode with looping previews, and a live Power Word: Shield mid-depletion) answered:
the fill IS orange, so `SetStatusBarColor` reaches the visible overlay through the `hooksecurefunc`
in `SetAtlasOnStatusBar` — worth confirming, because the engine's own bar texture is deliberately
alpha-0 and a missed hook would render a plain grey bar with nothing else looking wrong. The pip
reads as a spark, not the oversized blob its 10x46 cell suggested (the art is only ~6x30 inside it).
Typography and alignment match upstream's XML, which our Lua transcribes literally.

**The defect was `Bar-BG` stretching bodily.** Decoding the cell settles where it slices:

| cols | content |
|---|---|
| 0-7 | alpha 96, 253, 235, 220, 188, 179, 174, 173 — left cap, edge line at x=1 |
| 8-120 | alpha 173 flat, luminance 0 — uniform, safe to stretch by any factor |
| 121-131 | alpha 179..253 (edge line at x=126) then 172, 90, 35, 11, 5 — cap plus drop shadow |

The right cap is wider because the art's shadow falls down and to the right, which is also why
retail's anchors are `-2/+2, +4/-7` rather than symmetric. Stretched whole, the two 1px edge lines
smear: 1.47x at the 100% bar width, **3.1x at the 200% end of the width slider**. That last figure is
what the owner's screenshot was actually showing, since they had widened the bars for legibility.

**Horizontal only.** Vertically there is no flat band to slice — rows 3-11 run 209, 185, 165, 153,
153, 160, 173, 194, 228, a continuous bevel — so every piece stretches down the same constant 28/19
it always has. A nine-slice here would be inventing a seam. Cap widths therefore scale with the
region's HEIGHT, so widening the bar moves the extra pixels into the middle and leaves the corner
bevel uniformly scaled instead of squashed into an ellipse.

**`BarBG` is three textures on the bar, held in a plain table — not a child frame.** A child frame
draws above every layer of its parent (§H.2.8), so a `Frame`-based group would have put the
background over the fill, the pip and the name. The same rule, one phase later, in a place it could
have bitten again.

Two things the harness taught us:

* **A zero width is "not laid out yet", not "too narrow for caps".** The bar takes its width from its
  anchors, unresolved when the row is built, so the first call reads 0. Conflating the two collapsed
  every row to a single stretch until something happened to resize it. The guard also has to test the
  BAR's width rather than the padded region's — padding is +6, so an unresolved bar still reports a
  6px region and sails past a `regionW > 0` check.
* **`HookScript` in the stub replaced instead of chaining**, so the last hook on a script silently
  won — and these rows hook `OnSizeChanged` twice, once for the fill's texcoord and once for the cap
  widths. Fixed. It mattered: under the replacing stub the cap-width assertion passed **vacuously**,
  because nothing re-ran at all and "the caps did not change" is satisfied by doing nothing. The
  assertion now blanks the middle's texcoord first, so the re-apply is itself observable.

What 8d did NOT need: a retail comparison shot. Upstream's XML is vendored at
`ReferenceAddons/NewEra/CooldownViewer/CooldownViewer.xml` and our geometry matches it line for line,
so any mismatch had to be in the texture treatment rather than the numbers.

`/necdm` now reports the stretch factor the middle is carrying and the cap widths it is holding off.

### 8e. The pandemic ring

`Alerts.lua`'s `refresh` type is already upstream's `CooldownPandemicFXTemplate` in behaviour, tinted
pandemic-orange. The retail art (`PandemicFX-Icon01/02/03`, `PandemicFX-Bar`) is on sheet 6685874,
which 8a ships anyway. The two clip masks (7552325, 7553101) are unusable — §C2, `<MaskTexture>` cannot
be polyfilled — so the ring needs the unmasked art plus a crop, the same substitution the icons use for
their rounded corners.

### H.2.10 What 8e actually took

**The premise above was wrong, and decoding the cells is what showed it.** "The ring needs the unmasked
art plus a crop" assumed everything in retail's pandemic FX depends on the two clip masks §C2 rules
out. It does not. `UI-CooldownManager-PandemicBorder` is **already a hollow rounded-square ring**:
alpha 0 through the centre, material in two bands at cols 2-8 and 52-58 of 61, real RGB at full alpha
(peak 255,48,48). It needs no mask, no crop and no substitute. It is finished art, on a sheet 8a
already ships, and it ported as one atlas registration plus a texture.

This is the fourth time this phase that reading a texture's metadata instead of its pixels produced a
wrong plan — after the six unregistered atlases (8a), the black additive glow (8c) and the
shadow-vs-border frame (§H.2.5). The correction cost about ten minutes with `blp.js`.

**What genuinely needed the masks was the CASCADE, and it is the half that did not port.**
`PandemicFX-Icon01/02/03` are FILLED 128x128 quads (centre alpha 61/81/24), not rings — retail clips
them to the ring shape and *then* scales them 0.25 → 1.5. Unmasked they are square smears across the
icon and its neighbours, so those three atlases are deliberately **not** registered. `Animation:SetTarget`
is independently absent too, so the template's one-group-drives-three-textures structure has no
equivalent regardless.

**Substitution: the ring pulses.** One texture on one frame, so the animation acts on the region that
owns the group — which is exactly what this client's animation model does — and no mask is involved at
any point. Same signal as the cascade, real art, no faked clip.

Details worth keeping:

* **A fourth FX, not a special case.** `AL.FX` already drives the settings submenu by generation, so
  adding `{ id = 4, name = "Pandemic Border" }` gave it a menu entry, a preview and idempotent
  start/stop for free. `refresh` defaults to it via `AL.DefaultFX`; the three LibCustomGlow renderers
  stay selectable.
* **Untinted, alone among the FX.** The other three renderers are colourless and take meaning from
  `TINT`. This art already carries the colour, and vertex colour multiplies — TINT.refresh's
  (1, 0.5, 0.1) over a ring that is (1, 0.19, 0.19) lands on (1, 0.09, 0.02), a muddier red than the
  artist chose, arrived at by tinting something that needed no tint.
* **The opening lands on the VISIBLE icon, which is not the same rect on every tile.** Retail anchors
  this ring with `SetAllPoints(item)`; copying that put it inside the icon on a picker tile, and
  anchoring to `.Icon` instead then pushed it too far out on a viewer tile. Both reports were correct,
  because the two tiles disagree about where the icon ends: a picker tile has no frame art, so the
  visible icon IS the `.Icon` rect; a framed viewer tile's gold `IconOverlay` opens `M.IconAperture`
  inside the tile (6.8px on a 50px Essential) and covers the icon's outer edge, so the 46px `.Icon`
  rect shows as ~36px. The art settles what to do with that. Its mid-row alpha runs 5, 15, 30, 50,
  75, 106, 141, 181, **255** across cols 0-8, then 0 through col 51, then mirrors — a hard edge at
  col 8 bleeding OUTWARD. So the 43-pixel OPENING is what must land on the visible icon and the 9 per
  side belong outside it. 43 is not a coincidence: it is the size of `OORshadow` on the same sheet,
  the icon-sized cell of this art family. Deriving from the aperture makes both tiles one formula —
  and on a framed tile it lands within a pixel of the tile rect, which is *why* retail's
  `SetAllPoints` works for retail: 43/61 = 70.5% is where a frame of these proportions opens.
  `.Icon` was wrong for a framed tile in a second way too — it moves with the icon-inset slider while
  the frame does not, so a ring tied to it would drift off the opening it is meant to trace.
  Re-anchored on every SHOW, because these rects come from anchors the client resolves late
  (the §H.2.9 lesson).
* **Levelled above the cooldown sweep**, for the reason §H.2.8 cost four passes to find: the sweep is a
  child frame, so it outranks every draw layer of the item and a ring on any layer would sit under it.
* **Alpha animations are DELTAS on this client.** ClassicAPI's `SetFromAlpha`/`SetToAlpha` are a
  polyfill over native `SetChange` (WidgetAPI.lua:414-436) and only emit it once both halves are set —
  hence from-then-to on each animation, and hence `startPandemic` setting alpha to 1 before `Play`.
* The **bar** ring (`pandemicborderbar`, 32x32, nine-slice 15/15/15/15) is registered nowhere: the
  alert ticker walks only the icon viewers, so nothing could read it. Upstream's own bar path is
  dormant for the same reason, by its own comment.

The harness gained an AnimationGroup stub, without which the builder's feature gate would have skipped
the pulse and the ring would have tested green while sitting static. Four mutations verified negatively:
never playing the pulse, levelling the ring at the sweep's level, tinting it, and reverting the anchor
to `SetAllPoints`. The last of those first ABORTED the harness rather than failing by name — `GetPoint`
returns no offsets for an all-points anchor, so the comparison hit nil — which is barely a catch at
all; the assertion now reads defensively and names the defect.

### Verification

Screenshots, into `screenshots/`, per the repo's existing practice: an Essential row on cooldown, a
Utility row with one spell buffed, a Buff Bar mid-depletion, and an out-of-range target. Offline
harness can only assert the atlases resolve — the rest is the eye.

## H.3. Phase 9 — audit against the current retail guide — **DONE**

Every feature and setting the guide describes, with a verdict. Consumables excluded by owner decision.

Phase 9 closes the port. Of the three items that were open when it was written, two had already been
paid for by earlier phases and only needed confirming; the third was the rename, which is the only
code this phase actually shipped.

**Have it:**

- Enable checkbox + a button through to the settings window ("Enable Cooldown Manager", "Advanced
  Cooldown Settings") — §G.12, as an enable toggle plus "Open Cooldown Manager".
- Two picker tabs, spells and buffs, with icon tooltips on hover. (We have three; the Settings tab is
  ours. Retail keeps its settings in Edit Mode.)
- Essential / Utility / Not Displayed, per mode — and since Phase 9, under retail's own name.
- Not-talented spells greyed out — our unlearned tint, which goes further: it explains itself in the
  tooltip.
- Right-click to move between categories.
- Sound and visual alerts via right-click, choosing trigger and effect — §E6/§G.7. **We are ahead
  here:** the guide says alerts are "only available with castable spells, and not buffs".
- Drag to reorder, and to reassign — §G.8. **Also ahead:** the guide's comments are three people asking
  for reordering and being told it does not exist.
- All four elements movable — four movers plus, since Phase 6, a per-viewer Position button.
- Buff timers on tracked buffs; out-of-combat buffs excluded.

**Missing, and worth doing — all three now closed:**

1. ~~**The glow around a buffed spell** → 8c. The only headline feature from the guide's own list that
   we do not have in some form.~~ **DONE** (§H.2.2). Nothing on the guide's feature list is now
   missing; what remains under Phase 9 is the "Not Displayed" naming preference and the two deliberate
   cuts below.

2. ~~**Target DoT timers.** The guide lists "timers for ... damage-over-time effects". The code exists
   (`ScanTargetTrackedAuras`) and has never been reachable~~ — **DONE, by Phase 7**, and confirmed
   rather than re-fixed. `ScanTargetTrackedAuras` reads the `include` set that `GetBuffOverrides`
   builds from the tracked-aura pool, and that pool was empty on every character until 7a/7d gave it
   a source. One empty table was disabling two features.

   Confirmed end-to-end, not by reading: `test_boot.lua` assigns Shadow Word: Pain through the same
   `SetAuraAssignment` the picker calls, puts a **Rank 10** SW:P on the target — a different spellID
   from the assigned one, and outside the auto-track window, so nothing but the name match can show
   it — and asserts the tile appears. The negative half is asserted separately: an *unassigned* target
   debuff stays invisible, because the auto window must never reach targets or every enemy debuff in
   the room arrives uninvited.

3. ~~**"Not Displayed"** is retail's name for what we call "Hidden", in both modes.~~ **DONE.** The
   two `CATS` labels, plus the three other places the old word reached the player: the empty-state
   line for the aura catalog ("Everything recorded is displayed."), the trinket tooltip, and the
   buff-tracking help text on the Settings tab. The right-click menu needed nothing — it builds
   "Move to …" from `Adapter.Label`, so it followed.

   **The rename stops at the display string.** The category ids (`hiddenSpell` / `hiddenAura`) and
   the stored assignment value (`"hidden"`) are unchanged, because that value is what every saved
   layout already on disk contains — renaming it would silently un-hide every aura a player has ever
   hidden. Both halves are asserted, so a future tidy-up that "finishes" the rename fails loudly.

**Deliberately not doing:**

- **Charges / recharge** ("Max 2 Charges ... 12 sec recharge"). No charge system exists on 3.3.5a.
- **Pet and AoE-spell timers.** Totems are already trackable as ordinary cooldowns via the arsenal;
  a totem's *remaining duration* would need `GetTotemInfo` polling and a per-class totem→spell mapping,
  which is a feature in its own right rather than a gap in this one. Flag for a later decision.
- **Retail's curated per-spec buff list.** 7d is the closest we can get from client data, and the
  guide's comment thread is largely people complaining that the curated list omits their abilities —
  a generated catalog plus the seen registry is arguably a better answer than the thing being copied.

### H.3.1. In-game fault: rows with no name on hover

Found immediately after Phase 9, on the surface Phase 9 sent the owner to look at. Most rows under
Not Displayed showed no name when hovered.

`tooltipSetSpell` reports whether its `pcall` errored, and callers were reading that as "a tooltip
was drawn". It is not. 3.3.5a has no `GameTooltip:SetSpellByID` and `!!!ClassicAPI` does not add one
(it adds `SetItemByID` and stops), so every spell tooltip goes through `SetHyperlink` — and
`SetHyperlink` on an id the client cannot resolve **succeeds and draws nothing**. Aura rows hit that
constantly, because the generated catalog stores rank-1 ids straight from `Spell.dbc` and plenty of
aura-only ids have no linkable spell behind them. The tile then showed "Lasts 30 sec" and "Tracked
automatically" under no title at all, on a 38px grid icon that carries no label of its own.

The name was never missing — the catalog and the seen registry both store one, precisely because
`GetSpellInfo` cannot be relied on for aura ids. It simply was not used. `M.TooltipSetSpellNamed`
adds it as a floor: `ClearLines`, ask the client, and if `NumLines()` is still 0, put the row's own
name up as the title. All four hover paths route through it — the two viewer aura mixins, the spell
tiles, and the picker.

**The stub was hiding it.** `test_boot.lua` defined a `SetSpellByID` the client does not have, so the
harness exercised a branch no player reaches, and its `SetHyperlink` was a bare no-op that could not
model "succeeds, draws nothing". Both are fixed, and the stub now gives a resolvable spell a title
**and a body** — without a body, "the client answered" and "we wrote the name ourselves" produce
identical tooltips and the guard passes just as happily when the fallback has eaten every tooltip in
the addon. That was caught by a mutation that failed to fail; it is the fourth vacuous assertion this
phase and the same shape every time.

Five mutations, each failing by name: the picker reverted to the unnamed helper, the viewer mixin
reverted, the fallback fired regardless of `NumLines`, the fallback emptied, and the client never
asked.

### H.3.2. In-game fault: alerts never fired on tracked buffs

Reported as "the FX on tracked buffs doesn't work". It was not the FX — it was the ticker's viewer
list. `Alerts.lua` walked `viewers.essential` and `viewers.utility` only, justified in a comment as
"the aura viewers have no ready transition and no curated usable state".

Both halves of that are true and neither was a reason to skip them. `available` is edge-triggered off
`ConsumeReadyTransition`, which aura items do not define, so `checkReadyTransition` returns at its
first guard and costs one lookup. `usable` reads `IsUsableSpell`, which answers for a self-buff's own
spell exactly as it does for a cooldown. What the omission actually cost was **`refresh`** — the one
alert whose trigger *is* an aura decaying, and therefore the most useful of the three on a tracked
buff. It could be assigned from the menu, it lit the badge, it previewed on the settings tile, and
then it never fired in play.

**The asymmetry that hid it:** `AL.Stop` and `M.ResetAlerts` have always cleared FX across all four
viewers via `M.ForEachViewer`. Only the code that *set* it was narrower, so the teardown looked
complete. The ticker now uses `ForEachViewer` too, which is also why it cannot go stale against
`M.viewers` a second time.

**Two triggers were being offered where they cannot fire**, which is the same defect one layer up.
`Available`'s own tooltip promised "Works for every spell" on rows that hold no spell, and a ready
sound assigned to a buff lit the badge permanently with nothing able to play it — `FireReadyAlerts`
is a cooldown-edge path. `SettingsMenu.lua` now gates both on the row's category `mode`. `None` still
sits above `Available`, so a layout that stored it before the gate is still clearable; a stored ready
sound gets a single `Clear Ready Sound` entry rather than vanishing with the submenu, because a
setting you can reach only to regret is worse than one you were never shown. `Refresh` also drops its
"a cooldown that applies no aura can never trigger it" caveat on aura rows — there, the row *is* the
aura.

Four mutations, each failing by name: the ticker reverted to the two spell viewers (three
assertions), the `Available` gate removed, the ready-sound gate removed, and `isAuraRow` forced true
to prove the gate does not fire on spell rows.

### H.3.3. In-game fault: the alert triggers were all cooldown questions

Reported after §H.3.2 shipped: "the tracked buffs still don't work with effects", with an alert
reading `Alert: usable (Button Glow)` on **Surge of Light**. The ticker was reaching the aura viewers
by then. The trigger could still never fire.

All three ported triggers ask questions about a **cooldown** — has it finished (`available`), is it
castable (`usable`), is the buff it applies running out (`refresh`). A proc is none of those. Surge
of Light is a 10s aura with no castable spell of its own name, so `IsUsableSpell` answers nil,
`available` has no cooldown edge to consume, and `refresh` covers the last 3 seconds of the 10. The
question a tracked buff actually asks — *is this proc up* — had no trigger at all.

**`active` is the fourth type**, ours and not retail's, offered on aura rows only. It reads the
item's own `_auraActive`, which both aura mixins already maintain, so it costs nothing on the ticker
path. **`usable` is now gated** on the client knowing a castable spell of that name — probed with
`GetSpellInfo`, not `IsUsableSpell`, because the latter returns nil both for an unknown name and for
a known spell you merely cannot afford right now, and reading it would have hidden the entry from
anyone who opened the menu out of mana. A self-buff row keeps it, with a line saying it is about
re-casting rather than about the buff being up.

**A second fault, found while fixing the first.** Per-spell settings are stored under the id the
PICKER ROW carries — rank 1 from the catalog, or whatever rank the scan first met — while a live
viewer item carries the id the scan returned this time. For any ranked buff those differ, so
`AL.Get(item.spellID)` found nothing: stored, badged, silently dead. `GetBuffOverrides` had already
solved this for *assignments* by keying on name as well as id; `M.SettingsKeyForAura` applies the
same rule to the settings stores, and the aura mixins gained the `GetSettingsKey` the spell items
have always had. It did not bite Surge of Light (catalog id 33151 is also the applied id) which is
why the report was about `usable` and not about everything.

**Three harness gaps, each of which had been hiding one of these.**
`IsUsableSpell` returned `true` for **any** string, so a proc row looked castable offline — the exact
opposite of the client's answer, and the reason `usable`-on-an-aura had a passing test.
`CreateTexture` **discarded the subLevel**, so "created underneath the thing it was meant to cover"
had no offline symptom; that is the same fault §H.3.2's stone note describes, and it had gone
unmodelled for four phases. And the earlier `refresh`-on-a-buff test used one spellID for both the
stored alert and the scanned aura, so it could not have caught the rank mismatch.

Six mutations, each failing by name: `active` never evaluated, `active` sharing the usable tint,
`Active` not offered, `Usable` offered regardless, the settings key falling back to the live id, and
the Inset fill returned to subLevel -5.

### H.3.4. The window body, and the inset that was never visible

The `/cdm` window read as a dark wash beside every other standalone window: `PC.ApplyModernChrome`
tints its `f.Bg` to 0.32 grey — a downport fix for a different frame's first-paint colour flash — and
this was the last window still wearing it. Stripped to full brightness, as Collections does.

The Inset fill it carried was `character-panel-background` at BACKGROUND subLevel **-5**, while
`f.Bg` sits at subLevel **0** and spans the whole frame. It drew underneath and **was never once
visible**. ClassicAPI's `PortraitFrameTemplate` declares its own `$parentBg` with no parentKey
(`UIPanelTemplates.xml:1517`), so PanelChrome builds `f.Bg` fresh at the default subLevel instead of
re-texturing the template's at -6 — which is what put the two on the wrong sides of each other. The
Inset now carries the near-black recessed fill every other inset in this addon uses (Collections'
`buildInset`, LFG's rail), at a subLevel **above** the body stone.

The rock FDID was never registered in the offline harness, so PanelChrome took its graceful-degrade
branch and applied no tint at all — a guard on the body brightness passed against the very regression
it exists to catch, and a mutation removing the untint failed to fail. Registering it fixed that, the
registration is now itself asserted, and the stub gained `SetHorizTile`/`SetVertTile` (whose absence
was what forced the degrade branch) plus `ButtonFrameTemplate`'s `Inset` child.

### H.3.5. The scrollbar was never reskinned, and the row highlight was the wrong shape

**The scrollbar.** `/cdm` called `NE.scrollbar.Reskin`, which looked applied and could never have done
anything here. Reskin reaches for `scroll.ScrollBar`; 3.3.5a's `UIPanelScrollFrameTemplate` declares
its slider as `$parentScrollBar` with **no parentKey**, so that field is nil and Reskin returns at its
second line. Exactly the shape of the `PortraitFrameTemplate` `$parentBg` trap in §H.3.4, and it has
no symptom beyond "the bar looks stock" — which is what it looked like.

Switched to `NE.scrollbar.BuildCustomPixel`, the hand-built track+thumb every other list in this addon
uses. It is the right variant for a real ScrollFrame: it drives `SetVerticalScroll` directly and sizes
the thumb from visible:total, rather than `BuildCustom`'s row-step heuristic for FauxScrollFrames.

`BuildCustomPixel` had to grow the stock-bar handling `BuildCustom` has always had. Its only previous
caller (the character stats sidebar) is a bare `CreateFrame("ScrollFrame")` with no template and so no
stock bar to get out of the way of; a templated ScrollFrame has one, complete with arrows, and without
this the player gets **two** bars side by side. It now hides the stock slider with a re-show guard,
reparents the arrows off it (a hidden parent hides its children whatever their own state), reskins and
re-anchors them to our track, and replaces their `OnClick` — the template's inline handler drives
`self:GetParent()` and assumes that is the slider, so after the reparent every click throws.

**The row highlight.** Reported from the game: the blue highlight over-stretched on Tracked Bars.
`ButtonHilight-Square` is a 64×64 glow drawn for a square button; across a 344px row it smears — bright
over the icon, bleeding away to the right. Wide rows take `UI-QuestTitleHighlight`, which is built to
stretch and is what the character Sidebar, EquipmentManagerPane and TitlesPane rows already use. The
square tiles keep the square texture, which is the half a blanket swap would have broken.

**Harness.** `core/ScrollbarReskin.lua` was not loaded at all, so none of this had coverage. Loading it
needed four stub fixes, each of which had been hiding something: `GetVerticalScrollRange` was a hard 0
(the one value that makes every scrollbar hide itself, so a bar built wrong in every respect still
looked right), `SetFrameStrata` was write-only with no getter (code that re-reads a strata to match it
died inside a `pcall`, visible only as a widget that quietly failed to build), the four button state
textures returned a fresh region per call (so "did this button get retextured" was unanswerable), and
`UIPanelScrollFrameTemplate` supplied no slider — modelled now by global name and deliberately
**without** a `.ScrollBar` parentKey, because that absence is the bug.

### H.3.6. In-game fault: the per-character reset was resetting every character

Reported as "the reset character button in the settings actually resets all characters", and that is
exactly what it did.

The store is **one shared DragonUI profile**, keyed by class all the way down —
`customLists[<category>][<CLASS>]`, `trackedAura[<CLASS>]`, `seenAura[<CLASS>]`. That class key is the
only thing separating one character's data from another's. `M.ResetTracking` blanked
`cd.specLayouts = {}` and `cd.seenAura = {}` **whole**, taking every class with it: a Priest pressing
reset cleared the Warlock, the Druid and the Mage as well.

Now scoped. Each layout bucket loses only this class's slice — the "every bucket, not just the active
talent group" half was right and is unchanged. The one-time migration is forced first, so the legacy
flat keys are gone by the time the scrub runs and there is one shape to handle rather than two.

**`equipAssign` could not be sliced the same way**: it is keyed `"item:<itemID>"` with no class
dimension at all. Scoped instead to the tokens this character can actually reach — the trinkets it has
equipped — which leaves another character's placements alone. A token for an item nobody has equipped
is unreachable in the picker regardless.

**The copy was wrong too, in the same direction.** The button promised "clearing per-character spell
lists" and the confirm popup named no scope whatever, which is the last thing read before an
irreversible action. Both now say *this class*, which is the honest word: another class is untouched,
and another character of the same class shares these lists and will see them reset.

Three mutations, each failing by name: the unscoped wipe restored verbatim, `seenAura` blanked whole
again, and `customLists` left alone — the last proving the fix did not quietly turn the reset into a
no-op, which is the failure mode a scoping change invites.

### H.3.7. Viewer positions are per character

Owner request: moving the viewers in `/dui edit` should save per character. It did not — DragonUI's
profile is shared across the account (the same fact behind §H.3.6), so all four viewers sat wherever
the last character to touch them left them.

**Done by KEY, not by a parallel store.** DragonUI's editor takes exactly one thing from us — the
`configPath = { section, key }` it reads and writes `profile[section][key]` through. Varying the key
therefore buys per-character positions with no change to DragonUI at all (CONTRACTS §0).
`NE.FramePositionKey` appends name and realm, and it is **opt-in per frame**: a module that wants one
placement across the account keeps it by saying nothing. Only the four Cooldown Manager viewers ask.
The fallback when the client cannot yet name the player is the shared key — a shared position is a
mild surprise, a position filed under `-nil` is one nothing will ever read back.

**Migration matters more than the feature here.** A character upgrading into this must not watch its
viewers jump to the default; that reads as data loss. The existing shared entry seeds each character's
slot on first registration, as a **copy**, and is deliberately left in place — deleting it would hand
the upgrade to whoever logged in first and a default layout to everybody else.

Four mutations, each failing by name: the viewers no longer asking, the key builder ignoring the flag,
the seed skipped, and the seed moving the shared entry instead of copying it.

### H.3.8. Per-character appearance, as a tickbox

Follow-up to §H.3.7. Position went per character unconditionally; everything else under `cd.frames` —
orientation, icons per row, icon direction, size, padding, opacity, visibility, timer, tooltips, bar
content, bar width — stayed account-wide. The owner asked for that to be opt-in rather than automatic.

**"Separate appearance per character", off by default.** With it off nothing about the previous
behaviour changes: reads and writes go to `cd.frames` exactly as before, and no per-character bucket is
created at all.

**On, a character's values are OVERRIDES on the shared table, not a copy of it.** `getOpt` consults the
character bucket first and falls through to `cd.frames`. That structure is doing the work:

* **Nothing moves when the box is ticked.** A character that has changed nothing reads what the account
  reads, because the fall-through *is* the seed. There is no copy step, so there is no copy step to get
  wrong — contrast §H.3.7's position migration, which needed one.
* **Unticking is not destructive.** It stops consulting the bucket; the overrides survive, so the box is
  free to try in both directions.
* **An untouched key keeps tracking the account.** Change icon size account-wide and every character
  that never overrode it follows.

`ResetOpts` clears **both** levels: the button says "defaults", and clearing only the override would
land on the account-wide setup while promising something else. Other characters' buckets are untouched.

Five mutations, each failing by name: the read never consulting the bucket, writes always going
account-wide, the option ignored, the bucket not keyed by character, and reset clearing only the
override. The third of those initially aborted the run instead of failing by name — one assertion
indexed `frames[FID]` without a nil guard, which is a caught regression that looks like a truncated
harness.

**Not covered, and worth knowing:** `CDS.SnapshotState` captures five leaves — `customLists`,
`trackedAura`, `equipAssign`, `alerts`, `sounds`. Appearance has never been among them, so import/export
does not carry icons-per-row on any setting of this box.

### H.3.9. Layouts carry appearance, behind their own checkbox

§H.3.8 closed by noting that `CDS.SnapshotState` captured five leaves and appearance was not among
them, so a share string carried *what* you track but not *how it looks*. The owner asked for that,
gated.

**Capture is unconditional; applying is the gate.** A share string always carries appearance — a few
hundred bytes — so the decision belongs to whoever *applies* it, not whoever exported it. The new
"Layouts include appearance" checkbox is off by default: an imported layout that silently resizes and
reorients four viewers is how "load a layout" stops being an action anyone trusts.

**Captured RESOLVED, not as a table copy.** What the exporting character sees is the account-wide
table with their own per-character overrides on top (§H.3.8), so copying either half alone would export
something nobody is looking at. Resolving through `GetOpt` also keeps the per-character bucket out of
share strings entirely — its keys are a character name and a realm, meaningless on another account.

**Applied through `SetOpt`**, not by assigning the leaf: `SetOpt` is what knows whether this character
writes to its own bucket or the shared one, and it re-applies each viewer as it goes.

**Revert is not governed by the box.** `CDS.RestoreState(snap, opts)` takes `opts.appearance` —
true forces, false forces skip, nil follows the setting — and Revert passes true. Its contract is to
put things back exactly, and the box may have been ticked for the apply and unticked before the undo;
a revert that left a resized viewer behind is a partial undo, which is no undo.

**The codec needed no change**, because the serializer is generic over tables — a claim worth checking
rather than assuming, so the round-trip test now asserts the appearance leaf survives it.

Five mutations, each failing by name: capture removed, the box ignored in both directions, appearance
never applied, Revert no longer forcing it, and the option defaulting on.

### H.3.10. The settings move onto the frame, in edit mode

Retail puts a system's settings **on the frame**: enter Edit Mode, select the Cooldown Manager, and
orientation / icon limit / size / opacity are right there beside it. Ours were reachable only from the
`/cdm` Settings tab — correct, complete, and a different window from the one showing the thing you want
to change. The owner asked for the retail shape.

**§B1's decision is not reopened.** Upstream's 6,441-line Edit Mode reimplementation stays unported;
what changes is that DragonUI's editor now carries the *settings* as well as the *position*.

**The seam is `NE.RegisterHUDFrame`'s new `editorSettings` field** (integration/Register.lua), not the
module. Every DragonUI touch — the mouse handler, the edit-mode gate, `SelectEditorFrame`,
`EditorMode:Hide` — lives there. The field is a **callback**, not a widget: what a module opens when its
frame is clicked is the module's business, and the host glue's business is only deciding when it may
(CONTRACTS §4).

**Nothing in DragonUI is edited (CONTRACTS §0).** `CreateUIFrame` sets `OnMouseDown` (left-click
select), `OnDragStart` and `OnDragStop`, and *none* of `OnMouseUp` / `OnEnter` / `OnLeave` — so ours are
plain `SetScript` calls on a frame we asked the factory to build, overwriting nothing. Out of edit mode
the anchor is `EnableMouse(false)`, so the settings are unreachable without the gate even existing.

**Either button opens it**, because retail opens a system's dialog on *selection* and left-click is what
selects. **Our handler also selects the frame**, which matters most on right-click: `CreateUIFrame` only
selects on `LeftButton`, so without it the editor's coordinate readout and Reset button would describe
whatever was clicked last while the dialog edits something else.

#### The first pass was a context menu, and that was the wrong shape

It shipped as a right-click menu: every setting a submenu of radios. It worked. Then the owner showed
what NewEra's own 1.15 edit mode does — a small **dialog** beside the selected frame with every slider
and dropdown visible at once — and the menu's two compromises stopped being defensible:

* **A menu shows one setting at a time**, and hides the value you are trying to match while you pick it.
* **A numeric setting inside a menu has to become a list of discrete rows.** That is why the menu shipped
  opacity in steps of 5 where the tab steps 1, and why it needed a tooltip explaining that a value could
  legitimately tick *nothing at all*. A dialog takes a real slider and both compromises simply go away.

So `EditorMenu.lua` was replaced by `EditorPanel.lua`. The seam survived the swap unchanged, which is
the argument for having made it a callback rather than a menu generator.

#### What the dialog is

**The /cdm control kit, not a second set of widgets** (SettingsControls.lua). One new control was needed:
`AddCompactSlider`, a one-line slider with nudge arrows. The tab's tall two-line slider is right for a
page you scroll and wrong for a dialog that has to sit on screen next to the thing it edits without
burying it. **The arrows are not decoration** — a drag reports continuous values on this client
(`SetObeyStepOnDrag` is retail-only), so they are the only precise way to land on an exact value.

**`FULLSCREEN_DIALOG` strata.** `CreateUIFrame` puts the editor handles at `FULLSCREEN`; a settings
dialog that renders behind the frame it configures is not a settings dialog.

**One dialog, not four.** Selecting another viewer swaps the page and retitles. Pages are built lazily
and kept, so switching costs nothing after the first visit.

**Re-read on open.** Something else may have moved these underneath it — the `/cdm` tab, a layout apply,
a reset — and a dialog that opens on a stale value is indistinguishable from one whose settings did not
take.

**Revert vs Reset, deliberately not the same button.** *Revert Changes* goes back to how the viewer was
when the editor was opened; *Reset to Default* goes to defaults. Conflating them is how someone loses a
setup they spent ten minutes on. The snapshot is taken on first open per editor session and dropped when
the editor closes — keeping it would silently arm the button with an hour-old state. Revert is disabled
until there is something to revert, because a button that is always live and usually does nothing teaches
you to ignore it, and this one is the undo.

**Leaving edit mode takes the dialog with it**, via the viewer spec's `onHide`. `HideAllEditableFrames`
calls that for every registered frame, so it fires whichever viewer was selected.

**Two editors for one value**, which SettingsOptions.lua's header forbids. The rule is about *staleness*,
so both halves are closed rather than the rule waived: the dialog re-reads on open, and every write it
makes calls `CDS.RefreshSettingsPage`, which no-ops when that tab was never built. The test asserts the
tab's slider actually moves.

**Not carried:** `Scale`, the first row in NewEra's own dialog. There is no scale value in this port's
store — `iconSize` scales the icons and nothing scales the frame — so adding it is a new stored setting
(defaults, per-character, layout capture) plus a fix to the editor anchor, which sizes itself from the
content's *unscaled* `GetWidth`. That is a feature, not a look change, and is left for the owner to call.

Fourteen mutations, each failing by name and none aborting the run: the opener never attached, the
edit-mode gate dropped, the tab never notified, no re-read on open, Revert going to defaults instead of
the snapshot, snapshots surviving the session, Revert always armed, the arrows not stepping, the arrows
not clamping, `onHide` not wired, `Hide When Inactive` offered everywhere, the title never updated, pages
never hidden on switch, and the strata left below the handles.

#### The art, second pass

The first render was the right dialog wearing the wrong clothes: `PC.Apply` is PANEL chrome, so a
small floating dialog arrived with the rock fill and — despite `noPortrait` — the portrait ring, which
lives in the `PortraitFrameTemplate` nineslice, not in the portrait texture that flag suppresses. It
read as a window that had lost its contents.

The reference is `ReferenceAddons/NewEra/EditMode/SettingsPopup.lua`, itself a transcription of
retail's `EditModeSystemSettingsDialog`. Taken from it:

* **Chrome** — `DialogBorderTranslucentTemplate`: black at 0.8 inset 7, under the **DiamondMetal
  "Dialog"** nineslice. That layout is now registered in `core/NineSliceLayouts.lua` (verbatim from
  NewEra, including its `D = 32`, since the corner square and the edge thickness must match or they do
  not line up), and its two sheets — 3056750 frame, 3056755 side edges — ship in `Textures/Common`.
  Core art, not the module's: anything dialog-shaped needs it, and the Metal family is panel chrome.
* **Metrics** — 343×32 rows spaced 2, a 100px label column, 200px controls, 20px content inset,
  `GameFontHighlightMedium` labels, a 32px checkbox, `GameFontHighlightLarge` title at `TOP -15`.
* **Buttons region** — Revert at 180 wide, the `UI-FriendsFrame-OnlineDivider` strip, then full-width
  Reset. "Cooldown Manager Settings" moved OUT of that region and onto the end of the options stack,
  which is where retail's `AddExtraButtons` puts a system's own extra actions.
* **Dropdown** — retail's `WowStyle1Dropdown` paints a STATIC body and puts the gradient on the arrow.
  3.3.5a has no such template, so the trigger is assembled from four pieces off sheet 5390329
  (`common-dropdown-textholder` plus the `a-button` states) on a bare Button — fighting
  `UIPanelButtonTemplate`'s own art for a look this different is more code than drawing it.

**A THEME, NOT A SECOND KIT.** All of that lands in `SettingsControls.lua` as a table passed to
`Kit.New`, with every default equal to what the `/cdm` tab already had. Same widgets, two sets of
metrics; the tab is a scrolling page of sections and this is a fixed panel, and asserting the tab kept
its own is part of the suite.

**`Scale` is still not carried** — see above; unchanged by this pass.

**Three assertions in the first art pass were vacuous, and the mutations found all three.** Checking
that the `Dialog` layout table names a DiamondMetal atlas passed just as happily with the dialog
applying `PortraitFrameTemplate`, and with the BLPs never copied: `NE.tex.SetAtlas` reports a miss and
leaves the texture blank in both cases. Reading the file path off the piece the dialog actually wears
answers all three questions at once. The harness now loads `core/NineSlice.lua`,
`core/NineSliceLayouts.lua` and `Textures/Assets.lua` for the same reason — without them it could not
tell a registered atlas from one whose art nobody shipped, and PanelChrome takes its graceful-degrade
path silently either way.

Ten further mutations, each failing by name: the panel chrome layout swapped back in, the nineslice
never applied, each of the three sheets unshipped (frame, edges, dropdown — three separate mutations,
since they fail independently), the theme ignored, the modern trigger never built, the theme leaking
into the tab, the hover state never swapping the arrow, and the bare button left without `SetText`.

#### The red 3-slice button, and the bug it was hiding

`core/ButtonSkin.lua` has reskinned buttons to retail's `BigRedThreeSliceButton` since Sprint 0 — off
the `128-RedButton` sheet, which this port **never shipped**. So every call fail-safed to native art
and returned `false` to say so, and nothing read the return: the LFG role buttons and this dialog's
Revert/Reset were all silently unskinned. Sheet 1536801 now ships, with its ten rects (three states ×
three pieces, plus the highlight strip).

**Shipping it turned on a code path that had never once run, and it was broken.** `updateScale` is a
port of retail's `ThreeSliceButtonMixin:UpdateScale`, which does `self.Left:SetScale(scale)` —
**Texture has no `SetScale` on 3.3.5a.** ClassicAPI has to synthesise even `GetEffectiveScale` for a
Region by delegating to the parent (`Util/WidgetAPI.lua:205`) and adds no `SetScale` at all. Every
call site wraps `Skin` in `pcall`, so in game this would have thrown *after* the three textures were
created and the native art hidden — a button wearing nothing at all, with no error in the log. The
caps are now sized in real pixels instead, and the trim branch no longer divides back out by a scale
that was never applied.

Two harness gaps fell out of chasing it, both now closed: `Enable`/`Disable` did not fire their
scripts (so a skin that repaints on `OnEnable`/`OnDisable` was never asked to, and a disabled button
would have tested as wearing the normal art), and textures had `SetHorizTile` with no getter (so
"does the centre tile?" could only be written with a nil escape hatch that passed either way — it
did, until the getter existed).

Six more mutations, each failing by name: the sheet unshipped, the left cap's rect dropped, the
footer never skinned, the pressed state never applied, `SetScale` put back, and the centre stopping
tiling.

**One button was missed on that pass:** "Cooldown Manager Settings" is built by the control kit
(`Column:AddButton`), not by the dialog, so the dialog's own `NE.button.Skin` call never reached it —
and it sat directly above two buttons that *were* skinned, which is far more obviously wrong than
three unskinned buttons would have been. The skin is now a theme flag (`buttonArt`, off by default,
like the rest of the theme) so the `/cdm` tab's buttons keep their look. Three mutations: the kit
never skinning, the dialog not asking, and the flag defaulting on so it leaks into the tab.

#### H.3.11. Three corrections from the owner

**The buttons pair up, and the destructive one asks.** Revert and Reset were stacked with a divider
between them, which is retail's shape but costs 46px of a dialog whose whole job is to sit beside the
frame it edits without burying it — and stacked they read as a list of two things to work down rather
than the pair of alternatives they are. They are now one row, `(343 - 3) / 2` each, one anchored to
each side, under the divider.

That puts them three pixels apart, which is why Reset now confirms. The asymmetry between the two is
easy to miss: Revert is *bounded* — it undoes this editor session and greys itself out when there is
nothing to undo — while Reset throws away every layout choice ever made for that viewer and nothing in
the addon can put it back. `StaticPopupDialogs["NE_CDM_EDITOR_RESET"]` rewrites its `text` per viewer
at click time, so the confirm names what it is about to wipe; a generic "are you sure?" asked over four
differently-configured viewers is the kind of prompt people learn to click through. It also bumps its
own strata to `FULLSCREEN_DIALOG` on show — StaticPopups live at `DIALOG`, and this dialog sits above
the editor's own handles, so left alone the confirm would open *behind* the button that raised it.

**The dropdown body is a 3-slice.** `common-dropdown-textholder` is not a bar: decoded off sheet
5390329 it is a **54×41 rounded rect with a ~12px bevelled corner and a soft outer glow**. Stretched
to a 200×26 row — one texture, `SetAllPoints` — the corners smear into horizontal blobs and the bevel
squashes to a blur. That is what "the dropdowns are formatted very weirdly" was looking at, and it was
only visible because the art finally shipped. Columns 13..42 of the source are a flat vertical run, so
an 18px cut lands well inside it on both sides: the two caps carry the corners with their width
following the row height (`18 × h/41`), and only the middle stretches, invisibly. The arrow is a
separate 27×27 square button in the same sheet and is now drawn square and inset, instead of
`h-2` straddling the right cap's bevel.

The same pass fixed the *alignment*, which was the other half of "weirdly": the dropdown was a fixed
200 anchored at `labelW + 6`, so its left edge sat 4px right of the compact slider's nudge arrow and
its right edge 37px short of the slider's value text. Down a stack of alternating rows, nothing lined
up with anything. The control column is now defined once, by the slider, and the dropdown fills it.

**The red 3-slice is the addon's standard button.** Not the Cooldown Manager's look — the addon's.
Roughly sixty `CreateFrame(..., "UIPanelButtonTemplate")` calls across a dozen modules build the stock
grey button, and the mechanism for this is deliberately *not* sixty edits:

* `NE.buttonskin.SkinPanelButtons(root)` walks a frame tree and skins what it finds. The predicate
  reads the **art**, because a running frame cannot be asked which template built it: on 3.3.5a
  `UIPanelButtonTemplate`'s entire runtime identity is that it `SetNormalTexture`s
  `Interface\Buttons\UI-Panel-Button-Up`. It is self-limiting — `Skin` clears that texture, so a
  skinned button stops matching.
* `NE.buttonskin.Watch(root)` keeps it true as the tree grows. A window is registered before its
  contents exist and its panes are built on the tab that first needs them, so one sweep at
  registration would miss most of the addon. Three passes cover it: now, next frame, and on show —
  plus an `OnShow` hook on frames within two levels of the root, which is where panes live.
* Twelve windows call `Watch` — auction house, bags, character, collections, encounter journal, guild,
  LFG, professions, social, spellbook, talents, and the `/cdm` window.
* **Opt-out** is `_nePlain` (already the codebase's marker for a plain button standing in for a tab —
  those sit in a tab strip and would read as loose buttons in red) and `_neNoSkin` for anything else.
* `DEFAULT_THEME.buttonArt` flips to **on**, so the `/cdm` Settings tab's buttons come along too. The
  suite's old assertion that the tab was untouched now asserts the opposite, deliberately.

This resolves the question left open when the sheet shipped: the LFG role buttons and everything else
change to the red art, by the owner's call.

**A harness gap, and a vacuous assertion, both found by mutation.** `SetNormalTexture` was a no-op in
the stub, which would have made every assertion about the sweep pass by describing an empty tree — it
now writes to the memoized state texture, and `CreateFrame` models the template's normal texture. And
the predicate test only had a button with *no* normal texture, so loosening it to `return true` still
passed; a button carrying art of its own (an item slot, an icon button — the case where a false match
costs something, since `hideNativeArt` would blank it) is now in the test. The dropdown slicing had
the same shape of hole: all three pieces resolve to the same file and the cap widths come from a Lua
constant, so nothing read the atlas at all. The texcoords are asserted contiguous and left-to-right.

Thirteen mutations, each failing by name: `buttonArt` defaulting off, the dropdown back to a fixed 200,
the caps collapsed, the caps unscaled, the atlas rect covering the whole textholder, all three pieces
using the left cap, Reset firing without confirming, the confirm text left generic, Reset back on its
own row, the sweep ignoring `_nePlain`, the sweep not recursing, `Watch` never hooking a pane's
`OnShow`, and the predicate matching any button.

#### H.3.12. Three more from the same pass

**The confirm opened behind the edit-mode buttons.** Edit mode stacks three things over `DIALOG`,
where StaticPopups live: the editor handles at `FULLSCREEN` (`addon.CreateUIFrame`), this dialog at
`FULLSCREEN_DIALOG` to clear them, and DragonUI's own Exit Edit Mode / Reset All Positions panel at
**`TOOLTIP` frame level 200** (`DragonUI/core/api.lua:971`). `TOOLTIP` is the top strata, so clearing
that last one is a *level* question, not a strata one — the confirm goes to `TOOLTIP`/300 on show and
puts the shared popup frame back on hide, since the next dialog to use that slot is not ours.

(The "Error Messages" title above the confirm in the report is not ours either: it is DragonUI's own
editor handle for `UIErrorsFrame`, which parks at screen centre-top under where the popup lands.)

**The dialog slid sideways while a slider was being dragged.** `place` anchored it *to* the viewer —
`SetPoint("TOPLEFT", anchor, "TOPRIGHT", ...)` — so Icon Size or Icon Limit resized the frame and the
dialog moved out from under the cursor mid-drag. It now resolves the position into `UIParent`
coordinates once, on open, and holds still until another frame is selected. The trade is that a viewer
which grows a lot can end up overlapping its own dialog; a dialog that holds still is worth more.

**Menus close on a click outside.** They had two ways out — pick a row, or Escape — and nothing in the
backend supplies a third: ClassicAPI's `C_DropDownList` frames carry only the mouse-off timer that
applies to menus opened in `MENU` mode from a hovered parent, not to one opened by clicking a button.
So `core/Menu.lua` grew a full-screen mouse catcher, armed by both `OpenContext` and `ToggleAnchored`,
parked **strictly one frame level under** the open list so the menu keeps its own clicks. It disarms
from the list's `OnHide`, which covers every other way a menu closes (a row picked, Escape, a
`CloseAll` from elsewhere) — a catcher left up would silently eat the next click anywhere on screen.
The click is consumed, which is what Blizzard's dropdowns do.

**The level clamp was wrong, and the test caught it before the game did.** The first version clamped
the *catcher* up (`math.max(1, lvl - 1)`), which ties with a list at level 1 — and at equal levels the
click resolves by creation order, so the catcher would sometimes have swallowed the row the player was
aiming at. It clamps the *list* up instead.

Three harness gaps closed alongside, each of which would have made an assertion vacuous: the dropdown
stub's `Toggle` never showed or hid anything (so "is a menu open?" was unanswerable, and a catcher
armed over an empty screen tested identically to one that was not); frames had no `GetLeft`/`GetTop`,
so a placement resolving screen coordinates could only ever take its "I cannot measure this" fallback;
and `UIParent` was 0×0, so a branch on which half of the screen a frame sits in always went the same
way — which is exactly why the first mutation of the new placement came back green.

Eight mutations, each failing by name: the popup left at `FULLSCREEN_DIALOG`, the popup never
restoring the shared frame, each placement branch pinned back to the frame, the catcher never armed,
armed with nothing open, never disarmed on close, and sitting on top of the list instead of under it.

#### H.3.13. The confirm again, and the tab loses its per-viewer half

**The strata fix above was aimed at the wrong frame.** `DragonUI_EditorPanel` — the coordinate
readout, `TOOLTIP` level 200, `core/api.lua:971` — is not what covers the confirm. **Exit Edit Mode**
and **Reset All Positions** are separate frames on `UIParent` at `TOOLTIP` level **1000**
(`modules/editor_mode.lua:190, 210`), so 300 cleared something nobody was complaining about and the
popup was still unreadable. It now READS the level off those frames and adds 10, because a constant
picked to beat 1000 is a constant that stops working the next time DragonUI moves theirs, and nothing
would say so. The test models `DragonUIExitEditorButton` for exactly this reason: without it, "the
confirm is above the edit-mode buttons" is a comparison against nothing.

**The per-viewer settings leave the `/cdm` Settings tab (owner steer).** They had been in two places
since the dialog shipped — thirteen controls rendered twice, held together by a refresh contract that
this file's own header calls out as the thing not to do. The dialog is the better half: you are
looking at the frame while you change its layout, rather than at a list of numbers in a window that
covers it. So the tab's four viewer sections are gone, and with them `buildViewerSection`, the
`ORIENTATION` / `DIRECTION` / `VISIBILITY` / `BAR_CONTENT` lists, and `EditorPanel`'s `notifyPanel` —
which was not merely dead but ran on every tick of a slider drag.

What replaces them is one **Viewer layout** section of four buttons. Each opens edit mode with that
viewer selected *and its dialog already up*, through the same seam a click on the handle uses — since
this is now the only route from the tab to those settings, landing the player in edit mode to go
hunting for the right handle would be a worse tab than the one it replaced.

The tab keeps everything that was never per-viewer: buffed-spell glow, icon fit, talent specs, buff
tracking, resets.

**Six tests moved rather than being deleted, because the behaviour did not go away.** Step snapping,
write-once-per-step, checkbox row-versus-box and dropdown ordering were all asserted against the tab's
copies of these controls. They now sit in the dialog block, against `AddCompactSlider` — a genuinely
different commit path from `AddSlider` — while the tab's own widget kinds keep their coverage through
the controls it still has (`Icon inset` for the tall slider, `Glow while buffed` for the checkbox,
`Show them as` for the plain dropdown). The theme-isolation assertions moved the same way, and the
tab's absence of per-viewer settings is asserted **by control name over every viewer**, not by the
sections being gone — the latter would still pass with the controls re-homed under another header.

Four mutations, each failing by name: the popup level hardcoded again, the popup clearing only the
coordinate panel, the viewer link stopping at edit mode, and a per-viewer section reappearing on the
tab.

#### H.3.14. The confirm stops being a StaticPopup

Three attempts to out-stack DragonUI's Exit Edit Mode and Reset All Positions buttons, and the third
one was to stop trying. In order: `FULLSCREEN_DIALOG`/300 (aimed at the coordinate panel, the wrong
frame); `TOOLTIP`/300 (right strata, still short of their 1000); reading their level at show time
(did not work in game either, and from this side there was nothing to see — a `StaticPopup` frame is
shared, re-parented and repositioned by code we do not own, and every hook we had went through it).

**So the confirm is our own frame, parented to the dialog.** That settles the stacking by construction
rather than by arithmetic — a child draws inside its parent's stacking, above it, with no number to
get wrong — and it settles the *position* too, which was the other half of the problem: those buttons
park at screen centre, and a `StaticPopup` lands in exactly that spot. A confirm inside the dialog
appears beside the viewer being edited, where nothing else is competing for the space.

It is **modal to the dialog**: a blocker fills the panel behind it, dimmed, eating clicks. The question
is about the very settings underneath it, and nudging a slider behind an unanswered "are you sure?"
means answering it about a different state than the one that was read. It wears the same DiamondMetal
chrome and red buttons as the dialog, and it is dropped whenever the dialog switches viewers — it names
one viewer and acts on whichever is current, so those must not be allowed to differ.

One thing did not survive first contact: the message came out as "…orientation and vis...".
The FontString was sized by anchoring TOPLEFT and TOPRIGHT, which does give it a width — but on 3.3.5a
that width TRUNCATES with an ellipsis rather than wrapping. An explicit `SetWidth` wraps, which is why
`SettingsControls`' own `AddText` has always set one. The height then follows from `GetStringHeight`,
so the frame grows around whatever the text turns out to be.

Nine mutations, each failing by name: the confirm parented to `UIParent`, its level not raised above
the dialog, the blocker never shown, the confirm placed under its own blocker, Reset firing without
asking, the confirm surviving a viewer switch, No doing what Yes does, the two-anchor sizing put back,
and the height returned to a constant. A tenth — raising the blocker — turned out not to be a
regression at all: the confirm's level is derived from the blocker's, so they move together, which is
the property that makes the ordering structural rather than a pair of constants to keep in step.

#### H.3.15. The sliders stop being 2004, and Revert learns to explain itself

Two reports in one pass. **"The revert button on the CDM window does nothing. What is it currently
designed to do?"** — and the answer is that it was doing exactly what it was built to do, which turned
out to be the problem. That Revert (the /cdm footer, next to the layout picker) is a ONE-STEP session
undo for *layout* operations only: apply, import, starter reset. It is disabled the rest of the time,
and cleared when the window closes so a stale undo from an hour ago can never fire. So for a player who
has never touched layouts it is permanently grey — and, because **a disabled Button eats OnEnter on
3.3.5a**, permanently mute. The tooltip that would have answered "what would this even undo?" only
existed in the one state nobody needed it. `SetMotionScriptsWhileDisabled(true)` gives it back, and
the tooltip now adds a reason line while it is unavailable, naming what it covers (layouts) and what it
does not (the per-viewer settings, which revert from the edit-mode panel instead). The button's
*behaviour* is unchanged; it was never broken, it was illegible.

**"Can we get the horizontal scrollbars in the new settings matching the earlier NewEra screenshots?"**
— the sliders. NewEra builds every edit-mode slider from retail's `MinimalSliderWithSteppersTemplate`
(`EditMode/SettingsPopup.lua:173`), whose art is sheet 4567914, the `minimal_sliderbar_*` family.

**This shipped twice, and the second version is the one to read.** The sheet was not in the NewEra Art
set, so the first build substituted: the minimal *scrollbar* art IS shipped, and it is the same rounded
bar at right angles, so the horizontal slider borrowed the vertical one's pieces and turned them 90°
via a new `NE.tex.SetAtlasRotated` — the **eight-argument** `SetTexCoord`, which names all four display
corners independently and is the only way to rotate art on 3.3.5a (`Texture:SetRotation` is retail).
Then the owner supplied 4567914, and the whole workaround came out: rotation helper deleted with it,
since a primitive whose only caller has gone is dead code. *For future missing art, ask — the owner
supplies it.*

The sheet is 32×128 and carries the entire widget: both rounded track caps (11×17), the **one-pixel**
run that tiles between them, the little **diamond** thumb (20×19), and both chevron steppers (11×19 and
9×18). `NE.scrollbar.SkinSlider` rebuilds it piece by piece at those native sizes. Only the run
stretches; the caps keep their own width, which is the rule the dropdown's textholder learned the hard
way when stretching a rounded rect smeared its corners. The Slider is sized to the **knob**, not the
track, so the diamond stands two pixels proud of the bar and the whole of it falls inside the frame's
own mouse region.

`OptionsSliderTemplate`'s groove goes whole — it is a *backdrop* of `UI-SliderBar-Background` inside a
beveled border, not a region that could be re-pointed. The compact slider's nudge arrows became the
sheet's own chevrons: they were the spellbook's page-turn glyphs, which is the mismatch the whole pass
is about. The button stays 18px, because the row's arithmetic is written against `ARROW_W`; only the
glyph takes the atlas's size.

**No hover or pressed art, deliberately.** The sheet has one diamond and one chevron per direction,
because retail's minimal slider does not change art on either — the feedback is the thumb moving. The
first build *did* swap three states per piece, but only because the scrollbar art it was borrowing has
them; carrying that over would have been this addon's idea wearing the reference's clothes. The
steppers keep a one-pixel pressed offset, which is the only feedback this art affords, and a test
asserts the sheet has no `-over` variant so nobody re-adds a tint and calls it fidelity.

Both slider kinds are skinned, the tall two-line one on the tab as well as the dialog's compact one:
the skin belongs to the kit, not to the dialog that asked for it first.

Assertions read the rendered **texcoords**, never the atlas name: all six pieces come off one file, so
the texture path is identical whichever rect a piece ends up wearing, and "did the left cap get the
left cap's rect" is a question only the coordinates can answer. Seven mutations fail by name — the
track caps swapped, the thumb wearing a cap instead of the diamond, the groove left in place, the caps
stretching with the bar, the steppers swapped, the pressed glyph not nudged, and the Slider sized to
the track instead of the knob. That last one took two attempts: the first assertion read the *thumb's*
height against a constant, which cannot see a change to the *frame's*, so it passed the mutation
unmoved. Rewritten to compare the two heights directly.

One mutation from the first build was **not** caught, and was right not to be: `applyState` re-asserted
the caps' drawn size in case `useAtlasSize` snapped them back to native — but those caps were 8×8
*squares*, so rotation returned exactly the size they already had, and the only caller that could have
made the guard matter was a `thickness` option nobody passed. Guard and option deleted before the art
arrived and made the whole path moot.

#### H.3.16. Submenus stop demanding you aim at the arrow

> "The effects dropdown menu has issues where i have to specifically mouse over the arrow which makes
> navigating annoying"

The FX Style submenu on the alert menu — and every other submenu we build, the ready-sound tree
included. Hovering the row did nothing; only the 16×16 `$parentExpandArrow` at the right edge opened
it, and a diagonal approach to it across the row shut whatever had just been opened.

**Same 3.3.5a quirk as §H.3.15's Revert button, wearing a different hat: a disabled Button eats
OnEnter.** Submenu parents are `notClickable` — deliberately, and §H.3.15's reason still holds, because
UIDropDownMenu's OnClick ticks the row's Check texture before it ever looks at `func`. But
`C_UIDropDownMenu.lua:172` turns `notClickable` into `info.disabled`, and disabling costs the row two
things at once:

1. its own `OnEnter` — which for a `hasArrow` row is the thing that calls `C_ToggleDropDownMenu` on
   level+1. Silenced.
2. `$parentInvisibleButton` goes **up** (line 179). It covers the row, and its `OnEnter` calls
   `C_CloseDropDownMenus(level + 1)`. So the row body did not merely fail to open the submenu — it
   actively closed one.

Between them, the arrow was the only door and the row was a wall in front of it.

`NE.menu` cannot fix this in ClassicAPI — read-only, §0 — so `openOnHover` does it per row, after
`AddButton` has written it: `SetMotionScriptsWhileDisabled(true)` and take the invisible button down.
The tooltip that button existed to serve is on the row's own `OnEnter` too (`C_UIDropDownMenu.xml:157`),
so nothing is lost, and `AddButton` re-shows it on the next build regardless.

**It is set on every row, `false` included.** These list buttons are shared with every
`C_UIDropDownMenu` in the game; one left motion-enabled is a disabled title in some later menu that
hover-highlights for no reason. Handing it back on non-submenu rows is what keeps the change from
leaking, and is its own assertion.

The harness gained `$parentInvisibleButton` and the one rule that governs it — shown on any disabled
row, and `notClickable`/`isTitle` both *become* disabled two lines before that check. Without it in the
stub, taking the button down would have tested identically to forgetting to. Three mutations fail by
name: the row never told to take OnEnter, the invisible button left up, and the motion flag set
blanket-true.

#### H.3.17. …and the submenu opens where the row is

> "The submenu opens up right next to the main menu then when i move my mouse over to it, the frame
> drops down to where it actually should be"

Letting the row open its own submenu uncovered a second fault that had been sitting under the first,
harmless only because nothing ever exercised it. ClassicAPI picks a level-2+ list's anchor like this
(`C_UIDropDownMenu.lua:397`):

```lua
local anchorFrame = (strsub(button:GetParent():GetName(), 1, 12) == listFramePrefix)
                     and button or button:GetParent()
```

Blizzard's original compares against the **literal** `"DropDownList"` — exactly 12 characters.
ClassicAPI renamed the prefix to `"C_DropDownList"`, which is 14, and left the 12 alone. The test can
therefore never be true, and the anchor is always `button:GetParent()`.

That was invisible while the arrow was the only way in, because an arrow's parent **is** its row —
the right answer, reached by accident. A row's parent is the whole **list**, so the submenu hung off
the top of the parent menu. Crossing the arrow then re-opened it from the arrow, and it dropped into
place: exactly the two-step the owner described.

The correction re-anchors to the **arrow**, not to the row that was hovered. The arrow is a 16×16
child centred in a 16px row, so `TOPRIGHT` is the same point either way — but the arrow's own OnEnter
re-opens the menu unless it finds itself as the anchor already (`C_UIDropDownMenu.xml:94`), and
anchoring to the row would rebuild the whole submenu every time the mouse crossed the arrow on its way
there. Same pixels, no rebuild under the cursor.

The screen-bounds flip from `ToggleDropDownMenu`'s own tail is re-run here too, against the right
anchor this time; a submenu that re-anchored correctly and then fell off the bottom of the screen would
be no improvement.

It hooks `OnEnter` on the row, which cannot be un-hooked, on a button shared with every menu in the
game — so the hook asks whether `C_UIDROPDOWNMENU_OPEN_MENU` is ours before it moves anything, and
that guard is its own assertion. The level is closed over rather than read back off the parent: a
button belongs to exactly one list forever and its name already says which.

918 assertions. Six mutations fail by name: no fix at all, anchored to the row, the ownership guard
dropped, the wrong corner, the old points left in place, and the off-screen flip removed.

#### H.3.18. The module ships disabled

> "I want this module to be set to disabled by default."
> "When disabled the cdm window shouldnt be loadable via settings or /cdm."
> "When going to the window via the settings menu it should go to the Spells tab by default."

Owner's decision, and the only NewEra module that ships off. The reasoning is worth recording because it
does not generalise: everything else here **replaces** something the player already had — a nicer
character sheet, a nicer guild window — so shipping it on ships an improvement. Four viewers in the
middle of the screen replace nothing. They are new HUD furniture, sized and placed by us, over whatever
the player has already arranged there, and deciding that for them on first login is the one thing a HUD
addon should not do.

`M.IsEnabled` fell through to `true`; it now falls through to `false`. That single flag is the whole
gate, deliberately — nothing else keys off it, so a profile that switches it on later reads exactly the
same curated lists, layouts and alerts as one that had it on all along. There is no seed to miss and no
first-run path that only happens while it is on.

Flipping the default turned four places that had been merely *quiet* while disabled into places that were
**wrong**, because "disabled" had never been the state anyone actually shipped in:

* **Edit mode offered four handles for it.** `NE.RegisterHUDFrame` defaults `editorVisible` to "always
  offer it", which is right for a HUD frame that is only *empty* right now — that is what `showTest` is
  for — and wrong for one the player has never turned on. Out of the box `/dui edit` would have opened
  onto four green rectangles full of demo icons for a feature that has never been on screen. DragonUI
  honours a false `editorVisible` by hiding the anchor and skipping `showTest` (`core/api.lua:1239`).
* **The viewers kept working.** Frame events do not care whether a frame is shown, so every player who
  never turned the Cooldown Manager on would still have paid for `SPELL_UPDATE_COOLDOWN`, `UNIT_AURA`,
  `BAG_UPDATE_COOLDOWN` and the rest for the whole session, re-reading cooldowns to repaint tiles nobody
  can see. Gated at both `OnEvent` entry points — the base's, and `auraViewerOnEvent`, which answers the
  two hottest events on this client itself and never reaches the base. Safe to **drop** events rather
  than queue them: switching on runs through `UpdateVisibility`, whose `Show` fires `OnShow`, and
  `OnShow` is `Rebuild`, so the catch-up is a full re-read from scratch. Not gated on `IsShown()` — a
  viewer hidden by its own category or by "In Combat" still has to track state or it comes back wrong.
* **The ready sounds kept playing.** The alert ticker early-outs when nothing is assigned, which is not
  the same question. A player who assigns sounds, switches the module off, and then keeps hearing it
  announce cooldowns for viewers that are not on screen has a haunted UI. (A latent fault before this,
  since the toggle already existed; off-by-default is what made it worth fixing.)
* **The window was still reachable, and configured viewers it could not show.** The owner's answer, on
  the second message: the window is part of the module, so an off Cooldown Manager has no window. Every
  route in — `/cdm`, the options button, `OpenTo` — funnels through `ShowPanel`, so one gate covers it,
  and it sits **before** `build()`: the panel is several hundred frames built lazily on first open, and
  a player who never turns the module on should never pay for them. `M.SetEnabled` closes a window that
  is already up, for the one case the player can reach — open `/cdm`, then untick the toggle. Closing is
  never gated, so `/cdm` stays the way to shut it either way.

That last one also settles a question off-by-default would otherwise leave open: **where** a player goes
to switch it on. Not the window, which would be a dead end configuring viewers it cannot show — the
switch is in DragonUI's options, where every other module's is, and the refusal message names it.

And the options button now opens on **Spells**, not Settings. The first thing anyone wants after turning
the module on is to see and change what it tracks; Settings is one click away on a tab already on screen.
The link on the edit-mode dialog still opens on Settings — that one exists to reach the non-per-viewer
settings by name, so it means it.

**Existing profiles:** one that never touched the toggle stored nothing, so it lands on the new default
and the viewers are hidden after this change. One tick brings back the exact setup that was there —
disabling has never deleted anything — and the branch is unreleased, so no adoption migration was added.

934 assertions, and the boot block asserts the *off* state before anything turns it on, since that is the
state the rest of the file spends its time not being in. Nine mutations fail by name: the default back to
`true` (10 failures), `editorVisible` dropped, either event gate dropped, the ticker gate dropped, the
window gate always allowing, `OpenTo` gated only via `ShowPanel`, `SetEnabled` not closing the window,
and the options button back on Settings. The aura-viewer gate is probed through `_lastShownCount` rather
than the item count — a profile with nothing tracked yet has zero items either way, so asserting on the
count would have passed against the missing gate.

#### H.3.19. The rotation spells, and why no class had any

> "Lots of classes are missing default abilities that dont have cooldowns. Such as druids with wrath,
> which i have added myself. Can you do a pass over classes and make sure the default rotation spells
> are in for eahc spec?"

Not an oversight in the curation — **the generator could not express one.** `resolve.py` defines a
"castable" id as the lowest-rank entry carrying a cooldown `> 1.5s`, which is a good test for telling
an ability from its triggered sub-spells and a useless one for asking whether something is an ability.
Wrath has no cooldown. Neither does Frostbolt, Shred, Steady Shot, Shadow Bolt or Sinister Strike. Every
one of them resolved to nothing, and `gen_wotlk.py` treats an unresolvable name as a hard error, so no
rotational spell could ever have reached the seed. The owner's four hand-added Druid ids were the only
ones in the file, and the next `gen_wotlk.py` run would have deleted them — `verify.py` rejects a
no-cooldown id outright.

**A second resolver, not a relaxed one.** `resolved_any.json` drops the cooldown test and replaces it
with the two rules that test was standing in for, both picked by reading candidate dumps
(`explore_nocd.py`, new, prints each class's no-cooldown non-passive non-talent abilities — the menu the
curation is authored from) rather than by argument:

* **Prefer an explicit `Rank 1`; fall back to unranked only when nothing is ranked.** Rejuvenation
  forces it — fifteen ranks plus an *unranked* sixteenth (`64801`, the glyph's), and sorting by rank
  number puts that one first, because an unparseable rank string scores 0. It is the same trap
  `gen_alertdata.py` documents for Overpower, in the other direction.
* **Drop passives.** Without a cooldown filter, nothing else keeps talent passives out of a list of
  things to press.

Emitted as its own `ROTATION_ADD` table rather than more rows in `ESSENTIAL_ADD`, which is what lets
`verify.py` keep asserting "carries a real cooldown" of the two tables where that holds. In the rotation
table the assertion is inverted — an entry that *does* carry a cooldown is an error — and that is how
Crusader Strike (4s) and Flame Shock (6s) got moved up into Essential where they belong.

**The class attribution was wrong, and the cooldown filter had been hiding it.** `skill2class` was a
bare `most_common(1)` over every skill line. Skill line 202 is **Engineering**: 321 rows, 287 with no
class mask, and the 34 that have one split 10 PALADIN / 9 SHAMAN / 9 DRUID — class-restricted engineering
items — so `most_common` broke the tie for PALADIN and handed a profession's inventory to paladins. Line
777 is **Mounts**, category 7 like the real class lines, unanimously PALADIN on the strength of 4 rows
out of 315. Invisible while every answer had to carry a cooldown; it surfaced the moment the rotation
resolver stopped filtering, as PALADIN reporting **661** abilities against 60–100 for every other class.
Fixed with category 7 + Mounts excluded by name + 90% dominance, and verified to change **not one id**
in the existing curation. Per-row class masks instead of the vote was tried and is worse: it loses every
talent-granted ability (Penance, Starfall, Dispersion, all of DEATHKNIGHT), whose rows carry mask 0.

**Two collision guards**, because the seed appends to `ClassData.lua` and `appendAll` dedupes by **id**,
which is not the same as deduping by ability. `ClassData` lists Multi-Shot as `14288`; the resolver
answers `2643`. Both real, both survive an id dedupe, and the viewer shows one spell twice. So the
comparison is by NAME with every vanilla id mapped back through `Spell.dbc` — same id is redundant and
merely printed, a different id is a hard error. Nine rotation names were dropped that way.

**And it found live bugs in `ClassData.lua`.** The guard's first version matched the two table headers
on entry and nothing on exit, so it ran on into the buff tables and raised a false alarm — which was
worth having. Auditing every id in the file against its own comment turned up 23 disagreements. Most are
vanilla→WotLK renames where the id is right (Blessing → Hand of Protection/Freedom, Soulstone → Create
Soulstone, Arcane Intellect (Greater) → Arcane Brilliance). Twelve are genuinely wrong ids, and all
twelve sit in `BUFFICON_BY_CLASS` / `BUFFBAR_BY_CLASS`, which `CooldownViewer.lua:789` records as unused
— the aura viewers auto-track instead. Left alone as dead data, listed in the session notes.

The two that were **not** dead are Mage's, and between them they cost mages a core button: `12472` was
listed in Essential as "Cold Snap" and is **Icy Veins**; `11958` was listed in Utility as "Ice Block" and
is **Cold Snap**. Two wrong labels, and Ice Block absent from every list. Both entries are dropped from
`ClassData.lua` and all three abilities are now curated by name in the generator, which resolves them
from the DBC.

Curation is per CLASS, not per spec, because that is all the tables can express — the runtime gate is
"has the player learned it" plus the talent gate, and every druid has learned Wrath. So each list is the
union across a class's specs, and the per-spec layouts (§F2) are where a player prunes it. A Feral druid
finding Balance's nukes in the picker is the cost of a Balance druid finding them there at all.

232 ids verified against the DBC. Two mutations fail by name: the rotation table never appended (4
failures), and Wrath listed at its max-rank id instead of rank 1.

#### H.3.20. Starter layouts per spec, and how to tell what spec you are

> "Yes lets do starter layouts per spec. Although im not sure the besty way to decide what spec for
> lower levels? Would it be just talent points spent?"

Yes — and `GetTalentTabInfo(tab, false, false, group)` takes a **talent group**, which is what makes it
usable for the inactive spec's bucket as well as the active one. Without that argument dual spec would
detect the same tree twice.

The honest limits, since the question was about low levels:

* **Levels 1–9 there is no signal at all.** Zero points; a pick would be one in three.
* **At 10+ the first point is already a declaration of intent.** Someone who spends point one in Balance
  is levelling Balance. It is weak evidence about power and strong evidence about intent — and intent is
  what a starter layout needs, so a single point is enough.
* **An exact tie (5/5/0) has no right answer.**

**The failure that actually matters is not guessing wrong, it is guessing repeatedly.** A layout that
re-derives itself as points are spent would silently overwrite curation every few levels. So detection
runs at the moment of application and nowhere else, which reduces the low-level problem to being right
*once*, with the player present. Owner's calls on the two forks: apply on demand **and** once on a fresh
spec bucket; and when the spec is unreadable, **do not guess** — offer the three trees by name.

`M.DetectSpec(group)` therefore returns **nil** for no-points and for a tie, rather than tab 1. The menu
marks the detected tree with "(your spec)" instead of pre-selecting it — detection is derived data and
can be wrong, the same reasoning that keeps "Show Unlearned" on the aura picker.

**Once per bucket is the entire safety argument for the auto path.** `SeedStarterIfFresh` marks the
bucket in the same breath as seeding it, so it can never run twice over curation the player has since
done. It is hung on `NE.spellbook.OnRebuilt` rather than `PLAYER_LOGIN` because that fires once the
client has finished answering about talents — at login and after a spec swap — and it is idempotent, so
firing often is free. A character with no points is skipped **without being marked**, so the first point
they spend still seeds them a starter.

**Disabled, not deleted.** The starter writes a custom list holding every spell in the class's Essential
list, the spec's own on and the rest off, so off-spec spells land under Not Displayed one drag from
returning. Deleting them would make the starter the one action in the window you cannot undo by hand.
**Essential only** — Utility is defensives, interrupts and escapes any spec might press, and the bloat
this answers is all in Essential.

30 lists, authored by name in `gen_wotlk.py` and resolved against **the ids the curated list actually
holds**, not against a fresh resolve: `ClassData` keeps some abilities at a higher rank (Multi-Shot at
`14288`), and a starter carrying the rank-1 `2643` would enable a row the picker has never heard of and
appear to do nothing. A starter name that is not in that class's Essential list is a hard error — and it
is checked against Essential specifically, not Essential+Utility, or a name living only in Utility would
pass and then enable nothing. Tab order is from `TalentTab.dbc`, not memory.

964 assertions. Seven mutations fail by name: no-points falling back to tree 1 (5 failures), a tie
resolving to the first tree, the group argument ignored, the starter deleting instead of disabling, the
seed marker never set, the marker set even when the spec is unknown, and an invalid tab falling back to
tab 1.

#### H.3.21. Unlearned spells are hidden, not tinted

> "I can see spells I havent learnt yet on my druid. For instance Mangle which is a talent i dont have
> yet, it lists under not displayed. I want spells that are not known to be hidden entirely"

One report, three faults. What hid all three for this long is that **no consumer ever hid an unlearned
row — they only tinted it**, so a learn-gate that answered "learned" for nearly everything looked
exactly like a learn-gate that worked.

**1. The gate barely gated.** §E4 replaced an id-keyed check with the spellbook, correctly, but kept the
old checks chained after it "so the change can only widen what shows, never narrow it". The last link is
`GetSpellInfo(name)`, which on this client answers from the spell **database** — §E4's own bullet list
says so two lines earlier. A chain whose last link says yes to every ability in the game is not a gate.
The fallbacks are now reached only when `SB.EnsureBuilt()` reports no book at all; with a book, the book
is the answer. The condition is deliberately "built", not "non-empty": an empty book is a real answer for
a character with no spells, whereas *not built yet* is the absence of one, and there the gate still fails
**open** — showing an ability the player lacks beats hiding one they have because a scan had not run.

**2. Not Displayed ignored the gate entirely**, by an explicit decision recorded in the code: a fresh
character seeing an empty picker reads as broken. True, but the price was worse than the disease.
`Mangle (Bear)` sat in a section whose name means *you chose not to show this*, one drag from a row that
could never light up, and the red tint's "not yet learned" contradicted the heading rather than
qualifying it. The catalog now honours **Show Unlearned** like every other spell section — the setting
already existed and already meant this; it simply did not reach here. The empty-picker worry is answered
where it belongs, in the section's empty text, which names the setting instead of saying "(empty)".

**3. `IsTrackable` waved the whole arsenal through.** Its escape hatch — *an id outside the curated set
is a user-added external, so always trackable* — was written when the curated lists were the only class
data. `M.ARSENAL_BY_CLASS` is 296 more ids that are nothing but class abilities, and `Mangle (Bear)` is
one of them (the seed curates the Cat form). So the gate was never consulted for most of the picker, and
the moment a player dragged an arsenal-only ability into a viewer it rendered whether they could cast it
or not. The arsenal now counts as class data for the gate. The hatch still exists, and still has to —
delete it and every user-added trinket use-spell vanishes, which is its own mutation below.

The picker surfaces ask `M.IsSpellLearned` (new, the raw test) rather than `M.IsTrackable`: on a picker
row every entry is a class ability by construction, so "not in the class tables" means nothing there.
Gating the catalog on `IsTrackable` would have hidden Mangle (Cat), which the seed curates, and kept
Mangle (Bear), which it does not — the exact inversion of the report.

Regenerating `CdmArsenal.lua` for the new footer also collected the §H.3.19 attribution fix, which had
never been applied to this table: seven ids leave, all of them the bug that fix describes — `Stuck` and
`Summon Friend` under DRUID, `Wormhole: Gadgetzan` under PALADIN, and four racials filed under ROGUE and
WARRIOR. Its header had also drifted, still saying "Hidden" where the file on disk had been hand-edited
to the §H.3 rename; the generator now carries the current wording so the next regen keeps it.

984 assertions. Ten mutations fail by name: the database fallback restored unconditionally (2 failures),
the gate failing closed with no book, the arsenal dropped from the class-ability set (2), the external
hatch deleted, the catalog skipping the learn gate (2), the catalog ignoring Show Unlearned (3), the
empty text back to "(empty)", and the tile tint stuck on, stuck off, or flagged without desaturating.
Two mutations are **equivalent, not uncaught**, and worth naming so nobody re-tests them: gating the
catalog on `IsTrackable` now behaves identically, because widening the class-ability set to include the
arsenal made the two agree for every id the catalog can hold; and dropping `CdmArsenal.lua`'s
`InvalidateCuratedCache()` footer changes nothing in a harness that loads every file before the first
assertion, which is the one ordering it exists to protect against.

#### H.3.22. Not Displayed is the catalog minus what is on screen

Reported as "Gift of the Naaru is showing twice — under Utility and Not Displayed". It was every racial,
for every race that has one, on every class: Blood Fury for Orcs, Berserking for Trolls, Stoneform for
Dwarves, Cannibalize and Will of the Forsaken for the Forsaken, and so on. Only Human was clean, and only
because its racial lists in `ClassData.lua` are deliberately empty.

The catalog is defined as *the arsenal minus what is placed*, and `SettingsAdapter.lua` computed the
subtrahend with its own `isPlaced` — a second implementation of the placement rules that read the custom
list and fell back to the curated defaults. `GetActiveSpellList` answers the same question, and it does
one more thing: `appendRacials` merges the player's racials into both lists at render time, because
racials are class-agnostic and were never in the editable seed. The copy had no idea that merge existed,
so a racial was placed and unplaced simultaneously — rendered by the viewer, and offered again by the
catalog as something the player had chosen not to display.

`isPlaced` is replaced by `placedSet`, which asks `GetActiveSpellList` for each display category and
unions the results. Two properties follow that the old shape could not have:

* **Duplication becomes impossible by construction.** `GetItems` renders `GetActiveSpellList(cat, showAll)`,
  and `placedSet` subtracts `GetActiveSpellList(cat, true)`. The `includeUnlearned` list is a strict
  superset of the gated one — the only difference is the `IsTrackable` filter — so anything on screen is
  necessarily subtracted. Any *future* merge into a display list is inherited rather than re-missed.
* **The round trip survives.** Suppressing racials in the catalog would have fixed the duplicate and made
  a removed racial unrecoverable. Instead, removing one writes it disabled into the custom list, which is
  exactly what `appendRacials`' `exclude` set reads, so it leaves the viewer and appears in the catalog —
  once — ready to drag back.

`includeUnlearned` is `true` deliberately: this asks about PLACEMENT, not castability. Gating it would
call an unlearned-but-placed spell unplaced and hand it back to the catalog, restoring the double listing
for a second, unrelated reason. `M.GetActiveSpellList` gained an optional third `class` argument for this
caller, which carries a class down from `Adapter.GetItems`; every viewer still gets the player's.

The suite could not have caught this. The pre-existing overlap check runs as a Human — the one race with
nothing to duplicate. The new §H.3.22 block switches race, asserts the merge/subtract/round-trip cycle,
and then asserts the invariant itself across both spell categories with Show Unlearned each way. 992
assertions. Two mutations fail by name: `placedSet` re-deriving placement instead of asking (the original
bug, reproduced exactly), and placement gated on learnedness.

#### H.3.23. One tile per ability, not per spell ID

Reported as "two versions of Icy Touch, the correct one and another with just the name and icon", after
§H.3.22 had removed the id-level duplicates. This is the other half: an **ability is not an id**.
`Spell.dbc` holds a row per rank plus variants that never reach a spellbook, so one ability can enter a
list under two ids and render as two identical tiles — the tile draws `GetSpellInfo`'s name and icon, and
by construction those match.

Five abilities are in that state, because the arsenal is generated and the curated tables are authored
and for these five they picked different rows for the same thing:

| Class | Ability | arsenal | curated |
|---|---|---|---|
| DEATHKNIGHT | Icy Touch | 52372 | 45477 (essential) |
| HUNTER | Multi-Shot | 2643 (R1) | 14288 (R2) |
| PALADIN | Hammer of Justice | 853 (R1) | 10308 (R4) |
| PALADIN | Judgement of Wisdom | 53408 | 20186 (R1) |
| ROGUE | Sprint | 2983 (R1) | 11305 (R3) |

**The data is deliberately left alone.** Every runtime read resolves through `highestKnownRankID`
(ItemMixins), which maps a spellID to the player's highest KNOWN rank BY NAME — so any id for an ability
lands on the same cooldown, icon and tooltip, and none of these five misbehaves in a viewer. Rewriting
curated ids would churn saved layouts for no functional gain. Two are worth recording anyway, as data
notes rather than bugs to fix here: `52372` is the untrained Icy Touch variant (`classmask=0`) against
curated `45477` (`classmask=0x20`, the trained DK rank 1); and curated `20186` is the *vanilla* Judgement
of Wisdom (Rank 1, skill line Holy) where WotLK's player-cast version is `53408` (skill line
Retribution) — the arsenal has the better id there, and name resolution is why it has never shown.

`classmask = 0` is **not** a "not a player ability" signal and must not be used as one: 72 of the 296
arsenal ids have it, and most are talents (Starfall, Penance, Preparation, Last Stand).

The dedupe lives in **`GetActiveSpellList`**, not in the picker, because the live viewer reads that same
function — a picker-only fix would have left two identical tiles on the cooldown bar itself. The catalog
adds the other half in `hiddenSpells`: a name already on screen, or already emitted during the walk, is
not offered again. Three guards, each load-bearing in a different situation:

* `ownerByName` — the CURATED id wins a collision even though the catalog walks the arsenal first.
  Nothing functional rides on it; consistency does, since the seed, starter layouts and presets all name
  the curated id.
* `placedNames` — the placed id is not always in a pool the catalog walks. Regenerating `CdmArsenal.lua`
  drops ids (seven left it in §H.3.21), and a saved layout goes on holding one; nothing then marks its
  name in passing.
* `seenNames` — two generated ids for one ability, neither placed nor curated. Nothing outside the walk
  can arbitrate, so the walk keeps the first.

An id the client cannot name is never collapsed: `GetSpellInfo` returns nil, there is nothing to compare,
and treating "no name" as one shared name would merge unrelated abilities into a single tile.

1001 assertions. Six mutations fail by name: the dedupe removed from `GetActiveSpellList`; the catalog
ignoring what is on screen under another id; the generated twin winning the collision; no within-walk
name memory; and `or ""` for a missing name in either file, which collapses every unnamed id together.
The fixture builds its own twins rather than asserting against the five above, so it keeps meaning the
same thing after any regeneration.

Verified in bulk out-of-band as well: a probe that feeds the harness all 49,839 real `Spell.dbc` names
and walks 10 races × 10 classes reports one tile per ability everywhere, and reports exactly the five
collisions above when the dedupe is disabled.

#### H.3.24. A short trailing row centres under the full ones

12 essential icons at an icon limit of 9 wrap to 9 + 3, and the 3 were flush against the start edge —
visibly off-centre under the row above. `core/GridLayout.lua` now takes `centerPartialLines`, and every
viewer sets it in `BaseViewerMixin:RefreshLayout`.

A *line* is the axis `stride` counts along: a row when horizontal, a column when vertical. The offset is
half the line's shortfall against the laid-out bounds, measured as the furthest child edge rather than a
sum of cell sizes — so a line of mixed-width children (the BuffBar's bars) measures what it actually
occupies. A line that fills `stride` measures the full extent and gets 0, which is what keeps the columns
of a multi-row grid aligned with one another.

The offset is folded into `x`/`y` **before** the `layoutFramesGoingRight` mirror, not after. Mirroring
reflects a line about the frame's centre and the centring offset is symmetric about that same centre, so
ordering it first is exactly what flips its sign for a leftward grid — there is no separate mirrored case
to get wrong. Vertically there is nothing to mirror at all: `rowY` is always measured from whichever edge
`layoutFramesGoingUp` picked, so the same `+off` serves both stack directions.

The flag defaults off in the mixin, so the alert and preview grids that also use it are untouched.

`test_gridlayout.lua` covers the owner's 9+3 case, the flag being off, the mirrored grid, an evenly
dividing grid getting no offset at all, vertical short columns in both stack directions, and the offset
being converted back into child units under `iconSize` scaling.

## H.4. Suggested order

**Phase 7 is done; what follows applies to 8 and 9.**

**Phase 7 first**, and not because it is a bug: 8a is a bigger visible change, but the Tracked Buffs
tab is currently a feature that appears broken on every character, and it is also blocking target-DoT
tracking. 7a-7c are contained (one registry, one adapter branch, one empty state).

**Then 8a**, which is the largest look-and-feel change per line of code in the whole port — three
registrations turning bare icons into Cooldown Manager tiles. **Then 8c** (the glow, small and it
closes the last guide feature), **8b** (the swipe, needs measuring), **8d/8e** (screenshot work).

8a, 8c, 8d (§H.2.9) and 8e (§H.2.10) are done. Both of the "screenshot work" items turned out to have
one real defect each behind a pile of things that were already correct, and in both cases the defect
was found by decoding the art rather than by looking at a screenshot: `Bar-BG` stretching its 1px edge
lines up to 3.1x, and 8e's premise that the pandemic ring needed a mask substitute when the art is
already a hollow ring.

§H.2 is closed. **8b was measured and declined** (§H.2.11): it was indeed the one item that could make
things worse, and it would have — `CooldownCaptureShow` zeroes the Cooldown frame's alpha, which takes
our countdown numbers with it, for ~200 frames' cost and a capability 8c already substitutes for.

**Phase 9 is done** (§H.3), and the prediction held: it was bookkeeping absorbed by the phases above,
apart from the "Not Displayed" rename. What the estimate missed is that "a one-line owner preference"
was five strings, not one — the label reached the player through the empty-state text, a trinket
tooltip and the Settings tab's help text as well as the two category headers, and the right-click
menu's "Move to …" only followed for free because it already read `Adapter.Label`. The single line it
was *not* was the stored assignment value, which had to stay `"hidden"`.

Phase 7 and 8a are also the two that most want an in-game pass immediately after, which argues for
doing them before the deferred verification of 4b-4 / 4b-5 / 5a / 4c rather than after — one trip
through the game covering all of it.

**Nothing in the phasing tables is left.** What remains is not port work: §G.9 consumables (parked by
the owner), and the in-game passes listed at the top — §F4, §F5, and 4b-4 / 4b-5 / 5a / 4c / Phase 6.
