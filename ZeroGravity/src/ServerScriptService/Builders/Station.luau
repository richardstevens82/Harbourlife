-- Orbital station "Meridian". Layout (station centred on the origin):
--   Hub (central command & docking junction) with six branches:
--     +Y Command Module (observation windows, top airlock)
--     -Y Docking Bay (open hangar to space, reached through an airlock)
--     -X Science Labs (junction + three labs; one lab is damaged: sparks, smoke, breachable hull)
--     +Z Armoury -> Observation Deck (panoramic window, side airlocks)
--     -Z Hydroponics (grow beds, exterior airlock)
--     +X Spine -> Ring Junction -> Engineering (reactor); the Habitat Ring (8 segments) circles the
--        spine in the YZ plane and is reached by two spokes.
--   Exterior: solar arrays, antennae, maintenance platforms with loot, hull lights.
local Kit = require(script.Parent.Kit)
local P = Kit.Palette

local Station = {}

local T = 2 -- wall thickness used throughout

local function airlockAt(parent, center: Vector3, outward: Vector3)
	local up = math.abs(outward.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
	return Kit.airlock(parent, CFrame.lookAt(center, center + outward, up))
end

-- Airlock attached to the outside of a room face (room must have a 12x12 opening on that face).
local function airlockOnFace(parent, roomCf: CFrame, size: Vector3, face: string)
	local fcf = Kit.faceCFrame(roomCf, size, face, T)
	local center = (fcf * CFrame.new(0, 0, 7)).Position
	return airlockAt(parent, center, fcf.LookVector * -1)
end

-- Maintenance platform: grated deck with railings, a crate stack and a loot marker.
local function platform(parent, markers, cf: CFrame, w: number, d: number, tier: string)
	local m = Kit.model("MaintenancePlatform", parent)
	Kit.part(m, { Name = "Grate", CFrame = cf, Size = Vector3.new(w, 1, d), Color = P.HullDark, Material = Enum.Material.DiamondPlate })
	for _, s in { -1, 1 } do
		Kit.part(m, { Name = "Rail", CFrame = cf * CFrame.new(s * (w / 2 - 0.3), 2, 0), Size = Vector3.new(0.4, 0.4, d), Color = P.Orange })
		Kit.part(m, { Name = "Rail", CFrame = cf * CFrame.new(0, 2, s * (d / 2 - 0.3)), Size = Vector3.new(w, 0.4, 0.4), Color = P.Orange })
	end
	for i = 1, 4 do
		local x, z = (i % 2 == 0 and 1 or -1) * (w / 2 - 0.3), (i <= 2 and 1 or -1) * (d / 2 - 0.3)
		Kit.part(m, { Name = "Post", CFrame = cf * CFrame.new(x, 1, z), Size = Vector3.new(0.5, 2, 0.5), Color = P.HullLight })
	end
	Kit.crate(m, cf * CFrame.new(w / 4, 3.5, 0), Vector3.new(6, 6, 10), P.Gunmetal)
	local lamp = Kit.part(m, { Name = "Floodlight", CFrame = cf * CFrame.new(-w / 2 + 1, 4, -d / 2 + 1), Size = Vector3.new(1.4, 1.4, 1.4),
		Material = Enum.Material.Neon, Color = P.BlueGlow, CanCollide = false })
	Kit.light(lamp, P.BlueGlow, 30, 1.4)
	Kit.marker(markers, "LootSpot", cf * CFrame.new(-w / 4, 2.5, 0), { Tier = tier, Kind = "crate" })
	return m
end

-- Furniture helpers ------------------------------------------------------------------------------
local function console(parent, cf: CFrame)
	Kit.part(parent, { Name = "Console", CFrame = cf, Size = Vector3.new(6, 3, 2.4), Color = P.Gunmetal })
	local screen = Kit.part(parent, { Name = "Screen", CFrame = cf * CFrame.new(0, 1.6, -0.4) * CFrame.Angles(math.rad(-25), 0, 0),
		Size = Vector3.new(5, 0.2, 1.8), Material = Enum.Material.Neon, Color = Color3.fromRGB(60, 150, 255), CanCollide = false })
	return screen
end

local function lockers(parent, cf: CFrame, count: number)
	for i = 0, count - 1 do
		local c = cf * CFrame.new((i - (count - 1) / 2) * 3.2, 0, 0)
		Kit.part(parent, { Name = "Locker", CFrame = c, Size = Vector3.new(3, 8, 2.4), Color = P.HullDark })
		Kit.part(parent, { Name = "LockerLight", CFrame = c * CFrame.new(0, 3, -1.25), Size = Vector3.new(2, 0.3, 0.1),
			Material = Enum.Material.Neon, Color = P.Blue, CanCollide = false })
	end
end

local function cargoStack(parent, cf: CFrame)
	Kit.crate(parent, cf, Vector3.new(8, 6, 6), P.HullDark)
	Kit.crate(parent, cf * CFrame.new(1, 6, 0) * CFrame.Angles(0, math.rad(15), 0), Vector3.new(6, 6, 6), Color3.fromRGB(70, 90, 120))
end

function Station.Build(arena: Instance, markers: Instance)
	local root = Kit.model("SpaceStation", arena)

	-- HUB ---------------------------------------------------------------------------------------
	local hubCf, hubSize = CFrame.new(0, 0, 0), Vector3.new(60, 40, 60)
	local door = { w = 12, h = 12 }
	local hub = Kit.room(root, hubCf, hubSize, {
		name = "Hub", pressurized = "hub", deck = true,
		openings = { ["+X"] = door, ["-X"] = door, ["+Y"] = door, ["-Y"] = door, ["+Z"] = door, ["-Z"] = door },
	})
	-- Central holo-table and support columns (cover)
	Kit.part(hub, { Name = "HoloTable", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(0, -16, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(4, 16, 16), Color = P.Gunmetal })
	local holo = Kit.part(hub, { Name = "Hologram", Shape = Enum.PartType.Ball, CFrame = CFrame.new(0, -8, 0), Size = Vector3.one * 8,
		Material = Enum.Material.ForceField, Color = P.BlueGlow, CanCollide = false })
	Kit.light(holo, P.BlueGlow, 30, 2)
	for _, c in { { 18, 18 }, { -18, 18 }, { 18, -18 }, { -18, -18 } } do
		Kit.part(hub, { Name = "Column", CFrame = CFrame.new(c[1], 0, c[2]), Size = Vector3.new(5, 40, 5), Color = P.HullDark })
	end
	for _, c in { { 22, -16, 10 }, { -22, -16, -10 }, { 10, -16, -24 } } do
		cargoStack(hub, CFrame.new(c[1], c[2], c[3]))
	end
	console(hub, CFrame.new(0, -18, 24))
	Kit.sign(hub, CFrame.new(0, 14, 29.6) * CFrame.Angles(0, math.rad(180), 0), "MERIDIAN STATION - HUB", 24, 3)
	Kit.marker(markers, "LootSpot", CFrame.new(24, -17, -24), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", CFrame.new(-24, 10, 24), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "OxygenStation", CFrame.new(-28, -10, 0) * CFrame.Angles(0, math.rad(90), 0))
	Kit.marker(markers, "FinalZone", CFrame.new(0, 0, 0), { Label = "Station Hub" })

	-- +Y COMMAND MODULE ----------------------------------------------------------------------------
	Kit.corridor(root, Vector3.new(0, 22, 0), Vector3.new(0, 72, 0), { pressurized = "cmd_corridor" })
	local cmdCf, cmdSize = CFrame.new(0, 85, 0), Vector3.new(44, 22, 44)
	local win = { w = 30, h = 8, y = 2 }
	local cmd = Kit.room(root, cmdCf, cmdSize, {
		name = "CommandModule", pressurized = "command", deck = true,
		openings = { ["-Y"] = door, ["+Y"] = door, ["+X"] = win, ["-X"] = win, ["+Z"] = win, ["-Z"] = win },
	})
	for _, f in { "+X", "-X", "+Z", "-Z" } do
		Kit.window(cmd, Kit.faceCFrame(cmdCf, cmdSize, f, T / 2) * CFrame.new(0, 2, 0), 30, 8)
	end
	for i = 0, 3 do
		console(cmd, cmdCf * CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.new(0, -9, 16))
	end
	Kit.part(cmd, { Name = "CaptainChair", CFrame = cmdCf * CFrame.new(0, -9.5, 11), Size = Vector3.new(3, 3, 3), Color = P.Blue })
	Kit.sign(cmd, cmdCf * CFrame.new(0, 9, -21.6), "COMMAND MODULE", 16, 2.5)
	Kit.marker(markers, "LootSpot", cmdCf * CFrame.new(14, -8, -10), { Tier = "high", Kind = "locker" })
	Kit.marker(markers, "OxygenStation", cmdCf * CFrame.new(-20, -6, 10) * CFrame.Angles(0, math.rad(90), 0))
	airlockOnFace(root, cmdCf, cmdSize, "+Y")
	Kit.antenna(root, cmdCf * CFrame.new(16, 13, 16), 30)
	Kit.antenna(root, cmdCf * CFrame.new(-16, 13, -16), 22)

	-- -Y DOCKING BAY ---------------------------------------------------------------------------------
	Kit.corridor(root, Vector3.new(0, -22, 0), Vector3.new(0, -62, 0), { pressurized = "dock_corridor" })
	airlockAt(root, Vector3.new(0, -69, 0), Vector3.new(0, -1, 0))
	local bayCf, baySize = CFrame.new(0, -96, 0), Vector3.new(100, 36, 70)
	local bay = Kit.room(root, bayCf, baySize, {
		name = "DockingBay", deck = true, lightColor = Color3.fromRGB(255, 220, 180),
		openings = { ["+Y"] = door, ["-Z"] = true, ["+X"] = { w = 36, h = 24 } },
	})
	-- Hangar door frame and warning stripes
	for _, s in { -1, 1 } do
		Kit.part(bay, { Name = "HangarFrame", CFrame = bayCf * CFrame.new(s * 51, 0, -36), Size = Vector3.new(4, 40, 4), Color = P.Orange,
			Material = Enum.Material.SmoothPlastic })
	end
	Kit.part(bay, { Name = "HangarLintel", CFrame = bayCf * CFrame.new(0, 20, -36), Size = Vector3.new(106, 3, 4), Color = P.HullDark })
	-- Parked shuttle (cover + loot)
	local shuttle = Kit.model("Shuttle", bay)
	local sCf = bayCf * CFrame.new(-18, -10, 6)
	Kit.part(shuttle, { Name = "Fuselage", CFrame = sCf, Size = Vector3.new(14, 7, 26), Color = P.HullLight })
	Kit.part(shuttle, { Name = "Nose", ClassName = "WedgePart", CFrame = sCf * CFrame.new(0, 0, -16) * CFrame.Angles(0, math.rad(180), 0),
		Size = Vector3.new(14, 7, 6), Color = P.HullLight })
	Kit.part(shuttle, { Name = "Canopy", CFrame = sCf * CFrame.new(0, 3.2, -9), Size = Vector3.new(8, 2, 6), Material = Enum.Material.Glass,
		Color = P.Glass, Transparency = 0.4 })
	for _, s in { -1, 1 } do
		Kit.part(shuttle, { Name = "Wing", CFrame = sCf * CFrame.new(s * 11, -1.5, 4), Size = Vector3.new(10, 1, 12), Color = P.Hull })
		local e = Kit.part(shuttle, { Name = "Engine", Shape = Enum.PartType.Cylinder, CFrame = sCf * CFrame.new(s * 4, 0, 14) * CFrame.Angles(0, math.rad(90), 0),
			Size = Vector3.new(3, 4, 4), Material = Enum.Material.Neon, Color = P.BlueGlow })
		Kit.light(e, P.BlueGlow, 16, 1.5)
	end
	Kit.marker(markers, "LootSpot", sCf * CFrame.new(0, 6, 4), { Tier = "mid", Kind = "crate" })
	for _, c in { { 30, -14, 20 }, { 38, -14, -10 }, { 20, -14, -24 } } do
		cargoStack(bay, bayCf * CFrame.new(c[1], c[2], c[3]))
	end
	Kit.marker(markers, "ExplosiveBarrel", bayCf * CFrame.new(40, -15, 8))
	Kit.marker(markers, "ExplosiveBarrel", bayCf * CFrame.new(42, -15, 12))
	Kit.marker(markers, "LootSpot", bayCf * CFrame.new(30, -10, 26), { Tier = "mid", Kind = "crate" })
	Kit.sign(bay, bayCf * CFrame.new(0, 14, 34.6) * CFrame.Angles(0, math.rad(180), 0), "DOCKING BAY 1", 20, 3, P.Orange)
	Kit.marker(markers, "DeployPoint", bayCf * CFrame.new(0, 0, -90))

	-- -X SCIENCE LABS --------------------------------------------------------------------------------
	Kit.corridor(root, Vector3.new(-32, 0, 0), Vector3.new(-100, 0, 0), { pressurized = "lab_corridor" })
	local jCf, jSize = CFrame.new(-120, 0, 0), Vector3.new(36, 24, 36)
	local junction = Kit.room(root, jCf, jSize, {
		name = "LabJunction", pressurized = "lab_junction", deck = true,
		openings = { ["+X"] = door, ["-X"] = door, ["+Z"] = door, ["-Z"] = door, ["+Y"] = door },
	})
	Kit.sign(junction, jCf * CFrame.new(0, 9, -17.6), "SCIENCE LABS", 14, 2.5)
	Kit.marker(markers, "OxygenStation", jCf * CFrame.new(16, -6, 10) * CFrame.Angles(0, math.rad(-90), 0))
	airlockOnFace(root, jCf, jSize, "-X")

	-- Lab A (+Z)
	Kit.corridor(root, jCf * Vector3.new(0, 0, 20), jCf * Vector3.new(0, 0, 50), { pressurized = "labA_corridor" })
	local laCf, laSize = jCf * CFrame.new(0, 0, 68), Vector3.new(40, 20, 32)
	local labA = Kit.room(root, laCf, laSize, { name = "LabA", pressurized = "labA", deck = true, openings = { ["-Z"] = door } })
	for i = -1, 1 do
		Kit.part(labA, { Name = "Bench", CFrame = laCf * CFrame.new(i * 12, -8, 4), Size = Vector3.new(8, 3, 14), Color = P.HullLight })
		local tube = Kit.part(labA, { Name = "SpecimenTube", Shape = Enum.PartType.Cylinder, CFrame = laCf * CFrame.new(i * 12, -3, 10) * CFrame.Angles(0, 0, math.rad(90)),
			Size = Vector3.new(6, 3, 3), Material = Enum.Material.Glass, Color = Color3.fromRGB(80, 220, 180), Transparency = 0.3 })
		Kit.light(tube, Color3.fromRGB(80, 220, 180), 12, 1)
	end
	Kit.marker(markers, "LootSpot", laCf * CFrame.new(-14, -5, -10), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "LootSpot", laCf * CFrame.new(14, 2, -8), { Tier = "low", Kind = "crate" })

	-- Lab B (-Z) - damaged: electrical hazard, smoke, breachable hull plate to space
	Kit.corridor(root, jCf * Vector3.new(0, 0, -20), jCf * Vector3.new(0, 0, -50), { pressurized = "labB_corridor" })
	local lbCf, lbSize = jCf * CFrame.new(0, 0, -68), Vector3.new(40, 20, 32)
	local labB = Kit.room(root, lbCf, lbSize, {
		name = "LabB_Damaged", pressurized = "labB", deck = true, lights = false,
		openings = { ["+Z"] = door, ["-Z"] = { w = 10, h = 10 } },
	})
	local breach = Kit.part(labB, { Name = "WeakHullPlate", CFrame = Kit.faceCFrame(lbCf, lbSize, "-Z", T / 2), Size = Vector3.new(10, 10, 1.6),
		Color = Color3.fromRGB(120, 105, 95), Material = Enum.Material.CorrodedMetal })
	breach:SetAttribute("ZoneId", "labB")
	game:GetService("CollectionService"):AddTag(breach, "Breachable")
	Kit.brokenLight(labB, lbCf * CFrame.new(-8, 9.5, 0))
	Kit.brokenLight(labB, lbCf * CFrame.new(10, 9.5, 6))
	Kit.part(labB, { Name = "FallenBench", CFrame = lbCf * CFrame.new(4, -6, 2) * CFrame.Angles(0.3, 0.5, 0.2), Size = Vector3.new(8, 3, 14), Color = P.HullLight })
	Kit.marker(markers, "ElectricHazard", lbCf * CFrame.new(-10, 0, 4), { Size = Vector3.new(10, 20, 10) })
	Kit.marker(markers, "SmokeVolume", lbCf, { Size = lbSize })
	Kit.marker(markers, "LootSpot", lbCf * CFrame.new(-14, -6, -10), { Tier = "high", Kind = "crate" })

	-- Lab C (+Y)
	Kit.corridor(root, jCf * Vector3.new(0, 14, 0), jCf * Vector3.new(0, 38, 0), { pressurized = "labC_corridor" })
	local lcCf, lcSize = jCf * CFrame.new(0, 49, 0), Vector3.new(30, 18, 30)
	local labC = Kit.room(root, lcCf, lcSize, { name = "LabC_Observatory", pressurized = "labC", deck = true,
		openings = { ["-Y"] = door, ["+Y"] = { w = 18, h = 18 } } })
	Kit.window(labC, Kit.faceCFrame(lcCf, lcSize, "+Y", T / 2), 18, 18)
	Kit.part(labC, { Name = "Telescope", Shape = Enum.PartType.Cylinder, CFrame = lcCf * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(70)),
		Size = Vector3.new(14, 4, 4), Color = P.HullLight })
	Kit.marker(markers, "LootSpot", lcCf * CFrame.new(10, -5, 10), { Tier = "mid", Kind = "locker" })

	-- -Z HYDROPONICS ----------------------------------------------------------------------------------
	Kit.corridor(root, Vector3.new(0, 0, -32), Vector3.new(0, 0, -110), { pressurized = "hydro_corridor" })
	local hyCf, hySize = CFrame.new(0, 0, -140), Vector3.new(56, 24, 56)
	local hydro = Kit.room(root, hyCf, hySize, {
		name = "Hydroponics", pressurized = "hydro", deck = true, lightColor = Color3.fromRGB(200, 255, 210),
		openings = { ["+Z"] = door, ["-Z"] = door, ["+X"] = door },
	})
	for x = -1, 1 do
		for z = -1, 1 do
			local bed = hyCf * CFrame.new(x * 16, -10, z * 16)
			Kit.part(hydro, { Name = "Planter", CFrame = bed, Size = Vector3.new(10, 2, 10), Color = P.HullDark })
			Kit.part(hydro, { Name = "Crop", CFrame = bed * CFrame.new(0, 1.6, 0), Size = Vector3.new(9, 1.2, 9), Color = Color3.fromRGB(70, 160, 60),
				Material = Enum.Material.Grass })
			Kit.strip(hydro, bed * CFrame.new(0, 9, 0), Vector3.new(8, 0.3, 1), Color3.fromRGB(255, 120, 255), x == 0 and z == 0, 40)
		end
	end
	Kit.sign(hydro, hyCf * CFrame.new(0, 9, 27.6) * CFrame.Angles(0, math.rad(180), 0), "HYDROPONICS", 16, 2.5, P.Green)
	Kit.marker(markers, "LootSpot", hyCf * CFrame.new(24, -8, -20), { Tier = "low", Kind = "crate" })
	Kit.marker(markers, "LootSpot", hyCf * CFrame.new(-24, 4, 20), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "OxygenStation", hyCf * CFrame.new(-26, -6, 0) * CFrame.Angles(0, math.rad(90), 0))
	Kit.marker(markers, "FinalZone", hyCf, { Label = "Hydroponics" })
	airlockOnFace(root, hyCf, hySize, "-Z")
	airlockOnFace(root, hyCf, hySize, "+X")

	-- +Z ARMOURY -> OBSERVATION DECK -----------------------------------------------------------------
	Kit.corridor(root, Vector3.new(0, 0, 32), Vector3.new(0, 0, 90), { pressurized = "arm_corridor" })
	local arCf, arSize = CFrame.new(0, 0, 107), Vector3.new(30, 16, 30)
	local armoury = Kit.room(root, arCf, arSize, { name = "Armoury", pressurized = "armoury", deck = true, lightColor = Color3.fromRGB(255, 200, 170),
		openings = { ["-Z"] = door, ["+Z"] = door } })
	lockers(armoury, arCf * CFrame.new(-13.5, -4, 0) * CFrame.Angles(0, math.rad(90), 0), 5)
	lockers(armoury, arCf * CFrame.new(13.5, -4, 0) * CFrame.Angles(0, math.rad(-90), 0), 5)
	Kit.sign(armoury, arCf * CFrame.new(0, 6, -14.6), "ARMOURY", 10, 2, P.Orange)
	Kit.marker(markers, "LootSpot", arCf * CFrame.new(-10, -4, 6), { Tier = "high", Kind = "locker" })
	Kit.marker(markers, "LootSpot", arCf * CFrame.new(10, -4, -6), { Tier = "high", Kind = "locker" })

	Kit.corridor(root, Vector3.new(0, 0, 124), Vector3.new(0, 0, 154), { pressurized = "obs_corridor" })
	local obCf, obSize = CFrame.new(0, 0, 171), Vector3.new(60, 20, 30)
	local obs = Kit.room(root, obCf, obSize, { name = "ObservationDeck", pressurized = "observation", deck = true,
		openings = { ["-Z"] = door, ["+Z"] = { w = 50, h = 14 }, ["+X"] = door, ["-X"] = door } })
	Kit.window(obs, Kit.faceCFrame(obCf, obSize, "+Z", T / 2), 50, 14)
	for i = -2, 2 do
		Kit.part(obs, { Name = "Bench", CFrame = obCf * CFrame.new(i * 10, -8.5, 6), Size = Vector3.new(7, 1.5, 3), Color = P.Blue })
	end
	Kit.marker(markers, "LootSpot", obCf * CFrame.new(-24, -6, -10), { Tier = "low", Kind = "crate" })
	Kit.marker(markers, "OxygenStation", obCf * CFrame.new(20, -6, -13))
	airlockOnFace(root, obCf, obSize, "+X")
	airlockOnFace(root, obCf, obSize, "-X")

	-- +X SPINE, RING JUNCTION, ENGINEERING ---------------------------------------------------------
	local spineR = 12
	local function tubeBetween(x0, x1, name, zone)
		local len = x1 - x0
		return Kit.octTube(root, CFrame.new((x0 + x1) / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0), spineR, len,
			{ name = name, pressurized = zone, caps = { front = true, back = true }, accentColor = P.Blue })
	end
	tubeBetween(32, 183, "SpineForward", "spine1")
	local rjCf, rjSize = CFrame.new(200, 0, 0), Vector3.new(34, 34, 34)
	local tubeHole = { w = 24, h = 24 }
	local rj = Kit.room(root, rjCf, rjSize, { name = "RingJunction", pressurized = "ring_junction", deck = true,
		openings = { ["-X"] = tubeHole, ["+X"] = tubeHole, ["+Y"] = door, ["-Y"] = door } })
	Kit.marker(markers, "LootSpot", rjCf * CFrame.new(0, -12, 12), { Tier = "mid", Kind = "crate" })
	Kit.sign(rj, rjCf * CFrame.new(0, 10, -16.6), "RING ACCESS", 12, 2)
	tubeBetween(217, 300, "SpineAft", "spine2")
	local enCf, enSize = CFrame.new(334, 0, 0), Vector3.new(64, 48, 64)
	local eng = Kit.room(root, enCf, enSize, { name = "Engineering", pressurized = "engineering", deck = true,
		lightColor = Color3.fromRGB(255, 210, 160), openings = { ["-X"] = tubeHole, ["+X"] = door, ["+Z"] = door } })
	local core = Kit.part(eng, { Name = "ReactorCore", Shape = Enum.PartType.Cylinder, CFrame = enCf * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(44, 12, 12), Material = Enum.Material.Neon, Color = Color3.fromRGB(90, 200, 255) })
	Kit.light(core, Color3.fromRGB(90, 200, 255), 50, 3, true)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		Kit.part(eng, { Name = "CoolantPipe", CFrame = enCf * CFrame.new(math.cos(a) * 12, 0, math.sin(a) * 12), Size = Vector3.new(3, 48, 3), Color = P.HullDark })
	end
	for _, c in { { 24, -20, 24 }, { -24, -20, 24 }, { 24, -20, -24 } } do
		cargoStack(eng, enCf * CFrame.new(c[1], c[2], c[3]))
	end
	Kit.marker(markers, "ReactorHazard", enCf, { Size = Vector3.new(22, 48, 22) })
	Kit.marker(markers, "ExplosiveBarrel", enCf * CFrame.new(-26, -21, -26))
	Kit.marker(markers, "LootSpot", enCf * CFrame.new(-24, -18, -20), { Tier = "high", Kind = "crate" })
	Kit.marker(markers, "LootSpot", enCf * CFrame.new(24, 10, -24), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "OxygenStation", enCf * CFrame.new(-30, -16, 10) * CFrame.Angles(0, math.rad(90), 0))
	Kit.sign(eng, enCf * CFrame.new(0, 20, -31.6), "ENGINEERING  -  REACTOR RADIATION", 26, 3, P.Orange)
	airlockOnFace(root, enCf, enSize, "+X")
	airlockOnFace(root, enCf, enSize, "+Z")

	-- HABITAT RING: 8 joint rooms + 8 tube segments in the YZ plane around (200,0,0) -----------------
	local ringC, R = Vector3.new(200, 0, 0), 150
	local jointSize = Vector3.new(30, 30, 30)
	local nodes = {}
	for k = 0, 7 do
		local th = math.rad(k * 45)
		local r = Vector3.new(0, math.cos(th), math.sin(th))
		local cf = CFrame.fromMatrix(ringC + r * R, Vector3.xAxis, r) -- local Y = outward, local Z = tangent
		nodes[k] = { cf = cf, r = r }
		local openings = { ["+Z"] = { w = 26, h = 26 }, ["-Z"] = { w = 26, h = 26 } }
		if k == 0 or k == 4 then openings["-Y"] = door end
		if k == 2 or k == 6 then openings["+Y"] = door end
		local j = Kit.room(root, cf, jointSize, { name = "RingNode" .. k, pressurized = "ring" .. k, deck = false, openings = openings })
		if k % 2 == 1 then
			-- crew quarters: bunks
			for b = -1, 1, 2 do
				Kit.part(j, { Name = "Bunk", CFrame = cf * CFrame.new(b * 11, 10, 0), Size = Vector3.new(6, 2, 12), Color = P.Blue })
				Kit.part(j, { Name = "Bunk", CFrame = cf * CFrame.new(b * 11, 3, 0), Size = Vector3.new(6, 2, 12), Color = P.Blue })
			end
			Kit.marker(markers, "LootSpot", cf * CFrame.new(0, 10, 0), { Tier = "low", Kind = "locker" })
		else
			Kit.marker(markers, "LootSpot", cf * CFrame.new(8, 6, 0), { Tier = "mid", Kind = "crate" })
		end
		if k == 2 or k == 6 then
			airlockOnFace(root, cf, jointSize, "+Y")
			Kit.marker(markers, "OxygenStation", cf * CFrame.new(-13, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
		end
	end
	Kit.marker(markers, "FinalZone", nodes[2].cf, { Label = "Habitat Ring" })
	for k = 0, 7 do
		local a, b = nodes[k], nodes[(k + 1) % 8]
		local pa, pb = a.cf.Position, b.cf.Position
		local d = (pb - pa).Unit
		local s, e = pa + d * 14, pb - d * 14
		local mid = (s + e) / 2
		local outward = (mid - ringC).Unit
		local cf = CFrame.lookAt(mid, e, -outward) -- deck (local -Y) faces outward, like centrifugal "down"
		Kit.octTube(root, cf, 11, (e - s).Magnitude, { name = "RingSegment" .. k, pressurized = "ringseg" .. k,
			caps = { front = true, back = true }, rings = 2, accentColor = P.Blue })
	end
	Kit.corridor(root, Vector3.new(200, 19, 0), (nodes[0].cf * CFrame.new(0, -17, 0)).Position, { pressurized = "spoke_top" })
	Kit.corridor(root, Vector3.new(200, -19, 0), (nodes[4].cf * CFrame.new(0, -17, 0)).Position, { pressurized = "spoke_bottom" })

	-- EXTERIOR: solar arrays, platforms, antennae, hull lights ---------------------------------------
	Kit.solarArray(root, CFrame.new(32, 16, 32) * CFrame.Angles(0, math.rad(-45), 0), 90, 60, 26)
	Kit.solarArray(root, CFrame.new(-32, 16, -32) * CFrame.Angles(0, math.rad(135), 0), 90, 60, 26)
	Kit.solarArray(root, CFrame.new(-32, -16, 32) * CFrame.Angles(0, math.rad(-135), 0) * CFrame.Angles(math.rad(90), 0, 0), 80, 50, 22)
	Kit.solarArray(root, CFrame.new(334, 26, 0) * CFrame.Angles(0, 0, math.rad(90)), 70, 48, 20)
	platform(root, markers, CFrame.new(0, -21, 50), 24, 16, "low")
	platform(root, markers, CFrame.new(-120, -13.5, 30), 20, 14, "low")
	platform(root, markers, CFrame.new(334, 28, 42), 26, 18, "mid")
	platform(root, markers, CFrame.new(0, 97, 40), 20, 14, "mid")
	platform(root, markers, CFrame.new(60, 21, -140), 22, 16, "low")
	Kit.antenna(root, CFrame.new(-120, 12, -12), 26)
	Kit.antenna(root, CFrame.new(0, 12, 171), 18)
	-- Nav beacons on hub corners
	for _, c in { { 1, 1, 1 }, { -1, 1, -1 }, { 1, -1, -1 }, { -1, -1, 1 } } do
		local b = Kit.part(root, { Name = "NavLight", Shape = Enum.PartType.Ball, CFrame = CFrame.new(c[1] * 33, c[2] * 23, c[3] * 33), Size = Vector3.one * 2,
			Material = Enum.Material.Neon, Color = c[2] > 0 and P.Red or P.Green, CanCollide = false })
		Kit.light(b, b.Color, 24, 2)
	end

	-- Deployment points around the station exterior
	for i = 0, 7 do
		local a = math.rad(i * 45 + 10)
		Kit.marker(markers, "DeployPoint", CFrame.new(100 + math.cos(a) * 330, (i % 3 - 1) * 120, math.sin(a) * 330))
	end
	return root
end

return Station
