local SC = SoloCollections

-- Imported from ezCollections Data/Camera.lua (Classic section only).
-- Upstream SHA-256: 364310ecb57da13a410f98638499d0db31267170fcd7a230f23b1b8430333fe3
-- The numeric tuples and the original lookup encoding are preserved. SoloCollections
-- owns only the adapter below; SC2 remains authoritative for collection state/actions.
SC.EzCollectionsCamera = SC.EzCollectionsCamera or {}
local ezCollections = SC.EzCollectionsCamera
local PI = math.pi

-- ezCollections' camera table references the Retail-style subclass constants.
-- These are the exact 3.3.5 weapon subclass IDs used by its compatibility layer.
local LE_ITEM_WEAPON_SWORD1H = 7
local LE_ITEM_WEAPON_FIST = 10
local LE_ITEM_WEAPON_DAGGER = 12
local LE_ITEM_WEAPON_CROSSBOW = 14
local LE_ITEM_WEAPON_WAND = 15
local LE_ITEM_WEAPON_FISHINGPOLE = 16

ezCollections.Config = ezCollections.Config or { Wardrobe = { CameraOption = "Classic" } }
ezCollections.Cache = ezCollections.Cache or { Cameras = {} }
ezCollections.Source = {
    project = "ezCollections",
    file = "Data/Camera.lua",
    sha256 = "364310ecb57da13a410f98638499d0db31267170fcd7a230f23b1b8430333fe3",
    cameraOption = "Classic",
}

-- +OORRGIISS
-- -OORRGCCCC
ezCollections.CameraOptions =
{
    "Classic",
};
ezCollections.CameraOptionsToCameraID = { };
for id, name in ipairs(ezCollections.CameraOptions) do
    ezCollections.CameraOptionsToCameraID[name] = id * 10000000;
end
ezCollections.RaceToCameraID =
{
    Human                  =  1 *   100000,
    Orc                    =  2 *   100000,
    Dwarf                  =  3 *   100000,
    NightElf               =  4 *   100000,
    Scourge                =  5 *   100000,
    Tauren                 =  6 *   100000,
    Gnome                  =  7 *   100000,
    Troll                  =  8 *   100000,
    Goblin                 =  9 *   100000,
    BloodElf               = 10 *   100000,
    Draenei                = 11 *   100000,
};
ezCollections.SexToCameraID =
{
    [1]                    =  1 *    10000,
    [2]                    =  1 *    10000,
    [3]                    =  2 *    10000,
};
ezCollections.InvTypeToCameraID =
{
    INVTYPE_NON_EQUIP      =  0 *      100,
    INVTYPE_HEAD           =  1 *      100,
    INVTYPE_NECK           =  2 *      100,
    INVTYPE_SHOULDER       =  3 *      100,
    INVTYPE_BODY           =  4 *      100,
    INVTYPE_CHEST          =  5 *      100,
    INVTYPE_WAIST          =  6 *      100,
    INVTYPE_LEGS           =  7 *      100,
    INVTYPE_FEET           =  8 *      100,
    INVTYPE_WRIST          =  9 *      100,
    INVTYPE_HAND           = 10 *      100,
    INVTYPE_FINGER         = 11 *      100,
    INVTYPE_TRINKET        = 12 *      100,
    INVTYPE_WEAPON         = 13 *      100,
    INVTYPE_SHIELD         = 14 *      100,
    INVTYPE_RANGED         = 15 *      100,
    INVTYPE_CLOAK          = 16 *      100,
    INVTYPE_2HWEAPON       = 17 *      100,
    INVTYPE_BAG            = 18 *      100,
    INVTYPE_TABARD         = 19 *      100,
    INVTYPE_ROBE           = 20 *      100,
    INVTYPE_WEAPONMAINHAND = 21 *      100,
    INVTYPE_WEAPONOFFHAND  = 22 *      100,
    INVTYPE_HOLDABLE       = 23 *      100,
    INVTYPE_AMMO           = 24 *      100,
    INVTYPE_THROWN         = 25 *      100,
    INVTYPE_RANGEDRIGHT    = 26 *      100,
    INVTYPE_QUIVER         = 27 *      100,
    INVTYPE_RELIC          = 28 *      100,

    SetsDetails            = 50 *      100,
    SetsVendor             = 51 *      100,
};
ezCollections.SubClassToCameraID =       1;

local RACE_TOKEN_ALIASES = {
    human = "Human", orc = "Orc", dwarf = "Dwarf", nightelf = "NightElf",
    scourge = "Scourge", undead = "Scourge", tauren = "Tauren", gnome = "Gnome",
    troll = "Troll", goblin = "Goblin", bloodelf = "BloodElf", draenei = "Draenei",
    ["人类"] = "Human", ["兽人"] = "Orc", ["矮人"] = "Dwarf",
    ["暗夜精灵"] = "NightElf", ["亡灵"] = "Scourge", ["被遗忘者"] = "Scourge",
    ["牛头人"] = "Tauren", ["侏儒"] = "Gnome", ["巨魔"] = "Troll",
    ["地精"] = "Goblin", ["血精灵"] = "BloodElf", ["德莱尼"] = "Draenei",
}

local function normalizeRaceToken(localizedRace, raceToken)
    if raceToken and ezCollections.RaceToCameraID[raceToken] then return raceToken end
    if localizedRace and ezCollections.RaceToCameraID[localizedRace] then return localizedRace end
    local function resolve(value)
        if type(value) == "string" and value ~= "" then
            local compact = string.lower((string.gsub(value, "[%s%-']", "")))
            local normalized = RACE_TOKEN_ALIASES[compact] or RACE_TOKEN_ALIASES[value]
            if normalized then return normalized end
        end
        return nil
    end
    return resolve(raceToken) or resolve(localizedRace)
