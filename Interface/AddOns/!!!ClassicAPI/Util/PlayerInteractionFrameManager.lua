local _, Private = ...

local _G = _G
local Type = type
local Pairs = pairs
local ShowUIPanel = ShowUIPanel
local HideUIPanel = HideUIPanel

local InteractionManagerFrameInfo

local function GetInteractionManagerFrameInfo()
	if ( not InteractionManagerFrameInfo ) then
		local Interaction = Enum.PlayerInteractionType

		--[[
			Frame     = [REQUIRED][STRING]   - The global string name of the frame intended to open.
			ShowFunc  = [OPTIONAL][FUNCTION] - Function or global string name called on open. Defaults to ShowUIPanel.
			HideFunc  = [OPTIONAL][FUNCTION] - Function or global string name called on close. Defaults to HideUIPanel.
			LoadFunc  = [OPTIONAL][FUNCTION] - Required only if the frame must be loaded on demand before use.
			ShowEvent = [OPTIONAL][STRING]   - Client event string that triggers the frame to show.
			HideEvent = [OPTIONAL][STRING]   - Client event string that triggers the frame to hide.
		]]

		InteractionManagerFrameInfo = {
			[Interaction.Merchant] = {
				Frame = "MerchantFrame",
				ShowFunc = "MerchantFrame_MerchantShow",
				HideFunc = "MerchantFrame_MerchantClosed",
				ShowEvent = "MERCHANT_SHOW",
				HideEvent = "MERCHANT_CLOSED"
			},
			[Interaction.Banker] = {
				Frame = "BankFrame",
				ShowFunc = "BankFrame_Open",
				ShowEvent = "BANKFRAME_OPENED",
				HideEvent = "BANKFRAME_CLOSED"
			},
			[Interaction.Trainer] = {
				Frame = "ClassTrainerFrame",
				ShowFunc = "ClassTrainerFrame_Show",
				HideFunc = "ClassTrainerFrame_Hide",
				LoadFunc = ClassTrainerFrame_LoadUI,
				ShowEvent = "TRAINER_SHOW",
				HideEvent = "TRAINER_CLOSED"
			},
			[Interaction.GuildBanker] = {
				Frame = "GuildBankFrame",
				LoadFunc = GuildBankFrame_LoadUI,
				ShowEvent = "GUILDBANKFRAME_OPENED",
				HideEvent = "GUILDBANKFRAME_CLOSED"
			},
			[Interaction.Registrar] = {
				Frame = "GuildRegistrarFrame"
			},
			[Interaction.GuildTabardVendor] = {
				Frame = "TabardFrame",
				ShowFunc = "TabardFrame_Open"
			},
			[Interaction.MailInfo] = {
				Frame = "MailFrame",
				ShowFunc = "MailFrame_Show",
				HideFunc = "MailFrame_Hide",
				ShowEvent = "MAIL_SHOW",
				HideEvent = "MAIL_CLOSED"
			},
			[Interaction.Auctioneer] = {
				Frame = "AuctionHouseFrame",
				ShowEvent = "AUCTION_HOUSE_SHOW",
				HideEvent = "AUCTION_HOUSE_CLOSED"
			}
		}
	end

	return InteractionManagerFrameInfo
end

local PlayerInteractionFrameManagerMixin = PlayerInteractionFrameManagerMixin or {}

function PlayerInteractionFrameManagerMixin:ShowFrame(InteractionType)
	local FrameInfo = GetInteractionManagerFrameInfo()[InteractionType]
	if ( not FrameInfo ) then
		return
	end

	local FrameName = FrameInfo.Frame
	if ( FrameInfo.LoadFunc and not _G[FrameName] ) then
		FrameInfo.LoadFunc()
	end

	local ShowFunc = FrameInfo.ShowFunc
	if ( ShowFunc ) then
		if ( Type(ShowFunc) == "string" ) then
			ShowFunc = _G[ShowFunc]
			FrameInfo.ShowFunc = ShowFunc
		end
		if ( ShowFunc ) then
			ShowFunc()
		end
	else
		ShowUIPanel(_G[FrameName], FrameInfo.ForceShow)
	end
end

function PlayerInteractionFrameManagerMixin:HideFrame(InteractionType)
	local FrameInfo = GetInteractionManagerFrameInfo()[InteractionType]
	if ( not FrameInfo ) then
		return
	end

	local Frame = _G[FrameInfo.Frame]
	if ( not Frame ) then
		return
	end

	local HideFunc = FrameInfo.HideFunc
	if ( HideFunc ) then
		if ( Type(HideFunc) == "string" ) then
			HideFunc = _G[HideFunc]
			FrameInfo.HideFunc = HideFunc
		end
		if ( HideFunc ) then
			HideFunc()
		end
	else
		HideUIPanel(Frame)
	end
end

function PlayerInteractionFrameManagerMixin:OnLoad()
	self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
end

function PlayerInteractionFrameManagerMixin:OnEvent(Event, InteractionType)
	if ( Event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" ) then
		self:ShowFrame(InteractionType)
	elseif ( Event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" ) then
		self:HideFrame(InteractionType)
	end
end

-- [[ EventHandler: PLAYER_INTERACTION_MANAGER_FRAME_X ]]

local EventHandler = Private.EventHandler
local EventHandler_Fire = EventHandler.Fire
local EventHandler_Define = EventHandler.Define

local PlayerInteractionFrameManager = PlayerInteractionFrameManager or CreateFrame("Frame")
PlayerInteractionFrameManager.ShowFrame = PlayerInteractionFrameManagerMixin.ShowFrame
PlayerInteractionFrameManager.HideFrame = PlayerInteractionFrameManagerMixin.HideFrame

PlayerInteractionFrameManager:SetScript("OnEvent", function(Self, Event)
	local FrameInfoTable = GetInteractionManagerFrameInfo()

	for Enum, Meta in Pairs(FrameInfoTable) do
		if ( Meta.ShowEvent == Event ) then
			EventHandler_Fire(nil, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum)
			return
		elseif ( Meta.HideEvent == Event ) then
			EventHandler_Fire(nil, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum)
			return
		end
	end
end)

local function PLAYER_INTERACTION_MANAGER_FRAME_EH(Trigger, Event)
	local IsShow = (Event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	local EventField = IsShow and "ShowEvent" or "HideEvent"
	local FrameInfoTable = GetInteractionManagerFrameInfo()

	for Enum, Meta in Pairs(FrameInfoTable) do
		local SubEvent = Meta[EventField]
		if ( SubEvent ) then
			if ( Trigger == "OnRegister" ) then
				PlayerInteractionFrameManager:RegisterEvent(SubEvent)
			else
				PlayerInteractionFrameManager:UnregisterEvent(SubEvent)
			end
		end
	end
end

EventHandler_Define("Event", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
EventHandler_Define("Event", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
EventHandler_Define("OnRegister", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", PLAYER_INTERACTION_MANAGER_FRAME_EH)
EventHandler_Define("OnUnregister", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", PLAYER_INTERACTION_MANAGER_FRAME_EH)
EventHandler_Define("OnRegister", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", PLAYER_INTERACTION_MANAGER_FRAME_EH)
EventHandler_Define("OnUnregister", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", PLAYER_INTERACTION_MANAGER_FRAME_EH)

-- Global
_G.PlayerInteractionFrameManagerMixin = PlayerInteractionFrameManagerMixin
_G.PlayerInteractionFrameManager = PlayerInteractionFrameManager