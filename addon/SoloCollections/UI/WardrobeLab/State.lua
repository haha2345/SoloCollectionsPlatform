local SC = SoloCollections

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

Lab.SLOTS = {
    { key = "HEAD", label = "头部", inventorySlot = 0 },
    { key = "SHOULDER", label = "肩部", inventorySlot = 2 },
    { key = "BACK", label = "背部", inventorySlot = 14 },
    { key = "CHEST", label = "胸部", inventorySlot = 4 },
    { key = "SHIRT", label = "衬衣", inventorySlot = 3 },
    { key = "TABARD", label = "战袍", inventorySlot = 18 },
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

local APPEARANCE_CATEGORY = "APPEARANCES"
local SET_CATEGORY = "SETS"

local function currentRevision()
    return SC.CollectionState and SC.CollectionState.GetRevision and SC.CollectionState.GetRevision() or "0"
end

local function recordItemId(record)
    if type(record) ~= "table" then return nil end
    return tonumber(record.itemId or (record.itemIds and record.itemIds[1]))
end

local function collectionId(record)
    if type(record) ~= "table" then return nil end
    local value = tonumber(record.collectionId or record.id)
    if value and value > 0 and value == math.floor(value) then return value end
    return nil
end

local function currentAppearanceOwned(record, id)
    id = id or collectionId(record)
    if not id then return false, false, "INVALID_APPEARANCE" end
    local fallback = record and record.collected and true or false
    local state = SC.CollectionState
    if state and type(state.ResolveOwned) == "function" then
        local owned, ownershipKnown, stateName = state.ResolveOwned(APPEARANCE_CATEGORY, id, fallback)
        return owned and true or false, ownershipKnown and true or false, stateName
    end
    return fallback, false, "Demo"
end

local function selectedVariantOrdinal(record)
    local variant = type(record) == "table" and record.selectedVariant or nil
    return tonumber((type(variant) == "table" and variant.variantOrdinal) or
        (type(record) == "table" and record.selectedVariantOrdinal))
end

local function samePresetRecord(left, right)
    local leftId, rightId = collectionId(left), collectionId(right)
    if not leftId or leftId ~= rightId then return false end
    return selectedVariantOrdinal(left) == selectedVariantOrdinal(right)
end

local function sameAppearanceRecord(left, right)
    local leftId, rightId = collectionId(left), collectionId(right)
    return leftId ~= nil and leftId == rightId
end

local function currentSetRecord(record)
    local id = collectionId(record)
    if not id or not SC.Catalog or type(SC.Catalog.Get) ~= "function" then return record end
    local ordinal = selectedVariantOrdinal(record)
    for _, current in ipairs(SC.Catalog.Get(SET_CATEGORY) or {}) do
        if collectionId(current) == id then
            current.scSelectedVariantMissing = nil
            if ordinal then
                local matchedVariant = false
                for _, variant in ipairs(current.variants or {}) do
                    if tonumber(variant.variantOrdinal) == ordinal then
                        current.selectedVariant = variant
                        current.selectedVariantOrdinal = ordinal
                        matchedVariant = true
                        break
                    end
                end
                if not matchedVariant then current.scSelectedVariantMissing = true end
            end
            return current
        end
    end
    return record
end

local BLOCKED_FAILURE_REASONS = {
    NOT_OWNED = true,
    INVALID_APPEARANCE = true,
    INVALID_REQUEST = true,
    INVALID_TARGET_SLOT = true,
    CLASS_RESTRICTED = true,
    UNSUPPORTED = true,
}

local function bridgeCategoryReady(typeId)
    if not SC.Bridge then return false end
    if type(SC.Bridge.GetCategoryState) ~= "function" then return true end
    return SC.Bridge.GetCategoryState(typeId) == "Ready"
end

local function applyAccepted(ok, reason)
    return ok == true and (reason == nil or tostring(reason) == "ACCEPTED")
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

local function getMemberAppearanceId(member)
    if type(member) ~= "table" then return nil end
    for _, appearanceId in ipairs(member.appearanceIds or {}) do
        appearanceId = tonumber(appearanceId)
        if appearanceId and appearanceId > 0 and appearanceId == math.floor(appearanceId) then
            return appearanceId
        end
    end
    return nil
end

local function selectedVariantOwned(record)
    local variant = getSelectedVariant(record)
    if not variant then return false, 0, 0, "INVALID_REQUEST" end
    local ownedCount, requiredCount = 0, 0
    for _, member in ipairs(variant.members or {}) do
        if member.required then
            requiredCount = requiredCount + 1
            local memberOwned = false
            for _, appearanceId in ipairs(member.appearanceIds or {}) do
                local owned, ownershipKnown, ownershipState = currentAppearanceOwned(nil, appearanceId)
                if not ownershipKnown and ownershipState ~= "Demo" then
                    return false, ownedCount, requiredCount, "BRIDGE_UNAVAILABLE"
                end
                if owned then
                    memberOwned = true
                    break
                end
            end
            if memberOwned then ownedCount = ownedCount + 1 end
        end
    end
    if requiredCount == 0 then return false, ownedCount, requiredCount, "INVALID_REQUEST" end
    if ownedCount < requiredCount then return false, ownedCount, requiredCount, "NOT_OWNED" end
    return true, ownedCount, requiredCount
end

local function copyItemIds(member, fallbackItemId)
    local itemIds = {}
    for _, sourceItemId in ipairs((member and member.sourceItemIds) or {}) do
        sourceItemId = tonumber(sourceItemId)
        if sourceItemId then itemIds[#itemIds + 1] = sourceItemId end
    end
    if #itemIds == 0 and fallbackItemId then itemIds[1] = fallbackItemId end
    return itemIds
end

local function appearanceLookup()
    local lookup = {}
    if not SC.Catalog or type(SC.Catalog.Get) ~= "function" then return lookup end
    for _, record in ipairs(SC.Catalog.Get(APPEARANCE_CATEGORY) or {}) do
        local id = collectionId(record)
        if id then lookup[id] = record end
    end
    return lookup
end

local function appearanceRecordForMember(member, setRecord, lookup)
    local slotKey = type(member) == "table" and member.slotKey or nil
    if not slotKey or not Lab.SLOT_BY_KEY[slotKey] then return nil end
    local appearanceId = getMemberAppearanceId(member)
    local itemId = getMemberItemId(member)
    if not appearanceId or not itemId then return nil end
    if lookup and lookup[appearanceId] then return lookup[appearanceId] end
    return {
        id = appearanceId,
        collectionId = appearanceId,
        itemId = itemId,
        itemIds = copyItemIds(member, itemId),
        slot = slotKey,
        name = type(setRecord) == "table" and setRecord.name or nil,
        source = type(setRecord) == "table" and setRecord.source or nil,
        collected = type(setRecord) == "table" and setRecord.collected and true or false,
        favorite = false,
    }
end

local function firstDirtySlot(dirtySlots)
    for _, definition in ipairs(Lab.SLOTS) do
        if dirtySlots and dirtySlots[definition.key] then return definition.key end
    end
    return nil
end

local function appliedCopy(slotKey, record)
    local itemId = recordItemId(record)
    if not itemId then return nil end
    return {
        itemId = itemId,
        id = type(record) == "table" and record.id or nil,
        collectionId = collectionId(record),
        name = type(record) == "table" and record.name or nil,
        slot = slotKey,
        collected = type(record) == "table" and record.collected or nil,
    }
end

function Lab.CreateState()
    local state = setmetatable({
        equippedBySlot = {}, appliedBySlot = {}, draftBySlot = {}, selectedSlot = "HEAD", dirtySlots = {},
        requestState = { status = "IDLE", revision = currentRevision() },
        listeners = {}, generation = 0, preservedOnClose = false, equippedCaptured = false,
        presetRecord = nil, requestSerial = 0,
    }, State)
    state:CaptureEquipped()
    return state
end

function State:CaptureEquipped()
    local previous, hadPrevious = self.equippedBySlot or {}, self.equippedCaptured == true
    self.equippedBySlot = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", definition.inventorySlot + 1)
        local itemId = link and tonumber(string.match(link, "item:(%d+)")) or nil
        self.equippedBySlot[definition.key] = itemId
        if hadPrevious and previous[definition.key] ~= itemId and self.appliedBySlot then
            self.appliedBySlot[definition.key] = nil
        end
    end
    self.equippedCaptured = true
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
    if self:RejectMutationWhilePending() then return false, "REQUEST_PENDING" end
    if not Lab.SLOT_BY_KEY[slotKey] or type(record) ~= "table" then return false end
    local recordSlot = tostring(record.slot or "")
    if recordSlot ~= "" and recordSlot ~= slotKey then return false end
    if self.presetRecord then self:MaterializePresetDrafts() end
    self.draftBySlot[slotKey] = record
    self.dirtySlots[slotKey] = true
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_DRAFT", slot = slotKey, revision = currentRevision() }
    self:Notify("SET_DRAFT")
    return true
end

function State:SetPreset(record)
    if self:RejectMutationWhilePending() then return false, "REQUEST_PENDING" end
    if type(record) ~= "table" then return false end
    local alreadySelected = self.presetRecord and samePresetRecord(self.presetRecord, record)
    if self:HasDraft() and not alreadySelected then
        local confirmed = self.requestState and self.requestState.status == "CONFIRM_SET_PRESET"
            and samePresetRecord(self.requestState.record, record)
        if not confirmed then
            self.requestState = { status = "CONFIRM_SET_PRESET", record = record, revision = currentRevision() }
            self:Notify("CONFIRM_SET_PRESET")
            return false, "CONFIRM_SET_PRESET"
        end
    end
    self.draftBySlot, self.dirtySlots = {}, {}
    self.presetRecord = record
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_PRESET", record = record, revision = currentRevision() }
    self:Notify("SET_PRESET")
    return true
end

function State:ClearDraft(slotKey)
    if self:RejectMutationWhilePending() then return false, "REQUEST_PENDING" end
    if slotKey then
        if self.presetRecord then self:MaterializePresetDrafts() end
        self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    else
        self.draftBySlot, self.dirtySlots = {}, {}
        self.presetRecord = nil
    end
    local remainingSlot = firstDirtySlot(self.dirtySlots)
    self.requestState = remainingSlot
        and { status = "LOCAL_DRAFT", slot = remainingSlot, revision = currentRevision() }
        or { status = "IDLE", revision = currentRevision() }
    self:Notify("CLEAR_DRAFT")
    return true
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

function State:IsRequestPending()
    local status = self.requestState and self.requestState.status
    return status == "REQUESTING"
end

function State:RejectMutationWhilePending()
    if not self:IsRequestPending() then return false end
    self:Notify("REQUEST_PENDING_BLOCKED")
    return true
end

function State:GetBlockedFailureReason(kind, slotKey, record)
    local request = self.requestState
    if not request or request.status ~= "FAILED" or request.kind ~= kind then return nil end
    local reason = tostring(request.reason or "")
    if not BLOCKED_FAILURE_REASONS[reason] then return nil end
    if kind == "SLOT" then
        if request.slot ~= slotKey then return nil end
        if request.record and record and not sameAppearanceRecord(request.record, record) then return nil end
        return reason
    elseif kind == "DRAFT" then
        return reason
    elseif kind == "SET" then
        if request.record and self.presetRecord and not samePresetRecord(request.record, self.presetRecord) then return nil end
        return reason
    end
    return nil
end

function State:IsSlotDirty(slotKey)
    if self.dirtySlots[slotKey] then return true end
    if not self.presetRecord then return false end
    local variant = getSelectedVariant(self.presetRecord)
    for _, member in ipairs((variant and variant.members) or {}) do
        if member.slotKey == slotKey and getMemberItemId(member) then return true end
    end
    return false
end

function State:RefreshPresetRecord()
    if not self.presetRecord then return nil end
    self.presetRecord = currentSetRecord(self.presetRecord)
    return self.presetRecord
end

function State:MaterializePresetDrafts()
    local record = self:RefreshPresetRecord()
    local variant = getSelectedVariant(record)
    self.draftBySlot, self.dirtySlots = {}, {}
    self.presetRecord = nil
    if not variant then return 0 end
    local lookup = appearanceLookup()
    local count = 0
    for _, member in ipairs(variant.members or {}) do
        local draft = appearanceRecordForMember(member, record, lookup)
        if draft then
            local slotKey = draft.slot
            self.draftBySlot[slotKey] = draft
            self.dirtySlots[slotKey] = true
            count = count + 1
        end
    end
    return count
end

function State:FailApply(kind, slotKey, reason)
    self.requestState = {
        status = "FAILED",
        kind = kind,
        slot = slotKey,
        reason = reason or "UNKNOWN",
        revision = currentRevision(),
    }
    self:Notify("REQUEST_RESULT")
    return false, reason
end

function State:StoreAppliedRecord(slotKey, record)
    if not Lab.SLOT_BY_KEY[slotKey] then return false end
    local applied = appliedCopy(slotKey, record)
    if not applied then return false end
    self.appliedBySlot = self.appliedBySlot or {}
    self.appliedBySlot[slotKey] = applied
    return true
end

function State:StoreAppliedPreset(record)
    local variant = getSelectedVariant(record)
    if not variant then return false end
    local stored = false
    self.appliedBySlot = self.appliedBySlot or {}
    for _, member in ipairs(variant.members or {}) do
        local slotKey = member.slotKey
        local itemId = slotKey and Lab.SLOT_BY_KEY[slotKey] and getMemberItemId(member) or nil
        if itemId then
            self.appliedBySlot[slotKey] = {
                itemId = itemId,
                collectionId = collectionId(record),
                name = type(record) == "table" and record.name or nil,
                slot = slotKey,
                collected = type(record) == "table" and record.collected or nil,
            }
            stored = true
        end
    end
    return stored
end

function State:CompleteApply(kind, slotKey, reason, details)
    if kind == "SET" then
        self:StoreAppliedPreset(self.presetRecord)
        self.presetRecord = nil
    elseif kind == "DRAFT" then
        self.draftBySlot, self.dirtySlots = {}, {}
    elseif slotKey then
        self:StoreAppliedRecord(slotKey, self.draftBySlot[slotKey])
        self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    end
    local requestState = {
        status = "CONFIRMED",
        kind = kind,
        slot = slotKey,
        reason = reason or "ACCEPTED",
        revision = currentRevision(),
    }
    for key, value in pairs(details or {}) do requestState[key] = value end
    self.requestState = requestState
    self:CaptureEquipped()
    self:Notify("REQUEST_RESULT")
end

function State:GetDraftApplyState()
    if self:IsRequestPending() then return false, "REQUEST_PENDING", self:GetDirtyCount() end
    local blockedReason = self:GetBlockedFailureReason("DRAFT")
    if blockedReason then return false, blockedReason, self:GetDirtyCount() end
    local count = 0
    local draftEntries = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if record then
            count = count + 1
            local id = collectionId(record)
            if not id then return false, "INVALID_APPEARANCE", count end
            draftEntries[count] = { record = record, id = id }
        end
    end
    if count == 0 then return false, "NO_DRAFT", 0 end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE", count
    end
    if not bridgeCategoryReady(13) then
        return false, "BRIDGE_UNAVAILABLE", count
    end
    for _, entry in ipairs(draftEntries) do
        local owned, ownershipKnown, ownershipState = currentAppearanceOwned(entry.record, entry.id)
        if not ownershipKnown and ownershipState ~= "Demo" then return false, "BRIDGE_UNAVAILABLE", count end
        if not owned then return false, "NOT_OWNED", count end
    end
    return true, nil, count
end

function State:GetSlotApplyState(slotKey)
    slotKey = slotKey or self.selectedSlot
    if self:IsRequestPending() then return false, "REQUEST_PENDING" end
    local record, definition = self.draftBySlot[slotKey], Lab.SLOT_BY_KEY[slotKey]
    if not record or not definition then return false, "NO_DRAFT" end
    local blockedReason = self:GetBlockedFailureReason("SLOT", slotKey, record)
    if blockedReason then return false, blockedReason end
    local id = collectionId(record)
    if not id then return false, "INVALID_APPEARANCE" end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    if not bridgeCategoryReady(13) then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local owned, ownershipKnown, ownershipState = currentAppearanceOwned(record, id)
    if not ownershipKnown and ownershipState ~= "Demo" then return false, "BRIDGE_UNAVAILABLE" end
    if not owned then return false, "NOT_OWNED" end
    return true
end

function State:GetSetApplyState(useCachedRecord)
    if self:IsRequestPending() then return false, "REQUEST_PENDING" end
    local record = useCachedRecord and self.presetRecord or self:RefreshPresetRecord()
    if not record then return false, "NO_PRESET" end
    local blockedReason = self:GetBlockedFailureReason("SET")
    if blockedReason then return false, blockedReason end
    if not collectionId(record) then return false, "INVALID_REQUEST" end
    if record.scSelectedVariantMissing then return false, "INVALID_REQUEST" end
    local variantOwned, variantOwnedCount, variantRequiredCount, variantReason = selectedVariantOwned(record)
    if not SC.Bridge or type(SC.Bridge.ApplySet) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE", variantOwnedCount, variantRequiredCount
    end
    if not bridgeCategoryReady(14) then
        return false, "BRIDGE_UNAVAILABLE", variantOwnedCount, variantRequiredCount
    end
    if record.ownershipKnown == false then
        return false, "BRIDGE_UNAVAILABLE", variantOwnedCount, variantRequiredCount
    end
    if not variantOwned then
        return false, variantReason or "NOT_OWNED", variantOwnedCount, variantRequiredCount
    end
    return true, nil, variantOwnedCount, variantRequiredCount
end

function State:GetSlotPreviewItemId(slotKey)
    if self.presetRecord then
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            if member.slotKey == slotKey then
                local itemId = getMemberItemId(member)
                if itemId then return itemId, true, "PRESET" end
            end
        end
    end
    local draft = self.draftBySlot[slotKey]
    if draft then return recordItemId(draft), true, "DRAFT" end
    local applied = self.appliedBySlot and self.appliedBySlot[slotKey]
    if applied then return recordItemId(applied), false, "APPLIED" end
    local equipped = self.equippedBySlot[slotKey]
    return equipped, false, equipped and "EQUIPPED" or "EMPTY"
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
        local itemId = recordItemId(self.draftBySlot[definition.key] or
            (self.appliedBySlot and self.appliedBySlot[definition.key]))
        if itemId then items[#items + 1] = itemId end
    end
    return items
end

function State:BeginApply()
    local slotKey = self.selectedSlot
    local canApply, stateReason = self:GetSlotApplyState(slotKey)
    if not canApply then
        if stateReason == "REQUEST_PENDING" then return false, stateReason end
        return self:FailApply("SLOT", slotKey, stateReason)
    end
    local record, definition = self.draftBySlot[slotKey], Lab.SLOT_BY_KEY[slotKey]
    local appearanceCollectionId = collectionId(record)
    local baseRevision = currentRevision()
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "SLOT", slot = slotKey,
        record = record, revision = baseRevision, token = requestToken,
    }
    self:Notify("REQUESTING")
    local requestId = SC.Bridge.ApplyAppearance(appearanceCollectionId, definition.inventorySlot, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if applyAccepted(ok, reason) then
            self:CompleteApply("SLOT", slotKey, reason)
            return
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

function State:BeginApplyDraft()
    local canApply, reason = self:GetDraftApplyState()
    if not canApply then
        if reason == "REQUEST_PENDING" then return false, reason end
        return self:FailApply("DRAFT", self.selectedSlot, reason)
    end

    local queue = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if record then
            queue[#queue + 1] = {
                slot = definition.key,
                inventorySlot = definition.inventorySlot,
                record = record,
                collectionId = collectionId(record),
            }
        end
    end

    local baseRevision = currentRevision()
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "DRAFT", slot = queue[1] and queue[1].slot,
        queue = queue, index = 0, total = #queue, revision = baseRevision, token = requestToken,
    }
    self:Notify("REQUESTING_DRAFT")

    local function applyNext()
        if not self.requestState or self.requestState.token ~= requestToken then return end
        local nextIndex = (tonumber(self.requestState.index) or 0) + 1
        if nextIndex > #queue then
            self:CompleteApply("DRAFT", nil, "ACCEPTED", { appliedCount = #queue })
            return
        end

        local entry = queue[nextIndex]
        self.requestState.index = nextIndex
        self.requestState.slot = entry.slot
        self.requestState.record = entry.record
        self:Notify("REQUEST_PROGRESS")

        local requestId = SC.Bridge.ApplyAppearance(entry.collectionId, entry.inventorySlot, function(ok, callbackReason)
            if not self.requestState or self.requestState.token ~= requestToken then return end
            if applyAccepted(ok, callbackReason) then
                self:StoreAppliedRecord(entry.slot, entry.record)
                self.draftBySlot[entry.slot], self.dirtySlots[entry.slot] = nil, nil
                applyNext()
                return
            end
            self.requestState.status = "FAILED"
            self.requestState.reason = callbackReason or "UNKNOWN"
            self.requestState.slot = entry.slot
            self:Notify("REQUEST_RESULT")
        end)
        if self.requestState and self.requestState.token == requestToken
            and self.requestState.index == nextIndex and self.requestState.status == "REQUESTING" then
            self.requestState.requestId = requestId
        end
        if not requestId and self.requestState and self.requestState.token == requestToken
            and self.requestState.index == nextIndex and self.requestState.status == "REQUESTING" then
            self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
            self.requestState.slot = entry.slot
            self:Notify("REQUEST_RESULT")
        end
    end

    applyNext()
    local failureReason = self.requestState and self.requestState.reason
    return self.requestState and self.requestState.status ~= "FAILED", failureReason
end

function State:BeginApplySet()
    local canApply, stateReason = self:GetSetApplyState()
    if not canApply then
        if stateReason == "REQUEST_PENDING" then return false, stateReason end
        return self:FailApply("SET", nil, stateReason)
    end
    local record = self.presetRecord
    local setCollectionId = collectionId(record)
    local variant = getSelectedVariant(record)
    local baseRevision = currentRevision()
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "SET", record = record,
        revision = baseRevision, token = requestToken,
    }
    self:Notify("REQUESTING_SET")
    local requestId = SC.Bridge.ApplySet(setCollectionId, variant and variant.variantOrdinal or nil, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if applyAccepted(ok, reason) then
            self:CompleteApply("SET", nil, reason)
            return
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

function State:MarkClosed()
    self.preservedOnClose = self:HasDraft()
    local status = self.requestState and self.requestState.status
    if status ~= "CONFIRM_CLEAR" and status ~= "CONFIRM_SWITCH_EQUIPPED" and
        status ~= "CONFIRM_SET_PRESET" then
        return
    end
    if self.presetRecord then
        self.requestState = { status = "LOCAL_PRESET", record = self.presetRecord, revision = currentRevision() }
        return
    end
    local remainingSlot = firstDirtySlot(self.dirtySlots)
    self.requestState = remainingSlot
        and { status = "LOCAL_DRAFT", slot = remainingSlot, revision = currentRevision() }
        or { status = "IDLE", revision = currentRevision() }
end
