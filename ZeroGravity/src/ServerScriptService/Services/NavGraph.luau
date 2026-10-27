-- Bot navigation graph, generated from the construction kit's registry of hollow spaces
-- (Kit.NavSpaces: rooms, corridors, tubes, airlock chambers).
--   * every passable opening becomes a door node (doors of adjoining spaces merge)
--   * each space links its centre and doors; airlock chambers mark their edges with the door
--     that must be open (bots cycle the airlock like players do)
--   * door nodes that open onto space are "exits"; all exits link to each other through open space
-- Path queries start/end inside a space (via its doors) or in open space (via the exits).
local Kit = require(script.Parent.Parent:WaitForChild("Builders"):WaitForChild("Kit"))

local Nav = {}
local nodes = {} -- { pos, edges = { { to, cost, airlock, door } }, door = bool, exit = bool }
local spaces = {} -- { cf, half, volume, center, doors = { node idx } }
local exits = {} -- node indices
local MERGE = 3
local MIN_HOLE = 6 -- smallest opening a suited character fits through
local losFn: ((Vector3, Vector3) -> boolean)? = nil

local function addNode(pos: Vector3, isDoor: boolean): number
	if isDoor then
		for i, n in nodes do
			if n.door and (n.pos - pos).Magnitude <= MERGE then return i end
		end
	end
	table.insert(nodes, { pos = pos, edges = {}, door = isDoor, exit = false })
	return #nodes
end

local function link(a: number, b: number, info, costScale: number?)
	if a == b then return end
	for _, e in nodes[a].edges do
		if e.to == b then return end
	end
	local cost = (nodes[a].pos - nodes[b].pos).Magnitude * (costScale or 1)
	table.insert(nodes[a].edges, { to = b, cost = cost, airlock = info and info.airlock, door = info and info.door })
	table.insert(nodes[b].edges, { to = a, cost = cost, airlock = info and info.airlock, door = info and info.door })
end

local function inBox(cf: CFrame, half: Vector3, pos: Vector3, pad: number): boolean
	local lp = cf:PointToObjectSpace(pos)
	return math.abs(lp.X) <= half.X + pad and math.abs(lp.Y) <= half.Y + pad and math.abs(lp.Z) <= half.Z + pad
end

-- isBlocked(pos) -> true when solid geometry (glass, breach plates...) fills an opening.
-- exclude(space) -> true for spaces bots must ignore (the lobby).
-- los(a, b) -> true when the straight flight a->b is clear (exits only link when it is).
function Nav.Build(navSpaces, isBlocked: (Vector3) -> boolean, exclude: (any) -> boolean, los: ((Vector3, Vector3) -> boolean)?)
	losFn = los
	table.clear(nodes)
	table.clear(spaces)
	table.clear(exits)
	for _, s in navSpaces do
		if not exclude(s) then
			local sp = { cf = s.cf, half = s.size / 2, pad = (s.wall or 2) + 0.6, volume = s.size.X * s.size.Y * s.size.Z, doors = {}, airlock = s.airlock }
			sp.center = addNode(s.cf.Position, false)
			for face, o in s.openings or {} do
				local passable = o == true or (type(o) == "table" and o.w >= MIN_HOLE and o.h >= MIN_HOLE)
				if passable then
					local hx = type(o) == "table" and (o.x or 0) or 0
					local hy = type(o) == "table" and (o.y or 0) or 0
					local pos = Kit.faceCFrame(s.cf, s.size, face, s.wall or 2) * Vector3.new(hx, hy, 0)
					if not isBlocked(pos) then
						local d = addNode(pos, true)
						nodes[d].out = -Kit.faceCFrame(s.cf, s.size, face, 0).LookVector -- outward normal of the face
						table.insert(sp.doors, d)
						-- airlock chamber: +Z is the inner door, -Z the outer door
						local info = s.airlock and { airlock = s.airlock, door = face == "+Z" and "InnerDoor" or "OuterDoor" } or nil
						link(sp.center, d, info)
					end
				end
			end
			if not s.airlock then
				for i = 1, #sp.doors do
					for j = i + 1, #sp.doors do link(sp.doors[i], sp.doors[j]) end
				end
			end
			table.insert(spaces, sp)
		end
	end
	-- Door nodes that sit inside another space (tube ends inside ring joints, airlock inner ends inside
	-- their host room) link to that space; doors that no other space contains open onto space: exits.
	for i, n in nodes do
		if n.door then
			local containing = 0
			for _, sp in spaces do
				if inBox(sp.cf, sp.half, n.pos, sp.pad) then
					containing += 1
					if not table.find(sp.doors, i) then link(i, sp.center) end
				end
			end
			if containing <= 1 then
				n.exit = true
				table.insert(exits, i)
			end
		end
	end
	for a = 1, #exits do
		for b = a + 1, #exits do
			local pa, pb = Nav.ExitPoint(exits[a]), Nav.ExitPoint(exits[b])
			if not losFn or losFn(pa, pb) then link(exits[a], exits[b], nil, 1.15) end
		end
	end
	return Nav.Stats()
