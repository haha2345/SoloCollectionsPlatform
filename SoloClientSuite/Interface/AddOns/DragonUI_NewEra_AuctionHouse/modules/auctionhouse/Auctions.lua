-- DragonUI_NewEra/modules/auctionhouse/Auctions.lua
-- Auctions tab visual shell: Auctions/Bids sub-tabs (themed as the same "pill" tab-plate the Sell
-- pane's "Create Auction" label uses -- see buildPillTab below), a summary panel grouping your
-- listings by item (retail's per-item summary; Era's owner/bidder API has no server-side
-- equivalent, so it's grouped client-side), and the owner/bidder listing with a Cancel Auction
-- button.
--
-- Legacy API: GetNumAuctionItems("owner"/"bidder"), GetAuctionItemInfo(list,i),
-- GetAuctionItemTimeLeft(list,i), CanCancelAuction(i), CancelAuction(i);
-- events AUCTION_OWNED_LIST_UPDATE, AUCTION_BIDDER_LIST_UPDATE.

local NE = DragonUI_NewEra
if not NE then return end

NE.ah = NE.ah or {}
local AH = NE.ah

-- Keep alwaysShow custom Faux bars visually in sync with real overflow state.
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

  if not canScroll then
    local sliderName = scroll.GetName and scroll:GetName()
    local slider = (sliderName and _G[sliderName .. "ScrollBar"]) or scroll.ScrollBar or scroll.scrollBar
    if slider then
      if slider.SetMinMaxValues then slider:SetMinMaxValues(0, 0) end
      if slider.SetValue then slider:SetValue(0) end
    end
  end
end

local function moneyText(copper)
  if not copper or copper <= 0 then return "-" end
  if GetCoinTextureString then
    return GetCoinTextureString(copper)
  end
  return tostring(copper)
end

-- Prefer the SHORT list-column strings ("Short"/"Medium"/"Long"/"Very Long") over the verbose
-- "_DETAIL" globals ("Greater than 12 hours") -- the DETAIL variants are meant for tooltips and
-- are too wide for this column, wrapping onto a second line that bled into the Buyout column.
local function timeLeftText(code)
  if code == 1 then return AUCTION_TIME_LEFT1 or "Short" end
  if code == 2 then return AUCTION_TIME_LEFT2 or "Medium" end
  if code == 3 then return AUCTION_TIME_LEFT3 or "Long" end
  if code == 4 then return AUCTION_TIME_LEFT4 or "Very Long" end
  return "-"
end

function AH.BuildAuctionsPane(parent)
  local pane = CreateFrame("Frame", "NE_AuctionHouseAuctionsPane", parent)
  pane:SetAllPoints(parent)

  ----------------------------------------------------------------------
  -- Sub-tabs (Auctions / Bids): themed as the SAME "pill" tab-plate the Sell pane's "Create
  -- Auction" label uses (auctionhouse-selltab-left/middle/right), straddling the panel's top
  -- edge, instead of the classic CharacterFrameTabButtonTemplate reskin used by earlier rounds --
  -- that template's MakeTopTab flip + PanelTemplates_SetTab not honoring the reskin were a
  -- repeated source of bugs (upside-down art, both tabs reading "active" at once). This reuses
  -- proven, already-working art from Sell.lua instead. That atlas only has ONE visual state (no
  -- separate "active" pieces the way the classic tab template does), so selection is conveyed by
  -- dimming the inactive pill (alpha + grey text) rather than swapping art.
  ----------------------------------------------------------------------
  local PILL_H = 23
  local SUBTABS = {
    { id = 1, text = AUCTION_HOUSE_AUCTIONS_SUB_TAB or AUCTIONS or "Auctions" },
    { id = 2, text = AUCTION_HOUSE_BIDS_SUB_TAB or BIDS or "Bids" },
  }

  -- Explicit SetWidth/SetHeight on btn FIRST, then anchor the art pieces off btn's own corners --
  -- NOT the other way around (anchoring btn's own rect off its children's positions would be a
  -- circular reference: btn's rect has to be fully resolved before any anchor point on it, TOP/
  -- BOTTOM/LEFT/RIGHT/CENTER, can be used as a reference by something else).
  local function buildPillTab(text)
    local btn = CreateFrame("Button", nil, pane)
    btn:SetHeight(PILL_H)
    btn:EnableMouse(true)
    btn:SetFrameLevel((pane:GetFrameLevel() or 0) + 20)   -- draws above the panels' nineslice borders

    local tabText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tabText:SetText(text)
    -- 9 (left cap) + 12+textWidth+12 (middle, padded like Sell's plate) + 9 (right cap).
    btn:SetWidth((tabText:GetStringWidth() or 40) + 42)

    local tabL = btn:CreateTexture(nil, "ARTWORK")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(tabL, "auctionhouse-selltab-left", true) end
    tabL:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    tabL:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)

    local tabR = btn:CreateTexture(nil, "ARTWORK")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(tabR, "auctionhouse-selltab-right", true) end
    tabR:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    tabR:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)

    local tabM = btn:CreateTexture(nil, "ARTWORK")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(tabM, "auctionhouse-selltab-middle", false) end
    tabM:SetPoint("TOPLEFT", tabL, "TOPRIGHT", 0, 0)
    tabM:SetPoint("BOTTOMRIGHT", tabR, "BOTTOMLEFT", 0, 0)

    tabText:ClearAllPoints()
    tabText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.Text = tabText
    return btn
  end

  local subButtons = {}
  do
    local prev
    for i = 1, #SUBTABS do
      local d = SUBTABS[i]
      local btn = buildPillTab(d.text)
      btn:SetID(d.id)
      if prev then
        btn:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 6, 0)
      else
        -- x=80 matches the horizontal start every earlier tab attempt used here (proven clear of
        -- the window's portrait). y=-81 = the panels' own -78 top offset (below) minus a further
        -- 3px, so the pill's bottom edge overlaps 3px DOWN into the panel's top border -- same
        -- straddle convention Sell.lua's "Create Auction" plate uses against its own form.
        btn:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", 80, -81)
      end
      subButtons[d.id] = btn
      prev = btn
    end
  end

  -- Selection: dim the inactive pill (there's only one art style, no separate "active" atlas).
  local function setTabArt(id, selected)
    local btn = subButtons[id]
    if not btn then return end
    btn:SetAlpha(selected and 1 or 0.55)
    if btn.Text and btn.Text.SetTextColor then
      if selected then btn.Text:SetTextColor(1, 0.82, 0) else btn.Text:SetTextColor(0.6, 0.6, 0.6) end
    end
  end

  ----------------------------------------------------------------------
  -- Panels. TOP is a FIXED offset (-78) below the pane's own top -- clears the portrait/title band
  -- and stays constant regardless of which sub-tab is selected (the pill tabs above don't resize
  -- on selection, unlike the old classic-tab attempt, so there's no jump to guard against either
  -- way, but a fixed offset is still simplest). BOTTOM is +27 from the pane's bottom -- the SAME 27
  -- Browse.lua's own results/detail panels use against this same window (Window.lua's
  -- buildMoneyFrame inset also tops out at 27), so the footer row (Cancel button) lines up with
  -- the money frame across the window's width.
  ----------------------------------------------------------------------
  local left = CreateFrame("Frame", nil, pane)
  left:SetWidth(168)
  left:SetPoint("TOP", pane, "TOP", 0, -78)
  left:SetPoint("LEFT", pane, "LEFT", 4, 0)
  left:SetPoint("BOTTOM", pane, "BOTTOM", 0, 27)
  pane.Left = left

  -- Stretched to fill "left" (matches every other panel's background in this window -- rightBg
  -- right below does the same) instead of a fixed 138x433 SetSize, which left a ~27px raw gap on
  -- the right where the panel's own chrome showed through and rows/highlights ran past the art.
  local leftBg = left:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(leftBg, "auctionhouse-background-summarylist", false)
  end
  leftBg:SetPoint("TOPLEFT", left, "TOPLEFT", 3, -3)
  leftBg:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -3, 3)
  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, left, 0, 0, 0, 0)
  end

  -- TOPLEFT touches "left" directly (0 gap) -- matching Browse.lua's own categories/results split
  -- (categories 168 wide at pane x=4, results at pane x=172: zero gap between them). The two
  -- panels' own inset borders butting together is what reads as "the divider"; an explicit gap
  -- here just left a bare strip of raw chrome between them instead.
  local right = CreateFrame("Frame", nil, pane)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -5, 27)
  pane.Right = right

  local rightBg = right:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(rightBg, "auctionhouse-background-index", false)
  end
  rightBg:SetPoint("TOPLEFT", right, "TOPLEFT", 3, -22)
  rightBg:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -22, 0)
  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, right, 0, -19, -22, 0)
  end

  local selectedSub = 1
  local selectedOwnerIndex = nil
  local rowsData = {}
  local summaryEntries = { { all = true } }
  local selectedSummaryIndex = 1
  local cancelBtn
  local requestActiveList
  local refreshResults
  local refreshSummaryRows

  local function activeListType()
    if selectedSub == 1 then return "owner" end
    return "bidder"
  end

  local function updateCancelState()
    if selectedSub ~= 1 or not selectedOwnerIndex then
      cancelBtn:Disable()
      return
    end
    if type(CanCancelAuction) == "function" then
      if CanCancelAuction(selectedOwnerIndex) then
        cancelBtn:Enable()
      else
        cancelBtn:Disable()
      end
    else
      cancelBtn:Enable()
    end
  end

  local function captureRows()
    if type(GetAuctionItemInfo) ~= "function" then
      rowsData = {}
      return rowsData
    end

    local kind = activeListType()
    local batchCount = 0
    if type(GetNumAuctionItems) == "function" then
      local n = GetNumAuctionItems(kind)
      batchCount = (type(n) == "number") and n or 0
    end

    local out = {}
    for i = 1, batchCount do
      -- Field order per THIS server's own bundled APIDocumentation addon (13 return values, no
      -- "levelColumnName" slot the generic retail/Wowpedia signature has) -- texture is position
      -- 2, buyoutPrice is position 9 and bidAmount is position 10 on THIS client, not 10/11.
      local ok, name, texture, _, _, _, _, _, _, buyoutPrice, bidAmount = pcall(GetAuctionItemInfo, kind, i)
      if not ok then
        break
      end
      if not name then
        break
      end
      local tl = type(GetAuctionItemTimeLeft) == "function" and GetAuctionItemTimeLeft(kind, i) or nil
      out[#out + 1] = {
        index = i,
        name = name,
        texture = texture,
        bidAmount = bidAmount,
        buyoutPrice = buyoutPrice,
        timeLeft = tl,
      }
    end
    rowsData = out
    return out
  end

  -- "All Auctions"/"All Bids" + one row per distinct item name, in first-seen order (retail
  -- groups by item type server-side; Era's flat owner/bidder list has no such grouping, so this
  -- is built client-side from whatever captureRows just read).
  local function buildSummaryEntries()
    local entries = { { all = true } }
    local seen = {}
    for i = 1, #rowsData do
      local r = rowsData[i]
      if not seen[r.name] then
        seen[r.name] = true
        entries[#entries + 1] = { name = r.name, texture = r.texture }
      end
    end
    return entries
  end

  -- rowsData filtered down to the selected summary entry (or everything, for "All").
  local function filteredRows()
    local sel = summaryEntries[selectedSummaryIndex]
    if not sel or sel.all then return rowsData end
    local out = {}
    for i = 1, #rowsData do
      if rowsData[i].name == sel.name then out[#out + 1] = rowsData[i] end
    end
    return out
  end

  local function refreshActiveList()
    captureRows()
    summaryEntries = buildSummaryEntries()
    if selectedSummaryIndex > #summaryEntries then selectedSummaryIndex = 1 end
    if refreshSummaryRows then refreshSummaryRows() end
    if refreshResults then refreshResults() end
    updateCancelState()
  end

  local function setSub(id)
    selectedSub = id
    selectedOwnerIndex = nil
    selectedSummaryIndex = 1
    for i = 1, #SUBTABS do
      setTabArt(SUBTABS[i].id, SUBTABS[i].id == id)
    end
    if pane.EmptyText then
      pane.EmptyText:SetText((id == 1) and "You have no auctions." or "You have no bids.")
    end
    if cancelBtn then cancelBtn:SetShown(id == 1) end
    requestActiveList()
    refreshActiveList()
  end

  for id, btn in pairs(subButtons) do
    btn:SetScript("OnClick", function(self) setSub(self:GetID()) end)
  end

  requestActiveList = function()
    if selectedSub == 1 then
      if type(GetOwnerAuctionItems) == "function" then
        pcall(GetOwnerAuctionItems, 0)
      end
    else
      if type(GetBidderAuctionItems) == "function" then
        pcall(GetBidderAuctionItems, 0)
      end
    end
  end

  ----------------------------------------------------------------------
  -- Summary panel: "All Auctions"/"All Bids" + one row per distinct item, scrollable. Selecting
  -- a row filters the right list down to that item's individual auctions.
  ----------------------------------------------------------------------
  local SUM_ROW_H = 21
  local SUM_VISIBLE_ROWS = 20
  local summaryRows = {}
  local summaryScroll = CreateFrame("ScrollFrame", pane:GetName() .. "SummaryScroll", left, "FauxScrollFrameTemplate")
  summaryScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 3, -3)
  summaryScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -20, 3)

  if NE.scrollbar and NE.scrollbar.BuildCustom then
    -- arrows = true: the reference's Auctions-tab scrollbar (both its summary list and its
    -- results list) shows up/down arrow buttons, unlike the plain Buy-tab bar.
    -- x = -4 (not the usual -8): `right` sits flush against `left`'s edge (0 gap, no divider
    -- padding between the panels), so the arrow buttons -- 17px wide, centered on an 8px track --
    -- overhang the track by 4.5px each side and were poking past `left`'s edge into the seam at
    -- the standard -8 inset. -4 pulls the whole bar+arrows left so they clear it.
    local ok, bar = pcall(NE.scrollbar.BuildCustom, summaryScroll, { x = -4, alwaysShow = true, arrows = true })
    if ok and bar then
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((left:GetFrameLevel() or 1) + 10)
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  local function ensureSummaryRow(i)
    local row = summaryRows[i]
    if row then return row end

    row = CreateFrame("Button", nil, left)
    row:SetFrameStrata("DIALOG")
    row:SetFrameLevel((left:GetFrameLevel() or 1) + 8)
    row:SetHeight(SUM_ROW_H)
    if i == 1 then
      row:SetPoint("TOPLEFT", left, "TOPLEFT", 3, -3)
      row:SetPoint("TOPRIGHT", left, "TOPRIGHT", -20, -3)
    else
      row:SetPoint("TOPLEFT", summaryRows[i - 1], "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", summaryRows[i - 1], "BOTTOMRIGHT", 0, 0)
    end

    row.Sel = row:CreateTexture(nil, "BACKGROUND")
    if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(row.Sel, "auctionhouse-ui-row-select", false)) then
      row.Sel:SetTexture("Interface\\Buttons\\WHITE8X8")
      row.Sel:SetVertexColor(1, 0.82, 0, 0.18)
    end
    row.Sel:SetAllPoints(row)
    row.Sel:Hide()

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = row:GetHighlightTexture()
    if hl then
      hl:SetVertexColor(1, 0.82, 0, 0.10)
      hl:SetBlendMode("ADD")
    end

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(14, 14)
    row.Icon:SetPoint("LEFT", row, "LEFT", 4, 0)

    row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.Text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
      if not self._index then return end
      selectedSummaryIndex = self._index
      selectedOwnerIndex = nil
      if refreshSummaryRows then refreshSummaryRows() end
      if refreshResults then refreshResults() end
      updateCancelState()
    end)

    summaryRows[i] = row
    return row
  end

  refreshSummaryRows = function()
    local total = #summaryEntries
    if FauxScrollFrame_Update then FauxScrollFrame_Update(summaryScroll, total, SUM_VISIBLE_ROWS, SUM_ROW_H) end
    syncAlwaysShowFauxBar(summaryScroll, total, SUM_VISIBLE_ROWS)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(summaryScroll)) or 0

    for i = 1, SUM_VISIBLE_ROWS do
      local row = ensureSummaryRow(i)
      local e = summaryEntries[i + offset]
      if e then
        row._index = i + offset
        if e.all then
          row.Icon:Hide()
          row.Text:ClearAllPoints()
          row.Text:SetPoint("LEFT", row, "LEFT", 6, 0)
          row.Text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
          row.Text:SetText((selectedSub == 1) and (AUCTION_HOUSE_ALL_AUCTIONS or "All Auctions")
                                                or (AUCTION_HOUSE_ALL_BIDS or "All Bids"))
        else
          row.Icon:Show()
          row.Icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
          row.Text:ClearAllPoints()
          row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
          row.Text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
          row.Text:SetText(e.name or "-")
        end
        row.Sel:SetShown(row._index == selectedSummaryIndex)
        row:Show()
      else
        row._index = nil
        row:Hide()
      end
    end
  end

  summaryScroll:SetScript("OnVerticalScroll", function(self, offset)
    if FauxScrollFrame_OnVerticalScroll then
      FauxScrollFrame_OnVerticalScroll(self, offset, SUM_ROW_H, refreshSummaryRows)
    else
      refreshSummaryRows()
    end
  end)

  ----------------------------------------------------------------------
  -- Right list: column headers + faux-scroll rows.
  ----------------------------------------------------------------------
  local h1 = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h1:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -8)
  h1:SetText(NAME or "Name")

  local h2 = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h2:SetPoint("TOPLEFT", right, "TOPLEFT", 238, -8)
  h2:SetText(AUCTION_HOUSE_HEADER_CURRENT_BID or "Current Bid")

  local h3 = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h3:SetPoint("TOPLEFT", right, "TOPLEFT", 340, -8)
  h3:SetText(AUCTION_BUYOUT_PRICE or BUYOUT or "Buyout")

  -- Right-anchored + right-justified from the SAME frame ("right") and the SAME -30 (scrollbar
  -- gutter) / -8 (row inset) offsets row.Time itself resolves to below -- guarantees this header
  -- lines up with the actual data column instead of drifting from an unrelated absolute x. Widened
  -- to 115 (was 88) so "Very Long" / "Greater than..." style strings fit on one line.
  local h4 = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h4:SetPoint("TOPRIGHT", right, "TOPRIGHT", -38, -8)
  h4:SetWidth(115)
  h4:SetJustifyH("RIGHT")
  h4:SetText(TIME_LEFT or "Time Left")

  local empty = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("CENTER", right, "CENTER", 0, 44)
  empty:SetText("You have no auctions.")
  empty:SetTextColor(1, 0.82, 0)
  pane.EmptyText = empty

  local ROW_H = 20
  local VISIBLE_ROWS = 17
  local rows = {}
  local scroll = CreateFrame("ScrollFrame", pane:GetName() .. "ResultsScroll", right, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -24)
  scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -26, 28)

  if NE.scrollbar and NE.scrollbar.BuildCustom then
    local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, { x = -8, alwaysShow = true, arrows = true })
    if ok and bar then
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((right:GetFrameLevel() or 1) + 10)
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
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

  local function ensureRow(i)
    local row = rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, right)
    row:SetFrameStrata("DIALOG")
    row:SetFrameLevel((right:GetFrameLevel() or 1) + 8)
    row:SetHeight(ROW_H)
    if i == 1 then
      row:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -24)
      row:SetPoint("TOPRIGHT", right, "TOPRIGHT", -30, -24)
    else
      row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -1)
      row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, -1)
    end

    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.Bg:SetAllPoints(row)
    row.Bg:SetVertexColor(0.07, 0.07, 0.08, (i % 2 == 0) and 0.30 or 0.20)

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = row:GetHighlightTexture()
    if hl then
      hl:SetVertexColor(1, 0.82, 0, 0.12)
      hl:SetBlendMode("ADD")
    end

    row.Select = row:CreateTexture(nil, "ARTWORK")
    row.Select:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.Select:SetAllPoints(row)
    row.Select:SetVertexColor(1.0, 0.82, 0.0, 0.16)
    row.Select:Hide()

    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.Name:SetPoint("RIGHT", row, "LEFT", 220, 0)
    row.Name:SetJustifyH("LEFT")

    row.Bid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Bid:SetPoint("LEFT", row, "LEFT", 232, 0)
    row.Bid:SetWidth(90)
    row.Bid:SetJustifyH("LEFT")

    row.Buyout = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Buyout:SetPoint("LEFT", row, "LEFT", 334, 0)
    row.Buyout:SetWidth(90)
    row.Buyout:SetJustifyH("LEFT")

    row.Time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Time:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.Time:SetWidth(115)
    row.Time:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(self)
      -- SHIFT links the item in chat, CTRL dresses it up; otherwise select the row.
      if self._index then
        local link = GetAuctionItemLink and GetAuctionItemLink(activeListType(), self._index)
        if link and AH.HandleItemClick(link) then return end
      end
      if selectedSub ~= 1 then return end
      selectedOwnerIndex = self._index
      refreshResults()
      updateCancelState()
    end)

    rows[i] = row
    return row
  end

  refreshResults = function()
    local list = filteredRows()
    local total = #list
    fsUpdate(scroll, total, VISIBLE_ROWS, ROW_H + 1)
    syncAlwaysShowFauxBar(scroll, total, VISIBLE_ROWS)
    local offset = fsGetOffset(scroll)
    local maxOffset = total - VISIBLE_ROWS
    if maxOffset < 0 then maxOffset = 0 end
    if offset > maxOffset then offset = maxOffset end

    if total > 0 then
      empty:Hide()
    else
      empty:Show()
    end

    for i = 1, VISIBLE_ROWS do
      local row = ensureRow(i)
      local data = list[i + offset]
      if data then
        row._index = data.index
        row.Name:SetText(data.name or "-")
        row.Bid:SetText(moneyText(data.bidAmount))
        row.Buyout:SetText(moneyText(data.buyoutPrice))
        row.Time:SetText(timeLeftText(data.timeLeft))
        if selectedSub == 1 and selectedOwnerIndex == data.index then
          row.Select:Show()
        else
          row.Select:Hide()
        end
        row:Show()
      else
        row._index = nil
        row:Hide()
      end
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

  -- Footer row: sits in the SAME 27px band "right"/"left" stop short of (not a further offset
  -- below it -- that doubled the reserved space and crammed the button down against the window's
  -- very bottom edge). y=3..27 mirrors Window.lua's own money frame inset (also 3..27), so the
  -- button's vertical center lines up with the money display across the window.
  -- x=-27 lines the button's RIGHT edge up with the inset frame's own right edge: "right" stops
  -- 5px short of pane's right edge (matching the Sell tab's panel), and its visible inset
  -- (rightBg/AttachInset) sits a further 22px in from THAT (see rightBg/AttachInset below) --
  -- 5+22 = 27.
  cancelBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  cancelBtn:SetSize(150, 24)
  cancelBtn:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -27, 3)
  cancelBtn:SetText(AUCTION_HOUSE_CANCEL_AUCTION_BUTTON or CANCEL_AUCTION or "Cancel Auction")
  cancelBtn:Disable()
  cancelBtn:SetScript("OnClick", function()
    if selectedSub ~= 1 or not selectedOwnerIndex then return end
    if type(CancelAuction) == "function" then
      pcall(CancelAuction, selectedOwnerIndex)
    end
  end)

  local watcher = CreateFrame("Frame", nil, pane)
  watcher:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
  watcher:RegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
  watcher:RegisterEvent("AUCTION_HOUSE_SHOW")
  watcher:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
      requestActiveList()
    end
    if not pane:IsShown() then return end
    if event == "AUCTION_OWNED_LIST_UPDATE" and selectedSub ~= 1 then return end
    if event == "AUCTION_BIDDER_LIST_UPDATE" and selectedSub ~= 2 then return end
    refreshActiveList()
  end)

  setSub(selectedSub)
  requestActiveList()
  refreshActiveList()

  pane:HookScript("OnShow", function()
    requestActiveList()
    refreshActiveList()
  end)

  return pane
end
