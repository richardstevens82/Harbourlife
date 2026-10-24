-- Server-authoritative combat. Clients send aim rays; the server checks fire rate, ammunition,
-- reload state, origin position and aim plausibility, then performs its own raycasts and applies
-- damage. All damage in the game (weapons, explosions, zone, oxygen, hazards) goes through
-- Combat.ApplyDamage so shields, spawn protection and kill attribution behave consistently.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.WeaponDefinitions)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Security = require(script.Parent.SecurityService)
local Inventory = require(script.Parent.InventoryService)

local Combat = {}
local state: { [Player]: any } = {} -- per-player fire/reload timing
Combat.OnTargetDamaged = nil :: ((BasePart, number, Player?) -> ())? -- set by HazardService (barrels, breach plates)

local function st(player: Player)
	local s = state[player]
	if not s then
		s = { lastShot = 0, burstStart = 0, burstShots = 0, reloadUntil = 0, reloadSerial = 0, equipAt = 0, lastMelee = 0 }
		state[player] = s
	end
	return s
end

local function charOf(part: Instance): (Model?, Humanoid?)
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		local h = m:FindFirstChildOfClass("Humanoid")
		if h then return m, h end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- Practice range: not an active combatant and physically inside the lobby hall.
local function inLobby(player: Player): boolean
	if Roster.IsActive(player) then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - Config.Arena.LobbyCenter).Magnitude < 120
end

-- Central damage entry point. attacker nil = environment. Returns damage actually dealt.
function Combat.ApplyDamage(victim: Player, amount: number, attacker: Player?, cause: string, fromPos: Vector3?): number
	if amount <= 0 or not Roster.IsActive(victim) then return 0 end
	local r = Roster.Get(victim)
	local now = os.clock()
	if now < r.protectUntil then return 0 end
	if attacker then
		if attacker == victim and cause ~= "explosion" then return 0 end
		local ar = Roster.Get(attacker)
		if attacker ~= victim and (not ar or not ar.inMatch) then return 0 end
		if ar and attacker ~= victim and ar.team ~= 0 and ar.team == r.team then return 0 end -- squads
	end
	local hum = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return 0 end
	local armor = (victim:GetAttribute("Armor") :: number?) or 0
	local absorbed = 0
	if cause ~= "zone" and cause ~= "hypoxia" and armor > 0 then -- shields don't stop radiation or suffocation
		absorbed = math.min(armor, amount)
		victim:SetAttribute("Armor", armor - absorbed)
	end
	local toHealth = math.min(amount - absorbed, hum.Health)
	local dealt = absorbed + toHealth
	-- Record attribution BEFORE changing health: Humanoid.Died may fire immediately and MatchService
	-- reads lastAttacker/lastCause when it does.
	r.lastHurt = now
	r.lastCause = cause
	if attacker and attacker ~= victim then
		r.lastAttacker, r.lastAttackerAt = attacker, now
		local ar = Roster.Get(attacker)
		if ar then ar.damage += dealt end
	end
	hum.Health -= toHealth
	Remotes.FX:FireClient(victim, { t = "damaged", from = fromPos, amount = dealt, shield = absorbed > 0, cause = cause })
	return dealt
end

-- Area damage with line-of-sight and linear falloff. Used by grenades, barrels and the Helios.
function Combat.Explode(pos: Vector3, radius: number, damage: number, attacker: Player?, ignore: Player?)
	Remotes.FX:FireAllClients({ t = "explosion", pos = pos, radius = radius })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, p in Roster.Active() do
		if p ~= ignore then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - pos).Magnitude
				if d <= radius then
					params.FilterDescendantsInstances = { p.Character :: Model }
					local hit = workspace:Raycast(pos, root.Position - pos, params)
					if not hit or (hit.Position - root.Position).Magnitude < 3 then
						local dealt = Combat.ApplyDamage(p, damage * (1 - 0.6 * d / radius), attacker, "explosion", pos)
						if attacker and attacker ~= p and dealt > 0 then
							Remotes.FX:FireClient(attacker, { t = "hit", amount = dealt, kill = not Roster.IsActive(p) })
						end
						-- shove (characters are client-owned physics, so the owner applies the impulse)
						Remotes.FX:FireClient(p, { t = "impulse", v = (root.Position - pos).Unit * 25 * (1 - d / radius) })
						Security.AllowBurst(p, 1)
					end
				end
			end
		end
	end
	-- Chain into damageable props (barrels, breach plates)
	for _, tag in { "ExplosiveBarrelProp", "Breachable" } do
		for _, part in CollectionService:GetTagged(tag) do
			if part:IsA("BasePart") and part.Parent and (part.Position - pos).Magnitude <= radius and Combat.OnTargetDamaged then
				Combat.OnTargetDamaged(part, damage, attacker)
			end
		end
	end
