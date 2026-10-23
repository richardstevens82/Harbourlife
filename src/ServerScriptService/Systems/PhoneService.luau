-- Server side of the phone apps. The client only asks; amounts and jobs are checked here.
--   ("deposit" | "withdraw", amount | "all")   Bank app
--   ("quitJob")                                 Jobs app
local Players = game:GetService("Players")
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local JobService = require(script.Parent.JobService)
local Notify = require(script.Parent.NotificationService)

local PhoneService = {}
local last: { [Player]: number } = {}

local function amountFor(d, action: string, arg: any): number?
	if arg == "all" then return action == "deposit" and d.cash or d.bank end
	if type(arg) ~= "number" or arg ~= arg or arg % 1 ~= 0 or arg <= 0 or arg > 1e9 then return nil end
	return arg
end

local function onAction(player: Player, action: any, arg: any)
	local now = os.clock()
	if now - (last[player] or 0) < 0.3 then return end
	last[player] = now
	local d = DataService.Get(player)
	if not d or type(action) ~= "string" then return end
	if action == "deposit" or action == "withdraw" then
		local amount = amountFor(d, action, arg)
		if not amount or amount <= 0 then Notify.Send(player, action == "deposit" and "No cash to deposit" or "Nothing in the bank", "error"); return end
		local ok = if action == "deposit" then Economy.Deposit(player, amount) else Economy.Withdraw(player, amount)
		if ok then Notify.Send(player, string.format("%s $%d", action == "deposit" and "Deposited" or "Withdrew", amount), "success")
		else Notify.Send(player, action == "deposit" and "Not enough cash" or "Not enough in the bank", "error") end
	elseif action == "quitJob" then
		if d.job ~= "unemployed" then JobService.SetJob(player, "unemployed") end
	end
end

function PhoneService.Start()
	Remotes.PhoneAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
end

return PhoneService
