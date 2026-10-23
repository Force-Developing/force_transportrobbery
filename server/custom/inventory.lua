-- Dirty money as an item: the black_money item of ox_inventory (QBox, and QBCore servers that run ox_inventory).
-- Without ox_inventory, QBCore pays markedbills through its own player functions (server/custom/frameworks/qb.lua).

--- @return boolean added
function AddItem(source, item, count)
  if GetResourceState("ox_inventory") ~= "started" then
    Log("error", ("Can't give %sx %s: ox_inventory isn't running"):format(count, item))
    return false
  end
  local ok, success, response = pcall(function() return exports.ox_inventory:AddItem(source, item, count) end)
  if not ok then
    Log("error", ("ox_inventory AddItem failed: %s"):format(tostring(success)))
    return false
  end
  if not success and response == "invalid_item" then
    Log("error", ("Item '%s' doesn't exist in ox_inventory. Add it, or pay the reward as cash or bank."):format(item))
  end
  return success == true
end
