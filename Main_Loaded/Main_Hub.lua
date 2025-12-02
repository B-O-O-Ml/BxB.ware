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
    -- Role / Status helpers
    ----------------------------------------------------------------
    local role      = tostring(keydata.role or "user")
    local keyStatus = tostring(keydata.status or "active")

    local RolePriority = {
        user     = 1,
        trial    = 1,
        premium  = 2,
        reseller = 2,
        vip      = 3,
        staff    = 4,
        owner    = 5,
    }

    local function GetRolePriority(r)
        r = tostring(r or "user"):lower()
        return RolePriority[r] or 1
    end

    local function RoleAtLeast(minRole)
        return GetRolePriority(role) >= GetRolePriority(minRole)
    end

    local function GetRoleLabel(r)
        r = tostring(r or "user"):lower()
        if r == "premium" then
            return "Premium"
        elseif r == "vip" then
            return "VIP"
        elseif r == "staff" then
            return "Staff"
        elseif r == "owner" then
            return "Owner"
        elseif r == "reseller" then
            return "Reseller"
        elseif r == "trial" then
            return "Trial"
        else
            return "User"
        end
    end

    local function GetRoleColorHex(r)
        r = tostring(r or "user"):lower()
        if r == "premium" or r == "reseller" then
            return "#55aaff"
        elseif r == "vip" then
            return "#c955ff"
        elseif r == "staff" then
            return "#55ff99"
        elseif r == "owner" then
            return "#ffdd55"
        else
            return "#cccccc"
        end
    end

    local function GetTierLabel()
        local p = GetRolePriority(role)
        if p >= GetRolePriority("owner") then
            return "Dev tier"
        elseif p >= GetRolePriority("staff") then
            return "Staff tier"
        elseif p >= GetRolePriority("vip") then
            return "VIP tier"
        elseif p >= GetRolePriority("premium") then
            return "Premium tier"
        else
            return "Free tier"
        end
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
        local ok, dt = pcall(DateTime.now)
        if ok and dt then
            return dt.UnixTimestamp
        end
        return os.time()
    end

    local function formatUnix(ts)
        ts = tonumber(ts)
        if not ts then
            return "N/A"
        end

        local ok, dt = pcall(DateTime.fromUnixTimestamp, ts)
        if not ok then
            return "N/A"
        end
        local ut = dt:ToUniversalTime()

        local function pad(n)
            if n < 10 then
                return "0" .. tostring(n)
            end
            return tostring(n)
        end

        return string.format(
            "%s/%s/%s - %s:%s:%s",
            pad(ut.Day),
            pad(ut.Month),
            string.sub(tostring(ut.Year), 3, 4),
            pad(ut.Hour),
            pad(ut.Minute),
            pad(ut.Second)
        )
    end

    local function formatTimeLeft(expireTs)
        expireTs = tonumber(expireTs)
        if not expireTs then
            return "Lifetime"
        end

        local diff = expireTs - unixNow()
        if diff <= 0 then
            return "Expired"
        end

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
        if #k <= 8 then
            return k
        end
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
        local netStats = Stats:FindFirstChild("Network")
        if not netStats then
            return 0
        end

        local ssi = netStats:FindFirstChild("ServerStatsItem")
        if not ssi then
            return 0
        end

        local data = ssi:FindFirstChild("Data Ping")
        if not data then
            return 0
        end

        local ok, v = pcall(function()
            return data:GetValue()
        end)
        if ok and type(v) == "number" then
            return math.floor(v * 1000)
        end

        return 0
    end

    local function getMemoryMB()
        local ps = Stats:FindFirstChild("PerformanceStats")
        if not ps then
            return 0
        end

        local mem = ps:FindFirstChild("MemoryUsageMb")
        if not mem then
            return 0
        end

        local ok, v = pcall(function()
            return mem:GetValue()
        end)
        if ok and type(v) == "number" then
            return math.floor(v)
        end

        return 0
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
        BoxMode         = "Box",   -- Box / Corner / Off
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
        VisibleOnly     = false,   -- ถ้า true ซ่อนเป้าที่หลังกำแพง (ตาม Visible flag)
        WallCheck       = true,
        MaxDistance     = 1000,
        MaxPlayers      = 30,
        UpdateInterval  = 0.08,    -- วินาที (จาก slider ms 10–250)
        UseESPFOV       = false,
        ESPFOVRadius    = 500,
    }

    local AimSettings = {
        Enabled       = true,
        AimPart       = "Head",    -- Head/Chest/Arms/Legs/Closest/RandomWeighted
        FOVRadius     = 120,
        ShowFOV       = true,
        Smoothing     = 0.25,
        VisibleOnly   = true,
        TeamCheck     = true,
        IgnoreFriends = true,
        Key           = Enum.UserInputType.MouseButton2, -- RMB
        Weights       = { -- สำหรับ RandomWeighted
            Head  = 60,
            Chest = 25,
            Arms  = 10,
            Legs  = 5,
        },
    }

    local WhitelistNames = {} -- [playerName] = true

    ----------------------------------------------------------------
    -- Target Manager (ใช้ร่วม ESP & Aimbot)
    ----------------------------------------------------------------
    local WorldRoot = workspace:FindFirstChildOfClass("WorldRoot") or workspace

    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Blacklist
    RayParams.FilterDescendantsInstances = {}

    local function updateRaycastFilter()
        local list = { LocalPlayer.Character }
        RayParams.FilterDescendantsInstances = list
    end

    updateRaycastFilter()
    AddConnection(LocalPlayer.CharacterAdded:Connect(function()
        task.delay(1, updateRaycastFilter)
    end))

    local PlayerInfo = {} -- [Player] = { ... }

    local function isFriend(plr)
        local ok, res = pcall(LocalPlayer.IsFriendsWith, LocalPlayer, plr.UserId)
        if ok then
            return res == true
        end
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
        if not char then
            return
        end

        local parts = {}

        local function add(name)
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then
                parts[name] = p
            end
        end

        add("Head")
        add("Neck")
        add("UpperTorso")
        add("LowerTorso")
        add("Torso")

        add("LeftUpperArm")
        add("LeftLowerArm")
        add("LeftHand")

        add("RightUpperArm")
        add("RightLowerArm")
        add("RightHand")

        add("LeftUpperLeg")
        add("LeftLowerLeg")
        add("LeftFoot")

        add("RightUpperLeg")
        add("RightLowerLeg")
        add("RightFoot")

        info.AimParts = parts
    end

    local function updateTargets()
        local cam = workspace.CurrentCamera
        if not cam then
            return
        end

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

                if not info.AimParts then
                    buildAimParts(info)
                end

                table.insert(infoList, info)
            end
        end

        table.sort(infoList, function(a, b)
            local ad = a.Distance or 99999
            local bd = b.Distance or 99999
            return ad < bd
        end)

        local used = 0
        for _, info in ipairs(infoList) do
            if info.Valid and info.Distance <= ESPSettings.MaxDistance then
                local skip = false

                if ESPSettings.TeamCheck and not info.TeamOK then
                    skip = true
                end

                if not skip and ESPSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then
                    skip = true
                end

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
    -- Drawing objects (ESP + Aimbot FOV)
    ----------------------------------------------------------------
    local DrawObjects = {} -- [Player] = {...}
    local FOVCircle

    if hasDrawing then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 1
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    end

    local function getDrawObjects(plr)
        local existing = DrawObjects[plr]
        if existing then
            return existing
        end

        local t = {}

        t.Box = Drawing.new("Square")
        t.Box.Thickness = 1
        t.Box.Filled = false
        t.Box.Visible = false
        t.Box.Color = Color3.new(1, 1, 1)

        t.Tracer = Drawing.new("Line")
        t.Tracer.Thickness = 1
        t.Tracer.Visible = false
        t.Tracer.Color = Color3.new(1, 1, 1)

        t.Name = Drawing.new("Text")
        t.Name.Size = 13
        t.Name.Center = true
        t.Name.Outline = true
        t.Name.Visible = false
        t.Name.Color = Color3.new(1, 1, 1)

        t.HealthBar = Drawing.new("Line")
        t.HealthBar.Thickness = 3
        t.HealthBar.Visible = false
        t.HealthBar.Color = Color3.new(0, 1, 0)

        t.HeadDot = Drawing.new("Circle")
        t.HeadDot.Thickness = 2
        t.HeadDot.Filled = false
        t.HeadDot.Visible = false
        t.HeadDot.Color = Color3.new(1, 1, 1)

        t.Offscreen = Drawing.new("Triangle")
        t.Offscreen.Filled = true
        t.Offscreen.Visible = false
        t.Offscreen.Color = Color3.new(1, 1, 1)

        t.Corners = {}
        for i = 1, 4 do
            local c = Drawing.new("Line")
            c.Thickness = 1
            c.Visible = false
            c.Color = Color3.new(1, 1, 1)
            table.insert(t.Corners, c)
        end

        DrawObjects[plr] = t
        return t
    end

    local function hideDrawFor(plr)
        local objs = DrawObjects[plr]
        if not objs then
            return
        end

        objs.Box.Visible       = false
        objs.Tracer.Visible    = false
        objs.Name.Visible      = false
        objs.HealthBar.Visible = false
        objs.HeadDot.Visible   = false
        objs.Offscreen.Visible = false
        for _, c in ipairs(objs.Corners) do
            c.Visible = false
        end
    end

    local function hideAllDraw()
        for plr in pairs(DrawObjects) do
            hideDrawFor(plr)
        end
    end

    ----------------------------------------------------------------
    -- 3D Highlight (Chams)
    ----------------------------------------------------------------
    local HighlightFolder = Instance.new("Folder")
    HighlightFolder.Name = "Obsidian_Highlights"
    HighlightFolder.Parent = game:GetService("CoreGui")

    local function getHighlight(char)
        if not char then return nil end
        local tag = "Obsidian_Highlight_Tag"
        local existing = char:FindFirstChild(tag)
        if existing and existing:IsA("Highlight") then
            return existing
        end

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
        if existing and existing:IsA("Highlight") then
            existing:Destroy()
        end
    end

    ----------------------------------------------------------------
    -- Aimbot core
    ----------------------------------------------------------------
    local function isAimKeyDown()
        if not AimSettings.Enabled then
            return false
        end

        local key = AimSettings.Key
        if key == Enum.UserInputType.MouseButton2 then
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end

        return false
    end

    local function getWeightedRandomPart(info)
        local parts = info.AimParts
        if not parts then
            return nil
        end

        local w = AimSettings.Weights
        local wHead  = math.max(0, tonumber(w.Head)  or 0)
        local wChest = math.max(0, tonumber(w.Chest) or 0)
        local wArms  = math.max(0, tonumber(w.Arms)  or 0)
        local wLegs  = math.max(0, tonumber(w.Legs)  or 0)

        local total = wHead + wChest + wArms + wLegs
        if total <= 0 then
            return nil
        end

        local r = math.random() * total
        local acc = 0
        local group

        acc = acc + wHead
        if r <= acc then
            group = "Head"
        else
            acc = acc + wChest
            if r <= acc then
                group = "Chest"
            else
                acc = acc + wArms
                if r <= acc then
                    group = "Arms"
                else
                    group = "Legs"
                end
            end
        end

        local candidates = {}

        if group == "Head" then
            if parts.Head then table.insert(candidates, parts.Head) end
            if parts.Neck then table.insert(candidates, parts.Neck) end
        elseif group == "Chest" then
            if parts.UpperTorso then table.insert(candidates, parts.UpperTorso) end
            if parts.LowerTorso then table.insert(candidates, parts.LowerTorso) end
            if parts.Torso then table.insert(candidates, parts.Torso) end
        elseif group == "Arms" then
            if parts.LeftUpperArm  then table.insert(candidates, parts.LeftUpperArm) end
            if parts.LeftLowerArm  then table.insert(candidates, parts.LeftLowerArm) end
            if parts.LeftHand      then table.insert(candidates, parts.LeftHand) end
            if parts.RightUpperArm then table.insert(candidates, parts.RightUpperArm) end
            if parts.RightLowerArm then table.insert(candidates, parts.RightLowerArm) end
            if parts.RightHand     then table.insert(candidates, parts.RightHand) end
        elseif group == "Legs" then
            if parts.LeftUpperLeg  then table.insert(candidates, parts.LeftUpperLeg) end
            if parts.LeftLowerLeg  then table.insert(candidates, parts.LeftLowerLeg) end
            if parts.LeftFoot      then table.insert(candidates, parts.LeftFoot) end
            if parts.RightUpperLeg then table.insert(candidates, parts.RightUpperLeg) end
            if parts.RightLowerLeg then table.insert(candidates, parts.RightLowerLeg) end
            if parts.RightFoot     then table.insert(candidates, parts.RightFoot) end
        end

        if #candidates == 0 then
            return nil
        end

        local idx = math.random(1, #candidates)
        return candidates[idx]
    end

    local function getClosestPartToScreen(info, cam, mousePos)
        local parts = info.AimParts
        if not parts then
            return info.Head or info.Root
        end

        local bestPart
        local bestDist = math.huge

        for _, part in pairs(parts) do
            local p3d, onScreen = cam:WorldToViewportPoint(part.Position)
            if onScreen then
                local p2d = Vector2.new(p3d.X, p3d.Y)
                local d = (p2d - mousePos).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestPart = part
                end
            end
        end

        if bestPart then
            return bestPart
        end

        return info.Head or info.Root
    end

    local function getAimTargetPart(info)
        local cam = workspace.CurrentCamera
        if not cam then
            return nil
        end

        local parts = info.AimParts
        if not parts then
            return info.Head or info.Root
        end

        local ap = AimSettings.AimPart

        if ap == "Head" then
            return parts.Head or info.Head or info.Root
        elseif ap == "Chest" then
            return parts.UpperTorso or parts.LowerTorso or parts.Torso or info.Root
        elseif ap == "Arms" then
            return parts.LeftUpperArm or parts.RightUpperArm or parts.LeftLowerArm or parts.RightLowerArm or info.Root
        elseif ap == "Legs" then
            return parts.LeftUpperLeg or parts.RightUpperLeg or parts.LeftLowerLeg or parts.RightLowerLeg or info.Root
        elseif ap == "Closest" then
            local mousePos = UserInputService:GetMouseLocation()
            return getClosestPartToScreen(info, cam, mousePos)
        elseif ap == "RandomWeighted" then
            local p = getWeightedRandomPart(info)
            if p then return p end
            return info.Head or info.Root
        else
            return info.Head or info.Root
        end
    end

    local function getBestTarget(cam)
        local mousePos = UserInputService:GetMouseLocation()
        local bestInfo = nil
        local bestScore = math.huge

        for _, info in pairs(PlayerInfo) do
            if info.Valid and info.ShouldRender then
                if info.Distance <= ESPSettings.MaxDistance then
                    local skip = false

                    if AimSettings.TeamCheck and not info.TeamOK then
                        skip = true
                    end

                    if not skip and AimSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then
                        skip = true
                    end

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
        end

        return bestInfo
    end

    local function aimbotStep()
        if not hasDrawing then
            return
        end
        if not AimSettings.Enabled then
            return
        end
        if not isAimKeyDown() then
            return
        end

        local cam = workspace.CurrentCamera
        if not cam then
            return
        end

        local info = getBestTarget(cam)
        if not info or not info.Valid then
            return
        end

        local targetPart = getAimTargetPart(info)
        if not targetPart then
            return
        end

        local currentCF = cam.CFrame
        local targetCF  = CFrame.new(currentCF.Position, targetPart.Position)
        local alpha     = math.clamp(AimSettings.Smoothing, 0.01, 1)

        cam.CFrame = currentCF:Lerp(targetCF, alpha)
    end

    ----------------------------------------------------------------
    -- ESP render step
    ----------------------------------------------------------------
    local function espStep()
        local cam = workspace.CurrentCamera
        if not cam then
            hideAllDraw()
            return
        end

        local viewSize     = cam.ViewportSize
        local screenCenter = viewSize / 2

        -- FOV circle (ของ Aimbot)
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

        if not (ESPSettings.Enabled and hasDrawing) then
            hideAllDraw()
        end

        local visibleColor = Color3.fromRGB(0, 255, 0)   -- เห็นได้ = เขียว
        local hiddenColor  = Color3.fromRGB(255, 0, 0)   -- หลังกำแพง = แดง

for plr, info in pairs(PlayerInfo) do
    local objs = getDrawObjects(plr)

    if not info.Valid or not info.ShouldRender then
        -- ข้อมูลไม่ valid หรืออยู่นอก limit (MaxPlayers / MaxDistance)
        hideDrawFor(plr)
        if info.Character then
            removeHighlight(info.Character)
        end
    else
        -- ใช้ flag แทน goto
        local skip = false

        -- 1) VisibleOnly (ESP): ถ้าเปิดและไม่ visible -> ซ่อนทุกอย่าง / ไม่ต้อง render ต่อ
        if ESPSettings.VisibleOnly and not info.Visible then
            hideDrawFor(plr)
            if info.Character then
                removeHighlight(info.Character)
            end
            skip = true
        end

        -- 2) ESP FOV: ถ้าเปิดและอยู่นอก FOV -> ซ่อนทุกอย่าง / ไม่ต้อง render ต่อ
        if not skip and ESPSettings.UseESPFOV then
            local mousePos = UserInputService:GetMouseLocation()
            local delta = info.ScreenPos - mousePos
            if delta.Magnitude > ESPSettings.ESPFOVRadius then
                hideDrawFor(plr)
                if info.Character then
                    removeHighlight(info.Character)
                end
                skip = true
            end
        end

        if not skip then
            -- สีตามการมองเห็น (หน้า/หลังกำแพง)
            local color = info.Visible and visibleColor or hiddenColor

            -- 3D highlight (Chams)
            if ESPSettings.UseHighlight then
                local hl = getHighlight(info.Character)
                if hl then
                    hl.FillColor    = color
                    hl.OutlineColor = color
                end
            else
                removeHighlight(info.Character)
            end

            -- 2D Drawing ESP
            if ESPSettings.Enabled and hasDrawing then
                local cam = workspace.CurrentCamera
                if not cam then
                    hideDrawFor(plr)
                else
                    local viewSize     = cam.ViewportSize
                    local screenCenter = viewSize / 2

                    local screenPos = info.ScreenPos
                    local distance  = info.Distance

                    -- ปรับขนาด Box ตามระยะ (สูตรใหม่)
                    local baseSize = Vector2.new(30, 55)
                    local distForScale = math.max(distance, 1)
                    local scale = 600 / distForScale
                    if scale < 0.6 then
                        scale = 0.6
                    elseif scale > 1.6 then
                        scale = 1.6
                    end

                    local boxSize = baseSize * scale
                    boxSize = Vector2.new(
                        math.clamp(boxSize.X, 18, 90),
                        math.clamp(boxSize.Y, 40, 150)
                    )

                    local topLeft = screenPos - boxSize / 2

                    -- Offscreen arrow
                    if ESPSettings.OffscreenArrow and not info.OnScreen then
                        local dir = info.ScreenPos - screenCenter
                        if dir.Magnitude > 0 then
                            dir = dir.Unit
                            local radius = math.min(viewSize.X, viewSize.Y) * 0.45
                            local edgePos = screenCenter + dir * radius
                            local perp    = Vector2.new(-dir.Y, dir.X) * 8

                            local p1 = edgePos
                            local p2 = edgePos - dir * 18 + perp
                            local p3 = edgePos - dir * 18 - perp

                            objs.Offscreen.Visible = true
                            objs.Offscreen.PointA  = p1
                            objs.Offscreen.PointB  = p2
                            objs.Offscreen.PointC  = p3
                            objs.Offscreen.Color   = color
                        end
                    else
                        objs.Offscreen.Visible = false
                    end

                    if not info.OnScreen then
                        -- นอกจอ: ซ่อน box / tracer / text ฯลฯ
                        objs.Box.Visible       = false
                        objs.Tracer.Visible    = false
                        objs.Name.Visible      = false
                        objs.HealthBar.Visible = false
                        objs.HeadDot.Visible   = false
                        for _, c in ipairs(objs.Corners) do
                            c.Visible = false
                        end
                    else
                        -- Box / Corner
                        for _, c in ipairs(objs.Corners) do
                            c.Visible = false
                        end
                        objs.Box.Visible = false

                        if ESPSettings.BoxMode == "Box" then
                            objs.Box.Visible  = true
                            objs.Box.Position = topLeft
                            objs.Box.Size     = boxSize
                            objs.Box.Color    = color
                        elseif ESPSettings.BoxMode == "Corner" then
                            local w, h = boxSize.X, boxSize.Y
                            local tl   = topLeft
                            local tr   = topLeft + Vector2.new(w, 0)
                            local len  = math.max(4, math.floor(w * 0.2))

                            local corners = objs.Corners
                            if corners[1] then
                                corners[1].Visible = true
                                corners[1].From    = tl
                                corners[1].To      = tl + Vector2.new(len, 0)
                                corners[1].Color   = color
                            end
                            if corners[2] then
                                corners[2].Visible = true
                                corners[2].From    = tl
                                corners[2].To      = tl + Vector2.new(0, len)
                                corners[2].Color   = color
                            end
                            if corners[3] then
                                corners[3].Visible = true
                                corners[3].From    = tr
                                corners[3].To      = tr + Vector2.new(-len, 0)
                                corners[3].Color   = color
                            end
                            if corners[4] then
                                corners[4].Visible = true
                                corners[4].From    = tr
                                corners[4].To      = tr + Vector2.new(0, len)
                                corners[4].Color   = color
                            end
                        end

                        -- Tracer (จากกลางขอบล่าง)
                        if ESPSettings.Tracer then
                            local fromPos = Vector2.new(viewSize.X / 2, viewSize.Y)
                            objs.Tracer.Visible = true
                            objs.Tracer.From    = fromPos
                            objs.Tracer.To      = screenPos
                            objs.Tracer.Color   = color
                        else
                            objs.Tracer.Visible = false
                        end

                        -- Name + distance
                        if ESPSettings.NameTag or ESPSettings.ShowDistance then
                            local parts = {}
                            if ESPSettings.NameTag then
                                table.insert(parts, plr.Name)
                            end
                            if ESPSettings.ShowDistance then
                                table.insert(parts, string.format("%dm", math.floor(distance)))
                            end

                            local text = table.concat(parts, " | ")
                            objs.Name.Visible   = true
                            objs.Name.Text      = text
                            objs.Name.Position  = Vector2.new(screenPos.X, topLeft.Y - 12)
                            objs.Name.Color     = color
                        else
                            objs.Name.Visible = false
                        end

                        -- Health bar
                        if ESPSettings.HealthBar and info.Humanoid then
                            local hp  = info.Humanoid.Health
                            local mhp = math.max(info.Humanoid.MaxHealth, 1)
                            local r   = math.clamp(hp / mhp, 0, 1)

                            local barHeight = boxSize.Y * r
                            local x = topLeft.X - 4
                            local y1 = topLeft.Y + boxSize.Y
                            local y2 = y1 - barHeight

                            objs.HealthBar.Visible = true
                            objs.HealthBar.From    = Vector2.new(x, y1)
                            objs.HealthBar.To      = Vector2.new(x, y2)
                            objs.HealthBar.Color   = Color3.fromRGB(
                                math.floor(255 * (1 - r)),
                                math.floor(255 * r),
                                0
                            )
                        else
                            objs.HealthBar.Visible = false
                        end

                        -- Head dot
                        if ESPSettings.HeadDot and info.Head then
                            local headPos3D = info.Head.Position
                            local headView, onHeadScreen = cam:WorldToViewportPoint(headPos3D)
                            if onHeadScreen then
                                objs.HeadDot.Visible  = true
                                objs.HeadDot.Position = Vector2.new(headView.X, headView.Y)
                                objs.HeadDot.Radius   = 3
                                objs.HeadDot.Color    = color
                            else
                                objs.HeadDot.Visible = false
                            end
                        else
                            objs.HeadDot.Visible = false
                        end
                    end
                end
            end
        end
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
        Status = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "database", Description = "Key Status / Info"}),
        Player = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "users", Description = "Player Tool"}),
        ESP    = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "eye", Description = "ESP Client"}),
        Aim    = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "crosshair", Description = "Aimbot Client"}),
        Game   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "joystick", Description = "Game Module"}),
        UI     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "settings", Description = "UI/UX Setings"}),
    }

    local Options = Library.Options

    ----------------------------------------------------------------
    -- Helper: RichText label
    ----------------------------------------------------------------
    local function addRichLabel(groupbox, text)
        local lbl = groupbox:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

    ----------------------------------------------------------------
    -- Tab: Status
    ----------------------------------------------------------------
    local StatusKeyBox    = Tabs.Status:AddLeftGroupbox("Key / Role")
    local StatusSystemBox = Tabs.Status:AddRightGroupbox("System Info")

    local keyRole      = GetRoleLabel(keydata.role)
    local keyNote      = tostring(keydata.note or "")
    local keyStamp     = tonumber(keydata.timestamp)
    local keyExpire    = tonumber(keydata.expire)
    local keyCreatedAt = keyStamp and formatUnix(keyStamp) or "N/A"
    local keyExpireAt  = keyExpire and formatUnix(keyExpire) or "Lifetime"
    local roleColorHex = GetRoleColorHex(role)

    StatusKeyBox:AddLabel("<b>Key Information</b>", true)
    StatusKeyBox:AddDivider()
    addRichLabel(StatusKeyBox, string.format("<b>Key</b>: %s", shortKey(keydata.key)))
    addRichLabel(StatusKeyBox, string.format("<b>Role</b>: <font color=\"%s\">%s</font>", roleColorHex, keyRole))
    addRichLabel(StatusKeyBox, string.format("<b>Status</b>: %s", keyStatus))
    addRichLabel(StatusKeyBox, string.format("<b>Tier</b>: %s", GetTierLabel()))
    addRichLabel(StatusKeyBox, string.format("<b>Note</b>: %s", (keyNote ~= "" and keyNote or "N/A")))
    addRichLabel(StatusKeyBox, string.format("<b>Created at</b>: %s", keyCreatedAt))
    local ExpireLabel   = addRichLabel(StatusKeyBox, string.format("<b>Expire at</b>: %s", keyExpireAt))
    local TimeLeftLabel = addRichLabel(StatusKeyBox, string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire)))

    StatusKeyBox:AddDivider()
    addRichLabel(StatusKeyBox, '<font color="#ffcc66">Key is bound to your HWID. Sharing key may result in ban.</font>')

    AddConnection(RunService.Heartbeat:Connect(function()
        if TimeLeftLabel and TimeLeftLabel.TextLabel then
            TimeLeftLabel.TextLabel.Text = string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire))
            TimeLeftLabel.TextLabel.RichText = true
        end
    end))

    StatusSystemBox:AddLabel("<b>System / Game / Player</b>", true)
    StatusSystemBox:AddDivider()

    local placeId = game.PlaceId
    local jobId   = game.JobId
    local gameName = "Unknown game"

    do
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, placeId)
        if ok and type(info) == "table" and type(info.Name) == "string" then
            gameName = info.Name
        end
    end

    local sysLabels = {
        Game   = addRichLabel(StatusSystemBox, string.format("<b>Game</b>: %s (PlaceId: %d)", gameName, placeId)),
        Server = addRichLabel(StatusSystemBox, string.format("<b>JobId</b>: %s", jobId)),
        Player = addRichLabel(StatusSystemBox, string.format("<b>Player</b>: %s (%d)", LocalPlayer.Name, LocalPlayer.UserId)),
        FPS    = addRichLabel(StatusSystemBox, "<b>FPS</b>: ..."),
        Ping   = addRichLabel(StatusSystemBox, "<b>Ping</b>: ..."),
        Memory = addRichLabel(StatusSystemBox, "<b>Memory</b>: ... MB"),
    }

    AddConnection(RunService.Heartbeat:Connect(function()
        if sysLabels.FPS and sysLabels.FPS.TextLabel then
            sysLabels.FPS.TextLabel.Text = string.format("<b>FPS</b>: %d", math.floor(FPS))
            sysLabels.FPS.TextLabel.RichText = true
        end
        if sysLabels.Ping and sysLabels.Ping.TextLabel then
            sysLabels.Ping.TextLabel.Text = string.format("<b>Ping</b>: %d ms", getPing())
            sysLabels.Ping.TextLabel.RichText = true
        end
        if sysLabels.Memory and sysLabels.Memory.TextLabel then
            sysLabels.Memory.TextLabel.Text = string.format("<b>Memory</b>: %d MB", getMemoryMB())
            sysLabels.Memory.TextLabel.RichText = true
        end
    end))

    StatusSystemBox:AddDivider()
    StatusSystemBox:AddLabel("<b>Credits</b>", true)
    StatusSystemBox:AddLabel("Owner: YOUR_NAME_HERE", true)
    StatusSystemBox:AddLabel("UI: Obsidian UI Library", true)
    StatusSystemBox:AddLabel("Discord: yourdiscord", true)

    ----------------------------------------------------------------
    -- Tab: Player
    ----------------------------------------------------------------
    local MoveBox = Tabs.Player:AddLeftGroupbox("Movement")
    local QoLBox  = Tabs.Player:AddRightGroupbox("Anti-AFK / Server / Safe")

    local MovementState = {
        WalkSpeedEnabled = false,
        WalkSpeedValue   = 16,
        JumpEnabled      = false,
        JumpValue        = 50,
        InfiniteJump     = false,
        Fly              = false,
        FlySpeed         = 50,
        NoClip           = false,
    }

    local DefaultWalkSpeed = 16
    local DefaultJumpPower = 50

    do
        local hum = GetHumanoid()
        if hum then
            DefaultWalkSpeed = hum.WalkSpeed
            DefaultJumpPower = hum.JumpPower
        end
    end

    MoveBox:AddToggle("Move_WalkSpeed_Toggle", {
        Text    = "Custom WalkSpeed",
        Default = false,
        Callback = function(v)
            MovementState.WalkSpeedEnabled = v
            local hum = GetHumanoid()
            if hum then
                hum.WalkSpeed = v and MovementState.WalkSpeedValue or DefaultWalkSpeed
            end
        end
    })

    MoveBox:AddSlider("Move_WalkSpeed_Slider", {
        Text     = "WalkSpeed",
        Default  = 16,
        Min      = 5,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            MovementState.WalkSpeedValue = val
            if MovementState.WalkSpeedEnabled then
                local hum = GetHumanoid()
                if hum then
                    hum.WalkSpeed = val
                end
            end
        end
    })

    MoveBox:AddDivider()

    MoveBox:AddToggle("Move_Jump_Toggle", {
        Text    = "Custom JumpPower",
        Default = false,
        Callback = function(v)
            MovementState.JumpEnabled = v
            local hum = GetHumanoid()
            if hum then
                hum.JumpPower = v and MovementState.JumpValue or DefaultJumpPower
            end
        end
    })

    MoveBox:AddSlider("Move_Jump_Slider", {
        Text     = "JumpPower",
        Default  = 50,
        Min      = 20,
        Max      = 150,
        Rounding = 0,
        Callback = function(val)
            MovementState.JumpValue = val
            if MovementState.JumpEnabled then
                local hum = GetHumanoid()
                if hum then
                    hum.JumpPower = val
                end
            end
        end
    })

    MoveBox:AddDivider()
    MoveBox:AddToggle("Move_InfiniteJump_Toggle", {
        Text    = "Infinite Jump",
        Default = false,
        Callback = function(v)
            MovementState.InfiniteJump = v
        end
    })
    MoveBox:AddToggle("Move_Fly_Toggle", {
        Text    = "Fly (camera based)",
        Default = false,
        Callback = function(v)
            MovementState.Fly = v
        end
    })
    MoveBox:AddSlider("Move_FlySpeed_Slider", {
        Text     = "Fly speed",
        Default  = 50,
        Min      = 10,
        Max      = 200,
        Rounding = 0,
        Callback = function(val)
            MovementState.FlySpeed = val
        end
    })
    MoveBox:AddToggle("Move_NoClip_Toggle", {
        Text    = "NoClip",
        Default = false,
        Callback = function(v)
            MovementState.NoClip = v
        end
    })

    AddConnection(UserInputService.JumpRequest:Connect(function()
        if not MovementState.InfiniteJump then
            return
        end
        local hum = GetHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))

    AddConnection(RunService.RenderStepped:Connect(function()
        local char = GetCharacter()
        local hum  = GetHumanoid()
        local root = GetRoot()

        if char and MovementState.NoClip then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end

        if MovementState.Fly and root then
            local cam = workspace.CurrentCamera
            if not cam then
                return
            end

            local dir = Vector3.new(0, 0, 0)

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                dir = dir + cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                dir = dir - cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                dir = dir - cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                dir = dir + cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                dir = dir + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                dir = dir - Vector3.new(0, 1, 0)
            end

            if dir.Magnitude > 0 then
                dir = dir.Unit * MovementState.FlySpeed
            end

            root.Velocity = dir
            if hum then
                hum.PlatformStand = true
            end
        else
            if hum then
                hum.PlatformStand = false
            end
        end
    end))

    QoLBox:AddLabel("<b>Safety & Anti-AFK</b>", true)
    QoLBox:AddDivider()

    QoLBox:AddButton("Reset movement", function()
        MovementState.WalkSpeedEnabled = false
        MovementState.JumpEnabled      = false
        MovementState.InfiniteJump     = false
        MovementState.Fly              = false
        MovementState.NoClip           = false

        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed    = DefaultWalkSpeed
            hum.JumpPower    = DefaultJumpPower
            hum.PlatformStand = false
        end

        Notify("Movement reset", 3)
    end)

    local AntiAFKConn

    QoLBox:AddToggle("AntiAFK_Toggle", {
        Text    = "Enable Anti-AFK",
        Default = false,
        Callback = function(v)
            if v then
                if VirtualUser and not AntiAFKConn then
                    AntiAFKConn = LocalPlayer.Idled:Connect(function()
                        pcall(function()
                            VirtualUser:CaptureController()
                            VirtualUser:ClickButton2(Vector2.new())
                        end)
                    end)
                    AddConnection(AntiAFKConn)
                    Notify("Anti-AFK enabled", 3)
                else
                    Notify("VirtualUser not available", 3)
                end
            else
                if AntiAFKConn then
                    AntiAFKConn:Disconnect()
                    AntiAFKConn = nil
                end
                Notify("Anti-AFK disabled", 3)
            end
        end
    })

    QoLBox:AddDivider()
    QoLBox:AddLabel("<b>Server Tools</b>", true)

    QoLBox:AddButton("Rejoin server", function()
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
        end)
        if not ok then
            Notify("Rejoin failed: " .. tostring(err), 4)
        end
    end)

    QoLBox:AddButton("Server hop (random)", function()
        local ok, err = pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)
        if not ok then
            Notify("Server hop failed: " .. tostring(err), 4)
        end
    end)

    QoLBox:AddDivider()
    QoLBox:AddButton("Panic (Unload Hub)", function()
        CleanupConnections()
        pcall(function()
            HighlightFolder:Destroy()
        end)
        hideAllDraw()
        if FOVCircle then
            FOVCircle.Visible = false
        end
        Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    ----------------------------------------------------------------
    -- Tab: ESP (UI settings)
    ----------------------------------------------------------------
    local ESPMainBox   = Tabs.ESP:AddLeftGroupbox("ESP Visual")
    local ESPFilterBox = Tabs.ESP:AddRightGroupbox("Filter / Performance")

    ESPMainBox:AddToggle("ESP_Enable_Toggle", {
        Text    = "Enable ESP",
        Default = true,
        Callback = function(v)
            ESPSettings.Enabled = v
        end
    })

    ESPMainBox:AddDropdown("ESP_BoxMode", {
        Text    = "Box mode",
        Default = "Box",
        Values  = { "Box", "Corner", "Off" },
        Callback = function(v)
            ESPSettings.BoxMode = v
        end
    })

    ESPMainBox:AddToggle("ESP_UseHighlight", {
        Text    = "Use 3D Chams (Highlight)",
        Default = true,
        Callback = function(v)
            ESPSettings.UseHighlight = v
        end
    })

    ESPMainBox:AddToggle("ESP_HeadDot", {
        Text    = "Head dot",
        Default = true,
        Callback = function(v)
            ESPSettings.HeadDot = v
        end
    })

    ESPMainBox:AddToggle("ESP_NameTag", {
        Text    = "Name & distance",
        Default = true,
        Callback = function(v)
            ESPSettings.NameTag = v
        end
    })

    ESPMainBox:AddToggle("ESP_HealthBar", {
        Text    = "Health bar",
        Default = true,
        Callback = function(v)
            ESPSettings.HealthBar = v
        end
    })

    ESPMainBox:AddToggle("ESP_Tracer", {
        Text    = "Tracer",
        Default = true,
        Callback = function(v)
            ESPSettings.Tracer = v
        end
    })

    ESPMainBox:AddToggle("ESP_Offscreen", {
        Text    = "Offscreen arrows",
        Default = false,
        Callback = function(v)
            ESPSettings.OffscreenArrow = v
        end
    })

    ESPMainBox:AddToggle("ESP_UseESPFOV", {
        Text    = "Limit ESP by FOV",
        Default = false,
        Callback = function(v)
            ESPSettings.UseESPFOV = v
        end
    })

    ESPMainBox:AddSlider("ESP_ESPFOVRadius", {
        Text     = "ESP FOV radius (px)",
        Default  = 500,
        Min      = 100,
        Max      = 1000,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.ESPFOVRadius = val
        end
    })

    ESPFilterBox:AddToggle("ESP_TeamCheck", {
        Text    = "Team check",
        Default = true,
        Callback = function(v)
            ESPSettings.TeamCheck = v
        end
    })

    ESPFilterBox:AddToggle("ESP_IgnoreFriends", {
        Text    = "Ignore friends",
        Default = true,
        Callback = function(v)
            ESPSettings.IgnoreFriends = v
        end
    })

    ESPFilterBox:AddToggle("ESP_VisibleOnly", {
        Text    = "Visible only (ESP)",
        Default = false,
        Callback = function(v)
            ESPSettings.VisibleOnly = v
        end
    })

    ESPFilterBox:AddToggle("ESP_WallCheck", {
        Text    = "Wall check (for red/green)",
        Default = true,
        Callback = function(v)
            ESPSettings.WallCheck = v
        end
    })

    ESPFilterBox:AddSlider("ESP_MaxDistance", {
        Text     = "Max distance",
        Default  = 1000,
        Min      = 50,
        Max      = 3000,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.MaxDistance = val
        end
    })

    ESPFilterBox:AddSlider("ESP_MaxPlayers", {
        Text     = "Max players",
        Default  = 30,
        Min      = 5,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.MaxPlayers = val
        end
    })

    ESPFilterBox:AddSlider("ESP_UpdateInterval", {
        Text     = "Update interval (ms)",
        Default  = 80,
        Min      = 10,
        Max      = 250,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.UpdateInterval = val / 1000
        end
    })

    ESPFilterBox:AddDivider()
    ESPFilterBox:AddLabel("<b>Manual whitelist (auto player list)</b>", true)

    local function buildPlayerNameList()
        local list = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(list, plr.Name)
            end
        end
        table.sort(list, function(a, b)
            return a:lower() < b:lower()
        end)
        return list
    end

    local WhitelistDropdown = ESPFilterBox:AddDropdown("ESP_Whitelist_Dropdown", {
        Text    = "Whitelist players",
        Default = {},
        Values  = buildPlayerNameList(),
        Multi   = true,
        Callback = function(selected)
            for name in pairs(WhitelistNames) do
                WhitelistNames[name] = nil
            end

            if type(selected) == "table" then
                for name, enabled in pairs(selected) do
                    if enabled then
                        WhitelistNames[name] = true
                    end
                end
            end
        end
    })

    local WhitelistLabel = ESPFilterBox:AddLabel("Whitelisted: (none)", true)

    local function refreshWhitelistValues()
        local values = buildPlayerNameList()
        local opt = Library.Options.ESP_Whitelist_Dropdown
        if opt and opt.SetValues then
            opt:SetValues(values)
        end

        local names = {}
        for name, ok in pairs(WhitelistNames) do
            if ok then
                table.insert(names, name)
            end
        end
        table.sort(names)
        local text = (#names == 0) and "Whitelisted: (none)" or ("Whitelisted: " .. table.concat(names, ", "))
        if WhitelistLabel and WhitelistLabel.TextLabel then
            WhitelistLabel.TextLabel.Text = text
            WhitelistLabel.TextLabel.RichText = false
        end
    end

    ESPFilterBox:AddButton("Refresh player list", function()
        refreshWhitelistValues()
    end)

    AddConnection(Players.PlayerAdded:Connect(function()
        refreshWhitelistValues()
    end))
    AddConnection(Players.PlayerRemoving:Connect(function(plr)
        if WhitelistNames[plr.Name] then
            WhitelistNames[plr.Name] = nil
        end
        refreshWhitelistValues()
    end))

    ----------------------------------------------------------------
    -- Tab: Aim
    ----------------------------------------------------------------
    local AimBehaviorBox = Tabs.Aim:AddLeftGroupbox("Aimbot Behavior")
    local AimTargetBox   = Tabs.Aim:AddRightGroupbox("Aim Target / Weights")

    AimBehaviorBox:AddToggle("Aim_Enabled", {
        Text    = "Enable Aimbot",
        Default = true,
        Callback = function(v)
            AimSettings.Enabled = v
        end
    })

    AimBehaviorBox:AddSlider("Aim_FOV", {
        Text     = "FOV radius",
        Default  = 120,
        Min      = 30,
        Max      = 300,
        Rounding = 0,
        Callback = function(val)
            AimSettings.FOVRadius = val
        end
    })

    AimBehaviorBox:AddToggle("Aim_ShowFOV", {
        Text    = "Show FOV circle",
        Default = true,
        Callback = function(v)
            AimSettings.ShowFOV = v
        end
    })

    AimBehaviorBox:AddSlider("Aim_Smooth", {
        Text     = "Smooth",
        Default  = 0.25,
        Min      = 0.05,
        Max      = 1,
        Rounding = 2,
        Callback = function(val)
            AimSettings.Smoothing = val
        end
    })

    AimBehaviorBox:AddToggle("Aim_TeamCheck", {
        Text    = "Team check",
        Default = true,
        Callback = function(v)
            AimSettings.TeamCheck = v
        end
    })

    AimBehaviorBox:AddToggle("Aim_IgnoreFriends", {
        Text    = "Ignore friends",
        Default = true,
        Callback = function(v)
            AimSettings.IgnoreFriends = v
        end
    })

    AimBehaviorBox:AddToggle("Aim_VisibleOnly", {
        Text    = "Visible only (Aim)",
        Default = true,
        Callback = function(v)
            AimSettings.VisibleOnly = v
        end
    })

    AimBehaviorBox:AddLabel("Activation: Right mouse button (RMB)", true)

    AimTargetBox:AddDropdown("Aim_Part", {
        Text    = "Aim part mode",
        Default = "Head",
        Values  = {
            "Head",
            "Chest",
            "Arms",
            "Legs",
            "Closest",
            "RandomWeighted",
        },
        Callback = function(v)
            AimSettings.AimPart = v
        end
    })

    AimTargetBox:AddLabel("<b>RandomWeighted: part lock %</b>", true)
    AimTargetBox:AddSlider("Aim_WHead", {
        Text     = "Head weight",
        Default  = 60,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            AimSettings.Weights.Head = val
        end
    })
    AimTargetBox:AddSlider("Aim_WChest", {
        Text     = "Chest weight",
        Default  = 25,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            AimSettings.Weights.Chest = val
        end
    })
    AimTargetBox:AddSlider("Aim_WArms", {
        Text     = "Arms weight",
        Default  = 10,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            AimSettings.Weights.Arms = val
        end
    })
    AimTargetBox:AddSlider("Aim_WLegs", {
        Text     = "Legs weight",
        Default  = 5,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            AimSettings.Weights.Legs = val
        end
    })

    ----------------------------------------------------------------
    -- Tab: Game (stub)
    ----------------------------------------------------------------
    local GameLeftBox  = Tabs.Game:AddLeftGroupbox("Game Info")
    local GameRightBox = Tabs.Game:AddRightGroupbox("Game Modules")

    addRichLabel(GameLeftBox, "<b>Game:</b> " .. gameName)
    addRichLabel(GameLeftBox, string.format("<b>PlaceId:</b> %d", placeId))
    addRichLabel(GameLeftBox, "<b>JobId:</b> " .. jobId)

    GameRightBox:AddLabel("<b>Game module</b>", true)
    GameRightBox:AddLabel("No per-game module configured yet.", true)

    ----------------------------------------------------------------
    -- Tab: UI / Theme / Config
    ----------------------------------------------------------------
    local UIThemeBox  = Tabs.UI:AddLeftGroupbox("UI / Theme")
    local UIConfigBox = Tabs.UI:AddRightGroupbox("Config / Misc")

    UIThemeBox:AddLabel("<b>Theme</b>", true)
    UIThemeBox:AddDivider()

    if ThemeManager then
        if ThemeManager.ApplyToTab then
            ThemeManager:ApplyToTab(Tabs.UI)
        end
        if ThemeManager.BuildThemeSection then
            ThemeManager:BuildThemeSection(UIThemeBox)
        end
    end

    UIConfigBox:AddLabel("<b>Config</b>", true)
    UIConfigBox:AddDivider()

    if SaveManager and SaveManager.BuildConfigSection then
        -- สำคัญ: ต้องส่ง Tab เข้าไป ไม่ใช่ Groupbox
        SaveManager:BuildConfigSection(Tabs.UI)
    else
        UIConfigBox:AddLabel("SaveManager not fully available.", true)
    end

    UIConfigBox:AddDivider()
    UIConfigBox:AddButton("Unload Hub", function()
        CleanupConnections()
        pcall(function()
            HighlightFolder:Destroy()
        end)
        hideAllDraw()
        if FOVCircle then
            FOVCircle.Visible = false
        end
        Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    UIConfigBox:AddButton("Copy Discord", function()
        local ok, err = Exec.SetClipboard("https://discord.gg/yourdiscord")
        if ok then
            Notify("Copied Discord link", 3)
        else
            Notify("Clipboard not available: " .. tostring(err), 3)
        end
    end)

    ----------------------------------------------------------------
    -- Main loops: update targets + render ESP + aimbot
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
end
