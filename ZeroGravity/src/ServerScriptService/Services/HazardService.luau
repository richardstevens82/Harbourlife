-- Environmental systems: interlocked airlocks, telegraphed electrical faults, reactor radiation,
-- explosive cargo barrels, breachable weak hull plates and smoke in damaged compartments.
-- Reset() restores barrels and hull plates between matches.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Combat = require(script.Parent.CombatService)
local Oxygen = require(script.Parent.OxygenService)

local Hazards = {}
local airlocks: { [Model]: any } = {} -- model -> { request = fn(doorPart, who), state, inner, outer }
local H = Config.Hazards
local barrelFolder: Folder

local function inside(cf: CFrame, size: Vector3, pos: Vector3): boolean
	local lp = cf:PointToObjectSpace(pos)
	return math.abs(lp.X) <= size.X / 2 and math.abs(lp.Y) <= size.Y / 2 and math.abs(lp.Z) <= size.Z / 2
end

local function playersInside(cf: CFrame, size: Vector3): { Player }
	local out = {}
	for _, p in Roster.Active() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and inside(cf, size, root.Position) then table.insert(out, p) end
	end
	return out
end

-- AIRLOCKS ---------------------------------------------------------------------------------------
local function setupAirlock(model: Model)
	local inner = model:FindFirstChild("InnerDoor") :: BasePart?
	local outer = model:FindFirstChild("OuterDoor") :: BasePart?
	local lamp = model:FindFirstChild("StatusLamp") :: BasePart?
	if not (inner and outer and lamp) then return end
	local state = { open = nil :: BasePart?, busy = false, serial = 0 }
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local function move(door: BasePart, open: boolean)
		local closed = door:GetAttribute("ClosedCFrame") :: CFrame
		local goal = open and closed + (door:GetAttribute("OpenOffset") :: Vector3) or closed
		TweenService:Create(door, info, { CFrame = goal }):Play()
		local stripe = model:FindFirstChild(door.Name .. "Stripe") :: BasePart?
		if stripe then TweenService:Create(stripe, info, { CFrame = goal }):Play() end
	end
	local function setLamp(color: Color3)
		lamp.Color = color
		local l = lamp:FindFirstChildOfClass("PointLight")
		if l then l.Color = color end
	end
	local function request(door: BasePart, player: Player)
		if state.busy then return end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - door.Position).Magnitude > 18 then return end
		state.serial += 1
		local my = state.serial
		if state.open == door then
			move(door, false)
			state.open = nil
			return
		end
		state.busy = true
		local other = state.open
		if other then
			-- interlock: close the other door and cycle pressure before opening this one
			move(other, false)
			state.open = nil
			setLamp(Color3.fromRGB(255, 150, 40))
			Remotes.FX:FireAllClients({ t = "airlock", pos = model:GetPivot().Position })
			task.wait(1.6)
		end
		move(door, true)
		state.open = door
		setLamp(Color3.fromRGB(70, 200, 110))
		state.busy = false
		task.delay(7, function()
			if state.serial == my and state.open == door then
				move(door, false)
				state.open = nil
			end
		end)
	end
	for _, door in { inner, outer } do
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = "Cycle"
		pr.ObjectText = door == inner and "Airlock (inner)" or "Airlock (outer)"
		pr.KeyboardKeyCode = Enum.KeyCode.F
		pr.HoldDuration = 0.2
		pr.MaxActivationDistance = 12
		pr.RequiresLineOfSight = false
		pr.Parent = door
		pr.Triggered:Connect(function(player) task.spawn(request, door, player) end)
	end
	-- Outer doors start closed; inner doors start open so interiors read as connected spaces.
	move(inner, true)
	state.open = inner
	airlocks[model] = { request = request, state = state, inner = inner, outer = outer }
end

-- Bot entry points: open a given airlock door (same interlock and distance rules as the prompt).
function Hazards.IsAirlockDoorOpen(model: Model, doorName: string): boolean
	local a = airlocks[model]
	return a ~= nil and a.state.open ~= nil and a.state.open.Name == doorName
