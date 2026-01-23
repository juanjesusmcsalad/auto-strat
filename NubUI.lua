local originalWarn = warn
warn = function(...)
    local msg = tostring(select(1, ...))
    if msg and string.find(msg, "Infinite yield possible", 1, true) then
        return
    end
    return originalWarn(...)
end

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local coreGui = game:GetService("CoreGui")

local isLobby = workspace:FindFirstChild("Type") and workspace.Type.Value == "Lobby"

local localPlayer = players.LocalPlayer
local mouse = localPlayer:GetMouse()

local serverRemoteFunction = replicatedStorage:WaitForChild("RemoteFunction")
local serverRemoteEvent = replicatedStorage:FindFirstChild("RemoteEvent") or replicatedStorage:WaitForChild("RemoteEvent", 5)

local stackCount = 1
local stackYOffset = 6
local isStackModeEnabled = false
local stackPreviewPart = nil
local stackRenderConn = nil
local AutoRejoin = false

local log_message
local record_strat_action
local equipTowerByName
local refreshEquippedTowerNames

local isRecordingStrat = false
local stratSpawnedTowers = {}
local stratTowerCount = 0
local stratFileName = "Strat.txt"
local httpService = game:GetService("HttpService")

local moduleCache = {}

local function findLoadedModule(name, onlyReplicated)
    local cached = moduleCache[name]
    if cached and cached.Parent then
        return cached
    end
    for _, moduleScript in pairs(getloadedmodules()) do
        if moduleScript.Name == name and (not onlyReplicated or moduleScript:IsDescendantOf(replicatedStorage)) then
            moduleCache[name] = moduleScript
            return moduleScript
        end
    end
    return nil
end

local playerReplicatorModuleCache = nil

local function getLocalReplicator()
    local playerReplicatorModule = playerReplicatorModuleCache

    if not playerReplicatorModule then
        playerReplicatorModule = replicatedStorage:FindFirstChild("Client")
            and replicatedStorage.Client:FindFirstChild("Modules")
            and replicatedStorage.Client.Modules:FindFirstChild("Universal")
            and replicatedStorage.Client.Modules.Universal:FindFirstChild("Modules")
            and replicatedStorage.Client.Modules.Universal.Modules:FindFirstChild("PlayerReplicator")

        if not playerReplicatorModule then
            playerReplicatorModule = findLoadedModule("PlayerReplicator", true)
        end

        if playerReplicatorModule then
            playerReplicatorModuleCache = playerReplicatorModule
        end
    end

    if not playerReplicatorModule then
        warn("Could not find PlayerReplicator module")
        return nil
    end

    local playerReplicator = require(playerReplicatorModule)

    local entity = nil
    if playerReplicator.GetEntityFromPlayer then
        entity = playerReplicator.GetEntityFromPlayer(localPlayer)
    elseif playerReplicator.GetLocalPlayer then
        local promise = playerReplicator.GetLocalPlayer()
        if promise and promise.andThen then
            entity = promise:expect()
        else
            entity = promise
        end
    end

    if entity and entity.Replicator then
        return entity.Replicator
    end

    return nil
end

local function readGameModeValue()
    local stateFolder = replicatedStorage:FindFirstChild("State")
    local stateGameMode = stateFolder and stateFolder:FindFirstChild("GameMode")
    if stateGameMode and stateGameMode.Value ~= nil then
        return stateGameMode.Value
    end

    local directGameMode = replicatedStorage:FindFirstChild("GameMode")
    if directGameMode and directGameMode.Value ~= nil then
        return directGameMode.Value
    end

    local moduleScript = findLoadedModule("GameState", true)
    if moduleScript then
        local ok, gameState = pcall(require, moduleScript)
        if ok and type(gameState) == "table" then
            local mode = gameState.GameMode
            if type(mode) == "string" then
                return mode
            end
        end
    end

    return nil
end

local function getInventoryControllerPvpMode()
    local moduleScript = findLoadedModule("InventoryController", true)
    if moduleScript then
        local ok, controller = pcall(require, moduleScript)
        if ok and type(controller) == "table" and controller.getPVPMode then
            local modeOk, modeValue = pcall(function()
                return controller:getPVPMode()
            end)
            if modeOk then
                if type(modeValue) == "boolean" then
                    return modeValue
                end
                if type(modeValue) == "table" and modeValue.get then
                    local okValue, value = pcall(function()
                        return modeValue:get()
                    end)
                    if okValue and type(value) == "boolean" then
                        return value
                    end
                end
            end
        end
    end

    return nil
end

local inventoryControllerCache = nil
local function getInventoryController()
    local controller = inventoryControllerCache
    if controller then
        return controller
    end
    local moduleScript = findLoadedModule("InventoryController", true)
    if moduleScript then
        local ok, loaded = pcall(require, moduleScript)
        if ok and type(loaded) == "table" then
            inventoryControllerCache = loaded
            return loaded
        end
    end
    return nil
end

local function normalizeHotbarValue(value)
    if type(value) == "table" then
        if value.get then
            local ok, resolved = pcall(function()
                return value:get()
            end)
            if ok then
                return resolved
            end
        end
        return value
    end
    return nil
end

local function getHotbarSlotsFromController(pvpMode)
    local controller = getInventoryController()
    if not controller then
        return nil
    end
    local ok, hotbarValue = pcall(function()
        if pvpMode and controller.getPvPHotbar then
            return controller:getPvPHotbar()
        end
        if controller.getHotbar then
            return controller:getHotbar()
        end
        return nil
    end)
    if not ok then
        return nil
    end
    local slots = normalizeHotbarValue(hotbarValue)
    if type(slots) == "table" and next(slots) ~= nil then
        return slots
    end
    return nil
end

local function detectPvpMode()
    local modeValue = readGameModeValue()
    if type(modeValue) == "string" and string.find(string.upper(modeValue), "PVP", 1, true) then
        return true
    end

    local controllerMode = getInventoryControllerPvpMode()
    if controllerMode ~= nil then
        return controllerMode
    end

    return false
end

local inventoryCache = { data = nil, time = 0 }

local function fetchInventoryTroops()
    local now = os.clock()
    if inventoryCache.data and (now - inventoryCache.time) < 0.5 then
        return inventoryCache.data
    end
    local data = serverRemoteFunction:InvokeServer("Session", "Search", "Inventory.Troops") or {}
    inventoryCache.data = data
    inventoryCache.time = now
    return data
end

local function decodeEquippedSlots(rawSlots)
    if type(rawSlots) == "table" then
        return rawSlots
    end
    if type(rawSlots) ~= "string" then
        return nil
    end
    local jsonChunk = rawSlots:match("%[.*%]")
    if not jsonChunk then
        return nil
    end
    local httpService = game:GetService("HttpService")
    local ok, parsed = pcall(function()
        return httpService:JSONDecode(jsonChunk)
    end)
    if ok and type(parsed) == "table" then
        return parsed
    end
    return nil
end

local function getEquippedSlotsFromReplicator(pvpMode)
    local replicator = getLocalReplicator()
    if not replicator then
        return nil
    end
    local key = pvpMode and "EquippedPVPTowers" or "EquippedTowers"
    local slots = nil
    if replicator.Get then
        slots = replicator:Get(key)
    elseif replicator.get then
        slots = replicator:get(key)
    end
    return decodeEquippedSlots(slots)
end

local function fetchEquippedTowerSlots(pvpMode)
    local controllerSlots = getHotbarSlotsFromController(pvpMode)
    if type(controllerSlots) == "table" and next(controllerSlots) ~= nil then
        return controllerSlots
    end
    local replicatorSlots = getEquippedSlotsFromReplicator(pvpMode)
    if type(replicatorSlots) == "table" and next(replicatorSlots) ~= nil then
        return replicatorSlots
    end
    local key = pvpMode and "Equipped.PVPTroops" or "Equipped.Troops"
    local ok, slots = pcall(function()
        return serverRemoteFunction:InvokeServer("Session", "Search", key)
    end)
    if ok then
        return decodeEquippedSlots(slots) or slots
    end
    return nil
end

