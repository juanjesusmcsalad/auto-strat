if not game:IsLoaded() then game.Loaded:Wait() end

local function identify_game_state()
    local players = game:GetService("Players")
    local temp_player = players.LocalPlayer or players.PlayerAdded:Wait()
    local temp_gui = temp_player:WaitForChild("PlayerGui")
    
    while true do
        if temp_gui:FindFirstChild("LobbyGui") then
            return "LOBBY"
        elseif temp_gui:FindFirstChild("GameGui") then
            return "GAME"
        end
        task.wait(1)
    end
end

local game_state = identify_game_state()

local send_request = request or http_request or httprequest
    or GetDevice and GetDevice().request

if not send_request then 
    warn("failure: no http function") 
    return 
end

-- // services & main refs
local teleport_service = game:GetService("TeleportService")
local marketplace_service = game:GetService("MarketplaceService")
local replicated_storage = game:GetService("ReplicatedStorage")
local http_service = game:GetService("HttpService")
local remote_func = replicated_storage:WaitForChild("RemoteFunction")
local remote_event = replicated_storage:WaitForChild("RemoteEvent")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer or players_service.PlayerAdded:Wait()
local player_gui = local_player:WaitForChild("PlayerGui")

local back_to_lobby_running = false
local auto_pickups_running = false
local auto_skip_running = false
local auto_claim_rewards = false
local anti_lag_running = false
local auto_chain_running = false
local auto_dj_running = false
local auto_merc_mili_running = false
local sell_farms_running = false

local max_path_distance = 300 -- default
local mil_marker = nil
local merc_marker = nil

_G.record_strat = false
local spawned_towers = {}
local tower_count = 0

-- // icon item ids ill add more soon arghh
local ItemNames = {
    ["17447507910"] = "Timescale Ticket(s)",
    ["17438486690"] = "Range Flag(s)",
    ["17438486138"] = "Damage Flag(s)",
    ["17438487774"] = "Cooldown Flag(s)",
    ["17429537022"] = "Blizzard(s)",
    ["17448596749"] = "Napalm Strike(s)",
    ["18493073533"] = "Spin Ticket(s)",
    ["17429548305"] = "Supply Drop(s)",
    ["18443277308"] = "Low Grade Consumable Crate(s)",
    ["136180382135048"] = "Santa Radio(s)",
    ["18443277106"] = "Mid Grade Consumable Crate(s)",
    ["18443277591"] = "High Grade Consumable Crate(s)",
    ["132155797622156"] = "Christmas Tree(s)",
    ["124065875200929"] = "Fruit Cake(s)",
    ["17429541513"] = "Barricade(s)",
    ["110415073436604"] = "Holy Hand Grenade(s)",
    ["139414922355803"] = "Present Clusters(s)"
}

-- // tower management core
local TDS = {
    placed_towers = {},
    active_strat = true,
    matchmaking_map = {
        ["Hardcore"] = "hardcore",
        ["Pizza Party"] = "halloween",
        ["Badlands"] = "badlands",
        ["Polluted"] = "polluted"
    }
}

local upgrade_history = {}

-- // shared for addons
shared.TDS_Table = TDS

-- // for calculating path
local function find_path()
    local map_folder = workspace:FindFirstChild("Map")
    if not map_folder then return nil end
    local paths_folder = map_folder:FindFirstChild("Paths")
    if not paths_folder then return nil end
    local path_folder = paths_folder:GetChildren()[1]
    if not path_folder then return nil end
    
    local path_nodes = {}
    for _, node in ipairs(path_folder:GetChildren()) do
        if node:IsA("BasePart") then
            table.insert(path_nodes, node)
        end
    end
    
    table.sort(path_nodes, function(a, b)
        local num_a = tonumber(a.Name:match("%d+"))
        local num_b = tonumber(b.Name:match("%d+"))
        if num_a and num_b then return num_a < num_b end
        return a.Name < b.Name
    end)
    
    return path_nodes
end

local function total_length(path_nodes)
    local total_length = 0
    for i = 1, #path_nodes - 1 do
        total_length = total_length + (path_nodes[i + 1].Position - path_nodes[i].Position).Magnitude
    end
    return total_length
end

local function calc_length()
    if game_state == "GAME" then
        local path_nodes = nil
        while not path_nodes do
            task.wait()
            path_nodes = find_path()
            if path_nodes and #path_nodes > 0 then
                max_path_distance = total_length(path_nodes)
                break
            end
        end
    end
end

