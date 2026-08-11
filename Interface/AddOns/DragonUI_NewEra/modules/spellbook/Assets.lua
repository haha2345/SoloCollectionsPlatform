-- DragonUI_NewEra/modules/spellbook/Assets.lua — Spellbook art registration (Agent ASSETS).
--
-- DOWNPORT: mirrors NewEra/Spellbook/Assets.lua, but
--   (1) paths point at OUR addon (Textures\Spellbook\...), and
--   (2) the atlas-name -> texcoord rects NewEra read from its generated NE_ATLAS are TRANSCRIBED
--       here into NE.tex.atlases via NE.tex.RegisterAtlases (architect decision: coords live in
--       NE.tex.atlases, NOT C_Texture.RegisterAtlas — see core/Texture.lua).
--
-- This file ships ONLY the Spellbook-specific sheets + atlases. The talents sheets (4556093 / mask
-- 4633068 / sheenmask 4731579) provide the passive-spell round-icon clip + node border/sheen reused
-- by the spellbook passive rows. Sheet 5684744 (questlog) is shipped here for its cog gear icon
-- (questlog-icon-setting); the addon's Tabs.lua references unrelated questlog-tab-side* atlases off a
-- different (not-yet-shipped) sheet, so there is no overlap.
--
-- Source coord rects transcribed from NewEra/Generated/AtlasData.lua.

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Spellbook\\"

-- ============================================================================
-- 1. fdid -> shipped BLP path  (NE.tex.RegisterLocal)
-- ============================================================================

NE.tex.RegisterLocal(5834697, P .. "5834697-spellbook-backgrounds.blp")       -- evergreen book panels
NE.tex.RegisterLocal(5506565, P .. "5506565-spellbook-items.blp")             -- item/frame sheet (14 atlases)
NE.tex.RegisterLocal(4200162, P .. "4200162-spellbook-skilllinetab.blp")      -- skill-line side tab
NE.tex.RegisterLocal(5684744, P .. "5684744-questlog.blp")                    -- cog gear icon sheet
NE.tex.RegisterLocal(4556093, P .. "4556093-talents.blp")                     -- talents sheet (node circle + sheen)

-- Masks (full-texcoord 0->1; circular/sheen alpha clips).
NE.tex.RegisterLocal(5899876, P .. "5899876-spellbook-spellicon-mask.blp")    -- spell-icon circular clip
NE.tex.RegisterLocal(5794906, P .. "5794906-spellbook-sheen-mask.blp")        -- icon-frame sheen mask
NE.tex.RegisterLocal(5922242, P .. "5922242-spellbook-petautocast-mask.blp")  -- pet-autocast mask
NE.tex.RegisterLocal(4633068, P .. "4633068-talents-circle-mask.blp")         -- passive round-icon clip
NE.tex.RegisterLocal(4731579, P .. "4731579-talents-circle-sheenmask.blp")    -- passive round-icon sheen clip

-- ============================================================================
-- 2. atlas-name -> texcoord rect  (NE.tex.RegisterAtlases)
--    Rects transcribed verbatim from NewEra/Generated/AtlasData.lua.
-- ============================================================================

-- Sheet 5834697 — evergreen book backgrounds.
NE.tex.RegisterAtlases({
  ["spellbook-background-evergreen-header"] = { file=5834697, left=0.000488, right=0.788574, top=0.000977, bottom=0.057617, width=1614, height=58 },
  ["spellbook-background-evergreen-left"]   = { file=5834697, left=0.446289, right=0.839844, top=0.059570, bottom=0.845703, width=806,  height=805 },
  ["spellbook-background-evergreen-right"]  = { file=5834697, left=0.000488, right=0.394531, top=0.059570, bottom=0.845703, width=807,  height=805 },
  ["spellbook-background-evergreen-ribbon"] = { file=5834697, left=0.395508, right=0.445312, top=0.059570, bottom=0.603516, width=102,  height=557 },
})

-- Sheet 4698972 (the RedButton sheet we already ship for the X close button) — Condense (↙ → one
-- page) and Expand (↗ → two pages) glyphs, for the page min/max toggle. Coords read off the BLP:
-- 7-col x 3-row grid of 36x38 cells (row1 normal / row2 disabled / row3 pressed), col1=Condense,
-- col3=Expand (col2=Exit, col4=Highlight match the already-registered redbutton-exit/-highlight).
NE.tex.RegisterAtlases({
  ["redbutton-expand-2x"]            = { file=4698972, left=0.300781, right=0.441406, top=0.007812, bottom=0.304688, width=36, height=38 },
  ["redbutton-expand-disabled-2x"]   = { file=4698972, left=0.300781, right=0.441406, top=0.320312, bottom=0.617188, width=36, height=38 },
  ["redbutton-expand-pressed-2x"]    = { file=4698972, left=0.300781, right=0.441406, top=0.632812, bottom=0.929688, width=36, height=38 },
  ["redbutton-condense-2x"]          = { file=4698972, left=0.003906, right=0.144531, top=0.007812, bottom=0.304688, width=36, height=38 },
  ["redbutton-condense-disabled-2x"] = { file=4698972, left=0.003906, right=0.144531, top=0.320312, bottom=0.617188, width=36, height=38 },
  ["redbutton-condense-pressed-2x"]  = { file=4698972, left=0.003906, right=0.144531, top=0.632812, bottom=0.929688, width=36, height=38 },
})

