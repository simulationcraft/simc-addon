local _, Simulationcraft = ...

-- simc stat abbreviations

Simulationcraft.SimcStatAbbr = {
  ['strength'] = 'str',
  ['agility'] = 'agi',
  ['stamina'] = 'sta',
  ['intellect'] = 'int',
  ['spirit'] = 'spi',
  
  ['spell_power'] = 'sp',
  ['attack_power'] = 'ap',
  ['expertise'] = 'exp',
  ['hit'] = 'hit',
  
  ['critical_strike'] = 'crit',
  ['crit'] = 'crit',
  ['haste'] = 'haste',
  ['mastery'] = 'mastery',
  ['armor'] = 'armor',
  ['bonus_armor'] = 'bonusarmor',
  
  ['resilience'] = 'resil',
  ['dodge'] = 'dodge',
  ['parry'] = 'parry',
  
  ['all_stats'] = 'all',
  ['damage'] = 'damage',
  -- guessing for the rest
  ['multistrike'] = 'mult',
  ['readiness'] = 'readiness',  
}

-- non-localized profession names from ids
Simulationcraft.ProfNames = {
  [129] = 'First Aid',
  [164] = 'Blacksmith',
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
-- Druid 
  [102] = 'Balance',
  [103] = 'Feral Combat',
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
  [260] = 'Combat',
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
  [72] = 'Furry',
  [73] = 'Protection'
}

-- slot name conversion stuff

Simulationcraft.slotNames = {"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "AmmoSlot" };    
Simulationcraft.simcSlotNames = {'head','neck','shoulder','back','chest','shirt','tabard','wrist','hands','waist','legs','feet','finger1','finger2','trinket1','trinket2','main_hand','off_hand','ammo'}

-- table for conversion to upgrade level, stolen from AMR

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
  [505] = 4
}

-- this just handles a limited number of enchants for use with
-- "old-style" export strings. "new-style" ones (using "enchant_id=xxxx")
-- don't need this at all. Also stolen from AMR ( <3 )

Simulationcraft.enchantNames = {
[-1000]="Belt Buckle",
[2]="Frostbrand",
[5]="Flametongue",
[25]="Shadow Oil",
[26]="Frost Oil",
[27]="Sundered",
[37]="Steel Weapon Chain",
[911]="Minor Speed Increase",
[912]="Demonslaying",
[1003]="Venomhide Poison",
[1894]="Icy Chill",
[1898]="Lifestealing",
[1899]="Unholy Weapon",
[1900]="Crusader",
[2673]="Mongoose",
[2674]="Spellsurge",
[2675]="Battlemaster",
[3223]="Adamantite Weapon Chain",
[3225]="Executioner",
[3238]="Gatherer",
[3239]="Icebreaker Weapon",
[3241]="Lifeward",
[3250]="Icewalker",
[3251]="Giantslaying",
[3345]="Earthliving",
[3364]="Empower Rune Weapon",
[3365]="Swordshattering",
[3366]="Lichbane",
[3367]="Spellshattering",
[3368]="Fallen Crusader",
[3369]="Cinderglacier",
[3370]="Razorice",
[3594]="Swordbreaking",
[3595]="Spellbreaking",
[3722]="Lightweave 1",
[3728]="Darkglow 1",
[3730]="Swordguard 1",
[3789]="Berserking",
[3790]="Black Magic",
[3847]="Stoneskin Gargoyle",
[3849]="Titanium Plating",
[3883]="Nerubian Carapace",
[4066]="Mending",
[4067]="Avalanche",
[4074]="Elemental Slayer",
[4083]="Hurricane",
[4084]="Heartsong",
[4097]="Power Torrent",
[4098]="Windwalk",
[4099]="Landslide",
[4115]="Lightweave 2",
[4116]="Darkglow 2",
[4117]="Swordguard Embroidery",
[4118]="Swordguard 2",
[4179]="Synapse Springs",
[4180]="Quickflip Deflection Plates",
[4181]="Tazik Shocker",
[4188]="Grounded Plasma Shield",
[4223]="Nitro Boosts",
[4267]="Flintlocke's Woodchucker",
[4441]="Windsong",
[4442]="Jade Spirit",
[4443]="Elemental Force",
[4444]="Dancing Steel",
[4445]="Colossus",
[4446]="River's Song",
[4688]="Samurai",
[4697]="Phase Fingers",
[4698]="Incindiary Fireworks Launcher",
[4699]="Lord Blastington's Scope of Doom",
[4700]="Mirror Scope",
[4717]="Pandamonium",
[4892]="Lightweave 3",
[4893]="Darkglow 3",
[4894]="Swordguard 3",
[5035]="Tyranny",
[5125]="Bloody Dancing Steel"}



