-- Suit oxygen. Drains outside pressurised volumes, refills inside them, refill stations top up
-- instantly (with per-player cooldown). At zero the suit warns for GraceSeconds before hypoxia
-- damage begins, so oxygen is a pressure to act, not a random death.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Combat = require(script.Parent.CombatService)

local Oxygen = {}
local O = Config.Oxygen
local emptySince: { [Player]: number } = {}
local stationUse: { [Player]: { [Instance]: number } } = {}
local stationHandlers: { [BasePart]: (any) -> () } = {}

local function inside(part: BasePart, pos: Vector3): boolean
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

function Oxygen.IsPressurized(pos: Vector3): boolean
	for _, z in CollectionService:GetTagged("Pressurized") do
		if z:IsA("BasePart") and not z:GetAttribute("Breached") and inside(z, pos) then return true end
	end
	return false
end

-- Marks every pressurised volume with this ZoneId as breached (or restores it).
function Oxygen.SetBreached(zoneId: string, breached: boolean)
	for _, z in CollectionService:GetTagged("Pressurized") do
		if z:GetAttribute("ZoneId") == zoneId then z:SetAttribute("Breached", breached or nil) end
	end
end

function Oxygen.Reset(player: Player)
	player:SetAttribute("O2", O.Max)
	player:SetAttribute("Hypoxia", false)
	emptySince[player] = nil
	stationUse[player] = nil
end

local function buildStation(marker: BasePart)
	local unit = Instance.new("Part")
	unit.Name = "OxygenStation"
	unit.Size = Vector3.new(3, 5, 1.6)
	unit.CFrame = marker.CFrame
	unit.Anchored = true
	unit.Color = Color3.fromRGB(60, 64, 72)
	unit.Material = Enum.Material.Metal
	local tank = Instance.new("Part")
	tank.Name = "Tank"
	tank.Shape = Enum.PartType.Cylinder
	tank.Size = Vector3.new(3.6, 1.4, 1.4)
	tank.CFrame = marker.CFrame * CFrame.new(0, 0, -0.9) * CFrame.Angles(0, 0, math.rad(90))
	tank.Anchored, tank.CanCollide = true, false
	tank.Material = Enum.Material.Neon
	tank.Color = Color3.fromRGB(80, 230, 150)
	tank.Parent = unit
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(80, 230, 150), 14, 1
	light.Parent = tank
	unit.Parent = marker.Parent
	CollectionService:AddTag(unit, "OxygenUnit")
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Refill Oxygen"
	pr.ObjectText = "O2 Station"
	pr.KeyboardKeyCode = Enum.KeyCode.F
	pr.HoldDuration = 1
	pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false
	pr.Parent = unit
	local function use(player)
		if not Roster.IsActive(player) then return end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - unit.Position).Magnitude > 16 then return end
		local uses = stationUse[player] or {}
		stationUse[player] = uses
		local last = uses[unit]
		if last and os.clock() - last < O.StationCooldown then
			Remotes.FX:FireClient(player, { t = "notice", text = string.format("O2 station recharging (%ds)", math.ceil(O.StationCooldown - (os.clock() - last))) })
			return
		end
		uses[unit] = os.clock()
		player:SetAttribute("O2", O.Max)
		emptySince[player] = nil
		Remotes.FX:FireClient(player, { t = "notice", text = "Oxygen refilled", color = Color3.fromRGB(80, 230, 150), sound = "o2" })
	end
	stationHandlers[unit] = use
	pr.Triggered:Connect(use)
end

-- Bot entry point (same checks as the prompt).
function Oxygen.UseStation(c, unit: BasePart)
	local h = stationHandlers[unit]
	if h then h(c) end
end

function Oxygen.Stations(): { BasePart }
	local out = {}
	for unit in stationHandlers do table.insert(out, unit) end
	return out
end

function Oxygen.Start()
	for _, m in CollectionService:GetTagged("OxygenStation") do
		if m:IsA("BasePart") then buildStation(m) end
	end
	Players.PlayerRemoving:Connect(function(p)
		emptySince[p], stationUse[p] = nil, nil
	end)
	local DT = 0.25
	task.spawn(function()
		while true do
			task.wait(DT)
			local now = os.clock()
			for _, p in Roster.Active() do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local o2 = p:GetAttribute("O2") or O.Max
					local pressurized = Oxygen.IsPressurized(root.Position)
					if pressurized then
						o2 = math.min(O.Max, o2 + O.RefillPerSecond * DT)
					else
						o2 = math.max(0, o2 - O.DrainPerSecond * DT * (p:GetAttribute("O2Efficiency") or 1))
					end
					p:SetAttribute("O2", o2)
					if p:GetAttribute("Pressurized") ~= pressurized then p:SetAttribute("Pressurized", pressurized) end
					if o2 <= 0 then
						local since = emptySince[p]
						if not since then
							emptySince[p] = now
							Remotes.FX:FireClient(p, { t = "notice", text = "OXYGEN DEPLETED - get inside or use a canister!", color = Color3.fromRGB(255, 80, 60), sound = "alarm" })
						elseif now - since > O.GraceSeconds then
							p:SetAttribute("Hypoxia", true)
							Combat.ApplyDamage(p, O.HypoxiaDps * DT, nil, "hypoxia")
						end
					else
						emptySince[p] = nil
						if p:GetAttribute("Hypoxia") then p:SetAttribute("Hypoxia", false) end
					end
				end
			end
		end
	end)
end

return Oxygen
