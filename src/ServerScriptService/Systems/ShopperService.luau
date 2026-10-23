-- NPC shoppers for Harbour Mall. Each one arrives at an entrance (ground doors, or the footbridge for the
-- upper level), walks to 1-3 stores on that level, buys at the till (real stock comes off the shelf via
-- ShopService.NpcBuy), then leaves by an entrance on the same level and is removed.
-- Routes use the mall's Nodes (EntranceOut/In, StoreFront/Inside/Till) with PathfindingService between them.
-- Shoppers are tagged HarbourNPC so the automatic doors open for them.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local ShopService = require(script.Parent.ShopService)

local ShopperService = {}
local MAX_SHOPPERS = 16
local SPAWN_EVERY = 5
local ACTIVE_RANGE = 700 -- shoppers only come while a player is this close to the mall
local WALK_ANIM, IDLE_ANIM = "rbxassetid://507777826", "rbxassetid://507766388" -- Roblox default R15 animations
local SKIN = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(230, 180, 140), Color3.fromRGB(190, 135, 95), Color3.fromRGB(140, 95, 65), Color3.fromRGB(90, 60, 40) }

local folder: Folder
local active = 0
local index -- built from HarbourMall.Nodes

local function buildIndex()
	local mall = workspace:FindFirstChild("HarbourMall")
	local nodes = mall and mall:FindFirstChild("Nodes")
	if not nodes then return nil end
	local idx = { mall = mall, entrances = { [0] = {}, [1] = {} }, stores = { [0] = {}, [1] = {} }, centre = Vector3.zero }
	local byShop, entOut, entIn = {}, {}, {}
	local sum, n = Vector3.zero, 0
	for _, p in nodes:GetChildren() do
		local level = p:GetAttribute("Level")
		if p.Name == "EntranceOut" then table.insert(entOut, p)
		elseif p.Name == "EntranceIn" then table.insert(entIn, p)
		elseif p:GetAttribute("Shop") then
			local shop = p:GetAttribute("Shop")
			byShop[shop] = byShop[shop] or { shop = shop, level = level }
			byShop[shop][p.Name] = p.Position
		end
		sum += p.Position; n += 1
	end
	-- pair each outside node with the nearest inside node on the same level
	for _, o in entOut do
		local best, bestD
		for _, i in entIn do
			local d = (i.Position - o.Position).Magnitude
			if i:GetAttribute("Level") == o:GetAttribute("Level") and (not bestD or d < bestD) then best, bestD = i, d end
		end
		if best then table.insert(idx.entrances[o:GetAttribute("Level")], { out = o.Position, inn = best.Position }) end
	end
	for _, s in byShop do
		if s.StoreFront and s.StoreInside and s.StoreTill then table.insert(idx.stores[s.level], s) end
	end
	idx.centre = n > 0 and sum / n or Vector3.zero
	return idx
end

local function flat(v: Vector3) return Vector3.new(v.X, 0, v.Z).Magnitude end

-- Walk in a straight line, re-issuing MoveTo so long legs don't time out; false if stuck.
local function moveStraight(hum: Humanoid, root: BasePart, pos: Vector3): boolean
	local limit = os.clock() + flat(root.Position - pos) / hum.WalkSpeed * 2 + 4
	local last, lastCheck = root.Position, os.clock()
	while flat(root.Position - pos) > 2.5 do
		if os.clock() > limit or not hum.Parent or hum.Health <= 0 then return false end
		hum:MoveTo(pos)
		task.wait(0.2)
		if os.clock() - lastCheck > 2.5 then
			if flat(root.Position - last) < 1 then return false end
			last, lastCheck = root.Position, os.clock()
		end
	end
	return true
end

local function walkPath(hum: Humanoid, root: BasePart, pos: Vector3): boolean
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = false, WaypointSpacing = 10 })
	local ok = pcall(function() path:ComputeAsync(root.Position, pos) end)
	if ok and path.Status == Enum.PathStatus.Success then
		for _, wp in path:GetWaypoints() do
			if not moveStraight(hum, root, wp.Position) then return false end
		end
		return true
	end
	return moveStraight(hum, root, pos) -- no path: try directly
end

