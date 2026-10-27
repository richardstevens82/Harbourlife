-- Loot containers and world pickups. Every match re-seeds containers on LootSpot markers
-- (not every spot is filled, so routes vary). Searching and picking up use ProximityPrompts that
-- the server validates (active combatant, distance, container state, inventory capacity).
local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.ItemDefinitions)
local Weapons = require(Shared.WeaponDefinitions)
local LootTables = require(Shared.LootTables)
local WeaponModels = require(Shared.WeaponModels)
local Remotes = require(Shared.Remotes)
local Gravity = require(Shared.Gravity)
local Roster = require(script.Parent.Roster)
local Inventory = require(script.Parent.InventoryService)

local Loot = {}
local folder: Folder
local pickups: { [BasePart]: any } = {}
-- Interaction handlers keyed by container / pickup part, shared by ProximityPrompts (players) and
-- Loot.Search / Loot.Take (bots), so both go through identical validation.
local searchHandlers: { [BasePart]: (any) -> () } = {}
local takeHandlers: { [BasePart]: (any) -> () } = {}
local rng = Random.new()

local CATEGORY_COLOR = {
	ammo = Color3.fromRGB(230, 190, 70), consumable = Color3.fromRGB(90, 220, 140), armor = Color3.fromRGB(80, 160, 255),
	utility = Color3.fromRGB(255, 140, 60), upgrade = Color3.fromRGB(190, 110, 255),
}

local function displayName(entry): string
	local def = Items.Get(entry.id)
	if def and def.kind == "weapon" then return Weapons.Get(def.weapon).name end
	local name = def and def.name or entry.id
	if def and def.kind == "ammo" then name ..= " x" .. tostring(entry.amount) end
	return name
end
Loot.DisplayName = displayName

local function label(part: BasePart, text: string, color: Color3, rarity: string)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 34)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.MaxDistance = 45
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	t.BackgroundTransparency = 0.35
	t.TextColor3 = color
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = text .. (rarity ~= "common" and ("  [" .. string.upper(rarity) .. "]") or "")
	t.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = t
end

local function prompt(parent: Instance, action: string, object: string, hold: number, dist: number)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = dist
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = parent
	return p
end

local function canInteract(player: Player, at: Vector3, range: number): boolean
	if not Roster.IsActive(player) then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - at).Magnitude <= range + 4
end

-- World pickup for one loot entry.
function Loot.SpawnPickup(pos: Vector3, entry)
	local def = Items.Get(entry.id)
	if not def then return end
	local rarityColor = Items.RarityColor[entry.rarity or "common"]
	local base = Instance.new("Part")
	base.Name = "Pickup"
	base.Shape = Enum.PartType.Ball
	base.Size = Vector3.one * 1.6
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Material = Enum.Material.ForceField
	base.Color = rarityColor
	base.CFrame = CFrame.new(pos)
	if def.kind == "weapon" then
		local m = WeaponModels.Build(def.weapon, entry.rarity)
		m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then p.Anchored = true end
		end
		m.Parent = base
		base.Size = Vector3.one * 3
	else
		local box = Instance.new("Part")
		box.Name = "Box"
		box.Size = def.kind == "ammo" and Vector3.new(1.4, 0.9, 1) or Vector3.new(1.1, 1.1, 1.1)
		box.Anchored, box.CanCollide, box.CanQuery = true, false, false
		box.Color = CATEGORY_COLOR[def.kind] or rarityColor
		box.Material = Enum.Material.SmoothPlastic
		box.CFrame = CFrame.new(pos) * CFrame.Angles(0.4, rng:NextNumber(0, 6.28), 0.3)
		box.Parent = base
	end
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = rarityColor, 7, 0.8
	light.Parent = base
	label(base, displayName(entry), rarityColor, entry.rarity or "common")
	local pr = prompt(base, "Pick up", displayName(entry), 0, Config.Inventory.PickupRange)
	pickups[base] = entry
	base:SetAttribute("Spawned", os.clock())
	CollectionService:AddTag(base, "Pickup")
	base.Parent = folder
	local function take(player)
		local e = pickups[base]
		if not e or not canInteract(player, base.Position, Config.Inventory.PickupRange) then return end
		local accepted, leftover, dropped = Inventory.Add(player, e)
		if not accepted then
			Remotes.FX:FireClient(player, { t = "notice", text = "No room for " .. displayName(e), color = Color3.fromRGB(255, 120, 90) })
			return
		end
		Remotes.FX:FireClient(player, { t = "pickup", name = displayName(e), rarity = e.rarity })
		if leftover then
			pickups[base] = leftover
			pr.ObjectText = displayName(leftover)
		else
			pickups[base] = nil
			base:Destroy()
		end
		if dropped then
			Loot.SpawnPickup(base.Position + Vector3.new(0, 2.5, 0), dropped)
		end
	end
	takeHandlers[base] = take
	pr.Triggered:Connect(take)
	return base
