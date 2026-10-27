-- ZERO GRAVITY: LAST ORBIT - server bootstrap.
-- Builds the world, then starts each service on its own so one failure is reported in Output
-- without stopping the rest.
local Services = script.Parent:WaitForChild("Services")
require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes")) -- create remotes first
workspace.Gravity = 0

local function start(name: string, ...)
	local args = { ... }
	local ok, err = pcall(function() require(Services[name]).Start(table.unpack(args)) end)
	if not ok then warn("[ZG] " .. name .. " failed to start: " .. tostring(err)) end
end

start("WorldBuilder")
start("Roster")
local Roster = require(Services.Roster)
local Combat = require(Services.CombatService)
start("SecurityService", Roster.IsActive, function(p, amount, cause) Combat.ApplyDamage(p, amount, nil, cause) end)
start("CharacterService")
start("DataService")
start("InventoryService")
start("CombatService")
start("LagCompensation")
start("LootService")
start("EventService")
start("OxygenService")
start("SafeZoneService")
start("EquipmentService")
start("HazardService")
start("BotService")
start("MatchService")
print("[ZG] server started")