end

function Hazards.RequestAirlockDoor(model: Model, doorName: string, who)
	local a = airlocks[model]
	if not a or a.state.busy or Hazards.IsAirlockDoorOpen(model, doorName) then return end
	task.spawn(a.request, doorName == "InnerDoor" and a.inner or a.outer, who)
end

-- ELECTRICAL FAULTS --------------------------------------------------------------------------------
local function setupElectric(marker: BasePart)
	local size = marker:GetAttribute("Size") or Vector3.new(10, 10, 10)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "ElectricFault"
	emitterPart.Size = size
	emitterPart.CFrame = marker.CFrame
	emitterPart.Transparency = 1
	emitterPart.Anchored, emitterPart.CanCollide, emitterPart.CanQuery, emitterPart.CanTouch = true, false, false, false
	emitterPart.Parent = marker.Parent
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(140, 210, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Speed = NumberRange.new(8, 18)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Rate = 4
	sparks.Parent = emitterPart
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(140, 210, 255), math.max(size.X, size.Z) * 1.4, 0.3
	light.Parent = emitterPart
	CollectionService:AddTag(emitterPart, "ElectricFault")
	task.spawn(function()
		while emitterPart.Parent do
			emitterPart:SetAttribute("State", "idle")
			sparks.Rate, light.Brightness = 4, 0.3
			task.wait(H.ElectricIdle)
			emitterPart:SetAttribute("State", "warn") -- clients flicker the light and play crackle
			sparks.Rate, light.Brightness = 25, 1.2
			task.wait(H.ElectricWarn)
			emitterPart:SetAttribute("State", "active")
			sparks.Rate, light.Brightness = 200, 4
			for _, p in playersInside(emitterPart.CFrame, size) do
				Combat.ApplyDamage(p, H.ElectricDamage, nil, "electric", emitterPart.Position)
			end
			task.wait(H.ElectricActive)
		end
	end)
end

-- REACTOR RADIATION ------------------------------------------------------------------------------
local reactors = {}
local function setupReactor(marker: BasePart)
	table.insert(reactors, { cf = marker.CFrame, size = marker:GetAttribute("Size") or Vector3.new(20, 20, 20) })
end

-- BARRELS --------------------------------------------------------------------------------------------
local function spawnBarrel(marker: BasePart)
	local b = Instance.new("Part")
	b.Name = "ExplosiveCargo"
	b.Shape = Enum.PartType.Cylinder
	b.Size = Vector3.new(3.6, 2.6, 2.6)
	b.CFrame = marker.CFrame * CFrame.Angles(0, 0, math.rad(90))
	b.Anchored = true
	b.Color = Color3.fromRGB(200, 60, 30)
	b.Material = Enum.Material.Metal
	b:SetAttribute("Health", H.BarrelHealth)
	local band = Instance.new("Part")
	band.Name = "HazardBand"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.6, 2.7, 2.7)
	band.CFrame = b.CFrame
	band.Anchored, band.CanCollide, band.CanQuery = true, false, false
	band.Color = Color3.fromRGB(255, 200, 40)
	band.Material = Enum.Material.Neon
	band.Parent = b
	CollectionService:AddTag(b, "ExplosiveBarrelProp")
	b.Parent = barrelFolder
end

local function damageBarrel(b: BasePart, dmg: number, attacker: Player?)
	if b:GetAttribute("Fused") then return end
	local hp = ((b:GetAttribute("Health") :: number?) or 0) - dmg
	b:SetAttribute("Health", hp)
	if hp > 0 then return end
	b:SetAttribute("Fused", true)
	local band = b:FindFirstChild("HazardBand") :: BasePart?
	if band then band.Color = Color3.fromRGB(255, 40, 40) end
	Remotes.FX:FireAllClients({ t = "fuse", pos = b.Position })
	task.delay(H.BarrelFuse, function()
		if not b.Parent then return end
		local pos = b.Position
		CollectionService:RemoveTag(b, "ExplosiveBarrelProp")
		b:Destroy()
		Combat.Explode(pos, H.BarrelRadius, H.BarrelDamage, attacker and attacker.Parent and attacker or nil)
	end)
