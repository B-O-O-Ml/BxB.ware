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

    -- Role hierarchy: add "free" as tier 0 and shift priorities accordingly
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
        -- Unknown roles default to the lowest tier (free)
        r = tostring(r or "free"):lower()
        return RolePriority[r] or 0
    end

    local function RoleAtLeast(minRole)
        return GetRolePriority(role) >= GetRolePriority(minRole)
    end

    local function GetRoleLabel(r)
        r = tostring(r or "free"):lower()
        if r == "free" then
            return "Free"
        elseif r == "user" then
            return "User"
        elseif r == "trial" then
            return "Trial"
        elseif r == "premium" then
            return "Premium"
        elseif r == "reseller" then
            return "Reseller"
        elseif r == "vip" then
            return "VIP"
        elseif r == "staff" then
            return "Staff"
        elseif r == "owner" then
            return "Owner"
        else
            return r
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
        VisibleOnly     = false,   -- ซ่อนเป้าหลังกำแพง สำหรับ ESP
        WallCheck       = true,    -- ใช้ raycast เช็คกำแพง (เปลี่ยนสีแดง/เขียว)
        MaxDistance     = 1000,
        MaxPlayers      = 30,
        UpdateInterval  = 0.08,    -- วินาที (จาก slider ms)
        UseESPFOV       = false,
        ESPFOVRadius    = 500,

        DistanceFade    = false,
        FadeStart       = 500,
        FadeEnd         = 2000,
        -- Customisation options (can be changed via UI)
        BoxColor        = Color3.fromRGB(0, 255, 0),
        NameColor       = Color3.fromRGB(0, 255, 0),
        TracerColor     = Color3.fromRGB(0, 255, 0),
        ChamsColor      = Color3.fromRGB(0, 255, 0),
        TextSize        = 13,
        LineThickness   = 1,
        LookTracer      = false,
    }

    local AimSettings = {
        Enabled       = true,
        Mode          = "Legit",           -- Legit / Rage (ใช้เป็น preset)
        AimType       = "Hold",            -- Hold / Toggle
        AimPart       = "Head",            -- Head/Chest/Arms/Legs/Closest/RandomWeighted
        FOVRadius     = 120,
        ShowFOV       = true,
        Smoothing     = 0.25,              -- 0.05–1 (ใน UI map เป็น 1–20)
        VisibleOnly   = true,
        TeamCheck     = true,
        IgnoreFriends = true,
        MaxDistance   = 1000,
        HitChance     = 100,               -- 0–100
        Key           = Enum.UserInputType.MouseButton2, -- RMB
        Weights       = {                  -- สำหรับ RandomWeighted
            Head  = 60,
            Chest = 25,
            Arms  = 10,
            Legs  = 5,
        },
    }

    local AimToggleState = false -- สำหรับ AimType = "Toggle"

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
        FOVCircle.Transparency = 1
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
        t.Box.Transparency = 1

        t.Tracer = Drawing.new("Line")
        t.Tracer.Thickness = 1
        t.Tracer.Visible = false
        t.Tracer.Color = Color3.new(1, 1, 1)
        t.Tracer.Transparency = 1

        t.Name = Drawing.new("Text")
        t.Name.Size = 13
        t.Name.Center = true
        t.Name.Outline = true
        t.Name.Visible = false
        t.Name.Color = Color3.new(1, 1, 1)
        t.Name.Transparency = 1

        t.HealthBar = Drawing.new("Line")
        t.HealthBar.Thickness = 3
        t.HealthBar.Visible = false
        t.HealthBar.Color = Color3.new(0, 1, 0)
        t.HealthBar.Transparency = 1

        t.HeadDot = Drawing.new("Circle")
        t.HeadDot.Thickness = 2
        t.HeadDot.Filled = false
        t.HeadDot.Visible = false
        t.HeadDot.Color = Color3.new(1, 1, 1)
        t.HeadDot.Transparency = 1

        t.Offscreen = Drawing.new("Triangle")
        t.Offscreen.Filled = true
        t.Offscreen.Visible = false
        t.Offscreen.Color = Color3.new(1, 1, 1)
        t.Offscreen.Transparency = 1

        t.Corners = {}
        for i = 1, 4 do
            local c = Drawing.new("Line")
            c.Thickness = 1
            c.Visible = false
            c.Color = Color3.new(1, 1, 1)
            c.Transparency = 1
            table.insert(t.Corners, c)
        end

        -- Allocate skeleton and look tracer lines for future custom ESP features.
        -- We use a fixed number of lines (8) to connect major body parts such as head, torso, arms, and legs.
        t.Skeleton = {}
        for i = 1, 8 do
            local l = Drawing.new("Line")
            l.Thickness = 1
            l.Visible = false
            l.Color = Color3.new(1, 1, 1)
            l.Transparency = 1
            table.insert(t.Skeleton, l)
        end

        -- Single line for look tracer (line pointing in the direction the target is looking).
        t.LookTracer = Drawing.new("Line")
        t.LookTracer.Thickness = 1
        t.LookTracer.Visible = false
        t.LookTracer.Color = Color3.new(1, 1, 1)
        t.LookTracer.Transparency = 1

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

        -- Hide skeleton and look tracer lines if they exist.
        if objs.Skeleton then
            for _, line in ipairs(objs.Skeleton) do
                line.Visible = false
            end
        end
        if objs.LookTracer then
            objs.LookTracer.Visible = false
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

    -- Permanently destroy all drawing objects and reset FOVCircle.
    -- This is used when disabling ESP or unloading the hub to free resources.
    local function removeAllDraw()
        -- Remove draw objects
        for plr, objs in pairs(DrawObjects) do
            if objs then
                -- Basic shapes
                if objs.Box then pcall(function() objs.Box:Remove() end) end
                if objs.Tracer then pcall(function() objs.Tracer:Remove() end) end
                if objs.Name then pcall(function() objs.Name:Remove() end) end
                if objs.HealthBar then pcall(function() objs.HealthBar:Remove() end) end
                if objs.HeadDot then pcall(function() objs.HeadDot:Remove() end) end
                if objs.Offscreen then pcall(function() objs.Offscreen:Remove() end) end
                -- Corner lines
                if objs.Corners then
                    for _, c in ipairs(objs.Corners) do
                        pcall(function() c:Remove() end)
                    end
                end
                -- Skeleton lines
                if objs.Skeleton then
                    for _, l in ipairs(objs.Skeleton) do
                        pcall(function() l:Remove() end)
                    end
                end
                -- Look tracer line
                if objs.LookTracer then
                    pcall(function() objs.LookTracer:Remove() end)
                end
            end
        end
        table.clear(DrawObjects)
        -- Remove FOV circle
        if FOVCircle then
            pcall(function() FOVCircle:Remove() end)
            FOVCircle = nil
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

        if AimSettings.AimType == "Hold" then
            if key == Enum.UserInputType.MouseButton2 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            end
            return false
        else -- Toggle mode
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
            if info.Valid and info.ShouldRender and info.Distance <= AimSettings.MaxDistance then
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

        -- HitChance
        local chance = math.clamp(AimSettings.HitChance or 100, 0, 100)
        if chance < 100 then
            if math.random(1, 100) > chance then
                return
            end
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

        local smoothSlider = AimSettings.Smoothing -- 0.05–1
        local alpha = math.clamp(smoothSlider, 0.05, 1)

        cam.CFrame = currentCF:Lerp(targetCF, alpha)
    end

    ----------------------------------------------------------------
    -- ESP render step (ไม่มี goto / continue)
    ----------------------------------------------------------------
    local function espStep()
        local cam = workspace.CurrentCamera
        if not cam then
            hideAllDraw()
            return
        end

        local viewSize     = cam.ViewportSize
        local screenCenter = viewSize / 2

        -- FOV circle (Aimbot)
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

        if not hasDrawing then
            return
        end

        -- Precompute colours and styling based off user settings.
        local baseBoxColor      = ESPSettings.BoxColor or Color3.fromRGB(0, 255, 0)
        local baseNameColor     = ESPSettings.NameColor or baseBoxColor
        local baseTracerColor   = ESPSettings.TracerColor or baseBoxColor
        local baseChamsColor    = ESPSettings.ChamsColor or baseBoxColor
        local lineThick         = ESPSettings.LineThickness or 1
        local textSize          = ESPSettings.TextSize or 13
        local skeletonEnabled   = (ESPSettings.Skeleton == true)
        local lookTracerEnabled = (ESPSettings.LookTracer == true)

        -- Ensure FOVCircle thickness reflects the custom line thickness.
        if hasDrawing and FOVCircle then
            FOVCircle.Thickness = lineThick
        end

        for plr, info in pairs(PlayerInfo) do
            local objs = getDrawObjects(plr)

            if not info.Valid or not info.ShouldRender then
                hideDrawFor(plr)
                if info.Character then
                    removeHighlight(info.Character)
                end
            else
                local skip = false

                -- VisibleOnly (ESP)
                if ESPSettings.VisibleOnly and not info.Visible then
                    hideDrawFor(plr)
                    if info.Character then
                        removeHighlight(info.Character)
                    end
                    skip = true
                end

                -- ESP FOV limit
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
                    -- Determine colours for visible/hidden targets.
                    local colorBox    = info.Visible and baseBoxColor    or Color3.fromRGB(255, 0, 0)
                    local colorName   = info.Visible and baseNameColor   or Color3.fromRGB(255, 0, 0)
                    local colorTracer = info.Visible and baseTracerColor or Color3.fromRGB(255, 0, 0)
                    local colorCham   = info.Visible and baseChamsColor  or Color3.fromRGB(255, 0, 0)

                    -- Distance fade alpha
                    local alpha = 1
                    if ESPSettings.DistanceFade then
                        local s = ESPSettings.FadeStart
                        local e = ESPSettings.FadeEnd
                        local d = info.Distance
                        if d >= s then
                            if d >= e then
                                alpha = 0
                            else
                                local t = (d - s) / math.max(e - s, 1)
                                alpha = 1 - t
                            end
                        end
                        alpha = math.clamp(alpha, 0, 1)
                    end

                    -- 3D Chams
                    if ESPSettings.UseHighlight then
                        local hl = getHighlight(info.Character)
                        if hl then
                            hl.FillColor    = colorCham
                            hl.OutlineColor = colorCham
                            hl.FillTransparency    = 0.7 + (1 - alpha) * 0.2
                            hl.OutlineTransparency = 0 + (1 - alpha) * 0.3
                        end
                    else
                        removeHighlight(info.Character)
                    end

                    -- 2D ESP
                    if ESPSettings.Enabled then
                        local screenPos = info.ScreenPos
                        local distance  = info.Distance

                        -- ขนาด Box auto-scale ตามระยะ
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

                                objs.Offscreen.Visible = alpha > 0
                                objs.Offscreen.PointA  = p1
                                objs.Offscreen.PointB  = p2
                                objs.Offscreen.PointC  = p3
                                objs.Offscreen.Color   = colorTracer
                                objs.Offscreen.Transparency = 1 - alpha
                            end
                        else
                            objs.Offscreen.Visible = false
                        end

                        if not info.OnScreen or alpha <= 0 then
                            objs.Box.Visible       = false
                            objs.Tracer.Visible    = false
                            objs.Name.Visible      = false
                            objs.HealthBar.Visible = false
                            objs.HeadDot.Visible   = false
                            for _, c in ipairs(objs.Corners) do
                                c.Visible = false
                            end
                        else
                            -- Reset all corners
                            for _, c in ipairs(objs.Corners) do
                                c.Visible      = false
                            end
                            objs.Box.Visible = false

                            if ESPSettings.BoxMode == "Box" then
                                objs.Box.Visible      = true
                                objs.Box.Position     = topLeft
                                objs.Box.Size         = boxSize
                                objs.Box.Color        = colorBox
                                objs.Box.Thickness    = lineThick
                                objs.Box.Transparency = 1 - alpha
                            elseif ESPSettings.BoxMode == "Corner" then
                                local w, h = boxSize.X, boxSize.Y
                                local tl   = topLeft
                                local tr   = topLeft + Vector2.new(w, 0)
                                local len  = math.max(4, math.floor(w * 0.2))

                                local corners = objs.Corners
                                if corners[1] then
                                    corners[1].Visible      = true
                                    corners[1].From         = tl
                                    corners[1].To           = tl + Vector2.new(len, 0)
                                    corners[1].Color        = colorBox
                                    corners[1].Thickness    = lineThick
                                    corners[1].Transparency = 1 - alpha
                                end
                                if corners[2] then
                                    corners[2].Visible      = true
                                    corners[2].From         = tl
                                    corners[2].To           = tl + Vector2.new(0, len)
                                    corners[2].Color        = colorBox
                                    corners[2].Thickness    = lineThick
                                    corners[2].Transparency = 1 - alpha
                                end
                                if corners[3] then
                                    corners[3].Visible      = true
                                    corners[3].From         = tr
                                    corners[3].To           = tr + Vector2.new(-len, 0)
                                    corners[3].Color        = colorBox
                                    corners[3].Thickness    = lineThick
                                    corners[3].Transparency = 1 - alpha
                                end
                                if corners[4] then
                                    corners[4].Visible      = true
                                    corners[4].From         = tr
                                    corners[4].To           = tr + Vector2.new(0, len)
                                    corners[4].Color        = colorBox
                                    corners[4].Thickness    = lineThick
                                    corners[4].Transparency = 1 - alpha
                                end
                            end

                            -- Tracer
                            if ESPSettings.Tracer then
                                local fromPos = Vector2.new(viewSize.X / 2, viewSize.Y)
                                objs.Tracer.Visible      = true
                                objs.Tracer.From         = fromPos
                                objs.Tracer.To           = screenPos
                                objs.Tracer.Color        = colorTracer
                                objs.Tracer.Thickness    = lineThick
                                objs.Tracer.Transparency = 1 - alpha
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
                                objs.Name.Visible      = true
                                objs.Name.Text         = text
                                objs.Name.Position     = Vector2.new(screenPos.X, topLeft.Y - 12)
                                objs.Name.Color        = colorName
                                objs.Name.Size         = textSize
                                objs.Name.Transparency = 1 - alpha
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
                                -- Thickness of health bar scales with line thickness (minimum 1).
                                objs.HealthBar.Thickness    = math.max(1, math.floor(lineThick * 3))
                                objs.HealthBar.Transparency = 1 - alpha
                            else
                                objs.HealthBar.Visible = false
                            end

                            -- Head dot
                            if ESPSettings.HeadDot and info.Head then
                                local headPos3D = info.Head.Position
                                local headView, onHeadScreen = cam:WorldToViewportPoint(headPos3D)
                                if onHeadScreen then
                                    objs.HeadDot.Visible     = true
                                    objs.HeadDot.Position    = Vector2.new(headView.X, headView.Y)
                                    objs.HeadDot.Radius      = 3
                                    objs.HeadDot.Color       = colorBox
                                    objs.HeadDot.Transparency = 1 - alpha
                                else
                                    objs.HeadDot.Visible = false
                                end
                            else
                                objs.HeadDot.Visible = false
                            end
                            -- Skeleton rendering
                            if skeletonEnabled and objs.Skeleton and info.Character then
                                local char = info.Character
                                local cam = workspace.CurrentCamera
                                local p = info.AimParts or {}
                                -- gather relevant parts or fallback to char joints
                                local head       = p.Head or char:FindFirstChild("Head")
                                local upperTorso = p.UpperTorso or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
                                local lowerTorso = p.LowerTorso or char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso")
                                local lUpperArm  = p.LeftUpperArm or char:FindFirstChild("LeftUpperArm")
                                local lLowerArm  = p.LeftLowerArm or char:FindFirstChild("LeftLowerArm")
                                local rUpperArm  = p.RightUpperArm or char:FindFirstChild("RightUpperArm")
                                local rLowerArm  = p.RightLowerArm or char:FindFirstChild("RightLowerArm")
                                local lUpperLeg  = p.LeftUpperLeg or char:FindFirstChild("LeftUpperLeg")
                                local lLowerLeg  = p.LeftLowerLeg or char:FindFirstChild("LeftLowerLeg")
                                local rUpperLeg  = p.RightUpperLeg or char:FindFirstChild("RightUpperLeg")
                                local rLowerLeg  = p.RightLowerLeg or char:FindFirstChild("RightLowerLeg")
                                -- Build pairs for lines (up to 8 lines allocated)
                                local pairsList = {
                                    {head, upperTorso},
                                    {upperTorso, lUpperArm},
                                    {lUpperArm, lLowerArm},
                                    {upperTorso, rUpperArm},
                                    {rUpperArm, rLowerArm},
                                    {upperTorso, lowerTorso},
                                    {lowerTorso, lUpperLeg},
                                    {lUpperLeg, lLowerLeg},
                                }
                                for i = 1, #objs.Skeleton do
                                    local line = objs.Skeleton[i]
                                    local pair = pairsList[i]
                                    if pair then
                                        local a, b = pair[1], pair[2]
                                        if a and b then
                                            local aPos3d, aOn = cam:WorldToViewportPoint(a.Position)
                                            local bPos3d, bOn = cam:WorldToViewportPoint(b.Position)
                                            if aOn and bOn then
                                                line.Visible      = true
                                                line.From         = Vector2.new(aPos3d.X, aPos3d.Y)
                                                line.To           = Vector2.new(bPos3d.X, bPos3d.Y)
                                                line.Color        = colorBox
                                                line.Thickness    = lineThick
                                                line.Transparency = 1 - alpha
                                            else
                                                line.Visible = false
                                            end
                                        else
                                            line.Visible = false
                                        end
                                    else
                                        line.Visible = false
                                    end
                                end
                            else
                                if objs.Skeleton then
                                    for _, line in ipairs(objs.Skeleton) do
                                        line.Visible = false
                                    end
                                end
                            end

                            -- Look tracer rendering
                            if lookTracerEnabled and objs.LookTracer and info.Head then
                                local cam = workspace.CurrentCamera
                                local headPos3d, onScr = cam:WorldToViewportPoint(info.Head.Position)
                                local dir = info.Head.CFrame.LookVector
                                local targetPos = info.Head.Position + dir * 30
                                local target3d, onScr2 = cam:WorldToViewportPoint(targetPos)
                                if onScr and onScr2 then
                                    objs.LookTracer.Visible      = true
                                    objs.LookTracer.From         = Vector2.new(headPos3d.X, headPos3d.Y)
                                    objs.LookTracer.To           = Vector2.new(target3d.X, target3d.Y)
                                    objs.LookTracer.Color        = colorTracer
                                    objs.LookTracer.Thickness    = lineThick
                                    objs.LookTracer.Transparency = 1 - alpha
                                else
                                    objs.LookTracer.Visible = false
                                end
                            else
                                if objs.LookTracer then
                                    objs.LookTracer.Visible = false
                                end
                            end
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
        WalkSpeedEnabled = false,
        WalkSpeedValue   = 16,
        WalkSpeedLock    = false,

        JumpEnabled      = false,
        JumpValue        = 50,
        JumpLock         = false,

        InfiniteJump     = false,
        Fly              = false,
        FlySpeed         = 60,
        NoClip           = false,
        -- Additional movement toggles
        SpinBot          = false,
        AntiAim          = false,
        AutoRun          = false,
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

    -- Click teleport state (used for Ctrl+Click teleport feature)
    local ClickTPEnabled = false
    local ClickTPConn

    AddConnection(LocalPlayer.CharacterAdded:Connect(function(char)
        task.defer(function()
            local hum = char:WaitForChild("Humanoid", 5)
            if hum then
                DefaultWalkSpeed = hum.WalkSpeed
                DefaultJumpPower = hum.JumpPower

                if MovementState.WalkSpeedEnabled and MovementState.WalkSpeedLock then
                    hum.WalkSpeed = MovementState.WalkSpeedValue
                end
                if MovementState.JumpEnabled and MovementState.JumpLock then
                    hum.JumpPower = MovementState.JumpValue
                end
            end
        end)
    end))

    AddConnection(UserInputService.JumpRequest:Connect(function()
        if MovementState.InfiniteJump then
            local hum = GetHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
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

        -- Additional movement behaviours
        if root and hum then
            -- SpinBot: rotate character's root part continuously
            if MovementState.SpinBot then
                -- spin speed in radians per frame
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(10), 0)
            end

            -- Anti-Aim: rotate character to look downwards or sideways
            if MovementState.AntiAim then
                local pos = root.Position
                -- Keep constant rotation pointing downward
                root.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-90), 0, 0)
            end

            -- Auto Run: move character forward automatically
            if MovementState.AutoRun and not MovementState.Fly then
                local camDir = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.LookVector or Vector3.new(0, 0, -1)
                -- Remove vertical component
                camDir = Vector3.new(camDir.X, 0, camDir.Z)
                if camDir.Magnitude > 0 then
                    camDir = camDir.Unit
                    -- Apply a small forward force; adjust WalkSpeed to maintain constant speed
                    hum:Move(camDir, false)
                    if MovementState.WalkSpeedEnabled then
                        hum.WalkSpeed = MovementState.WalkSpeedValue
                    end
                end
            end
        end
    end))

    ----------------------------------------------------------------
    -- Anti-AFK
    ----------------------------------------------------------------
    local AntiAFKConn
    local AntiAFKInterval = 60

    local function setAntiAFK(enabled)
        if enabled then
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
                if not VirtualUser then
                    Notify("VirtualUser not available", 3)
                end
            end
        else
            if AntiAFKConn then
                AntiAFKConn:Disconnect()
                AntiAFKConn = nil
            end
            Notify("Anti-AFK disabled", 3)
        end
    end

    ----------------------------------------------------------------
    -- Fullbright
    ----------------------------------------------------------------
    local FullbrightEnabled = false
    local SavedLighting = {}

    local function saveLighting()
        SavedLighting.Ambient            = Lighting.Ambient
        SavedLighting.OutdoorAmbient     = Lighting.OutdoorAmbient
        SavedLighting.Brightness         = Lighting.Brightness
        SavedLighting.ColorShift_Bottom  = Lighting.ColorShift_Bottom
        SavedLighting.ColorShift_Top     = Lighting.ColorShift_Top
        SavedLighting.EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale
        SavedLighting.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
    end

    local function applyFullbright()
        saveLighting()
        Lighting.Ambient           = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient    = Color3.new(1, 1, 1)
        Lighting.Brightness        = 2
        Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
        Lighting.ColorShift_Top    = Color3.new(0, 0, 0)
        Lighting.EnvironmentDiffuseScale  = 1
        Lighting.EnvironmentSpecularScale = 1
    end

    local function restoreLighting()
        for k, v in pairs(SavedLighting) do
            Lighting[k] = v
        end
    end

    ----------------------------------------------------------------
    -- Window + Tabs (ตามสเปกใหม่)
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
        Info = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "database", Description = "Key Status / Info"}),
        Player = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "users", Description = "Player Tool"}),
        Combat    = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "eye", Description = "Combat Client"}),
        ESP   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "crosshair", Description = "ESP Client"}),
        Misc    = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "crosshair", Description = "Misc Client"}),
        Game   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "joystick", Description = "Game Module"}),
        Settings     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "settings", Description = "UI/UX Setings"}),
    }


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
    -- Tab: Info (Key / Game / Player / FPS / Ping / Memory)
    ----------------------------------------------------------------
    local InfoKeyBox    = Tabs.Info:AddLeftGroupbox("Key / Role")
    local InfoSystemBox = Tabs.Info:AddRightGroupbox("Game / System")

    local keyRole      = GetRoleLabel(keydata.role)
    local keyNote      = tostring(keydata.note or "")
    local keyStamp     = tonumber(keydata.timestamp)
    local keyExpire    = tonumber(keydata.expire)
    local keyCreatedAt = keyStamp and formatUnix(keyStamp) or "N/A"
    local keyExpireAt  = keyExpire and formatUnix(keyExpire) or "Lifetime"
    local roleColorHex = GetRoleColorHex(role)

    InfoKeyBox:AddLabel("<b>Key Information</b>", true)
    InfoKeyBox:AddDivider()
    addRichLabel(InfoKeyBox, string.format("<b>Key</b>: %s", shortKey(keydata.key)))
    addRichLabel(InfoKeyBox, string.format("<b>Role</b>: <font color=\"%s\">%s</font>", roleColorHex, keyRole))
    addRichLabel(InfoKeyBox, string.format("<b>Status</b>: %s", keyStatus))
    addRichLabel(InfoKeyBox, string.format("<b>Tier</b>: %s", GetTierLabel()))
    addRichLabel(InfoKeyBox, string.format("<b>Note</b>: %s", (keyNote ~= "" and keyNote or "N/A")))
    addRichLabel(InfoKeyBox, string.format("<b>Created at</b>: %s", keyCreatedAt))
    local ExpireLabel   = addRichLabel(InfoKeyBox, string.format("<b>Expire at</b>: %s", keyExpireAt))
    local TimeLeftLabel = addRichLabel(InfoKeyBox, string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire)))

    InfoKeyBox:AddDivider()
    addRichLabel(InfoKeyBox, '<font color="#ffcc66">Key is bound to your HWID. Sharing key may result in ban.</font>')

    AddConnection(RunService.Heartbeat:Connect(function()
        if TimeLeftLabel and TimeLeftLabel.TextLabel then
            TimeLeftLabel.TextLabel.Text = string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire))
            TimeLeftLabel.TextLabel.RichText = true
        end
    end))

    InfoSystemBox:AddLabel("<b>Game / System / Player</b>", true)
    InfoSystemBox:AddDivider()

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
        Game   = addRichLabel(InfoSystemBox, string.format("<b>Game</b>: %s (PlaceId: %d)", gameName, placeId)),
        Server = addRichLabel(InfoSystemBox, string.format("<b>JobId</b>: %s", jobId)),
        Player = addRichLabel(InfoSystemBox, string.format("<b>Player</b>: %s (%d)", LocalPlayer.Name, LocalPlayer.UserId)),
        FPS    = addRichLabel(InfoSystemBox, "<b>FPS</b>: ..."),
        Ping   = addRichLabel(InfoSystemBox, "<b>Ping</b>: ..."),
        Memory = addRichLabel(InfoSystemBox, "<b>Memory</b>: ... MB"),
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

    InfoSystemBox:AddDivider()
    InfoSystemBox:AddLabel("<b>Credits</b>", true)
    InfoSystemBox:AddLabel("Owner: YOUR_NAME_HERE", true)
    InfoSystemBox:AddLabel("UI: Obsidian UI Library", true)
    InfoSystemBox:AddLabel("Discord: yourdiscord", true)

    ----------------------------------------------------------------
    -- Tab: Player (Movement / Teleport & Utility / View)
    ----------------------------------------------------------------
    local MoveBox   = Tabs.Player:AddLeftGroupbox("Movement & Character")
    local UtilBox   = Tabs.Player:AddRightGroupbox("Teleport / Utility / View")

    -- Movement: WalkSpeed
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
        Min      = 0,
        Max      = 200,
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

    MoveBox:AddToggle("Move_WalkSpeed_Lock", {
        Text    = "Lock on spawn",
        Default = true,
        Callback = function(v)
            MovementState.WalkSpeedLock = v
        end
    })

    MoveBox:AddDivider()

    -- Movement: JumpPower
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
        Min      = 0,
        Max      = 200,
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

    MoveBox:AddToggle("Move_Jump_Lock", {
        Text    = "Lock on spawn",
        Default = true,
        Callback = function(v)
            MovementState.JumpLock = v
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
        Text    = "Fly (WASD / Space / Ctrl)",
        Default = false,
        Callback = function(v)
            MovementState.Fly = v
        end
    })

    MoveBox:AddSlider("Move_FlySpeed_Slider", {
        Text     = "Fly speed",
        Default  = 60,
        Min      = 1,
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

    MoveBox:AddDivider()
    MoveBox:AddButton("Reset movement", function()
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

    -- Additional movement toggles
    MoveBox:AddToggle("Move_SpinBot", {
        Text    = "SpinBot",
        Default = false,
        Callback = function(v)
            -- Require VIP or higher for SpinBot
            if v and not RoleAtLeast("vip") then
                Notify("SpinBot requires VIP or higher", 3)
                local opt = Library.Options.Move_SpinBot
                if opt and opt.SetValue then
                    opt:SetValue(false)
                end
                return
            end
            MovementState.SpinBot = v
        end
    })

    MoveBox:AddToggle("Move_AntiAim", {
        Text    = "Anti-Aim (Desync/Look down)",
        Default = false,
        Callback = function(v)
            -- Require VIP or higher for Anti-Aim
            if v and not RoleAtLeast("vip") then
                Notify("Anti-Aim requires VIP or higher", 3)
                local opt = Library.Options.Move_AntiAim
                if opt and opt.SetValue then
                    opt:SetValue(false)
                end
                return
            end
            MovementState.AntiAim = v
        end
    })

    MoveBox:AddToggle("Move_AutoRun", {
        Text    = "Auto Run",
        Default = false,
        Callback = function(v)
            MovementState.AutoRun = v
        end
    })

    -- Teleport & Utility
    UtilBox:AddLabel("<b>Teleport to Player</b>", true)
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

    local TeleportTarget = nil

    local TeleportDropdown = UtilBox:AddDropdown("TP_TargetPlayer", {
        Text    = "Target player",
        Default = "",
        Values  = buildPlayerNameList(),
        Callback = function(v)
            TeleportTarget = v
        end
    })

    UtilBox:AddButton("Teleport now", function()
        if not TeleportTarget then
            Notify("No target selected", 3)
            return
        end
        local target = Players:FindFirstChild(TeleportTarget)
        if not target or not target.Character then
            Notify("Target not available", 3)
            return
        end
        local myRoot = GetRoot()
        local theirRoot = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Torso")
        if myRoot and theirRoot then
            myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, 3, 0)
        end
    end)

    UtilBox:AddButton("Refresh player list", function()
        local values = buildPlayerNameList()
        local opt = Library.Options.TP_TargetPlayer
        if opt and opt.SetValues then
            opt:SetValues(values)
        end
    end)

    UtilBox:AddDivider()
    UtilBox:AddLabel("<b>View / Camera</b>", true)

    local FOVDefault = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
    local FOVEnabled = false

    UtilBox:AddToggle("View_FOV_Toggle", {
        Text    = "Enable FOV changer",
        Default = false,
        Callback = function(v)
            FOVEnabled = v
            local cam = workspace.CurrentCamera
            if cam then
                if not v then
                    cam.FieldOfView = FOVDefault
                end
            end
        end
    })

    UtilBox:AddSlider("View_FOV_Slider", {
        Text     = "FOV",
        Default  = FOVDefault,
        Min      = 40,
        Max      = 120,
        Rounding = 0,
        Callback = function(val)
            local cam = workspace.CurrentCamera
            if cam and FOVEnabled then
                cam.FieldOfView = val
            end
        end
    })

    UtilBox:AddToggle("View_Fullbright_Toggle", {
        Text    = "Fullbright (world)",
        Default = false,
        Callback = function(v)
            FullbrightEnabled = v
            if v then
                applyFullbright()
            else
                restoreLighting()
            end
        end
    })

    UtilBox:AddDivider()
    UtilBox:AddButton("Rejoin server", function()
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
        end)
        if not ok then
            Notify("Rejoin failed: " .. tostring(err), 4)
        end
    end)

    UtilBox:AddButton("Server hop (random)", function()
        local ok, err = pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)
        if not ok then
            Notify("Server hop failed: " .. tostring(err), 4)
        end
    end)

    -- Ctrl+Click Teleport
    UtilBox:AddToggle("Util_ClickTP_Toggle", {
        Text    = "Ctrl+Click Teleport",
        Default = false,
        Callback = function(v)
            -- Require user role or higher
            if v and not RoleAtLeast("user") then
                Notify("Click Teleport requires User or higher", 3)
                local opt = Library.Options.Util_ClickTP_Toggle
                if opt and opt.SetValue then
                    opt:SetValue(false)
                end
                return
            end
            ClickTPEnabled = v
            -- Disconnect existing connection if toggling off
            if ClickTPConn then
                ClickTPConn:Disconnect()
                ClickTPConn = nil
            end
            if v then
                -- Bind teleport to mouse left click while holding LeftControl
                ClickTPConn = UserInputService.InputBegan:Connect(function(input, gpe)
                    if gpe then return end
                    if input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                        local mouse = LocalPlayer:GetMouse()
                        if mouse then
                            local hit = mouse.Hit
                            if hit then
                                local targetPos = hit.Position + Vector3.new(0, 3, 0)
                                local root = GetRoot()
                                if root then
                                    root.CFrame = CFrame.new(targetPos)
                                end
                            end
                        end
                    end
                end)
                AddConnection(ClickTPConn)
            end
        end
    })

    ----------------------------------------------------------------
    -- Tab: ESP & Visuals
    ----------------------------------------------------------------
    local ESPMainBox   = Tabs.ESP:AddLeftGroupbox("Player ESP")
    local ESPFilterBox = Tabs.ESP:AddRightGroupbox("Filter / Visual / Whitelist")

    ESPMainBox:AddToggle("ESP_Enable_Toggle", {
        Text    = "Enable ESP",
        Default = true,
        Callback = function(v)
            ESPSettings.Enabled = v
            -- When disabling ESP, destroy all drawing objects and remove highlights.
            if not v then
                removeAllDraw()
                -- Remove 3D highlights from all characters.
                for plr, info in pairs(PlayerInfo) do
                    if info.Character then
                        removeHighlight(info.Character)
                    end
                end
            else
                -- When re-enabling, recreate FOV circle if needed.
                if hasDrawing and not FOVCircle then
                    local c = Drawing.new("Circle")
                    c.Thickness = ESPSettings.LineThickness or 1
                    c.Filled     = false
                    c.Visible    = false
                    c.Color      = Color3.fromRGB(255, 255, 255)
                    c.Transparency = 1
                    FOVCircle = c
                end
            end
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
        Text    = "3D Chams (Highlight)",
        Default = true,
        Callback = function(v)
            ESPSettings.UseHighlight = v
            -- When turning off highlight, remove existing highlights on players.
            if not v then
                for plr, info in pairs(PlayerInfo) do
                    if info.Character then
                        removeHighlight(info.Character)
                    end
                end
            end
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
            ESPSettings.ShowDistance = v
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
        Text    = "Wall check (สำหรับสีแดง/เขียว)",
        Default = true,
        Callback = function(v)
            ESPSettings.WallCheck = v
        end
    })

    ESPFilterBox:AddSlider("ESP_MaxDistance", {
        Text     = "Max distance",
        Default  = 1000,
        Min      = 50,
        Max      = 5000,
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
    ESPFilterBox:AddToggle("ESP_DistanceFade_Toggle", {
        Text    = "Distance fade",
        Default = false,
        Callback = function(v)
            ESPSettings.DistanceFade = v
        end
    })

    ESPFilterBox:AddSlider("ESP_FadeStart", {
        Text     = "Fade start",
        Default  = 500,
        Min      = 0,
        Max      = 5000,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.FadeStart = val
        end
    })

    ESPFilterBox:AddSlider("ESP_FadeEnd", {
        Text     = "Fade end",
        Default  = 2000,
        Min      = 0,
        Max      = 5000,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.FadeEnd = val
        end
    })

    ESPFilterBox:AddDivider()
    ESPFilterBox:AddLabel("<b>Manual whitelist</b>", true)

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

    -- Additional groupbox: Colours & Style for ESP customization
    local ESPStyleBox = Tabs.ESP:AddLeftGroupbox("Colours & Style")
    ESPStyleBox:AddLabel("<b>Colors</b>", true)
    ESPStyleBox:AddColorPicker("ESP_BoxColor_Picker", {
        Text     = "Box colour",
        Default  = ESPSettings.BoxColor,
        Callback = function(col)
            ESPSettings.BoxColor = col
        end
    })
    ESPStyleBox:AddColorPicker("ESP_NameColor_Picker", {
        Text     = "Name colour",
        Default  = ESPSettings.NameColor,
        Callback = function(col)
            ESPSettings.NameColor = col
        end
    })
    ESPStyleBox:AddColorPicker("ESP_TracerColor_Picker", {
        Text     = "Tracer colour",
        Default  = ESPSettings.TracerColor,
        Callback = function(col)
            ESPSettings.TracerColor = col
        end
    })
    ESPStyleBox:AddColorPicker("ESP_ChamsColor_Picker", {
        Text     = "Chams colour",
        Default  = ESPSettings.ChamsColor,
        Callback = function(col)
            ESPSettings.ChamsColor = col
        end
    })
    ESPStyleBox:AddDivider()
    ESPStyleBox:AddToggle("ESP_Skeleton_Toggle", {
        Text    = "Show skeleton",
        Default = false,
        Callback = function(v)
            ESPSettings.Skeleton = v
        end
    })
    ESPStyleBox:AddToggle("ESP_LookTracer_Toggle", {
        Text    = "Look tracer",
        Default = false,
        Callback = function(v)
            ESPSettings.LookTracer = v
        end
    })
    ESPStyleBox:AddSlider("ESP_TextSize_Slider", {
        Text     = "Text size",
        Default  = ESPSettings.TextSize,
        Min      = 10,
        Max      = 30,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.TextSize = val
        end
    })
    ESPStyleBox:AddSlider("ESP_LineThickness_Slider", {
        Text     = "Line thickness",
        Default  = ESPSettings.LineThickness,
        Min      = 1,
        Max      = 5,
        Rounding = 0,
        Callback = function(val)
            ESPSettings.LineThickness = val
        end
    })

    ----------------------------------------------------------------
    -- Tab: Combat & Aimbot
    ----------------------------------------------------------------
    local CombatLeft  = Tabs.Combat:AddLeftGroupbox("Core Aimbot")
    local CombatRight = Tabs.Combat:AddRightGroupbox("Target / Extra")

    CombatLeft:AddToggle("Aim_Enabled", {
        Text    = "Enable Aimbot",
        Default = true,
        Callback = function(v)
            AimSettings.Enabled = v
        end
    })

    CombatLeft:AddDropdown("Aim_Mode", {
        Text    = "Mode",
        Default = "Legit",
        Values  = { "Legit", "Rage" },
        Callback = function(v)
            AimSettings.Mode = v
            if v == "Legit" then
                AimSettings.FOVRadius   = 120
                AimSettings.Smoothing   = 0.25
                AimSettings.HitChance   = 90
                AimSettings.VisibleOnly = true
            else
                AimSettings.FOVRadius   = 300
                AimSettings.Smoothing   = 0.5
                AimSettings.HitChance   = 100
                AimSettings.VisibleOnly = false
            end
        end
    })

    CombatLeft:AddDropdown("Aim_Type", {
        Text    = "Aim type",
        Default = "Hold",
        Values  = { "Hold", "Toggle" },
        Callback = function(v)
            AimSettings.AimType = v
        end
    })

    CombatLeft:AddSlider("Aim_FOV", {
        Text     = "FOV radius",
        Default  = 120,
        Min      = 0,
        Max      = 360,
        Rounding = 0,
        Callback = function(val)
            AimSettings.FOVRadius = val
        end
    })

    CombatLeft:AddToggle("Aim_ShowFOV", {
        Text    = "Show FOV circle",
        Default = true,
        Callback = function(v)
            AimSettings.ShowFOV = v
        end
    })

    CombatLeft:AddSlider("Aim_Smooth", {
        Text     = "Smooth (1–20)",
        Default  = 5,
        Min      = 1,
        Max      = 20,
        Rounding = 0,
        Callback = function(val)
            -- map 1–20 -> 0.05–1
            local t = math.clamp(val, 1, 20)
            local alpha = 0.05 + (t - 1) * (0.95 / 19)
            AimSettings.Smoothing = alpha
        end
    })

    CombatLeft:AddSlider("Aim_HitChance", {
        Text     = "Hit chance (%)",
        Default  = 100,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            -- Limit access to HitChance slider for Premium tier and above
            if not RoleAtLeast("premium") then
                Notify("Hit chance customization requires Premium or higher", 3)
                -- Revert to default value (100)
                local opt = Library.Options.Aim_HitChance
                if opt and opt.SetValue then
                    opt:SetValue(100)
                end
                return
            end
            AimSettings.HitChance = val
        end
    })

    CombatLeft:AddToggle("Aim_TeamCheck", {
        Text    = "Team check",
        Default = true,
        Callback = function(v)
            AimSettings.TeamCheck = v
        end
    })

    CombatLeft:AddToggle("Aim_IgnoreFriends", {
        Text    = "Ignore friends",
        Default = true,
        Callback = function(v)
            AimSettings.IgnoreFriends = v
        end
    })

    CombatLeft:AddToggle("Aim_VisibleOnly", {
        Text    = "Visible only (Aimbot)",
        Default = true,
        Callback = function(v)
            AimSettings.VisibleOnly = v
        end
    })

    CombatLeft:AddSlider("Aim_MaxDistance", {
        Text     = "Max distance",
        Default  = 1000,
        Min      = 0,
        Max      = 5000,
        Rounding = 0,
        Callback = function(val)
            AimSettings.MaxDistance = val
        end
    })

    CombatLeft:AddLabel("Activation: Right mouse button", true)

    CombatRight:AddDropdown("Aim_Part", {
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
            if v == "RandomWeighted" and not RoleAtLeast("premium") then
                Notify("RandomWeighted target selection requires Premium or higher", 3)
                -- Revert to a valid option (Head)
                local opt = Library.Options.Aim_Part
                if opt and opt.SetValue then
                    opt:SetValue("Head")
                end
                return
            end
            AimSettings.AimPart = v
        end
    })

    CombatRight:AddLabel("<b>RandomWeighted: part weights</b>", true)
    CombatRight:AddSlider("Aim_WHead", {
        Text     = "Head weight",
        Default  = 60,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            if not RoleAtLeast("premium") then
                Notify("Editing aim weights requires Premium or higher", 3)
                -- Revert to default 60
                local opt = Library.Options.Aim_WHead
                if opt and opt.SetValue then
                    opt:SetValue(60)
                end
                return
            end
            AimSettings.Weights.Head = val
        end
    })
    CombatRight:AddSlider("Aim_WChest", {
        Text     = "Chest weight",
        Default  = 25,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            if not RoleAtLeast("premium") then
                Notify("Editing aim weights requires Premium or higher", 3)
                -- Revert to default 25
                local opt = Library.Options.Aim_WChest
                if opt and opt.SetValue then
                    opt:SetValue(25)
                end
                return
            end
            AimSettings.Weights.Chest = val
        end
    })
    CombatRight:AddSlider("Aim_WArms", {
        Text     = "Arms weight",
        Default  = 10,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            if not RoleAtLeast("premium") then
                Notify("Editing aim weights requires Premium or higher", 3)
                -- Revert to default 10
                local opt = Library.Options.Aim_WArms
                if opt and opt.SetValue then
                    opt:SetValue(10)
                end
                return
            end
            AimSettings.Weights.Arms = val
        end
    })
    CombatRight:AddSlider("Aim_WLegs", {
        Text     = "Legs weight",
        Default  = 5,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(val)
            if not RoleAtLeast("premium") then
                Notify("Editing aim weights requires Premium or higher", 3)
                -- Revert to default 5
                local opt = Library.Options.Aim_WLegs
                if opt and opt.SetValue then
                    opt:SetValue(5)
                end
                return
            end
            AimSettings.Weights.Legs = val
        end
    })

    CombatRight:AddDivider()
    CombatRight:AddLabel("<b>Extra (Skeleton / Silent / Trigger)</b>", true)
    CombatRight:AddLabel("SilentAim / Triggerbot / Recoil ต้องต่อกับ module per-game", true)

    ----------------------------------------------------------------
    -- Tab: Misc & System
    ----------------------------------------------------------------
    local MiscLeft  = Tabs.Misc:AddLeftGroupbox("Anti-AFK / Safety")
    local MiscRight = Tabs.Misc:AddRightGroupbox("System / Devtools")

    MiscLeft:AddToggle("Misc_AntiAFK", {
        Text    = "Enable Anti-AFK",
        Default = false,
        Callback = function(v)
            setAntiAFK(v)
        end
    })

    MiscLeft:AddSlider("Misc_AntiAFK_Interval", {
        Text     = "AFK interval (sec)",
        Default  = 60,
        Min      = 30,
        Max      = 600,
        Rounding = 0,
        Callback = function(val)
            AntiAFKInterval = val
        end
    })

    MiscLeft:AddButton("Panic (Unload Hub)", function()
        CleanupConnections()
        -- Destroy all drawing objects and highlights completely
        removeAllDraw()
        pcall(function()
            HighlightFolder:Destroy()
        end)
        if FullbrightEnabled then
            restoreLighting()
        end
        Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    MiscRight:AddLabel("<b>Server tools (duplicate)</b>", true)
    MiscRight:AddLabel("Server hop / Rejoin มีใน Player Tab แล้ว", true)

    MiscRight:AddDivider()
    MiscRight:AddLabel("<b>Dev tools (stub)</b>", true)
    MiscRight:AddLabel("สามารถเพิ่ม Logger / Console / ESP debug ภายหลัง", true)

    ----------------------------------------------------------------
    -- Tab: Game (Game Client / Modules)
    ----------------------------------------------------------------
    local GameLeftBox  = Tabs.Game:AddLeftGroupbox("Game Info")
    local GameRightBox = Tabs.Game:AddRightGroupbox("Game Modules")

    addRichLabel(GameLeftBox, "<b>Game:</b> " .. gameName)
    addRichLabel(GameLeftBox, string.format("<b>PlaceId:</b> %d", placeId))
    addRichLabel(GameLeftBox, "<b>JobId:</b> " .. jobId)

    GameRightBox:AddLabel("<b>Game module</b>", true)
    GameRightBox:AddLabel("No per-game module configured yet.", true)

    ----------------------------------------------------------------
    -- Tab: Settings (Theme / Config / Keybind)
    ----------------------------------------------------------------
    local UIThemeBox  = Tabs.Settings:AddLeftGroupbox("UI / Theme")
    local UIConfigBox = Tabs.Settings:AddRightGroupbox("Config / Misc")

    UIThemeBox:AddLabel("<b>Theme</b>", true)
    UIThemeBox:AddDivider()

    if ThemeManager then
        if ThemeManager.ApplyToTab then
            ThemeManager:ApplyToTab(Tabs.Settings)
        end
        if ThemeManager.BuildThemeSection then
            ThemeManager:BuildThemeSection(UIThemeBox)
        end
    end

    UIConfigBox:AddLabel("<b>Config</b>", true)
    UIConfigBox:AddDivider()

    if SaveManager and SaveManager.BuildConfigSection then
        -- ต้องส่ง Tab เข้าไป ไม่ใช่ Groupbox
        SaveManager:BuildConfigSection(Tabs.Settings)
    else
        UIConfigBox:AddLabel("SaveManager not fully available.", true)
    end

    UIConfigBox:AddDivider()
    UIConfigBox:AddButton("Unload Hub", function()
        CleanupConnections()
        -- Destroy all drawing objects and highlights completely
        removeAllDraw()
        pcall(function()
            HighlightFolder:Destroy()
        end)
        if FullbrightEnabled then
            restoreLighting()
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
