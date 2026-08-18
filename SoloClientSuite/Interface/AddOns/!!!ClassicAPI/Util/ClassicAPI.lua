local _, Private = ...

-- Texture Path
Private.TEXTURE_PATH = "Interface\\AddOns\\!!!ClassicAPI\\Texture\\"

-- Scan Tooltip
local Tooltip = CreateFrame("GameTooltip", "CAPI_ScanTooltip")
Tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
Tooltip:AddFontStrings(Tooltip:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"), Tooltip:CreateFontString("$parentTextRight1", nil, "GameTooltipText"))
Private.Tooltip = Tooltip

-- General Event
Tooltip:SetScript("OnEvent", function(Self, Event)
	-- Do not pre-warm Unit.lua's range-check item here. On 3.3.5a/SoloCam,
	-- the hidden item query can leak ERR_ITEM_NOT_FOUND during login; the
	-- range helper still uses IsItemInRange on demand.
	Private.AsyncCallbackSystemReady()
	Self:UnregisterEvent(Event)
	Self:SetScript("OnEvent", nil)
end)
Tooltip:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Common Functions
function Private.Void()
	-- To the nether!
end

function Private.True()
	return true
end

function Private.False()
	return false
end

function Private.Zero()
	return 0
end

--[[ MISCELLANEOUS ]]

-- [LFD_ERROR_FIX] Workaround long-standing client/server error.
local LFDCooldown = LFDQueueFrameCooldownFrame
if ( LFDCooldown ) then
	LFDCooldown:UnregisterEvent("UNIT_AURA")
	LFDCooldown:UnregisterEvent("PARTY_MEMBERS_CHANGED")
	LFDQueueFrame:HookScript("OnShow", LFDQueueFrameRandomCooldownFrame_Update)
end
