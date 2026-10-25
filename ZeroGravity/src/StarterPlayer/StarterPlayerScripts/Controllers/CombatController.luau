-- Client combat input and prediction. Sends aim rays to the server (which validates and decides
-- hits); draws the local tracer/muzzle flash immediately so firing feels responsive.
-- Also handles weapon switching, reload, melee, utilities and consumable hotkeys.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weapons = require(Shared.WeaponDefinitions)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.ClientState)
local CameraController = require(script.Parent.CameraController)
local Movement = require(script.Parent.MovementController)
local Effects = require(script.Parent.EffectsController)
local Animator = require(script.Parent.CharacterAnimator)

local Combat = {}
local player = Players.LocalPlayer
local triggerHeld = false
local lastShot = 0
local reloadingUntil = 0
local burstQueue = 0
local rng = Random.new()

local function canAct(): boolean
	if State.UIOpen or State.Spectating then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function activeWeapon()
	local inv = State.Inventory
	if not inv or inv.active == 0 then return nil end
	local w = inv.weapons[inv.active]
	return w or nil
end

local function muzzlePosition(): Vector3?
	local char = player.Character
	if not char then return nil end
	local held = char:FindFirstChild("HeldWeapon")
	local muzzle = held and held:FindFirstChild("Muzzle", true) :: Attachment?
	if muzzle then return muzzle.WorldPosition end
	local head = char:FindFirstChild("Head") :: BasePart?
	return head and head.Position
end

function Combat.Reload()
	local w = activeWeapon()
	if not w or os.clock() < reloadingUntil or w.mag >= w.magSize then return end
	Remotes.Combat:FireServer({ action = "reload" })
end

local function fireOnce()
	local w = activeWeapon()
	if not w then return false end
	local def = Weapons.Get(w.id)
	if w.mag <= 0 then
		Combat.Reload()
		Effects.Play("dry")
		return false
	end
	local origin = muzzlePosition()
	if not origin then return false end
	local ignore = { player.Character :: Model }
	local aim = CameraController.AimPoint(def.maxRange, ignore)
	local base = (aim - origin)
	if base.Magnitude < 0.1 then base = workspace.CurrentCamera.CFrame.LookVector end
	base = base.Unit
	-- spread: tighter when aiming, wider while moving fast
	local moving = math.clamp(Movement.Speed() / Config.Movement.MaxSpeed, 0, 1.5)
	local spread = (State.Aiming and def.adsSpread or def.spread) + moving * 0.6
	local dirs = {}
	for i = 1, def.pellets do
		local cf = CFrame.lookAt(Vector3.zero, base)
		local r = math.rad(spread) * math.sqrt(rng:NextNumber())
		local a = rng:NextNumber(0, math.pi * 2)
		if def.pellets == 1 and i == 1 and spread < 0.01 then r = 0 end
		dirs[i] = (cf * CFrame.Angles(math.sin(a) * r, math.cos(a) * r, 0)).LookVector
	end
	w.mag -= 1
	Remotes.Combat:FireServer({ action = "fire", origin = origin, dirs = dirs, expectMag = w.mag })
	-- local presentation (the server's raycast uses the same origin and directions)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local ends = {}
	for _, d in dirs do
		local hit = workspace:Raycast(origin, d * def.maxRange, params)
		table.insert(ends, hit and hit.Position or origin + d * def.maxRange)
	end
	Effects.Shot(origin, ends, w.id, true)
	Animator.Fired()
	CameraController.Kick(def.recoil * (State.Aiming and 0.6 or 1))
	State.InventoryChanged:Fire(State.Inventory)
	return true
end

local function tryFire()
	local w = activeWeapon()
	if not w or not canAct() or os.clock() < reloadingUntil then return end
	local def = Weapons.Get(w.id)
	local interval = Weapons.FireInterval(w.id)
	local now = os.clock()
	if now - lastShot < interval then return end
	lastShot = now
	if def.mode == "burst" then
		burstQueue = def.burstCount
		task.spawn(function()
			while burstQueue > 0 and canAct() do
				burstQueue -= 1
				if not fireOnce() then break end
				task.wait(def.burstDelay)
			end
			burstQueue = 0
		end)
	else
		fireOnce()
	end
end

local function useUtility()
	if not canAct() then return end
	if State.SelectedUtility == "tether" then
		if State.Tether then
			Movement.ReleaseTether()
			return
		end
		if (player:GetAttribute("TetherCharges") or 0) <= 0 then
			State.Notice:Fire("No tether charges", Color3.fromRGB(255, 140, 90))
			return
		end
		local cam = workspace.CurrentCamera.CFrame
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Model }
		local hit = workspace:Raycast(cam.Position, cam.LookVector * (Config.Tether.Range + 12), params)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hit or not root or (hit.Position - root.Position).Magnitude > Config.Tether.Range then
			State.Notice:Fire("Tether: no anchor in range (" .. Config.Tether.Range .. " studs)", Color3.fromRGB(255, 140, 90))
			return
		end
		Remotes.Equipment:FireServer({ action = "tether", target = hit.Position })
		Effects.Play("tether")
	else
		local inv = State.Inventory
		if not inv or (inv.items.grenade or 0) <= 0 then
			State.Notice:Fire("No pulse charges", Color3.fromRGB(255, 140, 90))
			return
		end
		Remotes.Equipment:FireServer({ action = "grenade", dir = workspace.CurrentCamera.CFrame.LookVector })
		Effects.Play("throw")
	end
end

