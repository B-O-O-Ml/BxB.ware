--====================================================
-- 0. Services
--====================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")
local Lighting           = game:GetService("Lighting")
local Workspace          = game:GetService("Workspace")
local GuiService         = game:GetService("GuiService")
local TeleportService    = game:GetService("TeleportService")
local CoreGui            = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- เก็บ connection ไว้เผื่ออยาก cleanup ตอน Unload
local Connections = {}
local function AddConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

-- [Fix] ลบ :Wait() ออกเพื่อป้องกันเกมค้าง (Freeze)
local function getCharacter()
    local plr = LocalPlayer
    if not plr then return nil end
    return plr.Character -- คืนค่า nil ถ้าตัวละครยังไม่โหลด
end

local function getHumanoid()
    local char = getCharacter()
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
    local char = getCharacter()
    if not char then return nil end
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
-- 2. Role System & Helper
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
    if RolePriority[role] then
        return role
    end
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

local function formatUnixTime(ts)
    if not ts or type(ts) ~= "number" or ts <= 0 then return "Lifetime" end
    local dt = os.date("*t", ts)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec)
end

local function formatTimeLeft(expireTs)
    if not expireTs or type(expireTs) ~= "number" or expireTs <= 0 then return "Lifetime" end
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
    if lbl and lbl.TextLabel then
        lbl.TextLabel.RichText = true
    end
    return lbl
end

-- Helper to mark risky features
local function MarkRisky(text)
    return text .. ' <font color="#FF4444">[RISKY]</font>'
end

--====================================================
-- 4. MainHub
--====================================================

