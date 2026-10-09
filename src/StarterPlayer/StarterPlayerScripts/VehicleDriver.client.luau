-- Drives the vehicle the local player is seated in. The server built the constraints
-- (Drive / Turn); the driver's client owns the physics so steering feels instant.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

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
