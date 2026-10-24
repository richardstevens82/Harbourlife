-- In-match HUD, inventory screen, results screen and spectating.
--   Vitals (health, shield, oxygen, boost, tether, suit status) bottom-left
--   Weapon, ammo, slots, utility bottom-right
--   Phase / timer / survivors top-centre; kill feed top-right; tactical map top-left
--   Crosshair, hit markers, directional damage, notices, use/reload progress, low-O2 vignette
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.WeaponDefinitions)
local Items = require(Shared.ItemDefinitions)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.ClientState)
local UI = require(script.Parent.UIKit)
local Effects = require(script.Parent.EffectsController)

local HUD = {}
local player = Players.LocalPlayer
local C = UI.Colors
local new = UI.new
local gui: ScreenGui
local refs: any = {}
local matchState: Configuration
local zoneState: Configuration
local spectateIndex = 1
local spectateOptOut = false

local PHASE_TEXT = {
	Waiting = "WAITING FOR PLAYERS", Countdown = "DEPLOYMENT COUNTDOWN", Preparing = "PREPARING DEPLOYMENT", Deploying = "DEPLOYING",
	Active = "BATTLE IN PROGRESS", Final = "FINAL COMBAT PHASE", Ending = "MATCH OVER", Results = "RESULTS",
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function inMatchAlive(): boolean
	return player:GetAttribute("InMatch") == true and player:GetAttribute("Alive") == true
end

-- BUILD ---------------------------------------------------------------------------------------------
-- Small display-font tag floating above a panel's top edge ("// SUIT TELEMETRY").
local function tag(panel: GuiObject, text: string, right: boolean?)
	UI.label(panel, "// " .. text, { Font = UI.Fonts.Display, TextSize = 10, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, -18), TextXAlignment = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left })
end

local function buildVitals()
	local f = UI.panel(gui, { Name = "Vitals", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(300, 150) },
		{ brackets = true })
	tag(f, "SUIT TELEMETRY")
	UI.pad(f, 10)
	UI.list(f, 5)
	local function row(name: string, color: Color3)
		local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16) }, f)
		UI.label(r, name, { Size = UDim2.fromOffset(62, 16), TextSize = 12, TextColor3 = C.Dim, Font = UI.Fonts.Bold })
		local _, set = UI.bar(r, color, { Position = UDim2.fromOffset(64, 2), Size = UDim2.new(1, -64, 0, 12) })
		return set
	end
	refs.setHealth = row("HEALTH", C.Health)
	refs.setShield = row("SHIELD", C.Shield)
	refs.setO2 = row("OXYGEN", C.Oxygen)
	refs.setBoost = row("BOOST", C.Boost)
	refs.suit = UI.label(f, "", { TextSize = 13, Font = UI.Fonts.Bold })
	refs.equip = UI.label(f, "", { TextSize = 13, TextColor3 = C.Dim })
	refs.vitals = f
end

local function buildWeapon()
	local f = UI.panel(gui, { Name = "Weapon", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(300, 150) },
		{ brackets = true })
	tag(f, "WEAPON SYSTEMS", true)
	UI.pad(f, 10)
	refs.weaponName = UI.label(f, "", { Size = UDim2.new(1, 0, 0, 22), TextSize = 18, Font = UI.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Right })
	refs.ammo = UI.label(f, "", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 40), TextSize = 36, Font = UI.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Right })
	local _, setReload, reloadBar = UI.bar(f, C.Accent, { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 4) })
	refs.setReload, refs.reloadBar = setReload, reloadBar.Parent
	refs.reloadBar.Visible = false
	local slots = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 44) }, f)
	UI.list(slots, 6, true)
	refs.slots = {}
	for i = 1, Config.Inventory.WeaponSlots do
		local s = new("Frame", { BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.3, Size = UDim2.new(1 / 3, -4, 1, 0), LayoutOrder = i }, slots)
		UI.corner(s, 4)
		local stroke = UI.stroke(s)
		local l = UI.label(s, i .. "  -", { Size = UDim2.fromScale(1, 1), TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
		refs.slots[i] = { frame = s, label = l, stroke = stroke }
	end
	refs.utility = UI.label(f, "", { Position = UDim2.fromOffset(0, 124), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Right })
	refs.weapon = f
end

local function buildTop()
	local f = UI.panel(gui, { Name = "MatchInfo", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(440, 64) },
		{ brackets = true })
	refs.phase = UI.label(f, "", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Fonts.Bold, TextSize = 16 })
	refs.sub = UI.label(f, "", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 14, TextColor3 = C.Dim, RichText = true })
	refs.top = f