end

function ezCollections:GetCharacterCameraID(invTypeName, cameraID)
    local fallback = self.CameraOptionsToCameraID[ezCollections.CameraOptions[1]];
    local option = self.CameraOptionsToCameraID[ezCollections.Config.Wardrobe.CameraOption];
    if not option or not fallback then return nil, "CAMERA_OPTION_UNAVAILABLE" end
    local localizedRace, raceToken = UnitRace("player");
    raceToken = normalizeRaceToken(localizedRace, raceToken);
    local race = raceToken and self.RaceToCameraID[raceToken] or nil;
    if not race then return nil, "RACE_UNAVAILABLE" end
    local sex = self.SexToCameraID[UnitSex("player")];
    if not sex then return nil, "SEX_UNAVAILABLE" end
    if cameraID then
        local fullCameraID = option + race + sex + cameraID;
        local fallbackCameraID = fallback + race + sex + cameraID;
        if ezCollections.Cache.Cameras[fullCameraID] then
            return -fullCameraID;
        elseif ezCollections.Cache.Cameras[fallbackCameraID] then
            return -fallbackCameraID;
        end
    end

    local invType = self.InvTypeToCameraID[invTypeName];
    if not invType then return nil, "INVENTORY_TYPE_UNAVAILABLE" end
    local fullCameraID = option + race + sex + invType;
    local fallbackCameraID = fallback + race + sex + invType;
    if self.Cameras[fullCameraID] then
        return fullCameraID;
    else
        return fallbackCameraID;
    end
end

function ezCollections:GetWeaponCameraID(invTypeName, subType, cameraID)
    if cameraID then
        if ezCollections.Cache.Cameras[cameraID] then
            return -cameraID;
        end
    end

    local invType = self.InvTypeToCameraID[invTypeName];
    if not invType then return nil, "INVENTORY_TYPE_UNAVAILABLE" end
    local subType = self.SubClassToCameraID * ((subType or 0) + 1);
    if self.Cameras[invType + subType] then
        return invType + subType;
    else
        return invType;
    end
end

local cameraOptionAffectedInvTypes;
function ezCollections:PlayerHasDifferentCameraOptions()
    local race = self.RaceToCameraID[select(2, UnitRace("player"))];
    local sex = self.SexToCameraID[UnitSex("player")];
    local fallbackOption;
    for _, name in ipairs(ezCollections.CameraOptions) do
        local option = self.CameraOptionsToCameraID[name];
        if not fallbackOption then
            fallbackOption = option;
        else
            for _, invType in ipairs(cameraOptionAffectedInvTypes) do
                local fallback = ezCollections.Cameras[fallbackOption + race + sex + invType];
                local camera = ezCollections.Cameras[option + race + sex + invType];
                if fallback and camera then
                    local fx, fy, fz, ff, fa = unpack(fallback);
                    local ox, oy, oz, of, oa = unpack(camera);
                    if fx ~= ox or fy ~= oy or fz ~= oz or ff ~= of or fa ~= oa then
                        return true, option, fallbackOption, invType;
                    end
                end
            end
        end
    end
end

-- Populate ezCollections.Cameras
local O = ezCollections.CameraOptionsToCameraID;
local R = ezCollections.RaceToCameraID;
local I = ezCollections.InvTypeToCameraID;
local S = { Male = ezCollections.SexToCameraID[2], Female = ezCollections.SexToCameraID[3] }
local BACK = PI;
local MHAND = PI / 2;
local OHAND = 0;
local function Wpn(invType, subType)
    return invType + (subType and (subType + 1) or 0) * ezCollections.SubClassToCameraID;
end
local function Chr(option, race, sex, invType)
    return option + race + sex + invType;
end

cameraOptionAffectedInvTypes =
{
    I.INVTYPE_HEAD,
    I.INVTYPE_SHOULDER,
    I.INVTYPE_CLOAK,
    I.INVTYPE_CHEST,
    I.INVTYPE_ROBE,
    I.INVTYPE_BODY,
    I.INVTYPE_TABARD,
    I.INVTYPE_WRIST,
    I.INVTYPE_HAND,
    I.INVTYPE_WAIST,
    I.INVTYPE_LEGS,
    I.INVTYPE_FEET,
    I.SetsDetails,
    I.SetsVendor,
};

