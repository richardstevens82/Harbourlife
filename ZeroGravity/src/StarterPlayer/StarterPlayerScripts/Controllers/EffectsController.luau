-- Visual and audio presentation: tracers, muzzle flashes, impacts, explosions, tether beams,
-- the radiation-storm sphere, the planet backdrop, flickering damaged lights, electrical crackle
-- and suit audio. Purely cosmetic; never affects gameplay state.
--
-- Audio framing: space is silent, so world sounds are "suit-transmitted": when the listener is
-- outside a pressurised area, remote sounds route through a muffled SoundGroup.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.WeaponDefinitions)
local Config = require(Shared.Config)

local Effects = {}
local player = Players.LocalPlayer
local fxFolder: Folder

-- Built-in Roblox content sounds (shipped with the client). Swap for licensed assets as needed.
local SOUNDS = {
	shot = { id = "rbxasset://sounds/paintball.wav", vol = 0.5 },
	shotHeavy = { id = "rbxasset://sounds/Rocket shot.wav", vol = 0.45 },
	shotEnergy = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.35, pitch = 0.6 },
	dry = { id = "rbxasset://sounds/clickfast.wav", vol = 0.5 },
	reload = { id = "rbxasset://sounds/unsheath.wav", vol = 0.4, pitch = 1.3 },
	equip = { id = "rbxasset://sounds/unsheath.wav", vol = 0.35 },
	hit = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.45, pitch = 1.8 },
	kill = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.7, pitch = 1.2 },
	melee = { id = "rbxasset://sounds/swordslash.wav", vol = 0.5 },
	tether = { id = "rbxasset://sounds/Rocket whoosh 01.wav", vol = 0.4, pitch = 1.5 },
	throw = { id = "rbxasset://sounds/swoosh.wav", vol = 0.5 },
	pickup = { id = "rbxasset://sounds/button.wav", vol = 0.5 },
	search = { id = "rbxasset://sounds/snap.wav", vol = 0.4 },
	ui = { id = "rbxasset://sounds/clickfast.wav", vol = 0.35 },
	alarm = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.6, pitch = 0.5 },
	warn = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.5, pitch = 0.75 },
	o2 = { id = "rbxasset://sounds/Rocket whoosh 01.wav", vol = 0.35, pitch = 0.6 },
	start = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.7, pitch = 1 },
	airlock = { id = "rbxasset://sounds/Rocket whoosh 01.wav", vol = 0.5, pitch = 0.4 },
	crackle = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.25, pitch = 2.5 },
	damage = { id = "rbxasset://sounds/collide.wav", vol = 0.5 },
	breath = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.35, pitch = 0.35 },
}

local suitGroup: SoundGroup
local transmittedGroup: SoundGroup

-- 2D sound (suit-internal) or positional (world) sound.
function Effects.Play(name: string, pos: Vector3?, pitchJitter: number?)
	local s = SOUNDS[name]
	if not s then return end
	local snd = Instance.new("Sound")
	snd.SoundId = s.id
	snd.Volume = s.vol
	snd.PlaybackSpeed = (s.pitch or 1) * (1 + (pitchJitter or 0) * (math.random() - 0.5))
	if pos then
		local a = Instance.new("Attachment")
		a.WorldPosition = pos
		a.Parent = workspace.Terrain
		snd.RollOffMaxDistance = 260
		snd.SoundGroup = player:GetAttribute("Pressurized") and suitGroup or transmittedGroup
		snd.Parent = a
		snd:Play()
		Debris:AddItem(a, 4)
	else
		snd.SoundGroup = suitGroup
		snd.Parent = SoundService
		snd:Play()
		Debris:AddItem(snd, 4)
	end
end

local function neon(size: Vector3, cf: CFrame, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = transparency or 0
	p.Parent = fxFolder
	return p
end

local function sparks(pos: Vector3, color: Color3, count: number)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.3, 0)
	pe.Speed = NumberRange.new(6, 16)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Lifetime = NumberRange.new(0.15, 0.35)
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(count)
	Debris:AddItem(a, 1)
end

-- Tracer(s) + muzzle flash + impact sparks. `ends` are the validated (or locally predicted) hits.
function Effects.Shot(origin: Vector3, ends: { Vector3 }, weaponId: string, isLocal: boolean)
	local def = Weapons.Get(weaponId)
	if not def then return end
	local color = isLocal and Color3.fromRGB(150, 220, 255) or def.accent:Lerp(Color3.fromRGB(255, 120, 90), 0.5)
	local width = (weaponId == "helios" and 0.5) or (weaponId == "precision" and 0.22) or 0.12
	for _, e in ends do
		local d = (e - origin)
		local len = d.Magnitude
		if len > 0.5 then
			local beam = neon(Vector3.new(width, width, len), CFrame.lookAt(origin + d / 2, e), color, 0.15)
			task.delay(weaponId == "helios" and 0.12 or 0.05, function() beam:Destroy() end)
			sparks(e, color, weaponId == "shotgun" and 3 or 6)
		end
	end
	local flash = neon(Vector3.one * (weaponId == "helios" and 1.6 or 0.8), CFrame.new(origin), Color3.fromRGB(255, 220, 160), 0.2)
	flash.Shape = Enum.PartType.Ball
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = Color3.fromRGB(255, 210, 150), 14, 3
	l.Parent = flash
	task.delay(0.04, function() flash:Destroy() end)
	local snd = (def.ammo == "energy" and "shotEnergy") or ((def.ammo == "heavy" or def.ammo == "shells") and "shotHeavy") or "shot"
	Effects.Play(snd, (not isLocal) and origin or nil, 0.12)
	if weaponId == "helios" then
		for _, e in ends do Effects.Explosion(e, def.splash or 8, true) end
	end
