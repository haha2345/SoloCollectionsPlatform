-- DragonUI_NewEra/core/Scale.lua — per-window scaling for the standalone panels.
--
-- Three modes per window:
--   "ui"     follow the game's UI Scale slider (the frame inherits UIParent → SetScale(1)).
--   "none"   no scaling: pixel-perfect, independent of the UI Scale slider (PinPixelPerfect).
--   "custom" a fixed multiplier in [MIN, MAX].
-- Settings persist account-wide in NE.db.scale[window] = { mode, custom }. The DragonUI options
-- "New Era" tab exposes a dropdown (mode) + slider (custom) per window (see integration/Options.lua),
-- and changes apply IMMEDIATELY to the live frame via S.Apply.

local NE = DragonUI_NewEra
NE.scale = NE.scale or {}
local S = NE.scale

S.MIN, S.MAX = 0.5, 1.5

-- Per-window defaults preserve each window's prior look: spellbook/talents were a fixed 0.8; the
-- character panel had no custom scale (= followed the UI scale).
-- BUG FIX (owner report 2026-07-17: "the default scaling is massive" after social/guild switched
-- from PinPixelPerfect(f, 1.21) to NE.scale's plain "custom" mode SetScale(c)): those aren't the
-- same computation -- PinPixelPerfect normalizes against physical screen height and the parent's
-- effective scale first, so its 1.21 wasn't a literal 1.21x of anything on-screen, while "custom"
-- mode is a bare f:SetScale(c). 1.21 there rendered much bigger than intended. Owner steer: "make
-- it overall 30% smaller as the addon default, this should show as 1.0" -- 1.0 (plain, unscaled)
-- IS the addon default now; still fully user-adjustable from here same as every other window.
--
-- Windows added 2026-08-09 (auctionhouse / cooldownmanager / encounterjournal / combinedbag): each
-- default reproduces EXACTLY what that window did before it had a setting, so nobody's UI moves on
-- upgrade. The AH and combined bag never scaled themselves at all -> "ui" (a plain SetScale(1.0),
-- i.e. inherit UIParent). The Cooldown Manager window and the Adventure Guide both built themselves
-- with a hard-coded PinPixelPerfect(f, N) -> "none" (which IS PinPixelPerfect) with that same N
-- carried over as their BASE_SCALE below.
local DEFAULTS = {
  character        = { mode = "ui",     custom = 1.0 },
  spellbook        = { mode = "custom", custom = 0.8 },
  talents          = { mode = "custom", custom = 0.8 },
  social           = { mode = "custom", custom = 1.0 },
  guild            = { mode = "custom", custom = 1.0 },
  -- Explicit rather than left to S.Get's fallback: LFG already registered itself with SetFrame but
  -- had no row in the options list, so this is the first release where anyone can change it. "ui" is
  -- what the fallback was already giving it, so its shipped size is unchanged.
  lfg              = { mode = "ui",     custom = 1.0 },
  auctionhouse     = { mode = "ui",     custom = 1.0 },
  cooldownmanager  = { mode = "none",   custom = 1.0 },
  encounterjournal = { mode = "none",   custom = 1.0 },
  combinedbag      = { mode = "ui",     custom = 1.0 },
}

-- BUG FIX (owner report 2026-07-17, round two: "the default is still massive" after DEFAULTS.social/
-- guild's custom value dropped to 1.0). Setting custom=1.0 only made S.Apply's "custom" branch do a
-- literal f:SetScale(1.0) -- genuinely unscaled/native. Turns out social/guild's raw pixel footprint
-- (465x560, unlike the smaller character/spellbook/talents/professions windows) IS just "massive" at
-- native size on this owner's setup -- 1.0 was never the right target scale, it just happened to be
-- what "not 1.21" meant. Owner steer: "make it overall 30% smaller ... this should show as 1.0" --
-- i.e. the SLIDER should keep reading a clean "1.0" as its default/center point, but the ACTUAL
-- applied scale at that position needs to be 30% smaller than plain SetScale(1.0). A fixed per-window
-- baseline multiplier gets us both: the user-facing custom/mode values stay simple round numbers
-- (slider still shows 1.0, still ranges MIN..MAX same as every other window), while the real
-- on-screen scale is BASE_SCALE[window] * (whatever S.Get's mode/custom computation yields). Windows
-- not listed here default to 1.0 (no change from prior behavior).
--
-- The Cooldown Manager window and the Adventure Guide use BASE_SCALE for a different reason than
-- social/guild do: both were BUILT at a hard-coded oversize pin (the CDM's "owner's +30%" and the
-- Adventure Guide's 1.5), applied as a scale rather than by growing their layouts. Folding those
-- numbers in here keeps their out-of-the-box look identical AND keeps their sliders reading a clean
-- 1.0 at that look, so "1.0" means "how it shipped" on every window in the list.
local BASE_SCALE = {
  social           = 0.7,
  guild            = 0.7,
  cooldownmanager  = 1.3,   -- was SettingsPanel.lua's PANEL_SCALE
  encounterjournal = 1.5,   -- was EncounterJournal.lua's WINDOW_USER_SCALE
}

S._frames = S._frames or {}   -- window -> live Frame

local function store()
  local db = NE.db
  if not db then return nil end
  db.scale = db.scale or {}
  return db.scale
end

-- mode, custom for a window (falls back to defaults; never nil).
function S.Get(window)
  local d = DEFAULTS[window] or { mode = "ui", custom = 1.0 }
  local st = store()
  local s = st and st[window]
  if not s then return d.mode, d.custom end
  return s.mode or d.mode, s.custom or d.custom
end

-- Register a window's live frame so Apply/Set can rescale it on demand.
function S.SetFrame(window, frame)
  if window and frame then S._frames[window] = frame end
end

-- Leaving pixel-perfect mode has to also leave FrameUtil's re-pin registry, or the next UI-scale or
-- resolution change re-pins the frame and silently discards the mode the user just picked. Matters
-- for any window whose module pinned it at build time (the Cooldown Manager, the Adventure Guide)
-- as much as for one the user switched off "No scaling".
local function unpin(f)
  if NE.FrameUtil and NE.FrameUtil.Unpin then NE.FrameUtil.Unpin(f) end
end

-- Apply the current setting to the window's registered frame (no-op if not registered yet).
function S.Apply(window)
  local f = S._frames[window]
  if not f or not f.SetScale then return end
  local mode, custom = S.Get(window)
  local base = BASE_SCALE[window] or 1.0
  if mode == "none" then
    if NE.FrameUtil and NE.FrameUtil.PinPixelPerfect then
      NE.FrameUtil.PinPixelPerfect(f, base)   -- 1 logical px = 1 physical; ignores the UI scale slider
    else
      f:SetScale(base)
    end
  elseif mode == "custom" then
    local c = tonumber(custom) or 0.8
    if c < S.MIN then c = S.MIN elseif c > S.MAX then c = S.MAX end
    unpin(f)
    f:SetScale(c * base)
  else  -- "ui": inherit UIParent so the window tracks the game UI Scale slider
    unpin(f)
    f:SetScale(1.0 * base)
  end
end

-- Persist a new mode + apply live.
function S.SetMode(window, mode)
  if mode ~= "ui" and mode ~= "none" and mode ~= "custom" then return end
  local st = store()
  if st then st[window] = st[window] or {}; st[window].mode = mode end
  S.Apply(window)
end

-- Persist a new custom value (clamped) + apply live.
function S.SetCustom(window, value)
  local v = tonumber(value)
  if not v then return end
  if v < S.MIN then v = S.MIN elseif v > S.MAX then v = S.MAX end
  local st = store()
  if st then st[window] = st[window] or {}; st[window].custom = v end
  S.Apply(window)
end