end

local function practiceHit(target: BasePart, dmg: number)
	local hp = ((target:GetAttribute("Health") :: number?) or 100) - dmg
	if hp <= 0 then
		target:SetAttribute("Health", 0)
		target.Transparency = 0.8
		task.delay(3, function()
			target:SetAttribute("Health", target:GetAttribute("MaxHealth") or 100)
			target.Transparency = 0
		end)
	else
		target:SetAttribute("Health", hp)
	end
end

local function angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local function onFire(player: Player, req)
	if not Security.RateLimit(player, "fire", 30, 12) then return end
	local origin, dirs = req.origin, req.dirs
	if not Security.IsVector(origin) or type(dirs) ~= "table" or #dirs == 0 or #dirs > 12 then return end
	local practice = inLobby(player)
	if not practice and not Roster.IsActive(player) then return end
	local weapon = Inventory.ActiveWeapon(player)
	if not weapon then return end
	local def = Weapons.Get(weapon.id)
	local s = st(player)
	local now = os.clock()
	if now < s.reloadUntil or now < s.equipAt then return end
	if weapon.mag <= 0 then return end
	-- Fire-rate check (with small network tolerance)
	local interval = Weapons.FireInterval(weapon.id)
	if def.mode == "burst" then
		if s.burstShots < def.burstCount and now - s.burstStart < def.burstCount * def.burstDelay + 0.25 then
			if now - s.lastShot < def.burstDelay * 0.7 then return end
			s.burstShots += 1
		else
			if now - s.burstStart < interval * 0.85 then return end
			s.burstStart, s.burstShots = now, 1
		end
	elseif now - s.lastShot < interval * 0.85 then
		return
	end
	if #dirs ~= def.pellets then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	-- Origin must be near the shooter (allow for movement during latency)
	local slack = 8 + root.AssemblyLinearVelocity.Magnitude * 0.35
	if (origin - root.Position).Magnitude > slack then
		Security.Flag(player, "fire origin too far")
		return
	end
	local mean = Vector3.zero
	for _, d in dirs do
		if not Security.IsVector(d) or d.Magnitude < 0.5 then return end
		mean += d.Unit
	end
	if mean.Magnitude < 0.1 then return end
	-- Aim must be roughly where the body faces, and pellets inside the weapon's spread cone
	if angleBetween(mean, root.CFrame.LookVector) > 80 then return end
	for _, d in dirs do
		if angleBetween(d, mean) > def.spread * 2 + 4 then return end
	end
	s.lastShot = now
	weapon.mag -= 1

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char :: Model }
	local ends = {}
	local hitAny, killAny, total = false, false, 0
	local victimsHit: { [Player]: boolean } = {}
	for _, d in dirs do
		local result = workspace:Raycast(origin, d.Unit * def.maxRange, params)
		local endPos = result and result.Position or origin + d.Unit * def.maxRange
		table.insert(ends, endPos)
		if result then
			local dist = (result.Position - origin).Magnitude
			local dmg = Weapons.DamageAt(weapon.id, weapon.rarity, dist)
			local model, hum = charOf(result.Instance)
			local victim = Roster.FromCharacter(model) -- player or bot
			if victim and hum and dmg > 0 then
				if result.Instance.Name == "Head" then dmg *= 1.5 end
				if not practice then
					local dealt = Combat.ApplyDamage(victim, dmg, player, "weapon", origin)
					if dealt > 0 then
						hitAny, total = true, total + dealt
						victimsHit[victim] = true
						if not Roster.IsActive(victim) then killAny = true end
					end
				end
			elseif CollectionService:HasTag(result.Instance, "PracticeTarget") and dmg > 0 then
				practiceHit(result.Instance :: BasePart, dmg)
				hitAny, total = true, total + dmg
			elseif Combat.OnTargetDamaged and dmg > 0 then
				Combat.OnTargetDamaged(result.Instance :: BasePart, dmg, player)
			end
			if def.splash and not practice then
				Combat.Explode(result.Position, def.splash, def.splashDamage, player, nil)
			end
		end
	end
	if hitAny then
		Remotes.FX:FireClient(player, { t = "hit", amount = math.floor(total + 0.5), kill = killAny })
	end
	-- Tracers for everyone else (the shooter already drew its own locally)
	for _, p in Players:GetPlayers() do
		if p ~= player then
			Remotes.FX:FireClient(p, { t = "tracer", from = origin, ends = ends, weapon = weapon.id, shooter = player })
		end
	end
	if weapon.mag ~= req.expectMag then
		Inventory.Sync(player) -- client prediction drifted; resync
	end
