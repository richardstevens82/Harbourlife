-- Inventory menu (press I, or the Bag app on the phone). Items are grouped by category, with a tab per
-- category, a search box and a detail panel, plus a Skills & Stats page. Display only: the server owns
-- the inventory and sends it with DataChanged.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Items = require(Shared.ItemDefinitions)
local Categories = require(Shared.ItemCategories)
local Config = require(Shared.Config)
local SkillDefs = require(Shared.SkillDefinitions)
local Jobs = require(Shared.JobDefinitions)

local player = Players.LocalPlayer
local rgb = Color3.fromRGB
local BG, PANEL, PANEL2, TEXT, DIM, ACCENT = rgb(20, 24, 32), rgb(32, 38, 50), rgb(44, 52, 68), rgb(240, 242, 246), rgb(150, 160, 178), rgb(70, 150, 255)
local W, H = 720, 470

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryUI"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local openEvent = Instance.new("BindableEvent") -- fired by the phone's Bag app
openEvent.Name = "Open"; openEvent.Parent = gui

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
local function text(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = TEXT, Font = Enum.Font.Gotham, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left }, parent)
	for k, v in props do (t :: any)[k] = v end
	return t
end

local window = new("Frame", { Size = UDim2.fromOffset(W, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = BG }, gui)
corner(window, 14)
new("UIStroke", { Color = rgb(60, 70, 90), Thickness = 2 }, window)
local scale = new("UIScale", {}, window)
local function fit()
	local vp = workspace.CurrentCamera.ViewportSize
	scale.Scale = math.min(1, (vp.X - 20) / W, (vp.Y - 20) / H)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
fit()

text(window, { Text = "🎒  INVENTORY", Font = Enum.Font.GothamBlack, TextSize = 20, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(200, 30) })
local slots = text(window, { TextColor3 = DIM, Position = UDim2.new(1, -250, 0, 12), Size = UDim2.fromOffset(190, 30), TextXAlignment = Enum.TextXAlignment.Right })
local search = new("TextBox", { PlaceholderText = "🔍  Search items…", Text = "", ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 14,
	TextColor3 = TEXT, PlaceholderColor3 = DIM, BackgroundColor3 = PANEL, Position = UDim2.fromOffset(200, 13), Size = UDim2.fromOffset(240, 28),
	TextXAlignment = Enum.TextXAlignment.Left }, window)
corner(search, 6)
new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, search)
local close = new("TextButton", { Text = "✕", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = TEXT, BackgroundColor3 = rgb(170, 50, 55),
	Position = UDim2.new(1, -46, 0, 10), Size = UDim2.fromOffset(34, 34) }, window)
corner(close, 8)

local sidebar = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 54), Size = UDim2.new(0, 160, 1, -66), BackgroundTransparency = 1,
	ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, window)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
local content = new("ScrollingFrame", { Position = UDim2.fromOffset(182, 54), Size = UDim2.new(1, -182 - 200, 1, -66), BackgroundColor3 = PANEL,
	ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, window)
corner(content, 10)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, content)
new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, content)
local detail = new("Frame", { Position = UDim2.new(1, -190, 0, 54), Size = UDim2.new(0, 178, 1, -66), BackgroundColor3 = PANEL }, window)
corner(detail, 10)

local data
local tab = "all"
local selected: string? = nil

local function categoryOf(id: string): string
	local c = Items[id] and Items[id].category
	return (c and Categories.info[c]) and c or "general"
end

local function itemName(id) return Items[id] and Items[id].name or id end

-- items the player holds, filtered by the search box, grouped by category
local function grouped()
	local q = string.lower(search.Text)
	local groups, total = {}, 0
	for id, n in (data and data.inventory or {}) do
		if q == "" or string.find(string.lower(itemName(id)), q, 1, true) then
			local c = categoryOf(id)
			groups[c] = groups[c] or {}
			table.insert(groups[c], { id = id, n = n })
			total += 1
		end
	end
	for _, list in groups do table.sort(list, function(a, b) return itemName(a.id) < itemName(b.id) end) end
	return groups, total
end

local render

local function tabButton(id, label, count, order)
	local active = tab == id
	local b = new("TextButton", { Text = "", AutoButtonColor = true, BackgroundColor3 = active and ACCENT or PANEL,
		Size = UDim2.new(1, -6, 0, 34), LayoutOrder = order }, sidebar)
	corner(b, 8)
	text(b, { Text = label, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -44, 1, 0), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
		Font = active and Enum.Font.GothamBold or Enum.Font.Gotham })
	if count then
		text(b, { Text = tostring(count), TextColor3 = active and TEXT or DIM, Position = UDim2.new(1, -40, 0, 0), Size = UDim2.fromOffset(32, 34),
			TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12 })
	end
	b.MouseButton1Click:Connect(function() tab = id; render() end)
end

