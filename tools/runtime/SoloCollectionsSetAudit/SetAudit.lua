local SETUP_DELAY = 3.0
local REQUIRED_PRODUCTION_SET_COUNT = 465
local REQUIRED_SAMPLE_COUNTS = { 2, 3, 5, 8, 9 }
local RAPID_SELECTION_COUNT = 20

local driver = CreateFrame("Frame")
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(520)
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
    phase = "idle",
    elapsed = 0,
    records = {},
    scanIndex = 0,
    active = nil,
    page = nil,
    hooked = false,
    pagination = nil,
    paginationIndex = 0,
    paginationFixture = nil,
}

local function auditDB()
    SoloCollectionsSetAuditDB = SoloCollectionsSetAuditDB or { requested = true }
    return SoloCollectionsSetAuditDB
end

local function setStatus(heading, detail)
    title:SetText(heading or "Stage 2 set preview audit")
    subtitle:SetText(detail or "")
    panel:Show()
end

local function recordError(message)
    local db = auditDB()
    db.ready = false
    db.errors = db.errors or {}
    table.insert(db.errors, tostring(message))
end

local function filters()
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

local function itemId(value)
    return tonumber(string.match(tostring(value or ""), "item:(%d+)"))
end

local function copyMember(member)
    local copy = {}
    for key, value in pairs(member or {}) do
        copy[key] = value
    end
    copy.sourceItemIds = {}
    for index, value in ipairs(member and member.sourceItemIds or {}) do
        copy.sourceItemIds[index] = value
    end
    copy.appearanceIds = {}
    for index, value in ipairs(member and member.appearanceIds or {}) do
        copy.appearanceIds[index] = value
    end
    return copy
end

local function copyMembers(members)
    local copied = {}
    for index, member in ipairs(members or {}) do
        copied[index] = copyMember(member)
    end
    return copied
end

local function previewItems(record)
    local result = {}
    local seenSlots = {}
    local slotOrder = {
        HEAD = 1, SHOULDER = 2, BACK = 3, CHEST = 4, WRIST = 5,
        HANDS = 6, WAIST = 7, LEGS = 8, FEET = 9, MAINHAND = 10, OFFHAND = 11,
    }
    local variant = record and record.selectedVariant
    for memberIndex, member in ipairs(variant and variant.members or {}) do
        if member.required then
            local source = tonumber(member.previewSourceItemId)
            if not source or source <= 0 then
                for _, candidate in ipairs(member.sourceItemIds or {}) do
                    candidate = tonumber(candidate)
                    if candidate and candidate > 0 and (not source or candidate < source) then
                        source = candidate
                    end
                end
            end
            local slot = tostring(member.slotKey or member.memberKey or "")
            local uniqueSlot = slot ~= "" and slot or ("member:" .. memberIndex)
            if source and not seenSlots[uniqueSlot] then
                seenSlots[uniqueSlot] = true
                table.insert(result, {
                    itemId = source,
                    order = slotOrder[slot] or (100 + memberIndex),
                    memberKey = tostring(member.memberKey or uniqueSlot),
                })
            end
        end
    end
    table.sort(result, function(left, right)
        if left.order == right.order then
            if left.memberKey == right.memberKey then return left.itemId < right.itemId end
            return left.memberKey < right.memberKey
        end
        return left.order < right.order
    end)
    local ids = {}
    for index, entry in ipairs(result) do ids[index] = entry.itemId end
    return ids
end

local function sameItems(left, right)
    if #left ~= #right then return false end
    for index, value in ipairs(left) do
        if tonumber(value) ~= tonumber(right[index]) then return false end
    end
    return true
end

local function currentRecords(query)
    return SoloCollections.Catalog.QueryAll("SETS", query or "", filters())
end

local function findRecord(records, id)
    for _, record in ipairs(records or {}) do
        if tonumber(record.id) == tonumber(id) then return record end
    end
    return nil
end

