-- DragonUI_NewEra/modules/cooldownviewer/EditorPanel.lua — each viewer's settings as a dialog beside
-- the frame, in edit mode.
--
-- WHAT THIS REPLACES. The first pass at retail's on-the-frame settings (§H.3.10) was a right-click
-- CONTEXT MENU: every setting as a submenu of radios. It worked, and it was the wrong shape. Retail —
-- and NewEra's own 1.15 edit mode, which is what the owner is comparing against — opens a small DIALOG
-- next to the selected frame, with the sliders and dropdowns visible at once. The difference is not
-- cosmetic: a menu shows you one setting at a time and hides the value you are trying to match, and a
-- numeric setting inside it has to become a list of discrete rows (§H.3.10 shipped opacity in steps of
-- 5 for exactly that reason, and had to explain in a tooltip why a value could tick nothing at all).
-- A dialog shows every value at once and takes a real slider, so both compromises simply go away.
--
-- SEAM: NE.RegisterHUDFrame's `editorSettings` field — a callback, not a menu generator, so the host
-- glue in integration/Register.lua does not care what a module chooses to open (CONTRACTS §4). Every
-- DragonUI touch lives there: the mouse handler, the edit-mode gate, SelectEditorFrame, EditorMode.
--
-- WIDGETS ARE THE /cdm SETTINGS KIT (SettingsControls.lua), not a second set. One new control was
-- needed — AddCompactSlider, a one-line slider with nudge arrows — because the tab's tall two-line
-- slider is right for a page you scroll and wrong for a dialog that has to sit on the screen next to
-- the thing it edits without burying it.
--
-- THIS IS NOW THE ONLY EDITOR FOR THESE VALUES. For a while it was the second one, with the /cdm
-- Settings tab rendering the same thirteen controls and a refresh contract holding the two together —
-- which SettingsOptions.lua's header forbids for good reason. The owner's call was to delete the
-- duplicate rather than keep syncing it, so those sections left the tab and what stands in their place
-- is four buttons that open this. The dialog still re-reads every control through col:Refresh() on
-- open, because a layout apply or a reset can still move a value underneath it.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

-- Geometry transcribed from retail's EditModeSystemSettingsDialog, via NewEra's own transcription of
-- it (ReferenceAddons/NewEra/EditMode/SettingsPopup.lua): 343×32 rows spaced 2, a 100px label column,
-- 20px content inset each side, and the buttons region at the bottom.
local ROW_W, ROW_H, ROW_GAP = 343, 32, 2
local LABEL_W   = 100
local CONTENT_X = 20
local PANEL_W   = ROW_W + (CONTENT_X * 2)
local BODY_TOP  = 43         -- title at TOP -15, options at its BOTTOM -12
local BTN_H     = 28
-- Revert and Reset sit SIDE BY SIDE on one row (owner steer). Stacked, they cost 46px of a dialog
-- that has to sit on screen next to the frame it edits, and they read as a list of two things to
-- work down rather than the pair of alternatives they are.
local BTN_GAP   = 3
local BTN_W     = math.floor((ROW_W - BTN_GAP) / 2)
local FOOTER_H  = 15 + BTN_H + 10               -- button row, divider above it
local SIDE_GAP  = 12         -- clearance between the dialog and the frame it edits

-- Same value/label pairs, in the same order, as the /cdm Settings tab.
local ORIENTATION = { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }
local DIRECTION   = { { "right", "Right" }, { "left", "Left" } }
local VISIBILITY  = { { "always", "Always" }, { "incombat", "In Combat" }, { "hidden", "Hidden" } }
local BAR_CONTENT = { { "iconAndName", "Icon and Name" }, { "iconOnly", "Icon Only" },
                      { "nameOnly", "Name Only" } }

local function pct(v) return tostring(v) .. "%" end
local function px(v)  return tostring(v) .. "px" end

local panel                  -- the one dialog
local pages   = {}           -- category -> { body, col, dirtyCheck }
local current                -- category currently shown
local snapshots = {}         -- category -> the values Revert goes back to, per editor session

