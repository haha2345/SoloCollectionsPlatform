-- DragonUI_NewEra/compat/Compat.lua
-- Modern-API shim LOADER. Loads first in the compat/ block (after bootstrap).
--
-- Purpose: confirm !!!ClassicAPI is present, expose NE.compat capability booleans,
-- and own the stub registry (NE.compat.RecordStub / NE.compat.stubs) that the
-- per-symbol shims reuse to record symbols 3.3.5a genuinely can't answer. This file
-- does NOT define C_* globals itself — each sibling file (C_Item.lua, C_Spell.lua,
-- ...) ensures its own symbols, only when missing, in TOC order.
--
-- DOWNPORT: !!!ClassicAPI is now a HARD dependency (## Dependencies) and loads first
-- (its `!!!` prefix + the dependency ordering), so it owns the modern C_* namespaces
-- (C_Timer/C_Texture/C_Container/C_Item/C_Spell/C_SpellBook/C_Map/Mixin/...). The
-- sibling files only fill the handful of symbols ClassicAPI does NOT provide.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

-- ---------------------------------------------------------------------------
-- ClassicAPI detection. bootstrap.lua already set NE.hasClassicAPI from the
-- "!!!ClassicAPI" load name; re-evaluate here in case load order surprised us.
-- (It is a hard dependency, so this should always be true.)
-- ---------------------------------------------------------------------------
local hasClassicAPI = _G["!!!ClassicAPI"] ~= nil
NE.hasClassicAPI = hasClassicAPI

-- ---------------------------------------------------------------------------
-- compat namespace + capability table. Each shim flips its bool true once it has
-- guaranteed its symbols. Consumers may read NE.compat.<cap> to branch, but the
-- v1 contract is simply: after compat/ loads, the modern globals exist.
-- ---------------------------------------------------------------------------
NE.compat = NE.compat or {}
local compat = NE.compat
compat.classicAPI = hasClassicAPI

-- Capability booleans (set by sibling files; default false here so reads are safe
-- even if a file failed to load). C_Timer/C_Texture are now owned entirely by
-- ClassicAPI, so they have no compat/ sibling and no bool.
compat.mixin     = compat.mixin     or false   -- Mixin/CreateFromMixins/CreateAndInitFromMixin
compat.container = compat.container or false   -- C_Container.* gap-fills
compat.item      = compat.item      or false   -- C_Item.* gap-fills
compat.spell     = compat.spell     or false   -- C_Spell.* gap-fills
compat.map       = compat.map       or false   -- C_Map.* (best-effort; stubs)

-- Record of symbols we could only STUB (3.3.5 genuinely can't answer, and ClassicAPI
-- doesn't emulate). Sibling files append { sym=, why= }; COVERAGE.md documents these.
-- Lets QA enumerate at runtime.
compat.stubs = compat.stubs or {}
function compat.RecordStub(sym, why)
    compat.stubs[#compat.stubs + 1] = { sym = sym, why = why }
end

-- print nothing on success (per contract).
