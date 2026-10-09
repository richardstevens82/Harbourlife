-- Drives the vehicle the local player is seated in. The server built the constraints
-- (Drive / Turn); the driver's client owns the physics so steering feels instant.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local player = Players.LocalPlayer

-- Excavator controls (hold): Q/E swing, R/F boom, T/G stick, Y/H bucket. Tap: X dig, Z dump.
local JOINTS = {
	{ name = "SwingHinge", up = Enum.KeyCode.Q, down = Enum.KeyCode.E, rate = 50 },
	{ name = "BoomHinge", up = Enum.KeyCode.R, down = Enum.KeyCode.F, rate = 30, min = -40, max = 30 },
	{ name = "StickHinge", up = Enum.KeyCode.T, down = Enum.KeyCode.G, rate = 35, min = -60, max = 50 },
	{ name = "BucketHinge", up = Enum.KeyCode.Y, down = Enum.KeyCode.H, rate = 50, min = -70, max = 60 },
}
local function driveArm(seat, dt)
	if UIS:GetFocusedTextBox() then return end
	local model = seat.Parent
	for _, j in JOINTS do
		local h = model:FindFirstChild(j.name, true)
		if h then
			local dir = (UIS:IsKeyDown(j.up) and 1 or 0) - (UIS:IsKeyDown(j.down) and 1 or 0)
			if dir ~= 0 then
				local t = h.TargetAngle + dir * j.rate * dt
				if j.min then t = math.clamp(t, j.min, j.max) end
				h.TargetAngle = t
			end
		end
	end
end
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not (seat and seat:GetAttribute("Construction")) then return end
	if input.KeyCode == Enum.KeyCode.X then Remotes.ExcavatorAction:FireServer("dig")
	elseif input.KeyCode == Enum.KeyCode.Z then Remotes.ExcavatorAction:FireServer("dump") end
end)

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not (seat and seat:IsA("VehicleSeat") and seat:GetAttribute("VehicleId")) then return end
	if seat:GetAttribute("OwnerUserId") ~= player.UserId then return end
	local body = seat.Parent and seat.Parent.PrimaryPart
	local drive = body and body:FindFirstChild("Drive")
	local turn = body and body:FindFirstChild("Turn")
	if not (drive and turn) then return end

	if seat:GetAttribute("Construction") then driveArm(seat, dt) end
	local maxSpeed = seat:GetAttribute("MaxSpeed") or 0
	local condition = seat:GetAttribute("Condition") or 100
	if seat:GetAttribute("Disabled") then maxSpeed = 0 end
	if condition < 25 then maxSpeed *= 0.6 end -- badly worn vehicles are slower

	local look = body.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zero
	local vel = Vector3.new(body.AssemblyLinearVelocity.X, 0, body.AssemblyLinearVelocity.Z)
	local forwardSpeed = vel:Dot(flat)

	local target = seat.ThrottleFloat * maxSpeed
	drive.PlaneVelocity = Vector2.new(flat.X * target, flat.Z * target)

	local grip = math.clamp(math.abs(forwardSpeed) / 8, 0, 1) * (forwardSpeed >= 0 and 1 or -1)
	turn.AngularVelocity = Vector3.new(0, -seat.SteerFloat * (seat:GetAttribute("TurnRate") or 1.5) * grip, 0)
end)
