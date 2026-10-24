-- Procedural construction kit: reusable functions for rooms, corridors, octagonal habitat tubes,
-- airlocks, solar arrays, crates, lights, signs and gameplay markers. All builders use this so the
-- station, ship and wrecks share one consistent visual language and one scale.
--
-- Scale reference: a Roblox character is ~5 studs tall. Corridors are >= 12 x 12 interior, doors
-- >= 8 x 9, so a floating player can pass in any orientation.
local CollectionService = game:GetService("CollectionService")

local Kit = {}

Kit.Palette = {
	Hull = Color3.fromRGB(150, 155, 165),
	HullLight = Color3.fromRGB(190, 194, 200),
	HullDark = Color3.fromRGB(68, 72, 80),
	Gunmetal = Color3.fromRGB(46, 49, 56),
	Interior = Color3.fromRGB(176, 180, 186),
	InteriorDark = Color3.fromRGB(96, 101, 110),
	Deck = Color3.fromRGB(84, 88, 96),
	Blue = Color3.fromRGB(45, 125, 255),
	BlueGlow = Color3.fromRGB(110, 190, 255),
	Orange = Color3.fromRGB(255, 128, 30),
	Red = Color3.fromRGB(220, 50, 40),
	Green = Color3.fromRGB(70, 200, 110),
	Glass = Color3.fromRGB(120, 170, 220),
	Solar = Color3.fromRGB(30, 70, 170),
}
local P = Kit.Palette

Kit.Stats = { parts = 0 }
-- Navigation registry: every hollow space the kit builds (rooms, corridors, tubes, airlocks), with its
-- openings. NavGraph turns this into the bot navigation graph after the world is built.
Kit.NavSpaces = {} :: { any }

local DEFAULTS = {
	Anchored = true,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	Material = Enum.Material.Metal,
	Color = P.Hull,
}

-- Generic part. `props` may include any Part property plus `Parent`.
function Kit.part(parent: Instance, props): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className)
	for k, v in DEFAULTS do
		(p :: any)[k] = v
	end
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	Kit.Stats.parts += 1
	return p
end

function Kit.model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.folder(name: string, parent: Instance): Folder
	local f = parent:FindFirstChild(name) or Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f :: Folder
end

function Kit.light(part: BasePart, color: Color3?, range: number?, brightness: number?, shadows: boolean?)
	local l = Instance.new("PointLight")
	l.Color = color or Color3.fromRGB(220, 230, 255)
	l.Range = range or 30
	l.Brightness = brightness or 1.2
	l.Shadows = shadows or false
	l.Parent = part
	return l
end

-- Neon strip with an attached light (light optional).
function Kit.strip(parent: Instance, cf: CFrame, size: Vector3, color: Color3?, withLight: boolean?, range: number?)
	local p = Kit.part(parent, {
		Name = "LightStrip", CFrame = cf, Size = size, Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(215, 230, 255), CanCollide = false, CastShadow = false,
	})
	if withLight then Kit.light(p, color, range or 28, 0.9) end
	return p
end

-- Wall in the local XY plane of `cf` (thickness along local Z), with one optional rectangular hole.
-- hole = { w, h, x?, y? } in wall-local studs.
function Kit.wall(parent: Instance, cf: CFrame, w: number, h: number, t: number, hole, props)
	props = props or {}
	local function piece(x0, x1, y0, y1)
		if x1 - x0 < 0.05 or y1 - y0 < 0.05 then return end
		local p = table.clone(props)
		p.Size = Vector3.new(x1 - x0, y1 - y0, t)
		p.CFrame = cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0)
		p.Name = p.Name or "Wall"
		Kit.part(parent, p)
	end
	if not hole then
		piece(-w / 2, w / 2, -h / 2, h / 2)
		return
	end
	local hx, hy = hole.x or 0, hole.y or 0
	local x0, x1 = math.max(hx - hole.w / 2, -w / 2), math.min(hx + hole.w / 2, w / 2)
	local y0, y1 = math.max(hy - hole.h / 2, -h / 2), math.min(hy + hole.h / 2, h / 2)
	piece(-w / 2, x0, -h / 2, h / 2) -- left
	piece(x1, w / 2, -h / 2, h / 2) -- right
	piece(x0, x1, -h / 2, y0) -- below
	piece(x0, x1, y1, h / 2) -- above
end

