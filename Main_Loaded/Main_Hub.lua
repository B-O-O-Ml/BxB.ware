-- Fixed / Added

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- ชั้นที่สอง: ตรวจ keycheck + keydata
    ----------------------------------------------------------------
    local EXPECTED_KEYCHECK = "BxB.ware-universal-private-*&^%$#$*#%&@#" -- ต้องตรงกับ Config.KEYCHECK_TOKEN ใน Key_Loaded.lua
    if keycheck ~= EXPECTED_KEYCHECK then return end
    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then return end

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
    if not LocalPlayer then return end

    local VirtualUser
    do
        local ok, vu = pcall(function()
            return game:GetService("VirtualUser")
        end)
        if ok then VirtualUser = vu end
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
                pcall(function() conn:Disconnect() end)
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
    -- Role / Status
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

    local isPremium = RoleAtLeast("premium")
    local isStaff   = RoleAtLeast("staff")

    ----------------------------------------------------------------
    -- Helpers: character / time / perf
    ----------------------------------------------------------------
    local function GetCharacter()
        return LocalPlayer.Character
    end
    local function GetHumanoid()
        local c = GetCharacter()
        return c and c:FindFirstChildOfClass("Humanoid")
    end
    local function GetRoot()
        local c = GetCharacter()
        return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso"))
    end

    local function unixNow()
        local ok, dt = pcall(DateTime.now)
        if ok and dt then return dt.UnixTimestamp end
        return os.time()
    end
    local function formatUnix(ts)
        ts = tonumber(ts); if not ts then return "N/A" end
        local ok, dt = pcall(DateTime.fromUnixTimestamp, ts)
        if not ok then return "N/A" end
        local ut = dt:ToUniversalTime()
        local function pad(n) return (n < 10 and ("0"..n)) or tostring(n) end
        return string.format(
            "%s/%s/%s - %s:%s:%s",
            pad(ut.Day), pad(ut.Month), string.sub(tostring(ut.Year), 3, 4),
            pad(ut.Hour), pad(ut.Minute), pad(ut.Second)
        )
    end
    local function formatTimeLeft(expireTs)
        expireTs = tonumber(expireTs)
        if not expireTs then return "Lifetime" end
        local diff = expireTs - unixNow()
        if diff <= 0 then return "Expired" end
        local d = math.floor(diff / 86400)
        local h = math.floor((diff % 86400) / 3600)
        local m = math.floor((diff % 3600) / 60)
        local s = diff % 60
        local t = {}
        if d > 0 then table.insert(t, d .. "d") end
        if h > 0 then table.insert(t, h .. "h") end
        if m > 0 then table.insert(t, m .. "m") end
        if s > 0 and #t == 0 then table.insert(t, s .. "s") end
        return table.concat(t, " ")
    end
    local function shortKey(k)
        k = tostring(k or "")
        if #k <= 8 then return k end
        return string.sub(k, 1, 4) .. "..." .. string.sub(k, -4)
    end

    local FPS, lastTime, frameCount = 0, tick(), 0
    AddConnection(RunService.RenderStepped:Connect(function()
        frameCount += 1
        local now = tick()
        if now - lastTime >= 1 then
            FPS = frameCount / (now - lastTime)
            frameCount = 0
            lastTime = now
        end
    end))
    local function getPing()
        local netStats = Stats:FindFirstChild("Network"); if not netStats then return 0 end
        local ssi = netStats:FindFirstChild("ServerStatsItem"); if not ssi then return 0 end
        local data = ssi:FindFirstChild("Data Ping"); if not data then return 0 end
        local ok, v = pcall(function() return data:GetValue() end)
        if ok and type(v) == "number" then return math.floor(v * 1000) end
        return 0
    end
    local function getMemoryMB()
        local ps = Stats:FindFirstChild("PerformanceStats"); if not ps then return 0 end
        local mem = ps:FindFirstChild("MemoryUsageMb"); if not mem then return 0 end
        local ok, v = pcall(function() return mem:GetValue() end)
        if ok and type(v) == "number" then return math.floor(v) end
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
    }

    local AimSettings = {
        Enabled      = true,
        Mode         = "Camera",   -- Camera
        AimPart      = "Head",    -- Head / Torso
        FOVRadius    = 120,
        ShowFOV      = true,
        Smoothing    = 0.25,
        VisibleOnly  = true,
        TeamCheck    = true,
        IgnoreFriends= true,
        Key          = Enum.UserInputType.MouseButton2,
    }

    local WhitelistNames = {}  -- [name]=true

    ----------------------------------------------------------------
    -- Target Manager (ใช้ร่วม ESP & Aimbot)
    ----------------------------------------------------------------
    local WorldRoot = workspace:FindFirstChildOfClass("WorldRoot") or workspace
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Blacklist
    RayParams.FilterDescendantsInstances = {LocalPlayer.Character}

    local PlayerInfo = {} -- [Player] = {fields}

    local function isFriend(plr)
        local ok, res = pcall(LocalPlayer.IsFriendsWith, LocalPlayer, plr.UserId)
        return ok and res == true
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

    local function updateTargets()
        local cam = workspace.CurrentCamera
        if not cam then return end

        updatePlayerList()

        local meTeam = LocalPlayer.Team
        local origin = cam.CFrame.Position

        local infos = {}
        for plr, info in pairs(PlayerInfo) do
            local char = plr.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
            local head = char and char:FindFirstChild("Head")

            if not (char and hum and root and hum.Health > 0) then
                info.VisibleOnScreen = false
                info.Valid = false
            else
                local dist = (root.Position - origin).Magnitude
                local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
                local friend = isFriend(plr)
                local whitelisted = WhitelistNames[plr.Name] == true

                local canTeam = true
                if ESPSettings.TeamCheck and meTeam and plr.Team == meTeam then
                    canTeam = false
                end
                if AimSettings.TeamCheck and meTeam and plr.Team == meTeam then
                    -- ใช้ flag เดียว
                end

                -- raycast visibility
                local visible = true
                if ESPSettings.WallCheck or AimSettings.VisibleOnly then
                    local targetPos = head and head.Position or root.Position
                    local dir = targetPos - origin
                    local result = WorldRoot:Raycast(origin, dir, RayParams)
                    if result and not result.Instance:IsDescendantOf(char) then
                        visible = false
                    end
                end

                info.Character = char
                info.Humanoid  = hum
                info.Root      = root
                info.Head      = head
                info.Distance  = dist
                info.ScreenPos = Vector2.new(screenPos.X, screenPos.Y)
                info.OnScreen  = onScreen
                info.Visible   = visible
                info.IsFriend  = friend
                info.Whitelisted = whitelisted
                info.TeamOK    = canTeam
                info.Valid     = true

                table.insert(infos, info)
            end
        end

        -- sort by distance
        table.sort(infos, function(a, b)
            return (a.Distance or 99999) < (b.Distance or 99999)
        end)

        -- mark ShouldRender ตาม MaxDistance / MaxPlayers / filter
        local used = 0
        for _, info in ipairs(infos) do
            info.ShouldRender = false
            if info.Valid and info.Distance <= ESPSettings.MaxDistance then
                if ESPSettings.TeamCheck and not info.TeamOK then
                    -- skip
                elseif ESPSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then
                    -- skip
                else
                    used += 1
                    if used <= ESPSettings.MaxPlayers then
                        info.ShouldRender = true
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Drawing objects (ESP + Aimbot FOV)
    ----------------------------------------------------------------
    local DrawObjects = {} -- [Player] = {Box, Corners, Tracer, Name, HealthBar, HeadDot, Offscreen}
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
        if existing then return existing end

        local t = {}

        t.Box = Drawing.new("Square")
        t.Box.Thickness = 1
        t.Box.Filled = false
        t.Box.Color = Color3.new(1, 1, 1)
        t.Box.Visible = false

        t.Tracer = Drawing.new("Line")
        t.Tracer.Thickness = 1
        t.Tracer.Color = Color3.new(1, 1, 1)
        t.Tracer.Visible = false

        t.Name = Drawing.new("Text")
        t.Name.Size = 13
        t.Name.Center = true
        t.Name.Outline = true
        t.Name.Color = Color3.new(1, 1, 1)
        t.Name.Visible = false

        t.HealthBar = Drawing.new("Line")
        t.HealthBar.Thickness = 3
        t.HealthBar.Color = Color3.new(0, 1, 0)
        t.HealthBar.Visible = false

        t.HeadDot = Drawing.new("Circle")
        t.HeadDot.Thickness = 2
        t.HeadDot.Filled = false
        t.HeadDot.Color = Color3.new(1, 1, 1)
        t.HeadDot.Visible = false

        t.Offscreen = Drawing.new("Triangle")
        t.Offscreen.Filled = true
        t.Offscreen.Color = Color3.new(1, 1, 1)
        t.Offscreen.Visible = false

        t.Corners = {}
        for i = 1, 4 do
            local c = Drawing.new("Line")
            c.Thickness = 1
            c.Color = Color3.new(1, 1, 1)
            c.Visible = false
            table.insert(t.Corners, c)
        end

        DrawObjects[plr] = t
        return t
    end

    local function hideDrawFor(plr)
        local objs = DrawObjects[plr]
        if not objs then return end
        objs.Box.Visible = false
        objs.Tracer.Visible = false
        objs.Name.Visible = false
        objs.HealthBar.Visible = false
        objs.HeadDot.Visible = false
        objs.Offscreen.Visible = false
        for _, c in ipairs(objs.Corners) do c.Visible = false end
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
        local hl = char:FindFirstChild(tag)
        if hl and hl:IsA("Highlight") then
            return hl
        end
        hl = Instance.new("Highlight")
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
        local hl = char:FindFirstChild(tag)
        if hl and hl:IsA("Highlight") then
            hl:Destroy()
        end
    end

    ----------------------------------------------------------------
    -- Aimbot core
    ----------------------------------------------------------------
    local aiming = false
    local function isAimKeyDown()
        if not AimSettings.Enabled then return false end
        local k = AimSettings.Key
        if k == Enum.UserInputType.MouseButton2 then
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end
        -- fallback สำหรับกรณีใช้ KeyCode
        return false
    end

    local function getBestTarget(cam)
        local bestInfo, bestScore = nil, math.huge
        local mousePos = UserInputService:GetMouseLocation()

        for plr, info in pairs(PlayerInfo) do
            if info.Valid and info.ShouldRender then
                if info.Distance <= ESPSettings.MaxDistance then
                    if AimSettings.TeamCheck and info.TeamOK == false then
                        -- skip
                    elseif AimSettings.IgnoreFriends and info.IsFriend and not info.Whitelisted then
                        -- skip
                    else
                        if (not AimSettings.VisibleOnly) or info.Visible then
                            -- จุดเล็ง = Head หรือ Root
                            local targetPos = info.ScreenPos
                            local dist2D = (targetPos - mousePos).Magnitude
                            if dist2D <= AimSettings.FOVRadius then
                                if dist2D < bestScore then
                                    bestScore = dist2D
                                    bestInfo = info
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestInfo
    end

    local function aimbotStep()
        if not (hasDrawing and AimSettings.Enabled and isAimKeyDown()) then
            return
        end
        local cam = workspace.CurrentCamera
        if not cam then return end

        local info = getBestTarget(cam)
        if not info or not info.Valid then
            return
        end

        local targetPart = (AimSettings.AimPart == "Head" and info.Head) or info.Root
        if not targetPart then return end

        local currentCF = cam.CFrame
        local targetCF = CFrame.new(currentCF.Position, targetPart.Position)
        local alpha = math.clamp(AimSettings.Smoothing, 0.01, 1)
        cam.CFrame = currentCF:Lerp(targetCF, alpha)
    end

    ----------------------------------------------------------------
    -- ESP render step (NO goto)
    ----------------------------------------------------------------
    local function espStep()
        local cam = workspace.CurrentCamera
        if not cam then
            hideAllDraw()
            return
        end

        local viewSize = cam.ViewportSize
        local screenCenter = viewSize / 2

        -- FOV circle (สำหรับ Aimbot)
        if hasDrawing and FOVCircle then
            if AimSettings.Enabled and AimSettings.ShowFOV then
                local mousePos = UserInputService:GetMouseLocation()
                FOVCircle.Visible = true
                FOVCircle.Radius = AimSettings.FOVRadius
                FOVCircle.Position = mousePos
            else
                FOVCircle.Visible = false
            end
        end

        for plr, info in pairs(PlayerInfo) do
            local objs = DrawObjects[plr]
            if not objs then
                objs = getDrawObjects(plr)
            end

            -- ถ้า target ใช้ไม่ได้ / ไม่ควร render → ซ่อนทุกอย่าง + ลบ highlight
            if not info.Valid or not info.ShouldRender then
                hideDrawFor(plr)
                if info.Character then
                    removeHighlight(info.Character)
                end
            else
                local colorEnemy = Color3.fromRGB(255, 85, 85)
                local colorTeam  = Color3.fromRGB(85, 170, 255)
                local col = info.TeamOK and colorEnemy or colorTeam

                local sp       = info.ScreenPos          -- Vector2
                local dist     = info.Distance or 0
                local camToRoot = (cam.CFrame.Position - info.Root.Position).Magnitude
                local onScreen = info.OnScreen == true

                ----------------------------------------------------------------
                -- 3D Highlight (Chams)
                ----------------------------------------------------------------
                if ESPSettings.UseHighlight then
                    local hl = getHighlight(info.Character)
                    if hl then
                        hl.FillColor = col
                        hl.OutlineColor = col
                    end
                else
                    removeHighlight(info.Character)
                end

                ----------------------------------------------------------------
                -- 2D ESP (Drawing)
                ----------------------------------------------------------------
                if not (ESPSettings.Enabled and hasDrawing) then
                    -- ปิด 2D overlays ทั้งหมด แต่ยังคง highlight ได้
                    hideDrawFor(plr)
                else
                    local sizeFactor = math.clamp(1200 / math.max(camToRoot, 1), 0.4, 2.5)
                    local boxSize = Vector2.new(40, 70) * sizeFactor
                    boxSize = Vector2.new(
                        math.clamp(boxSize.X, 20, 120),
                        math.clamp(boxSize.Y, 40, 180)
                    )
                    local topLeft = sp - boxSize / 2

                    ----------------------------------------------------------------
                    -- Offscreen arrow
                    ----------------------------------------------------------------
                    if ESPSettings.OffscreenArrow and not onScreen then
                        local dir = (sp - screenCenter)
                        if dir.Magnitude > 0 then
                            dir = dir.Unit
                            local edgePos = screenCenter + dir * (math.min(viewSize.X, viewSize.Y) * 0.45)
                            local perp = Vector2.new(-dir.Y, dir.X) * 8

                            local p1 = edgePos
                            local p2 = edgePos - dir * 18 + perp
                            local p3 = edgePos - dir * 18 - perp

                            objs.Offscreen.Visible = true
                            objs.Offscreen.PointA = p1
                            objs.Offscreen.PointB = p2
                            objs.Offscreen.PointC = p3
                            objs.Offscreen.Color  = col
                        else
                            objs.Offscreen.Visible = false
                        end
                    else
                        objs.Offscreen.Visible = false
                    end

                    ----------------------------------------------------------------
                    -- ถ้าอยู่นอกจอ: แสดง arrow ได้ แต่ไม่ต้อง render box/ชื่อ ฯลฯ
                    ----------------------------------------------------------------
                    if not onScreen then
                        objs.Box.Visible       = false
                        objs.Tracer.Visible    = false
                        objs.Name.Visible      = false
                        objs.HealthBar.Visible = false
                        objs.HeadDot.Visible   = false
                        for _, c in ipairs(objs.Corners) do
                            c.Visible = false
                        end
                    else
                        ----------------------------------------------------------------
                        -- Box / Corner
                        ----------------------------------------------------------------
                        objs.Box.Visible = false
                        for _, c in ipairs(objs.Corners) do
                            c.Visible = false
                        end

                        if ESPSettings.BoxMode == "Box" then
                            objs.Box.Visible   = true
                            objs.Box.Position  = topLeft
                            objs.Box.Size      = boxSize
                            objs.Box.Color     = col
                        elseif ESPSettings.BoxMode == "Corner" then
                            local w, h = boxSize.X, boxSize.Y
                            local tl = topLeft
                            local tr = topLeft + Vector2.new(w, 0)
                            local bl = topLeft + Vector2.new(0, h)
                            -- local br = topLeft + Vector2.new(w, h)
                            local len = math.max(4, math.floor(w * 0.2))

                            local lines = objs.Corners
                            lines[1].Visible = true
                            lines[1].From    = tl
                            lines[1].To      = tl + Vector2.new(len, 0)
                            lines[1].Color   = col

                            lines[2].Visible = true
                            lines[2].From    = tl
                            lines[2].To      = tl + Vector2.new(0, len)
                            lines[2].Color   = col

                            lines[3].Visible = true
                            lines[3].From    = tr
                            lines[3].To      = tr + Vector2.new(-len, 0)
                            lines[3].Color   = col

                            lines[4].Visible = true
                            lines[4].From    = tr
                            lines[4].To      = tr + Vector2.new(0, len)
                            lines[4].Color   = col
                        end

                        ----------------------------------------------------------------
                        -- Tracer
                        ----------------------------------------------------------------
                        if ESPSettings.Tracer then
                            local origin = Vector2.new(viewSize.X / 2, viewSize.Y)
                            objs.Tracer.Visible = true
                            objs.Tracer.From    = origin
                            objs.Tracer.To      = sp
                            objs.Tracer.Color   = col
                        else
                            objs.Tracer.Visible = false
                        end

                        ----------------------------------------------------------------
                        -- Name + distance
                        ----------------------------------------------------------------
                        if ESPSettings.NameTag or ESPSettings.ShowDistance then
                            local text = ""
                            if ESPSettings.NameTag then
                                text = text .. plr.Name
                            end
                            if ESPSettings.ShowDistance then
                                if text ~= "" then
                                    text = text .. " | "
                                end
                                text = text .. string.format("%dm", math.floor(dist))
                            end

                            objs.Name.Visible   = true
                            objs.Name.Text      = text
                            objs.Name.Position  = Vector2.new(sp.X, topLeft.Y - 12)
                            objs.Name.Color     = col
                        else
                            objs.Name.Visible = false
                        end

                        ----------------------------------------------------------------
                        -- Healthbar
                        ----------------------------------------------------------------
                        if ESPSettings.HealthBar and info.Humanoid then
                            local hp  = info.Humanoid.Health
                            local mhp = math.max(info.Humanoid.MaxHealth, 1)
                            local ratio = math.clamp(hp / mhp, 0, 1)

                            local barHeight = boxSize.Y * ratio
                            local x = topLeft.X - 4
                            local y1 = topLeft.Y + boxSize.Y
                            local y2 = y1 - barHeight

                            objs.HealthBar.Visible = true
                            objs.HealthBar.From    = Vector2.new(x, y1)
                            objs.HealthBar.To      = Vector2.new(x, y2)
                            objs.HealthBar.Color   = Color3.fromRGB(
                                math.floor(255 * (1 - ratio)),
                                math.floor(255 * ratio),
                                0
                            )
                        else
                            objs.HealthBar.Visible = false
                        end

                        ----------------------------------------------------------------
                        -- HeadDot
                        ----------------------------------------------------------------
                        if ESPSettings.HeadDot and info.Head then
                            local head3D = info.Head.Position
                            local head2D, onScr = cam:WorldToViewportPoint(head3D)
                            if onScr then
                                objs.HeadDot.Visible   = true
                                objs.HeadDot.Position  = Vector2.new(head2D.X, head2D.Y)
                                objs.HeadDot.Radius    = 3
                                objs.HeadDot.Color     = col
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
    -- Tab: Status
    ----------------------------------------------------------------
    local StatusKeyBox   = Tabs.Status:AddLeftGroupbox("Key / Role")
    local StatusSystemBox= Tabs.Status:AddLeftGroupbox("System Info")

    local function addRichLabel(group, text)
        local lbl = group:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

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
    local MoveBox   = Tabs.Player:AddLeftGroupbox("Movement")
    local QoLBox    = Tabs.Player:AddLeftGroupbox("Anti-AFK / Server / Safe")

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
        Text = "Custom WalkSpeed",
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
        Text = "WalkSpeed",
        Default = 16, Min = 5, Max = 100, Rounding = 0,
        Callback = function(val)
            MovementState.WalkSpeedValue = val
            if MovementState.WalkSpeedEnabled then
                local hum = GetHumanoid()
                if hum then hum.WalkSpeed = val end
            end
        end
    })

    MoveBox:AddDivider()
    MoveBox:AddToggle("Move_Jump_Toggle", {
        Text = "Custom JumpPower",
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
        Text = "JumpPower",
        Default = 50, Min = 20, Max = 150, Rounding = 0,
        Callback = function(val)
            MovementState.JumpValue = val
            if MovementState.JumpEnabled then
                local hum = GetHumanoid()
                if hum then hum.JumpPower = val end
            end
        end
    })

    MoveBox:AddDivider()
    MoveBox:AddToggle("Move_InfiniteJump_Toggle", {
        Text = "Infinite Jump",
        Default = false,
        Callback = function(v) MovementState.InfiniteJump = v end
    })
    MoveBox:AddToggle("Move_Fly_Toggle", {
        Text = "Fly (camera based)",
        Default = false,
        Callback = function(v) MovementState.Fly = v end
    })
    MoveBox:AddSlider("Move_FlySpeed_Slider", {
        Text = "Fly speed",
        Default = 50, Min = 10, Max = 200, Rounding = 0,
        Callback = function(val) MovementState.FlySpeed = val end
    })
    MoveBox:AddToggle("Move_NoClip_Toggle", {
        Text = "NoClip",
        Default = false,
        Callback = function(v) MovementState.NoClip = v end
    })

    AddConnection(UserInputService.JumpRequest:Connect(function()
        if not MovementState.InfiniteJump then return end
        local hum = GetHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))

    AddConnection(RunService.RenderStepped:Connect(function()
        local char = GetCharacter()
        local hum  = GetHumanoid()
        local root = GetRoot()
        if char and MovementState.NoClip then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end

        if MovementState.Fly and root then
            local cam = workspace.CurrentCamera
            local dir = Vector3.new()
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                dir += cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                dir -= cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                dir -= cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                dir += cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                dir += Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                dir -= Vector3.new(0, 1, 0)
            end
            if dir.Magnitude > 0 then
                dir = dir.Unit * MovementState.FlySpeed
            end
            root.Velocity = dir
            if hum then hum.PlatformStand = true end
        else
            if hum then hum.PlatformStand = false end
        end
    end))

    QoLBox:AddLabel("<b>Safety & Anti-AFK</b>", true)
    QoLBox:AddDivider()

    QoLBox:AddButton("Reset movement", function()
        MovementState.WalkSpeedEnabled = false
        MovementState.JumpEnabled      = false
        MovementState.InfiniteJump     = false
        MovementState.Fly             = false
        MovementState.NoClip          = false

        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed = DefaultWalkSpeed
            hum.JumpPower = DefaultJumpPower
            hum.PlatformStand = false
        end
        Notify("Movement reset", 3)
    end)

    local AntiAFKConn
    QoLBox:AddToggle("AntiAFK_Toggle", {
        Text = "Enable Anti-AFK",
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
        pcall(function() HighlightFolder:Destroy() end)
        hideAllDraw()
        if FOVCircle then FOVCircle.Visible = false end
        Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    ----------------------------------------------------------------
    -- Tab: ESP (UI settings)
    ----------------------------------------------------------------
    local ESPMainBox   = Tabs.ESP:AddLeftGroupbox("ESP Core")
    local ESPFilterBox = Tabs.ESP:AddLeftGroupbox("Filter / Whitelist")

    ESPMainBox:AddToggle("ESP_Enable_Toggle", {
        Text = "Enable ESP",
        Default = true,
        Callback = function(v) ESPSettings.Enabled = v end
    })
    ESPMainBox:AddDropdown("ESP_BoxMode", {
        Text = "Box mode",
        Default = "Box",
        Values = {"Box", "Corner", "Off"},
        Callback = function(v) ESPSettings.BoxMode = v end
    })
    ESPMainBox:AddToggle("ESP_UseHighlight", {
        Text = "Use 3D Chams (Highlight)",
        Default = true,
        Callback = function(v) ESPSettings.UseHighlight = v end
    })
    ESPMainBox:AddToggle("ESP_HeadDot", {
        Text = "Head dot",
        Default = true,
        Callback = function(v) ESPSettings.HeadDot = v end
    })
    ESPMainBox:AddToggle("ESP_NameTag", {
        Text = "Name & distance",
        Default = true,
        Callback = function(v) ESPSettings.NameTag = v end
    })
    ESPMainBox:AddToggle("ESP_HealthBar", {
        Text = "Health bar",
        Default = true,
        Callback = function(v) ESPSettings.HealthBar = v end
    })
    ESPMainBox:AddToggle("ESP_Tracer", {
        Text = "Tracer",
        Default = true,
        Callback = function(v) ESPSettings.Tracer = v end
    })
    ESPMainBox:AddToggle("ESP_Offscreen", {
        Text = "Offscreen arrows",
        Default = false,
        Callback = function(v) ESPSettings.OffscreenArrow = v end
    })

    ESPMainBox:AddSlider("ESP_MaxDistance", {
        Text = "Max distance",
        Default = 1000, Min = 50, Max = 3000, Rounding = 0,
        Callback = function(val) ESPSettings.MaxDistance = val end
    })
    ESPMainBox:AddSlider("ESP_MaxPlayers", {
        Text = "Max players",
        Default = 30, Min = 5, Max = 100, Rounding = 0,
        Callback = function(val) ESPSettings.MaxPlayers = val end
    })
    ESPMainBox:AddSlider("ESP_UpdateInterval", {
        Text = "Update interval (ms)",
        Default = 80, Min = 20, Max = 250, Rounding = 0,
        Callback = function(val) ESPSettings.UpdateInterval = val / 1000 end
    })

    ESPFilterBox:AddToggle("ESP_TeamCheck", {
        Text = "Team check",
        Default = true,
        Callback = function(v) ESPSettings.TeamCheck = v end
    })
    ESPFilterBox:AddToggle("ESP_IgnoreFriends", {
        Text = "Ignore friends",
        Default = true,
        Callback = function(v) ESPSettings.IgnoreFriends = v end
    })
    ESPFilterBox:AddToggle("ESP_VisibleOnly", {
        Text = "Visible only (Raycast)",
        Default = false,
        Callback = function(v) ESPSettings.VisibleOnly = v end
    })
    ESPFilterBox:AddToggle("ESP_WallCheck", {
        Text = "Wall check",
        Default = true,
        Callback = function(v) ESPSettings.WallCheck = v end
    })

    ESPFilterBox:AddDivider()
    ESPFilterBox:AddLabel("<b>Manual whitelist (by name)</b>", true)

    local WhitelistLabel = addRichLabel(ESPFilterBox, "Whitelist: (none)")
    local function refreshWhitelistLabel()
        local names = {}
        for name, ok in pairs(WhitelistNames) do
            if ok then table.insert(names, name) end
        end
        table.sort(names)
        local text = (#names == 0) and "Whitelist: (none)" or ("Whitelist: " .. table.concat(names, ", "))
        if WhitelistLabel and WhitelistLabel.TextLabel then
            WhitelistLabel.TextLabel.Text = text
            WhitelistLabel.TextLabel.RichText = false
        end
    end

    ESPFilterBox:AddInput("ESP_Whitelist_Input", {
        Text = "Player name",
        Default = "",
        Placeholder = "Exact player name",
        Callback = function() end
    })
    ESPFilterBox:AddButton("Add to whitelist", function()
        local opt = Library.Options.ESP_Whitelist_Input
        local name = opt and tostring(opt.Value or "") or ""
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            Notify("Please enter player name", 3)
            return
        end
        WhitelistNames[name] = true
        refreshWhitelistLabel()
    end)
    ESPFilterBox:AddButton("Clear whitelist", function()
        table.clear(WhitelistNames)
        refreshWhitelistLabel()
    end)

    ----------------------------------------------------------------
    -- Tab: Aim
    ----------------------------------------------------------------
    local AimBox = Tabs.Aim:AddLeftGroupbox("Aimbot")

    AimBox:AddToggle("Aim_Enabled", {
        Text = "Enable Aimbot",
        Default = true,
        Callback = function(v) AimSettings.Enabled = v end
    })
    AimBox:AddDropdown("Aim_Mode", {
        Text = "Mode",
        Default = "Camera",
        Values = {"Camera"},
        Callback = function(v) AimSettings.Mode = v end
    })
    AimBox:AddDropdown("Aim_Part", {
        Text = "Aim part",
        Default = "Head",
        Values = {"Head", "Torso"},
        Callback = function(v) AimSettings.AimPart = v end
    })
    AimBox:AddSlider("Aim_FOV", {
        Text = "FOV radius",
        Default = 120, Min = 30, Max = 300, Rounding = 0,
        Callback = function(val) AimSettings.FOVRadius = val end
    })
    AimBox:AddToggle("Aim_ShowFOV", {
        Text = "Show FOV circle",
        Default = true,
        Callback = function(v) AimSettings.ShowFOV = v end
    })
    AimBox:AddSlider("Aim_Smooth", {
        Text = "Smooth",
        Default = 0.25, Min = 0.05, Max = 1, Rounding = 2,
        Callback = function(val) AimSettings.Smoothing = val end
    })
    AimBox:AddToggle("Aim_TeamCheck", {
        Text = "Team check",
        Default = true,
        Callback = function(v) AimSettings.TeamCheck = v end
    })
    AimBox:AddToggle("Aim_IgnoreFriends", {
        Text = "Ignore friends",
        Default = true,
        Callback = function(v) AimSettings.IgnoreFriends = v end
    })
    AimBox:AddToggle("Aim_VisibleOnly", {
        Text = "Visible only",
        Default = true,
        Callback = function(v) AimSettings.VisibleOnly = v end
    })
    AimBox:AddLabel("Activation: Right mouse button (RMB)", true)

    ----------------------------------------------------------------
    -- Tab: Game (stub – ไว้ต่อยอด module ภายหลัง)
    ----------------------------------------------------------------
    local GameBox = Tabs.Game:AddLeftGroupbox("Game Module")
    addRichLabel(GameBox, "<b>No per-game module configured yet.</b>")
    addRichLabel(GameBox, "You can add GameModules system later.")

    ----------------------------------------------------------------
    -- Tab: UI / Theme / Config
    ----------------------------------------------------------------
    local UIThemeBox  = Tabs.UI:AddLeftGroupbox("UI / Theme")
    local UIConfigBox = Tabs.UI:AddLeftGroupbox("Config / Misc")

    UIThemeBox:AddLabel("<b>Theme</b>", true)
    UIThemeBox:AddDivider()
    if ThemeManager then
        if ThemeManager.ApplyToTab then ThemeManager:ApplyToTab(Tabs.UI) end
        if ThemeManager.BuildThemeSection then ThemeManager:BuildThemeSection(UIThemeBox) end
    end

    UIConfigBox:AddLabel("<b>Config</b>", true)
    UIConfigBox:AddDivider()
    if SaveManager and SaveManager.BuildConfigSection then
        SaveManager:BuildConfigSection(UIConfigBox)
    else
        UIConfigBox:AddLabel("SaveManager not fully available.", true)
    end

    UIConfigBox:AddDivider()
    UIConfigBox:AddButton("Unload Hub", function()
        CleanupConnections()
        pcall(function() HighlightFolder:Destroy() end)
        hideAllDraw()
        if FOVCircle then FOVCircle.Visible = false end
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
        accum += dt
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
