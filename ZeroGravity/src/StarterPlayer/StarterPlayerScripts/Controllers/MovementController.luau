-- Movement for the local character: six-degree-of-freedom zero-gravity flight, and walking under
-- the artificial gravity of level pressurised decks (Shared.Gravity; see the gravity branch of step).
--
-- Model: the Humanoid is held in the Physics state (no walking/falling logic), the body is turned
-- toward the camera by an AlignOrientation, and translation is a momentum model integrated here:
--   * thrust accelerates along camera-relative axes (W/S forward, A/D strafe, Space/Ctrl up/down)
--   * momentum is kept when keys are released (tiny drag so drift eventually settles)
--   * speed is soft-capped (cruise / boost); excess speed from boosts or explosions bleeds off
--   * X stabilises (exponential brake to a full stop)
--   * tether pulls override thrust while active
-- Each frame starts from the physics-resolved velocity, so collisions with walls are respected and
-- a player sliding along a surface is never pinned to it. The character is client-owned; the
-- server checks speed and boundaries (SecurityService).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Motion = require(Shared.ZeroGMotion)
local Gravity = require(Shared.Gravity)
local State = require(script.Parent.ClientState)
local Input = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)

local Movement = {}
local player = Players.LocalPlayer
local M = Config.Movement
local hum: Humanoid?, root: BasePart?, align: AlignOrientation?
local lastBoostUse = 0
local lastRoll = -math.huge
local boosting = false
local thruster: ParticleEmitter?

local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics, Enum.HumanoidStateType.Landed, Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.StrafingNoPhysics,
}

function Movement.IsBoosting(): boolean
	return boosting
end

function Movement.Speed(): number
	return root and root.AssemblyLinearVelocity.Magnitude or 0
end

local function setup(c: Model)
	hum = c:WaitForChild("Humanoid", 5) :: Humanoid?
	root = c:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not (hum and root) then return end
	for _, s in DISABLED_STATES do
		hum:SetStateEnabled(s, false)
	end
	hum.AutoRotate = false
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	hum.StateChanged:Connect(function(_, new)
		if new ~= Enum.HumanoidStateType.Physics and new ~= Enum.HumanoidStateType.Dead and hum and hum.Health > 0 then
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end)
	-- Body orientation follows the camera
	local att = Instance.new("Attachment")
	att.Name = "ZG_Align"
	att.Parent = root
	local a = Instance.new("AlignOrientation")
	a.Mode = Enum.OrientationAlignmentMode.OneAttachment
	a.Attachment0 = att
	a.RigidityEnabled = false
	a.Responsiveness = M.TurnResponsiveness
	a.MaxTorque = math.huge
	a.MaxAngularVelocity = 20
	a.CFrame = root.CFrame.Rotation
	a.Parent = root
	align = a
	-- Local thruster plume (visual feedback for boosting)
	local pack = Instance.new("Attachment")
	pack.Name = "ZG_Thruster"
	pack.Position = Vector3.new(0, -0.5, 1.4)
	pack.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(140, 200, 255))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0.2, 1)
	pe.Lifetime = NumberRange.new(0.15, 0.3)
	pe.Speed = NumberRange.new(14, 20)
	pe.EmissionDirection = Enum.NormalId.Back
	pe.Rate = 0
	pe.Parent = pack
	thruster = pe
	State.Boost = M.BoostMax * (player:GetAttribute("BoostMaxMult") or 1)
	State.Tether = nil
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Begin reeling toward a server-approved tether point.
function Movement.StartTether(point: Vector3, duration: number)
	State.Tether = { point = point, untilT = os.clock() + duration }
end

-- Server-requested velocity change (explosion shove, melee knockback, boundary push-back).
function Movement.ApplyImpulse(v: Vector3, set: boolean?)
	if not root then return end
	if set then
		Movement.ReleaseTether()
		root.AssemblyLinearVelocity = v
	else
		root.AssemblyLinearVelocity += v
	end
end

-- Air roll: a barrel-roll dodge that throws the body sideways (camera-relative). Costs boost energy;
-- the extra speed bleeds back to cruise like any other overspeed. Returns true if it happened.
function Movement.Roll(dir: number): boolean
	if not (root and hum and root.Parent) or hum.Health <= 0 or State.UIOpen then return false end
	local now = os.clock()
	if now - lastRoll < M.RollCooldown or (State.Boost or 0) < M.RollCost then return false end
	lastRoll = now
	State.Boost -= M.RollCost
	lastBoostUse = now -- pauses regeneration like boosting does
	root.AssemblyLinearVelocity += CameraController.Rotation().RightVector * dir * M.RollImpulse
	Remotes.Combat:FireServer({ action = "roll", dir = dir })
	return true
end

