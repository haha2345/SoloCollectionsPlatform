-- DragonUI_NewEra/modules/auctionhouse/Window.lua
-- Visual shell host for the modern Auction House panel with optional external tab embedding.

local NE = DragonUI_NewEra
if not NE then return end

NE.ah = NE.ah or {}
local AH = NE.ah

local MODULE = "AuctionHouse"
local FRAME_NAME = "NE_AuctionHouseFrame"

-- The window is called "Auction House" whichever built-in tab is showing, matching retail (and the
-- physical thing you walked up to) rather than naming the tab twice -- the tab strip already says
-- Buy / Sell / Auctions. 3.3.5a has no AUCTION_HOUSE global; BUTTON_LAG_AUCTIONHOUSE is the only
-- GlobalStrings entry whose value is exactly "Auction House", and it IS localized per client, so
-- it beats hardcoding English. Literal fallback in case a locale ever drops it.
local AH_WINDOW_TITLE = BUTTON_LAG_AUCTIONHOUSE or "Auction House"

-- Ctrl-click dress-up preview. In WoW 3.3.5a the dressup function is DressUpItemLink(link);
-- DressUpLink is the retail/modern name and does not exist in this client. The legacy
-- AuctionFrame is kept alive (alpha 0) to hold the AH session. In environments where
-- SideDressUpFrame.parentFrame points to AuctionFrame, DressUpVisual would route to the bare
-- side model instead of the full Dressing Room; temporarily clear parentFrame so it falls
-- through to DressUpFrame, then restore.
function AH.DressUpItem(link)
  if not link or not DressUpItemLink then return end
  local side = _G.SideDressUpFrame
  local saved
  if side then saved = side.parentFrame; side.parentFrame = nil end
  DressUpItemLink(link)
  if side then side.parentFrame = saved end
end