-- Production currently has no one-row, exactly-one-window, or nine-row
-- query cohorts.  Keep those pagination cases inside this disposable audit
-- catalog so the UI's real QueryAll/slider/offset path is exercised without
-- changing the checked-in ItemSet projection.
local function removePaginationFixtures()
    local fixture = state.paginationFixture
    local source = SoloCollections and SoloCollections.Data and SoloCollections.Data.Sets
    if fixture and source then
        for index = #source, fixture.firstIndex, -1 do
            table.remove(source, index)
        end
    end
    state.paginationFixture = nil
end

local function beginPaginationAudit()
    local base = state.records[1]
    local source = SoloCollections and SoloCollections.Data and SoloCollections.Data.Sets
    if not base or not source or not base.variants then
        recordError("PAGINATION_FIXTURE_BASE_UNAVAILABLE")
        state.phase = "failed"
        return
    end

    local firstIndex = #source + 1
    local ordinal = 0
    local function appendFixture(queryKey)
        ordinal = ordinal + 1
        local fixture = {}
        for key, value in pairs(base) do fixture[key] = value end
        fixture.id = 399990100 + ordinal
        fixture.collectionId = fixture.id
        fixture.collectionKey = "stage2-pagination-" .. tostring(ordinal)
        fixture.itemSetId = fixture.id
        fixture.name = queryKey
        fixture.source = queryKey
        table.insert(source, fixture)
    end

    appendFixture("stage2-pagination-single")
    for _ = 1, 8 do appendFixture("stage2-pagination-exact") end
    for _ = 1, 17 do appendFixture("stage2-pagination-multi") end

    state.paginationFixture = { firstIndex = firstIndex, count = ordinal }
    state.pagination = {
        { label = "empty", query = "stage2-pagination-empty", expectedCount = 0, expectedOffset = 0, expectedPage = 1, expectedVisible = 0 },
        { label = "single", query = "stage2-pagination-single", expectedCount = 1, expectedOffset = 0, expectedPage = 1, expectedVisible = 1 },
        { label = "exact-window", query = "stage2-pagination-exact", expectedCount = 8, expectedOffset = 0, expectedPage = 1, expectedVisible = 8 },
        -- The rows are an intentionally continuous scrolling window.  For a
        -- 17-record result the final page is clamped at offset 9, so the
        -- final range overlaps rather than drawing seven blank cards.
        { label = "multi-last-partial", query = "stage2-pagination-multi", expectedCount = 17, expectedOffset = 9, expectedPage = 3, expectedVisible = 8 },
    }
    state.paginationIndex = 1
    state.phase = "next_pagination"
end

local function configurePage()
    local SC = SoloCollections
    if not SC or not SC.UI or not SC.UI.CreateCollectionsFrame then return nil end
    local frame = SC.UI.CreateCollectionsFrame()
    local page = SC.UI.CollectionsFrame and SC.UI.CollectionsFrame.scPages
        and SC.UI.CollectionsFrame.scPages.WARDROBE
    if not page then return nil end
    -- Set the audit's explicit ALL-class filter before either tab-selection
    -- helper can perform the first-visit default-class mutation.
    page.scDefaultSetClassApplied = true
    frame:Show()
    SC.db.query = ""
    if frame.scSearchBox then frame.scSearchBox:SetText("") end
    for key, value in pairs(filters()) do SC.db.filters[key] = value end
    SC.UI.SetMainTab("WARDROBE")
    SC.UI.SetWardrobeTab("SETS")
    page:Refresh()
    return page
end

local function setPageQuery(value)
    local frame = SoloCollections and SoloCollections.UI and SoloCollections.UI.CollectionsFrame
    value = value or ""
    if frame and frame.scSearchBox then
        -- Exercise the same callback the player uses instead of updating the
        -- database behind the search control's back.
        frame.scSearchBox:SetText(value)
    else
        SoloCollections.db.query = value
        state.page:Refresh()
    end
end

