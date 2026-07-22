local SC = SoloCollections

SC.Catalog = SC.Catalog or {}

local Catalog = SC.Catalog

local CATEGORY_KEYS = {
    MOUNTS = "Mounts",
    PETS = "Pets",
    TOYS = "Toys",
    APPEARANCES = "Appearances",
    SETS = "Sets",
}

local DEFAULT_FILTERS = {
    collected = true,
    uncollected = true,
    favorites = false,
    classToken = "ALL",
    armorType = "AUTO",
    slot = "HEAD",
    weaponType = "AUTO",
}

local WEAPON_SLOTS = { MAINHAND = true, OFFHAND = true }
local generatedMountSource = nil
local generatedCompanionSource = nil
local generatedToySource = nil
local generatedAppearanceSource = nil

local function getGeneratedMountSource()
    if generatedMountSource then
        return generatedMountSource
    end
    generatedMountSource = {}
    local generated = SC.GeneratedCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        if collection.typeKey == "mount" and collection.lifecycle == "active" then
            local names = collection.name or {}
            table.insert(generatedMountSource, {
                id = collection.collectionId,
                previewCreatureEntry = collection.previewCreatureEntry or collection.displayCreatureId,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = collection.iconTexture,
                presentationStatus = collection.presentationStatus,
                source = "账号收藏",
                description = "由 SoloCollections 服务端权威目录提供。",
                collected = false,
                favorite = false,
            })
        end
    end
    return generatedMountSource
end

local function getGeneratedCompanionSource()
    if generatedCompanionSource then
        return generatedCompanionSource
    end
    generatedCompanionSource = {}
    local generated = SC.GeneratedCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        if collection.typeKey == "companion" and collection.lifecycle == "active" then
            local names = collection.name or {}
            table.insert(generatedCompanionSource, {
                id = collection.collectionId,
                previewCreatureEntry = collection.previewCreatureEntry or collection.displayCreatureId,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = collection.iconTexture,
                presentationStatus = collection.presentationStatus,
                source = "账号收藏",
                description = "由 SoloCollections 服务端权威目录提供。",
                collected = false,
                favorite = false,
            })
        end
    end
    return generatedCompanionSource
end

local function getGeneratedToySource()
    if generatedToySource then
        return generatedToySource
    end
    generatedToySource = {}
    local generated = SC.GeneratedCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        if collection.typeKey == "toy" and collection.lifecycle == "active" then
            local names = collection.name or {}
            table.insert(generatedToySource, {
                id = collection.collectionId,
                itemId = collection.displayItemId,
                targetPolicy = collection.targetPolicy or (collection.requiresTarget and "REQUIRED_UNIT" or "SELF"),
                requiresTarget = collection.requiresTarget and true or false,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = "Interface\\Icons\\INV_Misc_Toy_10",
                source = "账号收藏",
                description = "由 SoloCollections 服务端权威动作目录提供。",
                collected = false,
                favorite = false,
            })
        end
    end
    return generatedToySource
end

local function getGeneratedAppearanceSource()
    if generatedAppearanceSource then
        return generatedAppearanceSource
    end
    generatedAppearanceSource = {}
    local generated = SC.GeneratedCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        if collection.typeKey == "appearance" and collection.lifecycle == "active" then
            local names = collection.name or {}
            local itemIds = {}
            local slot = "HEAD"
            local armorType
            local weaponType
            for _, alias in ipairs(collection.aliases or {}) do
                local itemId = string.match(alias, "^item:(%d+)$")
                if itemId then
                    table.insert(itemIds, tonumber(itemId))
                else
                    slot = string.match(alias, "^slot:(.+)$") or slot
                    armorType = string.match(alias, "^armor:(.+)$") or armorType
                    weaponType = string.match(alias, "^weapon:(.+)$") or weaponType
                end
            end
            if #itemIds == 0 and tonumber(collection.displayItemId) then
                itemIds[1] = tonumber(collection.displayItemId)
            end
            table.insert(generatedAppearanceSource, {
                id = collection.collectionId,
                itemId = tonumber(collection.displayItemId) or itemIds[1],
                itemIds = itemIds,
                slot = slot,
                armorType = armorType,
                weaponType = collection.weaponType or weaponType,
                weaponCategory = collection.weaponCategory,
                renderMode = collection.renderMode,
                syntheticDisplayId = collection.syntheticDisplayId,
                modelPath = collection.modelPath,
                modelScale = collection.modelScale,
                cameraTuningKey = collection.cameraTuningKey,
                m2Camera = collection.m2Camera,
                presentationStatus = collection.presentationStatus,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = nil,
                source = "账号收藏",
                description = "canonical 外观；来源物品可追溯。",
                collected = false,
                favorite = false,
            })
        end
    end
    return generatedAppearanceSource
