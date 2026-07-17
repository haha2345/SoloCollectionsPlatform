local SC = SoloCollections

-- 独立武器均以各自的 M2 camera 0 为基准。以下 pose 是运行时相机偏移，
-- 不修改 M2 文件，也不旋转武器网格。已确认的数值来自游戏内逐类校准；
-- 未校准类别则使用最接近已确认类别推导出的首轮构图，仍可在“调相机”中继续微调。
--
-- 字段说明：yaw 决定正反面/两端落点，pitch 改变俯仰，roll 改变画面内斜率，
-- distanceScale 决定远近，target 是 M2 本地坐标中的平移 { x, y, z }。
local WEAPON_M2_CAMERA = {
    -- 已由玩家在游戏内确认。
    WAR_GLAIVE_MAINHAND = { yaw = 0.76, pitch = -0.63, roll = 1.24, distanceScale = 0.52, target = { -0.18, -0.26, 0.00 } },
    WAR_GLAIVE_OFFHAND = { yaw = -1.93, pitch = -0.82, roll = 1.38, distanceScale = 1.34, target = { 0.09, -0.09, 0.00 } },
    TWO_HAND_SWORD = { yaw = 1.04, pitch = -0.18, roll = 0.97, distanceScale = 0.72, target = { -0.44, 0.00, 0.00 } },
    ONE_HAND_AXE = { yaw = 0.90, pitch = -0.69, roll = 1.45, distanceScale = 0.68, target = { -0.18, -0.18, 0.00 } },
    TWO_HAND_MACE = { yaw = 0.00, pitch = 0.84, roll = 0.00, distanceScale = 0.89, target = { -0.18, 0.00, 0.00 } },
    ONE_HAND_MACE = { yaw = 0.00, pitch = 1.20, roll = 0.00, distanceScale = 0.68, target = { -0.09, 0.00, 0.00 } },
    CROSSBOW = { yaw = 0.00, pitch = 0.84, roll = 0.00, distanceScale = 0.77, target = { -0.18, 0.00, 0.00 } },
    FIST_WEAPON = { yaw = 1.18, pitch = -0.90, roll = -1.52, distanceScale = 0.64, target = { 0.00, -0.26, 0.09 } },
    DAGGER = { yaw = 1.04, pitch = -0.74, roll = 1.52, distanceScale = 0.77, target = { -0.18, 0.00, 0.00 } },
    STAFF = { yaw = 1.24, pitch = -0.71, roll = -1.45, distanceScale = 0.25, target = { 0.35, 0.09, 0.00 } },
    WAND = { yaw = 1.38, pitch = -0.82, roll = -1.17, distanceScale = 0.56, target = { 0.00, -0.18, 0.00 } },

    -- 尚未逐类人工确认：按外形与已确认类别推导的首轮参数。
    TWO_HAND_AXE = { yaw = 1.00, pitch = -0.32, roll = 0.96, distanceScale = 0.72, target = { -0.35, -0.05, 0.00 } },
    BOW = { yaw = 0.90, pitch = -0.55, roll = 1.00, distanceScale = 0.74, target = { -0.15, -0.08, 0.00 } },
    GUN = { yaw = 0.92, pitch = -0.48, roll = 1.06, distanceScale = 0.72, target = { -0.18, -0.05, 0.00 } },
    POLEARM = { yaw = 1.20, pitch = -0.70, roll = -1.42, distanceScale = 0.42, target = { 0.25, 0.08, 0.00 } },
    ONE_HAND_SWORD = { yaw = 1.02, pitch = -0.58, roll = 1.35, distanceScale = 0.70, target = { -0.20, -0.05, 0.00 } },
    THROWN = { yaw = 1.00, pitch = -0.70, roll = 1.45, distanceScale = 0.72, target = { -0.12, -0.05, 0.00 } },
    FISHING_POLE = { yaw = 1.22, pitch = -0.70, roll = -1.45, distanceScale = 0.34, target = { 0.30, 0.08, 0.00 } },
    SHIELD = { yaw = 0.42, pitch = 0.20, roll = 0.25, distanceScale = 0.78, target = { -0.10, 0.00, 0.00 } },
}

