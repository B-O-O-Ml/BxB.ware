--[[
    BxB.ware | Universal Premium Hub (Full Version)
    This script is intended to be loaded by the Key UI loader.  It
    performs a two‑factor handshake using a dynamic token and then
    constructs the full interface for the premium hub.  The UI is
    built on top of the Linoria/Obsidian library with ThemeManager
    and SaveManager addons.  Each tab exposes a range of tools:
      • Info tab shows key status and system/session information.
      • Player tab provides movement tweaks and camera utilities.
      • Combat tab contains an aimbot with extensive configuration.
      • ESP tab draws visual overlays and chams with rich options.
      • Misc tab offers utilities like anti‑AFK, auto reconnect and
        server hopping.
      • Game tab loads game‑specific modules when available.
      • Settings tab hooks up theme and save managers for configs.

    To use this script you must call it through the Key UI which
    supplies the Exec abstraction, a user data table and a dynamic
    token.  The secret salt used here must match the one in the
    loader for the handshake to succeed.

    Author: BXMQZ (adapted by ChatGPT)
]]

return function(Exec, UserData, IncomingToken)
    ----------------------------------------------------------------
    -- 1. Security Handshake (Double‑layer check)
    ----------------------------------------------------------------
    local secretSalt = "BxB_SUPER_SECRET_SALT_CHANGE_THIS" -- MUST match Key_UI
    local datePart   = os.date("%Y%m%d")
    local expectedToken = secretSalt .. "_" .. datePart
    if IncomingToken ~= expectedToken then
        warn("[BxB Security] Invalid or expired security token!")
        local Players = game:GetService("Players")
        local lp = Players.LocalPlayer
        if lp then
            lp:Kick("Security Breach: Invalid Token (Please re‑login via Key UI)")
        end
        return
    end

    ----------------------------------------------------------------
    -- 2. Services & Variables
    ----------------------------------------------------------------
    local Players          = game:GetService("Players")
    local RunService       = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace        = game:GetService("Workspace")
    local Lighting         = game:GetService("Lighting")
    local TeleportService  = game:GetService("TeleportService")
    local HttpService      = game:GetService("HttpService")
    local Stats            = game:GetService("Stats")

    local Camera       = Workspace.CurrentCamera
    local LocalPlayer  = Players.LocalPlayer
    local Mouse        = LocalPlayer:GetMouse()

    -- guarantee Exec is available and has HttpGet
    local function safeHttpGet(url)
        local ok, result = pcall(function()
            if Exec and type(Exec.HttpGet) == "function" then
                return Exec.HttpGet(url)
            else
                return game:HttpGet(url)
            end
        end)
        if not ok then
            warn("[BxB] HttpGet failed: " .. tostring(result))
            return nil
        end
        return result
    end

    ----------------------------------------------------------------
    -- 3. Load Library / ThemeManager / SaveManager
    ----------------------------------------------------------------
    -- Config table pointing to the remote assets; adjust to your repo
    local Config = {
        LIB_URL    = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua",
        THEME_URL  = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/ThemeManager.lua",
        SAVE_URL   = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/SaveManager.lua",
        FolderName = "BxB_Ware/Premium"
    }
    
    -- Fetch and load library
    local librarySrc = safeHttpGet(Config.LIB_URL)
    if not librarySrc then return end
    local libChunk, libErr = loadstring(librarySrc)
    if not libChunk then
        warn("[BxB] Failed to compile Library: " .. tostring(libErr))
        return
    end
    local Library = libChunk()
    if not Library then
        warn("[BxB] Library returned nil")
        return
    end

    -- Fetch and load theme / save managers
    local ThemeManager, SaveManager
    do
        local themeSrc = safeHttpGet(Config.THEME_URL)
        if themeSrc then
            local ok, res = pcall(loadstring, themeSrc)
            if ok and type(res) == "table" then
                ThemeManager = res
                if ThemeManager.SetLibrary then
                    ThemeManager:SetLibrary(Library)
                end
            else
                warn("[BxB] Failed to load ThemeManager")
            end
        end
        local saveSrc = safeHttpGet(Config.SAVE_URL)
        if saveSrc then
            local ok2, res2 = pcall(loadstring, saveSrc)
            if ok2 and type(res2) == "table" then
                SaveManager = res2
                if SaveManager.SetLibrary then
                    SaveManager:SetLibrary(Library)
                end
                if SaveManager.SetFolder then
                    SaveManager:SetFolder(Config.FolderName)
                end
            else
                warn("[BxB] Failed to load SaveManager")
            end
        end
    end

    ----------------------------------------------------------------
    -- 4. Window & Tabs Construction
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title      = "",
        Icon       = 84528813312016,
        Size       = UDim2.fromOffset(720, 600),
        Center     = true,
        AutoShow   = true,
        Resizable  = true,
        Compact    = true
    })
    
    local Tabs = {
        Info     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "database",   Description = "Key Status / Info"}),
        Player   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "users",     Description = "Player Tool"}),
        Combat   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "eye",       Description = "Combat Client"}),
        ESP      = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "crosshair", Description = "ESP Client"}),
        Misc     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "crosshair", Description = "Misc Client"}),
        Game     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "joystick",  Description = "Game Module"}),
        Settings = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "settings",  Description = "UI/UX Settings"}),
    }

    ----------------------------------------------------------------
    -- 5. Info Tab: Key & System Information
    ----------------------------------------------------------------
    -- Left side: Key Information
    local Info_KeyBox = Tabs.Info:AddLeftGroupbox("Key Status")
    local function maskKey(k)
        if not k or #k < 8 then return k or "Unknown" end
        return k:sub(1, 4) .. string.rep("*", #k - 8) .. k:sub(-4)
    end
    Info_KeyBox:AddLabel("Key: " .. maskKey(UserData.key))
    Info_KeyBox:AddLabel("Status: " .. tostring(UserData.status or "active"))
    Info_KeyBox:AddLabel("Role: " .. tostring(UserData.role or "user"))
    Info_KeyBox:AddLabel("Owner: " .. tostring(UserData.owner or "Unknown"))
    Info_KeyBox:AddLabel("Note: " .. tostring(UserData.note or "None"))
    Info_KeyBox:AddLabel("Timestamp: " .. tostring(UserData.timestamp or "Unknown"))
    local ExpireLabel = Info_KeyBox:AddLabel("Expire: Calculating...")

    -- Right side: System / Session Information
    local Info_SysBox = Tabs.Info:AddRightGroupbox("System / Session")
    local GameIdLabel    = Info_SysBox:AddLabel('Game ID: ' .. tostring(game.PlaceId))
    local UserLabel      = Info_SysBox:AddLabel('Username: ' .. tostring(LocalPlayer.Name))
    local DisplayLabel   = Info_SysBox:AddLabel('Display Name: ' .. tostring(LocalPlayer.DisplayName))
    local ExecLabel      = Info_SysBox:AddLabel('Executor: ' .. (identifyexecutor and identifyexecutor() or "Unknown"))
    local PingLabel      = Info_SysBox:AddLabel('Ping: -- ms')
    local FpsLabel       = Info_SysBox:AddLabel('FPS: --')
    local MemLabel       = Info_SysBox:AddLabel('Memory: -- MB')
    local TimeLabel      = Info_SysBox:AddLabel('Time: ' .. os.date("%H:%M:%S"))

    -- Update loop: expire countdown, ping/fps/mem/time
    task.spawn(function()
        local lastTime = os.clock()
        local frameCount = 0
        while true do
            -- Expire countdown
            if UserData.expire then
                local diff = UserData.expire - os.time()
                if diff > 0 then
                    local d = math.floor(diff / 86400)
                    local h = math.floor((diff % 86400) / 3600)
                    local m = math.floor((diff % 3600) / 60)
                    local s = math.floor(diff % 60)
                    ExpireLabel:SetText(string.format('Expire: %dd %02dh %02dm %02ds', d, h, m, s))
                else
                    ExpireLabel:SetText('Expire: Expired')
                end
            else
                ExpireLabel:SetText('Expire: Lifetime')
            end
            -- Update system stats
            frameCount = frameCount + 1
            local now = os.clock()
            if now - lastTime >= 1 then
                local fps = frameCount / (now - lastTime)
                frameCount = 0
                lastTime = now
                FpsLabel:SetText('FPS: ' .. math.floor(fps))
                -- ping via Stats or network ping; fallback to 0 if unknown
                local networkStats = Stats and Stats:FindFirstChild("Network" )
                local incomingPing = networkStats and networkStats:FindFirstChild("IncomingReplicationLag")
                local ping = incomingPing and math.floor(incomingPing.Value * 1000) or 0
                PingLabel:SetText('Ping: ' .. tostring(ping) .. ' ms')
                -- memory via collectgarbage
                local kb = collectgarbage("count")
                MemLabel:SetText('Memory: ' .. string.format('%.1f MB', kb / 1024))
                -- time
                TimeLabel:SetText('Time: ' .. os.date("%H:%M:%S"))
            end
            task.wait() -- yields for one heartbeat
        end
    end)

    ----------------------------------------------------------------
    -- 6. Player Tab: Movement & Utility Tools
    ----------------------------------------------------------------
    local Player_MoveBox = Tabs.Player:AddLeftGroupbox('Movement')
    local Player_ToolBox = Tabs.Player:AddRightGroupbox('Tools')

    -- Walk Speed
    Player_MoveBox:AddSlider('Player_WalkSpeed', {
        Text    = 'Walk Speed',
        Default = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid") and LocalPlayer.Character.Humanoid.WalkSpeed or 16,
        Min     = 16,
        Max     = 500,
        Rounding = 0,
        Callback = function(v)
            if LocalPlayer.Character then
                local hum = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
                if hum then hum.WalkSpeed = v end
            end
        end
    })

    -- Jump Power
    Player_MoveBox:AddSlider('Player_JumpPower', {
        Text    = 'Jump Power',
        Default = 50,
        Min     = 50,
        Max     = 500,
        Rounding = 0,
        Callback = function(v)
            if LocalPlayer.Character then
                local hum = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
                if hum then hum.JumpPower = v end
            end
        end
    })

    -- Infinite Jump
    local InfJumpToggle = Player_MoveBox:AddToggle('Player_InfJump', {
        Text    = 'Infinite Jump',
        Default = false
    })
    -- Bind infinite jump behaviour
    UserInputService.JumpRequest:Connect(function()
        if InfJumpToggle.Value and LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    -- Fly Mode implementation
    local FlyToggle = Player_MoveBox:AddToggle('Player_Fly', { Text = 'Fly Mode', Default = false })
    local flyBody -- BodyVelocity holder
    local flyConnection
    local flySpeed = 50
    local function startFly()
        if flyBody then return end
        local character = LocalPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = character.HumanoidRootPart
        flyBody = Instance.new("BodyVelocity")
        flyBody.Name = "BxB_FlyVelocity"
        flyBody.MaxForce = Vector3.new(1e5,1e5,1e5)
        flyBody.Velocity = Vector3.new()
        flyBody.Parent = hrp
        flyConnection = RunService.Heartbeat:Connect(function()
            if not FlyToggle.Value then return end
            local moveVector = Vector3.new()
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += Camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector -= Camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector -= Camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += Camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector += Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector -= Vector3.new(0,1,0) end
            if moveVector.Magnitude > 0 then
                moveVector = moveVector.Unit * flySpeed
            end
                flyBody.Velocity = moveVector
            end)
    end
    local function stopFly()
        if flyConnection then flyConnection:Disconnect() flyConnection = nil end
        if flyBody then flyBody:Destroy() flyBody = nil end
    end
    FlyToggle:OnChanged(function(v)
        if v then
            startFly()
        else
            stopFly()
        end
    end)

    -- NoClip
    local NoclipToggle = Player_MoveBox:AddToggle('Player_Noclip', { Text = 'Noclip', Default = false })
    local noclipConn
    NoclipToggle:OnChanged(function(v)
        if v then
            noclipConn = RunService.Stepped:Connect(function()
                if LocalPlayer.Character then
                    for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        else
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end
            -- restore collision if needed
            if LocalPlayer.Character then
                for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
                end
            end
        end
    end)

    -- Tools: Teleport, Free Camera, FOV, Spectate
    -- Teleport to Player
    local tpInput = Player_ToolBox:AddInput('Player_TeleportTo', {
        Default = '',
        Placeholder = 'Username or partial',
        Text = 'Teleport To',
        Finished = true
    })
    Player_ToolBox:AddButton('Teleport', function()
        local targetName = tpInput.Value
        if targetName and targetName ~= '' then
            for _, plr in pairs(Players:GetPlayers()) do
                if string.find(plr.Name:lower(), targetName:lower()) == 1 then
                    if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        LocalPlayer.Character.HumanoidRootPart.CFrame = plr.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
                    end
                    return
                end
            end
            Library:Notify("Player not found", 3)
        end
    end)

    -- Free Camera
    local FreeCamToggle = Player_ToolBox:AddToggle('Player_FreeCam', { Text = 'Free Camera', Default = false })
    local freecamSpeed = 50
    local freecamConn
    local function freecamUpdate(dt)
        if not FreeCamToggle.Value then return end
        local move = Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += Vector3.new(0,0,-1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move += Vector3.new(0,0,1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move += Vector3.new(-1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += Vector3.new(1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move += Vector3.new(0,-1,0) end
        if move.Magnitude > 0 then move = move.Unit end
        local delta = freecamSpeed * dt
        local camCF = Camera.CFrame
        local newPos = camCF.Position + (camCF.LookVector * move.Z + camCF.RightVector * move.X + Vector3.new(0,1,0) * move.Y) * delta
        -- preserve rotation
        local rx, ry, rz = camCF:ToEulerAnglesXYZ()
        local newCF = CFrame.new(newPos) * CFrame.Angles(rx, ry, rz)
        Camera.CFrame = newCF
    end
    FreeCamToggle:OnChanged(function(v)
        if v then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.AutoRotate = false
            end
            Camera.CameraType = Enum.CameraType.Scriptable
            if not freecamConn then
                freecamConn = RunService.RenderStepped:Connect(freecamUpdate)
            end
        else
            if freecamConn then freecamConn:Disconnect() freecamConn = nil end
            Camera.CameraType = Enum.CameraType.Custom
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.AutoRotate = true
            end
            -- reset camera to character
            Camera.CameraSubject = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        end
    end)

    -- FOV slider
    Player_ToolBox:AddSlider('Player_FOV', {
        Text    = 'Field of View',
        Default = Camera.FieldOfView,
        Min     = 40,
        Max     = 120,
        Rounding = 0,
        Callback = function(v)
            Camera.FieldOfView = v
        end
    })

    -- Spectate other player
    local spectateDropdown = Player_ToolBox:AddDropdown('Player_SpectateDropdown', {
        Values = {},
        Default = nil,
        Multi = false,
        Text = 'Spectate Player'
    })
    local function updateSpectateList()
        local list = {}
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then table.insert(list, plr.Name) end
        end
        spectateDropdown.Values = list
        spectateDropdown:SetValues(list)
    end
    updateSpectateList()
    Players.PlayerAdded:Connect(updateSpectateList)
    Players.PlayerRemoving:Connect(updateSpectateList)
    Player_ToolBox:AddButton('Start Spectate', function()
        local targetName = spectateDropdown.Value
        if targetName and targetName ~= '' then
            local targetPlayer = Players:FindFirstChild(targetName)
            if targetPlayer and targetPlayer.Character then
                local hum = targetPlayer.Character:FindFirstChildWhichIsA("Humanoid")
                if hum then
                    Camera.CameraSubject = hum
                    Library:Notify('Spectating ' .. targetName, 3)
                end
            end
        end
    end)
    Player_ToolBox:AddButton('Stop Spectate', function()
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid") then
            Camera.CameraSubject = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        end
        Library:Notify('Stopped Spectating', 3)
    end)

    ----------------------------------------------------------------
    -- 7. Combat Tab: Aimbot & Targeting
    ----------------------------------------------------------------
    local Combat_AimBox    = Tabs.Combat:AddLeftGroupbox('Aimbot')
    local Combat_SetBox    = Tabs.Combat:AddRightGroupbox('Settings')
    local Combat_FilterBox = Tabs.Combat:AddRightGroupbox('Target Filter')

    -- Aimbot settings table
    local AimSettings = {
        Enabled    = false,
        Mode       = 'Hold',
        Smooth     = 1,
        Predict    = 0,
        HitChance  = 100,
        RandomHit  = false,
        PartWeights = {Head=50, UpperTorso=20, Torso=20, LeftHand=5, RightHand=5, LeftLeg=0, RightLeg=0},
        TeamCheck = true,
        VisibleCheck = true,
        Whitelist  = {},
        AutoFriend = false
    }

    -- Toggle to enable aimbot
    Combat_AimBox:AddToggle('Combat_AimEnabled', {
        Text    = 'Enable Aimbot',
        Default = false,
        Callback = function(v) AimSettings.Enabled = v end
    })
    -- Aim Mode dropdown
    Combat_AimBox:AddDropdown('Combat_AimMode', {
        Values = { 'Hold', 'Auto', 'Toggle' },
        Default = 1,
        Multi = false,
        Text = 'Aim Mode',
        Callback = function(v) AimSettings.Mode = v end
    })
    -- Smoothness
    Combat_SetBox:AddSlider('Combat_Smooth', {
        Text    = 'Smoothness',
        Default = 1,
        Min     = 1,
        Max     = 20,
        Rounding = 1,
        Callback = function(v) AimSettings.Smooth = v end
    })
    -- Prediction
    Combat_SetBox:AddSlider('Combat_Predict', {
        Text    = 'Prediction',
        Default = 0,
        Min     = 0,
        Max     = 10,
        Rounding = 1,
        Callback = function(v) AimSettings.Predict = v end
    })
    -- Hit chance
    Combat_SetBox:AddSlider('Combat_HitChance', {
        Text    = 'Hit Chance (%)',
        Default = 100,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.HitChance = v end
    })
    -- Random Hit toggle
    Combat_SetBox:AddToggle('Combat_RandomHit', {
        Text = 'Random Hit Offset',
        Default = false,
        Callback = function(v) AimSettings.RandomHit = v end
    })
    -- Hit part sliders (weights)
    Combat_SetBox:AddSlider('Combat_HeadWeight', {
        Text    = 'Head Weight',
        Default = 50,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.Head = v end
    })
    Combat_SetBox:AddSlider('Combat_UpperTorsoWeight', {
        Text    = 'Upper Torso Wt',
        Default = 20,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.UpperTorso = v end
    })
    Combat_SetBox:AddSlider('Combat_TorsoWeight', {
        Text    = 'Torso Weight',
        Default = 20,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.Torso = v end
    })
    Combat_SetBox:AddSlider('Combat_LHandWeight', {
        Text    = 'Left Hand Wt',
        Default = 5,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.LeftHand = v end
    })
    Combat_SetBox:AddSlider('Combat_RHandWeight', {
        Text    = 'Right Hand Wt',
        Default = 5,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.RightHand = v end
    })
    Combat_SetBox:AddSlider('Combat_LLegWeight', {
        Text    = 'Left Leg Wt',
        Default = 0,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.LeftLeg = v end
    })
    Combat_SetBox:AddSlider('Combat_RLegWeight', {
        Text    = 'Right Leg Wt',
        Default = 0,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
        Callback = function(v) AimSettings.PartWeights.RightLeg = v end
    })
    -- Team Check and Visible Only toggles
    Combat_SetBox:AddToggle('Combat_TeamCheck', { Text = 'Team Check', Default = true, Callback = function(v) AimSettings.TeamCheck = v end })
    Combat_SetBox:AddToggle('Combat_VisibleCheck', { Text = 'Visible Check', Default = true, Callback = function(v) AimSettings.VisibleCheck = v end })

    -- Whitelist dropdown / auto friend
    local whitelistDropdown = Combat_FilterBox:AddDropdown('Combat_WhitelistDropdown', {
        Values  = {},
        Default = nil,
        Multi   = true,
        Text    = 'Whitelist Players'
    })
    local function updateWhitelistList()
        local list = {}
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then table.insert(list, plr.Name) end
        end
        whitelistDropdown.Values = list
        whitelistDropdown:SetValues(list)
    end
    updateWhitelistList()
    Players.PlayerAdded:Connect(updateWhitelistList)
    Players.PlayerRemoving:Connect(updateWhitelistList)
    whitelistDropdown:OnChanged(function(selected)
        AimSettings.Whitelist = selected or {}
    end)
    Combat_FilterBox:AddToggle('Combat_AutoFriend', { Text = 'Auto Whitelist Friends', Default = false, Callback = function(v) AimSettings.AutoFriend = v end })

    -- Aimbot logic
    local aimbotTarget
    local isToggleActive = false
    local aimToggleKey = Enum.KeyCode.G -- key to toggle aim if Mode = Toggle
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if AimSettings.Mode == 'Toggle' and input.KeyCode == aimToggleKey then
            isToggleActive = not isToggleActive
            Library:Notify('Aimbot ' .. (isToggleActive and 'Enabled' or 'Disabled'), 2)
        end
    end)
    -- helper functions
    local function canTarget(plr)
        if plr == LocalPlayer then return false end
        if AimSettings.TeamCheck and plr.Team == LocalPlayer.Team then return false end
        -- whitelist
        if AimSettings.AutoFriend then
            local success, isFriend = pcall(function() return LocalPlayer:IsFriendsWith(plr.UserId) end)
            if success and isFriend then return false end
        end
        for _, wName in pairs(AimSettings.Whitelist or {}) do
            if wName == plr.Name then return false end
        end
        return true
    end
    local function choosePart(plr)
        -- Weighted random choice of body part
        local total = 0
        for _, w in pairs(AimSettings.PartWeights) do total = total + w end
        if total <= 0 then return plr.Character:FindFirstChild("Head") end
        local pick = math.random(1, total)
        local cumulative = 0
        for partName, w in pairs(AimSettings.PartWeights) do
            cumulative = cumulative + w
            if pick <= cumulative then
                return plr.Character:FindFirstChild(partName)
            end
        end
        return plr.Character:FindFirstChild("Head")
    end
    local function isVisible(part)
        if not part then return false end
        if not AimSettings.VisibleCheck then return true end
        local origin = Camera.CFrame.Position
        local dir = (part.Position - origin)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { LocalPlayer.Character }
        local res = Workspace:Raycast(origin, dir.Unit * dir.Magnitude, params)
        return res == nil or res.Instance:IsDescendantOf(part.Parent)
    end
    local function getClosestTarget()
        local closest
        local closestDist = math.huge
        local mousePos = Vector2.new(Mouse.X, Mouse.Y)
        for _, plr in pairs(Players:GetPlayers()) do
            if plr.Character and plr.Character:FindFirstChildWhichIsA("Humanoid") and plr.Character.Humanoid.Health > 0 then
                if canTarget(plr) then
                    local part = choosePart(plr)
                    if part then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            if isVisible(part) then
                                local dist = (mousePos - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
                                if dist < closestDist then
                                    closestDist = dist
                                    closest = part
                                end
                            end
                        end
                    end
                end
            end
        end
        return closest
    end
    -- RenderStepped loop for aimbot
    RunService.RenderStepped:Connect(function(dt)
        if not AimSettings.Enabled then return end
        -- Determine if we should aim based on mode
        local aimActive = false
        if AimSettings.Mode == 'Hold' then
            aimActive = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        elseif AimSettings.Mode == 'Auto' then
            aimActive = true
        elseif AimSettings.Mode == 'Toggle' then
            aimActive = isToggleActive
        end
        if aimActive then
            -- Select target if none or lost
            if not aimbotTarget or not aimbotTarget.Parent or aimbotTarget.Parent:FindFirstChildWhichIsA("Humanoid").Health <= 0 then
                aimbotTarget = getClosestTarget()
            end
            local targetPart = aimbotTarget
            if targetPart and targetPart.Parent and targetPart.Parent:FindFirstChildWhichIsA("Humanoid") and targetPart.Parent.Humanoid.Health > 0 then
                if math.random(0,100) <= AimSettings.HitChance then
                    local predictedPos = targetPart.Position
                    -- Apply prediction (relative to velocity scaled)
                    local root = targetPart.Parent:FindFirstChild("HumanoidRootPart")
                    if root then
                        predictedPos = predictedPos + (root.Velocity * (AimSettings.Predict / 10))
                    end
                    -- Random hit offset
                    if AimSettings.RandomHit then
                        local offsetScale = math.random(-5,5)/100 * AimSettings.Predict
                        predictedPos = predictedPos + Vector3.new(offsetScale, offsetScale, offsetScale)
                    end
                    local camPos = Camera.CFrame.Position
                    local look = CFrame.new(camPos, predictedPos)
                    Camera.CFrame = Camera.CFrame:Lerp(look, dt * AimSettings.Smooth)
                end
            else
                aimbotTarget = nil -- lost target
            end
        else
            aimbotTarget = nil
        end
    end)

    ----------------------------------------------------------------
    -- 8. ESP Tab: Visual Enhancements
    ----------------------------------------------------------------
    local ESP_MainBox = Tabs.ESP:AddLeftGroupbox('ESP Elements')
    local ESP_SetBox  = Tabs.ESP:AddRightGroupbox('ESP Settings')

    -- ESP settings table
    local ESPSettings = {
        Box = false,
        Corner = false,
        Skeleton = false,
        HeadDot = false,
        NameTag = false,
        Distance = false,
        HealthBarLeft = false,
        HealthBarRight = false,
        Tracers = false,
        Chams = false,
        ChamPart = 'All',
        VisibleOnly = false,
        WallCheck = true,
        TeamCheck = true,
        Whitelist = {},
        AutoFriend = false,
        VisColor  = Color3.fromRGB(0, 255, 0),
        HidColor  = Color3.fromRGB(255, 0, 0),
        NameSize  = 16,
        DistSize  = 16,
        BarSize   = 4
    }

    -- Populate controls
    ESP_MainBox:AddToggle('ESP_Box', { Text = 'Box', Default = false, Callback = function(v) ESPSettings.Box = v end })
    ESP_MainBox:AddToggle('ESP_Corner', { Text = 'Corner Box', Default = false, Callback = function(v) ESPSettings.Corner = v end })
    ESP_MainBox:AddToggle('ESP_Skeleton', { Text = 'Skeleton', Default = false, Callback = function(v) ESPSettings.Skeleton = v end })
    ESP_MainBox:AddToggle('ESP_HeadDot', { Text = 'Head Dot', Default = false, Callback = function(v) ESPSettings.HeadDot = v end })
    ESP_MainBox:AddToggle('ESP_NameTag', { Text = 'Name Tag', Default = false, Callback = function(v) ESPSettings.NameTag = v end })
    ESP_MainBox:AddToggle('ESP_Distance', { Text = 'Distance', Default = false, Callback = function(v) ESPSettings.Distance = v end })
    ESP_MainBox:AddToggle('ESP_Tracers', { Text = 'Tracers', Default = false, Callback = function(v) ESPSettings.Tracers = v end })
    ESP_MainBox:AddToggle('ESP_HealthLeft', { Text = 'Health Bar Left', Default = false, Callback = function(v) ESPSettings.HealthBarLeft = v end })
    ESP_MainBox:AddToggle('ESP_HealthRight', { Text = 'Health Bar Right', Default = false, Callback = function(v) ESPSettings.HealthBarRight = v end })
    ESP_MainBox:AddToggle('ESP_Chams', { Text = 'Chams', Default = false, Callback = function(v) ESPSettings.Chams = v end })
    ESP_MainBox:AddDropdown('ESP_ChamPart', {
        Values  = { 'All', 'Head', 'Hands', 'Torso', 'Legs' },
        Default = 1,
        Multi   = false,
        Text    = 'Chams Part',
        Callback = function(v) ESPSettings.ChamPart = v end
    })
    ESP_MainBox:AddToggle('ESP_VisibleOnly', { Text = 'Visible Only', Default = false, Callback = function(v) ESPSettings.VisibleOnly = v end })
    ESP_SetBox:AddToggle('ESP_WallCheck', { Text = 'Wall Color Check', Default = true, Callback = function(v) ESPSettings.WallCheck = v end })
    ESP_SetBox:AddToggle('ESP_TeamCheck', { Text = 'Team Check', Default = true, Callback = function(v) ESPSettings.TeamCheck = v end })
    ESP_SetBox:AddToggle('ESP_AutoFriend', { Text = 'Auto Whitelist Friend', Default = false, Callback = function(v) ESPSettings.AutoFriend = v end })
    -- Colors
    ESP_SetBox:AddColorPicker('ESP_VisColor', { Title = 'Visible Color', Default = Color3.fromRGB(0,255,0), Callback = function(c) ESPSettings.VisColor = c end })
    ESP_SetBox:AddColorPicker('ESP_HidColor', { Title = 'Hidden Color', Default = Color3.fromRGB(255,0,0), Callback = function(c) ESPSettings.HidColor = c end })
    -- Sizes
    ESP_SetBox:AddSlider('ESP_NameSize', { Text = 'Name Size', Default = 16, Min=10, Max=30, Rounding=0, Callback = function(v) ESPSettings.NameSize = v end })
    ESP_SetBox:AddSlider('ESP_DistSize', { Text = 'Distance Size', Default = 16, Min=10, Max=30, Rounding=0, Callback = function(v) ESPSettings.DistSize = v end })
    ESP_SetBox:AddSlider('ESP_BarSize', { Text = 'Health Bar Width', Default = 4, Min=2, Max=10, Rounding=0, Callback = function(v) ESPSettings.BarSize = v end })
    -- ESP Whitelist dropdown
    local espWhitelistDropdown = ESP_SetBox:AddDropdown('ESP_Whitelist', {
        Values  = {},
        Default = nil,
        Multi   = true,
        Text    = 'ESP Whitelist'
    })
    local function updateESPWhitelist()
        local list = {}
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then table.insert(list, plr.Name) end
        end
        espWhitelistDropdown.Values = list
        espWhitelistDropdown:SetValues(list)
    end
    updateESPWhitelist()
    Players.PlayerAdded:Connect(updateESPWhitelist)
    Players.PlayerRemoving:Connect(updateESPWhitelist)
    espWhitelistDropdown:OnChanged(function(sel)
        ESPSettings.Whitelist = sel or {}
    end)

    -- ESP Drawing & Highlight management
    local DrawCache = {}
    local HighlightCache = {}
    local function removeESP(plr)
        if DrawCache[plr] then
            for _, obj in pairs(DrawCache[plr]) do
                obj:Remove()
            end
            DrawCache[plr] = nil
        end
        if HighlightCache[plr] then
            for _, h in pairs(HighlightCache[plr]) do
                pcall(function() h:Destroy() end)
            end
            HighlightCache[plr] = nil
        end
    end
    local function createDrawing(type, props)
        local d = Drawing.new(type)
        for k,v in pairs(props) do d[k] = v end
        return d
    end
    -- update ESP each frame
    RunService.RenderStepped:Connect(function()
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChildWhichIsA("Humanoid") and plr.Character.Humanoid.Health > 0 then
                -- skip if in whitelist
                local skip = false
                if ESPSettings.AutoFriend then
                    local success, isFriend = pcall(function() return LocalPlayer:IsFriendsWith(plr.UserId) end)
                    if success and isFriend then skip = true end
                end
                for _, wName in pairs(ESPSettings.Whitelist or {}) do if wName == plr.Name then skip = true break end end
                if ESPSettings.TeamCheck and plr.Team == LocalPlayer.Team then skip = true end
                -- prepare drawing objects
                if not DrawCache[plr] then
                    DrawCache[plr] = {}
                    DrawCache[plr].Box    = createDrawing("Square", {Thickness=1,Filled=false,Visible=false})
                    DrawCache[plr].Corner = createDrawing("Quad", {Thickness=1,Filled=false,Visible=false})
                    DrawCache[plr].Tracers= createDrawing("Line", {Thickness=1,Visible=false})
                    DrawCache[plr].Name   = createDrawing("Text", {Size=16,Center=true,Outline=true,Visible=false})
                    DrawCache[plr].Dist   = createDrawing("Text", {Size=16,Center=true,Outline=true,Visible=false})
                    DrawCache[plr].HeadDot= createDrawing("Circle", {Radius=4,Filled=true,Visible=false})
                    DrawCache[plr].HealthLeft = createDrawing("Line", {Thickness=ESPSettings.BarSize,Visible=false})
                    DrawCache[plr].HealthRight= createDrawing("Line", {Thickness=ESPSettings.BarSize,Visible=false})
                end
                -- update highlight
                if ESPSettings.Chams then
                    -- create highlights if not exist
                    if not HighlightCache[plr] then HighlightCache[plr] = {} end
                    -- determine parts to highlight
                    local parts = {}
                    if ESPSettings.ChamPart == 'All' then
                        for _, p in pairs(plr.Character:GetChildren()) do
                            if p:IsA("BasePart") then table.insert(parts, p) end
                        end
                    elseif ESPSettings.ChamPart == 'Head' then
                        local head = plr.Character:FindFirstChild("Head")
                        if head then parts = { head } end
                    elseif ESPSettings.ChamPart == 'Hands' then
                        local lh = plr.Character:FindFirstChild("LeftHand")
                        local rh = plr.Character:FindFirstChild("RightHand")
                        if lh then table.insert(parts, lh) end
                        if rh then table.insert(parts, rh) end
                    elseif ESPSettings.ChamPart == 'Torso' then
                        local ut = plr.Character:FindFirstChild("UpperTorso")
                        local lt = plr.Character:FindFirstChild("LowerTorso")
                        if ut then table.insert(parts, ut) end
                        if lt then table.insert(parts, lt) end
                    elseif ESPSettings.ChamPart == 'Legs' then
                        local ll = plr.Character:FindFirstChild("LeftLeg") or plr.Character:FindFirstChild("LeftFoot")
                        local rl = plr.Character:FindFirstChild("RightLeg") or plr.Character:FindFirstChild("RightFoot")
                        if ll then table.insert(parts, ll) end
                        if rl then table.insert(parts, rl) end
                    end
                    -- remove any stale highlights not in parts
                    if HighlightCache[plr] then
                        for part, h in pairs(HighlightCache[plr]) do
                            if not table.find(parts, part) then
                                h:Destroy()
                                HighlightCache[plr][part] = nil
                            end
                        end
                    end
                    -- create or update highlights
                    for _, part in ipairs(parts) do
                        if not HighlightCache[plr][part] then
                            local h = Instance.new("Highlight")
                            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            h.FillTransparency = 0.5
                            h.OutlineTransparency = 0
                            h.Parent = game.CoreGui
                            HighlightCache[plr][part] = h
                        end
                        local h = HighlightCache[plr][part]
                        h.Adornee = part
                        h.FillColor = ESPSettings.VisColor
                        h.OutlineColor = ESPSettings.VisColor
                    end
                else
                    -- destroy highlights if disabled
                    if HighlightCache[plr] then
                        for _, h in pairs(HighlightCache[plr]) do h:Destroy() end
                        HighlightCache[plr] = nil
                    end
                end
                -- compute screen position and draw
                local char = plr.Character
                local root = char:FindFirstChild("HumanoidRootPart")
                local head = char:FindFirstChild("Head")
                if root and head then
                    local hrpPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                    local headPos, onHead  = Camera:WorldToViewportPoint(head.Position)
                    if onScreen and onHead and not skip then
                        local isVis = true
                        if ESPSettings.WallCheck then
                            local origin = Camera.CFrame.Position
                            local dir = (head.Position - origin)
                            local params = RaycastParams.new()
                            params.FilterType = Enum.RaycastFilterType.Exclude
                            params.FilterDescendantsInstances = { LocalPlayer.Character }
                            local res = Workspace:Raycast(origin, dir.Unit * dir.Magnitude, params)
                            isVis = res == nil or res.Instance:IsDescendantOf(char)
                        end
                        local col = isVis and ESPSettings.VisColor or ESPSettings.HidColor
                        -- box dimensions
                        local boxH = (headPos.Y - hrpPos.Y) * -2
                        local boxW = boxH/2
                        local x = headPos.X - boxW/2
                        local y = headPos.Y - boxH*0.1
                        -- Box
                        if ESPSettings.Box then
                            local box = DrawCache[plr].Box
                            box.Visible = true
                            box.Color = col
                            box.Size = Vector2.new(boxW, boxH)
                            box.Position = Vector2.new(x, y)
                        else
                            DrawCache[plr].Box.Visible = false
                        end
                        -- Corner box (draw quad corners)
                        if ESPSettings.Corner then
                            local quad = DrawCache[plr].Corner
                            quad.Visible = true
                            quad.Color = col
                            local topLeft     = Vector2.new(x, y)
                            local topRight    = Vector2.new(x + boxW, y)
                            local bottomLeft  = Vector2.new(x, y + boxH)
                            local bottomRight = Vector2.new(x + boxW, y + boxH)
                            -- create small corners: use quad to draw one big shape representing corners
                            quad.PointA = topLeft + Vector2.new(boxW*0.2, 0)
                            quad.PointB = topRight - Vector2.new(boxW*0.2, 0)
                            quad.PointC = bottomRight - Vector2.new(boxW*0.2, 0)
                            quad.PointD = bottomLeft + Vector2.new(boxW*0.2, 0)
                        else
                            DrawCache[plr].Corner.Visible = false
                        end
                        -- Tracers
                        if ESPSettings.Tracers then
                            local tracer = DrawCache[plr].Tracers
                            tracer.Visible = true
                            tracer.Color = col
                            tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                            tracer.To   = Vector2.new(hrpPos.X, hrpPos.Y)
                        else
                            DrawCache[plr].Tracers.Visible = false
                        end
                        -- Name Tag
                        if ESPSettings.NameTag then
                            local nameDraw = DrawCache[plr].Name
                            nameDraw.Visible = true
                            nameDraw.Color   = col
                            nameDraw.Text    = plr.Name
                            nameDraw.Size    = ESPSettings.NameSize
                            nameDraw.Position= Vector2.new(headPos.X, y - 15)
                        else
                            DrawCache[plr].Name.Visible = false
                        end
                        -- Distance
                        if ESPSettings.Distance then
                            local distDraw = DrawCache[plr].Dist
                            distDraw.Visible = true
                            distDraw.Color   = col
                            local dist = (root.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
                            distDraw.Text  = string.format("%.0f m", dist)
                            distDraw.Size  = ESPSettings.DistSize
                            distDraw.Position = Vector2.new(hrpPos.X, hrpPos.Y + boxH + 10)
                        else
                            DrawCache[plr].Dist.Visible = false
                        end
                        -- Head Dot
                        if ESPSettings.HeadDot then
                            local dot = DrawCache[plr].HeadDot
                            dot.Visible = true
                            dot.Color   = col
                            dot.Radius  = 3
                            dot.Position= Vector2.new(headPos.X, headPos.Y)
                        else
                            DrawCache[plr].HeadDot.Visible = false
                        end
                        -- Health bar left/right
                        local hum = char:FindFirstChildWhichIsA("Humanoid")
                        if hum then
                            local hpFrac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                            if ESPSettings.HealthBarLeft then
                                local bar = DrawCache[plr].HealthLeft
                                bar.Visible = true
                                bar.Color   = Color3.fromRGB(255 - math.floor(255 * hpFrac), math.floor(255 * hpFrac), 0)
                                bar.Thickness = ESPSettings.BarSize
                                local startY = y + boxH
                                local endY   = startY - (boxH * hpFrac)
                                bar.From = Vector2.new(x - 5, startY)
                                bar.To   = Vector2.new(x - 5, endY)
                            else
                                DrawCache[plr].HealthLeft.Visible = false
                            end
                            if ESPSettings.HealthBarRight then
                                local bar = DrawCache[plr].HealthRight
                                bar.Visible = true
                                bar.Color   = Color3.fromRGB(255 - math.floor(255 * hpFrac), math.floor(255 * hpFrac), 0)
                                bar.Thickness = ESPSettings.BarSize
                                local startY = y + boxH
                                local endY   = startY - (boxH * hpFrac)
                                bar.From = Vector2.new(x + boxW + 5, startY)
                                bar.To   = Vector2.new(x + boxW + 5, endY)
                            else
                                DrawCache[plr].HealthRight.Visible = false
                            end
                        end
                    else
                        -- hide if off screen or skipping
                        local d = DrawCache[plr]
                        d.Box.Visible=false; d.Corner.Visible=false; d.Tracers.Visible=false
                        d.Name.Visible=false; d.Dist.Visible=false; d.HeadDot.Visible=false
                        d.HealthLeft.Visible=false; d.HealthRight.Visible=false
                    end
                else
                    -- hide if no root/head
                    if DrawCache[plr] then
                        local d = DrawCache[plr]
                        d.Box.Visible=false; d.Corner.Visible=false; d.Tracers.Visible=false
                        d.Name.Visible=false; d.Dist.Visible=false; d.HeadDot.Visible=false
                        d.HealthLeft.Visible=false; d.HealthRight.Visible=false
                    end
                end
            else
                removeESP(plr)
            end
        end
    end)
    -- Remove drawings on player leave
    Players.PlayerRemoving:Connect(function(plr) removeESP(plr) end)

    ----------------------------------------------------------------
    -- 9. Misc Tab: Miscellaneous Utilities
    ----------------------------------------------------------------
    local Misc_ServerBox = Tabs.Misc:AddLeftGroupbox('Server Tools')
    local Misc_ClientBox = Tabs.Misc:AddRightGroupbox('Client Tools')

    -- Anti AFK
    local AntiAfkToggle = Misc_ServerBox:AddToggle('Misc_AntiAFK', { Text = 'Anti AFK', Default = true })
    -- Auto Reconnect (auto rejoin when character removed)
    local AutoReconnectToggle = Misc_ServerBox:AddToggle('Misc_AutoReconnect', { Text = 'Auto Reconnect', Default = false })
    -- Server hop low players
    Misc_ServerBox:AddButton('Server Hop (Low)', function()
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
        local body = safeHttpGet(url)
        if body then
            local data = HttpService:JSONDecode(body)
            for _, s in pairs(data.data or {}) do
                if s.playing < s.maxPlayers and s.id ~= game.JobId then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                    break
                end
            end
        end
    end)
    -- Server hop high players (random server)
    Misc_ServerBox:AddButton('Server Hop (Random)', function()
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100", game.PlaceId)
        local body = safeHttpGet(url)
        if body then
            local data = HttpService:JSONDecode(body)
            local candidates = {}
            for _, s in pairs(data.data or {}) do
                if s.id ~= game.JobId then table.insert(candidates, s) end
            end
            if #candidates > 0 then
                local pick = candidates[math.random(1, #candidates)]
                TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
            end
        end
    end)
    -- Auto reconnect logic: keep track of connection
    LocalPlayer.CharacterAdded:Connect(function()
        if AutoReconnectToggle.Value then
            Library:Notify('Rejoined server', 3)
        end
    end)
    LocalPlayer.CharacterRemoving:Connect(function()
        if AutoReconnectToggle.Value then
            task.delay(2, function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
        end
    end)
    -- Anti AFK implementation
    LocalPlayer.Idled:Connect(function()
        if AntiAfkToggle.Value then
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end)
    -- Client side tools: toggle UI, panic/unload
    Misc_ClientBox:AddButton('Unload / Panic', function()
        Library:Unload()
        warn('[BxB] Unloaded script')
    end)
    Misc_ClientBox:AddToggle('UI_Toggle', { Text = 'Toggle UI (Ctrl+J)', Default = true, Callback = function(v)
        -- placeholder for UI toggle key binding; actual keybind set by library
    end })

    ----------------------------------------------------------------
    -- 10. Game Tab: Game‑Specific Modules
    ----------------------------------------------------------------
    local Game_MainBox = Tabs.Game:AddLeftGroupbox('Module Loader')
    -- Define game modules
    local GameModules = {
        [2753915549] = { Name = 'Blox Fruits', Url = nil }, -- replace Url with your script
        [4442272183] = { Name = 'Blox Fruits', Url = nil },
        [7449423635] = { Name = 'Blox Fruits', Url = nil },
        [286090429]  = { Name = 'Arsenal', Url = nil },
        [155615604]  = { Name = 'Prison Life', Url = nil }
    }
    -- detect current game
    local gameName = 'Universal'
    local moduleInfo = GameModules[game.PlaceId]
    if moduleInfo then
        gameName = moduleInfo.Name
    end
    Game_MainBox:AddLabel('Detected: ' .. gameName)
    if moduleInfo and moduleInfo.Url then
        Game_MainBox:AddButton('Load ' .. moduleInfo.Name .. ' Module', function()
            local scriptSrc = safeHttpGet(moduleInfo.Url)
            if scriptSrc then
                local modChunk, err = loadstring(scriptSrc)
                if modChunk then
                    pcall(modChunk, Exec, UserData, Library)
                else
                    warn('[BxB] Module load error: ' .. tostring(err))
                end
            else
                warn('[BxB] Unable to fetch module for ' .. moduleInfo.Name)
            end
        end)
    else
        Game_MainBox:AddLabel('No specific module available.')
        Game_MainBox:AddLabel('Universal features are active.')
    end

    ----------------------------------------------------------------
    -- 11. Settings Tab: Theme & Config
    ----------------------------------------------------------------
    -- Apply managers only if loaded
    if ThemeManager then
        ThemeManager:ApplyToTab(Tabs.Settings)
    end
    if SaveManager then
        SaveManager:SetLibrary(Library)
        SaveManager:SetFolder(Config.FolderName .. '/Configs')
        SaveManager:IgnoreThemeSettings()
        SaveManager:BuildConfigSection(Tabs.Settings)
    end
    -- custom UI for theme selection
    Tabs.Settings:AddLeftGroupbox('Theme'):AddButton('Random Theme', function()
        local themes = {
            { 'Light', { FontColor = Color3.new(0,0,0), MainColor = Color3.fromRGB(60, 61, 83), AccentColor = Color3.fromRGB(255,255,255) } },
            { 'Dark', { FontColor = Color3.new(1,1,1), MainColor = Color3.fromRGB(40,40,40), AccentColor = Color3.fromRGB(255,0,0) } }
        }
        local choice = themes[math.random(1, #themes)]
        Library.Theme = choice[2]
        Library:Notify('Applied ' .. choice[1] .. ' theme', 3)
    end)

    ----------------------------------------------------------------
    -- 12. Final Notification
    ----------------------------------------------------------------
    Library:Notify('BxB.ware Premium Loaded Successfully!', 5)
end
