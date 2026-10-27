-- Starting kits chosen in the lobby. Deliberately side-grades: everyone deploys with a common
-- pistol; the kit only changes a small piece of utility.
local Loadouts = {}

Loadouts.List = {
	{ id = "scout", name = "Scout", desc = "Pistol, 5 tether charges.", tether = 5 },
	{ id = "medic", name = "Field Medic", desc = "Pistol, 3 tether charges, 2 med stims.", tether = 3, items = { stim = 2 } },
	{ id = "breacher", name = "Breacher", desc = "Pistol, 3 tether charges, 1 pulse charge.", tether = 3, items = { grenade = 1 } },
	{ id = "spacer", name = "Spacer", desc = "Pistol, 3 tether charges, 1 oxygen canister.", tether = 3, items = { o2canister = 1 } },
}

Loadouts.StartWeapon = "pistol"
Loadouts.StartAmmo = { light = 36 }

function Loadouts.Get(id: string)
	for _, l in Loadouts.List do
		if l.id == id then return l end
	end
	return Loadouts.List[1]
end

return Loadouts
