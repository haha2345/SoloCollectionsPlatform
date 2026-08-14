local SC = SoloCollections

local NativePreview = SC.NativePreview or {}
SC.NativePreview = NativePreview

local TRY_ON_AUTO_BASE = 0x10000000
local TRY_ON_SLOT_BASE = 0x18000000
local TRY_ON_SLOT_STRIDE = 0x00100000
local UNDRESS_REQUEST = 0x1FFFFFFF
local MAXIMUM_ITEM_ID = 0x000FFFFF
local VALID_EQUIPMENT_SLOT = { [16] = true, [17] = true, [18] = true }

NativePreview.PROTOCOL_VERSION = 1
NativePreview.SOLOCAM_VERSION = 11
NativePreview._runtimeCapability = nil

local function usableModel(model)
    return model and type(model.SetCreature) == "function"
end

function NativePreview:SetRuntimeCapability(capability)
    local wasReady = self._runtimeCapability ~= nil
    self._runtimeCapability = nil
    if type(capability) ~= "table"
        or tonumber(capability.soloCamVersion) ~= self.SOLOCAM_VERSION
        or tonumber(capability.previewProtocolVersion) ~= self.PROTOCOL_VERSION
        or type(capability.features) ~= "table"
        or capability.features.previewTryOnV1 ~= true then
        return false, "PREVIEW_PROTOCOL_MISMATCH"
    end
    self._runtimeCapability = {
        soloCamVersion = self.SOLOCAM_VERSION,
        previewProtocolVersion = self.PROTOCOL_VERSION,
        features = capability.features,
    }
    if not wasReady then
        local model = SC.EzWardrobe and SC.EzWardrobe.Model
        if model and type(model.OnNativePreviewReady) == "function" then
            model:OnNativePreviewReady()
        end
    end
    return true, "READY"
end

function NativePreview:GetCapability()
    return self._runtimeCapability, self._runtimeCapability and "READY" or "CAPABILITY_MISSING"
end

function NativePreview:Undress(model)
    if not self._runtimeCapability then return false, "CAPABILITY_MISSING" end
    if not usableModel(model) then return false, "MODEL_UNAVAILABLE" end
    local ok = pcall(model.SetCreature, model, UNDRESS_REQUEST)
    return ok, ok and "READY" or "MODEL_UNAVAILABLE"
end

function NativePreview:TryOn(model, sourceItemId, equipmentSlotId)
    if not self._runtimeCapability then return false, "CAPABILITY_MISSING" end
    sourceItemId = tonumber(sourceItemId)
    if not sourceItemId or sourceItemId <= 0 or sourceItemId > MAXIMUM_ITEM_ID then
        return false, "INVALID_ITEM_ID"
    end
    if not usableModel(model) then return false, "MODEL_UNAVAILABLE" end

    local request
    if equipmentSlotId == nil then
        request = TRY_ON_AUTO_BASE + sourceItemId
    else
        equipmentSlotId = tonumber(equipmentSlotId)
        if not VALID_EQUIPMENT_SLOT[equipmentSlotId] then return false, "INVALID_SLOT_ID" end
        request = TRY_ON_SLOT_BASE + equipmentSlotId * TRY_ON_SLOT_STRIDE + sourceItemId
    end
    local ok = pcall(model.SetCreature, model, request)
    return ok, ok and "READY" or "MODEL_UNAVAILABLE"
end
