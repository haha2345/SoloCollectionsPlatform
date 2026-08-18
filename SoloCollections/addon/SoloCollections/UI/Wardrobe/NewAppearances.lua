local SC = SoloCollections

SC.NewAppearances = SC.NewAppearances or {}
local New = SC.NewAppearances

local NEW_TYPE_ID = 20
local APPEARANCE_TYPE_ID = 13
local FADE_STEP = 0.035
local pendingSeen = {}
local pendingClearAll = false
local fadeDriver

local function appearanceTypeId()
    local CS = SC.CollectionState
    if CS and CS.GetTypeId then
        return CS.GetTypeId("APPEARANCES") or APPEARANCE_TYPE_ID
    end
    return APPEARANCE_TYPE_ID
end

local function newTypeId()
    local CS = SC.CollectionState
    if CS and CS.GetTypeId then
        return CS.GetTypeId("appearance-new") or NEW_TYPE_ID
    end
    return NEW_TYPE_ID
end

local slotById

local function rebuildSlotIndex()
    slotById = {}
    local Catalog = SC.Catalog
    if not Catalog then
        return
    end
    -- The compact wardrobe store exposes an id->slot map directly; avoid
    -- materializing every appearance record just to learn slots.
    if Catalog.GetAppearanceSlotIndex then
        slotById = Catalog.GetAppearanceSlotIndex() or {}
        return
    end
    if not Catalog.Get then
        return
    end
    for _, record in ipairs(Catalog.Get("APPEARANCES") or {}) do
        local id = tonumber(record.id or record.collectionId)
        if id then
            slotById[id] = record.slot
        end
    end
end

local function slotFor(collectionId)
    collectionId = tonumber(collectionId)
    if not collectionId then
        return nil
    end
    if not slotById then
        rebuildSlotIndex()
    end
    return slotById[collectionId]
end

local function ownedNewSet()
    local CS = SC.CollectionState
    if not CS or not CS.GetOwnedSet then
        return nil
    end
    return CS.GetOwnedSet(newTypeId())
end

local function authoritativeTotal()
    local owned = ownedNewSet()
    if not owned then
        return 0
    end
    local count = 0
    for _, isOwned in pairs(owned) do
        if isOwned then
            count = count + 1
        end
    end
    return count
end

local function sweepPending()
    if pendingClearAll and authoritativeTotal() == 0 then
        pendingClearAll = false
        pendingSeen = {}
    end
end

local function notifyPages()
    if SC.UI and SC.UI.RefreshActivePage then
        SC.UI.RefreshActivePage()
    end
end

function New.IsNew(collectionId)
    sweepPending()
    collectionId = tonumber(collectionId)
    if not collectionId or pendingClearAll or pendingSeen[collectionId] then
        return false
    end
    local CS = SC.CollectionState
    return CS and CS.IsOwnedByType and CS.IsOwnedByType(newTypeId(), collectionId) or false
end

function New.CountForSlot(slotKey)
    sweepPending()
    if pendingClearAll then
        return 0
    end
    local owned = ownedNewSet()
    if not owned then
        return 0
    end
    local count = 0
    for collectionId, isOwned in pairs(owned) do
        local id = tonumber(collectionId)
        if isOwned and id and not pendingSeen[id] and (not slotKey or slotFor(id) == slotKey) then
            count = count + 1
        end
    end
    return count
end

function New.Total()
    return New.CountForSlot(nil)
end

function New.MarkSeen(collectionId)
    collectionId = tonumber(collectionId)
    if not collectionId or not New.IsNew(collectionId) then
        return false
    end
    pendingSeen[collectionId] = true
    local Bridge = SC.Bridge
    if not Bridge or not Bridge.RequestSC2Action then
        pendingSeen[collectionId] = nil
        return false
    end
    Bridge.RequestSC2Action(appearanceTypeId(), collectionId, "MARK_SEEN", nil, function(ok)
        if not ok then
            pendingSeen[collectionId] = nil
            notifyPages()
        end
    end)
    return true
end

function New.MarkAllSeen()
    if pendingClearAll or New.Total() <= 0 then
        return false
    end
    pendingClearAll = true
    local Bridge = SC.Bridge
    if not Bridge or not Bridge.RequestSC2Action then
        pendingClearAll = false
        return false
    end
    Bridge.RequestSC2Action(appearanceTypeId(), 1, "MARK_ALL_SEEN", nil, function(ok)
        if not ok then
            pendingClearAll = false
            notifyPages()
        end
    end)
    return true
end

function New.OnDelta(delta)
    if type(delta) ~= "table" or tonumber(delta.typeId) ~= tonumber(newTypeId()) then
        return
    end
    local collectionId = tonumber(delta.collectionId)
    if collectionId and delta.operation == "R" then
        pendingSeen[collectionId] = nil
    end
    if New.Total() == 0 then
        pendingClearAll = false
        pendingSeen = {}
    end
