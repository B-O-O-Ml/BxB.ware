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
-- ช่วยดึง Character / Humanoid / Root
local function getCharHumanoidRoot()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return end

    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")

    return char, hum, root
end

-- ค่า default movement (จะ sync อีกทีตอนเข้าเกม / character spawn)
local DefaultWalkSpeed = 16
local DefaultJumpPower = 50

local function syncDefaultsFromHumanoid()
    local _, hum = getCharHumanoidRoot()
    if hum then
        DefaultWalkSpeed = hum.WalkSpeed or 16

        if hum.UseJumpPower ~= false and hum.JumpPower then
            DefaultJumpPower = hum.JumpPower
        elseif hum.JumpHeight then
            DefaultJumpPower = hum.JumpHeight * 7.2
        end
    end
end

-- sync เวลา character spawn ใหม่
AddConnection(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    syncDefaultsFromHumanoid()
end))

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
-- Movement state
local InfiniteJumpEnabled = false
local FlyEnabled          = false
local NoclipEnabled       = false
local FlySpeed            = 60

local InfiniteJumpConn
local FlyConn
local NoclipConn

-- Infinite Jump
local function setInfiniteJump(enabled)
    InfiniteJumpEnabled = enabled

    if enabled and not InfiniteJumpConn then
        InfiniteJumpConn = AddConnection(UserInputService.JumpRequest:Connect(function()
            if not InfiniteJumpEnabled then return end
            local _, hum = getCharHumanoidRoot()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end))
    end
end

-- Noclip
local function setNoclip(enabled)
    NoclipEnabled = enabled

    if not NoclipConn then
        NoclipConn = AddConnection(RunService.Stepped:Connect(function()
            if not NoclipEnabled then return end

            local char = LocalPlayer.Character
            if not char then return end

            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end))
    end
end

-- Fly (basic, ใช้ WASD + Space + Ctrl)
local function setFly(enabled)
    FlyEnabled = enabled

    local _, hum = getCharHumanoidRoot()
    if hum then
        hum.PlatformStand = enabled
    end

    if enabled and not FlyConn then
        FlyConn = AddConnection(RunService.RenderStepped:Connect(function(dt)
            if not FlyEnabled then return end

            local _, hum, root = getCharHumanoidRoot()
            local cam = workspace.CurrentCamera
            if not (hum and root and cam) then return end

            local dir = Vector3.zero

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                dir += cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                dir -= cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                dir += cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                dir -= cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                dir += Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                dir -= Vector3.new(0, 1, 0)
            end

            if dir.Magnitude > 0 then
                dir = dir.Unit
                root.CFrame = root.CFrame + dir * (FlySpeed * dt)
            end
        end))
    end

    if not enabled then
        local _, hum2 = getCharHumanoidRoot()
        if hum2 then
            hum2.PlatformStand = false
        end
    end
end

-- list player เอาไว้ให้ dropdown ใช้
local function getPlayerList()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(list, plr.Name)
        end
    end
    table.sort(list)
    return list