end

local function resolvedWeaponType(record)
    local weaponType = record.weaponCategory or record.weaponType
    -- Warglaives are one-handed swords in the 3.3.5 item subclass table.
    -- Keep the special camera key in Data, but never expose a Retail-only
    -- "warglaive" filter category in the WotLK wardrobe.
    if weaponType == "WAR_GLAIVE" then
        return "ONE_HAND_SWORD"
    end
    return weaponType
end

local function armorTypeMatches(record, filters)
    if WEAPON_SLOTS[record.slot] then
        return true
    end
    local selected = filters.armorType
    if not selected or selected == "AUTO" or selected == "ALL" then
        return true
    end
    local recordType = record.armorType or "ALL"
    return recordType == "ALL" or recordType == selected
end

local function weaponTypeMatches(record, filters)
    if not WEAPON_SLOTS[record.slot] then
        return true
    end
    local selected = filters.weaponType
    if not selected or selected == "AUTO" or selected == "ALL" then
        return true
    end
    return resolvedWeaponType(record) == selected
end

local function copyRecord(source)
    local copy = {}
    for key, value in pairs(source) do
        if key == "itemIds" and type(value) == "table" then
            local itemIds = {}
            for index, itemId in ipairs(value) do
                itemIds[index] = itemId
            end
            copy[key] = itemIds
        else
            copy[key] = value
        end
    end
    return copy
end

local function overlayCollectionState(category, record, fallback)
    local collectionState = SC.CollectionState
    if collectionState and collectionState.ResolveOwned then
        local collected, ownershipKnown, state = SC.CollectionState.ResolveOwned(category, record.id, fallback)
        record.collected = collected
        record.ownershipKnown = ownershipKnown
        record.collectionState = state
    else
        record.collected = fallback and true or false
        record.ownershipKnown = false
        record.collectionState = "Demo"
    end
    return record
end

local function deriveSetState(record)
    local collectionState = SC.CollectionState
    local categoryState = collectionState and collectionState.GetCategoryState and
        collectionState.GetCategoryState("APPEARANCES") or "Demo"
    local ownershipKnown = categoryState == "Ready"
    local bestOwned = 0
    local bestRequired = 0
    local complete = false
    local selectedVariant
    local requestedOrdinal = tonumber(record.selectedVariantOrdinal)
    for _, variant in ipairs(record.variants or {}) do
        if variant.lifecycle == "ACTIVE" then
            local owned = 0
            local required = 0
            for _, member in ipairs(variant.members or {}) do
                if member.required then
                    required = required + 1
                    local memberOwned = false
                    for _, appearanceId in ipairs(member.appearanceIds or {}) do
                        if collectionState and collectionState.IsOwnedByType and
                            collectionState.IsOwnedByType(13, appearanceId) then
                            memberOwned = true
                            break
                        end
                    end
                    if memberOwned then owned = owned + 1 end
                end
            end
            local variantComplete = required > 0 and owned == required
            local requested = requestedOrdinal and tonumber(variant.variantOrdinal) == requestedOrdinal
            if requested or (not selectedVariant and (variant.isDefault or bestRequired == 0)) or
                (not requestedOrdinal and owned * bestRequired > bestOwned * required) then
                bestOwned = owned
                bestRequired = required
                selectedVariant = variant
            end
            if variantComplete then
                complete = true
                break
            end
        end
    end
    record.collectedCount = bestOwned
    record.requiredCount = bestRequired
    record.collected = complete
    record.ownershipKnown = ownershipKnown
    record.collectionState = ownershipKnown and "Derived" or categoryState
    record.selectedVariant = selectedVariant
    return record
end

local function resolveRecordState(category, record, fallback)
    if category == "SETS" then
        return deriveSetState(record)
    end
    return overlayCollectionState(category, record, fallback)
end

local function getSource(category)
    if category == "MOUNTS" and SC.GeneratedCatalog then
        return getGeneratedMountSource()
    end
    if category == "PETS" and SC.GeneratedCatalog then
        return getGeneratedCompanionSource()
    end
    if category == "TOYS" and SC.GeneratedCatalog then
        return getGeneratedToySource()
    end
    if category == "APPEARANCES" and SC.GeneratedCatalog then
        return getGeneratedAppearanceSource()
    end
    local key = CATEGORY_KEYS[category]
    if not key or not SC.Data then
        return nil
    end
    return SC.Data[key]
