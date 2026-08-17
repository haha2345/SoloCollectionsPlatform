local SC = SoloCollections

-- Development-only instrumentation: synthetic benchmarks and page timing
-- probes. Stable builds keep the file for contract reference but never
-- register the module.
if SC.BUILD_CHANNEL ~= "development" then
    return
end

SC.Diagnostics = SC.Diagnostics or {}
local Diagnostics = SC.Diagnostics

local function timer()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    return GetTime() * 1000
end

local function toBase36(value)
    local alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    local result = ""
    repeat
        local digit = value % 36
        result = string.sub(alphabet, digit + 1, digit + 1) .. result
        value = math.floor(value / 36)
    until value == 0
    return result
end

local function pageTiming(key)
    local started = timer()
    SC.UI.SetMainTab(key)
    SC.UI.RefreshActivePage()
    return timer() - started
end

local function snapshotBenchmark()
    local memoryBefore = collectgarbage("count")
    local values = {}
    local bytes = 0
    local value = 1
    while true do
        local token = toBase36(value)
        local added = #token + (#values > 0 and 1 or 0)
        if bytes + added > 32000 then
            break
        end
        values[#values + 1] = token
        bytes = bytes + added
        value = value + 1
    end
    local payload = table.concat(values, ",")
    local chunks = {}
    for offset = 1, #payload, 160 do
        chunks[#chunks + 1] = string.sub(payload, offset, offset + 159)
    end
    local started = timer()
    local reassembled = table.concat(chunks)
    local owned = SC.CollectionState.parseOwnedPayload(reassembled)
    local elapsed = timer() - started
    local ownedCount = 0
    for _ in pairs(owned or {}) do ownedCount = ownedCount + 1 end
    local memoryPeak = collectgarbage("count")
    values, chunks, payload, reassembled, owned = nil, nil, nil, nil, nil
    collectgarbage("collect")
    return {
        chunks = math.ceil(bytes / 160),
        bytes = bytes,
        owned = ownedCount,
        elapsedMs = elapsed,
        peakMemoryKb = math.max(0, memoryPeak - memoryBefore),
    }
end

local function hiddenModelDiagnostics(frame)
    local pending = 0
    local activeUpdates = 0
    for _, key in ipairs({ "MOUNTS", "PETS", "WARDROBE" }) do
        local page = frame.scPages[key]
        if page and not page:IsShown() then
            pending = pending + #(page.scModelTasks or {})
            for _, model in ipairs(page.scItemModels or {}) do
                if model:GetScript("OnUpdate") then activeUpdates = activeUpdates + 1 end
            end
        end
    end
    return pending, activeUpdates
end

function Diagnostics.RunPerformanceBaseline()
    local frame = SC.UI and SC.UI.CollectionsFrame
    if not frame then
        print("SC_PERF unavailable collections_frame=missing")
        return nil
    end
    local originalTab = SC.db.mainTab
    local originalWardrobeTab = SC.db.wardrobeTab
    local originalQuery = SC.db.query
    local pageResults = {}
    for _, key in ipairs({ "MOUNTS", "PETS", "TOYS", "WARDROBE", "TITLES" }) do
        pageResults[key] = pageTiming(key)
    end

    local synthetic = SC.Catalog.RunSyntheticAppearanceBenchmark(18190)
    local expanded = SC.Catalog.RunExpandedCollectionBenchmark(18190, 201, 509)
    local snapshot = snapshotBenchmark()
    SC.UI.SetMainTab("TITLES")
    local pendingTasks, hiddenUpdates = hiddenModelDiagnostics(frame)
    local wardrobe = frame.scPages.WARDROBE
    local poolSize = wardrobe and #(wardrobe.scItemModels or {}) or 0

    print(string.format(
        "SC_PERF pages_ms mounts=%.3f pets=%.3f toys=%.3f wardrobe=%.3f titles=%.3f",
        pageResults.MOUNTS, pageResults.PETS, pageResults.TOYS, pageResults.WARDROBE, pageResults.TITLES))
    print(string.format(
        "SC_PERF catalog scale=%d load_ms=%.3f filter_ms=%.3f page_ms=%.3f peak_kb=%.1f model_pool=%d",
        synthetic.count, synthetic.loadMs, synthetic.filterMs, synthetic.pageMs,
        synthetic.peakMemoryKb, poolSize))
    print(string.format(
        "SC_PERF expanded appearances=%d companions=%d sets=%d load_ms=%.3f filter_ms=%.3f page_ms=%.3f pages=%d peak_kb=%.1f",
        expanded.appearances, expanded.companions, expanded.sets, expanded.loadMs,
        expanded.filterMs, expanded.pageMs, expanded.pages, expanded.peakMemoryKb))
    print(string.format(
        "SC_PERF snapshot chunks=%d bytes=%d owned=%d reassembly_ms=%.3f peak_kb=%.1f",
        snapshot.chunks, snapshot.bytes, snapshot.owned, snapshot.elapsedMs, snapshot.peakMemoryKb))
    print(string.format(
        "SC_PERF hidden pending_model_tasks=%d active_card_onupdates=%d",
        pendingTasks, hiddenUpdates))

    SC.db.mainTab = originalTab
    SC.db.wardrobeTab = originalWardrobeTab
    SC.db.query = originalQuery
    SC.UI.SyncJournalFromDatabase()
    return { pages = pageResults, catalog = synthetic, expanded = expanded, snapshot = snapshot,
        hiddenPendingTasks = pendingTasks, hiddenActiveUpdates = hiddenUpdates, modelPool = poolSize }
end
