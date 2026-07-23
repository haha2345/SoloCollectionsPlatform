local DATA = SoloCollectionsWeaponShadowAuditData or {}
local REQUEST_BASE = 0x6F000000
local MODEL_WINDOW = 2.00
local RETRIES = { 0.10, 0.25, 0.50 }

local driver = CreateFrame("Frame")
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(420)
panel:SetHeight(440)
panel:SetPoint("CENTER", UIParent, "CENTER", 390, 0)
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

local state = { phase = "idle", index = 1, current = nil, rows = {}, logoutAt = nil }

local function safe(value)
    return string.gsub(tostring(value or ""), "[,\r\n]", "_")
end

local function lower(value)
    return type(value) == "string" and string.lower(value) or ""
end

local function sync()
    SoloCollectionsWeaponShadowAuditDB.csv = table.concat(state.rows, "\n") .. "\n"
    SoloCollectionsWeaponShadowAuditDB.progress = state.index
    SoloCollectionsWeaponShadowAuditDB.total = #DATA.records
end

local function finishRecord(result, actual)
    local current = state.current
    table.insert(state.rows, table.concat({
        current.record.appearanceId,
        current.record.syntheticDisplayId,
        safe(current.record.modelPath),
        safe(actual),
        result,
        current.retries,
        math.floor((GetTime() - current.startedAt) * 1000 + 0.5),
    }, ","))
    state.current = nil
    state.index = state.index + 1
    sync()
    if state.index > #DATA.records then
        state.phase = "complete"
        local ready = 0
        for index = 2, #state.rows do
            if string.find(state.rows[index], ",READY,") then ready = ready + 1 end
        end
        SoloCollectionsWeaponShadowAuditDB.ready = ready
        SoloCollectionsWeaponShadowAuditDB.failed = #DATA.records - ready
        SoloCollectionsWeaponShadowAuditDB.completed = true
        SoloCollectionsWeaponShadowAuditDB.requested = false
        SoloCollectionsWeaponShadowAuditDB.completedAt = time()
        status:SetText(string.format("Shadow audit complete: %d ready / %d failed", ready, #DATA.records - ready))
        if DATA.autoLogout then
            local delay = tonumber(DATA.autoLogoutDelay) or 8
            state.logoutAt = GetTime() + math.max(1, math.min(delay, 60))
            state.phase = "logout"
        end
    end
end

local function request(record)
    model:ClearModel()
    model:SetCreature(REQUEST_BASE + record.syntheticDisplayId)
    if model.SetLight then
        pcall(function()
            model:SetLight(true, false, -1.0, -0.7, -0.5, 0.82, 1.0, 1.0, 1.0, 0.72, 1.0, 0.95, 0.88)
        end)
    end
    if model.SetCamera then pcall(function() model:SetCamera(0) end) end
end

local function startRecord(record)
    request(record)
    state.current = {
        record = record,
        startedAt = GetTime(),
        deadline = GetTime() + MODEL_WINDOW,
        retryIndex = 1,
        retries = 0,
        stablePath = nil,
        stableFrames = 0,
    }
    status:SetText(string.format("Shadow audit %d/%d display=%d", state.index, #DATA.records, record.syntheticDisplayId))
end

local function startAudit()
    state.rows = { "appearanceId,syntheticDisplayId,expectedModel,getModel,status,retryCount,elapsedMs" }
    table.sort(DATA.records, function(left, right) return left.syntheticDisplayId < right.syntheticDisplayId end)
    SoloCollectionsWeaponShadowAuditDB.bundleId = DATA.bundleId or ""
    SoloCollectionsWeaponShadowAuditDB.expected = #DATA.records
    SoloCollectionsWeaponShadowAuditDB.completed = false
    SoloCollectionsWeaponShadowAuditDB.requested = false
    SoloCollectionsWeaponShadowAuditDB.startedAt = time()
    panel:Show()
    sync()
    if #DATA.records == 0 then
        SoloCollectionsWeaponShadowAuditDB.error = "NO_GENERATED_RECORDS"
        SoloCollectionsWeaponShadowAuditDB.completed = true
        state.phase = "complete"
        return
    end
    state.phase = "scan"
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    SoloCollectionsWeaponShadowAuditDB = SoloCollectionsWeaponShadowAuditDB or {}
    if SoloCollectionsWeaponShadowAuditDB.requested then startAudit() end
end)

driver:SetScript("OnUpdate", function()
    if state.phase == "logout" then
        if state.logoutAt and GetTime() >= state.logoutAt then Logout() end
        return
    end
    if state.phase ~= "scan" then return end
    if not state.current then
        startRecord(DATA.records[state.index])
        return
    end
    local current = state.current
    local actual = model:GetModel()
    if lower(actual) == lower(current.record.modelPath) and actual ~= "" then
        if current.stablePath == actual then current.stableFrames = current.stableFrames + 1 else current.stablePath = actual; current.stableFrames = 1 end
        if current.stableFrames >= 2 then finishRecord("READY", actual); return end
    else
        current.stablePath = nil
        current.stableFrames = 0
    end
    local now = GetTime()
    if current.retryIndex <= #RETRIES and now >= current.startedAt + RETRIES[current.retryIndex] then
        request(current.record)
        current.retries = current.retries + 1
        current.retryIndex = current.retryIndex + 1
    end
    if now >= current.deadline then finishRecord("MODEL_TIMEOUT", actual or ""); return end
end)
