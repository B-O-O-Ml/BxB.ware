-- Main_Hub.lua (Skeleton UI Only)
-- ใช้ร่วมกับ Key UI ที่ส่ง (Exec, UserData, IncomingToken)

return function(Exec, UserData, IncomingToken)
    ----------------------------------------------------------------
    -- 0. Basic Config (ใส่ URL จริงของคุณเอง)
    ----------------------------------------------------------------
    local Config = {
        LIB_URL    = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua",
        THEME_URL  = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/ThemeManager.lua",
        SAVE_URL   = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/SaveManager.lua",

        FolderName = "BxB.ware/Configs"
    }

    ----------------------------------------------------------------
    -- 1. Security Layer: Dynamic Token Check
    ----------------------------------------------------------------
    local secretSalt   = "BxB_SUPER_SECRET_SALT_CHANGE_THIS" -- ต้องตรงกับ Key UI
    local datePart     = os.date("%Y%m%d")
    local expectedToken = secretSalt .. "_" .. datePart

    if IncomingToken ~= expectedToken then
        warn("[BxB Security] Invalid Security Token!")

        local Players = game:GetService("Players")
        local lp = Players.LocalPlayer
        if lp then
            lp:Kick("Security Breach: Invalid Token (Please re-login via Key UI)")
        end

        return
    end

    ----------------------------------------------------------------
    -- 2. Basic UserData Check (โครงเท่านั้น)
    ----------------------------------------------------------------
    if type(UserData) ~= "table" or type(UserData.key) ~= "string" then
        warn("[BxB Security] Invalid UserData from Key UI")
        return
    end

    -- ฟิลด์ที่ “อยากมี” (ไม่บังคับว่าต้องมีจริงทุกตัว)
    local key       = UserData.key
    local status    = UserData.status or "unknown"
    local role      = UserData.role or "user"
    local owner     = UserData.owner or "N/A"
    local timestamp = UserData.timestamp or "N/A"
    local expire    = UserData.expire or "N/A"
    local note      = UserData.note or "N/A"

    ----------------------------------------------------------------
    -- 3. Services / Local Refs
    ----------------------------------------------------------------
    local Players            = game:GetService("Players")
    local RunService         = game:GetService("RunService")
    local UserInputService   = game:GetService("UserInputService")
    local HttpService        = game:GetService("HttpService")
    local TeleportService    = game:GetService("TeleportService")
    local StarterGui         = game:GetService("StarterGui")

    local LocalPlayer = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    ----------------------------------------------------------------
    -- 4. Helper: Safe HttpGet
    ----------------------------------------------------------------
    local function safeHttpGet(url)
        local ok, res = pcall(function()
            return Exec.HttpGet(url)
        end)

        if not ok then
            warn("[BxB] HttpGet failed: " .. tostring(res))
            return nil
        end

        return res
    end

    ----------------------------------------------------------------
    -- 5. Load Obsidian Library + ThemeManager + SaveManager
    ----------------------------------------------------------------
    local Library, ThemeManager, SaveManager

    do
        local src = safeHttpGet(Config.LIB_URL)
        if not src then
            warn("[BxB] Cannot load Library.lua")
            return
        end

        local chunk, err = loadstring(src)
        if not chunk then
            warn("[BxB] Library chunk error: " .. tostring(err))
            return
        end

        Library = chunk()
        if not Library then
            warn("[BxB] Library returned nil")
            return
        end
    end

    do
        local themeSrc = Config.THEME_URL and safeHttpGet(Config.THEME_URL)
        if themeSrc then
            local ok, mod = pcall(loadstring(themeSrc))
            if ok and type(mod) == "table" then
                ThemeManager = mod
                if ThemeManager.SetLibrary then
                    ThemeManager:SetLibrary(Library)
                end
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
                    SaveManager:SetFolder(Config.FolderName)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- 6. Create Main Window + Tabs (โครงตามที่คุณกำหนด)
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title      = "",
        Icon       = 84528813312016,
        Size       = UDim2.fromOffset(720, 600),
        Center     = true,
        AutoShow   = true,
        Resizable  = true,
        Compact    = true,
    })

    local Tabs = {
        Info = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "database",
            Description = "Key Status / Info"
        }),

        Player = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "users",
            Description = "Player Tool"
        }),

        Combat = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "eye",
            Description = "Combat Client"
        }),

        ESP = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "crosshair",
            Description = "ESP Client"
        }),

        Misc = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "crosshair",
            Description = "Misc Client"
        }),

        Game = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "joystick",
            Description = "Game Module"
        }),

        Settings = Window:AddTab({
            Name        = '<b><font color="#FF0000">BxB.ware | Premium</font></b>',
            Icon        = "settings",
            Description = "UI/UX Settings"
        }),
    }

    ----------------------------------------------------------------
    -- 7. INFO TAB (Key Status + System Info Skeleton)
    ----------------------------------------------------------------
    local InfoLeft  = Tabs.Info:AddLeftGroupbox("Key Status")
    local InfoRight = Tabs.Info:AddRightGroupbox("System Info")

    -- Key Status (ใช้ข้อมูลจาก UserData เฉย ๆ ยังไม่ต้องทำ countdown)
    InfoLeft:AddLabel("Key: " .. tostring(key))
    InfoLeft:AddLabel("Status: " .. tostring(status))
    InfoLeft:AddLabel("Role: " .. tostring(role))
    InfoLeft:AddLabel("Owner: " .. tostring(owner))
    InfoLeft:AddLabel("Timestamp: " .. tostring(timestamp))
    InfoLeft:AddLabel("Expire: " .. tostring(expire))
    InfoLeft:AddLabel("Note: " .. tostring(note))

    InfoLeft:AddDivider()
    InfoLeft:AddLabel("You can expand this box later with:")
    InfoLeft:AddLabel("- Real-time expire countdown")
    InfoLeft:AddLabel("- Last login time, HWID hash, etc.")

    -- System Info (เกม + ผู้เล่น)
    local placeId = game.PlaceId
    local jobId   = game.JobId
    local gameName = "Unknown"

    InfoRight:AddLabel("Game Name: " .. gameName)
    InfoRight:AddLabel("PlaceId: " .. tostring(placeId))
    InfoRight:AddLabel("JobId: " .. tostring(jobId))
    InfoRight:AddLabel("Players: " .. #Players:GetPlayers())

    if LocalPlayer then
        InfoRight:AddDivider()
        InfoRight:AddLabel("Username: " .. LocalPlayer.Name)
        InfoRight:AddLabel("Display: " .. LocalPlayer.DisplayName)
        InfoRight:AddLabel("Account Age: " .. tostring(LocalPlayer.AccountAge))
    end

    InfoRight:AddDivider()
    InfoRight:AddLabel("You can later add:")
    InfoRight:AddLabel("- Ping / FPS / Memory")
    InfoRight:AddLabel("- Executor name, version, etc.")

    ----------------------------------------------------------------
    -- 8. PLAYER TAB (Movement + Player Tools Skeleton)
    ----------------------------------------------------------------
    local PlayerLeft  = Tabs.Player:AddLeftGroupbox("Movement")
    local PlayerRight = Tabs.Player:AddRightGroupbox("Player Tools")

    -- Movement (ยังไม่ใส่ logic)
    PlayerLeft:AddToggle("Plr_EnableMovement", {
        Text = "Enable Movement Modifiers",
        Default = false
    })

    PlayerLeft:AddSlider("Plr_WalkSpeed", {
        Text = "WalkSpeed",
        Min = 16,
        Max = 300,
        Default = 16,
        Rounding = 0,
        Compact = false
    })

    PlayerLeft:AddSlider("Plr_JumpPower", {
        Text = "JumpPower",
        Min = 50,
        Max = 300,
        Default = 50,
        Rounding = 0,
        Compact = false
    })

    PlayerLeft:AddToggle("Plr_InfJump", { Text = "Infinite Jump", Default = false })
    PlayerLeft:AddToggle("Plr_Fly",     { Text = "Fly",           Default = false })
    PlayerLeft:AddToggle("Plr_Noclip",  { Text = "Noclip",        Default = false })

    PlayerLeft:AddLabel("Later: add modes, keys, etc.")

    -- Player tools (ขวา)
    PlayerRight:AddLabel("Target Player")
    PlayerRight:AddInput("Plr_TargetName", {
        Text = "Username",
        Default = "",
        Placeholder = "type player name"
    })

    PlayerRight:AddButton("Teleport to Player", function()
        -- TODO: implement teleport logic
    end)

    PlayerRight:AddButton("Spectate Player", function()
        -- TODO: implement spectate logic
    end)

    PlayerRight:AddButton("Stop Spectate", function()
        -- TODO: implement stop spectate
    end)

    PlayerRight:AddDivider()
    PlayerRight:AddButton("Free Camera (Toggle)", function()
        -- TODO: implement free camera
    end)

    PlayerRight:AddLabel("You can add:")
    PlayerRight:AddLabel("- Bring player / TP all (ถ้าต้องการ)")
    PlayerRight:AddLabel("- Safe check, whitelist, etc.")

    ----------------------------------------------------------------
    -- 9. COMBAT TAB (Aimbot / Targeting Skeleton)
    ----------------------------------------------------------------
    local CombatLeft   = Tabs.Combat:AddLeftGroupbox("Aimbot")
    local CombatRight  = Tabs.Combat:AddRightGroupbox("Settings / Whitelist")

    CombatLeft:AddToggle("Aim_Enabled", {
        Text = "Enable Aimbot",
        Default = false
    })

    CombatLeft:AddDropdown("Aim_Mode", {
        Text = "Aim Mode",
        Values = { "Hold", "Toggle", "Auto" },
        Default = 1,
        Multi = false
    })

    CombatLeft:AddDropdown("Aim_TargetPart", {
        Text = "Hit Part",
        Values = { "Head", "UpperTorso", "HumanoidRootPart", "Random" },
        Default = 1,
        Multi = false
    })

    CombatLeft:AddLabel("Hit Part Percentage (Skeleton only)")
    CombatLeft:AddSlider("Aim_HeadPercent", {
        Text = "Head %",
        Min = 0,
        Max = 100,
        Default = 50,
        Rounding = 0
    })
    CombatLeft:AddSlider("Aim_TorsoPercent", {
        Text = "Torso %",
        Min = 0,
        Max = 100,
        Default = 30,
        Rounding = 0
    })
    CombatLeft:AddSlider("Aim_LimbPercent", {
        Text = "Limbs %",
        Min = 0,
        Max = 100,
        Default = 20,
        Rounding = 0
    })

    CombatRight:AddSlider("Aim_Smoothness", {
        Text = "Smoothness",
        Min = 1,
        Max = 20,
        Default = 5,
        Rounding = 1
    })

    CombatRight:AddSlider("Aim_Prediction", {
        Text = "Prediction",
        Min = 0,
        Max = 5,
        Default = 0,
        Rounding = 2
    })

    CombatRight:AddSlider("Aim_HitChance", {
        Text = "Hit Chance %",
        Min = 0,
        Max = 100,
        Default = 100,
        Rounding = 0
    })

    CombatRight:AddToggle("Aim_RandomHit", {
        Text = "Randomize Hits",
        Default = false
    })

    CombatRight:AddDivider()

    CombatRight:AddToggle("Aim_TeamCheck", {
        Text = "Team Check",
        Default = true
    })

    CombatRight:AddToggle("Aim_VisibleOnly", {
        Text = "Visible Only (WallCheck)",
        Default = true
    })

    CombatRight:AddDropdown("Aim_WhitelistPlayers", {
        Text = "Whitelist Players",
        Values = {}, -- later: fill with player list
        Multi = true
    })

    CombatRight:AddToggle("Aim_AutoFriendWhitelist", {
        Text = "Auto Whitelist Friends",
        Default = true
    })

    ----------------------------------------------------------------
    -- 10. ESP TAB (Visual / ESP Skeleton)
    ----------------------------------------------------------------
    local ESPLeft   = Tabs.ESP:AddLeftGroupbox("ESP Toggles")
    local ESPRight  = Tabs.ESP:AddRightGroupbox("ESP Settings")

    ESPLeft:AddToggle("ESP_Enabled", { Text = "Enable ESP", Default = false })
    ESPLeft:AddToggle("ESP_Box",     { Text = "Box",        Default = true })
    ESPLeft:AddToggle("ESP_Corner",  { Text = "Corner Box", Default = false })
    ESPLeft:AddToggle("ESP_Skeleton",{ Text = "Skeleton",   Default = false })
    ESPLeft:AddToggle("ESP_HeadDot", { Text = "Head Dot",   Default = false })
    ESPLeft:AddToggle("ESP_Tracers", { Text = "Tracers",    Default = false })
    ESPLeft:AddToggle("ESP_Name",    { Text = "Name Tag",   Default = true })
    ESPLeft:AddToggle("ESP_Distance",{ Text = "Distance",   Default = false })
    ESPLeft:AddToggle("ESP_Health",  { Text = "Health Bar", Default = false })

    ESPLeft:AddDivider()
    ESPLeft:AddToggle("ESP_VisibleOnly", { Text = "Visible Only", Default = false })
    ESPLeft:AddToggle("ESP_TeamCheck",   { Text = "Team Check",   Default = true })

    ESPRight:AddDropdown("ESP_ChamsPart", {
        Text = "Chams Bodypart",
        Values = {
            "Full Body",
            "Head",
            "Torso",
            "Arms",
            "Legs"
        },
        Default = 1,
        Multi = false
    })

    ESPRight:AddDropdown("ESP_WhitelistPlayers", {
        Text = "Whitelist Players",
        Values = {},
        Multi = true
    })

    ESPRight:AddToggle("ESP_AutoFriendWhitelist", {
        Text = "Auto Whitelist Friends",
        Default = true
    })

    ESPRight:AddDivider()

    ESPRight:AddSlider("ESP_TextSize", {
        Text = "Name / Info Text Size",
        Min = 10,
        Max = 24,
        Default = 14,
        Rounding = 0
    })

    ESPRight:AddSlider("ESP_TracerThickness", {
        Text = "Tracer Thickness",
        Min = 1,
        Max = 5,
        Default = 1,
        Rounding = 0
    })

    ESPRight:AddDropdown("ESP_HealthBarSide", {
        Text = "Healthbar Side",
        Values = { "Left", "Right" },
        Default = 1,
        Multi = false
    })

    ESPRight:AddLabel("Later: add color pickers for:")
    ESPRight:AddLabel("- Visible color / Hidden color")
    ESPRight:AddLabel("- Enemy / Team color")

    ----------------------------------------------------------------
    -- 11. MISC TAB (Anti-AFK / Rejoin / Server Hop Skeleton)
    ----------------------------------------------------------------
    local MiscLeft   = Tabs.Misc:AddLeftGroupbox("AFK / Reconnect")
    local MiscRight  = Tabs.Misc:AddRightGroupbox("Server Tools")

    MiscLeft:AddToggle("Misc_AntiAFK", {
        Text = "Anti AFK",
        Default = true
    })

    MiscLeft:AddToggle("Misc_AutoRejoin", {
        Text = "Auto Rejoin on Disconnect",
        Default = false
    })

    MiscLeft:AddButton("Rejoin Now", function()
        -- TODO: implement rejoin
    end)

    MiscRight:AddDropdown("Misc_ServerHopMode", {
        Text = "Server Hop Mode",
        Values = { "Low Player", "Random", "High Ping", "Custom" },
        Default = 1,
        Multi = false
    })

    MiscRight:AddButton("Server Hop", function()
        -- TODO: implement server hop
    end)

    MiscRight:AddLabel("Later: add advanced filters")
    MiscRight:AddLabel("- Region, Ping, Player count, etc.")

    ----------------------------------------------------------------
    -- 12. GAME TAB (Game Module Skeleton)
    ----------------------------------------------------------------
    local GameLeft   = Tabs.Game:AddLeftGroupbox("Game Detection")
    local GameRight  = Tabs.Game:AddRightGroupbox("Game Module")

    GameLeft:AddLabel("Detected Game: (fill later)")
    GameLeft:AddLabel("PlaceId: " .. tostring(placeId))

    GameLeft:AddLabel("You can later:")
    GameLeft:AddLabel("- Map PlaceId -> GameName")
    GameLeft:AddLabel("- Show support status for each game")

    GameRight:AddLabel("Game-specific Module Loader")
    GameRight:AddButton("Load Game Module", function()
        -- TODO: implement load module by PlaceId (Exec.HttpGet)
    end)

    GameRight:AddLabel("If no module: use Universal fallback")

    ----------------------------------------------------------------
    -- 13. SETTINGS TAB (Theme / Config / Unload Skeleton)
    ----------------------------------------------------------------
    local SettingsLeft  = Tabs.Settings:AddLeftGroupbox("Theme / UI")
    local SettingsRight = Tabs.Settings:AddRightGroupbox("Config / Script")

    SettingsLeft:AddLabel("Theme / UI Settings")
    SettingsLeft:AddLabel("Use ThemeManager to build presets here.")

    if ThemeManager and ThemeManager.ApplyToTab then
        ThemeManager:ApplyToTab(Tabs.Settings)
    end

    SettingsRight:AddLabel("Config / Save Manager")
    if SaveManager and SaveManager.BuildConfigSection then
        SaveManager:BuildConfigSection(Tabs.Settings)
    end

    SettingsRight:AddDivider()

    SettingsRight:AddButton("Unload Script", function()
        if Library and Library.Unload then
            Library:Unload()
        end
    end)

    SettingsRight:AddButton("Panic (Turn Off All Features)", function()
        -- TODO: set all toggles false / cleanup
    end)

    SettingsRight:AddLabel("Later: add export/import config via clipboard")

    ----------------------------------------------------------------
    -- 14. Simple Notification
    ----------------------------------------------------------------
    StarterGui:SetCore("SendNotification", {
        Title    = "BxB.ware Loaded",
        Text     = "Main Hub UI Skeleton Loaded",
        Duration = 5
    })
end
