local _, Simulationcraft = ...

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
    local maxTiers = 6
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
    local str = 'glyphs='
    for i=1, NUM_GLYPH_SLOTS do
        local _,_,_,spellid = GetGlyphSocketInfo(i, nil)
        if (spellid) then
            name = GetSpellInfo(spellid)
            str = str .. StripGlyphPrefixes(name) ..'/'
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

-- =================== Item stuff========================= 
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
    
    --simcDebug('Bonus String:')
    --simcDebug(bonusStr)
    
    --simcDebug('Start Conversion:')    
    
    -- Extract Enchant bonus from string
    local enchantBonusStr = ''
    if bonusStr:len()>0 then
        enchantBonusStr = ConvertTooltipToStatStr( bonusStr )
    end
    --simcDebug('Result of Conversion:')    
    --simcDebug(enchantBonusStr)
    return enchantBonusStr

end

-- This scans the tooltip to get gem stats
local function GetGemBonus(link)
    SimulationcraftTooltip:ClearLines()
    SimulationcraftTooltip:SetHyperlink(link)
    local numLines = SimulationcraftTooltip:NumLines()
    --print(numLines)
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

function Simulationcraft:GetItemStuffs()
    local items = {}
    for slotNum=1, #slotNames do
        local slotId = GetInventorySlotInfo( slotNames[slotNum] )
        local itemLink = GetInventoryItemLink('player', slotId)
        local simcItemStr 
        
        -- if we don't have an item link, we don't care
        if itemLink then
            local itemString = string.match(itemLink, "item[%-?%d:]+")
            --simcDebug(itemString)
            local _, itemId, enchantId, gemId1, gemId2, gemId3, gemId4, _, _, _, upgradeId, unk1, hasBonus, bonusId = strsplit(":", itemString)

            local name = GetItemInfo( itemId )
            local upgradeLevel = upgradeTable[tonumber(upgradeId)]
            
            if not bonusId then
              bonusId = "0"
            end
            
            --=====Gems======
            -- determine number of sockets
            local statTable = GetItemStats(itemLink)
            local numSockets = 0
            for stat, value in pairs(statTable) do
                if string.match(stat, 'SOCKET') then
                    numSockets = numSockets + value
                end                
            end
            
            --simcDebug( itemLink )
            --simcDebug(enchantId)
            
            -- Gems are super easy if item id style is set
            local gemString=''
            if self.db.profile.newStyle then
                for i=1, 3 do -- hardcoded here to just grab all 3 sockets
                    local _,gemLink = GetItemGem(itemLink,i)
                    if gemLink then
                        --simcDebug(gemLink)
                        local gemDetail = string.match(gemLink, "item[%-?%d:]+")
                        --simcDebug(gemDetail)
                        gemString = gemString .. string.match(gemDetail, "item:(%d+):" ) .. "/"
                    else
                      gemString = gemString .. '0/'
                    end
                  --simcDebug(gemString)
                end
                gemString = ',gem_id=' .. gemString
                --simcDebug(gemString)
              -- and a giant pain in the ass otherwise. Lots of tooltip parsing
            else
                -- check for socket bonus activation and gems
                local useBonus=true
                if numSockets>0 then
                    SocketInventoryItem(slotId)
                    for i=1, numSockets do
                        local name,_,matches = GetExistingSocketInfo(i)
                        --if name then print(name) else print('no Gem') end
                        --if matches then print(matches) end
                        if not matches then
                            useBonus=false
                        end
                        local name,gemLink = GetItemGem(itemLink,i)
                        --simcDebug(gemLink)
                        local gemBonus = GetGemBonus(gemLink)
                        --simcDebug(gemBonus)
                        if gemString:len()>0 then
                            gemString=gemString .. '_' .. gemBonus
                        else
                            gemString=gemBonus
                        end
                    end
                    -- check for an extra socket (BS, belt buckle)
                    local name,gemLink = GetItemGem(itemLink,numSockets+1)
                    --simcDebug(gemLink)
                    if gemLink then
                        gemBonus = GetGemBonus(gemLink)
                        if gemString:len()>0 then 
                            gemString = gemString .. '_' .. gemBonus
                        else
                            gemString = gemBonus
                        end
                    end
                    CloseSocketInfo()
                    if useBonus then
                        socketBonus=GetSocketBonus(itemLink)
                        gemString = gemString .. '_' .. socketBonus
                    end
                    -- construct final gem string
                    gemString = ',gems=' .. gemString
                end
            end
            
            --simcDebug('Starting Enchant Section')
            --simcDebug(enchantId)
            --=====Enchants======
            -- Enchants are super easy if item id style is set
            local enchantString=''
            if self.db.profile.newStyle then
                --simcDebug('New Style')
                --simcDebug(enchantId)
                enchantString = ',enchant_id=' .. enchantId
                --simcDebug(enchantString)
            else
                -- if this is a 'special' enchant, it's in enchantNames and we can just use that
                --simcDebug('Checking Special')
                --simcDebug(enchantId)
                if enchantNames[tonumber(enchantId)] then
                    --simcDebug('enchantNames[tonumber(enchantId)] is:')
                    --simcDebug(enchantNames[tonumber(enchantId)])
                    enchantString = ',enchant=' .. tokenize(enchantNames[tonumber(enchantId)])
                else
                -- otherwise we need some tooltip scanning
                    --simcDebug('Scanning Tooltip')
                    enchantBonus=GetEnchantBonus(itemLink)
                    if enchantBonus:len()>0 then
                        enchantString= ',enchant=' .. enchantBonus
                    end
                end
            end         
            
        simcItemStr = simcSlotNames[slotNum] .. "=" .. tokenize(name) .. ",id=" .. itemId .. ",bonus_id=".. bonusId .. ",upgrade=" .. upgradeLevel .. gemString .. enchantString
          --print('#sockets = '..numSockets .. ', bonus = ' .. tostring(useBonus))
          --print( simcItemStr )
        end
        items[slotNum] = simcItemStr
    end
    
    return items
