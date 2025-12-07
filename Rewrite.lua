--[[
    BxB.ware | Universal Premium Hub
    Library: Linoria / Obsidian
    Author: BXMQZ
]]

return function(Exec, UserData, CheckToken)
    ----------------------------------------------------------------
    -- 1. Security Handshake (ระบบเช็ค 2 ชั้น)
    ----------------------------------------------------------------
    local secretSalt = "BxB_SUPER_SECRET_SALT_CHANGE_THIS" -- **ต้องตรงกับ Key_UI**
    local datePart = os.date("%Y%m%d")
    local expectedToken = secretSalt .. "_" .. datePart

    if CheckToken ~= expectedToken then
        warn("[BxB Security] Token Mismatch!")
        if game.Players.LocalPlayer then game.Players.LocalPlayer:Kick("Security Breach: Invalid Token") end
        return
    end

    ----------------------------------------------------------------
    -- 2. Services & Variables
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local Camera = Workspace.CurrentCamera
    local LocalPlayer = Players.LocalPlayer
    local Mouse = LocalPlayer:GetMouse()

    -- Load Library (Linoria/Obsidian)
    local repo = 'https://raw.githubusercontent.com/violnes/LinoriaLib/main/'
    local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
    local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
    local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

    ----------------------------------------------------------------
    -- 3. Window Construction
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "BxB.ware | Universal Premium",
        Center = true,
        AutoShow = true,
        TabPadding = 8,
        MenuFadeTime = 0.2
    })

    local Tabs = {
        Info = Window:AddTab('Info'),
        Player = Window:AddTab('Player'),
        Combat = Window:AddTab('Combat'),
        Visuals = Window:AddTab('Visuals'),
        Misc = Window:AddTab('Misc'),
        Game = Window:AddTab('Game'),
        Settings = Window:AddTab('Settings'),
    }

    ----------------------------------------------------------------
    -- [TAB] Info: Detailed Key Status
    ----------------------------------------------------------------
    local InfoGroup = Tabs.Info:AddLeftGroupbox('Key Information')
    local SystemGroup = Tabs.Info:AddRightGroupbox('System Status')

    -- Key Data
    InfoGroup:AddLabel('Key: ' .. (UserData.key or "Unknown"))
    InfoGroup:AddLabel('Status: ' .. (UserData.status or "Active"))
    InfoGroup:AddLabel('Role: ' .. (UserData.role or "Free User"))
    InfoGroup:AddLabel('Owner: ' .. (UserData.owner or "BXMQZ")) -- ใส่ชื่อคุณ
    InfoGroup:AddLabel('Note: ' .. (UserData.note or "None"))
    
    local ExpireLabel = InfoGroup:AddLabel('Expire: Calculating...')
    
    -- System Data
    SystemGroup:AddLabel('Game ID: ' .. game.PlaceId)
    SystemGroup:AddLabel('Username: ' .. LocalPlayer.Name)
    SystemGroup:AddLabel('Display Name: ' .. LocalPlayer.DisplayName)
    SystemGroup:AddLabel('Executor: ' .. (identifyexecutor and identifyexecutor() or "Unknown"))
    
    local TimeLabel = SystemGroup:AddLabel('Time: ...')

    -- Realtime Update Loop
    task.spawn(function()
        while true do
            TimeLabel:SetText('Time: ' .. os.date("%X"))
            
            if UserData.expire then
                local diff = UserData.expire - os.time()
                if diff > 0 then
                    local d = math.floor(diff / 86400)
                    local h = math.floor((diff % 86400) / 3600)
                    local m = math.floor((diff % 3600) / 60)
                    ExpireLabel:SetText(string.format('Expire: %dd %02dh %02dm', d, h, m))
                else
                    ExpireLabel:SetText('Expire: Expired')
                end
            else
                ExpireLabel:SetText('Expire: Lifetime / Unlimited')
            end
            task.wait(1)
        end
    end)

    ----------------------------------------------------------------
    -- [TAB] Player: Movement & Tools
    ----------------------------------------------------------------
    local P_Main = Tabs.Player:AddLeftGroupbox('Movement')
    local P_Tool = Tabs.Player:AddRightGroupbox('Tools')

    P_Main:AddSlider('WalkSpeed', { Text = 'Walk Speed', Default = 16, Min = 16, Max = 500, Rounding = 0, Callback = function(v) 
        if LocalPlayer.Character then LocalPlayer.Character.Humanoid.WalkSpeed = v end 
    end})
    
    P_Main:AddSlider('JumpPower', { Text = 'Jump Power', Default = 50, Min = 50, Max = 500, Rounding = 0, Callback = function(v) 
        if LocalPlayer.Character then LocalPlayer.Character.Humanoid.JumpPower = v end 
    end})

    P_Main:AddToggle('InfJump', { Text = 'Infinite Jump', Default = false })
    
    local FlyToggle = P_Main:AddToggle('Fly', { Text = 'Fly Mode', Default = false })
    -- (Simple Fly Logic would go here, omitting for brevity to focus on specific requests)

    -- Spectate System
    local SpectateInput = P_Tool:AddInput('SpectateUser', { Default = '', Placeholder = 'Username', Text = 'Spectate Player', Finished = true })
    
    P_Tool:AddButton('Spectate', function()
        local targetName = SpectateInput.Value
        for _, v in pairs(Players:GetPlayers()) do
            if string.sub(v.Name:lower(), 1, #targetName) == targetName:lower() then
                Camera.CameraSubject = v.Character.Humanoid
                Library:Notify("Spectating: " .. v.Name)
                return
            end
        end
        Camera.CameraSubject = LocalPlayer.Character.Humanoid
        Library:Notify("Reset View")
    end)
    
    P_Tool:AddButton('Stop Spectating', function()
        Camera.CameraSubject = LocalPlayer.Character.Humanoid
    end)

    P_Tool:AddInput('TPUser', { Default = '', Placeholder = 'Username', Text = 'Teleport To', Finished = true, Callback = function(val)
        for _, v in pairs(Players:GetPlayers()) do
            if string.sub(v.Name:lower(), 1, #val) == val:lower() and v.Character and v.Character.HumanoidRootPart then
                LocalPlayer.Character.HumanoidRootPart.CFrame = v.Character.HumanoidRootPart.CFrame * CFrame.new(0,0,3)
            end
        end
    end})

    ----------------------------------------------------------------
    -- [TAB] Combat: Advanced Aimbot
    ----------------------------------------------------------------
    local C_Main = Tabs.Combat:AddLeftGroupbox('Aimbot')
    local C_Set = Tabs.Combat:AddRightGroupbox('Settings')
    local C_List = Tabs.Combat:AddRightGroupbox('Whitelist')

    -- Variables
    local AimSettings = { Enabled = false, AimPart = "Head", Smooth = 1, Predict = 0, Chance = 100 }
    
    C_Main:AddToggle('AimEnabled', { Text = 'Enable Aimbot', Default = false, Callback = function(v) AimSettings.Enabled = v end })
    C_Main:AddDropdown('AimMode', { Values = { 'Hold Right Click', 'Auto Lock' }, Default = 1, Multi = false, Text = 'Trigger Mode' })
    C_Main:AddDropdown('AimPart', { Values = { 'Head', 'HumanoidRootPart', 'Random' }, Default = 1, Multi = false, Text = 'Target Part', Callback = function(v) AimSettings.AimPart = v end })
    
    C_Set:AddSlider('AimSmooth', { Text = 'Smoothness', Default = 1, Min = 1, Max = 20, Rounding = 1, Callback = function(v) AimSettings.Smooth = v end })
    C_Set:AddSlider('AimPredict', { Text = 'Prediction', Default = 0, Min = 0, Max = 10, Rounding = 1, Callback = function(v) AimSettings.Predict = v end })
    C_Set:AddSlider('HitChance', { Text = 'Hit Chance (%)', Default = 100, Min = 0, Max = 100, Rounding = 0, Callback = function(v) AimSettings.Chance = v end })
    
    C_Set:AddToggle('TeamCheck', { Text = 'Team Check', Default = true })
    C_Set:AddToggle('WallCheck', { Text = 'Wall Check', Default = true })

    -- Aimbot Core Logic
    local function IsVisible(target, origin)
        if not Toggles.WallCheck.Value then return true end
        local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {LocalPlayer.Character}
        local dir = (target.Position - origin).Unit * (target.Position - origin).Magnitude
        local res = Workspace:Raycast(origin, dir, params)
        return res == nil or res.Instance:IsDescendantOf(target.Parent)
    end

    local function GetTarget()
        local bestTarget = nil
        local bestDist = math.huge
        local mousePos = Vector2.new(Mouse.X, Mouse.Y)

        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
                if Toggles.TeamCheck.Value and plr.Team == LocalPlayer.Team then continue end
                
                local partName = AimSettings.AimPart
                if partName == "Random" then
                    local parts = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"}
                    partName = parts[math.random(1, #parts)]
                end
                
                local targetPart = plr.Character:FindFirstChild(partName)
                if targetPart then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        if IsVisible(targetPart, Camera.CFrame.Position) then
                            local dist = (mousePos - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                bestTarget = targetPart
                            end
                        end
                    end
                end
            end
        end
        return bestTarget
    end

    RunService.RenderStepped:Connect(function()
        if not AimSettings.Enabled then return end
        
        local isAiming = (Options.AimMode.Value == 'Auto Lock') or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        
        if isAiming then
            local target = GetTarget()
            if target then
                if math.random(1, 100) <= AimSettings.Chance then
                    local predictedPos = target.Position + (target.Velocity * (AimSettings.Predict / 100))
                    local lookCFrame = CFrame.new(Camera.CFrame.Position, predictedPos)
                    Camera.CFrame = Camera.CFrame:Lerp(lookCFrame, 1 / AimSettings.Smooth)
                end
            end
        end
    end)

    ----------------------------------------------------------------
    -- [TAB] Visuals: Drawing API ESP
    ----------------------------------------------------------------
    local V_Main = Tabs.Visuals:AddLeftGroupbox('ESP Elements')
    local V_Set = Tabs.Visuals:AddRightGroupbox('Settings')

    V_Main:AddToggle('ESP_Box', { Text = 'Box (2D)', Default = false })
    V_Main:AddToggle('ESP_Skel', { Text = 'Skeleton', Default = false })
    V_Main:AddToggle('ESP_Trace', { Text = 'Tracers', Default = false })
    V_Main:AddToggle('ESP_Name', { Text = 'Name Tag', Default = false })
    
    V_Set:AddColorPicker('ESP_VisColor', { Default = Color3.fromRGB(0, 255, 0), Title = 'Visible Color' })
    V_Set:AddColorPicker('ESP_HidColor', { Default = Color3.fromRGB(255, 0, 0), Title = 'Hidden Color' })
    V_Set:AddToggle('ESP_WallCheck', { Text = 'Color Wall Check', Default = true })

    -- ESP Drawing Cache
    local Drawings = {} 
    
    local function CreateDrawing(type, props)
        local d = Drawing.new(type)
        for k, v in pairs(props) do d[k] = v end
        return d
    end

    local function RemoveDrawing(plr)
        if Drawings[plr] then
            for _, d in pairs(Drawings[plr]) do d:Remove() end
            Drawings[plr] = nil
        end
    end

    RunService.RenderStepped:Connect(function()
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                if not Drawings[plr] then Drawings[plr] = { 
                    Box = CreateDrawing("Square", {Thickness=1, Filled=false}),
                    Trace = CreateDrawing("Line", {Thickness=1}),
                    Name = CreateDrawing("Text", {Size=16, Center=true, Outline=true}),
                    -- Skeleton lines... (simplified for brevity, usually needs 10+ lines)
                } end
                
                local d = Drawings[plr]
                local char = plr.Character
                
                if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 and (not Toggles.TeamCheck.Value or plr.Team ~= LocalPlayer.Team) then
                    local root = char.HumanoidRootPart
                    local head = char:FindFirstChild("Head")
                    local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                    
                    local isVis = false
                    if Toggles.ESP_WallCheck.Value then
                        isVis = IsVisible(head or root, Camera.CFrame.Position)
                    else
                        isVis = true
                    end
                    local color = isVis and Options.ESP_VisColor.Value or Options.ESP_HidColor.Value

                    if onScreen then
                        -- Box Logic
                        if Toggles.ESP_Box.Value then
                            d.Box.Visible = true
                            d.Box.Color = color
                            d.Box.Size = Vector2.new(2000 / screenPos.Z, 2500 / screenPos.Z)
                            d.Box.Position = Vector2.new(screenPos.X - d.Box.Size.X/2, screenPos.Y - d.Box.Size.Y/2)
                        else d.Box.Visible = false end

                        -- Tracer Logic
                        if Toggles.ESP_Trace.Value then
                            d.Trace.Visible = true
                            d.Trace.Color = color
                            d.Trace.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y) -- Bottom Middle
                            d.Trace.To = Vector2.new(screenPos.X, screenPos.Y)
                        else d.Trace.Visible = false end

                        -- Name Logic
                        if Toggles.ESP_Name.Value then
                            d.Name.Visible = true
                            d.Name.Text = plr.Name .. " [" .. math.floor((root.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude) .. "m]"
                            d.Name.Color = color
                            d.Name.Position = Vector2.new(screenPos.X, screenPos.Y - (d.Box.Size.Y/2) - 15)
                        else d.Name.Visible = false end

                    else
                        d.Box.Visible = false; d.Trace.Visible = false; d.Name.Visible = false
                    end
                else
                    d.Box.Visible = false; d.Trace.Visible = false; d.Name.Visible = false
                end
            end
        end
    end)
    
    Players.PlayerRemoving:Connect(RemoveDrawing)

    ----------------------------------------------------------------
    -- [TAB] Misc
    ----------------------------------------------------------------
    local M_Gen = Tabs.Misc:AddLeftGroupbox('Server')
    
    M_Gen:AddToggle('AntiAFK', { Text = 'Anti AFK', Default = true })
    M_Gen:AddButton('Rejoin Server', function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    M_Gen:AddButton('Server Hop (Low Users)', function()
        -- Server Hop Logic (Simplified)
        local servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
        for _, s in pairs(servers.data) do
            if s.playing < s.maxPlayers and s.id ~= game.JobId then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                break
            end
        end
    end)
    
    -- Anti AFK Loop
    LocalPlayer.Idled:Connect(function()
        if Toggles.AntiAFK.Value then
            game:GetService("VirtualUser"):CaptureController()
            game:GetService("VirtualUser"):ClickButton2(Vector2.new())
        end
    end)

    ----------------------------------------------------------------
    -- [TAB] Game: Universal Module Loader
    ----------------------------------------------------------------
    local GameGroup = Tabs.Game:AddLeftGroupbox('Module Loader')
    
    local function LoadGameSpecifics()
        local pid = game.PlaceId
        local url = nil
        local gameName = "Universal"

        if pid == 2753915549 or pid == 4442272183 then
            gameName = "Blox Fruits"
            -- url = "https://raw.githubusercontent.com/.../BloxFruits.lua"
        elseif pid == 155615604 then
            gameName = "Prison Life"
        end
        
        GameGroup:AddLabel('Detected: ' .. gameName)
        
        if url then
            GameGroup:AddButton('Load '..gameName..' Script', function()
                loadstring(game:HttpGet(url))()
            end)
        else
            GameGroup:AddLabel('No specific module found.')
            GameGroup:AddLabel('Universal features are active.')
        end
    end
    
    LoadGameSpecifics()

    ----------------------------------------------------------------
    -- [TAB] Settings
    ----------------------------------------------------------------
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetFolder('BxB_Ware/Main')
    ThemeManager:SetFolder('BxB_Ware')
    
    SaveManager:BuildConfigSection(Tabs.Settings)
    ThemeManager:ApplyToTab(Tabs.Settings)

    Library:Notify("BxB.ware Premium Loaded Successfully!", 5)
end
