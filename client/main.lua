local RESOURCE = GetCurrentResourceName()
local CALLBACK_TIMEOUT = 15000
local PED_SPAWN_DISTANCE = 50.0
local SLOW_TICK = 250
local KEY_E = 38
local BLIP_COLOUR = 46
local PROMPT = "prompt"
-- How long the truck may be out of reach before the robbery is off
local TRUCK_LOST_MS = 10000
-- How long a freshly created entity may take to get a network id
local NETWORK_TIMEOUT = 3000
local GUARD_GROUP = "FORCE_TRANSPORT_GUARDS"
local CUT_SCENARIO = "WORLD_HUMAN_WELDING"
local LOOT_DICT, LOOT_CLIP = "mini@repair", "fixing_a_ped"
-- Back doors of the truck
local DOORS = { 2, 3 }

local boss = {}           -- ped, point, blip, near
local requesting = false  -- dialog / server request at the boss in progress
local robbery = nil       -- the running robbery, see beginRobbery()
local alerts = {}         -- police alarm blips
local lastPress = 0

local function notify(message, notifyType)
  lib.notify({ description = message, type = notifyType or "inform" })
end

local function playerLoaded()
  local ok, loaded = pcall(IsPlayerLoaded)
  return ok and loaded == true
end

--- lib.callback with its own timeout (ox_lib waits 5 minutes and throws). Returns nil when the server didn't answer.
local function awaitServer(name, ...)
  local p = promise.new()
  local settled = false
  local function settle(value)
    if settled then return end
    settled = true
    p:resolve(value)
  end
  lib.callback(name, false, function(...)
    settle({ n = select("#", ...), ... })
  end, ...)
  SetTimeout(CALLBACK_TIMEOUT, function() settle(false) end)
  local result = Citizen.Await(p)
  if not result then return nil end
  return table.unpack(result, 1, result.n)
end

--- Notification for a reason the server returned
local function notifyReason(reason, extra)
  if reason == "boss_busy" then return notify(locale("boss_busy", Robbery.boss.name), "error") end
  if reason == "cooldown" then return notify(locale("cooldown", Robbery.boss.name, tonumber(extra) or 1), "error") end
  local key = type(reason) == "string" and reason or "failed"
  local text = locale(key)
  notify(text == key and locale("failed") or text, "error")
end

local function drawText2D(text, y)
  SetTextFont(4)
  SetTextScale(0.5, 0.5)
  SetTextColour(255, 255, 255, 255)
  SetTextEdge(2, 0, 0, 0, 150)
  SetTextOutline()
  SetTextCentre(true)
  BeginTextCommandDisplayText("STRING")
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(0.5, y)
end

local function setBlipName(blip, text)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandSetBlipName(blip)
end

local function removeBlip(blip)
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function deleteEntity(entity)
  if entity and entity ~= 0 and DoesEntityExist(entity) then
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
  end
end

--- Loads a model (pcall: lib.requestModel throws on a bad model or timeout). Returns the hash or nil.
local function loadModel(model)
  local hash = type(model) == "number" and model or joaat(model)
  local ok, err = pcall(lib.requestModel, hash, 10000)
  if not ok then
    Debug("error", "Model '%s' could not be loaded: %s", tostring(model), tostring(err))
    return nil
  end
  return hash
end

local function playerCoords()
  return GetEntityCoords(PlayerPedId())
end

--- Asks for control of a networked entity: ownership moves to whichever player is closest, and tasks or doors set
--- by a client that doesn't own the entity are ignored. Returns true once this client has control.
local function requestControl(entity, timeout)
  if NetworkHasControlOfEntity(entity) then return true end
  local deadline = GetGameTimer() + (timeout or 1000)
  repeat
    NetworkRequestControlOfEntity(entity)
    Wait(0)
  until NetworkHasControlOfEntity(entity) or GetGameTimer() >= deadline or not DoesEntityExist(entity)
  return NetworkHasControlOfEntity(entity)
end

