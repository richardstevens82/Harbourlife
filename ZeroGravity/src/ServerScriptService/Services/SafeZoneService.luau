-- The orbital radiation storm: a shrinking SPHERE of safe space. Its schedule is computed once
-- per match (ZoneMath), state is published as attributes on ReplicatedStorage.ZoneState for the
-- client visual, countdown and tactical map. Damage outside escalates each stage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ZoneMath = require(Shared.ZoneMath)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Combat = require(script.Parent.CombatService)

local SafeZone = {}
local stateObj: Configuration
local schedule = nil
local serial = 0
local collapsing = false

local function now(): number
	return workspace:GetServerTimeNow()
end

function SafeZone.IsLastStage(): boolean
	return stateObj:GetAttribute("Stage") == #Config.Zone.Stages and stateObj:GetAttribute("Active") == true
end

-- spareLast: never let the storm eliminate the last combatant alive (multi-combatant matches).
function SafeZone.Begin(finalTarget: Vector3, spareLast: boolean?)
	serial += 1
	local my = serial
	local Z = Config.Zone
	local start = now()
	schedule = ZoneMath.BuildSchedule(Z.Stages, Vector3.zero, Z.StartRadius, finalTarget, start)
	collapsing = false
	stateObj:SetAttribute("Active", true)
	stateObj:SetAttribute("StageCount", #Z.Stages)
	local announced, warned = {}, {}
	task.spawn(function()
		local DT = 0.5
		while serial == my do
			local t = now()
			local c, r, dps, stage, phase, nextT = ZoneMath.Evaluate(schedule, t, Vector3.zero, Z.StartRadius, 1)
			local st = schedule[stage]
			stateObj:SetAttribute("Center", c)
			stateObj:SetAttribute("Radius", r)
			stateObj:SetAttribute("Stage", stage)
			stateObj:SetAttribute("Phase", phase)
			stateObj:SetAttribute("NextTime", nextT == math.huge and 0 or nextT)
			stateObj:SetAttribute("Dps", dps)
			if st and not collapsing then
				stateObj:SetAttribute("NextCenter", st.toC)
				stateObj:SetAttribute("NextRadius", st.toR)
				if not announced[stage] then
					announced[stage] = true
					Remotes.FX:FireAllClients({ t = "notice", text = string.format("Radiation storm stage %d plotted - safe zone shrinks in %ds", stage, math.floor(st.startShrink - t)),
						color = Color3.fromRGB(190, 120, 255), sound = "warn" })
				end
				if phase == "waiting" and not warned[stage] and st.startShrink - t <= Z.WarnBefore then
					warned[stage] = true
					Remotes.FX:FireAllClients({ t = "notice", text = "STORM CONTRACTING IN " .. Z.WarnBefore .. "s", color = Color3.fromRGB(255, 90, 200), sound = "alarm" })
				end
			end
			-- Weakest first, and never the last one alive: when the storm eliminates several combatants on
			-- the same tick, the healthiest survives and wins (last one standing, never "no survivors").
			local active = Roster.Active()
			local hp = {}
			for _, p in active do
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				hp[p] = hum and hum.Health or 0
			end
			table.sort(active, function(a, b) return hp[a] < hp[b] end)
			for _, p in active do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local outside = ZoneMath.DistanceOutside(c, r, root.Position)
					p:SetAttribute("InStorm", outside > 0)
					if outside > 0 and (not spareLast or #Roster.Alive() > 1) then
						Combat.ApplyDamage(p, dps * DT, nil, "zone", c)
					end
				end
			end
			task.wait(DT)
		end
	end)
end

-- Sudden death: from wherever the storm is now, shrink it to nothing over `duration` seconds. Everyone
-- ends up outside and the storm (which ignores shields) eliminates the weakest first, so the match is
-- still won by the last combatant standing.
function SafeZone.Collapse(duration: number, dps: number)
	if not schedule or collapsing then return end
	collapsing = true
	local t = now()
	local c = stateObj:GetAttribute("Center") or Vector3.zero
	local r = stateObj:GetAttribute("Radius") or Config.Zone.StartRadius
	schedule = { { index = #Config.Zone.Stages, announceAt = t, startShrink = t, endShrink = t + duration, fromC = c, fromR = r, toC = c, toR = 0, dps = dps } }
	stateObj:SetAttribute("NextCenter", c)
	stateObj:SetAttribute("NextRadius", 0)
	Remotes.FX:FireAllClients({ t = "notice", text = "STORM COLLAPSE - LAST ONE STANDING WINS", color = Color3.fromRGB(255, 90, 200), sound = "alarm" })
end

function SafeZone.IsCollapsing(): boolean
	return collapsing
end

function SafeZone.Stop()
	serial += 1
	collapsing = false
	schedule = nil
	stateObj:SetAttribute("Active", false)
end

function SafeZone.Start()
	stateObj = Instance.new("Configuration")
	stateObj.Name = "ZoneState"
	stateObj:SetAttribute("Active", false)
	stateObj:SetAttribute("Center", Vector3.zero)
	stateObj:SetAttribute("Radius", Config.Zone.StartRadius)
	stateObj.Parent = ReplicatedStorage
end

return SafeZone