local function collectEquippedTowerNames(pvpMode)
    local equippedTowerNames = {}
    local seen = {}

    local slots = fetchEquippedTowerSlots(pvpMode)
    if type(slots) == "table" then
        for _, towerName in pairs(slots) do
            if type(towerName) == "string" and not seen[towerName] then
                seen[towerName] = true
                equippedTowerNames[#equippedTowerNames + 1] = towerName
            end
        end
    end

    if #equippedTowerNames > 0 then
        return equippedTowerNames
    end

    local inventory = fetchInventoryTroops()
    for towerName, towerData in next, inventory do
        if towerData.Equipped and not seen[towerName] then
            seen[towerName] = true
            equippedTowerNames[#equippedTowerNames + 1] = towerName
        end
    end

    return equippedTowerNames
end

local function fetchEquippedTowerNames()
    return collectEquippedTowerNames(detectPvpMode())
end

local function resolveTowerName(inputText, inventoryData)
    if not inputText or inputText == "" then
        return nil
    end

    local needle = string.lower(inputText)
    for towerName in pairs(inventoryData) do
        if string.lower(towerName) == needle then
            return towerName
        end
    end

    local prefixMatches = {}
    for towerName in pairs(inventoryData) do
        if string.sub(string.lower(towerName), 1, #needle) == needle then
            prefixMatches[#prefixMatches + 1] = towerName
        end
    end

    local function pickBest(matches)
        table.sort(matches, function(a, b)
            if #a ~= #b then
                return #a < #b
            end
            return a < b
        end)
        return matches[1]
    end

    if #prefixMatches > 0 then
        return pickBest(prefixMatches)
    end

    local containsMatches = {}
    for towerName in pairs(inventoryData) do
        if string.find(string.lower(towerName), needle, 1, true) then
            containsMatches[#containsMatches + 1] = towerName
        end
    end

    if #containsMatches > 0 then
        return pickBest(containsMatches)
    end

    return nil
end

local function waitForUnequip(towerName, attempts, delaySeconds, pvpMode)
    local mode = pvpMode
    if mode == nil then
        mode = detectPvpMode()
    end
    for _ = 1, attempts do
        local equipped = false
        local slots = fetchEquippedTowerSlots(mode)
        if type(slots) == "table" then
            for _, slotName in pairs(slots) do
                if slotName == towerName then
                    equipped = true
                    break
                end
            end
        end
        if not equipped then
            local inventory = fetchInventoryTroops()
            local record = inventory[towerName]
            equipped = record and record.Equipped or false
        end
        if not equipped then
            return true
        end
        task.wait(delaySeconds)
    end
    return false
end

local function waitForEquip(towerName, attempts, delaySeconds, pvpMode)
    local mode = pvpMode
    if mode == nil then
        mode = detectPvpMode()
    end
    for _ = 1, attempts do
        local equipped = false
        local slots = fetchEquippedTowerSlots(mode)
        if type(slots) == "table" then
            for _, slotName in pairs(slots) do
                if slotName == towerName then
                    equipped = true
                    break
                end
            end
        end
        if not equipped then
            local inventory = fetchInventoryTroops()
            local record = inventory[towerName]
            equipped = record and record.Equipped or false
        end
        if equipped then
            return true
        end
        task.wait(delaySeconds)
    end
    return false
end

local function getOwnedTowersByName(towerName, minUpgrade)
    local list = {}
    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder then
        return list
    end
    for _, tower in ipairs(towersFolder:GetChildren()) do
        local rep = tower:FindFirstChild("TowerReplicator")
        if not rep then
            rep = tower:FindFirstChild("TowerReplicator", true)
        end
        if rep and rep:GetAttribute("OwnerId") == localPlayer.UserId then
            local name = rep:GetAttribute("Name")
            if name == towerName and (rep:GetAttribute("Upgrade") or 0) >= (minUpgrade or 0) then
                list[#list + 1] = tower
            end
        end
    end
    return list
end

local auto_chain_running = false
local auto_chain_idx = 1

local function auto_chain_step()
    if not _G.AutoChain then
        auto_chain_running = false
        return
    end

    local player_gui = localPlayer:FindFirstChild("PlayerGui")
    local commanders = getOwnedTowersByName("Commander", 2)

    if #commanders >= 3 then
        if auto_chain_idx > #commanders then
            auto_chain_idx = 1
        end

        local response = serverRemoteFunction:InvokeServer(
            "Troops",
            "Abilities",
            "Activate",
            { Troop = commanders[auto_chain_idx], Name = "Call Of Arms", Data = {} }
        )

        if response then
            auto_chain_idx += 1

            local waitTime = 10.3
            if player_gui then
                local hotbar = player_gui:FindFirstChild("ReactUniversalHotbar")
                local timescale_frame = hotbar and hotbar.Frame:FindFirstChild("timescale")

                if timescale_frame and timescale_frame.Visible then
                    if timescale_frame:FindFirstChild("Lock") then
                        waitTime = 10.3
                    else
                        waitTime = 5.25
                    end
                else
                    waitTime = 10.3
                end
            end

            task.delay(waitTime, auto_chain_step)
            return
        end

        task.delay(0.5, auto_chain_step)
        return
    end

    task.delay(1, auto_chain_step)
end

local function start_auto_chain()
    if auto_chain_running or not _G.AutoChain then
        return
    end
    auto_chain_running = true
    auto_chain_idx = 1
    task.defer(auto_chain_step)
end

local auto_dj_running = false

local function auto_dj_step()
    if not _G.AutoDJ then
        auto_dj_running = false
        return
    end

    local dj = nil
    local list = getOwnedTowersByName("DJ Booth", 3)
    if #list > 0 then
        dj = list[1]
    end

    if dj then
        serverRemoteFunction:InvokeServer(
            "Troops",
            "Abilities",
            "Activate",
            { Troop = dj, Name = "Drop The Beat", Data = {} }
        )
    end

    task.delay(1, auto_dj_step)
end

local function start_auto_dj_booth()
    if auto_dj_running or not _G.AutoDJ then
        return
    end
    auto_dj_running = true
    task.defer(auto_dj_step)
end

local auto_mercenary_running = false

local function auto_mercenary_cycle()
    if not _G.AutoMercenary then
        auto_mercenary_running = false
        return
    end

    local towers_folder = workspace:FindFirstChild("Towers")
    if towers_folder then
        for _, towers in ipairs(towers_folder:GetDescendants()) do
            if towers:IsA("Folder")
                and towers.Name == "TowerReplicator"
                and towers:GetAttribute("Name") == "Mercenary Base"
                and towers:GetAttribute("OwnerId") == localPlayer.UserId
                and (towers:GetAttribute("Upgrade") or 0) >= 5 then
                
                serverRemoteFunction:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { 
                        Troop = towers.Parent, 
                        Name = "Air-Drop", 
                        Data = {
                            pathName = 1, 
                            directionCFrame = CFrame.new(), 
                            dist = _G.MercenaryPath or _G.PathDistance or 195
                        } 
                    }
                )

                task.wait(0.5)
                
                if not _G.AutoMercenary then
                    auto_mercenary_running = false
                    return
                end
            end
        end
    end

    task.delay(0.5, auto_mercenary_cycle)
end

local function start_auto_mercenary()
    if auto_mercenary_running or not _G.AutoMercenary then
        return
    end
    auto_mercenary_running = true
    task.defer(auto_mercenary_cycle)
end

local function send_to_lobby()
    task.wait(1)
    local lobby_remote = game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Teleport"):WaitForChild("RE:backToLobby")
    if lobby_remote then
        lobby_remote:FireServer()
    end
end

local auto_rejoin_running = false
local function auto_rejoin_step()
    if not AutoRejoin then
        auto_rejoin_running = false
        return
    end

    local delayTime = 1
    local playerGui = localPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local root = playerGui:FindFirstChild("ReactGameNewRewards")
        if root then
            local frame = root:FindFirstChild("Frame")
            local gameOver = frame and frame:FindFirstChild("gameOver")
            local rewards_screen = gameOver and gameOver:FindFirstChild("RewardsScreen")
            local ui_root = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")

            if ui_root then
                send_to_lobby()
                delayTime = 6
            end
        end
    end

    task.delay(delayTime, auto_rejoin_step)
end

local function start_auto_rejoin()
    if auto_rejoin_running then return end
    auto_rejoin_running = true
    task.defer(auto_rejoin_step)
end



-- // Path Finding & Distance Logic (Ported from DUUX_UI)
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
    local len = 0
    for i = 1, #path_nodes - 1 do
        len = len + (path_nodes[i + 1].Position - path_nodes[i].Position).Magnitude
    end
    return len
end

_G.MercenaryPath = _G.MercenaryPath or _G.PathDistance or 195
_G.PathVisuals = _G.PathVisuals or false

local mercState = { marker = nil, pending = false, tries = 0 }

local function get_point_at_distance(path_nodes, distance)
    if not path_nodes or #path_nodes < 2 then return nil end
    local current_dist = 0
    for i = 1, #path_nodes - 1 do
        local start_pos = path_nodes[i].Position
        local end_pos = path_nodes[i + 1].Position
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
        if mercState.marker then
            mercState.marker:Destroy()
            mercState.marker = nil
        end
        mercState.pending = false
        mercState.tries = 0
        return
    end

    local path_nodes = find_path()
    if not path_nodes or #path_nodes < 2 then
        if not mercState.pending then
            mercState.pending = true
            mercState.tries = 0
        end
        if mercState.tries < 10 then
            mercState.tries += 1
            task.delay(0.5, function()
                mercState.pending = false
                update_path_visuals()
            end)
        end
        return
    end

    mercState.pending = false
    mercState.tries = 0

    if not mercState.marker then
        local part = Instance.new("Part")
        part.Name = "MercVisual"
        part.Shape = Enum.PartType.Cylinder
        part.Size = Vector3.new(0.3, 3, 3)
        part.Color = Color3.fromRGB(255, 0, 0)
        part.Material = Enum.Material.Plastic
        part.Anchored = true
        part.CanCollide = false
        part.Orientation = Vector3.new(0, 0, 90)
        part.Parent = workspace
        mercState.marker = part
    end

    local merc_pos = get_point_at_distance(path_nodes, _G.MercenaryPath or 0)
    if merc_pos then
        mercState.marker.Position = merc_pos + Vector3.new(0, 0.2, 0)
        mercState.marker.Transparency = 0.7
    end
end

local max_path_distance = 300
local PathDistanceSlider = nil

local function calc_length()
    local map = workspace:FindFirstChild("Map")
    if map then
        local path_nodes = find_path()
        if path_nodes and #path_nodes > 0 then
            max_path_distance = total_length(path_nodes)
            
            if PathDistanceSlider and PathDistanceSlider.SetMax then
                pcall(function() PathDistanceSlider:SetMax(max_path_distance) end)
            end
            update_path_visuals()
            
            return true
        end
    end
    return false
end
local calc_length_running = false
local function start_calc_length()
    if calc_length_running then
        return
    end
    calc_length_running = true
    local function step()
        if calc_length() then
            calc_length_running = false
            return
        end
        task.delay(3, step)
    end
    step()
end
start_calc_length()

local equippedTowerNames = fetchEquippedTowerNames()
local selectedTowerName = equippedTowerNames[1]

local function getTowerOwnerUserId(tower)
    local towerReplicator = tower:FindFirstChild("TowerReplicator")
    if towerReplicator then
        local ownerId = towerReplicator:GetAttribute("OwnerId")
        if ownerId then
            return ownerId
        end
    end
    local ownerValue = tower:FindFirstChild("Owner")
    if ownerValue then
        return ownerValue.Value
    end
    return nil
end

local function getTowerTypeName(tower)
    local towerReplicator = tower:FindFirstChild("TowerReplicator")
    if towerReplicator then
        return towerReplicator:GetAttribute("Name")
    end
    return nil
end

local function processOwnedTowers(filterFn, actionFn)
    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder then
        return 0
    end

    local processedCount = 0
    for _, tower in pairs(towersFolder:GetChildren()) do
        if getTowerOwnerUserId(tower) == localPlayer.UserId and (not filterFn or filterFn(tower)) then
            actionFn(tower)
            processedCount = processedCount + 1
        end
    end
    return processedCount
end

local function upgradeTower(tower)
    serverRemoteFunction:InvokeServer("Troops", "Upgrade", "Set", {Troop = tower})
    task.wait()
end

local function sellTower(tower)
    serverRemoteFunction:InvokeServer("Troops", "Sell", {Troop = tower})
    task.wait()
end

local towerStatsCache = {}
local function getTowerStats(towerName)
    if type(towerName) ~= "string" then
        return nil
    end
    local cached = towerStatsCache[towerName]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    if not towerName or towerName == "" or towerName == "None" then
        towerStatsCache[towerName] = false
        return nil
    end
    local statsModule = replicatedStorage:FindFirstChild("Content")
        and replicatedStorage.Content:FindFirstChild("Tower")
        and replicatedStorage.Content.Tower:FindFirstChild(towerName)
        and replicatedStorage.Content.Tower[towerName]:FindFirstChild("Stats")
    if statsModule then
        local success, statsData = pcall(function()
            return require(statsModule)
        end)
        if success and statsData then
            towerStatsCache[towerName] = statsData
            return statsData
        end
    end
    towerStatsCache[towerName] = false
    return nil
end

local function getTowerPrice(towerName)
    local statsData = getTowerStats(towerName)
    if statsData then
        local price = statsData.Stats
            and statsData.Stats.Default
            and statsData.Stats.Default.Defaults
            and statsData.Stats.Default.Defaults.Price
        return price or 0
    end
    return 0
end

local function getTowerLimit(towerName)
    local statsData = getTowerStats(towerName)
    if statsData then
        local limit = statsData.Stats
            and statsData.Stats.Default
            and statsData.Stats.Default.Defaults
            and statsData.Stats.Default.Defaults.Limit
        return limit or 15
    end
    return 15
end

local Starlight = loadstring(game:HttpGet("https://gist.githubusercontent.com/Serial-Zero/c3b532470e7d9d84d4db4a12ffb87375/raw/3c95f36bbfec8c55794e222edd0492eda1ed5223/Source.lua"))()
local NebulaIcons = loadstring(game:HttpGet("https://raw.nebulasoftworks.xyz/nebula-icon-library-loader"))()

local execName = "Unknown"
pcall(function()
    local a, b = identifyexecutor()
    execName = a or b or execName
end)

local Window = Starlight:CreateWindow({
    Name = "SOLVER",
    Subtitle = "TDS Utils - " .. tostring(execName),
    Icon = 105059922903197,
    LoadingSettings = {
        Title = "SOLVER",
        Subtitle = "Loading...",
    },
    FileSettings = {
        ConfigFolder = "SOLVER"
    }
})

local function isWindowFocused()
    local env = getgenv and getgenv() or nil
    local fn = (env and (env.iswindowactive or env.isrbxactive or env.isgameactive))
        or iswindowactive or isrbxactive or isgameactive
    if type(fn) == "function" then
        local ok, focused = pcall(fn)
        if ok then
            return focused
        end
    end
    return true
end

local notifyCount = 0
local function uiNotify(desc, time, type)
    notifyCount = notifyCount + 1
    local iconName = (type == "warning") and "warning" or "info"
    
    local iconId = 0
    pcall(function()
        iconId = NebulaIcons:GetIcon(iconName, 'Material')
    end)

    local notif = Starlight:Notification({
        Title = "N",
        Icon = iconId,
        Content = tostring(desc),
    }, "Notify_" .. tostring(notifyCount))

    if notif and notif.Destroy then
        task.delay(time or 3, function()
            pcall(function() notif:Destroy() end)
        end)
    end
end

local function pickIcon(name, fallback)
    local icon = fallback
    pcall(function()
        local v = NebulaIcons:GetIcon(name, "Material")
        if type(v) == "number" or type(v) == "string" then
            if v ~= 0 and v ~= "0" then
                icon = v
            end
        end
    end)
    if type(icon) ~= "number" and type(icon) ~= "string" or icon == 0 or icon == "0" then
        icon = fallback
    end
    return icon
end

local Menu = Window:CreateTabSection("Menu")
local MainTab = Menu:CreateTab({ Name = "Main", Icon = pickIcon("home", 10723407389), Columns = 2 }, "MainTab")
local StatsTab = Menu:CreateTab({ Name = "Stats", Icon = pickIcon("bar_chart", 10709782497), Columns = 1 }, "StatsTab")
local RecorderTab = Menu:CreateTab({ Name = "Recorder", Icon = NebulaIcons:GetIcon('fiber_manual_record', 'Material'), Columns = 1 }, "RecorderTab")
local LoggerTab = Menu:CreateTab({ Name = "Logger", Icon = NebulaIcons:GetIcon('description', 'Material'), Columns = 1 }, "LoggerTab")
local SettingsTab = Menu:CreateTab({ Name = "Settings", Icon = NebulaIcons:GetIcon('settings', 'Material'), Columns = 2 }, "SettingsTab")
local InfoTab = Menu:CreateTab({ Name = "Info", Icon = NebulaIcons:GetIcon('info', 'Material'), Columns = 1 }, "InfoTab")

local MainGroup = MainTab:CreateGroupbox({ Name = "Tower", Column = 1 }, "MainGroup")
local EquipperGroup = MainTab:CreateGroupbox({ Name = "Equip", Column = 1 }, "EquipperGroup")
local StackGroup = MainTab:CreateGroupbox({ Name = "Stacking", Column = 1 }, "StackGroup")
local StatsGroup = StatsTab:CreateGroupbox({ Name = "Player Stats", Column = 1 }, "StatsGroup")

local StackCostLabel = nil
local StackSlider = nil
local function updateStackCostLabel()
    local price = getTowerPrice(selectedTowerName)
    local total = price * stackCount
    if StackCostLabel then
        pcall(function()
            StackCostLabel:Set({ Name = "Cost: $" .. tostring(total) })
        end)
    end
end

local function setStackPreviewEnabled(enabled)
    if enabled then
        if stackRenderConn then
            return
        end
        stackRenderConn = runService.RenderStepped:Connect(function()
            if not stackPreviewPart then
                stackPreviewPart = Instance.new("Part")
                stackPreviewPart.Shape = Enum.PartType.Ball
                stackPreviewPart.Size = Vector3.new(1, 1, 1)
                stackPreviewPart.Color = Color3.fromRGB(0, 255, 0)
                stackPreviewPart.Transparency = 0.5
                stackPreviewPart.Anchored = true
                stackPreviewPart.CanCollide = false
                stackPreviewPart.Material = Enum.Material.Neon
                stackPreviewPart.Parent = workspace
                mouse.TargetFilter = stackPreviewPart
            end

            local mouseHit = mouse.Hit
            if mouseHit then
                stackPreviewPart.Position = mouseHit.Position
            end
        end)
    else
        if stackRenderConn then
            stackRenderConn:Disconnect()
            stackRenderConn = nil
        end
        if stackPreviewPart then
            stackPreviewPart:Destroy()
            stackPreviewPart = nil
        end
    end
end

do
    local coinsLabel = StatsGroup:CreateLabel({ Name = "Coins: 0" }, "CoinsLabel")
    local gemsLabel = StatsGroup:CreateLabel({ Name = "Gems: 0" }, "GemsLabel")
    local levelLabel = StatsGroup:CreateLabel({ Name = "Level: 0" }, "LevelLabel")
    local winsLabel = StatsGroup:CreateLabel({ Name = "Wins: 0" }, "WinsLabel")
    local losesLabel = StatsGroup:CreateLabel({ Name = "Loses: 0" }, "LosesLabel")
    local expLabel = StatsGroup:CreateLabel({ Name = "Experience: 0" }, "ExperienceLabel")
    local expBar = StatsGroup:CreateSlider({
        Name = "EX",
        Range = {0, 100},
        Increment = 1,
        Suffix = "XP",
        CurrentValue = 0,
        Callback = function()
        end
    }, "ExperienceBar")

    local function parseNumber(val)
        if type(val) == "number" then
            return val
        end
        if type(val) == "string" then
            local cleaned = string.gsub(val, ",", "")
            local n = tonumber(cleaned)
            if n then
                return n
            end
        end
        if type(val) == "table" and val.get then
            local ok, v = pcall(function()
                return val:get()
            end)
            if ok then
                return parseNumber(v)
            end
        end
        return nil
    end

    local function readValue(obj)
        if not obj then
            return nil
        end
        local ok, v = pcall(function()
            return obj.Value
        end)
        if ok then
            return parseNumber(v)
        end
        return nil
    end

    local function getStatNumber(name)
        local obj = localPlayer:FindFirstChild(name)
        local v = readValue(obj)
        if v ~= nil then
            return v
        end
        local attr = localPlayer:GetAttribute(name)
        v = parseNumber(attr)
        if v ~= nil then
            return v
        end
        return nil
    end

    local function pickExpMax()
        local expObj = localPlayer:FindFirstChild("Experience")
        local attrMax = expObj and parseNumber(expObj:GetAttribute("Max"))
        local attrNeed = expObj and parseNumber(expObj:GetAttribute("Required"))
        local attrNext = expObj and parseNumber(expObj:GetAttribute("Next"))
        return attrMax
            or attrNeed
            or attrNext
            or getStatNumber("ExperienceMax")
            or getStatNumber("ExperienceNeeded")
            or getStatNumber("ExperienceRequired")
            or getStatNumber("ExperienceToNextLevel")
            or getStatNumber("ExperienceToLevel")
            or getStatNumber("NextLevelExp")
            or getStatNumber("ExpToNextLevel")
            or getStatNumber("ExpNeeded")
            or getStatNumber("ExpRequired")
            or getStatNumber("MaxExp")
            or getStatNumber("MaxExperience")
            or 100
    end

    local gcExpCache = { t = nil, last = 0 }
    local function getGcExp()
        if not getgc then
            return nil
        end
        local t = gcExpCache.t
        if t then
            local exp = parseNumber(rawget(t, "exp") or rawget(t, "Exp") or rawget(t, "experience") or rawget(t, "Experience"))
            local maxExp = parseNumber(rawget(t, "maxExp") or rawget(t, "MaxExp") or rawget(t, "maxEXP") or rawget(t, "MaxEXP") or rawget(t, "maxExperience") or rawget(t, "MaxExperience"))
            local lvl = parseNumber(rawget(t, "level") or rawget(t, "Level") or rawget(t, "lvl") or rawget(t, "Lvl"))
            if exp and maxExp then
                return exp, maxExp, lvl
            end
        end
        local now = os.clock()
        if now - gcExpCache.last < 3 then
            return nil
        end
        gcExpCache.last = now
        local plvl = getStatNumber("Level")
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" then
                local exp = parseNumber(rawget(obj, "exp") or rawget(obj, "Exp") or rawget(obj, "experience") or rawget(obj, "Experience"))
                local maxExp = parseNumber(rawget(obj, "maxExp") or rawget(obj, "MaxExp") or rawget(obj, "maxEXP") or rawget(obj, "MaxEXP") or rawget(obj, "maxExperience") or rawget(obj, "MaxExperience"))
                if exp and maxExp then
                    local lvl = parseNumber(rawget(obj, "level") or rawget(obj, "Level") or rawget(obj, "lvl") or rawget(obj, "Lvl"))
                    if not plvl or not lvl or lvl == plvl then
                        gcExpCache.t = obj
                        return exp, maxExp, lvl
                    end
                end
            end
        end
        return nil
    end

    local function updateStats()
        local coins = getStatNumber("Coins") or 0
        local gems = getStatNumber("Gems") or 0
        local lvl = getStatNumber("Level") or 0
        local wins = getStatNumber("Triumphs") or 0
        local loses = getStatNumber("Loses") or 0
        local exp = getStatNumber("Experience") or 0
        local maxExp = pickExpMax()
        local gcExp, gcMax, gcLvl = getGcExp()
        if gcExp and gcMax then
            exp = gcExp
            maxExp = gcMax
            if gcLvl then
                lvl = gcLvl
            end
        end
        if maxExp < 1 then
            maxExp = 1
        end
        if exp > maxExp then
            maxExp = exp
        end
        pcall(function() coinsLabel:Set({ Name = "Coins: " .. tostring(coins) }) end)
        pcall(function() gemsLabel:Set({ Name = "Gems: " .. tostring(gems) }) end)
        pcall(function() levelLabel:Set({ Name = "Level: " .. tostring(lvl) }) end)
        pcall(function() winsLabel:Set({ Name = "Wins: " .. tostring(wins) }) end)
        pcall(function() losesLabel:Set({ Name = "Loses: " .. tostring(loses) }) end)
        pcall(function() expLabel:Set({ Name = "Experience: " .. tostring(exp) .. " / " .. tostring(maxExp) }) end)
        pcall(function()
            expBar:Set({
                Range = {0, maxExp},
                CurrentValue = exp
            })
        end)
    end
    local statsQueued = false
    local function queueStatsUpdate()
        if statsQueued then
            return
        end
        statsQueued = true
        task.delay(0.2, function()
            statsQueued = false
            updateStats()
        end)
    end

    local statNames = {"Coins", "Gems", "Level", "Triumphs", "Loses", "Experience"}
    local expAttrNames = {
        "ExperienceMax",
        "ExperienceNeeded",
        "ExperienceRequired",
        "ExperienceToNextLevel",
        "ExperienceToLevel",
        "NextLevelExp",
        "ExpToNextLevel",
        "ExpNeeded",
        "ExpRequired",
        "MaxExp",
        "MaxExperience"
    }

    local function hookStatObj(obj)
        if not obj then
            return
        end
        if obj.Changed then
            obj.Changed:Connect(queueStatsUpdate)
        end
        obj:GetAttributeChangedSignal("Max"):Connect(queueStatsUpdate)
        obj:GetAttributeChangedSignal("Required"):Connect(queueStatsUpdate)
        obj:GetAttributeChangedSignal("Next"):Connect(queueStatsUpdate)
    end

    for _, name in ipairs(statNames) do
        hookStatObj(localPlayer:FindFirstChild(name))
        localPlayer:GetAttributeChangedSignal(name):Connect(queueStatsUpdate)
    end

    for _, name in ipairs(expAttrNames) do
        localPlayer:GetAttributeChangedSignal(name):Connect(queueStatsUpdate)
    end

    localPlayer.ChildAdded:Connect(function(child)
        if table.find(statNames, child.Name) then
            hookStatObj(child)
            queueStatsUpdate()
        end
    end)

    localPlayer.ChildRemoved:Connect(function(child)
        if table.find(statNames, child.Name) then
            queueStatsUpdate()
        end
    end)

    queueStatsUpdate()
end

-- Tower Select Dropdown
local TowerLabel = MainGroup:CreateLabel({ Name = "Select Tower" }, "TowerLabel")
local towerList = #equippedTowerNames > 0 and equippedTowerNames or {"None"}
local defaultSelection = selectedTowerName
if not defaultSelection or not table.find(towerList, defaultSelection) then
    defaultSelection = towerList[1]
end

local function updateStackSliderLimit()
    if StackSlider then
        local limit = getTowerLimit(selectedTowerName)
        if stackCount > limit then
            stackCount = limit
        end
        pcall(function()
            StackSlider:Set({
                Range = {1, limit},
                CurrentValue = stackCount
            })
        end)
    end
end

local towerSelectionDropdown = TowerLabel:AddDropdown({
    Options = towerList,
    CurrentOptions = {defaultSelection},
    Placeholder = "Select Tower",
    Callback = function(Option)
        local selected = type(Option) == "table" and Option[1] or Option
        if selected == "None" then
            selectedTowerName = nil
        else
            selectedTowerName = selected
        end
        updateStackCostLabel()
        updateStackSliderLimit()
    end
}, "TowerDropdown")

-- Stack Logic
StackGroup:CreateToggle({
    Name = "Stack Tower",
    CurrentValue = false,
    Callback = function(Value)
        isStackModeEnabled = Value
        setStackPreviewEnabled(Value)
    end
}, "StackToggle")

local initialLimit = getTowerLimit(selectedTowerName)
StackSlider = StackGroup:CreateSlider({
    Name = "Stack Amount",
    Range = {1, initialLimit},
    Increment = 1,
    CurrentValue = math.min(stackCount, initialLimit),
    Callback = function(Value)
        stackCount = Value
        updateStackCostLabel()
    end
}, "StackSlider")

StackCostLabel = StackGroup:CreateLabel({ Name = "Cost: $0" }, "StackCostLabel")



-- Equipper UI
EquipperGroup:CreateInput({
    Name = "Equip Tower",
    PlaceholderText = "Tower Name",
    CurrentValue = "",
    Enter = true,
    Callback = function(Text)
        if Text and Text ~= "" then
             if not isWindowFocused() then
                 uiNotify("Focus the game window before equipping.")
                 return
             end
             local success, errorMsg = equipTowerByName(Text)
             if success then
                 uiNotify("Equipped " .. Text)
             else
                 uiNotify(errorMsg or "Make sure you own the tower!", 3)
             end
        end
    end
}, "EquipInput")



local function buildEquippedSignature(list)
    local normalized = {}
    for _, name in ipairs(list) do
        if type(name) == "string" then
            normalized[#normalized + 1] = string.lower(name)
        end
    end
    table.sort(normalized)
    return table.concat(normalized, "|")
end

local function applyEquippedTowerList(list)
    equippedTowerNames = list
    pcall(function()
        if towerSelectionDropdown then
            local items = (#equippedTowerNames > 0) and equippedTowerNames or {"None"}
            local displaySelection = selectedTowerName

            if #equippedTowerNames == 0 then
                selectedTowerName = nil
                displaySelection = "None"
            elseif not selectedTowerName or not table.find(equippedTowerNames, selectedTowerName) then
                selectedTowerName = equippedTowerNames[1]
                displaySelection = selectedTowerName
            end

            -- Update Starlight Dropdown
            towerSelectionDropdown:Set({
                Options = items,
                CurrentOptions = {displaySelection}
            })
        end
    end)
end

local function updateEquippedListAfterEquip(newTowerName, swappedTowerName)
    if type(newTowerName) ~= "string" or newTowerName == "" then
        return
    end

    selectedTowerName = newTowerName

    local updated = {}
    local seen = {}
    for _, towerName in ipairs(equippedTowerNames or {}) do
        if towerName ~= swappedTowerName and towerName ~= newTowerName then
            updated[#updated + 1] = towerName
            seen[towerName] = true
        end
    end
    if not seen[newTowerName] then
        updated[#updated + 1] = newTowerName
    end

    applyEquippedTowerList(updated)
end

refreshEquippedTowerNames = function()
    local ok, latest = pcall(fetchEquippedTowerNames)
    if ok and type(latest) == "table" then
        applyEquippedTowerList(latest)
    end
end

local refreshQueued = false
local function requestEquippedTowerRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    task.delay(0.2, function()
        refreshQueued = false
        refreshEquippedTowerNames()
    end)
end

local function setupEquippedTowerWatcher()
    local stateReplicators = replicatedStorage:FindFirstChild("StateReplicators")
    if not stateReplicators then
        stateReplicators = replicatedStorage:WaitForChild("StateReplicators", 10)
        if not stateReplicators then
            return
        end
    end

    local function connectReplicator(folder)
        if folder.Name ~= "PlayerReplicator" then
            return
        end
        if folder:GetAttribute("UserId") ~= localPlayer.UserId then
            return
        end
        folder:GetAttributeChangedSignal("EquippedTowers"):Connect(requestEquippedTowerRefresh)
        folder:GetAttributeChangedSignal("EquippedPVPTowers"):Connect(requestEquippedTowerRefresh)
    end

    for _, folder in ipairs(stateReplicators:GetChildren()) do
        connectReplicator(folder)
    end

    stateReplicators.ChildAdded:Connect(connectReplicator)
end

local function setupEquippedTowerPoller()
    local lastSignature = buildEquippedSignature(equippedTowerNames or {})
    local tries = 0
    local function step()
        tries += 1
        local ok, latest = pcall(fetchEquippedTowerNames)
        if ok and type(latest) == "table" then
            local signature = buildEquippedSignature(latest)
            if signature ~= lastSignature then
                lastSignature = signature
                applyEquippedTowerList(latest)
            end
        end
        if tries < 10 then
            task.delay(1, step)
        end
    end
    step()
end

local ActionsGroup = MainTab:CreateGroupbox({ Name = "Actions", Column = 2 }, "ActionsGroup")

ActionsGroup:CreateButton({
    Name = "Upgrade Selected",
    Callback = function()
        processOwnedTowers(function(tower)
            return getTowerTypeName(tower) == selectedTowerName
        end, upgradeTower)
    end
}, "UpgradeSelectedButton")

ActionsGroup:CreateButton({
    Name = "Sell Selected",
    Callback = function()
        processOwnedTowers(function(tower)
            return getTowerTypeName(tower) == selectedTowerName
        end, sellTower)
    end
}, "SellSelectedButton")

ActionsGroup:CreateButton({
    Name = "Upgrade All",
    Callback = function()
        processOwnedTowers(nil, upgradeTower)
    end
}, "UpgradeAllButton")

ActionsGroup:CreateButton({
    Name = "Sell All",
    Callback = function()
        processOwnedTowers(nil, sellTower)
    end
}, "SellAllButton")


-- Info Tab
local InfoGroup = InfoTab:CreateGroupbox({Name = "Info", Column = 1}, "InfoGroup")
InfoGroup:CreateLabel({Name = "Serial Designation N"}, "InfoLabel")

local PrivacyGroup = SettingsTab:CreateGroupbox({Name = "Privacy", Column = 1}, "PrivacyGroup")
local TagGroup = SettingsTab:CreateGroupbox({Name = "Tags", Column = 2}, "TagGroup")
local GraphicsGroup = SettingsTab:CreateGroupbox({Name = "Graphics", Column = 2}, "GraphicsGroup")

local savedSettingsPath = "SOLVER/settings.json"
local function loadSettings()
    local settings = { hideUsername = false, streamerMode = false, streamerName = "", glitchyName = "None", potatoGraphics = false }
    pcall(function()
        if isfile and isfile(savedSettingsPath) then
            local data = readfile(savedSettingsPath)
            local parsed = game:GetService("HttpService"):JSONDecode(data)
            if parsed then settings = parsed end
        end
    end)
    if type(settings.glitchyName) == "boolean" then
        settings.glitchyName = "None"
    end
    if type(settings.glitchyName) ~= "string" then
        settings.glitchyName = "None"
    end
    if type(settings.potatoGraphics) ~= "boolean" then
        settings.potatoGraphics = false
    end
    return settings
end

local function saveSettings(settings)
    pcall(function()
        if writefile then
            if makefolder then
                local needsFolder = true
                if isfolder then
                    needsFolder = not isfolder("SOLVER")
                end
                if needsFolder then
                    pcall(function()
                        makefolder("SOLVER")
                    end)
                end
            end
            local data = game:GetService("HttpService"):JSONEncode(settings)
            writefile(savedSettingsPath, data)
        end
    end)
end

local currentSettings = loadSettings()
_G.PotatoGraphics = currentSettings.potatoGraphics or false
local settingsDirty = false
local settingsSaveQueued = false

local function queueSave()
    settingsDirty = true
    if settingsSaveQueued then
        return
    end
    settingsSaveQueued = true
    task.delay(0.5, function()
        if settingsDirty then
            saveSettings(currentSettings)
            settingsDirty = false
        end
        settingsSaveQueued = false
    end)
end

local originalDisplayName = localPlayer.DisplayName
local originalUserName = localPlayer.Name

local spoofTextCache = setmetatable({}, {__mode = "k"})
local streamerRunning = false
local lastSpoofName = nil
local streamerConns = {}
local streamerTextNodes = setmetatable({}, {__mode = "k"})
local streamerTag = nil
local streamerTagOrig = nil
local streamerTagConn = nil
local glitchyRunning = false
local glitchyConn = nil
local glitchyTag = nil
local originalTagValue = nil

local function makeSpoofName()
    return "BelowNatural"
end

local function addStreamerConn(conn)
    if conn then
        streamerConns[#streamerConns + 1] = conn
    end
end

local function clearStreamerConns()
    for _, c in ipairs(streamerConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    streamerConns = {}
    for inst in pairs(streamerTextNodes) do
        streamerTextNodes[inst] = nil
    end
end

local function ensureSpoofName()
    local nm = currentSettings.streamerName
    if not nm or nm == "" then
        nm = makeSpoofName()
        currentSettings.streamerName = nm
        queueSave()
    end
    return nm
end

local function isGlitchyEnabled()
    return type(currentSettings.glitchyName) == "string"
        and currentSettings.glitchyName ~= ""
        and currentSettings.glitchyName ~= "None"
end

local function setLocalDisplayName(nm)
    if not nm or nm == "" then
        return
    end
    pcall(function()
        localPlayer.DisplayName = nm
    end)
end

local function setWindowName(a, b)
    pcall(function()
        local mainWindow = Window and Window.Instance
        if mainWindow then
            local sidebar = mainWindow:FindFirstChild("Sidebar")
            if sidebar then
                local playerSection = sidebar:FindFirstChild("Player")
                if playerSection then
                    local headerLabel = playerSection:FindFirstChild("Header")
                    local subheaderLabel = playerSection:FindFirstChild("subheader")
                    if headerLabel then headerLabel.Text = a end
                    if subheaderLabel then subheaderLabel.Text = b end
                end
            end
        end
    end)
end

local function refreshWindowName()
    if currentSettings.streamerMode then
        local nm = ensureSpoofName()
        setWindowName(nm, nm)
        return
    end
    if currentSettings.hideUsername then
        setWindowName("████████", "████████████")
    else
        setWindowName(originalDisplayName, originalUserName)
    end
end

local function replacePlain(str, old, new)
    if not str or str == "" or not old or old == "" or old == new then
        return str, false
    end
    local start = 1
    local out = {}
    local changed = false
    while true do
        local i, j = string.find(str, old, start, true)
        if not i then
            out[#out + 1] = string.sub(str, start)
            break
        end
        changed = true
        out[#out + 1] = string.sub(str, start, i - 1)
        out[#out + 1] = new
        start = j + 1
    end
    if changed then
        return table.concat(out), true
    end
    return str, false
end

local function applySpoofToInstance(inst, oldA, oldB, newName)
    if not inst then
        return
    end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        local txt = inst.Text
        if type(txt) == "string" and txt ~= "" then
            local hasA = oldA and oldA ~= "" and string.find(txt, oldA, 1, true)
            local hasB = oldB and oldB ~= "" and string.find(txt, oldB, 1, true)
            if not hasA and not hasB then
                return
            end
            local t = txt
            local changed = false
            local ch
            if oldA and oldA ~= "" then
                t, ch = replacePlain(t, oldA, newName)
                if ch then changed = true end
            end
            if oldB and oldB ~= "" then
                t, ch = replacePlain(t, oldB, newName)
                if ch then changed = true end
            end
            if changed then
                if spoofTextCache[inst] == nil then
                    spoofTextCache[inst] = txt
                end
                inst.Text = t
            end
        end
    end
end

local function applySpoofToRoot(root, oldA, oldB, newName)
    if not root then
        return
    end
    for _, inst in ipairs(root:GetDescendants()) do
        applySpoofToInstance(inst, oldA, oldB, newName)
    end
end

local function restoreSpoofText()
    for inst, txt in pairs(spoofTextCache) do
        if inst and inst.Parent then
            pcall(function()
                inst.Text = txt
            end)
        end
        spoofTextCache[inst] = nil
    end
end

local function addStreamerNode(inst)
    if not (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then
        return
    end
    streamerTextNodes[inst] = true
    local nm = ensureSpoofName()
    applySpoofToInstance(inst, originalDisplayName, originalUserName, nm)
end

local function hookStreamerRoot(root)
    if not root then
        return
    end
    for _, inst in ipairs(root:GetDescendants()) do
        addStreamerNode(inst)
    end
    addStreamerConn(root.DescendantAdded:Connect(function(inst)
        if currentSettings.streamerMode then
            addStreamerNode(inst)
        end
    end))
end

local function sweepStreamerText()
    if not currentSettings.streamerMode then
        return
    end
    local nm = ensureSpoofName()
    for inst in pairs(streamerTextNodes) do
        if inst and inst.Parent then
            applySpoofToInstance(inst, originalDisplayName, originalUserName, nm)
        else
            streamerTextNodes[inst] = nil
        end
    end
end

local function applyStreamerTag()
    if isGlitchyEnabled() then
        return
    end
    local nm = ensureSpoofName()
    local tag = localPlayer:FindFirstChild("Tag")
    if not tag then
        return
    end
    if streamerTag and streamerTag ~= tag then
        if streamerTagConn then
            streamerTagConn:Disconnect()
            streamerTagConn = nil
        end
    end
    if streamerTag ~= tag then
        streamerTag = tag
        streamerTagOrig = tag.Value
    end
    if tag.Value ~= nm then
        tag.Value = nm
    end
    if streamerTagConn then
        streamerTagConn:Disconnect()
        streamerTagConn = nil
    end
    streamerTagConn = tag:GetPropertyChangedSignal("Value"):Connect(function()
        if not currentSettings.streamerMode then
            return
        end
        if isGlitchyEnabled() then
            return
        end
        local nm2 = ensureSpoofName()
        if tag.Value ~= nm2 then
            tag.Value = nm2
        end
    end)
end

local function restoreStreamerTag()
    if streamerTagConn then
        streamerTagConn:Disconnect()
        streamerTagConn = nil
    end
    if isGlitchyEnabled() then
        streamerTag = nil
        streamerTagOrig = nil
        return
    end
    if streamerTag and streamerTag.Parent and streamerTagOrig ~= nil then
        pcall(function()
            streamerTag.Value = streamerTagOrig
        end)
    end
    streamerTag = nil
    streamerTagOrig = nil
end

local function applyStreamerOnce()
    local nm = ensureSpoofName()
    if lastSpoofName and lastSpoofName ~= nm then
        restoreSpoofText()
    end
    refreshWindowName()
    setLocalDisplayName(nm)
    applyStreamerTag()
    sweepStreamerText()
    lastSpoofName = nm
end

local function startStreamerMode()
    if streamerRunning then
        return
    end
    streamerRunning = true
    clearStreamerConns()
    applyStreamerOnce()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if pg then
        hookStreamerRoot(pg)
    end
    if coreGui then
        hookStreamerRoot(coreGui)
    end
    local tagsRoot = workspace:FindFirstChild("Nametags")
    if tagsRoot then
        hookStreamerRoot(tagsRoot)
    end
    local ch = localPlayer.Character
    if ch then
        hookStreamerRoot(ch)
    end
    addStreamerConn(localPlayer.CharacterAdded:Connect(function(newChar)
        if not currentSettings.streamerMode then
            return
        end
        hookStreamerRoot(newChar)
        applyStreamerOnce()
    end))
    addStreamerConn(workspace.ChildAdded:Connect(function(inst)
        if not currentSettings.streamerMode then
            return
        end
        if inst.Name == "Nametags" then
            hookStreamerRoot(inst)
            applyStreamerOnce()
        end
    end))
    local function step()
        if not currentSettings.streamerMode then
            streamerRunning = false
            return
        end
        applyStreamerOnce()
        task.delay(0.5, step)
    end
    task.defer(step)
end

local function stopStreamerMode()
    clearStreamerConns()
    restoreSpoofText()
    refreshWindowName()
    lastSpoofName = nil
    restoreStreamerTag()
    setLocalDisplayName(originalDisplayName)
    streamerRunning = false
end

local function collectNametagOptions()
    local list = {}
    local seen = {}
    local function addFolder(folder)
        if not folder then
            return
        end
        for _, child in ipairs(folder:GetChildren()) do
            local name = child.Name
            if name and not seen[name] then
                seen[name] = true
                list[#list + 1] = name
            end
        end
    end
    local content = replicatedStorage:FindFirstChild("Content")
    if content then
        local nametag = content:FindFirstChild("Nametag")
        if nametag then
            addFolder(nametag:FindFirstChild("Basic"))
            addFolder(nametag:FindFirstChild("Exclusive"))
        end
    end
    table.sort(list)
    table.insert(list, 1, "None")
    return list
end

local function startGlitchyName()
    if glitchyRunning then
        return
    end
    glitchyRunning = true
    if not isGlitchyEnabled() then
        glitchyRunning = false
        return
    end
    _G.FakeName = currentSettings.glitchyName
    _G.Enableanonymousmode = true
    if not _G.Enableanonymousmode then
        glitchyRunning = false
        return
    end
    task.spawn(function()
        task.wait(1)
        local tag = localPlayer:FindFirstChild("Tag")
        if tag then
            if glitchyTag ~= tag then
                glitchyTag = tag
                if tag.Value ~= _G.FakeName then
                    originalTagValue = tag.Value
                end
            elseif tag.Value ~= _G.FakeName then
                originalTagValue = tag.Value
            end
            tag.Value = _G.FakeName
            if glitchyConn then
                glitchyConn:Disconnect()
                glitchyConn = nil
            end
            glitchyConn = tag:GetPropertyChangedSignal("Value"):Connect(function()
                task.wait()
                if not _G.Enableanonymousmode then
                    return
                end
                if tag.Value ~= _G.FakeName then
                    tag.Value = _G.FakeName
                end
            end)
        end
        glitchyRunning = false
    end)
end

local function stopGlitchyName()
    _G.Enableanonymousmode = false
    if glitchyConn then
        glitchyConn:Disconnect()
        glitchyConn = nil
    end
    if glitchyTag and glitchyTag.Parent then
        if originalTagValue ~= nil then
            pcall(function()
                glitchyTag.Value = originalTagValue
            end)
        else
            pcall(function()
                glitchyTag:Destroy()
            end)
        end
    end
    glitchyRunning = false
end

PrivacyGroup:CreateToggle({
    Name = "Hide Username",
    CurrentValue = currentSettings.hideUsername or false,
    Callback = function(Value)
        currentSettings.hideUsername = Value
        queueSave()
        refreshWindowName()
    end
}, "HideUsernameToggle")

PrivacyGroup:CreateInput({
    Name = "Streamer Name",
    PlaceholderText = "Spoof Name",
    CurrentValue = currentSettings.streamerName or "",
    Enter = true,
    Callback = function(Value)
        currentSettings.streamerName = Value or ""
        queueSave()
        if currentSettings.streamerMode then
            applyStreamerOnce()
        end
    end
}, "StreamerNameInput")

PrivacyGroup:CreateToggle({
    Name = "Streamer Mode",
    CurrentValue = currentSettings.streamerMode or false,
    Callback = function(Value)
        currentSettings.streamerMode = Value
        queueSave()
        if Value then
            startStreamerMode()
        else
            stopStreamerMode()
        end
    end
}, "StreamerModeToggle")

GraphicsGroup:CreateToggle({
    Name = "Potato graphics",
    CurrentValue = currentSettings.potatoGraphics or false,
    Callback = function(Value)
        currentSettings.potatoGraphics = Value
        _G.PotatoGraphics = Value
        queueSave()
    end
}, "PotatoGraphicsToggle")

local glitchyLabel = TagGroup:CreateLabel({ Name = "Tag Changer" }, "GlitchyNameLabel")
local glitchyOptions = collectNametagOptions()
local glitchyDefault = currentSettings.glitchyName
if not glitchyDefault or not table.find(glitchyOptions, glitchyDefault) then
    glitchyDefault = "None"
end
local glitchyDropdown = glitchyLabel:AddDropdown({
    Options = glitchyOptions,
    CurrentOptions = {glitchyDefault},
    Placeholder = "Select Tag",
    Callback = function(Option)
        local selected = type(Option) == "table" and Option[1] or Option
        if not selected or selected == "" then
            selected = "None"
        end
        currentSettings.glitchyName = selected
        queueSave()
        if selected == "None" then
            stopGlitchyName()
            if currentSettings.streamerMode then
                applyStreamerOnce()
            end
        else
            startGlitchyName()
        end
    end
}, "GlitchyNameDropdown")

task.delay(1, function()
    refreshWindowName()
    if currentSettings.streamerMode then
        startStreamerMode()
    end
    if isGlitchyEnabled() then
        startGlitchyName()
    end
end)

-- Utils Group
local UtilsGroup = MainTab:CreateGroupbox({Name = "Utilities", Column = 2}, "UtilsGroup")

UtilsGroup:CreateToggle({
    Name = "Auto Rejoin",
    CurrentValue = false,
    Callback = function(Value)
        AutoRejoin = Value
        if Value then
            start_auto_rejoin()
        end
    end
}, "AutoRejoinToggle")

UtilsGroup:CreateToggle({
    Name = "Auto Chain (Commander)",
    CurrentValue = false,
    Callback = function(Value)
        _G.AutoChain = Value
        if Value then
            start_auto_chain()
        end
    end
}, "AutoChainToggle")

UtilsGroup:CreateToggle({
    Name = "Auto DJ Booth",
    CurrentValue = false,
    Callback = function(Value)
        _G.AutoDJ = Value
        if Value then
            start_auto_dj_booth()
        end
    end
}, "AutoDJToggle")

UtilsGroup:CreateToggle({
    Name = "Auto Mercenary Base",
    CurrentValue = false,
    Callback = function(Value)
        _G.AutoMercenary = Value
        if Value then
            start_auto_mercenary()
        end
    end
}, "AutoMercenaryToggle")

UtilsGroup:CreateToggle({
    Name = "Path Visuals",
    CurrentValue = _G.PathVisuals or false,
    Callback = function(Value)
        _G.PathVisuals = Value
        update_path_visuals()
    end
}, "PathVisualsToggle")

PathDistanceSlider = UtilsGroup:CreateSlider({
    Name = "Merc Path Distance",
    Range = {0, 300},
    Increment = 1,
    Suffix = "Studs",
    CurrentValue = _G.MercenaryPath or _G.PathDistance or 195,
    Callback = function(Value)
        _G.MercenaryPath = Value
        _G.PathDistance = Value
        update_path_visuals()
    end
}, "PathDistanceSlider")

-- Recorder Tab
local RecorderGroup = RecorderTab:CreateGroupbox({Name = "Recorder", Column = 1}, "RecorderGroup")

RecorderGroup:CreateButton({
    Name = "START",
    Callback = function()
        if isRecordingStrat then
            uiNotify("Already recording!", 3)
            return
        end
    
        local current_mode = "Unknown"
        local current_map = "Unknown"
        
        local state_folder = replicatedStorage:FindFirstChild("State")
        if state_folder then
            current_mode = state_folder.Difficulty.Value
            current_map = state_folder.Map.Value
        end
    
        local tower1, tower2, tower3, tower4, tower5 = "None", "None", "None", "None", "None"
        local current_modifiers = "" 
        local state_replicators = replicatedStorage:FindFirstChild("StateReplicators")
    
        if state_replicators then
            for _, folder in ipairs(state_replicators:GetChildren()) do
                if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == localPlayer.UserId then
                    local equipped = folder:GetAttribute("EquippedTowers")
                    if type(equipped) == "string" then
                        -- Fix nested JSON match if needed, original code used match("%[.*%]")
                        local cleaned_json = equipped:match("%[.*%]") 
                        
                        local success, tower_table = pcall(function()
                            return httpService:JSONDecode(cleaned_json)
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
                            return httpService:JSONDecode(cleaned_json)
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
    
        isRecordingStrat = true
        stratTowerCount = 0
        stratSpawnedTowers = {}
    
        if writefile then 
            local config_header = string.format([[
local TDS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()

TDS:Loadout("%s", "%s", "%s", "%s", "%s")
TDS:Mode("%s")
TDS:GameInfo("%s", {%s})

]], tower1, tower2, tower3, tower4, tower5, current_mode, current_map, current_modifiers)
    
            writefile(stratFileName, config_header)
        end
    
        uiNotify("Recorder started! Place your towers.", 3)
        log_message("Recorder started!")
    end
}, "StartRecButton")

RecorderGroup:CreateButton({
    Name = "STOP",
    Callback = function()
        isRecordingStrat = false
        stratTowerCount = 0
        stratSpawnedTowers = {}
        uiNotify("Recording saved to Strat.txt", 3)
        log_message("Recording stopped. Saved to Strat.txt")
    end
}, "StopRecButton")

local recorderParagraph = RecorderGroup:CreateParagraph({
    Name = "Recorder Log",
    Content = "Logs will appear here..."
}, "RecorderParagraph")

-- Logger Tab
local LoggerGroup = LoggerTab:CreateGroupbox({Name = "Logger", Column = 1}, "LoggerGroup")
local loggerParagraph = LoggerGroup:CreateParagraph({
    Name = "Logs",
    Content = "Logs will appear here..."
}, "LoggerParagraph")

local logBuffer = {}
log_message = function(msg)
    local timestamp = os.date("%H:%M:%S")
    local formattedMsg = string.format("[%s] %s", timestamp, msg)
    
    table.insert(logBuffer, 1, formattedMsg) -- Add to top
    if #logBuffer > 50 then table.remove(logBuffer) end -- Limit size
    
    local content = table.concat(logBuffer, "\n")
    
    if recorderParagraph then
        recorderParagraph:Set({Content = content})
    end
    if loggerParagraph then
        loggerParagraph:Set({Content = content})
    end
end

record_strat_action = function(command_str)
    if not isRecordingStrat then return end
    if appendfile then
        appendfile(stratFileName, command_str .. "\n")
    end
end

local function setupStratRecorderListeners()
    local towers_folder = workspace:WaitForChild("Towers", 5)
    if not towers_folder then return end

    towers_folder.ChildAdded:Connect(function(tower)
        if not isRecordingStrat then return end
        
        local replicator = tower:WaitForChild("TowerReplicator", 5)
        if not replicator then return end

        local owner_id = replicator:GetAttribute("OwnerId")
        if owner_id and owner_id ~= localPlayer.UserId then return end

        stratTowerCount = stratTowerCount + 1
        local my_index = stratTowerCount
        stratSpawnedTowers[tower] = my_index

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
        record_strat_action(command)
        local msg = "Placed " .. tower_name .. " (" .. my_index .. ")"
        log_message(msg)

        replicator:GetAttributeChangedSignal("Upgrade"):Connect(function()
            if not isRecordingStrat then return end
            record_strat_action(string.format('TDS:Upgrade(%d)', my_index))
            local msg = "Upgraded Tower " .. my_index
            log_message(msg)
        end)
    end)

    towers_folder.ChildRemoved:Connect(function(tower)
        if not isRecordingStrat then return end
        
        local my_index = stratSpawnedTowers[tower]
        if my_index then
            record_strat_action(string.format('TDS:Sell(%d)', my_index))
            local msg = "Sold Tower " .. my_index
            log_message(msg)
            
            stratSpawnedTowers[tower] = nil
        end
    end)
end

task.spawn(setupStratRecorderListeners)
task.spawn(setupEquippedTowerWatcher)
task.spawn(setupEquippedTowerPoller)


local isPvpMode = false

local function ensureTowerAsset(towerName)
end

local function removeDummyAsset(towerName)
end

local function performEquip(towerName)
    -- Pre-emptively create dummy asset to satisfy immediate WaitForChild calls
    ensureTowerAsset(towerName)

    local remote = serverRemoteFunction
    if not remote then
        return false, "RemoteFunction not found"
    end
    local remoteEvent = serverRemoteEvent
    if not remoteEvent then
        return false, "RemoteEvent not found"
    end
    
    local success, err = remote:InvokeServer("Inventory", "Equip", "tower", towerName)
    if not success then
        removeDummyAsset(towerName)
        return false, err or "Failed to equip tower"
    end

    remoteEvent:FireServer("Streaming", "SelectTower", towerName, "Default")
    return true, nil
end

local function performUnequip(towerName)
    local remote = serverRemoteFunction
    if not remote then
        return false, "RemoteFunction not found"
    end

    local types = {"Tower", "tower", "Troop", "troop"}
    local lastErr = "Failed to unequip"

    for _, t in ipairs(types) do
        local success, err = remote:InvokeServer("Inventory", "Unequip", t, towerName)
        if success then
            removeDummyAsset(towerName)
            return true, nil
        end
        if err then lastErr = err end
    end
    return false, lastErr
end

local function getMaxEquippedSlots()
    if isPvpMode then
        return 4
    end
    return 5
end


equipTowerByName = function(towerName)
    -- Initialize/Detect mode if needed (isPvpMode is used by helpers/slot logic)
    isPvpMode = detectPvpMode()

    local inventoryData = fetchInventoryTroops()
    local resolvedName = resolveTowerName(towerName, inventoryData)
    if not resolvedName then
        return false, "Tower not found in inventory"
    end

    towerName = resolvedName
    local towerRecord = inventoryData and inventoryData[towerName]
    if not towerRecord then
        return false, "Tower not found in inventory"
    end

    if towerRecord.Equipped then
        refreshEquippedTowerNames()
        return true, nil
    end

    local equippedTowerNamesList = collectEquippedTowerNames(isPvpMode)
    local equippedTowerNameSet = {}
    for _, equippedName in ipairs(equippedTowerNamesList) do
        equippedTowerNameSet[equippedName] = true
    end

    if equippedTowerNameSet[towerName] then
        refreshEquippedTowerNames()
        return true, nil
    end

    local maxSlots = getMaxEquippedSlots()
    local towerToSwap = nil
    local equippedSlots = fetchEquippedTowerSlots(isPvpMode) or {}
    local occupiedCount = 0
    for slotIndex = 1, maxSlots do
        if equippedSlots[slotIndex] then
            occupiedCount = occupiedCount + 1
        end
    end
    if occupiedCount >= maxSlots then
        local candidate = equippedSlots[maxSlots]
        if candidate and candidate ~= towerName and equippedTowerNameSet[candidate] then
            towerToSwap = candidate
        end
    end

    if not towerToSwap and #equippedTowerNamesList >= maxSlots then
        for _, equippedName in ipairs(equippedTowerNamesList) do
            if equippedName ~= towerName then
                towerToSwap = equippedName
                break
            end
        end
    end

    if towerToSwap then
        local unequipSuccess = performUnequip(towerToSwap)
        if not unequipSuccess then
            -- Try to verify if it's already unequipped or lag
             if not waitForUnequip(towerToSwap, 10, 0.1, isPvpMode) then
                 return false, "Failed to unequip a tower"
             end
        else
             if not waitForUnequip(towerToSwap, 10, 0.1, isPvpMode) then
                  return false, "Unequip triggered but did not apply"
             end
        end
    end

    local equipSuccess, equipError = false, nil
    for _ = 1, 5 do
        equipSuccess, equipError = performEquip(towerName)
        if equipSuccess then
             if waitForEquip(towerName, 10, 0.1, isPvpMode) then
                 break
             end
        end
        task.wait(0.1)
    end
    
    if equipSuccess then
        -- Play sound
        task.spawn(function()
             local equipSuccessSound = Instance.new("Sound")
            equipSuccessSound.SoundId = "rbxassetid://109447077423599"
            equipSuccessSound.Volume = 1
            equipSuccessSound.Parent = game:GetService("SoundService")
            equipSuccessSound:Play()
            equipSuccessSound.Ended:Connect(function()
                equipSuccessSound:Destroy()
            end)
        end)

        updateEquippedListAfterEquip(towerName, towerToSwap)
        task.delay(0.5, refreshEquippedTowerNames)

        return true, nil
    end

    -- Restore swapped if failed
    if towerToSwap then
        local restoreSuccess = performEquip(towerToSwap)
        if restoreSuccess and waitForEquip(towerToSwap, 10, 0.1, isPvpMode) then
            refreshEquippedTowerNames()
        end
    end

    return false, equipError
end



local function unequipTowerByName(towerName)
    -- Ensure mode is detected
    isPvpMode = detectPvpMode()

    local success = performUnequip(towerName)
    if success then
        waitForUnequip(towerName, 15, 0.1, isPvpMode)
        return true
    end
    return false, "Failed to unequip"
end





local placementControllerCache = nil
local function getPlacementController()
    local cached = placementControllerCache
    if cached then
        return cached
    end
    local moduleScript = findLoadedModule("PlacementController", true)
    if moduleScript then
        local ok, controller = pcall(require, moduleScript)
        if ok and controller then
            placementControllerCache = controller
            return controller
        end
    end
    return nil
end

local function isGamePlacementActive()
    local playerGui = localPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    local gameGui = playerGui:FindFirstChild("GameGui")
    if gameGui then
        local hotbar = gameGui:FindFirstChild("Hotbar")
        if hotbar then
            local mobileButtons = hotbar:FindFirstChild("mobileButtons")
            if mobileButtons and mobileButtons.Visible then
                return true
            end
        end
    end
    local controller = getPlacementController()
    if controller and controller.Active then
        return true
    end
    return false
end

local function waitForTowerModel(towerName, timeoutSeconds)
    local troopsFolder = replicatedStorage:FindFirstChild("Assets")
    if troopsFolder then
        troopsFolder = troopsFolder:FindFirstChild("Troops")
    end
    if not troopsFolder then
        return false
    end
    local model = troopsFolder:FindFirstChild(towerName)
    if model then
        return true
    end
    local elapsed = 0
    local interval = 0.1
    while elapsed < timeoutSeconds do
        model = troopsFolder:FindFirstChild(towerName)
        if model then
            return true
        end
        task.wait(interval)
        elapsed = elapsed + interval
    end
    return false
end

local troopsChannelCache = nil
local function getTroopsChannel()
    if troopsChannelCache then
        return troopsChannelCache
    end
    local networkModule = replicatedStorage:FindFirstChild("Resources")
        and replicatedStorage.Resources:FindFirstChild("Universal")
        and replicatedStorage.Resources.Universal:FindFirstChild("Network")
    if networkModule then
        local ok, network = pcall(require, networkModule)
        if ok and network and network.Channel then
            troopsChannelCache = network.Channel("Troops")
            return troopsChannelCache
        end
    end
    return nil
end

local function preloadTowerAsset(towerName)
    pcall(function()
        serverRemoteFunction:InvokeServer("Streaming", "Stream", {towerName})
    end)
    task.wait(0.3)
end

local function placeTowerAtPosition(towerName, position, rotation)
    local channel = getTroopsChannel()
    if channel and channel.InvokeServer then
        local placementData = {
            Position = position,
            Rotation = rotation or CFrame.new()
        }
        local result = channel:InvokeServer("Pl\208\176ce", placementData, towerName)
        return result
    end
    return serverRemoteFunction:InvokeServer("Troops", "Pl\208\176ce", {Rotation = rotation or CFrame.new(), Position = position}, towerName)
end

mouse.Button1Down:Connect(function()
    if isStackModeEnabled and stackPreviewPart then
        local basePosition = stackPreviewPart.Position

        task.spawn(function()
            if not selectedTowerName then
                return
            end
            if not waitForTowerModel(selectedTowerName, 5) then
                warn("Tower model for " .. selectedTowerName .. " not found")
                return
            end
            for i = 1, stackCount do
                local stackedPosition = Vector3.new(basePosition.X, basePosition.Y + (stackYOffset * i), basePosition.Z)
                serverRemoteFunction:InvokeServer("Troops", "Pl\208\176ce", {Rotation = CFrame.new(), Position = stackedPosition}, selectedTowerName)
                task.wait(0.2)
            end
        end)
    end
end)
