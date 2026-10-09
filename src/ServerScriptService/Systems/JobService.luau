local Jobs = require(game.ReplicatedStorage.Shared.JobDefinitions)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Progression = require(script.Parent.ProgressionService)
local Notify = require(script.Parent.NotificationService)

local J = {}

function J.SetJob(player: Player, jobId: string): boolean
	local d, def = DataService.Get(player), Jobs[jobId]
	if not d or not def then return false end
	if d.level < def.minLevel then
		Notify.Send(player, "You need level " .. def.minLevel .. " for " .. def.name, "error")
		return false
	end
	d.job = jobId
	DataService.Push(player)
	Notify.Send(player, "You are now: " .. def.name, "success")
	return true
end

-- Called by job systems when a real task finishes (cooked pizza, delivered order, ...).
-- The payout comes from server-side definitions only; callers can't pass amounts.
function J.CompleteTask(player: Player, jobId: string): boolean
	local d, def = DataService.Get(player), Jobs[jobId]
	if not d or not def or d.job ~= jobId or def.pay <= 0 then return false end
	Economy.AddCash(player, def.pay)
	Progression.AddXp(player, def.xp)
	if def.skill then Progression.AddSkillXp(player, def.skill, def.xp) end
	return true
end

return J
