-- Vehicle ownership, spawning, fuel, wear and repair. Server-authoritative.
-- Driving physics run on the driver's client (VehicleDriver.client.luau) via constraints built here.
-- Workspace markers:
--   VehicleGarage_<id>   toggle: store current vehicle / take out <id>
--   VehicleShop_<id>     buy vehicle <id>
--   FuelStation          refuel active vehicle (must be nearby)
--   Garage_Repair        repair active vehicle (must be nearby)
--   VehicleSpawn         where vehicles appear (falls back to in front of the player)
local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Shared.Config)
local Defs = require(game.ReplicatedStorage.Shared.VehicleDefinitions)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local Notify = require(script.Parent.NotificationService)

local V = {}
local active: { [Player]: { id: string, model: Model, body: BasePart, seat: VehicleSeat, fuel: number, condition: number } } = {}

local function part(parent, name, size, cf, color, collide)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color
	p.CanCollide = collide ~= false; p.Massless = collide == false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint"); w.Part0 = a; w.Part1 = b; w.Parent = a
end

local function build(id, def, cf, player, fuel, condition)
	local model = Instance.new("Model"); model.Name = player.Name .. "_" .. id
	local s = def.size
	local body = part(model, "Body", s, cf, def.color)
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	model.PrimaryPart = body

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"; seat.Size = Vector3.new(2, 1, 2); seat.MaxSpeed = 0; seat.Torque = 0
	seat.CFrame = cf * CFrame.new(0, s.Y / 2 + 0.5, s.Z * 0.1)
	seat.Parent = model; weld(body, seat)

	local wheelSize = Vector3.new(1.5, 2.2, 2.2)
	for _, x in { -s.X / 2, s.X / 2 } do
		for _, z in { -s.Z / 2 + 2, s.Z / 2 - 2 } do
			local w = part(model, "Wheel", wheelSize, cf * CFrame.new(x, -s.Y / 2 + 0.2, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(25, 25, 25), false)
			w.Shape = Enum.PartType.Cylinder; weld(body, w)
		end
	end
	if def.construction then -- excavator: cab, boom and bucket
		weld(body, part(model, "Cab", Vector3.new(5, 4, 5), cf * CFrame.new(0, s.Y / 2 + 2, s.Z * 0.2), def.color, false))
		weld(body, part(model, "Boom", Vector3.new(1.5, 1.5, 11), cf * CFrame.new(0, s.Y / 2 + 3, -s.Z / 2 - 2) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(200, 150, 20), false))
		weld(body, part(model, "Bucket", Vector3.new(4, 2, 3), cf * CFrame.new(0, s.Y / 2 - 1, -s.Z / 2 - 8), Color3.fromRGB(90, 90, 90), false))
	end

	local att = Instance.new("Attachment"); att.Parent = body
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"; drive.Attachment0 = att; drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.xAxis; drive.SecondaryTangentAxis = Vector3.zAxis
	drive.PlaneVelocity = Vector2.zero; drive.Parent = body
	local turn = Instance.new("AngularVelocity")
	turn.Name = "Turn"; turn.Attachment0 = att; turn.RelativeTo = Enum.ActuatorRelativeTo.World
	turn.AngularVelocity = Vector3.zero; turn.Parent = body

	model.Parent = workspace
	local mass = body.AssemblyMass
	drive.MaxForce = mass * 60 -- horizontal only; gravity is untouched in Plane mode
	turn.MaxTorque = mass * 4000

	seat:SetAttribute("VehicleId", id)
	seat:SetAttribute("OwnerUserId", player.UserId)
	seat:SetAttribute("MaxSpeed", def.maxSpeed)
	seat:SetAttribute("TurnRate", def.turnRate)
	seat:SetAttribute("Fuel", fuel)
	seat:SetAttribute("FuelCapacity", def.fuelCapacity)
	seat:SetAttribute("Condition", condition)
	seat:SetAttribute("Disabled", fuel <= 0)

	-- only the owner may drive
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		if not hum then return end
		local occupant = Players:GetPlayerFromCharacter(hum.Parent)
		if occupant ~= player then
			task.defer(function() hum.Sit = false; hum.Jump = true end)
			if occupant then Notify.Send(occupant, "This is " .. player.Name .. "'s vehicle", "error") end
		end
	end)
	return model, body, seat
end

local function spawnCFrame(player)
	local sp = workspace:FindFirstChild("VehicleSpawn", true)
	if sp and sp:IsA("BasePart") then return sp.CFrame * CFrame.new(0, 4, 0) end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return CFrame.new(hrp.Position + hrp.CFrame.LookVector * 14 + Vector3.new(0, 4, 0), hrp.Position + hrp.CFrame.LookVector * 30)
end

function V.Despawn(player: Player)
	local a = active[player]
	if not a then return end
	active[player] = nil
	local d = DataService.Get(player)
	if d and d.vehicles[a.id] then d.vehicles[a.id].fuel = a.fuel; d.vehicles[a.id].condition = a.condition end
	a.model:Destroy()
end

