-- STATUS:online
-- STATUS_MSG:Main hub is live and ready

-- MainHub.lua
-- ต้องถูกโหลดผ่าน Key_Loaded.lua เท่านั้น

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- ชั้นที่สอง: ตรวจ keycheck + keydata
    ----------------------------------------------------------------
    local EXPECTED_KEYCHECK = "BxB.ware-universal-private-*&^%$#$*#%&@#" -- ต้องตรงกับ Config.KEYCHECK_TOKEN
    if keycheck ~= EXPECTED_KEYCHECK then
        return
    end

    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then
        return
    end

    ----------------------------------------------------------------
    -- Roblox services / locals
    ----------------------------------------------------------------
    local Players            = game:GetService("Players")
    local RunService         = game:GetService("RunService")
    local UserInputService   = game:GetService("UserInputService")
    local Stats              = game:GetService("Stats")
    local TeleportService    = game:GetService("TeleportService")
    local MarketplaceService = game:GetService("MarketplaceService")
    local Lighting           = game:GetService("Lighting")
    local TweenService       = game:GetService("TweenService")

    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then return end

    local VirtualUser
    pcall(function() VirtualUser = game:GetService("VirtualUser") end)

    ----------------------------------------------------------------
    -- โหลด Obsidian Library
    ----------------------------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

    if ThemeManager and ThemeManager.SetLibrary then ThemeManager:SetLibrary(Library) end
    if SaveManager and SaveManager.SetLibrary then SaveManager:SetLibrary(Library) end
    if SaveManager then 
        SaveManager:IgnoreThemeSettings() 
        SaveManager:SetFolder("ObsidianUniversalHub")
    end

    local Options = Library.Options
    local Toggles = Library.Toggles

    ----------------------------------------------------------------
    -- [CORE] Role System
    ----------------------------------------------------------------
    local RolePriority = {
        free     = 0,
        user     = 1,
        trial    = 1,
        premium  = 2,
        reseller = 2,
        vip      = 3,
        staff    = 4,
        owner    = 5,
    }

    local userRole = tostring(keydata.role or "free"):lower()

    local function GetRolePriority(r)
        return RolePriority[r:lower()] or 0
    end

    local function RoleAtLeast(req)
        return GetRolePriority(userRole) >= GetRolePriority(req)
    end

    local function RequireRole(req)
        if not RoleAtLeast(req) then
            Library:Notify("Access Denied: Requires " .. req:upper() .. " role!", 3)
            return false
        end
        return true
    end

    local function GetRoleColorHex(r)
        r = r:lower()
        if r == "owner" then return "#ffdd55"
        elseif r == "staff" then return "#55ff99"
        elseif r == "vip" then return "#c955ff"
        elseif r == "premium" then return "#55aaff"
        else return "#cccccc" end
    end

    ----------------------------------------------------------------
    -- Settings & State
    ----------------------------------------------------------------
    local MovementState = {
        WalkSpeedEnabled = false, WalkSpeedValue = 16,
        JumpEnabled = false, JumpValue = 50,
        InfiniteJump = false,
        Fly = false, FlySpeed = 60,
        NoClip = false,
        
        -- New Features
        SpinBot = false,
        AntiAim = false,
        AutoRun = false,
        ClickTP = false,
    }

    local ESPSettings = {
        Enabled = true,
        BoxMode = "Box",
        UseHighlight = true,
        NameTag = true,
        ShowDistance = true,
        HealthBar = true,
        Tracer = true,
        OffscreenArrow = false,
        
        -- Visual Parts
        HeadDot = true,
        Skeleton = false,     -- [NEW]
        LookTracer = false,   -- [NEW]
        
        -- Filter/Settings
        TeamCheck = true,
        IgnoreFriends = true,
        VisibleOnly = false,
        WallCheck = true,
        MaxDistance = 1000,
        MaxPlayers = 30,
        UpdateInterval = 0.05,
        
        -- Styling [NEW]
        TextSize = 13,
        Thickness = 1,
        
        -- Colors [NEW]
        Colors = {
            Box = Color3.new(1,1,1),
            Name = Color3.new(1,1,1),
            Tracer = Color3.new(1,1,1),
            Skeleton = Color3.new(1,1,1),
            LookTracer = Color3.new(1,0,0),
            ChamsFill = Color3.fromRGB(255, 0, 0),
            ChamsOutline = Color3.fromRGB(255, 255, 255),
            Visible = Color3.fromRGB(0, 255, 0),
            Hidden = Color3.fromRGB(255, 0, 0)
        }
    }

    local AimSettings = {
        Enabled = true,
        Mode = "Legit",
        AimType = "Hold",
        AimPart = "Head",
        FOVRadius = 120,
        ShowFOV = true,
        Smoothing = 0.25,
        VisibleOnly = true,
        TeamCheck = true,
        IgnoreFriends = true,
        MaxDistance = 1000,
        Key = Enum.UserInputType.MouseButton2,
        
        -- Advanced [NEW]
        HitChance = 100,
        Weights = {
            Head = 60,
            Chest = 25,
            Arms = 10,
            Legs = 5
        }
    }

    local AimToggleState = false
    local WhitelistNames = {}

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function GetCharacter() return LocalPlayer.Character end
    local function GetRoot() 
        local c = GetCharacter() 
        return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso")) 
    end
    local function GetHumanoid()
        local c = GetCharacter()
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local DefaultWalkSpeed, DefaultJumpPower = 16, 50
    task.spawn(function()
        local h = GetHumanoid()
        if h then DefaultWalkSpeed, DefaultJumpPower = h.WalkSpeed, h.JumpPower end
    end)

    ----------------------------------------------------------------
    -- Drawing & ESP Logic
    ----------------------------------------------------------------
    local DrawObjects = {}
    local FOVCircle = Drawing.new("Circle")
    
    -- Setup FOV Circle
    FOVCircle.Thickness = 1
    FOVCircle.Filled = false
    FOVCircle.Visible = false
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Transparency = 1

    local function getDrawObjects(plr)
        if DrawObjects[plr] then return DrawObjects[plr] end
        
        local t = {
            Box = Drawing.new("Square"),
            Tracer = Drawing.new("Line"),
            Name = Drawing.new("Text"),
            HealthBar = Drawing.new("Line"),
            HeadDot = Drawing.new("Circle"),
            LookTracer = Drawing.new("Line"), -- [NEW]
            SkeletonLines = {}, -- [NEW]
        }
        
        -- Init defaults
        t.Box.Thickness = 1; t.Box.Filled = false; t.Box.Transparency = 1
        t.Tracer.Thickness = 1; t.Tracer.Transparency = 1
        t.Name.Center = true; t.Name.Outline = true; t.Name.Transparency = 1
        t.HealthBar.Thickness = 2; t.HealthBar.Transparency = 1
        t.HeadDot.Thickness = 1; t.HeadDot.Filled = true; t.HeadDot.Transparency = 1
        t.LookTracer.Thickness = 1; t.LookTracer.Transparency = 1
        
        -- Init Skeleton lines (15 lines approx)
        for i=1, 15 do
            local l = Drawing.new("Line")
            l.Thickness = 1; l.Transparency = 1; l.Visible = false
            table.insert(t.SkeletonLines, l)
        end

        DrawObjects[plr] = t
        return t
    end

    local function hideDraw(t)
        if not t then return end
        t.Box.Visible = false
        t.Tracer.Visible = false
        t.Name.Visible = false
        t.HealthBar.Visible = false
        t.HeadDot.Visible = false
        t.LookTracer.Visible = false
        for _, l in pairs(t.SkeletonLines) do l.Visible = false end
    end

    local function removeHighlight(char)
        if not char then return end
        local hl = char:FindFirstChild("Obsidian_Highlight")
        if hl then hl:Destroy() end
    end

    local function updateHighlight(char, color, enabled)
        if not char then return end
        local hl = char:FindFirstChild("Obsidian_Highlight")
        if not enabled then
            if hl then hl:Destroy() end
            return
        end
        
        if not hl then
            hl = Instance.new("Highlight")
            hl.Name = "Obsidian_Highlight"
            hl.FillTransparency = 0.7
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = char
        end
        hl.FillColor = ESPSettings.Colors.ChamsFill
        hl.OutlineColor = color or ESPSettings.Colors.ChamsOutline
    end

    -- Skeleton joints map
    local SkeletonConnections = {
        {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, 
        {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
        {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
        {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
        {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
    }
    
    -- Main ESP Render Loop
    local function espStep()
        local cam = workspace.CurrentCamera
        if not cam then return end

        -- Aimbot FOV
        if AimSettings.Enabled and AimSettings.ShowFOV then
            FOVCircle.Visible = true
            FOVCircle.Radius = AimSettings.FOVRadius
            FOVCircle.Position = UserInputService:GetMouseLocation()
            FOVCircle.NumSides = 64
        else
            FOVCircle.Visible = false
        end

        if not ESPSettings.Enabled then
            for _, t in pairs(DrawObjects) do hideDraw(t) end
            return
        end

        for plr, t in pairs(DrawObjects) do
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChild("Humanoid")

            if plr ~= LocalPlayer and char and root and head and hum and hum.Health > 0 then
                local dist = (root.Position - cam.CFrame.Position).Magnitude
                
                -- Team & Distance Check
                local isTeammate = (LocalPlayer.Team and plr.Team == LocalPlayer.Team)
                if ESPSettings.TeamCheck and isTeammate then 
                    hideDraw(t)
                    updateHighlight(char, nil, false)
                    continue 
                end
                if dist > ESPSettings.MaxDistance then 
                    hideDraw(t)
                    updateHighlight(char, nil, false)
                    continue 
                end

                -- Visibility Check
                local _, onScreen = cam:WorldToViewportPoint(root.Position)
                local color = ESPSettings.Colors.Visible -- Default Visible
                
                if ESPSettings.WallCheck then
                    local ray = Ray.new(cam.CFrame.Position, (head.Position - cam.CFrame.Position).Unit * dist)
                    local hit = workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character, char})
                    if hit then color = ESPSettings.Colors.Hidden end -- Obstructed
                end

                if ESPSettings.VisibleOnly and color == ESPSettings.Colors.Hidden then
                    hideDraw(t)
                    updateHighlight(char, nil, false)
                    continue
                end

                -- Highlight (Chams)
                updateHighlight(char, color, ESPSettings.UseHighlight)

                if onScreen then
                    local rootPos, _ = cam:WorldToViewportPoint(root.Position)
                    local headPos, _ = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                    local legPos, _ = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                    
                    local height = math.abs(headPos.Y - legPos.Y)
                    local width = height * 0.6

                    -- Update Style
                    t.Box.Thickness = ESPSettings.Thickness
                    t.Name.Size = ESPSettings.TextSize
                    t.Tracer.Thickness = ESPSettings.Thickness
                    
                    -- BOX
                    if ESPSettings.BoxMode == "Box" then
                        t.Box.Visible = true
                        t.Box.Size = Vector2.new(width, height)
                        t.Box.Position = Vector2.new(rootPos.X - width/2, rootPos.Y - height/2)
                        t.Box.Color = ESPSettings.Colors.Box
                    else
                        t.Box.Visible = false
                    end

                    -- NAME
                    if ESPSettings.NameTag then
                        t.Name.Visible = true
                        t.Name.Text = string.format("%s [%d m]", plr.Name, math.floor(dist))
                        t.Name.Position = Vector2.new(rootPos.X, rootPos.Y - height/2 - 15)
                        t.Name.Color = ESPSettings.Colors.Name
                    else
                        t.Name.Visible = false
                    end

                    -- TRACER
                    if ESPSettings.Tracer then
                        t.Tracer.Visible = true
                        t.Tracer.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
                        t.Tracer.To = Vector2.new(rootPos.X, rootPos.Y + height/2)
                        t.Tracer.Color = ESPSettings.Colors.Tracer
                    else
                        t.Tracer.Visible = false
                    end

                    -- HEAD DOT
                    if ESPSettings.HeadDot then
                        local headV = cam:WorldToViewportPoint(head.Position)
                        t.HeadDot.Visible = true
                        t.HeadDot.Position = Vector2.new(headV.X, headV.Y)
                        t.HeadDot.Radius = 4
                        t.HeadDot.Color = color
                    else
                        t.HeadDot.Visible = false
                    end

                    -- LOOK TRACER [NEW]
                    if ESPSettings.LookTracer then
                        local lookVec = head.CFrame.LookVector * 5
                        local lookEnd = head.Position + lookVec
                        local p1 = cam:WorldToViewportPoint(head.Position)
                        local p2 = cam:WorldToViewportPoint(lookEnd)
                        
                        t.LookTracer.Visible = true
                        t.LookTracer.From = Vector2.new(p1.X, p1.Y)
                        t.LookTracer.To = Vector2.new(p2.X, p2.Y)
                        t.LookTracer.Color = ESPSettings.Colors.LookTracer
                    else
                        t.LookTracer.Visible = false
                    end

                    -- SKELETON [NEW]
                    if ESPSettings.Skeleton then
                        for i, conn in ipairs(SkeletonConnections) do
                            local p1 = char:FindFirstChild(conn[1])
                            local p2 = char:FindFirstChild(conn[2])
                            local line = t.SkeletonLines[i]
                            
                            if p1 and p2 and line then
                                local v1, vis1 = cam:WorldToViewportPoint(p1.Position)
                                local v2, vis2 = cam:WorldToViewportPoint(p2.Position)
                                
                                if vis1 or vis2 then
                                    line.Visible = true
                                    line.From = Vector2.new(v1.X, v1.Y)
                                    line.To = Vector2.new(v2.X, v2.Y)
                                    line.Color = ESPSettings.Colors.Skeleton
                                    line.Thickness = ESPSettings.Thickness
                                else
                                    line.Visible = false
                                end
                            elseif line then
                                line.Visible = false
                            end
                        end
                    else
                        for _, l in pairs(t.SkeletonLines) do l.Visible = false end
                    end

                else
                    hideDraw(t) -- Offscreen
                end
            else
                hideDraw(t) -- Invalid / Dead
                updateHighlight(char, nil, false)
            end
        end
    end

    ----------------------------------------------------------------
    -- Aimbot Logic (Advanced)
    ----------------------------------------------------------------
    local function GetAimPart(char)
        if not char then return nil end
        
        -- Weighted Selection [NEW]
        if AimSettings.AimPart == "RandomWeighted" then
            local w = AimSettings.Weights
            local total = w.Head + w.Chest + w.Arms + w.Legs
            local r = math.random(1, total)
            
            if r <= w.Head then return char:FindFirstChild("Head")
            elseif r <= w.Head + w.Chest then return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            elseif r <= w.Head + w.Chest + w.Arms then return char:FindFirstChild("LeftLowerArm") -- Simplified
            else return char:FindFirstChild("LeftLowerLeg") end
        end

        if AimSettings.AimPart == "Head" then return char:FindFirstChild("Head") end
        if AimSettings.AimPart == "Chest" then return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") end
        return char:FindFirstChild("Head") -- Fallback
    end

    local function aimbotStep()
        if not AimSettings.Enabled then return end
        
        -- Key Check
        local pressed = false
        if AimSettings.AimType == "Hold" then
            pressed = UserInputService:IsMouseButtonPressed(AimSettings.Key)
        else
            pressed = AimToggleState
        end
        if not pressed then return end

        -- Hit Chance [NEW]
        if math.random(0, 100) > AimSettings.HitChance then return end

        -- Find Target
        local cam = workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local bestPlr, bestDist = nil, AimSettings.FOVRadius

        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local char = plr.Character
                local head = char:FindFirstChild("Head")
                local root = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChild("Humanoid")
                
                if head and root and hum and hum.Health > 0 then
                    -- Team Check
                    if AimSettings.TeamCheck and plr.Team == LocalPlayer.Team then continue end
                    
                    local screenPos, onScreen = cam:WorldToViewportPoint(head.Position)
                    local dist2d = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    
                    if onScreen and dist2d < bestDist then
                        -- Visible Check
                        if AimSettings.VisibleOnly then
                            local ray = Ray.new(cam.CFrame.Position, (head.Position - cam.CFrame.Position).Unit * 1000)
                            local hit = workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character, char})
                            if not hit or hit:IsDescendantOf(char) then
                                bestDist = dist2d
                                bestPlr = plr
                            end
                        else
                            bestDist = dist2d
                            bestPlr = plr
                        end
                    end
                end
            end
        end

        if bestPlr then
            local targetPart = GetAimPart(bestPlr.Character)
            if targetPart then
                local lookAt = CFrame.new(cam.CFrame.Position, targetPart.Position)
                cam.CFrame = cam.CFrame:Lerp(lookAt, AimSettings.Smoothing)
            end
        end
    end

    ----------------------------------------------------------------
    -- Movement Loops (Optimization: task.spawn)
    ----------------------------------------------------------------
    task.spawn(function()
        while true do
            local dt = RunService.RenderStepped:Wait()
            local char = GetCharacter()
            local root = GetRoot()
            local hum = GetHumanoid()

            if char and root and hum then
                -- [NEW] SpinBot (VIP)
                if MovementState.SpinBot then
                    root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(2000 * dt), 0)
                end

                -- [NEW] Anti-Aim (LookDown) (VIP)
                if MovementState.AntiAim then
                    hum.AutoRotate = false
                    root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(-90), 0, 0)
                else
                    hum.AutoRotate = true
                end

                -- [NEW] AutoRun
                if MovementState.AutoRun then
                   hum:Move(Vector3.new(0,0,-1), true)
                end

                -- Fly Logic
                if MovementState.Fly then
                    hum.PlatformStand = true
                    local cam = workspace.CurrentCamera
                    local moveDir = Vector3.zero
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0,1,0) end
                    root.Velocity = moveDir.Unit * MovementState.FlySpeed
                else
                    hum.PlatformStand = false
                end
            end
        end
    end)

    -- [NEW] Click TP Logic
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if MovementState.ClickTP and input.UserInputType == Enum.UserInputType.MouseButton1 then
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                if not RequireRole("user") then return end
                local mouse = LocalPlayer:GetMouse()
                local root = GetRoot()
                if root and mouse.Hit then
                    root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
                end
            end
        end
        
        -- Toggle Aimbot
        if input.UserInputType == AimSettings.Key and AimSettings.AimType == "Toggle" then
            AimToggleState = not AimToggleState
        end
    end)

    ----------------------------------------------------------------
    -- UI Construction
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "",
        Icon = 84528813312016,
        Size = UDim2.fromOffset(720, 600),  
        Center = true, AutoShow = true, Resizable = true, Compact = true
    })

    local Tabs = {
        Info = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "database", Description = "Information"}),
        Player = Window:AddTab({Name = 'Player', Icon = "users", Description = "Movement & Utils"}),
        Combat = Window:AddTab({Name = 'Combat', Icon = "eye", Description = "Aimbot & Mods"}),
        ESP = Window:AddTab({Name = 'Visuals', Icon = "crosshair", Description = "ESP Settings"}),
        Misc = Window:AddTab({Name = 'Misc', Icon = "wrench", Description = "Extra Tools"}),
        Settings = Window:AddTab({Name = 'Settings', Icon = "settings", Description = "Config"}),
    }

    -- 1. INFO TAB
    local InfoBox = Tabs.Info:AddLeftGroupbox("User Info")
    InfoBox:AddLabel("Key: " .. (keydata.key:sub(1,10) .. "..."))
    InfoBox:AddLabel(string.format("Role: <font color='%s'>%s</font>", GetRoleColorHex(userRole), userRole:upper()), true)
    InfoBox:AddLabel("Status: Active")
    
    -- 2. PLAYER TAB
    local MoveBox = Tabs.Player:AddLeftGroupbox("Movement")
    local UtilBox = Tabs.Player:AddRightGroupbox("Utility")

    MoveBox:AddToggle("Move_Speed", {
        Text = "Custom WalkSpeed", Default = false,
        Callback = function(v)
            MovementState.WalkSpeedEnabled = v
            local h = GetHumanoid()
            if h then h.WalkSpeed = v and MovementState.WalkSpeedValue or DefaultWalkSpeed end
        end
    }):AddKeyPicker("SpeedKey", { Default = "N", NoUI = true, SyncToggleState = true })

    MoveBox:AddSlider("Move_SpeedVal", {
        Text = "Value", Default = 16, Min = 16, Max = 200, Rounding = 0,
        Callback = function(v) 
            MovementState.WalkSpeedValue = v 
            if MovementState.WalkSpeedEnabled then 
                local h = GetHumanoid(); if h then h.WalkSpeed = v end 
            end
        end
    })
    
    -- [NEW] Player Features
    MoveBox:AddDivider()
    MoveBox:AddToggle("Move_AutoRun", { Text = "Auto Run", Callback = function(v) MovementState.AutoRun = v end })
    MoveBox:AddToggle("Move_ClickTP", { 
        Text = "Click TP (Ctrl+Click)", Callback = function(v) 
            if v and not RequireRole("user") then Toggles.Move_ClickTP:SetValue(false) return end
            MovementState.ClickTP = v 
        end 
    })
    MoveBox:AddToggle("Move_SpinBot", { 
        Text = "SpinBot (VIP)", Callback = function(v) 
            if v and not RequireRole("vip") then Toggles.Move_SpinBot:SetValue(false) return end
            MovementState.SpinBot = v 
        end 
    })
    MoveBox:AddToggle("Move_AntiAim", { 
        Text = "Anti-Aim (VIP)", Callback = function(v) 
            if v and not RequireRole("vip") then Toggles.Move_AntiAim:SetValue(false) return end
            MovementState.AntiAim = v 
        end 
    })

    MoveBox:AddDivider()
    MoveBox:AddToggle("Move_Fly", { Text = "Fly", Callback = function(v) MovementState.Fly = v end })
    MoveBox:AddSlider("Move_FlySpd", { Text = "Speed", Default = 60, Min = 10, Max = 200, Callback = function(v) MovementState.FlySpeed = v end })

    -- 3. COMBAT TAB
    local AimMain = Tabs.Combat:AddLeftGroupbox("Aimbot Settings")
    local AimAdv = Tabs.Combat:AddRightGroupbox("Advanced (Premium+)")

    AimMain:AddToggle("Aim_En", { Text = "Enabled", Default = true, Callback = function(v) AimSettings.Enabled = v end })
    AimMain:AddDropdown("Aim_Part", {
        Text = "Aim Part", Default = "Head", Values = {"Head", "Chest", "RandomWeighted"},
        Callback = function(v) AimSettings.AimPart = v end
    })
    AimMain:AddToggle("Aim_Vis", { Text = "Visible Only", Default = true, Callback = function(v) AimSettings.VisibleOnly = v end })
    AimMain:AddSlider("Aim_FOV", { Text = "FOV Radius", Default = 120, Min = 10, Max = 500, Callback = function(v) AimSettings.FOVRadius = v end })
    AimMain:AddToggle("Aim_ShowFOV", { Text = "Draw FOV", Default = true, Callback = function(v) AimSettings.ShowFOV = v end })

    -- [NEW] Advanced Combat
    AimAdv:AddSlider("Aim_HitChance", {
        Text = "Hit Chance %", Default = 100, Min = 0, Max = 100,
        Callback = function(v) 
            if not RequireRole("premium") then Options.Aim_HitChance:SetValue(100) return end
            AimSettings.HitChance = v 
        end
    })
    
    AimAdv:AddLabel("Random Weights"):AddTooltip("Chance for each part when mode is RandomWeighted")
    AimAdv:AddSlider("W_Head", { Text = "Head", Default = 60, Min = 0, Max = 100, Callback = function(v) AimSettings.Weights.Head = v end })
    AimAdv:AddSlider("W_Chest", { Text = "Chest", Default = 25, Min = 0, Max = 100, Callback = function(v) AimSettings.Weights.Chest = v end })
    AimAdv:AddSlider("W_Arms", { Text = "Arms", Default = 10, Min = 0, Max = 100, Callback = function(v) AimSettings.Weights.Arms = v end })
    AimAdv:AddSlider("W_Legs", { Text = "Legs", Default = 5, Min = 0, Max = 100, Callback = function(v) AimSettings.Weights.Legs = v end })

    -- 4. ESP TAB
    local ESPMain = Tabs.ESP:AddLeftGroupbox("ESP Toggles")
    local ESPColor = Tabs.ESP:AddRightGroupbox("Colors & Style")

    ESPMain:AddToggle("ESP_En", { Text = "Enable ESP", Default = true, Callback = function(v) ESPSettings.Enabled = v end })
    ESPMain:AddToggle("ESP_Box", { Text = "Box", Default = true, Callback = function(v) ESPSettings.BoxMode = v and "Box" or "Off" end })
    ESPMain:AddToggle("ESP_Name", { Text = "Name", Default = true, Callback = function(v) ESPSettings.NameTag = v end })
    ESPMain:AddToggle("ESP_Hl", { Text = "Chams (Highlight)", Default = true, Callback = function(v) ESPSettings.UseHighlight = v end })
    
    -- [NEW] Visual Parts
    ESPMain:AddDivider()
    ESPMain:AddToggle("ESP_Skel", { Text = "Skeleton", Default = false, Callback = function(v) ESPSettings.Skeleton = v end })
    ESPMain:AddToggle("ESP_Look", { Text = "Look Tracers", Default = false, Callback = function(v) ESPSettings.LookTracer = v end })
    ESPMain:AddToggle("ESP_Dot", { Text = "Head Dot", Default = true, Callback = function(v) ESPSettings.HeadDot = v end })

    -- [NEW] Colors & Style
    ESPColor:AddSlider("ESP_Thick", { Text = "Thickness", Default = 1, Min = 1, Max = 5, Callback = function(v) ESPSettings.Thickness = v end })
    ESPColor:AddSlider("ESP_TxtSize", { Text = "Text Size", Default = 13, Min = 10, Max = 24, Callback = function(v) ESPSettings.TextSize = v end })
    
    ESPColor:AddLabel("Custom Colors"):AddColorPicker("C_Box", { Default = ESPSettings.Colors.Box, Title = "Box", Callback = function(v) ESPSettings.Colors.Box = v end })
    ESPColor:AddLabel("Name"):AddColorPicker("C_Name", { Default = ESPSettings.Colors.Name, Title = "Name", Callback = function(v) ESPSettings.Colors.Name = v end })
    ESPColor:AddLabel("Skeleton"):AddColorPicker("C_Skel", { Default = ESPSettings.Colors.Skeleton, Title = "Skeleton", Callback = function(v) ESPSettings.Colors.Skeleton = v end })
    ESPColor:AddLabel("Chams Fill"):AddColorPicker("C_Fill", { Default = ESPSettings.Colors.ChamsFill, Title = "Fill", Callback = function(v) ESPSettings.Colors.ChamsFill = v end })

    -- 5. SETTINGS TAB
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:BuildConfigSection(Tabs.Settings)
    ThemeManager:ApplyToTab(Tabs.Settings)

    -- Loops
    RunService.RenderStepped:Connect(function()
        espStep()
        aimbotStep()
    end)
    
    Library:Notify("Welcome " .. LocalPlayer.Name, 5)
end
