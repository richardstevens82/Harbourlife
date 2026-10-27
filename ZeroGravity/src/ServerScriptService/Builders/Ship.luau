-- Exploration vessel "ESV Long Horizon": a 550-stud ship parked near the station.
-- Interior chain along the ship's local X axis (bow at -X):
--   Bridge -> Crew Quarters -> Medical/Research -> Cargo Hold -> Engineering -> Engine Room
-- All linked by pressurised corridors. Exterior: dorsal spine (creates a covered hull-traversal
-- channel above the decks), ventral keel, sponsons, three engines, docking arm, antennae.
-- A hidden storage room above the bridge is reachable only by breaching a weak hull plate.
local CollectionService = game:GetService("CollectionService")
local Kit = require(script.Parent.Kit)
local P = Kit.Palette

local Ship = {}
local T = 2

local function airlockOnFace(parent, roomCf: CFrame, size: Vector3, face: string)
	local fcf = Kit.faceCFrame(roomCf, size, face, T)
	local center = (fcf * CFrame.new(0, 0, 7)).Position
	local outward = fcf.LookVector * -1
	local up = math.abs(outward.Y) > 0.9 and fcf.RightVector or fcf.UpVector
	return Kit.airlock(parent, CFrame.lookAt(center, center + outward, up))
end