local function installHooks(page)
    if state.hooked then return true end
    local model = page and page.scModel
    if not model or not hooksecurefunc then return false end
    local okUndress = pcall(function()
        hooksecurefunc(model, "Undress", function()
            if state.active then state.active.undressCount = state.active.undressCount + 1 end
        end)
    end)
    local okTryOn = pcall(function()
        hooksecurefunc(model, "TryOn", function(_, value)
            if state.active then table.insert(state.active.tryOns, itemId(value) or 0) end
        end)
    end)
    state.hooked = okUndress and okTryOn
    return state.hooked
end

local function beginSelection(record, bucket, label, injectPreGear, screenshot)
    local page = state.page
    if not page or not record then
        recordError("SELECTION_RECORD_UNAVAILABLE")
        state.phase = "failed"
        return
    end
    if injectPreGear then
        state.active = nil
        for _, value in ipairs({ 21409, 16689, 6096, 5976, 4309, 2844 }) do
            pcall(function() page.scModel:TryOn("item:" .. tostring(value)) end)
        end
    end
    state.active = {
        record = record,
        expected = previewItems(record),
        tryOns = {},
        undressCount = 0,
        bucket = bucket,
        label = label,
        screenshot = screenshot,
    }
    page.scSetSelectedId = record.id
    page:Refresh()
    state.active.generation = page.scSetPreviewGeneration
    state.elapsed = 0
    state.phase = "wait_selection"
    setStatus("Stage 2 set preview audit", string.format("%s: %s", label or "selection", tostring(record.name or record.id)))
end

local function appendResult(active)
    local page = state.page
    local pass = active.undressCount >= 1
        and sameItems(active.expected, active.tryOns)
        and page.scSetSelectedId == active.record.id
        and page.scSetPreviewPending == nil
        and page.scSetPreviewGeneration == active.generation
    local entry = {
        setId = active.record.id,
        itemSetId = active.record.itemSetId,
        label = active.label,
        expectedCount = #active.expected,
        actualCount = #active.tryOns,
        undressCount = active.undressCount,
        generation = active.generation,
        expectedItems = active.expected,
        actualItems = active.tryOns,
        pass = pass and true or false,
    }
    local db = auditDB()
    if active.bucket == "scan" then
        table.insert(db.scanRows, entry)
    else
        table.insert(db.samples, entry)
    end
    if not pass then recordError("PREVIEW_MISMATCH_" .. tostring(active.label or active.record.id)) end
    if active.screenshot then Screenshot() end
    return pass
end

