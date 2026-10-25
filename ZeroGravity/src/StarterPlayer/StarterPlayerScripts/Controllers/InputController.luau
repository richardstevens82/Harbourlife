-- Turns keyboard / gamepad state into abstract movement and look input, so the movement and camera
-- code never reads devices directly (keeps mobile/controller support a matter of mapping here).
local UserInputService = game:GetService("UserInputService")
local State = require(script.Parent.ClientState)

local Input = {}
local pad = { move = Vector2.zero, look = Vector2.zero, up = false, down = false, boost = false, brake = false }
-- Touch input (TouchController writes these): move = thumbstick (X right, Y forward), look = pixels
-- dragged since the last frame.
local touch = { move = Vector2.zero, look = Vector2.zero, up = false, down = false, boost = false, brake = false }
Input.Touch = touch

local function held(action: string): boolean
	local key = State.Bindings[action]
	return key ~= nil and UserInputService:IsKeyDown(key)
end
Input.Held = held

-- Movement intent in camera space: X = right, Y = up, Z = forward (each -1..1).
function Input.MoveVector(): Vector3
	if State.UIOpen then return Vector3.zero end
	local x = (held("Right") and 1 or 0) - (held("Left") and 1 or 0) + pad.move.X + touch.move.X
	local y = (held("Up") and 1 or 0) - (held("Down") and 1 or 0) + (pad.up and 1 or 0) - (pad.down and 1 or 0) + (touch.up and 1 or 0)
		- (touch.down and 1 or 0)
	local z = (held("Forward") and 1 or 0) - (held("Back") and 1 or 0) + pad.move.Y + touch.move.Y
	local v = Vector3.new(math.clamp(x, -1, 1), math.clamp(y, -1, 1), math.clamp(z, -1, 1))
	return v.Magnitude > 1 and v.Unit or v
end

function Input.Boosting(): boolean
	return not State.UIOpen and (held("Boost") or pad.boost or touch.boost)
end

function Input.Braking(): boolean
	return not State.UIOpen and (held("Brake") or pad.brake or touch.brake)
end

-- Look delta in degrees for this frame.
function Input.LookDelta(dt: number): Vector2
	if State.UIOpen then return Vector2.zero end
	local sens = State.Settings.sensitivity
	local m = UserInputService:GetMouseDelta() * 0.22 * sens
	local g = Vector2.new(pad.look.X, -pad.look.Y) * 220 * dt * sens
	local t = touch.look * 0.3 * sens -- degrees per dragged pixel
	touch.look = Vector2.zero
	local d = m + g + t
	if State.Aiming then d *= 0.6 end
	if State.Settings.invertY then d = Vector2.new(d.X, -d.Y) end
	return d
end

function Input.Start()
	local function dead(v: Vector2): Vector2
		return v.Magnitude < 0.15 and Vector2.zero or v
	end
	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			pad.move = dead(Vector2.new(io.Position.X, io.Position.Y))
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			pad.look = dead(Vector2.new(io.Position.X, io.Position.Y))
		end
	end)
	local map = { [Enum.KeyCode.ButtonA] = "up", [Enum.KeyCode.ButtonB] = "down", [Enum.KeyCode.ButtonL3] = "boost", [Enum.KeyCode.ButtonX] = "brake" }
	UserInputService.InputBegan:Connect(function(io)
		local k = map[io.KeyCode]
		if k then pad[k] = true end
	end)
	UserInputService.InputEnded:Connect(function(io)
		local k = map[io.KeyCode]
		if k then pad[k] = false end
	end)
end

return Input
