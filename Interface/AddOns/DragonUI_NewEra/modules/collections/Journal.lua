-- DragonUI_NewEra/modules/collections/Journal.lua — the shared Mounts / Pet-Journal pane.
--
-- ONE factory (createJournal) builds a self-contained journal for a given companion kind and is
-- instantiated twice by Window.lua: a "MOUNT" journal (the Mounts tab) and a "CRITTER" journal (the
-- Pet Journal tab). Both share the exact retail layout — a scrollable icon+name list on the left, a
-- rotatable 3D model + info panel on the right, a search box, a filter dropdown, a favourites star, a
-- "Summon Random Favourite" button, and a Mount/Summon action button — differing only in which
-- GetCompanionInfo filter they read and which source-info table (Data.lua) they join against.
--
-- DATA (3.3.5a pre-Cata Companions API, every call pcall-guarded so a slightly different server
-- implementation degrades to an empty list rather than erroring):
--   GetNumCompanions("MOUNT"/"CRITTER")
--   GetCompanionInfo(kind, index) -> creatureID, creatureName, creatureSpellID, icon, issummoned
--   CallCompanion(kind, index) / DismissCompanion(kind)
--   PlayerModel:SetCreature(creatureID)
-- The description / "Vendor: … Zone: … Cost: …" source text the API does NOT provide comes from
-- NE.collections.GetInfo(kind, spellID) (Data.lua).
--
-- Widgets are parented into per-journal container frames sitting inside the shared insets/bands
-- (Window.lua), so Journal:Show()/:Hide() toggles the whole group when the tab changes.

local NE = DragonUI_NewEra
NE.collections = NE.collections or {}
local C = NE.collections

local ROW_H       = 44
local SEARCH_H    = 20
local ICON_SIZE   = 38

local function log(msg) if C._log then C._log(msg) end end

-- ---------------------------------------------------------------------------
-- Favourites — per-character, persisted in NE.db.companionFavorites (same schema + key format the
-- retired Character-panel Companions.lua used, so existing favourites carry straight over). Keyed by
-- kind+creatureID (creatureID is the only stable identity across sessions; slot order is not).
-- ---------------------------------------------------------------------------
local function favTable()
  if not (NE.db and NE.CharKey) then return nil end
  NE.db.companionFavorites = NE.db.companionFavorites or {}
  local key = NE.CharKey()
  NE.db.companionFavorites[key] = NE.db.companionFavorites[key] or {}
  return NE.db.companionFavorites[key]
end
local function favKey(kind, data)
  if not (data and data.creatureID) then return nil end
  return kind .. ":" .. tostring(data.creatureID)
end
local function isFavorite(kind, data)
  local t, k = favTable(), favKey(kind, data)
  return t ~= nil and k ~= nil and t[k] == true
end
local function setFavorite(kind, data, fav)
  local t, k = favTable(), favKey(kind, data)
  if not (t and k) then return end
  if fav then t[k] = true else t[k] = nil end
end

-- ---------------------------------------------------------------------------
-- Mount category / usability — MODULE-level (kind-parameterized, not closed over a Journal
-- instance) so the draggable action-bar macro below can call them even in a session where the
-- Collections window was never opened (no Journal object exists yet).
-- ---------------------------------------------------------------------------