function Movement.ReleaseTether()
	if State.Tether then
		State.Tether = nil
		Remotes.Equipment:FireServer({ action = "tetherRelease" })
	end
end

-- Tether pull (overrides thrust and gravity while active). Returns the new velocity.
local function tetherPull(v: Vector3, dt: number): Vector3
	local tether = State.Tether
	if not (tether and root) then return v end
	local to = tether.point - root.Position
	if os.clock() > tether.untilT or to.Magnitude < Config.Tether.ReleaseDistance or Input.Braking() then
		Movement.ReleaseTether()
		return v
	end
	return v:Lerp(to.Unit * Config.Tether.PullSpeed, math.min(1, dt * 6))
end

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude

local function step(dt: number)
	if not (root and hum and align and root.Parent) or hum.Health <= 0 then return end
	dt = math.min(dt, 0.1)
	if hum:GetState() ~= Enum.HumanoidStateType.Physics then hum:ChangeState(Enum.HumanoidStateType.Physics) end
	local rot = CameraController.Rotation()
	local speedMult = player:GetAttribute("SpeedMult") or 1
	local boostMax = M.BoostMax * (player:GetAttribute("BoostMaxMult") or 1)
	local regenMult = player:GetAttribute("BoostRegenMult") or 1
	State.BoostMax = boostMax
	local v = root.AssemblyLinearVelocity
	local move = Input.MoveVector()
	local up = Gravity.UpAt(root.Position)
	local grounded = false

	if up then
		-- ARTIFICIAL GRAVITY: walk on the deck, body upright and facing the camera's heading.
		-- W/S/A/D walk, Shift sprints, Space jumps (hold it past the top of the jump for the jetpack),
		-- Ctrl drops faster.
		local look = rot.LookVector
		local fwd = look - up * look:Dot(up)
		if fwd.Magnitude < 0.05 then fwd = rot.UpVector - up * rot.UpVector:Dot(up) end -- looking straight up or down
		fwd = fwd.Unit
		local dir = fwd:Cross(up) * move.X + fwd * move.Z
		if dir.Magnitude > 1 then dir = dir.Unit end
		floorParams.FilterDescendantsInstances = { root.Parent :: Instance }
		local floorDist = Gravity.FloorDistance(root.Position, up, Config.Gravity.FloorProbe, floorParams)
		grounded = Motion.IsGrounded(v, up, floorDist)
		local energy, jetOn, lastUse = Motion.Boost(State.Boost, Motion.WantsJet(v, up, grounded, move.Y), lastBoostUse, os.clock(), boostMax,
			regenMult, dt)
		State.Boost, boosting, lastBoostUse = energy, false, lastUse
		if thruster then thruster.Rate = jetOn and 120 or 0 end
		align.CFrame = CFrame.lookAt(Vector3.zero, fwd, up)
		if State.Tether then
			v = tetherPull(v, dt)
		else
			v, grounded = Motion.GroundStep(v, dir, up, floorDist, move.Y, Input.Boosting(), jetOn, speedMult, dt)
		end
	else
		-- ZERO-G: six-direction thrust relative to the camera; the body turns with the view.
		align.CFrame = rot
		local thrust = rot:VectorToWorldSpace(Vector3.new(move.X, move.Y, -move.Z))
		local energy, isBoosting, lastUse = Motion.Boost(State.Boost, Input.Boosting() and thrust.Magnitude > 0.1, lastBoostUse, os.clock(),
			boostMax, regenMult, dt)
		State.Boost, boosting, lastBoostUse = energy, isBoosting, lastUse
		if thruster then thruster.Rate = boosting and 120 or (thrust.Magnitude > 0.1 and 15 or 0) end
		if State.Tether then
			v = tetherPull(v, dt)
		end
		if not State.Tether then
			v = Motion.Step(v, thrust, boosting, Input.Braking(), speedMult, dt)
		end
	end
	root.AssemblyLinearVelocity = v
	State.Speed, State.Boosting, State.Gravity, State.Grounded = v.Magnitude, boosting, up, grounded
end

function Movement.Start()
	-- Default walking controls do nothing useful in zero-g; turn them off.
	task.spawn(function()
		local ok, controls = pcall(function()
			local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any) :: any
			return pm:GetControls()
		end)
		if ok and controls then controls:Disable() end
	end)
	if player.Character then task.spawn(setup, player.Character) end
	player.CharacterAdded:Connect(setup)
	RunService.PreSimulation:Connect(step)
	Remotes.Equipment.OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then return end
		if msg.t == "tether" then
			Movement.StartTether(msg.point, msg.duration)
		elseif msg.t == "tetherDenied" then
			State.Notice:Fire(msg.reason or "Tether: no anchor point there", Color3.fromRGB(255, 140, 90))
		end
	end)
end

return Movement
