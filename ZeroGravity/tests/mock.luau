-- Minimal headless Roblox API mock for running the game's server modules in the Luau CLI.
-- Covers exactly what the server code uses: Vector3/CFrame maths (real rotation matrices),
-- Instances with properties/attributes/children/signals, tags, a cooperative task scheduler
-- with a controllable clock, ray-vs-box raycasts, Terrain ball fills, and the services.
-- SOURCES (path -> source string) is injected by tests/run.py.

local Mock = {}
local now = 0
Mock.clock = function() return now end

---------------------------------------------------------------------------------------------- Vector3
local V3 = {}
local V3mt = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
local V3methods = {}
V3mt.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m == 0 then return v3(0 / 0, 0 / 0, 0 / 0) end
		return v3(t.X / m, t.Y / m, t.Z / m)
	elseif k == "x" then return t.X elseif k == "y" then return t.Y elseif k == "z" then return t.Z end
	return V3methods[k]
end
V3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return string.format("%.3f, %.3f, %.3f", a.X, a.Y, a.Z) end
function V3methods.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3methods.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V3methods.Lerp(a, b, t) return a + (b - a) * t end
function V3methods.Abs(a) return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
V3.new = v3
V3.zero, V3.one = v3(0, 0, 0), v3(1, 1, 1)
V3.xAxis, V3.yAxis, V3.zAxis = v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)

----------------------------------------------------------------------------------------------- CFrame
-- rotation matrix m[1..9] row-major: r00 r01 r02 / r10 r11 r12 / r20 r21 r22; columns = right, up, back
local CF = {}
local CFmt = {}
local function cf(p, m)
	return setmetatable({ p = p, m = m }, CFmt)
end
local ID = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function mulMM(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function mulMV(m, v)
	return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local function transpose(m) return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] } end
local CFmethods = {}
CFmt.__index = function(t, k)
	local m = t.m
	if k == "Position" then return t.p
	elseif k == "X" then return t.p.X elseif k == "Y" then return t.p.Y elseif k == "Z" then return t.p.Z
	elseif k == "LookVector" then return v3(-m[3], -m[6], -m[9])
	elseif k == "RightVector" then return v3(m[1], m[4], m[7])
	elseif k == "UpVector" then return v3(m[2], m[5], m[8])
	elseif k == "Rotation" then return cf(v3(0, 0, 0), m)
	end
	return CFmethods[k]
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == V3mt then return a.p + mulMV(a.m, b) end
	return cf(a.p + mulMV(a.m, b.p), mulMM(a.m, b.m))
end
CFmt.__add = function(a, v) return cf(a.p + v, a.m) end
CFmt.__sub = function(a, v) return cf(a.p - v, a.m) end
function CFmethods.Inverse(a)
	local t = transpose(a.m)
	return cf(-mulMV(t, a.p), t)
end
function CFmethods.PointToObjectSpace(a, v) return mulMV(transpose(a.m), v - a.p) end
function CFmethods.PointToWorldSpace(a, v) return a.p + mulMV(a.m, v) end
function CFmethods.VectorToWorldSpace(a, v) return mulMV(a.m, v) end
function CFmethods.VectorToObjectSpace(a, v) return mulMV(transpose(a.m), v) end
function CFmethods.Lerp(a, b, t) return cf(a.p:Lerp(b.p, t), t < 0.5 and a.m or b.m) end
function CFmethods.GetComponents(a)
	local m = a.m
	return a.p.X, a.p.Y, a.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end
local function rx(a) local c, s = math.cos(a), math.sin(a) return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function ry(a) local c, s = math.cos(a), math.sin(a) return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rz(a) local c, s = math.cos(a), math.sin(a) return { c, -s, 0, s, c, 0, 0, 0, 1 } end
function CF.new(a, b, c, ...)
	if a == nil then return cf(v3(0, 0, 0), ID) end
	if type(a) == "number" then
		local rest = { ... }
		if #rest == 9 then return cf(v3(a, b, c), rest) end
		return cf(v3(a, b, c), ID)
	end
	if b ~= nil then return CF.lookAt(a, b) end
	return cf(a, ID)
