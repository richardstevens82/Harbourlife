-- Procedural zero-gravity character animation, run on every client for every character it can see
-- (players and bots). Roblox's default walk/jump/fall animations make no sense without gravity, so
-- the default Animate script is replaced (StarterCharacterScripts/Animate) and each R15 joint is
-- posed here from what every client already knows:
--   * the body's velocity and orientation (replicated physics; the root follows its owner's aim)
--   * the held weapon (HeldWeapon model, mounted on the root by CharacterService.SetWeaponVisual)
--   * character attributes set by the server: Aiming, RollAt / RollDir (air rolls)
--   * shots: tracer messages name the shooter's character (OnShot); the local player calls Fired()
--
-- Layers, written to Motor6D.Transform every PreSimulation (after Roblox's animation step, so these
-- values are what renders):
--   body  - bank into strafes, barrel rolls, idle sway and bob (Root joint; the gun moves with it)
--   legs  - trail behind forward thrust, swing forward when reversing, tuck when descending, dangle
--           when climbing, streamline while boosting, slow flutter while drifting
--   torso - bladed shooting stance while armed (Waist), head turned back to look down the sights
--   gun   - low ready, shouldered when aiming or firing, recoil kick per shot (WeaponMount)
--   arms  - two-bone IK puts the right hand on the weapon's Grip and the left hand on its Support;
--           unarmed arms float loosely
--   moves - reload (gun canted, support hand pulls and seats the magazine), weapon swap (the new gun
--           swings up from low), melee (a forward jab with the gun, or a straight punch when unarmed); driven by
--           the ReloadEnd / ReloadTime / MeleeAt attributes and by the HeldWeapon model changing
--   death - limp spread-eagle tumble (a slumped kneel under gravity)
--   gravity - on level decks (Shared.Gravity) the body stays upright: a walk cycle timed to ground
--           speed, a relaxed stance standing still, knees drawn up in the air, swinging arms when
--           unarmed, a side-dodge lean instead of the barrel roll, and the gun, head and chest
--           tilting to the aim's pitch (the AimPitch attribute for other characters)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Gravity = require(Shared.Gravity)
local State = require(script.Parent.ClientState)

local Anim = {}
local player = Players.LocalPlayer
local MV = Config.Movement
local GV = Config.Gravity
local STRIDE = 7 -- studs per full walk cycle (two steps)
local AIM_PIVOT = Vector3.new(0.3, 0.75, 0) -- the gun pitches about the chest (root space)
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
local rigs: { [Model]: any } = {}
local lastScan = -math.huge

local BLADE = math.rad(35) -- armed stance: upper body turned so the left shoulder leads
-- Low-ready gun pose relative to the shouldered (aim) grip: lower, a little back, barrel tipped down
local READY = CFrame.new(-0.05, -0.38, 0.12) * CFrame.Angles(math.rad(-30), math.rad(8), 0)
local SHOT_HOLD = 1.2 -- seconds a shot keeps the gun shouldered
local POLE = { Right = Vector3.new(0.8, -1, 0.5), Left = Vector3.new(-0.7, -1, 0.1) } -- elbow hints (upper-torso space)
local FAR, MID = 420, 160 -- studs from the camera: no updates beyond FAR, 30 Hz beyond MID
local SIDES = { Right = 1, Left = -1 }
local SWAP_TIME, MELEE_TIME = 0.4, 0.35
local XAXIS = Vector3.xAxis

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A character joint. Classic rigs use Motor6Ds; Roblox's avatar joint upgrade uses
-- AnimationConstraints instead (C0/C1 come from its attachments). Both are posed through Transform.
-- (CharacterService converts upgraded joints back to Motor6Ds on spawn; this handles either.)
local Joint = {}
Joint.__index = function(self, k)
	local inst = rawget(self, "inst")
	if k == "C0" then
		return if self.anim then inst.Attachment0.CFrame else inst.C0
	elseif k == "C1" then
		return if self.anim then inst.Attachment1.CFrame else inst.C1
	elseif k == "Parent" then
		return inst.Parent
	end
	return nil
