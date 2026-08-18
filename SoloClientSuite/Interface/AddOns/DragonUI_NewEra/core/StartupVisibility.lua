-- Keep modal NewEra panels closed during the one-time login boot sequence.
-- Module constructors still run so hooks and data are ready; only accidental
-- visibility caused by construction/reparenting is suppressed.
local NE = DragonUI_NewEra

local PANEL_GLOBALS = {
  "DragonUI_NewEra_Character",
  "NE_CollectionsFrame",
  "NE_SpellBookFrame",
  "NE_TalentFrame",
  "NE_ProfessionsCraftingFrame",
  "NE_AuctionHouseFrame",
  "NE_GuildFrame",
  "NE_FriendsFrame",
  "NE_GroupFinderFrame",
  "NE_EncounterJournal",
  "NE_CombinedBagFrame",
  "NE_CDMEditorPanel",
  "NE_CooldownViewerSettings",
}

local function closeStartupPanels()
  for _, name in ipairs(PANEL_GLOBALS) do
    local frame = _G[name]
    if frame and frame.Hide then frame:Hide() end
  end
  if CloseDropDownMenus then pcall(CloseDropDownMenus) end
end

local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_LOGIN")
guard:RegisterEvent("PLAYER_ENTERING_WORLD")
guard:SetScript("OnEvent", function(self, event)
  closeStartupPanels()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, closeStartupPanels)
    C_Timer.After(0.10, closeStartupPanels)
    C_Timer.After(0.50, closeStartupPanels)
  end
  if event == "PLAYER_ENTERING_WORLD" then
    self:UnregisterAllEvents()
  end
end)

NE.CloseStartupPanels = closeStartupPanels