end
function CF.Angles(x, y, z) return cf(v3(0, 0, 0), mulMM(mulMM(rx(x), ry(y)), rz(z))) end
CF.fromEulerAnglesXYZ = CF.Angles
function CF.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return cf(pos, { vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z })
end
function CF.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look)
	return CF.fromMatrix(at, right, up2, -look)
end
CF.identity = cf(v3(0, 0, 0), ID)

------------------------------------------------------------------------------------------------ misc types
local C3mt = {}
C3mt.__index = { Lerp = function(a, b, t)
	return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, C3mt)
end }
local Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end,
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3mt) end,
}
local function plain(name) return { new = function(...) return { _type = name, ... } end } end

local V2mt = {}
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2mt) end
V2mt.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	return nil
end
V2mt.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2mt.__mul = function(a, b)
	if type(a) == "number" then return v2(a * b.X, a * b.Y) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
local Vector2 = { new = v2, zero = v2(0, 0) }
Mock.keys = {}

local Rmt = {}
Rmt.__index = Rmt
function Rmt:_next()
	self.s = (self.s * 16807) % 2147483647
	return self.s / 2147483647
end
function Rmt:NextNumber(a, b)
	local r = self:_next()
	if a then return a + (b - a) * r end
	return r
end
function Rmt:NextInteger(a, b) return math.min(b, a + math.floor(self:_next() * (b - a + 1))) end
function Rmt:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local t = self:NextNumber(0, math.pi * 2)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(t), r * math.sin(t), z)
end
local seedCounter = 12345
local Random = { new = function(seed)
	seedCounter += 7919
	local s = math.floor(seed or seedCounter) % 2147483646 + 1
	return setmetatable({ s = s }, Rmt)
end }

local Enum = setmetatable({}, { __index = function(enums, typeName)
	local items = setmetatable({}, { __index = function(t, itemName)
		local item = { Name = itemName, EnumType = typeName, Value = 0 }
		rawset(t, itemName, item) -- cached so EnumItems compare equal, as in Roblox
		return item
	end })
	rawset(enums, typeName, items)
	return items
end })

-------------------------------------------------------------------------------------------------- signals
local function Signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		local conn = { Connected = true }
		function conn.Disconnect()
			local i = table.find(s.handlers, fn)
			if i then table.remove(s.handlers, i) end
			conn.Connected = false
		end
		return conn
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...) c.Disconnect() fn(...) end)
		return c
	end
	function s:Fire(...)
		for _, fn in table.clone(self.handlers) do fn(...) end
	end
	function s:Wait() return coroutine.yield() end
	return s
end
Mock.Signal = Signal

------------------------------------------------------------------------------------------------ scheduler
local queue = {} -- { at, co, args }
local function schedule(at, co, ...)
	table.insert(queue, { at = at, co = co, args = table.pack(...) })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		Mock.errors = Mock.errors or {}
		table.insert(Mock.errors, tostring(err))
		print("[mock] thread error: " .. tostring(err))
	end
end
local task = {}
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	local co = coroutine.create(fn)
	schedule(now, co, ...)
	return co
end
function task.delay(t, fn, ...)
	local co = coroutine.create(fn)
	schedule(now + (t or 0), co, ...)
	return co
end
function task.wait(t)
	local co = coroutine.running()
	schedule(now + math.max(t or 0, 1 / 60), co)
	coroutine.yield()
	return t or 0
end
function task.cancel(co)
	for i = #queue, 1, -1 do
		if queue[i].co == co then table.remove(queue, i) end
	end
