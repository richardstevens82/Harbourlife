-- Touch controls for phones and tablets. Built only on a touchscreen without a keyboard (Studio's
-- device emulator counts), so desktop and console players never see them.
--   Left half of the screen: a floating thumbstick that appears where the thumb lands (thrust).
--   Right half: drag to look.
--   Buttons: FIRE (hold), AIM (toggle), RELOAD, HEAL; BOOST / UP / DOWN / BRAKE (hold);
--            ROLL ◄ / ►, UTIL, SWAP (next weapon); MENU, MAP, BAG along the top.
-- Every button drives the same Input / CombatController / HUD / Menu paths as the keyboard, so the
-- server sees exactly the same requests.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local State = require(script.Parent.ClientState)
local Input = require(script.Parent.InputController)
local Combat = require(script.Parent.CombatController)
local HUD = require(script.Parent.HUDController)
local Menu = require(script.Parent.MenuController)
local UI = require(script.Parent.UIKit)

local Touch = {}
local player = Players.LocalPlayer
local C = UI.Colors
local new = UI.new
local STICK_R = 60 -- thumbstick travel in pixels
local gui: ScreenGui
local actions: Frame
local stickTouch, lookTouch = nil, nil
local stickOrigin, lookLast = Vector2.zero, Vector2.zero
local base: Frame, knob: Frame

function Touch.IsTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function pos2(io): Vector2
	return Vector2.new(io.Position.X, io.Position.Y)
end

-- Round translucent button anchored to the bottom-right (offsets from that corner) or top-right.
local function button(parent: Instance, text: string, right: number, y: number, size: number, top: boolean?)
	local b = new("TextButton", {
		Name = text, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), AutoButtonColor = false,
		Position = if top then UDim2.new(1, -right, 0, y) else UDim2.new(1, -right, 1, -y),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.35, Text = text, TextColor3 = C.Text, Font = UI.Fonts.Bold,
		TextSize = math.max(11, math.floor(size * 0.2)),
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	new("UIStroke", { Color = C.Accent, Transparency = 0.4, Thickness = 1.5 }, b)
	return b
end

-- Held while the finger is down (released if it slides off).
local function hold(b: TextButton, set: (boolean) -> ())
	local function press(on: boolean)
		set(on)
		b.BackgroundTransparency = if on then 0.05 else 0.35
	end
	b.MouseButton1Down:Connect(function() press(true) end)
	b.MouseButton1Up:Connect(function() press(false) end)
	b.MouseLeave:Connect(function() press(false) end)
end

local function tap(b: TextButton, fn: () -> ())
	b.MouseButton1Down:Connect(fn)
end

local function build()
	gui = new("ScreenGui", { Name = "ZG_Touch", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5 })
	-- thumbstick (hidden until a thumb lands on the left half)
	base = new("Frame", { Name = "StickBase", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(STICK_R * 2, STICK_R * 2),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.5, Visible = false }, gui)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, base)
	new("UIStroke", { Color = C.Accent, Transparency = 0.5, Thickness = 1.5 }, base)
	knob = new("Frame", { Name = "StickKnob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(48, 48), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.Accent, BackgroundTransparency = 0.25 }, base)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)

	actions = new("Frame", { Name = "Actions", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local T = Input.Touch
	hold(button(actions, "FIRE", 90, 130, 116), Combat.SetTrigger)
	local aim = button(actions, "AIM", 215, 90, 70)
	tap(aim, function()
		Combat.SetAiming(not State.Aiming)
		aim.BackgroundTransparency = if State.Aiming then 0.05 else 0.35
	end)
	tap(button(actions, "RELOAD", 222, 172, 58), Combat.Reload)
	tap(button(actions, "HEAL", 290, 82, 52), function() Combat.UseConsumable("heal") end)
	-- movement column (right edge) and action column next to it
	hold(button(actions, "BOOST", 46, 250, 60), function(on) T.boost = on end)
	hold(button(actions, "UP", 46, 318, 56), function(on) T.up = on end)
	hold(button(actions, "DOWN", 46, 384, 56), function(on) T.down = on end)
	hold(button(actions, "BRAKE", 46, 450, 56), function(on) T.brake = on end)
	tap(button(actions, "ROLL ►", 116, 250, 58), function() Combat.Roll(1) end)
	tap(button(actions, "◄ ROLL", 116, 318, 58), function() Combat.Roll(-1) end)
	tap(button(actions, "UTIL", 116, 384, 56), Combat.UseUtility)
	tap(button(actions, "SWAP", 116, 450, 56), Combat.CycleWeapon)
	-- top row
	tap(button(gui, "MENU", 40, 200, 46, true), Menu.Toggle)
	tap(button(gui, "MAP", 92, 200, 46, true), HUD.ToggleMap)
	tap(button(gui, "BAG", 144, 200, 46, true), function() HUD.ToggleInventory() end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function releaseStick()
	stickTouch = nil
	Input.Touch.move = Vector2.zero
	base.Visible = false
end

function Touch.Start()
	if not Touch.IsTouchDevice() then return end
	build()
	-- the weapon panel would sit under the FIRE button: move it to the top right
	local hudGui = player:WaitForChild("PlayerGui"):FindFirstChild("ZG_HUD")
	local weaponPanel = hudGui and hudGui:FindFirstChild("Weapon") :: GuiObject?
	if weaponPanel then
		weaponPanel.AnchorPoint = Vector2.new(1, 0)
		weaponPanel.Position = UDim2.new(1, -16, 0, 236)
	end
	UserInputService.TouchStarted:Connect(function(io, processed)
		if processed or State.UIOpen then return end -- a button or menu took it
		local p = pos2(io)
		local cam = workspace.CurrentCamera
		local width = cam and cam.ViewportSize.X or 1000
		if p.X < width * 0.42 then
			if not stickTouch then
				stickTouch, stickOrigin = io, p
				base.Position = UDim2.fromOffset(p.X, p.Y)
				knob.Position = UDim2.fromScale(0.5, 0.5)
				base.Visible = true
			end
		elseif not lookTouch then
			lookTouch, lookLast = io, p
		end
	end)
	UserInputService.TouchMoved:Connect(function(io)
		local p = pos2(io)
		if io == stickTouch then
			local d = p - stickOrigin
			if d.Magnitude > STICK_R then d = d.Unit * STICK_R end
			knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
			Input.Touch.move = Vector2.new(d.X / STICK_R, -d.Y / STICK_R) -- screen up = thrust forward
		elseif io == lookTouch then
			Input.Touch.look += p - lookLast
			lookLast = p
		end
	end)
	UserInputService.TouchEnded:Connect(function(io)
		if io == stickTouch then releaseStick() end
		if io == lookTouch then lookTouch = nil end
	end)
	-- action buttons hide while a menu or the inventory is open (the top row stays)
	State.UIChanged:Connect(function(open)
		actions.Visible = not open
		if open then
			releaseStick()
			lookTouch = nil
			Combat.SetTrigger(false)
		end
	end)
end

return Touch