end
Joint.__newindex = function(self, k, v)
	if k == "Transform" then
		(rawget(self, "inst") :: any).Transform = v
	else
		rawset(self, k, v)
	end
end

-- Every posable joint in a character, keyed by the name of the body part it moves (its Part1), so
-- joint names and where Roblox parents them don't matter.
local function jointsOf(char: Model): ({ [string]: any }, number, number)
	local byPart, motors, constraints = {}, 0, 0
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") then
			motors += 1
			if d.Part1 and d.Part0 and d.Name ~= "WeaponMount" then byPart[d.Part1.Name] = setmetatable({ inst = d, anim = false }, Joint) end
		elseif d:IsA("AnimationConstraint") then
			constraints += 1
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a1.Parent and a1.Parent:IsA("BasePart") then byPart[a1.Parent.Name] = setmetatable({ inst = d, anim = true }, Joint) end
		end
	end
	return byPart, motors, constraints
end

-- Rotation taking local direction a onto ta, and the component of b perpendicular to a onto the
-- component of tb perpendicular to ta.
local function basis(a: Vector3, b: Vector3, ta: Vector3, tb: Vector3): CFrame
	local u1, v1 = a.Unit, ta.Unit
	local u2, v2 = b - u1 * b:Dot(u1), tb - v1 * tb:Dot(v1)
	if u2.Magnitude < 1e-5 then u2 = u1:Cross(Vector3.zAxis) end
	if v2.Magnitude < 1e-5 then v2 = v1:Cross(Vector3.zAxis) end
	u2, v2 = u2.Unit, v2.Unit
	return CFrame.fromMatrix(Vector3.zero, v1, v2, v1:Cross(v2)) * CFrame.fromMatrix(Vector3.zero, u1, u2, u1:Cross(u2)):Inverse()
end

local warned: { [string]: boolean } = {}

