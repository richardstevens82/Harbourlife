-- Retail: browse a shop at its counter, buy with server-validated price, range and stock.
local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Shared.Config)
local Items = require(game.ReplicatedStorage.Shared.ItemDefinitions)
local Shops = require(game.ReplicatedStorage.Shared.ShopDefinitions)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local Interaction = require(script.Parent.InteractionService)
local Notify = require(script.Parent.NotificationService)

local ShopService = {}
local counters: { [string]: { BasePart } } = {}
local stock: { [string]: { [string]: number } } = {}
local lastBuy: { [Player]: number } = {}

function ShopService.Price(shopId: string, itemId: string): number
	return math.ceil(Items[itemId].price * Shops[shopId].markup)
end

local function nearShop(player: Player, shopId: string): boolean
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	for _, p in counters[shopId] or {} do
		if p.Parent and (p.Position - hrp.Position).Magnitude <= Config.ShopRange then return true end
	end
	return false
end

local function payload(shopId: string)
	local def = Shops[shopId]
	local list = {}
	for _, id in def.items do
		table.insert(list, { id = id, name = Items[id].name, price = ShopService.Price(shopId, id), stock = stock[shopId][id] })
	end
	return { id = shopId, name = def.name, items = list }
end

local function open(player: Player, shopId: string)
	Remotes.OpenShop:FireClient(player, payload(shopId))
end

local function buy(player: Player, shopId: any, itemId: any, qty: any)
	-- validate everything the client sent
	if type(shopId) ~= "string" or type(itemId) ~= "string" or type(qty) ~= "number" then return end
	local def = Shops[shopId]
	if not def or not Items[itemId] or not table.find(def.items, itemId) then return end
	if qty ~= qty or qty % 1 ~= 0 or qty < 1 or qty > Config.ShopMaxQty then return end
	local now = os.clock()
	if now - (lastBuy[player] or 0) < 0.2 then return end
	lastBuy[player] = now
	if not DataService.Get(player) then return end
	if not nearShop(player, shopId) then Notify.Send(player, "Walk back to the counter", "error"); return end

	if stock[shopId][itemId] < qty then Notify.Send(player, "Out of stock", "error"); open(player, shopId); return end
	local total = ShopService.Price(shopId, itemId) * qty
	if not Economy.SpendCash(player, total) then Notify.Send(player, "Need $" .. total, "error"); return end
	if not Inventory.Add(player, itemId, qty) then
		Economy.AddCash(player, total) -- refund
		Notify.Send(player, "No room in your inventory", "error")
		return
	end
	stock[shopId][itemId] -= qty
	Notify.Send(player, string.format("Bought %dx %s for $%d", qty, Items[itemId].name, total), "success")
	open(player, shopId) -- refresh stock on the client
end

local function hook(inst: Instance)
	if not inst:IsA("BasePart") then return end
	local shopId = inst.Name:match("^Shop_(.+)$")
	if not shopId or not Shops[shopId] then return end
	counters[shopId] = counters[shopId] or {}
	table.insert(counters[shopId], inst)
	Interaction.Register(inst, { action = "Browse", object = Shops[shopId].name, onTriggered = function(p) open(p, shopId) end })
end

function ShopService.Start()
	for id, def in Shops do
		stock[id] = {}
		for _, itemId in def.items do
			assert(Items[itemId], "ShopDefinitions: unknown item " .. itemId .. " in " .. id)
			stock[id][itemId] = def.stock
		end
	end
	for _, d in workspace:GetDescendants() do hook(d) end
	workspace.DescendantAdded:Connect(hook)
	Remotes.ShopBuy.OnServerEvent:Connect(buy)
	Players.PlayerRemoving:Connect(function(p) lastBuy[p] = nil end)
	-- one restock loop for all shops
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(5)
			elapsed += 5
			for id, def in Shops do
				if elapsed % def.restockSeconds < 5 then
					for itemId, n in stock[id] do stock[id][itemId] = math.min(def.stock, n + 1) end
				end
			end
		end
	end)
end

return ShopService
