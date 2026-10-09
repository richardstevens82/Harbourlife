-- Server-validated digging. The client only asks ("dig" / "dump"); the server checks the
-- driver, cooldown, reach and the real bucket position before editing terrain.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Defs = require(game.ReplicatedStorage.Shared.VehicleDefinitions)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Vehicle = require(script.Parent.VehicleService)
local Progression = require(script.Parent.ProgressionService)
local Notify = require(script.Parent.NotificationService)

local E = {}
local terrain = workspace.Terrain
local lastAction: { [Player]: number } = {}

-- ReadVoxels returns a 3D array plus a Size field, so index it numerically.
local function hasTerrain(pos: Vector3): boolean
	local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local mats = terrain:ReadVoxels(region, 4)
	local size = mats.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				local m = mats[x][y][z]
				if m ~= Enum.Material.Air and m ~= Enum.Material.Water then return true end
			end
		end
	end
	return false
end

local function setLoad(a, load)
	a.seat:SetAttribute("Load", load)
	local dirt = a.model:FindFirstChild("BucketDirt")
	if dirt then dirt.Transparency = load > 0 and 0 or 1 end
end

local function puff(tip: Attachment)
	local dust = tip:FindFirstChild("Dust")
	if not dust then return end
	dust.Enabled = true
	task.delay(0.35, function() dust.Enabled = false end)
end

-- Where dumped dirt lands: straight down from the bucket, ignoring the excavator itself.
local function groundBelow(pos: Vector3, model: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(pos, Vector3.new(0, -60, 0), params)
	return hit and hit.Position or pos
end

local function handle(player: Player, action: any)
	if action ~= "dig" and action ~= "dump" then return end
	local now = os.clock()
	if now - (lastAction[player] or 0) < Config.ExcavatorCooldown then return end
	lastAction[player] = now

	local a = Vehicle.GetActive(player)
	if not a or not Defs[a.id].construction or not a.seat.Occupant then return end
	local bucket = a.model:FindFirstChild("Bucket")
	local tip = bucket and bucket:FindFirstChild("Tip")
	if not tip then return end
	local pos = tip.WorldPosition
	if (pos - a.body.Position).Magnitude > Config.ExcavatorMaxReach then return end

	local load = a.seat:GetAttribute("Load") or 0
	if action == "dig" then
		if load >= Config.BucketCapacity then Notify.Send(player, "Bucket full - dump it first", "error"); return end
		if not hasTerrain(pos) then Notify.Send(player, "Nothing to dig here", "error"); return end
		terrain:FillBall(pos, Config.DigRadius, Enum.Material.Air)
		setLoad(a, load + 1)
		puff(tip)
		Progression.AddSkillXp(player, "construction", 3)
	else
		if load <= 0 then Notify.Send(player, "Bucket is empty", "error"); return end
		terrain:FillBall(groundBelow(pos, a.model), Config.DumpRadius, Enum.Material.Ground)
		setLoad(a, load - 1)
		puff(tip)
		Progression.AddSkillXp(player, "construction", 1)
	end
end

function E.Start()
	Remotes.ExcavatorAction.OnServerEvent:Connect(handle)
	game.Players.PlayerRemoving:Connect(function(p) lastAction[p] = nil end)
end

return E