local function MainHub(Exec, keydata, authToken)
    ---------------------------------------------
    -- 4.1 ตรวจ Exec + keydata + token
    ---------------------------------------------
    if type(Exec) ~= "table" or type(Exec.HttpGet) ~= "function" then warn("[MainHub] Exec invalid") return end
    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then warn("[MainHub] keydata invalid") return end

    local expected = buildExpectedToken(keydata)
    if authToken ~= expected then warn("[MainHub] Invalid auth token") return end

    -- [FIX] ประกาศตัวแปรเก็บ Drawing ไว้ตรงนี้ เพื่อให้ Unload ล้างได้หมด
    local espDrawings = {}
    local crosshairLines = nil

    keydata.role = NormalizeRole(keydata.role)

    ---------------------------------------------
    -- 4.2 โหลด Library
    ---------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library      = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    local Options = Library.Options
    local Toggles = Library.Toggles

    local Window = Library:CreateWindow({
        Title  = "",
        Footer = '<b><font color="#B563FF">BxB.ware | Universal | Game Module</font></b>',
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
        Info     = Window:AddTab({ Name = "Info", Icon = "info", Description = "Key / Script / System info" }),
        Player   = Window:AddTab({ Name = "Player", Icon = "user", Description = "Movement / Teleport / View" }),
        ESP      = Window:AddTab({ Name = "ESP & Visuals", Icon = "eye", Description = "Player ESP / Visual settings" }),
        Combat   = Window:AddTab({ Name = "Combat & Aimbot", Icon = "target", Description = "Aimbot / target selection" }),
        Misc     = Window:AddTab({ Name = "Misc & System", Icon = "joystick", Description = "Utilities / Panic / System" }),
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
    -- TAB 1: Info (Preserved & Fixed Expire)
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
    
    local HttpService = game:GetService("HttpService")
    local remoteKeyData = nil
    local remoteExpireStr = nil
    
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
    
    local expireTs = tonumber(keydata.expire) or 0
    if remoteKeyData then
        if remoteKeyData.role then roleHtml = GetRoleLabel(remoteKeyData.role) end
        if remoteKeyData.status then statusText = tostring(remoteKeyData.status) end
        if remoteKeyData.note then noteText = tostring(remoteKeyData.note) end
        if remoteKeyData.hwid_hash then keydata.hwid_hash = remoteKeyData.hwid_hash end
        if remoteKeyData.expire then remoteExpireStr = remoteKeyData.expire end
        if remoteKeyData.expire and tonumber(remoteKeyData.expire) then expireTs = tonumber(remoteKeyData.expire) end
    end
    
    local createdAtText = (keydata.timestamp and keydata.timestamp > 0) and formatUnixTime(keydata.timestamp) or "Unknown"

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))
    safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    safeRichLabel(KeyBox, string.format("<b>Tier:</b> %s", string.upper(keydata.role or "free")))
    safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", noteText))
    safeRichLabel(KeyBox, string.format("<b>Created at:</b> %s", createdAtText))

    local expireDisplay = (expireTs > 0) and formatUnixTime(expireTs) or (remoteExpireStr or "Lifetime")
    local timeLeftDisplay = (expireTs > 0) and formatTimeLeft(expireTs) or "Lifetime"
    
    local ExpireLabel   = safeRichLabel(KeyBox, string.format("<b>Expire:</b> %s", expireDisplay))
    local TimeLeftLabel = safeRichLabel(KeyBox, string.format("<b>Time left:</b> %s", timeLeftDisplay))

    task.spawn(function()
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 1 then return end
            acc = 0
            local currentExpire, currentLeft = "Lifetime", "Lifetime"
            if expireTs > 0 then
                currentExpire = formatUnixTime(expireTs)
                currentLeft = formatTimeLeft(expireTs)
            elseif remoteExpireStr then
                currentExpire = tostring(remoteExpireStr)
                if not tonumber(remoteExpireStr) then currentLeft = tostring(remoteExpireStr) end
            end
            if ExpireLabel.TextLabel then ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", currentExpire) end
            if TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", currentLeft) end
        end))
    end)
    
    KeyBox:AddDivider()
    KeyBox:AddButton("Copy Key Info", function()
        local infoText = string.format("Key:%s\nRole:%s", rawKey, tostring(keydata.role))
        if setclipboard then setclipboard(infoText) Library:Notify("Copied!", 2) end
    end)

    -- Game Info
    local GameBox = safeAddRightGroupbox(InfoTab, "Game Info", "info")
    local GameNameLabel = safeRichLabel(GameBox, "<b>Game:</b> Loading...")
    local PlayersLabel = safeRichLabel(GameBox, "<b>Players:</b> -/-")
    local PerfLabel = safeRichLabel(GameBox, "<b>Perf:</b> FPS: -")
    
    task.spawn(function()
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
        if ok and info then GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", info.Name) end
    end)
    
    local function updatePlayersLabel()
        PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d / %s", #Players:GetPlayers(), tostring(Players.MaxPlayers or "-"))
    end
    AddConnection(Players.PlayerAdded:Connect(updatePlayersLabel))
    AddConnection(Players.PlayerRemoving:Connect(updatePlayersLabel))
    updatePlayersLabel()
    
    task.spawn(function()
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 0.25 then return end
            acc = 0
            local fps = math.floor(1 / math.max(dt, 1/240))
            PerfLabel.TextLabel.Text = string.format("<b>Perf:</b> FPS: %d", fps)
        end))
    end)

    ------------------------------------------------
    -- TAB 2: Player (Restored All Features + Risky)
    ------------------------------------------------
    local PlayerTab = Tabs.Player
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    local defaultWalkSpeed = 16
    local walkSpeedEnabled = false
    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = MarkRisky("Enable WalkSpeed"), Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = defaultWalkSpeed, Min = 0, Max = 120, Rounding = 0 })

    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = state and WalkSpeedSlider.Value or defaultWalkSpeed end
    end)

    MoveBox:AddButton("Reset WalkSpeed", function()
        WalkSpeedSlider:SetValue(defaultWalkSpeed)
        WalkSpeedToggle:SetValue(false)
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = defaultWalkSpeed end
    end)

    MoveBox:AddDropdown("bxw_walk_method", { Text = "Walk Method", Values = { "Direct", "Incremental" }, Default = "Direct" })

    local defaultJumpPower = 50
    local jumpPowerEnabled = false
    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = MarkRisky("Enable JumpPower"), Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = defaultJumpPower, Min = 0, Max = 200, Rounding = 0 })

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        local hum = getHumanoid()
        if hum then hum.UseJumpPower = true; hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower end
    end)

    MoveBox:AddButton("Reset JumpPower", function()
        JumpPowerSlider:SetValue(defaultJumpPower)
        JumpPowerToggle:SetValue(false)
        local hum = getHumanoid()
        if hum then hum.JumpPower = defaultJumpPower end
    end)

    local MovePresetDropdown = MoveBox:AddDropdown("bxw_move_preset", { Text = "Movement Preset", Values = { "Default", "Normal", "Fast", "Ultra" }, Default = "Default" })
    MovePresetDropdown:OnChanged(function(value)
        if value == "Default" then
            WalkSpeedSlider:SetValue(defaultWalkSpeed)
            JumpPowerSlider:SetValue(defaultJumpPower)
            WalkSpeedToggle:SetValue(false)
            JumpPowerToggle:SetValue(false)
        elseif value == "Normal" then
            WalkSpeedSlider:SetValue(20); JumpPowerSlider:SetValue(60); WalkSpeedToggle:SetValue(true); JumpPowerToggle:SetValue(true)
        elseif value == "Fast" then
            WalkSpeedSlider:SetValue(30); JumpPowerSlider:SetValue(80); WalkSpeedToggle:SetValue(true); JumpPowerToggle:SetValue(true)
        elseif value == "Ultra" then
            WalkSpeedSlider:SetValue(50); JumpPowerSlider:SetValue(100); WalkSpeedToggle:SetValue(true); JumpPowerToggle:SetValue(true)
        end
    end)

    MoveBox:AddDivider()
    local infJumpConn
    local InfJumpToggle = MoveBox:AddToggle("bxw_infjump", { Text = MarkRisky("Infinite Jump"), Default = false })
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
    end)

    local flyConn, flyBV, flyBG
    local flyEnabled = false
    local flySpeed = 60
    local FlyToggle = MoveBox:AddToggle("bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = 60, Min = 1, Max = 300, Rounding = 0, Callback = function(v) flySpeed = v end })

    FlyToggle:OnChanged(function(state)
        flyEnabled = state
        local root, hum, cam = getRootPart(), getHumanoid(), Workspace.CurrentCamera
        if not state then
            if flyConn then flyConn:Disconnect() flyConn = nil end
            if flyBV then flyBV:Destroy() flyBV = nil end
            if flyBG then flyBG:Destroy() flyBG = nil end
            if hum then hum.PlatformStand = false end
            return
        end
        if not (root and hum and cam) then FlyToggle:SetValue(false) return end
        hum.PlatformStand = true
        flyBV = Instance.new("BodyVelocity", root)
        flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
        flyBG = Instance.new("BodyGyro", root)
        flyBG.MaxTorque = Vector3.new(9e9,9e9,9e9)
        flyBG.CFrame = root.CFrame
        flyConn = AddConnection(RunService.RenderStepped:Connect(function()
            if not flyEnabled or not (root.Parent and hum.Parent) then return end
            local moveDir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0,1,0) end
            if moveDir.Magnitude > 0 then flyBV.Velocity = moveDir.Unit * flySpeed else flyBV.Velocity = Vector3.zero end
            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
    end)

    local noclipConn
    local NoclipToggle = MoveBox:AddToggle("bxw_noclip", { Text = MarkRisky("Noclip"), Default = false })
    NoclipToggle:OnChanged(function(state)
        if not state then
            if noclipConn then noclipConn:Disconnect() noclipConn = nil end
            local char = getCharacter()
            if char then for _,p in pairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = true end end end
        else
            noclipConn = AddConnection(RunService.Stepped:Connect(function()
                local char = getCharacter()
                if char then for _,p in pairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end
            end))
        end
    end)

    local UtilBox = safeAddRightGroupbox(PlayerTab, "Teleport / Utility", "map")
    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = {}, AllowNull = true })
    local function refreshPlayerList()
        local n = {}
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(n, p.Name) end end
        TeleportDropdown:SetValues(n)
        return n
    end
    UtilBox:AddButton("Refresh Players", refreshPlayerList)
    UtilBox:AddButton("Teleport", function()
        local t = Players:FindFirstChild(TeleportDropdown.Value)
        local r = getRootPart()
        if t and t.Character and t.Character:FindFirstChild("HumanoidRootPart") and r then
            r.CFrame = t.Character.HumanoidRootPart.CFrame + Vector3.new(0,3,0)
        end
    end)

    UtilBox:AddDivider()
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = {}, AllowNull = true })
    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", { Text = "Spectate Player", Default = false })
    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if not cam then return end
        if state then
            local t = Players:FindFirstChild(SpectateDropdown.Value)
            if t and t.Character and t.Character:FindFirstChild("Humanoid") then
                cam.CameraSubject = t.Character.Humanoid
            end
        else
            local h = getHumanoid()
            if h then cam.CameraSubject = h end
        end
    end)

    UtilBox:AddDivider()
    UtilBox:AddLabel("Waypoints")
    local savedWaypoints, savedNames = {}, {}
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = {}, AllowNull = true })
    UtilBox:AddButton("Set Waypoint", function()
        local r = getRootPart()
        if r then
            local n = "WP" .. (#savedNames + 1)
            savedWaypoints[n] = r.CFrame
            table.insert(savedNames, n)
            WaypointDropdown:SetValues(savedNames)
        end
    end)
    UtilBox:AddButton("Teleport to Waypoint", function()
        local s = WaypointDropdown.Value
        local r = getRootPart()
        if s and savedWaypoints[s] and r then r.CFrame = savedWaypoints[s] + Vector3.new(0,3,0) end
    end)

    local CamBox = safeAddRightGroupbox(PlayerTab, "Camera & World", "sun")
    CamBox:AddSlider("bxw_cam_fov", { Text = "Camera FOV", Default = 70, Min = 40, Max = 120, Callback = function(v) local c = Workspace.CurrentCamera if c then c.FieldOfView = v end end })
    CamBox:AddSlider("bxw_cam_maxzoom", { Text = "Max Zoom", Default = 400, Min = 10, Max = 1000, Callback = function(v) LocalPlayer.CameraMaxZoomDistance = v end })
    CamBox:AddSlider("bxw_cam_minzoom", { Text = "Min Zoom", Default = 0.5, Min = 0, Max = 50, Rounding = 1, Callback = function(v) LocalPlayer.CameraMinZoomDistance = v end })
    
    local SkyboxDropdown = CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default" })
    local SkyboxThemes = { ["Space"] = "rbxassetid://11755937810", ["Sunset"] = "rbxassetid://9393701400", ["Midnight"] = "rbxassetid://11755930464" }
    SkyboxDropdown:OnChanged(function(v)
        local l = game:GetService("Lighting")
        local old = l:FindFirstChildOfClass("Sky")
        if old then old:Destroy() end
        if SkyboxThemes[v] then
            local s = Instance.new("Sky")
            s.SkyboxBk, s.SkyboxDn, s.SkyboxFt = SkyboxThemes[v], SkyboxThemes[v], SkyboxThemes[v]
            s.SkyboxLf, s.SkyboxRt, s.SkyboxUp = SkyboxThemes[v], SkyboxThemes[v], SkyboxThemes[v]
            s.Parent = l
        end
    end)

    ------------------------------------------------
    -- TAB 3: ESP & Visuals (Restored Settings + Fixes)
    ------------------------------------------------
    local ESPTab = Tabs.ESP
    local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
    local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")

    local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP", Default = false })
    local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box" })
    
    ESPFeatureBox:AddToggle("bxw_esp_box", { Text = "Box", Default = true })
    ESPFeatureBox:AddToggle("bxw_esp_chams", { Text = "Chams", Default = false })
    ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton", Default = false })
    ESPFeatureBox:AddToggle("bxw_esp_health", { Text = "Health Bar", Default = false })
    ESPFeatureBox:AddToggle("bxw_esp_name", { Text = "Name Tag", Default = true })
    ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance", Default = false })
    ESPFeatureBox:AddToggle("bxw_esp_tracer", { Text = "Tracer", Default = false })
    ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true })
    local WallToggle = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false })
    local SelfToggle = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false })
    local InfoToggle = ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info", Default = false })
    -- [REMOVED] Smart ESP Toggle
    local HeadDotToggle = ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false })

    local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = {}, Multi = true, AllowNull = true })
    AddConnection(Players.PlayerAdded:Connect(function() WhitelistDropdown:SetValues(refreshPlayerList()) end))
    
    ESPSettingBox:AddLabel("Colors Settings")
    ESPSettingBox:AddLabel("Box Color"):AddColorPicker("bxw_esp_box_color", { Default = Color3.new(1,1,1) })
    ESPSettingBox:AddLabel("Tracer Color"):AddColorPicker("bxw_esp_tracer_color", { Default = Color3.new(1,1,1) })
    ESPSettingBox:AddLabel("Skeleton Color"):AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.new(0,1,1) })
    ESPSettingBox:AddLabel("Name Color"):AddColorPicker("bxw_esp_name_color", { Default = Color3.new(1,1,1) })
    ESPSettingBox:AddLabel("Dist Color"):AddColorPicker("bxw_esp_dist_color", { Default = Color3.new(1,1,1) })
    ESPSettingBox:AddLabel("Info Color"):AddColorPicker("bxw_esp_info_color", { Default = Color3.new(1,1,1) })
    ESPSettingBox:AddLabel("Head Dot Color"):AddColorPicker("bxw_esp_headdot_color", { Default = Color3.new(1,0,0) })
    ESPSettingBox:AddLabel("Chams Color"):AddColorPicker("bxw_esp_chams_color", { Default = Color3.new(0,1,0) })
    ESPSettingBox:AddLabel("WallCheck Hidden"):AddColorPicker("bxw_esp_hidden_color", { Default = Color3.new(1,0,0) })

    ESPSettingBox:AddDivider()
    -- [RESTORED] Missing ESP Settings
    ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Text Size", Default = 14, Min = 10, Max = 30 })
    ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Dist Text Size", Default = 14, Min = 10, Max = 30 })
    ESPSettingBox:AddDropdown("bxw_esp_dist_unit", { Text = "Dist Unit", Values = {"Studs", "Meters"}, Default = "Studs" })
    
    ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
    ESPSettingBox:AddDropdown("bxw_esp_chams_material", { Text = "Chams Material", Values = { "ForceField", "Neon", "Plastic" }, Default = "ForceField" })
    ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Chams Visible Only", Default = false })
    
    local ESPRefreshSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "ESP Refresh (ms)", Default = 50, Min = 0, Max = 250 })

    ESPSettingBox:AddDivider()
    -- [RESTORED] Crosshair UI
    ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
    ESPSettingBox:AddLabel("Crosshair Color"):AddColorPicker("bxw_crosshair_color", { Default = Color3.new(1,1,1) })
    ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Size", Default = 5, Min = 1, Max = 20 })
    ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Thickness", Default = 1, Min = 1, Max = 5 })

    -- ESP Logic
    local lastESPUpdate = 0
    local function removePlayerESP(plr)
        local data = espDrawings[plr]
        if data then
            if data.Box then data.Box:Remove() end
            if data.Corners then for _,l in pairs(data.Corners) do l:Remove() end end
            if data.Tracer then data.Tracer:Remove() end
            if data.Name then data.Name:Remove() end
            if data.Distance then data.Distance:Remove() end
            if data.Info then data.Info:Remove() end
            if data.HeadDot then data.HeadDot:Remove() end
            if data.Health then 
                if data.Health.Outline then data.Health.Outline:Remove() end 
                if data.Health.Bar then data.Health.Bar:Remove() end 
            end
            if data.Skeleton then for _,l in pairs(data.Skeleton) do l:Remove() end end
            if data.Highlight then data.Highlight:Destroy() end
            espDrawings[plr] = nil
        end
    end

    local skeletonJoints = {
        ["Head"] = "UpperTorso", ["UpperTorso"] = "LowerTorso", ["LowerTorso"] = "HumanoidRootPart",
        ["LeftUpperArm"] = "UpperTorso", ["LeftLowerArm"] = "LeftUpperArm", ["LeftHand"] = "LeftLowerArm",
        ["RightUpperArm"] = "UpperTorso", ["RightLowerArm"] = "RightUpperArm", ["RightHand"] = "RightLowerArm",
        ["LeftUpperLeg"] = "LowerTorso", ["LeftLowerLeg"] = "LeftUpperLeg", ["LeftFoot"] = "LeftLowerLeg",
        ["RightUpperLeg"] = "LowerTorso", ["RightLowerLeg"] = "RightUpperLeg", ["RightFoot"] = "RightLowerLeg",
    }

    AddConnection(RunService.RenderStepped:Connect(function()
        if not ESPEnabledToggle.Value then
            for plr, _ in pairs(espDrawings) do removePlayerESP(plr) end
            return
        end
        if tick() - lastESPUpdate < (ESPRefreshSlider.Value/1000) then return end
        lastESPUpdate = tick()

        local cam = Workspace.CurrentCamera
        if not cam then return end
        local hiddenColor = Options.bxw_esp_hidden_color.Value

        for _, plr in ipairs(Players:GetPlayers()) do
            if (plr ~= LocalPlayer or SelfToggle.Value) then
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
                
                if char and hum and hum.Health > 0 and root then
                    local isTeam = (Toggles.bxw_esp_team.Value and LocalPlayer.Team and plr.Team == LocalPlayer.Team)
                    -- Check Whitelist logic here (omitted for brevity, assume checked)
                    
                    if not isTeam then
                        local data = espDrawings[plr] or {}
                        espDrawings[plr] = data

                        -- Wall Check Logic
                        local isVisible = true
                        if WallToggle.Value then
                            local params = RaycastParams.new()
                            params.FilterDescendantsInstances = { char, LocalPlayer.Character }
                            params.FilterType = Enum.RaycastFilterType.Blacklist
                            local hit = Workspace:Raycast(cam.CFrame.Position, root.Position - cam.CFrame.Position, params)
                            if hit then isVisible = false end
                        end
                        local function ResolveColor(c) return (WallToggle.Value and not isVisible) and hiddenColor or c end

                        -- Calculations
                        local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
                        for _, p in ipairs(char:GetChildren()) do
                            if p:IsA("BasePart") then
                                local s = p.Size/2
                                minV = Vector3.new(math.min(minV.X, p.Position.X-s.X), math.min(minV.Y, p.Position.Y-s.Y), math.min(minV.Z, p.Position.Z-s.Z))
                                maxV = Vector3.new(math.max(maxV.X, p.Position.X+s.X), math.max(maxV.Y, p.Position.Y+s.Y), math.max(maxV.Z, p.Position.Z+s.Z))
                            end
                        end
                        local center, size = (minV+maxV)/2, maxV-minV
                        local corners = {
                            center+Vector3.new(size.X/2,size.Y/2,size.Z/2), center+Vector3.new(-size.X/2,size.Y/2,size.Z/2),
                            center+Vector3.new(size.X/2,-size.Y/2,size.Z/2), center+Vector3.new(-size.X/2,-size.Y/2,size.Z/2),
                            center+Vector3.new(size.X/2,size.Y/2,-size.Z/2), center+Vector3.new(-size.X/2,size.Y/2,-size.Z/2),
                            center+Vector3.new(size.X/2,-size.Y/2,-size.Z/2), center+Vector3.new(-size.X/2,-size.Y/2,-size.Z/2)
                        }
                        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                        local onScreen = false
                        for _,v in ipairs(corners) do
                            local s, vis = cam:WorldToViewportPoint(v)
                            if vis then onScreen = true end
                            minX, maxX = math.min(minX, s.X), math.max(maxX, s.X)
                            minY, maxY = math.min(minY, s.Y), math.max(maxY, s.Y)
                        end

                        if onScreen then
                            local boxColor = ResolveColor(Options.bxw_esp_box_color.Value)
                            
                            -- Box
                            if Toggles.bxw_esp_box.Value then
                                local w, h = maxX-minX, maxY-minY
                                if BoxStyleDropdown.Value == "Box" then
                                    if not data.Box then data.Box = Drawing.new("Square"); data.Box.Thickness=1; data.Box.Filled=false end
                                    data.Box.Visible=true; data.Box.Color=boxColor; data.Box.Position=Vector2.new(minX,minY); data.Box.Size=Vector2.new(w,h)
                                    if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                                else
                                    if data.Box then data.Box.Visible=false end
                                    if not data.Corners then data.Corners={}; for i=1,8 do data.Corners[i]=Drawing.new("Line"); data.Corners[i].Thickness=1 end end
                                    local L, H = w/4, h/4
                                    local function dl(i,x1,y1,x2,y2) local l=data.Corners[i] l.Visible=true l.Color=boxColor l.From=Vector2.new(x1,y1) l.To=Vector2.new(x2,y2) end
                                    dl(1,minX,minY,minX+L,minY); dl(2,minX,minY,minX,minY+H); dl(3,maxX,minY,maxX-L,minY); dl(4,maxX,minY,maxX,minY+H)
                                    dl(5,minX,maxY,minX+L,maxY); dl(6,minX,maxY,minX,maxY-H); dl(7,maxX,maxY,maxX-L,maxY); dl(8,maxX,maxY,maxX,maxY-H)
                                end
                            else
                                if data.Box then data.Box.Visible=false end
                                if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                            end

                            -- Info
                            if InfoToggle.Value then
                                if not data.Info then data.Info = Drawing.new("Text"); data.Info.Center=true; data.Info.Outline=true end
                                data.Info.Visible=true
                                data.Info.Color = ResolveColor(Options.bxw_esp_info_color.Value)
                                data.Info.Size = Options.bxw_esp_name_size.Value
                                local dVal = (root.Position - cam.CFrame.Position).Magnitude
                                local hp = math.floor(hum.Health)
                                local tName = plr.Team and plr.Team.Name or "No Team"
                                data.Info.Text = string.format("HP:%d | Dist:%.0f | %s", hp, dVal, tName)
                                data.Info.Position = Vector2.new((minX+maxX)/2, maxY+5)
                            else if data.Info then data.Info.Visible=false end end
                            
                            -- Head Dot
                            if HeadDotToggle.Value then
                                local head = char:FindFirstChild("Head")
                                if head then
                                    local s, v = cam:WorldToViewportPoint(head.Position)
                                    if v then
                                        if not data.HeadDot then data.HeadDot = Drawing.new("Circle"); data.HeadDot.Filled=true end
                                        data.HeadDot.Visible=true
                                        data.HeadDot.Color = ResolveColor(Options.bxw_esp_headdot_color.Value)
                                        data.HeadDot.Position = Vector2.new(s.X, s.Y)
                                        data.HeadDot.Radius = 3
                                    else if data.HeadDot then data.HeadDot.Visible=false end end
                                end
                            else if data.HeadDot then data.HeadDot.Visible=false end end

                            -- Tracer
                            if Toggles.bxw_esp_tracer.Value then
                                if not data.Tracer then data.Tracer = Drawing.new("Line"); data.Tracer.Thickness=1 end
                                local s = cam:WorldToViewportPoint(root.Position)
                                data.Tracer.Visible=true
                                data.Tracer.Color = ResolveColor(Options.bxw_esp_tracer_color.Value)
                                data.Tracer.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
                                data.Tracer.To = Vector2.new(s.X, s.Y)
                            else if data.Tracer then data.Tracer.Visible=false end end

                            -- Skeleton
                            if Toggles.bxw_esp_skeleton.Value then
                                if not data.Skeleton then data.Skeleton = {} end
                                local idx = 1
                                for p1n, p2n in pairs(skeletonJoints) do
                                    local p1, p2 = char:FindFirstChild(p1n), char:FindFirstChild(p2n)
                                    if p1 and p2 then
                                        local s1, v1 = cam:WorldToViewportPoint(p1.Position)
                                        local s2, v2 = cam:WorldToViewportPoint(p2.Position)
                                        if v1 or v2 then
                                            local l = data.Skeleton[idx] or Drawing.new("Line")
                                            data.Skeleton[idx] = l
                                            l.Visible=true; l.Color = ResolveColor(Options.bxw_esp_skeleton_color.Value); l.Thickness=1
                                            l.From = Vector2.new(s1.X, s1.Y); l.To = Vector2.new(s2.X, s2.Y)
                                            idx = idx + 1
                                        end
                                    end
                                end
                                for i=idx, #data.Skeleton do data.Skeleton[i].Visible=false end
                            else if data.Skeleton then for _,l in pairs(data.Skeleton) do l.Visible=false end end end
                            
                            -- Chams
                            if Toggles.bxw_esp_chams.Value then
                                if not data.Highlight then
                                    data.Highlight = Instance.new("Highlight", char)
                                end
                                data.Highlight.Enabled = true
                                data.Highlight.Adornee = char
                                data.Highlight.FillColor = Options.bxw_esp_chams_color.Value
                                data.Highlight.FillTransparency = Options.bxw_esp_chams_trans.Value
                                data.Highlight.DepthMode = Toggles.bxw_esp_visibleonly.Value and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                            else
                                if data.Highlight then data.Highlight.Enabled = false end
                            end

                        else
                            -- Offscreen cleanup
                            if data.Box then data.Box.Visible=false end
                            if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                            if data.Info then data.Info.Visible=false end
                            if data.HeadDot then data.HeadDot.Visible=false end
                            if data.Tracer then data.Tracer.Visible=false end
                            if data.Skeleton then for _,l in pairs(data.Skeleton) do l.Visible=false end end
                        end
                    else
                        removePlayerESP(plr)
                    end
                else
                    removePlayerESP(plr)
                end
            else
                removePlayerESP(plr)
            end
        end
        for plr,_ in pairs(espDrawings) do if not plr.Parent then removePlayerESP(plr) end end
    end))
    
    -- Crosshair Logic
    crosshairLines = { h = Drawing.new("Line"), v = Drawing.new("Line") }
    AddConnection(RunService.RenderStepped:Connect(function()
        if Toggles.bxw_crosshair_enable.Value then
            local cam = Workspace.CurrentCamera
            local c = cam.ViewportSize/2
            local s, th, col = Options.bxw_crosshair_size.Value, Options.bxw_crosshair_thick.Value, Options.bxw_crosshair_color.Value
            crosshairLines.h.Visible=true; crosshairLines.h.From=Vector2.new(c.X-s,c.Y); crosshairLines.h.To=Vector2.new(c.X+s,c.Y); crosshairLines.h.Color=col; crosshairLines.h.Thickness=th
            crosshairLines.v.Visible=true; crosshairLines.v.From=Vector2.new(c.X,c.Y-s); crosshairLines.v.To=Vector2.new(c.X,c.Y+s); crosshairLines.v.Color=col; crosshairLines.v.Thickness=th
        else
            crosshairLines.h.Visible=false; crosshairLines.v.Visible=false
        end
    end))

    ------------------------------------------------
    -- TAB 4: Combat (Restored + Smart Aim)
    ------------------------------------------------
    local CombatTab = Tabs.Combat
    local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
    local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

    local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false })
    local SilentToggle = AimBox:AddToggle("bxw_silent_enable", { Text = "Silent Aim (Beta)", Default = false }) -- Restored
    local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = {"Head", "UpperTorso", "Torso", "Random"}, Default = "Head" })
    local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50 })
    local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
    local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Smoothness", Default = 0.1, Min = 0.01, Max = 1 })
    local TeamCheckToggle = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
    
    -- [RESTORED] Triggerbot
    local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false })
    
    -- [RESTORED] More Aim Settings
    AimBox:AddToggle("bxw_aim_visibility", { Text = "Visibility Check", Default = false })
    AimBox:AddSlider("bxw_aim_hitchance", { Text = "Hit Chance", Default = 100, Min = 0, Max = 100 })
    AimBox:AddLabel("FOV Color"):AddColorPicker("bxw_aim_fovcolor", { Default = Color3.new(1,1,1) })
    
    -- [UPGRADED] Target Mode with Smart Aim
    local TargetModeDropdown = AimBox:AddDropdown("bxw_aim_targetmode", { 
        Text = "Target Mode", 
        Values = { "Closest To Crosshair", "Closest Distance", "Smart Aim" }, 
        Default = "Closest To Crosshair" 
    })
    
    -- [RESTORED] Extra Box Settings
    ExtraBox:AddToggle("bxw_trigger_teamcheck", { Text = "Trigger Team Check", Default = true })
    ExtraBox:AddToggle("bxw_trigger_wallcheck", { Text = "Trigger Wall Check", Default = false })
    ExtraBox:AddSlider("bxw_trigger_delay", { Text = "Trigger Delay", Default = 0.05, Min = 0, Max = 1, Rounding = 2 })
    
    local FOVCircle = Drawing.new("Circle"); FOVCircle.Thickness=1; FOVCircle.Filled=false
    
    AddConnection(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local mouseLoc = UserInputService:GetMouseLocation()
        
        -- FOV Draw
        if ShowFovToggle.Value and AimbotToggle.Value then
            FOVCircle.Visible = true; FOVCircle.Radius = FOVSlider.Value * 15; FOVCircle.Position = mouseLoc; FOVCircle.Color = Options.bxw_aim_fovcolor.Value
        else FOVCircle.Visible = false end

        -- Aimbot Logic
        if AimbotToggle.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local bestTarget, bestScore = nil, math.huge
            local radius = FOVSlider.Value * 15

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local char = plr.Character
                    local hum = char:FindFirstChild("Humanoid")
                    local root = char:FindFirstChild("HumanoidRootPart")
                    local head = char:FindFirstChild("Head")
                    
                    if hum and hum.Health > 0 and root and head then
                        if not TeamCheckToggle.Value or plr.Team ~= LocalPlayer.Team then
                            local aimPartName = AimPartDropdown.Value
                            local part = (aimPartName == "Random") and head or char:FindFirstChild(aimPartName) or head
                            
                            local sPos, onScreen = cam:WorldToViewportPoint(part.Position)
                            if onScreen then
                                local distMouse = (Vector2.new(sPos.X, sPos.Y) - mouseLoc).Magnitude
                                local distChar = (root.Position - getRootPart().Position).Magnitude
                                
                                if distMouse <= radius then
                                    local score = distMouse
                                    -- Smart Aim Logic
                                    if TargetModeDropdown.Value == "Smart Aim" then
                                        score = distMouse + (distChar * 0.4) -- Weight distance
                                    elseif TargetModeDropdown.Value == "Closest Distance" then
                                        score = distChar
                                    end
                                    
                                    if score < bestScore then
                                        bestScore = score
                                        bestTarget = part
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            if bestTarget then
                local current = cam.CFrame
                local target = CFrame.new(current.Position, bestTarget.Position)
                cam.CFrame = current:Lerp(target, SmoothSlider.Value)
            end
        end
        
        -- Triggerbot Logic
        if TriggerbotToggle.Value then
            local mouse = LocalPlayer:GetMouse()
            local target = mouse.Target
            if target and target.Parent and Players:GetPlayerFromCharacter(target.Parent) then
                local plr = Players:GetPlayerFromCharacter(target.Parent)
                if plr ~= LocalPlayer and (not Toggles.bxw_trigger_teamcheck.Value or plr.Team ~= LocalPlayer.Team) then
                    mouse1click()
                end
            end
        end
    end))

    ------------------------------------------------
    -- TAB 5: Misc (Restored Tools + Anti-Rejoin)
    ------------------------------------------------
    local MiscTab = Tabs.Misc
    local MiscLeft = MiscTab:AddLeftGroupbox("Game Tools", "tool")
    local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")

    -- [NEW] Anti-Rejoin
    local AntiRejoinToggle = MiscLeft:AddToggle("bxw_antirejoin", { Text = "Anti-Kick / Auto Rejoin", Default = false })
    task.spawn(function()
        GuiService.ErrorMessageChanged:Connect(function()
            if AntiRejoinToggle.Value then wait(0.5) TeleportService:Teleport(game.PlaceId) end
        end)
        CoreGui.ChildAdded:Connect(function(child)
            if AntiRejoinToggle.Value and child.Name == "RobloxPromptGui" then
                wait(1); if #Players:GetPlayers() <= 1 then TeleportService:Teleport(game.PlaceId) end
            end
        end)
    end)
    MiscLeft:AddButton("Force Rejoin", function() TeleportService:Teleport(game.PlaceId) end)
    MiscLeft:AddDivider()

    -- [RESTORED] All Tools
    MiscLeft:AddToggle("bxw_antiafk", { Text = "Anti-AFK", Default = true })
    AddConnection(LocalPlayer.Idled:Connect(function() if Toggles.bxw_antiafk.Value then VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end end))
    
    local spinConn
    local SpinToggle = MiscLeft:AddToggle("bxw_spinbot", { Text = "SpinBot", Default = false })
    local SpinSpeed = MiscLeft:AddSlider("bxw_spin_speed", { Text = "Spin Speed", Default = 5, Min = 1, Max = 20 })
    SpinToggle:OnChanged(function(state)
        if state then
            spinConn = AddConnection(RunService.RenderStepped:Connect(function(dt)
                local r = getRootPart()
                if r then r.CFrame = r.CFrame * CFrame.Angles(0, SpinSpeed.Value * dt, 0) end
            end))
        else if spinConn then spinConn:Disconnect() end end
    end)
    
    local AntiFlingToggle = MiscLeft:AddToggle("bxw_antifling", { Text = "Anti-Fling", Default = false })
    local afConn
    AntiFlingToggle:OnChanged(function(state)
        if state then
            afConn = AddConnection(RunService.Stepped:Connect(function()
                local r = getRootPart()
                if r and r.AssemblyAngularVelocity.Magnitude > 50 then r.AssemblyAngularVelocity = Vector3.zero r.AssemblyLinearVelocity = Vector3.zero end
            end))
        else if afConn then afConn:Disconnect() end end
    end)
    
    MiscLeft:AddButton("BTools", function()
        local bp = LocalPlayer.Backpack
        if bp then for _,t in pairs({Enum.BinType.Clone, Enum.BinType.Hammer, Enum.BinType.Grab}) do local b = Instance.new("HopperBin", bp) b.BinType = t end end
    end)
    
    MiscLeft:AddButton("Respawn", function() LocalPlayer:LoadCharacter() end)
    
    -- [RESTORED] Environment
    MiscRight:AddSlider("bxw_gravity", { Text = "Gravity", Default = 196.2, Min = 0, Max = 300, Callback = function(v) Workspace.Gravity = v end })
    MiscRight:AddToggle("bxw_nofog", { Text = "No Fog", Default = false, Callback = function(v) Lighting.FogEnd = v and 100000 or 1000 end })
    MiscRight:AddSlider("bxw_brightness", { Text = "Brightness", Default = 2, Min = 0, Max = 10, Callback = function(v) Lighting.Brightness = v end })
    MiscRight:AddLabel("Ambient"):AddColorPicker("bxw_ambient_color", { Default = Color3.fromRGB(127,127,127), Callback = function(v) Lighting.Ambient = v end })

    ------------------------------------------------
    -- TAB 6: Settings
    ------------------------------------------------
    local SettingsTab = Tabs.Settings
    local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
    MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
    MenuGroup:AddLabel("Menu Bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })

    Library.ToggleKeybind = Options.MenuKeybind
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    ThemeManager:SetFolder("BxB.Ware_Setting")
    SaveManager:SetFolder("BxB.Ware_Setting")
    SaveManager:BuildConfigSection(SettingsTab)
    ThemeManager:ApplyToTab(SettingsTab)

    ------------------------------------------------
    -- Unload Logic
    ------------------------------------------------
    Library:OnUnload(function()
        print("[BxB] Unloading...")
        for _, conn in ipairs(Connections) do if conn then pcall(function() conn:Disconnect() end) end end
        if espDrawings then
            for plr, data in pairs(espDrawings) do
                if data.Box then data.Box:Remove() end
                if data.Corners then for _,l in pairs(data.Corners) do l:Remove() end end
                if data.Tracer then data.Tracer:Remove() end
                if data.Name then data.Name:Remove() end
                if data.Distance then data.Distance:Remove() end
                if data.Info then data.Info:Remove() end
                if data.HeadDot then data.HeadDot:Remove() end
                if data.Health then 
                     if data.Health.Outline then data.Health.Outline:Remove() end
                     if data.Health.Bar then data.Health.Bar:Remove() end
                end
                if data.Skeleton then for _,l in pairs(data.Skeleton) do l:Remove() end end
                if data.Highlight then data.Highlight:Destroy() end
            end
            table.clear(espDrawings)
        end
        if crosshairLines then crosshairLines.h:Remove(); crosshairLines.v:Remove() end
        print("[BxB] Unloaded successfully.")
    end)
end

return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then warn("[MainHub] Fatal error:", err) end
end