end

function Effects.Explosion(pos: Vector3, radius: number, small: boolean?)
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = radius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Visible = not small
	ex.Parent = workspace
	local ball = neon(Vector3.one * radius * 0.6, CFrame.new(pos), Color3.fromRGB(255, 170, 90), 0.2)
	ball.Shape = Enum.PartType.Ball
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = Color3.fromRGB(255, 170, 90), radius * 3, 4
	l.Parent = ball
	task.spawn(function()
		for i = 1, 10 do
			ball.Transparency = 0.2 + i * 0.08
			ball.Size = Vector3.one * radius * (0.6 + i * 0.06)
			l.Brightness = 4 * (1 - i / 10)
			task.wait(0.03)
		end
		ball:Destroy()
	end)
	sparks(pos, Color3.fromRGB(255, 190, 120), 30)
end

-- Tether beams (own + other players)
local beams: { [Player]: Instance } = {}
function Effects.TetherBeam(who: Player, point: Vector3?, duration: number?)
	if beams[who] then
		beams[who]:Destroy()
		beams[who] = nil
	end
	if not point then return end
	local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = point
	anchor.Parent = workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, anchor
	beam.Width0, beam.Width1 = 0.25, 0.15
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60))
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = a0
	local holder = Instance.new("Folder")
	holder.Destroying:Connect(function()
		a0:Destroy()
		anchor:Destroy()
	end)
	beams[who] = holder
	holder.Parent = fxFolder
	if duration then
		task.delay(duration, function()
			if beams[who] == holder then
				holder:Destroy()
				beams[who] = nil
			end
		end)
	end
end

-- Radiation storm sphere -------------------------------------------------------------------------
local zoneOuter: Part?, zoneInner: Part?, zoneNext: Part?
local function sphereMesh(color: Color3, inverted: boolean, transparency: number): (Part, SpecialMesh)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size = Vector3.one * 2048
	p.Material = Enum.Material.ForceField
	p.Color = color
	p.Transparency = transparency
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	p:SetAttribute("Inverted", inverted)
	p.Parent = fxFolder
	return p, m
end

local function updateZone()
	local zs = ReplicatedStorage:FindFirstChild("ZoneState")
	if not zs then return end
	local active = zs:GetAttribute("Active")
	local center = zs:GetAttribute("Center") or Vector3.zero
	local radius = zs:GetAttribute("Radius") or Config.Zone.StartRadius
	if not (zoneOuter and zoneInner and zoneNext) then
		zoneOuter = sphereMesh(Color3.fromRGB(170, 60, 255), false, 0.4)
		zoneInner = sphereMesh(Color3.fromRGB(170, 60, 255), true, 0.4)
		zoneNext = sphereMesh(Color3.fromRGB(230, 230, 255), true, 0.85)
	end
	local outer, inner, nxt = zoneOuter :: Part, zoneInner :: Part, zoneNext :: Part
	local show = active == true
	for _, p in { outer, inner } do
		p.Transparency = show and 0.4 or 1
		p.CFrame = CFrame.new(center)
		local s = radius * 2 / 2048
		local mesh = p:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh
		-- the inverted copy (negative scale flips the faces) is what you see from inside the sphere
		mesh.Scale = Vector3.one * s * (p:GetAttribute("Inverted") and -1 or 1)
	end
	local nextC, nextR = zs:GetAttribute("NextCenter") :: Vector3?, zs:GetAttribute("NextRadius") :: number?
	if show and zs:GetAttribute("Phase") == "waiting" and nextC and nextR then
		nxt.Transparency = 0.85
		nxt.CFrame = CFrame.new(nextC)
		local mesh = nxt:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh
		mesh.Scale = Vector3.one * (-nextR * 2 / 2048)
	else
		nxt.Transparency = 1
	end
	-- storm tint while outside
	local grade = Lighting:FindFirstChild("StormTint") :: ColorCorrectionEffect?
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "StormTint"
		grade.Parent = Lighting
	end
	local outside = show and player:GetAttribute("InStorm") == true
	grade.TintColor = outside and Color3.fromRGB(220, 170, 255) or Color3.new(1, 1, 1)
	grade.Saturation = outside and -0.3 or 0
end

