ESX              = nil
local PlayerData = {}
local missionIsStarted = false

Citizen.CreateThread(function()
	while ESX == nil do
		TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
		Citizen.Wait(0)
	end
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(player)
  PlayerData = player   
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
  PlayerData.job = job
end)

Citizen.CreateThread(function()
	while true do
		local sleepThread = 500
		
		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)

		local dist1 = #(pCoords - Config.PedPos)

		if dist1 < 50 then
			sleepThread = 4
			RequestModel(Config.PedHash) while not HasModelLoaded(Config.PedHash) do Wait(7) end
			if not DoesEntityExist(bertoPed) then
				bertoPed = CreatePed(4, Config.PedHash, Config.PedPos, Config.PedPosH, false, true)
				FreezeEntityPosition(bertoPed, true)
				SetBlockingOfNonTemporaryEvents(bertoPed, true)
				SetEntityInvincible(bertoPed, true)
				ESX.LoadAnimDict("mini@strip_club@idles@bouncer@base")
                TaskPlayAnim(bertoPed, 'mini@strip_club@idles@bouncer@base', 'base', 1.0, -1.0, -1, 69, 0, 0, 0, 0)
			end
		end

		if dist1 >= 1.5 and dist1 <= 6 then
			if not missionIsStarted then
				DrawText3Ds(Config.PedPos.x, Config.PedPos.y, Config.PedPos.z+2, '[~r~E~w~] Berto', 0.4)
			end
		end

		if dist1 < 2.0 then
			if not missionIsStarted then
				DrawText3Ds(Config.PedPos.x, Config.PedPos.y, Config.PedPos.z+2, '[~g~E~w~] Berto', 0.4)
				if IsControlJustPressed(1, 38) then
					AcceptJob()
				end
			end
		end

		Wait(sleepThread)
	end
end)

function AcceptJob()
    ESX.UI.Menu.CloseAll()

    ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'weamenu',
    {
        title = 'Do you want to help Berto?',
        align = 'center',
        elements = {
            {label = 'Yes', option = 'ja'},
            {label = 'No', option = 'nej'},
        }
    },

    function(data, menu)
        local chosen = data.current.option

        if chosen == 'ja' then
			ESX.TriggerServerCallback('force_robberyrobberyCops', function(CopsConnected)
				if CopsConnected >= Config.RequiredCopsRob then
					missionIsStarted = true
					TriggerEvent('force_transportrobberyMainDialog')
					TriggerEvent('force_transportrobberyMainMission')
					menu.close()
				else
					ESX.ShowNotification('There are too few police officers inside to do this!')
					menu.close()
				end
			end)
		elseif chosen == 'nej' then
            ESX.ShowNotification('You are welcome back!')
            menu.close()
        end
    end,
    function(data, menu)
        menu.close()
    end)
end

RegisterNetEvent('force_transportrobberyMainDialog')
AddEventHandler('force_transportrobberyMainDialog', function()
	ESX.ShowNotification('Servant, you will help me and rob a cash-in-transit!')
	Wait(2000)
	ESX.ShowNotification('Go to your specified position and then wait and you will receive further information!')
end)

