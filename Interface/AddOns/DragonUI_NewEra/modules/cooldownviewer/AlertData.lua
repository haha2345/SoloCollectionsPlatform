-- DragonUI_NewEra/modules/cooldownviewer/AlertData.lua — GENERATED, DO NOT HAND-EDIT.
--
-- Curated data for the visual-alert engine's "Usable" event (Alerts.lua). A Usable alert flashes a
-- spell ONLY if it appears in one of these tables — retail does not flash every ready spell, and
-- neither do we. Every id below is resolved from this client's own Spell.dbc; only the ability
-- NAMES and their mechanics are hand-authored. Regenerate with tools/cdm-spellgen/gen_alertdata.py.
--
-- Keyed by EVERY rank, because the engine has to recognise the ability at whichever rank the player
-- actually casts — our curated lists key rank 1, but the item's _rankCDIDs carries the learned ones
-- and a custom list may hold any of them.
--
-- COVERAGE NOTE: an entry here only ever fires if the spell is present in a viewer. Of the abilities
-- below, Hammer of Wrath, Kill Shot, Overpower and Revenge are in the curated Essential/Utility
-- lists; Execute, Victory Rush, Riposte and Counterattack are NOT, because those lists are built
-- from abilities with a real cooldown and these four have none. They stay listed so they work the
-- moment a custom list adds them.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer
M.alertdata = M.alertdata or {}
local A = M.alertdata

-- EXECUTE = { [spellID] = hpFraction } — castable only below a target health fraction.
A.EXECUTE = {
  -- Hunter — Kill Shot (target below 20% health)
  [53351] = 0.20,   -- Rank 1
  [61005] = 0.20,   -- Rank 2
  [61006] = 0.20,   -- Rank 3
  -- Paladin — Hammer of Wrath (target below 20% health)
  [24275] = 0.20,   -- Rank 1
  [24274] = 0.20,   -- Rank 2
  [24239] = 0.20,   -- Rank 3
  [27180] = 0.20,   -- Rank 4
  [48805] = 0.20,   -- Rank 5
  [48806] = 0.20,   -- Rank 6
  -- Warrior — Execute (target below 20% health)
  [5308] = 0.20,   -- Rank 1
  [20658] = 0.20,   -- Rank 2
  [20660] = 0.20,   -- Rank 3
  [20661] = 0.20,   -- Rank 4
  [20662] = 0.20,   -- Rank 5
  [25234] = 0.20,   -- Rank 6
  [25236] = 0.20,   -- Rank 7
  [47470] = 0.20,   -- Rank 8
  [47471] = 0.20,   -- Rank 9
}

-- REACTIVE = { [spellID] = true } — usable only after a combat trigger opens a window.
A.REACTIVE = {
  -- Hunter — Counterattack (enabled by a parry)
  [19306] = true,   -- Rank 1
  [20909] = true,   -- Rank 2
  [20910] = true,   -- Rank 3
  [27067] = true,   -- Rank 4
  [48998] = true,   -- Rank 5
  [48999] = true,   -- Rank 6
  -- Rogue — Riposte (enabled by a parry)
  [14251] = true,   -- unranked
  -- Warrior — Overpower (enabled by a target dodge)
  [7384] = true,   -- unranked
  -- Warrior — Revenge (enabled by a block, dodge or parry)
  [6572] = true,   -- Rank 1
  [6574] = true,   -- Rank 2
  [7379] = true,   -- Rank 3
  [11600] = true,   -- Rank 4
  [11601] = true,   -- Rank 5
  [25288] = true,   -- Rank 6
  [25269] = true,   -- Rank 7
  [30357] = true,   -- Rank 8
  [57823] = true,   -- Rank 9
  -- Warrior — Victory Rush (enabled by a killing an XP/honor-granting target)
  [34428] = true,   -- unranked
}

-- Execute HP fraction for a spell: the id itself, then any known rank (the item caches learned
-- ranks in _rankCDIDs). nil for non-execute spells, which makes the engine skip the branch.
function A.ExecuteThreshold(spellID, rankIDs)
  if spellID and A.EXECUTE[spellID] then return A.EXECUTE[spellID] end
  if rankIDs then
    for _, id in ipairs(rankIDs) do
      if A.EXECUTE[id] then return A.EXECUTE[id] end
    end
  end
  return nil
end

-- True if the spell, at any rank, is a curated reactive ability.
function A.IsReactive(spellID, rankIDs)
  if spellID and A.REACTIVE[spellID] then return true end
  if rankIDs then
    for _, id in ipairs(rankIDs) do
      if A.REACTIVE[id] then return true end
    end
  end
  return false
end
