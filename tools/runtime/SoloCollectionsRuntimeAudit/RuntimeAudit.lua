local SC = SoloCollections
local Audit = {}

local REQUEST_INTERVAL = 0.25
local REQUEST_TIMEOUT = 5
local MODEL_WINDOW = 2
local MODEL_RETRY_DELAYS = { 0.10, 0.25, 0.50 }

local driver = CreateFrame("Frame")
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(360)
panel:SetHeight(380)
panel:SetPoint("CENTER", UIParent, "CENTER", 410, 0)
panel:SetFrameStrata("DIALOG")

local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(panel)
background:SetTexture("Interface\\Buttons\\WHITE8X8")
background:SetVertexColor(0.02, 0.02, 0.02, 0.92)

local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOP", panel, "TOP", 0, -10)
statusText:SetText("SoloCollections RuntimeAudit")

local model = CreateFrame("PlayerModel", nil, panel)
model:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -34)
model:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
model:SetRotation(0.4)

panel:Hide()

local state = {
    phase = "idle",
    records = {},
    index = 0,
    generation = 0,
    nextRequestAt = 0,
    pending = nil,
    model = nil,
    csv = {},
}

local function safeCsv(value)
    value = tostring(value or "")
    value = string.gsub(value, "[,\r\n]", "_")
    return value
end

local function syncDatabase()
    SoloCollectionsRuntimeAuditDB.csv = table.concat(state.csv, "\n") .. "\n"
    SoloCollectionsRuntimeAuditDB.progress = state.index
    SoloCollectionsRuntimeAuditDB.total = #state.records
end

local function appendResult(record, previewStatus, modelStatus, modelPath, retries, elapsedMs)
    table.insert(state.csv, table.concat({
        tostring(record.typeId),
        tostring(record.collectionId),
        tostring(record.previewCreatureEntry),
        safeCsv(previewStatus),
        safeCsv(modelStatus),
        safeCsv(modelPath),
        tostring(retries or 0),
        tostring(elapsedMs or 0),
    }, ","))
    syncDatabase()
end

local function generatedRecords()
    local records = {}
    for _, record in ipairs((SC.GeneratedCatalog or {}).collections or {}) do
        local typeId = record.typeKey == "mount" and 10 or
            (record.typeKey == "companion" and 11 or nil)
        if typeId and
            type(record.collectionId) == "number" and record.collectionId > 0 and
            type(record.previewCreatureEntry) == "number" and record.previewCreatureEntry > 0 then
            table.insert(records, {
                typeId = typeId,
                collectionId = record.collectionId,
                previewCreatureEntry = record.previewCreatureEntry,
            })
        end
    end
    return records
end

local function bridgeReady()
    local bridge = SC.Bridge
    local collectionState = SC.CollectionState
    return bridge and bridge.sc2Connected and collectionState and
        collectionState.GetState and collectionState.GetState() == "Ready" and
        collectionState.categories and collectionState.categories[10] and
        collectionState.categories[10].state == "Ready" and
        collectionState.categories[11] and collectionState.categories[11].state == "Ready"
end

local function finishAudit()
    state.phase = "complete"
    syncDatabase()
    SoloCollectionsRuntimeAuditDB.requested = false
    SoloCollectionsRuntimeAuditDB.completed = true
    SoloCollectionsRuntimeAuditDB.completedAt = time()
    SoloCollectionsRuntimeAuditDB.readyCount = 0
    SoloCollectionsRuntimeAuditDB.failedCount = 0
    for index = 2, #state.csv do
        if string.find(state.csv[index], ",READY,") then
            SoloCollectionsRuntimeAuditDB.readyCount = SoloCollectionsRuntimeAuditDB.readyCount + 1
        else
            SoloCollectionsRuntimeAuditDB.failedCount = SoloCollectionsRuntimeAuditDB.failedCount + 1
        end
    end
    statusText:SetText(string.format(
        "RuntimeAudit complete: %d ready / %d failed - exit WoW normally to save",
        SoloCollectionsRuntimeAuditDB.readyCount,
        SoloCollectionsRuntimeAuditDB.failedCount
    ))
end

local function finishRecord(record, previewStatus, modelStatus, modelPath, retries, startedAt)
    local elapsedMs = math.floor((GetTime() - startedAt) * 1000 + 0.5)
    appendResult(record, previewStatus, modelStatus, modelPath, retries, elapsedMs)
    state.pending = nil
    state.model = nil
    state.index = state.index + 1
    state.nextRequestAt = math.max(state.nextRequestAt, GetTime())
    if state.index > #state.records then
        finishAudit()
    end
end

local function beginModel(record, startedAt, previewStatus)
    model:ClearModel()
    model:SetCreature(record.previewCreatureEntry)
    state.model = {
        record = record,
        startedAt = startedAt,
        previewStatus = previewStatus,
        deadline = GetTime() + MODEL_WINDOW,
        retryIndex = 1,
        nextRetryAt = GetTime() + MODEL_RETRY_DELAYS[1],
        retries = 0,
        stablePath = nil,
        stableFrames = 0,
    }
