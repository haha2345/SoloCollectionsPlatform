-- DragonUI_NewEra/modules/professions/Assets.lua — texture + atlas registration for the
-- profession crafting window (NE_ProfessionsCraftingFrame).
--
-- DOWNPORT: mirrors NewEra/Professions/Assets.lua but re-points paths to OUR addon and
-- registers atlas coords into NE.tex.atlases via NE.tex.RegisterAtlases instead of the
-- retail-only NE_ATLAS global. All texcoords are transcribed verbatim from
-- NewEra_ReferenceFolder/NewEra/Generated/AtlasData.lua (build 12.0.5.67451).
--
-- Load order: must come before Window.lua / RecipeList.lua / Crafting.lua so that every
-- NE.tex.SetAtlas("Professions-…") call resolves to a shipped local sheet.

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Professions\\"

-- ============================================================================
-- 1. fdid → shipped BLP path  (NE.tex.RegisterLocal)
-- ============================================================================

-- 4417031 — MAIN professions chrome sheet (2048×2048). Hosts almost all window chrome:
--   Professions-background-summarylist, Professions-recipe-header-left/middle/right,
--   Professions_Recipe_Active/Hover, Professions-skillbar-bg/-frame,
--   professions-slot-bg/-frame, Professions-Icon-Skill-Low/Medium/High,
--   AND the DefaultBlue skillbar flipbook (skillbar_fill_flipbook_defaultblue).
NE.tex.RegisterLocal(4417031, P .. "4417031-professions-chrome-sheet.blp")

-- Right-panel recipe parchment backgrounds. Generic fallback + per-profession themed sheets.
NE.tex.RegisterLocal(4659666, P .. "4659666-professions-recipe-background.blp")           -- generic
NE.tex.RegisterLocal(4625450, P .. "4625450-professions-recipe-background-alchemy.blp")
NE.tex.RegisterLocal(4625448, P .. "4625448-professions-recipe-background-blacksmithing.blp")
NE.tex.RegisterLocal(4723320, P .. "4723320-professions-recipe-background-enchanting.blp")
NE.tex.RegisterLocal(4722478, P .. "4722478-professions-recipe-background-engineering.blp")
NE.tex.RegisterLocal(4723159, P .. "4723159-professions-recipe-background-herbalism.blp")
NE.tex.RegisterLocal(4723154, P .. "4723154-professions-recipe-background-leatherworking.blp")
NE.tex.RegisterLocal(4723189, P .. "4723189-professions-recipe-background-mining.blp")
NE.tex.RegisterLocal(4723308, P .. "4723308-professions-recipe-background-skinning.blp")
NE.tex.RegisterLocal(4627497, P .. "4627497-professions-recipe-background-tailoring.blp")
NE.tex.RegisterLocal(4671747, P .. "4671747-professions-recipe-background-cooking.blp")
NE.tex.RegisterLocal(4723316, P .. "4723316-professions-recipe-background-fishing.blp")
NE.tex.RegisterLocal(4723119, P .. "4723119-professions-background-inscription.blp")
NE.tex.RegisterLocal(4723112, P .. "4723112-professions-recipe-background-jewelcrafting.blp")

-- 4626279 — RankBar skill-progress mask (the WHOLE BLP is the mask; reveals the fill by
-- width-clamping). Retail uses AddMaskTexture; we guard for 3.3.5a nil-return below.
NE.tex.RegisterLocal(4626279, P .. "4626279-professions-skillbar-mask.blp")

