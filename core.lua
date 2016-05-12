local _, Simulationcraft = ...

local wowVersion = select(4, GetBuildInfo())

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
local OFFSET_GEM_ID_2 = 4
local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_SUFFIX_ID = 7
local OFFSET_BONUS_ID = 13

-- Most of the guts of this addon were based on a variety of other ones, including
-- Statslog, AskMrRobot, and BonusScanner. And a bunch of hacking around with AceGUI.
-- Many thanks to the authors of those addons, and to reia for fixing my awful amateur
-- coding mistakes regarding objects and namespaces.

function Simulationcraft:OnInitialize()
  self.db = LibStub('AceDB-3.0'):New('SimulationcraftDB', self:CreateDefaults(), true)
  AceConfig = LibStub("AceConfigDialog-3.0")
  LibStub("AceConfig-3.0"):RegisterOptionsTable("Simulationcraft", self:CreateOptions())
  AceConfig:AddToBlizOptions("Simulationcraft", "Simulationcraft")
  Simulationcraft:RegisterChatCommand('simc', 'PrintSimcProfile')
end

function Simulationcraft:OnEnable()
  SimulationcraftTooltip:SetOwner(_G["UIParent"],"ANCHOR_NONE")
end

function Simulationcraft:OnDisable()

end

local L = LibStub("AceLocale-3.0"):GetLocale("Simulationcraft")

-- load stuff from extras.lua
local SimcStatAbbr  = Simulationcraft.SimcStatAbbr
local upgradeTable  = Simulationcraft.upgradeTable
local slotNames     = Simulationcraft.slotNames
local simcSlotNames = Simulationcraft.simcSlotNames
local enchantNames  = Simulationcraft.enchantNames
local specNames     = Simulationcraft.SpecNames
local profNames     = Simulationcraft.ProfNames
local regionString  = Simulationcraft.RegionString

-- error string
local simc_err_str = ''

-- debug flag
local SIMC_DEBUG = false

-- debug function
local function simcDebug( s )
  if SIMC_DEBUG then
    print('debug: '.. tostring(s) )
  end
end

-- SimC tokenize function
local function tokenize(str)
  str = str or ""
  -- convert to lowercase and remove spaces
  str = string.lower(str)
  str = string.gsub(str, ' ', '_')

  -- keep stuff we want, dumpster everything else
  local s = ""
  for i=1,str:len() do
    -- keep digits 0-9
    if str:byte(i) >= 48 and str:byte(i) <= 57 then
      s = s .. str:sub(i,i)
      -- keep lowercase letters
    elseif str:byte(i) >= 97 and str:byte(i) <= 122 then
      s = s .. str:sub(i,i)
      -- keep %, +, ., _
    elseif str:byte(i)==37 or str:byte(i)==43 or str:byte(i)==46 or str:byte(i)==95 then
      s = s .. str:sub(i,i)
    end
  end
  -- strip trailing spaces
  if string.sub(s, s:len())=='_' then
    s = string.sub(s, 0, s:len()-1)
  end
  return s
end

-- method for constructing the talent string
local function CreateSimcTalentString()
  local talentInfo = {}
  local maxTiers = 7
  local maxColumns = 3
  for tier = 1, maxTiers do
    for column = 1, maxColumns do
      local talentID, name, iconTexture, selected, available = GetTalentInfo(tier, column, GetActiveSpecGroup())
      if selected then
    talentInfo[tier] = column
      end
    end
  end

  local str = 'talents='
  for i = 1, maxTiers do
    if talentInfo[i] then
      str = str .. talentInfo[i]
    else
      str = str .. '0'
    end
  end

  return str
end

-- function that translates between the game's role values and ours
local function translateRole(str)
  if str == 'TANK' then
    return tokenize(str)
  elseif str == 'DAMAGER' then
    return 'attack'
  elseif str == 'HEALER' then
    return 'healer'
  else
    return ''
  end

end


-- =================== Item Information =========================

