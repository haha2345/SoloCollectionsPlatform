-- DragonUI_NewEra/modules/auctionhouse/Browse.lua
-- Buy tab visual shell and Blizzard API search bridge.

local NE = DragonUI_NewEra
if not NE then return end

NE.ah = NE.ah or {}
local AH = NE.ah

-- "Any rarity" sentinel for QueryAuctionItems' quality argument. That argument is an EXACT match
-- against the item's quality, NOT a minimum, and -1 is the only value that disables the filter --
-- 0 is a real quality (Poor). See the ISSUE #31 note on pane.Filter in buildBrowsePane. Every
-- QueryAuctionItems call site in this addon must pass this, never 0, when it wants "all rarities".
local ANY_QUALITY = -1
AH.ANY_QUALITY = ANY_QUALITY

-- ============================================================================
-- Shared "list" auction-query arbiter.  ISSUE #31.
--
-- The 3.3.5a client has exactly ONE "list" query slot. Three consumers in this addon write to it
-- (the browse scan, the item drill-down, the Sell tab's market lookup) and anything else loaded
-- can too -- Auctionator, the cloaked stock AuctionFrame, other addons. AUCTION_ITEM_LIST_UPDATE
-- carries no indication of who asked, so a watcher that reads the slot unconditionally will
-- happily parse somebody else's result set as its own.
--
-- Whoever issues a query claims the slot by name; every watcher must confirm it still owns the
-- slot before reading GetAuctionItemInfo("list", ...). An update we did not cause leaves
-- listOwner pointing at someone else (or nil, for a foreign query), so everyone ignores it.
-- ============================================================================
function AH.ClaimListQuery(owner)
  AH.listOwner = owner
end

function AH.OwnsListQuery(owner)
  return AH.listOwner == owner
end

-- Keep alwaysShow custom Faux bars visually in sync with the actual row overflow state.
-- Track/arrows stay visible; thumb only shows when the list can truly scroll.
local function syncAlwaysShowFauxBar(scroll, totalRows, visibleRows)
  if not scroll then return end
  local bar = scroll._neCustomBar
  if not (bar and bar._alwaysShow) then return end

  local canScroll = (totalRows or 0) > (visibleRows or 0)
  bar:Show()
  if bar._upBtn then bar._upBtn:Show() end
  if bar._downBtn then bar._downBtn:Show() end
  if bar._thumb then
    if canScroll then bar._thumb:Show() else bar._thumb:Hide() end
  end

  -- Clamp the hidden Faux slider when unscrollable so stale values cannot keep the thumb active.
  if not canScroll then
    local sliderName = scroll.GetName and scroll:GetName()
    local slider = (sliderName and _G[sliderName .. "ScrollBar"]) or scroll.ScrollBar or scroll.scrollBar
    if slider then
      if slider.SetMinMaxValues then slider:SetMinMaxValues(0, 0) end
      if slider.SetValue then slider:SetValue(0) end
    end
  end
end

-- Aggregate browse row click drills into a per-item detail page (all individual auctions of that
-- item); the detail page's Bid/Buyout buttons act on the selected listing via these two confirms.
StaticPopupDialogs["NE_AH_BROWSE_BID"] = {
  text = "Place a bid of %s?",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(_, data)
    if not data or not data.index then return end
    local ok, err = pcall(PlaceAuctionBid, "list", data.index, data.price)
    if not ok and NE.Log then
      NE.Log("AH", "PlaceAuctionBid(bid) error: " .. tostring(err))
    end
  end,
  timeout = 0,
  hideOnEscape = 1,
  whileDead = 1,
  showAlert = 1,
}
StaticPopupDialogs["NE_AH_BROWSE_BUYOUT"] = {
  text = "Buy out this auction for %s?",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(_, data)
    if not data or not data.index then return end
    local ok, err = pcall(PlaceAuctionBid, "list", data.index, data.price)
    if not ok and NE.Log then
      NE.Log("AH", "PlaceAuctionBid(buyout) error: " .. tostring(err))
    end
  end,
  timeout = 0,
  hideOnEscape = 1,
  whileDead = 1,
  showAlert = 1,
}

local CATEGORY_TREE = {
  { name = "Weapons", children = { "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces", "Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords", "Staves", "Fist Weapons", "Daggers", "Thrown" } },
  { name = "Armor", children = { "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams", "Idols", "Totems", "Sigils" } },
  { name = "Container", children = { "Bags", "Soul Bags", "Herb Bags", "Enchanting Bags", "Engineering Bags", "Gem Bags", "Mining Bags" } },
  { name = "Consumable", children = { "Food & Drink", "Potion", "Elixir", "Flask", "Bandage", "Scroll", "Item Enhancement" } },
  { name = "Trade Goods", children = { "Parts", "Explosives", "Devices", "Jewelcrafting", "Cloth", "Leather", "Metal & Stone", "Meat", "Herb", "Elemental", "Enchanting", "Materials", "Armor Enchantment", "Weapon Enchantment" } },
  { name = "Projectile", children = { "Wand", "Arrow", "Bullet" } },
  { name = "Quiver", children = { "Quiver", "Ammo Pouch" } },
  { name = "Recipe", children = { "Book", "Leatherworking", "Tailoring", "Engineering", "Blacksmithing", "Cooking", "Alchemy", "First Aid", "Enchanting", "Fishing", "Jewelcrafting", "Inscription" } },
  { name = "Gems", children = { "Red", "Blue", "Yellow", "Purple", "Green", "Orange", "Meta", "Simple", "Prismatic" } },
  { name = "Miscellaneous", children = { "Junk", "Reagent", "Pet", "Holiday", "Other" } },
  { name = "Quest Items", children = { "Quest" } },
}

local function buildCategoryList(parent)
  local ROW_H = 21
  local ROW_GAP = 1
  -- Row count sized to fill the categories panel's own background art down to its bottom edge
  -- (previously 18 rows against a hardcoded 424px list height -- neither number matched the other,
  -- leaving a large dead gap below the last row; both now derive from the same VISIBLE_ROWS).
  local VISIBLE_ROWS = 19

  local list = CreateFrame("Frame", nil, parent)
  list:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
  list:SetSize(152, VISIBLE_ROWS * ROW_H + (VISIBLE_ROWS - 1) * ROW_GAP)

  local rows = {}
  local flat = {}
  local selectedCat = nil
  local selectedSub = nil
  local selectedInv = nil
  local currentOffset = 0

  -- classIndex/subClassIndex passed to QueryAuctionItems are POSITIONAL (luaIndex into
  -- GetAuctionItemClasses()/GetAuctionItemSubClasses(classIndex)), not name-matched. Source the
  -- category tree from those same calls so the index we click is guaranteed to be the index the
  -- server expects -- a hand-maintained name list (CATEGORY_TREE) can silently drift out of order
  -- from the live class/subclass table and file every search under the wrong category. CATEGORY_TREE
  -- is kept only as a display-name fallback for the (never-expected) case these globals are missing.
  local classNamesCache
  local subClassCache = {}

  local function getClassNames()
    if classNamesCache then return classNamesCache end
    local names = {}
    if type(GetAuctionItemClasses) == "function" then
      local ok, res = pcall(function() return { GetAuctionItemClasses() } end)
      if ok and res and #res > 0 then names = res end
    end
    if #names == 0 then
      for i = 1, #CATEGORY_TREE do names[i] = CATEGORY_TREE[i].name end
    end
    classNamesCache = names
    return names
  end

  local function getSubClassNames(classIndex)
    local cached = subClassCache[classIndex]
    if cached then return cached end
    local subs = {}
    if type(GetAuctionItemSubClasses) == "function" then
      local ok, res = pcall(function() return { GetAuctionItemSubClasses(classIndex) } end)
      if ok and res then subs = res end
    end
    if #subs == 0 and CATEGORY_TREE[classIndex] then
      subs = CATEGORY_TREE[classIndex].children or {}
    end
    subClassCache[classIndex] = subs
    return subs
  end

  -- Third tier: inventory-type slots (Head, Shoulder, ...) within a selected class+subclass, e.g.
  -- Armor > Leather > Head. GetAuctionInvTypes(classIndex, subClassIndex) returns a FLAT list of
  -- (invTypeToken, shouldDisplay) pairs -- NOT one name per return like GetAuctionItemClasses -- so
  -- unlike the two tiers above this can't just be indexed 1:1; we walk it in twos, keep only the
  -- shouldDisplay entries, and record each one's ORIGINAL pair position as its invTypeIndex (the
  -- luaIndex QueryAuctionItems' invTypeIndex arg expects), not its position among the filtered/shown
  -- entries. invTypeToken (e.g. "INVTYPE_HEAD") is also the name of a global localized string with
  -- the human-readable slot name, same convention PaperDoll/Item tooltips use.
  local invTypeCache = {}

  local function getInvTypes(classIndex, subClassIndex)
    local key = classIndex .. ":" .. subClassIndex
    local cached = invTypeCache[key]
    if cached then return cached end
    local list = {}
    if type(GetAuctionInvTypes) == "function" then
      local ok, res = pcall(function() return { GetAuctionInvTypes(classIndex, subClassIndex) } end)
      if ok and res then
        local pos = 0
        for i = 1, #res, 2 do
          pos = pos + 1
          local token, display = res[i], res[i + 1]
          if display and token and token ~= "" then
            list[#list + 1] = { text = _G[token] or token, index = pos }
          end
        end
      end
    end
    invTypeCache[key] = list
    return list
  end

  local function maxOffset()
    local m = #flat - VISIBLE_ROWS
    if m < 0 then m = 0 end
    return m
  end

  local function setOffset(v)
    if v < 0 then v = 0 end
    local m = maxOffset()
    if v > m then v = m end
    currentOffset = v
    local sliderName = list.Scroll and list.Scroll.GetName and list.Scroll:GetName()
    local slider = sliderName and _G[sliderName .. "ScrollBar"]
    if slider and slider.SetValue then
      slider:SetValue(v * (ROW_H + ROW_GAP))
    elseif list.Scroll and list.Scroll.SetVerticalScroll then
      list.Scroll:SetVerticalScroll(v * (ROW_H + ROW_GAP))
    end
  end

  local function getOffset()
    if list.Scroll and FauxScrollFrame_GetOffset then
      local offset = FauxScrollFrame_GetOffset(list.Scroll) or 0
      currentOffset = offset
      return offset
    end
    return currentOffset
  end

  local function flatten()
    local out = {}
    local classNames = getClassNames()

    for ci = 1, #classNames do
      local catSelected = (selectedCat == ci)
      out[#out + 1] = { text = classNames[ci], kind = "category", ci = ci, selected = catSelected }
      if catSelected then
        local subs = getSubClassNames(ci)
        for si = 1, #subs do
          local subSelected = (selectedSub == si)
          out[#out + 1] = {
            text = subs[si] or tostring(si),
            kind = "subCategory",
            ci = ci,
            si = si,
            selected = subSelected,
          }
          if subSelected then
            local invTypes = getInvTypes(ci, si)
            for ii = 1, #invTypes do
              local inv = invTypes[ii]
              out[#out + 1] = {
                text = inv.text,
                kind = "invType",
                ci = ci,
                si = si,
                vi = inv.index,
                selected = (selectedInv == inv.index),
              }
            end
          end
        end
      end
    end
    return out
  end

  -- classIndex/subClassIndex/invTypeIndex for QueryAuctionItems. 0 == "any" (the client's own
  -- sentinel for an unset luaIndex filter slot), matching what a deselected row means.
  function list:GetSelectedIndices()
    return selectedCat or 0, selectedSub or 0, selectedInv or 0
  end

  local function styleRow(row, info)
    row.Bg:Hide()
    row.Line:Hide()

    if info.kind == "category" then
      if NE.tex and NE.tex.SetAtlas then
        NE.tex.SetAtlas(row.NormalTexture, "auctionhouse-nav-button", false)
        NE.tex.SetAtlas(row.SelectedTexture, "auctionhouse-nav-button-select", false)
        NE.tex.SetAtlas(row.HighlightTexture, "auctionhouse-nav-button-highlight", false)
      end
      row.NormalTexture:SetSize(136, 32)
      row.NormalTexture:ClearAllPoints()
      row.NormalTexture:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 0)

      row.SelectedTexture:SetSize(132, 21)
      row.SelectedTexture:ClearAllPoints()
      row.SelectedTexture:SetPoint("LEFT", row, "LEFT", 0, 0)

      row.HighlightTexture:SetSize(132, 21)
      row.HighlightTexture:ClearAllPoints()
      row.HighlightTexture:SetPoint("LEFT", row, "LEFT", 0, 0)

      row.Text:SetFontObject(GameFontNormal)
      row.Text:SetPoint("LEFT", row, "LEFT", 8, 0)
      row.Text:SetTextColor(1.0, 0.82, 0.0)
    else
      if NE.tex and NE.tex.SetAtlas then
        NE.tex.SetAtlas(row.NormalTexture, "auctionhouse-nav-button-secondary", false)
        NE.tex.SetAtlas(row.SelectedTexture, "auctionhouse-nav-button-secondary-select", false)
        NE.tex.SetAtlas(row.HighlightTexture, "auctionhouse-nav-button-secondary-highlight", false)
      end
      row.NormalTexture:SetSize(133, 32)
      row.NormalTexture:ClearAllPoints()
      row.NormalTexture:SetPoint("TOPLEFT", row, "TOPLEFT", 1, 0)

      row.SelectedTexture:SetSize(122, 21)
      row.SelectedTexture:ClearAllPoints()
      row.SelectedTexture:SetPoint("TOPLEFT", row, "TOPLEFT", 10, 0)

      row.HighlightTexture:SetSize(122, 21)
      row.HighlightTexture:ClearAllPoints()
      row.HighlightTexture:SetPoint("TOPLEFT", row, "TOPLEFT", 10, 0)

      -- Third tier (invType, e.g. "Head" under Armor > Leather) indents further than a plain
      -- subcategory so the two nesting depths read distinctly, matching the reference's deeper
      -- sub-sub-category rows.
      -- Sub/inv rows sit on a narrower secondary button (133px, vs. 136 for a category) AND start
      -- more indented -- GameFontNormal (used for the top-level rows) was overflowing that reduced
      -- width for longer names like "One-Handed Axes"/"Two-Handed Swords". Smaller font object fits
      -- comfortably within the button texture at every indent depth.
      row.Text:SetFontObject(GameFontHighlightSmall)
      row.Text:ClearAllPoints()
      local indent = (info.kind == "invType") and 28 or 18
      row.Text:SetPoint("LEFT", row, "LEFT", indent, 0)
      row.Text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      row.Text:SetTextColor(0.88, 0.9, 0.95)
      row.Line:Show()
    end

    row.SelectedTexture:SetShown(info.selected and true or false)
    row.HighlightTexture:Hide()
  end

  local viewport = CreateFrame("Frame", nil, list)
  viewport:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  viewport:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
  viewport:SetHeight(VISIBLE_ROWS * ROW_H + (VISIBLE_ROWS - 1) * ROW_GAP)
  viewport:EnableMouseWheel(true)

  local function refreshRows()
    flat = flatten()
    local offset = getOffset()
    local m = maxOffset()
    if offset < 0 then offset = 0 end
    if offset > m then
      offset = m
      setOffset(offset)
    else
      currentOffset = offset
    end

    for i = 1, VISIBLE_ROWS do
      local info = flat[i + offset]
      local row = rows[i]
      if not row then
        row = CreateFrame("Button", nil, viewport)
        row:SetSize(146, ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetAllPoints(row)
        bg:Hide()
        row.Bg = bg

        row.NormalTexture = row:CreateTexture(nil, "BACKGROUND")
        row.SelectedTexture = row:CreateTexture(nil, "ARTWORK")
        row.HighlightTexture = row:CreateTexture(nil, "BORDER")
        row.HighlightTexture:Hide()

        row.Line = row:CreateTexture(nil, "BACKGROUND")
        if NE.tex and NE.tex.SetAtlas then
          NE.tex.SetAtlas(row.Line, "auctionhouse-nav-button-tertiary-filterline", true)
        end
        row.Line:SetPoint("LEFT", row, "LEFT", 18, 3)
        row.Line:Hide()

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", row, "LEFT", 8, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        text:SetJustifyH("LEFT")
        row.Text = text

        row:SetScript("OnEnter", function(self)
          if self.HighlightTexture then self.HighlightTexture:Show() end
        end)
        row:SetScript("OnLeave", function(self)
          if self.HighlightTexture then self.HighlightTexture:Hide() end
        end)
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function(self)
          if self._kind == "category" then
            if selectedCat == self._ci then
              selectedCat = nil
            else
              selectedCat = self._ci
            end
            selectedSub = nil
            selectedInv = nil
          elseif self._kind == "subCategory" then
            if selectedSub == self._si then
              selectedSub = nil
            else
              selectedSub = self._si
            end
            selectedInv = nil
          elseif self._kind == "invType" then
            if selectedInv == self._vi then
              selectedInv = nil
            else
              selectedInv = self._vi
            end
          else
            return
          end

          refreshRows()
        end)

        rows[i] = row
      end

      if i == 1 then
        row:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
      else
        row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -ROW_GAP)
      end

      if info then
        row._kind = info.kind
        row._ci = info.ci
        row._si = info.si
        row._vi = info.vi

        row.Text:SetText(info.text)
        styleRow(row, info)

        row:Show()
      else
        row._kind = nil
        row._ci = nil
        row._si = nil
        row._vi = nil
        row:Hide()
      end
    end

    if list.Scroll and FauxScrollFrame_Update then
      FauxScrollFrame_Update(list.Scroll, #flat, VISIBLE_ROWS, ROW_H + ROW_GAP)
    end
    syncAlwaysShowFauxBar(list.Scroll, #flat, VISIBLE_ROWS)
  end

  -- FauxScrollFrameTemplate's handlers (FauxScrollFrame_Update etc., FrameXML/UIPanelTemplates.lua)
  -- resolve the scrollbar's sub-widgets via frame:GetName() string concatenation, NOT parentKey --
  -- an anonymous (nil-named) FauxScrollFrame throws "attempt to concatenate ... (a nil value)" the
  -- moment FauxScrollFrame_Update runs on it. Must have a real global name.
  local scroll = CreateFrame("ScrollFrame", "NE_AuctionHouseBrowseCategoryScroll", list, "FauxScrollFrameTemplate")
  -- Explicit TOPLEFT+BOTTOMRIGHT (not just TOPLEFT+BOTTOMLEFT) so this frame actually has a defined
  -- width -- BuildCustom's bar anchors off scroll:GetRight(), which is meaningless on a frame that
  -- was never given a right edge, and could leave the bar mispositioned/invisible.
  -- The right edge must sit INSET from viewport's own right edge (not flush with it) -- BuildCustom
  -- places the bar opts.x (8px here) further right of scroll's right edge, same as the results-list
  -- and item-detail scroll frames, which each reserve a >=18px gutter for exactly this. A flush (0)
  -- inset here pushed the bar 8px past the whole category panel's border, off its visible bounds --
  -- reserving 18px keeps the bar's 8px-wide track inside `list`/`viewport`'s actual bounds.
  scroll:SetPoint("TOPLEFT", viewport, "TOPRIGHT", -30, -2)
  scroll:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -18, 2)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    if FauxScrollFrame_OnVerticalScroll then
      FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H + ROW_GAP, refreshRows)
      return
    end
    local step = ROW_H + ROW_GAP
    local nextOffset = math.floor((offset / step) + 0.5)
    currentOffset = nextOffset
    refreshRows()
  end)
  list.Scroll = scroll

  -- Physical scrollbar track+thumb (FauxScrollFrameTemplate alone draws NOTHING visible -- it's
  -- just offset math plus a hidden slider; every other FauxScroll list in this addon gets its
  -- visible bar from this same hand-built widget, driven off that hidden slider's min/max/value).
  -- BuildCustom's bar defaults to "HIGH" strata. AH.frame itself is explicitly "DIALOG" (Window.lua),
  -- and a frame's strata is inherited from its parent AT CREATION unless overridden -- so `list`/
  -- `viewport`/`scroll`, none of which set their own strata, are ALL "DIALOG" too, same as the rows
  -- built on them. That puts a "HIGH"-strata bar BEHIND the row buttons, hiding it completely (same
  -- trap already fixed for the results-list and item-detail scrollbars below). Force it to match.
  if NE.scrollbar and NE.scrollbar.BuildCustom then
    local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, { x = -8, alwaysShow = true })
    if ok and bar then
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((viewport:GetFrameLevel() or 1) + 10)
      -- The arrow buttons' strata/level were set INSIDE BuildCustom against the bar's strata AT
      -- THAT TIME ("HIGH") -- promoting the bar to DIALOG afterward left them a strata behind,
      -- same trap as the bar-vs-rows one described above, so they never rendered (there but hidden).
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  local function onMouseWheel(_, delta)
    if delta > 0 then
      setOffset(currentOffset - 1)
    else
      setOffset(currentOffset + 1)
    end
    refreshRows()
  end
  viewport:SetScript("OnMouseWheel", onMouseWheel)
  list:SetScript("OnMouseWheel", onMouseWheel)
  list:EnableMouseWheel(true)

  refreshRows()

  -- Deselect all three tiers. Used by the shift-click-to-search bridge: a "find this bag item"
  -- search must not be constrained by (and then silently miss under) whatever category happened
  -- to be selected from a previous browse.
  function list:ClearSelection()
    selectedCat, selectedSub, selectedInv = nil, nil, nil
    refreshRows()
  end

  list.Refresh = refreshRows
  list.Rows = rows
  return list
