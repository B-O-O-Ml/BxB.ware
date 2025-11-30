
        
-- MainHub.lua
-- ต้องถูกเรียกผ่าน Key UI: startMainHub(keydata, Library) -> loadstring(HttpGet(MAINHUB_URL))()(Exec, keydata, "success")
-- return function(Exec, keydata, keycheck)

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- Guard ชั้นที่ 1: keycheck
    ----------------------------------------------------------------
    if keycheck ~= "BxB.ware-universal-private-*&^%$#$*#%&@#" then
        return
    end

    keydata = keydata or {}

    ----------------------------------------------------------------
    -- Guard ชั้นที่ 2: เช็คหมดอายุจาก keydata (ป้องกัน loader ถูกแก้)
    ----------------------------------------------------------------
    local function getUnixNow()
        local ok, dt = pcall(DateTime.now)
        if ok and dt then
            return dt.UnixTimestamp
        end
        return nil
    end

    local function isKeydataExpired(kd)
        if type(kd) ~= "table" then
            return false
        end

        local expireTs = tonumber(kd.expire or kd.expire_at or kd.expire_unix or kd.expires_at)
        if not expireTs then
            return false
        end

        local nowTs = getUnixNow()
        if not nowTs then
            return false
        end

        return nowTs >= expireTs
    end

    if isKeydataExpired(keydata) then
        warn("[Obsidian] Key expired (MainHub second layer).")
        return
    end

    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local StatsService = game:GetService("Stats")

    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- Helpers: Character / Humanoid / Root
    ----------------------------------------------------------------
    local function getCharacter()
        return LocalPlayer and LocalPlayer.Character or nil
    end

    local function getHumanoid()
        local char = getCharacter()
        if not char then
            return nil
        end

        return char:FindFirstChildOfClass("Humanoid")
    end

    local function getRootPart()
        local char = getCharacter()
        if not char then
            return nil
        end

        return char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- Helpers: Time / Date
    ----------------------------------------------------------------
    local function formatDateTime(dt)
        local d = dt.Day
        local m = dt.Month
        local y = dt.Year % 100
        local h = dt.Hour
        local mi = dt.Minute
        local s = dt.Second

        return string.format("%02d/%02d/%02d - %02d:%02d:%02d", d, m, y, h, mi, s)
    end

    local function formatUnixTimestamp(ts)
        if type(ts) ~= "number" then
            return "N/A"
        end

        local ok, dt = pcall(DateTime.fromUnixTimestamp, ts)
        if ok and dt then
            return formatDateTime(dt)
        end

        return tostring(ts)
    end

    local function getNowString()
        local ok, dt = pcall(DateTime.now)
        if ok and dt then
            return formatDateTime(dt)
        end
        return "N/A"
    end

    local function formatDuration(sec)
        if type(sec) ~= "number" then
            return "N/A"
        end

        sec = math.floor(sec)
        if sec <= 0 then
            return "0s"
        end

        local days = math.floor(sec / 86400)
        sec = sec % 86400

        local hours = math.floor(sec / 3600)
        sec = sec % 3600

        local minutes = math.floor(sec / 60)
        sec = sec % 60

        local parts = {}

        if days > 0 then
            table.insert(parts, tostring(days) .. "d")
        end

        if hours > 0 then
            table.insert(parts, tostring(hours) .. "h")
        end

        if minutes > 0 then
            table.insert(parts, tostring(minutes) .. "m")
        end

        if sec > 0 or #parts == 0 then
            table.insert(parts, tostring(sec) .. "s")
        end

        return table.concat(parts, " ")
    end

    ----------------------------------------------------------------
    -- โหลด Obsidian Library จาก repo ที่คุณใช้ (ไม่ผ่าน Exec)
    ----------------------------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

    if ThemeManager and type(ThemeManager.SetLibrary) == "function" then
        ThemeManager:SetLibrary(Library)
    end

    if SaveManager and type(SaveManager.SetLibrary) == "function" then
        SaveManager:SetLibrary(Library)
    end

    if ThemeManager and type(ThemeManager.SetFolder) == "function" then
        ThemeManager:SetFolder("ObsidianHub")
    end

    if SaveManager and type(SaveManager.SetFolder) == "function" then
        SaveManager:SetFolder("ObsidianHub")
    end

    ----------------------------------------------------------------
    -- Window + Tabs
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "Obsidian | Universal Hub",
        Center = true,
        AutoShow = true
    })

    local Tabs = {
        Status = Window:AddTab("Status"),
        Player = Window:AddTab("Player"),
        ESP    = Window:AddTab("ESP"),
        UI     = Window:AddTab("UI")
    }

    ----------------------------------------------------------------
    -- Helpers: RichText / masking
    ----------------------------------------------------------------
    local function setRichLabel(label, text)
        if label and label.TextLabel then
            label.TextLabel.RichText = true
            label.TextLabel.Text = text
        end
    end

    local function maskKey(key)
        key = tostring(key or "")
        local len = #key

        if len <= 6 then
            return string.rep("*", len)
        end

        return key:sub(1, 3) .. string.rep("*", len - 6) .. key:sub(len - 2, len)
    end

    local function shortHash(hash)
        hash = tostring(hash or "")
        if #hash <= 8 then
            return hash
        end
        return hash:sub(1, 4) .. "..." .. hash:sub(#hash - 3, #hash)
    end

    ----------------------------------------------------------------
    -- TAB 1: Status
    ----------------------------------------------------------------
    local StatusKeyBox     = Tabs.Status:AddLeftGroupbox("Key & User")
    local StatusCreditsBox = Tabs.Status:AddLeftGroupbox("Credits")
    local StatusServerBox  = Tabs.Status:AddRightGroupbox("Server & Performance")

    local keyMasked = maskKey(keydata.key or "N/A")
    local role = keydata.role or "N/A"
    local keyTimestamp = tonumber(keydata.timestamp)
    local expireTs = tonumber(keydata.expire or keydata.expire_at or keydata.expire_unix)

    local keyLabel      = StatusKeyBox:AddLabel("", true)
    local roleLabel     = StatusKeyBox:AddLabel("", true)
    local hwidLabel     = StatusKeyBox:AddLabel("", true)
    local userLabel     = StatusKeyBox:AddLabel("", true)
    local keyTimeLabel  = StatusKeyBox:AddLabel("", true)
    local nowTimeLabel  = StatusKeyBox:AddLabel("", true)
    local expireLabel   = StatusKeyBox:AddLabel("", true)
    local leftTimeLabel = StatusKeyBox:AddLabel("", true)

    setRichLabel(keyLabel, "<b>Key</b>: " .. keyMasked)
    setRichLabel(roleLabel, "<b>Role</b>: " .. role)
    setRichLabel(hwidLabel, "<b>HWID Hash</b>: " .. shortHash(keydata.hwid_hash))
    setRichLabel(userLabel, "<b>User</b>: " .. (LocalPlayer and LocalPlayer.Name or "N/A"))

    if keyTimestamp then
        setRichLabel(keyTimeLabel, "<b>Key Time</b>: " .. formatUnixTimestamp(keyTimestamp))
    else
        setRichLabel(keyTimeLabel, "<b>Key Time</b>: N/A")
    end

    setRichLabel(nowTimeLabel, "<b>Current Time</b>: " .. getNowString())

    if expireTs then
        setRichLabel(expireLabel, "<b>Expire At</b>: " .. formatUnixTimestamp(expireTs))
    else
        setRichLabel(expireLabel, "<b>Expire At</b>: N/A")
    end

    setRichLabel(leftTimeLabel, "<b>Time Left</b>: N/A")

    StatusKeyBox:AddDivider()

    local creditLines = {
        "<b>Obsidian Universal Hub</b>",
        "Developer: <font color=\"#7dcfff\">YOUR_NAME_HERE</font>",
        "Library: <font color=\"#b58cff\">Obsidian UI</font>",
        "Discord: <font color=\"#55ff99\">https://discord.gg/yourdiscord</font>",
        "",
        "<font color=\"#aaaaaa\">Please do not leak / resell.</font>"
    }

    local creditLabel = StatusCreditsBox:AddLabel(table.concat(creditLines, "\n"), true)
    if creditLabel and creditLabel.TextLabel then
        creditLabel.TextLabel.RichText = true
    end

    local placeId = game.PlaceId
    local jobId   = game.JobId

    local serverPlaceLabel = StatusServerBox:AddLabel("", true)
    local serverJobLabel   = StatusServerBox:AddLabel("", true)
    local playerCountLabel = StatusServerBox:AddLabel("", true)
    local pingLabel        = StatusServerBox:AddLabel("", true)
    local fpsLabel         = StatusServerBox:AddLabel("", true)

    setRichLabel(serverPlaceLabel, "<b>PlaceId</b>: " .. tostring(placeId))
    setRichLabel(serverJobLabel, "<b>JobId</b>: " .. tostring(jobId))

    local function updatePlayerCount()
        local count = #Players:GetPlayers()
        setRichLabel(playerCountLabel, "<b>Players</b>: " .. tostring(count))
    end

    updatePlayerCount()
    Players.PlayerAdded:Connect(updatePlayerCount)
    Players.PlayerRemoving:Connect(updatePlayerCount)

    local frameCount = 0
    local timeAcc = 0

    RunService.RenderStepped:Connect(function(dt)
        frameCount = frameCount + 1
        timeAcc = timeAcc + dt

        if timeAcc >= 1 then
            local fps = math.floor(frameCount / timeAcc + 0.5)
            frameCount = 0
            timeAcc = 0

            local pingText = "N/A"
            local okPing, pingValue = pcall(function()
                local pingStat = StatsService.Network.ServerStatsItem["Data Ping"]
                if pingStat then
                    return pingStat:GetValue()
                end
                return nil
            end)
            if okPing and pingValue then
                pingText = tostring(math.floor(pingValue + 0.5)) .. " ms"
            end

            setRichLabel(pingLabel, "<b>Ping</b>: " .. pingText)
            setRichLabel(fpsLabel, "<b>FPS</b>: " .. tostring(fps))

            setRichLabel(nowTimeLabel, "<b>Current Time</b>: " .. getNowString())

            if expireTs then
                local nowTs = getUnixNow()
                if nowTs then
                    local remain = expireTs - nowTs
                    if remain <= 0 then
                        setRichLabel(leftTimeLabel, "<b>Time Left</b>: <font color=\"#ff5555\">Expired</font>")
                    else
                        setRichLabel(leftTimeLabel, "<b>Time Left</b>: " .. formatDuration(remain))
                    end
                end
            end
        end
    end)

    ----------------------------------------------------------------
    -- TAB 2: Player (Movement)
    ----------------------------------------------------------------
    local PlayerMoveBox  = Tabs.Player:AddLeftGroupbox("Movement")
    local PlayerExtraBox = Tabs.Player:AddRightGroupbox("Extra")

    local MovementState = {
        WalkSpeedEnabled = false,
        WalkSpeedValue = 16,
        JumpPowerEnabled = false,
        JumpPowerValue = 50,
        NoClip = false,
        FlyEnabled = false,
        FlySpeed = 60
    }

    local DefaultValues = {
        WalkSpeed = nil,
        JumpPower = nil,
        JumpHeight = nil
    }

    local function updateDefaultHumanoidValues()
        local hum = getHumanoid()
        if not hum then
            return
        end

        if DefaultValues.WalkSpeed == nil then
            DefaultValues.WalkSpeed = hum.WalkSpeed
        end

        if DefaultValues.JumpPower == nil or DefaultValues.JumpHeight == nil then
            local ok = pcall(function()
                DefaultValues.JumpPower = hum.JumpPower
                DefaultValues.JumpHeight = hum.JumpHeight
            end)
            if not ok then end
        end
    end

    local noclipParts = {}

    local function updateNoClip()
        if not MovementState.NoClip then
            return
        end

        local char = getCharacter()
        if not char then
            return
        end

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
                noclipParts[part] = true
            end
        end
    end

    local function disableNoClip()
        for part in pairs(noclipParts) do
            if part and part.Parent then
                pcall(function()
                    part.CanCollide = true
                end)
            end
        end
        noclipParts = {}
    end

    local infJumpConnection

    local function setInfiniteJump(enabled)
        if enabled then
            if infJumpConnection then
                return
            end

            infJumpConnection = UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid()
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        else
            if infJumpConnection then
                infJumpConnection:Disconnect()
                infJumpConnection = nil
            end
        end
    end

    local FlyState = {
        Speed = MovementState.FlySpeed
    }

    local flyKeys = {
        W = false,
        A = false,
        S = false,
        D = false,
        Space = false,
        LeftShift = false
    }

    local flyBV
    local flyBG

    local function resetFlyBody()
        if flyBV then
            flyBV:Destroy()
            flyBV = nil
        end
        if flyBG then
            flyBG:Destroy()
            flyBG = nil
        end
    end

    local function updateFly()
        if not MovementState.FlyEnabled then
            resetFlyBody()
            return
        end

        local root = getRootPart()
        local cam = workspace.CurrentCamera
        if not root or not cam then
            resetFlyBody()
            return
        end

        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyBV.Velocity = Vector3.new()
            flyBV.Parent = root

            flyBG = Instance.new("BodyGyro")
            flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            flyBG.CFrame = cam.CFrame
            flyBG.Parent = root
        end

        local dir = Vector3.new()
        local cf = cam.CFrame

        if flyKeys.W then
            dir = dir + cf.LookVector
        end
        if flyKeys.S then
            dir = dir - cf.LookVector
        end
        if flyKeys.A then
            dir = dir - cf.RightVector
        end
        if flyKeys.D then
            dir = dir + cf.RightVector
        end
        if flyKeys.Space then
            dir = dir + Vector3.new(0, 1, 0)
        end
        if flyKeys.LeftShift then
            dir = dir - Vector3.new(0, 1, 0)
        end

        if dir.Magnitude > 0 then
            dir = dir.Unit
        end

        flyBV.Velocity = dir * FlyState.Speed
        flyBG.CFrame = cam.CFrame
    end

    RunService.Heartbeat:Connect(function()
        updateDefaultHumanoidValues()

        local hum = getHumanoid()
        if hum then
            if MovementState.WalkSpeedEnabled then
                hum.WalkSpeed = MovementState.WalkSpeedValue
            elseif DefaultValues.WalkSpeed then
                hum.WalkSpeed = DefaultValues.WalkSpeed
            end

            local ok = pcall(function()
                if hum.UseJumpPower ~= false then
                    if MovementState.JumpPowerEnabled then
                        hum.JumpPower = MovementState.JumpPowerValue
                    elseif DefaultValues.JumpPower then
                        hum.JumpPower = DefaultValues.JumpPower
                    end
                else
                    if MovementState.JumpPowerEnabled then
                        hum.JumpHeight = MovementState.JumpPowerValue / 3
                    elseif DefaultValues.JumpHeight then
                        hum.JumpHeight = DefaultValues.JumpHeight
                    end
                end
            end)
            if not ok then end
        end

        if MovementState.NoClip then
            updateNoClip()
        end

        if MovementState.FlyEnabled then
            updateFly()
        else
            resetFlyBody()
        end
    end)

    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then
            return
        end

        if input.KeyCode == Enum.KeyCode.W then
            flyKeys.W = true
        elseif input.KeyCode == Enum.KeyCode.A then
            flyKeys.A = true
        elseif input.KeyCode == Enum.KeyCode.S then
            flyKeys.S = true
        elseif input.KeyCode == Enum.KeyCode.D then
            flyKeys.D = true
        elseif input.KeyCode == Enum.KeyCode.Space then
            flyKeys.Space = true
        elseif input.KeyCode == Enum.KeyCode.LeftShift then
            flyKeys.LeftShift = true
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gp)
        if gp then
            return
        end

        if input.KeyCode == Enum.KeyCode.W then
            flyKeys.W = false
        elseif input.KeyCode == Enum.KeyCode.A then
            flyKeys.A = false
        elseif input.KeyCode == Enum.KeyCode.S then
            flyKeys.S = false
        elseif input.KeyCode == Enum.KeyCode.D then
            flyKeys.D = false
        elseif input.KeyCode == Enum.KeyCode.Space then
            flyKeys.Space = false
        elseif input.KeyCode == Enum.KeyCode.LeftShift then
            flyKeys.LeftShift = false
        end
    end)

    PlayerMoveBox:AddToggle("Move_WalkSpeed_Toggle", {
        Text = "WalkSpeed",
        Default = false,
        Callback = function(value)
            MovementState.WalkSpeedEnabled = value
        end
    })

    PlayerMoveBox:AddSlider("Move_WalkSpeed_Value", {
        Text = "WalkSpeed Value",
        Default = 16,
        Min = 8,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            MovementState.WalkSpeedValue = value
        end
    })

    PlayerMoveBox:AddToggle("Move_JumpPower_Toggle", {
        Text = "Jump Power / Height",
        Default = false,
        Callback = function(value)
            MovementState.JumpPowerEnabled = value
        end
    })

    PlayerMoveBox:AddSlider("Move_JumpPower_Value", {
        Text = "Jump Power Value",
        Default = 50,
        Min = 25,
        Max = 200,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            MovementState.JumpPowerValue = value
        end
    })

    PlayerMoveBox:AddToggle("Move_Fly_Toggle", {
        Text = "Fly (WASD + Space/Shift)",
        Default = false,
        Callback = function(value)
            MovementState.FlyEnabled = value
            if not value then
                resetFlyBody()
            end
        end
    })

    PlayerMoveBox:AddSlider("Move_Fly_Speed", {
        Text = "Fly Speed",
        Default = 60,
        Min = 20,
        Max = 200,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            MovementState.FlySpeed = value
            FlyState.Speed = value
        end
    })

    PlayerExtraBox:AddToggle("Move_NoClip_Toggle", {
        Text = "NoClip",
        Default = false,
        Callback = function(value)
            MovementState.NoClip = value
            if not value then
                disableNoClip()
            end
        end
    })

    PlayerExtraBox:AddToggle("Move_InfJump_Toggle", {
        Text = "Infinite Jump",
        Default = false,
        Callback = function(value)
            setInfiniteJump(value)
        end
    })

    ----------------------------------------------------------------
    -- TAB 3: ESP (Highlight + 2D Drawing)
    ----------------------------------------------------------------
    local ESPBoxLeft  = Tabs.ESP:AddLeftGroupbox("Highlight ESP (3D)")
    local ESPBoxRight = Tabs.ESP:AddRightGroupbox("2D ESP (Drawing)")

    local function getESPColorForPlayer(plr)
        if plr.TeamColor then
            local color = plr.TeamColor.Color
            if typeof(color) == "Color3" then
                return color
            end
        end
        return Color3.fromRGB(255, 255, 255)
    end

    local function shouldHighlight(plr)
        if plr == LocalPlayer then
            return false
        end
        return true
    end

    -- Highlight ESP
    local HighlightState = {
        Enabled = false,
        TeamCheck = true,
        FillTransparency = 0.75
    }

    local highlightFolder = Instance.new("Folder")
    highlightFolder.Name = "Obsidian_HighlightESP"
    highlightFolder.Parent = workspace

    local playerHighlight = {}

    local function updateHighlightSettings(h, plr)
        if not h then
            return
        end
        h.FillColor = getESPColorForPlayer(plr)
        h.OutlineColor = Color3.fromRGB(0, 0, 0)
        h.FillTransparency = HighlightState.FillTransparency
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    end

    local function highlightShouldDraw(plr)
        if plr == LocalPlayer then
            return false
        end
        if HighlightState.TeamCheck and LocalPlayer and LocalPlayer.Team ~= nil then
            if plr.Team == LocalPlayer.Team then
                return false
            end
        end
        return true
    end

    local function removeHighlightForPlayer(plr)
        local h = playerHighlight[plr]
        if h then
            playerHighlight[plr] = nil
            if h.Parent then
                h:Destroy()
            end
        end
    end

    local function createHighlightForPlayer(plr)
        if not HighlightState.Enabled then
            return
        end
        if not highlightShouldDraw(plr) then
            removeHighlightForPlayer(plr)
            return
        end
        if playerHighlight[plr] then
            return
        end

        local char = plr.Character
        if not char then
            return
        end

        local h = Instance.new("Highlight")
        h.Adornee = char
        h.Parent = highlightFolder

        updateHighlightSettings(h, plr)

        playerHighlight[plr] = h
    end

    local function refreshAllHighlights()
        if not HighlightState.Enabled then
            for plr, h in pairs(playerHighlight) do
                if h.Parent then
                    h:Destroy()
                end
                playerHighlight[plr] = nil
            end
            return
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                createHighlightForPlayer(plr)
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            plr.CharacterAdded:Connect(function()
                if HighlightState.Enabled then
                    task.wait(0.2)
                    createHighlightForPlayer(plr)
                end
            end)

            plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
                local h = playerHighlight[plr]
                if h then
                    updateHighlightSettings(h, plr)
                end
            end)
        end
    end

    Players.PlayerAdded:Connect(function(plr)
        if plr == LocalPlayer then
            return
        end

        plr.CharacterAdded:Connect(function()
            if HighlightState.Enabled then
                task.wait(0.2)
                createHighlightForPlayer(plr)
            end
        end)

        plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
            local h = playerHighlight[plr]
            if h then
                updateHighlightSettings(h, plr)
            end
        end)
    end)

    Players.PlayerRemoving:Connect(function(plr)
        removeHighlightForPlayer(plr)
    end)

    ESPBoxLeft:AddToggle("ESP_Highlight_Toggle", {
        Text = "Enable Highlight ESP",
        Default = false,
        Callback = function(value)
            HighlightState.Enabled = value
            refreshAllHighlights()
        end
    })

    ESPBoxLeft:AddToggle("ESP_Highlight_TeamCheck", {
        Text = "Team Check",
        Default = true,
        Callback = function(value)
            HighlightState.TeamCheck = value
            refreshAllHighlights()
        end
    })

    ESPBoxLeft:AddSlider("ESP_Highlight_FillTransparency", {
        Text = "Fill Transparency",
        Default = 75,
        Min = 0,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            HighlightState.FillTransparency = math.clamp(value / 100, 0, 1)
            for plr, h in pairs(playerHighlight) do
                updateHighlightSettings(h, plr)
            end
        end
    })

    -- 2D ESP (Drawing)
    local drawingNew
    pcall(function()
        if type(Drawing) == "table" and type(Drawing.new) == "function" then
            drawingNew = Drawing.new
        elseif type(Drawing) == "function" then
            drawingNew = Drawing
        end
    end)

    local drawingAvailable = drawingNew ~= nil

    local DrawingState = {
        Enabled = false,
        ShowBox = true,
        ShowCorner = false,
        ShowTracer = true,
        ShowName = true
    }

    local drawingESP = {}

    local function removeDrawingForPlayer(plr)
        local holder = drawingESP[plr]
        if holder then
            drawingESP[plr] = nil
            for _, obj in pairs(holder) do
                if typeof(obj) == "table" and obj.Remove then
                    pcall(function() obj:Remove() end)
                end
            end
        end
    end

    local function getOrCreateDrawingForPlayer(plr)
        if not drawingAvailable then
            return nil
        end

        local holder = drawingESP[plr]
        if holder then
            return holder
        end

        holder = {}

        holder.Box = drawingNew("Square")
        holder.Box.Thickness = 1
        holder.Box.Filled = false
        holder.Box.Visible = false

        holder.Tracer = drawingNew("Line")
        holder.Tracer.Thickness = 1
        holder.Tracer.Visible = false

        holder.Name = drawingNew("Text")
        holder.Name.Size = 13
        holder.Name.Center = true
        holder.Name.Outline = true
        holder.Name.Visible = false

        holder.Corners = {}
        for i = 1, 8 do
            local line = drawingNew("Line")
            line.Thickness = 1
            line.Visible = false
            holder.Corners[i] = line
        end

        drawingESP[plr] = holder
        return holder
    end

    local function hideAllDrawing()
        for _, holder in pairs(drawingESP) do
            if holder.Box then holder.Box.Visible = false end
            if holder.Tracer then holder.Tracer.Visible = false end
            if holder.Name then holder.Name.Visible = false end
            if holder.Corners then
                for _, line in ipairs(holder.Corners) do
                    line.Visible = false
                end
            end
        end
    end

    if not drawingAvailable then
        ESPBoxRight:AddLabel("Drawing API not available\nBox/Corner/Tracer ESP disabled", true)
    else
        ESPBoxRight:AddToggle("ESP2D_Enable", {
            Text = "Enable 2D ESP (Drawing)",
            Default = false,
            Callback = function(value)
                DrawingState.Enabled = value
                if not value then
                    hideAllDrawing()
                end
            end
        })

        ESPBoxRight:AddToggle("ESP2D_Box", {
            Text = "Box",
            Default = true,
            Callback = function(value)
                DrawingState.ShowBox = value
            end
        })

        ESPBoxRight:AddToggle("ESP2D_Corner", {
            Text = "Corner",
            Default = false,
            Callback = function(value)
                DrawingState.ShowCorner = value
            end
        })

        ESPBoxRight:AddToggle("ESP2D_Tracer", {
            Text = "Tracer",
            Default = true,
            Callback = function(value)
                DrawingState.ShowTracer = value
            end
        })

        ESPBoxRight:AddToggle("ESP2D_Name", {
            Text = "Name",
            Default = true,
            Callback = function(value)
                DrawingState.ShowName = value
            end
        })
    end

    if drawingAvailable then
        RunService.RenderStepped:Connect(function()
            if not DrawingState.Enabled then
                hideAllDrawing()
                return
            end

            local cam = workspace.CurrentCamera
            if not cam then
                hideAllDrawing()
                return
            end

            local viewport = cam.ViewportSize
            local screenCenter = Vector2.new(viewport.X / 2, viewport.Y)

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and shouldHighlight(plr) then
                    local char = plr.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")

                    if char and root then
                        local pos, onScreen = cam:WorldToViewportPoint(root.Position)
                        if onScreen and pos.Z > 0 then
                            local holder = getOrCreateDrawingForPlayer(plr)
                            if not holder then
                                continue
                            end

                            local distance = (root.Position - cam.CFrame.Position).Magnitude
                            local sizeFactor = math.clamp(2000 / distance, 30, 250)
                            local boxW = sizeFactor * 0.6
                            local boxH = sizeFactor

                            local boxX = pos.X - boxW / 2
                            local boxY = pos.Y - boxH / 2

                            local color = getESPColorForPlayer(plr)

                            if DrawingState.ShowBox then
                                holder.Box.Color = color
                                holder.Box.Size = Vector2.new(boxW, boxH)
                                holder.Box.Position = Vector2.new(boxX, boxY)
                                holder.Box.Visible = true
                            else
                                holder.Box.Visible = false
                            end

                            if DrawingState.ShowTracer then
                                holder.Tracer.Color = color
                                holder.Tracer.From = screenCenter
                                holder.Tracer.To = Vector2.new(pos.X, pos.Y + boxH / 2)
                                holder.Tracer.Visible = true
                            else
                                holder.Tracer.Visible = false
                            end

                            if DrawingState.ShowName then
                                holder.Name.Color = color
                                holder.Name.Text = plr.Name
                                holder.Name.Position = Vector2.new(pos.X, boxY - 14)
                                holder.Name.Visible = true
                            else
                                holder.Name.Visible = false
                            end

                            if DrawingState.ShowCorner then
                                local cornerLen = math.floor(boxH / 4)

                                local corners = holder.Corners
                                local lt = Vector2.new(boxX, boxY)
                                local rt = Vector2.new(boxX + boxW, boxY)
                                local lb = Vector2.new(boxX, boxY + boxH)
                                local rb = Vector2.new(boxX + boxW, boxY + boxH)

                                corners[1].Color = color
                                corners[1].From = lt
                                corners[1].To = Vector2.new(lt.X + cornerLen, lt.Y)
                                corners[1].Visible = true

                                corners[2].Color = color
                                corners[2].From = lt
                                corners[2].To = Vector2.new(lt.X, lt.Y + cornerLen)
                                corners[2].Visible = true

                                corners[3].Color = color
                                corners[3].From = rt
                                corners[3].To = Vector2.new(rt.X - cornerLen, rt.Y)
                                corners[3].Visible = true

                                corners[4].Color = color
                                corners[4].From = rt
                                corners[4].To = Vector2.new(rt.X, rt.Y + cornerLen)
                                corners[4].Visible = true

                                corners[5].Color = color
                                corners[5].From = lb
                                corners[5].To = Vector2.new(lb.X + cornerLen, lb.Y)
                                corners[5].Visible = true

                                corners[6].Color = color
                                corners[6].From = lb
                                corners[6].To = Vector2.new(lb.X, lb.Y - cornerLen)
                                corners[6].Visible = true

                                corners[7].Color = color
                                corners[7].From = rb
                                corners[7].To = Vector2.new(rb.X - cornerLen, rb.Y)
                                corners[7].Visible = true

                                corners[8].Color = color
                                corners[8].From = rb
                                corners[8].To = Vector2.new(rb.X, rb.Y - cornerLen)
                                corners[8].Visible = true
                            else
                                local holder = drawingESP[plr]
                                if holder and holder.Corners then
                                    for _, line in ipairs(holder.Corners) do
                                        line.Visible = false
                                    end
                                end
                            end
                        else
                            removeDrawingForPlayer(plr)
                        end
                    else
                        removeDrawingForPlayer(plr)
                    end
                else
                    removeDrawingForPlayer(plr)
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- TAB 4: UI / Theme / Config
    ----------------------------------------------------------------
    local UIBoxLeft  = Tabs.UI:AddLeftGroupbox("UI Controls")
    local UIBoxRight = Tabs.UI:AddRightGroupbox("Theme / Config")

    UIBoxLeft:AddButton("Toggle UI", function()
        if Library and type(Library.Toggle) == "function" then
            Library:Toggle()
        end
    end)

    UIBoxLeft:AddButton("Unload UI (close hub)", function()
        if Library and type(Library.Unload) == "function" then
            Library:Unload()
        end
    end)

    UIBoxLeft:AddLabel("If UI disappears, re-execute script.", true)

    if SaveManager and type(SaveManager.BuildConfigSection) == "function" then
        SaveManager:BuildConfigSection(Tabs.UI)
    end

    if ThemeManager and type(ThemeManager.ApplyToTab) == "function" then
        ThemeManager:ApplyToTab(Tabs.UI)
    end

    if SaveManager and type(SaveManager.LoadAutoloadConfig) == "function" then
        SaveManager:LoadAutoloadConfig()
    end
end
