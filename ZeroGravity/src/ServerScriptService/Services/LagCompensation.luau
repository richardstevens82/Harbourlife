-- Lag compensation for hitscan weapons ("favour the shooter", bounded).
-- A client aims at where its screen shows a target. For a server-simulated bot (or another player
-- relayed through the server) that is where the server had the target about one round trip plus
-- Roblox's interpolation delay ago, so against a strafing target a perfectly aimed shot misses the
-- target's *current* body by several studs. The server keeps a short history of every active
-- combatant's root CFrame; CombatService asks Trace() about shots that missed every current body,
-- and Trace() tests the ray against each body (a capsule) where the shooter saw it. Rewind is capped
-- (Config.LagCompensation.MaxRewind), and walls are still respected because the caller only passes the
-- distance to the first solid hit.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Roster = require(script.Parent.Roster)

local LagComp = {}
local C = Config.LagCompensation
local KEEP = 1.0 -- seconds of history per combatant
local BODY_LOW, BODY_HIGH = Vector3.new(0, -2.2, 0), Vector3.new(0, 1.6, 0) -- capsule axis in root space (R15: feet .. head)
local HEAD_T = 0.84 -- fraction along the axis above which a hit counts as the head
local MAX_TRAVEL = Config.Movement.BoostMaxSpeed * 1.5 + 10 -- studs/s; anything faster is a teleport

type Snapshot = { t: number, cf: CFrame }
local history: { [any]: { Snapshot } } = {}

local function record()
	local now = os.clock()
	local live = {}
	for _, c in Roster.Active() do
		local root = c.Character and c.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			live[c] = true
			local h = history[c]
			if not h then
				h = {}
				history[c] = h
			end
			local last = h[#h]
			if last and (root.Position - last.cf.Position).Magnitude > MAX_TRAVEL * (now - last.t) + 5 then
				table.clear(h) -- teleported (deployment, respawn): the old positions are not where anyone saw it
			end
			table.insert(h, { t = now, cf = root.CFrame })
			while h[1] and now - h[1].t > KEEP do table.remove(h, 1) end
		end
	end
	for c in history do
		if not live[c] then history[c] = nil end
	end
end

-- Root CFrame of combatant c at time t (interpolated between snapshots), or nil if t is outside the
-- recorded history.
function LagComp.At(c, t: number): CFrame?
	local h = history[c]
	if not h or #h == 0 or t < h[1].t then return nil end
	if t >= h[#h].t then return h[#h].cf end
	for i = #h - 1, 1, -1 do
		local a = h[i]
		if a.t <= t then
			local b = h[i + 1]
			return a.cf:Lerp(b.cf, (t - a.t) / math.max(b.t - a.t, 1e-6))
		end
	end
	return nil
end

-- How far behind the server's present the shooter's view of other combatants is, in seconds.
function LagComp.ViewDelay(shooter): number
	if not C.Enabled or Roster.IsBot(shooter) then return 0 end -- bots aim at the server's present
	local ok, ping = pcall(function() return shooter:GetNetworkPing() end)
	local rtt = if ok and type(ping) == "number" then ping else 0.1
	return math.clamp(rtt + C.InterpDelay, 0, C.MaxRewind)
end

-- Closest points between segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9).
-- Returns the parameters s (on the first) and t (on the second), both in [0, 1].
local function closestParams(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): (number, number)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	if a <= 1e-9 and e <= 1e-9 then return 0, 0 end
	if a <= 1e-9 then return 0, math.clamp(f / e, 0, 1) end
	local c = d1:Dot(r)
	if e <= 1e-9 then return math.clamp(-c / a, 0, 1), 0 end
	local b = d1:Dot(d2)
	local denom = a * e - b * b
	local s = if denom > 1e-9 then math.clamp((b * f - c * e) / denom, 0, 1) else 0
	local t = (b * s + f) / e
	if t < 0 then
		return math.clamp(-c / a, 0, 1), 0
	elseif t > 1 then
		return math.clamp((b - c) / a, 0, 1), 1
	end
	return s, t
end

-- Distance along the ray (origin, unit dir, length len) at which it enters the body capsule of a
-- character whose root is at cf, plus whether the hit is on the head. nil if it misses.
local function rayBody(origin: Vector3, dir: Vector3, len: number, cf: CFrame): (number?, boolean)
	local a, b = cf * BODY_LOW, cf * BODY_HIGH
	local stop = origin + dir * len
	local s, t = closestParams(origin, stop, a, b)
	local onRay = origin + dir * (len * s)
	local gap = (onRay - (a + (b - a) * t)).Magnitude
	local r = C.HitRadius
	if gap > r then return nil, false end
	return math.max(0, len * s - math.sqrt(r * r - gap * gap)), t >= HEAD_T
end

-- Tests a shot that missed every current body against where the shooter saw each other combatant.
-- maxDist is the distance to the first solid hit (or the weapon's range). Returns the nearest
-- (victim, distance, headshot) or nil.
function LagComp.Trace(shooter, origin: Vector3, dir: Vector3, maxDist: number): (any, number, boolean)
	local delay = LagComp.ViewDelay(shooter)
	if delay <= 0 then return nil, 0, false end
	local now = os.clock()
	local best, bestDist, bestHead = nil, math.huge, false
	for c in history do
		if c ~= shooter and Roster.IsActive(c) then
			local root = c.Character and c.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			-- cheap reject: too far from the ray to be hit at any rewind
			local rel = root and root.Position - origin
			local along = rel and rel:Dot(dir) or -1
			if rel and along > -10 and along < maxDist + 10 and (rel - dir * along).Magnitude < MAX_TRAVEL * (delay + C.Window) + 6 then
				for k = -1, 1, 0.5 do
					local cf = LagComp.At(c, now - math.clamp(delay + k * C.Window, 0, C.MaxRewind + C.Window))
					if cf then
						local d, head = rayBody(origin, dir, maxDist, cf)
						if d and d < bestDist then best, bestDist, bestHead = c, d, head end
					end
				end
			end
		end
	end
	return best, bestDist, bestHead
end

function LagComp.Start()
	RunService.Heartbeat:Connect(record)
end

return LagComp
