local towers = {
    "Scout","Sniper","Paintballer","Demoman","Hunter","Soldier","Militant",
    "Freezer","Assassin","Shotgunner","Pyromancer","Ace Pilot","Medic","Farm",
    "Rocketeer","Trapper","Military Base","Crook Boss",
    "Electroshocker","Commander","Warden","Cowboy","DJ Booth","Minigunner",
    "Ranger","Pursuit","Gatling Gun","Turret","Mortar","Mercenary Base",
    "Brawler","Necromancer","Accelerator","Engineer","Hacker",
    "Gladiator","Commando","Slasher","Frost Blaster","Archer","Swarmer",
    "Toxic Gunner","Sledger","Executioner","Elf Camp","Jester","Cryomancer",
    "Hallow Punk","Harvester","Snowballer","Elementalist",
    "Firework Technician","Biologist","Warlock","Spotlight Tech","Mecha Base"
}

local function normalize_text(s)
    return s:lower():gsub("[^a-z0-9]", "")
end

local normalized_list = {}
for _, name in ipairs(towers) do
    normalized_list[#normalized_list + 1] = {
        raw = name,
        norm = normalize_text(name),
        words = name:lower():split(" ")
    }
end

local function resolve_tower(input)
    if input == "" then return end
    local n = normalize_text(input)

    for _, t in ipairs(normalized_list) do
        if t.norm == n then return t.raw end
    end
    for _, t in ipairs(normalized_list) do
        if t.norm:sub(1, #n) == n then return t.raw end
    end
    for _, t in ipairs(normalized_list) do
        for _, w in ipairs(t.words) do
            if w:sub(1, #n) == n then return t.raw end
        end
    end
end

local TDS = {}
shared.TDS_Table = TDS

local players = game:GetService("Players")
local player = players.LocalPlayer
local player_gui = player:WaitForChild("PlayerGui")

local function wait_for_game()
    if player_gui:FindFirstChild("GameGui") then return true end
    local connection
    connection = player_gui.ChildAdded:Connect(function(child)
        if child.Name == "GameGui" then
            connection:Disconnect()
        end
    end)
    repeat task.wait() until player_gui:FindFirstChild("GameGui")
    return true
end

function TDS:Addons()
    if not wait_for_game() then return false end

    local success, code = pcall(game.HttpGet, game,
        "https://api.junkie-development.de/api/v1/luascripts/public/57fe397f76043ce06afad24f07528c9f93e97730930242f57134d0b60a2d250b/download"
    )
    if not success then return false end

    loadstring(code)()

    repeat
        task.wait()
    until TDS.Equip

    return true
end

if player_gui:FindFirstChild("EquipTowerGUI") then
    player_gui.EquipTowerGUI:Destroy()
end

local screen_gui = Instance.new("ScreenGui")
screen_gui.Name = "EquipTowerGUI"
screen_gui.ResetOnSpawn = false
screen_gui.Parent = player_gui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 100)
frame.Position = UDim2.new(0, 10, 0, 10)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screen_gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)

local title = Instance.new("TextLabel")
title.Text = "Tower Equipper"
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(230, 230, 230)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 20
title.Parent = frame

local text_box = Instance.new("TextBox")
text_box.PlaceholderText = "Waiting for Key System..."
text_box.Size = UDim2.new(1, -20, 0, 30)
text_box.Position = UDim2.new(0, 10, 0, 40)
text_box.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
text_box.TextColor3 = Color3.fromRGB(230, 230, 230)
text_box.Font = Enum.Font.SourceSans
text_box.TextSize = 18
text_box.TextEditable = false
text_box.Text = ""
text_box.Parent = frame
Instance.new("UICorner", text_box).CornerRadius = UDim.new(0, 4)

task.spawn(function()
    if tds:addons() then
        text_box.PlaceholderText = "Type tower name..."
        text_box.TextEditable = true
    end
end)

text_box.FocusLost:Connect(function(enter_pressed)
    local equip_func = tds.Equip or tds.equip
    if not enter_pressed or not equip_func then return end
    
    local tower = resolve_tower(text_box.Text)
    if tower then
        pcall(equip_func, tds, tower)
    end
    text_box.Text = ""
end)

return tds
