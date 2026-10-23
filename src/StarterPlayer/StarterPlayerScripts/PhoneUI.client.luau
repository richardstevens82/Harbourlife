-- Mobile phone (press P, or tap the phone button): slides up in the bottom-right corner like a real
-- handset, with a status bar, home screen of apps and a home bar. Apps:
--   Bank (deposit / withdraw, server-checked)   Jobs (current job, quit, job list)   Bag (inventory)
--   GPS (waypoint to places in the world)       Messages (notification history)       Stats
--   Garage (owned vehicles)                     Settings (wallpaper)
-- Money and job changes go to PhoneService on the server; everything else is display only.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Items = require(Shared.ItemDefinitions)
local Categories = require(Shared.ItemCategories)
local Config = require(Shared.Config)
local SkillDefs = require(Shared.SkillDefinitions)
local Jobs = require(Shared.JobDefinitions)
local Vehicles = require(Shared.VehicleDefinitions)

local player = Players.LocalPlayer
local rgb = Color3.fromRGB
local TEXT, DIM, CARD = rgb(255, 255, 255), rgb(200, 205, 215), rgb(255, 255, 255)
local PW, PH = 250, 500 -- phone body size
local WALLPAPERS = {
	{ name = "Harbour", a = rgb(20, 60, 120), b = rgb(10, 150, 170) },
	{ name = "Sunset", a = rgb(120, 40, 90), b = rgb(250, 140, 60) },
	{ name = "Forest", a = rgb(20, 60, 40), b = rgb(90, 160, 90) },
	{ name = "Night", a = rgb(15, 15, 30), b = rgb(60, 50, 110) },
}

local gui = Instance.new("ScreenGui")
gui.Name = "PhoneUI"; gui.ResetOnSpawn = false; gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do (o :: any)[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function clear(frame)
	for _, c in frame:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
end

-- phone body, screen and wallpaper
local OPEN_POS, CLOSED_POS = UDim2.new(1, -PW - 18, 1, -PH - 18), UDim2.new(1, -PW - 18, 1, 40)
local phone = new("Frame", { Size = UDim2.fromOffset(PW, PH), Position = CLOSED_POS, BackgroundColor3 = rgb(18, 18, 22), Visible = false }, gui)
corner(phone, 34)
new("UIStroke", { Color = rgb(90, 90, 100), Thickness = 3 }, phone)
local phoneScale = new("UIScale", {}, phone)
local function fit()
	local vp = workspace.CurrentCamera.ViewportSize
	phoneScale.Scale = math.min(1, (vp.Y - 40) / PH)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
fit()
for _, y in { 90, 140 } do -- side buttons
	new("Frame", { BackgroundColor3 = rgb(70, 70, 80), Position = UDim2.fromOffset(-4, y), Size = UDim2.fromOffset(4, 36) }, phone)
end
local screen = new("Frame", { Position = UDim2.fromOffset(9, 9), Size = UDim2.new(1, -18, 1, -18), BackgroundColor3 = TEXT, ClipsDescendants = true }, phone)
corner(screen, 26)
local wallpaper = new("UIGradient", { Rotation = 120 }, screen)
local wallpaperIndex = 1
local function applyWallpaper()
	local w = WALLPAPERS[wallpaperIndex]
	wallpaper.Color = ColorSequence.new(w.a, w.b)
end
applyWallpaper()
local notch = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(76, 20),
	BackgroundColor3 = rgb(0, 0, 0), ZIndex = 10 }, screen)
corner(notch, 10)