-- Modern DF profession portrait icons (round, used for the portrait area of the window).
-- These are standalone FDIDs, NOT crops from the chrome sheet.
-- CASC maps these FDIDs to the old vanilla art on 3.3.5a, so we MUST use the shipped local copy
-- (accessed via NE.tex.localFiles[fdid]) — never the raw FDID number as a texture path.
NE.tex.RegisterLocal(4620669, P .. "4620669-ui-profession-alchemy.blp")
NE.tex.RegisterLocal(4620670, P .. "4620670-ui-profession-blacksmithing.blp")
NE.tex.RegisterLocal(4620671, P .. "4620671-ui-profession-cooking.blp")
NE.tex.RegisterLocal(4620672, P .. "4620672-ui-profession-enchanting.blp")
NE.tex.RegisterLocal(4620673, P .. "4620673-ui-profession-engineering.blp")
NE.tex.RegisterLocal(4620674, P .. "4620674-ui-profession-fishing.blp")
NE.tex.RegisterLocal(4620675, P .. "4620675-ui-profession-herbalism.blp")
NE.tex.RegisterLocal(4620676, P .. "4620676-ui-profession-inscription.blp")
NE.tex.RegisterLocal(4620677, P .. "4620677-ui-profession-jewelcrafting.blp")   -- WotLK forward-compat
NE.tex.RegisterLocal(4620678, P .. "4620678-ui-profession-leatherworking.blp")
NE.tex.RegisterLocal(4620679, P .. "4620679-ui-profession-mining.blp")
NE.tex.RegisterLocal(4620680, P .. "4620680-ui-profession-skinning.blp")
NE.tex.RegisterLocal(4620681, P .. "4620681-ui-profession-tailoring.blp")

-- Themed RankBar fill flipbooks (Skillbar_Fill_Flipbook_<Profession>). Each is a 2048² sprite
-- sheet (~60 frames, 30 rows × 2 cols). Professions without a themed sheet use DefaultBlue
-- (already on the chrome sheet 4417031 above). Gathering profs (Herbalism/Mining/Fishing)
-- have no crafting window in WotLK so no fill is needed; First Aid reuses Skinning's art.
NE.tex.RegisterLocal(4696956, P .. "4696956-skillbar-fill-flipbook-alchemy.blp")
NE.tex.RegisterLocal(4683154, P .. "4683154-skillbar-fill-flipbook-blacksmithing.blp")
NE.tex.RegisterLocal(4872261, P .. "4872261-skillbar-fill-flipbook-cooking.blp")
NE.tex.RegisterLocal(4693223, P .. "4693223-skillbar-fill-flipbook-enchanting.blp")
NE.tex.RegisterLocal(4881558, P .. "4881558-skillbar-fill-flipbook-engineering.blp")
NE.tex.RegisterLocal(4872264, P .. "4872264-skillbar-fill-flipbook-inscription.blp")
NE.tex.RegisterLocal(4693237, P .. "4693237-skillbar-fill-flipbook-jewelcrafting.blp")
NE.tex.RegisterLocal(4696971, P .. "4696971-skillbar-fill-flipbook-leatherworking.blp")
NE.tex.RegisterLocal(4693230, P .. "4693230-skillbar-fill-flipbook-tailoring.blp")
NE.tex.RegisterLocal(4872267, P .. "4872267-skillbar-fill-flipbook-skinning.blp")   -- also reused for First Aid

-- 5094125 — Minimized-view right-panel background (compact 404px mode, future use).
NE.tex.RegisterLocal(5094125, P .. "5094125-professions-minimizedview-background.blp")

-- 3046538 — AuctionHouse chrome sheet. Hosts the favorite star (on/off) AND the white item-icon
-- border used by the output icon. Both were referenced but never shipped/registered → invisible.
NE.tex.RegisterLocal(3046538, P .. "3046538-auctionhouse-chrome.blp")

-- ============================================================================
-- 2. Atlas-name → texcoord rect  (NE.tex.RegisterAtlases)
--    All coords transcribed verbatim from
--    NewEra_ReferenceFolder/NewEra/Generated/AtlasData.lua (build 12.0.5.67451).
-- ============================================================================

