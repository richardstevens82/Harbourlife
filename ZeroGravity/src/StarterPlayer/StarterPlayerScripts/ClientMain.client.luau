-- ZERO GRAVITY: LAST ORBIT - client bootstrap. Starts the controllers and routes server
-- messages (FX / Match / Inventory remotes) into ClientState signals and effects.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Controllers = script.Parent:WaitForChild("Controllers")
local State = require(Controllers.ClientState)
local player = Players.LocalPlayer

-- Our own HUD replaces the default health bar, backpack and player list (Tab = inventory here).
for _, t in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList } do
	pcall(function() StarterGui:SetCoreGuiEnabled(t, false) end)
end

local function start(name: string)
	local ok, err = pcall(function() require(Controllers[name]).Start() end)
	if not ok then warn("[ZG] " .. name .. " failed: " .. tostring(err)) end
end
for _, name in { "InputController", "CameraController", "MovementController", "EffectsController", "CharacterAnimator", "CombatController",
	"HUDController", "MenuController" } do
	start(name)
end

local Effects = require(Controllers.EffectsController)
local Animator = require(Controllers.CharacterAnimator)
local Movement = require(Controllers.MovementController)
local HUD = require(Controllers.HUDController)
local Items = require(Shared.ItemDefinitions)

Remotes.FX.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	local t = msg.t
	if t == "tracer" then
		Effects.Shot(msg.from, msg.ends, msg.weapon, false)
		Animator.OnShot(msg.shooter)
	elseif t == "hit" then
		State.Hit:Fire(msg.amount, msg.kill)
	elseif t == "damaged" then
		State.Damaged:Fire(msg.from, msg.amount, msg.shield)
	elseif t == "killfeed" then
		State.KillFeed:Fire(msg)
	elseif t == "notice" then
		State.Notice:Fire(msg.text, msg.color)
		if msg.sound then Effects.Play(msg.sound) end
	elseif t == "explosion" then
		Effects.Explosion(msg.pos, msg.radius)
	elseif t == "fuse" then
		Effects.Play("alarm", msg.pos)
	elseif t == "using" then
		local def = Items.List[msg.item]
		State.UseProgress:Fire("USING " .. string.upper(def and def.name or msg.item), msg.time)
	elseif t == "reload" then
		State.Reloading:Fire(msg.time)
		Effects.Play("reload")
	elseif t == "pickup" then
		Effects.Play("pickup")
		State.Notice:Fire("+ " .. msg.name, Items.RarityColor[msg.rarity or "common"])
	elseif t == "search" then
		Effects.Play("search", msg.pos)
	elseif t == "airlock" then
		Effects.Play("airlock", msg.pos)
	elseif t == "melee" then
		Effects.Play("melee", msg.pos)
	elseif t == "tether" then
		Effects.TetherBeam(msg.player, msg.point, msg.duration)
	elseif t == "tetherEnd" then
		Effects.TetherBeam(msg.player, nil)
	elseif t == "impulse" then
		Movement.ApplyImpulse(msg.v, msg.set)
	elseif t == "winner" then
		HUD.Banner(msg.name and ("WINNER: " .. string.upper(msg.name)) or "NO SURVIVORS", Color3.fromRGB(255, 170, 60), 4)
		Effects.Play("start")
	end
end)

Remotes.Match.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	if msg.t == "profile" then
		State.Profile = msg.data
		State.TemporaryProfile = msg.temporary
		for k, v in msg.data.settings or {} do State.Settings[k] = v end
		State.ProfileChanged:Fire(msg.data)
	elseif msg.t == "deployed" then
		HUD.Banner("DEPLOYED", Color3.fromRGB(110, 190, 255), 2)
		State.Notice:Fire(string.format("Deployment shield active for %ds", msg.protect), Color3.fromRGB(110, 190, 255))
	elseif msg.t == "eliminated" then
		State.Eliminated:Fire(msg)
	elseif msg.t == "results" then
		State.Results:Fire(msg)
	end
end)

Remotes.Inventory.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	if msg.t == "sync" then
		State.Inventory = msg
		State.InventoryChanged:Fire(msg)
	elseif msg.t == "clear" then
		State.Inventory = nil
		State.InventoryChanged:Fire(nil)
	end
end)

-- Own tether beam
local lastTether = nil
game:GetService("RunService").Heartbeat:Connect(function()
	if State.Tether ~= lastTether then
		lastTether = State.Tether
		Effects.TetherBeam(player, State.Tether and State.Tether.point or nil)
	end
end)
