local SETUP_DELAY = 3.0
local REQUIRED_SET_COUNT = 465
local VISIBLE_ROWS = 8
local SORT_KEYS = { "expansion", "acquisition", "tier", "difficulty", "medianItemLevel", "maxItemLevel" }

local driver = CreateFrame("Frame")
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(560)
panel:SetHeight(54)
panel:SetPoint("TOP", UIParent, "TOP", 0, -72)
panel:SetFrameStrata("DIALOG")
local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(panel)
background:SetTexture("Interface\\Buttons\\WHITE8X8")
background:SetVertexColor(0.012, 0.014, 0.018, 0.92)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", panel, "TOP", 0, -8)
local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)

local state = {
    elapsed = 0,
    phase = "waiting",
    page = nil,
    records = nil,
    run = nil,
    runKey = nil,
    classToken = nil,
    searchTarget = nil,
}

local function auditDB()
    SoloCollectionsSetOrderAuditDB = SoloCollectionsSetOrderAuditDB or {}
    local db = SoloCollectionsSetOrderAuditDB
    db.schemaVersion = 1
    db.runs = db.runs or {}
    return db
end

local function setStatus(heading, detail)
    title:SetText(heading or "Stage 3 set ordering audit")
    subtitle:SetText(detail or "")
    panel:Show()
end

local function copyFilters()
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

local function getClassToken()
    local _, classToken = UnitClass("player")
    return classToken or "UNKNOWN"
end

local function currentRunKey()
    local name = UnitName("player") or "UNKNOWN"
    local realm = GetRealmName() or "UNKNOWN"
    return tostring(name) .. "@" .. tostring(realm) .. ":" .. getClassToken()
end

local function appendError(message)
    local run = state.run
    if run then
        run.errors = run.errors or {}
        table.insert(run.errors, tostring(message))
    end
end

local function fail(message)
    appendError(message)
    local db = auditDB()
    if state.run then
        state.run.ready = false
        state.run.completed = true
        state.run.errorCount = #(state.run.errors or {})
        db.runs[state.runKey] = state.run
    end
    db.completed = true
    db.ready = false
    db.lastError = tostring(message)
    setStatus("Stage 3 set ordering audit FAILED", tostring(message))
    state.phase = "failed"
end

local function sameSignature(left, right)
    return type(left) == "string" and left ~= "" and left == right
end

local function orderSignature(records)
    local ids = {}
    for index, record in ipairs(records or {}) do
        ids[index] = tostring(tonumber(record and record.itemSetId) or 0)
    end
    return table.concat(ids, ",")
end

local function rank(record, key)
    local presentation = record and record.presentation
    local ranks = presentation and presentation.sortRank
    return tonumber(ranks and ranks[key]) or 0
end

local function presentationLess(left, right)
    for _, key in ipairs(SORT_KEYS) do
        local leftRank = rank(left, key)
        local rightRank = rank(right, key)
        if leftRank ~= rightRank then return leftRank > rightRank end
    end
    local leftItemSetId = tonumber(left and left.itemSetId) or 0
    local rightItemSetId = tonumber(right and right.itemSetId) or 0
    if leftItemSetId ~= rightItemSetId then return leftItemSetId < rightItemSetId end
    return (tonumber(left and left.id) or 0) < (tonumber(right and right.id) or 0)
end

local function recordsAreSorted(records)
    for index = 2, #records do
        if presentationLess(records[index], records[index - 1]) then return false end
    end
    return true
end

local function containsItemSet(records, itemSetId)
    for _, record in ipairs(records or {}) do
        if tonumber(record.itemSetId) == itemSetId then return true end
    end
    return false
end

local function indexOfItemSet(records, itemSetId)
    for index, record in ipairs(records or {}) do
        if tonumber(record.itemSetId) == itemSetId then return index end
    end
    return nil
end

local function t10PrefixIsStable(records)
    for itemSetId = 883, 901 do
        local record = records[itemSetId - 882]
        if not record or tonumber(record.itemSetId) ~= itemSetId then return false end
    end
    return true
end

local function higherCohortsLead(records)
    local t8High = indexOfItemSet(records, 821)
    local t8Normal = indexOfItemSet(records, 820)
    local t7High = indexOfItemSet(records, 801)
    local t7Normal = indexOfItemSet(records, 787)
    return t8High and t8Normal and t8High < t8Normal
        and t7High and t7Normal and t7High < t7Normal
end

local function visibleMatches(page, records, firstIndex)
    for rowIndex = 1, VISIBLE_ROWS do
        local expected = records[firstIndex + rowIndex - 1]
        local row = page and page.scSetRows and page.scSetRows[rowIndex]
        local actual = row and row.scRecord
        if expected then
            if not actual or tonumber(actual.id) ~= tonumber(expected.id) then return false end
        elseif actual then
            return false
        end
    end
    return true