local status = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 5 }, screen)
local clockSmall = new("TextLabel", { Text = "12:00", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = TEXT, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(50, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, status)
new("TextLabel", { Text = "5G ▮▮▮ 🔋", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = TEXT, BackgroundTransparency = 1,
	Position = UDim2.new(1, -86, 0, 8), Size = UDim2.fromOffset(70, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, status)

local homeBar = new("TextButton", { Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(100, 5),
	BackgroundColor3 = TEXT, AutoButtonColor = false, ZIndex = 10 }, screen)
corner(homeBar, 3)

-- home screen
local home = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, screen)
local bigClock = new("TextLabel", { Text = "12:00", Font = Enum.Font.GothamBold, TextSize = 46, TextColor3 = TEXT, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 52) }, home)
new("TextLabel", { Text = "Harbourlife", Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = DIM, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 18) }, home)
local grid = new("Frame", { Position = UDim2.fromOffset(12, 130), Size = UDim2.new(1, -24, 1, -150), BackgroundTransparency = 1 }, home)
new("UIGridLayout", { CellSize = UDim2.fromOffset(48, 70), CellPadding = UDim2.fromOffset(4, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center }, grid)

-- app screen: header with back button and a scrolling body
local appPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(245, 246, 250), Visible = false }, screen)
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = rgb(40, 110, 220) }, appPage)
local back = new("TextButton", { Text = "‹", Font = Enum.Font.GothamBold, TextSize = 30, TextColor3 = TEXT, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(8, 32), Size = UDim2.fromOffset(30, 34) }, header)
local appTitle = new("TextLabel", { Text = "", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = TEXT, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(40, 34), Size = UDim2.new(1, -50, 0, 30), TextXAlignment = Enum.TextXAlignment.Left }, header)
local body = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 1, -90), BackgroundTransparency = 1,
	ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarImageColor3 = rgb(120, 120, 130) }, appPage)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, body)

-- body helpers
local order = 0
local function nextOrder() order += 1; return order end
local function label(t, size, color, bold)
	return new("TextLabel", { Text = t, TextSize = size or 13, TextColor3 = color or rgb(30, 34, 44), BackgroundTransparency = 1, TextWrapped = true,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() }, body)
end
local function card(height)
	local c = new("Frame", { BackgroundColor3 = CARD, Size = UDim2.new(1, 0, 0, height), LayoutOrder = nextOrder() }, body)
	corner(c, 12)
	return c
end
local function buttonRow(buttons)
	local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder() }, body)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, r)
	local w = 1 / #buttons
	for _, b in buttons do
		local btn = new("TextButton", { Text = b[1], Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = TEXT, BackgroundColor3 = b[2],
			Size = UDim2.new(w, -6 + 6 / #buttons, 1, 0) }, r)
		corner(btn, 8)
		btn.MouseButton1Click:Connect(b[3])
	end
	return r
end

local data
local messages = {}
local currentApp
local waypoint -- { part, gui, name }

local function fmtTime()
	local t = Lighting.ClockTime
	return string.format("%02d:%02d", math.floor(t), math.floor((t % 1) * 60))
end

-- GPS: places found in the world by Part name
local function firstPart(match)
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and match(d.Name) then return d.Position end
	end
	return nil
end
local PLACES = {
	{ "🛍️ Harbour Mall", function()
		local m = workspace:FindFirstChild("HarbourMall")
		local site = workspace:FindFirstChild("MallSite", true)
		return (site and site:IsA("BasePart") and site.Position) or (m and m:GetBoundingBox().Position)
	end },
	{ "💼 Job Centre", function() return firstPart(function(n) return n:match("^JobCentre_") ~= nil end) end },
	{ "🍕 Harbour Pizza", function() return firstPart(function(n) return n == "PizzaCounter" end) end },
	{ "☕ Harbour Café", function() return firstPart(function(n) return n == "CafeCounter" end) end },
	{ "🥐 Bakery", function() return firstPart(function(n) return n == "BakeryCounter" end) end },
	{ "🍽️ Restaurant", function() return firstPart(function(n) return n == "RestaurantCounter" end) end },
	{ "🍔 Dockside Burgers", function() return firstPart(function(n) return n == "FastFoodCounter" end) end },
	{ "📦 Food Wholesaler", function() return firstPart(function(n) return n == "Shop_food_wholesale" end) end },
	{ "⛽ Fuel Station", function() return firstPart(function(n) return n == "FuelStation" end) end },
	{ "🔧 Repair Garage", function() return firstPart(function(n) return n == "Garage_Repair" end) end },
	{ "🚗 Vehicle Garage", function() return firstPart(function(n) return n:match("^VehicleGarage_") ~= nil end) end },
}

local function clearWaypoint()
	if waypoint then waypoint.part:Destroy(); waypoint = nil end
end
local function setWaypoint(name, pos)
	clearWaypoint()
	local p = new("Part", { Name = "PhoneWaypoint", Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1,
		Size = Vector3.new(1, 1, 1), Position = pos + Vector3.new(0, 6, 0) }, workspace)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(180, 50), AlwaysOnTop = true, LightInfluence = 0 }, p)
	local t = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.3, BackgroundColor3 = rgb(20, 90, 220), TextColor3 = TEXT,
		Font = Enum.Font.GothamBold, TextScaled = true, Text = "📍 " .. name }, bb)
	corner(t, 10)
	waypoint = { part = p, label = t, name = name }