-- Sheet 5506565 — item/frame sheet (14 atlases).
NE.tex.RegisterAtlases({
  ["spellbook-corner-flipbook-evergreen"]            = { file=5506565, left=0.000977, right=0.586914, top=0.000977, bottom=0.303711, width=600, height=310 },
  ["spellbook-divider"]                              = { file=5506565, left=0.249023, right=0.890625, top=0.411133, bottom=0.421875, width=657, height=11 },
  ["spellbook-list-backplate"]                       = { file=5506565, left=0.000977, right=0.309570, top=0.305664, bottom=0.409180, width=316, height=106 },
  ["spellbook-item-backplate"]                       = { file=5506565, left=0.311523, right=0.561523, top=0.305664, bottom=0.368164, width=256, height=64 },
  ["spellbook-item-iconframe"]                       = { file=5506565, left=0.854492, right=0.989258, top=0.136719, bottom=0.264648, width=138, height=131 },
  ["spellbook-item-iconframe-hover"]                 = { file=5506565, left=0.000977, right=0.129883, top=0.666992, bottom=0.789062, width=132, height=125 },
  ["spellbook-item-iconframe-inactive"]              = { file=5506565, left=0.000977, right=0.133789, top=0.541016, bottom=0.665039, width=136, height=127 },
  ["spellbook-item-iconframe-passive-hover"]         = { file=5506565, left=0.136719, right=0.242188, top=0.636719, bottom=0.742188, width=108, height=108 },
  ["spellbook-item-iconframe-passive-inactive"]      = { file=5506565, left=0.136719, right=0.246094, top=0.525391, bottom=0.634766, width=112, height=112 },
  ["spellbook-item-needtrainer-iconframe-backplate"] = { file=5506565, left=0.000977, right=0.134766, top=0.411133, bottom=0.539062, width=137, height=131 },
  ["spellbook-item-needtrainer-passive-backplate"]   = { file=5506565, left=0.136719, right=0.247070, top=0.411133, bottom=0.523438, width=113, height=115 },
  ["spellbook-item-needtrainer-shadow"]              = { file=5506565, left=0.588867, right=0.852539, top=0.000977, bottom=0.264648, width=270, height=270 },
  ["spellbook-item-petautocast-corners"]             = { file=5506565, left=0.563477, right=0.651367, top=0.305664, bottom=0.393555, width=90,  height=90 },
  ["spellbook-item-unassigned-glow"]                 = { file=5506565, left=0.000977, right=0.125000, top=0.791016, bottom=0.915039, width=127, height=127 },
})

-- Sheet 4200162 — skill-line side tab.
NE.tex.RegisterAtlases({
  ["spellbook-skilllinetab"] = { file=4200162, left=0.015625, right=0.640625, top=0.015625, bottom=0.921875, width=40, height=58 },
})

-- Sheet 5684744 — cog gear icon (questlog setting button).
NE.tex.RegisterAtlases({
  ["questlog-icon-setting"] = { file=5684744, left=0.138672, right=0.167969, top=0.035156, bottom=0.066406, width=15, height=16 },
})

-- Sheet 4556093 — talents node circle border + swept sheen (reused by passive rows). The square
-- node frame (talents-node-square-gray, the dark socket the NewEra talents window uses for square
-- nodes) is the passive-spell border.
NE.tex.RegisterAtlases({
  ["talents-node-circle-gray"] = { file=4556093, left=0.106934, right=0.131348, top=0.555664, bottom=0.604492, width=40, height=40 },
  ["talents-node-square-gray"] = { file=4556093, left=0.490723, right=0.529785, top=0.799805, bottom=0.877930, width=40, height=40 },
  ["talents-sheen-node"]       = { file=4556093, left=0.490723, right=0.533203, top=0.170898, bottom=0.305664, width=87, height=138 },
})

-- Mask atlases (each full-texcoord 0->1).
NE.tex.RegisterAtlases({
  ["spellbook-item-spellicon-mask"]       = { file=5899876, left=0, right=1, top=0, bottom=1, width=64,  height=64 },
  ["spellbook-item-iconframe-sheen-mask"] = { file=5794906, left=0, right=1, top=0, bottom=1, width=128, height=128 },
  ["spellbook-item-petautocast-mask"]     = { file=5922242, left=0, right=1, top=0, bottom=1, width=64,  height=64 },
  ["talents-node-circle-mask"]            = { file=4633068, left=0, right=1, top=0, bottom=1, width=64,  height=64 },
  ["talents-node-circle-sheenmask"]       = { file=4731579, left=0, right=1, top=0, bottom=1, width=64,  height=64 },
})
