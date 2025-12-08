--// BxB.ware MainHub - Skeleton (ตามโครง Obsidian Example) + Mock data
--// ใช้ทดสอบ UI / Layout ไม่ต้องผ่าน Key UI ก่อน

------------------------------------------------------------
-- 0. Exec abstraction (ใช้แทนการเรียก executor API ตรง ๆ)
------------------------------------------------------------

local function CreateExec()
    local Exec = {}

    function Exec.HttpGet(url)
        local ok, res

        if syn and syn.request then
            ok, res = pcall(function()
                return syn.request({ Url = url, Method = "GET" })
            end)
            if ok and res and res.Body then
                return res.Body
            end
        end

        if http_request and type(http_request) == "function" then
            ok, res = pcall(function()
                return http_request({ Url = url, Method = "GET" })
            end)
            if ok and res and res.Body then
                return res.Body
            end
        end

        if request and type(request) == "function" then
            ok, res = pcall(function()
                return request({ Url = url, Method = "GET" })
            end)
            if ok and res and res.Body then
                return res.Body
            end
        end

        if game and game.HttpGet then
            ok, res = pcall(function()
                return game:HttpGet(url)
            end)
            if ok and res then
                return res
            end
        end

        warn("[Exec] HttpGet failed for:", url)
        return ""
    end

    function Exec.HttpRequest(options)
        local req = syn and syn.request or http_request or request
        if not req then
            warn("[Exec] HttpRequest not available")
            return nil
        end

        local ok, res = pcall(req, options)
        if not ok then
            warn("[Exec] HttpRequest error:", res)
            return nil
        end
        return res
    end

    function Exec.WriteFile(path, data)
        if writefile then
            local ok, err = pcall(writefile, path, data)
            if not ok then
                warn("[Exec] WriteFile error:", err)
            end
        else
            warn("[Exec] writefile not available")
        end
    end

    function Exec.ReadFile(path)
        if readfile then
            local ok, res = pcall(readfile, path)
            if ok then
                return res
            else
                warn("[Exec] ReadFile error:", res)
            end
        else
            warn("[Exec] readfile not available")
        end
        return nil
    end

    function Exec.IsFile(path)
        if isfile then
            local ok, res = pcall(isfile, path)
            if ok then
                return res
            end
        end
        return false
    end

    function Exec.SetClipboard(text)
        if setclipboard then
            local ok, err = pcall(setclipboard, text)
            if not ok then
                warn("[Exec] SetClipboard error:", err)
            end
        else
            warn("[Exec] setclipboard not available")
        end
    end

    return Exec
end

local Exec = CreateExec()

------------------------------------------------------------
-- 1. Secure token verify (ต้องใช้ค่าเดียวกับ KeyUI.startMainHub)
------------------------------------------------------------

local SECRET_PEPPER = "BxB.ware-Universal@#$)_%@#^()$@%_)+%(@"  -- ต้องเหมือนฝั่ง KeyUI

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
    -- เดาโครง keydata: ปรับชื่อให้ตรงของจริงได้
    local k    = tostring(keydata.key or keydata.Key or "")
    local hw   = tostring(keydata.hwid_hash or keydata.HWID or "")
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

------------------------------------------------------------
-- 2. MainHub ฟังก์ชันหลัก (จะใช้ Exec + keydata)
------------------------------------------------------------