end

local function buildKillFeed()
	local f = new("Frame", { Name = "KillFeed", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(380, 200) }, gui)
	UI.list(f, 4)
	refs.killFeed = f
end

local MAP_R = 95
local function buildMap()
	local f = UI.panel(gui, { Name = "TacticalMap", Position = UDim2.fromOffset(16, 28), Size = UDim2.fromOffset(MAP_R * 2 + 20, MAP_R * 2 + 44) },
		{ brackets = true })
	tag(f, "TACTICAL // ORBIT")
	local disc = new("Frame", { Name = "Disc", BackgroundColor3 = Color3.fromRGB(8, 12, 20), BackgroundTransparency = 0.2, Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(MAP_R * 2, MAP_R * 2), ClipsDescendants = false }, f)
	UI.corner(disc, MAP_R)
	UI.stroke(disc, C.Stroke, 0.6)
	local function ring(color: Color3, thickness: number)
		local r = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 }, disc)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
		new("UIStroke", { Color = color, Thickness = thickness, Transparency = 0.1 }, r)
		return r
	end
	refs.mapZone = ring(C.Storm, 2)
	refs.mapNext = ring(Color3.new(1, 1, 1), 1)
	refs.mapMe = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
		Text = "▲", TextColor3 = C.Accent, Font = UI.Fonts.Bold, TextSize = 14, ZIndex = 5 }, disc)
	refs.mapDisc = disc
	refs.mapInfo = UI.label(f, "", { Position = UDim2.new(0, 10, 1, -28), Size = UDim2.new(1, -20, 0, 20), TextSize = 12, TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Center })
	refs.map = f
	refs.landmarks = {}
end

local function buildCenter()
	-- crosshair
	local ch = new("Frame", { Name = "Crosshair", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40) }, gui)
	refs.cross = {}
	for i, d in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
		local horiz = d.Y == 0
		refs.cross[i] = { dir = d, frame = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Size = horiz and UDim2.fromOffset(7, 2) or UDim2.fromOffset(2, 7) }, ch) }
	end
	new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2) }, ch)
	refs.crosshair = ch
	-- hit marker
	local hm = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40), Text = "✕", TextColor3 = Color3.new(1, 1, 1), TextSize = 28, Font = UI.Fonts.Bold, TextTransparency = 1 }, gui)
	refs.hitmarker = hm
	refs.hitText = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 26, 0.5, -18),
		Size = UDim2.fromOffset(80, 20), Text = "", TextColor3 = C.Orange, TextSize = 16, Font = UI.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1 }, gui)
	-- damage indicators container
	refs.damage = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0) }, gui)
	-- notices
	local nf = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(600, 100) }, gui)
	UI.list(nf, 4).HorizontalAlignment = Enum.HorizontalAlignment.Center
	refs.notices = nf
	-- progress (use item / reload)
	local pf = UI.panel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -140), Size = UDim2.fromOffset(240, 34), Visible = false })
	refs.progLabel = UI.label(pf, "", { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 0, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center })
	local _, setProg = UI.bar(pf, C.Green, { Position = UDim2.fromOffset(10, 20), Size = UDim2.new(1, -20, 0, 6) })
	refs.progress, refs.setProg = pf, setProg
	-- big banner (eliminated / winner / deployed)
	refs.banner = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(900, 60), Text = "", TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Font = UI.Fonts.Display,
		TextSize = 44, TextTransparency = 1 }, gui)
	-- low oxygen / storm vignette
	local grad = new("Frame", { BackgroundColor3 = C.Red, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, gui)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 1),
		NumberSequenceKeypoint.new(0.8, 1), NumberSequenceKeypoint.new(1, 0) }) }, grad)
	refs.vignette = grad
	-- spectate banner
	refs.spectate = UI.panel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(460, 44), Visible = false })
	refs.spectateLabel = UI.label(refs.spectate, "", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, RichText = true })
	-- lobby hint
	refs.lobbyHint = UI.label(gui, "Practice range: shoot the drones  |  M: menu  |  Tab: inventory", { AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(600, 20), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Dim, TextSize = 14 })