-- Orientation of each face wall so that local Z is the outward normal.
local FACE_ROT = {
	["+X"] = CFrame.Angles(0, math.rad(90), 0),
	["-X"] = CFrame.Angles(0, math.rad(-90), 0),
	["+Y"] = CFrame.Angles(math.rad(-90), 0, 0),
	["-Y"] = CFrame.Angles(math.rad(90), 0, 0),
	["+Z"] = CFrame.new(),
	["-Z"] = CFrame.Angles(0, math.rad(180), 0),
}
Kit.FaceRot = FACE_ROT

-- Point on the centre of a room face (for attaching corridors/airlocks).
function Kit.faceCFrame(cf: CFrame, size: Vector3, face: string, wallT: number?): CFrame
	local t = wallT or 0
	local axis = string.sub(face, 2, 2)
	local sign = string.sub(face, 1, 1) == "+" and 1 or -1
	local half = (axis == "X" and size.X or axis == "Y" and size.Y or size.Z) / 2 + t
	local off = axis == "X" and Vector3.new(sign * half, 0, 0) or axis == "Y" and Vector3.new(0, sign * half, 0)
		or Vector3.new(0, 0, sign * half)
	return cf * CFrame.new(off) * FACE_ROT[face]
end

-- Hollow box room. size is the INTERIOR size. opts:
--   wall (thickness, default 2), openings = { ["+X"] = {w,h,x,y} | true (fully open) , ... },
--   color, interiorColor, material, lights (default true), trim (default true),
--   pressurized (zone id string or nil), name, deck (bool: darker -Y face)
function Kit.room(parent: Instance, cf: CFrame, size: Vector3, opts)
	opts = opts or {}
	local t = opts.wall or 2
	local m = Kit.model(opts.name or "Room", parent)
	local openings = opts.openings or {}
	local outer = { Color = opts.color or P.Hull, Material = opts.material or Enum.Material.Metal }
	local dims = {
		["+X"] = { size.Z + 2 * t, size.Y + 2 * t, size.X },
		["-X"] = { size.Z + 2 * t, size.Y + 2 * t, size.X },
		["+Y"] = { size.X, size.Z + 2 * t, size.Y },
		["-Y"] = { size.X, size.Z + 2 * t, size.Y },
		["+Z"] = { size.X, size.Y, size.Z },
		["-Z"] = { size.X, size.Y, size.Z },
	}
	for face, d in dims do
		local o = openings[face]
		if o ~= true then
			local wcf = Kit.faceCFrame(cf, size, face, t / 2)
			local props = table.clone(outer)
			if face == "-Y" and opts.deck then props.Color = P.Deck end
			Kit.wall(m, wcf, d[1], d[2], t, o, props)
		end
	end
	-- Interior detailing: light strips along the ceiling edges plus a panel light.
	if opts.trim ~= false and size.X >= 10 and size.Z >= 10 then
		local stripLen = math.max(size.Z - 4, 2)
		for _, sx in { -1, 1 } do
			Kit.strip(m, cf * CFrame.new(sx * (size.X / 2 - 0.3), size.Y / 2 - 0.3, 0), Vector3.new(0.4, 0.4, stripLen),
				opts.stripColor, false)
		end
	end
	if opts.lights ~= false then
		local lp = Kit.part(m, {
			Name = "CeilingLight", CFrame = cf * CFrame.new(0, size.Y / 2 - 0.25, 0),
			Size = Vector3.new(math.min(size.X * 0.4, 10), 0.3, math.min(size.Z * 0.4, 10)),
			Material = Enum.Material.Neon, Color = opts.lightColor or Color3.fromRGB(225, 235, 255), CanCollide = false,
		})
		Kit.light(lp, opts.lightColor, math.clamp(math.max(size.X, size.Z) * 0.9, 24, 60), 1.1)
	end
	if opts.pressurized then
		Kit.zone(m, cf, size, opts.pressurized)
	end
	table.insert(Kit.NavSpaces, { cf = cf, size = size, openings = openings, wall = t, model = m })
	return m
end

