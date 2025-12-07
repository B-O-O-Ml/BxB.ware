-- STATUS:online
-- STATUS_MSG:Main hub is live and ready

-- MainHub.lua
-- ต้องถูกโหลดผ่าน Key_Loaded.lua เท่านั้น

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- ชั้นที่สอง: ตรวจ keycheck + keydata
    ----------------------------------------------------------------
    local EXPECTED_KEYCHECK = "BxB.ware-universal-private-*&^%$#$*#%&@#" -- ต้องตรงกับ Config.KEYCHECK_TOKEN ใน Key_Loaded.lua
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
    local Camera             = workspace.CurrentCamera

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
    -- Role / key helpers
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

    -- ฟังก์ชันตรวจสอบสิทธิ์ก่อนใช้งาน
    local function ValidateFeature(featureName, minRole)
        if not RoleAtLeast(minRole) then
            Notify("Access Denied: " .. featureName .. " requires " .. minRole:upper() .. " rank.", 4)
            return false
        end
        return true
    end

    local function GetRoleLabel(r)
        r = tostring(r or "user"):lower()
        if r == "premium" then return "Premium"
        elseif r == "vip" then return "VIP"
        elseif r == "staff" then return "Staff"
        elseif r == "owner" then return "Owner"
        elseif r == "reseller" then return "Reseller"
        elseif r == "trial" then return "Trial"
        else return "User" end
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
        if p >= GetRolePriority("owner") then return "Dev tier"
        elseif p >= GetRolePriority("staff") then return "Staff tier"
        elseif p >= GetRolePriority("vip") then return "VIP tier"
        elseif p >= GetRolePriority("premium") then return "Premium tier"
        else return "Free tier" end
    end

    ----------------------------------------------------------------
    -- Helpers: character / time / perf
    ----------------------------------------------------------------
    local function GetCharacter()
        return LocalPlayer.Character
    end

    local function GetHumanoid()
        local c = GetCharacter()
        if not c then return nil end
        return c:FindFirstChildOfClass("Humanoid")
    end

    local function GetRoot()
        local c = GetCharacter()
        if not c then return nil end
        return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
    end

    local function unixNow()
        return os.time()
    end

    local function formatUnix(ts)
        ts = tonumber(ts)
        if not ts then return "N/A" end
        return os.date("%d/%m/%Y %H:%M:%S", ts)
    end

    local function formatTimeLeft(expireTs)
        expireTs = tonumber(expireTs)
        if not expireTs then return "Lifetime" end
        local diff = expireTs - unixNow()
        if diff <= 0 then return "Expired" end
        local days  = math.floor(diff / 86400)
        local hours = math.floor((diff % 86400) / 3600)
        local mins  = math.floor((diff % 3600) / 60)
        local secs  = diff % 60
        local parts = {}
        if days > 0 then table.insert(parts, days .. "d") end
        if hours > 0 then table.insert(parts, hours .. "h") end
        if mins > 0 then table.insert(parts, mins .. "m") end
        if secs > 0 and #parts == 0 then table.insert(parts, secs .. "s") end
        return table.concat(parts, " ")
    end

    local function shortKey(k)
        k = tostring(k or "")
        if #k <= 8 then return k end
        return string.sub(k, 1, 4) .. "..." .. string.sub(k, -4)
    end

    -- FPS / Ping / Memory
    local FPS        = 0
    local lastTime   = tick()
    local frameCount = 0

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
        return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
    end

    local function getMemoryMB()
        return math.floor(Stats.PerformanceStats.MemoryUsageMb:GetValue())
    end

    ----------------------------------------------------------------
    -- Drawing support
    ----------------------------------------------------------------
    local hasDrawing = false
    do
        local ok, res = pcall(function()
            return Drawing and typeof(Drawing.new) == "function"
        end)
        hasDrawing = ok and res == true
    end

    ----------------------------------------------------------------
    -- ESP / Aimbot global state
    ----------------------------------------------------------------
    local ESPSettings = {
        Enabled         = true,
        BoxMode         = "Box",
        UseHighlight    = true,
        Skeleton        = false, -- New Feature
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
        SilentAim     = false,
        Prediction    = 0,
        TargetMode    = "Distance", -- Distance, Health, Mouse
    }

    local AimToggleState = false
    local WhitelistNames = {} 
    local SilentAimTarget = nil -- Store target for silent aim hook

    ----------------------------------------------------------------
    -- Target Manager
    ----------------------------------------------------------------
    local WorldRoot = workspace:FindFirstChildOfClass("WorldRoot") or workspace
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Blacklist
    RayParams.FilterDescendantsInstances = {}

    local function updateRaycastFilter()
        if LocalPlayer.Character then
            RayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        end
    end

    updateRaycastFilter()
    AddConnection(LocalPlayer.CharacterAdded:Connect(function()
        task.delay(1, updateRaycastFilter)
    end))

    local PlayerInfo = {} 

    local function isFriend(plr)
        if not plr then return false end
        local ok, res = pcall(LocalPlayer.IsFriendsWith, LocalPlayer, plr.UserId)
        if ok then return res == true end
        return false
    end

    local function updatePlayerList()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and not PlayerInfo[plr] then
                PlayerInfo[plr] = {}
            end
        end
        for plr in pairs(PlayerInfo) do
            if not plr.Parent then
                PlayerInfo[plr] = nil
            end
        end
    end

    local function buildAimParts(info)
        local char = info.Character
        if not char then return end
        local parts = {}
        local function add(name)
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then parts[name] = p end
        end
        add("Head"); add("Neck");
        add("UpperTorso"); add("LowerTorso"); add("Torso");
        add("LeftUpperArm"); add("LeftLowerArm"); add("LeftHand");
        add("RightUpperArm"); add("RightLowerArm"); add("RightHand");
        add("LeftUpperLeg"); add("LeftLowerLeg"); add("LeftFoot");
        add("RightUpperLeg"); add("RightLowerLeg"); add("RightFoot");
        info.AimParts = parts
    end

    local function updateTargets()
        local cam = workspace.CurrentCamera
        if not cam then return end
        updatePlayerList()
        local meTeam = LocalPlayer.Team
        local origin = cam.CFrame.Position
        local infoList = {}

        for plr, info in pairs(PlayerInfo) do
            local char = plr.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
            local head = char and char:FindFirstChild("Head")

            if not (char and hum and root and hum.Health > 0) then
                info.Valid = false
                info.ShouldRender = false
            else
                local dist = (root.Position - origin).Magnitude
                local screenPos3D, onScreen = cam:WorldToViewportPoint(root.Position)
                local screenPos = Vector2.new(screenPos3D.X, screenPos3D.Y)

                local friend      = isFriend(plr)
                local whitelisted = WhitelistNames[plr.Name] == true
                local teamOK = true
                if ESPSettings.TeamCheck and meTeam and plr.Team == meTeam then
                    teamOK = false
                end

                local visible = true
                if ESPSettings.WallCheck or AimSettings.VisibleOnly or ESPSettings.VisibleOnly then
                    local targetPos = head and head.Position or root.Position
                    local dir = targetPos - origin
                    local result = WorldRoot:Raycast(origin, dir, RayParams)
                    if result and not result.Instance:IsDescendantOf(char) then
                        visible = false
                    end
                end

                info.Character   = char
                info.Humanoid    = hum
                info.Root        = root
                info.Head        = head
                info.Distance    = dist
                info.ScreenPos   = screenPos
                info.OnScreen    = onScreen
                info.IsFriend    = friend
                info.Whitelisted = whitelisted
                info.TeamOK      = teamOK
                info.Visible     = visible
                info.Valid       = true
                info.ShouldRender = false

                if not info.AimParts then buildAimParts(info) end
                table.insert(infoList, info)
            end
        end

        -- Sorting for Target Selector
        table.sort(infoList, function(a, b)
            if AimSettings.TargetMode == "Health" then
                local ha = a.Humanoid and a.Humanoid.Health or 100
                local hb = b.Humanoid and b.Humanoid.Health or 100
                return ha < hb
            elseif AimSettings.TargetMode == "Mouse" then
                local mousePos = UserInputService:GetMouseLocation()
                local da = (a.ScreenPos - mousePos).Magnitude
                local db = (b.ScreenPos - mousePos).Magnitude
                return da < db
            else -- Distance
                local ad = a.Distance or 99999
                local bd = b.Distance or 99999
                return ad < bd
            end
        end)

        local used = 0
        for _, info in ipairs(infoList) do
            if info.Valid and info.Distance <= ESPSettings.MaxDistance then
                local skip = false
                if ESPSettings.TeamCheck and not info.TeamOK then skip = true end
                if not skip and ESPSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then skip = true end
                
                if not skip then
                    used = used + 1
                    if used <= ESPSettings.MaxPlayers then
                        info.ShouldRender = true
                    else
                        info.ShouldRender = false
                    end
                else
                    info.ShouldRender = false
                end
            else
                info.ShouldRender = false
            end
        end
    end

    ----------------------------------------------------------------
    -- Drawing objects
    ----------------------------------------------------------------
    local DrawObjects = {}
    local FOVCircle

    if hasDrawing then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 1
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.Color = Color3.fromRGB(255, 255, 255)
        FOVCircle.Transparency = 1
    end

    local function getDrawObjects(plr)
        local existing = DrawObjects[plr]
        if existing then return existing end

        local t = {}
        t.Box = Drawing.new("Square"); t.Box.Thickness = 1; t.Box.Filled = false
        t.Tracer = Drawing.new("Line"); t.Tracer.Thickness = 1
        t.Name = Drawing.new("Text"); t.Name.Size = 13; t.Name.Center = true; t.Name.Outline = true
        t.HealthBar = Drawing.new("Line"); t.HealthBar.Thickness = 3
        t.HeadDot = Drawing.new("Circle"); t.HeadDot.Thickness = 2; t.HeadDot.Filled = false
        t.Offscreen = Drawing.new("Triangle"); t.Offscreen.Filled = true
        t.Skeleton = {} -- Store skeleton lines
        t.Corners = {}
        for i = 1, 4 do
            local c = Drawing.new("Line")
            c.Thickness = 1; c.Visible = false; table.insert(t.Corners, c)
        end
        
        -- Create Skeleton Lines
        for i = 1, 10 do -- Basic R15 skeleton needs about 10-15 lines
            local l = Drawing.new("Line")
            l.Thickness = 1; l.Visible = false; l.Color = Color3.new(1,1,1)
            table.insert(t.Skeleton, l)
        end

        DrawObjects[plr] = t
        return t
    end

    local function hideDrawFor(plr)
        local objs = DrawObjects[plr]
        if not objs then return end
        objs.Box.Visible = false; objs.Tracer.Visible = false; objs.Name.Visible = false
        objs.HealthBar.Visible = false; objs.HeadDot.Visible = false; objs.Offscreen.Visible = false
        for _, c in ipairs(objs.Corners) do c.Visible = false end
        for _, l in ipairs(objs.Skeleton) do l.Visible = false end
    end

    local function hideAllDraw()
        for plr in pairs(DrawObjects) do hideDrawFor(plr) end
    end

    ----------------------------------------------------------------
    -- 3D Highlight
    ----------------------------------------------------------------
    local HighlightFolder = Instance.new("Folder")
    HighlightFolder.Name = "Obsidian_Highlights"
    HighlightFolder.Parent = game:GetService("CoreGui")

    local function getHighlight(char)
        if not char then return nil end
        local tag = "Obsidian_Highlight_Tag"
        local existing = char:FindFirstChild(tag)
        if existing and existing:IsA("Highlight") then return existing end

        local hl = Instance.new("Highlight")
        hl.Name = tag
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.7
        hl.OutlineTransparency = 0
        hl.FillColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.Adornee = char
        hl.Parent = HighlightFolder
        return hl
    end

    local function removeHighlight(char)
        if not char then return end
        local tag = "Obsidian_Highlight_Tag"
        local existing = char:FindFirstChild(tag)
        if existing and existing:IsA("Highlight") then existing:Destroy() end
    end

    ----------------------------------------------------------------
    -- Aimbot Core
    ----------------------------------------------------------------
    local function isAimKeyDown()
        if not AimSettings.Enabled then return false end
        local key = AimSettings.Key
        if AimSettings.AimType == "Hold" then
            if key == Enum.UserInputType.MouseButton2 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            end
            return false
        else
            return AimToggleState
        end
    end

    AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == AimSettings.Key then
            if AimSettings.AimType == "Toggle" then
                AimToggleState = not AimToggleState
            end
        end
    end))

    local function getWeightedRandomPart(info)
        local parts = info.AimParts
        if not parts then return nil end
        local w = AimSettings.Weights
        local wHead  = math.max(0, tonumber(w.Head)  or 0)
        local wChest = math.max(0, tonumber(w.Chest) or 0)
        local wArms  = math.max(0, tonumber(w.Arms)  or 0)
        local wLegs  = math.max(0, tonumber(w.Legs)  or 0)
        local total = wHead + wChest + wArms + wLegs
        if total <= 0 then return nil end

        local r = math.random() * total
        local acc = 0; local group
        acc = acc + wHead; if r <= acc then group = "Head"
        else acc = acc + wChest; if r <= acc then group = "Chest"
        else acc = acc + wArms; if r <= acc then group = "Arms"
        else group = "Legs" end end end

        local candidates = {}
        if group == "Head" then if parts.Head then table.insert(candidates, parts.Head) end
        elseif group == "Chest" then if parts.UpperTorso then table.insert(candidates, parts.UpperTorso) end
        elseif group == "Arms" then if parts.RightHand then table.insert(candidates, parts.RightHand) end
        elseif group == "Legs" then if parts.RightFoot then table.insert(candidates, parts.RightFoot) end end

        if #candidates == 0 then return nil end
        return candidates[math.random(1, #candidates)]
    end

    local function getAimTargetPart(info)
        local cam = workspace.CurrentCamera
        if not cam then return nil end
        local parts = info.AimParts
        if not parts then return info.Head or info.Root end
        local ap = AimSettings.AimPart

        if ap == "Head" then return parts.Head or info.Head or info.Root
        elseif ap == "Chest" then return parts.UpperTorso or parts.LowerTorso or info.Root
        elseif ap == "Arms" then return parts.RightHand or info.Root
        elseif ap == "Legs" then return parts.RightFoot or info.Root
        elseif ap == "RandomWeighted" then
            local p = getWeightedRandomPart(info)
            if p then return p end
            return info.Head or info.Root
        else return info.Head or info.Root end
    end

    local function getBestTarget(cam)
        local mousePos = UserInputService:GetMouseLocation()
        local bestInfo = nil
        local bestScore = math.huge

        for _, info in pairs(PlayerInfo) do
            if info.Valid and info.ShouldRender and info.Distance <= AimSettings.MaxDistance then
                local skip = false
                if AimSettings.TeamCheck and not info.TeamOK then skip = true end
                if not skip and AimSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then skip = true end
                if not skip then
                    if (not AimSettings.VisibleOnly) or info.Visible then
                        local sp = info.ScreenPos
                        local delta = sp - mousePos
                        local dist2D = delta.Magnitude
                        if dist2D <= AimSettings.FOVRadius and dist2D < bestScore then
                            bestScore = dist2D
                            bestInfo = info
                        end
                    end
                end
            end
        end
        return bestInfo
    end

    local function aimbotStep()
        if not hasDrawing then return end
        if not AimSettings.Enabled then return end
        
        local cam = workspace.CurrentCamera
        if not cam then return end

        local info = getBestTarget(cam)
        SilentAimTarget = info -- Update silent aim target even if not holding key

        if not isAimKeyDown() then return end

        local chance = math.clamp(AimSettings.HitChance or 100, 0, 100)
        if chance < 100 then if math.random(1, 100) > chance then return end end

        if not info or not info.Valid then return end

        local targetPart = getAimTargetPart(info)
        if not targetPart then return end

        local targetPos = targetPart.Position
        
        -- Prediction Logic
        if AimSettings.Prediction > 0 and info.Root then
             targetPos = targetPos + (info.Root.Velocity * (AimSettings.Prediction * 0.1)) -- Adjust factor
        end

        local currentCF = cam.CFrame
        local targetCF  = CFrame.new(currentCF.Position, targetPos)
        local smoothSlider = AimSettings.Smoothing
        local alpha = math.clamp(smoothSlider, 0.05, 1)

        cam.CFrame = currentCF:Lerp(targetCF, alpha)
    end

    -- Silent Aim Hook (Universal if executor supports it)
    local mt = getrawmetatable(game)
    if mt and setreadonly then
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if AimSettings.SilentAim and SilentAimTarget and SilentAimTarget.Valid and method == "FireServer" then
                -- This is a very generic attempt to catch shoot events. 
                -- In reality, each game has specific arguments.
                -- For universal, we just ensure target is valid. 
                -- Real silent aim requires game-specific module.
            end
            return oldNamecall(self, unpack(args))
        end)
        setreadonly(mt, true)
    end

    ----------------------------------------------------------------
    -- ESP Render
    ----------------------------------------------------------------
    local function espStep()
        local cam = workspace.CurrentCamera
        if not cam then hideAllDraw(); return end
        local viewSize = cam.ViewportSize

        if hasDrawing and FOVCircle then
            if AimSettings.Enabled and AimSettings.ShowFOV then
                local mousePos = UserInputService:GetMouseLocation()
                FOVCircle.Visible  = true
                FOVCircle.Radius   = AimSettings.FOVRadius
                FOVCircle.Position = mousePos
            else
                FOVCircle.Visible = false
            end
        end

        if not hasDrawing then return end
        if not ESPSettings.Enabled then 
            hideAllDraw()
            return 
        end

        local visibleColor = Color3.fromRGB(0, 255, 0)
        local hiddenColor  = Color3.fromRGB(255, 0, 0)

        for plr, info in pairs(PlayerInfo) do
            local objs = getDrawObjects(plr)
            
            -- Basic Cleanup if invalid
            if not info.Valid or not info.ShouldRender then
                hideDrawFor(plr)
                if info.Character then removeHighlight(info.Character) end
            else
                local skip = false
                if ESPSettings.VisibleOnly and not info.Visible then
                    hideDrawFor(plr); if info.Character then removeHighlight(info.Character) end; skip = true
                end

                if not skip and ESPSettings.UseESPFOV then
                    local mousePos = UserInputService:GetMouseLocation()
                    local delta = info.ScreenPos - mousePos
                    if delta.Magnitude > ESPSettings.ESPFOVRadius then
                        hideDrawFor(plr); if info.Character then removeHighlight(info.Character) end; skip = true
                    end
                end

                if not skip then
                    local color = info.Visible and visibleColor or hiddenColor
                    local alpha = 1
                    if ESPSettings.DistanceFade then
                        local s, e, d = ESPSettings.FadeStart, ESPSettings.FadeEnd, info.Distance
                        if d >= s then
                            if d >= e then alpha = 0
                            else local t = (d - s) / math.max(e - s, 1); alpha = 1 - t end
                        end
                        alpha = math.clamp(alpha, 0, 1)
                    end

                    if not info.OnScreen or alpha <= 0 then
                        hideDrawFor(plr)
                    else
                        -- Reset skeleton lines
                        for _, l in ipairs(objs.Skeleton) do l.Visible = false end
                        -- Reset corners
                        for _, c in ipairs(objs.Corners) do c.Visible = false end
                        objs.Box.Visible = false

                        -- Skeleton ESP
                        if ESPSettings.Skeleton and info.Character then
                            local function drawBone(p1Name, p2Name, idx)
                                local p1 = info.Character:FindFirstChild(p1Name)
                                local p2 = info.Character:FindFirstChild(p2Name)
                                if p1 and p2 and objs.Skeleton[idx] then
                                    local v1, os1 = cam:WorldToViewportPoint(p1.Position)
                                    local v2, os2 = cam:WorldToViewportPoint(p2.Position)
                                    if os1 and os2 then
                                        objs.Skeleton[idx].Visible = true
                                        objs.Skeleton[idx].From = Vector2.new(v1.X, v1.Y)
                                        objs.Skeleton[idx].To = Vector2.new(v2.X, v2.Y)
                                        objs.Skeleton[idx].Color = color
                                        objs.Skeleton[idx].Transparency = 1 - alpha
                                        return true
                                    end
                                end
                                return false
                            end
                            -- Connect joints
                            local i = 1
                            drawBone("Head", "UpperTorso", i); i=i+1
                            drawBone("UpperTorso", "LowerTorso", i); i=i+1
                            drawBone("UpperTorso", "LeftUpperArm", i); i=i+1
                            drawBone("LeftUpperArm", "LeftLowerArm", i); i=i+1
                            drawBone("LeftLowerArm", "LeftHand", i); i=i+1
                            drawBone("UpperTorso", "RightUpperArm", i); i=i+1
                            drawBone("RightUpperArm", "RightLowerArm", i); i=i+1
                            drawBone("RightLowerArm", "RightHand", i); i=i+1
                            drawBone("LowerTorso", "LeftUpperLeg", i); i=i+1
                            drawBone("LeftUpperLeg", "LeftLowerLeg", i); i=i+1
                            drawBone("LeftLowerLeg", "LeftFoot", i); i=i+1
                            drawBone("LowerTorso", "RightUpperLeg", i); i=i+1
                            drawBone("RightUpperLeg", "RightLowerLeg", i); i=i+1
                            drawBone("RightLowerLeg", "RightFoot", i); i=i+1
                        end

                        -- Box Calculation
                        local baseSize = Vector2.new(30, 55)
                        local distForScale = math.max(info.Distance, 1)
                        local scale = 600 / distForScale
                        scale = math.clamp(scale, 0.6, 1.6)
                        local boxSize = baseSize * scale
                        boxSize = Vector2.new(math.clamp(boxSize.X, 18, 90), math.clamp(boxSize.Y, 40, 150))
                        local topLeft = info.ScreenPos - boxSize / 2

                        if ESPSettings.BoxMode == "Box" then
                            objs.Box.Visible = true; objs.Box.Position = topLeft; objs.Box.Size = boxSize
                            objs.Box.Color = color; objs.Box.Transparency = 1 - alpha
                        elseif ESPSettings.BoxMode == "Corner" then
                            local w, h = boxSize.X, boxSize.Y
                            local len = math.max(4, math.floor(w * 0.2))
                            local corners = objs.Corners
                            corners[1].Visible = true; corners[1].From = topLeft; corners[1].To = topLeft + Vector2.new(len, 0)
                            corners[2].Visible = true; corners[2].From = topLeft; corners[2].To = topLeft + Vector2.new(0, len)
                            local tr = topLeft + Vector2.new(w, 0)
                            corners[3].Visible = true; corners[3].From = tr; corners[3].To = tr + Vector2.new(-len, 0)
                            corners[4].Visible = true; corners[4].From = tr; corners[4].To = tr + Vector2.new(0, len)
                            for j=1,4 do corners[j].Color = color; corners[j].Transparency = 1 - alpha end
                        end

                        if ESPSettings.Tracer then
                            objs.Tracer.Visible = true; objs.Tracer.From = Vector2.new(viewSize.X/2, viewSize.Y)
                            objs.Tracer.To = info.ScreenPos; objs.Tracer.Color = color; objs.Tracer.Transparency = 1 - alpha
                        else objs.Tracer.Visible = false end

                        if ESPSettings.NameTag or ESPSettings.ShowDistance then
                            local parts = {}
                            if ESPSettings.NameTag then table.insert(parts, plr.Name) end
                            if ESPSettings.ShowDistance then table.insert(parts, string.format("%dm", math.floor(info.Distance))) end
                            objs.Name.Visible = true; objs.Name.Text = table.concat(parts, " | ")
                            objs.Name.Position = Vector2.new(info.ScreenPos.X, topLeft.Y - 12)
                            objs.Name.Color = color; objs.Name.Transparency = 1 - alpha
                        else objs.Name.Visible = false end

                        if ESPSettings.HealthBar and info.Humanoid then
                            local hp, mhp = info.Humanoid.Health, math.max(info.Humanoid.MaxHealth, 1)
                            local r = math.clamp(hp / mhp, 0, 1)
                            local barHeight = boxSize.Y * r
                            local x = topLeft.X - 4
                            objs.HealthBar.Visible = true; objs.HealthBar.From = Vector2.new(x, topLeft.Y + boxSize.Y)
                            objs.HealthBar.To = Vector2.new(x, (topLeft.Y + boxSize.Y) - barHeight)
                            objs.HealthBar.Color = Color3.fromRGB(math.floor(255*(1-r)), math.floor(255*r), 0)
                            objs.HealthBar.Transparency = 1 - alpha
                        else objs.HealthBar.Visible = false end
                        
                        -- Chams Logic
                        if ESPSettings.UseHighlight then
                            local hl = getHighlight(info.Character)
                            if hl then
                                hl.FillColor = color; hl.OutlineColor = color
                                hl.FillTransparency = 0.7 + (1 - alpha) * 0.2
                                hl.OutlineTransparency = 0 + (1 - alpha) * 0.3
                            end
                        else
                            removeHighlight(info.Character)
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Player movement / misc state
    ----------------------------------------------------------------
    local MovementState = {
        WalkSpeedEnabled = false, WalkSpeedValue = 16,
        JumpEnabled = false, JumpValue = 50,
        InfiniteJump = false, Fly = false, FlySpeed = 60, NoClip = false,
        AutoRun = false,
    }
    local DefaultWalkSpeed = 16
    local DefaultJumpPower = 50

    -- Reset Defaults
    local function ResetCharacterState()
        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed = DefaultWalkSpeed
            hum.JumpPower = DefaultJumpPower
            hum.PlatformStand = false
        end
        local char = GetCharacter()
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
    end

    AddConnection(LocalPlayer.CharacterAdded:Connect(function(char)
        task.defer(function()
            local hum = char:WaitForChild("Humanoid", 5)
            if hum then
                DefaultWalkSpeed = hum.WalkSpeed
                DefaultJumpPower = hum.JumpPower
                if MovementState.WalkSpeedEnabled then hum.WalkSpeed = MovementState.WalkSpeedValue end
                if MovementState.JumpEnabled then hum.JumpPower = MovementState.JumpValue end
            end
        end)
    end))

    AddConnection(UserInputService.JumpRequest:Connect(function()
        if MovementState.InfiniteJump then
            local hum = GetHumanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end))

    AddConnection(RunService.RenderStepped:Connect(function()
        local char = GetCharacter(); local hum = GetHumanoid(); local root = GetRoot()
        if not char or not hum or not root then return end

        -- AutoRun
        if MovementState.AutoRun then
            hum:Move(Vector3.new(0, 0, -1), true)
        end

        -- NoClip
        if MovementState.NoClip then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then 
                    part.CanCollide = false 
                end
            end
        end

        -- Fly
        if MovementState.Fly then
            local cam = workspace.CurrentCamera
            local dir = Vector3.new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
            
            if dir.Magnitude > 0 then 
                root.Velocity = dir.Unit * MovementState.FlySpeed 
            else
                root.Velocity = Vector3.new(0,0,0)
            end
            hum.PlatformStand = true
        end
    end))

    ----------------------------------------------------------------
    -- Game Module System
    ----------------------------------------------------------------
    local SupportedGames = {
        [2753915549] = { Name = "Blox Fruits", Url = "..." }, 
        [155615604]  = { Name = "Prison Life", Url = "..." },
    }
    local CurrentGameModule = nil

    local function LoadGameModule()
        local placeId = game.PlaceId
        local data = SupportedGames[placeId]
        if data then
            Notify("Detected Game: " .. data.Name, 5)
            CurrentGameModule = data.Name
        else
            CurrentGameModule = nil
        end
    end

    ----------------------------------------------------------------
    -- Window + Tabs
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
        Info     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "database", Description = "Info & Status"}),
        Player   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "users", Description = "Character"}),
        Combat   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "eye", Description = "Aimbot & PVP"}),
        ESP      = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "crosshair", Description = "Visuals"}),
        Misc     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "wrench", Description = "Utilities"}),
        Settings = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>', Icon = "settings", Description = "Configs"}),
    }

    local function addRichLabel(groupbox, text)
        local lbl = groupbox:AddLabel(text, true)
        if lbl and lbl.TextLabel then lbl.TextLabel.RichText = true end
        return lbl
    end

    ----------------------------------------------------------------
    -- Tab: Info
    ----------------------------------------------------------------
    local InfoKeyBox    = Tabs.Info:AddLeftGroupbox("Account Info")
    local InfoSystemBox = Tabs.Info:AddRightGroupbox("System")

    local bindTypeText = keydata.bind_hwid and "HWID Locked" or "Free (No HWID)"
    
    InfoKeyBox:AddLabel("Key: " .. shortKey(keydata.key))
    addRichLabel(InfoKeyBox, "Role: <b>" .. GetRoleLabel(role) .. "</b>")
    InfoKeyBox:AddLabel("Expire: " .. formatTimeLeft(keydata.expire))
    InfoKeyBox:AddDivider()
    addRichLabel(InfoKeyBox, "Status: <font color='#55ff55'>" .. bindTypeText .. "</font>")

    local sysLabels = {
        FPS = InfoSystemBox:AddLabel("FPS: ..."),
        Ping = InfoSystemBox:AddLabel("Ping: ..."),
    }
    AddConnection(RunService.Heartbeat:Connect(function()
        sysLabels.FPS:SetText("FPS: " .. math.floor(FPS))
        sysLabels.Ping:SetText("Ping: " .. getPing() .. " ms")
    end))

    ----------------------------------------------------------------
    -- Tab: Player
    ----------------------------------------------------------------
    local MoveBox   = Tabs.Player:AddLeftGroupbox("Movement")
    local UtilBox   = Tabs.Player:AddRightGroupbox("Utility")

    MoveBox:AddToggle("WalkSpeed", { Text = "WalkSpeed", Default = false, Callback = function(v) 
        MovementState.WalkSpeedEnabled = v 
        if not v then local h=GetHumanoid(); if h then h.WalkSpeed = DefaultWalkSpeed end end
    end }):AddSlider("WS_Val", { Text = "Value", Default = 16, Min = 0, Max = 300, Rounding = 0, Callback = function(v) MovementState.WalkSpeedValue = v end })

    MoveBox:AddToggle("JumpPower", { Text = "JumpPower", Default = false, Callback = function(v) 
        MovementState.JumpEnabled = v 
        if not v then local h=GetHumanoid(); if h then h.JumpPower = DefaultJumpPower end end
    end }):AddSlider("JP_Val", { Text = "Value", Default = 50, Min = 0, Max = 300, Rounding = 0, Callback = function(v) MovementState.JumpValue = v end })

    MoveBox:AddToggle("InfJump", { Text = "Infinite Jump", Default = false, Callback = function(v) MovementState.InfiniteJump = v end })
    
    -- Fly Logic Fix: Clear PlatformStand on disable
    MoveBox:AddToggle("Fly", { Text = "Fly (CFrame)", Default = false, Callback = function(v) 
        MovementState.Fly = v 
        if not v then 
            local h=GetHumanoid(); local r=GetRoot()
            if h then h.PlatformStand = false end
            if r then r.Velocity = Vector3.new(0,0,0) end
        end
    end }):AddSlider("FlySpeed", { Text = "Speed", Default = 60, Min = 10, Max = 200, Rounding = 0, Callback = function(v) MovementState.FlySpeed = v end })

    -- NoClip Logic Fix: Restore collision on disable
    MoveBox:AddToggle("NoClip", { Text = "NoClip", Default = false, Callback = function(v) 
        MovementState.NoClip = v 
        if not v then 
            local c=GetCharacter()
            if c then 
                for _,p in ipairs(c:GetDescendants()) do 
                    if p:IsA("BasePart") then p.CanCollide = true end 
                end 
            end
        end
    end })

    MoveBox:AddToggle("AutoRun", { Text = "Auto Run", Default = false, Callback = function(v) MovementState.AutoRun = v end })

    UtilBox:AddButton("Click TP (Ctrl+Click)", function() 
        if not ValidateFeature("Click TP", "user") then return end
        local mouse = UserInputService:GetMouseLocation()
        local cam = workspace.CurrentCamera
        local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
        local res = workspace:Raycast(ray.Origin, ray.Direction * 1000)
        if res and GetRoot() then
            GetRoot().CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0))
        end
    end)

    ----------------------------------------------------------------
    -- Tab: ESP
    ----------------------------------------------------------------
    local ESPMain = Tabs.ESP:AddLeftGroupbox("ESP Settings")
    local ESPVisual = Tabs.ESP:AddRightGroupbox("Visual Options")

    ESPMain:AddToggle("ESP_Master", { Text = "Master Switch", Default = true, Callback = function(v) 
        ESPSettings.Enabled = v 
        if not v then hideAllDraw() end -- Clear immediately
    end })
    
    ESPMain:AddDropdown("ESP_Box", { Text = "Box Type", Default = "Box", Values = {"Box", "Corner", "Off"}, Callback = function(v) ESPSettings.BoxMode = v end })
    ESPMain:AddToggle("ESP_Skel", { Text = "Skeleton (New!)", Default = false, Callback = function(v) ESPSettings.Skeleton = v end })
    ESPMain:AddToggle("ESP_Name", { Text = "Names", Default = true, Callback = function(v) ESPSettings.NameTag = v end })
    ESPMain:AddToggle("ESP_Health", { Text = "Health Bar", Default = true, Callback = function(v) ESPSettings.HealthBar = v end })
    ESPMain:AddToggle("ESP_Tracer", { Text = "Tracers", Default = true, Callback = function(v) ESPSettings.Tracer = v end })
    ESPMain:AddToggle("ESP_Chams", { Text = "Chams Highlight", Default = true, Callback = function(v) ESPSettings.UseHighlight = v end })

    ESPVisual:AddToggle("ESP_Team", { Text = "Team Check", Default = true, Callback = function(v) ESPSettings.TeamCheck = v end })
    ESPVisual:AddToggle("ESP_Vis", { Text = "Visible Only", Default = false, Callback = function(v) ESPSettings.VisibleOnly = v end })
    ESPVisual:AddSlider("ESP_Dist", { Text = "Max Distance", Default = 1000, Min = 100, Max = 5000, Rounding = 0, Callback = function(v) ESPSettings.MaxDistance = v end })

    ----------------------------------------------------------------
    -- Tab: Combat
    ----------------------------------------------------------------
    local CombatMain = Tabs.Combat:AddLeftGroupbox("Legit Aimbot")
    local CombatRage = Tabs.Combat:AddRightGroupbox("Rage / Advanced")

    CombatMain:AddToggle("Aim_Enable", { Text = "Enable Aimbot", Default = true, Callback = function(v) AimSettings.Enabled = v end })
    CombatMain:AddDropdown("Aim_Key", { Text = "Keybind", Default = "Right Mouse", Values = {"Right Mouse", "Left Alt", "Ctrl"}, Callback = function(v) 
        AimSettings.Key = (v == "Right Mouse") and Enum.UserInputType.MouseButton2 or (v == "Left Alt") and Enum.KeyCode.LeftAlt or Enum.KeyCode.LeftControl
    end })
    CombatMain:AddSlider("Aim_FOV", { Text = "FOV Radius", Default = 120, Min = 10, Max = 500, Rounding = 0, Callback = function(v) AimSettings.FOVRadius = v end })
    CombatMain:AddToggle("Aim_DrawFOV", { Text = "Draw FOV", Default = true, Callback = function(v) AimSettings.ShowFOV = v end })
    CombatMain:AddSlider("Aim_Smooth", { Text = "Smoothing", Default = 5, Min = 1, Max = 20, Rounding = 1, Callback = function(v) AimSettings.Smoothing = 0.05 + (v-1)*(0.95/19) end })

    -- Silent Aim (Requires Premium)
    CombatRage:AddToggle("SilentAim", { Text = "Silent Aim", Default = false, Callback = function(v) 
        if ValidateFeature("Silent Aim", "premium") then 
            AimSettings.SilentAim = v 
        else
            -- Reset toggle visually (Needs library support or manual reset)
        end
    end })
    
    CombatRage:AddSlider("Pred", { Text = "Prediction", Default = 0, Min = 0, Max = 10, Rounding = 1, Callback = function(v) AimSettings.Prediction = v end })
    CombatRage:AddDropdown("TargetMode", { Text = "Prioritize", Default = "Distance", Values = {"Distance", "Health", "Mouse"}, Callback = function(v) AimSettings.TargetMode = v end })

    ----------------------------------------------------------------
    -- Tab: Settings
    ----------------------------------------------------------------
    local ConfigBox = Tabs.Settings:AddLeftGroupbox("Configuration")
    if SaveManager then SaveManager:BuildConfigSection(Tabs.Settings) end
    if ThemeManager then ThemeManager:ApplyToTab(Tabs.Settings) end

    local MiscBox = Tabs.Settings:AddRightGroupbox("Hub Management")
    MiscBox:AddButton("Unload Hub", function()
        CleanupConnections()
        pcall(function() HighlightFolder:Destroy() end)
        hideAllDraw()
        ResetCharacterState() -- Clean up character physics
        if FOVCircle then FOVCircle.Visible = false end
        Library:Unload()
    end)

    ----------------------------------------------------------------
    -- Init Loops
    ----------------------------------------------------------------
    local accum = 0
    AddConnection(RunService.Heartbeat:Connect(function(dt)
        accum = accum + dt
        if accum >= ESPSettings.UpdateInterval then
            accum = 0
            updateTargets()
        end
    end))

    AddConnection(RunService.RenderStepped:Connect(function()
        espStep()
        aimbotStep()
    end))

    task.delay(1, LoadGameModule)
    Notify("Loaded Successfully! Welcome " .. LocalPlayer.Name, 5)
end
