-- Server-authoritative inventory: three weapon slots, ammo reserves, consumables (with backpack
-- stack limits), utility (pulse charges, tether charges), armour tier and suit upgrades.
-- Clients only ever see a synced copy and send "use"/"drop" requests, all validated here.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.ItemDefinitions)
local Weapons = require(Shared.WeaponDefinitions)
local Loadouts = require(Shared.Loadouts)
local Remotes = require(Shared.Remotes)
local Roster = require(script.Parent.Roster)
local Security = require(script.Parent.SecurityService)
local CharacterService = require(script.Parent.CharacterService)

local Inventory = {}
local invs: { [Player]: any } = {}
-- Set by LootService (which depends on this module) so drops become world pickups.
Inventory.SpawnPickup = function(_pos: Vector3, _entry) end

local function empty()
	return {
		weapons = {}, -- [slot] = { id, rarity, mag }
		active = 0,
		ammo = { light = 0, medium = 0, heavy = 0, shells = 0, energy = 0 },
		items = { medkit = 0, stim = 0, o2canister = 0, shieldcell = 0, grenade = 0 },
		tether = 0,
		upgrades = {},
		armorMax = 0,
		usingUntil = 0,
		practice = false, -- lobby practice kit: infinite reserve ammo, no loot
	}
end

function Inventory.Get(player: Player)
	return invs[player]
end

local function applyAttributes(player: Player, inv)
	local w = inv.weapons[inv.active]
	local mobility = w and Weapons.Get(w.id).mobility or 1
	local up = inv.upgrades
	player:SetAttribute("SpeedMult", mobility * (up.thruster_tune and Items.List.thruster_tune.speed or 1))
	player:SetAttribute("BoostMaxMult", up.boost_cell and Items.List.boost_cell.boostMax or 1)
	player:SetAttribute("BoostRegenMult", up.boost_cell and Items.List.boost_cell.boostRegen or 1)
	player:SetAttribute("O2Efficiency", up.o2_recycler and Items.List.o2_recycler.o2Efficiency or 1)
	player:SetAttribute("TetherCharges", inv.tether)
	player:SetAttribute("ArmorMax", inv.armorMax)
	if (player:GetAttribute("Armor") or 0) > inv.armorMax then player:SetAttribute("Armor", inv.armorMax) end
end

function Inventory.Sync(player: Player)
	local inv = invs[player]
	if not inv then return end
	applyAttributes(player, inv)
	local weapons = {}
	for slot = 1, Config.Inventory.WeaponSlots do
		local w = inv.weapons[slot]
		weapons[slot] = w and { id = w.id, rarity = w.rarity, mag = w.mag, magSize = Weapons.MagSize(w.id, w.rarity) } or false
	end
	Remotes.Inventory:FireClient(player, {
		t = "sync", weapons = weapons, active = inv.active, ammo = inv.ammo, items = inv.items, tether = inv.tether,
		upgrades = inv.upgrades, armorMax = inv.armorMax, practice = inv.practice,
	})
end

function Inventory.RefreshVisual(player: Player)
	local inv = invs[player]
	local w = inv and inv.weapons[inv.active]
	CharacterService.SetWeaponVisual(player, w and w.id, w and w.rarity)
end

-- Fresh kit for a deployment (loadout) or the lobby practice range.
function Inventory.Reset(player: Player, mode: "match" | "practice" | "none", loadoutId: string?)
	local inv = empty()
	invs[player] = inv
	player:SetAttribute("Armor", 0)
	if mode == "match" then
		local l = Loadouts.Get(loadoutId or "scout")
		inv.weapons[1] = { id = Loadouts.StartWeapon, rarity = "common", mag = Weapons.MagSize(Loadouts.StartWeapon, "common") }
		inv.active = 1
		for k, v in Loadouts.StartAmmo do inv.ammo[k] = v end
		inv.tether = l.tether or Config.Tether.StartCharges
		for k, v in l.items or {} do inv.items[k] = v end
	elseif mode == "practice" then
		inv.practice = true
		inv.weapons[1] = { id = "pistol", rarity = "common", mag = Weapons.MagSize("pistol", "common") }
		inv.weapons[2] = { id = "assault", rarity = "common", mag = Weapons.MagSize("assault", "common") }
		inv.weapons[3] = { id = "shotgun", rarity = "common", mag = Weapons.MagSize("shotgun", "common") }
		inv.active = 1
		inv.tether = Config.Tether.MaxCharges
	end
	Inventory.Sync(player)
	Inventory.RefreshVisual(player)
