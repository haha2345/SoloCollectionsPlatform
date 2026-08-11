local Type = type
local UseEquipmentSet = UseEquipmentSet
local SaveEquipmentSet = SaveEquipmentSet
local GetNumMacroIcons = GetNumMacroIcons
local GetMacroIconInfo = GetMacroIconInfo
local DeleteEquipmentSet = DeleteEquipmentSet
local PickupEquipmentSet = PickupEquipmentSet
local GetInventoryItemID = GetInventoryItemID
local GetEquipmentSetInfo = GetEquipmentSetInfo
local GetEquipmentSetItemIDs = GetEquipmentSetItemIDs
local GetEquipmentSetLocations = GetEquipmentSetLocations
local GetEquipmentSetInfoByName = GetEquipmentSetInfoByName
local EquipmentManager_UnpackLocation = EquipmentManager_UnpackLocation

local C_EquipmentSet = C_EquipmentSet or {}

local UNAVAILABLE_LOCATION = -1
local EMPTY_LOCATION = 0
local IGNORED_LOCATION = 1

local function GetIconIndexFromTexture(Icon)
	if ( Icon ) then
		local TargetName = Icon:lower()

		for Index = 1, GetNumMacroIcons() do
			local TexturePath = GetMacroIconInfo(Index)
			if ( TexturePath and TexturePath:lower():find(TargetName, 1, true) ) then
				return Index
			end
		end
	end

	return 1
end

function C_EquipmentSet.GetEquipmentSetIDs()
	local SetIDs = {}
	for Index = 1, C_EquipmentSet.GetNumEquipmentSets() do
		SetIDs[Index] = Index
	end
	return SetIDs
end

function C_EquipmentSet.GetEquipmentSetInfo(SetID)
	if ( Type(SetID) ~= "number" ) then return end

	local Name, Icon = GetEquipmentSetInfo(SetID)
	if ( not Name ) then return end

	local Locations = GetEquipmentSetLocations(Name)
	if ( not Locations ) then
		return Name, Icon, SetID, false, 0, 0, 0, 0, 0
	end

	local NumItems = 0
	local NumEquipped = 0
	local NumInInventory = 0
	local NumLost = 0
	local NumIgnored = 0
	local IsSetFullyMatched = true

	for EquipSlot = 1, 19 do
		local Location = Locations[EquipSlot]

		if ( Location == IGNORED_LOCATION ) then
			NumIgnored = NumIgnored + 1
		elseif ( Location == UNAVAILABLE_LOCATION ) then
			NumItems = NumItems + 1
			NumLost = NumLost + 1
			IsSetFullyMatched = false
		elseif ( Location == EMPTY_LOCATION or not Location ) then
			local CurrentEquippedID = GetInventoryItemID("player", EquipSlot)
			if ( CurrentEquippedID ) then
				IsSetFullyMatched = false
			end
		else
			NumItems = NumItems + 1

			local PlayerHas, BankHas, BagsHas, Slot, Bag = EquipmentManager_UnpackLocation(Location)

			if ( PlayerHas ) then
				if ( not BankHas and not BagsHas and Slot == EquipSlot ) then
					NumEquipped = NumEquipped + 1
				else
					IsSetFullyMatched = false
					NumInInventory = NumInInventory + 1
				end
			else
				IsSetFullyMatched = false
				NumLost = NumLost + 1
			end
		end
	end

	local IsEquipped = IsSetFullyMatched

	return Name, Icon, SetID, IsEquipped, NumItems, NumEquipped, NumInInventory, NumLost, NumIgnored
end

function C_EquipmentSet.GetEquipmentSetID(SetName)
	for Index = 1, C_EquipmentSet.GetNumEquipmentSets() do
		if ( GetEquipmentSetInfo(Index) == SetName ) then
			return Index
		end
	end
end

function C_EquipmentSet.SaveEquipmentSet(SetID, Icon)
	local Name, CurrentIcon

	if ( Type(SetID) == "number" ) then
		Name, CurrentIcon = GetEquipmentSetInfo(SetID)
	elseif ( Type(SetID) == "string" ) then
		Name = SetID
		CurrentIcon = GetEquipmentSetInfoByName(SetID)
	end

	SaveEquipmentSet(Name, GetIconIndexFromTexture(Icon or CurrentIcon))
end

function C_EquipmentSet.DeleteEquipmentSet(SetID)
	if ( Type(SetID) ~= "number" ) then return end

	local Name = GetEquipmentSetInfo(SetID)
	if ( Name ) then
		DeleteEquipmentSet(Name)
	end
end

function C_EquipmentSet.UseEquipmentSet(SetID)
	if ( Type(SetID) ~= "number" ) then return end

	local Name = GetEquipmentSetInfo(SetID)
	if ( Name ) then
		return UseEquipmentSet(Name)
	end
end

function C_EquipmentSet.ModifyEquipmentSet(SetID, NewName, NewIcon)
	if ( Type(SetID) ~= "number" ) then return end

	local OldName, CurrentIcon = GetEquipmentSetInfo(SetID)
	if ( not OldName ) then return end

	local Locations = GetEquipmentSetLocations(OldName)
	if ( Locations ) then
		for SlotID = 1, 19 do
			if ( Locations[SlotID] == IGNORED_LOCATION ) then
				C_EquipmentSet.IgnoreSlotForSave(SlotID)
			else
				C_EquipmentSet.UnignoreSlotForSave(SlotID)
			end
		end
	end

	local TargetName = NewName or OldName

	SaveEquipmentSet(TargetName, GetIconIndexFromTexture(NewIcon or CurrentIcon))

	if ( TargetName ~= OldName ) then
		DeleteEquipmentSet(OldName)
	end
end

function C_EquipmentSet.GetIgnoredSlots(SetID)
	if ( Type(SetID) ~= "number" ) then return end

	local Name = GetEquipmentSetInfo(SetID)
	if ( not Name ) then return end

	local Locations = GetEquipmentSetLocations(Name)
	if ( not Locations ) then return end

	local IgnoredSlots = {}
	for SlotID = 1, 19 do
		local Location = Locations[SlotID]
		if ( Location == IGNORED_LOCATION ) then
			IgnoredSlots[SlotID] = true
		end
	end

	return IgnoredSlots
end

function C_EquipmentSet.GetItemIDs(SetID)
	if ( Type(SetID) ~= "number" ) then return end

	local Name = GetEquipmentSetInfo(SetID)
	if ( Name ) then
		return GetEquipmentSetItemIDs(Name)
	end
end

function C_EquipmentSet.GetItemLocations(SetID)
	if ( Type(SetID) ~= "number" ) then return end

	local Name = GetEquipmentSetInfo(SetID)
	if ( Name ) then
		return GetEquipmentSetLocations(Name)
	end
end

C_EquipmentSet.ClearIgnoredSlotsForSave = EquipmentManagerClearIgnoredSlotsForSave
C_EquipmentSet.UnignoreSlotForSave = EquipmentManagerUnignoreSlotForSave
C_EquipmentSet.IgnoreSlotForSave = EquipmentManagerIgnoreSlotForSave
C_EquipmentSet.CreateEquipmentSet = C_EquipmentSet.SaveEquipmentSet
C_EquipmentSet.GetNumEquipmentSets = GetNumEquipmentSets
C_EquipmentSet.PickupEquipmentSet = PickupEquipmentSet

-- Global
_G.C_EquipmentSet = C_EquipmentSet