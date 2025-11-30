-- MainHub.lua
-- Must return function(Exec, keydata, keycheck)

return function(Exec, keydata, keycheck)
    -- basic guard
    if keycheck ~= "success" then
        return
    end

    keydata = keydata or {}

    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Stats = game:GetService("Stats")

    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- Helper: character / humanoid / root
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

    local function getRoot()
        local char = getCharacter()
        if not char then
            return nil
        end
        return char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- Obsidian URLs (change to your repo)
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- Load Obsidian
    ----------------------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

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
    -- Small helpers
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

    -- Key & user info
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
    local creditText = table.concat({
        "<b>Obsidian Universal Hub</b>",
        "Developer: <font color=\"#7dcfff\">YourName / Boom</font>",
        "Library: <font color=\"#b58cff\">Obsidian UI</font>",
        "Discord: <font color=\"#55ff99\">https://discord.gg/yourdiscord</font>",
        "",
        "<font color=\"#aaaaaa\">Please do not leak / resell.</font>"
    }, "\n")

    local creditLabel = StatusCreditsBox:AddLabel(creditText, true)
    if creditLabel and creditLabel.TextLabel then
        creditLabel.TextLabel.RichText = true
    end

    -- Server & realtime stats
    local placeId = game.PlaceId
    local jobId   = game.JobId

    local serverPlaceLabel = StatusServerBox:AddLabel("", true)
    local serverJobLabel   = StatusServerBox:AddLabel("", true)
    local playerCountLabel = StatusServerBox:AddLabel("", true)
    local pingLabel        = StatusServerBox:AddLabel("", true)
    local fpsLabel         = StatusServerBox:AddLabel("", true)
    local hpLabel          = StatusServerBox:AddLabel("", true)
    local posLabel         = StatusServerBox:AddLabel("", true)

    setRichLabel(serverPlaceLabel, "<b>PlaceId</b>: " .. tostring(placeId))
    setRichLabel(serverJobLabel, "<b>JobId</b>: " .. tostring(jobId))

    local function updatePlayerCount()
        local count = #Players:GetPlayers()
        setRichLabel(playerCountLabel, "<b>Players</b>: " .. tostring(count))
    end

    updatePlayerCount()
    Players.PlayerAdded:Connect(updatePlayerCount)
    Players.PlayerRemoving:Connect(updatePlayerCount)

    -- realtime ping/fps/hp/pos
    local frameCount = 0
    local timeAcc = 0
    local statTimer = 0

    RunService.RenderStepped:Connect(function(dt)
        frameCount += 1
        timeAcc += dt
        statTimer += dt

        if timeAcc >= 1 then
            local fps = math.floor(frameCount / timeAcc + 0.5)
            frameCount = 0
            timeAcc = 0

            local pingText = "N/A"
            local okPing, pingValue = pcall(function()
                local pingStat = Stats.Network.ServerStatsItem["Data Ping"]
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

        if statTimer >= 0.2 then
            statTimer = 0

            local hum = getHumanoid()
            if hum then
                local hp = math.floor(hum.Health + 0.5)
                local maxHp = math.floor(hum.MaxHealth + 0.5)
                setRichLabel(hpLabel, "<b>HP</b>: " .. hp .. " / " .. maxHp)
            else
                setRichLabel(hpLabel, "<b>HP</b>: N/A")
            end

            local root = getRoot()
            if root then
                local p = root.Position
                setRichLabel(
                    posLabel,
                    string.format("<b>Position</b>: %.1f, %.1f, %.1f", p.X, p.Y, p.Z)
                )
            else
                setRichLabel(posLabel, "<b>Position</b>: N/A")
            end
        end
    end)

    ----------------------------------------------------------------
    -- TAB 2: Player
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
                -- ignore
            end
        end
    end

    -- NoClip
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

        local root = getRoot()
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

    -- realtime apply movement
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
            if not ok then
                -- ignore
            end
        end

        if MovementState.NoClip then
            updateNoClip()
        else
            disableNoClip()
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

        local kc = input.KeyCode
        if kc == Enum.KeyCode.W then
            flyKeys.W = true
        elseif kc == Enum.KeyCode.A then
            flyKeys.A = true
        elseif kc == Enum.KeyCode.S then
            flyKeys.S = true
        elseif kc == Enum.KeyCode.D then
            flyKeys.D = true
        elseif kc == Enum.KeyCode.Space then
            flyKeys.Space = true
        elseif kc == Enum.KeyCode.LeftShift then
            flyKeys.LeftShift = true
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gp)
        if gp then
            return
        end

        local kc = input.KeyCode
        if kc == Enum.KeyCode.W then
            flyKeys.W = false
        elseif kc == Enum.KeyCode.A then
            flyKeys.A = false
        elseif kc == Enum.KeyCode.S then
            flyKeys.S = false
        elseif kc == Enum.KeyCode.D then
            flyKeys.D = false
        elseif kc == Enum.KeyCode.Space then
            flyKeys.Space = false
        elseif kc == Enum.KeyCode.LeftShift then
            flyKeys.LeftShift = false
        end
    end)

    -- UI for movement
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
    -- TAB 3: ESP
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