-- Straight corridor between two points (ends open). Returns model and its CFrame.
function Kit.corridor(parent: Instance, a: Vector3, b: Vector3, opts)
	opts = opts or {}
	local w, h = opts.width or 12, opts.height or 12
	local dir = b - a
	local up = math.abs(dir.Unit.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up)
	local o = table.clone(opts)
	o.name = opts.name or "Corridor"
	o.openings = { ["+Z"] = true, ["-Z"] = true }
	o.deck = true
	local m = Kit.room(parent, cf, Vector3.new(w, h, dir.Magnitude), o)
	-- Structural rib frames every ~16 studs around the OUTSIDE of the hull (four bars, open middle).
	local len = dir.Magnitude
	local n = math.floor(len / 16)
	local t = opts.wall or 2
	local ow, oh = w + 2 * t, h + 2 * t
	for i = 1, n - 1 do
		local rcf = cf * CFrame.new(0, 0, -len / 2 + i * (len / n))
		for _, s in { -1, 1 } do
			Kit.part(m, { Name = "Rib", CFrame = rcf * CFrame.new(0, s * (oh / 2 + 0.6), 0), Size = Vector3.new(ow + 2.4, 1.2, 1.4), Color = P.HullDark })
			Kit.part(m, { Name = "Rib", CFrame = rcf * CFrame.new(s * (ow / 2 + 0.6), 0, 0), Size = Vector3.new(1.2, oh, 1.4), Color = P.HullDark })
		end
	end
	return m, cf
end

-- Hollow octagonal tube along local Z. radius = inner apothem. caps: { front = hole|true|nil, back = ... }
-- (true = open end, table = door hole {w,h}, nil = closed cap)
function Kit.octTube(parent: Instance, cf: CFrame, radius: number, length: number, opts)
	opts = opts or {}
	local t = opts.wall or 2
	local m = Kit.model(opts.name or "Tube", parent)
	local panelW = 2 * (radius + t) * math.tan(math.rad(22.5)) + 0.2
	for i = 0, 7 do
		local rot = CFrame.Angles(0, 0, math.rad(i * 45 + 22.5))
		local col = opts.color or P.Hull
		if i == 2 or i == 5 then col = opts.accentColor or col end
		Kit.part(m, {
			Name = "HullPanel", CFrame = cf * rot * CFrame.new(0, -(radius + t / 2), 0),
			Size = Vector3.new(panelW, t, length), Color = col, Material = opts.material or Enum.Material.Metal,
		})
	end
	-- Exterior ring trims
	local rings = opts.rings or math.max(math.floor(length / 28), 1)
	for r = 0, rings do
		local z = -length / 2 + r * (length / rings)
		for i = 0, 7 do
			local rot = CFrame.Angles(0, 0, math.rad(i * 45 + 22.5))
			Kit.part(m, {
				Name = "Ring", CFrame = cf * CFrame.new(0, 0, z) * rot * CFrame.new(0, -(radius + t + 0.6), 0),
				Size = Vector3.new(panelW + 1.2, 1.2, 2.2), Color = P.HullDark,
			})
		end
	end
	-- Caps (square plates covering the octagon cross-section, with optional door)
	local capSize = 2 * (radius + t)
	for _, side in { "front", "back" } do
		local c = opts.caps and opts.caps[side]
		if c ~= true then
			local z = side == "front" and -length / 2 - t / 2 or length / 2 + t / 2
			Kit.wall(m, cf * CFrame.new(0, 0, z), capSize, capSize, t, c, { Color = P.HullDark, Name = "Cap" })
		end
	end
	-- Interior: deck plating band on the lower face plus a lit ceiling strip
	if opts.interior ~= false then
		Kit.part(m, { Name = "Deck", CFrame = cf * CFrame.new(0, -radius + 0.15, 0), Size = Vector3.new(panelW, 0.3, length - 2),
			Color = P.Deck, Material = Enum.Material.DiamondPlate })
		local s = Kit.strip(m, cf * CFrame.new(0, radius - 0.3, 0), Vector3.new(1.4, 0.3, length - 4), nil, false)
		local step = 30
		for z = -length / 2 + step / 2, length / 2 - step / 2, step do
			local lp = Kit.part(m, { Name = "Lamp", CFrame = cf * CFrame.new(0, radius - 0.6, z), Size = Vector3.new(2, 0.4, 2),
				Material = Enum.Material.Neon, Color = Color3.fromRGB(225, 235, 255), CanCollide = false })
			Kit.light(lp, nil, 34, 1)
		end
		local _ = s
	end
	if opts.pressurized then
		Kit.zone(m, cf, Vector3.new(radius * 2, radius * 2, length), opts.pressurized)
	end
	local caps = opts.caps or {}
	table.insert(Kit.NavSpaces, { cf = cf, size = Vector3.new(radius * 2, radius * 2, length), wall = t, model = m, tube = true,
		openings = { ["-Z"] = caps.front, ["+Z"] = caps.back } })
	return m
