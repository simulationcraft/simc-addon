local _, Simulationcraft = ...

local wowVersion = select(4, GetBuildInfo())

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
local OFFSET_GEM_ID_2 = 4
local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_SUFFIX_ID = 7
local OFFSET_UPGRADE_ID = wowVersion >= 60000 and 10 or 11
local OFFSET_HAS_BONUS = wowVersion >= 60000 and 12 or -1


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

-- method for removing glyph prefixes
local function StripGlyphPrefixes(name)
  local s = tokenize(name)

  s = string.gsub( s, 'glyph__', '')
  s = string.gsub( s, 'glyph_of_the_', '')
  s = string.gsub( s, 'glyph_of_','')

  return s
end

-- constructs glyph string from game's glyph info
local function CreateSimcGlyphString()
  local glyphs = {}
  for i=1, NUM_GLYPH_SLOTS do
    local _,_,_,spellid = GetGlyphSocketInfo(i, nil)
    if (spellid) then
      name = GetSpellInfo(spellid)
      glyphs[#glyphs + 1] = StripGlyphPrefixes(name)
    end            
  end
  return 'glyphs=' .. table.concat(glyphs, '/')
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

-- =================== Item stuff (old style ) ========================= 
-- The following functions are used to grab item info from tooltips to support "old-style" character definitions

-- This function converts text-based stat info (from tooltips) into SimC-compatible strings
local function ConvertToStatString( s )
    s = s or ''
    -- grab the value and stat from the string
    local value,stat = string.match(s, "(%d+)%s(%a+%s?%a*)")
    -- convert stat into simc abbreviation
    local statAbbr = SimcStatAbbr[tokenize(stat)]   
    -- return abbreviated combination or nil
    if statAbbr and value then
        return value..statAbbr
    else
        return ''
    end
end

local function ConvertTooltipToStatStr( s )

    local s1=s
    local s2=''
    if s:len()>0 then
        -- check for a split bonus
        if string.find(s, " and ++") then
            s1, s2 = string.match(s, "(%d+%s%a+%s?%a*) and ++?(%d+%s%a+%s?%a*)")
        end
    end

    s1=ConvertToStatString(s1)
    s2=ConvertToStatString(s2)
    
    if s2:len()>0 then
        return  s1 .. '_' .. s2
    else
        return s1
    end
end

-- This scans the tooltip to get gem stats
local function GetGemBonus(link)
    SimulationcraftTooltip:ClearLines()
    SimulationcraftTooltip:SetHyperlink(link)
    local numLines = SimulationcraftTooltip:NumLines()
    --simcDebug(numLines)
    local bonusStr=''
    for i=2, numLines, 1 do
        tmpText = _G["SimulationcraftTooltipTextLeft"..i]
        if (tmpText:GetText()) then
            line = tmpText:GetText()
            --print(line)
            if ( string.sub(line, 0, 1) == '+') then
                bonusStr=line
                --print('nabbed line: '..bonusStr)
                break
            end
        end
    end
        
    local gemBonusStr = ''
    -- Extract Gem bonus from string
    local enchantBonusStr = ''
    if bonusStr:len()>0 then
        gemBonusStr = ConvertTooltipToStatStr( bonusStr )
    end
    return gemBonusStr
end

-- This scans the tooltip and picks out a socket bonus, if one exists
local function GetSocketBonus(link)
    SimulationcraftTooltip:ClearLines()
    SimulationcraftTooltip:SetHyperlink(link)
    local numLines = SimulationcraftTooltip:NumLines()
    --Check each line of the tooltip until we find a bonus string
    local bonusStr=''
    for i=2, numLines, 1 do
        tmpText = _G["SimulationcraftTooltipTextLeft"..i]
        if (tmpText:GetText()) then
            line = tmpText:GetText()
            if ( string.sub(line, 0, string.len(L["SocketBonusPrefix"])) == L["SocketBonusPrefix"]) then
                bonusStr=string.sub(line,string.len(L["SocketBonusPrefix"])+1)
            end
        end
    end
    
    -- Extract Socket bonus from string
    local socketBonusStr = ''
    if bonusStr:len()>0 then
        socketBonusStr = ConvertToStatString( bonusStr )
    end
    return socketBonusStr
end

-- determine the number of sockets in an item
local function GetNumSockets(itemLink)
  local statTable = GetItemStats(itemLink)
  local numSockets = 0
  for stat, value in pairs(statTable) do
    if string.match(stat, 'SOCKET') then
      numSockets = numSockets + value
    end                
  end
  return numSockets
end

-- method that grabs gems and constructs old-style gem strings
local function GetOldStyleGems(itemLink, slotId)
  local gems={}
  for i=1, 3 do -- hardcoded here to just grab all 3 sockets
    local _,gemLink = GetItemGem(itemLink, i)
    if gemLink then
      local gemBonus = GetGemBonus(gemLink)
      if gemBonus:len() > 0 then
        gems[#gems + 1] = gemBonus
      end
    end
  end
  
  local numSockets = GetNumSockets(itemLink)
  SocketInventoryItem(slotId)
  local useBonus=true
  for i=1, numSockets do
    local _,_,matches = GetExistingSocketInfo(i)
    if not matches then
      useBonus=false
    end
  end
  CloseSocketInfo()
  if #gems > 0 and useBonus then
    gems[#gems + 1] = GetSocketBonus(itemLink)
  end
  return gems
end

-- method to construct old-style enchant strings
local function GetEnchantBonus(link)
  SimulationcraftTooltip:ClearLines()
  SimulationcraftTooltip:SetHyperlink(link)
  local numLines = SimulationcraftTooltip:NumLines()
  --Check each line of the tooltip until we find a bonus string
  local bonusStr=''
  for i=2, numLines, 1 do
    tmpText = _G["SimulationcraftTooltipTextLeft"..i]
    if (tmpText:GetText()) then
      line = tmpText:GetText()
      if ( string.sub(line, 0, string.len(L["EnchantBonusPrefix"])) == L["EnchantBonusPrefix"]) then
        bonusStr=string.sub(line,string.len(L["EnchantBonusPrefix"])+1)
      end
    end
  end

  -- Extract Enchant bonus from string
  local enchantBonusStr = ''
  if bonusStr:len()>0 then
    enchantBonusStr = ConvertTooltipToStatStr( bonusStr )
  end

  return enchantBonusStr
end

-- =================== Item Information ========================= 

function Simulationcraft:GetItemStrings()
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      local itemString = string.match(itemLink, "item[%-?%d:]+")
      local itemSplit = {}
      local simcItemOptions = {}

      -- Split data into a table
      for v in string.gmatch(itemString, "(%d+):?") do
        itemSplit[#itemSplit + 1] = v
      end

      -- Item tokenized name
      local itemId = itemSplit[OFFSET_ITEM_ID]
      simcItemOptions[#simcItemOptions + 1] = tokenize(GetItemInfo(itemId))
      simcItemOptions[#simcItemOptions + 1] = 'id=' .. itemId

      -- Item upgrade level
      local upgradeId = itemSplit[OFFSET_UPGRADE_ID]
      local upgradeLevel = upgradeTable[tonumber(upgradeId)]
      if upgradeLevel == nil then
        upgradeLevel = 0
        simc_err_str = simc_err_str + '\n # WARNING: upgradeLevel nil for upgradeId ' .. upgradeId .. ' in itemString ' .. itemString
      end
      if tonumber(upgradeLevel) > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'upgrade=' .. upgradeLevel
      end

      -- New style item suffix, old suffix style not supported
      if tonumber(itemSplit[OFFSET_SUFFIX_ID]) ~= 0 then
        simcItemOptions[#simcItemOptions + 1] = 'suffix=' .. itemSplit[OFFSET_SUFFIX_ID]
      end

      -- Item bonuses (WoD only)
      if wowVersion >= 60000 then
        local hasBonus = itemSplit[OFFSET_HAS_BONUS]
        local bonuses = {}
        if tonumber(hasBonus) > 0 then
          for index=OFFSET_HAS_BONUS + 1, #itemSplit do
            bonuses[#bonuses + 1] = itemSplit[index]
          end
          if #bonuses > 0 then
            simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
          end
        end
      end

      -- Gems
      local gems = {}
      if self.db.profile.newStyle then
        for i=1, 3 do -- hardcoded here to just grab all 3 sockets
          local _,gemLink = GetItemGem(itemLink, i)
          if gemLink then
            local gemDetail = string.match(gemLink, "item[%-?%d:]+")
            gems[#gems + 1] = string.match(gemDetail, "item:(%d+):" )
          end
        end
      else 
        gems = GetOldStyleGems(itemLink, slotId)
      end
      --simcDebug(#gems)
      if #gems > 0 then
        if self.db.profile.newStyle then
          simcItemOptions[#simcItemOptions + 1] = 'gem_id=' .. table.concat(gems, '/')
        else
          simcItemOptions[#simcItemOptions + 1] = 'gems=' .. table.concat(gems,'_')
        end
      end

      -- Enchant
      if tonumber(itemSplit[OFFSET_ENCHANT_ID]) > 0 then
        if self.db.profile.newStyle then
          simcItemOptions[#simcItemOptions + 1] = 'enchant_id=' .. itemSplit[OFFSET_ENCHANT_ID]
        else
          local enchantBonus
          --simcDebug(tonumber(itemSplit[OFFSET_ENCHANT_ID]))
          if enchantNames[tonumber(itemSplit[OFFSET_ENCHANT_ID])] then
            enchantBonus = tokenize(enchantNames[tonumber(itemSplit[OFFSET_ENCHANT_ID])])
          else
            enchantBonus = GetEnchantBonus(itemLink)
          end
          --simcDebug('ELEN' .. enchantBonus:len())
          if enchantBonus:len() > 0 then
            simcItemOptions[#simcItemOptions + 1] = 'enchant=' .. enchantBonus
          end
        end
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
  local playerSpec, role
  local specId = GetSpecialization()    
  if specId then
    _, playerSpec,_,_,_,role = GetSpecializationInfo(specId)
  end

  -- Professions
  local p1, p2 = GetProfessions()
  local playerProfessionOne, playerProfessionOneRank, playerProfessionTwo, playerProfessionTwoRank
  if p1 then
    playerProfessionOne,_,playerProfessionOneRank = GetProfessionInfo(p1)
  end
  if p2 then
    playerProfessionTwo,_,playerProfessionTwoRank = GetProfessionInfo(p2)
  end
  local realm = GetRealmName() -- not used yet (possibly for origin)
  
  local playerProfessions = ''
  if p1 or p2 then
    playerProfessions = 'professions='
    if p1 then
      playerProfessions = playerProfessions..tokenize(playerProfessionOne)..'='..tostring(playerProfessionOneRank)..'/'
    end
    if p2 then
      playerProfessions = playerProfessions..tokenize(playerProfessionTwo)..'='..tostring(playerProfessionTwoRank)
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
  
  -- Talents and Glyphs more involved - methods to handle them
  local playerTalents = CreateSimcTalentString()
  local playerGlyphs  = CreateSimcGlyphString()

  -- Build the output string for the player (not including gear)
  local simulationcraftProfile = player .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerLevel .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRace .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRole .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerProfessions .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerTalents .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerGlyphs .. '\n'
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
  simulationcraftProfile = simulationcraftProfile .. '\n\n' ..simc_err_str

  -- show the appropriate frames
  SimcCopyFrame:Show()
  SimcCopyFrameScroll:Show()
  SimcCopyFrameScrollText:Show()
  SimcCopyFrameScrollText:SetText(simulationcraftProfile)
  SimcCopyFrameScrollText:HighlightText()
  
end
