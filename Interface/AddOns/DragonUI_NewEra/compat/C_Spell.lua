-- DragonUI_NewEra/compat/C_Spell.lua
-- Fills the ONE C_Spell.* symbol !!!ClassicAPI does NOT define: GetSpellPowerCost.
--
-- DOWNPORT: Classic 1.15 namespaced spell queries under C_Spell. !!!ClassicAPI is a
-- HARD dependency and loads first, providing the bulk of C_Spell (GetSpellInfo /
-- GetSpellName / GetSpellSubtext / GetSpellTexture / GetSpellCooldown /
-- GetSpellDescription / GetSpellLink / ...). 3.3.5a has NO concept of a per-spell
-- power-cost table and ClassicAPI does not emulate one, so we provide that stub.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local compat = NE.compat

C_Spell = C_Spell or {}
local C = C_Spell

-- GetSpellPowerCost(spellID) -> array of { type=, cost=, name=, ... }
-- 3.3.5 has NO per-spell power-cost API and ClassicAPI does not emulate one. NewEra
-- reads costInfo.type / costInfo.cost and matches against a power-bar's powerType. We
-- cannot answer accurately, so return an empty list (the source already does `... or {}`
-- and the pairs() loop no-ops). Recorded as a stub.
if not C.GetSpellPowerCost then
    function C.GetSpellPowerCost(spellID)
        return {}
    end
    compat.RecordStub("C_Spell.GetSpellPowerCost",
        "3.3.5 has no per-spell power-cost API; returns empty list (cost overlay shows nothing)")
end

NE.compat.spell = true
