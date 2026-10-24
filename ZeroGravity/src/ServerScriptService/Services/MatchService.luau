-- Match lifecycle:
--   Waiting -> Countdown -> Preparing -> Deploying -> Active -> Final -> Ending -> Results -> Waiting
-- Solo battle royale today; players carry a team id so duos/squads only need team assignment and
-- the "teams alive" check below to change.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.WeaponDefinitions)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Security = require(script.Parent.SecurityService)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local Inventory = require(script.Parent.InventoryService)
local Combat = require(script.Parent.CombatService)
local Loot = require(script.Parent.LootService)
local Oxygen = require(script.Parent.OxygenService)
local SafeZone = require(script.Parent.SafeZoneService)
local Hazards = require(script.Parent.HazardService)
local Bots = require(script.Parent.BotService)
local Lobby = require(script.Parent.Parent:WaitForChild("Builders"):WaitForChild("Lobby"))

local Match = {}
local M = Config.Match
local stateObj: Configuration
local participants: { Player } = {}
local matchSerial = 0
local matchStart = 0
local diedConns: { [Player]: RBXScriptConnection } = {}

local function setPhase(phase: string, duration: number?)
	stateObj:SetAttribute("Phase", phase)
	stateObj:SetAttribute("PhaseEndsAt", duration and workspace:GetServerTimeNow() + duration or 0)
end

-- Real (queued) players needed to start: with bots enabled one player gets a full 20-combatant match.
local function minPlayers(): number
	if Config.Bots.Enabled then return Config.Bots.MinRealPlayers end
	return RunService:IsStudio() and M.StudioMinPlayers or M.MinPlayers
end

