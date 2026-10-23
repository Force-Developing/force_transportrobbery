-- Runs once force_transportrobbery knows the framework is "qb" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("qb", function()
  local QBCore
  local resource = GetFrameworkResource() or "qb-core"
  -- Loaded again when qb-core restarts: the old core object points at the stopped resource
  LoadFrameworkObject(resource, function()
    return exports[resource]:GetCoreObject()
  end, function(obj)
    QBCore = obj
  end)

  local function getPlayer(source)
    return QBCore and QBCore.Functions.GetPlayer(source)
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
    if not QBCore then return {} end
    local list = {}
    for id, player in pairs(QBCore.Functions.GetQBPlayers() or {}) do
      local job = player.PlayerData and player.PlayerData.job
      if type(job) == "table" and jobs[job.name] and (not onlyOnDuty or job.onduty) then
        list[#list + 1] = tonumber(player.PlayerData.source) or tonumber(id)
      end
    end
    return list
  end

  local function itemBox(source, item, action, count)
    local shared = QBCore and QBCore.Shared and QBCore.Shared.Items
    if type(shared) == "table" and shared[item] then
      TriggerClientEvent("qb-inventory:client:ItemBox", source, shared[item], action, count)
    end
  end

  --- Pays the reward. Return true only when the money was added.
  --- "dirty": the black_money item with ox_inventory, otherwise one markedbills item worth the amount.
  --- @param account "cash"|"bank"|"dirty"
  --- @return boolean
  function AddMoney(source, account, amount)
    local player = getPlayer(source)
    if not player then return false end
    if account == "dirty" then
      if GetResourceState("ox_inventory") == "started" then return AddItem(source, "black_money", amount) end
      local added = player.Functions.AddItem("markedbills", 1, false, { worth = amount }) ~= false
      if added then itemBox(source, "markedbills", "add", 1) end
      return added
    end
    return player.Functions.AddMoney(account, amount, "transport-robbery") ~= false
  end
end)
