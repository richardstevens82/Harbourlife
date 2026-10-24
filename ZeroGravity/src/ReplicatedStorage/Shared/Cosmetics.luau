-- Cosmetic suit finishes unlocked by level. Purely visual; no competitive effect.
local Cosmetics = {}

Cosmetics.Suits = {
	{ id = "navy", name = "Fleet Navy", level = 1, suit = Color3.fromRGB(40, 70, 160), trim = Color3.fromRGB(230, 130, 40) },
	{ id = "graphite", name = "Graphite Ops", level = 3, suit = Color3.fromRGB(55, 58, 64), trim = Color3.fromRGB(90, 170, 255) },
	{ id = "rescue", name = "Rescue Orange", level = 5, suit = Color3.fromRGB(220, 110, 35), trim = Color3.fromRGB(235, 235, 240) },
	{ id = "arctic", name = "Arctic Survey", level = 8, suit = Color3.fromRGB(215, 222, 230), trim = Color3.fromRGB(40, 120, 220) },
	{ id = "crimson", name = "Crimson Vanguard", level = 12, suit = Color3.fromRGB(150, 25, 35), trim = Color3.fromRGB(30, 30, 34) },
	{ id = "aurum", name = "Aurum Command", level = 18, suit = Color3.fromRGB(205, 160, 50), trim = Color3.fromRGB(25, 25, 30) },
}

Cosmetics.Titles = {
	{ id = "recruit", name = "Recruit", level = 1 },
	{ id = "spacer", name = "Spacer", level = 4 },
	{ id = "voidwalker", name = "Voidwalker", level = 10 },
	{ id = "lastorbit", name = "Last Orbit", wins = 1 },
	{ id = "ace", name = "Orbital Ace", kills = 50 },
}

function Cosmetics.GetSuit(id: string)
	for _, s in Cosmetics.Suits do
		if s.id == id then return s end
	end
	return Cosmetics.Suits[1]
end

function Cosmetics.IsUnlocked(entry, profile): boolean
	if entry.level and (profile.level or 1) < entry.level then return false end
	if entry.wins and (profile.wins or 0) < entry.wins then return false end
	if entry.kills and (profile.kills or 0) < entry.kills then return false end
	return true
end

return Cosmetics
