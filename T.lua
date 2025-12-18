--====================================================
-- 0. Services
--====================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")
local GuiService         = game:GetService("GuiService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local Lighting           = game:GetService("Lighting")
local CoreGui            = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- เก็บ connection ไว้เผื่ออยาก cleanup ตอน Unload
local Connections = {}
local function AddConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

local function getCharacter()
    local plr = LocalPlayer
    if not plr then return end
    local char = plr.Character or plr.CharacterAdded:Wait()
    return char
end

local function getHumanoid()
    local char = getCharacter()
    if not char then return end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
    local char = getCharacter()
    if not char then return end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

--====================================================
-- 1. Secret + Token Verify
--====================================================

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

--====================================================
-- 2. Role System
--====================================================

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
    if RolePriority[role] then return role end
    return "free"
end

local function GetRoleLabel(role)
    role = NormalizeRole(role)
    if role == "free" then return '<font color="#A0A0A0">Free</font>'
    elseif role == "user" then return '<font color="#FFFFFF">User</font>'
    elseif role == "premium" then return '<font color="#FFD700">Premium</font>'
    elseif role == "vip" then return '<font color="#FF00FF">VIP</font>'
    elseif role == "staff" then return '<font color="#00FFFF">Staff</font>'
    elseif role == "owner" then return '<font color="#FF4444">Owner</font>'
    end
    return '<font color="#A0A0A0">Unknown</font>'
end

local function MarkRisky(text)
    return text .. ' <font color="#FF5555" size="10">[RISKY]</font>'
end

--====================================================
-- 3. Helper format
--====================================================

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
    local d = math.floor(diff / 86400)
    diff = diff % 86400
    local h = math.floor(diff / 3600)
    diff = diff % 3600
    local m = math.floor(diff / 60)
    local s = diff % 60
    if d > 0 then return string.format("%dd %02dh %02dm %02ds", d, h, m, s)
    else return string.format("%02dh %02dm %02ds", h, m, s) end
end

local function safeRichLabel(groupbox, text)
    local lbl = groupbox:AddLabel(text, true)
    if lbl and lbl.TextLabel then lbl.TextLabel.RichText = true end
    return lbl
end

--====================================================
-- 4. MainHub Logic
--====================================================

local function MainHub(Exec, keydata, authToken)
    -- Validate Inputs
    if type(Exec) ~= "table" or type(Exec.HttpGet) ~= "function" then warn("[MainHub] Exec invalid") return end
    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then warn("[MainHub] keydata invalid") return end
    
    local expected = buildExpectedToken(keydata)
    if authToken ~= expected then warn("[MainHub] Invalid auth token") return end

    -- Centralized Storage for Cleanup (Fixes Unload Bug)
    local espDrawings = {}
    local crosshairLines = nil
    local AimbotFOVCircle = nil
    local AimbotSnapLine = nil

    keydata.role = NormalizeRole(keydata.role)

    -- Load Library
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library      = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    local Options = Library.Options
    local Toggles = Library.Toggles

    local Window = Library:CreateWindow({
        Title  = "",
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

    local Tabs = {
        Info = Window:AddTab({ Name = "Info", Icon = "info", Description = "Key / Script / System info" }),
        Player = Window:AddTab({ Name = "Player", Icon = "user", Description = "Movement / Teleport / View" }),
        ESP = Window:AddTab({ Name = "ESP & Visuals", Icon = "eye", Description = "Player ESP / Visual settings" }),
        Combat = Window:AddTab({ Name = "Combat & Aimbot", Icon = "target", Description = "Aimbot / target selection" }),
        Misc = Window:AddTab({ Name = "Misc & System", Icon = "joystick", Description = "Utilities / Panic / System" }),
        Settings = Window:AddTab({ Name = "Settings", Icon = "settings", Description = "Theme / Config / Keybinds" }),
    }

    local function safeAddRightGroupbox(tab, name, icon)
        if tab and typeof(tab) == "table" then
            if type(tab.AddRightGroupbox) == "function" then return tab:AddRightGroupbox(name, icon)
            elseif type(tab.AddGroupbox) == "function" then return tab:AddGroupbox({ Side = 2, Name = name, IconName = icon }) end
        end
        return nil
    end

    ------------------------------------------------
    -- TAB 1: Info (Preserved)
    ------------------------------------------------
    local InfoTab = Tabs.Info
    local KeyBox = InfoTab:AddLeftGroupbox("Key Info", "key-round")
    
    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()

    local rawKey = tostring(keydata.key or "N/A")
    local maskedKey = (#rawKey > 4) and string.format("%s-****%s", rawKey:sub(1, 4), rawKey:sub(-3)) or rawKey
    local roleHtml = GetRoleLabel(keydata.role)
    local statusText = tostring(keydata.status or "active")
    local noteText = tostring(keydata.note or "-")

    -- Remote Data Fetch (Safe)
    local remoteKeyData, remoteCreatedAtStr, remoteExpireStr = nil, nil, nil
    task.spawn(function()
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
    end)

    if remoteKeyData then
        if remoteKeyData.role then roleHtml = GetRoleLabel(remoteKeyData.role) end
        if remoteKeyData.status then statusText = tostring(remoteKeyData.status) end
        if remoteKeyData.note and remoteKeyData.note ~= "" then noteText = tostring(remoteKeyData.note) end
        if remoteKeyData.hwid_hash then keydata.hwid_hash = remoteKeyData.hwid_hash end
        if remoteKeyData.timestamp then remoteCreatedAtStr = tostring(remoteKeyData.timestamp) end
        if remoteKeyData.expire then remoteExpireStr = tostring(remoteKeyData.expire) end
    end

    local createdAtText = remoteCreatedAtStr or ((keydata.timestamp and keydata.timestamp > 0) and formatUnixTime(keydata.timestamp) or "Unknown")
    local expireTs = tonumber(keydata.expire) or 0
    local expireDisplay = remoteExpireStr or formatUnixTime(expireTs)
    local timeLeftDisplay = remoteExpireStr and remoteExpireStr or formatTimeLeft(expireTs)

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))
    safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    safeRichLabel(KeyBox, string.format("<b>Tier:</b> %s", string.upper(keydata.role or "free")))
    safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", noteText))
    safeRichLabel(KeyBox, string.format("<b>Created at:</b> %s", createdAtText))
    local ExpireLabel = safeRichLabel(KeyBox, string.format("<b>Expire:</b> %s", expireDisplay))
    local TimeLeftLabel = safeRichLabel(KeyBox, string.format("<b>Time left:</b> %s", timeLeftDisplay))

    AddConnection(RunService.Heartbeat:Connect(function(dt)
        if math.floor(tick()) % 5 == 0 then
            local nowExpire = tonumber(keydata.expire) or expireTs
            local expireStr = remoteExpireStr or formatUnixTime(nowExpire)
            local leftStr = remoteExpireStr and remoteExpireStr or formatTimeLeft(nowExpire)
            if ExpireLabel.TextLabel then ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", expireStr) end
            if TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", leftStr) end
        end
    end))

    KeyBox:AddDivider()
    KeyBox:AddButton("Copy Key Info", function()
        pcall(function() setclipboard(string.format("Key: %s", rawKey)) Library:Notify("Copied", 2) end)
    end)

    local GameBox = safeAddRightGroupbox(InfoTab, "Game Info", "info")
    safeRichLabel(GameBox, '<font size="14"><b>Game / Server Information</b></font>')
    GameBox:AddDivider()
    local GameNameLabel = safeRichLabel(GameBox, "<b>Game:</b> Loading...")
    safeRichLabel(GameBox, string.format("<b>PlaceId:</b> %d", game.PlaceId))
    safeRichLabel(GameBox, string.format("<b>JobId:</b> %s", game.JobId))
    local PlayersLabel = safeRichLabel(GameBox, "<b>Players:</b> -/-")
    local PerfLabel = safeRichLabel(GameBox, "<b>Perf:</b> FPS: - | Ping: -")
    local ServerTimeLabel = safeRichLabel(GameBox, "<b>Server Time:</b> -")

    task.spawn(function()
        local n = "Unknown"
        pcall(function() n = MarketplaceService:GetProductInfo(game.PlaceId).Name end)
        if GameNameLabel.TextLabel then GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", n) end
    end)

    local function updatePlayersLabel()
        local cur = #Players:GetPlayers()
        local max = Players.MaxPlayers or "-"
        if PlayersLabel.TextLabel then PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d / %s", cur, tostring(max)) end
    end
    updatePlayersLabel()
    AddConnection(Players.PlayerAdded:Connect(updatePlayersLabel))
    AddConnection(Players.PlayerRemoving:Connect(updatePlayersLabel))

    AddConnection(RunService.Heartbeat:Connect(function(dt)
        local fps = math.floor(1/math.max(dt, 1/240))
        local ping = 0
        pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
        if PerfLabel.TextLabel then PerfLabel.TextLabel.Text = string.format("<b>Perf:</b> FPS: %d | Ping: %d ms", fps, ping) end
        if ServerTimeLabel.TextLabel then ServerTimeLabel.TextLabel.Text = string.format("<b>Server Time:</b> %s", os.date("%H:%M:%S")) end
    end))

    ------------------------------------------------
    -- TAB 2: Player (Features Preserved)
    ------------------------------------------------
    local PlayerTab = Tabs.Player
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    local walkSpeedEnabled, defaultWalkSpeed = false, 16
    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = 16, Min = 0, Max = 150, Rounding = 0 })
    
    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = state and WalkSpeedSlider.Value or defaultWalkSpeed end
    end)
    MoveBox:AddButton("Reset WalkSpeed", function()
        local hum = getHumanoid() if hum then hum.WalkSpeed = defaultWalkSpeed end
        WalkSpeedSlider:SetValue(defaultWalkSpeed) WalkSpeedToggle:SetValue(false)
    end)

    local jumpPowerEnabled, defaultJumpPower = false, 50
    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = 50, Min = 0, Max = 300, Rounding = 0 })

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        local hum = getHumanoid()
        if hum then hum.UseJumpPower = true hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower end
    end)
    MoveBox:AddButton("Reset JumpPower", function()
        local hum = getHumanoid() if hum then hum.UseJumpPower = true hum.JumpPower = defaultJumpPower end
        JumpPowerSlider:SetValue(defaultJumpPower) JumpPowerToggle:SetValue(false)
    end)

    MoveBox:AddLabel("Movement Presets")
    local MovePresetDropdown = MoveBox:AddDropdown("bxw_move_preset", { Text = "Movement Preset", Values = { "Default", "Normal", "Fast", "Ultra" }, Default = "Default" })
    MovePresetDropdown:OnChanged(function(value)
        if value == "Default" then WalkSpeedSlider:SetValue(defaultWalkSpeed) JumpPowerSlider:SetValue(defaultJumpPower)
        elseif value == "Normal" then WalkSpeedSlider:SetValue(24) JumpPowerSlider:SetValue(65)
        elseif value == "Fast" then WalkSpeedSlider:SetValue(40) JumpPowerSlider:SetValue(100)
        elseif value == "Ultra" then WalkSpeedSlider:SetValue(80) JumpPowerSlider:SetValue(200) end
    end)

    MoveBox:AddDivider()
    local infJumpConn
    local InfJumpToggle = MoveBox:AddToggle("bxw_infjump", { Text = "Infinite Jump", Default = false })
    InfJumpToggle:OnChanged(function(state)
        if state then
            infJumpConn = AddConnection(UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid() if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end))
        elseif infJumpConn then infJumpConn:Disconnect() infJumpConn = nil end
    end)

    local flyConn, flyBV, flyBG
    local flyEnabled = false
    local FlyToggle = MoveBox:AddToggle("bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = 60, Min = 1, Max = 300, Rounding = 0 })
    FlyToggle:OnChanged(function(state)
        flyEnabled = state
        local root, hum, cam = getRootPart(), getHumanoid(), Workspace.CurrentCamera
        if not state then
            if flyConn then flyConn:Disconnect() flyConn = nil end
            if flyBV then flyBV:Destroy() flyBV = nil end
            if flyBG then flyBG:Destroy() flyBG = nil end
            if hum then hum.PlatformStand = false end
        else
            if not root or not hum then FlyToggle:SetValue(false) return end
            hum.PlatformStand = true
            flyBV = Instance.new("BodyVelocity", root) flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
            flyBG = Instance.new("BodyGyro", root) flyBG.MaxTorque = Vector3.new(9e9,9e9,9e9) flyBG.P = 9e4
            flyConn = AddConnection(RunService.RenderStepped:Connect(function()
                if not flyEnabled then return end
                local moveDir = Vector3.new(0,0,0)
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0,1,0) end
                if moveDir.Magnitude > 0 then flyBV.Velocity = moveDir.Unit * FlySpeedSlider.Value else flyBV.Velocity = Vector3.zero end
                flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
            end))
        end
    end)

    local noclipConn
    local NoclipToggle = MoveBox:AddToggle("bxw_noclip", { Text = MarkRisky("Noclip"), Default = false })
    NoclipToggle:OnChanged(function(state)
        if not state then
            if noclipConn then noclipConn:Disconnect() noclipConn = nil end
            local char = getCharacter()
            if char then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = true end end end
        else
            noclipConn = AddConnection(RunService.Stepped:Connect(function()
                local char = getCharacter()
                if char then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end
            end))
        end
    end)

    local UtilBox = safeAddRightGroupbox(PlayerTab, "Teleport / Utility", "map")
    local playerNames = {}
    local function refreshPlayerList()
        table.clear(playerNames)
        for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then table.insert(playerNames, plr.Name) end end
    end
    refreshPlayerList()
    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = playerNames, Default = "", AllowNull = true })
    UtilBox:AddButton("Refresh Players", function() refreshPlayerList() TeleportDropdown:SetValues(playerNames) end)
    UtilBox:AddButton("Teleport", function()
        local t = Players:FindFirstChild(TeleportDropdown.Value)
        local r = getRootPart()
        if t and t.Character and t.Character:FindFirstChild("HumanoidRootPart") and r then
            r.CFrame = t.Character.HumanoidRootPart.CFrame + Vector3.new(0,3,0)
        else Library:Notify("Invalid Target", 2) end
    end)

    UtilBox:AddDivider()
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = playerNames, Default = "", AllowNull = true })
    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", { Text = "Spectate Player", Default = false })
    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if state then
            local t = Players:FindFirstChild(SpectateDropdown.Value)
            if t and t.Character and t.Character:FindFirstChild("Humanoid") then cam.CameraSubject = t.Character.Humanoid
            else Library:Notify("Target invalid", 2) SpectateToggle:SetValue(false) end
        else
            local h = getHumanoid() if h then cam.CameraSubject = h end
        end
    end)

    UtilBox:AddDivider()
    local savedWaypoints, savedNames = {}, {}
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", AllowNull = true })
    UtilBox:AddButton("Set Waypoint", function()
        local r = getRootPart()
        if r then
            local n = "WP" .. (#savedNames+1)
            savedWaypoints[n] = r.CFrame table.insert(savedNames, n) WaypointDropdown:SetValues(savedNames)
            Library:Notify("Saved " .. n, 2)
        end
    end)
    UtilBox:AddButton("Teleport to Waypoint", function()
        local s = WaypointDropdown.Value
        local r = getRootPart()
        if s and savedWaypoints[s] and r then r.CFrame = savedWaypoints[s] + Vector3.new(0,3,0) end
    end)

    local CamBox = safeAddRightGroupbox(PlayerTab, "Camera & World", "sun")
    CamBox:AddSlider("bxw_cam_fov", { Text = "Camera FOV", Default = 70, Min = 40, Max = 120, Callback = function(v) Workspace.CurrentCamera.FieldOfView = v end })
    CamBox:AddSlider("bxw_cam_maxzoom", { Text = "Max Zoom", Default = 400, Min = 10, Max = 1000, Callback = function(v) LocalPlayer.CameraMaxZoomDistance = v end })
    CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default", Callback = function(v)
        local l = Lighting
        local ids = { Space="rbxassetid://11755937810", Sunset="rbxassetid://9393701400", Midnight="rbxassetid://11755930464" }
        local old = l:FindFirstChildOfClass("Sky") if old then old:Destroy() end
        if ids[v] then
            local s = Instance.new("Sky") s.SkyboxBk, s.SkyboxDn, s.SkyboxFt, s.SkyboxLf, s.SkyboxRt, s.SkyboxUp = ids[v], ids[v], ids[v], ids[v], ids[v], ids[v] s.Parent = l
        end
    end})

    ------------------------------------------------
    -- TAB 3: ESP & Visuals (Fixed Off-Screen Bug)
    ------------------------------------------------
    local ESPTab = Tabs.ESP
    local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
    local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")

    local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP", Default = false })
    local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box" })
    local BoxToggle = ESPFeatureBox:AddToggle("bxw_esp_box", { Text = "Box", Default = true })
    local ChamsToggle = ESPFeatureBox:AddToggle("bxw_esp_chams", { Text = "Chams", Default = false })
    local SkeletonToggle = ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton", Default = false })
    local HealthToggle = ESPFeatureBox:AddToggle("bxw_esp_health", { Text = "Health Bar", Default = false })
    local NameToggle = ESPFeatureBox:AddToggle("bxw_esp_name", { Text = "Name Tag", Default = true })
    local DistToggle = ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance", Default = false })
    local TracerToggle = ESPFeatureBox:AddToggle("bxw_esp_tracer", { Text = "Tracer", Default = false })
    local TeamToggle = ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true })
    local WallToggle = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false })
    local SelfToggle = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false })
    local InfoToggle = ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info", Default = false })
    local HeadDotToggle = ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false })

    local function getPlayerNames()
        local n = {} for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(n, p.Name) end end table.sort(n) return n
    end
    local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = getPlayerNames(), Default = "", Multi = true, AllowNull = true })
    AddConnection(Players.PlayerAdded:Connect(function() WhitelistDropdown:SetValues(getPlayerNames()) end))
    AddConnection(Players.PlayerRemoving:Connect(function() WhitelistDropdown:SetValues(getPlayerNames()) end))

    ESPSettingBox:AddLabel("Box Color"):AddColorPicker("bxw_esp_box_color", { Default = Color3.fromRGB(255,255,255) })
    ESPSettingBox:AddLabel("Tracer Color"):AddColorPicker("bxw_esp_tracer_color", { Default = Color3.fromRGB(255,255,255) })
    ESPSettingBox:AddLabel("Name Color"):AddColorPicker("bxw_esp_name_color", { Default = Color3.fromRGB(255,255,255) })
    local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30 })
    ESPSettingBox:AddLabel("Distance Color"):AddColorPicker("bxw_esp_dist_color", { Default = Color3.fromRGB(255,255,255) })
    local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Distance Size", Default = 14, Min = 10, Max = 30 })
    local DistUnitDropdown = ESPSettingBox:AddDropdown("bxw_esp_dist_unit", { Text = "Distance Unit", Values = { "Studs", "Meters" }, Default = "Studs" })
    ESPSettingBox:AddLabel("Skeleton Color"):AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.fromRGB(0,255,255) })
    ESPSettingBox:AddLabel("Health Color"):AddColorPicker("bxw_esp_health_color", { Default = Color3.fromRGB(0,255,0) })
    ESPSettingBox:AddLabel("Info Color"):AddColorPicker("bxw_esp_info_color", { Default = Color3.fromRGB(255,255,255) })
    ESPSettingBox:AddLabel("Head Dot Color"):AddColorPicker("bxw_esp_headdot_color", { Default = Color3.fromRGB(255,0,0) })
    local HeadDotSizeSlider = ESPSettingBox:AddSlider("bxw_esp_headdot_size", { Text = "Head Dot Size", Default = 3, Min = 1, Max = 10 })
    ESPSettingBox:AddLabel("Chams Color"):AddColorPicker("bxw_esp_chams_color", { Default = Color3.fromRGB(0,255,0) })
    local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
    local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Visible Only", Default = false })
    local ESPRefreshSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "ESP Refresh (ms)", Default = 20, Min = 0, Max = 250 })

    local CrosshairToggle = ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
    ESPSettingBox:AddLabel("Crosshair Color"):AddColorPicker("bxw_crosshair_color", { Default = Color3.fromRGB(255,255,255) })
    local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20 })
    local CrossThickSlider = ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Crosshair Thickness", Default = 1, Min = 1, Max = 5 })

    -- ESP Logic
    local lastESPUpdate = 0
    local skeletonJoints = {{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","HumanoidRootPart"},{"LeftUpperArm","UpperTorso"},{"LeftLowerArm","LeftUpperArm"},{"LeftHand","LeftLowerArm"},{"RightUpperArm","UpperTorso"},{"RightLowerArm","RightUpperArm"},{"RightHand","RightLowerArm"},{"LeftUpperLeg","LowerTorso"},{"LeftLowerLeg","LeftUpperLeg"},{"LeftFoot","LeftLowerLeg"},{"RightUpperLeg","LowerTorso"},{"RightLowerLeg","RightUpperLeg"},{"RightFoot","RightLowerLeg"}}

    local function cleanupESP(plr)
        if espDrawings[plr] then
            for _,v in pairs(espDrawings[plr]) do
                if type(v)=="table" then for _,d in pairs(v) do pcall(function() d:Remove() end) end
                elseif typeof(v)=="Instance" then pcall(function() v:Destroy() end)
                else pcall(function() v:Remove() end) end
            end
            espDrawings[plr] = nil
        end
    end
    AddConnection(Players.PlayerRemoving:Connect(cleanupESP))

    AddConnection(RunService.RenderStepped:Connect(function()
        if ESPRefreshSlider then
            if tick() - lastESPUpdate < (ESPRefreshSlider.Value/1000) then return end
            lastESPUpdate = tick()
        end
        
        local cam = Workspace.CurrentCamera
        local enabled = ESPEnabledToggle.Value

        for _, plr in ipairs(Players:GetPlayers()) do
            if not enabled then
                cleanupESP(plr)
            elseif plr ~= LocalPlayer or SelfToggle.Value then
                local char = plr.Character
                local hum = char and char:FindFirstChild("Humanoid")
                local root = char and char:FindFirstChild("HumanoidRootPart")
                
                if char and hum and hum.Health > 0 and root then
                    local skip = false
                    if TeamToggle.Value and plr.Team == LocalPlayer.Team and plr ~= LocalPlayer then skip = true end
                    local wl = WhitelistDropdown.Value
                    if type(wl) == "table" then for _,n in ipairs(wl) do if n == plr.Name then skip = true break end end end
                    
                    if skip then
                        cleanupESP(plr)
                    else
                        if not espDrawings[plr] then espDrawings[plr] = {} end
                        local data = espDrawings[plr]
                        
                        -- WorldToViewport Check
                        local rootPos, onScreen = cam:WorldToViewportPoint(root.Position)
                        local dist = (root.Position - cam.CFrame.Position).Magnitude
                        
                        -- ** FIX: Off-Screen Handling **
                        if not onScreen then
                            -- Hide all 2D drawings if root is off-screen
                            if data.Box then data.Box.Visible = false end
                            if data.Corners then for _,l in pairs(data.Corners) do l.Visible = false end end
                            if data.Name then data.Name.Visible = false end
                            if data.Distance then data.Distance.Visible = false end
                            if data.Info then data.Info.Visible = false end
                            if data.Tracer then data.Tracer.Visible = false end
                            if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end
                            if data.HeadDot then data.HeadDot.Visible = false end
                            -- Note: Skeleton handled separately to allow partial visibility
                        end

                        -- Wall Check Logic
                        local isVis = true
                        if WallToggle.Value then
                            local rp = RaycastParams.new() rp.FilterDescendantsInstances = {char, LocalPlayer.Character} rp.FilterType = Enum.RaycastFilterType.Blacklist
                            local hit = Workspace:Raycast(cam.CFrame.Position, (root.Position - cam.CFrame.Position).Unit * dist, rp)
                            if hit then isVis = false end
                        end
                        local mainColor = isVis and Color3.fromRGB(0,255,0) or Color3.fromRGB(255,0,0)
                        
                        if onScreen then
                            -- Calculations
                            local minV, maxV = Vector3.new(math.huge,math.huge,math.huge), Vector3.new(-math.huge,-math.huge,-math.huge)
                            for _,p in ipairs(char:GetChildren()) do
                                if p:IsA("BasePart") then
                                    minV = Vector3.new(math.min(minV.X, p.Position.X), math.min(minV.Y, p.Position.Y), math.min(minV.Z, p.Position.Z))
                                    maxV = Vector3.new(math.max(maxV.X, p.Position.X), math.max(maxV.Y, p.Position.Y), math.max(maxV.Z, p.Position.Z))
                                end
                            end
                            local s, c = maxV - minV, (maxV + minV) / 2
                            local sc, vis = cam:WorldToViewportPoint(c)
                            local tl = cam:WorldToViewportPoint(c + Vector3.new(0, s.Y/2, 0))
                            local bl = cam:WorldToViewportPoint(c - Vector3.new(0, s.Y/2, 0))
                            local h = math.abs(tl.Y - bl.Y)
                            local w = h * 0.6
                            local x, y = sc.X - w/2, sc.Y - h/2
                            
                            local bCol = WallToggle.Value and mainColor or Options.bxw_esp_box_color.Value

                            -- 1. Box
                            if BoxToggle.Value then
                                if BoxStyleDropdown.Value == "Box" then
                                    if not data.Box then data.Box = Drawing.new("Square") data.Box.Thickness = 1 data.Box.Filled = false end
                                    data.Box.Visible = true data.Box.Color = bCol data.Box.Position = Vector2.new(x,y) data.Box.Size = Vector2.new(w,h)
                                    if data.Corners then for _,l in pairs(data.Corners) do l.Visible = false end end
                                else
                                    if not data.Corners then data.Corners = {} for i=1,8 do data.Corners[i] = Drawing.new("Line") data.Corners[i].Thickness = 1 end end
                                    if data.Box then data.Box.Visible = false end
                                    local cw, ch = w*0.25, h*0.25
                                    local function dLine(i, f, t) data.Corners[i].Visible = true data.Corners[i].Color = bCol data.Corners[i].From = f data.Corners[i].To = t end
                                    dLine(1, Vector2.new(x,y), Vector2.new(x+cw,y)) dLine(2, Vector2.new(x,y), Vector2.new(x,y+ch))
                                    dLine(3, Vector2.new(x+w,y), Vector2.new(x+w-cw,y)) dLine(4, Vector2.new(x+w,y), Vector2.new(x+w,y+ch))
                                    dLine(5, Vector2.new(x,y+h), Vector2.new(x+cw,y+h)) dLine(6, Vector2.new(x,y+h), Vector2.new(x,y+h-ch))
                                    dLine(7, Vector2.new(x+w,y+h), Vector2.new(x+w-cw,y+h)) dLine(8, Vector2.new(x+w,y+h), Vector2.new(x+w,y+h-ch))
                                end
                            else
                                if data.Box then data.Box.Visible = false end
                                if data.Corners then for _,l in pairs(data.Corners) do l.Visible = false end end
                            end

                            -- 2. Name
                            if NameToggle.Value then
                                if not data.Name then data.Name = Drawing.new("Text") data.Name.Center = true data.Name.Outline = true end
                                data.Name.Visible = true
                                data.Name.Text = plr.DisplayName
                                data.Name.Size = NameSizeSlider.Value
                                data.Name.Color = WallToggle.Value and mainColor or Options.bxw_esp_name_color.Value
                                data.Name.Position = Vector2.new(sc.X, y - 16)
                            else if data.Name then data.Name.Visible = false end end

                            -- 3. Distance
                            if DistToggle.Value then
                                if not data.Distance then data.Distance = Drawing.new("Text") data.Distance.Center = true data.Distance.Outline = true end
                                data.Distance.Visible = true
                                local unit = DistUnitDropdown.Value == "Meters" and "m" or "st"
                                local dVal = DistUnitDropdown.Value == "Meters" and dist * 0.28 or dist
                                data.Distance.Text = string.format("%.0f %s", dVal, unit)
                                data.Distance.Size = DistSizeSlider.Value
                                data.Distance.Color = WallToggle.Value and mainColor or Options.bxw_esp_dist_color.Value
                                data.Distance.Position = Vector2.new(sc.X, y + h + 2)
                            else if data.Distance then data.Distance.Visible = false end end

                            -- 4. Target Info
                            if InfoToggle.Value then
                                if not data.Info then data.Info = Drawing.new("Text") data.Info.Center = true data.Info.Outline = true end
                                data.Info.Visible = true
                                local unit = DistUnitDropdown.Value == "Meters" and "m" or "st"
                                local dVal = DistUnitDropdown.Value == "Meters" and dist * 0.28 or dist
                                local tName = (plr.Team and plr.Team.Name) or "None"
                                data.Info.Text = string.format("[HP:%d] [Dist:%.0f%s] [Team:%s]", hum.Health, dVal, unit, tName)
                                data.Info.Size = NameSizeSlider.Value
                                data.Info.Color = WallToggle.Value and mainColor or Options.bxw_esp_info_color.Value
                                data.Info.Position = Vector2.new(sc.X, y + h + 15)
                            else if data.Info then data.Info.Visible = false end end

                            -- 5. Tracer
                            if TracerToggle.Value then
                                if not data.Tracer then data.Tracer = Drawing.new("Line") data.Tracer.Thickness = 1 end
                                data.Tracer.Visible = true
                                data.Tracer.Color = WallToggle.Value and mainColor or Options.bxw_esp_tracer_color.Value
                                data.Tracer.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
                                data.Tracer.To = Vector2.new(sc.X, sc.Y)
                            else if data.Tracer then data.Tracer.Visible = false end end

                            -- 6. Health
                            if HealthToggle.Value then
                                if not data.Health then data.Health = {Outline=Drawing.new("Line"), Bar=Drawing.new("Line")} data.Health.Outline.Thickness=3 data.Health.Bar.Thickness=1 end
                                local hpH = (h * (hum.Health / hum.MaxHealth))
                                data.Health.Outline.Visible = true data.Health.Outline.Color = Color3.new(0,0,0)
                                data.Health.Outline.From = Vector2.new(x-6, y) data.Health.Outline.To = Vector2.new(x-6, y+h)
                                data.Health.Bar.Visible = true data.Health.Bar.Color = (Options.bxw_esp_health_color and Options.bxw_esp_health_color.Value) or mainColor
                                data.Health.Bar.From = Vector2.new(x-6, y+h) data.Health.Bar.To = Vector2.new(x-6, y+h-hpH)
                            else if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end end

                            -- 7. Head Dot
                             if HeadDotToggle.Value then
                                local head = char:FindFirstChild("Head")
                                if head then
                                    local hv, hon = cam:WorldToViewportPoint(head.Position)
                                    if hon then
                                        if not data.HeadDot then data.HeadDot = Drawing.new("Circle") data.HeadDot.Filled = true end
                                        data.HeadDot.Visible = true data.HeadDot.Radius = 3
                                        data.HeadDot.Color = WallToggle.Value and mainColor or Options.bxw_esp_headdot_color.Value
                                        data.HeadDot.Position = Vector2.new(hv.X, hv.Y)
                                    else if data.HeadDot then data.HeadDot.Visible = false end end
                                end
                            else if data.HeadDot then data.HeadDot.Visible = false end end
                        end

                        -- 8. Skeleton (Robust Off-Screen Check)
                        if SkeletonToggle.Value then
                            if not data.Skeleton then data.Skeleton = {} end
                            local skCol = WallToggle.Value and mainColor or Options.bxw_esp_skeleton_color.Value
                            for i, joint in ipairs(skeletonJoints) do
                                local p1 = char:FindFirstChild(joint[1])
                                local p2 = char:FindFirstChild(joint[2])
                                local ln = data.Skeleton[i]
                                if not ln then ln = Drawing.new("Line") ln.Thickness = 1 data.Skeleton[i] = ln end
                                if p1 and p2 then
                                    local v1, on1 = cam:WorldToViewportPoint(p1.Position)
                                    local v2, on2 = cam:WorldToViewportPoint(p2.Position)
                                    -- **FIX**: Hide line if BOTH points are off screen, or just hide if one is off (cleaner)
                                    if on1 or on2 then 
                                        ln.Visible = true ln.Color = skCol
                                        ln.From = Vector2.new(v1.X, v1.Y) ln.To = Vector2.new(v2.X, v2.Y)
                                    else ln.Visible = false end
                                else ln.Visible = false end
                            end
                        else if data.Skeleton then for _,l in pairs(data.Skeleton) do l.Visible = false end end end

                        -- 9. Chams (Highlight)
                        if ChamsToggle.Value then
                            if not data.Highlight then data.Highlight = Instance.new("Highlight", char) end
                            data.Highlight.Enabled = true
                            data.Highlight.FillColor = WallToggle.Value and mainColor or Options.bxw_esp_chams_color.Value
                            data.Highlight.OutlineColor = data.Highlight.FillColor
                            data.Highlight.FillTransparency = ChamsTransSlider.Value
                            data.Highlight.DepthMode = ChamsVisibleToggle.Value and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                        else if data.Highlight then data.Highlight.Enabled = false end end
                    end
                else
                    cleanupESP(plr)
                end
            end
        end
        
        -- Crosshair Update
        if not crosshairLines then crosshairLines = {h=Drawing.new("Line"),v=Drawing.new("Line")} end
        if CrosshairToggle.Value then
            local cx, cy = cam.ViewportSize.X/2, cam.ViewportSize.Y/2
            local sz, th = CrossSizeSlider.Value, CrossThickSlider.Value
            local col = Options.bxw_crosshair_color.Value
            crosshairLines.h.Visible = true crosshairLines.h.From = Vector2.new(cx-sz,cy) crosshairLines.h.To = Vector2.new(cx+sz,cy) crosshairLines.h.Thickness=th crosshairLines.h.Color=col
            crosshairLines.v.Visible = true crosshairLines.v.From = Vector2.new(cx,cy-sz) crosshairLines.v.To = Vector2.new(cx,cy+sz) crosshairLines.v.Thickness=th crosshairLines.v.Color=col
        else
            crosshairLines.h.Visible = false crosshairLines.v.Visible = false
        end
    end))

    ------------------------------------------------
    -- TAB 4: Combat (Full Features)
    ------------------------------------------------
    local CombatTab = Tabs.Combat
    local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
    local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

    AimBox:AddLabel("Core")
    local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false })
    local SilentToggle = AimBox:AddToggle("bxw_silent_enable", { Text = "Silent Aim", Default = false })
    local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "Torso", "Random" }, Default = "Head" })
    local UseSmartAimLogic = AimBox:AddToggle("bxw_aim_smart_logic", { Text = "Smart Aim Logic", Default = true, Tooltip = "Auto calc target based on Dist/HP" })

    AimBox:AddLabel("FOV")
    local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50 })
    local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
    local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Smoothness", Default = 0.1, Min = 0.01, Max = 1 })
    
    local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
    local VisibilityToggle = AimBox:AddToggle("bxw_aim_visibility", { Text = "Visibility Check", Default = false })
    
    AimBox:AddLabel("Colors")
    AimBox:AddLabel("FOV Color"):AddColorPicker("bxw_aim_fovcolor", { Default = Color3.fromRGB(255,255,255) })
    
    ExtraBox:AddLabel("Triggerbot")
    local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false })
    local TriggerDelay = ExtraBox:AddSlider("bxw_trigger_delay", { Text = "Delay (s)", Default = 0, Min = 0, Max = 1, Rounding = 2 })
    
    -- Aimbot Loop
    AimbotFOVCircle = Drawing.new("Circle") AimbotFOVCircle.Thickness = 1 AimbotFOVCircle.Filled = false
    AddConnection(RunService.RenderStepped:Connect(function()
        AimbotFOVCircle.Visible = ShowFovToggle.Value
        AimbotFOVCircle.Radius = FOVSlider.Value * 15
        AimbotFOVCircle.Position = UserInputService:GetMouseLocation()
        AimbotFOVCircle.Color = Options.bxw_aim_fovcolor.Value

        if AimbotToggle.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local cam = Workspace.CurrentCamera
            local ms = UserInputService:GetMouseLocation()
            local best, bestScore = nil, math.huge
            
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("Head") then
                    if not AimTeamCheck.Value or p.Team ~= LocalPlayer.Team then
                        local hum = p.Character:FindFirstChild("Humanoid")
                        if hum and hum.Health > 0 then
                            local part = p.Character[AimPartDropdown.Value == "Random" and "Head" or AimPartDropdown.Value] or p.Character.Head
                            local pos, onScreen = cam:WorldToViewportPoint(part.Position)
                            if onScreen then
                                local dist = (Vector2.new(pos.X, pos.Y) - ms).Magnitude
                                if dist <= AimbotFOVCircle.Radius then
                                    local isVis = true
                                    if VisibilityToggle.Value then
                                        local rp = RaycastParams.new() rp.FilterDescendantsInstances = {p.Character, LocalPlayer.Character}
                                        if Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, rp) then isVis = false end
                                    end
                                    
                                    if isVis then
                                        local score = dist
                                        if UseSmartAimLogic.Value then
                                            local distPlr = (LocalPlayer.Character.HumanoidRootPart.Position - part.Position).Magnitude
                                            score = dist + (distPlr * 0.5) + (hum.Health * 0.1)
                                        end
                                        if score < bestScore then bestScore = score best = part end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            if best then
                local smooth = SmoothSlider.Value
                local current = cam.CFrame
                local target = CFrame.new(current.Position, best.Position)
                cam.CFrame = current:Lerp(target, smooth)
                
                if TriggerbotToggle.Value then
                    local msDist = (Vector2.new(cam:WorldToViewportPoint(best.Position).X, cam:WorldToViewportPoint(best.Position).Y) - ms).Magnitude
                    if msDist < 20 then
                        task.delay(TriggerDelay.Value, function() mouse1click() end)
                    end
                end
            end
        end
    end))

    ------------------------------------------------
    -- TAB 5: Misc & System (REORGANIZED PER INSTRUCTION)
    ------------------------------------------------
    local MiscTab = Tabs.Misc
    
    -- 1. Game Tool (Left)
    local GameToolBox = MiscTab:AddLeftGroupbox("Game Tool", "tool")
    local AntiRejoinToggle = GameToolBox:AddToggle("bxw_antirejoin", { Text = "Auto Rejoin on Kick", Default = false })
    local AntiAfkToggle = GameToolBox:AddToggle("bxw_anti_afk", { Text = "Anti-AFK", Default = true })
    
    local lastKick = 0
    AddConnection(GuiService.ErrorMessageChanged:Connect(function()
        if AntiRejoinToggle.Value then
            local t = tick()
            if t - lastKick > 5 then
                lastKick = t
                warn("Kick detected. Rejoining...")
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end
    end))
    local afkConn
    AntiAfkToggle:OnChanged(function(v)
        if v then afkConn = AddConnection(LocalPlayer.Idled:Connect(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end))
        elseif afkConn then afkConn:Disconnect() end
    end)

    -- 2. Fun & Utility (Left)
    local FunBox = MiscTab:AddLeftGroupbox("Fun & Utility", "smile")
    local SpinToggle = FunBox:AddToggle("bxw_spinbot", { Text = "SpinBot", Default = false })
    local SpinSpeed = FunBox:AddSlider("bxw_spin_speed", { Text = "Spin Speed", Default = 5, Min = 1, Max = 20 })
    local ReverseSpin = FunBox:AddToggle("bxw_spin_reverse", { Text = "Reverse Spin", Default = false })
    local AntiFling = FunBox:AddToggle("bxw_antifling", { Text = "Anti Fling", Default = false })
    local JerkToggle = FunBox:AddToggle("bxw_jerktool", { Text = "Jerk Tool", Default = false })
    
    FunBox:AddButton("BTools", function()
        local bp = LocalPlayer.Backpack
        local t = {Enum.BinType.Clone, Enum.BinType.Hammer, Enum.BinType.Grab}
        for _,v in ipairs(t) do local b = Instance.new("HopperBin", bp) b.BinType = v end
        Library:Notify("BTools added", 2)
    end)
    FunBox:AddButton("Teleport Tool", function()
        local t = Instance.new("Tool", LocalPlayer.Backpack) t.Name = "TeleportTool" t.RequiresHandle = false
        t.Activated:Connect(function()
            local m = LocalPlayer:GetMouse()
            if m.Hit then getRootPart().CFrame = CFrame.new(m.Hit.Position + Vector3.new(0,3,0)) end
        end)
        Library:Notify("TP Tool added", 2)
    end)

    local spinC
    SpinToggle:OnChanged(function(v)
        if v then
            spinC = AddConnection(RunService.RenderStepped:Connect(function(dt)
                local r = getRootPart()
                if r then r.CFrame = r.CFrame * CFrame.Angles(0, SpinSpeed.Value * dt * (ReverseSpin.Value and -1 or 1), 0) end
            end))
        elseif spinC then spinC:Disconnect() end
    end)
    local flingC
    AntiFling:OnChanged(function(v)
        if v then
            flingC = AddConnection(RunService.Stepped:Connect(function()
                local r = getRootPart()
                if r then
                    if r.AssemblyLinearVelocity.Magnitude > 100 then r.AssemblyLinearVelocity = Vector3.zero end
                    if r.AssemblyAngularVelocity.Magnitude > 100 then r.AssemblyAngularVelocity = Vector3.zero end
                end
            end))
        elseif flingC then flingC:Disconnect() end
    end)
    local jerkT
    JerkToggle:OnChanged(function(v)
        if v then
            jerkT = Instance.new("Tool", LocalPlayer.Backpack) jerkT.Name = "Jerk" jerkT.RequiresHandle=false
            jerkT.Activated:Connect(function()
                local m = LocalPlayer:GetMouse()
                if m.Target then
                    local v = Instance.new("BodyVelocity", m.Target) v.Velocity = m.Hit.LookVector * 100 v.MaxForce = Vector3.new(1e9,1e9,1e9) game.Debris:AddItem(v, 0.3)
                end
            end)
        elseif jerkT then jerkT:Destroy() end
    end)

    -- 3. Environment (Right)
    local EnvBox = safeAddRightGroupbox(MiscTab, "Environment", "sun")
    EnvBox:AddSlider("bxw_gravity", { Text = "Gravity", Default = Workspace.Gravity, Min = 0, Max = 300, Callback = function(v) Workspace.Gravity = v end })
    EnvBox:AddToggle("bxw_nofog", { Text = "No Fog", Default = false, Callback = function(v) if v then Lighting.FogEnd = 1e9 else Lighting.FogEnd = 1000 end end })
    EnvBox:AddSlider("bxw_brightness", { Text = "Brightness", Default = Lighting.Brightness, Min = 0, Max = 10, Callback = function(v) Lighting.Brightness = v end })
    EnvBox:AddLabel("Ambient"):AddColorPicker("bxw_ambient", { Default = Lighting.Ambient, Callback = function(v) Lighting.Ambient = v end })

    -- 4. Server (Right - New)
    local ServerBox = safeAddRightGroupbox(MiscTab, "Server", "server")
    ServerBox:AddButton("Rejoin Server", function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
    
    local HopDropdown = ServerBox:AddDropdown("bxw_hop_mode", { Text = "Hop Mode", Values = { "Normal", "Low Users", "High Users" }, Default = "Normal" })
    ServerBox:AddButton("Server Hop", function()
        local mode = HopDropdown.Value
        Library:Notify("Hopping ("..mode..")...", 3)
        pcall(function()
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
            local data = HttpService:JSONDecode(game:HttpGet(url))
            if data and data.data then
                local servers = {}
                for _, s in ipairs(data.data) do
                    if s.playing < s.maxPlayers and s.id ~= game.JobId then table.insert(servers, s) end
                end
                
                if #servers > 0 then
                    if mode == "Low Users" then
                        table.sort(servers, function(a,b) return a.playing < b.playing end)
                    elseif mode == "High Users" then
                        table.sort(servers, function(a,b) return a.playing > b.playing end)
                    else
                        -- Normal = Random
                        for i = #servers, 2, -1 do local j = math.random(i) servers[i], servers[j] = servers[j], servers[i] end
                    end
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LocalPlayer)
                else
                    Library:Notify("No server found", 3)
                end
            end
        end)
    end)

    local JobIdInput = ServerBox:AddInput("bxw_jobid", { Text = "Join JobId", Default = "", Placeholder = "JobId here..." })
    ServerBox:AddButton("Join JobId", function()
        local id = JobIdInput.Value
        if id and id ~= "" then TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer) end
    end)

    ------------------------------------------------
    -- TAB 6: Settings
    ------------------------------------------------
    local SettingsTab = Tabs.Settings
    local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
    MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(v) Library.KeybindFrame.Visible = v end })
    MenuGroup:AddToggle("ShowCustomCursor", { Text = "Custom Cursor", Default = true, Callback = function(v) Library.ShowCustomCursor = v end })
    MenuGroup:AddDropdown("NotificationSide", { Values = {"Left","Right"}, Default = "Right", Text = "Notification Side", Callback = function(v) Library:SetNotifySide(v) end })
    MenuGroup:AddDropdown("DPIDropdown", { Values = {"50%","75%","100%","125%","150%","200%"}, Default = "100%", Text = "DPI Scale", Callback = function(v) Library:SetDPIScale(tonumber(v:gsub("%%",""))) end })
    MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
    Library.ToggleKeybind = Options.MenuKeybind

    MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
    MenuGroup:AddButton("Reload UI", function() Library:Unload() warn("UI Reloaded") end)

    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    ThemeManager:SetFolder("BxB.Ware")
    SaveManager:SetFolder("BxB.Ware")
    SaveManager:BuildConfigSection(SettingsTab)
    ThemeManager:ApplyToTab(SettingsTab)
    SaveManager:LoadAutoloadConfig()

    -- Cleanup
    Library:OnUnload(function()
        for _,c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        for _,p in pairs(espDrawings) do
            for _,o in pairs(p) do
                if type(o)=="table" then for _,i in pairs(o) do pcall(function() i:Remove() end) end
                elseif typeof(o)=="Instance" then pcall(function() o:Destroy() end)
                else pcall(function() o:Remove() end) end
            end
        end
        if AimbotFOVCircle then AimbotFOVCircle:Remove() end
        if crosshairLines then crosshairLines.h:Remove() crosshairLines.v:Remove() end
    end)
end

--====================================================
-- 5. Return function
--====================================================
return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then warn("[MainHub] Error:", err) end
end
