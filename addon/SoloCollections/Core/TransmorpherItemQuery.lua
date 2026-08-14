local SC = SoloCollections

local ItemQuery = SC.TransmorpherItemQuery or {}
SC.TransmorpherItemQuery = ItemQuery

-- Namespaced projection of Transmorpher frames/QueryItem.lua.  Callers can
-- opt into the original hidden-tooltip query, but wardrobe previews use the
-- cached-only path to avoid repeated client "item not found" errors.
local QUERY_TIME = 180
local PERIOD = 0.1
local FAILURE_RETRY_TIME = 600

local tooltip = CreateFrame("GameTooltip", nil, UIParent)
local driver = CreateFrame("Frame", nil, UIParent)
driver.queries = {}
driver.failures = {}
driver.elapsed = 0

local function currentTime()
    return GetTime and GetTime() or 0
end

local function getCachedItemLink(itemId)
    local _, itemLink = GetItemInfo(itemId)
    return itemLink
end

local function clearFailure(itemId)
    driver.failures[itemId] = nil
end

local function markFailure(itemId, reason)
    driver.failures[itemId] = {
        reason = reason or "ITEM_QUERY_FAILED",
        retryAt = currentTime() + FAILURE_RETRY_TIME,
    }
end

local function activeFailure(itemId)
    local failure = driver.failures[itemId]
    if not failure then return nil end
    if failure.retryAt and failure.retryAt <= currentTime() then
        driver.failures[itemId] = nil
        return nil
    end
    return failure
end

local function onUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < PERIOD then return end

    local step = self.elapsed
    self.elapsed = 0
    local finished = {}
    for itemId, handlers in pairs(self.queries) do
        local itemLink = getCachedItemLink(itemId)
        if itemLink then clearFailure(itemId) end
        for index = #handlers, 1, -1 do
            local pending = handlers[index]
            pending.time = pending.time - step
            if itemLink or pending.time <= 0 then
                local success = itemLink and true or false
                if not success then markFailure(itemId, "ITEM_QUERY_TIMEOUT") end
                pending.handler(itemId, success, success and "READY" or "ITEM_QUERY_TIMEOUT")
                table.remove(handlers, index)
            end
        end
        if #handlers == 0 then finished[#finished + 1] = itemId end
    end
    for _, itemId in ipairs(finished) do self.queries[itemId] = nil end
    if next(self.queries) == nil then self:SetScript("OnUpdate", nil) end
end

function ItemQuery:ResolveLink(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil, "INVALID_ITEM_QUERY" end

    local itemLink = getCachedItemLink(itemId)
    if itemLink then
        clearFailure(itemId)
        return itemLink, "READY"
    end

    local failure = activeFailure(itemId)
    if failure then return nil, failure.reason or "ITEM_QUERY_FAILED" end
    return nil, "ITEM_NOT_CACHED"
end

function ItemQuery:IsUnavailable(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return true, "INVALID_ITEM_QUERY" end
    if getCachedItemLink(itemId) then
        clearFailure(itemId)
        return false, "READY"
    end
    local failure = activeFailure(itemId)
    if failure then return true, failure.reason or "ITEM_QUERY_FAILED" end
    return false, "ITEM_NOT_CACHED"
end

function ItemQuery:ClearFailure(itemId)
    itemId = tonumber(itemId)
    if itemId then clearFailure(itemId) end
end

function ItemQuery:Query(itemId, handler, options)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or type(handler) ~= "function" then
        return false, "INVALID_ITEM_QUERY"
    end

    local itemLink = getCachedItemLink(itemId)
    if itemLink then
        clearFailure(itemId)
        handler(itemId, true, "READY")
        return true, "READY"
    end

    local failure = activeFailure(itemId)
    if failure then
        handler(itemId, false, failure.reason or "ITEM_QUERY_FAILED")
        return true, failure.reason or "ITEM_QUERY_FAILED"
    end

    if type(options) == "table" and options.force == false then
        handler(itemId, false, "ITEM_NOT_CACHED")
        return true, "ITEM_NOT_CACHED"
    end

    local handlers = driver.queries[itemId]
    if not handlers then
        tooltip:SetHyperlink("item:" .. itemId .. ":0:0:0:0:0:0:0")
        handlers = {}
        driver.queries[itemId] = handlers
    end
    handlers[#handlers + 1] = { handler = handler, time = QUERY_TIME }
    if not driver:GetScript("OnUpdate") then
        driver:SetScript("OnUpdate", onUpdate)
    end
    return true, "QUERYING"
end