-- 2.5, -0.6, -0.9, 2.85, 124
ezCollections.Cameras =
{
    [Wpn(I.INVTYPE_WEAPON                                       )] = {  2.00, -0.52, -1.00, MHAND },
    [Wpn(I.INVTYPE_WEAPON,         LE_ITEM_WEAPON_SWORD1H       )] = {  2.00, -0.52, -1.10, MHAND },
    [Wpn(I.INVTYPE_WEAPON,         LE_ITEM_WEAPON_FIST          )] = {  2.25, -0.52, -0.75, MHAND },
    [Wpn(I.INVTYPE_WEAPONMAINHAND                               )] = {  2.00, -0.52, -1.00, MHAND },
    [Wpn(I.INVTYPE_WEAPONMAINHAND, LE_ITEM_WEAPON_SWORD1H       )] = {  2.00, -0.52, -1.10, MHAND },
    [Wpn(I.INVTYPE_WEAPONMAINHAND, LE_ITEM_WEAPON_FIST          )] = {  2.25, -0.52, -0.75, MHAND },
    [Wpn(I.INVTYPE_RANGEDRIGHT                                  )] = {  2.00, -0.52, -1.00, MHAND },
    [Wpn(I.INVTYPE_RANGEDRIGHT,    LE_ITEM_WEAPON_CROSSBOW      )] = {  2.00,  0.05, -1.00,  BACK },
    [Wpn(I.INVTYPE_RANGEDRIGHT,    LE_ITEM_WEAPON_WAND          )] = {  2.50, -0.52, -0.90, MHAND },
    [Wpn(I.INVTYPE_THROWN                                       )] = {  2.75, -0.52, -0.85, MHAND },
    [Wpn(I.INVTYPE_2HWEAPON                                     )] = {  1.50, -0.52, -1.00, MHAND },
    [Wpn(I.INVTYPE_2HWEAPON,       LE_ITEM_WEAPON_FISHINGPOLE   )] = {  1.00, -0.52, -1.25, MHAND },
    [Wpn(I.INVTYPE_WEAPONOFFHAND                                )] = {  1.35,  0.00, -0.75, OHAND },
    [Wpn(I.INVTYPE_WEAPONOFFHAND,  LE_ITEM_WEAPON_DAGGER        )] = {  1.40,  0.00, -0.70, OHAND },
    [Wpn(I.INVTYPE_WEAPONOFFHAND,  LE_ITEM_WEAPON_SWORD1H       )] = {  1.35,  0.00, -0.83, OHAND },
    [Wpn(I.INVTYPE_WEAPONOFFHAND,  LE_ITEM_WEAPON_FIST          )] = {  1.70,  0.00, -0.45, OHAND },
    [Wpn(I.INVTYPE_SHIELD                                       )] = {  2.00,  0.10, -0.30, -0.50, 110 },
    [Wpn(I.INVTYPE_HOLDABLE                                     )] = {  1.75,  0.00, -0.60, OHAND },
    [Wpn(I.INVTYPE_RANGED                                       )] = {  0.50, -0.05, -0.47, OHAND },
    -- Classic
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_HEAD    )] = {  2.25,  0.05, -0.75, -0.50 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_SHOULDER)] = {  2.00, -0.25, -0.65, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_CLOAK   )] = {  1.30,  0.02,  0.00,  BACK },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_CHEST   )] = {  1.90,  0.00, -0.45, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_ROBE    )] = {  1.10,  0.00,  0.05, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_BODY    )] = {  1.90,  0.00, -0.45, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_TABARD  )] = {  1.50,  0.00, -0.15, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_WRIST   )] = {  2.45, -0.25, -0.15, -0.50 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_HAND    )] = {  2.20, -0.25, -0.10, -0.50 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_WAIST   )] = {  2.20,  0.02, -0.20, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_LEGS    )] = {  1.60,  0.00,  0.25, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.INVTYPE_FEET    )] = {  2.00,  0.05,  0.52, -0.80 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.SetsDetails     )] = {  0.00,  0.02, -0.33,  0.00 },
    [Chr(O.Classic,     R.Human,    S.Male,   I.SetsVendor      )] = {  0.75,  0.02, -0.25,  0.00 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_HEAD    )] = {  1.90,  0.02, -0.70, -0.50 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_SHOULDER)] = {  1.90, -0.15, -0.60, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_CLOAK   )] = {  1.05,  0.01, -0.10,  BACK },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_CHEST   )] = {  1.85,  0.00, -0.40, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_ROBE    )] = {  0.90,  0.00,  0.05, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_BODY    )] = {  1.85,  0.00, -0.40, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_TABARD  )] = {  1.45,  0.00, -0.15, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_WRIST   )] = {  2.00, -0.16, -0.20, -0.50 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_HAND    )] = {  1.90, -0.16, -0.15, -0.50 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_WAIST   )] = {  1.90,  0.02, -0.20, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_LEGS    )] = {  1.25,  0.00,  0.22, -0.25 },
    [Chr(O.Classic,     R.Human,    S.Female, I.INVTYPE_FEET    )] = {  1.70,  0.03,  0.50, -0.35 },
    [Chr(O.Classic,     R.Human,    S.Female, I.SetsDetails     )] = {  0.00,  0.02, -0.33,  0.00 },
    [Chr(O.Classic,     R.Human,    S.Female, I.SetsVendor      )] = {  0.75,  0.02, -0.25,  0.00 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_HEAD    )] = {  2.35,  0.10, -0.85, -0.50 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_SHOULDER)] = {  2.10, -0.45, -0.80, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_CLOAK   )] = {  1.15,  0.02, -0.05,  BACK },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_CHEST   )] = {  1.75,  0.00, -0.50, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_ROBE    )] = {  1.20,  0.00,  0.00, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_BODY    )] = {  1.75,  0.00, -0.50, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_TABARD  )] = {  1.80,  0.00, -0.20, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_WRIST   )] = {  2.70, -0.40, -0.15, -0.50 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_HAND    )] = {  2.40, -0.40, -0.05, -0.50 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_WAIST   )] = {  2.40,  0.00, -0.25, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_LEGS    )] = {  1.75,  0.00,  0.25, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.INVTYPE_FEET    )] = {  2.00,  0.00,  0.60, -1.00 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.SetsDetails     )] = {  0.00,  0.02, -0.33,  0.00 },
    [Chr(O.Classic,     R.Orc,      S.Male,   I.SetsVendor      )] = {  0.50,  0.02, -0.25,  0.00 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_HEAD    )] = {  2.20,  0.02, -0.65, -0.50 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_SHOULDER)] = {  2.00, -0.25, -0.55, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_CLOAK   )] = {  1.20,  0.00,  0.05,  BACK },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_CHEST   )] = {  2.05,  0.00, -0.30, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_ROBE    )] = {  1.10,  0.00,  0.15, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_BODY    )] = {  2.05,  0.00, -0.30, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_TABARD  )] = {  1.70,  0.00, -0.10, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_WRIST   )] = {  2.40, -0.25, -0.11, -0.50 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_HAND    )] = {  2.20, -0.25, -0.04, -0.50 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_WAIST   )] = {  2.30,  0.00, -0.15, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_LEGS    )] = {  1.45,  0.00,  0.35, -0.25 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.INVTYPE_FEET    )] = {  1.95,  0.00,  0.63, -1.00 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.SetsDetails     )] = {  0.00,  0.02, -0.28,  0.00 },
    [Chr(O.Classic,     R.Orc,      S.Female, I.SetsVendor      )] = {  1.00,  0.02, -0.20,  0.00 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_HEAD    )] = {  1.60,  0.00, -0.30, -0.50 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_SHOULDER)] = {  1.40, -0.30, -0.20, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_CLOAK   )] = {  1.00,  0.00,  0.20,  BACK },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_CHEST   )] = {  1.25,  0.00,  0.00, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_ROBE    )] = {  1.00,  0.00,  0.20, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_BODY    )] = {  1.25,  0.00,  0.00, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_TABARD  )] = {  1.25,  0.00,  0.15, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_WRIST   )] = {  1.90, -0.32,  0.20, -0.50 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_HAND    )] = {  1.70, -0.33,  0.25, -0.50 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_WAIST   )] = {  1.60,  0.00,  0.20, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_LEGS    )] = {  1.40,  0.00,  0.45, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.INVTYPE_FEET    )] = {  1.40,  0.00,  0.60, -0.65 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.SetsDetails     )] = {  0.00,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.Dwarf,    S.Male,   I.SetsVendor      )] = {  0.50,  0.00,  0.00,  0.00 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_HEAD    )] = {  1.45, -0.02, -0.40, -0.50 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_SHOULDER)] = {  1.50, -0.25, -0.25, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_CLOAK   )] = {  1.00, -0.05,  0.15,  BACK },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_CHEST   )] = {  1.35, -0.05, -0.05, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_ROBE    )] = {  1.00, -0.05,  0.20, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_BODY    )] = {  1.35, -0.05, -0.05, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_TABARD  )] = {  1.25, -0.03,  0.10, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_WRIST   )] = {  1.75, -0.25,  0.10, -0.50 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_HAND    )] = {  1.65, -0.25,  0.13, -0.50 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_WAIST   )] = {  1.55, -0.02,  0.10, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_LEGS    )] = {  1.35, -0.02,  0.37, -0.25 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.INVTYPE_FEET    )] = {  1.50, -0.02,  0.57, -0.85 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.SetsDetails     )] = {  0.00, -0.03, -0.20,  0.00 },
    [Chr(O.Classic,     R.Dwarf,    S.Female, I.SetsVendor      )] = {  0.50, -0.03,  0.00,  0.00 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_HEAD    )] = {  3.20,  0.00, -0.90, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_SHOULDER)] = {  3.00, -0.30, -0.75, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_CLOAK   )] = {  2.05,  0.00,  0.00,  BACK },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_CHEST   )] = {  3.00, -0.05, -0.50, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_ROBE    )] = {  1.95, -0.05,  0.05, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_BODY    )] = {  3.00, -0.05, -0.50, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_TABARD  )] = {  2.60,  0.00, -0.20, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_WRIST   )] = {  3.50, -0.35, -0.23, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_HAND    )] = {  3.20, -0.35, -0.13, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_WAIST   )] = {  3.45, -0.01, -0.25, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_LEGS    )] = {  2.50, -0.05,  0.30, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.INVTYPE_FEET    )] = {  3.00, -0.05,  0.64, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.SetsDetails     )] = {  0.00,  0.00, -0.40,  0.00 },
    [Chr(O.Classic,     R.NightElf, S.Male,   I.SetsVendor      )] = {  1.50,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_HEAD    )] = {  3.05, -0.02, -0.80, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_SHOULDER)] = {  2.95, -0.23, -0.65, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_CLOAK   )] = {  1.80,  0.00,  0.00,  BACK },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_CHEST   )] = {  2.95, -0.02, -0.45, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_ROBE    )] = {  1.65, -0.01,  0.10, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_BODY    )] = {  2.95, -0.02, -0.45, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_TABARD  )] = {  2.50,  0.00, -0.20, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_WRIST   )] = {  3.25, -0.23, -0.20, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_HAND    )] = {  3.05, -0.23, -0.15, -0.50 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_WAIST   )] = {  3.10,  0.00, -0.25, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_LEGS    )] = {  2.05,  0.00,  0.30, -0.25 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.INVTYPE_FEET    )] = {  2.70, -0.03,  0.66, -0.90 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.SetsDetails     )] = {  0.00,  0.00, -0.33,  0.00 },
    [Chr(O.Classic,     R.NightElf, S.Female, I.SetsVendor      )] = {  1.25,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_HEAD    )] = {  2.10, -0.05, -0.85, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_SHOULDER)] = {  2.15, -0.35, -0.80, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_CLOAK   )] = {  1.00, -0.06, -0.15,  BACK },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_CHEST   )] = {  1.75, -0.10, -0.60, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_ROBE    )] = {  0.80, -0.10, -0.05, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_BODY    )] = {  1.75, -0.10, -0.60, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_TABARD  )] = {  1.50, -0.08, -0.30, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_WRIST   )] = {  2.35, -0.30, -0.30, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_HAND    )] = {  2.05, -0.30, -0.25, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_WAIST   )] = {  2.30, -0.10, -0.35, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_LEGS    )] = {  1.40, -0.10,  0.20, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.INVTYPE_FEET    )] = {  2.00, -0.10,  0.45, -1.00 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.SetsDetails     )] = {  0.00,  0.00, -0.33,  0.00 },
    [Chr(O.Classic,     R.Scourge,  S.Male,   I.SetsVendor      )] = {  1.00,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_HEAD    )] = {  2.20,  0.00, -0.75, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_SHOULDER)] = {  2.20, -0.20, -0.60, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_CLOAK   )] = {  1.30,  0.00,  0.05,  BACK },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_CHEST   )] = {  2.20, -0.02, -0.35, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_ROBE    )] = {  1.20,  0.00,  0.05, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_BODY    )] = {  2.20, -0.02, -0.35, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_TABARD  )] = {  2.00,  0.00, -0.20, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_WRIST   )] = {  2.60, -0.18, -0.20, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_HAND    )] = {  2.30, -0.18, -0.15, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_WAIST   )] = {  2.50,  0.00, -0.20, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_LEGS    )] = {  1.65,  0.00,  0.25, -0.25 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.INVTYPE_FEET    )] = {  2.10,  0.02,  0.45, -0.50 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.SetsDetails     )] = {  0.00,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.Scourge,  S.Female, I.SetsVendor      )] = {  0.75,  0.00, -0.15,  0.00 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_HEAD    )] = {  2.20,  0.20, -0.50, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_SHOULDER)] = {  1.90, -0.45, -0.60, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_CLOAK   )] = {  1.25,  0.00,  0.00,  BACK },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_CHEST   )] = {  1.65,  0.00, -0.25, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_ROBE    )] = {  1.35,  0.00,  0.05, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_BODY    )] = {  1.65,  0.00, -0.25, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_TABARD  )] = {  1.65,  0.00, -0.10, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_WRIST   )] = {  2.75, -0.45, -0.05, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_HAND    )] = {  2.30, -0.45,  0.05, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_WAIST   )] = {  2.70, -0.02,  0.00, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_LEGS    )] = {  2.25, -0.02,  0.40, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.INVTYPE_FEET    )] = {  2.40, -0.02,  0.60, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.SetsDetails     )] = {  0.00,  0.00, -0.33,  0.00 },
    [Chr(O.Classic,     R.Tauren,   S.Male,   I.SetsVendor      )] = {  0.75,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_HEAD    )] = {  2.10,  0.15, -0.35, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_SHOULDER)] = {  2.25, -0.30, -0.30, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_CLOAK   )] = {  1.25,  0.00,  0.20,  BACK },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_CHEST   )] = {  2.10,  0.00, -0.10, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_ROBE    )] = {  1.25,  0.00,  0.20, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_BODY    )] = {  2.10,  0.00, -0.10, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_TABARD  )] = {  1.50,  0.05,  0.15, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_WRIST   )] = {  2.60, -0.32,  0.25, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_HAND    )] = {  2.25, -0.30,  0.28, -0.50 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_WAIST   )] = {  2.35,  0.00,  0.30, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_LEGS    )] = {  1.85,  0.00,  0.60, -0.25 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.INVTYPE_FEET    )] = {  2.20,  0.00,  0.90, -0.60 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.SetsDetails     )] = {  0.00,  0.00, -0.33,  0.00 },
    [Chr(O.Classic,     R.Tauren,   S.Female, I.SetsVendor      )] = {  0.75,  0.00, -0.15,  0.00 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_HEAD    )] = {  1.00,  0.00, -0.20, -0.50 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_SHOULDER)] = {  1.15, -0.22, -0.10, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_CLOAK   )] = {  1.00,  0.00,  0.20,  BACK },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_CHEST   )] = {  1.10, -0.02,  0.05, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_ROBE    )] = {  1.00, -0.02,  0.15, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_BODY    )] = {  1.10, -0.02,  0.05, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_TABARD  )] = {  1.25,  0.00,  0.15, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_WRIST   )] = {  1.50, -0.15,  0.15, -1.10 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_HAND    )] = {  1.50, -0.22,  0.17, -0.50 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_WAIST   )] = {  1.30,  0.00,  0.20, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_LEGS    )] = {  1.25,  0.00,  0.32, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.INVTYPE_FEET    )] = {  1.35, -0.02,  0.40, -1.00 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.SetsDetails     )] = {  0.00,  0.00, -0.15,  0.00 },
    [Chr(O.Classic,     R.Gnome,    S.Male,   I.SetsVendor      )] = {  0.50,  0.00,  0.00,  0.00 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_HEAD    )] = {  0.90, -0.03, -0.20, -0.50 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_SHOULDER)] = {  1.00, -0.20, -0.05, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_CLOAK   )] = {  0.90,  0.00,  0.20,  BACK },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_CHEST   )] = {  1.10, -0.02,  0.10, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_ROBE    )] = {  1.05, -0.02,  0.20, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_BODY    )] = {  1.10, -0.02,  0.10, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_TABARD  )] = {  1.15, -0.02,  0.18, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_WRIST   )] = {  1.35, -0.17,  0.17, -0.90 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_HAND    )] = {  1.35, -0.19,  0.20, -0.50 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_WAIST   )] = {  1.25, -0.02,  0.20, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_LEGS    )] = {  1.25, -0.02,  0.32, -0.25 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.INVTYPE_FEET    )] = {  1.25, -0.05,  0.40, -1.00 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.SetsDetails     )] = {  0.00,  0.00, -0.15,  0.00 },
    [Chr(O.Classic,     R.Gnome,    S.Female, I.SetsVendor      )] = {  0.50,  0.00,  0.00,  0.00 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_HEAD    )] = {  2.90,  0.05, -1.00, -0.50 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_SHOULDER)] = {  2.70, -0.35, -0.95, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_CLOAK   )] = {  1.50,  0.00, -0.25,  BACK },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_CHEST   )] = {  2.45,  0.00, -0.55, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_ROBE    )] = {  1.00,  0.00, -0.05, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_BODY    )] = {  2.45,  0.00, -0.55, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_TABARD  )] = {  2.00,  0.00, -0.30, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_WRIST   )] = {  3.25, -0.35, -0.13, -0.20 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_HAND    )] = {  3.00, -0.35, -0.05,  0.05 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_WAIST   )] = {  3.25, -0.01, -0.25, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_LEGS    )] = {  1.80,  0.00,  0.30, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.INVTYPE_FEET    )] = {  2.80, -0.05,  0.70, -0.80 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.SetsDetails     )] = {  0.00, -0.02, -0.33,  0.00 },
    [Chr(O.Classic,     R.Troll,    S.Male,   I.SetsVendor      )] = {  0.75, -0.02, -0.15,  0.00 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_HEAD    )] = {  3.00, -0.05, -0.65, -0.50 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_SHOULDER)] = {  2.85, -0.30, -0.45, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_CLOAK   )] = {  1.50, -0.05,  0.15,  BACK },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_CHEST   )] = {  2.85, -0.05, -0.30, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_ROBE    )] = {  1.40, -0.05,  0.20, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_BODY    )] = {  2.85, -0.05, -0.30, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_TABARD  )] = {  2.25, -0.05, -0.05, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_WRIST   )] = {  3.10, -0.30,  0.02, -0.50 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_HAND    )] = {  2.85, -0.30,  0.07, -0.50 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_WAIST   )] = {  3.10, -0.05, -0.02, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_LEGS    )] = {  2.10, -0.05,  0.45, -0.25 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.INVTYPE_FEET    )] = {  2.85, -0.07,  0.78, -0.50 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.SetsDetails     )] = {  0.00, -0.02, -0.33,  0.00 },
    [Chr(O.Classic,     R.Troll,    S.Female, I.SetsVendor      )] = {  1.25, -0.02, -0.10,  0.00 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_HEAD    )] = {  2.85,  0.02, -0.85, -0.30 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_SHOULDER)] = {  2.50, -0.25, -0.75, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_CLOAK   )] = {  1.80, -0.10, -0.10,  BACK },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_CHEST   )] = {  2.45,  0.00, -0.40,  0.10 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_ROBE    )] = {  1.50, -0.05,  0.05,  0.10 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_BODY    )] = {  2.45,  0.00, -0.40,  0.10 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_TABARD  )] = {  2.15,  0.00, -0.20,  0.10 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_WRIST   )] = {  3.00, -0.25, -0.30, -0.35 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_HAND    )] = {  2.85, -0.22, -0.25, -0.50 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_WAIST   )] = {  2.85,  0.02, -0.30,  0.10 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_LEGS    )] = {  2.00, -0.10,  0.20,  0.10 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.INVTYPE_FEET    )] = {  2.45, -0.10,  0.47, -0.70 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.SetsDetails     )] = {  0.00,  0.00, -0.33,  0.00 },
    [Chr(O.Classic,     R.BloodElf, S.Male,   I.SetsVendor      )] = {  1.25,  0.00, -0.25,  0.00 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_HEAD    )] = {  2.35,  0.03, -0.65, -0.50 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_SHOULDER)] = {  2.45, -0.13, -0.55, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_CLOAK   )] = {  1.30,  0.03,  0.00,  BACK },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_CHEST   )] = {  2.30,  0.03, -0.35, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_ROBE    )] = {  1.20,  0.02,  0.10, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_BODY    )] = {  2.30,  0.03, -0.35, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_TABARD  )] = {  1.95,  0.02, -0.17, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_WRIST   )] = {  2.50, -0.15, -0.15, -0.50 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_HAND    )] = {  2.30, -0.15, -0.10, -0.50 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_WAIST   )] = {  2.40,  0.05, -0.20, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_LEGS    )] = {  1.55,  0.00,  0.25, -0.25 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.INVTYPE_FEET    )] = {  2.05,  0.00,  0.55, -0.90 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.SetsDetails     )] = {  0.00,  0.03, -0.33,  0.00 },
    [Chr(O.Classic,     R.BloodElf, S.Female, I.SetsVendor      )] = {  1.00,  0.03, -0.15,  0.00 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_HEAD    )] = {  3.20, -0.05, -0.55, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_SHOULDER)] = {  2.80, -0.50, -0.40, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_CLOAK   )] = {  2.05, -0.10,  0.20,  BACK },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_CHEST   )] = {  2.50, -0.10, -0.25, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_ROBE    )] = {  1.80, -0.10,  0.30, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_BODY    )] = {  2.50, -0.10, -0.25, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_TABARD  )] = {  2.50, -0.10,  0.10, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_WRIST   )] = {  3.50, -0.45,  0.22, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_HAND    )] = {  3.20, -0.45,  0.25, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_WAIST   )] = {  3.20, -0.10,  0.25, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_LEGS    )] = {  2.55, -0.10,  0.65, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.INVTYPE_FEET    )] = {  2.95, -0.10,  1.00, -0.80 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.SetsDetails     )] = {  0.00, -0.10, -0.40,  0.00 },
    [Chr(O.Classic,     R.Draenei,  S.Male,   I.SetsVendor      )] = {  1.25, -0.06, -0.15,  0.00 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_HEAD    )] = {  2.75,  0.00, -0.90, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_SHOULDER)] = {  3.00, -0.25, -0.75, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_CLOAK   )] = {  2.00,  0.00, -0.10,  BACK },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_CHEST   )] = {  2.80, -0.03, -0.45, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_ROBE    )] = {  1.60, -0.00,  0.10, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_BODY    )] = {  2.80, -0.03, -0.45, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_TABARD  )] = {  2.45, -0.03, -0.25, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_WRIST   )] = {  3.20, -0.22, -0.30, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_HAND    )] = {  2.90, -0.23, -0.25, -0.50 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_WAIST   )] = {  3.00, -0.02, -0.30, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_LEGS    )] = {  2.10, -0.02,  0.30, -0.25 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.INVTYPE_FEET    )] = {  2.70, -0.03,  0.55, -0.80 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.SetsDetails     )] = {  0.00,  0.00, -0.33,  0.00 },
    [Chr(O.Classic,     R.Draenei,  S.Female, I.SetsVendor      )] = {  1.25,  0.00, -0.33,  0.00 },
};