end
RunService.RenderStepped:Connect(function()
	if not waypoint then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local dist = (waypoint.part.Position - hrp.Position).Magnitude
	if dist < 20 then
		table.insert(messages, 1, { time = fmtTime(), text = "Arrived: " .. waypoint.name, kind = "success" })
		clearWaypoint()
	else
		waypoint.label.Text = string.format("📍 %s\n%d m", waypoint.name, math.floor(dist / 3.57)) -- ~3.57 studs per metre
	end
end)

local function money(n) return "$" .. tostring(n) end
local function phoneAction(action, arg) Remotes.PhoneAction:FireServer(action, arg) end

local APPS
APPS = {
	{ id = "bank", name = "Bank", icon = "🏦", color = rgb(30, 140, 90), render = function()
		local c = card(86)
		new("TextLabel", { Text = "Harbour Bank", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = rgb(30, 140, 90), BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), TextXAlignment = Enum.TextXAlignment.Left }, c)
		new("TextLabel", { Text = money(data.bank), Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = rgb(30, 34, 44), BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 32), TextXAlignment = Enum.TextXAlignment.Left }, c)
		new("TextLabel", { Text = "Cash in hand: " .. money(data.cash), Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = rgb(90, 95, 110),
			BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left }, c)
		local green, blue = rgb(30, 140, 90), rgb(40, 110, 220)
		label("Deposit cash", 13, nil, true)
		buttonRow({ { "$50", green, function() phoneAction("deposit", 50) end }, { "$100", green, function() phoneAction("deposit", 100) end },
			{ "$500", green, function() phoneAction("deposit", 500) end }, { "All", green, function() phoneAction("deposit", "all") end } })
		label("Withdraw cash", 13, nil, true)
		buttonRow({ { "$50", blue, function() phoneAction("withdraw", 50) end }, { "$100", blue, function() phoneAction("withdraw", 100) end },
			{ "$500", blue, function() phoneAction("withdraw", 500) end }, { "All", blue, function() phoneAction("withdraw", "all") end } })
		label("Mall ATMs work too.", 11, rgb(120, 125, 140))
	end },
	{ id = "jobs", name = "Jobs", icon = "💼", color = rgb(230, 140, 30), render = function()
		local job = Jobs[data.job]
		label("Current job", 12, rgb(120, 125, 140), true)
		label(job and job.name or data.job, 18, nil, true)
		if data.job ~= "unemployed" then
			buttonRow({ { "Quit job", rgb(200, 60, 60), function() phoneAction("quitJob") end } })
		end
		label("Sign up at a Job Centre, or at Mall Management for mall jobs.", 11, rgb(120, 125, 140))
		label("All jobs", 13, nil, true)
		local list = {}
		for id, j in Jobs do if id ~= "unemployed" then table.insert(list, j) end end
		table.sort(list, function(a, b) return a.pay > b.pay end)
		for _, j in list do
			local locked = data.level < j.minLevel
			local c = card(40)
			new("TextLabel", { Text = j.name, Font = Enum.Font.GothamBold, TextSize = 13, BackgroundTransparency = 1,
				TextColor3 = locked and rgb(160, 160, 170) or rgb(30, 34, 44), Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, 0, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left }, c)
			new("TextLabel", { Text = string.format("$%d/task · Lv %d", j.pay, j.minLevel), Font = Enum.Font.Gotham, TextSize = 11,
				BackgroundTransparency = 1, TextColor3 = rgb(110, 115, 130), Position = UDim2.new(0.55, 0, 0, 0), Size = UDim2.new(0.45, -10, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right }, c)
		end
	end },
	{ id = "bag", name = "Bag", icon = "🎒", color = rgb(150, 90, 220), render = function()
		local used, counts = 0, {}
		for id, n in data.inventory do
			used += 1
			local c = Items[id] and Items[id].category or "general"
			if not Categories.info[c] then c = "general" end
			counts[c] = (counts[c] or 0) + n
		end
		label(string.format("%d / %d slots used", used, Config.InventorySlots), 15, nil, true)
		buttonRow({ { "Open inventory", rgb(150, 90, 220), function()
			local inv = player.PlayerGui:FindFirstChild("InventoryUI")
			local ev = inv and inv:FindFirstChild("Open")
			if ev then ev:Fire() end
		end } })
		for _, cat in Categories.order do
			if counts[cat] then
				local info = Categories.info[cat]
				label(string.format("%s  %s: %d", info.icon, info.name, counts[cat]), 13)
			end
		end
		if used == 0 then label("Your bag is empty.", 13, rgb(120, 125, 140)) end
	end },
	{ id = "gps", name = "GPS", icon = "🗺️", color = rgb(40, 110, 220), render = function()
		if waypoint then
			label("Heading to " .. waypoint.name, 13, nil, true)
			buttonRow({ { "Clear waypoint", rgb(200, 60, 60), function() clearWaypoint(); APPS.open("gps") end } })
		end
		label("Tap a place to set a waypoint", 12, rgb(120, 125, 140))
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local found = 0
		for _, place in PLACES do
			local pos = place[2]()
			if pos then
				found += 1
				local dist = hrp and math.floor((pos - hrp.Position).Magnitude / 3.57) or 0
				local c = card(40)
				local b = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, c)
				new("TextLabel", { Text = place[1], Font = Enum.Font.GothamBold, TextSize = 13, BackgroundTransparency = 1, TextColor3 = rgb(30, 34, 44),
					Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.7, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left }, b)
				new("TextLabel", { Text = dist .. " m", Font = Enum.Font.Gotham, TextSize = 12, BackgroundTransparency = 1, TextColor3 = rgb(110, 115, 130),
					Position = UDim2.new(0.7, 0, 0, 0), Size = UDim2.new(0.3, -10, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, b)
				b.MouseButton1Click:Connect(function() setWaypoint(place[1], pos); APPS.open("gps") end)
			end
		end
		if found == 0 then label("No places found nearby.", 13, rgb(120, 125, 140)) end
	end },
	{ id = "messages", name = "Messages", icon = "💬", color = rgb(50, 190, 90), render = function()
		if #messages == 0 then label("No messages yet.", 13, rgb(120, 125, 140)) end
		local colors = { success = rgb(30, 140, 90), error = rgb(200, 60, 60), info = rgb(40, 110, 220) }
		for _, m in messages do
			local c = card(0)
			c.AutomaticSize = Enum.AutomaticSize.Y
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, c)
			new("UIListLayout", { Padding = UDim.new(0, 2) }, c)
			new("TextLabel", { Text = m.time, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = colors[m.kind] or colors.info,
				BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Left }, c)
			new("TextLabel", { Text = m.text, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = rgb(30, 34, 44), BackgroundTransparency = 1,
				TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Left }, c)
		end
	end },
	{ id = "stats", name = "Stats", icon = "📊", color = rgb(220, 70, 110), render = function()
		local need = math.floor(Config.XpBase * data.level ^ Config.XpExponent)
		label("Level " .. data.level, 22, nil, true)
		local bar = new("Frame", { BackgroundColor3 = rgb(220, 222, 230), Size = UDim2.new(1, 0, 0, 10), LayoutOrder = nextOrder() }, body)
		corner(bar, 5)
		corner(new("Frame", { BackgroundColor3 = rgb(220, 70, 110), Size = UDim2.new(math.clamp(data.xp / math.max(need, 1), 0, 1), 0, 1, 0) }, bar), 5)
		label(string.format("%d / %d XP to next level", data.xp, need), 11, rgb(120, 125, 140))
		label("Reputation: " .. (data.reputation or 0), 13)
		label("Skills", 13, nil, true)
		local any = false
		for id, def in SkillDefs do
			local s = data.skills and data.skills[id]
			if s then any = true; label(string.format("%s  ·  Lv %d", def.name, s.level), 13) end
		end
		if not any then label("No skills yet. Working jobs trains them.", 12, rgb(120, 125, 140)) end
	end },
	{ id = "garage", name = "Garage", icon = "🚗", color = rgb(70, 80, 100), render = function()
		local any = false
		for id, v in data.vehicles or {} do
			local def = Vehicles[id]
			if def then
				any = true
				local c = card(54)
				new("TextLabel", { Text = def.name, Font = Enum.Font.GothamBold, TextSize = 14, BackgroundTransparency = 1, TextColor3 = rgb(30, 34, 44),
					Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left }, c)
				new("TextLabel", { Text = string.format("Fuel %d/%d  ·  Condition %d%%", math.floor(v.fuel or 0), def.fuelCapacity, math.floor(v.condition or 0)),
					Font = Enum.Font.Gotham, TextSize = 12, BackgroundTransparency = 1, TextColor3 = rgb(110, 115, 130),
					Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left }, c)
			end
		end
		if not any then label("You don't own any vehicles.", 13, rgb(120, 125, 140)) end
		label("Take a vehicle out at its garage pad. Use GPS to find one.", 11, rgb(120, 125, 140))
	end },
	{ id = "settings", name = "Settings", icon = "⚙️", color = rgb(120, 125, 140), render = function()
		label("Wallpaper", 13, nil, true)
		for i, w in WALLPAPERS do
			buttonRow({ { (i == wallpaperIndex and "✓ " or "") .. w.name, w.a, function()
				wallpaperIndex = i; applyWallpaper(); APPS.open("settings")
			end } })
		end
		label("Keys: P phone · I inventory · Backspace back", 11, rgb(120, 125, 140))
	end },
}

