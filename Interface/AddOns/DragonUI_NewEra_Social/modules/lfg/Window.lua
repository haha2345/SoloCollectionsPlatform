-- DragonUI_NewEra/modules/lfg/Window.lua — NE_GroupFinderFrame: the unified Group Finder shell.
--
-- DOWNPORT of NewEra/LFGFrame/PVEFrame.lua (retail PVEFrame geometry, capture eff 0.7111) onto
-- 3.3.5a. The reference wraps Era's premade-group system (C_LFGList); none of that exists here —
-- WotLK's two live systems are the Dungeon Finder (LFD) and the Raid Browser (LFR), so the
-- category rail collapses to TWO live buttons (owner direction 2026-07-18: "tabs in it Dungeons
-- and raids. Ignore PVP. The right hand side can be the queuing window"):
--   Dungeons → the LFD queue pane (Dungeons.lua)
--   Raids    → the LFR queue/browse pane (Raids.lua)
--
-- ARCHITECTURE (differs from the reference on purpose): the native LFDParentFrame/LFRParentFrame
-- remain loaded and are the STATE MACHINE — their always-registered event handlers keep
-- LFDQueueFrame.type, LFGEnabledList/LFGQueuedForList/LFGLockList, role selections etc. alive.
-- This window is a modern VIEW over that state: panes call the same shared FrameXML mutators
-- (LFDList_SetDungeonEnabled / LFDQueueFrame_Join / LFRQueueFrame_Join / LeaveLFG / …) and
-- re-render from the shared lists on the same events. Open.lua reroutes the native toggles here.
--
-- RENDER-BEFORE-WIRE: this file is chrome + rail + pane plumbing only. Dungeons.lua / Raids.lua
-- register their panes via L.RegisterPane, guarded so load order can't crash.

local NE = DragonUI_NewEra
if not NE then return end

NE.lfg = NE.lfg or {}
local L = NE.lfg

local FRAME_NAME = "NE_GroupFinderFrame"
local MODULE = "LFG"

local function isModuleEnabled()
  return not (NE.modules and NE.modules.IsEnabled) or NE.modules.IsEnabled(MODULE)
end
L.IsEnabled = isModuleEnabled

-- ---------------------------------------------------------------------------
-- Dungeon Finder unlock gate. The micromenu's LFDMicroButton already greys itself out below the
-- client's unlock level, but that only covers ONE entry point — the TOGGLELFGPARENT keybind, the
-- minimap eye and any addon calling the toggles bypass it entirely, and Open.lua reroutes all of
-- those straight into this window. So the gate lives HERE, at the show/toggle chokepoint every
-- path funnels through, rather than being re-implemented per entry point.
--
-- SHOW_LFD_LEVEL is the client's own constant (the same one the micro button's "requires level N"
-- state reads), so we stay in lockstep with the micromenu whatever the server sets it to; the
-- literal is only a fallback for clients that don't define it.
local DUNGEONS_MIN_LEVEL = SHOW_LFD_LEVEL or 10
L.DUNGEONS_MIN_LEVEL = DUNGEONS_MIN_LEVEL

-- PLAYER_LEVEL_UP hands us the new level; UnitLevel("player") is not guaranteed to have caught up
-- yet while that event is being handled, so the event arg wins when it's higher.
local levelHint = 0
local function playerLevel()
  local lvl = UnitLevel("player") or 0
  if levelHint > lvl then lvl = levelHint end
  return lvl
end

-- A category is locked until the player reaches its minLevel (only DUNGEONS declares one).
local function categoryUnlocked(def)
  return not def.minLevel or playerLevel() >= def.minLevel
end

local function lockedMessage(def)
  return format(FEATURE_BECOMES_AVAILABLE_AT_LEVEL or "This feature becomes available at level %d.",
                def.minLevel)
end

function L.IsDungeonsUnlocked()
  return playerLevel() >= DUNGEONS_MIN_LEVEL
end

-- ---------------------------------------------------------------------------
-- Reference geometry tables (PVEFrame.lua, transcribed verbatim where possible).
-- ---------------------------------------------------------------------------