-- Ground/Flying/Aquatic CATEGORY, ported EXACTLY from EZCollections' own MatchesFilter (the
-- if/elseif chain below, not the 0x2 "can go underwater" USABILITY bit isUsableNowFor uses below —
-- those are two different concepts that share the same `type` field, and conflating them was the
-- earlier bug: type bit 0x2 is set on almost every ordinary ground mount (it just means "doesn't
-- get dismounted while wading"), so treating it as the Aquatic CATEGORY misclassified nearly
-- everything as aquatic too, and unchecking Ground alone never hid anything (the Aquatic branch of
-- the OR still passed). The real Aquatic category comes from FLAGS bit 0x10 instead.
local function mountCategoryFor(kind, spellID)
  if kind ~= "MOUNT" then return true, false, false end
  local ty, flags = 0, 0
  if NE.collections.GetMountType then ty, flags = NE.collections.GetMountType(spellID) end
  if bit.band(ty, 0x4) ~= 0 then
    return true, true, false    -- scripted ground/flying hybrid: counts as BOTH
  elseif bit.band(flags, 0x10) ~= 0 then
    return false, false, true   -- Aquatic
  elseif bit.band(ty, 0x1) ~= 0 then
    return false, true, false   -- Flying-only
  else
    return true, false, false   -- Ground (the default — catches type 0, 2, etc.)
  end
end

-- Location-aware "can I summon this right now" (ported from EZCollections' IsMountUsable). Pets
-- have no location restriction. Falls back to true when there's no type data.
local function isUsableNowFor(kind, data)
  if kind ~= "MOUNT" then return true end
  if IsOutdoors and not IsOutdoors() then return false end
  local ty = NE.collections.GetMountType and (NE.collections.GetMountType(data.spellID)) or 0
  if bit.band(ty, 0x1) ~= 0 and IsFlyableArea and not IsFlyableArea() then return false end  -- flying-only, can't fly here
  if bit.band(ty, 0x2) == 0 and IsSwimming and IsSwimming() then return false end             -- non-aquatic while swimming
  return true
end

-- Priority tier for the random-favourite PICK itself (ported from EZCollections' own
-- SelectRandomFavoriteMount) — separate from isUsableNowFor above, which only answers "can this be
-- summoned at all right now." Without this, a flying-capable area with BOTH a favourited flying
-- mount and a favourited ground mount treated them as equally likely picks, so the random summon
-- button landed on the ground mount roughly half the time even though flying was available (the
-- reported bug). 1 = most preferred, 3 = least. Ground mounts default to 2; a flying/hybrid mount is
-- bumped to 1 whenever flight is actually usable right now (not swimming, area is flyable);
-- swimming favours aquatic-tagged mounts (flags 0x10/0x20) to priority 1 instead.
local function mountPriorityFor(data, isSwimmingNow, isFlyableNow)
  local ty, flags = 0, 0
  if NE.collections.GetMountType then ty, flags = NE.collections.GetMountType(data.spellID) end
  local priority = 2
  if bit.band(ty, 0x5) ~= 0 and not isSwimmingNow and isFlyableNow then priority = 1 end
  if bit.band(flags, 0x10) ~= 0 and isSwimmingNow then priority = 1 end
  if bit.band(flags, 0x20) ~= 0 and isSwimmingNow then priority = 1 end
  return priority
end

-- Splits an already-usable MOUNT pool into 3 priority tiers and returns the highest-priority
-- non-empty tier. Pets (and any empty/degenerate pool) pass through unchanged.
local function prioritizedPool(kind, pool)
  if kind ~= "MOUNT" or #pool <= 1 then return pool end
  local okSw, swimming = pcall(IsSwimming)
  swimming = okSw and swimming and true or false
  local okFly, flyable = pcall(IsFlyableArea)
  flyable = okFly and flyable and true or false
  local tiers = { {}, {}, {} }
  for _, d in ipairs(pool) do
    local p = mountPriorityFor(d, swimming, flyable)
    table.insert(tiers[p], d)
  end
  return (#tiers[1] > 0 and tiers[1]) or (#tiers[2] > 0 and tiers[2]) or tiers[3]
end

-- ---------------------------------------------------------------------------
-- NE.collections.SummonRandomFavorite(kind) — the canonical "summon a random usable favourite"
-- action. Re-enumerates GetCompanionInfo FRESH each call rather than depending on a Journal's
-- cached J.all, specifically so this also works when called from the draggable action-bar macro
-- below (which can fire in a session where the Collections window was never built). Preference
-- order mirrors retail: usable favourite -> any favourite -> any usable -> anything.
-- ---------------------------------------------------------------------------
function NE.collections.SummonRandomFavorite(kind)
  kind = (kind == "CRITTER") and "CRITTER" or "MOUNT"

  -- Retail's own random-favourite summon toggles OFF first: C_MountJournal.SummonByID(0) checks
  -- IsMounted() and calls Dismount() instead of picking a new mount; C_PetJournal.SummonRandomPet
  -- likewise dismisses whatever's already out. Without this, clicking again while already
  -- mounted/summoned just re-calls CallCompanion on top of an active companion, which the server
  -- rejects with a "you are already mounted" error instead of swapping or dismounting.
  if kind == "MOUNT" then
    if IsMounted and IsMounted() then
      pcall(Dismount)
      return
    end
  else
    local okC, count = pcall(GetNumCompanions, "CRITTER")
    count = (okC and count) or 0
    for i = 1, count do
      local okI, _, _, _, _, issummoned = pcall(GetCompanionInfo, "CRITTER", i)
      if okI and issummoned then
        pcall(DismissCompanion, "CRITTER")
        return
      end
    end
  end

  local all = {}
  local ok, count = pcall(GetNumCompanions, kind)
  count = (ok and count) or 0
  for i = 1, count do
    local okI, creatureID, name, spellID, icon, issummoned = pcall(GetCompanionInfo, kind, i)
    if okI and name then
      all[#all + 1] = { index = i, creatureID = creatureID, name = name, spellID = spellID, icon = icon, issummoned = issummoned }
    end
  end
  if #all == 0 then return end

  local t = favTable()
  local usableFav, fav, usable = {}, {}, {}
  for _, d in ipairs(all) do
    local k = favKey(kind, d)
    local isFav = t and k and t[k] == true
    local isUse = isUsableNowFor(kind, d)
    if isUse then usable[#usable + 1] = d end
    if isFav then
      fav[#fav + 1] = d
      if isUse then usableFav[#usableFav + 1] = d end
    end
  end
  local pool = (#usableFav > 0 and usableFav) or (#fav > 0 and fav) or (#usable > 0 and usable) or all
  -- Favourite status still trumps priority tier (a favourited ground mount beats a non-favourited
  -- flying one) — priority only breaks ties WITHIN whichever pool got picked above.
  pool = prioritizedPool(kind, pool)
  local pick = pool[math.random(#pool)]
  pcall(CallCompanion, kind, pick.index)
end

-- ---------------------------------------------------------------------------
-- "Summon Random Favourite" action-bar entry. 3.3.5a action bar slots only accept SECURE primitives
-- (spell/item/macro) — "random favourite" isn't a real spell, so (exactly like retail's own
-- C_MountJournal.Pickup(0), which calls PickupMacro under the hood) we back it with a REAL MACRO.
-- The macro body just re-enters SummonRandomFavorite via /script, so favourites/usability are
-- always read live at cast time.
--
-- We do NOT try to make the in-window button itself draggable onto a bar: a plain non-secure
-- Button doesn't hand off a macro pickup on OnDragStart the way retail's real (secure-templated)
-- MountJournal button does — confirmed this doesn't work here, and EZCollections has the same
-- limitation. Instead, ensureFavoriteMacro is called lazily on the button's first click (NOT eagerly
-- at build time — that used to create the macro just from opening the Collections window, before
-- the player ever asked for it), and the button's tooltip tells the player to drag it off their own
-- Macros window afterward.
--
-- CAVEAT: CreateMacro's icon argument is a NUMERIC INDEX into the macro icon picker's list, NOT a
-- texture path/name — it CANNOT take our custom MountUpFavourites.blp art. That custom texture is
-- used on the in-window button (see buildTop below); the macro's own icon falls back to a stock
-- riding/beast-call icon, resolved to its index below (findMacroIconIndex).
-- ---------------------------------------------------------------------------
local MACRO_ICON_PATH = {
  MOUNT   = "Interface\\Icons\\Ability_Mount_RidingHorse",
  CRITTER = "Interface\\Icons\\Ability_Hunter_BeastCall",
}

-- Resolve a bare texture path to its index in the macro-icon picker list (CreateMacro/EditMacro
-- take that INDEX, not a path — passing a path string directly errors, silently swallowed by our
-- pcall, which is exactly why dragging never picked anything up). Mirrors EZCollections' own
-- FindMacroIcon helper. Falls back to index 1 (never nil) so macro creation still succeeds.
local function findMacroIconIndex(path)
  if not (GetNumMacroIcons and GetMacroIconInfo) then return 1 end
  local target = path:lower():gsub("/", "\\")
  local okN, n = pcall(GetNumMacroIcons)
  if not okN then return 1 end
  for i = 1, n do
    local okI, p = pcall(GetMacroIconInfo, i)
    if okI and p and p:lower():gsub("/", "\\") == target then return i end
  end
  return 1
end

-- Find our macro by its BODY text rather than its name (mirrors EZCollections' own
-- FindFavoriteMacro). Matching on body — which is a fixed, known string per kind — rather than
-- name means the macro's Name field is free to be purely cosmetic; nothing here depends on what
-- it's called, so it's safe to give it a blank display name (see ensureFavoriteMacro below).
--
-- Exact match is tried first, but GetMacroBody doesn't always return byte-for-byte what was
-- passed to CreateMacro (e.g. a trailing newline the client appends) — an exact-only compare
-- would miss our own previously-created macro every subsequent login, silently creating a NEW
-- duplicate each time ("the macro keeps getting recreated"). EZCollections' real
-- FindFavoriteMacro hits this too and falls back to a substring-containment match; do the same
-- here. Uses the plain-find flag since our body contains literal parentheses/quotes
-- (`SummonRandomFavorite("MOUNT")`) that would otherwise be parsed as Lua pattern syntax.
local function findMacroByBody(body)
  if not GetMacroBody then return nil end
  local total = (MAX_ACCOUNT_MACROS or 0) + (MAX_CHARACTER_MACROS or 0)
  local loose
  for i = 1, total do
    local okB, b = pcall(GetMacroBody, i)
    if okB and b then
      if b == body then return i end
      if not loose and b:find(body, 1, true) then loose = i end
    end
  end
  return loose
end

local function ensureFavoriteMacro(kind)
  if not (CreateMacro and GetMacroBody) then return nil end
  -- MAX_ACCOUNT_MACROS/MAX_CHARACTER_MACROS and GetNumMacroIcons/GetMacroIconInfo all live in the
  -- Blizzard_MacroUI addon, which is lazy-loaded (not part of always-on FrameXML) — until it's
  -- loaded those globals are nil, both capacity checks below silently read as false, and CreateMacro
  -- never gets called. EZCollections' own macro helpers hit this too, which is why they always call
  -- LoadAddOn first; do the same here before touching any of them.
  if LoadAddOn then pcall(LoadAddOn, "Blizzard_MacroUI") end

  local body = string.format('/script DragonUI_NewEra.collections.SummonRandomFavorite("%s")', kind)
  local existing = findMacroByBody(body)
  if existing then return existing end

  -- Blank (single-space) display name: the text shown under a macro's icon on the action bar IS
  -- its Name field — there's no separate label — so this is the standard WoW "icon-only macro"
  -- trick. Safe specifically because existence is matched by body above, not name; if the user
  -- (or anything else) happens to have another macro also named " ", it's irrelevant here.
  local displayName = " "
  local icon = findMacroIconIndex(MACRO_ICON_PATH[kind] or "Interface\\Icons\\INV_Misc_QuestionMark")
  local numAccount, numChar = 0, 0
  if GetNumMacros then
    local okN, a, c = pcall(GetNumMacros)
    if okN then numAccount, numChar = a or 0, c or 0 end
  end
  -- Prefer an account-wide macro (matches retail's cross-character "favourite" concept); fall back
  -- to a per-character slot if the account pool is full. Never errors if both pools are full — the
  -- button just isn't draggable that session (still fully clickable/summonable in the window).
  if MAX_ACCOUNT_MACROS and numAccount < MAX_ACCOUNT_MACROS then
    local ok, idx = pcall(CreateMacro, displayName, icon, body, nil)
    if ok and idx then return idx end
  end
  if MAX_CHARACTER_MACROS and numChar < MAX_CHARACTER_MACROS then
    local ok, idx = pcall(CreateMacro, displayName, icon, body, 1)
    if ok and idx then return idx end
  end
  return nil
end

-- ===========================================================================
-- Factory
-- ===========================================================================
local function createJournal(kind)
  local J = { kind = kind }
  local isMount = (kind == "MOUNT")

  J.all      = {}   -- every KNOWN companion of this kind (learned + not-yet-learned): {index, creatureID,
                    -- name, spellID, icon, issummoned} — index/creatureID are nil for not-yet-learned
                    -- rows (no 3D model preview for those — see showModel)
  J.list     = {}   -- the filtered+ordered view actually shown
  J.rows     = {}   -- recycled list-row buttons
  J.selected = nil  -- the currently-selected data row (drives the model + info panel)
  J.collectedCount = 0                                           -- how many are actually learned (for the count pill)
  J.search   = ""
  J.favOnly  = false
  J.showCollected, J.showNotCollected = true, true               -- Collected / Not Collected filters
  J.showUnusable = true                                          -- show mounts not usable here (mounts only)
  J.showGround, J.showFlying, J.showAquatic = true, true, true   -- mount type filters (mounts only)
  J.sourceHidden = {}                                            -- [sourceIndex] = true -> hide that source

  -- Thin per-instance delegators to the module-level (kind-parameterized) versions above.
  local function mountCategory(spellID) return mountCategoryFor(kind, spellID) end
  local function isUsableNow(data) return isUsableNowFor(kind, data) end

  -- --- containers (one per shared region; Show/Hide as a group) --------------
  local function panel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints(parent)
    p:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    return p
  end
  local listGroup    = panel(C.LeftInset)
  local displayGroup = panel(C.RightInset)
  local topGroup     = panel(C.TopBand)
  local bottomGroup  = panel(C.BottomBand)
  J._groups = { listGroup, displayGroup, topGroup, bottomGroup }

  -- ------------------------------------------------------------------------
  -- Data
  -- ------------------------------------------------------------------------
  local function rebuildAll()
    for i = #J.all, 1, -1 do J.all[i] = nil end
    local seen = {}   -- spellID -> true, for learned companions (so the DB pass below can skip them)
    local ok, count = pcall(GetNumCompanions, kind)
    count = (ok and count) or 0
    local n = 0
    for i = 1, count do
      local okI, creatureID, name, spellID, icon, issummoned = pcall(GetCompanionInfo, kind, i)
      if okI and name then
        n = n + 1
        J.all[n] = { index = i, creatureID = creatureID, name = name,
                     spellID = spellID, icon = icon, issummoned = issummoned }
        if spellID then seen[spellID] = true end
      end
    end
    J.collectedCount = n

    -- Not-yet-learned entries from the bundled source DB (Data.lua), so the list reads like
    -- retail's full catalog rather than "only what you already have" — greyed out, info-only, no
    -- summon/favourite/model preview (SetCreature needs a server-resolvable creature/unit
    -- reference, not just a raw DB display ID — see showModel).
    -- SKIPPED when the spell doesn't even resolve client-side (GetSpellInfo fails): a hard signal
    -- that content genuinely isn't on THIS custom server, not just "you haven't gotten it yet" —
    -- showing a placeholder for something that can't possibly exist here would be pure clutter.
    -- ALSO skipped when the DB row has no description (row[5]) or no source (row[7]): a catalog
    -- entry with neither shows a blank info panel and gives the player nothing to act on (no idea
    -- what it is or where it comes from) — same "pure clutter" reasoning as the GetSpellInfo skip.
    -- ALSO skipped when it's a faction-specific mount for the OPPOSITE faction and NOT already
    -- learned: you can't ever legitimately acquire the other side's racial mount, so showing it
    -- greyed out in the catalog is pure clutter, not an aspirational "not yet collected" entry.
    -- (Only gates the not-yet-learned pass below — an already-learned opposite-faction mount, e.g.
    -- from a faction change, still shows normally via the GetCompanionInfo pass above.)
    local playerFaction
    if isMount and UnitFactionGroup then
      local okF, pf = pcall(UnitFactionGroup, "player")
      if okF then playerFaction = pf end
    end
    local db = isMount and NE.collections.MountData or NE.collections.PetData
    if db then
      for spellID, row in pairs(db) do
        if not seen[spellID] then
          local hasLore   = row[5] and row[5] ~= ""
          local hasSource = row[7] and row[7] ~= ""
          local factionOK = true
          if playerFaction then
            local mf = NE.collections.GetFaction and NE.collections.GetFaction(spellID)
            if (mf == 0 and playerFaction == "Alliance") or (mf == 1 and playerFaction == "Horde") then
              factionOK = false
            end
          end
          if hasLore and hasSource and factionOK then
            local okS, sName, _, sIcon = pcall(GetSpellInfo, spellID)
            if okS and sName then
              n = n + 1
              J.all[n] = {
                index = nil, creatureID = nil, name = row[4] or sName,
                spellID = spellID, icon = sIcon or C.tex.emptyIcon, issummoned = false,
              }
            end
          end
        end
      end
    end
  end

  -- Filtered + ordered view: Favourites, then Collected, then Not Collected — each group
  -- alphabetical within itself. Data.lua / GetSpellInfo supply the display name where
  -- GetCompanionInfo's/the DB's is blank.
  local function rebuildView()
    for i = #J.list, 1, -1 do J.list[i] = nil end
    local t = favTable()
    local favs, collected, uncollected = {}, {}, {}
    local needle = (J.search or ""):lower()
    for _, data in ipairs(J.all) do
      local name = data.name
      if not name or name == "" then name = C.GetInfo and select(1, C.GetInfo(kind, data.spellID)) end
      if not name or name == "" then
        local okS, sn = pcall(GetSpellInfo, data.spellID)
        if okS then name = sn end
      end
      data.displayName = (name and name ~= "" and name) or UNKNOWN or "?"

      local passSearch = (needle == "") or (data.displayName:lower():find(needle, 1, true) ~= nil)
      local k = favKey(kind, data)
      local fav = (t and k and t[k]) and true or false
      data._fav = fav

      -- A not-yet-learned row has no slot index; can't be favourited/summoned/previewed, gated
      -- purely by the Collected/Not Collected toggle rather than the usability/type-Unusable rule
      -- (which is meaningless for something you don't have).
      local passCollected = (data.index and J.showCollected) or ((not data.index) and J.showNotCollected)

      local passType = true
      if isMount then
        local ground, flying, aquatic = mountCategory(data.spellID)
        passType = (ground and J.showGround) or (flying and J.showFlying) or (aquatic and J.showAquatic)
        if data.index and not J.showUnusable and not isUsableNow(data) then passType = false end
      end
      local srcIdx = C.GetSourceIndex and C.GetSourceIndex(kind, data.spellID) or 12
      local passSource = not (J.sourceHidden and J.sourceHidden[srcIdx])
      if passSearch and passCollected and passType and passSource and (not J.favOnly or fav) then
        if fav then table.insert(favs, data)
        elseif data.index then table.insert(collected, data)
        else table.insert(uncollected, data) end
      end
    end
    local function byName(a, b) return (a.displayName or "") < (b.displayName or "") end
    table.sort(favs, byName)
    table.sort(collected, byName)
    table.sort(uncollected, byName)
    local m = 0
    for i = 1, #favs do m = m + 1; J.list[m] = favs[i] end
    for i = 1, #collected do m = m + 1; J.list[m] = collected[i] end
    for i = 1, #uncollected do m = m + 1; J.list[m] = uncollected[i] end
  end

  -- ------------------------------------------------------------------------
  -- 3D model + info panel (right inset)
  -- ------------------------------------------------------------------------
  local model, infoIcon, infoName, infoSource, infoLore, emptyLabel, notCollectedHint

  local function buildDisplay()
    -- Generic model backdrop (retail's MountJournal-BG). Visible slice is left 0..0.785.
    -- Inset 3px off displayGroup's edges (matching RightInset's own dark fill inset in Window.lua's
    -- buildInset) rather than SetAllPoints: displayGroup is a CHILD frame one level above RightInset,
    -- so a full-bleed texture here draws OVER RightInset's own InsetFrameTemplate silver border
    -- (frame-level ordering beats draw-layer ordering across different frames) — hiding it entirely.
    local bg = displayGroup:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", displayGroup, "TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", displayGroup, "BOTTOMRIGHT", -3, 3)
    bg:SetTexture(C.tex.modelBg)
    bg:SetTexCoord(0, 0.78515625, 0, 1)

    -- Header zone (icon/name/source/lore above) grew from 104 -> 170px: longer mount/pet lore
    -- descriptions (2-4 lines) were overflowing past the old boundary and getting visually covered
    -- by the model viewport, reading as "cut off". This also gives the modern control bar (below)
    -- clear room at the model's own TOP edge.
    model = CreateFrame("PlayerModel", nil, displayGroup)
    model:SetPoint("TOPLEFT", displayGroup, "TOPLEFT", 4, -170)
    model:SetPoint("BOTTOMRIGHT", displayGroup, "BOTTOMRIGHT", -4, 6)

    -- Same modern DF model control bar as the Character panel (zoom in/out, rotate L/R, reset,
    -- hover-reveal, click-drag rotate/pan, wheel-zoom) instead of the old bespoke drag-rotate +
    -- native rotation-art button pair.
    if NE.charpanel and NE.charpanel.BuildModelControls then
      -- rotateButtons MUST be forced to an empty table: the shared helper's own default targets the
      -- Character panel's GLOBAL rotate-button names by _G lookup — without this override, building
      -- controls for THIS model would reach into and hide the Character panel's own buttons too.
      pcall(NE.charpanel.BuildModelControls, model, {
        rotateButtons = {},
        panelCheck = function() return C.frame and C.frame:IsShown() and C.activeKind == kind end,
      })
    end

    -- Shown over the model area instead of a 3D preview when the selected row is not yet learned
    -- (no creatureDisplayID is available for those — only the API's real companions can preview).
    notCollectedHint = displayGroup:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    notCollectedHint:SetPoint("CENTER", model, "CENTER", 0, 0)
    notCollectedHint:SetText(NOT_COLLECTED or "Not yet collected")
    notCollectedHint:Hide()

    -- Info header (icon + name + source + lore), over the top of the backdrop.
    infoIcon = displayGroup:CreateTexture(nil, "ARTWORK")
    infoIcon:SetSize(ICON_SIZE, ICON_SIZE)
    infoIcon:SetPoint("TOPLEFT", displayGroup, "TOPLEFT", 14, -12)
    infoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    infoName = displayGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    infoName:SetPoint("TOPLEFT", infoIcon, "TOPRIGHT", 10, -2)
    infoName:SetPoint("RIGHT", displayGroup, "RIGHT", -30, 0)
    infoName:SetJustifyH("LEFT")

    -- Favourite star (top-right of the display, toggles the selected row's favourite).
    local fav = CreateFrame("CheckButton", nil, displayGroup)
    fav:SetSize(24, 24)
    fav:SetPoint("TOPRIGHT", displayGroup, "TOPRIGHT", -8, -8)
    local fN = fav:CreateTexture(nil, "ARTWORK"); fN:SetAllPoints(fav); fN:SetTexture(C.tex.favoriteIcon); fN:SetTexCoord(0.03125, 0.8125, 0.03125, 0.8125)
    local fH = fav:CreateTexture(nil, "HIGHLIGHT"); fH:SetAllPoints(fav); fH:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); fH:SetBlendMode("ADD")
    fav._star = fN
    fav:SetScript("OnClick", function(self)
      if not J.selected then return end
      local now = not J.selected._fav
      setFavorite(kind, J.selected, now)
      J:RefreshView()
    end)
    fav:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(BATTLE_PET_FAVORITE or "Favourite", 1, 0.82, 0)
      GameTooltip:AddLine("Keeps this at the front of the list.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    fav:SetScript("OnLeave", function() GameTooltip:Hide() end)
    J._favStar = fav

    -- TOPLEFT + RIGHT anchors alone were NOT reliably constraining these FontStrings' width for
    -- wrapping purposes — long lore text rendered as a single line, hard-clipped mid-word right at
    -- the panel edge instead of wrapping ("Descriptions are still being cut off"). An explicit
    -- SetWidth + SetWordWrap(true) is deterministic regardless of that anchor ambiguity; height is
    -- left unconstrained (only a TOPLEFT point) so it still grows downward to fit the text.
    local INFO_TEXT_W = 316

    infoSource = displayGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    infoSource:SetPoint("TOPLEFT", infoIcon, "BOTTOMLEFT", 0, -6)
    infoSource:SetWidth(INFO_TEXT_W)
    infoSource:SetWordWrap(true)
    infoSource:SetJustifyH("LEFT")

    infoLore = displayGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoLore:SetPoint("TOPLEFT", infoSource, "BOTTOMLEFT", 0, -8)
    infoLore:SetWidth(INFO_TEXT_W)
    infoLore:SetWordWrap(true)
    infoLore:SetJustifyH("LEFT")
    infoLore:SetTextColor(0.8, 0.8, 0.8)

    emptyLabel = displayGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    emptyLabel:SetPoint("CENTER", displayGroup, "CENTER", 0, 0)
    emptyLabel:SetText(isMount and (ERR_NO_RIDING_SKILL or "You have not learned any mounts.")
                                or "You have not learned any companions.")
    emptyLabel:Hide()
  end

  local function showModel(data)
    J.selected = data
    if not data then
      if model then model:Hide() end
      if notCollectedHint then notCollectedHint:Hide() end
      if infoIcon then infoIcon:SetTexture(nil) end
      if infoName then infoName:SetText("") end
      if infoSource then infoSource:SetText("") end
      if infoLore then infoLore:SetText("") end
      if J._favStar then J._favStar:Hide() end
      return
    end
    -- Model preview only works for a learned row's real creatureID (from GetCompanionInfo) —
    -- SetCreature on this client needs a server-resolvable creature/unit reference, not a raw
    -- CreatureDisplayInfo.dbc id, so a not-yet-learned row (no creatureID) always falls back to
    -- the "Not yet collected" text hint instead of attempting (and failing) a model preview.
    local previewID = data.creatureID
    if model then
      if previewID then
        model:Show()
        pcall(model.SetCreature, model, previewID)
        -- `.rotation` (not the old `._facing`) is the field the shared modern control bar
        -- (ModelControls.lua) reads as its drag-rotate baseline — keep it in sync with the actual
        -- visual reset here, or the next drag would jump from a stale angle.
        model.rotation = 0
        pcall(model.SetRotation, model, 0)
      else
        model:Hide()
      end
    end
    if notCollectedHint then notCollectedHint:SetShown(not previewID) end
    if infoIcon then infoIcon:SetTexture(data.icon) end
    if infoName then infoName:SetText(data.displayName or data.name or "") end
    local _, lore, source = nil, nil, nil
    if C.GetInfo then _, lore, source = C.GetInfo(kind, data.spellID) end
    if infoSource then infoSource:SetText(source or "") end
    if infoLore then infoLore:SetText(lore or "") end
    -- Favouriting requires a learned companion (favKey needs a creatureID) — hide the star entirely
    -- for not-yet-learned rows rather than show a star that would silently no-op if clicked.
    if J._favStar then
      if data.index then J._favStar:Show(); J._favStar:SetChecked(data._fav and true or false)
      else J._favStar:Hide() end
    end
  end

  -- ------------------------------------------------------------------------
  -- Action button (Mount / Summon / Dismiss) — bottom band.
  -- ------------------------------------------------------------------------
  local actionBtn
  local function summonData(data)
    if not (data and data.index) then return end   -- not-yet-learned rows have nothing to summon
    if data.issummoned then pcall(DismissCompanion, kind)
    else pcall(CallCompanion, kind, data.index) end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, function() J:Refresh() end) end
  end
  local function summonSelected() summonData(J.selected) end
  local function buildAction()
    actionBtn = CreateFrame("Button", nil, bottomGroup, "UIPanelButtonTemplate")
    actionBtn:SetSize(150, 22)
    actionBtn:SetPoint("LEFT", bottomGroup, "LEFT", 2, 0)
    actionBtn:SetText(isMount and (MOUNT or "Mount") or (SUMMON or "Summon"))
    actionBtn:SetScript("OnClick", summonSelected)
  end
  local function updateAction()
    if not actionBtn then return end
    local data = J.selected
    if not (data and data.index) then actionBtn:Disable(); return end
    actionBtn:Enable()
    if data.issummoned then
      actionBtn:SetText(isMount and (BINDING_NAME_DISMOUNT or "Dismiss") or (PET_DISMISS or "Dismiss"))
    else
      actionBtn:SetText(isMount and (MOUNT or "Mount") or (SUMMON or "Summon"))
    end
  end

  -- ------------------------------------------------------------------------
  -- Count pill + Summon-Random-Favourite (top band)
  -- ------------------------------------------------------------------------
  -- Fallback icon if the custom Mount-tab art isn't shipped; pets have no equivalent custom art yet,
  -- so they keep showing a live favourite's icon (falls back to the first companion's, then this).
  local SUMMON_FALLBACK = isMount and "Interface\\Icons\\Ability_Mount_RidingHorse"
                                   or "Interface\\Icons\\Ability_Hunter_BeastCall"

  local countLabel, summonBtn
  local function updateSummonIcon()
    if not summonBtn then return end
    if isMount and C.tex.mountUpFavourites then
      -- User-provided art for this exact button (Mounts tab only).
      summonBtn._tex:SetTexture(C.tex.mountUpFavourites)
      return
    end
    -- Pets: show a favourite's icon (retail shows the favourite macro's icon); else the first
    -- companion's; else the static fallback — always a real, relevant icon, never a generic guess.
    local icon
    for _, d in ipairs(J.all) do if d._fav then icon = d.icon; break end end
    icon = icon or (J.all[1] and J.all[1].icon) or SUMMON_FALLBACK
    summonBtn._tex:SetTexture(icon)
  end

  local function buildTop()
    -- Count sits to the RIGHT of the frame portrait (which overlaps the top-left corner), never
    -- under it — housed in a small recessed pill (dark fill + thin InsetFrameTemplate border), like
    -- retail's "Total Mounts" box, rather than bare floating text.
    local countBox = CreateFrame("Frame", nil, topGroup)
    countBox:SetPoint("LEFT", topGroup, "LEFT", 56, 0)
    countBox:SetHeight(20)
    countBox:SetWidth(90)
    local countBg = countBox:CreateTexture(nil, "BACKGROUND")
    countBg:SetPoint("TOPLEFT", 3, -3)
    countBg:SetPoint("BOTTOMRIGHT", -3, 3)
    if countBg.SetColorTexture then countBg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    else countBg:SetTexture(0.05, 0.05, 0.06, 0.92) end
    if NE.nineslice and NE.nineslice.ApplyLayout then pcall(NE.nineslice.ApplyLayout, countBox, "InsetFrameTemplate") end
    J._countBox = countBox

    countLabel = countBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("CENTER", countBox, "CENTER", 0, 0)

    summonBtn = CreateFrame("Button", nil, topGroup)
    summonBtn:SetSize(30, 30)
    summonBtn:SetPoint("RIGHT", topGroup, "RIGHT", -2, 0)
    local st = summonBtn:CreateTexture(nil, "ARTWORK"); st:SetAllPoints(summonBtn)
    st:SetTexture(SUMMON_FALLBACK)
    st:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    summonBtn._tex = st
    -- Thin icon border so it reads as a button, not floating art.
    local br = summonBtn:CreateTexture(nil, "OVERLAY")
    br:SetTexture(C.tex.iconFrame)
    br:SetPoint("TOPLEFT", summonBtn, "TOPLEFT", -2, 2)
    br:SetPoint("BOTTOMRIGHT", summonBtn, "BOTTOMRIGHT", 2, -2)
    -- Two-line label to the left of the icon (retail "Summon Random Favorite Mount").
    local slabel = topGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    slabel:SetPoint("RIGHT", summonBtn, "LEFT", -6, 0)
    slabel:SetWidth(150)
    slabel:SetJustifyH("RIGHT")
    slabel:SetText(isMount and "Summon Random\nFavorite Mount" or "Summon Random\nFavorite Companion")
    summonBtn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    summonBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- Dragging this button itself onto an action bar never worked reliably (matches EZCollections'
    -- own behaviour, per user report) — plain non-secure Buttons don't hand off a macro pickup on
    -- OnDragStart the way retail's real MountJournal button (a secure template) does. Instead, the
    -- backing macro is created lazily on the button's FIRST click (not eagerly at build time — the
    -- player never asked for it just by having the journal open, and eager creation meant a macro
    -- appeared at login even if the player never touched this button) and the tooltip tells the
    -- player where to find it afterward: drag it off their own Macros window (ESC > Macros, or
    -- /macro) onto a bar, same as any other macro.
    summonBtn:SetScript("OnClick", function()
      ensureFavoriteMacro(kind)
      NE.collections.SummonRandomFavorite(kind)
      if C_Timer and C_Timer.After then C_Timer.After(0.2, function() J:Refresh() end) end
    end)
    summonBtn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(isMount and "Summon Random Favorite Mount" or "Summon Random Favorite Companion", 1, 1, 1)
      GameTooltip:AddLine("Picks a random favorite usable here (or any, if none are favorited).", 0.82, 0.82, 0.82, true)
      GameTooltip:AddLine("To use this on an action bar: open Macros (ESC > Macros), find the unnamed icon-only macro matching this icon, and drag it onto your bar.", 0.6, 0.8, 1, true)
      GameTooltip:Show()
    end)
    summonBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  -- ------------------------------------------------------------------------
  -- Search box + filter (left inset top) + scrollable list
  -- ------------------------------------------------------------------------
  local scroll, content, searchBox, filterBtn

  local function styleRow(row)
    local co = C.listCoords
    row.background:SetTexCoord(co.background[1], co.background[2], co.background[3], co.background[4])
    row.selectedTex:SetTexCoord(co.select[1], co.select[2], co.select[3], co.select[4])
  end

  local function acquireRow(i)
    if J.rows[i] then return J.rows[i] end
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetTexture(C.tex.listButtons)
    row.background:SetAllPoints(row)

    row.selectedTex = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.selectedTex:SetTexture(C.tex.listButtons)
    row.selectedTex:SetAllPoints(row)
    row.selectedTex:Hide()

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(C.tex.listButtons)
    hl:SetTexCoord(C.listCoords.highlight[1], C.listCoords.highlight[2], C.listCoords.highlight[3], C.listCoords.highlight[4])
    hl:SetAllPoints(row)

    row.icon = row:CreateTexture(nil, "BORDER")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- "Currently summoned" tint over the icon. CheckButtonHilight's actual glow content doesn't
    -- reach its own texture edges (baked-in padding), so SetAllPoints(icon) rendered visibly
    -- smaller than the icon — oversize it a few px past the icon bounds instead so the bloom
    -- reaches/covers the icon edges.
    row.active = row:CreateTexture(nil, "OVERLAY")
    row.active:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.active:SetSize(ICON_SIZE + 10, ICON_SIZE + 10)
    row.active:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    row.active:SetBlendMode("ADD")
    row.active:Hide()

    -- Faction crest watermark on the right (faction-specific mounts only), faded, behind the name.
    -- Sized to the crest's actual pixel aspect ratio (see Assets.lua factionCoords) — the old flat
    -- 84x42 box didn't match either crest's real proportions and stretched them.
    row.faction = row:CreateTexture(nil, "ARTWORK")
    row.faction:SetSize(32, 36)
    row.faction:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.faction:SetTexture(C.tex.factionIcons)
    row.faction:SetAlpha(0.65)
    row.faction:Hide()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -26, 0)
    row.name:SetJustifyH("LEFT")

    row.fav = row:CreateTexture(nil, "OVERLAY")
    row.fav:SetSize(22, 22)
    row.fav:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -8, 8)
    row.fav:SetTexture(C.tex.favoriteIcon)
    row.fav:SetTexCoord(0.03125, 0.8125, 0.03125, 0.8125)
    row.fav:Hide()

    styleRow(row)

    row:SetScript("OnClick", function(self, button)
      local data = self._data
      if not data then return end
      if button == "RightButton" then
        if not data.index then return end   -- nothing to Mount/Favourite for a not-yet-learned row
        J._menuData = data
        if ToggleDropDownMenu and J.rowMenu then ToggleDropDownMenu(1, nil, J.rowMenu, "cursor", 0, 0) end
      else
        -- Left-click always selects (even not-yet-learned rows) — that's how you see its acquisition
        -- info (source/lore), same as retail's Mount Journal.
        showModel(data)
        J:UpdateList()   -- refresh selection highlight + action button
        updateAction()
      end
    end)
    row:SetScript("OnEnter", function(self)
      local data = self._data
      if not data then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(data.displayName or data.name or "", 1, 1, 1)
      if data.index then
        GameTooltip:AddLine(data.issummoned and "Right-click to dismiss" or "Right-click to summon", 1, 0.82, 0)
      else
        GameTooltip:AddLine(NOT_COLLECTED or "Not yet collected", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    J.rows[i] = row
    return row
  end

  -- How many rows fit the scroll height right now (created lazily), and the total pixel height
  -- available to them.
  local function visibleRows()
    local h = scroll and scroll:GetHeight() or 0
    if h <= 0 then h = 440 end   -- best-effort before first layout settles
    return math.max(1, math.floor(h / ROW_H)), h
  end

  function J:UpdateList()
    if not (scroll and content) then return end
    local shown, availH = visibleRows()
    -- Stretch rows to consume the FULL available height instead of the fixed ROW_H: ROW_H rarely
    -- divides the inset's actual height evenly, so flooring alone left a dead gap (often 30-40px)
    -- of bare background between the last row and the bottom of the inset. content isn't a real
    -- scroll-child (see the FauxScrollFrame_Update note below) so nothing clips an overhanging
    -- partial row — stretching each row slightly (a couple px at most) is the only way to reach the
    -- bottom without one hanging out past the inset's edge. Row art/icon/name are all anchored by
    -- single-point (LEFT/CENTER-style) anchors that re-center automatically at any row height, so
    -- this doesn't visibly distort them.
    local rowH = (shown > 0) and (availH / shown) or ROW_H
    J._rowH = rowH
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, shown do
      local row = acquireRow(i)
      row:ClearAllPoints()
      row:SetHeight(rowH)
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowH)
      row:SetPoint("RIGHT", content, "RIGHT", -2, 0)
      local data = J.list[i + offset]
      if data then
        row._data = data
        row.icon:SetTexture(data.icon)
        row.name:SetText(data.displayName or data.name or "")
        -- Not-yet-learned rows read grey/desaturated (retail's own "uncollected" treatment) — the
        -- icon itself is the only visual cue since there's no ring/star for them to omit.
        if data.index then
          row.name:SetFontObject(GameFontNormal)
          row.icon:SetAlpha(1)
          if row.icon.SetDesaturated then pcall(row.icon.SetDesaturated, row.icon, false) end
        else
          row.name:SetFontObject(GameFontDisable)
          row.icon:SetAlpha(0.45)
          if row.icon.SetDesaturated then pcall(row.icon.SetDesaturated, row.icon, true) end
        end
        if data.issummoned then row.active:Show() else row.active:Hide() end
        if data._fav then row.fav:Show() else row.fav:Hide() end
        local fac = isMount and C.GetFaction and C.GetFaction(data.spellID)
        if fac ~= nil and fac ~= false and C.factionCoords[fac] then
          local fc = C.factionCoords[fac]
          row.faction:SetTexCoord(fc[1], fc[2], fc[3], fc[4])
          row.faction:Show()
        else
          row.faction:Hide()
        end
        -- Compare by spellID, not slot index: two different not-yet-learned rows both have
        -- index == nil, so an index-based compare would show EVERY uncollected row as "selected".
        if J.selected and J.selected.spellID and J.selected.spellID == data.spellID then
          row.selectedTex:Show()
        else
          row.selectedTex:Hide()
        end
        row:Show()
      else
        row._data = nil
        row:Hide()
      end
    end
    FauxScrollFrame_Update(scroll, #J.list, shown, rowH)
    if countLabel then
      -- The count pill is "how many you actually have", like retail — NOT the full catalog size
      -- (J.all now also includes not-yet-learned placeholder rows).
      countLabel:SetText(string.format("%s %d", isMount and (TOTAL_MOUNTS or "Total Mounts") or "Companions", J.collectedCount or 0))
      if J._countBox then J._countBox:SetWidth(math.max(90, (countLabel:GetStringWidth() or 0) + 24)) end
    end
  end

  -- Right-click row context menu: Mount/Summon (or Dismiss), Favourite toggle, Cancel — like retail.
  local function rowMenuInit(self, level)
    local data = J._menuData
    if not data then return end
    local info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true

    if data.issummoned then
      info.text = isMount and (BINDING_NAME_DISMOUNT or "Dismiss") or (PET_DISMISS or "Dismiss")
    else
      info.text = isMount and (MOUNT or "Mount") or (SUMMON or "Summon")
    end
    info.func = function() summonData(data) end
    UIDropDownMenu_AddButton(info, level)

    info.text = data._fav and (BATTLE_PET_UNFAVORITE or "Remove Favourite") or (BATTLE_PET_FAVORITE or "Favourite")
    info.func = function() setFavorite(kind, data, not data._fav); J:RefreshView() end
    UIDropDownMenu_AddButton(info, level)

    info.text = CANCEL or "Cancel"
    info.func = nil
    UIDropDownMenu_AddButton(info, level)
  end

  -- The distinct source indices present in the current companion set (for the Sources submenu).
  local function presentSources()
    local seen, out = {}, {}
    for _, d in ipairs(J.all) do
      local idx = C.GetSourceIndex and C.GetSourceIndex(kind, d.spellID) or 12
      if not seen[idx] then seen[idx] = true; out[#out + 1] = idx end
    end
    table.sort(out)
    return out
  end

  -- Filter dropdown: Collected / Not Collected, Unusable + Type toggles (mounts), Favourites,
  -- Sources submenu — matches retail's Mount Journal filter layout. Uses the retail
  -- func(_, _, _, checked) + checked-as-function pattern so each toggle updates live AND filters.
  -- Toggling only re-runs rebuildView (not a full companion re-scan), so the menu stays snappy.
  local function filterMenuInit(self, level)
    level = level or 1
    if level == 1 then
      local info = UIDropDownMenu_CreateInfo()
      info.isNotRadio = true
      info.keepShownOnClick = true

      info.text = COLLECTED or "Collected"
      info.checked = function() return J.showCollected end
      info.func = function(_, _, _, checked) J.showCollected = checked and true or false; J:RefreshView() end
      UIDropDownMenu_AddButton(info, level)

      info.text = NOT_COLLECTED or "Not Collected"
      info.checked = function() return J.showNotCollected end
      info.func = function(_, _, _, checked) J.showNotCollected = checked and true or false; J:RefreshView() end
      UIDropDownMenu_AddButton(info, level)

      if isMount then
        info.text = MOUNT_JOURNAL_FILTER_UNUSABLE or "Unusable"
        info.checked = function() return J.showUnusable end
        info.func = function(_, _, _, checked) J.showUnusable = checked and true or false; J:RefreshView() end
        UIDropDownMenu_AddButton(info, level)

        local title = UIDropDownMenu_CreateInfo()
        title.text = MOUNT_JOURNAL_FILTER_TYPE or "Type"
        title.isTitle = true; title.notCheckable = true
        UIDropDownMenu_AddButton(title, level)

        local types = {
          { MOUNT_JOURNAL_FILTER_GROUND  or "Ground",  "showGround"  },
          { MOUNT_JOURNAL_FILTER_FLYING  or "Flying",  "showFlying"  },
          { MOUNT_JOURNAL_FILTER_AQUATIC or "Aquatic", "showAquatic" },
        }
        for _, ty in ipairs(types) do
          local key = ty[2]
          local i2 = UIDropDownMenu_CreateInfo()
          i2.isNotRadio = true; i2.keepShownOnClick = true
          i2.text = ty[1]
          i2.checked = function() return J[key] end
          i2.func = function(_, _, _, checked) J[key] = checked and true or false; J:RefreshView() end
          UIDropDownMenu_AddButton(i2, level)
        end
      end

      if UIDropDownMenu_AddSpace then pcall(UIDropDownMenu_AddSpace, level) end

      info.text = BATTLE_PET_FAVORITE or "Favorites"
      info.checked = function() return J.favOnly end
      info.func = function(_, _, _, checked) J.favOnly = checked and true or false; J:RefreshView() end
      UIDropDownMenu_AddButton(info, level)

      local src = UIDropDownMenu_CreateInfo()
      src.text = SOURCES or "Sources"
      src.notCheckable = true; src.hasArrow = true; src.value = "sources"
      UIDropDownMenu_AddButton(src, level)

    elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "sources" then
      local function refreshSub()
        if UIDropDownMenu_Refresh then pcall(UIDropDownMenu_Refresh, J.filterMenu, nil, 2) end
      end
      local all = UIDropDownMenu_CreateInfo()
      all.notCheckable = true; all.keepShownOnClick = true
      all.text = CHECK_ALL or "Check All"
      all.func = function() J.sourceHidden = {}; J:RefreshView(); refreshSub() end
      UIDropDownMenu_AddButton(all, level)
      all.text = UNCHECK_ALL or "Uncheck All"
      all.func = function()
        J.sourceHidden = {}
        for _, idx in ipairs(presentSources()) do J.sourceHidden[idx] = true end
        J:RefreshView(); refreshSub()
      end
      UIDropDownMenu_AddButton(all, level)

      for _, idx in ipairs(presentSources()) do
        local i2 = UIDropDownMenu_CreateInfo()
        i2.isNotRadio = true; i2.keepShownOnClick = true
        i2.text = (C.SourceLabel and C.SourceLabel(idx)) or ("Source " .. idx)
        i2.checked = function() return not J.sourceHidden[idx] end
        i2.func = function(_, _, _, checked) J.sourceHidden[idx] = (not checked) and true or nil; J:RefreshView() end
        UIDropDownMenu_AddButton(i2, level)
      end
    end
  end

  local function buildMenus()
    J.rowMenu = CreateFrame("Frame", "NE_Collections_" .. kind .. "RowMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(J.rowMenu, rowMenuInit, "MENU")
    J.filterMenu = CreateFrame("Frame", "NE_Collections_" .. kind .. "FilterMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(J.filterMenu, filterMenuInit, "MENU")
  end

  local function buildList()
    searchBox = CreateFrame("EditBox", nil, listGroup, "InputBoxTemplate")
    searchBox:SetSize(140, SEARCH_H)
    searchBox:SetPoint("TOPLEFT", listGroup, "TOPLEFT", 12, -8)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(18, 6, 0, 0)   -- leave room for the left magnifier
    -- Search magnifier at the box's left edge (retail SearchBoxTemplate), with a "Search" placeholder.
    local si = searchBox:CreateTexture(nil, "OVERLAY")
    si:SetSize(14, 14)
    si:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    si:SetTexture(C.tex.searchIcon)
    local ph = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ph:SetPoint("LEFT", searchBox, "LEFT", 20, 0)
    ph:SetText(SEARCH or "Search")
    searchBox:SetScript("OnTextChanged", function(self)
      local txt = self:GetText() or ""
      if txt == "" then ph:Show() else ph:Hide() end
      J.search = txt
      J:RefreshView()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    filterBtn = CreateFrame("Button", "NE_Collections_" .. kind .. "FilterButton", listGroup, "UIPanelButtonTemplate")
    filterBtn:SetSize(78, SEARCH_H)
    filterBtn:SetPoint("TOPRIGHT", listGroup, "TOPRIGHT", -6, -8)
    filterBtn:SetText(FILTER or "Filter")
    -- Dropdown arrow on the right edge (retail filter button).
    local far = filterBtn:CreateTexture(nil, "ARTWORK")
    far:SetSize(8, 8)
    far:SetPoint("RIGHT", filterBtn, "RIGHT", -6, 0)
    far:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    local ftext = filterBtn:GetFontString()
    if ftext then ftext:ClearAllPoints(); ftext:SetPoint("LEFT", filterBtn, "LEFT", 8, 0) end
    filterBtn:SetScript("OnClick", function(self)
      if PlaySound then pcall(PlaySound, "igMainMenuOptionCheckBoxOn") end
      if ToggleDropDownMenu and J.filterMenu then
        ToggleDropDownMenu(1, nil, J.filterMenu, self, 0, 0)
      end
    end)

    -- Named FauxScrollFrame (an UNNAMED FauxScrollFrameTemplate errors in its OnLoad, which
    -- concatenates self:GetName()..\"ScrollBar\").
    scroll = CreateFrame("ScrollFrame", "NE_Collections_" .. kind .. "List", listGroup, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listGroup, "TOPLEFT", 6, -(SEARCH_H + 14))
    scroll:SetPoint("BOTTOMRIGHT", listGroup, "BOTTOMRIGHT", -24, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
      FauxScrollFrame_OnVerticalScroll(self, offset, J._rowH or ROW_H, function() J:UpdateList() end)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local sb = _G[(self:GetName() or "") .. "ScrollBar"]
      if not sb then return end
      local mn, mx = sb:GetMinMaxValues()
      local v = sb:GetValue() - delta * (J._rowH or ROW_H)
      if v < mn then v = mn elseif v > mx then v = mx end
      sb:SetValue(v)
    end)
    scroll:HookScript("OnSizeChanged", function() J:UpdateList() end)
    -- Hand-built minimal scrollbar (the stock-slider Reskin path doesn't render for FauxScrollFrames).
    if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = -6 }) end

    -- The row container is a child of listGroup (always shown), NOT of the FauxScrollFrame:
    -- FauxScrollFrame_Update HIDES the scroll frame when the list fits with no scrolling, which would
    -- take every row down with it (the documented empty-pane bug — see Skills.lua). Anchor content
    -- over the scroll rect and raise it above the scroll frame.
    content = CreateFrame("Frame", nil, listGroup)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    content:SetHeight(1)
    content:SetFrameLevel(scroll:GetFrameLevel() + 5)
  end

  -- ------------------------------------------------------------------------
  -- Public: build once, refresh (rebuild data + relayout), show/hide the group.
  -- ------------------------------------------------------------------------
  local built = false
  local function build()
    if built then return end
    built = true
    buildTop()
    buildMenus()
    buildList()
    buildDisplay()
    buildAction()
  end

  -- Re-run the filter/sort + repaint only (search box, filter-menu toggles, favouriting) — NOT a
  -- full companion re-scan. J.all's table objects are mutated in place by rebuildView (never
  -- replaced), so J.selected stays a live, valid reference; no re-pointing needed here.
  function J:RefreshView()
    rebuildView()
    if not J.selected and J.list[1] then J.selected = J.list[1] end
    showModel(J.selected)
    updateSummonIcon()
    self:UpdateList()
    updateAction()
    if emptyLabel then
      if #J.list == 0 then
        emptyLabel:SetText((J.collectedCount or 0) == 0
          and (isMount and (ERR_NO_RIDING_SKILL or "You have not learned any mounts.")
                        or "You have not learned any companions.")
          or "No results match your filters.")
        emptyLabel:Show()
      else
        emptyLabel:Hide()
      end
    end
  end

  -- Full refresh: re-scan GetCompanionInfo + the not-yet-learned DB pass (rebuildAll REPLACES
  -- J.all's table objects), then RefreshView. Used on tab-select and companion-learn/summon events;
  -- search/filter-only changes use the cheaper RefreshView above instead.
  function J:Refresh()
    build()
    rebuildAll()
    -- Keep a valid selection across the rebuild: re-point at the same companion by spellID (stable
    -- identity for both collected AND not-yet-learned rows — unlike creatureID, which is nil for
    -- every not-yet-learned row and would falsely "match" the first such row it finds via nil==nil).
    if J.selected and J.selected.spellID then
      local keep
      for _, d in ipairs(J.all) do if d.spellID == J.selected.spellID then keep = d; break end end
      J.selected = keep
    end
    self:RefreshView()
  end

  function J:Show()
    build()
    for _, g in ipairs(J._groups) do g:Show() end
  end
  function J:Hide()
    for _, g in ipairs(J._groups) do g:Hide() end
  end

  return J
end

-- ---------------------------------------------------------------------------
-- Window.lua calls this at PLAYER_LOGIN (after the shell exists) to instantiate both journals.
-- ---------------------------------------------------------------------------
function C.BuildJournals()
  if C._journalsBuilt then return end
  if not (C.LeftInset and C.RightInset and C.TopBand and C.BottomBand) then
    log("BuildJournals: shell insets not ready"); return
  end
  C._journalsBuilt = true
  C.RegisterJournal("MOUNT", createJournal("MOUNT"))
  C.RegisterJournal("CRITTER", createJournal("CRITTER"))
end
