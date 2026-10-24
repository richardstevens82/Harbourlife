-- Zero-gravity translation model shared by player characters (MovementController, client) and
-- bots (BotService, server), so both obey exactly the same acceleration, caps and braking.
local Config = require(script.Parent.Config)

local Motion = {}
local M = Config.Movement

-- One integration step. v: current velocity; thrust: world-space thrust direction (length 0..1).
-- Returns the new velocity.
--   * thrust accelerates; no thrust = tiny drag (momentum is kept)
--   * thrust can never push past the current cap; speed already above it (boost just ended,
--     explosion shove) bleeds off at 90 studs/s instead of snapping, and thrust can still steer
--   * braking decays velocity exponentially to a full stop
function Motion.Step(v: Vector3, thrust: Vector3, boosting: boolean, braking: boolean, speedMult: number, dt: number): Vector3
	local accel = (boosting and M.BoostAccel or M.Accel) * speedMult
	local prevSpeed = v.Magnitude
	if thrust.Magnitude > 0.05 then
		v += thrust * accel * dt
	else
		v *= math.exp(-M.Drag * dt)
	end
	local cap = (boosting and M.BoostMaxSpeed or M.MaxSpeed) * speedMult
	local limit = math.max(cap, prevSpeed - 90 * dt)
	if v.Magnitude > limit then
		v = v.Unit * limit
	end
	if braking then
		v *= math.exp(-M.BrakeRate * dt)
		if v.Magnitude < M.StopThreshold then v = Vector3.zero end
	end
	return v
end

-- Boost energy bookkeeping. Returns (energy, boostingThisFrame, lastUse).
function Motion.Boost(energy: number, wantBoost: boolean, lastUse: number, now: number, maxEnergy: number, regenMult: number, dt: number)
	local boosting = wantBoost and energy > 1
	if boosting then
		return math.max(0, energy - M.BoostDrain * dt), true, now
	elseif now - lastUse > M.BoostRegenDelay then
		return math.min(maxEnergy, energy + M.BoostRegen * regenMult * dt), false, lastUse
	end
	return energy, false, lastUse
end

return Motion
