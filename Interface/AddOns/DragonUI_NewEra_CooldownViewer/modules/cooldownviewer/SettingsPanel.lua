-- DragonUI_NewEra/modules/cooldownviewer/SettingsPanel.lua — the /cdm settings window.
--
-- Phase 4b-1: the SHELL only. Chrome, the Spells/Auras side tabs, the scroll body, the search box,
-- and the open/close plumbing. The category grids (4b-2) and the item context menu that actually
-- assigns things (4b-3) build on top; `CDS.RefreshLayout` is the stub they replace.
--
-- Downport of NewEra/CooldownViewerSettings/Panel.lua (612 lines). See PORT_PLAN §G for the full
-- scope. What changed and why:
--
--   * THREE side tabs, but not upstream's three. Upstream's Group Buffs tab hosts NE.groupbuff.filter,
--     a module this addon does not have (12 references); it is dropped whole, along with
--     CDS.UpdateGroupBuffsTabState. In its place is a SETTINGS tab (PORT_PLAN §G.10, §G.12) holding
--     every viewer setting, which retail keeps in its Edit Mode dialog and we used to keep in
--     DragonUI's options panel.
--
--   * NO strata-raising hack. Upstream fights a real problem — Era opens context menus at
--     FULLSCREEN_DIALOG, the same strata as its panel, so menus rendered BEHIND it and had to be
--     raised to TOOLTIP inside securecallfunction. 3.3.5a's UIDropDownMenu opens its list frames at
--     DIALOG and we sit at MEDIUM, so menus clear us naturally. The whole raiseMenuAbovePanel /
--     securecallfunction contract is unnecessary here and is not ported.
--
--   * NO WowStyle1DropdownTemplate. That template is retail-only. The footer layout dropdown is
--     Phase 4b-5, and the Auras tab's auto-track dropdown already has a working equivalent in the
--     options tab, so neither is rebuilt here.
--
--   * The settings cog landed in 4b-3, once core/Menu.lua existed to give it a menu; Revert became
--     real in 4b-5, when SettingsPresets.lua brought the snapshot/restore pair it needs.
--
-- Taint: a plain display window. No secure templates, no protected frames, SavedVariables reads
-- only. Nothing here can taint the combat path.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

NE.cooldownviewersettings = NE.cooldownviewersettings or {}
local CDS = NE.cooldownviewersettings

local PANEL_NAME = "NE_CooldownViewerSettings"
local PANEL_W, PANEL_H = 399, 609
local PANEL_SCALE = 1.3

-- Height of the button strip below the Inset, measured from the frame's bottom edge.
-- ButtonFrameTemplate anchors its Inset at BOTTOMRIGHT y=26; this is that +10, on the owner's
-- request, because the layout and Revert buttons sat tight against the Inset's bottom border.
-- Both the Inset and the scroll body key off this, so the strip has ONE height rather than two
-- numbers that have to be remembered together.
local FOOTER_H = 36
local SCROLL_BOTTOM_PAD = 8   -- the scroll body's own clearance inside the Inset

-- Which side tab a viewer category belongs to. Essential/Utility are spellbook-driven; the buff
-- viewers are aura-driven. Nothing maps to "settings" — that tab is not a list of anything.
local CATEGORY_TO_MODE = {
  essential = "spells",
  utility   = "spells",
  buffIcon  = "auras",
  buffBar   = "auras",
}

local panel        -- lazily built on first open
local currentMode  -- "spells" | "auras" | "settings"

-- ── Build ───────────────────────────────────────────────────────────────────────────────────────

