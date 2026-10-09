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
