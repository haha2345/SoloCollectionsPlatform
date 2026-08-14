local SC = SoloCollections
local UI = SC.UI
local Catalog = SC.Catalog
local Identity = SC.IdentityRegistry
local EzModel = SC.EzWardrobe.Model
local EzItems = SC.EzWardrobe.Items

local ITEM_PAGE_SIZE = EzItems.PAGE_SIZE
local VISIBLE_SET_ROWS = 8
local SET_LIST_TOP_OFFSET = 36
local SET_ROW_HEIGHT = 52
local SET_ROW_SPACING = 3
local SET_PIECE_SIZE = 40
local SET_PIECE_SPACING = 5
local SET_PIECE_COLUMNS = 8
local SET_PIECE_POOL_LIMIT = 12
local SET_DETAILS_NAME_Y = -37
local SET_DETAILS_LONG_NAME_Y = -30
local SET_DETAILS_LABEL_Y = -63
local SET_DETAILS_ICON_ROW_Y = -94
local SET_DETAILS_MODEL_TOP_Y = -128
local DEFAULT_ROTATION = 0.18
local TWO_PI = math.pi * 2
local DRAG_ROTATION_CONSTANT = tonumber(MODELFRAME_DRAG_ROTATION_CONSTANT) or 0.010
local function showAppearanceActionResult(ok, reason)
    local message
    if ok then
        message = "外观已应用。"
    elseif reason == "NOT_ENOUGH_MONEY" then
        message = "你没有足够的钱。"
    elseif reason == "NOT_ENOUGH_TOKENS" then
        message = "你的筹码不够。"
    elseif reason == "NOT_OWNED" then
        message = "尚未收藏此外观。"
    elseif reason == "INVALID_TARGET_SLOT" then
        message = "对应装备栏没有可幻化物品。"
    else
        message = "外观应用失败：" .. tostring(reason or "UNKNOWN")
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, ok and 0.35 or 1, ok and 1 or 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

local function showSetActionResult(ok, reason)
    local message
    if ok then
        message = "套装外观已原子应用。"
    elseif reason == "NOT_OWNED" then
        message = "尚未收集完整套装。"
    elseif reason == "INVALID_TARGET_SLOT" then
        message = "需要先在套装的每个目标栏位装备物品。"
    elseif reason == "CLASS_RESTRICTED" then
        message = "当前角色无法使用这个套装外观。"
    elseif reason == "NOT_ENOUGH_MONEY" then
        message = "你没有足够的钱。"
    elseif reason == "NOT_ENOUGH_TOKENS" then
        message = "你的筹码不够。"
    elseif reason == "BRIDGE_UNAVAILABLE" then
        message = "统一收藏服务尚未就绪。"
    else
        message = "套装应用失败：" .. tostring(reason or "UNKNOWN")
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, ok and 0.35 or 1, ok and 1 or 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

--[=[ Reference-only legacy SoloCam/workbench profiles. This long-commented
-- block is deliberately excluded from the active runtime chunk; item cards
-- have no callable fallback to it.
--
-- WotLK player models expose only camera 0 (portrait) and camera 1
-- (dressing-room). Adding a third camera to the player M2 crashes the client,
-- so SoloCam uses a generated race/sex/slot SetCamera handshake. The
-- immediately following camera 1 call is a safe stock-client fallback.
-- Legacy DressUpModel frames also keep the same fixed rectangle as their
-- cards: the 3.3.5 renderer does not safely clip oversized 3D viewports.
local WARDROBE_MODEL_PROFILES = {
    DEFAULT = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
    HEAD = { camera = 0, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.50 },
    SHOULDER = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.50 },
    BACK = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 3.14 },
    CHEST = { camera = 1, scaleMultiplier = 2.40, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = -0.30, rotation = 0.08 },
    WRIST = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = -0.62 },
    HANDS = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = -0.62 },
    WAIST = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
    LEGS = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
    FEET = { camera = 1, scaleMultiplier = 1.00, depthOffset = 0.00, horizontalOffset = 0.00, verticalOffset = 0.00, rotation = 0.08 },
}
--]=]

local CLASS_FILTERS = Identity.GetClassFilterOptions()

local ARMOR_TYPE_FILTERS = SC.EzWardrobe.DataProvider.ARMOR_OPTIONS

local SLOT_FILTERS = {
    { key = "HEAD", label = "头部", atlas = "head" },
    { key = "SHOULDER", label = "肩部", atlas = "shoulder" },
    { key = "BACK", label = "背部", atlas = "back" },
    { key = "CHEST", label = "胸部", atlas = "chest" },
    { key = "WRIST", label = "手腕", atlas = "wrist", gapAfter = 18 },
    { key = "HANDS", label = "手部", atlas = "hands" },
    { key = "WAIST", label = "腰部", atlas = "waist" },
    { key = "LEGS", label = "腿部", atlas = "legs" },
    { key = "FEET", label = "脚部", atlas = "feet", gapAfter = 18 },
    { key = "MAINHAND", label = "主手武器", atlas = "mainhand" },
    { key = "OFFHAND", label = "副手武器", atlas = "secondaryhand" },
}

local SLOT_ATLAS_SIZE = 512
local SLOT_ATLAS_REGIONS = {
    back = { 152, 187, 460, 497 },
    chest = { 231, 266, 48, 85 },
    feet = { 268, 303, 48, 85 },
    hands = { 305, 340, 48, 85 },
    head = { 342, 377, 48, 85 },
    legs = { 379, 414, 48, 85 },
    mainhand = { 416, 451, 48, 85 },
    secondaryhand = { 453, 488, 48, 85 },
    shoulder = { 228, 263, 88, 125 },
    waist = { 302, 337, 88, 125 },
    wrist = { 339, 374, 88, 125 },
    selected = { 105, 150, 460, 507 },
}

local ROUND_HIGHLIGHT_SIZE = { 256, 256 }
local ROUND_HIGHLIGHT_REGION = { 42, 78, 176, 212 }

-- Only categories present in the 3.3.5 ItemSubclass tables are exposed.
-- Warglaive models retain their own camera key, but filter as one-handed
-- swords because WotLK has no separate warglaive weapon subclass.
local WEAPON_FILTERS = {
    { key = "ONE_HAND_AXE", label = "单手斧", main = true, off = true },
    { key = "TWO_HAND_AXE", label = "双手斧", main = true },
    { key = "BOW", label = "弓", main = true },
    { key = "GUN", label = "枪械", main = true },
    { key = "ONE_HAND_MACE", label = "单手锤", main = true, off = true },
    { key = "TWO_HAND_MACE", label = "双手锤", main = true },
    { key = "POLEARM", label = "长柄武器", main = true },
    { key = "ONE_HAND_SWORD", label = "单手剑", main = true, off = true },
    { key = "TWO_HAND_SWORD", label = "双手剑", main = true },
    { key = "STAFF", label = "法杖", main = true },
    { key = "FIST_WEAPON", label = "拳套", main = true, off = true },
    { key = "DAGGER", label = "匕首", main = true, off = true },
    { key = "THROWN", label = "投掷武器", main = true },
    { key = "CROSSBOW", label = "弩", main = true },
    { key = "WAND", label = "魔杖", main = true },
    { key = "FISHING_POLE", label = "钓鱼竿", main = true },
    { key = "SHIELD", label = "盾牌", off = true },
    { key = "OFFHAND_ITEM", label = "副手物品", off = true },
}

local STANDALONE_ITEM_SLOTS = {
    MAINHAND = true,
    OFFHAND = true,
}

-- ItemSet evidence already expresses member slots. Keep preview ordering in
-- that domain rather than asking GetItemInfo for a cache-dependent inventory
-- type while DressUpModel is being rebuilt.
local SET_MEMBER_SLOT_ORDER = {
    HEAD = 1,
    SHOULDER = 2,
    BACK = 3,
    CHEST = 4,
    WRIST = 5,
    HANDS = 6,
    WAIST = 7,
    LEGS = 8,
    FEET = 9,
    MAINHAND = 10,
    OFFHAND = 11,
}

local SLOT_LABEL_BY_KEY = {}
for _, option in ipairs(SLOT_FILTERS) do
    SLOT_LABEL_BY_KEY[option.key] = option.label
end

local function slotLabelFromKey(slotKey)
    return SLOT_LABEL_BY_KEY[tostring(slotKey or "")] or tostring(slotKey or "未知部位")
end

local function filterLabel(options, current)
    for _, option in ipairs(options) do
        if option.key == current then
            return option.label
        end
    end
    return options[1].label
end

local function classLabelFromKey(classKey)
    if classKey and classKey ~= "ALL" and Identity.GetClassByKey then
        local classIdentity = Identity.GetClassByKey(classKey)
        if classIdentity and classIdentity.known then
            return (classIdentity.name and (classIdentity.name.zhCN or classIdentity.name.enUS))
                or classIdentity.filterToken
                or tostring(classKey)
        end
    end
    return filterLabel(CLASS_FILTERS, classKey == "ALL" and "ALL" or string.upper(tostring(classKey or "")))
end

local function effectiveSetClassPolicy(record)
    local presentation = record and record.presentation
    if presentation and presentation.classPolicyOverride then
        return presentation.classPolicyOverride
    end
    return record and record.classPolicy
end

