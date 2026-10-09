-- Dev-only placeholder test area. Builds labelled, correctly named Parts near the origin
-- so every Phase 1/2 system can be exercised. Delete or set Enabled=false once the real map exists.
local TestWorld = { Enabled = true }

local function pad(name: string, pos: Vector3, color: Color3, size: Vector3?)
	if workspace:FindFirstChild(name, true) then return end -- never duplicate or overwrite map objects
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size or Vector3.new(6, 4, 6)
	p.Position = pos
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = name
	label.Parent = gui
end

function TestWorld.Start()
	if not TestWorld.Enabled then return end
	game.Players.PlayerAdded:Connect(function(p) task.spawn(TestWorld.GrantExcavator, p) end)
	for _, p in game.Players:GetPlayers() do task.spawn(TestWorld.GrantExcavator, p) end
	if not workspace:FindFirstChild("TestFloor") then
		local f = Instance.new("Part")
		f.Name = "TestFloor"; f.Anchored = true
		f.Size = Vector3.new(120, 1, 120); f.Position = Vector3.new(0, -0.5, 0)
		f.Color = Color3.fromRGB(90, 140, 90); f.Parent = workspace
	end
	if not workspace:FindFirstChild("DigZoneSign") then
		workspace.Terrain:FillBlock(CFrame.new(80, 0, -30), Vector3.new(40, 16, 40), Enum.Material.Ground)
		pad("DigZoneSign", Vector3.new(58, 2, -30), Color3.fromRGB(240, 190, 30), Vector3.new(2, 4, 8))
	end
	pad("JobCentre_pizza_cook", Vector3.new(-30, 2, 0), Color3.fromRGB(60, 120, 220))
	pad("JobCentre_delivery_driver", Vector3.new(-30, 2, 12), Color3.fromRGB(60, 120, 220))
	pad("PizzaSupplier", Vector3.new(-10, 2, -20), Color3.fromRGB(150, 100, 50))
	pad("PizzaOven_1", Vector3.new(0, 2, -20), Color3.fromRGB(200, 60, 40))
	pad("PizzaOven_2", Vector3.new(10, 2, -20), Color3.fromRGB(200, 60, 40))
	pad("PizzaCounter", Vector3.new(20, 2, -10), Color3.fromRGB(230, 200, 60))
	pad("PizzaDropoff_1", Vector3.new(30, 2, 20), Color3.fromRGB(90, 200, 120))
	pad("PizzaDropoff_2", Vector3.new(10, 2, 35), Color3.fromRGB(90, 200, 120))
	-- vehicles (Phase 3)
	pad("VehicleSpawn", Vector3.new(-40, 0.6, -40), Color3.fromRGB(70, 70, 70), Vector3.new(24, 1, 24))
	for i, id in { "sedan", "pickup", "delivery_van", "excavator" } do
		pad("VehicleGarage_" .. id, Vector3.new(-50 + i * 8, 2, -62), Color3.fromRGB(120, 120, 200), Vector3.new(6, 4, 6))
		if id ~= "sedan" then pad("VehicleShop_" .. id, Vector3.new(-50 + i * 8, 2, -72), Color3.fromRGB(200, 160, 60), Vector3.new(6, 4, 6)) end
	end
	pad("FuelStation", Vector3.new(-20, 2, -40), Color3.fromRGB(230, 90, 60), Vector3.new(4, 4, 4))
	pad("Garage_Repair", Vector3.new(-20, 2, -50), Color3.fromRGB(60, 180, 180), Vector3.new(6, 4, 6))
end

-- Dev only: every player gets the excavator for free so it can be perfected.
function TestWorld.GrantExcavator(player: Player)
	local DataService = require(script.Parent.DataService)
	for _ = 1, 60 do
		local d = DataService.Get(player)
		if d then
			d.vehicles.excavator = d.vehicles.excavator or { fuel = 120, condition = 100 }
			DataService.Push(player)
			return
		end
		task.wait(0.5)
	end
end

return TestWorld