function Simulationcraft:GetItemStrings()
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      local itemString = string.match(itemLink, "item:([%-?%d:]+)")
      local itemSplit = {}
      local simcItemOptions = {}


      -- Split data into a table
      for v in string.gmatch(itemString, "(%d*:)") do
        if v == ":" then
          itemSplit[#itemSplit + 1] = 0
        else
          itemSplit[#itemSplit + 1] = string.sub(v, 1, -2)
        end
      end

      -- Item tokenized name
      local itemId = itemSplit[OFFSET_ITEM_ID]
      simcItemOptions[#simcItemOptions + 1] = ',id=' .. itemId

      -- New style item suffix, old suffix style not supported
      if tonumber(itemSplit[OFFSET_SUFFIX_ID]) ~= 0 then
        simcItemOptions[#simcItemOptions + 1] = 'suffix=' .. itemSplit[OFFSET_SUFFIX_ID]
      end

      -- Item bonuses (WoD only)
      local hasBonus = itemSplit[OFFSET_BONUS_ID]
      local bonuses = {}
      if tonumber(hasBonus) > 0 then
        for index=OFFSET_BONUS_ID + 1, OFFSET_BONUS_ID + tonumber(hasBonus) do
          bonuses[#bonuses + 1] = itemSplit[index]
        end
        if #bonuses > 0 then
          simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
        end
      end

	  -- Item upgrade level
      local upgradeId = itemSplit[#itemSplit]
      local upgradeLevel = upgradeTable[tonumber(upgradeId)]
      if upgradeLevel == nil then
        upgradeLevel = 0
        --simc_err_str = simc_err_str .. '\n # WARNING: upgradeLevel nil for upgradeId ' .. upgradeId .. ' in itemString ' .. itemString
      end
      if tonumber(upgradeLevel) > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'upgrade=' .. upgradeLevel
      end

      -- Gems
      local gems = {}
      for i=1, 3 do -- hardcoded here to just grab all 3 sockets
        local _,gemLink = GetItemGem(itemLink, i)
        if gemLink then
          local gemDetail = string.match(gemLink, "item[%-?%d:]+")
          gems[#gems + 1] = string.match(gemDetail, "item:(%d+):" )
        end
      end
      --simcDebug(#gems)
      if #gems > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'gem_id=' .. table.concat(gems, '/')
      end

      -- Enchant
      if tonumber(itemSplit[OFFSET_ENCHANT_ID]) > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'enchant_id=' .. itemSplit[OFFSET_ENCHANT_ID]
      end

      items[slotNum] = simcSlotNames[slotNum] .. "=" .. table.concat(simcItemOptions, ',')
    end
  end

  return items
end

-- This is the workhorse function that constructs the profile
function Simulationcraft:PrintSimcProfile()

  -- Basic player info
  local playerName = UnitName('player')
  local _, playerClass = UnitClass('player')
  local playerLevel = UnitLevel('player')
  local playerRealm = GetRealmName()
  local playerRegion = regionString[GetCurrentRegion()]

  -- Race info
  local _, playerRace = UnitRace('player')
  -- fix some races to match SimC format
  if playerRace == 'BloodElf' then
    playerRace = 'Blood Elf'
  elseif playerRace == 'NightElf' then
    playerRace = 'Night Elf'
  elseif playerRace == 'Scourge' then --lulz
    playerRace = 'Undead'
  end

  -- Spec info
  local role, globalSpecID
  local specId = GetSpecialization()
  if specId then
    globalSpecID,_,_,_,_,role = GetSpecializationInfo(specId)
  end
  local playerSpec = specNames[ globalSpecID ]

  -- Professions
  local pid1, pid2 = GetProfessions()
  local firstProf, firstProfRank, secondProf, secondProfRank, profOneId, profTwoId
  if pid1 then
    _,_,firstProfRank,_,_,_,profOneId = GetProfessionInfo(pid1)
  end
  if pid2 then
    secondProf,_,secondProfRank,_,_,_,profTwoId = GetProfessionInfo(pid2)
  end

  firstProf = profNames[ profOneId ]
  secondProf = profNames[ profTwoId ]

  local playerProfessions = ''
  if pid1 or pid2 then
    playerProfessions = 'professions='
    if pid1 then
      playerProfessions = playerProfessions..tokenize(firstProf)..'='..tostring(firstProfRank)..'/'
    end
    if pid2 then
      playerProfessions = playerProfessions..tokenize(secondProf)..'='..tostring(secondProfRank)
    end
  else
    playerProfessions = ''
  end

  -- Construct SimC-compatible strings from the basic information
  local player = tokenize(playerClass) .. '="' .. playerName .. '"'
  playerLevel = 'level=' .. playerLevel
  playerRace = 'race=' .. tokenize(playerRace)
  playerRole = 'role=' .. translateRole(role)
  playerSpec = 'spec=' .. tokenize(playerSpec)
  playerRealm = 'server=' .. tokenize(playerRealm)
  playerRegion = 'region=' .. tokenize(playerRegion)

  -- Talents are more involved - method to handle them
  local playerTalents = CreateSimcTalentString()

  -- Build the output string for the player (not including gear)
  local simulationcraftProfile = player .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerLevel .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRace .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRegion .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRealm .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRole .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerProfessions .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerTalents .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerSpec .. '\n\n'

  -- Method that gets gear information
  local items = Simulationcraft:GetItemStrings()

  -- output gear
  for slotNum=1, #slotNames do
    if items[slotNum] then
      simulationcraftProfile = simulationcraftProfile .. items[slotNum] .. '\n'
    end
  end

  -- sanity checks - if there's anything that makes the output completely invalid, punt!
  if specId==nil then
    simulationcraftProfile = "Error: You need to pick a spec!"
  end

  -- append any error info
  if simc_err_str ~= '' then
      simulationcraftProfile = simulationcraftProfile .. '\n\n' ..simc_err_str
  end

  -- show the appropriate frames
  SimcCopyFrame:Show()
  SimcCopyFrameScroll:Show()
  SimcCopyFrameScrollText:Show()
  SimcCopyFrameScrollText:SetText(simulationcraftProfile)
  SimcCopyFrameScrollText:HighlightText()

end