local function build()
  if panel then return panel end

  local f = CreateFrame("Frame", PANEL_NAME, UIParent, "ButtonFrameTemplate")
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  f:SetSize(PANEL_W, PANEL_H)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)

  -- MEDIUM, matching our other standalone windows. Upstream needs DIALOG + SetToplevel to clear a
  -- retail Edit Mode overlay that does not exist here; sitting lower keeps dropdown lists (DIALOG
  -- on this client) above us without any per-menu strata juggling.
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop",  f.StopMovingOrSizing)
  f:Hide()

  -- Re-pull icons when the client reports them changed, and when an item's data finally arrives —
  -- an equip row's icon is nil until the server delivers it.
  f:RegisterEvent("SPELL_UPDATE_ICON")
  f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  -- A trinket swap changes the discovery set, so the Trinkets section has to re-source. Registered
  -- unfiltered: RegisterUnitEvent is our own compat shim and this frame has no other unit events.
  f:RegisterEvent("UNIT_INVENTORY_CHANGED")
  -- Phase 7d: the aura catalog is spec-gated, so a respec or a dual-spec swap changes which rows
  -- exist. The gate's cache expires on a short TTL and would recover on its own, but only at the
  -- next refresh — which for an open window could be never.
  f:RegisterEvent("CHARACTER_POINTS_CHANGED")
  f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  f:SetScript("OnEvent", function(self, event)
    if event == "CHARACTER_POINTS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
      if M.InvalidateTalentCache then M.InvalidateTalentCache() end
      -- The learn gate reads the curated set, and which of those spells the player KNOWS has just
      -- changed with the spec.
      if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
    end
    if self:IsShown() then CDS.RefreshLayout() end
  end)

  -- …and again once the spellbook table has actually caught up. Refreshing on the talent event alone
  -- is too early: core/SpellRanks.lua rebuilds on a deferred timer, so this window re-rendered from
  -- the OLD book and then had no reason to look again. That is the reported "switched from Holy to
  -- Disc and can still see Circle of Healing — it only disappears when I try to move it": moving a
  -- tile refreshes the layout, by which time the table is right. The viewers already subscribe here
  -- (Register.lua); the panel never did.
  if NE.spellbook and NE.spellbook.OnRebuilt then
    NE.spellbook.OnRebuilt(function()
      -- Redundant today — Register.lua's subscription runs first and already clears this — and kept
      -- anyway, because "first" is only true while these two register in their current order. A
      -- refresh that reads a stale cache is the failure mode this whole callback exists to fix.
      if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
      if f:IsShown() then CDS.RefreshLayout() end
    end)
  end

  -- On OnHide, not in HidePanel: the close button and ESC both call Hide() directly. A drag in
  -- flight owns a cursor icon parented to UIParent and a dimmed, locked source tile, and closing
  -- the window out from under it would strand both.
  f:HookScript("OnHide", function()
    if CDS.CancelDrag then CDS.CancelDrag() end
    -- The undo is a SESSION step, and its scope is one visit to this window. Keeping it across a
    -- close would offer to revert a layout change the player made and then spent an hour building on.
    if CDS.ClearUndo then CDS.ClearUndo() end
  end)

  -- Shared modern chrome: hides the classic ButtonFrameTemplate border, applies our nineslice,
  -- retextures the streaks and sets the title styling. Same path modules/collections/Window.lua uses.
  local PC = NE.panelchrome
  if PC and PC.Apply then
    PC.Apply(f, { layout = "PortraitFrameTemplate", title = "Cooldown Manager", noPortrait = true })
  end

  -- THE BODY: plain, full-brightness UI-Background-Rock — the same stone every other from-scratch
  -- standalone window in this addon shows (Guild, LFG, Professions, AuctionHouse, Social,
  -- Collections, Encounter Journal).
  --
  -- PC.ApplyModernChrome tints its own f.Bg to 0.32 grey. That tint is a DOWNPORT fix for a
  -- different frame's first-paint colour flash, and on a window this size it reads as a dark wash
  -- rather than stone. Collections strips it for exactly this reason (modules/collections/Window.lua
  -- "bgTint"); this window is the last one that still wore it.
  if f.Bg and f.Bg.SetVertexColor then f.Bg:SetVertexColor(1, 1, 1) end

  -- The INSET is the recessed content area, and it reads near-black over the body stone — the same
  -- fill and the same colour as every other inset in this addon (Collections' buildInset, LFG's
  -- category rail).
  --
  -- THE SUBLEVEL IS THE POINT. This window's previous Inset fill was created at BACKGROUND subLevel
  -- -5 while PanelChrome's f.Bg sits at subLevel 0 and spans the entire frame, so it drew UNDERNEATH
  -- the body stone and was never once visible — the window looked like whatever f.Bg was tinted to,
  -- and the fill might as well not have existed. It has to sit ABOVE f.Bg.
  --
  -- (ClassicAPI's PortraitFrameTemplate declares its own $parentBg with NO parentKey, so PanelChrome
  -- builds f.Bg fresh at the default subLevel instead of re-texturing the template's at -6. That is
  -- what put the two on the wrong sides of each other.)
  if f.Inset then
    -- Lift the Inset's bottom edge to make the button strip FOOTER_H tall. Only the BOTTOMRIGHT
    -- point is re-set: SetPoint replaces an existing anchor of the same name, so the template's
    -- TOPLEFT stays exactly where it was and this cannot drift from it.
    f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, FOOTER_H)
    if f.Inset.Bg then f.Inset.Bg:Hide() end   -- the template's own old-ClassicAPI marble
    local ibg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    ibg:SetPoint("TOPLEFT",     f.Inset, "TOPLEFT",     0, 0)
    ibg:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", 0, 0)
    ibg:SetTexture(0.05, 0.05, 0.06, 0.92)
    f.InsetBg = ibg
    -- Guards it against HideClassicChrome's BACKGROUND walk, which hides everything but f.Bg. Chrome
    -- is applied above this today; the Keep is what makes re-applying it survivable.
    if PC and PC.Keep then PC.Keep(f, ibg) end
  end
  if PC and PC.ModernizeCloseButton then PC.ModernizeCloseButton(f.CloseButton) end

  -- Portrait: retail shows the spec icon. No specs on 3.3.5a, so use the class icon — the same
  -- fallback the character panel's spec portrait uses, and a solid circle that fills the cutout.
  if f.portrait and NE.portrait and NE.portrait.ApplyCutout then
    local _, class = UnitClass("player")
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    f.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    if coords then f.portrait:SetTexCoord(unpack(coords)) end
    NE.portrait.ApplyCutout(f.portrait, f)
  end

  -- 1.3 = the owner's +30%. Applied as a SCALE, not by growing PANEL_W/H: the grid geometry
  -- (38px tiles on a 46px pitch, 7 to a row, a 344-wide category) is upstream's probe-confirmed
  -- layout, and a bigger frame around unchanged tiles would just add margin.
  --
  -- That 1.3 now lives in core/Scale.lua as BASE_SCALE["cooldownmanager"], and this window is a
  -- normal entry in the options tab's Window Scaling list (mode: ui / none / custom). Its default
  -- mode is "none", which IS PinPixelPerfect(f, 1.3) — identical to the line this replaced, and
  -- still re-pinned on any UI-scale change. PANEL_SCALE stays as the no-NE.scale fallback.
  if NE.scale and NE.scale.Apply then
    if NE.scale.SetFrame then NE.scale.SetFrame("cooldownmanager", f) end
    NE.scale.Apply("cooldownmanager")
  elseif NE.FrameUtil and NE.FrameUtil.PinPixelPerfect then
    NE.FrameUtil.PinPixelPerfect(f, PANEL_SCALE)
  end

  if NE.FrameUtil then
    if NE.FrameUtil.EscClose then NE.FrameUtil.EscClose(PANEL_NAME) end
    if NE.FrameUtil.WirePanelSounds then
      -- Retail plays the class-talent open/close kits; those are retail sound IDs, so the helper's
      -- vanilla character-pane fallback is what actually sounds here.
      NE.FrameUtil.WirePanelSounds(f, nil, nil,
        SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN,
        SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end
  end

  -- Side tabs, hung off the right edge. Anchors mirror retail's QuestMapFrame: first
  -- TOPLEFT -> panel TOPRIGHT(+1,-28), next TOP -> prev BOTTOM(0,-3). Retail reuses one glyph for
  -- both active and inactive states, so only activeAtlas is passed.
  f.spellsTab = NE.tabs.MakeSideTab(f, {
    activeAtlas = "icon_cooldownmanager", tooltip = "Spells", iconSize = 32,
    onClick = function() CDS.SetDisplayMode("spells") end,
  })
  f.spellsTab.displayMode = "spells"
  f.spellsTab:SetPoint("TOPLEFT", f, "TOPRIGHT", 1, -28)

  f.aurasTab = NE.tabs.MakeSideTab(f, {
    activeAtlas = "icon_trackedbuffs", tooltip = "Tracked Buffs", iconSize = 32,
    onClick = function() CDS.SetDisplayMode("auras") end,
  })
  f.aurasTab.displayMode = "auras"
  f.aurasTab:SetPoint("TOP", f.spellsTab, "BOTTOM", 0, -3)

  -- The settings tab. Its glyph is the client's own questlog cog rather than a third CDM-sheet icon:
  -- that sheet's spare glyph is icon_buffreorder, which means "reorder group buffs" and would be a
  -- lie here. Reusing the cog also ties the tab to the cog beside the search box, which is what a
  -- player already reads as "options in this window". At 18px it is a hair over its native 15x16, so
  -- it stays crisp.
  f.settingsTab = NE.tabs.MakeSideTab(f, {
    activeAtlas = "questlog-icon-setting", tooltip = "Settings", iconSize = 18,
    onClick = function() CDS.SetDisplayMode("settings") end,
  })
  f.settingsTab.displayMode = "settings"
  f.settingsTab:SetPoint("TOP", f.aurasTab, "BOTTOM", 0, -3)

  f.tabButtons = { f.spellsTab, f.aurasTab, f.settingsTab }

  -- Search box. Filtering DIMS non-matching items in place rather than reflowing the grid, which is
  -- what retail does; Categories.lua owns the per-item overlay in 4b-2.
  f.search = CreateFrame("EditBox", PANEL_NAME .. "Search", f, "SearchBoxTemplate")
  f.search:SetSize(290, 30)
  f.search:SetPoint("TOPLEFT", 72, -30)
  f.search:SetAutoFocus(false)
  f.search:HookScript("OnTextChanged", function()
    if CDS.ApplyItemFilter then CDS.ApplyItemFilter(CDS.GetSearchText()) end
  end)

  -- Settings cog, immediately right of the search box (retail anchors its SettingsDropdown
  -- LEFT -> SearchBox.RIGHT +5). Same 16x18 native-atlas recipe as the spellbook and professions
  -- cogs; the menu itself is SettingsMenu.lua's, opened through NE.menu so it toggles closed on a
  -- second click.
  local cog = CreateFrame("Button", nil, f)
  cog:SetSize(16, 18)
  cog:SetPoint("LEFT", f.search, "RIGHT", 5, 0)
  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true)) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")
  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true)) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER")
  cog.Hi:SetBlendMode("ADD")
  cog.Hi:SetAlpha(0.4)
  cog:SetScript("OnClick", function(self)
    if CDS.ToggleSettingsMenu then CDS.ToggleSettingsMenu(self) end
  end)
  cog:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Options")
    GameTooltip:Show()
  end)
  cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.settingsCog = cog

  -- Scrollable body. A plain UIPanelScrollFrameTemplate — upstream uses the same, and there is no
  -- WowScrollBox anywhere in the source to have to replace.
  f.scroll = CreateFrame("ScrollFrame", PANEL_NAME .. "Scroll", f, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", 17, -72)
  f.scroll:SetPoint("BOTTOMRIGHT", -30, FOOTER_H + SCROLL_BOTTOM_PAD)   -- clears the footer row below
  f.content = CreateFrame("Frame", nil, f.scroll)
  f.content:SetSize(330, 1)
  f.scroll:SetScrollChild(f.content)
  -- The MODERN minimal scrollbar — the hand-built track+thumb every other list in this addon uses,
  -- not NE.scrollbar.Reskin.
  --
  -- Reskin is the in-place re-skin of the stock UIPanelScrollBar Slider, and it is the older path
  -- for a documented reason: it "was not rendering — the user still saw the default Blizzard bar"
  -- (core/ScrollbarReskin.lua's own header, and the reason BuildCustom exists at all). On this frame
  -- it could not have rendered: Reskin reaches for `scroll.ScrollBar`, and 3.3.5a's
  -- UIPanelScrollFrameTemplate declares its slider as `$parentScrollBar` with no parentKey, so that
  -- field is nil and Reskin returned at its second line without touching anything.
  --
  -- BuildCustomPixel is the variant for a real ScrollFrame — it drives SetVerticalScroll directly
  -- and sizes the thumb from visible:total, rather than BuildCustom's row-step heuristic for
  -- FauxScrollFrames. x = -6 puts the bar in the gutter this panel already reserves between the
  -- scroll body's right edge and the Inset border.
  if NE.scrollbar and NE.scrollbar.BuildCustomPixel then
    pcall(NE.scrollbar.BuildCustomPixel, f.scroll, { x = -6 })
  end

  -- A SECOND scroll child for the settings tab, swapped in by SetDisplayMode. The grids own
  -- `f.content` end to end — RefreshLayout rebuilds it from the adapter on every call — so a page of
  -- controls needs its own child rather than a corner of theirs (PORT_PLAN §G.10 option (a)). Empty
  -- until the tab is first opened; SettingsOptions.lua fills it then.
  f.settingsContent = CreateFrame("Frame", nil, f.scroll)
  f.settingsContent:SetSize(330, 1)
  f.settingsContent:Hide()

  -- Footer: the layout picker and Revert. Retail's is a WowStyle1DropdownTemplate, which does not
  -- exist here — but the widget was never the point. This is a plain button that opens the same menu
  -- tree through core/Menu.lua, with the selected layout's name as its label so the footer still
  -- answers "which layout am I on" at a glance.
  f.layoutButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.layoutButton:SetSize(180, 22)
  f.layoutButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 6)
  f.layoutButton:SetScript("OnClick", function(self)
    if CDS.ToggleLayoutMenu then CDS.ToggleLayoutMenu(self) end
  end)
  f.layoutButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Layouts")
    GameTooltip:AddLine("Save, load, import and export the whole|nCooldown Manager setup for this class.",
      1, 1, 1)
    GameTooltip:Show()
  end)
  f.layoutButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Revert was deferred in 4b-1 because it needs a snapshot/restore pair, which arrived with
  -- SettingsPresets.lua. Disabled until there is something to revert, so it never reads as broken.
  f.revertButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.revertButton:SetSize(90, 22)
  f.revertButton:SetPoint("LEFT", f.layoutButton, "RIGHT", 6, 0)
  f.revertButton:SetText("Revert")
  f.revertButton:SetScript("OnClick", function()
    if CDS.Revert then CDS.Revert() end
  end)
  -- A disabled Button eats OnEnter, so the greyed Revert had no way to say WHY it was grey — and a
  -- button that is permanently dark and silent reads as broken rather than as inapplicable. Reported
  -- as exactly that: "the revert button does nothing". The tooltip is the only thing that can answer
  -- "what would this even undo?", so it has to survive the state it is most needed in.
  f.revertButton:SetMotionScriptsWhileDisabled(true)
  f.revertButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Revert")
    GameTooltip:AddLine("Undoes the last layout change — applying a layout,|nimporting one, or the "
      .. "starter reset.|n|nOne step, and only for this session.", 1, 1, 1)
    if not (CDS.CanRevert and CDS.CanRevert()) then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Nothing to undo. It covers LAYOUTS, not the settings|non these tabs — a "
        .. "viewer's own size and position revert|nfrom its edit-mode panel instead.", 1, 0.3, 0.3)
    end
    GameTooltip:Show()
  end)
  f.revertButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  panel = f
  CDS.panel = f
  return f