end
-- Advance simulated time, resuming due threads in time order.
function Mock.advance(dt)
	local target = now + dt
	while true do
		local bestI, best = nil, nil
		for i, q in queue do
			if q.at <= target and (not best or q.at < best.at) then bestI, best = i, q end
		end
		if not best then break end
		table.remove(queue, bestI)
		now = math.max(now, best.at)
		if coroutine.status(best.co) == "suspended" then resume(best.co, table.unpack(best.args, 1, best.args.n)) end
	end
	now = target
end
Mock.task = task

------------------------------------------------------------------------------------------------- instances
local Inst = {}
local INSTANCEmt = {}
local tags: { [string]: { [any]: boolean } } = {}
local allParts = {}
Mock.allParts = allParts

local HIER = {
	Part = { "BasePart", "PVInstance" }, WedgePart = { "BasePart", "PVInstance" }, MeshPart = { "BasePart", "PVInstance" },
	Terrain = { "BasePart", "PVInstance" }, SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Model = { "PVInstance" }, Workspace = { "Model", "WorldRoot", "PVInstance" },
	BloomEffect = { "PostEffect" }, ColorCorrectionEffect = { "PostEffect" },
	Script = { "BaseScript", "LuaSourceContainer" }, LocalScript = { "Script", "BaseScript" }, ModuleScript = { "LuaSourceContainer" },
	TextLabel = { "GuiObject", "GuiBase2d" }, Frame = { "GuiObject", "GuiBase2d" },
	SurfaceGui = { "LayerCollector", "GuiBase2d" }, BillboardGui = { "LayerCollector", "GuiBase2d" },
	PointLight = { "Light" }, SurfaceLight = { "Light" },
}
local EVENTS = {
	Triggered = true, Changed = true, Died = true, OnServerEvent = true, OnClientEvent = true, PlayerAdded = true,
	PlayerRemoving = true, CharacterAdded = true, Heartbeat = true, Stepped = true, RenderStepped = true, PreSimulation = true,
	Destroying = true, ChildAdded = true, StateChanged = true, MouseButton1Click = true, Touched = true,
	InputBegan = true, InputEnded = true, InputChanged = true,
}

local function isA(self, cls)
	if self.ClassName == cls or cls == "Instance" then return true end
	local h = HIER[self.ClassName]
	return h ~= nil and table.find(h, cls) ~= nil
end

function Inst.new(className, parent)
	local self = setmetatable({ _props = { Name = className, ClassName = className }, _children = {}, _attrs = {}, _signals = {} }, INSTANCEmt)
	if isA(self, "BasePart") then
		local p = self._props
		p.Size, p.CFrame, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = v3(4, 1, 2), CF.identity, false, true, true, true, 0
		p.Shape = Enum.PartType.Block
		p.AssemblyLinearVelocity = v3(0, 0, 0)
		table.insert(allParts, self)
	elseif className == "Attachment" then
		self._props.Position = v3(0, 0, 0)
	elseif className == "Humanoid" then
		self._props.Health, self._props.MaxHealth = 100, 100
	end
	if parent then self.Parent = parent end
	return self
end

