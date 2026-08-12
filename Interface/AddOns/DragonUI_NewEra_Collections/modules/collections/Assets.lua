-- DragonUI_NewEra/modules/collections/Assets.lua — art path constants for the Collections window.
--
-- These BLP/TGA files were copied verbatim from the EZCollections addon (the community retail-
-- Collections port) into Textures/Collections/ so this addon carries its own copy and does NOT
-- depend on EZCollections being installed. Unlike the shared chrome art (Textures/Assets.lua, which
-- routes fdid -> path through NE.tex for the nineslice coord tables), these are consumed by DIRECT
-- SetTexture(path) + SetTexCoord in the journal panes, so a plain path table is all that's needed.
--
-- ListButtons.blp is a 256-wide sheet; its three 208x46 row states share left 0.0039..0.8203:
--   ButtonBackground  top 0.00390625 .. 0.18359375
--   ButtonHighlight   top 0.19140625 .. 0.37109375
--   ButtonSelect      top 0.37890625 .. 0.55859375
-- MountJournal-BG is the right-hand model backdrop; its visible slice is left 0 .. 0.78515625.

local NE = DragonUI_NewEra
NE.collections = NE.collections or {}

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Collections\\"

NE.collections.tex = {
  listButtons     = P .. "ListButtons.blp",
  favoriteIcon    = P .. "FavoritesIcon.blp",
  iconFrame       = P .. "WhiteIconFrame.blp",
  searchIcon      = P .. "UI-Searchbox-Icon.blp",
  mountPortrait   = P .. "MountJournalPortrait.blp",
  petPortrait     = P .. "PetJournalPortrait.blp",
  modelBg         = P .. "MountJournal-BG.blp",
  noMountsBg      = P .. "MountJournal-NoMounts.blp",
  emptyIcon       = P .. "MountJournalEmptyIcon.blp",
  factionIcons    = P .. "MountJournalIcons.blp",   -- Horde/Alliance corner badges
  mountUpFavourites = P .. "MountUpFavourites.blp", -- Mounts tab's "Summon Random Favorite" icon (user-supplied art)
}

-- Sub-rects into ListButtons.blp (left/right/top/bottom), from the EZCollections template.
NE.collections.listCoords = {
  background = { 0.00390625, 0.8203125, 0.00390625, 0.18359375 },
  highlight  = { 0.00390625, 0.8203125, 0.19140625, 0.37109375 },
  select     = { 0.00390625, 0.8203125, 0.37890625, 0.55859375 },
}

-- MountJournalIcons.blp (128x64 DXT5) holds the two faction crests. Bounding boxes below were found
-- by decoding the alpha channel per-block (4x4px blocks) and measuring each crest's actual extent —
-- the crests are NOT the same width (~44px vs ~40px), so a naive even 50/50 split stretched both
-- into the wrong aspect ratio (the "stretched banner" look). The alpha-only decode couldn't tell
-- which SHAPE was which faction, and the left/right assignment guessed was backwards (confirmed
-- in-game: Alliance was showing on Horde mounts) — swapped below, same two crops.
--   Alliance: blocks x1-11, y0-11    -> px x4-48,   y0-48
--   Horde:    blocks x14-23, y0-11   -> px x56-96,  y0-48
NE.collections.factionCoords = {
  [0] = { 56/128, 96/128, 0, 48/64 },   -- Horde
  [1] = { 4/128,  48/128, 0, 48/64 },   -- Alliance
}
