-- DragonUI_NewEra/modules/auctionhouse/Sell.lua
-- Sell tab: drag an item into the slot, set quantity/price/duration, see the item's current
-- market listings on the right, and post the auction. Legacy 3.3.5a API (verified against this
-- server's own bundled APIDocumentation + Auctionator, same pattern Browse.lua/Auctions.lua use):
--   ClickAuctionSellItemButton()                          -- cursor item -> sell slot
--   GetAuctionSellItemInfo() -> name, texture, count, quality, canUse, price   (6 values)
--   GetAuctionDeposit(duration, minBid, buyoutPrice, stackSize, numStacks)     -- deposit cost
--   PostAuction(minBid, buyoutPrice, duration, stackSize, numStacks)           -- create the auction
--   QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page,
--                      isUsable, quality, getAll)                             -- market search
--                      `quality` is an EXACT match, not a minimum; -1 = any rarity (0 = Poor).
--   GetAuctionItemInfo("list", i) -> name,tex,count,quality,canUse,level,minBid,minIncrement,
--                      buyoutPrice,bidAmount,highBidder,owner,saleStatus      (13 values)
--   Events: NEW_AUCTION_UPDATE (sell slot changed), AUCTION_ITEM_LIST_UPDATE (list query done).
--
-- Layout mirrors the reference NewEra Sell.lua (ReferenceAddons/NewEra/AuctionHouse/Sell.lua):
-- Create-Auction tab plate, itemheaderframe item display, aligned label rows with the modern
-- auctionhouse-ui-inputfield input skin, money input with in-field coin icons, coin-icon
-- Deposit/Total readouts, and a sortable market list with a Refresh control. Widgets are
-- hand-built on 3.3.5a primitives -- the retail templates the reference leaned on
-- (InputBoxScriptTemplate, WowStyle1DropdownTemplate, MoneyDisplayFrameTemplate) don't exist here.

local NE = DragonUI_NewEra
if not NE then return end

NE.ah = NE.ah or {}
local AH = NE.ah

local DURATIONS = {
  { code = 1, label = AUCTION_DURATION_ONE   or "12 Hours" },
  { code = 2, label = AUCTION_DURATION_TWO   or "24 Hours" },
  { code = 3, label = AUCTION_DURATION_THREE or "48 Hours" },
}

-- Deposit lookup: this server's real signature takes (duration, minBid, buyoutPrice, stackSize,
-- numStacks); fall back to the older 1-arg form (duration only) if that call shape errors.
local function computeDeposit(durationCode, minBid, buyoutPrice, stack, numStacks)
  if not GetAuctionDeposit then return 0 end
  local ok, d = pcall(GetAuctionDeposit, durationCode, minBid, buyoutPrice, stack, numStacks)
  if ok and type(d) == "number" then return d end
  ok, d = pcall(GetAuctionDeposit, durationCode)
  if ok and type(d) == "number" then return d end
  return 0
end

----------------------------------------------------------------------
-- Hand-built modern widgets (shared makeInput/makeMoneyInput shapes
-- from the reference, on 3.3.5a primitives).
----------------------------------------------------------------------
-- auctionhouse-ui-inputfield is a 2x asset: caps 16x66, middle 356x66. Display at INPUT_H and
-- keep the cap aspect (16:66) so the rounded ends aren't distorted.
local INPUT_H = 33
local CAP_W = math.max(6, math.floor(16 * (INPUT_H / 66) + 0.5))

-- opts.justify ("RIGHT") + opts.rightInset reserve room inside the box for a trailing coin icon.
local function makeInput(parent, w, opts)
  opts = opts or {}
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetSize(w, INPUT_H)
  eb:SetAutoFocus(false)
  eb:SetFontObject(opts.font or _G.ChatFontNormal or _G.GameFontHighlight)
  eb:SetTextInsets(CAP_W + 3, (opts.rightInset or CAP_W) + 3, 0, 0)
  if opts.justify and eb.SetJustifyH then eb:SetJustifyH(opts.justify) end
  eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  if NE.tex and NE.tex.SetAtlas then
    local l = eb:CreateTexture(nil, "BACKGROUND")
    NE.tex.SetAtlas(l, "auctionhouse-ui-inputfield-left", false)
    l:SetSize(CAP_W, INPUT_H); l:SetPoint("LEFT", eb, "LEFT", 0, 0)
    local r = eb:CreateTexture(nil, "BACKGROUND")
    NE.tex.SetAtlas(r, "auctionhouse-ui-inputfield-right", false)
    r:SetSize(CAP_W, INPUT_H); r:SetPoint("RIGHT", eb, "RIGHT", 0, 0)
    local m = eb:CreateTexture(nil, "BACKGROUND")
    NE.tex.SetAtlas(m, "auctionhouse-ui-inputfield-middle", false)
    m:SetHeight(INPUT_H); m:SetPoint("LEFT", l, "RIGHT", 0, 0); m:SetPoint("RIGHT", r, "LEFT", 0, 0)
  end
  return eb
