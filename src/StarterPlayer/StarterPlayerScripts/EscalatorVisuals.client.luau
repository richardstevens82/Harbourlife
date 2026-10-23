-- Moving step edges on every escalator, drawn locally so the server only runs the conveyor.
-- The steps Part's Conveyor attribute (set by MallBuilder) gives the direction and speed.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SPACING = 1.6 -- studs between step edges
local escalators = {}
local folder = Instance.new("Folder")
folder.Name = "EscalatorSteps"
folder.Parent = workspace

local function add(steps: Instance)
	local v = steps:GetAttribute("Conveyor")
	if not (steps:IsA("BasePart") and typeof(v) == "Vector3") then return end
	local len = steps.Size.Z
	-- sign of travel along the Part's own Z axis (its length runs along the slope)
	local dir = v.Unit:Dot(steps.CFrame.ZVector) >= 0 and 1 or -1
	local lines = {}
	for i = 1, math.floor(len / SPACING) do
		local p = Instance.new("Part")
		p.Name = "StepEdge"
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Size = Vector3.new(steps.Size.X - 0.6, 0.08, 0.25)
		p.Color = Color3.fromRGB(230, 200, 60)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = folder
		lines[i] = p
	end
	escalators[steps] = { lines = lines, len = len, dir = dir, speed = v.Magnitude }
end

for _, s in CollectionService:GetTagged("HarbourEscalator") do add(s) end
CollectionService:GetInstanceAddedSignal("HarbourEscalator"):Connect(add)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local parts, cframes = {}, {}
	for steps, e in escalators do
		if not steps.Parent then
			for _, p in e.lines do p:Destroy() end
			escalators[steps] = nil
			continue
		end
		local shift = (t * e.speed) % SPACING
		local top = steps.Size.Y / 2 + 0.05
		for i, p in e.lines do
			local z = (-e.len / 2 + (i - 1) * SPACING + shift) * e.dir
			table.insert(parts, p)
			table.insert(cframes, steps.CFrame * CFrame.new(0, top, z))
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)