-- Sheet 4417031 — main chrome: recipe list background, header tiles, row overlays.
NE.tex.RegisterAtlases({
  ["professions-background-summarylist"] = { file=4417031, left=0.000488, right=0.131348, top=0.257812, bottom=0.537109, width=268,  height=572 },

  ["professions-recipe-header-left"]     = { file=4417031, left=0.223633, right=0.230469, top=0.550293, bottom=0.562988, width=14,   height=26  },
  ["professions-recipe-header-middle"]   = { file=4417031, left=0.228027, right=0.228516, top=0.348633, bottom=0.361328, width=1,    height=26  },
  ["professions-recipe-header-right"]    = { file=4417031, left=0.223633, right=0.230469, top=0.563965, bottom=0.576660, width=14,   height=26  },
  ["professions-recipe-header-collapse"] = { file=4417031, left=0.218262, right=0.229004, top=0.465332, bottom=0.473145, width=11,   height=8   },
  ["professions-recipe-header-expand"]   = { file=4417031, left=0.217773, right=0.228516, top=0.475098, bottom=0.482910, width=11,   height=8   },

  -- Row selection / hover overlays (note: names use underscore, not hyphen, per AtlasData).
  ["professions_recipe_active"]          = { file=4417031, left=0.703125, right=0.833496, top=0.138672, bottom=0.147949, width=267,  height=19  },
  ["professions_recipe_hover"]           = { file=4417031, left=0.841309, right=0.992188, top=0.136230, bottom=0.146484, width=309,  height=21  },

  -- Skill-up chevron icons (shown LEFT of a craftable recipe row).
  ["professions-icon-skill-high"]        = { file=4417031, left=0.223633, right=0.229980, top=0.587891, bottom=0.595215, width=13,   height=15  },
  ["professions-icon-skill-medium"]      = { file=4417031, left=0.223633, right=0.229980, top=0.604492, bottom=0.611816, width=13,   height=15  },
  ["professions-icon-skill-low"]         = { file=4417031, left=0.223633, right=0.229980, top=0.596191, bottom=0.603516, width=13,   height=15  },

  -- RankBar (skill-progress bar) art.
  ["professions-skillbar-bg"]            = { file=4417031, left=0.664062, right=0.884277, top=0.193359, bottom=0.207520, width=451,  height=29  },
  ["professions-skillbar-frame"]         = { file=4417031, left=0.233398, right=0.453613, top=0.286621, bottom=0.300781, width=451,  height=29  },

  -- DefaultBlue flipbook fill (on the chrome sheet; 2 frames only → rendered static).
  ["skillbar_fill_flipbook_defaultblue"] = { file=4417031, left=0.233398, right=0.663086, top=0.193359, bottom=0.209473, width=880,  height=33  },

  -- Reagent slot art.
  ["professions-slot-bg"]                = { file=4417031, left=0.195801, right=0.216797, top=0.362305, bottom=0.383301, width=43,   height=43  },
  ["professions-slot-frame"]             = { file=4417031, left=0.197754, right=0.217285, top=0.802246, bottom=0.821777, width=40,   height=40  },
  ["professions-slot-frame-blue"]        = { file=4417031, left=0.197754, right=0.217285, top=0.822754, bottom=0.842285, width=40,   height=40  },
  ["professions-slot-frame-epic"]        = { file=4417031, left=0.197754, right=0.217285, top=0.843262, bottom=0.862793, width=40,   height=40  },
  ["professions-slot-frame-green"]       = { file=4417031, left=0.107422, right=0.126953, top=0.968262, bottom=0.987793, width=40,   height=40  },
  ["professions-slot-frame-white"]       = { file=4417031, left=0.158691, right=0.178223, top=0.890625, bottom=0.910156, width=40,   height=40  },

  -- Detail/quality pane 3-slice (charcoal fill, rounded corners, ornate top/bottom flourishes).
  -- Used as the background for the repurposed "Item Details" box — the same dark panel retail
  -- uses for its Crafting Details window. Top/bottom are fixed caps; middle (1px) tiles/stretches.
  ["professions-qualitypane-bg-top"]     = { file=4417031, left=0.233398, right=0.360352, top=0.210449, bottom=0.259277, width=260,  height=100 },
  ["professions-qualitypane-bg-middle"]  = { file=4417031, left=0.399414, right=0.526367, top=0.161621, bottom=0.162109, width=260,  height=1   },
  ["professions-qualitypane-bg-bottom"]  = { file=4417031, left=0.361328, right=0.488281, top=0.210449, bottom=0.258789, width=260,  height=99  },
})