local methods = {}
INSTANCEmt.__index = function(self, k)
	local m = methods[k]
	if m then return m end
	local props = rawget(self, "_props")
	if k == "Position" and props.CFrame then return props.CFrame.p end
	if k == "WorldPosition" and props.ClassName == "Attachment" then
		local par = props.Parent
		if par and par._props.CFrame and par.ClassName ~= "Terrain" then return par._props.CFrame * props.Position end
		return props.Position
	end
	local v = props[k]
	if v ~= nil then return v end
	if EVENTS[k] then
		local s = Signal()
		props[k] = s
		return s
	end
	-- child lookup by name (like Roblox's instance.ChildName)
	for _, c in rawget(self, "_children") do
		if c._props.Name == k then return c end
	end
	return nil
end
INSTANCEmt.__newindex = function(self, k, v)
	local props = rawget(self, "_props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local i = table.find(old._children, self)
			if i then table.remove(old._children, i) end
		end
		props.Parent = v
		if v then table.insert(v._children, self) end
		return
	end
	if k == "Position" and props.CFrame then
		props.CFrame = cf(v, props.CFrame.m)
		return
	end
	if k == "Health" and props.ClassName == "Humanoid" then
		local was = props.Health
		props.Health = math.clamp(v, 0, props.MaxHealth)
		if was > 0 and props.Health <= 0 then self.Died:Fire() end
		return
	end
	if k == "WorldPosition" and props.ClassName == "Attachment" then
		local par = props.Parent
		if par and par._props.CFrame and par.ClassName ~= "Terrain" then
			props.Position = par._props.CFrame:PointToObjectSpace(v)
		else
			props.Position = v
		end
		return
	end
	props[k] = v
end
INSTANCEmt.__tostring = function(self) return self._props.Name end

function methods.IsA(self, cls) return isA(self, cls) end
function methods.GetChildren(self) return table.clone(self._children) end
function methods.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in n._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in self._children do
		if c._props.Name == name then return c end
	end
	if recursive then
		for _, c in self._children do
			local f = c:FindFirstChild(name, true)
			if f then return f end
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	local c = self:FindFirstChild(name)
	if not c then error("WaitForChild: " .. name .. " not found in " .. tostring(self._props.Name), 2) end
	return c
end
function methods.FindFirstChildOfClass(self, cls)
	for _, c in self._children do
		if c._props.ClassName == cls then return c end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, cls)
	for _, c in self._children do
		if c:IsA(cls) then return c end
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, cls)
	local p = self._props.Parent
	while p do
		if p._props.ClassName == cls then return p end
		p = p._props.Parent
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, cls)
	local p = self._props.Parent
	while p do
		if p:IsA(cls) then return p end
		p = p._props.Parent
	end
	return nil
end
function methods.IsDescendantOf(self, other)
	local p = self._props.Parent
	while p do
		if p == other then return true end
		p = p._props.Parent
	end
	return false
end
function methods.SetAttribute(self, k, v) self._attrs[k] = v end
function methods.GetAttribute(self, k) return self._attrs[k] end
function methods.GetAttributes(self) return table.clone(self._attrs) end
function methods.GetAttributeChangedSignal(self, k)
	self._signals["attr_" .. k] = self._signals["attr_" .. k] or Signal()
	return self._signals["attr_" .. k]
end
function methods.GetPropertyChangedSignal(self, k)
	self._signals["prop_" .. k] = self._signals["prop_" .. k] or Signal()
	return self._signals["prop_" .. k]
end
function methods.Destroy(self)
	self._props.Destroyed = true
	for _, c in table.clone(self._children) do c:Destroy() end
	self.Parent = nil
	for _, set in tags do set[self] = nil end
end
function methods.ClearAllChildren(self)
	for _, c in table.clone(self._children) do c:Destroy() end
end
function methods.Clone(self)
	local c = Inst.new(self._props.ClassName)
	for k, v in self._props do
		if k ~= "Parent" then c._props[k] = v end
	end
	return c
end
function methods.GetPivot(self)
	if self._props.CFrame then return self._props.CFrame end
	local pp = self._props.PrimaryPart
	if pp then return pp._props.CFrame end
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then return d._props.CFrame end
	end
	return CF.identity
end
function methods.PivotTo(self, target)
	local delta = target * self:GetPivot():Inverse()
	if self._props.CFrame then self._props.CFrame = target end
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then d._props.CFrame = delta * d._props.CFrame end
	end
end
-- Humanoid
function methods.TakeDamage(self, amount) self.Health = self._props.Health - amount end
function methods.ChangeState() end
function methods.SetStateEnabled() end
-- RemoteEvent
function methods.FireClient(self, player, msg)
	Mock.sent = Mock.sent or {}
	table.insert(Mock.sent, { remote = self._props.Name, player = player, msg = msg })
