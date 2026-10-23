-- Food businesses (Phase 5): café, bakery, restaurant, fast food. One data-driven loop for all of them:
-- Food Wholesaler (a shop) -> ingredients -> station cooks a menu recipe -> counter serves a customer order
-- -> payment, job pay, XP, reputation. Definitions live in BusinessDefinitions (entries with food = true).
-- Workspace markers per business, e.g. the café:
--   CafeCounter              serves orders (shows open orders above it); CafeCounter_2 etc. for more branches
--   CafeCoffeeMachine_<n>    a station; prefix -> appliance type in the definition
local Players = game:GetService("Players")
local Items = require(game.ReplicatedStorage.Shared.ItemDefinitions)
local Recipes = require(game.ReplicatedStorage.Shared.RecipeDefinitions)
local Businesses = require(game.ReplicatedStorage.Shared.BusinessDefinitions)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local Progression = require(script.Parent.ProgressionService)
local JobService = require(script.Parent.JobService)
local Interaction = require(script.Parent.InteractionService)
local Notify = require(script.Parent.NotificationService)

type Order = { id: number, item: string, expires: number }
type Station = { biz: string, kind: string, owner: Player?, recipe: string?, doneAt: number?, ready: boolean }

local F = {}
local foodBiz: { [string]: any } = {}
local orders: { [string]: { Order } } = {}
local stations: { [Instance]: Station } = {}
local boards: { [string]: { TextLabel } } = {}
local nextId = 1

local function isStaff(player: Player, bizId: string): boolean
	local d = DataService.Get(player)
	return d ~= nil and table.find(foodBiz[bizId].jobs, d.job) ~= nil
end

local function staffOf(bizId: string): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do if isStaff(p, bizId) then table.insert(list, p) end end
	return list
end

local function reputationChange(player: Player, delta: number)
	local d = DataService.Get(player)
	if d then d.reputation += delta; DataService.Push(player) end
end

local function refreshBoard(bizId: string)
	local names = {}
	for _, o in orders[bizId] do table.insert(names, Items[o.item].name) end
	local text = #names > 0 and ("Orders: " .. table.concat(names, ", ")) or "No orders"
	for _, label in boards[bizId] or {} do label.Text = text end
end

