-- DragonUI_NewEra/modules/guild/Open.lua — route the game's "open guild" entry points to
-- NE_GuildFrame and suppress the native GuildFrame.
--
-- DOWNPORT of NewEra/Guild/Open.lua. On 3.3.5a the canonical entry point is the global
-- ToggleGuildFrame() (used by the guild keybind and the FriendsFrame Guild tab). We wrap it to
-- toggle our modern window whenever the module is enabled — including when the player is guildless
-- (the window degrades to an empty "Guild" state, owner steer: it should still be openable without a
-- guild). Belt-and-suspenders: hook the native GuildFrame's OnShow to hide it and open ours, in case
-- something shows it directly.

local NE = DragonUI_NewEra
if not NE then return end

NE.guild = NE.guild or {}
local G = NE.guild

-- Binding labels for the Key Bindings UI. Bindings.xml (addon root) declares the actions; the
-- settings UI reads these globals for the header + row labels. "never overwrite an existing
-- global" precedent, same as the reference's Core/Boot/Core.lua.
BINDING_HEADER_DRAGONUI_NEWERA = BINDING_HEADER_DRAGONUI_NEWERA or "DragonUI New Era"
BINDING_NAME_NEWERA_TOGGLEGUILD = BINDING_NAME_NEWERA_TOGGLEGUILD or "Toggle Guild Window"
BINDING_NAME_NEWERA_TOGGLESOCIAL = BINDING_NAME_NEWERA_TOGGLESOCIAL or "Toggle Social Window"

-- Same as Window.lua's isModuleEnabled: gated entirely by the options panel's single "Social"
-- checkbox — Guild has no enable flag of its own (see Window.lua's comment for why a
-- modules["Guild"] fallback must NOT be reintroduced here).
local function isModuleEnabled()
  return not (NE.modules and NE.modules.IsEnabled) or NE.modules.IsEnabled("Social")
end
G.IsEnabled = isModuleEnabled

local wired = false
local function wireRedirects()
  if wired then return end
  wired = true

  -- (1) Wrap ToggleGuildFrame — the shared "open guild" verb. Opens our modern window whenever the
  -- module is on, regardless of guild membership (guildless just shows an empty Guild window).
  if type(_G.ToggleGuildFrame) == "function" then
    local orig = _G.ToggleGuildFrame
    _G.ToggleGuildFrame = function(...)
      if isModuleEnabled() then
        if G.Toggle then G.Toggle() end
        return
      end
      return orig(...)
    end
  end

  -- (2) Suppress the native GuildFrame: if anything shows it while our module is on, hide it and open
  -- ours instead (guildless included). Guard for load order (GuildFrame is LoD in some builds).
  local function hookNative()
    local gf = _G.GuildFrame
    if not gf or gf._neRedirectHooked then return end
    gf._neRedirectHooked = true
    gf:HookScript("OnShow", function(self)
      if isModuleEnabled() then
        self:Hide()
        if G.Show then G.Show() end
      end
    end)
  end
  hookNative()
  if type(_G.GuildFrame_LoadUI) == "function" then
    hooksecurefunc("GuildFrame_LoadUI", hookNative)
  end
end

-- Default keybind: 'J' opens the guild window (owner steer 2026-07-15). The 3.3.5a Bindings.xml
-- schema has no `default` attribute, so the default has to be applied once via SetBinding.
-- Applied ONCE (latched in the DB) and only if 'J' is actually free — we never steal a key the
-- player has already bound, and once the latch is set we never fight a later manual rebind.
local DEFAULT_GUILD_KEY = "J"

local function applyDefaultBinding()
  local db = NE.db
  if not db or db.guildKeybindApplied then return end
  if InCombatLockdown and InCombatLockdown() then return end   -- SetBinding is blocked in combat; retry next login
  if not (SetBinding and SaveBindings and GetBindingKey and GetBindingAction) then return end
  db.guildKeybindApplied = true

  if GetBindingKey("NEWERA_TOGGLEGUILD") then return end        -- already bound somewhere
  local existing = GetBindingAction(DEFAULT_GUILD_KEY)
  if existing and existing ~= "" then return end                -- 'J' is taken — leave it alone

  if SetBinding(DEFAULT_GUILD_KEY, "NEWERA_TOGGLEGUILD") then
    local set = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    pcall(SaveBindings, set)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  wireRedirects()
  applyDefaultBinding()
end)
