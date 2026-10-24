local RESOURCE = GetCurrentResourceName()
-- Extra meters on top of a radius (the player's position on the server lags a little behind)
local DISTANCE_MARGIN = 3.0
-- A timed step may be reported this much before its duration is up (network and frame timing)
local FINISH_EARLY_MS = 1500
-- How long the server waits for an entity the client just created to exist here
local SPAWN_TIMEOUT_MS = 3000
-- The truck must be registered this close to its spawn point, the guards this close to the truck
local SPAWN_RADIUS = 30.0
local GUARD_RADIUS = 15.0
-- The truck may not cover the straight line from its spawn to the destination faster than this times its speed
local DRIVE_SPEED_FACTOR = 1.5

-- The one robbery that can run at a time (a single truck on a single route):
-- { source, identifier, stage, startedAt, deadline, waitStarted, spawnedAt, truck, guards, begun, alerted, finishing }
-- stage: "meet" (go to the ambush) -> "waiting" -> "follow" (truck out) -> "open" (doors cut) -> paid
local run = nil
local cooldownUntil = 0
local policeJobs = {}

local function prepareConfig()
  local police = type(Config.Police) == "table" and Config.Police or {}
  Config.Police = police
  -- Accepts { "police" } and { police = true }
  for key, value in pairs(type(police.jobs) == "table" and police.jobs or {}) do
    if type(value) == "string" then policeJobs[value] = true
    elseif type(key) == "string" and value then policeJobs[key] = true end
  end
  police.minimum = math.max(0, math.floor(tonumber(police.minimum) or 0))
  if police.minimum > 0 and next(policeJobs) == nil then
    Log("error", "Config.Police.minimum is set but Config.Police.jobs is empty: nobody can start a robbery")
  end
end

local function maxDurationMs()
  return math.max(5, tonumber(Config.MaxDuration) or 30) * 60000
end

local function cooldownMs()
  return math.max(0, tonumber(Config.Cooldown) or 0) * 60000
end

--- Shortest time the truck needs from its spawn to the destination
local function minDriveMs()
  local truck = Robbery.truck
  return #(truck.destination - truck.position) / (truck.speed * DRIVE_SPEED_FACTOR) * 1000
end

local function playerPed(source)
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then return nil end
  return ped
end

local function isNear(source, coords, distance)
  local ped = playerPed(source)
  return ped ~= nil and #(GetEntityCoords(ped) - coords) <= distance + DISTANCE_MARGIN
end

local function identifierOf(source)
  local ok, identifier = pcall(GetIdentifier, source)
  if not ok then
    Log("error", ("Reading the player's identifier failed: %s"):format(tostring(identifier)))
    return nil
  end
  return type(identifier) == "string" and identifier ~= "" and identifier or nil
end

--- Sources of the police on duty, or nil when the framework bridge failed
local function policeOnline()
  local ok, list = pcall(GetPolice, policeJobs, Config.Police.onlyOnDuty ~= false)
  if not ok or type(list) ~= "table" then
    Log("error", ("Reading the police failed: %s"):format(tostring(list)))
    return nil
  end
  return list
end

local function sameHash(a, b)
  a, b = math.tointeger(a), math.tointeger(b)
  return a ~= nil and b ~= nil and (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

local function deleteEntity(entity)
  if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end

--- The robbery of this player, or nil
local function runOf(source)
  if run and run.source == source then return run end
  return nil
end

--- Ends the robbery (if it is still the running one). Every way a robbery ends goes through here.
--- @param keepEntities boolean leave the truck and guards in the world (after the payout)
local function endRun(current, why, keepEntities)
  if not current or run ~= current then return end
  run = nil
  if current.alerted and cooldownMs() > 0 then cooldownUntil = GetGameTimer() + cooldownMs() end
  if not keepEntities then
    deleteEntity(current.truck)
    for _, ped in ipairs(current.guards) do deleteEntity(ped) end
  end
  Debug("info", "Robbery of %s ended: %s", tostring(GetPlayerName(current.source)), why)
end

--- Ends a robbery that ran past Config.MaxDuration and tells the client. Returns true when it did.
local function expire()
  local current = run
  if not current or current.finishing or GetGameTimer() <= current.deadline then return false end
  endRun(current, "max duration")
  TriggerClientEvent(RESOURCE .. ":client:ended", current.source, "expired")
  return true
end

--- Milliseconds left of the cooldown
local function cooldownLeft()
  return math.max(0, cooldownUntil - GetGameTimer())
end

lib.callback.register(RESOURCE .. ":server:start", function(source)
  if not IsFrameworkReady() or not Robbery.valid then return false, "not_ready" end
  local identifier = identifierOf(source)
  if not identifier then return false, "not_ready" end
  expire()
  if runOf(source) then return false, "busy" end
  if not isNear(source, Robbery.boss.position, GetInteractDistance()) then return false, "too_far" end
  if run then return false, "boss_busy" end
  local left = cooldownLeft()
  if left > 0 then return false, "cooldown", math.ceil(left / 60000) end
  if Config.Police.minimum > 0 then
    local police = policeOnline()
    if not police then return false, "not_ready" end
    -- the robber doesn't count, even with a police job
    local others = 0
    for _, id in ipairs(police) do
      if tonumber(id) ~= tonumber(source) then others = others + 1 end
    end
    if others < Config.Police.minimum then return false, "not_enough_police" end
  end

  local now = GetGameTimer()
  run = {
    source = source,
    identifier = identifier,
    stage = "meet",
    startedAt = now,
    deadline = now + maxDurationMs(),
    guards = {},
  }
  Debug("info", "%s started a robbery", tostring(GetPlayerName(source)))
  return true
end)

-- The player is at the ambush and starts waiting for the truck
lib.callback.register(RESOURCE .. ":server:wait", function(source)
  local current = runOf(source)
  if not current then return false, "no_run" end
  if expire() then return false, "expired" end
  if current.stage ~= "meet" then return false, "failed" end
  local ambush = Robbery.ambush
  if not isNear(source, ambush.coords, ambush.radius) then return false, "too_far" end
  current.stage = "waiting"
  current.waitStarted = GetGameTimer()
  return true, ambush.wait
end)

--- An entity the player's client owns, by net id (nil when it isn't one). The server can't see which client created
--- an entity, only its current owner; the callers also check the model and the position.
--- @param entityType number 1 = ped, 2 = vehicle
local function ownedEntity(source, netId, entityType)
  netId = math.tointeger(tonumber(netId))
  if not netId or netId <= 0 then return nil end
  local entity = NetworkGetEntityFromNetworkId(netId)
  local deadline = GetGameTimer() + SPAWN_TIMEOUT_MS
  while (not entity or entity == 0 or not DoesEntityExist(entity)) and GetGameTimer() < deadline do
    Wait(100)
    entity = NetworkGetEntityFromNetworkId(netId)
  end
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  if GetEntityType(entity) ~= entityType or NetworkGetEntityOwner(entity) ~= source then return nil end
  return entity
end

-- The wait is over and the client spawned the truck and its guards (networked, owned by the player's client:
-- only the owner can drive the guards' AI). The server checks what it got and deletes it when the robbery ends.
lib.callback.register(RESOURCE .. ":server:spawned", function(source, truckNet, guardNets)
  local current = runOf(source)
  if not current then return false, "no_run" end
  if expire() then return false, "expired" end
  if current.stage ~= "waiting" then return false, "failed" end
  local ambush = Robbery.ambush
  if GetGameTimer() - current.waitStarted < ambush.wait - FINISH_EARLY_MS then return false, "too_fast" end
  if not isNear(source, ambush.coords, ambush.radius) then return false, "too_far" end
  current.stage = "spawning"

  local def = Robbery.truck
  local truck = ownedEntity(source, truckNet, 2)
  -- the robbery may have ended while the server waited for the truck
  if run ~= current then return false, "no_run" end
  if not truck or not sameHash(GetEntityModel(truck), joaat(def.model))
      or #(GetEntityCoords(truck) - def.position) > SPAWN_RADIUS then
    current.stage = "waiting"
    Debug("warn", "Truck from %s rejected (net id %s)", tostring(GetPlayerName(source)), tostring(truckNet))
    return false, "truck_failed"
  end
  current.truck = truck

  local truckCoords = GetEntityCoords(truck)
  local seen = {}
  -- each configured guard can be matched once, by its model
  local open = {}
  for index, guard in ipairs(def.guards) do open[index] = joaat(guard.model) end
  for index, netId in ipairs(type(guardNets) == "table" and guardNets or {}) do
    if index > #def.guards then break end
    local ped = ownedEntity(source, netId, 1)
    if run ~= current then return false, "no_run" end
    if ped and not seen[ped] and not IsPedAPlayer(ped) and #(GetEntityCoords(ped) - truckCoords) <= GUARD_RADIUS then
      local model = GetEntityModel(ped)
      for slot, hash in pairs(open) do
        if sameHash(model, hash) then
          open[slot] = nil
          seen[ped] = true
          current.guards[#current.guards + 1] = ped
          break
        end
      end
    end
  end

  current.stage = "follow"
  current.spawnedAt = GetGameTimer()
  return true
end)

--- The truck must exist and stand at its destination, and the player next to it
--- @return boolean ok, string|nil reason
local function checkTruck(source, current, arriving)
  local truck = current.truck
  if not truck or not DoesEntityExist(truck) then
    endRun(current, "truck gone")
    return false, "truck_lost"
  end
  local def = Robbery.truck
  local coords = GetEntityCoords(truck)
  if #(coords - def.destination) > def.arriveRadius + DISTANCE_MARGIN then return false, "not_arrived" end
  if arriving and GetGameTimer() - current.spawnedAt < minDriveMs() then return false, "too_fast" end
  if not isNear(source, coords, Robbery.distance) then return false, "too_far" end
  return true
end

local function alertPolice(source, coords)
  -- for dispatch resources: AddEventHandler("force_transportrobbery:policeAlert", function(source, coords) end)
  TriggerEvent(RESOURCE .. ":policeAlert", source, coords)
  if Config.Police.alert == false then return end
  for _, id in ipairs(policeOnline() or {}) do
    TriggerClientEvent(RESOURCE .. ":client:alert", id, coords)
  end
end

local STAGE_OF = { cut = "follow", loot = "open" }

-- A timed step at the truck starts: "cut" (the back doors) or "loot" (the money)
lib.callback.register(RESOURCE .. ":server:begin", function(source, action)
  local current = runOf(source)
  if not current then return false, "no_run" end
  if expire() then return false, "expired" end
  if current.finishing then return false, "busy" end
  if type(action) ~= "string" or not STAGE_OF[action] or STAGE_OF[action] ~= current.stage then return false, "failed" end
  local ok, why = checkTruck(source, current, action == "cut")
  if not ok then return false, why end
  current.begun = { action = action, at = GetGameTimer() }
  if action == "cut" and not current.alerted then
    current.alerted = true
    alertPolice(source, GetEntityCoords(current.truck))
  end
  return true, action == "cut" and Robbery.cutTime or Robbery.lootTime
end)

--- The step `action` began and lasted long enough
local function begunLongEnough(current, action, duration)
  local begun = current.begun
  return begun ~= nil and begun.action == action and GetGameTimer() - begun.at >= duration - FINISH_EARLY_MS
end

-- The back doors are cut open
lib.callback.register(RESOURCE .. ":server:complete", function(source, action)
  local current = runOf(source)
  if not current then return false, "no_run" end
  if expire() then return false, "expired" end
  if action ~= "cut" or current.stage ~= "follow" then return false, "failed" end
  if not begunLongEnough(current, "cut", Robbery.cutTime) then return false, "too_fast" end
  local ok, why = checkTruck(source, current, false)
  if not ok then return false, why end
  current.stage = "open"
  current.begun = nil
  return true
end)

-- The money is taken: pays the reward once and ends the robbery
lib.callback.register(RESOURCE .. ":server:finish", function(source)
  local current = runOf(source)
  if not current then return false, "no_run" end
  if current.finishing then return false, "busy" end
  if expire() then return false, "expired" end
  -- The character changed (logout / multichar) since the robbery started: it belonged to the old one
  if identifierOf(source) ~= current.identifier then
    endRun(current, "character changed")
    return false, "no_run"
  end
  if current.stage ~= "open" then return false, "failed" end
  if not begunLongEnough(current, "loot", Robbery.lootTime) then return false, "too_fast" end
  local ok, why = checkTruck(source, current, false)
  if not ok then return false, why end

  local reward = Robbery.reward
  local amount = math.random(reward.min, reward.max)
  -- Money and inventory exports may yield: a second finish (or a cancel) must not run while this one pays
  current.finishing = true
  local okPay, paid = pcall(AddMoney, source, reward.account, amount)
  current.finishing = nil
  if not okPay or not paid then
    Log("error", ("Paying $%s (%s) to %s failed%s"):format(amount, reward.account, tostring(GetPlayerName(source)),
      okPay and "" or (": " .. tostring(paid))))
    current.begun = nil
    return false, "payment_failed"
  end

  endRun(current, "paid", true)
  Debug("info", "%s robbed the truck for $%s (%s)", tostring(GetPlayerName(source)), amount, reward.account)
  TriggerEvent(RESOURCE .. ":robberyFinished", source, amount, reward.account)
  return true, amount
end)

-- The player called the robbery off, left the area, died or lost the truck
RegisterNetEvent(RESOURCE .. ":server:cancel", function()
  local src = source
  local current = runOf(src)
  -- A payout in progress decides the robbery; it ends the robbery itself
  if not current or current.finishing then return end
  endRun(current, "cancelled")
end)

AddEventHandler("playerDropped", function()
  local src = source
  endRun(runOf(src), "player left")
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= RESOURCE then return end
  endRun(run, "resource stopped")
end)

--- Ends the robbery when its player logged out or switched character (multichar) without leaving the server:
--- otherwise the robbery would block everyone else until Config.MaxDuration.
local function checkCharacter()
  local current = run
  if not current or current.finishing or identifierOf(current.source) == current.identifier then return end
  endRun(current, "character changed")
  TriggerClientEvent(RESOURCE .. ":client:ended", current.source, "character")
end

-- Ends a robbery that ran past Config.MaxDuration or whose character is gone
CreateThread(function()
  while true do
    Wait(5000)
    if not expire() then checkCharacter() end
  end
end)

--- The player running the robbery and its stage, or nil
exports("GetActiveRobbery", function()
  if not run then return nil end
  return run.source, run.stage
end)

prepareConfig()
