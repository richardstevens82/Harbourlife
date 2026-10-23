-- Builds Harbour Mall on the Part named "MallSite" and the multi-storey car park on "CarParkSite".
-- Two retail levels around a skylit atrium with escalators and glass lifts; every unit is a full store
-- (themed shop floor, till, stockroom with racking, staff room, loading door). See MallDefinitions.
-- MallService runs this at server start when no "HarbourMall" model exists. To bake the mall into the
-- place so it can be edited by hand, run in the Studio command bar (edit mode):
--   require(game.ServerScriptService.Systems.MallBuilder).Build(true)
local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Def = require(Shared.MallDefinitions)
local Shops = require(Shared.ShopDefinitions)
local Businesses = require(Shared.BusinessDefinitions)
local Recipes = require(Shared.RecipeDefinitions)
local Items = require(Shared.ItemDefinitions)
local C = Def.structure
local Mat = Enum.Material

local MallBuilder = {}

local GLASS = { Transparency = 0.45, Reflectance = 0.25 }
local CLEAR = { Transparency = 0.7, Reflectance = 0.1 }
local SETBACK = 26 -- gap between the site edge and the building, for canopies, planters and the plaza
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

--------------------------------------------------------------------------------------------------
-- geometry helpers (all coordinates are local to a frame f)