end

-- INVENTORY SCREEN -----------------------------------------------------------------------------------
local function itemTooltip(id: string): string
	local def = Items.Get(id)
	if not def then return id end
	if def.kind == "weapon" then
		local w = Weapons.Get(def.weapon)
		return string.format("%s - %s\nDamage %d%s | %d RPM | Mag %d | Range %d\nAmmo: %s | Mobility %d%%", w.name, w.class, w.damage,
			w.pellets > 1 and (" x" .. w.pellets) or "", w.rpm, w.mag, w.range, w.ammo, math.floor(w.mobility * 100))
	end
	return (def.name or id) .. "\n" .. (def.desc or "")
end
HUD.ItemTooltip = itemTooltip

local function buildInventory()
	local f = UI.panel(gui, { Name = "Inventory", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 440),
		Visible = false, ZIndex = 10 }, { brackets = true })
	UI.pad(f, 14)
	UI.title(f, "SUIT INVENTORY")
	refs.invBody = new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -90),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, BorderSizePixel = 0 }, f)
	UI.list(refs.invBody, 6)
	refs.tooltip = UI.label(f, "Hover an item for details.", { Position = UDim2.new(0, 0, 1, -54), Size = UDim2.new(1, 0, 0, 52), TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, TextSize = 13, TextColor3 = C.Dim })
	refs.inventory = f
end

