local Systems = script.Parent:WaitForChild("Systems")
require(game.ReplicatedStorage.Shared.Remotes) -- create remotes first
require(Systems.DataService).Start()
require(Systems.JobCentre).Start()