end

-- A point just outside an exit, used for line-of-sight tests through open space.
function Nav.ExitPoint(i: number): Vector3
	local n = nodes[i]
	return n.pos + (n.out or Vector3.zero) * 4
end

-- Exits a point in open space can fly to directly (nearest first, line of sight checked).
local function visibleExits(p: Vector3): { number }
	local sorted = table.clone(exits)
	table.sort(sorted, function(a, b) return (nodes[a].pos - p).Magnitude < (nodes[b].pos - p).Magnitude end)
	local out = {}
	for k = 1, math.min(#sorted, 8) do
		local i = sorted[k]
		if not losFn or losFn(p, Nav.ExitPoint(i)) then table.insert(out, i) end
		if #out >= 4 then break end
	end
	if #out == 0 then
		for k = 1, math.min(#sorted, 3) do table.insert(out, sorted[k]) end
	end
	return out
end

function Nav.Stats()
	local edges = 0
	for _, n in nodes do edges += #n.edges end
	return { nodes = #nodes, edges = edges / 2, exits = #exits, spaces = #spaces }
end

-- Smallest space whose interior contains pos (nil = open space).
function Nav.SpaceOf(pos: Vector3)
	local best, bestV = nil, math.huge
	for _, sp in spaces do
		if sp.volume < bestV and inBox(sp.cf, sp.half, pos, 0) then best, bestV = sp, sp.volume end
	end
	return best
end

-- Binary-heap Dijkstra over the graph with virtual start/goal connections.
local function heapPush(h, item)
	table.insert(h, item)
	local i = #h
	while i > 1 do
		local p = i // 2
		if h[p][1] <= h[i][1] then break end
		h[p], h[i] = h[i], h[p]
		i = p
	end
end
local function heapPop(h)
	local top = h[1]
	local last = table.remove(h)
	if #h > 0 then
		h[1] = last
		local i = 1
		while true do
			local l, r, m = i * 2, i * 2 + 1, i
			if l <= #h and h[l][1] < h[m][1] then m = l end
			if r <= #h and h[r][1] < h[m][1] then m = r end
			if m == i then break end
			h[m], h[i] = h[i], h[m]
			i = m
		end
	end
	return top
end

-- Returns a list of waypoints { pos, airlock?, door? } from `from` to `to` (last waypoint is `to`),
-- or nil when no route exists. door/airlock: that airlock door must be open to cross into pos.
function Nav.Path(from: Vector3, to: Vector3)
	local sFrom, sTo = Nav.SpaceOf(from), Nav.SpaceOf(to)
	if sFrom == sTo then return { { pos = to } } end
	local startSet = sFrom and sFrom.doors or visibleExits(from)
	local goalSet = sTo and sTo.doors or visibleExits(to)
	if #startSet == 0 or #goalSet == 0 then return nil end
	local dist, prev, prevEdge = {}, {}, {}
	local h = {}
	for _, i in startSet do
		local d = (nodes[i].pos - from).Magnitude
		if d < (dist[i] or math.huge) then
			dist[i] = d
			heapPush(h, { d, i })
		end
	end
	local goalBonus = {}
	for _, g in goalSet do goalBonus[g] = (nodes[g].pos - to).Magnitude end
	local best, bestCost = nil, math.huge
	while #h > 0 do
		local top = heapPop(h)
		local d, i = top[1], top[2]
		if d <= (dist[i] or math.huge) and d < bestCost then
			if goalBonus[i] and d + goalBonus[i] < bestCost then best, bestCost = i, d + goalBonus[i] end
			for _, e in nodes[i].edges do
				local nd = d + e.cost
				if nd < (dist[e.to] or math.huge) then
					dist[e.to] = nd
					prev[e.to] = i
					prevEdge[e.to] = e
					heapPush(h, { nd, e.to })
				end
			end
		end
	end
	if not best then return nil end
	local out = {}
	local i = best
	local first = best
	while i do
		local e = prevEdge[i]
		table.insert(out, 1, { pos = nodes[i].pos, airlock = e and e.airlock, door = e and e.door })
		first = i
		i = prev[i]
	end
	-- entering from open space: line up just outside the exit first so the approach is straight in
	if not sFrom and nodes[first].exit then table.insert(out, 1, { pos = Nav.ExitPoint(first) }) end
	if not sTo and nodes[best].exit then table.insert(out, { pos = Nav.ExitPoint(best) }) end
	table.insert(out, { pos = to })
	return out
end

Nav.Exits = function() return exits end
Nav.Nodes = function() return nodes end
return Nav