-- The upstream addon receives this entry from PREVIEWCREATURE:WEAPON. The
-- AzerothCore 3.3.5 base row 14307 uses invisible display 11686 and is kept
-- loaded only as the fixed weapon attachment skeleton. Deployments may replace
-- the entry without changing any per-item camera data.
ezCollections.weaponPreviewCreatureEntry = ezCollections.weaponPreviewCreatureEntry or 14307

local SLOT_TO_INV_TYPE = {
    HEAD = "INVTYPE_HEAD",
    SHOULDER = "INVTYPE_SHOULDER",
    BACK = "INVTYPE_CLOAK",
    CHEST = "INVTYPE_CHEST",
    WRIST = "INVTYPE_WRIST",
    HANDS = "INVTYPE_HAND",
    WAIST = "INVTYPE_WAIST",
    LEGS = "INVTYPE_LEGS",
    FEET = "INVTYPE_FEET",
}

local WEAPON_SUBCLASS_BY_TYPE = {
    ONE_HAND_AXE = 0,
    TWO_HAND_AXE = 1,
    BOW = 2,
    GUN = 3,
    ONE_HAND_MACE = 4,
    TWO_HAND_MACE = 5,
    POLEARM = 6,
    ONE_HAND_SWORD = 7,
    TWO_HAND_SWORD = 8,
    STAFF = 9,
    FIST_WEAPON = 10,
    WAR_GLAIVE = 7,
    DAGGER = 12,
    THROWN = 13,
    CROSSBOW = 14,
    WAND = 15,
    FISHING_POLE = 16,
}