SC.Data.Appearances = {
    { id = 1, itemId = 16802, slot = "WAIST", classMask = 128, name = "奥术师腰带", icon = "Interface\\Icons\\INV_Belt_30", source = "熔火之心", collected = true, favorite = true },
    { id = 2, itemId = 16799, slot = "WRIST", classMask = 128, name = "奥术师护腕", icon = "Interface\\Icons\\INV_Belt_29", source = "熔火之心", collected = false, favorite = false },
    { id = 3, itemId = 16795, slot = "HEAD", classMask = 128, name = "奥术师头冠", icon = "Interface\\Icons\\INV_Helmet_53", source = "熔火之心", collected = true, favorite = false },
    { id = 4, itemId = 16800, slot = "FEET", classMask = 128, name = "奥术师便鞋", icon = "Interface\\Icons\\INV_Boots_07", source = "熔火之心", collected = true, favorite = false },
    { id = 5, itemId = 16801, slot = "HANDS", classMask = 128, name = "奥术师手套", icon = "Interface\\Icons\\INV_Gauntlets_14", source = "熔火之心", collected = false, favorite = true },
    { id = 6, itemId = 16796, slot = "LEGS", classMask = 128, name = "奥术师护腿", icon = "Interface\\Icons\\INV_Pants_08", source = "熔火之心", collected = true, favorite = false },
    { id = 7, itemId = 16806, slot = "WAIST", classMask = 256, name = "恶魔之心腰带", icon = "Interface\\Icons\\INV_Belt_13", source = "熔火之心", collected = false, favorite = false },
    { id = 8, itemId = 16804, slot = "WRIST", classMask = 256, name = "恶魔之心护腕", icon = "Interface\\Icons\\INV_Bracer_07", source = "熔火之心", collected = true, favorite = false },
    { id = 9, itemId = 16805, slot = "HANDS", classMask = 256, name = "恶魔之心手套", icon = "Interface\\Icons\\INV_Gauntlets_19", source = "熔火之心", collected = true, favorite = true },
    { id = 10, itemId = 16810, slot = "LEGS", classMask = 256, name = "恶魔之心短裤", icon = "Interface\\Icons\\INV_Pants_Cloth_14", source = "熔火之心", collected = false, favorite = false },
    { id = 11, itemId = 16809, slot = "CHEST", classMask = 256, name = "恶魔之心长袍", icon = "Interface\\Icons\\INV_Chest_Cloth_09", source = "熔火之心", collected = true, favorite = false },
    { id = 12, itemId = 16807, slot = "SHOULDER", classMask = 256, name = "恶魔之心护肩", icon = "Interface\\Icons\\INV_Shoulder_23", source = "熔火之心", collected = false, favorite = true },
    { id = 13, itemId = 16827, slot = "WAIST", classMask = 8, name = "夜幕杀手腰带", icon = "Interface\\Icons\\INV_Belt_23", source = "熔火之心", collected = true, favorite = false },
    { id = 14, itemId = 16824, slot = "FEET", classMask = 8, name = "夜幕杀手长靴", icon = "Interface\\Icons\\INV_Boots_08", source = "熔火之心", collected = false, favorite = false },
    { id = 15, itemId = 16825, slot = "WRIST", classMask = 8, name = "夜幕杀手护腕", icon = "Interface\\Icons\\INV_Bracer_02", source = "熔火之心", collected = true, favorite = false },
    { id = 16, itemId = 16820, slot = "CHEST", classMask = 8, name = "夜幕杀手胸甲", icon = "Interface\\Icons\\INV_Chest_Cloth_07", source = "熔火之心", collected = true, favorite = true },
    { id = 17, itemId = 16821, slot = "HEAD", classMask = 8, name = "夜幕杀手头巾", icon = "Interface\\Icons\\INV_Helmet_41", source = "熔火之心", collected = false, favorite = true },
    { id = 18, itemId = 16826, slot = "HANDS", classMask = 8, name = "夜幕杀手手套", icon = "Interface\\Icons\\INV_Gauntlets_21", source = "熔火之心", collected = true, favorite = false },
    { id = 19, itemId = 16828, slot = "WAIST", classMask = 1024, name = "塞纳里奥腰带", icon = "Interface\\Icons\\INV_Belt_06", source = "熔火之心", collected = true, favorite = false },
    { id = 20, itemId = 16829, slot = "FEET", classMask = 1024, name = "塞纳里奥长靴", icon = "Interface\\Icons\\INV_Boots_08", source = "熔火之心", collected = false, favorite = false },
    { id = 21, itemId = 16830, slot = "WRIST", classMask = 1024, name = "塞纳里奥护腕", icon = "Interface\\Icons\\INV_Bracer_03", source = "熔火之心", collected = true, favorite = true },
    { id = 22, itemId = 16833, slot = "CHEST", classMask = 1024, name = "塞纳里奥胸甲", icon = "Interface\\Icons\\INV_Chest_Cloth_06", source = "熔火之心", collected = false, favorite = false },
    { id = 23, itemId = 16831, slot = "HANDS", classMask = 1024, name = "塞纳里奥手套", icon = "Interface\\Icons\\INV_Gauntlets_07", source = "熔火之心", collected = true, favorite = false },
    { id = 24, itemId = 16834, slot = "HEAD", classMask = 1024, name = "塞纳里奥头盔", icon = "Interface\\Icons\\INV_Helmet_09", source = "熔火之心", collected = false, favorite = true },
    { id = 25, itemId = 16851, slot = "WAIST", classMask = 4, name = "巨人追猎者腰带", icon = "Interface\\Icons\\INV_Belt_28", source = "熔火之心", collected = true, favorite = false },
    { id = 26, itemId = 16849, slot = "FEET", classMask = 4, name = "巨人追猎者长靴", icon = "Interface\\Icons\\INV_Boots_Chain_13", source = "熔火之心", collected = false, favorite = false },
    { id = 27, itemId = 16850, slot = "WRIST", classMask = 4, name = "巨人追猎者护腕", icon = "Interface\\Icons\\INV_Bracer_17", source = "熔火之心", collected = true, favorite = false },
    { id = 28, itemId = 16845, slot = "CHEST", classMask = 4, name = "巨人追猎者胸甲", icon = "Interface\\Icons\\INV_Chest_Chain_03", source = "熔火之心", collected = true, favorite = true },
    { id = 29, itemId = 16848, slot = "SHOULDER", classMask = 4, name = "巨人追猎者肩饰", icon = "Interface\\Icons\\INV_Shoulder_10", source = "熔火之心", collected = false, favorite = false },
    { id = 30, itemId = 16852, slot = "HANDS", classMask = 4, name = "巨人追猎者手套", icon = "Interface\\Icons\\INV_Gauntlets_10", source = "熔火之心", collected = true, favorite = true },
    { id = 31, itemId = 16838, slot = "WAIST", classMask = 64, name = "大地之怒腰带", icon = "Interface\\Icons\\INV_Belt_14", source = "熔火之心", collected = false, favorite = false },
    { id = 32, itemId = 16837, slot = "FEET", classMask = 64, name = "大地之怒长靴", icon = "Interface\\Icons\\INV_Boots_Plate_06", source = "熔火之心", collected = true, favorite = false },
    { id = 33, itemId = 16840, slot = "WRIST", classMask = 64, name = "大地之怒护腕", icon = "Interface\\Icons\\INV_Bracer_16", source = "熔火之心", collected = true, favorite = true },
    { id = 34, itemId = 16841, slot = "CHEST", classMask = 64, name = "大地之怒外衣", icon = "Interface\\Icons\\INV_Chest_Chain_11", source = "熔火之心", collected = false, favorite = false },
    { id = 35, itemId = 16844, slot = "SHOULDER", classMask = 64, name = "大地之怒肩饰", icon = "Interface\\Icons\\INV_Shoulder_29", source = "熔火之心", collected = true, favorite = false },
    { id = 36, itemId = 16839, slot = "HANDS", classMask = 64, name = "大地之怒护手", icon = "Interface\\Icons\\INV_Gauntlets_11", source = "熔火之心", collected = false, favorite = true },
    { id = 37, itemId = 16858, slot = "WAIST", classMask = 2, name = "秩序之源腰带", icon = "Interface\\Icons\\INV_Belt_27", source = "熔火之心", collected = true, favorite = false },
    { id = 38, itemId = 16859, slot = "FEET", classMask = 2, name = "秩序之源战靴", icon = "Interface\\Icons\\INV_Boots_Plate_09", source = "熔火之心", collected = false, favorite = false },
    { id = 39, itemId = 16857, slot = "WRIST", classMask = 2, name = "秩序之源护腕", icon = "Interface\\Icons\\INV_Bracer_18", source = "熔火之心", collected = true, favorite = true },
    { id = 40, itemId = 16853, slot = "CHEST", classMask = 2, name = "秩序之源胸甲", icon = "Interface\\Icons\\INV_Chest_Plate03", source = "熔火之心", collected = true, favorite = false },
    { id = 41, itemId = 16860, slot = "HANDS", classMask = 2, name = "秩序之源护手", icon = "Interface\\Icons\\INV_Gauntlets_29", source = "熔火之心", collected = false, favorite = false },
    { id = 42, itemId = 16854, slot = "HEAD", classMask = 2, name = "秩序之源头盔", icon = "Interface\\Icons\\INV_Helmet_05", source = "熔火之心", collected = true, favorite = true },
    { id = 43, itemId = 16864, slot = "WAIST", classMask = 1, name = "力量腰带", icon = "Interface\\Icons\\INV_Belt_09", source = "熔火之心", collected = false, favorite = false },
    { id = 44, itemId = 16861, slot = "WRIST", classMask = 1, name = "力量护腕", icon = "Interface\\Icons\\INV_Bracer_19", source = "熔火之心", collected = true, favorite = false },
    { id = 45, itemId = 16865, slot = "CHEST", classMask = 1, name = "力量胸甲", icon = "Interface\\Icons\\INV_Chest_Plate16", source = "熔火之心", collected = true, favorite = true },
    { id = 46, itemId = 16863, slot = "HANDS", classMask = 1, name = "力量护手", icon = "Interface\\Icons\\INV_Gauntlets_10", source = "熔火之心", collected = false, favorite = false },
    { id = 47, itemId = 16866, slot = "HEAD", classMask = 1, name = "力量头盔", icon = "Interface\\Icons\\INV_Helmet_09", source = "熔火之心", collected = true, favorite = true },
    { id = 48, itemId = 16867, slot = "LEGS", classMask = 1, name = "力量腿铠", icon = "Interface\\Icons\\INV_Pants_04", source = "熔火之心", collected = false, favorite = false },
    { id = 49, itemId = 17102, slot = "BACK", classMask = 2047, name = "雾影斗篷", icon = "Interface\\Icons\\INV_Misc_Cape_17", source = "熔火之心", collected = true, favorite = false },

    -- WotLK has no Retail SetItemAppearance API. These records use client-only
    -- CreatureDisplayInfo rows so PlayerModel can bind the original weapon skin.
    -- Standalone cards now control M2 camera 0 through SC.M2Camera instead of
    -- rotating the mesh. Every source M2 shares the same camera-space view;
    -- per-type corrections can override m2Camera without rebuilding an MPQ.
    { id = 50, itemId = 19364, slot = "MAINHAND", classMask = 2047, name = "阿什坎迪，兄弟会之剑", icon = "Interface\\Icons\\INV_Sword_50", source = "黑翼之巢", collected = true, favorite = true, weaponType = "TWO_HAND_SWORD", weaponTypeLabel = "双手剑", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Sword_2H_Blackwing_A_02_19364.m2", modelScale = 0.82, m2Camera = WEAPON_M2_CAMERA.TWO_HAND_SWORD },
    { id = 51, itemId = 19019, slot = "MAINHAND", classMask = 2047, name = "雷霆之怒，逐风者的祝福之剑", icon = "Interface\\Icons\\INV_Sword_39", source = "逐风者任务线", collected = true, favorite = false, weaponType = "TWO_HAND_SWORD", weaponTypeLabel = "双手剑", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Sword_2H_Ashbringer02_19019.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.TWO_HAND_SWORD },
    { id = 52, itemId = 32837, slot = "MAINHAND", classMask = 2047, name = "埃辛诺斯战刃（主手）", icon = "Interface\\Icons\\INV_Weapon_Glave_01", source = "黑暗神殿", collected = false, favorite = false, weaponType = "WAR_GLAIVE", weaponCategory = "ONE_HAND_SWORD", weaponTypeLabel = "单手剑", cameraTuningKey = "WAR_GLAIVE_MAINHAND", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Glave_1H_DualBlade_D_02_32837.m2", modelScale = 0.86, m2Camera = WEAPON_M2_CAMERA.WAR_GLAIVE_MAINHAND },
    { id = 53, itemId = 32838, slot = "OFFHAND", classMask = 2047, name = "埃辛诺斯战刃（副手）", icon = "Interface\\Icons\\INV_Weapon_Glave_01", source = "黑暗神殿", collected = false, favorite = true, weaponType = "WAR_GLAIVE", weaponCategory = "ONE_HAND_SWORD", weaponTypeLabel = "单手剑", cameraTuningKey = "WAR_GLAIVE_OFFHAND", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Glave_1H_DualBlade_D_02left_32838.m2", modelScale = 0.86, m2Camera = WEAPON_M2_CAMERA.WAR_GLAIVE_OFFHAND },
    { id = 54, itemId = 32375, slot = "OFFHAND", classMask = 2047, name = "埃辛诺斯壁垒", icon = "Interface\\Icons\\INV_Shield_32", source = "黑暗神殿", collected = true, favorite = false, weaponType = "SHIELD", weaponTypeLabel = "盾牌", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Shield_2H_OutlandRaid_D_06_32375.m2", modelScale = 0.92, m2Camera = WEAPON_M2_CAMERA.SHIELD },

    -- One client-verified sample for every practical 3.3.5 weapon subclass.
    -- Ranged samples stay in MAINHAND so the existing weapon filter shows all
    -- categories on the same card grid while their real type remains explicit.
    { id = 55, itemId = 50737, slot = "MAINHAND", classMask = 2047, name = "校准样本：单手斧", icon = "Interface\\Icons\\INV_Axe_113", source = "类别校准样本", collected = true, favorite = false, weaponType = "ONE_HAND_AXE", weaponTypeLabel = "单手斧", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Axe_1H_IcecrownRaid_D_01_50737.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.ONE_HAND_AXE },
    { id = 56, itemId = 50709, slot = "MAINHAND", classMask = 2047, name = "校准样本：双手斧", icon = "Interface\\Icons\\INV_Axe_120", source = "类别校准样本", collected = true, favorite = false, weaponType = "TWO_HAND_AXE", weaponTypeLabel = "双手斧", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Axe_2H_IcecrownRaid_D_02_50709.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.TWO_HAND_AXE },
    { id = 57, itemId = 50638, slot = "MAINHAND", classMask = 2047, name = "校准样本：弓", icon = "Interface\\Icons\\INV_Weapon_Bow_55", source = "类别校准样本", collected = true, favorite = false, weaponType = "BOW", weaponTypeLabel = "弓", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Bow_1H_IcecrownRaid_D_01_50638.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.BOW },
    { id = 58, itemId = 50444, slot = "MAINHAND", classMask = 2047, name = "校准样本：枪械", icon = "Interface\\Icons\\INV_Weapon_Rifle_39", source = "类别校准样本", collected = true, favorite = false, weaponType = "GUN", weaponTypeLabel = "枪械", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Firearm_2H_Rifle_IcecrownRaid_D_01_50444.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.GUN },
    { id = 59, itemId = 50734, slot = "MAINHAND", classMask = 2047, name = "校准样本：单手锤", icon = "Interface\\Icons\\INV_Mace_115", source = "类别校准样本", collected = true, favorite = false, weaponType = "ONE_HAND_MACE", weaponTypeLabel = "单手锤", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Mace_1H_IcecrownRaid_D_04_50734.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.ONE_HAND_MACE },
    { id = 60, itemId = 50603, slot = "MAINHAND", classMask = 2047, name = "校准样本：双手锤", icon = "Interface\\Icons\\INV_Mace_116", source = "类别校准样本", collected = true, favorite = false, weaponType = "TWO_HAND_MACE", weaponTypeLabel = "双手锤", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Mace_2H_IcecrownRaid_D_01_50603.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.TWO_HAND_MACE },
    { id = 61, itemId = 50735, slot = "MAINHAND", classMask = 2047, name = "校准样本：长柄武器", icon = "Interface\\Icons\\INV_Weapon_Staff_109", source = "类别校准样本", collected = true, favorite = false, weaponType = "POLEARM", weaponTypeLabel = "长柄武器", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Polearm_2H_IcecrownRaid_D_01_50735.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.POLEARM },
    { id = 62, itemId = 32466, slot = "MAINHAND", classMask = 2047, name = "校准样本：单手剑", icon = "Interface\\Icons\\INV_Sword_78", source = "类别校准样本", collected = true, favorite = false, weaponType = "ONE_HAND_SWORD", weaponTypeLabel = "单手剑", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Sword_1H_Crystal_C_02_32466.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.ONE_HAND_SWORD },
    { id = 63, itemId = 33350, slot = "MAINHAND", classMask = 2047, name = "校准样本：双手剑", icon = "Interface\\Icons\\INV_Sword_92", source = "类别校准样本", collected = true, favorite = false, weaponType = "TWO_HAND_SWORD", weaponTypeLabel = "双手剑", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Sword_2H_Frostmourne_D_01_33350.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.TWO_HAND_SWORD },
    { id = 64, itemId = 50731, slot = "MAINHAND", classMask = 2047, name = "校准样本：法杖", icon = "Interface\\Icons\\INV_Staff_108", source = "类别校准样本", collected = true, favorite = false, weaponType = "STAFF", weaponTypeLabel = "法杖", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Stave_2H_IcecrownRaid_D_02_50731.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.STAFF },
    { id = 65, itemId = 50692, slot = "MAINHAND", classMask = 2047, name = "校准样本：拳套", icon = "Interface\\Icons\\INV_Weapon_Hand_33", source = "类别校准样本", collected = true, favorite = false, weaponType = "FIST_WEAPON", weaponTypeLabel = "拳套", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Hand_1H_IcecrownRaid_D_02Right_50692.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.FIST_WEAPON },
    { id = 66, itemId = 50736, slot = "MAINHAND", classMask = 2047, name = "校准样本：匕首", icon = "Interface\\Icons\\INV_Weapon_ShortBlade_104", source = "类别校准样本", collected = true, favorite = false, weaponType = "DAGGER", weaponTypeLabel = "匕首", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Knife_1H_IcecrownRaid_D_03_50736.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.DAGGER },
    { id = 67, itemId = 50474, slot = "MAINHAND", classMask = 2047, name = "校准样本：投掷武器", icon = "Interface\\Icons\\INV_ThrowingKnife_07", source = "类别校准样本", collected = true, favorite = false, weaponType = "THROWN", weaponTypeLabel = "投掷武器", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Thrown_1H_Shuriken_A_02_50474.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.THROWN },
    { id = 68, itemId = 50733, slot = "MAINHAND", classMask = 2047, name = "校准样本：弩", icon = "Interface\\Icons\\INV_Weapon_Crossbow_38", source = "类别校准样本", collected = true, favorite = false, weaponType = "CROSSBOW", weaponTypeLabel = "弩", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Bow_2H_Crossbow_IcecrownRaid_D_01_50733.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.CROSSBOW },
    { id = 69, itemId = 50631, slot = "MAINHAND", classMask = 2047, name = "校准样本：魔杖", icon = "Interface\\Icons\\INV_Wand_34", source = "类别校准样本", collected = true, favorite = false, weaponType = "WAND", weaponTypeLabel = "魔杖", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Wand_1H_IcecrownRaid_D_02_50631.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.WAND },
    { id = 70, itemId = 43651, slot = "MAINHAND", classMask = 2047, name = "校准样本：钓鱼竿", icon = "Interface\\Icons\\INV_Fishingpole_01", source = "类别校准样本", collected = true, favorite = false, weaponType = "FISHING_POLE", weaponTypeLabel = "钓鱼竿", modelPath = "Item\\ObjectComponents\\SoloCollections\\SC_Misc_2H_FishingPole_A_01_43651.m2", modelScale = 0.88, m2Camera = WEAPON_M2_CAMERA.FISHING_POLE },
}

-- Armor-family navigation follows the four WotLK armor subclasses requested
-- by the wardrobe UI. Existing demo records are tier pieces, so their class
-- masks are a stable source for the family; universal cloaks remain visible
-- from every armor-family selection. Future generated records may provide an
-- explicit armorType and bypass this fallback.
local ARMOR_TYPE_BY_CLASS_BIT = {
    [1] = "PLATE", [2] = "PLATE", [32] = "PLATE",
    [4] = "MAIL", [64] = "MAIL",
    [8] = "LEATHER", [1024] = "LEATHER",
    [16] = "CLOTH", [128] = "CLOTH", [256] = "CLOTH",
}

local function inferArmorType(classMask)
    local resolved
    classMask = tonumber(classMask)
    if not classMask then return "ALL" end
    for classBit, armorType in pairs(ARMOR_TYPE_BY_CLASS_BIT) do
        if math.floor(classMask / classBit) % 2 == 1 then
            if resolved and resolved ~= armorType then
                return "ALL"
            end
            resolved = armorType
        end
    end
    return resolved or "ALL"
end

for _, appearance in ipairs(SC.Data.Appearances) do
    if appearance.slot ~= "MAINHAND" and appearance.slot ~= "OFFHAND" and not appearance.armorType then
        appearance.armorType = appearance.slot == "BACK" and "ALL" or inferArmorType(appearance.classMask)
    end
end

-- Client-only CreatureDisplayInfo rows packaged in the locale DBC patch. These
-- IDs live above the highest row in the loaded 3.3.5a zhCN patch chain.
local standaloneDisplayIds = {
    [50] = 40000,
    [51] = 40001,
    [52] = 40002,
    [53] = 40003,
    [54] = 40004,
    [55] = 40005,
    [56] = 40006,
    [57] = 40007,
    [58] = 40008,
    [59] = 40009,
    [60] = 40010,
    [61] = 40011,
    [62] = 40012,
    [63] = 40013,
    [64] = 40014,
    [65] = 40015,
    [66] = 40016,
    [67] = 40017,
    [68] = 40018,
    [69] = 40019,
    [70] = 40020,
}
for _, appearance in ipairs(SC.Data.Appearances) do
    appearance.creatureDisplayId = standaloneDisplayIds[appearance.id]
end