local function tile(parent, id, n)
	local cat = Categories.get(categoryOf(id))
	local b = new("TextButton", { Text = "", BackgroundColor3 = PANEL2, AutoButtonColor = true }, parent)
	corner(b, 8)
	if selected == id then new("UIStroke", { Color = ACCENT, Thickness = 2 }, b) end
	local icon = new("TextLabel", { Text = cat.icon, TextSize = 26, BackgroundColor3 = cat.color, Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 46), Font = Enum.Font.GothamBold, TextColor3 = TEXT }, b)
	corner(icon, 6)
	text(b, { Text = itemName(id), Position = UDim2.fromOffset(6, 54), Size = UDim2.new(1, -12, 0, 30), TextSize = 11, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
	local badge = text(b, { Text = "x" .. n, Font = Enum.Font.GothamBold, TextSize = 12, BackgroundTransparency = 0.2, BackgroundColor3 = rgb(0, 0, 0),
		Position = UDim2.new(1, -36, 0, 8), Size = UDim2.fromOffset(30, 18), TextXAlignment = Enum.TextXAlignment.Center })
	corner(badge, 9)
	b.MouseButton1Click:Connect(function() selected = id; render() end)
end

local function section(cat: string, list, order)
	local info = Categories.get(cat)
	local s = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, content)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	local head = new("Frame", { BackgroundColor3 = info.color, BackgroundTransparency = 0.75, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 }, s)
	corner(head, 6)
	text(head, { Text = string.format("%s  %s  (%d)", info.icon, string.upper(info.name), #list), Font = Enum.Font.GothamBold, TextSize = 13,
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0) })
	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, s)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(92, 92), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for _, e in list do tile(grid, e.id, e.n) end
end

local function statsPage()
	local d = data
	local need = math.floor(Config.XpBase * d.level ^ Config.XpExponent)
	local function line(t, size, color, bold)
		text(content, { Text = t, TextSize = size or 14, TextColor3 = color or TEXT, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
			Size = UDim2.new(1, 0, 0, (size or 14) + 8), TextWrapped = true })
	end
	line("📊  SKILLS & STATS", 16, TEXT, true)
	line(string.format("Level %d   (%d / %d XP)", d.level, d.xp, need), 15, TEXT, true)
	local bar = new("Frame", { BackgroundColor3 = PANEL2, Size = UDim2.new(1, 0, 0, 10) }, content)
	corner(bar, 5)
	local fill = new("Frame", { BackgroundColor3 = ACCENT, Size = UDim2.new(math.clamp(d.xp / math.max(need, 1), 0, 1), 0, 1, 0) }, bar)
	corner(fill, 5)
	line(string.format("Job: %s", Jobs[d.job] and Jobs[d.job].name or d.job))
	line(string.format("Cash $%d    Bank $%d", d.cash, d.bank))
	line(string.format("Reputation: %d", d.reputation or 0))
	line("SKILLS", 14, DIM, true)
	local any = false
	for id, def in SkillDefs do
		local s = d.skills and d.skills[id]
		if s then any = true; line(string.format("%s   Lv %d", def.name, s.level or 0)) end
	end
	if not any then line("No skills trained yet. Jobs train skills.", 13, DIM) end
end

local function renderDetail()
	clear(detail)
	local n = selected and data and data.inventory[selected]
	if not n then
		text(detail, { Text = "Select an item to see its details.", TextColor3 = DIM, TextWrapped = true, Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 0, 60), TextYAlignment = Enum.TextYAlignment.Top })
		return
	end
	local id = selected :: string
	local def = Items[id]
	local cat = Categories.get(categoryOf(id))
	local icon = new("TextLabel", { Text = cat.icon, TextSize = 48, BackgroundColor3 = cat.color, Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 96), TextColor3 = TEXT, Font = Enum.Font.GothamBold }, detail)
	corner(icon, 10)
	local y = 116
	local function line(t, size, color, bold)
		text(detail, { Text = t, TextSize = size, TextColor3 = color, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
			Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, size + 10), TextWrapped = true })
		y += size + 12
	end
	line(def and def.name or id, 16, TEXT, true)
	line(cat.name, 13, cat.color, true)
	line("Quantity: " .. n, 13, TEXT)
	if def then
		line(string.format("Value: $%d each", def.price), 13, TEXT)
		line(string.format("Total: $%d", def.price * n), 13, TEXT)
		line(string.format("Max stack: %d", def.stack or Config.MaxStack), 12, DIM)
	end
end

function render()
	if not data then return end
	local groups, total = grouped()
	local used = 0
	for _ in data.inventory do used += 1 end
	slots.Text = string.format("%d / %d slots", used, Config.InventorySlots)

	clear(sidebar)
	tabButton("all", "🗂  All items", total, 0)
	for i, cat in Categories.order do
		if groups[cat] then tabButton(cat, Categories.info[cat].icon .. "  " .. Categories.info[cat].name, #groups[cat], i) end
	end
	tabButton("stats", "📊  Skills & Stats", nil, 100)
	if tab ~= "all" and tab ~= "stats" and not groups[tab] then tab = "all" end

	clear(content)
	if tab == "stats" then
		statsPage()
	else
		local order = 0
		for _, cat in Categories.order do
			if groups[cat] and (tab == "all" or tab == cat) then
				order += 1
				section(cat, groups[cat], order)
			end
		end
		if order == 0 then
			text(content, { Text = search.Text ~= "" and "No items match your search." or "Your inventory is empty. Visit the shops in Harbour Mall!",
				TextColor3 = DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) })
		end
	end
	renderDetail()
end

local function setOpen(open: boolean)
	gui.Enabled = open
	if open then render() end
end

Remotes.DataChanged.OnClientEvent:Connect(function(d)
	data = d
	if gui.Enabled then render() end
end)
search:GetPropertyChangedSignal("Text"):Connect(function() if gui.Enabled then render() end end)
close.MouseButton1Click:Connect(function() setOpen(false) end)
openEvent.Event:Connect(function() setOpen(true) end)
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.I then setOpen(not gui.Enabled) end
end)
