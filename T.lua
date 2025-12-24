--============================================================================================
-- [BxB.ware] Universal MainHub Script
-- Optimized & Designed by: Diablo (AI Assistant)
--============================================================================================

--/////////////////////////////////////////////////////////////////////////////////
-- 0. SERVICES & VARIABLES
--/////////////////////////////////////////////////////////////////////////////////
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")
local GuiService         = game:GetService("GuiService")
local TeleportService    = game:GetService("TeleportService")
local Lighting           = game:GetService("Lighting")
local HttpService        = game:GetService("HttpService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterGui         = game:GetService("StarterGui")
local Debris             = game:GetService("Debris")
local TweenService       = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

-- Table to hold all connections for clean disconnect on unload
local Connections = {}

-- Helper to add connection
local function AddConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

-- Helper to get Character safely
local function getCharacter()
    local plr = LocalPlayer
    if not plr then return end
    local char = plr.Character or plr.CharacterAdded:Wait()
    return char
end

-- Helper to get Humanoid safely
local function getHumanoid()
    local char = getCharacter()
    if not char then return end
    return char:FindFirstChildOfClass("Humanoid")
end

-- Helper to get RootPart safely
local function getRootPart()
    local char = getCharacter()
    if not char then return end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

--/////////////////////////////////////////////////////////////////////////////////
-- 1. SECURITY & KEY VERIFICATION
--/////////////////////////////////////////////////////////////////////////////////
-- Must match the secret in KeyUI.lua
local SECRET_PEPPER = "BxB.ware-Universal@#$)_%@#^()$@%_)+%(@"

local bit = bit32 or bit

local function fnv1a32(str)
    local hash = 0x811C9DC5
    for i = 1, #str do
        hash = bit.bxor(hash, str:byte(i))
        hash = (hash * 0x01000193) % 0x100000000
    end
    return hash
end

local function buildExpectedToken(keydata)
    local k    = tostring(keydata.key or keydata.Key or "")
    local hw   = tostring(keydata.hwid_hash or keydata.HWID or "no-hwid")
    local role = tostring(keydata.role or "user")
    local datePart = os.date("%Y%m%d")

    local raw = table.concat({
        SECRET_PEPPER,
        k,
        hw,
        role,
        datePart,
        tostring(#k),
    }, "|")

    local h = fnv1a32(raw)
    return ("%08X"):format(h)
end

--/////////////////////////////////////////////////////////////////////////////////
-- 2. ROLE & PERMISSION SYSTEM
--/////////////////////////////////////////////////////////////////////////////////
local RolePriority = {
    free    = 0,
    user    = 1,
    premium = 2,
    vip     = 3,
    staff   = 4,
    owner   = 5,
}

local function NormalizeRole(role)
    role = tostring(role or ""):lower()
    if RolePriority[role] then
        return role
    end
    return "free"
end

local function GetRoleLabel(role)
    role = NormalizeRole(role)
    if role == "free" then
        return '<font color="#A0A0A0">Free</font>'
    elseif role == "user" then
        return '<font color="#FFFFFF">User</font>'
    elseif role == "premium" then
        return '<font color="#FFD700">Premium</font>'
    elseif role == "vip" then
        return '<font color="#FF00FF">VIP</font>'
    elseif role == "staff" then
        return '<font color="#00FFFF">Staff</font>'
    elseif role == "owner" then
        return '<font color="#FF4444">Owner</font>'
    end
    return '<font color="#A0A0A0">Unknown</font>'
end

local function MarkRisky(text)
    return text .. ' <font color="#FF5555" size="10">[RISKY]</font>'
end

--/////////////////////////////////////////////////////////////////////////////////
-- 3. UTILITY FUNCTIONS
--/////////////////////////////////////////////////////////////////////////////////

local function formatUnixTime(ts)
    if not ts or ts <= 0 then return "Lifetime" end
    local dt = os.date("*t", ts)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec)
end

local function formatTimeLeft(expireTs)
    if not expireTs or expireTs <= 0 then return "Lifetime" end
    local now = os.time()
    local diff = expireTs - now
    if diff <= 0 then return "Expired" end
    local d = math.floor(diff / 86400) diff = diff % 86400
    local h = math.floor(diff / 3600) diff = diff % 3600
    local m = math.floor(diff / 60) local s = diff % 60
    if d > 0 then return string.format("%dd %02dh %02dm %02ds", d, h, m, s)
    else return string.format("%02dh %02dm %02ds", h, m, s) end
end

local function safeRichLabel(groupbox, text)
    local lbl = groupbox:AddLabel(text, true)
    if lbl and lbl.TextLabel then
        lbl.TextLabel.RichText = true
    end
    return lbl
end

--/////////////////////////////////////////////////////////////////////////////////
-- 4. MAIN HUB LOGIC
--/////////////////////////////////////////////////////////////////////////////////
local function MainHub(Exec, keydata, authToken)
    
    -- 4.1 Input Validation
    if type(Exec) ~= "table" or type(Exec.HttpGet) ~= "function" then
        warn("[MainHub] Exec invalid")
        return
    end

    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then
        warn("[MainHub] keydata invalid")
        return
    end

    local expected = buildExpectedToken(keydata)
    if authToken ~= expected then
        warn("[MainHub] Invalid auth token. Access Denied.")
        return
    end

    -- 4.2 Initialize Drawing Containers
    -- Crosshair
    local crosshairLines = nil
    
    -- Aimbot Visuals
    local AimbotFOVCircle = nil
    local AimbotSnapLine = nil
    
    -- ESP Containers
    local espDrawings = {}
    local itemDrawings = {}
    local radarDrawings = {
        Background = nil,
        Border = nil,
        Center = nil,
        Blips = {}
    }

    -- Normalize Role
    keydata.role = NormalizeRole(keydata.role)

    -- 4.3 Load Library (Obsidian)
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library      = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    local Options = Library.Options
    local Toggles = Library.Toggles

    -- Helper for Notifications
    local function NotifyAction(feature, state)
        if Toggles.ForceNotify and Toggles.ForceNotify.Value then
            local s = state and "Enabled" or "Disabled"
            Library:Notify(string.format("%s: %s", feature, s), 1.5)
        end
    end

    -- Create Window
    local Window = Library:CreateWindow({
        Title  = "BxB.ware",
        Footer = '<b><font color="#B563FF">BxB.ware | Universal | Game Module/Client</font></b>',
        Icon = "84528813312016",
        Center   = true,
        Size     = UDim2.fromOffset(720, 600),
        AutoShow         = true,
        Resizable        = true,
        NotifySide       = "Right",
        ShowCustomCursor = false,
        CornerRadius = 4,
        MobileButtonsSide = "Left",
        DisableSearch = false,
        GlobalSearch  = true,
        UnlockMouseWhileOpen = false,
        Compact              = true,
        EnableSidebarResize  = true,
        SidebarHighlightCallback = function(Divider, isActive)
            Divider.BackgroundColor3 = isActive and Library.Scheme.AccentColor or Library.Scheme.OutlineColor
            Divider.BackgroundTransparency = isActive and 0 or 0.4
        end,
    })

    -- Create Tabs
    local Tabs = {
        Info = Window:AddTab({ Name = "Info", Icon = "info", Description = "Key / Script / System info" }),
        Player = Window:AddTab({ Name = "Player", Icon = "user", Description = "Movement / Teleport / View" }),
        ESP = Window:AddTab({ Name = "ESP & Visuals", Icon = "eye", Description = "Player ESP / Visual settings" }),
        Combat = Window:AddTab({ Name = "Combat & Aimbot", Icon = "target", Description = "Aimbot / target selection" }),
        Server = Window:AddTab({ Name = "Server", Icon = "server", Description = "Hop / Rejoin / Anti-AFK" }),
        Misc = Window:AddTab({ Name = "Misc & System", Icon = "joystick", Description = "Utilities / Panic / System" }),
        Settings = Window:AddTab({ Name = "Settings", Icon = "settings", Description = "Theme / Config / Keybinds" }),
    }

    local function safeAddRightGroupbox(tab, name, icon)
        if tab and typeof(tab) == "table" then
            if type(tab.AddRightGroupbox) == "function" then
                return tab:AddRightGroupbox(name, icon)
            elseif type(tab.AddGroupbox) == "function" then
                return tab:AddGroupbox({ Side = 2, Name = name, IconName = icon })
            end
        end
        return nil
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: INFO
    --/////////////////////////////////////////////////////////////////////////////////
    local InfoTab = Tabs.Info
    local KeyBox = InfoTab:AddLeftGroupbox("Key Info", "key-round")

    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()

    local rawKey = tostring(keydata.key or "N/A")
    local maskedKey = (#rawKey > 4) and string.format("%s-****%s", rawKey:sub(1, 4), rawKey:sub(-3)) or rawKey
    local KeyLabel = safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    local RoleLabel = safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", GetRoleLabel(keydata.role)))
    local StatusLabel = safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", tostring(keydata.status or "active")))
    local HWIDLabel = safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    local NoteLabel = safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", tostring(keydata.note or "-")))
    local CreatedLabel = safeRichLabel(KeyBox, "<b>Created at:</b> Loading...")
    local ExpireLabel = safeRichLabel(KeyBox, "<b>Expire:</b> Loading...")
    local TimeLeftLabel = safeRichLabel(KeyBox, "<b>Time left:</b> Loading...")

    -- Async Key Info Update
    task.spawn(function()
        local remoteKeyData = nil
        pcall(function()
            local url = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/main/Key_System/data.json"
            local dataStr = game:HttpGet(url)
            if type(dataStr) == "string" and #dataStr > 0 then
                local ok, decoded = pcall(function() return HttpService:JSONDecode(dataStr) end)
                if ok and decoded and decoded.keys then
                    for _, entry in ipairs(decoded.keys) do
                        if tostring(entry.key) == rawKey or tostring(entry.key) == tostring(keydata.key) then
                            remoteKeyData = entry 
                            break
                        end
                    end
                end
            end
        end)

        if remoteKeyData then
            if remoteKeyData.role then RoleLabel.TextLabel.Text = string.format("<b>Role:</b> %s", GetRoleLabel(remoteKeyData.role)) end
            if remoteKeyData.status then StatusLabel.TextLabel.Text = string.format("<b>Status:</b> %s", tostring(remoteKeyData.status)) end
            if remoteKeyData.note and remoteKeyData.note ~= "" then NoteLabel.TextLabel.Text = string.format("<b>Note:</b> %s", tostring(remoteKeyData.note)) end
            if remoteKeyData.hwid_hash then HWIDLabel.TextLabel.Text = string.format("<b>HWID Hash:</b> %s", tostring(remoteKeyData.hwid_hash)) end
        end

        local createdAtText
        if remoteKeyData and remoteKeyData.timestamp then 
            createdAtText = tostring(remoteKeyData.timestamp)
        elseif keydata.timestamp and keydata.timestamp > 0 then 
            createdAtText = formatUnixTime(keydata.timestamp)
        elseif keydata.created_at then 
            createdAtText = tostring(keydata.created_at)
        else 
            createdAtText = "Unknown" 
        end

        local expireTs = tonumber(keydata.expire) or 0
        local expireDisplay = (remoteKeyData and remoteKeyData.expire) and tostring(remoteKeyData.expire) or formatUnixTime(expireTs)
        local timeLeftDisplay = (remoteKeyData and remoteKeyData.expire) and tostring(remoteKeyData.expire) or formatTimeLeft(expireTs)

        CreatedLabel.TextLabel.Text = string.format("<b>Created at:</b> %s", createdAtText)
        ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", expireDisplay)
        TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", timeLeftDisplay)

        while true do
            task.wait(1)
            if remoteKeyData and remoteKeyData.expire then break end
            local nowExpire = tonumber(keydata.expire) or expireTs
            local leftStr = formatTimeLeft(nowExpire)
            if TimeLeftLabel and TimeLeftLabel.TextLabel then 
                TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", leftStr) 
            end
        end
    end)

    KeyBox:AddDivider()
    KeyBox:AddButton("Copy Key Info", function()
        local infoText = string.format("Key: %s\nRole: %s", rawKey, tostring(keydata.role))
        pcall(function() 
            if setclipboard then 
                setclipboard(infoText) 
                Library:Notify("Key info copied to clipboard", 2) 
            else 
                Library:Notify("Clipboard copy not supported", 2) 
            end 
        end)
    end)

    local GameBox = safeAddRightGroupbox(InfoTab, "Game Info", "info")
    safeRichLabel(GameBox, '<font size="14"><b>Game / Server Information</b></font>')
    GameBox:AddDivider()

    local placeId = game.PlaceId or 0
    local jobId   = tostring(game.JobId or "N/A")

    local GameNameLabel   = safeRichLabel(GameBox, "<b>Game:</b> Loading...")
    local PlaceIdLabel    = safeRichLabel(GameBox, string.format("<b>PlaceId:</b> %d", placeId))
    local JobIdLabel      = safeRichLabel(GameBox, string.format("<b>JobId:</b> %s", jobId))
    local PlayersLabel    = safeRichLabel(GameBox, "<b>Players:</b> -/-")
    
    task.spawn(function()
        local gameName = "Unknown Place"
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, placeId)
        if ok and info and info.Name then gameName = info.Name end
        if GameNameLabel and GameNameLabel.TextLabel then 
            GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", gameName) 
        end
    end)

    local function updatePlayersLabel()
        local current = #Players:GetPlayers()
        local max = Players.MaxPlayers or "-"
        if PlayersLabel and PlayersLabel.TextLabel then 
            PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d / %s", current, tostring(max)) 
        end
    end
    updatePlayersLabel()
    AddConnection(Players.PlayerAdded:Connect(updatePlayersLabel))
    AddConnection(Players.PlayerRemoving:Connect(updatePlayersLabel))


    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: PLAYER
    --/////////////////////////////////////////////////////////////////////////////////
    local PlayerTab = Tabs.Player
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    -- Walk Speed
    local defaultWalkSpeed = 16
    local walkSpeedEnabled = false
    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = defaultWalkSpeed, Min = 0, Max = 300, Rounding = 0, Compact = false,
        Callback = function(value) 
            if not walkSpeedEnabled then return end 
            local hum = getHumanoid() 
            if hum then hum.WalkSpeed = value end 
        end
    })
    WalkSpeedSlider:SetDisabled(true) -- Default locked

    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state
        if WalkSpeedSlider.SetDisabled then WalkSpeedSlider:SetDisabled(not state) end
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = state and WalkSpeedSlider.Value or defaultWalkSpeed end
        NotifyAction("WalkSpeed", state)
    end)

    MoveBox:AddButton("Reset WalkSpeed", function()
        local hum = getHumanoid() 
        if hum then hum.WalkSpeed = defaultWalkSpeed end
        WalkSpeedSlider:SetValue(defaultWalkSpeed) 
        WalkSpeedToggle:SetValue(false)
    end)

    -- Auto Sprint
    local AutoSprintToggle = MoveBox:AddToggle("bxw_autosprint", { Text = "Auto Sprint (Shift)", Default = false })
    local sprintConn
    AutoSprintToggle:OnChanged(function(state)
        if state then
            sprintConn = AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                if input.KeyCode == Enum.KeyCode.LeftShift then
                    local hum = getHumanoid() 
                    if hum then hum.WalkSpeed = WalkSpeedSlider.Value + 10 end
                end
            end))
            AddConnection(UserInputService.InputEnded:Connect(function(input)
                if input.KeyCode == Enum.KeyCode.LeftShift then
                    local hum = getHumanoid() 
                    if hum then hum.WalkSpeed = walkSpeedEnabled and WalkSpeedSlider.Value or defaultWalkSpeed end
                end
            end))
        else 
            if sprintConn then sprintConn:Disconnect() sprintConn = nil end 
        end
        NotifyAction("Auto Sprint", state)
    end)
    
    -- Jump Power
    local defaultJumpPower = 50
    local jumpPowerEnabled = false
    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = defaultJumpPower, Min = 0, Max = 300, Rounding = 0, Compact = false,
        Callback = function(value) 
            if not jumpPowerEnabled then return end 
            local hum = getHumanoid() 
            if hum then 
                pcall(function() hum.UseJumpPower = true end) 
                hum.JumpPower = value 
            end 
        end
    })
    JumpPowerSlider:SetDisabled(true) -- Default locked

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        if JumpPowerSlider.SetDisabled then JumpPowerSlider:SetDisabled(not state) end
        local hum = getHumanoid()
        if hum then 
            pcall(function() hum.UseJumpPower = true end) 
            hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower 
        end
        NotifyAction("JumpPower", state)
    end)

    MoveBox:AddButton("Reset JumpPower", function()
        local hum = getHumanoid() 
        if hum then 
            pcall(function() hum.UseJumpPower = true end) 
            hum.JumpPower = defaultJumpPower 
        end
        JumpPowerSlider:SetValue(defaultJumpPower) 
        JumpPowerToggle:SetValue(false)
    end)

    -- Hip Height
    local HipHeightToggle = MoveBox:AddToggle("bxw_hipheight_toggle", { Text = "Enable Hip Height", Default = false })
    local HipHeightSlider = MoveBox:AddSlider("bxw_hipheight", { Text = "Hip Height", Default = 0, Min = 0, Max = 50, Rounding = 1, Compact = false,
        Callback = function(value) 
            if not HipHeightToggle.Value then return end 
            local hum = getHumanoid() 
            if hum then hum.HipHeight = value end 
        end
    })
    HipHeightSlider:SetDisabled(true)

    HipHeightToggle:OnChanged(function(state)
        HipHeightSlider:SetDisabled(not state)
        local hum = getHumanoid() 
        if hum then hum.HipHeight = state and HipHeightSlider.Value or 0 end
        NotifyAction("Hip Height", state)
    end)

    -- Presets
    local MovePresetDropdown = MoveBox:AddDropdown("bxw_move_preset", { Text = "Movement Preset", Values = { "Default", "Normal", "Fast", "Ultra" }, Default = "Default", Multi = false })
    MovePresetDropdown:OnChanged(function(value)
        if value == "Default" then 
            WalkSpeedSlider:SetValue(defaultWalkSpeed) JumpPowerSlider:SetValue(defaultJumpPower) WalkSpeedToggle:SetValue(false) JumpPowerToggle:SetValue(false)
        elseif value == "Normal" then 
            WalkSpeedSlider:SetValue(20) JumpPowerSlider:SetValue(60) WalkSpeedToggle:SetValue(true) JumpPowerToggle:SetValue(true)
        elseif value == "Fast" then 
            WalkSpeedSlider:SetValue(30) JumpPowerSlider:SetValue(80) WalkSpeedToggle:SetValue(true) JumpPowerToggle:SetValue(true)
        elseif value == "Ultra" then 
            WalkSpeedSlider:SetValue(50) JumpPowerSlider:SetValue(100) WalkSpeedToggle:SetValue(true) JumpPowerToggle:SetValue(true) 
        end
    end)

    -- No Fall Damage
    local NoFallToggle = MoveBox:AddToggle("bxw_nofall", { Text = "No Fall Damage", Default = false })
    local noFallConn
    NoFallToggle:OnChanged(function(state)
        if state then
            noFallConn = AddConnection(RunService.Stepped:Connect(function()
                local hum = getHumanoid() 
                if hum then hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics) end
            end))
        else 
            if noFallConn then noFallConn:Disconnect() noFallConn = nil end 
        end
        NotifyAction("No Fall Damage", state)
    end)

    MoveBox:AddDivider()

    -- Infinite Jump
    local infJumpConn
    local InfJumpToggle = MoveBox:AddToggle("bxw_infjump", { Text = "Infinite Jump", Default = false })
    InfJumpToggle:OnChanged(function(state)
        if state then
            if infJumpConn then infJumpConn:Disconnect() end
            infJumpConn = AddConnection(UserInputService.JumpRequest:Connect(function() 
                local hum = getHumanoid() 
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end 
            end))
        else 
            if infJumpConn then infJumpConn:Disconnect() infJumpConn = nil end 
        end
        NotifyAction("Infinite Jump", state)
    end)

    -- Fly (Smooth)
    local flyConn, flyBV, flyBG
    local flyEnabled = false
    local flySpeed = 60
    local FlyToggle = MoveBox:AddToggle("bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = flySpeed, Min = 1, Max = 300, Rounding = 0, Compact = false, Callback = function(value) flySpeed = value end })
    FlySpeedSlider:SetDisabled(true)

    FlyToggle:OnChanged(function(state)
        flyEnabled = state
        FlySpeedSlider:SetDisabled(not state)
        local root = getRootPart() 
        local hum = getHumanoid() 
        local cam = Workspace.CurrentCamera
        
        if not state then
            if flyConn then flyConn:Disconnect() flyConn = nil end
            if flyBV then flyBV:Destroy() flyBV = nil end
            if flyBG then flyBG:Destroy() flyBG = nil end
            if hum then hum.PlatformStand = false end
            NotifyAction("Fly", false)
            return
        end
        
        if not (root and hum and cam) then 
            Library:Notify("Cannot start fly: character not loaded", 3) 
            FlyToggle:SetValue(false) 
            return 
        end
        
        hum.PlatformStand = true
        flyBV = Instance.new("BodyVelocity") 
        flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5) 
        flyBV.Velocity = Vector3.zero 
        flyBV.P = 9e4 
        flyBV.Parent = root
        
        flyBG = Instance.new("BodyGyro") 
        flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9) 
        flyBG.CFrame = root.CFrame 
        flyBG.P = 9e4 
        flyBG.Parent = root
        
        if flyConn then flyConn:Disconnect() end
        flyConn = AddConnection(RunService.RenderStepped:Connect(function()
            if not flyEnabled then return end
            local root = getRootPart() 
            local hum = getHumanoid() 
            local cam = Workspace.CurrentCamera
            
            if not (root and hum and cam and flyBV and flyBG) then return end
            
            local moveDir = Vector3.new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            
            if moveDir.Magnitude > 0 then 
                moveDir = moveDir.Unit 
                flyBV.Velocity = moveDir * flySpeed 
            else 
                flyBV.Velocity = Vector3.zero 
            end
            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
        NotifyAction("Fly", true)
    end)

    -- Noclip
    local noclipConn
    local NoclipToggle = MoveBox:AddToggle("bxw_noclip", { Text = MarkRisky("Noclip"), Default = false })
    NoclipToggle:OnChanged(function(state)
        if not state then
            if noclipConn then noclipConn:Disconnect() noclipConn = nil end
            local char = getCharacter()
            if char then 
                for _, part in ipairs(char:GetDescendants()) do 
                    if part:IsA("BasePart") then part.CanCollide = true end 
                end 
            end
            NotifyAction("Noclip", false)
            return
        end
        if noclipConn then noclipConn:Disconnect() end
        noclipConn = AddConnection(RunService.Stepped:Connect(function()
            local char = getCharacter()
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do 
                if part:IsA("BasePart") then part.CanCollide = false end 
            end
        end))
        NotifyAction("Noclip", true)
    end)

    -- Teleport & Utility
    local UtilBox = safeAddRightGroupbox(PlayerTab, "Teleport / Utility", "map")
    local playerNames = {}
    local function refreshPlayerList()
        table.clear(playerNames)
        for _, plr in ipairs(Players:GetPlayers()) do 
            if plr ~= LocalPlayer then table.insert(playerNames, plr.Name) end 
        end
    end
    refreshPlayerList()
    
    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = playerNames, Default = "", Multi = false, AllowNull = true })
    UtilBox:AddButton("Refresh Player List", function() refreshPlayerList() TeleportDropdown:SetValues(playerNames) end)
    
    UtilBox:AddButton("Teleport", function()
        local targetName = TeleportDropdown.Value
        if not targetName or targetName == "" then Library:Notify("Select player first", 2) return end
        local target = Players:FindFirstChild(targetName)
        local root = getRootPart()
        if not target or not root then Library:Notify("Target/Your character not found", 2) return end
        local tChar = target.Character
        local tRoot = tChar and (tChar:FindFirstChild("HumanoidRootPart") or tChar:FindFirstChild("Torso"))
        if not tRoot then Library:Notify("Target has no root part", 2) return end
        root.CFrame = tRoot.CFrame + Vector3.new(0, 3, 0)
    end)

    local ClickTPToggle = UtilBox:AddToggle("bxw_clicktp", { Text = "Ctrl + Click TP", Default = false })
    local clickTPConn
    ClickTPToggle:OnChanged(function(state)
        if state then
            clickTPConn = AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                    local mouse = LocalPlayer:GetMouse()
                    local root = getRootPart()
                    if mouse.Target and root then 
                        root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0)) 
                    end
                end
            end))
        else 
            if clickTPConn then clickTPConn:Disconnect() clickTPConn = nil end 
        end
        NotifyAction("Click TP", state)
    end)

    UtilBox:AddDivider()
    
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = playerNames, Default = "", Multi = false, AllowNull = true })
    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", { Text = "Spectate Player", Default = false })
    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if not cam then return end
        if state then
            local name = SpectateDropdown.Value
            if not name or name == "" then Library:Notify("Select player to spectate", 2) SpectateToggle:SetValue(false) return end
            local target = Players:FindFirstChild(name)
            if not target or not target.Character then Library:Notify("Target not found", 2) SpectateToggle:SetValue(false) return end
            local hum = target.Character:FindFirstChildOfClass("Humanoid")
            if not hum then Library:Notify("Target humanoid not found", 2) SpectateToggle:SetValue(false) return end
            cam.CameraSubject = hum
        else
            local hum = getHumanoid() 
            if hum then cam.CameraSubject = hum end
        end
        NotifyAction("Spectate", state)
    end)

    UtilBox:AddButton("Sit", function() 
        local hum = getHumanoid() 
        if hum then hum.Sit = true end 
    end)

    UtilBox:AddDivider()
    UtilBox:AddLabel("Waypoints")
    local savedWaypoints = {} 
    local savedNames = {}
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", Multi = false, AllowNull = true })
    
    UtilBox:AddButton("Set Waypoint", function()
        local root = getRootPart()
        if not root then Library:Notify("Character not loaded", 2) return end
        local name = "WP" .. tostring(#savedNames + 1)
        savedWaypoints[name] = root.CFrame
        table.insert(savedNames, name)
        WaypointDropdown:SetValues(savedNames)
        Library:Notify("Saved waypoint " .. name, 2)
    end)

    UtilBox:AddButton("Teleport to Waypoint", function()
        local sel = WaypointDropdown.Value
        if not sel or sel == "" then Library:Notify("Select a waypoint first", 2) return end
        local cf = savedWaypoints[sel]
        local root = getRootPart()
        if cf and root then 
            root.CFrame = cf + Vector3.new(0, 3, 0) 
            Library:Notify("Teleported to " .. sel, 2) 
        else 
            Library:Notify("Waypoint or character missing", 2) 
        end
    end)

    -- Camera Settings
    do
        local camera = Workspace.CurrentCamera
        local defaultCamFov = camera and camera.FieldOfView or 70
        local defaultMaxZoom = LocalPlayer.CameraMaxZoomDistance or 400
        local defaultMinZoom = LocalPlayer.CameraMinZoomDistance or 0.5
        
        local CamBox = safeAddRightGroupbox(PlayerTab, "Camera & World", "sun")
        local CamFOVSlider = CamBox:AddSlider("bxw_cam_fov", { Text = "Camera FOV", Default = defaultCamFov, Min = 40, Max = 120, Rounding = 0, Compact = false, Callback = function(value) local c = Workspace.CurrentCamera if c then c.FieldOfView = value end end })
        local MaxZoomSlider = CamBox:AddSlider("bxw_cam_maxzoom", { Text = "Max Zoom", Default = defaultMaxZoom, Min = 10, Max = 1000, Rounding = 0, Compact = false, Callback = function(value) pcall(function() LocalPlayer.CameraMaxZoomDistance = value end) end })
        
        CamBox:AddButton("Reset Max Zoom", function() pcall(function() LocalPlayer.CameraMaxZoomDistance = defaultMaxZoom end) MaxZoomSlider:SetValue(defaultMaxZoom) end)
        
        local MinZoomSlider = CamBox:AddSlider("bxw_cam_minzoom", { Text = "Min Zoom", Default = defaultMinZoom, Min = 0, Max = 50, Rounding = 1, Compact = false, Callback = function(value) pcall(function() LocalPlayer.CameraMinZoomDistance = value end) end })
        CamBox:AddButton("Reset Min Zoom", function() pcall(function() LocalPlayer.CameraMinZoomDistance = defaultMinZoom end) MinZoomSlider:SetValue(defaultMinZoom) end)
        
        local SkyboxThemes = { ["Default"] = "", ["Space"] = "rbxassetid://11755937810", ["Sunset"] = "rbxassetid://9393701400", ["Midnight"] = "rbxassetid://11755930464" }
        local SkyboxDropdown = CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default", Multi = false })
        
        local originalSkyCam = nil
        local function applySkyCam(name)
            local lighting = game:GetService("Lighting")
            if not originalSkyCam then 
                originalSkyCam = lighting:FindFirstChildOfClass("Sky") 
                if originalSkyCam then originalSkyCam = originalSkyCam:Clone() end 
            end
            
            local currentSky = lighting:FindFirstChildOfClass("Sky") 
            if currentSky then currentSky:Destroy() end
            
            local id = SkyboxThemes[name]
            if id and id ~= "" then 
                local sky = Instance.new("Sky") 
                sky.SkyboxBk = id sky.SkyboxDn = id sky.SkyboxFt = id sky.SkyboxLf = id sky.SkyboxRt = id sky.SkyboxUp = id 
                sky.Parent = lighting 
            else 
                if originalSkyCam then 
                    local newSky = originalSkyCam:Clone() 
                    newSky.Parent = lighting 
                end 
            end
        end
        SkyboxDropdown:OnChanged(function(value) applySkyCam(value) end)
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: ESP & VISUALS
    --/////////////////////////////////////////////////////////////////////////////////
    do
        local ESPTab = Tabs.ESP
        local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
        local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")
        local ESPAdvBox = ESPTab:AddLeftGroupbox("Advanced Visuals", "monitor")

        -- Collection for ESP Locking
        local ESPElements = {}
        local function AddESPElem(elem) 
            table.insert(ESPElements, elem) 
            return elem 
        end

        local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP", Default = false })

        -- Basic Elements
        local BoxStyleDropdown = AddESPElem(ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box", Multi = false }))
        local BoxToggle      = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_box",      { Text = "Box",        Default = true }))
        local ChamsToggle    = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_chams",    { Text = "Chams",      Default = false }))
        local SkeletonToggle = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton",   Default = false }))
        local HealthToggle   = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_health",   { Text = "Health Bar", Default = false }))
        local NameToggle     = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_name",     { Text = "Name Tag",   Default = true }))
        local DistToggle     = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance",   Default = false }))
        local TracerToggle   = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_tracer",   { Text = "Tracer",     Default = false }))
        local TeamToggle     = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_team",     { Text = "Team Check", Default = true }))
        local WallToggle     = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_wall",     { Text = "Wall Check", Default = false }))
        local SelfToggle     = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false }))
        local InfoToggle     = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info", Default = false, Tooltip = "Shows HP, Weapon & Team" }))
        local HeadDotToggle  = AddESPElem(ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false }))
        
        -- Advanced Elements
        local OffscreenToggle = AddESPElem(ESPAdvBox:AddToggle("bxw_esp_arrow", { Text = "Offscreen Arrows", Default = false }))
        local LookTracerToggle = AddESPElem(ESPAdvBox:AddToggle("bxw_esp_looktracer", { Text = "View Tracers", Default = false }))
        local RadarToggle = AddESPElem(ESPAdvBox:AddToggle("bxw_esp_radar", { Text = "2D Radar", Default = false }))
        local ItemEspToggle = AddESPElem(ESPAdvBox:AddToggle("bxw_esp_item", { Text = "Item/Tool ESP", Default = false }))
        local ChamsMatDropdown = AddESPElem(ESPAdvBox:AddDropdown("bxw_esp_chams_mat", { Text = "Chams Material", Values = {"AlwaysOnTop", "ForceField", "Neon", "Plastic"}, Default = "AlwaysOnTop", Multi = false }))

        -- Locking System
        local function SetESPGroupState(enabled)
            for _, elem in ipairs(ESPElements) do
                if elem.SetDisabled then elem:SetDisabled(not enabled) end
            end
        end
        SetESPGroupState(false) -- Lock initially
        
        ESPEnabledToggle:OnChanged(function(state)
            SetESPGroupState(state)
            NotifyAction("Global ESP", state)
        end)

        -- Helper Functions for Drawing Management
        local function HideAllDrawings(data)
            if not data then return end
            if data.Box then data.Box.Visible = false end
            if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
            if data.Health then if data.Health.Outline then data.Health.Outline.Visible = false end if data.Health.Bar then data.Health.Bar.Visible = false end end
            if data.Name then data.Name.Visible = false end
            if data.Distance then data.Distance.Visible = false end
            if data.Tracer then data.Tracer.Visible = false end
            if data.Highlight then data.Highlight.Enabled = false end
            if data.Skeleton then for _, ln in pairs(data.Skeleton) do ln.Visible = false end end
            if data.HeadDot then data.HeadDot.Visible = false end
            if data.Info then data.Info.Visible = false end
            if data.Arrow then data.Arrow.Visible = false end
            if data.LookTracer then data.LookTracer.Visible = false end
        end

        local function removePlayerESP(plr)
            local data = espDrawings[plr]
            if data then
                if data.Box then data.Box:Remove() end
                if data.Corners then for _, ln in pairs(data.Corners) do ln:Remove() end end
                if data.Health then if data.Health.Outline then data.Health.Outline:Remove() end if data.Health.Bar then data.Health.Bar:Remove() end end
                if data.Name then data.Name:Remove() end
                if data.Distance then data.Distance:Remove() end
                if data.Tracer then data.Tracer:Remove() end
                if data.Highlight then data.Highlight:Destroy() end
                if data.Skeleton then for _, ln in pairs(data.Skeleton) do ln:Remove() end end
                if data.HeadDot then data.HeadDot:Remove() end
                if data.Info then data.Info:Remove() end
                if data.Arrow then data.Arrow:Remove() end
                if data.LookTracer then data.LookTracer:Remove() end
                espDrawings[plr] = nil
            end
            if radarDrawings.Blips[plr] then radarDrawings.Blips[plr]:Remove() radarDrawings.Blips[plr] = nil end
        end

        AddConnection(Players.PlayerRemoving:Connect(removePlayerESP))

        -- Settings
        local function getPlayerNames() 
            local names = {} 
            for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then table.insert(names, plr.Name) end end 
            table.sort(names) 
            return names 
        end
        local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = getPlayerNames(), Default = "", Multi = true, AllowNull = true })
        
        task.spawn(function() 
            while true do 
                task.wait(10) 
                WhitelistDropdown:SetValues(getPlayerNames()) 
            end 
        end)

        local BoxColorLabel = ESPSettingBox:AddLabel("Box Color") BoxColorLabel:AddColorPicker("bxw_esp_box_color", { Default = Color3.fromRGB(255, 255, 255) })
        local TracerColorLabel = ESPSettingBox:AddLabel("Tracer Color") TracerColorLabel:AddColorPicker("bxw_esp_tracer_color", { Default = Color3.fromRGB(255, 255, 255) })
        local NameColorLabel = ESPSettingBox:AddLabel("Name Color") NameColorLabel:AddColorPicker("bxw_esp_name_color", { Default = Color3.fromRGB(255, 255, 255) })
        local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local DistColorLabel = ESPSettingBox:AddLabel("Distance Color") DistColorLabel:AddColorPicker("bxw_esp_dist_color", { Default = Color3.fromRGB(255, 255, 255) })
        local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Distance Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local DistUnitDropdown = ESPSettingBox:AddDropdown("bxw_esp_dist_unit", { Text = "Distance Unit", Values = { "Studs", "Meters" }, Default = "Studs", Multi = false })
        local SkeletonColorLabel = ESPSettingBox:AddLabel("Skeleton Color") SkeletonColorLabel:AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.fromRGB(0, 255, 255) })
        local HealthColorLabel = ESPSettingBox:AddLabel("Health Bar Color") HealthColorLabel:AddColorPicker("bxw_esp_health_color", { Default = Color3.fromRGB(0, 255, 0) })
        local InfoColorLabel = ESPSettingBox:AddLabel("Info Color") InfoColorLabel:AddColorPicker("bxw_esp_info_color", { Default = Color3.fromRGB(255, 255, 255) })
        local HeadDotColorLabel = ESPSettingBox:AddLabel("Head Dot Color") HeadDotColorLabel:AddColorPicker("bxw_esp_headdot_color", { Default = Color3.fromRGB(255, 0, 0) })
        local HeadDotSizeSlider = ESPSettingBox:AddSlider("bxw_esp_headdot_size", { Text = "Head Dot Size", Default = 3, Min = 1, Max = 10, Rounding = 0 })
        local ChamsColorLabel = ESPSettingBox:AddLabel("Chams Color") ChamsColorLabel:AddColorPicker("bxw_esp_chams_color", { Default = Color3.fromRGB(0, 255, 0) })
        local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2, Compact = false })
        local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Visible Only", Default = false })
        local ArrowRadiusSlider = ESPSettingBox:AddSlider("bxw_arrow_radius", { Text = "Arrow Radius", Default = 200, Min = 50, Max = 500, Rounding = 0 })
        local ArrowColorLabel = ESPSettingBox:AddLabel("Arrow Color") ArrowColorLabel:AddColorPicker("bxw_esp_arrow_color", { Default = Color3.fromRGB(255, 100, 0) })
        local RadarRangeSlider = ESPSettingBox:AddSlider("bxw_radar_range", { Text = "Radar Range", Default = 150, Min = 50, Max = 500, Rounding = 0 })
        local ESPRefreshSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "ESP Refresh (ms)", Default = 20, Min = 0, Max = 200, Rounding = 0, Compact = false })

        local CrosshairToggle = ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
        local CrossColorLabel = ESPSettingBox:AddLabel("Crosshair Color") CrossColorLabel:AddColorPicker("bxw_crosshair_color", { Default = Color3.fromRGB(255, 255, 255) })
        local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20, Rounding = 0, Compact = false })
        local CrossThickSlider = ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Crosshair Thickness", Default = 1, Min = 1, Max = 5, Rounding = 0 })
        CrossSizeSlider:SetDisabled(true) CrossThickSlider:SetDisabled(true)
        CrosshairToggle:OnChanged(function(state) CrossSizeSlider:SetDisabled(not state) CrossThickSlider:SetDisabled(not state) NotifyAction("Crosshair", state) end)

        local skeletonJoints = {
            ["Head"] = "UpperTorso", ["UpperTorso"] = "LowerTorso", ["LowerTorso"] = "HumanoidRootPart",
            ["LeftUpperArm"] = "UpperTorso", ["LeftLowerArm"] = "LeftUpperArm", ["LeftHand"] = "LeftLowerArm",
            ["RightUpperArm"] = "UpperTorso", ["RightLowerArm"] = "RightUpperArm", ["RightHand"] = "RightLowerArm",
            ["LeftUpperLeg"] = "LowerTorso", ["LeftLowerLeg"] = "LeftUpperLeg", ["LeftFoot"] = "LeftLowerLeg",
            ["RightUpperLeg"] = "LowerTorso", ["RightLowerLeg"] = "RightUpperLeg", ["RightFoot"] = "RightLowerLeg",
        }

        local lastESPUpdate = 0

        -- Main ESP Update Loop
        AddConnection(RunService.RenderStepped:Connect(function()
            -- Throttle check
            if ESPRefreshSlider.Value > 0 then
                local now = tick()
                if now - lastESPUpdate < (ESPRefreshSlider.Value / 1000) then return end
                lastESPUpdate = now
            end

            if not ESPEnabledToggle.Value then
                -- Disable everything if master switch is off
                for _, data in pairs(espDrawings) do HideAllDrawings(data) end
                for _, b in pairs(radarDrawings.Blips) do b.Visible = false end
                if radarDrawings.Background then radarDrawings.Background.Visible = false radarDrawings.Border.Visible = false radarDrawings.Center.Visible = false end
                for _, i in pairs(itemDrawings) do if i.Text then i.Text.Visible = false end end
                return
            end

            local cam = Workspace.CurrentCamera
            if not cam then return end
            local camPos = cam.CFrame.Position

            -- Radar Background
            if RadarToggle.Value then
                 if not radarDrawings.Background then
                     radarDrawings.Background = Drawing.new("Square") radarDrawings.Background.Filled = true radarDrawings.Background.Color = Color3.fromRGB(20, 20, 20) radarDrawings.Background.Transparency = 0.8 radarDrawings.Background.Size = Vector2.new(120, 120) radarDrawings.Background.Position = Vector2.new(50, 50)
                     radarDrawings.Border = Drawing.new("Square") radarDrawings.Border.Filled = false radarDrawings.Border.Color = Color3.fromRGB(255, 255, 255) radarDrawings.Border.Thickness = 1 radarDrawings.Border.Transparency = 1 radarDrawings.Border.Size = Vector2.new(120, 120) radarDrawings.Border.Position = Vector2.new(50, 50)
                     radarDrawings.Center = Drawing.new("Square") radarDrawings.Center.Filled = true radarDrawings.Center.Color = Color3.fromRGB(0, 255, 0) radarDrawings.Center.Size = Vector2.new(4, 4) radarDrawings.Center.Position = Vector2.new(110 - 2, 110 - 2)
                 end
                 radarDrawings.Background.Visible = true radarDrawings.Border.Visible = true radarDrawings.Center.Visible = true
            else
                 if radarDrawings.Background then radarDrawings.Background.Visible = false radarDrawings.Border.Visible = false radarDrawings.Center.Visible = false end
            end

            -- Item ESP
            if ItemEspToggle.Value then
                for _, item in pairs(workspace:GetDescendants()) do
                    if item:IsA("Tool") or (item:IsA("Model") and item:FindFirstChild("Handle")) then
                        local handle = item:FindFirstChild("Handle") or item:FindFirstChildOfClass("BasePart")
                        if handle then
                             if not itemDrawings[item] then
                                 local t = Drawing.new("Text") t.Center = true t.Outline = true t.Size = 12 t.Color = Color3.fromRGB(200, 200, 200) itemDrawings[item] = { Text = t, Part = handle }
                             end
                             local d = itemDrawings[item]
                             local pos, vis = cam:WorldToViewportPoint(d.Part.Position)
                             if vis then
                                 d.Text.Visible = true d.Text.Position = Vector2.new(pos.X, pos.Y) d.Text.Text = item.Name
                             else d.Text.Visible = false end
                        end
                    end
                end
            else
                 for _, d in pairs(itemDrawings) do d.Text.Visible = false end
            end
            for k, d in pairs(itemDrawings) do if not k.Parent then d.Text:Remove() itemDrawings[k] = nil end end

            -- Player Loop
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer or (SelfToggle.Value) then
                    local char = plr.Character
                    local hum  = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart") or char and char:FindFirstChild("Torso") or char and char:FindFirstChild("UpperTorso")
                    
                    if not (char and hum and root and hum.Health > 0) then
                        HideAllDrawings(espDrawings[plr])
                        if radarDrawings.Blips[plr] then radarDrawings.Blips[plr].Visible = false end
                    else
                        local skipPlayer = false
                        if TeamToggle.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then skipPlayer = true end
                        if not skipPlayer then
                            local list = WhitelistDropdown.Value
                            if list and type(list) == "table" then for _, name in ipairs(list) do if name == plr.Name then skipPlayer = true break end end end
                        end

                        if skipPlayer then
                             HideAllDrawings(espDrawings[plr])
                             if radarDrawings.Blips[plr] then radarDrawings.Blips[plr].Visible = false end
                        else
                            local data = espDrawings[plr]
                            if not data then data = {} espDrawings[plr] = data end

                            local minVec, maxVec = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
                            local children = char:GetChildren()
                            for i=1, #children do
                                local part = children[i]
                                if part:IsA("BasePart") then
                                    local pos = part.Position
                                    minVec = Vector3.new(math.min(minVec.X, pos.X), math.min(minVec.Y, pos.Y), math.min(minVec.Z, pos.Z))
                                    maxVec = Vector3.new(math.max(maxVec.X, pos.X), math.max(maxVec.Y, pos.Y), math.max(maxVec.Z, pos.Z))
                                end
                            end
                            local size = maxVec - minVec
                            local center = (maxVec + minVec) / 2
                            local halfSize = size / 2
                            local cornersWorld = {
                                center + Vector3.new(-halfSize.X,  halfSize.Y, -halfSize.Z), center + Vector3.new( halfSize.X,  halfSize.Y, -halfSize.Z),
                                center + Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z), center + Vector3.new( halfSize.X, -halfSize.Y, -halfSize.Z),
                                center + Vector3.new(-halfSize.X,  halfSize.Y,  halfSize.Z), center + Vector3.new( halfSize.X,  halfSize.Y,  halfSize.Z),
                                center + Vector3.new(-halfSize.X, -halfSize.Y,  halfSize.Z), center + Vector3.new( halfSize.X, -halfSize.Y,  halfSize.Z),
                            }
                            
                            local onScreen = false
                            local screenPoints = {}
                            for i, worldPos in ipairs(cornersWorld) do
                                local screenPos, vis = cam:WorldToViewportPoint(worldPos)
                                screenPoints[i] = Vector2.new(screenPos.X, screenPos.Y)
                                onScreen = onScreen or vis
                            end

                            -- Visibility Check
                            local isVisible = true
                            local sharedColor = Color3.fromRGB(255, 0, 0)
                            if WallToggle.Value then
                                if onScreen then
                                    local rayDir = (root.Position - camPos)
                                    local rayParams = RaycastParams.new()
                                    rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                    local rayResult = Workspace:Raycast(camPos, rayDir, rayParams)
                                    if rayResult then isVisible = false end
                                    sharedColor = isVisible and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
                                end
                            else
                                sharedColor = isVisible and Color3.fromRGB(0, 255, 0)
                            end

                            -- Radar Blip Update
                            if RadarToggle.Value then
                                if not radarDrawings.Blips[plr] then
                                    local b = Drawing.new("Square") b.Filled = true b.Size = Vector2.new(3, 3) radarDrawings.Blips[plr] = b
                                end
                                local blip = radarDrawings.Blips[plr]
                                local myRoot = getRootPart()
                                if myRoot then
                                    local scale = RadarRangeSlider.Value
                                    local dx, dz = root.Position.X - myRoot.Position.X, root.Position.Z - myRoot.Position.Z
                                    local angle = math.atan2(myRoot.CFrame.LookVector.Z, myRoot.CFrame.LookVector.X) + math.pi/2
                                    local rotX = dx * math.cos(angle) - dz * math.sin(angle)
                                    local rotY = dx * math.sin(angle) + dz * math.cos(angle)
                                    local rx = math.clamp((rotX / scale) * 60, -60, 60)
                                    local ry = math.clamp((rotY / scale) * 60, -60, 60)
                                    blip.Visible = true blip.Color = sharedColor blip.Position = Vector2.new(110 + rx, 110 + ry)
                                end
                            else if radarDrawings.Blips[plr] then radarDrawings.Blips[plr].Visible = false end end

                            -- Offscreen Arrows
                            if OffscreenToggle.Value then
                                if not data.Arrow then data.Arrow = Drawing.new("Triangle") data.Arrow.Filled = true end
                                if not onScreen then
                                    data.Arrow.Visible = true
                                    data.Arrow.Color = (Options.bxw_esp_arrow_color and Options.bxw_esp_arrow_color.Value) or Color3.fromRGB(255, 100, 0)
                                    local relative = cam.CFrame:PointToObjectSpace(root.Position)
                                    local angle = math.atan2(relative.Y, relative.X)
                                    local radius = ArrowRadiusSlider.Value
                                    local centerScreen = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                                    local arrowPos = centerScreen + Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
                                    local size = 15
                                    data.Arrow.PointA = arrowPos + Vector2.new(math.cos(angle) * size, math.sin(angle) * size)
                                    data.Arrow.PointB = arrowPos + Vector2.new(math.cos(angle + 2.5) * (size/2), math.sin(angle + 2.5) * (size/2))
                                    data.Arrow.PointC = arrowPos + Vector2.new(math.cos(angle - 2.5) * (size/2), math.sin(angle - 2.5) * (size/2))
                                else data.Arrow.Visible = false end
                            else if data.Arrow then data.Arrow.Visible = false end end

                            if not onScreen then
                                HideAllDrawings(data)
                            else
                                local minX, minY = math.huge, math.huge
                                local maxX, maxY = -math.huge, -math.huge
                                for _, v2 in ipairs(screenPoints) do
                                    minX = math.min(minX, v2.X) maxX = math.max(maxX, v2.X)
                                    minY = math.min(minY, v2.Y) maxY = math.max(maxY, v2.Y)
                                end
                                local boxW, boxH = maxX - minX, maxY - minY
                                local finalColor = sharedColor or (Options.bxw_esp_box_color and Options.bxw_esp_box_color.Value)

                                -- Chams
                                if ChamsToggle.Value then
                                    if not data.Highlight then local hl = Instance.new("Highlight") hl.Parent = char data.Highlight = hl end
                                    local hl = data.Highlight hl.Enabled = true
                                    hl.FillColor = (Options.bxw_esp_chams_color and Options.bxw_esp_chams_color.Value) or finalColor
                                    hl.OutlineColor = hl.FillColor
                                    hl.FillTransparency = ChamsTransSlider.Value
                                    local matStr = ChamsMatDropdown.Value or "AlwaysOnTop"
                                    hl.DepthMode = (matStr == "AlwaysOnTop" or not ChamsVisibleToggle.Value) and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
                                    hl.Adornee = char
                                else if data.Highlight then data.Highlight.Enabled = false end end

                                -- Boxes
                                if BoxToggle.Value then
                                    if BoxStyleDropdown.Value == "Box" then
                                        if not data.Box then local sq = Drawing.new("Square") sq.Thickness = 1 sq.Filled = false sq.Transparency = 1 data.Box = sq end
                                        data.Box.Visible = true data.Box.Color = finalColor data.Box.Position = Vector2.new(minX, minY) data.Box.Size = Vector2.new(boxW, boxH)
                                        if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                    else
                                        if not data.Corners then data.Corners = {} for i=1,8 do local ln = Drawing.new("Line") ln.Thickness = 1 ln.Transparency = 1 data.Corners[i] = ln end end
                                        if data.Box then data.Box.Visible = false end
                                        local cw, ch = boxW * 0.25, boxH * 0.25
                                        local tl, tr = Vector2.new(minX, minY), Vector2.new(maxX, minY)
                                        local bl, br = Vector2.new(minX, maxY), Vector2.new(maxX, maxY)
                                        local lines = data.Corners
                                        local function setL(idx, f, t) lines[idx].Visible = true lines[idx].Color = finalColor lines[idx].From = f lines[idx].To = t end
                                        setL(1, tl, tl + Vector2.new(cw, 0)) setL(2, tl, tl + Vector2.new(0, ch))
                                        setL(3, tr, tr + Vector2.new(-cw, 0)) setL(4, tr, tr + Vector2.new(0, ch))
                                        setL(5, bl, bl + Vector2.new(cw, 0)) setL(6, bl, bl + Vector2.new(0, -ch))
                                        setL(7, br, br + Vector2.new(-cw, 0)) setL(8, br, br + Vector2.new(0, -ch))
                                    end
                                else
                                    if data.Box then data.Box.Visible = false end
                                    if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                end

                                -- Health
                                if HealthToggle.Value then
                                    if not data.Health then data.Health = { Outline = Drawing.new("Line"), Bar = Drawing.new("Line") } data.Health.Outline.Thickness = 3 data.Health.Bar.Thickness = 1 end
                                    local hbX = minX - 6
                                    local hp = math.clamp(hum.Health, 0, hum.MaxHealth)
                                    local barY2 = minY + (maxY - minY) * (1 - (hp / hum.MaxHealth))
                                    data.Health.Outline.Visible = true data.Health.Outline.Color = Color3.new(0,0,0) data.Health.Outline.From = Vector2.new(hbX, minY) data.Health.Outline.To = Vector2.new(hbX, maxY)
                                    data.Health.Bar.Visible = true data.Health.Bar.Color = (Options.bxw_esp_health_color and Options.bxw_esp_health_color.Value) or Color3.fromRGB(0, 255, 0)
                                    data.Health.Bar.From = Vector2.new(hbX, minY) data.Health.Bar.To = Vector2.new(hbX, barY2)
                                else if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end end

                                -- Name
                                if NameToggle.Value then
                                    if not data.Name then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Name = txt end
                                    data.Name.Visible = true data.Name.Color = sharedColor or (Options.bxw_esp_name_color and Options.bxw_esp_name_color.Value)
                                    data.Name.Size = NameSizeSlider.Value data.Name.Text = plr.DisplayName or plr.Name
                                    data.Name.Position = Vector2.new((minX + maxX) / 2, minY - 14)
                                else if data.Name then data.Name.Visible = false end end

                                -- Info
                                if InfoToggle.Value then
                                    if not data.Info then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Info = txt end
                                    local hpVal = math.floor(hum.Health)
                                    local tool = char:FindFirstChildOfClass("Tool")
                                    local toolN = tool and tool.Name or "None"
                                    data.Info.Visible = true data.Info.Color = (Options.bxw_esp_info_color and Options.bxw_esp_info_color.Value) or Color3.fromRGB(255, 255, 255)
                                    data.Info.Size = NameSizeSlider.Value
                                    data.Info.Text = string.format("[%d HP]\n[%s]", hpVal, toolN)
                                    data.Info.Position = Vector2.new((minX + maxX) / 2, maxY + 16)
                                else if data.Info then data.Info.Visible = false end end
                                
                                -- Tracers
                                if TracerToggle.Value then
                                    if not data.Tracer then data.Tracer = Drawing.new("Line") data.Tracer.Thickness = 1 data.Tracer.Transparency = 1 end
                                    local screenRoot = cam:WorldToViewportPoint(root.Position)
                                    data.Tracer.Visible = true data.Tracer.Color = sharedColor or (Options.bxw_esp_tracer_color and Options.bxw_esp_tracer_color.Value)
                                    data.Tracer.From = Vector2.new(screenRoot.X, screenRoot.Y) data.Tracer.To = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
                                else if data.Tracer then data.Tracer.Visible = false end end

                                -- Look Tracers
                                if LookTracerToggle.Value then
                                    local head = char:FindFirstChild("Head")
                                    if head then
                                        if not data.LookTracer then data.LookTracer = Drawing.new("Line") data.LookTracer.Thickness = 1 end
                                        local endPos = head.Position + (head.CFrame.LookVector * 10)
                                        local s1, v1 = cam:WorldToViewportPoint(head.Position)
                                        local s2, v2 = cam:WorldToViewportPoint(endPos)
                                        if v1 or v2 then
                                            data.LookTracer.Visible = true data.LookTracer.Color = Color3.fromRGB(255, 255, 0)
                                            data.LookTracer.From = Vector2.new(s1.X, s1.Y) data.LookTracer.To = Vector2.new(s2.X, s2.Y)
                                        else data.LookTracer.Visible = false end
                                    end
                                else if data.LookTracer then data.LookTracer.Visible = false end end

                                -- Head Dot
                                if HeadDotToggle.Value then
                                    local head = char:FindFirstChild("Head")
                                    if head then
                                        local spHead = cam:WorldToViewportPoint(head.Position)
                                        if not data.HeadDot then data.HeadDot = Drawing.new("Circle") data.HeadDot.Filled = true end
                                        data.HeadDot.Visible = true data.HeadDot.Color = sharedColor or (Options.bxw_esp_headdot_color and Options.bxw_esp_headdot_color.Value)
                                        data.HeadDot.Position = Vector2.new(spHead.X, spHead.Y) data.HeadDot.Radius = HeadDotSizeSlider.Value
                                    end
                                else if data.HeadDot then data.HeadDot.Visible = false end end

                                -- Skeleton
                                if SkeletonToggle.Value then
                                    if not data.Skeleton then data.Skeleton = {} end
                                    local idx = 1
                                    local skCol = sharedColor or (Options.bxw_esp_skeleton_color and Options.bxw_esp_skeleton_color.Value)
                                    for joint, parentName in pairs(skeletonJoints) do
                                        local p1 = char:FindFirstChild(joint)
                                        local p2 = char:FindFirstChild(parentName)
                                        local ln = data.Skeleton[idx]
                                        if not ln then ln = Drawing.new("Line") ln.Thickness = 1 ln.Transparency = 1 data.Skeleton[idx] = ln end
                                        if p1 and p2 then
                                            local sp1, vis1 = cam:WorldToViewportPoint(p1.Position)
                                            local sp2, vis2 = cam:WorldToViewportPoint(p2.Position)
                                            if vis1 or vis2 then
                                                ln.Visible = true ln.Color = skCol
                                                ln.From = Vector2.new(sp1.X, sp1.Y) ln.To = Vector2.new(sp2.X, sp2.Y)
                                            else ln.Visible = false end
                                        else ln.Visible = false end
                                        idx = idx + 1
                                    end
                                else if data.Skeleton then for _, ln in pairs(data.Skeleton) do ln.Visible = false end end end
                            end
                        end
                    end
                end
            end
        end))

        -- Crosshair Render
        crosshairLines = { h = Drawing.new("Line"), v = Drawing.new("Line") }
        crosshairLines.h.Transparency = 1 crosshairLines.v.Transparency = 1
        AddConnection(RunService.RenderStepped:Connect(function()
            if Toggles.bxw_crosshair_enable.Value then
                local cx, cy = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
                local size, thick = CrossSizeSlider.Value, CrossThickSlider.Value
                local col = Options.bxw_crosshair_color.Value
                crosshairLines.h.Visible = true crosshairLines.h.From = Vector2.new(cx - size, cy) crosshairLines.h.To = Vector2.new(cx + size, cy) crosshairLines.h.Color = col crosshairLines.h.Thickness= thick
                crosshairLines.v.Visible = true crosshairLines.v.From = Vector2.new(cx, cy - size) crosshairLines.v.To = Vector2.new(cx, cy + size) crosshairLines.v.Color = col crosshairLines.v.Thickness= thick
            else
                crosshairLines.h.Visible = false crosshairLines.v.Visible = false
            end
        end))
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: COMBAT
    --/////////////////////////////////////////////////////////////////////////////////
    do
        local CombatTab = Tabs.Combat
        local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
        local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

        -- Aimbot UI
        local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false })
        local SilentToggle = AimBox:AddToggle("bxw_silent_enable", { Text = "Silent Aim", Default = false })
        local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest", "Random" }, Default = "Head", Multi = false })
        local UseSmartAimLogic = AimBox:AddToggle("bxw_aim_smart_logic", { Text = "Smart Aim Logic", Default = true, Tooltip = "Auto-calculate best target" })
        local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
        local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
        local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Aimbot Smoothness", Default = 0.1, Min = 0.01, Max = 1, Rounding = 2 })
        local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
        local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false })
        local VisibilityToggle = AimBox:AddToggle("bxw_aim_visibility", { Text = "Visibility Check", Default = false })
        local HitChanceSlider = AimBox:AddSlider("bxw_aim_hitchance", { Text = "Hit Chance %", Default = 100, Min = 1, Max = 100, Rounding = 0 })
        local RainbowToggle = AimBox:AddToggle("bxw_aim_rainbow", { Text = "Rainbow FOV", Default = false })
        local RainbowSpeedSlider = AimBox:AddSlider("bxw_aim_rainbowspeed", { Text = "Rainbow Speed", Default = 5, Min = 1, Max = 10, Rounding = 1 })
        local FOVColorLabel = AimBox:AddLabel("FOV Color") FOVColorLabel:AddColorPicker("bxw_aim_fovcolor", { Default = Color3.fromRGB(255, 255, 255) })
        
        local AimMethodDropdown = AimBox:AddDropdown("bxw_aim_method", { Text = "Aim Method", Values = { "CameraLock", "MouseDelta" }, Default = "CameraLock", Multi = false })
        local TargetModeDropdown = AimBox:AddDropdown("bxw_aim_targetmode", { Text = "Target Mode", Values = { "Closest To Crosshair", "Closest Distance", "Lowest Health" }, Default = "Closest To Crosshair", Multi = false })
        local ShowSnapToggle = AimBox:AddToggle("bxw_aim_snapline", { Text = "Show SnapLine", Default = false })
        local SnapColorLabel = AimBox:AddLabel("SnapLine Color") SnapColorLabel:AddColorPicker("bxw_aim_snapcolor", { Default = Color3.fromRGB(255, 0, 0) })
        local SnapThicknessSlider = AimBox:AddSlider("bxw_aim_snapthick", { Text = "SnapLine Thickness", Default = 1, Min = 1, Max = 5, Rounding = 0 })
        local AimActivationDropdown = AimBox:AddDropdown("bxw_aim_activation", { Text = "Aim Activation", Values = { "Hold Right Click", "Always On" }, Default = "Hold Right Click", Multi = false })
        local SmartAimToggle = AimBox:AddToggle("bxw_aim_smart", { Text = "Smart BodyAim", Default = false, Tooltip = "Aim at head if body blocked" }) 
        local PredToggle = AimBox:AddToggle("bxw_aim_pred", { Text = "Prediction Aim", Default = false })
        local PredSlider = AimBox:AddSlider("bxw_aim_predfactor", { Text = "Prediction Factor", Default = 0.1, Min = 0, Max = 1, Rounding = 2 })

        -- Advanced Combat
        local DeadzoneSlider = ExtraBox:AddSlider("bxw_aim_deadzone", { Text = "Deadzone Radius", Default = 0, Min = 0, Max = 100, Rounding = 0 })
        local RCSToggle = ExtraBox:AddToggle("bxw_aim_rcs", { Text = "Recoil Control (RCS)", Default = false })
        local RCSStrength = ExtraBox:AddSlider("bxw_aim_rcs_str", { Text = "RCS Strength", Default = 5, Min = 0, Max = 20, Rounding = 1 })
        local StrafeToggle = ExtraBox:AddToggle("bxw_aim_strafe", { Text = "Target Strafe (Hold T)", Default = false })
        local StrafeSpeed = ExtraBox:AddSlider("bxw_strafe_speed", { Text = "Strafe Speed", Default = 20, Min = 10, Max = 50, Rounding = 0 })
        local StrafeDist = ExtraBox:AddSlider("bxw_strafe_dist", { Text = "Strafe Distance", Default = 10, Min = 5, Max = 30, Rounding = 0 })
        
        -- Strafe Logic
        local strafeAngle = 0
        AddConnection(RunService.RenderStepped:Connect(function(dt)
            if StrafeToggle.Value and UserInputService:IsKeyDown(Enum.KeyCode.T) then
                 local root = getRootPart()
                 local target = nil local dist = math.huge
                 for _, p in ipairs(Players:GetPlayers()) do
                     if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                         local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
                         if d < dist then dist = d target = p.Character.HumanoidRootPart end
                     end
                 end
                 if target and root then
                     strafeAngle = strafeAngle + (StrafeSpeed.Value * dt)
                     local offset = Vector3.new(math.cos(strafeAngle) * StrafeDist.Value, 0, math.sin(strafeAngle) * StrafeDist.Value)
                     root.CFrame = CFrame.new(target.Position + offset, target.Position)
                 end
            end
        end))

        -- Aimbot UI Locking
        local function UpdateAimUI(state)
            FOVSlider:SetDisabled(not state) SmoothSlider:SetDisabled(not state) HitChanceSlider:SetDisabled(not state)
            AimPartDropdown:SetDisabled(not state) AimMethodDropdown:SetDisabled(not state)
        end
        UpdateAimUI(false)
        AimbotToggle:OnChanged(function(state) UpdateAimUI(state) NotifyAction("Aimbot", state) end)

        local TriggerFiringDropdown = ExtraBox:AddDropdown("bxw_trigger_firemode", { Text = "Firing Mode", Values = { "Single", "Burst", "Auto" }, Default = "Single", Multi = false })
        local TriggerFovSlider = ExtraBox:AddSlider("bxw_trigger_fov", { Text = "Trigger FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
        local TriggerDelaySlider = ExtraBox:AddSlider("bxw_trigger_delay", { Text = "Trigger Delay (s)", Default = 0.05, Min = 0, Max = 1, Rounding = 2 })
        TriggerFiringDropdown:SetDisabled(true) TriggerFovSlider:SetDisabled(true)
        TriggerbotToggle:OnChanged(function(state) TriggerFiringDropdown:SetDisabled(not state) TriggerFovSlider:SetDisabled(not state) NotifyAction("Triggerbot", state) end)

        AimbotFOVCircle = Drawing.new("Circle") AimbotFOVCircle.Transparency = 0.5 AimbotFOVCircle.Filled = false AimbotFOVCircle.Thickness = 1
        AimbotSnapLine = Drawing.new("Line") AimbotSnapLine.Transparency = 0.7 AimbotSnapLine.Visible = false
        local rainbowHue = 0

        local function performClick() 
            pcall(function() mouse1click() end) 
            pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(Vector2.new()) end) 
        end

        -- Main Aimbot Loop
        AddConnection(RunService.RenderStepped:Connect(function()
            if not cam then return end
            local mouseLoc = UserInputService:GetMouseLocation()
            
            -- FOV Circle
            if ShowFovToggle.Value and AimbotToggle.Value then
                AimbotFOVCircle.Visible = true AimbotFOVCircle.Radius = (FOVSlider.Value * 15) AimbotFOVCircle.Position = mouseLoc
                if RainbowToggle.Value then 
                    rainbowHue = (rainbowHue or 0) + (RainbowSpeedSlider.Value / 360) 
                    if rainbowHue > 1 then rainbowHue = rainbowHue - 1 end 
                    AimbotFOVCircle.Color = Color3.fromHSV(rainbowHue, 1, 1)
                else 
                    AimbotFOVCircle.Color = FOVColorLabel.Value 
                end
            else 
                AimbotFOVCircle.Visible = false 
            end
            AimbotSnapLine.Visible = false

            if AimbotToggle.Value then
                -- Safe Mode Check
                if Toggles.bxw_safemode and Toggles.bxw_safemode.Value and SilentToggle.Value then return end
                
                local activation = AimActivationDropdown.Value
                local isAiming = (activation == "Always On") or (activation == "Hold Right Click" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
                
                if isAiming then
                    local bestPlr, bestScore = nil, math.huge
                    local myRoot = getRootPart()
                    if myRoot then
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer then
                                local char = plr.Character
                                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    local rootCand = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                                    if rootCand then
                                        local skip = false
                                        if AimTeamCheck.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then skip = true end
                                        if not skip then
                                            local partName = AimPartDropdown.Value
                                            local selPart = (partName == "Random") and char:FindFirstChild({"Head","Torso"}math.random(1,2)) or char:FindFirstChild(partName) or rootCand
                                            if partName == "Closest" then selPart = rootCand end
                                            
                                            local sp, onScr = cam:WorldToViewportPoint(selPart.Position)
                                            if onScr then
                                                local dist = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                                                if dist <= (FOVSlider.Value * 15) then
                                                    local skipVis = false
                                                    if VisibilityToggle.Value then
                                                        local rp = RaycastParams.new() rp.FilterDescendantsInstances = {char, LocalPlayer.Character} rp.FilterType = Enum.RaycastFilterType.Blacklist
                                                        if Workspace:Raycast(cam.CFrame.Position, (selPart.Position - cam.CFrame.Position), rp) then skipVis = true end
                                                    end
                                                    if not skipVis then
                                                        local score = dist
                                                        if UseSmartAimLogic.Value then score = (dist * 1.5) + ((rootCand.Position - myRoot.Position).Magnitude * 0.5) end
                                                        if score < bestScore then bestScore = score bestPlr = { part = selPart, sp = sp, dist = dist } end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    if bestPlr and bestPlr.dist > DeadzoneSlider.Value then
                         if math.random(0,100) <= HitChanceSlider.Value then
                             local aimPos = bestPlr.part.Position
                             if PredToggle.Value then aimPos = aimPos + (bestPlr.part.AssemblyLinearVelocity * PredSlider.Value) end
                             
                             if RCSToggle.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then mousemoverel(0, RCSStrength.Value) end
                             
                             if AimMethodDropdown.Value == "MouseDelta" then
                                 local d = (Vector2.new(bestPlr.sp.X, bestPlr.sp.Y) - mouseLoc) * SmoothSlider.Value
                                 mousemoverel(d.X, d.Y)
                             else
                                 cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, aimPos), SmoothSlider.Value)
                             end

                             if ShowSnapToggle.Value then
                                 AimbotSnapLine.Visible = true AimbotSnapLine.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2) AimbotSnapLine.To = Vector2.new(bestPlr.sp.X, bestPlr.sp.Y)
                                 AimbotSnapLine.Color = SnapColorLabel.Value AimbotSnapLine.Thickness = SnapThicknessSlider.Value
                             end
                             
                             if TriggerbotToggle.Value then
                                 if bestPlr.dist <= (TriggerFovSlider.Value * 15) then
                                     task.spawn(function() task.wait(TriggerDelaySlider.Value) performClick() end)
                                 end
                             end
                         end
                    end
                end
            end
        end))
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: SERVER
    --/////////////////////////////////////////////////////////////////////////////////
    do
        local ServerTab = Tabs.Server
        local ServerLeft = ServerTab:AddLeftGroupbox("Server Actions", "server")
        local ServerRight = safeAddRightGroupbox(ServerTab, "Connection & Config", "wifi")

        ServerLeft:AddButton("Server Hop", function() 
            pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end) 
            NotifyAction("Server Hop", true) 
        end)

        ServerLeft:AddButton("Low Server Hop", function()
             Library:Notify("Searching low server...", 3)
             pcall(function()
                local list = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
                if list and list.data then
                    for _, s in ipairs(list.data) do
                        if s.playing < s.maxPlayers and s.id ~= game.JobId then 
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer) 
                            return 
                        end
                    end
                end
                Library:Notify("No low server found", 2)
             end)
        end)

        ServerLeft:AddButton("Rejoin Server", function() 
            pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end) 
        end)

        ServerLeft:AddButton("Instant Leave", function() game:Shutdown() end)

        ServerLeft:AddDivider()
        local jobInput = ""
        ServerLeft:AddInput("bxw_join_jobid_input", { Default = "", Text = "Input Job ID", Placeholder = "Job ID...", Callback = function(Value) jobInput = Value end })
        ServerLeft:AddButton("Join Job ID", function() if jobInput ~= "" then TeleportService:TeleportToPlaceInstance(game.PlaceId, jobInput, LocalPlayer) end end)

        local antiAfkConn
        local AntiAfkToggle = ServerRight:AddToggle("bxw_anti_afk", { Text = "Anti-AFK", Default = true })
        AntiAfkToggle:OnChanged(function(state)
            if state then
                if antiAfkConn then antiAfkConn:Disconnect() end
                antiAfkConn = AddConnection(LocalPlayer.Idled:Connect(function() 
                    pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) 
                end))
            else 
                if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end 
            end
            NotifyAction("Anti-AFK", state)
        end)
        
        local AntiRejoinToggle = ServerRight:AddToggle("bxw_antirejoin", { Text = "Auto Rejoin on Kick", Default = false })
        local lastKick = 0
        AddConnection(GuiService.ErrorMessageChanged:Connect(function()
            if AntiRejoinToggle.Value and (tick() - lastKick > 5) then
                lastKick = tick() 
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end))
        
        ServerRight:AddDivider()
        ServerRight:AddButton("Copy Job ID", function() setclipboard(game.JobId) Library:Notify("Copied Job ID", 2) end)
        ServerRight:AddButton("Copy Place ID", function() setclipboard(tostring(game.PlaceId)) Library:Notify("Copied Place ID", 2) end)
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: MISC & SYSTEM
    --/////////////////////////////////////////////////////////////////////////////////
    do
        local MiscTab = Tabs.Misc
        local MiscLeft  = MiscTab:AddLeftGroupbox("Game Tools", "tool")
        local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")
        local GfxBox = MiscTab:AddRightGroupbox("Graphics & Visuals", "monitor")

        GfxBox:AddButton("Potato Mode (FPS Boost)", function()
            pcall(function()
                Lighting.GlobalShadows = false Lighting.FogEnd = 9e9 Lighting.Brightness = 0
                for _, v in pairs(Workspace:GetDescendants()) do if v:IsA("BasePart") and not v:IsA("MeshPart") then v.Material = Enum.Material.SmoothPlastic v.CastShadow = false end end
            end)
            Library:Notify("Potato Mode Enabled", 2)
        end)

        GfxBox:AddButton("Beautiful Mode (Cinematic)", function()
            pcall(function()
                Lighting.GlobalShadows = true Lighting.Brightness = 2 Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            end)
             Library:Notify("Beautiful Mode Enabled", 2)
        end)

        local ShadowToggle = GfxBox:AddToggle("bxw_shadows", { Text = "Shadows", Default = Lighting.GlobalShadows })
        ShadowToggle:OnChanged(function(state) Lighting.GlobalShadows = state NotifyAction("Shadows", state) end)

        local FullbrightToggle = GfxBox:AddToggle("bxw_fullbright", { Text = "Fullbright", Default = false })
        local fbLoop
        FullbrightToggle:OnChanged(function(state)
            if state then
                fbLoop = AddConnection(RunService.LightingChanged:Connect(function() Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e10 Lighting.GlobalShadows = false end))
                Lighting.Brightness = 2 Lighting.ClockTime = 14
            else if fbLoop then fbLoop:Disconnect() fbLoop = nil end end
            NotifyAction("Fullbright", state)
        end)
        
        local XrayToggle = GfxBox:AddToggle("bxw_xray", { Text = "X-Ray (Wall Trans)", Default = false })
        XrayToggle:OnChanged(function(state)
             for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then v.LocalTransparencyModifier = state and 0.5 or 0 end
             end
             NotifyAction("X-Ray", state)
        end)

        local GravitySlider = MiscRight:AddSlider("bxw_gravity", { Text = "Gravity", Default = Workspace.Gravity, Min = 0, Max = 300, Rounding = 0, Compact = false, Callback = function(value) Workspace.Gravity = value end })
        MiscRight:AddButton("Reset Gravity", function() Workspace.Gravity = 196.2 GravitySlider:SetValue(196.2) end)

        local spinConn
        local SpinToggle = MiscLeft:AddToggle("bxw_spinbot", { Text = "SpinBot", Default = false })
        local SpinSpeedSlider = MiscLeft:AddSlider("bxw_spin_speed", { Text = "Spin Speed", Default = 5, Min = 0.1, Max = 10, Rounding = 1, Compact = false })
        SpinSpeedSlider:SetDisabled(true)
        SpinToggle:OnChanged(function(state)
            SpinSpeedSlider:SetDisabled(not state)
            if state then
                spinConn = AddConnection(RunService.RenderStepped:Connect(function(dt)
                    local root = getRootPart()
                    if root then root.CFrame = root.CFrame * CFrame.Angles(0, SpinSpeedSlider.Value * dt * math.pi, 0) end
                end))
            else if spinConn then spinConn:Disconnect() spinConn = nil end end
            NotifyAction("SpinBot", state)
        end)

        local antiFlingConn
        local AntiFlingToggle2 = MiscLeft:AddToggle("bxw_antifling", { Text = "Anti Fling", Default = false })
        AntiFlingToggle2:OnChanged(function(state)
            if state then
                antiFlingConn = AddConnection(RunService.Stepped:Connect(function()
                    local root = getRootPart()
                    if root then if root.AssemblyLinearVelocity.Magnitude > 80 then root.AssemblyLinearVelocity = Vector3.zero end end
                end))
            else if antiFlingConn then antiFlingConn:Disconnect() antiFlingConn = nil end end
            NotifyAction("Anti-Fling", state)
        end)

        MiscLeft:AddButton("BTools", function()
            local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
            if bp then 
                for _,t in pairs({Enum.BinType.Clone, Enum.BinType.Hammer, Enum.BinType.Grab}) do 
                    local b = Instance.new("HopperBin") b.BinType = t b.Parent = bp 
                end 
            end
            Library:Notify("BTools added", 2)
        end)
        
        -- Auto Clicker
        local ACLeft = MiscTab:AddLeftGroupbox("Auto Clicker", "mouse-pointer-2")
        local ACToggle = ACLeft:AddToggle("bxw_autoclicker", { Text = "Enable Auto Clicker", Default = false })
        local ACDelay = ACLeft:AddSlider("bxw_ac_delay", { Text = "Delay (s)", Default = 0.1, Min = 0.01, Max = 1, Rounding = 2 })
        local acConn
        ACToggle:OnChanged(function(state)
             if state then
                 acConn = AddConnection(RunService.Heartbeat:Connect(function()
                     if ACDelay.Value then task.wait(ACDelay.Value) end
                     if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then mouse1click() end
                 end))
             else if acConn then acConn:Disconnect() acConn = nil end end
        end)

        -- Chat Spy
        local CSLeft = MiscTab:AddLeftGroupbox("Chat Spy", "message-circle")
        local CSToggle = CSLeft:AddToggle("bxw_chatspy", { Text = "Enable Chat Spy", Default = false })
        local csConn
        CSToggle:OnChanged(function(state)
            if state then
                csConn = AddConnection(ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("OnMessageDoneFiltering").OnClientEvent:Connect(function(data)
                    if data and data.FromSpeaker and data.Message and data.FromSpeaker ~= LocalPlayer.Name then
                        print(string.format("[SPY] %s: %s", data.FromSpeaker, data.Message))
                        Library:Notify(string.format("[SPY] %s: %s", data.FromSpeaker, data.Message), 4)
                    end
                end))
            else if csConn then csConn:Disconnect() csConn = nil end end
        end)

        -- Fake Mobile UI
        CSLeft:AddButton("Fake Mobile UI", function()
            if GuiService then
                GuiService.TouchEnabled = true
                Library:Notify("Enabled TouchEnabled (Fake Mobile)", 3)
            end
        end)
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- TAB: SETTINGS
    --/////////////////////////////////////////////////////////////////////////////////
    do
        local SettingsTab = Tabs.Settings
        local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
        
        MenuGroup:AddToggle("ForceNotify", { Text = "Force Notification", Default = true })
        MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end })
        MenuGroup:AddToggle("ShowCustomCursor", { Text = "Custom Cursor", Default = true, Callback = function(Value) Library.ShowCustomCursor = Value end })
        MenuGroup:AddDropdown("NotificationSide", { Values = { "Left", "Right" }, Default = "Right", Text = "Notification Side", Callback = function(Value) Library:SetNotifySide(Value) end })
        MenuGroup:AddDropdown("DPIDropdown", { Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" }, Default = "100%", Text = "DPI Scale", Callback = function(Value) local DPI = tonumber(tostring(Value):gsub("%%", "")) if DPI then Library:SetDPIScale(DPI) end end })
        
        MenuGroup:AddDivider()
        local SafeModeToggle = MenuGroup:AddToggle("bxw_safemode", { Text = "Safe Mode", Default = false, Tooltip = "Disables risky features" })
        SafeModeToggle:OnChanged(function(state) if state then Library:Notify("Safe Mode ENABLED.", 5) end end)

        MenuGroup:AddLabel("Panic Button"):AddKeyPicker("PanicKey", { Default = "F8", NoUI = true, Text = "Unload Everything", Callback = function() Library:Unload() end})
        MenuGroup:AddDivider()
        MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
        MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
        
        Library.ToggleKeybind = Options.MenuKeybind
        ThemeManager:SetLibrary(Library) 
        SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings() 
        SaveManager:SetIgnoreIndexes({ "MenuKeybind", "Key Info", "Game Info" })
        ThemeManager:SetFolder("BxB.Ware_Setting") 
        SaveManager:SetFolder("BxB.Ware_Setting")
        SaveManager:BuildConfigSection(SettingsTab) 
        ThemeManager:ApplyToTab(SettingsTab)
    end

    --/////////////////////////////////////////////////////////////////////////////////
    -- CLEANUP & WATERMARK
    --/////////////////////////////////////////////////////////////////////////////////
    Library:OnUnload(function()
        for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
        
        -- Drawing Cleanup
        if espDrawings then
            for _, data in pairs(espDrawings) do
                for _, item in pairs(data) do
                    if type(item) == "table" then for _, d in pairs(item) do pcall(function() d:Remove() end) end
                    elseif typeof(item) == "Instance" then pcall(function() item:Destroy() end)
                    elseif item.Remove then pcall(function() item:Remove() end) end
                end
            end
        end
        if radarDrawings then
             if radarDrawings.Background then radarDrawings.Background:Remove() end
             if radarDrawings.Border then radarDrawings.Border:Remove() end
             if radarDrawings.Center then radarDrawings.Center:Remove() end
             for _, b in pairs(radarDrawings.Blips) do pcall(function() b:Remove() end) end
        end
        if itemDrawings then for _, d in pairs(itemDrawings) do if d.Text then pcall(function() d.Text:Remove() end) end end end
        if crosshairLines then pcall(function() crosshairLines.h:Remove() crosshairLines.v:Remove() end) end
        if AimbotFOVCircle then pcall(function() AimbotFOVCircle:Remove() end) end
        if AimbotSnapLine then pcall(function() AimbotSnapLine:Remove() end) end
        
        pcall(function() Library:SetWatermarkVisibility(false) end)
    end)
    
    -- Watermark
    pcall(function()
        Library:SetWatermarkVisibility(true)
        AddConnection(RunService.RenderStepped:Connect(function()
            local ping = 0
            pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
            local fps = math.floor(1 / math.max(RunService.RenderStepped:Wait(), 0.001))
            local timeStr = os.date("%H:%M:%S")
            Library:SetWatermark(string.format("BxB.ware | Universal | FPS: %d | Ping: %d ms | %s", fps, ping, timeStr))
        end))
    end)
end

--/////////////////////////////////////////////////////////////////////////////////
-- 5. RETURN EXECUTION
--/////////////////////////////////////////////////////////////////////////////////
return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then warn("[MainHub] Fatal error:", err) end
end