end

local function querySets(query, filters)
    return SoloCollections.Catalog.QueryAll("SETS", query or "", filters or copyFilters())
end

local function configurePage()
    local SC = SoloCollections
    if not SC or not SC.UI or not SC.UI.CreateCollectionsFrame or not SC.db then return nil end
    local frame = SC.UI.CreateCollectionsFrame()
    local page = SC.UI.CollectionsFrame and SC.UI.CollectionsFrame.scPages
        and SC.UI.CollectionsFrame.scPages.WARDROBE
    if not page then return nil end
    page.scDefaultSetClassApplied = true
    frame:Show()
    SC.db.query = ""
    for key, value in pairs(copyFilters()) do SC.db.filters[key] = value end
    if frame.scSearchBox then frame.scSearchBox:SetText("") end
    SC.UI.SetMainTab("WARDROBE")
    SC.UI.SetWardrobeTab("SETS")
    page:Refresh()
    return page
end

local function setPageQuery(value)
    local frame = SoloCollections and SoloCollections.UI and SoloCollections.UI.CollectionsFrame
    value = value or ""
    if frame and frame.scSearchBox then
        -- Use the player's real search callback, not a direct database write.
        frame.scSearchBox:SetText(value)
    else
        SoloCollections.db.query = value
        state.page:Refresh()
    end
end

