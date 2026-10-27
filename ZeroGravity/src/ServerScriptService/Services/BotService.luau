-- Bots: server-simulated combatants that keep every lobby and match at Config.Bots.FillTo (20).
--
-- Fair by construction: bots act ONLY through the same server entry points players use
-- (Combat.Fire / Reload / Equip / Melee, Loot.Search / Take, Inventory.Use, Equipment.ThrowGrenade,
-- Oxygen.UseStation, airlock requests) so fire rate, ammo, spread, aim cone, pickup range and
-- cooldowns are validated exactly as for a human. They move with the shared ZeroGMotion model
-- (same acceleration, caps, boost energy and braking).
--
-- Skill (0..1 per bot, Config.Bots.SkillMin..SkillMax) shapes reaction time, aim error and its
-- settling, headshot preference, strafing and tactical choices. Behaviour priority each think:
--   storm > oxygen > fight > heal > loot > hunt, with navigation through station and ship
--   interiors (NavGraph, airlocks cycled like a player would), obstacle avoidance and unsticking.
-- Between matches bots float around the lobby and practise on the range drones.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.WeaponDefinitions)
local Items = require(Shared.ItemDefinitions)
local Cosmetics = require(Shared.Cosmetics)
local Loadouts = require(Shared.Loadouts)
local Motion = require(Shared.ZeroGMotion)
local Gravity = require(Shared.Gravity)
local Remotes = require(Shared.Remotes)
local Kit = require(script.Parent.Parent:WaitForChild("Builders"):WaitForChild("Kit"))
local Roster = require(script.Parent.Roster)
local CharacterService = require(script.Parent.CharacterService)
local Inventory = require(script.Parent.InventoryService)
local Combat = require(script.Parent.CombatService)
local Loot = require(script.Parent.LootService)
local Oxygen = require(script.Parent.OxygenService)
local Equipment = require(script.Parent.EquipmentService)
local Hazards = require(script.Parent.HazardService)
local Nav = require(script.Parent.NavGraph)

local Bots = {}
local B = Config.Bots
local MV = Config.Movement
local GV = Config.Gravity
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
local bots: { any } = {}
local cfgFolder: Folder
local charFolder: Folder
local rng = Random.new()
local nextId = 0
local claims: { [Instance]: any } = {} -- container -> bot heading for it (spreads bots out)

local NAMES = {
	"Vex", "Orion", "Kestrel", "Nyx", "Rook", "Halcyon", "Juno", "Talon", "Ash", "Vega", "Sable", "Quill", "Echo", "Rune", "Cobalt",
	"Wraith", "Lumen", "Pike", "Nova", "Drift", "Hex", "Zephyr", "Kite", "Onyx", "Saber", "Flint", "Iris", "Corvus", "Ember", "Atlas",
	"Mako", "Specter", "Lyra", "Grit", "Tycho", "Rhea", "Bishop", "Comet", "Vanta", "Shrike", "Ion", "Wren", "Banshee", "Strix",
	"Polaris", "Torque", "Raptor", "Cinder", "Moth", "Kairo", "Delta", "Tamsin", "Brink", "Caspian", "Riven", "Solace", "Jett", "Voss",
	"Marlow", "Quasar", "Zeal", "Ronin", "Tessa", "Fable",
}
local SUFFIX = { "", "_7", "X", "-9", "01", "_rx", "42", "Prime", "_v2", "77", "", "", "" }

-- Preferred engagement distance per weapon (studs).
local PREF_RANGE = { shotgun = 12, arc = 11, smg = 34, pistol = 40, assault = 75, burst = 85, helios = 90, precision = 230 }
local WEAPON_TIER = { pistol = 1, arc = 2, smg = 3, shotgun = 3, assault = 4, burst = 4, precision = 4, helios = 5 }

local BotMeta = {}
BotMeta.__index = BotMeta
function BotMeta:GetAttribute(k: string) return self._cfg:GetAttribute(k) end
function BotMeta:SetAttribute(k: string, v: any) self._cfg:SetAttribute(k, v) end

local function lerp(a: number, b: number, t: number): number return a + (b - a) * t end

