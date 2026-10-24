-- Creates (server) or waits for (client) the game's few RemoteEvents.
-- Client -> server requests always carry an `action` string and are validated by the owning service.
--   Combat:    fire / reload / equip / melee            (CombatService)
--   Inventory: use / drop                               (InventoryService)  server -> client: inventory sync
--   Equipment: tether / tetherRelease / grenade         (EquipmentService)
--   Match:     queue / unqueue / cosmetic               (MatchService)      server -> client: phase, results
--   FX:        server -> clients only (tracers, kill feed, hit markers, damage indicators, notices)
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Combat", "Inventory", "Equipment", "Match", "FX" }
local Remotes = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name)
end
return Remotes
