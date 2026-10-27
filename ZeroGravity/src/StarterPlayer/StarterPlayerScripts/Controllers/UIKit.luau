-- UI construction kit: one "orbital HUD" look shared by every screen.
--   * deep-space glass panels (navy with a soft vertical sheen) edged by a light-catching cyan stroke
--   * HUD corner brackets on major panels
--   * Michroma display type, Titillium body, Sarpanch for numbers and short readouts
--   * segmented telemetry bars, buttons with an accent rail and animated hover glow
local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Fonts = {
	Display = Enum.Font.Michroma, -- titles, section headers, buttons
	Body = Enum.Font.TitilliumWeb, -- paragraphs and descriptions
	Bold = Enum.Font.Sarpanch, -- numbers, readouts, short labels
	Mono = Enum.Font.RobotoMono, -- key bindings, tabular values
}
local F = UIKit.Fonts

UIKit.Colors = {
	Panel = Color3.fromRGB(6, 12, 26),
	PanelLight = Color3.fromRGB(14, 28, 52),
	Stroke = Color3.fromRGB(0, 210, 255),
	Text = Color3.fromRGB(228, 242, 255),
	Dim = Color3.fromRGB(128, 160, 196),
	Accent = Color3.fromRGB(0, 225, 255),
	Accent2 = Color3.fromRGB(150, 110, 255),
	Orange = Color3.fromRGB(255, 170, 60),
	Red = Color3.fromRGB(255, 72, 96),
	Green = Color3.fromRGB(70, 255, 170),
	Health = Color3.fromRGB(235, 248, 255),
	Shield = Color3.fromRGB(60, 160, 255),
	Oxygen = Color3.fromRGB(70, 240, 225),
	Boost = Color3.fromRGB(255, 176, 70),
	Storm = Color3.fromRGB(196, 110, 255),
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
	return new("UICorner", { CornerRadius = UDim.new(0, r or 3) }, parent)
end

-- Stroke that catches the light on its left/top edge and fades out to the right.
function UIKit.stroke(parent: Instance, color: Color3?, transparency: number?)
	local s = new("UIStroke", { Color = color or C.Stroke, Transparency = transparency or 0.35, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
	new("UIGradient", { Rotation = 25, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.55), NumberSequenceKeypoint.new(1, 0.25),
	}) }, s)
	return s
end

-- Four L-shaped corner brackets, the classic HUD framing.
function UIKit.brackets(parent: Instance, color: Color3?, len: number?)
	local L = len or 12
	local col = color or C.Accent
	for _, c in { { 0, 0, 1, 1 }, { 1, 0, -1, 1 }, { 0, 1, 1, -1 }, { 1, 1, -1, -1 } } do
		local anchor = Vector2.new(c[1], c[2])
		new("Frame", { Name = "Bracket", BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = anchor, Position = UDim2.fromScale(c[1], c[2]),
			Size = UDim2.fromOffset(L, 2), ZIndex = 5 }, parent)
		new("Frame", { Name = "Bracket", BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = anchor, Position = UDim2.fromScale(c[1], c[2]),
			Size = UDim2.fromOffset(2, L), ZIndex = 5 }, parent)
	end
end

-- Glass panel. opts.brackets adds HUD corner brackets; opts.accent tints edge and brackets.
function UIKit.panel(parent: Instance, props, opts)
	opts = opts or {}
	local f = new("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.18, BorderSizePixel = 0 }, parent)
	for k, v in props or {} do (f :: any)[k] = v end
	UIKit.corner(f)
	UIKit.stroke(f, opts.accent)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(190, 225, 255), Color3.fromRGB(150, 170, 200)),
		Transparency = NumberSequence.new(0, 0.1) }, f)
	if opts.brackets then UIKit.brackets(f, opts.accent) end
	return f
end

function UIKit.label(parent: Instance, text: string, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = C.Text, Font = F.Body, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 20),
	}, parent)
	for k, v in props or {} do (l :: any)[k] = v end
	return l