local function uniqueName(): string
	local used = {}
	for _, b in bots do used[b.Name] = true end
	for _, p in Players:GetPlayers() do used[p.Name] = true end
	for _ = 1, 200 do
		local n = NAMES[rng:NextInteger(1, #NAMES)] .. SUFFIX[rng:NextInteger(1, #SUFFIX)]
		if not used[n] then return n end
	end
	nextId += 1
	return "Pilot" .. nextId
end

local function newBrain()
	return {
		mode = "lobby", moveDir = Vector3.zero, boost = false, brake = false, face = CFrame.new(),
		energy = MV.BoostMax, lastBoostUse = 0, nextThink = 0,
		path = nil, pathI = 1, pathGoal = nil, pathAt = 0,
		task = "", taskObj = nil,
		target = nil, acquiredAt = 0, seenAt = 0, lastSeenPos = nil, aimHead = false, errDeg = 8, errDir = Vector3.xAxis,
		strafe = 1, strafeUntil = 0, vert = 0,
		wantFire = false, nextShot = 0, burstLeft = 0,
		hurtAt = -100, threatPos = nil,
		progressPos = nil, progressAt = 0, escapeUntil = 0, escapeDir = Vector3.zero,
		nextGrenadeAt = 0, nextEquipAt = 0, nextUseAt = 0,
		lobbyGoal = nil, lobbyWaitUntil = 0, practiceAt = 0, practiceShots = 0,
		avoidDir = nil, avoidUntil = 0,
		nextRollAt = 0, aimingShown = false,
	}
end

local function newBot()
	nextId += 1
	local name = uniqueName()
	local cfg = Instance.new("Configuration")
	cfg.Name = name
	local charRef = Instance.new("ObjectValue")
	charRef.Name = "Character"
	charRef.Parent = cfg
	cfg.Parent = cfgFolder
	local suits = Cosmetics.Suits
	local bot: any = setmetatable({
		IsBot = true, Name = name, DisplayName = name, UserId = -nextId, Parent = cfg, Character = nil,
		_cfg = cfg, _charRef = charRef,
		skill = rng:NextNumber(B.SkillMin, B.SkillMax),
		suit = suits[rng:NextInteger(1, #suits)].id,
		loadout = Loadouts.List[rng:NextInteger(1, #Loadouts.List)].id,
		brain = newBrain(),
	}, BotMeta)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("Skill", math.floor(bot.skill * 100))
	local r = Roster.Get(bot)
	r.queued = false -- bots are drafted by MatchService, never queued
	Roster.Sync(bot)
	table.insert(bots, bot)
	return bot
end

local function displayName(bot): string
	return B.ShowTag and (bot.Name .. " [BOT]") or bot.Name
end

local function setCharacter(bot, char: Model?)
	bot._charRef.Value = char
end

local function lobbyPoint(): Vector3
	local c = Config.Arena.LobbyCenter
	return c + Vector3.new(rng:NextNumber(-44, 44), rng:NextNumber(-14, 14), rng:NextNumber(-28, 30))
end

-- Spawn (or respawn) a bot floating in the lobby with the practice kit.
function Bots.ToLobby(bot)
	if not bot.Parent then return end
	local p = lobbyPoint()
	local char = CharacterService.SpawnBot(bot, CFrame.lookAt(p, p + Vector3.new(0, 0, -1)), charFolder, displayName(bot))
	setCharacter(bot, char)
	bot.brain = newBrain()
	bot.brain.face = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1))
	if char then
		Combat.ResetPlayer(bot)
		Inventory.Reset(bot, "practice")
		Oxygen.Reset(bot)
	end
end

-- Body for a match deployment. MatchService resets inventory/oxygen and hooks death afterwards.
function Bots.Deploy(bot, cf: CFrame): Model?
	local char = CharacterService.SpawnBot(bot, cf, charFolder, displayName(bot))
	setCharacter(bot, char)
	bot.brain = newBrain()
	bot.brain.mode = "match"
	bot.brain.face = cf.Rotation
	bot.brain.deployedAt = os.clock()
	return char
end

function Bots.Remove(bot)
	if bot.Character then
		Roster.UnbindCharacter(bot.Character)
		bot.Character:Destroy()
	end
	for box, owner in claims do
		if owner == bot then claims[box] = nil end
	end
	local i = table.find(bots, bot)
	if i then table.remove(bots, i) end
	Roster.Remove(bot)
	bot._cfg:Destroy()
	bot.Parent = nil
end

function Bots.All(): { any }
	return bots
end

-- Bots available to draft into a match (alive in the lobby, not already in a match).
function Bots.ForMatch(n: number): { any }
	local out = {}
	for _, b in bots do
		if #out >= n then break end
		local r = Roster.Get(b)
		if r and not r.inMatch and b.Character then table.insert(out, b) end
	end
	return out
end

-- Keep (players + bots) at FillTo. Only lobby bots are removed; match bots finish their match.
-- realPlayers defaults to everyone online; MatchService passes the queued count at deployment so
-- every match has exactly FillTo combatants.
function Bots.Rebalance(realPlayers: number?)
	if not B.Enabled then
		for i = #bots, 1, -1 do
			if not Roster.Get(bots[i]).inMatch then Bots.Remove(bots[i]) end
		end
		return
	end
	local want = math.max(0, B.FillTo - (realPlayers or #Players:GetPlayers()))
	while #bots < want do
		Bots.ToLobby(newBot())
	end
	for i = #bots, 1, -1 do
		if #bots <= want then break end
		if not Roster.Get(bots[i]).inMatch then Bots.Remove(bots[i]) end
	end
end

------------------------------------------------------------------------------------------- perception
local function rootOf(c): BasePart?
	local ch = c and c.Character
	return ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humOf(c): Humanoid?
	local ch = c and c.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function rayParams(bot): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { bot.Character :: Model }
	return p
end

-- Can `bot` see `enemy`? (ray from the bot's head to the enemy's torso)
local function canSee(bot, enemy, params: RaycastParams): boolean
	local head = bot.Character and bot.Character:FindFirstChild("Head") :: BasePart?
	local er = rootOf(enemy)
	if not (head and er) then return false end
	local d = er.Position - head.Position
	local hit = workspace:Raycast(head.Position, d, params)
	if not hit then return true end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model do
		if model == enemy.Character then return true end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function enemiesOf(bot): { any }
	local out = {}
	local team = Roster.Get(bot).team
	for _, c in Roster.Active() do
		if c ~= bot then
			local r = Roster.Get(c)
			if not (team ~= 0 and r.team == team) then table.insert(out, c) end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------- inventory
local function weaponDps(w, dist: number): number
	local def = Weapons.Get(w.id)
	return Weapons.DamageAt(w.id, w.rarity, dist) * def.pellets * def.rpm / 60
end

local function bestSlotFor(bot, dist: number): number?
	local inv = Inventory.Get(bot)
	if not inv then return nil end
	local best, bestScore = nil, 0
	for slot = 1, Config.Inventory.WeaponSlots do
		local w = inv.weapons[slot]
		if w then
			local def = Weapons.Get(w.id)
			local hasAmmo = w.mag > 0 or inv.practice or inv.ammo[def.ammo] > 0
			local score = hasAmmo and weaponDps(w, dist) or 0
			if slot == inv.active then score *= 1.2 end -- avoid flip-flopping
			if score > bestScore then best, bestScore = slot, score end
		end
	end
	return best
end

local function weaponValue(id: string, rarity: string): number
	return (WEAPON_TIER[id] or 1) + (table.find(Items.Rarities, rarity) or 1) * 0.35
end

-- Would picking this loot entry improve the bot's kit?
local function wants(bot, entry): boolean
	local inv = Inventory.Get(bot)
	local def = entry and Items.Get(entry.id)
	if not (inv and def) then return false end
	local IC = Config.Inventory
	if def.kind == "weapon" then
		local worst, count = math.huge, 0
		for slot = 1, IC.WeaponSlots do
			local w = inv.weapons[slot]
			if w then
				count += 1
				worst = math.min(worst, weaponValue(w.id, w.rarity))
			end
		end
		return count < IC.WeaponSlots or weaponValue(def.weapon, entry.rarity or "common") > worst + 0.6
	elseif def.kind == "ammo" then
		for _, w in inv.weapons do
			if Weapons.Get(w.id).ammo == def.ammo and inv.ammo[def.ammo] < IC.AmmoCap[def.ammo] then return true end
		end
		return false
	elseif def.kind == "consumable" or (def.kind == "utility" and def.stack) then
		local key = def.stack or entry.id
		return inv.items[key] < (IC.ConsumableStack[key] or 1)
	elseif def.kind == "utility" then
		return inv.tether < Config.Tether.MaxCharges
	elseif def.kind == "armor" then
		return def.armorMax > inv.armorMax or (bot:GetAttribute("Armor") or 0) < inv.armorMax
	elseif def.kind == "upgrade" then
		return not inv.upgrades[entry.id]
	end
	return false
end

local function needsLoot(bot): boolean
	local inv = Inventory.Get(bot)
	if not inv then return false end
	local best = 0
	for _, w in inv.weapons do best = math.max(best, weaponValue(w.id, w.rarity)) end
	if best < 4 or inv.armorMax < 50 then return true end
	local w = inv.weapons[inv.active]
	if w and inv.ammo[Weapons.Get(w.id).ammo] < 20 then return true end
	return (inv.items.medkit + inv.items.stim) == 0
end

--------------------------------------------------------------------------------------------- movement
-- Steer around obstacles: probe ahead along `dir`, try deflections if blocked.
local function avoid(bot, root: BasePart, dir: Vector3, params: RaycastParams): Vector3
	local brain = bot.brain
	if dir.Magnitude < 0.01 then return Vector3.zero end
	dir = dir.Unit
	local now = os.clock()
	if brain.avoidDir and now < brain.avoidUntil then return brain.avoidDir end
	local speed = root.AssemblyLinearVelocity.Magnitude
	local probe = math.clamp(speed * 0.7, 9, 40)
	local origin = root.Position
	local function clear(d: Vector3): boolean
		local hit = workspace:Raycast(origin, d * probe, params)
		return hit == nil or Roster.FromCharacter(hit.Instance:FindFirstAncestorOfClass("Model")) ~= nil
	end
	if clear(dir) then return dir end
	local up = math.abs(dir.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
	local side = dir:Cross(up).Unit
	local vert = side:Cross(dir).Unit
	for _, cand in { (dir + side * 0.7).Unit, (dir - side * 0.7).Unit, (dir + vert * 0.7).Unit, (dir - vert * 0.7).Unit, side, -side, vert, -vert } do
		if clear(cand) then
			brain.avoidDir, brain.avoidUntil = cand, now + 0.35
			return cand
		end
	end
	brain.avoidDir, brain.avoidUntil = -dir, now + 0.5
	return -dir
end

-- Navigate toward `goal` (through interiors and airlocks when needed). Returns remaining distance.
local function navigate(bot, root: BasePart, goal: Vector3, params: RaycastParams, urgent: boolean): number
	local brain = bot.brain
	local now = os.clock()
	local pos = root.Position
	if not brain.path or not brain.pathGoal or (brain.pathGoal - goal).Magnitude > 25 or now - brain.pathAt > 5 then
		brain.path = Nav.Path(pos, goal) or { { pos = goal } }
		brain.pathI, brain.pathGoal, brain.pathAt = 1, goal, now
	end
	local path = brain.path
	local wp = path[brain.pathI]
	while wp and brain.pathI < #path and (wp.pos - pos).Magnitude < 5 do
		brain.pathI += 1
		wp = path[brain.pathI]
	end
	if not wp then
		brain.moveDir = Vector3.zero
		return 0
	end
	-- airlock door on the way: request it, hold short until it opens
	if wp.door and wp.airlock and not Hazards.IsAirlockDoorOpen(wp.airlock, wp.door) then
		local door = wp.airlock:FindFirstChild(wp.door) :: BasePart?
		local dd = door and (door.Position - pos).Magnitude or math.huge
		if dd < 16 then
			Hazards.RequestAirlockDoor(wp.airlock, wp.door, bot)
			brain.moveDir, brain.brake = Vector3.zero, true
			return (goal - pos).Magnitude
		end
	end
	local to = wp.pos - pos
	local remaining = (goal - pos).Magnitude
	local dir = avoid(bot, root, to, params)
	-- slow down for the final waypoint and inside tight spaces
	local speed = root.AssemblyLinearVelocity.Magnitude
	brain.brake = brain.pathI == #path and to.Magnitude < 14 and speed > to.Magnitude * 1.5
	brain.moveDir = dir
	brain.boost = urgent and to.Magnitude > 60 and brain.energy > 25
	if not brain.target then brain.face = CFrame.lookAt(Vector3.zero, dir) end
	return remaining
end

-- Unstick: if a moving bot makes no progress for 2 s, take a random escape burst and re-path.
local function unstick(bot, root: BasePart)
	local brain = bot.brain
	local now = os.clock()
	if now < brain.escapeUntil then
		brain.moveDir = brain.escapeDir
		return true
	end
	if now - brain.progressAt > 2 then
		local moved = brain.progressPos and (root.Position - brain.progressPos).Magnitude or math.huge
		brain.progressPos, brain.progressAt = root.Position, now
		if moved < 3 and brain.moveDir.Magnitude > 0.1 and not brain.wantFire then
			brain.escapeDir = rng:NextUnitVector()
			brain.escapeUntil = now + 0.9
			brain.path = nil
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------------------ combat
local function pickTarget(bot, root: BasePart, params: RaycastParams)
	local brain = bot.brain
	local now = os.clock()
	local enemies = enemiesOf(bot)
	table.sort(enemies, function(a, b)
		local ra, rb = rootOf(a), rootOf(b)
		return (ra and (ra.Position - root.Position).Magnitude or math.huge) < (rb and (rb.Position - root.Position).Magnitude or math.huge)
	end)
	local best, bestScore = nil, math.huge
	for i = 1, math.min(#enemies, 4) do
		local e = enemies[i]
		local er = rootOf(e)
		local d = er and (er.Position - root.Position).Magnitude or math.huge
		if d <= B.SightRange and canSee(bot, e, params) then
			local hum = humOf(e)
			local score = d * (0.6 + 0.4 * ((hum and hum.Health or 100) / 100))
			if e == brain.target then score *= 0.6 end -- stick with the current target
			if score < bestScore then best, bestScore = e, score end
		end
	end
	if best then
		if best ~= brain.target then
			brain.target = best
			brain.acquiredAt = now
			-- fresh target: big initial error that settles while tracking
			brain.errDeg = lerp(9, 3.5, bot.skill)
			brain.aimHead = rng:NextNumber() < 0.15 + 0.4 * bot.skill
		end
		brain.seenAt = now
		local br = rootOf(best)
		brain.lastSeenPos = br and br.Position
	elseif brain.target and (now - brain.seenAt > 2.5 or not Roster.IsActive(brain.target)) then
		brain.target = nil
	end
	return brain.target, brain.target ~= nil and now - brain.seenAt < 0.3
end

local function aimPartOf(bot, target): BasePart?
	local ch = target.Character
	if not ch then return nil end
	if bot.brain.aimHead then
		local head = ch:FindFirstChild("Head") :: BasePart?
		if head then return head end
	end
	return (ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso") or ch:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function fight(bot, root: BasePart, target, visible: boolean, params: RaycastParams)
	local brain = bot.brain
	local now = os.clock()
	local tr = rootOf(target)
	if not tr then return end
	local toT = tr.Position - root.Position
	local dist = toT.Magnitude
	local inv = Inventory.Get(bot)
	-- weapon for this range
	if now >= brain.nextEquipAt then
		local slot = bestSlotFor(bot, dist)
		if inv and slot and slot ~= inv.active then
			Combat.Equip(bot, slot)
			brain.nextEquipAt = now + 1.5
		end
	end
	local w = inv and inv.weapons[inv.active]
	local pref = w and PREF_RANGE[w.id] or 40
	-- range keeping + strafing (unpredictable lateral jinks, more for skilled bots)
	if now > brain.strafeUntil then
		brain.strafe = -brain.strafe
		brain.strafeUntil = now + lerp(2.4, 0.9, bot.skill) * rng:NextNumber(0.6, 1.4)
		brain.vert = rng:NextNumber() < 0.35 and (rng:NextNumber() < 0.5 and -1 or 1) or 0
	end
	local fwd = toT.Unit
	local up = math.abs(fwd.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
	local side = fwd:Cross(up).Unit
	local vert = side:Cross(fwd).Unit
	local radial = 0
	if dist > pref * 1.3 then radial = 1 elseif dist < pref * 0.6 then radial = -1 end
	local hum = humOf(bot)
	local lowHealth = hum and hum.Health < 30
	if lowHealth and dist < 150 then radial = -1 end -- break off and survive
	local dir = fwd * radial + side * brain.strafe * 0.8 + vert * brain.vert * 0.5
	if not visible and brain.lastSeenPos then
		-- lost sight: push toward the last known position
		dir = (brain.lastSeenPos - root.Position)
		if dir.Magnitude < 8 then brain.target = nil end
	end
	brain.moveDir = avoid(bot, root, dir, params)
	local recentlyHurt = now - brain.hurtAt < 0.8
	brain.boost = (recentlyHurt or dist > 180 or lowHealth) and brain.energy > 30
	brain.brake = false
	brain.face = CFrame.lookAt(Vector3.zero, fwd)
	-- aim settles while tracking; worse while either side moves fast
	local floor = lerp(3.0, 0.65, bot.skill)
	local motionPenalty = (tr.AssemblyLinearVelocity.Magnitude / 50) * lerp(2.2, 0.7, bot.skill)
		+ (root.AssemblyLinearVelocity.Magnitude / 50) * lerp(1.2, 0.4, bot.skill)
	brain.errDeg = math.max(floor + motionPenalty, brain.errDeg * lerp(0.82, 0.62, bot.skill))
	brain.errDir = (brain.errDir + rng:NextUnitVector() * 0.6).Unit
	-- fire once reaction time has passed and the target is in range
	local reaction = lerp(0.5, 0.17, bot.skill)
	local def = w and Weapons.Get(w.id)
	brain.wantFire = visible and def ~= nil and now - brain.acquiredAt >= reaction and dist <= def.maxRange * 0.9
	-- pulse charge at mid range, melee up close
	if visible and inv and inv.items.grenade > 0 and dist > 16 and dist < 48 and now >= brain.nextGrenadeAt and rng:NextNumber() < 0.25 then
		brain.nextGrenadeAt = now + 6
		local lead = tr.Position + tr.AssemblyLinearVelocity * (dist / Config.Grenade.Speed)
		Equipment.ThrowGrenade(bot, (lead - root.Position).Unit)
	end
	if visible and dist < Config.Melee.Range - 1 then
		root.CFrame = CFrame.lookAt(root.Position, tr.Position)
		Combat.Melee(bot)
	end
end

-- Called every Heartbeat for bots that want to fire: paces shots exactly like a player's trigger.
local function fireStep(bot, root: BasePart)
	local brain = bot.brain
	local now = os.clock()
	local target = brain.target
	if not (brain.wantFire and target and now >= brain.nextShot) then return end
	local weapon = Inventory.ActiveWeapon(bot)
	if not weapon or Combat.ReadyIn(bot) > 0 then return end
	if weapon.mag <= 0 then
		Combat.Reload(bot)
		brain.nextShot = now + 0.3
		return
	end
	local part = aimPartOf(bot, target)
	if not part then return end
	local def = Weapons.Get(weapon.id)
	local head = bot.Character:FindFirstChild("Head") :: BasePart?
	local held = bot.Character:FindFirstChild("HeldWeapon")
	local muzzle = held and held:FindFirstChild("Muzzle", true) :: Attachment?
	local origin = muzzle and muzzle.WorldPosition or (head and head.Position) or root.Position
	local dist = (part.Position - origin).Magnitude
	-- aim error as an angular offset around the line of fire
	local aimDir = (part.Position - origin).Unit
	local perp = brain.errDir - aimDir * brain.errDir:Dot(aimDir)
	if perp.Magnitude > 1e-3 then aimDir = (aimDir + perp.Unit * math.tan(math.rad(brain.errDeg))).Unit end
	-- face the shot (the server checks the body faces where it fires); under gravity the body stays
	-- upright and only turns to the shot's heading
	local up = Gravity.UpAt(root.Position)
	local flat = if up then aimDir - up * aimDir:Dot(up) else aimDir
	if up and flat.Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat, up)
	elseif not up then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + aimDir)
	end
	brain.face = CFrame.lookAt(Vector3.zero, aimDir)
	local steady = root.AssemblyLinearVelocity.Magnitude < 15 and dist > 50
	local spread = steady and def.adsSpread or def.spread
	local dirs = {}
	for i = 1, def.pellets do
		local cf = CFrame.lookAt(Vector3.zero, aimDir)
		local r = math.rad(spread) * math.sqrt(rng:NextNumber())
		local a = rng:NextNumber(0, math.pi * 2)
		dirs[i] = (cf * CFrame.Angles(math.sin(a) * r, math.cos(a) * r, 0)).LookVector
	end
	Combat.Fire(bot, origin, dirs, weapon.mag - 1)
	local interval = Weapons.FireInterval(weapon.id)
	if def.mode == "burst" then
		if brain.burstLeft <= 0 then brain.burstLeft = def.burstCount end
		brain.burstLeft -= 1
		brain.nextShot = now + (brain.burstLeft > 0 and def.burstDelay or interval - def.burstDelay * (def.burstCount - 1))
	elseif def.mode == "semi" then
		-- human-like trigger pulls: a little slower than the cap, less so for skilled bots
		brain.nextShot = now + interval + rng:NextNumber(0.03, 0.2) * (1.3 - bot.skill)
	else
		brain.nextShot = now + interval
	end
end

------------------------------------------------------------------------------------------------- think
local function zoneInfo()
	local zs = ReplicatedStorage:FindFirstChild("ZoneState")
	if not zs or not zs:GetAttribute("Active") then return nil end
	return {
		c = zs:GetAttribute("Center") :: Vector3, r = zs:GetAttribute("Radius") :: number,
		nc = zs:GetAttribute("NextCenter") :: Vector3?, nr = zs:GetAttribute("NextRadius") :: number?,
		phase = zs:GetAttribute("Phase"), nextT = zs:GetAttribute("NextTime") or 0,
	}
end

local function nearestOf(list: { BasePart }, pos: Vector3, maxDist: number, filter: ((BasePart) -> boolean)?): BasePart?
	local best, bestD = nil, maxDist
	for _, p in list do
		local d = (p.Position - pos).Magnitude
		if d < bestD and (not filter or filter(p)) then best, bestD = p, d end
	end
	return best
end

local function useIfHave(bot, item: string): boolean
	local inv = Inventory.Get(bot)
	if inv and (inv.items[item] or 0) > 0 and os.clock() >= bot.brain.nextUseAt then
		Inventory.Use(bot, item)
		bot.brain.nextUseAt = os.clock() + (Items.List[item].useTime or 1) + 0.3
		return true
	end
	return false
end

local function thinkLobby(bot, root: BasePart, params: RaycastParams)
	local brain = bot.brain
	local now = os.clock()
	brain.wantFire = false
	if not brain.lobbyGoal or (root.Position - brain.lobbyGoal).Magnitude < 4 then
		if not brain.lobbyGoal or now > brain.lobbyWaitUntil then
			brain.lobbyGoal = lobbyPoint()
			brain.lobbyWaitUntil = now + rng:NextNumber(2, 7)
		end
		brain.moveDir, brain.brake = Vector3.zero, true
	else
		local to = brain.lobbyGoal - root.Position
		brain.moveDir = avoid(bot, root, to, params) * 0.45
		brain.brake = root.AssemblyLinearVelocity.Magnitude > 14
		brain.face = CFrame.lookAt(Vector3.zero, to.Unit)
	end
	brain.boost = false
	-- occasional practice on the range drones (the same validated fire path as players)
	if B.LobbyPractice and now >= brain.practiceAt then
		brain.practiceAt = now + rng:NextNumber(5, 12)
		local drone = nearestOf(CollectionService:GetTagged("PracticeTarget"), root.Position, 100, function(d)
			return (d:GetAttribute("Health") or 0) > 0
		end)
		local weapon = Inventory.ActiveWeapon(bot)
		local head = bot.Character:FindFirstChild("Head") :: BasePart?
		if drone and weapon and head and Combat.ReadyIn(bot) == 0 then
			local dir = (drone.Position - head.Position).Unit
			root.CFrame = CFrame.lookAt(root.Position, drone.Position)
			brain.face = CFrame.lookAt(Vector3.zero, dir)
			local pellets = {}
			for i = 1, Weapons.Get(weapon.id).pellets do pellets[i] = dir end
			if weapon.mag <= 0 then Combat.Reload(bot) else Combat.Fire(bot, head.Position, pellets, weapon.mag - 1) end
		end
	end
end

local function thinkMatch(bot, root: BasePart, params: RaycastParams)
	local brain = bot.brain
	local now = os.clock()
	local hum = humOf(bot)
	if not hum then return end
	brain.brake = false
	brain.boost = false
	local target, visible = pickTarget(bot, root, params)
	local zone = zoneInfo()
	local pos = root.Position
	local o2 = bot:GetAttribute("O2") or 100
	local inv = Inventory.Get(bot)
	if not inv then return end

	local pressurized = bot:GetAttribute("Pressurized") == true
	-- Refill: canister if carried, else fly to the nearest O2 station (stations sit in pressurised rooms).
	local function seekOxygen(): boolean
		if pressurized or useIfHave(bot, "o2canister") then return false end
		local station = nearestOf(Oxygen.Stations(), pos, 3000)
		if not station then return false end
		brain.task = "o2"
		local d = navigate(bot, root, station.Position, params, true)
		if d < 10 then Oxygen.UseStation(bot, station) end
		brain.wantFire = visible and target ~= nil
		return true
	end
	-- 0. critical oxygen beats everything except being deep inside the storm
	local deepInStorm = zone ~= nil and (pos - zone.c).Magnitude > zone.r + 60
	if o2 < 20 and not deepInStorm and seekOxygen() then return end

	-- 1. the storm: get inside (and ahead of the next contraction)
	if zone then
		local margin = 25
		local outside = (pos - zone.c).Magnitude > zone.r - margin
		local nextOutside = zone.nc and zone.nr and zone.phase == "waiting" and zone.nextT - workspace:GetServerTimeNow() < 25
			and (pos - zone.nc).Magnitude > zone.nr - margin
		if outside or nextOutside then
			brain.task = "zone"
			local goal = (outside or not zone.nc) and zone.c or zone.nc
			navigate(bot, root, goal, params, true)
			brain.wantFire = visible and target ~= nil
			if visible and target then
				local tr = rootOf(target)
				if tr then brain.face = CFrame.lookAt(Vector3.zero, (tr.Position - pos).Unit) end
			end
			return
		end
	end
	-- 2. oxygen: plan a refill before it becomes critical (unless something is shooting at us)
	if o2 < 38 and now - brain.hurtAt > 2 and seekOxygen() then return end
	-- 3. fight, but only within effective range of our best weapon, when shot at, or up close.
	--    Far-off contacts are remembered and hunted later instead of plinking at them.
	if target and (visible or now - brain.seenAt < 2.5) then
		local tr = rootOf(target)
		local dist = tr and (tr.Position - pos).Magnitude or math.huge
		local slot = bestSlotFor(bot, dist)
		local w = slot and inv.weapons[slot]
		local engage = w and math.min(B.SightRange, Weapons.Get(w.id).maxRange * 0.75) or 0
		local early = brain.deployedAt ~= nil and now - brain.deployedAt < 45
		local hurt = now - brain.hurtAt < 3
		if hurt or dist < 90 or (dist <= engage and not (early and dist > 140)) then
			brain.task = "fight"
			fight(bot, root, target, visible, params)
			return
		end
	end
	brain.wantFire = false
	-- 4. heal / recharge when safe
	if now - brain.hurtAt > 2 then
		if hum.Health < 55 and (useIfHave(bot, hum.Health < 35 and "medkit" or "stim") or useIfHave(bot, "medkit")) then
			brain.moveDir, brain.brake = Vector3.zero, true
			return
		end
		if inv.armorMax > 0 and (bot:GetAttribute("Armor") or 0) < inv.armorMax - 20 and useIfHave(bot, "shieldcell") then
			brain.moveDir, brain.brake = Vector3.zero, true
			return
		end
		-- reload while nothing is around
		local w = inv.weapons[inv.active]
		if w and w.mag < Weapons.MagSize(w.id, w.rarity) * 0.5 and inv.ammo[Weapons.Get(w.id).ammo] > 0 and not Combat.IsReloading(bot) then
			Combat.Reload(bot)
		end
	end
	-- If hurt by something unseen, turn toward the threat and look for it
	if now - brain.hurtAt < 3 and brain.threatPos then
		brain.face = CFrame.lookAt(Vector3.zero, (brain.threatPos - pos).Unit)
	end
	-- 5. loot: grab useful pickups nearby, then search containers
	local early = brain.deployedAt and now - brain.deployedAt < 150
	if early or needsLoot(bot) then
		local pick = nearestOf(Loot.PickupsNear(pos, 140), pos, 140, function(p) return wants(bot, Loot.EntryOf(p)) end)
		if pick then
			brain.task = "pickup"
			local d = navigate(bot, root, pick.Position, params, false)
			if d < Config.Inventory.PickupRange - 2 then Loot.Take(bot, pick) end
			return
		end
		local box = brain.taskObj
		if not (box and box.Parent and not box:GetAttribute("Searched")) then
			if box and claims[box] == bot then claims[box] = nil end
			-- supply drops are worth a detour and are contested (no claim needed); otherwise the nearest unclaimed box
			local open = Loot.OpenContainers()
			box = nearestOf(open, pos, 900, function(b) return b:GetAttribute("SupplyDrop") == true end)
				or nearestOf(open, pos, 650, function(b) return claims[b] == nil or claims[b] == bot end)
			brain.taskObj = box
			if box then claims[box] = bot end
		end
		if box then
			brain.task = "loot"
			local d = navigate(bot, root, box.Position + Vector3.new(0, 3, 0), params, false)
			if d < Config.Inventory.SearchRange - 3 then
				Loot.Search(bot, box)
				claims[box] = nil
				brain.taskObj = nil
			end
			return
		end
	end
	-- 6. hunt: head for the nearest known enemy (suit radar), else the safe zone's heart
	local prey, preyD = nil, B.HuntRange
	for _, e in enemiesOf(bot) do
		local er = rootOf(e)
		if er and (er.Position - pos).Magnitude < preyD then prey, preyD = e, (er.Position - pos).Magnitude end
	end
	brain.task = "hunt"
	if prey then
		local er = rootOf(prey) :: BasePart
		navigate(bot, root, er.Position, params, preyD > 200)
	elseif zone then
		navigate(bot, root, zone.nc or zone.c, params, false)
	else
		brain.moveDir, brain.brake = Vector3.zero, true
	end
end

local function think(bot)
	local root = rootOf(bot)
	local hum = humOf(bot)
	if not (root and hum) or hum.Health <= 0 then return end
	local params = rayParams(bot)
	if unstick(bot, root) then return end
	if bot.brain.mode == "match" and Roster.IsActive(bot) then
		thinkMatch(bot, root, params)
	else
		thinkLobby(bot, root, params)
	end
end

-- Per-frame: physics for every bot body, and trigger pacing for bots in a fight.
local function step(dt: number)
	dt = math.min(dt, 0.1)
	local now = os.clock()
	for _, bot in bots do
		local root = rootOf(bot)
		local hum = humOf(bot)
		if root and hum and hum.Health > 0 then
			local brain = bot.brain
			if now >= brain.nextThink then
				brain.nextThink = now + (1 / B.ThinkRate) * rng:NextNumber(0.85, 1.15)
				local ok, err = pcall(think, bot)
				if not ok then warn("[ZG] bot " .. bot.Name .. " think error: " .. tostring(err)) end
			end
			if hum:GetState() ~= Enum.HumanoidStateType.Physics then hum:ChangeState(Enum.HumanoidStateType.Physics) end
			local thrust = brain.moveDir
			if thrust.Magnitude > 1 then thrust = thrust.Unit end
			local boostMax = MV.BoostMax * (bot:GetAttribute("BoostMaxMult") or 1)
			local regen, speedMult = bot:GetAttribute("BoostRegenMult") or 1, bot:GetAttribute("SpeedMult") or 1
			local align = root:FindFirstChild("ZG_Align") :: AlignOrientation?
			local char = bot.Character
			local up = Gravity.UpAt(root.Position)
			if up then
				-- artificial gravity: walk the floor plane, jump / jetpack when the route climbs
				local vertical = thrust:Dot(up)
				local flat = thrust - up * vertical
				if flat.Magnitude > 1 then flat = flat.Unit end
				floorParams.FilterDescendantsInstances = { char }
				local floorDist = Gravity.FloorDistance(root.Position, up, GV.FloorProbe, floorParams)
				local v = root.AssemblyLinearVelocity
				local vin = if vertical > 0.45 then 1 elseif vertical < -0.45 then -1 else 0
				local energy, jetOn, lastUse = Motion.Boost(brain.energy, Motion.WantsJet(v, up, Motion.IsGrounded(v, up, floorDist), vin),
					brain.lastBoostUse, now, boostMax, regen, dt)
				brain.energy, brain.lastBoostUse = energy, lastUse
				root.AssemblyLinearVelocity = Motion.GroundStep(v, flat, up, floorDist, vin, brain.boost, jetOn, speedMult, dt)
				-- upright, facing the aim's heading; the aim's pitch goes to the animators
				local look = brain.face.LookVector
				local fwd = look - up * look:Dot(up)
				if fwd.Magnitude < 0.05 then fwd = root.CFrame.LookVector - up * root.CFrame.LookVector:Dot(up) end
				if align and fwd.Magnitude > 1e-3 then align.CFrame = CFrame.lookAt(Vector3.zero, fwd.Unit, up) end
				local pitch = math.floor(math.deg(math.asin(math.clamp(look:Dot(up), -1, 1))) / 3 + 0.5) * 3
				if char:GetAttribute("AimPitch") ~= pitch then char:SetAttribute("AimPitch", pitch) end
			else
				local energy, boosting, lastUse = Motion.Boost(brain.energy, brain.boost and thrust.Magnitude > 0.1, brain.lastBoostUse, now, boostMax,
					regen, dt)
				brain.energy, brain.lastBoostUse = energy, lastUse
				root.AssemblyLinearVelocity = Motion.Step(root.AssemblyLinearVelocity, thrust, boosting, brain.brake, speedMult, dt)
				if align then align.CFrame = brain.face end
				if char:GetAttribute("AimPitch") then char:SetAttribute("AimPitch", nil) end
			end
			if brain.wantFire then
				local ok, err = pcall(fireStep, bot, root)
				if not ok then warn("[ZG] bot " .. bot.Name .. " fire error: " .. tostring(err)) end
			end
			-- shoulder the gun while fighting (clients animate it from the character attribute)
			local aiming = brain.wantFire or brain.task == "fight"
			if aiming ~= brain.aimingShown then
				brain.aimingShown = aiming
				Combat.Aim(bot, aiming)
			end
		end
	end
end

-- Air roll dodge under fire, like a player's Q / E: same impulse, energy cost and cooldown. Better
-- bots roll more often.
local function maybeRoll(bot)
	local brain = bot.brain
	local now = os.clock()
	if brain.mode ~= "match" or now < brain.nextRollAt or brain.energy < MV.RollCost or rng:NextNumber() > 0.2 + 0.4 * bot.skill then return end
	local root = rootOf(bot)
	if not root then return end
	local dir = if brain.strafe >= 0 then 1 else -1
	if not Combat.Roll(bot, dir) then return end
	brain.nextRollAt = now + MV.RollCooldown + rng:NextNumber(1.5, 3.5)
	brain.energy -= MV.RollCost
	brain.lastBoostUse = now
	root.AssemblyLinearVelocity += root.CFrame.RightVector * dir * MV.RollImpulse
end

-- Server messages addressed to a bot (via Remotes.BotSink): react to damage and impulses.
local function onMessage(bot, remote: string, msg)
	if type(msg) ~= "table" or remote ~= "FX" then return end
	local brain = bot.brain
	if msg.t == "damaged" then
		brain.hurtAt = os.clock()
		brain.threatPos = msg.from
		if msg.cause == "weapon" then maybeRoll(bot) end
	elseif msg.t == "impulse" then
		local root = rootOf(bot)
		if root then
			root.AssemblyLinearVelocity = msg.set and msg.v or root.AssemblyLinearVelocity + msg.v
		end
	end
end

function Bots.Start()
	cfgFolder = Instance.new("Folder")
	cfgFolder.Name = "Bots"
	cfgFolder.Parent = ReplicatedStorage
	charFolder = Instance.new("Folder")
	charFolder.Name = "BotCharacters"
	charFolder.Parent = workspace
	Remotes.BotSink = onMessage
	-- Navigation graph from the generated world (ignores the lobby; glass and hull plates block doors)
	local overlap = OverlapParams.new()
	overlap.RespectCanCollide = true
	local lobby = workspace:FindFirstChild("Lobby")
	local losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Exclude
	losParams.FilterDescendantsInstances = { charFolder, lobby or charFolder }
	local stats = Nav.Build(Kit.NavSpaces, function(pos)
		for _, p in workspace:GetPartBoundsInRadius(pos, 0.75, overlap) do
			-- airlock doors open on demand and characters move; anything else solid closes the opening
			if p.Name ~= "InnerDoor" and p.Name ~= "OuterDoor" and not Roster.FromCharacter(p:FindFirstAncestorOfClass("Model")) then
				return true
			end
		end
		return false
	end, function(space)
		return lobby ~= nil and space.model ~= nil and space.model:IsDescendantOf(lobby)
	end, function(a, b)
		return workspace:Raycast(a, b - a, losParams) == nil
	end)
	print(string.format("[ZG] bot nav graph: %d nodes, %d edges, %d exits, %d spaces", stats.nodes, stats.edges, stats.exits, stats.spaces))
	Players.PlayerAdded:Connect(function() task.defer(Bots.Rebalance) end)
	Players.PlayerRemoving:Connect(function() task.defer(Bots.Rebalance) end)
	RunService.Heartbeat:Connect(step)
	task.defer(Bots.Rebalance)
end

return Bots
