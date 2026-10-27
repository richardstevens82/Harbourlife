-- Per-combatant match state (never persisted). The single source of truth for "is this combatant
-- active right now". A combatant is a Player or a bot (BotService): bots are tables that expose the
-- same surface the services use (Name, UserId, Parent, Character, GetAttribute, SetAttribute).
-- Mirrors the fields clients need onto attributes.
local Players = game:GetService("Players")

local Roster = {}
local records: { [any]: any } = {}
local characterOwner: { [Model]: any } = {} -- bot characters -> bot

local function fresh()
	return {
		queued = true, -- wants to join the next match
		inMatch = false, -- deployed in the current match
		alive = false, -- in match and not eliminated
		team = 0,
		kills = 0,
		damage = 0,
		deployedAt = 0,
		eliminatedAt = 0,
		placement = 0,
		protectUntil = 0,
		lastHurt = 0,
		lastAttacker = nil :: Player?,
		lastAttackerAt = 0,
		loadout = "scout",
		chain = 0, lastKillAt = -math.huge, medals = 0, -- kill medals (MatchService)
		lastHead = false, lastDist = 0, -- how the last weapon hit landed (headshot medal, long shot)
	}
end

function Roster.IsBot(c): boolean
	return type(c) == "table" and c.IsBot == true
end

-- Player or bot owning a character model (nil for anything else).
function Roster.FromCharacter(model: Instance?)
	if not model or not model:IsA("Model") then return nil end
	return Players:GetPlayerFromCharacter(model) or characterOwner[model :: Model]
end

function Roster.BindCharacter(model: Model, bot)
	characterOwner[model] = bot
end

function Roster.UnbindCharacter(model: Model)
	characterOwner[model] = nil
end

function Roster.Remove(c)
	records[c] = nil
end

function Roster.Get(player: Player)
	local r = records[player]
	if not r and player.Parent then
		r = fresh()
		records[player] = r
	end
	return r
end

-- Active combatant: deployed, not eliminated, has a living character.
function Roster.IsActive(player: Player): boolean
	local r = records[player]
	if not (r and r.inMatch and r.alive) then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

function Roster.Active(): { Player }
	local out = {}
	for p in records do
		if p.Parent and Roster.IsActive(p) then table.insert(out, p) end
	end
	return out
end

function Roster.Alive(): { Player }
	local out = {}
	for p, r in records do
		if p.Parent and r.inMatch and r.alive then table.insert(out, p) end
	end
	return out
end

function Roster.Sync(player: Player)
	local r = records[player]
	if not r then return end
	player:SetAttribute("InMatch", r.inMatch)
	player:SetAttribute("Alive", r.alive)
	player:SetAttribute("Queued", r.queued)
	player:SetAttribute("Kills", r.kills)
end

function Roster.ResetMatchStats(player: Player)
	local r = Roster.Get(player)
	r.kills, r.damage, r.deployedAt, r.eliminatedAt, r.placement = 0, 0, 0, 0, 0
	r.lastAttacker, r.lastAttackerAt, r.lastHurt, r.protectUntil = nil, 0, 0, 0
	r.chain, r.lastKillAt, r.medals, r.lastHead, r.lastDist = 0, -math.huge, 0, false, 0
end

function Roster.Start()
	Players.PlayerAdded:Connect(function(p)
		Roster.Get(p)
		Roster.Sync(p)
	end)
	for _, p in Players:GetPlayers() do
		Roster.Get(p)
		Roster.Sync(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		task.defer(function() records[p] = nil end) -- after MatchService has processed the leave
	end)
end

return Roster
