local SETUP_DELAY = 3.0
local LOAD_DELAY = 1.25
local CAMERA_SETTLE_DELAY = 0.75
local PAGE_HOLD_DELAY = 1.5
local DIRECT_DISPLAY_REQUEST_BASE = 0x6F000000
local EXPECTED_VERIFIED_COUNT = 21
local PAGE_SIZE = 9

local driver = CreateFrame("Frame")
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(1180)
panel:SetHeight(690)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(panel)
background:SetTexture("Interface\\Buttons\\WHITE8X8")
background:SetVertexColor(0.012, 0.014, 0.018, 0.98)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", panel, "TOP", 0, -12)
local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)

local cards = {}
for index = 1, PAGE_SIZE do
    local row = math.floor((index - 1) / 3)
    local column = (index - 1) % 3
    local card = CreateFrame("Frame", nil, panel)
    card:SetWidth(370)
    card:SetHeight(198)
    card:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + column * 385, -72 - row * 204)
    local cardBackground = card:CreateTexture(nil, "BACKGROUND")
    cardBackground:SetAllPoints(card)
    cardBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    cardBackground:SetVertexColor(0.035, 0.038, 0.045, 1)
    local model = CreateFrame("PlayerModel", nil, card)
    model:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -24)
    model:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 10)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", card, "TOP", 0, -5)
    card.model = model
    card.label = label
    cards[index] = card
end

local state = {
    phase = "idle",
    page = 1,
    elapsed = 0,
    records = {},
    totalPages = 0,
}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function getVerifiedRecords()
    local records = {}
    -- The public wardrobe intentionally omits unobtainable appearances.  This
    -- regression matrix is instead scoped to the complete reviewed presentation
    -- set, including the one synthetic weapon that is not player-obtainable.
    local generated = SoloCollections and SoloCollections.GeneratedCatalog
    for _, collection in ipairs(generated and generated.collections or {}) do
        if collection.typeKey == "appearance" and collection.renderMode == "STANDALONE"
            and collection.presentationStatus == "verified"
            and tonumber(collection.syntheticDisplayId) and type(collection.modelPath) == "string"
            and type(collection.autoCamera or collection.m2Camera) == "table" then
            table.insert(records, {
                id = collection.collectionId,
                itemId = collection.displayItemId,
                weaponType = collection.weaponType,
                weaponCategory = collection.weaponCategory,
                syntheticDisplayId = collection.syntheticDisplayId,
                modelPath = collection.modelPath,
                modelScale = collection.modelScale,
                modelPosition = collection.modelPosition,
                autoCamera = collection.autoCamera,
                m2Camera = collection.m2Camera,
            })
        end
    end
    table.sort(records, function(left, right)
        return (tonumber(left.id) or 0) < (tonumber(right.id) or 0)
    end)
    return records
end

local function applyLight(model)
    if not model or not model.SetLight then return end
    pcall(function()
        model:SetLight(
            true, false,
            -1.0, -0.7, -0.5,
            0.82, 1.0, 1.0, 1.0,
            0.72, 1.0, 0.95, 0.88
        )
    end)
end

local function applyRecordView(model, record)
    if not model or not record then return false end
    applyLight(model)
    local pose = record.autoCamera or record.m2Camera
    local applied = SoloCollections.M2Camera and SoloCollections.M2Camera.Apply
        and SoloCollections.M2Camera.Apply(model, pose)
    if not applied and model.SetCamera then
        pcall(function() model:SetCamera(0) end)
    end
    if model.SetModelScale then pcall(function() model:SetModelScale(record.modelScale or 1.0) end) end
    local position = record.modelPosition or { 0, 0, 0 }
    if model.SetPosition then
        pcall(function() model:SetPosition(position[1] or 0, position[2] or 0, position[3] or 0) end)
    end
    if model.SetRotation then pcall(function() model:SetRotation(0) end) end
    return applied and true or false
end

local function recordForCard(index)
    return state.records[((state.page - 1) * PAGE_SIZE) + index]
end

local function startPage(page)
    state.page = page
    title:SetText(string.format("Stage 4 weapon camera matrix %d/%d", page, state.totalPages))
    subtitle:SetText("21 reviewed standalone weapons; green text means the expected M2 path and camera request settled")
    for index, card in ipairs(cards) do
        local record = recordForCard(index)
        card.model:ClearModel()
        card.model.scRecord = record
        card.model.scCameraApplied = false
        if record then
            pcall(function()
                card.model:SetCreature(DIRECT_DISPLAY_REQUEST_BASE + tonumber(record.syntheticDisplayId))
            end)
            card.label:SetText(string.format("%s  id=%s  pending", record.weaponType or record.weaponCategory or "weapon", record.id))
        else
            card.label:SetText("")
        end
    end
    state.phase = "load"
    state.elapsed = 0
end

local function applyPageCameras()
    for _, card in ipairs(cards) do
        local record = card.model.scRecord
        if record then
            card.model.scCameraApplied = applyRecordView(card.model, record)
        end
    end
    state.phase = "settle"
    state.elapsed = 0
    state.reapplied = false
end

local function pageScreenshotName()
    return string.format("weapon-camera-%02d", state.page)
end

