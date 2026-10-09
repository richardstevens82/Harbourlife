-- Shop window. The server sends the item list; buying only sends a request, the server decides.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ShopUI"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(420, 400); frame.Position = UDim2.new(0.5, -210, 0.5, -200)
frame.BackgroundColor3 = Color3.fromRGB(25, 30, 40); frame.BackgroundTransparency = 0.05; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 0, 44); title.Position = UDim2.fromOffset(14, 0)
title.BackgroundTransparency = 1; title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold; title.TextSize = 20; title.TextColor3 = Color3.new(1, 1, 1); title.Parent = frame

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(36, 36); close.Position = UDim2.new(1, -44, 0, 4)
close.Text = "X"; close.Font = Enum.Font.GothamBold; close.TextSize = 18
close.BackgroundColor3 = Color3.fromRGB(170, 50, 50); close.TextColor3 = Color3.new(1, 1, 1); close.Parent = frame
Instance.new("UICorner", close)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -54); list.Position = UDim2.fromOffset(10, 48)
list.BackgroundTransparency = 1; list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.CanvasSize = UDim2.new()
list.Parent = frame
local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 6); layout.Parent = list

local current
local openedAt: Vector3?

local function row(shopId, it)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, -8, 0, 44); r.BackgroundColor3 = Color3.fromRGB(45, 52, 66); r.Parent = list
	Instance.new("UICorner", r).CornerRadius = UDim.new(0, 6)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -100, 1, 0); label.Position = UDim2.fromOffset(10, 0); label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left; label.Font = Enum.Font.Gotham; label.TextSize = 15
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = string.format("%s   $%d   (stock %d)", it.name, it.price, it.stock); label.Parent = r
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(80, 32); b.Position = UDim2.new(1, -88, 0.5, -16)
	b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = it.stock > 0 and "Buy" or "Sold out"
	b.BackgroundColor3 = it.stock > 0 and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(90, 90, 90)
	b.AutoButtonColor = it.stock > 0; b.Parent = r
	Instance.new("UICorner", b)
	b.Activated:Connect(function()
		if it.stock > 0 then Remotes.ShopBuy:FireServer(shopId, it.id, 1) end
	end)
end

Remotes.OpenShop.OnClientEvent:Connect(function(data)
	current = data.id
	title.Text = data.name
	for _, c in list:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	for _, it in data.items do row(data.id, it) end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not gui.Enabled then openedAt = hrp and hrp.Position end
	gui.Enabled = true
end)

close.Activated:Connect(function() gui.Enabled = false; current = nil end)

-- close when the player walks away from the counter
RunService.Heartbeat:Connect(function()
	if not gui.Enabled or not openedAt then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - openedAt).Magnitude > 18 then gui.Enabled = false; current = nil end
end)
