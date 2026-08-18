-- DragonUI_NewEra/modules/bags/CombinedBag.lua — single all-in-one "retail combined bag" window.
--
-- DOWNPORT: distilled from NewEra (Classic 1.15) ContainerFrame/CombinedBag.lua, rebuilt on the
-- already-downported grid engine (core/ItemGrid.lua = NE.itemgrid). One movable window shows every
-- backpack slot (bags 0..NUM_BAG_SLOTS) in a 10-wide retail-ordered grid, framed with the same
-- Dragonflight metal chrome the rest of the addon uses. The grid engine re-parents pooled
-- ContainerFrameItemButtonTemplate buttons onto per-bag proxy frames so the NATIVE item handlers
-- (click/drag/split/use/tooltip/cooldown) resolve the correct bag+slot — we never reimplement item
-- mechanics.
--
-- When this module is enabled it becomes the bag UI: it takes over the bag-open globals
-- (ToggleBackpack / ToggleAllBags / OpenAllBags / CloseAllBags / OpenBackpack / CloseBackpack) and
-- suppresses the stock ContainerFrames on show. It therefore SUPERSEDES the per-window "Retail
-- bags" restyle (modules/bags/Bags.lua) — enable one or the other. Default OFF (opt-in), since it
-- changes bag-open behaviour; the per-window restyle is the lighter default.
--
-- DELIBERATELY OMITTED vs the 1.15 original (each needs a retail-only system 3.3.5a lacks): the
-- right-click filter/cleanup/mode Menu (retail Menu API), the in-bag search box
-- (BagSearchBoxTemplate), and the auto-sort button (3.3.5a has no native SortBags). Money frame IS
-- kept (SmallMoneyFrameTemplate), and the bottom money band ports the retail currency/token bar
-- (common-currencybox pills fed by 3.3.5a's GetBackpackCurrencyInfo + player money, right-docked).
--
-- Reload-gated per Core/Modules.lua: disabled → not booted → stock / per-window bags.

local NE = DragonUI_NewEra
if not NE then return end

local MODULE = "combinedbag"
NE.combinedbag = NE.combinedbag or {}
local CB = NE.combinedbag

-- ItemGrid uses NE.containerframe for its shared helpers (ApplyLockedSlot etc.). Mark _hideLocked
-- so the retail "buy more slots" authenticator phantom slots never appear on 3.3.5a.
NE.containerframe = NE.containerframe or {}
NE.containerframe._hideLocked = true

local G = NE.itemgrid

local function log(msg) if NE.Log then NE.Log("COMBINEDBAG", msg) end end

-- ----------------------------------------------------------------------------
-- Geometry (transcribed from NewEra's ContainerFrameCombinedBagsMixin values).
-- ----------------------------------------------------------------------------
-- Geometry measured from the target image.png (522px window): slot pitch ~45px, ~18-20px gutters
-- to the window edges. So: 40px slots + 5px spacing = 45px pitch; LEFT_PADDING 18 + PADDING_WIDTH 36
-- give matching ~18px left/right gutters (frameW = contentW + PADDING_WIDTH; right gutter =
-- PADDING_WIDTH - LEFT_PADDING = 18).
-- Measured from image.png: visible slot 38px, gap 7px, pitch 45px (slot/pitch 0.84). The recess
-- draws at button+4px (SkinButton insets -2/+2), so ITEM_SIZE 34 → 38px visible slot; spacing 11 →
-- 45px pitch and a 7px gap. Gutters ~18px via LEFT_PADDING 18 / PADDING_WIDTH 36.
local NUM_BAG_SLOTS  = NUM_BAG_SLOTS or 4            -- backpack(0) + bags 1..4
local KEYRING_CONTAINER = KEYRING_CONTAINER or -2    -- the keyring is container -2 (its own key row)
local COLUMNS        = 10
local ITEM_SIZE      = 34                             -- +4px recess overhang = 38px visible slot
local ITEM_SPACING_X = 11                            -- pitch 45, visible gap 7 (matches target)
local ITEM_SPACING_Y = 11
local PADDING_WIDTH  = 36
local PADDING_HEIGHT = 82
local LEFT_PADDING   = 18                             -- left gutter to the metal frame
local RIGHT_PADDING  = PADDING_WIDTH - LEFT_PADDING   -- matching right gutter (18)
local TOP_HEADER     = 72                             -- chrome (title + search) above the items
local MONEY_FRAME_H  = 16

-- Bottom money band (transcribed from retail's ContainerFrameTokenWatcherMixin + the NewEra port):
-- a full-width band under the item grid, separated by a thin divider, carrying the watched-currency
-- token pills on the LEFT and the player MoneyFrame on the RIGHT. Sizes tuned for the ~11px gutters
-- the rest of the window uses.
local BAND_H          = 20                            -- token/money row height
local BAND_TOP_GAP    = 12                            -- last item row → divider
local BAND_BOTTOM_GAP = 12                            -- band → window bottom (matches the gutters)
local BAND_RESERVE    = BAND_TOP_GAP + BAND_H + BAND_BOTTOM_GAP   -- bottom room the grid must leave

-- common-currencybox 3-piece pill (fdid 4701880, coords from wago.tools via NewEra AtlasData). The
-- BLP ships in Textures/Common (registered in Textures/Assets.lua); coords registered here so the
-- whole token-bar feature stays inside the bags module.
local TOKEN_ATLASES = {
  ["common-currencybox-left"]    = { file = 4701880, left = 0.031250, right = 0.531250, top = 0.289062, bottom = 0.554688, width = 16, height = 34 },
  ["common-currencybox-right"]   = { file = 4701880, left = 0.031250, right = 0.531250, top = 0.570312, bottom = 0.835938, width = 16, height = 34 },
  ["_common-currencybox-center"] = { file = 4701880, left = 0.000000, right = 0.500000, top = 0.007812, bottom = 0.273438, width = 16, height = 34 },
}
if NE.tex and NE.tex.RegisterAtlases then NE.tex.RegisterAtlases(TOKEN_ATLASES) end
local MAX_TOKENS = MAX_WATCHED_TOKENS or 3            -- 3.3.5a backpack tracks up to 3 currencies

local PORTRAIT_BAG_ASSET = "Interface\\Icons\\Inv_misc_bag_08"
-- Prefer WoW's localized COMBINED_BAG_TITLE global (absent on 3.3.5a) → English via NE.L.
local TITLE_TEXT         = (type(COMBINED_BAG_TITLE) == "string" and COMBINED_BAG_TITLE) or NE.L["All Bags"]

local frame   -- the window (built lazily)
local grid    -- NE.itemgrid instance over bags 0..NUM_BAG_SLOTS
local keyGrid -- NE.itemgrid instance over the keyring (container -2), shown as an opt-in bottom row

-- Keyring row layout: a small "Keys" label + one grid row under the main grid, above the money band.
local KEYS_TOP_GAP = 10   -- gap between the last item row and the keys section
local KEYS_LABEL_H = 15   -- height reserved for the "Keys" label above the key slots

-- Opt-in: show the keyring as a row inside the combined window. OFF by default → the stock keyring
-- frame opens normally when you click the keyring (see installIntercept).
if CB._showKeys == nil then CB._showKeys = false end
function CB.ShowKeys() return CB._showKeys and true or false end

-- Opt-in: split specialty bags (quiver, ammo pouch, soul bag, profession bags) into their OWN labeled
-- sections below the general grid — each with an UPPERCASE header (QUIVER, MINING BAG, …), mirroring
-- the keyring row. OFF by default (the general grid then just clusters specialty items after general).
if CB._separateBags == nil then CB._separateBags = false end
function CB.SeparateBags() return CB._separateBags and true or false end

-- Player's held bags grouped by TYPE: general bags (family 0, incl. the backpack) first, then
-- specialty bags (quiver, soul, profession, etc.) grouped by family. Drives both the grid display
-- order (items cluster by bag type) and the sort target assignment. bagFamily from
-- GetContainerNumFreeSlots's 2nd return; item family from GetItemFamily.
local function orderedBags()
  local list = {}
  for bag = 0, NUM_BAG_SLOTS do
    local _, family = 0, 0
    if GetContainerNumFreeSlots then _, family = GetContainerNumFreeSlots(bag) end
    list[#list + 1] = { bag = bag, family = family or 0 }
  end
  table.sort(list, function(a, b)
    if (a.family == 0) ~= (b.family == 0) then return a.family == 0 end   -- general bags first
    if a.family ~= b.family then return a.family < b.family end           -- specialty grouped by family
    return a.bag < b.bag
  end)
  return list
end

-- Does an item of family `itemFam` fit a bag of family `bagFam`? General bags (0) take anything;
-- specialty bags only take matching families. Prevents e.g. regular items landing in a quiver.
local function itemFitsBag(itemFam, bagFam)
  if bagFam == 0 then return true end
  return bit and bit.band and bit.band(itemFam or 0, bagFam) ~= 0
end

-- Sort scheme (persisted via NE.db.combinedbag). "category" = the smart default; others are simple.
CB._sortMode = CB._sortMode or "category"
-- Red-tint items the player can't use. Default on (opt-out). Persisted.
if CB._redUnusable == nil then CB._redUnusable = true end
-- Auto-sell grey (junk) items when a merchant opens. Default OFF (opt-in — it spends items). Persisted.
if CB._autoSellJunk == nil then CB._autoSellJunk = false end
-- Auto-empty & swap when equipping a bag over a non-empty one. Default on (opt-out). Persisted.
if CB._autoEmptyBag == nil then CB._autoEmptyBag = true end

-- Category rank for the smart sort (enUS fallback): weapons before armor, quest, consumables,
-- materials, recipes, then everything else.
local CAT_RANK = {
  Weapon = 1, Armor = 2, Quest = 3, Consumable = 4,
  ["Trade Goods"] = 5, Gem = 5, Projectile = 5, Quiver = 5, Reagent = 5, Recipe = 6,
}
-- Locale-independent category rank. GetItemInfo's itemType is LOCALISED, so keying CAT_RANK by the
-- English string only ranks correctly on enUS. GetAuctionItemClasses() returns the class names in a
-- FIXED index order on every locale — 1 Weapon, 2 Armor, 3 Container, 4 Consumable, 5 Glyph,
-- 6 Trade Goods, 7 Projectile, 8 Quiver, 9 Recipe, 10 Gem, 11 Miscellaneous, 12 Quest — so we map
-- each localised name to a rank by its index (built once, lazily). Falls back to the enUS table.
local RANK_BY_CLASS_INDEX = { 1, 2, 6, 4, 5, 5, 5, 5, 6, 5, 7, 3 }
local classRankMap
local function classRank(itemType)
  if not itemType then return 7 end
  if not classRankMap then
    classRankMap = {}
    if GetAuctionItemClasses then
      local names = { GetAuctionItemClasses() }
      for i = 1, #names do classRankMap[names[i]] = RANK_BY_CLASS_INDEX[i] or 7 end
    end
  end
  return classRankMap[itemType] or CAT_RANK[itemType] or 7
end
-- The Hearthstone is pinned to the very front of the category (smart) sort (rank below any CAT_RANK).
local HEARTHSTONE_ID = 6948

-- Canonical, deterministic sort key for an item (higher quality / item level first; usable before
-- unusable; name then itemID break ties → the sort is stable and idempotent). Honours CB._sortMode.
local function sortKey(link, itemID)
  local name, _, quality, iLvl, _, itemType, itemSubType = GetItemInfo(link or itemID)
  if not name then return string.format("~~|%08d", itemID or 0) end   -- uncached → sort last
  name, quality, iLvl = name:lower(), quality or 1, iLvl or 0
  local mode = CB._sortMode
  if mode == "name" then
    return string.format("%s|%08d", name, itemID or 0)
  elseif mode == "quality" then
    return string.format("%02d|%s|%08d", 99 - quality, name, itemID or 0)
  elseif mode == "ilvl" then
    return string.format("%04d|%s|%08d", 9999 - math.min(iLvl, 9999), name, itemID or 0)
  end
  -- category (default): category > SUBTYPE > usable > item level > quality > name > id. Grouping by
  -- subtype keeps like with like (all swords, all cloth, all potions together) — nicer in general AND
  -- specialty bags. Hearthstone is pinned to rank 0 so it always lands in the first slot.
  local cat = (itemID == HEARTHSTONE_ID) and 0 or classRank(itemType)
  local usable = 1
  if IsUsableItem then local u = IsUsableItem(link or itemID); usable = u and 0 or 1 end
  return string.format("%d|%s|%d|%04d|%02d|%s|%08d",
    cat, (itemSubType or ""):lower(), usable, 9999 - math.min(iLvl, 9999), 99 - quality, name, itemID or 0)
end

-- Small icon button for the header row (sort / options): dark backing, ADD highlight, tooltip.
-- `spec` = { atlas = "name" }  (a registered atlas, e.g. the grey cog "questlog-icon-setting"), OR
--          { path = "Interface\\..." [, trim=true] [, desaturate=true] }  (a plain texture/icon).
--   atlasSize = true → draw the atlas at its NATIVE size, centred (spellbook-cog look), instead of
--                      stretching it to fill the button.
--   noBg      = true → skip the dark backing square (bare icon, like the spellbook cog).
local function makeHeaderButton(parent, spec, tooltip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetFrameLevel((parent:GetFrameLevel() or 1) + 25)
  if not spec.noBg then
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetTexture(0, 0, 0, 0.4)
  end
  local icon = b:CreateTexture(nil, "ARTWORK")
  local atlasOK = spec.atlas and NE.tex and NE.tex.SetAtlas
    and NE.tex.SetAtlas(icon, spec.atlas, spec.atlasSize and true or false)
  if spec.atlasSize and atlasOK then
    icon:SetPoint("CENTER")                                -- native atlas size, centred (SetAtlas sized it)
  else
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
  end
  if not atlasOK then
    icon:SetTexture(spec.path)
    if spec.trim ~= false then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end   -- trim the icon's built-in border
  end
  if spec.desaturate and icon.SetDesaturated then icon:SetDesaturated(true) end
  b.icon = icon
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(icon)
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(tooltip or "")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- ----------------------------------------------------------------------------
-- Bottom money band: a thin engraved divider + a full-width band carrying the watched-currency
-- token pills (left) and the player MoneyFrame (right). Built once, repopulated on refresh.
-- ----------------------------------------------------------------------------
-- One currency pill: [count][icon] on the money band. Pooled on band._pills.
local function getTokenPill(band, index)
  local pill = band._pills[index]
  if pill then return pill end

  pill = CreateFrame("Frame", nil, band)
  pill:SetHeight(BAND_H)
  pill:SetFrameLevel(band:GetFrameLevel() + 1)

  -- No box border: the common-currencybox art renders with a green edge on this client, so we show
  -- the currency as a bare icon + count on the band. capW is kept only as left/right text padding.
  local capW = math.floor(16 * BAND_H / 34 + 0.5)

  pill.icon = pill:CreateTexture(nil, "ARTWORK")
  pill.icon:SetSize(14, 14)
  pill.icon:SetPoint("RIGHT", pill, "RIGHT", -6, 0)
  pill.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  pill.count = pill:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  pill.count:SetPoint("RIGHT", pill.icon, "LEFT", -3, 0)
  pill.count:SetJustifyH("RIGHT")

  -- Hover → the native backpack-token tooltip + a "shift-right-click to stop watching" hint.
  -- Shift+right-click → untrack this currency (mirrors the character Currency tab's watch checkbox).
  pill:EnableMouse(true)
  pill:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self._backpackIndex and GameTooltip.SetBackpackToken
       and pcall(GameTooltip.SetBackpackToken, GameTooltip, self._backpackIndex) then
      -- native tooltip set
    else
      GameTooltip:SetText(self._name or "", 1, 1, 1)
    end
    GameTooltip:AddLine(NE.L["Shift-right-click to stop watching"], 0.2, 1, 0.2)
    GameTooltip:Show()
  end)
  pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pill:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
      CB.UntrackCurrency(self._itemID, self._name)
    end
  end)

  pill._capW = capW
  band._pills[index] = pill
  return pill
end

local function buildMoneyBand(parent)
  if parent._moneyBand then return parent._moneyBand end

  -- Engraved divider between the item grid and the band (a dark line + a faint highlight under it).
  local divShadow = parent:CreateTexture(nil, "ARTWORK")
  divShadow:SetTexture(0, 0, 0, 0.55)
  divShadow:SetHeight(1)
  divShadow:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  LEFT_PADDING,  BAND_H + BAND_BOTTOM_GAP + 3)
  divShadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -RIGHT_PADDING, BAND_H + BAND_BOTTOM_GAP + 3)
  local divHi = parent:CreateTexture(nil, "ARTWORK")
  divHi:SetTexture(1, 1, 1, 0.06)
  divHi:SetHeight(1)
  divHi:SetPoint("TOPLEFT",  divShadow, "BOTTOMLEFT",  0, 0)
  divHi:SetPoint("TOPRIGHT", divShadow, "BOTTOMRIGHT", 0, 0)

  local band = CreateFrame("Frame", "NE_CombinedBagMoneyBand", parent)
  band:SetHeight(BAND_H)
  band:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  LEFT_PADDING,  BAND_BOTTOM_GAP)
  band:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -RIGHT_PADDING, BAND_BOTTOM_GAP)
  band:SetFrameLevel((parent:GetFrameLevel() or 1) + 6)
  band._pills = {}

  -- Player money, docked to the RIGHT of the band. Native SmallMoneyFrame (self-updates on PLAYER_MONEY).
  local money = CreateFrame("Frame", "NE_CombinedBagMoneyFrame", band, "SmallMoneyFrameTemplate")
  money:SetPoint("RIGHT", band, "RIGHT", -2, 0)
  if MoneyFrame_SetType then pcall(MoneyFrame_SetType, money, "PLAYER") end
  if MoneyFrame_SetMaxDisplayWidth then pcall(MoneyFrame_SetMaxDisplayWidth, money, 168) end
  band.money = money
  parent.moneyFrame = money

  parent._moneyBand = band
  return band