-- Shared modified-click router for every item row in this window: SHIFT links the item into an
-- open chat edit box, CTRL opens the dressing room. Returns true when it consumed the click, so
-- callers can fall through to their normal (plain-click) behaviour otherwise.
--
-- Deliberately NOT a plain HandleModifiedItemClick(link) call, even though that is the stock
-- router (ItemButtonTemplate.lua) and has exactly this CHATLINK-then-DRESSUP precedence: its
-- DRESSUP branch goes straight to DressUpItemLink and would bypass the SideDressUpFrame workaround
-- above. Same order, our dress-up path.
function AH.HandleItemClick(link)
  if not link then return false end

  if IsModifiedClick and IsModifiedClick("CHATLINK") and type(ChatEdit_InsertLink) == "function" then
    -- Suppress this addon's OWN ChatEdit_InsertLink hook (Browse.lua) for the duration of the
    -- call. That hook turns a shift-click into an auction search whenever no chat edit box takes
    -- the link -- which is what we want when shift-clicking an item in the BAGS while the window
    -- is open (issue #17), but not for a row inside the results list, where it would throw away
    -- the results being looked at and re-search the item just clicked. hooksecurefunc post-hooks
    -- run synchronously inside the call, so a plain flag around it is enough; no timer needed.
    AH._suppressLinkSearch = true
    local ok, inserted = pcall(ChatEdit_InsertLink, link)
    AH._suppressLinkSearch = false
    if ok and inserted then return true end
    -- No chat box took it: fall through, so shift-click behaves like a plain click rather than
    -- silently doing nothing.
  end

  if IsModifiedClick and IsModifiedClick("DRESSUP") then
    AH.DressUpItem(link)
    return true
  end

  return false
end

local BASE_MODES = {
  Buy = true,
  Sell = true,
  Auctions = true,
}

local function isModuleEnabled()
  return not (NE.modules and NE.modules.IsEnabled) or NE.modules.IsEnabled(MODULE)
end

-- Force the AH background/chrome sheets GPU-resident for the whole session via a permanent,
-- SHOWN 1x1 BACKGROUND frame (same pattern as Spellbook.lua's prewarmBackgroundBLP). createWindow()
-- builds ALL panes (Buy/Sell/Auctions) at PLAYER_LOGIN while the real window frame is still
-- :Hide()'n -- every background/inset/nav-button texture cropped from these two sheets gets
-- SetTexture()'d onto a texture that never actually draws until the player first opens the AH.
-- If the BLP hasn't finished streaming from disk by then, the crop resolves to a black frame or
-- the old Blizzard art peeking through. A shown frame forces the upload up front and keeps the
-- file resident (not evicted) for the rest of the session.
local AH_PREWARM_FILES = { 3054898, 3046538, 2922105 }
local function prewarmAuctionHouseTextures()
  if AH._bgPrewarmed then return end
  AH._bgPrewarmed = true
  local pw = CreateFrame("Frame", nil, UIParent)
  pw:SetFrameStrata("BACKGROUND"); pw:SetFrameLevel(1)
  pw:SetSize(1, 1)
  pw:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  for _, fdid in ipairs(AH_PREWARM_FILES) do
    local path = NE.tex and NE.tex.localFiles and NE.tex.localFiles[fdid]
    if path then
      local t = pw:CreateTexture(nil, "BACKGROUND")
      t:SetAllPoints(pw)
      t:SetTexture(path)
    end
  end
  pw:Show()
  AH._bgPrewarm = pw
end

local function disableMouseTree(frame, depth)
  if not frame or (depth or 0) > 10 then return end
  if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
  if frame.EnableMouseWheel then pcall(frame.EnableMouseWheel, frame, false) end
  if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
  if frame.GetChildren then
    local kids = { frame:GetChildren() }
    for i = 1, #kids do
      disableMouseTree(kids[i], (depth or 0) + 1)
    end
  end
end

local function restoreFrameTree(frame, depth)
  if not frame or (depth or 0) > 10 then return end
  if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
  if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
  if frame.GetChildren then
    local kids = { frame:GetChildren() }
    for i = 1, #kids do
      restoreFrameTree(kids[i], (depth or 0) + 1)
    end
  end
end

local function cloakFrame(frame)
  if not frame then return end
  disableMouseTree(frame, 0)
  if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
end

local function suppressLegacyAuctionFrame()
  local f = _G.AuctionFrame
  if not f then return end
  cloakFrame(f)

  if not f._neAHCloakHooked then
    f._neAHCloakHooked = true
    f:HookScript("OnShow", function(self)
      cloakFrame(self)
    end)
  end

  -- Some tab buttons are global-named and can still be visible/clickable above alpha-cloaked content.
  for i = 1, 16 do
    local tab = _G["AuctionFrameTab" .. i]
    if tab then
      cloakFrame(tab)
    end
  end

  local childNames = {
    "AuctionFrameBrowse",
    "AuctionFrameBid",
    "AuctionFrameAuctions",
    "AuctionFrameMoneyFrame",
    "BrowseName",
    "BrowseMinLevel",
    "BrowseMaxLevel",
  }
  for i = 1, #childNames do
    local child = _G[childNames[i]]
    if child then
      cloakFrame(child)
    end
  end
end

local function suppressModernAuctionFrame()
  local f = _G.AuctionHouseFrame
  if not f then return end
  if IsUsingLegacyAuctionClient and IsUsingLegacyAuctionClient() then return end

  cloakFrame(f)
  if not f._neAHCloakHooked then
    f._neAHCloakHooked = true
    f:HookScript("OnShow", function(self)
      cloakFrame(self)
    end)
  end
end

-- Exposed so Browse.lua's AUCTION_ITEM_LIST_UPDATE watcher can re-cloak on every event, not just
-- at window-open time -- the stock AuctionFrameBrowse_Update() (called every such event so the
-- legacy client's own internal state stays consistent) can reassert Show()/alpha on the legacy
-- frame as part of its own normal update logic, silently undoing the one-time cloak below and
-- letting its old parchment/stone background bleed back through.
AH.SuppressLegacyAuctionFrame = suppressLegacyAuctionFrame
AH.SuppressModernAuctionFrame = suppressModernAuctionFrame

-- Reverse the cloak applied by suppressLegacyAuctionFrame so Auctionator's UI becomes visible.
-- Called by external tab providers that need AuctionFrame to render their own content.
local function uncloakLegacyAuctionFrame()
  local f = _G.AuctionFrame
  if not f then return end
  restoreFrameTree(f, 0)
  for i = 1, 16 do
    local tab = _G["AuctionFrameTab" .. i]
    if tab then restoreFrameTree(tab, 0) end
  end
  local named = { "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions", "AuctionFrameMoneyFrame" }
  for i = 1, #named do
    local child = _G[named[i]]
    if child then restoreFrameTree(child, 0) end
  end
end
AH.UncloakLegacyAuctionFrame = uncloakLegacyAuctionFrame

local function buildChrome(f)
  local body = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
  if rockPath then
    body:SetTexture(rockPath, "REPEAT", "REPEAT")
  else
    body:SetTexture(374155, "REPEAT", "REPEAT")
  end
  body:SetHorizTile(true)
  body:SetVertTile(true)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -21)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

  local streaks = f:CreateTexture(nil, "BORDER")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(streaks, "_UI-Frame-TopTileStreaks", false)
  end
  streaks:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -21)
  streaks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -21)
  streaks:SetHeight(43)
  streaks:SetHorizTile(true)

  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f)
  if NE.nineslice and NE.nineslice.ApplyLayout then
    NE.nineslice.ApplyLayout(ns, "PortraitFrameTemplate")
  end
  f.NineSlice = ns

  -- EnsureTitle, not SetTitle: this window builds its own chrome and never created a title
  -- FontString, and SetTitle silently returns when it can't find one -- which is why the title bar
  -- rendered empty. EnsureTitle makes the band + FontString (as f.Title), so the setTitleForMode
  -- calls below find it from then on.
  local title = AH_WINDOW_TITLE
  if NE.panelchrome and NE.panelchrome.EnsureTitle then
    NE.panelchrome.EnsureTitle(f, title)
  elseif NE.panelchrome and NE.panelchrome.SetTitle then
    NE.panelchrome.SetTitle(f, title)
  elseif f.TitleText and f.TitleText.SetText then
    f.TitleText:SetText(title)
  end

  local close = CreateFrame("Button", FRAME_NAME .. "CloseButton", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  close:SetScript("OnClick", function()
    if CloseAuctionHouse and CanSendAuctionQuery and CanSendAuctionQuery("list") then
      CloseAuctionHouse()
    end
    AH.Hide()
  end)
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    NE.panelchrome.ModernizeCloseButton(close, { frameLevelBump = 10 })
  end

  local portrait = f.portrait or f.Portrait or f.PortraitTex
  if portrait and SetPortraitTexture then
    pcall(SetPortraitTexture, portrait, "npc")
  elseif portrait and portrait.SetTexture then
    portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  end
end

local function setTitleForMode(mode)
  local f = AH.frame
  if not f then return end
  local t = ""
  if type(mode) == "string" and string.find(mode, "external:", 1, true) == 1 then
    -- External tab: prefer the provider's own live title ("Auctionator+ - Buy", mirrored into
    -- AH.atr._lastTitle by AuctionatorEmbed's SetText hook), falling back to the tab's label.
    local key = string.gsub(mode, "^external:", "")
    local def = f.ExternalTabDefs and f.ExternalTabDefs[key]
    if def and def.providerId == "Auctionator" and AH.atr and AH.atr._lastTitle then
      t = AH.atr._lastTitle
    else
      t = (def and def.text) or "Auctionator"
    end
  else
    -- Every built-in tab (Buy / Sell / Auctions) keeps the window's own name; the tab strip
    -- already says which one is active. Only an embedded external provider overrides it, above.
    t = AH_WINDOW_TITLE
  end
  if NE.panelchrome and NE.panelchrome.SetTitle then
    NE.panelchrome.SetTitle(f, t)
  elseif f.TitleText and f.TitleText.SetText then
    f.TitleText:SetText(t)
  end
end

local function setMode(mode)
  local f = AH.frame
  if not f then return end

  if not mode or (not BASE_MODES[mode] and not (type(mode) == "string" and string.find(mode, "external:", 1, true) == 1)) then
    mode = "Buy"
  end

  -- External modes are only valid while their tab definition exists.
  if type(mode) == "string" and string.find(mode, "external:", 1, true) == 1 then
    local key = string.gsub(mode, "^external:", "")
    if not (f.ExternalTabDefs and f.ExternalTabDefs[key]) then
      mode = "Buy"
    end
  end

  f._switchingModes = true
  f._mode = mode

  if f.ContentRoot and f.ContentRoot.GetChildren then
    local children = { f.ContentRoot:GetChildren() }
    for i = 1, #children do
      local c = children[i]
      if c and c.Hide then c:Hide() end
    end
  end

  local isExternalMode = type(mode) == "string" and string.find(mode, "external:", 1, true) == 1

  if f.Panes then
    local selected = f.Panes[mode]
    -- Only fall back to a base pane when the mode is genuinely unknown (not one of Buy/Sell/
    -- Auctions). External modes (e.g. "external:Auctionator") are intentionally absent from
    -- f.Panes -- they render via f.ExternalPane below -- so they must NOT be coerced into "Buy"
    -- here, or every click on a mirrored Auctionator tab silently reopens the Buy pane instead.
    if not selected and not isExternalMode then
      selected = f.Panes.Buy or f.Panes.Sell or f.Panes.Auctions
      if selected == f.Panes.Sell then mode = "Sell"
      elseif selected == f.Panes.Auctions then mode = "Auctions"
      else mode = "Buy" end
      f._mode = mode
    end
    if selected then selected:Show() end
  end

  if f.ExternalPane then
    if isExternalMode then
      f.ExternalPane:Show()
    end
  end

  -- Grow the shell to Auctionator's native footprint on its tabs, restore on the base tabs.
  -- Done BEFORE the external onSelect (which reveals Auctionator's panel) so it lays out at the
  -- final size. No-ops until AuctionatorEmbed has actually embedded (AH._atrEmbedded).
  if AH.atr and AH.atr.SetWindowForExternal then
    AH.atr.SetWindowForExternal(isExternalMode and AH._atrEmbedded and true or false)
  end

  if PanelTemplates_SetTab and f._tabIds and f._tabIds[mode] then
    PanelTemplates_SetTab(f, f._tabIds[mode])
  end

  if isExternalMode then
    local key = string.gsub(mode, "^external:", "")
    local def = f.ExternalTabDefs and f.ExternalTabDefs[key]
    if def and type(def.onSelect) == "function" then
      def.onSelect({
        frame = f,
        mode = mode,
        showHint = function(msg)
          if not f.ExternalHint then return end
          f.ExternalHint:SetText(msg or "")
        end,
      })
    end
    if f.ExternalHint then f.ExternalHint:Show() end
  else
    if f.ExternalHint then
      f.ExternalHint:SetText("")
      f.ExternalHint:Hide()
    end
  end

  setTitleForMode(mode)
  -- External modes hand off rendering to a provider (e.g. Auctionator); suppressing the legacy
  -- AH frame here would undo whatever the provider's onSelect just showed -- UNLESS the
  -- provider's UI has been reparented INTO this shell (AuctionatorEmbed sets AH._atrEmbedded),
  -- in which case the legacy frame no longer hosts anything of the provider's and must stay
  -- cloaked.
  if not isExternalMode or AH._atrEmbedded then
    suppressLegacyAuctionFrame()
  end
  f._switchingModes = false
end
AH.SetMode = setMode

-- Player money readout, bottom-left of the window (retail AuctionHouseFrame.xml money inset).
-- DOWNPORT: the reference's NE.money.Well used retail-only "ThinGoldEdgeTemplate" /
-- "MoneyDisplayFrameTemplate", neither shipped on 3.3.5a. Use the same proven stock pattern
-- CombinedBag.lua already relies on for its own money readout: native "SmallMoneyFrameTemplate"
-- set to type "PLAYER", which self-initializes and self-updates on PLAYER_MONEY with no extra
-- wiring. Wrapped in our own AttachInset recessed border for visual consistency with the rest
-- of the window (categories/results panels use the same border).
local function buildMoneyFrame(f)
  local inset = CreateFrame("Frame", nil, f)
  inset:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, 27)
  inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 167, 3)

  -- AttachInset alone only draws the thin gold-trim border pieces (transparent center) -- every
  -- other inset in this window (categories/results panels) additionally fills behind it with a
  -- dark tint so the well itself reads as a solid recessed box, not just an outline over the rock
  -- chrome. Same near-black tone used by the results header strip / filter panel for consistency.
  local fill = inset:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture("Interface\\Buttons\\WHITE8X8")
  fill:SetVertexColor(0.06, 0.06, 0.07, 0.95)
  fill:SetAllPoints(inset)

  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, inset, 0, 0, 0, 0)
  end
  f.MoneyFrameInset = inset

  local money = CreateFrame("Frame", FRAME_NAME .. "MoneyFrame", inset, "SmallMoneyFrameTemplate")
  money:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
  if MoneyFrame_SetType then pcall(MoneyFrame_SetType, money, "PLAYER") end
  if MoneyFrame_SetMaxDisplayWidth then pcall(MoneyFrame_SetMaxDisplayWidth, money, 150) end
  f.MoneyFrame = money