function V.Spawn(player: Player, id: string): boolean
	local d, def = DataService.Get(player), Defs[id]
	if not d or not def or not d.vehicles[id] then return false end
	V.Despawn(player)
	local cf = spawnCFrame(player)
	if not cf then return false end
	local rec = d.vehicles[id]
	local model, body, seat = build(id, def, cf, player, rec.fuel, rec.condition)
	active[player] = { id = id, model = model, body = body, seat = seat, fuel = rec.fuel, condition = rec.condition }
	Notify.Send(player, def.name .. " ready", "success")
	return true
end

function V.Buy(player: Player, id: string): boolean
	local d, def = DataService.Get(player), Defs[id]
	if not d or not def then return false end
	if d.vehicles[id] then Notify.Send(player, "You already own a " .. def.name, "error"); return false end
	if not Economy.SpendCash(player, def.price) then Notify.Send(player, "Need $" .. def.price, "error"); return false end
	d.vehicles[id] = { fuel = def.fuelCapacity, condition = 100 }
	DataService.Push(player)
	Notify.Send(player, "Bought " .. def.name, "success")
	return true
end

local function near(a, station, range)
	return a and (a.body.Position - station.Position).Magnitude <= range
end

local function refuel(player, station)
	local a = active[player]
	if not near(a, station, Config.VehicleServiceRange) then Notify.Send(player, "Bring your vehicle to the pump", "error"); return end
	local cap = Defs[a.id].fuelCapacity
	local want = math.ceil(cap - a.fuel)
	local d = DataService.Get(player)
	if want <= 0 or not d then Notify.Send(player, "Tank is full", "info"); return end
	local units = math.min(want, math.floor(d.cash / Config.FuelPricePerUnit))
	if units <= 0 or not Economy.SpendCash(player, units * Config.FuelPricePerUnit) then Notify.Send(player, "Not enough cash", "error"); return end
	a.fuel = math.min(cap, a.fuel + units)
	a.seat:SetAttribute("Fuel", a.fuel); a.seat:SetAttribute("Disabled", false)
	Notify.Send(player, "Refuelled: $" .. units * Config.FuelPricePerUnit, "success")
end

local function repair(player, station)
	local a = active[player]
	if not near(a, station, Config.VehicleServiceRange) then Notify.Send(player, "Bring your vehicle to the garage", "error"); return end
	local missing = 100 - a.condition
	local cost = math.ceil(missing * Config.RepairPricePerPoint)
	if cost <= 0 then Notify.Send(player, "No repairs needed", "info"); return end
	if not Economy.SpendCash(player, cost) then Notify.Send(player, "Repairs cost $" .. cost, "error"); return end
	a.condition = 100
	a.seat:SetAttribute("Condition", 100)
	Notify.Send(player, "Repaired: $" .. cost, "success")
end

local function hook(inst: Instance)
	if not inst:IsA("BasePart") then return end
	local garageId = inst.Name:match("^VehicleGarage_(.+)$")
	local shopId = inst.Name:match("^VehicleShop_(.+)$")
	if garageId and Defs[garageId] then
		Interaction.Register(inst, { action = "Take out / store", object = Defs[garageId].name, onTriggered = function(p)
			local a = active[p]
			if a and a.id == garageId then V.Despawn(p); Notify.Send(p, "Vehicle stored", "info")
			elseif not V.Spawn(p, garageId) then Notify.Send(p, "You don't own a " .. Defs[garageId].name, "error") end
		end })
	elseif shopId and Defs[shopId] then
		Interaction.Register(inst, { action = "Buy $" .. Defs[shopId].price, object = Defs[shopId].name, onTriggered = function(p) V.Buy(p, shopId) end })
	elseif inst.Name == "FuelStation" then
		Interaction.Register(inst, { action = "Refuel", object = "Fuel Pump", onTriggered = function(p) refuel(p, inst) end })
	elseif inst.Name == "Garage_Repair" then
		Interaction.Register(inst, { action = "Repair", object = "Mechanic", onTriggered = function(p) repair(p, inst) end })
	end
end

function V.Start()
	for _, d in workspace:GetDescendants() do hook(d) end
	workspace.DescendantAdded:Connect(hook)
	Players.PlayerRemoving:Connect(V.Despawn)
	-- one loop for every vehicle: fuel use and wear only while moving with a driver
	task.spawn(function()
		while true do
			task.wait(1)
			for player, a in active do
				if not a.model.Parent then active[player] = nil; continue end
				local def = Defs[a.id]
				if a.seat.Occupant and a.body.AssemblyLinearVelocity.Magnitude > 2 then
					a.fuel = math.max(0, a.fuel - def.fuelPerSecond)
					a.condition = math.max(0, a.condition - def.wearPerSecond)
					a.seat:SetAttribute("Fuel", a.fuel); a.seat:SetAttribute("Condition", a.condition)
					a.seat:SetAttribute("Disabled", a.fuel <= 0)
					local d = DataService.Get(player)
					if d and d.vehicles[a.id] then d.vehicles[a.id].fuel = a.fuel; d.vehicles[a.id].condition = a.condition end
				end
			end
		end
	end)
end

return V
