-- Stable external API. Internal NE.* names may change without changing this table.
local NE = DragonUI_NewEra
if not NE then return end

local Public = NE.Public or {}
NE.Public = Public
Public.API_VERSION = 1
Public.capabilities = Public.capabilities or {}

local function setCapability(name, available)
    Public.capabilities[name] = available and true or false
end

function Public.GetVersion()
    return Public.API_VERSION
end

function Public.HasCapability(name)
    return Public.capabilities[name] == true
end

function Public.Require(version, capabilities)
    if tonumber(version) and Public.API_VERSION < tonumber(version) then
        return false, "API_VERSION"
    end
    for _, name in ipairs(capabilities or {}) do
        if not Public.HasCapability(name) then return false, name end
    end
    return true
end

Public._SetCapability = setCapability
setCapability("api.versioned", true)

