-- Loot rolling. Pure logic (no instances) so it can be unit-tested outside Roblox.
-- rng is a Roblox `Random` (or anything with :NextNumber() and :NextInteger(a, b)).
local Shared = script.Parent
local Weapons = require(Shared.WeaponDefinitions)
local Items = require(Shared.ItemDefinitions)

local Loot = {}

-- Rarity weights by container tier. High tiers improve odds; legendary stays rare everywhere.
Loot.RarityWeights = {
	low = { common = 60, uncommon = 28, rare = 10, epic = 2, legendary = 0 },
	mid = { common = 44, uncommon = 32, rare = 17, epic = 6, legendary = 1 },
	high = { common = 25, uncommon = 33, rare = 26, epic = 12, legendary = 4 },
}

-- Category weights by tier.
Loot.CategoryWeights = {
	low = { weapon = 18, ammo = 34, consumable = 30, armor = 8, utility = 7, upgrade = 3 },
	mid = { weapon = 26, ammo = 26, consumable = 24, armor = 11, utility = 8, upgrade = 5 },
	high = { weapon = 34, ammo = 18, consumable = 18, armor = 14, utility = 8, upgrade = 8 },
}

-- Weapon pools per rarity: strong weapons appear mainly at higher rarity.
Loot.WeaponWeights = {
	pistol = 20, smg = 16, assault = 14, burst = 11, shotgun = 13, arc = 10, precision = 7, helios = 4,
}

Loot.ConsumableWeights = { stim = 34, medkit = 18, o2canister = 30, shieldcell = 18 }
Loot.UtilityWeights = { grenade = 60, tether_pack = 40 }
Loot.UpgradeWeights = { boost_cell = 40, o2_recycler = 30, thruster_tune = 30 }
Loot.ArmorByRarity = {
	common = "armor_light", uncommon = "armor_light", rare = "armor_heavy", epic = "armor_heavy", legendary = "armor_elite",
}

local function pick(rng, weights: { [string]: number }, order: { string }?): string
	local keys = order
	if not keys then
		keys = {}
		for k in weights do table.insert(keys, k) end
		table.sort(keys) -- deterministic order for a given seed
	end
	local total = 0
	for _, k in keys do total += weights[k] or 0 end
	local r = rng:NextNumber() * total
	for _, k in keys do
		r -= weights[k] or 0
		if r < 0 then return k end
	end
	return keys[#keys]
end
Loot.Pick = pick

function Loot.RollRarity(rng, tier: string): string
	return pick(rng, Loot.RarityWeights[tier] or Loot.RarityWeights.low, Items.Rarities)
end

-- Ammo matching a weapon, used so a weapon drop is usable straight away.
local function ammoItemFor(weaponId: string): string
	return "ammo_" .. Weapons.List[weaponId].ammo
end
Loot.AmmoItemFor = ammoItemFor

-- Returns one loot entry: { id = string, rarity = string, amount = number }
function Loot.RollItem(rng, tier: string)
	local category = pick(rng, Loot.CategoryWeights[tier] or Loot.CategoryWeights.low)
	local rarity = Loot.RollRarity(rng, tier)
	if category == "weapon" then
		local w = pick(rng, Loot.WeaponWeights)
		-- Heavy weapons cannot roll below rare; reroll the weapon instead of inflating rarity.
		if (w == "helios" or w == "precision") and (rarity == "common" or rarity == "uncommon") then
			w = pick(rng, { pistol = 1, smg = 1, assault = 1, shotgun = 1 })
		end
		return { id = "weapon:" .. w, rarity = rarity, amount = 1 }
	elseif category == "ammo" then
		local a = pick(rng, { ammo_light = 30, ammo_medium = 30, ammo_shells = 16, ammo_energy = 14, ammo_heavy = 10 })
		return { id = a, rarity = "common", amount = Items.List[a].amount }
	elseif category == "consumable" then
		return { id = pick(rng, Loot.ConsumableWeights), rarity = "common", amount = 1 }
	elseif category == "armor" then
		return { id = Loot.ArmorByRarity[rarity], rarity = rarity, amount = 1 }
	elseif category == "utility" then
		return { id = pick(rng, Loot.UtilityWeights), rarity = "uncommon", amount = 1 }
	else
		return { id = pick(rng, Loot.UpgradeWeights), rarity = "rare", amount = 1 }
	end
end

-- A container's contents. Every weapon is accompanied by a stack of its ammo.
function Loot.RollContainer(rng, tier: string, minItems: number, maxItems: number)
	local out = {}
	for _ = 1, rng:NextInteger(minItems, maxItems) do
		local entry = Loot.RollItem(rng, tier)
		table.insert(out, entry)
		if string.sub(entry.id, 1, 7) == "weapon:" then
			local ammoId = ammoItemFor(string.sub(entry.id, 8))
			table.insert(out, { id = ammoId, rarity = "common", amount = Items.List[ammoId].amount })
		end
	end
	return out
end

return Loot
