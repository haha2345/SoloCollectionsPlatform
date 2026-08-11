DragonUI_NewEra = DragonUI_NewEra or {}
local NE = DragonUI_NewEra

function NE:GetLocale()
    local Ace = LibStub and LibStub("AceLocale-3.0", true)
    return Ace and Ace:GetLocale("DragonUI_NewEra", true)
end