-- bluemenu group-button bg slices (retail GroupFinderFrameButton_SetEnabled/_Select). 593918 sheet.
local BTN_TC = {
  enabled  = { 0.00390625, 0.87890625, 0.75195313, 0.83007813 },
  selected = { 0.00390625, 0.87890625, 0.59179688, 0.66992188 },
  disabled = { 0.00390625, 0.87890625, 0.67187500, 0.75000000 },
}

-- Category rail decorative textures (file/size/layer/anchor/texcoord from the retail capture).
-- f: m=bluemenu-main(593918) v=vert(593919) g=goldborder(593917) — shipped by modules/guild/Assets.
local RAIL = {
  { key="BlueBg",         f="m", w=209, h=399, layer="BORDER",  sub=-1, a={"TOPLEFT","f","TOPLEFT",7,-23},
    tc={0.00390625,0.82421875,0.18554688,0.58984375} },
  { key="TLCorner",       f="m", w=64,  h=64,  layer="ARTWORK", a={"TOPLEFT","BlueBg","TOPLEFT",0,0},
    tc={0.00390625,0.25390625,0.00097656,0.06347656} },
  { key="TRCorner",       f="m", w=64,  h=64,  layer="ARTWORK", a={"TOPLEFT","f","TOPLEFT",151,-23},
    tc={0.51953125,0.76953125,0.00097656,0.06347656} },
  { key="BRCorner",       f="m", w=64,  h=64,  layer="ARTWORK", a={"BOTTOMLEFT","f","BOTTOMLEFT",151,7},
    tc={0.00390625,0.25390625,0.06542969,0.12792969} },
  { key="BLCorner",       f="m", w=64,  h=64,  layer="ARTWORK", a={"BOTTOMLEFT","f","BOTTOMLEFT",7,7},
    tc={0.26171875,0.51171875,0.00097656,0.06347656} },
  { key="LLVert",         f="v", w=43,  h=270, layer="ARTWORK", a={"TOPLEFT","f","TOPLEFT",7,-87},   vTile=true,
    tc={0.06250000,0.39843750,0.0,1.0} },
  { key="RLVert",         f="v", w=43,  h=270, layer="ARTWORK", a={"TOPLEFT","f","TOPLEFT",172,-87}, vTile=true,
    tc={0.41406250,0.75000000,0.0,1.0} },
  { key="BottomLine",     f="g", w=80,  h=43,  layer="ARTWORK", a={"BOTTOMLEFT","BLCorner","BOTTOMRIGHT",0,0}, hTile=true,
    tc={0.0,1.0,0.35937500,0.69531250} },
  { key="TopLine",        f="g", w=80,  h=43,  layer="ARTWORK", a={"TOPLEFT","TLCorner","TOPRIGHT",0,0},      hTile=true,
    tc={0.0,1.0,0.00781250,0.34375000} },
  { key="TopFiligree",    f="m", w=185, h=55,  layer="BORDER",  a={"TOPLEFT","BlueBg","TOPLEFT",12,-6},
    tc={0.00390625,0.72656250,0.12988281,0.18359375} },
  { key="BottomFiligree", f="m", w=185, h=55,  layer="BORDER",  a={"BOTTOMLEFT","BlueBg","BOTTOMLEFT",12,4},
    tc={0.26171875,0.98437500,0.06542969,0.11914063} },
}

