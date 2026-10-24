-- Six-degree-of-freedom zero-gravity movement for the local character.
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
local State = require(script.Parent.ClientState)
local Input = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)

local Movement = {}
local player = Players.LocalPlayer
local M = Config.Movement
local hum: Humanoid?, root: BasePart?, align: AlignOrientation?
local lastBoostUse = 0
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

function Movement.ReleaseTether()
	if State.Tether then
		State.Tether = nil
		Remotes.Equipment:FireServer({ action = "tetherRelease" })
	end
end

local function step(dt: number)
	if not (root and hum and align and root.Parent) or hum.Health <= 0 then return end
	dt = math.min(dt, 0.1)
	if hum:GetState() ~= Enum.HumanoidStateType.Physics then hum:ChangeState(Enum.HumanoidStateType.Physics) end
	local rot = CameraController.Rotation()
	align.CFrame = rot

	local speedMult = player:GetAttribute("SpeedMult") or 1
	local boostMax = M.BoostMax * (player:GetAttribute("BoostMaxMult") or 1)
	State.BoostMax = boostMax
	local v = root.AssemblyLinearVelocity
	local move = Input.MoveVector()
	local thrust = rot:VectorToWorldSpace(Vector3.new(move.X, move.Y, -move.Z))

	-- Boost energy
	boosting = Input.Boosting() and thrust.Magnitude > 0.1 and State.Boost > 1
	if boosting then
		State.Boost = math.max(0, State.Boost - M.BoostDrain * dt)
		lastBoostUse = os.clock()
	elseif os.clock() - lastBoostUse > M.BoostRegenDelay then
		State.Boost = math.min(boostMax, State.Boost + M.BoostRegen * (player:GetAttribute("BoostRegenMult") or 1) * dt)
	end
	if thruster then thruster.Rate = boosting and 120 or (thrust.Magnitude > 0.1 and 15 or 0) end

	local tether = State.Tether
	if tether then
		local to = tether.point - root.Position
		if os.clock() > tether.untilT or to.Magnitude < Config.Tether.ReleaseDistance or Input.Braking() then
			Movement.ReleaseTether()
		else
			local want = to.Unit * Config.Tether.PullSpeed
			v = v:Lerp(want, math.min(1, dt * 6))
		end
	end
	if not State.Tether then
		local accel = (boosting and M.BoostAccel or M.Accel) * speedMult
		local prevSpeed = v.Magnitude
		if thrust.Magnitude > 0.05 then
			v += thrust * accel * dt
		else
			v *= math.exp(-M.Drag * dt)
		end
		-- Speed cap: thrust can never push past the current cap. Speed already above it (boost just
		-- ended, explosion shove) bleeds off at 90 studs/s instead of snapping, and thrust can still steer.
		local cap = (boosting and M.BoostMaxSpeed or M.MaxSpeed) * speedMult
		local limit = math.max(cap, prevSpeed - 90 * dt)
		if v.Magnitude > limit then
			v = v.Unit * limit
		end
		if Input.Braking() then
			v *= math.exp(-M.BrakeRate * dt)
			if v.Magnitude < M.StopThreshold then v = Vector3.zero end
		end
	end
	root.AssemblyLinearVelocity = v
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
