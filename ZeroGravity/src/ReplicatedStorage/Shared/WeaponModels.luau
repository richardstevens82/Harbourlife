-- Procedural weapon models (shared: the server mounts them on characters, the lobby shows them on
-- display pedestals). Each model has a PrimaryPart "Handle" with two Attachments for the hands -
-- "Grip" (right hand, on the pistol grip) and "Support" (left hand, on the handguard) - and an
-- Attachment "Muzzle" on the barrel.
local Weapons = require(script.Parent.WeaponDefinitions)
local Items = require(script.Parent.ItemDefinitions)

local Models = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	if shape then p.Shape = shape end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Builds the model at the origin, barrel pointing along -Z (Handle's LookVector). scale shrinks the
-- whole model (display pieces use 1; guns in a character's hands use Config.Character.HeldWeaponScale).
function Models.Build(id: string, rarity: string?, scale: number?): Model
	local def = Weapons.Get(id)
	local m = Instance.new("Model")
	m.Name = "Weapon_" .. id
	local s = def.size
	local body = def.color
	local accent = def.accent
	local trim = Items.RarityColor[rarity or "common"] or accent
	local len = 2.6 * s
	-- Handle is axis-aligned so its LookVector is the barrel direction; the angled grip is cosmetic.
	local handle = part(m, "Handle", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, -0.1, 0.35), body)
	handle.Transparency = 1
	part(m, "Grip", Vector3.new(0.45, 0.9, 0.6), CFrame.new(0, -0.45, 0.35) * CFrame.Angles(math.rad(-15), 0, 0), body)
	m.PrimaryPart = handle
	local receiver = part(m, "Receiver", Vector3.new(0.55, 0.7, len), CFrame.new(0, 0.15, -len / 2 + 0.6), body)
	part(m, "AccentL", Vector3.new(0.05, 0.18, len * 0.6), CFrame.new(-0.29, 0.2, -len / 2 + 0.6), accent, Enum.Material.Neon)
	part(m, "AccentR", Vector3.new(0.05, 0.18, len * 0.6), CFrame.new(0.29, 0.2, -len / 2 + 0.6), accent, Enum.Material.Neon)
	part(m, "RarityBand", Vector3.new(0.58, 0.1, 0.3), CFrame.new(0, 0.52, -0.2), trim, Enum.Material.Neon)
	local barrelLen = (id == "precision" and 2.4 or id == "shotgun" and 1.2 or id == "arc" and 0.6 or 1.0) * s
	local barrelR = id == "shotgun" and 0.42 or id == "helios" and 0.5 or 0.26
	local barrelZ = -len + 0.6 - barrelLen / 2
	part(m, "Barrel", Vector3.new(barrelLen, barrelR, barrelR), CFrame.new(0, 0.2, barrelZ) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(35, 37, 42), Enum.Material.Metal, Enum.PartType.Cylinder)
	if id ~= "pistol" then
		part(m, "Magazine", Vector3.new(0.35, 0.8, 0.5), CFrame.new(0, -0.45, -len / 2 + 0.8) * CFrame.Angles(math.rad(10), 0, 0), Color3.fromRGB(40, 42, 48))
	end
	if id == "assault" or id == "burst" or id == "precision" or id == "shotgun" or id == "helios" then
		part(m, "Stock", Vector3.new(0.4, 0.6, 1.1 * s), CFrame.new(0, 0.0, 0.9 + 0.55 * s), body)
	end
	if id == "precision" or id == "burst" then
		part(m, "Scope", Vector3.new(1.4, 0.3, 0.3), CFrame.new(0, 0.7, -len / 2 + 0.6) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(30, 30, 34), Enum.Material.Metal, Enum.PartType.Cylinder)
		part(m, "Lens", Vector3.new(0.05, 0.26, 0.26), CFrame.new(0, 0.7, -len / 2 - 0.12) * CFrame.Angles(0, math.rad(90), 0), accent,
			Enum.Material.Neon, Enum.PartType.Cylinder)
	end
	if id == "helios" or id == "arc" then
		for i = 0, 2 do
			part(m, "Coil", Vector3.new(0.12, 0.7, 0.7), CFrame.new(0, 0.2, barrelZ + (i - 1) * 0.35) * CFrame.Angles(0, math.rad(90), 0), accent,
				Enum.Material.Neon, Enum.PartType.Cylinder)
		end
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = receiver
	muzzle.WorldPosition = Vector3.new(0, 0.2, barrelZ - barrelLen / 2 - 0.1)
	-- Hand points (Handle space; the Handle sits at (0, -0.1, 0.35) with no rotation). The support hand
	-- holds the handguard about half way along the receiver, or cups the grip hand on a pistol.
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Position = Vector3.new(0, -0.35, 0)
	grip.Parent = handle
	local support = Instance.new("Attachment")
	support.Name = "Support"
	support.Position = if id == "pistol" then Vector3.new(-0.3, -0.42, -0.12) else Vector3.new(0, -0.15, -math.min(len * 0.55 - 0.25, 2.1))
	support.Parent = handle
	-- Scale before welding: moving a welded part would drag the whole assembly with it.
	local k = scale or 1
	if k ~= 1 then
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				p.Size *= k
				p.CFrame = p.CFrame.Rotation + p.CFrame.Position * k
			end
		end
		for _, a in m:GetDescendants() do
			if a:IsA("Attachment") then a.Position *= k end
		end
	end
	-- Weld everything to the handle so the model moves as one assembly.
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p ~= handle then
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = p
			w.Parent = p
		end
	end
	return m
end

return Models
