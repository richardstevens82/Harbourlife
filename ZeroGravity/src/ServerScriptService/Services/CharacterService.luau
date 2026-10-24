-- Character spawning (characters never auto-load; MatchService decides where everyone goes),
-- space-suit visuals (helmet, life-support pack, suit colours) and the held-weapon visual.
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local WeaponModels = require(Shared.WeaponModels)
local Security = require(script.Parent.SecurityService)
local Roster = require(script.Parent.Roster)

local CharacterService = {}
local spawnSerial: { [Player]: number } = {}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
end

local function attach(char: Model, to: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CFrame = to.CFrame * offset
	p.Parent = char
	weld(to, p)
	return p
end

-- Space suit: recolours the body, removes clothing/accessories, adds helmet and life-support pack.
function CharacterService.ApplySuit(player: Player, char: Model, suitId: string?)
	local suit = Cosmetics.GetSuit(suitId or tostring(player:GetAttribute("Suit") or "navy"))
	for _, c in char:GetChildren() do
		if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") or c.Name == "SuitPart" then c:Destroy() end
	end
	local bc = char:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bc.HeadColor3 = Color3.fromRGB(230, 200, 175)
	bc.TorsoColor3 = suit.suit
	bc.LeftArmColor3, bc.RightArmColor3 = suit.suit, suit.suit
	bc.LeftLegColor3, bc.RightLegColor3 = suit.suit, suit.suit
	bc.Parent = char
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: any
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if face then face.Transparency = 0.3 end
		local helmet = attach(char, head, "SuitPart", Vector3.one * 2.5, CFrame.new(0, 0.1, 0), Color3.fromRGB(200, 205, 215), Enum.Material.Glass, Enum.PartType.Ball)
		helmet.Transparency = 0.55
		local visor = attach(char, head, "SuitPart", Vector3.new(1.7, 0.9, 0.3), CFrame.new(0, 0.15, -1.05), Color3.fromRGB(60, 120, 200), Enum.Material.Glass)
		visor.Transparency = 0.3
		visor.Reflectance = 0.3
		attach(char, head, "SuitPart", Vector3.new(0.35, 2.6, 2.6), CFrame.new(0, -0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), suit.trim,
			Enum.Material.Metal, Enum.PartType.Cylinder) -- neck ring
	end
	if torso then
		attach(char, torso, "SuitPart", Vector3.new(1.8, 2.0, 0.9), CFrame.new(0, 0.1, 1.0), Color3.fromRGB(70, 74, 82), Enum.Material.Metal)
		for _, x in { -0.45, 0.45 } do
			attach(char, torso, "SuitPart", Vector3.new(1.8, 0.6, 0.6), CFrame.new(x, 0.1, 1.55) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(210, 215, 222), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		local light = attach(char, torso, "SuitPart", Vector3.new(1.2, 0.15, 0.1), CFrame.new(0, 0.9, 1.47), Color3.fromRGB(80, 170, 255), Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Color = 10, 0.6, Color3.fromRGB(150, 200, 255)
		pl.Parent = light
		attach(char, torso, "SuitPart", Vector3.new(0.25, 1.4, 0.1), CFrame.new(0.35, 0, -0.52), suit.trim, Enum.Material.SmoothPlastic)
	end
	-- Arms and legs are posed every frame by the CharacterAnimator; they must not shove the body
	-- against walls while they swing (the root, torso and head keep their collisions).
	for _, c in char:GetChildren() do
		if c:IsA("BasePart") and (string.find(c.Name, "Arm") or string.find(c.Name, "Leg") or string.find(c.Name, "Hand") or string.find(c.Name, "Foot")) then
			c.CanCollide = false
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameOcclusion = Enum.NameOcclusion.OccludeAll
		hum.NameDisplayDistance = 60
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

-- Held weapon. The gun is mounted on the HumanoidRootPart with a Motor6D ("WeaponMount") so that it
-- always points where the body aims (the root follows the camera, or a bot's aim). C0 puts the
-- weapon's Grip attachment at the shouldered-aim position; every client's CharacterAnimator moves
-- the gun between ready and aim with the mount's Transform and puts the hands on Grip and Support
-- with IK, so the server copy (used for bot muzzle positions) is the aim pose.
function CharacterService.SetWeaponVisual(player: Player, weaponId: string?, rarity: string?)
	local char = player.Character
	if not char then return end
	local old = char:FindFirstChild("HeldWeapon")
	if old then old:Destroy() end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (weaponId and root) then return end
	local m = WeaponModels.Build(weaponId, rarity, Config.Character.HeldWeaponScale)
	m.Name = "HeldWeapon"
	m:SetAttribute("WeaponId", weaponId)
	local handle = m.PrimaryPart :: BasePart
	local grip = handle:FindFirstChild("Grip") :: Attachment
	local aim = Config.Character.AimGrip
	m:PivotTo(root.CFrame * aim * grip.CFrame:Inverse())
	m.Parent = char
	local mount = Instance.new("Motor6D")
	mount.Name = "WeaponMount"
	mount.Part0 = root
	mount.Part1 = handle
	mount.C0 = aim
	mount.C1 = grip.CFrame
	mount.Parent = handle
end

-- Loads a fresh character and places it at cf. Returns the character (or nil if superseded).
function CharacterService.Spawn(player: Player, cf: CFrame): Model?
	local serial = (spawnSerial[player] or 0) + 1
	spawnSerial[player] = serial
	-- LoadCharacterAsync where available (newer API), LoadCharacter otherwise; both yield until loaded
	local ok, err = pcall(function() (player :: any):LoadCharacterAsync() end)
	if not ok then ok, err = pcall(function() player:LoadCharacter() end) end
	if not ok then
		warn("[ZG] LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
		return nil
	end
	if spawnSerial[player] ~= serial or not player.Parent then return nil end
	local char = player.Character
	if not char then return nil end
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = Config.Health.Max
		hum.Health = Config.Health.Max
		hum.BreakJointsOnDeath = false -- the body stays in one piece and tumbles (CharacterAnimator)
	end
	Security.Teleported(player)
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	CharacterService.ApplySuit(player, char)
	return char
end

-- Bot bodies: an R15 rig built from a default HumanoidDescription, simulated by the server.
local BOT_DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics, Enum.HumanoidStateType.Landed, Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.StrafingNoPhysics,
}

function CharacterService.SpawnBot(bot, cf: CFrame, parent: Instance, displayName: string): Model?
	local old = bot.Character
	if old then
		Roster.UnbindCharacter(old)
		old:Destroy()
		bot.Character = nil
	end
	local ok, char = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not char then
		warn("[ZG] could not build bot body: " .. tostring(char))
		return nil
	end
	char.Name = bot.Name
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then
		char:Destroy()
		return nil
	end
	char.PrimaryPart = root
	hum.DisplayName = displayName
	hum.MaxHealth = Config.Health.Max
	hum.Health = Config.Health.Max
	hum.AutoRotate = false
	hum.BreakJointsOnDeath = false
	for _, st in BOT_DISABLED_STATES do hum:SetStateEnabled(st, false) end
	local att = Instance.new("Attachment")
	att.Name = "ZG_Align"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "ZG_Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.Responsiveness = Config.Movement.TurnResponsiveness
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = 20
	align.CFrame = cf.Rotation
	align.Parent = root
	char:PivotTo(cf)
	char.Parent = parent
	pcall(function() root:SetNetworkOwner(nil) end) -- the server simulates bots
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	bot.Character = char
	Roster.BindCharacter(char, bot)
	CharacterService.ApplySuit(bot, char, bot.suit)
	return char
end

function CharacterService.Start()
	Players.CharacterAutoLoads = false
	-- Disable Roblox's default health regeneration (our regen rules live in CombatService).
	local scs = StarterPlayer:FindFirstChildOfClass("StarterCharacterScripts")
	if scs and not scs:FindFirstChild("Health") then
		local stub = Instance.new("Script")
		stub.Name = "Health"
		stub.Parent = scs
	end
	Players.PlayerRemoving:Connect(function(p) spawnSerial[p] = nil end)
end

return CharacterService