function Ship.Build(arena: Instance, markers: Instance, shipCf: CFrame)
	local root = Kit.model("ExplorationShip", arena)
	local function L(x, y, z) return shipCf * CFrame.new(x, y, z) end
	local door = { w = 12, h = 12 }

	local function corridor(x0, x1, zone)
		Kit.corridor(root, L(x0, 0, 0).Position, L(x1, 0, 0).Position, { pressurized = zone, color = P.HullLight })
	end

	-- BRIDGE -----------------------------------------------------------------------------------------
	local brCf, brSize = L(-262, 0, 0), Vector3.new(40, 18, 36)
	local bridge = Kit.room(root, brCf, brSize, { name = "Bridge", pressurized = "ship_bridge", deck = true, color = P.HullLight,
		openings = { ["-X"] = { w = 30, h = 10, y = 1 }, ["+X"] = door, ["-Z"] = door, ["+Z"] = { w = 16, h = 6, y = 3 } } })
	Kit.window(bridge, Kit.faceCFrame(brCf, brSize, "-X", T / 2) * CFrame.new(0, 1, 0), 30, 10)
	Kit.window(bridge, Kit.faceCFrame(brCf, brSize, "+Z", T / 2) * CFrame.new(0, 3, 0), 16, 6)
	for i = -1, 1 do
		local c = brCf * CFrame.new(-10, -7, i * 10) * CFrame.Angles(0, math.rad(90), 0)
		Kit.part(bridge, { Name = "Console", CFrame = c, Size = Vector3.new(7, 3, 2.4), Color = P.Gunmetal })
		Kit.part(bridge, { Name = "Screen", CFrame = c * CFrame.new(0, 1.6, -0.3), Size = Vector3.new(6, 1.4, 0.2), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(60, 150, 255), CanCollide = false })
	end
	Kit.part(bridge, { Name = "CommandChair", CFrame = brCf * CFrame.new(4, -7.5, 0), Size = Vector3.new(3.5, 3, 3.5), Color = P.Blue })
	Kit.sign(bridge, brCf * CFrame.new(0, 7, 17.6) * CFrame.Angles(0, math.rad(180), 0), "ESV LONG HORIZON - BRIDGE", 18, 2.5)
	Kit.marker(markers, "LootSpot", brCf * CFrame.new(12, -6, 12), { Tier = "high", Kind = "locker" })
	airlockOnFace(root, brCf, brSize, "-Z")
	-- Nose cone
	Kit.part(root, { Name = "Nose", ClassName = "WedgePart", CFrame = L(-296, -4, 0) * CFrame.Angles(0, math.rad(90), 0),
		Size = Vector3.new(40, 14, 22), Color = P.Hull })

	-- Hidden storage above the bridge (breach the weak plate on its +X face)
	local hdCf, hdSize = L(-262, 17, 0), Vector3.new(16, 8, 16)
	local hidden = Kit.room(root, hdCf, hdSize, { name = "HiddenStorage", deck = true, lightColor = Color3.fromRGB(255, 120, 80),
		openings = { ["+X"] = { w = 7, h = 6 } } })
	local plate = Kit.part(hidden, { Name = "WeakHullPlate", CFrame = Kit.faceCFrame(hdCf, hdSize, "+X", T / 2), Size = Vector3.new(7, 6, 1.6),
		Color = Color3.fromRGB(120, 105, 95), Material = Enum.Material.CorrodedMetal })
	CollectionService:AddTag(plate, "Breachable")
	Kit.marker(markers, "LootSpot", hdCf * CFrame.new(-3, -2, 0), { Tier = "high", Kind = "crate" })
	Kit.marker(markers, "LootSpot", hdCf * CFrame.new(4, -2, 4), { Tier = "high", Kind = "locker" })

	-- CREW QUARTERS ------------------------------------------------------------------------------------
	corridor(-240, -198, "ship_c1")
	local crCf, crSize = L(-166, 0, 0), Vector3.new(60, 20, 40)
	local crew = Kit.room(root, crCf, crSize, { name = "CrewQuarters", pressurized = "ship_crew", deck = true, color = P.HullLight,
		openings = { ["-X"] = door, ["+X"] = door, ["-Z"] = door } })
	for i = -2, 2 do
		for _, s in { -1, 1 } do
			if not (s == -1 and i == 0) then
				local c = crCf * CFrame.new(i * 11, -5, s * 14)
				Kit.part(crew, { Name = "BunkFrame", CFrame = c, Size = Vector3.new(8, 10, 8), Color = P.Gunmetal, Transparency = 0 })
				Kit.part(crew, { Name = "Bunk", CFrame = c * CFrame.new(0, -1, -s * 0.5), Size = Vector3.new(7, 1.5, 7.5), Color = P.Blue })
			end
		end
	end
	Kit.sign(crew, crCf * CFrame.new(0, 8, -19.6), "CREW QUARTERS", 14, 2.5)
	Kit.marker(markers, "LootSpot", crCf * CFrame.new(-22, -7, 0), { Tier = "low", Kind = "locker" })
	Kit.marker(markers, "LootSpot", crCf * CFrame.new(22, -7, 0), { Tier = "low", Kind = "crate" })
	Kit.marker(markers, "OxygenStation", crCf * CFrame.new(28, -6, 10) * CFrame.Angles(0, math.rad(-90), 0))
	airlockOnFace(root, crCf, crSize, "-Z")

	-- MEDICAL / RESEARCH --------------------------------------------------------------------------------
	corridor(-134, -116, "ship_c2")
	local mdCf, mdSize = L(-89, 0, 0), Vector3.new(50, 20, 40)
	local med = Kit.room(root, mdCf, mdSize, { name = "MedicalBay", pressurized = "ship_med", deck = true, color = P.HullLight,
		lightColor = Color3.fromRGB(220, 255, 245), openings = { ["-X"] = door, ["+X"] = door, ["+Z"] = door } })
	for i = -1, 1 do
		Kit.part(med, { Name = "MedBed", CFrame = mdCf * CFrame.new(i * 14, -8, -12), Size = Vector3.new(6, 2, 10), Color = Color3.fromRGB(230, 235, 240) })
		local pod = Kit.part(med, { Name = "StasisPod", Shape = Enum.PartType.Cylinder, CFrame = mdCf * CFrame.new(i * 14, 0, -16) * CFrame.Angles(0, 0, math.rad(90)),
			Size = Vector3.new(12, 5, 5), Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 230, 255), Transparency = 0.35 })
		Kit.light(pod, Color3.fromRGB(150, 230, 255), 10, 0.8)
	end
	Kit.sign(med, mdCf * CFrame.new(0, 8, 19.6) * CFrame.Angles(0, math.rad(180), 0), "MEDICAL / RESEARCH", 16, 2.5, P.Green)
	Kit.marker(markers, "LootSpot", mdCf * CFrame.new(-18, -6, 10), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "LootSpot", mdCf * CFrame.new(18, -6, 10), { Tier = "mid", Kind = "crate" })
	airlockOnFace(root, mdCf, mdSize, "+Z")

	-- CARGO HOLD ---------------------------------------------------------------------------------------
	corridor(-62, -44, "ship_c3")
	local chCf, chSize = L(18, 0, 0), Vector3.new(120, 50, 70)
	local hold = Kit.room(root, chCf, chSize, { name = "CargoHold", pressurized = "ship_cargo", deck = true, color = P.Hull,
		lightColor = Color3.fromRGB(255, 225, 190), openings = { ["-X"] = door, ["+X"] = door, ["-Z"] = door, ["+Z"] = door } })
	-- Catwalks along both long walls at mid height
	for _, s in { -1, 1 } do
		Kit.part(hold, { Name = "Catwalk", CFrame = chCf * CFrame.new(0, 0, s * 29), Size = Vector3.new(110, 1, 8), Color = P.HullDark,
			Material = Enum.Material.DiamondPlate })
		Kit.part(hold, { Name = "CatwalkRail", CFrame = chCf * CFrame.new(0, 2.5, s * 25), Size = Vector3.new(110, 0.5, 0.5), Color = P.Orange })
	end
	-- Container stacks (cover, multiple levels)
	local rng = Random.new(77)
	for i = 0, 9 do
		local x = -48 + (i % 5) * 24
		local z = i < 5 and -10 or 12
		local h = rng:NextInteger(1, 3)
		for lv = 0, h - 1 do
			local colors = { Color3.fromRGB(60, 90, 140), P.HullDark, Color3.fromRGB(150, 80, 40), Color3.fromRGB(70, 110, 80) }
			Kit.crate(hold, chCf * CFrame.new(x, -21 + lv * 8, z) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
				Vector3.new(16, 8, 9), colors[rng:NextInteger(1, #colors)])
		end
	end
	-- Overhead crane
	Kit.part(hold, { Name = "CraneRail", CFrame = chCf * CFrame.new(0, 22, 0), Size = Vector3.new(116, 2, 3), Color = P.Orange })
	Kit.part(hold, { Name = "CraneTrolley", CFrame = chCf * CFrame.new(-10, 19.5, 0), Size = Vector3.new(6, 3, 6), Color = P.Gunmetal })
	Kit.part(hold, { Name = "CraneCable", CFrame = chCf * CFrame.new(-10, 10, 0), Size = Vector3.new(0.5, 16, 0.5), Color = P.HullDark })
	Kit.crate(hold, chCf * CFrame.new(-10, 0, 0), Vector3.new(10, 6, 10), Color3.fromRGB(150, 80, 40))
	Kit.sign(hold, chCf * CFrame.new(0, 18, 34.6) * CFrame.Angles(0, math.rad(180), 0), "CARGO HOLD", 24, 4, P.Orange)
	Kit.marker(markers, "LootSpot", chCf * CFrame.new(-36, -20, 0), { Tier = "high", Kind = "crate" })
	Kit.marker(markers, "LootSpot", chCf * CFrame.new(40, 3, 29), { Tier = "high", Kind = "locker" })
	Kit.marker(markers, "LootSpot", chCf * CFrame.new(0, -20, 28), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", chCf * CFrame.new(-50, 3, -29), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", chCf * CFrame.new(30, 12, -10), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "ExplosiveBarrel", chCf * CFrame.new(52, -22, -26))
	Kit.marker(markers, "ExplosiveBarrel", chCf * CFrame.new(54, -22, -22))
	Kit.marker(markers, "OxygenStation", chCf * CFrame.new(-58, -10, 20) * CFrame.Angles(0, math.rad(90), 0))
	Kit.marker(markers, "FinalZone", chCf, { Label = "Ship Cargo Hold" })
	airlockOnFace(root, chCf, chSize, "-Z")
	airlockOnFace(root, chCf, chSize, "+Z")
	-- Docking arm outside the -Z airlock with a docked courier
	local armCf = chCf * CFrame.new(0, -6, -66)
	Kit.part(root, { Name = "DockingArm", CFrame = armCf, Size = Vector3.new(30, 2, 20), Color = P.HullDark, Material = Enum.Material.DiamondPlate })
	for _, s in { -1, 1 } do
		Kit.part(root, { Name = "Rail", CFrame = armCf * CFrame.new(s * 14.7, 2, 0), Size = Vector3.new(0.5, 0.5, 20), Color = P.Orange })
	end
	Kit.crate(root, armCf * CFrame.new(-8, 4, 4), Vector3.new(8, 6, 6), P.Gunmetal)
	Kit.marker(markers, "LootSpot", armCf * CFrame.new(6, 3, 4), { Tier = "low", Kind = "crate" })

	-- ENGINEERING ---------------------------------------------------------------------------------------
	corridor(80, 98, "ship_c4")
	local enCf, enSize = L(130, 0, 0), Vector3.new(60, 40, 50)
	local eng = Kit.room(root, enCf, enSize, { name = "ShipEngineering", pressurized = "ship_eng", deck = true, color = P.Hull,
		lightColor = Color3.fromRGB(255, 205, 150), openings = { ["-X"] = door, ["+X"] = door, ["-Z"] = door } })
	local core = Kit.part(eng, { Name = "ReactorCore", Shape = Enum.PartType.Cylinder, CFrame = enCf * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(36, 10, 10), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 150, 70) })
	Kit.light(core, Color3.fromRGB(255, 150, 70), 45, 2.5, true)
	for i = 0, 5 do
		local a = math.rad(i * 60)
		Kit.part(eng, { Name = "Conduit", CFrame = enCf * CFrame.new(math.cos(a) * 9, 0, math.sin(a) * 9), Size = Vector3.new(1.6, 40, 1.6), Color = P.Gunmetal })
	end
	Kit.part(eng, { Name = "Generator", CFrame = enCf * CFrame.new(-20, -14, 14), Size = Vector3.new(12, 10, 10), Color = P.HullDark })
	Kit.part(eng, { Name = "Generator", CFrame = enCf * CFrame.new(20, -14, -14), Size = Vector3.new(12, 10, 10), Color = P.HullDark })
	Kit.marker(markers, "ReactorHazard", enCf, { Size = Vector3.new(18, 40, 18) })
	Kit.marker(markers, "LootSpot", enCf * CFrame.new(-20, -6, 14), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", enCf * CFrame.new(22, -16, 16), { Tier = "mid", Kind = "locker" })
	Kit.marker(markers, "OxygenStation", enCf * CFrame.new(0, -14, -23))
	Kit.sign(eng, enCf * CFrame.new(0, 16, 24.6) * CFrame.Angles(0, math.rad(180), 0), "ENGINEERING - RADIATION", 20, 3, P.Orange)
	airlockOnFace(root, enCf, enSize, "-Z")

	-- ENGINE ROOM ----------------------------------------------------------------------------------------
	corridor(162, 178, "ship_c5")
	local erCf, erSize = L(205, 0, 0), Vector3.new(50, 30, 46)
	local er = Kit.room(root, erCf, erSize, { name = "EngineRoom", pressurized = "ship_engineroom", deck = true, lights = false,
		openings = { ["-X"] = door, ["-Y"] = door, ["+Z"] = { w = 10, h = 10 } } })
	for _, z in { -12, 12 } do
		Kit.part(er, { Name = "Turbine", Shape = Enum.PartType.Cylinder, CFrame = erCf * CFrame.new(4, 0, z), Size = Vector3.new(30, 12, 12), Color = P.HullDark })
	end
	Kit.brokenLight(er, erCf * CFrame.new(-10, 14.5, 0))
	Kit.brokenLight(er, erCf * CFrame.new(14, 14.5, 8))
	local erPlate = Kit.part(er, { Name = "WeakHullPlate", CFrame = Kit.faceCFrame(erCf, erSize, "+Z", T / 2), Size = Vector3.new(10, 10, 1.6),
		Color = Color3.fromRGB(120, 105, 95), Material = Enum.Material.CorrodedMetal })
	erPlate:SetAttribute("ZoneId", "ship_engineroom")
	CollectionService:AddTag(erPlate, "Breachable")
	Kit.marker(markers, "ElectricHazard", erCf * CFrame.new(-14, 0, 0), { Size = Vector3.new(8, 30, 14) })
	Kit.marker(markers, "SmokeVolume", erCf, { Size = erSize })
	Kit.marker(markers, "ExplosiveBarrel", erCf * CFrame.new(18, -13, -20))
	Kit.marker(markers, "LootSpot", erCf * CFrame.new(-18, -10, 16), { Tier = "mid", Kind = "crate" })
	airlockOnFace(root, erCf, erSize, "-Y")

	-- Engines
	for _, e in { { 14, 16 }, { 14, -16 }, { -14, 0 } } do
		local ecf = L(250, e[1], e[2]) * CFrame.Angles(0, 0, 0)
		Kit.part(root, { Name = "EngineBell", Shape = Enum.PartType.Cylinder, CFrame = ecf, Size = Vector3.new(34, 22, 22), Color = P.Gunmetal })
		Kit.part(root, { Name = "EngineCollar", Shape = Enum.PartType.Cylinder, CFrame = ecf * CFrame.new(-14, 0, 0), Size = Vector3.new(4, 25, 25), Color = P.Hull })
		local glow = Kit.part(root, { Name = "EngineGlow", Shape = Enum.PartType.Cylinder, CFrame = ecf * CFrame.new(17.2, 0, 0), Size = Vector3.new(1, 18, 18),
			Material = Enum.Material.Neon, Color = P.BlueGlow, CanCollide = false })
		Kit.light(glow, P.BlueGlow, 60, 3)
	end

	-- EXTERIOR HULL ----------------------------------------------------------------------------------------
	-- Dorsal spine on pylons: the gap between deck roofs and the spine is a covered traversal channel.
	Kit.part(root, { Name = "DorsalSpine", CFrame = L(-10, 28.5, 0), Size = Vector3.new(460, 3, 26), Color = P.Hull })
	Kit.part(root, { Name = "DorsalRidge", CFrame = L(-10, 31.5, 0), Size = Vector3.new(420, 3, 8), Color = P.HullDark })
	-- Half-height of whatever deck section sits at ship-local x (pylons start on its outer skin)
	local sections = { { -284, -240, 11 }, { -198, -134, 12 }, { -116, -62, 12 }, { -44, 80, 27 }, { 98, 162, 22 }, { 178, 232, 17 } }
	local function skin(x)
		for _, s in sections do
			if x >= s[1] - 2 and x <= s[2] + 2 then return s[3] end
		end
		return 8 -- corridor
	end
	for x = -230, 210, 40 do
		local base = skin(x)
		if base < 25 then
			Kit.part(root, { Name = "Pylon", CFrame = L(x, (base + 27) / 2, 0), Size = Vector3.new(4, 27 - base, 4), Color = P.HullDark })
		end
		Kit.strip(root, L(x, 30.2, 13.2), Vector3.new(3, 0.6, 0.6), P.BlueGlow, x % 80 == 0, 24)
	end
	Kit.part(root, { Name = "VentralKeel", CFrame = L(-20, -30, 0), Size = Vector3.new(380, 3, 18), Color = P.HullDark })
	for x = -200, 160, 60 do
		local base = skin(x)
		if base < 25 then
			Kit.part(root, { Name = "KeelPylon", CFrame = L(x, -(base + 28.5) / 2, 0), Size = Vector3.new(4, 28.5 - base, 4), Color = P.HullDark })
		end
	end
	-- Sponsons with blue light bands
	for _, s in { -1, 1 } do
		-- kept below airlock height so the side airlocks open onto clear space
		Kit.part(root, { Name = "Sponson", CFrame = L(-30, -20, s * 46), Size = Vector3.new(300, 10, 6), Color = P.Hull })
		Kit.strip(root, L(-30, -20, s * 49.2), Vector3.new(280, 1, 0.4), P.Blue, false)
		Kit.part(root, { Name = "Fin", ClassName = "WedgePart", CFrame = L(220, 14, s * 30) * CFrame.Angles(0, math.rad(-90), 0),
			Size = Vector3.new(4, 30, 40), Color = P.HullDark })
	end
	Kit.antenna(root, L(-150, 31, 0), 26)
	Kit.antenna(root, L(100, 31, 6), 18)
	Kit.solarArray(root, L(60, 33, 0) * CFrame.Angles(0, 0, math.rad(90)), 30, 50, 18)
	-- Hull-route loot (exterior risk, decent reward)
	Kit.marker(markers, "LootSpot", L(-120, 25, 0), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", L(150, 25, 6), { Tier = "mid", Kind = "crate" })
	Kit.marker(markers, "LootSpot", L(-60, -26, 0), { Tier = "low", Kind = "crate" })
	Kit.sign(root, L(-89, 4, -22.4) * CFrame.Angles(0, math.rad(180), 0), "ESV LONG HORIZON", 40, 6, P.HullLight)

	for i, off in { { -200, 0, -110 }, { -60, 60, -120 }, { 80, -50, -130 }, { 200, 40, 110 }, { 0, 70, 120 }, { -250, -40, 100 } } do
		Kit.marker(markers, "DeployPoint", L(off[1], off[2], off[3]))
		local _ = i
	end
	return root
end

return Ship
