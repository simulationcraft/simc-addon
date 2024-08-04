-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, Simulationcraft = ...

Simulationcraft = LibStub("AceAddon-3.0"):NewAddon(Simulationcraft, "Simulationcraft", "AceConsole-3.0", "AceEvent-3.0")
LibRealmInfo = LibStub("LibRealmInfo")

-- Set up DataBroker for minimap button
SimcLDB = LibStub("LibDataBroker-1.1"):NewDataObject("SimulationCraft", {
  type = "data source",
  text = "SimulationCraft",
  label = "SimulationCraft",
  icon = "Interface\\AddOns\\SimulationCraft\\logo",
  OnClick = function()
    if SimcFrame and SimcFrame:IsShown() then
      SimcFrame:Hide()
    else
      Simulationcraft:PrintSimcProfile(false, false, false)
    end
  end,
  OnTooltipShow = function(tt)
    tt:AddLine("SimulationCraft")
    tt:AddLine(" ")
    tt:AddLine("Click to show SimC input")
    tt:AddLine("To toggle minimap button, type '/simc minimap'")
  end
})

LibDBIcon = LibStub("LibDBIcon-1.0")

local SimcFrame = nil

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
-- local OFFSET_GEM_ID_2 = 4
-- local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_GEM_BASE = OFFSET_GEM_ID_1
local OFFSET_SUFFIX_ID = 7
-- local OFFSET_FLAGS = 11
-- local OFFSET_CONTEXT = 12
local OFFSET_BONUS_ID = 13

local OFFSET_GEM_BONUS_FROM_MODS = 2

local ITEM_MOD_TYPE_DROP_LEVEL = 9
-- 28 shows frequently but is currently unknown
local ITEM_MOD_TYPE_CRAFT_STATS_1 = 29
local ITEM_MOD_TYPE_CRAFT_STATS_2 = 30

local SUPPORTED_LOADOUT_SERIALIZATION_VERSION = 2

local WeeklyRewards         = _G.C_WeeklyRewards

-- New talents for Dragonflight
local ClassTalents          = _G.C_ClassTalents
local Traits                = _G.C_Traits

-- GetAddOnMetadata was global until 10.1. It's now in C_AddOns. This line will use C_AddOns if available and work in either WoW build
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- Some global item functions have been moved into C_Item in 11.0
local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount

-- Talent string export
local bitWidthHeaderVersion         = 8
local bitWidthSpecID                = 16
local bitWidthRanksPurchased        = 6

-- load stuff from extras.lua
-- local upgradeTable        = Simulationcraft.upgradeTable
local slotNames           = Simulationcraft.slotNames
local simcSlotNames       = Simulationcraft.simcSlotNames
local specNames           = Simulationcraft.SpecNames
local profNames           = Simulationcraft.ProfNames
local regionString        = Simulationcraft.RegionString
local zandalariLoaBuffs   = Simulationcraft.zandalariLoaBuffs

-- Most of the guts of this addon were based on a variety of other ones, including
-- Statslog, AskMrRobot, and BonusScanner. And a bunch of hacking around with AceGUI.
-- Many thanks to the authors of those addons, and to reia for fixing my awful amateur
-- coding mistakes regarding objects and namespaces.

function Simulationcraft:OnInitialize()
  -- init databroker
  self.db = LibStub("AceDB-3.0"):New("SimulationCraftDB", {
    profile = {
      minimap = {
        hide = false,
      },
      frame = {
        point = "CENTER",
        relativeFrame = nil,
        relativePoint = "CENTER",
        ofsx = 0,
        ofsy = 0,
        width = 750,
        height = 400,
      },
    },
  });
  LibDBIcon:Register("SimulationCraft", SimcLDB, self.db.profile.minimap)
  Simulationcraft:UpdateMinimapButton()
  Simulationcraft:RegisterChatCommand('simc', 'HandleChatCommand')
  AddonCompartmentFrame:RegisterAddon({
    text = "SimulationCraft",
    icon = "Interface\\AddOns\\SimulationCraft\\logo",
    notCheckable = true,
    func = function()
      Simulationcraft:PrintSimcProfile(false, false, false)
    end,
  })
end

function Simulationcraft:OnEnable()

end

function Simulationcraft:OnDisable()

end

function Simulationcraft:UpdateMinimapButton()
  if (self.db.profile.minimap.hide) then
    LibDBIcon:Hide("SimulationCraft")
  else
    LibDBIcon:Show("SimulationCraft")
  end
