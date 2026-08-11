-- DragonUI_NewEra/modules/cooldownviewer/Register.lua — DragonUI wiring for the Cooldown Manager.
--
-- Replaces NewEra/CooldownViewer/EditModeRegister.lua, which is written against `NE.editmode` — a
-- 6,441-line reimplementation of retail Edit Mode this addon does not have and will not port (see
-- PORT_PLAN.md §B1). The two things that file delivered are re-homed:
--
--   position  -> DragonUI's MoversSystem, reached through NE.RegisterPanel (CONTRACTS §4: panel
--                modules never touch DragonUI internals directly)
--   settings  -> the /cdm window's own Settings tab (SettingsOptions.lua). They spent Phases 1-4b in
--                the New Era options tab, for want of anywhere better; §G.10/§G.12 moved them, which
--                is both where retail keeps them and one editor per stored value instead of two.
--                What NE.RegisterOptionSection still registers is the master enable toggle and a
--                button that opens the window.
--
-- Dropped with Edit Mode, deliberately: bottom-managed stacking (EM.RegisterBottomManaged — the
-- viewers would rise above the action-bar tower as bars are added; DragonUI has no equivalent, so
-- the viewers simply stay where the user puts them), and the retail settings-int codec.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

-- All four retail viewers. essential/utility read spell cooldowns from the curated class lists;
-- buffIcon/buffBar read live auras (Phase 3) and need no class data.
local VIEWERS = {
  { category = "essential", id = "CooldownViewerEssential", label = "Essential Cooldowns",
    desc = "Offensive burst and damage cooldowns.", order = 40 },
  { category = "utility",   id = "CooldownViewerUtility",   label = "Utility Cooldowns",
    desc = "Defensives, interrupts, CC and escapes.", order = 41 },
  { category = "buffIcon",  id = "CooldownViewerBuffIcon",  label = "Buff Icons",
    desc = "Short-duration buffs and procs, as icons.", order = 42, aura = true },
  { category = "buffBar",   id = "CooldownViewerBuffBar",   label = "Buff Bars",
    desc = "Short-duration buffs and procs, as depleting bars.", order = 43,
    aura = true, bar = true },
}
M.VIEWER_SPECS = VIEWERS

-- ── Frames + edit mode ──────────────────────────────────────────────────────────────────────────
--
-- TIMING: registration runs at PLAYER_LOGIN, not at file load. Every other NewEra module does the
-- same (see modules/guild/Window.lua, modules/auctionhouse/Window.lua) because DragonUI's AceDB
-- profile — which the position round-trip reads and writes — is not guaranteed ready while our
-- files are still executing.
--
-- SEAM: NE.RegisterHUDFrame, not NE.RegisterPanel. RegisterPanel wires a MoversSystem mover, and
-- `/dui edit` does not drive MoversSystem at all — it drives addon.EditableFrames. See the comment
-- block on NE.RegisterHUDFrame in integration/Register.lua for the full detail. Registering a HUD
-- frame with RegisterPanel produces a handle that is silently never shown.

local booted = false

