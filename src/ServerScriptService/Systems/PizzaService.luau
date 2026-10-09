-- Pizza Business: supplier -> oven -> orders (counter / delivery) -> payment, XP, reputation.
-- Workspace markers (rename Parts, no scripts needed):
--   PizzaSupplier        buys ingredients
--   PizzaOven_<n>        cooks pizza
--   PizzaCounter         serves counter orders
--   PizzaDropoff_<n>     delivery destinations
local Players = game:GetService("Players")
local Items = require(game.ReplicatedStorage.Shared.ItemDefinitions)
local Recipes = require(game.ReplicatedStorage.Shared.RecipeDefinitions)
local Biz = require(game.ReplicatedStorage.Shared.BusinessDefinitions).pizza_shop
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local Progression = require(script.Parent.ProgressionService)
local JobService = require(script.Parent.JobService)
local Interaction = require(script.Parent.InteractionService)
local Notify = require(script.Parent.NotificationService)

local P = {}
local recipe = Recipes.pizza
local ovens: { [Instance]: { owner: Player?, doneAt: number?, ready: boolean } } = {}
local orders: { { id: number, kind: string, dropoff: string?, expires: number } } = {}
local nextId = 1
local dropoffNames: { string } = {}

local function takesPizzaJobs(player) -- anyone with the cook or driver job counts as staff
	local d = DataService.Get(player)
	return d and (d.job == "pizza_cook" or d.job == "delivery_driver")
end

local function staffOnline()
	for _, p in Players:GetPlayers() do if takesPizzaJobs(p) then return true end end
	return false
end

local function reputationChange(player, delta)
	local d = DataService.Get(player)
	if d then d.reputation += delta; DataService.Push(player) end
end

local function removeOrder(i) table.remove(orders, i) end

local function expireOrders()
	for i = #orders, 1, -1 do
		if os.clock() >= orders[i].expires then
			removeOrder(i)
			for _, p in Players:GetPlayers() do
				if takesPizzaJobs(p) then reputationChange(p, Biz.reputationOnExpire); Notify.Send(p, "An order expired", "error") end
			end
		end
	end
end

local function spawnOrder()
	if #orders >= Biz.maxOpenOrders then return end
	local isDelivery = #dropoffNames > 0 and math.random() < 0.5
	local o = {
		id = nextId, kind = isDelivery and "delivery" or "counter",
		dropoff = isDelivery and dropoffNames[math.random(#dropoffNames)] or nil,
		expires = os.clock() + Biz.orderLifetimeSeconds,
	}
	nextId += 1
	table.insert(orders, o)
	for _, p in Players:GetPlayers() do
		if takesPizzaJobs(p) then
			Notify.Send(p, o.kind == "delivery" and ("New delivery order: " .. o.dropoff) or "New counter order", "info")
		end
	end
end

local function findOrder(kind, dropoff)
	for i, o in orders do
		if o.kind == kind and (kind == "counter" or o.dropoff == dropoff) then return i, o end
	end
end

-- Supplier: buys one full set of ingredients for the pizza recipe, atomically.
local function buyIngredients(player)
	if not DataService.Get(player) then return end
	local cost = 0
	for id, n in recipe.inputs do cost += Items[id].price * n end
	if not Economy.SpendCash(player, cost) then Notify.Send(player, "Need $" .. cost, "error"); return end
	local added = {}
	for id, n in recipe.inputs do
		if Inventory.Add(player, id, n) then added[id] = n
		else
			for rid, rn in added do Inventory.Remove(player, rid, rn) end
			Economy.AddCash(player, cost)
			Notify.Send(player, "Inventory full", "error")
			return
		end
	end
	Notify.Send(player, "Bought ingredients for $" .. cost, "success")
end

local function ovenInteract(player, oven)
	local st = ovens[oven]
	local d = DataService.Get(player)
	if not d then return end
	-- stale owner left the game
	if st.owner and not st.owner.Parent then st.owner, st.doneAt, st.ready = nil, nil, false end
	if st.ready and st.owner == player then
		if not Inventory.Add(player, recipe.output, 1) then Notify.Send(player, "Inventory full", "error"); return end
		st.owner, st.doneAt, st.ready = nil, nil, false
		JobService.CompleteTask(player, "pizza_cook")
		Notify.Send(player, "Pizza ready", "success")
	elseif st.owner then
		if st.owner == player and st.doneAt then Notify.Send(player, "Still cooking...", "info")
		else Notify.Send(player, "Oven in use", "error") end
	else
		for id, n in recipe.inputs do
			if Inventory.Count(player, id) < n then Notify.Send(player, "Missing " .. Items[id].name, "error"); return end
		end
		for id, n in recipe.inputs do Inventory.Remove(player, id, n) end
		local secs = math.max(Biz.minCookSeconds, recipe.cookSeconds - Progression.SkillLevel(player, "cooking"))
		st.owner, st.doneAt, st.ready = player, os.clock() + secs, false
		task.delay(secs, function()
			if st.owner == player and st.doneAt then st.ready = true; st.doneAt = nil; Notify.Send(player, "Your pizza is ready!", "success") end
		end)
		Notify.Send(player, "Cooking for " .. secs .. "s", "info")
	end
end

local function serve(player, kind, dropoff)
	local i, o = findOrder(kind, dropoff)
	if not i then Notify.Send(player, "No matching order", "error"); return end
	if not Inventory.Remove(player, "pizza", 1) then Notify.Send(player, "You need a pizza", "error"); return end
	removeOrder(i)
	local mult = kind == "delivery" and Biz.deliveryMultiplier or Biz.counterMultiplier
	local price = math.floor(Items.pizza.price * mult)
	Economy.AddCash(player, price)
	local job = kind == "delivery" and "delivery_driver" or "pizza_cook"
	JobService.CompleteTask(player, job) -- extra job pay + XP only if the player holds that job
	Progression.AddXp(player, 5)
	reputationChange(player, Biz.reputationOnServe)
	Notify.Send(player, "Order complete: +$" .. price, "success")
end

local function hook(inst: Instance)
	if not inst:IsA("BasePart") then return end
	if inst.Name == "PizzaSupplier" then
		Interaction.Register(inst, { action = "Buy ingredients", object = "Supplier", onTriggered = buyIngredients })
	elseif inst.Name:match("^PizzaOven_") then
		ovens[inst] = { ready = false }
		Interaction.Register(inst, { action = "Use oven", object = "Pizza Oven", onTriggered = function(p) ovenInteract(p, inst) end })
	elseif inst.Name == "PizzaCounter" then
		Interaction.Register(inst, { action = "Serve order", object = "Counter", onTriggered = function(p) serve(p, "counter") end })
	elseif inst.Name:match("^PizzaDropoff_") then
		table.insert(dropoffNames, inst.Name)
		Interaction.Register(inst, { action = "Deliver pizza", object = inst.Name, onTriggered = function(p) serve(p, "delivery", inst.Name) end })
	end
end

function P.Start()
	for _, d in workspace:GetDescendants() do hook(d) end
	workspace.DescendantAdded:Connect(hook)
	task.spawn(function()
		while true do
			task.wait(Biz.orderIntervalSeconds)
			expireOrders()
			if staffOnline() then spawnOrder() end
		end
	end)
end

-- test hook
function P._orders() return orders end

return P
