-- DragonUI_NewEra/modules/collections/Open.lua — open path for the Collections window.
--
-- Gives NE_CollectionsFrame a keybind (NEWERA_TOGGLECOLLECTIONS, declared in the addon-root
-- Bindings.xml) and applies SHIFT-P as its default key on first run — the key that used to open the
-- old Character-panel "Collection" view, now retired in favour of this standalone window. Mirrors the
-- guild module's Open.lua (labels + latched default-binding) exactly; the frame is insecure with no
-- protected children, so the binding body is combat-safe.

local NE = DragonUI_NewEra
if not NE then return end
NE.collections = NE.collections or {}
local C = NE.collections

-- Binding labels for the Key Bindings UI. Bindings.xml declares the action; the settings UI reads
-- these globals for the header + row label. Never overwrite an existing global.
BINDING_HEADER_DRAGONUI_NEWERA = BINDING_HEADER_DRAGONUI_NEWERA or "DragonUI New Era"
BINDING_NAME_NEWERA_TOGGLECOLLECTIONS = BINDING_NAME_NEWERA_TOGGLECOLLECTIONS or "Toggle Collections (Mounts & Pets)"

-- Default keybind: SHIFT-P opens the Collections window. The 3.3.5a Bindings.xml schema has no
-- `default` attribute, so the default is applied once via SetBinding, latched in the DB so we never
-- fight a later manual rebind. The player explicitly asked for SHIFT-P (it opened the old companion
-- view), so we DO take the key over on first run even if it currently maps elsewhere — but only
-- SHIFT-P, only once, and only if our action isn't already bound to some other key.
local DEFAULT_KEY = "SHIFT-P"

local function applyDefaultBinding()
  -- Not while the module is off (its default, since DragonUI ships its own collections UI) — taking
  -- SHIFT-P over for a window that refuses to open would just eat the key. The latch below is never
  -- set in that case, so enabling the module later still applies the default on the next login.
  if C.IsEnabled and not C.IsEnabled() then return end
  local db = NE.db
  if not db or db.collectionsKeybindApplied then return end
  if InCombatLockdown and InCombatLockdown() then return end   -- SetBinding is blocked in combat; retry next login
  if not (SetBinding and SaveBindings and GetBindingKey) then return end
  db.collectionsKeybindApplied = true

  if GetBindingKey("NEWERA_TOGGLECOLLECTIONS") then return end   -- already bound somewhere — respect it
  if SetBinding(DEFAULT_KEY, "NEWERA_TOGGLECOLLECTIONS") then
    local set = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    pcall(SaveBindings, set)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  applyDefaultBinding()
end)
