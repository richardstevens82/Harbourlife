-- Artificial gravity. Pressurised decks that sit level (station modules, the ship, the lobby) pull
-- toward their floor; lift columns through floor and ceiling hatches, vertical shafts, the habitat
-- ring, tilted wrecks, hangars, airlocks and open space are zero-g. The zones are parts tagged
-- "GravityZone" (pull toward the part's local -Y) and "LiftZone" (zero-g override), placed by
-- Kit.room. Shared by clients (own movement, animation) and the server (bots, loot placement).
local CollectionService = game:GetService("CollectionService")

local Gravity = {}
local lifts: { Instance } = {}
local zones: { Instance } = {}
local cachedAt = -math.huge

local function inside(part: BasePart, pos: Vector3): boolean
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

-- The "up" direction of the gravity acting at pos, or nil where there is none (zero-g).
function Gravity.UpAt(pos: Vector3): Vector3?
	local now = os.clock()
	if now - cachedAt > 2 then -- zones only appear when the world is built; refresh now and then
		cachedAt = now
		lifts, zones = CollectionService:GetTagged("LiftZone"), CollectionService:GetTagged("GravityZone")
	end
	for _, z in lifts do
		if z:IsA("BasePart") and z.Parent and inside(z, pos) then return nil end
	end
	for _, z in zones do
		-- a breached deck loses its gravity along with its air
		if z:IsA("BasePart") and z.Parent and not z:GetAttribute("Breached") and inside(z, pos) then return z.CFrame.UpVector end
	end
	return nil
end

-- Distance from `from` down (against `up`) to the first solid surface within `range`, or nil.
function Gravity.FloorDistance(from: Vector3, up: Vector3, range: number, params: RaycastParams): number?
	local hit = workspace:Raycast(from, -up * range, params)
	return hit and (hit.Position - from).Magnitude or nil
end

return Gravity
