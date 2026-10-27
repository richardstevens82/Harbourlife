-- Safe-zone geometry. Pure functions (Vector3 maths only) so they can be unit-tested.
local Zone = {}

-- Next stage centre: move toward `target` but keep the new sphere entirely inside the old one,
-- so a player standing in the next safe area is always inside the current one too.
function Zone.NextCenter(oldCenter: Vector3, oldRadius: number, newRadius: number, target: Vector3): Vector3
	local slack = math.max(oldRadius - newRadius, 0)
	local offset = target - oldCenter
	local dist = offset.Magnitude
	if dist <= slack then return target end
	return oldCenter + offset.Unit * slack
end

-- Zone state at time t during a shrink from (c0, r0) to (c1, r1) over `duration` seconds from t0.
function Zone.Interpolate(c0: Vector3, r0: number, c1: Vector3, r1: number, t0: number, duration: number, t: number)
	if duration <= 0 then return c1, r1 end
	local a = math.clamp((t - t0) / duration, 0, 1)
	return c0:Lerp(c1, a), r0 + (r1 - r0) * a
end

function Zone.IsInside(center: Vector3, radius: number, pos: Vector3): boolean
	return (pos - center).Magnitude <= radius
end

-- Distance outside the zone boundary (0 when inside).
function Zone.DistanceOutside(center: Vector3, radius: number, pos: Vector3): number
	return math.max((pos - center).Magnitude - radius, 0)
end

-- Builds the full stage schedule: list of { startShrink, endShrink, fromC, fromR, toC, toR, dps }.
function Zone.BuildSchedule(stages, startCenter: Vector3, startRadius: number, finalTarget: Vector3, startTime: number)
	local schedule = {}
	local t, c, r = startTime, startCenter, startRadius
	for i, s in stages do
		local nc = Zone.NextCenter(c, r, s.radius, finalTarget)
		local startShrink = t + s.wait
		table.insert(schedule, {
			index = i, announceAt = t, startShrink = startShrink, endShrink = startShrink + s.shrink,
			fromC = c, fromR = r, toC = nc, toR = s.radius, dps = s.dps,
		})
		t, c, r = startShrink + s.shrink, nc, s.radius
	end
	return schedule
end

-- Current (center, radius, dps, stageIndex, phase, nextEventTime) for schedule at time now.
-- phase: "waiting" (before stage shrink) | "shrinking" | "final" (after last stage)
function Zone.Evaluate(schedule, now: number, startCenter: Vector3, startRadius: number, baseDps: number)
	for _, st in schedule do
		if now < st.startShrink then
			return st.fromC, st.fromR, (st.index == 1 and baseDps or schedule[st.index - 1].dps), st.index, "waiting", st.startShrink
		elseif now < st.endShrink then
			local c, r = Zone.Interpolate(st.fromC, st.fromR, st.toC, st.toR, st.startShrink, st.endShrink - st.startShrink, now)
			return c, r, st.dps, st.index, "shrinking", st.endShrink
		end
	end
	local last = schedule[#schedule]
	if not last then return startCenter, startRadius, baseDps, 0, "final", math.huge end
	return last.toC, last.toR, last.dps, last.index, "final", math.huge
end

return Zone
