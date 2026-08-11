-- DragonUI_NewEra/compat/C_Map.lua
-- Best-effort fillers for the handful of C_Map.* symbols !!!ClassicAPI does NOT define.
--
-- DOWNPORT: Classic 1.15's C_Map is a uiMapID-based world-map model that 3.3.5a
-- simply does not have (3.3.5 uses SetMapToCurrentZone / GetCurrentMapAreaID /
-- GetPlayerMapPosition with a totally different id space). The v1 modules
-- (CharacterPanel, Spellbook, Talents, QuestFrame, MerchantFrame, MailFrame) do NOT
-- call C_Map — it's referenced only by NewEra's WorldMap/Minimap/Quest map providers
-- which are out of scope for v1. CONTRACTS §1 still asks for a best-effort shim so
-- anything that incidentally probes C_Map gets safe nils rather than a nil-index
-- error.
--
-- !!!ClassicAPI is a HARD dependency and loads first; it already provides
-- C_Map.GetBestMapForUnit / C_Map.IsWorldMap / C_Map.WorldMap, so we DON'T touch
-- those. It does NOT provide GetMapInfo or GetPlayerMapPosition — we fill those two
-- as recorded stubs (and only if still missing).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local compat = NE.compat

C_Map = C_Map or {}
local C = C_Map

-- GetMapInfo(uiMapID) -> table { mapID, name, mapType, parentMapID }. 3.3.5 cannot
-- map a retail uiMapID; return nil. Recorded. (ClassicAPI does not provide this.)
if not C.GetMapInfo then
    function C.GetMapInfo(uiMapID)
        return nil
    end
    compat.RecordStub("C_Map.GetMapInfo",
        "no uiMapID->map metadata on 3.3.5; returns nil")
end

-- GetPlayerMapPosition(uiMapID, unit) -> position table with :GetXY(). 3.3.5's
-- GetPlayerMapPosition returns positional x, y for the CURRENT map. We wrap it in a
-- minimal position object exposing GetXY() to match the retail return shape. The
-- uiMapID argument is ignored (we use whatever map is currently selected).
-- (ClassicAPI does not provide this.)
if not C.GetPlayerMapPosition then
    local posMethods = {}
    posMethods.__index = posMethods
    function posMethods:GetXY()
        return self.x, self.y
    end
    function C.GetPlayerMapPosition(uiMapID, unit)
        unit = unit or "player"
        if type(GetPlayerMapPosition) ~= "function" then return nil end
        local x, y = GetPlayerMapPosition(unit)
        if not x or (x == 0 and y == 0) then return nil end
        return setmetatable({ x = x, y = y }, posMethods)
    end
    compat.RecordStub("C_Map.GetPlayerMapPosition",
        "wraps legacy GetPlayerMapPosition; ignores uiMapID arg, uses current map")
end

NE.compat.map = true
