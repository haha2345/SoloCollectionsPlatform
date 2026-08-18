local DATA = SoloCollectionsWeaponPresentationAuditData or {}
local SC = SoloCollections

local SETUP_DELAY = 3.0
local MODEL_WINDOW = 3.0
local STABLE_TICKS = 3
local PAGE_HOLD_DELAY = 0.10
local VISUAL_SCREENSHOT_SETTLE_DELAY = 2.0
local PERFORMANCE_PREFLIGHT_DELAY = 0.25
local MAX_PERFORMANCE_ROUNDS = 3
local AUTO_LOGOUT_DEFAULT_SECONDS = 8
local RELOAD_TIMEOUT_SECONDS = 120.0

local driver = CreateFrame("Frame")
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(430)
panel:SetHeight(46)
panel:SetPoint("TOP", UIParent, "TOP", 0, -12)
panel:SetFrameStrata("HIGH")
local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(panel)
background:SetTexture("Interface\\Buttons\\WHITE8X8")
background:SetVertexColor(0.02, 0.02, 0.02, 0.88)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", panel, "TOP", 0, -7)
title:SetText("SoloCollections Weapon Presentation Audit")
local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
statusText:SetPoint("TOP", title, "BOTTOM", 0, -4)
panel:Hide()

local state = {
    phase = "idle",
    elapsed = 0,
    nextIndex = 1,
    records = {},
    pagePairs = {},
    rows = {},
    page = nil,
    pageStartedAt = nil,
    pageDeadline = nil,
    holdUntil = nil,
    logoutAt = nil,
    readyCount = 0,
    unavailableCount = 0,
    failedCount = 0,
    performanceMode = false,
    performanceRounds = 1,
    round = 1,
    performancePageRows = {},
    performanceRoundRows = {},
    roundStartedAt = nil,
    roundMemoryStartKb = 0,
    roundMaxMemoryKb = 0,
    roundPageCount = 0,
    pageMemoryBeforeKb = 0,
    performanceFilterRows = {},
    filterScenarios = {},
    filterScenarioIndex = 0,
    filterPairs = {},
    originalFilters = nil,
    originalQuery = nil,
    originalItemPage = nil,
}

local function safe(value)
    return string.gsub(tostring(value or ""), "[,\r\n]", "_")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function boolText(value)
    return value and "true" or "false"
end

local function setStatus(text)
    statusText:SetText(text or "")
end

local function writeCsv()
    local header = "appearanceId,sourceItemId,slot,weaponType,presentationStatus,syntheticDisplayId,expectedModelPath,actualModelPath,poseSource,readyMilliseconds,failureReason,cardState,iconVisible,reasonVisible,stableTicks,sampleKinds"
    SoloCollectionsWeaponPresentationAuditDB.csv = header .. "\n" .. table.concat(state.rows, "\n") .. "\n"
end

local function luaMemoryKb()
    return collectgarbage and tonumber(collectgarbage("count")) or 0
end

local function poolOnUpdateCounts()
    local hostCount, objectCount = 0, 0
    for _, host in ipairs((state.page and state.page.scItemModels) or {}) do
        if host and host.GetScript and host:GetScript("OnUpdate") then
            hostCount = hostCount + 1
        end
        local objectModel = host and host.scObjectModel
        if objectModel and objectModel.GetScript and objectModel:GetScript("OnUpdate") then
            objectCount = objectCount + 1
        end
    end
    return hostCount, objectCount
end

local function writePerformanceCsv()
    if not state.performanceMode then return end
    local pageHeader = "round,page,firstAppearanceId,lastAppearanceId,recordCount,loadMilliseconds,luaMemoryBeforeKb,luaMemoryAfterKb,luaMemoryDeltaKb,poolSize,hostOnUpdateCount,objectOnUpdateCount,totalOnUpdateCount,generation"
    local roundHeader = "round,pageCount,elapsedMilliseconds,luaMemoryStartKb,luaMemoryEndKb,luaMemoryPeakKb,luaMemoryGrowthKb"
    SoloCollectionsWeaponPresentationAuditDB.performancePageCsv = pageHeader .. "\n"
        .. table.concat(state.performancePageRows, "\n") .. "\n"
    SoloCollectionsWeaponPresentationAuditDB.performanceRoundCsv = roundHeader .. "\n"
        .. table.concat(state.performanceRoundRows, "\n") .. "\n"
    local filterHeader = "scenario,slot,weaponType,page,recordCount,loadMilliseconds,poolSize,hostOnUpdateCount,objectOnUpdateCount,totalOnUpdateCount,generation,generationDelta,crossContamination"
    SoloCollectionsWeaponPresentationAuditDB.performanceFilterCsv = filterHeader .. "\n"
        .. table.concat(state.performanceFilterRows, "\n") .. "\n"
