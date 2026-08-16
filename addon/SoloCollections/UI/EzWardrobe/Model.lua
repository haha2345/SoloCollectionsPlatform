local SC = SoloCollections

SC.EzWardrobe = SC.EzWardrobe or {}
SC.EzWardrobe.Model = SC.EzWardrobe.Model or {}

local Model = SC.EzWardrobe.Model
local NativePreview = SC.NativePreview
local ItemQuery = SC.TransmorpherItemQuery
local PreviewSetup = SC.TransmorpherPreviewSetup

local TYPE_PLAYER = "player"
local TYPE_MAIN = "main"
local TYPE_OFF = "off"
local TYPE_RANGED = "ranged"
local VALID_TYPES = {
    player = true,
    main = true,
    off = true,
    ranged = true,
}
local TYPE_SCALE = {
    player = 1,
    main = 1,
    off = 1,
    ranged = 1,
}
local ARMOR_SLOT_NAME = {
    HEAD = "Head",
    SHOULDER = "Shoulder",
    BACK = "Back",
    CHEST = "Chest",
    WRIST = "Wrist",
    HANDS = "Hands",
    WAIST = "Waist",
    LEGS = "Legs",
    FEET = "Feet",
}
local WEAPON_SLOT_NAME = {
    [TYPE_MAIN] = "Main Hand",
    [TYPE_OFF] = "Off-hand",
    [TYPE_RANGED] = "Ranged",
}
-- Transmorpher sentinel carrier values are Lua equipment slots. SoloCam v11
-- translates them to the zero-based C model slot (or stock auto slot).
local EQUIPMENT_SLOT_ID = {
    ["Main Hand"] = 16,
    ["Off-hand"] = 17,
    ["Ranged"] = 18,
}
local RANGED_WEAPON_TYPES = {
    BOW = true,
    CROSSBOW = true,
    GUN = true,
    WAND = true,
    THROWN = true,
}
local OFFHAND_WEAPON_TYPES = {
    SHIELD = true,
    HOLDABLE = true,
    HELD_IN_OFFHAND = true,
}
local WEAPON_SUBCLASS = {
    ONE_HAND_AXE = "Axe",
    TWO_HAND_AXE = "2H Axe",
    ONE_HAND_MACE = "Mace",
    TWO_HAND_MACE = "2H Mace",
    ONE_HAND_SWORD = "Sword",
    TWO_HAND_SWORD = "2H Sword",
    WAR_GLAIVE = "Sword",
    DAGGER = "Dagger",
    FIST_WEAPON = "Fist",
    POLEARM = "Polearm",
    STAFF = "Staff",
    SHIELD = "Shield",
    HOLDABLE = "Held in Off-hand",
    HELD_IN_OFFHAND = "Held in Off-hand",
    BOW = "Bow",
    CROSSBOW = "Crossbow",
    GUN = "Gun",
    WAND = "Wand",
    THROWN = "Thrown",
    -- Transmorpher has no fishing-pole entry. Its Staff camera is the
    -- equivalent long two-handed setup and keeps this WotLK-only category on
    -- the same player-model rendering path.
    FISHING_POLE = "Staff",
}
local LOCALIZED_SUBCLASS = {
    ["Axes"] = "Axe",
    ["One-Handed Axes"] = "Axe",
    ["Two-Handed Axes"] = "Axe",
    ["Maces"] = "Mace",
    ["One-Handed Maces"] = "Mace",
    ["Two-Handed Maces"] = "Mace",
    ["Swords"] = "Sword",
    ["One-Handed Swords"] = "Sword",
    ["Two-Handed Swords"] = "Sword",
    ["Daggers"] = "Dagger",
    ["Fist Weapons"] = "Fist",
    ["Polearms"] = "Polearm",
    ["Staves"] = "Staff",
    ["Shields"] = "Shield",
    ["Bows"] = "Bow",
    ["Crossbows"] = "Crossbow",
    ["Guns"] = "Gun",
    ["Wands"] = "Wand",
    ["Thrown"] = "Thrown",
    ["Fishing Poles"] = "Staff",
    ["斧"] = "Axe",
    ["单手斧"] = "Axe",
    ["双手斧"] = "Axe",
    ["锤"] = "Mace",
    ["单手锤"] = "Mace",
    ["双手锤"] = "Mace",
    ["剑"] = "Sword",
    ["单手剑"] = "Sword",
    ["双手剑"] = "Sword",
    ["匕首"] = "Dagger",
    ["拳套"] = "Fist",
    ["长柄武器"] = "Polearm",
    ["法杖"] = "Staff",
    ["盾牌"] = "Shield",
    ["弓"] = "Bow",
    ["弩"] = "Crossbow",
    ["枪械"] = "Gun",
    ["魔杖"] = "Wand",
    ["投掷武器"] = "Thrown",
    ["鱼竿"] = "Staff",
}

