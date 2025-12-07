-- STATUS:online
-- STATUS_MSG:Main hub is live and ready

-- MainHub.lua
-- ต้องถูกโหลดผ่าน Key_Loaded.lua เท่านั้น

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- [CORE] Fallback Exec (เผื่อรันโดยไม่ผ่าน Loader เพื่อ Debug)
    ----------------------------------------------------------------
    if not Exec then
        warn("[MainHub] Exec not found, using fallback.")
        Exec = {
            SetClipboard = function(txt) 
                if setclipboard then setclipboard(txt) return true end
                return false, "setclipboard not supported"
            end,
            HttpGet = function(url) return game:HttpGet(url) end
        }
    end

    ----------------------------------------------------------------
    -- ชั้นที่สอง: ตรวจ keycheck + keydata
    ----------------------------------------------------------------
    local EXPECTED_KEYCHECK = "BxB.ware-universal-private-*&^%$#$*#%&@#" -- ต้องตรงกับ Config.KEYCHECK_TOKEN ใน Key_Loaded.lua
    
    -- ถ้า keycheck ไม่ตรง หรือไม่มีข้อมูล keydata ให้ return (Safety)
    if keycheck ~= EXPECTED_KEYCHECK then
        -- ถ้าเป็นการ Test ใน Studio หรือ Executor ตรงๆ อาจจะยอมผ่าน (Comment บรรทัด return ถ้าจะ Debug)
        -- return 
    end

    -- Mock Data ถ้า keydata เป็น nil (สำหรับการ Debug)
    if type(keydata) ~= "table" then
        keydata = { key = "DEBUG_KEY", role = "owner", status = "active" }
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
    if not LocalPlayer then
        return
    end

    local VirtualUser
    do
        local ok, vu = pcall(function()
            return game:GetService("VirtualUser")
        end)
        if ok then
            VirtualUser = vu
        end
    end

    ----------------------------------------------------------------
    -- โหลด Obsidian Library + ThemeManager + SaveManager
    ----------------------------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

    if ThemeManager and ThemeManager.SetLibrary then
        ThemeManager:SetLibrary(Library)
    end
    if SaveManager and SaveManager.SetLibrary then
        SaveManager:SetLibrary(Library)
    end
    if SaveManager and SaveManager.IgnoreThemeSettings then
        SaveManager:IgnoreThemeSettings()
    end
    if SaveManager and SaveManager.SetFolder then
        SaveManager:SetFolder("ObsidianUniversalHub")
    end

    local Options = Library.Options
    local Toggles = Library.Toggles

    ----------------------------------------------------------------
    -- Helper: connections / notify
    ----------------------------------------------------------------
    local Connections = {}

    local function AddConnection(conn)
        if typeof(conn) == "RBXScriptConnection" then
            table.insert(Connections, conn)
        end
    end

    local function CleanupConnections()
        for _, conn in ipairs(Connections) do
            if typeof(conn) == "RBXScriptConnection" then
                pcall(function()
                    conn:Disconnect()
                end)
            end
        end
        table.clear(Connections)
    end

    local function Notify(msg, dur)
        if Library and Library.Notify then
            Library:Notify(tostring(msg), dur or 3)
        else
            warn("[Obsidian] " .. tostring(msg))
        end
    end

    ----------------------------------------------------------------
    -- [CORE] Role / key helpers
    ----------------------------------------------------------------
    local role      = tostring(keydata.role or "user")
    local keyStatus = tostring(keydata.status or "active")

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

    local function GetRolePriority(r)
        r = tostring(r or "free"):lower()
        return RolePriority[r] or 0
    end

    local function RoleAtLeast(minRole)
        return GetRolePriority(role) >= GetRolePriority(minRole)
    end

    -- ฟังก์ชันตรวจสอบสิทธิ์และแจ้งเตือน (ใช้ใน Callback ปุ่ม)
    local function RequireRole(req)
        if not RoleAtLeast(req) then
            Notify("Access Denied: Requires " .. req:upper() .. " role!", 3)
            return false
        end
        return true
    end

    local function GetRoleLabel(r)
        r = tostring(r or "free"):lower()
        return r:sub(1,1):upper() .. r:sub(2)
    end

    local function GetRoleColorHex(r)
        r = tostring(r or "user"):lower()
        if r == "premium" or r == "reseller" then return "#55aaff"
        elseif r == "vip" then return "#c955ff"
        elseif r == "staff" then return "#55ff99"
        elseif r == "owner" then return "#ffdd55"
        else return "#cccccc" end
    end

    local function GetTierLabel()
        local p = GetRolePriority(role)
        if p >= 5 then return "Dev Tier"
        elseif p >= 4 then return "Staff Tier"
        elseif p >= 3 then return "VIP Tier"
        elseif p >= 2 then return "Premium Tier"
        else return "Free Tier" end
    end

    ----------------------------------------------------------------
    -- Helpers: character / time / perf
    ----------------------------------------------------------------
    local function GetCharacter() return LocalPlayer.Character end
    local function GetRoot() 
        local c = GetCharacter()
        return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso"))
    end
    local function GetHumanoid()
        local c = GetCharacter()
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function unixNow()
        local ok, dt = pcall(DateTime.now)
        return (ok and dt) and dt.UnixTimestamp or os.time()
    end

    local function formatUnix(ts)
        ts = tonumber(ts)
        if not ts then return "N/A" end
        local ok, dt = pcall(DateTime.fromUnixTimestamp, ts)
        if not ok then return "N/A" end
        local ut = dt:ToUniversalTime()
        return string.format("%02d/%02d/%s - %02d:%02d:%02d", ut.Day, ut.Month, tostring(ut.Year):sub(3,4), ut.Hour, ut.Minute, ut.Second)
    end

    local function formatTimeLeft(expireTs)
        expireTs = tonumber(expireTs)
        if not expireTs then return "Lifetime" end
        local diff = expireTs - unixNow()
        if diff <= 0 then return "Expired" end
        local days = math.floor(diff/86400)
        local hours = math.floor((diff%86400)/3600)
        if days > 0 then return days .. "d " .. hours .. "h" end
        return hours .. "h " .. math.floor((diff%3600)/60) .. "m"
    end

    local function shortKey(k)
        k = tostring(k or "")
        return #k <= 8 and k or (k:sub(1,4) .. "..." .. k:sub(-4))
    end

    -- Performance Stats
    local FPS, lastTime, frameCount = 0, tick(), 0
    AddConnection(RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        local now = tick()
        if now - lastTime >= 1 then
            FPS = frameCount / (now - lastTime)
            frameCount = 0
            lastTime = now
        end
    end))

    local function getPing()
        local s = Stats:FindFirstChild("Network")
        if not s then return 0 end
        local data = s:FindFirstChild("ServerStatsItem") and s.ServerStatsItem:FindFirstChild("Data Ping")
        return data and math.floor(data:GetValue() * 1000) or 0
    end

    local function getMemoryMB()
        local m = Stats:FindFirstChild("PerformanceStats") and Stats.PerformanceStats:FindFirstChild("MemoryUsageMb")
        return m and math.floor(m:GetValue()) or 0
    end

    ----------------------------------------------------------------
    -- Drawing Check
    ----------------------------------------------------------------
    local hasDrawing = false
    pcall(function() hasDrawing = Drawing and type(Drawing.new) == "function" end)

    ----------------------------------------------------------------
    -- [CONFIG] Settings Tables
    ----------------------------------------------------------------
    local ESPSettings = {
        Enabled         = true,
        BoxMode         = "Box",
        UseHighlight    = true,
        Skeleton        = false,
        HeadDot         = true,
        NameTag         = true,
        ShowDistance    = true,
        HealthBar       = true,
        Tracer          = true,
        OffscreenArrow  = false,
        TeamCheck       = true,
        IgnoreFriends   = true,
        VisibleOnly     = false,
        WallCheck       = true,
        MaxDistance     = 1000,
        MaxPlayers      = 30,
        UpdateInterval  = 0.08,
        UseESPFOV       = false,
        ESPFOVRadius    = 500,
        DistanceFade    = false,
        FadeStart       = 500,
        FadeEnd         = 2000,
        -- Colors & Style
        BoxColor        = Color3.fromRGB(0, 255, 0),
        NameColor       = Color3.fromRGB(255, 255, 255),
        TracerColor     = Color3.fromRGB(255, 255, 255),
        ChamsFill       = Color3.fromRGB(255, 0, 0),
        ChamsOutline    = Color3.fromRGB(255, 255, 255),
        SkeletonColor   = Color3.fromRGB(255, 255, 255),
        LookTracerColor = Color3.fromRGB(255, 0, 0),
        TextSize        = 13,
        LineThickness   = 1,
        LookTracer      = false,
    }

    local AimSettings = {
        Enabled       = true,
        Mode          = "Legit",
        AimType       = "Hold",
        AimPart       = "Head",
        FOVRadius     = 120,
        ShowFOV       = true,
        Smoothing     = 0.25,
        VisibleOnly   = true,
        TeamCheck     = true,
        IgnoreFriends = true,
        MaxDistance   = 1000,
        HitChance     = 100,
        Key           = Enum.UserInputType.MouseButton2,
        Weights       = { Head = 60, Chest = 25, Arms = 10, Legs = 5 },
    }

    local MovementState = {
        WalkSpeedEnabled = false, WalkSpeedValue = 16, WalkSpeedLock = false,
        JumpEnabled = false, JumpValue = 50, JumpLock = false,
        InfiniteJump = false, Fly = false, FlySpeed = 60, NoClip = false,
        -- Advanced
        SpinBot = false, AntiAim = false, AutoRun = false, ClickTP = false,
    }

    local AimToggleState = false
    local WhitelistNames = {}
    
    ----------------------------------------------------------------
    -- Target Manager (Optimized)
    ----------------------------------------------------------------
    local WorldRoot = workspace
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local function updateRaycastFilter()
        RayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    end
    AddConnection(LocalPlayer.CharacterAdded:Connect(function() task.delay(1, updateRaycastFilter) end))
    updateRaycastFilter()

    local PlayerInfo = {} 

    local function isFriend(plr)
        local ok, res = pcall(LocalPlayer.IsFriendsWith, LocalPlayer, plr.UserId)
        return ok and res
    end

    local function updatePlayerList()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and not PlayerInfo[plr] then
                PlayerInfo[plr] = {}
            end
        end
        for plr in pairs(PlayerInfo) do
            if not plr.Parent then PlayerInfo[plr] = nil end
        end
    end

    local function buildAimParts(info)
        local c = info.Character; if not c then return end
        local p = {}
        local function add(n) local x = c:FindFirstChild(n); if x then p[n] = x end end
        
        add("Head"); add("Neck"); add("UpperTorso"); add("LowerTorso"); add("Torso")
        add("LeftUpperArm"); add("RightUpperArm"); add("LeftUpperLeg"); add("RightUpperLeg")
        add("LeftHand"); add("RightHand"); add("LeftFoot"); add("RightFoot")
        
        info.AimParts = p
    end

    local function updateTargets()
        local cam = workspace.CurrentCamera
        if not cam then return end
        updatePlayerList()
        
        local origin = cam.CFrame.Position
        local meTeam = LocalPlayer.Team
        local infoList = {}

        for plr, info in pairs(PlayerInfo) do
            local char = plr.Character
            local hum = char and char:FindFirstChild("Humanoid")
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
            
            if char and hum and root and hum.Health > 0 then
                local dist = (root.Position - origin).Magnitude
                local sPos, onScreen = cam:WorldToViewportPoint(root.Position)
                
                info.Character = char
                info.Humanoid = hum
                info.Root = root
                info.Head = char:FindFirstChild("Head")
                info.Distance = dist
                info.ScreenPos = Vector2.new(sPos.X, sPos.Y)
                info.OnScreen = onScreen
                info.IsFriend = isFriend(plr)
                info.Whitelisted = WhitelistNames[plr.Name] == true
                info.TeamOK = (not ESPSettings.TeamCheck) or (not meTeam or plr.Team ~= meTeam)
                
                -- Visibility Check
                local visible = true
                if ESPSettings.WallCheck or AimSettings.VisibleOnly then
                    local targetPos = (info.Head or root).Position
                    local res = WorldRoot:Raycast(origin, targetPos - origin, RayParams)
                    if res and not res.Instance:IsDescendantOf(char) then visible = false end
                end
                info.Visible = visible
                info.Valid = true
                
                if not info.AimParts then buildAimParts(info) end
                table.insert(infoList, info)
            else
                info.Valid = false
                info.ShouldRender = false
            end
        end
        
        -- Sort by distance
        table.sort(infoList, function(a,b) return a.Distance < b.Distance end)
        
        -- Filter render count
        local used = 0
        for _, info in ipairs(infoList) do
            local skip = false
            if ESPSettings.TeamCheck and not info.TeamOK then skip = true end
            if ESPSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then skip = true end
            
            if not skip and used < ESPSettings.MaxPlayers then
                info.ShouldRender = true
                used = used + 1
            else
                info.ShouldRender = false
            end
        end
    end

    ----------------------------------------------------------------
    -- Drawing Objects
    ----------------------------------------------------------------
    local DrawObjects = {}
    local FOVCircle
    
    if hasDrawing then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 1
        FOVCircle.Filled = false
        FOVCircle.Color = Color3.new(1,1,1)
    end

    local function getDrawObjects(plr)
        if DrawObjects[plr] then return DrawObjects[plr] end
        
        local t = {
            Box = Drawing.new("Square"),
            Tracer = Drawing.new("Line"),
            Name = Drawing.new("Text"),
            HealthBar = Drawing.new("Line"),
            HeadDot = Drawing.new("Circle"),
            Offscreen = Drawing.new("Triangle"),
            LookTracer = Drawing.new("Line"),
            Corners = {},
            Skeleton = {}
        }
        -- Init defaults
        t.Box.Thickness = 1; t.Box.Filled = false
        t.Name.Center = true; t.Name.Outline = true
        t.HealthBar.Thickness = 3
        t.HeadDot.Thickness = 1; t.HeadDot.Filled = true
        t.Offscreen.Filled = true
        
        for i=1,4 do table.insert(t.Corners, Drawing.new("Line")) end
        for i=1,12 do table.insert(t.Skeleton, Drawing.new("Line")) end -- Alloc 12 lines
        
        DrawObjects[plr] = t
        return t
    end

    local function hideDrawFor(plr)
        local t = DrawObjects[plr]
        if not t then return end
        t.Box.Visible = false; t.Tracer.Visible = false; t.Name.Visible = false
        t.HealthBar.Visible = false; t.HeadDot.Visible = false; t.Offscreen.Visible = false
        t.LookTracer.Visible = false
        for _,c in pairs(t.Corners) do c.Visible = false end
        for _,l in pairs(t.Skeleton) do l.Visible = false end
    end

    local function removeAllDraw()
        for _, t in pairs(DrawObjects) do
            pcall(function()
                t.Box:Remove(); t.Tracer:Remove(); t.Name:Remove()
                t.HealthBar:Remove(); t.HeadDot:Remove(); t.Offscreen:Remove()
                t.LookTracer:Remove()
                for _,c in pairs(t.Corners) do c:Remove() end
                for _,l in pairs(t.Skeleton) do l:Remove() end
            end)
        end
        table.clear(DrawObjects)
        if FOVCircle then FOVCircle.Visible = false end
    end

    -- Highlight Logic
    local HighlightFolder = Instance.new("Folder", game:GetService("CoreGui"))
    local function updateHighlight(char, enable, colorFill, colorOut)
        if not char then return end
        local hl = char:FindFirstChild("Obsidian_Highlight")
        
        if not enable then
            if hl then hl:Destroy() end
            return
        end
        
        if not hl then
            hl = Instance.new("Highlight")
            hl.Name = "Obsidian_Highlight"
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = char
        end
        hl.FillColor = colorFill or Color3.new(1,0,0)
        hl.OutlineColor = colorOut or Color3.new(1,1,1)
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
    end

    ----------------------------------------------------------------
    -- Aimbot Core (Advanced)
    ----------------------------------------------------------------
    local function getWeightedPart(info)
        local w = AimSettings.Weights
        local total = w.Head + w.Chest + w.Arms + w.Legs
        if total <= 0 then return info.Head end
        
        local r = math.random() * total
        local parts = info.AimParts or {}
        
        if r <= w.Head then return parts.Head or info.Head
        elseif r <= w.Head + w.Chest then return parts.UpperTorso or parts.Torso or info.Root
        elseif r <= w.Head + w.Chest + w.Arms then return parts.RightHand or parts.LeftHand or info.Root
        else return parts.RightFoot or parts.LeftFoot or info.Root end
    end

    local function getTarget()
        local cam = workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local best, bestDist = nil, AimSettings.FOVRadius
        
        for _, info in pairs(PlayerInfo) do
            if info.Valid and info.ShouldRender and info.Distance < AimSettings.MaxDistance then
                -- Visible check logic handled in updateTargets
                if (not AimSettings.VisibleOnly) or info.Visible then
                    local dist2D = (info.ScreenPos - mousePos).Magnitude
                    if dist2D < bestDist then
                        bestDist = dist2D
                        best = info
                    end
                end
            end
        end
        return best
    end

    local function aimbotStep()
        if not hasDrawing or not AimSettings.Enabled then return end
        
        -- Key Check
        local press = false
        if AimSettings.AimType == "Hold" then
            press = UserInputService:IsMouseButtonPressed(AimSettings.Key)
        else
            press = AimToggleState
        end
        if not press then return end
        
        -- Hit Chance
        if math.random(0,100) > AimSettings.HitChance then return end
        
        local info = getTarget()
        if info then
            local part
            if AimSettings.AimPart == "RandomWeighted" then part = getWeightedPart(info)
            elseif AimSettings.AimPart == "Chest" then part = info.Root
            else part = info.Head end
            
            if part then
                local cam = workspace.CurrentCamera
                local cf = CFrame.new(cam.CFrame.Position, part.Position)
                cam.CFrame = cam.CFrame:Lerp(cf, AimSettings.Smoothing)
            end
        end
    end

    ----------------------------------------------------------------
    -- ESP Rendering
    ----------------------------------------------------------------
    local function espStep()
        if not hasDrawing then return end
        local cam = workspace.CurrentCamera
        
        -- FOV Circle
        if FOVCircle then
            if AimSettings.Enabled and AimSettings.ShowFOV then
                FOVCircle.Visible = true
                FOVCircle.Radius = AimSettings.FOVRadius
                FOVCircle.Position = UserInputService:GetMouseLocation()
            else
                FOVCircle.Visible = false
            end
        end
        
        if not ESPSettings.Enabled then
            for plr in pairs(PlayerInfo) do 
                hideDrawFor(plr) 
                updateHighlight(plr.Character, false)
            end
            return
        end
        
        for plr, info in pairs(PlayerInfo) do
            local objs = getDrawObjects(plr)
            
            if not info.Valid or not info.ShouldRender then
                hideDrawFor(plr)
                updateHighlight(info.Character, false)
            else
                -- Highlights
                if ESPSettings.UseHighlight then
                    updateHighlight(info.Character, true, ESPSettings.ChamsFill, ESPSettings.ChamsOutline)
                else
                    updateHighlight(info.Character, false)
                end
                
                -- Colors logic
                local mainColor = ESPSettings.BoxColor
                if ESPSettings.WallCheck and not info.Visible then mainColor = Color3.new(1,0,0) end
                
                -- 2D Elements
                if info.OnScreen then
                    local rootPos = info.ScreenPos
                    local headPos = cam:WorldToViewportPoint(info.Head.Position + Vector3.new(0, 0.5, 0))
                    local legPos  = cam:WorldToViewportPoint(info.Root.Position - Vector3.new(0, 3, 0))
                    local h = legPos.Y - headPos.Y
                    local w = h * 0.6
                    local tl = Vector2.new(rootPos.X - w/2, headPos.Y)
                    local boxSize = Vector2.new(w, h)
                    
                    -- BOX
                    if ESPSettings.BoxMode == "Box" then
                        objs.Box.Visible = true; objs.Box.Size = boxSize; objs.Box.Position = tl
                        objs.Box.Color = mainColor; objs.Box.Thickness = ESPSettings.LineThickness
                    else
                        objs.Box.Visible = false
                    end
                    
                    -- NAME
                    if ESPSettings.NameTag then
                        objs.Name.Visible = true
                        objs.Name.Position = Vector2.new(rootPos.X, headPos.Y - 16)
                        objs.Name.Text = string.format("%s [%dm]", plr.Name, math.floor(info.Distance))
                        objs.Name.Color = ESPSettings.NameColor; objs.Name.Size = ESPSettings.TextSize
                    else
                        objs.Name.Visible = false
                    end
                    
                    -- TRACER
                    if ESPSettings.Tracer then
                        objs.Tracer.Visible = true
                        objs.Tracer.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
                        objs.Tracer.To = Vector2.new(rootPos.X, rootPos.Y + h/2)
                        objs.Tracer.Color = ESPSettings.TracerColor; objs.Tracer.Thickness = ESPSettings.LineThickness
                    else
                        objs.Tracer.Visible = false
                    end
                    
                    -- SKELETON (Simple)
                    if ESPSettings.Skeleton and info.AimParts then
                        local joints = {
                            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
                            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftHand"},
                            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightHand"},
                            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftFoot"},
                            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightFoot"}
                        }
                        for i, pair in ipairs(joints) do
                            local p1, p2 = info.AimParts[pair[1]], info.AimParts[pair[2]]
                            local line = objs.Skeleton[i]
                            if p1 and p2 and line then
                                local v1, on1 = cam:WorldToViewportPoint(p1.Position)
                                local v2, on2 = cam:WorldToViewportPoint(p2.Position)
                                if on1 and on2 then
                                    line.Visible = true
                                    line.From = Vector2.new(v1.X, v1.Y); line.To = Vector2.new(v2.X, v2.Y)
                                    line.Color = ESPSettings.SkeletonColor; line.Thickness = ESPSettings.LineThickness
                                else
                                    line.Visible = false
                                end
                            end
                        end
                    else
                        for _,l in pairs(objs.Skeleton) do l.Visible = false end
                    end
                    
                else
                    hideDrawFor(plr) -- Offscreen
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Movement Logic (Spawned Loop)
    ----------------------------------------------------------------
    local DefaultWalkSpeed, DefaultJumpPower = 16, 50
    
    AddConnection(LocalPlayer.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid", 5)
        if h then DefaultWalkSpeed = h.WalkSpeed; DefaultJumpPower = h.JumpPower end
    end))

    task.spawn(function()
        while true do
            local dt = RunService.RenderStepped:Wait()
            local hum = GetHumanoid()
            local root = GetRoot()
            
            if hum and root then
                -- WalkSpeed / JumpPower
                if MovementState.WalkSpeedEnabled then hum.WalkSpeed = MovementState.WalkSpeedValue end
                if MovementState.JumpEnabled then hum.JumpPower = MovementState.JumpValue end
                
                -- SpinBot (VIP)
                if MovementState.SpinBot then
                    root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(1500*dt), 0)
                end
                
                -- AntiAim (VIP)
                if MovementState.AntiAim then
                    hum.AutoRotate = false
                    root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(-90), 0, 0)
                else
                    hum.AutoRotate = true
                end
                
                -- AutoRun
                if MovementState.AutoRun then
                    hum:Move(Vector3.new(0,0,-1), true)
                end
                
                -- Infinite Jump
                if MovementState.InfiniteJump and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
                
                -- Fly
                if MovementState.Fly then
                    hum.PlatformStand = true
                    local cam = workspace.CurrentCamera
                    local lv, rv = cam.CFrame.LookVector, cam.CFrame.RightVector
                    local move = Vector3.zero
                    
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + lv end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - lv end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - rv end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + rv end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0,1,0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0,1,0) end
                    
                    root.Velocity = move * MovementState.FlySpeed
                else
                    hum.PlatformStand = false
                end
            end
        end
    end)

    -- Click TP Logic
    AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        
        -- Toggle Aimbot Key
        if input.UserInputType == AimSettings.Key and AimSettings.AimType == "Toggle" then
            AimToggleState = not AimToggleState
        end
        
        -- ClickTP (User+)
        if MovementState.ClickTP and input.UserInputType == Enum.UserInputType.MouseButton1 then
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                if RoleAtLeast("user") then
                    local mouse = LocalPlayer:GetMouse()
                    local root = GetRoot()
                    if mouse.Hit and root then
                        root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
                    end
                else
                    Notify("Click TP requires User role", 3)
                end
            end
        end
    end))

    ----------------------------------------------------------------
    -- UI Construction
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "",
        Icon = 84528813312016, -- ใช้ Icon ID ที่คุณให้มา
        Size = UDim2.fromOffset(720, 600),  
        Center = true,
        AutoShow = true,
        Resizable = true,  
        Compact = true
    })

    local Tabs = {
        Info     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "database", Description = "Key Status"}),
        Player   = Window:AddTab({Name = 'Player', Icon = "users", Description = "Movement"}),
        Combat   = Window:AddTab({Name = 'Combat', Icon = "eye", Description = "Aimbot"}),
        ESP      = Window:AddTab({Name = 'Visuals', Icon = "crosshair", Description = "ESP"}),
        Misc     = Window:AddTab({Name = 'Misc', Icon = "wrench", Description = "Tools"}),
        Settings = Window:AddTab({Name = 'Settings', Icon = "settings", Description = "Config"}),
    }

    -- 1. INFO TAB
    local InfoKeyBox    = Tabs.Info:AddLeftGroupbox("Information")
    InfoKeyBox:AddLabel("Key: " .. shortKey(keydata.key))
    InfoKeyBox:AddLabel(string.format("Role: <font color='%s'>%s</font>", GetRoleColorHex(role), GetRoleLabel(role)), true)
    InfoKeyBox:AddLabel("Tier: " .. GetTierLabel())
    InfoKeyBox:AddLabel("Expire: " .. formatUnix(keydata.expire or 0))
    
    local StatsBox = Tabs.Info:AddRightGroupbox("Status")
    local fpsLabel = StatsBox:AddLabel("FPS: 0")
    local pingLabel = StatsBox:AddLabel("Ping: 0 ms")
    
    AddConnection(RunService.Heartbeat:Connect(function()
        if fpsLabel.TextLabel then fpsLabel.TextLabel.Text = "FPS: " .. math.floor(FPS) end
        if pingLabel.TextLabel then pingLabel.TextLabel.Text = "Ping: " .. getPing() .. " ms" end
    end))

    -- 2. PLAYER TAB
    local MoveBox = Tabs.Player:AddLeftGroupbox("Movement")
    
    MoveBox:AddToggle("Move_Speed", { Text = "Custom WalkSpeed", Default = false, Callback = function(v) MovementState.WalkSpeedEnabled = v end })
    MoveBox:AddSlider("Move_SpeedVal", { Text = "Value", Default = 16, Min = 0, Max = 300, Rounding = 0, Callback = function(v) MovementState.WalkSpeedValue = v end })
    
    MoveBox:AddToggle("Move_Jump", { Text = "Custom JumpPower", Default = false, Callback = function(v) MovementState.JumpEnabled = v end })
    MoveBox:AddSlider("Move_JumpVal", { Text = "Value", Default = 50, Min = 0, Max = 300, Rounding = 0, Callback = function(v) MovementState.JumpValue = v end })
    
    MoveBox:AddDivider()
    
    MoveBox:AddToggle("Move_SpinBot", { Text = "SpinBot (VIP)", Default = false, Callback = function(v) 
        if v and not RequireRole("vip") then Library.Toggles.Move_SpinBot:SetValue(false) return end
        MovementState.SpinBot = v 
    end })
    
    MoveBox:AddToggle("Move_AntiAim", { Text = "Anti-Aim (VIP)", Default = false, Callback = function(v) 
        if v and not RequireRole("vip") then Library.Toggles.Move_AntiAim:SetValue(false) return end
        MovementState.AntiAim = v 
    end })
    
    local UtilBox = Tabs.Player:AddRightGroupbox("Utility")
    UtilBox:AddToggle("Move_ClickTP", { Text = "Click TP (Ctrl+Click)", Default = false, Callback = function(v) MovementState.ClickTP = v end })
    UtilBox:AddToggle("Move_Fly", { Text = "Fly (WASD)", Default = false, Callback = function(v) MovementState.Fly = v end })
    UtilBox:AddSlider("Move_FlySpd", { Text = "Fly Speed", Default = 60, Min = 10, Max = 200, Callback = function(v) MovementState.FlySpeed = v end })

    -- 3. COMBAT TAB
    local AimMain = Tabs.Combat:AddLeftGroupbox("Aimbot")
    AimMain:AddToggle("Aim_En", { Text = "Enabled", Default = true, Callback = function(v) AimSettings.Enabled = v end })
    AimMain:AddDropdown("Aim_Part", { Text = "Target Part", Default = "Head", Values = {"Head", "Chest", "RandomWeighted"}, Callback = function(v) AimSettings.AimPart = v end })
    AimMain:AddToggle("Aim_Vis", { Text = "Visible Only", Default = true, Callback = function(v) AimSettings.VisibleOnly = v end })
    AimMain:AddSlider("Aim_FOV", { Text = "FOV Radius", Default = 120, Min = 10, Max = 800, Callback = function(v) AimSettings.FOVRadius = v end })
    AimMain:AddToggle("Aim_ShowFOV", { Text = "Draw FOV", Default = true, Callback = function(v) AimSettings.ShowFOV = v end })
    
    local AimAdv = Tabs.Combat:AddRightGroupbox("Advanced (Premium)")
    AimAdv:AddSlider("Aim_Hit", { Text = "Hit Chance %", Default = 100, Min = 0, Max = 100, Callback = function(v) 
        if not RequireRole("premium") then Library.Options.Aim_Hit:SetValue(100) return end
        AimSettings.HitChance = v 
    end })
    AimAdv:AddLabel("<b>Random Weights</b>", true)
    AimAdv:AddSlider("W_Head", { Text = "Head", Default = 60, Min = 0, Max = 100, Callback = function(v) AimSettings.Weights.Head = v end })
    AimAdv:AddSlider("W_Chest", { Text = "Chest", Default = 25, Min = 0, Max = 100, Callback = function(v) AimSettings.Weights.Chest = v end })

    -- 4. ESP TAB
    local ESPMain = Tabs.ESP:AddLeftGroupbox("ESP Toggles")
    ESPMain:AddToggle("ESP_En", { Text = "Master Switch", Default = true, Callback = function(v) ESPSettings.Enabled = v end })
    ESPMain:AddToggle("ESP_Box", { Text = "Box", Default = true, Callback = function(v) ESPSettings.BoxMode = v and "Box" or "Off" end })
    ESPMain:AddToggle("ESP_Name", { Text = "Name", Default = true, Callback = function(v) ESPSettings.NameTag = v end })
    ESPMain:AddToggle("ESP_Hl", { Text = "Chams", Default = true, Callback = function(v) ESPSettings.UseHighlight = v end })
    ESPMain:AddToggle("ESP_Skel", { Text = "Skeleton", Default = false, Callback = function(v) ESPSettings.Skeleton = v end })
    
    local ESPColor = Tabs.ESP:AddRightGroupbox("Colors")
    ESPColor:AddLabel("Box"):AddColorPicker("C_Box", { Default = ESPSettings.BoxColor, Callback = function(v) ESPSettings.BoxColor = v end })
    ESPColor:AddLabel("Skeleton"):AddColorPicker("C_Skel", { Default = ESPSettings.SkeletonColor, Callback = function(v) ESPSettings.SkeletonColor = v end })
    ESPColor:AddLabel("Chams Fill"):AddColorPicker("C_Fill", { Default = ESPSettings.ChamsFill, Callback = function(v) ESPSettings.ChamsFill = v end })

    -- 5. SETTINGS TAB (Fixed Logic)
    -- ใช้ ApplyToTab และ BuildConfigSection อย่างถูกวิธี
    if ThemeManager then
        ThemeManager:SetLibrary(Library)
        ThemeManager:ApplyToTab(Tabs.Settings)
    end
    
    if SaveManager then
        SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetFolder("ObsidianHub")
        SaveManager:BuildConfigSection(Tabs.Settings)
    end
    
    -- Unload Button
    local ConfigBox = Tabs.Settings:AddRightGroupbox("Extra")
    ConfigBox:AddButton("Unload Hub", function()
        CleanupConnections()
        removeAllDraw()
        HighlightFolder:Destroy()
        if FullbrightEnabled then restoreLighting() end
        Library:Unload()
    end)

    ----------------------------------------------------------------
    -- Loop Start
    ----------------------------------------------------------------
    AddConnection(RunService.RenderStepped:Connect(function()
        espStep()
        aimbotStep()
    end))
    
    AddConnection(RunService.Heartbeat:Connect(function()
        updateTargets()
    end))

    Notify("Loaded Successfully!", 5)
end