local function newRig(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return nil end
	local J, motors, constraints = jointsOf(char)
	local r = {
		char = char, root = root, hum = hum,
		rootJ = J.LowerTorso, waist = J.UpperTorso, neck = J.Head,
		legs = {}, arms = {},
		phase = math.random() * 20, acc = 0,
		s = { fwd = 0, side = 0, up = 0, boost = 0, aim = 0, armed = 0, dead = 0, grav = 0, ground = 0, walk = 0 },
		stride = 0,
		kick = 0, lastShot = -math.huge, rollStart = -math.huge, rollDir = 1, localRollUntil = -math.huge,
		rollAt = char:GetAttribute("RollAt"), diedAt = nil :: number?,
		held = nil :: Instance?, equipStart = -math.huge, meleeAt = char:GetAttribute("MeleeAt"), meleeStart = -math.huge, magLocal = nil :: Vector3?,
	}
	for side in SIDES do
		r.legs[side] = { hip = J[side .. "UpperLeg"], knee = J[side .. "LowerLeg"], ankle = J[side .. "Foot"] }
		local hand = char:FindFirstChild(side .. "Hand") :: BasePart?
		local grip = hand and hand:FindFirstChild(side .. "GripAttachment") :: Attachment?
		r.arms[side] = {
			shoulder = J[side .. "UpperArm"], elbow = J[side .. "LowerArm"], wrist = J[side .. "Hand"],
			gripPos = if grip then grip.Position elseif hand then Vector3.new(0, -hand.Size.Y * 0.5, 0) else Vector3.zero,
		}
	end
	r.r15 = r.rootJ ~= nil and r.waist ~= nil
	if not r.r15 and char:FindFirstChild("LowerTorso") and not warned[char.Name] then
		warned[char.Name] = true
		warn(string.format("[ZG] animator: %s has no usable R15 joints (%d Motor6D, %d AnimationConstraint) - it will not be animated",
			char.Name, motors, constraints))
	end
	return r
end

-- Two-bone IK: turns shoulder and elbow so the hand's grip point lands on target (upper-torso
-- space), bending the elbow toward pole. The wrist stays straight.
local function solveArm(arm, target: Vector3, pole: Vector3)
	local sh, el, wr = arm.shoulder, arm.elbow, arm.wrist
	if not (sh and el and wr) then return end
	if not arm.eu then
		arm.eu = el.C0.Position - sh.C1.Position -- shoulder pivot -> elbow pivot, upper-arm space
		arm.el = (wr.C0 * wr.C1:Inverse() * arm.gripPos) - el.C1.Position -- elbow pivot -> grip point, lower-arm space
	end
	local eu, ev = arm.eu, arm.el
	local L1, L2 = eu.Magnitude, ev.Magnitude
	local S = sh.C0.Position
	local d = target - S
	local n = if d.Magnitude > 1e-4 then d.Unit else Vector3.new(0, 0, -1)
	local D = math.clamp(d.Magnitude, math.abs(L1 - L2) + 1e-3, (L1 + L2) * 0.999)
	local a = (L1 * L1 - L2 * L2 + D * D) / (2 * D)
	local h = math.sqrt(math.max(0, L1 * L1 - a * a))
	local m = pole - n * pole:Dot(n)
	if m.Magnitude < 1e-4 then m = n:Cross(XAXIS) end
	m = m.Unit
	local E = S + n * a + m * h
	local P = S + n * D
	local up, low = (E - S).Unit, (P - E).Unit
	local hinge = up:Cross(low)
	if hinge.Magnitude < 1e-4 then hinge = n:Cross(m) end
	local rArm = basis(eu, XAXIS, up, hinge)
	local rLow = basis(ev, XAXIS, low, hinge)
	sh.Transform = sh.C0.Rotation:Inverse() * rArm * sh.C1.Rotation
	el.Transform = el.C0.Rotation:Inverse() * rArm:Inverse() * rLow * el.C1.Rotation
	wr.Transform = CFrame.identity
end

local function floatArms(r, t: number, life: number, punch: number?)
	local s = r.s
	for side, sign in SIDES do
		local a = r.arms[side]
		if a.shoulder and a.elbow then
			local bob = math.sin(t * 1.3 + (sign > 0 and 0 or 1.7)) * 0.12 * life
			local flex = lerp(0.25 + bob - 0.7 * s.boost, 0.2, s.dead)
			local out = sign * lerp(0.35 - 0.23 * s.boost, 1.1, s.dead)
			local bend = lerp(0.55 + 0.12 * math.sin(t * 1.1 + sign) - 0.35 * s.boost, 0.35, s.dead)
			if s.grav > 0.01 then -- under gravity: arms swing with the stride, or spread for balance in the air
				local ph = r.stride * math.pi * 2 + (if sign > 0 then math.pi else 0)
				local flexG = lerp(0.3, 0.05 + 0.55 * s.walk * math.sin(ph), s.ground)
				local outG = sign * lerp(0.6, 0.1, s.ground)
				local bendG = lerp(0.4, 0.25 + 0.25 * s.walk, s.ground)
				local k = s.grav * (1 - s.dead)
				flex, out, bend = lerp(flex, flexG, k), lerp(out, outG, k), lerp(bend, bendG, k)
			end
			if punch and sign > 0 then -- unarmed melee: a straight right jab
				flex, out, bend = lerp(flex, 1.55, punch), lerp(out, 0.05, punch), lerp(bend, 0.05, punch)
			end
			a.shoulder.Transform = CFrame.fromEulerAnglesYXZ(flex, 0, out)
			a.elbow.Transform = CFrame.Angles(math.max(bend, 0.05), 0, 0)
			if a.wrist then a.wrist.Transform = CFrame.Angles(0.15, 0, 0) end
		end
	end
