--[[
    BxB.ware | Main Hub (Universal)
    Author: BXMQZ
    UI Library: Obsidian / Linoria
]]

return function(Exec, UserData, CheckToken)
    ----------------------------------------------------------------
    -- 1. Security Handshake (2-Factor Check)
    ----------------------------------------------------------------
    local secretSalt = "BxB_SUPER_SECRET_SALT_CHANGE_THIS" -- ** แก้ให้ตรงกับ Key_UI **
    local datePart = os.date("%Y%m%d")
    local expectedToken = secretSalt .. "_" .. datePart

    if CheckToken ~= expectedToken then
        warn("[BxB Security] Invalid Security Token!")
        if game.Players.LocalPlayer then
            game.Players.LocalPlayer:Kick("Security Breach: Invalid Token. Please re-login via Key UI.")
        end
        return
    end

    if type(UserData) ~= "table" or not UserData.key then
        warn("[BxB Security] Invalid User Data!")
        return
    end

    ----------------------------------------------------------------
    -- 2. Services & Variables
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")
    
    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- Load Library
    local Library = loadstring(Exec.HttpGet("https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet("https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/addons/ThemeManager.lua"))()
    local SaveManager = loadstring(Exec.HttpGet("https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/addons/SaveManager.lua"))()

    ----------------------------------------------------------------
    -- 3. UI Construction
    ----------------------------------------------------------------
    local Window = Library:CreateWindow({
        Title = "",
        Icon = 84528813312016, -- Custom Icon ID
        Size = UDim2.fromOffset(720, 600),  
        Center = true,
        AutoShow = true,
        Resizable = true,  
        Compact = true
    })

    local Tabs = {
        Info     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "info", Description = "Key Status / Info"}),
        Player   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "user", Description = "Player Tool"}),
        Combat   = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "swords", Description = "Combat Client"}),
        ESP      = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "eye", Description = "ESP Client"}),
        Misc     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "box", Description = "Misc Client"}),
        Game     = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "joystick", Description = "Game Module"}),
        Settings = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware | Premium</font></b>', Icon = "settings", Description = "UI/UX Settings"}),
    }

    ----------------------------------------------------------------
    -- TAB: Info
    ----------------------------------------------------------------
    local InfoGroup = Tabs.Info:AddLeftGroupbox("User Information")
    InfoGroup:AddLabel("Key: " .. (UserData.key or "Unknown"))
    InfoGroup:AddLabel("Status: " .. (UserData.status or "Active"))
    InfoGroup:AddLabel("Role: " .. (UserData.role or "User"))
    InfoGroup:AddLabel("Expire: " .. (UserData.expire and os.date("%c", UserData.expire) or "Never"))
    
    local SystemGroup = Tabs.Info:AddRightGroupbox("System")
    SystemGroup:AddLabel("Game ID: " .. tostring(game.PlaceId))
    SystemGroup:AddLabel("Executor: " .. (identifyexecutor and identifyexecutor() or "Unknown"))
    SystemGroup:AddButton("Unload Script", function() Library:Unload() end)

    ----------------------------------------------------------------
    -- TAB: Player
    ----------------------------------------------------------------
    local PlayerMain = Tabs.Player:AddLeftGroupbox("Movement")
    
    PlayerMain:AddSlider('WalkSpeed', {
        Text = 'WalkSpeed',
        Default = 16,
        Min = 16,
        Max = 500,
        Rounding = 1,
        Compact = false,
        Callback = function(Value)
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = Value
            end
        end
    })

    PlayerMain:AddSlider('JumpPower', {
        Text = 'JumpPower',
        Default = 50,
        Min = 50,
        Max = 500,
        Rounding = 1,
        Callback = function(Value)
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.UseJumpPower = true
                LocalPlayer.Character.Humanoid.JumpPower = Value
            end
        end
    })

    PlayerMain:AddToggle('InfiniteJump', {
        Text = 'Infinite Jump',
        Default = false,
        Tooltip = 'Jump in the air',
    })

    -- Logic for Infinite Jump
    game:GetService("UserInputService").JumpRequest:Connect(function()
        if Toggles.InfiniteJump.Value then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid:ChangeState("Jumping")
            end
        end
    end)

    ----------------------------------------------------------------
    -- TAB: Combat (Universal)
    ----------------------------------------------------------------
    local CombatMain = Tabs.Combat:AddLeftGroupbox("Hitbox Expander")
    
    CombatMain:AddToggle('HitboxExpander', { Text = 'Enable Hitbox', Default = false })
    CombatMain:AddSlider('HitboxSize', { Text = 'Head Size', Default = 1, Min = 1, Max = 20, Rounding = 1 })
    CombatMain:AddDropdown('HitboxPart', { Values = { 'Head', 'HumanoidRootPart' }, Default = 1, Multi = false, Text = 'Target Part' })

    -- Logic for Hitbox
    task.spawn(function()
        while true do
            task.wait(0.5)
            if Toggles.HitboxExpander.Value then
                local size = Options.HitboxSize.Value
                local part = Options.HitboxPart.Value
                
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild(part) then
                        local p = plr.Character[part]
                        p.Size = Vector3.new(size, size, size)
                        p.Transparency = 0.5
                        p.CanCollide = false
                    end
                end
            end
        end
    end)

    ----------------------------------------------------------------
    -- TAB: ESP (Universal)
    ----------------------------------------------------------------
    local ESPGroup = Tabs.ESP:AddLeftGroupbox("Visuals")
    
    ESPGroup:AddToggle('ESP_Enabled', { Text = 'Enable ESP', Default = false })
    ESPGroup:AddToggle('ESP_TeamCheck', { Text = 'Team Check', Default = true })
    ESPGroup:AddColorPicker('ESP_Color', { Default = Color3.fromRGB(255, 0, 0), Title = 'ESP Color' })

    -- Simple ESP Logic (Highlight)
    local ESP_Holder = Instance.new("Folder", game.CoreGui)
    ESP_Holder.Name = "BxB_ESP_Holder"

    local function UpdateESP()
        ESP_Holder:ClearAllChildren()
        if not Toggles.ESP_Enabled.Value then return end

        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                if Toggles.ESP_TeamCheck.Value and plr.Team == LocalPlayer.Team then
                    continue -- Skip teammates
                end
                
                local highlight = Instance.new("Highlight")
                highlight.Adornee = plr.Character
                highlight.Parent = ESP_Holder
                highlight.FillColor = Options.ESP_Color.Value
                highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                highlight.FillTransparency = 0.5
            end
        end
    end

    RunService.RenderStepped:Connect(function()
        if math.floor(tick() % 2) == 0 then -- Update every second roughly, not every frame to save FPS
             UpdateESP()
        end
    end)

    ----------------------------------------------------------------
    -- TAB: Game (Auto Detection)
    ----------------------------------------------------------------
    local GameGroup = Tabs.Game:AddLeftGroupbox("Detected Game")
    local PlaceID = game.PlaceId
    
    local function loadExternalScript(url)
        local content = Exec.HttpGet(url)
        local func = loadstring(content)
        if func then func() end
    end

    if PlaceID == 2753915549 or PlaceID == 4442272183 or PlaceID == 7449423635 then -- Blox Fruits
        GameGroup:AddLabel("Game: Blox Fruits")
        GameGroup:AddButton("Load Blox Fruits Script", function()
            -- ใส่ Link Script ของ Blox Fruits
            print("Loading Blox Fruits...")
        end)
    elseif PlaceID == 286090429 then -- Arsenal
        GameGroup:AddLabel("Game: Arsenal")
        GameGroup:AddButton("Load Arsenal Script", function()
            print("Loading Arsenal...")
        end)
    else
        GameGroup:AddLabel("Game: Unknown / Universal")
        GameGroup:AddLabel("Universal features are active.")
        GameGroup:AddButton("Force Load Blox Fruits (Manual)", function()
             -- Manual Load
        end)
    end

    ----------------------------------------------------------------
    -- TAB: Misc
    ----------------------------------------------------------------
    local MiscGroup = Tabs.Misc:AddLeftGroupbox("Tools")
    
    MiscGroup:AddButton("Fullbright", function()
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    end)

    MiscGroup:AddButton("FPS Boost (Low Graphics)", function()
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") and not v:IsA("MeshPart") then
                v.Material = Enum.Material.SmoothPlastic
            elseif v:IsA("Texture") or v:IsA("Decal") then
                v:Destroy()
            end
        end
    end)

    ----------------------------------------------------------------
    -- TAB: Settings
    ----------------------------------------------------------------
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    
    ThemeManager:SetFolder("BxB_Ware")
    SaveManager:SetFolder("BxB_Ware/Configs")
    
    SaveManager:BuildConfigSection(Tabs.Settings)
    ThemeManager:ApplyToTab(Tabs.Settings)

    -- Select Default Tab
    Window:SelectTab(1)
    
    -- Notification
    Library:Notify("Welcome to BxB.ware | Premium", 5)
    Library:Notify("Loaded successfully!", 3)
end