end

local function ensureFavoriteStore(category)
    if type(SoloCollectionsDB) ~= "table" then
        SoloCollectionsDB = {}
    end
    if type(SoloCollectionsDB.favorites) ~= "table" then
        SoloCollectionsDB.favorites = {}
    end
    if type(SoloCollectionsDB.favorites[category]) ~= "table" then
        SoloCollectionsDB.favorites[category] = {}
    end
    return SoloCollectionsDB.favorites[category]
end

local function isCollectibleCompanion(category)
    return category == "MOUNTS" or category == "PETS"
end

local function getFavorite(category, record)
    -- A collectible companion cannot be a usable favorite before it is
    -- collected. This also neutralizes old overrides and demo-data defaults.
    if isCollectibleCompanion(category) and not record.collected then
        return false
    end
    local database = SoloCollectionsDB
    if type(database) ~= "table" then
        return record.favorite and true or false
    end
    local categories = database.favorites
    if type(categories) ~= "table" then
        return record.favorite and true or false
    end
    local overrides = categories[category]
    if type(overrides) ~= "table" then
        return record.favorite and true or false
    end
    if overrides[record.id] ~= nil then
        return overrides[record.id] and true or false
    end
    return record.favorite and true or false
end

local function resolvedFilters(filters)
    local result = {}
    for key, defaultValue in pairs(DEFAULT_FILTERS) do
        if filters and filters[key] ~= nil then
            result[key] = filters[key]
        else
            result[key] = defaultValue
        end
    end
    return result
end

local function classMatches(record, classToken)
    if not classToken or classToken == "ALL" then
        return true
    end
    if record.classPolicy then
        if record.classPolicy.mode == "ANY" then
            return true
        end
        if record.classPolicy.mode ~= "ALLOW_LIST" then
            return false
        end
        local wanted = string.lower(tostring(classToken))
        for _, allowed in ipairs(record.classPolicy.allowedClassKeys or {}) do
            if allowed == wanted then return true end
        end
        return false
    elseif record.classToken then
        return record.classToken == classToken
    end
    local classBit = SC.IdentityRegistry.GetLegacyClassBit(classToken)
    local classMask = tonumber(record.classMask)
    if not classBit or not classMask then
        return false
    end
    return math.floor(classMask / classBit) % 2 == 1
end

local function stateMatches(record, filters)
    if record.collected then
        return filters.collected
    end
    return filters.uncollected
end

local function metadataMatches(record, query)
    query = string.lower(tostring(query or ""))
    query = string.gsub(query, "^%s+", "")
    query = string.gsub(query, "%s+$", "")
    if query == "" then
        return true
    end
    local haystack = table.concat({
        tostring(record.name or ""),
        tostring(record.source or ""),
        tostring(record.description or ""),
    }, " ")
    return string.find(string.lower(haystack), query, 1, true) ~= nil
end

local function filterMatches(category, record, query, filters, includeCollectionState)
    if includeCollectionState and not stateMatches(record, filters) then
        return false
    end
    if filters.favorites and not getFavorite(category, record) then
        return false
    end
    local usesClassFilter = category == "SETS"
    if usesClassFilter and not classMatches(record, filters.classToken) then
        return false
    end
    if category == "APPEARANCES" and filters.slot and filters.slot ~= "ALL" and record.slot ~= filters.slot then
        return false
    end
    if category == "APPEARANCES" and not armorTypeMatches(record, filters) then
        return false
    end
    if category == "APPEARANCES" and not weaponTypeMatches(record, filters) then
        return false
    end
    return metadataMatches(record, query)
end

function Catalog.Get(category)
    local result = {}
    local source = getSource(category)
    if not source then
        return result
    end
    for index, sourceRecord in ipairs(source) do
        local record = resolveRecordState(category, copyRecord(sourceRecord), sourceRecord.collected)
        record.favorite = getFavorite(category, record)
        result[index] = record
    end
    return result
end

function Catalog.QueryAll(category, query, filters)
    local matches = {}
    local source = getSource(category) or {}
    local activeFilters = resolvedFilters(filters)
    for _, sourceRecord in ipairs(source) do
        local record = resolveRecordState(category, copyRecord(sourceRecord), sourceRecord.collected)
        if filterMatches(category, record, query, activeFilters, true) then
            record.favorite = getFavorite(category, record)
            table.insert(matches, record)
        end
    end
    return matches