-- THE TAB IS NO LONGER A SECOND VIEW ONTO THESE VALUES. It was, and every write here called
-- CDS.RefreshSettingsPage to stop the two drifting; the owner's call was to remove the duplicate
-- rather than keep syncing it, so the tab now carries only settings this dialog does not. That makes
-- the notify dead weight on a path that runs on every tick of a slider drag, so it is gone. If a
-- per-viewer control is ever added back to the tab, this is the contract it has to restore —
-- SettingsOptions.lua's header is where that rule is written down.

local function specFor(category)
  for _, s in ipairs(M.VIEWER_SPECS or {}) do
    if s.category == category then return s end
  end
  return nil
end

-- ── Revert ──────────────────────────────────────────────────────────────────────────────────────
--
-- "Revert Changes" goes back to how this viewer was when the editor was opened, NOT to defaults —
-- that is what the button below it is for, and conflating the two is how someone loses a setup they
-- spent ten minutes on. So the snapshot is taken the first time the dialog is opened for a viewer in
-- an editor session, and dropped when the editor closes.

local function snapshotOf(category)
  local frameID = M.FRAME_ID[category]
  local t = { _enabled = M.IsCategoryEnabled(category) }
  for key in pairs(M.DEFAULTS or {}) do t[key] = M.GetOpt(frameID, key) end
  return t
end

local function ensureSnapshot(category)
  if not snapshots[category] then snapshots[category] = snapshotOf(category) end
  return snapshots[category]
end

local function isDirty(category)
  local snap = snapshots[category]
  if not snap then return false end
  local now = snapshotOf(category)
  for key, v in pairs(snap) do
    if now[key] ~= v then return true end
  end
  return false
end

local function revert(category)
  local snap = snapshots[category]
  if not snap then return end
  local frameID = M.FRAME_ID[category]
  for key, v in pairs(snap) do
    if key ~= "_enabled" then M.SetOpt(frameID, key, v) end
  end
  M.SetCategoryEnabled(category, snap._enabled)
end

-- ── The Reset confirm ───────────────────────────────────────────────────────────────────────────
--
-- OUR OWN FRAME, INSIDE THE DIALOG. It was a StaticPopup, and it kept opening underneath DragonUI's
-- Exit Edit Mode / Reset All Positions buttons — which sit on UIParent at TOOLTIP frame level 1000
-- (DragonUI/modules/editor_mode.lua:190, 210) and park at screen centre, exactly where a StaticPopup
-- lands. Two attempts at out-stacking them failed in game (first aiming at the wrong frame, then
-- reading the level at show time), so the fight is not worth having: a confirm parented to THIS DIALOG
-- draws inside the dialog's own stacking, above it by construction, and appears beside the viewer
-- being edited rather than in the middle of the screen where those buttons live. There is nothing left
-- for it to lose to.
--
-- It is also MODAL to the dialog — a blocker fills the panel behind it — because the question is about
-- the very settings underneath, and letting someone go on nudging sliders behind an unanswered "are
-- you sure?" invites answering it about a different state than the one they read.
--
-- The text is rewritten per viewer at ask time. A generic "are you sure?" over four
-- differently-configured viewers is the kind of prompt people learn to click through.

local CONFIRM_W = PANEL_W - 60
local CONFIRM_BTN_W = 110

