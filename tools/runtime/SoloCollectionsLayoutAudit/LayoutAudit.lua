local SETUP_DELAY = 2.0
local COLLECTED = { 0.58, 0.43, 0.16, 1 }
local UNCOLLECTED = { 0.38, 0.39, 0.40, 1 }
local SELECTED = { 1.00, 0.78, 0.14, 1 }

local driver = CreateFrame("Frame")
local elapsed = 0

local banner = CreateFrame("Frame", nil, UIParent)
banner:SetWidth(620)
banner:SetHeight(34)
banner:SetPoint("TOP", UIParent, "TOP", 0, -24)
banner:SetFrameStrata("TOOLTIP")
local background = banner:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(banner)
background:SetTexture(0.04, 0.04, 0.04, 0.94)
local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bannerText:SetPoint("CENTER")

local function near(actual, expected)
    return math.abs((tonumber(actual) or 0) - expected) <= 0.01
end

local function colorOf(border)
    local edge = border and border.scEdges and border.scEdges[1]
    if not edge or not edge.GetVertexColor then
        return nil
    end
    local red, green, blue, alpha = edge:GetVertexColor()
    return { red, green, blue, alpha }
end

local function colorMatches(actual, expected)
    return actual
        and near(actual[1], expected[1])
        and near(actual[2], expected[2])
        and near(actual[3], expected[3])
        and near(actual[4], expected[4])
end

local function thicknessOf(border)
    local edge = border and border.scEdges and border.scEdges[1]
    return edge and edge:GetHeight() or nil
end

local function syntheticRecord(index, collected)
    return {
        id = 990000 + index,
        itemId = 6948,
        name = "Layout audit " .. index,
        source = collected and "Collected state" or "Uncollected state",
        description = "Temporary phase-4 layout evidence",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        collected = collected and true or false,
        favorite = index == 1,
    }
end

local function countShown(tiles)
    local count = 0
    for _, tile in ipairs(tiles or {}) do
        if tile:IsShown() then
            count = count + 1
        end
    end
    return count
end

local function setVisibleCount(tiles, count)
    for index, tile in ipairs(tiles or {}) do
        tile:SetRecord(index <= count and syntheticRecord(index, index % 2 == 1) or nil)
    end
    return countShown(tiles)
end

local function validateRows(page)
    local first = page and page.scRows and page.scRows[1]
    local second = page and page.scRows and page.scRows[2]
    if not first or not second then
        return { ready = false, reason = "ROWS_MISSING" }
    end
    first:SetRecord(syntheticRecord(1, true))
    second:SetRecord(syntheticRecord(2, false))
    local collectedBefore = colorOf(first.scCollectionBorder)
    first:SetSelected(true)
    second:SetSelected(false)
    local collectedAfter = colorOf(first.scCollectionBorder)
    return {
        ready = colorMatches(collectedBefore, COLLECTED)
            and colorMatches(collectedAfter, COLLECTED)
            and colorMatches(colorOf(second.scCollectionBorder), UNCOLLECTED)
            and colorMatches(colorOf(first.scSelectionBorder), SELECTED)
            and first.scSelectionBorder:IsShown()
            and near(thicknessOf(first.scCollectionBorder), 1)
            and near(thicknessOf(first.scSelectionBorder), 2),
        collectedBefore = collectedBefore,
        collectedAfterSelection = collectedAfter,
        uncollected = colorOf(second.scCollectionBorder),
        selected = colorOf(first.scSelectionBorder),
        collectionThickness = thicknessOf(first.scCollectionBorder),
        selectionThickness = thicknessOf(first.scSelectionBorder),
    }
end