local function part(parent, name, size, cf, color, mat, props, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Mat.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	if props then for k, v in props do (p :: any)[k] = v end end
	p.Parent = parent
	return p
end

local function box(f, parent, name, x0, y0, z0, x1, y1, z1, color, mat, props)
	local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	if sx < 0.05 or sy < 0.05 or sz < 0.05 then return nil end
	return part(parent, name, Vector3.new(sx, sy, sz), f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat, props)
end

local function ball(f, parent, name, x, y, z, d, color, mat, props)
	return part(parent, name, Vector3.new(d, d, d), f * CFrame.new(x, y, z), color, mat, props or DECOR, Enum.PartType.Ball)
end

-- vertical cylinder standing on y
local function post(f, parent, name, x, y, z, h, d, color, mat, props)
	return part(parent, name, Vector3.new(h, d, d), f * CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, mat, props, Enum.PartType.Cylinder)
end

local function wedge(f, parent, name, size, lcf, color, mat, props)
	local w = Instance.new("WedgePart")
	w.Name = name; w.Anchored = true; w.Size = size; w.CFrame = f * lcf; w.Color = color; w.Material = mat
	if props then for k, v in props do (w :: any)[k] = v end end
	w.Parent = parent
	return w
end

local function font(name)
	local ok, f = pcall(function() return (Enum.Font :: any)[name] end)
	return ok and f or Enum.Font.GothamBold
end

local function material(name)
	local ok, m = pcall(function() return (Mat :: any)[name] end)
	return ok and m or Mat.SmoothPlastic
end

local function sign(p, face, text, color, fontName, bg)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 25
	g.LightInfluence = 0
	g.MaxDistance = 400
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	if bg then t.BackgroundColor3 = bg end
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.Font = font(fontName or "GothamBold")
	t.Parent = g
	g.Parent = p
	return g
end

-- Wall along local X from u0 to u1, centred on z = zc with thickness t, with rectangular openings {u0, u1, y0, y1}.
local function wall(f, parent, name, u0, u1, y0, y1, zc, t, openings, color, mat, props)
	local us = { u0, u1 }
	for _, o in openings do
		for _, v in { o[1], o[2] } do if v > u0 and v < u1 then table.insert(us, v) end end
	end
	table.sort(us)
	for i = 1, #us - 1 do
		local a, b = us[i], us[i + 1]
		if b - a > 0.05 then
			local mid = (a + b) / 2
			local cuts = {}
			for _, o in openings do
				if mid > o[1] and mid < o[2] then table.insert(cuts, { math.max(o[3], y0), math.min(o[4], y1) }) end
			end
			table.sort(cuts, function(p, q) return p[1] < q[1] end)
			local y = y0
			for _, c in cuts do
				if c[1] > y then box(f, parent, name, a, y, zc - t / 2, b, c[1], zc + t / 2, color, mat, props) end
				y = math.max(y, c[2])
			end
			if y1 > y then box(f, parent, name, a, y, zc - t / 2, b, y1, zc + t / 2, color, mat, props) end
		end
	end
end

-- Same as wall() but running along local Z at x = xc; openings use z ranges.
local function wallZ(f, parent, name, z0, z1, y0, y1, xc, t, openings, color, mat, props)
	local rf = f * CFrame.new(xc, 0, 0) * CFrame.Angles(0, math.pi / 2, 0) -- local +X of rf is -Z of f
	local ops = {}
	for _, o in openings do table.insert(ops, { -o[2], -o[1], o[3], o[4] }) end
	wall(rf, parent, name, -z1, -z0, y0, y1, 0, t, ops, color, mat, props)
end

-- Horizontal slab with rectangular holes {x0, z0, x1, z1}; solid cells are merged into strips.
local function slab(f, parent, name, x0, z0, x1, z1, y0, y1, holes, color, mat, props)
	local xs, zs = { x0, x1 }, { z0, z1 }
	for _, h in holes do
		for _, v in { h[1], h[3] } do if v > x0 and v < x1 then table.insert(xs, v) end end
		for _, v in { h[2], h[4] } do if v > z0 and v < z1 then table.insert(zs, v) end end
	end
	table.sort(xs); table.sort(zs)
	local function solid(x, z)
		for _, h in holes do
			if x > h[1] and x < h[3] and z > h[2] and z < h[4] then return false end
		end
		return true
	end
	for i = 1, #xs - 1 do
		local a, b = xs[i], xs[i + 1]
		if b - a > 0.05 then
			local runStart
			for j = 1, #zs do
				local c, d = zs[j], zs[j + 1]
				local isSolid = d ~= nil and solid((a + b) / 2, (c + d) / 2)
				if d ~= nil and d - c <= 0.05 then continue end
				if isSolid and not runStart then runStart = c end
				if not isSolid and runStart then
					box(f, parent, name, a, y0, runStart, b, y1, c, color, mat, props)
					runStart = nil
				end
			end
		end
	end
end

-- Sloped slab whose top surface runs from p0 to p1; width is horizontal, across the slope.
local function ramp(f, parent, name, p0: Vector3, p1: Vector3, width, thick, color, mat, props)
	local d = (p1 - p0).Unit
	local across = Vector3.yAxis:Cross(d)
	across = across.Magnitude > 1e-3 and across.Unit or Vector3.xAxis
	local up = d:Cross(across)
	if up.Y < 0 then up = -up end
	local cf = CFrame.fromMatrix((p0 + p1) / 2 - up * thick / 2, across, up)
	return part(parent, name, Vector3.new(width, thick, (p1 - p0).Magnitude), f * cf, color, mat, props), across, up, d
end

-- Glass balustrade with a steel top rail along an axis-aligned line at floor height y.
local function railing(f, parent, x0, z0, x1, z1, y, h)
	h = h or 3.5
	local ax, az = math.min(x0, x1), math.min(z0, z1)
	local bx, bz = math.max(x0, x1), math.max(z0, z1)
	local alongX = (bx - ax) >= (bz - az)
	local hx, hz = alongX and 0 or 0.15, alongX and 0.15 or 0
	box(f, parent, "Railing", ax - hx, y, az - hz, bx + hx, y + h, bz + hz, C.glass, Mat.Glass, CLEAR)
	box(f, parent, "Handrail", ax - hx * 2, y + h, az - hz * 2, bx + hx * 2, y + h + 0.35, bz + hz * 2, C.metal, Mat.Metal)
end

local function tree(f, parent, x, y, z, s)
	post(f, parent, "Trunk", x, y, z, 7 * s, 0.8 * s, Color3.fromRGB(110, 85, 60), Mat.Wood, DECOR)
	ball(f, parent, "Leaves", x, y + 8 * s, z, 6 * s, C.leaves, Mat.Grass)
	ball(f, parent, "Leaves", x + 1.2 * s, y + 10 * s, z - 0.8 * s, 4.5 * s, C.leaves, Mat.Grass)
end

local function planter(f, parent, x, y, z, sx, sz, withTree)
	box(f, parent, "Planter", x - sx / 2, y, z - sz / 2, x + sx / 2, y + 2.5, z + sz / 2, C.planter, Mat.Limestone)
	box(f, parent, "Soil", x - sx / 2 + 0.5, y + 2.5, z - sz / 2 + 0.5, x + sx / 2 - 0.5, y + 2.6, z + sz / 2 - 0.5, Color3.fromRGB(70, 50, 35), Mat.Ground, DECOR)
	if withTree then tree(f, parent, x, y + 2.5, z, 1) end
end

--------------------------------------------------------------------------------------------------
-- store furniture

local function product(fr, m, x0, y0, z0, x1, y1, z1, color)
	return box(fr, m, "Product", x0, y0, z0, x1, y1, z1, color, Mat.SmoothPlastic, DECOR)
end

local function pick(ctx) return ctx.colors[ctx.rng:NextInteger(1, #ctx.colors)] end

-- Shelving unit over [x0,x1]x[z0,z1] (long axis = shelf direction), stocked with product blocks.
local function shelfRun(ctx, x0, z0, x1, z1, h, levels, blockLen, frameColor)
	local fr, m, rng = ctx.fr, ctx.m, ctx.rng
	frameColor = frameColor or C.metal
	box(fr, m, "Shelf", x0, 0, z0, x1, 0.5, z1, frameColor, Mat.Metal)
	local alongX = (x1 - x0) > (z1 - z0)
	if alongX then
		local zm = (z0 + z1) / 2
		box(fr, m, "Shelf", x0, 0.5, zm - 0.2, x1, h, zm + 0.2, frameColor, Mat.Metal)
	else
		local xm = (x0 + x1) / 2
		box(fr, m, "Shelf", xm - 0.2, 0.5, z0, xm + 0.2, h, z1, frameColor, Mat.Metal)
	end
	local gap = (h - 1) / levels
	for l = 1, levels do
		local y = 0.5 + (l - 1) * gap
		if l > 1 then box(fr, m, "Shelf", x0, y - 0.15, z0, x1, y, z1, frameColor, Mat.Metal) end
		local a0, a1 = alongX and x0 or z0, alongX and x1 or z1
		local a = a0 + 0.3
		while a < a1 - 1 do
			local len = math.min(blockLen * (0.6 + rng:NextNumber() * 0.8), a1 - 0.3 - a)
			local ph = math.min(gap - 0.4, 0.8 + rng:NextNumber() * 1.2)
			if alongX then product(fr, m, a, y, z0 + 0.2, a + len, y + ph, z1 - 0.2, pick(ctx))
			else product(fr, m, x0 + 0.2, y, a, x1 - 0.2, y + ph, a + len, pick(ctx)) end
			a += len + 0.4
		end
	end
end

local function wallShelf(ctx, side, z0, z1, h, levels)
	local x = side < 0 and ctx.wx0 or ctx.wx1 - 2.5
	shelfRun(ctx, x, z0, x + 2.5, z1, h or 8, levels or 4, 5, ctx.def.accent)
end

local function clothesRail(ctx, x, z, len)
	local fr, m = ctx.fr, ctx.m
	for _, dx in { -len / 2, len / 2 } do post(fr, m, "RailPost", x + dx, 0, z, 5.6, 0.3, C.metal, Mat.Metal) end
	box(fr, m, "Rail", x - len / 2, 5.4, z - 0.1, x + len / 2, 5.6, z + 0.1, C.metal, Mat.Metal, DECOR)
	local n = math.floor(len / 3)
	for i = 1, n do
		local gx = x - len / 2 + (i - 0.5) * len / n
		box(fr, m, "Garment", gx - 0.35, 2.2, z - 1.2, gx + 0.35, 5.3, z + 1.2, pick(ctx), Mat.Fabric, DECOR)
	end
end

local function mannequin(ctx, x, z)
	local fr, m = ctx.fr, ctx.m
	post(fr, m, "Mannequin", x, 0, z, 0.3, 2.2, C.dark, Mat.Metal, DECOR)
	box(fr, m, "Mannequin", x - 0.5, 0.3, z - 0.4, x + 0.5, 3.4, z + 0.4, Color3.fromRGB(235, 235, 235), Mat.SmoothPlastic, DECOR)
	box(fr, m, "Outfit", x - 1, 3.4, z - 0.55, x + 1, 6, z + 0.55, pick(ctx), Mat.Fabric, DECOR)
	ball(fr, m, "Mannequin", x, 6.8, z, 1.3, Color3.fromRGB(235, 235, 235), Mat.SmoothPlastic)
end

local function displayTable(ctx, x, z, w, d)
	local fr, m, rng = ctx.fr, ctx.m, ctx.rng
	box(fr, m, "Table", x - w / 2 + 0.6, 0, z - d / 2 + 0.6, x + w / 2 - 0.6, 2.6, z + d / 2 - 0.6, ctx.def.wall, Mat.SmoothPlastic)
	box(fr, m, "TableTop", x - w / 2, 2.6, z - d / 2, x + w / 2, 3, z + d / 2, ctx.def.accent, Mat.SmoothPlastic)
	for i = 1, 4 do
		local px = x - w / 2 + (i - 0.5) * w / 4
		local s = 0.8 + rng:NextNumber() * 1.2
		product(fr, m, px - s / 2, 3, z - s / 2, px + s / 2, 3 + 0.3 + rng:NextNumber() * 1.5, z + s / 2, pick(ctx))
	end
end

local function glassCase(ctx, x0, z0, x1, z1)
	local fr, m, rng = ctx.fr, ctx.m, ctx.rng
	box(fr, m, "Case", x0, 0, z0, x1, 3, z1, ctx.def.wall, Mat.SmoothPlastic)
	box(fr, m, "CaseLight", x0 + 0.2, 3, z0 + 0.2, x1 - 0.2, 3.1, z1 - 0.2, Color3.fromRGB(250, 245, 230), Mat.Neon, DECOR)
	box(fr, m, "CaseGlass", x0, 3.1, z0, x1, 4.6, z1, C.glass, Mat.Glass, CLEAR)
	local alongX = (x1 - x0) > (z1 - z0)
	local len = alongX and (x1 - x0) or (z1 - z0)
	for i = 1, math.floor(len / 2) do
		local t = (i - 0.5) / math.floor(len / 2)
		local px = alongX and (x0 + t * (x1 - x0)) or (x0 + x1) / 2
		local pz = alongX and (z0 + z1) / 2 or (z0 + t * (z1 - z0))
		ball(fr, m, "Item", px, 3.5, pz, 0.4 + rng:NextNumber() * 0.4, pick(ctx), Mat.Neon)
	end
end

local function sofa(ctx, x, z, color)
	local fr, m = ctx.fr, ctx.m
	box(fr, m, "Sofa", x - 5, 0, z - 2, x + 5, 1.8, z + 2, color, Mat.Fabric)
	box(fr, m, "Sofa", x - 5, 1.8, z + 1, x + 5, 4, z + 2, color, Mat.Fabric)
	for _, s in { -1, 1 } do box(fr, m, "Sofa", x + s * 4.4 - 0.6, 1.8, z - 2, x + s * 4.4 + 0.6, 2.8, z + 2, color, Mat.Fabric) end
end

local function vignette(ctx, kind, x, z)
	local fr, m = ctx.fr, ctx.m
	local wood = Color3.fromRGB(150, 110, 70)
	box(fr, m, "Rug", x - 10, 0.06, z - 9, x + 10, 0.12, z + 9, pick(ctx), Mat.Fabric, DECOR)
	if kind == 1 then
		sofa(ctx, x, z + 4, pick(ctx))
		box(fr, m, "CoffeeTable", x - 3, 0, z - 4, x + 3, 1.6, z - 1, wood, Mat.Wood)
		post(fr, m, "Lamp", x + 8, 0, z + 5, 6, 0.3, C.dark, Mat.Metal)
		post(fr, m, "LampShade", x + 8, 6, z + 5, 1.6, 1.6, Color3.fromRGB(250, 240, 210), Mat.Fabric, DECOR)
	elseif kind == 2 then
		box(fr, m, "Bed", x - 4.5, 0, z - 5, x + 4.5, 1.6, z + 6, wood, Mat.Wood)
		box(fr, m, "Mattress", x - 4.2, 1.6, z - 4.8, x + 4.2, 2.6, z + 5.8, Color3.fromRGB(245, 245, 245), Mat.Fabric)
		box(fr, m, "Duvet", x - 4.3, 2.6, z - 4.9, x + 4.3, 2.9, z + 2, pick(ctx), Mat.Fabric, DECOR)
		box(fr, m, "Headboard", x - 4.5, 0, z + 6, x + 4.5, 5, z + 6.6, wood, Mat.Wood)
		for _, s in { -1, 1 } do box(fr, m, "Bedside", x + s * 6.5 - 1, 0, z + 4, x + s * 6.5 + 1, 2.2, z + 6, wood, Mat.Wood) end
	elseif kind == 3 then
		box(fr, m, "DiningTable", x - 4, 2.6, z - 2.5, x + 4, 3, z + 2.5, wood, Mat.Wood)
		box(fr, m, "DiningTable", x - 3.5, 0, z - 2, x + 3.5, 2.6, z + 2, C.dark, Mat.Metal)
		for _, cx in { -2.2, 2.2 } do
			for _, s in { -1, 1 } do
				local cz = z + s * 3.6
				box(fr, m, "Chair", x + cx - 0.9, 0, cz - 0.9, x + cx + 0.9, 1.8, cz + 0.9, pick(ctx), Mat.Fabric)
				box(fr, m, "Chair", x + cx - 0.9, 1.8, cz + s * 0.7 - 0.2, x + cx + 0.9, 4, cz + s * 0.7 + 0.2, pick(ctx), Mat.Fabric)
			end
		end
	else
		box(fr, m, "Desk", x - 4, 2.6, z - 2, x + 4, 3, z + 2, wood, Mat.Wood)
		box(fr, m, "Desk", x - 4, 0, z - 2, x - 3.4, 2.6, z + 2, wood, Mat.Wood)
		box(fr, m, "Desk", x + 3.4, 0, z - 2, x + 4, 2.6, z + 2, wood, Mat.Wood)
		box(fr, m, "Bookcase", x - 6, 0, z + 5, x + 6, 8, z + 6.5, wood, Mat.Wood)
		box(fr, m, "Chair", x - 1, 0, z - 4, x + 1, 2, z - 2, pick(ctx), Mat.Fabric)
	end
end

local function tank(ctx, x0, z0, x1, z1)
	local fr, m, rng = ctx.fr, ctx.m, ctx.rng
	box(fr, m, "TankStand", x0, 0, z0, x1, 3, z1, C.dark, Mat.Wood)
	box(fr, m, "Water", x0 + 0.2, 3, z0 + 0.2, x1 - 0.2, 7.5, z1 - 0.2, Color3.fromRGB(60, 150, 230), Mat.Glass, { Transparency = 0.5, CanCollide = false })
	box(fr, m, "Tank", x0, 3, z0, x1, 8, z1, C.glass, Mat.Glass, { Transparency = 0.8 })
	for _ = 1, 3 do
		ball(fr, m, "Fish", x0 + 0.6 + rng:NextNumber() * (x1 - x0 - 1.2), 4 + rng:NextNumber() * 3, z0 + 0.6 + rng:NextNumber() * (z1 - z0 - 1.2), 0.5, pick(ctx), Mat.Neon)
	end
end

local function sideScreens(ctx, side, z0, z1, kind)
	local fr, m = ctx.fr, ctx.m
	local x = side < 0 and ctx.wx0 or ctx.wx1
	local inward = -side
	for z = z0 + 4, z1 - 4, 8 do
		for row = 0, 1 do
			local y = 6 + row * 5
			if kind == "tv" then
				box(fr, m, "TV", x, y, z - 3, x + inward * 0.4, y + 3.6, z + 3, C.dark, Mat.SmoothPlastic, DECOR)
				box(fr, m, "Screen", x + inward * 0.4, y + 0.2, z - 2.8, x + inward * 0.45, y + 3.4, z + 2.8, pick(ctx), Mat.Neon, DECOR)
			else -- guitar
				local col = pick(ctx)
				part(m, "Guitar", Vector3.new(0.5, 2.6, 2.6), fr * CFrame.new(x + inward * 0.6, y, z), col, Mat.Wood, DECOR, Enum.PartType.Cylinder)
				box(fr, m, "Neck", x + inward * 0.5, y + 1.2, z - 0.2, x + inward * 0.75, y + 4.5, z + 0.2, C.dark, Mat.Wood, DECOR)
			end
		end
	end
end

--------------------------------------------------------------------------------------------------
-- store layouts and features. ctx.x0..x1 / z0..z1 is the open shop floor behind the till zone.

local Layouts = {}

function Layouts.aisles(ctx)
	local h = ctx.def.shelfHeight or 6
	for x = ctx.x0 + 8, ctx.x1 - 6, 13 do
		shelfRun(ctx, x - 1.5, ctx.z0 + 2, x + 1.5, ctx.z1 - 10, h, h >= 8 and 4 or 3, 7)
		box(ctx.fr, ctx.m, "EndCap", x - 1.8, 0, ctx.z0, x + 1.8, 3.5, ctx.z0 + 2, ctx.def.accent, Mat.SmoothPlastic)
	end
	wallShelf(ctx, -1, ctx.z0, ctx.z1, h + 2)
	if not ctx.rightWallUsed then wallShelf(ctx, 1, ctx.z0, ctx.z1, h + 2) end
end

function Layouts.bookcases(ctx)
	local wood = ctx.def.accent
	for x = ctx.x0 + 10, ctx.x1 - 6, 12 do
		shelfRun(ctx, x - 1.5, ctx.z0 + 14, x + 1.5, ctx.z1 - 6, 9, 4, 6, wood)
	end
	wallShelf(ctx, -1, ctx.z0, ctx.z1, 12, 5)
	wallShelf(ctx, 1, ctx.z0, ctx.z1, 12, 5)
	for x = ctx.x0 + 10, ctx.x1 - 10, 18 do displayTable(ctx, x, ctx.z0 + 6, 10, 5) end
end

function Layouts.racks(ctx)
	for z = ctx.z0 + 6, ctx.z1 - 6, 11 do
		for x = ctx.x0 + 10, ctx.x1 - 10, 19 do clothesRail(ctx, x, z, 12) end
	end
	wallShelf(ctx, -1, ctx.z0, ctx.z1, 9, 4)
	if not ctx.rightWallUsed then wallShelf(ctx, 1, ctx.z0, ctx.z1, 9, 4) end
end

function Layouts.tables(ctx)
	for z = ctx.z0 + 6, ctx.z1 - 6, 14 do
		for x = ctx.x0 + 10, ctx.x1 - 10, 18 do displayTable(ctx, x, z, 10, 5) end
	end
	if not ctx.leftWallUsed then wallShelf(ctx, -1, ctx.z0, ctx.z1, 8, 4) end
	if not ctx.rightWallUsed then wallShelf(ctx, 1, ctx.z0, ctx.z1, 8, 4) end
end

function Layouts.showroom(ctx)
	local kind = 0
	for z = ctx.z0 + 10, ctx.z1 - 10, 24 do
		for x = ctx.x0 + 12, ctx.x1 - 12, 26 do
			kind = kind % 4 + 1
			vignette(ctx, kind, x, z)
		end
	end
end

function Layouts.tanks(ctx)
	for _, side in { -1, 1 } do
		local x = side < 0 and ctx.wx0 or ctx.wx1 - 4
		for z = ctx.z0, ctx.z1 - 9, 10 do tank(ctx, x, z, x + 4, z + 9) end
	end
	local fr, m = ctx.fr, ctx.m
	for i, x in { ctx.x0 + 18, ctx.x1 - 18 } do
		local z = ctx.z0 + 8
		for _, e in { { -6, -0.2, 6, 0.2 }, { -6, 11.8, 6, 12.2 }, { -6.2, 0, -5.8, 12 }, { 5.8, 0, 6.2, 12 } } do
			box(fr, m, "PenFence", x + e[1], 0, z + e[2], x + e[3], 2.5, z + e[4], ctx.def.accent, Mat.Wood)
		end
		box(fr, m, "Straw", x - 5.8, 0.06, z + 0.2, x + 5.8, 0.3, z + 11.8, Color3.fromRGB(220, 190, 110), Mat.Grass, DECOR)
		box(fr, m, "PetBed", x - 2, 0.3, z + 4 + i, x + 2, 1, z + 7 + i, pick(ctx), Mat.Fabric, DECOR)
	end
	for x = ctx.x0 + 12, ctx.x1 - 12, 14 do shelfRun(ctx, x - 1.5, ctx.z0 + 26, x + 1.5, ctx.z1 - 8, 5, 3, 5) end
end

function Layouts.wallShelves(ctx)
	wallShelf(ctx, -1, ctx.z0, ctx.z1, 10, 6)
	wallShelf(ctx, 1, ctx.z0, ctx.z1, 10, 6)
	for z = ctx.z0 + 8, ctx.z1 - 8, 16 do
		for x = ctx.x0 + 14, ctx.x1 - 14, 22 do displayTable(ctx, x, z, 12, 4) end
	end
end

function Layouts.cases(ctx)
	for z = ctx.z0 + 2, ctx.z1 - 10, 12 do
		glassCase(ctx, ctx.wx0 + 1, z, ctx.wx0 + 4, z + 9)
		glassCase(ctx, ctx.wx1 - 4, z, ctx.wx1 - 1, z + 9)
	end
	for z = ctx.z0 + 8, ctx.z1 - 10, 18 do
		for x = ctx.x0 + 16, ctx.x1 - 16, 24 do
			glassCase(ctx, x - 6, z, x + 6, z + 3)
			glassCase(ctx, x - 6, z + 3, x - 3, z + 9)
		end
	end
	for x = ctx.x0 + 16, ctx.x1 - 16, 24 do -- chandeliers
		for i = 0, 4 do ball(ctx.fr, ctx.m, "Chandelier", x + math.cos(i) * 1.5, ctx.hc - 3 - (i % 2), ctx.z0 + 20 + math.sin(i) * 1.5, 0.9, Color3.fromRGB(255, 240, 200), Mat.Neon) end
	end
end

local Features = {}

function Features.produce(ctx)
	for i = 0, 3 do
		local x = ctx.wx0 + 6 + i * 9
		box(ctx.fr, ctx.m, "ProduceStand", x, 0, 6, x + 7, 2.5, 14, Color3.fromRGB(150, 110, 70), Mat.WoodPlanks)
		box(ctx.fr, ctx.m, "Produce", x + 0.4, 2.5, 6.4, x + 6.6, 3.3, 13.6, pick(ctx), Mat.Grass, DECOR)
	end
end

function Features.fridges(ctx)
	ctx.rightWallUsed = true
	local x = ctx.wx1 - 3
	shelfRun(ctx, x, ctx.z0, x + 3, ctx.z1, 8, 4, 4, Color3.fromRGB(240, 240, 240))
	box(ctx.fr, ctx.m, "FridgeGlass", x - 0.3, 0.5, ctx.z0, x, 8, ctx.z1, C.glass, Mat.Glass, CLEAR)
	box(ctx.fr, ctx.m, "FridgeLight", x - 0.4, 8, ctx.z0, x + 3, 8.4, ctx.z1, Color3.fromRGB(120, 200, 255), Mat.Neon, DECOR)
end

function Features.timber(ctx)
	ctx.rightWallUsed = true
	for i = 0, 3 do
		box(ctx.fr, ctx.m, "Timber", ctx.wx1 - 5, i * 1.2, ctx.z0, ctx.wx1 - 1, i * 1.2 + 1, ctx.z1, Color3.fromRGB(205, 170, 120), Mat.WoodPlanks)
	end
end

function Features.shed(ctx)
	local x, z = ctx.wx0 + 10, 12
	box(ctx.fr, ctx.m, "Shed", x - 5, 0, z - 4, x + 5, 7, z + 4, Color3.fromRGB(140, 100, 60), Mat.WoodPlanks)
	box(ctx.fr, ctx.m, "ShedRoof", x - 6, 7, z - 5, x + 6, 7.8, z + 5, Color3.fromRGB(60, 60, 60), Mat.Slate)
	box(ctx.fr, ctx.m, "ShedDoor", x - 1.5, 0, z - 4.2, x + 1.5, 6, z - 4, Color3.fromRGB(100, 70, 40), Mat.Wood, DECOR)
end

function Features.dispensary(ctx)
	local z = ctx.z1 - 4
	box(ctx.fr, ctx.m, "Dispensary", -14, 0, z, 14, 4, z + 3, Color3.fromRGB(250, 250, 250), Mat.SmoothPlastic)
	box(ctx.fr, ctx.m, "Cross", -0.8, 9, ctx.sd - 0.8, 0.8, 15, ctx.sd - 0.5, ctx.def.accent, Mat.Neon, DECOR)
	box(ctx.fr, ctx.m, "Cross", -3, 11.2, ctx.sd - 0.8, 3, 12.8, ctx.sd - 0.5, ctx.def.accent, Mat.Neon, DECOR)
end

function Features.rodWall(ctx)
	ctx.rightWallUsed = true
	local x = ctx.wx1 - 1.2
	for z = ctx.z0, ctx.z0 + 50, 1.4 do post(ctx.fr, ctx.m, "Rod", x, 1, z, 10, 0.25, pick(ctx), Mat.SmoothPlastic, DECOR) end
	box(ctx.fr, ctx.m, "RodRack", x - 0.6, 0, ctx.z0 - 1, x + 0.6, 1, ctx.z0 + 51, C.dark, Mat.Wood)
end

function Features.boat(ctx)
	local x, z = ctx.wx0 + 14, 12
	box(ctx.fr, ctx.m, "BoatPlinth", x - 9, 0, z - 4, x + 9, 1, z + 4, C.dark, Mat.Wood)
	box(ctx.fr, ctx.m, "BoatHull", x - 6, 1, z - 2.5, x + 6, 3.5, z + 2.5, Color3.fromRGB(245, 245, 245), Mat.SmoothPlastic)
	wedge(ctx.fr, ctx.m, "BoatBow", Vector3.new(5, 2.5, 3), CFrame.new(x + 7.5, 2.25, z) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(245, 245, 245), Mat.SmoothPlastic)
	box(ctx.fr, ctx.m, "BoatStripe", x - 6, 2.6, z - 2.6, x + 6, 3, z + 2.6, ctx.def.accent, Mat.SmoothPlastic, DECOR)
end

function Features.mannequins(ctx)
	for _, x in { -ctx.uw / 2 + 6, -ctx.uw / 2 + 12, ctx.uw / 2 - 12, ctx.uw / 2 - 6 } do mannequin(ctx, x, 3) end
end

function Features.fittingRooms(ctx)
	local z1 = ctx.sd - 0.5
	for i = 0, 3 do
		local x = ctx.wx0 + 4 + i * 6
		box(ctx.fr, ctx.m, "FittingWall", x, 0, z1 - 7, x + 0.3, 8, z1, ctx.def.wall, Mat.SmoothPlastic)
		box(ctx.fr, ctx.m, "Curtain", x + 0.3, 0.5, z1 - 7, x + 6, 7.5, z1 - 6.8, ctx.def.accent, Mat.Fabric, DECOR)
	end
end

function Features.ballPyramids(ctx)
	for p = 0, 1 do
		local bx = ctx.wx0 + 8 + p * 12
		for layer = 0, 2 do
			local n = 3 - layer
			for i = 0, n - 1 do
				for j = 0, n - 1 do
					ball(ctx.fr, ctx.m, "Ball", bx + (i - (n - 1) / 2) * 1.6, 0.8 + layer * 1.3, 12 + (j - (n - 1) / 2) * 1.6, 1.6, pick(ctx), Mat.SmoothPlastic)
				end
			end
		end
	end
end

function Features.hoop(ctx)
	local x, z = ctx.x0 + 4, ctx.z1 - 2
	post(ctx.fr, ctx.m, "HoopPole", x, 0, z, 12, 0.5, C.dark, Mat.Metal)
	box(ctx.fr, ctx.m, "Backboard", x - 3, 10, z - 1, x + 3, 14, z - 0.7, Color3.fromRGB(250, 250, 250), Mat.SmoothPlastic)
	for _, e in { { -1, -3.2, 1, -3 }, { -1, -1.2, 1, -1 }, { -1.1, -3.2, -0.9, -1 }, { 0.9, -3.2, 1.1, -1 } } do
		box(ctx.fr, ctx.m, "Rim", x + e[1], 10.8, z + e[2], x + e[3], 11, z + e[4], Color3.fromRGB(240, 100, 20), Mat.Metal, DECOR)
	end
end

function Features.displayCases(ctx)
	for i = 0, 2 do glassCase(ctx, ctx.wx0 + 4 + i * 9, 6, ctx.wx0 + 11 + i * 9, 9) end
end

function Features.tvWall(ctx)
	ctx.leftWallUsed, ctx.rightWallUsed = true, true
	sideScreens(ctx, -1, ctx.z0, ctx.z1, "tv")
	sideScreens(ctx, 1, ctx.z0, ctx.z1, "tv")
end

function Features.guitarWall(ctx)
	ctx.leftWallUsed = true
	sideScreens(ctx, -1, ctx.z0, ctx.z1, "guitar")
end

function Features.stage(ctx)
	local x, z = ctx.wx0 + 14, 12
	box(ctx.fr, ctx.m, "Stage", x - 10, 0, z - 5, x + 10, 1.5, z + 5, C.dark, Mat.WoodPlanks)
	for _, s in { -1, 1 } do box(ctx.fr, ctx.m, "Speaker", x + s * 8 - 1.5, 1.5, z, x + s * 8 + 1.5, 7, z + 2.5, C.dark, Mat.Fabric) end
	post(ctx.fr, ctx.m, "Drum", x, 1.5, z + 1, 1.6, 3, ctx.def.accent, Mat.SmoothPlastic)
	post(ctx.fr, ctx.m, "Drum", x - 2.5, 1.5, z + 1.5, 2.4, 1.8, ctx.def.accent, Mat.SmoothPlastic)
	post(ctx.fr, ctx.m, "Cymbal", x + 2.5, 1.5, z + 2, 5, 0.2, C.metal, Mat.Metal)
end

function Features.benches(ctx)
	for i = 0, 2 do
		local x = ctx.wx0 + 6 + i * 12
		box(ctx.fr, ctx.m, "Bench", x, 0, 8, x + 8, 1.8, 10.5, ctx.def.accent, Mat.Fabric)
		box(ctx.fr, ctx.m, "Mirror", x + 2, 0, 12.5, x + 6, 6, 12.8, C.glass, Mat.Glass, { Reflectance = 0.6 })
	end
end

function Features.giantTeddy(ctx)
	local x, z, brown = ctx.wx0 + 10, 10, Color3.fromRGB(160, 110, 60)
	ball(ctx.fr, ctx.m, "Teddy", x, 4, z, 8, brown, Mat.Fabric, {})
	ball(ctx.fr, ctx.m, "Teddy", x, 10, z, 6, brown, Mat.Fabric)
	for _, s in { -1, 1 } do
		ball(ctx.fr, ctx.m, "TeddyEar", x + s * 2.4, 12.6, z, 2.2, brown, Mat.Fabric)
		ball(ctx.fr, ctx.m, "TeddyArm", x + s * 4.2, 5.5, z - 1, 3, brown, Mat.Fabric)
		ball(ctx.fr, ctx.m, "TeddyLeg", x + s * 2.2, 1.4, z - 2.5, 3.2, brown, Mat.Fabric)
	end
	ball(ctx.fr, ctx.m, "TeddyNose", x, 9.8, z - 2.8, 1.2, Color3.fromRGB(40, 30, 20), Mat.SmoothPlastic)
end

function Features.readingArea(ctx)
	local x, z = ctx.wx0 + 14, 12
	box(ctx.fr, ctx.m, "Rug", x - 10, 0.06, z - 6, x + 10, 0.12, z + 6, Color3.fromRGB(120, 40, 40), Mat.Fabric, DECOR)
	for _, s in { -1, 1 } do
		box(ctx.fr, ctx.m, "Armchair", x + s * 5 - 2, 0, z - 2, x + s * 5 + 2, 2, z + 2, Color3.fromRGB(60, 90, 60), Mat.Fabric)
		box(ctx.fr, ctx.m, "Armchair", x + s * 5 - 2, 2, z + 1.4, x + s * 5 + 2, 4.5, z + 2, Color3.fromRGB(60, 90, 60), Mat.Fabric)
	end
	box(ctx.fr, ctx.m, "CoffeeTable", x - 1.5, 0, z - 1.5, x + 1.5, 1.6, z + 1.5, ctx.def.accent, Mat.Wood)
end

--------------------------------------------------------------------------------------------------
-- fittings shared by the stores and the mall

-- Automatic sliding glass doors filling x0..x1 at z = zc in frame f. Each panel stores the world offset it
-- slides by when open; MallService opens the pair while a player is near the Centre attribute.
local function autoDoor(f, parent, x0, x1, y0, y1, zc, frameColor)
	local m = Instance.new("Model")
	m.Name = "AutoDoor"
	local half, mid = (x1 - x0) / 2, (x0 + x1) / 2
	box(f, m, "DoorTrack", x0 - half, y1, zc - 0.3, x1 + half, y1 + 0.6, zc + 0.3, frameColor, Mat.Metal)
	for _, s in { -1, 1 } do
		local a, b = s < 0 and x0 or mid, s < 0 and mid or x1
		local panel = box(f, m, s < 0 and "DoorLeft" or "DoorRight", a, y0, zc - 0.15, b, y1, zc + 0.15, C.glass, Mat.Glass, { Transparency = 0.5, Reflectance = 0.2 })
		panel:SetAttribute("OpenOffset", f:VectorToWorldSpace(Vector3.new(s * (half - 0.4), 0, 0)))
	end
	m:SetAttribute("Centre", (f * CFrame.new(mid, y0, zc)).Position)
	CollectionService:AddTag(m, "HarbourAutoDoor")
	m.Parent = parent
	return m
end

-- Free-standing board listing text on its -Z face.
local function board(f, parent, name, x0, y0, z0, x1, y1, text, title)
	local b = box(f, parent, name, x0, y0, z0, x1, y1, z0 + 0.6, C.dark, Mat.SmoothPlastic)
	box(f, parent, name .. "Frame", x0 - 0.3, y0, z0 + 0.1, x1 + 0.3, y1 + 0.3, z0 + 0.5, C.bronze, Mat.Metal)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = b
	local head = Instance.new("TextLabel")
	head.Size = UDim2.fromScale(1, 0.12); head.BackgroundColor3 = C.bronze; head.TextScaled = true
	head.TextColor3 = Color3.new(1, 1, 1); head.Font = Enum.Font.GothamBlack; head.Text = title
	head.Parent = g
	local body = Instance.new("TextLabel")
	body.Position = UDim2.fromScale(0.05, 0.14); body.Size = UDim2.fromScale(0.9, 0.84)
	body.BackgroundTransparency = 1; body.TextScaled = true; body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left; body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = Color3.fromRGB(235, 235, 235); body.Font = Enum.Font.Gotham; body.Text = text
	body.Parent = g
	return b
end

--------------------------------------------------------------------------------------------------
-- a store unit: frame fr has origin at the shopfront centre on the floor, +Z pointing into the store

local function hashSeed(s)
	local h = 7
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

local function buildStore(parent, fr, uw, ud, hc, def, groundFloor)
	local shopDef = def and Shops[def.shop]
	local m = Instance.new("Model")
	m.Name = shopDef and def.shop or "VacantUnit"
	local wallColor = def and def.wall or Color3.fromRGB(235, 235, 235)
	local hw = uw / 2

	-- shell: side walls, floor, ceiling, pilasters between units
	box(fr, m, "Wall", -hw, 0, 0, -hw + 1, hc, ud, wallColor, Mat.SmoothPlastic)
	box(fr, m, "Wall", hw - 1, 0, 0, hw, hc, ud, wallColor, Mat.SmoothPlastic)
	box(fr, m, "Pilaster", -hw, 0, -0.8, -hw + 1.5, hc, 0, C.gallery, Mat.Marble)
	box(fr, m, "Pilaster", hw - 1.5, 0, -0.8, hw, hc, 0, C.gallery, Mat.Marble)
	box(fr, m, "Ceiling", -hw + 1, hc - 0.3, 0, hw - 1, hc, ud, C.ceiling, Mat.SmoothPlastic)

	if not shopDef then -- vacant: hoarding across the front
		box(fr, m, "Hoarding", -hw + 1, 0, 0, hw - 1, hc, 0.6, Color3.fromRGB(245, 245, 245), Mat.SmoothPlastic)
		local s = box(fr, m, "HoardingSign", -hw / 2, 6, -0.2, hw / 2, 12, 0, C.bronze, Mat.SmoothPlastic, DECOR)
		sign(s, Enum.NormalId.Front, "NEW STORE COMING SOON", Color3.new(1, 1, 1), "GothamBold")
		m.Parent = parent
		return m
	end

	local floorMat = material(def.floorMat)
	box(fr, m, "Floor", -hw + 1, 0, 0, hw - 1, 0.06, ud, def.floor, floorMat)

	-- shopfront: glass with a central entrance, LED strip and the store's own fascia sign
	local doorH = 14
	wall(fr, m, "Shopfront", -hw + 1, hw - 1, 0, doorH, 0.2, 0.4, { { -8, 8, 0, doorH } }, C.glass, Mat.Glass, GLASS)
	for x = -hw + 1 + 10, hw - 11, 10 do
		if math.abs(x) > 8.5 then box(fr, m, "Mullion", x - 0.2, 0, -0.1, x + 0.2, doorH, 0.5, C.dark, Mat.Metal) end
	end
	for _, x in { -8, 8 } do box(fr, m, "DoorFrame", x - 0.4, 0, -0.2, x + 0.4, doorH, 0.6, def.accent, Mat.Metal) end
	box(fr, m, "Transom", -8, 10.6, 0, 8, doorH, 0.4, C.glass, Mat.Glass, GLASS)
	autoDoor(fr, m, -8, 8, 0, 10, 0.85, def.accent) -- slides behind the fixed glass
	box(fr, m, "Fascia", -hw + 1, doorH, -0.3, hw - 1, hc, 0.6, def.wall, Mat.SmoothPlastic)
	box(fr, m, "FasciaLED", -hw + 1, doorH, -0.6, hw - 1, doorH + 0.4, -0.3, def.accent, Mat.Neon, DECOR)
	local sg = box(fr, m, "StoreSign", -hw * 0.55, doorH + 1.6, -1, hw * 0.55, hc - 1.6, -0.3, def.accent, Mat.SmoothPlastic, DECOR)
	sign(sg, Enum.NormalId.Front, string.upper(shopDef.name), def.signColor, def.font)
	box(fr, m, "Entrance", -8, 0.06, -2, 8, 0.1, 3, C.dark, Mat.Fabric, DECOR)

	local sd = math.floor(ud * Def.salesFraction)
	local rng = Random.new(hashSeed(def.shop))
	local ctx = {
		fr = fr, m = m, def = def, rng = rng, colors = def.products, uw = uw, ud = ud, hc = hc, sd = sd,
		wx0 = -hw + 1, wx1 = hw - 1, -- inner faces of the side walls
		x0 = -hw + 6, x1 = hw - 6, z0 = 26, z1 = sd - 8,
	}

	-- till: the counter Part is what ShopService turns into the Browse prompt
	local till = box(fr, m, "Shop_" .. def.shop, hw - 30, 0, 12, hw - 10, 4, 15, def.accent, Mat.SmoothPlastic)
	till:SetAttribute("Till", true)
	box(fr, m, "CounterTop", hw - 30.3, 4, 11.7, hw - 9.7, 4.3, 15.3, Color3.fromRGB(245, 245, 245), Mat.Marble, DECOR)
	for _, x in { hw - 26, hw - 16 } do
		box(fr, m, "TillScreen", x - 1, 4.3, 13, x + 1, 6, 13.3, C.dark, Mat.SmoothPlastic, DECOR)
		box(fr, m, "TillScreen", x - 0.9, 4.4, 12.95, x + 0.9, 5.9, 13, Color3.fromRGB(120, 220, 255), Mat.Neon, DECOR)
	end
	shelfRun(ctx, hw - 30, 21, hw - 4, 23, 7, 3, 4, def.accent) -- behind-the-till stock
	local tillSign = box(fr, m, "TillSign", hw - 26, hc - 5, 13.4, hw - 14, hc - 2.5, 13.6, def.accent, Mat.SmoothPlastic, DECOR)
	sign(tillSign, Enum.NormalId.Front, "PAY HERE", def.signColor, def.font)
	box(fr, m, "TillHanger", hw - 20.1, hc - 2.5, 13.45, hw - 19.9, hc, 13.55, C.metal, Mat.Metal, DECOR)

	for _, feat in def.features or {} do
		if Features[feat] then Features[feat](ctx) else warn("[MallBuilder] unknown feature " .. feat) end
	end
	local layout = Layouts[def.layout] or Layouts.aisles
	layout(ctx)

	-- lighting: neon ceiling panels with a couple of real lights
	local lit = 0
	for z = 10, sd - 6, 20 do
		for x = -hw + 12, hw - 12, 22 do
			local panel = box(fr, m, "CeilingLight", x - 4, hc - 0.6, z - 1, x + 4, hc - 0.3, z + 1, Color3.fromRGB(255, 250, 240), Mat.Neon, DECOR)
			if lit < 2 and z > 20 and x > -hw + 20 then
				lit += 1
				local l = Instance.new("SurfaceLight")
				l.Face = Enum.NormalId.Bottom; l.Range = 45; l.Angle = 150; l.Brightness = 1.2; l.Shadows = false
				l.Parent = panel
			end
		end
	end
	box(fr, m, "AccentStrip", -hw + 1, hc - 1.4, 2, -hw + 1.2, hc - 1, sd, def.accent, Mat.Neon, DECOR)
	box(fr, m, "AccentStrip", hw - 1.2, hc - 1.4, 2, hw - 1, hc - 1, sd, def.accent, Mat.Neon, DECOR)

	-- back of house: partition with staff door, stockroom racking, staff room, loading door
	wall(fr, m, "Partition", -hw + 1, hw - 1, 0, hc, sd, 1, { { hw - 16, hw - 8, 0, 10 } }, def.wall, Mat.SmoothPlastic)
	local staffSign = box(fr, m, "StaffOnly", hw - 16, 10.4, sd - 0.7, hw - 8, 12.4, sd - 0.5, C.dark, Mat.SmoothPlastic, DECOR)
	sign(staffSign, Enum.NormalId.Front, "STAFF ONLY", Color3.new(1, 1, 1), "GothamBold")
	box(fr, m, "StockFloor", -hw + 1, 0.06, sd + 0.5, hw - 1, 0.1, ud, Color3.fromRGB(160, 160, 160), Mat.Concrete, DECOR)

	local staffX1, staffZ0 = -hw + 26, ud - 22
	local upright, beam, cardboard = Color3.fromRGB(40, 70, 140), Color3.fromRGB(235, 120, 30), Color3.fromRGB(190, 150, 100)
	for z = sd + 8, ud - 6, 16 do
		local x0 = (z + 4 > staffZ0) and staffX1 + 4 or -hw + 4
		local x1 = hw - 4
		for x = x0, x1, 14 do box(fr, m, "Racking", x - 0.2, 0, z - 2, x + 0.2, 15, z + 2, upright, Mat.Metal) end
		for _, y in { 0.3, 5.5, 10.5 } do
			box(fr, m, "RackBeam", x0, y, z - 2, x1, y + 0.4, z + 2, beam, Mat.Metal)
			for x = x0 + 1, x1 - 13, 14 do
				if rng:NextNumber() < 0.8 then
					local c = cardboard:Lerp(Color3.fromRGB(150, 110, 70), rng:NextNumber())
					box(fr, m, "Stock", x, y + 0.4, z - 1.6, x + 11.5, y + 0.4 + 2.5 + rng:NextNumber() * 1.5, z + 1.6, c, Mat.Cardboard, DECOR)
				end
			end
		end
	end
	wall(fr, m, "StaffRoomWall", -hw + 1, staffX1, 0, hc, staffZ0, 0.6, { { staffX1 - 8, staffX1 - 3, 0, 9 } }, def.wall, Mat.SmoothPlastic)
	box(fr, m, "StaffRoomWall", staffX1, 0, staffZ0, staffX1 + 0.6, hc, ud, def.wall, Mat.SmoothPlastic)
	local srSign = box(fr, m, "StaffRoomSign", staffX1 - 8, 9.4, staffZ0 - 0.4, staffX1 - 3, 10.8, staffZ0 - 0.3, C.dark, Mat.SmoothPlastic, DECOR)
	sign(srSign, Enum.NormalId.Front, "STAFF ROOM", Color3.new(1, 1, 1), "Gotham")
	local tx, tz = -hw + 12, ud - 11
	box(fr, m, "StaffTable", tx - 3, 2.6, tz - 2, tx + 3, 3, tz + 2, Color3.fromRGB(230, 230, 230), Mat.SmoothPlastic)
	box(fr, m, "StaffTable", tx - 0.4, 0, tz - 0.4, tx + 0.4, 2.6, tz + 0.4, C.dark, Mat.Metal)
	for _, o in { { -4.2, 0 }, { 4.2, 0 }, { 0, -3.4 }, { 0, 3.4 } } do
		box(fr, m, "StaffChair", tx + o[1] - 0.9, 0, tz + o[2] - 0.9, tx + o[1] + 0.9, 1.8, tz + o[2] + 0.9, def.accent, Mat.SmoothPlastic)
	end
	for i = 0, 5 do
		box(fr, m, "Locker", -hw + 2 + i * 2.2, 0, ud - 1.6, -hw + 4 + i * 2.2, 7, ud - 0.1, Color3.fromRGB(90, 110, 130), Mat.Metal)
	end
	box(fr, m, "Kitchenette", staffX1 - 9, 0, ud - 2.5, staffX1 - 1, 3.6, ud - 0.1, Color3.fromRGB(240, 240, 240), Mat.SmoothPlastic)

	-- loading door to the service yard (ground floor); named so delivery jobs can find it later
	local ld = box(fr, m, "LoadingDoor_" .. def.shop, hw - 20, 0, ud - 0.3, hw - 6, 12, ud, Color3.fromRGB(150, 155, 160), Mat.DiamondPlate)
	ld:SetAttribute("Shop", def.shop)
	if not groundFloor then ld.Name = "GoodsLift_" .. def.shop end

	m.Parent = parent
	return m
end

--------------------------------------------------------------------------------------------------
-- lifts and escalators (MallService gives them their behaviour at runtime)

local function buildElevator(E, parent, name, floors)
	local m = Instance.new("Model")
	m.Name = name
	local top = floors[#floors] + 11
	box(E, m, "Shaft", -5, floors[1] - 3, 4.6, 5, top, 5, C.glass, Mat.Glass, GLASS)
	box(E, m, "Shaft", -5, floors[1] - 3, -5, -4.6, top, 4.6, C.glass, Mat.Glass, GLASS)
	box(E, m, "Shaft", 4.6, floors[1] - 3, -5, 5, top, 4.6, C.glass, Mat.Glass, GLASS)
	local ops = {}
	for _, fy in floors do table.insert(ops, { -3.5, 3.5, fy, fy + 9 }) end
	wall(E, m, "Shaft", -5, 5, floors[1] - 3, top, -4.8, 0.4, ops, C.glass, Mat.Glass, GLASS)
	for _, c in { { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } } do
		box(E, m, "ShaftFrame", c[1] - 0.4, floors[1] - 3, c[2] - 0.4, c[1] + 0.4, top, c[2] + 0.4, C.metal, Mat.Metal)
	end
	box(E, m, "ShaftRoof", -5.4, top, -5.4, 5.4, top + 1, 5.4, C.metal, Mat.Metal)
	box(E, m, "Pit", -4.6, floors[1] - 3, -4.6, 4.6, floors[1] - 2, 4.6, C.dark, Mat.Concrete)
	local offsets = {}
	for i, fy in floors do
		table.insert(offsets, tostring(fy - floors[1]))
		box(E, m, "Gate_" .. i, -3.5, fy, -5, 3.5, fy + 9, -4.6, Color3.fromRGB(200, 220, 235), Mat.Glass, { Transparency = 0.55 })
		local call = box(E, m, "Call_" .. i, 4.2, fy + 4, -5.7, 5.2, fy + 5.4, -5.1, C.dark, Mat.SmoothPlastic)
		sign(call, Enum.NormalId.Front, "CALL", Color3.fromRGB(120, 220, 255), "GothamBold")
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance = 14; cd.Parent = call
	end
	local carCF = E * CFrame.new(0, floors[1] - 0.5, 0)
	local car = part(m, "Car", Vector3.new(9, 1, 9), carCF, C.metal, Mat.DiamondPlate, { Anchored = false })
	local function attach(p)
		p.Anchored = false; p.Massless = true
		local w = Instance.new("WeldConstraint"); w.Part0 = car; w.Part1 = p; w.Parent = p
	end
	attach(box(E, m, "CarWall", -4.5, floors[1], 3.9, 4.5, floors[1] + 9, 4.3, C.glass, Mat.Glass, GLASS))
	attach(box(E, m, "CarRail", -4.5, floors[1] + 3, 3.4, 4.5, floors[1] + 3.3, 3.8, C.metal, Mat.Metal))
	attach(box(E, m, "CarCeiling", -4.5, floors[1] + 9, -4.5, 4.5, floors[1] + 9.3, 4.5, C.ceiling, Mat.SmoothPlastic))
	for i = 1, #floors do
		local x = -3.6 + (i - 1) * 1.5
		local b = box(E, m, "Floor_" .. i, x - 0.6, floors[1] + 4, 3.6, x + 0.6, floors[1] + 5.2, 3.9, C.dark, Mat.SmoothPlastic)
		sign(b, Enum.NormalId.Front, i == 1 and "G" or tostring(i - 1), Color3.fromRGB(120, 220, 255), "GothamBold")
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance = 12; cd.Parent = b
		attach(b)
	end
	local rail = part(m, "Rail", Vector3.new(1, 1, 1), carCF, C.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local a0 = Instance.new("Attachment"); a0.Axis = Vector3.yAxis; a0.SecondaryAxis = Vector3.xAxis; a0.Parent = rail
	local a1 = Instance.new("Attachment"); a1.Axis = Vector3.yAxis; a1.SecondaryAxis = Vector3.xAxis; a1.Parent = car
	local lift = Instance.new("PrismaticConstraint")
	lift.Name = "Lift"
	lift.Attachment0 = a0; lift.Attachment1 = a1
	lift.ActuatorType = Enum.ActuatorType.Servo
	lift.ServoMaxForce = 1e8; lift.Speed = 10
	lift.LimitsEnabled = true; lift.LowerLimit = 0; lift.UpperLimit = floors[#floors] - floors[1]
	lift.TargetPosition = 0
	lift.Parent = m
	m:SetAttribute("Stops", table.concat(offsets, ","))
	CollectionService:AddTag(m, "HarbourElevator")
	m.Parent = parent
	return m
end

local function buildEscalator(f, parent, bottom: Vector3, top: Vector3, up: boolean)
	local m = Instance.new("Model")
	m.Name = up and "EscalatorUp" or "EscalatorDown"
	local steps, across, normal, d = ramp(f, m, "Steps", bottom, top, 7, 1, Color3.fromRGB(80, 82, 88), Mat.DiamondPlate)
	steps:SetAttribute("Conveyor", f:VectorToWorldSpace(d) * (up and Def.escalatorSpeed or -Def.escalatorSpeed))
	CollectionService:AddTag(steps, "HarbourEscalator")
	ramp(f, m, "Truss", bottom - normal * 1, top - normal * 1, 8, 2.5, C.metal, Mat.Metal)
	for _, s in { -1, 1 } do
		local off = across * s * 3.85
		ramp(f, m, "Balustrade", bottom + off + normal * 3.5, top + off + normal * 3.5, 0.3, 3.5, C.glass, Mat.Glass, CLEAR)
		ramp(f, m, "Handrail", bottom + off + normal * 3.9, top + off + normal * 3.9, 0.5, 0.4, Color3.fromRGB(20, 20, 20), Mat.Rubber)
	end
	for _, p in { bottom, top } do
		part(m, "CombPlate", Vector3.new(8, 0.1, 2), f * CFrame.new(p) * CFrame.fromMatrix(Vector3.zero, across, Vector3.yAxis), C.metal, Mat.DiamondPlate, DECOR)
	end
	m.Parent = parent
	return m
end

--------------------------------------------------------------------------------------------------
-- food court: kiosks along both sides of an arm, seating down the middle (frame f: arm runs along +Z)

local function buildFoodCourt(f, parent, H)
	local fc = Instance.new("Model")
	fc.Name = "FoodCourt"
	for _, k in Def.foodCourt do
		local biz = Businesses[k.biz]
		if not biz then warn("[MallBuilder] unknown food court business " .. k.biz); continue end
		-- kiosk frame: front at z'=0 facing the seating, running back 10 studs to the store wall
		local kf = f * CFrame.new(k.side * 14, H, k.z) * CFrame.Angles(0, k.side < 0 and -math.pi / 2 or math.pi / 2, 0)
		local km = Instance.new("Model"); km.Name = k.biz; km.Parent = fc
		box(kf, km, "KioskFloor", -12, 0, 0, 12, 0.08, 10, Color3.fromRGB(60, 60, 64), Mat.Slate, DECOR)
		for _, s in { -1, 1 } do box(kf, km, "KioskWall", s * 12 - 0.3, 0, 0, s * 12 + 0.3, 10, 10, k.accent, Mat.SmoothPlastic) end
		box(kf, km, "KioskCanopy", -12.5, 10, -1.5, 12.5, 12.5, 10, k.accent, Mat.SmoothPlastic)
		local sg = box(kf, km, "KioskSign", -9, 10.4, -1.8, 9, 12.1, -1.5, Color3.new(1, 1, 1), Mat.SmoothPlastic, DECOR)
		sign(sg, Enum.NormalId.Front, string.upper(biz.name), k.accent, "GothamBlack")
		box(kf, km, "CanopyLED", -12.5, 9.8, -1.6, 12.5, 10, 10, Color3.fromRGB(255, 245, 225), Mat.Neon, DECOR)
		box(kf, km, k.counter, -8, 0, 0, 8, 4, 2, Color3.fromRGB(245, 245, 245), Mat.Marble)
		box(kf, km, "CounterFront", -8, 0.5, -0.1, 8, 3.5, 0, k.accent, Mat.SmoothPlastic, DECOR)
		for i, name in k.stations do
			local x = -8 + (i - 1) * 8
			box(kf, km, name, x - 2.5, 0, 6.5, x + 2.5, 4, 9.5, C.metal, Mat.Metal)
			box(kf, km, "StationLight", x - 2.5, 4, 6.5, x + 2.5, 4.2, 9.5, k.accent, Mat.Neon, DECOR)
		end
		local menu = {}
		for _, r in biz.menu do
			local out = Recipes[r] and Items[Recipes[r].output]
			if out then table.insert(menu, string.format("%s  $%d", out.name, math.floor(out.price * biz.counterMultiplier))) end
		end
		board(kf, km, "MenuBoard", -10, 5.5, 9.3, 10, 9.5, table.concat(menu, "\n"), "MENU")
	end
	-- seating
	local wood = Color3.fromRGB(170, 125, 80)
	for z = 100, 170, 10 do
		for _, x in { -5, 5 } do
			post(f, fc, "Table", x, H, z, 2.8, 0.6, C.metal, Mat.Metal)
			part(fc, "TableTop", Vector3.new(0.3, 4, 4), f * CFrame.new(x, H + 2.95, z) * CFrame.Angles(0, 0, math.pi / 2), wood, Mat.Wood, nil, Enum.PartType.Cylinder)
			for _, o in { { 2.8, 0 }, { -2.8, 0 }, { 0, 2.8 }, { 0, -2.8 } } do
				post(f, fc, "Stool", x + o[1], H, z + o[2], 1.8, 1.4, wood, Mat.Wood)
			end
		end
	end
	for _, z in { 104, 136, 168 } do
		local lamp = box(f, fc, "Pendant", -1.5, 2 * H - 4, z - 1.5, 1.5, 2 * H - 3.4, z + 1.5, Color3.fromRGB(255, 240, 200), Mat.Neon, DECOR)
		local l = Instance.new("PointLight"); l.Range = 36; l.Brightness = 1.2; l.Parent = lamp
	end
	local fs = box(f, fc, "FoodCourtSign", -12, H + 14, 94, 12, H + 18, 94.4, C.bronze, Mat.Metal, DECOR)
	sign(fs, Enum.NormalId.Front, "FOOD COURT", Color3.new(1, 1, 1), "GothamBlack")
	-- staff can restock here without leaving the mall
	box(f, fc, "Shop_food_wholesale", -23, H, 162, -19, H + 4, 170, C.bronze, Mat.Wood)
	local ss = box(f, fc, "SuppliesSign", -23, H + 6, 161.6, -19, H + 7.5, 161.9, C.dark, Mat.SmoothPlastic, DECOR)
	sign(ss, Enum.NormalId.Front, "STAFF SUPPLIES", Color3.new(1, 1, 1), "GothamBold")
	fc.Parent = parent
	return fc
end

-- Invisible marker used by the shopper NPCs and mall jobs.
local function node(parent, name, cf: CFrame, attrs)
	local p = part(parent, name, Vector3.new(1, 1, 1), cf, Color3.new(1, 0, 1), Mat.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	for k, v in attrs or {} do p:SetAttribute(k, v) end
	return p
end

--------------------------------------------------------------------------------------------------
-- the mall building

-- W x D is the whole site; the building is set back so canopies, planters and the plaza stay on the site.
local function buildMall(M, siteW, siteD, root)
	local W, D = siteW - 2 * SETBACK, siteD - 2 * SETBACK
	local H, CW, G = Def.floorHeight, Def.concourseWidth, Def.galleryWidth
	local VW, T, ST = CW - 2 * G, 2, 1.5
	local hc = H - ST
	local structure = Instance.new("Folder"); structure.Name = "Structure"; structure.Parent = root
	local storesFolder = Instance.new("Folder"); storesFolder.Name = "Stores"; storesFolder.Parent = root
	local moving = Instance.new("Folder"); moving.Name = "Transport"; moving.Parent = root

	local R = H / math.tan(math.rad(30)) -- escalator run
	local VL = math.min(W / 2 - 30, 6 + R + 70)
	local hasAtrium = VL > 6 + R + 8
	local voids = hasAtrium and { { 6, -VW / 2, VL, VW / 2 }, { -VL, -VW / 2, -6, VW / 2 } } or {}
	local zN = CW / 2 + 14
	local shafts = { { -5, zN - 5, 5, zN + 5 }, { -5, -zN - 5, 5, -zN + 5 } }

	-- plaza around the building, floors, slabs and roof with skylight
	box(M, structure, "Plaza", -siteW / 2, -0.6, -siteD / 2, siteW / 2, -0.05, siteD / 2, Color3.fromRGB(215, 205, 190), Mat.Pavement)
	slab(M, structure, "Floor", -W / 2, -D / 2, W / 2, D / 2, -1, 0, shafts, C.floor, Mat.Marble)
	for _, s in { -1, 1 } do
		box(M, structure, "Inlay", -W / 2 + T, 0, s * (CW / 2 - 4) - 0.5, W / 2 - T, 0.05, s * (CW / 2 - 4) + 0.5, C.inlay, Mat.Marble, DECOR)
		box(M, structure, "Inlay", s * (CW / 2 - 4) - 0.5, 0, -D / 2 + T, s * (CW / 2 - 4) + 0.5, 0.05, -CW / 2 + 4, C.inlay, Mat.Marble, DECOR)
		box(M, structure, "Inlay", s * (CW / 2 - 4) - 0.5, 0, CW / 2 - 4, s * (CW / 2 - 4) + 0.5, 0.05, D / 2 - T, C.inlay, Mat.Marble, DECOR)
	end
	-- stairs in the north and south arms (24 steps, 1 stud rise, 1.4 tread); south is the north one turned round
	local stairX0, stairX1, stairZ0, stairRun = 10, 16, 48, 24 * 1.4
	local stairFrames = { M, M * CFrame.Angles(0, math.pi, 0) }
	local l2holes = table.clone(shafts)
	table.insert(l2holes, { stairX0, stairZ0, stairX1, stairZ0 + stairRun })
	table.insert(l2holes, { -stairX1, -stairZ0 - stairRun, -stairX0, -stairZ0 })
	for _, v in voids do table.insert(l2holes, v) end
	slab(M, structure, "Level1Floor", -W / 2 + T, -D / 2 + T, W / 2 - T, D / 2 - T, H - ST, H, l2holes, C.gallery, Mat.Marble)
	local sky = hasAtrium and { -VL, -CW / 2, VL, CW / 2 } or nil
	slab(M, structure, "Roof", -W / 2, -D / 2, W / 2, D / 2, 2 * H, 2 * H + ST, sky and { sky } or {}, C.exteriorDark, Mat.Concrete)

	if hasAtrium then
		-- pitched glass skylight with a steel grid, like the reference atrium
		local b, rise = 2 * H + ST, 9
		for _, s in { -1, 1 } do
			ramp(M, structure, "Skylight", Vector3.new(0, b, s * CW / 2), Vector3.new(0, b + rise, 0), 2 * VL, 0.4, C.glass, Mat.Glass, { Transparency = 0.6, Reflectance = 0.3 })
			for x = -VL, VL + 0.1, 12 do
				local rafter = ramp(M, structure, "SkylightBeam", Vector3.new(x, b + 0.05, s * CW / 2), Vector3.new(x, b + rise + 0.05, 0), 0.6, 0.6, C.metal, Mat.Metal)
				rafter.CanCollide = false
			end
		end
		box(M, structure, "SkylightRidge", -VL, b + rise - 0.3, -0.4, VL, b + rise + 0.3, 0.4, C.metal, Mat.Metal)
		for _, x in { -VL, VL } do
			wedge(M, structure, "SkylightGable", Vector3.new(0.4, rise, CW / 2), CFrame.new(x, b + rise / 2, -CW / 4), C.glass, Mat.Glass, GLASS)
			wedge(M, structure, "SkylightGable", Vector3.new(0.4, rise, CW / 2), CFrame.new(x, b + rise / 2, CW / 4) * CFrame.Angles(0, math.pi, 0), C.glass, Mat.Glass, GLASS)
		end

		-- atrium: white bulkheads, balustrades, escalators crossing at the central bridge
		for _, v in voids do
			for _, z in { v[2], v[4] } do
				box(M, structure, "Bulkhead", v[1], H - 4, z - 0.3, v[3], H - ST, z + 0.3, C.ceiling, Mat.SmoothPlastic)
				box(M, structure, "BulkheadLED", v[1], H - 4.3, z - 0.3, v[3], H - 4, z + 0.3, Color3.fromRGB(255, 245, 225), Mat.Neon, DECOR)
				railing(M, structure, v[1], z + (z > 0 and 0.2 or -0.2), v[3], z + (z > 0 and 0.2 or -0.2), H)
			end
			local outer = math.abs(v[1]) > math.abs(v[3]) and v[1] or v[3]
			local inner = outer == v[1] and v[3] or v[1]
			local so = outer > 0 and 1 or -1
			railing(M, structure, outer + so * 0.2, v[2], outer + so * 0.2, v[4], H)
			for _, seg in { { -VW / 2, -10.5 }, { -1.5, 1.5 }, { 10.5, VW / 2 } } do
				railing(M, structure, inner - so * 0.2, seg[1], inner - so * 0.2, seg[2], H)
			end
			buildEscalator(M, moving, Vector3.new(so * (6 + R), 0, 6), Vector3.new(so * 6, H, 6), true)
			buildEscalator(M, moving, Vector3.new(so * (6 + R), 0, -6), Vector3.new(so * 6, H, -6), false)
			planter(M, structure, so * (6 + R + 14), 0, 0, 8, 8, true)
		end
	end

	for _, sf in stairFrames do
		for i = 1, 24 do
			local z = stairZ0 + (i - 1) * 1.4
			box(sf, structure, "Stair", stairX0, 0, z, stairX1, i, z + 1.4, C.gallery, Mat.Marble)
			box(sf, structure, "StairNosing", stairX0, i - 0.05, z, stairX1, i + 0.02, z + 0.25, C.inlay, Mat.Metal, DECOR)
		end
		for _, x in { stairX0 - 0.15, stairX1 + 0.15 } do
			ramp(sf, structure, "StairRail", Vector3.new(x, 1 + 3.5, stairZ0), Vector3.new(x, 24 + 3.5, stairZ0 + stairRun), 0.3, 3.5, C.glass, Mat.Glass, CLEAR)
			ramp(sf, structure, "StairHandrail", Vector3.new(x, 1 + 3.85, stairZ0), Vector3.new(x, 24 + 3.85, stairZ0 + stairRun), 0.5, 0.35, C.metal, Mat.Metal)
		end
		railing(sf, structure, stairX0 - 0.2, stairZ0, stairX0 - 0.2, stairZ0 + stairRun, H)
		railing(sf, structure, stairX1 + 0.2, stairZ0, stairX1 + 0.2, stairZ0 + stairRun, H)
		railing(sf, structure, stairX0, stairZ0 - 0.2, stairX1, stairZ0 - 0.2, H)
		local sg = box(sf, structure, "StairSign", stairX0, H - 4, stairZ0 - 0.7, stairX1, H - 2.4, stairZ0 - 0.4, C.dark, Mat.SmoothPlastic, DECOR)
		sign(sg, Enum.NormalId.Front, "STAIRS  LEVEL 1", Color3.new(1, 1, 1), "GothamBold")

		-- toilets at the end of each upper arm
		local tz0, tz1 = D / 2 - T - 34, D / 2 - T
		wall(sf, structure, "ToiletWall", -CW / 2, -4, H, 2 * H - ST, tz0, 0.6, { { -14, -9, H, H + 9 } }, C.ceiling, Mat.SmoothPlastic)
		box(sf, structure, "ToiletWall", -4.6, H, tz0, -4, 2 * H - ST, tz1, C.ceiling, Mat.SmoothPlastic)
		box(sf, structure, "ToiletFloor", -CW / 2, H, tz0, -4.6, H + 0.06, tz1, Color3.fromRGB(200, 215, 225), Mat.Slate)
		local ts = box(sf, structure, "ToiletSign", -15, H + 9.4, tz0 - 0.4, -8, H + 11, tz0 - 0.3, C.dark, Mat.SmoothPlastic, DECOR)
		sign(ts, Enum.NormalId.Front, "TOILETS", Color3.new(1, 1, 1), "GothamBold")
		for i = 0, 3 do
			local x = -CW / 2 + 1 + i * 4.6
			box(sf, structure, "Cubicle", x, H, tz1 - 7, x + 0.2, H + 7, tz1, C.metal, Mat.SmoothPlastic)
			box(sf, structure, "CubicleDoor", x + 0.2, H + 0.5, tz1 - 7, x + 4.6, H + 7, tz1 - 6.8, C.bronze, Mat.SmoothPlastic)
			box(sf, structure, "Toilet", x + 1.6, H, tz1 - 2.6, x + 3.2, H + 1.6, tz1 - 0.2, Color3.new(1, 1, 1), Mat.SmoothPlastic)
		end
		box(sf, structure, "Basins", -9.6, H, tz0 + 4, -5, H + 3.4, tz0 + 20, Color3.fromRGB(240, 240, 240), Mat.Marble)
		box(sf, structure, "Mirror", -5.2, H + 4, tz0 + 4, -4.9, H + 8, tz0 + 20, C.glass, Mat.Glass, { Reflectance = 0.6 })
	end

	buildFoodCourt(stairFrames[1], structure, H)
	local nodes = Instance.new("Folder"); nodes.Name = "Nodes"; nodes.Parent = root

	-- mall management office (south arm, ground floor): sign up as cleaner or security here
	local mo = stairFrames[2]
	for i, job in { "mall_cleaner", "mall_security" } do
		local z = 96 + i * 8
		box(mo, structure, "JobCentre_" .. job, -23, 0, z, -18, 4, z + 3, C.bronze, Mat.Wood)
	end
	local ms = box(mo, structure, "OfficeSign", -23.4, 7, 103, -23.1, 9.5, 120, C.dark, Mat.SmoothPlastic, DECOR)
	sign(ms, Enum.NormalId.Right, "MALL MANAGEMENT - JOBS", Color3.new(1, 1, 1), "GothamBold")

	-- security patrol checkpoints, visited in order by the security guard
	local checkpoints = {
		Vector3.new(-W / 2 + 20, 0, -21), Vector3.new(-21, 0, 120), Vector3.new(W / 2 - 20, 0, 21), Vector3.new(21, 0, -120),
		Vector3.new(W / 2 - 20, H, -21), Vector3.new(-21, H, -120), Vector3.new(-W / 2 + 20, H, 21),
	}
	for i, p in checkpoints do
		local post = box(M, structure, "SecurityPoint_" .. i, p.X - 0.6, p.Y, p.Z - 0.6, p.X + 0.6, p.Y + 5, p.Z + 0.6, Color3.fromRGB(30, 60, 140), Mat.Metal)
		box(M, structure, "CardReader", p.X - 0.4, p.Y + 3.5, p.Z - 0.7, p.X + 0.4, p.Y + 4.5, p.Z + 0.7, Color3.fromRGB(80, 255, 120), Mat.Neon, DECOR)
		post:SetAttribute("Checkpoint", i)
	end

	-- litter appears at these spots while a cleaner is on shift
	for _, y in { 0, H } do
		for x = -W / 2 + 30, W / 2 - 30, 40 do
			for _, z in { -18, 18 } do node(nodes, "LitterSpot", M * CFrame.new(x, y, z)) end
		end
		for z = 50, 170, 40 do node(nodes, "LitterSpot", M * CFrame.new(-10.5, y, z)); node(nodes, "LitterSpot", M * CFrame.new(10.5, y, -z)) end
	end

	-- ATMs in each arm (MallService turns parts named ATM_<n> into deposit / withdraw points)
	for i, sf in stairFrames do
		box(sf, structure, "ATM_" .. i, -23, 0, 28, -20, 7, 31, C.dark, Mat.Metal)
		box(sf, structure, "ATMScreen", -20, 3.5, 28.4, -19.9, 6, 30.6, Color3.fromRGB(60, 160, 255), Mat.Neon, DECOR)
		local as = box(sf, structure, "ATMSign", -23, 7, 28, -20, 8.2, 31, C.led, Mat.SmoothPlastic, DECOR)
		sign(as, Enum.NormalId.Right, "CASH", Color3.new(1, 1, 1), "GothamBold")
	end

	-- lifts in the north and south arms
	buildElevator(M * CFrame.new(0, 0, zN), moving, "LiftNorth", { 0, H })
	buildElevator(M * CFrame.new(0, 0, -zN) * CFrame.Angles(0, math.pi, 0), moving, "LiftSouth", { 0, H })

	-- concourse lighting under the upper galleries
	for _, s in { -1, 1 } do
		box(M, structure, "ConcourseLight", -W / 2 + T + 2, H - ST - 0.3, s * (CW / 2 - 4) - 0.6, W / 2 - T - 2, H - ST, s * (CW / 2 - 4) + 0.6, Color3.fromRGB(255, 248, 235), Mat.Neon, DECOR)
	end
	for x = -W / 2 + 40, W / 2 - 40, 80 do
		local p = box(M, structure, "ConcourseLamp", x - 1, H - ST - 0.4, -1, x + 1, H - ST - 0.3, 1, Color3.new(1, 1, 1), Mat.Neon, DECOR)
		if p and not (hasAtrium and math.abs(x) < VL) then
			local l = Instance.new("SurfaceLight"); l.Face = Enum.NormalId.Bottom; l.Range = 50; l.Angle = 160; l.Brightness = 1.5; l.Parent = p
		end
		if not (hasAtrium and math.abs(x) < VL + 4) then
			for _, s in { -1, 1 } do
				box(M, structure, "Bench", x - 4, 0, s * 12 - 1, x + 4, 1.8, s * 12 + 1, C.bronze, Mat.Wood)
				planter(M, structure, x + 10, 0, s * 12, 4, 4, false)
			end
		end
	end

	-- outer walls with entrances; east side also opens onto the car park bridge
	local wallTop = 2 * H + 6
	local doorW, doorH = CW / 2 - 4, 16
	local ground = { -doorW, doorW, 0, doorH }
	local bridgeOp = { -8, 8, H, H + 12 }
	local sides = {
		{ name = "West", f = M * CFrame.new(-W / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), len = D, ops = { ground } },
		{ name = "East", f = M * CFrame.new(W / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), len = D, ops = { ground, bridgeOp } },
		{ name = "North", f = M * CFrame.new(0, 0, D / 2), len = W, ops = { ground } },
		{ name = "South", f = M * CFrame.new(0, 0, -D / 2) * CFrame.Angles(0, math.pi, 0), len = W, ops = { ground } },
	}
	-- in each side frame: +Z points out of the building, X runs along the wall
	for _, sd in sides do
		local f, half = sd.f, sd.len / 2
		wall(f, structure, "OuterWall", -half, half, 0, wallTop, -T / 2, T, sd.ops, C.exterior, Mat.Limestone)
		wall(f, structure, "Band", -half, half, H - 2, H + 1, 0.3, 0.6, sd.ops, C.exteriorDark, Mat.Limestone)
		wall(f, structure, "LEDBand", -half, half, H + 1, H + 1.5, 0.15, 0.3, sd.ops, C.led, Mat.Neon, DECOR)
		wall(f, structure, "Coping", -half, half, wallTop - 1, wallTop, 0.3, 0.6, {}, C.exteriorDark, Mat.Limestone)
		for u = -half + 24, half - 24, 24 do
			if math.abs(u) > doorW + 8 then
				box(f, structure, "Reveal", u - 0.3, 0, 0, u + 0.3, wallTop - 1, 0.25, C.exteriorDark, Mat.Limestone, DECOR)
				if (u // 24) % 2 == 0 then
					box(f, structure, "Window", u + 3, H + 5, 0, u + 21, H + 16, 0.2, C.glass, Mat.Glass, { Reflectance = 0.4 })
				end
			end
		end

		-- bronze-framed glass entrance tower with canopy, sign and planters
		local TW, TD, TH = 2 * doorW + 12, 6, 2 * H + 14
		local tops = { { -doorW, doorW, 0, doorH } }
		if sd.name == "East" then table.insert(tops, bridgeOp) end
		wall(f, structure, "CurtainWall", -TW / 2, TW / 2, 0, TH, TD, 0.4, tops, C.glass, Mat.Glass, { Transparency = 0.25, Reflectance = 0.35 })
		for _, s in { -1, 1 } do box(f, structure, "CurtainWall", s * TW / 2 - 0.2, 0, 0, s * TW / 2 + 0.2, TH, TD, C.glass, Mat.Glass, { Transparency = 0.25, Reflectance = 0.35 }) end
		for u = -TW / 2, TW / 2 + 0.1, 8 do wall(f, structure, "Mullion", u - 0.3, u + 0.3, 0, TH, TD + 0.3, 0.4, tops, C.bronze, Mat.Metal) end
		-- entrance: fixed side lights and transom with a pair of automatic doors behind them
		for _, s in { -1, 1 } do
			box(f, structure, "SideLight", s * 8, 0, TD - 0.2, s * doorW, 12, TD + 0.2, C.glass, Mat.Glass, GLASS)
			box(f, structure, "Mullion", s * 8 - 0.3, 0, TD + 0.2, s * 8 + 0.3, doorH, TD + 0.6, C.bronze, Mat.Metal)
		end
		box(f, structure, "Transom", -doorW, 12.6, TD - 0.2, doorW, doorH, TD + 0.2, C.glass, Mat.Glass, GLASS)
		autoDoor(f, structure, -8, 8, 0, 12, TD - 0.6, C.bronze)
		node(nodes, "EntranceOut", f * CFrame.new(0, 0, TD + 10), { Level = 0 })
		node(nodes, "EntranceIn", f * CFrame.new(0, 0, -T - 8), { Level = 0 })
		if sd.name == "East" then -- footbridge doors on the upper level
			box(f, structure, "Transom", -8, H + 10.6, TD - 0.2, 8, H + 12, TD + 0.2, C.glass, Mat.Glass, GLASS)
			autoDoor(f, structure, -8, 8, H, H + 10, TD - 0.6, C.bronze)
			node(nodes, "EntranceOut", f * CFrame.new(0, H, TD + 10), { Level = 1 })
			node(nodes, "EntranceIn", f * CFrame.new(0, H, -T - 8), { Level = 1 })
		end
		for y = doorH, TH, 12 do wall(f, structure, "Transom", -TW / 2, TW / 2, y - 0.3, y + 0.3, TD + 0.3, 0.4, tops, C.bronze, Mat.Metal) end
		box(f, structure, "TowerRoof", -TW / 2 - 1, TH, -T, TW / 2 + 1, TH + 1.5, TD + 1, C.bronze, Mat.Metal)
		box(f, structure, "TowerFloor", -TW / 2, -1, 0, TW / 2, 0, TD, C.floor, Mat.Marble)
		local name = box(f, structure, "MallSign", -18, TH - 10, TD + 0.5, 18, TH - 3, TD + 1, C.bronze, Mat.Metal)
		sign(name, Enum.NormalId.Back, Def.name, Color3.fromRGB(255, 250, 235), "GothamBlack")
		box(f, structure, "Canopy", -doorW - 4, doorH + 1, TD, doorW + 4, doorH + 1.6, TD + 14, C.glass, Mat.Glass, { Transparency = 0.4, Reflectance = 0.3 })
		box(f, structure, "CanopyBeam", -doorW - 4, doorH + 0.6, TD + 13.4, doorW + 4, doorH + 1.6, TD + 14, C.bronze, Mat.Metal)
		for _, s in { -1, 1 } do
			post(f, structure, "CanopyColumn", s * (doorW + 3), 0, TD + 13.4, doorH + 1, 1, C.bronze, Mat.Metal)
			planter(f, structure, s * (doorW + 14), 0, TD + 10, 10, 6, true)
			post(f, structure, "LampPost", s * (doorW + 26), 0, TD + 12, 14, 0.5, C.dark, Mat.Metal)
			local lamp = box(f, structure, "LampHead", s * (doorW + 26) - 1, 14, TD + 11, s * (doorW + 26) + 1, 14.6, TD + 13, Color3.fromRGB(255, 240, 200), Mat.Neon, DECOR)
			if lamp then local l = Instance.new("PointLight"); l.Range = 30; l.Brightness = 1; l.Parent = lamp end
		end
	end

	-- rooftop plant
	local rng = Random.new(42)
	for _ = 1, 8 do
		local x = (rng:NextNumber() - 0.5) * (W - 60)
		local z = (rng:NextNumber() > 0.5 and 1 or -1) * (CW / 2 + 20 + rng:NextNumber() * (D / 2 - CW / 2 - 50))
		box(M, structure, "RoofPlant", x - 6, 2 * H + ST, z - 4, x + 6, 2 * H + ST + 5, z + 4, Color3.fromRGB(170, 172, 175), Mat.DiamondPlate)
	end

	-- store units: frontage onto the concourse, full depth back to the outer wall
	local qw = W / 2 - T - CW / 2
	local ud = D / 2 - T - CW / 2
	-- units per quadrant: the target width, but never fewer than needed to fit every store (4 quadrants x 2 levels)
	local n = math.max(1, math.floor(qw / Def.unitWidth + 0.5), math.ceil(#Def.stores / 8))
	local uw = qw / n
	if uw < 50 then warn(string.format("[MallBuilder] stores are only %d studs wide; enlarge MallSite", uw)) end
	local units = {}
	for level = 0, 1 do
		for _, sz in { 1, -1 } do
			for _, sx in { -1, 1 } do
				for i = (sx < 0 and n or 1), (sx < 0 and 1 or n), (sx < 0 and -1 or 1) do
					local x = sx * (CW / 2 + (i - 0.5) * uw)
					local fr = M * CFrame.new(x, level * H, sz * CW / 2) * (sz < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity)
					table.insert(units, { fr = fr, ground = level == 0, x = x, sz = sz })
				end
			end
		end
	end
	local placed = {}
	for i, u in units do
		local def = Def.stores[i]
		if def and not Shops[def.shop] then warn("[MallBuilder] unknown shop " .. def.shop); def = nil end
		buildStore(storesFolder, u.fr, uw, ud, hc, def, u.ground)
		if def then
			placed[def.shop] = true
			local a = { Shop = def.shop, Level = u.ground and 0 or 1 }
			node(nodes, "StoreFront", u.fr * CFrame.new(0, 0, -6), a)
			node(nodes, "StoreInside", u.fr * CFrame.new(0, 0, 5), a)
			node(nodes, "StoreTill", u.fr * CFrame.new(uw / 2 - 20, 0, 8), a)
			if u.ground then -- roller door and dock on the outside wall
				local back = M * CFrame.new(u.x, 0, u.sz * D / 2) * (u.sz < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity)
				local rx = uw / 2 - 13 -- both frames are mirrored the same way on the south side
				box(back, structure, "RollerDoor", rx - 7, 0, 0, rx + 7, 12, 0.3, Color3.fromRGB(170, 172, 176), Mat.DiamondPlate)
				box(back, structure, "DockLight", rx - 7, 12.5, 0, rx + 7, 13, 0.4, Color3.fromRGB(255, 200, 60), Mat.Neon, DECOR)
				for _, s in { -1, 1 } do box(back, structure, "DockBumper", rx + s * 6 - 0.5, 0, 0, rx + s * 6 + 0.5, 3, 0.8, Color3.fromRGB(240, 200, 0), Mat.Rubber) end
			end
		end
	end
	local lines = { "GROUND FLOOR" }
	for i, u in units do
		if i == #units / 2 + 1 then table.insert(lines, ""); table.insert(lines, "LEVEL 1") end
		local def = Def.stores[i]
		if def and Shops[def.shop] then table.insert(lines, "  " .. Shops[def.shop].name) end
	end
	table.insert(lines, ""); table.insert(lines, "Lifts and stairs: north and south arms")
	local listing = table.concat(lines, "\n")
	for _, sd in sides do -- inside each entrance, beside the doors
		board(sd.f, structure, "Directory", doorW - 4, 0, -T - 10.6, doorW + 2, 9, listing, Def.name)
	end
	for _, sf in stairFrames do -- upper level, at the top of the stairs
		board(sf, structure, "Directory", 18, H, stairZ0 + stairRun + 6, 23, H + 8, listing, Def.name)
	end

	for _, s in Def.stores do
		if not placed[s.shop] then warn("[MallBuilder] no room for " .. s.shop .. "; enlarge MallSite or lower unitWidth") end
	end
end

--------------------------------------------------------------------------------------------------
-- multi-storey car park: +X faces away from the mall, the bridge lands on the -X side at z = bz

local function buildCarPark(CF, Wc, Dc, root, bridgeDeck, bz)
	local h, N, RW = Def.carParkDeckHeight, Def.carParkLevels, Def.carParkRampWidth
	local Lr = h / math.tan(math.rad(Def.carParkRampDegrees))
	local rx1 = Wc / 2 - 2
	local rx0 = rx1 - RW
	local rz0, rz1 = -Lr / 2, Lr / 2
	local hole = { rx0, rz0, rx1, rz1 }
	local liftX, liftZ = -Wc / 2 + 9, bz + 22
	local liftHole = { liftX - 5, liftZ - 5, liftX + 5, liftZ + 5 }
	local concrete, band, paint = C.deck, C.led, C.lines
	local m = Instance.new("Model"); m.Name = "CarPark"; m.Parent = root

	-- parking rows (x ranges) between drive lanes, bays along z
	local rows = {}
	local x = -Wc / 2 + 2
	table.insert(rows, { x, x + 18, wall = true }); x += 18 + 24
	while x + 36 + 24 <= rx0 do
		table.insert(rows, { x, x + 18 }); table.insert(rows, { x + 18, x + 36, pair = true }); x += 36 + 24
	end
	if x + 18 + 24 <= rx0 then table.insert(rows, { x, x + 18 }) end
	local zA, zB = -Dc / 2 + 28, Dc / 2 - 28

	for lvl = 0, N - 1 do
		local y = lvl * h
		if lvl == 0 then
			slab(CF, m, "Deck", -Wc / 2, -Dc / 2, Wc / 2, Dc / 2, -1, 0, { liftHole }, concrete, Mat.Asphalt)
		else
			slab(CF, m, "Deck", -Wc / 2, -Dc / 2, Wc / 2, Dc / 2, y - 1, y, { hole, liftHole }, concrete, Mat.Concrete)
			box(CF, m, "DeckEdge", -Wc / 2 - 0.3, y - 1.6, -Dc / 2 - 0.3, Wc / 2 + 0.3, y - 1, Dc / 2 + 0.3, C.exteriorDark, Mat.Concrete)
		end
		-- perimeter: parapets on decks (bridge gap on the mall side); low kerbs at ground with open ends
		local ph = lvl == 0 and 1 or 3.5
		local westOps = (lvl == bridgeDeck) and { { bz - 8, bz + 8, y, y + ph + 1 } } or {}
		wallZ(CF, m, "Parapet", -Dc / 2, Dc / 2, y, y + ph, -Wc / 2 + 0.5, 1, westOps, concrete, Mat.Concrete)
		wallZ(CF, m, "Parapet", -Dc / 2, Dc / 2, y, y + ph, Wc / 2 - 0.5, 1, {}, concrete, Mat.Concrete)
		if lvl > 0 then
			for _, s in { -1, 1 } do wall(CF, m, "Parapet", -Wc / 2, Wc / 2, y, y + ph, s * (Dc / 2 - 0.5), 1, {}, concrete, Mat.Concrete) end
			wallZ(CF, m, "ParapetBand", -Dc / 2, Dc / 2, y + 2.6, y + 3.2, -Wc / 2 - 0.1, 0.3, westOps, band, Mat.Neon, DECOR)
			wallZ(CF, m, "ParapetBand", -Dc / 2, Dc / 2, y + 2.6, y + 3.2, Wc / 2 + 0.1, 0.3, {}, band, Mat.Neon, DECOR)
		end
		-- ramp guards: inner rail along the ramp well, barriers where a car could drop or drive under
		box(CF, m, "RampRail", rx0 - 1, y, rz0, rx0, y + 3.5, rz1, Color3.fromRGB(240, 200, 0), Mat.Concrete)
		if lvl == 0 then box(CF, m, "RampBarrier", rx0, y, rz1 - 1, rx1, y + 3.5, rz1, Color3.fromRGB(240, 200, 0), Mat.Concrete) end
		if lvl == N - 1 then box(CF, m, "RampBarrier", rx0, y, rz0, rx1, y + 3.5, rz0 + 1, Color3.fromRGB(240, 200, 0), Mat.Concrete) end
		-- bays, walkway, columns, lights
		for ri, r in rows do
			for z = zA, zB + 0.1, 10 do
				local walkway = ri == 1 and z > bz - 14 and z < bz + 34
				if not walkway then box(CF, m, "BayLine", r[1] + 0.5, y, z - 0.2, r[2] - 0.5, y + 0.05, z + 0.2, paint, Mat.SmoothPlastic, DECOR) end
			end
			if lvl < N - 1 and (r.wall or r.pair) then
				local cx = r.wall and r[1] + 1 or r[1]
				for z = zA, zB + 0.1, 30 do box(CF, m, "Column", cx - 0.9, y, z - 0.9, cx + 0.9, y + h - 1, z + 0.9, concrete, Mat.Concrete) end
			end
		end
		box(CF, m, "Walkway", -Wc / 2 + 2, y, bz - 14, -Wc / 2 + 20, y + 0.05, bz + 34, Color3.fromRGB(60, 140, 90), Mat.SmoothPlastic, DECOR)
		if lvl < N - 1 then
			for z = rz0, rz1 + 0.1, 30 do box(CF, m, "Column", rx0 - 2.8, y, z - 0.9, rx0 - 1, y + h - 1, z + 0.9, concrete, Mat.Concrete) end
			for _, r in rows do
				if not r.pair then
					box(CF, m, "DeckLight", r[2] + 11.5, y + h - 1.3, zA, r[2] + 12.5, y + h - 1, zB, Color3.fromRGB(255, 250, 235), Mat.Neon, DECOR)
				end
			end
		else
			for z = zA, zB, 60 do
				post(CF, m, "LampPost", 0, y, z, 16, 0.5, C.dark, Mat.Metal)
				local lamp = box(CF, m, "LampHead", -1.5, y + 16, z - 1, 1.5, y + 16.6, z + 1, Color3.fromRGB(255, 240, 200), Mat.Neon, DECOR)
				if lamp then local l = Instance.new("PointLight"); l.Range = 40; l.Brightness = 1; l.Parent = lamp end
			end
		end
	end

	-- straight two-way ramps stacked in one well; each climbs one deck along +Z
	for lvl = 0, N - 2 do
		local xm = (rx0 + rx1) / 2
		local p0, p1 = Vector3.new(xm, lvl * h, rz0), Vector3.new(xm, (lvl + 1) * h, rz1)
		ramp(CF, m, "Ramp", p0, p1, RW, 1, concrete, Mat.Concrete)
		for _, s in { -1, 1 } do
			local off = Vector3.new(s * (RW / 2 - 0.5), 0, 0)
			ramp(CF, m, "RampWall", p0 + off + Vector3.new(0, 3.5, 0), p1 + off + Vector3.new(0, 3.5, 0), 1, 3.5, concrete, Mat.Concrete)
		end
		ramp(CF, m, "RampLine", p0 + Vector3.new(0, 0.05, 0), p1 + Vector3.new(0, 0.05, 0), 0.4, 0.05, Color3.fromRGB(240, 200, 0), Mat.SmoothPlastic, DECOR)
	end

	-- entrances, height bars and the big P sign
	for _, s in { -1, 1 } do
		local z = s * (Dc / 2 - 1)
		for _, px in { -Wc / 2 + 1, rx0 - 2 } do post(CF, m, "BarPost", px, 0, z, 11, 0.6, Color3.fromRGB(240, 200, 0), Mat.Metal) end
		local bar = box(CF, m, "HeightBar", -Wc / 2 + 1, 10.4, z - 0.3, rx0 - 2, 11, z + 0.3, Color3.fromRGB(240, 200, 0), Mat.Metal)
		sign(bar, s > 0 and Enum.NormalId.Back or Enum.NormalId.Front, "MAX HEIGHT 10", Color3.new(0, 0, 0), "GothamBold")
	end
	local topY = (N - 1) * h
	local tower = box(CF, m, "SignTower", Wc / 2 - 8, 0, Dc / 2 - 8, Wc / 2, topY + 14, Dc / 2, C.exterior, Mat.Limestone)
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Right } do
		sign(tower, face, "P", Color3.new(1, 1, 1), "GothamBlack", Color3.fromRGB(20, 80, 200))
	end

	buildElevator(CF * CFrame.new(liftX, 0, liftZ) * CFrame.Angles(0, -math.pi / 2, 0), m, "CarParkLift", (function()
		local floors = {}
		for lvl = 0, N - 1 do table.insert(floors, lvl * h) end
		return floors
	end)())
	return m
end

--------------------------------------------------------------------------------------------------

-- Frame on the top of the site Part, turned so local +X faces the car park.
local function mallFrame(site: BasePart, cp: BasePart?)
	local top = site.CFrame * CFrame.new(0, site.Size.Y / 2, 0)
	local W, D, rot = site.Size.X, site.Size.Z, 0
	if cp then
		local rel = top:PointToObjectSpace(cp.Position)
		if math.abs(rel.Z) > math.abs(rel.X) then
			rot = rel.Z > 0 and -math.pi / 2 or math.pi / 2
			W, D = D, W
		elseif rel.X < 0 then
			rot = math.pi
		end
	end
	return top * CFrame.Angles(0, rot, 0), W, D
end

-- Footprint of a Part measured along the axes of frame F.
local function extentsIn(F: CFrame, p: BasePart)
	local rel = F:ToObjectSpace(p.CFrame)
	local s = p.Size
	local function ext(axis)
		return math.abs(rel.XVector[axis]) * s.X + math.abs(rel.YVector[axis]) * s.Y + math.abs(rel.ZVector[axis]) * s.Z
	end
	return rel.Position, ext("X"), ext("Y"), ext("Z")
end

function MallBuilder.Build(rebuild: boolean?)
	local existing = workspace:FindFirstChild("HarbourMall")
	if existing then
		if not rebuild then return existing end
		existing:Destroy()
	end
	local site = workspace:FindFirstChild("MallSite", true)
	if not (site and site:IsA("BasePart")) then warn("[MallBuilder] no Part named MallSite in Workspace"); return nil end
	local cp = workspace:FindFirstChild("CarParkSite", true)
	if cp and not cp:IsA("BasePart") then cp = nil end

	local root = Instance.new("Model")
	root.Name = "HarbourMall"
	local M, W, D = mallFrame(site, cp)
	buildMall(M, W, D, root)

	if cp then
		local pos, ex, ey, ez = extentsIn(M, cp)
		local CF = M * CFrame.new(pos.X, pos.Y + ey / 2, pos.Z)
		local h, H = Def.carParkDeckHeight, Def.floorHeight
		local deck = math.clamp(math.floor((H - (pos.Y + ey / 2)) / h + 0.5), 1, Def.carParkLevels - 1)
		local bz = math.clamp(-pos.Z, -ez / 2 + 40, ez / 2 - 50) -- bridge stays on the mall's centre line
		buildCarPark(CF, ex, ez, root, deck, bz)
		-- footbridge from the mall's upper level to the car park deck
		local a = Vector3.new(W / 2 - SETBACK - 2, H, 0)
		local bWorld = (CF * CFrame.new(-ex / 2 + 0.5, deck * h, bz)).Position
		local b = M:PointToObjectSpace(bWorld)
		b = Vector3.new(b.X, b.Y, 0)
		local bridge = Instance.new("Model"); bridge.Name = "Footbridge"; bridge.Parent = root
		local _, across = ramp(M, bridge, "BridgeDeck", a, b, 16, 1.5, C.gallery, Mat.Marble)
		for _, s in { -1, 1 } do
			local off = across * s * 7.85
			ramp(M, bridge, "BridgeRail", a + off + Vector3.new(0, 4, 0), b + off + Vector3.new(0, 4, 0), 0.3, 4, C.glass, Mat.Glass, CLEAR)
			ramp(M, bridge, "BridgeHandrail", a + off + Vector3.new(0, 4.35, 0), b + off + Vector3.new(0, 4.35, 0), 0.5, 0.35, C.metal, Mat.Metal)
		end
		ramp(M, bridge, "BridgeFascia", a - Vector3.new(0, 1.5, 0), b - Vector3.new(0, 1.5, 0), 16.4, 1.5, C.exteriorDark, Mat.Limestone)
		cp.Transparency = 1; cp.CanCollide = false; cp.CanQuery = false
	end
	site.Transparency = 1; site.CanCollide = false; site.CanQuery = false
	root.Parent = workspace
	return root
end

return MallBuilder
