-- STATUS:online
-- STATUS_MSG:Main hub Premium is live

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- Security & Validation
    ----------------------------------------------------------------
    local EXPECTED_KEYCHECK = "BxB.ware-universal-private-*&^%$#$*#%&@#"
    if keycheck ~= EXPECTED_KEYCHECK then return end
    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then return end

    ----------------------------------------------------------------
    -- Services & Locals
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Stats = game:GetService("Stats")
    local TeleportService = game:GetService("TeleportService")
    local MarketplaceService = game:GetService("MarketplaceService")
    local Lighting = game:GetService("Lighting")
    local Camera = workspace.CurrentCamera
    local Mouse = Players.LocalPlayer:GetMouse()

    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then return end

    ----------------------------------------------------------------
    -- Library Setup (Obsidian/Linoria)
    ----------------------------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

    if ThemeManager then ThemeManager:SetLibrary(Library) end
    if SaveManager then SaveManager:SetLibrary(Library) end

    local Options = Library.Options
    local Toggles = Library.Toggles

    ----------------------------------------------------------------
    -- Role System (Core Upgrade 1)
    ----------------------------------------------------------------
    local role = tostring(keydata.role or "user"):lower()
    
    -- Hierarchy: Free < User < Premium < VIP < Staff < Owner
    local RolePriority = {
        free = 0,
        user = 1, trial = 1,
        premium = 2, reseller = 2,
        vip = 3,
        staff = 4,
        owner = 5
    }

    local function GetRolePriority(r)
        return RolePriority[r:lower()] or 0
    end

    local function RoleAtLeast(req)
        return GetRolePriority(role) >= GetRolePriority(req)
    end

    local function Notify(msg, dur)
        Library:Notify(tostring(msg), dur or 3)
    end

    -- Helper to lock toggles if role not met
    local function CheckRole(req, toggleName)
        if not RoleAtLeast(req) then
            if Toggles[toggleName] and Toggles[toggleName].Value then
                Toggles[toggleName]:SetValue(false)
            end
            Notify("🔒 Requires " .. req:upper() .. " rank or higher!", 3)
            return false
        end
        return true
    end

    ----------------------------------------------------------------
    -- Window Creation
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "BxB.ware | Premium Hub",
        Icon = 84528813312016,
        Center = true,
        AutoShow = true,
        Resizable = true,
        Compact = true,
        Size = UDim2.fromOffset(750, 600)
    })

    local Tabs = {
        Info = Window:AddTab({ Name = "Info", Icon = "info" }),
        Player = Window:AddTab({ Name = "Player", Icon = "user" }),
        Combat = Window:AddTab({ Name = "Combat", Icon = "crosshair" }),
        ESP = Window:AddTab({ Name = "Visuals", Icon = "eye" }),
        Settings = Window:AddTab({ Name = "Settings", Icon = "settings" })
    }

    ----------------------------------------------------------------
    -- Variables & State
    ----------------------------------------------------------------
    local State = {
        -- Player
        SpinBot = false,
        SpinSpeed = 20,
        AntiAim = false,
        AutoRun = false,
        ClickTP = false,
        
        -- ESP
        Skeleton = false,
        LookTracer = false,
    }

    ----------------------------------------------------------------
    -- Tab: Player (Upgrade 2)
    ----------------------------------------------------------------
    local PlrMain = Tabs.Player:AddLeftGroupbox("Movement")
    local PlrExtra = Tabs.Player:AddRightGroupbox("Utilities")

    -- WalkSpeed & JumpPower with Reset Fix
    PlrMain:AddToggle("WS_Toggle", { Text = "Custom WalkSpeed", Default = false }):OnChanged(function(v)
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
             hum.WalkSpeed = v and Options.WS_Slider.Value or 16
        end
    end)
    PlrMain:AddSlider("WS_Slider", { Text = "Value", Default = 16, Min = 16, Max = 300, Rounding = 0 }):OnChanged(function(v)
        if Toggles.WS_Toggle.Value then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = v end
        end
    end)

    PlrMain:AddToggle("JP_Toggle", { Text = "Custom JumpPower", Default = false }):OnChanged(function(v)
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
             hum.JumpPower = v and Options.JP_Slider.Value or 50
        end
    end)
    PlrMain:AddSlider("JP_Slider", { Text = "Value", Default = 50, Min = 50, Max = 500, Rounding = 0 }):OnChanged(function(v)
        if Toggles.JP_Toggle.Value then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
            if hum then hum.JumpPower = v end
        end
    end)

    PlrMain:AddToggle("AutoRun_Toggle", { Text = "Auto Run", Default = false }):OnChanged(function(v)
        State.AutoRun = v
    end)

    -- VIP Features
    PlrMain:AddDivider()
    PlrMain:AddLabel("<b>VIP Features</b>")
    
    PlrMain:AddToggle("SpinBot_Toggle", { Text = "SpinBot (Blatant)", Default = false }):OnChanged(function(v)
        if not CheckRole("vip", "SpinBot_Toggle") then return end
        State.SpinBot = v
    end)
    
    PlrMain:AddSlider("SpinSpeed", { Text = "Spin Speed", Default = 20, Min = 1, Max = 100, Rounding = 0 })

    PlrMain:AddToggle("AntiAim_Toggle", { Text = "Anti-Aim (LookDown)", Default = false }):OnChanged(function(v)
        if not CheckRole("vip", "AntiAim_Toggle") then return end
        State.AntiAim = v
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum then hum.AutoRotate = not v end
    end)

    -- Utilities
    PlrExtra:AddToggle("ClickTP_Toggle", { Text = "Ctrl + Click TP", Default = false }):OnChanged(function(v)
        if not CheckRole("user", "ClickTP_Toggle") then return end
        State.ClickTP = v
    end)

    ----------------------------------------------------------------
    -- Tab: Combat (Upgrade 3 - Advanced Aimbot)
    ----------------------------------------------------------------
    local AimMain = Tabs.Combat:AddLeftGroupbox("Aimbot Settings")
    local AimSettingsBox = Tabs.Combat:AddRightGroupbox("Targeting Weights")

    AimMain:AddToggle("Aim_Enabled", { Text = "Enable Aimbot", Default = false })
    
    AimMain:AddDropdown("Aim_Part", {
        Text = "Target Selection",
        Default = "Head",
        Values = { "Head", "Chest", "Closest", "RandomWeighted" }
    })

    AimMain:AddSlider("Aim_HitChance", { Text = "Hit Chance (%)", Default = 100, Min = 0, Max = 100, Rounding = 0 })

    -- Weighted Sliders (Role Locked)
    AimSettingsBox:AddLabel("<b>RandomWeighted Settings (Premium)</b>")
    AimSettingsBox:AddSlider("Weight_Head", { Text = "Head Chance", Default = 50, Min = 0, Max = 100, Rounding = 0 })
    AimSettingsBox:AddSlider("Weight_Chest", { Text = "Chest Chance", Default = 30, Min = 0, Max = 100, Rounding = 0 })
    AimSettingsBox:AddSlider("Weight_Limbs", { Text = "Arms/Legs Chance", Default = 20, Min = 0, Max = 100, Rounding = 0 })

    local function GetWeightedTarget(char)
        if not RoleAtLeast("premium") then return char:FindFirstChild("Head") end

        local head = Options.Weight_Head.Value
        local chest = Options.Weight_Chest.Value
        local limbs = Options.Weight_Limbs.Value
        local total = head + chest + limbs
        local rand = math.random(0, total)

        if rand <= head then return char:FindFirstChild("Head")
        elseif rand <= head + chest then return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        else return char:FindFirstChild("RightHand") or char:FindFirstChild("LeftFoot") end
    end

    ----------------------------------------------------------------
    -- Tab: ESP & Visuals (Upgrade 4)
    ----------------------------------------------------------------
    local ESPMain = Tabs.ESP:AddLeftGroupbox("ESP Main")
    local ESPStyle = Tabs.ESP:AddRightGroupbox("Style & Colors")

    ESPMain:AddToggle("ESP_Enabled", { Text = "Master Switch", Default = false })
    ESPMain:AddToggle("ESP_Box", { Text = "Box 2D", Default = true })
    ESPMain:AddToggle("ESP_Name", { Text = "Names", Default = true })
    ESPMain:AddToggle("ESP_Health", { Text = "Health Bar", Default = true })
    ESPMain:AddToggle("ESP_Skeleton", { Text = "Skeleton", Default = false })
    ESPMain:AddToggle("ESP_Tracers", { Text = "Snaplines", Default = false })
    ESPMain:AddToggle("ESP_Chams", { Text = "Chams (Highlight)", Default = false })

    -- Styling
    ESPStyle:AddLabel("Colors")
    ESPStyle:AddColorPicker("Color_Box", { Default = Color3.fromRGB(255, 255, 255), Title = "Box Color" })
    ESPStyle:AddColorPicker("Color_Skeleton", { Default = Color3.fromRGB(255, 255, 255), Title = "Skeleton Color" })
    ESPStyle:AddColorPicker("Color_Chams", { Default = Color3.fromRGB(255, 0, 0), Title = "Chams Fill" })
    ESPStyle:AddColorPicker("Color_ChamsOut", { Default = Color3.fromRGB(255, 255, 255), Title = "Chams Outline" })

    ESPStyle:AddDivider()
    ESPStyle:AddSlider("ESP_TextSize", { Text = "Text Size", Default = 13, Min = 10, Max = 24, Rounding = 0 })
    ESPStyle:AddSlider("ESP_Thickness", { Text = "Line Thickness", Default = 1, Min = 1, Max = 5, Rounding = 1 })

    ----------------------------------------------------------------
    -- Core Loop & Logic (Optimization)
    ----------------------------------------------------------------
    local DrawCache = {}

    local function CreateDrawing(type, props)
        local d = Drawing.new(type)
        for k, v in pairs(props or {}) do d[k] = v end
        return d
    end

    local function RemoveDrawing(plr)
        if DrawCache[plr] then
            for _, d in pairs(DrawCache[plr]) do
                if type(d) == "table" then -- For corners/skeleton arrays
                    for _, sub in pairs(d) do sub:Remove() end
                else
                    d:Remove()
                end
            end
            DrawCache[plr] = nil
        end
        -- Remove Highlights
        if plr.Character then
            local hl = plr.Character:FindFirstChild("Obsidian_Highlight")
            if hl then hl:Destroy() end
        end
    end

    local function GetDrawObject(plr)
        if not DrawCache[plr] then
            DrawCache[plr] = {
                Box = CreateDrawing("Square", { Transparency = 1, Filled = false }),
                Name = CreateDrawing("Text", { Center = true, Outline = true, Transparency = 1 }),
                HealthBar = CreateDrawing("Line", { Transparency = 1 }),
                HealthOutline = CreateDrawing("Line", { Transparency = 1, Color = Color3.new(0,0,0) }),
                Tracer = CreateDrawing("Line", { Transparency = 1 }),
                Skeleton = {} -- Array of lines
            }
            -- Pre-create skeleton lines (15 lines max usually)
            for i=1, 16 do table.insert(DrawCache[plr].Skeleton, CreateDrawing("Line", { Transparency = 1 })) end
        end
        return DrawCache[plr]
    end

    -- Skeleton Connection Map
    local SkeletonLinks = {
        {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, 
        {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
        {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
        {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
        {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
    }

    local function UpdateVisuals()
        -- Loop players
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local cache = GetDrawObject(plr)
                local char = plr.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local hum = char and char:FindFirstChild("Humanoid")
                
                local isEspEnabled = Toggles.ESP_Enabled.Value
                local onScreen = false
                local screenPos, vis = Vector2.zero, false

                if isEspEnabled and char and root and hum and hum.Health > 0 then
                    local vec3, os = Camera:WorldToViewportPoint(root.Position)
                    onScreen = os
                    screenPos = Vector2.new(vec3.X, vec3.Y)
                end

                if onScreen then
                    -- Color & Style
                    local boxColor = Options.Color_Box.Value
                    local skelColor = Options.Color_Skeleton.Value
                    local thickness = Options.ESP_Thickness.Value
                    local textSize = Options.ESP_TextSize.Value

                    -- Box Calculation
                    local rootPos = root.Position
                    local drag = Camera:WorldToViewportPoint(rootPos + Vector3.new(2, 3, 0))
                    local drag2 = Camera:WorldToViewportPoint(rootPos + Vector3.new(-2, -3.5, 0))
                    local height = math.abs(drag.Y - drag2.Y)
                    local width = height / 1.5 -- Standard aspect ratio

                    -- Draw Box
                    if Toggles.ESP_Box.Value then
                        cache.Box.Visible = true
                        cache.Box.Size = Vector2.new(width, height)
                        cache.Box.Position = Vector2.new(screenPos.X - width/2, screenPos.Y - height/2)
                        cache.Box.Color = boxColor
                        cache.Box.Thickness = thickness
                    else cache.Box.Visible = false end

                    -- Draw Name
                    if Toggles.ESP_Name.Value then
                        cache.Name.Visible = true
                        cache.Name.Text = plr.Name .. " [" .. math.floor((rootPos - Camera.CFrame.Position).Magnitude) .. "m]"
                        cache.Name.Size = textSize
                        cache.Name.Position = Vector2.new(screenPos.X, screenPos.Y - height/2 - textSize - 2)
                        cache.Name.Color = boxColor
                    else cache.Name.Visible = false end

                    -- Draw Health
                    if Toggles.ESP_Health.Value then
                        cache.HealthOutline.Visible = true
                        cache.HealthBar.Visible = true
                        
                        local barX = screenPos.X - width/2 - 6
                        local barY = screenPos.Y - height/2
                        local healthY = height * (hum.Health / hum.MaxHealth)
                        
                        cache.HealthOutline.From = Vector2.new(barX, barY)
                        cache.HealthOutline.To = Vector2.new(barX, barY + height)
                        cache.HealthOutline.Thickness = 3
                        
                        cache.HealthBar.From = Vector2.new(barX, barY + height)
                        cache.HealthBar.To = Vector2.new(barX, barY + height - healthY)
                        cache.HealthBar.Color = Color3.fromHSV(math.clamp(hum.Health/hum.MaxHealth, 0, 1)/3, 1, 1)
                        cache.HealthBar.Thickness = 1
                    else 
                        cache.HealthBar.Visible = false 
                        cache.HealthOutline.Visible = false
                    end

                    -- Draw Skeleton (Loop through links)
                    if Toggles.ESP_Skeleton.Value then
                        for i, link in ipairs(SkeletonLinks) do
                            local p1 = char:FindFirstChild(link[1])
                            local p2 = char:FindFirstChild(link[2])
                            local line = cache.Skeleton[i]
                            
                            if p1 and p2 and line then
                                local v1, o1 = Camera:WorldToViewportPoint(p1.Position)
                                local v2, o2 = Camera:WorldToViewportPoint(p2.Position)
                                
                                if o1 and o2 then
                                    line.Visible = true
                                    line.From = Vector2.new(v1.X, v1.Y)
                                    line.To = Vector2.new(v2.X, v2.Y)
                                    line.Color = skelColor
                                    line.Thickness = thickness
                                else
                                    line.Visible = false
                                end
                            elseif line then
                                line.Visible = false
                            end
                        end
                    else
                        for _, l in pairs(cache.Skeleton) do l.Visible = false end
                    end

                    -- Chams (Highlights)
                    if Toggles.ESP_Chams.Value then
                        local hl = char:FindFirstChild("Obsidian_Highlight")
                        if not hl then
                            hl = Instance.new("Highlight", char)
                            hl.Name = "Obsidian_Highlight"
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        end
                        hl.FillColor = Options.Color_Chams.Value
                        hl.OutlineColor = Options.Color_ChamsOut.Value
                    else
                        local hl = char:FindFirstChild("Obsidian_Highlight")
                        if hl then hl:Destroy() end
                    end

                else
                    -- Off screen or disabled
                    cache.Box.Visible = false
                    cache.Name.Visible = false
                    cache.HealthBar.Visible = false
                    cache.HealthOutline.Visible = false
                    cache.Tracer.Visible = false
                    for _, l in pairs(cache.Skeleton) do l.Visible = false end
                    
                    if char then
                        local hl = char:FindFirstChild("Obsidian_Highlight")
                        if hl then hl:Destroy() end
                    end
                end
            elseif DrawCache[plr] then
                -- Remove if player valid but logic failed
                RemoveDrawing(plr)
            end
        end
    end

    ----------------------------------------------------------------
    -- Loop Connections (Aimbot & Player Logic)
    ----------------------------------------------------------------
    RunService.RenderStepped:Connect(function()
        -- Auto Run
        if State.AutoRun and LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
            if hum then hum:Move(Vector3.new(0, 0, -1), true) end
        end

        -- SpinBot (VIP)
        if State.SpinBot and LocalPlayer.Character then
            local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(Options.SpinSpeed.Value), 0)
            end
        end

        -- Anti-Aim (LookDown) (VIP)
        if State.AntiAim and LocalPlayer.Character then
            local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                -- Just visual manipulation to look down, real desync requires network tinkering
                -- Setting lookVector downwards
                local pos = root.Position
                -- Keep position, rotate x axis down
               -- root.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-90), 0, 0) -- Too aggressive, might glitch movement
            end
        end

        -- Advanced Aimbot Logic
        if Toggles.Aim_Enabled.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            -- Hit Chance Check
            if math.random(0, 100) > Options.Aim_HitChance.Value then return end

            local bestTarget = nil
            local bestDist = math.huge
            local mousePos = UserInputService:GetMouseLocation()

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
                    local targetPart = GetWeightedTarget(plr.Character) -- Use Weighted Function
                    if targetPart then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                        if onScreen then
                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if dist < bestDist and dist < 150 then -- Basic FOV
                                bestDist = dist
                                bestTarget = targetPart
                            end
                        end
                    end
                end
            end

            if bestTarget then
                Camera.CFrame = CFrame.new(Camera.CFrame.Position, bestTarget.Position)
            end
        end
    end)

    -- ESP Loop (Optimized with task.spawn)
    task.spawn(function()
        while true do
            UpdateVisuals()
            task.wait() -- Update every frame/tick but in spawn to prevent main thread freeze
        end
    end)

    -- Click TP
    UserInputService.InputBegan:Connect(function(input, gpe)
        if not gpe and input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            if State.ClickTP and Mouse.Target then
                local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    root.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0))
                end
            end
        end
    end)

    -- Cleanup on Unload
    Library:OnUnload(function()
        print("Unloading BxB Premium...")
        for _, plr in pairs(Players:GetPlayers()) do RemoveDrawing(plr) end
    end)
    
    Notify("Loaded Premium Hub! Role: " .. role:upper(), 5)
end
