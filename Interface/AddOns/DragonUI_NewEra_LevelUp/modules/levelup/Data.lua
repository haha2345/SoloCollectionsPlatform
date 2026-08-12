-- DragonUI_NewEra/modules/levelup/Data.lua — the curated FALLBACK, and nothing more.
--
-- Harvest.lua learns spells, battlegrounds, dungeons, raids and talent-point steps from the live
-- server. What is left here is the short list of unlocks the 3.3.5a client exposes no API for at
-- all: you cannot ask it at what level glyph slots open. Those are Blizzlike constants, used only
-- until (and unless) the harvest observes something better, and Unlocks.lua always prefers observed
-- data over anything in this file.
--
-- DELIBERATELY NOT HERE — profession specializations. NewEra fires those at "the typical character
-- level when the spec becomes practical", which is a guess about a SKILL gate dressed up as a level
-- gate, and a private server that moves the skill requirement makes it simply wrong. Specialization
-- trainers are trainers, so where a server does gate them on level, Harvest.lua picks them up with
-- the server's own number. Inventing a level we cannot observe is the thing this rebuild exists to
-- stop doing.
--
-- DELIBERATELY NOT HERE — the class spell tables. That is the whole point; see Harvest.lua's header.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local M = NE.levelup
local L = NE.L

-- Level -> list of entries. `type` picks display defaults out of Assets.lua's ENTRY_TYPES.
-- Each entry may carry `check`, a predicate that must pass for the entry to be shown; it is how a
-- fallback withdraws itself on a server where the feature does not exist.
M.FALLBACK = {
  [15] = {
    { type = "Feature", text = L["Glyphs"],
      icon = [[Interface\Icons\INV_Inscription_Tradeskill01]] },
    { type = "Feature", text = LOOKING_FOR_DUNGEON or L["Dungeon Finder"],
      icon = M.ICON_LFD },
  },
  [20] = {
    -- Apprentice Riding moved 40 -> 20 in patch 3.2. Riding trainers are trainers, so a player who
    -- visits one gets the server's real number and this never renders.
    { type = "Mount", text = L["Apprentice Riding"],
      icon = [[Interface\Icons\Ability_Mount_RidingHorse]] },
  },
  [30] = {
    { type = "Feature", text = L["Glyph Slots"],
      icon = [[Interface\Icons\INV_Inscription_Tradeskill01]] },
  },
  [40] = {
    { type = "Mount", text = L["Journeyman Riding"],
      icon = [[Interface\Icons\Ability_Mount_RidingHorse]] },
    { type = "Feature", text = L["Dual Talent Specialization"],
      icon = [[Interface\Icons\INV_Misc_Coin_01]] },
  },
  [50] = {
    { type = "Feature", text = L["Glyph Slots"],
      icon = [[Interface\Icons\INV_Inscription_Tradeskill01]] },
  },
  [60] = {
    { type = "Mount", text = L["Expert Riding"],
      icon = [[Interface\Icons\Ability_Mount_Gryphon_01]] },
  },
  [68] = {
    { type = "Mount", text = L["Cold Weather Flying"],
      icon = [[Interface\Icons\Spell_Frost_ArcticWinds]] },
  },
  [70] = {
    { type = "Mount", text = L["Artisan Riding"],
      icon = [[Interface\Icons\Ability_Mount_Gryphon_01]] },
    { type = "Feature", text = L["Glyph Slots"],
      icon = [[Interface\Icons\INV_Inscription_Tradeskill01]] },
  },
  [80] = {
    { type = "Feature", text = L["Glyph Slots"],
      icon = [[Interface\Icons\INV_Inscription_Tradeskill01]] },
  },
}

-- Talent-point fallback. Harvest.TalentPointsGainedAt gives the server's real answer once it has
-- seen both sides of a level step; this covers the very first level-up on a fresh install, where
-- there is no previous total to diff against.
--
-- Blizzlike 3.3.5a: first point at 10, one per level thereafter. A server that grants a different
-- rate overrides this the moment it is observed.
M.TALENT_FIRST_LEVEL = 10

function M.FallbackTalentPoints(level)
  if not level or level < M.TALENT_FIRST_LEVEL then return nil end
  return 1
end
