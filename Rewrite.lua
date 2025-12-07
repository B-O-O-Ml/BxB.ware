--[[
    BxB.ware | Main Hub (Universal Premium)
    Author: BXMQZ
    Updated: Dynamic Token & Advanced Combat/ESP
]]

return function(Exec, UserData, CheckToken)
    ----------------------------------------------------------------
    -- 1. Security Handshake
    ----------------------------------------------------------------
    local secretSalt = "BxB_SUPER_SECRET_SALT_CHANGE_THIS" -- **ต้องตรงกับ Key_UI**
    local datePart = os.date("%Y%m%d")
    local expectedToken = secretSalt .. "_" .. datePart

    if CheckToken ~= expectedToken then
        game.Players.LocalPlayer:Kick("Security Breach: Invalid Token.")
        return
    end

    if type(UserData) ~= "table" or not UserData.key then
        warn("Invalid User Data")
        return
    end

    ----------------------------------------------------------------
    -- 2. Services & Variables
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")
    local UserInputService = game:GetService("UserInputService")
    local TeleportService = game:GetService("TeleportService")
    local VirtualUser = game:GetService("VirtualUser")

    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera
    local Mouse = LocalPlayer:GetMouse()

    -- Load Library
    local repo = 'https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/'
    local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
    local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
    local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

    ----------------------------------------------------------------
    -- 3. UI Setup
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "",
        Icon = 84528813312016,
        Size = UDim2.fromOffset(720, 600),
        Center = true,
        AutoShow = true,
        Resizable = true,
        Compact = true
    })

    local Tabs = {
        Info = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Info</font></b>', Icon = "info", Description = "Key Status"}),
        Player = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Player</font></b>', Icon = "user", Description = "Movement & Tools"}),
        Combat = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Combat</font></b>', Icon = "swords", Description = "Aimbot & Hitbox"}),
        ESP = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Visual</font></b>', Icon = "eye", Description = "ESP System"}),
        Misc = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Misc</font></b>', Icon = "box", Description = "Tools"}),
        Game = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Game</font></b>', Icon = "joystick", Description = "Auto-Detect Module"}),
        Settings = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Settings</font></b>', Icon = "settings", Description = "Config"}),
    }

    ----------------------------------------------------------------
    -- [TAB] Info: Real-time Data
    ----------------------------------------------------------------
    local KeyGroup = Tabs.Info:AddLeftGroupbox("Key Status")
    KeyGroup:AddLabel("Key: " .. (UserData.key or "Unknown"))
    KeyGroup:AddLabel("Status: " .. (UserData.status or "Active"))
    KeyGroup:AddLabel("Role: " .. (UserData.role or "User"))
    KeyGroup:AddLabel("Note: " .. (UserData.note or "-"))
    
    local ExpireLabel = KeyGroup:AddLabel("Time Left: Calculating...")
    
    local SysGroup = Tabs.Info:AddRightGroupbox("System Info")
    SysGroup:AddLabel("Username: " .. LocalPlayer.Name)
    SysGroup:AddLabel("ID: " .. LocalPlayer.UserId)
    SysGroup:AddLabel("Game ID: " .. game.PlaceId)
    SysGroup:AddLabel("Executor: " .. (identifyexecutor and identifyexecutor() or "Unknown"))

    -- Real-time Expire Loop
    task.spawn(function()
        while true do
            if UserData.expire then
                local timeLeft = UserData.expire - os.time()
                if timeLeft > 0 then
                    local d = math.floor(timeLeft / 86400)
                    local h = math.floor((timeLeft % 86400) / 3600)
                    local m = math.floor((timeLeft % 3600) / 60)
                    local s = timeLeft % 60
                    ExpireLabel:SetText(string.format("Expires in: %dd %02dh %02dm %02ds", d, h, m, s))
                else
                    ExpireLabel:SetText("Status: Expired")
                end
            else
                ExpireLabel:SetText("Expires in: Never (Lifetime)")
            end
            task.wait(1)
        end
    end)

    ----------------------------------------------------------------
    -- [TAB] Player: Movement & Tools
    ----------------------------------------------------------------
    local MoveGroup = Tabs.Player:AddLeftGroupbox("Movement")
    MoveGroup:AddSlider('WalkSpeed', { Text = 'WalkSpeed', Default = 16, Min = 16, Max = 500, Rounding = 0 })
    MoveGroup:AddSlider('JumpPower', { Text = 'JumpPower', Default = 50, Min = 50, Max = 500, Rounding = 0 })
    
    MoveGroup:AddToggle('InfJump', { Text = 'Infinite Jump' })
    MoveGroup:AddToggle('NoClip', { Text = 'Noclip' })
    
    local FlyToggle = MoveGroup:AddToggle('Fly', { Text = 'Fly Mode' })
    MoveGroup:AddSlider('FlySpeed', { Text = 'Fly Speed', Default = 50, Min = 10, Max = 200 })

    -- Logic Hook
    Options.WalkSpeed:OnChanged(function() if LocalPlayer.Character then LocalPlayer.Character.Humanoid.WalkSpeed = Options.WalkSpeed.Value end end)
    Options.JumpPower:OnChanged(function() if LocalPlayer.Character then LocalPlayer.Character.Humanoid.JumpPower = Options.JumpPower.Value end end)

    UserInputService.JumpRequest:Connect(function()
        if Toggles.InfJump.Value and LocalPlayer.Character then
            LocalPlayer.Character.Humanoid:ChangeState("Jumping")
        end
    end)

    RunService.Stepped:Connect(function()
        if Toggles.NoClip.Value and LocalPlayer.Character then
            for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") then v.CanCollide = false end
            end
        end
    end)

    -- Player Tools
    local ToolGroup = Tabs.Player:AddRightGroupbox("Tools")
    ToolGroup:AddInput('TpUser', { Default = '', Placeholder = 'Username part...', Text = 'Teleport to Player' })
    ToolGroup:AddButton('Teleport', function()
        local targetName = Options.TpUser.Value
        for _, v in pairs(Players:GetPlayers()) do
            if string.find(string.lower(v.Name), string.lower(targetName)) then
                if v.Character and v.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character then
                    LocalPlayer.Character.HumanoidRootPart.CFrame = v.Character.HumanoidRootPart.CFrame
                end
                break
            end
        end
    end)
    
    ToolGroup:AddSlider('FOV', { Text = 'Field of View', Default = 70, Min = 30, Max = 120, Callback = function(v) Camera.FieldOfView = v end })

    ----------------------------------------------------------------
    -- [TAB] Combat: Advanced Aimbot
    ----------------------------------------------------------------
    local AimMain = Tabs.Combat:AddLeftGroupbox("Aimbot Settings")
    AimMain:AddToggle('AimEnabled', { Text = 'Enable Aimbot', Default = false })
    AimMain:AddDropdown('AimMode', { Values = {'Hold (Right Click)', 'Auto Lock'}, Default = 1, Multi = false, Text = 'Aim Mode' })
    AimMain:AddDropdown('AimPart', { Values = {'Head', 'Torso', 'Random'}, Default = 1, Multi = false, Text = 'Target Part' })
    
    AimMain:AddSlider('AimSmooth', { Text = 'Smoothness', Default = 5, Min = 1, Max = 20, Rounding = 1 })
    AimMain:AddSlider('AimRadius', { Text = 'FOV Radius', Default = 100, Min = 10, Max = 500 })
    
    local AimCalc = Tabs.Combat:AddRightGroupbox("Calculation & Filters")
    AimCalc:AddToggle('AimWallCheck', { Text = 'Wall Check', Default = true })
    AimCalc:AddToggle('AimTeamCheck', { Text = 'Team Check', Default = true })
    AimCalc:AddSlider('HitChance', { Text = 'Hit Chance %', Default = 100, Min = 1, Max = 100 })
    AimCalc:AddSlider('HeadPercent', { Text = 'Head Shot %', Default = 50, Min = 0, Max = 100, Tooltip = 'If "Random" selected, how often to hit Head' })

    -- Aimbot Logic
    local currentTarget = nil
    
    local function getClosestPlayer()
        local closest = nil
        local shortestDist = Options.AimRadius.Value
        local mousePos = UserInputService:GetMouseLocation()

        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
                
                -- Team Check
                if Toggles.AimTeamCheck.Value and plr.Team == LocalPlayer.Team then continue end

                local pos, onScreen = Camera:WorldToViewportPoint(plr.Character.HumanoidRootPart.Position)
                if onScreen then
                    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                    if dist < shortestDist then
                        -- Wall Check
                        if Toggles.AimWallCheck.Value then
                            local ray = Ray.new(Camera.CFrame.Position, (plr.Character.Head.Position - Camera.CFrame.Position).Unit * 500)
                            local hit, _ = Workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character})
                            if hit and not hit:IsDescendantOf(plr.Character) then continue end
                        end
                        
                        shortestDist = dist
                        closest = plr
                    end
                end
            end
        end
        return closest
    end

    local function getTargetPart()
        if Options.AimPart.Value == 'Head' then return "Head" end
        if Options.AimPart.Value == 'Torso' then return "HumanoidRootPart" end
        
        -- Percentage Logic
        if math.random(1, 100) <= Options.HeadPercent.Value then
            return "Head"
        else
            return "HumanoidRootPart" -- Body
        end
    end

    RunService.RenderStepped:Connect(function()
        if Toggles.AimEnabled.Value then
            local isAiming = (Options.AimMode.Value == 'Auto Lock') or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            
            if isAiming then
                -- Chance Check
                if math.random(1, 100) > Options.HitChance.Value then return end

                currentTarget = getClosestPlayer()
                if currentTarget and currentTarget.Character then
                    local partName = getTargetPart()
                    local targetPos = currentTarget.Character[partName].Position
                    
                    local currentCFrame = Camera.CFrame
                    local targetCFrame = CFrame.new(currentCFrame.Position, targetPos)
                    
                    -- Smoothness
                    Camera.CFrame = currentCFrame:Lerp(targetCFrame, 1 / Options.AimSmooth.Value)
                end
            else
                currentTarget = nil
            end
        end
    end)
    
    -- Draw FOV Circle
    local FOVCircle = Drawing.new("Circle")
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Thickness = 1
    FOVCircle.NumSides = 60
    FOVCircle.Filled = false
    FOVCircle.Transparency = 1
    
    RunService.RenderStepped:Connect(function()
        FOVCircle.Visible = Toggles.AimEnabled.Value
        FOVCircle.Radius = Options.AimRadius.Value
        FOVCircle.Position = UserInputService:GetMouseLocation()
    end)

    ----------------------------------------------------------------
    -- [TAB] ESP: Visuals (Advanced)
    ----------------------------------------------------------------
    local ESPMain = Tabs.ESP:AddLeftGroupbox("ESP Settings")
    ESPMain:AddToggle('ESP_Box', { Text = 'Box ESP', Default = false })
    ESPMain:AddToggle('ESP_Name', { Text = 'Names', Default = false })
    ESPMain:AddToggle('ESP_Health', { Text = 'Health Bar', Default = false })
    ESPMain:AddToggle('ESP_Chams', { Text = 'Chams (Highlight)', Default = false })
    
    local ESPColor = Tabs.ESP:AddRightGroupbox("Colors & Checks")
    ESPColor:AddToggle('ESP_TeamCheck', { Text = 'Team Check', Default = true })
    ESPColor:AddToggle('ESP_WallCheck', { Text = 'Wall Check (Color)', Default = true, Tooltip = 'Green=Visible, Red=Hidden' })
    ESPColor:AddColorPicker('Color_Vis', { Default = Color3.fromRGB(0, 255, 0), Title = 'Visible Color' })
    ESPColor:AddColorPicker('Color_Hid', { Default = Color3.fromRGB(255, 0, 0), Title = 'Hidden Color' })

    -- ESP Loop (Efficient)
    local ESP_Folder = Instance.new("Folder", game.CoreGui)
    ESP_Folder.Name = "BxB_ESP"

    local function CreateHighlight(model)
        if model:FindFirstChild("BxB_Highlight") then return model.BxB_Highlight end
        local hl = Instance.new("Highlight")
        hl.Name = "BxB_Highlight"
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.Parent = model
        return hl
    end

    local function isVisible(part)
        local origin = Camera.CFrame.Position
        local direction = (part.Position - origin).Unit * (part.Position - origin).Magnitude
        local ray = Ray.new(origin, direction)
        local hit, _ = Workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character})
        return hit and hit:IsDescendantOf(part.Parent)
    end

    task.spawn(function()
        while true do
            task.wait(0.1) -- Refresh Rate
            for _, plr in pairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                    
                    -- Cleanup if disabled
                    local hl = plr.Character:FindFirstChild("BxB_Highlight")
                    local bg = plr.Character:FindFirstChild("BxB_Info")

                    if not Toggles.ESP_Chams.Value and hl then hl:Destroy() end
                    if not Toggles.ESP_Name.Value and bg then bg:Destroy() end
                    
                    -- Check Team
                    if Toggles.ESP_TeamCheck.Value and plr.Team == LocalPlayer.Team then 
                        if hl then hl:Destroy() end
                        continue 
                    end

                    -- Chams Logic
                    if Toggles.ESP_Chams.Value then
                        local h = CreateHighlight(plr.Character)
                        local visible = true
                        if Toggles.ESP_WallCheck.Value then
                            visible = isVisible(plr.Character.HumanoidRootPart)
                        end
                        
                        h.FillColor = visible and Options.Color_Vis.Value or Options.Color_Hid.Value
                        h.OutlineColor = visible and Options.Color_Vis.Value or Options.Color_Hid.Value
                    end

                    -- Name/Info Logic (Billboard)
                    if Toggles.ESP_Name.Value or Toggles.ESP_Health.Value then
                        if not bg then
                            bg = Instance.new("BillboardGui")
                            bg.Name = "BxB_Info"
                            bg.Adornee = plr.Character.Head
                            bg.Size = UDim2.new(0, 100, 0, 50)
                            bg.StudsOffset = Vector3.new(0, 2, 0)
                            bg.AlwaysOnTop = true
                            bg.Parent = plr.Character
                            
                            local nameLbl = Instance.new("TextLabel", bg)
                            nameLbl.Size = UDim2.new(1, 0, 0.5, 0)
                            nameLbl.BackgroundTransparency = 1
                            nameLbl.TextColor3 = Color3.new(1,1,1)
                            nameLbl.TextStrokeTransparency = 0
                            nameLbl.Name = "NameLbl"
                            
                            local hpLbl = Instance.new("TextLabel", bg)
                            hpLbl.Size = UDim2.new(1, 0, 0.5, 0)
                            hpLbl.Position = UDim2.new(0, 0, 0.5, 0)
                            hpLbl.BackgroundTransparency = 1
                            hpLbl.TextColor3 = Color3.new(0,1,0)
                            hpLbl.TextStrokeTransparency = 0
                            hpLbl.Name = "HpLbl"
                        end
                        
                        if bg:FindFirstChild("NameLbl") then 
                            bg.NameLbl.Text = Toggles.ESP_Name.Value and plr.Name or "" 
                        end
                        
                        if bg:FindFirstChild("HpLbl") and Toggles.ESP_Health.Value then
                            local hp = math.floor(plr.Character.Humanoid.Health)
                            local maxHp = plr.Character.Humanoid.MaxHealth
                            bg.HpLbl.Text = hp .. " / " .. maxHp
                            bg.HpLbl.TextColor3 = Color3.fromHSV((hp/maxHp)*0.3, 1, 1) -- Green to Red
                        else
                            bg.HpLbl.Text = ""
                        end
                    end
                end
            end
        end
    end)

    ----------------------------------------------------------------
    -- [TAB] Misc
    ----------------------------------------------------------------
    local MiscMain = Tabs.Misc:AddLeftGroupbox("General")
    MiscMain:AddToggle('AntiAFK', { Text = 'Anti-AFK', Default = true })
    
    MiscMain:AddButton('Rejoin Server', function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
    
    local HopGroup = Tabs.Misc:AddRightGroupbox("Server Hop")
    HopGroup:AddButton('Hop (Low Player)', function()
        Library:Notify("Scanning for low player servers...", 5)
        -- ใส่โค้ด Server Hop API ตรงนี้ (ย่อไว้)
    end)
    
    -- Anti AFK
    task.spawn(function()
        VirtualUser:CaptureController()
        LocalPlayer.Idled:Connect(function()
            if Toggles.AntiAFK.Value then
                VirtualUser:Button2Down(Vector2.new(0,0), Workspace.CurrentCamera.CFrame)
                task.wait(1)
                VirtualUser:Button2Up(Vector2.new(0,0), Workspace.CurrentCamera.CFrame)
                Library:Notify("Anti-AFK Triggered", 3)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- [TAB] Game: Auto Detect
    ----------------------------------------------------------------
    local GameGroup = Tabs.Game:AddLeftGroupbox("Game Detection")
    local CurrentID = game.PlaceId
    
    -- Game Database
    local GameDB = {
        [2753915549] = { Name = "Blox Fruits", Url = "URL_TO_BLOXFRUIT_SCRIPT" },
        [4442272183] = { Name = "Blox Fruits", Url = "URL_TO_BLOXFRUIT_SCRIPT" },
        [7449423635] = { Name = "Blox Fruits", Url = "URL_TO_BLOXFRUIT_SCRIPT" },
        [286090429]  = { Name = "Arsenal", Url = "URL_TO_ARSENAL_SCRIPT" },
        [155615604]  = { Name = "Prison Life", Url = "URL_TO_PRISON_SCRIPT" },
    }
    
    local Detected = GameDB[CurrentID]
    
    if Detected then
        GameGroup:AddLabel('Detected: <font color="#00FF00">' .. Detected.Name .. '</font>')
        GameGroup:AddButton('Load ' .. Detected.Name .. ' Module', function()
            Library:Notify("Loading Module...", 3)
            loadstring(game:HttpGet(Detected.Url))()
        end)
    else
        GameGroup:AddLabel('Detected: <font color="#FFFF00">Universal</font>')
        GameGroup:AddLabel('No specific module found for this game.')
        GameGroup:AddLabel('Universal scripts are active.')
    end

    ----------------------------------------------------------------
    -- [TAB] Settings
    ----------------------------------------------------------------
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    
    ThemeManager:SetFolder("BxB_Ware")
    SaveManager:SetFolder("BxB_Ware/Configs")
    
    SaveManager:BuildConfigSection(Tabs.Settings)
    ThemeManager:ApplyToTab(Tabs.Settings)

    Window:SelectTab(1)
    Library:Notify("BxB.ware Premium Loaded!", 5)
end