end

local function getLinks(input)
  local separatedLinks = {}
  for link in input:gmatch("|c.-|h|r") do
     separatedLinks[#separatedLinks + 1] = link
  end
  return separatedLinks
end

function Simulationcraft:HandleChatCommand(input)
  local args = {strsplit(' ', input)}

  local debugOutput = false
  local noBags = false
  local showMerchant = false
  local links = getLinks(input)

  for _, arg in ipairs(args) do
    if arg == 'debug' then
      debugOutput = true
    elseif arg == 'nobag' or arg == 'nobags' or arg == 'nb' then
      noBags = true
    elseif arg == 'merchant' then
      showMerchant = true
    elseif arg == 'minimap' then
      self.db.profile.minimap.hide = not self.db.profile.minimap.hide
      DEFAULT_CHAT_FRAME:AddMessage(
        "SimulationCraft: Minimap button is now " .. (self.db.profile.minimap.hide and "hidden" or "shown")
      )
      Simulationcraft:UpdateMinimapButton()
      return
    end
  end

  self:PrintSimcProfile(debugOutput, noBags, showMerchant, links)
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

local function GetItemName(itemLink)
  local name = string.match(itemLink, '|h%[(.*)%]|')
  local removeIcons = gsub(name, '|%a.+|%a', '')
  local trimmed = string.match(removeIcons, '^%s*(.*)%s*$')
  -- check for empty string or only spaces
  if string.match(trimmed, '^%s*$') then
    return nil
  end

  return trimmed
end

-- char size for utf8 strings
local function ChrSize(char)
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
local function Tokenize(str)
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
    elseif ChrSize(b) > 1 then
      local offset = ChrSize(b) - 1
      s = s .. str:sub(i, i + offset)
      i = i + offset -- luacheck: no unused
    end
  end
  -- strip trailing spaces
  if string.sub(s, s:len())=='_' then
    s = string.sub(s, 0, s:len()-1)
  end
  return s
end

-- method to add spaces to UnitRace names for proper tokenization
local function FormatRace(str)
  str = str or ""
  local matches = {}
  for match, _ in string.gmatch(str, '([%u][%l]*)') do
    matches[#matches+1] = match
  end
  return string.join(' ', unpack(matches))
end

-- method for constructing the talent string
local function CreateSimcTalentString()
  local talentInfo = {}
  local maxTiers = 7
  local maxColumns = 3
  for tier = 1, maxTiers do
    for column = 1, maxColumns do
      local _, _, _, selected, _ = GetTalentInfo(tier, column, GetActiveSpecGroup())
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

-- class_talents= builder for dragonflight
-- Older function, leave around for reference
-- local function GetTalentString(configId)
--   local entryStrings = {}
--
--   local active = false
--   if configId == ClassTalents.GetActiveConfigID() then
--     active = true
--   end
--
--   local configInfo = Traits.GetConfigInfo(configId)
--   for _, treeId in pairs(configInfo.treeIDs) do
--     local nodes = Traits.GetTreeNodes(treeId)
--     for _, nodeId in pairs(nodes) do
--       local node = Traits.GetNodeInfo(configId, nodeId)
--       if node.ranksPurchased > 0 then
--         entryStrings[#entryStrings + 1] = node.activeEntry.entryID .. ":" .. node.activeEntry.rank
--       end
--     end
--   end
--
--   local str = "class_talents=" .. table.concat(entryStrings, '/')
--   if not active then
--     -- comment out the class_talents and then prepend a comment with the loadout name
--     str = '# ' .. str
--     str = '# Saved Loadout: ' .. configInfo.name .. '\n' .. str
--   end
--
--   return str
-- end

-- based on ClassTalentImportExportMixin:WriteLoadoutHeader
local function WriteLoadoutHeader(exportStream, serializationVersion, specID, treeHash)
  exportStream:AddValue(bitWidthHeaderVersion, serializationVersion)
  exportStream:AddValue(bitWidthSpecID, specID)
  for _, hashVal in ipairs(treeHash) do
    exportStream:AddValue(8, hashVal)
  end
end

-- based on ClassTalentImportExportMixin:GetActiveEntryIndex(treeNode)
local function GetActiveEntryIndex(treeNode)
  for i, entryID in ipairs(treeNode.entryIDs) do
    if(treeNode.activeEntry and entryID == treeNode.activeEntry.entryID) then
      return i;
    end
  end

  return 0;
end

-- based on ClassTalentImportExportMixin:WriteLoadoutContent
local function WriteLoadoutContent(exportStream, configID, treeID)
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  for _, treeNodeID in ipairs(treeNodes) do
    local treeNode = C_Traits.GetNodeInfo(configID, treeNodeID);

    local isNodeGranted = treeNode.activeRank - treeNode.ranksPurchased > 0;
    local isNodePurchased = treeNode.ranksPurchased > 0;
    local isNodeSelected = isNodeGranted or isNodePurchased;
    local isPartiallyRanked = treeNode.ranksPurchased ~= treeNode.maxRanks;
    local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection
      or treeNode.type == Enum.TraitNodeType.SubTreeSelection;

    exportStream:AddValue(1, isNodeSelected and 1 or 0);
    if(isNodeSelected) then
      exportStream:AddValue(1, isNodePurchased and 1 or 0);

      if isNodePurchased then
        exportStream:AddValue(1, isPartiallyRanked and 1 or 0);
        if(isPartiallyRanked) then
          exportStream:AddValue(bitWidthRanksPurchased, treeNode.ranksPurchased);
        end

        exportStream:AddValue(1, isChoiceNode and 1 or 0);
        if(isChoiceNode) then
          local entryIndex = GetActiveEntryIndex(treeNode);
          if(entryIndex <= 0 or entryIndex > 4) then
            local configInfo = Traits.GetConfigInfo(configID)
            local errorMsg = "Talent loadout '" .. configInfo.name .. "' is corrupt/incomplete. It needs to be"
              .. " recreated or deleted for /simc to function properly"
            print(errorMsg);
            error(errorMsg);
          end

          -- store entry index as zero-index
          exportStream:AddValue(2, entryIndex - 1);
        end
      end
    end
  end
end

-- based on ClassTalentImportExportMixin:GetLoadoutExportString
local function GetExportString(configID)
  local active = false
  if configID == ClassTalents.GetActiveConfigID() then
    active = true
  end

  local exportStream = ExportUtil.MakeExportDataStream();
  local configInfo = Traits.GetConfigInfo(configID);
  local currentSpecID = PlayerUtil.GetCurrentSpecID();
  local treeID = configInfo.treeIDs[1];
  local treeHash = C_Traits.GetTreeHash(treeID);
  local serializationVersion = C_Traits.GetLoadoutSerializationVersion();

  WriteLoadoutHeader(exportStream, serializationVersion, currentSpecID, treeHash )
  WriteLoadoutContent(exportStream, configID, treeID)

  local str = "talents=" .. exportStream:GetExportString()
  if not active then
    -- comment out the talents and then prepend a comment with the loadout name
    str = '# ' .. str
    -- Make sure any pipe characters get unescaped, otherwise breaks checksums
    str = '# Saved Loadout: ' .. configInfo.name:gsub("||", "|") .. '\n' .. str
  end

  return str
end

-- function that translates between the game's role values and ours
local function TranslateRole(spec_id, str)
  local spec_role = Simulationcraft.RoleTable[spec_id]
  if spec_role ~= nil then
    return spec_role
  end

  if str == 'TANK' then
    return 'tank'
  elseif str == 'DAMAGER' then
    return 'attack'
  elseif str == 'HEALER' then
    return 'attack'
  else
    return ''
  end
end

-- =================== Item Information =========================

local function GetItemStringFromItemLink(slotNum, itemLink, debugOutput)
  local itemSplit = GetItemSplit(itemLink)
  local simcItemOptions = {}
  local gems = {}
  local gemBonuses = {}

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
    gems[gemIndex] = 0
    gemBonuses[gemIndex] = 0
    if itemSplit[gemOffset] > 0 then
      local gemId = itemSplit[gemOffset]
      if gemId > 0 then
        gems[gemIndex] = gemId
      end
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

  local bonuses = {}

  for index=1, itemSplit[OFFSET_BONUS_ID] do
    bonuses[#bonuses + 1] = itemSplit[OFFSET_BONUS_ID + index]
  end

  if #bonuses > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
  end

  -- Shadowlands looks like it changed the item string
  -- There's now a variable list of additional data after bonus IDs, looks like some kind of type/value pairs
  local linkOffset = OFFSET_BONUS_ID + #bonuses + 1

  local craftedStats = {}
  local numPairs = itemSplit[linkOffset]
  for index=1, numPairs do
    local pairOffset = 1 + linkOffset + (2 * (index - 1))
    local pairType = itemSplit[pairOffset]
    local pairValue = itemSplit[pairOffset + 1]
    if pairType == ITEM_MOD_TYPE_DROP_LEVEL then
      simcItemOptions[#simcItemOptions + 1] = 'drop_level=' .. pairValue
    elseif pairType == ITEM_MOD_TYPE_CRAFT_STATS_1 or pairType == ITEM_MOD_TYPE_CRAFT_STATS_2 then
      craftedStats[#craftedStats + 1] = pairValue
    end
  end

  if #craftedStats > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'crafted_stats=' .. table.concat(craftedStats, '/')
  end

  -- gem bonuses
  local gemBonusOffset = linkOffset + (2 * numPairs) + OFFSET_GEM_BONUS_FROM_MODS
  local numGemBonuses = itemSplit[gemBonusOffset]
  local gemBonuses = {}
  for index=1, numGemBonuses do
    local offset = gemBonusOffset + index
    gemBonuses[index] = itemSplit[offset]
  end

  if #gemBonuses > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'gem_bonus_id=' .. table.concat(gemBonuses, '/')
  end

  local craftingQuality = C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemLink);
  if craftingQuality then
    simcItemOptions[#simcItemOptions + 1] = 'crafting_quality=' .. craftingQuality
  end

  local itemStr = ''
  itemStr = itemStr .. (simcSlotNames[slotNum] or 'unknown') .. "=" .. table.concat(simcItemOptions, ',')
  if debugOutput then
    itemStr = itemStr .. '\n# ' .. gsub(itemLink, "\124", "\124\124") .. '\n'
  end

  return itemStr
end

function Simulationcraft:GetItemStrings(debugOutput)
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      -- In theory, this should always be loaded/cached
      local name = GetItemName(itemLink)

      -- get correct level for scaling gear
      local level, _, _ = GetDetailedItemLevelInfo(itemLink)

      local itemComment
      if name and level then
        itemComment = name .. ' (' .. level .. ')'
      end

      items[slotNum] = {
        string = GetItemStringFromItemLink(slotNum, itemLink, debugOutput),
        name = itemComment
      }
    end
  end

  return items
end

-- Iterate through all container slots looking for gear that can be equipped.
-- Item name and item level may not be available if other addons are causing lookups to be throttled but
-- item links and IDs should always be available
function Simulationcraft:GetBagItemStrings(debugOutput)
  local bagItems = {}

  -- https://wowpedia.fandom.com/wiki/BagID
  -- Bag indexes are a pain, need to start in the negatives to check everything (like the default bank container)
  for bag=BACKPACK_CONTAINER - ITEM_INVENTORY_BANK_BAG_OFFSET, NUM_TOTAL_EQUIPPED_BAG_SLOTS + NUM_BANKBAGSLOTS do
    for slot=1, C_Container.GetContainerNumSlots(bag) do
      local itemId = C_Container.GetContainerItemID(bag, slot)

      -- something is in the bag slot
      if itemId then
        local _, _, _, itemEquipLoc = GetItemInfoInstant(itemId)
        local slotNum = Simulationcraft.invTypeToSlotNum[itemEquipLoc]

        -- item can be equipped
        if slotNum then
          local info = C_Container.GetContainerItemInfo(bag, slot)
          local itemLink = C_Container.GetContainerItemLink(bag, slot)
          bagItems[#bagItems + 1] = {
            string = GetItemStringFromItemLink(slotNum, itemLink, debugOutput),
            slotNum = slotNum
          }
          local itemName = GetItemName(itemLink)
          local level, _, _ = GetDetailedItemLevelInfo(itemLink)
          if itemName and level then
            bagItems[#bagItems].name = itemName .. ' (' .. level .. ')'
          end
        end
      end
    end
  end

  -- order results by paper doll slot, not bag slot
  table.sort(bagItems, function (a, b) return a.slotNum < b.slotNum end)

  return bagItems
end

-- Scan buffs to determine which loa racial this player has, if any
function Simulationcraft:GetZandalariLoa()
  local zandalariLoa = nil
  for index = 1, 32 do
    local auraData = C_UnitAuras.GetBuffDataByIndex("player", index)
    local spellId = auraData.spellId
    if spellId == nil then
      break
    end
    if zandalariLoaBuffs[spellId] then
      zandalariLoa = zandalariLoaBuffs[spellId]
      break
    end
  end
  return zandalariLoa
end

function Simulationcraft:GetSlotHighWatermarks()
  if C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkForSlot then
    local slots = {}
    -- These are not normal equipment slots, they are Enum.ItemRedundancySlot
    for slot = 0, 16 do
      local characterHighWatermark, accountHighWatermark = C_ItemUpgrade.GetHighWatermarkForSlot(slot)
      if characterHighWatermark or accountHighWatermark then
        slots[#slots + 1] = table.concat({  slot, characterHighWatermark, accountHighWatermark }, ':')
      end
    end
    return table.concat(slots, '/')
  end
end

function Simulationcraft:GetUpgradeCurrencies()
  local upgradeCurrencies = {}
  -- Collect actual currencies
  for currencyId, currencyName in pairs(Simulationcraft.upgradeCurrencies) do
    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyId)
    if currencyInfo and currencyInfo.quantity > 0 then
      upgradeCurrencies[#upgradeCurrencies + 1] = table.concat({ "c", currencyId, currencyInfo.quantity }, ':')
    end
  end

  -- Collect items that get used as currencies
  for itemId, itemName in pairs(Simulationcraft.upgradeItems) do
    local count = GetItemCount(itemId, true, true, true)
    if count > 0 then
      upgradeCurrencies[#upgradeCurrencies + 1] = table.concat({ "i", itemId, count }, ':')
    end
  end

  return table.concat(upgradeCurrencies, '/')
end

function Simulationcraft:GetMainFrame(text)
  -- Frame code largely adapted from https://www.wowinterface.com/forums/showpost.php?p=323901&postcount=2
  if not SimcFrame then
    -- Main Frame
    local frameConfig = self.db.profile.frame
    local f = CreateFrame("Frame", "SimcFrame", UIParent, "DialogBoxFrame")
    f:ClearAllPoints()
    -- load position from local DB
    f:SetPoint(
      frameConfig.point,
      frameConfig.relativeFrame,
      frameConfig.relativePoint,
      frameConfig.ofsx,
      frameConfig.ofsy
    )
    f:SetSize(frameConfig.width, frameConfig.height)
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight",
      edgeSize = 16,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
      if button == "LeftButton" then
        self:StartMoving()
      end
    end)
    f:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
      self:StopMovingOrSizing()
      -- save position between sessions
      local point, relativeFrame, relativeTo, ofsx, ofsy = self:GetPoint()
      frameConfig.point = point
      frameConfig.relativeFrame = relativeFrame
      frameConfig.relativePoint = relativeTo
      frameConfig.ofsx = ofsx
      frameConfig.ofsy = ofsy
    end)

    -- scroll frame
    local sf = CreateFrame("ScrollFrame", "SimcScrollFrame", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("LEFT", 16, 0)
    sf:SetPoint("RIGHT", -32, 0)
    sf:SetPoint("TOP", 0, -32)
    sf:SetPoint("BOTTOM", SimcFrameButton, "TOP", 0, 0)

    -- edit box
    local eb = CreateFrame("EditBox", "SimcEditBox", SimcScrollFrame)
    eb:SetSize(sf:GetSize())
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)

    -- resizing
    f:SetResizable(true)
    if f.SetMinResize then
      -- older function from shadowlands and before
      -- Can remove when Dragonflight is in full swing
      f:SetMinResize(150, 100)
    else
      -- new func for dragonflight
      f:SetResizeBounds(150, 100, nil, nil)
    end
    local rb = CreateFrame("Button", "SimcResizeButton", f)
    rb:SetPoint("BOTTOMRIGHT", -6, 7)
    rb:SetSize(16, 16)

    rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    rb:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
        if button == "LeftButton" then
            f:StartSizing("BOTTOMRIGHT")
            self:GetHighlightTexture():Hide() -- more noticeable
        end
    end)
    rb:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
        f:StopMovingOrSizing()
        self:GetHighlightTexture():Show()
        eb:SetWidth(sf:GetWidth())

        -- save size between sessions
        frameConfig.width = f:GetWidth()
        frameConfig.height = f:GetHeight()
    end)

    SimcFrame = f
  end
  SimcEditBox:SetText(text)
  SimcEditBox:HighlightText()
  return SimcFrame
end

-- Adapted from https://github.com/philanc/plc/blob/master/plc/checksum.lua
local function adler32(s)
  -- return adler32 checksum  (uint32)
  -- adler32 is a checksum defined by Mark Adler for zlib
  -- (based on the Fletcher checksum used in ITU X.224)
  -- implementation based on RFC 1950 (zlib format spec), 1996
  local prime = 65521 --largest prime smaller than 2^16
  local s1, s2 = 1, 0

  -- limit s size to ensure that modulo prime can be done only at end
  -- 2^40 is too large for WoW Lua so limit to 2^30
  if #s > (bit.lshift(1, 30)) then error("adler32: string too large") end

  for i = 1,#s do
    local b = string.byte(s, i)
    s1 = s1 + b
    s2 = s2 + s1
    -- no need to test or compute mod prime every turn.
  end

  s1 = s1 % prime
  s2 = s2 % prime

  return (bit.lshift(s2, 16)) + s1
end --adler32()

function Simulationcraft:GetSimcProfile(debugOutput, noBags, showMerchant, links)
  -- addon metadata
  local versionComment = '# SimC Addon ' .. GetAddOnMetadata('Simulationcraft', 'Version')
  local wowVersion, wowBuild, _, wowToc = GetBuildInfo()
  local wowVersionComment = '# WoW ' .. wowVersion .. '.' .. wowBuild .. ', TOC ' .. wowToc
  local simcVersionWarning = '# Requires SimulationCraft 1000-01 or newer'

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
  local playerRegion = region or GetCurrentRegionName() or regionString[GetCurrentRegion()]

  -- Race info
  local _, playerRace = UnitRace('player')

  -- fix some races to match SimC format
  if playerRace == 'Scourge' then --lulz
    playerRace = 'Undead'
  else
    playerRace = FormatRace(playerRace)
  end

  local isZandalariTroll = false
  if Tokenize(playerRace) == 'zandalari_troll' then
    isZandalariTroll = true
  end

  -- Spec info
  local role, globalSpecID, playerRole
  local specId = GetSpecialization()
  if specId then
    globalSpecID,_,_,_,_,role = GetSpecializationInfo(specId)
  end
  local playerSpec = specNames[ globalSpecID ] or 'unknown'

  -- Professions
  local pid1, pid2 = GetProfessions()
  local firstProf, firstProfRank, secondProf, secondProfRank, profOneId, profTwoId
  if pid1 then
    _,_,firstProfRank,_,_,_,profOneId = GetProfessionInfo(pid1)
  end
  if pid2 then
    _,_,secondProfRank,_,_,_,profTwoId = GetProfessionInfo(pid2)
  end

  firstProf = profNames[ profOneId ]
  secondProf = profNames[ profTwoId ]

  local playerProfessions = '' -- luacheck: ignore
  if pid1 or pid2 then
    playerProfessions = 'professions='
    if pid1 then
      playerProfessions = playerProfessions..Tokenize(firstProf)..'='..tostring(firstProfRank)..'/'
    end
    if pid2 then
      playerProfessions = playerProfessions..Tokenize(secondProf)..'='..tostring(secondProfRank)
    end
  else
    playerProfessions = ''
  end

  -- create a header comment with basic player info and a date
  local headerComment = (
    "# " .. playerName .. ' - ' .. playerSpec
    .. ' - ' .. date('%Y-%m-%d %H:%M') .. ' - '
    .. playerRegion .. '/' .. playerRealm
 )


  -- Construct SimC-compatible strings from the basic information
  local player = Tokenize(playerClass) .. '="' .. playerName .. '"'
  playerLevel = 'level=' .. playerLevel
  playerRace = 'race=' .. Tokenize(playerRace)
  playerRole = 'role=' .. TranslateRole(globalSpecID, role)
  local playerSpecStr = 'spec=' .. Tokenize(playerSpec)
  playerRealm = 'server=' .. Tokenize(playerRealm)
  playerRegion = 'region=' .. Tokenize(playerRegion)

  -- Build the output string for the player (not including gear)
  local simcPrintError = nil
  local simulationcraftProfile = ''

  simulationcraftProfile = simulationcraftProfile .. headerComment .. '\n'
  simulationcraftProfile = simulationcraftProfile .. versionComment .. '\n'
  simulationcraftProfile = simulationcraftProfile .. wowVersionComment .. '\n'
  simulationcraftProfile = simulationcraftProfile .. simcVersionWarning .. '\n'
  simulationcraftProfile = simulationcraftProfile .. '\n'

  simulationcraftProfile = simulationcraftProfile .. player .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerLevel .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRace .. '\n'
  if isZandalariTroll then
    local zandalari_loa = Simulationcraft:GetZandalariLoa()
    if zandalari_loa then
      simulationcraftProfile = simulationcraftProfile .. "zandalari_loa=" .. zandalari_loa .. '\n'
    end
  end
  simulationcraftProfile = simulationcraftProfile .. playerRegion .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRealm .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRole .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerProfessions .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerSpecStr .. '\n'
  simulationcraftProfile = simulationcraftProfile .. '\n'

  if playerSpec == 'unknown' then -- luacheck: ignore
    -- do nothing
    -- Player does not have a spec / is in starting player area
  elseif ClassTalents then
    -- DRAGONFLIGHT
    -- new dragonflight talents
    if Traits.GetLoadoutSerializationVersion() ~= SUPPORTED_LOADOUT_SERIALIZATION_VERSION then
      simcPrintError = 'This version of the SimC addon does not work with this version of WoW.\n'
      simcPrintError = simcPrintError .. 'There is a mismatch in the version of talent string exports.\n'
      simcPrintError = simcPrintError .. '\n'
      if Traits.GetLoadoutSerializationVersion() > SUPPORTED_LOADOUT_SERIALIZATION_VERSION then
        simcPrintError = simcPrintError .. 'WoW is using a newer version - you probably need to update your addon.\n'
      else
        simcPrintError = simcPrintError .. 'WoW is using an older version - you may be running an alpha/beta addon that is not currently ready for retail.\n'
      end
      simcPrintError = simcPrintError .. '\n'
      simcPrintError = simcPrintError .. 'WoW talent string export version = ' .. Traits.GetLoadoutSerializationVersion() .. '\n'
      simcPrintError = simcPrintError .. 'Addon talent string export version = ' .. SUPPORTED_LOADOUT_SERIALIZATION_VERSION .. '\n'
    end

    local currentConfigId = ClassTalents.GetActiveConfigID()

    simulationcraftProfile = simulationcraftProfile .. GetExportString(currentConfigId) .. '\n'
    simulationcraftProfile = simulationcraftProfile .. '\n'

    local specConfigs = ClassTalents.GetConfigIDsBySpecID(globalSpecID)

    for _, configId in pairs(specConfigs) do
      simulationcraftProfile = simulationcraftProfile .. GetExportString(configId) .. '\n'
    end
  else
    -- old talents
    local playerTalents = CreateSimcTalentString()
    simulationcraftProfile = simulationcraftProfile .. playerTalents .. '\n'
  end

  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- Method that gets gear information
  local items = Simulationcraft:GetItemStrings(debugOutput)

  -- output gear
  for slotNum=1, #slotNames do
    local item = items[slotNum]
    if item then
      if item.name then
        simulationcraftProfile = simulationcraftProfile .. '# ' .. item.name .. '\n'
      end
      simulationcraftProfile = simulationcraftProfile .. items[slotNum].string .. '\n'
    end
  end

  -- output gear from bags
  if noBags == false then
    local bagItems = Simulationcraft:GetBagItemStrings(debugOutput)

    if #bagItems > 0 then
      simulationcraftProfile = simulationcraftProfile .. '\n'
      simulationcraftProfile = simulationcraftProfile .. '### Gear from Bags\n'
      for i=1, #bagItems do
        simulationcraftProfile = simulationcraftProfile .. '#\n'
        if bagItems[i].name and bagItems[i].name ~= '' then
          simulationcraftProfile = simulationcraftProfile .. '# ' .. bagItems[i].name .. '\n'
        end
        simulationcraftProfile = simulationcraftProfile .. '# ' .. bagItems[i].string .. '\n'
      end
    end
  end

  -- output weekly reward gear
  if WeeklyRewards then
    if WeeklyRewards:HasAvailableRewards() then
      simulationcraftProfile = simulationcraftProfile .. '\n'
      simulationcraftProfile = simulationcraftProfile .. '### Weekly Reward Choices\n'
      local activities = WeeklyRewards.GetActivities()
      for _, activityInfo in ipairs(activities) do
        for _, rewardInfo in ipairs(activityInfo.rewards) do
          local _, _, _, itemEquipLoc = GetItemInfoInstant(rewardInfo.id)
          local itemLink = WeeklyRewards.GetItemHyperlink(rewardInfo.itemDBID)
          local itemName = GetItemName(itemLink);
          local slotNum = Simulationcraft.invTypeToSlotNum[itemEquipLoc]
          if slotNum then
            local itemStr = GetItemStringFromItemLink(slotNum, itemLink, debugOutput)
            local level, _, _ = GetDetailedItemLevelInfo(itemLink)
            simulationcraftProfile = simulationcraftProfile .. '#\n'
            if itemName and level then
              itemNameComment = itemName .. ' ' .. '(' .. level .. ')'
              simulationcraftProfile = simulationcraftProfile .. '# ' .. itemNameComment .. '\n'
            end
            simulationcraftProfile = simulationcraftProfile .. '# ' .. itemStr .. "\n"
          end
        end
      end
      simulationcraftProfile = simulationcraftProfile .. '#\n'
      simulationcraftProfile = simulationcraftProfile .. '### End of Weekly Reward Choices\n'
    end
  end

  -- Dump out equippable items from a vendor, this is mostly for debugging / data collection
  local numMerchantItems = GetMerchantNumItems()
  if showMerchant and numMerchantItems > 0 then
    simulationcraftProfile = simulationcraftProfile .. '\n'
    simulationcraftProfile = simulationcraftProfile .. '\n### Merchant items\n'
    for i=1,numMerchantItems do
      local link = GetMerchantItemLink(i)
      local name,_,_,_,_,_,_,_,invType = GetItemInfo(link)
      if name and invType ~= "" then
        local slotNum = Simulationcraft.invTypeToSlotNum[invType]
        -- Doesn't work, seems to always return base item level
        -- local level, _, _ = GetDetailedItemLevelInfo(itemLink)
        local itemStr = GetItemStringFromItemLink(slotNum, link, false)
        simulationcraftProfile = simulationcraftProfile .. '#\n'
        if name then
          simulationcraftProfile = simulationcraftProfile .. '# ' .. name .. '\n'
        end
        simulationcraftProfile = simulationcraftProfile .. '# ' .. itemStr .. "\n"
      end
    end
  end


  -- output item links that were included in the /simc chat line
  if links and #links > 0 then
    simulationcraftProfile = simulationcraftProfile .. '\n'
    simulationcraftProfile = simulationcraftProfile .. '\n### Linked gear\n'
    for _, v in pairs(links) do
      local name,_,_,_,_,_,_,_,invType = GetItemInfo(v)
      if name and invType ~= "" then
        local slotNum = Simulationcraft.invTypeToSlotNum[invType]
        local itemStr = GetItemStringFromItemLink(slotNum, v, debugOutput)
        simulationcraftProfile = simulationcraftProfile .. '#\n'
        simulationcraftProfile = simulationcraftProfile .. '# ' .. name .. '\n'
        simulationcraftProfile = simulationcraftProfile .. '# ' .. itemStr .. "\n"
      else -- Someone linked something that was not gear.
        simcPrintError = "Error: " .. v .. " is not gear."
        break
      end
    end
  end

  simulationcraftProfile = simulationcraftProfile .. '\n'
  simulationcraftProfile = simulationcraftProfile .. '### Additional Character Info\n'

  local upgradeCurrenciesStr = Simulationcraft:GetUpgradeCurrencies()
  simulationcraftProfile = simulationcraftProfile .. '#\n'
  simulationcraftProfile = simulationcraftProfile .. '# upgrade_currencies=' .. upgradeCurrenciesStr .. '\n'

  local highWatermarksStr = Simulationcraft:GetSlotHighWatermarks()
  if highWatermarksStr then
    simulationcraftProfile = simulationcraftProfile .. '#\n'
    simulationcraftProfile = simulationcraftProfile .. '# slot_high_watermarks=' .. highWatermarksStr .. '\n'
  end

  -- sanity checks - if there's anything that makes the output completely invalid, punt!
  if specId==nil then
    simcPrintError = "Error: You need to pick a spec!"
  end

  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- Simple checksum to provide a lightweight verification that the input hasn't been edited/modified
  local checksum = adler32(simulationcraftProfile)

  simulationcraftProfile = simulationcraftProfile .. '# Checksum: ' .. string.format('%x', checksum)

  return simulationcraftProfile, simcPrintError
end

-- This is the workhorse function that constructs the profile
function Simulationcraft:PrintSimcProfile(debugOutput, noBags, showMerchant, links)
  local simulationcraftProfile, simcPrintError = Simulationcraft:GetSimcProfile(debugOutput, noBags, showMerchant, links)

  local f = Simulationcraft:GetMainFrame(simcPrintError or simulationcraftProfile)
  f:Show()
end
