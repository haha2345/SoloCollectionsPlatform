-- DragonUI_NewEra/modules/lfg/Open.lua — route the game's "open LFD / open LFR" entry points to
-- NE_GroupFinderFrame and suppress the native windows. Same recipe as modules/guild/Open.lua.
--
-- Entry points on 3.3.5a:
--   * ToggleLFDParentFrame() — the 'I' keybind (TOGGLELFGPARENT), the micro menu LFG button and
--     the minimap eye all resolve this global at call time, so wrapping it captures them all.
--   * ToggleLFRParentFrame() — the Raid Browser (Social window's Raid tab button, minimap eye's
--     "listed" mode; our own modules/social/Raid.lua Browser button calls it too).
--   * ShowUIPanel(LFDParentFrame) — LFG_OPEN_FROM_GOSSIP (Icecrown NPC gossip) shows the native
--     frame directly; the OnShow hook below catches that path. The native handler has already
--     run LFDQueueFrame_SetType(dungeonID) by then, so our pane opens on the offered dungeon.
--
-- LEVEL GATE: none of these paths check the Dungeon Finder unlock level — only the micro button
-- greys itself out, and the keybind/eye/gossip routes sail straight past it. The check therefore
-- lives inside L.Show/L.Toggle (Window.lua's DUNGEONS_MIN_LEVEL), so redirecting here is safe: a
-- locked request is refused there and the native frame stays suppressed either way.

local NE = DragonUI_NewEra
if not NE then return end

NE.lfg = NE.lfg or {}
local L = NE.lfg

local function enabled()
  return not L.IsEnabled or L.IsEnabled()
end

local wired = false
local function wireRedirects()
  if wired then return end
  wired = true

  if type(_G.ToggleLFDParentFrame) == "function" then
    local orig = _G.ToggleLFDParentFrame
    _G.ToggleLFDParentFrame = function(...)
      if enabled() and L.Toggle then
        L.Toggle("DUNGEONS")
        return
      end
      return orig(...)
    end
  end

  if type(_G.ToggleLFRParentFrame) == "function" then
    local orig = _G.ToggleLFRParentFrame
    _G.ToggleLFRParentFrame = function(...)
      if enabled() and L.Toggle then
        L.Toggle("RAIDS")
        return
      end
      return orig(...)
    end
  end

  -- Belt-and-suspenders: anything that shows a native frame directly (gossip open, other
  -- addons) gets swallowed and rerouted. HideUIPanel keeps the UIPanel bookkeeping clean —
  -- both natives are managed UIPanels.
  if _G.LFDParentFrame then
    _G.LFDParentFrame:HookScript("OnShow", function(self)
      if enabled() then
        HideUIPanel(self)
        if L.Show then L.Show("DUNGEONS") end
      end
    end)
  end
  if _G.LFRParentFrame then
    _G.LFRParentFrame:HookScript("OnShow", function(self)
      if enabled() then
        HideUIPanel(self)
        if L.Show then L.Show("RAIDS") end
      end
    end)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  wireRedirects()
end)