end

-- Money input mirroring retail LargeMoneyInputFrame: gold (expands) | silver | copper, -6 gaps,
-- each box with its modern coin icon INSIDE-right + a right-justified number.
local MONEY_W = 230
local SC_W    = 64
local COIN    = 12
local function makeMoneyInput(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(MONEY_W, INPUT_H)
  local function field(coinAtlas, letters, place)
    local b = makeInput(f, SC_W, { justify = "RIGHT", rightInset = COIN + 9 })
    b:SetNumeric(true)
    b:SetMaxLetters(letters)
    place(b)
    local ic = b:CreateTexture(nil, "OVERLAY")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(ic, coinAtlas, false) end
    ic:SetSize(COIN, COIN)
    ic:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    b:SetScript("OnTextChanged", function() if f._onChanged then f._onChanged() end end)
    return b
  end
  f.copper = field("auctionhouse-icon-coin-copper", 2, function(b) b:SetPoint("RIGHT", f, "RIGHT", 0, 0) end)
  f.silver = field("auctionhouse-icon-coin-silver", 2, function(b) b:SetPoint("RIGHT", f.copper, "LEFT", -6, 0) end)
  f.gold   = field("auctionhouse-icon-coin-gold",   8, function(b)
    b:ClearAllPoints(); b:SetPoint("LEFT", f, "LEFT", 0, 0); b:SetPoint("RIGHT", f.silver, "LEFT", -6, 0)
  end)
  f.GetCopper = function()
    return (f.gold:GetNumber() or 0) * 10000 + (f.silver:GetNumber() or 0) * 100 + (f.copper:GetNumber() or 0)
  end
  f.SetCopper = function(_, c)
    c = math.max(0, math.floor((c or 0) + 0.5))
    f.gold:SetNumber(math.floor(c / 10000))
    f.silver:SetNumber(math.floor(c / 100) % 100)
    f.copper:SetNumber(c % 100)
  end
  f.SetOnChanged = function(_, fn) f._onChanged = fn end
  return f
end

-- Read-only money readout with the modern coin icons (stand-in for retail's
-- MoneyDisplayFrameTemplate): gold segment only when nonzero, silver/copper always,
-- so a zero amount reads "0s 0c" like the reference.
local function makeMoneyDisplay(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(170, 16)
  local atlases = { "auctionhouse-icon-coin-gold", "auctionhouse-icon-coin-silver", "auctionhouse-icon-coin-copper" }
  f.segs = {}
  for i = 1, 3 do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local ic = f:CreateTexture(nil, "OVERLAY")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(ic, atlases[i], false) end
    ic:SetSize(COIN, COIN)
    f.segs[i] = { fs = fs, ic = ic }
  end
  function f:SetAmount(copper)
    copper = math.max(0, math.floor((copper or 0) + 0.5))
    local vals = { math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100 }
    local anchor
    for i = 1, 3 do
      local seg = self.segs[i]
      seg.fs:ClearAllPoints()
      seg.ic:ClearAllPoints()
      if i > 1 or vals[1] > 0 then
        if anchor then
          seg.fs:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
        else
          seg.fs:SetPoint("LEFT", self, "LEFT", 0, 0)
        end
        seg.fs:SetText(tostring(vals[i]))
        seg.fs:Show()
        seg.ic:SetPoint("LEFT", seg.fs, "RIGHT", 2, 0)
        seg.ic:Show()
        anchor = seg.ic
      else
        seg.fs:Hide()
        seg.ic:Hide()
      end
    end
  end
  f:SetAmount(0)
  return f
end

-- Sort-direction arrow off the gear-manager flyout sheet -- the one rotatable arrow texture
-- already proven on this client (modules/character/EquipmentFlyout.lua). Upper half of the
-- sheet is the arrow pointing up; vertical texcoord flip points it down.
local ARROW_TEX = "Interface\\PaperDollInfoFrame\\UI-GearManager-FlyoutButton"
local function setArrowDirection(tex, descending)
  if descending then
    tex:SetTexCoord(0.15625, 0.84375, 0.5, 0)
  else
    tex:SetTexCoord(0.15625, 0.84375, 0, 0.5)
  end
end

function AH.BuildSellPane(parent)
  local pane = CreateFrame("Frame", nil, parent)
  pane:SetAllPoints(parent)

  local SF = {
    durationIndex = 2, buyoutMode = true, currentCount = 0,
    marketRows = {}, marketName = nil,
    sortKey = "buyout", sortDesc = false,
  }
  pane.Sell = SF

  ----------------------------------------------------------------------
  -- Panels (reference geometry: ItemSellFrame 363x440 flush on its bg,
  -- ItemSellList filling the rest). Bottom is +27 from the pane's bottom edge --
  -- the SAME convention the Buy tab's list/detail panels and the Auctions tab's
  -- left/right panels use (Window.lua's money inset top sits at exactly pane+27),
  -- so every tab's panel-bottom divider lines up flush with the currency bar
  -- instead of sitting a couple px above/below it depending on which tab is open.
  ----------------------------------------------------------------------
  local form = CreateFrame("Frame", nil, pane)
  form:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -69)
  form:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 4, 27)
  form:SetWidth(363)
  pane.Left = form

  local formBg = form:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(formBg, "auctionhouse-background-sell-left", false)
  end
  formBg:SetPoint("TOPLEFT", form, "TOPLEFT", 3, -3)
  formBg:SetSize(357, 437)

  local right = CreateFrame("Frame", nil, pane)
  right:SetPoint("TOPLEFT", form, "TOPRIGHT", 1, 0)
  right:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -5, 27)
  pane.Right = right

  local rightBg = right:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(rightBg, "auctionhouse-background-sell-right", false)
  end
  rightBg:SetPoint("TOPLEFT", right, "TOPLEFT", 3, -22)
  rightBg:SetSize(399, 418)

  -- Recessed gold-trim borders, same treatment as the Buy tab's panels (reference:
  -- full-panel inset on the form, header-strip + scrollbar-gutter inset on the list).
  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, form, 0, 0, 0, 0)
    pcall(NE.nineslice.AttachInset, right, 0, -19, -22, 0)
  end

  ----------------------------------------------------------------------
  -- "Create Auction" tab plate, straddling the form's top edge. On its own
  -- high-level child frame so it draws ABOVE the inset-border nineslice.
  ----------------------------------------------------------------------
  local tabFrame = CreateFrame("Frame", nil, form)
  tabFrame:SetAllPoints(form)
  tabFrame:EnableMouse(false)
  tabFrame:SetFrameLevel((form:GetFrameLevel() or 0) + 20)
  local tabL = tabFrame:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(tabL, "auctionhouse-selltab-left", true) end
  tabL:SetPoint("BOTTOMLEFT", form, "TOPLEFT", 42, -3)
  local tabText = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tabText:SetText(AUCTION_CREATE_AUCTION or CREATE_AUCTION or "Create Auction")
  tabText:SetPoint("LEFT", tabL, "RIGHT", 12, 0)
  local tabM = tabFrame:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(tabM, "auctionhouse-selltab-middle", false) then
    tabM:SetHeight(23)
  end
  tabM:SetPoint("TOPLEFT", tabL, "TOPRIGHT", 0, 0)
  tabM:SetPoint("RIGHT", tabText, "RIGHT", 12, 0)
  local tabR = tabFrame:CreateTexture(nil, "ARTWORK")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(tabR, "auctionhouse-selltab-right", true) end
  tabR:SetPoint("TOPLEFT", tabM, "TOPRIGHT", 0, 0)
  tabR:SetPoint("BOTTOMLEFT", tabM, "BOTTOMRIGHT", 0, 0)

  ----------------------------------------------------------------------
  -- Item display: itemheaderframe row plate with the 54px item slot on its
  -- left and the item name to its right (empty slot shows no label, like the
  -- reference). Both the slot and the wide row accept the click/drop.
  ----------------------------------------------------------------------
  local disp = CreateFrame("Button", nil, form)
  disp:SetSize(342, 72)
  disp:SetPoint("TOP", form, "TOP", 0, -14)
  pane.ItemDisplay = disp

  local hf = disp:CreateTexture(nil, "BORDER")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(hf, "auctionhouse-itemheaderframe", false) end
  hf:SetSize(342, 72)
  hf:SetPoint("TOPLEFT", disp, "TOPLEFT", 0, 0)

  local slot = CreateFrame("Button", nil, disp)
  slot:SetSize(54, 54)
  slot:SetPoint("LEFT", disp, "LEFT", 12, 0)
  pane.ItemSlot = slot

  local slotBG = slot:CreateTexture(nil, "BACKGROUND")
  slotBG:SetAllPoints(slot)
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(slotBG, "auctionhouse-itemicon-empty", false) end

  local sicon = slot:CreateTexture(nil, "ARTWORK")
  sicon:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
  sicon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
  sicon:Hide()
  pane.ItemIcon = sicon

  local itemName = disp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  itemName:SetPoint("LEFT", slot, "RIGHT", 12, 0)
  itemName:SetPoint("RIGHT", disp, "RIGHT", -12, 0)
  itemName:SetJustifyH("LEFT")
  itemName:SetText("")
  pane.ItemName = itemName

  -- Click/drag places from the cursor; right-click an occupied slot returns the item to the
  -- bag. Tooltip anchors to the SLOT (not the wide row) so it never lands off to the side.
  local function doPlace(mouseButton)
    if not ClickAuctionSellItemButton then return end
    if mouseButton == "RightButton" then
      if GetAuctionSellItemInfo and GetAuctionSellItemInfo() then
        ClickAuctionSellItemButton()
        if ClearCursor then ClearCursor() end
      end
    else
      -- Places the cursor item, or picks the slotted item back up when the cursor is empty.
      ClickAuctionSellItemButton()
    end
  end
  local slotEnter
  slotEnter = function()
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if GetAuctionSellItemInfo and GetAuctionSellItemInfo() and GameTooltip.SetAuctionSellItem then
      GameTooltip:SetAuctionSellItem()
    else
      GameTooltip:SetText(AUCTION_ITEM_TEXT or "Auction Item", 1, 1, 1)
    end
    GameTooltip:Show()
    -- Keep refreshing while hovered so pressing SHIFT mid-hover raises the comparison tooltip
    -- (NE.FrameUtil.WireLiveTooltip documents the stock UpdateTooltip contract). Registered on
    -- `slot` rather than on whichever button was entered: the tooltip is deliberately anchored to
    -- the icon even when the mouse is over the wider `disp` row, so `slot` is always the OWNER --
    -- and GameTooltip_OnUpdate only ever calls UpdateTooltip on the owner.
    slot.UpdateTooltip = slotEnter
  end
  local function slotLeave()
    slot.UpdateTooltip = nil
    GameTooltip:Hide()
  end
  for _, b in ipairs({ disp, slot }) do
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouseButton) doPlace(mouseButton) end)
    b:SetScript("OnReceiveDrag", function()
      if ClickAuctionSellItemButton then ClickAuctionSellItemButton() end
    end)
    b:SetScript("OnEnter", slotEnter)
    b:SetScript("OnLeave", slotLeave)
  end

  ----------------------------------------------------------------------
  -- Aligned form rows: right-justified 93px label + control 18px to its right
  -- (reference AuctionHouseSellFrameTemplate row shape).
  ----------------------------------------------------------------------
  local LABEL_W = 93
  local function alignedRow(below, labelText)
    local r = CreateFrame("Frame", nil, form)
    r:SetSize(330, 30)
    if below then
      r:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -15)
    else
      r:SetPoint("TOPLEFT", disp, "BOTTOMLEFT", 0, -10)
    end
    local l = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    l:SetSize(LABEL_W, 0)
    l:SetJustifyH("RIGHT")
    l:SetPoint("LEFT", r, "LEFT", 0, 0)
    l:SetText(labelText)
    r.Label = l
    return r
  end

  -- Quantity (+ Max).
  local qRow = alignedRow(nil, AUCTION_QUANTITY_LABEL or "Quantity")
  local qty = makeInput(qRow, 134)
  qty:SetNumeric(true)
  qty:SetMaxLetters(5)
  qty:SetPoint("LEFT", qRow.Label, "RIGHT", 18, 0)
  qty:SetText("1")
  pane.Quantity = qty

  local maxBtn = CreateFrame("Button", nil, qRow, "UIPanelButtonTemplate")
  maxBtn:SetSize(50, 20)
  maxBtn:SetPoint("LEFT", qty, "RIGHT", 10, 0)
  maxBtn:SetText(MAX or "Max")

  -- Buyout price (per item; relabeled "Starting Bid" when Buyout Mode is off).
  local pRow = alignedRow(qRow, AUCTION_BUYOUT_PRICE or "Buyout Price")
  local priceLabel = pRow.Label
  local money = makeMoneyInput(pRow)
  money:SetPoint("LEFT", pRow.Label, "RIGHT", 18, 0)
  pane.BuyoutPrice = money

  local function priceCopper()
    return money:GetCopper()
  end

  -- Duration: dropdown-look button in the same input skin; click cycles the three options.
  local dRow = alignedRow(pRow, AUCTION_DURATION or "Duration")
  local duration = CreateFrame("Button", nil, dRow)
  duration:SetSize(142, INPUT_H)
  duration:SetPoint("LEFT", dRow.Label, "RIGHT", 18, 0)
  if NE.tex and NE.tex.SetAtlas then
    local l = duration:CreateTexture(nil, "BACKGROUND")
    NE.tex.SetAtlas(l, "auctionhouse-ui-inputfield-left", false)
    l:SetSize(CAP_W, INPUT_H); l:SetPoint("LEFT", duration, "LEFT", 0, 0)
    local r = duration:CreateTexture(nil, "BACKGROUND")
    NE.tex.SetAtlas(r, "auctionhouse-ui-inputfield-right", false)
    r:SetSize(CAP_W, INPUT_H); r:SetPoint("RIGHT", duration, "RIGHT", 0, 0)
    local m = duration:CreateTexture(nil, "BACKGROUND")
    NE.tex.SetAtlas(m, "auctionhouse-ui-inputfield-middle", false)
    m:SetHeight(INPUT_H); m:SetPoint("LEFT", l, "RIGHT", 0, 0); m:SetPoint("RIGHT", r, "LEFT", 0, 0)
  end
  local durText = duration:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  durText:SetPoint("CENTER", duration, "CENTER", -6, 0)
  durText:SetText(DURATIONS[SF.durationIndex].label)
  local durArrow = duration:CreateTexture(nil, "OVERLAY")
  durArrow:SetTexture(ARROW_TEX)
  setArrowDirection(durArrow, true)
  durArrow:SetSize(12, 11)
  durArrow:SetPoint("RIGHT", duration, "RIGHT", -10, 0)
  pane.DurationButton = duration

  -- Deposit / Total Price coin readouts.
  local depRow = alignedRow(dRow, AUCTION_DEPOSIT_LABEL or DEPOSIT or "Deposit")
  local dep = makeMoneyDisplay(depRow)
  dep:SetPoint("LEFT", depRow.Label, "RIGHT", 18, 0)
  pane.Deposit = dep

  local totRow = alignedRow(depRow, AUCTION_TOTAL_VALUE or "Total Price")
  local total = makeMoneyDisplay(totRow)
  total:SetPoint("LEFT", totRow.Label, "RIGHT", 18, 0)
  pane.Total = total

  ----------------------------------------------------------------------
  -- Create Auction + Buyout Mode
  ----------------------------------------------------------------------
  local createBtn = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
  createBtn:SetSize(160, 22)
  createBtn:SetPoint("TOP", totRow, "BOTTOM", 0, -16)
  createBtn:SetText(AUCTION_CREATE_AUCTION or "Create Auction")
  createBtn:Disable()
  pane.CreateButton = createBtn

  local buyoutMode = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
  buyoutMode:SetSize(28, 28)
  buyoutMode:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 10, 8)
  buyoutMode:SetChecked(true)
  local buyoutLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  buyoutLabel:SetPoint("LEFT", buyoutMode, "RIGHT", 4, 0)
  buyoutLabel:SetText(AUCTION_HOUSE_BUYOUT_MODE or "Buyout Mode")

  ----------------------------------------------------------------------
  -- Market listings (right side): sortable header strip + refresh, rows on a
  -- faux scroll with the addon's custom scrollbar (same shape as the Buy tab).
  ----------------------------------------------------------------------
  local headerStrip = right:CreateTexture(nil, "BORDER")
  headerStrip:SetTexture("Interface\\Buttons\\WHITE8X8")
  headerStrip:SetVertexColor(0.06, 0.06, 0.07, 0.95)
  headerStrip:SetPoint("TOPLEFT", right, "TOPLEFT", 3, -1)
  headerStrip:SetPoint("TOPRIGHT", right, "TOPRIGHT", -22, -1)
  headerStrip:SetHeight(21)

  local applySort   -- forward decl (used by header clicks)
  local refreshMarketRows

  local headerDefs = {
    { key = "buyout", text = AUCTION_BUYOUT_PRICE or "Buyout", x = 8,   w = 130 },
    { key = "qty",    text = AUCTION_QUANTITY_LABEL or "Qty",  x = 152, w = 48 },
    { key = "seller", text = AUCTION_SELLER or "Seller",       x = 206, w = 110 },
  }
  local headerBtns = {}
  local function updateSortArrows()
    for i = 1, #headerBtns do
      local hb = headerBtns[i]
      if hb._key == SF.sortKey then
        setArrowDirection(hb.Arrow, SF.sortDesc)
        hb.Arrow:Show()
      else
        hb.Arrow:Hide()
      end
    end
  end
  for i = 1, #headerDefs do
    local hd = headerDefs[i]
    local hb = CreateFrame("Button", nil, right)
    hb:SetSize(hd.w, 19)
    hb:SetPoint("TOPLEFT", right, "TOPLEFT", hd.x, -2)
    hb._key = hd.key
    local fs = hb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", hb, "LEFT", 4, 0)
    fs:SetText(hd.text)
    hb.Text = fs
    local ar = hb:CreateTexture(nil, "OVERLAY")
    ar:SetTexture(ARROW_TEX)
    ar:SetSize(10, 9)
    ar:SetPoint("LEFT", fs, "RIGHT", 3, 0)
    ar:Hide()
    hb.Arrow = ar
    hb:SetScript("OnClick", function(self)
      if SF.sortKey == self._key then
        SF.sortDesc = not SF.sortDesc
      else
        SF.sortKey, SF.sortDesc = self._key, false
      end
      applySort()
      updateSortArrows()
      refreshMarketRows()
    end)
    headerBtns[i] = hb
  end

  -- Text refresh button (an icon-texture refresh already proved unreliable on this client --
  -- see Browse.lua's detailRefresh note), sitting at the header strip's right end.
  local refreshBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
  refreshBtn:SetSize(64, 18)
  refreshBtn:SetPoint("TOPRIGHT", right, "TOPRIGHT", -26, -2)
  refreshBtn:SetText(REFRESH or "Refresh")
  pane.RefreshButton = refreshBtn

  local emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  emptyText:SetPoint("CENTER", right, "CENTER", 0, 40)
  emptyText:SetText("")
  emptyText:SetTextColor(1, 0.82, 0)
  pane.EmptyText = emptyText

  local ROW_H = 18
  local VISIBLE_ROWS = 21
  local rows = {}
  -- FauxScrollFrameTemplate resolves its scrollbar sub-widgets via GetName() concatenation --
  -- it must have a real global name (see Browse.lua for the failure mode).
  local scroll = CreateFrame("ScrollFrame", "NE_AuctionHouseSellMarketScroll", right, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -26)
  scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -26, 8)

  -- Physical scrollbar track+thumb in the reserved gutter. Must be forced to the window's
  -- DIALOG strata or the rows draw over it (same trap as every other list in this window).
  if NE.scrollbar and NE.scrollbar.BuildCustom then
    local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, { x = -8 })
    if ok and bar then
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((right:GetFrameLevel() or 1) + 10)
      -- Arrow buttons' strata/level were set against the bar's strata AT BUILD TIME ("HIGH") --
      -- promoting the bar to DIALOG afterward (same trap as every other list in this window)
      -- leaves them a strata behind unless they're bumped too.
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  local function fsUpdate(frame, totalCount, shown, step)
    if FauxScrollFrame_Update then FauxScrollFrame_Update(frame, totalCount, shown, step)
    else frame.offset = frame.offset or 0 end
  end
  local function fsGetOffset(frame)
    if FauxScrollFrame_GetOffset then return FauxScrollFrame_GetOffset(frame) or 0 end
    return frame.offset or 0
  end

  applySort = function()
    local key, desc = SF.sortKey, SF.sortDesc
    table.sort(SF.marketRows, function(a, b)
      local av, bv
      if key == "qty" then
        av, bv = a.count or 0, b.count or 0
      elseif key == "seller" then
        av, bv = string.lower(a.owner or ""), string.lower(b.owner or "")
      else
        av, bv = a.perUnit or math.huge, b.perUnit or math.huge
      end
      if av == bv then return (a.index or 0) < (b.index or 0) end
      if desc then return av > bv end
      return av < bv
    end)
  end

  local function ensureRow(i)
    local row = rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, right)
    row:SetHeight(ROW_H)
    if i == 1 then
      row:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -26)
      row:SetPoint("TOPRIGHT", right, "TOPRIGHT", -30, -26)
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

    row.Buyout = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Buyout:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.Buyout:SetWidth(130)
    row.Buyout:SetJustifyH("LEFT")

    row.Qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Qty:SetPoint("LEFT", row, "LEFT", 150, 0)
    row.Qty:SetWidth(46)
    row.Qty:SetJustifyH("LEFT")

    row.Seller = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Seller:SetPoint("LEFT", row, "LEFT", 204, 0)
    row.Seller:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.Seller:SetJustifyH("LEFT")

    -- Click a listing to copy its per-unit buyout into the price input.
    row:SetScript("OnClick", function(self)
      if not self._buyout or not self._count or self._count <= 0 then return end
      money:SetCopper(self._buyout / self._count)
    end)

    rows[i] = row
    return row
  end

  local function coin(copper)
    if not copper or copper <= 0 then return "0" end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return tostring(copper)
  end

  refreshMarketRows = function()
    local data = SF.marketRows
    local totalCount = #data
    fsUpdate(scroll, totalCount, VISIBLE_ROWS, ROW_H + 1)
    local offset = fsGetOffset(scroll)

    if totalCount > 0 then
      emptyText:Hide()
    else
      emptyText:Show()
    end

    for i = 1, VISIBLE_ROWS do
      local row = ensureRow(i)
      local d = data[i + offset]
      if d then
        row._buyout, row._count = d.buyout, d.count
        row.Buyout:SetText(coin(d.buyout))
        row.Qty:SetText(tostring(d.count))
        row.Seller:SetText(d.owner or "")
        row:Show()
      else
        row._buyout, row._count = nil, nil
        row:Hide()
      end
    end
  end
  pane.RefreshMarketRows = refreshMarketRows

  scroll:SetScript("OnVerticalScroll", function(self, offset)
    if FauxScrollFrame_OnVerticalScroll then
      FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H + 1, refreshMarketRows)
    else
      local step = ROW_H + 1
      self.offset = math.max(0, math.floor((offset / step) + 0.5))
      refreshMarketRows()
    end
  end)

  ----------------------------------------------------------------------
  -- Behaviour
  ----------------------------------------------------------------------
  local function readMarket()
    local out = {}
    local n = (GetNumAuctionItems and GetNumAuctionItems("list")) or 0
    for i = 1, n do
      local ok, name, _, count, _, _, _, _, _, buyoutPrice, _, _, owner =
        pcall(GetAuctionItemInfo, "list", i)
      if not ok then break end
      if name and buyoutPrice and buyoutPrice > 0 then
        local cnt = count or 1
        out[#out + 1] = {
          index = i, count = cnt, buyout = buyoutPrice, owner = owner,
          perUnit = (cnt > 0) and (buyoutPrice / cnt) or buyoutPrice,
        }
      end
    end
    return out
  end

  local function queryMarket(force)
    local name = GetAuctionSellItemInfo and GetAuctionSellItemInfo()
    if not name then
      SF.marketName = nil
      SF.marketRows = {}
      emptyText:SetText("")
      refreshMarketRows()
      return
    end
    if name == SF.marketName and not force then return end

    -- ISSUE #31: the Buy tab's scan owns the shared "list" query slot while it is paging. Firing
    -- this lookup into the middle of it steals the throttle slot, so the scan burns its retries and
    -- aborts with a partial aggregate. Wait for it -- bounded, so a wedged scan can't stall this
    -- forever. Retry with force=true or the name-unchanged guard above would swallow it.
    if AH.IsBrowseScanning and AH.IsBrowseScanning() then
      SF._marketWaits = (SF._marketWaits or 0) + 1
      if SF._marketWaits <= 20 and C_Timer and C_Timer.After then
        emptyText:SetText(SEARCHING or "Searching...")
        C_Timer.After(0.25, function() queryMarket(true) end)
        return
      end
    end
    SF._marketWaits = 0

    SF.marketName = name
    if not (CanSendAuctionQuery and CanSendAuctionQuery("list")) then
      emptyText:SetText(AUCTION_HOUSE_THROTTLED or "Auction query is throttled. Try again in a moment.")
      return
    end
    emptyText:SetText(SEARCHING or "Searching...")
    SF.marketRows = {}
    refreshMarketRows()
    -- ISSUE #31: -1 ("any rarity"), not 0 -- QueryAuctionItems' quality argument is an exact match
    -- and 0 means "exactly Poor", so this market lookup previously came back empty for every item
    -- that wasn't grey. Mirrors AH.ANY_QUALITY in Browse.lua.
    if AH.ClaimListQuery then AH.ClaimListQuery("sellmarket") end
    pcall(QueryAuctionItems, name, 0, 0, 0, 0, 0, 0, false, -1, false)
  end

  refreshBtn:SetScript("OnClick", function()
    queryMarket(true)
  end)

  local function updatePostState()
    local slotted = GetAuctionSellItemInfo and GetAuctionSellItemInfo()
    local stack = tonumber(qty:GetText()) or 0
    local price = priceCopper()
    local ok = slotted ~= nil
              and stack >= 1
              and stack <= (SF.currentCount or 0)
              and price > 0
    createBtn:SetEnabled(ok and true or false)
  end
  pane.UpdatePostState = updatePostState

  local function recalcPrice()
    local stack = tonumber(qty:GetText()) or 0
    local perItem = priceCopper()
    local totalPrice = perItem * stack
    local minBid = totalPrice
    local buyoutPrice = SF.buyoutMode and totalPrice or 0

    local depositCopper = computeDeposit(DURATIONS[SF.durationIndex].code, minBid, buyoutPrice, stack, 1)
    dep:SetAmount(depositCopper)
    total:SetAmount(SF.buyoutMode and buyoutPrice or minBid)
    SF._minBid, SF._buyout, SF._stack, SF._depositCopper = minBid, buyoutPrice, stack, depositCopper
    updatePostState()
  end
  pane.RecalculatePrice = recalcPrice
  money:SetOnChanged(recalcPrice)

  local function updateItem()
    local name, tex, count = GetAuctionSellItemInfo()
    if tex then
      sicon:SetTexture(tex)
      sicon:Show()
    else
      sicon:Hide()
    end
    if name then
      itemName:SetText(name)
      SF.currentCount = count or 1
      qty:SetText(tostring(SF.currentCount))
    else
      itemName:SetText("")
      SF.currentCount = 0
    end
    recalcPrice()
    queryMarket()
  end

  qty:SetScript("OnTextChanged", function(self)
    local n = tonumber(self:GetText()) or 0
    if n > (SF.currentCount or 0) and SF.currentCount > 0 then
      self:SetNumber(SF.currentCount)
      return
    end
    recalcPrice()
  end)

  maxBtn:SetScript("OnClick", function()
    qty:SetNumber(SF.currentCount or 0)
    recalcPrice()
  end)

  duration:SetScript("OnClick", function()
    SF.durationIndex = (SF.durationIndex % #DURATIONS) + 1
    durText:SetText(DURATIONS[SF.durationIndex].label)
    recalcPrice()
  end)

  buyoutMode:SetScript("OnClick", function(self)
    SF.buyoutMode = self:GetChecked() and true or false
    priceLabel:SetText(SF.buyoutMode and (AUCTION_BUYOUT_PRICE or "Buyout Price") or (AUCTION_STARTING_PRICE or "Starting Bid"))
    recalcPrice()
  end)

  createBtn:SetScript("OnClick", function()
    if not (GetAuctionSellItemInfo and GetAuctionSellItemInfo()) then return end
    local stack = SF._stack or 0
    if stack < 1 then return end
    local minBid = SF._minBid or 0
    local buyoutPrice = SF._buyout or 0
    if minBid <= 0 then return end
    local durationCode = DURATIONS[SF.durationIndex].code
    local ok = pcall(PostAuction, minBid, buyoutPrice, durationCode, stack, 1)
    if ok then
      if PlaySound and SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND then
        PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND)
      end
      if DEFAULT_CHAT_FRAME and ERR_AUCTION_STARTED then
        DEFAULT_CHAT_FRAME:AddMessage(ERR_AUCTION_STARTED)
      end
    end
  end)

  ----------------------------------------------------------------------
  -- Events
  ----------------------------------------------------------------------
  local watcher = CreateFrame("Frame", nil, pane)
  watcher:RegisterEvent("NEW_AUCTION_UPDATE")
  watcher:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
  watcher:RegisterEvent("AUCTION_HOUSE_SHOW")
  watcher:RegisterEvent("PLAYER_MONEY")
  watcher:SetScript("OnEvent", function(_, event)
    if not pane:IsShown() then
      if event == "AUCTION_HOUSE_SHOW" then updateItem() end
      return
    end
    if event == "NEW_AUCTION_UPDATE" then
      updateItem()
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
      -- ISSUE #31: only read the shared "list" slot when OUR market lookup is what filled it.
      -- This used to fire on every update, so a Buy-tab scan page or an Auctionator search landed
      -- in this tab's market table as if it were price data for the slotted item.
      if AH.OwnsListQuery and not AH.OwnsListQuery("sellmarket") then return end
      SF.marketRows = readMarket()
      if #SF.marketRows == 0 then
        emptyText:SetText(BROWSE_NO_RESULTS_TEXT or "No auctions found for this item.")
      end
      applySort()
      updateSortArrows()
      refreshMarketRows()
    elseif event == "PLAYER_MONEY" then
      updatePostState()
    end
  end)

  pane:HookScript("OnShow", function()
    updateItem()
  end)

  updateSortArrows()
  updateItem()

  return pane
end
