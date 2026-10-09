local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Shared.Config)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local DataService = {}
-- GetDataStore throws in unpublished places; nil store means "temporary data only".
local storeOk, store = pcall(function() return DataStoreService:GetDataStore(Config.DataStoreName) end)
if not storeOk then
	warn("[Harbourlife] DataStores unavailable (" .. tostring(store) .. "); progress will not save")
	store = nil
end
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
		if i < tries then task.wait(2 ^ i) end
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
	if not d or not store or loadFailed[player] then return end -- never overwrite real data after a failed load
	tryAsync(function() store:SetAsync("p_" .. player.UserId, d) end, 3)
end

local function onJoin(player: Player)
	local tries = game:GetService("RunService"):IsStudio() and 1 or 3
	local ok, data = false, nil
	if store then ok, data = tryAsync(function() return store:GetAsync("p_" .. player.UserId) end, tries) end
	if not player.Parent then return end
	if not ok then
		loadFailed[player] = true -- never save over real data we couldn't read
		if game:GetService("RunService"):IsStudio() then
			-- Unpublished place / API access off: play with temporary data instead of kicking.
			warn("[Harbourlife] DataStore unavailable in Studio; using temporary data (nothing will save)")
			profiles[player] = defaultData()
			DataService.Push(player)
			return
		end
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
