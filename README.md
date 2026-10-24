# force_transportrobbery

Cash-in-transit robbery. Talk to Berto at the docks, wait for the armoured truck at the marked spot, follow it to its destination, deal with the two armed guards, cut open the back doors and take the money. The police get an alarm with a blip when the cutting starts.

Free and open source. Works on ESX Legacy, QBCore and QBox.

## Features

- The 1.x robbery: Berto, the ambush spot, the Stockade with two guards, the drive, the guards fighting at the destination, cutting the doors and taking the money
- Server-side checks: the steps in order, the player's position at every step, the truck's model, owner, spawn point and destination, the guards' models and owner, the minimum drive time and the truck's speed during the drive, the cut and loot durations, the police minimum, one robbery at a time and a cooldown
- The reward (a random amount between a min and a max) is paid once by the server
- Payout as cash, bank or dirty money (ESX black_money, QBox / ox_inventory black_money item, QBCore markedbills)
- Police alarm with a map blip for the police on duty, and a server event for your dispatch resource
- Fails cleanly when the player leaves the ambush, dies, loses the truck or logs out; cancel at Berto, a time limit to reach the ambush, a maximum duration, a personal cooldown after a failed or cancelled robbery, and cleanup when the player leaves or the resource restarts
- ox_target, qb-target or [E] with the ox_lib text UI
- English and Swedish locales

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- OneSync
- ESX Legacy, QBCore or QBox (other frameworks through `server/custom/frameworks/custom.lua`)
- Optional: ox_target or qb-target

The truck and the guards are created by the robber's client as networked entities (their driving AI runs there). If you use `sv_entityLockdown`, it must allow client-created entities.

No database is used.

## Installation

1. Put the folder in your resources as `force_transportrobbery`.
2. Add `ensure force_transportrobbery` to `server.cfg` below `ensure ox_lib`. The order relative to your framework and target resource doesn't matter.
3. Edit `config.lua`: reward and payout account, police minimum, cooldown and the locations.

## Updating from 1.x

A `config.lua` kept from 1.x still works (its locations, models, reward and police minimum are used), but the new options need the 2.0 `config.lua`. The old events, including the reward event any client could call, are gone. See the [documentation](https://docs.forcedevelopments.com/free-resources/force_transportrobbery/introduction#updating-from-1.x).

## Documentation

https://docs.forcedevelopments.com/free-resources/force_transportrobbery/introduction

## License

Apache 2.0, see [LICENSE](LICENSE).
