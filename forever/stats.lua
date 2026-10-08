-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, Simulationcraft = ...   -- same shared addon table as core.lua / extras.lua

-- Grab a bunch of character stats/buffs to have available for verification

-- Calls a global stat API by name and returns its results, or nil if the API
-- is missing in this client or errors
local function CallStatAPI(name, ...)
  local fn = _G[name]
  if type(fn) ~= 'function' then return nil end
  local results = { pcall(fn, ...) }
  if not results[1] then return nil end
  return unpack(results, 2)
end

local function FormatStatValue(value)
  if value == math.floor(value) then
    return string.format('%d', value)
  end
  return string.format('%.2f', value)
end

local function AddStat(stats, name, value)
  if type(value) == 'number' then
    stats[#stats + 1] = name .. ':' .. FormatStatValue(value)
  end
end

local PRIMARY_STAT_NAMES = { 'strength', 'agility', 'stamina', 'intellect', 'spirit' }

local POWER_TYPES = {
  { 'mana',   Enum.PowerType.Mana },
  { 'rage',   Enum.PowerType.Rage },
  { 'focus',  Enum.PowerType.Focus },
  { 'energy', Enum.PowerType.Energy },
}

-- Spell school indices as used by GetSpellBonusDamage / UnitResistance (physical is 1 / 0)
local SPELL_SCHOOL_NAMES = { 'physical', 'holy', 'fire', 'nature', 'frost', 'shadow', 'arcane' }

local function AddPrimaryStats(lines, unit, prefix)
  local total, base, bonus = {}, {}, {}
  AddStat(total, 'health', (CallStatAPI('UnitHealthMax', unit)))

  -- current power type
  AddStat(total, 'power_type', (CallStatAPI('UnitPowerType', unit)))

  -- max of all power types
  for _, power in ipairs(POWER_TYPES) do
    AddStat(total, power[1], (CallStatAPI('UnitPowerMax', unit, power[2])))
  end

  for statIndex, statName in ipairs(PRIMARY_STAT_NAMES) do
    local stat, effectiveStat, posBuff, negBuff = CallStatAPI('UnitStat', unit, statIndex)
    if type(stat) == 'number' then
      AddStat(total, statName, effectiveStat or stat)
      -- base is innate (race/class/level); bonus is everything else: gear, enchants, talents, auras
      AddStat(base, statName, stat - (posBuff or 0) - (negBuff or 0))
      AddStat(bonus, statName, (posBuff or 0) + (negBuff or 0))
    end
  end

  lines[#lines + 1] = { prefix .. 'stats', total }
  lines[#lines + 1] = { prefix .. 'stats_base', base }
  lines[#lines + 1] = { prefix .. 'stats_bonus', bonus }
end

-- Stats summed from every equipped item link. GetItemStats does not include enchants.
local function AddGearStats(lines)
  local GetItemStats = C_Item and C_Item.GetItemStats or _G.GetItemStats
  if not GetItemStats then return end

  local gearTotals = {}
  for slotId = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
    local itemLink = GetInventoryItemLink('player', slotId)
    local ok, itemStats = pcall(GetItemStats, itemLink)
    if itemLink and ok and type(itemStats) == 'table' then
      for key, value in pairs(itemStats) do
        if type(value) == 'number' and not key:find('^EMPTY_SOCKET') then
          gearTotals[key] = (gearTotals[key] or 0) + value
        end
      end
    end
  end

  local gearKeys = {}
  for key in pairs(gearTotals) do
    gearKeys[#gearKeys + 1] = key
  end
  table.sort(gearKeys)

  local gear = {}
  for _, key in ipairs(gearKeys) do
    -- Keys are global string names: ITEM_MOD_CRIT_RATING_SHORT -> crit_rating, RESISTANCE0_NAME -> armor
    local name = key == 'RESISTANCE0_NAME' and 'armor'
      or key:gsub('^ITEM_MOD_', ''):gsub('_SHORT$', ''):gsub('_NAME$', ''):lower()
    AddStat(gear, name, gearTotals[key])
  end

  lines[#lines + 1] = { 'character_stats_gear', gear }
end

-- base:posBuff:negBuff triples, as the APIs return them
local function AddAttackPower(lines, unit, prefix)
  local ap = {}

  for _, entry in ipairs({ { 'melee', 'UnitAttackPower' }, { 'ranged', 'UnitRangedAttackPower' } }) do
    local base, posBuff, negBuff = CallStatAPI(entry[2], unit)
    if type(base) == 'number' then
      ap[#ap + 1] = entry[1] .. ':' .. FormatStatValue(base) .. ':' .. FormatStatValue(posBuff or 0)
        .. ':' .. FormatStatValue(negBuff or 0)
    end
  end

  lines[#lines + 1] = { prefix .. 'attack_power', ap }
end

-- Per-school values from an API taking a school index 1..7 (or 0..6 for UnitResistance)
local function AddPerSchool(lines, key, apiName, firstSchool, unit)
  local values = {}

  for schoolIndex, schoolName in ipairs(SPELL_SCHOOL_NAMES) do
    if schoolIndex >= firstSchool then
      local value
      if unit then
        value = CallStatAPI(apiName, unit, schoolIndex - 1)
      else
        value = CallStatAPI(apiName, schoolIndex)
      end
      AddStat(values, schoolName, value)
    end
  end

  if #values > 0 then
    lines[#lines + 1] = { key, values }
  end
end

local function AddSpellStats(lines)
  AddPerSchool(lines, 'spell_power', 'GetSpellBonusDamage', 2)

  local healing = {}

  AddStat(healing, 'healing', (CallStatAPI('GetSpellBonusHealing')))
  AddStat(healing, 'penetration', (CallStatAPI('GetSpellPenetration')))

  lines[#lines + 1] = { 'spell_stats', healing }

  -- Regen APIs are player-only (no unit argument). Each returns an out-of-combat and a
  -- casting/in-combat value, emitted as name:base:casting
  local regen = {}
  local function AddRegenPair(name, apiName, ...)
    local base, casting = CallStatAPI(apiName, ...)
    if type(base) == 'number' then
      regen[#regen + 1] = name .. ':' .. FormatStatValue(base) .. ':' .. FormatStatValue(casting or 0)
    end
  end
  AddRegenPair('health', 'GetHealthRegen')
  AddRegenPair('health_from_spirit', 'GetHealthRegenFromSpirit')
  AddRegenPair('mana', 'GetManaRegen')
  AddRegenPair('mana_from_spirit', 'GetManaRegenFromSpirit')
  for _, power in ipairs(POWER_TYPES) do
    AddRegenPair(power[1] .. '_power', 'GetPowerRegenForPowerType', power[2])
  end

  lines[#lines + 1] = { 'regen', regen }
end

-- Crit, hit, haste, expertise: each component the sheet adds together, kept separate
local function AddCombatModifiers(lines)
  local crit = {}
  AddStat(crit, 'melee', (CallStatAPI('GetCritChance')))
  AddStat(crit, 'ranged', (CallStatAPI('GetRangedCritChance')))

  -- Forever takes no school argument; also try per school in case it does
  local spellCrit = CallStatAPI('GetSpellCritChance')
  AddStat(crit, 'spell', spellCrit)

  for schoolIndex = 2, #SPELL_SCHOOL_NAMES do
    local value = CallStatAPI('GetSpellCritChance', schoolIndex)
    if type(value) == 'number' and value ~= spellCrit then
      AddStat(crit, 'spell_' .. SPELL_SCHOOL_NAMES[schoolIndex], value)
    end
  end

  lines[#lines + 1] = { 'crit', crit }

  -- rating bonus (from gear) and modifier (talents/auras) are separate sources on the sheet
  local hit = {}
  for _, entry in ipairs({
    { 'melee',  CR_HIT_MELEE,  'GetHitModifier' },
    { 'ranged', CR_HIT_RANGED, 'GetRangedHitModifier' },
    { 'spell',  CR_HIT_SPELL,  'GetSpellHitModifier' },
  }) do
    AddStat(hit, entry[1] .. '_rating_bonus', entry[2] and CallStatAPI('GetCombatRatingBonus', entry[2]))
    AddStat(hit, entry[1] .. '_modifier', (CallStatAPI(entry[3])))
  end
  lines[#lines + 1] = { 'hit', hit }

  local haste = {}
  AddStat(haste, 'melee', (CallStatAPI('GetMeleeHaste')))

  local rangedHaste, ammoHaste = CallStatAPI('GetRangedHaste')
  AddStat(haste, 'ranged', rangedHaste)
  AddStat(haste, 'ranged_ammo', ammoHaste)
  AddStat(haste, 'spell', (CallStatAPI('UnitSpellHaste', 'player')))
  lines[#lines + 1] = { 'haste', haste }

  local misc = {}
  local expertise, offhandExpertise, rangedExpertise = CallStatAPI('GetExpertise')
  AddStat(misc, 'expertise', expertise)
  AddStat(misc, 'expertise_offhand', offhandExpertise)
  AddStat(misc, 'expertise_ranged', rangedExpertise)
  AddStat(misc, 'armor_penetration', (CallStatAPI('GetArmorPenetration')))
  AddStat(misc, 'mastery', (CallStatAPI('GetMasteryEffect')))

  lines[#lines + 1] = { 'combat_modifiers', misc }
end

-- Every CR_* combat rating with a nonzero rating or bonus, as name:rating:bonus
local function AddCombatRatings(lines)
  local names = {}

  for name, value in pairs(_G) do
    if type(value) == 'number' and type(name) == 'string' and name:find('^CR_') then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  local ratings = {}
  for _, name in ipairs(names) do
    local rating = CallStatAPI('GetCombatRating', _G[name])
    local bonus = CallStatAPI('GetCombatRatingBonus', _G[name])
    if (type(rating) == 'number' and rating ~= 0) or (type(bonus) == 'number' and bonus ~= 0) then
      ratings[#ratings + 1] = name:gsub('^CR_', ''):lower() .. ':' .. FormatStatValue(rating or 0)
        .. ':' .. FormatStatValue(bonus or 0)
    end
  end

  lines[#lines + 1] = { 'combat_ratings', ratings }
end

local function AddDefenseStats(lines, unit, prefix)
  local defense = {}

  -- Forever's UnitArmor returns (baselineArmor, effectiveArmor, armor, bonusArmor), not the
  -- modern pos/neg buff pair
  local baseArmor, effectiveArmor, armor, bonusArmor = CallStatAPI('UnitArmor', unit)
  AddStat(defense, 'armor_base', baseArmor)
  AddStat(defense, 'armor_effective', effectiveArmor)
  AddStat(defense, 'armor', armor)
  AddStat(defense, 'armor_bonus', bonusArmor)

  local defenseBase, defenseModifier = CallStatAPI('UnitDefenseSkill', unit)
  AddStat(defense, 'defense_skill', defenseBase)
  AddStat(defense, 'defense_modifier', defenseModifier)

  if unit == 'player' then
    AddStat(defense, 'dodge', (CallStatAPI('GetDodgeChance')))
    AddStat(defense, 'parry', (CallStatAPI('GetParryChance')))
    AddStat(defense, 'block', (CallStatAPI('GetBlockChance')))
    AddStat(defense, 'block_value', (CallStatAPI('GetShieldBlock')))
  end
  lines[#lines + 1] = { prefix .. 'defense', defense }

  -- UnitResistance returns base, real, effective, bonus; emit the effective value per school
  local resistances = {}
  for schoolIndex = 2, #SPELL_SCHOOL_NAMES do
    local _, _, effective = CallStatAPI('UnitResistance', unit, schoolIndex - 1)
    AddStat(resistances, SPELL_SCHOOL_NAMES[schoolIndex], effective)
  end

  lines[#lines + 1] = { prefix .. 'resistances', resistances }
end

local function AddWeaponDamage(lines, unit, prefix)
  local damage = {}

  local minDamage, maxDamage, offMin, offMax, posBuff, negBuff, percent = CallStatAPI('UnitDamage', unit)
  local mainSpeed, offSpeed, rangedSpeed = CallStatAPI('UnitAttackSpeed', unit)

  if type(minDamage) == 'number' then
    damage[#damage + 1] = table.concat({ 'mainhand', FormatStatValue(minDamage), FormatStatValue(maxDamage or 0),
      FormatStatValue(mainSpeed or 0) }, ':')
    if type(offSpeed) == 'number' then
      damage[#damage + 1] = table.concat({ 'offhand', FormatStatValue(offMin or 0), FormatStatValue(offMax or 0),
        FormatStatValue(offSpeed) }, ':')
    end
    AddStat(damage, 'pos_buff', posBuff)
    AddStat(damage, 'neg_buff', negBuff)
    AddStat(damage, 'percent', percent)
  end

  local rangedTime, rangedMin, rangedMax, rangedPos, rangedNeg, rangedPercent = CallStatAPI('UnitRangedDamage', unit)

  if unit == 'player' and type(rangedMin) == 'number' and (rangedMax or 0) > 0 then
    damage[#damage + 1] = table.concat({ 'ranged', FormatStatValue(rangedMin), FormatStatValue(rangedMax),
      FormatStatValue(rangedSpeed or rangedTime or 0) }, ':')
    AddStat(damage, 'ranged_pos_buff', rangedPos)
    AddStat(damage, 'ranged_neg_buff', rangedNeg)
    AddStat(damage, 'ranged_percent', rangedPercent)
  end

  lines[#lines + 1] = { prefix .. 'weapon_damage', damage }
end

-- Strings in stat lines: lowercased, non-alphanumerics collapsed to _, so / and : stay unambiguous
local function AddStatString(stats, name, value)
  if type(value) == 'string' and value ~= '' then
    stats[#stats + 1] = name .. ':' .. value:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
  end
end

-- What the active pet is. npc_id (from the GUID) is the stable identifier; the family,
-- type and loyalty strings are localized and only there for readability.
local function AddPetInfo(lines)
  local info = {}

  -- GUIDs look like Creature-0-[server]-[instance]-[zone]-[npcID]-[spawnUID]; pets are "Pet-..."
  local guid = CallStatAPI('UnitGUID', 'pet')
  if type(guid) == 'string' then
    local npcId = guid:match('^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-')
    AddStat(info, 'npc_id', tonumber(npcId))
  end
  AddStat(info, 'level', (CallStatAPI('UnitLevel', 'pet')))
  AddStatString(info, 'name', (CallStatAPI('UnitName', 'pet')))
  AddStatString(info, 'family', (CallStatAPI('UnitCreatureFamily', 'pet')))
  AddStatString(info, 'type', (CallStatAPI('UnitCreatureType', 'pet')))

  if C_PetInfo then
    AddStatString(info, 'talent_tree', C_PetInfo.GetPetTalentTree and (select(2, pcall(C_PetInfo.GetPetTalentTree))))
    AddStatString(info, 'loyalty', C_PetInfo.GetPetLoyalty and (select(2, pcall(C_PetInfo.GetPetLoyalty))))
    if C_PetInfo.GetPetHappiness then
      local ok, happiness, damagePercentage, loyaltyRate = pcall(C_PetInfo.GetPetHappiness)
      if ok then
        AddStat(info, 'happiness', happiness)
        AddStat(info, 'damage_percent', damagePercentage)
        AddStat(info, 'loyalty_rate', loyaltyRate)
      end
    end
    if C_PetInfo.GetPetTrainingPoints then
      local ok, totalPoints, usedPoints = pcall(C_PetInfo.GetPetTrainingPoints)
      if ok and type(totalPoints) == 'number' then
        info[#info + 1] = 'training_points:' .. FormatStatValue(totalPoints) .. ':' .. FormatStatValue(usedPoints or 0)
      end
    end
  end

  lines[#lines + 1] = { 'pet_info', info }
end

-- The pet versions of the modifier APIs take no unit argument
local function AddPetModifiers(lines)
  local modifiers = {}

  AddStat(modifiers, 'spell_power', (CallStatAPI('GetPetSpellBonusDamage')))
  AddStat(modifiers, 'haste_melee', (CallStatAPI('GetPetMeleeHaste')))
  AddStat(modifiers, 'hit_melee_modifier', (CallStatAPI('GetPetHitChanceModifier')))
  AddStat(modifiers, 'hit_spell_modifier', (CallStatAPI('GetPetSpellHitChanceModifier')))

  lines[#lines + 1] = { 'pet_modifiers', modifiers }
end

-- Returns an ordered list of { key, "name:value/name:value" } pairs for the export comments.
-- Any stat whose API is missing or errors is simply left out of its line.
function Simulationcraft:GetCharacterStats()
  local lines = {}

  AddPrimaryStats(lines, 'player', 'character_')
  AddGearStats(lines)
  AddAttackPower(lines, 'player', '')
  AddSpellStats(lines)
  AddCombatModifiers(lines)
  AddCombatRatings(lines)
  AddDefenseStats(lines, 'player', '')
  AddWeaponDamage(lines, 'player', '')

  -- Hunter/warlock style pets have a stats pane of their own; mirror it when one is out
  if HasPetUI and HasPetUI() and UnitExists('pet') then
    AddPetInfo(lines)
    AddPrimaryStats(lines, 'pet', 'pet_')
    AddAttackPower(lines, 'pet', 'pet_')
    AddPetModifiers(lines)
    AddDefenseStats(lines, 'pet', 'pet_')
    AddWeaponDamage(lines, 'pet', 'pet_')
  end

  for _, line in ipairs(lines) do
    line[2] = table.concat(line[2], '/')
  end

  return lines
end

-- Current skill levels (weapon skills, defense, professions, ...) from the skills pane.
-- Returns "skillID:rank:modifier:maxRank/..." sorted by skill ID, or nil if this client
-- has no skill list (retail). modifier is the temporary bonus from gear/auras/racials.
function Simulationcraft:GetSkillLevels()
  if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then
    return nil
  end

  local skills = {}
  for index = 1, C_SkillInfo.GetNumSkillLines() do
    local skillInfo = C_SkillInfo.GetSkillLineInfo(index)
    if skillInfo and not skillInfo.isHeader and skillInfo.skillID then
      skills[#skills + 1] = skillInfo
    end
  end
  table.sort(skills, function(a, b) return a.skillID < b.skillID end)

  local entries = {}
  for _, skillInfo in ipairs(skills) do
    entries[#entries + 1] = table.concat({
      skillInfo.skillID, skillInfo.rank or 0, skillInfo.modifier or 0, skillInfo.maxRank or 0
    }, ':')
  end
  return table.concat(entries, '/')
end

-- Returns "spellID:stacks/..." sorted by spell ID (stacks is 0 for buffs that don't stack),
-- or nil if the aura API is unavailable.
function Simulationcraft:GetActiveBuffs()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
    return nil
  end

  local buffs = {}
  local index = 1
  local aura = C_UnitAuras.GetAuraDataByIndex('player', index, 'HELPFUL')

  while aura do
    if aura.spellId then
      buffs[#buffs + 1] = aura
    end
    index = index + 1
    aura = C_UnitAuras.GetAuraDataByIndex('player', index, 'HELPFUL')
  end
  table.sort(buffs, function(a, b) return a.spellId < b.spellId end)

  local entries = {}
  for _, buff in ipairs(buffs) do
    entries[#entries + 1] = buff.spellId .. ':' .. (buff.applications or 0)
  end

  return table.concat(entries, '/')
end