local function ensureConfirm(f)
  if f.confirm then return f.confirm end

  -- Fills the dialog, eats every click meant for the controls behind. Below the confirm, above
  -- everything else the panel holds.
  local blocker = CreateFrame("Frame", nil, f)
  blocker:SetAllPoints(f)
  blocker:EnableMouse(true)
  blocker:SetFrameLevel(f:GetFrameLevel() + 10)
  blocker:Hide()
  local dim = blocker:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints()
  dim:SetTexture(0, 0, 0, 0.55)

  local c = CreateFrame("Frame", "NE_CDMEditorConfirm", f)
  c:SetWidth(CONFIRM_W)
  c:SetPoint("CENTER", f, "CENTER", 0, 0)
  c:SetFrameLevel(blocker:GetFrameLevel() + 10)
  c:EnableMouse(true)
  c:Hide()

  -- Same chrome as the dialog it sits in: black under the DiamondMetal "Dialog" nineslice. Opaque
  -- rather than the dialog's 0.8, so the controls it is asking about do not read through it.
  local bg = c:CreateTexture(nil, "BACKGROUND", nil, -5)
  bg:SetTexture(0, 0, 0, 0.95)
  bg:SetPoint("TOPLEFT", 7, -7)
  bg:SetPoint("BOTTOMRIGHT", -7, 7)
  c.Bg = bg
  if NE.nineslice and NE.nineslice.ApplyLayout then
    pcall(NE.nineslice.ApplyLayout, c, "Dialog")
  end

  -- WIDTH, not two anchors. Anchoring TOPLEFT and TOPRIGHT does give the FontString a width, but on
  -- 3.3.5a that width TRUNCATES with an ellipsis instead of wrapping — the second paragraph came out as
  -- "This viewer's position, size, orientation and vis...". An explicit SetWidth wraps, which is the
  -- same reason SettingsControls' AddText sets one.
  c.Text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  c.Text:SetWidth(CONFIRM_W - 36)
  c.Text:SetPoint("TOP", c, "TOP", 0, -20)
  c.Text:SetJustifyH("CENTER")

  local function confirmButton(label, w, onClick)
    local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    b:SetSize(w, BTN_H)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if NE.button and NE.button.Skin then pcall(NE.button.Skin, b) end
    return b
  end

  c.YesButton = confirmButton(YES or "Yes", CONFIRM_BTN_W, function()
    local cat = c._category
    M.HideConfirm()
    if not cat then return end
    M.ResetOpts(M.FRAME_ID[cat])
    M.RefreshEditorPanel()
  end)
  c.YesButton:SetPoint("BOTTOMRIGHT", c, "BOTTOM", -4, 16)

  c.NoButton = confirmButton(NO or "No", CONFIRM_BTN_W, function() M.HideConfirm() end)
  c.NoButton:SetPoint("BOTTOMLEFT", c, "BOTTOM", 4, 16)

  c.Blocker = blocker
  f.confirm = c
  return c
end

-- Ask about `category`. Public so the test can drive the same path the button does.
function M.ShowConfirmReset(category)
  if not (panel and category) then return false end
  local c = ensureConfirm(panel)
  local spec = specFor(category)
  c._category = category
  c.Text:SetText("Reset " .. ((spec and spec.label) or category) ..
    " to its default layout?\n\nThis viewer's position, size, orientation and visibility all go back " ..
    "to stock. Nothing else is affected, and it cannot be undone.")
  -- Sized to the wrapped text. The floor covers the offline harness, whose FontString cannot measure.
  local textH = math.max(60, (c.Text.GetStringHeight and c.Text:GetStringHeight() or 0) + 4)
  c:SetHeight(20 + textH + 18 + BTN_H + 16)
  c.Blocker:Show()
  c:Show()
  return true
end

function M.HideConfirm()
  local c = panel and panel.confirm
  if not c then return end
  c._category = nil
  c:Hide()
  c.Blocker:Hide()
end

M.IsConfirmShown = function()
  local c = panel and panel.confirm
  return (c and c:IsShown()) and true or false
end

-- ── One viewer's page ───────────────────────────────────────────────────────────────────────────

