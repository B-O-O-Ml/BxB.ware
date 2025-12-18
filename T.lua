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
local CoreGui            = game:GetService("CoreGui")
local TeleportService    = game:GetService("TeleportService")
local GuiService         = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

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
    if not plr then return nil end
    return plr.Character
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
    if RolePriority[role] then
        return role
    end
    return "free"
end

local function RoleAtLeast(haveRole, needRole)
    local have  = NormalizeRole(haveRole)
    local need  = NormalizeRole(needRole)
    local hPrio = RolePriority[have] or 0
    local nPrio = RolePriority[need] or 999
    return hPrio >= nPrio
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

--====================================================
-- 3. Helpers
--====================================================

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

local function isPlayerWhitelisted(plrName, whitelistData)
    if not whitelistData then return false end
    if type(whitelistData) == "table" then
        if whitelistData[plrName] then return true end
        for _, v in pairs(whitelistData) do
            if v == plrName then return true end
        end
    end
    return false
end

--====================================================
-- 4. MainHub Function
--====================================================

local function MainHub(Exec, keydata, authToken)
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
        warn("[MainHub] Invalid auth token, abort")
        return
    end

    -- Global Storage for Drawings (Important for Cleanup)
    local espDrawings = {}
    local crosshairLines = nil

    -- Clean up function for Drawings
    local function cleanupESP()
        for _, data in pairs(espDrawings) do
            if data.Box then pcall(function() data.Box:Remove() end) end
            if data.Corners then for _, ln in pairs(data.Corners) do pcall(function() ln:Remove() end) end end
            if data.Health then
                if data.Health.Outline then pcall(function() data.Health.Outline:Remove() end) end
                if data.Health.Bar then pcall(function() data.Health.Bar:Remove() end) end
            end
            if data.Name then pcall(function() data.Name:Remove() end) end
            if data.Distance then pcall(function() data.Distance:Remove() end) end
            if data.Tracer then pcall(function() data.Tracer:Remove() end) end
            if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
            if data.Skeleton then for _, ln in pairs(data.Skeleton) do pcall(function() ln:Remove() end) end end
            if data.HeadDot then pcall(function() data.HeadDot:Remove() end) end
            if data.Info then pcall(function() data.Info:Remove() end) end
        end
        table.clear(espDrawings)
    end

    keydata.role = NormalizeRole(keydata.role)

    -- Library Load
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
    -- TAB 1: Info
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

    -- Fetch Remote Key Data
    local HttpService = game:GetService("HttpService")
    local remoteKeyData, remoteCreatedAtStr, remoteExpireStr = nil, nil, nil
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
        if remoteKeyData.role then roleHtml = GetRoleLabel(remoteKeyData.role) end
        if remoteKeyData.status then statusText = tostring(remoteKeyData.status) end
        if remoteKeyData.note and remoteKeyData.note ~= "" then noteText = tostring(remoteKeyData.note) end
        if remoteKeyData.hwid_hash then keydata.hwid_hash = remoteKeyData.hwid_hash end
        if remoteKeyData.timestamp then remoteCreatedAtStr = tostring(remoteKeyData.timestamp) end
        if remoteKeyData.expire then remoteExpireStr = remoteKeyData.expire end
    end

    local createdAtText = remoteCreatedAtStr or (keydata.timestamp and keydata.timestamp > 0 and formatUnixTime(keydata.timestamp)) or tostring(keydata.created_at) or "Unknown"
    local expireTs = tonumber(keydata.expire) or 0
    if remoteExpireStr and tonumber(remoteExpireStr) then expireTs = tonumber(remoteExpireStr) end

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))
    safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    safeRichLabel(KeyBox, string.format("<b>Tier:</b> %s", string.upper(keydata.role or "free")))
    safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", noteText))
    safeRichLabel(KeyBox, string.format("<b>Created at:</b> %s", createdAtText))

    local expireDisplay = (expireTs > 0 and formatUnixTime(expireTs)) or (remoteExpireStr and not tonumber(remoteExpireStr) and tostring(remoteExpireStr)) or "Lifetime"
    local timeLeftDisplay = (expireTs > 0 and formatTimeLeft(expireTs)) or (remoteExpireStr and not tonumber(remoteExpireStr) and tostring(remoteExpireStr)) or "Lifetime"

    local ExpireLabel = safeRichLabel(KeyBox, string.format("<b>Expire:</b> %s", expireDisplay))
    local TimeLeftLabel = safeRichLabel(KeyBox, string.format("<b>Time left:</b> %s", timeLeftDisplay))

    AddConnection(RunService.Heartbeat:Connect(function(dt)
        if expireTs > 0 then
            if ExpireLabel.TextLabel then ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", formatUnixTime(expireTs)) end
            if TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", formatTimeLeft(expireTs)) end
        end
    end))

    KeyBox:AddDivider()
    KeyBox:AddButton("Copy Key Info", function()
        local infoText = string.format("Key: %s\nRole: %s\nStatus: %s\nCreated at: %s\nExpire: %s\nHWID: %s", rawKey, keydata.role, statusText, createdAtText, expireDisplay, tostring(keydata.hwid_hash))
        pcall(function() setclipboard(infoText); Library:Notify("Key info copied", 2) end)
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
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
        if ok and info and info.Name then GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", info.Name) end
    end)

    local function updatePlayersLabel()
        PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d / %s", #Players:GetPlayers(), tostring(Players.MaxPlayers))
    end
    updatePlayersLabel()
    AddConnection(Players.PlayerAdded:Connect(updatePlayersLabel))
    AddConnection(Players.PlayerRemoving:Connect(updatePlayersLabel))

    local fpsAcc = 0
    AddConnection(RunService.Heartbeat:Connect(function(dt)
        fpsAcc = fpsAcc + dt
        if fpsAcc < 0.25 then return end
        fpsAcc = 0
        local fps = math.floor(1 / math.max(dt, 1/240))
        local ping = 0
        pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
        PerfLabel.TextLabel.Text = string.format("<b>Perf:</b> FPS: %d | Ping: %d ms", fps, ping)
        ServerTimeLabel.TextLabel.Text = string.format("<b>Server Time:</b> %s", os.date("%H:%M:%S"))
    end))

    ------------------------------------------------
    -- TAB 2: Player
    ------------------------------------------------
    local PlayerTab = Tabs.Player
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    local walkSpeedEnabled = false
    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = 16, Min = 0, Max = 120, Rounding = 0 })

    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state
        if WalkSpeedSlider.SetDisabled then WalkSpeedSlider:SetDisabled(not state) end
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = state and WalkSpeedSlider.Value or 16 end
    end)
    MoveBox:AddButton("Reset WalkSpeed", function()
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = 16 end
        WalkSpeedSlider:SetValue(16)
        WalkSpeedToggle:SetValue(false)
    end)

    local jumpPowerEnabled = false
    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = 50, Min = 0, Max = 200, Rounding = 0 })

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        if JumpPowerSlider.SetDisabled then JumpPowerSlider:SetDisabled(not state) end
        local hum = getHumanoid()
        if hum then hum.UseJumpPower = true; hum.JumpPower = state and JumpPowerSlider.Value or 50 end
    end)
    MoveBox:AddButton("Reset JumpPower", function()
        local hum = getHumanoid()
        if hum then hum.UseJumpPower = true; hum.JumpPower = 50 end
        JumpPowerSlider:SetValue(50)
        JumpPowerToggle:SetValue(false)
    end)

    -- Movement Presets
    MoveBox:AddDivider()
    local MovePresetDropdown = MoveBox:AddDropdown("bxw_move_preset", { Text = "Movement Preset", Values = { "Default", "Normal", "Fast", "Ultra" }, Default = "Default" })
    MovePresetDropdown:OnChanged(function(value)
        if value == "Default" then WalkSpeedSlider:SetValue(16); JumpPowerSlider:SetValue(50); WalkSpeedToggle:SetValue(false); JumpPowerToggle:SetValue(false)
        elseif value == "Normal" then WalkSpeedSlider:SetValue(20); JumpPowerSlider:SetValue(60); WalkSpeedToggle:SetValue(true); JumpPowerToggle:SetValue(true)
        elseif value == "Fast" then WalkSpeedSlider:SetValue(30); JumpPowerSlider:SetValue(80); WalkSpeedToggle:SetValue(true); JumpPowerToggle:SetValue(true)
        elseif value == "Ultra" then WalkSpeedSlider:SetValue(50); JumpPowerSlider:SetValue(100); WalkSpeedToggle:SetValue(true); JumpPowerToggle:SetValue(true) end
    end)

    -- Inf Jump
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
            if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
        end
    end)

    -- Fly
    local flyConn, flyBV, flyBG
    local flyEnabled, flySpeed = false, 60
    local FlyToggle = MoveBox:AddToggle("bxw_fly", { Text = "Fly (Smooth) <font color='#FF0000'>[RISKY]</font>", Default = false, Tooltip = "Risky Feature" })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = 60, Min = 1, Max = 300, Rounding = 0 })

    FlySpeedSlider:OnChanged(function(v) flySpeed = v end)
    FlyToggle:OnChanged(function(state)
        flyEnabled = state
        local root, hum, cam = getRootPart(), getHumanoid(), Workspace.CurrentCamera
        if not state then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
            if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
            if hum then hum.PlatformStand = false end
            return
        end
        if not (root and hum and cam) then FlyToggle:SetValue(false); return end

        hum.PlatformStand = true
        flyBV = Instance.new("BodyVelocity", root); flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5); flyBV.Velocity = Vector3.zero
        flyBG = Instance.new("BodyGyro", root); flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9); flyBG.CFrame = root.CFrame

        flyConn = AddConnection(RunService.RenderStepped:Connect(function()
            if not flyEnabled or not root or not hum or not flyBV or not flyBG or not flyBV.Parent then return end
            local moveDir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            if moveDir.Magnitude > 0 then flyBV.Velocity = moveDir.Unit * flySpeed else flyBV.Velocity = Vector3.zero end
            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
    end)

    -- Noclip (Role Limited)
    local noclipConn
    local NoclipToggle = MoveBox:AddToggle("bxw_noclip", { Text = "Noclip <font color='#FF0000'>[RISKY]</font>", Default = false })
    -- Role Check for Noclip
    if not RoleAtLeast(keydata.role, "user") then -- Example: Locked for free users (if needed) or just display warning
        -- NoclipToggle:SetDisabled(true) -- Uncomment if you want to lock it
    end

    NoclipToggle:OnChanged(function(state)
        if not state then
            if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
            local char = getCharacter()
            if char then for _, p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = true end end end
        else
            if noclipConn then noclipConn:Disconnect() end
            noclipConn = AddConnection(RunService.Stepped:Connect(function()
                local char = getCharacter()
                if char then for _, p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end
            end))
        end
    end)

    -- Util Box
    local UtilBox = safeAddRightGroupbox(PlayerTab, "Teleport / Utility", "map")
    local playerNames = {}
    local function refreshPlayerList()
        table.clear(playerNames)
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(playerNames, p.Name) end end
    end
    refreshPlayerList()

    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = playerNames, Default = "", AllowNull = true })
    UtilBox:AddButton("Refresh Player List", function() refreshPlayerList(); TeleportDropdown:SetValues(playerNames) end)
    UtilBox:AddButton("Teleport", function()
        local tName = TeleportDropdown.Value
        if not tName or tName == "" then return end
        local target = Players:FindFirstChild(tName)
        local root = getRootPart()
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and root then
            root.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(0, 3, 0)
        end
    end)

    UtilBox:AddDivider()
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = playerNames, Default = "", AllowNull = true })
    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", { Text = "Spectate Player", Default = false })
    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if state then
            local t = Players:FindFirstChild(SpectateDropdown.Value)
            if t and t.Character and t.Character:FindFirstChild("Humanoid") then
                cam.CameraSubject = t.Character.Humanoid
            end
        else
            local hum = getHumanoid()
            if hum then cam.CameraSubject = hum end
        end
    end)

    -- Waypoints
    UtilBox:AddDivider()
    UtilBox:AddLabel("Waypoints")
    local savedWaypoints = {}
    local savedNames = {}
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", AllowNull = true })
    UtilBox:AddButton("Set Waypoint", function()
        local root = getRootPart()
        if not root then return end
        local name = "WP" .. (#savedNames + 1)
        savedWaypoints[name] = root.CFrame
        table.insert(savedNames, name)
        WaypointDropdown:SetValues(savedNames)
        Library:Notify("Saved " .. name, 2)
    end)
    UtilBox:AddButton("Teleport to Waypoint", function()
        local cf = savedWaypoints[WaypointDropdown.Value]
        local root = getRootPart()
        if cf and root then root.CFrame = cf + Vector3.new(0, 3, 0) end
    end)

    -- Camera
    local CamBox = safeAddRightGroupbox(PlayerTab, "Camera & World", "sun")
    local CamFOVSlider = CamBox:AddSlider("bxw_cam_fov", { Text = "Camera FOV", Default = 70, Min = 40, Max = 120, Rounding = 0 })
    CamFOVSlider:OnChanged(function(v) if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = v end end)
    local MaxZoomSlider = CamBox:AddSlider("bxw_cam_maxzoom", { Text = "Max Zoom", Default = 400, Min = 10, Max = 1000, Rounding = 0 })
    MaxZoomSlider:OnChanged(function(v) LocalPlayer.CameraMaxZoomDistance = v end)
    local SkyboxThemes = { ["Default"] = "", ["Space"] = "rbxassetid://11755937810", ["Sunset"] = "rbxassetid://9393701400", ["Midnight"] = "rbxassetid://11755930464" }
    local SkyboxDropdown = CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default" })
    SkyboxDropdown:OnChanged(function(v)
        local l = game:GetService("Lighting")
        local s = l:FindFirstChildOfClass("Sky")
        if s then s:Destroy() end
        if SkyboxThemes[v] ~= "" then
            local n = Instance.new("Sky", l)
            n.SkyboxBk, n.SkyboxDn, n.SkyboxFt, n.SkyboxLf, n.SkyboxRt, n.SkyboxUp = SkyboxThemes[v], SkyboxThemes[v], SkyboxThemes[v], SkyboxThemes[v], SkyboxThemes[v], SkyboxThemes[v]
        end
    end)

    ------------------------------------------------
    -- TAB 3: ESP
    ------------------------------------------------
    local ESPTab = Tabs.ESP
    local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
    local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")

    local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP", Default = false })
    local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box" })
    
    local BoxToggle    = ESPFeatureBox:AddToggle("bxw_esp_box", { Text = "Box", Default = true })
    local ChamsToggle  = ESPFeatureBox:AddToggle("bxw_esp_chams", { Text = "Chams", Default = false })
    local SkeletonToggle = ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton", Default = false })
    local HealthToggle = ESPFeatureBox:AddToggle("bxw_esp_health", { Text = "Health Bar", Default = false })
    local NameToggle   = ESPFeatureBox:AddToggle("bxw_esp_name", { Text = "Name Tag", Default = true })
    local DistToggle   = ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance", Default = false })
    local TracerToggle = ESPFeatureBox:AddToggle("bxw_esp_tracer", { Text = "Tracer", Default = false })
    local HeadDotToggle = ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false })
    
    local TeamToggle   = ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true })
    local WallToggle   = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false, Tooltip = "Changes color if obstructed" })
    local SelfToggle   = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false })
    local InfoToggle   = ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info", Default = false, Tooltip = "Show HP, Dist, Team" })

    -- Whitelist
    local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = {}, Default = "", Multi = true })
    local function refreshWhitelist()
        local n = {}
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(n, p.Name) end end
        table.sort(n)
        WhitelistDropdown:SetValues(n)
    end
    refreshWhitelist()
    AddConnection(Players.PlayerAdded:Connect(refreshWhitelist))
    AddConnection(Players.PlayerRemoving:Connect(refreshWhitelist))

    -- ESP Settings
    local BoxColorLabel = ESPSettingBox:AddLabel("Box Color"); BoxColorLabel:AddColorPicker("bxw_esp_box_color", { Default = Color3.fromRGB(255, 255, 255) })
    local NameColorLabel = ESPSettingBox:AddLabel("Name Color"); NameColorLabel:AddColorPicker("bxw_esp_name_color", { Default = Color3.fromRGB(255, 255, 255) })
    local TracerColorLabel = ESPSettingBox:AddLabel("Tracer Color"); TracerColorLabel:AddColorPicker("bxw_esp_tracer_color", { Default = Color3.fromRGB(255, 255, 255) })
    local SkeletonColorLabel = ESPSettingBox:AddLabel("Skeleton Color"); SkeletonColorLabel:AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.fromRGB(0, 255, 255) })
    local HealthColorLabel = ESPSettingBox:AddLabel("Health Color"); HealthColorLabel:AddColorPicker("bxw_esp_health_color", { Default = Color3.fromRGB(0, 255, 0) })
    local HeadDotColorLabel = ESPSettingBox:AddLabel("Head Dot Color"); HeadDotColorLabel:AddColorPicker("bxw_esp_headdot_color", { Default = Color3.fromRGB(255, 0, 0) })
    local ChamsColorLabel = ESPSettingBox:AddLabel("Chams Color"); ChamsColorLabel:AddColorPicker("bxw_esp_chams_color", { Default = Color3.fromRGB(0, 255, 0) })
    
    local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
    local DistUnitDropdown = ESPSettingBox:AddDropdown("bxw_esp_dist_unit", { Text = "Distance Unit", Values = { "Studs", "Meters" }, Default = "Studs" })
    local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
    local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Chams Visible Only", Default = false })
    local ESPRefreshSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "ESP Refresh (ms)", Default = 20, Min = 0, Max = 200, Rounding = 0 })

    local CrosshairToggle = ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
    local CrossColorLabel = ESPSettingBox:AddLabel("Crosshair Color"); CrossColorLabel:AddColorPicker("bxw_crosshair_color", { Default = Color3.fromRGB(255, 255, 255) })
    local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20, Rounding = 0 })

    -- ESP Variables
    local lastESPUpdate = 0
    local skeletonJoints = {
        ["Head"] = "UpperTorso", ["UpperTorso"] = "LowerTorso", ["LowerTorso"] = "HumanoidRootPart",
        ["LeftUpperArm"] = "UpperTorso", ["LeftLowerArm"] = "LeftUpperArm", ["LeftHand"] = "LeftLowerArm",
        ["RightUpperArm"] = "UpperTorso", ["RightLowerArm"] = "RightUpperArm", ["RightHand"] = "RightLowerArm",
        ["LeftUpperLeg"] = "LowerTorso", ["LeftLowerLeg"] = "LeftUpperLeg", ["LeftFoot"] = "LeftLowerLeg",
        ["RightUpperLeg"] = "LowerTorso", ["RightLowerLeg"] = "RightUpperLeg", ["RightFoot"] = "RightLowerLeg",
    }

    local function removePlayerESP(plr)
        local data = espDrawings[plr]
        if data then
            if data.Box then pcall(function() data.Box:Remove() end) end
            if data.Corners then for _, ln in pairs(data.Corners) do pcall(function() ln:Remove() end) end end
            if data.Health then pcall(function() data.Health.Outline:Remove(); data.Health.Bar:Remove() end) end
            if data.Name then pcall(function() data.Name:Remove() end) end
            if data.Distance then pcall(function() data.Distance:Remove() end) end
            if data.Tracer then pcall(function() data.Tracer:Remove() end) end
            if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
            if data.Skeleton then for _, ln in pairs(data.Skeleton) do pcall(function() ln:Remove() end) end end
            if data.HeadDot then pcall(function() data.HeadDot:Remove() end) end
            if data.Info then pcall(function() data.Info:Remove() end) end
            espDrawings[plr] = nil
        end
    end
    AddConnection(Players.PlayerRemoving:Connect(removePlayerESP))

    local function updateESP()
        -- Refresh rate check
        if tick() - lastESPUpdate < (ESPRefreshSlider.Value / 1000) then return end
        lastESPUpdate = tick()

        if not ESPEnabledToggle.Value then
            for _, d in pairs(espDrawings) do
                if d.Box then d.Box.Visible = false end
                if d.Corners then for _, l in pairs(d.Corners) do l.Visible = false end end
                if d.Health then d.Health.Outline.Visible = false; d.Health.Bar.Visible = false end
                if d.Name then d.Name.Visible = false end
                if d.Distance then d.Distance.Visible = false end
                if d.Tracer then d.Tracer.Visible = false end
                if d.Highlight then d.Highlight.Enabled = false end
                if d.Skeleton then for _, l in pairs(d.Skeleton) do l.Visible = false end end
                if d.HeadDot then d.HeadDot.Visible = false end
                if d.Info then d.Info.Visible = false end
            end
            return
        end

        local cam = Workspace.CurrentCamera
        local camPos = cam.CFrame.Position

        for _, plr in ipairs(Players:GetPlayers()) do
            local shouldDraw = false
            local mainColor = Color3.fromRGB(255, 255, 255) -- Default

            if (plr ~= LocalPlayer or SelfToggle.Value) then
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))

                if char and hum and hum.Health > 0 and root then
                    local isTeammate = (TeamToggle.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team)
                    local isWhitelisted = isPlayerWhitelisted(plr.Name, WhitelistDropdown.Value)

                    if not isTeammate and not isWhitelisted then
                        shouldDraw = true
                        
                        -- [Logic: Wall Check & Color]
                        local isVisible = true
                        if WallToggle.Value then
                            local rp = RaycastParams.new()
                            rp.FilterDescendantsInstances = { char, LocalPlayer.Character }
                            rp.FilterType = Enum.RaycastFilterType.Blacklist
                            local hit = Workspace:Raycast(camPos, root.Position - camPos, rp)
                            if hit then isVisible = false end
                        end

                        if isVisible then
                            -- Use user configured color if visible
                            mainColor = Options.bxw_esp_box_color.Value
                        else
                            -- Use Red if obstructed
                            mainColor = Color3.fromRGB(255, 0, 0)
                        end

                        -- Ensure Data Exists
                        local data = espDrawings[plr]
                        if not data then data = {}; espDrawings[plr] = data end

                        -- 1. Highlight
                        if ChamsToggle.Value then
                            if not data.Highlight then data.Highlight = Instance.new("Highlight", char) end
                            data.Highlight.Parent = char; data.Highlight.Adornee = char
                            data.Highlight.Enabled = true
                            data.Highlight.FillColor = mainColor
                            data.Highlight.OutlineColor = mainColor
                            data.Highlight.FillTransparency = ChamsTransSlider.Value
                            data.Highlight.DepthMode = ChamsVisibleToggle.Value and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                        else
                            if data and data.Highlight then data.Highlight.Enabled = false end
                        end

                        -- Calculate Box
                        local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
                        for _, p in ipairs(char:GetChildren()) do
                            if p:IsA("BasePart") then
                                local sz = p.Size * 0.5
                                minV = Vector3.new(math.min(minV.X, p.Position.X - sz.X), math.min(minV.Y, p.Position.Y - sz.Y), math.min(minV.Z, p.Position.Z - sz.Z))
                                maxV = Vector3.new(math.max(maxV.X, p.Position.X + sz.X), math.max(maxV.Y, p.Position.Y + sz.Y), math.max(maxV.Z, p.Position.Z + sz.Z))
                            end
                        end
                        local size = maxV - minV
                        local center = (maxV + minV) / 2
                        local corners = {
                            center + Vector3.new(size.X/2, size.Y/2, size.Z/2), center + Vector3.new(-size.X/2, size.Y/2, size.Z/2),
                            center + Vector3.new(size.X/2, -size.Y/2, size.Z/2), center + Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
                            center + Vector3.new(size.X/2, size.Y/2, -size.Z/2), center + Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
                            center + Vector3.new(size.X/2, -size.Y/2, -size.Z/2), center + Vector3.new(-size.X/2, -size.Y/2, -size.Z/2)
                        }
                        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                        local onScreen = false
                        for _, c in ipairs(corners) do
                            local s, v = cam:WorldToViewportPoint(c)
                            if v then onScreen = true end
                            minX = math.min(minX, s.X); maxX = math.max(maxX, s.X)
                            minY = math.min(minY, s.Y); maxY = math.max(maxY, s.Y)
                        end

                        if onScreen then
                            local boxW, boxH = maxX - minX, maxY - minY
                            
                            -- 2. Box
                            if BoxToggle.Value then
                                if BoxStyleDropdown.Value == "Box" then
                                    if not data.Box then data.Box = Drawing.new("Square"); data.Box.Thickness = 1; data.Box.Filled = false end
                                    data.Box.Visible = true; data.Box.Color = mainColor
                                    data.Box.Position = Vector2.new(minX, minY); data.Box.Size = Vector2.new(boxW, boxH)
                                    if data.Corners then for _, l in pairs(data.Corners) do l.Visible = false end end
                                else
                                    if not data.Corners then data.Corners = {}; for i=1,8 do data.Corners[i] = Drawing.new("Line"); data.Corners[i].Thickness = 1 end end
                                    if data.Box then data.Box.Visible = false end
                                    local cw, ch = boxW * 0.25, boxH * 0.25
                                    local l = data.Corners
                                    local function dL(i, x1, y1, x2, y2) l[i].Visible = true; l[i].Color = mainColor; l[i].From = Vector2.new(x1, y1); l[i].To = Vector2.new(x2, y2) end
                                    dL(1, minX, minY, minX+cw, minY); dL(2, minX, minY, minX, minY+ch)
                                    dL(3, maxX, minY, maxX-cw, minY); dL(4, maxX, minY, maxX, minY+ch)
                                    dL(5, minX, maxY, minX+cw, maxY); dL(6, minX, maxY, minX, maxY-ch)
                                    dL(7, maxX, maxY, maxX-cw, maxY); dL(8, maxX, maxY, maxX, maxY-ch)
                                end
                            else
                                if data.Box then data.Box.Visible = false end
                                if data.Corners then for _, l in pairs(data.Corners) do l.Visible = false end end
                            end

                            -- 3. Health
                            if HealthToggle.Value then
                                if not data.Health then data.Health = { Outline = Drawing.new("Line"), Bar = Drawing.new("Line") }
                                    data.Health.Outline.Thickness = 3; data.Health.Bar.Thickness = 1
                                end
                                local hpRatio = hum.Health / hum.MaxHealth
                                local barH = boxH * hpRatio
                                data.Health.Outline.Visible = true; data.Health.Outline.Color = Color3.new(0,0,0)
                                data.Health.Outline.From = Vector2.new(minX - 5, minY); data.Health.Outline.To = Vector2.new(minX - 5, maxY)
                                data.Health.Bar.Visible = true; data.Health.Bar.Color = Options.bxw_esp_health_color.Value
                                data.Health.Bar.From = Vector2.new(minX - 5, maxY); data.Health.Bar.To = Vector2.new(minX - 5, maxY - barH)
                            else
                                if data.Health then data.Health.Outline.Visible = false; data.Health.Bar.Visible = false end
                            end

                            -- 4. Name
                            if NameToggle.Value then
                                if not data.Name then data.Name = Drawing.new("Text"); data.Name.Center = true; data.Name.Outline = true end
                                data.Name.Visible = true; data.Name.Text = plr.DisplayName
                                data.Name.Size = NameSizeSlider.Value; data.Name.Color = WallToggle.Value and mainColor or Options.bxw_esp_name_color.Value
                                data.Name.Position = Vector2.new((minX+maxX)/2, minY - 18)
                            else
                                if data.Name then data.Name.Visible = false end
                            end

                            -- 5. Distance
                            if DistToggle.Value then
                                if not data.Distance then data.Distance = Drawing.new("Text"); data.Distance.Center = true; data.Distance.Outline = true end
                                local d = (root.Position - camPos).Magnitude
                                local suffix = "st"
                                if DistUnitDropdown.Value == "Meters" then d = d * 0.28; suffix = "m" end
                                data.Distance.Visible = true; data.Distance.Text = string.format("%.0f %s", d, suffix)
                                data.Distance.Size = 14; data.Distance.Color = WallToggle.Value and mainColor or Color3.fromRGB(255, 255, 255)
                                data.Distance.Position = Vector2.new((minX+maxX)/2, maxY + 2)
                            else
                                if data.Distance then data.Distance.Visible = false end
                            end

                            -- 6. Info (New: HP, Dist, Team)
                            if InfoToggle.Value then
                                if not data.Info then data.Info = Drawing.new("Text"); data.Info.Center = true; data.Info.Outline = true end
                                local d = (root.Position - camPos).Magnitude
                                local tName = (plr.Team and plr.Team.Name or "None")
                                data.Info.Visible = true
                                data.Info.Text = string.format("HP: %d | Dist: %d | Team: %s", math.floor(hum.Health), math.floor(d), tName)
                                data.Info.Size = 13; data.Info.Color = WallToggle.Value and mainColor or Options.bxw_esp_info_color.Value
                                data.Info.Position = Vector2.new((minX+maxX)/2, maxY + 16)
                            else
                                if data.Info then data.Info.Visible = false end
                            end

                            -- 7. Tracer
                            if TracerToggle.Value then
                                if not data.Tracer then data.Tracer = Drawing.new("Line"); data.Tracer.Thickness = 1 end
                                local rS = cam:WorldToViewportPoint(root.Position)
                                data.Tracer.Visible = true; data.Tracer.Color = WallToggle.Value and mainColor or Options.bxw_esp_tracer_color.Value
                                data.Tracer.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
                                data.Tracer.To = Vector2.new(rS.X, rS.Y)
                            else
                                if data.Tracer then data.Tracer.Visible = false end
                            end

                            -- 8. Skeleton
                            if SkeletonToggle.Value then
                                if not data.Skeleton then data.Skeleton = {} end
                                local idx = 1
                                for p1, p2 in pairs(skeletonJoints) do
                                    local pp1, pp2 = char:FindFirstChild(p1), char:FindFirstChild(p2)
                                    local ln = data.Skeleton[idx]
                                    if not ln then ln = Drawing.new("Line"); ln.Thickness = 1; data.Skeleton[idx] = ln end
                                    if pp1 and pp2 then
                                        local s1, v1 = cam:WorldToViewportPoint(pp1.Position)
                                        local s2, v2 = cam:WorldToViewportPoint(pp2.Position)
                                        if v1 or v2 then
                                            ln.Visible = true; ln.Color = WallToggle.Value and mainColor or Options.bxw_esp_skeleton_color.Value
                                            ln.From = Vector2.new(s1.X, s1.Y); ln.To = Vector2.new(s2.X, s2.Y)
                                        else ln.Visible = false end
                                    else ln.Visible = false end
                                    idx = idx + 1
                                end
                            else
                                if data.Skeleton then for _, l in pairs(data.Skeleton) do l.Visible = false end end
                            end

                            -- 9. Head Dot
                            if HeadDotToggle.Value then
                                local head = char:FindFirstChild("Head")
                                if head then
                                    local hs, hv = cam:WorldToViewportPoint(head.Position)
                                    if hv then
                                        if not data.HeadDot then data.HeadDot = Drawing.new("Circle"); data.HeadDot.Filled = true end
                                        data.HeadDot.Visible = true; data.HeadDot.Radius = 3
                                        data.HeadDot.Color = WallToggle.Value and mainColor or Options.bxw_esp_headdot_color.Value
                                        data.HeadDot.Position = Vector2.new(hs.X, hs.Y)
                                    else
                                        if data.HeadDot then data.HeadDot.Visible = false end
                                    end
                                end
                            else
                                if data.HeadDot then data.HeadDot.Visible = false end
                            end

                        else -- Offscreen
                            if data.Box then data.Box.Visible = false end
                            if data.Corners then for _, l in pairs(data.Corners) do l.Visible = false end end
                            if data.Health then data.Health.Outline.Visible = false; data.Health.Bar.Visible = false end
                            if data.Name then data.Name.Visible = false end
                            if data.Distance then data.Distance.Visible = false end
                            if data.Tracer then data.Tracer.Visible = false end
                            if data.Skeleton then for _, l in pairs(d.Skeleton) do l.Visible = false end end
                            if data.HeadDot then data.HeadDot.Visible = false end
                            if data.Info then data.Info.Visible = false end
                        end
                    end
                end
            end

            -- Cleanup if logic says shouldn't draw
            if not shouldDraw and espDrawings[plr] then
                local d = espDrawings[plr]
                if d.Box then d.Box.Visible = false end
                if d.Corners then for _, l in pairs(d.Corners) do l.Visible = false end end
                if d.Health then d.Health.Outline.Visible = false; d.Health.Bar.Visible = false end
                if d.Name then d.Name.Visible = false end
                if d.Distance then d.Distance.Visible = false end
                if d.Tracer then d.Tracer.Visible = false end
                if d.Highlight then d.Highlight.Enabled = false end
                if d.Skeleton then for _, l in pairs(d.Skeleton) do l.Visible = false end end
                if d.HeadDot then d.HeadDot.Visible = false end
                if d.Info then d.Info.Visible = false end
            end
        end
    end
    AddConnection(RunService.RenderStepped:Connect(updateESP))

    crosshairLines = { h = Drawing.new("Line"), v = Drawing.new("Line") }
    crosshairLines.h.Visible = false; crosshairLines.v.Visible = false
    AddConnection(RunService.RenderStepped:Connect(function()
        if CrosshairToggle.Value then
            local cam = Workspace.CurrentCamera
            local c = CrossColorLabel.Value or Color3.new(1,1,1)
            local cx, cy = cam.ViewportSize.X/2, cam.ViewportSize.Y/2
            local s, t = CrossSizeSlider.Value, 1
            crosshairLines.h.Visible = true; crosshairLines.h.Color = c; crosshairLines.h.Thickness = t
            crosshairLines.h.From = Vector2.new(cx-s, cy); crosshairLines.h.To = Vector2.new(cx+s, cy)
            crosshairLines.v.Visible = true; crosshairLines.v.Color = c; crosshairLines.v.Thickness = t
            crosshairLines.v.From = Vector2.new(cx, cy-s); crosshairLines.v.To = Vector2.new(cx, cy+s)
        else
            crosshairLines.h.Visible = false; crosshairLines.v.Visible = false
        end
    end))

    ------------------------------------------------
    -- TAB 4: Combat
    ------------------------------------------------
    local CombatTab = Tabs.Combat
    local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
    local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

    local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false })
    local SilentToggle = AimBox:AddToggle("bxw_silent_enable", { Text = "Silent Aim <font color='#FF0000'>[RISKY]</font>", Default = false })
    
    local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "Closest" }, Default = "Head" })
    local TargetModeDropdown = AimBox:AddDropdown("bxw_aim_targetmode", { Text = "Target Mode", Values = { "Closest To Crosshair", "Closest Distance", "Smart Aim" }, Default = "Closest To Crosshair", Tooltip = "Smart Aim combines distance to mouse and character" })

    local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
    local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
    local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Smoothness", Default = 0.1, Min = 0.01, Max = 1, Rounding = 2 })
    
    local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
    local VisibilityToggle = AimBox:AddToggle("bxw_aim_visibility", { Text = "Visibility Check", Default = false })
    local WallCheckToggle = AimBox:AddToggle("bxw_aim_wall", { Text = "Wall Check", Default = false })
    
    local FOVColorPicker = AimBox:AddLabel("FOV Color"):AddColorPicker("bxw_aim_fovcolor", { Default = Color3.fromRGB(255, 255, 255) })
    
    local AimbotFOVCircle = Drawing.new("Circle"); AimbotFOVCircle.Thickness = 1; AimbotFOVCircle.Filled = false
    
    AddConnection(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        
        AimbotFOVCircle.Visible = ShowFovToggle.Value and AimbotToggle.Value
        AimbotFOVCircle.Radius = FOVSlider.Value * 10
        AimbotFOVCircle.Position = mousePos
        AimbotFOVCircle.Color = FOVColorPicker.Value

        if AimbotToggle.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local bestTarget = nil
            local bestScore = math.huge
            local fovRad = FOVSlider.Value * 10

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local hum = plr.Character:FindFirstChild("Humanoid")
                    local root = plr.Character:FindFirstChild("HumanoidRootPart")
                    local head = plr.Character:FindFirstChild("Head")
                    local myRoot = getRootPart()
                    
                    local isTeammate = (AimTeamCheck.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team)

                    if hum and hum.Health > 0 and root and myRoot and not isTeammate then
                        local part = (AimPartDropdown.Value == "Closest") and root or (plr.Character:FindFirstChild(AimPartDropdown.Value) or root)
                        local sPos, onScreen = cam:WorldToViewportPoint(part.Position)
                        
                        if onScreen then
                            local distMouse = (Vector2.new(sPos.X, sPos.Y) - mousePos).Magnitude
                            
                            if distMouse <= fovRad then
                                local isVisible = true
                                if VisibilityToggle.Value or WallCheckToggle.Value then
                                    local rp = RaycastParams.new(); rp.FilterDescendantsInstances = { plr.Character, LocalPlayer.Character }; rp.FilterType = Enum.RaycastFilterType.Blacklist
                                    if Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, rp) then isVisible = false end
                                end

                                if isVisible then
                                    local score = distMouse
                                    local mode = TargetModeDropdown.Value
                                    
                                    if mode == "Closest Distance" then
                                        score = (root.Position - myRoot.Position).Magnitude
                                    elseif mode == "Smart Aim" then
                                        -- Logic: Combine Mouse Dist and World Dist
                                        local distWorld = (root.Position - myRoot.Position).Magnitude
                                        score = distMouse + (distWorld * 0.5) -- Weight World Distance less than Mouse Distance
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
                local currentCF = cam.CFrame
                local targetCF = CFrame.new(currentCF.Position, bestTarget.Position)
                cam.CFrame = currentCF:Lerp(targetCF, SmoothSlider.Value)
            end
        end
    end))

    ------------------------------------------------
    -- TAB 5: Misc
    ------------------------------------------------
    local MiscTab = Tabs.Misc
    local MiscLeft = MiscTab:AddLeftGroupbox("Game Tools", "tool")
    local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")

    local AntiAfkToggle = MiscLeft:AddToggle("bxw_anti_afk", { Text = "Anti-AFK", Default = true })
    local afkConn
    AntiAfkToggle:OnChanged(function(state)
        if state then
            afkConn = AddConnection(LocalPlayer.Idled:Connect(function()
                VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new())
            end))
        else
            if afkConn then afkConn:Disconnect(); afkConn = nil end
        end
    end)

    -- [Anti-Rejoin Feature]
    local AntiRejoinToggle = MiscLeft:AddToggle("bxw_antirejoin", { Text = "Anti-Rejoin / Reconnect", Default = false, Tooltip = "Auto reconnect when kicked" })
    task.spawn(function()
        -- Error Prompt Detection
        GuiService.ErrorMessageChanged:Connect(function(msg)
            if AntiRejoinToggle.Value and msg ~= "" then
                warn("[BxB] Disconnect detected, reconnecting...")
                task.wait(2)
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
        -- CoreGui Prompt Detection (Backup)
        local prompt = CoreGui:WaitForChild("RobloxPromptGui", 10)
        if prompt then
            prompt:WaitForChild("promptOverlay", 10).ChildAdded:Connect(function(child)
                if AntiRejoinToggle.Value and child.Name == "ErrorPrompt" then
                     task.wait(2)
                     TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end
            end)
        end
    end)

    MiscLeft:AddButton("Rejoin Server", function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
    MiscLeft:AddButton("Server Hop", function() TeleportService:Teleport(game.PlaceId) end)

    local GravitySlider = MiscRight:AddSlider("bxw_gravity", { Text = "Gravity", Default = Workspace.Gravity, Min = 0, Max = 300, Rounding = 0 })
    GravitySlider:OnChanged(function(v) Workspace.Gravity = v end)

    local TimeSlider = MiscRight:AddSlider("bxw_time", { Text = "Time", Default = 14, Min = 0, Max = 24, Rounding = 1 })
    TimeSlider:OnChanged(function(v) Lighting.ClockTime = v end)

    ------------------------------------------------
    -- TAB 6: Settings
    ------------------------------------------------
    local SettingsTab = Tabs.Settings
    local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")

    MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
    MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
    Library.ToggleKeybind = Options.MenuKeybind

    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    ThemeManager:SetFolder("BxB.Ware_Setting")
    SaveManager:SetFolder("BxB.Ware_Setting")
    SaveManager:BuildConfigSection(SettingsTab)
    ThemeManager:ApplyToTab(SettingsTab)

    ------------------------------------------------
    -- Cleanup Logic
    ------------------------------------------------
    Library:OnUnload(function()
        -- Disconnect Connections
        for _, conn in ipairs(Connections) do
            if conn then pcall(function() conn:Disconnect() end) end
        end
        -- Remove Crosshair
        if crosshairLines then
            pcall(function() crosshairLines.h:Remove(); crosshairLines.v:Remove() end)
        end
        -- Remove Aimbot FOV
        if AimbotFOVCircle then pcall(function() AimbotFOVCircle:Remove() end) end
        -- Clean ESP
        cleanupESP()
    end)
end

return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then warn("[MainHub] Fatal error:", err) end
end
