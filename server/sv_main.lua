ESX = nil
local CopsConnected  = 0

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

RegisterServerEvent('force_transportrobberyReward')
AddEventHandler('force_transportrobberyReward', function()
    local player = ESX.GetPlayerFromId(source)

    local money = math.random(Config.MoneyRewardMin, Config.MoneyReward)

    player.addMoney(money)
    TriggerClientEvent('esx:showNotification', source, 'You got ' .. money .. '$ in reward, get yourself new from here before the cop comes!')
end)

function CountCops()

	local players = ESX.GetPlayers()

	CopsConnected = 0

	for i=1, #players, 1 do
		local xPlayer = ESX.GetPlayerFromId(players[i])
		if xPlayer.job.name == 'police' then
			CopsConnected = CopsConnected + 1
		end
	end

	SetTimeout(120 * 1000, CountCops)
end

CountCops()

ESX.RegisterServerCallback('force_robberyrobberyCops', function(source, cb)
	local xPlayer = ESX.GetPlayerFromId(source)

	cb(CopsConnected)
end)

RegisterServerEvent('force_transportrobberyAlertPolice')
AddEventHandler('force_transportrobberyAlertPolice', function()
    local player = ESX.GetPlayerFromId(source)
    local players = ESX.GetPlayers()

    for i=1, #players, 1 do
        local player = ESX.GetPlayerFromId(players[i])
        if player.job.name == 'police' then
            TriggerClientEvent('esx:showNotification', players[i], 'Alarm: A cash-in-transit robbery is ongoing, check GPS for position!')
            TriggerClientEvent('force_transportrobberySetBlip', players[i])
        end
    end
end)