-- Sheet 3046538 — AuctionHouse chrome: favorite star (on/off) + white item-icon border.
NE.tex.RegisterAtlases({
  ["auctionhouse-icon-favorite"]        = { file=3046538, left=0.940430, right=0.979492, top=0.047852, bottom=0.083008, width=40,  height=36  },
  ["auctionhouse-icon-favorite-off"]    = { file=3046538, left=0.940430, right=0.979492, top=0.084961, bottom=0.120117, width=40,  height=36  },
  ["auctionhouse-itemicon-border-white"]= { file=3046538, left=0.135742, right=0.268555, top=0.698242, bottom=0.831055, width=136, height=136 },
})

-- Sheet 4626279 — skillbar mask (full-BLP, alpha shape applied via width-clamp or AddMaskTexture).
NE.tex.RegisterAtlases({
  ["professions-skillbar-mask"] = { file=4626279, left=0, right=1, top=0, bottom=1, width=512, height=512 },
})

-- Themed skillbar flipbooks (each its own BLP, 2-col sprite grid, ~30+ rows = 60+ frames).
-- Rows/cols derived from atlas height / 34px per row (cell height from retail probe).
NE.tex.RegisterAtlases({
  ["skillbar_fill_flipbook_alchemy"]        = { file=4696956, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
  ["skillbar_fill_flipbook_blacksmithing"]  = { file=4683154, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
  ["skillbar_fill_flipbook_cooking"]        = { file=4872261, left=0.000488, right=0.836426, top=0.000977, bottom=0.997070, width=1712, height=1020 },
  ["skillbar_fill_flipbook_enchanting"]     = { file=4693223, left=0.000488, right=0.836426, top=0.000488, bottom=0.614746, width=1712, height=1258 },
  ["skillbar_fill_flipbook_engineering"]    = { file=4881558, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
  ["skillbar_fill_flipbook_inscription"]    = { file=4872264, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
  ["skillbar_fill_flipbook_jewelcrafting"]  = { file=4693237, left=0.000488, right=0.836426, top=0.000488, bottom=0.365723, width=1712, height=748 },
  ["skillbar_fill_flipbook_leatherworking"] = { file=4696971, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
  ["skillbar_fill_flipbook_tailoring"]      = { file=4693230, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
  ["skillbar_fill_flipbook_skinning"]       = { file=4872267, left=0.000488, right=0.836426, top=0.000488, bottom=0.498535, width=1712, height=1020 },
})

-- Per-profession recipe parchment backgrounds (right-panel theming). All share the same
-- texcoord crop; different BLPs give each profession its unique art theme.
NE.tex.RegisterAtlases({
  ["professions-recipe-background"]              = { file=4659666, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-alchemy"]      = { file=4625450, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-blacksmithing"]= { file=4625448, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-cooking"]      = { file=4671747, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-enchanting"]   = { file=4723320, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-engineering"]  = { file=4722478, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-fishing"]      = { file=4723316, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-herbalism"]    = { file=4723159, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-inscription"]  = { file=4723119, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-jewelcrafting"] = { file=4723112, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-leatherworking"]={ file=4723154, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-mining"]       = { file=4723189, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-skinning"]     = { file=4723308, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
  ["professions-recipe-background-tailoring"]    = { file=4627497, left=0.000977, right=0.660156, top=0.000977, bottom=0.536133, width=675, height=548 },
})

-- Minimized-view background (compact single-panel mode, future use).
NE.tex.RegisterAtlases({
  ["professions-minimizedview-background"] = { file=5094125, left=0.001953, right=0.787109, top=0.000977, bottom=0.576172, width=402, height=589 },
})
