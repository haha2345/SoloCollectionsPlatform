local SC = SoloCollections

SC.WardrobeUI = SC.WardrobeUI or {}
local Filters = {}
SC.WardrobeUI.Filters = Filters

function Filters:Create(page, catalog, dataProvider)
    local controller = { page = page, catalog = catalog, dataProvider = dataProvider }
    function controller:Set(key, value)
        if self.dataProvider then
            return self.dataProvider:SetFilter(key, value)
        end
        if not (SC.db and SC.db.filters) then return false end
        SC.db.filters[key] = value
        self.page.scItemSelectedId = nil
        self.page.scSetSelectedId = nil
        self.page.scItemPage = 1
        return true
    end
    function controller:QueryItems(pageNumber, pageSize)
        if self.dataProvider then
            return self.dataProvider:QueryItems(pageNumber, pageSize)
        end
        return self.catalog.Query("APPEARANCES", SC.db.query, SC.db.filters, pageNumber, pageSize)
    end
    function controller:QuerySets()
        local filters = {}
        for key, value in pairs(SC.db.filters) do filters[key] = value end
        filters.slot = "ALL"
        return self.catalog.QueryAll("SETS", SC.db.query, filters), filters
    end
    return controller
end