end

-- BREACHABLE PLATES -----------------------------------------------------------------------------------
local function damageBreach(plate: BasePart, dmg: number)
	if plate:GetAttribute("Breached") then return end
	local hp = ((plate:GetAttribute("Health") :: number?) or H.BreachHealth) - dmg
	plate:SetAttribute("Health", hp)
	if hp > 0 then
		plate.Color = plate.Color:Lerp(Color3.fromRGB(60, 40, 30), 0.15)
		return
	end
	plate:SetAttribute("Breached", true)
	plate.CanCollide = false
	plate.CanQuery = false
	plate.Transparency = 1
	Remotes.FX:FireAllClients({ t = "explosion", pos = plate.Position, radius = 8 })
	local zone = plate:GetAttribute("ZoneId")
	if zone then
		Oxygen.SetBreached(zone, true)
		Remotes.FX:FireAllClients({ t = "notice", text = "Hull breach detected - compartment depressurised", color = Color3.fromRGB(255, 150, 60) })
	end
end

function Hazards.Reset()
	barrelFolder:ClearAllChildren()
	for _, m in CollectionService:GetTagged("ExplosiveBarrel") do
		if m:IsA("BasePart") then spawnBarrel(m) end
	end
	for _, plate in CollectionService:GetTagged("Breachable") do
		if plate:IsA("BasePart") then
			plate:SetAttribute("Breached", nil)
			plate:SetAttribute("Health", H.BreachHealth)
			plate.CanCollide, plate.CanQuery, plate.Transparency = true, true, 0
			plate.Color = Color3.fromRGB(120, 105, 95)
			local zone = plate:GetAttribute("ZoneId")
			if zone then Oxygen.SetBreached(zone, false) end
		end
	end
end

function Hazards.Start()
	barrelFolder = Instance.new("Folder")
	barrelFolder.Name = "Barrels"
	barrelFolder.Parent = workspace:FindFirstChild("Arena") or workspace
	for _, m in CollectionService:GetTagged("Airlock") do
		if m:IsA("Model") then setupAirlock(m) end
	end
	for _, m in CollectionService:GetTagged("ElectricHazard") do
		if m:IsA("BasePart") then setupElectric(m) end
	end
	for _, m in CollectionService:GetTagged("ReactorHazard") do
		if m:IsA("BasePart") then setupReactor(m) end
	end
	for _, m in CollectionService:GetTagged("SmokeVolume") do
		if m:IsA("BasePart") then
			local size = m:GetAttribute("Size") or Vector3.new(20, 10, 20)
			for i = -1, 1 do
				local a = Instance.new("Attachment")
				a.Position = Vector3.new(i * size.X / 3, 0, 0)
				a.Parent = m
				local s = Instance.new("Smoke")
				s.Color = Color3.fromRGB(90, 90, 95)
				s.Opacity = 0.18
				s.RiseVelocity = 0.5
				s.Size = math.min(size.X, size.Z) / 3
				s.Parent = a
			end
		end
	end
	Combat.OnTargetDamaged = function(part: BasePart, dmg: number, attacker: Player?)
		if CollectionService:HasTag(part, "ExplosiveBarrelProp") then
			damageBarrel(part, dmg, attacker)
		elseif CollectionService:HasTag(part, "Breachable") then
			damageBreach(part, dmg)
		end
	end
	Hazards.Reset()
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, r in reactors do
				for _, p in playersInside(r.cf, r.size) do
					Combat.ApplyDamage(p, H.ReactorDps * 0.5, nil, "radiation", r.cf.Position)
				end
			end
		end
	end)
end

return Hazards
