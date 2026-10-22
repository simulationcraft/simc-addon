-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, Simulationcraft = ...   -- same shared addon table as core.lua / extras.lua

-- Creature ID from the pet GUID: Pet-0-server-instance-zone-creatureID-spawn
local function GetPetCreatureID()
  return tonumber(UnitGUID('pet'):match('^Pet%-%d+%-%d+%-%d+%-%d+%-(%d+)%-'))
end

-- Spell IDs from the pet spellbook. Attack/Follow/Stay are pet actions without a spellID
local function GetPetAbilities()
  local abilities = {}
  for i = 1, C_SpellBook.HasPetSpells() or 0 do
    local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet)
    if info and info.spellID then
      abilities[#abilities + 1] = info.spellID
    end
  end
  table.sort(abilities)
  return abilities
end

-- Returns a list of profile lines for a hunter's active pet, or nil if there isn't one
function Simulationcraft:GetPetExport()
  local _, playerClass = UnitClass('player')
  if playerClass ~= 'HUNTER' or not UnitExists('pet') then return nil end

  local lines = {}
  local family = UnitCreatureFamily('pet')
  local level = UnitLevel('pet')

  lines[#lines + 1] = '# ' .. UnitName('pet') .. ' - ' .. (family or '?') .. ' (' .. level .. ')'
  if family then
    lines[#lines + 1] = 'pet_family=' .. Simulationcraft.Tokenize(family)
  end
  local creatureID = GetPetCreatureID()
  if creatureID then
    lines[#lines + 1] = 'pet_creature_id=' .. creatureID
  end
  lines[#lines + 1] = 'pet_level=' .. level

  local happiness = C_PetInfo.GetPetHappiness()
  if happiness then
    lines[#lines + 1] = 'pet_happiness=' .. happiness
  end

  local abilities = GetPetAbilities()
  if #abilities > 0 then
    lines[#lines + 1] = 'pet_abilities=' .. table.concat(abilities, '/')
  end

  local total, used = C_PetInfo.GetPetTrainingPoints()
  if total then
    lines[#lines + 1] = '# pet_training_points=' .. (used or 0) .. '/' .. total
  end

  return lines
end
