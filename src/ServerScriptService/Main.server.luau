local Systems = script.Parent:WaitForChild("Systems")
require(game.ReplicatedStorage.Shared.Remotes) -- create remotes first

-- Start each system on its own so one failure can't stop the rest; failures are named in Output.
local ORDER = { "DataService", "TestWorld", "JobCentre", "PizzaService", "VehicleService", "ExcavatorService" }
for _, name in ORDER do
	local ok, err = pcall(function() require(Systems[name]).Start() end)
	if not ok then warn("[Harbourlife] " .. name .. " failed to start: " .. tostring(err)) end
end
print("[Harbourlife] server started")