local function recordPage()
    local pageReady = true
    for index, card in ipairs(cards) do
        local record = recordForCard(index)
        if record then
            local actualModel = card.model.GetModel and card.model:GetModel() or nil
            local modelReady = lower(actualModel) == lower(record.modelPath)
            local cameraApplied = card.model.scCameraApplied and true or false
            if not modelReady or not cameraApplied then pageReady = false end
            card.label:SetText(string.format(
                "%s  id=%s  %s",
                record.weaponType or record.weaponCategory or "weapon",
                record.id,
                modelReady and cameraApplied and "READY" or "FAILED"
            ))
            table.insert(SoloCollectionsWeaponCameraAuditDB.rows, {
                page = state.page,
                appearanceId = record.id,
                sourceItemId = record.itemId,
                weaponType = record.weaponType or record.weaponCategory,
                syntheticDisplayId = record.syntheticDisplayId,
                expectedModel = record.modelPath,
                actualModel = actualModel,
                modelReady = modelReady and true or false,
                cameraApplied = cameraApplied,
                screenshot = pageScreenshotName(),
            })
        end
    end
    table.insert(SoloCollectionsWeaponCameraAuditDB.pages, {
        page = state.page,
        ready = pageReady,
        screenshot = pageScreenshotName(),
    })
    if not pageReady then SoloCollectionsWeaponCameraAuditDB.ready = false end
    Screenshot()
    state.phase = "hold"
    state.elapsed = 0
end

local function finishAudit()
    local rows = SoloCollectionsWeaponCameraAuditDB.rows
    local identity = {}
    for _, row in ipairs(rows) do identity[tonumber(row.appearanceId) or 0] = true end
    local identityCount = 0
    for _ in pairs(identity) do identityCount = identityCount + 1 end
    SoloCollectionsWeaponCameraAuditDB.rowCount = #rows
    SoloCollectionsWeaponCameraAuditDB.pageCount = #SoloCollectionsWeaponCameraAuditDB.pages
    SoloCollectionsWeaponCameraAuditDB.completed = true
    SoloCollectionsWeaponCameraAuditDB.requested = false
    SoloCollectionsWeaponCameraAuditDB.completedAt = time()
    SoloCollectionsWeaponCameraAuditDB.ready = SoloCollectionsWeaponCameraAuditDB.ready
        and #rows == EXPECTED_VERIFIED_COUNT
        and #SoloCollectionsWeaponCameraAuditDB.pages == state.totalPages
        and identityCount == EXPECTED_VERIFIED_COUNT
    title:SetText(SoloCollectionsWeaponCameraAuditDB.ready
        and "Stage 4 weapon camera matrix: 21/21 READY - reload to persist"
        or "Stage 4 weapon camera matrix: FAILED")
    state.phase = "complete"
end

local function beginAudit()
    state.records = getVerifiedRecords()
    if #state.records ~= EXPECTED_VERIFIED_COUNT then
        SoloCollectionsWeaponCameraAuditDB.error = "VERIFIED_RECORD_COUNT_" .. tostring(#state.records)
        SoloCollectionsWeaponCameraAuditDB.completed = true
        SoloCollectionsWeaponCameraAuditDB.requested = false
        return
    end
    state.totalPages = math.ceil(#state.records / PAGE_SIZE)
    SoloCollectionsWeaponCameraAuditDB.rows = {}
    SoloCollectionsWeaponCameraAuditDB.pages = {}
    SoloCollectionsWeaponCameraAuditDB.ready = true
    SoloCollectionsWeaponCameraAuditDB.startedAt = time()
    panel:Show()
    startPage(1)
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    SoloCollectionsWeaponCameraAuditDB = SoloCollectionsWeaponCameraAuditDB or { requested = true }
    if SoloCollectionsWeaponCameraAuditDB.requested then
        state.phase = "setup"
        state.elapsed = 0
    elseif SoloCollectionsWeaponCameraAuditDB.completed and not SoloCollectionsWeaponCameraAuditDB.reloadObserved then
        SoloCollectionsWeaponCameraAuditDB.reloadObserved = true
        SoloCollectionsWeaponCameraAuditDB.reloadObservedAt = time()
        panel:Show()
        title:SetText("Stage 4 weapon camera matrix: reload persistence READY")
        subtitle:SetText(string.format("%d rows / %d pages", SoloCollectionsWeaponCameraAuditDB.rowCount or 0, SoloCollectionsWeaponCameraAuditDB.pageCount or 0))
        Screenshot()
    end
end)

driver:SetScript("OnUpdate", function(_, delta)
    if state.phase == "idle" or state.phase == "complete" then return end
    state.elapsed = state.elapsed + delta
    if state.phase == "setup" and state.elapsed >= SETUP_DELAY then
        beginAudit()
    elseif state.phase == "load" and state.elapsed >= LOAD_DELAY then
        applyPageCameras()
    elseif state.phase == "settle" then
        if not state.reapplied and state.elapsed >= 0.30 then
            for _, card in ipairs(cards) do
                if card.model.scRecord then
                    card.model.scCameraApplied = applyRecordView(card.model, card.model.scRecord)
                end
            end
            state.reapplied = true
        end
        if state.elapsed >= CAMERA_SETTLE_DELAY then recordPage() end
    elseif state.phase == "hold" and state.elapsed >= PAGE_HOLD_DELAY then
        if state.page >= state.totalPages then finishAudit() else startPage(state.page + 1) end
    end
end)