local TWO_HAND_TYPES = {
    TWO_HAND_AXE = true,
    TWO_HAND_MACE = true,
    POLEARM = true,
    TWO_HAND_SWORD = true,
    STAFF = true,
    FISHING_POLE = true,
}

local function getRecordInventoryType(record)
    local itemId = record and tonumber(record.itemId)
    local inventoryType = itemId and select(9, GetItemInfo(itemId)) or nil
    if inventoryType and inventoryType ~= "" then
        return inventoryType
    end
    if not record then return nil end
    if record.weaponType == "SHIELD" then return "INVTYPE_SHIELD" end
    if record.weaponType == "THROWN" then return "INVTYPE_THROWN" end
    if record.weaponType == "WAND" then return "INVTYPE_RANGEDRIGHT" end
    if record.weaponType == "BOW" or record.weaponType == "GUN" or record.weaponType == "CROSSBOW" then
        return "INVTYPE_RANGED"
    end
    if TWO_HAND_TYPES[record.weaponType] then return "INVTYPE_2HWEAPON" end
    if record.slot == "OFFHAND" then return "INVTYPE_WEAPONOFFHAND" end
    if record.slot == "MAINHAND" then return "INVTYPE_WEAPONMAINHAND" end
    return SLOT_TO_INV_TYPE[record.slot]
