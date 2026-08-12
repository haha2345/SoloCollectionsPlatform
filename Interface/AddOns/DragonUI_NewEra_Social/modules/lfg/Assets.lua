-- DragonUI_NewEra/modules/lfg/Assets.lua — Group Finder (LFG) art registration.
--
-- DOWNPORT of NewEra/LFGFrame/Assets.lua (the TBC-Classic Group Finder skin). Same two
-- differences from the reference as modules/guild/Assets.lua:
--   (1) BLP paths point at OUR addon (Textures\LFG\...), and
--   (2) the atlas-name → texcoord rects NewEra read from its generated NE_ATLAS global are
--       TRANSCRIBED here into NE.tex.atlases via NE.tex.RegisterAtlases (no atlas DB on 3.3.5a).
--
-- Shipped sheets (copied from ReferenceAddons/NewEra/Art/LFG/, retail build 12.0.5.67451 —
-- all BLP2, POT dimensions, raw-BGRA/DXT5 encodings; format-checked with the same header pass
-- as Textures/ASSETS.md §4):
--   4616456  groupfinder-eye sheet (2048x1024 raw BGRA) — the static eye-frame portrait + the
--            searching/initial flipbook strips that drive the animated "looking for players" eye.
--   5171843  ui-lfg-roleicon sheet (2048x2048 raw BGRA) — modern round tank/healer/dps/leader
--            medallions (+ disabled variants) for the role rows.
--   985877   groupfinder sheet (2048x1024 raw BGRA) — micro role/lock/leader/friend/check icons
--            used by the dungeon + raid-browse lists, and the dark groupfinder panel background.
--
-- NOT needed: a retail Raid Finder portrait icon. The Raids rail button (Window.lua CATEGORIES)
-- instead references the NATIVE 3.3.5a client texture directly (Interface\LFGFrame\UI-LFR-PORTRAIT,
-- the exact art LFRParentFrame's own $parentIcon uses per LFRFrame.xml) — no BLP copy needed.
-- NOT shipped here:
--   * bluemenu-main/vert/goldborder (593918/593919/593917) — the category-rail chrome — already
--     ship in Textures/Guild/ and are RegisterLocal'd by modules/guild/Assets.lua (loads before
--     us in the TOC). Registered once globally; we only read NE.tex.Local(fdid).
--   * bluemenu-ring (retail file 922034) — NOT in the reference's shipped art (Era's CASC serves
--     it natively; 3.3.5a can't read FDIDs). The rail buttons instead build their gold ring by
--     four-way mirroring the clean top-left quadrant of the DF PortraitMetal corner already
--     shipped in Textures/Common/2406979 — registered below as ne-lfg-ring-quadrant.

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\LFG\\"

-- ============================================================================
-- 1. fdid → shipped BLP path  (NE.tex.RegisterLocal)
-- ============================================================================

NE.tex.RegisterLocal(4616456, P .. "4616456-groupfinder-eye.blp")
NE.tex.RegisterLocal(5171843, P .. "5171843-roleicons.blp")
NE.tex.RegisterLocal(985877,  P .. "985877-groupfinder.blp")

-- ============================================================================
-- 2. atlas-name → texcoord rect  (NE.tex.RegisterAtlases)
-- Rects transcribed verbatim from NewEra/Generated/AtlasData.lua (12.0.5.67451).
-- ============================================================================

