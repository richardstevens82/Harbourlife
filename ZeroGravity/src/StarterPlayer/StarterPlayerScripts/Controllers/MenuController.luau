-- Main menu (opens on join and with M): Deploy, Practice, Loadout, Locker, Settings, Statistics,
-- Tutorial, Credits. Every option shown is implemented. During a match only Resume, Settings and
-- Tutorial are offered.
--
-- Layout: a full-screen orbital overlay. A twinkling starfield and a left-to-right fade let the
-- lobby window (station + planet) show through; the logo, navigation and pilot card sit on the
-- left; the selected page sits in a bracketed glass panel on the right; a status chip shows the
-- orbit state and how many pilots and bots are ready.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
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
local leftCol: Frame
local content: Frame
local pageHeader: TextLabel
local statusText: TextLabel
local pilotText: TextLabel
local setXp: (number, string?) -> ()
local stars: { Frame } = {}

local PAGE_TAGS = {
	home = "MISSION CONTROL", loadout = "DEPLOYMENT KIT", locker = "SUIT LOCKER", settings = "SYSTEM SETTINGS",
	stats = "PILOT RECORD", tutorial = "FLIGHT MANUAL", credits = "CREDITS",
}
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
	local wasOpen = root.Visible
	root.Visible = open
	State.SetModal("menu", open)
	if open then
		Menu.Show(currentPage)
		if not wasOpen then
			UI.reveal(leftCol, Vector2.new(-60, 0))
			UI.reveal(content, Vector2.new(80, 0), 0.05)
		end
	end
end
Menu.SetOpen = setOpen

local function clear(f: Instance)
	for _, c in f:GetChildren() do c:Destroy() end
end

local function title(text: string)
	pageHeader.Text = text
end

local function para(text: string, order: number, props)
	local l = UI.label(page, text, { TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 18), TextSize = 17,
		TextColor3 = C.Text, LayoutOrder = order, TextYAlignment = Enum.TextYAlignment.Top, RichText = true })
	for k, v in props or {} do (l :: any)[k] = v end
	return l
end

local pages = {}

function pages.home()
	local inMatch = player:GetAttribute("InMatch") == true and player:GetAttribute("Alive") == true
	title("MISSION CONTROL")
	para("<font size=\"24\"><b>20 PILOTS. ONE ORBIT. ONE SURVIVOR.</b></font>", 1, { Font = UI.Fonts.Bold, TextColor3 = C.Accent })
	para("Fly in every direction, loot the station and the exploration ship, manage your oxygen and stay ahead of the radiation storm.", 2,
		{ TextColor3 = C.Dim })
	if State.TemporaryProfile then
		para("<font color=\"#FFB060\">Progress is not saving in this session (DataStores unavailable).</font>", 3)
	end
	if inMatch then
		para("You are in a live match. Close the menu to keep fighting.", 4)
		return
	end
	local queued = player:GetAttribute("Queued") == true
	para(queued and "<font color=\"#46FFAA\">QUEUED</font> - you deploy with the next drop. Practise on the range while you wait."
		or "Not queued. Hit DEPLOY to join the next drop (bots fill every empty seat).", 4)
	local b = UI.button(page, queued and "LEAVE QUEUE" or "DEPLOY", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 58), TextSize = 22 }, nil,
		{ primary = not queued })
	b.MouseButton1Click:Connect(function()
		Effects.Play("ui")
		Remotes.Match:FireServer({ action = "queue", value = not queued })
		task.wait(0.2)
		if not queued then setOpen(false) else Menu.Show("home") end
	end)
	UI.button(page, "PRACTICE RANGE  (stay in the lobby)", { LayoutOrder = 6 }, function()
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
			Font = UI.Fonts.Mono }, function()
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
	UI.list(page, 10)
	pageHeader.Text = ""
	local fn = pages[name] or pages.home
	fn()
	local tagLabel = content:FindFirstChild("PageTag") :: TextLabel?
	if tagLabel then tagLabel.Text = "// " .. (PAGE_TAGS[name] or "") end
	-- nav highlights
	for _, b in nav:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == name
			b.TextColor3 = on and C.Accent or C.Text
			local rail = b:FindFirstChild("Rail") :: Frame?
			if rail then rail.BackgroundTransparency = on and 0 or 0.6 end
		end
	end
end

local NAV_GLYPH = { home = "\u{25C8}", loadout = "\u{25A3}", locker = "\u{2B21}", settings = "\u{2699}", stats = "\u{25B2}", tutorial = "\u{25CE}",
	credits = "\u{2726}" }

local function buildNav()
	local inMatch = player:GetAttribute("InMatch") == true and player:GetAttribute("Alive") == true
	clear(nav)
	UI.list(nav, 8)
	local entries = inMatch and { { "home", "RESUME" }, { "settings", "SETTINGS" }, { "tutorial", "TUTORIAL" } }
		or { { "home", "MISSION" }, { "loadout", "LOADOUT" }, { "locker", "LOCKER" }, { "settings", "SETTINGS" }, { "stats", "STATISTICS" },
			{ "tutorial", "TUTORIAL" }, { "credits", "CREDITS" } }
	for i, e in entries do
		local b = UI.button(nav, "   " .. (NAV_GLYPH[e[1]] or "") .. "   " .. e[2], { Name = e[1], LayoutOrder = i, Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left })
		b.MouseButton1Click:Connect(function()
			Effects.Play("ui")
			if inMatch and e[1] == "home" then
				setOpen(false)
			else
				Menu.Show(e[1])
			end
		end)
	end
	UI.button(nav, "   \u{2715}   CLOSE  [M]", { LayoutOrder = 99, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim }, function()
		setOpen(false)
	end)