local function MainHub(ExecObj, keydata, authToken)
    --------------------------------------------------------
    -- 2.1 ตรวจ authToken + Exec + keydata แบบเบื้องต้น
    --------------------------------------------------------
    if type(authToken) ~= "string" then
        warn("[MainHub] Missing auth token, abort")
        return
    end

    if type(keydata) ~= "table" then
        warn("[MainHub] keydata invalid (not table)")
        return
    end

    -- สร้าง token ที่ "ควรจะเป็น" จาก keydata เดียวกัน
    local expected = buildExpectedToken(keydata)

    if authToken ~= expected then
        warn("[MainHub] Invalid auth token, abort")
        return
    end

    if type(ExecObj) ~= "table" or type(ExecObj.HttpGet) ~= "function" then
        warn("[MainHub] Exec invalid")
        return
    end

    if type(keydata.key) ~= "string" then
        warn("[MainHub] keydata.key invalid")
        return
    end

    local Exec = ExecObj

    --------------------------------------------------------
    -- 2.2 Role system (ตาม spec: free < user < premium < vip < staff < owner)
    --------------------------------------------------------
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

    keydata.role = NormalizeRole(keydata.role)

    local function RoleAtLeast(requiredRole)
        local have  = NormalizeRole(keydata.role)
        local need  = NormalizeRole(requiredRole)
        local hPrio = RolePriority[have] or 0
        local nPrio = RolePriority[need] or 999
        return hPrio >= nPrio
    end

    local function GetRoleLabel(role)
        role = NormalizeRole(role)
        if role == "free" then
            return "<font color=\"#A0A0A0\">Free</font>"
        elseif role == "user" then
            return "<font color=\"#FFFFFF\">User</font>"
        elseif role == "premium" then
            return "<font color=\"#FFD700\">Premium</font>"
        elseif role == "vip" then
            return "<font color=\"#FF00FF\">VIP</font>"
        elseif role == "staff" then
            return "<font color=\"#00FFFF\">Staff</font>"
        elseif role == "owner" then
            return "<font color=\"#FF4444\">Owner</font>"
        end
        return "<font color=\"#A0A0A0\">Unknown</font>"
    end

    --------------------------------------------------------
    -- 3. โหลด Library / ThemeManager / SaveManager (ผ่าน Exec)
    --    ตรงนี้ยึดโครงของ Example_All เป็นหลัก :contentReference[oaicite:4]{index=4}
    --------------------------------------------------------
    -- TODO: เปลี่ยน repo ให้เป็นของคุณเองในภายหลัง
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    local Library = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    local Options = Library.Options
    local Toggles = Library.Toggles

    --------------------------------------------------------
    -- 3.1 DPI / MinSize / CornerRadius (mobile-friendly) :contentReference[oaicite:5]{index=5}
    --------------------------------------------------------
    if Library.IsMobile then
        Library.DPIScale = 1.1
        Library.MinSize = Vector2.new(480, 260)
    else
        Library.DPIScale = 1
        Library.MinSize = Vector2.new(480, 360)
    end

    Library.CornerRadius = 4

    --------------------------------------------------------
    -- 3.2 สร้าง Window หลัก (ใช้เมธอด/option แบบเดียวกับ Example_All) :contentReference[oaicite:6]{index=6}
    --------------------------------------------------------
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

    --------------------------------------------------------
    -- 4. Tabs
    --------------------------------------------------------
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

    --------------------------------------------------------
    -- 5. Core State (ใช้ต่อยอดภายหลัง)
    --------------------------------------------------------
    local State = {
        Player = {
            WalkSpeedEnabled = false,
            WalkSpeedValue   = 16,
            JumpEnabled      = false,
            JumpValue        = 50,
            InfiniteJump     = false,
            Fly              = false,
            FlySpeed         = 60,
            NoClip           = false,
            SpinBot          = false, -- VIP+
            AntiAim          = false, -- VIP+
            AutoRun          = false,
            ClickTP          = false, -- User+
        },

        ESP = {
            Enabled        = false,
            Distance       = 200,
            MaxDistance    = 200,
            Box            = true,
            Name           = true,
            Health         = true,
            Tracer         = true,
            UseHighlight   = false,
            Skeleton       = false,
            HeadDot        = false,
            LookTracer     = false,
            TeamCheck      = true,
            VisibleOnly    = false,
            WallCheck      = false,

            ColorMain   = Color3.fromRGB(255, 255, 0),
            BoxColor    = Color3.fromRGB(255, 255, 255),
            NameColor   = Color3.fromRGB(255, 255, 255),
            TracerColor = Color3.fromRGB(255, 255, 255),
            ChamsColor  = Color3.fromRGB(0, 255, 255),
        },

        Aim = {
            Enabled       = false,
            Mode          = "Legit",
            AimType       = "Hold",
            AimPart       = "Head",
            FOVRadius     = 150,
            ShowFOV       = true,
            Smooth        = 0.1,
            HitChance     = 100, -- Premium+
            TeamCheck     = true,
            VisibleOnly   = true,
            IgnoreFriends = true,
            MaxDistance   = 300,

            Weights = {
                Head  = 50,
                Chest = 30,
                Arms  = 10,
                Legs  = 10,
            },
        },

        Misc = {
            AntiAFK    = false,
            Fullbright = false,
        },
    }

    --------------------------------------------------------
    -- 6. Tab: Info (Key / Role / System / ScriptInfo skeleton)
    --------------------------------------------------------
    local InfoLeft  = Tabs.Info:AddLeftGroupbox("Key / Role", "key")
    local InfoRight = Tabs.Info:AddRightGroupbox("Game / System / Script", "info")

    InfoLeft:AddLabel({
        Text = ("<b>Key:</b> %s"):format(keydata.key or "N/A"),
        DoesWrap = true,
    })

    InfoLeft:AddLabel({
        Text = "Role: " .. GetRoleLabel(keydata.role),
        DoesWrap = true,
    })

    InfoLeft:AddLabel({
        Text = ("Status: <b>%s</b>"):format(tostring(keydata.status or "unknown")),
        DoesWrap = true,
    })

    InfoLeft:AddLabel({
        Text = ("HWID Mode: <b>%s</b>"):format(keydata.bind_hwid and "HWID-locked" or "Free"),
        DoesWrap = true,
    })

    InfoLeft:AddDivider()

    InfoLeft:AddLabel({
        Text = "Expire: <i>(TODO: format expire / time left)</i>",
        DoesWrap = true,
    })

    InfoLeft:AddLabel({
        Text = "Note: <i>" .. tostring(keydata.note or "N/A") .. "</i>",
        DoesWrap = true,
    })

    InfoRight:AddLabel({
        Text = "<b>Game / System info</b>",
        Size = 18,
        DoesWrap = true,
    })

    InfoRight:AddLabel({
        Text = "Game: <i>(TODO: MarketplaceService:GetProductInfo)</i>",
        DoesWrap = true,
    })

    InfoRight:AddLabel({
        Text = "FPS / Ping / Memory: <i>(TODO: update loop)</i>",
        DoesWrap = true,
    })

    InfoRight:AddDivider()

    InfoRight:AddLabel({
        Text = "<b>Script Info</b>",
        Size = 16,
        DoesWrap = true,
    })

    InfoRight:AddLabel({
        Text = "<i>TODO: ดึง SCRIPTINFO_URL, แปลง JSON → RichText</i>",
        DoesWrap = true,
    })

    InfoRight:AddDivider()

    InfoRight:AddLabel({
        Text = "<b>Changelog</b>",
        Size = 16,
        DoesWrap = true,
    })

    InfoRight:AddLabel({
        Text = "<i>TODO: ดึง CHANGELOG_URL, แสดง entry ล่าสุด</i>",
        DoesWrap = true,
    })

    --------------------------------------------------------
    -- 7. Tab: Player (Movement / Teleport / View skeleton)
    --------------------------------------------------------
    local PlayerLeft  = Tabs.Player:AddLeftGroupbox("Movement & Character", "user")
    local PlayerRight = Tabs.Player:AddRightGroupbox("Teleport / View / Server", "map")

    PlayerLeft:AddLabel({
        Text = "<b>Movement</b>",
        Size = 18,
        DoesWrap = true,
    })

    local WalkSpeedToggle = PlayerLeft:AddToggle("Move_WalkSpeedToggle", {
        Text    = "Custom WalkSpeed",
        Default = false,
        Tooltip = "เปิดแล้วใช้ค่า WalkSpeed จาก Slider ด้านล่าง",
    })

    WalkSpeedToggle:AddKeyPicker("Move_WalkSpeedKeybind", {
        Text         = "WalkSpeed Key",
        Default      = "F",
        Mode         = "Toggle",
        SyncToggleState = true,
    })

    PlayerLeft:AddSlider("Move_WalkSpeedValue", {
        Text    = "WalkSpeed",
        Default = 16,
        Min     = 8,
        Max     = 60,
        Rounding = 0,
        Suffix   = " stud/s",
        Tooltip  = "ค่าความเร็วเดินของ player",
    })

    PlayerLeft:AddToggle("Move_JumpToggle", {
        Text    = "Custom JumpPower",
        Default = false,
        Tooltip = "เปิดแล้วใช้ JumpPower จาก input ด้านล่าง",
    })

    PlayerLeft:AddInput("Move_JumpValue", {
        Text       = "JumpPower",
        Default    = "50",
        Numeric    = true,
        Finished   = true,
        Placeholder = "50",
        Tooltip    = "กำหนด JumpPower ของ player",
    })

    PlayerLeft:AddToggle("Move_InfiniteJump", {
        Text    = "Infinite Jump",
        Default = false,
    })

    PlayerLeft:AddToggle("Move_Fly", {
        Text    = "Fly",
        Default = false,
    })

    PlayerLeft:AddSlider("Move_FlySpeed", {
        Text    = "Fly Speed",
        Default = 60,
        Min     = 10,
        Max     = 200,
        Rounding = 0,
    })

    PlayerLeft:AddToggle("Move_NoClip", {
        Text    = "NoClip",
        Default = false,
    })

    PlayerLeft:AddDivider()

    PlayerLeft:AddToggle("Move_SpinBot", {
        Text    = "SpinBot (VIP+)",
        Default = false,
        Tooltip = "ใช้เฉพาะผู้ใช้ VIP ขึ้นไป",
    })

    PlayerLeft:AddToggle("Move_AntiAim", {
        Text    = "Anti-Aim / Desync (VIP+)",
        Default = false,
        Tooltip = "ใช้เฉพาะผู้ใช้ VIP ขึ้นไป",
    })

    PlayerLeft:AddButton({
        Text = "Reset movement",
        Func = function()
            -- TODO: reset WalkSpeed / JumpPower / flags ทั้งหมด
        end,
    })

    PlayerRight:AddLabel({
        Text = "<b>Teleport / View</b>",
        Size = 18,
        DoesWrap = true,
    })

    PlayerRight:AddToggle("Move_AutoRun", {
        Text    = "Auto Run",
        Default = false,
    })

    PlayerRight:AddToggle("Move_ClickTP", {
        Text    = "Click TP (Ctrl+Click) [User+]",
        Default = false,
    })

    PlayerRight:AddDropdown("TP_PlayerList", {
        Text    = "Teleport to player",
        Values  = { "TODO: Fill with players" },
        Default = "TODO: Fill with players",
        Multi   = false,
        Searchable = true,
    })

    PlayerRight:AddButton({
        Text = "Teleport",
        Func = function()
            -- TODO: TP ไปยัง player ที่เลือก
        end,
    })

    PlayerRight:AddButton({
        Text = "Refresh players",
        Func = function()
            -- TODO: refresh รายชื่อ player ใน dropdown
        end,
    })

    PlayerRight:AddDivider()

    PlayerRight:AddToggle("View_FOVToggle", {
        Text    = "FOV Changer",
        Default = false,
    })

    PlayerRight:AddSlider("View_FOVValue", {
        Text    = "Field of View",
        Default = 70,
        Min     = 50,
        Max     = 120,
    })

    PlayerRight:AddToggle("Misc_Fullbright", {
        Text    = "Fullbright",
        Default = false,
    })

    PlayerRight:AddDivider()

    PlayerRight:AddButton({
        Text = "Rejoin",
        Func = function()
            -- TODO: รียูส TeleportService ไป server เดิม
        end,
    })

    PlayerRight:AddButton({
        Text = "Server Hop",
        Func = function()
            -- TODO: หา server ใหม่แบบง่าย ๆ แล้ว teleport
        end,
    })

    --------------------------------------------------------
    -- 8. Tab: ESP & Visuals (AddColorPicker ผ่าน Toggle เท่านั้น)
    --------------------------------------------------------
    local ESPLeft  = Tabs.ESP:AddLeftGroupbox("Player ESP", "eye")
    local ESPRight = Tabs.ESP:AddRightGroupbox("Filter / Visual", "sliders")

    ESPLeft:AddLabel({
        Text = "<b>ESP core</b>",
        Size = 18,
        DoesWrap = true,
    })

    local ESPEnabled = ESPLeft:AddToggle("ESP_Enabled", {
        Text    = "Enable ESP",
        Default = false,
        Tooltip = "เปิด/ปิด ESP (logic คุณเขียนเอง)",
    })

    -- ColorPicker หลักผูกกับ Toggle ตามโครง Example_All :contentReference[oaicite:7]{index=7}
    ESPEnabled:AddColorPicker("ESP_ColorMain", {
        Title   = "Main ESP color",
        Default = State.ESP.ColorMain,
    })

    ESPLeft:AddSlider("ESP_Distance", {
        Text    = "ESP Distance",
        Default = State.ESP.Distance,
        Min     = 50,
        Max     = 500,
        Rounding = 0,
        Suffix   = " studs",
    })

    ESPLeft:AddDivider()

    ESPLeft:AddToggle("ESP_Box",    { Text = "Box",    Default = true  })
    ESPLeft:AddToggle("ESP_Name",   { Text = "Name",   Default = true  })
    ESPLeft:AddToggle("ESP_Health", { Text = "Health", Default = true  })
    ESPLeft:AddToggle("ESP_Tracer", { Text = "Tracer", Default = true  })

    ESPLeft:AddDivider()

    ESPLeft:AddToggle("ESP_Skeleton",  { Text = "Skeleton",   Default = false })
    ESPLeft:AddToggle("ESP_HeadDot",   { Text = "Head Dot",   Default = false })
    ESPLeft:AddToggle("ESP_LookTrace", { Text = "Look Tracer",Default = false })

    ESPRight:AddLabel({
        Text = "<b>Filter / Visual</b>",
        Size = 18,
        DoesWrap = true,
    })

    ESPRight:AddToggle("ESP_TeamCheck", {
        Text    = "Team check",
        Default = true,
    })

    ESPRight:AddToggle("ESP_VisibleOnly", {
        Text    = "Visible only",
        Default = false,
    })

    ESPRight:AddToggle("ESP_WallCheck", {
        Text    = "Wall check",
        Default = false,
    })

    ESPRight:AddSlider("ESP_MaxDistance", {
        Text    = "Max distance",
        Default = State.ESP.MaxDistance,
        Min     = 50,
        Max     = 2000,
        Rounding = 0,
    })

    ESPRight:AddDivider()

    -- ถ้าต้องมีสีแยก Box / Name / Tracer / Chams → ผูก ColorPicker กับ Toggle แทน Groupbox
    local ESPBoxToggle    = ESPRight:AddToggle("ESP_BoxColorToggle",    { Text = "Custom Box color",    Default = false })
    local ESPNameToggle   = ESPRight:AddToggle("ESP_NameColorToggle",   { Text = "Custom Name color",   Default = false })
    local ESPTracerToggle = ESPRight:AddToggle("ESP_TracerColorToggle", { Text = "Custom Tracer color", Default = false })
    local ESPChamsToggle  = ESPRight:AddToggle("ESP_ChamsColorToggle",  { Text = "Custom Chams color",  Default = false })

    ESPBoxToggle:AddColorPicker("ESP_BoxColor", {
        Title   = "Box color",
        Default = State.ESP.BoxColor,
    })

    ESPNameToggle:AddColorPicker("ESP_NameColor", {
        Title   = "Name color",
        Default = State.ESP.NameColor,
    })

    ESPTracerToggle:AddColorPicker("ESP_TracerColor", {
        Title   = "Tracer color",
        Default = State.ESP.TracerColor,
    })

    ESPChamsToggle:AddColorPicker("ESP_ChamsColor", {
        Title   = "Chams color",
        Default = State.ESP.ChamsColor,
    })

    --------------------------------------------------------
    -- 9. Tab: Combat & Aimbot (Advanced skeleton)
    --------------------------------------------------------
    local CombatLeft  = Tabs.Combat:AddLeftGroupbox("Aimbot Core", "target")
    local CombatRight = Tabs.Combat:AddRightGroupbox("Targeting / Advanced", "crosshair")

    CombatLeft:AddLabel({
        Text = "<b>Aimbot core</b>",
        Size = 18,
        DoesWrap = true,
    })

    local AimToggle = CombatLeft:AddToggle("Aim_Enabled", {
        Text    = "Enable Aimbot",
        Default = false,
    })

    AimToggle:AddKeyPicker("Aim_Keybind", {
        Text    = "Aimbot Key",
        Default = "Q",
        Mode    = "Hold",
    })

    CombatLeft:AddDropdown("Aim_Mode", {
        Text    = "Mode",
        Values  = { "Legit", "Rage" },
        Default = "Legit",
        Multi   = false,
    })

    CombatLeft:AddDropdown("Aim_Type", {
        Text    = "Aim type",
        Values  = { "Hold", "Toggle" },
        Default = "Hold",
        Multi   = false,
    })

    CombatLeft:AddSlider("Aim_FOVRadius", {
        Text    = "Aimbot FOV",
        Default = State.Aim.FOVRadius,
        Min     = 10,
        Max     = 500,
        Rounding = 0,
    })

    CombatLeft:AddToggle("Aim_ShowFOV", {
        Text    = "Show FOV circle",
        Default = true,
    })

    CombatLeft:AddSlider("Aim_Smooth", {
        Text    = "Smooth",
        Default = 0.1,
        Min     = 0.01,
        Max     = 1,
        Rounding = 2,
    })

    CombatLeft:AddSlider("Aim_HitChance", {
        Text    = "Hit chance (%) [Premium+]",
        Default = State.Aim.HitChance,
        Min     = 0,
        Max     = 100,
        Rounding = 0,
    })

    CombatLeft:AddDivider()

    CombatLeft:AddToggle("Aim_TeamCheck", {
        Text    = "Team check",
        Default = true,
    })

    CombatLeft:AddToggle("Aim_VisibleOnly", {
        Text    = "Visible only",
        Default = true,
    })

    CombatLeft:AddToggle("Aim_IgnoreFriends", {
        Text    = "Ignore friends",
        Default = true,
    })

    CombatLeft:AddSlider("Aim_MaxDistance", {
        Text    = "Max distance",
        Default = State.Aim.MaxDistance,
        Min     = 50,
        Max     = 2000,
        Rounding = 0,
    })

    CombatRight:AddLabel({
        Text = "<b>Target selection</b>",
        Size = 18,
        DoesWrap = true,
    })

    CombatRight:AddDropdown("Aim_PartMode", {
        Text    = "Aim part mode",
        Values  = { "Head", "Chest", "Arms", "Legs", "Closest", "RandomWeighted" },
        Default = "Head",
        Multi   = false,
    })

    CombatRight:AddLabel({
        Text = "<b>Weighted targeting (Premium+)</b>",
        Size = 16,
        DoesWrap = true,
    })

    CombatRight:AddSlider("Aim_WHead", {
        Text    = "Head weight",
        Default = State.Aim.Weights.Head,
        Min     = 0,
        Max     = 100,
    })

    CombatRight:AddSlider("Aim_WChest", {
        Text    = "Chest weight",
        Default = State.Aim.Weights.Chest,
        Min     = 0,
        Max     = 100,
    })

    CombatRight:AddSlider("Aim_WArms", {
        Text    = "Arms weight",
        Default = State.Aim.Weights.Arms,
        Min     = 0,
        Max     = 100,
    })

    CombatRight:AddSlider("Aim_WLegs", {
        Text    = "Legs weight",
        Default = State.Aim.Weights.Legs,
        Min     = 0,
        Max     = 100,
    })

    CombatRight:AddDivider()

    CombatRight:AddLabel({
        Text = "<b>Extras</b>\n<i>TODO: Silent Aim / Triggerbot / Prediction</i>",
        DoesWrap = true,
    })

    --------------------------------------------------------
    -- 10. Tab: Misc & System
    --------------------------------------------------------
    local MiscLeft  = Tabs.Misc:AddLeftGroupbox("Misc", "tool")
    local MiscRight = Tabs.Misc:AddRightGroupbox("System / Panic", "alert-triangle")

    MiscLeft:AddToggle("Misc_AntiAFK", {
        Text    = "Anti-AFK",
        Default = false,
    })

    MiscLeft:AddButton({
        Text = "Copy Discord",
        Func = function()
            Exec.SetClipboard("https://discord.gg/YOUR_SERVER")
        end,
    })

    MiscLeft:AddButton({
        Text = "Copy GitHub",
        Func = function()
            Exec.SetClipboard("https://github.com/YOUR_REPO")
        end,
    })

    MiscRight:AddButton({
        Text = "Panic (Unload Hub)",
        Func = function()
            -- TODO: หยุด loop, ลบ Drawing/Highlight, Library:OnUnload ฯลฯ
        end,
    })

    MiscRight:AddLabel({
        Text = "<i>TODO: Dev tools / logger / debug overlay</i>",
        DoesWrap = true,
    })

    --------------------------------------------------------
    -- 11. Tab: Settings (ThemeManager / SaveManager skeleton)
    --------------------------------------------------------
    local SettingsLeft  = Tabs.Settings:AddLeftGroupbox("Theme", "palette")
    local SettingsRight = Tabs.Settings:AddRightGroupbox("Config / Keybinds", "settings")

    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("BxBware")

    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetFolder("BxBware/UniversalHub")

    SettingsLeft:AddLabel({
        Text = "<b>Theme</b>\n<i>TODO: ThemeManager:ApplyToTab(Tabs.Settings)</i>",
        DoesWrap = true,
    })

    SettingsRight:AddLabel({
        Text = "<b>Config / Keybinds</b>\n<i>TODO: SaveManager:BuildConfigSection(Tabs.Settings)</i>",
        DoesWrap = true,
    })

    SettingsRight:AddButton({
        Text = "Unload Hub",
        Func = function()
            -- TODO: เรียก Panic logic
        end,
    })

    --------------------------------------------------------
    -- 12. Watermark / Notify (แบบใน Example_All) :contentReference[oaicite:8]{index=8}
    --------------------------------------------------------
    Library:SetWatermarkVisibility(true)
    Library:SetWatermark("BxB.ware MainHub Skeleton | Loading...")

    Library:Notify("BxB.ware MainHub (Mock Skeleton) loaded", 4)

    Library:OnUnload(function()
        print("[MainHub] Unloaded")
    end)
end

return function(Exec, keydata, authToken)
    MainHub(Exec, keydata, authToken)
end

-- ถ้าเอาไปใช้ร่วมกับ Key UI จริง:
-- return function(Exec, keydata, keycheck)
--     MainHub(Exec, keydata, keycheck)
-- end
