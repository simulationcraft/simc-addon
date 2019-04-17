local _, Simulationcraft = ...

Simulationcraft.RoleTable = {
  -- Death Knight
  [250] = 'tank',
  [251] = 'attack',
  [252] = 'attack',
  -- Demon Hunter
  [577] = 'attack',
  [581] = 'tank',
  -- Druid
  [102] = 'spell',
  [103] = 'attack',
  [104] = 'tank',
  [105] = 'attack',
  -- Hunter
  [253] = 'attack',
  [254] = 'attack',
  [255] = 'attack',
  -- Mage
  [62] = 'spell',
  [63] = 'spell',
  [64] = 'spell',
  -- Monk
  [268] = 'tank',
  [269] = 'attack',
  [270] = 'attack',
  -- Paladin
  [65] = 'attack',
  [66] = 'tank',
  [70] = 'attack',
  -- Priest
  [256] = 'spell',
  [257] = 'attack',
  [258] = 'spell',
  -- Rogue
  [259] = 'attack',
  [260] = 'attack',
  [261] = 'attack',
  -- Shaman
  [262] = 'spell',
  [263] = 'attack',
  [264] = 'attack',
  -- Warlock
  [265] = 'spell',
  [266] = 'spell',
  [267] = 'spell',
  -- Warrior
  [71] = 'attack',
  [72] = 'attack',
  [73] = 'tank'
}

-- regionID lookup
Simulationcraft.RegionString = {
  [1] = 'us',
  [2] = 'kr',
  [3] = 'eu',
  [4] = 'tw',
  [5] = 'cn'
}

-- non-localized profession names from ids
Simulationcraft.ProfNames = {
  [129] = 'First Aid',
  [164] = 'Blacksmithing',
  [165] = 'Leatherworking',
  [171] = 'Alchemy',
  [182] = 'Herbalism',
  [184] = 'Cooking',
  [186] = 'Mining',
  [197] = 'Tailoring',
  [202] = 'Engineering',
  [333] = 'Enchanting',
  [356] = 'Fishing',
  [393] = 'Skinning',
  [755] = 'Jewelcrafting',
  [773] = 'Inscription',
  [794] = 'Archaeology'  
}

-- non-localized spec names from spec ids
Simulationcraft.SpecNames = {
-- Death Knight
  [250] = 'Blood',
  [251] = 'Frost',
  [252] = 'Unholy',
-- Demon Hunter
  [577] = 'Havoc',
  [581] = 'Vengeance',
-- Druid 
  [102] = 'Balance',
  [103] = 'Feral',
  [104] = 'Guardian',
  [105] = 'Restoration',
-- Hunter 
  [253] = 'Beast Mastery',
  [254] = 'Marksmanship',
  [255] = 'Survival',
-- Mage 
  [62] = 'Arcane',
  [63] = 'Fire',
  [64] = 'Frost',
-- Monk 
  [268] = 'Brewmaster',
  [269] = 'Windwalker',
  [270] = 'Mistweaver',
-- Paladin 
  [65] = 'Holy',
  [66] = 'Protection',
  [70] = 'Retribution',
-- Priest 
  [256] = 'Discipline',
  [257] = 'Holy',
  [258] = 'Shadow',
-- Rogue 
  [259] = 'Assassination',
  [260] = 'Outlaw',
  [261] = 'Subtlety',
-- Shaman 
  [262] = 'Elemental',
  [263] = 'Enhancement',
  [264] = 'Restoration',
-- Warlock 
  [265] = 'Affliction',
  [266] = 'Demonology',
  [267] = 'Destruction',
-- Warrior 
  [71] = 'Arms',
  [72] = 'Fury',
  [73] = 'Protection'
}

-- slot name conversion stuff