end

local function buildMainTabs(f)
  local labels = {
    AUCTION_HOUSE_BUY_TAB or "Buy",
    AUCTION_HOUSE_SELL_TAB or "Sell",
    AUCTION_HOUSE_AUCTIONS_SUB_TAB or "Auctions",
  }

  f._tabIds = {}
  f.BaseTabNames = {}

  for i = 1, #labels do
    local name = FRAME_NAME .. "Tab" .. i
    local tab = CreateFrame("Button", name, f, "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(labels[i])

    local mode = (i == 1 and "Buy") or (i == 2 and "Sell") or "Auctions"
    tab._neMode = mode
    tab:SetScript("OnClick", function(self)
      setMode(self._neMode)
    end)

    f._tabIds[mode] = i
    f.BaseTabNames[#f.BaseTabNames + 1] = name

    if NE.tabs and NE.tabs.ReskinClassicTab then
      NE.tabs.ReskinClassicTab(name)
    end
  end

  if PanelTemplates_SetNumTabs then
    PanelTemplates_SetNumTabs(f, #labels)
  end

  if NE.tabs and NE.tabs.SizeAndAnchorTabs then
    NE.tabs.SizeAndAnchorTabs(f, f.BaseTabNames, { startX = 20, startY = 2, parentPoint = "BOTTOMLEFT" })
  end
end

function AH.RefreshExternalTabs()
  local f = AH.frame
  if not f then return end

  if f.ExternalTabs then
    for i = 1, #f.ExternalTabs do
      f.ExternalTabs[i]:Hide()
    end
  end

  f.ExternalTabs = f.ExternalTabs or {}
  f.ExternalTabDefs = {}

  local ext = {}
  if AH.bridge and AH.bridge.GetExternalTabs then
    ext = AH.bridge.GetExternalTabs(f)
  end

  local nextId = #(f.BaseTabNames or {})
  local allNames = {}
  for i = 1, #(f.BaseTabNames or {}) do
    allNames[#allNames + 1] = f.BaseTabNames[i]
  end

  for i = 1, #ext do
    nextId = nextId + 1
    local name = FRAME_NAME .. "Tab" .. nextId
    local tab = _G[name] or f.ExternalTabs[i]
    if not tab then
      tab = CreateFrame("Button", name, f, "CharacterFrameTabButtonTemplate")
      f.ExternalTabs[i] = tab
      if NE.tabs and NE.tabs.ReskinClassicTab then
        NE.tabs.ReskinClassicTab(name)
      end
    end

    local mode = "external:" .. tostring(ext[i].key)
    tab._neMode = mode
    tab:SetID(nextId)
    tab:SetText(ext[i].text)
    -- Auctionator's own native tabs use its signature orange text; carry that through so the
    -- embedded tabs read as distinct from the shell's base Buy/Sell/Auctions tabs (which they
    -- otherwise duplicate by name).
    if ext[i].providerId == "Auctionator" then
      local fs = _G[name .. "Text"]
      if fs and fs.SetTextColor then fs:SetTextColor(1, 0.55, 0.25) end
    end
    tab:SetScript("OnClick", function(self)
      setMode(self._neMode)
    end)
    tab:Show()

    f.ExternalTabDefs[ext[i].key] = ext[i]
    f._tabIds[mode] = nextId
    allNames[#allNames + 1] = name
  end

  if PanelTemplates_SetNumTabs then
    PanelTemplates_SetNumTabs(f, nextId)
  end
  if PanelTemplates_UpdateTabs then
    PanelTemplates_UpdateTabs(f)
  end
  if NE.tabs and NE.tabs.SizeAndAnchorTabs then
    NE.tabs.SizeAndAnchorTabs(f, allNames, { startX = 20, startY = 2, parentPoint = "BOTTOMLEFT" })
  end
end

local function buildPanes(f)
  local root = CreateFrame("Frame", nil, f)
  root:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
  root:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.ContentRoot = root

  local function fallbackPane(modeName, errText)
    local p = CreateFrame("Frame", nil, root)
    p:SetAllPoints(root)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER", p, "CENTER", 0, 34)
    t:SetWidth(700)
    t:SetJustifyH("CENTER")
    t:SetText(modeName .. " pane fallback active")
    t:SetTextColor(1, 0.82, 0)

    if errText and errText ~= "" then
      local e = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
      e:SetPoint("TOP", t, "BOTTOM", 0, -12)
      e:SetWidth(700)
      e:SetJustifyH("CENTER")
      e:SetText(tostring(errText))
    end

    return p
  end

  local function safeBuild(builder, modeName)
    if type(builder) ~= "function" then
      return fallbackPane(modeName, "builder missing")
    end
    local ok, pane = pcall(builder, root)
    if ok and pane then
      return pane
    end
    return fallbackPane(modeName, pane)
  end

  f.Panes = {
    Buy = safeBuild(AH.BuildBrowsePane, "Buy"),
    Sell = safeBuild(AH.BuildSellPane, "Sell"),
    Auctions = safeBuild(AH.BuildAuctionsPane, "Auctions"),
  }

  local function enforceSingleVisible(activePane)
    if f._switchingModes then return end
    for _, pane in pairs(f.Panes) do
      if pane and pane ~= activePane then pane:Hide() end
    end
  end

  for key, pane in pairs(f.Panes) do
    if pane then
      pane._neModeKey = key
      pane:HookScript("OnShow", function(self)
        enforceSingleVisible(self)
      end)
    end
  end

  for _, pane in pairs(f.Panes) do
    if pane then pane:Hide() end
  end

  local external = CreateFrame("Frame", nil, root)
  external:SetAllPoints(root)
  external:Hide()
  f.ExternalPane = external

  local hint = external:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hint:SetPoint("CENTER", external, "CENTER", 0, 20)
  hint:SetText("")
  hint:SetTextColor(1, 0.82, 0)
  hint:Hide()
  f.ExternalHint = hint
end

local function createWindow()
  if AH.frame then return AH.frame end

  local f = CreateFrame("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  f:SetSize(800, 538)
  -- Default Blizzard UI panels (AuctionFrame included) open pinned to the LEFT side of the
  -- screen, vertically centered -- not screen-CENTER. Match that instead of centering.
  f:SetPoint("LEFT", UIParent, "LEFT", 16, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()

  AH.frame = f

  buildChrome(f)
  pcall(buildMoneyFrame, f)   -- never let a money-widget failure blank the whole shell
  buildMainTabs(f)
  buildPanes(f)

  -- Clear the Buy tab's search box/results whenever the WHOLE window closes (AUCTION_HOUSE_CLOSED,
  -- ESC, the close button -- all end up calling f:Hide() one way or another), so the next
  -- AUCTION_HOUSE_SHOW starts fresh instead of still displaying last session's search. A plain tab
  -- switch away from Buy does NOT reach here (Buy's own OnHide handles that separately) -- this is
  -- specifically for the top-level frame's own OnHide, which children don't inherit.
  f:HookScript("OnHide", function()
    local buy = f.Panes and f.Panes.Buy
    if buy and buy.ResetSearch then pcall(buy.ResetSearch) end
  end)

  -- Per-window scaling via NE.scale (mode: ui / none / custom; options tab > Window Scaling).
  -- DEFAULTS["auctionhouse"] is "ui" = a plain SetScale(1.0), i.e. exactly what this window did
  -- before it had a setting.
  if NE.scale and NE.scale.Apply then
    if NE.scale.SetFrame then NE.scale.SetFrame("auctionhouse", f) end
    NE.scale.Apply("auctionhouse")
  end

  if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
    NE.FrameUtil.WirePanelSounds(f, SOUNDKIT.AUCTION_WINDOW_OPEN, SOUNDKIT.AUCTION_WINDOW_CLOSE)
  end
  if NE.FrameUtil and NE.FrameUtil.EscClose then
    NE.FrameUtil.EscClose(FRAME_NAME)
  end

  AH.RefreshExternalTabs()
  setMode("Buy")

  return f
end

function AH.Show()
  if not isModuleEnabled() then return end
  local f = createWindow()
  f:Show()
  setMode("Buy")
  local portrait = f.portrait or f.Portrait or f.PortraitTex
  if portrait and SetPortraitTexture then
    pcall(SetPortraitTexture, portrait, "npc")
  end
  suppressLegacyAuctionFrame()
  suppressModernAuctionFrame()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, suppressLegacyAuctionFrame)
    C_Timer.After(0, suppressModernAuctionFrame)
    C_Timer.After(0.05, suppressLegacyAuctionFrame)
    C_Timer.After(0.05, suppressModernAuctionFrame)
  end
  AH.RefreshExternalTabs()
  setMode("Buy")
  -- Belt-and-suspenders: on some load orders Atr_Init (which creates Auctionator's own
  -- AuctionFrameTab4+ Buy/Sell/More tabs) hasn't finished by the time AUCTION_HOUSE_SHOW reaches
  -- us this same frame. Re-scan a couple frames later so the bridge upgrades from the generic
  -- placeholder tab to the real native-mirrored ones without requiring the window to be reopened.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, AH.RefreshExternalTabs)
    C_Timer.After(0.2, AH.RefreshExternalTabs)
  end
end

function AH.Hide()
  if AH.frame then AH.frame:Hide() end
end

local function boot()
  local enabled = isModuleEnabled()
  if enabled then
    prewarmAuctionHouseTextures()
    createWindow()
  end
  if NE.RegisterPanel then
    NE.RegisterPanel({
      id = MODULE,
      title = AUCTION_HOUSE or "Auction House",
      desc = "Modern visual shell for Buy/Sell/Auctions with optional Auctionator tab embedding.",
      frame = AH.frame,
      openFn = AH.Show,
      closeFn = AH.Hide,
      order = 50,
    })
  end
end
AH.Boot = boot

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    boot()
  elseif event == "AUCTION_HOUSE_SHOW" then
    if isModuleEnabled() then AH.Show() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    AH.Hide()
  elseif event == "ADDON_LOADED" and arg1 == "Auctionator" then
    if AH.RefreshExternalTabs then AH.RefreshExternalTabs() end
  elseif event == "ADDON_LOADED" and arg1 == "Blizzard_AuctionUI" then
    -- Auctionator only builds its own AuctionFrameTab4+ (Buy/Sell/More) once Blizzard_AuctionUI
    -- itself finishes loading (Atr_Init runs off this addon's ADDON_LOADED, not Auctionator's own,
    -- which fires much earlier at login before those tabs exist). Re-scan here so the bridge picks
    -- up the native tabs instead of getting stuck on the single non-functional placeholder tab.
    if AH.RefreshExternalTabs then AH.RefreshExternalTabs() end
  end
end)