end

-- Repopulate the currency pills from the watched-token API (3.3.5a shape:
-- name, count, extraCurrencyType, icon, itemID — icon at position 4). Lays them out left→right.
local function updateMoneyBand(parent)
  local band = parent._moneyBand
  if not band then return end
  if not GetBackpackCurrencyInfo then
    for _, p in ipairs(band._pills) do p:Hide() end
    return
  end

  local shown = 0
  local prev
  for i = 1, MAX_TOKENS do
    local name, count, _, icon, itemID = GetBackpackCurrencyInfo(i)
    if name and icon then
      shown = shown + 1
      local pill = getTokenPill(band, shown)
      pill._name, pill._itemID, pill._backpackIndex = name, itemID, i
      pill.icon:SetTexture(icon)
      pill.count:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(count or 0) or (count or 0))
      -- Width = left cap + count text + gap + icon + right cap + insets.
      local w = pill._capW + (pill.count:GetStringWidth() or 0) + 3 + 14 + 6 + pill._capW
      pill:SetWidth(math.max(w, 34))
      pill:ClearAllPoints()
      if prev then pill:SetPoint("LEFT", prev, "RIGHT", 6, 0)
      else pill:SetPoint("LEFT", band, "LEFT", 0, 0) end
      pill:Show()
      prev = pill
    end
  end
  for i = shown + 1, #band._pills do band._pills[i]:Hide() end
end
CB.UpdateMoneyBand = updateMoneyBand

