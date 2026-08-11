-- DOWNPORT: copied from NewEra (see ReferenceAddons); namespace localized to DragonUI_NewEra,
-- art paths re-pointed at DragonUI_NewEra\Textures\EncounterJournal. Content unchanged.
local NE = DragonUI_NewEra
-- Addon/EncounterJournal/LootEra.lua — VANILLA (Era 1.15) boss LOOT overlay.
-- AUTO-REGENERATED from cmangos ClassicDB 1.12.1 (creature_loot_template +
-- reference_loot_template), BOSS-LOOT filtered: rare/epic (Quality>=3) always kept;
-- green (Quality==2) and recipe/quest (item class 9/12) kept ONLY if boss-specific
-- (dropped by <=4 distinct creatures); gray/white non-recipe/quest dropped entirely.
-- This keeps each boss's signature/dungeon-set drops while excluding generic world-
-- drop greens & vendor recipes. Era 1.15 item IDs == vanilla 1.12 IDs, used directly.
-- Encounters resolved to cmangos npcID by exact name, then displayID fallback,
-- then a small manual override map for multi-NPC / retail-renamed bosses. Shared
-- world-drop / profession reference pools are excluded so each boss carries only
-- its curated notable loot (mirrors retail EJ). The original hand-sourced entries are
-- gone: every boss now also covered by the cmangos boss-filter dropped its redundant
-- hand entry; the lone exception is BRD 'Ring of Law' (a random-monster gauntlet whose
-- loot hangs off the arena mobs, not the event creature) -- its hand entry is RETAINED
-- but run through the SAME boss-loot filter (all rare/epic). No gray/white/generic-green
-- items remain. Merged into NE.ej.DATA at load WITHOUT editing the auto-generated
-- Data.lua (same overlay mechanism as AbilitiesEra.lua); survives a Data.lua re-gen.
-- Must load AFTER Data.lua. Lighting up loot here also lights up the item tooltip
-- "Boss Drop" line (it reads NE.ej.DATA loot).

NE.ej = NE.ej or {}