end

local function requestRecord(record)
    state.generation = state.generation + 1
    local generation = state.generation
    local startedAt = GetTime()
    state.nextRequestAt = startedAt + REQUEST_INTERVAL
    state.pending = {
        record = record,
        generation = generation,
        startedAt = startedAt,
        deadline = startedAt + REQUEST_TIMEOUT,
    }
    statusText:SetText(string.format(
        "RuntimeAudit %d/%d type=%d collection=%d",
        state.index, #state.records, record.typeId, record.collectionId
    ))
    SC.Bridge.RequestCreaturePreview(record.typeId, record.collectionId, function(ok, reason)
        if generation ~= state.generation then
            SoloCollectionsRuntimeAuditDB.staleGenerationDiscarded = true
            return
        end
        if not state.pending or state.pending.generation ~= generation then
            return
        end
        state.pending = nil
        if not ok then
            finishRecord(record, reason or "ERROR", "NOT_ATTEMPTED", "", 0, startedAt)
            return
        end
        beginModel(record, startedAt, reason or "ACCEPTED")
    end)
end

local function beginStaleGenerationProbe()
    local record = state.records[1]
    state.generation = state.generation + 1
    local generation = state.generation
    state.phase = "stale_probe"
    state.staleDeadline = GetTime() + REQUEST_TIMEOUT
    SC.Bridge.RequestCreaturePreview(record.typeId, record.collectionId, function()
        if generation ~= state.generation then
            SoloCollectionsRuntimeAuditDB.staleGenerationDiscarded = true
        end
        state.phase = "scan"
    end)
    state.generation = state.generation + 1
end

local function startAudit()
    state.records = generatedRecords()
    state.index = 1
    state.csv = {
        "typeId,collectionId,previewCreatureEntry,previewStatus,modelStatus,getModel,retryCount,elapsedMs",
    }
    SoloCollectionsRuntimeAuditDB.completed = false
    SoloCollectionsRuntimeAuditDB.staleGenerationDiscarded = false
    SoloCollectionsRuntimeAuditDB.startedAt = time()
    SoloCollectionsRuntimeAuditDB.expectedMounts = 281
    SoloCollectionsRuntimeAuditDB.expectedCompanions = 24
    panel:Show()
    syncDatabase()
    beginStaleGenerationProbe()
end

local function updateModel(now)
    local current = state.model
    local path = model:GetModel()
    if type(path) == "string" and path ~= "" then
        if current.stablePath == path then
            current.stableFrames = current.stableFrames + 1
        else
            current.stablePath = path
            current.stableFrames = 1
        end
        if current.stableFrames >= 2 then
            finishRecord(current.record, current.previewStatus, "READY", path,
                current.retries, current.startedAt)
            return
        end
    else
        current.stablePath = nil
        current.stableFrames = 0
    end

    if current.retryIndex <= #MODEL_RETRY_DELAYS and now >= current.nextRetryAt then
        model:SetCreature(current.record.previewCreatureEntry)
        current.retries = current.retries + 1
        current.retryIndex = current.retryIndex + 1
        if current.retryIndex <= #MODEL_RETRY_DELAYS then
            current.nextRetryAt = current.startedAt + MODEL_RETRY_DELAYS[current.retryIndex]
        end
    end
    if now >= current.deadline then
        finishRecord(current.record, current.previewStatus, "MODEL_TIMEOUT", path or "",
            current.retries, current.startedAt)
    end
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    SoloCollectionsRuntimeAuditDB = SoloCollectionsRuntimeAuditDB or {}
    if SoloCollectionsRuntimeAuditDB.requested then
        state.phase = "waiting"
        state.waitDeadline = GetTime() + 30
    end
end)

driver:SetScript("OnUpdate", function()
    local now = GetTime()
    if state.phase == "idle" then
        return
    elseif state.phase == "waiting" then
        if bridgeReady() then
            startAudit()
        elseif now >= state.waitDeadline then
            SoloCollectionsRuntimeAuditDB.completed = true
            SoloCollectionsRuntimeAuditDB.requested = false
            SoloCollectionsRuntimeAuditDB.error = "SC2_NOT_READY"
            state.phase = "complete"
        end
    elseif state.phase == "stale_probe" then
        if now >= state.staleDeadline then
            state.phase = "scan"
        end
    elseif state.phase == "scan" then
        if state.model then
            updateModel(now)
        elseif state.pending then
            if now >= state.pending.deadline then
                local pending = state.pending
                finishRecord(pending.record, "TIMEOUT", "NOT_ATTEMPTED", "", 0, pending.startedAt)
            end
        elseif state.index <= #state.records and now >= state.nextRequestAt then
            requestRecord(state.records[state.index])
        end
    end
end)

Audit.RequestInterval = REQUEST_INTERVAL
Audit.RequestTimeout = REQUEST_TIMEOUT
Audit.ModelWindow = MODEL_WINDOW
SC.RuntimeAudit = Audit