end

function Inventory.ActiveWeapon(player: Player)
	local inv = invs[player]
	if not inv then return nil end
	return inv.weapons[inv.active], inv
end

function Inventory.SetActive(player: Player, slot: number): boolean
	local inv = invs[player]
	if not inv or not inv.weapons[slot] or inv.active == slot then return false end
	inv.active = slot
	Inventory.Sync(player)
	Inventory.RefreshVisual(player)
	return true
end

-- Adds a loot entry { id, rarity, amount }. Returns:
--   accepted (bool), leftover entry or nil (to stay on the ground), dropped entry or nil (swapped out)
function Inventory.Add(player: Player, entry)
	local inv = invs[player]
	if not inv or inv.practice then return false, entry, nil end
	local def = Items.Get(entry.id)
	if not def then return false, entry, nil end
	local IC = Config.Inventory
	local result, leftover, dropped = false, nil, nil
	if def.kind == "weapon" then
		local wid = def.weapon
		local new = { id = wid, rarity = entry.rarity or "common", mag = entry.mag or Weapons.MagSize(wid, entry.rarity or "common") }
		local slot
		for s = 1, IC.WeaponSlots do
			if not inv.weapons[s] then
				slot = s
				break
			end
		end
		if slot then
			inv.weapons[slot] = new
			if inv.active == 0 then inv.active = slot end
		else
			local old = inv.weapons[inv.active]
			inv.weapons[inv.active] = new
			dropped = { id = "weapon:" .. old.id, rarity = old.rarity, amount = 1, mag = old.mag }
		end
		result = true
	elseif def.kind == "ammo" then
		local cap = IC.AmmoCap[def.ammo]
		local space = cap - inv.ammo[def.ammo]
		local take = math.min(space, entry.amount or def.amount)
		if take <= 0 then return false, entry, nil end
		inv.ammo[def.ammo] += take
		local rest = (entry.amount or def.amount) - take
		if rest > 0 then leftover = { id = entry.id, rarity = entry.rarity, amount = rest } end
		result = true
	elseif def.kind == "consumable" or (def.kind == "utility" and def.stack) then
		local key = def.stack or entry.id
		local cap = IC.ConsumableStack[key] or 1
		if inv.items[key] >= cap then return false, entry, nil end
		inv.items[key] += 1
		result = true
	elseif def.kind == "utility" and def.tether then
		if inv.tether >= Config.Tether.MaxCharges then return false, entry, nil end
		inv.tether = math.min(Config.Tether.MaxCharges, inv.tether + def.tether)
		result = true
	elseif def.kind == "armor" then
		local armor = player:GetAttribute("Armor") or 0
		if def.armorMax <= inv.armorMax and armor >= inv.armorMax then return false, entry, nil end
		inv.armorMax = math.max(inv.armorMax, def.armorMax)
		player:SetAttribute("Armor", inv.armorMax)
		result = true
	elseif def.kind == "upgrade" then
		if inv.upgrades[entry.id] then return false, entry, nil end
		inv.upgrades[entry.id] = true
		result = true
	end
	if result then
		Inventory.Sync(player)
		if def.kind == "weapon" then Inventory.RefreshVisual(player) end
	end
	return result, leftover, dropped
end