local function refreshInventoryScreen()
	local body = refs.invBody
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local inv = State.Inventory
	if not inv then return end
	local order = 0
	local function row(text: string, color: Color3?, tooltip: string?, actions)
		order += 1
		local r = new("Frame", { BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.35, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = order }, body)
		UI.corner(r, 4)
		UI.label(r, text, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -200, 0, 20), TextColor3 = color or C.Text, TextSize = 14 })
		local x = -8
		for i = #(actions or {}), 1, -1 do
			local a = actions[i]
			UI.button(r, a[1], { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(70, 24), TextSize = 12 }, a[2])
			x -= 76
		end
		if tooltip then
			r.MouseEnter:Connect(function() refs.tooltip.Text = tooltip end)
		end
	end
	local function header(text: string)
		order += 1
		UI.label(body, text, { LayoutOrder = order, TextSize = 13, TextColor3 = C.Accent, Font = UI.Fonts.Bold })
	end
	header("WEAPONS")
	for slot = 1, Config.Inventory.WeaponSlots do
		local w = inv.weapons[slot]
		if w then
			local def = Weapons.Get(w.id)
			row(string.format("[%d] %s  %s  %d/%d  (%s %d)", slot, def.name, string.upper(w.rarity), w.mag, w.magSize, def.ammo, inv.ammo[def.ammo] or 0),
				Items.RarityColor[w.rarity], itemTooltip("weapon:" .. w.id), inv.practice and {} or {
					{ "Equip", function() Remotes.Combat:FireServer({ action = "equip", slot = slot }) end },
					{ "Drop", function() Remotes.Inventory:FireServer({ action = "drop", slot = slot }) end },
				})
		else
			row(string.format("[%d] empty", slot), C.Dim)
		end
	end
	header("BACKPACK")
	local any = false
	for _, id in Items.Consumables do
		local n = inv.items[id] or 0
		if n > 0 then
			any = true
			local def = Items.List[id]
			local acts = { { "Drop", function() Remotes.Inventory:FireServer({ action = "drop", item = id }) end } }
			if def.kind == "consumable" then
				table.insert(acts, 1, { "Use", function() Remotes.Inventory:FireServer({ action = "use", item = id }) end })
			end
			row(string.format("%s  x%d / %d", def.name, n, Config.Inventory.ConsumableStack[id] or 1), C.Text, itemTooltip(id), acts)
		end
	end
	if not any then row("No consumables", C.Dim) end
	header("AMMUNITION")
	local ammoText = {}
	for _, a in { "light", "medium", "heavy", "shells", "energy" } do
		table.insert(ammoText, string.format("%s %d/%d", a, inv.ammo[a] or 0, Config.Inventory.AmmoCap[a]))
	end
	row(table.concat(ammoText, "   "), C.Text)
	header("SUIT")
	local ups = {}
	for id in inv.upgrades do table.insert(ups, Items.List[id] and Items.List[id].name or id) end
	row(string.format("Shield capacity %d   |   Tether charges %d   |   Upgrades: %s", inv.armorMax, inv.tether, #ups > 0 and table.concat(ups, ", ") or "none"), C.Text)
end

function HUD.ToggleInventory(open: boolean?)
	if open == nil then open = not refs.inventory.Visible end
	if open and not State.Inventory then return end
	local isOpen = open == true
	refs.inventory.Visible = isOpen
	if isOpen then refreshInventoryScreen() end
	State.SetModal("inventory", isOpen)
end

-- RESULTS -------------------------------------------------------------------------------------------
local function buildResults()
	local f = UI.panel(gui, { Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 400),
		Visible = false, ZIndex = 20 }, { brackets = true, accent = C.Accent })
	UI.pad(f, 18)
	UI.list(f, 8)
	refs.resTitle = UI.label(f, "", { TextSize = 22, Font = UI.Fonts.Display, Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true })
	UI.new("UITextSizeConstraint", { MaxTextSize = 24 }, refs.resTitle)
	refs.resWinner = UI.label(f, "", { TextSize = 18, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Orange })
	refs.resStats = UI.label(f, "", { TextSize = 17, Size = UDim2.new(1, 0, 0, 150), TextYAlignment = Enum.TextYAlignment.Top, RichText = true })
	refs.resRewards = UI.label(f, "", { TextSize = 17, Size = UDim2.new(1, 0, 0, 50), TextColor3 = C.Green, RichText = true })
	UI.button(f, "RETURN TO LOBBY", { Size = UDim2.new(1, 0, 0, 44) }, function()
		Effects.Play("ui")
		Remotes.Match:FireServer({ action = "returnToLobby" })
		f.Visible = false
		State.SetModal("results", false)
	end)
	refs.results = f
end

local function showResults(d)
	refs.resTitle.Text = d.placement == 1 and "VICTORY - LAST IN ORBIT" or string.format("PLACED #%d OF %d", d.placement, d.total)
	refs.resTitle.TextColor3 = d.placement == 1 and C.Orange or C.Text
	refs.resWinner.Text = d.winner and ("Winner: " .. d.winner) or "No survivors"
	refs.resStats.Text = string.format("Placement  <b>#%d / %d</b>\nEliminations  <b>%d</b>\nDamage dealt  <b>%d</b>\nSurvival time  <b>%s</b>",
		d.placement, d.total, d.kills, d.damage, UI.formatTime(d.survived))
	refs.resRewards.Text = string.format("+%d XP   +%d credits%s", d.xp, d.credits, d.levelUp and ("\n<b>LEVEL UP! Now level " .. tostring(d.level) .. "</b>") or "")
	refs.results.Visible = true
	State.SetModal("results", true)
end

-- FEEDBACK -------------------------------------------------------------------------------------------
function HUD.Notice(text: string, color: Color3?)
	local l = UI.label(refs.notices, text, { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Fonts.Bold,
		TextSize = 18, TextColor3 = color or C.Text, TextStrokeTransparency = 0.6 })
	local kids = {}
	for _, c in refs.notices:GetChildren() do
		if c:IsA("TextLabel") then table.insert(kids, c) end
	end
	if #kids > 3 then kids[1]:Destroy() end
	task.delay(4, function()
		for i = 1, 10 do
			l.TextTransparency = i / 10
			l.TextStrokeTransparency = 0.6 + i * 0.04
			task.wait(0.04)
		end
		l:Destroy()
	end)
end

local function banner(text: string, color: Color3?, seconds: number)
	refs.banner.Text = text
	refs.banner.TextColor3 = color or Color3.new(1, 1, 1)
	refs.banner.TextTransparency = 0
	local my = text
	task.delay(seconds, function()
		if refs.banner.Text ~= my then return end
		for i = 1, 10 do
			refs.banner.TextTransparency = i / 10
			task.wait(0.05)
		end
	end)
end
HUD.Banner = banner

local function hitMarker(amount: number, kill: boolean)
	refs.hitmarker.TextColor3 = kill and C.Red or Color3.new(1, 1, 1)
	refs.hitmarker.TextTransparency = 0
	refs.hitText.Text = (kill and "ELIMINATED  " or "") .. tostring(math.floor(amount))
	refs.hitText.TextTransparency = 0
	Effects.Play(kill and "kill" or "hit")
	local t = os.clock()
	refs.hitAt = t
	task.delay(0.25, function()
		if refs.hitAt == t then refs.hitmarker.TextTransparency = 1 end
	end)
	task.delay(0.9, function()
		if refs.hitAt == t then refs.hitText.TextTransparency = 1 end
	end)
end

local function damageIndicator(from: Vector3?, _amount: number, shield: boolean)
	Effects.Play("damage")
	if not from then
		refs.vignette.BackgroundTransparency = 0.5
		task.delay(0.2, function() refs.vignette.BackgroundTransparency = 1 end)
		return
	end
	local cam = workspace.CurrentCamera.CFrame
	local rel = cam:VectorToObjectSpace(from - cam.Position)
	local angle = math.atan2(rel.X, -rel.Z) -- bearing around the crosshair (0 = in front, shown at top)
	local arrow = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(math.sin(angle) * 120, -math.cos(angle) * 120), Rotation = math.deg(angle), Text = "▲",
		TextColor3 = shield and C.Shield or C.Red, TextSize = 34, Font = UI.Fonts.Display }, refs.damage)
	task.spawn(function()
		task.wait(0.6)
		for i = 1, 10 do
			arrow.TextTransparency = i / 10
			task.wait(0.04)
		end
		arrow:Destroy()
	end)
