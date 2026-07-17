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

local CLASS_BITS = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER = 4,
    ROGUE = 8,
    PRIEST = 16,
    DEATHKNIGHT = 32,
    SHAMAN = 64,
    MAGE = 128,
    WARLOCK = 256,
    DRUID = 1024,
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

local function getSource(category)
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
    if record.classToken then
        return record.classToken == classToken
    end
    local classBit = CLASS_BITS[classToken]
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
        local record = copyRecord(sourceRecord)
        record.favorite = getFavorite(category, sourceRecord)
        result[index] = record
    end
    return result
end

function Catalog.QueryAll(category, query, filters)
    local matches = {}
    local source = getSource(category) or {}
    local activeFilters = resolvedFilters(filters)
    for _, sourceRecord in ipairs(source) do
        if filterMatches(category, sourceRecord, query, activeFilters, true) then
            local record = copyRecord(sourceRecord)
            record.favorite = getFavorite(category, sourceRecord)
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

function Catalog.GetProgress(category, filters)
    local collected = 0
    local total = 0
    local source = getSource(category) or {}
    local activeFilters = resolvedFilters(filters)
    for _, record in ipairs(source) do
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
    for _, record in ipairs(source) do
        if record.id == id then
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
