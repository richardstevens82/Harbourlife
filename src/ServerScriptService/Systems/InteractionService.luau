-- Single place that turns world objects into interactable prompts.
-- The server owns the ProximityPrompt, so distance is enforced by Roblox and the
-- callback only ever runs on the server, with a per-player cooldown.
local Config = require(game.ReplicatedStorage.Shared.Config)

local I = {}
local last: { [Player]: { [Instance]: number } } = {}

function I.Register(part: BasePart, opts: { action: string, object: string?, distance: number?, onTriggered: (Player) -> () })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = opts.action
	prompt.ObjectText = opts.object or ""
	prompt.MaxActivationDistance = opts.distance or 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local now = os.clock()
		last[player] = last[player] or {}
		if now - (last[player][prompt] or 0) < Config.InteractCooldown then return end
		last[player][prompt] = now
		opts.onTriggered(player)
	end)
	return prompt
end

game.Players.PlayerRemoving:Connect(function(p) last[p] = nil end)

return I
