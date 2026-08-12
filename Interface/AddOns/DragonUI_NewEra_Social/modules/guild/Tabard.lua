-- DragonUI_NewEra/modules/guild/Tabard.lua — the guild's tabard crest in the Roster tab's left
-- column (Window.lua's GuildColumn).
--
-- HOW IT RENDERS, and why it isn't the obvious way: this client does NOT ship the per-guild tabard
-- art. GetGuildTabardFileNames() answers with well-formed paths
-- ("Textures\GuildEmblems\Emblem_166_14_TU_U" and friends), but every one of those files is absent
-- — they render as the solid green missing-texture fill, while a control texture under the same
-- non-Interface root loads fine. The same goes for the FrameXML helpers that consume them
-- (SetLargeGuildTabardTextures et al), which draw nothing here.
--
-- What IS present is the shared EMBLEM SHEET, Interface\GuildFrame\GuildEmblemsLG_01: every
-- emblem on one 1024x1024 texture. So the crest is composed rather than blitted —
--
--   emblem      = one 64px cell of that sheet, picked by the guild's emblem index and tinted
--   background  = the column's existing GuildLogo-NoLogo shield, tinted to the guild's colour
--
-- The cell geometry and the index-extraction rule are transcribed from Blizzard's own
-- SetGuildTabardTextures (Era UIParent.lua), so an emblem lands in the same cell here as it would
-- on a client with the real art.
--
-- REJECTED ALTERNATIVE, recorded so it isn't retried: a DressUpModel/TabardModel wearing the Guild
-- Tabard item (5976) DOES show the true design, because the engine composites it. But the model is
-- the VIEWER'S OWN character, so the camera framing is per-race and per-gender — values that frame
-- a draenei's chest put a dwarf's head or a tauren's waist in the box. Flat art has no such problem.

local NE = DragonUI_NewEra
if not NE then return end

NE.guild = NE.guild or {}
local G = NE.guild

-- Sheet geometry, transcribed from Era's UIParent.lua SetLargeGuildTabardTextures: a 1024x1024
-- sheet of 64px icons in 16 columns, no inset. (Its sibling GuildEmblems_01 — 18/256 across 14
-- columns — is NOT in this client, so the large sheet is the only option.)
local EMBLEM_SHEET   = "Interface\\GuildFrame\\GuildEmblemsLG_01"
local EMBLEM_CELL    = 64 / 1024
local EMBLEM_COLUMNS = 16
local EMBLEM_OFFSET  = 0

-- THE REAL PALETTES, transcribed from the client DBCs (GuildColorBackground / GuildColorEmblem,
-- build 12.1.0.68824). These are the tables the colour indices in the tile filenames point at, and
-- they're baked in as data because 3.3.5a exposes no API for them: GetGuildLogoInfo — the function
-- Blizzard's own tinting path reads colours from — does not exist on this client.
--
-- CHANNEL ORDER: the DBC columns are Red, BLUE, Green, NOT RGB. They are reordered to RGB here, at
-- the point of transcription, so everything downstream is ordinary RGB. Sanity check if you ever
-- re-import these: background 38 must come out purple (155, 0, 166), not olive.
local BACKGROUND_COLORS = {
  [0]  = {255,32,136},  [1]  = {189,0,91},   [2]  = {158,0,54},   [3]  = {255,137,27},
  [4]  = {225,69,0},    [5]  = {177,0,46},   [6]  = {255,179,23}, [7]  = {246,135,0},
  [8]  = {174,75,0},    [9]  = {255,252,20}, [10] = {243,202,0},  [11] = {196,155,0},
  [12] = {255,255,20},  [13] = {216,221,0},  [14] = {166,172,0},  [15] = {227,246,24},
  [16] = {183,192,3},   [17] = {142,151,0},  [18] = {188,246,27}, [19] = {136,186,3},
  [20] = {88,128,0},    [21] = {30,255,104}, [22] = {4,195,71},   [23] = {0,130,15},
  [24] = {30,247,193},  [25] = {4,183,143},  [26] = {0,144,97},   [27] = {33,220,255},
  [28] = {0,157,197},   [29] = {0,99,145},   [30] = {77,142,218}, [31] = {44,106,174},
  [32] = {0,53,130},    [33] = {211,74,200}, [34] = {173,41,172}, [35] = {134,15,154},
  [36] = {255,56,250},  [37] = {201,0,195},  [38] = {155,0,166},  [39] = {255,31,191},
  [40] = {211,0,135},   [41] = {163,0,104},  [42] = {197,129,50}, [43] = {135,85,19},
  [44] = {79,35,0},     [45] = {35,35,35},   [46] = {100,100,100},[47] = {180,187,168},
  [48] = {215,221,203}, [49] = {255,255,255},[50] = {252,104,145},
}

local EMBLEM_COLORS = {
  [0]  = {103,0,33},   [1]  = {103,35,0},  [2]  = {103,69,0},  [3]  = {103,86,0},
  [4]  = {99,103,0},   [5]  = {81,103,0},  [6]  = {55,103,0},  [7]  = {0,103,31},
  [8]  = {0,103,87},   [9]  = {0,72,103},  [10] = {9,42,93},   [11] = {86,9,93},
  [12] = {93,9,79},    [13] = {84,55,10},  [14] = {177,184,177},
  [15] = {16,21,23},   [16] = {223,165,90},
}

-- (No border layer by design: the only border shape available is a single fixed trim — Blizzard's
-- own code never SetTextures the border, it just tints it — and drawing it added a heavy outline
-- without adding any real per-guild information.)

-- Vertex colour can only MULTIPLY, so a fully saturated tint drives the plate art's darker pixels
-- to near-black and flattens its shading into a solid block. Blending the palette colour toward
-- white keeps the hue while leaving the artwork's texture and highlights readable.
local TINT_LIFT = 0.3

-- Used only when an index falls outside the tables above — a neutral tone is honest, whereas
-- defaulting to entry 0 would silently paint a real colour that isn't this guild's.
local SHAPE_ONLY_TONE = { 0.25, 0.25, 0.28 }

-- `lift` blends toward white; 0 applies the palette colour exactly.
local function applyColor(tex, palette, idx, lift)
  local c = idx and palette[idx]
  if not c then return false end
  lift = lift or 0
  local function ch(v) return (v / 255) * (1 - lift) + lift end
  tex:SetVertexColor(ch(c[1]), ch(c[2]), ch(c[3]))
  return true
end

-- Emblem size in pixels, and a small upward nudge — the plate tapers to a point at the bottom, so
-- its usable area sits above centre and a geometrically centred emblem reads as sitting low.
local EMBLEM_SIZE_X     = 55
local EMBLEM_SIZE_Y     = 70
local EMBLEM_Y_OFFSET = 3

-- The player guild's tabard tile paths. Not used to DRAW anything (the files are absent) — they're
-- the carrier for the style/colour indices, which this client exposes nowhere else.
-- GetGuildTabardFileNames is the native name here; GetGuildTabardFiles is Era/retail's and is tried
-- second. Both pcall'd, and empty strings normalise to nil since the design streams in async.
function G.GetTabardTiles()
  local function nonEmpty(s) return (type(s) == "string" and s ~= "") and s or nil end
  -- Looked up by NAME, not by value: a {GetGuildTabardFileNames, GetGuildTabardFiles} literal
  -- would hole at index 1 on any client missing the first one, and ipairs would stop there.
  for _, name in ipairs({ "GetGuildTabardFileNames", "GetGuildTabardFiles" }) do
    local fn = _G and _G[name]
    if type(fn) == "function" then
      local ok, a, b, c, d, e, f = pcall(fn)
      a, b, c, d, e, f = nonEmpty(a), nonEmpty(b), nonEmpty(c), nonEmpty(d), nonEmpty(e), nonEmpty(f)
      if ok and a and c then return a, b, c, d, e, f end
    end
  end
end

-- emblemStyle, emblemColor, borderStyle, borderColor, backgroundStyle.
--
-- This client returns exactly six values from GetGuildTabardFileNames (verified with select('#'),
-- which — unlike a table constructor's length — can't be fooled by trailing nils), and GetTabardInfo
-- answers with nothing. So the indices are PARSED OUT OF THE FILENAMES: "Emblem_166_14_TU_U" is
-- emblem style 166 in colour 14, "Border_02_10" is border 2 colour 10, "Background_38" is 38.
function G.GetTabardDetails()
  local bgU, _, emU, _, bdU = G.GetTabardTiles()
  if not emU then return end
  local emblemStyle, emblemColor = emU:match("Emblem_(%d+)_(%d+)")
  if not emblemStyle then return end
  -- NOT `local a, b = bdU and bdU:match(...)`: an and/or expression is adjusted to ONE value, so the
  -- second capture would silently always be nil.
  local borderStyle, borderColor
  if bdU then borderStyle, borderColor = bdU:match("Border_(%d+)_(%d+)") end
  local backgroundStyle = bgU and bgU:match("Background_(%d+)")
  return tonumber(emblemStyle), tonumber(emblemColor),
         tonumber(borderStyle), tonumber(borderColor), tonumber(backgroundStyle)
end

-- Blizzard's nine colour components (0-255) plus the emblem filename. Preferred over the parsed
-- indices because these colours are EXACT rather than palette approximations.
local function guildLogoInfo()
  if not GetGuildLogoInfo then return end
  local ok, bgR, bgG, bgB, brR, brG, brB, emR, emG, emB, file = pcall(GetGuildLogoInfo, "player")
  if ok and file then return bgR, bgG, bgB, brR, brG, brB, emR, emG, emB, file end
end

-- Crop one emblem out of the sheet, exactly as SetGuildTabardTextures does it.
local function setEmblemCell(tex, index)
  tex:SetTexture(EMBLEM_SHEET)
  local x = math.fmod(index, EMBLEM_COLUMNS) * EMBLEM_CELL
  local y = math.floor(index / EMBLEM_COLUMNS) * EMBLEM_CELL
  tex:SetTexCoord(x + EMBLEM_OFFSET, x + EMBLEM_CELL - EMBLEM_OFFSET,
                  y + EMBLEM_OFFSET, y + EMBLEM_CELL - EMBLEM_OFFSET)
end

-- Plate size, matching the communities-guildbanner-background atlas rect.
local PLATE_W, PLATE_H = 74, 69

-- The crest owns BOTH its plate and its emblem, in ONE frame.
--
-- Earlier revisions tinted Window.lua's banner texture and drew the emblem over it from a separate
-- frame. That kept producing an emblem floating alone on bare panel, because the two live in
-- different draw hierarchies: the banner is a texture on the column (subject to the column's own
-- layering and to whether Window.lua's SetAtlas call happened to succeed), while the emblem is in a
-- child frame that always draws on top. Whenever the banner didn't render, the emblem still did.
--
-- Note GetTexture() cannot be used to test for that: SetTexture stores the path whether or not the
-- file loads, so it returns a truthy path for a texture that draws nothing. Owning both layers here
-- removes the question entirely — they share a frame, so they render together or not at all.
function G.MakeTabardCrest(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(PLATE_W, PLATE_H)

  f.Plate = f:CreateTexture(nil, "BACKGROUND")
  f.Plate:SetAllPoints(f)
  f.PlateOK = G.ApplyPlateAtlas(f)

  f.Emblem = f:CreateTexture(nil, "OVERLAY")
  f.Emblem:SetSize(EMBLEM_SIZE_X, EMBLEM_SIZE_Y)
  f.Emblem:SetPoint("CENTER", f, "CENTER", 0, EMBLEM_Y_OFFSET)
  f:Hide()
  return f
end

-- SetAtlas's RETURN is the only trustworthy signal that the art resolved — it reports false when the
-- atlas entry or its bundled BLP is unregistered. Retried on later passes if it fails.
function G.ApplyPlateAtlas(f)
  if not (f and f.Plate and NE.tex and NE.tex.SetAtlas) then return false end
  local ok, res = pcall(NE.tex.SetAtlas, f.Plate, "communities-guildbanner-background", false)
  return (ok and res) and true or false
end

-- Paint plate + emblem. Returns true only if the plate art actually resolved, so a crest can never
-- appear as a lone emblem, and the caller's retry loop keeps running until the art is there.
function G.FillTabardCrest(f)
  if not f then return false end
  if not f.PlateOK then
    f.PlateOK = G.ApplyPlateAtlas(f)
    if not f.PlateOK then f:Hide() return false end
  end
  local plate = f.Plate
  local bgR, bgG, bgB, _, _, _, emR, emG, emB, file = guildLogoInfo()

  -- Blizzard takes the FIRST run of digits in the filename as the cell index; failing that, the
  -- style parsed out of the tile paths.
  local style, emblemColorIdx, _, _, backgroundIdx = G.GetTabardDetails()
  local index = file and tonumber(file:match("(%d+)")) or style
  if not index then f:Hide() return false end

  setEmblemCell(f.Emblem, index)
  -- GetGuildLogoInfo's live RGB wins where it exists; otherwise the DBC palettes, keyed by the
  -- colour index parsed out of the filename.
  if emR then
    f.Emblem:SetVertexColor(emR / 255, emG / 255, emB / 255)
  elseif not applyColor(f.Emblem, EMBLEM_COLORS, emblemColorIdx) then
    f.Emblem:SetVertexColor(unpack(SHAPE_ONLY_TONE))
  end

  if plate then
    if bgR then plate:SetVertexColor(bgR / 255, bgG / 255, bgB / 255)
    elseif not applyColor(plate, BACKGROUND_COLORS, backgroundIdx, TINT_LIFT) then
      plate:SetVertexColor(1, 1, 1)
    end
  end

  f:Show()
  return true
end

-- Wire the crest into the GuildColumn (Window.lua's left panel, Roster tab only). While a design is
-- shown this REPLACES the column's own banner + NoLogo crest; both come back when there isn't one.
function G.SetupTabard(column)
  if not column or column._neTabard then return end
  column._neTabard = true

  local crest = G.MakeTabardCrest(column)
  -- Anchored to the COLUMN at the banner's own position, not to the banner itself: anchoring to a
  -- texture that may have failed to size means inheriting its collapse. This keeps the crest put
  -- regardless of what happened to Window.lua's banner.
  -- No explicit SetFrameLevel needed: a child frame's default level (parent+1) already draws above
  -- everything the parent owns directly, whatever draw layer those textures use.
  crest:SetPoint("TOP", column, "TOP", 0, -46)
  column.TabardCrest = crest

  -- Repaint whenever the window opens, with the retry budget reset. The tabard events can all have
  -- fired (and the retries been spent) before the art was ready, so opening the panel has to be able
  -- to start a fresh attempt rather than showing whatever the last failed pass left behind.
  if G.frame and G.frame.HookScript and not G.frame._neTabardShowHook then
    G.frame._neTabardShowHook = true
    G.frame:HookScript("OnShow", function()
      G._tabardTries = 0
      G.UpdateTabard()
    end)
  end

  G.EnsureTabardEvents()
  G.UpdateTabard()
end

-- Shared event frame, created once regardless of whether the (lazily-built) guild window exists
-- yet. GUILD_TABARD_UPDATE is pcall-registered: its presence on this build is unconfirmed.
function G.EnsureTabardEvents()
  if G._tabardEv then return end
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_GUILD_UPDATE")
  ev:RegisterEvent("GUILD_ROSTER_UPDATE")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  pcall(ev.RegisterEvent, ev, "GUILD_TABARD_UPDATE")
  ev:SetScript("OnEvent", function() G.UpdateTabard() end)
  G._tabardEv = ev
  if GuildRoster then pcall(GuildRoster) end   -- nudge the server; the design streams in async
end

function G.UpdateTabard()
  local f = G.frame
  local column = f and f.GuildColumn
  if not column then return end

  local inGuild = IsInGuild and IsInGuild()

  local filled = false
  if column.TabardCrest then
    if inGuild then filled = G.FillTabardCrest(column.TabardCrest)
    else column.TabardCrest:Hide() end
  end

  -- Our crest supplies its own plate, so the column's banner and NoLogo shield would only double up
  -- behind it. They come back untinted whenever there's no design to show.
  if column.Banner then column.Banner:SetShown(not filled) end
  if column.Crest then column.Crest:SetShown(not filled) end

  -- Retry while anything is still missing: the guild design streams in after login/guild-join, and
  -- the plate atlas may not have resolved yet. FillTabardCrest returns false for BOTH cases, so one
  -- condition now covers them — an earlier version returned true with no plate, which convinced this
  -- loop the work was done and left the crest permanently half-drawn.
  if inGuild and not filled and (G._tabardTries or 0) < 12 and C_Timer and C_Timer.After then
    G._tabardTries = (G._tabardTries or 0) + 1
    C_Timer.After(1.5, G.UpdateTabard)
  elseif filled then
    G._tabardTries = 0
  end
end
