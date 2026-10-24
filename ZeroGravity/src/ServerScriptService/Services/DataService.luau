-- Persistent progression (XP, level, credits, lifetime stats, cosmetic choice, loadout choice).
-- Match state is never saved here. UpdateAsync with retries; temporary data in Studio when
-- DataStores are unavailable; never overwrites real data after a failed load.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Loadouts = require(Shared.Loadouts)
local Remotes = require(Shared.Remotes)

local DataService = {}
local storeOk, store = pcall(function() return DataStoreService:GetDataStore(Config.DataStoreName) end)
if not storeOk then
	warn("[ZG] DataStores unavailable (" .. tostring(store) .. "); progress will not save")
	store = nil
end

local profiles: { [Player]: any } = {}
local loadFailed: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

local VERSION = 1
local function defaultData()
	return {
		version = VERSION, xp = 0, level = 1, credits = 0,
		matches = 0, wins = 0, kills = 0, damage = 0, bestPlacement = 0, timeSurvived = 0,
		suit = "navy", title = "recruit", loadout = "scout",
		settings = { sensitivity = 1, invertY = false, fov = Config.Camera.DefaultFov },
	}
end

local function reconcile(data)
	local d = defaultData()
	for k, v in d do
		if data[k] == nil then data[k] = v end
	end
	for k, v in d.settings do
		if data.settings[k] == nil then data.settings[k] = v end
	end
	return data
end

local function tryAsync(fn, tries: number)
	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		warn("[ZG] DataStore call failed (" .. i .. "/" .. tries .. "): " .. tostring(res))
		if i < tries then task.wait(2 ^ i) end
	end
	return false, nil
end

function DataService.Get(player: Player)
	return profiles[player]
end

function DataService.Push(player: Player)
	local d = profiles[player]
	if not d then return end
	player:SetAttribute("Level", d.level)
	player:SetAttribute("Suit", d.suit)
	Remotes.Match:FireClient(player, { t = "profile", data = d, temporary = (store == nil or loadFailed[player] == true) })
end

function DataService.Save(player: Player)
	local d = profiles[player]
	if not d or not store or loadFailed[player] or not dirty[player] then return end
	local key = "p_" .. player.UserId
	local ok = tryAsync(function()
		store:UpdateAsync(key, function(old)
			-- Never regress progress if another server saved more XP (e.g. quick rejoin race).
			if old and type(old) == "table" and (old.xp or 0) > d.xp then return nil end
			return d
		end)
	end, 3)
	if ok then dirty[player] = nil end
end

local function levelFromXp(xp: number): number
	local level = 1
	while xp >= Config.XpForLevel(level) and level < 100 do
		level += 1
	end
	return level
end
DataService.LevelFromXp = levelFromXp

-- Applies a finished match's results. Returns the reward summary shown on the results screen.
function DataService.AwardMatch(player: Player, stats)
	local d = profiles[player]
	local R = Config.Rewards
	local xp = R.Participation + stats.kills * R.PerKill + math.floor(stats.damage * R.PerDamage)
		+ (R.PlacementBonus[stats.placement] or 0) + (stats.placement == 1 and R.WinBonus or 0)
	local credits = math.floor(xp * R.CreditsPerXp)
	if not d then return { xp = xp, credits = credits, levelUp = false } end
	local oldLevel = d.level
	d.xp += xp
	d.credits += credits
	d.matches += 1
	d.kills += stats.kills
	d.damage += math.floor(stats.damage)
	d.timeSurvived += math.floor(stats.survived)
	if stats.placement == 1 then d.wins += 1 end
	if d.bestPlacement == 0 or stats.placement < d.bestPlacement then d.bestPlacement = stats.placement end
	d.level = levelFromXp(d.xp)
	dirty[player] = true
	DataService.Push(player)
	task.spawn(DataService.Save, player)
	return { xp = xp, credits = credits, levelUp = d.level > oldLevel, level = d.level }
end

function DataService.SetSuit(player: Player, id: string)
	local d = profiles[player]
	if not d then return false end
	for _, s in Cosmetics.Suits do
		if s.id == id and Cosmetics.IsUnlocked(s, d) then
			d.suit = id
			dirty[player] = true
			DataService.Push(player)
			return true
		end
	end
	return false
end

function DataService.SetLoadout(player: Player, id: string)
	local d = profiles[player]
	if not d or Loadouts.Get(id).id ~= id then return false end
	d.loadout = id
	dirty[player] = true
	DataService.Push(player)
	return true
end

function DataService.SetSettings(player: Player, s)
	local d = profiles[player]
	if not d or type(s) ~= "table" then return end
	if type(s.sensitivity) == "number" then d.settings.sensitivity = math.clamp(s.sensitivity, 0.2, 3) end
	if type(s.invertY) == "boolean" then d.settings.invertY = s.invertY end
	if type(s.fov) == "number" then d.settings.fov = math.clamp(s.fov, 60, 100) end
	dirty[player] = true
end

local function onJoin(player: Player)
	local ok, data = false, nil
	if store then
		ok, data = tryAsync(function() return store:GetAsync("p_" .. player.UserId) end, RunService:IsStudio() and 1 or 3)
	end
	if not player.Parent then return end
	if not ok then
		loadFailed[player] = true
		if store and not RunService:IsStudio() then
			player:Kick("Could not load your progress. Please rejoin so it is not lost.")
			return
		end
		profiles[player] = defaultData() -- temporary (Studio / DataStores off): nothing saves
	else
		profiles[player] = reconcile(type(data) == "table" and data or {})
	end
	DataService.Push(player)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onJoin)
	for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end
	Players.PlayerRemoving:Connect(function(p)
		DataService.Save(p)
		profiles[p], loadFailed[p], dirty[p] = nil, nil, nil
	end)
	game:BindToClose(function()
		local threads = {}
		for _, p in Players:GetPlayers() do
			table.insert(threads, task.spawn(DataService.Save, p))
		end
		task.wait(3)
	end)
	-- periodic autosave
	task.spawn(function()
		while true do
			task.wait(120)
			for _, p in Players:GetPlayers() do task.spawn(DataService.Save, p) end
		end
	end)
end

return DataService
