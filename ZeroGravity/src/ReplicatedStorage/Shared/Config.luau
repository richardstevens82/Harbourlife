-- Central tuning values. Everything gameplay-relevant that a designer might tweak lives here.
local Config = {}

Config.GameName = "ZERO GRAVITY: LAST ORBIT"
Config.DataStoreName = "ZG_Progress_v1"

-- Match ----------------------------------------------------------------------------------------
Config.Match = {
	MinPlayers = 2, -- real players needed when bots are disabled
	MaxPlayers = 20,
	StudioMinPlayers = 1, -- solo testing in Studio: a match with one player ends when the zone wins
	LobbyCountdown = 30, -- every round: 30 s in the lobby, then 20 combatants deploy (real players first, bots fill the rest)
	PrepareTime = 3,
	DeployProtection = 4, -- seconds of invulnerability after deployment
	FinalPhaseAtPlayers = 3, -- "final combat phase" begins at this many survivors (or final zone stage)
	ResultsTime = 12,
	MaxMatchTime = 15 * 60, -- then the storm collapses (sudden death) until one combatant is left
	SuddenDeathTime = 30, -- seconds for the sudden-death collapse
	CollapseDps = 30, -- storm damage per second during a collapse
	DeploySpacing = 160, -- minimum distance between two deployment points used in one match
	TeamSize = 1, -- solo; squads would raise this (MatchService groups players by team id)
}

-- Bots fill every match (and the lobby) up to FillTo combatants: with 1 player online there are 19
-- bots; each real player who joins replaces one (after the current match). See BotService.
Config.Bots = {
	Enabled = true,
	FillTo = 20,
	MinRealPlayers = 0, -- with bots on a match always starts after the countdown (bots-only if nobody is queued)
	SkillMin = 0.72, -- 0..1; shapes reaction time, aim error/settling, headshots, strafing
	SkillMax = 0.93,
	ShowTag = true, -- "[BOT]" after bot name tags (set false to hide)
	ThinkRate = 8, -- decisions per second per bot
	SightRange = 450,
	HuntRange = 1100, -- bots track enemies this far away when nothing else needs doing
	LobbyPractice = true, -- bots shoot the lobby range drones between matches
	-- Once every real player is eliminated the storm collapses over this many seconds, so the bots-only
	-- remainder is decided quickly - still last one standing. 0 = let the match play out normally.
	CollapseWhenHumansOut = 25,
}

-- Arena geometry (studs). Arena is centred on the origin.
Config.Arena = {
	HardRadius = 2100, -- beyond this the suit computer pushes players back and they take damage
	OutOfBoundsDps = 15,
	LobbyCenter = Vector3.new(0, 300, 2600),
}

-- Zero-gravity movement ------------------------------------------------------------------------
Config.Movement = {
	Accel = 55, -- studs/s^2 while a direction key is held
	MaxSpeed = 42,
	BoostAccel = 130,
	BoostMaxSpeed = 85,
	BoostMax = 100, -- energy
	BoostDrain = 32, -- per second while boosting
	BoostRegen = 16,
	BoostRegenDelay = 1.0,
	BrakeRate = 4.0, -- exponential velocity decay per second while stabilising
	Drag = 0.08, -- tiny passive decay so a drifting player eventually settles; momentum still dominates
	StopThreshold = 0.6,
	TurnResponsiveness = 35,
	-- Air roll (Q / E): a barrel-roll dodge that throws you sideways
	RollImpulse = 34, -- studs/s added sideways (bleeds back to cruise like any overspeed)
	RollCost = 22, -- boost energy
	RollCooldown = 0.9,
	RollTime = 0.5, -- length of the barrel-roll animation
	-- Server sanity limits (with allowance for tether pulls and network jitter)
	ServerSpeedTolerance = 1.35,
	ServerCheckInterval = 0.5,
}

Config.Camera = {
	BoostFovKick = 12, -- extra field of view at full boost speed
	ShakeAngle = 3.5, -- degrees of camera shake at full trauma
	Offset = Vector3.new(2.2, 2.2, 11), -- over-the-shoulder
	AimOffset = Vector3.new(1.6, 1.4, 5.5),
	PitchLimit = 85,
	DefaultFov = 75,
	AimFovScale = 0.75,
}

-- Survival ----------------------------------------------------------------------------------------
Config.Oxygen = {
	Max = 100,
	DrainPerSecond = 0.9, -- outside pressurised areas (~110 s of exterior time)
	RefillPerSecond = 10, -- inside pressurised areas
	CanisterAmount = 50,
	StationCooldown = 20, -- per player, refill station use
	GraceSeconds = 8, -- at 0 oxygen: warnings first, then hypoxia damage
	HypoxiaDps = 6,
	WarnAt = 25,
}

