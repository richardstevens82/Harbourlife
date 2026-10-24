-- Test specs. Runs after the mock is loaded (Mock is in scope).
local V3, CF = Mock.Vector3, Mock.CFrame
local Random = Mock.GLOBAL.Random
local Vector2 = Mock.GLOBAL.Vector2
local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
		print("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end
local function check(cond, msg, ...)
	if not cond then error(string.format(msg or "assertion failed", ...), 2) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local Shared = { "ReplicatedStorage", "Shared" }
local function shared(name) return Mock.module("ReplicatedStorage", "Shared", name) end
local function svc(name) return Mock.module("ServerScriptService", "Services", name) end
local function builder(name) return Mock.module("ServerScriptService", "Builders", name) end
local _ = Shared

------------------------------------------------------------------------------------------- pure logic
print("\n== Pure logic ==")
local Config = shared("Config")
local Weapons = shared("WeaponDefinitions")
local Items = shared("ItemDefinitions")
local Loot = shared("LootTables")
local Zone = shared("ZoneMath")
local Cosmetics = shared("Cosmetics")

test("CFrame mock sanity (Angles, lookAt, inverse)", function()
	local c = CF.new(1, 2, 3) * CF.Angles(0, math.rad(90), 0)
	local v = c:VectorToWorldSpace(V3.new(0, 0, 1))
	check(near(v.X, 1) and near(v.Z, 0), "Angles(0,90,0) maps +Z to +X, got %s", tostring(v))
	local l = CF.lookAt(V3.new(0, 0, 0), V3.new(10, 0, 0))
	check(near(l.LookVector.X, 1), "lookAt LookVector")
	local p = V3.new(5, -2, 7)
	local back = c:PointToObjectSpace(c * p)
	check(near(back.X, 5) and near(back.Y, -2) and near(back.Z, 7), "inverse round trip")
end)

test("8 weapon classes defined with complete stats", function()
	local n = 0
	for id, w in Weapons.List do
		n += 1
		for _, f in { "name", "ammo", "mode", "damage", "pellets", "rpm", "mag", "reload", "range", "maxRange", "spread", "recoil", "mobility" } do
			check(w[f] ~= nil, "%s missing %s", id, f)
		end
		check(Config.Inventory.AmmoCap[w.ammo], "%s uses unknown ammo %s", id, w.ammo)
		check(w.maxRange > w.range, "%s maxRange must exceed range", id)
	end
	check(n == 8 and #Weapons.Order == 8, "expected 8 weapons, got %d", n)
end)

test("damage falloff is monotonic and zero past max range", function()
	for id, w in Weapons.List do
		local last = math.huge
		for d = 0, w.maxRange + 50, 5 do
			local dmg = Weapons.DamageAt(id, "common", d)
			check(dmg <= last + 1e-9, "%s damage increased at %d", id, d)
			last = dmg
		end
		check(Weapons.DamageAt(id, "common", w.maxRange + 1) == 0, "%s should do 0 beyond maxRange", id)
		check(Weapons.DamageAt(id, "legendary", 0) > Weapons.DamageAt(id, "common", 0), "%s rarity bonus", id)
		check(Weapons.DamageAt(id, "legendary", 0) <= w.damage * 1.2, "%s legendary bonus too large", id)
	end
end)

test("time-to-kill is sane (no weapon kills a full-shield player in < 0.4 s)", function()
	for id, w in Weapons.List do
		local per = Weapons.DamageAt(id, "legendary", 0) * w.pellets
		local shots = math.ceil(200 / per)
		local ttk = (shots - 1) * Weapons.FireInterval(id)
		if w.mode == "burst" then ttk = math.floor((shots - 1) / w.burstCount) * Weapons.FireInterval(id) + ((shots - 1) % w.burstCount) * w.burstDelay end
		check(ttk >= 0.4, "%s TTK vs 200 effective HP is %.2fs", id, ttk)
	end
end)

test("loot rolls: valid ids, ammo with weapons, rarity rules", function()
	local rng = Random.new(99)
	for _, tier in { "low", "mid", "high" } do
		for _ = 1, 3000 do
			local items = Loot.RollContainer(rng, tier, 2, 4)
			for i, e in items do
				local def = Items.Get(e.id)
				check(def ~= nil, "unknown item %s", e.id)
				check(table.find(Items.Rarities, e.rarity) ~= nil, "bad rarity %s", tostring(e.rarity))
				check(e.amount and e.amount > 0, "bad amount")
				if def.kind == "weapon" then
					local nxt = items[i + 1]
					check(nxt and nxt.id == "ammo_" .. Weapons.Get(def.weapon).ammo, "weapon %s without matching ammo", e.id)
					if def.weapon == "helios" or def.weapon == "precision" then
						check(e.rarity ~= "common" and e.rarity ~= "uncommon", "%s rolled %s", def.weapon, e.rarity)
					end
				end
				if tier == "low" then check(e.rarity ~= "legendary", "legendary in low tier") end
			end
		end
	end
end)

test("loot quality improves with tier", function()
	local function avg(tier)
		local rng, sum = Random.new(5), 0
		for _ = 1, 4000 do sum += table.find(Items.Rarities, Loot.RollRarity(rng, tier)) end
		return sum / 4000
	end
	local lo, mi, hi = avg("low"), avg("mid"), avg("high")
	check(lo < mi and mi < hi, "avg rarity low %.2f mid %.2f high %.2f", lo, mi, hi)
end)

test("zone: every next sphere lies inside the previous one", function()
	local rng = Random.new(3)
	for _ = 1, 2000 do
		local c0 = rng:NextUnitVector() * rng:NextNumber(0, 500)
		local r0 = rng:NextNumber(50, 2000)
		local r1 = rng:NextNumber(1, r0)
		local target = rng:NextUnitVector() * rng:NextNumber(0, 3000)
		local c1 = Zone.NextCenter(c0, r0, r1, target)
		check((c1 - c0).Magnitude + r1 <= r0 + 1e-6, "next zone escapes previous")
	end
end)

test("zone schedule: radius never grows, ends at final radius, fits the match time", function()
	local stages = Config.Zone.Stages
	local target = V3.new(-880, -40, 380)
	local sched = Zone.BuildSchedule(stages, V3.zero, Config.Zone.StartRadius, target, 0)
	local last = math.huge
	local total = sched[#sched].endShrink
	for t = 0, total + 30, 0.5 do
		local _, r = Zone.Evaluate(sched, t, V3.zero, Config.Zone.StartRadius, 1)
		check(r <= last + 1e-6, "radius grew at t=%.1f", t)
		last = r
	end
	check(near(last, stages[#stages].radius), "final radius %.2f", last)
	check(total < Config.Match.MaxMatchTime, "zone schedule (%ds) exceeds MaxMatchTime", total)
	local c = Zone.Evaluate(sched, total + 1, V3.zero, Config.Zone.StartRadius, 1)
	check((c - target).Magnitude < 1, "final zone should converge on its target")
	for i = 2, #sched do
		check(sched[i].dps >= sched[i - 1].dps, "damage must escalate per stage")
	end
end)

test("progression curve and cosmetics unlocks", function()
	for l = 1, 50 do check(Config.XpForLevel(l + 1) > Config.XpForLevel(l), "xp curve not increasing at %d", l) end
	check(Cosmetics.IsUnlocked(Cosmetics.Suits[1], { level = 1 }), "default suit must be unlocked")
	check(not Cosmetics.IsUnlocked(Cosmetics.Suits[#Cosmetics.Suits], { level = 1 }), "top suit locked at level 1")
end)

-------------------------------------------------------------------------------------------- world build
print("\n== Environment build & inspection ==")
local Kit = builder("Kit")
local corridors, tubes, airlocks = {}, {}, {}
do
	local oc, ot, oa = Kit.corridor, Kit.octTube, Kit.airlock
	Kit.corridor = function(parent, a, b, opts)
		local m, cf = oc(parent, a, b, opts)
		table.insert(corridors, { a = a, b = b, name = opts and opts.name or "Corridor", model = m })
		return m, cf
	end
	Kit.octTube = function(parent, cf, radius, length, opts)
		local m = ot(parent, cf, radius, length, opts)
		if opts and opts.caps and opts.caps.front == true then
			table.insert(tubes, { cf = cf, r = radius, len = length, name = opts.name, model = m })
		end
		return m
	end
	Kit.airlock = function(parent, cf, opts)
		local m = oa(parent, cf, opts)
		table.insert(airlocks, { cf = cf, model = m })
		return m
	end
end
-- The station is laid out at base scale and then enlarged; bring recorded geometry along.
local function rescaleRecorded()
	local station = Mock.workspace.Arena:FindFirstChild("SpaceStation")
	local S = builder("Station").Scale
	local function sc(cf) return CF.new(cf.p * S) * cf.Rotation end
	for _, c in corridors do
		if c.model:IsDescendantOf(station) then c.a, c.b = c.a * S, c.b * S end
	end
	for _, t in tubes do
		if t.model:IsDescendantOf(station) then t.cf, t.len = sc(t.cf), t.len * S end
	end
	for _, a in airlocks do
		if a.model:IsDescendantOf(station) then a.cf, a.scale = sc(a.cf), S end
	end
end
local WorldBuilder = svc("WorldBuilder")
local CS = Mock.services.CollectionService
local arena

test("world builds without runtime errors", function()
	Mock.errors = {}
	WorldBuilder.Start()
	arena = Mock.workspace:FindFirstChild("Arena")
	check(arena ~= nil, "Arena missing")
	rescaleRecorded()
	check(#Mock.errors == 0, "errors: %s", table.concat(Mock.errors, "; "))
end)

local solids = {}
local function collectSolids()
	table.clear(solids)
	for _, p in Mock.allParts do
		local pr = p._props
		if pr.Parent and not pr.Destroyed and pr.CanCollide ~= false and pr.ClassName ~= "Terrain"
			and pr.Name ~= "InnerDoor" and pr.Name ~= "OuterDoor" and pr.Name ~= "HumanoidRootPart" then
			table.insert(solids, p)
		end
	end
end
local function solidAt(pos: any)
	for _, p in solids do
		if Mock.pointInPart(pos, p) then return p end
	end
	if Mock.terrainSolidAt(pos) then return { _props = { Name = "Terrain asteroid" } } end
	return nil
end
local function describe(p)
	local path = {}
	local n = p
	while n and n._props and n._props.Name ~= "Workspace" do
		table.insert(path, 1, n._props.Name)
		n = n._props.Parent
	end
	return table.concat(path, ".")
end

test("part budget and landmark counts", function()
	collectSolids()
	local n = 0
	for _, p in Mock.allParts do
		if p._props.Parent and not p._props.Destroyed then n += 1 end
	end
	print(string.format("        parts in world: %d (%d collidable), terrain fills: %d", n, #solids, #Mock.terrainBalls))
	check(n < 20000, "too many parts: %d", n)
	local counts = {}
	for _, tag in { "LootSpot", "DeployPoint", "FinalZone", "OxygenStation", "Airlock", "Pressurized", "ElectricHazard", "ReactorHazard",
		"ExplosiveBarrel", "Breachable", "LobbySpawn", "PracticeTarget" } do
		counts[tag] = #CS:GetTagged(tag)
	end
	local s = {}
	for k, v in counts do table.insert(s, k .. "=" .. v) end
	table.sort(s)
	print("        " .. table.concat(s, "  "))
	check(counts.DeployPoint >= Config.Match.MaxPlayers, "need >= %d deploy points, have %d", Config.Match.MaxPlayers, counts.DeployPoint)
	check(counts.LootSpot >= 80, "only %d loot spots", counts.LootSpot)
	check(counts.FinalZone >= 5, "need several final zone candidates")
	check(counts.Airlock >= 10, "only %d airlocks", counts.Airlock)
	check(counts.OxygenStation >= 10, "only %d O2 stations", counts.OxygenStation)
	check(counts.LobbySpawn >= 8, "lobby spawns")
end)

-- A passage is clear if its centre line and a ring of points 2.6 studs off it (character radius)
-- are free of collidable geometry.
local function passageBlocked(a: any, b: any, extend: number)
	local d = (b - a)
	local len = d.Magnitude
	local dir = d.Unit
	local up = math.abs(dir.Y) > 0.95 and V3.xAxis or V3.yAxis
	local right = dir:Cross(up).Unit
	local up2 = right:Cross(dir)
	for t = -extend, len + extend, 1 do
		local c = a + dir * t
		for _, off in { V3.zero, right * 2.6, -right * 2.6, up2 * 2.6, -up2 * 2.6 } do
			local hit = solidAt(c + off)
			if hit then return hit, c + off, t end
		end
	end
	return nil
end

test("every corridor is passable end to end (including its doorways)", function()
	collectSolids()
	local bad = {}
	for _, c in corridors do
		local hit, at = passageBlocked(c.a, c.b, 3)
		if hit then table.insert(bad, string.format("%s %s->%s blocked by %s at %s", c.name, tostring(c.a), tostring(c.b), describe(hit), tostring(at))) end
	end
	check(#corridors >= 12, "expected many corridors, got %d", #corridors)
	check(#bad == 0, "%d blocked:\n          %s", #bad, table.concat(bad, "\n          "))
end)

test("habitat tubes (spine and ring) are passable", function()
	collectSolids()
	local bad = {}
	for _, t in tubes do
		local a = t.cf * V3.new(0, 0, -t.len / 2)
		local b = t.cf * V3.new(0, 0, t.len / 2)
		local hit, at = passageBlocked(a, b, 4)
		if hit then table.insert(bad, string.format("%s blocked by %s at %s", t.name, describe(hit), tostring(at))) end
	end
	check(#tubes >= 10, "expected ring and spine tubes, got %d", #tubes)
	check(#bad == 0, "%d blocked:\n          %s", #bad, table.concat(bad, "\n          "))
end)

test("airlock chambers are clear and open to the outside", function()
	collectSolids()
	local bad = {}
	for _, al in airlocks do
		-- from the inner door plane, through the chamber, 10 studs out into space
		local cf, k = al.cf, al.scale or 1
		local a = cf * V3.new(0, 0, 6 * k)
		local b = cf * V3.new(0, 0, -17 * k)
		local hit, at = passageBlocked(a, b, 0)
		if hit then table.insert(bad, string.format("airlock at %s blocked by %s at %s", tostring(cf.Position), describe(hit), tostring(at))) end
	end
	check(#bad == 0, "%d blocked:\n          %s", #bad, table.concat(bad, "\n          "))
end)

test("deploy points, loot spots, O2 stations and final zones are not inside geometry", function()
	collectSolids()
	local bad = {}
	for _, tag in { "DeployPoint", "LootSpot", "OxygenStation", "FinalZone", "LobbySpawn" } do
		for _, m in CS:GetTagged(tag) do
			local hit = solidAt(m._props.CFrame.p)
			if hit then table.insert(bad, string.format("%s at %s inside %s", tag, tostring(m._props.CFrame.p), describe(hit))) end
		end
	end
	check(#bad == 0, "%d embedded:\n          %s", #bad, table.concat(bad, "\n          "))
end)

test("deploy points are spread out and inside the arena", function()
	local pts = {}
	for _, m in CS:GetTagged("DeployPoint") do table.insert(pts, m._props.CFrame.p) end
	local tooClose = 0
	for i, a in pts do
		check(a.Magnitude < Config.Zone.StartRadius - 150, "deploy point %s outside the starting zone", tostring(a))
		for j = i + 1, #pts do
			if (a - pts[j]).Magnitude < 60 then tooClose += 1 end
		end
	end
	check(tooClose <= 2, "%d deploy point pairs closer than 60 studs", tooClose)
end)

test("lobby hall is sealed (no route from the lobby into the arena)", function()
	collectSolids()
	local center = Config.Arena.LobbyCenter
	local rng = Random.new(8)
	local open = 0
	for _ = 1, 400 do
		local dir = rng:NextUnitVector() * 200
		local blocked = false
		for _, p in solids do
			if p:IsDescendantOf(Mock.workspace.Lobby) and Mock.rayBox(center, dir, p) then
				blocked = true
				break
			end
		end
		if not blocked then open += 1 end
	end
	check(open == 0, "%d of 400 rays escaped the lobby", open)
end)

test("major structures are within the arena boundary and visible landmarks are spaced", function()
	for _, m in CS:GetTagged("FinalZone") do
		check(m._props.CFrame.p.Magnitude < Config.Arena.HardRadius - 200, "landmark %s too close to boundary", m:GetAttribute("Label"))
	end
	local ship = WorldBuilder.ShipCFrame.Position
	check((ship - V3.zero).Magnitude > 450, "ship too close to station")
	check((ship - V3.zero).Magnitude < 900, "ship too far from station")
end)

test("pressurised volumes cover interiors but not hangars/airlocks", function()
	local Oxygen = svc("OxygenService")
	local S = builder("Station").Scale
	check(Oxygen.IsPressurized(V3.new(0, 0, 0)), "hub should be pressurised")
	check(Oxygen.IsPressurized(V3.new(0, 85, 0) * S), "command module should be pressurised")
	check(not Oxygen.IsPressurized(V3.new(0, -96, 0) * S), "docking bay is open to space")
	check(Oxygen.IsPressurized(V3.new(0, 0, -140) * S), "hydroponics pressurised (holo doors keep the air in)")
	check(#CS:GetTagged("HoloDoor") >= 15, "expected many holo doors, got %d", #CS:GetTagged("HoloDoor"))
	check(not Oxygen.IsPressurized(V3.new(0, 300, 900)), "open space must not be pressurised")
	check(Oxygen.IsPressurized(WorldBuilder.ShipCFrame * V3.new(18, 0, 0)), "ship cargo hold pressurised")
end)

-------------------------------------------------------------------------------------------- server match
print("\n== Server systems (simulated match) ==")
Mock.errors = {}
Mock.isStudio = false -- live-server rules: 2 players minimum
Config.Bots.Enabled = false -- the 2-player scenarios below run without bots; bots get their own section
local Roster = svc("Roster")
local Combat = svc("CombatService")
local Security = svc("SecurityService")
for _, name in { "Roster" } do svc(name).Start() end
Security.Start(Roster.IsActive, function(p, amount, cause) Combat.ApplyDamage(p, amount, nil, cause) end)
for _, name in { "CharacterService", "DataService", "InventoryService", "CombatService", "LootService", "OxygenService", "SafeZoneService",
	"EquipmentService", "HazardService", "BotService", "MatchService" } do
	svc(name).Start()
end
local Inventory = svc("InventoryService")
local DataService = svc("DataService")
local Remotes = shared("Remotes")
local RS = Mock.services.ReplicatedStorage
local matchState = RS:FindFirstChild("MatchState")

local alice = Mock.addPlayer("Alice", 1)
local bob = Mock.addPlayer("Bob", 2)
Mock.advance(1)

local function root(p) return p._props.Character and p._props.Character:FindFirstChild("HumanoidRootPart") end
local function hum(p) return p._props.Character and p._props.Character:FindFirstChildOfClass("Humanoid") end
local function place(p, pos, lookAt)
	Security.Teleported(p)
	p._props.Character:PivotTo(lookAt and CF.lookAt(pos, lookAt) or CF.new(pos))
end
local function sentTo(p, remote, t)
	local out = {}
	for _, s in Mock.sent or {} do
		if s.remote == remote and (s.player == p or s.player == "all") and s.msg.t == t then table.insert(out, s.msg) end
	end
	return out
end

test("players load profiles and spawn in the lobby with the practice kit", function()
	for _, p in { alice, bob } do
		check(DataService.Get(p) ~= nil, "%s has no profile", p.Name)
		check(root(p) ~= nil, "%s has no character", p.Name)
		check((root(p)._props.CFrame.p - Config.Arena.LobbyCenter).Magnitude < 80, "%s not in lobby", p.Name)
		local inv = Inventory.Get(p)
		check(inv and inv.practice, "%s missing practice kit", p.Name)
	end
	check(matchState:GetAttribute("Phase") == "Waiting" or matchState:GetAttribute("Phase") == "Countdown", "phase %s", tostring(matchState:GetAttribute("Phase")))
end)

test("lobby practice: shots are validated and never hurt other players", function()
	local h = hum(bob)
	place(alice, Config.Arena.LobbyCenter + V3.new(0, 0, 10), Config.Arena.LobbyCenter + V3.new(0, 0, -10))
	place(bob, Config.Arena.LobbyCenter + V3.new(0, 0, -10))
	local origin = root(alice)._props.CFrame.p
	Remotes.Combat.OnServerEvent:Fire(alice, { action = "fire", origin = origin, dirs = { (root(bob)._props.CFrame.p - origin).Unit }, expectMag = 11 })
	check(h.Health == 100, "practice shot damaged a player")
	check(Inventory.Get(alice).weapons[1].mag == 11, "practice shot not consumed")
end)

local function advanceUntil(pred, maxSeconds)
	local t = 0
	while not pred() and t < maxSeconds do
		Mock.advance(0.25)
		t += 0.25
	end
	return pred()
end

test("countdown starts with 2 queued players and the match deploys both", function()
	advanceUntil(function() return matchState:GetAttribute("Phase") == "Active" end, 60)
	check(matchState:GetAttribute("Phase") == "Active", "phase is %s", tostring(matchState:GetAttribute("Phase")))
	for _, p in { alice, bob } do
		check(Roster.IsActive(p), "%s not active", p.Name)
		local pos = root(p)._props.CFrame.p
		check(pos.Magnitude < Config.Zone.StartRadius, "%s deployed outside zone", p.Name)
		local inv = Inventory.Get(p)
		check(inv and not inv.practice and inv.weapons[1].id == "pistol", "%s did not get the deploy kit", p.Name)
		check(p:GetAttribute("O2") >= Config.Oxygen.Max - 5, "O2 not (nearly) full at deployment")
	end
	print("        deployed at", tostring(root(alice)._props.CFrame.p), "|", tostring(root(bob)._props.CFrame.p))
	local d = (root(alice)._props.CFrame.p - root(bob)._props.CFrame.p).Magnitude
	check(d > 100, "deploy points too close (%d)", d)
	check(RS:FindFirstChild("ZoneState"):GetAttribute("Active") == true, "zone not active")
end)

-- put both players in open space inside the zone, facing each other
local A0, B0 = V3.new(0, 700, 400), V3.new(0, 700, 340)
local function face()
	place(alice, A0, B0)
	place(bob, B0, A0)
end
local function shoot(dirOverride, originOverride, expect)
	local o = originOverride or (root(alice)._props.CFrame.p + V3.new(0, 0.5, 0))
	local d = dirOverride or { (root(bob)._props.CFrame.p - o).Unit }
	Remotes.Combat.OnServerEvent:Fire(alice, { action = "fire", origin = o, dirs = d, expectMag = expect or 0 })
end

test("deployment shield blocks damage for the first seconds", function()
	face()
	local h = hum(bob)
	check(h.Health == 100, "bob hurt before the test (%d)", h.Health)
	shoot()
	check(h.Health == 100, "damage applied during deploy protection (%d)", h.Health)
	Mock.advance(Config.Match.DeployProtection + 0.5)
end)

test("server rejects exploit requests (origin, pellets, fire rate, no ammo)", function()
	face()
	local h = hum(bob)
	h.Health = 100
	local mag0 = Inventory.Get(alice).weapons[1].mag
	shoot(nil, V3.new(0, 700, 900)) -- origin 500 studs away
	check(Inventory.Get(alice).weapons[1].mag == mag0 and h.Health == 100, "far origin accepted")
	local dir = (root(bob)._props.CFrame.p - root(alice)._props.CFrame.p).Unit
	shoot({ dir, dir, dir, dir, dir, dir, dir, dir, dir }) -- shotgun pellets from a pistol
	check(Inventory.Get(alice).weapons[1].mag == mag0, "pellet count not enforced")
	shoot({ -dir }) -- behind the shooter
	check(Inventory.Get(alice).weapons[1].mag == mag0, "aim behind body accepted")
	shoot()
	check(Inventory.Get(alice).weapons[1].mag == mag0 - 1, "valid shot rejected")
	check(h.Health < 100, "valid shot did no damage")
	local hp = h.Health
	shoot() -- immediately again: faster than 360 rpm allows
	check(Inventory.Get(alice).weapons[1].mag == mag0 - 1 and h.Health == hp, "fire-rate limit not enforced")
	Mock.advance(0.2)
	shoot()
	check(Inventory.Get(alice).weapons[1].mag == mag0 - 2, "second valid shot rejected")
	-- fabricated packets for unknown actions / types are ignored
	Remotes.Combat.OnServerEvent:Fire(alice, "nonsense")
	Remotes.Combat.OnServerEvent:Fire(alice, { action = "fire", origin = "x", dirs = 5 })
	Remotes.Inventory.OnServerEvent:Fire(alice, { action = "use", item = "medkit" })
	check(#Mock.errors == 0, "handler errors: %s", table.concat(Mock.errors, "; "))
end)

test("shields absorb damage before health", function()
	bob:SetAttribute("Armor", 50)
	Inventory.Get(bob).armorMax = 50
	local h = hum(bob)
	local hp = h.Health
	Mock.advance(0.2)
	face()
	shoot()
	check(h.Health == hp, "health dropped while shield up")
	check(bob:GetAttribute("Armor") < 50, "shield not reduced")
end)

test("reload refills the magazine from reserve after the reload time", function()
	local inv = Inventory.Get(alice)
	local w = inv.weapons[1]
	local reserve = inv.ammo.light
	local mag = w.mag
	Remotes.Combat.OnServerEvent:Fire(alice, { action = "reload" })
	check(w.mag == mag, "reload was instant")
	Mock.advance(Weapons.Get("pistol").reload + 0.05)
	check(w.mag == 12, "mag not refilled (%d)", w.mag)
	check(inv.ammo.light == reserve - (12 - mag), "reserve not reduced correctly")
end)

test("inventory: stack limits, ammo caps, weapon swap drops the old weapon", function()
	local inv = Inventory.Get(alice)
	for _ = 1, 10 do Inventory.Add(alice, { id = "stim", rarity = "common", amount = 1 }) end
	check(inv.items.stim == Config.Inventory.ConsumableStack.stim, "stim stack %d", inv.items.stim)
	local ok, leftover = Inventory.Add(alice, { id = "ammo_light", rarity = "common", amount = 500 })
	check(ok and inv.ammo.light == Config.Inventory.AmmoCap.light and leftover and leftover.amount > 0, "ammo cap / leftover")
	Inventory.Add(alice, { id = "weapon:smg", rarity = "rare", amount = 1 })
	Inventory.Add(alice, { id = "weapon:shotgun", rarity = "common", amount = 1 })
	local _, _, dropped = Inventory.Add(alice, { id = "weapon:precision", rarity = "epic", amount = 1 })
	check(dropped ~= nil and dropped.id == "weapon:pistol", "full slots should swap out the active weapon")
	check(inv.weapons[1].id == "precision", "new weapon not in active slot")
	local okUp = Inventory.Add(alice, { id = "o2_recycler", rarity = "rare", amount = 1 })
	local okUp2 = Inventory.Add(alice, { id = "o2_recycler", rarity = "rare", amount = 1 })
	check(okUp and not okUp2, "upgrades must not stack")
	check(alice:GetAttribute("O2Efficiency") < 1, "upgrade not applied")
	check(alice:GetAttribute("SpeedMult") < 1, "precision rifle should slow the player")
end)

test("loot containers: search spawns pickups, pickups go into the inventory", function()
	local LootSvc = svc("LootService")
	local containers = CS:GetTagged("LootContainer")
	check(#containers > 50, "only %d containers seeded", #containers)
	local box = containers[1]
	place(bob, box._props.CFrame.p + V3.new(0, 4, 0))
	local prompt = box:FindFirstChildOfClass("ProximityPrompt")
	local before = #CS:GetTagged("Pickup")
	prompt.Triggered:Fire(alice) -- alice is far away: must be refused
	check(box:GetAttribute("Searched") ~= true, "search from far away accepted")
	prompt.Triggered:Fire(bob)
	check(box:GetAttribute("Searched") == true, "search failed")
	local pickups = CS:GetTagged("Pickup")
	check(#pickups > before, "no pickups spawned")
	local got = 0
	for _, pk in pickups do
		local pp = pk:FindFirstChildOfClass("ProximityPrompt")
		local was = pk._props.Destroyed
		pp.Triggered:Fire(bob)
		if pk._props.Destroyed and not was then got += 1 end
	end
	check(got > 0, "could not pick anything up")
	local _ = LootSvc
end)

test("oxygen drains in vacuum, refills inside, hypoxia only after the grace period", function()
	face()
	bob:SetAttribute("O2", 10)
	local h = hum(bob)
	h.Health = 100
	Mock.advance(10 / (Config.Oxygen.DrainPerSecond) + 0.5)
	check(bob:GetAttribute("O2") == 0, "O2 should be empty, is %s", tostring(bob:GetAttribute("O2")))
	local hpAtZero = h.Health
	Mock.advance(Config.Oxygen.GraceSeconds - 1)
	check(h.Health == hpAtZero, "hypoxia damage before grace period ended")
	Mock.advance(3)
	check(h.Health < hpAtZero, "no hypoxia damage after grace period")
	place(bob, V3.new(0, 0, 0)) -- station hub (pressurised)
	Mock.advance(2)
	check(bob:GetAttribute("O2") > 10, "O2 not refilling inside")
	check(bob:GetAttribute("Pressurized") == true, "pressurised flag")
	h.Health = 100
end)

test("storm damages players outside the safe sphere", function()
	place(bob, V3.new(0, 0, 0))
	local zs = RS:FindFirstChild("ZoneState")
	local h = hum(bob)
	h.Health = 100
	bob:SetAttribute("O2", 100)
	-- drop a player far outside the current radius but within the hard arena boundary
	local r = zs:GetAttribute("Radius")
	check(r <= Config.Zone.StartRadius, "zone radius")
	local probe = V3.new(0, 0, (Config.Zone.StartRadius + Config.Arena.HardRadius) / 2)
	place(bob, probe)
	Mock.advance(2)
	check(bob:GetAttribute("InStorm") == true, "InStorm flag")
	check(h.Health < 100, "no storm damage")
	place(bob, V3.new(0, 0, 0))
	h.Health = 100
end)

test("elimination: kill feed, death locker, last player standing wins, rewards saved", function()
	face()
	local h = hum(bob)
	bob:SetAttribute("Armor", 0)
	h.Health = 20
	local xpBefore = DataService.Get(alice).xp
	check(Roster.Get(bob).alive and Roster.Get(alice).alive, "both must still be alive before the duel (phase %s)", tostring(matchState:GetAttribute("Phase")))
	Mock.advance(0.3)
	shoot()
	Mock.advance(0.3)
	shoot()
	check(h.Health <= 0, "bob should be dead (hp %s)", tostring(h.Health))
	check(Roster.Get(bob).alive == false, "bob still alive in roster")
	check(Roster.Get(alice).kills == 1, "kill not credited")
	check(#sentTo(alice, "FX", "killfeed") > 0, "no kill feed")
	local lockers = 0
	for _, c in CS:GetTagged("LootContainer") do
		local pr = c:FindFirstChildOfClass("ProximityPrompt")
		if pr and string.find(tostring(pr.ObjectText), "Bob") then lockers += 1 end
	end
	check(lockers == 1, "death locker missing")
	Mock.advance(6)
	check(matchState:GetAttribute("Winner") == "Alice" or #sentTo(alice, "FX", "winner") > 0, "winner not declared")
	Mock.advance(Config.Match.ResultsTime + 3)
	local res = sentTo(alice, "Match", "results")
	check(#res == 1 and res[1].placement == 1 and res[1].kills == 1, "alice results wrong")
	local resB = sentTo(bob, "Match", "results")
	check(#resB == 1 and resB[1].placement == 2, "bob results wrong")
	check(DataService.Get(alice).xp > xpBefore and DataService.Get(alice).wins == 1, "rewards not applied")
	check(matchState:GetAttribute("Phase") == "Waiting" or matchState:GetAttribute("Phase") == "Countdown", "did not return to lobby phase: %s",
		tostring(matchState:GetAttribute("Phase")))
	for _, p in { alice, bob } do
		check(not Roster.Get(p).inMatch, "%s still marked in match", p.Name)
		check((root(p)._props.CFrame.p - Config.Arena.LobbyCenter).Magnitude < 80, "%s not returned to lobby", p.Name)
	end
end)

test("second match starts automatically; a disconnect ends it cleanly", function()
	Mock.sent = {}
	advanceUntil(function() return matchState:GetAttribute("Phase") == "Active" end, 60)
	check(matchState:GetAttribute("Phase") == "Active", "second match not active: %s", tostring(matchState:GetAttribute("Phase")))
	check(#CS:GetTagged("LootContainer") > 50, "loot not re-seeded")
	Mock.advance(Config.Match.DeployProtection + 1)
	Mock.removePlayer(bob)
	Mock.advance(8)
	check(#sentTo(alice, "Match", "results") == 1, "match did not end after disconnect")
	local res = sentTo(alice, "Match", "results")[1]
	check(res.placement == 1, "remaining player should win")
	Mock.advance(Config.Match.ResultsTime + 3)
	check(not Roster.Get(alice).inMatch, "alice stuck in match")
end)

test("no server thread errors during the simulation", function()
	check(#(Mock.errors or {}) == 0, "errors:\n          %s", table.concat(Mock.errors or {}, "\n          "))
end)

-------------------------------------------------------------------------------------------- client movement
print("\n== Client zero-g movement (MovementController driven headlessly) ==")
local M = Config.Movement
local localPlayer = Mock.addPlayer("Pilot", 99)
Mock.services.Players._props.LocalPlayer = localPlayer
local cam = Mock.Instance.new("Camera")
cam.CFrame = CF.identity
Mock.workspace._props.CurrentCamera = cam
-- let the server finish spawning the pilot in the lobby, and keep it out of matches
Mock.advance(3)
Roster.Get(localPlayer).queued = false
local pilotChar = localPlayer.Character
Security.Teleported(localPlayer)
pilotChar:PivotTo(CF.new(0, 500, 0))
local function client(name) return Mock.module("StarterPlayer", "StarterPlayerScripts", "Controllers", name) end
local CState = client("ClientState")
client("InputController").Start()
client("CameraController").Start()
local Movement = client("MovementController")
Movement.Start()
local proot = pilotChar:FindFirstChild("HumanoidRootPart")
local RunService = Mock.services.RunService
local function sim(seconds, keys)
	table.clear(Mock.keys)
	for _, k in keys or {} do Mock.keys[k] = true end
	for _ = 1, math.floor(seconds * 60) do
		RunService.PreSimulation:Fire(1 / 60)
		Mock.advance(1 / 60)
	end
	table.clear(Mock.keys)
end
local function vel() return proot.AssemblyLinearVelocity end

test("thrust accelerates along the view and caps at cruise speed", function()
	proot.AssemblyLinearVelocity = V3.zero
	sim(0.5, { "W" })
	check(near(vel().Magnitude, M.Accel * 0.5, 2), "speed after 0.5 s: %.1f", vel().Magnitude)
	check(vel().Z < 0 and math.abs(vel().X) < 1e-6, "W should thrust along -Z (camera look)")
	sim(3, { "W" })
	check(near(vel().Magnitude, M.MaxSpeed, 0.5), "cruise cap: %.1f", vel().Magnitude)
end)

test("momentum is kept when keys are released (drift)", function()
	local before = vel().Magnitude
	sim(2)
	check(vel().Magnitude > before * 0.8, "drift decayed too fast: %.1f -> %.1f", before, vel().Magnitude)
	check(vel().Magnitude < before, "drag should slowly settle the drift")
end)

test("stabilise (X) brings the player to a complete stop", function()
	sim(2, { "X" })
	check(vel().Magnitude == 0, "still moving at %.2f", vel().Magnitude)
end)

test("six directions: strafe, up and down are camera relative", function()
	for _, case in { { "D", "X", 1 }, { "A", "X", -1 }, { "Space", "Y", 1 }, { "LeftControl", "Y", -1 }, { "S", "Z", 1 } } do
		proot.AssemblyLinearVelocity = V3.zero
		sim(0.3, { case[1] })
		check(vel()[case[2]] * case[3] > 10, "%s should move along %s%d", case[1], case[3] > 0 and "+" or "-", case[2])
	end
	proot.AssemblyLinearVelocity = V3.zero
	sim(0.3, { "W", "D" })
	check(near(vel().Magnitude, M.Accel * 0.3, 1.5), "diagonal thrust must not be faster than straight thrust")
end)

test("boost is faster but limited by energy, then bleeds back to cruise", function()
	proot.AssemblyLinearVelocity = V3.zero
	CState.Boost = M.BoostMax
	sim(1.5, { "W", "LeftShift" })
	check(vel().Magnitude > M.MaxSpeed + 20, "boost too slow: %.1f", vel().Magnitude)
	check(vel().Magnitude <= M.BoostMaxSpeed + 0.5, "boost exceeded cap: %.1f", vel().Magnitude)
	sim(M.BoostMax / M.BoostDrain + 1, { "W", "LeftShift" })
	check(CState.Boost < 1, "boost energy should be exhausted (%.1f)", CState.Boost)
	sim(2, { "W", "LeftShift" })
	check(vel().Magnitude <= M.MaxSpeed + 0.5, "speed should bleed to cruise once energy is gone: %.1f", vel().Magnitude)
	sim(M.BoostRegenDelay + 2)
	check(CState.Boost > 10, "boost should regenerate")
end)

test("tether pulls toward the anchor and releases on arrival", function()
	sim(3, { "X" })
	Security.AllowBurst(localPlayer, 10) -- the mock does not integrate positions; these are test teleports
	proot._props.CFrame = CF.new(0, 500, 0)
	Movement.StartTether(V3.new(0, 500, -100), Config.Tether.MaxDuration)
	sim(0.6)
	check(vel().Z < -40, "tether pull too weak: %.1f", vel().Z)
	proot._props.CFrame = CF.new(0, 500, -97) -- arrive (the mock does not integrate positions)
	sim(0.1)
	check(CState.Tether == nil, "tether should release near the anchor")
end)

test("server impulses (explosions/knockback) add to velocity; boundary push sets it", function()
	proot.AssemblyLinearVelocity = V3.zero
	Movement.ApplyImpulse(V3.new(25, 0, 0))
	check(near(vel().X, 25), "impulse not applied: %s", tostring(vel()))
	Movement.ApplyImpulse(V3.new(0, 0, 40), true)
	check(near(vel().X, 0) and near(vel().Z, 40), "set-impulse should replace velocity")
end)

-------------------------------------------------------------------------------------------- client UI smoke
print("\n== Client bootstrap, HUD, menu and effects (smoke) ==")
cam.ViewportSize = Vector2.new(1280, 720)
local RS2 = Mock.services.RunService
local function frames(n)
	for _ = 1, n do
		RS2.RenderStepped:Fire(1 / 60)
		for _, fn in Mock.renderSteps or {} do fn(1 / 60) end
		Mock.advance(1 / 60)
	end
end

test("ClientMain boots every controller without errors", function()
	Mock.errors = {}
	Mock.require(Mock.services.StarterPlayer.StarterPlayerScripts.ClientMain)
	frames(10)
	check(#Mock.errors == 0, "errors: %s", table.concat(Mock.errors, "; "))
	check(localPlayer.PlayerGui:FindFirstChild("ZG_HUD") ~= nil, "HUD not created")
	check(localPlayer.PlayerGui:FindFirstChild("ZG_Menu") ~= nil, "menu not created")
end)

test("every server->client message type is handled", function()
	Mock.errors = {}
	local FX, MatchR, InvR = Remotes.FX.OnClientEvent, Remotes.Match.OnClientEvent, Remotes.Inventory.OnClientEvent
	InvR:Fire({ t = "sync", weapons = { { id = "assault", rarity = "epic", mag = 20, magSize = 37 }, false, { id = "shotgun", rarity = "common", mag = 6, magSize = 6 } },
		active = 1, ammo = { light = 10, medium = 90, heavy = 0, shells = 12, energy = 0 }, items = { medkit = 1, stim = 2, o2canister = 1, shieldcell = 0, grenade = 1 },
		tether = 3, upgrades = { boost_cell = true }, armorMax = 75, practice = false })
	MatchR:Fire({ t = "profile", data = { level = 3, xp = 900, credits = 120, matches = 4, wins = 1, kills = 7, damage = 2400, bestPlacement = 1,
		timeSurvived = 1300, suit = "graphite", title = "recruit", loadout = "medic", settings = { sensitivity = 1.2, invertY = false, fov = 80 } }, temporary = true })
	localPlayer:SetAttribute("InMatch", true)
	localPlayer:SetAttribute("Alive", true)
	localPlayer:SetAttribute("O2", 12)
	localPlayer:SetAttribute("Armor", 40)
	localPlayer:SetAttribute("ArmorMax", 75)
	MatchR:Fire({ t = "deployed", protect = 4 })
	for _, msg in {
		{ t = "tracer", from = V3.new(0, 500, 0), ends = { V3.new(0, 500, -50) }, weapon = "helios" },
		{ t = "hit", amount = 33, kill = false }, { t = "hit", amount = 50, kill = true },
		{ t = "damaged", from = V3.new(20, 500, 0), amount = 15, shield = true }, { t = "damaged", amount = 3, cause = "zone" },
		{ t = "killfeed", killer = "Alice", victim = "Bob", weapon = "AR-7 Pulse Rifle", cause = "gunfire" },
		{ t = "killfeed", victim = "Carol", cause = "the radiation storm" },
		{ t = "notice", text = "STORM CONTRACTING", sound = "alarm" }, { t = "explosion", pos = V3.new(0, 500, -10), radius = 20 },
		{ t = "fuse", pos = V3.zero }, { t = "using", item = "medkit", time = 3 }, { t = "reload", time = 2 },
		{ t = "pickup", name = "Med Stim", rarity = "common" }, { t = "search", pos = V3.zero }, { t = "airlock", pos = V3.zero },
		{ t = "melee", pos = V3.zero }, { t = "tether", player = alice, point = V3.new(0, 0, 10), duration = 1 }, { t = "tetherEnd", player = alice },
		{ t = "impulse", v = V3.new(0, 5, 0) }, { t = "winner", name = "Alice" },
	} do
		FX:Fire(msg)
	end
	frames(30)
	MatchR:Fire({ t = "eliminated", by = "Alice", cause = "gunfire", placement = 2 })
	MatchR:Fire({ t = "results", winner = "Alice", placement = 2, total = 12, kills = 3, damage = 812, survived = 431, xp = 260, credits = 130,
		levelUp = true, level = 4 })
	frames(30)
	InvR:Fire({ t = "clear" })
	frames(5)
	check(#Mock.errors == 0, "errors:\n          %s", table.concat(Mock.errors, "\n          "))
end)

test("HUD keeps running through lobby, match, spectate and results states", function()
	Mock.errors = {}
	local zs = RS:FindFirstChild("ZoneState")
	zs:SetAttribute("Active", true)
	zs:SetAttribute("NextCenter", V3.new(100, 0, 0))
	zs:SetAttribute("NextRadius", 400)
	zs:SetAttribute("Phase", "waiting")
	zs:SetAttribute("NextTime", Mock.clock() + 30)
	for _, phase in { "Waiting", "Countdown", "Active", "Final", "Ending", "Results" } do
		matchState:SetAttribute("Phase", phase)
		frames(5)
	end
	localPlayer:SetAttribute("Alive", false) -- spectating
	alice:SetAttribute("Alive", true)
	alice:SetAttribute("InMatch", true)
	matchState:SetAttribute("Phase", "Active")
	frames(10)
	check(#Mock.errors == 0, "errors:\n          %s", table.concat(Mock.errors, "\n          "))
end)

-------------------------------------------------------------------------------------------------- bots
print("\n== Bots (19 bots + 1 player, full simulated match) ==")
local Bots = svc("BotService")
local Nav = svc("NavGraph")
Mock.errors, Mock.warnings, Mock.sent = {}, {}, {}

test("navigation graph reaches every pressurised interior from open space", function()
	local st = Nav.Stats()
	print(string.format("        nav: %d nodes, %d edges, %d exits, %d spaces", st.nodes, st.edges, st.exits, st.spaces))
	check(st.exits >= 15, "too few exits: %d", st.exits)
	local unreachable = {}
	local from = V3.new(0, 600, 300)
	local lobbyFolder = Mock.workspace:FindFirstChild("Lobby")
	for _, z in CS:GetTagged("Pressurized") do
		if not z:IsDescendantOf(lobbyFolder) then
			local path = Nav.Path(from, z._props.CFrame.p)
			if not path then table.insert(unreachable, tostring(z:GetAttribute("ZoneId"))) end
		end
	end
	check(#unreachable == 0, "no route into: %s", table.concat(unreachable, ", "))
	local p = Nav.Path(V3.new(0, 0, 0), WorldBuilder.ShipCFrame * V3.new(18, 0, 0)) -- hub -> ship cargo hold
	check(p and #p > 3, "no hub -> ship route")
	local usesAirlock = false
	for _, wp in p do
		if wp.door then usesAirlock = true end
	end
	check(usesAirlock, "hub -> ship route should cycle an airlock")
end)

test("19 bots fill the lobby when one player is online", function()
	Mock.removePlayer(localPlayer)
	Config.Bots.Enabled = true
	Bots.Rebalance()
	Mock.advance(1)
	check(#Bots.All() == Config.Bots.FillTo - 1, "expected %d bots, got %d", Config.Bots.FillTo - 1, #Bots.All())
	for _, b in Bots.All() do
		local r = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
		check(r and (r._props.CFrame.p - Config.Arena.LobbyCenter).Magnitude < 90, "%s not in the lobby", b.Name)
		check(RS.Bots:FindFirstChild(b.Name) ~= nil, "%s not published for clients", b.Name)
	end
end)

test("lobby bots drift and practise on the range without hurting anyone", function()
	local h = hum(alice)
	local hp = h.Health
	local before = {}
	for _, b in Bots.All() do before[b] = b.Character.HumanoidRootPart._props.CFrame.p end
	Mock.advance(12)
	local moved = 0
	for _, b in Bots.All() do
		if b.Character and (b.Character.HumanoidRootPart._props.CFrame.p - before[b]).Magnitude > 2 then moved += 1 end
	end
	check(moved >= 10, "only %d bots moved", moved)
	check(#sentTo(alice, "FX", "tracer") > 0, "no practice shots seen")
	check(h.Health == hp, "lobby practice hurt a player")
end)

local matchStats = {}
-- Compress the storm schedule so the simulated match takes minutes, not a quarter of an hour.
for _, st in Config.Zone.Stages do
	st.wait *= 0.35
	st.shrink *= 0.35
end
test("a full 20-combatant match plays out to a winner", function()
	Mock.sent = {}
	local rays0, clock0 = Mock.stats.rays, os.clock()
	check(advanceUntil(function() return matchState:GetAttribute("Phase") == "Active" end, 60), "match never started (%s)",
		tostring(matchState:GetAttribute("Phase")))
	check(matchState:GetAttribute("Participants") == 20, "participants %s", tostring(matchState:GetAttribute("Participants")))
	local t0 = Mock.clock()
	local firstKillAt
	local lastReport = 0
	check(advanceUntil(function()
		if not firstKillAt and matchState:GetAttribute("AliveCount") < 20 then firstKillAt = Mock.clock() - t0 end
		if Mock.clock() - lastReport > 30 then
			lastReport = Mock.clock()
			local tasks = {}
			for _, b in Bots.All() do
				if Roster.IsActive(b) then
					local k = b.brain.task ~= "" and b.brain.task or "-"
					tasks[k] = (tasks[k] or 0) + 1
				end
			end
			local tl = {}
			for k, n in tasks do table.insert(tl, k .. "=" .. n) end
			table.sort(tl)
			print(string.format("        t=%3.0fs alive=%d rays=%d cpu=%.0fs  [%s]", Mock.clock() - t0, matchState:GetAttribute("AliveCount"),
				Mock.stats.rays - rays0, os.clock() - clock0, table.concat(tl, " ")))
		end
		local ph = matchState:GetAttribute("Phase")
		return ph == "Ending" or ph == "Results" or ph == "Waiting" or ph == "Countdown"
	end, Config.Match.MaxMatchTime + 60), "match did not finish")
	matchStats.duration = Mock.clock() - t0
	matchStats.firstKill = firstKillAt
	local winner = matchState:GetAttribute("Winner")
	local kills = 0
	for _, b in Bots.All() do kills += b:GetAttribute("Kills") or 0 end
	matchStats.kills = kills
	print(string.format("        match lasted %.0fs, first elimination at %.0fs, bot kills %d, winner %s", matchStats.duration, firstKillAt or -1, kills,
		tostring(winner)))
	print(string.format("        (mock: %d raycasts, %.1fs CPU)", Mock.stats.rays - rays0, os.clock() - clock0))
	check(winner ~= nil and winner ~= "", "no winner declared")
	check(kills >= 5, "bots barely fought (%d kills)", kills)
	check(#sentTo(alice, "FX", "killfeed") >= 10, "too few eliminations in the kill feed")
end)

test("bots looted, used the validated fire path and never tripped security", function()
	local searched = 0
	for _, s in Mock.sent or {} do
		if s.msg.t == "search" then searched += 1 end
	end
	check(searched >= 5, "bots searched only %d containers", searched)
	for _, w in Mock.warnings do
		check(not string.find(w, "error"), "warning: %s", w)
		check(not string.find(w, "Security"), "security flag: %s", w)
	end
	check(#(Mock.errors or {}) == 0, "errors: %s", table.concat(Mock.errors or {}, "; "))
end)

test("after the match bots return to the lobby and a new round begins", function()
	advanceUntil(function() return matchState:GetAttribute("Phase") == "Countdown" or matchState:GetAttribute("Phase") == "Active" end, 40)
	local inLobby = 0
	for _, b in Bots.All() do
		local r = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
		if r and (r._props.CFrame.p - Config.Arena.LobbyCenter).Magnitude < 90 then inLobby += 1 end
	end
	check(#Bots.All() == 19 and inLobby >= 15, "bots %d, in lobby %d", #Bots.All(), inLobby)
	-- a second real player joining replaces a bot (between matches)
	local carol = Mock.addPlayer("Carol", 7)
	Mock.advance(1)
	local r = Roster.Get(carol)
	check(#Bots.All() == 18 or (r and r.inMatch), "bot count after join: %d", #Bots.All())
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
