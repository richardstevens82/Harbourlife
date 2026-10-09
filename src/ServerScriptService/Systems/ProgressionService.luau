local Config = require(game.ReplicatedStorage.Shared.Config)
local Skills = require(game.ReplicatedStorage.Shared.SkillDefinitions)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.NotificationService)

local P = {}

function P.XpForNext(level: number): number
	return math.floor(Config.XpBase * level ^ Config.XpExponent)
end

function P.AddXp(player: Player, amount: number): boolean
	local d = DataService.Get(player)
	if not d or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > 1e6 then return false end
	d.xp += math.floor(amount)
	while d.level < Config.MaxLevel and d.xp >= P.XpForNext(d.level) do
		d.xp -= P.XpForNext(d.level)
		d.level += 1
		Notify.Send(player, "Level up! You are now level " .. d.level, "success")
	end
	if d.level >= Config.MaxLevel then d.xp = 0 end
	DataService.Push(player)
	return true
end

-- skills[id] = { level, xp }
function P.AddSkillXp(player: Player, skillId: string, amount: number): boolean
	local d = DataService.Get(player)
	if not d or not Skills[skillId] or type(amount) ~= "number" or amount <= 0 or amount > 1e6 then return false end
	local s = d.skills[skillId] or { level = 1, xp = 0 }
	d.skills[skillId] = s
	if s.level >= Config.MaxSkillLevel then return true end
	s.xp += math.floor(amount)
	while s.level < Config.MaxSkillLevel and s.xp >= Config.SkillXpBase * s.level do
		s.xp -= Config.SkillXpBase * s.level
		s.level += 1
		Notify.Send(player, Skills[skillId].name .. " is now level " .. s.level, "success")
	end
	DataService.Push(player)
	return true
end

function P.SkillLevel(player: Player, skillId: string): number
	local d = DataService.Get(player)
	return d and d.skills[skillId] and d.skills[skillId].level or 1
end

return P
