-- Non-weapon items. kind: "ammo" | "consumable" | "armor" | "utility" | "upgrade" | "weapon".
-- Weapons are items too ("weapon:<id>"), with stats in WeaponDefinitions.
local Items = {}

Items.Rarities = { "common", "uncommon", "rare", "epic", "legendary" }
Items.RarityColor = {
	common = Color3.fromRGB(190, 195, 205),
	uncommon = Color3.fromRGB(90, 210, 120),
	rare = Color3.fromRGB(70, 150, 255),
	epic = Color3.fromRGB(185, 95, 255),
	legendary = Color3.fromRGB(255, 170, 40),
}

Items.List = {
	-- Ammunition (amount = rounds per pickup)
	ammo_light = { kind = "ammo", ammo = "light", amount = 45, name = "Light Rounds", desc = "Pistol and SMG ammunition." },
	ammo_medium = { kind = "ammo", ammo = "medium", amount = 45, name = "Medium Rounds", desc = "Rifle ammunition." },
	ammo_heavy = { kind = "ammo", ammo = "heavy", amount = 10, name = "Heavy Rounds", desc = "Precision rifle ammunition." },
	ammo_shells = { kind = "ammo", ammo = "shells", amount = 12, name = "Shells", desc = "Shotgun ammunition." },
	ammo_energy = { kind = "ammo", ammo = "energy", amount = 16, name = "Energy Cells", desc = "Helios and Arc Thrower charge." },

	-- Consumables (use time in seconds; interrupted by taking a shot? no: kept simple, just a delay)
	medkit = { kind = "consumable", name = "Trauma Kit", desc = "Restores 60 health over a 3 s application.", heal = 60, useTime = 3 },
	stim = { kind = "consumable", name = "Med Stim", desc = "Restores 25 health quickly.", heal = 25, useTime = 1 },
	o2canister = { kind = "consumable", name = "Oxygen Canister", desc = "Restores 50 oxygen.", oxygen = 50, useTime = 1.2 },
	shieldcell = { kind = "consumable", name = "Shield Cell", desc = "Restores 25 suit shielding.", armor = 25, useTime = 1.8 },

	-- Armour: picking up sets the suit's max shield tier
	armor_light = { kind = "armor", name = "Light Suit Plating", desc = "Shield capacity 50.", armorMax = 50 },
	armor_heavy = { kind = "armor", name = "Reinforced Plating", desc = "Shield capacity 75.", armorMax = 75 },
	armor_elite = { kind = "armor", name = "Aegis Plating", desc = "Shield capacity 100.", armorMax = 100 },

	-- Utility (G key)
	grenade = { kind = "utility", name = "Pulse Charge", desc = "Thrown charge; detonates after a short fuse.", stack = "grenade" },
	tether_pack = { kind = "utility", name = "Tether Spool", desc = "+2 tether charges.", tether = 2 },

	-- Movement / suit upgrades (permanent for the match)
	boost_cell = { kind = "upgrade", name = "Boost Cell", desc = "+30% boost energy and faster recharge.", boostMax = 1.3, boostRegen = 1.25 },
	o2_recycler = { kind = "upgrade", name = "O2 Recycler", desc = "Oxygen use outside pressurised areas -35%.", o2Efficiency = 0.65 },
	thruster_tune = { kind = "upgrade", name = "Thruster Tune", desc = "+8% cruise speed.", speed = 1.08 },
}

-- Items that take the backpack consumable stack limit (Config.Inventory.ConsumableStack)
Items.Consumables = { "medkit", "stim", "o2canister", "shieldcell", "grenade" }

function Items.Get(id: string)
	if string.sub(id, 1, 7) == "weapon:" then
		return { kind = "weapon", weapon = string.sub(id, 8) }
	end
	return Items.List[id]
end

return Items
