# compat/ — Modern-API Coverage Matrix

`!!!ClassicAPI` is now a **HARD dependency** (`## Dependencies: DragonUI, !!!ClassicAPI`). Because of
its `!!!` name prefix **and** the dependency ordering, ClassicAPI's files run **before** any
`compat/` file. ClassicAPI therefore **owns** the modern C_* namespaces; `compat/` no longer vendors
fallbacks for anything ClassicAPI provides — it ships **only** the handful of symbols ClassicAPI does
not define.

Each surviving `compat/` file still uses the `C_X = C_X or {}; if not C_X.Fn then C_X.Fn = … end`
guard, so a real ClassicAPI impl is never clobbered; with ClassicAPI loaded first these guards are
simply already satisfied for the symbols it owns.

**Source legend**
- `ClassicAPI` — provided by `!!!ClassicAPI` (loads first). **No compat/ shim shipped.**
- `compat` — `compat/` defines it because ClassicAPI does NOT.
- `stub` — `compat/` defines it but it CANNOT answer correctly on 3.3.5a (and ClassicAPI does not
  emulate it); returns a safe value. Recorded at runtime in `NE.compat.stubs`.
- `DragonUI` / `global` — satisfied by base DragonUI or a native 3.3.5a global.

---

## Owned by ClassicAPI — compat/ ships NOTHING