-- Stop watching a currency on the backpack. SetCurrencyBackpack indexes the CURRENCY LIST (not the
-- backpack), and that list hides children under collapsed headers — so we expand every header, find
-- the entry by itemID (fallback name), untrack it, then restore the headers we opened. Also refreshes
-- the character Currency tab so its watch checkbox reflects the change.
function CB.UntrackCurrency(itemID, name)
  if not (SetCurrencyBackpack and GetCurrencyListSize and GetCurrencyListInfo) then return end

  -- Expand all collapsed headers (remember them by name — list indices shift as we expand).
  local reCollapse = {}
  if ExpandCurrencyList then
    local i, size = 1, (GetCurrencyListSize() or 0)
    while i <= size do
      local nm, isHeader, isExpanded = GetCurrencyListInfo(i)
      if isHeader and not isExpanded then
        reCollapse[#reCollapse + 1] = nm
        pcall(ExpandCurrencyList, i, 1)
        size = GetCurrencyListSize() or 0
      end
      i = i + 1
    end
  end

  -- Find + untrack (itemID is the 9th return of GetCurrencyListInfo; match name as a fallback).
  for j = 1, (GetCurrencyListSize() or 0) do
    local nm, isHeader, _, _, _, _, _, _, iid = GetCurrencyListInfo(j)
    if not isHeader and ((itemID and iid == itemID) or (name and nm == name)) then
      pcall(SetCurrencyBackpack, j, 0)
      break
    end
  end

  -- Re-collapse the headers we opened (untracking doesn't reshape the list, so a name match is safe).
  if ExpandCurrencyList then
    for _, hn in ipairs(reCollapse) do
      for j = 1, (GetCurrencyListSize() or 0) do
        local nm, isHeader, isExpanded = GetCurrencyListInfo(j)
        if isHeader and isExpanded and nm == hn then pcall(ExpandCurrencyList, j, 0); break end
      end
    end
  end

  CB.Refresh()
  if NE.charpanel and NE.charpanel.RefreshCurrency then NE.charpanel.RefreshCurrency() end
end

-- ----------------------------------------------------------------------------
-- Build the window chrome + grid once.
-- ----------------------------------------------------------------------------
local function buildChrome()
  if frame then return frame end
  if not G then log("NE.itemgrid missing (core/ItemGrid.lua not loaded); combined bag unavailable"); return nil end

  frame = CreateFrame("Frame", "NE_CombinedBagFrame", UIParent)
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, frame) end
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:Hide()

  -- Dark rock Bg + metal border, then the warm-dark backpack texture over the fill.
  if NE.chrome and NE.chrome.ApplyModernChrome then
    pcall(NE.chrome.ApplyModernChrome, frame, "HeldBagLayout")
  end
  if NE.bagskin and NE.bagskin.ApplyWindowBackground then
    pcall(NE.bagskin.ApplyWindowBackground, frame)
  end

  -- Portrait (the generic bag icon) seated into the metal corner cutout.
  local portrait = frame:CreateTexture(nil, "ARTWORK")
  if NE.portrait and NE.portrait.ApplyCutout then
    -- Fill the metal ring, centred on it — same size/anchor the character panel uses for this exact
    -- PortraitMetal corner (size 60 seated at TOPLEFT{-5,8} → centred on the ring circle).
    pcall(NE.portrait.ApplyCutout, portrait, frame,
      { size = 60, layer = "ARTWORK", anchor = { "TOPLEFT", -5, 8 }, maskInset = { 1, 0, -1, 2 } })
  end
  -- Circular crop: SetPortraitToTexture zooms the square icon so the round metal ring reads circular
  -- (3.3.5a has no real mask). Called AFTER ApplyCutout so its texcoord wins.
  if SetPortraitToTexture then
    SetPortraitToTexture(portrait, PORTRAIT_BAG_ASSET)
  else
    portrait:SetTexture(PORTRAIT_BAG_ASSET)
  end
  frame.portrait = portrait

  -- Title — route through the shared panel-chrome title styling (NE.panelchrome.SetTitle) so the
  -- header aligns EXACTLY like the character/spellbook windows: GameFontNormal gold, hosted on the
  -- title band (between the portrait and close button) and anchored TOP/LEFT/RIGHT so it centres in
  -- that span. (Previously a hand-rolled single -3 TOP anchor sat slightly off vs the other windows.)
  local title
  if NE.panelchrome and NE.panelchrome.TitleBand and NE.panelchrome.SetTitle then
    local band = NE.panelchrome.TitleBand(frame)
    title = band:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Title = title                                   -- SetTitle resolves frame.Title on later calls
    NE.panelchrome.SetTitle(frame, TITLE_TEXT, title, band)
  else
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetJustifyH("CENTER")
    title:SetText(TITLE_TEXT)
  end
  frame.title = title

  -- Header buttons: Sort + Bag-options menu, on the RIGHT of the search row. Right edge aligns with
  -- the item grid's right edge (LEFT_PADDING gutter); 7px gaps between them and the search box —
  -- matching the item-slot gap. Vertically centred on the 18px search row (top -32, h 22, mid -43).
  local HDR_BTN = 22
  local ROW_MID = -43   -- vertical centre of the 24px search row (top -31) → keep both buttons on it
  -- Options cog: the spellbook cog's exact size + look (16x18, native-size icon, no dark backing).
  -- Left-click toggles the bag-options menu open/closed (CB.ToggleMenu).
  local menuBtn = makeHeaderButton(frame,
    { atlas = "questlog-icon-setting", atlasSize = true, noBg = true }, NE.L["Bag Options"],
    function(self) CB.ToggleMenu(self) end)
  menuBtn:SetSize(16, 18)
  menuBtn:SetPoint("RIGHT", frame, "TOPRIGHT", -LEFT_PADDING, ROW_MID)
  local sortBtn = makeHeaderButton(frame,
    { path = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\inv_pet_broom.blp" },
    NE.L["Sort Bags"], function() CB.SortBags() end)
  sortBtn:SetSize(HDR_BTN, HDR_BTN)
  sortBtn:SetPoint("RIGHT", menuBtn, "LEFT", -ITEM_SPACING_X + 4, 0)   -- ~7px visual gap, same centre line
  frame.sortButton, frame.menuButton = sortBtn, menuBtn

  -- Search box — the spellbook's modern self-contained style: a bare EditBox with a tooltip-art
  -- backdrop + magnifier + separate placeholder (NOT InputBoxTemplate/SearchBoxTemplate, which other
  -- addons redefine and can break). Placeholder uses the localized SEARCH global.
  local search = CreateFrame("EditBox", "NE_CombinedBagSearch", frame)
  search:SetAutoFocus(false)
  search:SetHeight(24)
  search:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -31)
  search:SetPoint("RIGHT", sortBtn, "LEFT", -ITEM_SPACING_X + 4, 0)   -- leave room for the buttons, ~7px gap
  search:SetFrameLevel((frame:GetFrameLevel() or 1) + 25)
  search:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
  search:SetTextInsets(24, 8, 0, 0)   -- room for the magnifier at the left
  search:SetMaxLetters(40)
  if search.SetBackdrop then
    search:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    search:SetBackdropColor(0, 0, 0, 0.6)
    search:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end
  local mag = search:CreateTexture(nil, "OVERLAY")
  mag:SetSize(14, 14)
  mag:SetPoint("LEFT", search, "LEFT", 7, 0)
  mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  local ph = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  ph:SetPoint("LEFT", search, "LEFT", 24, 0)
  ph:SetText((SEARCH or NE.L["Search"]) or "Search")
  local function syncPlaceholder()
    if (search:GetText() or "") == "" and not search:HasFocus() then ph:Show() else ph:Hide() end
  end
  search:SetScript("OnTextChanged", function(self)
    CB._searchText = self:GetText() or ""
    syncPlaceholder()
    CB.Refresh()
  end)
  search:SetScript("OnEditFocusGained", syncPlaceholder)
  search:SetScript("OnEditFocusLost", syncPlaceholder)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  syncPlaceholder()
  frame.search = search

  -- Close button (build + modernize). OnClick hides the window.
  local close = CreateFrame("Button", "NE_CombinedBagCloseButton", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
  close:SetScript("OnClick", function() CB.Hide() end)
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    pcall(NE.panelchrome.ModernizeCloseButton, close, { frameLevelBump = 10 })
  end
  frame.closeButton = close

  -- Bottom money band: divider + currency token pills (left) + player money (right).
  buildMoneyBand(frame)

  -- The grid over the held bags, ordered by TYPE (general first), filling top-left → bottom-right so
  -- regular items cluster first and specialty bags (quiver/soul/profession) group after.
  grid = G.New{
    host          = frame,
    containers    = function()
      -- When "separate specialty bags" is on, the MAIN grid holds only general bags (family 0); the
      -- specialty bags each get their own labeled section (see the spec sections in refresh()).
      local t = {}
      for _, bd in ipairs(orderedBags()) do
        if (not CB.SeparateBags()) or bd.family == 0 then t[#t + 1] = bd.bag end
      end
      return t
    end,
    columns       = COLUMNS,
    itemSize      = ITEM_SIZE,
    spacingX      = ITEM_SPACING_X,
    spacingY      = ITEM_SPACING_Y,
    originX       = LEFT_PADDING,
    originY       = -TOP_HEADER,
    direction     = "TLBR",
    slotDescending = false,
    namePrefix    = "NE_CombinedItem",
    frameLevel    = function() return (frame:GetFrameLevel() or 1) + 5 end,
  }
  CB.grid = grid

  -- Keyring row: a second grid over container -2, laid out under the main grid (positioned per refresh).
  -- Its container list is empty unless the "Show keyring row" option is on, so it's a no-op when off.
  keyGrid = G.New{
    host       = frame,
    containers = function() return CB.ShowKeys() and { KEYRING_CONTAINER } or {} end,
    slotCount  = function(c)
      if c == KEYRING_CONTAINER then
        return (GetKeyRingSize and GetKeyRingSize())
            or (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(c)) or 0
      end
      return (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(c)) or 0
    end,
    columns    = COLUMNS,
    itemSize   = ITEM_SIZE,
    spacingX   = ITEM_SPACING_X,
    spacingY   = ITEM_SPACING_Y,
    originX    = LEFT_PADDING,
    originY    = -TOP_HEADER,   -- repositioned each refresh, below the main grid
    direction  = "TLBR",
    namePrefix = "NE_CombinedKey",
    frameLevel = function() return (frame:GetFrameLevel() or 1) + 5 end,
  }
  CB.keyGrid = keyGrid

  -- "Keys" label above the keyring row (shown only when the row has slots and the option is on).
  local keysLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  keysLabel:SetText(string.upper(NE.L["Keys"] or "Keys"))   -- UPPERCASE, matching the specialty-bag headers
  keysLabel:SetTextColor(1, 0.82, 0)
  keysLabel:Hide()
  frame._keysLabel = keysLabel

  -- Sorting cover: an opaque panel over the grid, shown while a sort runs, so the item shuffle is
  -- invisible — the player sees "Sorting…" then the finished layout. Also blocks clicks mid-sort.
  local cover = CreateFrame("Frame", nil, frame)
  cover:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(TOP_HEADER - 2))
  cover:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  cover:SetFrameLevel((frame:GetFrameLevel() or 1) + 40)
  cover:EnableMouse(true)
  -- No opaque fill: during a sort we HIDE the item buttons/slots directly (see SortBags), so the bag's
  -- own marble background shows through with just the spinner + label floating over it.

  -- Center zone: spans [bottom of the search bar .. the currency divider], NOT the whole cover (which
  -- also overlays the money band). Anchoring the spinner/label to THIS zone's center keeps them
  -- centered in that band for any row count (2 rows or 18) — the top is pinned to the search bar's
  -- bottom edge and the bottom to the divider (a fixed BAND_H + BAND_BOTTOM_GAP + 3 above the frame
  -- bottom), so the midpoint tracks the real height difference instead of drifting low.
  local centerZone = CreateFrame("Frame", nil, cover)
  centerZone:SetPoint("LEFT",   cover,  "LEFT",   0, 0)
  centerZone:SetPoint("RIGHT",  cover,  "RIGHT",  0, 0)
  centerZone:SetPoint("TOP",    search, "BOTTOM", 0, 0)                              -- top = bottom of the search bar
  centerZone:SetPoint("BOTTOM", frame,  "BOTTOM", 0, BAND_H + BAND_BOTTOM_GAP + 3)   -- bottom = currency divider

  -- Retail-style loading spinner (Stream* art ported from ezCollections): static gold background +
  -- frame, with a gold circle + spark that rotate continuously via a looping Rotation animation.
  local TEX = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\"
  local spinner = CreateFrame("Frame", nil, cover)
  spinner:SetSize(48, 48)
  spinner:SetPoint("CENTER", centerZone, "CENTER", 0, 12)
  local sbg = spinner:CreateTexture(nil, "BACKGROUND")
  sbg:SetAllPoints(); sbg:SetTexture(TEX .. "StreamBackground.tga"); sbg:SetVertexColor(1, 0.82, 0)
  local sframe = spinner:CreateTexture(nil, "ARTWORK")
  sframe:SetAllPoints(); sframe:SetTexture(TEX .. "StreamFrame.tga")
  local anim = CreateFrame("Frame", nil, spinner)
  anim:SetAllPoints()
  local scircle = anim:CreateTexture(nil, "BACKGROUND")
  scircle:SetAllPoints(); scircle:SetTexture(TEX .. "StreamCircle.tga"); scircle:SetVertexColor(1, 0.82, 0)
  local sspark = anim:CreateTexture(nil, "OVERLAY")
  sspark:SetAllPoints(); sspark:SetTexture(TEX .. "StreamSpark.tga")
  local ag = anim:CreateAnimationGroup()
  ag:SetLooping("REPEAT")
  local rot = ag:CreateAnimation("Rotation")
  rot:SetDegrees(-360); rot:SetDuration(1); rot:SetOrder(1)
  cover.spinnerAnim = ag

  local clabel = cover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  clabel:SetPoint("TOP", spinner, "BOTTOM", 0, -8)
  clabel:SetText(NE.L["Sorting…"])
  clabel:SetTextColor(1, 0.82, 0)
  cover.label = clabel

  -- Spin only while the cover is shown.
  cover:SetScript("OnShow", function(self) if self.spinnerAnim then self.spinnerAnim:Play() end end)
  cover:SetScript("OnHide", function(self) if self.spinnerAnim then self.spinnerAnim:Stop() end end)
  cover:Hide()
  frame.sortCover = cover

  -- Movable + persisted position + ESC close.
  if NE.FrameUtil then
    if NE.FrameUtil.PersistWindowPosition then
      NE.FrameUtil.PersistWindowPosition(frame, "combinedbag",
        { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -25, y = 85 })
    else
      frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -25, 85)
    end
    if NE.FrameUtil.EscClose then NE.FrameUtil.EscClose("NE_CombinedBagFrame") end
  else
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -25, 85)
  end

  -- Per-window scaling via NE.scale (mode: ui / none / custom; options tab > Window Scaling). Same
  -- "combinedbag" key PersistWindowPosition uses above. DEFAULTS["combinedbag"] is "ui" = a plain
  -- SetScale(1.0), i.e. exactly what this window did before it had a setting. Applied AFTER the
  -- position is restored so the anchor is already in place when the scale lands on it.
  if NE.scale and NE.scale.Apply then
    if NE.scale.SetFrame then NE.scale.SetFrame("combinedbag", frame) end
    NE.scale.Apply("combinedbag")
  end

  return frame