end

local function startGoldFlash(parent)
    local flash = parent and parent.scNewFlash
    if not flash then
        return
    end
    flash:SetAlpha(0.95)
    flash:Show()
    local elapsed = 0
    local pulses = 0
    flash:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        local phase = elapsed / 0.12
        if phase >= 1 then
            elapsed = 0
            pulses = pulses + 1
            if pulses >= 2 then
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(0)
                self:Hide()
                return
            end
            phase = 0
        end
        self:SetAlpha(0.95 - phase * 0.75)
    end)
end

function New.AttachCardBadge(parent)
    if not parent then
        return nil
    end
    local flash = CreateFrame("Frame", nil, parent)
    flash:SetWidth(28)
    flash:SetHeight(16)
    flash:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 2, 22)
    flash:SetFrameLevel(parent:GetFrameLevel() + 7)
    local flashTexture = flash:CreateTexture(nil, "OVERLAY")
    flashTexture:SetAllPoints(flash)
    flashTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    flashTexture:SetVertexColor(1, 0.82, 0.20, 0.9)
    flash:Hide()
    parent.scNewFlash = flash

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetWidth(24)
    badge:SetHeight(14)
    badge:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 3, 23)
    badge:SetFrameLevel(parent:GetFrameLevel() + 8)
    local background = badge:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(badge)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.75, 0.12, 0.10, 0.92)
    local label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetAllPoints(badge)
    label:SetJustifyH("CENTER")
    label:SetText("新")
    label:SetTextColor(1, 0.92, 0.55)
    badge:Hide()
    parent.scNewBadge = badge
    return badge
end

function New.UpdateCardBadge(parent, collectionId)
    local badge = parent and parent.scNewBadge
    if not badge then
        return
    end
    if New.IsNew(collectionId) then
        badge:SetAlpha(1)
        badge:Show()
        if parent.scNewFlashId ~= tonumber(collectionId) then
            parent.scNewFlashId = tonumber(collectionId)
            startGoldFlash(parent)
        end
    else
        parent.scNewFlashId = nil
        if parent.scNewFlash then
            parent.scNewFlash:Hide()
        end
        badge:Hide()
    end
end

function New.AttachSlotBadge(button)
    if not button then
        return nil
    end
    local badge = CreateFrame("Frame", nil, button)
    badge:SetWidth(16)
    badge:SetHeight(16)
    badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 5, 5)
    badge:SetFrameLevel(button:GetFrameLevel() + 8)
    local background = badge:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(badge)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.82, 0.10, 0.10, 0.96)
    local label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetAllPoints(badge)
    label:SetJustifyH("CENTER")
    label:SetTextColor(1, 1, 1)
    badge.scLabel = label
    badge:Hide()
    button.scNewCountBadge = badge
    return badge
end

function New.UpdateSlotBadge(button, slotKey)
    local badge = button and button.scNewCountBadge
    if not badge then
        return
    end
    local count = New.CountForSlot(slotKey)
    if count > 0 then
        badge.scLabel:SetText(count > 99 and "99" or tostring(count))
        badge:Show()
    else
        badge:Hide()
    end
end

function New.RefreshSlotBadges(page)
    if not page or not page.scSlotButtons then
        return
    end
    for slotKey, button in pairs(page.scSlotButtons) do
        New.UpdateSlotBadge(button, slotKey)
    end
    if page.scClearNewButton then
        if New.Total() > 0 then
            page.scClearNewButton:Show()
        else
            page.scClearNewButton:Hide()
        end
    end
end

local function collectVisibleBadges(page)
    local badges = {}
    if page and page.scItemModels then
        for _, itemModel in ipairs(page.scItemModels) do
            local badge = itemModel.scHitFrame and itemModel.scHitFrame.scNewBadge or itemModel.scNewBadge
            if badge and badge:IsShown() then
                badges[#badges + 1] = badge
            end
        end
    end
    return badges
end

function New.ClearAll(page)
    local badges = collectVisibleBadges(page)
    if not New.MarkAllSeen() and #badges == 0 then
        New.RefreshSlotBadges(page)
        return
    end
    if #badges == 0 then
        New.RefreshSlotBadges(page)
        return
    end
    if fadeDriver then
        fadeDriver:SetScript("OnUpdate", nil)
    end
    local index = 1
    local elapsed = 0
    fadeDriver = fadeDriver or CreateFrame("Frame")
    fadeDriver:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < FADE_STEP then
            return
        end
        elapsed = 0
        local badge = badges[index]
        if badge then
            badge:SetAlpha(1)
            badge:Hide()
            index = index + 1
            return
        end
        self:SetScript("OnUpdate", nil)
        New.RefreshSlotBadges(page)
    end)
end
