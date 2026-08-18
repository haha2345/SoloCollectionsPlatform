-- DragonUI_NewEra/compat/C_Item.lua
-- Fills the C_Item.* symbols !!!ClassicAPI does NOT define: GetItemSpell, GetItemQualityColor.
--
-- DOWNPORT: Classic 1.15 namespaced item queries under C_Item. !!!ClassicAPI is a
-- HARD dependency and loads first, providing GetItemInfo / GetItemInfoInstant /
-- GetItemIconByID / GetItemCount and the ItemLocation family. It does NOT, however,
-- define C_Item.GetItemSpell or C_Item.GetItemQualityColor — both of which v1 uses
-- (ItemGrid reads GetItemSpell; quality colouring reads GetItemQualityColor). We
-- forward those two to the 3.3.5a globals.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

C_Item = C_Item or {}
local C = C_Item

-- GetItemSpell(item) -> spellName, spellID  (same on 3.3.5; not provided by ClassicAPI).
if not C.GetItemSpell then
    C.GetItemSpell = GetItemSpell
end

-- GetItemQualityColor(quality) -> r, g, b, hex  (same on 3.3.5; not provided by ClassicAPI).
if not C.GetItemQualityColor then
    if type(GetItemQualityColor) == "function" then
        C.GetItemQualityColor = GetItemQualityColor
    else
        -- Fallback from the global ITEM_QUALITY_COLORS table (always present on 3.3.5).
        function C.GetItemQualityColor(quality)
            local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if q then
                return q.r, q.g, q.b, q.hex
            end
            return 1, 1, 1, "|cffffffff"
        end
    end
end

NE.compat.item = true
