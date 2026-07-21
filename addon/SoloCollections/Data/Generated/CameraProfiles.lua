local SC = SoloCollections

SC.CameraProfiles = SC.CameraProfiles or {}

local CameraProfiles = SC.CameraProfiles
CameraProfiles.schemaVersion = 1
CameraProfiles.profileVersion = 1
CameraProfiles.profileHash = "5f7ec4dde75364cbd1e9886aed139a9855c4facc11766b44be40223e7c0013b1"
CameraProfiles.mode = CameraProfiles.mode or "Generated"

CameraProfiles.slotOrder = { "HEAD", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET" }

CameraProfiles.runtimeRaceProfiles = {
    Human = "race.human",
    Orc = "race.orc",
    Dwarf = "race.dwarf",
    NightElf = "race.night_elf",
    Scourge = "race.undead",
    Tauren = "race.tauren",
    Gnome = "race.gnome",
    Troll = "race.troll",
    BloodElf = "race.blood_elf",
    Draenei = "race.draenei",
}

CameraProfiles.entries = {
    ["race.blood_elf"] = {
        MALE = { HEAD = 0x6087, SHOULDER = 0x6088, BACK = 0x6089, CHEST = 0x608A, WRIST = 0x608B, HANDS = 0x608C, WAIST = 0x608D, LEGS = 0x608E, FEET = 0x608F },
        FEMALE = { HEAD = 0x6090, SHOULDER = 0x6091, BACK = 0x6092, CHEST = 0x6093, WRIST = 0x6094, HANDS = 0x6095, WAIST = 0x6096, LEGS = 0x6097, FEET = 0x6098 },
    },
    ["race.draenei"] = {
        MALE = { HEAD = 0x6099, SHOULDER = 0x609A, BACK = 0x609B, CHEST = 0x609C, WRIST = 0x609D, HANDS = 0x609E, WAIST = 0x609F, LEGS = 0x60A0, FEET = 0x60A1 },
        FEMALE = { HEAD = 0x60A2, SHOULDER = 0x60A3, BACK = 0x60A4, CHEST = 0x60A5, WRIST = 0x60A6, HANDS = 0x60A7, WAIST = 0x60A8, LEGS = 0x60A9, FEET = 0x60AA },
    },
    ["race.dwarf"] = {
        MALE = { HEAD = 0x601B, SHOULDER = 0x601C, BACK = 0x601D, CHEST = 0x601E, WRIST = 0x601F, HANDS = 0x6020, WAIST = 0x6021, LEGS = 0x6022, FEET = 0x6023 },
        FEMALE = { HEAD = 0x6024, SHOULDER = 0x6025, BACK = 0x6026, CHEST = 0x6027, WRIST = 0x6028, HANDS = 0x6029, WAIST = 0x602A, LEGS = 0x602B, FEET = 0x602C },
    },
    ["race.gnome"] = {
        MALE = { HEAD = 0x6063, SHOULDER = 0x6064, BACK = 0x6065, CHEST = 0x6066, WRIST = 0x6067, HANDS = 0x6068, WAIST = 0x6069, LEGS = 0x606A, FEET = 0x606B },
        FEMALE = { HEAD = 0x606C, SHOULDER = 0x606D, BACK = 0x606E, CHEST = 0x606F, WRIST = 0x6070, HANDS = 0x6071, WAIST = 0x6072, LEGS = 0x6073, FEET = 0x6074 },
    },
    ["race.human"] = {
        MALE = { HEAD = 0x6000, SHOULDER = 0x6001, BACK = 0x6002, CHEST = 0x6003, WRIST = 0x6004, HANDS = 0x6005, WAIST = 0x6006, LEGS = 0x6007, FEET = 0x6008 },
        FEMALE = { HEAD = 0x5341, SHOULDER = 0x5342, BACK = 0x5349, CHEST = 0x5343, WRIST = 0x5344, HANDS = 0x5345, WAIST = 0x5346, LEGS = 0x5347, FEET = 0x5348 },
    },
    ["race.night_elf"] = {
        MALE = { HEAD = 0x602D, SHOULDER = 0x602E, BACK = 0x602F, CHEST = 0x6030, WRIST = 0x6031, HANDS = 0x6032, WAIST = 0x6033, LEGS = 0x6034, FEET = 0x6035 },
        FEMALE = { HEAD = 0x6036, SHOULDER = 0x6037, BACK = 0x6038, CHEST = 0x6039, WRIST = 0x603A, HANDS = 0x603B, WAIST = 0x603C, LEGS = 0x603D, FEET = 0x603E },
    },
    ["race.orc"] = {
        MALE = { HEAD = 0x6009, SHOULDER = 0x600A, BACK = 0x600B, CHEST = 0x600C, WRIST = 0x600D, HANDS = 0x600E, WAIST = 0x600F, LEGS = 0x6010, FEET = 0x6011 },
        FEMALE = { HEAD = 0x6012, SHOULDER = 0x6013, BACK = 0x6014, CHEST = 0x6015, WRIST = 0x6016, HANDS = 0x6017, WAIST = 0x6018, LEGS = 0x6019, FEET = 0x601A },
    },
    ["race.tauren"] = {
        MALE = { HEAD = 0x6051, SHOULDER = 0x6052, BACK = 0x6053, CHEST = 0x6054, WRIST = 0x6055, HANDS = 0x6056, WAIST = 0x6057, LEGS = 0x6058, FEET = 0x6059 },
        FEMALE = { HEAD = 0x605A, SHOULDER = 0x605B, BACK = 0x605C, CHEST = 0x605D, WRIST = 0x605E, HANDS = 0x605F, WAIST = 0x6060, LEGS = 0x6061, FEET = 0x6062 },
    },
    ["race.troll"] = {
        MALE = { HEAD = 0x6075, SHOULDER = 0x6076, BACK = 0x6077, CHEST = 0x6078, WRIST = 0x6079, HANDS = 0x607A, WAIST = 0x607B, LEGS = 0x607C, FEET = 0x607D },
        FEMALE = { HEAD = 0x607E, SHOULDER = 0x607F, BACK = 0x6080, CHEST = 0x6081, WRIST = 0x6082, HANDS = 0x6083, WAIST = 0x6084, LEGS = 0x6085, FEET = 0x6086 },
    },
    ["race.undead"] = {
        MALE = { HEAD = 0x603F, SHOULDER = 0x6040, BACK = 0x6041, CHEST = 0x6042, WRIST = 0x6043, HANDS = 0x6044, WAIST = 0x6045, LEGS = 0x6046, FEET = 0x6047 },
        FEMALE = { HEAD = 0x6048, SHOULDER = 0x6049, BACK = 0x604A, CHEST = 0x604B, WRIST = 0x604C, HANDS = 0x604D, WAIST = 0x604E, LEGS = 0x604F, FEET = 0x6050 },
    },
}

CameraProfiles.modelPaths = {
    ["race.blood_elf"] = { MALE = "Character\\BloodElf\\Male\\BloodElfMale.m2", FEMALE = "Character\\BloodElf\\Female\\BloodElfFemale.m2" },
    ["race.draenei"] = { MALE = "Character\\Draenei\\Male\\DraeneiMale.m2", FEMALE = "Character\\Draenei\\Female\\DraeneiFemale.m2" },
    ["race.dwarf"] = { MALE = "Character\\Dwarf\\Male\\DwarfMale.m2", FEMALE = "Character\\Dwarf\\Female\\DwarfFemale.m2" },
    ["race.gnome"] = { MALE = "Character\\Gnome\\Male\\GnomeMale.m2", FEMALE = "Character\\Gnome\\Female\\GnomeFemale.m2" },
    ["race.human"] = { MALE = "Character\\Human\\Male\\HumanMale.m2", FEMALE = "Character\\Human\\Female\\HumanFemale.m2" },
    ["race.night_elf"] = { MALE = "Character\\NightElf\\Male\\NightElfMale.m2", FEMALE = "Character\\NightElf\\Female\\NightElfFemale.m2" },
    ["race.orc"] = { MALE = "Character\\Orc\\Male\\OrcMale.m2", FEMALE = "Character\\Orc\\Female\\OrcFemale.m2" },
    ["race.tauren"] = { MALE = "Character\\Tauren\\Male\\TaurenMale.m2", FEMALE = "Character\\Tauren\\Female\\TaurenFemale.m2" },
    ["race.troll"] = { MALE = "Character\\Troll\\Male\\TrollMale.m2", FEMALE = "Character\\Troll\\Female\\TrollFemale.m2" },
    ["race.undead"] = { MALE = "Character\\Scourge\\Male\\ScourgeMale.m2", FEMALE = "Character\\Scourge\\Female\\ScourgeFemale.m2" },
}

CameraProfiles.previewDisplayIds = {
    ["race.blood_elf"] = { MALE = 10375, FEMALE = 15505 },
    ["race.draenei"] = { MALE = 16199, FEMALE = 16200 },
    ["race.dwarf"] = { MALE = 115, FEMALE = 1286 },
    ["race.gnome"] = { MALE = 1832, FEMALE = 1890 },
    ["race.human"] = { MALE = 1276, FEMALE = 176 },
    ["race.night_elf"] = { MALE = 1285, FEMALE = 1543 },
    ["race.orc"] = { MALE = 1139, FEMALE = 1312 },
    ["race.tauren"] = { MALE = 1624, FEMALE = 1905 },
    ["race.troll"] = { MALE = 1976, FEMALE = 1882 },
    ["race.undead"] = { MALE = 1027, FEMALE = 1029 },
}

function CameraProfiles.SetMode(mode)
    if mode ~= "LegacyHumanFemale" and mode ~= "Compare" and mode ~= "Generated" and mode ~= "Native" then
        return false
    end
    CameraProfiles.mode = mode
    return true
end

function CameraProfiles.GetSentinel(raceToken, sex, slot, clientAssetProfile)
    if CameraProfiles.mode == "Native" then return nil end
    local family = CameraProfiles.runtimeRaceProfiles[raceToken]
    if not family then return nil end
    if clientAssetProfile and clientAssetProfile ~= family then return nil end
    local sexKey = sex == 2 and "MALE" or (sex == 3 and "FEMALE" or nil)
    if not sexKey then return nil end
    local familyEntries = CameraProfiles.entries[family]
    local sexEntries = familyEntries and familyEntries[sexKey]
    local generated = sexEntries and sexEntries[slot] or nil
    if CameraProfiles.mode == "Compare" then
        -- Ephemeral diagnostics only: do not persist a second mutable profile table.
        CameraProfiles.lastComparison = { family = family, sex = sexKey, slot = slot, generated = generated }
        if family ~= "race.human" or sexKey ~= "FEMALE" then return nil end
        return generated
    end
    if CameraProfiles.mode == "LegacyHumanFemale" then
        if family ~= "race.human" or sexKey ~= "FEMALE" then return nil end
    end
    return generated
end