end

local function poseLegs(r, t: number, life: number, speed: number)
	local s = r.s
	local fwdOn, backOn = math.max(s.fwd, 0), math.max(-s.fwd, 0)
	local upOn, downOn = math.max(s.up, 0), math.max(-s.up, 0)
	for side, sign in SIDES do
		local L = r.legs[side]
		if L.hip and L.knee then
			local flutter = math.sin(t * (1.5 + 2.5 * math.min(speed, 1)) + (sign > 0 and 0 or math.pi)) * (0.16 - 0.1 * s.boost) * life
			local hip = 0.3 - 0.85 * fwdOn + 0.6 * backOn - 0.25 * upOn + 1.0 * downOn - 0.55 * s.boost + flutter
			local knee = 0.5 - 0.3 * fwdOn + 0.45 * backOn - 0.3 * upOn + 1.3 * downOn - 0.35 * s.boost + flutter * 0.7
			local spread = sign * 0.07 - 0.35 * math.clamp(s.side, -1, 1)
			hip = lerp(math.clamp(hip, -1.1, 1.7), 0.45, s.dead)
			knee = lerp(math.clamp(knee, 0.05, 2.0), 0.7, s.dead)
			spread = lerp(spread, sign * 0.45, s.dead)
			local ankle = -0.3 - 0.35 * s.boost - 0.2 * fwdOn -- toes pointed
			if s.grav > 0.01 then
				-- under gravity: stride on the floor (nearly straight legs standing still), knees up in the
				-- air, a slumped kneel when dead
				local ph = r.stride * math.pi * 2 + (if sign > 0 then 0 else math.pi)
				local hipG = lerp(0.35, 0.04 + 0.6 * s.walk * math.sin(ph), s.ground)
				local kneeG = lerp(0.65, 0.1 + 0.95 * s.walk * math.max(0, math.cos(ph)), s.ground)
				local ankleG = lerp(-0.25, 0.05 - 0.3 * s.walk * math.max(0, -math.sin(ph)), s.ground)
				hipG, kneeG = lerp(hipG, 1.0, s.dead), lerp(kneeG, 1.6, s.dead)
				hip, knee = lerp(hip, hipG, s.grav), lerp(knee, kneeG, s.grav)
				spread, ankle = lerp(spread, sign * 0.04, s.grav * (1 - s.dead)), lerp(ankle, ankleG, s.grav)
			end
			L.hip.Transform = CFrame.fromEulerAnglesYXZ(hip, 0, spread)
			L.knee.Transform = CFrame.Angles(-knee, 0, 0) -- knees bend backward
			if L.ankle then L.ankle.Transform = CFrame.Angles(ankle, 0, 0) end
		end
	end
end