end
CB.BuildChrome = buildChrome

-- ----------------------------------------------------------------------------
-- Refresh the grid + size the window to fit.
-- ----------------------------------------------------------------------------
-- Does the item in (bag,slot) match the search text? Empty slots never match while searching.
function CB.SlotMatches(bagID, slot, text)
  if not text or text == "" then return true end
  if not (bagID and slot and C_Container and C_Container.GetContainerItemInfo) then return false end
  local info = C_Container.GetContainerItemInfo(bagID, slot)
  local key = info and (info.hyperlink or info.itemID)
  if not key then return false end
  local name = info.name
  if not name and GetItemInfo then name = GetItemInfo(key) end
  if not name then return true end   -- name not cached yet: don't hide it
  return name:lower():find(text:lower(), 1, true) ~= nil
end

-- ----------------------------------------------------------------------------
-- Specialty-bag sections ("separate specialty bags" option). One labeled section per bag family the
-- player carries (quiver, ammo pouch, soul bag, herb/mining/… profession bags), stacked below the
-- general grid, mirroring the keyring row. Grids are created lazily and cached per family.
-- ----------------------------------------------------------------------------
-- UPPERCASE fallback names per bag family bit (used only if the bag's localized subtype isn't cached).
local FAMILY_NAME = {
  [1]    = "QUIVER",            [2]   = "AMMO POUCH",      [4]   = "SOUL BAG",
  [8]    = "LEATHERWORKING BAG", [16] = "INSCRIPTION BAG", [32]  = "HERB BAG",
  [64]   = "ENCHANTING BAG",    [128] = "ENGINEERING BAG", [512] = "GEM BAG",
  [1024] = "MINING BAG",
}
-- Ordered list of the specialty families the player currently has a bag for.
local function activeSpecFamilies()
  local seen, list = {}, {}
  for _, bd in ipairs(orderedBags()) do
    if bd.family ~= 0 and not seen[bd.family] then seen[bd.family] = true; list[#list + 1] = bd.family end
  end
  table.sort(list)
  return list
end
-- Section header text: the bag's own localized subtype (e.g. "Mining Bag"), UPPERCASED; static fallback.
local function familyLabel(family)
  if ContainerIDToInventoryID and GetInventoryItemLink and GetItemInfo then
    for _, bd in ipairs(orderedBags()) do
      if bd.family == family then
        local link = GetInventoryItemLink("player", ContainerIDToInventoryID(bd.bag))
        local sub = link and select(7, GetItemInfo(link))
        if sub and sub ~= "" then return string.upper(sub) end
      end
    end
  end
  return FAMILY_NAME[family] or "OTHER"
end
-- Lazily create + cache a { grid, label } section for a family. The grid holds that family's bags only
-- while "separate specialty bags" is on (else its container list is empty → a no-op row).
local specSections = {}
local function getSpecSection(family)
  local sec = specSections[family]
  if sec then return sec end
  local g = G.New{
    host       = frame,
    containers = function()
      if not CB.SeparateBags() then return {} end
      local t = {}
      for _, bd in ipairs(orderedBags()) do
        if bd.family == family then t[#t + 1] = bd.bag end
      end
      return t
    end,
    columns    = COLUMNS, itemSize = ITEM_SIZE, spacingX = ITEM_SPACING_X, spacingY = ITEM_SPACING_Y,
    originX    = LEFT_PADDING, originY = -TOP_HEADER, direction = "TLBR",
    namePrefix = "NE_CombinedSpec" .. tostring(family),
    frameLevel = function() return (frame:GetFrameLevel() or 1) + 5 end,
  }
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetTextColor(1, 0.82, 0)
  label:Hide()
  sec = { grid = g, label = label }
  specSections[family] = sec
  return sec
end

local function refresh()
  if not frame or not frame:IsShown() or not grid then return end
  if CB._sorting then return end   -- frozen under the sort cover; one repaint runs when the sort ends
  local _, _, contentW, contentH = grid:Refresh()

  -- Skin every slot button the grid just laid out: recessed cavity + quality ring + search dim.
  -- The grid stamps btn._bagID/_slotID, so we colour quality + test search from live container info.
  local text = CB._searchText
  local searching = text and text ~= ""
  if NE.bagskin and grid.ForEachButton then
    grid:ForEachButton(function(b)
      NE.bagskin.SkinButton(b, ITEM_SIZE)
      NE.bagskin.ApplyQuality(b, b._bagID, b._slotID)
      NE.bagskin.ApplyUsableTint(b, b._bagID, b._slotID, CB._redUnusable)
      NE.bagskin.SetSearchDim(b, searching and not CB.SlotMatches(b._bagID, b._slotID, text))
      NE.bagskin.ApplyItemLevel(b, b._bagID, b._slotID)
    end)
  end

  contentW = contentW or (COLUMNS * ITEM_SIZE + (COLUMNS - 1) * ITEM_SPACING_X)
  contentH = contentH or 0

  -- Specialty-bag sections (opt-in): stack a labeled grid per bag family below the general grid.
  -- flowH tracks the running height below the header; maxW the widest section (drives window width).
  local flowH, maxW = contentH, contentW
  local activeFam = {}
  if CB.SeparateBags() then
    for _, family in ipairs(activeSpecFamilies()) do
      activeFam[family] = true
      local sec = getSpecSection(family)
      local topY = -(TOP_HEADER + flowH + KEYS_TOP_GAP)
      sec.grid.originY = topY - KEYS_LABEL_H
      local _, rows, w, h = sec.grid:Refresh()
      if NE.bagskin and sec.grid.ForEachButton then
        sec.grid:ForEachButton(function(b)
          NE.bagskin.SkinButton(b, ITEM_SIZE)
          NE.bagskin.ApplyQuality(b, b._bagID, b._slotID)
          NE.bagskin.ApplyUsableTint(b, b._bagID, b._slotID, CB._redUnusable)
          NE.bagskin.SetSearchDim(b, searching and not CB.SlotMatches(b._bagID, b._slotID, text))
          NE.bagskin.ApplyItemLevel(b, b._bagID, b._slotID)
        end)
      end
      if (rows or 0) > 0 then
        sec.label:SetText(familyLabel(family))
        sec.label:ClearAllPoints()
        sec.label:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_PADDING, topY)
        sec.label:Show()
        flowH = flowH + KEYS_TOP_GAP + KEYS_LABEL_H + (h or 0)
        maxW  = math.max(maxW, w or 0)
      else
        sec.label:Hide()
      end
    end
  end
  -- Hide any cached section whose family is no longer active (or when the option is off) — its empty
  -- container list makes the Refresh hide the slot buttons.
  for family, sec in pairs(specSections) do
    if not activeFam[family] then
      sec.label:Hide()
      sec.grid:Refresh()
    end
  end

  -- Keyring row (opt-in): sit it just under the last section, with a "Keys" label above it. keyGrid's
  -- container list is empty when the option is off, so this is a no-op (0 rows) then. originY is set
  -- LIVE each refresh so the row tracks the grid stack's height.
  local keysSectionH = 0
  if keyGrid then
    local keysTopY = -(TOP_HEADER + flowH + KEYS_TOP_GAP)
    keyGrid.originY = keysTopY - KEYS_LABEL_H
    local _, keyRows, _, keyH = keyGrid:Refresh()
    if NE.bagskin and keyGrid.ForEachButton then
      keyGrid:ForEachButton(function(b)
        NE.bagskin.SkinButton(b, ITEM_SIZE)
        NE.bagskin.ApplyQuality(b, b._bagID, b._slotID)
        NE.bagskin.ApplyUsableTint(b, b._bagID, b._slotID, CB._redUnusable)
        NE.bagskin.SetSearchDim(b, searching and not CB.SlotMatches(b._bagID, b._slotID, text))
        NE.bagskin.ApplyItemLevel(b, b._bagID, b._slotID)
      end)
    end
    if CB.ShowKeys() and (keyRows or 0) > 0 then
      keysSectionH = KEYS_TOP_GAP + KEYS_LABEL_H + (keyH or 0)
      if frame._keysLabel then
        frame._keysLabel:ClearAllPoints()
        frame._keysLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_PADDING, keysTopY)
        frame._keysLabel:Show()
      end
    elseif frame._keysLabel then
      frame._keysLabel:Hide()
    end
  end

  -- Repopulate the currency pills, then reserve room below the grid (+ keys section) for the divider +
  -- money band (BAND_RESERVE = top gap + band height + bottom gap) so the bottom breathes like retail.
  updateMoneyBand(frame)
  frame:SetSize(maxW + PADDING_WIDTH, flowH + TOP_HEADER + keysSectionH + BAND_RESERVE)
