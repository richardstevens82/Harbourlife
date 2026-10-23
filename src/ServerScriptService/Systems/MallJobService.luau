-- Mall jobs (sign up at Mall Management, south arm):
--   Mall Cleaner   litter builds up at the mall's LitterSpot nodes while a cleaner is on shift; clear it for pay
--   Mall Security  patrol the SecurityPoint_<n> checkpoints in order; each correct check-in pays
-- Pay and XP come from JobDefinitions via JobService.CompleteTask.
local Players = game:GetService("Players")
local DataService = require(script.Parent.DataService)
local JobService = require(script.Parent.JobService)
local Interaction = require(script.Parent.InteractionService)
local Notify = require(script.Parent.NotificationService)

local MallJobService = {}
local MAX_LITTER, LITTER_INTERVAL = 10, 12
local LITTER = {
	{ name = "Drinks can", size = Vector3.new(0.6, 1, 0.6), color = Color3.fromRGB(200, 40, 40), material = Enum.Material.Metal },
	{ name = "Crisp packet", size = Vector3.new(1.4, 0.2, 1), color = Color3.fromRGB(240, 200, 40), material = Enum.Material.Plastic },
	{ name = "Spilt drink", size = Vector3.new(4, 0.05, 3), color = Color3.fromRGB(140, 90, 40), material = Enum.Material.Glass },
	{ name = "Newspaper", size = Vector3.new(2, 0.1, 1.5), color = Color3.fromRGB(230, 230, 225), material = Enum.Material.Fabric },
}

local litterSpots: { BasePart } = {}
local litter: { [BasePart]: BasePart } = {}
local checkpoints: { [number]: BasePart } = {}
local nextCheckpoint: { [Player]: number } = {}
local folder

local function holds(player: Player, job: string): boolean
	local d = DataService.Get(player)
	return d ~= nil and d.job == job
end

local function onShift(job: string): boolean
	for _, p in Players:GetPlayers() do if holds(p, job) then return true end end
	return false
end

local function spawnLitter()
	local free, count = {}, 0
	for _, spot in litterSpots do
		if litter[spot] then count += 1 elseif spot.Parent then table.insert(free, spot) end
	end
	if count >= MAX_LITTER or #free == 0 then return end
	local spot = free[math.random(#free)]
	local look = LITTER[math.random(#LITTER)]
	local p = Instance.new("Part")
	p.Name = "Litter"
	p.Anchored = true; p.CanCollide = false; p.CastShadow = false
	p.Size = look.size; p.Color = look.color; p.Material = look.material
	p.CFrame = spot.CFrame * CFrame.new((math.random() - 0.5) * 4, look.size.Y / 2 + 0.06, (math.random() - 0.5) * 4) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	p.Parent = folder
	litter[spot] = p
	Interaction.Register(p, { action = "Clean up", object = look.name, onTriggered = function(player)
		if litter[spot] ~= p then return end -- already cleaned
		if not holds(player, "mall_cleaner") then
			Notify.Send(player, "Mall cleaners clean this up (jobs at Mall Management)", "error")
			return
		end
		litter[spot] = nil
		p:Destroy()
		JobService.CompleteTask(player, "mall_cleaner")
		Notify.Send(player, "Cleaned up " .. string.lower(look.name), "success")
	end })
end

local function checkIn(player: Player, i: number)
	if not holds(player, "mall_security") then
		Notify.Send(player, "Security checkpoint (jobs at Mall Management)", "error")
		return
	end
	local want = nextCheckpoint[player] or 1
	if i ~= want then Notify.Send(player, "Wrong checkpoint. Next on your patrol: " .. want, "error"); return end
	JobService.CompleteTask(player, "mall_security")
	nextCheckpoint[player] = want % #checkpoints + 1
	Notify.Send(player, "Checkpoint " .. i .. " clear. Next: " .. nextCheckpoint[player], "success")
end

local function label(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 30)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 60
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1); t.BackgroundColor3 = Color3.fromRGB(30, 60, 140); t.BackgroundTransparency = 0.2
	t.TextColor3 = Color3.new(1, 1, 1); t.TextScaled = true; t.Font = Enum.Font.GothamBold; t.Text = text
	t.Parent = gui
end

local function hook(inst: Instance)
	if not inst:IsA("BasePart") then return end
	if inst.Name == "LitterSpot" then
		table.insert(litterSpots, inst)
	elseif inst.Name:match("^SecurityPoint_%d+$") then
		local i = tonumber(inst.Name:match("%d+$"))
		checkpoints[i] = inst
		label(inst, "CHECKPOINT " .. i)
		Interaction.Register(inst, { action = "Check in", object = "Security checkpoint " .. i, onTriggered = function(p) checkIn(p, i) end })
	end
end

function MallJobService.Start()
	folder = Instance.new("Folder")
	folder.Name = "MallLitter"
	folder.Parent = workspace
	for _, d in workspace:GetDescendants() do hook(d) end
	workspace.DescendantAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(p) nextCheckpoint[p] = nil end)
	task.spawn(function()
		while true do
			task.wait(LITTER_INTERVAL)
			if onShift("mall_cleaner") then spawnLitter() end
		end
	end)
end

return MallJobService