end
  local PlayerTab = Tabs.Player

    ------------------------------------------------
    -- 4.4.1 Left: Player / Movement
    ------------------------------------------------
    local MoveBox = PlayerTab:AddLeftGroupbox("Player / Movement", "user")
    safeRichLabel(MoveBox, '<font size="14"><b>Movement</b></font>')
    MoveBox:AddDivider()

    -- sync default speed/jump จาก Humanoid ปัจจุบัน
    syncDefaultsFromHumanoid()

    -- WalkSpeed slider
    local WalkSpeedSlider = MoveBox:AddSlider("WalkSpeedSlider", {
        Text    = "WalkSpeed",
        Default = DefaultWalkSpeed,
        Min     = 8,
        Max     = 200,
        Rounding = 0,
        Callback = function(value)
            local _, hum = getCharHumanoidRoot()
            if hum then
                hum.WalkSpeed = value
            end
        end,
    })

    -- JumpPower slider
    local JumpPowerSlider = MoveBox:AddSlider("JumpPowerSlider", {
        Text    = "JumpPower",
        Default = DefaultJumpPower,
        Min     = 20,
        Max     = 200,
        Rounding = 0,
        Callback = function(value)
            local _, hum = getCharHumanoidRoot()
            if not hum then return end

            if hum.UseJumpPower ~= false then
                hum.JumpPower = value
            else
                hum.JumpHeight = value / 7.2
            end
        end,
    })

    MoveBox:AddDivider()

    -- Infinite Jump toggle
    local InfJumpToggle = MoveBox:AddToggle("InfiniteJumpToggle", {
        Text    = "Infinite Jump",
        Default = false,
        Callback = function(state)
            setInfiniteJump(state)
        end,
    })

    -- Fly toggle
    local FlyToggle = MoveBox:AddToggle("FlyToggle", {
        Text    = "Fly (WASD + Space/Ctrl)",
        Default = false,
        Callback = function(state)
            setFly(state)
        end,
    })

    -- Fly speed slider (แค่เปลี่ยนค่าตัวแปร FlySpeed)
    local FlySpeedSlider = MoveBox:AddSlider("FlySpeedSlider", {
        Text    = "Fly Speed",
        Default = FlySpeed,
        Min     = 10,
        Max     = 200,
        Rounding = 0,
        Callback = function(value)
            FlySpeed = value
        end,
    })

    -- Noclip toggle
    local NoclipToggle = MoveBox:AddToggle("NoclipToggle", {
        Text    = "Noclip",
        Default = false,
        Callback = function(state)
            setNoclip(state)
        end,
    })

    MoveBox:AddDivider()

    -- Reset movement
    MoveBox:AddButton("Reset Movement", function()
        syncDefaultsFromHumanoid()

        local _, hum = getCharHumanoidRoot()
        if hum then
            hum.WalkSpeed = DefaultWalkSpeed
            if hum.UseJumpPower ~= false then
                hum.JumpPower = DefaultJumpPower
            else
                hum.JumpHeight = DefaultJumpPower / 7.2
            end
        end

        setInfiniteJump(false)
        setFly(false)
        setNoclip(false)

        if InfJumpToggle and InfJumpToggle.SetValue then InfJumpToggle:SetValue(false) end
        if FlyToggle and FlyToggle.SetValue     then FlyToggle:SetValue(false)     end
        if NoclipToggle and NoclipToggle.SetValue then NoclipToggle:SetValue(false) end
    end)

    ------------------------------------------------
    -- 4.4.2 Right: Teleport / Utility
    ------------------------------------------------
    local UtilBox = PlayerTab:AddRightGroupbox("Teleport / Utility", "map-pin")
    safeRichLabel(UtilBox, '<font size="14"><b>Teleport / Utility</b></font>')
    UtilBox:AddDivider()

    -- Teleport Player dropdown
    local TeleportDropdown

    TeleportDropdown = UtilBox:AddDropdown("TeleportPlayerDropdown", {
        Text   = "Teleport to Player",
        Values = getPlayerList(),
        Multi  = false,
        Callback = function(selected)
            if not selected or selected == "" then return end

            local target = Players:FindFirstChild(selected)
            if not target or not target.Character then return end

            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
                              or target.Character:FindFirstChild("Torso")
            local _, _, myRoot = getCharHumanoidRoot()
            if myRoot and targetRoot then
                myRoot.CFrame = targetRoot.CFrame + targetRoot.CFrame.LookVector * 3
            end
        end,
    })

    UtilBox:AddButton("Refresh Player List", function()
        if TeleportDropdown and TeleportDropdown.SetValues then
            TeleportDropdown:SetValues(getPlayerList())
        end
    end)

    -- auto refresh เมื่อมีคนเข้า/ออก
    AddConnection(Players.PlayerAdded:Connect(function()
        if TeleportDropdown and TeleportDropdown.SetValues then
            TeleportDropdown:SetValues(getPlayerList())
        end
    end))
    AddConnection(Players.PlayerRemoving:Connect(function()
        if TeleportDropdown and TeleportDropdown.SetValues then
            TeleportDropdown:SetValues(getPlayerList())
        end
    end))

    UtilBox:AddDivider()

    -- FOV changer
    local cam = workspace.CurrentCamera
    local DefaultFOV = cam and cam.FieldOfView or 70

    local FOVSlider = UtilBox:AddSlider("FOVSlider", {
        Text    = "Field of View",
        Min     = 40,
        Max     = 120,
        Default = DefaultFOV,
        Rounding = 0,
        Callback = function(value)
            local currentCam = workspace.CurrentCamera
            if currentCam then
                currentCam.FieldOfView = value
            end
        end,
    })

    UtilBox:AddButton("Reset FOV", function()
        local currentCam = workspace.CurrentCamera
        if currentCam then
            currentCam.FieldOfView = DefaultFOV
        end
        if FOVSlider and FOVSlider.SetValue then
            FOVSlider:SetValue(DefaultFOV)
        end
    end)
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
