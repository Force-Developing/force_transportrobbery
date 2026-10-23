Config = {}

-- Prints extra info to the F8 / server console. Setup errors are always printed.
Config.Debug = false

-- "en", "sv" or "auto" (follows the replicated ox:locale convar: setr ox:locale "sv")
Config.Locale = "en"

-- "auto" (detected by the server: qbx_core, es_extended, qb-core), "esx", "qb", "qbx" or "custom"
Config.Framework = "auto"

-- "auto" (ox_target, then qb-target, else [E] + text UI), "ox_target", "qb-target" or "none" ([E] + text UI).
-- Used for the boss. The starting point and the truck always use [E].
Config.Target = "auto"

-- How close (meters) the player has to stand to the boss. The server allows a small margin on top.
Config.InteractDistance = 2.0

-- The man who hands out the robbery
Config.Boss = {
    name = "Berto",
    model = "csb_ortega",
    coords = vec4(557.14, -2961.39, 5.06, 0.0),
    anim = { dict = "mini@strip_club@idles@bouncer@base", clip = "base" }, -- false for none
    blip = false, -- { sprite = 500, colour = 1, scale = 0.7 } to show him on the map
}

-- Police online needed to start a robbery, and the alarm they get when the doors are cut open
Config.Police = {
    jobs = { "police", "sheriff" },
    minimum = 1,       -- 0 = no requirement
    onlyOnDuty = true, -- QBCore / QBox duty, ESX job.onDuty where your ESX version has it
    alert = true,      -- false: no built-in alarm (hook your dispatch on the server event force_transportrobbery:policeAlert)
    blip = { sprite = 161, colour = 3, scale = 2.0, duration = 300 }, -- duration in seconds
}

-- Minutes before anyone can start a new robbery once a robbery where the police were alerted has ended. 0 = none.
Config.Cooldown = 30

-- Minutes a robbery may take. After that it is called off and the truck and guards are removed.
Config.MaxDuration = 30

-- Draw what to do next at the bottom of the screen during a robbery
Config.ShowHints = true

-- Where the player waits for the truck. Leaving the radius before the truck shows up fails the robbery.
Config.Ambush = {
    coords = vec3(1616.66, 1201.58, 85.06),
    radius = 20.0,
    wait = 30, -- seconds
}

-- The cash-in-transit truck. It spawns at coords and its driver takes it to destination.
Config.Truck = {
    model = "stockade",
    coords = vec4(1746.47, 1936.50, 72.22, 170.0),
    destination = vec3(697.09, 606.43, 128.91),
    arriveRadius = 10.0, -- the truck counts as arrived this close to the destination
    speed = 30.0,        -- driving speed (m/s)
    drivingStyle = 787391,
    -- seat -1 = driver, 0 = front passenger. They get out and fight once the truck has arrived.
    guards = {
        { model = "cs_siemonyetarian", seat = -1 },
        { model = "cs_solomon", seat = 0 },
    },
    weapon = "WEAPON_SMG",
    armour = 100,
}

-- The robbery at the destination
Config.Robbery = {
    distance = 5.0, -- how close to the truck the player has to stand
    cutTime = 60,   -- seconds to cut open the back doors (the police are alerted when it starts)
    lootTime = 60,  -- seconds to take the money
}

-- Paid by the server once the money is taken, a random amount between min and max.
-- account = "cash", "bank" or "dirty" (ESX black_money; QBox / ox_inventory black_money item; QBCore markedbills)
Config.Reward = {
    min = 100000,
    max = 150000,
    account = "cash",
}