end

-- This is the workhorse function that constructs the profile
function Simulationcraft:PrintSimcProfile()
    -- get basic player info
    local playerName = UnitName('player')
    local _, playerClass = UnitClass('player')
    local playerLevel = UnitLevel('player')
    local _, playerRace = UnitRace('player')
    local playerSpec, role
    local specId = GetSpecialization()    
    if specId then
      _, playerSpec,_,_,_,role = GetSpecializationInfo(specId)
    end
    
    local p1, p2 = GetProfessions()
    local playerProfessionOne, playerProfessionOneRank, playerProfessionTwo, playerProfessionTwoRank
    if p1 then
      playerProfessionOne,_,playerProfessionOneRank = GetProfessionInfo(p1)
    end
    if p2 then
      playerProfessionTwo,_,playerProfessionTwoRank = GetProfessionInfo(p2)
    end
    local realm = GetRealmName() -- not used yet (possibly for origin)

    -- get player info that's a little more involved
    local playerTalents = CreateSimcTalentString()
    local playerGlyphs = CreateSimcGlyphString()
    
    -- construct some strings from the basic information
    local player = tokenize(playerClass) .. '=' .. tokenize(playerName)
    playerLevel = 'level=' .. playerLevel
    playerRace = 'race=' .. tokenize(playerRace)
    playerRole = 'role=' .. translateRole(role)
    playerSpec = 'spec=' .. tokenize(playerSpec)
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
    
    
    -- output testing
    local simulationcraftProfile = player .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerLevel .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerRace .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerRole .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerProfessions .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerTalents .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerGlyphs .. '\n'
    simulationcraftProfile = simulationcraftProfile .. playerSpec .. '\n\n'
        
    -- get gear info
    local items = Simulationcraft:GetItemStuffs()
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
         
    -- show the appropriate frames
    SimcCopyFrame:Show()
    SimcCopyFrameScroll:Show()
    SimcCopyFrameScrollText:Show()
    SimcCopyFrameScrollText:SetText(simulationcraftProfile)
    SimcCopyFrameScrollText:HighlightText()
    -- Abandoned GUI code from earlier implementations
    --[[
    self.exportFrame:Show()
    self.ebox:Show()
    -- put the text in the editbox and highlight it for copy/paste
    self.ebox.EditBox:SetText(simulationcraftProfile)
    --self.ebox.editBox:HighlightText()
    self.ebox.EditBox:SetFocus()
    self.ebox.EditBox:HighlightText()
    --]]
    
end