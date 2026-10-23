-- Harbour Mall at runtime: builds the mall if the place has a MallSite but no baked "HarbourMall",
-- then runs every escalator (conveyor steps), lift (server-owned prismatic car with floor gates),
-- automatic door and ATM. Works the same for a mall built at runtime or baked into the place.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MallBuilder = require(script.Parent.MallBuilder)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local Notify = require(script.Parent.NotificationService)

local MallService = {}
local DOOR_RADIUS, DOOR_HEIGHT = 11, 8 -- a player this close (horizontally / vertically) opens the doors
local ATM_AMOUNT = 100
local doorTween = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local doors = {}

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

local function addDoor(m: Instance)
	local centre = m:GetAttribute("Centre")
	if typeof(centre) ~= "Vector3" then return end
	local panels = {}
	for _, p in m:GetChildren() do
		local offset = p:GetAttribute("OpenOffset")
		if p:IsA("BasePart") and typeof(offset) == "Vector3" then
			table.insert(panels, { part = p, closed = p.CFrame, open = p.CFrame + offset })
		end
	end
	if #panels > 0 then table.insert(doors, { model = m, centre = centre, panels = panels, open = false }) end
end

-- One loop for every door: open while any player is close, close when they have all gone.
local function runDoors()
	while true do
		local roots = {}
		for _, plr in Players:GetPlayers() do
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then table.insert(roots, hrp.Position) end
		end
		for i = #doors, 1, -1 do
			local d = doors[i]
			if not d.model.Parent then table.remove(doors, i); continue end
			local want = false
			for _, pos in roots do
				local dv = pos - d.centre
				if math.abs(dv.Y) < DOOR_HEIGHT and Vector3.new(dv.X, 0, dv.Z).Magnitude < DOOR_RADIUS then want = true; break end
			end
			if want ~= d.open then
				d.open = want
				for _, p in d.panels do TweenService:Create(p.part, doorTween, { CFrame = want and p.open or p.closed }):Play() end
			end
		end
		task.wait(0.15)
	end
end

local function hookATM(inst: Instance)
	if not (inst:IsA("BasePart") and inst.Name:match("^ATM_%d+$")) then return end
	Interaction.Register(inst, { action = "Deposit $" .. ATM_AMOUNT, object = "ATM", onTriggered = function(p)
		if Economy.Deposit(p, ATM_AMOUNT) then Notify.Send(p, "Deposited $" .. ATM_AMOUNT, "success")
		else Notify.Send(p, "Not enough cash", "error") end
	end })
	local w = Interaction.Register(inst, { action = "Withdraw $" .. ATM_AMOUNT, object = "ATM", onTriggered = function(p)
		if Economy.Withdraw(p, ATM_AMOUNT) then Notify.Send(p, "Withdrew $" .. ATM_AMOUNT, "success")
		else Notify.Send(p, "Not enough in the bank", "error") end
	end })
	w.KeyboardKeyCode = Enum.KeyCode.F
	w.GamepadKeyCode = Enum.KeyCode.ButtonY
	w.UIOffset = Vector2.new(0, 70) -- stack below the deposit prompt
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
	for _, m in CollectionService:GetTagged("HarbourAutoDoor") do addDoor(m) end
	CollectionService:GetInstanceAddedSignal("HarbourAutoDoor"):Connect(addDoor)
	task.spawn(runDoors)
	for _, d in workspace:GetDescendants() do hookATM(d) end
	workspace.DescendantAdded:Connect(hookATM)
end

return MallService