RegisterNetEvent('force_transportrobberyMainMission')
AddEventHandler('force_transportrobberyMainMission', function()
	while missionIsStarted do
		Wait(5)
		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)

		for _,mainPoint in pairs(Config.MainPoint) do
			for _,mainVehicle in pairs(Config.MainCarPoint) do
				local mainVehicleCoords = GetEntityCoords(mainVehicle.vehicleName)
				local dist2 = #(mainVehicleCoords - Config.VehicleDestination)

				if dist2 <= 10 then
					mainVehicleHasArrived = true
					if mainVehicleHasArrived and not shownNotifications then
						ESX.ShowNotification('Wait until the people have jumped out of the vehicle and open the back doors.')
						Wait(2000)
						ESX.ShowNotification('Then take the money from there.')
						RemoveBlip(mainVehicle.blipName)
						TaskLeaveVehicle(VehiclePed2, mainVehicle.vehicleName, 1)
						TaskLeaveVehicle(VehiclePed, mainVehicle.vehicleName, 1)
						Wait(2000)
						SetPedArmour(VehiclePed2, 100)
						SetPedArmour(VehiclePed, 100)
						SetPedCombatAttributes(VehiclePed2, 46, 1)
						SetPedCombatAttributes(VehiclePed, 46, 1)
						GiveWeaponToPed(VehiclePed, 'WEAPON_SMG', 1, false, true)
						GiveWeaponToPed(VehiclePed2, 'WEAPON_SMG', 1, false, true)
						SetPedCurrentWeaponVisible(VehiclePed2, true, false, 0, 0)
						SetPedCurrentWeaponVisible(VehiclePed, true, false, 0, 0)
						SetPedSeeingRange(VehiclePed, 100000000.0)
						SetPedSeeingRange(VehiclePed2, 100000000.0)
						SetPedHearingRange(VehiclePed2, 100000000.0)
						SetPedHearingRange(VehiclePed, 100000000.0)
						AddRelationshipGroup('hostilePed')
						SetPedRelationshipGroupHash(VehiclePed, GetHashKey("hostilePed"))
						SetPedRelationshipGroupHash(VehiclePed2, GetHashKey("hostilePed"))
						SetPedRelationshipGroupHash(player, GetHashKey("Player"))
						SetRelationshipBetweenGroups(0, GetHashKey("hostilePed"), GetHashKey("hostilePed"))
						SetRelationshipBetweenGroups(5, GetHashKey("hostilePed"), GetHashKey("Player"))
						SetRelationshipBetweenGroups(5, GetHashKey("Player"), GetHashKey("hostilePed"))
						shownNotifications = true
					end

					if GetDistanceBetweenCoords(pCoords, mainVehicleCoords) < 5 and not hasOpenedDoors then
						DrawText3Ds(mainVehicleCoords.x, mainVehicleCoords.y, mainVehicleCoords.z+1, '[~g~E~w~] Backlucka', 0.4)
						if IsControlJustPressed(1, 38) then
							TriggerServerEvent('force_transportrobberyAlertPolice')
							exports["btrp_progressbar"]:StartDelayedFunction({
								["text"] = "Cuts up the doors...",
								["delay"] = 60000
							})
							TaskStartScenarioInPlace(player, "world_human_welding", 0, true)
							FreezeEntityPosition(player, true)
							Wait(60000)
							FreezeEntityPosition(player, false)
							SetVehicleDoorOpen(mainVehicle.vehicleName, 2, false, true)
							Wait(250)
							SetVehicleDoorOpen(mainVehicle.vehicleName, 3, false, true)
							ClearPedTasksImmediately(player)
							hasOpenedDoors = true
						end
					end
					if GetDistanceBetweenCoords(pCoords, mainVehicleCoords) < 5 and not hasTakenMoney and hasOpenedDoors then
						DrawText3Ds(mainVehicleCoords.x, mainVehicleCoords.y, mainVehicleCoords.z+1, '[~g~E~w~] Take money', 0.4)
						if IsControlJustPressed(1, 38) then
							exports["btrp_progressbar"]:StartDelayedFunction({
								["text"] = "Takes money...",
								["delay"] = 60000
							})
							ESX.LoadAnimDict("mini@repair")
							TaskPlayAnim(player, 'mini@repair', 'fixing_a_ped', 1.0, -1.0, -1, 69, 0, 0, 0, 0)
							FreezeEntityPosition(player, true)
							Wait(60000)
							FreezeEntityPosition(player, false)
							ClearPedTasksImmediately(player)
							TriggerServerEvent('force_transportrobberyReward')
							hasTakenMoney = true
							Wait(500)
							missionIsStarted = false
							hasTakenMoney = false
							hasArrivedAtMainPoint = false
							hasPressed = false
							mainVehicleHasArrived = false
							hasOpenedDoors = false
							shownNotifications = false
							mainPoint.hasSpawned = false
							hasWaited = false
							mainVehicle.blipHasSpawned = false
							RemoveBlip(mainVehicle.blipName)
							RemoveBlip(mainPoint.blip)
						end
					end
				end

				if not mainPoint.hasSpawned then
					mainPoint.blip = AddBlipForCoord(mainPoint.x, mainPoint.y, mainPoint.z)
					BlipDetails(mainPoint.blip, 'Position', 46, true)
					mainPoint.hasSpawned = true
				end

				if GetDistanceBetweenCoords(pCoords, mainPoint.x, mainPoint.y, mainPoint.z) < 20 and not hasArrivedAtMainPoint then
					if not hasPressed then
						ESX.ShowHelpNotification('~INPUT_PICKUP~ Get started')
						if IsControlJustPressed(1, 38) then
							hasArrivedAtMainPoint = true
							hasPressed = true
							RemoveBlip(mainPoint.blip)
							Wait(30000)
							hasWaited = true
							if hasWaited then
								ESX.ShowNotification('The car is now deployed on as a GPS point on your GPS!')
								Wait(2000)
								ESX.ShowNotification('Wait until the car has passed you and then drive after it!')
								Wait(2000)
								ESX.ShowNotification('Make sure and keep a good distance behind it!')

								RequestModel(mainVehicle.vehicleHash) while not HasModelLoaded(mainVehicle.vehicleHash) do Wait(7) end
								mainVehicle.vehicleName = CreateVehicle(mainVehicle.vehicleHash, mainVehicle.x, mainVehicle.y, mainVehicle.z, mainVehicle.h, true, true)
								if not DoesEntityExist(VehiclePed) then
									RequestModel(Config.VehiclePedHash) while not HasModelLoaded(Config.VehiclePedHash) do Wait(7) end
									VehiclePed = CreatePed(4, Config.VehiclePedHash, Config.VehiclePedPos, false, true)
									SetPedIntoVehicle(VehiclePed, mainVehicle.vehicleName, 0)
								end
								if not DoesEntityExist(VehiclePed2) then
									RequestModel(Config.VehiclePedHash2) while not HasModelLoaded(Config.VehiclePedHash2) do Wait(7) end
									VehiclePed2 = CreatePed(4, Config.VehiclePedHash2, Config.VehiclePedPos2, false, true)
									SetPedIntoVehicle(VehiclePed2, mainVehicle.vehicleName, -1)
								end
								if not mainVehicle.blipHasSpawned then
									mainVehicle.blipName = AddBlipForEntity(mainVehicle.vehicleName)
									BlipDetails(mainVehicle.blipName, 'Vehicle', 46, true)
									mainVehicle.blipHasSpawned = true
								end

								if not mainVehicleHasArrived then
									TaskVehicleDriveToCoord(VehiclePed2, mainVehicle.vehicleName, Config.VehicleDestination, 30.00, 1, mainVehicle.vehicleName, 787391, 3.0, true)
								end
							end
						end
					end
				elseif hasArrivedAtMainPoint == true and GetDistanceBetweenCoords(pCoords, mainPoint.x, mainPoint.y, mainPoint.z) > 20 and not hasWaited then
					ESX.ShowNotification('You have gone outside the radius that you have been assigned.')
					Wait(2000)
					ESX.ShowNotification('With this, you have failed the mission.')
					mainPoint.hasSpawned = false
					hasArrivedAtMainPoint = false
					hasPressed = false
					missionIsStarted = false
					hasWaited = false
				end
			end
		end
	end
end)

RegisterNetEvent('force_transportrobberySetBlip')
AddEventHandler('force_transportrobberySetBlip', function()
    blipRobbery = AddBlipForCoord(Config.VehicleDestination)
    SetBlipSprite(blipRobbery , 161)
    SetBlipScale(blipRobbery , 2.0)
    SetBlipColour(blipRobbery, 3)
    PulseBlip(blipRobbery)
end)