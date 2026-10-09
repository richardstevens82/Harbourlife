local DataService = require(script.Parent.DataService)

local Economy = {}

local function valid(n) return type(n) == "number" and n == n and n > 0 and n < 1e9 and n % 1 == 0 end

function Economy.AddCash(player: Player, amount: number): boolean
	local d = DataService.Get(player)
	if not d or not valid(amount) then return false end
	d.cash += amount
	DataService.Push(player)
	return true
end

function Economy.SpendCash(player: Player, amount: number): boolean
	local d = DataService.Get(player)
	if not d or not valid(amount) or d.cash < amount then return false end
	d.cash -= amount
	DataService.Push(player)
	return true
end

function Economy.Deposit(player: Player, amount: number): boolean
	local d = DataService.Get(player)
	if not d or not valid(amount) or d.cash < amount then return false end
	d.cash -= amount; d.bank += amount
	DataService.Push(player)
	return true
end

function Economy.Withdraw(player: Player, amount: number): boolean
	local d = DataService.Get(player)
	if not d or not valid(amount) or d.bank < amount then return false end
	d.bank -= amount; d.cash += amount
	DataService.Push(player)
	return true
end

return Economy