-- Consumable use (H/O/J hotkeys or inventory screen). Takes useTime seconds; cancelled by death.
local function useItem(player: Player, itemId: string)
	local inv = invs[player]
	local def = Items.List[itemId]
	if not (inv and def and def.kind == "consumable") then return end
	if not (Roster.IsActive(player) or inv.practice) then return end
	if inv.items[itemId] <= 0 or os.clock() < inv.usingUntil then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	-- refuse pointless use
	if def.heal and hum.Health >= hum.MaxHealth then return end
	if def.oxygen and (player:GetAttribute("O2") or 0) >= Config.Oxygen.Max then return end
	if def.armor and (inv.armorMax <= 0 or (player:GetAttribute("Armor") or 0) >= inv.armorMax) then return end
	inv.usingUntil = os.clock() + def.useTime
	local char = player.Character
	Remotes.FX:FireClient(player, { t = "using", item = itemId, time = def.useTime })
	task.delay(def.useTime, function()
		if invs[player] ~= inv or player.Character ~= char or not hum.Parent or hum.Health <= 0 then return end
		if inv.items[itemId] <= 0 then return end
		inv.items[itemId] -= 1
		if def.heal then hum.Health = math.min(hum.MaxHealth, hum.Health + def.heal) end
		if def.oxygen then player:SetAttribute("O2", math.min(Config.Oxygen.Max, (player:GetAttribute("O2") or 0) + def.oxygen)) end
		if def.armor then player:SetAttribute("Armor", math.min(inv.armorMax, (player:GetAttribute("Armor") or 0) + def.armor)) end
		Inventory.Sync(player)
	end)
end

-- Consumes one pulse charge / tether charge. Returns true if one was available.
function Inventory.TakeUtility(player: Player, key: "grenade" | "tether"): boolean
	local inv = invs[player]
	if not inv then return false end
	if key == "tether" then
		if inv.tether <= 0 then return false end
		if not inv.practice then inv.tether -= 1 end
	else
		if inv.items.grenade <= 0 then return false end
		inv.items.grenade -= 1
	end
	Inventory.Sync(player)
	return true
end

-- Everything the player carries, as loot entries (for the drop-on-elimination container).
function Inventory.DumpEntries(player: Player)
	local inv = invs[player]
	local out = {}
	if not inv or inv.practice then return out end
	for _, w in inv.weapons do
		table.insert(out, { id = "weapon:" .. w.id, rarity = w.rarity, amount = 1, mag = w.mag })
	end
	for ammo, n in inv.ammo do
		if n > 0 then table.insert(out, { id = "ammo_" .. ammo, rarity = "common", amount = n }) end
	end
	for item, n in inv.items do
		for _ = 1, n do table.insert(out, { id = item, rarity = "common", amount = 1 }) end
	end
	if inv.armorMax >= 100 then table.insert(out, { id = "armor_elite", rarity = "legendary", amount = 1 })
	elseif inv.armorMax >= 75 then table.insert(out, { id = "armor_heavy", rarity = "rare", amount = 1 })
	elseif inv.armorMax >= 50 then table.insert(out, { id = "armor_light", rarity = "common", amount = 1 }) end
	for up in inv.upgrades do table.insert(out, { id = up, rarity = "rare", amount = 1 }) end
	return out
end

function Inventory.Clear(player: Player)
	invs[player] = nil
	CharacterService.SetWeaponVisual(player, nil)
	Remotes.Inventory:FireClient(player, { t = "clear" })
end

Inventory.Use = useItem -- bot entry point (same checks as the remote)

function Inventory.Start()
	Remotes.Inventory.OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or not Security.RateLimit(player, "inventory", 8, 6) then return end
		local inv = invs[player]
		if not inv then return end
		if req.action == "use" and Security.IsString(req.item, 24) then
			useItem(player, req.item)
		elseif req.action == "drop" and not inv.practice and Roster.IsActive(player) then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then return end
			local at = root.CFrame * CFrame.new(0, 0, -5)
			if type(req.slot) == "number" and inv.weapons[req.slot] then
				local w = inv.weapons[req.slot]
				inv.weapons[req.slot] = nil
				if inv.active == req.slot then
					inv.active = 0
					for s = 1, Config.Inventory.WeaponSlots do
						if inv.weapons[s] then
							inv.active = s
							break
						end
					end
				end
				Inventory.SpawnPickup(at.Position, { id = "weapon:" .. w.id, rarity = w.rarity, amount = 1, mag = w.mag })
				Inventory.Sync(player)
				Inventory.RefreshVisual(player)
			elseif Security.IsString(req.item, 24) and inv.items[req.item] and inv.items[req.item] > 0 then
				inv.items[req.item] -= 1
				Inventory.SpawnPickup(at.Position, { id = req.item, rarity = "common", amount = 1 })
				Inventory.Sync(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) invs[p] = nil end)
end

return Inventory
