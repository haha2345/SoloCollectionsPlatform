-- DOWNPORT: copied from NewEra (see ReferenceAddons); namespace localized to DragonUI_NewEra,
-- art paths re-pointed at DragonUI_NewEra\Textures\EncounterJournal. Content unchanged.
local NE = DragonUI_NewEra
-- Addon/EncounterJournal/Slices.lua — texcoord slice table for the legacy journal
-- chrome sheets, transcribed VERBATIM from retail Cata
-- Blizzard_EncounterJournal.xml:4-317 (build 12.0.5.67451). These are the virtual
-- <Texture> slices the journal carves out of the two master BLPs (shipped local via
-- Assets.lua). NOT modern atlas members — they're not in Generated/AtlasData.lua, so we
-- carry their texcoords ourselves.
--
--   fdid 522972 = UI-EncounterJournalTextures        (master sheet, 512x1024)
--   fdid 522973 = UI-EncounterJournalTextures_Tile   (h-tiled mid-pieces, 64x512)
--
-- Each entry: { fdid, w, h, l, r, t, b }. l/r/t/b are the LITERAL left/right/top/bottom
-- attribute values from the XML — several are intentionally flipped (top>bottom for a
-- vertical flip; left>right for a horizontal flip, e.g. RightPageHeader). Preserve as-is;
-- SetTexCoord(l, r, t, b) reproduces the flip.

local M, T = 522972, 522973