end
function methods.FireServer(self, msg)
	Mock.sent = Mock.sent or {}
	table.insert(Mock.sent, { remote = self._props.Name, player = "server", msg = msg })
end
function methods.FireAllClients(self, msg)
	Mock.sent = Mock.sent or {}
	table.insert(Mock.sent, { remote = self._props.Name, player = "all", msg = msg })
end
-- Tween-ish / misc
function methods.Play() end
function methods.Emit() end
-- Player
function methods.Kick(self, reason) self._props.Kicked = reason end
function methods.LoadCharacter(self) Mock.makeCharacter(self) end
function methods.LoadCharacterAsync(self) Mock.makeCharacter(self) end

-- Terrain
function methods.FillBall(self, center, radius, material)
	table.insert(Mock.terrainBalls, { c = center, r = radius, air = material.Name == "Air" })
end
-- Solid if the most recent fill covering the point is not Air (later fills overwrite earlier ones).
function Mock.terrainSolidAt(p)
	for i = #Mock.terrainBalls, 1, -1 do
		local b = Mock.terrainBalls[i]
		if (p - b.c).Magnitude < b.r then return not b.air end
	end
	return false
end
function methods.Clear(self) table.clear(Mock.terrainBalls) end
function methods.ReadVoxels(_self, region)
	return { Size = v3(1, 1, 1), { { Enum.Material.Air } } }
end
Mock.terrainBalls = {}

------------------------------------------------------------------------------------------------ raycasting
-- Ray vs oriented box (slab test). Returns distance or nil.
local function rayBox(origin, dir, part)
	local c = part._props.CFrame
	local half = part._props.Size / 2
	local o = c:PointToObjectSpace(origin)
	local d = c:VectorToObjectSpace(dir)
	local tmin, tmax = 0, 1
	for _, ax in { "X", "Y", "Z" } do
		local oa, da, h = o[ax], d[ax], half[ax]
		if math.abs(da) < 1e-9 then
			if oa < -h or oa > h then return nil end
		else
			local t1, t2 = (-h - oa) / da, (h - oa) / da
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then return nil end
		end
	end
	return tmin
end
Mock.rayBox = rayBox

function Mock.pointInPart(p, part)
	local lp = part._props.CFrame:PointToObjectSpace(p)
	local h = part._props.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

function methods.Raycast(_self, origin, dir, params)
	local filter = params and params.FilterDescendantsInstances or {}
	local bestT, bestPart = math.huge, nil
	for _, part in allParts do
		local pr = part._props
		if pr.Parent and not pr.Destroyed and pr.CanQuery ~= false and pr.ClassName ~= "Terrain" then
			local skip = false
			for _, f in filter do
				if part == f or part:IsDescendantOf(f) then skip = true break end
			end
			if not skip then
				local t = rayBox(origin, dir, part)
				if t and t < bestT then bestT, bestPart = t, part end
			end
		end
	end
	if bestPart then
		return { Instance = bestPart, Position = origin + dir * bestT, Normal = -dir.Unit, Distance = dir.Magnitude * bestT }
	end
	return nil
end
function methods.GetPartBoundsInRadius() return {} end
function methods.GetServerTimeNow() return now end
function methods.GetPlayers(self) return table.clone(self._players) end
function methods.GetPlayerFromCharacter(self, char)
	for _, p in self._players do
		if p._props.Character == char then return p end
	end
	return nil
end
function methods.BindToClose() end
function methods.IsKeyDown(_self, key) return Mock.keys[key.Name] == true end
function methods.GetMouseDelta() return Vector2.zero end
function methods.BindToRenderStep(_self, name, _prio, fn) Mock.renderSteps = Mock.renderSteps or {}; Mock.renderSteps[name] = fn end
function methods.GetState() return Enum.HumanoidStateType.Physics end
function methods.IsStudio() return Mock.isStudio end
function methods.IsServer() return true end
function methods.IsClient() return false end
-- CollectionService
function methods.AddTag(_self, inst, tag)
	tags[tag] = tags[tag] or {}
	tags[tag][inst] = true
