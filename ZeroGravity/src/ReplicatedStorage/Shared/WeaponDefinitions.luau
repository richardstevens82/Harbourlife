-- Weapon stats. Damage is per pellet; `pellets` > 1 means a spread shot.
-- range: full damage up to `range`, linear falloff to `minDamageScale` at `maxRange`.
-- mobility multiplies MaxSpeed while the weapon is equipped (weight trade-off).
-- spread / adsSpread are cone half-angles in degrees. recoil is camera kick in degrees per shot.
local Weapons = {}

Weapons.List = {
	pistol = {
		name = "Vega P9 Pistol", class = "Compact space pistol", ammo = "light", mode = "semi",
		damage = 22, pellets = 1, rpm = 360, mag = 12, reload = 1.3,
		range = 120, maxRange = 300, minDamageScale = 0.6, spread = 1.4, adsSpread = 0.5, recoil = 1.2,
		mobility = 1.0, color = Color3.fromRGB(70, 75, 85), accent = Color3.fromRGB(60, 140, 255), size = 1.0,
	},
	assault = {
		name = "AR-7 Pulse Rifle", class = "Assault rifle", ammo = "medium", mode = "auto",
		damage = 17, pellets = 1, rpm = 600, mag = 30, reload = 2.1,
		range = 220, maxRange = 500, minDamageScale = 0.55, spread = 2.0, adsSpread = 0.6, recoil = 0.9,
		mobility = 0.93, color = Color3.fromRGB(55, 58, 66), accent = Color3.fromRGB(70, 160, 255), size = 1.45,
	},
	burst = {
		name = "Triad Burst Rifle", class = "Burst-fire rifle", ammo = "medium", mode = "burst", burstCount = 3, burstDelay = 0.07,
		damage = 21, pellets = 1, rpm = 220, mag = 24, reload = 2.2,
		range = 260, maxRange = 550, minDamageScale = 0.6, spread = 1.3, adsSpread = 0.35, recoil = 1.1,
		mobility = 0.93, color = Color3.fromRGB(60, 62, 70), accent = Color3.fromRGB(255, 140, 50), size = 1.4,
	},
	precision = {
		name = "Longreach Precision Rifle", class = "Precision rifle", ammo = "heavy", mode = "semi",
		damage = 85, pellets = 1, rpm = 45, mag = 5, reload = 2.8,
		range = 900, maxRange = 1400, minDamageScale = 0.8, spread = 4.0, adsSpread = 0.05, recoil = 4,
		mobility = 0.85, color = Color3.fromRGB(45, 48, 54), accent = Color3.fromRGB(60, 140, 255), size = 1.9,
	},
	shotgun = {
		name = "Breacher Shotgun", class = "Shotgun", ammo = "shells", mode = "semi",
		damage = 11, pellets = 9, rpm = 75, mag = 6, reload = 2.6,
		range = 25, maxRange = 70, minDamageScale = 0.2, spread = 6.5, adsSpread = 5.0, recoil = 3.5,
		mobility = 0.92, color = Color3.fromRGB(70, 60, 52), accent = Color3.fromRGB(255, 120, 40), size = 1.35,
	},
	smg = {
		name = "Wasp SMG", class = "Submachine gun", ammo = "light", mode = "auto",
		damage = 13, pellets = 1, rpm = 900, mag = 32, reload = 1.7,
		range = 80, maxRange = 220, minDamageScale = 0.45, spread = 3.0, adsSpread = 1.6, recoil = 0.6,
		mobility = 1.0, color = Color3.fromRGB(62, 66, 74), accent = Color3.fromRGB(80, 220, 255), size = 1.15,
	},
	helios = {
		name = "Helios Arc Cannon", class = "Heavy energy weapon", ammo = "energy", mode = "semi",
		damage = 55, pellets = 1, rpm = 70, mag = 4, reload = 3.2, splash = 10, splashDamage = 30,
		range = 300, maxRange = 600, minDamageScale = 0.7, spread = 1.0, adsSpread = 0.4, recoil = 5,
		mobility = 0.8, color = Color3.fromRGB(40, 44, 52), accent = Color3.fromRGB(120, 200, 255), size = 1.8,
	},
	arc = {
		name = "Arc Thrower", class = "Short-range defensive weapon", ammo = "energy", mode = "auto",
		damage = 6, pellets = 3, rpm = 480, mag = 20, reload = 2.0,
		range = 18, maxRange = 32, minDamageScale = 0.0, spread = 9, adsSpread = 9, recoil = 0.3,
		mobility = 0.97, color = Color3.fromRGB(58, 62, 70), accent = Color3.fromRGB(150, 230, 255), size = 1.1,
	},
}

Weapons.Order = { "pistol", "smg", "assault", "burst", "shotgun", "precision", "helios", "arc" }

-- Rarity scales damage and magazine slightly; never enough to make rarity mandatory.
Weapons.RarityDamage = { common = 1.0, uncommon = 1.04, rare = 1.08, epic = 1.12, legendary = 1.16 }
Weapons.RarityMag = { common = 1.0, uncommon = 1.0, rare = 1.15, epic = 1.25, legendary = 1.35 }

function Weapons.Get(id: string)
	return Weapons.List[id]
end

function Weapons.MagSize(id: string, rarity: string): number
	local def = Weapons.List[id]
	return math.floor(def.mag * (Weapons.RarityMag[rarity] or 1) + 0.5)
end

function Weapons.FireInterval(id: string): number
	return 60 / Weapons.List[id].rpm
end

-- Damage for one pellet at `distance`, after rarity.
function Weapons.DamageAt(id: string, rarity: string, distance: number): number
	local def = Weapons.List[id]
	local scale
	if distance <= def.range then
		scale = 1
	elseif distance >= def.maxRange then
		return 0
	else
		local t = (distance - def.range) / (def.maxRange - def.range)
		scale = 1 + (def.minDamageScale - 1) * t
	end
	return def.damage * scale * (Weapons.RarityDamage[rarity] or 1)
end

return Weapons
