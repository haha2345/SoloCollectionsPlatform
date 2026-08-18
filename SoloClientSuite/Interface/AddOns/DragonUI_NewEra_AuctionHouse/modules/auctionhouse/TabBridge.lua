-- DragonUI_NewEra/modules/auctionhouse/TabBridge.lua
-- External tab embedding contract. Auctionator integration is additive and optional.

local NE = DragonUI_NewEra
if not NE then return end

NE.ah = NE.ah or {}
local AH = NE.ah
AH.bridge = AH.bridge or {}

local function isAddonLoaded(name)
  if NE.IsAddOnLoaded then return NE.IsAddOnLoaded(name) end
  if _G.IsAddOnLoaded then
    local ok, loaded = pcall(_G.IsAddOnLoaded, name)
    return ok and loaded and true or false
  end
  return false
end

AH.bridge.providers = AH.bridge.providers or {}

function AH.bridge.RegisterProvider(id, provider)
  if not id or type(provider) ~= "table" then return end
  AH.bridge.providers[id] = provider
  if AH.RefreshExternalTabs then
    AH.RefreshExternalTabs()
  end
end

function AH.bridge.GetExternalTabs(frame)
  local tabs = {}
  for id, provider in pairs(AH.bridge.providers) do
    local enabled = true
    if type(provider.isEnabled) == "function" then
      local ok, v = pcall(provider.isEnabled, frame)
      enabled = ok and v and true or false
    end
    if enabled and type(provider.getTabs) == "function" then
      local ok, out = pcall(provider.getTabs, frame)
      if ok and type(out) == "table" then
        for i = 1, #out do
          local t = out[i]
          if type(t) == "table" and t.key and t.text and type(t.onSelect) == "function" then
            t.providerId = id
            tabs[#tabs + 1] = t
          end
        end
      end
    end
  end
  -- Sort by KEY, not label: native-mirrored keys are "AuctionatorNative4/5/6", so this preserves
  -- Auctionator's own tab order (Buy, Sell, More...) instead of alphabetizing the labels
  -- (Buy, More..., Sell).
  table.sort(tabs, function(a, b)
    return tostring(a.key) < tostring(b.key)
  end)
  return tabs
end

-- Built-in Auctionator provider: appears only when Auctionator is loaded.
-- This does not reimplement Auctionator logic; it delegates into Auctionator/legacy tabs when possible.
AH.bridge.RegisterProvider("Auctionator", {
  isEnabled = function()
    return isAddonLoaded("Auctionator")
  end,

  getTabs = function(frame)
    local list = {}

    -- If Auctionator added extra native AuctionFrame tabs (>3), mirror each as an embedded tab.
    local idx = 4
    while _G["AuctionFrameTab" .. idx] do
      local src = _G["AuctionFrameTab" .. idx]
      local textObj = _G[src:GetName() .. "Text"]
      local label = (textObj and textObj.GetText and textObj:GetText()) or (src.GetText and src:GetText()) or ("Tab " .. idx)
      list[#list + 1] = {
        key = "AuctionatorNative" .. idx,
        text = label,
        onSelect = function(ctx)
          local NE = _G.DragonUI_NewEra
          local ah = NE and NE.ah
          local atr = ah and ah.atr
          if atr and atr.IsEmbedded and atr.IsEmbedded() then
            -- Embedded (AuctionatorEmbed.lua): Atr_Main_Panel lives inside this shell's
            -- ExternalPane, so click the native tab to drive Auctionator's own pane logic and
            -- KEEP the legacy AuctionFrame cloaked and the shell up. When this select came from
            -- the Atr_AuctionFrameTab_OnClick sync hook (atr._syncing), Auctionator has already
            -- switched its pane -- clicking again would bounce back through the hook.
            if not atr._syncing then
              atr._clicking = true
              if src and src.Click then pcall(src.Click, src) end
              atr._clicking = nil
            end
            if ah.SuppressLegacyAuctionFrame then ah.SuppressLegacyAuctionFrame() end
            return
          end
          -- Fallback (embedding unavailable): reverse the alpha/mouse cloak so AuctionFrame and
          -- Atr_Main_Panel are visible, then dismiss the NE shell so Auctionator's own UI is
          -- unobstructed.
          if ah then
            if ah.UncloakLegacyAuctionFrame then ah.UncloakLegacyAuctionFrame() end
            if ah.Hide then ah.Hide() end
          end
          if src and src.Click then pcall(src.Click, src) end
        end,
      }
      idx = idx + 1
    end

    if #list == 0 then
      list[#list + 1] = {
        key = "Auctionator",
        text = "Auctionator",
        onSelect = function(ctx)
          local NE = _G.DragonUI_NewEra
          local ah = NE and NE.ah
          local atr = ah and ah.atr
          -- Embedded (AuctionatorEmbed.lua): keep the shell up and the legacy frame cloaked;
          -- otherwise fall back to uncloak-and-dismiss so Auctionator's own UI is unobstructed.
          local embedded = atr and atr.IsEmbedded and atr.IsEmbedded()
          if not embedded and ah then
            if ah.UncloakLegacyAuctionFrame then ah.UncloakLegacyAuctionFrame() end
            if ah.Hide then ah.Hide() end
          end
          -- Auctionator's BUY_TAB/SELL_TAB/MORE_TAB constants are LOCAL to its own file (never
          -- published as globals), so _G.BUY_TAB is always nil -- this call silently no-op'd
          -- forever. Its addon source hardcodes BUY_TAB = 3; Atr_SelectPane just needs that
          -- numeric value to find the tab it tagged with matching .auctionatorTab at creation.
          if type(_G.Atr_SelectPane) == "function" and not (embedded and atr._syncing) then
            if atr then atr._clicking = true end
            pcall(_G.Atr_SelectPane, 3)
            if atr then atr._clicking = nil end
          end
          if embedded and ah.SuppressLegacyAuctionFrame then ah.SuppressLegacyAuctionFrame() end
        end,
      }
    end

    return list
  end,
})