-- Planet backdrop: a huge cratered world that stays at a fixed offset from the camera ------------
local planet: Model?
local planetOffset = Vector3.new(0.35, -0.75, -0.55).Unit * 6000
local lastPlanetCam = Vector3.new(1e9, 0, 0)
local function buildPlanet()
	local m = Instance.new("Model")
	m.Name = "Planet"
	local rng = Random.new(2024)
	local R = 3000
	local function ball(name, cf: CFrame, scale: Vector3, color: Color3, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = Vector3.one * 2048
		p.Material = material or Enum.Material.SmoothPlastic
		p.Color = color
		p.Transparency = transparency or 0
		p.CFrame = cf
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = scale / 2048
		mesh.Parent = p
		p.Parent = m
		return p
	end
	local core = ball("Surface", CFrame.new(), Vector3.one * R * 2, Color3.fromRGB(120, 108, 98), Enum.Material.Slate)
	m.PrimaryPart = core
	ball("Atmosphere", CFrame.new(), Vector3.one * R * 2.06, Color3.fromRGB(120, 170, 255), Enum.Material.Neon, 0.93)
	-- mineral regions
	for _ = 1, 14 do
		local n = (rng:NextUnitVector() + Vector3.new(0, 1.2, 0)).Unit
		local r = rng:NextNumber(300, 900)
		local cf = CFrame.lookAt(n * (R - r * 0.05), n * R * 2) * CFrame.Angles(math.rad(90), 0, 0)
		local colors = { Color3.fromRGB(150, 120, 90), Color3.fromRGB(90, 85, 82), Color3.fromRGB(170, 150, 120), Color3.fromRGB(110, 70, 55) }
		ball("Region", cf, Vector3.new(r * 2, r * 0.12, r * 2), colors[rng:NextInteger(1, #colors)])
	end
	-- craters: dark floor + lighter rim
	for _ = 1, 45 do
		local n = (rng:NextUnitVector() + Vector3.new(0, 1.0, 0)).Unit
		local r = rng:NextNumber(40, 380)
		local cf = CFrame.lookAt(n * R, n * R * 2) * CFrame.Angles(math.rad(90), 0, 0)
		ball("CraterRim", cf * CFrame.new(0, -r * 0.02, 0), Vector3.new(r * 2.3, r * 0.14, r * 2.3), Color3.fromRGB(175, 165, 152))
		ball("CraterFloor", cf * CFrame.new(0, r * 0.01, 0), Vector3.new(r * 2, r * 0.12, r * 2), Color3.fromRGB(70, 64, 60))
	end
	m.Parent = workspace.CurrentCamera
	planet = m
end

local function updatePlanet()
	local cam = workspace.CurrentCamera
	if not planet or planet.Parent ~= cam then
		buildPlanet()
		lastPlanetCam = Vector3.new(1e9, 0, 0)
	end
	local pos = cam.CFrame.Position
	if planet and (pos - lastPlanetCam).Magnitude > 20 then
		lastPlanetCam = pos
		planet:PivotTo(CFrame.new(pos + planetOffset))
	end
end

-- Damaged-light flicker and electrical crackle --------------------------------------------------
local function flickerLoop()
	while true do
		task.wait(0.12)
		for _, p in CollectionService:GetTagged("Flicker") do
			if p:IsA("BasePart") and math.random() < 0.3 then
				local on = math.random() < 0.6
				p.Transparency = on and 0 or 0.8
				local l = p:FindFirstChildOfClass("PointLight")
				if l then l.Enabled = on end
			end
		end
	end
end

local function crackleLoop()
	while true do
		task.wait(0.35)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			for _, f in CollectionService:GetTagged("ElectricFault") do
				local st = f:GetAttribute("State")
				if (st == "warn" or st == "active") and (f.Position - root.Position).Magnitude < 60 then
					Effects.Play("crackle", f.Position, 0.5)
				end
			end
		end
	end
end

-- Low-oxygen breathing / beeps
local function oxygenLoop()
	while true do
		local o2 = player:GetAttribute("O2") or 100
		if player:GetAttribute("InMatch") and player:GetAttribute("Alive") and o2 < Config.Oxygen.WarnAt then
			Effects.Play("breath")
			task.wait(o2 <= 0 and 0.5 or 1.2)
		else
			task.wait(0.5)
		end
	end
end

function Effects.Start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ZG_Effects"
	fxFolder.Parent = workspace
	suitGroup = Instance.new("SoundGroup")
	suitGroup.Name = "Suit"
	suitGroup.Volume = 0.8
	suitGroup.Parent = SoundService
	transmittedGroup = Instance.new("SoundGroup")
	transmittedGroup.Name = "Transmitted"
	transmittedGroup.Volume = 0.6
	transmittedGroup.Parent = SoundService
	local eq = Instance.new("EqualizerSoundEffect")
	eq.HighGain, eq.MidGain, eq.LowGain = -30, -8, 2
	eq.Parent = transmittedGroup
	RunService.RenderStepped:Connect(function()
		updatePlanet()
		updateZone()
	end)
	task.spawn(flickerLoop)
	task.spawn(crackleLoop)
	task.spawn(oxygenLoop)
end

return Effects
