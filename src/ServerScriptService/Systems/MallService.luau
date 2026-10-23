-- Harbour Mall at runtime: builds the mall if the place has a MallSite but no baked "HarbourMall",
-- then runs every escalator (conveyor steps) and lift (server-owned prismatic car with floor gates).
-- Works the same for a mall built at runtime or baked into the place with MallBuilder in Studio.
local CollectionService = game:GetService("CollectionService")
local MallBuilder = require(script.Parent.MallBuilder)

local MallService = {}

local function runEscalator(steps: Instance)
	local v = steps:GetAttribute("Conveyor")
	if steps:IsA("BasePart") and typeof(v) == "Vector3" then steps.AssemblyLinearVelocity = v end
end

local function runLift(m: Instance)
	local car = m:FindFirstChild("Car")
	local lift = m:FindFirstChild("Lift")
	if not (car and car:IsA("BasePart") and lift and lift:IsA("PrismaticConstraint")) then return end
	pcall(function() car:SetNetworkOwner(nil) end) -- server moves the car so riders can't desync it
	local stops = {}
	for s in string.gmatch(m:GetAttribute("Stops") or "", "[^,]+") do table.insert(stops, tonumber(s)) end
	local queue = {}
	local function request(i: number)
		if not table.find(queue, i) then table.insert(queue, i) end
	end
	for i in stops do
		for _, name in { "Call_" .. i, "Floor_" .. i } do
			local button = m:FindFirstChild(name)
			local cd = button and button:FindFirstChildOfClass("ClickDetector")
			if cd then cd.MouseClick:Connect(function() request(i) end) end
		end
	end
	-- travel loop: one stop at a time, doors stay open for a moment at each
	task.spawn(function()
		while m.Parent do
			local i = table.remove(queue, 1)
			if i then
				lift.TargetPosition = stops[i]
				local started = os.clock()
				while math.abs(lift.CurrentPosition - stops[i]) > 0.1 and os.clock() - started < 30 do task.wait(0.1) end
				task.wait(3)
			else
				task.wait(0.2)
			end
		end
	end)
	-- a floor's gate opens only while the car is stopped at that floor
	task.spawn(function()
		while m.Parent do
			for i, offset in stops do
				local gate = m:FindFirstChild("Gate_" .. i)
				if gate and gate:IsA("BasePart") then
					local open = math.abs(lift.CurrentPosition - offset) < 0.3 and math.abs(lift.TargetPosition - offset) < 0.01
					gate.CanCollide = not open
					gate.Transparency = open and 1 or 0.55
				end
			end
			task.wait(0.1)
		end
	end)
end

function MallService.Start()
	if not workspace:FindFirstChild("HarbourMall") and workspace:FindFirstChild("MallSite", true) then
		local started = os.clock()
		MallBuilder.Build()
		print(string.format("[Harbourlife] mall built in %.2fs", os.clock() - started))
	end
	for _, p in CollectionService:GetTagged("HarbourEscalator") do runEscalator(p) end
	CollectionService:GetInstanceAddedSignal("HarbourEscalator"):Connect(runEscalator)
	for _, m in CollectionService:GetTagged("HarbourElevator") do runLift(m) end
	CollectionService:GetInstanceAddedSignal("HarbourElevator"):Connect(runLift)
end

return MallService
