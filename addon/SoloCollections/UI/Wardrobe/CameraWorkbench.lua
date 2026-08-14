local SC = SoloCollections

SC.WardrobeUI = SC.WardrobeUI or {}
local Workbench = {}
SC.WardrobeUI.CameraWorkbench = Workbench

-- Camera data keeps its production identity and precedence in M2Camera:
-- (raceId, sex, slot), appearance > model > weaponFamily > autoCamera.
function Workbench:Attach(page)
    local instance = {
        page = page,
        identity = "raceId:sex:slot",
        precedence = { "appearance", "model", "weaponFamily", "autoCamera" },
        strategies = { "NEWERA_POSITION", "SOLOCAM_PROFILE" },
        strategy = "SOLOCAM_PROFILE",
    }
    function instance:SetStrategy(value)
        if value ~= "NEWERA_POSITION" and value ~= "SOLOCAM_PROFILE" then return false end
        self.strategy = value
        for _, model in ipairs(self.page.scItemModels or {}) do
            model.scCameraStrategy = value
            model.scRecordId = nil
        end
        return true
    end
    function instance:ToggleStrategy()
        local nextValue = self.strategy == "SOLOCAM_PROFILE" and "NEWERA_POSITION" or "SOLOCAM_PROFILE"
        self:SetStrategy(nextValue)
        return nextValue
    end
    page.scCameraWorkbench = instance
    return instance
end