end

function AH.BuildBrowsePane(parent)
  local pane = CreateFrame("Frame", nil, parent)
  pane:SetAllPoints(parent)

  -- Build right-to-left with RELATIVE anchors (searchButton -> filterButton -> searchBox) so the
  -- three controls can never overlap regardless of individual widths. The previous version anchored
  -- filterButton and searchButton independently off pane:TOPRIGHT with fixed offsets that didn't
  -- account for both widths, so filterButton's right 12px sat underneath searchButton's left edge.
  local searchButton = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  searchButton:SetSize(120, 22)
  searchButton:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -8, -38)
  searchButton:SetText(SEARCH or "Search")
  pane.SearchButton = searchButton

  local filterButton = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  filterButton:SetSize(90, 22)
  filterButton:SetPoint("RIGHT", searchButton, "LEFT", -10, 0)
  filterButton:SetText(AUCTION_FILTER_SUBCATEGORY_INVENTORY_TYPE or "Filter")
  pane.FilterButton = filterButton

  -- Styled to match the professions crafting search box (modules/professions/RecipeList.lua) --
  -- plain EditBox + dark tooltip backdrop + left search icon + right clear "x", instead of the
  -- stock InputBoxTemplate's gold-inset look, for visual consistency across the addon's search
  -- fields.
  local searchBox = CreateFrame("EditBox", nil, pane)
  searchBox:SetAutoFocus(false)
  searchBox:SetHeight(20)
  searchBox:SetWidth(220)
  searchBox:SetPoint("TOPLEFT", pane, "TOPLEFT", 220, -38)
  searchBox:SetPoint("RIGHT", filterButton, "LEFT", -10, 0)
  searchBox:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
  searchBox:SetTextInsets(20, 18, 0, 0)
  if searchBox.SetBackdrop then
    searchBox:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    searchBox:SetBackdropColor(0, 0, 0, 0.6)
    searchBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end
  searchBox:SetText("")
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  pane.SearchBox = searchBox

  local searchIcon = searchBox:CreateTexture(nil, "OVERLAY")
  searchIcon:SetSize(14, 14)
  searchIcon:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
  searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

  local searchClear = CreateFrame("Button", nil, searchBox)
  searchClear:SetSize(16, 16)
  searchClear:SetPoint("RIGHT", searchBox, "RIGHT", -2, 0)
  local searchClearTex = searchClear:CreateTexture(nil, "OVERLAY")
  searchClearTex:SetAllPoints(searchClear)
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(searchClearTex, "common-search-clearbutton", false)) then
    searchClearTex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  end
  searchClear:Hide()
  searchClear:SetScript("OnClick", function()
    searchBox:SetText("")
    searchBox:ClearFocus()
  end)
  searchBox:HookScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    if txt ~= "" then searchClear:Show() else searchClear:Hide() end
  end)
  pane.SearchClear = searchClear

  -- Filter popup: Level Range + Usable Items Only. Plain manual frame (not a dropdown/menu widget
  -- unavailable on 3.3.5a). Styled with the SAME gold-trim inset + dark fill used everywhere else
  -- in this window (categories/results panels), instead of the flat parchment DialogBox backdrop,
  -- for visual consistency. Sits in "FULLSCREEN_DIALOG" strata (above the window's own "DIALOG"
  -- strata) so it always draws above the results list header/rows regardless of sibling creation
  -- order -- the previous version shared "DIALOG" with the results list, which (being built later
  -- in this function) drew on top of the panel and made it unreadable.
  -- ISSUE #31: the rarity slot of QueryAuctionItems is an EXACT quality match, not a minimum, and
  -- its "any rarity" sentinel is -1 -- NOT 0. Server side (TrinityCore AuctionHouseMgr.cpp,
  -- BuildListAuctionItems): `if (quality != 0xffffffff && proto->Quality != quality) continue;`.
  -- Stock FrameXML agrees: Blizzard_AuctionUI.lua's BrowseDropDown_Initialize gives the ALL entry
  -- `info.value = -1`, and BrowseDropDown_OnLoad/AuctionFrameBrowse_Reset select -1.
  -- This field was previously named minQuality and defaulted to 0, so "All" searched for items of
  -- EXACTLY Poor quality and found nothing. Renamed to `quality` so the wrong mental model that
  -- caused the bug can't be read back out of the field name.
  pane.Filter = { minLevel = 0, maxLevel = 0, usable = false, quality = ANY_QUALITY }

  local filterPanel = CreateFrame("Frame", nil, pane)
  filterPanel:SetFrameStrata("FULLSCREEN_DIALOG")
  filterPanel:EnableMouse(true)
  filterPanel:Hide()
  filterPanel:SetPoint("TOPRIGHT", filterButton, "BOTTOMRIGHT", 0, -6)
  filterPanel:SetSize(184, 262)
  pane.FilterPanel = filterPanel

  -- Grey fill matching THIS window's own header-strip tone (the results list's Price/Name/
  -- Available header row, a few lines below), not a value borrowed from an unrelated module --
  -- that mismatched against everything else in the Auction House window, which is uniformly dark.
  local filterBg = filterPanel:CreateTexture(nil, "BACKGROUND")
  filterBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  filterBg:SetVertexColor(0.06, 0.06, 0.07, 0.97)
  filterBg:SetAllPoints(filterPanel)

  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, filterPanel, 0, 0, 0, 0)
  end

  local lvlTitle = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lvlTitle:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 14, -14)
  lvlTitle:SetText(AUCTION_HOUSE_FILTER_DROP_DOWN_LEVEL_RANGE or "Level Range")
  lvlTitle:SetTextColor(1, 0.82, 0)

  local function lvlBox()
    local b = CreateFrame("EditBox", nil, filterPanel, "InputBoxTemplate")
    b:SetSize(32, 20)
    b:SetAutoFocus(false)
    b:SetNumeric(true)
    b:SetMaxLetters(2)
    b:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    return b
  end

  local minBox = lvlBox()
  minBox:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 22, -36)
  local dash = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dash:SetPoint("LEFT", minBox, "RIGHT", 10, 0)
  dash:SetText("-")
  local maxBox = lvlBox()
  maxBox:SetPoint("LEFT", dash, "RIGHT", 10, 0)

  local function commitLevels()
    pane.Filter.minLevel = minBox:GetNumber() or 0
    pane.Filter.maxLevel = maxBox:GetNumber() or 0
  end
  minBox:SetScript("OnEditFocusLost", commitLevels)
  maxBox:SetScript("OnEditFocusLost", commitLevels)
  minBox:SetScript("OnTextChanged", commitLevels)
  maxBox:SetScript("OnTextChanged", commitLevels)

  local divider = filterPanel:CreateTexture(nil, "ARTWORK")
  divider:SetTexture("Interface\\Buttons\\WHITE8X8")
  divider:SetVertexColor(1, 0.82, 0, 0.25)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 12, -62)
  divider:SetPoint("TOPRIGHT", filterPanel, "TOPRIGHT", -12, -62)

  local usable = CreateFrame("CheckButton", nil, filterPanel, "UICheckButtonTemplate")
  usable:SetSize(24, 24)
  usable:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 10, -72)
  local usableLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  usableLabel:SetPoint("LEFT", usable, "RIGHT", 2, 0)
  usableLabel:SetText(AUCTION_HOUSE_FILTER_USABLE_ONLY or USABLE_ITEMS or "Usable Items Only")
  usable:SetScript("OnClick", function(self)
    pane.Filter.usable = self:GetChecked() and true or false
  end)

  local divider2 = filterPanel:CreateTexture(nil, "ARTWORK")
  divider2:SetTexture("Interface\\Buttons\\WHITE8X8")
  divider2:SetVertexColor(1, 0.82, 0, 0.25)
  divider2:SetHeight(1)
  divider2:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 12, -104)
  divider2:SetPoint("TOPRIGHT", filterPanel, "TOPRIGHT", -12, -104)

  local rarityTitle = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rarityTitle:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 14, -114)
  rarityTitle:SetText(RARITY or "Rarity")
  rarityTitle:SetTextColor(1, 0.82, 0)

  -- Rarity radios (All + Poor..Epic). No dedicated radio-button XML template is trusted here --
  -- "RefreshButtonTemplate" already proved reference-addon template assumptions don't hold on this
  -- exact client build (see the detailRefresh comment above), so this reuses the SAME
  -- UICheckButtonTemplate the Usable Items checkbox above already uses safely, with hand-rolled
  -- mutual exclusivity instead of relying on a native radio widget.
  local rarityBtns = {}
  local function setRarity(val)
    -- ANY_QUALITY (-1), not 0 -- see the pane.Filter note above. The "All" row used to pass nil
    -- here, which `or 0` then turned into a Poor-only filter.
    pane.Filter.quality = val or ANY_QUALITY
    for _, rb in ipairs(rarityBtns) do rb:SetChecked(rb._val == val) end
  end
  local function rarityRow(y, val, label)
    local rb = CreateFrame("CheckButton", nil, filterPanel, "UICheckButtonTemplate")
    rb:SetSize(18, 18)
    rb:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", 12, y)
    rb._val = val
    local fs = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    fs:SetText(label)
    rb:SetScript("OnClick", function() setRarity(val) end)
    rarityBtns[#rarityBtns + 1] = rb
  end
  rarityRow(-134, ANY_QUALITY, ALL or "All")
  rarityRow(-153, 0, NE.itembtn and NE.itembtn.WrapTextByQuality(_G.ITEM_QUALITY0_DESC or "Poor", 0) or (_G.ITEM_QUALITY0_DESC or "Poor"))
  rarityRow(-172, 1, NE.itembtn and NE.itembtn.WrapTextByQuality(_G.ITEM_QUALITY1_DESC or "Common", 1) or (_G.ITEM_QUALITY1_DESC or "Common"))
  rarityRow(-191, 2, NE.itembtn and NE.itembtn.WrapTextByQuality(_G.ITEM_QUALITY2_DESC or "Uncommon", 2) or (_G.ITEM_QUALITY2_DESC or "Uncommon"))
  rarityRow(-210, 3, NE.itembtn and NE.itembtn.WrapTextByQuality(_G.ITEM_QUALITY3_DESC or "Rare", 3) or (_G.ITEM_QUALITY3_DESC or "Rare"))
  rarityRow(-229, 4, NE.itembtn and NE.itembtn.WrapTextByQuality(_G.ITEM_QUALITY4_DESC or "Epic", 4) or (_G.ITEM_QUALITY4_DESC or "Epic"))
  setRarity(ANY_QUALITY)

  filterButton:SetScript("OnClick", function() filterPanel:SetShown(not filterPanel:IsShown()) end)

  -- Click-outside-to-close: a fullscreen catcher one frame level under the panel, same strata so
  -- it still sits above the rest of the window and intercepts the outside click.
  local filterCatcher = CreateFrame("Button", nil, filterPanel)
  filterCatcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
  filterCatcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
  filterCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
  filterCatcher:SetFrameLevel(math.max((filterPanel:GetFrameLevel() or 1) - 1, 0))
  filterCatcher:EnableMouse(true)
  filterCatcher:Hide()
  filterCatcher:SetScript("OnClick", function() filterPanel:Hide() end)
  filterPanel:HookScript("OnShow", function() filterCatcher:Show() end)
  filterPanel:HookScript("OnHide", function() filterCatcher:Hide() end)
  pane:HookScript("OnHide", function() filterPanel:Hide() end)

  local list = CreateFrame("Frame", nil, pane)
  list:SetPoint("TOPLEFT", pane, "TOPLEFT", 172, -73)
  -- -5, matching the Sell tab's right-hand panel (Sell.lua's `right`) -- previously -24, which cut
  -- this panel 19px shorter than Sell's and left its right edge not lining up across tabs.
  list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -5, 27)
  pane.Results = list

  local listFallback = list:CreateTexture(nil, "BACKGROUND")
  listFallback:SetTexture("Interface\\Buttons\\WHITE8X8")
  listFallback:SetVertexColor(0.02, 0.02, 0.025, 0.92)
  listFallback:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -22)
  listFallback:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -22, 0)

  local listBg = list:CreateTexture(nil, "BACKGROUND")
  local appliedIndexAtlas = false
  if NE.tex and NE.tex.SetAtlas then
    appliedIndexAtlas = NE.tex.SetAtlas(listBg, "auctionhouse-background-index", false) and true or false
  end
  if appliedIndexAtlas then
    listBg:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -22)
    listBg:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -22, 0)
  else
    listBg:SetTexture(nil)
  end

  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, list, 0, -19, -22, 0)
  end

  local headerStrip = list:CreateTexture(nil, "BORDER")
  headerStrip:SetTexture("Interface\\Buttons\\WHITE8X8")
  headerStrip:SetVertexColor(0.06, 0.06, 0.07, 0.95)
  headerStrip:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -1)
  headerStrip:SetPoint("TOPRIGHT", list, "TOPRIGHT", -22, -1)
  headerStrip:SetHeight(21)

  -- Sortable column headers (issue #17: no way to sort results by price/quantity). Each header is
  -- a click target: first click sorts the aggregated results by that column ascending, second click
  -- flips direction. Sorting happens client-side over the fully-scanned aggregate (sortDisplayRows,
  -- defined with the paging helpers below and forward-declared here because the header buttons are
  -- built before the data pipeline exists).
  local sortKey = nil
  local sortAsc = true
  local applySort -- assigned below once the paging helpers it drives exist
  local headerButtons = {}

  -- Right-anchored header `x` values are chosen so the header text's right edge lands exactly on its
  -- column's right edge in the rows below: rows are inset -30 from `list`, their own content another
  -- -8 (or -96 for Lvl), so -38 / -126 here. ("Available" previously sat at -80, floating 42px left
  -- of the numbers it labels -- with a Lvl column now next to it that gap reads as a misprint.)
  local headers = {
    { text = AUCTION_HOUSE_BROWSE_HEADER_PRICE or "Price", x = 10, w = 120, just = "LEFT", key = "price" },
    { text = AUCTION_HOUSE_BROWSE_HEADER_NAME or NAME or "Name", x = 180, w = 260, just = "LEFT", key = "name" },
    -- "Lvl" (the stock AH's own name for the required-level column) rather than a spelled-out
    -- "Req. Level": the same column has to fit the much tighter item-detail header strip below, and
    -- one label across both views beats a wide one here and an abbreviation there.
    { text = "Lvl", x = -126, w = 64, just = "RIGHT", right = true, key = "level" },
    { text = AUCTION_HOUSE_BROWSE_HEADER_QUANTITY or "Available", x = -38, w = 72, just = "RIGHT", right = true, key = "qty" },
  }

  for i = 1, #headers do
    local h = headers[i]
    local hb = CreateFrame("Button", nil, list)
    hb:SetSize(h.w, 21)
    if h.right then
      hb:SetPoint("TOPRIGHT", list, "TOPRIGHT", h.x, -1)
    else
      hb:SetPoint("TOPLEFT", list, "TOPLEFT", h.x, -1)
    end

    local fs = hb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", hb, "LEFT", 0, 0)
    fs:SetWidth(h.w)
    fs:SetJustifyH(h.just)
    fs:SetText(h.text)
    hb.Label = fs

    -- Same sort-direction arrow sheet the stock Who/Guild column headers use; up = ascending.
    local arrow = hb:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:Hide()
    hb.Arrow = arrow

    hb:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hhl = hb:GetHighlightTexture()
    if hhl then
      hhl:SetVertexColor(1, 0.82, 0, 0.08)
      hhl:SetBlendMode("ADD")
    end

    hb._sortKey = h.key
    hb._just = h.just
    hb:SetScript("OnClick", function(self)
      if applySort then applySort(self._sortKey) end
    end)
    headerButtons[#headerButtons + 1] = hb
  end

  local function updateHeaderArrows()
    for i = 1, #headerButtons do
      local hb = headerButtons[i]
      if hb._sortKey == sortKey then
        -- Positioned off the label's live string width so the arrow hugs the text no matter the
        -- localized header length. Right-justified labels get the arrow on their left instead.
        local tw = (hb.Label.GetStringWidth and hb.Label:GetStringWidth()) or 40
        hb.Arrow:ClearAllPoints()
        if hb._just == "RIGHT" then
          hb.Arrow:SetPoint("RIGHT", hb, "RIGHT", -(tw + 4), 0)
        else
          hb.Arrow:SetPoint("LEFT", hb, "LEFT", math.min(tw + 3, hb:GetWidth() - 9), 0)
        end
        if sortAsc then
          hb.Arrow:SetTexCoord(0, 0.5625, 1.0, 0)
        else
          hb.Arrow:SetTexCoord(0, 0.5625, 0, 1.0)
        end
        hb.Arrow:Show()
      else
        hb.Arrow:Hide()
      end
    end
  end

  local empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("CENTER", list, "CENTER", 0, 44)
  empty:SetText("Choose search criteria and press \"Search\"")
  empty:SetTextColor(1, 0.82, 0)
  pane.EmptyText = empty

  local RESULTS_TOP = -24
  local ROW_H = 20

  local rows = {}
  local rowsHost = CreateFrame("Frame", nil, list)
  rowsHost:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  rowsHost:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
  rowsHost:SetFrameStrata("DIALOG")
  rowsHost:SetFrameLevel((list:GetFrameLevel() or 1) + 20)

  -- FauxScrollFrameTemplate's handlers resolve the scrollbar's sub-widgets via frame:GetName()
  -- string concatenation, NOT parentKey -- an anonymous (nil-named) FauxScrollFrame throws
  -- "attempt to concatenate ... (a nil value)" the moment FauxScrollFrame_Update runs on it. THIS
  -- was the actual reason the Buy tab got stuck on "Searching..." forever: refreshResults() called
  -- FauxScrollFrame_Update on this nameless frame, the resulting error aborted refreshResults()
  -- before it ever reached the empty:Hide()/row-population code below it, even though the data
  -- (listRows) was already correctly populated by that point.
  local scroll = CreateFrame("ScrollFrame", "NE_AuctionHouseBrowseResultsScroll", list, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 2, RESULTS_TOP)
  scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -26, 4)
  local resultsCustomBar

  -- Physical scrollbar track+thumb -- FauxScrollFrameTemplate alone draws nothing visible, just
  -- offset math plus a hidden slider. Sits in the 26px gutter reserved above, so it never overlaps
  -- the DIALOG-strata rows (they're inset -30 from list's right edge, see ensureRow below).
  -- BuildCustom's bar defaults to "HIGH" strata, but rowsHost (the actual row buttons, below) is
  -- explicitly "DIALOG" so it draws above the plain-strata list background -- that puts the rows
  -- ABOVE a HIGH-strata scrollbar too, hiding it entirely. Same trap already fixed for the item-
  -- detail scroll bar (see detailScroll below); force this bar to match.
  if NE.scrollbar and NE.scrollbar.BuildCustom then
    local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, { x = -8, alwaysShow = true })
    if ok and bar then
      resultsCustomBar = bar
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((rowsHost:GetFrameLevel() or 1) + 10)
      -- See the matching comment on the category-list scrollbar above -- the arrow buttons need
      -- the same post-hoc strata promotion the bar itself gets, or they stay stuck at "HIGH".
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  local function setResultsScrollbarShown(shown)
    if not resultsCustomBar then return end
    if shown then
      resultsCustomBar:Show()
      if resultsCustomBar._upBtn then resultsCustomBar._upBtn:Show() end
      if resultsCustomBar._downBtn then resultsCustomBar._downBtn:Show() end
    else
      resultsCustomBar:Hide()
      if resultsCustomBar._upBtn then resultsCustomBar._upBtn:Hide() end
      if resultsCustomBar._downBtn then resultsCustomBar._downBtn:Hide() end
    end
  end

  local function setBrowseResultsShown(shown)
    if shown then
      list:Show()
    else
      list:Hide()
    end
    setResultsScrollbarShown(shown)
  end

  local function fsUpdate(frame, total, shown, step)
    if FauxScrollFrame_Update then
      FauxScrollFrame_Update(frame, total, shown, step)
    else
      frame.offset = frame.offset or 0
    end
  end

  local function fsGetOffset(frame)
    if FauxScrollFrame_GetOffset then
      return FauxScrollFrame_GetOffset(frame) or 0
    end
    return frame.offset or 0
  end

  local function moneyText(copper)
    if not copper or copper <= 0 then return "-" end
    if GetCoinTextureString then
      return GetCoinTextureString(copper)
    end
    return tostring(copper)
  end

  -- Required-level cell for both the aggregate results list and the item-detail listing rows.
  -- Returns text + colour: "-" for the level-1 / no-requirement case (same "nothing to show here"
  -- glyph moneyText uses), and red when the requirement is above the player's own level, matching
  -- the stock Auction House's Lvl column.
  local function levelText(level)
    if not level or level <= 1 then return "-", 1, 1, 1 end
    local playerLevel = UnitLevel and UnitLevel("player") or 0
    if playerLevel > 0 and level > playerLevel then
      local c = RED_FONT_COLOR
      if c then return tostring(level), c.r, c.g, c.b end
      return tostring(level), 1, 0.1, 0.1
    end
    return tostring(level), 1, 1, 1
  end

  local listRows = {}     -- every auction the scan collected, across all server pages
  local listTotal = 0     -- auctions the server says match, across all server pages
  local displayRows = {}  -- listRows collapsed to one entry per item name
  local pageRows = {}     -- the slice of displayRows currently drawn

  -- Page navigation -- Prev/Next + a "Page N of M" label in the gutter under the results list, using
  -- the same proven-safe UIPanelButtonTemplate the Search/Filter buttons above already use.
  --
  -- These paginate the aggregated ITEM rows, NOT the server's auction pages. A search used to map
  -- one server page onto one displayed page, which mixed two different units: QueryAuctionItems
  -- returns up to NUM_AUCTION_ITEMS_PER_PAGE (50) AUCTIONS, but buildDisplayRows collapses those by
  -- item name, so 50 auctions of 8 distinct glyphs drew 8 rows next to "of 6 pages" and read like 42
  -- rows went missing -- and each row's "cheapest" price was only the cheapest on that one page, not
  -- the market's. runSearch now scans every server page up front (see queryPage/collectScanPage) and
  -- paginates the aggregate client-side, so both numbers are in items and the prices are real minima.
  local ITEMS_PER_PAGE = 50
  local currentPage = 0
  local lastQuery = nil

  -- Scan state. MAX_SCAN_PAGES bounds a pathological search (an empty-text browse of a busy AH can
  -- match tens of thousands of auctions); scanTruncated records that we stopped early so the label
  -- can say so rather than quietly presenting a partial aggregate as the whole market.
  local MAX_SCAN_PAGES = 20
  local scanning = false
  local scanPage = 0
  local scanPages = 1
  local scanTruncated = false
  -- True from the moment a page is requested until its auctions are banked into listRows. Both the
  -- AUCTION_ITEM_LIST_UPDATE event and a poll timer can reach collectScanPage for the SAME page, so
  -- without this whichever arrived second would append that page's auctions a second time -- the
  -- aggregate would double every quantity and the auction count would exceed the server's total.
  local scanPending = false
  -- Bumped whenever the search is replaced or cleared. A scan spans many queries and timer
  -- callbacks, so every one of them carries the token it started under and bails if it no longer
  -- matches -- otherwise a retry still pending from an abandoned scan would resume into the NEXT
  -- search and splice a stale page's auctions into its aggregate.
  local scanToken = 0

  local pagePrev = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  pagePrev:SetSize(24, 20)
  pagePrev:SetText("<")
  pagePrev:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 3, -24)
  pagePrev:Disable()

  local pageNext = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  pageNext:SetSize(24, 20)
  pageNext:SetText(">")
  pageNext:SetPoint("LEFT", pagePrev, "RIGHT", 4, 0)
  pageNext:Disable()

  local pageLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pageLabel:SetPoint("LEFT", pageNext, "RIGHT", 8, 0)
  pageLabel:SetText("Page 1 of 1")

  local function totalDisplayPages()
    return math.max(1, math.ceil(#displayRows / ITEMS_PER_PAGE))
  end

  local function updatePageControls()
    local totalItems = #displayRows
    local totalPages = totalDisplayPages()

    -- Prev/Next stay disabled mid-scan: displayRows is still growing a page at a time, so the page
    -- count it implies right now is not the final one.
    if scanning then
      pageLabel:SetText(string.format("Scanning page %d of %d...",
        math.min(scanPage + 1, scanPages), scanPages))
      pagePrev:Disable()
      pageNext:Disable()
      return
    end

    if totalItems <= 0 then
      pageLabel:SetText("Page 1 of 1")
    else
      local first = currentPage * ITEMS_PER_PAGE + 1
      local last = math.min(first + ITEMS_PER_PAGE - 1, totalItems)
      pageLabel:SetText(string.format("Page %d of %d  (items %d-%d of %d, from %d auction%s%s)",
        currentPage + 1, totalPages, first, last, totalItems,
        listTotal, listTotal == 1 and "" or "s",
        scanTruncated and " -- partial scan" or ""))
    end

    if currentPage <= 0 then pagePrev:Disable() else pagePrev:Enable() end
    if currentPage + 1 >= totalPages then pageNext:Disable() else pageNext:Enable() end
  end

  -- "browse" (aggregate results list, below) or "itembuy" (the per-item drill-down built near the
  -- end of this function). Both share the client's single "list" query slot and its
  -- AUCTION_ITEM_LIST_UPDATE event, so this flag routes that shared watcher to the right refresher
  -- -- opening the drill-down re-queries "list" scoped to one item, which would otherwise silently
  -- clobber the aggregate browse rows with that one item's data.
  local activeQuery = "browse"
  -- Forward decls: assigned once the drill-down widgets exist, near the end of this function, but
  -- referenced earlier (the aggregate row's OnClick, the shared watcher below).
  local openItemDetail
  local refreshDetailRows

  -- Switching away from Buy (Sell/Auctions tab, or closing the window) while the item drill-down
  -- is open would otherwise leave activeQuery == "itembuy" and keep routing the shared
  -- AUCTION_ITEM_LIST_UPDATE watcher away from the browse list on return.
  pane:HookScript("OnHide", function()
    activeQuery = "browse"
    if pane.ItemDetail then pane.ItemDetail:Hide() end
    setBrowseResultsShown(true)
  end)

  local function getListCounts()
    if type(GetNumAuctionItems) ~= "function" then
      return 0, 0
    end
    local batch, total = GetNumAuctionItems("list")
    batch = (type(batch) == "number" and batch) or 0
    total = (type(total) == "number" and total) or batch
    if total < batch then
      total = batch
    end
    return batch, total
  end

  -- Read whatever the client currently has in its "list" slot -- i.e. ONE server page of auctions.
  -- Pure: the caller (collectScanPage) owns listRows/listTotal, because a search accumulates many
  -- of these pages before anything is drawn.
  local function capturePageAuctions()
    local rows = {}
    local batchCount, totalCount = getListCounts()

    local cap = batchCount
    if cap <= 0 then
      cap = NUM_AUCTION_ITEMS_PER_PAGE or 50
    end

    for index = 1, cap do
      -- Field order per THIS server's own bundled APIDocumentation addon (13 return values, no
      -- "levelColumnName" slot the generic retail/Wowpedia signature has): name, texture, count,
      -- quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highestBidder, owner,
      -- sold. minBid is position 7 and buyoutPrice is position 9 on THIS client.
      -- `level` (slot 6) is the item's REQUIRED level on this client, not its item level -- it's what
      -- the stock AH's own "Lvl" column shows.
      local name, texture, count, quality, _, level, minBid, _, buyoutPrice = GetAuctionItemInfo("list", index)
      if not name then
        break
      end
      local link = GetAuctionItemLink and GetAuctionItemLink("list", index)
      -- No auction index is kept: it only addresses the page currently in the client's "list" slot,
      -- and these rows outlive that page (they're accumulated across the whole scan). Acting on a
      -- specific listing goes through the drill-down, which re-queries "list" for one item.
      rows[#rows + 1] = {
        name = name,
        texture = texture,
        quality = quality,
        count = count,
        level = level,
        minBid = minBid,
        buyoutPrice = buyoutPrice,
        link = link,
      }
    end

    return rows, batchCount, totalCount
  end

  -- Group the raw per-auction rows above by item name into one row per item (icon, quality-colored
  -- name, cheapest current price, total quantity across every auction of that item) -- matching the
  -- reference's aggregated Browse view. Clicking an aggregate row re-queries and drills into the
  -- individual auctions (openItemDetail, near the end of this function). listRows spans every server
  -- page by the time the scan finishes, so the price here is the whole result set's minimum.
  local function buildDisplayRows()
    local groups = {}
    local order = {}
    for i = 1, #listRows do
      local r = listRows[i]
      local g = groups[r.name]
      if not g then
        g = { name = r.name, texture = r.texture, quality = r.quality, count = 0 }
        groups[r.name] = g
        order[#order + 1] = g
      end
      g.link = g.link or r.link
      -- Required level is a property of the item, so it's uniform across a group by construction --
      -- first non-nil wins (the server can leave it nil on a row it hasn't filled in yet).
      g.level = g.level or r.level
      g.count = g.count + (r.count or 1)
      if r.buyoutPrice and r.buyoutPrice > 0 then
        if not g.minBuyout or r.buyoutPrice < g.minBuyout then g.minBuyout = r.buyoutPrice end
      end
      if r.minBid and r.minBid > 0 then
        if not g.minBid or r.minBid < g.minBid then g.minBid = r.minBid end
      end
    end
    displayRows = order
  end

  -- Slice displayRows down to the page the pager is on. Call after every buildDisplayRows and after
  -- any currentPage change; clamps currentPage so a shrinking result set can't strand the pager past
  -- the last page.
  local function buildPageRows()
    local totalPages = totalDisplayPages()
    if currentPage < 0 then currentPage = 0 end
    if currentPage > totalPages - 1 then currentPage = totalPages - 1 end

    local slice = {}
    local first = currentPage * ITEMS_PER_PAGE + 1
    local last = math.min(first + ITEMS_PER_PAGE - 1, #displayRows)
    for i = first, last do
      slice[#slice + 1] = displayRows[i]
    end
    pageRows = slice
  end

  -- Fill the entire scroll viewport instead of a hardcoded row count -- previously a fixed 17 rows
  -- left most of the panel's actual (much taller) height as dead space below the last row, same bug
  -- already fixed on the item-detail rows below (see detailVisibleRows).
  local function resultsVisibleRows()
    local h = scroll:GetHeight() or 0
    return math.max(1, math.floor(h / (ROW_H + 1)))
  end

  local function ensureRow(i)
    local row = rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, rowsHost)
    row:SetFrameStrata("DIALOG")
    row:SetHeight(ROW_H)
    row:SetFrameLevel((list:GetFrameLevel() or 1) + 10)
    if i == 1 then
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 6, RESULTS_TOP)
      row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -30, RESULTS_TOP)
    else
      row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -1)
      row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, -1)
    end

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    rowBg:SetAllPoints(row)
    rowBg:SetVertexColor(0.07, 0.07, 0.08, (i % 2 == 0) and 0.30 or 0.20)
    row.Bg = rowBg

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = row:GetHighlightTexture()
    if hl then
      hl:SetVertexColor(1, 0.82, 0, 0.12)
      hl:SetBlendMode("ADD")
    end

    local price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    price:SetPoint("LEFT", row, "LEFT", 4, 0)
    price:SetWidth(164)
    price:SetJustifyH("LEFT")
    row.Price = price

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 174, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -148, 0)
    name:SetJustifyH("LEFT")
    row.Name = name

    local level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    level:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    level:SetWidth(44)
    level:SetJustifyH("RIGHT")
    row.Level = level

    local qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qty:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    qty:SetWidth(80)
    qty:SetJustifyH("RIGHT")
    row.Qty = qty

    -- Click drills into this item's individual auctions (the ItemBuy-style page built near the end
    -- of this function), matching the reference's two-tier Browse -> item-detail flow. These rows
    -- are aggregated across auctions, so show a normal item tooltip from the item link rather than
    -- an auction-index tooltip bound to one specific listing.
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      -- SHIFT links the item in chat, CTRL dresses it up; otherwise drill into the item.
      if self._data and self._data.link and AH.HandleItemClick(self._data.link) then return end
      if openItemDetail then openItemDetail(self._data) end
    end)
    -- WireLiveTooltip, not a bare OnEnter: the tooltip has to keep refreshing while the mouse sits
    -- still, or pressing SHIFT after hovering never brings up the item comparison (it only worked
    -- if SHIFT was already held on mouse-over). Same stock UpdateTooltip contract bag buttons use.
    local function rowTooltip(self)
      if not (self._data and self._data.name) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local shown = self._data.link and pcall(GameTooltip.SetHyperlink, GameTooltip, self._data.link)
      if not shown then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self._data.name, 1, 1, 1)
      end
      GameTooltip:Show()
    end
    if NE.FrameUtil and NE.FrameUtil.WireLiveTooltip then
      NE.FrameUtil.WireLiveTooltip(row, rowTooltip)
    else
      row:SetScript("OnEnter", rowTooltip)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    rows[i] = row
    return row
  end

  local function refreshResults()
    local drawCount = #pageRows
    local visibleRows = resultsVisibleRows()
    fsUpdate(scroll, drawCount, visibleRows, ROW_H + 1)
    syncAlwaysShowFauxBar(scroll, drawCount, visibleRows)
    local offset = fsGetOffset(scroll)
    local maxOffset = drawCount - visibleRows
    if maxOffset < 0 then maxOffset = 0 end
    if offset > maxOffset then offset = maxOffset end

    if drawCount > 0 then
      empty:Hide()
    else
      empty:Show()
      if scanning then
        empty:SetText("Searching...")
      elseif listTotal > 0 then
        empty:SetText("Loading results...")
      else
        empty:SetText("No results. Adjust filters and search again.")
      end
    end

    for i = 1, visibleRows do
      local row = ensureRow(i)
      local data = pageRows[i + offset]
      if data then
        row._data = data
        row.Price:SetText(moneyText((data.minBuyout and data.minBuyout > 0) and data.minBuyout or data.minBid or 0))
        row.Name:SetText(data.name or "?")
        if data.quality and data.quality > 1 and GetItemQualityColor then
          local r, g, b = GetItemQualityColor(data.quality)
          row.Name:SetTextColor(r, g, b)
        else
          row.Name:SetTextColor(1, 1, 1)
        end
        if row.Icon then
          row.Icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        local lvText, lr, lg, lb = levelText(data.level)
        row.Level:SetText(lvText)
        row.Level:SetTextColor(lr, lg, lb)
        row.Qty:SetText(data.count and tostring(data.count) or "1")
        row:Show()
      else
        row._data = nil
        row:Hide()
      end
    end
    -- Hide any previously-built rows beyond the current viewport (only relevant if the panel's
    -- effective height ever shrinks between refreshes; harmless no-op otherwise).
    for i = visibleRows + 1, #rows do
      local row = rows[i]
      row._data = nil
      row:Hide()
    end
  end

  scroll:SetScript("OnVerticalScroll", function(self, offset)
    if FauxScrollFrame_OnVerticalScroll then
      FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H + 1, refreshResults)
    else
      local step = ROW_H + 1
      local nextOffset = math.floor((offset / step) + 0.5)
      if nextOffset < 0 then nextOffset = 0 end
      self.offset = nextOffset
      refreshResults()
    end
  end)

  -- Ask the server for one server page of the last search, reusing the filter/category params
  -- runSearch captured into `lastQuery`. This is a step of the scan, not a user-facing pager action:
  -- collectScanPage (further down, driven by AUCTION_ITEM_LIST_UPDATE) calls it again for the next
  -- page until every page is in, then the aggregate is drawn and Prev/Next page through THAT.
  local queryPage

  -- Abort the scan. Anything already collected stays on screen -- a partial aggregate still beats an
  -- empty list -- but scanTruncated makes the pager label admit it's partial, since these rows'
  -- prices are only minima across the pages we actually got.
  local function abortScan(message)
    scanning = false
    scanPending = false
    scanTruncated = true
    if #pageRows > 0 then
      if NE.Log then NE.Log("AH", "browse scan aborted: " .. tostring(message)) end
    else
      scanTruncated = false
      empty:SetText(message)
      empty:Show()
    end
    updatePageControls()
  end

  -- Tear down an INTERRUPTED scan.  ISSUE #31 ("the addon automatically triggers the search and
  -- refresh buttons without user input").
  --
  -- collectScanPage bails early when the pane is hidden (tab switch) or the item drill-down has
  -- taken over activeQuery -- both before it reaches `scanPending = false`. That left scanning and
  -- scanPending set with scanToken unchanged, and nothing else ever cleared them: runSearch and
  -- resetSearch are the only other writers and both need a user action. So the dead scan sat armed,
  -- and the next AUCTION_ITEM_LIST_UPDATE from ANY source -- the Sell tab's market lookup,
  -- Auctionator, the stock UI -- got accepted as its next page: it banked whatever rows were in the
  -- shared "list" slot into our aggregate, then chained queryPage for another server page. That is
  -- the search firing with nobody pressing anything (and the drill-down's mirror of it at
  -- refreshDetailRows is the Refresh button appearing to press itself).
  --
  -- The query arbiter above already stops us acting on updates we didn't cause; this closes the
  -- hole from the other side so there is no stranded state left for even our OWN events to revive.
  -- Deliberately redundant: this state machine has leaked once already.
  local function cancelScan()
    if not (scanning or scanPending) then return end
    scanning = false
    scanPending = false
    scanToken = scanToken + 1   -- orphan any in-flight retry/poll callbacks
    -- Whatever pages did land stay on screen, but the pager has to admit the aggregate is partial:
    -- these rows' prices are only minima across the pages we actually got.
    if #pageRows > 0 then scanTruncated = true end
    updatePageControls()
  end

  -- Window.lua hides the inactive pane on a tab switch, which is the other way collectScanPage
  -- bails out mid-scan. Same teardown.
  pane:HookScript("OnHide", cancelScan)

  -- Lets the Sell tab hold its market lookup while a scan is paging (see Sell.lua queryMarket):
  -- a query fired into the middle of a scan steals the shared throttle slot and makes queryPage
  -- burn its retries and abortScan.
  function AH.IsBrowseScanning()
    return scanning and true or false
  end

  -- The core rate-limits back-to-back list queries, and a scan issues one per server page. Wait out
  -- a busy slot rather than abandoning the scan mid-way, which would leave a partial aggregate whose
  -- prices silently aren't market minima.
  local scanRetries = 0
  local MAX_SCAN_RETRIES = 50 -- ~10s at 0.2s steps

  queryPage = function(page, token)
    if token ~= scanToken then return end
    if not lastQuery then return end

    if not (CanSendAuctionQuery and CanSendAuctionQuery("list")) then
      scanRetries = scanRetries + 1
      if scanRetries <= MAX_SCAN_RETRIES and C_Timer and C_Timer.After then
        C_Timer.After(0.2, function() queryPage(page, token) end)
      else
        abortScan("Auction query is throttled. Try again in a moment.")
      end
      return
    end
    scanRetries = 0

    scanning = true
    scanPage = page

    local q = lastQuery
    AH.ClaimListQuery("browse")
    local ok, err = pcall(QueryAuctionItems, q.text, q.minLevel, q.maxLevel, q.invTypeIndex, q.classIndex, q.subClassIndex, page, q.isUsable, q.quality, false)
    if not ok then
      -- Surface the real Lua error instead of a generic message -- if this still isn't the right
      -- call shape, the exact "bad argument #N" text tells us which slot to fix next.
      if NE.Log then NE.Log("AH", "QueryAuctionItems error: " .. tostring(err)) end
      abortScan("Search failed: " .. tostring(err))
      return
    end
    scanPending = true
    updatePageControls()
  end

  local function runSearch()
    -- Fresh scan from page 0: drop everything the previous search accumulated.
    listRows = {}
    listTotal = 0
    displayRows = {}
    pageRows = {}
    currentPage = 0
    scanPage = 0
    scanPages = 1
    scanTruncated = false
    scanToken = scanToken + 1
    scanPending = false
    -- Mark the scan live before the first draw below, so an empty list reads "Searching..." and not
    -- "No results" while queryPage is still waiting out a throttled query slot.
    scanning = true
    -- A fresh browse search always returns to the aggregate list -- close any open item drill-down
    -- so it can't keep routing the shared "list" query event and show a stale item's rows.
    activeQuery = "browse"
    if pane.ItemDetail then pane.ItemDetail:Hide() end
    setBrowseResultsShown(true)

    local q = searchBox:GetText() or ""
    q = string.gsub(q, "^%s+", "")
    q = string.gsub(q, "%s+$", "")

    -- 3.3.5a's QueryAuctionItems signature, confirmed against the stock client's own FrameXML
    -- (Blizzard_AuctionUI.lua AuctionFrameBrowse_SearchHelper): name, minLevel, maxLevel,
    -- invTypeIndex, classIndex, subClassIndex, page, isUsable, quality[, getAll]. Every one of
    -- those except getAll takes a concrete type (number/luaIndex/bool), so pass real typed values
    -- rather than nil, or a strict argument check on this core can reject the call outright.
    --
    -- The class/subclass/invtype slots are luaIndex values (1-based positions in
    -- GetAuctionItemClasses() etc.), so 0 correctly means "no filter" -- the client maps it to the
    -- server's 0xffffffff "any" sentinel. `quality` is NOT an index: it's a raw quality value that
    -- goes to the wire as-is, so its "any" sentinel has to be written out as -1. That asymmetry is
    -- exactly what issue #31 tripped over.
    local filter = pane.Filter or {}
    local minLevel = filter.minLevel or 0
    local maxLevel = filter.maxLevel or 0
    local isUsable = filter.usable and true or false
    -- ANY_QUALITY (-1) is the "no rarity filter" sentinel; 0 would mean "exactly Poor". Issue #31.
    local quality = filter.quality or ANY_QUALITY

    -- classIndex/subClassIndex/invTypeIndex from the left category tree (0/0/0 == no category
    -- filter). These are POSITIONAL luaIndex values into GetAuctionItemClasses()/
    -- GetAuctionItemSubClasses()/GetAuctionInvTypes(), which is exactly what pane.CategoryList
    -- tracks a click against -- see buildCategoryList's getClassNames/getSubClassNames/getInvTypes.
    -- Previously hardcoded to 0,0,0 here, so clicking a category never filtered.
    local classIndex, subClassIndex, invTypeIndex = 0, 0, 0
    if pane.CategoryList and pane.CategoryList.GetSelectedIndices then
      classIndex, subClassIndex, invTypeIndex = pane.CategoryList:GetSelectedIndices()
    end

    lastQuery = {
      text = q, minLevel = minLevel, maxLevel = maxLevel, invTypeIndex = invTypeIndex,
      classIndex = classIndex, subClassIndex = subClassIndex, isUsable = isUsable, quality = quality,
    }
    refreshResults()
    queryPage(0, scanToken)
  end

  -- Scroll the results list back to the top. The bar the user sees is our own custom one, but the
  -- offset refreshResults reads comes from the Faux slider underneath it (same lookup as
  -- syncAlwaysShowFauxBar), so that's what has to be driven.
  local function resetResultsScroll()
    if not scroll then return end
    if FauxScrollFrame_SetOffset then
      FauxScrollFrame_SetOffset(scroll, 0)
    else
      scroll.offset = 0
    end
    local sliderName = scroll.GetName and scroll:GetName()
    local slider = (sliderName and _G[sliderName .. "ScrollBar"]) or scroll.ScrollBar or scroll.scrollBar
    if slider and slider.SetValue then slider:SetValue(0) end
  end

  -- Pure client-side paging over the already-scanned aggregate: no re-query, so no throttle and no
  -- wait. Guarded against running mid-scan because displayRows is still growing then, so the slice
  -- taken here would be re-sliced from different content a moment later.
  local function showPage(page)
    if scanning then return end
    currentPage = page
    buildPageRows()
    resetResultsScroll()
    refreshResults()
    updatePageControls()
  end

  pagePrev:SetScript("OnClick", function()
    if currentPage > 0 then showPage(currentPage - 1) end
  end)
  pageNext:SetScript("OnClick", function()
    if currentPage + 1 < totalDisplayPages() then showPage(currentPage + 1) end
  end)

  -- The price a row DISPLAYS (min buyout, else min bid) is also the price it sorts by, so what the
  -- user sees in the Price column is exactly what the column orders on. nil = no price shown ("-").
  local function effectiveItemPrice(g)
    if g.minBuyout and g.minBuyout > 0 then return g.minBuyout end
    if g.minBid and g.minBid > 0 then return g.minBid end
    return nil
  end

  -- In-place sort of the full aggregate (all pages of it) by the active header column. Called
  -- after every buildDisplayRows so a mid-scan redraw and a finished scan both come out ordered.
  local function sortDisplayRows()
    if not sortKey then return end
    local key, asc = sortKey, sortAsc
    table.sort(displayRows, function(a, b)
      local av, bv
      if key == "price" then
        av, bv = effectiveItemPrice(a), effectiveItemPrice(b)
        -- Priceless rows ("-") always sink to the bottom, whichever direction is active.
        if (av ~= nil) ~= (bv ~= nil) then return av ~= nil end
        if av == nil then av, bv = 0, 0 end
      elseif key == "qty" then
        av, bv = a.count or 0, b.count or 0
      elseif key == "level" then
        av, bv = a.level or 0, b.level or 0
      else
        av, bv = a.name or "", b.name or ""
      end
      if av ~= bv then
        if asc then return av < bv else return av > bv end
      end
      -- Equal keys: fall back to name ascending (returns false on full ties, keeping the
      -- comparator a valid strict order for table.sort).
      return (a.name or "") < (b.name or "")
    end)
  end

  applySort = function(key)
    if sortKey == key then
      sortAsc = not sortAsc
    else
      sortKey = key
      sortAsc = true
    end
    updateHeaderArrows()
    sortDisplayRows()
    -- Reordering invalidates the current page slice; snap back to page 1 of the new order.
    currentPage = 0
    buildPageRows()
    resetResultsScroll()
    refreshResults()
    updatePageControls()
  end

  -- Exposed so Window.lua can clear this pane's search state when the WHOLE Auction House window
  -- closes (AH.frame:Hide(), via AUCTION_HOUSE_CLOSED/ESC/close-button) -- not the same as switching
  -- away from the Buy tab, which only hides `pane` itself and is already handled by the OnHide hook
  -- below. Hiding the top-level frame does NOT fire OnHide on this pane (WoW only fires a frame's
  -- own OnHide from its own explicit :Hide() call, not from an ancestor's), so without this the next
  -- AUCTION_HOUSE_SHOW would still be showing whatever was searched last session.
  local function resetSearch()
    listRows = {}
    listTotal = 0
    displayRows = {}
    pageRows = {}
    activeQuery = "browse"
    currentPage = 0
    lastQuery = nil
    -- Clearing lastQuery already makes queryPage a no-op, so an in-flight scan can't resume against
    -- the search we just threw away; drop the scanning flag too so the label/pager leave that state.
    scanning = false
    scanPage = 0
    scanPages = 1
    scanTruncated = false
    scanToken = scanToken + 1
    scanPending = false
    if pane.ItemDetail then pane.ItemDetail:Hide() end
    setBrowseResultsShown(true)
    searchBox:SetText("")
    searchBox:ClearFocus()
    empty:SetText("Choose search criteria and press \"Search\"")
    refreshResults()
    updatePageControls()
  end
  pane.ResetSearch = resetSearch

  searchButton:SetScript("OnClick", runSearch)
  searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    runSearch()
  end)

  -- The client reports GetNumAuctionItems("list") counts before GetAuctionItemInfo has the
  -- per-index data ready, so a single read can still race the server response. Poll on a short timer
  -- until this page's rows actually populate (or we give up) instead of trying just once.
  local pollAttempts = 0
  local MAX_POLL_ATTEMPTS = 40 -- ~4s at 0.1s steps

  -- One page of the scan landed: fold it into listRows, redraw so results visibly accumulate, then
  -- either chain to the next server page or finish. Drives the whole scan together with queryPage.
  local collectScanPage
  collectScanPage = function(token)
    if token ~= scanToken then return end
    if not scanning then return end
    if not scanPending then return end
    if not (pane and pane:IsShown()) then return end
    if activeQuery ~= "browse" then return end

    local rows, batchCount, totalCount = capturePageAuctions()

    -- Page not fully materialized yet -- wait for the rest rather than banking a short page, which
    -- would drop auctions out of the aggregate AND (since a short page looks like the last page)
    -- could end the scan early.
    if batchCount > 0 and #rows < batchCount then
      pollAttempts = pollAttempts + 1
      if pollAttempts < MAX_POLL_ATTEMPTS and C_Timer and C_Timer.After then
        C_Timer.After(0.1, function() collectScanPage(token) end)
        return
      end
    end
    pollAttempts = 0

    -- Past every bail-out: this page is being banked exactly once, right now.
    scanPending = false

    listTotal = totalCount
    for i = 1, #rows do
      listRows[#listRows + 1] = rows[i]
    end

    local perPage = NUM_AUCTION_ITEMS_PER_PAGE or 50
    local pages = math.max(1, math.ceil(totalCount / perPage))
    scanTruncated = pages > MAX_SCAN_PAGES
    if scanTruncated then pages = MAX_SCAN_PAGES end
    scanPages = pages

    -- A page that came back short of the server's own per-page cap is the last one, whatever the
    -- total claimed -- keeps a stale/rounded total from spinning the scan on empty pages forever.
    local more = scanPage + 1 < pages and #rows >= perPage
    -- Clear `scanning` BEFORE drawing on the final page: refreshResults and updatePageControls both
    -- render scan-in-progress text, and this pass is the finished one.
    if not more then scanning = false end

    buildDisplayRows()
    sortDisplayRows()
    buildPageRows()
    -- pcall-wrapped: refreshResults calls the stock FauxScrollFrame_Update, which errors if the
    -- scroll frame is ever anonymous again (see the naming comment above) -- don't let a future
    -- regression there leave the UI stuck showing stale text with no visible feedback.
    local rrOk, rrErr = pcall(refreshResults)
    if not rrOk and NE.Log then
      NE.Log("AH", "refreshResults error: " .. tostring(rrErr))
    end
    updatePageControls()

    if more then
      queryPage(scanPage + 1, token)
    end
  end

  local watcher = CreateFrame("Frame", nil, pane)
  watcher:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
  watcher:SetScript("OnEvent", function()
    if not pane:IsShown() then return end
    if type(AuctionFrameBrowse_Update) == "function" then
      pcall(AuctionFrameBrowse_Update)
    end
    -- AuctionFrameBrowse_Update (stock FrameXML, called above so the legacy client's own internal
    -- state stays consistent) can reassert Show()/alpha on the legacy AH frame as part of its own
    -- normal update logic, undoing the one-time cloak from window-open time -- re-cloak on every
    -- single event (browse AND the item drill-down's own re-query both fire this) so its old
    -- parchment/stone background can never bleed back through.
    if AH.SuppressLegacyAuctionFrame then pcall(AH.SuppressLegacyAuctionFrame) end
    if AH.SuppressModernAuctionFrame then pcall(AH.SuppressModernAuctionFrame) end

    -- The item drill-down issues its own "list" query scoped to one item -- route this shared
    -- event to its refresher instead of the aggregate browse path while it's the active query.
    -- ISSUE #31: only when the drill-down's own query is the one that produced this update. It used
    -- to refresh on EVERY event, so a Sell-tab market lookup or an Auctionator scan reloaded the
    -- seller list out from under the user -- the Refresh button appearing to press itself.
    if activeQuery == "itembuy" then
      if refreshDetailRows and AH.OwnsListQuery("itembuy") then
        local rdOk, rdErr = pcall(refreshDetailRows)
        if not rdOk and NE.Log then
          NE.Log("AH", "refreshDetailRows error: " .. tostring(rdErr))
        end
      end
      return
    end

    -- This event is the scan's clock: each server page we asked for arrives here, gets folded in,
    -- and collectScanPage requests the next one. Ignore the event outside a scan -- an unsolicited
    -- AUCTION_ITEM_LIST_UPDATE (the stock UI, another addon, an owner/bidder query) is about a
    -- "list" slot we didn't fill and must not be spliced into our aggregate.
    -- ISSUE #31: `scanning` alone was not enough -- an interrupted scan could sit armed with
    -- scanning == true and let a foreign update drive it (see cancelScan). Require that the browse
    -- scan is also the current owner of the shared query slot.
    if not scanning then return end
    if not AH.OwnsListQuery("browse") then return end
    pollAttempts = 0
    local csOk, csErr = pcall(collectScanPage, scanToken)
    if not csOk and NE.Log then
      NE.Log("AH", "collectScanPage error: " .. tostring(csErr))
    end
  end)

  -- ================================================================================
  -- Item drill-down (retail's Buy -> ItemBuy two-tier flow): clicking an aggregate row above
  -- re-queries "list" scoped to that exact item name and lists every individual auction (Current
  -- Bid / Buyout / Qty / Seller / Time Left). Click a listing to select it, then Bid/Buyout acts on
  -- it. Confirmed against a live screenshot of the actual NewEra reference addon: the search bar
  -- STAYS visible/unhidden -- this overlay only occupies the categories/results footprint below
  -- it (same TOPLEFT the results list itself uses, 172,-73), with a plain Back/count/refresh row
  -- at its own top (no border around just that row), then the item header card and the auction
  -- list as two SEPARATE bordered boxes beneath it -- not one border wrapping the whole thing.
  -- ================================================================================
  local detail = CreateFrame("Frame", nil, pane)
  detail:SetFrameStrata("DIALOG")
  detail:SetFrameLevel((list:GetFrameLevel() or 1) + 30)
  detail:SetPoint("TOPLEFT", pane, "TOPLEFT", 172, -73)
  -- Matches `list`'s own right edge (-5, same as Sell's `right` panel) so this overlay lines up
  -- with the panel it sits on top of.
  detail:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -5, 27)
  detail:EnableMouse(true) -- swallow clicks so the hidden results list beneath can't be hit
  detail:Hide()
  pane.ItemDetail = detail

  local detailBg = detail:CreateTexture(nil, "BACKGROUND")
  detailBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  detailBg:SetVertexColor(0.045, 0.045, 0.05, 0.98)
  detailBg:SetAllPoints(detail)

  local detailBack = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
  detailBack:SetSize(90, 22)
  detailBack:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -8)
  detailBack:SetText(BACK or "Back")

  -- Refresh button: plain text, same UIPanelButtonTemplate every other button on this page uses.
  -- Two prior icon attempts both failed on THIS client build -- a hand-rolled
  -- Interface\Buttons\UI-RefreshButton texcoord split guessed the sheet layout wrong (rendered as
  -- a cut-off half-circle), and "RefreshButtonTemplate" (which the reference addon's own
  -- ItemList.lua assumes) doesn't exist as an inheritable XML template here at all -- CreateFrame
  -- threw "Couldn't find inherited node", which errored the ENTIRE pane builder (safeBuild's pcall
  -- caught it) and dropped the whole Buy tab to its fallback screen. A plain text button needs no
  -- texture asset at all, so it can't hit either failure mode.
  local detailRefresh = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
  detailRefresh:SetSize(70, 20)
  detailRefresh:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -6, -10)
  detailRefresh:SetText(REFRESH or "Refresh")

  local detailCount = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  detailCount:SetPoint("RIGHT", detailRefresh, "LEFT", -8, 0)
  detailCount:SetTextColor(1, 1, 1)

  -- "Sort Per Item" toggle (issue #17): the listings arrive cheapest-TOTAL-first, which buries a
  -- well-priced 20-stack under every cheap single. When checked, the list ranks by per-item buyout
  -- instead. Display is unaffected -- the Buyout (total) and Per Item columns are both always
  -- visible in the list, and the Bid/Buyout ACTION buttons always charge the listing's real total,
  -- which is what the confirm popup shows.
  -- Default ON: per-item price is the number that actually compares listings fairly, so it's the
  -- default ranking; untick to fall back to cheapest-total-first.
  local detailPerItem = true
  local detailPerItemCheck = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
  detailPerItemCheck:SetSize(22, 22)
  detailPerItemCheck:SetPoint("LEFT", detailBack, "RIGHT", 12, 0)
  detailPerItemCheck:SetChecked(true)
  local detailPerItemLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  detailPerItemLabel:SetPoint("LEFT", detailPerItemCheck, "RIGHT", 2, 0)
  detailPerItemLabel:SetText("Sort Per Item")
  detailPerItemCheck:SetScript("OnClick", function(self)
    detailPerItem = self:GetChecked() and true or false
    -- Re-read + re-sort the page the client already holds -- no fresh server query needed.
    if refreshDetailRows then pcall(refreshDetailRows) end
  end)

  -- Item header card (its own separate bordered box, not shared with the Back row above it). Real
  -- retail art per the reference addon's own atlas dump (ReferenceAddons/NewEra/Generated/
  -- AtlasData.lua) -- both atlases live on the SAME two sheet files this module already ships
  -- locally (3054898/3046538), just not previously registered here. Flat-fill/plain-square
  -- fallback if SetAtlas ever can't find them (missing/renamed asset), so a bad lookup degrades
  -- gracefully instead of leaving the header blank.
  local detailHeader = CreateFrame("Frame", nil, detail)
  detailHeader:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -36)
  detailHeader:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -6, -36)
  detailHeader:SetHeight(76)

  local detailHeaderFallback = detailHeader:CreateTexture(nil, "BACKGROUND", nil, -1)
  detailHeaderFallback:SetTexture("Interface\\Buttons\\WHITE8X8")
  detailHeaderFallback:SetVertexColor(0.06, 0.06, 0.07, 0.95)
  detailHeaderFallback:SetAllPoints(detailHeader)

  local detailHeaderBg = detailHeader:CreateTexture(nil, "BACKGROUND")
  if NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(detailHeaderBg, "auctionhouse-background-buy-noncommodities-header", false) then
    detailHeaderBg:SetPoint("TOPLEFT", detailHeader, "TOPLEFT", 3, -2)
    detailHeaderBg:SetPoint("BOTTOMRIGHT", detailHeader, "BOTTOMRIGHT", -3, 2)
  end
  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, detailHeader, 0, 0, 0, 0)
  end

  -- Item icon button + hover tooltip. Plain Frame, not CreateTexture, because only frames/buttons
  -- can receive OnEnter/OnLeave on 3.3.5a.
  local detailIconBtn = CreateFrame("Button", nil, detailHeader)
  detailIconBtn:SetSize(54, 54)
  detailIconBtn:SetPoint("LEFT", detailHeader, "LEFT", 12, 0)

  local detailIcon = detailIconBtn:CreateTexture(nil, "ARTWORK")
  detailIcon:SetSize(46, 46)
  detailIcon:SetPoint("CENTER")
  detailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Rarity glow -- NOT a ring atlas. A cropped/masked circular ring (the previous
  -- "auctionhouse-itemicon-border-white" atlas) reads as a big blue smear here because circular
  -- icon masking (CreateMaskTexture/AddMaskTexture) doesn't work on this 3.3.5a client (see
  -- core/Portrait.lua) -- there's no way to clip the ring down to just the visible band. Swapped
  -- to the SAME glow technique the professions crafting reagent slots and the bags window use
  -- instead: UI-ActionButton-Border, ADD blend, tinted per quality, oversized by ~35% so its own
  -- built-in transparent margin reaches the icon's edge.
  local detailRing = detailIconBtn:CreateTexture(nil, "OVERLAY")
  detailRing:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  detailRing:SetBlendMode("ADD")
  local detailGlowOver = math.max(8, math.floor(54 * 0.35 + 0.5))
  detailRing:SetPoint("TOPLEFT", detailIconBtn, "TOPLEFT", -detailGlowOver, detailGlowOver)
  detailRing:SetPoint("BOTTOMRIGHT", detailIconBtn, "BOTTOMRIGHT", detailGlowOver, -detailGlowOver)
  detailRing:Hide()

  -- Live-refreshed so shift-compare works mid-hover (see the aggregate row above).
  local function detailIconTooltip(self)
    local item = detail.CurrentItem
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = item.link and pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
    if not shown then
      GameTooltip:ClearLines()
      GameTooltip:AddLine(item.name or "", 1, 1, 1)
    end
    GameTooltip:Show()
  end
  if NE.FrameUtil and NE.FrameUtil.WireLiveTooltip then
    NE.FrameUtil.WireLiveTooltip(detailIconBtn, detailIconTooltip)
  else
    detailIconBtn:SetScript("OnEnter", detailIconTooltip)
    detailIconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  -- The drill-down header icon is an item too: same shift-to-link / ctrl-to-dress-up as the rows.
  detailIconBtn:RegisterForClicks("LeftButtonUp")
  detailIconBtn:SetScript("OnClick", function()
    local item = detail.CurrentItem
    if item and item.link then AH.HandleItemClick(item.link) end
  end)

  local detailName = detailHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  detailName:SetPoint("LEFT", detailIconBtn, "RIGHT", 14, 0)
  detailName:SetPoint("RIGHT", detailHeader, "RIGHT", -14, 0)
  detailName:SetJustifyH("LEFT")

  -- Bid / Buyout footer bar (acts on the currently-selected listing below; OnClick wired further
  -- down once detailSelected exists).
  local detailBar = CreateFrame("Frame", nil, detail)
  detailBar:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 6, 6)
  detailBar:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -6, 6)
  detailBar:SetHeight(22)

  local detailBuyoutBtn = CreateFrame("Button", nil, detailBar, "UIPanelButtonTemplate")
  detailBuyoutBtn:SetSize(110, 22)
  detailBuyoutBtn:SetPoint("RIGHT", detailBar, "RIGHT", 0, 0)
  detailBuyoutBtn:SetText(AUCTION_HOUSE_BUYOUT_BUTTON or BUYOUT or "Buyout")

  local detailBidBtn = CreateFrame("Button", nil, detailBar, "UIPanelButtonTemplate")
  detailBidBtn:SetSize(110, 22)
  detailBidBtn:SetPoint("RIGHT", detailBuyoutBtn, "LEFT", -6, 0)
  detailBidBtn:SetText(AUCTION_HOUSE_BID_BUTTON or BID or "Bid")

  -- Per-auction list.
  local detailList = CreateFrame("Frame", nil, detail)
  detailList:SetPoint("TOPLEFT", detailHeader, "BOTTOMLEFT", 0, -10)
  detailList:SetPoint("BOTTOMRIGHT", detailBar, "TOPRIGHT", 0, 6)

  -- Same always-present-fallback + optional-atlas-overlay pattern as the main results list's own
  -- listFallback/listBg pair above (search for "auctionhouse-background-index").
  local detailListFallback = detailList:CreateTexture(nil, "BACKGROUND")
  detailListFallback:SetTexture("Interface\\Buttons\\WHITE8X8")
  detailListFallback:SetVertexColor(0.02, 0.02, 0.025, 0.92)
  detailListFallback:SetPoint("TOPLEFT", detailList, "TOPLEFT", 3, -22)
  detailListFallback:SetPoint("BOTTOMRIGHT", detailList, "BOTTOMRIGHT", -22, 0)

  local detailListBg = detailList:CreateTexture(nil, "BACKGROUND")
  if NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(detailListBg, "auctionhouse-background-buy-noncommodities-market", false) then
    detailListBg:SetPoint("TOPLEFT", detailList, "TOPLEFT", 3, -22)
    detailListBg:SetPoint("BOTTOMRIGHT", detailList, "BOTTOMRIGHT", -22, 0)
  else
    detailListBg:SetTexture(nil)
  end

  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, detailList, 0, -19, -22, 0)
  end

  local detailHeaderStrip = detailList:CreateTexture(nil, "BORDER")
  detailHeaderStrip:SetTexture("Interface\\Buttons\\WHITE8X8")
  detailHeaderStrip:SetVertexColor(0.06, 0.06, 0.07, 0.95)
  detailHeaderStrip:SetPoint("TOPLEFT", detailList, "TOPLEFT", 3, -1)
  detailHeaderStrip:SetPoint("TOPRIGHT", detailList, "TOPRIGHT", -22, -1)
  detailHeaderStrip:SetHeight(21)

  -- Auctionator-style column order: the per-item price leads (it's the number listings are
  -- compared by), then the whole-stack Buyout and Current Bid, then the item's required level, a
  -- Quantity column wide enough for a grouped row's "6 stacks of 20" breakdown, and the Seller.
  -- Per Item and Buyout are BOTH always visible -- swapping one display into the other's column (an
  -- earlier iteration) made it impossible to see what a whole stack costs while comparing unit
  -- prices. Seller shows "Multiple" on a grouped row that spans several sellers; the row hover
  -- tooltip (see ensureDetailRow) is still where the full list of them lives.
  --
  -- The seven columns only fit across the ~575px row if the three money columns give up the slack
  -- they used to carry (110 -> 92), so every x/w below is load-bearing against its neighbours.
  -- Header x values match each column's own offset in ensureDetailRow plus the rows' 6px inset;
  -- Time Left's right anchor is -38 (rows are inset -30 from detailList, their text another -8),
  -- not the -80 it previously used, which floated the label 42px clear of its own column.
  local detailCols = {
    { text = "Per Item",                                               x = 6,   w = 92, just = "RIGHT" },
    { text = AUCTION_HOUSE_HEADER_BUYOUT or BUYOUT or "Buyout",        x = 104, w = 92, just = "RIGHT" },
    { text = AUCTION_HOUSE_HEADER_CURRENT_BID or BID or "Current Bid", x = 202, w = 92, just = "RIGHT" },
    { text = "Lvl",                                                    x = 300, w = 36, just = "RIGHT" },
    { text = AUCTION_HOUSE_HEADER_QUANTITY or "Quantity",              x = 344, w = 82, just = "LEFT" },
    { text = AUCTION_HOUSE_HEADER_SELLER or "Seller",                  x = 430, w = 76, just = "LEFT" },
    { text = AUCTION_HOUSE_HEADER_TIME_LEFT or "Time Left",            x = -38, w = 62, just = "RIGHT", right = true },
  }
  for i = 1, #detailCols do
    local h = detailCols[i]
    local fs = detailList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", detailList, "TOPLEFT", h.x, -7)
    if h.right then
      fs:ClearAllPoints()
      fs:SetPoint("TOPRIGHT", detailList, "TOPRIGHT", h.x, -7)
    end
    fs:SetWidth(h.w)
    fs:SetJustifyH(h.just)
    fs:SetText(h.text)
  end

  local detailEmpty = detailList:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  detailEmpty:SetPoint("CENTER", detailList, "CENTER", 0, 44)
  detailEmpty:SetTextColor(1, 0.82, 0)

  local DETAIL_ROW_H = 20
  local DETAIL_TOP = -24

  local detailRowWidgets = {}
  local detailRowsHost = CreateFrame("Frame", nil, detailList)
  detailRowsHost:SetPoint("TOPLEFT", detailList, "TOPLEFT", 0, 0)
  detailRowsHost:SetPoint("BOTTOMRIGHT", detailList, "BOTTOMRIGHT", 0, 0)
  detailRowsHost:SetFrameStrata("DIALOG")
  detailRowsHost:SetFrameLevel((detailList:GetFrameLevel() or 1) + 20)

  local detailScroll = CreateFrame("ScrollFrame", "NE_AuctionHouseItemBuyScroll", detailList, "FauxScrollFrameTemplate")
  detailScroll:SetPoint("TOPLEFT", detailList, "TOPLEFT", 2, DETAIL_TOP)
  detailScroll:SetPoint("BOTTOMRIGHT", detailList, "BOTTOMRIGHT", -26, 4)
  if NE.scrollbar and NE.scrollbar.BuildCustom then
    local ok, bar = pcall(NE.scrollbar.BuildCustom, detailScroll, { x = -8 })
    -- BuildCustom's bar defaults to "HIGH" strata, which is correct everywhere else it's used (plain
    -- MEDIUM-strata list hosts), but `detail` (this overlay's root) is deliberately "DIALOG" strata
    -- so it draws above the underlying browse results list -- every descendant frame that doesn't
    -- set its own strata (detailList, detailListBg/detailRowsHost) inherits that DIALOG level, which
    -- then sits ABOVE the scrollbar's HIGH strata and hides it behind the list background. Force the
    -- bar to match this overlay's own strata and sit above its row buttons.
    if ok and bar then
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((detailRowsHost:GetFrameLevel() or 1) + 10)
      -- Same post-hoc strata promotion the arrow buttons need everywhere else this pattern is used.
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  local detailRowsData = {}
  local detailSelected = nil
  local detailAutoResyncDone = false

  -- Fill the entire scroll viewport instead of a hardcoded row count -- previously a fixed 8 rows
  -- left most of the panel's actual (much taller) height as dead space below the last row.
  local function detailVisibleRows()
    local h = detailScroll:GetHeight() or 0
    return math.max(1, math.floor(h / (DETAIL_ROW_H + 1)))
  end

  -- GetAuctionItemTimeLeft is an enum (1-4) on this client; handle a raw seconds value too, just
  -- in case.
  local function detailTimeLeftText(v)
    if not v then return "" end
    local TL = {
      [1] = AUCTION_TIME_LEFT1 or "Short", [2] = AUCTION_TIME_LEFT2 or "Medium",
      [3] = AUCTION_TIME_LEFT3 or "Long",  [4] = AUCTION_TIME_LEFT4 or "Very Long",
    }
    if v >= 1 and v <= 4 and TL[v] then return TL[v] end
    return SecondsToTime and SecondsToTime(v) or tostring(v)
  end

  local function updateDetailActions()
    local r = detailSelected
    local canBuyout = r and r.buyout and r.buyout > 0
    local canBid = r and r.nextBid and r.nextBid > 0
    detailBuyoutBtn:SetEnabled(canBuyout and true or false)
    detailBidBtn:SetEnabled(canBid and true or false)
  end

  local function ensureDetailRow(i)
    local row = detailRowWidgets[i]
    if row then return row end

    row = CreateFrame("Button", nil, detailRowsHost)
    row:SetFrameStrata("DIALOG")
    row:SetHeight(DETAIL_ROW_H)
    row:SetFrameLevel((detailList:GetFrameLevel() or 1) + 10)
    if i == 1 then
      row:SetPoint("TOPLEFT", detailList, "TOPLEFT", 6, DETAIL_TOP)
      row:SetPoint("TOPRIGHT", detailList, "TOPRIGHT", -30, DETAIL_TOP)
    else
      row:SetPoint("TOPLEFT", detailRowWidgets[i - 1], "BOTTOMLEFT", 0, -1)
      row:SetPoint("TOPRIGHT", detailRowWidgets[i - 1], "BOTTOMRIGHT", 0, -1)
    end

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    rowBg:SetAllPoints(row)
    rowBg:SetVertexColor(0.07, 0.07, 0.08, (i % 2 == 0) and 0.30 or 0.20)
    row.Bg = rowBg

    local sel = row:CreateTexture(nil, "ARTWORK")
    sel:SetTexture("Interface\\Buttons\\WHITE8X8")
    sel:SetVertexColor(1, 0.82, 0, 0.25)
    sel:SetAllPoints(row)
    sel:Hide()
    row.Sel = sel

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = row:GetHighlightTexture()
    if hl then
      hl:SetVertexColor(1, 0.82, 0, 0.12)
      hl:SetBlendMode("ADD")
    end

    -- Offsets here are the source of truth the detailCols header x values are derived from; keep
    -- the two in step when touching either.
    local each = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    each:SetPoint("LEFT", row, "LEFT", 0, 0)
    each:SetWidth(92)
    each:SetJustifyH("RIGHT")
    row.Each = each

    local buyout = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buyout:SetPoint("LEFT", row, "LEFT", 98, 0)
    buyout:SetWidth(92)
    buyout:SetJustifyH("RIGHT")
    row.Buyout = buyout

    local bid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bid:SetPoint("LEFT", row, "LEFT", 196, 0)
    bid:SetWidth(92)
    bid:SetJustifyH("RIGHT")
    row.Bid = bid

    local level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    level:SetPoint("LEFT", row, "LEFT", 294, 0)
    level:SetWidth(36)
    level:SetJustifyH("RIGHT")
    row.Level = level

    local qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qty:SetPoint("LEFT", row, "LEFT", 338, 0)
    qty:SetWidth(82)
    qty:SetJustifyH("LEFT")
    row.Qty = qty

    local seller = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    seller:SetPoint("LEFT", row, "LEFT", 424, 0)
    seller:SetWidth(76)
    seller:SetJustifyH("LEFT")
    row.Seller = seller

    local time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    time:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    time:SetWidth(62)
    time:SetJustifyH("RIGHT")
    row.Time = time

    -- The Seller column only has room for one name, so a grouped row spanning several sellers shows
    -- "Multiple" and defers the full list to this tooltip.
    row:SetScript("OnEnter", function(self)
      local d = self._data
      if not d then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      if (d.num or 1) > 1 then
        GameTooltip:AddLine(string.format("%d auctions", d.num), 1, 0.82, 0)
      end
      -- Unique sellers, capped so one mass-poster's wall of alts can't grow a giant tooltip.
      -- owner can be nil on this client until the server fills it in; skip those.
      local sellers = d.owners or { d.owner }
      local seen, uniq = {}, {}
      for i = 1, #sellers do
        local s = sellers[i]
        if s and s ~= "" and not seen[s] then
          seen[s] = true
          uniq[#uniq + 1] = s
        end
      end
      if #uniq > 0 then
        local MAX_SHOWN = 8
        local label = (#uniq == 1) and (AUCTION_HOUSE_HEADER_SELLER or "Seller")
          or ((AUCTION_HOUSE_HEADER_SELLER or "Seller") .. "s")
        local names = table.concat(uniq, ", ", 1, math.min(#uniq, MAX_SHOWN))
        if #uniq > MAX_SHOWN then
          names = names .. string.format(" (+%d more)", #uniq - MAX_SHOWN)
        end
        GameTooltip:AddLine(label .. ": " .. names, 1, 1, 1, true)
      end
      if GameTooltip:NumLines() > 0 then
        GameTooltip:Show()
      else
        GameTooltip:Hide()
      end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      -- SHIFT links the item in chat, CTRL dresses it up; otherwise select this listing.
      if self._data and self._data.index then
        local link = GetAuctionItemLink and GetAuctionItemLink("list", self._data.index)
        if link and AH.HandleItemClick(link) then return end
      end
      detailSelected = self._data
      for _, rr in ipairs(detailRowWidgets) do
        if rr.Sel then rr.Sel:SetShown(rr._data ~= nil and rr._data == detailSelected) end
      end
      updateDetailActions()
    end)

    detailRowWidgets[i] = row
    return row
  end

  local function readDetailPage()
    local out = {}
    local batch = 0
    if type(GetNumAuctionItems) == "function" then
      batch = select(1, GetNumAuctionItems("list")) or 0
    end
    -- This client's QueryAuctionItems does a SUBSTRING search, not an exact-name match (there's no
    -- dedicated exact-match argument in its signature) -- searching "Linen Cloth" also returns
    -- "Bolt of Linen Cloth". Auctionator and the default 3.3.5a AH UI both filter the requeried
    -- page down to an EXACT name match client-side before listing/allowing a purchase; do the same
    -- here, or a click on "Linen Cloth" could end up placing a bid on a totally different listing
    -- that merely shares the substring.
    local wantName = detail.CurrentItem and detail.CurrentItem.name
    for i = 1, batch do
      -- Same 13-value field order as capturePageAuctions above.
      local name, _, count, _, _, level, minBid, minInc, buyout, bidAmt, _, owner = GetAuctionItemInfo("list", i)
      if name and (not wantName or name == wantName) then
        local cur = (bidAmt and bidAmt > 0) and bidAmt or minBid
        local tl = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("list", i)
        out[#out + 1] = {
          index = i, count = count or 1, level = level,
          curBid = cur, nextBid = (cur or 0) + (minInc or 0),
          buyout = buyout, owner = owner,
          hasBid = (bidAmt and bidAmt > 0) and true or false,
          timeText = detailTimeLeftText(tl),
        }
      end
    end

    -- Hybrid Auctionator-style condensing (issue #17 follow-up): listings that are identical from
    -- a buyer's point of view -- same stack size, same buyout, same starting bid, and NO bid in
    -- progress -- collapse into one row ("6 stacks of 1", "3 stacks of 2"), exactly how
    -- Auctionator's own scan does it (AtrScan:AddScanItem's numAuctions counter). Listings with an
    -- active bid (or no buyout at all) stay as individual rows: each carries its own bid state, so
    -- grouping them would hide which specific auction you'd be bidding against. A grouped row
    -- remembers every member's auction index (cheapest-index first); Bid/Buyout act on the first
    -- one, and the AUCTION_ITEM_LIST_UPDATE that follows a purchase re-reads and re-groups, so the
    -- stack count visibly ticks down with each buy. `key` identifies a row across those refreshes
    -- (group identity for grouped rows, auction index for singles) so the selection can survive.
    local groups = {}
    local condensed = {}
    for i = 1, #out do
      local r = out[i]
      if r.buyout and r.buyout > 0 and not r.hasBid then
        local key = (r.count or 1) .. ":" .. r.buyout .. ":" .. (r.curBid or 0)
        local g = groups[key]
        if not g then
          r.key = "g:" .. key
          r.num = 1
          r.indices = { r.index }
          r.owners = { r.owner }
          groups[key] = r
          condensed[#condensed + 1] = r
        else
          g.num = g.num + 1
          g.indices[#g.indices + 1] = r.index
          g.owners[#g.owners + 1] = r.owner
          -- Per-member fields only survive on the group while they're uniform across it.
          if g.owner ~= r.owner then g.owner = nil end
          if g.timeText ~= r.timeText then g.timeText = "" end
        end
      else
        r.key = "i:" .. r.index
        r.num = 1
        condensed[#condensed + 1] = r
      end
    end
    out = condensed

    -- Explicit cheapest-first ordering (issue #17) instead of trusting whatever order the server
    -- returned the page in: listings WITH a buyout first (ranked by total buyout, or by per-item
    -- buyout when the Sort Per Item toggle is on), then bid-only listings ranked by current bid,
    -- with the auction index as a stable final tiebreak.
    local function rankPrice(r)
      local bo = (r.buyout and r.buyout > 0) and r.buyout or nil
      local bid = r.curBid or 0
      if detailPerItem then
        local c = (r.count and r.count > 0) and r.count or 1
        if bo then bo = bo / c end
        bid = bid / c
      end
      return bo, bid
    end
    table.sort(out, function(a, b)
      local abo, abid = rankPrice(a)
      local bbo, bbid = rankPrice(b)
      if (abo ~= nil) ~= (bbo ~= nil) then return abo ~= nil end
      if abo and bbo and abo ~= bbo then return abo < bbo end
      if not abo and abid ~= bbid then return abid < bbid end
      return a.index < b.index
    end)
    return out
  end

  -- Seller cell. A grouped row keeps `owner` only while every member shares it (see the grouping
  -- above), so fall back to its `owners` list: still one distinct name after de-duping (a seller
  -- posting six identical stacks is the common case) shows that name, genuinely mixed shows
  -- "Multiple", and all-unknown shows nothing -- owner comes back nil on this client until the
  -- server fills it in, and "?" on a whole page of fresh listings reads like an error.
  local function sellerText(d)
    if d.owner and d.owner ~= "" then return d.owner end
    local owners = d.owners
    if owners then
      local seen, count, last = {}, 0, nil
      for i = 1, #owners do
        local s = owners[i]
        if s and s ~= "" and not seen[s] then
          seen[s] = true
          count = count + 1
          last = s
        end
      end
      if count == 1 then return last end
      if count > 1 then return "Multiple" end
    end
    return ""
  end

  refreshDetailRows = function()
    detailRowsData = readDetailPage()
    local drawCount = #detailRowsData
    local visibleRows = detailVisibleRows()
    if FauxScrollFrame_Update then
      FauxScrollFrame_Update(detailScroll, drawCount, visibleRows, DETAIL_ROW_H + 1)
    end
    syncAlwaysShowFauxBar(detailScroll, drawCount, visibleRows)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(detailScroll)) or 0

    if drawCount > 0 then
      detailEmpty:Hide()
    else
      detailEmpty:Show()
      detailEmpty:SetText("No listings.")
    end
    -- Total AUCTIONS, not visible rows -- condensing collapses identical listings into one row,
    -- but this readout should keep meaning "how many listings exist".
    local totalAuctions = 0
    for i = 1, drawCount do
      totalAuctions = totalAuctions + (detailRowsData[i].num or 1)
    end
    detailCount:SetText(tostring(totalAuctions))

    -- Selection survives a refresh only if the same row identity is still present -- matched by
    -- `key`, which for a grouped row is its (stack size, buyout, bid) identity rather than any one
    -- auction index, so buying one stack out of "6 stacks of 20" keeps the shrunk group selected
    -- for the next buy. When the identity is gone entirely (last one bought), drop the selection
    -- instead of leaving the footer buttons pointed at a listing that no longer exists.
    if detailSelected then
      local stillThere = nil
      for i = 1, #detailRowsData do
        if detailRowsData[i].key == detailSelected.key then
          stillThere = detailRowsData[i]
          break
        end
      end
      detailSelected = stillThere
    end

    for i = 1, visibleRows do
      local row = ensureDetailRow(i)
      local data = detailRowsData[i + offset]
      if data then
        row._data = data
        -- Per Item = buyout / stack size, ceil'd so a fractional copper never understates the
        -- cost. Display-only; the popup/purchase path uses the listing's real totals.
        local per = (data.count and data.count > 0) and data.count or 1
        row.Each:SetText(moneyText(math.ceil((data.buyout or 0) / per)))
        row.Buyout:SetText(moneyText(data.buyout or 0))
        row.Bid:SetText(moneyText(data.curBid or 0))
        local lvText, lr, lg, lb = levelText(data.level)
        row.Level:SetText(lvText)
        row.Level:SetTextColor(lr, lg, lb)
        if (data.num or 1) > 1 then
          row.Qty:SetText(string.format("%d stacks of %d", data.num, data.count or 1))
        else
          row.Qty:SetText(tostring(data.count or 1))
        end
        row.Seller:SetText(sellerText(data))
        row.Time:SetText(data.timeText or "")
        if row.Sel then row.Sel:SetShown(data == detailSelected) end
        row:Show()
      else
        row._data = nil
        if row.Sel then row.Sel:Hide() end
        row:Hide()
      end
    end
    -- Hide any previously-built rows beyond the current viewport (only relevant if the panel's
    -- effective height ever shrinks between refreshes; harmless no-op otherwise).
    for i = visibleRows + 1, #detailRowWidgets do
      local row = detailRowWidgets[i]
      row._data = nil
      if row.Sel then row.Sel:Hide() end
      row:Hide()
    end
    updateDetailActions()

    -- detailVisibleRows() reads detailScroll:GetHeight(), but the very first refresh after
    -- openItemDetail's detail:Show() can land before this branch of the anchor chain has settled
    -- (same class of stale-zero-size read BuildCustom's own first sync() guards against below) --
    -- that undercounts the viewport, makes FauxScrollFrame_Update think there's more to scroll than
    -- there really is, and leaves the scrollbar/arrows stuck showing even though every row fits.
    -- One deferred re-run per item-open with a settled layout self-corrects it. Flag is set BEFORE
    -- scheduling (not inside the callback) so the callback's own call to refreshDetailRows sees it
    -- already true and doesn't reschedule itself forever; openItemDetail resets it per new item.
    if not detailAutoResyncDone and C_Timer and C_Timer.After then
      detailAutoResyncDone = true
      C_Timer.After(0, function()
        if activeQuery == "itembuy" then
          pcall(refreshDetailRows)
        end
      end)
    end
  end

  detailScroll:SetScript("OnVerticalScroll", function(self, offset)
    if FauxScrollFrame_OnVerticalScroll then
      FauxScrollFrame_OnVerticalScroll(self, offset, DETAIL_ROW_H + 1, refreshDetailRows)
    end
  end)

  detailBuyoutBtn:SetScript("OnClick", function()
    local r = detailSelected
    if not (r and r.buyout and r.buyout > 0) then return end
    StaticPopup_Show("NE_AH_BROWSE_BUYOUT", moneyText(r.buyout), nil, { index = r.index, price = r.buyout })
  end)
  detailBidBtn:SetScript("OnClick", function()
    local r = detailSelected
    if not (r and r.nextBid and r.nextBid > 0) then return end
    StaticPopup_Show("NE_AH_BROWSE_BID", moneyText(r.nextBid), nil, { index = r.index, price = r.nextBid })
  end)

  detailBack:SetScript("OnClick", function()
    activeQuery = "browse"
    detail:Hide()
    setBrowseResultsShown(true)
  end)
  detailRefresh:SetScript("OnClick", function()
    if detail.CurrentItem and openItemDetail then openItemDetail(detail.CurrentItem) end
  end)

  openItemDetail = function(data)
    if not data or not data.name then return end
    detail.CurrentItem = data
    -- Drilling in takes the shared "list" slot away from the browse scan. Retire the scan properly
    -- instead of letting collectScanPage bail on activeQuery and strand it armed (issue #31).
    cancelScan()
    activeQuery = "itembuy"
    detailSelected = nil
    detailRowsData = {}
    detailAutoResyncDone = false

    detailIcon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    detailName:SetText(data.name)
    if data.quality and data.quality > 1 and GetItemQualityColor then
      local r, g, b = GetItemQualityColor(data.quality)
      detailName:SetTextColor(r, g, b)
      detailRing:SetVertexColor(r, g, b)
      detailRing:Show()
    else
      detailName:SetTextColor(1, 1, 1)
      detailRing:Hide()
    end
    detailCount:SetText("")
    detailEmpty:SetText("Searching...")
    detailEmpty:Show()
    updateDetailActions()
    setBrowseResultsShown(false)
    detail:Show()

    if not (CanSendAuctionQuery and CanSendAuctionQuery("list")) then
      detailEmpty:SetText("Auction query is throttled. Try again in a moment.")
      return
    end
    -- Re-query scoped to this exact item name. THIS server's QueryAuctionItems signature (per its
    -- own bundled APIDocumentation) has no dedicated exact-match flag the way some other clients'
    -- do -- passing the full item name as the search text returns just this item barring rare
    -- substring collisions (e.g. "Belt" would also match "Belt of Deep Shadow").
    -- ISSUE #31 ("the list of sellers does not appear, even if that item is available"): the
    -- rarity slot was hardcoded to 0, which is an EXACT match on Poor quality, not "any" -- so this
    -- drill-down only ever returned listings for grey items and the seller list came back empty for
    -- everything else. ANY_QUALITY (-1) disables the filter. Note this must stay unfiltered even
    -- though we know the item's quality: filtering by it would be redundant, and data.quality can be
    -- nil when the item isn't in the local cache yet.
    AH.ClaimListQuery("itembuy")
    local ok, err = pcall(QueryAuctionItems, data.name, 0, 0, 0, 0, 0, 0, false, ANY_QUALITY, false)
    if not ok and NE.Log then
      NE.Log("AH", "ItemBuy QueryAuctionItems error: " .. tostring(err))
    end
  end

  local categories = CreateFrame("Frame", nil, pane)
  categories:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -73)
  -- Height 437, not 438 -- anchored from the TOP (fixed height, unlike every other panel here which
  -- anchors its BOTTOM at pane+27), so a hardcoded 438 landed its bottom 1px below the shared
  -- pane+27 divider line the results/detail lists and the Auctions tab's panels all sit on.
  categories:SetSize(168, 437)
  pane.Categories = categories

  local catBg = categories:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(catBg, "auctionhouse-background-categories", false)
  end
  catBg:SetPoint("TOPLEFT", categories, "TOPLEFT", 3, -3)
  catBg:SetSize(138, 433)

  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, categories, 0, 0, 0, 0)
  end

  local ok, catList = pcall(buildCategoryList, categories)
  if ok then
    pane.CategoryList = catList
  else
    pane.CategoryList = nil
  end

  -- Shift-clicking a bag item fills this search box (issue #17). On a stock client,
  -- ChatEdit_InsertLink routes an item shift-click (no chat box open) into the legacy Browse tab's
  -- BrowseName edit box -- but that whole frame is permanently alpha-cloaked here (Window.lua's
  -- suppressLegacyAuctionFrame), so the name landed in an invisible box and the visible search bar
  -- stayed empty. Post-hook the same entry point: when no chat edit box took the link and this
  -- pane is the one on screen, mirror the item's name into our search box and run the search
  -- immediately (Auctionator-style; one shift-click = results on screen). hooksecurefunc (not a
  -- replacement) so the stock routing, other addons' hooks, and taint behavior are all untouched.
  if not AH._browseChatLinkHooked and type(hooksecurefunc) == "function" then
    AH._browseChatLinkHooked = true
    hooksecurefunc("ChatEdit_InsertLink", function(text)
      if type(text) ~= "string" or not string.find(text, "item:", 1, true) then return end
      -- Shift-clicking a row INSIDE this window is a request to link that item in chat, not to
      -- search for it -- AH.HandleItemClick (Window.lua) raises this flag around its own
      -- ChatEdit_InsertLink call so a chat box that isn't open can't turn the click into a search
      -- that discards the results being looked at. Bag/chat shift-clicks still search as before.
      if AH._suppressLinkSearch then return end
      -- A shown chat edit box already consumed the link; 3.3.5a uses the single global
      -- ChatFrameEditBox, but check the retail-style active-window API too in case this client
      -- backports it.
      if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
      if ChatFrameEditBox and ChatFrameEditBox.IsShown and ChatFrameEditBox:IsShown() then return end
      if not (pane:IsShown() and AH.frame and AH.frame:IsShown()) then return end
      local name = GetItemInfo and GetItemInfo(text)
      if not name or name == "" then
        -- Item not in the local cache yet: fall back to the display name inside the link itself.
        name = string.match(text, "%[(.-)%]")
      end
      if not name or name == "" then return end
      searchBox:SetText(name)
      searchBox:ClearFocus()
      -- Name search only: drop any category selection, or a herb shift-clicked while "Weapons"
      -- was highlighted would query Weapons-only and come back empty. The filter popup's level/
      -- rarity/usable settings are left alone -- they're deliberate, visible-on-reopen choices.
      if pane.CategoryList and pane.CategoryList.ClearSelection then
        pane.CategoryList:ClearSelection()
      end
      runSearch()
    end)
  end

  return pane
end
