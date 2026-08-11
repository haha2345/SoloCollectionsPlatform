local SC = SoloCollections

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

Lab.SLOTS = {
    { key = "HEAD", label = "头部", inventorySlot = 0 },
    { key = "SHOULDER", label = "肩部", inventorySlot = 2 },
    { key = "BACK", label = "背部", inventorySlot = 14 },
    { key = "CHEST", label = "胸部", inventorySlot = 4 },
    { key = "WRIST", label = "手腕", inventorySlot = 8 },
    { key = "HANDS", label = "手部", inventorySlot = 9 },
    { key = "WAIST", label = "腰部", inventorySlot = 5 },
    { key = "LEGS", label = "腿部", inventorySlot = 6 },
    { key = "FEET", label = "脚部", inventorySlot = 7 },
    { key = "MAINHAND", label = "主手", inventorySlot = 15 },
    { key = "OFFHAND", label = "副手", inventorySlot = 16 },
}

Lab.SLOT_BY_KEY = {}
for _, definition in ipairs(Lab.SLOTS) do Lab.SLOT_BY_KEY[definition.key] = definition end

local State = {}
State.__index = State

local function currentRevision()
    return SC.CollectionState and SC.CollectionState.GetRevision and SC.CollectionState.GetRevision() or "0"
end

local function recordItemId(record)
    if type(record) ~= "table" then return nil end
    return tonumber(record.itemId or (record.itemIds and record.itemIds[1]))
end

local function getSelectedVariant(record)
    if type(record) ~= "table" then return nil end
    if type(record.selectedVariant) == "table" then return record.selectedVariant end
    local requested = tonumber(record.selectedVariantOrdinal)
    local fallback
    for _, variant in ipairs(record.variants or {}) do
        if not fallback or variant.isDefault then fallback = variant end
        if requested and tonumber(variant.variantOrdinal) == requested then return variant end
    end
    return fallback
end

local function getMemberItemId(member)
    if type(member) ~= "table" then return nil end
    local itemId = tonumber(member.previewSourceItemId)
    for _, sourceItemId in ipairs(member.sourceItemIds or {}) do
        sourceItemId = tonumber(sourceItemId)
        if sourceItemId and (not itemId or sourceItemId < itemId) then itemId = sourceItemId end
    end
    return itemId
end

function Lab.CreateState()
    local state = setmetatable({
        equippedBySlot = {}, draftBySlot = {}, selectedSlot = "HEAD", dirtySlots = {},
        requestState = { status = "IDLE", revision = currentRevision() },
        listeners = {}, generation = 0, preservedOnClose = false,
        presetRecord = nil, requestSerial = 0,
    }, State)
    state:CaptureEquipped()
    return state
end

function State:CaptureEquipped()
    self.equippedBySlot = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", definition.inventorySlot + 1)
        self.equippedBySlot[definition.key] = link and tonumber(string.match(link, "item:(%d+)")) or nil
    end
end

function State:Subscribe(owner, callback)
    if owner and type(callback) == "function" then self.listeners[owner] = callback end
end

function State:Notify(reason)
    self.generation = self.generation + 1
    for owner, callback in pairs(self.listeners) do pcall(callback, owner, self, reason) end
end

function State:SelectSlot(slotKey)
    if not Lab.SLOT_BY_KEY[slotKey] then return false end
    self.selectedSlot = slotKey
    self:Notify("SELECT_SLOT")
    return true
end

function State:SetDraft(slotKey, record)
    if not Lab.SLOT_BY_KEY[slotKey] or type(record) ~= "table" then return false end
    self.presetRecord = nil
    self.draftBySlot[slotKey] = record
    self.dirtySlots[slotKey] = true
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_DRAFT", slot = slotKey, revision = currentRevision() }
    self:Notify("SET_DRAFT")
    return true
end

function State:SetPreset(record)
    if type(record) ~= "table" then return false end
    self.draftBySlot, self.dirtySlots = {}, {}
    self.presetRecord = record
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_PRESET", record = record, revision = currentRevision() }
    self:Notify("SET_PRESET")
    return true
end

function State:ClearDraft(slotKey)
    if slotKey then
        self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    else
        self.draftBySlot, self.dirtySlots = {}, {}
        self.presetRecord = nil
    end
    self.requestState = { status = "IDLE", revision = currentRevision() }
    self:Notify("CLEAR_DRAFT")
end

function State:GetDirtyCount()
    if self.presetRecord then
        local count, seen = 0, {}
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            local slotKey = member.slotKey
            if slotKey and Lab.SLOT_BY_KEY[slotKey] and not seen[slotKey] and getMemberItemId(member) then
                seen[slotKey] = true
                count = count + 1
            end
        end
        return count
    end
    local count = 0
    for _ in pairs(self.dirtySlots) do count = count + 1 end
    return count