end

function ezCollections:SetWeaponPreviewCreatureEntry(entry)
    entry = tonumber(entry)
    if not entry or entry <= 0 or entry ~= math.floor(entry) then return false end
    self.weaponPreviewCreatureEntry = entry
    return true
end

function ezCollections:IsWeaponRecord(record)
    return record and (record.slot == "MAINHAND" or record.slot == "OFFHAND")
end

function ezCollections:GetRecordCamera(record)
    if not record then return nil, nil, "RECORD_UNAVAILABLE" end
    local inventoryType = getRecordInventoryType(record)
    if not inventoryType then return nil, nil, "INVENTORY_TYPE_UNAVAILABLE" end
    local cameraID, reason
    if self:IsWeaponRecord(record) then
        cameraID, reason = self:GetWeaponCameraID(inventoryType, WEAPON_SUBCLASS_BY_TYPE[record.weaponType])
    else
        cameraID, reason = self:GetCharacterCameraID(inventoryType)
    end
    if not cameraID then return nil, nil, reason or "CAMERA_ID_UNAVAILABLE" end
    local camera = self.Cameras[cameraID]
    if not camera then return nil, cameraID, "CAMERA_TUPLE_UNAVAILABLE" end
    return camera, cameraID, "READY"
end

function ezCollections:GetRecordAnimation(record, camera)
    if camera and camera[5] then return camera[5] end
    if self:IsWeaponRecord(record) then
        return record.slot == "OFFHAND" and 63 or 51
    end
    return 15
