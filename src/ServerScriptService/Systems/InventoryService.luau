local Config = require(game.ReplicatedStorage.Shared.Config)
local Items = require(game.ReplicatedStorage.Shared.ItemDefinitions)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)

local Inventory = {}

local function slotsUsed(inv) local n = 0 for _ in inv do n += 1 end return n end

function Inventory.Count(player, itemId): number
	local d = DataService.Get(player)
	return d and d.inventory[itemId] or 0
end

-- Returns false (and changes nothing) if the item is unknown or the inventory is full.
function Inventory.Add(player, itemId: string, qty: number): boolean
	local d, def = DataService.Get(player), Items[itemId]
	if not d or not def or type(qty) ~= "number" or qty < 1 or qty % 1 ~= 0 then return false end
	local have = d.inventory[itemId] or 0
	if have == 0 and slotsUsed(d.inventory) >= Config.InventorySlots then return false end
	if have + qty > (def.stack or Config.MaxStack) then return false end
	d.inventory[itemId] = have + qty
	DataService.Push(player)
	return true
end

function Inventory.Remove(player, itemId: string, qty: number): boolean
	local d = DataService.Get(player)
	if not d or type(qty) ~= "number" or qty < 1 or qty % 1 ~= 0 then return false end
	local have = d.inventory[itemId] or 0
	if have < qty then return false end
	d.inventory[itemId] = have > qty and have - qty or nil
	DataService.Push(player)
	return true
end

-- Atomic purchase: cash is refunded if the item can't be added.
function Inventory.Buy(player, itemId: string, qty: number): boolean
	local def = Items[itemId]
	if not def or type(qty) ~= "number" or qty < 1 or qty % 1 ~= 0 then return false end
	if not Economy.SpendCash(player, def.price * qty) then return false end
	if not Inventory.Add(player, itemId, qty) then
		Economy.AddCash(player, def.price * qty)
		return false
	end
	return true
end

return Inventory
