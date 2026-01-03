local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local guiParent = gethui and gethui() or game:GetService("CoreGui")

local old = guiParent:FindFirstChild("TDSGui")
if old then
	old:Destroy()
end

local TDSGui = Instance.new("ScreenGui")
TDSGui.Name = "TDSGui"
TDSGui.Parent = guiParent
TDSGui.ResetOnSpawn = false
TDSGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local bckpattern = Instance.new("ImageLabel")
local UICorner = Instance.new("UICorner")
local Tab1 = Instance.new("Frame")
local Consoleframe = Instance.new("Frame")
local shadowHolder = Instance.new("Frame")
local umbraShadow = Instance.new("ImageLabel")
local penumbraShadow = Instance.new("ImageLabel")
local ambientShadow = Instance.new("ImageLabel")
local Console = Instance.new("ScrollingFrame")
local UIListLayout = Instance.new("UIListLayout")
local TextLabel = Instance.new("TextLabel")
local UIScale = Instance.new("UIScale")

bckpattern.Parent = TDSGui
bckpattern.Active = true
bckpattern.Draggable = true
bckpattern.BorderSizePixel = 0
bckpattern.Position = UDim2.new(0.25, 0, 0.2, 0)
bckpattern.Size = UDim2.new(0.5, 0, 0.6, 0)
bckpattern.Image = "rbxassetid://118045968280960"
bckpattern.ImageColor3 = Color3.fromRGB(18, 18, 18)
bckpattern.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
bckpattern.ScaleType = Enum.ScaleType.Crop

UICorner.Parent = bckpattern
UICorner.CornerRadius = UDim.new(0, 12)

UIScale.Parent = bckpattern
UIScale.Scale = 0 -- start hidden
if not UIS.TouchEnabled then
	UIScale.Scale = 0
end

Tab1.Parent = bckpattern
Tab1.BackgroundTransparency = 1
Tab1.Size = UDim2.new(1, 0, 1, 0)

Consoleframe.Parent = Tab1
Consoleframe.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
Consoleframe.BorderSizePixel = 0
Consoleframe.Position = UDim2.new(0.045, 0, 0.17, 0)
Consoleframe.Size = UDim2.new(0.91, 0, 0.78, 0)
Instance.new("UICorner", Consoleframe).CornerRadius = UDim.new(0, 10)

shadowHolder.Parent = Consoleframe
shadowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
shadowHolder.BackgroundTransparency = 1
shadowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
shadowHolder.Size = UDim2.new(1, 0, 1, 0)

umbraShadow.Parent = shadowHolder
umbraShadow.AnchorPoint = Vector2.new(0.5, 0.5)
umbraShadow.BackgroundTransparency = 1
umbraShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
umbraShadow.Size = UDim2.new(1, 0, 1, 0)
umbraShadow.Image = "rbxassetid://1316045217"
umbraShadow.ImageTransparency = 0.9
umbraShadow.ScaleType = Enum.ScaleType.Slice
umbraShadow.SliceCenter = Rect.new(10, 10, 118, 118)

penumbraShadow.Parent = shadowHolder
penumbraShadow.AnchorPoint = Vector2.new(0.5, 0.5)
penumbraShadow.BackgroundTransparency = 1
penumbraShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
penumbraShadow.Size = UDim2.new(1, 0, 1, 0)
penumbraShadow.Image = umbraShadow.Image
penumbraShadow.ImageTransparency = 0.92
penumbraShadow.ScaleType = Enum.ScaleType.Slice
penumbraShadow.SliceCenter = umbraShadow.SliceCenter

ambientShadow.Parent = shadowHolder
ambientShadow.Visible = false

Console.Parent = Consoleframe
Console.BackgroundTransparency = 1
Console.Size = UDim2.new(1, 0, 1, 0)
Console.ScrollBarThickness = 2
Console.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90)

UIListLayout.Parent = Console
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout.Padding = UDim.new(0, 6)

TextLabel.Parent = Tab1
TextLabel.BackgroundTransparency = 1
TextLabel.Position = UDim2.new(0.5, 0, 0.035, 0)
TextLabel.AnchorPoint = Vector2.new(0.5, 0)
TextLabel.Size = UDim2.new(0.6, 0, 0.1, 0)
TextLabel.Font = Enum.Font.GothamSemibold
TextLabel.Text = "Pure Strategy"
TextLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
TextLabel.TextScaled = true

local ToggleButton = Instance.new("TextButton")
ToggleButton.Parent = TDSGui
ToggleButton.Size = UDim2.new(0, 120, 0, 34)
ToggleButton.Position = UDim2.new(0, 12, 1, -46)
ToggleButton.Text = "Toggle GUI"
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 14
ToggleButton.TextColor3 = Color3.fromRGB(220, 220, 220)
ToggleButton.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 8)

-- Tweens for animation
local openTween = TweenService:Create(
	UIScale,
	TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ Scale = UIS.TouchEnabled and 1 or 0.8 }
)

local closeTween = TweenService:Create(
	UIScale,
	TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	{ Scale = 0 }
)

local fadeIn = TweenService:Create(
	bckpattern,
	TweenInfo.new(0.2),
	{ ImageTransparency = 0 }
)

local fadeOut = TweenService:Create(
	bckpattern,
	TweenInfo.new(0.2),
	{ ImageTransparency = 1 }
)

bckpattern.Visible = false
local visible = false
local busy = false

local function toggle()
	if busy then return end
	busy = true
	visible = not visible

	if visible then
		bckpattern.Visible = true
		openTween:Play()
		fadeIn:Play()
		fadeIn.Completed:Wait()
	else
		closeTween:Play()
		fadeOut:Play()
		fadeOut.Completed:Wait()
		bckpattern.Visible = false
	end

	busy = false
end

ToggleButton.MouseButton1Click:Connect(toggle)

UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.Delete or i.KeyCode == Enum.KeyCode.LeftAlt then
		toggle()
	end
end)

shared.AutoStratGUI = {
	Console = Console,
	bckpattern = bckpattern
}