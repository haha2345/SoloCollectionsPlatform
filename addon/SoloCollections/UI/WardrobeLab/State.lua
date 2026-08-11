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

function Lab.CreateState()
    local state = setmetatable({
        equippedBySlot = {}, draftBySlot = {}, selectedSlot = "HEAD", dirtySlots = {},
        requestState = { status = "IDLE", revision = currentRevision() },
        listeners = {}, generation = 0, preservedOnClose = false,
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
    self.draftBySlot[slotKey] = record
    self.dirtySlots[slotKey] = true
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_DRAFT", slot = slotKey, revision = currentRevision() }
    self:Notify("SET_DRAFT")
    return true
end

function State:ClearDraft(slotKey)
    if slotKey then
        self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    else
        self.draftBySlot, self.dirtySlots = {}, {}
    end
    self.requestState = { status = "IDLE", revision = currentRevision() }
    self:Notify("CLEAR_DRAFT")
end

function State:GetDirtyCount()
    local count = 0
    for _ in pairs(self.dirtySlots) do count = count + 1 end
    return count
end

function State:HasDraft() return next(self.dirtySlots) ~= nil end

function State:BeginApply()
    local slotKey = self.selectedSlot
    local record, definition = self.draftBySlot[slotKey], Lab.SLOT_BY_KEY[slotKey]
    if not record or not definition then return false, "NO_DRAFT" end
    if self.requestState.status == "REQUESTING" or self.requestState.status == "WAITING_STATE" then
        return false, "REQUEST_PENDING"
    end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local baseRevision = currentRevision()
    self.requestState = { status = "REQUESTING", slot = slotKey, record = record, revision = baseRevision }
    self:Notify("REQUESTING")
    local requestId = SC.Bridge.ApplyAppearance(record.id, definition.inventorySlot, function(ok, reason)
        if ok then
            self.requestState.status, self.requestState.reason = "WAITING_STATE", reason or "ACCEPTED"
        else
            self.requestState.status, self.requestState.reason = "FAILED", reason or "UNKNOWN"
        end
        self:Notify("REQUEST_RESULT")
    end)
    self.requestState.requestId = requestId
    if not requestId and self.requestState.status == "REQUESTING" then
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    return requestId ~= nil, requestId and nil or self.requestState.reason
end

function State:ObserveAuthoritativeState()
    if self.requestState.status ~= "WAITING_STATE" then return false end
    local revision = currentRevision()
    if tostring(revision) == tostring(self.requestState.revision) then return false end
    local slotKey = self.requestState.slot
    self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    self.requestState = { status = "CONFIRMED", slot = slotKey, revision = revision }
    self:CaptureEquipped()
    self:Notify("AUTHORITATIVE_REFRESH")
    return true
end

function State:MarkClosed() self.preservedOnClose = self:HasDraft() end

