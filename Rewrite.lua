--====================================================
-- 0. Services
--====================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService") -- เพิ่มบรรทัดนี้
-- VirtualUser for simulating user input (Anti-AFK)
local VirtualUser        = game:GetService("VirtualUser")

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

    local Library      = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    -- นำ Options และ Toggles มาไว้ในตัวแปรเพื่อใช้งานในส่วนต่าง ๆ
    local Options = Library.Options
    local Toggles = Library.Toggles

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

    -- WalkSpeed method dropdown (for future expansion)
    local WalkMethodDropdown = MoveBox:AddDropdown("bxw_walk_method", {
        Text = "Walk Method",
        Values = { "Direct", "Incremental" },
        Default = "Direct",
        Multi = false,
        Tooltip = "Method to apply WalkSpeed (placeholder)",
    })

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

    -- Fly speed slider
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", {
        Text = "Fly Speed",
        Default = flySpeed,
        Min = 1,
        Max = 300,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            flySpeed = value
        end,
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

    -- Waypoints management
    UtilBox:AddDivider()
    UtilBox:AddLabel("Waypoints")
    -- table to store waypoint CFrame by name
    local savedWaypoints = {}
    local savedNames = {}
    -- Dropdown to list saved waypoints
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", {
        Text = "Waypoint List",
        Values = savedNames,
        Default = "",
        Multi = false,
        AllowNull = true,
        Tooltip = "Select a saved waypoint",
    })
    -- Button to save current position as waypoint
    UtilBox:AddButton("Set Waypoint", function()
        local root = getRootPart()
        if not root then
            Library:Notify("Character not loaded", 2)
            return
        end
        local name = "WP" .. tostring(#savedNames + 1)
        savedWaypoints[name] = root.CFrame
        table.insert(savedNames, name)
        WaypointDropdown:SetValues(savedNames)
        Library:Notify("Saved waypoint " .. name, 2)
    end)
    -- Button to teleport to selected waypoint
    UtilBox:AddButton("Teleport to Waypoint", function()
        local sel = WaypointDropdown.Value
        if not sel or sel == "" then
            Library:Notify("Select a waypoint first", 2)
            return
        end
        local cf = savedWaypoints[sel]
        local root = getRootPart()
        if cf and root then
            root.CFrame = cf + Vector3.new(0, 3, 0)
            Library:Notify("Teleported to " .. sel, 2)
        else
            Library:Notify("Waypoint or character missing", 2)
        end
    end)

    ------------------------------------------------
    -- 4.3 ESP & Visuals Tab
    ------------------------------------------------
    do
        local ESPTab = Tabs.ESP

        -- Groupboxes for ESP features and settings
        local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
        local ESPSettingBox = ESPTab:AddRightGroupbox("ESP Settings", "palette")

        -- Master toggle for ESP
        local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", {
            Text = "Enable ESP",
            Default = false,
            Tooltip = "Toggle all ESP drawing on/off",
        })

        -- Box style: full box vs corner
        local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", {
            Text = "Box Style",
            Values = { "Box", "Corner" },
            Default = "Box",
            Multi = false,
            Tooltip = "Choose between full box or corner box",
        })

        -- Individual feature toggles
        local BoxToggle      = ESPFeatureBox:AddToggle("bxw_esp_box",      { Text = "Box",        Default = true })
        local ChamsToggle    = ESPFeatureBox:AddToggle("bxw_esp_chams",    { Text = "Chams",      Default = false })
        local SkeletonToggle = ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton",   Default = false })
        local HealthToggle   = ESPFeatureBox:AddToggle("bxw_esp_health",   { Text = "Health Bar", Default = false })
        local NameToggle     = ESPFeatureBox:AddToggle("bxw_esp_name",     { Text = "Name Tag",   Default = true })
        local DistToggle     = ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance",   Default = false })
        local TracerToggle   = ESPFeatureBox:AddToggle("bxw_esp_tracer",   { Text = "Tracer",     Default = false })
        local TeamToggle     = ESPFeatureBox:AddToggle("bxw_esp_team",     { Text = "Team Check", Default = true })
        local WallToggle     = ESPFeatureBox:AddToggle("bxw_esp_wall",     { Text = "Wall Check", Default = false })

        -- Additional ESP feature toggles
        local SelfToggle     = ESPFeatureBox:AddToggle("bxw_esp_self", {
            Text = "Self ESP",
            Default = false,
            Tooltip = "Draw ESP on your own character for testing",
        })
        local InfoToggle     = ESPFeatureBox:AddToggle("bxw_esp_info", {
            Text = "Target Info",
            Default = false,
            Tooltip = "Display extra info (health, team, distance) under ESP",
        })

        -- Whitelist players dropdown (auto refresh)
        local function getPlayerNames()
            local names = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    table.insert(names, plr.Name)
                end
            end
            table.sort(names)
            return names
        end

        local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", {
            Text = "Whitelist Player",
            Values = getPlayerNames(),
            Default = "",
            Multi = true,
            AllowNull = true,
            Tooltip = "Players to exclude from ESP",
        })

        -- Auto refresh whitelist every 10 seconds and on player join/leave
        do
            local function refreshWhitelist()
                local names = getPlayerNames()
                WhitelistDropdown:SetValues(names)
            end
            refreshWhitelist()
            AddConnection(Players.PlayerAdded:Connect(refreshWhitelist))
            AddConnection(Players.PlayerRemoving:Connect(refreshWhitelist))
            -- periodic refresh
            task.spawn(function()
                while true do
                    task.wait(10)
                    refreshWhitelist()
                end
            end)
        end

        -- Color pickers and size sliders
        local BoxColorPicker    = ESPSettingBox:AddColorPicker("bxw_esp_box_color", {
            Text = "Box Color",
            Default = Color3.fromRGB(255, 255, 255),
        })
        local TracerColorPicker = ESPSettingBox:AddColorPicker("bxw_esp_tracer_color", {
            Text = "Tracer Color",
            Default = Color3.fromRGB(255, 255, 255),
        })
        local NameColorPicker   = ESPSettingBox:AddColorPicker("bxw_esp_name_color", {
            Text = "Name Color",
            Default = Color3.fromRGB(255, 255, 255),
        })
        local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", {
            Text = "Name Size",
            Default = 14,
            Min = 10,
            Max = 30,
            Rounding = 0,
        })
        local DistColorPicker   = ESPSettingBox:AddColorPicker("bxw_esp_dist_color", {
            Text = "Distance Color",
            Default = Color3.fromRGB(255, 255, 255),
        })
        local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", {
            Text = "Distance Size",
            Default = 14,
            Min = 10,
            Max = 30,
            Rounding = 0,
        })

        -- Distance unit dropdown (studs/meters)
        local DistUnitDropdown = ESPSettingBox:AddDropdown("bxw_esp_dist_unit", {
            Text = "Distance Unit",
            Values = { "Studs", "Meters" },
            Default = "Studs",
            Multi = false,
            Tooltip = "Choose unit for distance display",
        })

        -- Additional color pickers for ESP elements
        local SkeletonColorPicker = ESPSettingBox:AddColorPicker("bxw_esp_skeleton_color", {
            Text = "Skeleton Color",
            Default = Color3.fromRGB(0, 255, 255),
        })
        local HealthColorPicker = ESPSettingBox:AddColorPicker("bxw_esp_health_color", {
            Text = "Health Bar Color",
            Default = Color3.fromRGB(0, 255, 0),
        })
        local InfoColorPicker = ESPSettingBox:AddColorPicker("bxw_esp_info_color", {
            Text = "Info Color",
            Default = Color3.fromRGB(255, 255, 255),
        })
        local ChamsColorPicker = ESPSettingBox:AddColorPicker("bxw_esp_chams_color", {
            Text = "Chams Color",
            Default = Color3.fromRGB(0, 255, 0),
        })

        -- Chams customization sliders/toggles
        local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", {
            Text = "Chams Transparency",
            Default = 0.5,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Compact = false,
        })
        local ChamsMaterialDropdown = ESPSettingBox:AddDropdown("bxw_esp_chams_material", {
            Text = "Chams Material",
            Values = { "ForceField", "Neon", "Plastic" },
            Default = "ForceField",
            Multi = false,
            Tooltip = "Material applied to highlighted parts (visual only)",
        })
        local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", {
            Text = "Visible Only",
            Default = false,
            Tooltip = "Only show chams when unobstructed",
        })

        -- Camera & world settings group
        local cam = Workspace.CurrentCamera
        local defaultCamFov = cam and cam.FieldOfView or 70
        local defaultMaxZoom = LocalPlayer.CameraMaxZoomDistance or 400
        local defaultMinZoom = LocalPlayer.CameraMinZoomDistance or 0.5
        local WorldBox = ESPTab:AddLeftGroupbox("Camera & World", "sun")

        local CamFOVSlider = WorldBox:AddSlider("bxw_cam_fov", {
            Text = "Camera FOV",
            Default = defaultCamFov,
            Min = 40,
            Max = 120,
            Rounding = 0,
            Compact = false,
            Callback = function(value)
                local c = Workspace.CurrentCamera
                if c then
                    c.FieldOfView = value
                end
            end,
        })
        local MaxZoomSlider = WorldBox:AddSlider("bxw_cam_maxzoom", {
            Text = "Max Zoom",
            Default = defaultMaxZoom,
            Min = 10,
            Max = 1000,
            Rounding = 0,
            Compact = false,
            Callback = function(value)
                pcall(function()
                    LocalPlayer.CameraMaxZoomDistance = value
                end)
            end,
        })
        WorldBox:AddButton("Reset Max Zoom", function()
            pcall(function()
                LocalPlayer.CameraMaxZoomDistance = defaultMaxZoom
            end)
            MaxZoomSlider:SetValue(defaultMaxZoom)
        end)
        local MinZoomSlider = WorldBox:AddSlider("bxw_cam_minzoom", {
            Text = "Min Zoom",
            Default = defaultMinZoom,
            Min = 0,
            Max = 50,
            Rounding = 1,
            Compact = false,
            Callback = function(value)
                pcall(function()
                    LocalPlayer.CameraMinZoomDistance = value
                end)
            end,
        })
        WorldBox:AddButton("Reset Min Zoom", function()
            pcall(function()
                LocalPlayer.CameraMinZoomDistance = defaultMinZoom
            end)
            MinZoomSlider:SetValue(defaultMinZoom)
        end)

        -- Simple skybox themes (IDs correspond to Roblox asset IDs)
        local SkyboxThemes = {
            ["Default"] = "",
            ["Space"]   = "rbxassetid://11755937810",
            ["Sunset"]  = "rbxassetid://9393701400",
            ["Midnight"] = "rbxassetid://11755930464",
        }
        local SkyboxDropdown = WorldBox:AddDropdown("bxw_cam_skybox", {
            Text = "Skybox Theme",
            Values = { "Default", "Space", "Sunset", "Midnight" },
            Default = "Default",
            Multi = false,
            Tooltip = "Change the skybox theme",
        })
        local originalSky = nil
        local function applySky(name)
            local lighting = game:GetService("Lighting")
            if not originalSky then
                -- capture original sky (clone)
                originalSky = lighting:FindFirstChildOfClass("Sky")
                if originalSky then
                    originalSky = originalSky:Clone()
                end
            end
            -- remove any current sky
            local currentSky = lighting:FindFirstChildOfClass("Sky")
            if currentSky then
                currentSky:Destroy()
            end
            local id = SkyboxThemes[name]
            if id and id ~= "" then
                local sky = Instance.new("Sky")
                sky.SkyboxBk = id
                sky.SkyboxDn = id
                sky.SkyboxFt = id
                sky.SkyboxLf = id
                sky.SkyboxRt = id
                sky.SkyboxUp = id
                sky.Parent = lighting
            else
                -- restore original if available
                if originalSky then
                    local newSky = originalSky:Clone()
                    newSky.Parent = lighting
                end
            end
        end
        SkyboxDropdown:OnChanged(function(value)
            applySky(value)
        end)

        ------------------------------------------------
        -- ESP Logic
        ------------------------------------------------
        local espDrawings = {}

        local function removePlayerESP(plr)
            local data = espDrawings[plr]
            if data then
                -- Destroy drawing objects
                if data.Box then
                    pcall(function() data.Box:Remove() end)
                end
                if data.Corners then
                    for _, ln in pairs(data.Corners) do
                        pcall(function() ln:Remove() end)
                    end
                end
                if data.Health then
                    if data.Health.Outline then pcall(function() data.Health.Outline:Remove() end) end
                    if data.Health.Bar then     pcall(function() data.Health.Bar:Remove() end) end
                end
                if data.Name then
                    pcall(function() data.Name:Remove() end)
                end
                if data.Distance then
                    pcall(function() data.Distance:Remove() end)
                end
                if data.Tracer then
                    pcall(function() data.Tracer:Remove() end)
                end
                if data.Highlight then
                    pcall(function() data.Highlight:Destroy() end)
                end
                espDrawings[plr] = nil
            end
        end

        -- Cleanup on player removal
        AddConnection(Players.PlayerRemoving:Connect(function(plr)
            removePlayerESP(plr)
        end))

        -- Helper to create skeleton lines (R6/R15)
        local skeletonJoints = {
            -- For R15 avatars; keys are joint names, values are parent name
            ["Head"] = "UpperTorso",
            ["UpperTorso"] = "LowerTorso",
            ["LowerTorso"] = "HumanoidRootPart",

            ["LeftUpperArm"]  = "UpperTorso",
            ["LeftLowerArm"]  = "LeftUpperArm",
            ["LeftHand"]      = "LeftLowerArm",
            ["RightUpperArm"] = "UpperTorso",
            ["RightLowerArm"] = "RightUpperArm",
            ["RightHand"]     = "RightLowerArm",

            ["LeftUpperLeg"]  = "LowerTorso",
            ["LeftLowerLeg"]  = "LeftUpperLeg",
            ["LeftFoot"]      = "LeftLowerLeg",
            ["RightUpperLeg"] = "LowerTorso",
            ["RightLowerLeg"] = "RightUpperLeg",
            ["RightFoot"]     = "RightLowerLeg",
        }

        -- Main update function
        local function updateESP()
            if not ESPEnabledToggle.Value then
                -- hide or remove drawings
                for _, v in pairs(espDrawings) do
                    if v.Box then v.Box.Visible = false end
                    if v.Corners then for _, ln in pairs(v.Corners) do ln.Visible = false end end
                    if v.Health then
                        if v.Health.Outline then v.Health.Outline.Visible = false end
                        if v.Health.Bar then v.Health.Bar.Visible = false end
                    end
                    if v.Name then v.Name.Visible = false end
                    if v.Distance then v.Distance.Visible = false end
                    if v.Tracer then v.Tracer.Visible = false end
                    if v.Highlight then v.Highlight.Enabled = false end
                end
                return
            end

            local cam = Workspace.CurrentCamera
            if not cam then return end
            local camCFrame = cam.CFrame
            local camPos = camCFrame.Position

            for _, plr in ipairs(Players:GetPlayers()) do
                -- include local player if self ESP enabled
                if plr ~= LocalPlayer or (SelfToggle and SelfToggle.Value) then
                    local char = plr.Character
                    local hum  = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart") or char and char:FindFirstChild("Torso") or char and char:FindFirstChild("UpperTorso")
                    if hum and hum.Health > 0 and root then
                        local skipPlayer = false
                        -- Team check
                        if TeamToggle.Value then
                            local myTeam = LocalPlayer.Team
                            local hisTeam = plr.Team
                            if myTeam ~= nil and hisTeam ~= nil and myTeam == hisTeam then
                                skipPlayer = true
                            end
                        end
                        -- Whitelist check
                        if not skipPlayer then
                            local list = WhitelistDropdown.Value
                            if list and type(list) == "table" then
                                for _, name in ipairs(list) do
                                    if name == plr.Name then
                                        skipPlayer = true
                                        break
                                    end
                                end
                            end
                        end

                        if skipPlayer then
                            -- hide drawings for this player
                            if espDrawings[plr] then
                                local d = espDrawings[plr]
                                if d.Box then d.Box.Visible = false end
                                if d.Corners then for _, ln in pairs(d.Corners) do ln.Visible = false end end
                                if d.Health then
                                    if d.Health.Outline then d.Health.Outline.Visible = false end
                                    if d.Health.Bar then d.Health.Bar.Visible = false end
                                end
                                if d.Name then d.Name.Visible = false end
                                if d.Distance then d.Distance.Visible = false end
                                if d.Tracer then d.Tracer.Visible = false end
                                if d.Highlight then d.Highlight.Enabled = false end
                            end
                        else
                            -- ensure drawing objects exist
                            local data = espDrawings[plr]
                            if not data then
                                data = {}
                                espDrawings[plr] = data
                            end

                            -- highlight (chams) with customization
                            if ChamsToggle.Value then
                                -- determine highlight color and transparency
                                local chamsCol = ChamsColorPicker and ChamsColorPicker.Value or BoxColorPicker.Value
                                local chamsTrans = ChamsTransSlider and ChamsTransSlider.Value or 0.5
                                local visibleOnly = ChamsVisibleToggle and ChamsVisibleToggle.Value or false
                                local depthMode = visibleOnly and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                                if not data.Highlight then
                                    local hl = Instance.new("Highlight")
                                    hl.DepthMode = depthMode
                                    hl.FillColor = chamsCol
                                    hl.FillTransparency = chamsTrans
                                    hl.OutlineColor = chamsCol
                                    hl.OutlineTransparency = 0.0
                                    hl.Adornee = char
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
                                -- optional: apply material to parts (reserved for future)
                            else
                                if data.Highlight then
                                    data.Highlight.Enabled = false
                                end
                            end

                            -- compute bounding box for box/health bar/tracer/position
                            local minVec = Vector3.new(math.huge, math.huge, math.huge)
                            local maxVec = Vector3.new(-math.huge, -math.huge, -math.huge)
                            for _, part in ipairs(char:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    local pos = part.Position
                                    minVec = Vector3.new(math.min(minVec.X, pos.X), math.min(minVec.Y, pos.Y), math.min(minVec.Z, pos.Z))
                                    maxVec = Vector3.new(math.max(maxVec.X, pos.X), math.max(maxVec.Y, pos.Y), math.max(maxVec.Z, pos.Z))
                                end
                            end
                            local size = maxVec - minVec
                            local center = (maxVec + minVec) / 2

                            -- world corners for box
                            local halfSize = size / 2
                            local cornersWorld = {
                                center + Vector3.new(-halfSize.X,  halfSize.Y, -halfSize.Z),
                                center + Vector3.new( halfSize.X,  halfSize.Y, -halfSize.Z),
                                center + Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
                                center + Vector3.new( halfSize.X, -halfSize.Y, -halfSize.Z),
                                center + Vector3.new(-halfSize.X,  halfSize.Y,  halfSize.Z),
                                center + Vector3.new( halfSize.X,  halfSize.Y,  halfSize.Z),
                                center + Vector3.new(-halfSize.X, -halfSize.Y,  halfSize.Z),
                                center + Vector3.new( halfSize.X, -halfSize.Y,  halfSize.Z),
                            }

                            -- project corners to screen
                            local screenPoints = {}
                            local onScreen = false
                            for i, worldPos in ipairs(cornersWorld) do
                                local screenPos, vis = cam:WorldToViewportPoint(worldPos)
                                screenPoints[i] = Vector2.new(screenPos.X, screenPos.Y)
                                onScreen = onScreen or vis
                            end

                            if not onScreen then
                                -- hide if not on screen
                                if data.Box then data.Box.Visible = false end
                                if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                if data.Health then
                                    if data.Health.Outline then data.Health.Outline.Visible = false end
                                    if data.Health.Bar then data.Health.Bar.Visible = false end
                                end
                                if data.Name then data.Name.Visible = false end
                                if data.Distance then data.Distance.Visible = false end
                                if data.Tracer then data.Tracer.Visible = false end
                            else
                                -- compute 2D bounding box
                                local minX, minY = math.huge, math.huge
                                local maxX, maxY = -math.huge, -math.huge
                                for _, v2 in ipairs(screenPoints) do
                                    minX = math.min(minX, v2.X)
                                    maxX = math.max(maxX, v2.X)
                                    minY = math.min(minY, v2.Y)
                                    maxY = math.max(maxY, v2.Y)
                                end
                                local boxW, boxH = maxX - minX, maxY - minY

                                -- wall check color (default color)
                                local finalColor = BoxColorPicker.Value
                                if WallToggle.Value then
                                    local rayDir = (center - camPos)
                                    local rayParams = RaycastParams.new()
                                    rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                    local rayResult = Workspace:Raycast(camPos, rayDir, rayParams)
                                    if rayResult then
                                        finalColor = Color3.fromRGB(255, 0, 0) -- red if obstructed
                                    else
                                        finalColor = Color3.fromRGB(0, 255, 0) -- green if visible
                                    end
                                end

                                -- Box drawing
                                if BoxToggle.Value then
                                    if BoxStyleDropdown.Value == "Box" then
                                        if not data.Box then
                                            local sq = Drawing.new("Square")
                                            sq.Thickness = 1
                                            sq.Filled = false
                                            sq.Transparency = 1
                                            data.Box = sq
                                        end
                                        data.Box.Visible = true
                                        data.Box.Color = finalColor
                                        data.Box.Position = Vector2.new(minX, minY)
                                        data.Box.Size = Vector2.new(boxW, boxH)
                                        -- hide corners if exist
                                        if data.Corners then
                                            for _, ln in pairs(data.Corners) do
                                                ln.Visible = false
                                            end
                                        end
                                    else
                                        -- corner box style
                                        if not data.Corners then
                                            data.Corners = {}
                                            for i = 1, 4 do
                                                local ln = Drawing.new("Line")
                                                ln.Thickness = 1
                                                ln.Transparency = 1
                                                data.Corners[i] = ln
                                            end
                                        end
                                        -- hide full box if exists
                                        if data.Box then
                                            data.Box.Visible = false
                                        end
                                        -- set up corner lines: use 25% of width/height
                                        local cw = boxW * 0.25
                                        local ch = boxH * 0.25
                                        local topLeft     = Vector2.new(minX, minY)
                                        local topRight    = Vector2.new(maxX, minY)
                                        local bottomLeft  = Vector2.new(minX, maxY)
                                        local bottomRight = Vector2.new(maxX, maxY)
                                        -- line segments: top-left horizontal and vertical
                                        local lines = data.Corners
                                        lines[1].Visible = true
                                        lines[1].Color = finalColor
                                        lines[1].From = topLeft
                                        lines[1].To   = topLeft + Vector2.new(cw, 0)
                                        lines[2].Visible = true
                                        lines[2].Color = finalColor
                                        lines[2].From = topLeft
                                        lines[2].To   = topLeft + Vector2.new(0, ch)
                                        -- top-right
                                        lines[3].Visible = true
                                        lines[3].Color = finalColor
                                        lines[3].From = topRight
                                        lines[3].To   = topRight + Vector2.new(-cw, 0)
                                        lines[4].Visible = true
                                        lines[4].Color = finalColor
                                        lines[4].From = topRight
                                        lines[4].To   = topRight + Vector2.new(0, ch)
                                        -- bottom-left (reuse lines array if extended)
                                        if #lines < 8 then
                                            for i = #lines + 1, 8 do
                                                local ln = Drawing.new("Line")
                                                ln.Thickness = 1
                                                ln.Transparency = 1
                                                lines[i] = ln
                                            end
                                        end
                                        lines[5].Visible = true
                                        lines[5].Color = finalColor
                                        lines[5].From = bottomLeft
                                        lines[5].To   = bottomLeft + Vector2.new(cw, 0)
                                        lines[6].Visible = true
                                        lines[6].Color = finalColor
                                        lines[6].From = bottomLeft
                                        lines[6].To   = bottomLeft + Vector2.new(0, -ch)
                                        -- bottom-right
                                        lines[7].Visible = true
                                        lines[7].Color = finalColor
                                        lines[7].From = bottomRight
                                        lines[7].To   = bottomRight + Vector2.new(-cw, 0)
                                        lines[8].Visible = true
                                        lines[8].Color = finalColor
                                        lines[8].From = bottomRight
                                        lines[8].To   = bottomRight + Vector2.new(0, -ch)
                                    end
                                else
                                    if data.Box then data.Box.Visible = false end
                                    if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                end

                                -- Health bar
                                if HealthToggle.Value then
                                    if not data.Health then
                                        data.Health = {
                                            Outline = Drawing.new("Line"),
                                            Bar     = Drawing.new("Line"),
                                        }
                                        data.Health.Outline.Thickness = 3
                                        data.Health.Outline.Transparency = 1
                                        data.Health.Bar.Thickness = 1
                                        data.Health.Bar.Transparency = 1
                                    end
                                    local outline = data.Health.Outline
                                    local bar     = data.Health.Bar
                                    local healthRatio = hum.Health / math.max(hum.MaxHealth, 1)
                                    local hbX = minX - 6
                                    local hbY1 = minY
                                    local hbY2 = maxY
                                    local barY2 = hbY1 + (maxY - minY) * (1 - healthRatio)

                                    outline.Visible = true
                                    outline.Color = Color3.fromRGB(0, 0, 0)
                                    outline.From  = Vector2.new(hbX, hbY1)
                                    outline.To    = Vector2.new(hbX, hbY2)
                                    bar.Visible = true
                                    -- Use custom health bar color if available
                                    if HealthColorPicker then
                                        bar.Color = HealthColorPicker.Value
                                    else
                                        bar.Color = finalColor
                                    end
                                    bar.From  = Vector2.new(hbX, hbY1)
                                    bar.To    = Vector2.new(hbX, barY2)
                                else
                                    if data.Health then
                                        data.Health.Outline.Visible = false
                                        data.Health.Bar.Visible = false
                                    end
                                end

                                -- Name tag
                                if NameToggle.Value then
                                    if not data.Name then
                                        local txt = Drawing.new("Text")
                                        txt.Center = true
                                        txt.Outline = true
                                        txt.Transparency = 1
                                        data.Name = txt
                                    end
                                    data.Name.Visible = true
                                    data.Name.Color = NameColorPicker.Value
                                    data.Name.Size = NameSizeSlider.Value
                                    data.Name.Text = plr.DisplayName or plr.Name
                                    data.Name.Position = Vector2.new((minX + maxX) / 2, minY - 14)
                                else
                                    if data.Name then data.Name.Visible = false end
                                end

                                -- Distance tag
                                if DistToggle.Value then
                                    if not data.Distance then
                                        local txt = Drawing.new("Text")
                                        txt.Center = true
                                        txt.Outline = true
                                        txt.Transparency = 1
                                        data.Distance = txt
                                    end
                                    local distStud = (root.Position - camPos).Magnitude
                                    -- convert units if using meters (approx 1 stud = 0.28m)
                                    local unit = DistUnitDropdown and DistUnitDropdown.Value or "Studs"
                                    local distNum = distStud
                                    local suffix = " studs"
                                    if unit == "Meters" then
                                        distNum = distStud * 0.28
                                        suffix = " m"
                                    end
                                    data.Distance.Visible = true
                                    data.Distance.Color = DistColorPicker.Value
                                    data.Distance.Size = DistSizeSlider.Value
                                    data.Distance.Text = string.format("%.1f", distNum) .. suffix
                                    data.Distance.Position = Vector2.new((minX + maxX) / 2, maxY + 2)
                                else
                                    if data.Distance then data.Distance.Visible = false end
                                end

                                -- Skeleton lines
                                if SkeletonToggle and SkeletonToggle.Value then
                                    if not data.Skeleton then
                                        data.Skeleton = {}
                                    end
                                    local idx = 1
                                    for joint, parentName in pairs(skeletonJoints) do
                                        local part1 = char:FindFirstChild(joint)
                                        local part2 = char:FindFirstChild(parentName)
                                        local ln = data.Skeleton[idx]
                                        if not ln then
                                            ln = Drawing.new("Line")
                                            ln.Thickness = 1
                                            ln.Transparency = 1
                                            data.Skeleton[idx] = ln
                                        end
                                        if part1 and part2 then
                                            local sp1, vis1 = cam:WorldToViewportPoint(part1.Position)
                                            local sp2, vis2 = cam:WorldToViewportPoint(part2.Position)
                                            if vis1 or vis2 then
                                                ln.Visible = true
                                                ln.Color = (SkeletonColorPicker and SkeletonColorPicker.Value) or BoxColorPicker.Value
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
                                    if data.Skeleton then
                                        for j = idx, #data.Skeleton do
                                            local ln = data.Skeleton[j]
                                            if ln then
                                                ln.Visible = false
                                            end
                                        end
                                    end
                                else
                                    if data.Skeleton then
                                        for _, ln in pairs(data.Skeleton) do
                                            ln.Visible = false
                                        end
                                    end
                                end

                                -- Target info display
                                if InfoToggle and InfoToggle.Value then
                                    if not data.Info then
                                        local txt = Drawing.new("Text")
                                        txt.Center = true
                                        txt.Outline = true
                                        txt.Transparency = 1
                                        data.Info = txt
                                    end
                                    local distStudInfo = (root.Position - camPos).Magnitude
                                    local unitInfo = DistUnitDropdown and DistUnitDropdown.Value or "Studs"
                                    local distNumInfo = distStudInfo
                                    local suffixInfo = " studs"
                                    if unitInfo == "Meters" then
                                        distNumInfo = distStudInfo * 0.28
                                        suffixInfo = " m"
                                    end
                                    local teamName = plr.Team and plr.Team.Name or "No Team"
                                    data.Info.Visible = true
                                    data.Info.Color = (InfoColorPicker and InfoColorPicker.Value) or NameColorPicker.Value
                                    data.Info.Size = (NameSizeSlider and NameSizeSlider.Value) or 14
                                    data.Info.Text = string.format("%s | HP:%d | %.1f%s | %s", plr.DisplayName or plr.Name, hum.Health, distNumInfo, suffixInfo, teamName)
                                    data.Info.Position = Vector2.new((minX + maxX) / 2, maxY + 16)
                                else
                                    if data.Info then
                                        data.Info.Visible = false
                                    end
                                end

                                -- Tracer line
                                if TracerToggle.Value then
                                    if not data.Tracer then
                                        local ln = Drawing.new("Line")
                                        ln.Thickness = 1
                                        ln.Transparency = 1
                                        data.Tracer = ln
                                    end
                                    local screenRoot, rootOnScreen = cam:WorldToViewportPoint(root.Position)
                                    if rootOnScreen then
                                        data.Tracer.Visible = true
                                        data.Tracer.Color = TracerColorPicker.Value
                                        data.Tracer.From = Vector2.new(screenRoot.X, screenRoot.Y)
                                        -- draw to bottom of screen center
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
                        -- hide if no character
                        removePlayerESP(plr)
                    end
                end
            end
        end

        -- Connect render stepped for ESP
        AddConnection(RunService.RenderStepped:Connect(updateESP))
    end

    ------------------------------------------------
    -- 4.4 Combat & Aimbot Tab
    ------------------------------------------------
    do
        local CombatTab = Tabs.Combat

        local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
        local ExtraBox = CombatTab:AddRightGroupbox("Extra Settings", "adjust")

        -- Aimbot toggles and settings
        local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", {
            Text = "Enable Aimbot",
            Default = false,
            Tooltip = "Smoothly aim towards enemies within FOV",
        })
        local SilentToggle = AimBox:AddToggle("bxw_silent_enable", {
            Text = "Silent Aim",
            Default = false,
            Tooltip = "Redirect bullets (not implemented)",
        })
        local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", {
            Text = "Aim Part",
            Values = { "Head", "Torso", "HumanoidRootPart", "Closest" },
            Default = "Head",
            Multi = false,
            Tooltip = "Part to aim at",
        })
        local FOVSlider = AimBox:AddSlider("bxw_aim_fov", {
            Text = "Aim FOV",
            Default = 10,
            Min = 1,
            Max = 50,
            Rounding = 1,
            Compact = false,
        })
        local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", {
            Text = "Show FOV Circle",
            Default = false,
        })
        local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", {
            Text = "Aimbot Smoothness",
            Default = 0.1,
            Min = 0.01,
            Max = 1,
            Rounding = 2,
            Compact = false,
        })
        local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", {
            Text = "Team Check",
            Default = true,
        })
        local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", {
            Text = "Triggerbot",
            Default = false,
            Tooltip = "Auto click when target in crosshair",
        })

        -- Additional Aimbot controls
        local VisibilityToggle = AimBox:AddToggle("bxw_aim_visibility", {
            Text = "Visibility Check",
            Default = false,
            Tooltip = "Only aim at players visible on screen",
        })
        local HitChanceSlider = AimBox:AddSlider("bxw_aim_hitchance", {
            Text = "Hit Chance %",
            Default = 100,
            Min = 1,
            Max = 100,
            Rounding = 0,
            Compact = false,
        })
        local RainbowToggle = AimBox:AddToggle("bxw_aim_rainbow", {
            Text = "Rainbow FOV",
            Default = false,
            Tooltip = "Cycle FOV circle color through the rainbow",
        })
        local RainbowSpeedSlider = AimBox:AddSlider("bxw_aim_rainbowspeed", {
            Text = "Rainbow Speed",
            Default = 5,
            Min = 1,
            Max = 10,
            Rounding = 1,
        })
        local FOVColorPicker = AimBox:AddColorPicker("bxw_aim_fovcolor", {
            Text = "FOV Color",
            Default = Color3.fromRGB(255, 255, 255),
        })
        local AimMethodDropdown = AimBox:AddDropdown("bxw_aim_method", {
            Text = "Aim Method",
            Values = { "CameraLock", "MouseDelta" },
            Default = "CameraLock",
            Multi = false,
        })
        local TargetModeDropdown = AimBox:AddDropdown("bxw_aim_targetmode", {
            Text = "Target Mode",
            Values = { "Closest To Crosshair", "Closest Distance", "Lowest Health" },
            Default = "Closest To Crosshair",
            Multi = false,
        })
        local ShowSnapToggle = AimBox:AddToggle("bxw_aim_snapline", {
            Text = "Show SnapLine",
            Default = false,
        })
        local SnapColorPicker = AimBox:AddColorPicker("bxw_aim_snapcolor", {
            Text = "SnapLine Color",
            Default = Color3.fromRGB(255, 0, 0),
        })
        local SnapThicknessSlider = AimBox:AddSlider("bxw_aim_snapthick", {
            Text = "SnapLine Thickness",
            Default = 1,
            Min = 1,
            Max = 5,
            Rounding = 0,
        })

        -- TriggerBot advanced settings (in ExtraBox)
        local TriggerTeamToggle = ExtraBox:AddToggle("bxw_trigger_teamcheck", {
            Text = "Trigger Team Check",
            Default = true,
        })
        local TriggerWallToggle = ExtraBox:AddToggle("bxw_trigger_wallcheck", {
            Text = "Trigger Wall Check",
            Default = false,
        })
        local TriggerMethodDropdown = ExtraBox:AddDropdown("bxw_trigger_method", {
            Text = "Trigger Method",
            Values = { "Always On", "Hold Key" },
            Default = "Always On",
            Multi = false,
        })
        local TriggerFiringDropdown = ExtraBox:AddDropdown("bxw_trigger_firemode", {
            Text = "Firing Mode",
            Values = { "Single", "Burst", "Auto" },
            Default = "Single",
            Multi = false,
        })
        local TriggerFovSlider = ExtraBox:AddSlider("bxw_trigger_fov", {
            Text = "Trigger FOV",
            Default = 10,
            Min = 1,
            Max = 50,
            Rounding = 1,
        })
        local TriggerDelaySlider = ExtraBox:AddSlider("bxw_trigger_delay", {
            Text = "Trigger Delay (s)",
            Default = 0.05,
            Min = 0,
            Max = 1,
            Rounding = 2,
        })
        local TriggerHoldSlider = ExtraBox:AddSlider("bxw_trigger_hold", {
            Text = "Trigger HoldTime (s)",
            Default = 0.05,
            Min = 0.01,
            Max = 0.5,
            Rounding = 2,
        })
        local TriggerReleaseSlider = ExtraBox:AddSlider("bxw_trigger_release", {
            Text = "Trigger ReleaseTime (s)",
            Default = 0.05,
            Min = 0.01,
            Max = 0.5,
            Rounding = 2,
        })

        -- FOV circle drawing
        local AimbotFOVCircle = Drawing.new("Circle")
        AimbotFOVCircle.Transparency = 0.5
        AimbotFOVCircle.Filled = false
        AimbotFOVCircle.Thickness = 1
        AimbotFOVCircle.Color = Color3.fromRGB(255, 255, 255)

        -- Snap line object for aimbot
        local AimbotSnapLine = Drawing.new("Line")
        AimbotSnapLine.Transparency = 0.7
        AimbotSnapLine.Visible = false

        -- Rainbow hue accumulator for FOV color cycling
        local rainbowHue = 0

        -- Aimbot update loop
        local function getClosestTarget()
            local cam = Workspace.CurrentCamera
            local mousePos = UserInputService:GetMouseLocation()
            local closestPlr = nil
            local closestDist = FOVSlider.Value * 15 -- convert FOV degrees to pixel radius approx
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local hum  = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart") or char and char:FindFirstChild("Torso") or char and char:FindFirstChild("UpperTorso")
                    if hum and hum.Health > 0 and root then
                        -- team check
                        local skip = false
                        if AimTeamCheck.Value then
                            if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then
                                skip = true
                            end
                        end
                        if not skip then
                            local aimPartName = AimPartDropdown.Value
                            local aimPart = nil
                            if aimPartName == "Head" then
                                aimPart = char:FindFirstChild("Head")
                            elseif aimPartName == "Torso" then
                                aimPart = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                            elseif aimPartName == "HumanoidRootPart" then
                                aimPart = root
                            else
                                -- Closest part to crosshair
                                local minPartDist = math.huge
                                for _, part in ipairs(char:GetChildren()) do
                                    if part:IsA("BasePart") then
                                        local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                                        if onScreen then
                                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                                            if dist < minPartDist then
                                                minPartDist = dist
                                                aimPart = part
                                            end
                                        end
                                    end
                                end
                            end
                            if aimPart then
                                local screenPos, onScreen = cam:WorldToViewportPoint(aimPart.Position)
                                if onScreen then
                                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                                    if dist < closestDist then
                                        closestDist = dist
                                        closestPlr = { player = plr, part = aimPart }
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return closestPlr
        end

        -- manage triggerbot click
        local function performClick()
            -- some executors provide mouse1click, fallback to VirtualUser
            pcall(function()
                mouse1click()
            end)
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton1(Vector2.new())
            end)
        end

        AddConnection(RunService.RenderStepped:Connect(function()
            -- update FOV circle and snap line colors
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local mouseLoc = UserInputService:GetMouseLocation()

            -- Rainbow or static FOV color
            if ShowFovToggle.Value and AimbotToggle.Value then
                AimbotFOVCircle.Visible = true
                AimbotFOVCircle.Radius = FOVSlider.Value * 15
                AimbotFOVCircle.Position = mouseLoc
                if RainbowToggle and RainbowToggle.Value then
                    rainbowHue = (rainbowHue or 0) + (RainbowSpeedSlider.Value / 360)
                    if rainbowHue > 1 then rainbowHue = rainbowHue - 1 end
                    AimbotFOVCircle.Color = Color3.fromHSV(rainbowHue, 1, 1)
                else
                    AimbotFOVCircle.Color = FOVColorPicker.Value
                end
            else
                AimbotFOVCircle.Visible = false
            end

            -- hide snap line by default
            AimbotSnapLine.Visible = false

            -- return if aimbot off
            if not AimbotToggle.Value then
                return
            end

            -- find target based on mode and FOV
            local bestPlr = nil
            local bestScore = math.huge
            local myRoot = getRootPart()
            if myRoot then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then
                        local char = plr.Character
                        local hum  = char and char:FindFirstChildOfClass("Humanoid")
                        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
                        if hum and hum.Health > 0 and root then
                            -- team check
                            local skip = false
                            if AimTeamCheck.Value then
                                if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then
                                    skip = true
                                end
                            end
                            if not skip then
                                -- compute 2D distance to crosshair
                                local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
                                if onScreen then
                                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mouseLoc).Magnitude
                                    local fovLimit = FOVSlider.Value * 15
                                    if screenDist <= fovLimit then
                                        -- visibility check
                                        if VisibilityToggle and VisibilityToggle.Value then
                                            local rayParams = RaycastParams.new()
                                            rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                            rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                            local dir = (root.Position - cam.CFrame.Position)
                                            local hit = Workspace:Raycast(cam.CFrame.Position, dir, rayParams)
                                            if hit and hit.Instance and not hit.Instance:IsDescendantOf(char) then
                                                goto continueTarget3
                                            end
                                        end
                                        -- compute score based on target mode
                                        local score = screenDist
                                        local mode = TargetModeDropdown and TargetModeDropdown.Value or "Closest To Crosshair"
                                        if mode == "Closest Distance" then
                                            score = (root.Position - myRoot.Position).Magnitude
                                        elseif mode == "Lowest Health" then
                                            score = hum.Health
                                        end
                                        if score < bestScore then
                                            bestScore = score
                                            bestPlr = { player = plr, part = root, screenPos = screenPos, health = hum.Health }
                                        end
                                    end
                                end
                            end
                        end
                    end
                    ::continueTarget3::
                end
            end

            if bestPlr then
                -- apply hit chance
                local chance = HitChanceSlider and HitChanceSlider.Value or 100
                if math.random(0, 100) <= chance then
                    local aimPart = bestPlr.part
                    local camPos = cam.CFrame.Position
                    local aimDir = (aimPart.Position - camPos).Unit
                    -- handle aim method
                    if AimMethodDropdown and AimMethodDropdown.Value == "MouseDelta" then
                        local sPos = bestPlr.screenPos
                        local delta = (Vector2.new(sPos.X, sPos.Y) - mouseLoc)
                        -- scale by smoothing
                        local smooth = SmoothSlider.Value
                        delta = delta * smooth
                        pcall(function()
                            mousemoverel(delta.X, delta.Y)
                        end)
                    else
                        -- camera lock (default)
                        local newCFrame = CFrame.new(camPos, camPos + aimDir)
                        local smooth = SmoothSlider.Value
                        cam.CFrame = cam.CFrame:Lerp(newCFrame, smooth)
                    end

                    -- update snap line
                    if ShowSnapToggle and ShowSnapToggle.Value then
                        AimbotSnapLine.Visible = true
                        AimbotSnapLine.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                        AimbotSnapLine.To = Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y)
                        AimbotSnapLine.Color = SnapColorPicker.Value
                        AimbotSnapLine.Thickness = SnapThicknessSlider.Value
                    end

                    -- triggerbot implementation
                    if TriggerbotToggle and TriggerbotToggle.Value then
                        -- FOV check for trigger
                        local tFov = (TriggerFovSlider and TriggerFovSlider.Value or 10) * 15
                        local tDist = (Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y) - mouseLoc).Magnitude
                        if tDist <= tFov then
                            -- additional checks: team & wall
                            local tSkip = false
                            if TriggerTeamToggle and TriggerTeamToggle.Value then
                                if bestPlr.player ~= LocalPlayer and LocalPlayer.Team and bestPlr.player.Team and LocalPlayer.Team == bestPlr.player.Team then
                                    tSkip = true
                                end
                            end
                            if not tSkip and TriggerWallToggle and TriggerWallToggle.Value then
                                local rp2 = RaycastParams.new()
                                rp2.FilterDescendantsInstances = { bestPlr.player.Character, LocalPlayer.Character }
                                rp2.FilterType = Enum.RaycastFilterType.Blacklist
                                local dir2 = (aimPart.Position - camPos)
                                local hit2 = Workspace:Raycast(camPos, dir2, rp2)
                                if hit2 and hit2.Instance and not hit2.Instance:IsDescendantOf(bestPlr.player.Character) then
                                    tSkip = true
                                end
                            end
                            if not tSkip then
                                -- handle trigger fire based on mode
                                local fireMode = TriggerFiringDropdown and TriggerFiringDropdown.Value or "Single"
                                local method   = TriggerMethodDropdown and TriggerMethodDropdown.Value or "Always On"
                                -- check hold key if required (use RightMouseButton as default)
                                local holdAllowed = true
                                if method == "Hold Key" then
                                    holdAllowed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                                end
                                if holdAllowed then
                                    local delayTime   = TriggerDelaySlider and TriggerDelaySlider.Value or 0
                                    local holdTime    = TriggerHoldSlider and TriggerHoldSlider.Value or 0.05
                                    local releaseTime = TriggerReleaseSlider and TriggerReleaseSlider.Value or 0.05
                                    task.spawn(function()
                                        task.wait(delayTime)
                                        if fireMode == "Single" then
                                            performClick()
                                        elseif fireMode == "Burst" then
                                            for i=1,3 do
                                                performClick()
                                                task.wait(holdTime / 3)
                                            end
                                        elseif fireMode == "Auto" then
                                            local t0 = tick()
                                            while tick() - t0 < holdTime do
                                                performClick()
                                                task.wait(0.05)
                                            end
                                            task.wait(releaseTime)
                                        end
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
    -- 4.5 Misc & System Tab
    ------------------------------------------------
    do
        local MiscTab = Tabs.Misc

        local MiscLeft  = MiscTab:AddLeftGroupbox("Game Tools", "tool")
        local MiscRight = MiscTab:AddRightGroupbox("Environment", "sun")

        -- Anti AFK toggle
        local antiAfkConn
        local AntiAfkToggle = MiscLeft:AddToggle("bxw_anti_afk", {
            Text = "Anti-AFK",
            Default = true,
            Tooltip = "Prevent getting kicked for idling",
        })
        AntiAfkToggle:OnChanged(function(state)
            if state then
                if antiAfkConn then
                    antiAfkConn:Disconnect()
                    antiAfkConn = nil
                end
                antiAfkConn = AddConnection(LocalPlayer.Idled:Connect(function()
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new())
                    end)
                end))
            else
                if antiAfkConn then
                    antiAfkConn:Disconnect()
                    antiAfkConn = nil
                end
            end
        end)

        -- Gravity slider
        local defaultGravity = Workspace.Gravity
        local GravitySlider = MiscRight:AddSlider("bxw_gravity", {
            Text = "Gravity",
            Default = defaultGravity,
            Min = 0,
            Max = 300,
            Rounding = 0,
            Compact = false,
            Callback = function(value)
                Workspace.Gravity = value
            end,
        })
        MiscRight:AddButton("Reset Gravity", function()
            Workspace.Gravity = defaultGravity
            GravitySlider:SetValue(defaultGravity)
        end)

        -- No Fog toggle
        local fogDefaults = {
            FogStart = game.Lighting.FogStart,
            FogEnd   = game.Lighting.FogEnd,
        }
        local NoFogToggle = MiscRight:AddToggle("bxw_nofog", {
            Text = "No Fog",
            Default = false,
        })
        NoFogToggle:OnChanged(function(state)
            if state then
                fogDefaults.FogStart = game.Lighting.FogStart
                fogDefaults.FogEnd   = game.Lighting.FogEnd
                game.Lighting.FogStart = 0
                game.Lighting.FogEnd   = 1e10
            else
                game.Lighting.FogStart = fogDefaults.FogStart or 0
                game.Lighting.FogEnd   = fogDefaults.FogEnd   or 1e10
            end
        end)

        -- Brightness slider
        local defaultBrightness = game.Lighting.Brightness
        local BrightnessSlider = MiscRight:AddSlider("bxw_brightness", {
            Text = "Brightness",
            Default = defaultBrightness,
            Min = 0,
            Max = 10,
            Rounding = 1,
            Compact = false,
            Callback = function(value)
                game.Lighting.Brightness = value
            end,
        })
        MiscRight:AddButton("Reset Brightness", function()
            game.Lighting.Brightness = defaultBrightness
            BrightnessSlider:SetValue(defaultBrightness)
        end)

        -- Ambient color picker
        local AmbientColorPicker = MiscRight:AddColorPicker("bxw_ambient_color", {
            Text = "Ambient Color",
            Default = game.Lighting.Ambient,
        })
        AmbientColorPicker:OnChanged(function(col)
            game.Lighting.Ambient = col
        end)

        -- Additional Game Utilities and Fun features
        MiscLeft:AddDivider()
        MiscLeft:AddLabel("Fun & Utility")

        -- SpinBot
        local spinConn
        local SpinToggle = MiscLeft:AddToggle("bxw_spinbot", {
            Text = "SpinBot",
            Default = false,
            Tooltip = "Rotate your character continuously",
        })
        local SpinSpeedSlider = MiscLeft:AddSlider("bxw_spin_speed", {
            Text = "Spin Speed",
            Default = 5,
            Min = 0.1,
            Max = 10,
            Rounding = 1,
            Compact = false,
        })
        local ReverseSpinToggle = MiscLeft:AddToggle("bxw_spin_reverse", {
            Text = "Reverse Spin",
            Default = false,
        })
        SpinToggle:OnChanged(function(state)
            if state then
                if spinConn then
                    spinConn:Disconnect()
                end
                spinConn = AddConnection(RunService.RenderStepped:Connect(function(dt)
                    local root = getRootPart()
                    if root then
                        local dir = ReverseSpinToggle.Value and -1 or 1
                        -- rotate small step each frame based on speed and delta time
                        local step = (SpinSpeedSlider.Value or 5) * dir * dt * math.pi
                        root.CFrame = root.CFrame * CFrame.Angles(0, step, 0)
                    end
                end))
            else
                if spinConn then
                    spinConn:Disconnect()
                    spinConn = nil
                end
            end
        end)

        -- Anti Fling
        local antiFlingConn
        local AntiFlingToggle2 = MiscLeft:AddToggle("bxw_antifling", {
            Text = "Anti Fling",
            Default = false,
            Tooltip = "Stop extreme velocity applied by other players",
        })
        AntiFlingToggle2:OnChanged(function(state)
            if state then
                if antiFlingConn then
                    antiFlingConn:Disconnect()
                end
                antiFlingConn = AddConnection(RunService.Stepped:Connect(function()
                    local root = getRootPart()
                    if root then
                        if root.AssemblyLinearVelocity.Magnitude > 80 then
                            root.AssemblyLinearVelocity = Vector3.zero
                        end
                        if root.AssemblyAngularVelocity.Magnitude > 80 then
                            root.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                end))
            else
                if antiFlingConn then
                    antiFlingConn:Disconnect()
                    antiFlingConn = nil
                end
            end
        end)

        -- Jerk Tool
        local jerkTool
        local JerkToggle = MiscLeft:AddToggle("bxw_jerktool", {
            Text = "Jerk Tool",
            Default = false,
            Tooltip = "Tool that applies force on clicked parts",
        })
        JerkToggle:OnChanged(function(state)
            if state then
                if jerkTool then
                    jerkTool:Destroy()
                end
                jerkTool = Instance.new("Tool")
                jerkTool.Name = "JerkTool"
                jerkTool.RequiresHandle = false
                jerkTool.Activated:Connect(function()
                    local mouse = LocalPlayer:GetMouse()
                    local target = mouse.Target
                    if target and target:IsA("BasePart") then
                        local vel = Instance.new("BodyVelocity")
                        vel.Velocity = (mouse.Hit.LookVector) * 60
                        vel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                        vel.Parent = target
                        game.Debris:AddItem(vel, 0.25)
                    end
                end)
                jerkTool.Parent = LocalPlayer.Backpack
                Library:Notify("Jerk Tool added to Backpack", 2)
            else
                if jerkTool then
                    jerkTool:Destroy()
                    jerkTool = nil
                end
            end
        end)

        -- BTools button
        MiscLeft:AddButton("BTools", function()
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            if not backpack then
                Library:Notify("Backpack not found", 2)
                return
            end
            local function addBin(binType)
                local bin = Instance.new("HopperBin")
                bin.BinType = binType
                bin.Parent = backpack
            end
            addBin(Enum.BinType.Clone)
            addBin(Enum.BinType.Hammer)
            addBin(Enum.BinType.Grab)
            Library:Notify("BTools added to Backpack", 2)
        end)

        -- Teleport Tool button
        MiscLeft:AddButton("Teleport Tool", function()
            local tool = Instance.new("Tool")
            tool.Name = "TeleportTool"
            tool.RequiresHandle = false
            tool.Activated:Connect(function()
                local mouse = LocalPlayer:GetMouse()
                local targetPos = mouse.Hit and mouse.Hit.Position
                if targetPos then
                    local root = getRootPart()
                    if root then
                        root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                    end
                end
            end)
            tool.Parent = LocalPlayer.Backpack
            Library:Notify("Teleport Tool added to Backpack", 2)
        end)

        -- Server Hop button
        MiscLeft:AddButton("Server Hop", function()
            local TeleportService = game:GetService("TeleportService")
            pcall(function()
                TeleportService:Teleport(game.PlaceId)
            end)
        end)

        -- F3X placeholder
        MiscLeft:AddButton("F3X Tool", function()
            Library:Notify("F3X tool not implemented", 2)
        end)

        MiscLeft:AddDivider()
        -- Respawn character button
        MiscLeft:AddButton("Respawn Character", function()
            pcall(function()
                LocalPlayer:LoadCharacter()
            end)
        end)

        -- Rejoin server button
        MiscLeft:AddButton("Rejoin Server", function()
            pcall(function()
                game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end)
        end)

        -- Unload UI button
        MiscLeft:AddButton("Unload UI", function()
            pcall(function()
                Library:Unload()
            end)
        end)
    end

    ------------------------------------------------
    -- 4.6 Settings Tab (Theme & Config)
    ------------------------------------------------
    do
        local SettingsTab = Tabs.Settings
        local SettingsLeft = SettingsTab:AddLeftGroupbox("UI Settings", "settings")
        local SettingsRight = SettingsTab:AddRightGroupbox("Config & Theme", "save")

        -- Attach library to ThemeManager and SaveManager
        ThemeManager:SetLibrary(Library)
        SaveManager:SetLibrary(Library)

        -- Set folders for storing configs and themes
        local ConfigFolder = "BxB_Universal_Settings"
        SaveManager:SetFolder(ConfigFolder)
        SaveManager:SetIgnoreIndexes({ "Key Info", "Game Info" })
        ThemeManager:SetFolder(ConfigFolder)

        -- Create theme picker UI
        -- Use ThemeManager built-in UI builder
        ThemeManager:ApplyToGroupbox(SettingsRight)

        -- Config management UI
        SaveManager:BuildConfigSection(SettingsLeft)

        -- UI to reset / unload
        SettingsLeft:AddDivider()
        SettingsLeft:AddButton("Unload UI", function()
            pcall(function()
                Library:Unload()
            end)
        end)
    end
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