end

function Catalog.Query(category, query, filters, page, pageSize)
    local matches = Catalog.QueryAll(category, query, filters)
    pageSize = math.max(1, math.floor(tonumber(pageSize) or 18))
    local total = #matches
    local totalPages = math.max(1, math.ceil(total / pageSize))
    page = math.max(1, math.min(math.floor(tonumber(page) or 1), totalPages))
    local firstIndex = ((page - 1) * pageSize) + 1
    local lastIndex = math.min(total, firstIndex + pageSize - 1)
    local pageRecords = {}
    for index = firstIndex, lastIndex do
        table.insert(pageRecords, matches[index])
    end
    return pageRecords, page, totalPages, total
end

function Catalog.RunSyntheticAppearanceBenchmark(count)
    count = math.max(1, math.min(50000, math.floor(tonumber(count) or 17000)))
    local timer = type(debugprofilestop) == "function" and debugprofilestop or function() return GetTime() * 1000 end
    local memoryBefore = collectgarbage("count")
    local started = timer()
    local source = {}
    local slots = { "HEAD", "SHOULDER", "CHEST", "MAINHAND", "OFFHAND" }
    for index = 1, count do
        source[index] = {
            id = index,
            itemId = 100000 + index,
            itemIds = { 100000 + index },
            slot = slots[((index - 1) % #slots) + 1],
            armorType = "ALL",
            weaponType = "ALL",
            name = "synthetic appearance " .. index,
            source = "performance baseline",
            collected = index % 3 == 0,
            favorite = false,
        }
    end
    local loadedAt = timer()
    local filters = resolvedFilters({
        collected = true,
        uncollected = true,
        favorites = false,
        classToken = "ALL",
        armorType = "ALL",
        slot = "ALL",
        weaponType = "ALL",
    })
    local matches = {}
    for _, sourceRecord in ipairs(source) do
        local record = copyRecord(sourceRecord)
        if filterMatches("APPEARANCES", record, "synthetic appearance", filters, true) then
            matches[#matches + 1] = record
        end
    end
    local filteredAt = timer()
    local firstPage = {}
    local lastPage = {}
    local pageSize = 18
    for index = 1, math.min(pageSize, #matches) do
        firstPage[#firstPage + 1] = matches[index]
    end
    local firstLastIndex = math.max(1, #matches - pageSize + 1)
    for index = firstLastIndex, #matches do
        lastPage[#lastPage + 1] = matches[index]
    end
    local pagedAt = timer()
    local memoryPeak = collectgarbage("count")
    source = nil
    matches = nil
    firstPage = nil
    lastPage = nil
    collectgarbage("collect")
    return {
        count = count,
        loadMs = loadedAt - started,
        filterMs = filteredAt - loadedAt,
        pageMs = pagedAt - filteredAt,
        peakMemoryKb = math.max(0, memoryPeak - memoryBefore),
    }
end

function Catalog.GetProgress(category, filters)
    local collected = 0
    local total = 0
    local source = getSource(category) or {}
    local activeFilters = resolvedFilters(filters)
    for _, sourceRecord in ipairs(source) do
        local record = resolveRecordState(category, copyRecord(sourceRecord), sourceRecord.collected)
        if filterMatches(category, record, "", activeFilters, false) then
            total = total + 1
            if record.collected then
                collected = collected + 1
            end
        end
    end
    return collected, total
end

function Catalog.ToggleDemoFavorite(category, id)
    local source = getSource(category) or {}
    for _, sourceRecord in ipairs(source) do
        if sourceRecord.id == id then
            local record = resolveRecordState(category, copyRecord(sourceRecord), sourceRecord.collected)
            if isCollectibleCompanion(category) and not record.collected then
                ensureFavoriteStore(category)[id] = false
                return false
            end
            local value = not getFavorite(category, record)
            ensureFavoriteStore(category)[id] = value
            return value
        end
    end
    return nil
end

function Catalog.ResetFilters(category)
    local filters = resolvedFilters(nil)
    if type(SoloCollectionsDB) ~= "table" then
        SoloCollectionsDB = {}
    end
    SoloCollectionsDB.filters = filters
    if SC.db then
        SC.db.filters = filters
    end
    return resolvedFilters(filters)
end

function Catalog.GetCategoryKey(category)
    return CATEGORY_KEYS[category]
end
