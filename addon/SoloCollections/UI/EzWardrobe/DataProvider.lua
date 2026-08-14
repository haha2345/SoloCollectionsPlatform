local SC = SoloCollections

SC.EzWardrobe = SC.EzWardrobe or {}
SC.EzWardrobe.DataProvider = SC.EzWardrobe.DataProvider or {}

local DataProvider = SC.EzWardrobe.DataProvider
local Catalog = SC.Catalog
local Identity = SC.IdentityRegistry

local APPEARANCE_CATEGORY = "APPEARANCES"
local ARMOR_TYPES = {
    AUTO = true,
    PLATE = true,
    MAIL = true,
    LEATHER = true,
    CLOTH = true,
}
local EQUIPMENT_SLOT_BY_APPEARANCE_SLOT = {
    HEAD = 0,
    SHOULDER = 2,
    CHEST = 4,
    WAIST = 5,
    LEGS = 6,
    FEET = 7,
    WRIST = 8,
    HANDS = 9,
    BACK = 14,
    MAINHAND = 15,
    OFFHAND = 16,
}

DataProvider.ARMOR_OPTIONS = {
    { key = "PLATE", label = "板甲" },
    { key = "MAIL", label = "锁甲" },
    { key = "LEATHER", label = "皮甲" },
    { key = "CLOTH", label = "布甲" },
}

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do
                nested[nestedKey] = nestedValue
            end
            result[key] = nested
        else
            result[key] = value
        end
    end
    return result
end

local function currentFilters()
    return SC.db and SC.db.filters or nil
end

local function defaultArmorType()
    local value = Identity and Identity.GetDefaultArmorType and Identity.GetDefaultArmorType() or nil
    return ARMOR_TYPES[value] and value ~= "AUTO" and value or "PLATE"
end

local function finish(callback, ok, reason)
    if type(callback) == "function" then
        pcall(callback, ok, reason)
    end
    return ok, reason
end

function DataProvider:Create(page)
    return setmetatable({ page = page }, { __index = self })
end

function DataProvider:GetArmorState()
    local filters = currentFilters()
    local stored = filters and filters.armorType or "AUTO"
    if not ARMOR_TYPES[stored] then stored = "AUTO" end
    local effective = stored == "AUTO" and defaultArmorType() or stored
    return stored, effective
end

function DataProvider:GetQueryFilters()
    local filters = copyTable(currentFilters())
    local _, effectiveArmorType = self:GetArmorState()
    filters.armorType = effectiveArmorType
    return filters
end

function DataProvider:ToItemRecord(record)
    if type(record) ~= "table" then return nil end
    local item = copyTable(record)
    item.collectionId = tonumber(record.collectionId or record.id)
    item.id = item.collectionId
    item.itemId = tonumber(record.itemId)
    item.slot = record.slot
    item.weaponType = record.weaponType or record.weaponCategory
    item.name = record.name
    item.collected = record.collected and true or false
    item.favorite = record.favorite and true or false
    if item.slot == "MAINHAND" then
        item.ezModelType = "main"
    elseif item.slot == "OFFHAND" then
        item.ezModelType = "off"
    else
        item.ezModelType = "player"
    end
    return item
end

local function convertRecords(provider, records)
    local result = {}
    for index, record in ipairs(records or {}) do
        result[index] = provider:ToItemRecord(record)
    end
    return result
end

function DataProvider:QueryItems(pageNumber, pageSize)
    if not Catalog or type(Catalog.Query) ~= "function" then
        return {}, 1, 1, 0
    end
    local query = SC.db and SC.db.query or ""
    local records, page, totalPages, total = Catalog.Query(
        APPEARANCE_CATEGORY,
        query,
        self:GetQueryFilters(),
        pageNumber,
        pageSize
    )
    return convertRecords(self, records), page, totalPages, total
end

function DataProvider:QueryAllItems()
    if not Catalog or type(Catalog.QueryAll) ~= "function" then return {} end
    local query = SC.db and SC.db.query or ""
    return convertRecords(self, Catalog.QueryAll(APPEARANCE_CATEGORY, query, self:GetQueryFilters()))
end

function DataProvider:GetProgress()
    if not Catalog or type(Catalog.GetProgress) ~= "function" then return 0, 0 end
    return Catalog.GetProgress(APPEARANCE_CATEGORY, self:GetQueryFilters())
end

function DataProvider:SetFilter(key, value)
    local filters = currentFilters()
    if not filters or type(key) ~= "string" then return false end
    if key == "armorType" and not ARMOR_TYPES[value] then return false end
    filters[key] = value
    if self.page then
        self.page.scItemPage = 1
        self.page.scItemSelectedId = nil
        self.page.scSetSelectedId = nil
    end
    return true
end

function DataProvider:ToggleFavorite(collectionId)
    if not Catalog or type(Catalog.ToggleDemoFavorite) ~= "function" then return nil end
    return Catalog.ToggleDemoFavorite(APPEARANCE_CATEGORY, tonumber(collectionId))
end

function DataProvider:ApplyAppearance(record, callback)
    if type(record) ~= "table" then
        return finish(callback, false, "INVALID_APPEARANCE")
    end
    if not record.collected then
        return finish(callback, false, "NOT_OWNED")
    end
    local collectionId = tonumber(record.collectionId or record.id)
    local equipmentSlot = EQUIPMENT_SLOT_BY_APPEARANCE_SLOT[record.slot]
    if not collectionId or not equipmentSlot then
        return finish(callback, false, "INVALID_TARGET_SLOT")
    end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return finish(callback, false, "BRIDGE_UNAVAILABLE")
    end
    return SC.Bridge.ApplyAppearance(collectionId, equipmentSlot, callback)
end

function DataProvider:GetCollectionState()
    local state = SC.CollectionState
    return state and state.GetCategoryState and state.GetCategoryState(APPEARANCE_CATEGORY) or "Disabled"
end

function DataProvider:GetRevision()
    local state = SC.CollectionState
    return state and state.GetRevision and state.GetRevision() or "0"
end

function DataProvider:GetAppearanceTypeId()
    local state = SC.CollectionState
    return state and state.GetTypeId and state.GetTypeId(APPEARANCE_CATEGORY) or nil
end

function DataProvider:IsOwned(collectionId, fallback)
    local state = SC.CollectionState
    if not state or not state.ResolveOwned then return fallback and true or false, false end
    return state.ResolveOwned(APPEARANCE_CATEGORY, tonumber(collectionId), fallback)
end