end
CB.Refresh = refresh

-- Repaint when DragonUI's item level settings change. Its RefreshItemLevel hides EVERY text it owns
-- (ours included — our slots' FontStrings live in its own registry) and then re-runs only ITS update
-- paths, which don't know about this grid. Without this hook, turning the setting back on, or
-- changing the font or position, leaves our slots blank until the next bag event repaints them.
do
  local dragon = NE.dragon
  local function repaintIfOpen()
    if frame and frame:IsShown() then pcall(refresh) end
  end
  if dragon and type(dragon.RefreshItemLevel) == "function" then
    hooksecurefunc(dragon, "RefreshItemLevel", repaintIfOpen)
  end
  if dragon and type(dragon.RefreshItemLevelPosition) == "function" then
    hooksecurefunc(dragon, "RefreshItemLevelPosition", repaintIfOpen)
  end
end

-- ----------------------------------------------------------------------------
-- Show / hide / toggle. Showing suppresses the stock container frames.
-- ----------------------------------------------------------------------------
local function hideStockFrames()
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local f = _G["ContainerFrame" .. i]
    if f and f:IsShown() then f:Hide() end
  end
end

function CB.Show()
  if not buildChrome() then return end
  local wasShown = frame:IsShown()
  hideStockFrames()
  -- Open with a clean search: clear the box + filter and drop focus so the placeholder shows again.
  CB._searchText = ""
  if frame.search then
    frame.search:SetText("")
    frame.search:ClearFocus()
  end
  frame:Show()
  frame:Raise()
  refresh()
  -- Bag-open whoosh. The stock ContainerFrames play this on show, but the combined bag suppresses
  -- them and replaces the open globals, so we have to play it ourselves (issue #12). Only on an
  -- actual hidden->shown transition — a re-Show of an already-open bag (e.g. loot opening a
  -- container while bags are up) must not re-trigger it.
  if not wasShown and PlaySound then pcall(PlaySound, "igBackPackOpen") end
end

function CB.Hide()
  if not (frame and frame:IsShown()) then
    if frame then frame:Hide() end
    return
  end
  frame:Hide()
  if PlaySound then pcall(PlaySound, "igBackPackClose") end
end

function CB.IsShown()
  return frame and frame:IsShown() and true or false
end

function CB.Toggle()
  if CB.IsShown() then CB.Hide() else CB.Show() end
end

-- ----------------------------------------------------------------------------
-- Sort. Best-effort, bag-TYPE aware:
--   1. Gather held items with their family (GetItemFamily) + a quality>name>id key (reversible).
--   2. Assign each item a target slot in a bag it FITS — specialty items prefer their specialty bag,
--      everything else fills general bags. Never targets a bag that can't hold the item (so regular
--      items never land in a quiver / profession bag).
--   3. Realize the assignment via swaps. The game itself rejects any invalid placement, so a busy
--      server just leaves a few items unmoved rather than mis-filing them.
-- Out-of-combat only; bails if any item is mid-transfer (locked) — re-click after it settles.
-- ----------------------------------------------------------------------------
-- One selection-sort PASS toward the deterministic target. Partitions slots into a general pool +
-- one pool per specialty bag (so every swap stays within compatible bags), sorts each pool's items,
-- then moves what it can — skipping LOCKED items (mid server round-trip) and their slots. Returns the
-- number of slots still not matching their target, so the driver knows when to stop.
-- PLAN the sort ONCE (offline, separate from the live bag): snapshot slots + items, partition into a
-- general pool + one pool per specialty bag, sort each pool, and bake the itemID that should end up
-- in each slot. Returns groups = { { slots = {{bag,slot}...}, want = { itemID-or-nil per slot } } }.
-- The expensive work (GetItemInfo / sortKey / GetItemFamily) happens here, ONCE — not per pass.
local function buildSortPlan()
  local generalGroup = { slots = {}, family = 0, items = {} }
  local groups, specGroups, famGroups = { generalGroup }, {}, {}
  -- Pool specialty slots BY FAMILY (not per bag) so two quivers / two herb bags share one pool and an
  -- item can fill either. General bags (family 0, incl. the backpack) form the general pool.
  for _, bd in ipairs(orderedBags()) do
    local n = C_Container.GetContainerNumSlots(bd.bag) or 0
    if bd.family == 0 then
      for s = 1, n do generalGroup.slots[#generalGroup.slots + 1] = { bag = bd.bag, slot = s } end
    else
      local g = famGroups[bd.family]
      if not g then
        g = { slots = {}, family = bd.family, items = {} }
        famGroups[bd.family] = g; specGroups[#specGroups + 1] = g; groups[#groups + 1] = g
      end
      for s = 1, n do g.slots[#g.slots + 1] = { bag = bd.bag, slot = s } end
    end
  end

  -- Assign every held item to its best home: the specialty pool it fits (arrows→quiver, herbs→herb
  -- bag, soul shards→soul bag, profession mats→that profession's bag, …), else the general pool.
  for _, g in ipairs(groups) do
    for _, sl in ipairs(g.slots) do
      local info = C_Container.GetContainerItemInfo(sl.bag, sl.slot)
      if info and (info.itemID or info.hyperlink) then
        local link = info.hyperlink or info.itemID
        local fam = (GetItemFamily and GetItemFamily(link)) or 0
        local target = generalGroup
        if fam ~= 0 then
          for _, sg in ipairs(specGroups) do
            if itemFitsBag(fam, sg.family) then target = sg; break end
          end
        end
        target.items[#target.items + 1] =
          { id = info.itemID, count = info.stackCount or 1, key = sortKey(link, info.itemID) }
      end
    end
  end

  -- Ordering: by sort key, then FULLER STACKS FIRST so same-item stacks read 20,20,20,8 (not shuffled).
  local function itemLess(a, b)
    if a.key ~= b.key then
      if CB._reverseSort then return a.key > b.key else return a.key < b.key end
    end
    return (a.count or 1) > (b.count or 1)   -- partial stacks sink to the end
  end

  -- Specialty pools fill FIRST; anything that doesn't fit (a full quiver, etc.) spills into general so
  -- nothing is left stranded — the tail (lowest-priority / smallest stacks) is what spills.
  for _, g in ipairs(specGroups) do
    table.sort(g.items, itemLess)
    while #g.items > #g.slots do
      generalGroup.items[#generalGroup.items + 1] = table.remove(g.items)
    end
  end

  for _, g in ipairs(groups) do
    table.sort(g.items, itemLess)
    g.want = {}
    -- Bake the desired itemID AND stack count per slot so the position pass can place the right stack.
    for i = 1, #g.slots do
      local it = g.items[i]
      g.want[i] = it and { id = it.id, count = it.count } or nil
    end
  end
  return groups
end

-- Stack consolidation. One pass: for every stackable item with more than one PARTIAL stack, pour the
-- smallest partial into the largest so partial stacks combine and free whole slots (the position sort
-- then packs the freed space). Moves are client-predicted + locked, so counts go stale after each pour
-- — we do ONE pour per item-type per pass and re-read next pass; returns whether anything moved so the
-- driver knows when stacks are fully consolidated. Same-item pours are always bag-family-legal.
local function mergePass()
  if not (GetItemInfo and PickupContainerItem and C_Container and C_Container.GetContainerNumSlots
          and C_Container.GetContainerItemInfo) then return false end
  if ClearCursor then ClearCursor() end
  local stacks = {}   -- itemID -> { {bag,slot,count,max,locked}, ... } — every non-full partial stack
  for _, bd in ipairs(orderedBags()) do
    local n = C_Container.GetContainerNumSlots(bd.bag) or 0
    for s = 1, n do
      local info = C_Container.GetContainerItemInfo(bd.bag, s)
      if info and info.itemID then
        local maxStack = select(8, GetItemInfo(info.hyperlink or info.itemID))
        local count = info.stackCount or 1
        if maxStack and maxStack > 1 and count < maxStack then
          local t = stacks[info.itemID]; if not t then t = {}; stacks[info.itemID] = t end
          t[#t + 1] = { bag = bd.bag, slot = s, count = count, max = maxStack, locked = info.isLocked }
        end
      end
    end
  end
  local merged, pending = false, false
  for _, list in pairs(stacks) do
    if #list >= 2 then
      local free = {}
      for _, e in ipairs(list) do if not e.locked then free[#free + 1] = e end end
      if #free >= 2 then
        table.sort(free, function(a, b) return a.count > b.count end)   -- largest first
        local dst, src = free[1], free[#free]                          -- pour smallest → largest
        PickupContainerItem(src.bag, src.slot)
        PickupContainerItem(dst.bag, dst.slot)
        if CursorHasItem and CursorHasItem() then ClearCursor() end     -- overflow returns to src
        merged = true
      else
        pending = true   -- ≥2 partials but some are locked mid-move; retry after they settle
      end
    end
  end
  if ClearCursor then ClearCursor() end
  return merged or pending
end

-- Route items into the correct BAG TYPE before arranging. The within-pool position sort only reorders
-- inside a bag; it can't migrate an item from a general bag into its specialty bag — which is why
-- specialty items were all ending up in the general bags. This pass does that migration: any item in
-- the WRONG bag type (a specialty item sitting in a general bag, or a stray general item inside a
-- specialty bag) is moved into a free slot of the bag family it belongs to (arrows→quiver, herbs→herb
-- bag, soul shards→soul bag, …; an item with no matching specialty bag belongs in general). One move
-- per mis-placed item per pass; iterate until nothing migrates, THEN plan + position arranges each bag.
local function routePass()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
          and PickupContainerItem and GetItemFamily) then return false end
  local bags = orderedBags()
  local specFamilies, seen, freeByFamily = {}, {}, {}
  for _, bd in ipairs(bags) do
    if bd.family ~= 0 and not seen[bd.family] then seen[bd.family] = true; specFamilies[#specFamilies + 1] = bd.family end
    freeByFamily[bd.family] = freeByFamily[bd.family] or {}
    local n = C_Container.GetContainerNumSlots(bd.bag) or 0
    for s = 1, n do
      if not C_Container.GetContainerItemInfo(bd.bag, s) then
        local f = freeByFamily[bd.family]; f[#f + 1] = { bag = bd.bag, slot = s }
      end
    end
  end
  -- The bag family an item belongs in: its fitting specialty family, else 0 (general).
  local function targetFamily(link)
    local fam = GetItemFamily(link) or 0
    if fam ~= 0 then
      for _, sf in ipairs(specFamilies) do
        if itemFitsBag(fam, sf) then return sf end
      end
    end
    return 0
  end
  local moved = false
  if ClearCursor then ClearCursor() end
  for _, bd in ipairs(bags) do
    local n = C_Container.GetContainerNumSlots(bd.bag) or 0
    for s = 1, n do
      local info = C_Container.GetContainerItemInfo(bd.bag, s)
      if info and (info.itemID or info.hyperlink) and not info.isLocked then
        local tf = targetFamily(info.hyperlink or info.itemID)
        if tf ~= bd.family then
          local free = freeByFamily[tf]
          if free and #free > 0 then
            local fs = table.remove(free, 1)                 -- a free slot in the right bag type
            PickupContainerItem(bd.bag, s)
            PickupContainerItem(fs.bag, fs.slot)
            if CursorHasItem and CursorHasItem() then ClearCursor() end
            local og = freeByFamily[bd.family]; og[#og + 1] = { bag = bd.bag, slot = s }   -- old slot now free
            moved = true
          end
        end
      end
    end
  end
  if ClearCursor then ClearCursor() end
  return moved
end

-- Sweep loose keys out of the regular bags into the keyring (container -2). Keys carry the keyring bag
-- family (GetItemFamily → the keyring bit) but ALSO fit general bags, so they can sit loose; this moves
-- any that aren't already in the keyring while free keyring slots remain. Runs as part of the sort.
local function routeKeysToKeyRing()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
          and PickupContainerItem and GetItemFamily and GetContainerNumFreeSlots and bit and bit.band) then return false end
  local keyN = (GetKeyRingSize and GetKeyRingSize()) or 0
  if keyN <= 0 then return false end
  local keyFamily = select(2, GetContainerNumFreeSlots(KEYRING_CONTAINER)) or 0
  if keyFamily == 0 then keyFamily = 256 end   -- keyring bag family (fallback if the API reports 0)

  local function isKeyLink(link)
    if not link then return false end
    local fam = GetItemFamily(link) or 0
    if bit.band(fam, keyFamily) ~= 0 then return true end
    if GetItemInfo then return (select(6, GetItemInfo(link))) == "Key" end   -- enUS type fallback
    return false
  end

  -- Free keyring slots to fill.
  local freeKey = {}
  for s = 1, keyN do
    if not C_Container.GetContainerItemInfo(KEYRING_CONTAINER, s) then freeKey[#freeKey + 1] = s end
  end
  if #freeKey == 0 then return false end

  local moved = false
  if ClearCursor then ClearCursor() end
  for bag = 0, NUM_BAG_SLOTS do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for s = 1, n do
      if #freeKey == 0 then break end
      local info = C_Container.GetContainerItemInfo(bag, s)
      if info and (info.itemID or info.hyperlink) and not info.isLocked
         and isKeyLink(info.hyperlink or info.itemID) then
        local dst = table.remove(freeKey, 1)
        PickupContainerItem(bag, s)
        PickupContainerItem(KEYRING_CONTAINER, dst)
        if CursorHasItem and CursorHasItem() then ClearCursor() end
        moved = true
      end
    end
  end
  if ClearCursor then ClearCursor() end
  return moved
end

-- One pass toward the CACHED plan: compare each live slot to its baked target itemID and move what
-- it can (skipping locked items). No re-sorting — just cheap itemID compares. Returns the count of
-- slots not yet matching, so the driver knows when the bag has reached the planned layout.
local function sortPassFromPlan(groups)
  if not groups then return 0, 0 end
  if ClearCursor then ClearCursor() end
  local remaining = 0
  local moved = 0            -- swaps actually issued this pass (drives the "nothing moved" convergence)
  local locked = 0           -- slots waiting on an in-flight (locked) item — NOT yet settled
  for _, g in ipairs(groups) do
    local slots, want = g.slots, g.want
    for i = 1, #slots do
      local w = want[i]
      local wantID, wantCount = w and w.id, w and w.count
      local ci = C_Container.GetContainerItemInfo(slots[i].bag, slots[i].slot)
      local curID = ci and ci.itemID or nil
      local curCount = ci and ci.stackCount or nil
      -- A slot is satisfied only if BOTH the item AND the stack size match — so same-item stacks of
      -- different sizes still get ordered (fullest into the earliest slot, partial to the end).
      if curID ~= wantID or curCount ~= wantCount then
        if ci and ci.isLocked then
          remaining = remaining + 1                       -- can't move yet; retry next pass
          locked = locked + 1                             -- in-flight; a quiet pass here isn't convergence
        elseif wantID then
          -- Find the best forward stack of the wanted item: an exact stack-size match if possible,
          -- otherwise the fullest available (earlier slots want the fuller stacks).
          local bestJ, bestCount
          for j = i + 1, #slots do
            local cj = C_Container.GetContainerItemInfo(slots[j].bag, slots[j].slot)
            if cj and cj.itemID == wantID and not cj.isLocked then
              local cc = cj.stackCount or 1
              if cc == wantCount then bestJ = j; break end
              if not bestCount or cc > bestCount then bestJ, bestCount = j, cc end
            end
          end
          if bestJ then
            PickupContainerItem(slots[i].bag, slots[i].slot)
            PickupContainerItem(slots[bestJ].bag, slots[bestJ].slot)
            if CursorHasItem and CursorHasItem() then
              PickupContainerItem(slots[i].bag, slots[i].slot)   -- drop displaced item into slots[i]'s old slot
            end
            remaining = remaining + 1   -- swapped; may need another pass to fully settle the order
            moved = moved + 1           -- something actually moved this pass
          else
            remaining = remaining + 1
          end
        end
      end
    end
  end
  if ClearCursor then ClearCursor() end
  return remaining, moved, locked
end

-- Iteration driver: run a pass, let the moved items settle, run again. The positioning phase converges
-- on STABILITY — it stops once two consecutive passes move NOTHING (or the bag is fully sorted), instead
-- of a fixed pass count, so a small bag stops early and a huge one keeps going until it settles.
-- Client-predicted moves lock items for a round-trip, so a big reorder needs several passes; this makes
-- ONE click converge instead of many. SORT_MAX_ITERS is now only a safety guard against an item the
-- server perpetually refuses to move (which would otherwise never register as "stable").
local SORT_STABLE_PASSES = 2    -- stop after this many consecutive no-move passes
local SORT_MAX_ITERS  = 50      -- hard safety cap (guards against a never-settling move)
local MERGE_MAX_ITERS = 20
local ROUTE_MAX_ITERS = 20

-- End the sort: drop the cached plan + cover and do the single, final repaint to the sorted layout.
local function finishSort()
  CB._sorting = false
  CB._sortPlan = nil
  CB._sortPhase = nil
  if frame and frame.sortCover then frame.sortCover:Hide() end
  refresh()
end

-- Two-phase driver: PHASE 1 consolidates partial stacks (mergePass) until stable, THEN plans + PHASE 2
-- positions items into the planned layout. Merging first means the plan is built on the compacted bag,
-- so freed slots are packed correctly. Each phase iterates (client-predicted moves lock items for a
-- round-trip) and yields via C_Timer so the moves settle between passes.
function CB._sortStep()
  if not CB._sorting then return end
  if InCombatLockdown() then finishSort(); return end

  if CB._sortPhase == "merge" then
    CB._mergeIter = (CB._mergeIter or 0) + 1
    local didMerge = mergePass()
    if didMerge and CB._mergeIter < MERGE_MAX_ITERS and C_Timer and C_Timer.After then
      C_Timer.After(0.25, CB._sortStep)   -- more partial stacks to combine
      return
    end
    -- Stacks consolidated → migrate items into their correct bag TYPE next.
    CB._sortPhase = "route"
    CB._routeIter = 0
    if C_Timer and C_Timer.After then C_Timer.After(0.25, CB._sortStep) else finishSort() end
    return
  end

  if CB._sortPhase == "route" then
    CB._routeIter = (CB._routeIter or 0) + 1
    local didRoute = routePass()
    local didKeys  = routeKeysToKeyRing()   -- move loose keys into the keyring
    if (didRoute or didKeys) and CB._routeIter < ROUTE_MAX_ITERS and C_Timer and C_Timer.After then
      C_Timer.After(0.25, CB._sortStep)   -- more mis-placed items to migrate to their bags
      return
    end
    -- Items now in the right bags → plan the layout on the routed bag and move to positioning.
    CB._sortPlan   = buildSortPlan()
    CB._sortPhase  = "position"
    CB._sortIter   = 0
    CB._sortStable = 0
    if C_Timer and C_Timer.After then C_Timer.After(0.25, CB._sortStep) else finishSort() end
    return
  end

  -- PHASE 2: positioning. Converge on stability — stop after SORT_STABLE_PASSES consecutive passes that
  -- move nothing (or once the bag exactly matches the plan). The hard cap is only a runaway guard.
  CB._sortIter = (CB._sortIter or 0) + 1
  local remaining, moved, locked = sortPassFromPlan(CB._sortPlan)   -- moves items toward the CACHED plan; no repaint
  -- A pass is "quiet" only if it moved nothing AND isn't still waiting on any in-flight (locked) item —
  -- so a settle-delay pass on a laggy server doesn't get mistaken for convergence.
  if (moved or 0) > 0 or (locked or 0) > 0 then
    CB._sortStable = 0                                   -- moved, or still settling → reset the streak
  else
    CB._sortStable = (CB._sortStable or 0) + 1           -- a genuinely quiet pass → count toward convergence
  end
  if remaining == 0 or CB._sortStable >= SORT_STABLE_PASSES or CB._sortIter >= SORT_MAX_ITERS then
    finishSort()
    return
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0.25, CB._sortStep)   -- wait for the moved items to unlock, then continue
  else
    finishSort()                         -- no timer available → single pass only
  end
end

function CB.SortBags()
  if InCombatLockdown() or CB._sorting then return end
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
          and PickupContainerItem) then return end
  CB._sorting = true
  CB._sortPhase = "merge"          -- consolidate stacks first, then plan + position (see CB._sortStep)
  CB._mergeIter = 0
  CB._sortIter = 0
  -- HIDE the item buttons/slots so the shuffle is invisible, then float the spinner over the empty bag.
  if buildChrome() then
    if grid and grid.ForEachButton then grid:ForEachButton(function(b) b:Hide() end) end
    -- The cover has no opaque fill (we hide slots directly), so hide the keyring row + label too or
    -- they show through the "Sorting…" cover.
    if keyGrid and keyGrid.ForEachButton then keyGrid:ForEachButton(function(b) b:Hide() end) end
    if frame._keysLabel then frame._keysLabel:Hide() end
    -- Same for every separated specialty-bag section (grid slots + header label).
    for _, sec in pairs(specSections) do
      if sec.grid and sec.grid.ForEachButton then sec.grid:ForEachButton(function(b) b:Hide() end) end
      if sec.label then sec.label:Hide() end
    end
    if frame.sortCover then
      if frame.sortCover.label then frame.sortCover.label:SetText(NE.L["Sorting…"]) end
      frame.sortCover:Raise(); frame.sortCover:Show()
    end
  end
  CB._sortStep()
end

-- Sell every grey (Poor quality) item that has a sell value, if a merchant is open. UseContainerItem
-- sells the item while the MerchantFrame is up (3.3.5a). Skips locked & no-value greys (quest greys).
--
-- 3.3.5a gotcha: C_Container.GetContainerItemInfo's `quality` is unreliable — the native container
-- API returns -1 (or the ClassicAPI shim leaves it unresolved) until the item is queried, so gating
-- on `info.quality == 0` silently matches nothing. We resolve quality (and the vendor sell price)
-- from the item LINK via GetItemInfo instead, which is cached for anything sitting in the player's bags.
function CB.SellJunk()
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  if not (UseContainerItem and C_Container and C_Container.GetContainerItemInfo
          and C_Container.GetContainerNumSlots) then return end
  local sold = 0
  for bag = 0, NUM_BAG_SLOTS do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and not info.isLocked then
        local link = info.hyperlink
        local quality, sellPrice = info.quality, nil
        if link and GetItemInfo then
          local _, _, q, _, _, _, _, _, _, _, price = GetItemInfo(link)
          if (not quality or quality < 0) and q then quality = q end   -- trust the link's quality
          sellPrice = price
        end
        -- Grey (Poor) items only, and only if they actually have vendor value (skip quest greys).
        if quality == 0 and (sellPrice == nil or sellPrice > 0) then
          UseContainerItem(bag, slot)
          sold = sold + 1
        end
      end
    end
  end
  if sold > 0 and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(string.format(NE.L["Sold %d junk item(s)."], sold))
  end
end

-- ============================================================================
-- Auto-empty on bag equip. When the player drops a NEW bag onto an occupied, non-empty bag slot
-- (which the game normally refuses — "that container is not empty"), we empty the old bag into free
-- space in the OTHER bags, equip the new bag, stash the old (now empty) bag, then auto-sort.
-- SAFETY: a pre-check (canEmptyBag) guarantees every item has a valid home BEFORE anything moves, so
-- items are never destroyed; if they can't all fit, we abort and let the normal refusal stand.
-- ============================================================================
local CONTAINER_BAG_OFFSET = 19   -- inventory slot 20..23 ↔ container 1..4

-- Dormant bag-swap trace helper. Inert unless CB._debug is set true (no user command sets it); kept
-- inline so the swap logic stays annotated. Set CB._debug=true via /script to re-enable if debugging.
local function dbg(...)
  if CB._debug and DEFAULT_CHAT_FRAME then
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffNEBags|r " .. table.concat(parts, " "))
  end
end

local function containerUsed(container)
  local n = C_Container.GetContainerNumSlots(container) or 0
  local used = 0
  for s = 1, n do
    local info = C_Container.GetContainerItemInfo(container, s)
    if info and (info.itemID or info.hyperlink) then used = used + 1 end
  end
  return used
end

-- Empty (nil-item) slots in every bag except `exclude`, each tagged with its bag family.
local function freeSlotsExcluding(exclude)
  local list = {}
  for _, bd in ipairs(orderedBags()) do
    if bd.bag ~= exclude then
      local n = C_Container.GetContainerNumSlots(bd.bag) or 0
      for s = 1, n do
        if not C_Container.GetContainerItemInfo(bd.bag, s) then
          list[#list + 1] = { bag = bd.bag, slot = s, family = bd.family }
        end
      end
    end
  end
  return list
end

-- Can every item in `container` be placed into a fitting free slot elsewhere? (No move happens here.)
local function canEmptyBag(container)
  local free = freeSlotsExcluding(container)
  local n = C_Container.GetContainerNumSlots(container) or 0
  for s = 1, n do
    local info = C_Container.GetContainerItemInfo(container, s)
    if info and (info.itemID or info.hyperlink) then
      local fam = (GetItemFamily and GetItemFamily(info.hyperlink or info.itemID)) or 0
      local idx
      for k, fs in ipairs(free) do
        if not fs.used and itemFitsBag(fam, fs.family) then idx = k; break end
      end
      if not idx then return false end
      free[idx].used = true
    end
  end
  return true
end

-- One move-pass: relocate `container`'s (unlocked) items into fitting free slots elsewhere. Returns
-- the count still inside so the driver keeps going until it's empty (locks resolve between passes).
local function emptyBagPass(container)
  local free = freeSlotsExcluding(container)
  local n = C_Container.GetContainerNumSlots(container) or 0
  if ClearCursor then ClearCursor() end
  for s = 1, n do
    local info = C_Container.GetContainerItemInfo(container, s)
    if info and (info.itemID or info.hyperlink) and not info.isLocked then
      local fam = (GetItemFamily and GetItemFamily(info.hyperlink or info.itemID)) or 0
      for _, fs in ipairs(free) do
        if not fs.used and itemFitsBag(fam, fs.family) then
          fs.used = true
          PickupContainerItem(container, s)
          PickupContainerItem(fs.bag, fs.slot)
          if CursorHasItem and CursorHasItem() then ClearCursor() end
          break
        end
      end
    end
  end
  if ClearCursor then ClearCursor() end
  return containerUsed(container)
end

local function findItemByLink(link)
  if not link then return nil end
  for b = 0, NUM_BAG_SLOTS do
    local n = C_Container.GetContainerNumSlots(b) or 0
    for s = 1, n do
      local info = C_Container.GetContainerItemInfo(b, s)
      if info and info.hyperlink == link then return b, s end
    end
  end
end

local function firstFreeSlot()
  for b = 0, NUM_BAG_SLOTS do
    local n = C_Container.GetContainerNumSlots(b) or 0
    for s = 1, n do
      if not C_Container.GetContainerItemInfo(b, s) then return b, s end
    end
  end
end

-- End the swap: clear flags; either flow straight into a sort (keeping the cover up) or reveal.
local function finishBagSwap(doSort)
  CB._bagSwapping = false
  CB._bagSwap = nil
  if doSort then
    CB._sorting = false          -- let SortBags start (it keeps items hidden + cover up, then reveals)
    CB.SortBags()
    return
  end
  CB._sorting = false
  if frame and frame.sortCover then
    if frame.sortCover.label then frame.sortCover.label:SetText(NE.L["Sorting…"]) end
    frame.sortCover:Hide()
  end
  refresh()
end

function CB._bagSwapStep()
  local st = CB._bagSwap
  if not st then finishBagSwap(false); return end
  if InCombatLockdown() then finishBagSwap(false); return end
  st.iter = (st.iter or 0) + 1
  if st.iter > 60 then finishBagSwap(true); return end   -- safety cap → at least tidy up with a sort

  if st.phase == "empty" then
    local left = emptyBagPass(st.container)
    dbg("  empty pass", st.iter, "→ items left:", left)
    if left == 0 then st.phase = "equip" end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, CB._bagSwapStep) else finishBagSwap(true) end
    return
  end

  if st.phase == "equip" then
    local bag, slot = findItemByLink(st.newBagLink)
    dbg("  equip phase: found new bag at", bag, slot, "invSlot", st.invSlot)
    if bag and PutItemInBag then
      PickupContainerItem(bag, slot)          -- pick up the new (empty) bag
      PutItemInBag(st.invSlot)                 -- equip it; the old (now empty) bag lands on the cursor
      if CursorHasItem and CursorHasItem() then
        local fb, fs = firstFreeSlot()          -- park the old empty bag in any free slot
        if fb then PickupContainerItem(fb, fs) end
        if CursorHasItem and CursorHasItem() then ClearCursor() end
      end
    end
    st.phase = "done"
    if C_Timer and C_Timer.After then C_Timer.After(0.25, CB._bagSwapStep) else finishBagSwap(true) end
    return
  end

  finishBagSwap(true)   -- "done": reveal + auto-sort
end

-- Called AFTER PutItemInBag with the bag link captured BEFORE the call (the cursor is cleared by a
-- failed equip on this client, so we can't read it post-hoc). If the equip failed — i.e. the old bag
-- in that slot is still non-empty — run the managed swap; the new bag is back in inventory (by link).
function CB.HandleBagEquip(invSlot, link)
  local container = (invSlot or 0) - CONTAINER_BAG_OFFSET
  dbg("HandleBagEquip invSlot=", invSlot, "container=", container, "link=", link)
  if not CB._autoEmptyBag then dbg("  skip: autoEmptyBag off"); return end
  if InCombatLockdown() or CB._bagSwapping or CB._sorting then dbg("  skip: busy/combat"); return end
  if not (C_Container and C_Container.GetContainerNumSlots and PickupContainerItem and PutItemInBag and link) then
    dbg("  skip: missing API/link"); return end
  if container < 1 or container > NUM_BAG_SLOTS then dbg("  skip: bad container"); return end
  local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
  dbg("  equipLoc:", equipLoc)
  if equipLoc ~= "INVTYPE_BAG" then dbg("  skip: not a bag"); return end
  local used = containerUsed(container)
  dbg("  old bag used slots:", used)
  if used == 0 then dbg("  skip: equip succeeded / old bag empty"); return end   -- nothing to move
  if not findItemByLink(link) then dbg("  skip: new bag not found back in inventory"); return end
  if not canEmptyBag(container) then
    dbg("  ABORT: not enough free space")
    if UIErrorsFrame then
      UIErrorsFrame:AddMessage(NE.L["Not enough free space to swap that bag."], 1, 0.2, 0.2)
    end
    return
  end
  -- Begin the managed swap (cursor is already empty; the new bag sits back in inventory).
  dbg("  >>> STARTING SWAP: emptying container", container)
  CB._bagSwapping = true
  CB._sorting = true
  CB._bagSwap = { container = container, invSlot = invSlot, newBagLink = link, phase = "empty", iter = 0 }
  if buildChrome() then
    if grid and grid.ForEachButton then grid:ForEachButton(function(b) b:Hide() end) end
    if frame.sortCover then
      if frame.sortCover.label then frame.sortCover.label:SetText(NE.L["Swapping bag…"]) end
      frame.sortCover:Raise(); frame.sortCover:Show()
    end
  end
  CB._bagSwapStep()
end

-- Catch a failed "equip over a full bag". We WRAP the global PutItemInBag so we can read the cursor
-- bag BEFORE the equip — on this client a failed equip clears the cursor, so hooksecurefunc (post-only)
-- sees nothing. We capture the bag link, call the original, then hand off to HandleBagEquip which
-- decides (from the target bag's contents) whether the equip failed and a managed swap is needed.
local function installBagEquipHooks()
  if CB._bagHooksInstalled then return end
  CB._bagHooksInstalled = true
  if type(_G.PutItemInBag) ~= "function" then dbg("PutItemInBag missing; bag-swap disabled"); return end
  local orig = _G.PutItemInBag
  _G.PutItemInBag = function(invSlot)
    local link
    if not (CB._bagSwapping or CB._sorting) and not InCombatLockdown()
       and CursorHasItem and CursorHasItem() then
      local ctype, _, clink = GetCursorInfo()
      if ctype == "item" and clink then link = clink end
    end
    orig(invSlot)                 -- perform the real equip (may succeed or fail)
    if link then CB.HandleBagEquip(invSlot, link) end
  end
  dbg("installed PutItemInBag wrapper")
end
CB.InstallBagEquipHooks = installBagEquipHooks

-- Is our bag-options dropdown currently open? (DropDownList1 shown AND owned by our menu frame.)
function CB.MenuIsOpen()
  return CB._menuFrame and DropDownList1 and DropDownList1:IsShown()
     and UIDROPDOWNMENU_OPEN_MENU == CB._menuFrame and true or false
end

-- Left-click the cog: toggle the menu — open it, or close it if it's already showing.
function CB.ToggleMenu(anchor)
  if CB.MenuIsOpen() then
    if CloseDropDownMenus then CloseDropDownMenus() end
  else
    CB.OpenMenu(anchor)
  end
end

-- The item level entry. It's DragonUI's setting, not ours (see BagSkin's BS.SetItemLevelShown) —
-- this is a second CONTROL over one value, not a second copy of it, so it can't drift from the
-- checkbox in Options -> Enhancements -> Item Level. Surfaced here because hunting through another
-- addon's options tab to change how the bag looks is a poor trade for one line of menu.
--
-- When DragonUI's master "Enable Item Level" is off the per-context flag is inert, so the entry
-- greys out and its tooltip says where the master lives — better than a switch that does nothing.
local function itemLevelMenuItem()
  local BS = NE.bagskin
  local label = NE.L["Show item level on items"]
  -- Greyed but still a checkbox, so the row doesn't reflow against its neighbours when it's inert.
  if not (BS and BS.CanToggleItemLevel and BS.CanToggleItemLevel()) then
    return {
      text = label, checked = false, disabled = true,
      tooltipOnButton = true, tooltipTitle = label,
      tooltipText = NE.L["Turn on Item Level in DragonUI's options (Enhancements > Item Level) first."],
    }
  end
  return {
    text    = label,
    checked = BS.IsItemLevelShown(),
    func    = function() BS.SetItemLevelShown(not BS.IsItemLevelShown()) end,
    -- It's the master switch, so say so: this is the same checkbox as "Enable Item Level" in
    -- DragonUI's options and it governs every frame, not just the bag.
    tooltipOnButton = true, tooltipTitle = label,
    tooltipText = NE.L["The same setting as Enable Item Level in DragonUI's options (Enhancements > Item Level). Covers the character panel and every other frame too."],
  }
end

-- Bag-options dropdown (native EasyMenu / UIDropDownMenu — present on 3.3.5a).
function CB.OpenMenu(anchor)
  if not EasyMenu then return end
  if not CB._menuFrame then
    CB._menuFrame = CreateFrame("Frame", "NE_CombinedBagMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local function modeItem(mode, label)
    return { text = label, checked = (CB._sortMode == mode),
      func = function() CB._sortMode = mode; CB.SaveSortPrefs(); CB.SortBags() end }
  end
  local menu = {
    { text = NE.L["Bag Options"], isTitle = true, notCheckable = true },
    { text = NE.L["Sort Bags"], notCheckable = true, func = function() CB.SortBags() end },
    { text = NE.L["Sort by"], isTitle = true, notCheckable = true },
    modeItem("category", NE.L["Category (smart)"]),
    modeItem("quality",  NE.L["Quality"]),
    modeItem("ilvl",     NE.L["Item Level"]),
    modeItem("name",     NE.L["Name"]),
    { text = NE.L["Reverse sort order"], checked = CB._reverseSort and true or false,
      func = function() CB._reverseSort = not CB._reverseSort; CB.SaveSortPrefs() end },
    { text = NE.L["Red-tint unusable items"], checked = CB._redUnusable and true or false,
      func = function() CB._redUnusable = not CB._redUnusable; CB.SaveSortPrefs(); CB.Refresh() end },
    itemLevelMenuItem(),
    { text = NE.L["Show keyring row"], checked = CB._showKeys and true or false,
      func = function() CB._showKeys = not CB._showKeys; CB.SaveSortPrefs(); CB.Refresh() end },
    { text = NE.L["Separate specialty bags"], checked = CB._separateBags and true or false,
      func = function() CB._separateBags = not CB._separateBags; CB.SaveSortPrefs(); CB.Refresh() end },
    { text = NE.L["Auto-empty old bag when swapping"], checked = CB._autoEmptyBag and true or false,
      func = function() CB._autoEmptyBag = not CB._autoEmptyBag; CB.SaveSortPrefs() end },
    { text = NE.L["Merchant"], isTitle = true, notCheckable = true },
    { text = NE.L["Auto-sell junk at merchants"], checked = CB._autoSellJunk and true or false,
      func = function() CB._autoSellJunk = not CB._autoSellJunk; CB.SaveSortPrefs()
        if CB._autoSellJunk then CB.SellJunk() end end },   -- sell now too if a merchant is already open
  }
  EasyMenu(menu, CB._menuFrame, anchor or "cursor", 0, 0, "MENU")
end

-- Persist / restore the sort scheme in our SavedVariables.
function CB.SaveSortPrefs()
  if not NE.db then return end
  NE.db.combinedbag = NE.db.combinedbag or {}
  NE.db.combinedbag.sortMode    = CB._sortMode
  NE.db.combinedbag.reverse     = CB._reverseSort and true or false
  NE.db.combinedbag.redUnusable = CB._redUnusable and true or false
  NE.db.combinedbag.autoSellJunk = CB._autoSellJunk and true or false
  NE.db.combinedbag.autoEmptyBag = CB._autoEmptyBag and true or false
  NE.db.combinedbag.showKeys     = CB._showKeys and true or false
  NE.db.combinedbag.separateBags = CB._separateBags and true or false
end
function CB.LoadSortPrefs()
  local c = NE.db and NE.db.combinedbag
  if not c then return end
  if c.sortMode then CB._sortMode = c.sortMode end
  CB._reverseSort = c.reverse and true or false
  if c.redUnusable ~= nil then CB._redUnusable = c.redUnusable and true or false end
  if c.autoSellJunk ~= nil then CB._autoSellJunk = c.autoSellJunk and true or false end
  if c.autoEmptyBag ~= nil then CB._autoEmptyBag = c.autoEmptyBag and true or false end
  if c.showKeys ~= nil then CB._showKeys = c.showKeys and true or false end
  if c.separateBags ~= nil then CB._separateBags = c.separateBags and true or false end
end

-- ----------------------------------------------------------------------------
-- Take over the bag-open globals + suppress stock frames. Saved originals live on CB._old so a
-- future teardown could restore them (we don't, since disable is reload-gated).
-- ----------------------------------------------------------------------------
local intercepted = false
CB._old = CB._old or {}

local function installIntercept()
  if intercepted then return end
  intercepted = true

  local function take(name, fn)
    if type(_G[name]) ~= "function" then return end
    CB._old[name] = _G[name]
    _G[name] = fn
  end

  take("ToggleBackpack", function() CB.Toggle() end)
  take("ToggleAllBags",  function() CB.Toggle() end)
  take("OpenAllBags",    function() CB.Show() end)
  take("CloseAllBags",   function() CB.Hide() end)
  take("OpenBackpack",   function() CB.Show() end)
  take("CloseBackpack",  function() CB.Hide() end)

  -- Safety net for paths that open a ContainerFrame directly (loot, merchant, right-click a bag):
  -- hide it and show the combined window instead.
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then
      f:HookScript("OnShow", function(self)
        if InCombatLockdown() then return end
        -- Keyring (container -2): only take it over when the keys row is enabled; otherwise let the
        -- stock keyring frame open so keys stay reachable when the row is toggled off.
        if self.GetID and self:GetID() == KEYRING_CONTAINER and not CB.ShowKeys() then return end
        self:Hide()
        CB.Show()
      end)
    end
  end
end

-- ----------------------------------------------------------------------------
-- Live refresh watcher.
-- ----------------------------------------------------------------------------
local function installWatcher()
  if CB._watcher then return end
  local w = CreateFrame("Frame")
  CB._watcher = w
  for _, ev in ipairs({
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
    "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD", "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
  }) do
    pcall(function() w:RegisterEvent(ev) end)
  end
  w:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
      -- Combat ended: flush any bag re-parents that were queued during lockdown, then refresh.
      if grid and grid.FlushPendingParents then grid:FlushPendingParents() end
    elseif event == "AUCTION_HOUSE_SHOW" then
      -- Stock merchant/bank auto-open bags via OpenAllBags() (which we intercept), but the 3.3.5 AH
      -- does not -- so the combined bag never opened with the AH (issue #12). Mirror the merchant
      -- behaviour here. Owner-gated: only auto-open when the bag wasn't already up, and remember we
      -- did, so we only auto-close it on AUCTION_HOUSE_CLOSED if we were the ones who opened it.
      if not InCombatLockdown() and not CB.IsShown() then
        CB._ahAutoOpened = true
        CB.Show()
      end
    elseif event == "AUCTION_HOUSE_CLOSED" then
      if CB._ahAutoOpened then
        CB._ahAutoOpened = nil
        CB.Hide()
      end
    elseif event == "MERCHANT_SHOW" and CB._autoSellJunk and not InCombatLockdown() then
      -- Defer one tick so the MerchantFrame is fully open + item quality is resolved before selling.
      if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function() if not InCombatLockdown() then CB.SellJunk() end end)
      else
        CB.SellJunk()   -- auto-sell greys on arrival at a vendor (opt-in)
      end
    end
    refresh()
  end)
end

-- ----------------------------------------------------------------------------
-- Boot.
-- ----------------------------------------------------------------------------
local function boot()
  CB.LoadSortPrefs()
  installIntercept()
  installWatcher()
  installBagEquipHooks()
end
CB.Boot = boot

if NE.modules and NE.modules.Register then
  NE.modules.Register{
    name    = MODULE,
    default = false,   -- Default OFF: players opt in via the options toggle (integration/Options.lua).
                       -- When enabled it takes over bag opening and supersedes the per-window restyle.
    label   = NE.L["Combined bag (all-in-one)"],
    category = "Windows",
    desc    = NE.L["One movable window showing every bag slot in a Dragonflight-style grid. Takes over "
           .. "bag opening and replaces the per-window 'Retail bags' restyle. Reload (/reload) to apply."],
    events  = { "PLAYER_LOGIN" },
    onBoot  = function() boot() end,
    conflictsWith = NE.modules.RIVALS and NE.modules.RIVALS.BAGS or nil,
  }
else
  log("NE.modules.Register absent; combined bag not booted")
end

if NE.qa then
  NE.qa.modules = NE.qa.modules or {}
  table.insert(NE.qa.modules, {
    name  = "Combined bag",
    frame = nil,   -- built lazily; harness resolves NE_CombinedBagFrame on open
    open  = function() CB.Show() end,
    close = function() CB.Hide() end,
  })
end
