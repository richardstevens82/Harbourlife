-- Main menu (opens on join and with M): Play, Practice, Loadout, Locker, Settings, Statistics,
-- Tutorial, Credits. Every option shown is implemented. During a match only Resume, Settings and
-- Tutorial are offered.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Loadouts = require(Shared.Loadouts)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.ClientState)
local UI = require(script.Parent.UIKit)
local Effects = require(script.Parent.EffectsController)

local Menu = {}
local player = Players.LocalPlayer
local C = UI.Colors
local new = UI.new
local gui: ScreenGui
local root: Frame
local nav: Frame
local page: Frame
local currentPage = "home"
local rebinding: string? = nil

local TUTORIAL = {
	{ "Zero-gravity movement", "W/S thrust forward/back, A/D strafe, SPACE moves up, CTRL moves down - always relative to where you look. You keep your momentum when you let go: plan your drift. Hold SHIFT to boost (uses boost energy). Hold X to stabilise and come to a full stop before aiming or looting." },
	{ "Tether", "Press G to fire your tether at any solid surface within 160m and reel yourself in. Press G or X again to let go. Charges are limited - find Tether Spools. Press Z to switch your utility to Pulse Charges (thrown, short fuse)." },
	{ "Oxygen", "Your suit drains oxygen in vacuum (about two minutes). Inside pressurised rooms it recharges. Green O2 stations refill instantly. At zero you get a few seconds of reserve air, then hypoxia damage. Breached rooms (blown hull plates) lose pressure." },
	{ "Airlocks", "Interiors connect to space through airlocks. Press F at a door to cycle it. Only one door opens at a time - the other closes and the chamber cycles first." },
	{ "Loot", "Press F to search crates, lockers, pods and caches; press F on items to pick them up. Rarity: common, uncommon, rare, epic, legendary. TAB opens your inventory (equip, use, drop). 4 heal, 5 shield cell, 6 O2 canister." },
	{ "Combat", "Left mouse fires, right mouse aims (tighter spread). R reloads, 1-3 or the wheel switch weapons, V is an emergency melee strike with knockback. Heavier weapons slow your cruise speed." },
	{ "The storm", "An orbital radiation storm closes in on a shrinking SPHERE of safe space. Watch the countdown and tactical map (N enlarges it): it shows the storm ring and whether the safe centre is above or below you. Damage outside rises each stage." },
	{ "Winning", "Last player in orbit wins. Eliminated players drop a suit locker with their gear and can spectate (Q/E to switch). Hazards: electrical faults spark before they discharge, reactor rooms irradiate, red cargo barrels explode when shot." },
}

local function setOpen(open: boolean)
	root.Visible = open
	State.SetModal("menu", open)
	if open then Menu.Show(currentPage) end
end
Menu.SetOpen = setOpen

local function clear(f: Instance)
	for _, c in f:GetChildren() do c:Destroy() end
end

local function title(text: string)
	UI.label(page, text, { TextSize = 24, Font = Enum.Font.GothamBlack, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 })
end

local function para(text: string, order: number, props)
	local l = UI.label(page, text, { TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 18), TextSize = 15,
		TextColor3 = C.Text, LayoutOrder = order, TextYAlignment = Enum.TextYAlignment.Top, RichText = true })
	for k, v in props or {} do (l :: any)[k] = v end
	return l
end

local pages = {}

function pages.home()
	local inMatch = player:GetAttribute("InMatch") == true and player:GetAttribute("Alive") == true
	title(Config.GameName)
	local p = State.Profile
	para(p and string.format("Level <b>%d</b>   |   %d XP   |   %d credits%s", p.level, p.xp, p.credits,
		State.TemporaryProfile and "\n<font color=\"#FF9060\">Progress is not saving in this session (DataStores unavailable).</font>" or "") or "Loading profile...", 1)
	local phase = ReplicatedStorage:FindFirstChild("MatchState") and ReplicatedStorage.MatchState:GetAttribute("Phase") or "Waiting"
	para("Match status: <b>" .. tostring(phase) .. "</b>", 2, { TextColor3 = C.Dim })
	if inMatch then
		para("You are in a live match. Close the menu to keep fighting.", 3)
		return
	end
	local queued = player:GetAttribute("Queued") == true
	para(queued and "<font color=\"#5ADC8C\">You are queued for the next match.</font> Practise on the range while you wait."
		or "You are not queued. Press PLAY to join the next match.", 3)
	local b = UI.button(page, queued and "LEAVE QUEUE" or "PLAY", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 52), TextSize = 22,
		BackgroundColor3 = queued and C.PanelLight or Color3.fromRGB(30, 80, 150) })
	b.MouseButton1Click:Connect(function()
		Effects.Play("ui")
		Remotes.Match:FireServer({ action = "queue", value = not queued })
		task.wait(0.2)
		if not queued then setOpen(false) else Menu.Show("home") end
	end)
	UI.button(page, "PRACTICE RANGE (stay in lobby, not queued)", { LayoutOrder = 5 }, function()
		Effects.Play("ui")
		Remotes.Match:FireServer({ action = "queue", value = false })
		setOpen(false)
	end)