NE.tex.RegisterAtlases({
  -- Eye portrait + flipbooks (Window.lua's animator reads these sub-rects and advances
  -- texcoords inside them — retail QueueStatusFrame EyeTemplate, grid dims in Window.lua).
  ["groupfinder-eye-frame"]              = { file = 4616456, left = 0.971191, right = 0.996582, top = 0.000977, bottom = 0.051758, width = 52,  height = 52 },
  ["groupfinder-eye-flipbook-initial"]   = { file = 4616456, left = 0.237793, right = 0.474121, top = 0.305664, bottom = 0.520508, width = 484, height = 220 },
  ["groupfinder-eye-flipbook-searching"] = { file = 4616456, left = 0.000488, right = 0.236816, top = 0.305664, bottom = 0.649414, width = 484, height = 352 },

  -- Modern round role medallions (role rows on both panes). The -disabled variants are the
  -- greyed art retail shows for roles the class can't perform.
  ["ui-lfg-roleicon-tank"]              = { file = 5171843, left = 0.630371, right = 0.755371, top = 0.251465, bottom = 0.376465, width = 70, height = 70 },
  ["ui-lfg-roleicon-tank-disabled"]     = { file = 5171843, left = 0.756348, right = 0.881348, top = 0.251465, bottom = 0.376465, width = 70, height = 70 },
  ["ui-lfg-roleicon-healer"]            = { file = 5171843, left = 0.000488, right = 0.125488, top = 0.755371, bottom = 0.880371, width = 70, height = 70 },
  ["ui-lfg-roleicon-healer-disabled"]   = { file = 5171843, left = 0.126465, right = 0.251465, top = 0.251465, bottom = 0.376465, width = 70, height = 70 },
  ["ui-lfg-roleicon-dps"]               = { file = 5171843, left = 0.000488, right = 0.125488, top = 0.251465, bottom = 0.376465, width = 70, height = 70 },
  ["ui-lfg-roleicon-dps-disabled"]      = { file = 5171843, left = 0.000488, right = 0.125488, top = 0.377441, bottom = 0.502441, width = 70, height = 70 },
  ["ui-lfg-roleicon-leader"]            = { file = 5171843, left = 0.126465, right = 0.251465, top = 0.503418, bottom = 0.628418, width = 70, height = 70 },
  ["ui-lfg-roleicon-leader-disabled"]   = { file = 5171843, left = 0.126465, right = 0.251465, top = 0.629395, bottom = 0.754395, width = 70, height = 70 },

  -- Micro icons for list rows (16px-ish, groupfinder sheet).
  ["groupfinder-icon-role-micro-tank"]  = { file = 985877, left = 0.009277, right = 0.017090, top = 0.983398, bottom = 0.999023, width = 16, height = 16 },
  ["groupfinder-icon-role-micro-heal"]  = { file = 985877, left = 0.000488, right = 0.008301, top = 0.983398, bottom = 0.999023, width = 16, height = 16 },
  ["groupfinder-icon-role-micro-dps"]   = { file = 985877, left = 0.147949, right = 0.155762, top = 0.397461, bottom = 0.413086, width = 16, height = 16 },
  ["groupfinder-icon-lock"]             = { file = 985877, left = 0.161621, right = 0.192383, top = 0.577148, bottom = 0.651367, width = 28, height = 34 },
  ["groupfinder-icon-leader"]           = { file = 985877, left = 0.047852, right = 0.054688, top = 0.983398, bottom = 0.992188, width = 14, height = 9 },
  ["groupfinder-icon-friend"]           = { file = 985877, left = 0.147949, right = 0.157715, top = 0.352539, bottom = 0.371094, width = 20, height = 19 },
  ["groupfinder-icon-greencheckmark"]   = { file = 985877, left = 0.041504, right = 0.046875, top = 0.983398, bottom = 0.996094, width = 11, height = 13 },
  ["groupfinder-icon-redx"]             = { file = 985877, left = 0.034668, right = 0.040527, top = 0.983398, bottom = 0.995117, width = 12, height = 12 },
  ["groupfinder-icon-emptyslot"]        = { file = 985877, left = 0.979492, right = 0.993652, top = 0.348633, bottom = 0.376953, width = 29, height = 29 },

  -- Dark Group-Finder panel background (retail LFGList panel fill) — right-pane inset backdrop.
  ["groupfinder-background"]            = { file = 985877, left = 0.000488, right = 0.160645, top = 0.000977, bottom = 0.329102, width = 328, height = 336 },

  -- OUR OWN rect (not a retail atlas): the clean top-left quadrant of the DF PortraitMetal
  -- circular ring on the Sprint-0 corners sheet (Textures/Common/2406979). The retail
  -- bluemenu-ring's backing file isn't shipped anywhere (see header), so Window.lua draws the
  -- rail buttons' gold ring as 4 copies of this quadrant with mirrored texcoords.
  -- Region measured off the decoded sheet: px (14,166)-(81,230) of 512x512 → the ring arc only,
  -- clear of the frame-edge bars that exit the corner piece to the right and downward.
  ["ne-lfg-ring-quadrant"]              = { file = 2406979, left = 0.027344, right = 0.158203, top = 0.324219, bottom = 0.449219, width = 67, height = 64 },
})