end

local function setFailure(reason)
    SoloCollectionsWeaponPresentationAuditDB = SoloCollectionsWeaponPresentationAuditDB or {}
    SoloCollectionsWeaponPresentationAuditDB.error = tostring(reason or "UNKNOWN")
    SoloCollectionsWeaponPresentationAuditDB.completed = true
    SoloCollectionsWeaponPresentationAuditDB.ready = false
    SoloCollectionsWeaponPresentationAuditDB.requested = false
    SoloCollectionsWeaponPresentationAuditDB.total = #state.records
    SoloCollectionsWeaponPresentationAuditDB.readyCount = state.readyCount
    SoloCollectionsWeaponPresentationAuditDB.unavailableCount = state.unavailableCount
    SoloCollectionsWeaponPresentationAuditDB.failedCount = math.max(1, state.failedCount)
    SoloCollectionsWeaponPresentationAuditDB.completedAt = time()
    writeCsv()
    setStatus("Runtime audit failed: " .. tostring(reason))
    panel:Show()
    state.phase = "complete"
end

local function presentationFilters()
    return {
        collected = true,
        uncollected = true,
        favorites = false,
        classToken = "ALL",
        armorType = "AUTO",
        slot = "ALL",
        weaponType = "AUTO",
    }
end

local function contractError(prefix, expected, actual)
    return prefix .. " expected=" .. safe(expected) .. " actual=" .. safe(actual)
end

