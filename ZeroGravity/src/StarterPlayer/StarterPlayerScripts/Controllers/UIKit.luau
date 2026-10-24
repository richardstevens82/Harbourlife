-- Small UI construction helpers so every screen shares one look: transparent dark panels,
-- thin cyan strokes, clean Gotham type, restrained neon accents.
local UIKit = {}

UIKit.Colors = {
	Panel = Color3.fromRGB(10, 14, 22),
	PanelLight = Color3.fromRGB(22, 30, 44),
	Stroke = Color3.fromRGB(70, 150, 230),
	Text = Color3.fromRGB(225, 235, 248),
	Dim = Color3.fromRGB(140, 155, 175),
	Accent = Color3.fromRGB(80, 180, 255),
	Orange = Color3.fromRGB(255, 140, 50),
	Red = Color3.fromRGB(255, 70, 60),
	Green = Color3.fromRGB(90, 220, 140),
	Health = Color3.fromRGB(235, 240, 245),
	Shield = Color3.fromRGB(70, 150, 255),
	Oxygen = Color3.fromRGB(90, 230, 220),
	Boost = Color3.fromRGB(255, 160, 60),
	Storm = Color3.fromRGB(190, 110, 255),
}
local C = UIKit.Colors

function UIKit.new(className: string, props, parent: Instance?)
	local i = Instance.new(className)
	for k, v in props or {} do
		(i :: any)[k] = v
	end
	if parent then i.Parent = parent end
	return i
end
local new = UIKit.new

function UIKit.corner(parent: Instance, r: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, parent)
end

function UIKit.stroke(parent: Instance, color: Color3?, transparency: number?)
	return new("UIStroke", { Color = color or C.Stroke, Transparency = transparency or 0.55, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function UIKit.panel(parent: Instance, props)
	local f = new("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, parent)
	for k, v in props or {} do (f :: any)[k] = v end
	UIKit.corner(f)
	UIKit.stroke(f)
	return f
end

function UIKit.label(parent: Instance, text: string, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = C.Text, Font = Enum.Font.GothamMedium, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 20),
	}, parent)
	for k, v in props or {} do (l :: any)[k] = v end
	return l
end

function UIKit.button(parent: Instance, text: string, props, onClick: (() -> ())?)
	local b = new("TextButton", {
		BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.1, BorderSizePixel = 0, AutoButtonColor = true,
		Text = text, TextColor3 = C.Text, Font = Enum.Font.GothamBold, TextSize = 16, Size = UDim2.new(1, 0, 0, 38),
	}, parent)
	for k, v in props or {} do (b :: any)[k] = v end
	UIKit.corner(b)
	UIKit.stroke(b, C.Stroke, 0.4)
	if onClick then b.MouseButton1Click:Connect(onClick) end
	return b
end

-- Horizontal bar with fill; returns frame and a setter (fraction 0..1, optional text).
function UIKit.bar(parent: Instance, color: Color3, props)
	local back = new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 36, 48), BackgroundTransparency = 0.2, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 12) }, parent)
	for k, v in props or {} do (back :: any)[k] = v end
	UIKit.corner(back, 3)
	local fill = new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, back)
	UIKit.corner(fill, 3)
	local text = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = Color3.fromRGB(10, 14, 22), Text = "", ZIndex = 3 }, back)
	local function set(frac: number, txt: string?)
		fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
		text.Text = txt or ""
	end
	return back, set, fill
end

function UIKit.list(parent: Instance, padding: number?, horizontal: boolean?)
	return new("UIListLayout", {
		Padding = UDim.new(0, padding or 6), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
	}, parent)
end

function UIKit.pad(parent: Instance, px: number)
	return new("UIPadding", { PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px), PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px) }, parent)
end

function UIKit.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return UIKit