local function get_point_at_distance(path_nodes, distance)
    if not path_nodes or #path_nodes < 2 then return nil end
    
    local current_dist = 0
    for i = 1, #path_nodes - 1 do
        local start_pos = path_nodes[i].Position
        local end_pos = path_nodes[i+1].Position
        local segment_len = (end_pos - start_pos).Magnitude
        
        if current_dist + segment_len >= distance then
            local remaining = distance - current_dist
            local direction = (end_pos - start_pos).Unit
            return start_pos + (direction * remaining)
        end
        current_dist = current_dist + segment_len
    end
    return path_nodes[#path_nodes].Position
end

local function update_path_visuals()
    if not _G.PathVisuals then
        if mil_marker then 
            mil_marker:Destroy() 
            mil_marker = nil 
        end
        if merc_marker then 
            merc_marker:Destroy() 
            merc_marker = nil 
        end
        return
    end

    local path_nodes = find_path()
    if not path_nodes then return end

    if not mil_marker then
        mil_marker = Instance.new("Part")
        mil_marker.Name = "MilVisual"
        mil_marker.Shape = Enum.PartType.Cylinder
        mil_marker.Size = Vector3.new(0.3, 3, 3)
        mil_marker.Color = Color3.fromRGB(0, 255, 0)
        mil_marker.Material = Enum.Material.Plastic
        mil_marker.Anchored = true
        mil_marker.CanCollide = false
        mil_marker.Orientation = Vector3.new(0, 0, 90)
        mil_marker.Parent = workspace
    end

    if not merc_marker then
        merc_marker = mil_marker:Clone()
        merc_marker.Name = "MercVisual"
        merc_marker.Color = Color3.fromRGB(255, 0, 0)
        merc_marker.Parent = workspace
    end

    local mil_pos = get_point_at_distance(path_nodes, _G.MilitaryPath or 0)
    local merc_pos = get_point_at_distance(path_nodes, _G.MercenaryPath or 0)

    if mil_pos then
        mil_marker.Position = mil_pos + Vector3.new(0, 0.2, 0)
        mil_marker.Transparency = 0.7
    end
    if merc_pos then
        merc_marker.Position = merc_pos + Vector3.new(0, 0.2, 0)
        merc_marker.Transparency = 0.7
    end
end

local function record_action(command_str)
    if not _G.record_strat then return end
    if appendfile then
        appendfile("Strat.txt", command_str .. "\n")
    end
end

function TDS:Addons()
    local url = "https://api.junkie-development.de/api/v1/luascripts/public/57fe397f76043ce06afad24f07528c9f93e97730930242f57134d0b60a2d250b/download"
    local success, code = pcall(game.HttpGet, game, url)

    if not success then
        return false
    end

    loadstring(code)()

    while not (TDS.MultiMode and TDS.Multiplayer) do
        task.wait(0.1)
    end

    local original_equip = TDS.Equip
    TDS.Equip = function(...)
        if game_state == "GAME" then
            return original_equip(...)
        end
    end

    return true
end

-- // ui
local UI = (loadstring(Game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Sources/UI.lua")))();
if UI:LoadAnimation() then UI:StartLoad(); end;
if UI:LoadAnimation() then UI:Loaded(); end;

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Remote = ReplicatedStorage:WaitForChild("RemoteFunction")

local stack_enabled = false
local selected_tower = nil
local stack_sphere = nil

local function get_towers()
    local names = {}
    local success, result = pcall(function()
        return Remote:InvokeServer("Session", "Search", "Inventory.Troops")
    end)
    if success and result then
        for i, v in next, result do
            if v.Equipped then table.insert(names, i) end
        end
    end
    return names
end

local equipped_towers = get_towers()

local Window = UI:Window({
	SubTitle = "AFK Defense Simulator",
	Size = game:GetService("UserInputService").TouchEnabled and UDim2.new(0, 380, 0, 260) or UDim2.new(0, 500, 0, 320),
	TabWidth = 140
})
local Main = Window:Tab("Main", "rbxassetid://10723407389");
local Logger = Window:Tab("Logger", "rbxassetid://10723415335");
local Recorder = Window:Tab("Recorder", "rbxassetid://71694182730051");
local Strats = Window:Tab("Strategies", "rbxassetid://90865936209687");
local Misc = Window:Tab("Misc", "rbxassetid://10709782497");
local Settings = Window:Tab("Settings", "rbxassetid://10734950309");

Main:Seperator("Main");

Main:Dropdown("Tower:", equipped_towers, nil, function(selected)
    selected_tower = selected
end)

Main:Line()

Main:Toggle("Stack Tower", UI:Get("StackTower", false), "Enables Stacking placement", function(state)
    stack_enabled = state 
end)

Main:Button("Upgrade Selected", function()
	if selected_tower then
        for _, v in pairs(workspace.Towers:GetChildren()) do
            if v:FindFirstChild("TowerReplicator") and v.TowerReplicator:GetAttribute("Name") == selected_tower and v.TowerReplicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                Remote:InvokeServer("Troops", "Upgrade", "Set", {Troop = v})
            end
        end
    end
	UI:Notify("Attempted to upgrade all the selected towers!", 3);
end)

Main:Button("Sell Selected", function()
    if selected_tower then
        for _, v in pairs(workspace.Towers:GetChildren()) do
            if v:FindFirstChild("TowerReplicator") and v.TowerReplicator:GetAttribute("Name") == selected_tower and v.TowerReplicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                Remote:InvokeServer("Troops", "Sell", {Troop = v})
            end
        end
    end
	UI:Notify("Attempted to sell all the selected towers!", 3);
end)

Main:Button("Upgrade All", function()
    for _, v in pairs(workspace.Towers:GetChildren()) do
        if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer.UserId then
            Remote:InvokeServer("Troops", "Upgrade", "Set", {Troop = v})
        end
    end
	UI:Notify("Attempted to upgrade all the towers!", 3);
end)

Main:Button("Sell All", function()
    for _, v in pairs(workspace.Towers:GetChildren()) do
        if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer.UserId then
            Remote:InvokeServer("Troops", "Sell", {Troop = v})
        end
    end
	UI:Notify("Attempted to sell all the towers!", 3);
end)

Main:Seperator("Equipper");
Main:Textbox("Equip:", true, function(value)
    if value == "" or value == nil then return end

    task.spawn(function()
        if not TDS.Equip then
            UI:Notify("Waiting for Key System to finish...", 2)
            repeat 
                task.wait(0.5) 
            until TDS.Equip
        end
        
        local success, err = pcall(function()
            TDS:Equip(tostring(value))
        end)

        if success then
            UI:Notify("Successfully equipped: " .. tostring(value), 3)
        end
    end)
end)

Main:Button("Unlock Equipper", function()
    task.spawn(function()
        UI:Notify("Loading Key System...", 3)
        local success = TDS:Addons()
        
        if success then
            UI:Notify("Addons Loaded! You can now equip towers.", 3)
        end
    end)
end)

RunService.RenderStepped:Connect(function()
    if stack_enabled then
        if not stack_sphere then
            stack_sphere = Instance.new("Part")
            stack_sphere.Shape = Enum.PartType.Ball
            stack_sphere.Size = Vector3.new(1.5, 1.5, 1.5)
            stack_sphere.Color = Color3.fromRGB(0, 255, 0)
            stack_sphere.Transparency = 0.5
            stack_sphere.Anchored = true
            stack_sphere.CanCollide = false
            stack_sphere.Material = Enum.Material.Neon
            stack_sphere.Parent = workspace
            Mouse.TargetFilter = stack_sphere
        end
        local hit = Mouse.Hit
        if hit then stack_sphere.Position = hit.Position end
    elseif stack_sphere then
        stack_sphere:Destroy()
        stack_sphere = nil
    end

    update_path_visuals()
end)

Mouse.Button1Down:Connect(function()
    if stack_enabled and stack_sphere and selected_tower then
        local pos = stack_sphere.Position
        local newpos = Vector3.new(pos.X, pos.Y + 25, pos.Z)
        Remote:InvokeServer("Troops", "Pl\208\176ce", {Rotation = CFrame.new(), Position = newpos}, selected_tower)
    end
end)

Main:Seperator("Quality of life");
Main:Toggle("Auto Skip Waves", UI:Get("AutoSkip", false), "Skips all waves", function(state)
    UI:Set("AutoSkip", state)
    _G.AutoSkip = state
end)

Main:Toggle("Auto Chain", UI:Get("AutoChain", false), "Chains Commander Ability", function(state)
    UI:Set("AutoChain", state)
    _G.AutoChain = state
end)

Main:Toggle("Auto DJ Booth", UI:Get("AutoDJ", false), "Uses DJ Booth Ability", function(state)
    UI:Set("AutoDJ", state)
    _G.AutoDJ = state
end)

Main:Toggle("Auto Rejoin Lobby", UI:Get("AutoRejoin", true), "Teleports back to lobby after you've won immediately", function(state)
    UI:Set("AutoRejoin", state)
    _G.AutoRejoin = state
end)

Main:Seperator("Farm");
Main:Toggle("Sell Farms", UI:Get("SellFarms", false), "Toggle with desc", function(state)
    UI:Set("SellFarms", state)
    _G.SellFarms = state
end)

Main:Textbox("Wave:", true, function(value)
    UI:Set("SellFarmsWave", value)
    _G.SellFarmsWave = tonumber(value) or 40
end, UI:Get("SellFarmsWave", "40"))

Main:Seperator("Abilities");
Main:Toggle("Auto Mercenary Base", UI:Get("AutoMercenary", false), "Uses Air-Drop Ability", function(state)
    UI:Set("AutoMercenary", state)
    _G.AutoMercenary = state
end)

Main:Slider("Path Distance", 0, max_path_distance, UI:Get("MercenaryPath", 25), function(value)
    UI:Set("MercenaryPath", value)
    _G.MercenaryPath = value
end)

Main:Toggle("Auto Military Base", UI:Get("AutoMilitary", false), "Uses Airstrike Ability", function(state)
    UI:Set("AutoMilitary", state)
    _G.AutoMilitary = state
end)

Main:Slider("Path Distance", 0, max_path_distance, UI:Get("MilitaryPath", 25), function(value)
    UI:Set("MilitaryPath", value)
    _G.MilitaryPath = value
end)

Main:Toggle("Auto Medic", UI:Get("AutoMedic", false), "Uses Ubercharge Ability", function(state)
    UI:Set("AutoMedic", state)
    _G.AutoMedic = state
end)

Logger:Box("STRATEGY LOGGER:", UDim2.new(1, 0, 0, 270))

Recorder:Box("RECORDER:", UDim2.new(1, 0, 0, 190))
Recorder:Button("START", function()
    Recorder:Clear()
    Recorder:Log("Recorder started")

    local current_mode = "Unknown"
    local current_map = "Unknown"
    
    local state_folder = replicated_storage:FindFirstChild("State")
    if state_folder then
        current_mode = state_folder.Difficulty.Value
        current_map = state_folder.Map.Value
    end

    local tower1, tower2, tower3, tower4, tower5 = "None", "None", "None", "None", "None"
    local current_modifiers = "" 
    local state_replicators = replicated_storage:FindFirstChild("StateReplicators")

    if state_replicators then
        for _, folder in ipairs(state_replicators:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == local_player.UserId then
                local equipped = folder:GetAttribute("EquippedTowers")
                if type(equipped) == "string" then
                    local cleaned_json = equipped:match("%[.*%]") 
                    
                    local success, tower_table = pcall(function()
                        return http_service:JSONDecode(cleaned_json)
                    end)

                    if success and type(tower_table) == "table" then
                        tower1 = tower_table[1] or "None"
                        tower2 = tower_table[2] or "None"
                        tower3 = tower_table[3] or "None"
                        tower4 = tower_table[4] or "None"
                        tower5 = tower_table[5] or "None"
                    end
                end
            end

            if folder.Name == "ModifierReplicator" then
                local raw_votes = folder:GetAttribute("Votes")
                if type(raw_votes) == "string" then
                    local cleaned_json = raw_votes:match("{.*}") 
                    
                    local success, mod_table = pcall(function()
                        return http_service:JSONDecode(cleaned_json)
                    end)

                    if success and type(mod_table) == "table" then
                        local mods = {}
                        for mod_name, _ in pairs(mod_table) do
                            table.insert(mods, mod_name .. " = true")
                        end
                        current_modifiers = table.concat(mods, ", ")
                    end
                end
            end
        end
    end

    Recorder:Log("Mode: " .. current_mode)
    Recorder:Log("Map: " .. current_map)
    Recorder:Log("Towers: " .. tower1 .. ", " .. tower2)
    Recorder:Log(tower3 .. ", " .. tower4 .. ", " .. tower5)

    _G.record_strat = true

        if writefile then 
        local config_header = string.format([[
local TDS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()

TDS:Loadout("%s", "%s", "%s", "%s", "%s")
TDS:Mode("%s")
TDS:GameInfo("%s", {%s})

]], tower1, tower2, tower3, tower4, tower5, current_mode, current_map, current_modifiers)

        writefile("Strat.txt", config_header)
    end

    UI:Notify("Recorder has started, you may place down your towers now.", 3);
end)
Recorder:Button("STOP", function()
    Recorder:Clear()
    Recorder:Log("Strategy saved, you may find it in your workspace\nfolder called 'Strat.txt'")
    UI:Notify("Recording has been saved!", 3);
end)

if game_state == "GAME" then
    local towers_folder = workspace:WaitForChild("Towers", 5)

    towers_folder.ChildAdded:Connect(function(tower)
        if not _G.record_strat then return end
        
        local replicator = tower:WaitForChild("TowerReplicator", 5)
        if not replicator then return end

        local owner_id = replicator:GetAttribute("OwnerId")
        if owner_id and owner_id ~= local_player.UserId then return end

        tower_count = tower_count + 1
        local my_index = tower_count
        spawned_towers[tower] = my_index

        local tower_name = replicator:GetAttribute("Name") or tower.Name
        local raw_pos = replicator:GetAttribute("Position")
        
        local pos_x, pos_y, pos_z
        if typeof(raw_pos) == "Vector3" then
            pos_x, pos_y, pos_z = raw_pos.X, raw_pos.Y, raw_pos.Z
        else
            local p = tower:GetPivot().Position
            pos_x, pos_y, pos_z = p.X, p.Y, p.Z
        end
        
        local command = string.format('TDS:Place("%s", %.3f, %.3f, %.3f)', tower_name, pos_x, pos_y, pos_z)
        record_action(command)
        Recorder:Log("Placed " .. tower_name .. " (Index: " .. my_index .. ")")

        replicator:GetAttributeChangedSignal("Upgrade"):Connect(function()
            if not _G.record_strat then return end
            record_action(string.format('TDS:Upgrade(%d)', my_index))
            Recorder:Log("Upgraded Tower " .. my_index)
        end)
    end)

    towers_folder.ChildRemoved:Connect(function(tower)
        if not _G.record_strat then return end
        
        local my_index = spawned_towers[tower]
        if my_index then
            record_action(string.format('TDS:Sell(%d)', my_index))
            Recorder:Log("Sold Tower " .. my_index)
            
            spawned_towers[tower] = nil
        end
    end)
end

Strats:Seperator("Survival Strategies:");
Strats:Label("Once you toggle a Strategy, please go to the Logger\nSection for information!")
Strats:Toggle("Frost Mode", UI:Get("FrostMode", false), nil, function(state)
    UI:Set("FrostMode", state)
    _G.FrostMode = state
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")

        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Frost.lua"
        local content = game:HttpGet(url)
        writefile("FrostMode.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Toggle("Fallen Mode", UI:Get("FallenMode", false), nil, function(state)
    UI:Set("FallenMode", state)
    _G.FallenMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Fallen Mode")
        Logger:Log("Towers: Farm, Brawler, Mercenary Base,")
        Logger:Log("Electroshocker, Engineer")

        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Fallen.lua"
        local content = game:HttpGet(url)
        writefile("FallenMode.lua", content)
        
        loadstring(content)()
    end
end)
--[[
Strats:Toggle("Molten Mode", UI:Get("MoltenMode", false), nil, function(state)
    UI:Set("MoltenMode", state)
    _G.MoltenMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")

        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Molten.lua"
        local content = game:HttpGet(url)
        writefile("MoltenMode.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Toggle("Intermediate Mode", UI:Get("IntermediateMode", false), nil, function(state)
    UI:Set("IntermediateMode", state)
    _G.IntermediateMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")
        
        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Intermediate.lua"
        local content = game:HttpGet(url)
        writefile("IntermediateMode.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Toggle("Easy Mode", UI:Get("EasyMode", false), nil, function(state)
    UI:Set("EasyMode", state)
    _G.EasyMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")
        
        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Easy.lua"
        local content = game:HttpGet(url)
        writefile("EasyMode.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Seperator("Special Modes")
Strats:Toggle("Badlands II", UI:Get("EasyMode", false), nil, function(state)
    UI:Set("EasyMode", state)
    _G.EasyMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")
        
        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/BadlandsII.lua"
        local content = game:HttpGet(url)
        writefile("BadlandsII.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Toggle("Polluted Wastelands", UI:Get("EasyMode", false), nil, function(state)
    UI:Set("PollutedWastelands", state)
    _G.EasyMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")
        
        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/PollutedWastelands.lua"
        local content = game:HttpGet(url)
        writefile("PollutedWastelands.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Toggle("Pizza Party", UI:Get("EasyMode", false), nil, function(state)
    UI:Set("PizzaParty", state)
    _G.EasyMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Frost Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")
        
        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/PizzaParty.lua"
        local content = game:HttpGet(url)
        writefile("PizzaParty.lua", content)
        
        loadstring(content)()
    end
end)
Strats:Toggle("Hardcore", UI:Get("Hardcore", false), nil, function(state)
    UI:Set("Hardcore", state)
    _G.EasyMode = state
    
    if state then
        UI:Notify("Go to the Logger Section to see the towers needed!", 5)
        Logger:Clear()
        Logger:Log("Hardcore Mode")
        Logger:Log("Skill Tree: MAX (Optional)")
        Logger:Log("Towers: Golden Scout, Firework Technician, Hacker,")
        Logger:Log("Brawler, DJ Booth, Commander, Engineer, Accelerator,")
        Logger:Log("Turret, Mercenary Base")
        
        local url = "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Hardcore.lua"
        local content = game:HttpGet(url)
        writefile("Hardcore.lua", content)
        
        loadstring(content)()
    end
end)
]]

Misc:Seperator("Visuals");
Misc:Toggle("Enable Anti-Lag", UI:Get("AntiLag", false), "Boosts your FPS", function(state)
    UI:Set("AntiLag", state)
    _G.AntiLag = state
end)

Misc:Toggle("Enable Path Distance Marker", UI:Get("AutoPickups", false), "Red = Mercenary Base, Green = Military Base", function(state)
    UI:Set("PathVisuals", state)
    _G.PathVisuals = state
end)

Misc:Toggle("Auto Collect Pickups", UI:Get("AutoPickups", false), "Collects Logbooks + Snowballs", function(state)
    UI:Set("AutoPickups", state)
    _G.AutoPickups = state
end)

Misc:Toggle("Claim Rewards", UI:Get("ClaimRewards", false), "Claims your playtime and uses spin tickets in Lobby", function(state)
    UI:Set("ClaimRewards", state)
    _G.ClaimRewards = state
end)

Misc:Seperator("Webhook");
Misc:Toggle("Send Webhook", UI:Get("SendWebhook", false), nil, function(state)
    UI:Set("SendWebhook", state)
    _G.SendWebhook = state
end)

Misc:Textbox("Webhook URL:", true, function(value)
    if value == "" or not value:find("https://") then
        UI:Notify("Invalid Webhook URL!", 3);
    else
        UI:Notify("Webhook is successfully set!", 3);
        UI:Set("WebhookURL", value)
        _G.WebhookURL = value
    end
end, UI:Get("WebhookURL", ""))

Settings:Button("Save Settings", function()
    getgenv().SaveConfig()
    UI:Notify("Saved your current settings!", 3);
end)

Settings:Button("Load Settings", function()
    getgenv().LoadConfig()
    UI:Notify("Loaded your settings from file!", 3);
end)

Settings:Button("Discord Server", function()
    setclipboard("https://discord.gg/autostrat")
    UI:Notify("Copied to your clipboard!", 3);
end)

-- // currency tracking
local start_coins, current_total_coins, start_gems, current_total_gems = 0, 0, 0, 0
if game_state == "GAME" then
    pcall(function()
        repeat task.wait(1) until local_player:FindFirstChild("Coins")
        start_coins = local_player.Coins.Value
        current_total_coins = start_coins
        start_gems = local_player.Gems.Value
        current_total_gems = start_gems
    end)
end

-- // check if remote returned valid
local function check_res_ok(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end

    local success, is_model = pcall(function()
        return data and data:IsA("Model")
    end)
    
    if success and is_model then return true end
    if type(data) == "userdata" then return true end

    return false
end

-- // scrap ui for match data
local function get_all_rewards()
    local results = {
        Coins = 0, 
        Gems = 0, 
        XP = 0, 
        Wave = 0,
        Level = 0,
        Time = "00:00",
        Status = "UNKNOWN",
        Others = {} 
    }
    
    local ui_root = player_gui:FindFirstChild("ReactGameNewRewards")
    local main_frame = ui_root and ui_root:FindFirstChild("Frame")
    local game_over = main_frame and main_frame:FindFirstChild("gameOver")
    local rewards_screen = game_over and game_over:FindFirstChild("RewardsScreen")
    
    local game_stats = rewards_screen and rewards_screen:FindFirstChild("gameStats")
    local stats_list = game_stats and game_stats:FindFirstChild("stats")
    
    if stats_list then
        for _, frame in ipairs(stats_list:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            if l1 and l2 and l1.Text:find("Time Completed:") then
                results.Time = l2.Text
                break
            end
        end
    end

    local top_banner = rewards_screen and rewards_screen:FindFirstChild("RewardBanner")
    if top_banner and top_banner:FindFirstChild("textLabel") then
        local txt = top_banner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end

    local level_value = local_player.Level
    if level_value then
        results.Level = level_value.Value or 0
    end

    local label = player_gui:WaitForChild("ReactGameTopGameDisplay").Frame.wave.container.value
    local wave_num = label.Text:match("^(%d+)")

    if wave_num then
        results.Wave = tonumber(wave_num) or 0
    end

    local section_rewards = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
    if section_rewards then
        for _, item in ipairs(section_rewards:GetChildren()) do
            if tonumber(item.Name) then 
                local icon_id = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then icon_id = img.Image:match("%d+") or "0" end

                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0
                        
                        if text:find("Coins") then
                            results.Coins = amt
                        elseif text:find("Gems") then
                            results.Gems = amt
                        elseif text:find("XP") then
                            results.XP = amt
                        elseif text:lower():find("x%d+") then 
                            local displayName = ItemNames[icon_id] or "Unknown Item (" .. icon_id .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end
    
    return results
end

-- // lobby / teleporting
local function send_to_lobby()
    task.wait(1)
    local lobby_remote = game.ReplicatedStorage.Network.Teleport["RE:backToLobby"]
    lobby_remote:FireServer()
end

local function handle_post_match()
    local ui_root
    repeat
        task.wait(1)

        local root = player_gui:FindFirstChild("ReactGameNewRewards")
        local frame = root and root:FindFirstChild("Frame")
        local gameOver = frame and frame:FindFirstChild("gameOver")
        local rewards_screen = gameOver and gameOver:FindFirstChild("RewardsScreen")
        ui_root = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
    until ui_root

    if not ui_root then return send_to_lobby() end
    if not _G.AutoRejoin then return end

    if not _G.SendWebhook then
        send_to_lobby()
        return
    end

    local match = get_all_rewards()

    current_total_coins += match.Coins
    current_total_gems += match.Gems

    local bonus_string = ""
    if #match.Others > 0 then
        for _, res in ipairs(match.Others) do
            bonus_string = bonus_string .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n"
        end
    else
        bonus_string = "_No bonus rewards found._"
    end

    local post_data = {
        username = "TDS AutoStrat",
        embeds = {{
            title = (match.Status == "WIN" and "🏆 TRIUMPH" or "💀 DEFEAT"),
            color = (match.Status == "WIN" and 0x2ecc71 or 0xe74c3c),
            description =
                "### 📋 Match Overview\n" ..
                "> **Status:** `" .. match.Status .. "`\n" ..
                "> **Time:** `" .. match.Time .. "`\n" ..
                "> **Current Level:** `" .. match.Level .. "`\n" ..
                "> **Wave:** `" .. match.Wave .. "`\n",
                
            fields = {
                {
                    name = "✨ Rewards",
                    value = "```ansi\n" ..
                            "[2;33mCoins:[0m +" .. match.Coins .. "\n" ..
                            "[2;34mGems: [0m +" .. match.Gems .. "\n" ..
                            "[2;32mXP:   [0m +" .. match.XP .. "```",
                    inline = false
                },
                {
                    name = "🎁 Bonus Items",
                    value = bonus_string,
                    inline = true
                },
                {
                    name = "📊 Session Totals",
                    value = "```py\n# Total Amount\nCoins: " .. current_total_coins .. "\nGems:  " .. current_total_gems .. "```",
                    inline = true
                }
            },
            footer = { text = "Logged for " .. local_player.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        send_request({
            Url = _G.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(post_data)
        })
    end)

    task.wait(1.5)

    send_to_lobby()
end

local function log_match_start()
    if not _G.SendWebhook then return end
    if type(_G.WebhookURL) ~= "string" or _G.WebhookURL == "" then return end
    if _G.WebhookURL:find("YOUR%-WEBHOOK") then return end
    
    local start_payload = {
        username = "TDS AutoStrat",
        embeds = {{
            title = "🚀 **Match Started Successfully**",
            description = "The AutoStrat has successfully loaded into a new game session and is beginning execution.",
            color = 3447003,
            fields = {
                {
                    name = "🪙 Starting Coins",
                    value = "```" .. tostring(start_coins) .. " Coins```",
                    inline = true
                },
                {
                    name = "💎 Starting Gems",
                    value = "```" .. tostring(start_gems) .. " Gems```",
                    inline = true
                },
                {
                    name = "Status",
                    value = "🟢 Running Script",
                    inline = false
                }
            },
            footer = { text = "Logged for " .. local_player.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        send_request({
            Url = _G.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(start_payload)
        })
    end)
end

-- // voting & map selection
local function run_vote_skip()
    while true do
        local success = pcall(function()
            remote_func:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.2)
    end
end

local function match_ready_up()
    local player_gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    
    local ui_overrides = player_gui:WaitForChild("ReactOverridesVote", 30)
    local main_frame = ui_overrides and ui_overrides:WaitForChild("Frame", 30)
    
    if not main_frame then
        return
    end

    local vote_ready = nil

    while not vote_ready do
        local vote_node = main_frame:FindFirstChild("votes")
        
        if vote_node then
            local container = vote_node:FindFirstChild("container")
            if container then
                local ready = container:FindFirstChild("ready")
                if ready then
                    vote_ready = ready
                end
            end
        end
        
        if not vote_ready then
            task.wait(0.5) 
        end
    end

    repeat task.wait(0.1) until vote_ready.Visible == true

    run_vote_skip()
    log_match_start()
end

local function cast_map_vote(map_id, pos_vec)
    local target_map = map_id or "Simplicity"
    local target_pos = pos_vec or Vector3.new(0,0,0)
    remote_event:FireServer("LobbyVoting", "Vote", target_map, target_pos)
    Logger:Log("Cast map vote: " .. target_map)
end

local function lobby_ready_up()
    pcall(function()
        remote_event:FireServer("LobbyVoting", "Ready")
        Logger:Log("Lobby ready up sent")
    end)
end

local function select_map_override(map_id, ...)
    local args = {...}

    if args[#args] == "vip" then
        remote_func:InvokeServer("LobbyVoting", "Override", map_id)
    end

    task.wait(3)
    cast_map_vote(map_id, Vector3.new(12.59, 10.64, 52.01))
    task.wait(1)
    lobby_ready_up()
    match_ready_up()
end

local function cast_modifier_vote(mods_table)
    local bulk_modifiers = replicated_storage:WaitForChild("Network"):WaitForChild("Modifiers"):WaitForChild("RF:BulkVoteModifiers")
    local selected_mods = mods_table or {
        HiddenEnemies = true, Glass = true, ExplodingEnemies = true,
        Limitation = true, Committed = true, HealthyEnemies = true,
        SpeedyEnemies = true, Quarantine = true, Fog = true,
        FlyingEnemies = true, Broke = true, Jailed = true, Inflation = true
    }

    pcall(function()
        bulk_modifiers:InvokeServer(selected_mods)
    end)
end

local function is_map_available(name)
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    repeat
        remote_event:FireServer("LobbyVoting", "Veto")
        wait(1)

        local found = false
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and t.Text == name then
                    found = true
                    break
                end
            end
        end

        local total_player = #players_service:GetChildren()
        local veto_text = player_gui:WaitForChild("ReactGameIntermission"):WaitForChild("Frame"):WaitForChild("buttons"):WaitForChild("veto"):WaitForChild("value").Text
        
    until found or veto_text == "Veto ("..total_player.."/"..total_player..")"

    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    return false
end

-- // timescale logic
local function set_game_timescale(target_val)
    local speed_list = {0, 0.5, 1, 1.5, 2}

    local target_idx
    for i, v in ipairs(speed_list) do
        if v == target_val then
            target_idx = i
            break
        end
    end
    if not target_idx then return end

    local speed_label = game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Speed

    local current_val = tonumber(speed_label.Text:match("x([%d%.]+)"))
    if not current_val then return end

    local current_idx
    for i, v in ipairs(speed_list) do
        if v == current_val then
            current_idx = i
            break
        end
    end
    if not current_idx then return end

    local diff = target_idx - current_idx
    if diff < 0 then
        diff = #speed_list + diff
    end

    for _ = 1, diff do
        replicated_storage.RemoteFunction:InvokeServer(
            "TicketsManager",
            "CycleTimeScale"
        )
        task.wait(0.5)
    end
end

local function unlock_speed_tickets()
    if local_player.TimescaleTickets.Value >= 1 then
        if game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Lock.Visible then
            replicated_storage.RemoteFunction:InvokeServer('TicketsManager', 'UnlockTimeScale')
            Logger:Log("Unlocked timescale tickets")
        end
    else
        Logger:Log("No timescale tickets left")
    end
end

-- // ingame control
local function trigger_restart()
    local ui_root = player_gui:WaitForChild("ReactGameNewRewards")
    local found_section = false

    repeat
        task.wait(0.3)
        local f = ui_root:FindFirstChild("Frame")
        local g = f and f:FindFirstChild("gameOver")
        local s = g and g:FindFirstChild("RewardsScreen")
        if s and s:FindFirstChild("RewardsSection") then
            found_section = true
        end
    until found_section

    task.wait(3)
    run_vote_skip()
end

local function get_current_wave()
    local label = game:GetService("Players").LocalPlayer.PlayerGui
        .ReactGameTopGameDisplay.Frame.wave.container.value

    local text = label.Text
    local wave_num = text:match("(%d+)")

    return tonumber(wave_num) or 0
end

local function do_place_tower(t_name, t_pos)
    Logger:Log("Placing tower: " .. t_name)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Pl\208\176ce", {
                Rotation = CFrame.new(),
                Position = t_pos
            }, t_name)
        end)

        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_upgrade_tower(t_obj, path_id)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Upgrade", "Set", {
                Troop = t_obj,
                Path = path_id
            })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_sell_tower(t_obj)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Sell", { Troop = t_obj })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_set_option(t_obj, opt_name, opt_val, req_wave)
    if req_wave then
        repeat task.wait(0.3) until get_current_wave() >= req_wave
    end

    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Option", "Set", {
                Troop = t_obj,
                Name = opt_name,
                Value = opt_val
            })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_activate_ability(t_obj, ab_name, ab_data, is_looping)
    if type(ab_data) == "boolean" then
        is_looping = ab_data
        ab_data = nil
    end

    ab_data = type(ab_data) == "table" and ab_data or nil

    local positions
    if ab_data and type(ab_data.towerPosition) == "table" then
        positions = ab_data.towerPosition
    end

    local clone_idx = ab_data and ab_data.towerToClone
    local target_idx = ab_data and ab_data.towerTarget

    local function attempt()
        while true do
            local ok, res = pcall(function()
                local data

                if ab_data then
                    data = table.clone(ab_data)

                    if positions and #positions > 0 then
                        data.towerPosition = positions[math.random(#positions)]
                    end

                    if type(clone_idx) == "number" then
                        data.towerToClone = TDS.placed_towers[clone_idx]
                    end

                    if type(target_idx) == "number" then
                        data.towerTarget = TDS.placed_towers[target_idx]
                    end
                end

                return remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    {
                        Troop = t_obj,
                        Name = ab_name,
                        Data = data
                    }
                )
            end)

            if ok and check_res_ok(res) then
                return true
            end

            task.wait(0.25)
        end
    end

    if is_looping then
        local active = true
        task.spawn(function()
            while active do
                attempt()
                task.wait(1)
            end
        end)
        return function() active = false end
    end

    return attempt()
end

-- // public api
-- lobby
function TDS:Mode(difficulty)
    if game_state ~= "LOBBY" then 
        return false 
    end

    local lobby_hud = player_gui:WaitForChild("ReactLobbyHud", 30)
    local frame = lobby_hud and lobby_hud:WaitForChild("Frame", 30)
    local match_making = frame and frame:WaitForChild("matchmaking", 30)

    if match_making then
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local success = false
    local res
        repeat
            local ok, result = pcall(function()
                local mode = TDS.matchmaking_map[difficulty]

                local payload

                if mode then
                    payload = {
                        mode = mode,
                        count = 1
                    }
                else
                    payload = {
                        difficulty = difficulty,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and check_res_ok(result) then
                success = true
                res = result
            else
                task.wait(0.5) 
            end
        until success
    end

    return true
end

function TDS:Loadout(...)
    if game_state ~= "LOBBY" then
        return
    end

    local lobby_hud = player_gui:WaitForChild("ReactLobbyHud", 30)
    local frame = lobby_hud:WaitForChild("Frame", 30)
    frame:WaitForChild("matchmaking", 30)

    local towers = {...}
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
    
    local currently_equipped = {}

    if state_replicators then
        for _, folder in ipairs(state_replicators:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == local_player.UserId then
                local equipped_attr = folder:GetAttribute("EquippedTowers")
                if type(equipped_attr) == "string" then
                    local cleaned_json = equipped_attr:match("%[.*%]") 
                    local decode_success, decoded = pcall(function()
                        return http_service:JSONDecode(cleaned_json)
                    end)

                    if decode_success and type(decoded) == "table" then
                        currently_equipped = decoded
                    end
                end
            end
        end
    end

    for _, current_tower in ipairs(currently_equipped) do
        if current_tower ~= "None" then
            local unequip_done = false
            repeat
                local ok = pcall(function()
                    remote:InvokeServer("Inventory", "Unequip", "tower", current_tower)
                    task.wait(0.3)
                end)
                if ok then unequip_done = true else task.wait(0.2) end
            until unequip_done
        end
    end

    task.wait(0.5)

    for _, tower_name in ipairs(towers) do
        if tower_name and tower_name ~= "" then
            local equip_success = false
            repeat
                local ok = pcall(function()
                    remote:InvokeServer("Inventory", "Equip", "tower", tower_name)
                    Logger:Log("Equipped tower: " .. tower_name)
                    task.wait(0.3)
                end)
                if ok then equip_success = true else task.wait(0.2) end
            until equip_success
        end
    end

    task.wait(0.5)
    return true
end

-- ingame
function TDS:TeleportToLobby()
    send_to_lobby()
end

function TDS:VoteSkip(start_wave, end_wave)
    task.spawn(function()
        local current_wave = get_current_wave()
        start_wave = start_wave or (current_wave > 0 and current_wave or 1)
        end_wave = end_wave or start_wave

        for wave = start_wave, end_wave do
            while get_current_wave() < wave do
                task.wait(1)
            end

            local skip_done = false
            while not skip_done do
                local vote_ui = player_gui:FindFirstChild("ReactOverridesVote")
                local vote_button = vote_ui 
                    and vote_ui:FindFirstChild("Frame") 
                    and vote_ui.Frame:FindFirstChild("votes") 
                    and vote_ui.Frame.votes:FindFirstChild("vote", true)

                if vote_button and vote_button.Position == UDim2.new(0.5, 0, 0.5, 0) then
                    run_vote_skip()
                    skip_done = true
                    Logger:Log("Voted to skip wave " .. wave)
                else
                    if get_current_wave() > wave then
                        break 
                    end
                    task.wait(0.5)
                end
            end
        end
    end)
end

function TDS:GameInfo(name, list)
    list = list or {}
    if game_state ~= "GAME" then return false end

    local vote_gui = player_gui:WaitForChild("ReactGameIntermission", 30)
    if not (vote_gui and vote_gui.Enabled and vote_gui:WaitForChild("Frame", 5)) then return end

    cast_modifier_vote(list)

    if marketplace_service:UserOwnsGamePassAsync(local_player.UserId, 10518590) then
        select_map_override(name, "vip")
        Logger:Log("Selected map: " .. name)
        repeat task.wait(1) until player_gui:FindFirstChild("ReactUniversalHotbar") -- waits for the game to load
        return true 
    elseif is_map_available(name) then
        select_map_override(name)
        repeat task.wait(1) until player_gui:FindFirstChild("ReactUniversalHotbar") -- waits for the game to load again
        return true
    else
        Logger:Log("Map '" .. name .. "' not available, rejoining...") -- Logger
        teleport_service:Teleport(3260590327, local_player)
        repeat task.wait(9999) until false -- waits until 2050 instead of wasting timescale tickets/phantom placing/upgrading/selling towers
    end
end

function TDS:UnlockTimeScale()
    unlock_speed_tickets()
end

function TDS:TimeScale(val)
    set_game_timescale(val)
end

function TDS:StartGame()
    lobby_ready_up()
end

function TDS:Ready()
    if game_state ~= "GAME" then
        return false 
    end
    match_ready_up()
end

function TDS:GetWave()
    return get_current_wave()
end

function TDS:RestartGame()
    trigger_restart()
end

function TDS:Place(t_name, px, py, pz, ...)
    local args = {...}
    local stack = false

    if args[#args] == "stack" or args[#args] == true then
        py = py+20
    end
    if game_state ~= "GAME" then
        return false 
    end
    
    local existing = {}
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        for _, sub_child in ipairs(child:GetChildren()) do
            if sub_child.Name == "Owner" and sub_child.Value == local_player.UserId then
                existing[child] = true
                break
            end
        end
    end

    do_place_tower(t_name, Vector3.new(px, py, pz))

    local new_t
    repeat
        for _, child in ipairs(workspace.Towers:GetChildren()) do
            if not existing[child] then
                for _, sub_child in ipairs(child:GetChildren()) do
                    if sub_child.Name == "Owner" and sub_child.Value == local_player.UserId then
                        new_t = child
                        break
                    end
                end
            end
            if new_t then break end
        end
        task.wait(0.05)
    until new_t

    table.insert(self.placed_towers, new_t)
    return #self.placed_towers
end

function TDS:Upgrade(idx, p_id)
    local t = self.placed_towers[idx]
    if t then
        do_upgrade_tower(t, p_id or 1)
        Logger:Log("Upgrading tower index: " .. idx)
        upgrade_history[idx] = (upgrade_history[idx] or 0) + 1
    end
end

function TDS:SetTarget(idx, target_type, req_wave)
    if req_wave then
        repeat task.wait(0.5) until get_current_wave() >= req_wave
    end

    local t = self.placed_towers[idx]
    if not t then return end

    pcall(function()
        remote_func:InvokeServer("Troops", "Target", "Set", {
            Troop = t,
            Target = target_type
        })
        Logger:Log("Set target for tower index " .. idx .. " to " .. target_type)
    end)
end

function TDS:Sell(idx, req_wave)
    if req_wave then
        repeat task.wait(0.5) until get_current_wave() >= req_wave
    end
    local t = self.placed_towers[idx]
    if t and do_sell_tower(t) then
        return true
    end
    return false
end

function TDS:SellAll(req_wave)
    task.spawn(function()
        if req_wave then
            repeat task.wait(0.5) until get_current_wave() >= req_wave
        end

        local towers_copy = {unpack(self.placed_towers)}
        for idx, t in ipairs(towers_copy) do
            if do_sell_tower(t) then
                for i, orig_t in ipairs(self.placed_towers) do
                    if orig_t == t then
                        table.remove(self.placed_towers, i)
                        break
                    end
                end
            end
        end

        return true
    end)
end

function TDS:Ability(idx, name, data, loop)
    local t = self.placed_towers[idx]
    if not t then return false end
    Logger:Log("Activating ability '" .. name .. "' for tower index: " .. idx)
    return do_activate_ability(t, name, data, loop)
end

function TDS:AutoChain(...)
    local tower_indices = {...}
    if #tower_indices == 0 then return end

    local running = true

    task.spawn(function()
        local i = 1
        while running do
            local idx = tower_indices[i]
            local tower = TDS.placed_towers[idx]

            if tower then
                do_activate_ability(tower, "Call Of Arms")
            end

            local hotbar = player_gui.ReactUniversalHotbar.Frame
            local timescale = hotbar:FindFirstChild("timescale")

            if timescale then
                if timescale:FindFirstChild("Lock") then
                    task.wait(10.5)
                else
                    task.wait(5.5)
                end
            else
                task.wait(10.5)
            end

            i += 1
            if i > #tower_indices then
                i = 1
            end
        end
    end)

    return function()
        running = false
    end
end

function TDS:SetOption(idx, name, val, req_wave)
    local t = self.placed_towers[idx]
    if t then
        Logger:Log("Setting option '" .. name .. "' for tower index: " .. idx)
        return do_set_option(t, name, val, req_wave)
    end
    return false
end

-- // misc utility
local function is_void_charm(obj)
    return math.abs(obj.Position.Y) > 999999
end

local function get_root()
    local char = local_player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function start_auto_pickups()
    if auto_pickups_running or not _G.AutoPickups then return end
    auto_pickups_running = true

    task.spawn(function()
        while _G.AutoPickups do
            local folder = workspace:FindFirstChild("Pickups")
            local hrp = get_root()

            if folder and hrp then
                for _, item in ipairs(folder:GetChildren()) do
                    if not _G.AutoPickups then break end

                    if item:IsA("MeshPart") and (item.Name == "SnowCharm" or item.Name == "Lorebook") then
                        if not is_void_charm(item) then
                            local old_pos = hrp.CFrame
                            hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                            task.wait(0.2)
                            hrp.CFrame = old_pos
                            task.wait(0.3)
                        end
                    end
                end
            end

            task.wait(1)
        end

        auto_pickups_running = false
    end)
end

local function start_auto_skip()
    if auto_skip_running or not _G.AutoSkip then return end
    auto_skip_running = true

    task.spawn(function()
        while _G.AutoSkip do
            local skip_visible =
                player_gui:FindFirstChild("ReactOverridesVote")
                and player_gui.ReactOverridesVote:FindFirstChild("Frame")
                and player_gui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and player_gui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if skip_visible and skip_visible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                run_vote_skip()
            end

            task.wait(1)
        end

        auto_skip_running = false
    end)
end

local function start_claim_rewards()
    if auto_claim_rewards or not _G.ClaimRewards or game_state ~= "LOBBY" then 
        return 
    end
    
    auto_claim_rewards = true

    local player = game:GetService("Players").LocalPlayer
    local network = game:GetService("ReplicatedStorage"):WaitForChild("Network")
        
    local spin_tickets = player:WaitForChild("SpinTickets", 15)
    
    if spin_tickets and spin_tickets.Value > 0 then
        local ticket_count = spin_tickets.Value
        
        local daily_spin = network:WaitForChild("DailySpin", 5)
        local redeem_remote = daily_spin and daily_spin:WaitForChild("RF:RedeemSpin", 5)
    
        if redeem_remote then
            for i = 1, ticket_count do
                redeem_remote:InvokeServer()
                task.wait(0.5)
            end
        end
    end

    for i = 1, 6 do
        local args = { i }
        network:WaitForChild("PlaytimeRewards"):WaitForChild("RF:ClaimReward"):InvokeServer(unpack(args))
        task.wait(0.5)
    end
    
    game:GetService("ReplicatedStorage").Network.DailySpin["RF:RedeemReward"]:InvokeServer()
    auto_claim_rewards = false
end

local function start_back_to_lobby()
    if back_to_lobby_running then return end
    back_to_lobby_running = true

    handle_post_match()

    back_to_lobby_running = false
end

local function start_anti_lag()
    if anti_lag_running then return end
    anti_lag_running = true

    local settings = settings().Rendering
    local original_quality = settings.QualityLevel
    settings.QualityLevel = Enum.QualityLevel.Level01

    task.spawn(function()
        while _G.AntiLag do
            local towers_folder = workspace:FindFirstChild("Towers")
            local client_units = workspace:FindFirstChild("ClientUnits")
            local enemies = workspace:FindFirstChild("NPCs")

            if towers_folder then
                for _, tower in ipairs(towers_folder:GetChildren()) do
                    local anims = tower:FindFirstChild("Animations")
                    local weapon = tower:FindFirstChild("Weapon")
                    local projectiles = tower:FindFirstChild("Projectiles")
                    
                    if anims then anims:Destroy() end
                    if projectiles then projectiles:Destroy() end
                    if weapon then weapon:Destroy() end
                end
            end
            if client_units then
                for _, unit in ipairs(client_units:GetChildren()) do
                    unit:Destroy()
                end
            end
            if enemies then
                for _, npc in ipairs(enemies:GetChildren()) do
                    npc:Destroy()
                end
            end
            task.wait(0.5)
        end
        anti_lag_running = false
    end)
end

local function start_anti_afk()
    local VirtualUser = game:GetService("VirtualUser")

    task.spawn(function()
        local function disable_idled()
            local success, connections = pcall(getconnections, local_player.Idled)
            if success then
                for _, v in pairs(connections) do
                    v:Disable()
                end
            end
        end
        
        disable_idled()
    end)

    task.spawn(function()
        local_player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)

    task.spawn(function()
        local core_gui = game:GetService("CoreGui")
        local overlay = core_gui:WaitForChild("RobloxPromptGui"):WaitForChild("promptOverlay")

        overlay.ChildAdded:Connect(function(child)
            if child.Name == 'ErrorPrompt' then
                while true do
                    teleport_service:Teleport(3260590327)
                    task.wait(5)
                end
            end
        end)
    end)

    task.spawn(function()
        local lobby_timer = 0
        while game_state == "LOBBY" do 
            task.wait(1)
            lobby_timer = lobby_timer + 1
            if lobby_timer >= 600 then
                teleport_service:Teleport(3260590327)
                break 
            end
        end
    end)
end

local function start_auto_chain()
    if auto_chain_running or not _G.AutoChain then return end
    auto_chain_running = true

    task.spawn(function()
        local idx = 1

        while _G.AutoChain do
            local commander = {}
            local towers_folder = workspace:FindFirstChild("Towers")

            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Commander"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 2 then
                        commander[#commander + 1] = towers.Parent
                    end
                end
            end

            if #commander >= 3 then
                if idx > #commander then idx = 1 end

                local response = remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = commander[idx], Name = "Call Of Arms", Data = {} }
                )

                if response then
                    idx += 1

                    local hotbar = player_gui:FindFirstChild("ReactUniversalHotbar")
                    local timescale_frame = hotbar and hotbar.Frame:FindFirstChild("timescale")
                    
                    if timescale_frame and timescale_frame.Visible then
                        if timescale_frame:FindFirstChild("Lock") then
                            task.wait(10.3)
                        else
                            task.wait(5.25)
                        end
                    else
                        task.wait(10.3)
                    end
                else
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        end

        auto_chain_running = false
    end)
end

local function start_auto_dj_booth()
    if auto_dj_running or not _G.AutoDJ then return end
    auto_dj_running = true

    task.spawn(function()
        while _G.AutoDJ do
            local towers_folder = workspace:FindFirstChild("Towers")

            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "DJ Booth"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                        DJ = towers.Parent
                    end
                end
            end

            if DJ then
                remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = DJ, Name = "Drop The Beat", Data = {} }
                )
            end

            task.wait(1)
        end

        auto_dj_running = false
    end)
end

local function start_auto_mercenary_mili()
    if not _G.AutoMercenary and not _G.AutoMilitary then return end
        
    if auto_merc_mili_running then return end
    auto_merc_mili_running = true

    task.spawn(function()
        while _G.AutoMercenary do
            local towers_folder = workspace:FindFirstChild("Towers")

            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Mercenary Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 5 then
                        
                        remote_func:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Air-Drop", 
                                Data = {
                                    pathName = 1, 
                                    directionCFrame = CFrame.new(), 
                                    dist = _G.MercenaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)
                        
                        if not _G.AutoMercenary then break end
                    end
                end
            end

            task.wait(0.5)
        end
    end)

    task.spawn(function()
        while _G.AutoMilitary do
            local towers_folder = workspace:FindFirstChild("Towers")
            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Military Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 4 then
                        
                        remote_func:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Airstrike", 
                                Data = {
                                    pathName = 1, 
                                    pointToEnd = CFrame.new(), 
                                    dist = _G.MilitaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)
                        
                        if not _G.AutoMilitary then break end
                    end
                end
            end

            task.wait(0.5)
        end
    end)

    auto_merc_mili_running = false
end

local function start_sell_farm()
    if sell_farms_running or not _G.SellFarms then return end
    sell_farms_running = true

    task.spawn(function()
        while _G.SellFarms do
            local current_wave = get_current_wave()
            if _G.SellFarmsWave and current_wave < _G.SellFarmsWave then
                task.wait(1)
                continue
            end

            local towers_folder = workspace:FindFirstChild("Towers")
            if towers_folder then
                for _, replicator in ipairs(towers_folder:GetDescendants()) do
                    if replicator:IsA("Folder") and replicator.Name == "TowerReplicator" then
                        local is_farm = replicator:GetAttribute("Name") == "Farm"
                        local is_mine = replicator:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId

                        if is_farm and is_mine then
                            local tower_model = replicator.Parent
                            remote_func:InvokeServer("Troops", "Sell", { Troop = tower_model })
                            
                            task.wait(0.2)
                        end
                    end
                end
            end

            task.wait(1)
        end
        sell_farms_running = false
    end)
end

task.spawn(function()
    while true do
        if _G.AutoPickups and not auto_pickups_running then
            start_auto_pickups()
        end
        
        if _G.AutoSkip and not auto_skip_running then
            start_auto_skip()
        end

        if _G.AutoChain and not auto_chain_running then
            start_auto_chain()
        end

        if _G.AutoDJ and not auto_dj_running then
            start_auto_dj_booth()
        end

        if _G.AutoMercenary or _G.AutoMilitary and not auto_merc_mili_running then
            start_auto_mercenary_mili()
        end

        if _G.SellFarms and not sell_farms_running then
            start_sell_farm()
        end
        
        if _G.AntiLag and not anti_lag_running then
            start_anti_lag()
        end

        if _G.AutoRejoin and not back_to_lobby_running then
            start_back_to_lobby()
        end
        
        task.wait(1)
    end
end)

if _G.ClaimRewards and not auto_claim_rewards then
    start_claim_rewards()
end

start_anti_afk()

return TDS