local function runAudit()
    local SC = SoloCollections
    if not SC or not SC.UI or not SC.db then
        return nil, "SOLO_COLLECTIONS_MISSING"
    end
    local journal = SC.UI.CreateCollectionsFrame()
    journal:Show()
    local priorMainTab = SC.db.mainTab
    local priorQuery = SC.db.query
    local priorFilters = {
        collected = SC.db.filters.collected,
        uncollected = SC.db.filters.uncollected,
        favorites = SC.db.filters.favorites,
    }

    SC.db.query = ""
    SC.db.filters.collected = true
    SC.db.filters.uncollected = true
    SC.db.filters.favorites = false

    SC.UI.SetMainTab("MOUNTS")
    local mountPage = journal.scPages and journal.scPages.MOUNTS
    local mountRows = validateRows(mountPage)
    if mountPage and mountPage.scInfoBorder then
        mountPage.scInfoBorder:SetCollected(true)
        mountPage.scInfoSelectedBorder:Show()
    end
    mountRows.detailReady = (mountPage
        and colorMatches(colorOf(mountPage.scInfoBorder), COLLECTED)
        and colorMatches(colorOf(mountPage.scInfoSelectedBorder), SELECTED)
        and near(thicknessOf(mountPage.scInfoBorder), 1)
        and near(thicknessOf(mountPage.scInfoSelectedBorder), 2)) and true or false

    SC.UI.SetMainTab("PETS")
    local petPage = journal.scPages and journal.scPages.PETS
    local petRows = validateRows(petPage)
    if petPage and petPage.scInfoBorder then
        petPage.scInfoBorder:SetCollected(false)
        petPage.scInfoSelectedBorder:Show()
    end
    petRows.detailReady = (petPage
        and colorMatches(colorOf(petPage.scInfoBorder), UNCOLLECTED)
        and colorMatches(colorOf(petPage.scInfoSelectedBorder), SELECTED)
        and near(thicknessOf(petPage.scInfoBorder), 1)
        and near(thicknessOf(petPage.scInfoSelectedBorder), 2)) and true or false

    SC.UI.SetMainTab("TOYS")
    local toyPage = journal.scPages and journal.scPages.TOYS
    if not toyPage or not toyPage.scTiles or #toyPage.scTiles ~= 18 then
        return nil, "TOY_POOL_MISSING"
    end
    toyPage.scLayoutTiles()
    local visibleCounts = {
        one = setVisibleCount(toyPage.scTiles, 1),
        two = setVisibleCount(toyPage.scTiles, 2),
        four = setVisibleCount(toyPage.scTiles, 4),
        full = setVisibleCount(toyPage.scTiles, 18),
    }
    local first = toyPage.scTiles[1]
    local second = toyPage.scTiles[2]
    local third = toyPage.scTiles[3]
    local last = toyPage.scTiles[18]
    first:SetSelected(true)
    second:SetSelected(false)
    second.scHover:Show()
    local firstCollectionBefore = colorOf(first.scBorder)
    first:SetSelected(true)
    local firstCollectionAfter = colorOf(first.scBorder)
    local _, _, _, firstX, firstY = first:GetPoint(1)
    local _, _, _, secondX = second:GetPoint(1)
    local _, _, _, thirdX = third:GetPoint(1)
    local _, _, _, fourthX, fourthY = toyPage.scTiles[4]:GetPoint(1)
    if type(firstX) ~= "number" or type(firstY) ~= "number"
        or type(secondX) ~= "number" or type(thirdX) ~= "number"
        or type(fourthX) ~= "number" or type(fourthY) ~= "number" then
        return nil, "TOY_LAYOUT_PENDING"
    end
    local gridWidth = toyPage.scGrid:GetWidth()
    local leftMargin = firstX
    local rightMargin = gridWidth - thirdX - third:GetWidth()
    local horizontalGap = secondX - firstX - first:GetWidth()
    local verticalGap = math.abs(fourthY - firstY) - first:GetHeight()

    local toyReady = (colorMatches(firstCollectionBefore, COLLECTED)
        and colorMatches(firstCollectionAfter, COLLECTED)
        and colorMatches(colorOf(second.scBorder), UNCOLLECTED)
        and colorMatches(colorOf(first.scSelectionBorder), SELECTED)
        and first.scSelectionBorder:IsShown()
        and second.scHover:IsShown()
        and near(thicknessOf(first.scBorder), 1)
        and near(thicknessOf(first.scSelectionBorder), 2)
        and math.abs(leftMargin - rightMargin) <= 1.01
        and near(horizontalGap, 6)
        and math.abs(verticalGap) <= 0.01
        and visibleCounts.one == 1
        and visibleCounts.two == 2
        and visibleCounts.four == 4
        and visibleCounts.full == 18
        and last:IsShown()) and true or false

    SoloCollectionsLayoutAuditDB = SoloCollectionsLayoutAuditDB or { runs = {} }
    SoloCollectionsLayoutAuditDB.runs = SoloCollectionsLayoutAuditDB.runs or {}
    local run = {
        completed = true,
        ready = (mountRows.ready and mountRows.detailReady
            and petRows.ready and petRows.detailReady and toyReady) and true or false,
        screenWidth = GetScreenWidth(),
        screenHeight = GetScreenHeight(),
        uiScaleCVar = GetCVar("uiScale"),
        useUiScaleCVar = GetCVar("useUiScale"),
        uiParentEffectiveScale = UIParent:GetEffectiveScale(),
        journalScale = journal:GetScale(),
        priorMainTab = priorMainTab,
        priorQuery = priorQuery,
        priorFilters = priorFilters,
        reloadRestored = #SoloCollectionsLayoutAuditDB.runs == 0 or priorMainTab == "TOYS",
        mounts = mountRows,
        pets = petRows,
        toys = {
            ready = toyReady,
            poolSize = #toyPage.scTiles,
            visibleCounts = visibleCounts,
            gridWidth = gridWidth,
            tileWidth = first:GetWidth(),
            tileHeight = first:GetHeight(),
            leftMargin = leftMargin,
            rightMargin = rightMargin,
            horizontalGap = horizontalGap,
            verticalGap = verticalGap,
            firstAnchorX = firstX,
            firstAnchorY = firstY,
            fourthAnchorX = fourthX,
            fourthAnchorY = fourthY,
            firstCollectionBefore = firstCollectionBefore,
            firstCollectionAfterSelection = firstCollectionAfter,
            secondCollection = colorOf(second.scBorder),
            selected = colorOf(first.scSelectionBorder),
            hoverVisible = second.scHover:IsShown(),
            collectionThickness = thicknessOf(first.scBorder),
            selectionThickness = thicknessOf(first.scSelectionBorder),
        },
    }
    table.insert(SoloCollectionsLayoutAuditDB.runs, run)
    SoloCollectionsLayoutAuditDB.completed = true
    SoloCollectionsLayoutAuditDB.ready = run.ready
    SoloCollectionsLayoutAuditDB.latest = run

    SC.db.mainTab = "TOYS"
    SC.db.query = ""
    SC.db.filters.collected = true
    SC.db.filters.uncollected = true
    SC.db.filters.favorites = false
    bannerText:SetTextColor(run.ready and 0.25 or 1.0, run.ready and 1.0 or 0.25, 0.25)
    bannerText:SetText(run.ready
        and "SoloCollections phase-4 layout audit: READY"
        or "SoloCollections phase-4 layout audit: FAILED")
    Screenshot()
    return run
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    elapsed = 0
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < SETUP_DELAY then
            return
        end
        local ok, run, reason = pcall(runAudit)
        if ok and not run and reason == "TOY_LAYOUT_PENDING" and elapsed < (SETUP_DELAY + 5) then
            return
        end
        driver:SetScript("OnUpdate", nil)
        if not ok or not run then
            SoloCollectionsLayoutAuditDB = SoloCollectionsLayoutAuditDB or { runs = {} }
            SoloCollectionsLayoutAuditDB.completed = true
            SoloCollectionsLayoutAuditDB.ready = false
            SoloCollectionsLayoutAuditDB.reason = ok and reason or tostring(run)
            bannerText:SetTextColor(1.0, 0.25, 0.25)
            bannerText:SetText("SoloCollections phase-4 layout audit: FAILED")
            Screenshot()
        end
    end)
end)
