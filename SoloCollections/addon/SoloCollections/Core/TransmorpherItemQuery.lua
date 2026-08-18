local SC = SoloCollections

local ItemQuery = SC.TransmorpherItemQuery or {}
SC.TransmorpherItemQuery = ItemQuery

-- Namespaced projection of Transmorpher frames/QueryItem.lua.  The hidden
-- tooltip forces an uncached WotLK item query; callbacks run only after the
-- item link is available (or after the same bounded timeout).
local QUERY_TIME = 180
local PERIOD = 0.1

local tooltip = CreateFrame("GameTooltip", nil, UIParent)
local driver = CreateFrame("Frame", nil, UIParent)
driver.queries = {}
driver.elapsed = 0

local function onUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < PERIOD then return end

    local step = self.elapsed
    self.elapsed = 0
    local finished = {}
    for itemId, handlers in pairs(self.queries) do
        local _, itemLink = GetItemInfo(itemId)
        for index = #handlers, 1, -1 do
            local pending = handlers[index]
            pending.time = pending.time - step
            if itemLink or pending.time <= 0 then
                pending.handler(itemId, itemLink and true or false)
                table.remove(handlers, index)
            end
        end
        if #handlers == 0 then finished[#finished + 1] = itemId end
    end
    for _, itemId in ipairs(finished) do self.queries[itemId] = nil end
    if next(self.queries) == nil then self:SetScript("OnUpdate", nil) end
end

function ItemQuery:Query(itemId, handler)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or type(handler) ~= "function" then
        return false, "INVALID_ITEM_QUERY"
    end

    local _, itemLink = GetItemInfo(itemId)
    if itemLink then
        handler(itemId, true)
        return true, "READY"
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
