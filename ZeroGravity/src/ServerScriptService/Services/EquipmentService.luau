-- Equipment: tether (grapple to an approved surface, then the client reels itself in) and the
-- thrown pulse charge. Boost energy is simulated on the client for responsiveness; the server's
-- speed ceiling in SecurityService bounds it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Security = require(script.Parent.SecurityService)
local Inventory = require(script.Parent.InventoryService)
local Combat = require(script.Parent.CombatService)

local Equipment = {}
local tetherReadyAt: { [Player]: number } = {}
local grenadeReadyAt: { [Player]: number } = {}
local tethered: { [Player]: number } = {}

local function rootOf(p: Player): BasePart?
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function canUse(player: Player): boolean
	if Roster.IsActive(player) then return true end
	local inv = Inventory.Get(player)
	return inv ~= nil and inv.practice and rootOf(player) ~= nil
end

-- Approved anchor: any anchored, collidable world part or terrain; never a character or pickup.
local function approved(inst: Instance): boolean
	if inst:IsA("Terrain") then return true end
	if not inst:IsA("BasePart") or not inst.Anchored or not inst.CanCollide then return false end
	local model = inst:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return false end
	return inst:IsDescendantOf(workspace:FindFirstChild("Arena") or workspace) or inst:IsDescendantOf(workspace:FindFirstChild("Lobby") or workspace)
end

local function onTether(player: Player, target)
	if not Security.IsVector(target) or not canUse(player) then return end
	local root = rootOf(player)
	if not root then return end
	local now = os.clock()
	if now < (tetherReadyAt[player] or 0) then return end
	local offset = target - root.Position
	if offset.Magnitude > Config.Tether.Range + 6 or offset.Magnitude < 3 then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local hit = workspace:Raycast(root.Position, offset.Unit * (offset.Magnitude + 4), params)
	if not hit or (hit.Position - target).Magnitude > 8 or not approved(hit.Instance) then
		Remotes.Equipment:FireClient(player, { t = "tetherDenied" })
		return
	end
	if not Inventory.TakeUtility(player, "tether") then
		Remotes.Equipment:FireClient(player, { t = "tetherDenied", reason = "No tether charges" })
		return
	end
	tetherReadyAt[player] = now + Config.Tether.Cooldown
	tethered[player] = now + Config.Tether.MaxDuration
	Security.AllowBurst(player, Config.Tether.MaxDuration + 1)
	Remotes.Equipment:FireClient(player, { t = "tether", point = hit.Position, duration = Config.Tether.MaxDuration })
	for _, p in Players:GetPlayers() do
		if p ~= player then Remotes.FX:FireClient(p, { t = "tether", player = player, point = hit.Position, duration = Config.Tether.MaxDuration }) end
	end
end

local function onRelease(player: Player)
	if tethered[player] then
		tethered[player] = nil
		Remotes.FX:FireAllClients({ t = "tetherEnd", player = player })
	end
end

local function onGrenade(player: Player, dir)
	if not Security.IsVector(dir) or dir.Magnitude < 0.5 or not Roster.IsActive(player) then return end
	local root = rootOf(player)
	if not root then return end
	local now = os.clock()
	if now < (grenadeReadyAt[player] or 0) then return end
	if not Inventory.TakeUtility(player, "grenade") then return end
	grenadeReadyAt[player] = now + Config.Grenade.Cooldown
	local G = Config.Grenade
	dir = dir.Unit
	if dir:Dot(root.CFrame.LookVector) < 0 then dir = root.CFrame.LookVector end
	local pos = root.Position + dir * 3
	local vel = dir * G.Speed + root.AssemblyLinearVelocity
	local ball = Instance.new("Part")
	ball.Name = "PulseCharge"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 1.2
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 140, 60)
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
	ball.CFrame = CFrame.new(pos)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = ball.Color, 12, 2
	light.Parent = ball
	ball.Parent = workspace
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, ball }
	local born = os.clock()
	local stuck = false
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local age = os.clock() - born
		if age >= G.Fuse or not ball.Parent then
			conn:Disconnect()
			if ball.Parent then
				local p = ball.Position
				ball:Destroy()
				Combat.Explode(p, G.Radius, G.Damage, player.Parent and player or nil)
			end
			return
		end
		light.Brightness = 1 + math.abs(math.sin(age * 12)) * 3
		if stuck then return end
		local step = vel * dt
		local hit = workspace:Raycast(ball.Position, step, params)
		if hit then
			ball.CFrame = CFrame.new(hit.Position + hit.Normal * 0.6)
			stuck = true -- magnetic charge clamps to whatever it hits
		else
			ball.CFrame += step
		end
	end)
end

Equipment.ThrowGrenade = onGrenade -- bot entry point (same checks as the remote)

function Equipment.Start()
	Remotes.Equipment.OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or not Security.RateLimit(player, "equipment", 6, 4) then return end
		if req.action == "tether" then
			onTether(player, req.target)
		elseif req.action == "tetherRelease" then
			onRelease(player)
		elseif req.action == "grenade" then
			onGrenade(player, req.dir)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		tetherReadyAt[p], grenadeReadyAt[p], tethered[p] = nil, nil, nil
	end)
end

return Equipment