end

CDS.Build = build

-- ── Display mode ────────────────────────────────────────────────────────────────────────────────

function CDS.SetDisplayMode(mode)
  build()
  if mode ~= "spells" and mode ~= "auras" and mode ~= "settings" then mode = "spells" end
  currentMode = mode
  CDS.displayMode = mode   -- read by the category grids in 4b-2

  for _, tab in ipairs(panel.tabButtons) do
    tab:SetSelectedState(tab.displayMode == mode)
  end

  local settings = (mode == "settings")

  -- The search box and the cog are both about the GRIDS: one dims non-matching tiles, the other
  -- holds the Show Unlearned filter. Neither has any meaning over a page of sliders, and a search
  -- box that silently does nothing is worse than an absent one.
  if settings then panel.search:Hide() else panel.search:Show() end
  if settings then panel.settingsCog:Hide() else panel.settingsCog:Show() end

  -- Same for the footer: a layout captures spell lists, tracked auras, trinket placement, alerts and
  -- sounds — not viewer geometry. Leaving "Layout: X" under a page of icon-size sliders would imply
  -- it saves them.
  if settings then panel.layoutButton:Hide() else panel.layoutButton:Show() end
  if settings then panel.revertButton:Hide() else panel.revertButton:Show() end

  if settings then
    -- Built on first use; a player who never opens this tab never pays for its ~60 frames.
    if CDS.EnsureSettingsPage then CDS.EnsureSettingsPage() end
    panel.content:Hide()
    panel.settingsContent:Show()
    panel.scroll:SetScrollChild(panel.settingsContent)
    if CDS.RefreshSettingsPage then CDS.RefreshSettingsPage() end
  else
    panel.settingsContent:Hide()
    panel.content:Show()
    panel.scroll:SetScrollChild(panel.content)
    CDS.RefreshLayout()
  end

  -- After the refresh, so the new child has its final height: the ScrollFrame recomputes its range
  -- from the child, and the scrollbar is stale until it does. The offset is one number on the SCROLL
  -- frame, not per-child, so a swap from halfway down a long page would otherwise land the short one
  -- scrolled past its own end.
  panel.scroll:UpdateScrollChildRect()
  panel.scroll:SetVerticalScroll(0)