end

function pages.loadout()
	title("LOADOUT")
	para("Everyone deploys with a common Vega P9 pistol. Your kit changes only a small piece of utility.", 1, { TextColor3 = C.Dim })
	local current = State.Profile and State.Profile.loadout or "scout"
	for i, l in Loadouts.List do
		UI.button(page, string.format("%s%s  -  %s", l.id == current and "> " or "", l.name, l.desc), { LayoutOrder = 1 + i, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = l.id == current and C.Accent or C.Text }, function()
			Effects.Play("ui")
			Remotes.Match:FireServer({ action = "loadout", id = l.id })
		end)
	end
	para("Equipment previews: every weapon is displayed on the pedestals along the lobby wall.", 20, { TextColor3 = C.Dim })
end

function pages.locker()
	title("LOCKER")
	para("Suit finishes unlock as you level up. Cosmetic only.", 1, { TextColor3 = C.Dim })
	local p = State.Profile or { level = 1, suit = "navy" }
	for i, s in Cosmetics.Suits do
		local unlocked = Cosmetics.IsUnlocked(s, p)
		local b = UI.button(page, string.format("%s%s   %s", p.suit == s.id and "> " or "", s.name, unlocked and "" or ("(level " .. s.level .. ")")),
			{ LayoutOrder = 1 + i, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = unlocked and C.Text or C.Dim, AutoButtonColor = unlocked })
		new("Frame", { BackgroundColor3 = s.suit, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -36, 0.5, 0), Size = UDim2.fromOffset(22, 22) }, b)
		new("Frame", { BackgroundColor3 = s.trim, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(22, 22) }, b)
		if unlocked then
			b.MouseButton1Click:Connect(function()
				Effects.Play("ui")
				Remotes.Match:FireServer({ action = "suit", id = s.id })
			end)
		end
	end
	local titles = {}
	for _, t in Cosmetics.Titles do
		table.insert(titles, (Cosmetics.IsUnlocked(t, p) and "<font color=\"#5ADC8C\">" or "<font color=\"#8C9BAF\">") .. t.name .. "</font>")
	end
	para("Titles: " .. table.concat(titles, "  ·  "), 30)
end

local function sendSettings()
	Remotes.Match:FireServer({ action = "settings", settings = State.Settings })
end

function pages.settings()
	title("SETTINGS")
	local S = State.Settings
	local order = 1
	local function stepper(label: string, get: () -> string, dec: () -> (), inc: () -> ())
		order += 1
		local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order }, page)
		local l = UI.label(r, label .. ": " .. get(), { Size = UDim2.new(1, -120, 1, 0), TextSize = 15 })
		UI.button(r, "-", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 0), Size = UDim2.fromOffset(52, 32) }, function()
			dec()
			l.Text = label .. ": " .. get()
			sendSettings()
		end)
		UI.button(r, "+", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(52, 32) }, function()
			inc()
			l.Text = label .. ": " .. get()
			sendSettings()
		end)
	end
	stepper("Look sensitivity", function() return string.format("%.1f", S.sensitivity) end,
		function() S.sensitivity = math.max(0.2, S.sensitivity - 0.1) end, function() S.sensitivity = math.min(3, S.sensitivity + 0.1) end)
	stepper("Field of view", function() return tostring(S.fov) end,
		function() S.fov = math.max(60, S.fov - 5) end, function() S.fov = math.min(100, S.fov + 5) end)
	order += 1
	UI.button(page, "Invert look Y: " .. (S.invertY and "ON" or "OFF"), { LayoutOrder = order }, function()
		S.invertY = not S.invertY
		sendSettings()
		Menu.Show("settings")
	end)
	order += 1
	para("<b>Controls</b> (click a binding, then press a key). Bindings apply to this session.", order, { TextColor3 = C.Dim })
	for _, action in State.BindingOrder do
		order += 1
		local key = State.Bindings[action]
		local text = string.format("%-22s  %s", State.BindingLabels[action], rebinding == action and "press a key..." or key.Name)
		UI.button(page, text, { LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 28), TextSize = 14,
			Font = Enum.Font.Code }, function()
			rebinding = action
			Menu.Show("settings")
		end)
	end
	order += 1
	para("Mouse: left fire, right aim, wheel switch weapon.  Gamepad: sticks move/look, A up, B down, L3 boost, X brake, R2 fire, L2 aim, R1 utility, Y reload, L1 next weapon, D-pad items, Select inventory.",
		order, { TextColor3 = C.Dim, TextSize = 13 })