Config.Health = {
	Max = 100,
	ArmorMax = 100,
	RegenEnabled = true,
	RegenDelay = 8, -- seconds without damage before regeneration starts
	RegenPerSecond = 2,
	RegenCap = 60, -- passive regen never heals above this; medical items needed beyond it
}

-- Safe zone ("orbital radiation storm"): a shrinking sphere ---------------------------------------
-- Each stage: wait (announced), then shrink over `shrink` seconds to `radius`. dps applies outside.
Config.Zone = {
	StartRadius = 1800,
	Stages = {
		{ wait = 90, shrink = 60, radius = 1150, dps = 2 },
		{ wait = 70, shrink = 50, radius = 720, dps = 4 },
		{ wait = 60, shrink = 40, radius = 420, dps = 7 },
		{ wait = 45, shrink = 35, radius = 210, dps = 11 },
		{ wait = 35, shrink = 30, radius = 90, dps = 16 },
		{ wait = 30, shrink = 30, radius = 10, dps = 25 },
	},
	WarnBefore = 15,
}

-- Equipment ---------------------------------------------------------------------------------------
Config.Tether = {
	Range = 160,
	PullSpeed = 70,
	Cooldown = 3,
	MaxDuration = 4,
	StartCharges = 3,
	MaxCharges = 6,
	ReleaseDistance = 6,
}

Config.Grenade = {
	Speed = 70,
	Fuse = 2.2,
	Radius = 20,
	Damage = 70,
	Cooldown = 1,
}

Config.Melee = {
	Range = 8,
	Damage = 35,
	Cooldown = 0.8,
}

-- Character presentation: weapon size in the hands and where the gun sits when shouldered.
Config.Character = {
	HeldWeaponScale = 0.45, -- weapon models are built at display size; this scales them to the body
	-- Grip (right hand) position relative to the HumanoidRootPart while aiming; the barrel points along
	-- the root's look direction, which follows the camera. The animator lowers it to "ready" otherwise.
	AimGrip = CFrame.new(0.4, 0.55, -0.9),
}

-- Lag compensation: a player aims at where their screen shows a target, which is where the server
-- had it about one round trip plus Roblox's interpolation delay ago. Shots that miss a target's
-- current body are re-tested against its recent past positions (see LagCompensation).
Config.LagCompensation = {
	Enabled = true,
	InterpDelay = 0.12, -- seconds the client renders other characters behind the server (added to ping)
	MaxRewind = 0.5, -- never rewind further than this, however high the ping
	Window = 0.1, -- also test this far either side of the estimate (ping jitter)
	HitRadius = 1.3, -- body capsule radius in studs (a little wider than the 2-stud torso)
}

Config.Inventory = {
	WeaponSlots = 3,
	ConsumableStack = { medkit = 3, stim = 5, o2canister = 4, shieldcell = 4, grenade = 3 },
	AmmoCap = { light = 180, medium = 210, heavy = 40, shells = 40, energy = 60 },
	PickupRange = 14,
	SearchRange = 14,
	DropOnDeathLifetime = 90,
}

Config.Loot = {
	ItemsPerContainer = { min = 2, max = 4 },
	PickupLifetime = 300,
}

-- Hazards ------------------------------------------------------------------------------------------
Config.Hazards = {
	ElectricWarn = 1.6,
	ElectricActive = 1.0,
	ElectricIdle = 3.5,
	ElectricDamage = 18,
	BarrelHealth = 40,
	BarrelFuse = 0.7,
	BarrelRadius = 22,
	BarrelDamage = 65,
	ReactorDps = 5,
	BreachHealth = 160,
}

-- Rewards / progression ---------------------------------------------------------------------------
Config.Rewards = {
	Participation = 40,
	PerKill = 30,
	PerDamage = 0.1,
	WinBonus = 200,
	PlacementBonus = { [1] = 150, [2] = 90, [3] = 60, [4] = 40, [5] = 25 },
	CreditsPerXp = 0.5,
	PerMedal = 15, -- XP for each medal earned in the match
}

-- Dynamic match events (EventService).
Config.Events = {
	SupplyDropTimes = { 120, 300, 480 }, -- seconds after deployment
	DropFallTime = 10, -- seconds from the warning to touchdown
	DropItems = { min = 4, max = 6 },
}

-- Kill medals (MatchService): shown to the killer, sprees announced to everyone.
Config.Medals = {
	ChainWindow = 5, -- seconds between kills for DOUBLE / TRIPLE / MULTI KILL
	LongShot = 150, -- studs
	Streaks = { [3] = "KILLING SPREE", [5] = "RAMPAGE", [8] = "UNSTOPPABLE", [12] = "ORBITAL LEGEND" },
}

function Config.XpForLevel(level: number): number
	return math.floor(200 * level ^ 1.35)
end

return Config
