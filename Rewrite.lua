--====================================================
-- 0. Services
--====================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService") -- เพิ่มบรรทัดนี้

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

local function RoleAtLeast(haveRole, needRole)
    local have  = NormalizeRole(haveRole)
    local need  = NormalizeRole(needRole)
    local hPrio = RolePriority[have] or 0
    local nPrio = RolePriority[need] or 999
    return hPrio >= nPrio
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

    -- normalize role
    keydata.role = NormalizeRole(keydata.role)

    ---------------------------------------------
    -- 4.2 โหลด Obsidian Library + Theme/Save
    --     (บล็อคนี้คือโครง noedit.lua ที่ห้ามเปลี่ยนโครงสร้าง)
    ---------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    local Library = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    -- 1) สร้าง Window (ตาม noedit.lua)
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

    -- 2) Tabs (ตาม noedit.lua)
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

    ------------------------------------------------
    -- 4.3 TAB 1: Info [Key / Game]
    ------------------------------------------------

    local InfoTab = Tabs.Info

    --=== 4.3.1 Key Info (Left Groupbox) =========================
    local KeyBox = InfoTab:AddLeftGroupbox("Key Info", "key-round")

    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()

    -- mask key นิดหน่อย
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

    local createdAtText = formatUnixTime(keydata.timestamp)
    local expireTs      = tonumber(keydata.expire) or 0

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))

    -- Tier: ตอนนี้ยังไม่มีใน keydata, ใช้ role แทน (คุณจะมา map เพิ่มทีหลังก็ได้)
    local tierText = string.upper(keydata.role or "free")
    safeRichLabel(KeyBox, string.format("<b>Tier:</b> %s", tierText))

    safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", noteText))
    safeRichLabel(KeyBox, string.format("<b>Created at:</b> %s", createdAtText))

    local ExpireLabel   = safeRichLabel(KeyBox, string.format("<b>Expire:</b> %s", formatUnixTime(expireTs)))
    local TimeLeftLabel = safeRichLabel(KeyBox, string.format("<b>Time left:</b> %s", formatTimeLeft(expireTs)))

    -- อัปเดต Expire / Time left แบบ realtime (ทุก ~1 วินาที)
    do
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 1 then
                return
            end
            acc = 0

            local nowExpire = tonumber(keydata.expire) or expireTs
            local expireStr = formatUnixTime(nowExpire)
            local leftStr   = formatTimeLeft(nowExpire)

            if ExpireLabel and ExpireLabel.TextLabel then
                ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", expireStr)
            end

            if TimeLeftLabel and TimeLeftLabel.TextLabel then
                TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", leftStr)
            end
        end))
    end

    --=== 4.3.2 Game Info (Right Groupbox) =======================
    local GameBox = InfoTab:AddRightGroupbox("Game Info", "info")

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

    -- ดึงชื่อเกมจาก MarketplaceService (ครั้งเดียว)
    task.spawn(function()
        local gameName = "Unknown Place"
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, placeId)
        if ok and info and info.Name then
            gameName = info.Name
        end

        if GameNameLabel and GameNameLabel.TextLabel then
            GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", gameName)
        end
    end)

    -- ฟังก์ชันอัปเดตจำนวนผู้เล่น
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

    -- FPS / Ping / Memory + ServerTime อัปเดตทุก ~0.5s
    do
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 0.5 then
                return
            end
            acc = 0

            local fps = math.floor(1 / math.max(dt, 1/240))

            local pingMs = 0
            local memMb  = 0

            -- Ping ms
            local okPing, pingItem = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]
            end)

            if okPing and pingItem and pingItem.GetValue then
                local v = pingItem:GetValue()
                if typeof(v) == "number" then
                    pingMs = math.floor(v)
                end
            end

            -- Memory
            local okMem, mem = pcall(function()
                return Stats:GetTotalMemoryUsageMb()
            end)
            if okMem and type(mem) == "number" then
                memMb = math.floor(mem)
            end

            if PerfLabel and PerfLabel.TextLabel then
                PerfLabel.TextLabel.Text = string.format(
                    "<b>Perf:</b> FPS: %d | Ping: %d ms | Mem: %d MB",
                    fps, pingMs, memMb
                )
            end

            if ServerTimeLabel and ServerTimeLabel.TextLabel then
                ServerTimeLabel.TextLabel.Text = string.format(
                    "<b>Server Time:</b> %s",
                    os.date("%H:%M:%S")
                )
            end
        end))
    end

    --------------------------------------------------------
    -- 2. PLAYER TAB (Movement / Teleport / View)
    --------------------------------------------------------
   local PlayerTab = Tabs.Player

    ------------------------------------------------
    -- 2.1 Left: Player Movement
    ------------------------------------------------
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    -- WalkSpeed + Toggle
    local defaultWalkSpeed = 16
    local walkSpeedEnabled = false

    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", {
        Text = "Enable WalkSpeed",
        Default = false,
        Tooltip = "Enable custom WalkSpeed",
    })

    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", {
        Text = "WalkSpeed",
        Default = defaultWalkSpeed,
        Min = 0,
        Max = 120,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            if not walkSpeedEnabled then
                return
            end
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = value
            end
        end,
    })

    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state

        if WalkSpeedSlider.SetDisabled then
            WalkSpeedSlider:SetDisabled(not state)
        end

        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = state and WalkSpeedSlider.Value or defaultWalkSpeed
        end
    end)

    MoveBox:AddButton("Reset WalkSpeed", function()
        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = defaultWalkSpeed
        end
        WalkSpeedSlider:SetValue(defaultWalkSpeed)
        WalkSpeedToggle:SetValue(false)
    end)

    -- JumpPower + Toggle
    local defaultJumpPower = 50
    local jumpPowerEnabled = false

    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", {
        Text = "Enable JumpPower",
        Default = false,
        Tooltip = "Enable custom JumpPower",
    })

    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", {
        Text = "JumpPower",
        Default = defaultJumpPower,
        Min = 0,
        Max = 200,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            if not jumpPowerEnabled then
                return
            end

            local hum = getHumanoid()
            if hum then
                pcall(function()
                    hum.UseJumpPower = true
                end)
                hum.JumpPower = value
            end
        end,
    })

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state

        if JumpPowerSlider.SetDisabled then
            JumpPowerSlider:SetDisabled(not state)
        end

        local hum = getHumanoid()
        if hum then
            pcall(function()
                hum.UseJumpPower = true
            end)
            hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower
        end
    end)

    MoveBox:AddButton("Reset JumpPower", function()
        local hum = getHumanoid()
        if hum then
            pcall(function()
                hum.UseJumpPower = true
            end)
            hum.JumpPower = defaultJumpPower
        end
        JumpPowerSlider:SetValue(defaultJumpPower)
        JumpPowerToggle:SetValue(false)
    end)

    MoveBox:AddDivider()

    -- Infinite Jump
    local infJumpConn
    local InfJumpToggle = MoveBox:AddToggle("bxw_infjump", {
        Text = "Infinite Jump",
        Default = false,
        Tooltip = "Allow you to jump in the air forever",
    })

    InfJumpToggle:OnChanged(function(state)
        if state then
            if infJumpConn then
                infJumpConn:Disconnect()
            end
            infJumpConn = AddConnection(UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid()
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end))
        else
            if infJumpConn then
                infJumpConn:Disconnect()
                infJumpConn = nil
            end
        end
    end)

    -- Smooth Fly (BodyVelocity + BodyGyro)
    local flyConn
    local flyBV, flyBG
    local flyEnabled = false
    local flySpeed = 60

    local FlyToggle = MoveBox:AddToggle("bxw_fly", {
        Text = "Fly (Smooth)",
        Default = false,
        Tooltip = "Smooth fly with locked rotation",
    })

    FlyToggle:OnChanged(function(state)
        flyEnabled = state

        local char = getCharacter()
        local root = getRootPart()
        local hum  = getHumanoid()
        local cam  = Workspace.CurrentCamera

        if not state then
            if flyConn then
                flyConn:Disconnect()
                flyConn = nil
            end

            if flyBV then
                flyBV:Destroy()
                flyBV = nil
            end

            if flyBG then
                flyBG:Destroy()
                flyBG = nil
            end

            if hum then
                hum.PlatformStand = false
            end

            return
        end

        if not (root and hum and cam) then
            if Library and Library.Notify then
                Library:Notify("Cannot start fly: character not loaded", 3)
            end
            FlyToggle:SetValue(false)
            return
        end

        hum.PlatformStand = true

        -- ตัวดันความเร็ว
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        flyBV.Velocity = Vector3.zero
        flyBV.P = 9e4
        flyBV.Parent = root

        -- ตัวล็อคทิศ/หมุน
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyBG.CFrame = root.CFrame
        flyBG.P = 9e4
        flyBG.Parent = root

        if flyConn then
            flyConn:Disconnect()
        end

        flyConn = AddConnection(RunService.RenderStepped:Connect(function()
            if not flyEnabled then
                return
            end

            local root = getRootPart()
            local hum  = getHumanoid()
            local cam  = Workspace.CurrentCamera
            if not (root and hum and cam and flyBV and flyBG) then
                return
            end

            local moveDir = Vector3.new(0, 0, 0)

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveDir = moveDir + cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveDir = moveDir - cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveDir = moveDir - cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveDir = moveDir + cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveDir = moveDir + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                moveDir = moveDir - Vector3.new(0, 1, 0)
            end

            if moveDir.Magnitude > 0 then
                moveDir = moveDir.Unit
                flyBV.Velocity = moveDir * flySpeed
            else
                flyBV.Velocity = Vector3.zero
            end

            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
    end)

    -- Noclip
    local noclipConn
    local NoclipToggle = MoveBox:AddToggle("bxw_noclip", {
        Text = "Noclip",
        Default = false,
        Tooltip = "Walk through walls",
    })

    NoclipToggle:OnChanged(function(state)
        if not state then
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end

            local char = getCharacter()
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
                end
            end
            return
        end

        if noclipConn then
            noclipConn:Disconnect()
        end

        noclipConn = AddConnection(RunService.Stepped:Connect(function()
            local char = getCharacter()
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end))
    end)

    ------------------------------------------------
    -- 2.2 Right: Teleport / Utility
    ------------------------------------------------
    local UtilBox = PlayerTab:AddRightGroupbox("Teleport / Utility", "map")

    local playerNames = {}
    local function refreshPlayerList()
        table.clear(playerNames)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(playerNames, plr.Name)
            end
        end
    end

    refreshPlayerList()

    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", {
        Text = "Teleport to Player",
        Values = playerNames,
        Default = "",
        Multi = false,
        AllowNull = true,
        Tooltip = "Select a player to teleport to",
    })

    UtilBox:AddButton("Refresh Player List", function()
        refreshPlayerList()
        TeleportDropdown:SetValues(playerNames)
    end)

    UtilBox:AddButton("Teleport", function()
        local targetName = TeleportDropdown.Value
        if not targetName or targetName == "" then
            Library:Notify("Select player first", 2)
            return
        end

        local target = Players:FindFirstChild(targetName)
        local root = getRootPart()
        if not target or not root then
            Library:Notify("Target/Your character not found", 2)
            return
        end

        local tChar = target.Character
        local tRoot = tChar and (tChar:FindFirstChild("HumanoidRootPart") or tChar:FindFirstChild("Torso"))
        if not tRoot then
            Library:Notify("Target has no root part", 2)
            return
        end

        root.CFrame = tRoot.CFrame + Vector3.new(0, 3, 0)
    end)

    UtilBox:AddDivider()

    -- Spectate: toggle แทนปุ่ม start/stop
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", {
        Text = "Spectate Target",
        Values = playerNames,
        Default = "",
        Multi = false,
        AllowNull = true,
        Tooltip = "Select player to spectate",
    })

    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", {
        Text = "Spectate Player",
        Default = false,
        Tooltip = "Toggle camera spectate",
    })

    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if not cam then
            return
        end

        if state then
            local name = SpectateDropdown.Value
            if not name or name == "" then
                Library:Notify("Select player to spectate", 2)
                SpectateToggle:SetValue(false)
                return
            end

            local target = Players:FindFirstChild(name)
            if not target or not target.Character then
                Library:Notify("Target not found", 2)
                SpectateToggle:SetValue(false)
                return
            end

            local hum = target.Character:FindFirstChildOfClass("Humanoid")
            if not hum then
                Library:Notify("Target humanoid not found", 2)
                SpectateToggle:SetValue(false)
                return
            end

            cam.CameraSubject = hum
        else
            local hum = getHumanoid()
            if hum then
                cam.CameraSubject = hum
            end
        end
    end)

    UtilBox:AddDivider()

    -- FOV Changer
    local camera = Workspace.CurrentCamera
    local defaultFov = camera and camera.FieldOfView or 70

    local FovSlider = UtilBox:AddSlider("bxw_fov", {
        Text = "FOV",
        Default = defaultFov,
        Min = 40,
        Max = 120,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            local cam = Workspace.CurrentCamera
            if cam then
                cam.FieldOfView = value
            end
        end,
    })

    UtilBox:AddButton("Reset FOV", function()
        local cam = Workspace.CurrentCamera
        if cam then
            cam.FieldOfView = defaultFov
        end
        FovSlider:SetValue(defaultFov)
    end)

    UtilBox:AddDivider()
    UtilBox:AddLabel("More utilities will be added later.")

    --------------------------------------------------------
    -- 3. ESP TAB (ESP & Visuals)
    --------------------------------------------------------
    -- Set up local references for Options and Toggles to simplify
    local Options = Library.Options
    local Toggles = Library.Toggles

    local EspTab = Tabs.ESP

    -- Groupboxes: left for toggles/features, right for settings
    local EspFeatureBox  = EspTab:AddLeftGroupbox("ESP Features", "eye")
    local EspSettingBox  = EspTab:AddRightGroupbox("ESP Settings", "sliders")

    -- #region ESP Controls
    -- Master enable toggle for the entire ESP system
    local EspEnabledToggle = EspFeatureBox:AddToggle("bxw_esp_enable", {
        Text    = "Enable ESP",
        Default = false,
        Tooltip = "Master switch for all ESP features",
    })

    -- Box / Corner toggle
    local BoxToggle = EspFeatureBox:AddToggle("bxw_esp_box", {
        Text    = "Box ESP",
        Default = true,
        Tooltip = "Draw boxes around players",
    })

    local BoxTypeDropdown = EspFeatureBox:AddDropdown("bxw_esp_box_type", {
        Text    = "Box Style",
        Values  = {"Box", "Corner"},
        Default = "Box",
        Multi   = false,
        Tooltip = "Full box or only corners",
    })

    local ChamsToggle = EspFeatureBox:AddToggle("bxw_esp_chams", {
        Text    = "Chams",
        Default = false,
        Tooltip = "Highlight players with a colored overlay",
    })

    local SkeletonToggle = EspFeatureBox:AddToggle("bxw_esp_skeleton", {
        Text    = "Skeleton",
        Default = false,
        Tooltip = "Draw bone lines between limbs",
    })

    local HealthToggle = EspFeatureBox:AddToggle("bxw_esp_healthbar", {
        Text    = "Health Bar",
        Default = false,
        Tooltip = "Draw a health bar next to the box",
    })

    local NameToggle = EspFeatureBox:AddToggle("bxw_esp_nametag", {
        Text    = "Name Tag",
        Default = true,
        Tooltip = "Show player name above their head",
    })

    local DistanceToggle = EspFeatureBox:AddToggle("bxw_esp_distance", {
        Text    = "Distance",
        Default = false,
        Tooltip = "Show distance to player",
    })

    local TracerToggle = EspFeatureBox:AddToggle("bxw_esp_tracer", {
        Text    = "Tracer",
        Default = false,
        Tooltip = "Draw lines from screen center to players",
    })

    local TeamCheckToggle = EspFeatureBox:AddToggle("bxw_esp_teamcheck", {
        Text    = "Team Check",
        Default = false,
        Tooltip = "Hide ESP for players on the same team",
    })

    local WallCheckToggle = EspFeatureBox:AddToggle("bxw_esp_wallcheck", {
        Text    = "Wall Check",
        Default = false,
        Tooltip = "Change box/tracer color when player is behind a wall",
    })

    EspFeatureBox:AddDivider()

    -- Whitelist dropdown (multi‑select)
    local whitelistNames = {}
    local function refreshWhitelist()
        table.clear(whitelistNames)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(whitelistNames, plr.Name)
            end
        end
    end
    refreshWhitelist()

    local WhitelistDropdown = EspFeatureBox:AddDropdown("bxw_esp_whitelist", {
        Text    = "Whitelist Players",
        Values  = whitelistNames,
        Default = {},
        Multi   = true,
        AllowNull = true,
        Tooltip = "Select players to ignore in ESP",
    })

    EspFeatureBox:AddButton("Refresh List", function()
        refreshWhitelist()
        WhitelistDropdown:SetValues(whitelistNames)
    end)

    -- #endregion ESP Controls

    -- #region ESP Settings
    -- Color pickers and sliders for customizing visuals
    local BoxColorPicker = EspSettingBox:AddColorPicker("bxw_esp_boxcolor", {
        Text = "Box Color",
        Default = Color3.fromRGB(255, 255, 255),
    })

    local TracerColorPicker = EspSettingBox:AddColorPicker("bxw_esp_tracercolor", {
        Text = "Tracer Color",
        Default = Color3.fromRGB(255, 255, 255),
    })

    local NameColorPicker = EspSettingBox:AddColorPicker("bxw_esp_namecolor", {
        Text = "Name Color",
        Default = Color3.fromRGB(255, 255, 255),
    })

    local NameSizeSlider = EspSettingBox:AddSlider("bxw_esp_namesize", {
        Text = "Name Size",
        Default = 13,
        Min = 10,
        Max = 24,
        Rounding = 0,
        Compact = false,
    })

    local DistanceColorPicker = EspSettingBox:AddColorPicker("bxw_esp_distancecolor", {
        Text = "Distance Color",
        Default = Color3.fromRGB(255, 255, 255),
    })

    local DistanceSizeSlider = EspSettingBox:AddSlider("bxw_esp_distancesize", {
        Text = "Distance Size",
        Default = 12,
        Min = 8,
        Max = 20,
        Rounding = 0,
        Compact = false,
    })

    -- #endregion ESP Settings

    --------------------------------------------------------
    -- ESP Logic Implementation
    -- This section sets up drawing objects for each player
    -- and updates them every frame based on toggles/settings.
    --------------------------------------------------------
    -- Table to store drawing objects keyed by player
    local espObjects = {}

    -- Helper: remove ESP objects for a player
    local function removeEspForPlayer(plr)
        local obj = espObjects[plr]
        if not obj then return end
        -- destroy drawings
        if obj.BoxLines then
            for _, line in pairs(obj.BoxLines) do
                if line then line:Remove() end
            end
        end
        if obj.CornerLines then
            for _, line in pairs(obj.CornerLines) do
                if line then line:Remove() end
            end
        end
        if obj.SkeletonLines then
            for _, line in pairs(obj.SkeletonLines) do
                if line then line:Remove() end
            end
        end
        if obj.HealthLines then
            for _, line in pairs(obj.HealthLines) do
                if line then line:Remove() end
            end
        end
        if obj.NameText and obj.NameText.Remove then
            obj.NameText:Remove()
        end
        if obj.DistanceText and obj.DistanceText.Remove then
            obj.DistanceText:Remove()
        end
        if obj.TracerLine and obj.TracerLine.Remove then
            obj.TracerLine:Remove()
        end
        if obj.HighlightInstance and obj.HighlightInstance.Destroy then
            obj.HighlightInstance:Destroy()
        end
        espObjects[plr] = nil
    end

    -- Helper: create ESP drawings for a player
    local function createEspForPlayer(plr)
        if espObjects[plr] then return end
        local obj = {}
        obj.BoxLines    = {}
        obj.CornerLines = {}
        obj.SkeletonLines = {}
        obj.HealthLines = {}

        -- full box (4 lines)
        for i = 1, 4 do
            local ln = Drawing.new("Line")
            ln.Visible = false
            ln.Thickness = 1
            ln.Transparency = 1
            table.insert(obj.BoxLines, ln)
        end
        -- corner lines (8 lines: each corner has horizontal and vertical segments)
        for i = 1, 8 do
            local ln = Drawing.new("Line")
            ln.Visible = false
            ln.Thickness = 1
            ln.Transparency = 1
            table.insert(obj.CornerLines, ln)
        end
        -- skeleton lines (create enough lines, we will map pairs at runtime)
        for i = 1, 15 do
            local ln = Drawing.new("Line")
            ln.Visible = false
            ln.Thickness = 1
            ln.Transparency = 1
            table.insert(obj.SkeletonLines, ln)
        end
        -- health bar lines (outer and inner)
        for i = 1, 2 do
            local ln = Drawing.new("Line")
            ln.Visible = false
            ln.Thickness = 2
            ln.Transparency = 1
            table.insert(obj.HealthLines, ln)
        end
        -- name text
        local nameText = Drawing.new("Text")
        nameText.Visible = false
        nameText.Center = true
        nameText.Outline = true
        nameText.Text = plr.Name
        obj.NameText = nameText
        -- distance text
        local distText = Drawing.new("Text")
        distText.Visible = false
        distText.Center = true
        distText.Outline = true
        obj.DistanceText = distText
        -- tracer line
        local tracer = Drawing.new("Line")
        tracer.Visible = false
        tracer.Thickness = 1
        tracer.Transparency = 1
        obj.TracerLine = tracer
        -- chams highlight (using Highlight instance)
        local highlight = Instance.new("Highlight")
        highlight.Enabled = false
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Parent = game:GetService("CoreGui")
        obj.HighlightInstance = highlight
        espObjects[plr] = obj
    end

    -- Helper: update skeleton line pairs depending on rig type (R6/R15)
    local function getSkeletonPairs(character)
        local pairsList = {}
        if not character then return pairsList end
        -- Determine rig type
        if character:FindFirstChild("UpperTorso") then
            -- R15 skeleton connections
            local function addPair(a, b)
                local aPart = character:FindFirstChild(a)
                local bPart = character:FindFirstChild(b)
                if aPart and bPart then
                    table.insert(pairsList, {aPart, bPart})
                end
            end
            addPair("Head","UpperTorso")
            addPair("UpperTorso","LowerTorso")
            addPair("LowerTorso","LeftUpperLeg")
            addPair("LeftUpperLeg","LeftLowerLeg")
            addPair("LeftLowerLeg","LeftFoot")
            addPair("LowerTorso","RightUpperLeg")
            addPair("RightUpperLeg","RightLowerLeg")
            addPair("RightLowerLeg","RightFoot")
            addPair("UpperTorso","LeftUpperArm")
            addPair("LeftUpperArm","LeftLowerArm")
            addPair("LeftLowerArm","LeftHand")
            addPair("UpperTorso","RightUpperArm")
            addPair("RightUpperArm","RightLowerArm")
            addPair("RightLowerArm","RightHand")
        else
            -- R6 skeleton connections
            local function addPair(a, b)
                local aPart = character:FindFirstChild(a)
                local bPart = character:FindFirstChild(b)
                if aPart and bPart then
                    table.insert(pairsList, {aPart, bPart})
                end
            end
            addPair("Head","Torso")
            addPair("Torso","Left Arm")
            addPair("Torso","Right Arm")
            addPair("Torso","Left Leg")
            addPair("Torso","Right Leg")
        end
        return pairsList
    end

    -- Helper: compute bounding box screen coords
    local function getBoundingBox(character)
        local cframe, size = character:GetBoundingBox()
        local corners = {
            Vector3.new(-size.X/2, -size.Y/2, -size.Z/2),
            Vector3.new(size.X/2, -size.Y/2, -size.Z/2),
            Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
            Vector3.new(size.X/2, size.Y/2, -size.Z/2),
            Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
            Vector3.new(size.X/2, -size.Y/2, size.Z/2),
            Vector3.new(-size.X/2, size.Y/2, size.Z/2),
            Vector3.new(size.X/2, size.Y/2, size.Z/2),
        }
        local camera = Workspace.CurrentCamera
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local onScreen = false
        local points = {}
        for _, offset in ipairs(corners) do
            local worldPoint = (cframe * CFrame.new(offset)).Position
            local screenPoint, visible = camera:WorldToViewportPoint(worldPoint)
            if visible then
                onScreen = true
                minX = math.min(minX, screenPoint.X)
                minY = math.min(minY, screenPoint.Y)
                maxX = math.max(maxX, screenPoint.X)
                maxY = math.max(maxY, screenPoint.Y)
                table.insert(points, screenPoint)
            else
                table.insert(points, screenPoint)
            end
        end
        return onScreen, minX, minY, maxX, maxY, points
    end

    -- Wall check: cast ray from camera to target; returns true if blocked
    local function isBehindWall(origin, target)
        local direction = (target - origin)
        local rayParams = RaycastParams.new()
        -- ignore player's character and local player
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
        rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
        local result = workspace:Raycast(origin, direction, rayParams)
        -- if hit something before reaching the player, then behind wall
        if result and (result.Instance and result.Instance:IsDescendantOf(LocalPlayer.Character) == false) then
            local hitPosition = result.Position
            local distanceToHit = (hitPosition - origin).Magnitude
            local distanceToTarget = direction.Magnitude
            if distanceToHit < distanceToTarget - 1 then
                return true
            end
        end
        return false
    end

    -- Main update loop; runs every frame when ESP is enabled
    local function updateEsp()
        if not EspEnabledToggle.Value then
            -- hide all drawings
            for plr, obj in pairs(espObjects) do
                -- hide box lines
                for _, l in pairs(obj.BoxLines) do l.Visible = false end
                for _, l in pairs(obj.CornerLines) do l.Visible = false end
                for _, l in pairs(obj.SkeletonLines) do l.Visible = false end
                for _, l in pairs(obj.HealthLines) do l.Visible = false end
                if obj.NameText then obj.NameText.Visible = false end
                if obj.DistanceText then obj.DistanceText.Visible = false end
                if obj.TracerLine then obj.TracerLine.Visible = false end
                if obj.HighlightInstance then obj.HighlightInstance.Enabled = false end
            end
            return
        end
        local camera = Workspace.CurrentCamera
        if not camera then return end

        -- update whitelist list periodically
        -- (done by event and manual refresh)

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                -- respect team check
                local skip = false
                if TeamCheckToggle.Value then
                    local myTeam = LocalPlayer.Team
                    if myTeam and plr.Team == myTeam then
                        skip = true
                    end
                end
                -- whitelist check
                local wl = WhitelistDropdown.Value or {}
                if type(wl) == "string" then
                    -- single value returns string
                    if wl == plr.Name then
                        skip = true
                    end
                elseif type(wl) == "table" then
                    for _, v in pairs(wl) do
                        if v == plr.Name then
                            skip = true
                            break
                        end
                    end
                end
                if skip then
                    -- hide and continue
                    removeEspForPlayer(plr)
                    goto continue
                end
                -- ensure esp object exists
                if not espObjects[plr] then
                    createEspForPlayer(plr)
                end
                local obj = espObjects[plr]
                local character = plr.Character
                local hrp = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"))
                if not character or not hrp then
                    -- no character; hide and continue
                    removeEspForPlayer(plr)
                    goto continue
                end
                -- compute bounding box
                local onScreen, minX, minY, maxX, maxY, points = getBoundingBox(character)
                if not onScreen then
                    -- hide
                    if obj.BoxLines then
                        for _, l in pairs(obj.BoxLines) do l.Visible = false end
                    end
                    if obj.CornerLines then
                        for _, l in pairs(obj.CornerLines) do l.Visible = false end
                    end
                    if obj.SkeletonLines then
                        for _, l in pairs(obj.SkeletonLines) do l.Visible = false end
                    end
                    if obj.HealthLines then
                        for _, l in pairs(obj.HealthLines) do l.Visible = false end
                    end
                    if obj.NameText then obj.NameText.Visible = false end
                    if obj.DistanceText then obj.DistanceText.Visible = false end
                    if obj.TracerLine then obj.TracerLine.Visible = false end
                    if obj.HighlightInstance then obj.HighlightInstance.Enabled = false end
                    goto continue
                end

                -- Determine color based on wall check
                local baseColor = BoxColorPicker.Value
                local useColor = baseColor
                if WallCheckToggle.Value then
                    local camPos = camera.CFrame.Position
                    local wallHit = isBehindWall(camPos, hrp.Position)
                    if wallHit then
                        useColor = Color3.fromRGB(255, 0, 0) -- red behind wall
                    else
                        useColor = Color3.fromRGB(0, 255, 0) -- green when visible
                    end
                end

                --------------------------------------------------
                -- Box drawing (either full box or corners)
                if BoxToggle.Value then
                    if BoxTypeDropdown.Value == "Box" then
                        -- compute lines: top, bottom, left, right
                        local topLeft     = Vector2.new(minX, minY)
                        local topRight    = Vector2.new(maxX, minY)
                        local bottomLeft  = Vector2.new(minX, maxY)
                        local bottomRight = Vector2.new(maxX, maxY)
                        -- assign positions
                        local bl = obj.BoxLines
                        if bl and #bl >= 4 then
                            bl[1].From = topLeft;    bl[1].To = topRight
                            bl[2].From = topRight;   bl[2].To = bottomRight
                            bl[3].From = bottomRight;bl[3].To = bottomLeft
                            bl[4].From = bottomLeft; bl[4].To = topLeft
                            for _, l in ipairs(bl) do
                                l.Color = useColor
                                l.Visible = true
                            end
                        end
                        -- hide corners
                        if obj.CornerLines then
                            for _, l in pairs(obj.CornerLines) do l.Visible = false end
                        end
                    else -- Corner style
                        -- compute ratio for corner length
                        local width  = maxX - minX
                        local height = maxY - minY
                        local cw     = math.clamp(width * 0.25, 4, 50)
                        local ch     = math.clamp(height * 0.25, 4, 50)
                        -- coordinates
                        local topLeft     = Vector2.new(minX, minY)
                        local topRight    = Vector2.new(maxX, minY)
                        local bottomLeft  = Vector2.new(minX, maxY)
                        local bottomRight = Vector2.new(maxX, maxY)
                        -- set corner lines (eight lines)
                        local cl = obj.CornerLines
                        if cl and #cl >= 8 then
                            -- TopLeft horizontal and vertical
                            cl[1].From = topLeft;                cl[1].To = topLeft + Vector2.new(cw, 0)
                            cl[2].From = topLeft;                cl[2].To = topLeft + Vector2.new(0, ch)
                            -- TopRight horizontal and vertical
                            cl[3].From = topRight;               cl[3].To = topRight - Vector2.new(cw, 0)
                            cl[4].From = topRight;               cl[4].To = topRight + Vector2.new(0, ch)
                            -- BottomLeft horizontal and vertical
                            cl[5].From = bottomLeft;             cl[5].To = bottomLeft + Vector2.new(cw, 0)
                            cl[6].From = bottomLeft;             cl[6].To = bottomLeft - Vector2.new(0, ch)
                            -- BottomRight horizontal and vertical
                            cl[7].From = bottomRight;            cl[7].To = bottomRight - Vector2.new(cw, 0)
                            cl[8].From = bottomRight;            cl[8].To = bottomRight - Vector2.new(0, ch)
                            for _, l in ipairs(cl) do
                                l.Color = useColor
                                l.Visible = true
                            end
                        end
                        -- hide full box lines
                        if obj.BoxLines then
                            for _, l in pairs(obj.BoxLines) do l.Visible = false end
                        end
                    end
                else
                    -- hide all box/corner lines
                    if obj.BoxLines then
                        for _, l in pairs(obj.BoxLines) do l.Visible = false end
                    end
                    if obj.CornerLines then
                        for _, l in pairs(obj.CornerLines) do l.Visible = false end
                    end
                end

                --------------------------------------------------
                -- Chams: highlight part surfaces
                if ChamsToggle.Value and obj.HighlightInstance then
                    obj.HighlightInstance.Adornee = character
                    obj.HighlightInstance.FillColor = useColor
                    obj.HighlightInstance.OutlineColor = useColor
                    obj.HighlightInstance.Enabled = true
                else
                    if obj.HighlightInstance then
                        obj.HighlightInstance.Enabled = false
                    end
                end

                --------------------------------------------------
                -- Skeleton
                if SkeletonToggle.Value then
                    local pairsList = getSkeletonPairs(character)
                    -- ensure we have enough line objects
                    local sl = obj.SkeletonLines
                    -- hide unused lines
                    for i = 1, #sl do
                        local line = sl[i]
                        if i <= #pairsList then
                            local a = pairsList[i][1].Position
                            local b = pairsList[i][2].Position
                            local posA, visA = camera:WorldToViewportPoint(a)
                            local posB, visB = camera:WorldToViewportPoint(b)
                            if visA and visB then
                                line.From = Vector2.new(posA.X, posA.Y)
                                line.To   = Vector2.new(posB.X, posB.Y)
                                line.Color = useColor
                                line.Visible = true
                            else
                                line.Visible = false
                            end
                        else
                            line.Visible = false
                        end
                    end
                else
                    if obj.SkeletonLines then
                        for _, l in pairs(obj.SkeletonLines) do l.Visible = false end
                    end
                end

                --------------------------------------------------
                -- Health bar
                if HealthToggle.Value then
                    -- compute positions: draw bar on the left side of box
                    local hum = character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local health     = math.clamp(hum.Health, 0, hum.MaxHealth)
                        local ratio      = health / math.max(1, hum.MaxHealth)
                        local barHeight  = maxY - minY
                        local barWidth   = 4
                        local x0 = minX - barWidth - 2
                        local y0 = minY
                        local y1 = maxY
                        -- outer line
                        local hl = obj.HealthLines
                        if hl and #hl >= 2 then
                            -- outline
                            hl[1].From = Vector2.new(x0, y0)
                            hl[1].To   = Vector2.new(x0, y1)
                            hl[1].Color = Color3.new(0,0,0)
                            hl[1].Thickness = 2
                            hl[1].Visible = true
                            -- inner bar
                            local innerY = y0 + barHeight * (1 - ratio)
                            hl[2].From = Vector2.new(x0, innerY)
                            hl[2].To   = Vector2.new(x0, y1)
                            -- gradient from red to green
                            local r = math.clamp(1 - ratio, 0, 1)
                            local g = math.clamp(ratio, 0, 1)
                            hl[2].Color = Color3.new(r, g, 0)
                            hl[2].Thickness = 2
                            hl[2].Visible = true
                        end
                    else
                        if obj.HealthLines then
                            for _, l in pairs(obj.HealthLines) do l.Visible = false end
                        end
                    end
                else
                    if obj.HealthLines then
                        for _, l in pairs(obj.HealthLines) do l.Visible = false end
                    end
                end

                --------------------------------------------------
                -- Name tag
                if NameToggle.Value and obj.NameText then
                    local text = obj.NameText
                    local midX = (minX + maxX) / 2
                    local yPos = minY - 15
                    text.Position = Vector2.new(midX, yPos)
                    text.Color    = NameColorPicker.Value
                    text.Size     = NameSizeSlider.Value
                    text.Text     = plr.DisplayName or plr.Name
                    text.Visible  = true
                else
                    if obj.NameText then obj.NameText.Visible = false end
                end

                --------------------------------------------------
                -- Distance text
                if DistanceToggle.Value and obj.DistanceText then
                    local text = obj.DistanceText
                    -- compute distance from local player
                    local root = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("Torso") or LocalPlayer.Character:FindFirstChild("UpperTorso"))
                    if root then
                        local dist = (hrp.Position - root.Position).Magnitude
                        local midX = (minX + maxX) / 2
                        local yPos = maxY + 3
                        text.Position = Vector2.new(midX, yPos)
                        text.Color    = DistanceColorPicker.Value
                        text.Size     = DistanceSizeSlider.Value
                        text.Text     = string.format("%.0f m", dist)
                        text.Visible  = true
                    else
                        text.Visible = false
                    end
                else
                    if obj.DistanceText then obj.DistanceText.Visible = false end
                end

                --------------------------------------------------
                -- Tracer line
                if TracerToggle.Value and obj.TracerLine then
                    local line = obj.TracerLine
                    local screenPos, visible = camera:WorldToViewportPoint(hrp.Position)
                    if visible then
                        -- start from bottom center of screen
                        local viewSize = camera.ViewportSize
                        local startX = viewSize.X / 2
                        local startY = viewSize.Y
                        line.From = Vector2.new(startX, startY)
                        line.To   = Vector2.new(screenPos.X, screenPos.Y)
                        line.Color = TracerColorPicker.Value
                        line.Visible = true
                    else
                        line.Visible = false
                    end
                else
                    if obj.TracerLine then obj.TracerLine.Visible = false end
                end

                ::continue::
                -- loop end for each player
            end
        end

        -- remove esp for players no longer in game
        for plr, _ in pairs(espObjects) do
            if not Players:FindFirstChild(plr.Name) then
                removeEspForPlayer(plr)
            end
        end
    end

    -- set up event to update whitelist list on join/leave
    AddConnection(Players.PlayerAdded:Connect(function(plr)
        refreshWhitelist()
        WhitelistDropdown:SetValues(whitelistNames)
    end))
    AddConnection(Players.PlayerRemoving:Connect(function(plr)
        refreshWhitelist()
        WhitelistDropdown:SetValues(whitelistNames)
        removeEspForPlayer(plr)
    end))

    -- periodic refresh every 10 seconds
    task.spawn(function()
        while true do
            task.wait(10)
            refreshWhitelist()
            WhitelistDropdown:SetValues(whitelistNames)
        end
    end)

    -- connect main ESP update loop
    AddConnection(RunService.RenderStepped:Connect(updateEsp))
    ------------------------------------------------
    -- 4.4 Theme / SaveManager (optional) ไว้ทำใน Tab Settings ภายหลัง
    ------------------------------------------------
    -- คุณสามารถโยก ThemeManager/SaveManager ไปผูกกับ Tabs.Settings ทีหลังได้

    ------------------------------------------------
    -- 4.5 Cleanup เมื่อ Unload
    ------------------------------------------------
    if Library and type(Library.OnUnload) == "function" then
        Library:OnUnload(function()
            for _, conn in ipairs(Connections) do
                pcall(function()
                    conn:Disconnect()
                end)
            end
        end)
    end
end

--====================================================
-- 5. Return function สำหรับ KeyUI.startMainHub
--====================================================
return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then
        warn("[MainHub] Fatal error:", err)
    end
end