local function update(r, dt: number, now: number)
	local char, root, hum = r.char, r.root, r.hum
	local s = r.s
	local alive = hum.Health > 0
	if alive then
		r.diedAt = nil
	elseif not r.diedAt then
		r.diedAt = now
	end
	local vel = root.AssemblyLinearVelocity
	local lv = root.CFrame:VectorToObjectSpace(vel) / MV.MaxSpeed
	local f6 = 1 - math.exp(-dt * 6)
	s.fwd += (math.clamp(-lv.Z, -1.5, 1.5) - s.fwd) * f6
	s.side += (math.clamp(lv.X, -1.5, 1.5) - s.side) * f6
	s.up += (math.clamp(lv.Y, -1.5, 1.5) - s.up) * f6
	s.boost += ((if vel.Magnitude > MV.MaxSpeed * 1.08 then 1 else 0) - s.boost) * (1 - math.exp(-dt * 5))
	-- artificial gravity: upright, walking / standing / airborne
	local gup = Gravity.UpAt(root.Position)
	local onFloor, flatSpeed = false, 0
	if gup then
		floorParams.FilterDescendantsInstances = { char }
		local fd = Gravity.FloorDistance(root.Position, gup, GV.FloorProbe, floorParams)
		onFloor = fd ~= nil and fd <= GV.HipHeight + 0.6
		flatSpeed = (vel - gup * vel:Dot(gup)).Magnitude
	end
	local f8 = 1 - math.exp(-dt * 8)
	s.grav += ((if gup then 1 else 0) - s.grav) * f8
	s.ground += ((if onFloor then 1 else 0) - s.ground) * (1 - math.exp(-dt * 12))
	s.walk += ((if onFloor then math.clamp(flatSpeed / GV.WalkSpeed, 0, 1.4) else 0) - s.walk) * f8
	r.stride = (r.stride + flatSpeed * dt / STRIDE) % 1
	s.dead += ((if alive then 0 else 1) - s.dead) * (1 - math.exp(-dt * 3))

	-- weapon state
	local held = char:FindFirstChild("HeldWeapon") :: Model?
	local handle = held and held.PrimaryPart
	local mount = handle and handle:FindFirstChild("WeaponMount") :: Motor6D?
	local gripA = handle and handle:FindFirstChild("Grip") :: Attachment?
	local supA = handle and handle:FindFirstChild("Support") :: Attachment?
	local armed = alive and mount ~= nil and gripA ~= nil
	s.armed += ((if armed then 1 else 0) - s.armed) * (1 - math.exp(-dt * 8))
	local isLocal = char == player.Character
	local aiming = armed and ((if isLocal then State.Aiming == true else char:GetAttribute("Aiming") == true) or now - r.lastShot < SHOT_HOLD)
	s.aim += ((if aiming then 1 else 0) - s.aim) * (1 - math.exp(-dt * 12))
	r.kick *= math.exp(-dt * 14)

	-- weapon swaps (a new HeldWeapon model) and melee strikes
	if held ~= r.held then
		r.held, r.magLocal = held, nil
		if held then r.equipStart = now end
	end
	local meleeAt = char:GetAttribute("MeleeAt")
	if meleeAt ~= r.meleeAt then
		r.meleeAt = meleeAt
		if meleeAt then r.meleeStart = now end
	end
	local mp = (now - r.meleeStart) / MELEE_TIME
	local melee = if mp >= 0 and mp < 1 then math.sin(mp * math.pi) else 0
	local reloadEnd = (char:GetAttribute("ReloadEnd") :: number?) or 0
	local reloadTime = math.max((char:GetAttribute("ReloadTime") :: number?) or 1, 0.1)
	local sn = workspace:GetServerTimeNow()
	local reload = if armed and reloadEnd > sn then math.clamp(1 - (reloadEnd - sn) / reloadTime, 0, 1) else -1

	-- air rolls announced by the server (the local player's own roll already started in Roll())
	local rollAt = char:GetAttribute("RollAt")
	if rollAt ~= r.rollAt then
		r.rollAt = rollAt
		if rollAt and now > r.localRollUntil then Anim.StartRoll(char, char:GetAttribute("RollDir") or 1) end
	end

	-- body: bank, roll, sway (rotation about the root's centre, applied to the torso and the gun)
	local t = now + r.phase
	local life = 1 - s.dead
	local roll, lean = 0, 0
	local rp = (now - r.rollStart) / MV.RollTime
	if rp >= 0 and rp < 1 then
		roll = -r.rollDir * (rp * rp * (3 - 2 * rp)) * math.pi * 2 -- zero-g barrel roll
		lean = -r.rollDir * 0.55 * math.sin(rp * math.pi) -- under gravity: a dodging side lean
	end
	local bank = -0.45 * math.clamp(s.side, -1, 1)
	local angle = lerp((roll + bank + 0.05 * math.sin(t * 0.9)) * life, lean * life, s.grav)
	local bob = lerp(0.07 * math.sin(t * 1.3) * life, 0.07 * math.abs(math.sin(r.stride * math.pi * 2)) * s.walk * life, s.grav)
	local B = CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, angle)
	if r.diedAt then
		local k = (now - r.diedAt) * s.dead * (1 - s.grav)
		B *= CFrame.Angles(k * 0.5, k * 0.2, k * 0.3) -- slow tumble (zero-g)
	end
	-- the aim's pitch while upright under gravity (in zero-g the whole body pitches with the aim)
	local pitch = 0
	if gup and s.grav > 0.01 then
		local deg = (char:GetAttribute("AimPitch") :: number?) or 0
		if isLocal then
			local cam = workspace.CurrentCamera
			if cam then deg = math.deg(math.asin(math.clamp(cam.CFrame.LookVector:Dot(gup), -1, 1))) end
		end
		pitch = math.rad(math.clamp(deg, -85, 85)) * s.grav * (1 - s.dead)
	end
	if melee > 0 then B *= CFrame.new(0, 0, -0.35 * melee) end -- lunge into the strike

	local waistT = CFrame.fromEulerAnglesYXZ(-0.3 * s.boost * (1 - s.armed) * (1 - s.grav) + 0.25 * s.dead + 0.3 * pitch + 0.35 * s.dead * s.grav,
		-BLADE * s.armed, 0)
	if r.r15 then
		r.rootJ.Transform = r.rootJ.C0:Inverse() * B * r.rootJ.C0
		r.waist.Transform = waistT
		if r.neck then
			r.neck.Transform = CFrame.fromEulerAnglesYXZ(-0.16 * s.aim + 0.04 * math.sin(t * 0.7) * life - 0.4 * s.dead + 0.5 * pitch, BLADE * s.armed,
				-0.15 * s.aim)
		end
		poseLegs(r, t, life, vel.Magnitude / MV.MaxSpeed)
	end

	-- gun and hands
	if armed and mount and gripA then
		local aimCF = mount.C0
		local kick = r.kick
		local pose = (aimCF * READY):Lerp(aimCF, s.aim) * CFrame.new(0, 0.03 * kick, 0.22 * kick) * CFrame.Angles(0.15 * kick, 0, 0)
		if pitch ~= 0 then pose = CFrame.new(AIM_PIVOT) * CFrame.Angles(pitch, 0, 0) * CFrame.new(-AIM_PIVOT) * pose end
		local e = (now - r.equipStart) / SWAP_TIME
		if e >= 0 and e < 1 then -- new weapon swings up from pointing down
			local low = 1 - e * e * (3 - 2 * e)
			pose *= CFrame.new(0, -0.45 * low, 0.15 * low) * CFrame.Angles(-1.1 * low, 0, 0.35 * low)
		end
		local w = 0
		if reload >= 0 then -- canted and lowered while the magazine is swapped
			w = math.clamp(math.min(reload, 1 - reload) / 0.12, 0, 1)
			pose *= CFrame.new(-0.05 * w, -0.18 * w, 0.12 * w) * CFrame.Angles(0.3 * w, 0.15 * w, 0.65 * w)
		end
		if melee > 0 then -- the gun comes up level and jabs forward
			pose = pose:Lerp(aimCF, melee) * CFrame.new(0, 0.1 * melee, -0.8 * melee) * CFrame.Angles(0.15 * melee, 0, 0)
		end
		local final = B * pose
		mount.Transform = aimCF:Inverse() * final
		if r.r15 then
			local handleCF = final * mount.C1:Inverse()
			local UT = B * r.rootJ.C0 * r.rootJ.C1:Inverse() * r.waist.C0 * waistT * r.waist.C1:Inverse()
			solveArm(r.arms.Right, UT:PointToObjectSpace(handleCF * gripA.Position), POLE.Right)
			if supA then
				local support = supA.Position
				if reload >= 0 then
					-- support hand: to the magazine, pull it out and away, seat a fresh one, back to the grip
					if not r.magLocal then
						local mag = held and held:FindFirstChild("Magazine") :: BasePart?
						r.magLocal = if mag and handle
							then handle.CFrame:PointToObjectSpace(mag.Position - mag.CFrame.UpVector * mag.Size.Y * 0.45)
							else support + Vector3.new(0, -0.2, 0.25)
					end
					local mag = r.magLocal :: Vector3
					local out = mag + Vector3.new(-0.15, -0.75, 0.2)
					local p = reload
					support = if p < 0.3 then support:Lerp(mag, p / 0.3)
						elseif p < 0.55 then mag:Lerp(out, (p - 0.3) / 0.25)
						elseif p < 0.8 then out:Lerp(mag, (p - 0.55) / 0.25)
						else mag:Lerp(support, (p - 0.8) / 0.2)
				end
				solveArm(r.arms.Left, UT:PointToObjectSpace(handleCF * support), POLE.Left)
			else
				floatArms(r, t, life)
			end
		end
	elseif r.r15 then
		floatArms(r, t, life, if melee > 0 then melee else nil)
	end
end

local function scan()
	local seen = {}
	local function add(char: Model?)
		if not char then return end
		seen[char] = true
		local r = rigs[char]
		if not r or (not r.r15 and char:FindFirstChild("LowerTorso")) then rigs[char] = newRig(char) end
	end
	for _, p in Players:GetPlayers() do add(p.Character) end
	local bots = workspace:FindFirstChild("BotCharacters")
	if bots then
		for _, c in bots:GetChildren() do
			if c:IsA("Model") then add(c) end
		end
	end
	for char in rigs do
		if not seen[char] then rigs[char] = nil end
	end
end

local function step(dt: number, everyone: boolean?)
	local now = os.clock()
	if now - lastScan > 0.5 then
		lastScan = now
		scan()
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for char, r in rigs do
		if r.root.Parent ~= char or (r.rootJ and r.rootJ.Parent == nil) then
			rigs[char] = nil -- respawned or broken apart; picked up again by the next scan
			continue
		end
		r.acc += dt
		local dist = (r.root.Position - camPos).Magnitude
		if everyone or (dist < FAR and (dist < MID or r.acc >= 1 / 30)) then
			local ok, err = pcall(update, r, math.min(r.acc, 0.1), now)
			r.acc = 0
			if not ok and not r.warned then
				r.warned = true
				warn("[ZG] animator (" .. char.Name .. "): " .. tostring(err))
			end
		end
	end
end

-- A character fired (tracer from the server, or the local player's own shot).
function Anim.OnShot(char: Instance?)
	local r = char and rigs[char :: Model]
	if r then
		r.kick = 1
		r.lastShot = os.clock()
	end
end

function Anim.Fired()
	Anim.OnShot(player.Character)
end

function Anim.StartRoll(char: Instance?, dir: number)
	local r = char and rigs[char :: Model]
	if r then
		r.rollStart = os.clock()
		r.rollDir = if dir < 0 then -1 else 1
	end
end

-- The local player's own roll: animate immediately and ignore the server's echo of it.
function Anim.Roll(dir: number)
	local char = player.Character
	local r = char and rigs[char]
	if r then
		Anim.StartRoll(char, dir)
		r.localRollUntil = os.clock() + MV.RollTime + 1
	end
end

-- For tests and tools: refresh the rig list and advance every rig by dt, ignoring distance culling.
function Anim.StepAll(dt: number)
	lastScan = -math.huge
	step(dt, true)
end

function Anim.Start()
	RunService.PreSimulation:Connect(step)
	-- one line in Output so a playtest shows whether characters are being posed
	task.delay(6, function()
		local n, posed = 0, 0
		for _, r in rigs do
			n += 1
			if r.r15 then posed += 1 end
		end
		print(string.format("[ZG] animator: posing %d of %d characters", posed, n))
	end)
end

return Anim
