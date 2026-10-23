-- Runs once force_transportrobbery knows the framework is "esx" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("esx", function()
  local ESX
  local resource = GetFrameworkResource() or "es_extended"
  -- Loaded again when es_extended restarts: the old shared object points at the stopped resource
  LoadFrameworkObject(resource, function()
    return exports[resource]:getSharedObject()
  end, function(obj)
    ESX = obj
  end)

  local function getPlayer(source)
    return ESX and ESX.GetPlayerFromId(source)
  end

  --- Character identifier (a robbery belongs to this character), nil while the player has no character loaded
  --- @param source number
  --- @return string|nil
  function GetIdentifier(source)
    local xPlayer = getPlayer(source)
    return xPlayer and xPlayer.identifier or nil
  end

  --- Server ids of the players with one of the police jobs (on duty when onlyOnDuty and the ESX version has job.onDuty)
  --- @param jobs table<string, true>
  --- @param onlyOnDuty boolean
  --- @return number[]
  function GetPolice(jobs, onlyOnDuty)
    if not ESX then return {} end
    local players = {}
    if ESX.GetExtendedPlayers then
      players = ESX.GetExtendedPlayers()
    else
      for _, id in ipairs(ESX.GetPlayers()) do players[#players + 1] = ESX.GetPlayerFromId(id) end
    end
    local list = {}
    for _, xPlayer in pairs(players) do
      local job = type(xPlayer) == "table" and xPlayer.job
      if type(job) == "table" and jobs[job.name] and (not onlyOnDuty or job.onDuty ~= false) then
        list[#list + 1] = tonumber(xPlayer.source)
      end
    end
    return list
  end

  -- Config reward account -> ESX account
  local ACCOUNTS = { cash = "money", bank = "bank", dirty = "black_money" }

  --- Pays the reward. Return true only when the money was added.
  --- @param account "cash"|"bank"|"dirty"
  --- @return boolean
  function AddMoney(source, account, amount)
    local xPlayer = getPlayer(source)
    local name = ACCOUNTS[account]
    if not xPlayer or not name or not xPlayer.getAccount(name) then return false end
    xPlayer.addAccountMoney(name, amount, "Cash-in-transit robbery")
    return true
  end
end)