local function boot()
  if booted then return end
  booted = true

  -- Before anything reads a spell list: clear custom lists that were auto-seeded by the old
  -- GetItemMeta side effect. They shadow the curated tables and would hide the whole WotLK seed on
  -- any character that had run an earlier build. Versioned, so it runs once.
  if M.MigrateStaleCustomLists then M.MigrateStaleCustomLists() end

  for _, spec in ipairs(VIEWERS) do
    local frame = spec.aura and M.CreateBuffViewer(spec.category) or M.CreateViewer(spec.category)
    if not frame then
      if NE.Log then NE.Log("CDM", "viewer '" .. spec.category .. "' failed to build") end
    else

      NE.RegisterHUDFrame({
        name    = spec.id,
        label   = spec.label,   -- shown on the editor handle; also silences AceLocale's missing-key warning
        frame   = frame,
        section = "widgets",
        key     = "ne" .. spec.id,
        -- PER CHARACTER. DragonUI's profile is shared across the account, so without this all four
        -- viewers sit wherever the last character to touch them left them. Where these belong is
        -- downstream of WHAT they show, and that is per class already — a Warlock's buff bars have
        -- no reason to inherit a Priest's placement. Existing shared positions are seeded into each
        -- character's slot on first login, so nothing moves on upgrade.
        perCharacter = true,
        -- No handles while the module is off. RegisterHUDFrame defaults this to "always offer it",
        -- which is right for a HUD frame that is merely EMPTY right now — that is what showTest is
        -- for. It is wrong for one the player has not turned on: the Cooldown Manager ships disabled
        -- (see M.IsEnabled), so out of the box `/dui edit` would open onto four green rectangles for
        -- a feature that has never been on screen, and showTest would fill them with demo icons.
        -- DragonUI honours a false here by hiding the anchor and skipping showTest entirely
        -- (core/api.lua:1239).
        editorVisible = function() return M.IsEnabled() end,
        -- Retail keeps a system's settings ON the frame in Edit Mode, not in a separate options
        -- window. EditorPanel.lua builds that dialog; integration/Register.lua owns when it opens.
        editorSettings = function(editorAnchor)
          if M.ShowEditorPanel then M.ShowEditorPanel(spec.category, editorAnchor) end
        end,
        -- Leaving edit mode takes the dialog with it. HideAllEditableFrames calls this for every
        -- registered frame, so it fires whichever viewer was selected — and it is idempotent.
        onHide = function()
          if M.HideEditorPanel then M.HideEditorPanel() end
        end,
        defaultPoint = {
          point = "BOTTOM", relativePoint = "BOTTOM",
          -- BuffBar sits off to the side in retail's preset; the rest are centred.
          x = (spec.category == "buffBar") and 420 or 0,
          y = M.VIEWER_DEFAULT_Y[spec.category] or 300,
        },
        -- Demo content while the editor is open. Essential/Utility would otherwise be empty for a
        -- character who hasn't learned those spells (or any Death Knight, pending Phase 2), and the
        -- aura viewers are empty by nature whenever no short buff happens to be up.
        showTest = function()
          frame._editPreview = true
          frame:Show()
          frame:Rebuild()
        end,
        hideTest = function()
          frame._editPreview = false
          frame:Rebuild()
          frame:UpdateVisibility()
        end,
      })

      frame:RefreshLayout()
      frame:UpdateVisibility()
    end
  end

  -- The learn-gate reads the spellbook table (core/SpellRanks.lua). Re-source every viewer once
  -- that table has been rebuilt — training a rank, switching spec or respeccing all change what
  -- the player knows, and the viewers must follow.
  if NE.spellbook and NE.spellbook.OnRebuilt then
    NE.spellbook.OnRebuilt(function()
      M.InvalidateCuratedCache()
      -- The talent gate too: a spec swap changes which catalog rows are offered, and this is the
      -- point at which the client has finished telling us what changed.
      if M.InvalidateTalentCache then M.InvalidateTalentCache() end

      -- Seed a per-spec starter into a layout bucket that has never had one. Hung HERE rather than on
      -- PLAYER_LOGIN because this fires once the client has finished answering about talents — at
      -- login AND after a spec swap — and GetTalentTabInfo is what the detection reads. It is
      -- idempotent: the bucket is marked the moment it is seeded, so every later call is a no-op, and
      -- a character with no talent points is simply skipped until they spend one.
      local P = NE.cooldownviewersettings and NE.cooldownviewersettings.presets
      if P and P.SeedStarterIfFresh then pcall(P.SeedStarterIfFresh) end

      M.RefreshActiveViewer()
    end)
  end

  -- Alert/ready-sound poll. Started unconditionally: it early-outs on its own gate every tick when
  -- nothing is assigned, which is cheaper than watching the store for the first assignment.
  if M.alerts and M.alerts.Start then M.alerts.Start() end
end