end

function ezCollections:ApplyRecordCamera(model, record)
    if not model then return false, "MODEL_UNAVAILABLE" end
    if not record then return false, "RECORD_UNAVAILABLE" end
    local camera, cameraID, cameraReason = self:GetRecordCamera(record)
    if not camera then return false, cameraReason or "CAMERA_UNAVAILABLE", cameraID end
    if not model.SetPosition then return false, "SET_POSITION_UNAVAILABLE", cameraID end
    local modelScale = self:IsWeaponRecord(record) and 1 or 10
    if model.SetModelScale then
        local scaleApplied = pcall(function() model:SetModelScale(modelScale) end)
        if not scaleApplied then return false, "SET_SCALE_FAILED", cameraID end
    end
    if model.GetModelScale then
        local ok, value = pcall(function() return model:GetModelScale() end)
        if ok and type(value) == "number" then modelScale = value end
    end
    local screenWidth, screenHeight = GetScreenWidth(), GetScreenHeight()
    if type(screenWidth) ~= "number" or type(screenHeight) ~= "number" or screenHeight <= 0 then
        return false, "SCREEN_SIZE_UNAVAILABLE", cameraID
    end
    local screenRatio = screenWidth / screenHeight
    local ratio = (0.5 + ((1600 / 900) / screenRatio) / 2) * modelScale
    local expectedX = camera[1] * ratio
    local expectedY = camera[2] * ratio
    local expectedZ = camera[3] * ratio
    local positioned = pcall(function()
        model:SetPosition(expectedX, expectedY, expectedZ)
    end)
    if not positioned then return false, "SET_POSITION_FAILED", cameraID end
    if model.SetFacing then
        local faced = pcall(function() model:SetFacing(camera[4]) end)
        if not faced then return false, "SET_FACING_FAILED", cameraID end
    elseif model.SetRotation then
        local rotated = pcall(function() model:SetRotation(camera[4]) end)
        if not rotated then return false, "SET_ROTATION_FAILED", cameraID end
    else
        return false, "SET_FACING_UNAVAILABLE", cameraID
    end
    model.scEzAnimID = self:GetRecordAnimation(record, camera)
    model.scEzExpectedScale = modelScale
    model.scEzExpectedX = expectedX
    model.scEzExpectedY = expectedY
    model.scEzExpectedZ = expectedZ
    model.scEzExpectedFacing = camera[4]
    return true, "READY", cameraID