end

function CDS.GetDisplayMode() return currentMode end

-- ── Footer state ────────────────────────────────────────────────────────────────────────────────
-- Both are called from SettingsPresets after any change, and are safe before the panel exists —
-- Presets loads after this file but a slash command can reach either first.

function CDS.RefreshLayoutDropdown()
  if not (panel and panel.layoutButton) then return end
  local cur = CDS.presets and CDS.presets.Current and CDS.presets.Current()
  panel.layoutButton:SetText(cur or "Layout: Starter")
end

function CDS.RefreshRevertState()
  if not (panel and panel.revertButton) then return end
  if CDS.CanRevert and CDS.CanRevert() then
    panel.revertButton:Enable()
  else
    panel.revertButton:Disable()
  end
end

-- ── Search text ─────────────────────────────────────────────────────────────────────────────────
-- ClassicAPI's SearchBoxTemplate has NO Instructions FontString: its placeholder IS the edit box's
-- text (SearchBoxTemplate_OnLoad calls SetText(SEARCH), and OnEditFocusLost puts it back). So an
-- untouched search box reads back "Search", and handing that to the filter dimmed every tile in the
-- panel to 25% — which is what "all the icons are greyed out" turned out to be. Every read of the
-- box goes through here.
function CDS.GetSearchText()
  if not (panel and panel.search) then return "" end
  local t = panel.search:GetText() or ""
  if t == (SEARCH or "Search") then return "" end
  return t