NE.ej = NE.ej or {}
NE.ej.SLICES = {
  -- _Tile sheet (522973) — horizontally tiled mid-pieces
  ["_FilterButtonUp-Mid"]          = { T, 64, 26, 0, 1, 0.00195313, 0.05273438 },
  ["_FilterButtonDown-Mid"]        = { T, 64, 26, 0, 1, 0.05664063, 0.10742188 },
  ["_FilterButtonHighlight-Mid"]   = { T, 64, 26, 0, 1, 0.11132813, 0.16210938 },
  ["_PaperHeader-UnSelectDown-Mid"]= { T, 64, 29, 0, 1, 0.28320313, 0.33984375 },
  ["_PaperHeader-UnSelectUp-Mid"]  = { T, 64, 29, 0, 1, 0.34375000, 0.40039063 },
  ["_PaperHeader-SelectDown-Mid"]  = { T, 64, 29, 0, 1, 0.40429688, 0.46093750 },
  ["_PaperHeader-Highlight-Mid"]   = { T, 64, 29, 0, 1, 0.46484375, 0.52148438 },
  ["_DungeonGridTab-MidHighlight"] = { T, 64, 36, 0, 1, 0.59570313, 0.52539063 },
  ["_DungeonGridTab-MidSelect"]    = { T, 64, 36, 0, 1, 0.66992188, 0.59960938 },
  ["_DungeonGridTab-Mid"]          = { T, 64, 36, 0, 1, 0.74414063, 0.67382813 },

  -- Master sheet (522972)
  ["UI-EJ-AbilityIconBorder"]            = { M, 20, 20, 0.00195313, 0.04101563, 0.00097656, 0.02050781 },
  -- description parchment box + bottom border (SharedUIPanelTemplates.xml; same master sheet)
  ["UI-PaperOverlay-AbilityTextBG"]         = { M, 256, 80, 0.00195313, 0.50195313, 0.02246094, 0.10058594 },
  ["UI-PaperOverlay-AbilityTextBottomBorder"] = { M, 243, 9, 0.04492188, 0.51953125, 0.00097656, 0.00976563 },
  ["UI-EJ-DungeonGridTab-SelectedGlow"]  = { M, 64, 15, 0.52343750, 0.64843750, 0.01562500, 0.00097656 },
  ["UI-EJ-DungeonGridTab-Shadow"]        = { M, 128, 15, 0.65234375, 0.90234375, 0.00097656, 0.01562500 },
  ["UI-EJ-ReturnToDefault"]              = { M, 21, 20, 0.90625000, 0.94726563, 0.00097656, 0.02050781 },
  ["UI-EJ-BossModelButton"]              = { M, 64, 61, 0.50585938, 0.63085938, 0.02246094, 0.08203125 },
  ["UI-EJ-CreatureHeaderFrameSm-bg"]     = { M, 45, 44, 0.63476563, 0.72265625, 0.02246094, 0.06542969 },
  ["UI-EJ-FilterButtonDown"]             = { M, 26, 26, 0.63476563, 0.68554688, 0.06738281, 0.09277344 },
  ["UI-EJ-CreatureHeaderFrameSm"]        = { M, 45, 44, 0.72656250, 0.81445313, 0.02246094, 0.06542969 },
  ["UI-EJ-FilterButtonHighlight"]        = { M, 26, 26, 0.72656250, 0.77734375, 0.06738281, 0.09277344 },
  ["UI-EJ-DungeonGridTab-Left"]          = { M, 12, 36, 0.81835938, 0.84179688, 0.05761719, 0.02246094 },
  ["UI-EJ-DungeonGridTab-LeftHighlight"] = { M, 12, 36, 0.81835938, 0.84179688, 0.09472656, 0.05957031 },
  ["UI-EJ-DungeonGridTab-LeftSelect"]    = { M, 12, 36, 0.84570313, 0.86914063, 0.05761719, 0.02246094 },
  ["UI-EJ-DungeonGridTab-Right"]         = { M, 12, 36, 0.84570313, 0.86914063, 0.09472656, 0.05957031 },
  ["UI-EJ-DungeonGridTab-RightHighlight"]= { M, 12, 36, 0.87304688, 0.89648438, 0.05761719, 0.02246094 },
  ["UI-EJ-DungeonGridTab-RightSelect"]   = { M, 12, 36, 0.87304688, 0.89648438, 0.09472656, 0.05957031 },
  ["UI-EJ-FilterButtonSelect"]           = { M, 26, 26, 0.90039063, 0.95117188, 0.02246094, 0.04785156 },
  ["UI-EJ-SearchIconFrameSm"]            = { M, 22, 22, 0.95507813, 0.99804688, 0.02246094, 0.04394531 },
  ["UI-EJ-FilterButtonUp"]               = { M, 26, 26, 0.90039063, 0.95117188, 0.04980469, 0.07519531 },
  ["UI-EJ-BossButton-Down"]              = { M, 325, 55, 0.00195313, 0.63671875, 0.10253906, 0.15625000 },
  ["UI-EJ-MapButtonSm-Down"]             = { M, 50, 50, 0.64062500, 0.73828125, 0.10253906, 0.15136719 },
  ["UI-EJ-MapButtonSm-Highlight"]        = { M, 50, 50, 0.74218750, 0.83984375, 0.10253906, 0.15136719 },
  ["UI-EJ-MapButtonSm-Selection"]        = { M, 50, 50, 0.84375000, 0.94140625, 0.10253906, 0.15136719 },
  ["UI-EJ-BossButton-Highlight"]         = { M, 325, 55, 0.00195313, 0.63671875, 0.15820313, 0.21191406 },
  ["UI-EJ-MapButtonSm-Up"]               = { M, 50, 50, 0.64062500, 0.73828125, 0.15820313, 0.20703125 },
  ["UI-EJ-PaperHeader-Highlight-Left"]   = { M, 64, 29, 0.74218750, 0.86718750, 0.15820313, 0.18652344 },
  ["UI-EJ-PaperHeader-Highlight-Right"]  = { M, 64, 29, 0.87109375, 0.99609375, 0.15820313, 0.18652344 },
  ["UI-EJ-BossButton-Up"]                = { M, 325, 55, 0.00195313, 0.63671875, 0.21386719, 0.26757813 },
  ["UI-EJ-PaperHeader-SelectDown-Left"]  = { M, 64, 29, 0.64062500, 0.76562500, 0.21386719, 0.24218750 },
  ["UI-EJ-PaperHeader-SelectDown-Right"] = { M, 64, 29, 0.76953125, 0.89453125, 0.21386719, 0.24218750 },
  ["UI-EJ-BossNameShadow"]               = { M, 395, 63, 0.00195313, 0.77343750, 0.26953125, 0.33105469 },
  ["UI-EJ-MapButtonLg-Down"]             = { M, 62, 61, 0.77734375, 0.89843750, 0.26953125, 0.32910156 },
  ["UI-EJ-Tab-BossIcon-Selected"]        = { M, 48, 43, 0.90234375, 0.99609375, 0.26953125, 0.31152344 },
  ["UI-EJ-DungeonButton-Down"]           = { M, 174, 96, 0.00195313, 0.34179688, 0.33300781, 0.42675781 },
  ["UI-EJ-DungeonButton-Highlight"]      = { M, 174, 96, 0.34570313, 0.68554688, 0.33300781, 0.42675781 },
  ["UI-EJ-MapButtonLg-Highlight"]        = { M, 62, 61, 0.68945313, 0.81054688, 0.33300781, 0.39257813 },
  ["UI-EJ-MapButtonLg-Select"]           = { M, 62, 61, 0.81445313, 0.93554688, 0.33300781, 0.39257813 },
  ["UI-EJ-DungeonButton-Up"]             = { M, 174, 96, 0.00195313, 0.34179688, 0.42871094, 0.52246094 },
  ["UI-EJ-DungeonNameBg"]                = { M, 256, 64, 0.34570313, 0.84570313, 0.42871094, 0.49121094 },
  ["UI-EJ-PaperHeader-SelectUp-Right"]   = { M, 64, 29, 0.34570313, 0.47070313, 0.49316406, 0.52148438 },
  ["UI-EJ-PaperHeader-UnSelectDown-Left"]= { M, 64, 29, 0.47460938, 0.59960938, 0.49316406, 0.52148438 },
  ["UI-EJ-PaperHeader-UnSelectDown-Right"]={ M, 64, 29, 0.60351563, 0.72851563, 0.49316406, 0.52148438 },
  ["UI-EJ-MapButtonLg-Up"]               = { M, 62, 61, 0.84960938, 0.97070313, 0.42871094, 0.48828125 },
  ["UI-EJ-PaperHeader-UnSelectUp-Left"]  = { M, 64, 29, 0.84960938, 0.97460938, 0.49023438, 0.51855469 },
  ["UI-EJ-DungeonLootFrame"]             = { M, 369, 64, 0.00195313, 0.72265625, 0.52441406, 0.58691406 },
  ["UI-EJ-PaperHeader-UnSelectUp-Right"] = { M, 64, 29, 0.72656250, 0.85156250, 0.52441406, 0.55273438 },
  ["UI-EJ-Tab-BossIcon-UnSelected"]      = { M, 48, 43, 0.85546875, 0.94921875, 0.52441406, 0.56640625 },
  ["UI-EJ-FilterBar"]                    = { M, 320, 28, 0.00195313, 0.62695313, 0.58886719, 0.61621094 },
  ["UI-EJ-SearchBarHighlightSm"]         = { M, 128, 27, 0.63085938, 0.88085938, 0.58886719, 0.61523438 },
  ["UI-EJ-LootFrame"]                    = { M, 321, 45, 0.00195313, 0.62890625, 0.61816406, 0.66210938 },
  ["UI-EJ-Tab-LootIcon-Selected"]        = { M, 48, 43, 0.63281250, 0.72656250, 0.61816406, 0.66015625 },
  ["UI-EJ-Tab-LootIcon-UnSelected"]      = { M, 48, 43, 0.73046875, 0.82421875, 0.61816406, 0.66015625 },
  ["UI-EJ-LoreTextCover-Bottom"]         = { M, 386, 29, 0.00195313, 0.75585938, 0.66406250, 0.69238281 },
  ["UI-EJ-LoreTextCover-Top"]            = { M, 386, 32, 0.00195313, 0.75585938, 0.69433594, 0.72558594 },
  ["UI-EJ-MainTextCover-Bottom"]         = { M, 386, 43, 0.00195313, 0.75585938, 0.72753906, 0.76953125 },
  ["UI-EJ-MainTextCover-Top"]            = { M, 386, 13, 0.00195313, 0.75585938, 0.77148438, 0.78417969 },
  ["UI-EJ-MoreTextBelowHighlight"]       = { M, 259, 17, 0.00195313, 0.50781250, 0.78613281, 0.80273438 },
  ["UI-EJ-SearchBarHighlightLg"]         = { M, 256, 47, 0.00195313, 0.50195313, 0.80468750, 0.85058594 },
  ["UI-EJ-ShowMapBG"]                    = { M, 171, 50, 0.00195313, 0.33593750, 0.85253906, 0.90136719 },
  ["UI-EJ-Tab-Highlight"]                = { M, 63, 57, 0.00195313, 0.12500000, 0.90332031, 0.95898438 },
  ["UI-EJ-Tab-Selected"]                 = { M, 63, 57, 0.12890625, 0.25195313, 0.90332031, 0.95898438 },
  ["UI-EJ-Tab-UnSelected"]               = { M, 63, 57, 0.25585938, 0.37890625, 0.90332031, 0.95898438 },
  ["UI-EJ-Tab-ModelIcon-Selected"]       = { M, 48, 43, 0.80468750, 0.90039063, 0.66210938, 0.70507813 },
  ["UI-EJ-Tab-ModelIcon-UnSelected"]     = { M, 48, 43, 0.90234375, 1.00000000, 0.66210938, 0.70507813 },
  ["UI-EJ-LeftPageHeader"]               = { M, 386, 39, 0.00000000, 0.75585938, 0.95996094, 1.00000000 },
  ["UI-EJ-RightPageHeader"]              = { M, 386, 39, 0.75585938, 0.00000000, 0.95996094, 1.00000000 },
  ["UI-EJ-Tab-AbilitiesIcon-Selected"]   = { M, 48, 43, 0.80664063, 0.89843750, 0.70703125, 0.74804688 },
  ["UI-EJ-Tab-AbilitiesIcon-UnSelected"] = { M, 48, 43, 0.90429688, 0.99609375, 0.70703125, 0.74804688 },
  ["UI-EJ-Header-Overview"]              = { M, 327, 30, 0.35937500, 0.99609375, 0.85253906, 0.88085938 },
}

-- Apply a slice to a Texture: bind the LOCAL sheet BLP (same-FDID-≠-same-art) + texcoords,
-- optionally size to the slice's native dimensions.
function NE.ej.ApplySlice(tex, name, setSize)
  local s = NE.ej.SLICES[name]
  if not s then return false end
  tex:SetTexture(NE.tex.localFiles[s[1]] or s[1])
  tex:SetTexCoord(s[4], s[5], s[6], s[7])
  if setSize then tex:SetSize(s[2], s[3]) end
  return true
end
