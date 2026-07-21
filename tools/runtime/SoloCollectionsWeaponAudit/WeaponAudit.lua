local SC = SoloCollections
local DIRECT_DISPLAY_REQUEST_BASE = 0x6F000000
local MODEL_WINDOW = 2
local RETRIES = { 0.10, 0.25, 0.50 }

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
local status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
status:SetPoint("TOP", panel, "TOP", 0, -10)
local model = CreateFrame("PlayerModel", nil, panel)
model:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -34)
model:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
panel:Hide()

local state = { phase = "idle", records = {}, index = 1, rows = {}, current = nil }

local function safe(value)
    return string.gsub(tostring(value or ""), "[,\r\n]", "_")
end

local function sync()
    SoloCollectionsWeaponAuditDB.csv = table.concat(state.rows, "\n") .. "\n"
    SoloCollectionsWeaponAuditDB.progress = state.index
    SoloCollectionsWeaponAuditDB.total = #state.records
end

local function finishRecord(result, path)
    local current = state.current
    table.insert(state.rows, table.concat({
        current.record.id,
        current.record.syntheticDisplayId,
        safe(current.record.modelPath),
        safe(path),
        result,
        current.retries,
        math.floor((GetTime() - current.startedAt) * 1000 + 0.5),
    }, ","))
    state.current = nil
    state.index = state.index + 1
    sync()
    if state.index > #state.records then
        state.phase = "complete"
        local ready = 0
        for index = 2, #state.rows do
            if string.find(state.rows[index], ",READY,") then ready = ready + 1 end
        end
        SoloCollectionsWeaponAuditDB.ready = ready
        SoloCollectionsWeaponAuditDB.failed = #state.records - ready
        SoloCollectionsWeaponAuditDB.completed = true
        SoloCollectionsWeaponAuditDB.requested = false
        SoloCollectionsWeaponAuditDB.completedAt = time()
        status:SetText(string.format("WeaponAudit complete: %d ready / %d failed - exit normally", ready, #state.records - ready))
    end
end

local function startRecord(record)
    model:ClearModel()
    model:SetCreature(DIRECT_DISPLAY_REQUEST_BASE + record.syntheticDisplayId)
    if SC.M2Camera and SC.M2Camera.Apply then SC.M2Camera.Apply(model, record.m2Camera) end
    state.current = {
        record = record,
        startedAt = GetTime(),
        deadline = GetTime() + MODEL_WINDOW,
        retryIndex = 1,
        retries = 0,
        stablePath = nil,
        stableFrames = 0,
    }
    status:SetText(string.format("WeaponAudit %d/%d appearance=%d", state.index, #state.records, record.id))
end

local function startAudit()
    for _, record in ipairs((SC.GeneratedCatalog or {}).collections or {}) do
        if record.typeKey == "appearance" and record.renderMode == "STANDALONE" then
            table.insert(state.records, {
                id = record.collectionId,
                syntheticDisplayId = record.syntheticDisplayId,
                modelPath = record.modelPath,
                m2Camera = record.m2Camera,
            })
        end
    end
    table.sort(state.records, function(left, right) return left.syntheticDisplayId < right.syntheticDisplayId end)
    state.rows = { "appearanceId,syntheticDisplayId,expectedModel,getModel,status,retryCount,elapsedMs" }
    SoloCollectionsWeaponAuditDB.expected = 21
    SoloCollectionsWeaponAuditDB.completed = false
    SoloCollectionsWeaponAuditDB.startedAt = time()
    panel:Show()
    sync()
    if #state.records ~= 21 then
        SoloCollectionsWeaponAuditDB.error = "EXPECTED_21"
        SoloCollectionsWeaponAuditDB.completed = true
        SoloCollectionsWeaponAuditDB.requested = false
        state.phase = "complete"
        return
    end
    state.phase = "scan"
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    SoloCollectionsWeaponAuditDB = SoloCollectionsWeaponAuditDB or {}
    if SoloCollectionsWeaponAuditDB.requested then startAudit() end
end)

driver:SetScript("OnUpdate", function()
    if state.phase ~= "scan" then return end
    local now = GetTime()
    if not state.current then
        startRecord(state.records[state.index])
        return
    end
    local current = state.current
    local path = model:GetModel()
    if type(path) == "string" and path ~= "" then
        if string.lower(path) == string.lower(current.record.modelPath) then
            if current.stablePath == path then current.stableFrames = current.stableFrames + 1 else current.stablePath = path; current.stableFrames = 1 end
            if current.stableFrames >= 2 then finishRecord("READY", path); return end
        else
            current.stablePath = nil
            current.stableFrames = 0
        end
    end
    if current.retryIndex <= #RETRIES and now >= current.startedAt + RETRIES[current.retryIndex] then
        model:SetCreature(DIRECT_DISPLAY_REQUEST_BASE + current.record.syntheticDisplayId)
        if SC.M2Camera and SC.M2Camera.Apply then SC.M2Camera.Apply(model, current.record.m2Camera) end
        current.retries = current.retries + 1
        current.retryIndex = current.retryIndex + 1
    end
    if now >= current.deadline then finishRecord("MODEL_TIMEOUT", path); return end
end)