end

local function killFeed(d)
	local text
	if d.killer then
		text = string.format("<font color=\"#FFB060\">%s</font>  [%s]  %s", d.killer, d.weapon or "?", d.victim)
	else
		text = string.format("%s  <font color=\"#B080FF\">- %s</font>", d.victim, d.cause or "eliminated")
	end
	local f = UI.panel(refs.killFeed, { Size = UDim2.new(1, 0, 0, 26) })
	UI.label(f, text, { Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 20), RichText = true, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right })
	local items = {}
	for _, c in refs.killFeed:GetChildren() do
		if c:IsA("Frame") then table.insert(items, c) end
	end
	if #items > 6 then items[1]:Destroy() end
	task.delay(8, function() if f.Parent then f:Destroy() end end)
end

local progressSerial = 0
local function progress(label: string, seconds: number)
	progressSerial += 1
	local my = progressSerial
	refs.progress.Visible = true
	refs.progLabel.Text = label
	local t0 = os.clock()
	task.spawn(function()
		while progressSerial == my and os.clock() - t0 < seconds do
			refs.setProg((os.clock() - t0) / seconds)
			task.wait()
		end
		if progressSerial == my then refs.progress.Visible = false end
	end)
end

-- PER-FRAME UPDATE -------------------------------------------------------------------------------------
local function updateSpectate()
	local phase = matchState and matchState:GetAttribute("Phase")
	local should = player:GetAttribute("InMatch") == true and player:GetAttribute("Alive") ~= true and (phase == "Active" or phase == "Final" or phase == "Ending")
		and not spectateOptOut
	if not should then
		State.Spectating = nil
		refs.spectate.Visible = false
		return
	end
	-- living combatants: other players plus bots (bots publish their state under ReplicatedStorage.Bots)
	local alive = {}
	local function add(name: string, char: Instance?, kills: number?)
		if char then
			table.insert(alive, { Name = name, Character = char, kills = kills or 0, GetAttribute = function(self, k)
				return k == "Kills" and self.kills or nil
			end })
		end
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Alive") == true and p:GetAttribute("InMatch") == true then add(p.Name, p.Character, p:GetAttribute("Kills")) end
	end
	local botFolder = ReplicatedStorage:FindFirstChild("Bots")
	for _, cfg in botFolder and botFolder:GetChildren() or {} do
		local ref = cfg:FindFirstChild("Character") :: ObjectValue?
		if cfg:GetAttribute("Alive") == true and cfg:GetAttribute("InMatch") == true and ref then add(cfg.Name, ref.Value, cfg:GetAttribute("Kills")) end
	end
	table.sort(alive, function(a, b) return a.Name < b.Name end)
	if #alive == 0 then
		State.Spectating = nil
		refs.spectate.Visible = false
		return
	end
	spectateIndex = ((spectateIndex - 1) % #alive) + 1
	State.Spectating = alive[spectateIndex] :: any
	refs.spectate.Visible = true
	refs.spectateLabel.Text = string.format("SPECTATING <b>%s</b>  (%d kills)   [Q / E] switch   [Backspace] lobby", State.Spectating.Name,
		State.Spectating:GetAttribute("Kills") or 0)
end

local function updateMap()
	local zs = zoneState
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local focus = State.Spectating and State.Spectating.Character and State.Spectating.Character:FindFirstChild("HumanoidRootPart") or root
	local scale = MAP_R / Config.Arena.HardRadius
	local function toMap(p: Vector3): UDim2
		return UDim2.fromOffset(MAP_R + p.X * scale, MAP_R + p.Z * scale)
	end
	if zs and zs:GetAttribute("Active") then
		local c, r = zs:GetAttribute("Center") or Vector3.zero, zs:GetAttribute("Radius") or 0
		refs.mapZone.Visible = true
		refs.mapZone.Position = toMap(c)
		refs.mapZone.Size = UDim2.fromOffset(r * 2 * scale, r * 2 * scale)
		local nc, nr = zs:GetAttribute("NextCenter"), zs:GetAttribute("NextRadius")
		refs.mapNext.Visible = nc ~= nil and zs:GetAttribute("Phase") == "waiting"
		if nc then
			refs.mapNext.Position = toMap(nc)
			refs.mapNext.Size = UDim2.fromOffset(nr * 2 * scale, nr * 2 * scale)
		end
		if focus then
			local off = c - (focus :: BasePart).Position
			local dist = math.max(off.Magnitude - r, 0)
			refs.mapInfo.Text = dist > 0 and string.format("STORM: %dm outside  |  safe zone %s %dm", math.floor(dist), off.Y > 0 and "above" or "below",
				math.floor(math.abs(off.Y))) or string.format("Inside safe zone  |  centre %s %dm", off.Y > 0 and "above" or "below", math.floor(math.abs(off.Y)))
			refs.mapInfo.TextColor3 = dist > 0 and C.Storm or C.Dim
		end
	else
		refs.mapZone.Visible, refs.mapNext.Visible = false, false
		refs.mapInfo.Text = "Arena radius " .. Config.Arena.HardRadius .. "m"
	end
	if focus then
		local p = (focus :: BasePart).Position
		refs.mapMe.Position = toMap(p)
		local look = workspace.CurrentCamera.CFrame.LookVector
		refs.mapMe.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
	-- landmarks (tagged FinalZone markers carry readable labels)
	if #refs.landmarks == 0 then
		for _, m in CollectionService:GetTagged("FinalZone") do
			if m:IsA("BasePart") then
				local dot = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(80, 12),
					Position = toMap(m.Position), Text = "• " .. (m:GetAttribute("Label") or ""), TextColor3 = C.Dim, TextSize = 9,
					Font = UI.Fonts.Body, ZIndex = 4 }, refs.mapDisc)
				table.insert(refs.landmarks, dot)
			end
		end
	end
