-- Derelict spacecraft and orbital debris: two explorable wrecks, satellites, damaged cargo
-- modules, broken solar panels, escape pods, industrial equipment, cargo platforms and a
-- communications array. Each small location carries loot so space between landmarks is never dead.
local Kit = require(script.Parent.Kit)
local P = Kit.Palette

local Debris = {}

-- Wrecked freighter "Kestrel": three tilted compartments with missing walls, dark and damaged.
local function freighterWreck(parent, markers, cf: CFrame)
	local m = Kit.model("Wreck_Kestrel", parent)
	local door = { w = 12, h = 12 }
	-- Fore compartment (cockpit), torn open on +Z
	local aCf = cf * CFrame.new(-70, 0, 0) * CFrame.Angles(0, 0, math.rad(8))
	local a = Kit.room(m, aCf, Vector3.new(36, 18, 30), { name = "Fore", lights = false, deck = true, color = P.HullDark,
		openings = { ["+X"] = door, ["+Z"] = true, ["-X"] = { w = 20, h = 8 } } })
	Kit.brokenLight(a, aCf * CFrame.new(0, 8.5, 0))
	Kit.marker(markers, "LootSpot", aCf * CFrame.new(-10, -6, -8), { Tier = "mid", Kind = "crate" })
	-- Mid compartment (cargo), pressurised pocket still holding air
	local bCf = cf
	local b = Kit.room(m, bCf, Vector3.new(60, 26, 40), { name = "Mid", lights = false, deck = true, color = P.Hull,
		pressurized = "wreck_kestrel_mid", openings = { ["-X"] = door, ["+X"] = { w = 26, h = 20 }, ["+Y"] = door } })
	Kit.brokenLight(b, bCf * CFrame.new(-12, 12.5, 6))
	Kit.brokenLight(b, bCf * CFrame.new(16, 12.5, -8))
	for i = -1, 1 do
		Kit.crate(b, bCf * CFrame.new(i * 16, -9, 10) * CFrame.Angles(0, i * 0.2, i * 0.1), Vector3.new(12, 8, 8), Color3.fromRGB(70, 90, 120))
	end
	Kit.marker(markers, "ElectricHazard", bCf * CFrame.new(20, 0, 10), { Size = Vector3.new(10, 26, 12) })
	Kit.marker(markers, "SmokeVolume", bCf, { Size = Vector3.new(60, 26, 40) })
	Kit.marker(markers, "ExplosiveBarrel", bCf * CFrame.new(-22, -10, -14))
	Kit.marker(markers, "ExplosiveBarrel", bCf * CFrame.new(-18, -10, -16))
	Kit.marker(markers, "LootSpot", bCf * CFrame.new(0, -8, -10), { Tier = "high", Kind = "crate" })
	Kit.marker(markers, "LootSpot", bCf * CFrame.new(-20, 4, 12), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "OxygenStation", bCf * CFrame.new(28, -6, -16) * CFrame.Angles(0, math.rad(-90), 0))
	Kit.marker(markers, "FinalZone", bCf, { Label = "Kestrel Wreck" })
	-- Aft section broken away and drifting
	local cCf = cf * CFrame.new(78, -14, 12) * CFrame.Angles(math.rad(20), math.rad(-15), math.rad(-25))
	local c = Kit.room(m, cCf, Vector3.new(40, 22, 34), { name = "Aft", lights = false, deck = true, color = P.HullDark,
		openings = { ["-X"] = true, ["+Y"] = { w = 14, h = 10 } } })
	Kit.brokenLight(c, cCf * CFrame.new(0, 10.5, 0))
	for _, z in { -8, 8 } do
		Kit.part(c, { Name = "DeadEngine", Shape = Enum.PartType.Cylinder, CFrame = cCf * CFrame.new(26, 0, z), Size = Vector3.new(14, 10, 10), Color = P.Gunmetal })
	end
	Kit.marker(markers, "LootSpot", cCf * CFrame.new(-6, -7, 0), { Tier = "mid", Kind = "crate" })
	-- Torn hull plates
	local rng = Random.new(91)
	for _ = 1, 14 do
		local pcf = cf * CFrame.new(rng:NextNumber(-110, 120), rng:NextNumber(-40, 40), rng:NextNumber(-50, 50))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		Kit.part(m, { Name = "HullFragment", CFrame = pcf, Size = Vector3.new(rng:NextNumber(4, 12), 0.8, rng:NextNumber(4, 10)), Color = P.HullDark,
			Material = Enum.Material.CorrodedMetal })
	end
	Kit.sign(m, bCf * CFrame.new(0, 6, -22.2) * CFrame.Angles(0, math.rad(180), 0), "KESTREL  //  HAULER 2291", 26, 4, P.Orange)
	return m
