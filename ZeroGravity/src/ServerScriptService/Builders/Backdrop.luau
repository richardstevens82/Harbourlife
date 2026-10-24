-- Server-side lighting and sky. The planet itself is rendered client-side (BackdropController)
-- relative to the camera, so it always reads as an enormous, distant body that players can
-- never fly into, regardless of render distance.
local Lighting = game:GetService("Lighting")

local Backdrop = {}

function Backdrop.Apply()
	for _, c in Lighting:GetChildren() do
		if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("PostEffect") or c:IsA("Clouds") then c:Destroy() end
	end
	-- Night-side clock: a black, star-filled sky. The directional light becomes a hard, low sun.
	Lighting.ClockTime = 0.2
	Lighting.GeographicLatitude = 25
	Lighting.Brightness = 4
	Lighting.Ambient = Color3.fromRGB(28, 30, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(44, 48, 62)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.08
	Lighting.ExposureCompensation = 0.3
	Lighting.FogEnd = 100000

	local sky = Instance.new("Sky")
	sky.StarCount = 5000
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 6 -- reads as a distant bright star / second moon
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Contrast = 0.12
	cc.Saturation = -0.05
	cc.TintColor = Color3.fromRGB(235, 242, 255)
	cc.Parent = Lighting
end

return Backdrop
