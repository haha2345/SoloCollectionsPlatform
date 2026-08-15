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
    mounts = {
        unusable = true,
        ground = true,
        flying = true,
        aquatic = true,
        hiddenSources = {},
    },
    pets = {
        hiddenSources = {},
    },
}

local WEAPON_SLOTS = { MAINHAND = true, OFFHAND = true }
local generatedMountSource = nil
local generatedCompanionSource = nil
local generatedToySource = nil
local generatedAppearanceSource = nil
local wardrobeLoadAttempted = false
local mountDescriptionCache = {}
local mountDescriptionGaps = {}
local mountDescriptionGapKeys = {}
local getGeneratedMountSource

local MOUNT_SOURCE_LABELS = {
    [0] = "掉落",
    [1] = "任务",
    [2] = "商人",
    [3] = "专业",
    [4] = "宠物对战",
    [5] = "成就",
    [6] = "世界事件",
    [7] = "促销",
    [8] = "集换式卡牌",
    [9] = "游戏商城",
    [10] = "发现",
    [11] = "其他",
}

Catalog.MOUNT_SOURCE_ORDER = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }

local function refreshMountSourceOrder(source)
    local seen = {}
    for _, record in ipairs(source or {}) do
        local sourceType = tonumber(record.sourceType)
        if sourceType ~= nil then
            seen[sourceType] = true
        end
    end
    local order = {}
    for sourceType in pairs(seen) do
        order[#order + 1] = sourceType
    end
    table.sort(order)
    if #order > 0 then
        Catalog.MOUNT_SOURCE_ORDER = order
    end
end

local function sourceOrder(source)
    local seen = {}
    for _, record in ipairs(source or {}) do
        local sourceType = tonumber(record.sourceType)
        if sourceType ~= nil then seen[sourceType] = true end
    end
    local order = {}
    for sourceType in pairs(seen) do order[#order + 1] = sourceType end
    table.sort(order)
    return order
end

function Catalog.GetMountSourceOrder()
    getGeneratedMountSource()
    return Catalog.MOUNT_SOURCE_ORDER
end

function Catalog.MountSourceLabel(sourceType)
    sourceType = tonumber(sourceType)
    return MOUNT_SOURCE_LABELS[sourceType] or "其他"
end

local function ensureWardrobeCatalog()
    if SC.GeneratedWardrobeCatalog then
        return true
    end
    if not wardrobeLoadAttempted and type(LoadAddOn) == "function" then
        wardrobeLoadAttempted = true
        LoadAddOn("SoloCollections_WardrobeData")
    end
    return SC.GeneratedWardrobeCatalog ~= nil
end

function getGeneratedMountSource()
    if generatedMountSource then
        return generatedMountSource
    end
    generatedMountSource = {}
    local generated = SC.GeneratedCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        local journalVisible = collection.journalVisible
        if journalVisible == nil then journalVisible = collection.uiCollectible ~= false end
        if collection.typeKey == "mount" and collection.lifecycle == "active" and journalVisible then
            local names = collection.name or {}
            table.insert(generatedMountSource, {
                id = collection.collectionId,
                previewCreatureEntry = collection.previewCreatureEntry or collection.displayCreatureId,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = collection.iconTexture,
                presentationStatus = collection.presentationStatus,
                spellId = collection.spellId,
                canonicalActionSpellId = collection.canonicalActionSpellId,
                actionable = collection.actionable and true or false,
                draggable = collection.draggable and true or false,
                randomEligible = collection.randomEligible and true or false,
                capability = collection.capability,
                exclusionReason = collection.exclusionReason,
                faction = collection.faction,
                mountType = collection.mountType,
                flags = collection.flags,
                sourceType = collection.sourceType,
                descriptionKey = collection.descriptionKey or collection.spellId,
                descriptionStatus = collection.descriptionStatus or "MISSING",
                acquisitionClass = collection.acquisitionClass or "STANDARD",
                visibilityReason = collection.visibilityReason,
                source = collection.sourceText and collection.sourceText ~= "" and
                    collection.sourceText or "来源未知",
                collected = false,
                favorite = false,
            })
        end
    end
    refreshMountSourceOrder(generatedMountSource)
    return generatedMountSource
end

local function getGeneratedCompanionSource()
    if generatedCompanionSource then
        return generatedCompanionSource
    end
    generatedCompanionSource = {}
    local generated = SC.GeneratedCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        local journalVisible = collection.journalVisible
        if journalVisible == nil then journalVisible = collection.uiCollectible ~= false end
        if collection.typeKey == "companion" and collection.lifecycle == "active" and journalVisible then
            local names = collection.name or {}
            table.insert(generatedCompanionSource, {
                id = collection.collectionId,
                spellId = collection.spellId,
                canonicalActionSpellId = collection.canonicalActionSpellId,
                previewCreatureEntry = collection.previewCreatureEntry or collection.displayCreatureId,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = collection.iconTexture,
                presentationStatus = collection.presentationStatus,
                sourceType = collection.sourceType,
                source = collection.sourceText and collection.sourceText ~= "" and
                    collection.sourceText or "来源未知",
                description = collection.descriptionZhCN or "",
                journalVisible = true,
                actionable = collection.actionable and true or false,
                randomEligible = collection.randomEligible and true or false,
                collected = false,
                favorite = false,
            })
        end
    end
    return generatedCompanionSource
end

function Catalog.GetPetSourceOrder()
    return sourceOrder(getGeneratedCompanionSource())
end

function Catalog.PetSourceLabel(sourceType)
    sourceType = tonumber(sourceType)
    return MOUNT_SOURCE_LABELS[sourceType] or "其他"
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
    ensureWardrobeCatalog()
    local generated = SC.GeneratedWardrobeCatalog or {}
    for _, collection in ipairs(generated.collections or {}) do
        if collection.typeKey == "appearance" and collection.lifecycle == "active" and
            collection.uiLifecycle == "public" then
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
            local acquisitionSources = SC.GeneratedWardrobeAcquisitionSources and
                SC.GeneratedWardrobeAcquisitionSources.itemSources or nil
            local acquisitionSource
            if acquisitionSources then
                for _, sourceItemId in ipairs(itemIds) do
                    local sourceRecord = acquisitionSources[tonumber(sourceItemId)]
                    if sourceRecord and sourceRecord.text and sourceRecord.text ~= "" then
                        acquisitionSource = sourceRecord.text
                        break
                    end
                end
            end
            table.insert(generatedAppearanceSource, {
                id = collection.collectionId,
                itemId = tonumber(collection.displayItemId) or itemIds[1],
                iconItemId = tonumber(collection.displayItemId) or itemIds[1],
                itemIds = itemIds,
                slot = slot,
                armorType = armorType,
                weaponType = collection.weaponType or weaponType,
                weaponCategory = collection.weaponCategory,
                renderMode = collection.renderMode,
                nativeDisplayId = collection.nativeDisplayId,
                syntheticDisplayId = collection.syntheticDisplayId,
                modelPath = collection.modelPath,
                modelScale = collection.modelScale,
                cameraTuningKey = collection.cameraTuningKey,
                m2Camera = collection.m2Camera,
                modelSignature = collection.modelSignature,
                -- Keep reviewed, generated model-scoped camera defaults in the
                -- runtime projection.  Wardrobe resolves this below explicit
                -- player appearance/model tuning and above weapon-family
                -- fallbacks; dropping it here silently turns it into auto.
                generatedModelCameraOverride = collection.generatedModelCameraOverride,
                autoCamera = collection.autoCamera,
                presentationStatus = collection.presentationStatus,
                presentationReasonCode = collection.presentationReasonCode,
                presentationCapability = collection.presentationCapability,
                assetPackVersion = collection.assetPackVersion,
                retiredSyntheticDisplayId = collection.retiredSyntheticDisplayId,
                registryTombstoneReason = collection.registryTombstoneReason,
                name = names.zhCN ~= "" and names.zhCN or names.enUS or collection.collectionKey,
                icon = nil,
                source = acquisitionSource or "获取方式未记录",
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
    if category == "APPEARANCES" and ensureWardrobeCatalog() then
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
    -- Companion favorites are server projections (mount 16, pet 17). Never let the
    -- legacy SavedVariables table affect production ordering, even while the
    -- preference snapshot is still loading.
    if category == "MOUNTS" or category == "PETS" then
        local collectionState = SC.CollectionState
        local projectionType = category == "MOUNTS" and 16 or 17
        return collectionState and collectionState.IsOwnedByType
            and collectionState.IsOwnedByType(projectionType, record.id) or false
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
            if type(defaultValue) == "table" then
                result[key] = {}
                for nestedKey, nestedDefault in pairs(defaultValue) do
                    if type(nestedDefault) == "table" then
                        result[key][nestedKey] = {}
                        local savedNested = type(filters[key]) == "table" and filters[key][nestedKey]
                        if type(savedNested) == "table" then
                            for savedKey, savedValue in pairs(savedNested) do
                                result[key][nestedKey][savedKey] = savedValue
                            end
                        end
                    elseif type(filters[key]) == "table" and filters[key][nestedKey] ~= nil then
                        result[key][nestedKey] = filters[key][nestedKey]
                    else
                        result[key][nestedKey] = nestedDefault
                    end
                end
            else
                result[key] = filters[key]
            end
        else
            if type(defaultValue) == "table" then
                result[key] = {}
                for nestedKey, nestedDefault in pairs(defaultValue) do
                    if type(nestedDefault) == "table" then
                        result[key][nestedKey] = {}
                    else
                        result[key][nestedKey] = nestedDefault
                    end
                end
            else
                result[key] = defaultValue
            end
        end
    end
    return result
end

local function effectiveSetClassPolicy(record)
    local presentation = record and record.presentation
    if presentation and presentation.classPolicyOverride then
        return presentation.classPolicyOverride
    end
    return record and record.classPolicy
end

local function canonicalClassKey(value)
    if SC.IdentityRegistry and SC.IdentityRegistry.GetClassByKey then
        local identity = SC.IdentityRegistry.GetClassByKey(value)
        if identity and identity.known and identity.classKey then
            return identity.classKey
        end
    end
    return string.lower(tostring(value or ""))
end

local function classMatches(record, classToken)
    if not classToken or classToken == "ALL" then
        return true
    end
    local policy = effectiveSetClassPolicy(record)
    if policy then
        if policy.mode == "ANY" then
            return true
        end
        if policy.mode ~= "ALLOW_LIST" then
            return false
        end
        local wanted = canonicalClassKey(classToken)
        for _, allowed in ipairs(policy.allowedClassKeys or {}) do
            if canonicalClassKey(allowed) == wanted then return true end
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

local function hasMountBit(value, mask)
    value = tonumber(value) or 0
    if bit and bit.band then
        return bit.band(value, mask) ~= 0
    end
    return math.floor(value / mask) % 2 == 1
end

local function mountCategories(record)
    local categories = {}
    local mountType = tonumber(record.mountType) or 0
    local flags = tonumber(record.flags) or 0
    -- Keep ezCollections' original journal filter semantics. The 0x4 group is
    -- intentionally an OR category: either ground or flying must remain
    -- enabled for the row to stay visible. Do not infer movement from flags;
    -- 0x10 is only the aquatic display category.
    if hasMountBit(mountType, 0x4) then
        categories.kind = "GROUND_FLYING"
        categories.ground = true
        categories.flying = true
    elseif hasMountBit(flags, 0x10) then
        categories.kind = "AQUATIC"
        categories.aquatic = true
    elseif hasMountBit(mountType, 0x1) then
        categories.kind = "FLYING"
        categories.flying = true
    else
        categories.kind = "GROUND"
        categories.ground = true
    end
    return categories
end

local function mountIsUsable(record)
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
        return false
    end
    if record.faction and type(UnitFactionGroup) == "function" then
        local faction = UnitFactionGroup("player")
        local expectedFaction = string.upper(tostring(record.faction))
        local playerFaction = faction and string.upper(tostring(faction))
        if playerFaction and expectedFaction ~= "ALL" and expectedFaction ~= playerFaction then
            return false
        end
    end

    -- Match ezCollections' pure client-side usability checks. The 0x1 bit
    -- means flying-only; 0x2 means the mount can be used underwater. The 0x4
    -- scripted ground/flying group is deliberately not blocked by
    -- IsFlyableArea().
    local mountType = tonumber(record.mountType) or 0
    if type(IsOutdoors) == "function" and not IsOutdoors() then
        return false
    end
    if hasMountBit(mountType, 0x1) and type(IsFlyableArea) == "function" then
        if IsFlyableArea() == false then return false end
    end
    if not hasMountBit(mountType, 0x2) and type(IsSwimming) == "function" then
        if IsSwimming() then return false end
    end

    local spellId = tonumber(record.spellId or record.descriptionKey)
    local isAhnQirajMount = spellId == 25953 or spellId == 26054
        or spellId == 26055 or spellId == 26056
    if isAhnQirajMount and type(GetMinimapZoneText) == "function" then
        local zone = tostring(GetMinimapZoneText() or "")
        local isAhnQiraj = zone == "Ahn'Qiraj" or zone == "Ahn Qiraj"
            or zone == "Ан'Кираж" or zone == "安其拉"
            or zone == "安其拉神殿" or zone == "安其拉废墟"
        if isAhnQiraj ~= true then
            return false
        end
    elseif not isAhnQirajMount and type(GetMinimapZoneText) == "function" then
        local zone = tostring(GetMinimapZoneText() or "")
        if zone == "Ahn'Qiraj" or zone == "Ahn Qiraj"
            or zone == "Ан'Кираж" or zone == "安其拉"
            or zone == "安其拉神殿" or zone == "安其拉废墟" then
            return false
        end
    end
    return true
end

local function enrichMountRecord(record)
    if not record.mountCategories then
        record.mountCategories = mountCategories(record)
    end
    record.mountUsable = mountIsUsable(record)
    return record
end

local function mountFilterMatches(record, filters)
    local mountFilters = filters.mounts or DEFAULT_FILTERS.mounts
    local categories = record.mountCategories or mountCategories(record)
    if mountFilters.unusable == false and not record.mountUsable then
        return false
    end
    if categories.kind == "GROUND_FLYING" then
        if mountFilters.ground == false and mountFilters.flying == false then
            return false
        end
    elseif categories.kind == "AQUATIC" then
        if mountFilters.aquatic == false then return false end
    elseif categories.kind == "FLYING" then
        if mountFilters.flying == false then return false end
    elseif mountFilters.ground == false then
        return false
    end
    local hiddenSources = mountFilters.hiddenSources
    local sourceType = tonumber(record.sourceType)
    if type(hiddenSources) == "table" and sourceType ~= nil and hiddenSources[sourceType] then
        return false
    end
    return true
end

local function petFilterMatches(record, filters)
    local petFilters = filters.pets or DEFAULT_FILTERS.pets
    local hiddenSources = petFilters.hiddenSources
    local sourceType = tonumber(record.sourceType)
    return not (type(hiddenSources) == "table" and sourceType ~= nil and hiddenSources[sourceType])
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
        record.acquisitionClass == "LEGACY" and "绝版" or "",
        record.acquisitionClass == "PROMOTION" and "促销" or "",
    }, " ")
    return string.find(string.lower(haystack), query, 1, true) ~= nil
end

local function normalizeMountDescription(text, record)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or string.match(text, "^%d+$") or
        string.find(text, "法术ID", 1, true) or string.find(string.lower(text), "spell id", 1, true) then
        return nil
    end
    local male = type(UnitSex) ~= "function" or UnitSex("player") ~= 3
    text = string.gsub(text, "%$g([^:;]*):([^;]*);", function(maleText, femaleText)
        return male and maleText or femaleText
    end)
    if record and record.name and text == record.name then return nil end
    return text
end

function Catalog.ResolveMountDescription(record)
    local spellId = tonumber(record and (record.descriptionKey or record.spellId))
    if spellId then
        if mountDescriptionCache[spellId] then
            return mountDescriptionCache[spellId]
        end
        local ezui = _G.SoloCollections_EzUI
        local fallback = ezui and ezui.MountDescriptionsZhCN
        local localText = normalizeMountDescription(fallback and fallback[spellId], record)
        if localText then
            mountDescriptionCache[spellId] = localText
            return localText
        end
    end
    return nil
end

function Catalog.RecordMountDescriptionGap(record)
    local key = record and (record.descriptionKey or record.spellId or record.id)
    if key == nil then return end
    key = tostring(key)
    if mountDescriptionGapKeys[key] then return end
    mountDescriptionGapKeys[key] = true
    mountDescriptionGaps[#mountDescriptionGaps + 1] = {
        spellId = tonumber(record.spellId or record.descriptionKey),
        name = record.name,
        descriptionStatus = "MISSING",
    }
end

function Catalog.GetMountDescriptionGaps()
    local result = {}
    for index, gap in ipairs(mountDescriptionGaps) do
        result[index] = gap
    end
    return result
end

local function filterMatches(category, record, query, filters, includeCollectionState)
    if category == "MOUNTS" then
        enrichMountRecord(record)
        if not mountFilterMatches(record, filters) then
            return false
        end
    elseif category == "PETS" and not petFilterMatches(record, filters) then
        return false
    end
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

-- Set identity and APPLY semantics deliberately remain in the generated
-- ItemSet mapping.  These ranks are a presentation-only projection produced
-- by tools/catalog/set_presentations.py, so localized names never influence
-- the default wardrobe order.
local SET_PRESENTATION_SORT_KEYS = {
    "expansion", "acquisition", "tier", "season", "difficulty", "medianItemLevel", "maxItemLevel",
}

local function setPresentationRank(record, key)
    local presentation = record and record.presentation
    local ranks = presentation and presentation.sortRank
    return tonumber(ranks and ranks[key]) or 0
end

local function setPresentationLess(left, right)
    for _, key in ipairs(SET_PRESENTATION_SORT_KEYS) do
        local leftRank = setPresentationRank(left, key)
        local rightRank = setPresentationRank(right, key)
        if leftRank ~= rightRank then
            return leftRank > rightRank
        end
    end
    local leftItemSetId = tonumber(left and left.itemSetId) or 0
    local rightItemSetId = tonumber(right and right.itemSetId) or 0
    if leftItemSetId ~= rightItemSetId then
        return leftItemSetId < rightItemSetId
    end
    return (tonumber(left and left.id) or 0) < (tonumber(right and right.id) or 0)
end

local function collectionPresentationLess(left, right)
    local leftRank = left.collected and (left.favorite and 0 or 1) or 2
    local rightRank = right.collected and (right.favorite and 0 or 1) or 2
    if leftRank ~= rightRank then
        return leftRank < rightRank
    end
    local leftName = tostring(left.name or "")
    local rightName = tostring(right.name or "")
    if leftName ~= rightName then
        if type(strcmputf8i) == "function" then
            return strcmputf8i(leftName, rightName) < 0
        end
        return leftName < rightName
    end
    return (tonumber(left.id) or 0) < (tonumber(right.id) or 0)
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
    if category == "MOUNTS" or category == "PETS" then
        table.sort(matches, collectionPresentationLess)
    elseif category == "SETS" then
        table.sort(matches, setPresentationLess)
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

function Catalog.RunExpandedCollectionBenchmark(appearanceCount, companionCount, setCount)
    appearanceCount = math.max(1, math.min(50000, math.floor(tonumber(appearanceCount) or 18190)))
    companionCount = math.max(1, math.min(1000, math.floor(tonumber(companionCount) or 201)))
    setCount = math.max(1, math.min(2000, math.floor(tonumber(setCount) or 509)))
    local clock = type(debugprofilestop) == "function" and debugprofilestop or function() return GetTime() * 1000 end
    local memoryBefore = collectgarbage("count")
    local started = clock()
    local appearances, companions, sets = {}, {}, {}
    local appearanceIndex, setMemberIndex = {}, {}
    for index = 1, appearanceCount do
        local row = { id = 200000 + index, name = "appearance " .. index, slot = index % 2 == 0 and "HEAD" or "CHEST" }
        appearances[index], appearanceIndex[row.id] = row, row
    end
    for index = 1, companionCount do
        companions[index] = { id = 110000 + index, name = "companion " .. index }
    end
    for index = 1, setCount do
        local first = 200000 + ((index * 7) % appearanceCount) + 1
        local row = { id = 300000 + index, name = "set " .. index, members = { first, first + 1, first + 2 } }
        sets[index] = row
        for _, appearanceId in ipairs(row.members) do
            setMemberIndex[appearanceId] = setMemberIndex[appearanceId] or {}
            table.insert(setMemberIndex[appearanceId], row.id)
        end
    end
    local loadedAt = clock()
    local matched = {}
    for _, row in ipairs(appearances) do
        if row.slot == "HEAD" and string.find(row.name, "appearance", 1, true) then matched[#matched + 1] = row end
    end
    for index = 1, #sets do
        local row = sets[index]
        for _, appearanceId in ipairs(row.members) do
            if not appearanceIndex[appearanceId] then error("synthetic set index drift") end
        end
    end
    local filteredAt = clock()
    local pageSize, pages = 18, 0
    for offset = 1, #matched, pageSize do
        pages = pages + 1
        local _ = matched[math.min(#matched, offset + pageSize - 1)]
    end
    local pagedAt = clock()
    local peak = collectgarbage("count")
    appearances, companions, sets, appearanceIndex, setMemberIndex, matched = nil, nil, nil, nil, nil, nil
    collectgarbage("collect")
    return {
        appearances = appearanceCount, companions = companionCount, sets = setCount,
        loadMs = loadedAt - started, filterMs = filteredAt - loadedAt,
        pageMs = pagedAt - filteredAt, pages = pages, peakMemoryKb = math.max(0, peak - memoryBefore),
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
    if category == "MOUNTS" or category == "PETS" then
        local bridge = SC.Bridge
        if not bridge or bridge.sc2Connected or bridge.demoMode ~= true then
            return nil
        end
    end
    if category == "MOUNTS" then
        return nil
    end
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