end

-- Corvette wreck: a smaller split warship hull.
local function corvetteWreck(parent, markers, cf: CFrame)
	local m = Kit.model("Wreck_Corvette", parent)
	local door = { w = 12, h = 12 }
	local aCf = cf * CFrame.Angles(math.rad(-10), 0, math.rad(12))
	local a = Kit.room(m, aCf, Vector3.new(50, 16, 24), { name = "Gundeck", lights = false, deck = true, color = P.Gunmetal,
		openings = { ["+X"] = true, ["-Z"] = door, ["+Y"] = { w = 18, h = 8, x = 10 } } })
	Kit.brokenLight(a, aCf * CFrame.new(-10, 7.5, 0))
	Kit.part(a, { Name = "Turret", Shape = Enum.PartType.Cylinder, CFrame = aCf * CFrame.new(-14, 11, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(4, 10, 10), Color = P.HullDark })
	Kit.part(a, { Name = "TurretBarrel", CFrame = aCf * CFrame.new(-6, 12, 0), Size = Vector3.new(14, 1.4, 1.4), Color = P.HullDark })
	Kit.marker(markers, "LootSpot", aCf * CFrame.new(-16, -5, 6), { Tier = "high", Kind = "locker" })
	Kit.marker(markers, "LootSpot", aCf * CFrame.new(8, -5, -6), { Tier = "mid", Kind = "crate" })
	local bCf = cf * CFrame.new(60, 10, 20) * CFrame.Angles(math.rad(25), math.rad(30), 0)
	local b = Kit.room(m, bCf, Vector3.new(30, 14, 22), { name = "Stern", lights = false, deck = true, color = P.Gunmetal,
		openings = { ["-X"] = true } })
	Kit.brokenLight(b, bCf * CFrame.new(0, 6.5, 0))
	Kit.marker(markers, "LootSpot", bCf * CFrame.new(4, -4, 0), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "ExplosiveBarrel", bCf * CFrame.new(-6, -5, 6))
	Kit.marker(markers, "FinalZone", cf, { Label = "Corvette Wreck" })
	return m
end

local function satellite(parent, markers, cf: CFrame, rng: Random)
	local m = Kit.model("DerelictSatellite", parent)
	Kit.part(m, { Name = "Bus", CFrame = cf, Size = Vector3.new(8, 8, 10), Color = Color3.fromRGB(200, 170, 80), Material = Enum.Material.Foil })
	Kit.part(m, { Name = "Dish", Shape = Enum.PartType.Cylinder, CFrame = cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(1, 10, 10), Color = P.HullLight })
	for s = -1, 1, 2 do
		local broken = rng:NextNumber() < 0.5
		local wcf = cf * CFrame.new(0, 0, s * 15) * CFrame.Angles(broken and rng:NextNumber(-0.8, 0.8) or 0, 0, 0)
		Kit.part(m, { Name = "Wing", CFrame = wcf, Size = Vector3.new(8, 0.4, broken and 10 or 18), Color = P.Solar, Material = Enum.Material.Glass })
	end
	local b = Kit.part(m, { Name = "Blink", Shape = Enum.PartType.Ball, CFrame = cf * CFrame.new(0, -4.5, 0), Size = Vector3.one, Material = Enum.Material.Neon,
		Color = P.Red, CanCollide = false })
	Kit.light(b, P.Red, 12, 1)
	Kit.marker(markers, "LootSpot", cf * CFrame.new(0, 6, 7), { Tier = "low", Kind = "cache" })
	return m
end

local function escapePod(parent, markers, cf: CFrame, tier: string)
	local m = Kit.octTube(parent, cf, 5, 12, { name = "EscapePod", caps = { front = { w = 7, h = 7 } }, color = P.HullLight, accentColor = P.Orange,
		rings = 1, pressurized = nil })
	m.Name = "EscapePod"
	local b = Kit.part(m, { Name = "Beacon", Shape = Enum.PartType.Ball, CFrame = cf * CFrame.new(0, 7.5, 0), Size = Vector3.one * 1.2,
		Material = Enum.Material.Neon, Color = P.Orange, CanCollide = false })
	Kit.light(b, P.Orange, 18, 1.5)
	Kit.marker(markers, "LootSpot", cf * CFrame.new(0, -2, 2), { Tier = tier, Kind = "pod" })
	return m
end

local function cargoModule(parent, markers, cf: CFrame, rng: Random)
	local m = Kit.model("DamagedCargoModule", parent)
	for i = 0, rng:NextInteger(2, 4) do
		-- containers tumble around the module's centre, leaving the salvage cache at the middle reachable
		local c = cf * CFrame.new(rng:NextUnitVector() * rng:NextNumber(13, 18))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		local colors = { Color3.fromRGB(150, 80, 40), Color3.fromRGB(60, 90, 140), P.HullDark }
		Kit.crate(m, c, Vector3.new(16, 8, 8), colors[(i % 3) + 1])
	end
	Kit.marker(markers, "LootSpot", cf, { Tier = "low", Kind = "crate" })
	return m
end

local function industrial(parent, cf: CFrame, rng: Random)
	local m = Kit.model("IndustrialDebris", parent)
	local kind = rng:NextInteger(1, 3)
	if kind == 1 then
		Kit.part(m, { Name = "Tank", Shape = Enum.PartType.Cylinder, CFrame = cf, Size = Vector3.new(18, 9, 9), Color = P.HullLight })
		Kit.part(m, { Name = "TankBand", Shape = Enum.PartType.Cylinder, CFrame = cf, Size = Vector3.new(2, 9.4, 9.4), Color = P.Orange })
	elseif kind == 2 then
		for i = -1, 1 do
			Kit.part(m, { Name = "Girder", CFrame = cf * CFrame.new(0, i * 3, 0) * CFrame.Angles(0, i * 0.3, 0), Size = Vector3.new(30, 1.4, 1.4), Color = P.Orange })
		end
	else
		Kit.part(m, { Name = "Generator", CFrame = cf, Size = Vector3.new(10, 8, 8), Color = P.HullDark })
		Kit.part(m, { Name = "Fins", CFrame = cf * CFrame.new(0, 4.5, 0), Size = Vector3.new(9, 1, 7), Color = P.Gunmetal })
	end
	return m
end

local function brokenSolar(parent, cf: CFrame)
	local m = Kit.model("BrokenSolarPanel", parent)
	Kit.part(m, { Name = "Cell", CFrame = cf, Size = Vector3.new(14, 0.4, 9), Color = P.Solar, Material = Enum.Material.Glass, Reflectance = 0.15 })
	Kit.part(m, { Name = "Spar", CFrame = cf * CFrame.new(0, 0, 4.8), Size = Vector3.new(16, 0.8, 0.8), Color = P.HullLight })
	return m
end

local function cargoPlatform(parent, markers, cf: CFrame, label: string)
	local m = Kit.model("CargoPlatform", parent)
	Kit.part(m, { Name = "Deck", CFrame = cf, Size = Vector3.new(36, 2, 36), Color = P.HullDark, Material = Enum.Material.DiamondPlate })
	for _, c in { { 10, 10 }, { -10, 8 }, { 8, -12 } } do
		Kit.crate(m, cf * CFrame.new(c[1], 4, c[2]), Vector3.new(10, 6, 6), Color3.fromRGB(60, 90, 140))
	end
	for _, c in { { 17, 17 }, { -17, 17 }, { 17, -17 }, { -17, -17 } } do
		local b = Kit.part(m, { Name = "CornerLight", CFrame = cf * CFrame.new(c[1], 1.6, c[2]), Size = Vector3.new(1.2, 1.2, 1.2), Material = Enum.Material.Neon,
			Color = P.Orange, CanCollide = false })
		Kit.light(b, P.Orange, 18, 1)
	end
	Kit.sign(m, cf * CFrame.new(0, 3, -18.2) * CFrame.Angles(0, math.rad(180), 0), label, 14, 2, P.Orange)
	Kit.marker(markers, "LootSpot", cf * CFrame.new(-6, 3, -6), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "OxygenStation", cf * CFrame.new(0, 3, 12))
	return m
end

local function commArray(parent, markers, cf: CFrame)
	local m = Kit.model("CommArray", parent)
	Kit.part(m, { Name = "Mast", CFrame = cf * CFrame.new(0, 60, 0), Size = Vector3.new(4, 120, 4), Color = P.HullLight })
	for i = 0, 5 do
		local y = 20 + i * 18
		Kit.part(m, { Name = "Brace", CFrame = cf * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(i * 30), 0), Size = Vector3.new(16, 1, 1), Color = P.HullDark })
	end
	for i, a in { 0, 120, 240 } do
		local dcf = cf * CFrame.new(0, 40 + i * 25, 0) * CFrame.Angles(0, math.rad(a), 0) * CFrame.new(10, 0, 0) * CFrame.Angles(0, 0, math.rad(-35))
		Kit.part(m, { Name = "Dish", Shape = Enum.PartType.Cylinder, CFrame = dcf, Size = Vector3.new(1.4, 18, 18), Color = P.HullLight })
	end
	Kit.part(m, { Name = "Base", CFrame = cf, Size = Vector3.new(30, 4, 30), Color = P.HullDark, Material = Enum.Material.DiamondPlate })
	Kit.part(m, { Name = "Shack", CFrame = cf * CFrame.new(8, 6, 8), Size = Vector3.new(10, 8, 10), Color = P.Hull })
	local top = Kit.part(m, { Name = "Beacon", Shape = Enum.PartType.Ball, CFrame = cf * CFrame.new(0, 122, 0), Size = Vector3.one * 3,
		Material = Enum.Material.Neon, Color = P.Red, CanCollide = false })
	Kit.light(top, P.Red, 60, 3)
	Kit.marker(markers, "LootSpot", cf * CFrame.new(-8, 4, -8), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", cf * CFrame.new(0, 3, 16), { Tier = "low", Kind = "cache" })
	return m
end

-- Returns the list of exclusion spheres the asteroid builder should keep clear of.
Debris.Sites = {
	kestrel = CFrame.new(-380, 230, 760) * CFrame.Angles(0, math.rad(25), 0),
	corvette = CFrame.new(700, -260, 470) * CFrame.Angles(0, math.rad(-40), 0),
	commArray = CFrame.new(950, 250, -200),
	platformA = CFrame.new(-250, -320, -600),
	platformB = CFrame.new(500, 330, 650),
}

function Debris.Exclusions()
	return {
		{ center = Debris.Sites.kestrel.Position, radius = 170 },
		{ center = Debris.Sites.corvette.Position, radius = 110 },
		{ center = Debris.Sites.commArray.Position + Vector3.new(0, 60, 0), radius = 90 },
		{ center = Debris.Sites.platformA.Position, radius = 50 },
		{ center = Debris.Sites.platformB.Position, radius = 50 },
	}
end

function Debris.Build(arena: Instance, markers: Instance, exclusion)
	local root = Kit.model("DerelictsAndDebris", arena)
	local rng = Random.new(1337)
	freighterWreck(root, markers, Debris.Sites.kestrel)
	corvetteWreck(root, markers, Debris.Sites.corvette)
	commArray(root, markers, Debris.Sites.commArray)
	cargoPlatform(root, markers, Debris.Sites.platformA, "DEPOT SIGMA")
	cargoPlatform(root, markers, Debris.Sites.platformB, "DEPOT TAU")
	for _, s in { Debris.Sites.kestrel, Debris.Sites.corvette } do
		for i = 0, 2 do
			local a = math.rad(i * 120)
			Kit.marker(markers, "DeployPoint", s * CFrame.new(math.cos(a) * 190, 50, math.sin(a) * 190))
		end
	end

	local placed = {}
	local function spot(minR, maxR, clearance): CFrame?
		for _ = 1, 200 do
			local pos = rng:NextUnitVector() * rng:NextNumber(minR, maxR) * Vector3.new(1, 0.55, 1)
			local ok = true
			for _, e in exclusion do
				if (pos - e.center).Magnitude < e.radius + clearance then
					ok = false
					break
				end
			end
			for _, p in placed do
				if (pos - p).Magnitude < clearance * 2 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(placed, pos)
				return CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5))
			end
		end
		return nil
	end
	for _ = 1, 6 do
		local cf = spot(450, 1500, 40)
		if cf then satellite(root, markers, cf, rng) end
	end
	for i = 1, 8 do
		local cf = spot(350, 1600, 30)
		if cf then escapePod(root, markers, cf, i <= 2 and "mid" or "low") end
	end
	for _ = 1, 6 do
		local cf = spot(400, 1600, 40)
		if cf then cargoModule(root, markers, cf, rng) end
	end
	for _ = 1, 14 do
		local cf = spot(300, 1650, 20)
		if cf then industrial(root, cf, rng) end
	end
	for _ = 1, 12 do
		local cf = spot(300, 1600, 15)
		if cf then brokenSolar(root, cf) end
	end
	return root, placed
end

return Debris