local function finishSelection()
    local active = state.active
    if not active then
        recordError("ACTIVE_SELECTION_LOST")
        state.phase = "failed"
        return
    end
    appendResult(active)
    state.active = nil
    if active.bucket == "synthetic" then
        local db = auditDB()
        db.syntheticFixturePassed = (#active.expected == 9 and active.record.selectedVariant
            and tonumber(active.record.selectedVariant.variantOrdinal) == 2
            and #active.tryOns == 9 and active.undressCount >= 1)
        if not db.syntheticFixturePassed then recordError("SYNTHETIC_VARIANT_FIXTURE_FAILED") end
        if state.syntheticFixture then
            table.remove(SoloCollections.Data.Sets, state.syntheticFixture.index)
            state.syntheticFixture = nil
        end
        state.sampleIndex = 1
        state.phase = "next_sample"
    elseif active.bucket == "sample" then
        state.sampleIndex = state.sampleIndex + 1
        state.phase = "next_sample"
    elseif active.bucket == "pregear" then
        state.phase = "rapid"
    elseif active.bucket == "rapid" then
        local db = auditDB()
        db.rapidPassed = #active.tryOns == #active.expected and active.undressCount >= 1
        if not db.rapidPassed then recordError("RAPID_GENERATION_FAILED") end
        state.scanIndex = 1
        state.phase = "next_scan"
    elseif active.bucket == "scan" then
        state.scanIndex = state.scanIndex + 1
        state.phase = "next_scan"
    end
end

local function beginSyntheticFixture()
    local base
    for _, record in ipairs(state.records) do
        if #previewItems(record) == 8 then base = record break end
    end
    if not base or not base.selectedVariant then
        recordError("SYNTHETIC_BASE_UNAVAILABLE")
        state.phase = "failed"
        return
    end
    local defaultMembers = copyMembers(base.selectedVariant.members)
    while #defaultMembers > 2 do table.remove(defaultMembers) end
    local selectedMembers = copyMembers(base.selectedVariant.members)
    table.insert(selectedMembers, {
        memberKey = "synthetic-back",
        slotKey = "BACK",
        required = true,
        sourceItemIds = { 21409 },
        appearanceIds = { 207790 },
    })
    local fixture = {}
    for key, value in pairs(base) do fixture[key] = value end
    fixture.id = 399990001
    fixture.collectionId = 399990001
    fixture.collectionKey = "stage2-synthetic-variant"
    fixture.itemSetId = 399990001
    fixture.name = "Stage 2 Synthetic 9-piece Variant"
    fixture.selectedVariantOrdinal = 2
    fixture.variants = {
        { lifecycle = "ACTIVE", isDefault = true, variantOrdinal = 1, members = defaultMembers },
        { lifecycle = "ACTIVE", isDefault = false, variantOrdinal = 2, members = selectedMembers },
    }
    local source = SoloCollections.Data.Sets
    table.insert(source, fixture)
    state.syntheticFixture = { index = #source }
    local resolved = findRecord(currentRecords(), fixture.id)
    if not resolved then
        recordError("SYNTHETIC_QUERY_UNAVAILABLE")
        table.remove(source, state.syntheticFixture.index)
        state.syntheticFixture = nil
        state.phase = "failed"
        return
    end
    beginSelection(resolved, "synthetic", "synthetic selected variant 2/9", false, true)
end

local function beginScrollAudit()
    local page = state.page
    local maximum = math.max(0, (page.scSetRecordCount or 0) - 8)
    local middle = math.floor(maximum / 2)
    page.scSetScrollbar:SetValue(middle)
    state.scroll = { middle = middle }
    state.elapsed = 0
    state.phase = "wait_scroll_middle"
    setStatus("Stage 2 set preview audit", "mid-list slider then wheel continuity")
end

local function finishAudit()
    local db = auditDB()
    local unique = {}
    for _, row in ipairs(db.scanRows or {}) do unique[tonumber(row.setId) or 0] = true end
    local uniqueCount = 0
    for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end
    local scanPass = #db.scanRows == REQUIRED_PRODUCTION_SET_COUNT and uniqueCount == REQUIRED_PRODUCTION_SET_COUNT
    for _, row in ipairs(db.scanRows) do if not row.pass then scanPass = false end end
    local samplePass = true
    local counts = {}
    for _, row in ipairs(db.samples) do
        if not row.pass then samplePass = false end
        if row.label and string.find(row.label, "sample", 1, true) then counts[row.expectedCount] = true end
    end
    for _, count in ipairs(REQUIRED_SAMPLE_COUNTS) do
        if count == 9 and db.syntheticFixturePassed then counts[count] = true end
        if not counts[count] then samplePass = false end
    end
    local paginationPass = type(db.pagination) == "table" and #db.pagination == 4
    for _, row in ipairs(db.pagination or {}) do
        if not row.pass then paginationPass = false end
    end
    db.rowCount = #db.scanRows
    db.uniqueSetCount = uniqueCount
    db.sampleCount = #db.samples
    db.completed = true
    db.requested = false
    db.completedAt = time()
    db.paginationPassed = paginationPass and true or false
    db.ready = db.ready and scanPass and samplePass and paginationPass and db.syntheticFixturePassed
        and db.rapidPassed and db.scroll and db.scroll.pass
    setStatus(db.ready and "Stage 2 set audit: 465/465 READY - reload to persist" or "Stage 2 set audit: FAILED", string.format("rows=%d unique=%d samples=%d", db.rowCount, db.uniqueSetCount, db.sampleCount))
    state.phase = "complete"
end

local function beginAudit()
    state.page = configurePage()
    if not state.page then
        recordError("WARDROBE_PAGE_UNAVAILABLE")
        state.phase = "failed"
        return
    end
    if not installHooks(state.page) then
        recordError("PREVIEW_HOOK_UNAVAILABLE")
        state.phase = "failed"
        return
    end
    state.records = currentRecords()
    if #state.records ~= REQUIRED_PRODUCTION_SET_COUNT then
        recordError("PRODUCTION_SET_COUNT_" .. tostring(#state.records))
        state.phase = "failed"
        return
    end
    local db = auditDB()
    db.ready = true
    db.errors = {}
    db.scanRows = {}
    db.samples = {}
    db.pagination = {}
    db.startedAt = time()
    beginPaginationAudit()
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    local db = auditDB()
    if db.requested then
        state.phase = "setup"
        state.elapsed = 0
    elseif db.completed and not db.reloadObserved then
        db.reloadObserved = true
        db.reloadObservedAt = time()
        setStatus(db.ready and "Stage 2 set audit: reload persistence READY" or "Stage 2 set audit: reload persistence FAILED", string.format("%d rows / %d samples", db.rowCount or 0, db.sampleCount or 0))
        Screenshot()
    end
end)

driver:SetScript("OnUpdate", function(_, elapsed)
    if state.phase == "idle" or state.phase == "complete" or state.phase == "failed" then return end
    state.elapsed = state.elapsed + elapsed
    if state.phase == "setup" and state.elapsed >= SETUP_DELAY then
        beginAudit()
    elseif state.phase == "wait_scroll_middle" and state.elapsed >= 0.12 then
        local page = state.page
        local middleOk = page.scSetOffset == state.scroll.middle
            and math.floor((page.scSetScrollbar:GetValue() or -1) + 0.5) == state.scroll.middle
        page.scSetsPanel:GetScript("OnMouseWheel")(page.scSetsPanel, -1)
        state.scroll.middleOk = middleOk
        state.elapsed = 0
        state.phase = "wait_scroll_wheel"
    elseif state.phase == "wait_scroll_wheel" and state.elapsed >= 0.12 then
        local page = state.page
        local expected = math.min(state.scroll.middle + 1, math.max(0, (page.scSetRecordCount or 0) - 8))
        state.scroll.afterWheel = page.scSetOffset
        state.scroll.scrollbarValue = math.floor((page.scSetScrollbar:GetValue() or -1) + 0.5)
        state.scroll.pass = state.scroll.middleOk and state.scroll.afterWheel == expected
            and state.scroll.scrollbarValue == expected
        if not state.scroll.pass then recordError("SCROLL_CONTINUITY_FAILED") end
        auditDB().scroll = state.scroll
        page.scSetScrollbar:SetValue(0)
        state.phase = "synthetic"
    elseif state.phase == "synthetic" then
        beginSyntheticFixture()
    elseif state.phase == "wait_selection" then
        local page = state.page
        -- Two render ticks are the contract; the small extra delay just lets
        -- the hooked TryOn calls settle without turning the 465-row audit
        -- into a minute-long client stall.
        if page.scSetPreviewPending == nil and state.elapsed >= 0.03 then finishSelection() end
    elseif state.phase == "next_pagination" then
        local case = state.pagination and state.pagination[state.paginationIndex]
        if not case then
            removePaginationFixtures()
            setPageQuery("")
            state.page.scSetScrollbar:SetValue(0)
            beginScrollAudit()
            return
        end
        setPageQuery(case.query)
        state.paginationNeedsOffset = case.expectedOffset
        state.elapsed = 0
        state.phase = "set_pagination_offset"
        setStatus("Stage 2 set preview audit", "pagination " .. case.label)
    elseif state.phase == "set_pagination_offset" then
        -- Let the real search callback rebuild the slider range before
        -- applying its final test position; otherwise a just-expanded slider
        -- can still clamp a programmatic SetValue to its previous zero range.
        if (state.paginationNeedsOffset or 0) > 0 then
            state.page.scSetScrollbar:SetValue(state.paginationNeedsOffset)
        end
        state.elapsed = 0
        state.phase = "wait_pagination"
    elseif state.phase == "wait_pagination" and state.elapsed >= 0.12 then
        local case = state.pagination[state.paginationIndex]
        local page = state.page
        local visible = 0
        for _, row in ipairs(page.scSetRows or {}) do
            if row.scRecord then visible = visible + 1 end
        end
        local minimum, maximum = page.scSetScrollbar:GetMinMaxValues()
        local expectedMaximum = math.max(0, case.expectedCount - 8)
        local pass = page.scSetRecordCount == case.expectedCount
            and page.scSetOffset == case.expectedOffset
            and page.scSetPage == case.expectedPage
            and page.scSetTotalPages == math.max(1, math.ceil(case.expectedCount / 8))
            and visible == case.expectedVisible
            and math.floor((minimum or -1) + 0.5) == 0
            and math.floor((maximum or -1) + 0.5) == expectedMaximum
            and math.floor((page.scSetScrollbar:GetValue() or -1) + 0.5) == case.expectedOffset
        local db = auditDB()
        db.pagination = db.pagination or {}
        table.insert(db.pagination, {
            label = case.label,
            recordCount = page.scSetRecordCount,
            offset = page.scSetOffset,
            page = page.scSetPage,
            totalPages = page.scSetTotalPages,
            visible = visible,
            maximum = maximum,
            query = SoloCollections.db.query,
            catalogCount = #currentRecords(case.query),
            fixtureSourceCount = #(SoloCollections.Data.Sets or {}),
            pass = pass and true or false,
        })
        if not pass then recordError("PAGINATION_" .. tostring(case.label) .. "_FAILED") end
        if case.label == "multi-last-partial" then Screenshot() end
        state.paginationIndex = state.paginationIndex + 1
        state.phase = "next_pagination"
    elseif state.phase == "next_sample" then
        local count = REQUIRED_SAMPLE_COUNTS[state.sampleIndex]
        if not count then
            local pregear
            for _, record in ipairs(state.records) do
                if #previewItems(record) == 2 then pregear = record break end
            end
            if not pregear then
                recordError("PREGEAR_SAMPLE_UNAVAILABLE")
                state.phase = "failed"
            else
                beginSelection(pregear, "pregear", "pregear-clear two-piece", true, true)
            end
            return
        end
        if count == 9 then
            -- Production currently has no nine-piece cohort.  The selected
            -- non-default synthetic fixture above is the real nine-piece
            -- coverage and was verified before this production-only loop.
            state.sampleIndex = state.sampleIndex + 1
            state.phase = "next_sample"
            return
        end
        local sample
        for _, record in ipairs(state.records) do
            if #previewItems(record) == count then sample = record break end
        end
        if not sample then
            recordError("SAMPLE_COUNT_" .. tostring(count) .. "_UNAVAILABLE")
            state.phase = "failed"
        else
            beginSelection(sample, "sample", "sample " .. tostring(count) .. " pieces", false, true)
        end
    elseif state.phase == "rapid" then
        local final = state.records[math.min(RAPID_SELECTION_COUNT, #state.records)]
        state.active = {
            record = final,
            expected = previewItems(final),
            tryOns = {},
            undressCount = 0,
            bucket = "rapid",
            label = "rapid final of " .. tostring(RAPID_SELECTION_COUNT),
            screenshot = true,
        }
        for index = 1, math.min(RAPID_SELECTION_COUNT, #state.records) do
            state.page.scSetSelectedId = state.records[index].id
            state.page:Refresh()
        end
        state.active.generation = state.page.scSetPreviewGeneration
        state.elapsed = 0
        state.phase = "wait_selection"
    elseif state.phase == "next_scan" then
        local record = state.records[state.scanIndex]
        if not record then finishAudit() else
            beginSelection(record, "scan", "scan " .. tostring(state.scanIndex) .. "/" .. tostring(#state.records), false, false)
        end
    end
end)