local LOOT = {
  [639] = {
    {id=2874,pct=100}, {id=3637,pct=100}, {id=5193,pct=30}, {id=5202,pct=30}, {id=5191,pct=20}, {id=10399,pct=20},
  },
  [643] = {
    {id=5195,pct=65}, {id=5194,pct=35},
  },
  [644] = {
    {id=872,pct=5},
  },
  [645] = {
    {id=5197,pct=65}, {id=5198,pct=35},
  },
  [646] = {
    {id=5192,pct=40}, {id=5196,pct=40}, {id=7230,pct=20},
  },
  [647] = {
    {id=5201,pct=40}, {id=5200,pct=30}, {id=10403,pct=30},
  },
  [1663] = {
    {id=3628,pct=100},
  },
  [1666] = {
    {id=3640,pct=100}, {id=2280,pct=1.2},
  },
  [1696] = {
    {id=3630,pct=100},
  },
  [1716] = {
    {id=2926,pct=100}, {id=3871,pct=0},
  },
  [1720] = {
    {id=2941,pct=0}, {id=2942,pct=0}, {id=3228,pct=0},
  },
  [1763] = {
    {id=5199,pct=55}, {id=1156,pct=45},
  },
  [1853] = {
    {id=21525,pct=100}, {id=13501,pct=10}, {id=14514,pct=7}, {id=19276,pct=3}, {id=13937,pct=2}, {id=13398,pct=0},
    {id=13938,pct=0}, {id=13944,pct=0}, {id=13951,pct=0}, {id=13953,pct=0}, {id=13964,pct=0}, {id=16667,pct=0},
    {id=16677,pct=0}, {id=16686,pct=0}, {id=16693,pct=0}, {id=16698,pct=0}, {id=16707,pct=0}, {id=16720,pct=0},
    {id=16727,pct=0}, {id=16731,pct=0}, {id=22433,pct=0},
  },
  [2748] = {
    {id=7672,pct=100}, {id=11118,pct=60}, {id=9413,pct=0}, {id=9418,pct=0},
  },
  [3653] = {
    {id=13245,pct=10},
  },
  [3654] = {
    {id=10441,pct=100}, {id=6461,pct=33.3}, {id=6463,pct=33.3}, {id=6627,pct=33.3},
  },
  [3669] = {
    {id=9738,pct=100}, {id=6465,pct=60}, {id=6460,pct=20}, {id=10410,pct=20},
  },
  [3670] = {
    {id=9740,pct=100}, {id=6473,pct=60}, {id=6472,pct=40},
  },
  [3671] = {
    {id=9739,pct=100}, {id=10412,pct=10},
  },
  [3673] = {
    {id=9741,pct=100}, {id=5970,pct=25}, {id=6459,pct=25}, {id=6469,pct=25}, {id=10411,pct=25},
  },
  [3674] = {
    {id=6448,pct=50}, {id=6449,pct=50},
  },
  [3886] = {
    {id=6226,pct=45}, {id=6633,pct=45}, {id=1292,pct=10},
  },
  [3887] = {
    {id=6323,pct=70}, {id=6321,pct=30},
  },
  [3927] = {
    {id=3748,pct=60}, {id=6314,pct=40},
  },
  [3974] = {
    {id=7756,pct=60}, {id=3456,pct=30}, {id=7710,pct=10},
  },
  [3975] = {
    {id=7717,pct=15}, {id=10330,pct=15}, {id=7718,pct=0}, {id=7719,pct=0},
  },
  [3976] = {
    {id=7726,pct=40}, {id=10330,pct=15}, {id=7723,pct=0}, {id=7724,pct=0},
  },
  [3977] = {
    {id=7721,pct=20}, {id=7720,pct=0}, {id=7722,pct=0},
  },
  [3983] = {
    {id=7682,pct=10},
  },
  [4274] = {
    {id=6340,pct=70}, {id=3230,pct=30},
  },
  [4275] = {
    {id=5442,pct=100}, {id=6324,pct=40}, {id=6392,pct=40}, {id=6220,pct=20},
  },
  [4278] = {
    {id=3191,pct=0}, {id=6320,pct=0},
  },
  [4279] = {
    {id=6319,pct=60}, {id=6318,pct=40},
  },
  [4420] = {
    {id=6686,pct=60}, {id=6687,pct=40},
  },
  [4421] = {
    {id=5792,pct=100}, {id=5793,pct=100}, {id=6693,pct=40}, {id=6694,pct=40}, {id=6692,pct=20},
  },
  [4422] = {
    {id=6690,pct=60}, {id=6691,pct=40},
  },
  [4428] = {
    {id=6682,pct=40}, {id=6685,pct=40}, {id=2816,pct=20},
  },
  [4542] = {
    {id=19507,pct=0}, {id=19508,pct=0}, {id=19509,pct=0},
  },
  [4543] = {
    {id=7684,pct=0}, {id=7685,pct=0},
  },
  [4829] = {
    {id=6910,pct=40}, {id=6911,pct=40}, {id=6909,pct=20},
  },
  [4830] = {
    {id=6901,pct=40}, {id=6902,pct=30}, {id=6904,pct=30},
  },
  [4831] = {
    {id=888,pct=40}, {id=11121,pct=40}, {id=3078,pct=20},
  },
  [4832] = {
    {id=5881,pct=100}, {id=1155,pct=60}, {id=6903,pct=40},
  },
  [4854] = {
    {id=7670,pct=100}, {id=9416,pct=20}, {id=9414,pct=0}, {id=9415,pct=0},
  },
  [4887] = {
    {id=6908,pct=60}, {id=6907,pct=40},
  },
  [5312] = {
    {id=16870,pct=100}, {id=14510,pct=0.1}, {id=17413,pct=0.1}, {id=17682,pct=0.1}, {id=810,pct=0}, {id=812,pct=0},
    {id=942,pct=0}, {id=2163,pct=0}, {id=2824,pct=0}, {id=2915,pct=0}, {id=10795,pct=0}, {id=10796,pct=0},
    {id=10797,pct=0}, {id=12243,pct=0}, {id=12463,pct=0}, {id=12464,pct=0}, {id=12465,pct=0}, {id=12466,pct=0},
  },
  [5709] = {
    {id=10454,pct=100}, {id=10828,pct=20}, {id=10837,pct=20}, {id=10847,pct=0.5}, {id=10829,pct=0}, {id=10833,pct=0},
    {id=10835,pct=0}, {id=10836,pct=0},
  },
  [5710] = {
    {id=6212,pct=100}, {id=17413,pct=0.1}, {id=17414,pct=0.1}, {id=17682,pct=0.1}, {id=17683,pct=0.1}, {id=18600,pct=0.1},
    {id=22393,pct=0.1}, {id=10806,pct=0}, {id=10807,pct=0}, {id=10808,pct=0},
  },
  [5775] = {
    {id=6630,pct=40}, {id=6631,pct=40}, {id=6629,pct=20},
  },
  [6229] = {
    {id=9450,pct=60}, {id=9449,pct=40}, {id=11827,pct=2},
  },
  [6235] = {
    {id=9447,pct=40}, {id=9448,pct=40}, {id=9446,pct=20},
  },
  [6243] = {
    {id=6905,pct=50}, {id=6906,pct=50},
  },
  [6487] = {
    {id=7711,pct=0}, {id=7712,pct=0}, {id=7713,pct=0}, {id=7714,pct=0},
  },
  [6906] = {
    {id=9399,pct=100}, {id=9401,pct=10},
  },
  [6910] = {
    {id=7741,pct=100}, {id=9387,pct=0}, {id=9388,pct=0}, {id=9389,pct=0}, {id=9390,pct=0},
  },
  [7079] = {
    {id=9454,pct=55}, {id=9453,pct=25}, {id=9452,pct=20},
  },
  [7206] = {
    {id=9410,pct=0}, {id=9411,pct=0},
  },
  [7228] = {
    {id=9408,pct=20}, {id=9407,pct=0}, {id=9409,pct=0},
  },
  [7267] = {
    {id=9476,pct=30}, {id=11086,pct=10}, {id=862,pct=0}, {id=2040,pct=0}, {id=5616,pct=0}, {id=6440,pct=0},
    {id=9477,pct=0}, {id=9478,pct=0}, {id=9479,pct=0}, {id=9480,pct=0}, {id=9481,pct=0}, {id=9482,pct=0},
    {id=9483,pct=0}, {id=9484,pct=0}, {id=9511,pct=0}, {id=9512,pct=0},
  },
  [7271] = {
    {id=18083,pct=40}, {id=18082,pct=20}, {id=862,pct=0}, {id=2040,pct=0}, {id=5616,pct=0}, {id=6440,pct=0},
    {id=9480,pct=0}, {id=9481,pct=0}, {id=9482,pct=0}, {id=9483,pct=0}, {id=9484,pct=0}, {id=9511,pct=0},
    {id=9512,pct=0},
  },
  [7272] = {
    {id=10660,pct=100}, {id=3875,pct=0}, {id=862,pct=0}, {id=2040,pct=0}, {id=5616,pct=0}, {id=6440,pct=0},
    {id=9480,pct=0}, {id=9481,pct=0}, {id=9482,pct=0}, {id=9483,pct=0}, {id=9484,pct=0}, {id=9511,pct=0},
    {id=9512,pct=0},
  },
  [7273] = {
    {id=8707,pct=100}, {id=862,pct=0}, {id=2040,pct=0}, {id=5616,pct=0}, {id=6440,pct=0}, {id=9467,pct=0},
    {id=9469,pct=0}, {id=9480,pct=0}, {id=9481,pct=0}, {id=9482,pct=0}, {id=9483,pct=0}, {id=9484,pct=0},
    {id=9511,pct=0}, {id=9512,pct=0},
  },
  [7291] = {
    {id=11311,pct=40}, {id=9412,pct=0}, {id=9419,pct=0}, {id=11310,pct=0},
  },
  [7354] = {
    {id=10758,pct=20}, {id=10767,pct=0}, {id=10768,pct=0},
  },
  [7355] = {
    {id=10775,pct=0}, {id=10776,pct=0}, {id=10777,pct=0},
  },
  [7356] = {
    {id=10760,pct=60}, {id=10766,pct=40},
  },
  [7357] = {
    {id=10769,pct=0}, {id=10770,pct=0}, {id=10771,pct=0},
  },
  [7358] = {
    {id=10420,pct=100}, {id=10761,pct=0}, {id=10762,pct=0}, {id=10763,pct=0}, {id=10764,pct=0}, {id=10765,pct=0},
  },
  [7361] = {
    {id=9445,pct=10},
  },
  [7795] = {
    {id=9234,pct=100}, {id=10661,pct=100}, {id=17413,pct=0.2}, {id=17682,pct=0.1}, {id=862,pct=0}, {id=2040,pct=0},
    {id=5616,pct=0}, {id=6440,pct=0}, {id=9480,pct=0}, {id=9481,pct=0}, {id=9482,pct=0}, {id=9483,pct=0},
    {id=9484,pct=0}, {id=9511,pct=0}, {id=9512,pct=0},
  },
  [7796] = {
    {id=9471,pct=100}, {id=862,pct=0}, {id=2040,pct=0}, {id=5616,pct=0}, {id=6440,pct=0}, {id=9480,pct=0},
    {id=9481,pct=0}, {id=9482,pct=0}, {id=9483,pct=0}, {id=9484,pct=0}, {id=9511,pct=0}, {id=9512,pct=0},
  },
  [7800] = {
    {id=9458,pct=30}, {id=9461,pct=30}, {id=9459,pct=25}, {id=9492,pct=15}, {id=11828,pct=15}, {id=4411,pct=2},
    {id=4413,pct=2}, {id=4415,pct=2}, {id=7742,pct=2},
  },
  [8127] = {
    {id=9639,pct=20}, {id=9379,pct=10}, {id=862,pct=0}, {id=2040,pct=0}, {id=5616,pct=0}, {id=6440,pct=0},
    {id=9480,pct=0}, {id=9481,pct=0}, {id=9482,pct=0}, {id=9483,pct=0}, {id=9484,pct=0}, {id=9511,pct=0},
    {id=9512,pct=0}, {id=9640,pct=0}, {id=9641,pct=0},
  },
  [8443] = {
    {id=10838,pct=20}, {id=10844,pct=20}, {id=12462,pct=0.5}, {id=10842,pct=0}, {id=10843,pct=0}, {id=10845,pct=0},
    {id=10846,pct=0},
  },
  [8567] = {
    {id=10772,pct=0}, {id=10774,pct=0},
  },
  [8983] = {
    {id=11268,pct=100}, {id=11465,pct=100}, {id=11819,pct=8}, {id=11669,pct=0}, {id=11822,pct=0}, {id=11823,pct=0},
  },
  [9016] = {
    {id=11805,pct=18}, {id=11807,pct=18}, {id=11802,pct=0}, {id=11803,pct=0},
  },
  [9017] = {
    {id=11126,pct=100}, {id=21987,pct=100}, {id=19268,pct=2}, {id=11764,pct=0}, {id=11765,pct=0}, {id=11766,pct=0},
    {id=11767,pct=0},
  },
  [9018] = {
    {id=11624,pct=0}, {id=11625,pct=0}, {id=11626,pct=0}, {id=22240,pct=0},
  },
  [9019] = {
    {id=21524,pct=100}, {id=11684,pct=1}, {id=11815,pct=0}, {id=11924,pct=0}, {id=11928,pct=0}, {id=11930,pct=0},
    {id=11931,pct=0}, {id=11932,pct=0}, {id=11933,pct=0}, {id=11934,pct=0}, {id=22204,pct=0}, {id=22207,pct=0},
  },
  [9024] = {
    {id=11207,pct=40}, {id=11750,pct=20}, {id=11747,pct=0}, {id=11748,pct=0}, {id=11749,pct=0},
  },
  [9025] = {
    {id=11630,pct=16}, {id=11813,pct=15}, {id=11631,pct=0}, {id=11632,pct=0}, {id=22234,pct=0}, {id=22397,pct=0},
  },
  [9033] = {
    {id=11464,pct=100}, {id=11810,pct=0}, {id=11816,pct=0}, {id=11817,pct=0}, {id=11820,pct=0}, {id=11821,pct=0},
  },
  [9041] = {
    {id=11782,pct=0}, {id=11783,pct=0}, {id=11784,pct=0}, {id=22241,pct=0},
  },
  [9056] = {
    {id=10999,pct=100}, {id=11839,pct=0}, {id=11841,pct=0}, {id=11842,pct=0}, {id=22223,pct=0},
  },
  [9156] = {
    {id=11809,pct=20}, {id=11832,pct=17}, {id=11808,pct=1}, {id=11812,pct=0}, {id=11814,pct=0},
  },
  [9196] = {
    {id=12534,pct=100}, {id=12336,pct=13}, {id=13166,pct=0}, {id=13167,pct=0}, {id=13168,pct=0}, {id=13169,pct=0},
    {id=13170,pct=0}, {id=16670,pct=0},
  },
  [9236] = {
    {id=13352,pct=100}, {id=12654,pct=30}, {id=12651,pct=8}, {id=12653,pct=8}, {id=12626,pct=0}, {id=13255,pct=0},
    {id=13257,pct=0}, {id=16712,pct=0},
  },
  [9237] = {
    {id=13173,pct=100}, {id=21524,pct=100}, {id=12335,pct=17}, {id=12582,pct=0}, {id=13177,pct=0}, {id=13179,pct=0},
    {id=16676,pct=0}, {id=22231,pct=0},
  },
  [9319] = {
    {id=11628,pct=15}, {id=11629,pct=15}, {id=11623,pct=0}, {id=11627,pct=0},
  },
  [9499] = {
    {id=12791,pct=0}, {id=12793,pct=0}, {id=18653,pct=0},
  },
  [9502] = {
    {id=11744,pct=0}, {id=11745,pct=0}, {id=22212,pct=0},
  },
  [9537] = {
    {id=11312,pct=100}, {id=11735,pct=9}, {id=18043,pct=0}, {id=18044,pct=0}, {id=22275,pct=0},
  },
  [9568] = {
    {id=12780,pct=100}, {id=12337,pct=26}, {id=13143,pct=2}, {id=13161,pct=0}, {id=13162,pct=0}, {id=13163,pct=0},
    {id=16679,pct=0}, {id=22321,pct=0},
  },
  [9736] = {
    {id=13252,pct=16}, {id=13253,pct=14}, {id=12835,pct=10},
  },
  [9938] = {
    {id=11746,pct=0}, {id=11935,pct=0}, {id=22208,pct=0}, {id=22395,pct=0}, {id=22400,pct=0},
  },
  [10096] = {
    {id=11610,pct=82}, {id=11685,pct=35}, {id=22271,pct=35}, {id=11665,pct=34}, {id=11703,pct=34}, {id=11675,pct=31},
    {id=11722,pct=29}, {id=22266,pct=29}, {id=11634,pct=27}, {id=11731,pct=27}, {id=11679,pct=26}, {id=11686,pct=26},
    {id=11728,pct=25}, {id=22257,pct=24}, {id=11635,pct=23}, {id=11677,pct=23}, {id=11729,pct=23}, {id=11633,pct=19},
    {id=11662,pct=19}, {id=11824,pct=16}, {id=11678,pct=15}, {id=11702,pct=13}, {id=22270,pct=13}, {id=11726,pct=12},
    {id=11730,pct=12},
  },
  [10184] = {
    {id=17966,pct=100}, {id=18422,pct=100}, {id=18423,pct=100}, {id=18705,pct=40}, {id=17064,pct=8}, {id=17068,pct=8},
    {id=17075,pct=8}, {id=16900,pct=0}, {id=16908,pct=0}, {id=16914,pct=0}, {id=16921,pct=0}, {id=16929,pct=0},
    {id=16939,pct=0}, {id=16947,pct=0}, {id=16955,pct=0}, {id=16963,pct=0}, {id=17067,pct=0}, {id=17078,pct=0},
    {id=18205,pct=0}, {id=18813,pct=0},
  },
  [10220] = {
    {id=13210,pct=14}, {id=13211,pct=0}, {id=13212,pct=0}, {id=22313,pct=0},
  },
  [10268] = {
    {id=16718,pct=15}, {id=13205,pct=0}, {id=13206,pct=0}, {id=13208,pct=0},
  },
  [10432] = {
    {id=14577,pct=7}, {id=18691,pct=7},
  },
  [10433] = {
    {id=14576,pct=7}, {id=18692,pct=7},
  },
  [10435] = {
    {id=12382,pct=100}, {id=13376,pct=0}, {id=18722,pct=0}, {id=18725,pct=0}, {id=18726,pct=0}, {id=18727,pct=0},
    {id=23198,pct=0},
  },
  [10436] = {
    {id=13514,pct=0}, {id=13534,pct=0}, {id=13535,pct=0}, {id=13537,pct=0}, {id=13538,pct=0}, {id=13539,pct=0},
    {id=16704,pct=0}, {id=18728,pct=0}, {id=18729,pct=0}, {id=18730,pct=0},
  },
  [10437] = {
    {id=13508,pct=0}, {id=13529,pct=0}, {id=13530,pct=0}, {id=13531,pct=0}, {id=13532,pct=0}, {id=13533,pct=0},
    {id=16675,pct=0}, {id=18738,pct=0}, {id=18739,pct=0}, {id=18740,pct=0},
  },
  [10438] = {
    {id=12833,pct=6}, {id=13509,pct=0}, {id=13524,pct=0}, {id=13525,pct=0}, {id=13526,pct=0}, {id=13527,pct=0},
    {id=13528,pct=0}, {id=16691,pct=0}, {id=18734,pct=0}, {id=18735,pct=0}, {id=18737,pct=0},
  },
  [10439] = {
    {id=12735,pct=100}, {id=15880,pct=100}, {id=16737,pct=12}, {id=13372,pct=0}, {id=13373,pct=0}, {id=13374,pct=0},
    {id=13375,pct=0}, {id=13515,pct=0}, {id=18723,pct=0},
  },
  [10502] = {
    {id=18335,pct=1}, {id=14611,pct=0}, {id=14612,pct=0}, {id=14614,pct=0}, {id=14615,pct=0}, {id=14616,pct=0},
    {id=14620,pct=0}, {id=14621,pct=0}, {id=14622,pct=0}, {id=14623,pct=0}, {id=14624,pct=0}, {id=14626,pct=0},
    {id=14629,pct=0}, {id=14631,pct=0}, {id=14632,pct=0}, {id=14633,pct=0}, {id=14636,pct=0}, {id=14637,pct=0},
    {id=14638,pct=0}, {id=14640,pct=0}, {id=14641,pct=0}, {id=18680,pct=0}, {id=18681,pct=0}, {id=18682,pct=0},
    {id=18683,pct=0}, {id=18684,pct=0}, {id=23200,pct=0}, {id=23201,pct=0},
  },
  [10503] = {
    {id=13523,pct=100}, {id=13725,pct=100}, {id=16701,pct=17}, {id=18335,pct=1}, {id=14541,pct=0}, {id=14543,pct=0},
    {id=14545,pct=0}, {id=14548,pct=0}, {id=18689,pct=0}, {id=18690,pct=0}, {id=22394,pct=0},
  },
  [10504] = {
    {id=16722,pct=5}, {id=14611,pct=0}, {id=14612,pct=0}, {id=14614,pct=0}, {id=14615,pct=0}, {id=14616,pct=0},
    {id=14620,pct=0}, {id=14621,pct=0}, {id=14622,pct=0}, {id=14623,pct=0}, {id=14624,pct=0}, {id=14626,pct=0},
    {id=14629,pct=0}, {id=14631,pct=0}, {id=14632,pct=0}, {id=14633,pct=0}, {id=14636,pct=0}, {id=14637,pct=0},
    {id=14638,pct=0}, {id=14640,pct=0}, {id=14641,pct=0}, {id=18680,pct=0}, {id=18681,pct=0}, {id=18682,pct=0},
    {id=18683,pct=0}, {id=18684,pct=0}, {id=23200,pct=0}, {id=23201,pct=0},
  },
  [10505] = {
    {id=16710,pct=5}, {id=18335,pct=1}, {id=14611,pct=0}, {id=14612,pct=0}, {id=14614,pct=0}, {id=14615,pct=0},
    {id=14616,pct=0}, {id=14620,pct=0}, {id=14621,pct=0}, {id=14622,pct=0}, {id=14623,pct=0}, {id=14624,pct=0},
    {id=14626,pct=0}, {id=14629,pct=0}, {id=14631,pct=0}, {id=14632,pct=0}, {id=14633,pct=0}, {id=14636,pct=0},
    {id=14637,pct=0}, {id=14638,pct=0}, {id=14640,pct=0}, {id=14641,pct=0}, {id=18680,pct=0}, {id=18681,pct=0},
    {id=18682,pct=0}, {id=18683,pct=0}, {id=18684,pct=0}, {id=23200,pct=0}, {id=23201,pct=0},
  },
  [10506] = {
    {id=13955,pct=0}, {id=13956,pct=0}, {id=13957,pct=0}, {id=13960,pct=0}, {id=13967,pct=0}, {id=13969,pct=0},
    {id=13983,pct=0}, {id=14024,pct=0}, {id=16734,pct=0},
  },
  [10507] = {
    {id=16716,pct=4}, {id=18335,pct=1}, {id=14611,pct=0}, {id=14612,pct=0}, {id=14614,pct=0}, {id=14615,pct=0},
    {id=14616,pct=0}, {id=14620,pct=0}, {id=14621,pct=0}, {id=14622,pct=0}, {id=14623,pct=0}, {id=14624,pct=0},
    {id=14626,pct=0}, {id=14629,pct=0}, {id=14631,pct=0}, {id=14632,pct=0}, {id=14633,pct=0}, {id=14636,pct=0},
    {id=14637,pct=0}, {id=14638,pct=0}, {id=14640,pct=0}, {id=14641,pct=0}, {id=18680,pct=0}, {id=18681,pct=0},
    {id=18682,pct=0}, {id=18683,pct=0}, {id=18684,pct=0}, {id=23200,pct=0}, {id=23201,pct=0},
  },
  [10508] = {
    {id=13626,pct=100}, {id=17414,pct=15}, {id=17683,pct=15}, {id=18600,pct=15}, {id=22393,pct=15}, {id=22890,pct=15},
    {id=22891,pct=15}, {id=13521,pct=4}, {id=13314,pct=2}, {id=18335,pct=0.2}, {id=13952,pct=0}, {id=14340,pct=0},
    {id=14487,pct=0}, {id=14502,pct=0}, {id=14503,pct=0}, {id=14522,pct=0}, {id=14525,pct=0}, {id=16689,pct=0},
    {id=17413,pct=0}, {id=17682,pct=0}, {id=18693,pct=0}, {id=18694,pct=0}, {id=18695,pct=0}, {id=18696,pct=0},
    {id=19233,pct=0}, {id=19234,pct=0}, {id=19235,pct=0}, {id=19236,pct=0}, {id=19262,pct=0}, {id=19263,pct=0},
    {id=19264,pct=0}, {id=19265,pct=0}, {id=19272,pct=0}, {id=19273,pct=0}, {id=19274,pct=0}, {id=19275,pct=0},
    {id=19281,pct=0}, {id=19282,pct=0}, {id=19283,pct=0}, {id=19284,pct=0},
  },
  [10516] = {
    {id=13404,pct=0}, {id=13405,pct=0}, {id=13408,pct=0}, {id=13409,pct=0}, {id=16717,pct=0},
  },
  [10558] = {
    {id=13378,pct=0}, {id=13379,pct=0}, {id=13383,pct=0}, {id=13384,pct=0}, {id=16682,pct=0},
  },
  [10584] = {
    {id=18784,pct=16}, {id=13178,pct=0}, {id=13258,pct=0}, {id=13259,pct=0}, {id=22232,pct=0},
  },
  [10596] = {
    {id=13183,pct=15}, {id=16715,pct=15}, {id=13213,pct=0}, {id=13244,pct=0},
  },
  [10808] = {
    {id=13400,pct=0}, {id=13401,pct=0}, {id=13402,pct=0}, {id=13403,pct=0}, {id=16724,pct=0},
  },
  [10811] = {
    {id=22206,pct=100}, {id=22897,pct=14}, {id=13385,pct=12}, {id=13386,pct=0}, {id=13387,pct=0}, {id=16692,pct=0},
    {id=18716,pct=0},
  },
  [10813] = {
    {id=13250,pct=100}, {id=14512,pct=6}, {id=13520,pct=3}, {id=13353,pct=1}, {id=12103,pct=0}, {id=13348,pct=0},
    {id=13358,pct=0}, {id=13359,pct=0}, {id=13360,pct=0}, {id=13369,pct=0}, {id=16725,pct=0}, {id=18717,pct=0},
    {id=18718,pct=0}, {id=18720,pct=0},
  },
  [10901] = {
    {id=22206,pct=100}, {id=16705,pct=17}, {id=18335,pct=1}, {id=14611,pct=0}, {id=14612,pct=0}, {id=14614,pct=0},
    {id=14615,pct=0}, {id=14616,pct=0}, {id=14620,pct=0}, {id=14621,pct=0}, {id=14622,pct=0}, {id=14623,pct=0},
    {id=14624,pct=0}, {id=14626,pct=0}, {id=14629,pct=0}, {id=14631,pct=0}, {id=14632,pct=0}, {id=14633,pct=0},
    {id=14636,pct=0}, {id=14637,pct=0}, {id=14638,pct=0}, {id=14640,pct=0}, {id=14641,pct=0}, {id=18680,pct=0},
    {id=18681,pct=0}, {id=18682,pct=0}, {id=18683,pct=0}, {id=18684,pct=0}, {id=23200,pct=0}, {id=23201,pct=0},
  },
  [10917] = {
    {id=13251,pct=100}, {id=13335,pct=1}, {id=13505,pct=1}, {id=13340,pct=0}, {id=13344,pct=0}, {id=13345,pct=0},
    {id=13346,pct=0}, {id=13349,pct=0}, {id=13361,pct=0}, {id=13368,pct=0}, {id=16668,pct=0}, {id=16678,pct=0},
    {id=16687,pct=0}, {id=16694,pct=0}, {id=16699,pct=0}, {id=16709,pct=0}, {id=16719,pct=0}, {id=16728,pct=0},
    {id=16732,pct=0}, {id=22408,pct=0}, {id=22409,pct=0}, {id=22410,pct=0}, {id=22411,pct=0}, {id=22412,pct=0},
  },
  [10997] = {
    {id=13377,pct=100}, {id=21524,pct=100}, {id=12839,pct=6}, {id=13380,pct=0}, {id=13381,pct=0}, {id=13382,pct=0},
    {id=16708,pct=0}, {id=18721,pct=0}, {id=22403,pct=0}, {id=22404,pct=0}, {id=22405,pct=0}, {id=22406,pct=0},
    {id=22407,pct=0},
  },
  [11032] = {
    {id=18335,pct=0.4}, {id=17414,pct=0.2}, {id=18600,pct=0.2}, {id=17683,pct=0.1}, {id=19233,pct=0.1}, {id=19282,pct=0.1},
    {id=19236,pct=0.1}, {id=19273,pct=0.1}, {id=19284,pct=0}, {id=18742,pct=0}, {id=18745,pct=0}, {id=19265,pct=0},
    {id=19272,pct=0}, {id=19281,pct=0}, {id=22891,pct=0},
  },
  [11143] = {
    {id=13390,pct=3}, {id=13388,pct=0}, {id=13389,pct=0}, {id=13391,pct=0}, {id=13392,pct=0}, {id=13393,pct=0},
  },
  [11261] = {
    {id=13523,pct=100}, {id=16684,pct=14}, {id=18335,pct=1}, {id=14611,pct=0}, {id=14612,pct=0}, {id=14614,pct=0},
    {id=14615,pct=0}, {id=14616,pct=0}, {id=14620,pct=0}, {id=14621,pct=0}, {id=14622,pct=0}, {id=14623,pct=0},
    {id=14624,pct=0}, {id=14626,pct=0}, {id=14629,pct=0}, {id=14631,pct=0}, {id=14632,pct=0}, {id=14633,pct=0},
    {id=14636,pct=0}, {id=14637,pct=0}, {id=14638,pct=0}, {id=14640,pct=0}, {id=14641,pct=0}, {id=18680,pct=0},
    {id=18681,pct=0}, {id=18682,pct=0}, {id=18683,pct=0}, {id=18684,pct=0}, {id=23200,pct=0}, {id=23201,pct=0},
  },
  [11380] = {
    {id=22637,pct=100}, {id=19722,pct=15}, {id=19723,pct=15}, {id=19724,pct=15}, {id=19716,pct=0}, {id=19717,pct=0},
    {id=19718,pct=0}, {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19875,pct=0}, {id=19884,pct=0},
    {id=19885,pct=0}, {id=19886,pct=0}, {id=19887,pct=0}, {id=19888,pct=0}, {id=19889,pct=0}, {id=19890,pct=0},
    {id=19891,pct=0}, {id=19892,pct=0}, {id=19894,pct=0}, {id=19929,pct=0},
  },
  [11382] = {
    {id=22637,pct=100}, {id=19722,pct=15}, {id=19723,pct=15}, {id=19724,pct=15}, {id=19872,pct=2}, {id=19716,pct=0},
    {id=19717,pct=0}, {id=19718,pct=0}, {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19863,pct=0},
    {id=19866,pct=0}, {id=19867,pct=0}, {id=19869,pct=0}, {id=19870,pct=0}, {id=19873,pct=0}, {id=19874,pct=0},
    {id=19877,pct=0}, {id=19878,pct=0}, {id=19893,pct=0}, {id=19895,pct=0}, {id=20038,pct=0},
  },
  [11486] = {
    {id=21525,pct=100}, {id=18373,pct=0}, {id=18375,pct=0}, {id=18376,pct=0}, {id=18378,pct=0}, {id=18380,pct=0},
    {id=18382,pct=0}, {id=18388,pct=0}, {id=18392,pct=0}, {id=18395,pct=0}, {id=18396,pct=0},
  },
  [11487] = {
    {id=18374,pct=20}, {id=18397,pct=20}, {id=22309,pct=15}, {id=18350,pct=0}, {id=18351,pct=0}, {id=18371,pct=0},
  },
  [11488] = {
    {id=22206,pct=100}, {id=18347,pct=0}, {id=18349,pct=0}, {id=18383,pct=0}, {id=18386,pct=0},
  },
  [11489] = {
    {id=18352,pct=0}, {id=18353,pct=0}, {id=18390,pct=0}, {id=18393,pct=0},
  },
  [11490] = {
    {id=18313,pct=20}, {id=18323,pct=20}, {id=18306,pct=0}, {id=18308,pct=0}, {id=18319,pct=0},
  },
  [11492] = {
    {id=18309,pct=0}, {id=18310,pct=0}, {id=18312,pct=0}, {id=18314,pct=0}, {id=18315,pct=0}, {id=18318,pct=0},
    {id=18321,pct=0}, {id=18326,pct=0}, {id=18327,pct=0}, {id=18328,pct=0},
  },
  [11496] = {
    {id=18370,pct=0}, {id=18372,pct=0}, {id=18377,pct=0}, {id=18379,pct=0}, {id=18381,pct=0}, {id=18384,pct=0},
    {id=18385,pct=0}, {id=18389,pct=0}, {id=18391,pct=0}, {id=18394,pct=0},
  },
  [11501] = {
    {id=18780,pct=9}, {id=19258,pct=7}, {id=18520,pct=0}, {id=18521,pct=0}, {id=18522,pct=0}, {id=18523,pct=0},
    {id=18524,pct=0}, {id=18525,pct=0}, {id=18526,pct=0}, {id=18527,pct=0},
  },
  [11502] = {
    {id=19017,pct=100}, {id=17076,pct=8}, {id=17082,pct=8}, {id=17104,pct=8}, {id=17204,pct=3}, {id=16901,pct=0},
    {id=16909,pct=0}, {id=16915,pct=0}, {id=16922,pct=0}, {id=16930,pct=0}, {id=16938,pct=0}, {id=16946,pct=0},
    {id=16954,pct=0}, {id=16962,pct=0}, {id=17063,pct=0}, {id=17102,pct=0}, {id=17106,pct=0}, {id=17107,pct=0},
    {id=18814,pct=0}, {id=18815,pct=0}, {id=18816,pct=0}, {id=18817,pct=0}, {id=19137,pct=0}, {id=19138,pct=0},
  },
  [11518] = {
    {id=14147,pct=40}, {id=14150,pct=40}, {id=14151,pct=20},
  },
  [11520] = {
    {id=14540,pct=100}, {id=14148,pct=40}, {id=14149,pct=40}, {id=14145,pct=20},
  },
  [11583] = {
    {id=19002,pct=100}, {id=19003,pct=100}, {id=21138,pct=100}, {id=19356,pct=10}, {id=19360,pct=10}, {id=19363,pct=10},
    {id=19364,pct=10}, {id=16897,pct=0}, {id=16905,pct=0}, {id=16916,pct=0}, {id=16923,pct=0}, {id=16931,pct=0},
    {id=16942,pct=0}, {id=16950,pct=0}, {id=16958,pct=0}, {id=16966,pct=0}, {id=19375,pct=0}, {id=19376,pct=0},
    {id=19377,pct=0}, {id=19378,pct=0}, {id=19379,pct=0}, {id=19380,pct=0}, {id=19381,pct=0}, {id=19382,pct=0},
  },
  [11622] = {
    {id=18782,pct=40}, {id=16711,pct=16}, {id=18335,pct=1}, {id=14528,pct=0}, {id=14531,pct=0}, {id=14537,pct=0},
    {id=14538,pct=0}, {id=14539,pct=0}, {id=18686,pct=0},
  },
  [11981] = {
    {id=19357,pct=10}, {id=19367,pct=10}, {id=16899,pct=4}, {id=16907,pct=4}, {id=16913,pct=4}, {id=16920,pct=4},
    {id=16928,pct=4}, {id=16940,pct=4}, {id=16948,pct=4}, {id=16956,pct=4}, {id=16964,pct=4}, {id=19353,pct=4},
    {id=19355,pct=4}, {id=19394,pct=0}, {id=19395,pct=0}, {id=19396,pct=0}, {id=19397,pct=0}, {id=19430,pct=0},
    {id=19431,pct=0}, {id=19432,pct=0}, {id=19433,pct=0},
  },
  [11982] = {
    {id=17073,pct=20}, {id=18203,pct=20}, {id=16796,pct=0}, {id=16810,pct=0}, {id=16814,pct=0}, {id=16822,pct=0},
    {id=16835,pct=0}, {id=16843,pct=0}, {id=16847,pct=0}, {id=16855,pct=0}, {id=16867,pct=0}, {id=17065,pct=0},
    {id=17069,pct=0}, {id=18252,pct=0}, {id=18257,pct=0}, {id=18259,pct=0}, {id=18260,pct=0}, {id=18264,pct=0},
    {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0}, {id=18292,pct=0}, {id=18820,pct=0}, {id=18821,pct=0},
    {id=18822,pct=0}, {id=18823,pct=0}, {id=18824,pct=0}, {id=18829,pct=0}, {id=18861,pct=0}, {id=19136,pct=0},
    {id=19142,pct=0}, {id=19143,pct=0}, {id=19144,pct=0}, {id=21371,pct=0},
  },
  [11983] = {
    {id=16899,pct=4}, {id=16907,pct=4}, {id=16913,pct=4}, {id=16920,pct=4}, {id=16928,pct=4}, {id=16940,pct=4},
    {id=16948,pct=4}, {id=16956,pct=4}, {id=16964,pct=4}, {id=19353,pct=4}, {id=19355,pct=4}, {id=19343,pct=0},
    {id=19344,pct=0}, {id=19365,pct=0}, {id=19394,pct=0}, {id=19395,pct=0}, {id=19396,pct=0}, {id=19397,pct=0},
    {id=19398,pct=0}, {id=19399,pct=0}, {id=19400,pct=0}, {id=19401,pct=0}, {id=19402,pct=0},
  },
  [11988] = {
    {id=17203,pct=37}, {id=17072,pct=25}, {id=17103,pct=25}, {id=18842,pct=25}, {id=17011,pct=14}, {id=16798,pct=0},
    {id=16809,pct=0}, {id=16815,pct=0}, {id=16820,pct=0}, {id=16833,pct=0}, {id=16841,pct=0}, {id=16845,pct=0},
    {id=16853,pct=0}, {id=16865,pct=0}, {id=18252,pct=0}, {id=18257,pct=0}, {id=18259,pct=0}, {id=18260,pct=0},
    {id=18264,pct=0}, {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0}, {id=18292,pct=0}, {id=18820,pct=0},
    {id=18821,pct=0}, {id=18822,pct=0}, {id=18823,pct=0}, {id=18824,pct=0}, {id=18829,pct=0}, {id=18861,pct=0},
    {id=19136,pct=0}, {id=19142,pct=0}, {id=19143,pct=0}, {id=19144,pct=0}, {id=21371,pct=0},
  },
  [12017] = {
    {id=20383,pct=100}, {id=16898,pct=0}, {id=16906,pct=0}, {id=16912,pct=0}, {id=16919,pct=0}, {id=16927,pct=0},
    {id=16941,pct=0}, {id=16949,pct=0}, {id=16957,pct=0}, {id=16965,pct=0}, {id=19341,pct=0}, {id=19342,pct=0},
    {id=19350,pct=0}, {id=19351,pct=0}, {id=19373,pct=0}, {id=19374,pct=0},
  },
  [12056] = {
    {id=16836,pct=30}, {id=16844,pct=30}, {id=16856,pct=30}, {id=17010,pct=14}, {id=18563,pct=4}, {id=16797,pct=0},
    {id=16807,pct=0}, {id=17110,pct=0}, {id=18252,pct=0}, {id=18257,pct=0}, {id=18259,pct=0}, {id=18260,pct=0},
    {id=18264,pct=0}, {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0}, {id=18292,pct=0}, {id=18820,pct=0},
    {id=18821,pct=0}, {id=18822,pct=0}, {id=18823,pct=0}, {id=18824,pct=0}, {id=18829,pct=0}, {id=18861,pct=0},
    {id=19136,pct=0}, {id=19142,pct=0}, {id=19143,pct=0}, {id=19144,pct=0}, {id=21371,pct=0},
  },
  [12057] = {
    {id=17105,pct=20}, {id=18832,pct=20}, {id=17011,pct=14}, {id=18564,pct=4}, {id=16795,pct=0}, {id=16808,pct=0},
    {id=16813,pct=0}, {id=16821,pct=0}, {id=16834,pct=0}, {id=16842,pct=0}, {id=16846,pct=0}, {id=16854,pct=0},
    {id=16866,pct=0}, {id=17066,pct=0}, {id=17071,pct=0}, {id=18252,pct=0}, {id=18257,pct=0}, {id=18259,pct=0},
    {id=18260,pct=0}, {id=18264,pct=0}, {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0}, {id=18292,pct=0},
    {id=18820,pct=0}, {id=18821,pct=0}, {id=18822,pct=0}, {id=18823,pct=0}, {id=18824,pct=0}, {id=18829,pct=0},
    {id=18861,pct=0}, {id=19136,pct=0}, {id=19142,pct=0}, {id=19143,pct=0}, {id=19144,pct=0}, {id=21371,pct=0},
  },
  [12098] = {
    {id=17330,pct=100}, {id=16823,pct=33}, {id=16868,pct=33}, {id=16816,pct=0}, {id=16848,pct=0}, {id=17074,pct=0},
    {id=17077,pct=0}, {id=18861,pct=0}, {id=18870,pct=0}, {id=18872,pct=0}, {id=18875,pct=0}, {id=18878,pct=0},
    {id=18879,pct=0}, {id=19145,pct=0}, {id=19146,pct=0}, {id=19147,pct=0},
  },
  [12118] = {
    {id=16665,pct=100}, {id=17329,pct=100}, {id=16805,pct=33}, {id=16863,pct=33}, {id=16800,pct=0}, {id=16829,pct=0},
    {id=16837,pct=0}, {id=16859,pct=0}, {id=17077,pct=0}, {id=17109,pct=0}, {id=18252,pct=0}, {id=18257,pct=0},
    {id=18259,pct=0}, {id=18260,pct=0}, {id=18264,pct=0}, {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0},
    {id=18292,pct=0}, {id=18861,pct=0}, {id=18870,pct=0}, {id=18872,pct=0}, {id=18875,pct=0}, {id=18878,pct=0},
    {id=18879,pct=0}, {id=19145,pct=0}, {id=19146,pct=0}, {id=19147,pct=0}, {id=21371,pct=0},
  },
  [12201] = {
    {id=17707,pct=0}, {id=17710,pct=0}, {id=17711,pct=0}, {id=17715,pct=0}, {id=17766,pct=0},
  },
  [12203] = {
    {id=17734,pct=0}, {id=17736,pct=0}, {id=17737,pct=0}, {id=17943,pct=0},
  },
  [12225] = {
    {id=17738,pct=0}, {id=17739,pct=0}, {id=17740,pct=0},
  },
  [12236] = {
    {id=17703,pct=100}, {id=17752,pct=0}, {id=17754,pct=0}, {id=17755,pct=0},
  },
  [12258] = {
    {id=4808,pct=5}, {id=17748,pct=0}, {id=17749,pct=0}, {id=17750,pct=0}, {id=17751,pct=0},
  },
  [12259] = {
    {id=17331,pct=100}, {id=16849,pct=25}, {id=16862,pct=25}, {id=16812,pct=0}, {id=16826,pct=0}, {id=16839,pct=0},
    {id=16860,pct=0}, {id=17077,pct=0}, {id=18252,pct=0}, {id=18257,pct=0}, {id=18259,pct=0}, {id=18260,pct=0},
    {id=18264,pct=0}, {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0}, {id=18292,pct=0}, {id=18861,pct=0},
    {id=18870,pct=0}, {id=18872,pct=0}, {id=18875,pct=0}, {id=18878,pct=0}, {id=18879,pct=0}, {id=19145,pct=0},
    {id=19146,pct=0}, {id=19147,pct=0}, {id=21371,pct=0},
  },
  [12264] = {
    {id=17332,pct=100}, {id=16803,pct=25}, {id=16811,pct=25}, {id=16824,pct=25}, {id=16801,pct=0}, {id=16831,pct=0},
    {id=16852,pct=0}, {id=17077,pct=0}, {id=18252,pct=0}, {id=18257,pct=0}, {id=18259,pct=0}, {id=18260,pct=0},
    {id=18264,pct=0}, {id=18265,pct=0}, {id=18290,pct=0}, {id=18291,pct=0}, {id=18292,pct=0}, {id=18861,pct=0},
    {id=18870,pct=0}, {id=18872,pct=0}, {id=18875,pct=0}, {id=18878,pct=0}, {id=18879,pct=0}, {id=19145,pct=0},
    {id=19146,pct=0}, {id=19147,pct=0}, {id=21371,pct=0},
  },
  [12435] = {
    {id=16904,pct=0}, {id=16911,pct=0}, {id=16918,pct=0}, {id=16926,pct=0}, {id=16934,pct=0}, {id=16935,pct=0},
    {id=16943,pct=0}, {id=16951,pct=0}, {id=16959,pct=0}, {id=19334,pct=0}, {id=19335,pct=0}, {id=19336,pct=0},
    {id=19337,pct=0}, {id=19369,pct=0}, {id=19370,pct=0},
  },
  [13020] = {
    {id=16818,pct=0}, {id=16903,pct=0}, {id=16910,pct=0}, {id=16925,pct=0}, {id=16933,pct=0}, {id=16936,pct=0},
    {id=16944,pct=0}, {id=16952,pct=0}, {id=16960,pct=0}, {id=19339,pct=0}, {id=19340,pct=0}, {id=19346,pct=0},
    {id=19348,pct=0}, {id=19371,pct=0}, {id=19372,pct=0},
  },
  [13280] = {
    {id=18299,pct=100}, {id=18317,pct=20}, {id=18322,pct=20}, {id=18324,pct=10}, {id=19268,pct=2}, {id=18305,pct=0},
    {id=18307,pct=0},
  },
  [13282] = {
    {id=17702,pct=100}, {id=17745,pct=20}, {id=17744,pct=0}, {id=17746,pct=0},
  },
  [13596] = {
    {id=17730,pct=20}, {id=17728,pct=0}, {id=17732,pct=0},
  },
  [13601] = {
    {id=17717,pct=0}, {id=17718,pct=0}, {id=17719,pct=0},
  },
  [14020] = {
    {id=19347,pct=10}, {id=19349,pct=10}, {id=19352,pct=10}, {id=19361,pct=10}, {id=16832,pct=0}, {id=16902,pct=0},
    {id=16917,pct=0}, {id=16924,pct=0}, {id=16932,pct=0}, {id=16937,pct=0}, {id=16945,pct=0}, {id=16953,pct=0},
    {id=16961,pct=0}, {id=19385,pct=0}, {id=19386,pct=0}, {id=19387,pct=0}, {id=19388,pct=0}, {id=19389,pct=0},
    {id=19390,pct=0}, {id=19391,pct=0}, {id=19392,pct=0}, {id=19393,pct=0},
  },
  [14321] = {
    {id=18450,pct=0}, {id=18451,pct=0}, {id=18458,pct=0}, {id=18459,pct=0}, {id=18460,pct=0}, {id=18462,pct=0},
    {id=18463,pct=0}, {id=18464,pct=0},
  },
  [14322] = {
    {id=18425,pct=40},
  },
  [14323] = {
    {id=18450,pct=0}, {id=18451,pct=0}, {id=18458,pct=0}, {id=18459,pct=0}, {id=18460,pct=0}, {id=18462,pct=0},
    {id=18463,pct=0}, {id=18464,pct=0}, {id=18493,pct=0}, {id=18494,pct=0}, {id=18496,pct=0}, {id=18497,pct=0},
    {id=18498,pct=0},
  },
  [14324] = {
    {id=18483,pct=0}, {id=18484,pct=0}, {id=18485,pct=0}, {id=18490,pct=0},
  },
  [14325] = {
    {id=18502,pct=0}, {id=18503,pct=0}, {id=18505,pct=0}, {id=18507,pct=0},
  },
  [14326] = {
    {id=18450,pct=0}, {id=18451,pct=0}, {id=18458,pct=0}, {id=18459,pct=0}, {id=18460,pct=0}, {id=18462,pct=0},
    {id=18463,pct=0}, {id=18464,pct=0}, {id=18493,pct=0}, {id=18494,pct=0}, {id=18496,pct=0}, {id=18497,pct=0},
    {id=18498,pct=0},
  },
  [14327] = {
    {id=18426,pct=100}, {id=18311,pct=10}, {id=18301,pct=0}, {id=18302,pct=0}, {id=18325,pct=0},
  },
  [14507] = {
    {id=22216,pct=100}, {id=19722,pct=3}, {id=19723,pct=3}, {id=19724,pct=3}, {id=19716,pct=0}, {id=19717,pct=0},
    {id=19718,pct=0}, {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19900,pct=0}, {id=19903,pct=0},
    {id=19904,pct=0}, {id=19905,pct=0}, {id=19906,pct=0}, {id=19907,pct=0}, {id=22711,pct=0}, {id=22712,pct=0},
    {id=22713,pct=0}, {id=22714,pct=0}, {id=22715,pct=0}, {id=22716,pct=0}, {id=22718,pct=0}, {id=22720,pct=0},
    {id=22721,pct=0}, {id=22722,pct=0},
  },
  [14509] = {
    {id=19722,pct=3}, {id=19723,pct=3}, {id=19724,pct=3}, {id=19902,pct=2}, {id=19716,pct=0}, {id=19717,pct=0},
    {id=19718,pct=0}, {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19896,pct=0}, {id=19897,pct=0},
    {id=19898,pct=0}, {id=19899,pct=0}, {id=19901,pct=0}, {id=20260,pct=0}, {id=20266,pct=0}, {id=22711,pct=0},
    {id=22712,pct=0}, {id=22713,pct=0}, {id=22714,pct=0}, {id=22715,pct=0}, {id=22716,pct=0}, {id=22718,pct=0},
    {id=22720,pct=0}, {id=22721,pct=0}, {id=22722,pct=0},
  },
  [14510] = {
    {id=19722,pct=3}, {id=19723,pct=3}, {id=19724,pct=3}, {id=19716,pct=0}, {id=19717,pct=0}, {id=19718,pct=0},
    {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19871,pct=0}, {id=19919,pct=0}, {id=19925,pct=0},
    {id=19927,pct=0}, {id=19930,pct=0}, {id=20032,pct=0}, {id=22711,pct=0}, {id=22712,pct=0}, {id=22713,pct=0},
    {id=22714,pct=0}, {id=22715,pct=0}, {id=22716,pct=0}, {id=22718,pct=0}, {id=22720,pct=0}, {id=22721,pct=0},
    {id=22722,pct=0},
  },
  [14515] = {
    {id=19722,pct=3}, {id=19723,pct=3}, {id=19724,pct=3}, {id=19716,pct=0}, {id=19717,pct=0}, {id=19718,pct=0},
    {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19909,pct=0}, {id=19910,pct=0}, {id=19912,pct=0},
    {id=19913,pct=0}, {id=19914,pct=0}, {id=19922,pct=0}, {id=22711,pct=0}, {id=22712,pct=0}, {id=22713,pct=0},
    {id=22714,pct=0}, {id=22715,pct=0}, {id=22716,pct=0}, {id=22718,pct=0}, {id=22720,pct=0}, {id=22721,pct=0},
    {id=22722,pct=0},
  },
  [14517] = {
    {id=19722,pct=3}, {id=19723,pct=3}, {id=19724,pct=3}, {id=19716,pct=0}, {id=19717,pct=0}, {id=19718,pct=0},
    {id=19719,pct=0}, {id=19720,pct=0}, {id=19721,pct=0}, {id=19915,pct=0}, {id=19918,pct=0}, {id=19920,pct=0},
    {id=19923,pct=0}, {id=19928,pct=0}, {id=20262,pct=0}, {id=20265,pct=0}, {id=22711,pct=0}, {id=22712,pct=0},
    {id=22713,pct=0}, {id=22714,pct=0}, {id=22715,pct=0}, {id=22716,pct=0}, {id=22718,pct=0}, {id=22720,pct=0},
    {id=22721,pct=0}, {id=22722,pct=0},
  },
  [14601] = {
    {id=19368,pct=10}, {id=16899,pct=4}, {id=16907,pct=4}, {id=16913,pct=4}, {id=16920,pct=4}, {id=16928,pct=4},
    {id=16940,pct=4}, {id=16948,pct=4}, {id=16956,pct=4}, {id=16964,pct=4}, {id=19353,pct=4}, {id=19355,pct=4},
    {id=19345,pct=0}, {id=19394,pct=0}, {id=19395,pct=0}, {id=19396,pct=0}, {id=19397,pct=0}, {id=19403,pct=0},
    {id=19405,pct=0}, {id=19406,pct=0}, {id=19407,pct=0},
  },
  [14834] = {
    {id=19802,pct=100}, {id=19852,pct=0}, {id=19853,pct=0}, {id=19854,pct=0}, {id=19855,pct=0}, {id=19856,pct=0},
    {id=19857,pct=0}, {id=19859,pct=0}, {id=19861,pct=0}, {id=19862,pct=0}, {id=19864,pct=0}, {id=19865,pct=0},
    {id=19876,pct=0}, {id=20257,pct=0}, {id=20264,pct=0},
  },
  [15082] = {
    {id=19939,pct=100}, {id=19961,pct=0}, {id=19962,pct=0},
  },
  [15083] = {
    {id=19942,pct=100}, {id=19967,pct=0}, {id=19968,pct=0},
  },
  [15084] = {
    {id=19940,pct=100}, {id=19963,pct=0}, {id=19964,pct=0},
  },
  [15085] = {
    {id=19941,pct=100}, {id=19965,pct=0}, {id=19993,pct=0},
  },
  [15114] = {
    {id=22739,pct=15}, {id=19944,pct=10}, {id=19945,pct=10}, {id=19946,pct=0}, {id=19947,pct=0},
  },
  [15263] = {
    {id=22222,pct=15}, {id=21128,pct=10}, {id=21703,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0},
    {id=20730,pct=0}, {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0},
    {id=21698,pct=0}, {id=21699,pct=0}, {id=21700,pct=0}, {id=21701,pct=0}, {id=21702,pct=0}, {id=21704,pct=0},
    {id=21705,pct=0}, {id=21706,pct=0}, {id=21707,pct=0}, {id=21708,pct=0}, {id=21814,pct=0},
  },
  [15276] = {
    {id=20930,pct=100}, {id=20735,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0},
    {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21597,pct=0},
    {id=21598,pct=0}, {id=21599,pct=0}, {id=21600,pct=0}, {id=21601,pct=0}, {id=21602,pct=0},
  },
  [15299] = {
    {id=20928,pct=100}, {id=20932,pct=100}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0},
    {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21622,pct=0},
    {id=21623,pct=0}, {id=21624,pct=0}, {id=21625,pct=0}, {id=21626,pct=0}, {id=21677,pct=0}, {id=22399,pct=0},
  },
  [15339] = {
    {id=21220,pct=100}, {id=20886,pct=40}, {id=20890,pct=40}, {id=20884,pct=10}, {id=20888,pct=10}, {id=21459,pct=10},
    {id=21715,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0}, {id=20731,pct=0},
    {id=20734,pct=0}, {id=20736,pct=0}, {id=21214,pct=0}, {id=21279,pct=0}, {id=21280,pct=0}, {id=21281,pct=0},
    {id=21282,pct=0}, {id=21283,pct=0}, {id=21284,pct=0}, {id=21285,pct=0}, {id=21287,pct=0}, {id=21288,pct=0},
    {id=21289,pct=0}, {id=21290,pct=0}, {id=21291,pct=0}, {id=21292,pct=0}, {id=21293,pct=0}, {id=21294,pct=0},
    {id=21295,pct=0}, {id=21296,pct=0}, {id=21297,pct=0}, {id=21298,pct=0}, {id=21299,pct=0}, {id=21300,pct=0},
    {id=21302,pct=0}, {id=21303,pct=0}, {id=21304,pct=0}, {id=21306,pct=0}, {id=21307,pct=0}, {id=21452,pct=0},
    {id=21453,pct=0}, {id=21454,pct=0}, {id=21456,pct=0}, {id=21458,pct=0}, {id=21460,pct=0}, {id=21461,pct=0},
    {id=21462,pct=0}, {id=21463,pct=0}, {id=21464,pct=0},
  },
  [15340] = {
    {id=20886,pct=40}, {id=20890,pct=40}, {id=22220,pct=15}, {id=20884,pct=10}, {id=20888,pct=10}, {id=21467,pct=10},
    {id=21471,pct=10}, {id=21472,pct=10}, {id=21479,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0},
    {id=20730,pct=0}, {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21214,pct=0}, {id=21279,pct=0},
    {id=21280,pct=0}, {id=21281,pct=0}, {id=21282,pct=0}, {id=21283,pct=0}, {id=21284,pct=0}, {id=21285,pct=0},
    {id=21287,pct=0}, {id=21288,pct=0}, {id=21289,pct=0}, {id=21290,pct=0}, {id=21291,pct=0}, {id=21292,pct=0},
    {id=21293,pct=0}, {id=21294,pct=0}, {id=21295,pct=0}, {id=21296,pct=0}, {id=21297,pct=0}, {id=21298,pct=0},
    {id=21299,pct=0}, {id=21300,pct=0}, {id=21302,pct=0}, {id=21303,pct=0}, {id=21304,pct=0}, {id=21306,pct=0},
    {id=21307,pct=0}, {id=21455,pct=0}, {id=21468,pct=0}, {id=21469,pct=0}, {id=21470,pct=0}, {id=21473,pct=0},
    {id=21474,pct=0}, {id=21475,pct=0}, {id=21476,pct=0}, {id=21477,pct=0},
  },
  [15341] = {
    {id=20885,pct=40}, {id=20889,pct=40}, {id=20884,pct=10}, {id=20888,pct=10}, {id=21492,pct=10}, {id=21493,pct=10},
    {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0}, {id=20731,pct=0}, {id=20734,pct=0},
    {id=20736,pct=0}, {id=21214,pct=0}, {id=21279,pct=0}, {id=21280,pct=0}, {id=21281,pct=0}, {id=21282,pct=0},
    {id=21283,pct=0}, {id=21284,pct=0}, {id=21285,pct=0}, {id=21287,pct=0}, {id=21288,pct=0}, {id=21289,pct=0},
    {id=21290,pct=0}, {id=21291,pct=0}, {id=21292,pct=0}, {id=21293,pct=0}, {id=21294,pct=0}, {id=21295,pct=0},
    {id=21296,pct=0}, {id=21297,pct=0}, {id=21298,pct=0}, {id=21299,pct=0}, {id=21300,pct=0}, {id=21302,pct=0},
    {id=21303,pct=0}, {id=21304,pct=0}, {id=21306,pct=0}, {id=21307,pct=0}, {id=21494,pct=0}, {id=21495,pct=0},
    {id=21496,pct=0}, {id=21497,pct=0},
  },
  [15348] = {
    {id=22217,pct=100}, {id=20885,pct=40}, {id=20889,pct=40}, {id=20884,pct=10}, {id=20888,pct=10}, {id=21498,pct=10},
    {id=21499,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0}, {id=20731,pct=0},
    {id=20734,pct=0}, {id=20736,pct=0}, {id=21214,pct=0}, {id=21279,pct=0}, {id=21280,pct=0}, {id=21281,pct=0},
    {id=21282,pct=0}, {id=21283,pct=0}, {id=21284,pct=0}, {id=21285,pct=0}, {id=21287,pct=0}, {id=21288,pct=0},
    {id=21289,pct=0}, {id=21290,pct=0}, {id=21291,pct=0}, {id=21292,pct=0}, {id=21293,pct=0}, {id=21294,pct=0},
    {id=21295,pct=0}, {id=21296,pct=0}, {id=21297,pct=0}, {id=21298,pct=0}, {id=21299,pct=0}, {id=21300,pct=0},
    {id=21302,pct=0}, {id=21303,pct=0}, {id=21304,pct=0}, {id=21306,pct=0}, {id=21307,pct=0}, {id=21500,pct=0},
    {id=21501,pct=0}, {id=21502,pct=0}, {id=21503,pct=0},
  },
  [15369] = {
    {id=20884,pct=30}, {id=20888,pct=30}, {id=20885,pct=10}, {id=20886,pct=10}, {id=20889,pct=10}, {id=20890,pct=10},
    {id=21478,pct=10}, {id=21466,pct=5}, {id=21479,pct=5}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0},
    {id=20730,pct=0}, {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21214,pct=0}, {id=21279,pct=0},
    {id=21280,pct=0}, {id=21281,pct=0}, {id=21282,pct=0}, {id=21283,pct=0}, {id=21284,pct=0}, {id=21285,pct=0},
    {id=21287,pct=0}, {id=21288,pct=0}, {id=21289,pct=0}, {id=21290,pct=0}, {id=21291,pct=0}, {id=21292,pct=0},
    {id=21293,pct=0}, {id=21294,pct=0}, {id=21295,pct=0}, {id=21296,pct=0}, {id=21297,pct=0}, {id=21298,pct=0},
    {id=21299,pct=0}, {id=21300,pct=0}, {id=21302,pct=0}, {id=21303,pct=0}, {id=21304,pct=0}, {id=21306,pct=0},
    {id=21307,pct=0}, {id=21480,pct=0}, {id=21481,pct=0}, {id=21482,pct=0}, {id=21483,pct=0}, {id=21484,pct=0},
  },
  [15370] = {
    {id=20884,pct=10}, {id=20885,pct=10}, {id=20886,pct=10}, {id=20888,pct=10}, {id=20889,pct=10}, {id=20890,pct=10},
    {id=21485,pct=10}, {id=21486,pct=10}, {id=21487,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0},
    {id=20730,pct=0}, {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21214,pct=0}, {id=21279,pct=0},
    {id=21280,pct=0}, {id=21281,pct=0}, {id=21282,pct=0}, {id=21283,pct=0}, {id=21284,pct=0}, {id=21285,pct=0},
    {id=21287,pct=0}, {id=21288,pct=0}, {id=21289,pct=0}, {id=21290,pct=0}, {id=21291,pct=0}, {id=21292,pct=0},
    {id=21293,pct=0}, {id=21294,pct=0}, {id=21295,pct=0}, {id=21296,pct=0}, {id=21297,pct=0}, {id=21298,pct=0},
    {id=21299,pct=0}, {id=21300,pct=0}, {id=21302,pct=0}, {id=21303,pct=0}, {id=21304,pct=0}, {id=21306,pct=0},
    {id=21307,pct=0}, {id=21488,pct=0}, {id=21489,pct=0}, {id=21490,pct=0}, {id=21491,pct=0},
  },
  [15509] = {
    {id=20928,pct=100}, {id=20932,pct=100}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0},
    {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21616,pct=0},
    {id=21617,pct=0}, {id=21618,pct=0}, {id=21619,pct=0}, {id=21620,pct=0}, {id=21621,pct=0},
  },
  [15510] = {
    {id=21635,pct=10}, {id=21650,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0},
    {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21627,pct=0},
    {id=21645,pct=0}, {id=21647,pct=0}, {id=21651,pct=0}, {id=21652,pct=0}, {id=21663,pct=0}, {id=21664,pct=0},
    {id=21665,pct=0}, {id=22396,pct=0}, {id=22402,pct=0},
  },
  [15511] = {
    {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0}, {id=20731,pct=0}, {id=20734,pct=0},
    {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21603,pct=0}, {id=21680,pct=0}, {id=21681,pct=0},
    {id=21685,pct=0}, {id=21692,pct=0}, {id=21693,pct=0}, {id=21694,pct=0}, {id=21695,pct=0}, {id=21696,pct=0},
    {id=21697,pct=0},
  },
  [15516] = {
    {id=21666,pct=10}, {id=21673,pct=10}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0},
    {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21648,pct=0},
    {id=21667,pct=0}, {id=21668,pct=0}, {id=21669,pct=0}, {id=21670,pct=0}, {id=21671,pct=0}, {id=21672,pct=0},
    {id=21674,pct=0}, {id=21675,pct=0}, {id=21676,pct=0}, {id=21678,pct=0},
  },
  [15517] = {
    {id=20927,pct=100}, {id=20931,pct=100}, {id=20727,pct=0}, {id=20728,pct=0}, {id=20729,pct=0}, {id=20730,pct=0},
    {id=20731,pct=0}, {id=20734,pct=0}, {id=20736,pct=0}, {id=21232,pct=0}, {id=21237,pct=0}, {id=21610,pct=0},
    {id=21611,pct=0}, {id=21615,pct=0}, {id=23557,pct=0}, {id=23558,pct=0}, {id=23570,pct=0},
  },
  [15727] = {
    {id=20929,pct=100}, {id=20933,pct=100}, {id=21221,pct=100}, {id=22734,pct=100}, {id=21579,pct=15}, {id=21126,pct=8},
    {id=21134,pct=8}, {id=21839,pct=8}, {id=21581,pct=0}, {id=21582,pct=0}, {id=21583,pct=0}, {id=21585,pct=0},
    {id=21586,pct=0}, {id=21596,pct=0}, {id=22730,pct=0}, {id=22731,pct=0}, {id=22732,pct=0},
  },
  [15928] = {
    {id=22726,pct=30}, {id=22353,pct=0}, {id=22360,pct=0}, {id=22367,pct=0}, {id=22801,pct=0}, {id=22808,pct=0},
    {id=23000,pct=0}, {id=23001,pct=0}, {id=23070,pct=0},
  },
  [15931] = {
    {id=22726,pct=30}, {id=22354,pct=0}, {id=22361,pct=0}, {id=22368,pct=0}, {id=22803,pct=0}, {id=22810,pct=0},
    {id=22967,pct=0}, {id=22968,pct=0}, {id=22988,pct=0},
  },
  [15932] = {
    {id=22726,pct=30}, {id=22354,pct=0}, {id=22355,pct=0}, {id=22356,pct=0}, {id=22358,pct=0}, {id=22361,pct=0},
    {id=22362,pct=0}, {id=22363,pct=0}, {id=22365,pct=0}, {id=22368,pct=0}, {id=22369,pct=0}, {id=22370,pct=0},
    {id=22372,pct=0}, {id=22813,pct=0}, {id=22981,pct=0}, {id=22983,pct=0}, {id=22994,pct=0}, {id=23075,pct=0},
  },
  [15936] = {
    {id=22726,pct=30}, {id=22356,pct=0}, {id=22363,pct=0}, {id=22370,pct=0}, {id=23019,pct=0}, {id=23033,pct=0},
    {id=23035,pct=0}, {id=23036,pct=0}, {id=23068,pct=0},
  },
  [15952] = {
    {id=22726,pct=30}, {id=22357,pct=0}, {id=22364,pct=0}, {id=22371,pct=0}, {id=22804,pct=0}, {id=22807,pct=0},
    {id=22947,pct=0}, {id=22954,pct=0}, {id=23220,pct=0},
  },
  [15953] = {
    {id=22726,pct=30}, {id=22355,pct=0}, {id=22362,pct=0}, {id=22369,pct=0}, {id=22806,pct=0}, {id=22940,pct=0},
    {id=22941,pct=0}, {id=22942,pct=0}, {id=22943,pct=0},
  },
  [15954] = {
    {id=22726,pct=30}, {id=22356,pct=0}, {id=22363,pct=0}, {id=22370,pct=0}, {id=22816,pct=0}, {id=23005,pct=0},
    {id=23006,pct=0}, {id=23028,pct=0}, {id=23029,pct=0}, {id=23030,pct=0}, {id=23031,pct=0},
  },
  [15956] = {
    {id=22726,pct=30}, {id=22355,pct=0}, {id=22362,pct=0}, {id=22369,pct=0}, {id=22935,pct=0}, {id=22936,pct=0},
    {id=22937,pct=0}, {id=22938,pct=0}, {id=22939,pct=0},
  },
  [15989] = {
    {id=23040,pct=0}, {id=23041,pct=0}, {id=23043,pct=0}, {id=23045,pct=0}, {id=23046,pct=0}, {id=23047,pct=0},
    {id=23048,pct=0}, {id=23049,pct=0}, {id=23050,pct=0}, {id=23242,pct=0}, {id=23545,pct=0}, {id=23547,pct=0},
    {id=23548,pct=0}, {id=23549,pct=0},
  },
  [15990] = {
    {id=22520,pct=100}, {id=22733,pct=100}, {id=22798,pct=0}, {id=22799,pct=0}, {id=22802,pct=0}, {id=22812,pct=0},
    {id=22819,pct=0}, {id=22821,pct=0}, {id=23053,pct=0}, {id=23054,pct=0}, {id=23056,pct=0}, {id=23057,pct=0},
    {id=23059,pct=0}, {id=23060,pct=0}, {id=23061,pct=0}, {id=23062,pct=0}, {id=23063,pct=0}, {id=23064,pct=0},
    {id=23065,pct=0}, {id=23066,pct=0}, {id=23067,pct=0}, {id=23577,pct=0},
  },
  [16011] = {
    {id=22726,pct=30}, {id=22352,pct=0}, {id=22359,pct=0}, {id=22366,pct=0}, {id=22800,pct=0}, {id=23037,pct=0},
    {id=23038,pct=0}, {id=23039,pct=0}, {id=23042,pct=0},
  },
  [16028] = {
    {id=22726,pct=30}, {id=22354,pct=0}, {id=22361,pct=0}, {id=22368,pct=0}, {id=22815,pct=0}, {id=22818,pct=0},
    {id=22820,pct=0}, {id=22960,pct=0}, {id=22961,pct=0},
  },
  [16060] = {
    {id=22726,pct=30}, {id=22358,pct=0}, {id=22365,pct=0}, {id=22372,pct=0}, {id=23020,pct=0}, {id=23021,pct=0},
    {id=23023,pct=0}, {id=23032,pct=0}, {id=23073,pct=0},
  },
  [16061] = {
    {id=22726,pct=30}, {id=22358,pct=0}, {id=22365,pct=0}, {id=22372,pct=0}, {id=23004,pct=0}, {id=23009,pct=0},
    {id=23014,pct=0}, {id=23017,pct=0}, {id=23018,pct=0}, {id=23219,pct=0},
  },
}

NE.ej.LOOT = LOOT

-- Union-merge the overlay loot into NE.ej.DATA. Existing Data.lua items (and their
-- AtlasLoot drop rates) are kept verbatim; overlay items not already present are
-- appended; empty encounters are filled. Dedup by item id, never clobbers.
local function applyLoot()
  local data = NE.ej.DATA
  if not data then return end
  for _, inst in ipairs(data.instances or {}) do
    for _, enc in ipairs(inst.encounters or {}) do
      local add = LOOT[enc.id]
      if add then
        local loot = enc.loot or {}
        local seen = {}
        for _, e in ipairs(loot) do seen[e.id] = true end
        for _, e in ipairs(add) do
          if not seen[e.id] then
            seen[e.id] = true
            loot[#loot+1] = { id = e.id, pct = e.pct }
          end
        end
        enc.loot = loot
      end
    end
  end
end
applyLoot()