local function buildPage(category)
  local Kit = NE.cooldownviewersettings and NE.cooldownviewersettings.controls
  if not (Kit and Kit.New) then return nil end

  local frameID = M.FRAME_ID[category]
  local spec    = specFor(category)

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_X, -BODY_TOP)
  body:SetWidth(ROW_W)
  body:Hide()

  -- The dialog's metrics, not the Settings tab's. Same widgets either way — see the theme note in
  -- SettingsControls.lua.
  local col = Kit.New(body, ROW_W, {
    labelFont   = "GameFontHighlightMedium",
    checkSize   = 32,
    checkH      = ROW_H,
    sliderH     = ROW_H,
    dropH       = ROW_H,
    labelW      = LABEL_W,
    -- controlW deliberately unset: the dropdowns FILL the control column, so their left edge lands on
    -- the compact slider's nudge arrow and their right edge on its value text. A fixed 200 lined up
    -- with neither.
    dropdownArt = true,
    buttonH     = BTN_H + 4,
    buttonArtH  = BTN_H,
  })

  local function get(key) return M.GetOpt(frameID, key) end
  -- Every write goes through here: store, then the OTHER view, then this dialog's own Revert state.
  local function set(key)
    return function(v)
      M.SetOpt(frameID, key, v)
      if panel and panel.UpdateRevert then panel.UpdateRevert() end
    end
  end
  local function getter(key) return function() return get(key) end end

  col:AddCheckbox({
    label = "Enabled",
    desc  = "Show this viewer at all. The editor handle stays either way, so this is reversible from "
            .. "right here.",
    get   = function() return M.IsCategoryEnabled(category) end,
    set   = function(v)
      M.SetCategoryEnabled(category, v)
      if panel and panel.UpdateRevert then panel.UpdateRevert() end
    end,
  })

  col:AddDropdown({
    label = "Orientation", values = ORIENTATION,
    get = getter("orientation"), set = set("orientation"),
  })
  col:AddCompactSlider({
    label = "Icon Limit", min = 1, max = 20, step = 1,
    desc  = "How many icons before the layout wraps. Vertical orientation reads this as icons per "
            .. "column.",
    get = getter("iconLimit"), set = set("iconLimit"),
  })
  col:AddDropdown({
    label = "Icon Direction", values = DIRECTION,
    get = getter("iconDirection"), set = set("iconDirection"),
  })
  col:AddCompactSlider({
    label = "Icon Size", min = 50, max = 200, step = 10, format = pct,
    get = getter("iconSize"), set = set("iconSize"),
  })
  col:AddCompactSlider({
    label = "Icon Padding", min = 0, max = 14, step = 1, format = px,
    desc  = "Gap between icons. Retail offsets this by -4, so the low end overlaps slightly — that is "
            .. "the stock look, not a bug.",
    get = getter("iconPadding"), set = set("iconPadding"),
  })
  col:AddCompactSlider({
    label = "Opacity", min = 50, max = 100, step = 1, format = pct,
    get = getter("opacity"), set = set("opacity"),
  })
  col:AddDropdown({
    label = "Visibility", values = VISIBILITY,
    desc  = "When this viewer is on screen at all. Hidden still leaves the editor handle here.",
    get = getter("visibleSetting"), set = set("visibleSetting"),
  })

  -- Only where it does something: retail's Essential/Utility templates do not set
  -- allowHideWhenInactive, so UpdateShownState ignores the setting there. The /cdm tab drops the
  -- control for the same reason, and a row that silently does nothing is worse than no row.
  if get("allowHideWhenInactive") then
    col:AddCheckbox({
      label = "Hide When Inactive",
      desc  = "Show a slot only while its aura is active.",
      get   = function() return get("hideWhenInactive") and true or false end,
      set   = set("hideWhenInactive"),
    })
  end

  col:AddCheckbox({
    label = "Show Timer",
    desc  = "Draw the countdown number on each icon.",
    get   = function() return get("showTimer") and true or false end,
    set   = set("showTimer"),
  })
  col:AddCheckbox({
    label = "Show Tooltips",
    desc  = "Show a tooltip when hovering an icon.",
    get   = function() return get("showTooltips") and true or false end,
    set   = set("showTooltips"),
  })

  -- Bar-only, exactly as retail exposes them (the BuffBar system alone).
  if spec and spec.bar then
    col:AddDropdown({
      label = "Bar Content", values = BAR_CONTENT,
      get = getter("barContent"), set = set("barContent"),
    })
    col:AddCompactSlider({
      label = "Bar Width", min = 50, max = 200, step = 5, format = pct,
      get = getter("barWidthScale"), set = set("barWidthScale"),
    })
  end

  -- Retail's AddExtraButtons puts a system's own extra actions at the END of the options stack,
  -- above the Revert/Reset region — which is where NewEra's dialog carries this one too.
  col:AddButton({
    label = "Cooldown Manager Settings",
    width = ROW_W,
    desc  = "Closes edit mode and opens the Cooldown Manager window, which carries the settings that "
            .. "are not per-viewer: alerts, ready sounds, buff tracking, icon fit and the resets.",
    onClick = function()
      -- Leave the editor first: it covers the screen, and DragonUI saves every frame's position on
      -- the way out, so nothing is lost by going this way.
      if NE.CloseFrameEditor then NE.CloseFrameEditor() end
      if M.OpenSettingsPanel then M.OpenSettingsPanel("settings") end
    end,
  })

  col:Relayout()
  local page = { body = body, col = col, category = category }
  pages[category] = page
  return page
