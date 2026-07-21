local SETUP_DELAY = 3.0
local LOAD_DELAY = 1.5
local CAMERA_SETTLE_DELAY = 0.75
local PAGE_HOLD_DELAY = 1.5
local DIRECT_DISPLAY_REQUEST_BASE = 0x6F000000

local RACES = {
    { key = "human", token = "Human", family = "race.human" },
    { key = "orc", token = "Orc", family = "race.orc" },
    { key = "dwarf", token = "Dwarf", family = "race.dwarf" },
    { key = "night_elf", token = "NightElf", family = "race.night_elf" },
    { key = "undead", token = "Scourge", family = "race.undead" },
    { key = "tauren", token = "Tauren", family = "race.tauren" },
    { key = "gnome", token = "Gnome", family = "race.gnome" },
    { key = "troll", token = "Troll", family = "race.troll" },
    { key = "blood_elf", token = "BloodElf", family = "race.blood_elf" },
    { key = "draenei", token = "Draenei", family = "race.draenei" },
}
local SEXES = {
    { key = "MALE", unitSex = 2 },
    { key = "FEMALE", unitSex = 3 },
}

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
for index = 1, 9 do
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
    local safe = CreateFrame("Frame", nil, card)
    safe:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -23)
    safe:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 10)
    local safeTexture = safe:CreateTexture(nil, "OVERLAY")
    safeTexture:SetAllPoints(safe)
    safeTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    safeTexture:SetVertexColor(0.08, 0.10, 0.12, 0.20)
    local model = CreateFrame("DressUpModel", nil, safe)
    model:SetAllPoints(safe)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", card, "TOP", 0, -5)
    card.model = model
    card.label = label
    cards[index] = card
end

local state = { phase = "idle", page = 1, elapsed = 0, current = nil, previewItems = {} }

local function itemString(itemId)
    return string.format("item:%d:0:0:0:0:0:0:0", itemId)
end

local function loadPreviewItems()
    local result = {}
    for _, record in ipairs((SoloCollections.Data or {}).Appearances or {}) do
        if record.slot and record.itemId and not result[record.slot] then
            result[record.slot] = record.itemId
        end
    end
    return result
end

local function combination(page)
    local raceIndex = math.floor((page - 1) / 2) + 1
    local sexIndex = ((page - 1) % 2) + 1
    return RACES[raceIndex], SEXES[sexIndex]
end

local function startPage(page)
    local profiles = SoloCollections and SoloCollections.CameraProfiles
    local race, sex = combination(page)
    local modelPath = profiles and profiles.modelPaths
        and profiles.modelPaths[race.family]
        and profiles.modelPaths[race.family][sex.key]
    local displayId = profiles and profiles.previewDisplayIds
        and profiles.previewDisplayIds[race.family]
        and profiles.previewDisplayIds[race.family][sex.key]
    state.current = { race = race, sex = sex, modelPath = modelPath, displayId = displayId, startedAt = GetTime() }
    title:SetText(string.format("Phase 5 camera matrix %02d/20 - %s %s", page, race.key, sex.key))
    subtitle:SetText(string.format("profile %s / %s - green inset is the required safe frame", profiles and profiles.profileVersion or "?", profiles and profiles.profileHash or "?"))
    for index, slot in ipairs((profiles and profiles.slotOrder) or {}) do
        local card = cards[index]
        card.model:ClearModel()
        if displayId then card.model:SetCreature(DIRECT_DISPLAY_REQUEST_BASE + displayId) end
        if card.model.Undress then card.model:Undress() end
        local previewItem = state.previewItems[slot]
        if previewItem and card.model.TryOn then card.model:TryOn(itemString(previewItem)) end
        if card.model.SetSequence then card.model:SetSequence(0) end
        card.label:SetText(string.format("%s  item=%s  sentinel=pending", slot, previewItem or "NONE"))
    end
    state.phase = "load"
    state.elapsed = 0
end

local function reapplyPageCameras()
    local profiles = SoloCollections.CameraProfiles
    local current = state.current
    for index, slot in ipairs(profiles.slotOrder) do
        local sentinel = profiles.GetSentinel(
            current.race.token,
            current.sex.unitSex,
            slot,
            current.race.family
        )
        local model = cards[index].model
        local previewItem = state.previewItems[slot]
        if sentinel and model.SetCamera then
            model:SetCamera(sentinel)
            model:SetCamera(1)
        elseif model.SetCamera then
            model:SetCamera(1)
        end
        cards[index].label:SetText(string.format("%s item=%s sentinel=0x%04X", slot, previewItem or "NONE", sentinel or 0))
    end
end

local function applyPageCameras()
    reapplyPageCameras()
    state.phase = "settle"
    state.elapsed = 0
    state.reapplied = false
end