local function setClassLabel(record)
    local policy = effectiveSetClassPolicy(record)
    if not policy then
        return classLabelFromKey(record and record.classToken)
    end
    if policy.mode == "ANY" then return "全部职业" end
    if policy.mode ~= "ALLOW_LIST" then return "职业未解析" end
    local labels = {}
    for _, classKey in ipairs(policy.allowedClassKeys or {}) do
        labels[#labels + 1] = classLabelFromKey(classKey)
    end
    return table.concat(labels, "/")
end

local function setPresentationLabel(record)
    local presentation = record and record.presentation
    if not presentation then return nil end
    local label = presentation.displayLabel
    if label and label ~= "" then return label end
    if presentation.pvpSeason and presentation.pvpSeason ~= "NONE" then
        return presentation.pvpSeason
    end
    if presentation.raidTier and presentation.raidTier ~= "NONE" then
        return presentation.raidTier
    end
    return nil
end

local function setMetadataLine(record)
    local classLabel = setClassLabel(record)
    local presentationLabel = setPresentationLabel(record)
    if presentationLabel then
        return presentationLabel .. "  ·  " .. classLabel
    end
    return classLabel
end

local SET_SOURCE_BY_LABEL = {
    ["T0"] = "经典地下城套装",
    ["T0.5"] = "经典地下城套装升级任务",
    ["T1"] = "熔火之心",
    ["T2"] = "黑翼之巢 / 奥妮克希亚的巢穴",
    ["T2.5"] = "安其拉神殿",
    ["T3"] = "纳克萨玛斯（60级）",
    ["D3"] = "外域地下城套装",
    ["T4"] = "卡拉赞 / 格鲁尔的巢穴 / 玛瑟里顿的巢穴",
    ["T5"] = "毒蛇神殿 / 风暴要塞",
    ["T6"] = "海加尔山之战 / 黑暗神殿 / 太阳之井高地",
}
local SET_SOURCE_T7 = "纳克萨玛斯 / 黑曜石圣殿 / 阿尔卡冯的宝库"
local SET_SOURCE_T8 = "奥杜尔 / 阿尔卡冯的宝库"
local SET_SOURCE_T9 = "十字军的试炼 / 银色锦标赛套装商人"
local SET_SOURCE_T10 = "冰冠堡垒 / 达拉然套装商人"
local SET_SOURCE_PVP = "PvP 商人 / 竞技场赛季奖励"

local NON_CLASS_SET_DETAILS = {
    [1] = { category = "地下城", source = "黑石深渊竞技场" },
    [41] = { category = "武器", source = "黑石塔上层" },
    [65] = { category = "武器", source = "纳克萨玛斯（60级）" },
    [81] = { category = "地下城", source = "斯坦索姆邮差" },
    [121] = { category = "地下城", source = "通灵学院" },
    [122] = { category = "地下城", source = "通灵学院" },
    [123] = { category = "地下城", source = "通灵学院" },
    [124] = { category = "地下城", source = "通灵学院" },
    [141] = { category = "制造", source = "经典旧世制皮" },
    [142] = { category = "制造", source = "经典旧世制皮" },
    [143] = { category = "制造", source = "经典旧世制皮" },
    [144] = { category = "制造", source = "经典旧世制皮" },
    [161] = { category = "地下城", source = "死亡矿井" },
    [162] = { category = "地下城", source = "哀嚎洞穴" },
    [163] = { category = "地下城", source = "血色修道院" },
    [261] = { category = "武器", source = "经典旧世团队首领" },
    [321] = { category = "制造", source = "经典旧世锻造" },
    [421] = { category = "制造", source = "祖尔格拉布声望 / 裁缝" },
    [441] = { category = "制造", source = "祖尔格拉布声望 / 制皮" },
    [442] = { category = "制造", source = "祖尔格拉布声望 / 制皮" },
    [443] = { category = "制造", source = "祖尔格拉布声望 / 锻造" },
    [444] = { category = "制造", source = "祖尔格拉布声望 / 锻造" },
    [461] = { category = "武器", source = "祖尔格拉布" },
    [463] = { category = "武器", source = "祖尔格拉布" },
    [489] = { category = "制造", source = "经典旧世制皮" },
    [490] = { category = "制造", source = "经典旧世制皮" },
    [491] = { category = "制造", source = "经典旧世制皮" },
    [492] = { category = "声望", source = "希利苏斯暮光信徒" },
    [533] = { category = "事件", source = "天灾入侵事件" },
    [534] = { category = "事件", source = "天灾入侵事件" },
    [535] = { category = "事件", source = "天灾入侵事件" },
    [536] = { category = "事件", source = "天灾入侵事件" },
    [552] = { category = "制造", source = "外域裁缝" },
    [553] = { category = "制造", source = "外域裁缝" },
    [554] = { category = "制造", source = "外域裁缝" },
    [555] = { category = "制造", source = "外域裁缝" },
    [556] = { category = "制造", source = "外域裁缝" },
    [557] = { category = "制造", source = "外域裁缝" },
    [558] = { category = "制造", source = "外域裁缝" },
    [559] = { category = "制造", source = "外域裁缝" },
    [560] = { category = "制造", source = "外域锻造" },
    [561] = { category = "制造", source = "外域锻造" },
    [562] = { category = "制造", source = "外域锻造" },
    [563] = { category = "制造", source = "外域锻造" },
    [564] = { category = "制造", source = "外域锻造" },
    [565] = { category = "制造", source = "外域锻造" },
    [566] = { category = "制造", source = "外域锻造" },
    [569] = { category = "制造", source = "外域锻造" },
    [570] = { category = "制造", source = "外域锻造" },
    [571] = { category = "制造", source = "外域裁缝" },
    [572] = { category = "制造", source = "外域裁缝" },
    [573] = { category = "制造", source = "外域制皮" },
    [574] = { category = "制造", source = "外域制皮" },
    [575] = { category = "制造", source = "外域制皮" },
    [576] = { category = "制造", source = "外域制皮" },
    [611] = { category = "制造", source = "外域制皮" },
    [612] = { category = "制造", source = "外域制皮" },
    [613] = { category = "制造", source = "外域制皮" },
    [614] = { category = "制造", source = "外域制皮" },
    [616] = { category = "制造", source = "外域制皮" },
    [617] = { category = "制造", source = "外域制皮" },
    [618] = { category = "制造", source = "外域制皮" },
    [619] = { category = "地下城", source = "外域地下城套装" },
    [658] = { category = "地下城", source = "外域地下城套装" },
    [659] = { category = "地下城", source = "外域地下城套装" },
    [660] = { category = "地下城", source = "外域地下城套装" },
    [661] = { category = "地下城", source = "外域地下城套装" },
    [719] = { category = "PvP", source = "外域 PvP 声望" },
    [754] = { category = "制造", source = "诺森德制皮" },
    [755] = { category = "制造", source = "诺森德制皮" },
    [756] = { category = "制造", source = "诺森德制皮" },
    [757] = { category = "制造", source = "诺森德制皮" },
    [761] = { category = "节日", source = "冬幕节" },
    [762] = { category = "节日", source = "美酒节" },
    [763] = { category = "制造", source = "诺森德裁缝" },
    [764] = { category = "制造", source = "诺森德裁缝" },
    [781] = { category = "事件", source = "天灾入侵事件" },
    [782] = { category = "事件", source = "天灾入侵事件" },
    [783] = { category = "事件", source = "天灾入侵事件" },
    [784] = { category = "事件", source = "天灾入侵事件" },
    [785] = { category = "节日", source = "仲夏火焰节" },
    [812] = { category = "节日", source = "复活节 / 春季礼服" },
    [813] = { category = "制造", source = "诺森德制皮 PvP 套装" },
    [814] = { category = "制造", source = "诺森德锻造 PvP 套装" },
    [815] = { category = "制造", source = "诺森德裁缝 PvP 套装" },
    [816] = { category = "制造", source = "诺森德锻造 PvP 套装" },
    [817] = { category = "制造", source = "诺森德制皮 PvP 套装" },
    [818] = { category = "制造", source = "诺森德制皮 PvP 套装" },
    [819] = { category = "制造", source = "诺森德裁缝 PvP 套装" },
}

-- Retail transmog sets are presented as a base set plus variant sets.  Our
-- generated 3.3.5 ItemSet catalogue is intentionally flat, so this reviewed
-- UI-only table folds only the clear WotLK T9 Alliance/Horde counterparts.
-- The names below follow the current Wowhead/Retail transmog naming while
-- keeping the local zhCN ItemSet names visible to the player.
-- Do not use this table for ApplySet authority; the selected concrete record
-- remains the SC2 collection/action target.
local REVIEWED_SET_GROUP_VARIANTS = {
    [843] = { key = "wrath-t9-mage-regalia", groupName = "T9 · 卡德加/逐日者的法衣", variantLabel = "联盟", faction = "联盟", specLabel = "法师", role = "法衣", order = 1, sourceLabel = SET_SOURCE_T9 },
    [844] = { key = "wrath-t9-mage-regalia", groupName = "T9 · 卡德加/逐日者的法衣", variantLabel = "部落", faction = "部落", specLabel = "法师", role = "法衣", order = 2, sourceLabel = SET_SOURCE_T9 },
    [845] = { key = "wrath-t9-warlock-regalia", groupName = "T9 · 克尔苏加德/古尔丹的法衣", variantLabel = "部落", faction = "部落", specLabel = "术士", role = "法衣", order = 2, sourceLabel = SET_SOURCE_T9 },
    [846] = { key = "wrath-t9-warlock-regalia", groupName = "T9 · 克尔苏加德/古尔丹的法衣", variantLabel = "联盟", faction = "联盟", specLabel = "术士", role = "法衣", order = 1, sourceLabel = SET_SOURCE_T9 },
    [847] = { key = "wrath-t9-priest-healing", groupName = "T9 · 维伦/萨布拉的圣装", variantLabel = "联盟", faction = "联盟", specLabel = "神圣/戒律", role = "圣装", order = 1, sourceLabel = SET_SOURCE_T9 },
    [848] = { key = "wrath-t9-priest-healing", groupName = "T9 · 维伦/萨布拉的圣装", variantLabel = "部落", faction = "部落", specLabel = "神圣/戒律", role = "圣装", order = 2, sourceLabel = SET_SOURCE_T9 },
    [849] = { key = "wrath-t9-priest-caster", groupName = "T9 · 维伦/萨布拉的法衣", variantLabel = "联盟", faction = "联盟", specLabel = "暗影", role = "法衣", order = 1, sourceLabel = SET_SOURCE_T9 },
    [850] = { key = "wrath-t9-priest-caster", groupName = "T9 · 维伦/萨布拉的法衣", variantLabel = "部落", faction = "部落", specLabel = "暗影", role = "法衣", order = 2, sourceLabel = SET_SOURCE_T9 },
    [851] = { key = "wrath-t9-druid-healing", groupName = "T9 · 玛法里奥/伊哈缪尔的圣装", variantLabel = "联盟", faction = "联盟", specLabel = "恢复", role = "圣装", order = 1, sourceLabel = SET_SOURCE_T9 },
    [852] = { key = "wrath-t9-druid-healing", groupName = "T9 · 玛法里奥/伊哈缪尔的圣装", variantLabel = "部落", faction = "部落", specLabel = "恢复", role = "圣装", order = 2, sourceLabel = SET_SOURCE_T9 },
    [853] = { key = "wrath-t9-druid-caster", groupName = "T9 · 玛法里奥/伊哈缪尔的法衣", variantLabel = "联盟", faction = "联盟", specLabel = "平衡", role = "法衣", order = 1, sourceLabel = SET_SOURCE_T9 },
    [854] = { key = "wrath-t9-druid-caster", groupName = "T9 · 玛法里奥/伊哈缪尔的法衣", variantLabel = "部落", faction = "部落", specLabel = "平衡", role = "法衣", order = 2, sourceLabel = SET_SOURCE_T9 },
    [855] = { key = "wrath-t9-druid-feral", groupName = "T9 · 玛法里奥/伊哈缪尔的战甲", variantLabel = "联盟", faction = "联盟", specLabel = "野性", role = "战甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [856] = { key = "wrath-t9-druid-feral", groupName = "T9 · 玛法里奥/伊哈缪尔的战甲", variantLabel = "部落", faction = "部落", specLabel = "野性", role = "战甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [857] = { key = "wrath-t9-rogue-battlegear", groupName = "T9 · 范克里夫/迦罗娜的战甲", variantLabel = "联盟", faction = "联盟", specLabel = "潜行者", role = "战甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [858] = { key = "wrath-t9-rogue-battlegear", groupName = "T9 · 范克里夫/迦罗娜的战甲", variantLabel = "部落", faction = "部落", specLabel = "潜行者", role = "战甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [859] = { key = "wrath-t9-hunter-battlegear", groupName = "T9 · 风行者的战甲/猎装", variantLabel = "联盟", faction = "联盟", specLabel = "猎人", role = "猎装", order = 1, sourceLabel = SET_SOURCE_T9 },
    [860] = { key = "wrath-t9-hunter-battlegear", groupName = "T9 · 风行者的战甲/猎装", variantLabel = "部落", faction = "部落", specLabel = "猎人", role = "猎装", order = 2, sourceLabel = SET_SOURCE_T9 },
    [861] = { key = "wrath-t9-shaman-healing", groupName = "T9 · 努波顿/萨尔的圣装", variantLabel = "联盟", faction = "联盟", specLabel = "恢复", role = "圣装", order = 1, sourceLabel = SET_SOURCE_T9 },
    [862] = { key = "wrath-t9-shaman-healing", groupName = "T9 · 努波顿/萨尔的圣装", variantLabel = "部落", faction = "部落", specLabel = "恢复", role = "圣装", order = 2, sourceLabel = SET_SOURCE_T9 },
    [863] = { key = "wrath-t9-shaman-caster", groupName = "T9 · 努波顿/萨尔的法衣", variantLabel = "部落", faction = "部落", specLabel = "元素", role = "法衣", order = 2, sourceLabel = SET_SOURCE_T9 },
    [864] = { key = "wrath-t9-shaman-caster", groupName = "T9 · 努波顿/萨尔的法衣", variantLabel = "联盟", faction = "联盟", specLabel = "元素", role = "法衣", order = 1, sourceLabel = SET_SOURCE_T9 },
    [865] = { key = "wrath-t9-shaman-melee", groupName = "T9 · 努波顿/萨尔的战甲", variantLabel = "联盟", faction = "联盟", specLabel = "增强", role = "战甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [866] = { key = "wrath-t9-shaman-melee", groupName = "T9 · 努波顿/萨尔的战甲", variantLabel = "部落", faction = "部落", specLabel = "增强", role = "战甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [867] = { key = "wrath-t9-warrior-dps", groupName = "T9 · 乌瑞恩/地狱咆哮的战甲", variantLabel = "联盟", faction = "联盟", specLabel = "武器/狂怒", role = "战甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [868] = { key = "wrath-t9-warrior-dps", groupName = "T9 · 乌瑞恩/地狱咆哮的战甲", variantLabel = "部落", faction = "部落", specLabel = "武器/狂怒", role = "战甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [869] = { key = "wrath-t9-warrior-tank", groupName = "T9 · 乌瑞恩/地狱咆哮的铠甲", variantLabel = "联盟", faction = "联盟", specLabel = "防护", role = "铠甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [870] = { key = "wrath-t9-warrior-tank", groupName = "T9 · 乌瑞恩/地狱咆哮的铠甲", variantLabel = "部落", faction = "部落", specLabel = "防护", role = "铠甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [871] = { key = "wrath-t9-death-knight-dps", groupName = "T9 · 萨萨里安/库尔迪拉的战甲", variantLabel = "联盟", faction = "联盟", specLabel = "冰霜/邪恶", role = "战甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [872] = { key = "wrath-t9-death-knight-dps", groupName = "T9 · 萨萨里安/库尔迪拉的战甲", variantLabel = "部落", faction = "部落", specLabel = "冰霜/邪恶", role = "战甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [873] = { key = "wrath-t9-death-knight-tank", groupName = "T9 · 萨萨里安/库尔迪拉的铠甲", variantLabel = "联盟", faction = "联盟", specLabel = "鲜血", role = "铠甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [874] = { key = "wrath-t9-death-knight-tank", groupName = "T9 · 萨萨里安/库尔迪拉的铠甲", variantLabel = "部落", faction = "部落", specLabel = "鲜血", role = "铠甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [875] = { key = "wrath-t9-paladin-healing", groupName = "T9 · 图拉扬/莉亚德琳的圣装", variantLabel = "联盟", faction = "联盟", specLabel = "神圣", role = "圣装", order = 1, sourceLabel = SET_SOURCE_T9 },
    [876] = { key = "wrath-t9-paladin-healing", groupName = "T9 · 图拉扬/莉亚德琳的圣装", variantLabel = "部落", faction = "部落", specLabel = "神圣", role = "圣装", order = 2, sourceLabel = SET_SOURCE_T9 },
    [877] = { key = "wrath-t9-paladin-dps", groupName = "T9 · 图拉扬/莉亚德琳的战甲", variantLabel = "联盟", faction = "联盟", specLabel = "惩戒", role = "战甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [878] = { key = "wrath-t9-paladin-dps", groupName = "T9 · 图拉扬/莉亚德琳的战甲", variantLabel = "部落", faction = "部落", specLabel = "惩戒", role = "战甲", order = 2, sourceLabel = SET_SOURCE_T9 },
    [879] = { key = "wrath-t9-paladin-tank", groupName = "T9 · 图拉扬/莉亚德琳的铠甲", variantLabel = "联盟", faction = "联盟", specLabel = "防护", role = "铠甲", order = 1, sourceLabel = SET_SOURCE_T9 },
    [880] = { key = "wrath-t9-paladin-tank", groupName = "T9 · 图拉扬/莉亚德琳的铠甲", variantLabel = "部落", faction = "部落", specLabel = "防护", role = "铠甲", order = 2, sourceLabel = SET_SOURCE_T9 },
}

local REVIEWED_SET_DETAILS = {
    [883] = { displayName = "T10 · 血法战衣", specLabel = "法师", sourceLabel = SET_SOURCE_T10 },
    [884] = { displayName = "T10 · 黑巫法衣", specLabel = "术士", sourceLabel = SET_SOURCE_T10 },
    [885] = { displayName = "T10 · 血色侍僧战衣", specLabel = "暗影", sourceLabel = SET_SOURCE_T10 },
    [886] = { displayName = "T10 · 血色侍僧法衣", specLabel = "神圣/戒律", sourceLabel = SET_SOURCE_T10 },
    [887] = { displayName = "T10 · 树纹套装", specLabel = "恢复", sourceLabel = SET_SOURCE_T10 },
    [888] = { displayName = "T10 · 树纹法衣", specLabel = "平衡", sourceLabel = SET_SOURCE_T10 },
    [889] = { displayName = "T10 · 树纹战甲", specLabel = "野性", sourceLabel = SET_SOURCE_T10 },
    [890] = { displayName = "T10 · 影刃战甲", specLabel = "潜行者", sourceLabel = SET_SOURCE_T10 },
    [891] = { displayName = "T10 · 安卡哈猎血战甲", specLabel = "猎人", sourceLabel = SET_SOURCE_T10 },
    [892] = { displayName = "T10 · 霜巫套装", specLabel = "恢复", sourceLabel = SET_SOURCE_T10 },
    [893] = { displayName = "T10 · 霜巫战衣", specLabel = "元素", sourceLabel = SET_SOURCE_T10 },
    [894] = { displayName = "T10 · 霜巫战甲", specLabel = "增强", sourceLabel = SET_SOURCE_T10 },
    [895] = { displayName = "T10 · 伊米亚之王战甲", specLabel = "武器/狂怒", sourceLabel = SET_SOURCE_T10 },
    [896] = { displayName = "T10 · 伊米亚之王战铠", specLabel = "防护", sourceLabel = SET_SOURCE_T10 },
    [897] = { displayName = "T10 · 天灾领主战甲", specLabel = "冰霜/邪恶", sourceLabel = SET_SOURCE_T10 },
    [898] = { displayName = "T10 · 天灾领主战铠", specLabel = "鲜血", sourceLabel = SET_SOURCE_T10 },
    [899] = { displayName = "T10 · 光誓套装", specLabel = "神圣", sourceLabel = SET_SOURCE_T10 },
    [900] = { displayName = "T10 · 光誓战甲", specLabel = "惩戒", sourceLabel = SET_SOURCE_T10 },
    [901] = { displayName = "T10 · 光誓战铠", specLabel = "防护", sourceLabel = SET_SOURCE_T10 },
}

for itemSetId, info in pairs(REVIEWED_SET_GROUP_VARIANTS) do
    REVIEWED_SET_DETAILS[itemSetId] = info
end

local function setRecordSelectionKey(record)
    if not record then return nil end
    if record.scIsSetGroup and record.scSetGroupKey then
        return record.scSetGroupKey
    end
    return "set:" .. tostring(record.id or record.itemSetId or "unknown")
end

local function concreteSetRecord(record)
    if record and record.scIsSetGroup then
        return record.scSelectedVariantRecord or (record.scVariants and record.scVariants[1])
    end
    return record
end

local function reviewedSetInfo(record)
    record = concreteSetRecord(record)
    return REVIEWED_SET_DETAILS[tonumber(record and record.itemSetId) or 0]
end

local function nonClassSetInfo(record)
    record = concreteSetRecord(record)
    return NON_CLASS_SET_DETAILS[tonumber(record and record.itemSetId) or 0]
end

local function setRecordIsClassSpecific(record)
    record = concreteSetRecord(record)
    local policy = effectiveSetClassPolicy(record)
    return policy and policy.mode == "ALLOW_LIST" and #(policy.allowedClassKeys or {}) > 0
end

local function setRecordCategoryLabel(record)
    local info = nonClassSetInfo(record)
    if info and info.category and info.category ~= "" then
        return info.category
    end

    local presentation = record and record.presentation
    local displayLabel = presentation and presentation.displayLabel
    if displayLabel == "D3" then return "地下城" end
    if displayLabel and string.find(displayLabel, "PvP", 1, true) then return "PvP" end
    if presentation and presentation.acquisition == "PVP" then return "PvP" end
    if not setRecordIsClassSpecific(record) then return "通用" end
    return nil
end

local function setDisplayName(record)
    if not record then return "未知套装" end
    if record.scIsSetGroup and record.scGroupName and record.scGroupName ~= "" then
        return record.scGroupName
    end
    local info = reviewedSetInfo(record)
    if info and info.displayName and info.displayName ~= "" then
        return info.displayName
    end
    local name = record.name or "未知套装"
    local presentationLabel = setPresentationLabel(record)
    if presentationLabel and presentationLabel ~= "" and not string.find(name, presentationLabel, 1, true) then
        return presentationLabel .. " · " .. name
    end
    return name
end

local function setVariantLabel(record)
    local info = reviewedSetInfo(record)
    if info and info.variantLabel and info.variantLabel ~= "" then
        return info.variantLabel
    end
    return tostring(record and record.name or "未知版本")
end

local SPEC_SPLIT_CLASSES = {
    death_knight = true,
    druid = true,
    paladin = true,
    priest = true,
    shaman = true,
    warrior = true,
}

local function setRecordPrimaryClassKey(record)
    record = concreteSetRecord(record)
    local policy = effectiveSetClassPolicy(record)
    if policy and policy.mode == "ALLOW_LIST" and #(policy.allowedClassKeys or {}) == 1 then
        return policy.allowedClassKeys[1]
    end
    return record and record.classToken
end

local function recordNameHas(recordName, token)
    return recordName and token and token ~= "" and string.find(recordName, token, 1, true)
end

local function inferredSetSpecLabel(record)
    record = concreteSetRecord(record)
    local classKey = setRecordPrimaryClassKey(record)
    if not SPEC_SPLIT_CLASSES[classKey or ""] then
        return nil
    end

    local name = record and record.name or ""
    if classKey == "death_knight" then
        if recordNameHas(name, "铠甲") or recordNameHas(name, "战铠") or recordNameHas(name, "板甲") then
            return "鲜血"
        end
        if recordNameHas(name, "战甲") then
            return "冰霜/邪恶"
        end
    elseif classKey == "warrior" then
        if recordNameHas(name, "铠甲") or recordNameHas(name, "战铠") or recordNameHas(name, "板甲") or
            recordNameHas(name, "护甲") or recordNameHas(name, "保护") or recordNameHas(name, "壁垒") then
            return "防护"
        end
        if recordNameHas(name, "战甲") then
            return "武器/狂怒"
        end
    elseif classKey == "paladin" then
        if recordNameHas(name, "圣装") or recordNameHas(name, "圣服") or recordNameHas(name, "圣甲") or
            recordNameHas(name, "救赎") or recordNameHas(name, "魔装") or recordNameHas(name, "雕饰") then
            return "神圣"
        end
        if recordNameHas(name, "铠甲") or recordNameHas(name, "战铠") or recordNameHas(name, "板甲") or
            recordNameHas(name, "护甲") or recordNameHas(name, "保护") or recordNameHas(name, "壁垒") then
            return "防护"
        end
        if recordNameHas(name, "战甲") or recordNameHas(name, "辩护") or recordNameHas(name, "板鳞甲") then
            return "惩戒"
        end
    elseif classKey == "priest" then
        if recordNameHas(name, "法衣") or recordNameHas(name, "战衣") then
            return "暗影"
        end
        if recordNameHas(name, "圣装") or recordNameHas(name, "套装") or recordNameHas(name, "神服") or
            recordNameHas(name, "魔装") or
            recordNameHas(name, "月布") or recordNameHas(name, "绸缎") or recordNameHas(name, "天职") then
            return "神圣/戒律"
        end
    elseif classKey == "druid" then
        if recordNameHas(name, "法衣") or recordNameHas(name, "蟒皮") then
            return "平衡"
        end
        if recordNameHas(name, "战甲") or recordNameHas(name, "甲胄") or recordNameHas(name, "野性之皮") or
            recordNameHas(name, "野性") or recordNameHas(name, "龙皮") then
            return "野性"
        end
        if recordNameHas(name, "圣装") or recordNameHas(name, "圣服") or recordNameHas(name, "套装") or
            recordNameHas(name, "魔装") or recordNameHas(name, "庇护") or recordNameHas(name, "科多皮") then
            return "恢复"
        end
    elseif classKey == "shaman" then
        if recordNameHas(name, "法衣") or recordNameHas(name, "震撼") or
            recordNameHas(name, "雷霆之拳") or recordNameHas(name, "环甲") then
            return "元素"
        end
        if recordNameHas(name, "战甲") or recordNameHas(name, "甲胄") or recordNameHas(name, "锁甲") then
            return "增强"
        end
        if recordNameHas(name, "圣装") or recordNameHas(name, "套装") or recordNameHas(name, "圣服") or
            recordNameHas(name, "魔装") or recordNameHas(name, "战争之潮") or recordNameHas(name, "鳞甲") then
            return "恢复"
        end
    end
    return nil
end

local function setRecordSpecLabel(record)
    local info = reviewedSetInfo(record)
    if info and info.specLabel and info.specLabel ~= "" and SPEC_SPLIT_CLASSES[setRecordPrimaryClassKey(record) or ""] then
        return info.specLabel
    end
    return inferredSetSpecLabel(record)
end

local function setRecordFactionLabel(record)
    local info = reviewedSetInfo(record)
    if info and info.faction and info.faction ~= "" then
        return info.faction
    end
    return nil
end

local function setRecordSourceLabel(record)
    local info = reviewedSetInfo(record)
    if info and info.sourceLabel and info.sourceLabel ~= "" then
        return info.sourceLabel
    end
    local nonClassInfo = nonClassSetInfo(record)
    if nonClassInfo and nonClassInfo.source and nonClassInfo.source ~= "" then
        return nonClassInfo.source
    end
    local presentation = record and record.presentation
    local tier = presentation and presentation.raidTier
    local season = presentation and presentation.pvpSeason
    local displayLabel = presentation and presentation.displayLabel
    if tier == "T7" then return SET_SOURCE_T7 end
    if tier == "T8" then return SET_SOURCE_T8 end
    if tier == "T9" then return SET_SOURCE_T9 end
    if tier == "T10" then return SET_SOURCE_T10 end
    if tier and SET_SOURCE_BY_LABEL[tier] then return SET_SOURCE_BY_LABEL[tier] end
    if displayLabel and SET_SOURCE_BY_LABEL[displayLabel] then return SET_SOURCE_BY_LABEL[displayLabel] end
    if season and season ~= "" and season ~= "NONE" then return SET_SOURCE_PVP end
    if displayLabel and string.find(displayLabel, "PvP", 1, true) then return SET_SOURCE_PVP end
    if presentation and presentation.acquisition == "PVP" then return SET_SOURCE_PVP end
    return "来源未整理：按套装出处继续补齐"
end

local function setRecordCompletionRank(record)
    local owned = tonumber(record and record.collectedCount) or 0
    local required = tonumber(record and record.requiredCount) or 0
    if required <= 0 then return owned, required, 0 end
    return owned, required, owned / required
end

local function chooseSetGroupVariant(group, rememberedId)
    local variants = group and group.scVariants or {}
    local remembered = tonumber(rememberedId)
    if remembered then
        for _, variant in ipairs(variants) do
            if tonumber(variant.id) == remembered then
                return variant
            end
        end
    end
    local best
    local bestOwned, bestRequired, bestRatio = -1, 0, -1
    for _, variant in ipairs(variants) do
        local owned, required, ratio = setRecordCompletionRank(variant)
        if not best or variant.collected or ratio > bestRatio or
            (ratio == bestRatio and owned > bestOwned) or
            (ratio == bestRatio and owned == bestOwned and required > bestRequired) then
            best = variant
            bestOwned = owned
            bestRequired = required
            bestRatio = ratio
        end
        if variant.collected then
            break
        end
    end
    return best or variants[1]
end

local function updateSetGroupSummary(group, selectedVariant)
    local variants = group and group.scVariants or {}
    if #variants == 0 then return group end
    table.sort(variants, function(left, right)
        local leftInfo = REVIEWED_SET_GROUP_VARIANTS[tonumber(left.itemSetId) or 0] or {}
        local rightInfo = REVIEWED_SET_GROUP_VARIANTS[tonumber(right.itemSetId) or 0] or {}
        if (leftInfo.order or 99) ~= (rightInfo.order or 99) then
            return (leftInfo.order or 99) < (rightInfo.order or 99)
        end
        return (tonumber(left.itemSetId) or 0) < (tonumber(right.itemSetId) or 0)
    end)

    selectedVariant = selectedVariant or chooseSetGroupVariant(group)
    group.scSelectedVariantRecord = selectedVariant
    group.id = selectedVariant.id
    group.itemSetId = selectedVariant.itemSetId
    group.icon = selectedVariant.icon
    group.iconItemId = selectedVariant.iconItemId
    group.classPolicy = selectedVariant.classPolicy
    group.presentation = selectedVariant.presentation
    group.favorite = selectedVariant.favorite
    local selectedInfo = reviewedSetInfo(selectedVariant)
    group.scVariantLabel = selectedInfo and selectedInfo.variantLabel
    group.scFactionLabel = selectedInfo and selectedInfo.faction
    group.scSpecLabel = selectedInfo and selectedInfo.specLabel

    local topOwned, topRequired, topRatio = 0, 0, -1
    local anyCollected = false
    for _, variant in ipairs(variants) do
        local owned, required, ratio = setRecordCompletionRank(variant)
        if variant.collected then anyCollected = true end
        if ratio > topRatio or (ratio == topRatio and owned > topOwned) then
            topOwned, topRequired, topRatio = owned, required, ratio
        end
    end
    group.collectedCount = topOwned
    group.requiredCount = topRequired
    group.collected = anyCollected or (topRequired > 0 and topOwned == topRequired)

    group.name = setDisplayName(group)
    return group
end

local function buildSetDisplayRecords(records, rememberedVariants)
    local displayRecords = {}
    local groups = {}
    for _, record in ipairs(records or {}) do
        local groupInfo = REVIEWED_SET_GROUP_VARIANTS[tonumber(record.itemSetId) or 0]
        if groupInfo then
            local groupKey = "reviewed:" .. groupInfo.key
            local group = groups[groupKey]
            if not group then
                group = {
                    scIsSetGroup = true,
                    scSetGroupKey = groupKey,
                    scGroupName = groupInfo.groupName,
                    scRoleLabel = groupInfo.role,
                    scSourceLabel = groupInfo.sourceLabel,
                    scVariants = {},
                }
                groups[groupKey] = group
                displayRecords[#displayRecords + 1] = group
            end
            record.scSetGroupKey = groupKey
            record.scVariantOrder = groupInfo.order
            group.scVariants[#group.scVariants + 1] = record
        else
            record.scSetGroupKey = "set:" .. tostring(record.id or record.itemSetId or #displayRecords + 1)
            displayRecords[#displayRecords + 1] = record
        end
    end
    for _, record in ipairs(displayRecords) do
        if record.scIsSetGroup then
            local rememberedId = rememberedVariants and rememberedVariants[record.scSetGroupKey]
            updateSetGroupSummary(record, chooseSetGroupVariant(record, rememberedId))
        end
    end
    return displayRecords
end

local function setVariantDropdownText(record)
    local owned = tonumber(record and record.collectedCount) or 0
    local required = tonumber(record and record.requiredCount) or 0
    return setVariantLabel(record) .. "  " .. owned .. "/" .. required
end

local function hasFilterValue(options, current)
    for _, option in ipairs(options) do
        if option.key == current then
            return true
        end
    end
    return false
end

local function setAtlasRegion(texture, texturePath, atlasWidth, atlasHeight, region)
    texture:SetTexture(texturePath)
    texture:SetTexCoord(
        region[1] / atlasWidth,
        region[2] / atlasWidth,
        region[3] / atlasHeight,
        region[4] / atlasHeight
    )
end

local function getPlayerClassToken()
    local classIdentity = Identity.GetPlayerClass()
    return classIdentity.known and classIdentity.filterToken or nil
end

local function weaponOptionSupportsSlot(option, slot)
    return (slot == "MAINHAND" and option.main) or (slot == "OFFHAND" and option.off)
end

local function getAvailableWeaponFilters(slot)
    local result = {}
    local allowed = Identity.GetWeaponTypes(slot)
    for _, option in ipairs(WEAPON_FILTERS) do
        if weaponOptionSupportsSlot(option, slot) and allowed[option.key] then
            table.insert(result, option)
        end
    end
    return result
end

local function ensureWeaponTypeForSlot(filters, slot)
    local options = getAvailableWeaponFilters(slot)
    for _, option in ipairs(options) do
        if filters.weaponType == option.key then
            return option.key
        end
    end
    filters.weaponType = options[1] and options[1].key or "AUTO"
    return filters.weaponType
end

local function showItemTooltip(owner, record)
    if not record or not record.itemId then
        return
    end
    local itemName, itemLink = GetItemInfo(record.itemId)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        GameTooltip:SetText(itemName or record.name or "未知外观", 1, 0.82, 0.18)
    end
    if record.source then
        GameTooltip:AddLine("来源：" .. record.source, 0.94, 0.82, 0.58, true)
    end
    if record.weaponTypeLabel then
        GameTooltip:AddLine("武器类型：" .. record.weaponTypeLabel, 0.52, 0.82, 1.00, true)
    end
    GameTooltip:AddLine(record.collected and "已收集" or "未收集 · 仍可预览", record.collected and 0.38 or 0.62, record.collected and 0.90 or 0.58, 0.32)
    if record.collected then
        GameTooltip:AddLine("Shift + 左键：应用到当前装备", 1.00, 0.82, 0.18)
    end
    GameTooltip:Show()
end

local function itemQualityColor(quality)
    if quality and GetItemQualityColor then
        local red, green, blue = GetItemQualityColor(quality)
        return red or 1.00, green or 0.82, blue or 0.18
    end
    return 1.00, 0.82, 0.18
end

local function setRecordQuality(record)
    record = concreteSetRecord(record)
    local quality = record and record.presentation and record.presentation.quality
    local reviewed = tonumber(quality and (quality.median or quality.max or quality.min))
    if reviewed then return reviewed end
    local _, _, itemQuality = GetItemInfo(record and record.iconItemId)
    return itemQuality
end

local function setRecordQualityColor(record)
    return itemQualityColor(setRecordQuality(record) or 4)
end

local function compactSetRowMetadata(record)
    record = concreteSetRecord(record)
    local parts = { setRecordIsClassSpecific(record) and setClassLabel(record) or setRecordCategoryLabel(record) }
    local specLabel = setRecordSpecLabel(record)
    if specLabel and specLabel ~= "" then
        parts[#parts + 1] = specLabel
    end
    return table.concat(parts, "  ·  ")
end

local function showPieceTooltip(owner, itemId, setRecord, previewItem, displayRecord)
    if not itemId then return end
    local itemName, _, quality = GetItemInfo(itemId)
    quality = quality or (owner and owner.scQuality) or 4
    local red, green, blue = itemQualityColor(quality)
    setRecord = setRecord or (owner and owner.scSetRecord)
    displayRecord = displayRecord or (owner and owner.scSetDisplayRecord) or setRecord
    previewItem = previewItem or (owner and owner.scPreviewItem)
    local sourceItemIds = previewItem and previewItem.sourceItemIds or (owner and owner.scSourceItemIds)
    local sourceCount = sourceItemIds and #sourceItemIds or 0

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(itemName or ("套装部件 #" .. tostring(itemId)), red, green, blue)
    GameTooltip:AddLine("套装：" .. setDisplayName(displayRecord), 0.95, 0.82, 0.36, true)

    local slotLabel = slotLabelFromKey(previewItem and previewItem.slotKey or (owner and owner.scSlotKey))
    if slotLabel and slotLabel ~= "" then
        GameTooltip:AddLine("部位：" .. slotLabel, 0.82, 0.78, 0.70)
    end

    local factionLabel = setRecordFactionLabel(setRecord)
    if factionLabel then
        GameTooltip:AddLine("阵营：" .. factionLabel, 0.65, 0.78, 0.92)
    end

    local categoryLabel = setRecordCategoryLabel(setRecord)
    if categoryLabel and not setRecordIsClassSpecific(setRecord) then
        GameTooltip:AddLine("类型：" .. categoryLabel, 0.82, 0.78, 0.70)
    end

    local specLabel = setRecordSpecLabel(setRecord)
    if specLabel then
        GameTooltip:AddLine("适用专精：" .. specLabel, 0.52, 0.82, 1.00, true)
    end

    local sourceLabel = setRecordSourceLabel(setRecord)
    if sourceLabel then
        GameTooltip:AddLine("来源：" .. sourceLabel, 0.94, 0.82, 0.58, true)
    end

    local collected = owner and owner.scCollected
    GameTooltip:AddLine(collected and "已收集外观" or "未收集 · 仍可预览", collected and 0.38 or 0.62, collected and 0.90 or 0.58, 0.32)
    if sourceCount > 1 then
        GameTooltip:AddLine("Alt + 左键：切换同部位来源（" .. tostring(sourceCount) .. " 个）", 1.00, 0.82, 0.18)
    end
    GameTooltip:Show()
end

local function resolveTryOnItem(itemId)
    local _, itemLink = GetItemInfo(itemId)
    return itemLink or ("item:" .. itemId)
end

-- Keep the Sets tab in its original list/detail shape. The item tab can use
-- ezCollections model cards, but sets read better as named rows with one large
-- preview and the piece strip.
local function createSetListRow(parent, width, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(width or 330)
    row:SetHeight(SET_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetAllPoints(row)
    background:SetVertexColor(0.018, 0.016, 0.014, 0.78)

    local selected = row:CreateTexture(nil, "BORDER")
    selected:SetTexture("Interface\\Buttons\\WHITE8X8")
    selected:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    selected:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    selected:SetGradientAlpha("HORIZONTAL", 0.46, 0.22, 0.045, 0.72, 0.17, 0.075, 0.02, 0.34)
    selected:Hide()

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    hover:SetGradientAlpha("HORIZONTAL", 0.72, 0.48, 0.13, 0.24, 0.42, 0.24, 0.06, 0.08)
    row:SetHighlightTexture(hover)

    local separator = row:CreateTexture(nil, "BORDER")
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
    separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
    separator:SetHeight(1)
    separator:SetVertexColor(0.34, 0.29, 0.22, 0.34)

    local iconHolder = CreateFrame("Frame", nil, row)
    iconHolder:SetWidth(42)
    iconHolder:SetHeight(42)
    iconHolder:SetPoint("LEFT", row, "LEFT", 5, 0)
    iconHolder:SetFrameLevel(row:GetFrameLevel() + 1)

    local iconBackground = iconHolder:CreateTexture(nil, "BACKGROUND")
    iconBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconBackground:SetAllPoints(iconHolder)
    iconBackground:SetVertexColor(0.018, 0.021, 0.024, 0.92)

    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -2, 2)
    UI.SetFallbackTexture(icon)

    local glass = iconHolder:CreateTexture(nil, "OVERLAY")
    glass:SetTexture("Interface\\Buttons\\WHITE8X8")
    glass:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 2, -2)
    glass:SetPoint("TOPRIGHT", iconHolder, "TOPRIGHT", -2, -2)
    glass:SetHeight(17)
    glass:SetGradientAlpha("VERTICAL", 0.80, 0.88, 0.94, 0.02, 0.92, 0.96, 1.00, 0.18)

    local iconBorder = UI.CreateThinCardBorder(iconHolder, 1)
    iconBorder:SetBorderColor(0.44, 0.46, 0.48, 0.92)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 10, -5)
    name:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    name:SetJustifyH("LEFT")
    name:SetTextColor(0.93, 0.77, 0.26)

    local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMRIGHT", 10, 5)
    detail:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(0.49, 0.48, 0.46)

    local star = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    star:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    star:SetText("★")
    star:SetTextColor(1.00, 0.82, 0.18)
    star:Hide()

    row:SetScript("OnClick", function(self, button)
        if onClick and self.scRecord then
            onClick(self, self.scRecord, button)
        end
    end)

    function row:SetRecord(record)
        self.scRecord = record
        if not record then
            selected:Hide()
            star:Hide()
            name:SetText("")
            detail:SetText("")
            self:Hide()
            return
        end

        local concreteRecord = concreteSetRecord(record)
        UI.SetIconTexture(icon, record.icon or (record.iconItemId and GetItemIcon(record.iconItemId)) or
            (concreteRecord and concreteRecord.iconItemId and GetItemIcon(concreteRecord.iconItemId)))
        UI.SetCollectedVisual(icon, record.collected, 0.52)
        name:SetText(setDisplayName(record))
        name:SetTextColor(record.collected and 0.96 or 0.59, record.collected and 0.79 or 0.59, record.collected and 0.28 or 0.57)
        local owned = tonumber(record.collectedCount) or 0
        local required = tonumber(record.requiredCount) or #(record.itemIds or {})
        if record.scIsSetGroup then
            local variantCount = record.scVariants and #record.scVariants or 0
            detail:SetText(compactSetRowMetadata(record) .. "  ·  " .. tostring(variantCount) .. " 阵营  ·  " .. owned .. "/" .. required)
        else
            detail:SetText(compactSetRowMetadata(record) .. "  ·  " .. owned .. "/" .. required)
        end
        if record.collected then
            iconBorder:SetBorderColor(0.66, 0.52, 0.24, 0.96)
        else
            iconBorder:SetBorderColor(0.39, 0.41, 0.43, 0.86)
        end
        if record.favorite then star:Show() else star:Hide() end
        self:Show()
    end

    function row:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then selected:Show() else selected:Hide() end
    end

    row.scIcon = icon
    row.scIconBorder = iconBorder
    row.scName = name
    row.scDetail = detail
    row.scStar = star
    return row
end


local function applyItemModelRecord(model, record, pageGeneration, force)
    pageGeneration = pageGeneration or ((model.scItemGeneration or 0) + 1)
    return EzModel:Present(model, record, pageGeneration, force)
end

SC.WardrobeUI.ItemCardRenderer = SC.WardrobeUI.ItemCardRenderer or {}
local ItemCardRenderer = SC.WardrobeUI.ItemCardRenderer

function ItemCardRenderer:Attach(model, objectModel)
    if model.scWardrobeItemCardRenderer then return end
    model.scWardrobeItemCardRenderer = true
    EzModel:Attach(model, objectModel)
end

function ItemCardRenderer:Present(model, record, generation)
    return applyItemModelRecord(model, record, generation)
end

function ItemCardRenderer:Clear(model, generation)
    return applyItemModelRecord(model, nil, generation)
end

function UI.CreateWardrobePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page:Hide()
    page.scItemPage = 1
    page.scSetPage = 1
    page.scSetOffset = 0
    page.scSetRecordCount = 0
    page.scSetPreviewGeneration = 0
    page.scDefaultSetClassApplied = false
    page.scItemModels = {}
    page.scItemPageSize = ITEM_PAGE_SIZE
    page.scSetRows = {}
    page.scPieceIcons = {}
    page.scSelectedSetVariantByGroup = {}
    page.scSetPieceAltSourceByMember = {}
    local setSetOffset
    local selectSetDisplayRecord
    local previewSet
    local itemDataProvider = SC.EzWardrobe.DataProvider:Create(page)
    local wardrobeFilters = SC.WardrobeUI.Filters:Create(page, Catalog, itemDataProvider)
    local filterBar = CreateFrame("Frame", nil, page)
    filterBar:SetHeight(78)
    filterBar:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
    filterBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -60)
    filterBar:SetFrameLevel(page:GetFrameLevel() + 8)

    local armorDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeArmorDropdown", filterBar, "UIDropDownMenuTemplate")
    armorDropdown:SetPoint("TOPLEFT", filterBar, "TOPLEFT", -12, -6)
    UIDropDownMenu_SetWidth(armorDropdown, 148)

    -- Sets remain class-owned data in 3.3.5. Retail places this selector above
    -- the preview side, so it deliberately does not reuse the item filter's
    -- upper-left position.
    local classDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeClassDropdown", filterBar, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", 12, -6)
    UIDropDownMenu_SetWidth(classDropdown, 148)

    local slotsFrame = CreateFrame("Frame", nil, filterBar)
    slotsFrame:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 181, -20)
    slotsFrame:SetWidth(430)
    slotsFrame:SetHeight(42)
    page.scSlotButtons = {}

    local weaponDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeWeaponDropdown", filterBar, "UIDropDownMenuTemplate")
    weaponDropdown:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", 12, -40)
    UIDropDownMenu_SetWidth(weaponDropdown, 164)
    weaponDropdown:Hide()

    local function chooseDedicatedFilter(key, value)
        if not SC.db or not SC.db.filters then return end
        wardrobeFilters:Set(key, value)
        if key == "slot" and STANDALONE_ITEM_SLOTS[value] then
            ensureWeaponTypeForSlot(SC.db.filters, value)
        end
        page.scItemSelectedId = nil
        page.scSetSelectedId = nil
        page.scSetSelectedGroupKey = nil
        page.scItemPage = 1
        setSetOffset(0, true)
        page:Refresh()
    end

    UIDropDownMenu_Initialize(armorDropdown, function()
        for _, option in ipairs(ARMOR_TYPE_FILTERS) do
            local armorOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = armorOption.label
            info.value = armorOption.key
            info.checked = SC.db and SC.db.filters.armorType == armorOption.key
            info.func = function()
                chooseDedicatedFilter("armorType", armorOption.key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(classDropdown, function()
        for _, option in ipairs(CLASS_FILTERS) do
            local classOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = classOption.label
            info.value = classOption.key
            info.checked = SC.db and SC.db.filters.classToken == classOption.key
            info.func = function()
                chooseDedicatedFilter("classToken", classOption.key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(weaponDropdown, function()
        if not SC.db or not SC.db.filters then return end
        for _, option in ipairs(getAvailableWeaponFilters(SC.db.filters.slot)) do
            local weaponOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = weaponOption.label
            info.value = weaponOption.key
            info.checked = SC.db.filters.weaponType == weaponOption.key
            info.func = function()
                chooseDedicatedFilter("weaponType", weaponOption.key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local xOffset = 0
    for _, option in ipairs(SLOT_FILTERS) do
        local slotOption = option
        local button = CreateFrame("Button", nil, slotsFrame)
        button:SetWidth(31)
        button:SetHeight(31)
        button:SetPoint("TOPLEFT", slotsFrame, "TOPLEFT", xOffset, 0)

        local normal = button:CreateTexture(nil, "ARTWORK")
        normal:SetWidth(35)
        normal:SetHeight(37)
        normal:SetPoint("CENTER", button, "CENTER", 0, 0)
        setAtlasRegion(
            normal,
            UI.EzCollections:MediaPath("Transmogrify", "Transmogrify.tga", UI.Media.wardrobeSlotAtlas),
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_REGIONS[slotOption.atlas]
        )
        button:SetNormalTexture(normal)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetWidth(31)
        highlight:SetHeight(31)
        highlight:SetPoint("CENTER", button, "CENTER", 0, 1)
        highlight:SetBlendMode("ADD")
        setAtlasRegion(
            highlight,
            UI.EzCollections:AssetPath("Interface\\ContainerFrame\\Bags.tga", UI.Media.roundHighlightAtlas),
            ROUND_HIGHLIGHT_SIZE[1],
            ROUND_HIGHLIGHT_SIZE[2],
            ROUND_HIGHLIGHT_REGION
        )
        button:SetHighlightTexture(highlight)

        local selected = button:CreateTexture(nil, "OVERLAY")
        selected:SetWidth(45)
        selected:SetHeight(47)
        selected:SetPoint("CENTER", button, "CENTER", 0, 0)
        setAtlasRegion(
            selected,
            UI.EzCollections:MediaPath("Transmogrify", "Transmogrify.tga", UI.Media.wardrobeSlotAtlas),
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_SIZE,
            SLOT_ATLAS_REGIONS.selected
        )
        selected:Hide()

        button:SetScript("OnClick", function()
            chooseDedicatedFilter("slot", slotOption.key)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slotOption.label, 1.00, 0.82, 0.18)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button.scSlot = slotOption.key
        button.scSelected = selected
        page.scSlotButtons[slotOption.key] = button
        xOffset = xOffset + 33 + (slotOption.gapAfter or 0)
    end

    local itemsPanel, itemsInset = EzItems:CreatePanel(page)

    local setsPanel = CreateFrame("Frame", nil, page)
    setsPanel:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -60)
    setsPanel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 5)
    setsPanel:SetWidth(350)
    local setsInset = UI.EzCollections:ApplyInset(setsPanel)
    UI.EzCollections:AddShadowOverlay(setsPanel)
    SC.WardrobeUI.Layout:StylePanel(setsPanel, setsInset.background)
    setsPanel:Hide()

    local preview = CreateFrame("Frame", nil, page)
    preview:SetPoint("TOPLEFT", setsPanel, "TOPRIGHT", 10, 0)
    preview:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 5)
    preview:SetFrameLevel(setsPanel:GetFrameLevel() + 2)
    local previewInset = UI.EzCollections:ApplyInset(preview)
    UI.EzCollections:AddShadowOverlay(preview)
    SC.WardrobeUI.Layout:StylePanel(preview, previewInset.background)
    preview:Hide()

    local model = CreateFrame("DressUpModel", nil, preview)
    model:SetPoint("TOPLEFT", preview, "TOPLEFT", 9, SET_DETAILS_MODEL_TOP_Y)
    model:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -9, 76)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    local setPresenter = SC.WardrobeUI.ItemPresenter:AttachSet(model, function()
        return page:IsShown() and SC.db and SC.db.wardrobeTab == "SETS"
    end)

    local name = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOP", preview, "TOP", 0, SET_DETAILS_NAME_Y)
    name:SetWidth(380)
    name:SetJustifyH("CENTER")
    name:SetTextColor(1, 0.82, 0.18)

    local longName = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    longName:SetPoint("TOP", preview, "TOP", 0, SET_DETAILS_LONG_NAME_Y)
    longName:SetWidth(380)
    longName:SetJustifyH("CENTER")
    longName:SetTextColor(1, 0.82, 0.18)
    longName:Hide()

    local detail = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("TOP", preview, "TOP", 0, SET_DETAILS_LABEL_Y)
    detail:SetWidth(380)
    detail:SetJustifyH("CENTER")
    detail:SetTextColor(0.82, 0.75, 0.62)

    local setProgress = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setProgress:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 16, 18)
    setProgress:SetTextColor(0.45, 0.90, 0.34)
    setProgress:Hide()
    page.scSetProgress = setProgress

    local reset = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
    reset:SetWidth(104)
    reset:SetHeight(25)
    reset:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -14, 13)
    reset:SetText("重置视角")

    local applySet = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
    applySet:SetWidth(104)
    applySet:SetHeight(25)
    applySet:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    applySet:SetText("应用套装")
    applySet:Disable()
    page.scApplySet = applySet

    local variantDropdown = CreateFrame("Frame", "SoloCollectionsWardrobeSetVariantDropdown", preview, "UIDropDownMenuTemplate")
    variantDropdown:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", 12, 42)
    UIDropDownMenu_SetWidth(variantDropdown, 72)
    variantDropdown:Hide()
    page.scSetVariantDropdown = variantDropdown

    UIDropDownMenu_Initialize(variantDropdown, function()
        local groupRecord = variantDropdown.scSetGroupRecord
        if not (groupRecord and groupRecord.scVariants) then return end
        for _, variantRecord in ipairs(groupRecord.scVariants) do
            local optionRecord = variantRecord
            local info = UIDropDownMenu_CreateInfo()
            info.text = setVariantDropdownText(optionRecord)
            info.value = optionRecord.id
            info.checked = groupRecord.scSelectedVariantRecord and groupRecord.scSelectedVariantRecord.id == optionRecord.id
            info.func = function()
                groupRecord.scSelectedVariantRecord = optionRecord
                updateSetGroupSummary(groupRecord, optionRecord)
                if page.scSelectedSetVariantByGroup then
                    page.scSelectedSetVariantByGroup[groupRecord.scSetGroupKey] = optionRecord.id
                end
                if selectSetDisplayRecord then
                    selectSetDisplayRecord(groupRecord)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local pieces = CreateFrame("Frame", nil, preview)
    pieces:SetPoint("TOP", preview, "TOP", 0, SET_DETAILS_ICON_ROW_Y)
    -- The production catalogue currently tops out at eight pieces, but the
    -- preview contract must also cover nine-piece variants (and leave room for
    -- a reviewed future set) without rebuilding UI frames after the catalog
    -- has already loaded.  Keep the fixed pool bounded by the existing
    -- twelve-piece safety limit instead of sizing it from today's data.
    local piecePoolSize = SET_PIECE_POOL_LIMIT
    local poolColumns = math.min(SET_PIECE_COLUMNS, piecePoolSize)
    local poolRows = math.ceil(piecePoolSize / SET_PIECE_COLUMNS)
    pieces:SetWidth((poolColumns * SET_PIECE_SIZE) + (math.max(0, poolColumns - 1) * SET_PIECE_SPACING))
    pieces:SetHeight((poolRows * SET_PIECE_SIZE) + (math.max(0, poolRows - 1) * SET_PIECE_SPACING))
    pieces:Hide()
    for index = 1, piecePoolSize do
        local piece = CreateFrame("Button", nil, pieces)
        piece:SetWidth(SET_PIECE_SIZE)
        piece:SetHeight(SET_PIECE_SIZE)
        piece:RegisterForClicks("LeftButtonUp")
        if index == 1 then
            piece:SetPoint("TOPLEFT", pieces, "TOPLEFT", 0, 0)
        elseif (index - 1) % SET_PIECE_COLUMNS == 0 then
            piece:SetPoint("TOPLEFT", page.scPieceIcons[index - SET_PIECE_COLUMNS], "BOTTOMLEFT", 0, -SET_PIECE_SPACING)
        else
            piece:SetPoint("LEFT", page.scPieceIcons[index - 1], "RIGHT", SET_PIECE_SPACING, 0)
        end

        local iconBackground = piece:CreateTexture(nil, "BACKGROUND")
        iconBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        iconBackground:SetAllPoints(piece)
        iconBackground:SetVertexColor(0.012, 0.014, 0.018, 0.94)

        local icon = piece:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", piece, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", piece, "BOTTOMRIGHT", -2, 2)
        UI.SetFallbackTexture(icon)

        local glass = piece:CreateTexture(nil, "OVERLAY")
        glass:SetTexture("Interface\\Buttons\\WHITE8X8")
        glass:SetPoint("TOPLEFT", piece, "TOPLEFT", 2, -2)
        glass:SetPoint("TOPRIGHT", piece, "TOPRIGHT", -2, -2)
        glass:SetHeight(15)
        glass:SetGradientAlpha("VERTICAL", 0.72, 0.82, 0.92, 0.015, 0.90, 0.95, 1.00, 0.16)

        local border = UI.CreateThinCardBorder(piece, 1)
        border:SetBorderColor(0.46, 0.47, 0.49, 0.92)

        local highlight = piece:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
        highlight:SetPoint("TOPLEFT", piece, "TOPLEFT", 2, -2)
        highlight:SetPoint("BOTTOMRIGHT", piece, "BOTTOMRIGHT", -2, 2)
        highlight:SetVertexColor(1.00, 0.88, 0.52, 0.14)
        piece:SetHighlightTexture(highlight)

        piece:SetScript("OnEnter", function(self)
            if self.scItemId then
                showPieceTooltip(self, self.scItemId, self.scSetRecord, self.scPreviewItem, self.scSetDisplayRecord)
            end
        end)
        piece:SetScript("OnClick", function(self, button)
            local sourceItemIds = self.scSourceItemIds
            if button ~= "LeftButton" or not IsAltKeyDown or not IsAltKeyDown() or
                not sourceItemIds or #sourceItemIds <= 1 or not self.scAltSourceKey then
                return
            end

            local currentItemId = tonumber(self.scItemId)
            local nextIndex = 1
            for sourceIndex, sourceItemId in ipairs(sourceItemIds) do
                if tonumber(sourceItemId) == currentItemId then
                    nextIndex = sourceIndex + 1
                    if nextIndex > #sourceItemIds then nextIndex = 1 end
                    break
                end
            end
            page.scSetPieceAltSourceByMember[self.scAltSourceKey] = tonumber(sourceItemIds[nextIndex]) or sourceItemIds[nextIndex]
            if previewSet and page.scSetSelectedDisplayRecord then
                previewSet(page.scSetSelectedDisplayRecord)
            end
        end)
        piece:SetScript("OnLeave", function() GameTooltip:Hide() end)
        piece.scIcon = icon
        piece.scBorder = border
        SC.WardrobeUI.Layout:StyleItemButton(piece, nil)
        piece:Hide()
        page.scPieceIcons[index] = piece
    end

    local function clearDragState()
        model.scDragging = nil
        model.scLastCursorX = nil
        model:SetScript("OnUpdate", nil)
    end

    local function applyModelFacing(rotation)
        -- Keep the set preview aligned with the mount page: SetFacing changes
        -- the actor heading without forcing the model animation to restart.
        if model.SetFacing then
            model:SetFacing(rotation)
        elseif model.SetRotation then
            model:SetRotation(rotation, false)
        end
    end

    local function updateModelDrag(self)
        if not self.scDragging or not IsMouseButtonDown("LeftButton") then
            clearDragState()
            return
        end
        local cursorX = GetCursorPosition()
        local previousX = self.scLastCursorX or cursorX
        self.scLastCursorX = cursorX
        local delta = (cursorX - previousX) * DRAG_ROTATION_CONSTANT
        if delta == 0 then return end
        self.scRotation = (self.scRotation or DEFAULT_ROTATION) + delta
        if self.scRotation < 0 then self.scRotation = self.scRotation + TWO_PI end
        if self.scRotation > TWO_PI then self.scRotation = self.scRotation - TWO_PI end
        applyModelFacing(self.scRotation)
    end

    local function resetModelView()
        clearDragState()
        model.scRotation = DEFAULT_ROTATION
        model.scZoom = 0
        applyModelFacing(DEFAULT_ROTATION)
        if model.SetPosition then
            pcall(function() model:SetPosition(0, 0, 0) end)
        end
    end

    local function preparePlayerModel()
        model:ClearModel()
        resetModelView()
        pcall(function() model:SetUnit("player") end)
    end

    local function deriveSetPieceState(record)
        local state = {}
        local variant = record and record.selectedVariant
        for _, member in ipairs(variant and variant.members or {}) do
            local collected = false
            for _, appearanceId in ipairs(member.appearanceIds or {}) do
                if SC.CollectionState and SC.CollectionState.IsOwnedByType and
                    SC.CollectionState.IsOwnedByType(13, appearanceId) then
                    collected = true
                    break
                end
            end
            for _, itemId in ipairs(member.sourceItemIds or {}) do
                state[itemId] = collected
            end
        end
        return state
    end

    local function updateSetPieceVisual(piece, itemId, collected)
        local icon = GetItemIcon(itemId)
        UI.SetIconTexture(piece.scIcon, icon)
        UI.SetCollectedVisual(piece.scIcon, collected, 0.50)

        -- Item quality may arrive asynchronously. Use a neutral glass rim until
        -- GET_ITEM_INFO_RECEIVED supplies the real quality colour.
        local quality = select(3, GetItemInfo(itemId))
        local red, green, blue = 0.46, 0.47, 0.49
        if quality and GetItemQualityColor then
            red, green, blue = GetItemQualityColor(quality)
        end
        piece.scBorder:SetBorderColor(red, green, blue, collected and 1.00 or 0.74)
        piece.scQuality = quality
        piece.scCollected = collected and true or false
        SC.WardrobeUI.Layout:StyleItemButton(piece, quality)
    end

    -- Preview uses exactly one deterministic source item per selected-variant
    -- member. This is intentionally separate from the server-side owned
    -- alternative resolver used by APPLY: a local DressUpModel preview must
    -- not imply which source item the server would eventually choose.
    local function setPieceAltSourceKey(record, uniqueSlot)
        return tostring(record and (record.id or record.itemSetId) or "unknown") .. ":" .. tostring(uniqueSlot or "slot")
    end

    local function sourceListContains(sourceItemIds, itemId)
        itemId = tonumber(itemId)
        if not itemId then return false end
        for _, sourceItemId in ipairs(sourceItemIds or {}) do
            if tonumber(sourceItemId) == itemId then
                return true
            end
        end
        return false
    end

    local function getSelectedVariantPreviewItems(record)
        local result = {}
        local seenSlots = {}
        local variant = record and record.selectedVariant
        for memberIndex, member in ipairs(variant and variant.members or {}) do
            if member.required then
                local previewSourceItemId = tonumber(member.previewSourceItemId)
                if not previewSourceItemId or previewSourceItemId <= 0 then
                    for _, sourceItemId in ipairs(member.sourceItemIds or {}) do
                        sourceItemId = tonumber(sourceItemId)
                        if sourceItemId and sourceItemId > 0 and
                            (not previewSourceItemId or sourceItemId < previewSourceItemId) then
                            previewSourceItemId = sourceItemId
                        end
                    end
                end
                local slotKey = tostring(member.slotKey or member.memberKey or "")
                local uniqueSlot = slotKey ~= "" and slotKey or ("member:" .. memberIndex)
                local altSourceKey = setPieceAltSourceKey(record, uniqueSlot)
                local overrideSourceItemId = page.scSetPieceAltSourceByMember and page.scSetPieceAltSourceByMember[altSourceKey]
                if sourceListContains(member.sourceItemIds, overrideSourceItemId) then
                    previewSourceItemId = tonumber(overrideSourceItemId)
                end
                if previewSourceItemId and not seenSlots[uniqueSlot] then
                    seenSlots[uniqueSlot] = true
                    table.insert(result, {
                        memberIndex = memberIndex,
                        memberKey = tostring(member.memberKey or uniqueSlot),
                        slotKey = slotKey,
                        previewSourceItemId = previewSourceItemId,
                        sourceItemIds = member.sourceItemIds or {},
                        appearanceIds = member.appearanceIds or {},
                        altSourceKey = altSourceKey,
                        order = SET_MEMBER_SLOT_ORDER[slotKey] or (100 + memberIndex),
                    })
                end
            end
        end
        table.sort(result, function(left, right)
            if left.order == right.order then
                if left.memberKey == right.memberKey then
                    return left.previewSourceItemId < right.previewSourceItemId
                end
                return left.memberKey < right.memberKey
            end
            return left.order < right.order
        end)
        return result
    end

    local function cancelSetPreview()
        page.scSetPreviewGeneration = (page.scSetPreviewGeneration or 0) + 1
        page.scSetPreviewPending = nil
        page.scAdvanceSetPreview = nil
        model.scSetPreviewGeneration = page.scSetPreviewGeneration
        model.scSetPreviewPending = nil
        if setPresenter then setPresenter:Clear("SET_PREVIEW_INVALIDATED") end
    end

    local function queueSetPreview(record)
        local generation = (page.scSetPreviewGeneration or 0) + 1
        local previewItems = getSelectedVariantPreviewItems(record)
        local pending = {
            generation = generation,
            recordId = record and record.id,
            items = previewItems,
            renderTicks = 0,
        }
        page.scSetPreviewGeneration = generation
        page.scSetPreviewPending = pending
        model.scSetPreviewGeneration = generation
        model.scSetPreviewPending = pending
        local itemStrings = {}
        for _, previewItem in ipairs(previewItems) do
            itemStrings[#itemStrings + 1] = resolveTryOnItem(previewItem.previewSourceItemId)
        end
        setPresenter:Present({
            unit = "player",
            undress = true,
            settleTicks = 2,
            items = itemStrings,
            onReady = function()
                if page.scSetPreviewPending == pending and page.scSetSelectedId == pending.recordId then
                    page.scSetPreviewPending = nil
                    model.scSetPreviewPending = nil
                end
            end,
        })
        return previewItems
    end

    local function syncSetVariantDropdown(displayRecord, selectedRecord)
        local variantCount = displayRecord and displayRecord.scVariants and #displayRecord.scVariants or 0
        if displayRecord and displayRecord.scIsSetGroup and variantCount > 1 then
            variantDropdown.scSetGroupRecord = displayRecord
            UIDropDownMenu_SetSelectedValue(variantDropdown, selectedRecord and selectedRecord.id)
            UIDropDownMenu_SetText(variantDropdown, selectedRecord and setVariantLabel(selectedRecord) or "版本")
            variantDropdown:Show()
        else
            variantDropdown.scSetGroupRecord = nil
            UIDropDownMenu_SetText(variantDropdown, "")
            variantDropdown:Hide()
        end
    end

    previewSet = function(record)
        local displayRecord = record
        record = concreteSetRecord(record)
        if not record then return end
        page.scSetSelectedDisplayRecord = displayRecord
        page.scSetSelectedRecord = record
        if record.collected then applySet:Enable() else applySet:Disable() end
        model:ClearAllPoints()
        model:SetPoint("TOPLEFT", preview, "TOPLEFT", 9, SET_DETAILS_MODEL_TOP_Y)
        model:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -9, 76)
        model:Show()
        syncSetVariantDropdown(displayRecord, record)
        local previewItems = queueSetPreview(record)
        local setName = setDisplayName(displayRecord or record)
        name:SetText(setName)
        longName:SetText(setName)
        if name.GetStringWidth and name:GetStringWidth() > name:GetWidth() then
            name:Hide()
            longName:Show()
        else
            name:Show()
            longName:Hide()
        end
        local presentationLabel = setPresentationLabel(record)
        local detailParts = {}
        if presentationLabel then
            detailParts[#detailParts + 1] = "分类：" .. presentationLabel
        end
        local categoryLabel = setRecordCategoryLabel(record)
        if categoryLabel and not setRecordIsClassSpecific(record) then
            detailParts[#detailParts + 1] = "类型：" .. categoryLabel
        else
            detailParts[#detailParts + 1] = "职业：" .. setClassLabel(record)
        end
        local specLabel = setRecordSpecLabel(record)
        if specLabel then
            detailParts[#detailParts + 1] = "专精：" .. specLabel
        end
        local factionLabel = setRecordFactionLabel(record)
        if factionLabel then
            detailParts[#detailParts + 1] = "阵营：" .. factionLabel
        end
        detail:SetText(table.concat(detailParts, "  ·  "))
        local pieceState = deriveSetPieceState(record)
        local pieceCount = math.min(#previewItems, #page.scPieceIcons)
        local firstRow = math.min(SET_PIECE_COLUMNS, pieceCount)
        local piecesWidth = (firstRow * SET_PIECE_SIZE) + (math.max(0, firstRow - 1) * SET_PIECE_SPACING)
        pieces:SetWidth(math.max(1, piecesWidth))
        if pieceCount > 0 then pieces:Show() else pieces:Hide() end
        for index, piece in ipairs(page.scPieceIcons) do
            piece:ClearAllPoints()
            if index == 1 then
                piece:SetPoint("TOPLEFT", pieces, "TOPLEFT", 0, 0)
            elseif (index - 1) % SET_PIECE_COLUMNS == 0 then
                piece:SetPoint("TOPLEFT", page.scPieceIcons[index - SET_PIECE_COLUMNS], "BOTTOMLEFT", 0, -SET_PIECE_SPACING)
            else
                piece:SetPoint("LEFT", page.scPieceIcons[index - 1], "RIGHT", SET_PIECE_SPACING, 0)
            end

            local previewItem = previewItems[index]
            local itemId = previewItem and previewItem.previewSourceItemId
            piece.scItemId = itemId
            piece.scSetRecord = record
            piece.scSetDisplayRecord = displayRecord
            piece.scPreviewItem = previewItem
            piece.scSlotKey = previewItem and previewItem.slotKey
            piece.scSourceItemIds = previewItem and previewItem.sourceItemIds
            piece.scAltSourceKey = previewItem and previewItem.altSourceKey
            if itemId then
                local collected = pieceState[itemId] and true or false
                updateSetPieceVisual(piece, itemId, collected)
                piece:Show()
            else
                piece.scSetRecord = nil
                piece.scSetDisplayRecord = nil
                piece.scPreviewItem = nil
                piece.scSlotKey = nil
                piece.scSourceItemIds = nil
                piece.scAltSourceKey = nil
                piece.scCollected = nil
                piece.scQuality = nil
                piece:Hide()
            end
        end
        local collectedPieces = tonumber(record.collectedCount) or 0
        local requiredPieces = tonumber(record.requiredCount) or #previewItems
        setProgress:SetText("套装收集进度：" .. collectedPieces .. " / " .. requiredPieces)
        setProgress:Show()
    end

    selectSetDisplayRecord = function(record)
        local concreteRecord = concreteSetRecord(record)
        if not concreteRecord then return end
        local selectionKey = setRecordSelectionKey(record)
        page.scSetSelectedGroupKey = selectionKey
        page.scSetSelectedId = concreteRecord.id
        if record and record.scIsSetGroup and page.scSelectedSetVariantByGroup then
            page.scSelectedSetVariantByGroup[record.scSetGroupKey] = concreteRecord.id
        end
        previewSet(record)
        for _, setRow in ipairs(page.scSetRows) do
            if setRow.scRecord == record then
                setRow:SetRecord(record)
            end
            setRow:SetSelected(setRecordSelectionKey(setRow.scRecord) == selectionKey)
        end
    end

    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.scDragging = true
            self.scLastCursorX = GetCursorPosition()
            self:SetScript("OnUpdate", updateModelDrag)
        end
    end)
    model:SetScript("OnMouseUp", function() clearDragState() end)
    model:SetScript("OnMouseWheel", function(self, delta)
        if model.SetPosition then
            self.scZoom = math.max(-0.7, math.min(0.7, (self.scZoom or 0) + delta * 0.08))
            pcall(function() self:SetPosition(0, 0, self.scZoom) end)
        end
    end)
    reset:SetScript("OnClick", function()
        if setPresenter and setPresenter.ResetView then setPresenter:ResetView() end
        resetModelView()
    end)
    applySet:SetScript("OnClick", function()
        local record = page.scSetSelectedRecord
        if not record or not record.collected then
            showSetActionResult(false, "NOT_OWNED")
        elseif not SC.Bridge or not SC.Bridge.ApplySet then
            showSetActionResult(false, "BRIDGE_UNAVAILABLE")
        else
            local variant = record.selectedVariant
            SC.Bridge.ApplySet(record.id, variant and variant.variantOrdinal or nil, showSetActionResult)
        end
    end)

    local function selectItem(record)
        page.scItemSelectedId = record and record.id or nil
        for _, itemModel in ipairs(page.scItemModels) do
            local selected = itemModel.scRecord and itemModel.scRecord.id == page.scItemSelectedId
            if selected then
                itemModel.scSelected:Show()
            else
                itemModel.scSelected:Hide()
            end
        end
    end

--[=[ Reference-only in-game M2 camera tuner. The active item page neither
-- creates these frames nor exposes a toggle/fallback path.
    -- In-game M2 camera tuner -------------------------------------------------
    -- This intentionally lives on the item page rather than in the ordinary
    -- options UI: a pose only makes sense while its exact weapon card is
    -- visible. The values are persisted by weapon type, never written into the
    -- catalog record, and can later be exported into Appearances.lua.
    local cameraTuningButton
    local cameraTuningPanel = CreateFrame("Frame", "SoloCollectionsM2CameraTuningPanel", page)
    cameraTuningPanel:SetWidth(286)
    cameraTuningPanel:SetHeight(486)
    cameraTuningPanel:SetPoint("TOPRIGHT", itemsPanel, "TOPRIGHT", -4, -4)
    -- The item cards are children of itemsPanel and therefore may sit above a
    -- sibling frame whose level is derived only from page.  Keep the workbench
    -- in the normal frame strata, but place it explicitly above the cards so
    -- it remains visible on the stock 3.3.5 client.
    cameraTuningPanel:SetFrameLevel(itemsPanel:GetFrameLevel() + 12)
    cameraTuningPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    cameraTuningPanel:SetBackdropColor(0.025, 0.022, 0.018, 0.98)
    cameraTuningPanel:SetBackdropBorderColor(0.68, 0.49, 0.18, 1)
    cameraTuningPanel:Hide()
    cameraTuningPanel.scControls = {}
    cameraTuningPanel.scBodyControls = {}
    cameraTuningPanel.scScope = "weaponFamily"
    cameraTuningPanel.scMode = "weapon"
    cameraTuningPanel.scSessionBefore = {}
    cameraTuningPanel.scBatch = {}
    cameraTuningPanel.scBodySessionBefore = {}
    cameraTuningPanel.scBodyBatch = {}

    local tuningTitle = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tuningTitle:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -10)
    tuningTitle:SetText("镜头工作台")
    tuningTitle:SetTextColor(1.00, 0.82, 0.20)

    local tuningRecord = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tuningRecord:SetPoint("TOPLEFT", tuningTitle, "BOTTOMLEFT", 0, -4)
    tuningRecord:SetPoint("RIGHT", cameraTuningPanel, "RIGHT", -96, 0)
    tuningRecord:SetJustifyH("LEFT")
    tuningRecord:SetTextColor(0.80, 0.74, 0.63)

    local tuningScopeDropdown = CreateFrame("Frame", "SoloCollectionsM2CameraScopeDropdown", cameraTuningPanel, "UIDropDownMenuTemplate")
    tuningScopeDropdown:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -18, -17)
    UIDropDownMenu_SetWidth(tuningScopeDropdown, 74)

    local tuningMetadata = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tuningMetadata:SetPoint("TOPLEFT", tuningRecord, "BOTTOMLEFT", 0, -3)
    tuningMetadata:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -12, -47)
    tuningMetadata:SetHeight(37)
    tuningMetadata:SetJustifyH("LEFT")
    tuningMetadata:SetJustifyV("TOP")
    tuningMetadata:SetTextColor(0.63, 0.59, 0.51)

    local tuningStrategy = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningStrategy:SetWidth(118)
    tuningStrategy:SetHeight(21)
    tuningStrategy:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -70)
    local function syncTuningStrategyLabel()
        local strategy = page.scCameraWorkbench and page.scCameraWorkbench.strategy
        tuningStrategy:SetText(strategy == "NEWERA_POSITION" and "A: NewEra 位移" or "B: Profile/SoloCam")
    end
    tuningStrategy:SetScript("OnClick", function()
        page.scCameraWorkbench:ToggleStrategy()
        syncTuningStrategyLabel()
        page:Refresh()
    end)
    syncTuningStrategyLabel()

    local tuningClose = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelCloseButton")
    tuningClose:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", 2, 2)

    local tuningHint = cameraTuningPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tuningHint:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -294)
    tuningHint:SetPoint("TOPRIGHT", cameraTuningPanel, "TOPRIGHT", -12, -294)
    tuningHint:SetHeight(28)
    tuningHint:SetJustifyH("LEFT")
    tuningHint:SetJustifyV("TOP")
    tuningHint:SetText("范围：武器类别 / 此模型 / 此外观。数值会立即预览；导出仅生成待审核候选。")
    tuningHint:SetTextColor(0.62, 0.58, 0.49)

    local tuningPrevious = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningPrevious:SetWidth(78)
    tuningPrevious:SetHeight(22)
    tuningPrevious:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -327)
    tuningPrevious:SetText("上一条")

    local tuningNext = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningNext:SetWidth(78)
    tuningNext:SetHeight(22)
    tuningNext:SetPoint("LEFT", tuningPrevious, "RIGHT", 6, 0)
    tuningNext:SetText("下一条")

    local tuningPreviousUncalibrated = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningPreviousUncalibrated:SetWidth(122)
    tuningPreviousUncalibrated:SetHeight(22)
    tuningPreviousUncalibrated:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -353)
    tuningPreviousUncalibrated:SetText("上一条未校准")

    local tuningNextUncalibrated = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningNextUncalibrated:SetWidth(122)
    tuningNextUncalibrated:SetHeight(22)
    tuningNextUncalibrated:SetPoint("LEFT", tuningPreviousUncalibrated, "RIGHT", 6, 0)
    tuningNextUncalibrated:SetText("下一条未校准")

    -- A 3.3.5 EditBox is not clipped by its own height. Keep the review JSONL
    -- in a ScrollFrame so long records cannot paint over the sliders above it.
    local tuningExportScroll = CreateFrame("ScrollFrame", nil, cameraTuningPanel)
    tuningExportScroll:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 12)
    tuningExportScroll:SetPoint("BOTTOMRIGHT", cameraTuningPanel, "BOTTOMRIGHT", -12, 12)
    tuningExportScroll:SetHeight(42)
    tuningExportScroll:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tuningExportScroll:SetBackdropColor(0.015, 0.012, 0.010, 0.88)
    tuningExportScroll:SetBackdropBorderColor(0.40, 0.30, 0.16, 0.85)
    tuningExportScroll:EnableMouseWheel(true)

    local tuningExport = CreateFrame("EditBox", nil, tuningExportScroll, "InputBoxTemplate")
    tuningExport:SetWidth(254)
    tuningExport:SetHeight(512)
    if tuningExport.SetMultiLine then tuningExport:SetMultiLine(true) end
    tuningExport:SetAutoFocus(false)
    tuningExport:SetFontObject("ChatFontNormal")
    tuningExport:SetTextColor(0.92, 0.84, 0.62)
    tuningExportScroll:SetScrollChild(tuningExport)
    tuningExportScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, tuningExport:GetHeight() - self:GetHeight())
        local nextScroll = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 20))
        self:SetVerticalScroll(nextScroll)
    end)
    tuningExport:SetScript("OnTextChanged", function()
        tuningExportScroll:SetVerticalScroll(0)
    end)
    tuningExport:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local tuningReset = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningReset:SetWidth(84)
    tuningReset:SetHeight(22)
    tuningReset:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 61)
    tuningReset:SetText("恢复当前层")

    local tuningCopy = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningCopy:SetWidth(78)
    tuningCopy:SetHeight(22)
    tuningCopy:SetPoint("LEFT", tuningReset, "RIGHT", 4, 0)
    tuningCopy:SetText("复制当前")

    local tuningBatch = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningBatch:SetWidth(78)
    tuningBatch:SetHeight(22)
    tuningBatch:SetPoint("LEFT", tuningCopy, "RIGHT", 4, 0)
    tuningBatch:SetText("加入批次")

    local tuningCopyAll = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningCopyAll:SetWidth(84)
    tuningCopyAll:SetHeight(22)
    tuningCopyAll:SetPoint("BOTTOMLEFT", cameraTuningPanel, "BOTTOMLEFT", 12, 86)
    tuningCopyAll:SetText("复制本次修改")

    local tuningDiscard = CreateFrame("Button", nil, cameraTuningPanel, "UIPanelButtonTemplate")
    tuningDiscard:SetWidth(98)
    tuningDiscard:SetHeight(22)
    tuningDiscard:SetPoint("LEFT", tuningCopyAll, "RIGHT", 6, 0)
    tuningDiscard:SetText("放弃未导出")

    local function updateTuningValueLabel(control, value)
        control.value:SetText(string.format("%.2f", value))
    end

    local applyCameraTuning
    local applyBodyCameraTuning
    local updateCameraTuningExport

    local function getCameraTuningScopeKey(record, scope)
        if scope == "appearance" then return getAppearanceCameraKey(record) end
        if scope == "model" then return getModelCameraKey(record) end
        return getWeaponFamilyCameraKey(record)
    end

    local CAMERA_TUNING_SCOPES = {
        { key = "weaponFamily", label = "武器类别" },
        { key = "model", label = "此模型" },
        { key = "appearance", label = "此外观" },
    }

    local function cameraTuningScopeLabel(scope)
        for _, option in ipairs(CAMERA_TUNING_SCOPES) do
            if option.key == scope then return option.label end
        end
        return "武器类别"
    end

    local function cameraTuningSourceLabel(source)
        if source == "auto" then return "自动基线" end
        if source == "generatedModel" then return "已审核模型基线" end
        return cameraTuningScopeLabel(source)
    end

    UIDropDownMenu_Initialize(tuningScopeDropdown, function()
        for _, option in ipairs(CAMERA_TUNING_SCOPES) do
            local scopeOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = scopeOption.label
            info.value = scopeOption.key
            info.checked = cameraTuningPanel.scScope == scopeOption.key
            info.func = function()
                local record = cameraTuningPanel.scRecord
                if scopeOption.key == "model" and not getModelCameraKey(record) then
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前外观没有稳定模型签名，不能使用模型范围。")
                    end
                    return
                end
                cameraTuningPanel.scScope = scopeOption.key
                UIDropDownMenu_SetSelectedValue(tuningScopeDropdown, scopeOption.key)
                UIDropDownMenu_SetText(tuningScopeDropdown, scopeOption.label)
                if record then page:SyncCameraTuningPanel(record) end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local function createCameraTuningSlider(index, key, labelText, limits, targetIndex)
        local row = CreateFrame("Frame", nil, cameraTuningPanel)
        row:SetWidth(262)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -96 - ((index - 1) * 27))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 2)
        label:SetWidth(48)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        label:SetTextColor(0.88, 0.78, 0.58)

        local sliderName = "SoloCollectionsM2Camera" .. key .. "Slider"
        -- Do not use OptionsSliderTemplate here.  Its settings-panel scripts can
        -- assign a zero/default value when an ancestor frame becomes visible,
        -- which races the workbench's autoCamera baseline.  This small local
        -- slider owns only the visuals and has no hidden configuration state.
        local slider = CreateFrame("Slider", sliderName, row)
        slider:SetPoint("LEFT", label, "RIGHT", 2, 0)
        slider:SetWidth(76)
        slider:SetHeight(16)
        slider:SetOrientation("HORIZONTAL")
        local sliderTrack = slider:CreateTexture(nil, "BACKGROUND")
        sliderTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
        sliderTrack:SetHeight(3)
        sliderTrack:SetPoint("LEFT", slider, "LEFT", 2, 0)
        sliderTrack:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
        sliderTrack:SetVertexColor(0.36, 0.27, 0.15, 1)
        local sliderThumb = slider:CreateTexture(nil, "OVERLAY")
        sliderThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        sliderThumb:SetWidth(12)
        sliderThumb:SetHeight(16)
        slider:SetThumbTexture(sliderThumb)
        slider:SetMinMaxValues(limits.minimum, limits.maximum)
        slider:SetValueStep(limits.step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local value = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        value:SetPoint("LEFT", slider, "RIGHT", 3, 0)
        value:SetWidth(39)
        value:SetHeight(18)
        value:SetAutoFocus(false)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(1.00, 0.85, 0.34)

        local control = {
            key = key,
            targetIndex = targetIndex,
            slider = slider,
            value = value,
            limits = limits,
            buttons = {},
            row = row,
        }
        table.insert(cameraTuningPanel.scControls, control)

        local function applyDelta(delta)
            slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, slider:GetValue() + delta)))
        end

        local function createStepButton(offset, text, delta)
            local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            button:SetWidth(15)
            button:SetHeight(18)
            button:SetPoint("LEFT", value, "RIGHT", offset, 0)
            button:SetText(text)
            button:SetScript("OnClick", function() applyDelta(delta) end)
            table.insert(control.buttons, button)
        end
        createStepButton(3, "-", -limits.step)
        createStepButton(20, "--", -limits.step * 5)
        createStepButton(37, "+", limits.step)
        createStepButton(54, "++", limits.step * 5)

        value:SetScript("OnEnterPressed", function(self)
            local parsed = tonumber(self:GetText())
            if parsed then
                slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, parsed)))
            else
                updateTuningValueLabel(control, slider:GetValue())
            end
            self:ClearFocus()
        end)
        value:SetScript("OnEscapePressed", function(self)
            updateTuningValueLabel(control, slider:GetValue())
            self:ClearFocus()
        end)
        slider:SetScript("OnValueChanged", function(_, valueChanged)
            updateTuningValueLabel(control, valueChanged)
            if cameraTuningPanel.scSyncing or not cameraTuningPanel.scRecord
                or not SC.db or not SC.M2Camera or not SC.M2Camera.NormalizePose then
                return
            end
            local pose = SC.M2Camera.NormalizePose(cameraTuningPanel.scPose)
            if targetIndex then
                pose.target[targetIndex] = valueChanged
            else
                pose[key] = valueChanged
            end
            pose = SC.M2Camera.NormalizePose(pose)
            cameraTuningPanel.scPose = pose
            local scope = cameraTuningPanel.scScope or "weaponFamily"
            local tuningKey = getCameraTuningScopeKey(cameraTuningPanel.scRecord, scope)
            local lowerScopePose = select(1, resolveM2CameraScopePose(cameraTuningPanel.scRecord, scope))
            if not tuningKey or not SC.CameraTuning or not SC.CameraTuning.Set then return end
            local sessionKey = scope .. "\031" .. tuningKey
            if cameraTuningPanel.scSessionBefore[sessionKey] == nil then
                local previous = SC.CameraTuning.Get and SC.CameraTuning.Get(scope, tuningKey) or nil
                cameraTuningPanel.scSessionBefore[sessionKey] = previous or false
            end
            SC.CameraTuning.Set(scope, tuningKey, pose, lowerScopePose)
            cameraTuningPanel.scCurrentDirty = true
            if cameraTuningPanel.scBatch[sessionKey] then
                cameraTuningPanel.scBatch[sessionKey].pose = pose
            end
            applyCameraTuning(cameraTuningPanel.scRecord)
            updateCameraTuningExport()
        end)
        return control
    end

    local cameraLimits = (SC.M2Camera and SC.M2Camera.Limits) or {
        yaw = { minimum = -math.pi, maximum = math.pi, step = 0.01 },
        pitch = { minimum = -1.20, maximum = 1.20, step = 0.01 },
        roll = { minimum = -math.pi, maximum = math.pi, step = 0.01 },
        distanceScale = { minimum = 0.25, maximum = 4.00, step = 0.01 },
        target = { minimum = -4.00, maximum = 4.00, step = 0.01 },
    }
    createCameraTuningSlider(1, "yaw", "Yaw 环绕", cameraLimits.yaw)
    createCameraTuningSlider(2, "pitch", "Pitch 俯仰", cameraLimits.pitch)
    createCameraTuningSlider(3, "roll", "Roll 滚转", cameraLimits.roll)
    createCameraTuningSlider(4, "distanceScale", "Distance 距离", cameraLimits.distanceScale)
    createCameraTuningSlider(5, "targetX", "Target X", cameraLimits.target, 1)
    createCameraTuningSlider(6, "targetY", "Target Y", cameraLimits.target, 2)
    createCameraTuningSlider(7, "targetZ", "Target Z", cameraLimits.target, 3)

    local function createBodyCameraTuningSlider(index, key, labelText, limits)
        local row = CreateFrame("Frame", nil, cameraTuningPanel)
        row:SetWidth(262)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", cameraTuningPanel, "TOPLEFT", 12, -96 - ((index - 1) * 27))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 2)
        label:SetWidth(48)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        label:SetTextColor(0.72, 0.84, 0.96)

        local slider = CreateFrame("Slider", "SoloCollectionsBodyCamera" .. key .. "Slider", row)
        slider:SetPoint("LEFT", label, "RIGHT", 2, 0)
        slider:SetWidth(76)
        slider:SetHeight(16)
        slider:SetOrientation("HORIZONTAL")
        local sliderTrack = slider:CreateTexture(nil, "BACKGROUND")
        sliderTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
        sliderTrack:SetHeight(3)
        sliderTrack:SetPoint("LEFT", slider, "LEFT", 2, 0)
        sliderTrack:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
        sliderTrack:SetVertexColor(0.16, 0.32, 0.48, 1)
        local sliderThumb = slider:CreateTexture(nil, "OVERLAY")
        sliderThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        sliderThumb:SetWidth(12)
        sliderThumb:SetHeight(16)
        slider:SetThumbTexture(sliderThumb)
        slider:SetMinMaxValues(limits.minimum, limits.maximum)
        slider:SetValueStep(limits.step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local value = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        value:SetPoint("LEFT", slider, "RIGHT", 3, 0)
        value:SetWidth(39)
        value:SetHeight(18)
        value:SetAutoFocus(false)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(0.48, 0.84, 1.00)

        local control = { key = key, slider = slider, value = value, limits = limits, buttons = {}, row = row }
        table.insert(cameraTuningPanel.scBodyControls, control)
        local function update(valueChanged)
            value:SetText(string.format("%.2f", valueChanged))
        end
        local function applyDelta(delta)
            slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, slider:GetValue() + delta)))
        end
        local function createStepButton(offset, text, delta)
            local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            button:SetWidth(15)
            button:SetHeight(18)
            button:SetPoint("LEFT", value, "RIGHT", offset, 0)
            button:SetText(text)
            button:SetScript("OnClick", function() applyDelta(delta) end)
            table.insert(control.buttons, button)
        end
        createStepButton(3, "-", -limits.step)
        createStepButton(20, "--", -limits.step * 5)
        createStepButton(37, "+", limits.step)
        createStepButton(54, "++", limits.step * 5)
        value:SetScript("OnEnterPressed", function(self)
            local parsed = tonumber(self:GetText())
            if parsed then
                slider:SetValue(math.max(limits.minimum, math.min(limits.maximum, parsed)))
            else
                update(slider:GetValue())
            end
            self:ClearFocus()
        end)
        value:SetScript("OnEscapePressed", function(self)
            update(slider:GetValue())
            self:ClearFocus()
        end)
        slider:SetScript("OnValueChanged", function(_, valueChanged)
            update(valueChanged)
            if cameraTuningPanel.scSyncing or cameraTuningPanel.scMode ~= "body"
                or not cameraTuningPanel.scBodyProfile or not SC.M2Camera
                or not SC.M2Camera.NormalizeBodyDelta or not SC.BodyCameraTuning then
                return
            end
            local delta = SC.M2Camera.NormalizeBodyDelta(cameraTuningPanel.scBodyDelta)
            delta[key] = valueChanged
            delta = SC.M2Camera.NormalizeBodyDelta(delta)
            local profile = cameraTuningPanel.scBodyProfile
            local sessionKey = profile.profileKey
            if cameraTuningPanel.scBodySessionBefore[sessionKey] == nil then
                local previous = SC.BodyCameraTuning.Get and SC.BodyCameraTuning.Get(sessionKey) or nil
                cameraTuningPanel.scBodySessionBefore[sessionKey] = previous or false
            end
            if not SC.BodyCameraTuning.Set or not SC.BodyCameraTuning.Set(sessionKey, delta) then return end
            cameraTuningPanel.scBodyDelta = delta
            cameraTuningPanel.scCurrentDirty = true
            if cameraTuningPanel.scBodyBatch[sessionKey] then
                cameraTuningPanel.scBodyBatch[sessionKey].delta = delta
            end
            applyBodyCameraTuning(profile)
            updateCameraTuningExport()
        end)
        row:Hide()
        return control
    end

    local bodyLimits = (SC.M2Camera and SC.M2Camera.BodyLimits) or {
        verticalOffsetDelta = { minimum = -2.00, maximum = 2.00, step = 0.01 },
        horizontalOffsetDelta = { minimum = -2.00, maximum = 2.00, step = 0.01 },
        distanceScaleMultiplier = { minimum = 0.50, maximum = 2.00, step = 0.01 },
        minimumDistanceDelta = { minimum = -2.00, maximum = 2.00, step = 0.01 },
        yawOffsetDelta = { minimum = -math.pi, maximum = math.pi, step = 0.01 },
    }
    createBodyCameraTuningSlider(1, "verticalOffsetDelta", "Vertical 高度", bodyLimits.verticalOffsetDelta)
    createBodyCameraTuningSlider(2, "horizontalOffsetDelta", "Horizontal 横移", bodyLimits.horizontalOffsetDelta)
    createBodyCameraTuningSlider(3, "distanceScaleMultiplier", "Distance 倍率", bodyLimits.distanceScaleMultiplier)
    createBodyCameraTuningSlider(4, "minimumDistanceDelta", "Minimum 最小", bodyLimits.minimumDistanceDelta)
    createBodyCameraTuningSlider(5, "yawOffsetDelta", "Yaw 环绕", bodyLimits.yawOffsetDelta)

    local function getTuningPose(record)
        return resolveM2CameraScopePose(record, cameraTuningPanel.scScope or "weaponFamily")
    end

    applyCameraTuning = function(record)
        if not record then return end
        for _, itemModel in ipairs(page.scItemModels) do
            local objectModel = itemModel.scObjectModel
            if itemModel.scRecord and itemModel.scRenderKind == "STANDALONE"
                and objectModel and isM2CameraTunableRecord(itemModel.scRecord) then
                applyStandaloneItemView(objectModel)
                queueStandaloneItemTransform(objectModel)
            end
        end
    end

    applyBodyCameraTuning = function(profile)
        if not profile then return end
        for _, itemModel in ipairs(page.scItemModels) do
            local visibleProfile = itemModel.scRecord
                and getCharacterCameraProfileForSlot(itemModel.scRecord.slot) or nil
            if itemModel.scRecord and itemModel.scRenderKind == "BODY"
                and visibleProfile and visibleProfile.profileKey == profile.profileKey then
                -- Re-enter the existing SetUnit/TryOn generation state machine.
                -- It chooses the profile sentinel, replays the complete body
                -- transaction after asynchronous rebuild, and keeps all other
                -- slot/race profiles untouched.
                queueItemModelView(itemModel, true)
            end
        end
    end

    local function navigateCameraTuning(step, onlyUncalibrated)
        if not SC.db or not cameraTuningPanel.scRecord then return false end
        local records = itemDataProvider:QueryAllItems()
        if #records == 0 then return false end
        local currentIndex = 1
        for index, record in ipairs(records) do
            if record.id == cameraTuningPanel.scRecord.id then
                currentIndex = index
                break
            end
        end
        for offset = 1, #records do
            local index = ((currentIndex - 1 + step * offset) % #records) + 1
            local candidate = records[index]
            local bodyMode = cameraTuningPanel.scMode == "body"
            local candidateProfile = bodyMode and getCharacterCameraProfileForSlot(candidate.slot) or nil
            local source = nil
            if not bodyMode then
                local _, resolvedSource = resolveM2CameraPose(candidate)
                source = resolvedSource
            end
            local candidateIsTunable = bodyMode
                and isBodyCameraTunableRecord(candidate)
                or (not bodyMode and isM2CameraTunableRecord(candidate))
            local uncalibrated = bodyMode
                and candidateProfile and not getBodyCameraDelta(candidateProfile)
                or (not bodyMode and source == "auto")
            if candidateIsTunable and (not onlyUncalibrated or uncalibrated) then
                page.scItemSelectedId = candidate.id
                local itemPageSize = page.scItemPageSize or ITEM_PAGE_SIZE
                page.scItemPage = math.floor((index - 1) / itemPageSize) + 1
                page:Refresh()
                return true
            end
        end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前筛选中没有符合条件的镜头条目。")
        end
        return false
    end

    local function formatCameraTuningExportRecord(record, scope, tuningKey, pose)
        if not record or not scope or not tuningKey or not SC.M2Camera
            or not SC.M2Camera.FormatTuningExportRecord then
            return nil
        end
        return SC.M2Camera.FormatTuningExportRecord({
            scope = scope,
            key = tuningKey,
            appearanceId = record.id,
            sourceItemId = record.itemId,
            nativeDisplayId = record.nativeDisplayId,
            syntheticDisplayId = record.syntheticDisplayId,
            modelSignature = record.modelSignature,
            weaponFamily = getWeaponFamilyCameraKey(record),
            weaponType = record.weaponType,
            slot = record.slot,
            metadataVersion = (SC.GeneratedCatalog or {}).metadataVersion,
            assetPackVersion = (SC.GeneratedCatalog or {}).assetPackVersion,
            appearancePresentationHash = (SC.GeneratedCatalog or {}).appearancePresentationHash,
        }, pose)
    end

    local function buildCameraTuningExport(records)
        if not SC.M2Camera or not SC.M2Camera.FormatTuningExportHeader then return "" end
        local generated = SC.GeneratedCatalog or {}
        local lines = {
            SC.M2Camera.FormatTuningExportHeader(
                generated.metadataVersion or "",
                generated.assetPackVersion or "",
                generated.appearancePresentationHash or ""
            ),
        }
        for _, entry in ipairs(records or {}) do
            local line = formatCameraTuningExportRecord(entry.record, entry.scope, entry.key, entry.pose)
            if line then table.insert(lines, line) end
        end
        return table.concat(lines, "\n")
    end

    local function formatBodyCameraTuningExportRecord(profile, delta)
        if not profile or not SC.M2Camera or not SC.M2Camera.FormatBodyTuningExportRecord then
            return nil
        end
        local generated = SC.GeneratedCatalog or {}
        return SC.M2Camera.FormatBodyTuningExportRecord({
            profileKey = profile.profileKey,
            sentinel = profile.sentinel,
            raceToken = profile.raceToken,
            clientAssetProfile = profile.cameraProfile,
            sex = profile.sex,
            slot = profile.slot,
            profileVersion = profile.profileVersion,
            profileHash = profile.profileHash,
            metadataVersion = generated.metadataVersion,
            assetPackVersion = generated.assetPackVersion,
        }, delta)
    end

    local function buildBodyCameraTuningExport(records)
        local first = records and records[1]
        if not first or not first.profile or not SC.M2Camera
            or not SC.M2Camera.FormatBodyTuningExportHeader then
            return ""
        end
        local generated = SC.GeneratedCatalog or {}
        local lines = {
            SC.M2Camera.FormatBodyTuningExportHeader(
                generated.metadataVersion or "",
                generated.assetPackVersion or "",
                first.profile
            ),
        }
        for _, entry in ipairs(records) do
            local line = formatBodyCameraTuningExportRecord(entry.profile, entry.delta)
            if line then table.insert(lines, line) end
        end
        return table.concat(lines, "\n")
    end

    updateCameraTuningExport = function()
        if cameraTuningPanel.scMode == "body" then
            local profile = cameraTuningPanel.scBodyProfile
            local delta = cameraTuningPanel.scBodyDelta
            if not profile or not delta then
                tuningExport:SetText("")
                return
            end
            tuningExport:SetText(buildBodyCameraTuningExport({ { profile = profile, delta = delta } }))
            return
        end
        if not cameraTuningPanel.scRecord or not cameraTuningPanel.scPose
            or not SC.M2Camera or not SC.M2Camera.FormatTuningExportHeader
            or not SC.M2Camera.FormatTuningExportRecord then
            tuningExport:SetText("")
            return
        end
        local record = cameraTuningPanel.scRecord
        local scope = cameraTuningPanel.scScope or "weaponFamily"
        local tuningKey = getCameraTuningScopeKey(record, scope)
        if not tuningKey then
            tuningExport:SetText("")
            return
        end
        tuningExport:SetText(buildCameraTuningExport({ {
            record = record,
            scope = scope,
            key = tuningKey,
            pose = cameraTuningPanel.scPose,
        } }))
    end

    local function setCameraTuningControlsEnabled(enabled)
        local function setWidgetEnabled(widget, value)
            if not widget then return end
            -- WotLK Slider/EditBox widgets inherit EnableMouse but do not all
            -- expose the Button-only Enable/Disable methods. Keep the panel
            -- usable on the stock 3.3.5 UI while still visually disabling
            -- widgets that do support the richer button API.
            if value then
                if widget.Enable then widget:Enable() end
                if widget.EnableMouse then widget:EnableMouse(true) end
            else
                if widget.Disable then widget:Disable() end
                if widget.EnableMouse then widget:EnableMouse(false) end
            end
        end
        local bodyMode = cameraTuningPanel.scMode == "body"
        for _, control in ipairs(cameraTuningPanel.scControls) do
            if control.row then
                if bodyMode then control.row:Hide() else control.row:Show() end
            end
            setWidgetEnabled(control.slider, enabled and not bodyMode)
            setWidgetEnabled(control.value, enabled and not bodyMode)
            for _, button in ipairs(control.buttons) do setWidgetEnabled(button, enabled and not bodyMode) end
        end
        for _, control in ipairs(cameraTuningPanel.scBodyControls) do
            if control.row then
                if bodyMode then control.row:Show() else control.row:Hide() end
            end
            setWidgetEnabled(control.slider, enabled and bodyMode)
            setWidgetEnabled(control.value, enabled and bodyMode)
            for _, button in ipairs(control.buttons) do setWidgetEnabled(button, enabled and bodyMode) end
        end
        setWidgetEnabled(tuningPrevious, enabled)
        setWidgetEnabled(tuningNext, enabled)
        setWidgetEnabled(tuningPreviousUncalibrated, enabled)
        setWidgetEnabled(tuningNextUncalibrated, enabled)
        setWidgetEnabled(tuningReset, enabled)
        setWidgetEnabled(tuningCopy, enabled)
        setWidgetEnabled(tuningBatch, enabled)
        setWidgetEnabled(tuningCopyAll, enabled)
        setWidgetEnabled(tuningDiscard, enabled)
        if bodyMode then tuningScopeDropdown:Hide() else tuningScopeDropdown:Show() end
        tuningScopeDropdown:EnableMouse(enabled and not bodyMode)
    end

    function page:SyncCameraTuningPanel(record)
        if not cameraTuningPanel.scRequested then
            return
        end
        if isBodyCameraTunableRecord(record) then
            local profile = getCharacterCameraProfileForSlot(record.slot)
            if not profile then return end
            cameraTuningPanel.scMode = "body"
            cameraTuningPanel.scRecord = record
            cameraTuningPanel.scBodyProfile = profile
            cameraTuningPanel.scBodyDelta = getBodyCameraDelta(profile)
                or SC.M2Camera.NormalizeBodyDelta({})
            local bodyEnabled, bodyReason = SC.M2Camera.GetBodyProfileCapability(profile)
            cameraTuningPanel.scSyncing = true
            cameraTuningPanel:Show()
            setCameraTuningControlsEnabled(bodyEnabled)
            for _, control in ipairs(cameraTuningPanel.scBodyControls) do
                local value = cameraTuningPanel.scBodyDelta[control.key]
                control.slider:SetValue(value)
                control.value:SetText(string.format("%.2f", value))
            end
            cameraTuningPanel.scSyncing = nil
            tuningTitle:SetText("角色 Profile 相机")
            tuningRecord:SetText("角色相机：" .. (record.name or ("外观 " .. tostring(record.id))))
            local compactHash = string.sub(tostring(profile.profileHash or ""), 1, 16)
            if #(profile.profileHash or "") > #compactHash then compactHash = compactHash .. "..." end
            tuningMetadata:SetText(string.format(
                "%s · sentinel 0x%04X · %s\n%s · profile v%s · %s",
                tostring(profile.profileKey or "未知 profile"),
                tonumber(profile.sentinel) or 0,
                tostring(profile.cameraProfile or "未知资源"),
                tostring(profile.sex or "未知性别"),
                tostring(profile.profileVersion or "?"),
                compactHash
            ))
            if bodyEnabled then
                tuningHint:SetText(next(cameraTuningPanel.scBodySessionBefore)
                    and "当前 profile 有未导出差量；同 profile 的可见护甲会同步更新。"
                    or "调节作用于当前种族/性别/部位 profile，不是单件护甲。导出仅生成待审核候选。")
            else
                tuningHint:SetText("只读：需要匹配的 SoloCam v7 与 profile capability（" .. tostring(bodyReason) .. "）。普通预览保持安全回退。")
            end
            updateCameraTuningExport()
            if cameraTuningButton then cameraTuningButton:SetText("关闭工作台") end
            return
        end
        cameraTuningPanel.scMode = "weapon"
        cameraTuningPanel.scBodyProfile = nil
        cameraTuningPanel.scBodyDelta = nil
        tuningTitle:SetText("武器 M2 相机构图")
        if cameraTuningPanel.scScope == "model" and not getModelCameraKey(record) then
            cameraTuningPanel.scScope = "weaponFamily"
        end
        if not isM2CameraTunableRecord(record) then
            cameraTuningPanel.scRecord = record
            cameraTuningPanel.scPose = nil
            setCameraTuningControlsEnabled(false)
            tuningRecord:SetText(record and (record.name or ("外观 " .. tostring(record.id))) or "请选择一件武器")
            local reason = record and (
                record.presentationReasonCode
                or (record.renderMode == "UNAVAILABLE" and "NO_VERIFIED_STANDALONE_PRESENTATION")
                or record.presentationStatus
            ) or "NO_SELECTION"
            tuningMetadata:SetText("此条目没有可调的 verified standalone 模型。\n原因：" .. tostring(reason or "UNAVAILABLE"))
            tuningHint:SetText("不可用武器只显示资源失败原因；不会把空模型或角色占位当作可调对象。")
            tuningExport:SetText("")
            cameraTuningPanel:Show()
            if cameraTuningButton then cameraTuningButton:SetText("关闭工作台") end
            return
        end
        local pose, editedSource = getTuningPose(record)
        if not pose then return end
        local _, activeSource = resolveM2CameraPose(record)
        cameraTuningPanel.scRecord = record
        cameraTuningPanel.scPose = pose
        cameraTuningPanel.scScope = cameraTuningPanel.scScope or "weaponFamily"
        -- Enabling a stock 3.3.5 slider may emit its current (zero) value.
        -- Enter sync mode before enabling controls, otherwise that framework
        -- event can overwrite the resolved autoCamera pose.
        cameraTuningPanel.scSyncing = true
        -- Show the parent before applying values.  FrameXML children receive
        -- their default-value callbacks as their hidden parent is shown; doing
        -- this first lets the explicit pose writes below win deterministically.
        cameraTuningPanel:Show()
        setCameraTuningControlsEnabled(true)
        UIDropDownMenu_SetSelectedValue(tuningScopeDropdown, cameraTuningPanel.scScope)
        UIDropDownMenu_SetText(tuningScopeDropdown, cameraTuningScopeLabel(cameraTuningPanel.scScope))
        for _, control in ipairs(cameraTuningPanel.scControls) do
            local value = control.targetIndex and pose.target[control.targetIndex] or pose[control.key]
            control.slider:SetValue(value)
            updateTuningValueLabel(control, value)
        end
        cameraTuningPanel.scSyncing = nil
        tuningRecord:SetText("武器类型：" .. (record.weaponTypeLabel or "未分类") .. " · " .. (record.name or ("外观 " .. tostring(record.id))))
        local modelSignature = tostring(record.modelSignature or "未提供")
        local compactModelSignature = string.sub(modelSignature, 1, 16)
        if #modelSignature > #compactModelSignature then compactModelSignature = compactModelSignature .. "..." end
        tuningMetadata:SetText(string.format(
            "外观 %s · Item %s · display %s/%s\nM2 %s · %s · %s",
            tostring(record.id or "?"),
            tostring(record.itemId or "?"),
            tostring(record.nativeDisplayId or "?"),
            tostring(record.syntheticDisplayId or "?"),
            compactModelSignature,
            tostring(getWeaponFamilyCameraKey(record) or "未分类"),
            activeSource == "appearance" and "此外观" or activeSource == "model" and "此模型"
                or activeSource == "generatedModel" and "已审核模型基线"
                or activeSource == "weaponFamily" and "武器类别" or "自动基线"
        ))
        tuningHint:SetText(cameraTuningPanel.scCurrentDirty
            and "当前会话有未导出修改；可加入批次、复制或明确放弃。"
            or "编辑值来源：" .. cameraTuningSourceLabel(editedSource) .. "。数值会立即预览；导出仅生成待审核候选。")
        updateCameraTuningExport()
        if cameraTuningButton then cameraTuningButton:SetText("关闭工作台") end
    end

    function page:ToggleCameraTuning()
        cameraTuningPanel.scRequested = not cameraTuningPanel.scRequested
        self:UpdateCameraWorkbenchLayout()
        if not cameraTuningPanel.scRequested then
            cameraTuningPanel:Hide()
            cameraTuningButton:SetText("镜头工作台")
            self:Refresh()
            return
        end
        self:Refresh()
    end

    tuningClose:SetScript("OnClick", function() page:ToggleCameraTuning() end)

    local function selectCameraTuningExport(text, message)
        tuningExport:SetText(text or "")
        tuningExport:SetFocus()
        tuningExport:HighlightText()
        if DEFAULT_CHAT_FRAME and message then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：" .. message)
        end
    end

    tuningCopy:SetScript("OnClick", function()
        updateCameraTuningExport()
        selectCameraTuningExport(tuningExport:GetText(), "当前镜头 JSONL 记录已选中，可按 Ctrl+C 复制。")
    end)

    tuningBatch:SetScript("OnClick", function()
        if cameraTuningPanel.scMode == "body" then
            local profile = cameraTuningPanel.scBodyProfile
            local delta = profile and getBodyCameraDelta(profile) or nil
            if not profile or not delta then
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前 profile 没有差量 override，无需加入批次。")
                end
                return
            end
            cameraTuningPanel.scBodyBatch[profile.profileKey] = { profile = profile, delta = delta }
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：已加入角色 profile 导出批次。")
            end
            return
        end
        local record = cameraTuningPanel.scRecord
        local scope = cameraTuningPanel.scScope or "weaponFamily"
        local tuningKey = getCameraTuningScopeKey(record, scope)
        if not record or not tuningKey or not SC.CameraTuning or not SC.CameraTuning.Get then return end
        local pose = SC.CameraTuning.Get(scope, tuningKey)
        if not pose then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：当前范围没有差量 override，无需加入批次。")
            end
            return
        end
        local sessionKey = scope .. "\031" .. tuningKey
        cameraTuningPanel.scBatch[sessionKey] = {
            record = record,
            scope = scope,
            key = tuningKey,
            pose = pose,
        }
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：已加入镜头导出批次。")
        end
    end)

    tuningCopyAll:SetScript("OnClick", function()
        if cameraTuningPanel.scMode == "body" then
            local batchKeys = {}
            for batchKey in pairs(cameraTuningPanel.scBodyBatch) do table.insert(batchKeys, batchKey) end
            table.sort(batchKeys)
            if #batchKeys == 0 then
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：本次角色 profile 批次为空。先修改并点击“加入批次”。")
                end
                return
            end
            local records = {}
            for _, batchKey in ipairs(batchKeys) do
                local entry = cameraTuningPanel.scBodyBatch[batchKey]
                if entry then table.insert(records, entry) end
            end
            selectCameraTuningExport(buildBodyCameraTuningExport(records), "本次角色 profile JSONL 已选中，可按 Ctrl+C 复制。")
            return
        end
        local batchKeys = {}
        for batchKey in pairs(cameraTuningPanel.scBatch) do table.insert(batchKeys, batchKey) end
        table.sort(batchKeys)
        if #batchKeys == 0 then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("SoloCollections：本次批次为空。先修改并点击“加入批次”。")
            end
            return
        end
        local records = {}
        for _, batchKey in ipairs(batchKeys) do
            local entry = cameraTuningPanel.scBatch[batchKey]
            if entry then table.insert(records, entry) end
        end
        selectCameraTuningExport(buildCameraTuningExport(records), "本次批量镜头 JSONL 已选中，可按 Ctrl+C 复制。")
    end)

    local function discardUnexportedCameraTuning()
        if cameraTuningPanel.scMode == "body" then
            for profileKey, previous in pairs(cameraTuningPanel.scBodySessionBefore) do
                if SC.BodyCameraTuning then
                    if previous == false then
                        if SC.BodyCameraTuning.Reset then SC.BodyCameraTuning.Reset(profileKey) end
                    elseif SC.BodyCameraTuning.Set then
                        SC.BodyCameraTuning.Set(profileKey, previous)
                    end
                end
            end
            cameraTuningPanel.scBodySessionBefore = {}
            cameraTuningPanel.scBodyBatch = {}
            cameraTuningPanel.scCurrentDirty = nil
            applyBodyCameraTuning(cameraTuningPanel.scBodyProfile)
            page:SyncCameraTuningPanel(cameraTuningPanel.scRecord)
            return
        end
        for sessionKey, previous in pairs(cameraTuningPanel.scSessionBefore) do
            local scope, tuningKey = string.match(sessionKey, "^(.-)\031(.*)$")
            if scope and tuningKey and SC.CameraTuning then
                if previous == false then
                    if SC.CameraTuning.Reset then SC.CameraTuning.Reset(scope, tuningKey) end
                elseif SC.CameraTuning.Set then
                    SC.CameraTuning.Set(scope, tuningKey, previous)
                end
            end
        end
        cameraTuningPanel.scSessionBefore = {}
        cameraTuningPanel.scBatch = {}
        cameraTuningPanel.scCurrentDirty = nil
        applyCameraTuning(cameraTuningPanel.scRecord)
        page:SyncCameraTuningPanel(cameraTuningPanel.scRecord)
    end
    cameraTuningPanel.scDiscardUnexported = discardUnexportedCameraTuning

    tuningDiscard:SetScript("OnClick", function()
        local pending = cameraTuningPanel.scMode == "body"
            and cameraTuningPanel.scBodySessionBefore or cameraTuningPanel.scSessionBefore
        if not next(pending) then return end
        if StaticPopupDialogs then
            if not StaticPopupDialogs.SOLOCOLLECTIONS_CAMERA_DISCARD_V2 then
                StaticPopupDialogs.SOLOCOLLECTIONS_CAMERA_DISCARD_V2 = {
                    text = "放弃本次尚未导出的镜头修改？此操作会恢复打开工作台前的覆盖值。",
                    button1 = "放弃修改",
                    button2 = CANCEL,
                    OnAccept = function(_, data)
                        if data and data.scDiscardUnexported then data.scDiscardUnexported() end
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
            end
            StaticPopup_Show("SOLOCOLLECTIONS_CAMERA_DISCARD_V2", nil, nil, cameraTuningPanel)
        else
            discardUnexportedCameraTuning()
        end
    end)
    tuningReset:SetScript("OnClick", function()
        if cameraTuningPanel.scMode == "body" then
            local profile = cameraTuningPanel.scBodyProfile
            if not profile or not SC.BodyCameraTuning or not SC.BodyCameraTuning.Reset then return end
            SC.BodyCameraTuning.Reset(profile.profileKey)
            applyBodyCameraTuning(profile)
            page:SyncCameraTuningPanel(cameraTuningPanel.scRecord)
            return
        end
        local record = cameraTuningPanel.scRecord
        if not record or not SC.CameraTuning or not SC.CameraTuning.Reset then return end
        local scope = cameraTuningPanel.scScope or "weaponFamily"
        local tuningKey = getCameraTuningScopeKey(record, scope)
        if tuningKey then SC.CameraTuning.Reset(scope, tuningKey) end
        applyCameraTuning(record)
        page:SyncCameraTuningPanel(record)
    end)
    tuningPrevious:SetScript("OnClick", function() navigateCameraTuning(-1, false) end)
    tuningNext:SetScript("OnClick", function() navigateCameraTuning(1, false) end)
    tuningPreviousUncalibrated:SetScript("OnClick", function() navigateCameraTuning(-1, true) end)
    tuningNextUncalibrated:SetScript("OnClick", function() navigateCameraTuning(1, true) end)

    cameraTuningButton = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    cameraTuningButton:SetWidth(92)
    cameraTuningButton:SetHeight(22)
    cameraTuningButton:SetPoint("RIGHT", weaponDropdown, "LEFT", -4, 0)
    cameraTuningButton:SetText("镜头工作台")
    cameraTuningButton:SetScript("OnClick", function() page:ToggleCameraTuning() end)
--]=]

    local function scrollItemPage(delta)
        if not delta or delta == 0 then return end
        local totalPages = page.scItemTotalPages or 1
        if delta > 0 then
            page.scItemPage = math.max(1, (page.scItemPage or 1) - 1)
        else
            page.scItemPage = math.min(totalPages, (page.scItemPage or 1) + 1)
        end
        page:Refresh()
    end

    itemsPanel:SetScript("OnMouseWheel", function(_, delta) scrollItemPage(delta) end)

    page.scItemModels = EzItems:CreateCardPool(itemsPanel, {
        onClick = function(itemModel, button)
            if not itemModel.scRecord then return end
            if button == "RightButton" then
                itemDataProvider:ToggleFavorite(itemModel.scRecord.collectionId)
                page:Refresh()
            elseif IsShiftKeyDown() then
                itemDataProvider:ApplyAppearance(itemModel.scRecord, showAppearanceActionResult)
            else
                selectItem(itemModel.scRecord)
            end
        end,
        onEnter = function(owner, itemModel) showItemTooltip(owner, itemModel.scRecord) end,
        onLeave = function() GameTooltip:Hide() end,
        onMouseWheel = scrollItemPage,
    })
    for _, itemModel in ipairs(page.scItemModels) do
        ItemCardRenderer:Attach(itemModel, itemModel.scObjectModel)
    end

    local function getMaxSetOffset()
        local count = page.scSetRecordCount or 0
        if count <= 0 then return 0 end
        return math.max(0, count - VISIBLE_SET_ROWS)
    end

    setSetOffset = function(value, suppressRefresh)
        local target = math.max(0, math.min(math.floor(tonumber(value) or 0), getMaxSetOffset()))
        local changed = target ~= (page.scSetOffset or 0)
        page.scSetOffset = target
        page.scSetPage = math.floor(target / VISIBLE_SET_ROWS) + 1
        if changed and not suppressRefresh then
            page:Refresh()
        end
        return target
    end

    local function scrollSetList(delta)
        if not delta or delta == 0 then return end
        setSetOffset((page.scSetOffset or 0) + (delta > 0 and -1 or 1))
    end

    local setScrollbar = CreateFrame("Slider", nil, setsPanel)
    setScrollbar:SetWidth(14)
    setScrollbar:SetPoint("TOPRIGHT", setsPanel, "TOPRIGHT", -1, -SET_LIST_TOP_OFFSET)
    setScrollbar:SetPoint("BOTTOMRIGHT", setsPanel, "BOTTOMRIGHT", -1, 37)
    setScrollbar:SetOrientation("VERTICAL")
    setScrollbar:SetMinMaxValues(0, 0)
    setScrollbar:SetValueStep(1)
    setScrollbar:EnableMouseWheel(true)

    local setScrollbarTrack = setScrollbar:CreateTexture(nil, "BACKGROUND")
    setScrollbarTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
    setScrollbarTrack:SetPoint("TOPLEFT", setScrollbar, "TOPLEFT", 4, -1)
    setScrollbarTrack:SetPoint("BOTTOMRIGHT", setScrollbar, "BOTTOMRIGHT", -4, 1)
    setScrollbarTrack:SetVertexColor(0.025, 0.027, 0.030, 0.76)

    local setScrollbarThumb = setScrollbar:CreateTexture(nil, "OVERLAY")
    setScrollbarThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    setScrollbarThumb:SetWidth(16)
    setScrollbarThumb:SetHeight(24)
    setScrollbar:SetThumbTexture(setScrollbarThumb)
    local setScrollbarBorder = UI.CreateThinCardBorder(setScrollbar, 1)
    setScrollbarBorder:SetBorderColor(0.33, 0.34, 0.35, 0.62)
    setScrollbar:SetScript("OnValueChanged", function(self, value)
        if page.scSyncingSetScrollbar then return end
        setSetOffset(value)
    end)
    setScrollbar:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)
    setScrollbar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("套装列表", 1.00, 0.82, 0.18)
        GameTooltip:AddLine("拖动滚动条或使用鼠标滚轮浏览。", 0.82, 0.78, 0.70, true)
        GameTooltip:Show()
    end)
    setScrollbar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    setScrollbar:Hide()

    setsPanel:EnableMouseWheel(true)
    setsPanel:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)

    for index = 1, VISIBLE_SET_ROWS do
        local row = createSetListRow(setsPanel, 330, function(_, record, button)
            if not record then return end
            local concreteRecord = concreteSetRecord(record)
            if not concreteRecord then return end
            if button == "RightButton" then
                Catalog.ToggleDemoFavorite("SETS", concreteRecord.id)
                page:Refresh()
            elseif IsShiftKeyDown() then
                if not concreteRecord.collected then
                    showSetActionResult(false, "NOT_OWNED")
                elseif not SC.Bridge or not SC.Bridge.ApplySet then
                    showSetActionResult(false, "BRIDGE_UNAVAILABLE")
                else
                    local variant = concreteRecord.selectedVariant
                    SC.Bridge.ApplySet(concreteRecord.id, variant and variant.variantOrdinal or nil, showSetActionResult)
                end
            else
                selectSetDisplayRecord(record)
            end
        end)
        row:SetPoint("TOPLEFT", setsPanel, "TOPLEFT", 3, -SET_LIST_TOP_OFFSET - ((index - 1) * (SET_ROW_HEIGHT + SET_ROW_SPACING)))
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) scrollSetList(delta) end)
        row:SetScript("OnEnter", function(self)
            local record = self.scRecord
            if not record then return end
            local owned = tonumber(record.collectedCount) or 0
            local required = tonumber(record.requiredCount) or #(record.itemIds or {})
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local concreteRecord = concreteSetRecord(record)
            local red, green, blue = setRecordQualityColor(concreteRecord)
            GameTooltip:SetText(setDisplayName(record), red, green, blue)
            local presentationLabel = setPresentationLabel(concreteRecord)
            if presentationLabel then
                GameTooltip:AddLine("分类：" .. presentationLabel, 0.95, 0.82, 0.36)
            end
            local categoryLabel = setRecordCategoryLabel(concreteRecord)
            if categoryLabel and not setRecordIsClassSpecific(concreteRecord) then
                GameTooltip:AddLine("类型：" .. categoryLabel, 0.82, 0.78, 0.70)
            else
                GameTooltip:AddLine("职业：" .. setClassLabel(concreteRecord), 0.82, 0.78, 0.70)
            end
            local specLabel = setRecordSpecLabel(concreteRecord)
            if specLabel then
                GameTooltip:AddLine("适用专精：" .. specLabel, 0.52, 0.82, 1.00, true)
            end
            GameTooltip:AddLine("来源：" .. setRecordSourceLabel(concreteRecord), 0.94, 0.82, 0.58, true)
            if record.scIsSetGroup then
                local variantCount = record.scVariants and #record.scVariants or 0
                GameTooltip:AddLine("已折叠 " .. tostring(variantCount) .. " 个阵营版本；右下角下拉切换联盟/部落。", 0.78, 0.74, 0.64, true)
                for _, variantRecord in ipairs(record.scVariants or {}) do
                    GameTooltip:AddLine("· " .. setVariantLabel(variantRecord) .. "：" .. tostring(variantRecord.name or "未知版本"), 0.65, 0.78, 0.92, true)
                end
            end
            GameTooltip:AddLine("收集进度：" .. owned .. " / " .. required, 0.45, 0.90, 0.34)
            GameTooltip:AddLine("左键选择 · Shift+左键应用当前版本 · 右键偏好", 0.78, 0.74, 0.64)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.scSetRows[index] = row
    end

    local itemControls = UI.CreatePageControls(itemsPanel, function()
        page.scItemPage = math.max(1, page.scItemPage - 1)
        page:Refresh()
    end, function()
        page.scItemPage = math.min(page.scItemTotalPages or 1, page.scItemPage + 1)
        page:Refresh()
    end)
    itemControls:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 22, 38)

    local setControls = UI.CreatePageControls(setsPanel, function()
        setSetOffset((page.scSetOffset or 0) - VISIBLE_SET_ROWS)
    end, function()
        setSetOffset((page.scSetOffset or 0) + VISIBLE_SET_ROWS)
    end)
    setControls:SetPoint("BOTTOM", setsPanel, "BOTTOM", 0, 5)
    setControls:SetFrameLevel(preview:GetFrameLevel() + 1)

    local itemEmpty = UI.CreateEmptyState(itemsPanel, "没有符合条件的外观")
    itemEmpty:SetPoint("CENTER", itemsPanel, "CENTER", 0, 20)
    itemEmpty:Hide()
    local setEmpty = UI.CreateEmptyState(setsPanel, "没有符合条件的套装")
    setEmpty:SetPoint("CENTER", setsPanel, "CENTER", 0, 20)
    setEmpty:Hide()

    function page:ClearSelection()
        cancelSetPreview()
        self.scItemSelectedId = nil
        self.scSetSelectedId = nil
        self.scSetSelectedGroupKey = nil
        self.scSetSelectedRecord = nil
        self.scSetSelectedDisplayRecord = nil
        applySet:Disable()
        for _, itemModel in ipairs(self.scItemModels) do
            itemModel.scSelected:Hide()
        end
        for _, row in ipairs(self.scSetRows) do row:SetSelected(false) end
        name:SetText("")
        name:Show()
        longName:SetText("")
        longName:Hide()
        detail:SetText("")
        setProgress:Hide()
        pieces:Hide()
        syncSetVariantDropdown(nil, nil)
        clearDragState()
        model:ClearModel()
        GameTooltip:Hide()
    end

    function page:SyncDedicatedFilters()
        if not SC.db or not SC.db.filters then return end
        local filters = SC.db.filters

        -- On the first set-page visit, mirror Retail by starting on the
        -- character's own class. Afterwards an explicit "全部职业" choice is
        -- respected for the rest of the UI session.
        if SC.db.wardrobeTab == "SETS" and not self.scDefaultSetClassApplied then
            self.scDefaultSetClassApplied = true
            local playerClass = getPlayerClassToken()
            if hasFilterValue(CLASS_FILTERS, playerClass) then
                filters.classToken = playerClass
                setSetOffset(0, true)
                self.scSetSelectedId = nil
                self.scSetSelectedGroupKey = nil
            end
        end

        local storedArmorType, effectiveArmorType = itemDataProvider:GetArmorState()
        if filters.armorType ~= storedArmorType then filters.armorType = storedArmorType end
        if filters.slot == "ALL" or not page.scSlotButtons[filters.slot] then
            filters.slot = "HEAD"
        end

        UIDropDownMenu_SetSelectedValue(armorDropdown, effectiveArmorType)
        UIDropDownMenu_SetText(armorDropdown, filterLabel(ARMOR_TYPE_FILTERS, effectiveArmorType))
        UIDropDownMenu_SetSelectedValue(classDropdown, filters.classToken)
        UIDropDownMenu_SetText(classDropdown, filterLabel(CLASS_FILTERS, filters.classToken))

        for slotKey, button in pairs(page.scSlotButtons) do
            if slotKey == filters.slot then
                button.scSelected:Show()
            else
                button.scSelected:Hide()
            end
        end

        if SC.db.wardrobeTab == "ITEMS" then
            armorDropdown:Show()
            classDropdown:Hide()
            slotsFrame:Show()
            if STANDALONE_ITEM_SLOTS[filters.slot] then
                ensureWeaponTypeForSlot(filters, filters.slot)
                UIDropDownMenu_SetSelectedValue(weaponDropdown, filters.weaponType)
                UIDropDownMenu_SetText(weaponDropdown, filterLabel(getAvailableWeaponFilters(filters.slot), filters.weaponType))
                weaponDropdown:Show()
            else
                weaponDropdown:Hide()
            end
        else
            armorDropdown:Hide()
            classDropdown:Show()
            slotsFrame:Hide()
            weaponDropdown:Hide()
        end
    end

    function page:SyncFilters()
        local frame = UI.CollectionsFrame
        if not frame or not frame.scWardrobeFilterDropDown or not SC.db or SC.db.mainTab ~= "WARDROBE" then return end
        local filters = SC.db.filters
        local dropDown = frame.scWardrobeFilterDropDown
        if frame.scFilterPopup then frame.scFilterPopup:Hide() end
        if dropDown.scSoloCollectionsInitialized then return end

        local function setFilter(key, value)
            filters[key] = value and true or false
            self.scItemPage = 1
            setSetOffset(0, true)
            self:Refresh()
        end

        UIDropDownMenu_Initialize(dropDown, function(_, level)
            if level ~= 1 then return end
            local options = {
                { label = "已收集", key = "collected" },
                { label = "未收集", key = "uncollected" },
                { label = "仅显示偏好", key = "favorites" },
            }
            for _, option in ipairs(options) do
                local optionKey = option.key
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.label
                info.keepShownOnClick = true
                info.isNotRadio = true
                info.checked = function() return filters[optionKey] and true or false end
                info.func = function(_, _, _, checked) setFilter(optionKey, checked) end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        dropDown.scSoloCollectionsInitialized = true
    end

    local function refreshItems()
        EzItems:ApplyJournalChrome()
        cancelSetPreview()
        page.scRuntimeAuditActive = nil
        page.scItemGeneration = (page.scItemGeneration or 0) + 1
        local pageGeneration = page.scItemGeneration
        itemsPanel:Show()
        setsPanel:Hide()
        preview:Hide()
        local itemPageSize = page.scItemPageSize or ITEM_PAGE_SIZE
        local records, currentPage, totalPages = wardrobeFilters:QueryItems(page.scItemPage, itemPageSize)
        page.scItemPage = currentPage
        page.scItemTotalPages = totalPages
        itemControls:SetPage(currentPage, totalPages)
        local selected
        for index, itemModel in ipairs(page.scItemModels) do
            local record = records[index]
            applyItemModelRecord(itemModel, record, pageGeneration)
            EzItems:UpdateCardState(itemModel, page.scItemSelectedId)
            if record and record.id == page.scItemSelectedId then selected = record end
        end
        local collected, total = itemDataProvider:GetProgress()
        page.scItemCollected = collected
        page.scItemTotal = total
        page.scItemRevision = itemDataProvider:GetRevision()
        if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(collected, total) end
        if #records == 0 then
            UI.ShowEmptyState(itemEmpty, page, "没有符合条件的外观", "调整搜索、护甲类型、部位或武器类型后再试。")
        else
            UI.HideEmptyState(itemEmpty)
            selectItem(selected or records[1])
        end
    end

    -- The temporary runtime-audit AddOn uses this narrow entry point to drive
    -- the production 18-card pool without changing filters, collection state,
    -- or any persisted UI setting.  It deliberately delegates to the same
    -- applyItemModelRecord path as refreshItems, so the audit observes the same
    -- DressUpModel/preview-Creature route rather than a second renderer.
    function page:LoadRuntimeAuditAppearanceRecords(records)
        records = records or {}
        if #records > #self.scItemModels then
            return nil, "AUDIT_RECORD_COUNT_EXCEEDS_CARD_POOL"
        end

        cancelSetPreview()
        self.scRuntimeAuditActive = true
        self.scItemGeneration = (self.scItemGeneration or 0) + 1
        local pageGeneration = self.scItemGeneration
        self.scItemSelectedId = nil
        self.scItemPage = 1
        self.scItemTotalPages = 1
        itemsPanel:Show()
        setsPanel:Hide()
        preview:Hide()
        itemControls:SetPage(1, 1)

        local visible = 0
        for index, itemModel in ipairs(self.scItemModels) do
            local record = records[index]
            applyItemModelRecord(itemModel, record, pageGeneration)
            if record then
                visible = visible + 1
            end
            EzItems:UpdateCardState(itemModel, nil)
        end

        if visible == 0 then
            UI.ShowEmptyState(itemEmpty, page, "没有可审计的外观", "运行时审计未收到公开外观记录。")
        else
            UI.HideEmptyState(itemEmpty)
        end
        return pageGeneration, visible
    end

    local function refreshSets()
        itemsPanel:Hide()
        -- Release the pooled ez model lifecycle when the set page takes over.
        -- Returning to items will rebuild the correct player/weapon actor,
        -- redress the record, and then reapply its camera tuple.
        for _, itemModel in ipairs(page.scItemModels) do
            ItemCardRenderer:Clear(itemModel)
        end
        setsPanel:Show()
        preview:Show()
        local allRecords, setFilters = wardrobeFilters:QuerySets()
        allRecords = allRecords or {}
        page.scFlatSetRecordCount = #allRecords
        page.scSetRecordCount = #allRecords
        local maxOffset = #allRecords > 0
            and math.max(0, #allRecords - VISIBLE_SET_ROWS) or 0
        setSetOffset(page.scSetOffset, true)

        local records = {}
        local firstIndex = page.scSetOffset + 1
        local lastIndex = math.min(#allRecords, firstIndex + VISIBLE_SET_ROWS - 1)
        for index = firstIndex, lastIndex do
            table.insert(records, allRecords[index])
        end

        local totalPages = math.max(1, math.ceil(#allRecords / VISIBLE_SET_ROWS))
        local currentPage = math.max(1, math.min(totalPages, math.ceil((page.scSetOffset + VISIBLE_SET_ROWS) / VISIBLE_SET_ROWS)))
        page.scSetPage = currentPage
        page.scSetTotalPages = totalPages
        setControls:SetPage(currentPage, totalPages)

        page.scSyncingSetScrollbar = true
        setScrollbar:SetMinMaxValues(0, maxOffset)
        setScrollbar:SetValue(page.scSetOffset)
        setScrollbar:SetAlpha(maxOffset > 0 and 1.00 or 0.28)
        page.scSyncingSetScrollbar = nil

        local selected
        local selectedKey = page.scSetSelectedGroupKey
        for _, record in ipairs(allRecords) do
            local concreteRecord = concreteSetRecord(record)
            if setRecordSelectionKey(record) == selectedKey or
                (concreteRecord and concreteRecord.id == page.scSetSelectedId) then
                selected = record
                break
            end
        end
        for index, row in ipairs(page.scSetRows) do
            local record = records[index]
            row:SetRecord(record)
            row:SetSelected(record and setRecordSelectionKey(record) == selectedKey)
        end
        local collected, total = Catalog.GetProgress("SETS", setFilters)
        if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(collected, total) end
        if #records == 0 then
            page.scSetSelectedId = nil
            page.scSetSelectedGroupKey = nil
            page.scSetSelectedRecord = nil
            page.scSetSelectedDisplayRecord = nil
            applySet:Disable()
            pieces:Hide()
            setProgress:Hide()
            syncSetVariantDropdown(nil, nil)
            model:ClearModel()
            UI.ShowEmptyState(setEmpty, page, "没有符合条件的套装", "调整搜索或职业过滤后再试。")
        else
            UI.HideEmptyState(setEmpty)
            local record = selected or records[1] or allRecords[1]
            selectSetDisplayRecord(record)
        end
    end

    function page:Refresh()
        if not SC.db then return end
        self.scRuntimeAuditActive = nil
        self:SyncDedicatedFilters()
        if SC.db.wardrobeTab == "ITEMS" then
            refreshItems()
        elseif SC.db.wardrobeTab == "SETS" then
            refreshSets()
        end
        self:SyncFilters()
    end

    function page:ApplyAppearanceCollectionChange(change)
        if not change or change.kind ~= "DELTA" or not change.collectionId then return false end
        if self.scRuntimeAuditActive then return true end
        if self:IsShown() and SC.db and SC.db.wardrobeTab == "SETS" then
            -- Set completeness is derived from appearance ownership; let the
            -- existing active-page refresh update the unchanged Sets view.
            return false
        end

        local collected = itemDataProvider:IsOwned(change.collectionId, change.operation == "A")
        local filters = SC.db and SC.db.filters or nil
        local ownershipChangesMembership = filters and not (filters.collected and filters.uncollected)
        if self:IsShown() and SC.db and SC.db.wardrobeTab == "ITEMS" then
            if ownershipChangesMembership then
                -- Rebind the same 18-frame pool because an exclusive ownership
                -- filter can add/remove a row; unchanged records skip Reload.
                refreshItems()
            else
                EzItems:ApplyCollectionDelta(self.scItemModels, change.collectionId, collected, self.scItemSelectedId)
                local owned, total = itemDataProvider:GetProgress()
                self.scItemCollected = owned
                self.scItemTotal = total
                self.scItemRevision = change.revision
                if UI.CollectionsFrame then UI.CollectionsFrame.scProgress:SetProgress(owned, total) end
            end
        end
        return true
    end

    if SC.Bridge and type(SC.Bridge.RegisterStateListener) == "function" then
        page.scBridgeStateListener = SC.Bridge.RegisterStateListener(function(_, typeId, change)
            local appearanceTypeId = itemDataProvider:GetAppearanceTypeId()
            if appearanceTypeId and tonumber(typeId) == tonumber(appearanceTypeId) and change and change.kind == "DELTA" then
                return page:ApplyAppearanceCollectionChange(change)
            end
            return false
        end)
    end

    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:RegisterEvent("PLAYER_ENTERING_WORLD")
    page:RegisterEvent("UNIT_MODEL_CHANGED")
    page:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            cancelSetPreview()
            if self:IsShown() and SC.db and SC.db.wardrobeTab == "SETS" then
                self:Refresh()
            end
            return
        end
        if event == "UNIT_MODEL_CHANGED" then
            local unit = ...
            if unit == "player" then
                cancelSetPreview()
                if self:IsShown() and SC.db and SC.db.wardrobeTab == "SETS" then
                    self:Refresh()
                end
            end
            return
        end
        if not self:IsShown() then return end
        if self.scRuntimeAuditActive then return end
        local itemId, success = ...
        if success == false or not itemId then return end
        itemId = tonumber(itemId) or itemId

        for _, itemModel in ipairs(self.scItemModels) do
            if itemModel.scCard and itemModel.scCard:IsShown()
                and itemModel.scRecord and itemModel.scRecord.itemId == itemId then
                -- TransmorpherItemQuery owns readiness for every item card and
                -- feeds the shared generation-safe render queue. Replaying a
                -- cached armor or weapon page here would collapse 18 exact
                -- Reset/Undress/TryOn lifecycles back into one frame.
                if itemModel.scRenderKind ~= "TRANSMORPHER_ARMOR"
                    and itemModel.scRenderKind ~= "TRANSMORPHER_WEAPON" then
                    applyItemModelRecord(itemModel, itemModel.scRecord, self.scItemGeneration, true)
                end
                if itemModel.scHitFrame and GameTooltip:IsOwned(itemModel.scHitFrame) then
                    showItemTooltip(itemModel.scHitFrame, itemModel.scRecord)
                end
            end
        end

        for _, piece in ipairs(self.scPieceIcons) do
            if piece:IsShown() and piece.scItemId == itemId then
                updateSetPieceVisual(piece, itemId, appearanceState[itemId] and true or false)
                if GameTooltip:IsOwned(piece) then
                    showPieceTooltip(piece, itemId, piece.scSetRecord, piece.scPreviewItem, piece.scSetDisplayRecord)
                end
            end
        end
    end)
    page:SetScript("OnHide", function(self)
        self.scRuntimeAuditActive = nil
        self:ClearSelection()
        self.scItemPage = 1
        setSetOffset(0, true)
        self.scSetRecordCount = 0
        for _, itemModel in ipairs(self.scItemModels) do
            ItemCardRenderer:Clear(itemModel)
        end
        model:ClearModel()
        GameTooltip:Hide()
    end)

    page.scModel = model
    page.scItemsPanel = itemsPanel
    page.scSetsPanel = setsPanel
    page.scItemsBackground = itemsInset.background
    page.scSetsBackground = setsInset.background
    page.scSetDetail = preview
    page.scItemControls = itemControls
    page.scSetControls = setControls
    page.scSetScrollbar = setScrollbar
    page.scArmorDropdown = armorDropdown
    page.scClassDropdown = classDropdown
    page.scWeaponDropdown = weaponDropdown
    page.scSlotsFrame = slotsFrame
    return page
end