-- The array indexes are NOT the slot ids - they are the "slot numbers" used by this addons.
Simulationcraft.slotNames = {
	"HeadSlot", -- [1]
	"NeckSlot", -- [2]
	"ShoulderSlot", -- [3]
	"BackSlot", -- [4]
	"ChestSlot", -- [5]
	"ShirtSlot", -- [6]
	"TabardSlot", -- [7]
	"WristSlot", -- [8]
	"HandsSlot", -- [9]
	"WaistSlot", -- [10]
	"LegsSlot", -- [11]
	"FeetSlot", -- [12]
	"Finger0Slot", -- [13]
	"Finger1Slot", -- [14]
	"Trinket0Slot", -- [15]
	"Trinket1Slot", -- [16]
	"MainHandSlot", -- [17]
	"SecondaryHandSlot", -- [18]
	"AmmoSlot" -- [19]
}
-- The array indexes are NOT the slot ids - they are the "slot numbers" used by this addons.
Simulationcraft.simcSlotNames = {
	'head', -- [1]
	'neck', -- [2]
	'shoulder', -- [3]
	'back', -- [4]
	'chest', -- [5]
	'shirt', -- [6]
	'tabard', -- [7]
	'wrist', -- [8]
	'hands', -- [9]
	'waist', -- [10]
	'legs', -- [11]
	'feet', -- [12]
	'finger1', -- [13]
	'finger2', -- [14]
	'trinket1', -- [15]
	'trinket2', -- [16]
	'main_hand', -- [17]
	'off_hand', -- [18]
	'ammo', -- [19]
}
-- Map of the INVTYPE_ returned by GetItemInfo to the slot number (NOT the slot id).
Simulationcraft.invTypeToSlotNum = {
	INVTYPE_HEAD=1,
	INVTYPE_NECK=2,
	INVTYPE_SHOULDER=3,
	INVTYPE_CLOAK=4,
	INVTYPE_CHEST=5, INVTYPE_ROBE=5, -- These are the same slot - which one is used appears to differ based on whether the item's model covers the legs.
	INVTYPE_BODY=6, -- shirt.
	INVTYPE_TABARD=7,
	INVTYPE_WRIST=8,
	INVTYPE_HAND=9,
	INVTYPE_WAIST=10,
	INVTYPE_LEGS=11,
	INVTYPE_FEET=12,
	INVTYPE_FINGER=13,
	-- 14 is also a finger slot number.
	INVTYPE_TRINKET=15,
	-- 16 is also a trinket slot number.
	INVTYPE_WEAPON=17, -- 1h weapon.
	INVTYPE_2HWEAPON=17, -- 2h weapon.
	INVTYPE_RANGED=17, -- bows.
	INVTYPE_RANGEDRIGHT=17, -- Guns, wands, crossbows.
	INVTYPE_SHIELD=18,
	INVTYPE_HOLDABLE=18, -- off hand, but not a weapon or shield.

	-- These types are no longer used in current content.
	INVTYPE_WEAPONMAINHAND=17, -- Likely no items have this type anymore.
	INVTYPE_WEAPONOFFHAND=18, -- Likely no items have this type anymore.
	INVTYPE_THROWN=17, -- Thrown weapons. I do not know if this slot number is correct, but it shouldn't matter since these are no longer obtainable and those that do exist are now gray items.
	--INVTYPE_RELIC=?, -- No corresponding slot number, and I do not think any such items exist. Existing relics were turned into non-equipable gray items. This is value is not used for legion relics either.
}

-- table for conversion to upgrade level, stolen from AMR (<3)

Simulationcraft.upgradeTable = {
  [0]   =  0,
  [1]   =  1, -- 1/1 -> 8
  [373] =  1, -- 1/2 -> 4
  [374] =  2, -- 2/2 -> 8
  [375] =  1, -- 1/3 -> 4
  [376] =  2, -- 2/3 -> 4
  [377] =  3, -- 3/3 -> 4
  [378] =  1, -- 1/1 -> 7
  [379] =  1, -- 1/2 -> 4
  [380] =  2, -- 2/2 -> 4
  [445] =  0, -- 0/2 -> 0
  [446] =  1, -- 1/2 -> 4
  [447] =  2, -- 2/2 -> 8
  [451] =  0, -- 0/1 -> 0
  [452] =  1, -- 1/1 -> 8
  [453] =  0, -- 0/2 -> 0
  [454] =  1, -- 1/2 -> 4
  [455] =  2, -- 2/2 -> 8
  [456] =  0, -- 0/1 -> 0
  [457] =  1, -- 1/1 -> 8
  [458] =  0, -- 0/4 -> 0
  [459] =  1, -- 1/4 -> 4
  [460] =  2, -- 2/4 -> 8
  [461] =  3, -- 3/4 -> 12
  [462] =  4, -- 4/4 -> 16
  [465] =  0, -- 0/2 -> 0
  [466] =  1, -- 1/2 -> 4
  [467] =  2, -- 2/2 -> 8
  [468] =  0, -- 0/4 -> 0
  [469] =  1, -- 1/4 -> 4
  [470] =  2, -- 2/4 -> 8
  [471] =  3, -- 3/4 -> 12
  [472] =  4, -- 4/4 -> 16
  [476] =  0, -- ? -> 0
  [479] =  0, -- ? -> 0
  [491] =  0, -- ? -> 0
  [492] =  1, -- ? -> 0
  [493] =  2, -- ? -> 0
  [494] = 0,
  [495] = 1,
  [496] = 2,
  [497] = 3,
  [498] = 4,
  [504] = 3,
  [505] = 4,
  -- WOW-20726patch6.2.3_Retail
  [529] = 0, -- 0/2 -> 0
  [530] = 1, -- 1/2 -> 5
  [531] = 2 -- 2/2 -> 10
}

Simulationcraft.zandalariLoaBuffs = {
  [292359] = 'akunda',
  [292360] = 'bwonsamdi',
  [292362] = 'gonk',
  [292363] = 'kimbul',
  [292364] = 'kragwa',
  [292361] = 'paku',
}

Simulationcraft.azeriteEssenceSlotsMajor = {
  0
}

Simulationcraft.azeriteEssenceSlotsMinor = {
  1,
  2
}
