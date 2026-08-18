local NE = DragonUI_NewEra
local Public = NE and NE.Public
if not Public then return end

local Theme = Public.Theme or {}
Public.Theme = Theme

local tokens = {
    panelBackground = { 0.035, 0.025, 0.018, 0.96 },
    insetBackground = { 0.018, 0.020, 0.024, 0.92 },
    border = { 0.48, 0.34, 0.16, 0.95 },
    text = { 0.92, 0.84, 0.67, 1.00 },
    mutedText = { 0.64, 0.59, 0.50, 1.00 },
    selected = { 1.00, 0.78, 0.18, 1.00 },
    experimental = { 0.68, 0.38, 0.95, 1.00 },
    pending = { 0.95, 0.66, 0.18, 1.00 },
    applied = { 0.25, 0.88, 0.42, 1.00 },
}

function Theme:GetToken(name)
    return tokens[name]
end

function Theme:GetTexture(name)
    if name == "rock" then return "Interface\\FrameGeneral\\UI-Background-Rock" end
    if name == "white" then return "Interface\\Buttons\\WHITE8X8" end
    return nil
end

function Theme:SetTexture(texture, key, useAtlasSize, ...)
    if NE.tex and NE.tex.Set then return NE.tex.Set(texture, key, useAtlasSize, ...) end
    return false
end

Public._SetCapability("theme.tokens", true)
Public._SetCapability("theme.textures", NE.tex and type(NE.tex.Set) == "function")

