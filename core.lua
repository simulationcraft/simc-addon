local _, Simulationcraft = ...

Simulationcraft = LibStub("AceAddon-3.0"):NewAddon(Simulationcraft, "Simulationcraft", "AceConsole-3.0", "AceEvent-3.0")

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
local OFFSET_GEM_ID_2 = 4
local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_SUFFIX_ID = 7
local OFFSET_FLAGS = 11
local OFFSET_BONUS_ID = 13
local OFFSET_UPGRADE_ID = 14 -- Flags = 0x4

-- Artifact stuff (adapted from LibArtifactData [https://www.wowace.com/addons/libartifactdata-1-0/], thanks!)
local ArtifactUI          = _G.C_ArtifactUI
local HasArtifactEquipped = _G.HasArtifactEquipped
local SocketInventoryItem = _G.SocketInventoryItem
local Timer               = _G.C_Timer

-- load stuff from extras.lua
local upgradeTable  = Simulationcraft.upgradeTable
local slotNames     = Simulationcraft.slotNames
local simcSlotNames = Simulationcraft.simcSlotNames
local specNames     = Simulationcraft.SpecNames
local profNames     = Simulationcraft.ProfNames
local regionString  = Simulationcraft.RegionString
local artifactTable = Simulationcraft.ArtifactTable

-- Most of the guts of this addon were based on a variety of other ones, including
-- Statslog, AskMrRobot, and BonusScanner. And a bunch of hacking around with AceGUI.
-- Many thanks to the authors of those addons, and to reia for fixing my awful amateur
-- coding mistakes regarding objects and namespaces.

function Simulationcraft:OnInitialize()
  Simulationcraft:RegisterChatCommand('simc', 'PrintSimcProfile')
end

function Simulationcraft:OnEnable()
  SimulationcraftTooltip:SetOwner(_G["UIParent"],"ANCHOR_NONE")
end

function Simulationcraft:OnDisable()

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
local function translateRole(spec_id, str)
  local spec_role = Simulationcraft.RoleTable[spec_id]
  if spec_role ~= nil then
    return spec_role
  end

  if str == 'TANK' then
    return 'tank'
  elseif str == 'DAMAGER' then
    return 'attack'
  elseif str == 'HEALER' then
    return 'heal'
  else
    return ''
  end
end

-- ================= Artifact Information =======================

local function IsArtifactFrameOpen()
  local ArtifactFrame = _G.ArtifactFrame
  return ArtifactFrame and ArtifactFrame:IsShown() or false
end

function Simulationcraft:GetArtifactString()
  if not HasArtifactEquipped() then
    return nil
  end

  local artifactFrameOpen = IsArtifactFrameOpen()
  if not artifactFrameOpen then
    SocketInventoryItem(INVSLOT_MAINHAND)
  end

  local item_id = select(1, ArtifactUI.GetArtifactInfo())
  if item_id == nil or item_id == 0 then
    return nil
  end

  local artifact_id = artifactTable[item_id]
  if artifact_id == nil then
    return nil
  end

  -- Note, relics are handled by the item string
  local str = 'artifact=' .. artifact_id .. ':0:0:0:0'

  local powers = ArtifactUI.GetPowers()
  for i = 1, #powers do
    local power_id = powers[i]
    local power_info = ArtifactUI.GetPowerInfo(power_id)
    if power_info ~= nil and power_info.currentRank > 0 and power_info.currentRank - power_info.bonusRanks > 0 then
      str = str .. ':' .. power_id .. ':' .. (power_info.currentRank - power_info.bonusRanks)
    end
  end

  if not artifactFrameOpen then
    HideUIPanel(ArtifactFrame)
  end

  return str
end

-- =================== Item Information =========================

local function GetItemStringFromItemLink(slotNum, itemLink)
  local itemString = string.match(itemLink, "item:([%-?%d:]+)")
  local itemSplit = {}
  local simcItemOptions = {}

  -- Split data into a table
  for v in string.gmatch(itemString, "(%d*:?)") do
    if v == ":" then
      itemSplit[#itemSplit + 1] = 0
    else
      itemSplit[#itemSplit + 1] = string.gsub(v, ':', '')
    end
  end

  -- Item id
  local itemId = itemSplit[OFFSET_ITEM_ID]
  simcItemOptions[#simcItemOptions + 1] = ',id=' .. itemId

  -- Enchant
  if tonumber(itemSplit[OFFSET_ENCHANT_ID]) > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'enchant_id=' .. itemSplit[OFFSET_ENCHANT_ID]
  end

  -- New style item suffix, old suffix style not supported
  if tonumber(itemSplit[OFFSET_SUFFIX_ID]) ~= 0 then
    simcItemOptions[#simcItemOptions + 1] = 'suffix=' .. itemSplit[OFFSET_SUFFIX_ID]
  end

  local flags = tonumber(itemSplit[OFFSET_FLAGS])

  local bonuses = {}

  for index=1, tonumber(itemSplit[OFFSET_BONUS_ID]) do
    bonuses[#bonuses + 1] = itemSplit[OFFSET_BONUS_ID + index]
  end

  if #bonuses > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
  end

  local rest_offset = OFFSET_BONUS_ID + #bonuses + 1

  -- Upgrade level
  if bit.band(flags, 0x4) == 0x4 then
    local upgrade_id = tonumber(itemSplit[rest_offset])
    if upgradeTable and upgradeTable[upgrade_id] ~= nil and upgradeTable[upgrade_id] > 0 then
      simcItemOptions[#simcItemOptions + 1] = 'upgrade=' .. upgradeTable[upgrade_id]
    end
    rest_offset = rest_offset + 1
  end

  -- Artifacts use this
  if bit.band(flags, 0x100) == 0x100 then
    rest_offset = rest_offset + 1 -- An unknown field
    -- 7.2 added a new field to the item string if additional trait ranks are attained
    -- for the artifact.
    if bit.band(flags, 0x1000000) == 0x1000000 then
      rest_offset = rest_offset + 1
    end
    local relic_str = ''
    while rest_offset < #itemSplit do
      local n_bonus_ids = tonumber(itemSplit[rest_offset])
      rest_offset = rest_offset + 1

      if n_bonus_ids == 0 then
        relic_str = relic_str .. 0
      else
        for rbid = 1, n_bonus_ids do
          relic_str = relic_str .. itemSplit[rest_offset]
          if rbid < n_bonus_ids then
            relic_str = relic_str .. ':'
          end
          rest_offset = rest_offset + 1
        end
      end

      if rest_offset < #itemSplit then
        relic_str = relic_str .. '/'
      end
    end

    if relic_str ~= '' then
      simcItemOptions[#simcItemOptions + 1] = 'relic_id=' .. relic_str
    end
  end

  -- Some leveling quest items seem to use this, it'll include the drop level of the item
  if bit.band(flags, 0x200) == 0x200 then
    simcItemOptions[#simcItemOptions + 1] = 'drop_level=' .. itemSplit[rest_offset]
    rest_offset = rest_offset + 1
  end

  -- Gems
  local gems = {}
  for i=1, 4 do -- hardcoded here to just grab all 4 sockets
    local _,gemLink = GetItemGem(itemLink, i)
    if gemLink then
      local gemDetail = string.match(gemLink, "item[%-?%d:]+")
      gems[#gems + 1] = string.match(gemDetail, "item:(%d+):" )
    elseif bit.band(flags, 0x100) == 0x100 then
      gems[#gems + 1] = "0"
    end
  end
  if #gems > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'gem_id=' .. table.concat(gems, '/')
  end
  return simcSlotNames[slotNum] .. "=" .. table.concat(simcItemOptions, ',')
end

function Simulationcraft:GetItemStrings()
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      items[slotNum] = GetItemStringFromItemLink(slotNum, itemLink)
    end
  end

  return items
end

function Simulationcraft:GetBagItemStrings()
  local bagItems = {}

  for slotNum=1, #slotNames do
    local slotName = slotNames[slotNum]
    -- Ignore "double" slots, results in doubled output which isn't useful
    if slotName and slotName ~= 'Trinket1Slot' and slotName ~= 'Finger1Slot' then
      local slotItems = {}
      local slotId, _, _ = GetInventorySlotInfo(slotNames[slotNum])
      GetInventoryItemsForSlot(slotId, slotItems)
      for locationBitstring, itemID in pairs(slotItems) do
        local player, bank, bags, voidstorage, slot, bag = EquipmentManager_UnpackLocation(locationBitstring)
        if bags then
          _, _, _, _, _, _, itemLink, _, _, itemId = GetContainerItemInfo(bag, slot)
          if itemLink then
            local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)
            -- find all equippable, non-artifact items
            if IsEquippableItem(itemLink) and quality ~= 6 then
              bagItems[#bagItems + 1] = {
                string = GetItemStringFromItemLink(slotNum, itemLink),
                name = name .. ' (' .. iLevel .. ')'
              }
            end
          end
        end
      end
    end
  end

  return bagItems
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
  playerRole = 'role=' .. translateRole(globalSpecID, role)
  playerSpec = 'spec=' .. tokenize(playerSpec)
  playerRealm = 'server=' .. tokenize(playerRealm)
  playerRegion = 'region=' .. tokenize(playerRegion)

  -- Talents are more involved - method to handle them
  local playerTalents = CreateSimcTalentString()
  local playerArtifact = self:GetArtifactString()

  -- Build the output string for the player (not including gear)
  local simulationcraftProfile = player .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerLevel .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRace .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRegion .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRealm .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRole .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerProfessions .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerTalents .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerSpec .. '\n'
  if playerArtifact ~= nil then
    simulationcraftProfile = simulationcraftProfile .. playerArtifact .. '\n'
  end
  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- Method that gets gear information
  local items = Simulationcraft:GetItemStrings()

  -- output gear
  for slotNum=1, #slotNames do
    if items[slotNum] then
      simulationcraftProfile = simulationcraftProfile .. items[slotNum] .. '\n'
    end
  end

  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- output gear from bags
  local bagItems = Simulationcraft:GetBagItemStrings()

  simulationcraftProfile = simulationcraftProfile .. '### Gear from Bags\n'
  simulationcraftProfile = simulationcraftProfile .. '#\n'
  for i=1, #bagItems do
    simulationcraftProfile = simulationcraftProfile .. '# ' .. bagItems[i].name .. '\n'
    simulationcraftProfile = simulationcraftProfile .. '# ' .. bagItems[i].string .. '\n'
    simulationcraftProfile = simulationcraftProfile .. '#\n'
  end

  -- sanity checks - if there's anything that makes the output completely invalid, punt!
  if specId==nil then
    simulationcraftProfile = "Error: You need to pick a spec!"
  end

  -- show the appropriate frames
  SimcCopyFrame:Show()
  SimcCopyFrameScroll:Show()
  SimcCopyFrameScrollText:Show()
  SimcCopyFrameScrollText:SetText(simulationcraftProfile)
  SimcCopyFrameScrollText:HighlightText()
end
