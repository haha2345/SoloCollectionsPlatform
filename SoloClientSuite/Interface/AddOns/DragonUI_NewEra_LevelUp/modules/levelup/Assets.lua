-- DragonUI_NewEra/modules/levelup/Assets.lua — art paths, atlas rects, and entry-type presets
-- for the Level Up Display.
--
-- Interface\LevelUp\LevelUpTex does NOT exist in 3.3.5a client data — it arrived with Cataclysm,
-- which is why the standalone 3.3.5 LevelUpDisplay addon ships its own copy. We do the same:
-- Textures/LevelUp/LevelUpTex.blp, referenced by path. DOWNPORT: NewEra points at the client's
-- copy (Era ships Blizzard_LevelUpDisplay_Cata.toc, so the file is there); we cannot.
--
-- THE BLP MUST BE DXT5. This is not a preference, and re-encoding it will visibly break the banner.
-- Almost all of this sheet's art is a soft radial shadow that lives entirely in the ALPHA channel:
--
--   DXT3 stores alpha as 4 explicit bits per pixel  -> 16 flat levels, no interpolation
--   DXT5 stores two 8-bit endpoints + 3-bit indices -> 256 interpolated levels
--
-- The copy shipped by the standalone 3.3.5 addon is DXT3, and the shadow renders as a stack of
-- concentric rings because a smooth falloff has nowhere to go in 16 steps. Same dimensions, same
-- file size (both formats are 1 byte/pixel), same artwork — only the alpha precision differs, and
-- it is the entire visual difference. Verified by decoding both: 16 distinct alpha levels vs 256,
-- with mean RGB deltas of 0-4/255 across every rect below. Ours is the DXT5 encoding.
--
-- The rects below are the Cata-era character-variant coords, byte-identical in NewEra's port and
-- in the standalone 3.3.5 addon — two independent transcriptions of the same source agreeing is
-- as close to verification as this art gets.
--
-- Registered as plain texcoord tables rather than through NE.tex.RegisterAtlas: this sheet is a
-- handful of fixed rects consumed only here, and Textures/Assets.lua's header records why atlas
-- geometry lives in coord tables on this client rather than in a C_Texture atlas DB.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.levelup = NE.levelup or {}
local M = NE.levelup

M.TEX = [[Interface\AddOns\DragonUI_NewEra\Textures\LevelUp\LevelUpTex]]
M.ICON_LFD = [[Interface\AddOns\DragonUI_NewEra\Textures\LevelUp\LevelUpIcon-LFD]]

-- Sub-icon badges stamped on the bottom-left of each unlock icon.
M.SUBICON_BOOK  = { 0.64257813, 0.72070313, 0.03710938, 0.11132813 }  -- learnable at a trainer
M.SUBICON_LOCK  = { 0.64257813, 0.70117188, 0.11523438, 0.18359375 }  -- feature unlocked
M.SUBICON_ARROW = { 0.72460938, 0.78320313, 0.03710938, 0.10351563 }  -- talent point

-- Panel chrome.
M.RECT = {
  dot     = { 0.64257813, 0.68359375, 0.18750000, 0.23046875 },
  goldBG  = { 0.56054688, 0.99609375, 0.24218750, 0.46679688 },
  gLine   = { 0.00195313, 0.81835938, 0.01953125, 0.03320313 },
  blackBg = { 0.00195313, 0.63867188, 0.03710938, 0.23828125 },  -- banner
  sideBg  = { 0.00195313, 0.55664063, 0.24218750, 0.82031250 },  -- side panel
}

-- Per-entry-type display defaults. An unlock supplies whatever it knows (a harvested trainer
-- service knows its own name/rank/icon; a curated feature knows all three) and inherits the rest.
--
-- `subText` is the green flavour line under the name. Routed through NE.L so a locale file can
-- translate it; harvested NAMES need no such treatment because the server already sent them
-- localized, which is half the point of harvesting them.
local L = NE.L
M.ENTRY_TYPES = {
  Spell   = { subText = L["Can be learned from a trainer"], subIcon = M.SUBICON_BOOK },
  Rank    = { subText = L["New rank available"],            subIcon = M.SUBICON_BOOK },
  Talent  = { subText = L["Talents"],                       subIcon = M.SUBICON_ARROW,
              icon = [[Interface\Icons\Ability_Marksmanship]] },
  Feature = { subText = L["New Feature"],                   subIcon = M.SUBICON_LOCK },
  Mount   = { subText = L["New Riding Skill"],              subIcon = M.SUBICON_LOCK },
  BG      = { subText = L["Battleground available"],        subIcon = M.SUBICON_LOCK },
  Dungeon = { subText = L["Dungeon available"],             subIcon = M.SUBICON_LOCK },
  Raid    = { subText = L["Raid available"],                subIcon = M.SUBICON_LOCK },
}

M.FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
