-- DragonUI_NewEra/modules/auctionhouse/Assets.lua
-- Visual-shell atlas registration for the modern Auction House window.

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal and NE.tex.RegisterAtlases) then return end

NE.ah = NE.ah or {}

local AP = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\AuctionHouse\\"
local CP = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\"

NE.tex.RegisterLocal(3054898, AP .. "3054898-auctionhouse-backgrounds.blp")
NE.tex.RegisterLocal(3046538, AP .. "3046538-auctionhouse-chrome.blp")
NE.tex.RegisterLocal(2922105, CP .. "2922105-common-iconmask.blp")

NE.tex.RegisterAtlases({
  ["auctionhouse-background-categories"] = { file=3054898, left=0.845215, right=0.912598, top=0.390625, bottom=0.813477, width=138, height=433 },
  ["auctionhouse-background-index"]      = { file=3054898, left=0.180664, right=0.471191, top=0.390625, bottom=0.793945, width=595, height=413 },
  ["auctionhouse-background-sell-left"]  = { file=3054898, left=0.000488, right=0.174805, top=0.389648, bottom=0.816406, width=357, height=437 },
  ["auctionhouse-background-sell-right"] = { file=3054898, left=0.540527, right=0.735352, top=0.390625, bottom=0.798828, width=399, height=418 },
  ["auctionhouse-background-summarylist"] = { file=3054898, left=0.472168, right=0.539551, top=0.390625, bottom=0.813477, width=138, height=433 },
  ["auctionhouse-background-buy-noncommodities-header"] = { file=3054898, left=0.180664, right=0.481934, top=0.309570, bottom=0.388672, width=617, height=81 },
  ["auctionhouse-background-buy-noncommodities-market"] = { file=3054898, left=0.472168, right=0.762695, top=0.000977, bottom=0.271484, width=595, height=277 },

  ["auctionhouse-itemicon-border-white"] = { file=3046538, left=0.135742, right=0.268555, top=0.698242, bottom=0.831055, width=136, height=136 },

  -- Sell-form chrome (UVs transcribed from NewEra Generated/AtlasData.lua; the shipped chrome BLP
  -- is byte-identical to the reference's, verified by hash).
  ["auctionhouse-itemheaderframe"]      = { file=3046538, left=0.000977, right=0.668945, top=0.000977, bottom=0.141602, width=342, height=72 },
  ["auctionhouse-itemicon-empty"]       = { file=3046538, left=0.135742, right=0.233398, top=0.833008, bottom=0.930664, width=100, height=100 },
  ["auctionhouse-selltab-left"]         = { file=3046538, left=0.987305, right=0.996094, top=0.000977, bottom=0.023438, width=9,  height=23 },
  ["auctionhouse-selltab-middle"]       = { file=3046538, left=0.000977, right=0.093750, top=0.967773, bottom=0.990234, width=95, height=23 },
  ["auctionhouse-selltab-right"]        = { file=3046538, left=0.270508, right=0.279297, top=0.428711, bottom=0.451172, width=9,  height=23 },
  ["auctionhouse-ui-inputfield-left"]   = { file=3046538, left=0.235352, right=0.250977, top=0.833008, bottom=0.897461, width=8,   height=33 },
  ["auctionhouse-ui-inputfield-middle"] = { file=3046538, left=0.286133, right=0.633789, top=0.143555, bottom=0.208008, width=178, height=33 },
  ["auctionhouse-ui-inputfield-right"]  = { file=3046538, left=0.252930, right=0.268555, top=0.833008, bottom=0.897461, width=8,   height=33 },

  ["auctionhouse-icon-coin-copper"] = { file=3046538, left=0.940430, right=0.959961, top=0.122070, bottom=0.141602, width=20, height=20 },
  ["auctionhouse-icon-coin-silver"] = { file=3046538, left=0.931641, right=0.951172, top=0.143555, bottom=0.163086, width=20, height=20 },
  ["auctionhouse-icon-coin-gold"]   = { file=3046538, left=0.961914, right=0.981445, top=0.122070, bottom=0.141602, width=20, height=20 },

  ["auctionhouse-nav-button"]                     = { file=3046538, left=0.635742, right=0.901367, top=0.143555, bottom=0.206055, width=272, height=64 },
  ["auctionhouse-nav-button-select"]              = { file=3046538, left=0.286133, right=0.543945, top=0.274414, bottom=0.315430, width=264, height=42 },
  ["auctionhouse-nav-button-highlight"]           = { file=3046538, left=0.547852, right=0.805664, top=0.209961, bottom=0.250977, width=264, height=42 },
  ["auctionhouse-nav-button-secondary"]           = { file=3046538, left=0.286133, right=0.545898, top=0.209961, bottom=0.272461, width=266, height=64 },
  ["auctionhouse-nav-button-secondary-select"]    = { file=3046538, left=0.286133, right=0.524414, top=0.317383, bottom=0.358398, width=244, height=42 },
  ["auctionhouse-nav-button-secondary-highlight"] = { file=3046538, left=0.545898, right=0.784180, top=0.274414, bottom=0.315430, width=244, height=42 },
  ["auctionhouse-nav-button-tertiary-filterline"] = { file=3046538, left=0.270508, right=0.275391, top=0.468750, bottom=0.479492, width=5, height=11 },
  ["auctionhouse-ui-row-select"]                  = { file=3046538, left=0.807617, right=0.920898, top=0.209961, bottom=0.227539, width=116, height=18 },
  ["auctionhouse-ui-row-highlight"]               = { file=3046538, left=0.547852, right=0.661133, top=0.252930, bottom=0.270508, width=116, height=18 },
})
