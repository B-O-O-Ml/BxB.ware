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
