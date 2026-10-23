-- Runs once force_transportrobbery knows the framework is "qbx" (Config.Framework, or detected by the server).
-- Keep your code inside this function. Dirty money goes through ox_inventory (server/custom/inventory.lua).
RegisterFramework("qbx", function()
  local function getPlayer(source)
    if GetResourceState("qbx_core") ~= "started" then return nil end
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(source) end)
    return ok and player or nil
  end

  --- Citizen id (a robbery belongs to this character), nil while the player has no character loaded
  --- @param source number
  --- @return string|nil
  function GetIdentifier(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
  end

  --- Server ids of the players with one of the police jobs (on duty when onlyOnDuty)
  --- @param jobs table<string, true>
  --- @param onlyOnDuty boolean
  --- @return number[]
  function GetPolice(jobs, onlyOnDuty)
    if GetResourceState("qbx_core") ~= "started" then return {} end
    local ok, players = pcall(function() return exports.qbx_core:GetQBPlayers() end)
    if not ok or type(players) ~= "table" then return {} end
    local list = {}
    for id, player in pairs(players) do
      local job = player.PlayerData and player.PlayerData.job
      if type(job) == "table" and jobs[job.name] and (not onlyOnDuty or job.onduty) then
        list[#list + 1] = tonumber(player.PlayerData.source) or tonumber(id)
      end
    end
    return list
  end

  --- Pays the reward. Return true only when the money was added.
  --- "dirty": the black_money item in ox_inventory.
  --- @param account "cash"|"bank"|"dirty"
  --- @return boolean
  function AddMoney(source, account, amount)
    if account == "dirty" then return AddItem(source, "black_money", amount) end
    local player = getPlayer(source)
    if not player then return false end
    return player.Functions.AddMoney(account, amount, "transport-robbery") ~= false
  end
end)