end

function State:HasDraft() return self.presetRecord ~= nil or next(self.dirtySlots) ~= nil end

function State:IsSlotDirty(slotKey)
    if self.dirtySlots[slotKey] then return true end
    if not self.presetRecord then return false end
    local variant = getSelectedVariant(self.presetRecord)
    for _, member in ipairs((variant and variant.members) or {}) do
        if member.slotKey == slotKey and getMemberItemId(member) then return true end
    end
    return false
end

function State:GetSlotPreviewItemId(slotKey)
    if self.presetRecord then
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            if member.slotKey == slotKey then
                local itemId = getMemberItemId(member)
                if itemId then return itemId, true end
            end
        end
    end
    local draft = self.draftBySlot[slotKey]
    if draft then return recordItemId(draft), true end
    return self.equippedBySlot[slotKey], false
end

function State:GetPreviewItemIds()
    local items = {}
    if self.presetRecord then
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            local itemId = getMemberItemId(member)
            if itemId then items[#items + 1] = itemId end
        end
        return items
    end
    for _, definition in ipairs(Lab.SLOTS) do
        local itemId = recordItemId(self.draftBySlot[definition.key])
        if itemId then items[#items + 1] = itemId end
    end
    return items
end

function State:BeginApply()
    local slotKey = self.selectedSlot
    local record, definition = self.draftBySlot[slotKey], Lab.SLOT_BY_KEY[slotKey]
    if not record or not definition then return false, "NO_DRAFT" end
    if not record.collected then return false, "NOT_OWNED" end
    if self.requestState.status == "REQUESTING" or self.requestState.status == "WAITING_STATE" then
        return false, "REQUEST_PENDING"
    end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local baseRevision = currentRevision()
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "SLOT", slot = slotKey,
        record = record, revision = baseRevision, token = requestToken,
    }
    self:Notify("REQUESTING")
    local requestId = SC.Bridge.ApplyAppearance(record.id, definition.inventorySlot, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if ok then
            self.requestState.status, self.requestState.reason = "WAITING_STATE", reason or "ACCEPTED"
        else
            self.requestState.status, self.requestState.reason = "FAILED", reason or "UNKNOWN"
        end
        self:Notify("REQUEST_RESULT")
    end)
    if self.requestState and self.requestState.token == requestToken then
        self.requestState.requestId = requestId
    end
    if not requestId and self.requestState and self.requestState.token == requestToken
        and self.requestState.status == "REQUESTING" then
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    local failureReason = self.requestState and self.requestState.reason
    return requestId ~= nil, requestId and nil or failureReason
end

function State:BeginApplySet()
    local record = self.presetRecord
    if not record then return false, "NO_PRESET" end
    if not record.collected then return false, "NOT_OWNED" end
    if self.requestState.status == "REQUESTING" or self.requestState.status == "WAITING_STATE" then
        return false, "REQUEST_PENDING"
    end
    if not SC.Bridge or type(SC.Bridge.ApplySet) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local variant = getSelectedVariant(record)
    local baseRevision = currentRevision()
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "SET", record = record,
        revision = baseRevision, token = requestToken,
    }
    self:Notify("REQUESTING_SET")
    local requestId = SC.Bridge.ApplySet(record.id, variant and variant.variantOrdinal or nil, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if ok then
            self.requestState.status, self.requestState.reason = "WAITING_STATE", reason or "ACCEPTED"
        else
            self.requestState.status, self.requestState.reason = "FAILED", reason or "UNKNOWN"
        end
        self:Notify("REQUEST_RESULT")
    end)
    if self.requestState and self.requestState.token == requestToken then
        self.requestState.requestId = requestId
    end
    if not requestId and self.requestState and self.requestState.token == requestToken
        and self.requestState.status == "REQUESTING" then
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    local failureReason = self.requestState and self.requestState.reason
    return requestId ~= nil, requestId and nil or failureReason
end

function State:ObserveAuthoritativeState()
    if self.requestState.status ~= "WAITING_STATE" then return false end
    local revision = currentRevision()
    if tostring(revision) == tostring(self.requestState.revision) then return false end
    local kind = self.requestState.kind
    local slotKey = self.requestState.slot
    if kind == "SET" then
        self.presetRecord = nil
    else
        self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    end
    self.requestState = { status = "CONFIRMED", kind = kind, slot = slotKey, revision = revision }
    self:CaptureEquipped()
    self:Notify("AUTHORITATIVE_REFRESH")
    return true
end

function State:MarkClosed() self.preservedOnClose = self:HasDraft() end
