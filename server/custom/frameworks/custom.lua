-- Runs once force_transportrobbery knows the framework is "custom": Config.Framework = "custom", or "auto" when
-- none of qbx_core, es_extended and qb-core is installed. Keep your code inside this function.
RegisterFramework("custom", function()
  --- TODO: a stable id of the player's character (a robbery belongs to this id). nil while no character is loaded:
  --- nobody can start a robbery until this returns something.
  --- @param source number
  --- @return string|nil
  function GetIdentifier(source)
    return nil
  end

  --- TODO: server ids of the players with one of the police jobs. Used for Config.Police.minimum and the alarm.
  --- @param jobs table<string, true> e.g. { police = true }
  --- @param onlyOnDuty boolean
  --- @return number[]
  function GetPolice(jobs, onlyOnDuty)
    return {}
  end

  --- TODO: pay the reward. Return true only when the money was added.
  --- @param account "cash"|"bank"|"dirty"
  --- @return boolean
  function AddMoney(source, account, amount)
    return false
  end
end)