end
function methods.RemoveTag(_self, inst, tag) if tags[tag] then tags[tag][inst] = nil end end
function methods.HasTag(_self, inst, tag) return tags[tag] ~= nil and tags[tag][inst] == true end
function methods.GetTagged(_self, tag)
	local out = {}
	for inst in tags[tag] or {} do
		if not inst._props.Destroyed then table.insert(out, inst) end
	end
	return out
end
-- TweenService
function methods.Create(_self, inst, _info, goal)
	return { Play = function()
		for k, v in goal do inst[k] = v end
	end }
end
-- DataStore
function methods.GetDataStore(_self, name)
	local data = {}
	return {
		GetAsync = function(_, key) return data[key] end,
		SetAsync = function(_, key, v) data[key] = v end,
		UpdateAsync = function(_, key, fn)
			local r = fn(data[key])
			if r ~= nil then data[key] = r end
			return r
		end,
		_data = data,
	}
end
function methods.AddItem() end

-------------------------------------------------------------------------------------------------- the game
local game = Inst.new("DataModel")
local services = {}
local function service(name, className)
	local s = Inst.new(className or name)
	s._props.Name = name
	s.Parent = game
	services[name] = s
	return s
end
local workspace = service("Workspace")
local terrain = Inst.new("Terrain")
terrain._props.Name = "Terrain"
terrain.Parent = workspace
workspace._props.Terrain = terrain
workspace._props.Gravity = 196.2
local players = service("Players")
players._players = {}
service("ReplicatedStorage")
service("ServerScriptService")
local starterPlayer = service("StarterPlayer")
local scs = Inst.new("StarterCharacterScripts")
scs.Parent = starterPlayer
local sps = Inst.new("StarterPlayerScripts")
sps.Parent = starterPlayer
for _, n in { "Lighting", "CollectionService", "TweenService", "RunService", "DataStoreService", "Debris", "SoundService", "UserInputService", "StarterGui", "HttpService" } do
	service(n)
end
function methods.GetService(_self, name)
	return services[name] or error("unknown service " .. name)
end

