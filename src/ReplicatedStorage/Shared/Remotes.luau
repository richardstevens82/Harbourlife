-- Creates (server) or waits for (client) the shared RemoteEvents.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "DataChanged", "Notify", "ExcavatorAction", "OpenShop", "ShopBuy" }
local Remotes = {}

local folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, name in NAMES do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name)
end
return Remotes
