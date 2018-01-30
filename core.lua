local _, Simulationcraft = ...

Simulationcraft = LibStub("AceAddon-3.0"):NewAddon(Simulationcraft, "Simulationcraft", "AceConsole-3.0", "AceEvent-3.0")
ItemUpgradeInfo = LibStub("LibItemUpgradeInfo-1.0")
LibRealmInfo = LibStub("LibRealmInfo")

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
local OFFSET_GEM_ID_2 = 4
local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_GEM_BASE = OFFSET_GEM_ID_1
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
  Simulationcraft:RegisterChatCommand('simc', 'HandleChatCommand')
end

function Simulationcraft:OnEnable()
  SimulationcraftTooltip:SetOwner(_G["UIParent"],"ANCHOR_NONE")
end

function Simulationcraft:OnDisable()

end

function Simulationcraft:HandleChatCommand(input)
  local args = {strsplit(' ', input)}

  local debugOutput = false
  local noBags = false

  for _, arg in ipairs(args) do
    if arg == 'debug' then
      debugOutput = true
    elseif arg == 'nobag' or arg == 'nobags' or arg == 'nb' then
      noBags = true
    end
  end

  self:PrintSimcProfile(debugOutput, noBags)
end

local function GetItemSplit(itemLink)
  local itemString = string.match(itemLink, "item:([%-?%d:]+)")
  local itemSplit = {}

  -- Split data into a table
  for _, v in ipairs({strsplit(":", itemString)}) do
    if v == "" then
      itemSplit[#itemSplit + 1] = 0
    else
      itemSplit[#itemSplit + 1] = tonumber(v)
    end
  end

  return itemSplit
end

-- char size for utf8 strings
local function chsize(char)
  if not char then
      return 0
  elseif char > 240 then
      return 4
  elseif char > 225 then
      return 3
  elseif char > 192 then
      return 2
  else
      return 1
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
    local b = str:byte(i)
    -- keep digits 0-9
    if b >= 48 and b <= 57 then
      s = s .. str:sub(i,i)
      -- keep lowercase letters
    elseif b >= 97 and b <= 122 then
      s = s .. str:sub(i,i)
      -- keep %, +, ., _
    elseif b == 37 or b == 43 or b == 46 or b == 95 then
      s = s .. str:sub(i,i)
      -- save all multibyte chars
    elseif chsize(b) > 1 then
      local offset = chsize(b) - 1
      s = s .. str:sub(i, i + offset)
      i = i + offset
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

local function GetPowerData(powerId)
  if not powerId then
    return 0, 0
  end

  local powerInfo = ArtifactUI.GetPowerInfo(powerId)
  if powerInfo == nil then
    return powerId, 0
  end

  return powerId, powerInfo.currentRank - powerInfo.bonusRanks
end

function Simulationcraft:OpenArtifact()
  if not HasArtifactEquipped() then
    return false, false, 0
  end

  local artifactFrameOpen = IsArtifactFrameOpen()
  if not artifactFrameOpen then
    SocketInventoryItem(INVSLOT_MAINHAND)
  end

  local ArtifactFrame = _G.ArtifactFrame

  local itemId = select(1, ArtifactUI.GetArtifactInfo())
  if itemId == nil or itemId == 0 then
    if not artifactFrameOpen then
      HideUIPanel(ArtifactFrame)
    end
    return false, false, 0
  end

  -- if not select(1, IsUsableItem(itemId)) then
  --   if not artifactFrameOpen then
  --     HideUIPanel(ArtifactFrame)
  --   end
  --   return false, false, 0
  -- end

  local mhId = select(1, GetInventoryItemID("player", GetInventorySlotInfo("MainHandSlot")))
  local ohId = select(1, GetInventoryItemID("player", GetInventorySlotInfo("SecondaryHandSlot")))
  local correctArtifactOpen = (mhId ~= nil and mhId == itemId) or (ohId ~= nil and ohId == itemId)

  if not correctArtifactOpen then
    print("|cFFFF0000Warning, attempting to generate Simulationcraft artifact output for the wrong item (expected "
      .. (mhId or 0) .. " or " .. (ohId or 0) .. ", got " .. itemId .. ")")
    HideUIPanel(ArtifactFrame)
    SocketInventoryItem(INVSLOT_MAINHAND)
    itemId = select(1, ArtifactUI.GetArtifactInfo())
  end

  return artifactFrameOpen, correctArtifactOpen, itemId
end

function Simulationcraft:CloseArtifactFrame(wasOpen, correctOpen)
  local ArtifactFrame = _G.ArtifactFrame

  if ArtifactFrame and (not wasOpen or not correctOpen) then
    HideUIPanel(ArtifactFrame)
  end
end

function Simulationcraft:GetCrucibleString()
  local artifactFrameOpen, correctArtifactOpen, itemId = self:OpenArtifact()

  if not itemId then
    self:CloseArtifactFrame(artifactFrameOpen, correctArtifactOpen)
    return nil
  end

  local artifactId = artifactTable[itemId]
  if artifactId == nil then
    self:CloseArtifactFrame(artifactFrameOpen, correctArtifactOpen)
    return nil
  end

  local crucibleData = {}
  for ridx = 1, ArtifactUI.GetNumRelicSlots() do
    local link = select(4, ArtifactUI.GetRelicInfo(ridx))
    if link ~= nil then
      local relicSplit     = GetItemSplit(link)
      local baseLink       = select(2, GetItemInfo(relicSplit[1]))
      local basePowers     = { ArtifactUI.GetPowersAffectedByRelicItemLink(baseLink) }
      local relicPowers    = { ArtifactUI.GetPowersAffectedByRelic(ridx) }
      local cruciblePowers = {}

      for rpidx = 1, #relicPowers do
        local found = false
        for bpidx = 1, #basePowers do
          if relicPowers[rpidx] == basePowers[bpidx] then
            found = true
            break
          end
        end

        if not found then
          cruciblePowers[#cruciblePowers + 1] = relicPowers[rpidx]
        end
      end

      if #cruciblePowers == 0 then
        crucibleData[ridx] = { 0 }
      else
        crucibleData[ridx] = cruciblePowers
      end
    else
      crucibleData[ridx] = { 0 }
    end
  end

  local crucibleStrings = {}
  for ridx = 1, #crucibleData do
    crucibleStrings[ridx] = table.concat(crucibleData[ridx], ':')
  end

  self:CloseArtifactFrame(artifactFrameOpen, correctArtifactOpen)

  return 'crucible=' .. table.concat(crucibleStrings, '/')
end

function Simulationcraft:GetArtifactString()
  local artifactFrameOpen, correctArtifactOpen, itemId = self:OpenArtifact()

  if not itemId then
    self:CloseArtifactFrame(artifactFrameOpen, correctArtifactOpen)
    return nil
  end

  local artifactId = artifactTable[itemId]
  if artifactId == nil then
    self:CloseArtifactFrame(artifactFrameOpen, correctArtifactOpen)
    return nil
  end

  -- Note, relics are handled by the item string
  local str = 'artifact=' .. artifactId .. ':0:0:0:0'

  local baseRanks = {}
  local crucibleRanks = {}

  local powers = ArtifactUI.GetPowers()
  for i = 1, #powers do
    local powerId, powerRank = GetPowerData(powers[i])

    if powerRank > 0 then
      baseRanks[#baseRanks + 1] = powerId
      baseRanks[#baseRanks + 1] = powerRank
    end
  end

  if #baseRanks > 0 then
    str = str .. ':' .. table.concat(baseRanks, ':')
  end

  self:CloseArtifactFrame(artifactFrameOpen, correctArtifactOpen)

  return str
end

-- =================== Item Information =========================
local function GetGemItemID(itemLink, index)
  local _, gemLink = GetItemGem(itemLink, index)
  if gemLink ~= nil then
    local itemIdStr = string.match(gemLink, "item:(%d+)")
    if itemIdStr ~= nil then
      return tonumber(itemIdStr)
    end
  end

  return 0
end

local function GetItemStringFromItemLink(slotNum, itemLink, debugOutput)
  local itemSplit = GetItemSplit(itemLink)
  local simcItemOptions = {}
  local gems = {}

  -- Item id
  local itemId = itemSplit[OFFSET_ITEM_ID]
  simcItemOptions[#simcItemOptions + 1] = ',id=' .. itemId

  -- Enchant
  if itemSplit[OFFSET_ENCHANT_ID] > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'enchant_id=' .. itemSplit[OFFSET_ENCHANT_ID]
  end

  -- Gems
  for gemOffset = OFFSET_GEM_ID_1, OFFSET_GEM_ID_4 do
    local gemIndex = (gemOffset - OFFSET_GEM_BASE) + 1
    if itemSplit[gemOffset] > 0 then
      local gemId = GetGemItemID(itemLink, gemIndex)
      if gemId > 0 then
        gems[gemIndex] = gemId
      end
    else
      gems[gemIndex] = 0
    end
  end

  -- Remove any trailing zeros from the gems array
  while #gems > 0 and gems[#gems] == 0 do
    table.remove(gems, #gems)
  end

  if #gems > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'gem_id=' .. table.concat(gems, '/')
  end

  -- New style item suffix, old suffix style not supported
  if itemSplit[OFFSET_SUFFIX_ID] ~= 0 then
    simcItemOptions[#simcItemOptions + 1] = 'suffix=' .. itemSplit[OFFSET_SUFFIX_ID]
  end

  local flags = itemSplit[OFFSET_FLAGS]

  local bonuses = {}

  for index=1, itemSplit[OFFSET_BONUS_ID] do
    bonuses[#bonuses + 1] = itemSplit[OFFSET_BONUS_ID + index]
  end

  if #bonuses > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
  end

  local linkOffset = OFFSET_BONUS_ID + #bonuses + 1

  -- Upgrade level
  if bit.band(flags, 0x4) == 0x4 then
    local upgradeId = itemSplit[linkOffset]
    if upgradeTable and upgradeTable[upgradeId] ~= nil and upgradeTable[upgradeId] > 0 then
      simcItemOptions[#simcItemOptions + 1] = 'upgrade=' .. upgradeTable[upgradeId]
    end
    linkOffset = linkOffset + 1
  end

  -- Artifacts use this
  if bit.band(flags, 0x100) == 0x100 then
    linkOffset = linkOffset + 1 -- An unknown field
    -- 7.2 added a new field to the item string if additional trait ranks are attained
    -- for the artifact.
    if bit.band(flags, 0x1000000) == 0x1000000 then
      linkOffset = linkOffset + 1
    end

    -- Relic bonus ids, relic item ids handled by gems
    local relicStrs = {}
    local relicIndex = 1
    while linkOffset < #itemSplit do
      local nBonusIds = itemSplit[linkOffset]
      linkOffset = linkOffset + 1

      if nBonusIds == 0 then
        relicStrs[relicIndex] = "0"
      else
        local relicBonusIds = {}
        for rbid = 1, nBonusIds do
          relicBonusIds[#relicBonusIds + 1] = itemSplit[linkOffset]
          linkOffset = linkOffset + 1
        end

        relicStrs[relicIndex] = table.concat(relicBonusIds, ':')
      end

      relicIndex = relicIndex + 1
    end

    -- Remove any trailing zeros from the relic ids array
    while #relicStrs > 0 and relicStrs[#relicStrs] == "0" do
      table.remove(relicStrs, #relicStrs)
    end

    if #relicStrs > 0 then
      simcItemOptions[#simcItemOptions + 1] = 'relic_id=' .. table.concat(relicStrs, '/')
    end
  end

  -- Some leveling quest items seem to use this, it'll include the drop level of the item
  if bit.band(flags, 0x200) == 0x200 then
    simcItemOptions[#simcItemOptions + 1] = 'drop_level=' .. itemSplit[linkOffset]
    linkOffset = linkOffset + 1
  end

  local itemStr = ''
  if debugOutput then
    itemStr = itemStr .. '# ' .. itemString .. '\n'
  end
  itemStr = itemStr .. simcSlotNames[slotNum] .. "=" .. table.concat(simcItemOptions, ',')

  return itemStr
end

function Simulationcraft:GetItemStrings(debugOutput)
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      items[slotNum] = GetItemStringFromItemLink(slotNum, itemLink, debugOutput)
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
        if bags or bank then
          local container
          if bags then
            container = bag
          elseif bank then
            -- Default bank slots (the innate ones, not ones from bags-in-the-bank) are weird
            -- slot starts at 39, I believe that is based on some older location values
            -- GetContainerItemInfo uses a 0-based slot index
            -- So take the slot from the unpack and subtract 39 to get the right index for GetContainerItemInfo.
            -- 2018/01/17 - Change magic number to 47 to account for new backpack slots. Not sure why it went up by 8
            -- instead of 4, possible blizz is leaving the door open to more expansion in the future?
            container = BANK_CONTAINER
            slot = slot - 47
          end
          _, _, _, _, _, _, itemLink, _, _, itemId = GetContainerItemInfo(container, slot)
          if itemLink then
            local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)

            -- get correct level for scaling gear
            local level = ItemUpgradeInfo:GetUpgradedItemLevel(link) or 0

            -- find all equippable, non-artifact items
            if IsEquippableItem(itemLink) and quality ~= 6 then
              bagItems[#bagItems + 1] = {
                string = GetItemStringFromItemLink(slotNum, itemLink, false),
                name = name .. ' (' .. level .. ')'
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
function Simulationcraft:PrintSimcProfile(debugOutput, noBags)
  -- addon metadata
  local versionComment = '# SimC Addon ' .. GetAddOnMetadata('Simulationcraft', 'Version')

  -- Basic player info
  local _, realmName, _, _, _, _, region, _, _, realmLatinName, _ = LibRealmInfo:GetRealmInfoByUnit('player')

  local playerName = UnitName('player')
  local _, playerClass = UnitClass('player')
  local playerLevel = UnitLevel('player')

  -- Try Latin name for Russian servers first, then realm name from LibRealmInfo, then Realm Name from the game
  -- Latin name for Russian servers as most APIs use the latin name, not the cyrillic name
  local playerRealm = realmLatinName or realmName or GetRealmName()

  -- Try region from LibRealmInfo first, then use default API
  -- Default API can be wrong for region-switching players
  local playerRegion = region or regionString[GetCurrentRegion()]

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
  local playerCrucible = self:GetCrucibleString()

  -- Build the output string for the player (not including gear)
  local simulationcraftProfile = versionComment .. '\n'
  simulationcraftProfile = simulationcraftProfile .. '\n'
  simulationcraftProfile = simulationcraftProfile .. player .. '\n'
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
  if playerCrucible ~= nil then
    simulationcraftProfile = simulationcraftProfile .. playerCrucible .. '\n'
  end
  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- Method that gets gear information
  local items = Simulationcraft:GetItemStrings(debugOutput)

  -- output gear
  for slotNum=1, #slotNames do
    if items[slotNum] then
      simulationcraftProfile = simulationcraftProfile .. items[slotNum] .. '\n'
    end
  end

  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- output gear from bags
  if noBags == false then
    local bagItems = Simulationcraft:GetBagItemStrings()

    simulationcraftProfile = simulationcraftProfile .. '### Gear from Bags\n'
    simulationcraftProfile = simulationcraftProfile .. '#\n'
    for i=1, #bagItems do
      simulationcraftProfile = simulationcraftProfile .. '# ' .. bagItems[i].name .. '\n'
      simulationcraftProfile = simulationcraftProfile .. '# ' .. bagItems[i].string .. '\n'
      simulationcraftProfile = simulationcraftProfile .. '#\n'
    end
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
  SimcCopyFrameScrollText:SetScript("OnEscapePressed", function(self)
    SimcCopyFrame:Hide()
  end)
end
