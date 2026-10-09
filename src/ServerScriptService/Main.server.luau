local Systems = script.Parent:WaitForChild("Systems")
require(game.ReplicatedStorage.Shared.Remotes) -- create remotes first
require(Systems.DataService).Start()
require(Systems.TestWorld).Start() -- before the systems below so Parts exist
require(Systems.JobCentre).Start()
require(Systems.PizzaService).Start()