end

function pages.stats()
	title("STATISTICS")
	local p = State.Profile
	if not p then
		para("Loading...", 1)
		return
	end
	local kd = p.kills / math.max(1, p.matches - p.wins)
	para(string.format(
		"Level <b>%d</b>  (%d / %d XP)\nCredits <b>%d</b>\n\nMatches played <b>%d</b>\nVictories <b>%d</b>\nEliminations <b>%d</b>\nK/D <b>%.2f</b>\nDamage dealt <b>%d</b>\nBest placement <b>%s</b>\nTime survived <b>%s</b>",
		p.level, p.xp, Config.XpForLevel(p.level), p.credits, p.matches, p.wins, p.kills, kd, p.damage,
		p.bestPlacement > 0 and ("#" .. p.bestPlacement) or "-", UI.formatTime(p.timeSurvived)), 1)
end

function pages.tutorial()
	title("TUTORIAL")
	for i, t in TUTORIAL do
		para("<b>" .. t[1] .. "</b>\n" .. t[2], i)
	end
end

function pages.credits()
	title("CREDITS")
	para("ZERO GRAVITY: LAST ORBIT\n\nDesign, code, procedural environment and UI built for Roblox.\nAll geometry is generated by the game's own construction kit - no free models, no third-party scripts.\nSounds: Roblox built-in client sounds (placeholders until licensed audio is added).", 1)
end

function Menu.Show(name: string)
	currentPage = name
	clear(page)
	UI.list(page, 8)
	local fn = pages[name] or pages.home
	fn()
	-- nav highlights
	for _, b in nav:GetChildren() do
		if b:IsA("TextButton") then
			b.TextColor3 = b.Name == name and C.Accent or C.Text
		end
	end
end

local function buildNav()
	local inMatch = player:GetAttribute("InMatch") == true and player:GetAttribute("Alive") == true
	clear(nav)
	UI.list(nav, 6)
	local entries = inMatch and { { "home", "RESUME" }, { "settings", "SETTINGS" }, { "tutorial", "TUTORIAL" } }
		or { { "home", "PLAY" }, { "loadout", "LOADOUT" }, { "locker", "LOCKER" }, { "settings", "SETTINGS" }, { "stats", "STATISTICS" },
			{ "tutorial", "TUTORIAL" }, { "credits", "CREDITS" } }
	for i, e in entries do
		local b = UI.button(nav, e[2], { Name = e[1], LayoutOrder = i })
		b.MouseButton1Click:Connect(function()
			Effects.Play("ui")
			if inMatch and e[1] == "home" then
				setOpen(false)
			else
				Menu.Show(e[1])
			end
		end)
	end
	UI.button(nav, "CLOSE  [M]", { LayoutOrder = 99, BackgroundColor3 = Color3.fromRGB(40, 20, 24) }, function() setOpen(false) end)
end

function Menu.Start()
	gui = new("ScreenGui", { Name = "ZG_Menu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10 })
	local scale = new("UIScale", {}, gui)
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 700), 0.55, 1.2)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	root = UI.panel(gui, { Name = "Menu", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(860, 540),
		BackgroundTransparency = 0.12 })
	nav = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 16), Size = UDim2.new(0, 200, 1, -32) }, root)
	page = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(236, 16), Size = UDim2.new(1, -252, 1, -32),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4 }, root)
	gui.Parent = player:WaitForChild("PlayerGui")
	buildNav()
	setOpen(true)

	UserInputService.InputBegan:Connect(function(io, processed)
		if rebinding and io.UserInputType == Enum.UserInputType.Keyboard then
			if io.KeyCode ~= Enum.KeyCode.Escape then State.Bindings[rebinding] = io.KeyCode end
			rebinding = nil
			Menu.Show("settings")
			return
		end
		if processed then return end
		if io.KeyCode == State.Bindings.Menu or io.KeyCode == Enum.KeyCode.ButtonStart then
			buildNav()
			setOpen(not root.Visible)
		end
	end)
	State.ProfileChanged:Connect(function()
		if root.Visible then Menu.Show(currentPage) end
	end)
	player:GetAttributeChangedSignal("Queued"):Connect(function()
		if root.Visible and currentPage == "home" then Menu.Show("home") end
	end)
	for _, attr in { "InMatch", "Alive" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			buildNav()
			if player:GetAttribute("InMatch") and player:GetAttribute("Alive") and root.Visible then setOpen(false) end
		end)
	end
end

return Menu
