local TDSGui = Instance.new("ScreenGui")
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
local UIS = game:GetService("UserInputService")

TDSGui.Name = "TDSGui"
TDSGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
TDSGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
TDSGui.ResetOnSpawn = false
TDSGui.Enabled = true

bckpattern.Name = "bckpattern"
bckpattern.Parent = TDSGui
bckpattern.Active = true
bckpattern.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
bckpattern.BorderSizePixel = 0
bckpattern.Draggable = true
bckpattern.Position = UDim2.new(0.253089815, 0, 0.195836768, 0)
bckpattern.Size = UDim2.new(0.492764741, 0, 0.607694149, 0)
bckpattern.Image = "rbxassetid://118045968280960"
bckpattern.ImageColor3 = Color3.fromRGB(13, 13, 13)
bckpattern.ScaleType = Enum.ScaleType.Crop

UICorner.Parent = bckpattern

UIScale.Parent = bckpattern
if not UIS.TouchEnabled then
	UIScale.Scale = 0.8
end

Tab1.Name = "Tab1"
Tab1.Parent = bckpattern
Tab1.BackgroundTransparency = 1
Tab1.Size = UDim2.new(1, 0, 1, 0)

Consoleframe.Name = "Consoleframe"
Consoleframe.Parent = Tab1
Consoleframe.BackgroundColor3 = Color3.fromRGB(21, 21, 21)
Consoleframe.BorderSizePixel = 0
Consoleframe.Position = UDim2.new(0.044511538, 0, 0.172486231, 0)
Consoleframe.Size = UDim2.new(0.905291438, 0, 0.779315889, 0)

shadowHolder.Name = "shadowHolder"
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
umbraShadow.ImageTransparency = 0.88
umbraShadow.ScaleType = Enum.ScaleType.Slice
umbraShadow.SliceCenter = Rect.new(10, 10, 118, 118)

penumbraShadow.Parent = shadowHolder
penumbraShadow.AnchorPoint = Vector2.new(0.5, 0.5)
penumbraShadow.BackgroundTransparency = 1
penumbraShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
penumbraShadow.Size = UDim2.new(1, 0, 1, 0)
penumbraShadow.Image = "rbxassetid://1316045217"
penumbraShadow.ImageTransparency = 0.88
penumbraShadow.ScaleType = Enum.ScaleType.Slice
penumbraShadow.SliceCenter = Rect.new(10, 10, 118, 118)

ambientShadow.Parent = shadowHolder
ambientShadow.AnchorPoint = Vector2.new(0.5, 0.5)
ambientShadow.BackgroundTransparency = 1
ambientShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
ambientShadow.Size = UDim2.new(1, 0, 1, 0)
ambientShadow.Visible = false
ambientShadow.Image = "rbxassetid://1316045217"
ambientShadow.ImageTransparency = 0.88
ambientShadow.ScaleType = Enum.ScaleType.Slice
ambientShadow.SliceCenter = Rect.new(10, 10, 118, 118)

Console.Name = "Console"
Console.Parent = Consoleframe
Console.Active = true
Console.AnchorPoint = Vector2.new(0.5, 0.5)
Console.BackgroundTransparency = 1
Console.Position = UDim2.new(0.5, 0, 0.5, 0)
Console.Size = UDim2.new(1, 0, 1, 0)
Console.ScrollBarThickness = 1

UIListLayout.Parent = Console
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

TextLabel.Parent = Tab1
TextLabel.BackgroundTransparency = 1
TextLabel.Position = UDim2.new(0.5, 0, 0.03, 0)
TextLabel.AnchorPoint = Vector2.new(0.5, 0)
TextLabel.Size = UDim2.new(0.6, 0, 0.11, 0)
TextLabel.Font = Enum.Font.SourceSansSemibold
TextLabel.Text = "Pure Strategy"
TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TextLabel.TextScaled = true

local ToggleButton = Instance.new("TextButton", TDSGui)
ToggleButton.Size = UDim2.new(0, 100, 0, 30)
ToggleButton.Position = UDim2.new(0, 10, 1, -40)
ToggleButton.Text = "Toggle GUI"
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 14
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.BackgroundColor3 = Color3.fromRGB(50, 150, 255)
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 6)

local guiVisible = true

local function toggleGUI()
	guiVisible = not guiVisible
	TDSGui.Enabled = guiVisible
end

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.LeftAlt then
		toggleGUI()
	end
end)

ToggleButton.MouseButton1Click:Connect(toggleGUI)

local guiParent = gethui and gethui() or game:GetService("CoreGui")

local existing = guiParent:FindFirstChild("TDSGui")
if existing then
	existing:Destroy()
end

shared.AutoStratGUI = {
	Console = Console,
	bckpattern = bckpattern
}