end

-- ── The dialog ──────────────────────────────────────────────────────────────────────────────────

local function ensurePanel()
  if panel then return panel end

  local f = CreateFrame("Frame", "NE_CDMEditorPanel", UIParent)
  f:SetSize(PANEL_W, 200)
  -- Above the editor's own handles, which CreateUIFrame puts at FULLSCREEN. A settings dialog that
  -- renders behind the frame it configures is not a settings dialog.
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self._moved = true   -- once you place it yourself, it stops jumping to each frame you select
  end)
  f:Hide()

  -- CHROME: retail's DialogBorderTranslucentTemplate — black at 0.8 inset 7, under the DiamondMetal
  -- "Dialog" nineslice. NOT PanelChrome's portrait frame, which is window chrome: applied to a small
  -- floating dialog it brings the rock fill and the portrait ring, and reads as a window that lost
  -- its contents.
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -5)
  bg:SetTexture(0, 0, 0, 0.8)
  bg:SetPoint("TOPLEFT", 7, -7)
  bg:SetPoint("BOTTOMRIGHT", -7, 7)
  f.Bg = bg
  if NE.nineslice and NE.nineslice.ApplyLayout then
    pcall(NE.nineslice.ApplyLayout, f, "Dialog")
  end

  f.TitleText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  f.TitleText:SetPoint("TOP", 0, -15)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT")
  local PC = NE.chrome
  if PC and PC.ModernizeCloseButton then
    pcall(PC.ModernizeCloseButton, close, { anchor = false })
  end
  close:SetScript("OnClick", function() M.HideEditorPanel() end)
  f.CloseButton = close

  -- Buttons region: Revert and Reset as a pair on one row, under a divider. Built once and pointed at
  -- whichever viewer is showing — two buttons differing only in which category they act on would be
  -- two copies of this block. "Cooldown Manager Settings" is NOT here; retail puts a system's extra
  -- actions at the end of the options stack, and so does buildPage.
  local function footerButton(label, w, onClick)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w, BTN_H)
    b:SetText(label)
    b:SetScript("OnClick", function() if current then onClick(current) end end)
    if NE.button and NE.button.Skin then pcall(NE.button.Skin, b) end
    return b
  end

  f.buttonsDivider = f:CreateTexture(nil, "ARTWORK")
  f.buttonsDivider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
  f.buttonsDivider:SetSize(330, 16)
  f.buttonsDivider:SetPoint("BOTTOM", 0, 15 + BTN_H + 1)

  f.revertButton = footerButton("Revert Changes", BTN_W, function(category)
    revert(category)
    M.RefreshEditorPanel()
  end)
  f.revertButton:SetPoint("BOTTOMLEFT", CONTENT_X, 15)

  -- Reset CONFIRMS. Revert is bounded — it undoes this editor session and the button greys itself out
  -- when there is nothing to undo — but Reset throws away every layout choice ever made for this
  -- viewer, and nothing in the addon can put it back. The two now sit a few pixels apart, so the one
  -- that is not reversible asks.
  f.resetButton = footerButton("Reset to Default", BTN_W, function(category)
    M.ShowConfirmReset(category)
  end)
  f.resetButton:SetPoint("BOTTOMRIGHT", -CONTENT_X, 15)

  -- Revert is disabled until there IS something to revert. A button that is always live and usually
  -- does nothing teaches you to ignore it, and this one is the undo.
  function f.UpdateRevert()
    local on = current and isDirty(current)
    if on then f.revertButton:Enable() else f.revertButton:Disable() end
  end

  panel = f
  return f
