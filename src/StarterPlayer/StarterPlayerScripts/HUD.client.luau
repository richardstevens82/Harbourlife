local Players = game:GetService("Players")
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local gui = Instance.new("ScreenGui")
gui.Name = "HarbourlifeHUD"; gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local money = Instance.new("TextLabel")
money.Size = UDim2.fromOffset(340, 32); money.Position = UDim2.new(1, -350, 0, 10)
money.BackgroundTransparency = 0.4; money.BackgroundColor3 = Color3.new(0, 0, 0)
money.TextColor3 = Color3.new(1, 1, 1); money.Font = Enum.Font.GothamBold; money.TextSize = 16
money.Text = "Cash: ..."; money.Parent = gui

local toast = Instance.new("TextLabel")
toast.Size = UDim2.fromOffset(320, 36); toast.Position = UDim2.new(0.5, -160, 0, 20)
toast.BackgroundTransparency = 0.3; toast.BackgroundColor3 = Color3.new(0, 0, 0)
toast.TextColor3 = Color3.new(1, 1, 1); toast.Font = Enum.Font.Gotham; toast.TextSize = 16
toast.Visible = false; toast.Parent = gui

Remotes.DataChanged.OnClientEvent:Connect(function(d)
	money.Text = string.format("Lv %d | Cash $%d | Bank $%d | %s", d.level, d.cash, d.bank, d.job)
end)

local token = 0
Remotes.Notify.OnClientEvent:Connect(function(text)
	token += 1; local mine = token
	toast.Text = text; toast.Visible = true
	task.delay(3, function() if token == mine then toast.Visible = false end end)
end)

-- Inventory panel: press I
local Items = require(game.ReplicatedStorage.Shared.ItemDefinitions)
local UIS = game:GetService("UserInputService")
local panel = Instance.new("TextLabel")
panel.Size = UDim2.fromOffset(240, 260); panel.Position = UDim2.new(0, 10, 0.5, -130)
panel.BackgroundTransparency = 0.3; panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.TextColor3 = Color3.new(1, 1, 1); panel.Font = Enum.Font.Gotham; panel.TextSize = 16
panel.TextXAlignment = Enum.TextXAlignment.Left; panel.TextYAlignment = Enum.TextYAlignment.Top
panel.Visible = false; panel.Parent = gui

local lastData
local function render()
	if not lastData then return end
	local lines = { "INVENTORY (I to close)" }
	for id, n in lastData.inventory do
		table.insert(lines, string.format("%s x%d", Items[id] and Items[id].name or id, n))
	end
	table.insert(lines, "")
	table.insert(lines, "SKILLS")
	for id, s in lastData.skills do table.insert(lines, string.format("%s Lv %d", id, s.level)) end
	table.insert(lines, string.format("Reputation: %d", lastData.reputation or 0))
	panel.Text = table.concat(lines, "\n")
end
Remotes.DataChanged.OnClientEvent:Connect(function(d) lastData = d; render() end)
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.I then panel.Visible = not panel.Visible; render() end
end)

-- Vehicle gauge (reads attributes the server keeps on the seat)
local gauge = Instance.new("TextLabel")
gauge.Size = UDim2.fromOffset(220, 30); gauge.Position = UDim2.new(1, -230, 0, 48)
gauge.BackgroundTransparency = 0.4; gauge.BackgroundColor3 = Color3.new(0, 0, 0)
gauge.TextColor3 = Color3.new(1, 1, 1); gauge.Font = Enum.Font.GothamBold; gauge.TextSize = 15
gauge.Visible = false; gauge.Parent = gui
game:GetService("RunService").Heartbeat:Connect(function()
	local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat:GetAttribute("VehicleId") then
		gauge.Visible = true
		gauge.Text = string.format("Fuel %d/%d | Condition %d%%", seat:GetAttribute("Fuel") or 0, seat:GetAttribute("FuelCapacity") or 0, seat:GetAttribute("Condition") or 0)
	else
		gauge.Visible = false
	end
end)
