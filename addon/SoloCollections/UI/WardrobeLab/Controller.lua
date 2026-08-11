local SC = SoloCollections
local UI = SC.UI

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

function Lab.IsEnabled()
    return SC.db and SC.db.experimental and SC.db.experimental.transmogLabEnabled == true
end

function Lab.CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()

    page.scCapability = {
        localPreview = true,
        applySingleSlot = false,
        saveMultipleSlots = false,
        serverState = false,
    }

    if Lab.CreateLayout then Lab.CreateLayout(page) end

    function page:Refresh()
        if self.scStateText then
            self.scStateText:SetText("仅本地预览 · 尚未应用 · 不发送 SC2 请求")
        end
        if self.scCapabilityText then
            self.scCapabilityText:SetText(
                "当前阶段：三栏交互骨架已建立；槽位、来源目录、方案保存与单槽应用将在后续任务接入。"
            )
        end
    end

    page:SetScript("OnShow", function(self) self:Refresh() end)
    return page
end