local function simpleRig(shirt: Color3, skin: Color3): Model
	local m = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"; root.Size = Vector3.new(2, 2, 1); root.Transparency = 1; root.Parent = m
	local function limb(name, size, offset, color)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.Color = color; p.CanCollide = false; p.Massless = true
		p.CFrame = root.CFrame * CFrame.new(offset); p.Parent = m
		local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = p; w.Parent = p
	end
	limb("Torso", Vector3.new(2, 2, 1), Vector3.zero, shirt)
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), skin)
	limb("Legs", Vector3.new(2, 2, 1), Vector3.new(0, -2, 0), Color3.fromRGB(50, 50, 70))
	local hum = Instance.new("Humanoid"); hum.HipHeight = 2; hum.Parent = m
	m.PrimaryPart = root
	return m
end

local function makeShopper(): Model
	local skin = SKIN[math.random(#SKIN)]
	local shirt = Color3.fromHSV(math.random(), 0.3 + math.random() * 0.5, 0.4 + math.random() * 0.5)
	local trousers = Color3.fromHSV(math.random(), 0.2 + math.random() * 0.3, 0.2 + math.random() * 0.4)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.TorsoColor, desc.LeftLegColor, desc.RightLegColor = shirt, trousers, trousers
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not model then model = simpleRig(shirt, skin) end
	model.Name = "Shopper"
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.WalkSpeed = 9 + math.random() * 4
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	CollectionService:AddTag(model, "HarbourNPC")
	return model
end

local function animate(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local ok, walk, idle = pcall(function()
		local w, i = Instance.new("Animation"), Instance.new("Animation")
		w.AnimationId, i.AnimationId = WALK_ANIM, IDLE_ANIM
		return animator:LoadAnimation(w), animator:LoadAnimation(i)
	end)
	if not ok then return end
	idle:Play()
	hum.Running:Connect(function(speed)
		if speed > 0.5 then if not walk.IsPlaying then walk:Play() end
		elseif walk.IsPlaying then walk:Stop() end
	end)
end

local function carryBag(model: Model, root: BasePart)
	local hand = model:FindFirstChild("RightHand") or root
	local bag = Instance.new("Part")
	bag.Name = "ShoppingBag"; bag.Size = Vector3.new(1.2, 1.4, 0.5); bag.CanCollide = false; bag.Massless = true
	bag.Color = Color3.fromHSV(math.random(), 0.6, 0.9); bag.Material = Enum.Material.Fabric
	bag.CFrame = hand.CFrame * CFrame.new(0, -1, 0)
	local w = Instance.new("WeldConstraint"); w.Part0 = hand; w.Part1 = bag; w.Parent = bag
	bag.Parent = model
end

local function shop(idx)
	local level = (#idx.entrances[1] > 0 and #idx.stores[1] > 0 and math.random() < 0.4) and 1 or 0
	local ents, stores = idx.entrances[level], idx.stores[level]
	if #ents == 0 or #stores == 0 then return end
	local entry = ents[math.random(#ents)]
	local model = makeShopper()
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model:PivotTo(CFrame.new(entry.out + Vector3.new(0, 3.5, 0), entry.inn))
	model.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	animate(hum)
	active += 1

	local function trip(): boolean
		if not moveStraight(hum, root, entry.inn) then return false end
		for _ = 1, math.random(1, 3) do
			local s = stores[math.random(#stores)]
			if not walkPath(hum, root, s.StoreFront) then return false end
			if not moveStraight(hum, root, s.StoreInside) then return false end
			if not moveStraight(hum, root, s.StoreTill) then return false end
			task.wait(3 + math.random() * 4) -- queueing and paying
			if ShopService.NpcBuy(s.shop) and not model:FindFirstChild("ShoppingBag") then carryBag(model, root) end
			if not moveStraight(hum, root, s.StoreInside) then return false end
			if not moveStraight(hum, root, s.StoreFront) then return false end
		end
		local exit = ents[math.random(#ents)]
		if not walkPath(hum, root, exit.inn) then return false end
		return moveStraight(hum, root, exit.out)
	end

	local ok, err = pcall(trip)
	if not ok then warn("[ShopperService] " .. tostring(err)) end
	active -= 1
	model:Destroy() -- finished, or stuck: either way they leave
end

local function playerNear(centre: Vector3): boolean
	for _, p in Players:GetPlayers() do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - centre).Magnitude < ACTIVE_RANGE then return true end
	end
	return false
end

function ShopperService.Start()
	folder = Instance.new("Folder")
	folder.Name = "MallShoppers"
	folder.Parent = workspace
	task.spawn(function()
		while true do
			task.wait(SPAWN_EVERY)
			if not (index and index.mall.Parent) then index = buildIndex() end
			if index and active < MAX_SHOPPERS and playerNear(index.centre) then task.spawn(shop, index) end
		end
	end)
end

return ShopperService
