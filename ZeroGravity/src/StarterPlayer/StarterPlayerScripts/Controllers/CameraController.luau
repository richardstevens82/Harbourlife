-- Over-the-shoulder camera with a yaw/pitch model (pitch clamped short of vertical) so the view
-- can never flip or roll unpredictably. Collision-aware, aim zoom, recoil, and spectate mode.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local State = require(script.Parent.ClientState)
local Input = require(script.Parent.InputController)

local CameraController = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local yaw, pitch = 0, 0
local recoil = 0
local fovNow = Config.Camera.DefaultFov
local lastFocus = Vector3.zero
local C = Config.Camera

function CameraController.Rotation(): CFrame
	return CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
end

function CameraController.Kick(degrees: number)
	recoil += degrees
	yaw += (math.random() - 0.5) * degrees * 0.4
end

-- Point the camera along a direction (used on spawn so players face the arena).
function CameraController.LookAlong(dir: Vector3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 0.01 then
		yaw = math.deg(math.atan2(-flat.X, -flat.Z))
	end
	pitch = math.clamp(math.deg(math.asin(math.clamp(dir.Unit.Y, -1, 1))), -C.PitchLimit, C.PitchLimit)
end

-- Ray from the camera through the crosshair; returns the world point it hits (or max range).
function CameraController.AimPoint(maxRange: number, ignore: { Instance }): Vector3
	local origin = camera.CFrame.Position
	local dir = camera.CFrame.LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(origin, dir * maxRange, params)
	return hit and hit.Position or origin + dir * maxRange
end

local function focusTarget(): BasePart?
	local target = State.Spectating
	local char = (target and target.Character) or player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function update(dt: number)
	camera.CameraType = Enum.CameraType.Scriptable
	local d = Input.LookDelta(dt)
	yaw -= d.X
	pitch = math.clamp(pitch - d.Y + recoil, -C.PitchLimit, C.PitchLimit)
	recoil = 0
	UserInputService.MouseBehavior = State.UIOpen and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = State.UIOpen

	local root = focusTarget()
	if root then lastFocus = root.Position end
	local rot = CameraController.Rotation()
	local aiming = State.Aiming and not State.Spectating
	local off = aiming and C.AimOffset or C.Offset
	if State.Spectating then off = Vector3.new(0, 4, 18) end
	local want = lastFocus + rot:VectorToWorldSpace(off)
	-- keep the camera out of walls
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end
	if State.Spectating and State.Spectating.Character then table.insert(ignore, State.Spectating.Character) end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(lastFocus, want - lastFocus, params)
	if hit then
		want = hit.Position + (lastFocus - want).Unit * 0.8
	end
	camera.CFrame = CFrame.new(want) * rot
	local targetFov = aiming and State.Settings.fov * C.AimFovScale or State.Settings.fov
	fovNow += (targetFov - fovNow) * math.min(1, dt * 12)
	camera.FieldOfView = fovNow
end

function CameraController.Start()
	RunService:BindToRenderStep("ZG_Camera", Enum.RenderPriority.Camera.Value + 1, update)
	player.CharacterAdded:Connect(function(char)
		local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root then
			task.wait(0.3) -- the server pivots the character to its spawn point right after loading
			CameraController.LookAlong(root.CFrame.LookVector)
		end
	end)
end

return CameraController
