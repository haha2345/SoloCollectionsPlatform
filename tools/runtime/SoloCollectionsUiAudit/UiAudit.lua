local TARGET_ITEM_ID = 50012
local TARGET_SYNTHETIC_DISPLAY_ID = 40005
local EXPECT_UNAVAILABLE = SoloCollectionsUiAuditDB and SoloCollectionsUiAuditDB.expectUnavailable == true
local SETUP_DELAY = 1.0
local VERIFY_DELAY = 4.0

local frame = CreateFrame("Frame")
local elapsed = 0
local phase = "WAIT"

local banner = CreateFrame("Frame", nil, UIParent)
banner:SetWidth(520)
banner:SetHeight(34)
banner:SetPoint("TOP", UIParent, "TOP", 0, -24)
banner:SetFrameStrata("TOOLTIP")
banner:Hide()
local background = banner:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(banner)
background:SetTexture(0.04, 0.04, 0.04, 0.94)
local text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetPoint("CENTER")

local function showResult(ok, message)
    text:SetTextColor(ok and 0.25 or 1.0, ok and 1.0 or 0.25, 0.25)
    text:SetText(message)
    banner:Show()
end

local function findTarget()
    local catalog = SoloCollections and SoloCollections.Catalog
    if not catalog or not catalog.Get then return nil end
    for _, record in ipairs(catalog.Get("APPEARANCES") or {}) do
        if record.itemId == TARGET_ITEM_ID then
            return record
        end
    end
    return nil
end

local function fail(reason)
    SoloCollectionsUiAuditDB = {
        completed = true,
        ready = false,
        reason = reason,
        targetItemId = TARGET_ITEM_ID,
    }
    showResult(false, "SoloCollections formal UI audit: FAILED - " .. reason)
    frame:SetScript("OnUpdate", nil)
end

local function setup()
    local SC = SoloCollections
    local record = findTarget()
    if not SC or not SC.db or not SC.UI or not record then
        fail("TARGET_OR_UI_MISSING")
        return
    end
    local journal = SC.UI.CreateCollectionsFrame()
    journal:Show()
    SC.db.query = ""
    SC.db.wardrobeTab = "ITEMS"
    SC.db.mainTab = "WARDROBE"
    SC.db.filters.collected = true
    SC.db.filters.uncollected = true
    SC.db.filters.favorites = false
    SC.db.filters.classToken = "ALL"
    SC.db.filters.armorType = "ALL"
    SC.db.filters.slot = "MAINHAND"
    SC.db.filters.weaponType = "ONE_HAND_AXE"
    SC.UI.SetWardrobeTab("ITEMS")
    SC.UI.SetMainTab("WARDROBE")
    local page = journal.scPages and journal.scPages.WARDROBE
    local candidates = SC.Catalog.QueryAll("APPEARANCES", "", SC.db.filters)
    for index, candidate in ipairs(candidates) do
        if candidate.itemId == TARGET_ITEM_ID then
            page.scItemPage = math.ceil(index / 18)
            page:Refresh()
            break
        end
    end
    phase = "VERIFY"
    elapsed = 0
end

local function verify()
    local SC = SoloCollections
    local candidates = SC and SC.Catalog and SC.Catalog.QueryAll
        and SC.Catalog.QueryAll("APPEARANCES", "", SC.db.filters) or {}
    local journal = SC and SC.UI and SC.UI.CollectionsFrame
    local page = journal and journal.scPages and journal.scPages.WARDROBE
    local card
    for _, candidateCard in ipairs(page and page.scItemModels or {}) do
        if candidateCard.scRecord and candidateCard.scRecord.itemId == TARGET_ITEM_ID then
            card = candidateCard
            break
        end
    end
    local record = card and card.scRecord
    local objectModel = card and card.scObjectModel
    local rawActualModel = objectModel and objectModel.GetModel and objectModel:GetModel() or nil
    local actualModel = type(rawActualModel) == "string" and rawActualModel or nil
    local expectedModel = record and record.modelPath or nil
    local standaloneReady = record and record.itemId == TARGET_ITEM_ID
        and record.renderMode == "STANDALONE"
        and record.syntheticDisplayId == TARGET_SYNTHETIC_DISPLAY_ID
        and type(actualModel) == "string"
        and string.lower(actualModel) == string.lower(expectedModel or "")
        and objectModel:IsShown()
        and not card:IsShown()
        and not (card.scUnavailable and card.scUnavailable:IsShown())
    local unavailableReady = record and record.itemId == TARGET_ITEM_ID
        and record.renderMode == "STANDALONE"
        and record.syntheticDisplayId == TARGET_SYNTHETIC_DISPLAY_ID
        and not objectModel:IsShown()
        and not card:IsShown()
        and card.scUnavailable and card.scUnavailable:IsShown()
    local ready = EXPECT_UNAVAILABLE and unavailableReady or standaloneReady
    SoloCollectionsUiAuditDB = {
        completed = true,
        ready = ready and true or false,
        reason = ready and "READY" or "FORMAL_PAGE_MODEL_MISMATCH",
        targetItemId = TARGET_ITEM_ID,
        collectionId = record and record.id or nil,
        renderMode = record and record.renderMode or nil,
        syntheticDisplayId = record and record.syntheticDisplayId or nil,
        expectedModel = expectedModel,
        actualModel = actualModel,
        actualModelType = type(rawActualModel),
        objectVisible = objectModel and objectModel:IsShown() or false,
        characterVisible = card and card:IsShown() or false,
        unavailableVisible = card and card.scUnavailable and card.scUnavailable:IsShown() or false,
        expectedMode = EXPECT_UNAVAILABLE and "UNAVAILABLE" or "STANDALONE",
        candidateCount = #candidates,
        firstCandidateItemId = candidates[1] and candidates[1].itemId or nil,
        targetRecordSlot = findTarget() and findTarget().slot or nil,
        targetRecordWeaponType = findTarget() and findTarget().weaponType or nil,
        activeFilterSlot = SC.db.filters.slot,
        activeFilterWeaponType = SC.db.filters.weaponType,
    }
    local successMessage = EXPECT_UNAVAILABLE
        and "SoloCollections formal UI audit: READY - stock fallback unavailable"
        or "SoloCollections formal UI audit: READY - standalone weapon only"
    showResult(ready, ready and successMessage or "SoloCollections formal UI audit: FAILED - inspect SavedVariables")
    frame:SetScript("OnUpdate", nil)
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    elapsed = 0
    phase = "WAIT"
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if phase == "WAIT" and elapsed >= SETUP_DELAY then
            setup()
        elseif phase == "VERIFY" and elapsed >= VERIFY_DELAY then
            verify()
        end
    end)
end)
