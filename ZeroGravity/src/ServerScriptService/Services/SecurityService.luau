-- Request validation helpers and the server's movement sanity checks.
--   * RateLimit: token buckets per player per channel (drops floods of remote requests)
--   * Arg checks for remote payloads
--   * Movement: speed ceiling and arena hard boundary. Characters are client-owned physics (needed
--     for responsive zero-g movement), so the server verifies results instead of trusting them.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Security = {}
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local strikes: { [Player]: number } = {}
local allowance: { [Player]: number } = {} -- time until which extra speed is legitimate (tether)

-- Allows `rate` requests/second with bursts up to `burst`.
function Security.RateLimit(player: Player, channel: string, rate: number, burst: number): boolean
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[channel]
	local now = os.clock()
	if not b then
		b = { tokens = burst, last = now }
		pb[channel] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

function Security.IsVector(v): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

function Security.IsString(v, maxLen: number?): boolean
	return type(v) == "string" and #v <= (maxLen or 64)
end

function Security.Flag(player: Player, reason: string)
	strikes[player] = (strikes[player] or 0) + 1
	warn(string.format("[ZG][Security] %s: %s (strike %d)", player.Name, reason, strikes[player]))
end

-- Grants a short window of extra permitted speed (tether pulls, explosions).
function Security.AllowBurst(player: Player, seconds: number)
	allowance[player] = math.max(allowance[player] or 0, os.clock() + seconds)
end

function Security.Start(isActive: (Player) -> boolean, damage: (Player, number, string) -> ())
	local M = Config.Movement
	local maxSpeed = math.max(M.BoostMaxSpeed, Config.Tether.PullSpeed) * 1.3 * M.ServerSpeedTolerance
	local lastPos: { [Player]: Vector3 } = {}
	task.spawn(function()
		while true do
			task.wait(M.ServerCheckInterval)
			for _, p in Players:GetPlayers() do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local pos = root.Position
					-- Speed check from actual displacement (covers velocity spoofing and teleports)
					local prev = lastPos[p]
					lastPos[p] = pos
					if prev and (allowance[p] or 0) < os.clock() then
						local speed = (pos - prev).Magnitude / M.ServerCheckInterval
						if speed > maxSpeed then
							Security.Flag(p, string.format("moved %.0f studs/s", speed))
							root.CFrame = CFrame.new(prev) * root.CFrame.Rotation
							Remotes.FX:FireClient(p, { t = "impulse", v = Vector3.zero, set = true })
							lastPos[p] = prev
						end
					end
					-- Arena hard boundary: push back inward and hurt
					if isActive(p) and pos.Magnitude > Config.Arena.HardRadius then
						Remotes.FX:FireClient(p, { t = "impulse", v = -pos.Unit * 40, set = true })
						Security.AllowBurst(p, 1)
						damage(p, Config.Arena.OutOfBoundsDps * M.ServerCheckInterval, "boundary")
					end
				else
					lastPos[p] = nil
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p], strikes[p], allowance[p], lastPos[p] = nil, nil, nil, nil
	end)
end

-- Call after a server-side teleport so the jump isn't flagged.
function Security.Teleported(player: Player)
	Security.AllowBurst(player, 1.5)
end

return Security
