-- Staging lobby: a sealed observation hall outside the arena, with a panoramic window toward the
-- station, weapon display pedestals (equipment previews), a practice range with moving drone
-- targets, a match status board and a controls board. Players float here between matches.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Kit = require(script.Parent.Kit)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weapons = require(Shared.WeaponDefinitions)
local WeaponModels = require(Shared.WeaponModels)
local P = Kit.Palette

local Lobby = {}

function Lobby.Build(parent: Instance, center: Vector3)
	local root = Kit.model("Lobby", parent)
	local cf = CFrame.new(center)
	local size = Vector3.new(120, 44, 90)
	local room = Kit.room(root, cf, size, { name = "StagingHall", wall = 4, deck = true, pressurized = "lobby", color = P.HullDark,
		openings = { ["-Z"] = { w = 100, h = 30, y = 2 } } })
	Kit.window(room, Kit.faceCFrame(cf, size, "-Z", 2) * CFrame.new(0, 2, 0), 100, 30)
	-- Extra lighting rows
	for x = -40, 40, 40 do
		local lp = Kit.part(room, { Name = "Lamp", CFrame = cf * CFrame.new(x, 21.6, 20), Size = Vector3.new(8, 0.5, 3), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(220, 230, 255), CanCollide = false })
		Kit.light(lp, nil, 50, 1.2)
	end

	-- Spawn markers along the back half of the hall
	for i = 0, 11 do
		local x = -45 + (i % 6) * 18
		local y = (i < 6) and -10 or 6
		Kit.marker(root, "LobbySpawn", cf * CFrame.new(x, y, 26) * CFrame.Angles(0, 0, 0))
	end

	-- Title and boards
	Kit.sign(room, cf * CFrame.new(0, 18, 44.6) * CFrame.Angles(0, math.rad(180), 0), "ZERO GRAVITY: LAST ORBIT", 50, 5, P.BlueGlow)
	local board = Kit.sign(room, cf * CFrame.new(-38, 6, 44.6) * CFrame.Angles(0, math.rad(180), 0), "WAITING FOR PLAYERS", 34, 6, P.Orange)
	board.Name = "StatusBoard"
	local controls = Kit.sign(room, cf * CFrame.new(38, 6, 44.6) * CFrame.Angles(0, math.rad(180), 0),
		"WASD move  |  SPACE up  |  CTRL down  |  SHIFT boost  |  X stabilise\nF interact  |  R reload  |  G utility  |  V melee  |  TAB inventory  |  1-3 weapons  |  M menu",
		34, 6, P.HullLight)
	controls.Name = "ControlsBoard"

	-- Equipment previews: every weapon on a lit pedestal along the -X wall
	local previews = Kit.model("WeaponPreviews", root)
	for i, id in Weapons.Order do
		local pcf = cf * CFrame.new(-55, -14, -32 + (i - 1) * 9) * CFrame.Angles(0, math.rad(90), 0)
		Kit.part(previews, { Name = "Pedestal", CFrame = pcf, Size = Vector3.new(5, 3, 5), Color = P.Gunmetal })
		local ring = Kit.part(previews, { Name = "PedestalRing", CFrame = pcf * CFrame.new(0, 1.6, 0), Size = Vector3.new(5.2, 0.2, 5.2),
			Material = Enum.Material.Neon, Color = P.Blue, CanCollide = false })
		Kit.light(ring, P.Blue, 8, 0.8)
		local model = WeaponModels.Build(id, "common")
		model:PivotTo(pcf * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, math.rad(90), 0))
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then p.Anchored = true end
		end
		model.Parent = previews
		local label = Kit.sign(previews, pcf * CFrame.new(0, 6.2, 0) * CFrame.Angles(0, math.rad(180), 0), Weapons.Get(id).name, 7, 1, P.HullLight)
		local _ = label
	end

	-- Practice range: drones drifting on the +X side of the hall
	Kit.sign(room, cf * CFrame.new(59.6, 14, 0) * CFrame.Angles(0, math.rad(90), 0), "PRACTICE RANGE", 30, 4, P.Orange)
	local range = Kit.model("PracticeRange", root)
	for i = 0, 5 do
		local base = cf * CFrame.new(42 + (i % 2) * 10, -12 + (i % 3) * 10, -30 + i * 11)
		local d = Kit.part(range, { Name = "Drone", Shape = Enum.PartType.Ball, CFrame = base, Size = Vector3.one * 4, Color = P.Gunmetal, CanCollide = false })
		local eye = Kit.part(range, { Name = "Eye", Shape = Enum.PartType.Ball, CFrame = base * CFrame.new(-1.6, 0, 0), Size = Vector3.one * 1.4,
			Material = Enum.Material.Neon, Color = P.Red, CanCollide = false })
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = d, eye
		w.Parent = eye
		eye.Anchored = false
		d:SetAttribute("MaxHealth", 100)
		d:SetAttribute("Health", 100)
		CollectionService:AddTag(d, "PracticeTarget")
		local tween = TweenService:Create(d, TweenInfo.new(3 + i * 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = base * CFrame.new(0, 0, 8) })
		tween:Play()
	end
	return root
end

function Lobby.SetStatus(text: string)
	local board = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("StatusBoard", true)
	local label = board and board:FindFirstChildWhichIsA("SurfaceGui") and board:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
	if label then label.Text = text end
end

return Lobby
