-- Dynamic match events.
--
-- Supply drops: at Config.Events.SupplyDropTimes after deployment a drop pod falls into the NEXT safe
-- zone (so it is worth heading for) and lands as a "drop"-tier container: rare to legendary loot.
-- Everyone is told when it is inbound, the pod trails a beacon beam with a label visible through
-- walls, and it is tagged "SupplyDrop" so the tactical map marks it. Drops become hot spots to fight
-- over; bots weigh them above ordinary containers.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Loot = require(script.Parent.LootService)
local WorldQuery = require(script.Parent.WorldQuery)

local Events = {}
local E = Config.Events
local serial = 0
local folder: Folder
local rng = Random.new()

-- A clear spot well inside the next safe sphere (falls back to its centre).
local function landingSpot(): Vector3
	local zs = ReplicatedStorage:FindFirstChild("ZoneState")
	local c = (zs and (zs:GetAttribute("NextCenter") or zs:GetAttribute("Center"))) or Vector3.zero
	local r = (zs and (zs:GetAttribute("NextRadius") or zs:GetAttribute("Radius"))) or Config.Zone.StartRadius
	for _ = 1, 40 do
		local p = c + rng:NextUnitVector() * rng:NextNumber(0, r * 0.6)
		if WorldQuery.IsClear(p, 7) then return p end
	end
	return c
end

local function piece(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size, p.CFrame, p.Color, p.Material = size, cf, color, material
	if shape then p.Shape = shape end
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- The falling pod: a capsule with fins and a gold beacon; the beam and label make it findable.
local function buildPod(at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SupplyDropPod"
	local white, gold = Color3.fromRGB(225, 228, 235), Color3.fromRGB(255, 205, 60)
	local body = piece(m, Vector3.new(6, 5, 5), at * CFrame.Angles(0, 0, math.rad(90)), white, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	body.Name = "Body"
	m.PrimaryPart = body
	for i = 0, 3 do
		local a = i * math.pi / 2
		piece(m, Vector3.new(0.4, 2.6, 2.2), at * CFrame.Angles(0, a, 0) * CFrame.new(0, 2.2, 2.7), white, Enum.Material.Metal)
	end
	local ring = piece(m, Vector3.new(0.6, 5.4, 5.4), at * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), gold, Enum.Material.Neon,
		Enum.PartType.Cylinder)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = gold, 40, 3
	light.Parent = ring
	local beam = piece(m, Vector3.new(1.2, 400, 1.2), at * CFrame.new(0, 202, 0), gold, Enum.Material.Neon)
	beam.Name = "Beacon"
	beam.Transparency = 0.55
	beam.CastShadow = false
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 4000
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "▼ SUPPLY DROP"
	label.TextColor3 = gold
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = bb
	bb.Parent = body
	CollectionService:AddTag(body, "SupplyDrop")
	m.Parent = folder
	return m
end

-- Drops a pod now (at `at`, or a clear spot in the next safe zone). Returns the pod model.
function Events.SupplyDrop(at: Vector3?): Model
	local target = at or landingSpot()
	local from = target + Vector3.new(rng:NextNumber(-60, 60), 320, rng:NextNumber(-60, 60))
	local pod = buildPod(CFrame.new(from))
	Remotes.FX:FireAllClients({ t = "notice", text = "SUPPLY DROP INBOUND - rare loot, marked on your map", color = Color3.fromRGB(255, 205, 60),
		sound = "drop" })
	local my = serial
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if serial ~= my or not pod.Parent then
			conn:Disconnect()
			return
		end
		local a = math.clamp((os.clock() - t0) / E.DropFallTime, 0, 1)
		local eased = 1 - (1 - a) * (1 - a) -- fast entry, braking thrusters near the end
		pod:PivotTo(CFrame.new(from:Lerp(target, eased)))
		if a >= 1 then
			conn:Disconnect()
			local box = Loot.SpawnDrop(CFrame.new(target))
			box:SetAttribute("SupplyDrop", true)
			pod:SetAttribute("Landed", true)
			Remotes.FX:FireAllClients({ t = "explosion", pos = target, radius = 6 }) -- touchdown dust and thump (cosmetic)
			-- the beacon stays until someone opens the drop
			box:GetAttributeChangedSignal("Searched"):Connect(function()
				local beam = pod:FindFirstChild("Beacon")
				if beam then beam:Destroy() end
				CollectionService:RemoveTag(pod.PrimaryPart :: BasePart, "SupplyDrop")
			end)
		end
	end)
	return pod
end

-- Schedules the match's drops (called right after deployment).
function Events.Begin()
	serial += 1
	local my = serial
	for _, t in E.SupplyDropTimes do
		task.delay(t, function()
			if serial == my then Events.SupplyDrop() end
		end)
	end
end

function Events.Stop()
	serial += 1
	if folder then folder:ClearAllChildren() end
end

function Events.Start()
	folder = Instance.new("Folder")
	folder.Name = "Events"
	folder.Parent = workspace
end

return Events
