local UIS = game:GetService("UserInputService")
local guiParent = gethui and gethui() or game:GetService("CoreGui")

-- Remove existing GUI
local old = guiParent:FindFirstChild("TDSGui")
if old then old:Destroy() end

-- Create main ScreenGui
local TDSGui = Instance.new("ScreenGui")
TDSGui.Name = "TDSGui"
TDSGui.Parent = guiParent
TDSGui.ResetOnSpawn = false
TDSGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Background
local bckpattern = Instance.new("ImageLabel")
bckpattern.Name = "bckpattern"
bckpattern.Parent = TDSGui
bckpattern.Active = true
bckpattern.Draggable = true
bckpattern.Position = UDim2.new(0.25,0,0.2,0)
bckpattern.Size = UDim2.new(0.5,0,0.6,0)
bckpattern.Image = "rbxassetid://118045968280960"
bckpattern.ImageColor3 = Color3.fromRGB(13,13,13)
bckpattern.ScaleType = Enum.ScaleType.Crop
Instance.new("UICorner", bckpattern)
local UIScale = Instance.new("UIScale", bckpattern)
if not UIS.TouchEnabled then UIScale.Scale = 0.8 end

-- Tab
local Tab1 = Instance.new("Frame")
Tab1.Name = "Tab1"
Tab1.Parent = bckpattern
Tab1.BackgroundTransparency = 1
Tab1.Size = UDim2.new(1,0,1,0)

-- Console Frame
local Consoleframe = Instance.new("Frame")
Consoleframe.Name = "Consoleframe"
Consoleframe.Parent = Tab1
Consoleframe.BackgroundColor3 = Color3.fromRGB(21,21,21)
Consoleframe.BorderSizePixel = 0
Consoleframe.Position = UDim2.new(0.045,0,0.17,0)
Consoleframe.Size = UDim2.new(0.91,0,0.78,0)

-- Shadows
local shadowHolder = Instance.new("Frame", Consoleframe)
shadowHolder.AnchorPoint = Vector2.new(0.5,0.5)
shadowHolder.BackgroundTransparency = 1
shadowHolder.Position = UDim2.new(0.5,0,0.5,0)
shadowHolder.Size = UDim2.new(1,0,1,0)

local function createShadow(parent)
	local sh = Instance.new("ImageLabel", parent)
	sh.AnchorPoint = Vector2.new(0.5,0.5)
	sh.BackgroundTransparency = 1
	sh.Position = UDim2.new(0.5,0,0.5,0)
	sh.Size = UDim2.new(1,0,1,0)
	sh.Image = "rbxassetid://1316045217"
	sh.ImageTransparency = 0.88
	sh.ScaleType = Enum.ScaleType.Slice
	sh.SliceCenter = Rect.new(10,10,118,118)
	return sh
end

local umbraShadow = createShadow(shadowHolder)
local penumbraShadow = createShadow(shadowHolder)
local ambientShadow = createShadow(shadowHolder)
ambientShadow.Visible = false

-- Console
local Console = Instance.new("ScrollingFrame")
Console.Name = "Console"
Console.Parent = Consoleframe
Console.BackgroundTransparency = 1
Console.Size = UDim2.new(1,0,1,0)
Console.ScrollBarThickness = 1
Console.Active = true

local UIListLayout = Instance.new("UIListLayout", Console)
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- Title
local TextLabel = Instance.new("TextLabel")
TextLabel.Parent = Tab1
TextLabel.BackgroundTransparency = 1
TextLabel.Position = UDim2.new(0.5,0,0.03,0)
TextLabel.AnchorPoint = Vector2.new(0.5,0)
TextLabel.Size = UDim2.new(0.6,0,0.11,0)
TextLabel.Font = Enum.Font.SourceSansSemibold
TextLabel.Text = "Pure Strategy"
TextLabel.TextColor3 = Color3.new(1,1,1)
TextLabel.TextScaled = true

-- Toggle Button
local ToggleButton = Instance.new("TextButton")
ToggleButton.Parent = TDSGui
ToggleButton.Size = UDim2.new(0,110,0,32)
ToggleButton.Position = UDim2.new(0,10,1,-42)
ToggleButton.Text = "Toggle GUI"
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 14
ToggleButton.TextColor3 = Color3.new(1,1,1)
ToggleButton.BackgroundColor3 = Color3.fromRGB(50,150,255)
Instance.new("UICorner", ToggleButton)

local guiVisible = true
local function toggleGUI()
	guiVisible = not guiVisible
	bckpattern.Visible = guiVisible
end

ToggleButton.MouseButton1Click:Connect(toggleGUI)
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.LeftAlt then
		toggleGUI()
	end
end)

-- Shared reference
shared.AutoStratGUI = {
	Console = Console,
	bckpattern = bckpattern
}