end

local function onReload(player: Player)
	local weapon, inv = Inventory.ActiveWeapon(player)
	if not weapon then return end
	if not (Roster.IsActive(player) or inLobby(player)) then return end
	local s = st(player)
	local now = os.clock()
	if now < s.reloadUntil then return end
	local def = Weapons.Get(weapon.id)
	local magSize = Weapons.MagSize(weapon.id, weapon.rarity)
	if weapon.mag >= magSize then return end
	if not inv.practice and inv.ammo[def.ammo] <= 0 then return end
	s.reloadUntil = now + def.reload
	s.reloadSerial += 1
	local serial, slot = s.reloadSerial, inv.active
	Remotes.FX:FireClient(player, { t = "reload", time = def.reload })
	task.delay(def.reload, function()
		if s.reloadSerial ~= serial or Inventory.Get(player) ~= inv or inv.active ~= slot or inv.weapons[slot] ~= weapon then return end
		local need = magSize - weapon.mag
		local take = inv.practice and need or math.min(need, inv.ammo[def.ammo])
		weapon.mag += take
		if not inv.practice then inv.ammo[def.ammo] -= take end
		Inventory.Sync(player)
	end)
end

local function onEquip(player: Player, slot)
	if type(slot) ~= "number" or slot % 1 ~= 0 then return end
	if Inventory.SetActive(player, slot) then
		local s = st(player)
		s.reloadSerial += 1 -- cancels a reload in progress
		s.reloadUntil = 0
		s.equipAt = os.clock() + 0.3
	end
end

local function onMelee(player: Player)
	if not Roster.IsActive(player) then return end
	local s = st(player)
	local now = os.clock()
	if now - s.lastMelee < Config.Melee.Cooldown then return end
	s.lastMelee = now
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local best, bestD = nil, Config.Melee.Range
	for _, p in Roster.Active() do
		if p ~= player then
			local r2 = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r2 then
				local off = r2.Position - root.Position
				if off.Magnitude < bestD and angleBetween(off, root.CFrame.LookVector) < 55 then
					best, bestD = p, off.Magnitude
				end
			end
		end
	end
	Remotes.FX:FireAllClients({ t = "melee", pos = root.Position + root.CFrame.LookVector * 3 })
	if best then
		local dealt = Combat.ApplyDamage(best, Config.Melee.Damage, player, "melee", root.Position)
		if dealt > 0 then
			Remotes.FX:FireClient(player, { t = "hit", amount = dealt, kill = not Roster.IsActive(best) })
			Remotes.FX:FireClient(best, { t = "impulse", v = root.CFrame.LookVector * 30 }) -- knockback: momentum matters
			Security.AllowBurst(best, 1)
		end
	end
end

-- Direct entry points for bots: the same validation path the RemoteEvent handlers use.
function Combat.Fire(c, origin: Vector3, dirs: { Vector3 }, expectMag: number?)
	onFire(c, { origin = origin, dirs = dirs, expectMag = expectMag })
end
Combat.Reload = function(c) onReload(c) end
Combat.Equip = function(c, slot: number) onEquip(c, slot) end
Combat.Melee = function(c) onMelee(c) end

-- Seconds until this combatant may fire again (reload / equip / fire interval), for bot pacing.
function Combat.ReadyIn(c): number
	local s = st(c)
	local now = os.clock()
	return math.max(0, s.reloadUntil - now, s.equipAt - now)
end

function Combat.IsReloading(c): boolean
	return os.clock() < st(c).reloadUntil
end

function Combat.ResetPlayer(player: Player)
	state[player] = nil
end

function Combat.Start()
	Remotes.Combat.OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" then return end
		if req.action == "fire" then
			onFire(player, req)
		elseif not Security.RateLimit(player, "combat", 10, 6) then
			return
		elseif req.action == "reload" then
			onReload(player)
		elseif req.action == "equip" then
			onEquip(player, req.slot)
		elseif req.action == "melee" then
			onMelee(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p) state[p] = nil end)
	-- Health regeneration (capped; medical items needed to go higher)
	local H = Config.Health
	task.spawn(function()
		while H.RegenEnabled do
			task.wait(0.5)
			local now = os.clock()
			for _, p in Roster.Active() do
				local r = Roster.Get(p)
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if hum and now - r.lastHurt > H.RegenDelay and hum.Health < H.RegenCap then
					hum.Health = math.min(H.RegenCap, hum.Health + H.RegenPerSecond * 0.5)
				end
			end
		end
	end)
end

return Combat
