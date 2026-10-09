-- Placeholder Job Centre: a pad in Workspace named "JobCentre_<jobId>" becomes a sign-up point.
-- Example: name a Part "JobCentre_pizza_cook". Replace with the real building later.
local Jobs = require(game.ReplicatedStorage.Shared.JobDefinitions)
local Interaction = require(script.Parent.InteractionService)
local JobService = require(script.Parent.JobService)

local C = {}

local function hook(part: Instance)
	if not part:IsA("BasePart") then return end
	local jobId = part.Name:match("^JobCentre_(.+)$")
	if not jobId or not Jobs[jobId] then return end
	Interaction.Register(part, {
		action = "Take job",
		object = Jobs[jobId].name,
		onTriggered = function(player) JobService.SetJob(player, jobId) end,
	})
end

function C.Start()
	for _, d in workspace:GetDescendants() do hook(d) end
	workspace.DescendantAdded:Connect(hook)
end

return C
