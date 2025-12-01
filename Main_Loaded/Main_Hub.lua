-- STATUS:online
-- STATUS_MSG:Main hub is live and ready

-- MainHub.lua
-- ต้องถูกโหลดผ่าน Key_Loaded.lua เท่านั้น
-- ห้ามเรียกตรง ๆ จาก executor โดยไม่มี keycheck

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- ชั้นที่สอง: ตรวจ keycheck + keydata
    ----------------------------------------------------------------
    local EXPECTED_KEYCHECK = "BxB.ware-universal-private-*&^%$#$*#%&@#" -- ต้องตรงกับ Config.KEYCHECK_TOKEN ใน Key_Loaded.lua

    if keycheck ~= EXPECTED_KEYCHECK then
        -- ถ้าใครพยายาม load MainHub โดยตรง หรือ token ไม่ตรง -> ไม่ทำอะไรเลย
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

    local LocalPlayer = Players.LocalPlayer

    if not LocalPlayer then
        return
    end

    ----------------------------------------------------------------
    -- โหลด Obsidian Library + ThemeManager + SaveManager
    -- รูปแบบ load ตามที่คุณเคยใช้ (สำคัญ)
    ----------------------------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

    ----------------------------------------------------------------
    -- ตั้งค่า Theme / Save อย่างระมัดระวัง (เช็คฟังก์ชันก่อนเรียก)
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
    -- Helper: connection management (เพื่อ cleanup เวลา Unload)
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

    ----------------------------------------------------------------
    -- Helper: safe get humanoid / root
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
        local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
        return root
    end

    AddConnection(LocalPlayer.CharacterAdded:Connect(function()
        -- เวลา respawn ให้ reset ค่า default ต่าง ๆ
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
        local y, m, d = dt:ToUniversalTime().Year, dt:ToUniversalTime().Month, dt:ToUniversalTime().Day
        local hour, min, sec = dt:ToUniversalTime().Hour, dt:ToUniversalTime().Minute, dt:ToUniversalTime().Second

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
        local memStats = Stats:FindFirstChild("PerformanceStats")
        if not memStats then
            return 0
        end

        local mem = memStats:FindFirstChild("MemoryUsageMb")
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
    -- ตรวจ Drawing API สำหรับ ESP 2D
    ----------------------------------------------------------------
    local hasDrawing = false
    do
        local ok, result = pcall(function()
            return Drawing and typeof(Drawing.new) == "function"
        end)
        hasDrawing = ok and result == true
    end

    ----------------------------------------------------------------
    -- สร้าง Window + Tabs
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "BxB.ware",
            Footer = "BxB.ware | Universal | Premium",    
                Icon = "sparkle",
        Center = true,
        AutoShow = true,

        DisableSearch = false,              
            SearchbarSize = UDim2.fromScale(1, 1), -- ขนาด searchbar (ใช้เมื่อ DisableSearch = false)
        
        Compact = true
    })

    local Tabs = {
        Status = Window:AddTab("","shield-check"),
        Player = Window:AddTab("","user"),
        ESP    = Window:AddTab("","eye"),
        UI     = Window:AddTab("","settings")
    }

    local Options = Library.Options

    ----------------------------------------------------------------
    -- Tab 1: Status (Key + System)
    ----------------------------------------------------------------
    local KeyBoxLeft = Tabs.Status:AddLeftGroupbox("Key Status")
    local SysBoxRight = Tabs.Status:AddRightGroupbox("System Info")

    KeyBoxLeft:AddLabel("<b>Key Information</b>", true)
    KeyBoxLeft:AddDivider()

    local keyRole   = tostring(keydata.role or "user")
    local keyStatus = tostring(keydata.status or "active")
    local keyNote   = tostring(keydata.note or "")
    local keyStamp  = tonumber(keydata.timestamp)
    local keyExpire = tonumber(keydata.expire)

    local keyCreatedAt = keyStamp and formatUnix(keyStamp) or "N/A"
    local keyExpireAt  = keyExpire and formatUnix(keyExpire) or "Lifetime"

    local KeyLabels = {}

    local function addKeyLabel(id, text)
        local lbl = KeyBoxLeft:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        KeyLabels[id] = lbl
        return lbl
    end

    addKeyLabel("KeyID", string.format("<b>Key</b>: %s", shortKey(keydata.key)))
    addKeyLabel("Role", string.format("<b>Role</b>: %s", keyRole))
    addKeyLabel("Status", string.format("<b>Status</b>: %s", keyStatus))
    addKeyLabel("Note", string.format("<b>Note</b>: %s", (keyNote ~= "" and keyNote or "N/A")))
    addKeyLabel("Created", string.format("<b>Created at</b>: %s", keyCreatedAt))
    addKeyLabel("Expire", string.format("<b>Expire at</b>: %s", keyExpireAt))
    local timeLeftLbl = addKeyLabel("TimeLeft", string.format("<b>Time left</b>: %s", formatTimeLeft(keyExpire)))

    KeyBoxLeft:AddDivider()
    KeyBoxLeft:AddLabel('<font color="#ffcc66">Key is bound to your HWID (device). Sharing key may result in ban.</font>', true)

    -- อัปเดต TimeLeft แบบเบา ๆ ทุก ~1 วินาที
    AddConnection(RunService.Heartbeat:Connect(function()
        if not timeLeftLbl or not timeLeftLbl.TextLabel then
            return
        end

        local text = formatTimeLeft(keyExpire)
        timeLeftLbl.TextLabel.Text = string.format("<b>Time left</b>: %s", text)
        timeLeftLbl.TextLabel.RichText = true
    end))

    SysBoxRight:AddLabel("<b>System / Game / Player</b>", true)
    SysBoxRight:AddDivider()

    local function addSysLabel(text)
        local lbl = SysBoxRight:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

    local placeId = game.PlaceId
    local jobId = game.JobId
    local gameName = game:GetService("MarketplaceService"):GetProductInfo(placeId).Name

    local sysLabels = {
        Game      = addSysLabel(string.format("<b>Game</b>: %s (PlaceId: %d)", gameName, placeId)),
        Server    = addSysLabel(string.format("<b>JobId</b>: %s", jobId)),
        Player    = addSysLabel(string.format("<b>Player</b>: %s (%d)", LocalPlayer.Name, LocalPlayer.UserId)),
        FPS       = addSysLabel("<b>FPS</b>: ..."),
        Ping      = addSysLabel("<b>Ping</b>: ..."),
        Memory    = addSysLabel("<b>Memory</b>: ... MB")
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

    SysBoxRight:AddDivider()
    SysBoxRight:AddLabel("<b>Credits</b>", true)
    SysBoxRight:AddLabel("Owner: YOUR_NAME_HERE", true)
    SysBoxRight:AddLabel("UI: Obsidian UI Library", true)
    SysBoxRight:AddLabel("Discord: yourdiscord", true)

    ----------------------------------------------------------------
    -- Tab 2: Player (Movement & Misc)
    ----------------------------------------------------------------
    local MoveLeft = Tabs.Player:AddLeftGroupbox("Movement")
    local MoveRight = Tabs.Player:AddRightGroupbox("Misc / Safety")

    local MovementState = {
        WalkSpeedEnabled = false,
        WalkSpeedValue   = 16,
        JumpEnabled      = false,
        JumpValue        = 50,
        InfiniteJump     = false,
        Fly              = false,
        NoClip           = false
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

    -- Infinite Jump handler (เบามาก)
    AddConnection(UserInputService.JumpRequest:Connect(function()
        if not MovementState.InfiniteJump then
            return
        end

        local hum = GetHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))

    -- Fly + NoClip loop (RenderStepped)
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

        Library:Notify("Movement reset to default", 3)
    end)

    MoveRight:AddButton("Panic (Unload Hub)", function()
        CleanupConnections()
        Library:Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    ----------------------------------------------------------------
    -- Tab 3: ESP
    ----------------------------------------------------------------
    local ESPLeft  = Tabs.ESP:AddLeftGroupbox("Player ESP (3D Highlight)")
    local ESPRight = Tabs.ESP:AddRightGroupbox("Player ESP (2D Drawing)")

    ----------------------------------------------------------------
    -- 3D Highlight ESP
    ----------------------------------------------------------------
    local HighlightFolder = Instance.new("Folder")
    HighlightFolder.Name = "Obsidian_Highlights"
    HighlightFolder.Parent = game.CoreGui

    local HighlightState = {
        Enabled = false,
        TeamCheck = true
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
                    removeHighlightForCharacter(plr.Character)
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

    ESPLeft:AddLabel("Highlight ESP uses Roblox Highlight instances.\nSafer and lighter than full 2D ESP.", true)

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
    -- 2D ESP (Drawing) – optional
    ----------------------------------------------------------------
    local DrawingState = {
        Enabled = false,
        Mode = "Box", -- Box / Corner / Tracer
        TracerFrom = "Bottom" -- Bottom / Center
    }

    if not hasDrawing then
        ESPRight:AddLabel("<b>Drawing API not available.</b>\nYour executor does not support 2D ESP.", true)
    else
        ESPRight:AddToggle("ESP_2D_Enabled", {
            Text = "Enable 2D ESP",
            Default = false,
            Callback = function(value)
                DrawingState.Enabled = value
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

        ESPRight:AddLabel("2D ESP is experimental.\nUse carefully on low-end / mobile devices.", true)

        local Tracers = {}

        local function getTracerForPlayer(plr)
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

            Tracers[plr] = { line = line, box = box }
            return Tracers[plr]
        end

        local function hideAll2D()
            for _, objs in pairs(Tracers) do
                if objs.line then objs.line.Visible = false end
                if objs.box then objs.box.Visible = false end
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

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")

                    local objs = getTracerForPlayer(plr)
                    if not objs or not root or not hum or hum.Health <= 0 then
                        if objs then
                            objs.line.Visible = false
                            objs.box.Visible = false
                        end
                    else
                        local pos, onScreen = cam:WorldToViewportPoint(root.Position)
                        if not onScreen then
                            objs.line.Visible = false
                            objs.box.Visible = false
                        else
                            local screenPos = Vector2.new(pos.X, pos.Y)

                            local origin
                            if DrawingState.TracerFrom == "Center" then
                                origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
                            else
                                origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                            end

                            if DrawingState.Mode == "Tracer" then
                                objs.box.Visible = false

                                objs.line.Visible = true
                                objs.line.From = origin
                                objs.line.To = screenPos
                            else
                                objs.line.Visible = false

                                local scale = 2
                                local size = Vector2.new(50, 80) * (cam.CFrame.Position - root.Position).Magnitude / 100
                                size = Vector2.new(math.clamp(size.X, 20, 120), math.clamp(size.Y, 40, 180))

                                objs.box.Visible = true
                                objs.box.Position = screenPos - size / 2
                                objs.box.Size = size

                                if DrawingState.Mode == "Corner" then
                                    -- สำหรับ simplicity: ยังใช้ box ปกติ (แต่คุณจะต่อยอดให้เป็น corner แยกเองได้)
                                end
                            end
                        end
                    end
                end
            end
        end))
    end

    ----------------------------------------------------------------
    -- Tab 4: UI / Theme / Config
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
        Library:Notify("Unloading hub...", 2)
        Library:Unload()
    end)

    UIRight:AddButton("Copy Discord", function()
        local ok, err = Exec.SetClipboard("https://discord.gg/yourdiscord")
        if ok then
            Library:Notify("Copied Discord link", 3)
        else
            Library:Notify("Clipboard not available: " .. tostring(err), 3)
        end
    end)

    -- จบ function: Library จะรัน UI Loop ของมันเอง
end