end

-- Window: glass pane with a frame, placed in the plane of cf (local Z normal).
function Kit.window(parent: Instance, cf: CFrame, w: number, h: number)
	Kit.part(parent, { Name = "Window", CFrame = cf, Size = Vector3.new(w, h, 0.6), Material = Enum.Material.Glass,
		Color = P.Glass, Transparency = 0.55, CastShadow = false })
	for _, s in { { 0, h / 2 + 0.4, w + 1.6, 0.8 }, { 0, -h / 2 - 0.4, w + 1.6, 0.8 }, { w / 2 + 0.4, 0, 0.8, h }, { -w / 2 - 0.4, 0, 0.8, h } } do
		Kit.part(parent, { Name = "Frame", CFrame = cf * CFrame.new(s[1], s[2], 0), Size = Vector3.new(s[3], s[4], 1.2), Color = P.HullDark })
	end
end

-- Solar array: truss boom with two wings of blue cells. cf: base of the boom, boom along local X.
function Kit.solarArray(parent: Instance, cf: CFrame, boomLen: number, wingW: number, wingH: number)
	local m = Kit.model("SolarArray", parent)
	Kit.part(m, { Name = "Boom", CFrame = cf * CFrame.new(boomLen / 2, 0, 0), Size = Vector3.new(boomLen, 2.4, 2.4), Color = P.HullDark })
	local cells = math.max(math.floor(wingW / 10), 1)
	for side = -1, 1, 2 do
		local wingCf = cf * CFrame.new(boomLen * 0.55, 0, side * (wingH / 2 + 3))
		Kit.part(m, { Name = "Spar", CFrame = wingCf, Size = Vector3.new(1, 1, wingH + 2), Color = P.Hull })
		for i = 0, cells - 1 do
			local x = -wingW / 2 + (i + 0.5) * (wingW / cells)
			Kit.part(m, { Name = "Cell", CFrame = wingCf * CFrame.new(x, 0, 0), Size = Vector3.new(wingW / cells - 0.6, 0.4, wingH),
				Color = P.Solar, Material = Enum.Material.Glass, Reflectance = 0.15, CastShadow = true })
		end
		Kit.part(m, { Name = "Frame", CFrame = wingCf, Size = Vector3.new(wingW + 1, 0.5, 0.6), Color = P.HullLight })
	end
	return m
end

-- Cargo container with corner posts and a coloured stripe.
function Kit.crate(parent: Instance, cf: CFrame, size: Vector3, color: Color3?)
	local m = Kit.model("Container", parent)
	Kit.part(m, { Name = "Body", CFrame = cf, Size = size, Color = color or P.HullDark, Material = Enum.Material.CorrodedMetal })
	Kit.part(m, { Name = "Stripe", CFrame = cf, Size = size + Vector3.new(0.2, -size.Y * 0.7, 0.2), Color = P.Orange,
		Material = Enum.Material.SmoothPlastic, CanCollide = false })
	return m
end

-- Antenna mast with dish.
function Kit.antenna(parent: Instance, cf: CFrame, height: number)
	local m = Kit.model("Antenna", parent)
	Kit.part(m, { Name = "Mast", CFrame = cf * CFrame.new(0, height / 2, 0), Size = Vector3.new(1.2, height, 1.2), Color = P.HullLight })
	Kit.part(m, { Name = "Dish", Shape = Enum.PartType.Cylinder, CFrame = cf * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, math.rad(60)),
		Size = Vector3.new(1, height * 0.4, height * 0.4), Color = P.HullLight })
	local tip = Kit.part(m, { Name = "Beacon", Shape = Enum.PartType.Ball, CFrame = cf * CFrame.new(0, height + 1, 0), Size = Vector3.one * 1.4,
		Material = Enum.Material.Neon, Color = P.Red, CanCollide = false })
	Kit.light(tip, P.Red, 20, 1.5)
	return m
end

