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
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Stats = game:GetService("Stats")
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local MarketplaceService = game:GetService("MarketplaceService")
    local VirtualUser
    local successVU, vu = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if successVU then
        VirtualUser = vu
    end

    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then
        return
    end

    ----------------------------------------------------------------
    -- โหลด Obsidian Library + ThemeManager + SaveManager
    -- (ตามรูปแบบที่คุณกำหนด)
    ----------------------------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

    ----------------------------------------------------------------
    -- Theme / Save setup
    ----------------------------------------------------------------
    if ThemeManager and type(ThemeManager.SetLibrary) == "function" then
        ThemeManager:SetLibrary(Library)
    end

    if SaveManager and type(SaveManager.SetLibrary) == "function" then
        SaveManager:SetLibrary(Library)
    end

    if SaveManager and type(SaveManager.IgnoreThemeSettings) == "function" then
        SaveManager:IgnoreThemeSettings()
    end

    if SaveManager and type(SaveManager.SetFolder) == "function" then
        SaveManager:SetFolder("ObsidianUniversalHub")
    end

    ----------------------------------------------------------------
    -- Helper: notify + connections + cleanup
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
        if Library and type(Library.Notify) == "function" then
            Library:Notify(tostring(msg), dur or 3)
        else
            warn("[Obsidian] " .. tostring(msg))
        end
    end

    ----------------------------------------------------------------
    -- Role / Status system
    ----------------------------------------------------------------
    local role = tostring(keydata.role or "user")
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
    local isOwner   = RoleAtLeast("owner")

    ----------------------------------------------------------------
    -- Game module mapping (แก้ PlaceId/URL ตามโปรเจกต์จริงของคุณ)
    ----------------------------------------------------------------
    local GameModules = {
        -- [PLACE_ID] = { Name = "Demo Game", Url = "https://raw.githubusercontent.com/you/repo/main/modules/GameDemo.lua", MinRole = "user" }
        -- ตัวอย่าง:
        -- [1234567890] = { Name = "Demo Game A", Url = "https://raw.githubusercontent.com/you/repo/main/modules/GameA.lua", MinRole = "premium" },
    }

    ----------------------------------------------------------------
    -- Helper: character / humanoid / root
    ----------------------------------------------------------------
    local function GetCharacter()
        return LocalPlayer.Character
    end

    local function GetHumanoid()
        local char = GetCharacter()
        if not char then return nil end
        return char:FindFirstChildOfClass("Humanoid")
    end

    local function GetRootPart()
        local char = GetCharacter()
        if not char then return nil end
        return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
    end

    AddConnection(LocalPlayer.CharacterAdded:Connect(function()
        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed = 16
            hum.JumpPower = 50
        end
    end))

    ----------------------------------------------------------------
    -- Helper: time / key formatting
    ----------------------------------------------------------------
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
        local y, m, d = ut.Year, ut.Month, ut.Day
        local hour, min, sec = ut.Hour, ut.Minute, ut.Second

        local function pad(n)
            if n < 10 then
                return "0" .. tostring(n)
            end
            return tostring(n)
        end

        return string.format("%s/%s/%s - %s:%s:%s",
            pad(d), pad(m), string.sub(tostring(y), 3, 4),
            pad(hour), pad(min), pad(sec)
        )
    end

    local function formatTimeLeft(expireTs)
        expireTs = tonumber(expireTs)
        if not expireTs then
            return "Lifetime"
        end

        local now = unixNow()
        local diff = expireTs - now

        if diff <= 0 then
            return "Expired"
        end

        local days = math.floor(diff / 86400)
        local hours = math.floor((diff % 86400) / 3600)
        local mins = math.floor((diff % 3600) / 60)
        local secs = diff % 60

        local parts = {}

        if days > 0 then
            table.insert(parts, tostring(days) .. "d")
        end
        if hours > 0 then
            table.insert(parts, tostring(hours) .. "h")
        end
        if mins > 0 then
            table.insert(parts, tostring(mins) .. "m")
        end
        if secs > 0 and #parts == 0 then
            table.insert(parts, tostring(secs) .. "s")
        end

        return table.concat(parts, " ")
    end

    local function shortKey(k)
        k = tostring(k or "")
        if #k <= 8 then
            return k
        end
        return string.sub(k, 1, 4) .. "..." .. string.sub(k, -4)
    end

    ----------------------------------------------------------------
    -- Helper: FPS / Ping / Memory
    ----------------------------------------------------------------
    local FPS = 0
    local lastTime = tick()
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

        local serverStatsItem = netStats:FindFirstChild("ServerStatsItem")
        if not serverStatsItem then
            return 0
        end

        local data = serverStatsItem:FindFirstChild("Data Ping")
        if not data then
            return 0
        end

        local ok, value = pcall(function()
            return data:GetValue()
        end)

        if ok and type(value) == "number" then
            return math.floor(value * 1000)
        end

        return 0
    end

    local function getMemoryMB()
        local perfStats = Stats:FindFirstChild("PerformanceStats")
        if not perfStats then
            return 0
        end

        local mem = perfStats:FindFirstChild("MemoryUsageMb")
        if not mem then
            return 0
        end

        local ok, value = pcall(function()
            return mem:GetValue()
        end)

        if ok and type(value) == "number" then
            return math.floor(value)
        end

        return 0
    end

    ----------------------------------------------------------------
    -- Drawing check (สำหรับ ESP 2D)
    ----------------------------------------------------------------
    local hasDrawing = false
    do
        local ok, result = pcall(function()
            return Drawing and typeof(Drawing.new) == "function"
        end)
        hasDrawing = ok and result == true
    end

    ----------------------------------------------------------------
    -- Dev log (สำหรับ Dev tab / staff+)
    ----------------------------------------------------------------
    local DevLog = {}

    local function pushLog(msg)
        local ts = unixNow()
        local text = string.format("[%d] %s", ts, tostring(msg))
        table.insert(DevLog, text)
        if #DevLog > 20 then
            table.remove(DevLog, 1)
        end
    end

    pushLog("MainHub started; role=" .. tostring(role) .. ", status=" .. tostring(keyStatus))

    ----------------------------------------------------------------
    -- สร้าง Window + Tabs (ตั้ง Resizable = false แก้บั๊ก resize)
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
        Game   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "joystick", Description = "Game Module"}),
        UI     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "settings", Description = "UI/UX Setings"}),
    }

    if isStaff then
        Tabs.Dev = Window:AddTab("Dev")
    end

    local Options = Library.Options

    ----------------------------------------------------------------
    -- Tab: Status (Key + System + Role badge)
    ----------------------------------------------------------------
    local StatusLeft  = Tabs.Status:AddLeftGroupbox("Key / Role")
    local StatusRight = Tabs.Status:AddRightGroupbox("System Info")

    StatusLeft:AddLabel("<b>Key Information</b>", true)
    StatusLeft:AddDivider()

    local keyRole      = GetRoleLabel(keydata.role)
    local keyStatusStr = tostring(keydata.status or "active")
    local keyNote      = tostring(keydata.note or "")
    local keyStamp     = tonumber(keydata.timestamp)
    local keyExpire    = tonumber(keydata.expire)

    local keyCreatedAt = keyStamp and formatUnix(keyStamp) or "N/A"
    local keyExpireAt  = keyExpire and formatUnix(keyExpire) or "Lifetime"

    local roleColorHex = GetRoleColorHex(role)

    local function addStatusLabel(group, text)
        local lbl = group:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

    addStatusLabel(StatusLeft, string.format("<b>Key</b>: %s", shortKey(keydata.key)))
    addStatusLabel(StatusLeft, string.format("<b>Role</b>: <font color=\"%s\">%s</font>", roleColorHex, keyRole))
    addStatusLabel(StatusLeft, string.format("<b>Status</b>: %s", keyStatusStr))
    addStatusLabel(StatusLeft, string.format("<b>Tier</b>: %s", GetTierLabel()))
    addStatusLabel(StatusLeft, string.format("<b>Note</b>: %s", (keyNote ~= "" and keyNote or "N/A")))
    addStatusLabel(StatusLeft, string.format("<b>Created at</b>: %s", keyCreatedAt))
    local ExpireLabel = addStatusLabel(StatusLeft, string.format("<b>Expire at</b>: %s", keyExpireAt))
    local TimeLeftLabel = addStatusLabel(StatusLeft, string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire)))

    StatusLeft:AddDivider()
    StatusLeft:AddLabel('<font color="#ffcc66">Key is bound to your HWID. Sharing key may result in ban.</font>', true)

    AddConnection(RunService.Heartbeat:Connect(function()
        if TimeLeftLabel and TimeLeftLabel.TextLabel then
            TimeLeftLabel.TextLabel.RichText = true
            TimeLeftLabel.TextLabel.Text = string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire))
        end
    end))

    StatusRight:AddLabel("<b>System / Game / Player</b>", true)
    StatusRight:AddDivider()

    local function addSysLabel(text)
        local lbl = StatusRight:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

    local placeId = game.PlaceId
    local jobId = game.JobId

    local gameName = "Unknown game"
    do
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, placeId)
        if ok and type(info) == "table" and type(info.Name) == "string" then
            gameName = info.Name
        end
    end

    local sysLabels = {
        Game   = addSysLabel(string.format("<b>Game</b>: %s (PlaceId: %d)", gameName, placeId)),
        Server = addSysLabel(string.format("<b>JobId</b>: %s", jobId)),
        Player = addSysLabel(string.format("<b>Player</b>: %s (%d)", LocalPlayer.Name, LocalPlayer.UserId)),
        FPS    = addSysLabel("<b>FPS</b>: ..."),
        Ping   = addSysLabel("<b>Ping</b>: ..."),
        Memory = addSysLabel("<b>Memory</b>: ... MB"),
    }

    AddConnection(RunService.Heartbeat:Connect(function()
        if sysLabels.FPS and sysLabels.FPS.TextLabel then
            sysLabels.FPS.TextLabel.RichText = true
            sysLabels.FPS.TextLabel.Text = string.format("<b>FPS</b>: %d", math.floor(FPS))
        end

        if sysLabels.Ping and sysLabels.Ping.TextLabel then
            sysLabels.Ping.TextLabel.RichText = true
            sysLabels.Ping.TextLabel.Text = string.format("<b>Ping</b>: %d ms", getPing())
        end

        if sysLabels.Memory and sysLabels.Memory.TextLabel then
            sysLabels.Memory.TextLabel.RichText = true
            sysLabels.Memory.TextLabel.Text = string.format("<b>Memory</b>: %d MB", getMemoryMB())
        end
    end))

    StatusRight:AddDivider()
    StatusRight:AddLabel("<b>Credits</b>", true)
    StatusRight:AddLabel("Owner: YOUR_NAME_HERE", true)
    StatusRight:AddLabel("UI: Obsidian UI Library", true)
    StatusRight:AddLabel("Discord: yourdiscord", true)

    ----------------------------------------------------------------
    -- Tab: Player (Movement + Safety + Anti-AFK + Server tools)
    ----------------------------------------------------------------
    local MoveLeft  = Tabs.Player:AddLeftGroupbox("Movement")
    local MoveRight = Tabs.Player:AddRightGroupbox("Safety / Server")

    local MovementState = {
        WalkSpeedEnabled = false,
        WalkSpeedValue   = 16,
        JumpEnabled      = false,
        JumpValue        = 50,
        InfiniteJump     = false,
        Fly              = false,
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

    MoveLeft:AddToggle("Move_WalkSpeed_Toggle", {
        Text = "Custom WalkSpeed",
        Default = false,
        Callback = function(value)
            MovementState.WalkSpeedEnabled = value
            local hum = GetHumanoid()
            if hum then
                hum.WalkSpeed = value and MovementState.WalkSpeedValue or DefaultWalkSpeed
            end
        end
    })

    MoveLeft:AddSlider("Move_WalkSpeed_Slider", {
        Text = "WalkSpeed",
        Default = 16,
        Min = 5,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            MovementState.WalkSpeedValue = value
            if MovementState.WalkSpeedEnabled then
                local hum = GetHumanoid()
                if hum then
                    hum.WalkSpeed = value
                end
            end
        end
    })

    MoveLeft:AddDivider()

    MoveLeft:AddToggle("Move_Jump_Toggle", {
        Text = "Custom JumpPower",
        Default = false,
        Callback = function(value)
            MovementState.JumpEnabled = value
            local hum = GetHumanoid()
            if hum then
                hum.JumpPower = value and MovementState.JumpValue or DefaultJumpPower
            end
        end
    })

    MoveLeft:AddSlider("Move_Jump_Slider", {
        Text = "JumpPower",
        Default = 50,
        Min = 20,
        Max = 150,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            MovementState.JumpValue = value
            if MovementState.JumpEnabled then
                local hum = GetHumanoid()
                if hum then
                    hum.JumpPower = value
                end
            end
        end
    })

    MoveLeft:AddDivider()

    MoveLeft:AddToggle("Move_InfiniteJump_Toggle", {
        Text = "Infinite Jump",
        Default = false,
        Callback = function(value)
            MovementState.InfiniteJump = value
        end
    })

    MoveLeft:AddToggle("Move_Fly_Toggle", {
        Text = "Fly (simple)",
        Default = false,
        Callback = function(value)
            MovementState.Fly = value
        end
    })

    MoveLeft:AddToggle("Move_NoClip_Toggle", {
        Text = "NoClip",
        Default = false,
        Callback = function(value)
            MovementState.NoClip = value
        end
    })

    -- Infinite Jump
    AddConnection(UserInputService.JumpRequest:Connect(function()
        if not MovementState.InfiniteJump then
            return
        end

        local hum = GetHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))

    -- Fly + NoClip loop
    AddConnection(RunService.RenderStepped:Connect(function()
        local char = GetCharacter()
        if not char then
            return
        end

        local hum = GetHumanoid()
        local root = GetRootPart()

        if MovementState.Fly and root then
            local cam = workspace.CurrentCamera
            local moveVector = Vector3.new()

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveVector = moveVector + cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveVector = moveVector - cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveVector = moveVector - cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveVector = moveVector + cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveVector = moveVector + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                moveVector = moveVector - Vector3.new(0, 1, 0)
            end

            if moveVector.Magnitude > 0 then
                moveVector = moveVector.Unit * 50
            end

            root.Velocity = moveVector
            if hum then
                hum.PlatformStand = true
            end
        else
            if hum then
                hum.PlatformStand = false
            end
        end

        if MovementState.NoClip and char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end))

    MoveRight:AddLabel("<b>Safety</b>", true)
    MoveRight:AddDivider()

    MoveRight:AddButton("Reset movement to default", function()
        MovementState.WalkSpeedEnabled = false
        MovementState.JumpEnabled = false
        MovementState.InfiniteJump = false
        MovementState.Fly = false
        MovementState.NoClip = false

        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed = DefaultWalkSpeed
            hum.JumpPower = DefaultJumpPower
            hum.PlatformStand = false
        end

        Notify("Movement reset to default", 3)
    end)

    MoveRight:AddButton("Panic (Unload Hub)", function()
        CleanupConnections()
        Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    MoveRight:AddDivider()
    MoveRight:AddLabel("<b>Anti-AFK</b>", true)

    local AntiAFKConnection

    MoveRight:AddToggle("AntiAFK_Toggle", {
        Text = "Enable Anti-AFK",
        Default = false,
        Callback = function(value)
            if value then
                if VirtualUser and not AntiAFKConnection then
                    AntiAFKConnection = LocalPlayer.Idled:Connect(function()
                        pcall(function()
                            VirtualUser:CaptureController()
                            VirtualUser:ClickButton2(Vector2.new())
                        end)
                    end)
                    AddConnection(AntiAFKConnection)
                    Notify("Anti-AFK enabled", 3)
                    pushLog("Anti-AFK enabled")
                else
                    Notify("VirtualUser not available", 3)
                end
            else
                if AntiAFKConnection then
                    AntiAFKConnection:Disconnect()
                    AntiAFKConnection = nil
                    Notify("Anti-AFK disabled", 3)
                    pushLog("Anti-AFK disabled")
                end
            end
        end
    })

    MoveRight:AddDivider()
    MoveRight:AddLabel("<b>Server Tools</b>", true)

    MoveRight:AddButton("Rejoin server", function()
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
        end)
        if not ok then
            Notify("Rejoin failed: " .. tostring(err), 4)
            pushLog("Rejoin failed: " .. tostring(err))
        else
            pushLog("Rejoin triggered")
        end
    end)

    MoveRight:AddButton("Server hop (random)", function()
        local ok, err = pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)
        if not ok then
            Notify("Server hop failed: " .. tostring(err), 4)
            pushLog("Server hop failed: " .. tostring(err))
        else
            pushLog("Server hop triggered")
        end
    end)

    ----------------------------------------------------------------
    -- Tab: ESP
    ----------------------------------------------------------------
    local ESPLeft  = Tabs.ESP:AddLeftGroupbox("Player ESP (3D Highlight)")
    local ESPRight = Tabs.ESP:AddRightGroupbox("Player ESP (2D Drawing)")

    ----------------------------------------------------------------
    -- 3D Highlight ESP
    ----------------------------------------------------------------
    local HighlightFolder = Instance.new("Folder")
    HighlightFolder.Name = "Obsidian_Highlights"
    HighlightFolder.Parent = game:GetService("CoreGui")

    local HighlightState = {
        Enabled = false,
        TeamCheck = true,
    }

    local function getHighlightForCharacter(char)
        if not char then return nil end
        local tagName = "Obsidian_Highlight_Tag"
        local existing = char:FindFirstChild(tagName)
        if existing and existing:IsA("Highlight") then
            return existing
        end

        local hl = Instance.new("Highlight")
        hl.Name = tagName
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.7
        hl.OutlineTransparency = 0
        hl.FillColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.Adornee = char
        hl.Parent = HighlightFolder

        return hl
    end

    local function removeHighlightForCharacter(char)
        if not char then return end
        local tagName = "Obsidian_Highlight_Tag"
        local existing = char:FindFirstChild(tagName)
        if existing and existing:IsA("Highlight") then
            existing:Destroy()
        end
    end

    ESPLeft:AddToggle("ESP_3D_Enabled", {
        Text = "Enable 3D Highlight ESP",
        Default = false,
        Callback = function(value)
            HighlightState.Enabled = value
            if not value then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.Character then
                        removeHighlightForCharacter(plr.Character)
                    end
                end
            end
        end
    })

    ESPLeft:AddToggle("ESP_3D_TeamCheck", {
        Text = "Team check",
        Default = true,
        Callback = function(value)
            HighlightState.TeamCheck = value
        end
    })

    ESPLeft:AddLabel("Highlight ESP uses Roblox Highlight.\nSafer & lighter than full 2D ESP.", true)

    AddConnection(Players.PlayerAdded:Connect(function(plr)
        AddConnection(plr.CharacterAdded:Connect(function(char)
            if not HighlightState.Enabled then
                return
            end
            getHighlightForCharacter(char)
        end))
    end))

    AddConnection(Players.PlayerRemoving:Connect(function(plr)
        if plr.Character then
            removeHighlightForCharacter(plr.Character)
        end
    end))

    AddConnection(RunService.Heartbeat:Connect(function()
        if not HighlightState.Enabled then
            return
        end

        local myTeam = LocalPlayer.Team
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                if char then
                    local sameTeam = (myTeam and plr.Team == myTeam) or false
                    if HighlightState.TeamCheck and sameTeam then
                        removeHighlightForCharacter(char)
                    else
                        local hl = getHighlightForCharacter(char)
                        if hl then
                            if sameTeam then
                                hl.FillColor = Color3.fromRGB(85, 170, 255)
                                hl.OutlineColor = Color3.fromRGB(85, 170, 255)
                            else
                                hl.FillColor = Color3.fromRGB(255, 85, 85)
                                hl.OutlineColor = Color3.fromRGB(255, 85, 85)
                            end
                        end
                    end
                end
            end
        end
    end))

    ----------------------------------------------------------------
    -- 2D ESP (Drawing) – Premium+ only
    ----------------------------------------------------------------
    local DrawingState = {
        Enabled      = false,
        Mode         = "Box",   -- Box / Corner / Tracer
        TracerFrom   = "Bottom",-- Bottom / Center
        TeamCheck    = true,
        IgnoreFriends= true,
        MaxDistance  = 500,
    }

    if not hasDrawing then
        ESPRight:AddLabel("<b>Drawing API not available.</b>\nYour executor does not support 2D ESP.", true)
    elseif not isPremium then
        ESPRight:AddLabel("<b>2D ESP</b> is available for <font color=\"#55aaff\">Premium</font> or higher.", true)
    else
        ESPRight:AddToggle("ESP_2D_Enabled", {
            Text = "Enable 2D ESP",
            Default = false,
            Callback = function(value)
                DrawingState.Enabled = value
                pushLog("2D ESP toggled: " .. tostring(value))
            end
        })

        ESPRight:AddDropdown("ESP_2D_Mode", {
            Text = "ESP Mode",
            Default = "Box",
            Values = { "Box", "Corner", "Tracer" },
            Callback = function(value)
                DrawingState.Mode = value
            end
        })

        ESPRight:AddDropdown("ESP_2D_TracerFrom", {
            Text = "Tracer origin",
            Default = "Bottom",
            Values = { "Bottom", "Center" },
            Callback = function(value)
                DrawingState.TracerFrom = value
            end
        })

        ESPRight:AddToggle("ESP_2D_TeamCheck", {
            Text = "Team check",
            Default = true,
            Callback = function(value)
                DrawingState.TeamCheck = value
            end
        })

        ESPRight:AddToggle("ESP_2D_IgnoreFriends", {
            Text = "Ignore friends",
            Default = true,
            Callback = function(value)
                DrawingState.IgnoreFriends = value
            end
        })

        ESPRight:AddSlider("ESP_2D_MaxDist", {
            Text = "Max distance",
            Default = 500,
            Min = 50,
            Max = 2000,
            Rounding = 0,
            Compact = false,
            Callback = function(value)
                DrawingState.MaxDistance = value
            end
        })

        ESPRight:AddLabel("2D ESP is experimental.\nUse carefully on low-end / mobile devices.", true)

        local Tracers = {}

        local function getTracersForPlayer(plr)
            local existing = Tracers[plr]
            if existing then
                return existing
            end

            local line = Drawing.new("Line")
            line.Thickness = 1
            line.Visible = false
            line.Color = Color3.new(1, 1, 1)

            local box = Drawing.new("Square")
            box.Thickness = 1
            box.Filled = false
            box.Visible = false
            box.Color = Color3.new(1, 1, 1)

            -- corner: 4 small lines
            local corners = {}
            for _ = 1, 4 do
                local c = Drawing.new("Line")
                c.Thickness = 1
                c.Visible = false
                c.Color = Color3.new(1, 1, 1)
                table.insert(corners, c)
            end

            Tracers[plr] = { line = line, box = box, corners = corners }
            return Tracers[plr]
        end

        local function hideAll2D()
            for _, objs in pairs(Tracers) do
                if objs.line then objs.line.Visible = false end
                if objs.box then objs.box.Visible = false end
                if objs.corners then
                    for _, c in ipairs(objs.corners) do
                        c.Visible = false
                    end
                end
            end
        end

        AddConnection(RunService.RenderStepped:Connect(function()
            if not DrawingState.Enabled or not hasDrawing then
                hideAll2D()
                return
            end

            local cam = workspace.CurrentCamera
            if not cam then
                hideAll2D()
                return
            end

            local myTeam = LocalPlayer.Team

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")

                    local objs = getTracersForPlayer(plr)
                    if not objs or not root or not hum or hum.Health <= 0 then
                        if objs then
                            objs.line.Visible = false
                            objs.box.Visible = false
                            if objs.corners then
                                for _, c in ipairs(objs.corners) do
                                    c.Visible = false
                                end
                            end
                        end
                    else
                        local distance = (cam.CFrame.Position - root.Position).Magnitude
                        if distance > DrawingState.MaxDistance then
                            objs.line.Visible = false
                            objs.box.Visible = false
                            if objs.corners then
                                for _, c in ipairs(objs.corners) do
                                    c.Visible = false
                                end
                            end
                        else
                            if DrawingState.TeamCheck and myTeam and plr.Team == myTeam then
                                objs.line.Visible = false
                                objs.box.Visible = false
                                if objs.corners then
                                    for _, c in ipairs(objs.corners) do
                                        c.Visible = false
                                    end
                                end
                            elseif DrawingState.IgnoreFriends and pcall(LocalPlayer.IsFriendsWith, LocalPlayer, plr.UserId) and LocalPlayer:IsFriendsWith(plr.UserId) then
                                objs.line.Visible = false
                                objs.box.Visible = false
                                if objs.corners then
                                    for _, c in ipairs(objs.corners) do
                                        c.Visible = false
                                    end
                                end
                            else
                                local pos, onScreen = cam:WorldToViewportPoint(root.Position)
                                if not onScreen then
                                    objs.line.Visible = false
                                    objs.box.Visible = false
                                    if objs.corners then
                                        for _, c in ipairs(objs.corners) do
                                            c.Visible = false
                                        end
                                    end
                                else
                                    local screenPos = Vector2.new(pos.X, pos.Y)
                                    local origin
                                    if DrawingState.TracerFrom == "Center" then
                                        origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
                                    else
                                        origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                                    end

                                    local scaleFactor = math.clamp(100 / distance, 0.4, 3)
                                    local size = Vector2.new(50, 80) * scaleFactor
                                    size = Vector2.new(math.clamp(size.X, 20, 120), math.clamp(size.Y, 40, 180))
                                    local topLeft = screenPos - size / 2

                                    if DrawingState.Mode == "Tracer" then
                                        objs.box.Visible = false
                                        if objs.corners then
                                            for _, c in ipairs(objs.corners) do
                                                c.Visible = false
                                            end
                                        end

                                        objs.line.Visible = true
                                        objs.line.From = origin
                                        objs.line.To = screenPos
                                    elseif DrawingState.Mode == "Box" then
                                        objs.line.Visible = false
                                        if objs.corners then
                                            for _, c in ipairs(objs.corners) do
                                                c.Visible = false
                                            end
                                        end

                                        objs.box.Visible = true
                                        objs.box.Position = topLeft
                                        objs.box.Size = size
                                    else -- Corner
                                        objs.line.Visible = false
                                        objs.box.Visible = false

                                        local corners = objs.corners
                                        if corners then
                                            local w, h = size.X, size.Y
                                            local tl = topLeft
                                            local tr = Vector2.new(topLeft.X + w, topLeft.Y)
                                            local bl = Vector2.new(topLeft.X, topLeft.Y + h)
                                            local br = Vector2.new(topLeft.X + w, topLeft.Y + h)

                                            local len = 6

                                            corners[1].Visible = true
                                            corners[1].From = tl
                                            corners[1].To = tl + Vector2.new(len, 0)

                                            corners[2].Visible = true
                                            corners[2].From = tl
                                            corners[2].To = tl + Vector2.new(0, len)

                                            corners[3].Visible = true
                                            corners[3].From = tr
                                            corners[3].To = tr + Vector2.new(-len, 0)

                                            corners[4].Visible = true
                                            corners[4].From = tr
                                            corners[4].To = tr + Vector2.new(0, len)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end))
    end

    ----------------------------------------------------------------
    -- Tab: Game (Game Modules)
    ----------------------------------------------------------------
    local GameTab       = Tabs.Game
    local GameLeftBox   = GameTab:AddLeftGroupbox("Game Module")
    local GameRightBox  = GameTab:AddRightGroupbox("Info")

    local function addGameLabel(group, text)
        local lbl = group:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

    local gameModuleInfo = GameModules[placeId]

    if not gameModuleInfo then
        addGameLabel(GameLeftBox, "<b>This game has no dedicated module yet.</b>")
        addGameLabel(GameLeftBox, "You can add one in GameModules table in MainHub.lua.")
    else
        local minRole = gameModuleInfo.MinRole or "user"
        addGameLabel(GameLeftBox, string.format("<b>Detected module</b>: %s", tostring(gameModuleInfo.Name or "Unknown")))
        addGameLabel(GameLeftBox, string.format("<b>Required role</b>: %s", GetRoleLabel(minRole)))

        if not RoleAtLeast(minRole) then
            addGameLabel(GameLeftBox, string.format(
                '<font color="#ff6666">Your role (%s) is not enough to load this module.</font>',
                GetRoleLabel(role)
            ))
        else
            GameLeftBox:AddButton("Load Game Module", function()
                pushLog("Attempting to load game module for PlaceId=" .. tostring(placeId))
                local ok, srcOrErr = pcall(Exec.HttpGet, gameModuleInfo.Url)
                if not ok or type(srcOrErr) ~= "string" or srcOrErr == "" then
                    Notify("Failed to load game module (HTTP error)", 4)
                    pushLog("Game module HTTP error: " .. tostring(srcOrErr))
                    return
                end

                local chunk, err = loadstring(srcOrErr)
                if not chunk then
                    Notify("Game module loadstring error", 4)
                    pushLog("Game module loadstring error: " .. tostring(err))
                    return
                end

                local ok2, moduleFnOrErr = pcall(chunk)
                if not ok2 then
                    Notify("Game module runtime error", 4)
                    pushLog("Game module runtime error: " .. tostring(moduleFnOrErr))
                    return
                end

                if type(moduleFnOrErr) ~= "function" then
                    Notify("Game module must return a function(Exec, Library, Tab, keydata, ctx)", 5)
                    pushLog("Game module returned non-function")
                    return
                end

                local ctx = {
                    role      = role,
                    roleLabel = GetRoleLabel(role),
                    status    = keyStatus,
                    keydata   = keydata,
                }

                local ok3, err3 = pcall(moduleFnOrErr, Exec, Library, GameTab, keydata, ctx)
                if not ok3 then
                    Notify("Game module error: " .. tostring(err3), 5)
                    pushLog("Game module error: " .. tostring(err3))
                else
                    Notify("Game module loaded successfully", 3)
                    pushLog("Game module loaded successfully")
                end
            end)
        end
    end

    addGameLabel(GameRightBox, "<b>Game Module System</b>")
    addGameLabel(GameRightBox, "Add entries to GameModules in MainHub.lua")
    addGameLabel(GameRightBox, "Each module URL should return function(Exec, Library, Tab, keydata, ctx)")

    ----------------------------------------------------------------
    -- Tab: UI / Theme / Config
    ----------------------------------------------------------------
    local UILeft  = Tabs.UI:AddLeftGroupbox("UI / Theme")
    local UIRight = Tabs.UI:AddRightGroupbox("Config / Misc")

    UILeft:AddLabel("<b>Theme</b>", true)
    UILeft:AddDivider()

    if ThemeManager and type(ThemeManager.ApplyToTab) == "function" then
        ThemeManager:ApplyToTab(Tabs.UI)
    end

    if ThemeManager and type(ThemeManager.BuildThemeSection) == "function" then
        ThemeManager:BuildThemeSection(UILeft)
    else
        UILeft:AddLabel("ThemeManager not fully available.", true)
    end

    UIRight:AddLabel("<b>Config</b>", true)
    UIRight:AddDivider()

    if SaveManager and type(SaveManager.BuildConfigSection) == "function" then
        SaveManager:BuildConfigSection(UIRight)
    else
        UIRight:AddLabel("SaveManager not fully available.", true)
    end

    UIRight:AddDivider()
    UIRight:AddButton("Unload Hub", function()
        CleanupConnections()
        if HighlightFolder then
            pcall(function()
                HighlightFolder:Destroy()
            end)
        end
        Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    UIRight:AddButton("Copy Discord", function()
        local ok, err = Exec.SetClipboard("https://discord.gg/yourdiscord")
        if ok then
            Notify("Copied Discord link", 3)
        else
            Notify("Clipboard not available: " .. tostring(err), 3)
        end
    end)

    ----------------------------------------------------------------
    -- Tab: Dev (เฉพาะ staff/owner)
    ----------------------------------------------------------------
    if Tabs.Dev then
        local DevLeft  = Tabs.Dev:AddLeftGroupbox("Dev Info")
        local DevRight = Tabs.Dev:AddRightGroupbox("Dev Log")

        local function addDevLabel(group, text)
            local lbl = group:AddLabel(text, true)
            if lbl and lbl.TextLabel then
                lbl.TextLabel.RichText = true
            end
            return lbl
        end

        addDevLabel(DevLeft, string.format("<b>Role</b>: %s", GetRoleLabel(role)))
        addDevLabel(DevLeft, string.format("<b>Tier</b>: %s", GetTierLabel()))
        addDevLabel(DevLeft, string.format("<b>Key status</b>: %s", keyStatus))
        addDevLabel(DevLeft, string.format("<b>PlaceId</b>: %d", placeId))
        addDevLabel(DevLeft, string.format("<b>JobId</b>: %s", jobId))

        local LogLabel = addDevLabel(DevRight, "<b>Log</b>:")

        local function updateLogLabel()
            if not (LogLabel and LogLabel.TextLabel) then
                return
            end
            local textLines = {}
            for _, line in ipairs(DevLog) do
                table.insert(textLines, line)
            end
            if #textLines == 0 then
                table.insert(textLines, "(no log)")
            end
            LogLabel.TextLabel.Text = "<b>Log</b>:\n" .. table.concat(textLines, "\n")
            LogLabel.TextLabel.RichText = true
        end

        updateLogLabel()

        DevRight:AddButton("Refresh log", function()
            updateLogLabel()
        end)

        DevRight:AddButton("Write log to file", function()
            local data = table.concat(DevLog, "\n")
            local ok, err = Exec.WriteFile("obsidian_universal_log.txt", data)
            if ok then
                Notify("Wrote log to obsidian_universal_log.txt", 3)
            else
                Notify("Write log failed: " .. tostring(err), 4)
            end
        end)

        -- auto refresh ทุก 10 วินาที (เบา ๆ)
        AddConnection(RunService.Heartbeat:Connect(function()
            -- refresh นาน ๆ ครั้งก็พอ
        end))
    end

    -- จบ MainHub: Library จะ handle main UI loop เอง
end