end

-- Replaced by the real category-grid builder in SettingsCategories.lua, which loads after this file.
-- Kept as a no-op so a load failure there costs the grids, not every SetDisplayMode call. (It used to
-- paint a "coming in the next step" placeholder; that placeholder outlived 4b-2 by four phases.)
function CDS.RefreshLayout() end

-- ── Public entry points ─────────────────────────────────────────────────────────────────────────

-- THE WINDOW IS PART OF THE MODULE, so an off Cooldown Manager has no window (owner's decision). Every
-- route in — /cdm, the DragonUI options button, OpenTo from anywhere — funnels through ShowPanel, so
-- this is the one gate, and it sits BEFORE build(): the panel is several hundred frames built lazily on
-- first open, and a player who never turns the module on should never pay for them.
--
-- It also answers the question that off-by-default would otherwise leave open — where a player goes to
-- switch it on. Not here: the window would be a dead end that configures viewers it cannot show. The
-- switch is in DragonUI's options, which is where every other module's is, so the message names it.
local function windowAvailable()
  if M.IsEnabled() then return true end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1Cooldown Manager|r is turned off. Enable it in DragonUI's "
      .. "options, under New Era > Cooldown Manager.")
  end
  return false
end

-- Always through SetDisplayMode, never a bare RefreshLayout: which body is on screen, which chrome is
-- shown, and which refresher runs all depend on the mode, and re-opening on the settings tab has to
-- re-read the store rather than rebuild the grids.
function CDS.ShowPanel()
  if not windowAvailable() then return end
  build()
  CDS.SetDisplayMode(currentMode or "spells")
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  if CDS.RefreshRevertState then CDS.RefreshRevertState() end
  panel:Show()
