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

-- Standing on a floor under artificial gravity? (floorDist = distance from the root down to the floor)
function Motion.IsGrounded(v: Vector3, up: Vector3, floorDist: number?): boolean
	return floorDist ~= nil and floorDist <= Config.Gravity.HipHeight + 0.5 and v:Dot(up) <= 1
end

-- One step of walking under artificial gravity (Config.Gravity). move: desired direction on the
-- floor plane (length 0..1); vertical: +1 Space (jump, then jetpack while held), -1 Ctrl (fast-fall),
-- 0 none; jet: whether the jetpack may fire this frame (energy available, decided by the caller).
-- Returns (velocity, grounded, jetting).
--   * on the floor the legs hold standing height with a spring (no sinking, no bouncing)
--   * walk/sprint speed is reached quickly on the floor; in the air you only steer gently, so
--     momentum carried in from zero-g flight is kept until you land
function Motion.GroundStep(v: Vector3, move: Vector3, up: Vector3, floorDist: number?, vertical: number, sprint: boolean, jet: boolean,
	speedMult: number, dt: number): (Vector3, boolean, boolean)
	local G = Config.Gravity
	local grounded = Motion.IsGrounded(v, up, floorDist)
	local vUp = v:Dot(up)
	local flat = v - up * vUp
	local want = move * (sprint and G.SprintSpeed or G.WalkSpeed) * speedMult
	local diff = want - flat
	local stepMax = (grounded and G.GroundAccel or G.AirAccel) * dt
	if diff.Magnitude > stepMax then diff = diff.Unit * stepMax end
	flat += diff
	local jetting = false
	if grounded then
		if vertical > 0.5 then
			vUp = G.JumpVelocity
		else
			vUp = (G.HipHeight - (floorDist :: number)) * G.Stiffness
		end
	else
		vUp -= G.Strength * dt
		if vertical > 0.5 and jet then
			jetting = true
			vUp = math.min(vUp + G.JetAccel * dt, G.JetMaxRise)
		elseif vertical < -0.5 then
			vUp -= G.Strength * dt
		end
		vUp = math.max(vUp, -G.MaxFall)
	end
	return flat + up * vUp, grounded, jetting
end

-- Whether a held Space should fire the jetpack: airborne, and past the top of a jump (so a tap is a
-- plain hop and holding it keeps climbing).
function Motion.WantsJet(v: Vector3, up: Vector3, grounded: boolean, vertical: number): boolean
	return not grounded and vertical > 0.5 and v:Dot(up) < Config.Gravity.JumpVelocity * 0.3
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