function APPS.open(id)
	for _, app in APPS do
		if type(app) == "table" and app.id == id then
			currentApp = app
			home.Visible, appPage.Visible = false, true
			appTitle.Text = app.name
			header.BackgroundColor3 = app.color
			clear(body)
			order = 0
			if data then app.render() else label("Loading…", 13) end
			return
		end
	end
end

local function goHome()
	currentApp = nil
	home.Visible, appPage.Visible = true, false
end

for i, app in APPS do
	if type(app) ~= "table" then continue end
	local cell = new("Frame", { BackgroundTransparency = 1, LayoutOrder = i }, grid)
	local icon = new("TextButton", { Text = app.icon, TextSize = 24, Font = Enum.Font.GothamBold, BackgroundColor3 = app.color,
		Size = UDim2.fromOffset(48, 48), AutoButtonColor = true }, cell)
	corner(icon, 13)
	new("TextLabel", { Text = app.name, Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = TEXT, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-6, 50), Size = UDim2.fromOffset(60, 14) }, cell)
	icon.MouseButton1Click:Connect(function() APPS.open(app.id) end)
end

-- open / close
local isOpen = false
local tween = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local function setOpen(open: boolean)
	isOpen = open
	if open then
		phone.Visible = true
		goHome()
		TweenService:Create(phone, tween, { Position = OPEN_POS }):Play()
	else
		local t = TweenService:Create(phone, tween, { Position = CLOSED_POS })
		t.Completed:Connect(function() if not isOpen then phone.Visible = false end end)
		t:Play()
	end