local function useConsumable(kind: string)
	local inv = State.Inventory
	if not inv or not canAct() then return end
	local item
	if kind == "heal" then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local missing = hum and hum.MaxHealth - hum.Health or 0
		if missing <= 0 then return end
		-- use a stim for small wounds, the trauma kit for big ones
		if missing <= 30 and (inv.items.stim or 0) > 0 then item = "stim"
		elseif (inv.items.medkit or 0) > 0 then item = "medkit"
		elseif (inv.items.stim or 0) > 0 then item = "stim" end
	elseif kind == "shield" then
		item = (inv.items.shieldcell or 0) > 0 and "shieldcell" or nil
	elseif kind == "oxygen" then
		item = (inv.items.o2canister or 0) > 0 and "o2canister" or nil
	end
	if item then
		Remotes.Inventory:FireServer({ action = "use", item = item })
	else
		State.Notice:Fire("None in backpack", Color3.fromRGB(200, 200, 210))
	end
end

function Combat.Equip(slot: number)
	local inv = State.Inventory
	if not inv or not inv.weapons[slot] or inv.active == slot then return end
	reloadingUntil = 0
	Remotes.Combat:FireServer({ action = "equip", slot = slot })
	Effects.Play("equip")
end

-- Actions shared by the keyboard/mouse, gamepad and touch (TouchController) inputs.
function Combat.SetTrigger(held: boolean)
	triggerHeld = held
	if held then tryFire() end
end

function Combat.SetAiming(on: boolean)
	State.Aiming = on and canAct()
end

Combat.UseUtility = useUtility
Combat.UseConsumable = useConsumable

function Combat.SwapUtility()
	State.SelectedUtility = State.SelectedUtility == "tether" and "grenade" or "tether"
	State.InventoryChanged:Fire(State.Inventory)
end

function Combat.Melee()
	if canAct() then
		Remotes.Combat:FireServer({ action = "melee" })
		Effects.Play("melee")
	end
end

function Combat.Roll(dir: number)
	if canAct() and Movement.Roll(dir) then Animator.Roll(dir) end
end

function Combat.CycleWeapon()
	local inv = State.Inventory
	if inv then Combat.Equip(inv.active % Config.Inventory.WeaponSlots + 1) end
end

function Combat.Start()
	local B = State.Bindings
	UserInputService.InputBegan:Connect(function(io, processed)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.KeyCode == Enum.KeyCode.ButtonR2 then
			if processed and State.UIOpen then return end
			Combat.SetTrigger(true)
			return
		elseif io.UserInputType == Enum.UserInputType.MouseButton2 or io.KeyCode == Enum.KeyCode.ButtonL2 then
			Combat.SetAiming(true)
			return
		end
		if processed then return end
		local k = io.KeyCode
		if k == B.Reload or k == Enum.KeyCode.ButtonY then Combat.Reload()
		elseif k == B.Utility or k == Enum.KeyCode.ButtonR1 then useUtility()
		elseif k == B.SwapUtility or k == Enum.KeyCode.DPadUp then Combat.SwapUtility()
		elseif k == B.Melee or k == Enum.KeyCode.ButtonR3 then Combat.Melee()
		elseif k == B.RollLeft or k == B.RollRight then Combat.Roll(if k == B.RollRight then 1 else -1)
		elseif k == B.Slot1 then Combat.Equip(1)
		elseif k == B.Slot2 then Combat.Equip(2)
		elseif k == B.Slot3 then Combat.Equip(3)
		elseif k == Enum.KeyCode.ButtonL1 then Combat.CycleWeapon()
		elseif k == B.Heal or k == Enum.KeyCode.DPadLeft then useConsumable("heal")
		elseif k == B.Shield or k == Enum.KeyCode.DPadRight then useConsumable("shield")
		elseif k == B.Oxygen or k == Enum.KeyCode.DPadDown then useConsumable("oxygen")
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.KeyCode == Enum.KeyCode.ButtonR2 then
			Combat.SetTrigger(false)
		elseif io.UserInputType == Enum.UserInputType.MouseButton2 or io.KeyCode == Enum.KeyCode.ButtonL2 then
			State.Aiming = false
		end
	end)
	UserInputService.InputChanged:Connect(function(io, processed)
		if processed or State.UIOpen or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		local inv = State.Inventory
		if not inv then return end
		local n = Config.Inventory.WeaponSlots
		for i = 1, n do
			local slot = ((inv.active - 1 + (io.Position.Z > 0 and -i or i)) % n) + 1
			if inv.weapons[slot] then
				Combat.Equip(slot)
				break
			end
		end
	end)
	-- Other players see us shoulder the gun: the server mirrors our aim state onto the character
	-- (throttled; the latest state is always sent).
	local sentAim, lastAimSend = false, 0
	RunService.RenderStepped:Connect(function()
		local aimingNow = State.Aiming == true
		if aimingNow ~= sentAim and os.clock() - lastAimSend > 0.15 then
			sentAim, lastAimSend = aimingNow, os.clock()
			Remotes.Combat:FireServer({ action = "aim", value = aimingNow })
		end
		if triggerHeld then
			local w = activeWeapon()
			if w and Weapons.Get(w.id).mode == "auto" then tryFire() end
		end
		if State.UIOpen then
			triggerHeld = false
			State.Aiming = false
		end
	end)
	State.Reloading:Connect(function(seconds)
		reloadingUntil = os.clock() + seconds
	end)
	player.CharacterAdded:Connect(function()
		reloadingUntil, burstQueue, triggerHeld = 0, 0, false
		State.Aiming = false
	end)
end

return Combat
