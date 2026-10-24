-- Builds the whole battlefield once at server start: lighting, lobby, station, exploration ship,
-- asteroid field, derelicts and debris. Gameplay systems discover what they need through
-- CollectionService tags on markers (LootSpot, DeployPoint, FinalZone, OxygenStation,
-- Pressurized, Airlock, ElectricHazard, ReactorHazard, ExplosiveBarrel, Breachable, ...).
local Builders = script.Parent.Parent:WaitForChild("Builders")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Kit = require(Builders.Kit)

local WorldBuilder = {}

WorldBuilder.ShipCFrame = CFrame.new(150, 60, -600)

local function step(name: string, fn)
	local t0 = os.clock()
	local before = Kit.Stats.parts
	local ok, err = pcall(fn)
	if ok then
		print(string.format("[ZG] built %-14s %5d parts  %.2fs", name, Kit.Stats.parts - before, os.clock() - t0))
	else
		warn("[ZG] building " .. name .. " failed: " .. tostring(err))
	end
end

function WorldBuilder.Start()
	local old = workspace:FindFirstChild("Arena")
	if old then old:Destroy() end
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = workspace
	local markers = Kit.folder("Markers", arena)
	workspace.Terrain:Clear()
	for _, s in workspace:GetChildren() do
		if s:IsA("SpawnLocation") then s:Destroy() end
	end

	step("Backdrop", function() require(Builders.Backdrop).Apply() end)
	step("Lobby", function() require(Builders.Lobby).Build(workspace, Config.Arena.LobbyCenter) end)
	step("Station", function() require(Builders.Station).Build(arena, markers) end)
	step("Ship", function() require(Builders.Ship).Build(arena, markers, WorldBuilder.ShipCFrame) end)

	local Debris = require(Builders.Debris)
	local stationScale = require(Builders.Station).Scale
	local exclusion = {
		{ center = Vector3.new(110, 0, 0) * stationScale, radius = 420 * stationScale }, -- station
		{ center = WorldBuilder.ShipCFrame.Position, radius = 340 }, -- ship
	}
	for _, e in Debris.Exclusions() do table.insert(exclusion, e) end
	local asteroids = {}
	step("Asteroids", function()
		local _, placed = require(Builders.AsteroidField).Build(arena, markers, workspace.Terrain, exclusion)
		asteroids = placed
	end)
	local debrisExclusion = table.clone(exclusion)
	for _, a in asteroids do table.insert(debrisExclusion, { center = a.p, radius = a.r + 10 }) end
	step("Debris", function() Debris.Build(arena, markers, debrisExclusion) end)

	-- Hard boundary marker for clients (tactical map / warnings)
	arena:SetAttribute("HardRadius", Config.Arena.HardRadius)
	print(string.format("[ZG] world complete: %d parts", Kit.Stats.parts))
end

return WorldBuilder