end

local phoneButton = new("TextButton", { Text = "📱", TextSize = 26, Font = Enum.Font.GothamBold, BackgroundColor3 = rgb(25, 28, 36),
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(52, 52) }, gui)
corner(phoneButton, 26)
new("UIStroke", { Color = rgb(90, 90, 100), Thickness = 2 }, phoneButton)
phoneButton.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
local bagButton = new("TextButton", { Text = "🎒", TextSize = 24, Font = Enum.Font.GothamBold, BackgroundColor3 = rgb(25, 28, 36),
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -78, 1, -18), Size = UDim2.fromOffset(52, 52) }, gui)
corner(bagButton, 26)
new("UIStroke", { Color = rgb(90, 90, 100), Thickness = 2 }, bagButton)
bagButton.MouseButton1Click:Connect(function()
	local inv = player.PlayerGui:FindFirstChild("InventoryUI")
	local ev = inv and inv:FindFirstChild("Open")
	if ev then ev:Fire() end
end)
RunService.Heartbeat:Connect(function()
	phoneButton.Visible = not isOpen
	bagButton.Visible = not isOpen
end)

back.MouseButton1Click:Connect(goHome)
homeBar.MouseButton1Click:Connect(goHome)
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then setOpen(not isOpen)
	elseif input.KeyCode == Enum.KeyCode.Backspace and isOpen then
		if currentApp then goHome() else setOpen(false) end
	end
end)

-- live data
task.spawn(function()
	while true do
		local t = fmtTime()
		clockSmall.Text, bigClock.Text = t, t
		task.wait(1)
	end
end)
Remotes.DataChanged.OnClientEvent:Connect(function(d)
	data = d
	if isOpen and currentApp and currentApp.id ~= "gps" then APPS.open(currentApp.id) end
end)
Remotes.Notify.OnClientEvent:Connect(function(t, kind)
	table.insert(messages, 1, { time = fmtTime(), text = t, kind = kind })
	if #messages > 40 then table.remove(messages) end
	if isOpen and currentApp and currentApp.id == "messages" then APPS.open("messages") end
end)
