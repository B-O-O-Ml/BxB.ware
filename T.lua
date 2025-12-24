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
local Lighting           = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")

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
-- 1. Secret + Token Verify (ต้องแมพกับ KeyUI.lua)
--====================================================

local SECRET_PEPPER = "BxB.ware-Universal@#$)_%@#^()$@%_)+%(@"  -- ต้องเหมือนใน KeyUI.lua

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
    local datePart = os.date("%Y%m%d") -- ต้องใช้ format เดียวกับฝั่ง KeyUI

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
-- 2. Role System (ใช้ได้ทั้ง Info tab และ tab อื่นในอนาคต)
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

-- ฟังก์ชัน Helper สำหรับ Mark Risky Feature
local function MarkRisky(text)
    return text .. ' <font color="#FF5555" size="10">[RISKY]</font>'
end

--====================================================
-- 3. Helper format เวลา/ข้อความ
--====================================================

local function formatUnixTime(ts)
    if not ts or ts <= 0 then
        return "Lifetime"
    end

    local dt = os.date("*t", ts)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",
        dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec
    )
end

local function formatTimeLeft(expireTs)
    if not expireTs or expireTs <= 0 then
        return "Lifetime"
    end

    local now = os.time()
    local diff = expireTs - now
    if diff <= 0 then
        return "Expired"
    end

    local d = math.floor(diff / 86400)
    diff = diff % 86400
    local h = math.floor(diff / 3600)
    diff = diff % 3600
    local m = math.floor(diff / 60)
    local s = diff % 60

    if d > 0 then
        return string.format("%dd %02dh %02dm %02ds", d, h, m, s)
    else
        return string.format("%02dh %02dm %02ds", h, m, s)
    end
end

local function safeRichLabel(groupbox, text)
    local lbl = groupbox:AddLabel(text, true)
    if lbl and lbl.TextLabel then
        lbl.TextLabel.RichText = true
    end
    return lbl
end

--====================================================
-- 4. ฟังก์ชันหลักของ MainHub
--     (เรียกจาก KeyUI: startFn(Exec, keydata, authToken))
--====================================================

