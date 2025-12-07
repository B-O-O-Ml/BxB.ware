-- Main_Hub.lua
-- ถูกเรียกจาก Key UI: startFn(Exec, keydata, dynamicToken)

return function(Exec, UserData, IncomingToken)
    ----------------------------------------------------------------
    -- 0. Basic Services
    ----------------------------------------------------------------
    local Players         = game:GetService("Players")
    local RunService      = game:GetService("RunService")
    local UserInputService= game:GetService("UserInputService")
    local Stats           = game:FindService("Stats") or game:GetService("Stats")
    local HttpService     = game:GetService("HttpService")
    local StarterGui      = game:GetService("StarterGui")
    local Lighting        = game:GetService("Lighting")
    local TeleportService = game:GetService("TeleportService")

    local LocalPlayer     = Players.LocalPlayer
    local Camera          = workspace.CurrentCamera

    ----------------------------------------------------------------
    -- 1. Security Layer: Dynamic Token Check
    ----------------------------------------------------------------
    local secretSalt   = "BxB_SUPER_SECRET_SALT_CHANGE_THIS" -- ต้องตรงกับ Key UI
    local datePart     = os.date("%Y%m%d")
    local expectedToken= secretSalt .. "_" .. datePart

    if IncomingToken ~= expectedToken then
        warn("[BxB Security] Invalid Security Token!")

        if LocalPlayer then
            LocalPlayer:Kick("Security Breach: Invalid Token (Please re-login via Key UI)")
        end

        return
    end

    ----------------------------------------------------------------
    -- 2. Security Layer: UserData Check
    ----------------------------------------------------------------
    if type(UserData) ~= "table" or type(UserData.key) ~= "string" then
        warn("[BxB Security] Invalid UserData from Key UI")
        return
    end

    -- helper ปลอดภัยเวลาหา field
    local function safe(t, k, default)
        if type(t) ~= "table" then
            return default
        end
        local v = t[k]
        if v == nil then
            return default
        end
        return v
    end

    local keyValue   = safe(UserData, "key", "UNKNOWN_KEY")
    local keyStatus  = safe(UserData, "status", "unknown")
    local keyRole    = safe(UserData, "role", "user")
    local keyOwner   = safe(UserData, "owner", "N/A")
    local keyNote    = safe(UserData, "note", "No note")
    local keyCreated = safe(UserData, "timestamp", nil)  -- แนะนำให้เป็น os.time() จากฝั่ง keydata
    local keyExpire  = safe(UserData, "expire", nil)     -- แนะนำให้เป็น os.time() หมดอายุ

    print(("[BxB] Access Granted. Key: %s | Role: %s"):format(keyValue, keyRole))

    ----------------------------------------------------------------
    -- 3. Config: URL ของ Obsidian / Theme / Save
    ----------------------------------------------------------------
    local Config = {
        LIB_URL      = "https://raw.githubusercontent.com/your-user/your-repo/main/Library.lua",
        THEME_URL    = "https://raw.githubusercontent.com/your-user/your-repo/main/ThemeManager.lua",
        SAVE_URL     = "https://raw.githubusercontent.com/your-user/your-repo/main/SaveManager.lua",
        FOLDER_NAME  = "BxB.ware",  -- สำหรับ SaveManager
    }

    local function safeHttpGet(url)
        local ok, res = pcall(function()
            return Exec.HttpGet(url)
        end)
        if not ok then
            warn("[BxB] HttpGet failed for: " .. tostring(url) .. " | " .. tostring(res))
            return nil
        end
        return res
    end

    ----------------------------------------------------------------
    -- 4. Load Obsidian Library + ThemeManager + SaveManager
    ----------------------------------------------------------------
    local librarySrc = safeHttpGet(Config.LIB_URL)
    if not librarySrc then
        warn("[BxB] Cannot load Library.lua")
        return
    end

    local libChunk, libErr = loadstring(librarySrc)
    if not libChunk then
        warn("[BxB] Library chunk error: " .. tostring(libErr))
        return
    end

    local Library = libChunk()
    if not Library then
        warn("[BxB] Library returned nil")
        return
    end

    local ThemeManager, SaveManager

    do
        local themeSrc = Config.THEME_URL and safeHttpGet(Config.THEME_URL)
        if themeSrc then
            local ok, mod = pcall(loadstring(themeSrc))
            if ok and type(mod) == "table" then
                ThemeManager = mod
                if ThemeManager.SetLibrary then
                    ThemeManager:SetLibrary(Library)
                end
            else
                warn("[BxB] Failed to init ThemeManager: " .. tostring(mod))
            end
        end

        local saveSrc = Config.SAVE_URL and safeHttpGet(Config.SAVE_URL)
        if saveSrc then
            local ok, mod = pcall(loadstring(saveSrc))
            if ok and type(mod) == "table" then
                SaveManager = mod
                if SaveManager.SetLibrary then
                    SaveManager:SetLibrary(Library)
                end
                if SaveManager.SetFolder then
                    SaveManager:SetFolder(Config.FOLDER_NAME .. "/Config")
                end
            else
                warn("[BxB] Failed to init SaveManager: " .. tostring(mod))
            end
        end
    end

    ----------------------------------------------------------------
    -- 5. Create Window & Tabs (ตามโครงที่คุณกำหนด)
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
        Info = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "database",
            Description = "Key Status / Info"
        }),
        Player = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "users",
            Description = "Player Tool"
        }),
        Combat = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "eye",
            Description = "Combat Client"
        }),
        ESP = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "crosshair",
            Description = "ESP Client"
        }),
        Misc = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "crosshair",
            Description = "Misc Client"
        }),
        Game = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "joystick",
            Description = "Game Module"
        }),
        Settings = Window:AddTab({
            Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon = "settings",
            Description = "UI/UX Settings"
        }),
    }

    ----------------------------------------------------------------
    -- 6. Info Tab: Key Status + System Info (Skeleton + Countdown)
    ----------------------------------------------------------------
    local KeyBox = Tabs.Info:AddLeftGroupbox("Key Status")
    local SysBox = Tabs.Info:AddRightGroupbox("System / Session")

    -- แสดงค่าคีย์แบบ mask นิดหน่อย
    local function maskKey(key)
        key = tostring(key)
        if #key <= 6 then
            return key
        end
        return key:sub(1, 3) .. string.rep("*", math.max(0, #key - 6)) .. key:sub(#key-2, #key)
    end

    KeyBox:AddLabel("Key : " .. maskKey(keyValue))
    KeyBox:AddLabel("Status : " .. tostring(keyStatus))
    KeyBox:AddLabel("Role : " .. tostring(keyRole))
    KeyBox:AddLabel("Owner : " .. tostring(keyOwner))
    KeyBox:AddLabel("Note : " .. tostring(keyNote))

    local createdLabel = KeyBox:AddLabel("Created : " .. (keyCreated and os.date("%Y-%m-%d %H:%M:%S", keyCreated) or "N/A"))
    local expireLabel  = KeyBox:AddLabel("Expire : " .. (keyExpire and os.date("%Y-%m-%d %H:%M:%S", keyExpire) or "N/A"))
    local remainLabel  = KeyBox:AddLabel("Time Left : calculating...")

    -- helper แปลง seconds -> string
    local function formatDuration(sec)
        if not sec or sec < 0 then
            return "Expired"
        end
        local d = math.floor(sec / 86400)
        sec = sec % 86400
        local h = math.floor(sec / 3600)
        sec = sec % 3600
        local m = math.floor(sec / 60)
        local s = sec % 60

        local parts = {}
        if d > 0 then table.insert(parts, d .. "d") end
        if h > 0 then table.insert(parts, h .. "h") end
        if m > 0 then table.insert(parts, m .. "m") end
        table.insert(parts, s .. "s")

        return table.concat(parts, " ")
    end

    -- อัปเดต countdown ทุกวินาที
    task.spawn(function()
        while true do
            task.wait(1)
            if not keyExpire or type(keyExpire) ~= "number" then
                remainLabel:SetText("Time Left : N/A")
            else
                local now = os.time()
                local remain = keyExpire - now
                remainLabel:SetText("Time Left : " .. formatDuration(remain))
            end
        end
    end)

    -- System / Session info
    local function getPing()
        local network = Stats and Stats:FindFirstChild("Network")
        local serverStats = network and network:FindFirstChild("ServerStatsItem")
        local dataPing = serverStats and serverStats:FindFirstChild("Data Ping")
        return dataPing and math.floor(dataPing:GetValue()) or nil
    end

    local function getFPS()
        -- วิธีง่าย ๆ: วัดด้วย RenderStepped ในที่อื่นก็ได้
        return nil
    end

    local gameInfoLabel   = SysBox:AddLabel("Game ID : " .. tostring(game.PlaceId))
    local jobIdLabel      = SysBox:AddLabel("Job ID : " .. tostring(game.JobId))
    SysBox:AddLabel("Game Name : " .. (game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Unknown"))

    SysBox:AddDivider()

    local userLabel       = SysBox:AddLabel("User : " .. (LocalPlayer and LocalPlayer.Name or "N/A"))
    local displayLabel    = SysBox:AddLabel("Display : " .. (LocalPlayer and LocalPlayer.DisplayName or "N/A"))
    local ageLabel        = SysBox:AddLabel("Account Age : " .. (LocalPlayer and tostring(LocalPlayer.AccountAge) .. " days" or "N/A"))

    SysBox:AddDivider()

    local pingLabel       = SysBox:AddLabel("Ping : N/A")
    local fpsLabel        = SysBox:AddLabel("FPS : N/A")

    -- loop อัปเดต Ping/FPS
    task.spawn(function()
        local lastTime = tick()
        local frames = 0
        while true do
            RunService.RenderStepped:Wait()
            frames = frames + 1
            local now = tick()
            if now - lastTime >= 1 then
                local fps = frames / (now - lastTime)
                frames = 0
                lastTime = now

                fpsLabel:SetText("FPS : " .. tostring(math.floor(fps)))

                local ping = getPing()
                if ping then
                    pingLabel:SetText("Ping : " .. tostring(ping) .. " ms")
                end
            end
        end
    end)

    ----------------------------------------------------------------
    -- 7. Player Tab: Movement / Tools (Skeleton)
    ----------------------------------------------------------------
    local MoveBox = Tabs.Player:AddLeftGroupbox("Movement")
    local ToolBox = Tabs.Player:AddRightGroupbox("Player Tools")

    -- WalkSpeed / JumpPower basic
    local defaultWalkSpeed = 16
    local defaultJumpPower = 50

    local function getHumanoid()
        local char = LocalPlayer and LocalPlayer.Character
        if not char then return nil end
        return char:FindFirstChildOfClass("Humanoid")
    end

    MoveBox:AddSlider("BxB_WalkSpeed", {
        Text = "WalkSpeed",
        Default = defaultWalkSpeed,
        Min = 0,
        Max = 200,
        Rounding = 0,
        Compact = false
    }):OnChanged(function(value)
        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = value
        end
    end)

    MoveBox:AddSlider("BxB_JumpPower", {
        Text = "JumpPower",
        Default = defaultJumpPower,
        Min = 0,
        Max = 200,
        Rounding = 0,
        Compact = false
    }):OnChanged(function(value)
        local hum = getHumanoid()
        if hum then
            hum.JumpPower = value
        end
    end)

    -- Inf Jump (ตัวอย่าง logic เบื้องต้น)
    local InfJumpToggle = MoveBox:AddToggle("BxB_InfJump", {
        Text = "Infinite Jump",
        Default = false
    })

    do
        local infJumpEnabled = false

        InfJumpToggle:OnChanged(function(value)
            infJumpEnabled = value
        end)

        UserInputService.JumpRequest:Connect(function()
            if infJumpEnabled then
                local hum = getHumanoid()
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end
        end)
    end

    -- TODO: Fly, Noclip, ฯลฯ จะใส่ในรอบถัดไป

    -- Player Tools (skeleton)
    local playerList = {}
    local function refreshPlayers()
        table.clear(playerList)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(playerList, plr.Name)
            end
        end
    end

    refreshPlayers()
    Players.PlayerAdded:Connect(refreshPlayers)
    Players.PlayerRemoving:Connect(refreshPlayers)

    local SpectateDropdown = ToolBox:AddDropdown("BxB_SpectateTarget", {
        Text = "Spectate Player",
        Values = playerList,
        Default = 1,
        Multi = false
    })

    local spectating = nil

    ToolBox:AddToggle("BxB_SpectateToggle", {
        Text = "Enable Spectate",
        Default = false
    }):OnChanged(function(on)
        if on then
            local targetName = SpectateDropdown.Value
            spectating = Players:FindFirstChild(targetName)
        else
            spectating = nil
            if Camera then
                Camera.CameraSubject = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            end
        end
    end)

    SpectateDropdown:OnChanged(function(value)
        if value then
            spectating = Players:FindFirstChild(value)
        end
    end)

    RunService.RenderStepped:Connect(function()
        if spectating and spectating.Character and Camera then
            local hum = spectating.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                Camera.CameraSubject = hum
            end
        end
    end)

    ToolBox:AddButton("Teleport to Player", function()
        local targetName = SpectateDropdown.Value
        local target = Players:FindFirstChild(targetName or "")
        if target and target.Character and LocalPlayer and LocalPlayer.Character then
            local hrpTarget = target.Character:FindFirstChild("HumanoidRootPart")
            local hrpLocal  = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrpTarget and hrpLocal then
                hrpLocal.CFrame = hrpTarget.CFrame + Vector3.new(0, 2, 0)
            end
        end
    end)

    -- TODO: Free Camera / Fly / Noclip / ฯลฯ

    ----------------------------------------------------------------
    -- 8. TODO: Combat / ESP / Misc / Game / Settings Skeleton
    ----------------------------------------------------------------
    -- ในรอบถัดไป เราจะมาสร้างโครง:
    -- - Tabs.Combat:AddLeftGroupbox("Aimbot") ...
    -- - Tabs.ESP:AddLeftGroupbox("ESP / Visuals") ...
    -- - Tabs.Misc:AddLeftGroupbox("Server / Game Tools") ...
    -- - Tabs.Game ใช้ Game Detection + Module Loader
    -- - Tabs.Settings ผูก ThemeManager + SaveManager + Unload

    ----------------------------------------------------------------
    -- 9. Notification เมื่อโหลดเสร็จ
    ----------------------------------------------------------------
    StarterGui:SetCore("SendNotification", {
        Title = "BxB.ware Loaded",
        Text = "Main Hub initialized successfully.",
        Duration = 5
    })
end
