-- DragonUI_NewEra/modules/encounterjournal/Assets.lua — Encounter Journal chrome BLPs.
--
-- DOWNPORT of NewEra/EncounterJournal/Assets.lua. Registers the journal's fixed-texture
-- chrome sheets + per-instance splash art (fdid → local BLP path) via NE.tex.RegisterLocal.
-- Art copied from the NewEra reference addon into Textures\EncounterJournal (see
-- Textures\ASSETS.md). The per-instance Backdrops/Lore/Bosses/BossesGen sets are registered
-- by the DATA files' own tails (Data.lua / DataTBC.lua / PortraitOverrides.lua), exactly as
-- NewEra does — this file carries only the shared chrome + the Era-side button splashes.
--
-- DOWNPORT notes vs the 1.15 source:
--   * NE.ej.Preload: Era streams addon BLPs lazily and needed a warm-up holder; 3.3.5a loads
--     local BLPs synchronously at SetTexture, so Preload is a NO-OP kept only because the
--     generated data files call it (guarded).
--   * NE.flavor: the NewEra Era/TBC client switch. This 3.3.5a server runs WotLK with full
--     Classic + TBC content, so we take the TBC code paths (expansion-tier dropdown, TBC
--     heroic difficulty dropdown) — flavor is pinned to "tbc".
--   * 7494373 (modern icons_16x16_* flag sheet) is shipped but its named-atlas rects are NOT
--     registered here (NewEra got them from Generated/AtlasData.lua, which we don't carry);
--     EncounterPage's SetFlagIcon falls back to the legacy UI-EJ-Icons 8x2 grid (521749).

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}
NE.flavor = NE.flavor or "tbc"          -- WotLK server: show Classic + Burning Crusade tiers
function NE.ej.Preload() end            -- DOWNPORT: no-op (no lazy CASC streaming on 3.3.5a)

local A = {
  { 522972, "522972-ui-encounterjournaltextures.blp" },     -- master chrome sheet (512x1024)
  { 522973, "522973-ui-encounterjournaltextures-tile.blp" },-- h-tiled mid-pieces
  { 527422, "527422-ui-ej-lorebg-default.blp" },            -- generic lore-panel background
  { 527690, "527690-ui-ej-bossmodelpaperframe.blp" },       -- model-tab paper frame
  { 605327, "605327-ui-ej-classic.blp" },                   -- Classic-tier instance-select bg
  { 605326, "605326-ui-ej-burningcrusade.blp" },            -- TBC-tier instance-select bg
  { 605329, "605329-ui-ej-wrathofthelichking.blp" },        -- Wrath-tier instance-select bg
  { 521749, "521749-ui-ej-icons.blp" },                     -- legacy section flag icons (8x2)
  { 521753, "521753-ui-ej-portraiticon.blp" },              -- window portrait (journal book)
  { 521743, "521743-ui-ej-background-default.blp" },        -- model-scene backdrop default
  { 521744, "521744-ui-ej-boss-default.blp" },              -- generic boss-button plate
  { 521750, "521750-ui-ej-journalbg.blp" },                 -- journal page background
  { 521748, "521748-ui-ej-heroictexticon.blp" },            -- heroic difficulty badge
}

-- Era-side instance grid-button splashes (JournalInstance.ButtonFileDataID). The TBC set is
-- registered by DataTBC.lua's tail.
local BTN = {
  { 608196,  "608196-ejbutton-blackrock-depths.blp" },
  { 608197,  "608197-ejbutton-lower-blackrock-spire.blp" },
  { 608202,  "608202-ejbutton-gnomeregan.blp" },
  { 608209,  "608209-ejbutton-maraudon.blp" },
  { 608225,  "608225-ejbutton-uldaman.blp" },
  { 608229,  "608229-ejbutton-wailing-caverns.blp" },
  { 608230,  "608230-ejbutton-zulfarrak.blp" },
  { 1396586, "1396586-ejbutton-molten-core.blp" },
  { 1396580, "1396580-ejbutton-blackwing-lair.blp" },
  { 1396591, "1396591-ejbutton-ruins-of-ahnqiraj.blp" },
  { 1396593, "1396593-ejbutton-temple-of-ahnqiraj.blp" },
  { 608211, "608211-ejbutton-ragefire-chasm.blp" },
  { 522352, "522352-ejbutton-deadmines.blp" },
  { 522358, "522358-ejbutton-shadowfang-keep.blp" },
  { 608195, "608195-ejbutton-blackfathom-deeps.blp" },
  { 608213, "608213-ejbutton-razorfen-kraul.blp" },
  { 608212, "608212-ejbutton-razorfen-downs.blp" },
  { 608223, "608223-ejbutton-stockade.blp" },
  { 608217, "608217-ejbutton-sunken-temple.blp" },
  { 608200, "608200-ejbutton-dire-maul.blp" },
  { 608216, "608216-ejbutton-stratholme.blp" },
  { 608215, "608215-ejbutton-scholomance.blp" },
  { 608214, "608214-ejbutton-scarlet-monastery.blp" },
  { 1396587, "1396587-ejbutton-naxxramas.blp" },
  { 1396589, "1396589-ejbutton-onyxias-lair.blp" },
  { 522364,  "522364-ejbutton-zulgurub.blp" },
}

local _P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\EncounterJournal\\"
for _, e in ipairs(A)   do NE.tex.RegisterLocal(e[1], _P .. e[2]) end
for _, e in ipairs(BTN) do NE.tex.RegisterLocal(e[1], _P .. e[2]) end

-- Era-side per-instance model-tab backdrops (JournalInstance.BGFileDataID); TBC set in DataTBC.
for _, fd in ipairs({ 608157, 608158, 608163, 608170, 608186, 608190, 608191,
                      1396454, 1396460, 1396465, 1396467, 1396461, 1396463, 522348,
                      522336, 522342, 608156, 608161, 608172, 608173, 608174, 608175,
                      608176, 608177, 608178, 608184 }) do
  NE.tex.RegisterLocal(fd, _P .. "Backdrops\\" .. fd .. ".blp")
end

-- Era-side per-instance lore-panel splashes (JournalInstance.LoreFileDataID); TBC set in DataTBC.
-- (Data.lua's tail also registers these — harmless double-registration, kept for parity.)
for _, fd in ipairs({ 526404, 526410, 526416, 608234, 608235, 608236, 608239, 608241,
                      608248, 608250, 608251, 608252, 608253, 608254, 608255, 608256,
                      608262, 608264, 608267, 608313, 1396499, 1396505, 1396506, 1396508,
                      1396510, 1396512 }) do
  NE.tex.RegisterLocal(fd, _P .. "Lore\\" .. fd .. ".blp")
end
