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
	if not workspace:FindFirstChild("TestFloor") then
		local f = Instance.new("Part")
		f.Name = "TestFloor"; f.Anchored = true
		f.Size = Vector3.new(120, 1, 120); f.Position = Vector3.new(0, -0.5, 0)
		f.Color = Color3.fromRGB(90, 140, 90); f.Parent = workspace
	end
	pad("JobCentre_pizza_cook", Vector3.new(-30, 2, 0), Color3.fromRGB(60, 120, 220))
	pad("JobCentre_delivery_driver", Vector3.new(-30, 2, 12), Color3.fromRGB(60, 120, 220))
	pad("PizzaSupplier", Vector3.new(-10, 2, -20), Color3.fromRGB(150, 100, 50))
	pad("PizzaOven_1", Vector3.new(0, 2, -20), Color3.fromRGB(200, 60, 40))
	pad("PizzaOven_2", Vector3.new(10, 2, -20), Color3.fromRGB(200, 60, 40))
	pad("PizzaCounter", Vector3.new(20, 2, -10), Color3.fromRGB(230, 200, 60))
	pad("PizzaDropoff_1", Vector3.new(30, 2, 20), Color3.fromRGB(90, 200, 120))
	pad("PizzaDropoff_2", Vector3.new(10, 2, 35), Color3.fromRGB(90, 200, 120))
end

return TestWorld
