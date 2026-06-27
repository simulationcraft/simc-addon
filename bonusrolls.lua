-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, Simulationcraft = ...   -- same shared addon table as core.lua / extras.lua

-- Log bonus rolls for exprot
--
-- Events:
--   SPELL_CONFIRMATION_PROMPT  - source/context/keyLevel (stashed in-memory)
--   BONUS_ROLL_RESULT          - the item (no encounter info)
--
-- Item pools are per spec/encounter/context/keyLevel
--
-- Consulted KeystoneLoot and VoidcoreAdvisor to figure some of this out

-- Read/store data by current loot spec (or active spec if no loot spec set)
local function ResolveLootSpecId(specId)
  if not specId or specId == 0 then
    specId = GetLootSpecialization()
  end
  if not specId or specId == 0 then
    local active = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    if active then
      specId = C_SpecializationInfo.GetSpecializationInfo(active)
    end
  end
  return specId or 0
end

function Simulationcraft:GetCurrentSeasonId()
  if C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
    local seasonId = C_SeasonInfo.GetCurrentDisplaySeasonID()
    if seasonId and seasonId > 0 then
      return seasonId
    end
  end
  if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
    local mythicSeason = C_MythicPlus.GetCurrentSeason()
    if mythicSeason and mythicSeason > 0 then
      return mythicSeason
    end
  end
  return 0
end

-- Capture source/context/keyLevel in case the roll is used
function Simulationcraft:OnSpellConfirmationPrompt(_, spellID)
  local prompts = GetSpellConfirmationPromptsInfo and GetSpellConfirmationPromptsInfo()
  if not prompts then return end
  for _, entry in ipairs(prompts) do
    if entry.spellID == spellID then
      self.pendingBonusRoll = {
        currency = entry.currencyID,
        source = entry.displayItemID,
        context = entry.itemContext,
        keyLevel = entry.treasureContextLevel,
      }
      return
    end
  end
end

-- Capture the item after the roll
function Simulationcraft:OnBonusRollResult(_, typeIdentifier, itemLink, _, specID)
  if typeIdentifier ~= "item" or type(itemLink) ~= "string" then
    return
  end

  local itemId = tonumber(itemLink:match("|Hitem:(%d+):"))
  if not itemId then
    return
  end

  local pending = self.pendingBonusRoll or {}
  local currency = pending.currency or 0
  local source = pending.source or 0
  local keyLevel = pending.keyLevel or 0
  -- fall back to the won item's own context (item-string field 12) when the prompt was missed
  local context = pending.context or Simulationcraft.GetItemSplit(itemLink)[Simulationcraft.OFFSET_CONTEXT] or 0

  self:RecordBonusRoll(currency, source, context, keyLevel, itemId, specID)
  self.pendingBonusRoll = nil
end

-- Append a won item as a self-contained entry; the export filters these by season/spec.
function Simulationcraft:RecordBonusRoll(currency, source, ctx, keyLevel, itemId, specId)
  local rolls = self.db.char.bonusRolls
  rolls[#rolls + 1] = {
    season   = self:GetCurrentSeasonId(),
    spec     = ResolveLootSpecId(specId),
    currency = currency or 0,
    source   = source or 0,
    context  = ctx or 0,
    keyLevel = keyLevel or 0,
    itemId   = itemId,
    ts       = C_DateAndTime.GetServerTimeLocal(),
  }
end

-- Export the current season + current spec's pool as 'currency:source:context:keyLevel:itemId/...'.
function Simulationcraft:GetBonusRollItems()
  local season = self:GetCurrentSeasonId()
  local spec = ResolveLootSpecId(nil)
  local keys = {}
  for _, roll in ipairs(self.db.char.bonusRolls) do
    if type(roll) == 'table' and roll.season == season and roll.spec == spec then
      -- currency leads the key so Raidbots can map it to a season and drop stale-pool rolls
      keys[#keys + 1] = roll.currency .. ':' .. roll.source .. ':' .. roll.context .. ':' .. roll.keyLevel .. ':' .. roll.itemId
    end
  end
  table.sort(keys)
  return table.concat(keys, '/')
end

function Simulationcraft:SetupBonusRolls()
  self:RegisterEvent("SPELL_CONFIRMATION_PROMPT", "OnSpellConfirmationPrompt")
  self:RegisterEvent("BONUS_ROLL_RESULT", "OnBonusRollResult")
  -- prime C_MythicPlus.GetCurrentSeason() (the season-helper fallback) once
  if C_MythicPlus and C_MythicPlus.RequestMapInfo then
    C_MythicPlus.RequestMapInfo()
  end
end