local function beginRun()
    local page = configurePage()
    if not page then
        fail("WARDROBE_PAGE_UNAVAILABLE")
        return
    end
    state.page = page
    state.classToken = getClassToken()
    state.runKey = currentRunKey()
    state.records = querySets("", copyFilters())
    state.run = {
        playerClass = state.classToken,
        runKey = state.runKey,
        completed = false,
        ready = false,
        allCount = #state.records,
        allSignature = orderSignature(state.records),
        allOrderSorted = recordsAreSorted(state.records),
        t10PrefixPass = t10PrefixIsStable(state.records),
        higherCohortPass = higherCohortsLead(state.records),
        errors = {},
    }
    if #state.records ~= REQUIRED_SET_COUNT then
        fail("ACTIVE_SET_COUNT_" .. tostring(#state.records))
        return
    end
    if not state.run.allOrderSorted then
        fail("ALL_SET_ORDER_UNSORTED")
        return
    end
    if not state.run.t10PrefixPass then
        fail("T10_PREFIX_UNSTABLE")
        return
    end
    if not state.run.higherCohortPass then
        fail("HIGH_ITEM_LEVEL_COHORT_ORDER_FAILED")
        return
    end
    state.searchTarget = state.records[1]
    if not state.searchTarget or not state.searchTarget.name or state.searchTarget.name == "" then
        fail("SEARCH_TARGET_UNAVAILABLE")
        return
    end
    setStatus("Stage 3 set ordering audit", "search: " .. tostring(state.searchTarget.name))
    setPageQuery(state.searchTarget.name)
    state.elapsed = 0
    state.phase = "wait_search"
end

local function auditSearch()
    local query = SoloCollections.db and SoloCollections.db.query or ""
    local records = querySets(query, copyFilters())
    local page = state.page
    state.run.searchQuery = query
    state.run.searchCount = #records
    state.run.searchPass = query == state.searchTarget.name
        and #records > 0
        and recordsAreSorted(records)
        and containsItemSet(records, tonumber(state.searchTarget.itemSetId))
        and page.scSetRecordCount == #records
        and visibleMatches(page, records, 1)
    if not state.run.searchPass then
        fail("SEARCH_UI_OR_ORDER_FAILED")
        return
    end
    setPageQuery("")
    state.elapsed = 0
    state.phase = "wait_class_filter"
end

local function auditClassFilter()
    local page = state.page
    SoloCollections.db.filters.classToken = state.classToken
    page:Refresh()
    local filters = copyFilters()
    filters.classToken = state.classToken
    local records = querySets("", filters)
    state.run.classFilterCount = #records
    state.run.classFilterSignature = orderSignature(records)
    state.run.classFilterPass = #records > 0
        and recordsAreSorted(records)
        and page.scSetRecordCount == #records
        and visibleMatches(page, records, 1)
    if not state.run.classFilterPass then
        fail("CLASS_FILTER_UI_OR_ORDER_FAILED")
        return
    end
    SoloCollections.db.filters.classToken = "ALL"
    page:Refresh()
    if page.scSetScrollbar then page.scSetScrollbar:SetValue(0) end
    state.elapsed = 0
    state.phase = "wait_page_start"
end

local function auditPageStart()
    local page = state.page
    state.run.pageStartPass = page.scSetOffset == 0
        and page.scSetPage == 1
        and visibleMatches(page, state.records, 1)
    if not state.run.pageStartPass then
        fail("FIRST_PAGE_UI_FAILED")
        return
    end
    local maximum = #state.records - VISIBLE_ROWS
    if not page.scSetScrollbar then
        fail("SET_SCROLLBAR_UNAVAILABLE")
        return
    end
    page.scSetScrollbar:SetValue(maximum)
    state.elapsed = 0
    state.phase = "wait_page_end"
end

local function finalizePersistence()
    local db = auditDB()
    if type(db.pendingReload) == "table" and db.pendingReload.runKey == state.runKey then
        db.reloadPass = sameSignature(db.pendingReload.allSignature, state.run.allSignature)
        db.pendingReload = nil
    end
    if type(db.pendingRelog) == "table" and db.pendingRelog.runKey == state.runKey then
        db.relogPass = sameSignature(db.pendingRelog.allSignature, state.run.allSignature)
        db.pendingRelog = nil
    end
    if not db.referenceClass then
        db.referenceClass = state.classToken
        db.referenceAllSignature = state.run.allSignature
    elseif db.referenceClass ~= state.classToken then
        db.differentClassPass = sameSignature(db.referenceAllSignature, state.run.allSignature)
        db.differentClassReference = db.referenceClass
        db.differentClassObserved = state.classToken
    end
end

local function auditPageEnd()
    local page = state.page
    local maximum = #state.records - VISIBLE_ROWS
    state.run.pageEndPass = page.scSetOffset == maximum
        and page.scSetPage == math.ceil(#state.records / VISIBLE_ROWS)
        and visibleMatches(page, state.records, maximum + 1)
    if not state.run.pageEndPass then
        fail("LAST_PAGE_UI_FAILED")
        return
    end
    state.run.completed = true
    state.run.errorCount = #state.run.errors
    state.run.ready = #state.run.errors == 0
    finalizePersistence()
    local db = auditDB()
    db.runs[state.runKey] = state.run
    db.completed = state.run.completed
    db.ready = state.run.ready
    db.lastRunKey = state.runKey
    db.lastClass = state.classToken
    setStatus("Stage 3 set ordering audit READY", string.format("%s: %d sets; use /scsetaudit reload or relog", state.classToken, #state.records))
    Screenshot()
    state.phase = "complete"
end

local function requestPersistenceAction(action)
    local db = auditDB()
    local run = db.runs[currentRunKey()]
    if not run or not run.ready or run.allCount ~= REQUIRED_SET_COUNT then
        setStatus("Stage 3 set ordering audit", "wait for READY before " .. action)
        return
    end
    local snapshot = { runKey = currentRunKey(), allSignature = run.allSignature }
    if action == "reload" then
        db.pendingReload = snapshot
        setStatus("Stage 3 set ordering audit", "reloading for persistence check")
        ReloadUI()
    elseif action == "relog" then
        db.pendingRelog = snapshot
        -- The stock client does not reliably honor Logout() when invoked by
        -- an AddOn slash handler. Persist the marker first, then let the
        -- operator use the client's built-in /logout command so this remains
        -- a real character-session transition rather than a synthetic reset.
        setStatus("Stage 3 set ordering audit", "relog marker saved; use the client /logout command")
    end
end

SLASH_SOLOCOLLECTIONSSETAUDIT1 = "/scsetaudit"
SlashCmdList.SOLOCOLLECTIONSSETAUDIT = function(message)
    local command = string.lower(string.match(message or "", "^%s*(%S*)") or "")
    if command == "reload" or command == "relog" then
        requestPersistenceAction(command)
    elseif command == "run" then
        state.elapsed = SETUP_DELAY
        state.phase = "waiting"
    else
        setStatus("Stage 3 set ordering audit", "commands: /scsetaudit reload | relog | run")
    end
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    state.elapsed = 0
    state.phase = "waiting"
end)
driver:SetScript("OnUpdate", function(_, elapsed)
    if state.phase == "failed" or state.phase == "complete" then return end
    state.elapsed = state.elapsed + elapsed
    if state.phase == "waiting" then
        setStatus("Stage 3 set ordering audit", "waiting for SoloCollections")
        if state.elapsed >= SETUP_DELAY then beginRun() end
    elseif state.phase == "wait_search" and state.elapsed >= 0.20 then
        auditSearch()
    elseif state.phase == "wait_class_filter" and state.elapsed >= 0.20 then
        auditClassFilter()
    elseif state.phase == "wait_page_start" and state.elapsed >= 0.20 then
        auditPageStart()
    elseif state.phase == "wait_page_end" and state.elapsed >= 0.20 then
        auditPageEnd()
    end
end)