end

-- Scatter entries around a point, keeping them out of walls.
local function scatter(center: Vector3, entries, ignore: Instance?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore or folder }
	for i, e in entries do
		local a = (i / #entries) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0.4, math.sin(a)).Unit * 3.5
		local hit = workspace:Raycast(center, dir, params)
		local pos = hit and center + dir * math.max(((hit.Position - center).Magnitude - 1.2) / 3.5, 0) or center + dir
		Loot.SpawnPickup(pos, e)
	end
end

local KIND_LOOK = {
	crate = { size = Vector3.new(4, 3, 3), color = Color3.fromRGB(70, 75, 85), label = "Supply Crate" },
	locker = { size = Vector3.new(3, 6, 2), color = Color3.fromRGB(55, 60, 70), label = "Weapon Locker" },
	pod = { size = Vector3.new(2.6, 2.6, 2.6), color = Color3.fromRGB(200, 120, 50), label = "Pod Stowage" },
	cache = { size = Vector3.new(3, 2, 3), color = Color3.fromRGB(150, 80, 40), label = "Salvage Cache" },
	suit = { size = Vector3.new(3, 3, 3), color = Color3.fromRGB(40, 90, 200), label = "Suit Locker" },
	drop = { size = Vector3.new(4, 3.4, 4), color = Color3.fromRGB(225, 228, 235), label = "Supply Drop" },
}

local function container(cf: CFrame, kind: string, tier: string, contents, title: string?)
	local look = KIND_LOOK[kind] or KIND_LOOK.crate
	local box = Instance.new("Part")
	box.Name = "LootContainer"
	box.Size = look.size
	box.CFrame = cf
	box.Anchored = true
	box.Color = look.color
	box.Material = Enum.Material.Metal
	box.TopSurface, box.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	local strip = Instance.new("Part")
	strip.Name = "Seal"
	strip.Size = Vector3.new(look.size.X + 0.1, 0.3, look.size.Z + 0.1)
	strip.CFrame = cf * CFrame.new(0, look.size.Y / 2 - 0.4, 0)
	strip.Anchored, strip.CanCollide, strip.CanQuery = true, false, false
	strip.Material = Enum.Material.Neon
	strip.Color = (tier == "drop" and Color3.fromRGB(255, 215, 60)) or (tier == "high" and Color3.fromRGB(255, 170, 40))
		or (tier == "mid" and Color3.fromRGB(70, 150, 255)) or Color3.fromRGB(150, 220, 160)
	strip.Parent = box
	box:SetAttribute("Tier", tier)
	CollectionService:AddTag(box, "LootContainer")
	box.Parent = folder
	local pr = prompt(box, "Search", title or look.label, kind == "suit" and 0.4 or 0.8, Config.Inventory.SearchRange)
	local function search(player)
		if box:GetAttribute("Searched") or not canInteract(player, box.Position, Config.Inventory.SearchRange) then return end
		box:SetAttribute("Searched", true)
		pr.Enabled = false
		strip.Color = Color3.fromRGB(60, 60, 60)
		local items = contents or LootTables.RollContainer(rng, tier, Config.Loot.ItemsPerContainer.min, Config.Loot.ItemsPerContainer.max)
		scatter(box.Position + cf.UpVector * (look.size.Y / 2 + 1.2), items, box)
		Remotes.FX:FireAllClients({ t = "search", pos = box.Position })
	end
	searchHandlers[box] = search
	pr.Triggered:Connect(search)
	return box
end

-- Bot entry points (same checks as the prompts: active combatant, distance, state, capacity).
function Loot.Search(c, box: BasePart)
	local h = searchHandlers[box]
	if h then h(c) end
end

function Loot.Take(c, part: BasePart)
	local h = takeHandlers[part]
	if h then h(c) end
end

function Loot.EntryOf(part: BasePart)
	return pickups[part]
end

-- Unsearched containers and live pickups (for bot decision making).
function Loot.OpenContainers(): { BasePart }
	local out = {}
	for box in searchHandlers do
		if box.Parent and not box:GetAttribute("Searched") then table.insert(out, box) end
	end
	return out
end

function Loot.PickupsNear(pos: Vector3, radius: number): { BasePart }
	local out = {}
	for part in pickups do
		if part.Parent and (part.Position - pos).Magnitude <= radius then table.insert(out, part) end
	end
	return out
end

-- In a room with artificial gravity a container rests on whatever is below its spot (floor, table,
-- crate) instead of floating; elsewhere it stays where the spot is.
local function settle(cf: CFrame, kind: string): CFrame
	local up = Gravity.UpAt(cf.Position)
	if not up then return cf end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	for _, name in { "BotCharacters", "Events" } do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(exclude, f) end
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(cf.Position, -up * 120, params)
	if not hit then return cf end
	local look = KIND_LOOK[kind] or KIND_LOOK.crate
	local fwd = cf.LookVector - up * cf.LookVector:Dot(up)
	if fwd.Magnitude < 0.05 then fwd = cf.UpVector - up * cf.UpVector:Dot(up) end
	return CFrame.lookAt(hit.Position + up * (look.size.Y / 2 + 0.05), hit.Position + up * (look.size.Y / 2 + 0.05) + fwd.Unit, up)
end

-- A supply-drop container: rare-to-legendary loot, more of it than a normal container.
function Loot.SpawnDrop(cf: CFrame): BasePart
	local E = Config.Events
	return container(cf, "drop", "drop", LootTables.RollContainer(rng, "drop", E.DropItems.min, E.DropItems.max), "Supply Drop")
end

-- Drop everything an eliminated player carried in a suit locker at their position.
function Loot.SpawnDeathBox(pos: Vector3, entries, ownerName: string)
	if #entries == 0 then return end
	local box = container(settle(CFrame.new(pos), "suit"), "suit", "mid", entries, ownerName .. "'s Suit Locker")
	task.delay(Config.Inventory.DropOnDeathLifetime * 3, function()
		if box.Parent then box:Destroy() end
	end)
end

function Loot.ClearAll()
	for p in pickups do
		if p.Parent then p:Destroy() end
	end
	table.clear(pickups)
	table.clear(searchHandlers)
	table.clear(takeHandlers)
	folder:ClearAllChildren()
end

-- Re-seed containers for a new match. ~80% of spots get a container.
function Loot.Seed()
	Loot.ClearAll()
	rng = Random.new()
	local n = 0
	for _, marker in CollectionService:GetTagged("LootSpot") do
		if marker:IsA("BasePart") and marker:IsDescendantOf(workspace) and rng:NextNumber() < 0.8 then
			local kind = marker:GetAttribute("Kind") or "crate"
			container(settle(marker.CFrame, kind), kind, marker:GetAttribute("Tier") or "low")
			n += 1
		end
	end
	print("[ZG] loot seeded: " .. n .. " containers")
end

function Loot.Start()
	Inventory.SpawnPickup = Loot.SpawnPickup
	folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = workspace
	-- Expire stale pickups
	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.clock()
			for p in pickups do
				if now - (p:GetAttribute("Spawned") or now) > Config.Loot.PickupLifetime then
					pickups[p] = nil
					p:Destroy()
				end
			end
		end
	end)
end

return Loot
