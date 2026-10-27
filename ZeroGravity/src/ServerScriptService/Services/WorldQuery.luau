-- Small spatial queries shared by services that place things in the world (deployment, drops).
local WorldQuery = {}

-- Free of solid geometry and terrain within about radius studs?
function WorldQuery.IsClear(pos: Vector3, radius: number?): boolean
	local r = radius or 5
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	if #workspace:GetPartBoundsInRadius(pos, r, params) > 0 then return false end
	local region = Region3.new(pos - Vector3.one * (r + 1), pos + Vector3.one * (r + 1)):ExpandToGrid(4)
	local materials = workspace.Terrain:ReadVoxels(region, 4)
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] ~= Enum.Material.Air then return false end
			end
		end
	end
	return true
end

return WorldQuery