local function MainHub(Exec, keydata, authToken)
    ---------------------------------------------
    -- 4.1 ตรวจ Exec + keydata + token
    ---------------------------------------------
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

    -- Crosshair & Aimbot Drawings storage
    local crosshairLines = nil
    local AimbotFOVCircle = nil
    local AimbotSnapLine = nil

    -- ESP Drawings Storage
    local espDrawings = {}

    -- normalize role
    keydata.role = NormalizeRole(keydata.role)

    ---------------------------------------------
    -- 4.2 โหลด Obsidian Library + Theme/Save
    ---------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    local Library      = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    -- นำ Options และ Toggles มาไว้ในตัวแปรเพื่อใช้งานในส่วนต่าง ๆ
    local Options = Library.Options
    local Toggles = Library.Toggles

    -- [FEATURE] Action Notify Helper
    local function NotifyAction(feature, state)
        if Toggles.ForceNotify and Toggles.ForceNotify.Value then
            local s = state and "Enabled" or "Disabled"
            Library:Notify(string.format("%s: %s", feature, s), 1.5)
        end
    end

    -- 1) สร้าง Window
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

    -- 2) Tabs
    local Tabs = {
        Info = Window:AddTab({
            Name        = "Info",
            Icon        = "info",
            Description = "Key / Script / System info",
        }),

        Player = Window:AddTab({
            Name        = "Player",
            Icon        = "user",
            Description = "Movement / Teleport / View",
        }),

        ESP = Window:AddTab({
            Name        = "ESP & Visuals",
            Icon        = "eye",
            Description = "Player ESP / Visual settings",
        }),

        Combat = Window:AddTab({
            Name        = "Combat & Aimbot",
            Icon        = "target",
            Description = "Aimbot / target selection",
        }),

        Misc = Window:AddTab({
            Name        = "Misc & System",
            Icon        = "joystick",
            Description = "Utilities / Panic / System",
        }),

        Settings = Window:AddTab({
            Name        = "Settings",
            Icon        = "settings",
            Description = "Theme / Config / Keybinds",
        }),
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

    ------------------------------------------------
    -- 4.3 TAB 1: Info [Key / Game]
    ------------------------------------------------
    local InfoTab = Tabs.Info

    local KeyBox = InfoTab:AddLeftGroupbox("Key Info", "key-round")

    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()

    local rawKey = tostring(keydata.key or "N/A")
    local maskedKey
    if #rawKey > 4 then
        maskedKey = string.format("%s-****%s", rawKey:sub(1, 4), rawKey:sub(-3))
    else
        maskedKey = rawKey
    end

    local roleHtml   = GetRoleLabel(keydata.role)
    local statusText = tostring(keydata.status or "active")
    local noteText   = tostring(keydata.note or "-")

    local HttpService = game:GetService("HttpService")
    local remoteKeyData = nil
    local remoteCreatedAtStr = nil
    local remoteExpireStr = nil
    pcall(function()
        local url = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/main/Key_System/data.json"
        local dataStr = game:HttpGet(url)
        if type(dataStr) == "string" and #dataStr > 0 then
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(dataStr)
            end)
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
        if remoteKeyData.expire and remoteKeyData.expire ~= nil then remoteExpireStr = tostring(remoteKeyData.expire) end
    end

    local createdAtText
    if remoteCreatedAtStr then createdAtText = remoteCreatedAtStr
    elseif keydata.timestamp and keydata.timestamp > 0 then createdAtText = formatUnixTime(keydata.timestamp)
    elseif keydata.created_at then createdAtText = tostring(keydata.created_at)
    else createdAtText = "Unknown" end
    local expireTs = tonumber(keydata.expire) or 0

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))
    safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    local tierText = string.upper(keydata.role or "free")
    safeRichLabel(KeyBox, string.format("<b>Tier:</b> %s", tierText))
    safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", noteText))
    safeRichLabel(KeyBox, string.format("<b>Created at:</b> %s", createdAtText))

    local expireDisplay = remoteExpireStr or formatUnixTime(expireTs)
    local timeLeftDisplay = remoteExpireStr and remoteExpireStr or formatTimeLeft(expireTs)
    local ExpireLabel   = safeRichLabel(KeyBox, string.format("<b>Expire:</b> %s", expireDisplay))
    local TimeLeftLabel = safeRichLabel(KeyBox, string.format("<b>Time left:</b> %s", timeLeftDisplay))

    do
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 0.25 then return end
            acc = 0
            local nowExpire = tonumber(keydata.expire) or expireTs
            local expireStr = remoteExpireStr or formatUnixTime(nowExpire)
            local leftStr   = remoteExpireStr and remoteExpireStr or formatTimeLeft(nowExpire)
            if ExpireLabel and ExpireLabel.TextLabel then ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", expireStr) end
            if TimeLeftLabel and TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", leftStr) end
        end))
    end

    KeyBox:AddDivider()
    KeyBox:AddButton("Copy Key Info", function()
        local plainRole   = tostring((remoteKeyData and remoteKeyData.role) or keydata.role or "unknown")
        local plainStatus = tostring((remoteKeyData and remoteKeyData.status) or keydata.status or "unknown")
        local infoText = string.format(
            "Key: %s\nRole: %s\nStatus: %s\nCreated at: %s\nExpire: %s\nHWID Hash: %s\nNote: %s",
            rawKey, plainRole, plainStatus, createdAtText, expireDisplay, tostring(keydata.hwid_hash or "-"), noteText
        )
        pcall(function()
            if setclipboard then setclipboard(infoText) Library:Notify("Key info copied to clipboard", 2)
            else Library:Notify("Clipboard copy not supported on this executor", 2) end
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
    local PerfLabel       = safeRichLabel(GameBox, "<b>Perf:</b> FPS: - | Ping: - ms | Mem: - MB")
    local ServerTimeLabel = safeRichLabel(GameBox, "<b>Server Time:</b> -")

    task.spawn(function()
        local gameName = "Unknown Place"
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, placeId)
        if ok and info and info.Name then gameName = info.Name end
        if GameNameLabel and GameNameLabel.TextLabel then GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", gameName) end
    end)

    local function updatePlayersLabel()
        local current = #Players:GetPlayers()
        local max = Players.MaxPlayers or "-"
        if PlayersLabel and PlayersLabel.TextLabel then PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d / %s", current, tostring(max)) end
    end
    updatePlayersLabel()
    AddConnection(Players.PlayerAdded:Connect(updatePlayersLabel))
    AddConnection(Players.PlayerRemoving:Connect(updatePlayersLabel))

    do
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 0.25 then return end
            acc = 0
            local fps = math.floor(1 / math.max(dt, 1/240))
            local pingMs = 0
            local memMb  = 0
            local okPing, pingItem = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"] end)
            if okPing and pingItem and pingItem.GetValue then
                local v = pingItem:GetValue()
                if typeof(v) == "number" then pingMs = math.floor(v) end
            end
            local okMem, mem = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
            if okMem and type(mem) == "number" then memMb = math.floor(mem) end
            updatePlayersLabel()
            if PerfLabel and PerfLabel.TextLabel then PerfLabel.TextLabel.Text = string.format("<b>Perf:</b> FPS: %d | Ping: %d ms | Mem: %d MB", fps, pingMs, memMb) end
            if ServerTimeLabel and ServerTimeLabel.TextLabel then ServerTimeLabel.TextLabel.Text = string.format("<b>Server Time:</b> %s", os.date("%H:%M:%S")) end
        end))
    end

    --------------------------------------------------------
    -- 2. PLAYER TAB (Full Logic with Disabled)
    --------------------------------------------------------
   local PlayerTab = Tabs.Player

    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    -- WalkSpeed
    local defaultWalkSpeed = 16
    local walkSpeedEnabled = false
    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = defaultWalkSpeed, Min = 0, Max = 120, Rounding = 0, Compact = false,
        Callback = function(value)
            if not walkSpeedEnabled then return end
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = value end
        end,
    })

    -- Lock slider if toggle is off
    WalkSpeedSlider:SetDisabled(true)

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
    local WalkMethodDropdown = MoveBox:AddDropdown("bxw_walk_method", { Text = "Walk Method", Values = { "Direct", "Incremental" }, Default = "Direct", Multi = false })

    -- JumpPower
    local defaultJumpPower = 50
    local jumpPowerEnabled = false
    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = defaultJumpPower, Min = 0, Max = 200, Rounding = 0, Compact = false,
        Callback = function(value)
            if not jumpPowerEnabled then return end
            local hum = getHumanoid()
            if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = value end
        end,
    })

    -- Lock slider if toggle is off
    JumpPowerSlider:SetDisabled(true)

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        if JumpPowerSlider.SetDisabled then JumpPowerSlider:SetDisabled(not state) end
        local hum = getHumanoid()
        if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower end
        NotifyAction("JumpPower", state)
    end)
    MoveBox:AddButton("Reset JumpPower", function()
        local hum = getHumanoid()
        if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = defaultJumpPower end
        JumpPowerSlider:SetValue(defaultJumpPower)
        JumpPowerToggle:SetValue(false)
    end)

    MoveBox:AddLabel("Movement Presets")
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

    -- Smooth Fly
    local flyConn, flyBV, flyBG
    local flyEnabled = false
    local flySpeed = 60
    local FlyToggle = MoveBox:AddToggle("bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = flySpeed, Min = 1, Max = 300, Rounding = 0, Compact = false, Callback = function(value) flySpeed = value end })
    
    FlySpeedSlider:SetDisabled(true)

    FlyToggle:OnChanged(function(state)
        flyEnabled = state
        FlySpeedSlider:SetDisabled(not state)

        local char = getCharacter()
        local root = getRootPart()
        local hum  = getHumanoid()
        local cam  = Workspace.CurrentCamera
        if not state then
            if flyConn then flyConn:Disconnect() flyConn = nil end
            if flyBV then flyBV:Destroy() flyBV = nil end
            if flyBG then flyBG:Destroy() flyBG = nil end
            if hum then hum.PlatformStand = false end
            NotifyAction("Fly", false)
            return
        end
        if not (root and hum and cam) then
            if Library and Library.Notify then Library:Notify("Cannot start fly: character not loaded", 3) end
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
            local hum  = getHumanoid()
            local cam  = Workspace.CurrentCamera
            if not (root and hum and cam and flyBV and flyBG) then return end
            local moveDir = Vector3.new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            if moveDir.Magnitude > 0 then moveDir = moveDir.Unit flyBV.Velocity = moveDir * flySpeed else flyBV.Velocity = Vector3.zero end
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
            if char then for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end end
            NotifyAction("Noclip", false)
            return
        end
        if noclipConn then noclipConn:Disconnect() end
        noclipConn = AddConnection(RunService.Stepped:Connect(function()
            local char = getCharacter()
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = false end end
        end))
        NotifyAction("Noclip", true)
    end)

    ------------------------------------------------
    -- 2.2 Right: Teleport / Utility
    ------------------------------------------------
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
        if cf and root then root.CFrame = cf + Vector3.new(0, 3, 0) Library:Notify("Teleported to " .. sel, 2) else Library:Notify("Waypoint or character missing", 2) end
    end)

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
            if not originalSkyCam then originalSkyCam = lighting:FindFirstChildOfClass("Sky") if originalSkyCam then originalSkyCam = originalSkyCam:Clone() end end
            local currentSky = lighting:FindFirstChildOfClass("Sky") if currentSky then currentSky:Destroy() end
            local id = SkyboxThemes[name]
            if id and id ~= "" then local sky = Instance.new("Sky") sky.SkyboxBk = id sky.SkyboxDn = id sky.SkyboxFt = id sky.SkyboxLf = id sky.SkyboxRt = id sky.SkyboxUp = id sky.Parent = lighting else if originalSkyCam then local newSky = originalSkyCam:Clone() newSky.Parent = lighting end end
        end
        SkyboxDropdown:OnChanged(function(value) applySkyCam(value) end)
    end

    ------------------------------------------------
    -- 4.3 ESP & Visuals Tab (Full Uncompressed Logic + Disabled)
    ------------------------------------------------
    do
        local ESPTab = Tabs.ESP
        local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
        local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")

        local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP", Default = false })
        ESPEnabledToggle:OnChanged(function(state) NotifyAction("Global ESP", state) end)

        local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box", Multi = false })

        local BoxToggle      = ESPFeatureBox:AddToggle("bxw_esp_box",      { Text = "Box",        Default = true })
        -- Lock Box Style
        BoxStyleDropdown:SetDisabled(true)
        BoxToggle:OnChanged(function(state) BoxStyleDropdown:SetDisabled(not state) end)

        local ChamsToggle    = ESPFeatureBox:AddToggle("bxw_esp_chams",    { Text = "Chams",      Default = false })
        local SkeletonToggle = ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton",   Default = false })
        local HealthToggle   = ESPFeatureBox:AddToggle("bxw_esp_health",   { Text = "Health Bar", Default = false })
        local NameToggle     = ESPFeatureBox:AddToggle("bxw_esp_name",     { Text = "Name Tag",   Default = true })
        local DistToggle     = ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance",   Default = false })
        local TracerToggle   = ESPFeatureBox:AddToggle("bxw_esp_tracer",   { Text = "Tracer",     Default = false })
        local TeamToggle     = ESPFeatureBox:AddToggle("bxw_esp_team",     { Text = "Team Check", Default = true })
        local WallToggle     = ESPFeatureBox:AddToggle("bxw_esp_wall",     { Text = "Wall Check", Default = false })

        local SelfToggle     = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false })
        local InfoToggle     = ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info", Default = false, Tooltip = "Shows HP, Weapon & Team" })
        
        local HeadDotToggle = ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false })

        local function getPlayerNames()
            local names = {}
            for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then table.insert(names, plr.Name) end end
            table.sort(names)
            return names
        end
        local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = getPlayerNames(), Default = "", Multi = true, AllowNull = true })
        do
            local function refreshWhitelist() local names = getPlayerNames() WhitelistDropdown:SetValues(names) end
            refreshWhitelist()
            AddConnection(Players.PlayerAdded:Connect(refreshWhitelist))
            AddConnection(Players.PlayerRemoving:Connect(refreshWhitelist))
            task.spawn(function() while true do task.wait(10) refreshWhitelist() end end)
        end

        local BoxColorLabel = ESPSettingBox:AddLabel("Box Color")
        BoxColorLabel:AddColorPicker("bxw_esp_box_color", { Default = Color3.fromRGB(255, 255, 255) })
        local TracerColorLabel = ESPSettingBox:AddLabel("Tracer Color")
        TracerColorLabel:AddColorPicker("bxw_esp_tracer_color", { Default = Color3.fromRGB(255, 255, 255) })
        local NameColorLabel = ESPSettingBox:AddLabel("Name Color")
        NameColorLabel:AddColorPicker("bxw_esp_name_color", { Default = Color3.fromRGB(255, 255, 255) })
        
        local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        -- Lock Name Size
        NameSizeSlider:SetDisabled(true)
        NameToggle:OnChanged(function(state) NameSizeSlider:SetDisabled(not state) end)

        local DistColorLabel = ESPSettingBox:AddLabel("Distance Color")
        DistColorLabel:AddColorPicker("bxw_esp_dist_color", { Default = Color3.fromRGB(255, 255, 255) })
        
        local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Distance Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local DistUnitDropdown = ESPSettingBox:AddDropdown("bxw_esp_dist_unit", { Text = "Distance Unit", Values = { "Studs", "Meters" }, Default = "Studs", Multi = false })
        -- Lock Distance Settings
        DistSizeSlider:SetDisabled(true)
        DistUnitDropdown:SetDisabled(true)
        DistToggle:OnChanged(function(state) DistSizeSlider:SetDisabled(not state) DistUnitDropdown:SetDisabled(not state) end)

        local SkeletonColorLabel = ESPSettingBox:AddLabel("Skeleton Color")
        SkeletonColorLabel:AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.fromRGB(0, 255, 255) })
        local HealthColorLabel = ESPSettingBox:AddLabel("Health Bar Color")
        HealthColorLabel:AddColorPicker("bxw_esp_health_color", { Default = Color3.fromRGB(0, 255, 0) })
        local InfoColorLabel = ESPSettingBox:AddLabel("Info Color")
        InfoColorLabel:AddColorPicker("bxw_esp_info_color", { Default = Color3.fromRGB(255, 255, 255) })
        local HeadDotColorLabel = ESPSettingBox:AddLabel("Head Dot Color")
        HeadDotColorLabel:AddColorPicker("bxw_esp_headdot_color", { Default = Color3.fromRGB(255, 0, 0) })
        
        local HeadDotSizeSlider = ESPSettingBox:AddSlider("bxw_esp_headdot_size", { Text = "Head Dot Size", Default = 3, Min = 1, Max = 10, Rounding = 0 })
        -- Lock Head Dot Size
        HeadDotSizeSlider:SetDisabled(true)
        HeadDotToggle:OnChanged(function(state) HeadDotSizeSlider:SetDisabled(not state) end)

        local ChamsColorLabel = ESPSettingBox:AddLabel("Chams Color")
        ChamsColorLabel:AddColorPicker("bxw_esp_chams_color", { Default = Color3.fromRGB(0, 255, 0) })
        
        local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2, Compact = false })
        local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Visible Only", Default = false })
        -- Lock Chams Settings
        ChamsTransSlider:SetDisabled(true)
        ChamsVisibleToggle:SetDisabled(true)
        ChamsToggle:OnChanged(function(state) ChamsTransSlider:SetDisabled(not state) ChamsVisibleToggle:SetDisabled(not state) end)

        local ESPRefreshSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "ESP Refresh (ms)", Default = 50, Min = 0, Max = 250, Rounding = 0, Compact = false })

        local CrosshairToggle = ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
        local CrossColorLabel = ESPSettingBox:AddLabel("Crosshair Color")
        CrossColorLabel:AddColorPicker("bxw_crosshair_color", { Default = Color3.fromRGB(255, 255, 255) })
        local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20, Rounding = 0, Compact = false })
        local CrossThickSlider = ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Crosshair Thickness", Default = 1, Min = 1, Max = 5, Rounding = 0 })
        -- Lock Crosshair Settings
        CrossSizeSlider:SetDisabled(true)
        CrossThickSlider:SetDisabled(true)
        CrosshairToggle:OnChanged(function(state) CrossSizeSlider:SetDisabled(not state) CrossThickSlider:SetDisabled(not state) NotifyAction("Crosshair", state) end)

        -- Helper to remove ESP
        local lastESPUpdate = 0
        local function removePlayerESP(plr)
            local data = espDrawings[plr]
            if data then
                if data.Box then pcall(function() data.Box:Remove() end) end
                if data.Corners then for _, ln in pairs(data.Corners) do pcall(function() ln:Remove() end) end end
                if data.Health then if data.Health.Outline then pcall(function() data.Health.Outline:Remove() end) end if data.Health.Bar then pcall(function() data.Health.Bar:Remove() end) end end
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

        AddConnection(Players.PlayerRemoving:Connect(function(plr) removePlayerESP(plr) end))

        local skeletonJoints = {
            ["Head"] = "UpperTorso", ["UpperTorso"] = "LowerTorso", ["LowerTorso"] = "HumanoidRootPart",
            ["LeftUpperArm"] = "UpperTorso", ["LeftLowerArm"] = "LeftUpperArm", ["LeftHand"] = "LeftLowerArm",
            ["RightUpperArm"] = "UpperTorso", ["RightLowerArm"] = "RightUpperArm", ["RightHand"] = "RightLowerArm",
            ["LeftUpperLeg"] = "LowerTorso", ["LeftLowerLeg"] = "LeftUpperLeg", ["LeftFoot"] = "LeftLowerLeg",
            ["RightUpperLeg"] = "LowerTorso", ["RightLowerLeg"] = "RightUpperLeg", ["RightFoot"] = "RightLowerLeg",
        }

        local function updateESP()
            if ESPRefreshSlider then
                local nowTick = tick()
                local ms = ESPRefreshSlider.Value or 0
                if nowTick - lastESPUpdate < (ms / 1000) then return end
                lastESPUpdate = nowTick
            end
            if not ESPEnabledToggle.Value then
                for _, v in pairs(espDrawings) do
                    if v.Box then v.Box.Visible = false end
                    if v.Corners then for _, ln in pairs(v.Corners) do ln.Visible = false end end
                    if v.Health then if v.Health.Outline then v.Health.Outline.Visible = false end if v.Health.Bar then v.Health.Bar.Visible = false end end
                    if v.Name then v.Name.Visible = false end
                    if v.Distance then v.Distance.Visible = false end
                    if v.Tracer then v.Tracer.Visible = false end
                    if v.HeadDot then v.HeadDot.Visible = false end
                    if v.Highlight then v.Highlight.Enabled = false end
                    if v.Info then v.Info.Visible = false end
                    if v.Skeleton then for _, ln in pairs(v.Skeleton) do ln.Visible = false end end
                end
                return
            end

            local cam = Workspace.CurrentCamera
            if not cam then return end
            local camCFrame = cam.CFrame
            local camPos = camCFrame.Position

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer or (SelfToggle and SelfToggle.Value) then
                    local char = plr.Character
                    local hum  = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart") or char and char:FindFirstChild("Torso") or char and char:FindFirstChild("UpperTorso")
                    
                    if not hum or hum.Health <= 0 or not root then
                        local d = espDrawings[plr]
                        if d then
                            if d.Box then d.Box.Visible = false end
                            if d.Corners then for _, ln in pairs(d.Corners) do ln.Visible = false end end
                            if d.Health then if d.Health.Outline then d.Health.Outline.Visible = false end if d.Health.Bar then d.Health.Bar.Visible = false end end
                            if d.Name then d.Name.Visible = false end
                            if d.Distance then d.Distance.Visible = false end
                            if d.Tracer then d.Tracer.Visible = false end
                            if d.Skeleton then for _, ln in pairs(d.Skeleton) do ln.Visible = false end end
                            if d.Highlight then d.Highlight.Enabled = false end
                            if d.HeadDot then d.HeadDot.Visible = false end
                            if d.Info then d.Info.Visible = false end
                        end
                    elseif hum and hum.Health > 0 and root then
                        local skipPlayer = false
                        if TeamToggle.Value then
                            local myTeam = LocalPlayer.Team
                            local hisTeam = plr.Team
                            if myTeam ~= nil and hisTeam ~= nil and myTeam == hisTeam then skipPlayer = true end
                        end
                        if not skipPlayer then
                            local list = WhitelistDropdown.Value
                            if list and type(list) == "table" then
                                for _, name in ipairs(list) do if name == plr.Name then skipPlayer = true break end end
                            end
                        end

                        if skipPlayer then
                            if espDrawings[plr] then
                                local d = espDrawings[plr]
                                if d.Box then d.Box.Visible = false end
                                if d.Corners then for _, ln in pairs(d.Corners) do ln.Visible = false end end
                                if d.Health then if d.Health.Outline then d.Health.Outline.Visible = false end if d.Health.Bar then d.Health.Bar.Visible = false end end
                                if d.Name then d.Name.Visible = false end
                                if d.Distance then d.Distance.Visible = false end
                                if d.Tracer then d.Tracer.Visible = false end
                                if d.Highlight then d.Highlight.Enabled = false end
                                if d.HeadDot then d.HeadDot.Visible = false end
                                if d.Info then d.Info.Visible = false end
                            end
                        else
                            local data = espDrawings[plr]
                            if not data then data = {} espDrawings[plr] = data end

                            -- Wall Check Logic First (Determine Shared Color)
                            local isVisible = true
                            if WallToggle.Value then
                                local rayDir = (root.Position - camPos)
                                local rayParams = RaycastParams.new()
                                rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                local rayResult = Workspace:Raycast(camPos, rayDir, rayParams)
                                if rayResult then isVisible = false end
                            end

                            local sharedColor
                            if WallToggle.Value then
                                sharedColor = isVisible and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
                            end

                            if ChamsToggle.Value then
                                local chamsCol = sharedColor or (Options.bxw_esp_chams_color and Options.bxw_esp_chams_color.Value) or Color3.fromRGB(255, 255, 255)
                                local chamsTrans = ChamsTransSlider and ChamsTransSlider.Value or 0.5
                                local visibleOnly = ChamsVisibleToggle and ChamsVisibleToggle.Value or false
                                local depthMode = visibleOnly and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                                if not data.Highlight then
                                    local hl = Instance.new("Highlight")
                                    hl.Parent = char
                                    data.Highlight = hl
                                end
                                local hl = data.Highlight
                                hl.Enabled = true
                                hl.DepthMode = depthMode
                                hl.FillColor = chamsCol
                                hl.OutlineColor = chamsCol
                                hl.FillTransparency = chamsTrans
                                hl.Adornee = char
                            else
                                if data.Highlight then data.Highlight.Enabled = false end
                            end

                            local minVec, maxVec = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
                            for _, part in ipairs(char:GetDescendants()) do
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
                            local screenPoints = {}
                            local onScreen = false
                            for i, worldPos in ipairs(cornersWorld) do
                                local screenPos, vis = cam:WorldToViewportPoint(worldPos)
                                screenPoints[i] = Vector2.new(screenPos.X, screenPos.Y)
                                onScreen = onScreen or vis
                            end

                            if not onScreen then
                                if data.Box then data.Box.Visible = false end
                                if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                if data.Health then if data.Health.Outline then data.Health.Outline.Visible = false end if data.Health.Bar then data.Health.Bar.Visible = false end end
                                if data.Name then data.Name.Visible = false end
                                if data.Distance then data.Distance.Visible = false end
                                if data.Tracer then data.Tracer.Visible = false end
                                if data.HeadDot then data.HeadDot.Visible = false end
                                if data.Info then data.Info.Visible = false end
                            else
                                local minX, minY = math.huge, math.huge
                                local maxX, maxY = -math.huge, -math.huge
                                for _, v2 in ipairs(screenPoints) do
                                    minX = math.min(minX, v2.X) maxX = math.max(maxX, v2.X)
                                    minY = math.min(minY, v2.Y) maxY = math.max(maxY, v2.Y)
                                end
                                local boxW, boxH = maxX - minX, maxY - minY
                                local finalColor = sharedColor or (Options.bxw_esp_box_color and Options.bxw_esp_box_color.Value) or Color3.fromRGB(255, 255, 255)

                                if BoxToggle.Value then
                                    if BoxStyleDropdown.Value == "Box" then
                                        if not data.Box then local sq = Drawing.new("Square") sq.Thickness = 1 sq.Filled = false sq.Transparency = 1 data.Box = sq end
                                        data.Box.Visible = true
                                        data.Box.Color = finalColor
                                        data.Box.Position = Vector2.new(minX, minY)
                                        data.Box.Size = Vector2.new(boxW, boxH)
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

                                if HealthToggle.Value then
                                    if not data.Health then data.Health = { Outline = Drawing.new("Line"), Bar = Drawing.new("Line") } data.Health.Outline.Thickness = 3 data.Health.Bar.Thickness = 1 end
                                    local hbX = minX - 6
                                    -- Secure Health Calc
                                    local hp = math.clamp(hum.Health, 0, hum.MaxHealth)
                                    local maxHp = math.max(hum.MaxHealth, 1)
                                    local barY2 = minY + (maxY - minY) * (1 - (hp / maxHp))
                                    data.Health.Outline.Visible = true data.Health.Outline.Color = Color3.new(0,0,0) data.Health.Outline.From = Vector2.new(hbX, minY) data.Health.Outline.To = Vector2.new(hbX, maxY)
                                    data.Health.Bar.Visible = true data.Health.Bar.Color = (Options.bxw_esp_health_color and Options.bxw_esp_health_color.Value) or finalColor
                                    data.Health.Bar.From = Vector2.new(hbX, minY) data.Health.Bar.To = Vector2.new(hbX, barY2)
                                else
                                    if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end
                                end

                                if NameToggle.Value then
                                    if not data.Name then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Name = txt end
                                    data.Name.Visible = true
                                    data.Name.Color = sharedColor or (Options.bxw_esp_name_color and Options.bxw_esp_name_color.Value)
                                    data.Name.Size = NameSizeSlider.Value
                                    data.Name.Text = plr.DisplayName or plr.Name
                                    data.Name.Position = Vector2.new((minX + maxX) / 2, minY - 14)
                                else
                                    if data.Name then data.Name.Visible = false end
                                end

                                if DistToggle.Value then
                                    if not data.Distance then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Distance = txt end
                                    local distStud = (root.Position - camPos).Magnitude
                                    local unit = DistUnitDropdown and DistUnitDropdown.Value or "Studs"
                                    local distNum = distStud
                                    local suffix = " studs"
                                    if unit == "Meters" then distNum = distStud * 0.28 suffix = " m" end
                                    data.Distance.Visible = true
                                    data.Distance.Color = sharedColor or (Options.bxw_esp_dist_color and Options.bxw_esp_dist_color.Value)
                                    data.Distance.Size = DistSizeSlider.Value
                                    data.Distance.Text = string.format("%.1f", distNum) .. suffix
                                    data.Distance.Position = Vector2.new((minX + maxX) / 2, maxY + 2)
                                else
                                    if data.Distance then data.Distance.Visible = false end
                                end

                                -- Target Info Upgrade (Real data & Weapon check)
                                if InfoToggle and InfoToggle.Value then
                                    if not data.Info then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Info = txt end
                                    local distStudInfo = (root.Position - camPos).Magnitude
                                    local unitInfo = DistUnitDropdown and DistUnitDropdown.Value or "Studs"
                                    local distNumInfo = distStudInfo
                                    local suffixInfo = "s"
                                    if unitInfo == "Meters" then distNumInfo = distStudInfo * 0.28 suffixInfo = "m" end
                                    
                                    -- Check Team
                                    local teamName = plr.Team and plr.Team.Name or "Neutral"
                                    
                                    -- Check Weapon/Tool
                                    local currentTool = char:FindFirstChildOfClass("Tool")
                                    local toolName = currentTool and currentTool.Name or "None"

                                    -- Check Real HP
                                    local hpVal = math.floor(hum.Health)

                                    data.Info.Visible = true
                                    data.Info.Color = sharedColor or (Options.bxw_esp_info_color and Options.bxw_esp_info_color.Value) or Color3.fromRGB(255, 255, 255)
                                    data.Info.Size = NameSizeSlider.Value
                                    -- Updated Text Format
                                    data.Info.Text = string.format("[HP: %d] [Dist: %.0f%s]\n[Team: %s] [Wep: %s]", hpVal, distNumInfo, suffixInfo, teamName, toolName)
                                    data.Info.Position = Vector2.new((minX + maxX) / 2, maxY + 16)
                                else
                                    if data.Info then data.Info.Visible = false end
                                end

                                if SkeletonToggle and SkeletonToggle.Value then
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
                                                ln.Visible = true
                                                ln.Color = skCol
                                                ln.From = Vector2.new(sp1.X, sp1.Y)
                                                ln.To   = Vector2.new(sp2.X, sp2.Y)
                                            else
                                                ln.Visible = false
                                            end
                                        else
                                            ln.Visible = false
                                        end
                                        idx = idx + 1
                                    end
                                else
                                    if data.Skeleton then for _, ln in pairs(data.Skeleton) do ln.Visible = false end end
                                end

                                if HeadDotToggle and HeadDotToggle.Value then
                                    local head = char:FindFirstChild("Head")
                                    if head then
                                        local spHead, headVis = cam:WorldToViewportPoint(head.Position)
                                        if headVis then
                                            if not data.HeadDot then data.HeadDot = Drawing.new("Circle") data.HeadDot.Filled = true data.HeadDot.Transparency = 1 end
                                            data.HeadDot.Visible = true
                                            data.HeadDot.Color = sharedColor or (Options.bxw_esp_headdot_color and Options.bxw_esp_headdot_color.Value)
                                            data.HeadDot.Position = Vector2.new(spHead.X, spHead.Y)
                                            data.HeadDot.Radius = (Options.bxw_esp_headdot_size and Options.bxw_esp_headdot_size.Value) or 3
                                        else
                                            if data.HeadDot then data.HeadDot.Visible = false end
                                        end
                                    end
                                else
                                    if data.HeadDot then data.HeadDot.Visible = false end
                                end

                                if TracerToggle.Value then
                                    if not data.Tracer then data.Tracer = Drawing.new("Line") data.Tracer.Thickness = 1 data.Tracer.Transparency = 1 end
                                    local screenRoot, rootOnScreen = cam:WorldToViewportPoint(root.Position)
                                    if rootOnScreen then
                                        data.Tracer.Visible = true
                                        data.Tracer.Color = sharedColor or (Options.bxw_esp_tracer_color and Options.bxw_esp_tracer_color.Value)
                                        data.Tracer.From = Vector2.new(screenRoot.X, screenRoot.Y)
                                        data.Tracer.To = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                                    else
                                        data.Tracer.Visible = false
                                    end
                                else
                                    if data.Tracer then data.Tracer.Visible = false end
                                end
                            end
                        end
                    else
                        removePlayerESP(plr)
                    end
                end
            end
        end

        AddConnection(RunService.RenderStepped:Connect(updateESP))

        do
            local deathConnections = {}
            local function attachDeathListener(plr)
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    if deathConnections[plr] then pcall(function() deathConnections[plr]:Disconnect() end) deathConnections[plr] = nil end
                    deathConnections[plr] = AddConnection(hum.Died:Connect(function() removePlayerESP(plr) end))
                end
            end
            for _, plr in ipairs(Players:GetPlayers()) do
                attachDeathListener(plr)
                AddConnection(plr.CharacterAdded:Connect(function() attachDeathListener(plr) end))
            end
            AddConnection(Players.PlayerAdded:Connect(function(plr)
                AddConnection(plr.CharacterAdded:Connect(function() attachDeathListener(plr) end))
            end))
            AddConnection(Players.PlayerRemoving:Connect(function(plr)
                if deathConnections[plr] then pcall(function() deathConnections[plr]:Disconnect() end) deathConnections[plr] = nil end
                removePlayerESP(plr)
            end))
        end

        crosshairLines = { h = Drawing.new("Line"), v = Drawing.new("Line") }
        crosshairLines.h.Transparency = 1 crosshairLines.v.Transparency = 1
        crosshairLines.h.Visible = false crosshairLines.v.Visible = false
        AddConnection(RunService.RenderStepped:Connect(function()
            local toggle = Toggles.bxw_crosshair_enable and Toggles.bxw_crosshair_enable.Value
            if toggle then
                local cam = workspace.CurrentCamera
                if cam then
                    local cx, cy = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
                    local size  = (Options.bxw_crosshair_size and Options.bxw_crosshair_size.Value) or 5
                    local thick = (Options.bxw_crosshair_thick and Options.bxw_crosshair_thick.Value) or 1
                    local col   = (Options.bxw_crosshair_color and Options.bxw_crosshair_color.Value) or Color3.new(1, 1, 1)
                    crosshairLines.h.Visible = true crosshairLines.h.From = Vector2.new(cx - size, cy) crosshairLines.h.To = Vector2.new(cx + size, cy) crosshairLines.h.Color = col crosshairLines.h.Thickness= thick
                    crosshairLines.v.Visible = true crosshairLines.v.From = Vector2.new(cx, cy - size) crosshairLines.v.To = Vector2.new(cx, cy + size) crosshairLines.v.Color = col crosshairLines.v.Thickness= thick
                end
            else
                if crosshairLines.h then crosshairLines.h.Visible = false end
                if crosshairLines.v then crosshairLines.v.Visible = false end
            end
        end))
    end

    ------------------------------------------------
    -- 4.4 Combat & Aimbot Tab (Interlocked UI & Full Logic)
    ------------------------------------------------
    do
        local CombatTab = Tabs.Combat
        local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
        local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

        AimBox:AddLabel("Core Settings")
        local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false })
        local SilentToggle = AimBox:AddToggle("bxw_silent_enable", { Text = "Silent Aim", Default = false })

        AimBox:AddLabel("Aim & Target Settings")
        local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest", "Random", "Custom" }, Default = "Head", Multi = false })
        
        -- Smart Aim Logic Toggle
        local UseSmartAimLogic = AimBox:AddToggle("bxw_aim_smart_logic", { Text = "Smart Aim Logic", Default = true, Tooltip = "Auto-calculate best target based on Distance, HP and Mouse Proximity" })

        AimBox:AddLabel("FOV Settings")
        local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
        local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
        local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Aimbot Smoothness", Default = 0.1, Min = 0.01, Max = 1, Rounding = 2 })
        local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
        local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false })
        local VisibilityToggle = AimBox:AddToggle("bxw_aim_visibility", { Text = "Visibility Check", Default = false })
        local HitChanceSlider = AimBox:AddSlider("bxw_aim_hitchance", { Text = "Hit Chance %", Default = 100, Min = 1, Max = 100, Rounding = 0 })
        local RainbowToggle = AimBox:AddToggle("bxw_aim_rainbow", { Text = "Rainbow FOV", Default = false })
        local RainbowSpeedSlider = AimBox:AddSlider("bxw_aim_rainbowspeed", { Text = "Rainbow Speed", Default = 5, Min = 1, Max = 10, Rounding = 1 })
        local FOVColorLabel = AimBox:AddLabel("FOV Color")
        FOVColorLabel:AddColorPicker("bxw_aim_fovcolor", { Default = Color3.fromRGB(255, 255, 255) })
        AimBox:AddDivider()
        local AimMethodDropdown = AimBox:AddDropdown("bxw_aim_method", { Text = "Aim Method", Values = { "CameraLock", "MouseDelta" }, Default = "CameraLock", Multi = false })
        local TargetModeDropdown = AimBox:AddDropdown("bxw_aim_targetmode", { Text = "Target Mode", Values = { "Closest To Crosshair", "Closest Distance", "Lowest Health" }, Default = "Closest To Crosshair", Multi = false })
        local ShowSnapToggle = AimBox:AddToggle("bxw_aim_snapline", { Text = "Show SnapLine", Default = false })
        local SnapColorLabel = AimBox:AddLabel("SnapLine Color")
        SnapColorLabel:AddColorPicker("bxw_aim_snapcolor", { Default = Color3.fromRGB(255, 0, 0) })
        local SnapThicknessSlider = AimBox:AddSlider("bxw_aim_snapthick", { Text = "SnapLine Thickness", Default = 1, Min = 1, Max = 5, Rounding = 0 })

        AimBox:AddDivider()
        AimBox:AddLabel("Activation & Extras")
        local AimActivationDropdown = AimBox:AddDropdown("bxw_aim_activation", { Text = "Aim Activation", Values = { "Hold Right Click", "Always On" }, Default = "Hold Right Click", Multi = false })
        local SmartAimToggle = AimBox:AddToggle("bxw_aim_smart", { Text = "Smart BodyAim", Default = false, Tooltip = "Aim at head if body blocked" }) 
        local PredToggle = AimBox:AddToggle("bxw_aim_pred", { Text = "Prediction Aim", Default = false })
        local PredSlider = AimBox:AddSlider("bxw_aim_predfactor", { Text = "Prediction Factor", Default = 0.1, Min = 0, Max = 1, Rounding = 2 })

        -- Interlock Aimbot UI
        local function UpdateAimUI(state)
            FOVSlider:SetDisabled(not state)
            SmoothSlider:SetDisabled(not state)
            HitChanceSlider:SetDisabled(not state)
            AimPartDropdown:SetDisabled(not state)
            AimMethodDropdown:SetDisabled(not state)
        end
        -- Default Locked
        UpdateAimUI(false)
        AimbotToggle:OnChanged(function(state)
            UpdateAimUI(state)
            NotifyAction("Aimbot", state)
        end)


        local TriggerTeamToggle = ExtraBox:AddToggle("bxw_trigger_teamcheck", { Text = "Trigger Team Check", Default = true })
        local TriggerWallToggle = ExtraBox:AddToggle("bxw_trigger_wallcheck", { Text = "Trigger Wall Check", Default = false })
        local TriggerMethodDropdown = ExtraBox:AddDropdown("bxw_trigger_method", { Text = "Trigger Method", Values = { "Always On", "Hold Key" }, Default = "Always On", Multi = false })
        local TriggerFiringDropdown = ExtraBox:AddDropdown("bxw_trigger_firemode", { Text = "Firing Mode", Values = { "Single", "Burst", "Auto" }, Default = "Single", Multi = false })
        local TriggerFovSlider = ExtraBox:AddSlider("bxw_trigger_fov", { Text = "Trigger FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
        local TriggerDelaySlider = ExtraBox:AddSlider("bxw_trigger_delay", { Text = "Trigger Delay (s)", Default = 0.05, Min = 0, Max = 1, Rounding = 2 })
        local TriggerHoldSlider = ExtraBox:AddSlider("bxw_trigger_hold", { Text = "Trigger HoldTime (s)", Default = 0.05, Min = 0.01, Max = 0.5, Rounding = 2 })
        local TriggerReleaseSlider = ExtraBox:AddSlider("bxw_trigger_release", { Text = "Trigger ReleaseTime (s)", Default = 0.05, Min = 0.01, Max = 0.5, Rounding = 2 })
        
        -- Lock Trigger settings
        TriggerFiringDropdown:SetDisabled(true)
        TriggerFovSlider:SetDisabled(true)
        TriggerbotToggle:OnChanged(function(state)
            TriggerFiringDropdown:SetDisabled(not state)
            TriggerFovSlider:SetDisabled(not state)
            NotifyAction("Triggerbot", state)
        end)

        ExtraBox:AddDivider()
        ExtraBox:AddLabel("Hit Chance per Part")
        local HeadChanceSlider = ExtraBox:AddSlider("bxw_hit_head_chance", { Text = "Head Hit Chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 })
        local UpTorsoChanceSlider = ExtraBox:AddSlider("bxw_hit_uptorso_chance", { Text = "Upper Torso Hit Chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 })
        local TorsoChanceSlider = ExtraBox:AddSlider("bxw_hit_torso_chance", { Text = "Torso Hit Chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 })
        local HandChanceSlider = ExtraBox:AddSlider("bxw_hit_hand_chance", { Text = "Hand/Arm Hit Chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 })
        local LegChanceSlider = ExtraBox:AddSlider("bxw_hit_leg_chance", { Text = "Leg Hit Chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 })

        AimbotFOVCircle = Drawing.new("Circle") AimbotFOVCircle.Transparency = 0.5 AimbotFOVCircle.Filled = false AimbotFOVCircle.Thickness = 1 AimbotFOVCircle.Color = Color3.fromRGB(255, 255, 255)
        AimbotSnapLine = Drawing.new("Line") AimbotSnapLine.Transparency = 0.7 AimbotSnapLine.Visible = false
        local rainbowHue = 0

        local function performClick() pcall(function() mouse1click() end) pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(Vector2.new()) end) end

        AddConnection(RunService.RenderStepped:Connect(function()
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local mouseLoc = UserInputService:GetMouseLocation()

            if Toggles.bxw_aim_showfov and Toggles.bxw_aim_showfov.Value and Toggles.bxw_aimbot_enable and Toggles.bxw_aimbot_enable.Value then
                AimbotFOVCircle.Visible = true
                AimbotFOVCircle.Radius = (((Options.bxw_aim_fov and Options.bxw_aim_fov.Value) or 10) * 15)
                AimbotFOVCircle.Position = mouseLoc
                if Toggles.bxw_aim_rainbow and Toggles.bxw_aim_rainbow.Value then
                    rainbowHue = (rainbowHue or 0) + (((Options.bxw_aim_rainbowspeed and Options.bxw_aim_rainbowspeed.Value) or 0) / 360)
                    if rainbowHue > 1 then rainbowHue = rainbowHue - 1 end
                    AimbotFOVCircle.Color = Color3.fromHSV(rainbowHue, 1, 1)
                else
                    AimbotFOVCircle.Color = (Options.bxw_aim_fovcolor and Options.bxw_aim_fovcolor.Value) or Color3.fromRGB(255,255,255)
                end
            else
                AimbotFOVCircle.Visible = false
            end
            AimbotSnapLine.Visible = false

            if Toggles.bxw_aimbot_enable and Toggles.bxw_aimbot_enable.Value then
                local activation = (Options.bxw_aim_activation and Options.bxw_aim_activation.Value) or "Hold Right Click"
                if activation == "Always On" or (activation == "Hold Right Click" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
                    local bestPlr = nil
                    local bestScore = math.huge
                    local myRoot = getRootPart()
                    if myRoot then
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer then
                                local char = plr.Character
                                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    local rootCandidate = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                                    if rootCandidate then
                                        local skip = false
                                        if Toggles.bxw_aim_teamcheck and Toggles.bxw_aim_teamcheck.Value then
                                            if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then skip = true end
                                        end
                                        if not skip then
                                            local aimPartName = (Options.bxw_aim_part and Options.bxw_aim_part.Value) or "Head"
                                            local selectedPart = nil
                                            if aimPartName == "Head" then selectedPart = char:FindFirstChild("Head")
                                            elseif aimPartName == "UpperTorso" then selectedPart = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
                                            elseif aimPartName == "Torso" then selectedPart = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                                            elseif aimPartName == "HumanoidRootPart" then selectedPart = rootCandidate
                                            elseif aimPartName == "Closest" then
                                                local candidatesClosest = {}
                                                local function addClosest(name) local p = char:FindFirstChild(name) if p then table.insert(candidatesClosest, p) end end
                                                addClosest("Head") addClosest("UpperTorso") addClosest("Torso") addClosest("HumanoidRootPart")
                                                if #candidatesClosest > 0 then
                                                    local bestDist = math.huge
                                                    for _, p in ipairs(candidatesClosest) do
                                                        local sp, onScreen = cam:WorldToViewportPoint(p.Position)
                                                        if onScreen then
                                                            local dist = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                                                            if dist < bestDist then bestDist = dist selectedPart = p end
                                                        end
                                                    end
                                                end
                                            elseif aimPartName == "Random" then
                                                local parts = {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
                                                selectedPart = char:FindFirstChild(parts[math.random(1, #parts)])
                                            end
                                            if not selectedPart then selectedPart = rootCandidate end

                                            if selectedPart then
                                                local screenPos, onScreen = cam:WorldToViewportPoint(selectedPart.Position)
                                                if onScreen then
                                                    local fovLimit = ((Options.bxw_aim_fov and Options.bxw_aim_fov.Value) or 10) * 15
                                                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mouseLoc).Magnitude
                                                    if screenDist <= fovLimit then
                                                        local skipVis = false
                                                        if Toggles.bxw_aim_visibility and Toggles.bxw_aim_visibility.Value then
                                                            local rp = RaycastParams.new()
                                                            rp.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                                            rp.FilterType = Enum.RaycastFilterType.Blacklist
                                                            local dir = (selectedPart.Position - cam.CFrame.Position)
                                                            local hit = Workspace:Raycast(cam.CFrame.Position, dir, rp)
                                                            if hit and hit.Instance and not hit.Instance:IsDescendantOf(char) then skipVis = true end
                                                        end

                                                        if not skipVis then
                                                            local score = screenDist
                                                            
                                                            -- Smart Aim Logic Calculation
                                                            if UseSmartAimLogic.Value then
                                                                local distSelf = (rootCandidate.Position - myRoot.Position).Magnitude
                                                                -- Formula: MouseDist (Priority) + PlayerDist (Secondary) + LowHP (Tertiary)
                                                                score = (screenDist * 1.5) + (distSelf * 0.5) + (hum.Health * 0.1)
                                                            else
                                                                local mode = (Options.bxw_aim_targetmode and Options.bxw_aim_targetmode.Value) or "Closest To Crosshair"
                                                                if mode == "Closest Distance" then
                                                                    score = (rootCandidate.Position - myRoot.Position).Magnitude
                                                                elseif mode == "Lowest Health" then
                                                                    score = hum.Health
                                                                end
                                                            end

                                                            if score < bestScore then
                                                                bestScore = score
                                                                bestPlr = { player = plr, part = selectedPart, root = rootCandidate, char = char, hum = hum, screenPos = screenPos }
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if bestPlr then
                        local globalChance = (Options.bxw_aim_hitchance and Options.bxw_aim_hitchance.Value) or 100
                        if math.random(0, 100) <= globalChance then
                            local aimPart = bestPlr.part
                            local camPos = cam.CFrame.Position
                            if Toggles.bxw_aim_smart and Toggles.bxw_aim_smart.Value then
                                local rootPart = bestPlr.root
                                local headPart = bestPlr.char and bestPlr.char:FindFirstChild("Head")
                                if rootPart and headPart then
                                    local rp = RaycastParams.new() rp.FilterDescendantsInstances = { bestPlr.char, LocalPlayer.Character } rp.FilterType = Enum.RaycastFilterType.Blacklist
                                    local hitRoot = Workspace:Raycast(camPos, rootPart.Position - camPos, rp)
                                    local hitHead = Workspace:Raycast(camPos, headPart.Position - camPos, rp)
                                    if hitRoot and not hitHead then aimPart = headPart end
                                end
                            end
                            local predictedPos = aimPart.Position
                            if Toggles.bxw_aim_pred and Toggles.bxw_aim_pred.Value then
                                local vel = aimPart.AssemblyLinearVelocity or aimPart.Velocity or Vector3.zero
                                predictedPos = predictedPos + vel * ((Options.bxw_aim_predfactor and Options.bxw_aim_predfactor.Value) or 0)
                            end
                            local aimDir = (predictedPos - camPos).Unit
                            if Options.bxw_aim_method and Options.bxw_aim_method.Value == "MouseDelta" then
                                local delta = (Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y) - mouseLoc)
                                local smooth = (Options.bxw_aim_smooth and Options.bxw_aim_smooth.Value) or 0.1
                                delta = delta * ((smooth or 0) / 10)
                                pcall(function() mousemoverel(delta.X, delta.Y) end)
                            else
                                local newCFrame = CFrame.new(camPos, camPos + aimDir)
                                local smooth = (Options.bxw_aim_smooth and Options.bxw_aim_smooth.Value) or 0.1
                                cam.CFrame = cam.CFrame:Lerp(newCFrame, ((smooth or 0) / 10))
                            end
                            if Toggles.bxw_aim_snapline and Toggles.bxw_aim_snapline.Value then
                                AimbotSnapLine.Visible = true
                                AimbotSnapLine.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                                AimbotSnapLine.To = Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y)
                                AimbotSnapLine.Color = (Options.bxw_aim_snapcolor and Options.bxw_aim_snapcolor.Value) or Color3.fromRGB(255,0,0)
                                AimbotSnapLine.Thickness = (Options.bxw_aim_snapthick and Options.bxw_aim_snapthick.Value) or 1
                            end
                            if Toggles.bxw_triggerbot and Toggles.bxw_triggerbot.Value then
                                local tFov = ((Options.bxw_trigger_fov and Options.bxw_trigger_fov.Value) or 10) * 15
                                local tDist = (Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y) - mouseLoc).Magnitude
                                if tDist <= tFov then
                                    local fireMode = (Options.bxw_trigger_firing and Options.bxw_trigger_firing.Value) or "Single"
                                    local delayTime = (Options.bxw_trigger_delay and Options.bxw_trigger_delay.Value) or 0
                                    task.spawn(function()
                                        task.wait(delayTime)
                                        if fireMode == "Single" then performClick()
                                        elseif fireMode == "Burst" then for i=1,3 do performClick() task.wait(0.05) end
                                        elseif fireMode == "Auto" then performClick() end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end))
    end

    ------------------------------------------------
    -- 4.5 Misc & System Tab (FIXED GRAPHICS & NEW FEATURES)
    ------------------------------------------------
    do
        local MiscTab = Tabs.Misc
        local MiscLeft  = MiscTab:AddLeftGroupbox("Game Tools", "tool")
        local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")

        -- [NEW FEATURE] Auto Interact (Proximity Prompt Aura)
        local autoInteractConn
        local AutoInteractToggle = MiscLeft:AddToggle("bxw_auto_interact", { Text = "Auto Interact (E)", Default = false, Tooltip = "Automatically fires proximity prompts" })
        AutoInteractToggle:OnChanged(function(state)
            if state then
                autoInteractConn = AddConnection(RunService.Stepped:Connect(function()
                    if getRootPart() then
                        for _, prompt in ipairs(Workspace:GetDescendants()) do
                            if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                                local promptRoot = prompt.Parent and (prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChild("HumanoidRootPart"))
                                if promptRoot and (promptRoot.Position - getRootPart().Position).Magnitude <= prompt.MaxActivationDistance then
                                    fireproximityprompt(prompt)
                                end
                            end
                        end
                    end
                end))
            else
                if autoInteractConn then autoInteractConn:Disconnect() autoInteractConn = nil end
            end
            NotifyAction("Auto Interact", state)
        end)

        -- [FIX] Graphics & Visuals Section
        local GfxBox = MiscTab:AddRightGroupbox("Graphics & Visuals", "monitor")
        
        GfxBox:AddButton("Smart Potato Mode (FPS)", function()
            Library:Notify("Boosting FPS... Please wait", 3)
            task.spawn(function()
                -- 1. Lighting Optimization
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 9e9
                Lighting.Brightness = 2
                if setscriptable then setscriptable(Lighting, "Technology", true) end
                pcall(function() Lighting.Technology = Enum.Technology.Compatibility end)
                
                -- 2. Terrain Optimization
                local terrain = Workspace:FindFirstChildOfClass("Terrain")
                if terrain then
                    terrain.WaterWaveSize = 0
                    terrain.WaterReflectance = 0
                    terrain.WaterTransparency = 0
                    terrain.Decoration = false
                end

                -- 3. Texture/Decal Removal (Fast Scan)
                for _, v in pairs(Workspace:GetDescendants()) do
                    if v:IsA("Texture") or v:IsA("Decal") then
                        v:Destroy()
                    elseif v:IsA("BasePart") then
                        v.Material = Enum.Material.SmoothPlastic
                        v.Reflectance = 0
                        v.CastShadow = false
                    end
                end
                Library:Notify("Smart Potato Mode Applied!", 2)
            end)
        end)

        GfxBox:AddButton("Cinematic Mode (Beautiful)", function()
            task.spawn(function()
                Lighting.GlobalShadows = true
                Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 120)
                Lighting.Ambient = Color3.fromRGB(120, 120, 120)
                
                -- Check existing to avoid stacking blinding lights
                local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
                if not cc then cc = Instance.new("ColorCorrectionEffect", Lighting) end
                cc.Saturation = 0.2
                cc.Contrast = 0.1
                
                local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
                if not bloom then bloom = Instance.new("BloomEffect", Lighting) end
                bloom.Intensity = 0.4
                bloom.Size = 24
                
                local sun = Lighting:FindFirstChildOfClass("SunRaysEffect")
                if not sun then sun = Instance.new("SunRaysEffect", Lighting) end
                
                Library:Notify("Cinematic Mode Applied!", 2)
            end)
        end)

        -- [NEW FEATURE] Night Vision
        local NightVisionToggle = GfxBox:AddToggle("bxw_nightvision", { Text = "Night Vision", Default = false })
        local oldAmbient, oldOutdoor
        NightVisionToggle:OnChanged(function(state)
            if state then
                oldAmbient = Lighting.Ambient
                oldOutdoor = Lighting.OutdoorAmbient
                Lighting.Ambient = Color3.fromRGB(0, 255, 0)
                Lighting.OutdoorAmbient = Color3.fromRGB(0, 255, 0)
                Lighting.Brightness = 1
                Lighting.ClockTime = 12
            else
                if oldAmbient then Lighting.Ambient = oldAmbient end
                if oldOutdoor then Lighting.OutdoorAmbient = oldOutdoor end
            end
            NotifyAction("Night Vision", state)
        end)

        -- [NEW FEATURE] Fullbright Loop
        local fbConn
        local FullbrightToggle = GfxBox:AddToggle("bxw_fullbright", { Text = "Fullbright (Loop)", Default = false, Tooltip = "Loops brightness to max" })
        FullbrightToggle:OnChanged(function(state)
            if state then
                fbConn = AddConnection(RunService.RenderStepped:Connect(function()
                    Lighting.Brightness = 2
                    Lighting.ClockTime = 12
                    Lighting.FogEnd = 100000
                    Lighting.GlobalShadows = false
                    Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                end))
            else
                if fbConn then fbConn:Disconnect() fbConn = nil end
            end
            NotifyAction("Fullbright", state)
        end)

        local TimeSlider = GfxBox:AddSlider("bxw_time", { Text = "Time of Day", Default = 12, Min = 0, Max = 24, Rounding = 1, Callback = function(v) Lighting.ClockTime = v end })
        TimeSlider:SetDisabled(true)
        -- Unlock time slider if fullbright is OFF
        FullbrightToggle:OnChanged(function(state) TimeSlider:SetDisabled(state) if state then NotifyAction("Fullbright", true) else NotifyAction("Fullbright", false) end end)

        local ShadowToggle = GfxBox:AddToggle("bxw_shadows", { Text = "Shadows", Default = Lighting.GlobalShadows })
        ShadowToggle:OnChanged(function(state) Lighting.GlobalShadows = state NotifyAction("Shadows", state) end)

        local AntiRejoinToggle = MiscLeft:AddToggle("bxw_antirejoin", { Text = "Auto Rejoin on Kick", Default = false })
        local lastKick = 0
        AddConnection(GuiService.ErrorMessageChanged:Connect(function()
            if AntiRejoinToggle.Value then
                if tick() - lastKick > 5 then
                    lastKick = tick()
                    warn("Kick detected. Rejoining...")
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end
            end
        end))
        MiscLeft:AddButton("Force Rejoin", function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)

        local antiAfkConn
        local AntiAfkToggle = MiscLeft:AddToggle("bxw_anti_afk", { Text = "Anti-AFK", Default = true })
        AntiAfkToggle:OnChanged(function(state)
            if state then
                if antiAfkConn then antiAfkConn:Disconnect() end
                antiAfkConn = AddConnection(LocalPlayer.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end))
            else
                if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
            end
            NotifyAction("Anti-AFK", state)
        end)

        local defaultGravity = Workspace.Gravity
        local GravitySlider = MiscRight:AddSlider("bxw_gravity", { Text = "Gravity", Default = defaultGravity, Min = 0, Max = 300, Rounding = 0, Compact = false, Callback = function(value) Workspace.Gravity = value end })
        MiscRight:AddButton("Reset Gravity", function() Workspace.Gravity = defaultGravity GravitySlider:SetValue(defaultGravity) end)
        
        local NoFogToggle = MiscRight:AddToggle("bxw_nofog", { Text = "No Fog", Default = false })
        NoFogToggle:OnChanged(function(state)
            if state then Lighting.FogEnd = 1e10 else Lighting.FogEnd = 1000 end
            NotifyAction("No Fog", state)
        end)
        local defaultBrightness = game.Lighting.Brightness
        local BrightnessSlider = MiscRight:AddSlider("bxw_brightness", { Text = "Brightness", Default = defaultBrightness, Min = 0, Max = 10, Rounding = 1, Compact = false, Callback = function(value) game.Lighting.Brightness = value end })
        MiscRight:AddButton("Reset Brightness", function() game.Lighting.Brightness = defaultBrightness BrightnessSlider:SetValue(defaultBrightness) end)
        local AmbientColorLabel = MiscRight:AddLabel("Ambient Color")
        AmbientColorLabel:AddColorPicker("bxw_ambient_color", { Default = game.Lighting.Ambient })
        local AmbientOpt = Options.bxw_ambient_color
        if AmbientOpt and typeof(AmbientOpt.OnChanged) == "function" then AmbientOpt:OnChanged(function(col) game.Lighting.Ambient = col end) end

        MiscLeft:AddDivider()
        MiscLeft:AddLabel("Fun & Utility")
        local spinConn
        local SpinToggle = MiscLeft:AddToggle("bxw_spinbot", { Text = "SpinBot", Default = false })
        local SpinSpeedSlider = MiscLeft:AddSlider("bxw_spin_speed", { Text = "Spin Speed", Default = 5, Min = 0.1, Max = 10, Rounding = 1, Compact = false })
        local ReverseSpinToggle = MiscLeft:AddToggle("bxw_spin_reverse", { Text = "Reverse Spin", Default = false })
        
        -- Lock Spin settings
        SpinSpeedSlider:SetDisabled(true)
        SpinToggle:OnChanged(function(state)
            SpinSpeedSlider:SetDisabled(not state)
            if state then
                if spinConn then spinConn:Disconnect() end
                spinConn = AddConnection(RunService.RenderStepped:Connect(function(dt)
                    local root = getRootPart()
                    if root then
                        local dir = ReverseSpinToggle.Value and -1 or 1
                        local step = (SpinSpeedSlider.Value or 5) * dir * dt * math.pi
                        root.CFrame = root.CFrame * CFrame.Angles(0, step, 0)
                    end
                end))
            else
                if spinConn then spinConn:Disconnect() spinConn = nil end
            end
            NotifyAction("SpinBot", state)
        end)

        local antiFlingConn
        local AntiFlingToggle2 = MiscLeft:AddToggle("bxw_antifling", { Text = "Anti Fling", Default = false })
        AntiFlingToggle2:OnChanged(function(state)
            if state then
                if antiFlingConn then antiFlingConn:Disconnect() end
                antiFlingConn = AddConnection(RunService.Stepped:Connect(function()
                    local root = getRootPart()
                    if root then
                        if root.AssemblyLinearVelocity.Magnitude > 80 then root.AssemblyLinearVelocity = Vector3.zero end
                        if root.AssemblyAngularVelocity.Magnitude > 80 then root.AssemblyAngularVelocity = Vector3.zero end
                    end
                end))
            else
                if antiFlingConn then antiFlingConn:Disconnect() antiFlingConn = nil end
            end
            NotifyAction("Anti-Fling", state)
        end)

        local jerkTool
        local JerkToggle = MiscLeft:AddToggle("bxw_jerktool", { Text = "Jerk Tool", Default = false })
        JerkToggle:OnChanged(function(state)
            if state then
                if jerkTool then jerkTool:Destroy() end
                jerkTool = Instance.new("Tool") jerkTool.Name = "JerkTool" jerkTool.RequiresHandle = false
                jerkTool.Activated:Connect(function()
                    local mouse = LocalPlayer:GetMouse()
                    local target = mouse.Target
                    if target and target:IsA("BasePart") then
                        local vel = Instance.new("BodyVelocity") vel.Velocity = (mouse.Hit.LookVector) * 60 vel.MaxForce = Vector3.new(1e5, 1e5, 1e5) vel.Parent = target game.Debris:AddItem(vel, 0.25)
                    end
                end)
                jerkTool.Parent = LocalPlayer.Backpack Library:Notify("Jerk Tool added", 2)
            else
                if jerkTool then jerkTool:Destroy() jerkTool = nil end
            end
            NotifyAction("Jerk Tool", state)
        end)

        MiscLeft:AddButton("BTools", function()
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            if not backpack then Library:Notify("Backpack not found", 2) return end
            local function addBin(binType) local bin = Instance.new("HopperBin") bin.BinType = binType bin.Parent = backpack end
            addBin(Enum.BinType.Clone) addBin(Enum.BinType.Hammer) addBin(Enum.BinType.Grab) Library:Notify("BTools added", 2)
        end)
        MiscLeft:AddButton("Teleport Tool", function()
            local tool = Instance.new("Tool") tool.Name = "TeleportTool" tool.RequiresHandle = false
            tool.Activated:Connect(function()
                local mouse = LocalPlayer:GetMouse() local targetPos = mouse.Hit and mouse.Hit.Position
                if targetPos then local root = getRootPart() if root then root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0)) end end
            end)
            tool.Parent = LocalPlayer.Backpack Library:Notify("Teleport Tool added", 2)
        end)
        MiscLeft:AddButton("Server Hop", function() pcall(function() TeleportService:Teleport(game.PlaceId) end) end)
        MiscLeft:AddButton("Respawn Character", function() pcall(function() LocalPlayer:LoadCharacter() end) end)
    end

    ------------------------------------------------
    -- 4.6 Settings Tab
    ------------------------------------------------
    do
        local SettingsTab = Tabs.Settings
        local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
        
        -- Force Notify Toggle
        MenuGroup:AddToggle("ForceNotify", { Text = "Force Notification", Default = true, Tooltip = "Notify when features are toggled" })

        MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end })
        MenuGroup:AddToggle("ShowCustomCursor", { Text = "Custom Cursor", Default = true, Callback = function(Value) Library.ShowCustomCursor = Value end })
        MenuGroup:AddDropdown("NotificationSide", { Values = { "Left", "Right" }, Default = "Right", Text = "Notification Side", Callback = function(Value) Library:SetNotifySide(Value) end })
        MenuGroup:AddDropdown("DPIDropdown", { Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" }, Default = "100%", Text = "DPI Scale", Callback = function(Value) Value = tostring(Value):gsub("%%", "") local DPI = tonumber(Value) if DPI then Library:SetDPIScale(DPI) end end })
        MenuGroup:AddDivider()
        MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
        MenuGroup:AddButton("Unload UI", function() pcall(function() Library:Unload() end) end)
        MenuGroup:AddButton("Reload UI", function() pcall(function() Library:Unload() end) pcall(function() warn("[BxB] UI unloaded. Please re-execute.") end) end)
        Library.ToggleKeybind = Options.MenuKeybind
        ThemeManager:SetLibrary(Library) SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings() SaveManager:SetIgnoreIndexes({ "MenuKeybind", "Key Info", "Game Info" })
        ThemeManager:SetFolder("BxB.Ware_Setting") SaveManager:SetFolder("BxB.Ware_Setting")
        SaveManager:BuildConfigSection(SettingsTab) ThemeManager:ApplyToTab(SettingsTab)
        SaveManager:LoadAutoloadConfig()
    end

    ------------------------------------------------
    -- [FEATURE] Watermark
    ------------------------------------------------
    pcall(function()
        Library:SetWatermarkVisibility(true)
        -- Update Watermark loop
        AddConnection(RunService.RenderStepped:Connect(function()
            local ping = 0
            pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
            local fps = math.floor(1 / math.max(RunService.RenderStepped:Wait(), 0.001))
            local timeStr = os.date("%H:%M:%S")
            Library:SetWatermark(string.format("BxB.ware | Universal | FPS: %d | Ping: %d ms | %s", fps, ping, timeStr))
        end))
    end)


    ------------------------------------------------
    -- 4.7 Clean Up
    ------------------------------------------------
    if Library and type(Library.OnUnload) == "function" then
        Library:OnUnload(function()
            -- 1. Disconnect Connections
            for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
            
            -- 2. Clear Drawings (Accessing the scope-elevated variable)
            if espDrawings then
                for _, plrData in pairs(espDrawings) do
                    for _, item in pairs(plrData) do
                        if type(item) == "table" then for _, d in pairs(item) do pcall(function() d:Remove() end) end
                        elseif typeof(item) == "Instance" then pcall(function() item:Destroy() end)
                        elseif item.Remove then pcall(function() item:Remove() end) end
                    end
                end
            end
            
            -- 3. Clear Crosshair & FOV
            if crosshairLines then pcall(function() crosshairLines.h:Remove() crosshairLines.v:Remove() end) end
            if AimbotFOVCircle then pcall(function() AimbotFOVCircle:Remove() end) end
            if AimbotSnapLine then pcall(function() AimbotSnapLine:Remove() end) end
        end)
    end
end

--====================================================
-- 5. Return function
--====================================================
return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then
        warn("[MainHub] Fatal error:", err)
    end
end