local function spawnOrder(bizId: string)
	local def = foodBiz[bizId]
	if #orders[bizId] >= def.maxOpenOrders then return end
	local o = { id = nextId, item = def.menu[math.random(#def.menu)], expires = os.clock() + def.orderLifetimeSeconds }
	nextId += 1
	table.insert(orders[bizId], o)
	refreshBoard(bizId)
	for _, p in staffOf(bizId) do Notify.Send(p, def.name .. ": new order, " .. Items[o.item].name, "info") end
end

local function expireOrders(bizId: string)
	local list, changed = orders[bizId], false
	for i = #list, 1, -1 do
		if os.clock() >= list[i].expires then
			local o = table.remove(list, i)
			changed = true
			for _, p in staffOf(bizId) do
				reputationChange(p, foodBiz[bizId].reputationOnExpire)
				Notify.Send(p, Items[o.item].name .. " order expired", "error")
			end
		end
	end
	if changed then refreshBoard(bizId) end
end

local function hasInputs(player: Player, recipeId: string): boolean
	for id, n in Recipes[recipeId].inputs do
		if Inventory.Count(player, id) < n then return false end
	end
	return true
end

-- Recipes this station can make, oldest open order first, then the rest of the menu.
local function candidates(st: Station): { string }
	local list = {}
	local function add(r)
		if Recipes[r].station == st.kind and not table.find(list, r) then table.insert(list, r) end
	end
	for _, o in orders[st.biz] do add(o.item) end
	for _, r in foodBiz[st.biz].menu do add(r) end
	return list
end

local function describeInputs(recipeId: string): string
	local parts = {}
	for id, n in Recipes[recipeId].inputs do table.insert(parts, n .. "x " .. Items[id].name) end
	table.sort(parts)
	return table.concat(parts, " + ")
end

local function resetStation(st: Station)
	st.owner, st.recipe, st.doneAt, st.ready = nil, nil, nil, false
end

local function stationInteract(player: Player, part: Instance)
	local st = stations[part]
	if not DataService.Get(player) then return end
	if st.owner and not st.owner.Parent then resetStation(st) end -- owner left the game
	if st.ready and st.owner == player then
		local out = Recipes[st.recipe].output
		if not Inventory.Add(player, out, 1) then Notify.Send(player, "Inventory full", "error"); return end
		resetStation(st)
		local d = DataService.Get(player)
		if d and table.find(foodBiz[st.biz].jobs, d.job) then JobService.CompleteTask(player, d.job) end
		Notify.Send(player, Items[out].name .. " ready", "success")
	elseif st.owner then
		if st.owner == player then Notify.Send(player, "Still cooking...", "info")
		else Notify.Send(player, "In use by " .. st.owner.Name, "error") end
	else
		local list = candidates(st)
		local pick
		for _, r in list do
			if hasInputs(player, r) then pick = r; break end
		end
		if not pick then
			Notify.Send(player, "Need " .. describeInputs(list[1]) .. " for " .. Items[Recipes[list[1]].output].name .. " (Food Wholesaler)", "error")
			return
		end
		for id, n in Recipes[pick].inputs do Inventory.Remove(player, id, n) end
		local secs = math.max(foodBiz[st.biz].minCookSeconds, Recipes[pick].cookSeconds - Progression.SkillLevel(player, "cooking"))
		st.owner, st.recipe, st.doneAt, st.ready = player, pick, os.clock() + secs, false
		local token = st.doneAt
		task.delay(secs, function()
			if st.owner == player and st.doneAt == token then
				st.ready, st.doneAt = true, nil
				Notify.Send(player, Items[Recipes[pick].output].name .. " is ready to collect", "success")
			end
		end)
		Notify.Send(player, "Making " .. Items[Recipes[pick].output].name .. " (" .. secs .. "s)", "info")
	end
end

-- Serves the oldest order whose item the player is carrying.
local function serve(player: Player, bizId: string)
	if not DataService.Get(player) then return end
	local def = foodBiz[bizId]
	for i, o in orders[bizId] do
		if Inventory.Count(player, o.item) > 0 then
			if not Inventory.Remove(player, o.item, 1) then return end
			table.remove(orders[bizId], i)
			refreshBoard(bizId)
			local price = math.floor(Items[o.item].price * def.counterMultiplier)
			Economy.AddCash(player, price)
			local d = DataService.Get(player)
			if d and table.find(def.jobs, d.job) then JobService.CompleteTask(player, d.job) end
			Progression.AddXp(player, 5)
			reputationChange(player, def.reputationOnServe)
			Notify.Send(player, "Served " .. Items[o.item].name .. ": +$" .. price, "success")
			return
		end
	end
	Notify.Send(player, #orders[bizId] > 0 and "You don't have anything that was ordered" or "No orders right now", "error")
end

local function addBoard(part: BasePart, bizId: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OrderBoard"
	gui.Size = UDim2.fromOffset(260, 40)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 80
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = gui
	boards[bizId] = boards[bizId] or {}
	table.insert(boards[bizId], label)
	refreshBoard(bizId)
end

local function hook(inst: Instance)
	if not inst:IsA("BasePart") then return end
	for bizId, def in foodBiz do
		if inst.Name == def.counter or inst.Name:match("^" .. def.counter .. "_%d+$") then
			addBoard(inst, bizId)
			Interaction.Register(inst, { action = "Serve order", object = def.name, onTriggered = function(p) serve(p, bizId) end })
			return
		end
		for prefix, kind in def.stations do
			if inst.Name:match("^" .. prefix .. "_%d+$") then
				stations[inst] = { biz = bizId, kind = kind, ready = false }
				Interaction.Register(inst, { action = "Use", object = inst.Name, onTriggered = function(p) stationInteract(p, inst) end })
				return
			end
		end
	end
end

function F.Start()
	for id, def in Businesses do
		if def.food then
			for _, r in def.menu do
				assert(Recipes[r] and Items[Recipes[r].output], "FoodService: bad menu recipe " .. r .. " in " .. id)
				for ing in Recipes[r].inputs do assert(Items[ing], "FoodService: unknown ingredient " .. ing) end
			end
			foodBiz[id] = def
			orders[id] = {}
		end
	end
	for _, d in workspace:GetDescendants() do hook(d) end
	workspace.DescendantAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(p)
		for _, st in stations do if st.owner == p then resetStation(st) end end
	end)
	for id, def in foodBiz do
		task.spawn(function()
			while true do
				task.wait(def.orderIntervalSeconds)
				expireOrders(id)
				if #staffOf(id) > 0 then spawnOrder(id) end
			end
		end)
	end
end

-- test hooks
function F._orders(bizId: string) return orders[bizId] end

return F
