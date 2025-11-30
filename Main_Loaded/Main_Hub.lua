-- MainHub.lua
-- ต้อง return function(Exec, keydata, keycheck)

return function(Exec, keydata, keycheck)
    ----------------------------------------------------------------
    -- Basic guards
    ----------------------------------------------------------------
    if keycheck ~= "success" then
        -- กันคนโหลด MainHub ตรง ๆ โดยไม่ผ่าน Key UI
        return
    end

    keydata = keydata or {}

    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local StatsService = game:GetService("Stats")

    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- Helpers: character / humanoid / root
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
    -- Config: URLs ของ Obsidian Library
    ----------------------------------------------------------------
    local LIBRARY_URL     = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/Library.lua",
    local THEME_URL       = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/addons/ThemeManager.lua",
    local SAVE_URL        = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/addons/SaveManager.lua",

    ----------------------------------------------------------------
    -- Load Obsidian Library + ThemeManager + SaveManager
    ----------------------------------------------------------------
    local Library = loadstring(Exec.HttpGet(LIBRARY_URL))()
    local ThemeManager = loadstring(Exec.HttpGet(THEME_URL))()
    local SaveManager  = loadstring(Exec.HttpGet(SAVE_URL))()

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
        Status = Window:AddTab("Status"),  -- Tab1
        Player = Window:AddTab("Player"),  -- Tab2
        ESP    = Window:AddTab("ESP"),     -- Tab3
        UI     = Window:AddTab("UI")       -- Tab4
    }

    ----------------------------------------------------------------
    -- Helpers: label
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
    -- TAB 1: Status (Key / Server / Credits)
    ----------------------------------------------------------------
    local StatusKeyBox     = Tabs.Status:AddLeftGroupbox("Key & User")
    local StatusCreditsBox = Tabs.Status:AddLeftGroupbox("Credits")
    local StatusServerBox  = Tabs.Status:AddRightGroupbox("Server & Performance")

    -- Key & User
    local keyMasked = maskKey(keydata.key or "N/A")
    local role = keydata.role or "N/A"

    local keyLabel      = StatusKeyBox:AddLabel("", true)
    local roleLabel     = StatusKeyBox:AddLabel("", true)
    local hwidLabel     = StatusKeyBox:AddLabel("", true)
    local userLabel     = StatusKeyBox:AddLabel("", true)

    setRichLabel(keyLabel, "<b>Key</b>: " .. keyMasked)
    setRichLabel(roleLabel, "<b>Role</b>: " .. role)
    setRichLabel(hwidLabel, "<b>HWID Hash</b>: " .. shortHash(keydata.hwid_hash))
    setRichLabel(userLabel, "<b>User</b>: " .. (LocalPlayer and LocalPlayer.Name or "N/A"))

    StatusKeyBox:AddDivider()

    -- Credits
    local creditLines = {
        "<b>Obsidian Universal Hub</b>",
        "Developer: <font color=\"#7dcfff\">YourName / Boom</font>",
        "Library: <font color=\"#b58cff\">Obsidian UI</font>",
        "Discord: <font color=\"#55ff99\">https://discord.gg/yourdiscord</font>",
        "",
        "<font color=\"#aaaaaa\">Please do not leak / resell.</font>"
    }

    local creditLabel = StatusCreditsBox:AddLabel(table.concat(creditLines, "\n"), true)
    if creditLabel and creditLabel.TextLabel then
        creditLabel.TextLabel.RichText = true
    end

    -- Server & Performance
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

    -- FPS / Ping update ทุก ~1 วิ
    local frameCount = 0
    local timeAcc = 0

    RunService.RenderStepped:Connect(function(dt)
        frameCount = frameCount + 1
        timeAcc = timeAcc + dt

        if timeAcc >= 1 then
            local fps = math.floor(frameCount / timeAcc + 0.5)
            frameCount = 0
            timeAcc = 0

            -- Ping
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
        end
    end)

    ----------------------------------------------------------------
    -- TAB 2: Player (WalkSpeed / Jump / Fly / NoClip / Inf Jump)
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
            if not ok then
                -- ignore errors
            end
        end
    end

    -- NoClip tracking
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

    -- Infinite Jump
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

    -- Fly
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
            -- WalkSpeed
            if MovementState.WalkSpeedEnabled then
                hum.WalkSpeed = MovementState.WalkSpeedValue
            elseif DefaultValues.WalkSpeed then
                hum.WalkSpeed = DefaultValues.WalkSpeed
            end

            -- JumpPower / JumpHeight
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
            if not ok then
                -- ignore errors
            end
        end

        -- NoClip
        if MovementState.NoClip then
            updateNoClip()
        else
            disableNoClip()
        end

        -- Fly
        if MovementState.FlyEnabled then
            updateFly()
        else
            resetFlyBody()
        end
    end)

    -- Key input for Fly
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

    -- UI controls for movement
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
    -- TAB 3: ESP (Highlight ผู้เล่น)
    ----------------------------------------------------------------
    local ESPBox = Tabs.ESP:AddLeftGroupbox("Player ESP")

    local ESPState = {
        Enabled = false,
        TeamCheck = true,
        FillTransparency = 0.75
    }

    local espFolder = Instance.new("Folder")
    espFolder.Name = "Obsidian_ESP"
    espFolder.Parent = workspace

    local playerESP = {}

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
        if ESPState.TeamCheck and LocalPlayer and LocalPlayer.Team ~= nil then
            if plr.Team == LocalPlayer.Team then
                return false
            end
        end
        return true
    end

    local function removeESPForPlayer(plr)
        local h = playerESP[plr]
        if h then
            playerESP[plr] = nil
            if h.Parent then
                h:Destroy()
            end
        end
    end

    local function updateHighlightSettings(h, plr)
        if not h then
            return
        end
        h.FillColor = getESPColorForPlayer(plr)
        h.OutlineColor = Color3.fromRGB(0, 0, 0)
        h.FillTransparency = ESPState.FillTransparency
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    end

    local function createESPForPlayer(plr)
        if not ESPState.Enabled then
            return
        end
        if not shouldHighlight(plr) then
            removeESPForPlayer(plr)
            return
        end
        if playerESP[plr] then
            return
        end

        local char = plr.Character
        if not char then
            return
        end

        local highlight = Instance.new("Highlight")
        highlight.Adornee = char
        highlight.Parent = espFolder

        updateHighlightSettings(highlight, plr)

        playerESP[plr] = highlight
    end

    local function refreshAllESP()
        if not ESPState.Enabled then
            for plr, h in pairs(playerESP) do
                if h.Parent then
                    h:Destroy()
                end
                playerESP[plr] = nil
            end
            return
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                createESPForPlayer(plr)
            end
        end
    end

    -- Hook players
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            plr.CharacterAdded:Connect(function()
                if ESPState.Enabled then
                    task.wait(0.2)
                    createESPForPlayer(plr)
                end
            end)

            plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
                local h = playerESP[plr]
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
            if ESPState.Enabled then
                task.wait(0.2)
                createESPForPlayer(plr)
            end
        end)

        plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
            local h = playerESP[plr]
            if h then
                updateHighlightSettings(h, plr)
            end
        end)
    end)

    Players.PlayerRemoving:Connect(function(plr)
        removeESPForPlayer(plr)
    end)

    -- UI controls for ESP
    ESPBox:AddToggle("ESP_Player_Toggle", {
        Text = "Enable Player ESP",
        Default = false,
        Callback = function(value)
            ESPState.Enabled = value
            refreshAllESP()
        end
    })

    ESPBox:AddToggle("ESP_TeamCheck_Toggle", {
        Text = "Team Check",
        Default = true,
        Callback = function(value)
            ESPState.TeamCheck = value
            refreshAllESP()
        end
    })

    ESPBox:AddSlider("ESP_FillTransparency", {
        Text = "Fill Transparency",
        Default = 75,
        Min = 0,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            ESPState.FillTransparency = math.clamp(value / 100, 0, 1)
            for plr, h in pairs(playerESP) do
                updateHighlightSettings(h, plr)
            end
        end
    })

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