end

-- Pilot card + status chip, refreshed every half second while the menu is open.
local function refreshStatus()
	local p = State.Profile
	if p then
		local need = Config.XpForLevel(p.level)
		local prev = p.level > 1 and Config.XpForLevel(p.level - 1) or 0
		pilotText.Text = string.format("<font size=\"20\"><b>%s</b></font>\nLEVEL %d   \u{00B7}   %d CREDITS", string.upper(player.Name), p.level, p.credits)
		setXp((p.xp - prev) / math.max(1, need - prev), string.format("%d / %d XP", p.xp, need))
	end
	local ms = ReplicatedStorage:FindFirstChild("MatchState")
	if ms then
		local phase = string.upper(tostring(ms:GetAttribute("Phase") or "WAITING"))
		local bots = ms:GetAttribute("Bots") or 0
		local queued = ms:GetAttribute("Queued") or 0
		statusText.Text = string.format("ORBIT STATUS  <font color=\"#00E1FF\">\u{25CF} %s</font>   |   %d PILOT%s + %d BOTS", phase, queued,
			queued == 1 and "" or "S", bots)
	end
end

-- Twinkling starfield behind the menu.
local function buildStars(parent: Instance)
	local rng = Random.new(7)
	for i = 1, 90 do
		local size = rng:NextNumber() < 0.15 and 3 or (rng:NextNumber() < 0.5 and 2 or 1)
		local star = new("Frame", { Name = "Star", BackgroundColor3 = i % 7 == 0 and C.Accent or Color3.new(1, 1, 1), BorderSizePixel = 0,
			Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = rng:NextNumber(0.1, 0.7) }, parent)
		UI.corner(star, 2)
		table.insert(stars, star)
	end
	task.spawn(function()
		local trng = Random.new()
		while gui and gui.Parent do
			if root.Visible then
				for _ = 1, 6 do
					local s = stars[trng:NextInteger(1, #stars)]
					TweenService:Create(s, TweenInfo.new(trng:NextNumber(0.6, 1.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true),
						{ BackgroundTransparency = trng:NextNumber(0, 0.9) }):Play()
				end
				refreshStatus()
			end
			task.wait(0.5)
		end
	end)
end

function Menu.Start()
	gui = new("ScreenGui", { Name = "ZG_Menu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10 })
	local scale = new("UIScale", {}, gui)
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.5, 1.25)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	root = new("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	-- backdrop: deep space fading out to the right so the lobby window (station, planet) shows through
	local back = new("Frame", { Name = "Backdrop", BackgroundColor3 = Color3.fromRGB(2, 5, 14), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, root)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.02), NumberSequenceKeypoint.new(0.45, 0.25),
		NumberSequenceKeypoint.new(1, 0.55) }) }, back)
	buildStars(back)
	-- left column: logo, navigation, pilot card
	leftCol = new("Frame", { Name = "Left", BackgroundTransparency = 1, Position = UDim2.new(0, 56, 0, 0), Size = UDim2.new(0, 360, 1, 0) }, root)
	local logo = UI.label(leftCol, "ZERO GRAVITY", { Font = UI.Fonts.Display, TextSize = 40, Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 50) })
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(0, 225, 255), Color3.fromRGB(170, 120, 255)) }, logo)
	UI.label(leftCol, "L A S T    O R B I T", { Font = UI.Fonts.Display, TextSize = 14, TextColor3 = C.Dim, Position = UDim2.fromOffset(4, 110),
		Size = UDim2.new(1, 0, 0, 20) })
	new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 140), Size = UDim2.fromOffset(120, 2) }, leftCol)
	nav = new("Frame", { Name = "Nav", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 170), Size = UDim2.new(1, 0, 0, 400) }, leftCol)
	local card = UI.panel(leftCol, { Name = "PilotCard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(1, 0, 0, 92) },
		{ brackets = true })
	UI.pad(card, 12)
	pilotText = UI.label(card, "PILOT", { Font = UI.Fonts.Bold, TextSize = 15, RichText = true, Size = UDim2.new(1, 0, 0, 44),
		TextYAlignment = Enum.TextYAlignment.Top })
	local _, xpSetter = UI.bar(card, C.Accent, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 12) }, 20)
	setXp = xpSetter
	-- status chip (top right)
	local chip = UI.panel(root, { Name = "Status", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 40), Size = UDim2.fromOffset(470, 36) })
	statusText = UI.label(chip, "ORBIT STATUS", { Font = UI.Fonts.Bold, TextSize = 15, RichText = true, Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center })
	-- content panel (right)
	content = UI.panel(root, { Name = "Content", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -56, 0.5, 30),
		Size = UDim2.new(0.5, 0, 0.72, 0) }, { brackets = true })
	new("UISizeConstraint", { MinSize = Vector2.new(520, 380), MaxSize = Vector2.new(820, 640) }, content)
	UI.label(content, "// MISSION CONTROL", { Name = "PageTag", Font = UI.Fonts.Display, TextSize = 10, TextColor3 = C.Accent,
		Position = UDim2.fromOffset(22, 14), Size = UDim2.new(1, -44, 0, 14) })
	pageHeader = UI.title(content, "", { Position = UDim2.fromOffset(22, 32), Size = UDim2.new(1, -44, 0, 36) })
	page = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(22, 84), Size = UDim2.new(1, -44, 1, -104),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.Accent }, content)
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
		if root.Visible then
			Menu.Show(currentPage)
			refreshStatus()
		end
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