function Mock.addPlayer(name, userId)
	local p = Inst.new("Player")
	p._props.Name = name
	p._props.UserId = userId or (#players._players + 1)
	p.Parent = players
	local gui = Inst.new("PlayerGui")
	gui._props.Name = "PlayerGui"
	gui.Parent = p
	table.insert(players._players, p)
	players.PlayerAdded:Fire(p)
	return p
end
function Mock.removePlayer(p)
	players.PlayerRemoving:Fire(p)
	local i = table.find(players._players, p)
	if i then table.remove(players._players, i) end
	p.Parent = nil
end
-- R15-ish character: HumanoidRootPart, Head, UpperTorso, Humanoid
function Mock.makeCharacter(player, at)
	local old = player._props.Character
	if old then old:Destroy() end
	local char = Inst.new("Model")
	char._props.Name = player._props.Name
	local root = Inst.new("Part")
	root._props.Name = "HumanoidRootPart"
	root._props.Size = v3(2, 2, 1)
	root._props.CFrame = at or CF.identity
	root.Parent = char
	char._props.PrimaryPart = root
	local head = Inst.new("Part")
	head._props.Name = "Head"
	head._props.Size = v3(1.2, 1.2, 1.2)
	head._props.CFrame = (at or CF.identity) * CF.new(0, 2, 0)
	head.Parent = char
	local torso = Inst.new("Part")
	torso._props.Name = "UpperTorso"
	torso._props.Size = v3(2, 1.6, 1)
	torso._props.CFrame = (at or CF.identity) * CF.new(0, 0.6, 0)
	torso.Parent = char
	local hum = Inst.new("Humanoid")
	hum.Parent = char
	char.Parent = workspace
	player._props.Character = char
	player.CharacterAdded:Fire(char)
	return char
end

---------------------------------------------------------------------------------------------- module loader
local tree = {}
local cache = {}
local GLOBAL
local function requireModule(node)
	if cache[node] ~= nil then return cache[node] end
	local src = SOURCES[node._source]
	assert(src, "no source for " .. tostring(node._source))
	local chunk, err = loadstring(src, "=" .. node._source)
	assert(chunk, err)
	setfenv(chunk, setmetatable({ script = node }, { __index = GLOBAL }))
	local result = chunk()
	cache[node] = result
	return result
end

-- Build the DataModel tree for every source path (mirrors default.project.json)
local MAP = {
	["src/ReplicatedStorage/Shared/"] = { "ReplicatedStorage", "Shared" },
	["src/ServerScriptService/Services/"] = { "ServerScriptService", "Services" },
	["src/ServerScriptService/Builders/"] = { "ServerScriptService", "Builders" },
	["src/StarterPlayer/StarterPlayerScripts/Controllers/"] = { "StarterPlayer", "StarterPlayerScripts", "Controllers" },
}
local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Inst.new("Folder")
		f._props.Name = name
		f.Parent = parent
	end
	return f
end
for path in SOURCES do
	for prefix, chain in MAP do
		if string.sub(path, 1, #prefix) == prefix then
			local node = services[chain[1]]
			for i = 2, #chain do node = ensureFolder(node, chain[i]) end
			local file = string.sub(path, #prefix + 1)
			local name = string.gsub(file, "%.luau$", "")
			local ms = Inst.new("ModuleScript")
			ms._props.Name = name
			ms._source = path
			ms.Parent = node
		end
	end
end
-- the client bootstrap LocalScript sits directly in StarterPlayerScripts
do
	local path = "src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau"
	if SOURCES[path] then
		local ms = Inst.new("LocalScript")
		ms._props.Name = "ClientMain"
		ms._source = path
		ms.Parent = services.StarterPlayer:FindFirstChild("StarterPlayerScripts")
	end
end
local sss = services.ServerScriptService

GLOBAL = setmetatable({
	game = game, workspace = workspace, Instance = Inst, Vector3 = V3, CFrame = CF, Color3 = Color3, Enum = Enum, Random = Random,
	Vector2 = Vector2, UDim2 = { new = plain("UDim2").new, fromOffset = plain("UDim2").new, fromScale = plain("UDim2").new },
	UDim = plain("UDim"), TweenInfo = plain("TweenInfo"), NumberSequence = plain("NumberSequence"), ColorSequence = plain("ColorSequence"),
	NumberRange = plain("NumberRange"), NumberSequenceKeypoint = plain("NumberSequenceKeypoint"),
	Region3 = { new = function(a, b) return { ExpandToGrid = function(self) return self end, a = a, b = b } end },
	RaycastParams = { new = function() return { FilterDescendantsInstances = {} } end },
	OverlapParams = { new = function() return {} end },
	task = task, require = requireModule, warn = function(...) print("[warn]", ...) end,
	os = setmetatable({ clock = function() return now end, time = function() return now end }, { __index = os }),
	tick = function() return now end,
	typeof = function(v)
		local mt = getmetatable(v)
		if mt == V3mt then return "Vector3" elseif mt == CFmt then return "CFrame" elseif mt == C3mt then return "Color3"
		elseif mt == INSTANCEmt then return "Instance" end
		return type(v)
	end,
}, { __index = _G })

Mock.game, Mock.workspace, Mock.services, Mock.GLOBAL = game, workspace, services, GLOBAL
Mock.require = requireModule
Mock.Vector3, Mock.CFrame, Mock.Instance = V3, CF, Inst
Mock.tags = tags
Mock.isStudio = true
function Mock.module(...)
	local node = services[(...)]
	for i = 2, select("#", ...) do node = node:WaitForChild((select(i, ...))) end
	return requireModule(node)
end
Mock.sss = sss
return Mock