--- The local handle of an entity by net id, nil when it doesn't exist here
local function fromNet(netId)
  if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
  local entity = NetToEnt(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  return entity
end

-------------------------------------------------------------------------------------------------------------------
-- Robbery
-------------------------------------------------------------------------------------------------------------------

--- Removes everything the robbery put in the world. Safe to call more than once.
--- @param keepEntities boolean leave the truck and guards to the game (after the payout)
local function endRobbery(keepEntities)
  local current = robbery
  if not current then return end
  robbery = nil
  if current.busy then pcall(lib.cancelProgress) end
  for _, blip in pairs(current.blips) do removeBlip(blip) end
  Interact.hideText(PROMPT)
  local entities = { fromNet(current.truckNet) or current.truck or false }
  for index = 1, #Robbery.truck.guards do
    entities[#entities + 1] = fromNet(current.guardNetOf[index]) or current.guards[index] or false
  end
  for _, entity in ipairs(entities) do
    if entity and keepEntities then
      if DoesEntityExist(entity) then SetEntityAsNoLongerNeeded(entity) end
    elseif entity then
      deleteEntity(entity)
    end
  end
end

--- Calls the robbery off on the server and here, and tells the player why
local function cancelRobbery(reasonKey)
  if not robbery then return end
  TriggerServerEvent(RESOURCE .. ":server:cancel")
  endRobbery(false)
  if reasonKey then notify(locale(reasonKey), "error") end
end

local function truckEntity(current)
  return fromNet(current.truckNet)
end

--- Adds, moves and removes the robbery's blips. wanted[key] = { coords = vector3 | entity = handle, label, route }
local function setBlips(current, wanted)
  for key, blip in pairs(current.blips) do
    local want = wanted[key]
    if not want or not DoesBlipExist(blip) or (want.entity and current.blipEntity[key] ~= want.entity)
        or (want.route or false) ~= current.blipRoute[key] then
      removeBlip(blip)
      current.blips[key], current.blipEntity[key], current.blipRoute[key] = nil, nil, nil
    end
  end
  for key, want in pairs(wanted) do
    if not current.blips[key] then
      local blip
      if want.entity then
        blip = AddBlipForEntity(want.entity)
        current.blipEntity[key] = want.entity
      else
        blip = AddBlipForCoord(want.coords.x, want.coords.y, want.coords.z)
      end
      SetBlipColour(blip, BLIP_COLOUR)
      setBlipName(blip, want.label)
      if want.route then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, BLIP_COLOUR)
      end
      current.blips[key] = blip
      current.blipRoute[key] = want.route or false
    end
  end
end

--- Creates a networked entity and waits for its network id. Returns the handle and net id, or nil.
local function networked(entity)
  if not entity or entity == 0 then return nil end
  local deadline = GetGameTimer() + NETWORK_TIMEOUT
  while not NetworkGetEntityIsNetworked(entity) and GetGameTimer() < deadline do Wait(0) end
  if not NetworkGetEntityIsNetworked(entity) then
    deleteEntity(entity)
    return nil
  end
  SetEntityAsMissionEntity(entity, true, true)
  return entity, NetworkGetNetworkIdFromEntity(entity)
end

--- Spawns the truck and its guards (networked: this client owns them and drives the guards' AI), then tells the
--- server. The robbery is called off when anything fails.
local function spawnTruck(current)
  local def = Robbery.truck
  local truckHash = loadModel(def.model)
  local guardHashes = {}
  for index, guard in ipairs(def.guards) do guardHashes[index] = loadModel(guard.model) end
  if robbery ~= current then return end
  if not truckHash then return cancelRobbery("truck_failed") end

  local c = def.position
  local truck, truckNet = networked(CreateVehicle(truckHash, c.x, c.y, c.z, def.heading, true, true))
  SetModelAsNoLongerNeeded(truckHash)
  if robbery ~= current then return deleteEntity(truck) end
  if not truck then
    Log("error", "The truck could not be networked. Is sv_entityLockdown blocking client-created entities?")
    return cancelRobbery("truck_failed")
  end
  current.truck, current.truckNet = truck, truckNet
  -- the truck spawns far from the player: without its own collision it can drop through the map there
  SetEntityLoadCollisionFlag(truck, true)
  SetVehicleOnGroundProperly(truck)

  local driver
  for index, guard in ipairs(def.guards) do
    local hash = guardHashes[index]
    if hash then
      local ped, netId = networked(CreatePed(4, hash, c.x, c.y, c.z + 1.0, def.heading, true, true))
      SetModelAsNoLongerNeeded(hash)
      if robbery ~= current then return deleteEntity(ped) end
      if ped then
        SetPedIntoVehicle(ped, truck, guard.seat)
        -- keeps the guards on their route instead of reacting to traffic and the player behind them
        SetBlockingOfNonTemporaryEvents(ped, true)
        current.guards[index], current.guardNetOf[index] = ped, netId
        current.guardNets[#current.guardNets + 1] = netId
        if guard.seat == -1 then driver = ped end
      end
    end
  end
  if driver then
    local d = def.destination
    TaskVehicleDriveToCoord(driver, truck, d.x, d.y, d.z, def.speed, 1, truckHash, def.drivingStyle, 3.0, true)
  else
    Log("error", "The truck has no driver: add a guard with seat = -1 to Config.Truck.guards")
  end

  local ok, reason = awaitServer(RESOURCE .. ":server:spawned", truckNet, current.guardNets)
  if robbery ~= current then return end
  if not ok then
    if ok == nil then return cancelRobbery("server_no_response") end
    notifyReason(reason)
    return cancelRobbery()
  end
  current.stage = "follow"
  notify(locale("truck_marked"))
  Wait(2000)
  if robbery ~= current then return end
  notify(locale("truck_follow"))
  Wait(2000)
  if robbery ~= current then return end
  notify(locale("truck_distance"))
end

--- The truck reached its destination: the guards get out and fight
local function arrive(current, truck)
  current.arrived = true
  local def = Robbery.truck
  AddRelationshipGroup(GUARD_GROUP)
  local group = joaat(GUARD_GROUP)
  SetRelationshipBetweenGroups(0, group, group)
  SetRelationshipBetweenGroups(5, group, `PLAYER`)
  SetRelationshipBetweenGroups(5, `PLAYER`, group)
  local guards = {}
  for _, netId in ipairs(current.guardNets) do
    local ped = fromNet(netId)
    if ped and not IsEntityDead(ped) then
      requestControl(ped)
      if robbery ~= current then return end
      guards[#guards + 1] = ped
      SetBlockingOfNonTemporaryEvents(ped, false)
      TaskLeaveVehicle(ped, truck, 0)
      SetPedArmour(ped, def.armour)
      if def.weapon then
        GiveWeaponToPed(ped, joaat(def.weapon), 250, false, true)
        SetCurrentPedWeapon(ped, joaat(def.weapon), true)
      end
      SetPedCombatAttributes(ped, 46, true)
      SetPedSeeingRange(ped, 100.0)
      SetPedHearingRange(ped, 100.0)
      SetPedDropsWeaponsWhenDead(ped, false)
      SetPedRelationshipGroupHash(ped, group)
    end
  end
  notify(locale("arrived_guards"))
  Wait(2000)
  if robbery ~= current then return end
  for _, ped in ipairs(guards) do
    -- they fight whoever of the player group is around (the robber may still be on the way)
    if DoesEntityExist(ped) and not IsEntityDead(ped) and requestControl(ped) then
      TaskCombatHatedTargetsAroundPed(ped, 100.0, 0)
    end
  end
  notify(locale("arrived_money"))
end

--- A timed step at the truck: begin on the server, progress bar, then complete / finish on the server
local function runStep(current, action)
  local ok, result = awaitServer(RESOURCE .. ":server:begin", action)
  if robbery ~= current then return end
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    notifyReason(result)
    if result == "no_run" or result == "expired" or result == "truck_lost" then endRobbery(false) end
    return
  end

  local cut = action == "cut"
  local okBar, finished = pcall(lib.progressBar, {
    duration = tonumber(result) or (cut and Robbery.cutTime or Robbery.lootTime),
    label = locale(cut and "progress_cut" or "progress_loot"),
    useWhileDead = false,
    canCancel = true,
    disable = { move = true, car = true, combat = true },
    anim = cut and { scenario = CUT_SCENARIO } or { dict = LOOT_DICT, clip = LOOT_CLIP, flag = 1 },
  })
  ClearPedTasks(PlayerPedId())
  if robbery ~= current then return end
  if not okBar then Debug("error", "Progress failed: %s", tostring(finished)) return end
  if not finished then return end

  local amount
  if cut then
    ok, result = awaitServer(RESOURCE .. ":server:complete", "cut")
  else
    ok, amount = awaitServer(RESOURCE .. ":server:finish")
    result = amount
  end
  if robbery ~= current then return end
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    notifyReason(result)
    if result == "no_run" or result == "expired" or result == "truck_lost" then endRobbery(false) end
    return
  end

  if cut then
    current.stage = "open"
    local truck = truckEntity(current)
    if truck and requestControl(truck) then
      for _, door in ipairs(DOORS) do SetVehicleDoorOpen(truck, door, false, true) end
    end
  else
    notify(locale("rewarded", tonumber(amount) or 0), "success")
    endRobbery(true)
  end
end

--- The player is at the ambush: the wait for the truck starts
local function startWait(current)
  local ok, result = awaitServer(RESOURCE .. ":server:wait")
  if robbery ~= current then return end
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    notifyReason(result)
    if result == "no_run" or result == "expired" then endRobbery(false) end
    return
  end
  current.stage = "waiting"
  current.waitUntil = GetGameTimer() + (tonumber(result) or Robbery.ambush.wait)
end

local function handleStep(current, action)
  if current.busy then return end
  current.busy = true
  Interact.hideText(PROMPT)
  local ok, err
  if action == "wait" then
    ok, err = pcall(startWait, current)
  else
    ok, err = pcall(runStep, current, action)
  end
  if not ok then Debug("error", "Robbery step '%s' failed: %s", action, tostring(err)) end
  current.busy = false
end

--- Blips, hint, the wait, the truck and the guards (every SLOW_TICK ms)
local function update(current)
  if IsEntityDead(PlayerPedId()) then return cancelRobbery("died") end
  local pos = playerCoords()
  local ambush, def = Robbery.ambush, Robbery.truck
  local wanted = {}
  local stage = current.stage

  if stage == "meet" then
    wanted.ambush = { coords = ambush.coords, label = locale("blip_position"), route = true }
    current.hint = locale("hint_position")
  elseif stage == "waiting" or stage == "spawning" then
    if #(pos - ambush.coords) > ambush.radius then return cancelRobbery("left_area") end
    local left = math.max(0, math.ceil((current.waitUntil - GetGameTimer()) / 1000))
    current.hint = locale("hint_wait", left)
    if stage == "waiting" and left <= 0 then
      current.stage = "spawning"
      CreateThread(function()
        local ok, err = pcall(spawnTruck, current)
        if not ok then
          Log("error", ("Spawning the truck failed: %s"):format(tostring(err)))
          if robbery == current then cancelRobbery("truck_failed") end
        end
      end)
    end
  else
    local truck = truckEntity(current)
    if not truck or IsEntityDead(truck) then
      current.lostSince = current.lostSince or GetGameTimer()
      if (truck and IsEntityDead(truck)) or GetGameTimer() - current.lostSince > TRUCK_LOST_MS then
        return cancelRobbery("truck_lost")
      end
    else
      current.lostSince = nil
      current.truckCoords = GetEntityCoords(truck)
      if not current.arrived and #(current.truckCoords - def.destination) <= def.arriveRadius then
        CreateThread(function() arrive(current, truck) end)
        current.arrived = true
      end
      wanted.truck = { entity = truck, label = locale("blip_truck"), route = not current.arrived }
    end
    if stage == "open" then
      current.hint = locale("hint_loot")
    else
      current.hint = locale(current.arrived and "hint_doors" or "hint_follow")
    end
  end
  setBlips(current, wanted)
end

--- The [E] prompt of the current step, or nil
local function currentPrompt(current, pos)
  local stage = current.stage
  if stage == "meet" then
    if #(pos - Robbery.ambush.coords) <= Robbery.ambush.radius then return "wait", locale("prompt_start") end
    return nil
  end
  if (stage == "follow" and current.arrived) or stage == "open" then
    local coords = current.truckCoords
    -- cutting and looting are done on foot
    if coords and #(pos - coords) <= Robbery.distance and not IsPedInAnyVehicle(PlayerPedId(), false) then
      if stage == "follow" then return "cut", locale("prompt_cut") end
      return "loot", locale("prompt_loot")
    end
  end
  return nil
end

--- The hint and the [E] prompt (every frame while a robbery runs)
local function frame(current)
  if Config.ShowHints ~= false and current.hint then drawText2D(current.hint, 0.93) end
  if current.busy then return Interact.hideText(PROMPT) end
  local action, text = currentPrompt(current, playerCoords())
  if not action then return Interact.hideText(PROMPT) end
  Interact.showText(PROMPT, text)
  if IsControlJustReleased(0, KEY_E) and GetGameTimer() - lastPress > 500 then
    lastPress = GetGameTimer()
    CreateThread(function() handleStep(current, action) end)
  end
end

local function runRobbery(current)
  local nextUpdate = 0
  while robbery == current do
    if GetGameTimer() >= nextUpdate then
      nextUpdate = GetGameTimer() + SLOW_TICK
      local ok, err = pcall(update, current)
      if not ok then Debug("error", "Robbery update failed: %s", tostring(err)) end
    end
    if robbery == current then
      local ok, err = pcall(frame, current)
      if not ok then Debug("error", "Robbery frame failed: %s", tostring(err)) end
    end
    Wait(0)
  end
end

local function beginRobbery()
  local current = {
    stage = "meet",
    blips = {},
    blipEntity = {},
    blipRoute = {},
    guards = {},     -- [guard index] = handle
    guardNetOf = {}, -- [guard index] = net id
    guardNets = {},  -- net ids sent to the server
  }
  robbery = current
  CreateThread(function() runRobbery(current) end)
  CreateThread(function()
    notify(locale("dialog_start"))
    Wait(2000)
    if robbery ~= current then return end
    notify(locale("dialog_position"))
  end)
end

-------------------------------------------------------------------------------------------------------------------
-- Boss
-------------------------------------------------------------------------------------------------------------------

--- The server holds a robbery of this player that this client doesn't know (the answer to the start came after the
--- client stopped waiting for it): pick it up when it's still at the first step, otherwise offer to call it off.
local function resumeRobbery(stage)
  if stage == "meet" then return beginRobbery() end
  local answer = lib.alertDialog({
    header = locale("not_finished_header", Robbery.boss.name),
    content = locale("not_finished_content"),
    centered = true,
    cancel = true,
  })
  if answer == "confirm" and not robbery then
    TriggerServerEvent(RESOURCE .. ":server:cancel")
    notify(locale("cancelled"))
  end
end

local function confirmStart()
  local reward = Robbery.reward
  local answer = lib.alertDialog({
    header = locale("confirm_header", Robbery.boss.name),
    content = locale("confirm_content", Robbery.boss.name, reward.min, reward.max),
    centered = true,
    cancel = true,
  })
  if answer ~= "confirm" then return notify(locale("declined")) end
  if robbery then return notify(locale("busy"), "error") end
  local ok, reason, extra = awaitServer(RESOURCE .. ":server:start")
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    if reason == "busy" and type(extra) == "string" and not robbery then return resumeRobbery(extra) end
    return notifyReason(reason, extra)
  end
  beginRobbery()
end

local function askCancel(current)
  local answer = lib.alertDialog({
    header = locale("not_finished_header", Robbery.boss.name),
    content = locale("not_finished_content"),
    centered = true,
    cancel = true,
  })
  if answer == "confirm" and robbery == current then
    cancelRobbery()
    notify(locale("cancelled"))
  end
end

local function talkToBoss()
  if requesting then return end
  if not IsFrameworkReady() or not playerLoaded() then return notify(locale("not_ready"), "error") end
  local current = robbery
  if current and current.busy then return end
  requesting = true
  local ok, err
  if current then
    ok, err = pcall(askCancel, current)
  else
    ok, err = pcall(confirmStart)
  end
  requesting = false
  if not ok then
    Debug("error", "Talking to the boss failed: %s", tostring(err))
    notify(locale("server_no_response"), "error")
  end
end

local function deleteBoss()
  deleteEntity(boss.ped)
  boss.ped = nil
end

local function spawnBoss()
  if boss.ped and DoesEntityExist(boss.ped) then return end
  local def = Robbery.boss
  local hash = loadModel(def.model)
  if not hash then return end
  -- the player may have walked away while the model loaded
  if not boss.near or (boss.ped and DoesEntityExist(boss.ped)) then
    SetModelAsNoLongerNeeded(hash)
    return
  end
  local c = def.position
  local ped = CreatePed(4, hash, c.x, c.y, c.z, def.heading, false, false)
  SetModelAsNoLongerNeeded(hash)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCanRagdoll(ped, false)
  boss.ped = ped
  if def.anim then
    local ok, err = pcall(lib.requestAnimDict, def.anim.dict, 5000)
    if not ok then return Debug("error", "Boss animation could not be loaded: %s", tostring(err)) end
    if not DoesEntityExist(ped) then return end
    TaskPlayAnim(ped, def.anim.dict, def.anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
    RemoveAnimDict(def.anim.dict)
  end
end

local function setupBoss()
  local def = Robbery.boss
  local c = def.position
  boss.point = lib.points.new({
    coords = c,
    distance = PED_SPAWN_DISTANCE,
    onEnter = function()
      boss.near = true
      CreateThread(spawnBoss)
    end,
    onExit = function()
      boss.near = false
      deleteBoss()
    end,
  })
  Interact.add("boss", {
    coords = vector3(c.x, c.y, c.z + 1.0),
    distance = GetInteractDistance(),
    size = 1.0,
    label = locale("talk_label", def.name),
    icon = "fa-solid fa-comments",
    text = locale("talk_textui", def.name),
    canInteract = function() return not requesting and not (robbery and robbery.busy) and playerLoaded() end,
    onSelect = function() CreateThread(talkToBoss) end,
  })
  if def.blip then
    boss.blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(boss.blip, tonumber(def.blip.sprite) or 500)
    SetBlipColour(boss.blip, tonumber(def.blip.colour) or 1)
    SetBlipScale(boss.blip, (tonumber(def.blip.scale) or 0.7) + 0.0)
    SetBlipAsShortRange(boss.blip, true)
    setBlipName(boss.blip, type(def.blip.label) == "string" and def.blip.label or def.name)
  end
end

-------------------------------------------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------------------------------------------

-- The server ended the robbery (Config.MaxDuration, or the character logged out)
RegisterNetEvent(RESOURCE .. ":client:ended", function(reason)
  if not robbery then return end
  endRobbery(false)
  notify(locale(reason == "expired" and "expired" or "cancelled"), "error")
end)

-- Police alarm: only sent by the server to the police on duty
RegisterNetEvent(RESOURCE .. ":client:alert", function(coords)
  if type(coords) ~= "vector3" and type(coords) ~= "table" then return end
  local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
  if not x or not y or not z then return end
  local settings = type(Config.Police.blip) == "table" and Config.Police.blip or {}
  notify(locale("police_alert"), "warning")
  local blip = AddBlipForCoord(x, y, z)
  SetBlipSprite(blip, tonumber(settings.sprite) or 161)
  SetBlipColour(blip, tonumber(settings.colour) or 3)
  SetBlipScale(blip, (tonumber(settings.scale) or 2.0) + 0.0)
  setBlipName(blip, locale("blip_alert"))
  PulseBlip(blip)
  alerts[#alerts + 1] = blip
  SetTimeout(math.max(10, tonumber(settings.duration) or 300) * 1000, function()
    removeBlip(blip)
    for index, value in ipairs(alerts) do
      if value == blip then table.remove(alerts, index) break end
    end
  end)
end)

OnEnvironmentReady(function()
  if not Robbery.valid then return end
  local ok, err = pcall(setupBoss)
  if not ok then Log("error", ("The boss could not be set up: %s"):format(tostring(err))) end
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= RESOURCE then return end
  if requesting then pcall(lib.closeAlertDialog) end
  endRobbery(false)
  deleteBoss()
  removeBlip(boss.blip)
  if boss.point then boss.point:remove() end
  for _, blip in ipairs(alerts) do removeBlip(blip) end
  Interact.removeAll()
end)