local function collectProductionRecords()
    if not SC or not SC.db or not SC.UI or not SC.Catalog or not SC.Catalog.QueryAll then
        return nil, "SOLOCOLLECTIONS_CONTRACT_MISSING"
    end
    local expectedCount = tonumber(DATA.publicCount)
    local sampleOnly = DATA.sampleOnly and true or false
    if type(DATA.records) ~= "table" or not expectedCount or #DATA.records ~= expectedCount then
        return nil, "AUDIT_DATA_COUNT_DRIFT"
    end
    local generated = SC.GeneratedCatalog or {}
    if generated.assetPackVersion ~= DATA.assetPackVersion then
        return nil, contractError("ASSET_PACK_VERSION", DATA.assetPackVersion, generated.assetPackVersion)
    end
    if generated.appearancePresentationHash ~= DATA.appearancePresentationHash then
        return nil, contractError("PRESENTATION_HASH", DATA.appearancePresentationHash, generated.appearancePresentationHash)
    end
    if SC.CollectionState and SC.CollectionState.assetMismatch then
        return nil, "CLIENT_ASSET_MISMATCH"
    end

    local expectedByAppearance = {}
    for _, expected in ipairs(DATA.records) do
        local appearanceId = tonumber(expected.appearanceId)
        if not appearanceId or expectedByAppearance[appearanceId] then
            return nil, "AUDIT_DATA_DUPLICATE_APPEARANCE"
        end
        expectedByAppearance[appearanceId] = expected
    end

    local matched = {}
    local observed = {}
    local allRecords = SC.Catalog.QueryAll("APPEARANCES", "", presentationFilters())
    for _, record in ipairs(allRecords) do
        if record.slot == "MAINHAND" or record.slot == "OFFHAND" then
            local appearanceId = tonumber(record.id)
            local expected = appearanceId and expectedByAppearance[appearanceId] or nil
            if not expected and not sampleOnly then
                return nil, "PUBLIC_WEAPON_NOT_IN_AUDIT_DATA_" .. tostring(record.id)
            end
            if expected and observed[appearanceId] then
                return nil, "DUPLICATE_PUBLIC_WEAPON_" .. tostring(appearanceId)
            end
            if expected then
                observed[appearanceId] = true
            end
            if expected and tonumber(record.itemId) ~= tonumber(expected.displayItemId) then
                return nil, contractError("DISPLAY_ITEM_" .. tostring(appearanceId), expected.displayItemId, record.itemId)
            end
            if expected and record.presentationStatus ~= expected.presentationStatus then
                return nil, contractError("PRESENTATION_STATUS_" .. tostring(appearanceId), expected.presentationStatus, record.presentationStatus)
            end
            if expected and record.assetPackVersion ~= DATA.assetPackVersion then
                return nil, contractError("RECORD_ASSET_PACK_" .. tostring(appearanceId), DATA.assetPackVersion, record.assetPackVersion)
            end
            if expected and expected.presentationStatus == "READY" then
                if record.renderMode ~= "STANDALONE" or record.presentationCapability ~= "DIRECT_DISPLAY_V1" then
                    return nil, "READY_RENDER_CONTRACT_" .. tostring(appearanceId)
                end
                if tonumber(record.syntheticDisplayId) ~= tonumber(expected.syntheticDisplayId) then
                    return nil, contractError("DISPLAY_" .. tostring(appearanceId), expected.syntheticDisplayId, record.syntheticDisplayId)
                end
                if lower(record.modelPath) ~= lower(expected.modelPath) then
                    return nil, contractError("MODEL_PATH_" .. tostring(appearanceId), expected.modelPath, record.modelPath)
                end
            elseif expected and expected.presentationStatus == "UNAVAILABLE" then
                if record.renderMode ~= "UNAVAILABLE" or record.presentationCapability ~= "UNAVAILABLE" then
                    return nil, "UNAVAILABLE_RENDER_CONTRACT_" .. tostring(appearanceId)
                end
                if safe(record.presentationReasonCode) ~= safe(expected.presentationReasonCode) then
                    return nil, contractError("UNAVAILABLE_REASON_" .. tostring(appearanceId), expected.presentationReasonCode, record.presentationReasonCode)
                end
            elseif expected then
                return nil, "UNSUPPORTED_EXPECTED_STATUS_" .. tostring(expected.presentationStatus)
            end
            if expected then
                table.insert(matched, { record = record, expected = expected })
            end
        end
    end
    for appearanceId in pairs(expectedByAppearance) do
        if not observed[appearanceId] then
            return nil, "PUBLIC_WEAPON_MISSING_FROM_CATALOG_" .. tostring(appearanceId)
        end
    end
    if #matched ~= expectedCount then
        return nil, contractError(sampleOnly and "VISUAL_SAMPLE_COUNT" or "PUBLIC_WEAPON_COUNT", expectedCount, #matched)
    end
    table.sort(matched, function(left, right)
        return tonumber(left.record.id) < tonumber(right.record.id)
    end)
    return matched
end

local function pageRecordCount()
    return math.min(#state.records - state.nextIndex + 1, #(state.page.scItemModels or {}))
end

local function buildCurrentPage()
    local records = {}
    state.pagePairs = {}
    local count = pageRecordCount()
    for offset = 0, count - 1 do
        local pair = state.records[state.nextIndex + offset]
        table.insert(records, pair.record)
        state.pagePairs[offset + 1] = {
            pair = pair,
            result = nil,
            actualModelPath = "",
            poseSource = "",
            readyMilliseconds = 0,
            failureReason = "",
            stableTicks = 0,
            lastModelPath = "",
        }
    end
    return records
end

local function beginPage()
    if state.nextIndex > #state.records then
        return false
    end
    local records = buildCurrentPage()
    state.pageMemoryBeforeKb = luaMemoryKb()
    local generation, visibleOrReason = state.page:LoadRuntimeAuditAppearanceRecords(records)
    if not generation or visibleOrReason ~= #records then
        setFailure("WARDROBE_AUDIT_LOAD_" .. tostring(visibleOrReason or "FAILED"))
        return false
    end
    state.pageStartedAt = GetTime()
    state.pageDeadline = state.pageStartedAt + MODEL_WINDOW
    state.phase = "scan"
    local first = state.records[state.nextIndex].record.id
    setStatus(string.format("Scanning %d-%d / %d (appearance %s)", state.nextIndex,
        state.nextIndex + #records - 1, #state.records, tostring(first)))
    return true
end

local function unavailableVisualState(host, objectModel)
    local overlay = host and host.scUnavailable
    local icon = host and host.scUnavailableIcon
    local reason = host and host.scUnavailableText
    local iconTexture = icon and icon.GetTexture and icon:GetTexture() or nil
    local reasonText = reason and reason.GetText and reason:GetText() or ""
    local iconVisible = overlay and overlay:IsShown() and icon and icon:IsShown() and iconTexture ~= nil
    local reasonVisible = overlay and overlay:IsShown() and reason and reason:IsShown() and #tostring(reasonText or "") > 0
    local modelHidden = host and not host:IsShown() and objectModel and not objectModel:IsShown()
    return modelHidden and iconVisible and reasonVisible, iconVisible and true or false, reasonVisible and true or false
end

local function inspectReady(card, expected, now)
    local host = card.host
    local objectModel = card.objectModel
    if host.scRenderKind == "UNAVAILABLE" then
        card.result = "FAILED"
        card.failureReason = "RUNTIME_UNAVAILABLE_" .. safe(host.scRuntimeUnavailableReason or "UNKNOWN")
        return
    end
    if host.scRenderKind ~= "STANDALONE" then
        card.failureReason = "CARD_STATE_" .. safe(host.scRenderKind or "NONE")
        return
    end
    if not objectModel:IsShown() then
        card.failureReason = "DIRECT_MODEL_HIDDEN"
        return
    end
    local actual = objectModel.GetModel and objectModel:GetModel() or ""
    card.actualModelPath = tostring(actual or "")
    card.poseSource = tostring(objectModel.scPoseSource or "")
    if lower(card.actualModelPath) ~= lower(expected.modelPath) or card.actualModelPath == "" then
        card.stableTicks = 0
        card.lastModelPath = ""
        card.failureReason = "CANONICAL_MODEL_PENDING"
        return
    end
    if lower(card.lastModelPath) == lower(card.actualModelPath) then
        card.stableTicks = card.stableTicks + 1
    else
        card.lastModelPath = card.actualModelPath
        card.stableTicks = 1
    end
    if card.stableTicks >= STABLE_TICKS then
        card.result = "READY"
        card.readyMilliseconds = math.floor((now - state.pageStartedAt) * 1000 + 0.5)
        card.failureReason = ""
    end
end

local function inspectUnavailable(card)
    local host = card.host
    local objectModel = card.objectModel
    local valid, iconVisible, reasonVisible = unavailableVisualState(host, objectModel)
    card.iconVisible = iconVisible
    card.reasonVisible = reasonVisible
    -- A hidden 3.3.5 PlayerModel can retain an internal table-valued model
    -- handle after ClearModel.  It is not a visible path and must not turn a
    -- valid unavailable card into a false model-leak failure; visibility is
    -- asserted above before this canonical empty audit value is recorded.
    card.actualModelPath = ""
    if valid and host.scRenderKind == "UNAVAILABLE" then
        card.result = "UNAVAILABLE"
        card.failureReason = ""
    else
        card.failureReason = "UNAVAILABLE_CARD_INVALID_" .. safe(host.scRenderKind or "NONE")
    end
end

local function captureCardRow(card)
    local record = card.pair.record
    local expected = card.pair.expected
    local host = card.host
    local objectModel = card.objectModel
    local _, iconVisible, reasonVisible = unavailableVisualState(host, objectModel)
    if expected.presentationStatus == "READY" then
        iconVisible, reasonVisible = false, false
    end
    local cardState = host and host.scRenderKind or ""
    table.insert(state.rows, table.concat({
        safe(expected.appearanceId),
        safe(expected.sourceItemId),
        safe(record.slot),
        safe(record.weaponType or record.weaponCategory),
        safe(expected.presentationStatus),
        safe(expected.syntheticDisplayId),
        safe(expected.modelPath),
        safe(card.actualModelPath),
        safe(card.poseSource),
        safe(card.readyMilliseconds),
        safe(card.failureReason),
        safe(cardState),
        boolText(iconVisible),
        boolText(reasonVisible),
        safe(card.stableTicks),
        safe(expected.sampleKinds),
    }, ","))
end

local function capturePerformancePage(now)
    if not state.performanceMode then return end
    local recordCount = #state.pagePairs
    local firstIndex = state.nextIndex
    local lastIndex = firstIndex + recordCount - 1
    local first = state.records[firstIndex] and state.records[firstIndex].record.id or 0
    local last = state.records[lastIndex] and state.records[lastIndex].record.id or 0
    local memoryAfter = luaMemoryKb()
    local hostUpdates, objectUpdates = poolOnUpdateCounts()
    local poolSize = #((state.page and state.page.scItemModels) or {})
    local elapsedMilliseconds = math.floor((now - state.pageStartedAt) * 1000 + 0.5)
    local delta = memoryAfter - (state.pageMemoryBeforeKb or memoryAfter)
    table.insert(state.performancePageRows, table.concat({
        safe(state.round),
        safe(state.roundPageCount + 1),
        safe(first),
        safe(last),
        safe(recordCount),
        safe(elapsedMilliseconds),
        string.format("%.3f", state.pageMemoryBeforeKb or 0),
        string.format("%.3f", memoryAfter),
        string.format("%.3f", delta),
        safe(poolSize),
        safe(hostUpdates),
        safe(objectUpdates),
        safe(hostUpdates + objectUpdates),
        safe(state.page.scItemGeneration or 0),
    }, ","))
    state.roundPageCount = state.roundPageCount + 1
    state.roundMaxMemoryKb = math.max(state.roundMaxMemoryKb or 0, memoryAfter)
end

local function completePerformanceRound(now)
    if not state.performanceMode then return end
    local memoryEnd = luaMemoryKb()
    local elapsedMilliseconds = math.floor((now - (state.roundStartedAt or now)) * 1000 + 0.5)
    table.insert(state.performanceRoundRows, table.concat({
        safe(state.round),
        safe(state.roundPageCount),
        safe(elapsedMilliseconds),
        string.format("%.3f", state.roundMemoryStartKb or 0),
        string.format("%.3f", memoryEnd),
        string.format("%.3f", math.max(state.roundMaxMemoryKb or 0, memoryEnd)),
        string.format("%.3f", memoryEnd - (state.roundMemoryStartKb or memoryEnd)),
    }, ","))
end

local function completePage(now, timedOut)
    for index, card in ipairs(state.pagePairs) do
        if not card.result then
            if timedOut then
                card.result = "FAILED"
                if card.failureReason == "" then card.failureReason = "MODEL_WINDOW_TIMEOUT" end
            else
                card.result = "FAILED"
                card.failureReason = "PAGE_COMPLETED_WITHOUT_RESULT"
            end
        end
        if card.result == "READY" then
            state.readyCount = state.readyCount + 1
        elseif card.result == "UNAVAILABLE" then
            state.unavailableCount = state.unavailableCount + 1
        else
            state.failedCount = state.failedCount + 1
        end
        captureCardRow(card)
    end
    capturePerformancePage(now)
    state.nextIndex = state.nextIndex + #state.pagePairs
    if DATA.visualCapture then
        local db = SoloCollectionsWeaponPresentationAuditDB
        db.visualPages = db.visualPages or {}
        local visualPage = #db.visualPages + 1
        table.insert(db.visualPages, {
            page = visualPage,
            firstAppearanceId = state.records[state.nextIndex - #state.pagePairs].record.id,
            count = #state.pagePairs,
            screenshot = string.format("weapon-visual-sample-%02d", visualPage),
        })
        Screenshot()
    end
    state.pagePairs = {}
    state.holdUntil = now + (DATA.visualCapture and VISUAL_SCREENSHOT_SETTLE_DELAY or PAGE_HOLD_DELAY)
    state.phase = "hold"
end

local function beginNextPerformanceRound(now)
    state.round = state.round + 1
    state.rows = {}
    state.nextIndex = 1
    state.pagePairs = {}
    state.readyCount = 0
    state.unavailableCount = 0
    state.failedCount = 0
    state.roundStartedAt = now
    state.roundMemoryStartKb = luaMemoryKb()
    state.roundMaxMemoryKb = state.roundMemoryStartKb
    state.roundPageCount = 0
    state.holdUntil = now + PERFORMANCE_PREFLIGHT_DELAY
    state.phase = "preflight"
    setStatus(string.format("Performance round %d / %d", state.round, state.performanceRounds))
end

local function copyFilters(filters)
    local copied = {}
    for key, value in pairs(filters or {}) do copied[key] = value end
    return copied
end

local function restorePerformanceFilters()
    if not SC or not SC.db or not state.originalFilters then return end
    for key in pairs(SC.db.filters or {}) do SC.db.filters[key] = nil end
    for key, value in pairs(state.originalFilters) do SC.db.filters[key] = value end
    SC.db.query = state.originalQuery or ""
    state.page.scItemPage = state.originalItemPage or 1
    state.page:Refresh()
end

local function beginNextPerformanceFilterScenario(now)
    state.filterScenarioIndex = state.filterScenarioIndex + 1
    local scenario = state.filterScenarios[state.filterScenarioIndex]
    if not scenario then
        restorePerformanceFilters()
        state.phase = "performanceFilterComplete"
        return
    end
    local filters = SC.db.filters
    filters.collected = true
    filters.uncollected = true
    filters.favorites = false
    filters.classToken = "ALL"
    filters.armorType = "AUTO"
    filters.slot = scenario.slot
    filters.weaponType = scenario.weaponType
    SC.db.query = ""

    local beforeGeneration = state.page.scItemGeneration or 0
    state.page.scItemPage = 1
    state.page:Refresh()
    -- The second refresh intentionally races the first page so the production
    -- generation guard, rather than a test-only renderer, owns the final
    -- visible cards.  This is the exact stale-page case that must not leave a
    -- previous main/off-hand model in the grid.
    state.page.scItemPage = 2
    state.page:Refresh()
    local pageSize = state.page.scItemPageSize or 18
    local records, currentPage = SC.Catalog.Query("APPEARANCES", SC.db.query, filters,
        state.page.scItemPage, pageSize)
    if #records == 0 then
        setFailure("PERFORMANCE_FILTER_NO_RECORDS_" .. tostring(scenario.name))
        return
    end
    state.filterPairs = {}
    for index, record in ipairs(records) do
        table.insert(state.filterPairs, {
            pair = {
                record = record,
                expected = {
                    appearanceId = record.id,
                    sourceItemId = record.sourceItemId or record.itemId,
                    presentationStatus = record.presentationStatus,
                    syntheticDisplayId = record.syntheticDisplayId,
                    modelPath = record.modelPath or "",
                    sampleKinds = "",
                },
            },
            result = nil,
            actualModelPath = "",
            poseSource = "",
            readyMilliseconds = 0,
            failureReason = "",
            stableTicks = 0,
            lastModelPath = "",
        })
    end
    state.filterScenario = scenario
    state.filterPage = currentPage
    state.filterGeneration = state.page.scItemGeneration or 0
    state.filterGenerationDelta = state.filterGeneration - beforeGeneration
    state.pageStartedAt = now
    state.pageDeadline = now + MODEL_WINDOW
    state.phase = "performanceFilterScan"
    setStatus("Performance filter: " .. tostring(scenario.name))
end

local function capturePerformanceFilter(now)
    local hostUpdates, objectUpdates = poolOnUpdateCounts()
    local scenario = state.filterScenario or {}
    table.insert(state.performanceFilterRows, table.concat({
        safe(scenario.name),
        safe(scenario.slot),
        safe(scenario.weaponType),
        safe(state.filterPage),
        safe(#state.filterPairs),
        safe(math.floor((now - state.pageStartedAt) * 1000 + 0.5)),
        safe(#((state.page and state.page.scItemModels) or {})),
        safe(hostUpdates),
        safe(objectUpdates),
        safe(hostUpdates + objectUpdates),
        safe(state.filterGeneration),
        safe(state.filterGenerationDelta),
        "false",
    }, ","))
end

local function scanPerformanceFilter(now)
    local finished = true
    for index, card in ipairs(state.filterPairs) do
        local host = state.page.scItemModels[index]
        card.host = host
        card.objectModel = host and host.scObjectModel
        if not card.result then
            if not host or not card.objectModel then
                card.result = "FAILED"
                card.failureReason = "FILTER_CARD_POOL_MEMBER_MISSING"
            elseif host.scItemGeneration ~= state.filterGeneration then
                card.result = "FAILED"
                card.failureReason = "FILTER_GENERATION_STALE"
            elseif not host.scRecord or host.scRecord.id ~= card.pair.record.id then
                card.result = "FAILED"
                card.failureReason = "FILTER_RECORD_CROSS_CONTAMINATION"
            elseif card.pair.expected.presentationStatus == "READY" then
                inspectReady(card, card.pair.expected, now)
            else
                inspectUnavailable(card)
            end
        end
        if not card.result then finished = false end
    end
    for index = #state.filterPairs + 1, #(state.page.scItemModels or {}) do
        local host = state.page.scItemModels[index]
        local objectModel = host and host.scObjectModel
        if host and (host.scRecord or host:IsShown() or (objectModel and objectModel:IsShown())) then
            setFailure("FILTER_HIDDEN_CARD_CROSS_CONTAMINATION_" .. tostring(index))
            return
        end
    end
    if finished then
        for _, card in ipairs(state.filterPairs) do
            if card.result == "FAILED" then
                setFailure(card.failureReason or "FILTER_CARD_FAILED")
                return
            end
        end
        if state.filterGenerationDelta < 2 then
            setFailure("FILTER_RAPID_GENERATION_NOT_OBSERVED")
            return
        end
        capturePerformanceFilter(now)
        beginNextPerformanceFilterScenario(now)
    elseif now >= state.pageDeadline then
        setFailure("FILTER_MODEL_WINDOW_TIMEOUT_" .. tostring((state.filterScenario or {}).name or "UNKNOWN"))
    end
end

local function beginPerformanceFilterScenarios(now)
    state.performanceFilterRows = {}
    state.filterScenarioIndex = 0
    state.filterPairs = {}
    state.originalFilters = copyFilters(SC.db.filters)
    state.originalQuery = SC.db.query or ""
    state.originalItemPage = state.page.scItemPage or 1
    state.filterScenarios = {
        { name = "mainhand-auto-page2", slot = "MAINHAND", weaponType = "AUTO" },
        { name = "offhand-auto-page2", slot = "OFFHAND", weaponType = "AUTO" },
        { name = "mainhand-one-hand-sword-page2", slot = "MAINHAND", weaponType = "ONE_HAND_SWORD" },
        { name = "offhand-shield-page2", slot = "OFFHAND", weaponType = "SHIELD" },
    }
    beginNextPerformanceFilterScenario(now)
end

local function finishAudit()
    local db = SoloCollectionsWeaponPresentationAuditDB
    db.total = #state.records
    db.readyCount = state.readyCount
    db.unavailableCount = state.unavailableCount
    db.failedCount = state.failedCount
    db.performanceMode = state.performanceMode and true or false
    db.performanceRoundsRequested = state.performanceRounds or 1
    db.performanceRoundsCompleted = state.performanceMode and #state.performanceRoundRows or 0
    db.performanceFilterScenarioCount = state.performanceMode and #state.performanceFilterRows or 0
    db.cardPoolSize = #((state.page and state.page.scItemModels) or {})
    db.modelWindowSeconds = MODEL_WINDOW
    db.stableTicksRequired = STABLE_TICKS
    db.completed = true
    db.requested = false
    db.completedAt = time()
    db.ready = #state.rows == #state.records
        and state.readyCount == tonumber(DATA.readyCount)
        and state.unavailableCount == tonumber(DATA.unavailableCount)
        and state.failedCount == 0
    writeCsv()
    writePerformanceCsv()
    panel:Show()
    setStatus(string.format("Complete: %d READY / %d UNAVAILABLE / %d failed", state.readyCount,
        state.unavailableCount, state.failedCount))
    if DATA.autoLogout then
        local delay = tonumber(DATA.autoLogoutDelay) or AUTO_LOGOUT_DEFAULT_SECONDS
        state.logoutAt = GetTime() + math.max(1, math.min(delay, 60))
        state.phase = "logout"
    else
        state.phase = "complete"
    end
end

local function beginAudit()
    local records, reason = collectProductionRecords()
    if not records then
        setFailure(reason)
        return
    end
    local frame = SC.UI.CreateCollectionsFrame and SC.UI.CreateCollectionsFrame()
    if not frame or not frame.scPages or not frame.scPages.WARDROBE then
        setFailure("WARDROBE_FRAME_MISSING")
        return
    end
    frame:Show()
    SC.db.mainTab = "WARDROBE"
    SC.db.wardrobeTab = "ITEMS"
    SC.UI.SetMainTab("WARDROBE")
    SC.UI.SetWardrobeTab("ITEMS")
    state.page = frame.scPages.WARDROBE
    if not state.page.LoadRuntimeAuditAppearanceRecords or #(state.page.scItemModels or {}) ~= 18 then
        setFailure("WARDROBE_RUNTIME_AUDIT_ENTRYPOINT_OR_POOL_INVALID")
        return
    end

    state.records = records
    state.rows = {}
    state.nextIndex = 1
    state.readyCount = 0
    state.unavailableCount = 0
    state.failedCount = 0
    state.performanceMode = DATA.performanceMode and true or false
    state.performanceRounds = state.performanceMode and math.max(1,
        math.min(MAX_PERFORMANCE_ROUNDS, math.floor(tonumber(DATA.performanceRounds) or 1))) or 1
    state.round = 1
    state.performancePageRows = {}
    state.performanceRoundRows = {}
    state.roundStartedAt = GetTime()
    state.roundMemoryStartKb = luaMemoryKb()
    state.roundMaxMemoryKb = state.roundMemoryStartKb
    state.roundPageCount = 0
    local db = SoloCollectionsWeaponPresentationAuditDB
    db.bundleId = DATA.bundleId or ""
    db.assetPackVersion = DATA.assetPackVersion or ""
    db.appearancePresentationHash = DATA.appearancePresentationHash or ""
    db.presentationSourceSha256 = DATA.presentationSourceSha256 or ""
    db.presentationReportSha256 = DATA.presentationReportSha256 or ""
    db.catalogManifestSha256 = DATA.catalogManifestSha256 or ""
    db.cacheState = DATA.cacheState or ""
    db.sampleOnly = DATA.sampleOnly and true or false
    db.visualCapture = DATA.visualCapture and true or false
    db.samplePlanSha256 = DATA.samplePlanSha256 or ""
    db.sampleCount = tonumber(DATA.sampleCount) or 0
    db.visualPages = {}
    db.expected = #records
    db.completed = false
    db.ready = false
    db.error = nil
    db.startedAt = time()
    panel:Show()
    -- Showing the collection frame can schedule its regular filtered refresh
    -- after SetMainTab returns.  Let that one normal refresh settle before
    -- the audit takes ownership of the pool; otherwise the first 18 audit
    -- records can be replaced by the ordinary armor page while later pages
    -- are already generation-safe.
    state.holdUntil = GetTime() + 0.25
    state.phase = "preflight"
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    SoloCollectionsWeaponPresentationAuditDB = SoloCollectionsWeaponPresentationAuditDB or {}
    local db = SoloCollectionsWeaponPresentationAuditDB
    if not db.requested then return end
    if DATA.cacheState == "reload" then
        -- A true UI reload creates a second PLAYER_LOGIN for the same
        -- SavedVariables run.  Merely waiting must never count as proof:
        -- the prior implementation could report success after its timer
        -- expired even when no /reload was issued.
        db.reloadLoginCount = (tonumber(db.reloadLoginCount) or 0) + 1
        db.reloadLastPlayerLoginAt = time()
        if db.reloadLoginCount == 1 then
            db.reloadObserved = false
            db.reloadBoundary = nil
            db.reloadWaitStartedAt = time()
            state.phase = "reloadWait"
            state.elapsed = 0
            panel:Show()
            setStatus("Waiting for external /reload (120s timeout)")
            return
        end
        if db.reloadLoginCount == 2 then
            db.reloadObserved = true
            db.reloadObservedAt = time()
            db.reloadBoundary = "PLAYER_LOGIN"
            state.phase = "setup"
            state.elapsed = 0
            return
        end
        setFailure("RELOAD_LOGIN_COUNT_UNEXPECTED_" .. tostring(db.reloadLoginCount))
        return
    end
    state.phase = "setup"
    state.elapsed = 0
end)

driver:SetScript("OnUpdate", function(_, delta)
    if state.phase == "idle" or state.phase == "complete" then return end
    if state.phase == "logout" then
        if state.logoutAt and GetTime() >= state.logoutAt then Logout() end
        return
    end
    if state.phase == "setup" then
        state.elapsed = state.elapsed + delta
        if state.elapsed >= SETUP_DELAY then beginAudit() end
        return
    end
    if state.phase == "reloadWait" then
        state.elapsed = state.elapsed + delta
        if state.elapsed >= RELOAD_TIMEOUT_SECONDS then
            setFailure("RELOAD_NOT_OBSERVED_WITHIN_TIMEOUT")
        end
        return
    end
    if state.phase == "preflight" then
        if GetTime() >= state.holdUntil then beginPage() end
        return
    end
    if state.phase == "hold" then
        if GetTime() >= state.holdUntil then
            if state.nextIndex > #state.records then
                local now = GetTime()
                if state.performanceMode then
                    completePerformanceRound(now)
                    if state.round < state.performanceRounds then
                        beginNextPerformanceRound(now)
                    else
                        beginPerformanceFilterScenarios(now)
                    end
                else
                    finishAudit()
                end
            else
                beginPage()
            end
        end
        return
    end
    if state.phase == "performanceFilterScan" then
        scanPerformanceFilter(GetTime())
        return
    end
    if state.phase == "performanceFilterComplete" then
        finishAudit()
        return
    end
    if state.phase ~= "scan" then return end

    local now = GetTime()
    local finished = true
    for index, card in ipairs(state.pagePairs) do
        if not card.result then
            local host = state.page.scItemModels[index]
            card.host = host
            card.objectModel = host and host.scObjectModel
            if not host or not card.objectModel then
                card.result = "FAILED"
                card.failureReason = "CARD_POOL_MEMBER_MISSING"
            elseif card.pair.expected.presentationStatus == "READY" then
                inspectReady(card, card.pair.expected, now)
            else
                inspectUnavailable(card)
            end
        end
        if not card.result then finished = false end
    end
    if finished then
        completePage(now, false)
    elseif now >= state.pageDeadline then
        completePage(now, true)
    end
end)
