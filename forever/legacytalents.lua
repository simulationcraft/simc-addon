-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, Simulationcraft = ...   -- same shared addon table as core.lua / extras.lua

-- Legacy trees for WoW Forever.
--
-- Legacy points (earned account-wide through Legacy challenges) are spent in three C_Traits
-- trees: Professions, Adventure and Progression (e.g. "gain talents 1-5 levels earlier").
-- There is one set per character, independent of the primary/secondary talent spec groups.
-- Exported in the same "entryID:rank/entryID:rank" form as the other trait systems.

local Traits = _G.C_Traits

-- Tree IDs come from the client's own constants; fall back to the Legacy UI's table
local function GetLegacyTreeIDs()
  local consts = Constants and Constants.LegacyConsts
  if consts then
    return {
      consts.LEGACY_TREE_PROFESSIONS_ID,
      consts.LEGACY_TREE_ADVENTURE_ID,
      consts.LEGACY_TREE_PROGRESSION_ID,
    }
  end
  local treeIDs = {}
  for _, treeData in ipairs(LegacyTreeData or {}) do
    treeIDs[#treeIDs + 1] = treeData.treeID
  end
  return treeIDs
end

-- Returns "entryID:rank/..." across all three Legacy trees, '' if no points are spent,
-- or nil if the Legacy system isn't available in this client.
function Simulationcraft:GetLegacyTalentString()
  if not (Traits and Traits.GetConfigIDByTreeID and Traits.GetTreeNodes and Traits.GetNodeInfo) then
    return nil
  end

  local treeIDs = GetLegacyTreeIDs()
  if #treeIDs == 0 then
    return nil
  end

  local entries = {}
  local sawConfig = false
  for _, treeID in ipairs(treeIDs) do
    local configID = Traits.GetConfigIDByTreeID(treeID)
    if configID then
      sawConfig = true
      for _, nodeID in ipairs(Traits.GetTreeNodes(treeID) or {}) do
        local node = Traits.GetNodeInfo(configID, nodeID)
        if node and node.ranksPurchased and node.ranksPurchased > 0 and node.activeEntry then
          -- activeEntry.rank isn't reliable for multi-rank Legacy nodes; currentRank is the point total
          entries[#entries + 1] = node.activeEntry.entryID .. ':' .. (node.currentRank or node.ranksPurchased)
        end
      end
    end
  end

  if not sawConfig then
    return nil
  end
  return table.concat(entries, '/')
end