| Namespace / symbol | Where ClassicAPI defines it |
|---|---|
| `C_Timer.After` / `NewTimer` / `NewTicker` | `Util/C_Timer.lua` (AnimationGroup pool). **`compat/C_Timer.lua` deleted.** |
| `C_Texture.GetAtlasInfo` / `GetAtlasExists` / `RegisterAtlas` / `RegisterAtlasTable` / `AtlasData` | `Util/C_Texture.lua` (full atlas registry, identical return shape). **`compat/C_Texture.lua` deleted.** |
| `Mixin` / `CreateFromMixins` / `CreateAndInitFromMixin` | `Util/Mixin.lua`. ClassicAPI defines all three (see note below re: `compat/Mixin.lua`). |
| `C_Container.GetContainerItemInfo` (TABLE) / `GetContainerItemID` / `GetContainerItemLink` / `GetContainerNumSlots` / `GetContainerNumFreeSlots` / `UseContainerItem` / `PickupContainerItem` | `Util/C_Container.lua` |
| `C_Item.GetItemInfo` / `GetItemInfoInstant` / `GetItemIconByID` / `GetItemCount` / ItemLocation family | `Util/C_Item.lua` |
| `C_Spell.GetSpellInfo` / `GetSpellName` / `GetSpellSubtext` / `GetSpellTexture` / `GetSpellCooldown` / `GetSpellDescription` / `GetSpellLink` | `Util/C_Spell.lua` |
| `C_SpellBook.GetSpellBookItemName` (+ global) / `PickupSpellBookItem` (+ global) / `GetSpellLinkFromSpellID` / `HasPetSpells` | `Util/C_SpellBook.lua` |
| `C_Map.GetBestMapForUnit` / `IsWorldMap` / `WorldMap` | `Util/C_Map.lua` |
| `C_NewItems.*` | `Util/C_NewItems.lua` |
| `GetItemInfoInstant`, `GetPhysicalScreenSize`, `SearchBoxTemplate` (XML) | `Util/C_Item.lua`, `Util/PixelUtil.lua`, `Templates/UIPanelTemplates.*` |
| `C_UIDropDownMenu_Initialize` / `_AddButton` / `_CreateInfo` / `C_UIDropDownMenuTemplate` | `Templates/C_UIDropDownMenu.{lua,xml}`, reached via `Load.xml` → `Templates/Load.xml`. Note for any menu deeper than two levels: this grows `C_UIDROPDOWNMENU_MAXLEVELS` on demand (`:124-130`), which the 3.3.5a global does not. **Consumer: `core/Menu.lua`** — it prefers these over the native `UIDropDownMenu_*` for exactly that reason (the Cooldown Manager's ready-sound menu is three levels), and falls back to the native two-level API if ClassicAPI is ever absent. |

`C_GetContainerItemInfo` table fields ClassicAPI returns
(`iconFileID/stackCount/isLocked/quality/isReadable/hasLoot/hyperlink/isFiltered/hasNoValue/itemID/isBound`)
**match** the fields v1 reads (`.iconFileID/.stackCount/.isLocked/.quality/.hyperlink/.itemID`). No adapter needed.

---

## Shipped by compat/ — symbols ClassicAPI does NOT provide

| Symbol | Source | compat file | Notes |
|---|---|---|---|
| `Mixin` / `CreateFromMixins` / `CreateAndInitFromMixin` | compat (redundant — see note) | `Mixin.lua` | Retained pending review; ClassicAPI's `Util/Mixin.lua` already defines these and loads first, so the bodies here are dead at runtime. |
| `C_Container.GetContainerItemCooldown` | compat | `C_Container.lua` | Forward to 3.3.5 global. ClassicAPI marks this INCOMPLETE (it ships `GetItemCooldown`, not the container variant). Used by `core/ItemGrid.lua` (cooldown swipe). |
| `C_Container.GetContainerItemQuestInfo` | compat (partial) | `C_Container.lua` | Positional → table `{isQuestItem,questID/questId,isActive}`. ClassicAPI marks this INCOMPLETE. Used by `core/ItemGrid.lua` (quest-item border). If the 3.3.5 global is absent, returns empty — **partial**, recorded. |
| `C_Item.GetItemSpell` | compat | `C_Item.lua` | Forward to 3.3.5 global. ClassicAPI's `C_Item` has no `GetItemSpell`. Used by `core/ItemGrid.lua`. |
| `C_Item.GetItemQualityColor` | compat | `C_Item.lua` | Forward, or fallback to `ITEM_QUALITY_COLORS`. ClassicAPI's `C_Item` has no `GetItemQualityColor`. |
| `C_Spell.GetSpellPowerCost` | **stub** | `C_Spell.lua` | 3.3.5 has no per-spell power-cost API and ClassicAPI does not emulate one → returns `{}`. Source does `… or {}` then `pairs()`, so the cost overlay shows nothing. Recorded. |
| `C_Map.GetMapInfo` | **stub** | `C_Map.lua` | No uiMapID→metadata on 3.3.5; ClassicAPI doesn't define it. Returns nil. Recorded. v1 never calls C_Map. |
| `C_Map.GetPlayerMapPosition` | **stub (partial)** | `C_Map.lua` | Wraps legacy `GetPlayerMapPosition` in a `:GetXY()` object; ignores uiMapID. ClassicAPI doesn't define it. Recorded. |
| `GetSpellBookItemTexture` (global) | compat | `SpellBook.lua` | Maps to 3.3.5 `GetSpellTexture(slot,bookType)`. ClassicAPI's `C_SpellBook` does not alias this. Used by `modules/spellbook`. |
| `GetSpellBookItemInfo` (global) | compat | `SpellBook.lua` | Returns `"SPELL", spellID` (spellID parsed from the hyperlink). No 3.3.5 / ClassicAPI equivalent. Used by `modules/spellbook`. |
| `GameTooltip:SetSpellBookItem` | compat | `SpellBook.lua` | Aliased to `GameTooltip:SetSpell`. No 3.3.5 / ClassicAPI equivalent. Used by `modules/spellbook`. |
| `C_EquipmentSet.*` | compat (custom backend gate) | `C_EquipmentSet.lua` | ClassicAPI ships NO `C_EquipmentSet`. CharacterPanel uses the ItemRack-model custom backend in its own SavedVariables; this file publishes a safe namespace so stray `C_EquipmentSet.*` refs don't nil-error. |

> **Mixin note (for human review):** the task brief listed `compat/Mixin.lua` under "ClassicAPI does
> NOT provide", but `!!!ClassicAPI/Util/Mixin.lua` **does** define `Mixin`, `CreateFromMixins`, and
> `CreateAndInitFromMixin`, and loads first. The file is therefore redundant. It was **kept** to
> respect the explicit brief; it can be deleted (behavior-preserving) once confirmed.

---

## Out of scope (not shimmed; owned elsewhere or by ClassicAPI)

`C_SpecializationInfo.*` (Talents-owned), `C_NewItems.*` (ClassicAPI), `C_MerchantFrame.*`
(MerchantFrame-owned), `C_CVar.*` / `C_AddOns.*` (native globals / ClassicAPI), `C_ActionBar.*`,
`C_Reputation.*`, `C_UnitAuras.*`, `C_FriendList.*` (ClassicAPI), `C_GuildInfo.*`, `C_ChatBubbles.*`
— all **not-needed-v1**.

---

## Runtime self-report

`NE.compat` exposes:
- capability bools: `classicAPI, mixin, container, item, spell, map`
- `NE.compat.stubs` — array of `{ sym, why }` for every symbol that could only be stubbed
  (`C_Spell.GetSpellPowerCost`, `C_Map.GetMapInfo`, `C_Map.GetPlayerMapPosition`, and the no-native
  fallback branch of `C_Container.GetContainerItemQuestInfo`). QA's `/dnetest` can dump this.

## Headline

- `!!!ClassicAPI` is a **hard dependency** and owns `C_Timer`, `C_Texture`, `Mixin`, the bulk of
  `C_Container` / `C_Item` / `C_Spell` / `C_SpellBook`, and `C_Map.GetBestMapForUnit`.
- `compat/C_Timer.lua` and `compat/C_Texture.lua` were **deleted** (fully ClassicAPI-owned).
- `compat/` now ships only ClassicAPI gaps: two `C_Container` fns, two `C_Item` fns, one `C_Spell`
  stub, two `C_Map` stubs, three spellbook globals, and the `C_EquipmentSet` custom-backend gate
  (plus the redundant `Mixin.lua`, retained pending review).
