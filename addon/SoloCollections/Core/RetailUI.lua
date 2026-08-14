local SC = SoloCollections

local RetailUI = SC.RetailUI or {}
SC.RetailUI = RetailUI

RetailUI.SCHEMA_VERSION = 2
RetailUI.ASSET_GLOBAL = "SoloCollectionsRetailUIAssets"
RetailUI.EXPECTED_ROOT = "Interface\\AddOns\\SoloCollections_RetailUI"
RetailUI.EXPECTED_FILE_DATA_ID = 132658
RetailUI.EXPECTED_RAW_SHA256 = "2B4F665FCE0BC7FDE2086206AE22918DA5FC4EFB3BE1470307AF9E4D0EFCABB0"
RetailUI.EXPECTED_CONVERTED_SHA256 = "1125FB73500ED34826740046328AD4C495BB58FE738ECDDC5657DF4A3C5A2D4C"
RetailUI.EXPECTED_TGA_DESCRIPTOR = 8
RetailUI.NATIVE_WARDROBE_PORTRAIT = "Interface\\Icons\\inv_chest_cloth_17"

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

local function readWardrobePortrait()
    local marker = rawget(_G, RetailUI.ASSET_GLOBAL)
    if type(marker) ~= "table" or tonumber(marker.schemaVersion) ~= RetailUI.SCHEMA_VERSION then
        return nil, "asset-addon-missing"
    end
    if tostring(marker.root or "") ~= RetailUI.EXPECTED_ROOT then
        return nil, "asset-root-mismatch"
    end
    local portrait = marker.wardrobePortrait
    if type(portrait) ~= "table"
        or tonumber(portrait.fileDataId) ~= RetailUI.EXPECTED_FILE_DATA_ID
        or string.upper(tostring(portrait.rawSha256 or "")) ~= RetailUI.EXPECTED_RAW_SHA256
        or string.upper(tostring(portrait.convertedSha256 or "")) ~= RetailUI.EXPECTED_CONVERTED_SHA256
        or tonumber(portrait.width) ~= 64
        or tonumber(portrait.height) ~= 64
        or tonumber(portrait.pixelDepth) ~= 32
        or tonumber(portrait.decodedAlphaBits) ~= 8
        or tonumber(portrait.tgaDescriptor) ~= RetailUI.EXPECTED_TGA_DESCRIPTOR
        or tonumber(portrait.tgaAttributeBits) ~= 8
        or tostring(portrait.origin or "") ~= "bottom-left" then
        return nil, "asset-marker-mismatch"
    end
    local relative = normalizeRelativePath(portrait.relativePath)
    if not relative then return nil, "invalid-relative-path" end
    return marker.root .. "\\" .. relative
end

function RetailUI.GetWardrobePortraitPath()
    local path = readWardrobePortrait()
    return path or RetailUI.NATIVE_WARDROBE_PORTRAIT
end

function RetailUI.GetStatus()
    local path, reason = readWardrobePortrait()
    return {
        available = path ~= nil,
        reason = reason,
        path = path or RetailUI.NATIVE_WARDROBE_PORTRAIT,
        fileDataId = RetailUI.EXPECTED_FILE_DATA_ID,
        rawSha256 = RetailUI.EXPECTED_RAW_SHA256,
        convertedSha256 = RetailUI.EXPECTED_CONVERTED_SHA256,
    }
end
