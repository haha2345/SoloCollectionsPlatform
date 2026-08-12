-- DragonUI_NewEra/modules/encounterjournal/EncounterItem.lua — one Adventure-Guide loot row.
--
-- DOWNPORT of NewEra/EncounterJournal/EncounterItem.lua + EncounterJournal.xml
-- (NE_EncounterItemTemplate). The 3.3.5a XML schema has no `mixin` attribute, so the XML
-- template is folded into this Lua builder: NE.ej.CreateLootRow(parent) creates the row
-- (bg/icon/iconBorder/name/slot/armorType/dropPct — same keys fillLootRow paints) and wires
-- the retail click/hover behaviour on Era... 3.3.5a APIs:
--   * click  → HandleModifiedItemClick(link) (shift=chat link, ctrl=dress-up; native 3.3.5a)
--   * hover  → item tooltip via SetItemByID (ClassicAPI) or SetHyperlink fallback, plus a
--              cache prime so cold items (unowned raid loot) fill in as the server answers.
--
-- retail source: EncounterItemTemplate, Blizzard_EncounterJournal.xml:1220-1290.

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}

-- GameFontBlack exists on retail/Era; on 3.3.5a it may be absent — the dark parchment color
-- is applied explicitly either way, so the fallback object only supplies face/size.
local BLACK_FONT = _G.GameFontBlack and "GameFontBlack" or "GameFontHighlightSmall"

local function setTooltipItem(tip, id)
  if tip.SetItemByID then
    local ok = pcall(tip.SetItemByID, tip, id)
    if ok then return end
  end
  pcall(tip.SetHyperlink, tip, "item:" .. id)
end

function NE.ej.CreateLootRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetSize(321, 45)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- UI-EJ-LootFrame row plate (BORDER, per the retail template).
  r.bg = r:CreateTexture(nil, "BORDER")
  r.bg:SetSize(321, 45)
  r.bg:SetPoint("LEFT", r, "LEFT", 0, 0)
  if NE.ej.ApplySlice then NE.ej.ApplySlice(r.bg, "UI-EJ-LootFrame") end

  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(42, 42)
  r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -2)

  -- Quality stripe around the icon (tinted + shown in fillLootRow).
  r.iconBorder = r:CreateTexture(nil, "OVERLAY")
  r.iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
  r.iconBorder:SetPoint("TOPLEFT", r.icon, "TOPLEFT", 0, 0)
  r.iconBorder:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 0, 0)
  r.iconBorder:Hide()

  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.name:SetWidth(250)
  r.name:SetJustifyH("LEFT")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 7, -7)

  r.slot = r:CreateFontString(nil, "OVERLAY", BLACK_FONT)
  r.slot:SetJustifyH("LEFT")
  r.slot:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 7, 5)
  r.slot:SetTextColor(0.25, 0.148, 0.02)

  r.armorType = r:CreateFontString(nil, "OVERLAY", BLACK_FONT)
  r.armorType:SetJustifyH("RIGHT")
  r.armorType:SetPoint("RIGHT", r, "RIGHT", -10, -6)
  r.armorType:SetTextColor(0.25, 0.148, 0.02)

  -- drop-chance (top-right) — NOT retail parity; an NE addition (AtlasLoot droprate).
  r.dropPct = r:CreateFontString(nil, "OVERLAY", BLACK_FONT)
  r.dropPct:SetJustifyH("RIGHT")
  r.dropPct:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -7)
  r.dropPct:SetTextColor(0.25, 0.148, 0.02)

  r:SetScript("OnClick", function(self)
    if self.link and HandleModifiedItemClick and HandleModifiedItemClick(self.link) then
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    end
  end)
  r:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    setTooltipItem(GameTooltip, self.itemID)
    GameTooltip:Show()
    if NE.ej.PrimeItem then NE.ej.PrimeItem(self.itemID) end
    NE.ej._hoverLootRow = self
  end)
  r:SetScript("OnLeave", function()
    GameTooltip:Hide()
    NE.ej._hoverLootRow = nil
  end)

  return r
end