-- Sign: a thin plate with text on its local +Z face (so a sign on a room's +Z wall is rotated 180 degrees).
function Kit.sign(parent: Instance, cf: CFrame, text: string, w: number?, h: number?, color: Color3?)
	local p = Kit.part(parent, { Name = "Sign", CFrame = cf, Size = Vector3.new(w or 14, h or 3, 0.3), Color = P.Gunmetal,
		Material = Enum.Material.SmoothPlastic, CanCollide = false })
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Back
	g.LightInfluence = 0
	g.Brightness = 1.6
	g.PixelsPerStud = 30
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color or P.BlueGlow
	l.Text = text
	l.Parent = g
	return p
end

-- Invisible tagged marker for gameplay systems (loot spots, deploy points, etc.).
function Kit.marker(parent: Instance, tag: string, cf: CFrame, attrs)
	local p = Kit.part(parent, { Name = tag, CFrame = cf, Size = Vector3.one, Transparency = 1, CanCollide = false,
		CanQuery = false, CanTouch = false, CastShadow = false })
	for k, v in attrs or {} do p:SetAttribute(k, v) end
	CollectionService:AddTag(p, tag)
	return p
end

-- Pressurised volume: OxygenService refills oxygen inside any part tagged "Pressurized".
function Kit.zone(parent: Instance, cf: CFrame, size: Vector3, id: string)
	local p = Kit.part(parent, { Name = "PressurizedZone", CFrame = cf, Size = size, Transparency = 1, CanCollide = false,
		CanQuery = false, CanTouch = false, CastShadow = false })
	p:SetAttribute("ZoneId", id)
	CollectionService:AddTag(p, "Pressurized")
	return p
end

-- Airlock: a 14-long chamber between an inner and an outer sliding door. Door logic lives in
-- HazardService (interlocked: only one door may be open). cf: chamber centre, local -Z = outside.
function Kit.airlock(parent: Instance, cf: CFrame, opts)
	opts = opts or {}
	local w, h, len = opts.width or 12, opts.height or 12, opts.length or 14
	local m = Kit.room(parent, cf, Vector3.new(w, h, len), {
		name = "Airlock", openings = { ["+Z"] = true, ["-Z"] = true }, lightColor = Color3.fromRGB(255, 190, 120),
		stripColor = P.Orange, deck = true, color = P.HullDark,
	})
	for _, side in { { "InnerDoor", len / 2 }, { "OuterDoor", -len / 2 } } do
		local door = Kit.part(m, { Name = side[1], CFrame = cf * CFrame.new(0, 0, side[2]), Size = Vector3.new(w, h, 1),
			Color = P.HullLight, Material = Enum.Material.DiamondPlate })
		door:SetAttribute("ClosedCFrame", door.CFrame)
		door:SetAttribute("OpenOffset", Vector3.new(0, h, 0))
		Kit.part(m, { Name = side[1] .. "Stripe", CFrame = door.CFrame, Size = Vector3.new(w + 0.1, 1, 1.1), Color = P.Orange,
			Material = Enum.Material.Neon, CanCollide = false })
		-- frame around the opening (so the door retracts into the hull)
		Kit.part(m, { Name = "DoorFrame", CFrame = cf * CFrame.new(0, h / 2 + 1.5, side[2]), Size = Vector3.new(w + 4, 3, 2.2), Color = P.Gunmetal })
	end
	local panel = Kit.part(m, { Name = "Panel", CFrame = cf * CFrame.new(w / 2 - 0.4, 0, 0), Size = Vector3.new(0.6, 2.2, 1.6),
		Color = P.Gunmetal, Material = Enum.Material.SmoothPlastic })
	local lamp = Kit.part(m, { Name = "StatusLamp", CFrame = cf * CFrame.new(w / 2 - 0.5, h / 2 - 1, 0), Size = Vector3.new(0.6, 0.6, 3),
		Material = Enum.Material.Neon, Color = P.Green, CanCollide = false })
	Kit.light(lamp, P.Green, 14, 1)
	local _ = panel
	CollectionService:AddTag(m, "Airlock")
	Kit.NavSpaces[#Kit.NavSpaces].airlock = m -- the chamber room registered by Kit.room above
	return m
end

-- Damaged/flickering light fixture for wreck interiors.
function Kit.brokenLight(parent: Instance, cf: CFrame)
	local p = Kit.part(parent, { Name = "BrokenLight", CFrame = cf, Size = Vector3.new(2, 0.4, 2), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 170, 110), CanCollide = false })
	Kit.light(p, Color3.fromRGB(255, 160, 90), 22, 0.8)
	CollectionService:AddTag(p, "Flicker")
	return p
end

return Kit