Model.TYPE_PLAYER = TYPE_PLAYER
Model.TYPE_MAIN = TYPE_MAIN
Model.TYPE_OFF = TYPE_OFF
Model.TYPE_RANGED = TYPE_RANGED
Model.TransmogModelMixin = Model.TransmogModelMixin or {}
Model.WardrobeItemsModelMixin = Model.WardrobeItemsModelMixin or {}
Model.lifecycles = Model.lifecycles or setmetatable({}, { __mode = "k" })

local TransmogModelMixin = Model.TransmogModelMixin
local WardrobeItemsModelMixin = Model.WardrobeItemsModelMixin
local itemRenderQueue = {}
local itemRenderDriver = CreateFrame("Frame")

local function safeCall(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    local arguments = { ... }
    return pcall(function() object[method](object, unpack(arguments)) end)
end

local function recordKey(record)
    if not record then return nil end
    return table.concat({
        tostring(record.collectionId or record.id or ""),
        tostring(record.itemId or ""),
        tostring(record.slot or ""),
        tostring(record.weaponType or record.weaponCategory or ""),
    }, ":")
end

local function queueItemRender(lifecycle, record, expectedGeneration)
    lifecycle.pendingItemRender = {
        generation = expectedGeneration,
        key = recordKey(record),
    }
    itemRenderQueue[#itemRenderQueue + 1] = {
        lifecycle = lifecycle,
        generation = expectedGeneration,
        key = recordKey(record),
    }
    if not itemRenderDriver:GetScript("OnUpdate") then
        itemRenderDriver:SetScript("OnUpdate", function(self)
            while #itemRenderQueue > 0 do
                local pending = table.remove(itemRenderQueue, 1)
                local target = pending.lifecycle
                if target and target.record
                    and target.generation == pending.generation
                    and target.activeGeneration == pending.generation
                    and recordKey(target.record) == pending.key
                    and target.frame:IsShown() then
                    target.pendingItemRender = nil
                    target:RenderTransmorpherItem(target.record)
                    break
                end
            end
            if #itemRenderQueue == 0 then self:SetScript("OnUpdate", nil) end
        end)
    end
end

local function getItemDescriptor(record)
    local itemId = record and tonumber(record.itemId)
    local itemSubclass
    local inventoryType
    if itemId and GetItemInfo then
        itemSubclass = select(7, GetItemInfo(itemId))
        inventoryType = select(9, GetItemInfo(itemId))
    end
    return itemId, itemSubclass, inventoryType
end

local function modelTypeForRecord(record)
    if not record or (record.slot ~= "MAINHAND" and record.slot ~= "OFFHAND") then
        return TYPE_PLAYER
    end

    local weaponType = record.weaponType or record.weaponCategory
    local _, _, inventoryType = getItemDescriptor(record)
    if RANGED_WEAPON_TYPES[weaponType]
        or inventoryType == "INVTYPE_RANGED"
        or inventoryType == "INVTYPE_RANGEDRIGHT"
        or inventoryType == "INVTYPE_THROWN" then
        return TYPE_RANGED
    end
    if record.slot == "OFFHAND"
        or OFFHAND_WEAPON_TYPES[weaponType]
        or inventoryType == "INVTYPE_WEAPONOFFHAND"
        or inventoryType == "INVTYPE_SHIELD"
        or inventoryType == "INVTYPE_HOLDABLE" then
        return TYPE_OFF
    end
    return TYPE_MAIN
end

local function prefixOneHandSubclass(base, record, inventoryType)
    if base ~= "Axe" and base ~= "Mace" and base ~= "Sword"
        and base ~= "Dagger" and base ~= "Fist" then
        return base
    end
    if inventoryType == "INVTYPE_2HWEAPON" then return "2H " .. base end
    if inventoryType == "INVTYPE_WEAPONOFFHAND" or record.slot == "OFFHAND" then
        return "OH " .. base
    end
    if inventoryType == "INVTYPE_WEAPONMAINHAND" then return "MH " .. base end
    return "1H " .. base
end

local function weaponDescriptorForRecord(record)
    local modelType = modelTypeForRecord(record)
    if modelType == TYPE_PLAYER then return nil, "NOT_WEAPON" end

    local itemId, itemSubclass, inventoryType = getItemDescriptor(record)
    if not itemId then return nil, "INVALID_ITEM_ID" end
    local weaponType = record.weaponType or record.weaponCategory
    local subclass = WEAPON_SUBCLASS[weaponType] or LOCALIZED_SUBCLASS[itemSubclass]

    if inventoryType == "INVTYPE_SHIELD" then
        subclass = "Shield"
    elseif inventoryType == "INVTYPE_HOLDABLE" then
        subclass = "Held in Off-hand"
    end
    if not subclass then return nil, "WEAPON_SUBCLASS_UNAVAILABLE" end
    subclass = prefixOneHandSubclass(subclass, record, inventoryType)

    return {
        itemId = itemId,
        modelType = modelType,
        slotName = WEAPON_SLOT_NAME[modelType],
        subclass = subclass,
    }, "READY"
end

local function startsWith(value, prefix)
    return string.sub(value, 1, string.len(prefix)) == prefix
end

-- Namespaced copy of Transmorpher PreviewSetupAPI.GetPreviewSetup. Armor is
-- resolved from race/sex/Armor/slot. Weapon lookup keeps the upstream order:
-- actual render slot, full subclass, similar type, any camera from that render
-- slot, then Main Hand.
local function getTransmorpherSetup(slotName, subclass)
    local classic = PreviewSetup and PreviewSetup.classic
    local _, raceFileName = UnitRace("player")
    local sex = UnitSex("player")
    local raceData = classic and classic[raceFileName] and classic[raceFileName][sex]
    if not raceData then
        return nil, nil, "TRANSMORPHER_SETUP_UNAVAILABLE"
    end

    local armorData = raceData["Armor"]
    if armorData and armorData[slotName] then
        return armorData[slotName], slotName, "READY"
    end
    if not raceData[slotName] or type(subclass) ~= "string" or subclass == "" then
        return nil, nil, "TRANSMORPHER_SETUP_UNAVAILABLE"
    end

    local lookupSubclass = subclass
    local renderSlot = slotName
    local offhandRender = {
        ["Shield"] = true,
        ["Held in Off-hand"] = true,
    }
    local rangedRender = {
        ["Bow"] = true,
        ["Crossbow"] = true,
        ["Gun"] = true,
        ["Wand"] = true,
        ["Thrown"] = true,
    }

    if startsWith(subclass, "OH") then
        lookupSubclass = string.sub(subclass, 4)
        renderSlot = "Off-hand"
    elseif startsWith(subclass, "MH") then
        lookupSubclass = string.sub(subclass, 4)
        renderSlot = "Main Hand"
    elseif startsWith(subclass, "1H") then
        lookupSubclass = string.sub(subclass, 4)
        renderSlot = "Main Hand"
    elseif offhandRender[subclass] then
        renderSlot = "Off-hand"
    elseif rangedRender[subclass] then
        renderSlot = "Ranged"
    else
        renderSlot = "Main Hand"
    end

    local renderData = raceData[renderSlot]
    if renderData and renderData[lookupSubclass] then
        return renderData[lookupSubclass], renderSlot, "READY"
    end
    if lookupSubclass ~= subclass and renderData and renderData[subclass] then
        return renderData[subclass], renderSlot, "READY"
    end

    local similarMap = {
        ["2H Axe"] = "Axe",
        ["2H Mace"] = "Mace",
        ["2H Sword"] = "Sword",
        ["Polearm"] = "Axe",
        ["Staff"] = "Sword",
    }
    local similar = similarMap[lookupSubclass] or similarMap[subclass]
    if similar and renderData and renderData[similar] then
        return renderData[similar], renderSlot, "READY"
    end
    if renderData then
        for _, setup in pairs(renderData) do
            return setup, renderSlot, "RENDER_SLOT_FALLBACK"
        end
    end
    if raceData["Main Hand"] then
        for _, setup in pairs(raceData["Main Hand"]) do
            return setup, "Main Hand", "MAIN_HAND_FALLBACK"
        end
    end
    return nil, renderSlot, "TRANSMORPHER_SETUP_UNAVAILABLE"
end

local function resetPreviewState(frame)
    frame.scTransmorpherSetup = nil
    frame.scTransmorpherSlot = nil
    frame.scTransmorpherSubclass = nil
end

local function setUnavailable(lifecycle, reason)
    local frame = lifecycle.frame
    frame.scRuntimeUnavailableReason = reason
    frame:SetScript("OnUpdate", nil)
    safeCall(frame, "ClearModel")
    frame:Hide()
    if frame.scUnavailableIcon and frame.scRecord and GetItemIcon then
        SC.UI.SetIconTexture(frame.scUnavailableIcon, GetItemIcon(frame.scRecord.itemId))
    end
    if frame.scUnavailableText then
        local labels = {
            PLAYER_MODEL_LOAD_FAILED = "装备预览未就绪",
            CAPABILITY_MISSING = "SoloCam 武器预览未就绪",
            PREVIEW_PROTOCOL_MISMATCH = "SoloCam 武器协议不匹配",
            INVALID_ITEM_ID = "物品无效",
            ITEM_QUERY_FAILED = "物品数据未就绪",
            ARMOR_SLOT_UNAVAILABLE = "护甲部位未映射",
            WEAPON_SUBCLASS_UNAVAILABLE = "武器分类未就绪",
            TRANSMORPHER_SETUP_UNAVAILABLE = "物品构图未就绪",
            MODEL_UNAVAILABLE = "物品模型未就绪",
            TRYON_FAILED = "物品试穿失败",
        }
        frame.scUnavailableText:SetText(labels[reason] or "物品预览不可用")
    end
    if frame.scUnavailable then frame.scUnavailable:Show() end
    return false, reason
end

local function applyTransmorpherLight(frame)
    -- Transmorpher DressingRoom.lua defaultLight.
    safeCall(frame, "SetLight", 1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64)
end

-- 3.3.5 DressUpModel SetAllPoints often leaves a leftover 3D viewport on the
-- left of the widget. Keep an explicit card-sized rectangle centered in the
-- cell; do not grow past the card (the renderer does not clip oversized
-- viewports). Camera x/y/z still come from TransmorpherPreviewSetup.
local function syncCardViewport(frame)
    local card = frame and frame.scCard
    if not card then return end
    local width = card:GetWidth()
    local height = card:GetHeight()
    if not width or width < 1 then width = 78 end
    if not height or height < 1 then height = 104 end
    frame:ClearAllPoints()
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetPoint("CENTER", card, "CENTER", 0, 0)
    local objectModel = frame.scObjectModel
    if objectModel then
        objectModel:ClearAllPoints()
        objectModel:SetWidth(width)
        objectModel:SetHeight(height)
        objectModel:SetPoint("CENTER", card, "CENTER", 0, 0)
    end
end

function TransmogModelMixin:SetType(modelType, force)
    if not VALID_TYPES[modelType] then return false, "INVALID_MODEL_TYPE" end
    if self.type == modelType and not force then return false, "UNCHANGED" end

    self.type = modelType
    resetPreviewState(self.frame)
    safeCall(self.frame, "SetPosition", 0, 0, 0)
    safeCall(self.frame, "SetFacing", 0)
    safeCall(self.frame, "ClearModel")
    if not safeCall(self.frame, "SetUnit", "player") then
        return false, "PLAYER_MODEL_LOAD_FAILED"
    end
    syncCardViewport(self.frame)
    return true, "READY"
end

function TransmogModelMixin:RefreshType()
    return self:SetType(self.type or TYPE_PLAYER, true)
end

function WardrobeItemsModelMixin:OnModelLoaded()
    if self.suppressModelEvent or not self.record
        or self.generation ~= self.activeGeneration then
        return
    end
    if self.transmorpherSetup then
        -- Exact Transmorpher PreviewList OnUpdateModel behavior for both armor
        -- and weapons: only restore the selected setup sequence.
        safeCall(self.frame, "SetSequence", self.transmorpherSetup.sequence)
    end
end

function WardrobeItemsModelMixin:PrepareTransmorpherFrame()
    self.frame:SetScript("OnUpdate", nil)
    safeCall(self.frame, "SetAutoDress", true)
    safeCall(self.frame, "SetDoBlend", true)
    safeCall(self.frame, "SetKeepModelOnHide", false)
    safeCall(self.frame, "SetAlpha", 1)
    safeCall(self.frame, "SetModelScale", 1)

    -- Transmorpher DressingRoom:Reset resets model-space state, clears the
    -- previous actor and rebuilds the player's race/sex model every render.
    self.suppressModelEvent = true
    safeCall(self.frame, "SetPosition", 0, 0, 0)
    safeCall(self.frame, "SetFacing", 0)
    safeCall(self.frame, "ClearModel")
    if not safeCall(self.frame, "SetUnit", "player") then
        self.suppressModelEvent = nil
        return false, "PLAYER_MODEL_LOAD_FAILED"
    end
    syncCardViewport(self.frame)
    applyTransmorpherLight(self.frame)
    return true, "READY"
end

function WardrobeItemsModelMixin:RenderTransmorpherWeapon(record)
    local descriptor, descriptorReason = weaponDescriptorForRecord(record)
    if not descriptor then return setUnavailable(self, descriptorReason) end

    local capability
    local capabilityReason = "CAPABILITY_MISSING"
    if NativePreview then
        capability, capabilityReason = NativePreview:GetCapability()
    end
    if not capability then return setUnavailable(self, capabilityReason or "CAPABILITY_MISSING") end

    local setup, renderSlot, setupReason = getTransmorpherSetup(
        descriptor.slotName,
        descriptor.subclass
    )
    if not setup then return setUnavailable(self, setupReason) end
    local equipmentSlotId = EQUIPMENT_SLOT_ID[renderSlot]
    if not equipmentSlotId then return setUnavailable(self, "TRANSMORPHER_SETUP_UNAVAILABLE") end

    self.transmorpherSetup = setup
    self.weaponDescriptor = descriptor
    self.frame.scTransmorpherSetup = setup
    self.frame.scTransmorpherSlot = renderSlot
    self.frame.scTransmorpherSubclass = descriptor.subclass

    -- Transmorpher PreviewList_RenderItem order:
    -- Reset -> Undress -> SetPosition -> SetFacing -> TryOn -> SetSequence.
    local prepared, prepareReason = self:PrepareTransmorpherFrame()
    if not prepared then return setUnavailable(self, prepareReason) end

    local undressed, undressReason = NativePreview:Undress(self.frame)
    if not undressed then
        self.suppressModelEvent = nil
        return setUnavailable(self, undressReason or "MODEL_UNAVAILABLE")
    end
    safeCall(self.frame, "SetPosition", setup.x, setup.y, setup.z)
    safeCall(self.frame, "SetFacing", setup.facing)
    local triedOn, tryOnReason = NativePreview:TryOn(
        self.frame,
        descriptor.itemId,
        equipmentSlotId
    )
    self.suppressModelEvent = nil
    if not triedOn then return setUnavailable(self, tryOnReason or "TRYON_FAILED") end
    safeCall(self.frame, "SetSequence", setup.sequence)
    return true, setupReason
end

function WardrobeItemsModelMixin:RenderTransmorpherArmor(record)
    local itemId = record and tonumber(record.itemId)
    if not itemId or itemId <= 0 then return setUnavailable(self, "INVALID_ITEM_ID") end
    local slotName = ARMOR_SLOT_NAME[record.slot]
    if not slotName then return setUnavailable(self, "ARMOR_SLOT_UNAVAILABLE") end
    local setup, _, setupReason = getTransmorpherSetup(slotName)
    if not setup then return setUnavailable(self, setupReason) end

    self.transmorpherSetup = setup
    self.weaponDescriptor = nil
    self.frame.scTransmorpherSetup = setup
    self.frame.scTransmorpherSlot = slotName
    self.frame.scTransmorpherSubclass = "Armor"

    -- Direct projection of Transmorpher PreviewList_RenderItem for armor.
    -- Armor uses the stock Lua Undress/TryOn methods and never needs SoloCam.
    local prepared, prepareReason = self:PrepareTransmorpherFrame()
    if not prepared then return setUnavailable(self, prepareReason) end
    if not safeCall(self.frame, "Undress") then
        self.suppressModelEvent = nil
        return setUnavailable(self, "MODEL_UNAVAILABLE")
    end
    safeCall(self.frame, "SetPosition", setup.x, setup.y, setup.z)
    safeCall(self.frame, "SetFacing", setup.facing)
    local triedOn = safeCall(self.frame, "TryOn", itemId)
    self.suppressModelEvent = nil
    if not triedOn then
        return setUnavailable(self, "TRYON_FAILED")
    end
    safeCall(self.frame, "SetSequence", setup.sequence)
    return true, setupReason
end

function WardrobeItemsModelMixin:RenderTransmorpherItem(record)
    if modelTypeForRecord(record) == TYPE_PLAYER then
        return self:RenderTransmorpherArmor(record)
    end
    return self:RenderTransmorpherWeapon(record)
end

function WardrobeItemsModelMixin:Reload(record, pageGeneration, force)
    if not record then return self:Clear() end
    local nextKey = recordKey(record)
    if not force and self.recordKey == nextKey and not self.frame.scRuntimeUnavailableReason then
        self.record = record
        self.frame.scRecord = record
        self.frame.scRecordId = record.collectionId or record.id
        return true, "UNCHANGED"
    end

    self.generation = (self.generation or 0) + 1
    self.activeGeneration = self.generation
    self.record = record
    self.recordKey = nextKey
    self.frame.scRecord = record
    self.frame.scRecordId = record.collectionId or record.id
    self.frame.scItemGeneration = pageGeneration or self.generation
    self.frame.scAppearanceGeneration = self.generation
    self.frame.scRuntimeUnavailableReason = nil

    local nextType = modelTypeForRecord(record)
    self.frame.scRenderKind = nextType == TYPE_PLAYER
        and "TRANSMORPHER_ARMOR" or "TRANSMORPHER_WEAPON"
    if self.frame.scCard then self.frame.scCard:Show() end
    if self.frame.scUnavailable then self.frame.scUnavailable:Hide() end
    if self.objectModel then
        safeCall(self.objectModel, "ClearModel")
        self.objectModel:Hide()
    end
    self.frame:Show()
    syncCardViewport(self.frame)
    safeCall(self.frame, "SetModelScale", TYPE_SCALE[nextType])

    local typeChanged, typeReason = TransmogModelMixin.SetType(self, nextType, false)
    if typeReason ~= "READY" and typeReason ~= "UNCHANGED" then
        return setUnavailable(self, typeReason)
    end

    -- Transmorpher clears each recycled model before QueryItem and only calls
    -- Reset/Undress/TryOn after item data is ready.  The global queue submits
    -- at most one cached item TryOn per UI frame. This preserves its renderer
    -- order without issuing 18 armor or shield rebuilds in the same frame.
    self.transmorpherSetup = nil
    self.weaponDescriptor = nil
    self.pendingItemRender = nil
    safeCall(self.frame, "ClearModel")
    local expectedGeneration = self.generation
    local function onItemReady(itemId, success)
        if self.generation ~= expectedGeneration
            or self.activeGeneration ~= expectedGeneration
            or not self.record
            or tonumber(self.record.itemId) ~= tonumber(itemId) then
            return
        end
        if not success then
            setUnavailable(self, "ITEM_QUERY_FAILED")
            return
        end
        queueItemRender(self, self.record, expectedGeneration)
    end
    if ItemQuery and type(ItemQuery.Query) == "function" then
        local requested, queryReason = ItemQuery:Query(record.itemId, onItemReady)
        if not requested then return setUnavailable(self, queryReason or "ITEM_QUERY_FAILED") end
        return true, queryReason or "QUERYING"
    end
    queueItemRender(self, record, expectedGeneration)
    return true, typeChanged and "TYPE_CHANGED" or "QUEUED"
end

function WardrobeItemsModelMixin:Clear()
    self.generation = (self.generation or 0) + 1
    self.activeGeneration = self.generation
    self.record = nil
    self.recordKey = nil
    self.type = nil
    self.transmorpherSetup = nil
    self.weaponDescriptor = nil
    self.pendingItemRender = nil
    self.frame:SetScript("OnUpdate", nil)
    self.frame.scRecord = nil
    self.frame.scRecordId = nil
    self.frame.scRenderKind = nil
    self.frame.scRuntimeUnavailableReason = nil
    resetPreviewState(self.frame)
    safeCall(self.frame, "SetPosition", 0, 0, 0)
    safeCall(self.frame, "SetFacing", 0)
    safeCall(self.frame, "ClearModel")
    self.frame:Hide()
    if self.frame.scUnavailable then self.frame.scUnavailable:Hide() end
    if self.frame.scCard then self.frame.scCard:Hide() end
    if self.objectModel then
        safeCall(self.objectModel, "ClearModel")
        self.objectModel:Hide()
    end
    return true, "CLEARED"
end

function Model:Attach(frame, objectModel)
    if frame.scEzWardrobeLifecycle then return frame.scEzWardrobeLifecycle end
    local lifecycle = setmetatable({
        frame = frame,
        objectModel = objectModel,
        generation = 0,
        activeGeneration = 0,
    }, {
        __index = function(_, key)
            return WardrobeItemsModelMixin[key] or TransmogModelMixin[key]
        end,
    })
    frame.scEzWardrobeLifecycle = lifecycle
    frame.scObjectModel = objectModel
    if objectModel then objectModel.scHostModel = frame end
    frame:SetScript("OnUpdateModel", function()
        lifecycle:OnModelLoaded()
    end)
    syncCardViewport(frame)
    safeCall(frame, "SetModelScale", TYPE_SCALE[TYPE_PLAYER])
    applyTransmorpherLight(frame)
    lifecycle:SetType(TYPE_PLAYER, false)
    self.lifecycles[frame] = lifecycle
    return lifecycle
end

function Model:OnNativePreviewReady()
    for _, lifecycle in pairs(self.lifecycles) do
        if lifecycle.record and modelTypeForRecord(lifecycle.record) ~= TYPE_PLAYER then
            lifecycle:Reload(lifecycle.record, lifecycle.activeGeneration, true)
        end
    end
end

function Model:Present(frame, record, pageGeneration, force)
    return self:Attach(frame, frame.scObjectModel):Reload(record, pageGeneration, force)
end

function Model:Clear(frame)
    return self:Attach(frame, frame.scObjectModel):Clear()
end
