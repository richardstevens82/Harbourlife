-- Creates (server) or waits for (client) the game's few RemoteEvents.
-- Client -> server requests always carry an `action` string and are validated by the owning service.
--   Combat:    fire / reload / equip / melee            (CombatService)
--   Inventory: use / drop                               (InventoryService)  server -> client: inventory sync
--   Equipment: tether / tetherRelease / grenade         (EquipmentService)
--   Match:     queue / unqueue / cosmetic               (MatchService)      server -> client: phase, results
--   FX:        server -> clients only (kill feed, hit markers, damage indicators, notices, ...)
--   FXFast:    server -> clients, UnreliableRemoteEvent: batched tracers (cosmetic; a lost packet only
--              loses a tracer, and nothing waits on resends)
-- On the server each entry is a thin wrapper (FireClient / FireAllClients / OnServerEvent) so bots can
-- be addressed like players; on the client each entry is the RemoteEvent itself.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Combat", "Inventory", "Equipment", "Match", "FX", "FXFast" }
local UNRELIABLE = { FXFast = true }
local Remotes = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local r = Instance.new(if UNRELIABLE[name] then "UnreliableRemoteEvent" else "RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

-- Server side: wrap each RemoteEvent so a message addressed to a bot (a server-side combatant that
-- is not a Player instance) goes to the bot brain via Remotes.BotSink instead of the network.
Remotes.BotSink = nil :: ((any, string, any) -> ())?
for _, name in NAMES do
	local remote = folder:WaitForChild(name) :: any
	if RunService:IsServer() then
		Remotes[name] = {
			Instance = remote,
			OnServerEvent = remote.OnServerEvent,
			FireClient = function(_, target, msg)
				if typeof(target) == "Instance" then
					remote:FireClient(target, msg)
				elseif Remotes.BotSink then
					Remotes.BotSink(target, name, msg)
				end
			end,
			FireAllClients = function(_, msg)
				remote:FireAllClients(msg)
			end,
			-- client-side members, unused on a real server (the headless tests run both sides in one VM)
			OnClientEvent = remote.OnClientEvent,
			FireServer = function(_, msg)
				remote:FireServer(msg)
			end,
		}
	else
		Remotes[name] = remote
	end
end
return Remotes