end

function CDS.HidePanel()
  if panel then panel:Hide() end
end

-- Closing is never gated. The window can be up when the module goes off — open /cdm, then untick the
-- toggle in DragonUI's options — and /cdm has to stay the way to shut it. (M.SetEnabled closes it for
-- exactly that reason; this is the case where the player gets there first.)
function CDS.TogglePanel()
  if panel and panel:IsShown() then panel:Hide(); return end
  CDS.ShowPanel()
end

-- Open with a viewer category pre-selecting the right tab. `category` may also be a display mode, so a
-- caller can open straight onto "settings".
--
-- Gated before build() for the same reason ShowPanel is — this is a public entry point in its own right
-- (M.OpenSettingsPanel), and reaching build() through it would defeat the point of gating the other.
function CDS.OpenTo(category)
  if not windowAvailable() then return end
  build()
  currentMode = CATEGORY_TO_MODE[category]
    or ((category == "spells" or category == "auras" or category == "settings") and category)
    or "spells"
  CDS.ShowPanel()
end

-- One entry point for slash commands and any future keybind.
M.OpenSettingsPanel = function(category) CDS.OpenTo(category) end

SLASH_NECDMSETTINGS1 = "/cdm"
SlashCmdList["NECDMSETTINGS"] = function() CDS.TogglePanel() end