end

local function update()
	local playing = inMatchAlive()
	local phase = matchState and matchState:GetAttribute("Phase") or "Waiting"
	local inv = State.Inventory
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	refs.vitals.Visible = playing
	refs.map.Visible = playing or State.Spectating ~= nil or refs.mapBig == true
	refs.weapon.Visible = inv ~= nil and (playing or inv.practice)
	refs.crosshair.Visible = (inv ~= nil) and not State.UIOpen and not State.Spectating and hum ~= nil and hum.Health > 0
	refs.lobbyHint.Visible = not playing and not State.Spectating and not State.UIOpen
	-- vitals
	if playing and hum then
		local shield, shieldMax = player:GetAttribute("Armor") or 0, player:GetAttribute("ArmorMax") or 0
		local o2 = player:GetAttribute("O2") or 100
		refs.setHealth(hum.Health / hum.MaxHealth, tostring(math.ceil(hum.Health)))
		refs.setShield(shieldMax > 0 and shield / shieldMax or 0, shieldMax > 0 and string.format("%d/%d", shield, shieldMax) or "NO PLATING")
		refs.setO2(o2 / Config.Oxygen.Max, string.format("%d%%", math.floor(o2)))
		refs.setBoost(State.Boost / math.max(State.BoostMax, 1), "")
		local pressurized = player:GetAttribute("Pressurized") == true
		local status
		if player:GetAttribute("Hypoxia") then status, refs.suit.TextColor3 = "HYPOXIA - SUIT FAILING", C.Red
		elseif o2 <= 0 then status, refs.suit.TextColor3 = "OXYGEN DEPLETED - RESERVE AIR", C.Red
		elseif player:GetAttribute("InStorm") then status, refs.suit.TextColor3 = "RADIATION EXPOSURE", C.Storm
		elseif pressurized then status, refs.suit.TextColor3 = "PRESSURISED - O2 RECHARGING", C.Green
		else status, refs.suit.TextColor3 = "VACUUM - SUIT ON RESERVE O2", C.Text end
		refs.suit.Text = status
		local util = State.SelectedUtility == "tether" and "TETHER" or "PULSE CHARGE"
		refs.equip.Text = string.format("TETHER x%d   PULSE x%d   [Z] %s", player:GetAttribute("TetherCharges") or 0, inv and inv.items.grenade or 0, util)
		local low = o2 < Config.Oxygen.WarnAt or hum.Health < 30
		refs.vignette.BackgroundTransparency = low and (0.75 + math.sin(os.clock() * 5) * 0.12) or 1
	elseif refs.vignette.BackgroundTransparency < 1 and not playing then
		refs.vignette.BackgroundTransparency = 1
	end
	-- weapon
	if inv then
		local w = inv.active > 0 and inv.weapons[inv.active] or nil
		if w then
			local def = Weapons.Get(w.id)
			refs.weaponName.Text = def.name
			refs.weaponName.TextColor3 = Items.RarityColor[w.rarity] or C.Text
			refs.ammo.Text = string.format("%d <font size=\"20\" color=\"#8C9BAF\">/ %s</font>", w.mag, inv.practice and "∞" or tostring(inv.ammo[def.ammo] or 0))
			refs.ammo.RichText = true
		else
			refs.weaponName.Text, refs.ammo.Text = "UNARMED", ""
		end
		for i, s in refs.slots do
			local sw = inv.weapons[i]
			s.label.Text = sw and string.format("%d  %s", i, Weapons.Get(sw.id).name) or (i .. "  -")
			s.label.TextColor3 = sw and (Items.RarityColor[sw.rarity] or C.Text) or C.Dim
			s.stroke.Transparency = inv.active == i and 0 or 0.7
		end
		refs.utility.Text = inv.practice and "PRACTICE KIT - infinite reserve ammo" or "[4] heal  [5] shield  [6] O2   [V] melee"
	end
	-- crosshair spread
	local gap = State.Aiming and 4 or 9
	for _, c in refs.cross do
		c.frame.Position = UDim2.new(0.5, c.dir.X * gap, 0.5, c.dir.Y * gap)
	end
	-- top info
	local phaseText = PHASE_TEXT[phase] or phase
	refs.phase.Text = phaseText
	refs.phase.TextColor3 = phase == "Final" and C.Orange or C.Text
	local alive = matchState and matchState:GetAttribute("AliveCount") or 0
	local endsAt = matchState and matchState:GetAttribute("PhaseEndsAt") or 0
	if phase == "Active" or phase == "Final" then
		local zs = zoneState
		local nt = zs and zs:GetAttribute("NextTime") or 0
		local zp = zs and zs:GetAttribute("Phase") or ""
		local zText = nt > 0 and string.format("%s %s", zp == "shrinking" and "STORM CLOSING" or "STORM IN", UI.formatTime(nt - serverNow())) or "FINAL ZONE"
		refs.sub.Text = string.format("<b>%d</b> IN ORBIT   |   <font color=\"#C08CFF\">%s</font>   |   KILLS <b>%d</b>", alive, zText, player:GetAttribute("Kills") or 0)
	elseif phase == "Waiting" then
		local q, minP = matchState:GetAttribute("Queued") or 0, matchState:GetAttribute("MinPlayers") or 2
		local bots = matchState:GetAttribute("Bots") or 0
		refs.sub.Text = string.format("%d / %d ready%s   |   %s", q, minP, bots > 0 and string.format(" + %d bots", bots) or "",
			player:GetAttribute("Queued") and "You are queued" or "Not queued - open menu (M) and press PLAY")
	elseif endsAt > 0 then
		refs.sub.Text = string.format("%s   |   %d ready", UI.formatTime(endsAt - serverNow()), (matchState:GetAttribute("Queued") :: number?) or 0)
	else
		refs.sub.Text = player:GetAttribute("InMatch") and "" or "Match in progress - you will join the next one"
	end
	updateSpectate()
	if refs.map.Visible then updateMap() end
