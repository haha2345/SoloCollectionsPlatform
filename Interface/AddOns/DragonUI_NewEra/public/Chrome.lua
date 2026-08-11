local NE = DragonUI_NewEra
local Public = NE and NE.Public
if not Public then return end

local Chrome = Public.Chrome or {}
Public.Chrome = Chrome

function Chrome:Apply(frame, options)
    if not (NE.panelchrome and NE.panelchrome.Apply) then return false, "panelchrome" end
    NE.panelchrome.Apply(frame, options or {})
    return true
end

function Chrome:SetTitle(frame, title)
    if NE.panelchrome and NE.panelchrome.SetTitle then
        return NE.panelchrome.SetTitle(frame, title)
    end
    return nil
end

function Chrome:PersistWindowPosition(frame, key, defaultPoint, dragHandle)
    if not (NE.FrameUtil and NE.FrameUtil.PersistWindowPosition) then return false, "frameutil" end
    NE.FrameUtil.PersistWindowPosition(frame, key, defaultPoint, dragHandle)
    return true
end

function Chrome:MigrateWindowPosition(key, legacy)
    if not (key and type(legacy) == "table" and legacy.point and NE.db) then return false end
    NE.db.windowPos = NE.db.windowPos or {}
    if NE.db.windowPos[key] then return false end
    NE.db.windowPos[key] = {
        point = legacy.point,
        relPoint = legacy.relPoint or legacy.relativePoint or legacy.point,
        x = tonumber(legacy.x) or 0,
        y = tonumber(legacy.y) or 0,
    }
    return true
end

function Chrome:RestoreWindowPosition(frame, key, defaultPoint)
    if not (NE.FrameUtil and NE.FrameUtil.RestoreWindowPosition) then return false, "frameutil" end
    return NE.FrameUtil.RestoreWindowPosition(frame, key, defaultPoint)
end

function Chrome:ResetWindowPosition(key)
    if not (key and NE.db and NE.db.windowPos) then return false end
    NE.db.windowPos[key] = nil
    return true
end

function Chrome:KeepOnScreen(frame)
    if NE.FrameUtil and NE.FrameUtil.KeepOnScreen then return NE.FrameUtil.KeepOnScreen(frame) end
end

Public._SetCapability("chrome.panel", NE.panelchrome and type(NE.panelchrome.Apply) == "function")
Public._SetCapability("chrome.persist", NE.FrameUtil and type(NE.FrameUtil.PersistWindowPosition) == "function")
Public._SetCapability("chrome.position-migration", NE.FrameUtil and type(NE.FrameUtil.RestoreWindowPosition) == "function")