-- ── Diagnostic ──────────────────────────────────────────────────────────────────────────────────
-- /necdm — report, per curated spell for the player's class, exactly what the learn-gate decided
-- and why. Added after a report that talent-granted abilities (Penance on Disc, Guardian Spirit on
-- Holy) and level-squished abilities (Divine Hymn at 60) were being filtered out: guessing at which
-- of the three checks failed is far slower than printing all three.
SLASH_NECDM1 = "/necdm"
SlashCmdList["NECDM"] = function()
  local _, class = UnitClass("player")
  local SB = NE.spellbook
  local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1CDM|r " .. msg) end

  say(("class=%s  spellbook built=%s  names=%d"):format(
    tostring(class),
    tostring(SB and SB.built),
    (function() local n = 0; for _ in pairs(SB and SB.KNOWN_NAMES or {}) do n = n + 1 end; return n end)()))

  for _, category in ipairs({ "essential", "utility" }) do
    local source = M.SPELL_DATA_BY_CATEGORY and M.SPELL_DATA_BY_CATEGORY[category]
    local list = source and source[class] or {}
    local shown = M.GetActiveSpellList(category)
    local inShown = {}
    for _, id in ipairs(shown) do inShown[id] = true end

    -- Report whether a CUSTOM list is overriding the curated table. Its absence from the first
    -- version of this command is why a spell could report book=true on every check and still be
    -- hidden: the gate was fine, the list it was gating had been replaced.
    local custom = M.GetCustomList(category, class)
    say(("|cffffcc55%s|r — %d curated, %d shown%s"):format(
      category, #list, #shown,
      custom and ("  |cffff5555[custom list active: %d entries — curated table IGNORED]|r"):format(#custom) or ""))
    for _, id in ipairs(list) do
      local name = GetSpellInfo(id)
      local book = name and SB and SB.IsSpellNameKnown and SB.IsSpellNameKnown(name)
      local known = IsSpellKnown and IsSpellKnown(id)
      local byname = name and GetSpellInfo(name) ~= nil
      if not inShown[id] then
        say(("   |cffff5555hidden|r %-24s id=%-6d book=%-5s IsSpellKnown=%-5s byName=%s"):format(
          tostring(name or "?"), id, tostring(book), tostring(known), tostring(byname)))
      end
    end
  end

  -- Alerts and sounds, keyed by the LISTED spell id (never the learned-rank one — see
  -- ItemMixin:GetSettingsKey). Printing the key is the point: a mismatch here is what an orphaned
  -- assignment looks like.
  local cd = M._store and M._store(false)
  local alerts, sounds = (cd and cd.alerts) or {}, (cd and cd.sounds) or {}
  local n = 0
  for id, cfg in pairs(alerts) do
    if cfg and cfg.type then
      n = n + 1
      say(("   |cff55ff55alert|r  %-24s key=%-6d type=%-9s fx=%s window=%d%%"):format(
        tostring(GetSpellInfo(id) or "?"), id, cfg.type, tostring(cfg.fx), (cfg.window or 0.3) * 100))
    end
  end
  for id, kit in pairs(sounds) do
    if kit then
      n = n + 1
      say(("   |cff55ff55sound|r  %-24s key=%-6d kit=%-7d %s"):format(
        tostring(GetSpellInfo(id) or "?"), id, kit, tostring(M.GetSoundKitName(kit))))
    end
  end
  if n == 0 then say("   no alerts or ready sounds assigned (right-click an icon to add one)") end

  -- §F1: which Cooldown widget methods this client actually has. The plan has carried "confirm
  -- SetDrawEdge" as an open question since Phase 0, and the static evidence says it is native —
  -- ClassicAPI stubs SetEdgeTexture / SetEdgeColor / SetEdgeScale as "Incompatible (3.3.5)" but does
  -- NOT stub SetDrawEdge, and its own cooldown-capture path calls Self:GetDrawEdge() unguarded
  -- (Util/Cooldown.lua:204), which would error on every captured cooldown if it were missing. That is
  -- an inference from someone else's code, so this prints the answer instead of arguing it. One
  -- throwaway frame, created on demand: frames cannot be destroyed, so it is not created at load.
  local probe = M._widgetProbe
  if not probe then
    probe = CreateFrame("Cooldown", nil, UIParent)
    probe:Hide()
    M._widgetProbe = probe
  end
  local function has(name) return probe[name] ~= nil and "yes" or "NO" end
  say(("cooldown widget: SetDrawEdge=%s GetDrawEdge=%s SetSwipeTexture=%s SetReverse=%s"):format(
    has("SetDrawEdge"), has("GetDrawEdge"), has("SetSwipeTexture"), has("SetReverse")))

  -- Phase 8a. Six atlases were being set by name with nothing registered, which renders as an
  -- invisible texture and logs nothing — so the state is worth being able to READ rather than infer
  -- from how the bars look. The ready flash in particular has two very different code paths, and
  -- "is it the sprite or the fallback?" is otherwise a guess.
  if NE.tex and NE.tex.HasAtlas then
    local names = {
      "UI-HUD-CoolDownManager-IconOverlay", "UI-CooldownManager-OORshadow",
      "UI-HUD-ActionBar-GCD-Flipbook", "UI-HUD-CoolDownManager-Bar",
      "UI-HUD-CoolDownManager-Bar-BG", "UI-HUD-CoolDownManager-Bar-Pip",
    }
    local missing = {}
    for _, n in ipairs(names) do
      if not NE.tex.HasAtlas(n) then missing[#missing + 1] = n end
    end
    if #missing == 0 then
      say(("viewer art: all %d atlases registered"):format(#names))
    else
      say(("viewer art: MISSING %d of %d -- %s"):format(#missing, #names,
        table.concat(missing, ", ")))
    end
    local flip = NE.tex.HasAtlas("UI-HUD-ActionBar-GCD-Flipbook")
    say(("ready flash: %s"):format(flip and "retail flipbook sprite (22 frames)"
      or "fallback highlight burst (flipbook atlas not registered)"))
  end

  -- Phase 8c. The glow has two independent ways to be invisible — the setting is off, or no tile is
  -- currently in the aura branch at all — and neither one looks different from a broken glow. Report
  -- both, plus a live count, so "I don't see it" is answerable rather than guessable. (The first
  -- version had a third way: art that emits nothing under ADD. Hence naming the texture here.)
  local lit, withSpell = 0, 0
  for _, cat in ipairs({ "essential", "utility" }) do
    local v = M.viewers and M.viewers[cat]
    for _, it in ipairs((v and v.items) or {}) do
      if it.spellID and it:IsShown() then
        withSpell = withSpell + 1
        if it._buffGlow then lit = lit + 1 end
      end
    end
  end
  say(("buff glow: %s, texture %s, lit on %d of %d shown tiles"):format(
    M.IsBuffGlowEnabled() and "ON" or "off (Settings > Buffed spells)",
    tostring(M.BUFF_GLOW_TEXTURE), lit, withSpell))

  -- Phase 8e. The pandemic ring has the same "three ways to be invisible" problem the buff glow had:
  -- no spell carries a refresh alert, none is inside its window, or the atlas failed to register.
  -- Report which, plus whether the pulse is actually running — a built-but-never-played group is a
  -- silent failure, because the ring still shows, just static.
  local AL = M.alerts
  if AL then
    local assigned, lit, pulsing = 0, 0, 0
    for _, cat in ipairs({ "essential", "utility" }) do
      local v = M.viewers and M.viewers[cat]
      for _, it in ipairs((v and v.items) or {}) do
        local sid = it.GetSettingsKey and it:GetSettingsKey() or it.spellID
        if sid and AL.GetType(sid) == "refresh" then assigned = assigned + 1 end
        local ov = it._pandemicRing
        if ov and ov:IsShown() then
          lit = lit + 1
          if ov.anim and ov.anim.IsPlaying and ov.anim:IsPlaying() then pulsing = pulsing + 1 end
        end
      end
    end
    say(("pandemic ring: art %s, %d spell(s) set to Refresh, %d ring(s) up, %d pulsing"):format(
      (NE.tex and NE.tex.HasAtlas and NE.tex.HasAtlas("UI-CooldownManager-PandemicBorder"))
        and "registered" or "MISSING", assigned, lit, pulsing))
  end

  -- Phase 8d. The 3-slice is invisible when it works and a soft edge when it does not, which is a
  -- hard thing to eyeball at the 100% bar width. Report the stretch factor the middle is carrying:
  -- that is the number the slice exists to keep off the caps.
  local bar = M.viewers and M.viewers.buffBar and M.viewers.buffBar.items
              and M.viewers.buffBar.items[1] and M.viewers.buffBar.items[1].Bar
  local bg = bar and bar.BarBG
  if bg and bg.Left then
    local w = (bar:GetWidth() or 0) - M.BARBG_PAD_L + M.BARBG_PAD_R
    say(("bar frame: %s, region %.0fpx wide vs %dpx art (%.2fx), caps %.1f/%.1f held"):format(
      bg.Middle and bg.Middle:IsShown() and "3-slice" or "single stretch (bar too narrow)",
      w, M.BARBG_NATIVE_W, w / M.BARBG_NATIVE_W,
      bg.Left:GetWidth() or 0, bg.Right and bg.Right:GetWidth() or 0))
  end
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function()
  local ok, err = pcall(boot)
  if not ok and NE.Log then NE.Log("CDM", "boot failed: " .. tostring(err)) end
end)

-- ── Options ─────────────────────────────────────────────────────────────────────────────────────
--
-- TWO CONTROLS, deliberately. This section used to carry every viewer setting — the ten per-viewer
-- ones, the two bar-only ones, buff auto-tracking and both resets — because Phase 1 had nowhere else
-- to put them. They now live on the Cooldown Manager's own Settings tab (SettingsOptions.lua), which
-- is where retail keeps them and where a player already is when they care about them.
--
-- What stays is what only makes sense here: the master OFF switch, because DragonUI's options panel is
-- where a player goes to turn a module off, and nobody looks inside a window for the way to make that
-- window's frames stop existing — plus a button to reach the rest.
--
-- No stored VALUE is rendered in both places. A setting with two editors stays consistent only while
-- both are rebuilt on show, and the first time one is not, the player is reading a stale control and
-- cannot tell that from a setting that failed to apply. (EditorPanel.lua later added a third view of
-- the per-viewer settings — retail's on-the-frame dialog — and pays that cost explicitly: it re-reads
-- every control on open and refreshes the Settings tab on every write. See its header.)

NE.RegisterOptionSection({
  id    = "cooldownviewer",
  order = 40,
  build = function(scroll, C)
    if C.AddSpacer then C:AddSpacer(scroll) end
    C:AddHeading(scroll, "Cooldown Manager")
    C:AddDescription(scroll,
      "Retail's Cooldown Manager, driven from curated per-class cooldown lists. |cffffcc55Off by "
      .. "default|r — it adds four viewers to the middle of your screen, so it waits to be asked. Every "
      .. "setting — which spells and buffs are tracked, each viewer's layout, size and visibility, alerts "
      .. "and ready sounds — lives in the Cooldown Manager window itself (/cdm). Drag the viewers with "
      .. "DragonUI's editor mode to reposition them, and right-click one there for its own layout settings.")

    C:AddToggle(scroll, {
      label   = "Enable Cooldown Manager",
      desc    = "Off by default. Turn on to show the four viewers; turn off to hide them again. Takes "
                .. "effect immediately either way, and nothing is forgotten — this switch stores one flag "
                .. "and touches nothing else, so your setup comes back exactly as you left it.",
      getFunc = function() return M.IsEnabled() end,
      setFunc = function(v) M.SetEnabled(v) end,
    })

    if C.AddButton then
      C:AddButton(scroll, {
        label    = "Open Cooldown Manager",
        -- SPELLS, not Settings (owner's steer). This is the front door: the first thing anyone wants
        -- after turning the module on is to see and change what it tracks, which is the Spells tab.
        -- Settings is where you go once you already know what is in the viewers, and the tabs are right
        -- there. (The link on the edit-mode dialog still opens on Settings — that one exists to reach
        -- the non-per-viewer settings by name, so it means it.)
        desc     = "Opens the Cooldown Manager window (/cdm) on its Spells tab. Needs the module on — "
                   .. "the window configures the viewers, so it goes away with them.",
        callback = function()
          if M.OpenSettingsPanel then M.OpenSettingsPanel("spells") end
        end,
      })
    else
      -- An older DragonUI_Options with no AddButton. Name the command rather than leaving this section
      -- as an off switch and no way through.
      C:AddDescription(scroll, "Type /cdm to open the Cooldown Manager window.")
    end
  end,
})