end

-- Place beside the frame being edited, on whichever side has room. Skipped once the player has
-- dragged the dialog somewhere themselves.
--
-- ANCHORED TO UIParent, NOT TO THE FRAME, and that is the whole point. A relative point kept the
-- dialog glued to the viewer's edge — so dragging Icon Size or Icon Limit resized the viewer and the
-- dialog SLID SIDEWAYS under the cursor, mid-drag, which is unusable. The position is resolved once,
-- here, into screen coordinates; the dialog then stays where it was put until another frame is
-- selected. The trade is that a viewer which grows a lot can end up overlapping its own dialog, and
-- a dialog that holds still is worth more than one that never touches the frame.
local function place(f, anchor)
  if f._moved then return end
  f:ClearAllPoints()
  local sw = (UIParent and UIParent:GetWidth()) or 1024
  local cx = anchor and anchor.GetCenter and select(1, anchor:GetCenter())
  local left  = anchor and anchor.GetLeft  and anchor:GetLeft()
  local right = anchor and anchor.GetRight and anchor:GetRight()
  local top   = anchor and anchor.GetTop   and anchor:GetTop()
  if not (cx and left and right and top) then
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  elseif cx > sw / 2 then
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - SIDE_GAP, top)
  else
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + SIDE_GAP, top)
  end
end

-- ── API ─────────────────────────────────────────────────────────────────────────────────────────

function M.ShowEditorPanel(category, anchor)
  if not (category and M.FRAME_ID and M.FRAME_ID[category]) then return false end
  local f = ensurePanel()
  if not f then return false end

  local page = pages[category] or buildPage(category)
  if not page then return false end

  for cat, p in pairs(pages) do
    if cat ~= category then p.body:Hide() end
  end
  page.body:Show()
  -- An unanswered confirm names ONE viewer and acts on `current`; selecting another frame would leave
  -- it asking about the old one and resetting the new. It goes with the page it belongs to.
  if current ~= category then M.HideConfirm() end
  current = category

  -- Re-read every control before showing. Something else may have moved these underneath us — the
  -- /cdm tab, a layout apply, a reset — and a dialog that opens on stale values is indistinguishable
  -- from one whose settings did not take.
  page.col:Refresh()
  local h = page.col:Relayout()

  local spec = specFor(category)
  f.TitleText:SetText((spec and spec.label) or category)

  -- Size to the page. Height varies by viewer — Buff Bars carries two rows nothing else does — so
  -- this is computed rather than a constant that would clip one of them. The buttons region is
  -- anchored to the bottom edge, so it follows for free.
  f:SetHeight(BODY_TOP + h + 10 + FOOTER_H)

  ensureSnapshot(category)
  f.UpdateRevert()
  place(f, anchor or (M.viewers and M.viewers[category] and M.viewers[category].editorAnchor))
  f:Show()
  return true
end

-- Re-read the open page. Used by the footer buttons, which change values without going through a
-- control's own setter.
function M.RefreshEditorPanel()
  local page = current and pages[current]
  if not page then return end
  page.col:Refresh()
  if panel and panel.UpdateRevert then panel.UpdateRevert() end
end

-- Closing the editor drops the Revert snapshots: "revert" means "back to how this was when I started
-- editing", and once you have left, that session is over. Keeping them would silently arm the button
-- with a state from an hour ago.
function M.HideEditorPanel()
  M.HideConfirm()
  snapshots = {}
  current = nil
  if panel then panel:Hide() end
end

M.IsEditorPanelShown = function() return (panel and panel:IsShown()) and true or false end
M._editorPanel = function() return panel, pages end   -- test seam
