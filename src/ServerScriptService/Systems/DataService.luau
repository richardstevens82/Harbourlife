local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Shared.Config)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local DataService = {}
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local profiles: { [Player]: any } = {}
local loadFailed: { [Player]: boolean } = {}

local function defaultData()
	return { cash = Config.StartingCash, bank = Config.StartingBank, inventory = {}, xp = 0, level = 1, skills = {}, job = "unemployed", reputation = 0, vehicles = { sedan = { fuel = 60, condition = 100 } }, version = 1 }
end

local function reconcile(data)
	for k, v in defaultData() do
		if data[k] == nil then data[k] = v end
	end
	return data
end

local function tryAsync(fn, tries)
	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		task.wait(2 ^ i)
	end
	return false
end

function DataService.Get(player: Player)
	return profiles[player]
end

function DataService.Push(player: Player)
	local d = profiles[player]
	if d then Remotes.DataChanged:FireClient(player, { cash = d.cash, bank = d.bank, inventory = d.inventory, xp = d.xp, level = d.level, job = d.job, skills = d.skills, reputation = d.reputation }) end
end

function DataService.Save(player: Player)
	local d = profiles[player]
	if not d or loadFailed[player] then return end -- never overwrite real data after a failed load
	tryAsync(function() store:SetAsync("p_" .. player.UserId, d) end, 3)
end

local function onJoin(player: Player)
	local ok, data = tryAsync(function() return store:GetAsync("p_" .. player.UserId) end, 3)
	if not player.Parent then return end
	if not ok then
		loadFailed[player] = true
		player:Kick("Could not load your data. Rejoin to protect your progress.")
		return
	end
	profiles[player] = reconcile(data or {})
	DataService.Push(player)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onJoin)
	for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end
	Players.PlayerRemoving:Connect(function(p)
		DataService.Save(p)
		profiles[p] = nil
		loadFailed[p] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do task.spawn(DataService.Save, p) end
		task.wait(3)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for _, p in Players:GetPlayers() do task.spawn(DataService.Save, p) end
		end
	end)
end

return DataService