end

-- Display-font heading with a short accent underline.
function UIKit.title(parent: Instance, text: string, props)
	local l = UIKit.label(parent, text, { Font = F.Display, TextSize = 22, Size = UDim2.new(1, 0, 0, 34), TextColor3 = C.Text })
	for k, v in props or {} do (l :: any)[k] = v end
	new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(56, 2) }, l)
	return l
end

local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Button with a left accent rail and an animated hover glow. opts.primary = filled cyan call to action.
function UIKit.button(parent: Instance, text: string, props, onClick: (() -> ())?, opts)
	opts = opts or {}
	local base = opts.primary and Color3.fromRGB(0, 120, 160) or C.PanelLight
	local b = new("TextButton", {
		BackgroundColor3 = base, BackgroundTransparency = opts.primary and 0.05 or 0.25, BorderSizePixel = 0, AutoButtonColor = false,
		Text = text, TextColor3 = C.Text, Font = F.Display, TextSize = 14, Size = UDim2.new(1, 0, 0, 38),
	}, parent)
	for k, v in props or {} do (b :: any)[k] = v end
	UIKit.corner(b, 2)
	local stroke = UIKit.stroke(b, opts.primary and C.Accent or C.Stroke, opts.primary and 0.1 or 0.5)
	local rail = new("Frame", { Name = "Rail", BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0),
		BackgroundTransparency = opts.primary and 0 or 0.6 }, b)
	if opts.primary then
		new("UIGradient", { Rotation = 0, Color = ColorSequence.new(Color3.fromRGB(0, 210, 255), Color3.fromRGB(110, 90, 255)) }, b)
	end
	local hover = base:Lerp(C.Accent, 0.35)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, HOVER, { BackgroundColor3 = hover }):Play()
		TweenService:Create(stroke, HOVER, { Transparency = 0 }):Play()
		TweenService:Create(rail, HOVER, { BackgroundTransparency = 0, Size = UDim2.new(0, 5, 1, 0) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, HOVER, { BackgroundColor3 = base }):Play()
		TweenService:Create(stroke, HOVER, { Transparency = opts.primary and 0.1 or 0.5 }):Play()
		TweenService:Create(rail, HOVER, { BackgroundTransparency = opts.primary and 0 or 0.6, Size = UDim2.new(0, 3, 1, 0) }):Play()
	end)
	if onClick then b.MouseButton1Click:Connect(onClick) end
	return b
end

-- Segmented telemetry bar; returns frame, setter (fraction 0..1, optional text) and the fill.
function UIKit.bar(parent: Instance, color: Color3, props, segments: number?)
	local back = new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 22, 40), BackgroundTransparency = 0.15, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 12), ClipsDescendants = true }, parent)
	for k, v in props or {} do (back :: any)[k] = v end
	UIKit.corner(back, 2)
	new("UIStroke", { Color = color, Transparency = 0.7, Thickness = 1 }, back)
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, back)
	UIKit.corner(fill, 2)
	new("UIGradient", { Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.35), color:Lerp(Color3.new(1, 1, 1), 0.15)) }, fill)
	local n = segments or 10
	for i = 1, n - 1 do
		new("Frame", { Name = "Tick", BackgroundColor3 = Color3.fromRGB(4, 10, 20), BackgroundTransparency = 0.2, BorderSizePixel = 0,
			Position = UDim2.new(i / n, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), ZIndex = 2 }, back)
	end
	local text = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 1, 0), Position = UDim2.fromOffset(3, 0), Font = F.Bold,
		TextSize = 12, TextColor3 = C.Text, TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = 3 }, back)
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

-- Slide + fade a frame in (used when menus and result screens open).
function UIKit.reveal(frame: GuiObject, fromOffset: Vector2, delay: number?)
	local target = frame.Position
	frame.Position = target + UDim2.fromOffset(fromOffset.X, fromOffset.Y)
	task.delay(delay or 0, function()
		TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = target }):Play()
	end)
end

function UIKit.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return UIKit