local function lobbySpawnCFrame(): CFrame
	local spots = CollectionService:GetTagged("LobbySpawn")
	if #spots == 0 then return CFrame.new(Config.Arena.LobbyCenter) end
	local s = spots[math.random(1, #spots)] :: BasePart
	return s.CFrame -- markers face -Z: the panoramic window and the arena beyond it
end

-- Spawn in the lobby with the practice kit.
function Match.SendToLobby(player: Player)
	if Roster.IsBot(player) then
		Bots.ToLobby(player)
		return
	end
	task.spawn(function()
		local char = CharacterService.Spawn(player, lobbySpawnCFrame())
		if not char then return end
		Combat.ResetPlayer(player)
		Inventory.Reset(player, "practice")
		Oxygen.Reset(player)
	end)
end

local function eligibleQueued(): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		local r = Roster.Get(p)
		if r and r.queued and not r.inMatch and DataService.Get(p) and p.Character then table.insert(out, p) end
	end
	return out
end

local function aliveTeams(): number
	local teams = {}
	local n = 0
	for _, p in Roster.Alive() do
		local t = Roster.Get(p).team
		if not teams[t] then
			teams[t] = true
			n += 1
		end
	end
	return n
end

local function updateCounts()
	stateObj:SetAttribute("AliveCount", #Roster.Alive())
	stateObj:SetAttribute("Participants", #participants)
	stateObj:SetAttribute("Queued", #eligibleQueued())
	stateObj:SetAttribute("MinPlayers", minPlayers())
	stateObj:SetAttribute("Bots", #Bots.All())
	stateObj:SetAttribute("MaxPlayers", M.MaxPlayers)
end

-- Free of solid geometry and terrain?
local function isClear(pos: Vector3): boolean
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	if #workspace:GetPartBoundsInRadius(pos, 5, params) > 0 then return false end
	local region = Region3.new(pos - Vector3.one * 6, pos + Vector3.one * 6):ExpandToGrid(4)
	local materials = workspace.Terrain:ReadVoxels(region, 4)
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] ~= Enum.Material.Air then return false end
			end
		end
	end
	return true
end

-- Greedy spaced selection of deployment points inside the starting zone.
local function chooseDeployPoints(count: number): { CFrame }
	local candidates = {}
	for _, m in CollectionService:GetTagged("DeployPoint") do
		if m:IsA("BasePart") and m.Position.Magnitude < Config.Zone.StartRadius - 150 and isClear(m.Position) then
			table.insert(candidates, m.Position)
		end
	end
	for i = #candidates, 2, -1 do
		local j = math.random(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local chosen = {}
	local spacing = M.DeploySpacing
	while #chosen < count and spacing > 10 do
		for _, c in candidates do
			if #chosen >= count then break end
			local ok = true
			for _, ch in chosen do
				if (ch - c).Magnitude < spacing then
					ok = false
					break
				end
			end
			if ok then table.insert(chosen, c) end
		end
		spacing *= 0.7
	end
	-- Fallback: open points on a wide shell if the map ran out of markers
	local k = 0
	while #chosen < count and k < 200 do
		k += 1
		local p = Random.new():NextUnitVector() * 1300 * Vector3.new(1, 0.4, 1)
		if isClear(p) then table.insert(chosen, p) end
	end
	-- Last resort: evenly spaced points on a high ring so players never share a spawn
	local i = 0
	while #chosen < count do
		i += 1
		local a = (i / math.max(count, 1)) * math.pi * 2
		table.insert(chosen, Vector3.new(math.cos(a) * 1200, 700, math.sin(a) * 1200))
	end
	local out = {}
	for _, p in chosen do
		table.insert(out, CFrame.lookAt(p, Vector3.zero))
	end
	return out
end

local function weaponName(player: Player?): string?
	if not player then return nil end
	local w = Inventory.ActiveWeapon(player)
	return w and Weapons.Get(w.id).name or nil
end

local CAUSE_TEXT = {
	zone = "the radiation storm", hypoxia = "oxygen deprivation", electric = "an electrical fault", radiation = "reactor radiation",
	explosion = "an explosion", boundary = "the void", melee = "a suit-knife", weapon = "gunfire",
}

-- Elimination (death or disconnect while alive in the match).
local function eliminate(player: Player, disconnected: boolean)
	local r = Roster.Get(player)
	if not r or not r.alive or not r.inMatch then return end
	r.alive = false
	r.eliminatedAt = os.clock()
	r.placement = #Roster.Alive() + 1
	local killer = r.lastAttacker
	if killer and (os.clock() - r.lastAttackerAt > 12 or not killer.Parent or killer == player) then killer = nil end
	if killer then
		local kr = Roster.Get(killer)
		if kr then
			kr.kills += 1
			Roster.Sync(killer)
		end
	end
	local cause = disconnected and "disconnect" or (r.lastCause or "weapon")
	Remotes.FX:FireAllClients({
		t = "killfeed", killer = killer and killer.Name or nil, victim = player.Name, weapon = killer and weaponName(killer) or nil,
		cause = disconnected and "disconnected" or CAUSE_TEXT[cause] or cause,
	})
	-- Drop carried items in a suit locker
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Loot.SpawnDeathBox(root.Position, Inventory.DumpEntries(player), player.Name)
	end
	Inventory.Clear(player)
	Roster.Sync(player)
	updateCounts()
	if not disconnected then
		Remotes.Match:FireClient(player, { t = "eliminated", by = killer and killer.Name or nil, cause = CAUSE_TEXT[cause] or cause, placement = r.placement })
		local serial = matchSerial
		task.delay(3.5, function()
			if player.Parent and matchSerial == serial then Match.SendToLobby(player) end -- spectate from the lobby
		end)
	end
end

local function hookDeath(player: Player, char: Model)
	if diedConns[player] then diedConns[player]:Disconnect() end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	diedConns[player] = hum.Died:Connect(function()
		eliminate(player, false)
	end)
end

local function awardAndReport(winner: Player?)
	local total = #participants
	for _, p in participants do
		if p.Parent and not Roster.IsBot(p) then
			local r = Roster.Get(p)
			if p == winner then r.placement = 1 end
			local survived = (r.eliminatedAt > 0 and r.eliminatedAt or os.clock()) - r.deployedAt
			-- still alive at a time-limit finish without winning = runner-up
			local placement = r.placement > 0 and r.placement or (p == winner and 1 or 2)
			local stats = { kills = r.kills, damage = r.damage, placement = placement, survived = survived }
			local reward = DataService.AwardMatch(p, stats)
			Remotes.Match:FireClient(p, {
				t = "results", winner = winner and winner.Name or nil, placement = stats.placement, total = total, kills = stats.kills,
				damage = math.floor(stats.damage), survived = math.floor(survived), xp = reward.xp, credits = reward.credits,
				levelUp = reward.levelUp, level = reward.level,
			})
		end
	end
end

local function cleanupMatch()
	SafeZone.Stop()
	for p, c in diedConns do
		c:Disconnect()
		diedConns[p] = nil
	end
	for _, p in participants do
		if p.Parent then
			local r = Roster.Get(p)
			local wasAlive = r.alive
			r.inMatch, r.alive = false, false
			Roster.Sync(p)
			if wasAlive then Match.SendToLobby(p) end
		end
	end
	participants = {}
	Loot.ClearAll()
	for _, inst in workspace:GetChildren() do
		if inst.Name == "PulseCharge" then inst:Destroy() end
	end
	updateCounts()
end

local function runMatch()
	matchSerial += 1
	local serial = matchSerial
	-- PREPARING -------------------------------------------------------------------------------------
	setPhase("Preparing", M.PrepareTime)
	Lobby.SetStatus("PREPARING DEPLOYMENT")
	local queued = eligibleQueued()
	participants = {}
	for i, p in queued do
		if i > M.MaxPlayers then break end
		table.insert(participants, p)
	end
	-- top up with bots so every match is full
	if Config.Bots.Enabled then
		Bots.Rebalance()
		for _, b in Bots.ForMatch(M.MaxPlayers - #participants) do table.insert(participants, b) end
	end
	Loot.Seed()
	Hazards.Reset()
	local finals = CollectionService:GetTagged("FinalZone")
	local final = #finals > 0 and finals[math.random(1, #finals)] :: BasePart or nil
	local finalPos = final and final.Position or Vector3.zero
	local points = chooseDeployPoints(#participants)
	task.wait(M.PrepareTime)

	-- DEPLOYING -------------------------------------------------------------------------------------
	setPhase("Deploying", 3)
	Lobby.SetStatus("MATCH IN PROGRESS")
	matchStart = os.clock()
	local teamId = 0
	local deployed = {}
	for i, p in participants do
		if p.Parent then
			teamId += 1
			local r = Roster.Get(p)
			Roster.ResetMatchStats(p)
			r.inMatch, r.alive, r.team = true, true, teamId -- solo: one player per team
			r.deployedAt = os.clock()
			r.protectUntil = os.clock() + M.DeployProtection
			table.insert(deployed, p)
			task.spawn(function()
				local cf = points[i] or CFrame.new(0, 600, 0)
				local isBot = Roster.IsBot(p)
				local char = if isBot then Bots.Deploy(p, cf) else CharacterService.Spawn(p, cf)
				if not char or matchSerial ~= serial then return end
				hookDeath(p, char)
				Combat.ResetPlayer(p)
				Oxygen.Reset(p)
				local profile = not isBot and DataService.Get(p)
				Inventory.Reset(p, "match", if isBot then p.loadout else (profile and profile.loadout or "scout"))
				Roster.Sync(p)
				Remotes.Match:FireClient(p, { t = "deployed", protect = M.DeployProtection })
			end)
		end
	end
	participants = deployed
	task.wait(1.5)
	updateCounts()
	SafeZone.Begin(finalPos)
	Remotes.FX:FireAllClients({ t = "notice", text = "DEPLOYED - " .. #participants .. " combatants. Last one in orbit wins.", color = Color3.fromRGB(110, 190, 255), sound = "start" })

	-- ACTIVE / FINAL ---------------------------------------------------------------------------------
	setPhase("Active")
	local finalAnnounced = false
	local solo = #participants == 1
	while true do
		task.wait(0.5)
		updateCounts()
		local alive = #Roster.Alive()
		local teams = aliveTeams()
		local fewLeft = alive <= M.FinalPhaseAtPlayers and #participants > M.FinalPhaseAtPlayers
		if not finalAnnounced and (fewLeft or SafeZone.IsLastStage()) then
			finalAnnounced = true
			setPhase("Final")
			Remotes.FX:FireAllClients({ t = "notice", text = "FINAL COMBAT PHASE", color = Color3.fromRGB(255, 120, 60), sound = "alarm" })
		end
		if (solo and alive == 0) or (not solo and teams <= 1) or os.clock() - matchStart > M.MaxMatchTime then
			break
		end
	end

	-- ENDING ----------------------------------------------------------------------------------------
	local winner = nil
	local aliveNow = Roster.Alive()
	if #aliveNow == 1 then
		winner = aliveNow[1]
	elseif #aliveNow > 1 then
		-- time limit: highest health wins
		local best = -1
		for _, p in aliveNow do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local hp = hum and hum.Health or 0
			if hp > best then best, winner = hp, p end
		end
	end
	setPhase("Ending", 4)
	stateObj:SetAttribute("Winner", winner and winner.Name or "")
	Remotes.FX:FireAllClients({ t = "winner", name = winner and winner.Name or nil })
	Lobby.SetStatus(winner and ("WINNER: " .. string.upper(winner.Name)) or "NO SURVIVORS")
	if winner then
		Roster.Get(winner).protectUntil = math.huge -- no post-match deaths
	end
	SafeZone.Stop()
	task.wait(4)

	-- RESULTS ---------------------------------------------------------------------------------------
	awardAndReport(winner)
	setPhase("Results", M.ResultsTime)
	task.wait(M.ResultsTime)
	cleanupMatch()
	stateObj:SetAttribute("Winner", "")
end

local function loop()
	while true do
		-- WAITING -------------------------------------------------------------------------------------
		setPhase("Waiting")
		while #eligibleQueued() < minPlayers() do
			updateCounts()
			Lobby.SetStatus(string.format("WAITING FOR PLAYERS  %d / %d", #eligibleQueued(), minPlayers()))
			task.wait(1)
		end
		Bots.Rebalance() -- players may have joined or left during the last match
		-- COUNTDOWN -----------------------------------------------------------------------------------
		setPhase("Countdown", M.LobbyCountdown)
		local t0 = os.clock()
		local aborted = false
		while os.clock() - t0 < M.LobbyCountdown do
			updateCounts()
			if #eligibleQueued() < minPlayers() then
				aborted = true
				break
			end
			Lobby.SetStatus(string.format("DEPLOYMENT IN %d   |   %d PILOTS + %d BOTS", math.ceil(M.LobbyCountdown - (os.clock() - t0)),
				#eligibleQueued(), math.max(0, math.min(#Bots.All(), M.MaxPlayers - #eligibleQueued()))))
			task.wait(0.5)
		end
		if not aborted then
			local ok, err = pcall(runMatch)
			if not ok then
				warn("[ZG] match error: " .. tostring(err))
				cleanupMatch()
			end
		end
	end
end

function Match.Start()
	stateObj = Instance.new("Configuration")
	stateObj.Name = "MatchState"
	stateObj.Parent = ReplicatedStorage
	setPhase("Waiting")
	updateCounts()

	Remotes.Match.OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or not Security.RateLimit(player, "match", 4, 6) then return end
		local r = Roster.Get(player)
		if not r then return end
		if req.action == "queue" and type(req.value) == "boolean" then
			r.queued = req.value
			Roster.Sync(player)
			updateCounts()
		elseif req.action == "suit" and Security.IsString(req.id, 24) then
			if DataService.SetSuit(player, req.id) and player.Character then
				CharacterService.ApplySuit(player, player.Character, req.id)
			end
		elseif req.action == "loadout" and Security.IsString(req.id, 24) then
			DataService.SetLoadout(player, req.id)
		elseif req.action == "settings" then
			DataService.SetSettings(player, req.settings)
		elseif req.action == "profile" then
			DataService.Push(player)
		elseif req.action == "returnToLobby" then
			-- Winner leaving the arena early during Ending/Results
			local phase = stateObj:GetAttribute("Phase")
			if r.inMatch and r.alive and (phase == "Ending" or phase == "Results") then
				r.alive = false
				Roster.Sync(player)
				Match.SendToLobby(player)
			end
		end
	end)

	local function onJoin(player: Player)
		-- wait for the profile so cosmetics are known, then go to the lobby
		local t0 = os.clock()
		while player.Parent and not DataService.Get(player) and os.clock() - t0 < 15 do task.wait(0.2) end
		if player.Parent then Match.SendToLobby(player) end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end
	Players.PlayerRemoving:Connect(function(p)
		eliminate(p, true)
		for i, q in participants do
			if q == p then
				table.remove(participants, i)
				break
			end
		end
		if diedConns[p] then
			diedConns[p]:Disconnect()
			diedConns[p] = nil
		end
		updateCounts()
	end)
	task.spawn(loop)
end

return Match
