local SC = SoloCollections

local EzUI = SC.EzCollectionsUI or {}
SC.EzCollectionsUI = EzUI

EzUI.API_VERSION = 1
EzUI.ASSET_GLOBAL = "SoloCollectionsEzUIAssets"
EzUI.EXPECTED_SOURCE_VERSION = "2.2"
EzUI.EXPECTED_SOURCE_TREE_HASH = "218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6"
EzUI.EXPECTED_ASSET_TREE_HASH = "4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53"
EzUI.EXPECTED_ROOT = "Interface\\AddOns\\SoloCollections_EzUI"

EzUI.MEDIA = {
    Collections = "Interface\\Collections",
    Transmogrify = "Interface\\Transmogrify",
    DressUpFrame = "Interface\\DressUpFrame",
    Common = "Interface\\Common",
    Buttons = "Interface\\Buttons",
    Textures = "Textures",
    Sounds = "Sounds",
}

local failureText = {
    ["asset-addon-missing"] = "未安装本地 ezCollections UI 素材包。",
    ["schema-mismatch"] = "ezCollections UI 素材适配版本不匹配。",
    ["source-version-mismatch"] = "ezCollections 素材来源版本不是已锁定的 2.2。",
    ["source-hash-mismatch"] = "ezCollections 来源目录校验失败。",
    ["asset-hash-mismatch"] = "ezCollections 素材目录校验失败。",
    ["asset-root-mismatch"] = "ezCollections 素材根目录不正确。",
    ["invalid-relative-path"] = "请求了不安全的素材路径。",
}

local function readAssetMarker()
    local marker = rawget(_G, EzUI.ASSET_GLOBAL)
    if type(marker) ~= "table" then
        return nil, "asset-addon-missing"
    end
    if tonumber(marker.schemaVersion) ~= EzUI.API_VERSION then
        return nil, "schema-mismatch"
    end
    if tostring(marker.sourceVersion or "") ~= EzUI.EXPECTED_SOURCE_VERSION then
        return nil, "source-version-mismatch"
    end
    if tostring(marker.sourceTreeHash or "") ~= EzUI.EXPECTED_SOURCE_TREE_HASH then
        return nil, "source-hash-mismatch"
    end
    if tostring(marker.assetTreeHash or "") ~= EzUI.EXPECTED_ASSET_TREE_HASH then
        return nil, "asset-hash-mismatch"
    end
    if tostring(marker.root or "") ~= EzUI.EXPECTED_ROOT then
        return nil, "asset-root-mismatch"
    end
    return marker
end

local function normalizeRelativePath(relative)
    if type(relative) ~= "string" or relative == "" then return nil end
    relative = string.gsub(relative, "/", "\\")
    while string.sub(relative, 1, 1) == "\\" do
        relative = string.sub(relative, 2)
    end
    if relative == "" or string.find(relative, ":", 1, true) then return nil end
    if relative == ".." or string.sub(relative, 1, 3) == "..\\"
        or string.sub(relative, -3) == "\\.."
        or string.find(relative, "\\..\\", 1, true) then
        return nil
    end
    return relative
end

function EzUI.IsAvailable()
    local marker, reason = readAssetMarker()
    return marker ~= nil, reason
end

function EzUI.GetStatus()
    local marker, reason = readAssetMarker()
    return {
        available = marker ~= nil,
        reason = reason,
        sourceVersion = marker and marker.sourceVersion or EzUI.EXPECTED_SOURCE_VERSION,
        sourceTreeHash = marker and marker.sourceTreeHash or EzUI.EXPECTED_SOURCE_TREE_HASH,
        assetTreeHash = marker and marker.assetTreeHash or EzUI.EXPECTED_ASSET_TREE_HASH,
        root = marker and marker.root or EzUI.EXPECTED_ROOT,
    }
end

function EzUI.DescribeFailure(reason)
    return failureText[reason] or ("ezCollections UI 素材不可用：" .. tostring(reason or "unknown"))
end

function EzUI.Require()
    local marker, reason = readAssetMarker()
    if marker then return marker end
    return nil, reason
end

function EzUI.Path(relative)
    local marker, reason = readAssetMarker()
    if not marker then return nil, reason end
    relative = normalizeRelativePath(relative)
    if not relative then return nil, "invalid-relative-path" end
    return marker.root .. "\\" .. relative
end

function EzUI.MediaPath(group, name)
    local prefix = EzUI.MEDIA[group]
    if not prefix or type(name) ~= "string" or name == "" then
        return nil, "invalid-relative-path"
    end
    return EzUI.Path(prefix .. "\\" .. name)
end

function EzUI.ShowUnavailableNotice(parent, context, reason)
    if not parent then return nil end
    local overlay = parent.scEzUIUnavailable
    if not overlay then
        overlay = CreateFrame("Frame", nil, parent)
        overlay:SetAllPoints(parent)
        overlay:EnableMouse(true)
        if parent.GetFrameLevel and overlay.SetFrameLevel then
            overlay:SetFrameLevel(parent:GetFrameLevel() + 50)
        end
        local background = overlay:CreateTexture(nil, "OVERLAY")
        background:SetAllPoints(overlay)
        background:SetTexture(0.035, 0.025, 0.02, 0.96)
        local title = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("CENTER", overlay, "CENTER", 0, 18)
        title:SetText("SoloCollections UI 素材不可用")
        local body = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOP", title, "BOTTOM", 0, -10)
        body:SetWidth(math.max(180, (parent.GetWidth and parent:GetWidth() or 360) - 60))
        body:SetJustifyH("CENTER")
        overlay.scBody = body
        parent.scEzUIUnavailable = overlay
    end
    local detail = EzUI.DescribeFailure(reason)
    if context and context ~= "" then detail = tostring(context) .. "\n" .. detail end
    overlay.scBody:SetText(detail .. "\n请使用 SoloClientSuite 本地素材导入器重新构建。")
    overlay:Show()
    return overlay
end

function EzUI.Guard(parent, context)
    local marker, reason = readAssetMarker()
    if marker then
        if parent and parent.scEzUIUnavailable then parent.scEzUIUnavailable:Hide() end
        return true
    end
    EzUI.ShowUnavailableNotice(parent, context, reason)
    return false, reason
end