end

-- The upstream WardrobeItemsModelTemplate is already on the native dressing
-- room camera. SoloCollections owns independent DressUpModels, so repeat that
-- template state only at model rebuild boundaries. Do not run SetCamera every
-- render frame: SoloCam also uses this API as a private command transport.
function ezCollections:ActivateRecordCamera(model)
    if not model then return false, "MODEL_UNAVAILABLE" end
    if not model.SetCamera then return true, "CAMERA_API_UNAVAILABLE" end
    local selected = pcall(function() model:SetCamera(1) end)
    return selected and true or false, selected and "READY" or "SET_CAMERA_FAILED"
end

-- SetSequenceTime is evaluated every frame to keep wardrobe cards static. On
-- the target 3.3.5 client that operation can restore the model's default
-- full-body pose after the initial camera application. Reapply only the cheap
-- ezCollections position/facing tuple after the animation freeze; scale and
-- camera selection remain lifecycle operations.
function ezCollections:RetainRecordCamera(model)
    if not model then return false, "MODEL_UNAVAILABLE" end
    if type(model.scEzExpectedX) ~= "number"
        or type(model.scEzExpectedY) ~= "number"
        or type(model.scEzExpectedZ) ~= "number" then
        return false, "EXPECTED_POSITION_UNAVAILABLE"
    end
    if not model.SetPosition then return false, "SET_POSITION_UNAVAILABLE" end
    local positioned = pcall(function()
        model:SetPosition(model.scEzExpectedX, model.scEzExpectedY, model.scEzExpectedZ)
    end)
    if not positioned then return false, "SET_POSITION_FAILED" end
    if model.SetFacing and type(model.scEzExpectedFacing) == "number" then
        local faced = pcall(function() model:SetFacing(model.scEzExpectedFacing) end)
        if not faced then return false, "SET_FACING_FAILED" end
    elseif model.SetRotation and type(model.scEzExpectedFacing) == "number" then
        local rotated = pcall(function() model:SetRotation(model.scEzExpectedFacing) end)
        if not rotated then return false, "SET_ROTATION_FAILED" end
    end
    return true, "READY"
end

local function nearlyEqual(actual, expected, tolerance)
    return type(actual) == "number" and type(expected) == "number"
        and math.abs(actual - expected) <= tolerance
end

function ezCollections:VerifyRecordCamera(model, record)
    if not model or not record then return false, "VERIFY_INPUT_UNAVAILABLE" end
    if not model.GetPosition then return false, "GET_POSITION_UNAVAILABLE" end
    if type(model.scEzExpectedX) ~= "number" then return false, "EXPECTED_POSITION_UNAVAILABLE" end
    local ok, actualX, actualY, actualZ = pcall(function() return model:GetPosition() end)
    if not ok then return false, "GET_POSITION_FAILED" end
    local positionReady = nearlyEqual(actualX, model.scEzExpectedX, 0.02)
        and nearlyEqual(actualY, model.scEzExpectedY, 0.02)
        and nearlyEqual(actualZ, model.scEzExpectedZ, 0.02)
    if not positionReady then
        return false, "CAMERA_POSITION_RESET", actualX, actualY, actualZ
    end
    if model.GetModelScale and type(model.scEzExpectedScale) == "number" then
        local scaleOK, actualScale = pcall(function() return model:GetModelScale() end)
        if not scaleOK then return false, "GET_SCALE_FAILED" end
        if not nearlyEqual(actualScale, model.scEzExpectedScale, 0.02) then
            return false, "CAMERA_SCALE_RESET", actualScale
        end
    end
    return true, "READY", actualX, actualY, actualZ
end
