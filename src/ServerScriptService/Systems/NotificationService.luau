local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local N = {}
function N.Send(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, tostring(text):sub(1, 120), kind or "info")
end
return N