end

function HUD.Start()
	gui = new("ScreenGui", { Name = "ZG_HUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local scale = new("UIScale", {}, gui)
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.6, 1.2)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	buildVitals()
	buildWeapon()
	buildTop()
	buildKillFeed()
	buildMap()
	buildCenter()
	buildInventory()
	buildResults()
	gui.Parent = player:WaitForChild("PlayerGui")
	matchState = ReplicatedStorage:WaitForChild("MatchState") :: Configuration
	zoneState = ReplicatedStorage:WaitForChild("ZoneState") :: Configuration

	State.Notice:Connect(HUD.Notice)
	State.Hit:Connect(hitMarker)
	State.Damaged:Connect(damageIndicator)
	State.KillFeed:Connect(killFeed)
	State.Results:Connect(showResults)
	State.InventoryChanged:Connect(function()
		if refs.inventory.Visible then refreshInventoryScreen() end
	end)
	State.UseProgress:Connect(progress)
	State.Reloading:Connect(function(seconds) progress("RELOADING", seconds) end)
	State.Eliminated:Connect(function(d)
		banner(string.format("ELIMINATED  #%d", d.placement), C.Red, 3)
		HUD.Notice(d.by and ("Eliminated by " .. d.by) or ("Lost to " .. tostring(d.cause)), C.Red)
		HUD.ToggleInventory(false)
	end)

	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then return end
		if io.KeyCode == State.Bindings.Inventory or io.KeyCode == Enum.KeyCode.ButtonSelect then
			HUD.ToggleInventory()
		elseif io.KeyCode == State.Bindings.Map then
			refs.mapBig = not refs.mapBig
			local s = refs.map:FindFirstChildOfClass("UIScale") or new("UIScale", {}, refs.map)
			s.Scale = refs.mapBig and 2 or 1
		elseif State.Spectating and (io.KeyCode == Enum.KeyCode.Q or io.KeyCode == Enum.KeyCode.E) then
			spectateIndex += io.KeyCode == Enum.KeyCode.E and 1 or -1
		elseif io.KeyCode == Enum.KeyCode.Backspace and player:GetAttribute("InMatch") and not player:GetAttribute("Alive") then
			spectateOptOut = not spectateOptOut
		end
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		spectateOptOut = false
		if not player:GetAttribute("InMatch") then
			HUD.ToggleInventory(false)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return HUD