local function recordPage()
    local profiles = SoloCollections.CameraProfiles
    local current = state.current
    local pageReady = current.modelPath and true or false
    for index, slot in ipairs(profiles.slotOrder) do
        local model = cards[index].model
        local actualPath = model.GetModel and model:GetModel() or nil
        local sentinel = profiles.GetSentinel(current.race.token, current.sex.unitSex, slot, current.race.family)
        local pathReady = type(actualPath) == "string"
            and string.lower(actualPath) == string.lower(current.modelPath or "")
        if not pathReady or not sentinel then pageReady = false end
        table.insert(SoloCollectionsCameraAuditDB.rows, {
            page = state.page,
            raceKey = current.race.key,
            raceToken = current.race.token,
            cameraProfile = current.race.family,
            sex = current.sex.key,
            slot = slot,
            sentinel = sentinel,
            previewDisplayId = current.displayId,
            previewItemId = state.previewItems[slot],
            expectedModel = current.modelPath,
            actualModel = actualPath,
            modelReady = pathReady and true or false,
            screenshot = string.format("camera-%02d", state.page),
            visualReview = "PENDING",
            status = (current.race.key == "human" and current.sex.key == "FEMALE") and "verified" or "scaled",
        })
    end
    table.insert(SoloCollectionsCameraAuditDB.pages, {
        page = state.page,
        raceKey = current.race.key,
        sex = current.sex.key,
        ready = pageReady,
        screenshot = string.format("camera-%02d", state.page),
    })
    if not pageReady then SoloCollectionsCameraAuditDB.ready = false end
    Screenshot()
    state.phase = "hold"
    state.elapsed = 0
end

local function finishAudit()
    local profiles = SoloCollections.CameraProfiles
    SoloCollectionsCameraAuditDB.unknownFallback = {
        syntheticRace = profiles.GetSentinel("SyntheticRace", 2, "HEAD", "race.synthetic") == nil,
        unknownSex = profiles.GetSentinel("Human", 1, "HEAD", "race.human") == nil,
        assetMismatch = profiles.GetSentinel("Human", 3, "HEAD", "race.hd-human") == nil,
    }
    SoloCollectionsCameraAuditDB.completed = true
    SoloCollectionsCameraAuditDB.requested = false
    SoloCollectionsCameraAuditDB.completedAt = time()
    SoloCollectionsCameraAuditDB.rowCount = #SoloCollectionsCameraAuditDB.rows
    SoloCollectionsCameraAuditDB.pageCount = #SoloCollectionsCameraAuditDB.pages
    SoloCollectionsCameraAuditDB.ready = SoloCollectionsCameraAuditDB.ready
        and SoloCollectionsCameraAuditDB.rowCount == 180
        and SoloCollectionsCameraAuditDB.pageCount == 20
        and SoloCollectionsCameraAuditDB.unknownFallback.syntheticRace
        and SoloCollectionsCameraAuditDB.unknownFallback.unknownSex
        and SoloCollectionsCameraAuditDB.unknownFallback.assetMismatch
    title:SetText(SoloCollectionsCameraAuditDB.ready
        and "Phase 5 camera matrix: 180/180 READY - reload to persist"
        or "Phase 5 camera matrix: FAILED")
    state.phase = "complete"
end

local function beginAudit()
    local profiles = SoloCollections and SoloCollections.CameraProfiles
    if not profiles or profiles.profileVersion ~= 1 or type(profiles.profileHash) ~= "string"
        or #profiles.slotOrder ~= 9 or type(profiles.previewDisplayIds) ~= "table" then
        SoloCollectionsCameraAuditDB.error = "CAMERA_PROFILE_CONTRACT_MISSING"
        SoloCollectionsCameraAuditDB.completed = true
        SoloCollectionsCameraAuditDB.requested = false
        return
    end
    profiles.SetMode("Generated")
    state.previewItems = loadPreviewItems()
    for _, slot in ipairs(profiles.slotOrder) do
        if not state.previewItems[slot] then
            SoloCollectionsCameraAuditDB.error = "PREVIEW_ITEM_MISSING_" .. slot
            SoloCollectionsCameraAuditDB.completed = true
            SoloCollectionsCameraAuditDB.requested = false
            return
        end
    end
    SoloCollectionsCameraAuditDB.rows = {}
    SoloCollectionsCameraAuditDB.pages = {}
    SoloCollectionsCameraAuditDB.ready = true
    SoloCollectionsCameraAuditDB.profileVersion = profiles.profileVersion
    SoloCollectionsCameraAuditDB.profileHash = profiles.profileHash
    SoloCollectionsCameraAuditDB.screenWidth = GetScreenWidth()
    SoloCollectionsCameraAuditDB.screenHeight = GetScreenHeight()
    SoloCollectionsCameraAuditDB.startedAt = time()
    panel:Show()
    state.page = 1
    startPage(state.page)
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    SoloCollectionsCameraAuditDB = SoloCollectionsCameraAuditDB or { requested = true }
    if SoloCollectionsCameraAuditDB.requested then
        state.phase = "setup"
        state.elapsed = 0
    elseif SoloCollectionsCameraAuditDB.completed and not SoloCollectionsCameraAuditDB.reloadObserved then
        SoloCollectionsCameraAuditDB.reloadObserved = true
        SoloCollectionsCameraAuditDB.reloadObservedAt = time()
        panel:Show()
        title:SetText("Phase 5 camera matrix: reload persistence READY")
        subtitle:SetText(string.format("%d rows / %d pages", SoloCollectionsCameraAuditDB.rowCount or 0, SoloCollectionsCameraAuditDB.pageCount or 0))
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
            reapplyPageCameras()
            state.reapplied = true
        end
        if state.elapsed >= CAMERA_SETTLE_DELAY then recordPage() end
    elseif state.phase == "hold" and state.elapsed >= PAGE_HOLD_DELAY then
        state.page = state.page + 1
        if state.page > 20 then finishAudit() else startPage(state.page) end
    end
end)
