-- Client-side shared state and tiny signal helper, used by every controller.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local State = {}

-- Minimal signal
local function signal()
	local s = { _handlers = {} }
	function s:Connect(fn)
		table.insert(self._handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(self._handlers, fn)
				if i then table.remove(self._handlers, i) end
			end,
		}
	end
	function s:Fire(...)
		for _, fn in table.clone(self._handlers) do
			task.spawn(fn, ...)
		end
	end
	return s
end
State.Signal = signal

State.Settings = { sensitivity = 1, invertY = false, fov = Config.Camera.DefaultFov }

-- Rebindable keyboard controls (settings menu). Gamepad mapping lives in InputController.
State.Bindings = {
	Forward = Enum.KeyCode.W, Back = Enum.KeyCode.S, Left = Enum.KeyCode.A, Right = Enum.KeyCode.D,
	Up = Enum.KeyCode.Space, Down = Enum.KeyCode.LeftControl, Boost = Enum.KeyCode.LeftShift, Brake = Enum.KeyCode.X,
	Reload = Enum.KeyCode.R, Utility = Enum.KeyCode.G, SwapUtility = Enum.KeyCode.Z, Melee = Enum.KeyCode.V,
	Inventory = Enum.KeyCode.Tab, Menu = Enum.KeyCode.M, Map = Enum.KeyCode.N,
	Heal = Enum.KeyCode.Four, Shield = Enum.KeyCode.Five, Oxygen = Enum.KeyCode.Six,
	Slot1 = Enum.KeyCode.One, Slot2 = Enum.KeyCode.Two, Slot3 = Enum.KeyCode.Three,
	RollLeft = Enum.KeyCode.Q, RollRight = Enum.KeyCode.E,
}
State.BindingOrder = {
	"Forward", "Back", "Left", "Right", "Up", "Down", "Boost", "Brake", "RollLeft", "RollRight", "Reload", "Utility", "SwapUtility", "Melee",
	"Heal", "Shield", "Oxygen", "Inventory", "Map", "Menu",
}
State.BindingLabels = {
	Forward = "Thrust forward", Back = "Thrust back", Left = "Strafe left", Right = "Strafe right", Up = "Move up", Down = "Move down",
	Boost = "Boost", Brake = "Stabilise / brake", RollLeft = "Air roll left", RollRight = "Air roll right", Reload = "Reload", Utility = "Use utility", SwapUtility = "Switch utility",
	Melee = "Melee", Heal = "Use medical", Shield = "Use shield cell", Oxygen = "Use O2 canister", Inventory = "Inventory",
	Map = "Tactical map", Menu = "Menu",
}

State.Inventory = nil -- last sync from server
State.Profile = nil
State.TemporaryProfile = false
State.UIOpen = false -- true while any modal (see SetModal) is open
State.Aiming = false
State.SelectedUtility = "tether"
State.Spectating = nil :: Player?
State.Boost = 0
State.BoostMax = Config.Movement.BoostMax
State.Tether = nil -- { point = Vector3, untilT = number }

State.InventoryChanged = signal()
State.ProfileChanged = signal()
State.Notice = signal() -- (text, color)
State.Hit = signal() -- (amount, kill)
State.Damaged = signal() -- (fromPos, amount, shield)
State.KillFeed = signal() -- (data)
State.Results = signal() -- (data)
State.Eliminated = signal() -- (data)
State.UseProgress = signal() -- (label, seconds)
State.Reloading = signal() -- (seconds)
State.UIChanged = signal()

-- Modal screens (menu, inventory, results). Any open modal frees the mouse and blocks firing.
local modals: { [string]: boolean } = {}
function State.SetModal(name: string, open: boolean)
	if open then modals[name] = true else modals[name] = nil end
	State.UIOpen = next(modals) ~= nil
	State.UIChanged:Fire(State.UIOpen)
end

function State.IsModalOpen(name: string): boolean
	return modals[name] == true
end

return State