-- WotLK-real categories. Dungeons = a stock 3.3.5a icon (the reference's retail choice, 133076
-- INV_Helmet_08, exists here as a path); Raids = the native 3.3.5a Raid Browser's OWN portrait art
-- (LFRFrame.xml's $parentIcon, file="Interface\LFGFrame\UI-LFR-PORTRAIT") — ships with the client,
-- so referencing the path directly is both correct AND needs no custom BLP copy/registration.
local CATEGORIES = {
  { key = "DUNGEONS", name = DUNGEONS or "Dungeons", icon = "Interface\\Icons\\INV_Helmet_08", default = true,
    minLevel = DUNGEONS_MIN_LEVEL },
  { key = "RAIDS",    name = RAIDS or "Raids", icon = "Interface\\LFGFrame\\UI-LFR-PORTRAIT" },
}

local function railFile(code)
  if not (NE.tex and NE.tex.Local) then return nil end
  if code == "m" then return NE.tex.Local(593918) end
  if code == "v" then return NE.tex.Local(593919) end
  if code == "g" then return NE.tex.Local(593917) end
end

-- ---------------------------------------------------------------------------
-- Animated "looking for players" eye — retail QueueStatusFrame EyeTemplate, ported as a Lua
-- sub-rect flipbook (reference PVEFrame.lua eyePlay). Grid dims are retail's exact FlipBook
-- params (QueueStatusFrame.xml). DOWNPORT: entry lookup goes through NE.tex._atlasEntry and the
-- shipped-path map instead of the generated NE_ATLAS global.
-- ---------------------------------------------------------------------------
local EYE_ANIMS = {
  initial   = { atlas = "groupfinder-eye-flipbook-initial",   cols = 11, rows = 5, frames = 52, duration = 1.5, next = "searching" },
  searching = { atlas = "groupfinder-eye-flipbook-searching", cols = 11, rows = 8, frames = 80, duration = 2.0, loop = true },
}

local function eyeSetFrame(tex, entry, def, f)
  local cw = (entry.right - entry.left) / def.cols
  local ch = (entry.bottom - entry.top) / def.rows
  local col, row = f % def.cols, math.floor(f / def.cols)
  local l, t = entry.left + col * cw, entry.top + row * ch
  tex:SetTexCoord(l, l + cw, t, t + ch)
end

local function eyePlay(eye, name)
  local def = EYE_ANIMS[name]
  local entry = def and NE.tex._atlasEntry and NE.tex._atlasEntry(def.atlas)
  local path = entry and NE.tex.Local(entry.file)
  if not path then return end
  eye.anim = { def = def, entry = entry, t = 0, frame = -1, name = name }
  eye.tex:SetTexture(path)
  eyeSetFrame(eye.tex, entry, def, 0)
  eye:Show()
  eye:SetScript("OnUpdate", function(self, elapsed)
    local a = self.anim; if not a then return end
    a.t = a.t + elapsed
    local fr = math.floor(a.t / (a.def.duration / a.def.frames))
    if fr >= a.def.frames and not a.def.loop then
      if a.def.next then eyePlay(self, a.def.next) end   -- intro finished → roll into the loop
      return
    end
    fr = fr % a.def.frames
    if fr ~= a.frame then a.frame = fr; eyeSetFrame(self.tex, a.entry, a.def, fr) end
  end)
end

local function eyeStop(eye)
  eye.anim = nil
  eye:SetScript("OnUpdate", nil)
  eye:Hide()
end

-- ---------------------------------------------------------------------------
-- Chrome (rock body + streaks + PortraitFrameTemplate nineslice + eye portrait + title + close).
-- Same recipe as modules/auctionhouse + modules/guild buildChrome.
-- ---------------------------------------------------------------------------
local function buildChrome(f)
  local body = f:CreateTexture(nil, "BACKGROUND", nil, -6)
  local rockPath = NE.tex and NE.tex.Local and NE.tex.Local(374155)
  body:SetTexture(rockPath or "Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
  body:SetHorizTile(true); body:SetVertTile(true)
  body:SetPoint("TOPLEFT",     f, "TOPLEFT",      4, -21)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,   0)
  f.Bg = body

  local streaks = f:CreateTexture(nil, "BORDER")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(streaks, "_UI-Frame-TopTileStreaks", false) end
  streaks:SetHorizTile(true); streaks:SetHeight(43)
  streaks:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -21)
  streaks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -21)
  f.TopTileStreaks = streaks

  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f)
  ns:EnableMouse(false)
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(ns, "PortraitFrameTemplate") end
  f.NineSlice = ns

  -- Eye portrait in the circular corner cutout: static groupfinder-eye-frame at rest…
  -- DOWNPORT: lives on its OWN dedicated `portraitLayer` frame (not a texture directly on `ns`,
  -- and not on `f`) — same original reasoning as before (a portrait texture owned by `f` sank
  -- below the corner's OVERLAY cutout piece owned by `ns`), PLUS buildRail (below) re-elevates
  -- this layer above the rail's blue panel frame once that exists, since the panel's top edge
  -- overlaps the medallion's lower portion (retail's round-portrait-over-panel look) and would
  -- otherwise cover it now that the rail is its own explicitly-elevated frame.
  local portraitLayer = CreateFrame("Frame", nil, f)
  portraitLayer:SetAllPoints(f)
  portraitLayer:EnableMouse(false)
  portraitLayer:SetFrameLevel((ns:GetFrameLevel() or 2) + 1)
  f.PortraitLayer = portraitLayer

  local eye = portraitLayer:CreateTexture(nil, "OVERLAY")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(eye, "groupfinder-eye-frame", false)) then
    eye:SetTexture("Interface\\LFGFrame\\UI-LFG-PORTRAIT")   -- native 3.3.5a eye as fail-safe
  end
  eye:SetSize(60, 60)
  eye:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 8)
  f.Portrait = eye

  -- …with the animated flipbook overlay on top while we're queued/listed. DOWNPORT: was sized to
  -- 51x51 assuming the flipbook's 44px-native tiles needed scaling DOWN relative to the static
  -- frame's 52px-native tile — but decoding both confirms each is a SELF-CONTAINED bezel+eye
  -- circle that already fills its own tile edge-to-edge; the 44-vs-52 difference is just how
  -- densely retail packed the two sheets, not a size cue. Matching the static eye's OWN display
  -- size instead makes the animation replace it seamlessly instead of shrinking inside its ring.
  local aeye = CreateFrame("Frame", nil, portraitLayer)
  aeye:SetFrameLevel(portraitLayer:GetFrameLevel() + 1)
  aeye:SetSize(eye:GetWidth(), eye:GetHeight())
  aeye:SetPoint("CENTER", eye, "CENTER", 0, 0)
  local atex = aeye:CreateTexture(nil, "OVERLAY")
  atex:SetAllPoints(aeye); atex:SetBlendMode("BLEND")
  aeye.tex = atex
  aeye:Hide()
  f.AnimEye = aeye

  -- Animate while the player is anywhere in the LFD/LFR pipeline. GetLFGMode covers both
  -- systems on 3.3.5a: "queued"/"rolecheck"/"proposal" = LFD, "listed" = LFR.
  function f.UpdateEye()
    local mode = GetLFGMode and GetLFGMode()
    if mode == "queued" or mode == "rolecheck" or mode == "proposal" or mode == "listed" then
      if not f.AnimEye.anim then eyePlay(f.AnimEye, "initial") end
    else
      eyeStop(f.AnimEye)
    end
  end

  -- Title band (same as modules/guild — a bare Frame has no TitleContainer, build it).
  local tc = CreateFrame("Frame", nil, f)
  tc:SetFrameLevel((ns:GetFrameLevel() or 2) + 10)
  tc:SetPoint("TOPLEFT",  f, "TOPLEFT",  58, -1)
  tc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)
  tc:SetHeight(20); tc:EnableMouse(false)
  local titleStr = tc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleStr:SetJustifyH("CENTER")
  titleStr:SetPoint("TOP",   f, "TOP",    0,  -6)
  titleStr:SetPoint("LEFT",  f, "LEFT",   58,  0)
  titleStr:SetPoint("RIGHT", f, "RIGHT", -58,  0)
  titleStr:SetText(LFG_TITLE or "Looking for Group")
  f.TitleContainer = tc
  f.TitleText = titleStr
  f.Title = titleStr

  local close = CreateFrame("Button", FRAME_NAME .. "CloseButton", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  close:SetScript("OnClick", function() L.Hide() end)
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    NE.panelchrome.ModernizeCloseButton(close, { frameLevelBump = 10 })
  end
  f.CloseButton = close
end

-- ---------------------------------------------------------------------------
-- Bluemenu category rail + left inset.
--
-- DOWNPORT FIX: RAIL's own art (BlueBg/corners/filigree/verts) used to be textures drawn DIRECTLY
-- on `f` — the SAME frame that carries the window's own PortraitFrameTemplate nineslice (`ns`,
-- buildChrome). Since `ns` is a CHILD FRAME of `f`, its content sits ABOVE any of f's own texture
-- layers regardless of draw layer (confirmed by the eye-portrait bug fix above: content owned by
-- `f` directly renders below content owned by `ns`). That silently blanked the whole rail. Fix:
-- give the rail its OWN dedicated child frame, EXPLICITLY leveled above `ns` (not relying on
-- same-level creation-order tie-breaking) — same recipe as modules/guild's WORKING
-- FilligreeOverlay ("fo:SetFrameLevel(list:GetFrameLevel() + 5)").
--
-- Also fixes: `CreateFrame(..., "InsetFrameTemplate")` was passing OUR custom Lua nineslice layout
-- NAME as if it were a real Blizzard XML inherits template — it isn't one (grep confirms every
-- other user of "InsetFrameTemplate" in this codebase calls NE.nineslice.ApplyLayout instead), so
-- the call silently no-opped and the inset never got its thin gold border.
-- ---------------------------------------------------------------------------
local function buildRail(f)
  local ns = f.NineSlice
  local rail = CreateFrame("Frame", FRAME_NAME .. "Rail", f)
  rail:SetAllPoints(f)
  rail:EnableMouse(false)
  rail:SetFrameLevel((ns and ns:GetFrameLevel() or f:GetFrameLevel() + 1) + 1)
  f.Rail = rail

  for _, r in ipairs(RAIL) do
    local t = rail:CreateTexture(nil, r.layer, nil, r.sub or 0)
    t:SetTexture(railFile(r.f))
    t:SetSize(r.w, r.h)
    if r.hTile then t:SetHorizTile(true) end
    if r.vTile then t:SetVertTile(true) end
    t:SetTexCoord(r.tc[1], r.tc[2], r.tc[3], r.tc[4])
    local rel = (r.a[2] == "f") and f or rail[r.a[2]]
    t:SetPoint(r.a[1], rel, r.a[3], r.a[4], r.a[5])
    rail[r.key] = t
  end

  local inset = CreateFrame("Frame", FRAME_NAME .. "LeftInset", rail)
  inset:SetPoint("TOPLEFT",    f, "TOPLEFT",    4, -24)
  inset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
  inset:SetWidth(217)
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(inset, "InsetFrameTemplate") end
  f.LeftInset = inset

  -- The eye medallion (buildChrome's portraitLayer) intentionally overlaps the panel's rounded
  -- top edge (retail's round-portrait-over-panel look) — re-elevate it above the rail NOW that
  -- the rail frame exists, so the panel doesn't cover the medallion's lower half.
  if f.PortraitLayer then
    f.PortraitLayer:SetFrameLevel(rail:GetFrameLevel() + 1)
    if f.AnimEye then f.AnimEye:SetFrameLevel(f.PortraitLayer:GetFrameLevel() + 1) end
  end

  -- The window's gold border — including the circular PortraitMetal top-left ring
  -- (PortraitFrameTemplate's TopLeftCorner) — lives on `ns` and must render ABOVE the eye so it
  -- FRAMES it (retail's round-portrait-in-ring look). The eye was elevated above the rail panel
  -- (so the panel can't cover its lower half), which also pushed it above `ns` — so the eye sat
  -- ON TOP of the gold ring instead of below it. Re-raise `ns` above the eye now. Safe: this
  -- nineslice is border-only (corners + edges, no center fill — see NineSliceLayouts), so the
  -- title/close (leveled ns+10) and rail content stay correct.
  if ns and f.PortraitLayer then
    ns:SetFrameLevel(f.PortraitLayer:GetFrameLevel() + 2)
  end
end

-- The gold ring around each rail icon. DOWNPORT: retail's bluemenu-ring backing file (922034)
-- isn't shipped (see Assets.lua header) — mirror the clean DF PortraitMetal ring quadrant
-- (ne-lfg-ring-quadrant, Textures/Common/2406979) four ways instead. Returns the 4 textures.
local function makeRing(btn, w, h)
  local entry = NE.tex and NE.tex._atlasEntry and NE.tex._atlasEntry("ne-lfg-ring-quadrant")
  local path = entry and NE.tex.Local(entry.file)
  if not path then return nil end
  local holder = CreateFrame("Frame", nil, btn)
  holder:SetSize(w, h)
  local halfW, halfH = w / 2, h / 2
  local quads = {
    { point = "TOPLEFT",     tc = { entry.left,  entry.right, entry.top,    entry.bottom } },
    { point = "TOPRIGHT",    tc = { entry.right, entry.left,  entry.top,    entry.bottom } },
    { point = "BOTTOMLEFT",  tc = { entry.left,  entry.right, entry.bottom, entry.top    } },
    { point = "BOTTOMRIGHT", tc = { entry.right, entry.left,  entry.bottom, entry.top    } },
  }
  holder.quads = {}
  for _, q in ipairs(quads) do
    local t = holder:CreateTexture(nil, "ARTWORK", nil, 3)
    t:SetTexture(path)
    t:SetSize(halfW, halfH)
    t:SetPoint(q.point, holder, q.point, 0, 0)
    t:SetTexCoord(q.tc[1], q.tc[2], q.tc[3], q.tc[4])
    holder.quads[#holder.quads + 1] = t
  end
  return holder
end

-- Rail category button (retail GroupFinderGroupButtonTemplate look): bg plate 224x80 centered,
-- ring + circular icon at LEFT, name to the right. DOWNPORT: no MaskTexture on 3.3.5a (returns
-- nil on this client — see core/Portrait.lua) — the circular icon crop comes from
-- SetPortraitToTexture (native), appropriate HERE since this icon sits inside a round gold ring.
-- NOTE: reward-slot icons (Dungeons.lua) are square (UI-Quickslot2 border) and must NOT use this —
-- SetPortraitToTexture's circular crop there reads as a square-with-a-circle-cutout.
local function buildCategoryButton(parent, def)
  local b = CreateFrame("Button", FRAME_NAME .. def.key .. "Button", parent)
  b:SetSize(203, 60)
  -- Explicitly above the rail's own decorative textures (parent's level) — see buildRail's note
  -- on why creation-order alone isn't trusted to settle this stacking.
  b:SetFrameLevel(parent:GetFrameLevel() + 1)

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(railFile("m"))
  bg:SetSize(224, 80)
  bg:SetPoint("CENTER")
  b.bg = bg

  local ring = makeRing(b, 88, 84)
  if ring then ring:SetPoint("LEFT", b, "LEFT", -8, -1) end
  b.ring = ring

  local icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  -- Sized to fill the gold ring's inner opening (ring holder is 88x84). Was 58 (clear gap);
  -- 66 was still too small in-game, so the ring's hole is wider than assumed — 76 fills it.
  -- If the icon now spills over the gold band, dial this back toward ~70.
  icon:SetSize(76, 76)
  if ring then icon:SetPoint("CENTER", ring, "CENTER", 0, 0)
  else icon:SetPoint("LEFT", b, "LEFT", 4, -1) end
  -- DOWNPORT: was a single `and/or` ternary expression — if NE.tex.Local(def.icon) ever came back
  -- nil (registration timing, typo, etc.) the `or def.icon` fallback landed on the bare NUMBER
  -- 341547 itself (not a path string). SetTexture/SetPortraitToTexture can't read a raw FileDataID
  -- on 3.3.5a (see core/Texture.lua's own note on this exact caveat) — that silently blanked the
  -- Raids rail icon. Spelled out explicitly, with a guaranteed-visible fallback icon so a
  -- resolution miss degrades to SOME art rather than nothing.
  local iconPath
  if type(def.icon) == "number" then
    iconPath = NE.tex.Local and NE.tex.Local(def.icon)
  else
    iconPath = def.icon
  end
  if iconPath and SetPortraitToTexture then
    SetPortraitToTexture(icon, iconPath)          -- circular crop, native path
  elseif iconPath then
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0, 1, 0, 1)
  else
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")   -- fail-safe: never render blank
    icon:SetTexCoord(0, 1, 0, 1)
  end
  b.icon = icon

  local name = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  name:SetWidth(106); name:SetJustifyH("LEFT"); name:SetSpacing(2)
  name:SetPoint("LEFT", b, "LEFT", 88, 0)
  name:SetText(def.name)
  b.name = name

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(railFile("m"))
  hl:SetBlendMode("ADD"); hl:SetAlpha(0.8)
  hl:SetSize(224, 80); hl:SetPoint("CENTER")
  hl:SetTexCoord(unpack(BTN_TC.enabled))

  -- Locked categories explain themselves on hover (disabled Buttons still fire OnEnter on 3.3.5a,
  -- which is exactly how the native micro buttons show their "requires level N" text).
  b:SetScript("OnEnter", function(self)
    if categoryUnlocked(def) or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(def.name, 1, 1, 1)
    GameTooltip:AddLine(lockedMessage(def), 1, 0.1, 0.1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  b.def = def
  return b
end

local function setButtonState(b, state)
  local tc = BTN_TC[state] or BTN_TC.enabled
  b.bg:SetTexCoord(unpack(tc))
  local disabled = (state == "disabled")
  b.name:SetFontObject(disabled and "GameFontDisableLarge" or "GameFontNormalLarge")
  if SetDesaturation then
    SetDesaturation(b.icon, disabled)
    if b.ring and b.ring.quads then
      for _, q in ipairs(b.ring.quads) do SetDesaturation(q, disabled) end
    end
  end
  if disabled then b:Disable() else b:Enable() end
end

-- ---------------------------------------------------------------------------
-- Pane plumbing. Dungeons.lua / Raids.lua call L.RegisterPane(key, buildFn) at load; the
-- window builds each pane lazily on first select. Pane frames span the whole right side.
-- ---------------------------------------------------------------------------
L.paneBuilders = L.paneBuilders or {}
L.panes = L.panes or {}

function L.RegisterPane(key, buildFn)
  L.paneBuilders[key] = buildFn
end

-- Scrollbar for a pane's named FauxScrollFrame. Every list in this window goes through here
-- rather than calling BuildCustom directly, because of the strata bump: this window runs at
-- DIALOG (createWindow below) and BuildCustom parks its bar at HIGH, which is BELOW DIALOG --
-- so the bar and its arrows rendered behind the window's own background and were invisible on
-- every list here. Same trap, same fix as the Guild roster/event log and the Social channel
-- list. The level is taken off the scroll frame so the bar clears the rows it sits beside.
function L.BuildListBar(scroll, opts)
  if not (scroll and NE.scrollbar and NE.scrollbar.BuildCustom) then return end
  local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, opts)
  if not (ok and bar) then return end
  bar:SetFrameStrata("DIALOG")
  bar:SetFrameLevel((scroll:GetFrameLevel() or 1) + 10)
  if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
  if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
  return bar
end

-- Right-side pane host rect shared by both panes: everything right of the rail.
local function panesHost(f)
  if f.PaneHost then return f.PaneHost end
  local host = CreateFrame("Frame", nil, f)
  host:SetPoint("TOPLEFT",     f, "TOPLEFT",   226, -22)
  host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6,   4)
  f.PaneHost = host
  return host
end

local function showPane(f, key)
  for k, pane in pairs(L.panes) do
    if k ~= key and pane:IsShown() then pane:Hide() end
  end
  local pane = L.panes[key]
  if not pane then
    local build = L.paneBuilders[key]
    if not build then return end   -- pane file not loaded; rail button still selects
    pane = build(panesHost(f))
    L.panes[key] = pane
  end
  pane:Show()
  if pane.OnPaneShow then pane.OnPaneShow(pane) end
end

local function categoryDef(key)
  for _, def in ipairs(CATEGORIES) do
    if def.key == key then return def end
  end
end

-- The category the window should land on when nobody named one: the default, or the first
-- unlocked category if the default is still level-locked.
local function defaultCategory()
  local fallback
  for _, def in ipairs(CATEGORIES) do
    if categoryUnlocked(def) then
      if def.default then return def.key end
      fallback = fallback or def.key
    end
  end
  return fallback
end
L.DefaultCategory = defaultCategory

-- Repaint the rail after a level-up: a category that just unlocked stops rendering greyed.
function L.RefreshCategories()
  local f = L.frame
  if not f then return end
  for _, def in ipairs(CATEGORIES) do
    local b = f[def.key .. "Button"]
    if b then
      local state = "enabled"
      if not categoryUnlocked(def) then state = "disabled"
      elseif def.key == f.selectedCategory then state = "selected" end
      setButtonState(b, state)
    end
  end
end

function L.SelectCategory(key, userInitiated)
  local f = L.frame
  if not f then return end
  local def = categoryDef(key)
  if def and not categoryUnlocked(def) then return end   -- locked: rail button is disabled anyway
  f.selectedCategory = key
  L.RefreshCategories()
  showPane(f, key)
  if userInitiated and PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
end

local function buildCategoryButtons(f)
  local prev
  for i, def in ipairs(CATEGORIES) do
    local b = buildCategoryButton(f.Rail or f, def)
    if i == 1 then
      b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -110)
    else
      b:SetPoint("TOP", prev, "BOTTOM", 0, -36)
    end
    b:SetScript("OnClick", function() L.SelectCategory(def.key, true) end)
    f[def.key .. "Button"] = b
    prev = b
  end
end

-- ---------------------------------------------------------------------------
-- Construction + show/hide + registration.
-- ---------------------------------------------------------------------------
local function createWindow()
  if L.frame then return L.frame end

  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  f:SetSize(563, 428)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  L.frame = f

  buildChrome(f)
  buildRail(f)
  buildCategoryButtons(f)

  -- Eye state tracking (fires while hidden too — cheap, keeps the first paint honest).
  f:RegisterEvent("LFG_UPDATE")
  f:RegisterEvent("LFG_PROPOSAL_SHOW")
  f:RegisterEvent("LFG_PROPOSAL_FAILED")
  f:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
  f:RegisterEvent("LFG_ROLE_CHECK_SHOW")
  f:RegisterEvent("LFG_ROLE_CHECK_HIDE")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_LEVEL_UP")
  f:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LEVEL_UP" then
      local newLevel = tonumber(arg1)
      if newLevel and newLevel > levelHint then levelHint = newLevel end
      L.RefreshCategories()
    end
    if self.UpdateEye then self.UpdateEye() end
  end)

  f:HookScript("OnShow", function(self)
    if self.UpdateEye then self.UpdateEye() end
    L.RefreshCategories()
    -- Default-select on first open; re-assert the current pane's refresh on every open.
    if not self.selectedCategory then
      L.SelectCategory(defaultCategory() or CATEGORIES[1].key)
    else
      local pane = L.panes[self.selectedCategory]
      if pane and pane.OnPaneShow then pane.OnPaneShow(pane) end
    end
  end)

  if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
    NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
  end
  if NE.FrameUtil and NE.FrameUtil.EscClose then NE.FrameUtil.EscClose(FRAME_NAME) end

  -- Window scale: same seam as Social/Guild; PinPixelPerfect is the fallback.
  if NE.scale and NE.scale.Apply and NE.scale.SetFrame then
    pcall(NE.scale.SetFrame, "lfg", f)
    pcall(NE.scale.Apply, "lfg")
  elseif NE.panelchrome and NE.panelchrome.PinPixelPerfect then
    NE.panelchrome.PinPixelPerfect(f)
  end

  return f
end
L.Create = createWindow

-- Every open path (keybind, micro button, minimap eye, gossip, /commands, options panel) lands in
-- L.Show/L.Toggle, so the unlock check sits here. A locked request opens NOTHING — it doesn't fall
-- back to the other category — and says why in the error area, matching how the game refuses other
-- level-gated features. Returns true when the request was refused.
local function refuseIfLocked(category)
  local def = categoryDef(category or defaultCategory() or CATEGORIES[1].key)
  -- No unlocked category at all (defaultCategory() returned nil) → treat as the default one.
  def = def or categoryDef(CATEGORIES[1].key)
  if not def or categoryUnlocked(def) then return false end
  if UIErrorsFrame then UIErrorsFrame:AddMessage(lockedMessage(def), 1.0, 0.1, 0.1, 1.0) end
  return true
end
L.RefuseIfLocked = refuseIfLocked

function L.Show(category)
  if not isModuleEnabled() then return end
  if refuseIfLocked(category) then return end
  local f = createWindow()
  f:Show()
  if category then L.SelectCategory(category) end
end
function L.Hide() if L.frame then L.frame:Hide() end end
function L.Toggle(category)
  if not isModuleEnabled() then return end
  if refuseIfLocked(category) then
    -- Locked while the window happens to be open on the OTHER category: leave it as it is.
    return
  end
  local f = createWindow()
  if f:IsShown() then
    -- Toggling the OTHER category while open switches to it instead of closing (matches how
    -- the two native toggles behave as separate windows without stacking ours twice).
    if category and category ~= f.selectedCategory then
      L.SelectCategory(category)
    else
      L.Hide()
    end
  else
    L.Show(category)
  end
end

function L.Boot()
  if L.BootRedirects then L.BootRedirects() end
  if NE.RegisterPanel then
    NE.RegisterPanel({
      id = MODULE,
      title = LFG_TITLE or "Looking for Group",
      desc = "Unified retail-style Group Finder over the Dungeon Finder + Raid Browser.",
      frame = L.frame,
      openFn = function() L.Show() end,
      closeFn = L.Hide,
      order = 70,
    })
  end
end

-- Boot: install entry-point hooks and register options; build on explicit open.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
  L.Boot()
end)
