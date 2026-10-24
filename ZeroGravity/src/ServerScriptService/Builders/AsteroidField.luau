-- Asteroid mining & salvage field plus scattered asteroids across the arena.
-- Asteroids are Terrain (lumpy multi-ball rock with craters and mineral veins) so they cost no parts
-- and collide cheaply. "The Anvil", the largest rock, has a mining tunnel bored through it.
local Kit = require(script.Parent.Kit)
local P = Kit.Palette

local Field = {}

local ROCK = { Enum.Material.Rock, Enum.Material.Basalt, Enum.Material.Slate, Enum.Material.Rock }
local VEIN = { Enum.Material.CrackedLava, Enum.Material.Glacier, Enum.Material.Salt, Enum.Material.Limestone }

-- Outer bound of an asteroid of nominal radius r (lumps reach out to 1.4 r).
Field.BoundScale = 1.4

-- One lumpy asteroid (all terrain). Returns its solid balls so props can be seated on the surface.
function Field.Asteroid(terrain: Terrain, rng: Random, center: Vector3, radius: number)
	local balls = { { c = center, r = radius } }
	local mat = ROCK[rng:NextInteger(1, #ROCK)]
	terrain:FillBall(center, radius, mat)
	for _ = 1, rng:NextInteger(2, 5) do
		local off = rng:NextUnitVector() * radius * rng:NextNumber(0.3, 0.6)
		local r = radius * rng:NextNumber(0.45, 0.8)
		terrain:FillBall(center + off, r, ROCK[rng:NextInteger(1, #ROCK)])
		table.insert(balls, { c = center + off, r = r })
	end
	if radius >= 14 then
		for _ = 1, rng:NextInteger(1, 4) do
			local dir = rng:NextUnitVector()
			terrain:FillBall(center + dir * radius * 1.05, radius * rng:NextNumber(0.2, 0.32), Enum.Material.Air) -- crater
		end
		if rng:NextNumber() < 0.6 then
			local dir = rng:NextUnitVector()
			terrain:FillBall(center + dir * radius * 0.85, radius * rng:NextNumber(0.12, 0.2), VEIN[rng:NextInteger(1, #VEIN)])
		end
	end
	return balls
end

-- Highest rock surface under a horizontal footprint (half sizes hx, hz) centred on pos.
local function surfaceTop(balls, pos: Vector3, hx: number, hz: number): number
	local top = -math.huge
	for _, dx in { -hx, 0, hx } do
		for _, dz in { -hz, 0, hz } do
			for _, b in balls do
				local ox, oz = pos.X + dx - b.c.X, pos.Z + dz - b.c.Z
				local h2 = b.r * b.r - ox * ox - oz * oz
				if h2 > 0 then top = math.max(top, b.c.Y + math.sqrt(h2)) end
			end
		end
	end
	return top
end

local function drillRig(parent, cf: CFrame)
	local m = Kit.model("DrillRig", parent)
	Kit.part(m, { Name = "Base", CFrame = cf, Size = Vector3.new(14, 2, 14), Color = P.HullDark, Material = Enum.Material.DiamondPlate })
	for _, c in { { 6, 6 }, { -6, 6 }, { 6, -6 }, { -6, -6 } } do
		Kit.part(m, { Name = "Strut", CFrame = cf * CFrame.new(c[1], 8, c[2]), Size = Vector3.new(1.2, 16, 1.2), Color = P.Orange })
	end
	Kit.part(m, { Name = "Head", CFrame = cf * CFrame.new(0, 16, 0), Size = Vector3.new(14, 3, 14), Color = P.Gunmetal })
	Kit.part(m, { Name = "Drill", Shape = Enum.PartType.Cylinder, CFrame = cf * CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(26, 3, 3), Color = P.HullLight })
	local lamp = Kit.part(m, { Name = "WorkLight", CFrame = cf * CFrame.new(0, 17.8, 0), Size = Vector3.new(3, 0.6, 3), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 200, 120), CanCollide = false })
	Kit.light(lamp, Color3.fromRGB(255, 200, 120), 40, 1.5)
	return m
end

local function miningPlatform(parent, markers, cf: CFrame, label: string)
	local m = Kit.model("MiningPlatform", parent)
	Kit.part(m, { Name = "Deck", CFrame = cf, Size = Vector3.new(40, 2, 28), Color = P.HullDark, Material = Enum.Material.DiamondPlate })
	for _, s in { -1, 1 } do
		Kit.part(m, { Name = "Rail", CFrame = cf * CFrame.new(0, 2.2, s * 13.8), Size = Vector3.new(40, 0.5, 0.5), Color = P.Orange })
	end
	Kit.part(m, { Name = "Hab", CFrame = cf * CFrame.new(-12, 6, 0), Size = Vector3.new(12, 10, 16), Color = P.Hull })
	Kit.window(m, cf * CFrame.new(-5.6, 7, 0) * CFrame.Angles(0, math.rad(90), 0), 8, 3)
	Kit.crate(m, cf * CFrame.new(8, 4, -6), Vector3.new(10, 6, 6), Color3.fromRGB(150, 80, 40))
	Kit.crate(m, cf * CFrame.new(10, 4, 6), Vector3.new(6, 6, 6), P.Gunmetal)
	Kit.part(m, { Name = "OreHopper", CFrame = cf * CFrame.new(16, 6, 0) * CFrame.Angles(0, 0, math.rad(10)), Size = Vector3.new(6, 10, 10), Color = P.Orange })
	Kit.sign(m, cf * CFrame.new(-12, 12.5, 8.2), label, 12, 2, P.Orange)
	Kit.antenna(m, cf * CFrame.new(-16, 11, -6), 10)
	Kit.marker(markers, "LootSpot", cf * CFrame.new(0, 3, 0), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", cf * CFrame.new(-12, 3, -11), { Tier = "low", Kind = "cache" })
	return m
end

-- exclusion: list of { center = Vector3, radius = number } that asteroids must avoid
function Field.Build(arena: Instance, markers: Instance, terrain: Terrain, exclusion)
	local root = Kit.model("AsteroidField", arena)
	local rng = Random.new(4242)
	local placed = {}

	local function free(pos: Vector3, r: number, gap: number): boolean
		for _, e in exclusion do
			if (pos - e.center).Magnitude < e.radius + r then return false end
		end
		for _, a in placed do
			if (pos - a.p).Magnitude < a.r + r + gap then return false end
		end
		return pos.Magnitude + r < 1950
	end
	local function place(pos, r)
		local balls = Field.Asteroid(terrain, rng, pos, r)
		table.insert(placed, { p = pos, r = r * Field.BoundScale, nominal = r, balls = balls })
	end

	-- The Anvil: huge asteroid with a bored tunnel (choke point + final-zone candidate)
	local anvil = Vector3.new(-880, -40, 380)
	place(anvil, 90)
	local tunnelDir = Vector3.new(1, 0.15, -0.35).Unit
	for t = -120, 120, 6 do
		terrain:FillBall(anvil + tunnelDir * t, 11, Enum.Material.Air)
	end
	-- interior chamber in the middle of the tunnel
	terrain:FillBall(anvil, 26, Enum.Material.Air)
	local chamber = Kit.model("AnvilChamber", root)
	-- Mine shoring struts around the chamber (the tunnel itself stays clear)
	local axis = CFrame.lookAt(anvil, anvil + tunnelDir)
	for i = 0, 3 do
		Kit.part(chamber, { Name = "Strut", CFrame = axis * CFrame.Angles(0, 0, math.rad(i * 90 + 45)) * CFrame.new(0, 22, 0),
			Size = Vector3.new(1.5, 1.5, 40), Color = P.Orange })
	end
	local lamp = Kit.part(chamber, { Name = "ChamberLight", Shape = Enum.PartType.Ball, CFrame = CFrame.new(anvil + Vector3.new(0, 18, 0)),
		Size = Vector3.one * 3, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 190, 110), CanCollide = false })
	Kit.light(lamp, Color3.fromRGB(255, 190, 110), 50, 2)
	Kit.crate(chamber, CFrame.new(anvil + Vector3.new(6, -18, 4)), Vector3.new(8, 6, 6), P.Gunmetal)
	Kit.marker(markers, "LootSpot", CFrame.new(anvil + Vector3.new(-6, -16, -4)), { Tier = "high", Kind = "cache" })
	Kit.marker(markers, "LootSpot", CFrame.new(anvil + Vector3.new(8, -12, 10)), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "FinalZone", CFrame.new(anvil), { Label = "The Anvil" })
	Kit.marker(markers, "OxygenStation", CFrame.new(anvil + Vector3.new(0, -20, 12)))
	for _, s in { -1, 1 } do
		local mouth = anvil + tunnelDir * s * 100
		local b = Kit.part(root, { Name = "TunnelBeacon", Shape = Enum.PartType.Ball, CFrame = CFrame.new(mouth + Vector3.new(0, 16, 0)), Size = Vector3.one * 2.5,
			Material = Enum.Material.Neon, Color = P.Orange, CanCollide = false })
		Kit.light(b, P.Orange, 40, 2)
	end

	-- Dense mining field around the Anvil: clustered rocks forming channels
	local fieldCenter = Vector3.new(-820, -40, 380)
	local attempts = 0
	local count = 0
	while count < 34 and attempts < 2000 do
		attempts += 1
		local r = rng:NextNumber() < 0.25 and rng:NextNumber(35, 60) or rng:NextNumber(10, 30)
		local pos = fieldCenter + rng:NextUnitVector() * rng:NextNumber(130, 520) * Vector3.new(1, 0.45, 1)
		if free(pos, r * Field.BoundScale, 26) then
			place(pos, r)
			count += 1
		end
	end
	-- Mining platforms and drill rigs on the larger rocks
	local big = {}
	for _, a in placed do
		if (a.nominal or 0) >= 35 and a.p ~= anvil then table.insert(big, a) end
	end
	for i, a in big do
		if i > 5 then break end
		-- seat props on the highest rock under their footprint so nothing is buried in the asteroid
		if i <= 2 then
			local y = surfaceTop(a.balls, a.p, 20, 14) + 1
			miningPlatform(root, markers, CFrame.new(a.p.X, y, a.p.Z), i == 1 and "KESSLER MINING 04" or "KESSLER MINING 07")
		else
			local y = surfaceTop(a.balls, a.p, 12, 7)
			drillRig(root, CFrame.new(a.p.X, y + 1, a.p.Z))
			Kit.marker(markers, "LootSpot", CFrame.new(a.p.X + 10, y + 3, a.p.Z), { Tier = "low", Kind = "cache" })
		end
		Kit.marker(markers, "DeployPoint", CFrame.new(a.p + Vector3.new(0, a.r + 50, 0)))
	end
	-- Floating ore containers and caches between rocks
	for _ = 1, 8 do
		local pos = fieldCenter + rng:NextUnitVector() * rng:NextNumber(80, 420) * Vector3.new(1, 0.4, 1)
		if free(pos, 8, 4) then
			table.insert(placed, { p = pos, r = 8 })
			local cf = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6))
			Kit.crate(root, cf, Vector3.new(14, 8, 8), Color3.fromRGB(150, 80, 40))
			Kit.marker(markers, "LootSpot", cf * CFrame.new(0, 6, 0), { Tier = "low", Kind = "cache" })
		end
	end

	-- Scattered asteroids across the whole arena (cover between landmarks)
	attempts, count = 0, 0
	while count < 45 and attempts < 4000 do
		attempts += 1
		local r = rng:NextNumber(6, 26)
		local pos = rng:NextUnitVector() * rng:NextNumber(450, 1800) * Vector3.new(1, 0.5, 1)
		if free(pos, r * Field.BoundScale, 60) then
			place(pos, r)
			count += 1
		end
	end
	-- A few deploy points in the open field
	for _, d in { Vector3.new(-600, 80, 120), Vector3.new(-1100, 40, 650), Vector3.new(-700, -160, 700), Vector3.new(-1150, -120, 150),
		Vector3.new(-1000, 160, 300), Vector3.new(-560, -120, 520) } do
		local clear = true
		for _, a in placed do
			if (d - a.p).Magnitude < a.r + 15 then
				clear = false
				break
			end
		end
		if clear then Kit.marker(markers, "DeployPoint", CFrame.new(d)) end
	end
	return root, placed
end

return Field
