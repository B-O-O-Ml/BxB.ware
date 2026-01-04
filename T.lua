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
local HttpService        = game:GetService("HttpService")
local StarterGui         = game:GetService("StarterGui")
local TextChatService    = game:GetService("TextChatService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CoreGui            = game:GetService("CoreGui")
local TweenService       = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Check Mobile/Touch (Universal Check)
local isMobile = UserInputService.TouchEnabled
local isPC = not isMobile

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
-- 1. Secret + Token Verify (SYNCED WITH KEYMAIN 100%)
--====================================================
local Security = {}
-- สร้าง Secret แบบแตก String เพื่อป้องกันการค้นหา (Sync จาก KeyMain)
local _s1 = "BxB.ware"
local _s2 = "-Universal"
local _s3 = "@#$)_%@#^"
local _s4 = "()$@%_)+%(@"
Security.PEPPER = _s1 .. _s2 .. _s3 .. _s4

-- ใช้ bit32 หรือ bit ตามที่มีใน Environment (Sync Logic)
local bit = bit32 or require("bit")

local function fnv1a32(str)
    local hash = 0x811C9DC5
    for i = 1, #str do
        hash = bit.bxor(hash, str:byte(i))
        hash = (hash * 0x01000193) % 0x100000000
    end
    return hash
end

local function buildExpectedToken(keydata)
    local SECRET_PEPPER = Security.PEPPER
    local k    = tostring(keydata.key or keydata.Key or "")
    local hw   = tostring(keydata.hwid_hash or keydata.HWID or "no-hwid")
    local role = tostring(keydata.role or "user")
    local datePart = os.date("%Y%m%d")
    
    -- Sync structure exact same as KeyMain
    local raw = table.concat({ SECRET_PEPPER, k, hw, role, datePart, tostring(#k) }, "|")
    local h = fnv1a32(raw)
    return ("%08X"):format(h)
end

-- Anti-Tamper: Basic Integrity Check
local function IntegrityCheck()
    if iscclosure and not iscclosure(game.HttpGet) then
        return false -- HttpGet was hooked
    end
    return true
end

--====================================================
-- 2. Role System & Helpers
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

local function MarkRisky(text)
    return text .. ' <font color="#FF5555" size="10">[RISKY]</font>'
end

-- [NEW] Device Support Tag System
local function GetDeviceTag(supportedPlatforms)
    local isSupported = true
    local tag = ""

    if isMobile then
        if supportedPlatforms and supportedPlatforms.Mobile == false then
            isSupported = false
            tag = ' <font color="#FF5555" size="11">[PC Only]</font>'
        end
    end
    if isPC then
        if supportedPlatforms and supportedPlatforms.PC == false then
             tag = ' <font color="#AAAAAA" size="11">[Mobile Only]</font>'
        end
    end
    return tag, isSupported
end

local function GetRoleTag(reqRole)
    local r = NormalizeRole(reqRole)
    if r == "premium" then return ' <font color="#FFD700" size="11">[Premium]</font>'
    elseif r == "vip" then return ' <font color="#FF00FF" size="11">[VIP]</font>'
    elseif r == "staff" then return ' <font color="#00FFFF" size="11">[Staff]</font>'
    end
    return ""
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
    if lbl and lbl.TextLabel then
        lbl.TextLabel.RichText = true
        lbl.TextLabel.TextWrapped = true
        lbl.TextLabel.AutomaticSize = Enum.AutomaticSize.Y
        lbl.TextLabel.Size = UDim2.new(1, 0, 0, 0)
        lbl.TextLabel.TextYAlignment = Enum.TextYAlignment.Top
        lbl.TextLabel.TextXAlignment = Enum.TextXAlignment.Left
    end
    return lbl
end

-- Helper Parsers (Info/Update Tabs)
local function parseChangelogBody(body, HttpService)
    if type(body) ~= "string" or body == "" then return "unknown", "No changelog data." end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(decoded) ~= "table" then return "online", body end
    
    local function esc(s) return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") end
    local status = decoded.status or "online"
    local lines = {}
    local function add(s) table.insert(lines, s) end

    if decoded.project then add(string.format("<b>%s Changelog</b>", esc(decoded.project))) end
    if decoded.latest_version then add(string.format("Latest: <font color='#55ff55'>%s</font>", esc(decoded.latest_version))) end
    
    if type(decoded.entries) == "table" then
        for _, entry in ipairs(decoded.entries) do
            add("")
            local verHeader = string.format("<b>v%s</b> <font color='#aaaaaa'>(%s)</font>", esc(entry.version), esc(entry.date))
            add(verHeader)
            if entry.title then add("<i>" .. esc(entry.title) .. "</i>") end
            if type(entry.highlights) == "table" then for _, h in ipairs(entry.highlights) do add("• " .. esc(h)) end end
            if type(entry.changes) == "table" then
                local function addChangeGroup(label, color, items)
                    if type(items) == "table" and #items > 0 then
                        add(string.format("<font color='%s'>%s</font>", color, label))
                        for _, item in ipairs(items) do add(" - " .. esc(item)) end
                    end
                end
                addChangeGroup("[+] Added", "#55ff55", entry.changes.added)
                addChangeGroup("[*] Changed", "#55aaff", entry.changes.changed)
                addChangeGroup("[!] Fixed", "#ffcc66", entry.changes.fixed)
                addChangeGroup("[-] Removed", "#ff5555", entry.changes.removed)
            end
            add("________________________")
        end
    end
    return status, table.concat(lines, "\n")
end

local function parseScriptInfo(body, HttpService)
    if type(body) ~= "string" or body == "" then return "No info data." end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then return "Failed to parse JSON." end
    
    local lines = {}
    local function add(s) table.insert(lines, s) end
    local function recurse(tbl, indent)
        for k, v in pairs(tbl) do
            local keyStr = tostring(k)
            local indentStr = string.rep("  ", indent)
            if type(v) == "table" then
                add(string.format("%s<b>%s:</b>", indentStr, keyStr))
                recurse(v, indent + 1)
            else
                add(string.format("%s<b>%s:</b> <font color='#dddddd'>%s</font>", indentStr, keyStr, tostring(v)))
            end
        end
    end
    add("<b>Script Information</b>")
    add("________________________")
    recurse(decoded, 0)
    return table.concat(lines, "\n")
end

--====================================================
-- 4. MainHub Function
--====================================================

local function MainHub(Exec, keydata, authToken)
    ---------------------------------------------
    -- 4.1 ตรวจ Security
    ---------------------------------------------
    if not IntegrityCheck() then
        LocalPlayer:Kick("Security Error: Environment Tampered.")
        return
    end

    if type(Exec) ~= "table" or type(Exec.HttpGet) ~= "function" then
        warn("[MainHub] Exec invalid")
        return
    end
    
    -- Token Check
    local expected = buildExpectedToken(keydata)
    if authToken ~= expected then
        -- DEBUG PRINT FOR USER
        warn("[MainHub] Security Handshake Failed!")
        print("[MainHub] Expected Token:", expected)
        print("[MainHub] Received Token:", authToken)
        print("[MainHub] KeyData Used:", HttpService:JSONEncode(keydata))
        
        LocalPlayer:Kick("Security Error: Invalid Handshake.")
        return
    end

    -- Environment Flag Check
    if getgenv then
        local flagName = keydata._auth_flag
        if not flagName or not getgenv()[flagName] then
            LocalPlayer:Kick("Security Error: Direct execution blocked.")
            return
        end
        getgenv()[flagName] = nil
    end

    -- Drawing Storage
    local crosshairLines = nil
    local AimbotFOVCircle = nil
    local AimbotSnapLine = nil
    local espDrawings = {}
    local radarDrawings = { points = {}, outline = nil, line = nil, bg = nil }

    keydata.role = NormalizeRole(keydata.role)
    local MyRole = keydata.role

    ---------------------------------------------
    -- 4.2 โหลด Obsidian Library
    ---------------------------------------------
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library      = loadstring(Exec.HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(Exec.HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(Exec.HttpGet(repo .. "addons/SaveManager.lua"))()

    local Options = Library.Options
    local Toggles = Library.Toggles

    local function NotifyAction(feature, state)
        if Toggles.ForceNotify and Toggles.ForceNotify.Value then
            local s = state and "Enabled" or "Disabled"
            Library:Notify(string.format("%s: %s", feature, s), 1.5)
        end
    end

    local function IsLocked(reqRole) return not RoleAtLeast(MyRole, reqRole) end
    local function GetLockTooltip(reqRole) return "Requires " .. string.upper(reqRole) .. " rank or higher" end

    -- Smart UI Wrappers (Device + Role Logic)
    local function AddSmartToggle(groupbox, id, config)
        local reqRole = config.Role or "free"
        local platforms = config.Platforms
        local baseText = config.Text or id
        local baseTooltip = config.Tooltip or ""
        
        local isLocked = IsLocked(reqRole)
        local roleTag = GetRoleTag(reqRole)
        local devTag, isDevSupported = GetDeviceTag(platforms)
        
        config.Text = baseText .. roleTag .. devTag
        
        if isLocked then
            config.Disabled = true
            config.Default = false
            config.Text = baseText .. " <font color='#FF0000'>[LOCKED]</font>" .. devTag
            config.Tooltip = GetLockTooltip(reqRole)
        elseif not isDevSupported then
             config.Tooltip = (baseTooltip ~= "" and baseTooltip .. "\n" or "") .. "Feature may not work on your device."
        else
             config.Tooltip = baseTooltip
        end
        config.Role = nil
        config.Platforms = nil
        return groupbox:AddToggle(id, config)
    end

    local function AddSmartButton(groupbox, text, callback, config)
        config = config or {}
        local reqRole = config.Role or "free"
        local platforms = config.Platforms
        
        local isLocked = IsLocked(reqRole)
        local roleTag = GetRoleTag(reqRole)
        local devTag, isDevSupported = GetDeviceTag(platforms)
        local finalText = text .. roleTag .. devTag
        
        if isLocked then
            return groupbox:AddButton(text .. " [LOCKED]", function() Library:Notify(GetLockTooltip(reqRole), 3) end)
        else
            local btn = groupbox:AddButton(finalText, function()
                if not isDevSupported then Library:Notify("Feature not supported on device.", 2) end
                callback()
            end)
            if config.Tooltip then pcall(function() btn:SetTooltip(config.Tooltip) end) end
            return btn
        end
    end

    -- Window Creation
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

    local Tabs = {
        Info = Window:AddTab({ Name = "Info", Icon = "info", Description = "Key / Script / System info" }),
        Updates = Window:AddTab({ Name = "Updates", Icon = "rss", Description = "Changelogs & News" }),
        Player = Window:AddTab({ Name = "Player", Icon = "user", Description = "Movement / Teleport / View" }),
        ESP = Window:AddTab({ Name = "ESP & Visuals", Icon = "eye", Description = "Player ESP / Visual settings" }),
        Combat = Window:AddTab({ Name = "Combat & Aimbot", Icon = "target", Description = "Aimbot / target selection" }),
        Server = Window:AddTab({ Name = "Server", Icon = "server", Description = "Hop / Rejoin / Anti-AFK" }),
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
    -- Info Tab (Updated)
    ------------------------------------------------
    local InfoTab = Tabs.Info
    local startSessionTime = tick()
    local KeyBox = InfoTab:AddLeftGroupbox("Key Info", "key-round")
    local StatsBox = safeAddRightGroupbox(InfoTab, "User Profile & Stats", "bar-chart")

    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()
    local rawKey = tostring(keydata.key or "N/A")
    local maskedKey = #rawKey > 4 and string.format("%s-****%s", rawKey:sub(1, 4), rawKey:sub(-3)) or rawKey

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    local RoleLabel = safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", GetRoleLabel(keydata.role)))
    local StatusLabel = safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", tostring(keydata.status or "active")))
    local HWIDLabel = safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    local NoteLabel = safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", tostring(keydata.note or "-")))
    local CreatedLabel = safeRichLabel(KeyBox, "<b>Created at:</b> Loading...")
    local ExpireLabel = safeRichLabel(KeyBox, "<b>Expire:</b> Loading...")
    local TimeLeftLabel = safeRichLabel(KeyBox, "<b>Time left:</b> Loading...")

    safeRichLabel(StatsBox, string.format("<b>Welcome, %s</b>", LocalPlayer.DisplayName))
    safeRichLabel(StatsBox, string.format("User ID: %d", LocalPlayer.UserId))
    safeRichLabel(StatsBox, string.format("Account Age: %d days", LocalPlayer.AccountAge))
    safeRichLabel(StatsBox, string.format("Premium: %s", LocalPlayer.MembershipType.Name))
    StatsBox:AddDivider()
    local SessionLabel = safeRichLabel(StatsBox, "Session Time: 00:00:00")
    local TeamLabel = safeRichLabel(StatsBox, "Team: None")
    local PositionLabel = safeRichLabel(StatsBox, "Pos: (0, 0, 0)")
    local ServerRegionLabel = safeRichLabel(StatsBox, "Server Region: Unknown")

    local DiagBox = InfoTab:AddLeftGroupbox("System Diagnostics", "activity")
    local function getCheckColor(bool) return bool and '<font color="#55ff55">PASS</font>' or '<font color="#ff5555">FAIL</font>' end
    safeRichLabel(DiagBox, string.format("Drawing API: %s", getCheckColor(Drawing)))
    safeRichLabel(DiagBox, string.format("Hook Metamethod: %s", getCheckColor(hookmetamethod)))
    safeRichLabel(DiagBox, string.format("GetGenv: %s", getCheckColor(getgenv)))
    safeRichLabel(DiagBox, string.format("Request/HttpGet: %s", getCheckColor(request or http_request or (syn and syn.request) or Exec.HttpGet)))

    -- Stats Loop
    task.spawn(function()
        while true do
            local elapsed = tick() - startSessionTime
            local h = math.floor(elapsed / 3600)
            local m = math.floor((elapsed % 3600) / 60)
            local s = elapsed % 60
            SessionLabel.TextLabel.Text = string.format("Session Time: %02d:%02d:%02d", h, m, s)
            
            local root = getRootPart()
            if root then
                 local p = root.Position
                 PositionLabel.TextLabel.Text = string.format("Pos: (%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
            end
            local team = LocalPlayer.Team
            local tName = team and team.Name or "Neutral"
            local tColor = team and team.TeamColor.Color or Color3.new(1,1,1)
            TeamLabel.TextLabel.Text = string.format("Team: <font color='#%s'>%s</font>", tColor:ToHex(), tName)
            task.wait(1)
        end
    end)
    
    task.spawn(function()
        pcall(function()
            local region = game:GetService("LocalizationService").RobloxLocaleId
            ServerRegionLabel.TextLabel.Text = "Client Locale: " .. tostring(region)
        end)
    end)
    
    task.spawn(function()
         local UpdatesTab = Tabs.Updates
         local ChangelogBox = UpdatesTab:AddLeftGroupbox("Latest Changes", "rss")
         local ScriptInfoBox = UpdatesTab:AddRightGroupbox("Script Information", "file-text")
         
         local ChangeLogUrl = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/changelog.json"
         local ScriptInfoUrl = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/scriptinfo.json"
         
         local okCL, bodyCL = pcall(function() return Exec.HttpGet(ChangeLogUrl) end)
         if okCL then
             local _, txt = parseChangelogBody(bodyCL, HttpService)
             for line in string.gmatch(txt, "[^\r\n]+") do safeRichLabel(ChangelogBox, line) end
         else
             safeRichLabel(ChangelogBox, "<font color='#ff5555'>Failed to fetch changelog</font>")
         end
         
         local okSI, bodySI = pcall(function() return Exec.HttpGet(ScriptInfoUrl) end)
         if okSI then
             local fullText = parseScriptInfo(bodySI, HttpService)
             for line in string.gmatch(fullText, "[^\r\n]+") do safeRichLabel(ScriptInfoBox, line) end
         else
             safeRichLabel(ScriptInfoBox, "<font color='#ff5555'>Failed to fetch script info</font>")
         end
    end)

    task.spawn(function()
        local createdAtText, expireDisplay
        if keydata.timestamp and keydata.timestamp > 0 then createdAtText = formatUnixTime(keydata.timestamp) else createdAtText = tostring(keydata.created_at or "Unknown") end
        local expireTs = tonumber(keydata.expire) or 0
        if expireTs > 0 then expireDisplay = formatUnixTime(expireTs) else expireDisplay = "Lifetime" end

        CreatedLabel.TextLabel.Text = string.format("<b>Created at:</b> %s", createdAtText)
        ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", expireDisplay)
        
        while true do
            if expireTs > 0 then
                TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", formatTimeLeft(expireTs))
            else
                 TimeLeftLabel.TextLabel.Text = "<b>Time left:</b> Lifetime"
                 break 
            end
            task.wait(1)
        end
    end)

    --------------------------------------------------------
    -- Player Tab (Reconstructed Full Features)
    --------------------------------------------------------
    local PlayerTab = Tabs.Player
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    local defaultWalkSpeed = 16
    local walkSpeedEnabled = false
    local WalkSpeedToggle = AddSmartToggle(MoveBox, "bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = defaultWalkSpeed, Min = 0, Max = 120, Rounding = 0 })

    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = state and WalkSpeedSlider.Value or defaultWalkSpeed end
        NotifyAction("WalkSpeed", state)
    end)
    AddSmartButton(MoveBox, "Reset WalkSpeed", function()
        WalkSpeedSlider:SetValue(defaultWalkSpeed)
        WalkSpeedToggle:SetValue(false)
    end)
    
    local AutoRunToggle = AddSmartToggle(MoveBox, "bxw_autorun", { Text = "Auto Run (Circle)", Default = false })
    local autoRunConn
    AutoRunToggle:OnChanged(function(state)
        if state then
             local center = getRootPart().Position
             local angle = 0
             autoRunConn = AddConnection(RunService.Heartbeat:Connect(function(dt)
                 local hum = getHumanoid()
                 local root = getRootPart()
                 if hum and root then
                     angle = angle + dt
                     local offset = Vector3.new(math.cos(angle)*5, 0, math.sin(angle)*5)
                     hum:MoveTo(center + offset)
                 end
             end))
        else
             if autoRunConn then autoRunConn:Disconnect() autoRunConn = nil end
        end
        NotifyAction("Auto Run", state)
    end)

    local VehicleModeToggle = AddSmartToggle(MoveBox, "bxw_vehicle_mode", { Text = "Vehicle Speed Mode", Default = false })
    local VehicleSpeedSlider = MoveBox:AddSlider("bxw_vehicle_speed", { Text = "Vehicle Speed", Default = 100, Min = 0, Max = 500, Rounding = 0 })
    local vehConn
    VehicleModeToggle:OnChanged(function(state)
        if state then
             vehConn = AddConnection(RunService.Heartbeat:Connect(function()
                 local hum = getHumanoid()
                 if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
                     hum.SeatPart.MaxSpeed = VehicleSpeedSlider.Value
                     hum.SeatPart.Torque = 9999999
                 end
             end))
        else
             if vehConn then vehConn:Disconnect() vehConn = nil end
        end
        NotifyAction("Vehicle Mode", state)
    end)

    MoveBox:AddDivider()
    local defaultJumpPower = 50
    local jumpPowerEnabled = false
    local JumpPowerToggle = AddSmartToggle(MoveBox, "bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = defaultJumpPower, Min = 0, Max = 200, Rounding = 0 })

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        local hum = getHumanoid()
        if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower end
        NotifyAction("JumpPower", state)
    end)

    local HipHeightToggle = AddSmartToggle(MoveBox, "bxw_hipheight_toggle", { Text = "Enable Hip Height", Default = false })
    local HipHeightSlider = MoveBox:AddSlider("bxw_hipheight", { Text = "Hip Height", Default = 0, Min = 0, Max = 50, Rounding = 1 })
    HipHeightToggle:OnChanged(function(state)
        local hum = getHumanoid()
        if hum then hum.HipHeight = state and HipHeightSlider.Value or 0 end
        NotifyAction("Hip Height", state)
    end)

    local infJumpConn
    local InfJumpToggle = AddSmartToggle(MoveBox, "bxw_infjump", { Text = "Infinite Jump", Default = false })
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
    local FlyToggle = AddSmartToggle(MoveBox, "bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false, Role = "premium" })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = flySpeed, Min = 1, Max = 300, Rounding = 0, Callback = function(value) flySpeed = value end })
    
    FlyToggle:OnChanged(function(state)
        flyEnabled = state
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
        if not (root and hum and cam) then FlyToggle:SetValue(false) return end
        hum.PlatformStand = true
        flyBV = Instance.new("BodyVelocity") flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5) flyBV.Velocity = Vector3.zero flyBV.Parent = root
        flyBG = Instance.new("BodyGyro") flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9) flyBG.CFrame = root.CFrame flyBG.Parent = root
        if flyConn then flyConn:Disconnect() end
        flyConn = AddConnection(RunService.RenderStepped:Connect(function()
            if not flyEnabled then return end
            local root = getRootPart()
            local hum  = getHumanoid()
            local cam  = Workspace.CurrentCamera
            if not (root and hum and cam and flyBV and flyBG) then return end
            local moveDir = Vector3.new(0, 0, 0)
            if hum.MoveDirection.Magnitude > 0 then
                local camLook = cam.CFrame.LookVector
                local dot = camLook:Dot(hum.MoveDirection.Unit)
                if dot > 0.5 then moveDir = camLook * hum.MoveDirection.Magnitude else moveDir = hum.MoveDirection end
            else
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            end
            flyBV.Velocity = moveDir.Magnitude > 0 and moveDir.Unit * flySpeed or Vector3.zero
            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
        NotifyAction("Fly", true)
    end)
    
    -- Sky Walk
    local SkyWalkToggle = AddSmartToggle(MoveBox, "bxw_skywalk", { Text = "Sky Walk", Default = false })
    local skyWalkPart, skyWalkConn
    SkyWalkToggle:OnChanged(function(state)
        if state then
             skyWalkConn = AddConnection(RunService.Heartbeat:Connect(function()
                 local root = getRootPart()
                 if root then
                     if not skyWalkPart then
                         skyWalkPart = Instance.new("Part", workspace)
                         skyWalkPart.Anchored = true; skyWalkPart.Size = Vector3.new(10, 1, 10); skyWalkPart.Transparency = 0.5; skyWalkPart.Name = "BxB_SkyWalk"
                     end
                     skyWalkPart.CFrame = root.CFrame * CFrame.new(0, -3.5, 0)
                 end
             end))
        else
            if skyWalkConn then skyWalkConn:Disconnect() skyWalkConn = nil end
            if skyWalkPart then skyWalkPart:Destroy() skyWalkPart = nil end
        end
        NotifyAction("Sky Walk", state)
    end)

    local NoclipToggle = AddSmartToggle(MoveBox, "bxw_noclip", { Text = MarkRisky("Noclip"), Default = false, Role = "user" })
    local noclipConn
    NoclipToggle:OnChanged(function(state)
        if state then
             noclipConn = AddConnection(RunService.Stepped:Connect(function()
                local char = getCharacter()
                if char then for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = false end end end
             end))
        else
             if noclipConn then noclipConn:Disconnect() noclipConn = nil end
        end
        NotifyAction("Noclip", state)
    end)

    -- Utility Box
    local UtilBox = safeAddRightGroupbox(PlayerTab, "Teleport / Utility", "map")
    local playerNames = {}
    local function refreshPlayerList()
        table.clear(playerNames)
        for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then table.insert(playerNames, plr.Name) end end
    end
    refreshPlayerList()
    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = playerNames, Default = "", Multi = false, AllowNull = true })
    AddSmartButton(UtilBox, "Refresh List", function() refreshPlayerList() TeleportDropdown:SetValues(playerNames) end)
    
    AddSmartButton(UtilBox, "Teleport", function()
        local target = Players:FindFirstChild(TeleportDropdown.Value)
        local root = getRootPart()
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and root then
            root.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(0, 3, 0)
        end
    end, { Role = "premium" })
    
    local ClickTPToggle = AddSmartToggle(UtilBox, "bxw_clicktp", { Text = "Ctrl+Click TP (Mobile: Tap)", Default = false })
    local clickTpConn
    ClickTPToggle:OnChanged(function(state)
        if state then
            clickTpConn = AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                local targetPos = nil
                if isMobile and input.UserInputType == Enum.UserInputType.Touch then
                    local cam = workspace.CurrentCamera
                    local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
                    local res = workspace:Raycast(ray.Origin, ray.Direction * 1000)
                    if res then targetPos = res.Position end
                elseif input.UserInputType == Enum.UserInputType.MouseButton1 and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)) then
                     if Mouse.Hit then targetPos = Mouse.Hit.Position end
                end
                if targetPos then
                     local root = getRootPart()
                     if root then root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0)) end
                end
            end))
        else
            if clickTpConn then clickTpConn:Disconnect() clickTpConn = nil end
        end
        NotifyAction("Click TP", state)
    end)
    
    AddSmartButton(UtilBox, "Safe Zone (Sky)", function() local r = getRootPart() if r then r.CFrame = CFrame.new(r.Position.X, 10000, r.Position.Z) end end)

    UtilBox:AddInput("bxw_waypoint_name", { Default = "", Text = "Waypoint Name", Placeholder = "Enter name..." })
    local savedWaypoints, savedNames = {}, {}
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", Multi = false })
    
    AddSmartButton(UtilBox, "Set Waypoint", function()
        local name = Options.bxw_waypoint_name.Value
        if name == "" then name = "WP" .. #savedNames + 1 end
        local root = getRootPart()
        if root then
            savedWaypoints[name] = root.CFrame
            table.insert(savedNames, name)
            WaypointDropdown:SetValues(savedNames)
            Library:Notify("Saved: " .. name, 2)
        end
    end)
    AddSmartButton(UtilBox, "TP to Waypoint", function()
        local cf = savedWaypoints[WaypointDropdown.Value]
        local root = getRootPart()
        if cf and root then root.CFrame = cf + Vector3.new(0, 3, 0) end
    end)
    
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate", { Text = "Spectate Player", Values = playerNames, Default = "" })
    local SpectateToggle = AddSmartToggle(UtilBox, "bxw_spectate_toggle", { Text = "Spectate", Default = false })
    local specConn
    SpectateToggle:OnChanged(function(state)
        local cam = workspace.CurrentCamera
        if state then
             specConn = AddConnection(RunService.RenderStepped:Connect(function()
                 local t = Players:FindFirstChild(SpectateDropdown.Value)
                 if t and t.Character and t.Character:FindFirstChild("Humanoid") then
                     cam.CameraSubject = t.Character.Humanoid
                 end
             end))
        else
            if specConn then specConn:Disconnect() specConn = nil end
            local h = getHumanoid()
            if h then cam.CameraSubject = h end
        end
    end)

    -- Camera & World
    local CamBox = safeAddRightGroupbox(PlayerTab, "Camera & World", "sun")
    CamBox:AddSlider("bxw_cam_fov", { Text = "Camera FOV", Default = 70, Min = 40, Max = 120, Rounding = 0, Callback = function(v) workspace.CurrentCamera.FieldOfView = v end })
    CamBox:AddSlider("bxw_cam_maxzoom", { Text = "Max Zoom", Default = 400, Min = 10, Max = 2000, Rounding = 0, Callback = function(v) LocalPlayer.CameraMaxZoomDistance = v end })
    
    local FreeCamToggle = AddSmartToggle(CamBox, "bxw_freecam", { Text = "Free Camera", Default = false, Platforms = {PC=true, Mobile=false} })
    local freeCamConn
    FreeCamToggle:OnChanged(function(state)
        local cam = workspace.CurrentCamera
        if state then
            cam.CameraType = Enum.CameraType.Scriptable
            freeCamConn = AddConnection(RunService.RenderStepped:Connect(function()
                local speed = 0.5
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed = 2 end
                local cf = cam.CFrame
                local move = Vector3.new()
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cf.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cf.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cf.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cf.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.E) then move = move + Vector3.new(0,1,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move = move - Vector3.new(0,1,0) end
                cam.CFrame = cf + (move * speed)
            end))
        else
            if freeCamConn then freeCamConn:Disconnect() freeCamConn = nil end
            cam.CameraType = Enum.CameraType.Custom
        end
        NotifyAction("Free Camera", state)
    end)

    local SkyboxDropdown = CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default" })
    local SkyboxThemes = { ["Space"] = "rbxassetid://11755937810", ["Sunset"] = "rbxassetid://9393701400", ["Midnight"] = "rbxassetid://11755930464" }
    SkyboxDropdown:OnChanged(function(v)
        local l = game.Lighting
        for _,s in pairs(l:GetChildren()) do if s:IsA("Sky") then s:Destroy() end end
        if v ~= "Default" and SkyboxThemes[v] then
             local s = Instance.new("Sky", l); s.SkyboxBk=SkyboxThemes[v]; s.SkyboxDn=SkyboxThemes[v]; s.SkyboxFt=SkyboxThemes[v]; s.SkyboxLf=SkyboxThemes[v]; s.SkyboxRt=SkyboxThemes[v]; s.SkyboxUp=SkyboxThemes[v]
        end
    end)

    ------------------------------------------------
    -- ESP Tab (Reworked & Full)
    ------------------------------------------------
    local ESPTab = Tabs.ESP
    local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
    local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")
    local ExtraVisualBox = safeAddRightGroupbox(ESPTab, "Radar", "radar")

    local ESPEnabledToggle = AddSmartToggle(ESPFeatureBox, "bxw_esp_enable", { Text = "Enable ESP", Default = false })
    local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box" })
    
    local function AddColorToggle(id, text, def, col)
         return ESPFeatureBox:AddToggle(id, { Text = text, Default = def }):AddColorPicker(id.."_color", { Default = col })
    end

    local BoxToggle = AddColorToggle("bxw_esp_box", "Box", true, Color3.new(1,1,1))
    local ChamsToggle = AddColorToggle("bxw_esp_chams", "Chams (Highlight)", false, Color3.new(0,1,0))
    local SkeletonToggle = AddColorToggle("bxw_esp_skeleton", "Skeleton", false, Color3.new(0,1,1))
    local HealthToggle = AddColorToggle("bxw_esp_health", "Health Bar", false, Color3.new(0,1,0))
    local NameToggle = AddColorToggle("bxw_esp_name", "Name Tag", true, Color3.new(1,1,1))
    local DistToggle = AddColorToggle("bxw_esp_distance", "Distance", false, Color3.new(1,1,1))
    local InfoToggle = AddColorToggle("bxw_esp_info", "Target Info", false, Color3.new(1,1,1))
    local TracerToggle = AddColorToggle("bxw_esp_tracer", "Tracer", false, Color3.new(1,1,1))
    local HeadDotToggle = AddColorToggle("bxw_esp_headdot", "Head Dot", false, Color3.new(1,0,0))
    local ArrowToggle = AddColorToggle("bxw_esp_arrow", "Off-Screen Arrow", false, Color3.new(1,0.5,0))
    local ViewDirToggle = AddColorToggle("bxw_esp_viewdir", "View Direction", false, Color3.new(1,1,0))
    
    local TeamToggle = ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true })
    local WallToggle = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false })
    local SelfToggle = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false })

    -- Radar
    local RadarToggle = AddSmartToggle(ExtraVisualBox, "bxw_radar_enable", { Text = "Enable 2D Radar", Default = false, Platforms = {PC=true, Mobile=true} })
    local RadarRangeSlider = ExtraVisualBox:AddSlider("bxw_radar_range", { Text = "Radar Range", Default = 200, Min = 50, Max = 1000, Rounding = 0 })
    local RadarSizeSlider = ExtraVisualBox:AddSlider("bxw_radar_size", { Text = "Radar Scale", Default = 150, Min = 100, Max = 300, Rounding = 0 })

    -- Settings
    local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = {}, Default = "", Multi = true })
    local function refreshWhitelist() local names = {} for _,p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(names, p.Name) end end table.sort(names) WhitelistDropdown:SetValues(names) end
    refreshWhitelist(); Players.PlayerAdded:Connect(refreshWhitelist); Players.PlayerRemoving:Connect(refreshWhitelist)
    
    local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
    local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Distance Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
    local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
    local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Chams Visible Only", Default = false })
    local RefreshRateSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "Refresh Rate (ms)", Default = 0, Min = 0, Max = 500, Rounding = 0 })

    -- Skeleton logic
    local function UpdateSkeleton(plr, data, color)
        local char = plr.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local rigType = hum and hum.RigType
        local joints = {}
        if rigType == Enum.HumanoidRigType.R15 then
            joints = {{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","HumanoidRootPart"},{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"}}
        else
            joints = {{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}}
        end
        if not data.Skeleton then data.Skeleton = {} end
        for i = 1, #joints do
            if not data.Skeleton[i] then
                local l = Drawing.new("Line"); l.Thickness = 1; l.Transparency = 1; data.Skeleton[i] = l
            end
            local line = data.Skeleton[i]
            local p1, p2 = char:FindFirstChild(joints[i][1]), char:FindFirstChild(joints[i][2])
            if p1 and p2 then
                local v1, vis1 = workspace.CurrentCamera:WorldToViewportPoint(p1.Position)
                local v2, vis2 = workspace.CurrentCamera:WorldToViewportPoint(p2.Position)
                if vis1 and vis2 then
                    line.Visible = true; line.From = Vector2.new(v1.X, v1.Y); line.To = Vector2.new(v2.X, v2.Y); line.Color = color
                else line.Visible = false end
            else line.Visible = false end
        end
    end

    local function removePlayerESP(plr)
        if espDrawings[plr] then
            local d = espDrawings[plr]
            for k,v in pairs(d) do
                if k == "Skeleton" then for _,l in pairs(v) do l:Remove() end
                elseif k == "Health" then if v.Outline then v.Outline:Remove() end if v.Bar then v.Bar:Remove() end
                elseif k == "Highlight" then v:Destroy()
                elseif v.Remove then v:Remove() end
            end
            espDrawings[plr] = nil
        end
    end

    local lastEspUpdate = 0
    AddConnection(RunService.RenderStepped:Connect(function()
        if not ESPEnabledToggle.Value then for p in pairs(espDrawings) do removePlayerESP(p) end return end
        if tick() - lastEspUpdate < (RefreshRateSlider.Value/1000) then return end
        lastEspUpdate = tick()

        -- Radar Draw
        if RadarToggle.Value then
            local rSize = RadarSizeSlider.Value
            local rX, rY = workspace.CurrentCamera.ViewportSize.X - rSize - 20, workspace.CurrentCamera.ViewportSize.Y - rSize - 20
            if not radarDrawings.bg then
                radarDrawings.bg = Drawing.new("Square"); radarDrawings.bg.Filled = true; radarDrawings.bg.Transparency = 0.6; radarDrawings.bg.Color = Color3.new(0.1,0.1,0.1); radarDrawings.bg.Visible = true
                radarDrawings.outline = Drawing.new("Square"); radarDrawings.outline.Filled = false; radarDrawings.outline.Thickness = 2; radarDrawings.outline.Color = Color3.new(1,1,1); radarDrawings.outline.Visible = true
                radarDrawings.line = Drawing.new("Line"); radarDrawings.line.Color=Color3.new(1,1,1); radarDrawings.line.Thickness=1; radarDrawings.line.Visible=true
            end
            radarDrawings.bg.Size = Vector2.new(rSize, rSize); radarDrawings.bg.Position = Vector2.new(rX, rY)
            radarDrawings.outline.Size = Vector2.new(rSize, rSize); radarDrawings.outline.Position = Vector2.new(rX, rY)
            radarDrawings.line.From = Vector2.new(rX+rSize/2, rY+rSize/2); radarDrawings.line.To = Vector2.new(rX+rSize/2, rY)
        else
            if radarDrawings.bg then radarDrawings.bg.Visible = false; radarDrawings.outline.Visible = false; radarDrawings.line.Visible = false end
        end

        local cam = workspace.CurrentCamera
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local char = plr.Character
                local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                local hum = char:FindFirstChildOfClass("Humanoid")
                
                if root and hum and hum.Health > 0 then
                    local skip = false
                    if TeamToggle.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then skip = true end
                    local wList = WhitelistDropdown.Value
                    if wList and type(wList) == "table" then for _, n in ipairs(wList) do if n == plr.Name then skip = true end end end
                    
                    if not skip then
                        local data = espDrawings[plr] or {}; espDrawings[plr] = data
                        local pos, vis = cam:WorldToViewportPoint(root.Position)
                        local dist = (root.Position - cam.CFrame.Position).Magnitude
                        
                        -- Chams
                        if ChamsToggle.Value then
                            if not data.Highlight then data.Highlight = Instance.new("Highlight", CoreGui); data.Highlight.Adornee = char end
                            data.Highlight.FillColor = Options.bxw_esp_chams_color.Value
                            data.Highlight.OutlineColor = Options.bxw_esp_chams_color.Value
                            data.Highlight.FillTransparency = ChamsTransSlider.Value
                            data.Highlight.DepthMode = ChamsVisibleToggle.Value and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                            data.Highlight.Enabled = true
                        elseif data.Highlight then data.Highlight.Enabled = false end

                        -- Skeleton
                        if SkeletonToggle.Value then UpdateSkeleton(plr, data, Options.bxw_esp_skeleton_color.Value)
                        elseif data.Skeleton then for _,l in pairs(data.Skeleton) do l.Visible=false end end

                        -- Box & Info Calculations
                        if vis then
                            local tl, vis1 = cam:WorldToViewportPoint((root.CFrame * CFrame.new(-2, 3, 0)).Position)
                            local br, vis2 = cam:WorldToViewportPoint((root.CFrame * CFrame.new(2, -3, 0)).Position)
                            local w, h = math.abs(br.X - tl.X), math.abs(br.Y - tl.Y)
                            
                            -- Box
                            if BoxToggle.Value then
                                if BoxStyleDropdown.Value == "Box" then
                                    if not data.Box then data.Box = Drawing.new("Square"); data.Box.Thickness = 1; data.Box.Filled = false end
                                    data.Box.Visible = true; data.Box.Color = Options.bxw_esp_box_color.Value; data.Box.Position = Vector2.new(tl.X, tl.Y); data.Box.Size = Vector2.new(w, h)
                                    if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                                else
                                    if not data.Corners then data.Corners = {}; for i=1,8 do data.Corners[i] = Drawing.new("Line"); data.Corners[i].Thickness=1 end end
                                    if data.Box then data.Box.Visible = false end
                                    local cw, ch = w*0.25, h*0.25; local col = Options.bxw_esp_box_color.Value
                                    -- TopLeft
                                    data.Corners[1].Visible=true; data.Corners[1].From=Vector2.new(tl.X,tl.Y); data.Corners[1].To=Vector2.new(tl.X+cw,tl.Y); data.Corners[1].Color=col
                                    data.Corners[2].Visible=true; data.Corners[2].From=Vector2.new(tl.X,tl.Y); data.Corners[2].To=Vector2.new(tl.X,tl.Y+ch); data.Corners[2].Color=col
                                    -- TopRight
                                    data.Corners[3].Visible=true; data.Corners[3].From=Vector2.new(br.X,tl.Y); data.Corners[3].To=Vector2.new(br.X-cw,tl.Y); data.Corners[3].Color=col
                                    data.Corners[4].Visible=true; data.Corners[4].From=Vector2.new(br.X,tl.Y); data.Corners[4].To=Vector2.new(br.X,tl.Y+ch); data.Corners[4].Color=col
                                    -- BottomLeft
                                    data.Corners[5].Visible=true; data.Corners[5].From=Vector2.new(tl.X,br.Y); data.Corners[5].To=Vector2.new(tl.X+cw,br.Y); data.Corners[5].Color=col
                                    data.Corners[6].Visible=true; data.Corners[6].From=Vector2.new(tl.X,br.Y); data.Corners[6].To=Vector2.new(tl.X,br.Y-ch); data.Corners[6].Color=col
                                    -- BottomRight
                                    data.Corners[7].Visible=true; data.Corners[7].From=Vector2.new(br.X,br.Y); data.Corners[7].To=Vector2.new(br.X-cw,br.Y); data.Corners[7].Color=col
                                    data.Corners[8].Visible=true; data.Corners[8].From=Vector2.new(br.X,br.Y); data.Corners[8].To=Vector2.new(br.X,br.Y-ch); data.Corners[8].Color=col
                                end
                            else
                                if data.Box then data.Box.Visible=false end; if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                            end

                            -- Name
                            if NameToggle.Value then
                                if not data.Name then data.Name = Drawing.new("Text"); data.Name.Center=true; data.Name.Outline=true end
                                data.Name.Visible=true; data.Name.Text=plr.DisplayName; data.Name.Size=NameSizeSlider.Value; data.Name.Color=Options.bxw_esp_name_color.Value; data.Name.Position=Vector2.new(tl.X+w/2, tl.Y-15)
                            else if data.Name then data.Name.Visible=false end end
                            
                            -- Distance
                            if DistToggle.Value then
                                if not data.Distance then data.Distance = Drawing.new("Text"); data.Distance.Center=true; data.Distance.Outline=true end
                                data.Distance.Visible=true; data.Distance.Text=math.floor(dist).."m"; data.Distance.Size=DistSizeSlider.Value; data.Distance.Color=Options.bxw_esp_dist_color.Value; data.Distance.Position=Vector2.new(tl.X+w/2, br.Y+2)
                            else if data.Distance then data.Distance.Visible=false end end

                            -- Health
                            if HealthToggle.Value then
                                if not data.Health then data.Health = {Outline=Drawing.new("Line"), Bar=Drawing.new("Line")}; data.Health.Outline.Thickness=3; data.Health.Bar.Thickness=1 end
                                local hp = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
                                data.Health.Outline.Visible=true; data.Health.Outline.From=Vector2.new(tl.X-4, tl.Y); data.Health.Outline.To=Vector2.new(tl.X-4, br.Y)
                                data.Health.Bar.Visible=true; data.Health.Bar.Color=Options.bxw_esp_health_color.Value
                                data.Health.Bar.From=Vector2.new(tl.X-4, br.Y); data.Health.Bar.To=Vector2.new(tl.X-4, br.Y - (h * hp))
                            else if data.Health then data.Health.Outline.Visible=false; data.Health.Bar.Visible=false end end

                            -- Info (Weapon)
                            if InfoToggle.Value then
                                if not data.Info then data.Info = Drawing.new("Text"); data.Info.Outline=true end
                                local tool = char:FindFirstChildOfClass("Tool"); local tName = tool and tool.Name or "None"
                                data.Info.Visible=true; data.Info.Text=tName; data.Info.Size=13; data.Info.Color=Options.bxw_esp_info_color.Value; data.Info.Position=Vector2.new(br.X+4, tl.Y)
                            else if data.Info then data.Info.Visible=false end end

                            -- Head Dot
                            if HeadDotToggle.Value then
                                local head = char:FindFirstChild("Head")
                                if head then
                                    local hPos, hVis = cam:WorldToViewportPoint(head.Position)
                                    if hVis then
                                        if not data.HeadDot then data.HeadDot = Drawing.new("Circle"); data.HeadDot.Filled=true; data.HeadDot.Radius=3 end
                                        data.HeadDot.Visible=true; data.HeadDot.Position=Vector2.new(hPos.X, hPos.Y); data.HeadDot.Color=Options.bxw_esp_headdot_color.Value
                                    end
                                end
                            else if data.HeadDot then data.HeadDot.Visible=false end end

                            -- Tracer
                            if TracerToggle.Value then
                                if not data.Tracer then data.Tracer = Drawing.new("Line"); data.Tracer.Thickness=1 end
                                data.Tracer.Visible=true; data.Tracer.From=Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y); data.Tracer.To=Vector2.new(tl.X+w/2, br.Y); data.Tracer.Color=Options.bxw_esp_tracer_color.Value
                            else if data.Tracer then data.Tracer.Visible=false end end

                        else
                             -- Hide if offscreen
                             if data.Box then data.Box.Visible=false end
                             if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                             if data.Name then data.Name.Visible=false end
                             if data.Distance then data.Distance.Visible=false end
                             if data.Health then data.Health.Outline.Visible=false; data.Health.Bar.Visible=false end
                             if data.Info then data.Info.Visible=false end
                             if data.HeadDot then data.HeadDot.Visible=false end
                             if data.Tracer then data.Tracer.Visible=false end
                        end
                        
                        -- Arrow (Offscreen)
                        if ArrowToggle.Value and not vis then
                             if not data.Arrow then data.Arrow = Drawing.new("Triangle"); data.Arrow.Filled=true end
                             local rel = cam.CFrame:PointToObjectSpace(root.Position)
                             local ang = math.atan2(rel.Y, rel.X)
                             local ctr = cam.ViewportSize/2; local rad = 300
                             local p = ctr + Vector2.new(math.cos(ang)*rad, math.sin(ang)*rad)
                             data.Arrow.Visible=true; data.Arrow.PointA=p; data.Arrow.PointB=p+Vector2.new(math.cos(ang+2.5)*15, math.sin(ang+2.5)*15); data.Arrow.PointC=p+Vector2.new(math.cos(ang-2.5)*15, math.sin(ang-2.5)*15); data.Arrow.Color=Options.bxw_esp_arrow_color.Value
                        else if data.Arrow then data.Arrow.Visible=false end end
                        
                        -- Radar Dots
                        if RadarToggle.Value then
                            local rRange = RadarRangeSlider.Value; local rSize = RadarSizeSlider.Value
                            local rCenter = Vector2.new(workspace.CurrentCamera.ViewportSize.X - rSize/2 - 20, workspace.CurrentCamera.ViewportSize.Y - rSize/2 - 20)
                            local dist = (root.Position - getRootPart().Position).Magnitude
                            local ang = math.atan2(root.Position.Z - getRootPart().Position.Z, root.Position.X - getRootPart().Position.X) - math.atan2(cam.CFrame.LookVector.Z, cam.CFrame.LookVector.X)
                            local scale = math.clamp(dist,0,rRange)/rRange
                            local dotX, dotY = rCenter.X + math.cos(ang)*scale*rSize/2, rCenter.Y + math.sin(ang)*scale*rSize/2
                            if not radarDrawings.points[plr] then radarDrawings.points[plr]=Drawing.new("Circle"); radarDrawings.points[plr].Filled=true; radarDrawings.points[plr].Radius=3; radarDrawings.points[plr].Color=Color3.new(1,0,0) end
                            radarDrawings.points[plr].Visible=true; radarDrawings.points[plr].Position=Vector2.new(dotX, dotY)
                        elseif radarDrawings.points[plr] then radarDrawings.points[plr].Visible=false end

                    else
                        removePlayerESP(plr)
                        if radarDrawings.points[plr] then radarDrawings.points[plr].Visible=false end
                    end
                else
                    removePlayerESP(plr)
                end
            end
        end
    end))
    
    -- Crosshair
    local CrosshairToggle = AddColorToggle("bxw_crosshair_enable", "Crosshair", false, Color3.new(1,1,1))
    crosshairLines = { h = Drawing.new("Line"), v = Drawing.new("Line") }
    AddConnection(RunService.RenderStepped:Connect(function()
        if CrosshairToggle.Value then
            local c = workspace.CurrentCamera.ViewportSize / 2
            crosshairLines.h.Visible = true; crosshairLines.h.From = Vector2.new(c.X - 5, c.Y); crosshairLines.h.To = Vector2.new(c.X + 5, c.Y); crosshairLines.h.Color = Options.bxw_crosshair_enable_color.Value
            crosshairLines.v.Visible = true; crosshairLines.v.From = Vector2.new(c.X, c.Y - 5); crosshairLines.v.To = Vector2.new(c.X, c.Y + 5); crosshairLines.v.Color = Options.bxw_crosshair_enable_color.Value
        else
            crosshairLines.h.Visible = false; crosshairLines.v.Visible = false
        end
    end))

    ------------------------------------------------
    -- Combat Tab (Full Features)
    ------------------------------------------------
    local CombatTab = Tabs.Combat
    local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
    
    local AimbotToggle = AddSmartToggle(AimBox, "bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false, Role = "premium" })
    local SilentToggle = AddSmartToggle(AimBox, "bxw_silent_enable", { Text = "Silent Aim", Default = false, Role = "vip" })
    
    AimBox:AddLabel("Targeting")
    local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest" }, Default = "Head" })
    local SmartLogicToggle = AimBox:AddToggle("bxw_aim_smart", { Text = "Smart Aim Logic", Default = true, Tooltip = "Auto pick best target" })
    
    AimBox:AddLabel("FOV & Smoothing")
    local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
    local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false }):AddColorPicker("bxw_aim_fovcolor", { Default = Color3.new(1,1,1) })
    local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Smoothness", Default = 0, Min = 0, Max = 5, Rounding = 2, Tooltip = "0=Instant, 5=Slow" })
    
    -- Prediction
    local PredToggle = AimBox:AddToggle("bxw_aim_pred", { Text = "Prediction Aim", Default = false })
    local PredSlider = AimBox:AddSlider("bxw_aim_predfactor", { Text = "Prediction Factor", Default = 0.1, Min = 0, Max = 1, Rounding = 2 })
    
    -- Triggerbot & Checks
    local TriggerToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false })
    local TeamCheckToggle = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
    local VisCheckToggle = AimBox:AddToggle("bxw_aim_vischeck", { Text = "Visibility Check", Default = false })
    local HitChanceSlider = AimBox:AddSlider("bxw_aim_hitchance", { Text = "Hit Chance %", Default = 100, Min = 0, Max = 100, Rounding = 0 })
    local SnapLineToggle = AimBox:AddToggle("bxw_aim_snap", { Text = "Show SnapLine", Default = false })

    AimbotFOVCircle = Drawing.new("Circle"); AimbotFOVCircle.Transparency = 0.5; AimbotFOVCircle.Thickness = 1
    AimbotSnapLine = Drawing.new("Line"); AimbotSnapLine.Transparency = 0.5
    
    local function performClick() pcall(function() mouse1click() end) pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton1(Vector2.new()) end) end

    -- Aimbot Loop
    AddConnection(RunService.RenderStepped:Connect(function(dt)
        local cam = workspace.CurrentCamera
        local mouseLoc = UserInputService:GetMouseLocation()
        
        -- FOV Draw
        if ShowFovToggle.Value and AimbotToggle.Value then
            AimbotFOVCircle.Visible = true; AimbotFOVCircle.Radius = FOVSlider.Value * 15; AimbotFOVCircle.Position = mouseLoc; AimbotFOVCircle.Color = Options.bxw_aim_fovcolor.Value
        else AimbotFOVCircle.Visible = false end
        AimbotSnapLine.Visible = false

        -- Aimbot Logic
        if AimbotToggle.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local bestPlr, bestDist = nil, math.huge
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local skip = false
                    if TeamCheckToggle.Value and LocalPlayer.Team and p.Team and LocalPlayer.Team == p.Team then skip = true end
                    
                    if not skip then
                        local root = p.Character:FindFirstChild("HumanoidRootPart")
                        local hum = p.Character:FindFirstChild("Humanoid")
                        if root and hum and hum.Health > 0 then
                            local pos, vis = cam:WorldToViewportPoint(root.Position)
                            if vis then
                                local dist = (Vector2.new(pos.X, pos.Y) - mouseLoc).Magnitude
                                if dist < FOVSlider.Value * 15 then
                                    if VisCheckToggle.Value then
                                        local rp = RaycastParams.new(); rp.FilterDescendantsInstances={p.Character, LocalPlayer.Character}; rp.FilterType=Enum.RaycastFilterType.Blacklist
                                        local hit = workspace:Raycast(cam.CFrame.Position, root.Position - cam.CFrame.Position, rp)
                                        if hit then skip = true end
                                    end
                                    
                                    if not skip and dist < bestDist then
                                        bestDist = dist; bestPlr = p
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            if bestPlr then
                local partName = AimPartDropdown.Value
                if partName == "Closest" then partName = "Head" end -- Simplified closest logic
                local targetPart = bestPlr.Character:FindFirstChild(partName) or bestPlr.Character:FindFirstChild("HumanoidRootPart")
                
                if targetPart then
                    local aimPos = targetPart.Position
                    if PredToggle.Value then
                        aimPos = aimPos + (targetPart.AssemblyLinearVelocity * PredSlider.Value)
                    end
                    
                    if math.random(0,100) <= HitChanceSlider.Value then
                         if SnapLineToggle.Value then
                             local sPos = cam:WorldToViewportPoint(aimPos)
                             AimbotSnapLine.Visible=true; AimbotSnapLine.From=mouseLoc; AimbotSnapLine.To=Vector2.new(sPos.X, sPos.Y); AimbotSnapLine.Color=Color3.new(1,0,0)
                         end

                         local currentLook = cam.CFrame.LookVector
                         local targetLook = (aimPos - cam.CFrame.Position).Unit
                         local smooth = SmoothSlider.Value
                         
                         if smooth <= 0.05 then
                             cam.CFrame = CFrame.new(cam.CFrame.Position, aimPos)
                         else
                             local alpha = math.clamp(1 / (smooth * 20), 0, 1) -- Smooth 0-5 mapping
                             cam.CFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + currentLook:Lerp(targetLook, alpha))
                         end
                    end
                end
            end
        end
        
        -- Triggerbot
        if TriggerToggle.Value then
            local t = Mouse.Target
            if t and t.Parent and t.Parent:FindFirstChild("Humanoid") then
                local p = Players:GetPlayerFromCharacter(t.Parent)
                if p and p ~= LocalPlayer then
                     local skip = false
                     if TeamCheckToggle.Value and LocalPlayer.Team and p.Team and LocalPlayer.Team == p.Team then skip = true end
                     if not skip then performClick() end
                end
            end
        end
    end))

    ------------------------------------------------
    -- Server & Misc
    ------------------------------------------------
    local ServerTab = Tabs.Server
    local SrvBox = ServerTab:AddLeftGroupbox("Server Actions", "server")
    AddSmartButton(SrvBox, "Server Hop", function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    AddSmartButton(SrvBox, "Low Server Hop", function() 
        Library:Notify("Scanning...", 3)
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local list = HttpService:JSONDecode(game:HttpGet(url))
        for _, s in ipairs(list.data) do
            if s.playing < s.maxPlayers and s.id ~= game.JobId then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer); return
            end
        end
        Library:Notify("None found", 2)
    end)
    AddSmartButton(SrvBox, "Rejoin", function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
    SrvBox:AddInput("bxw_jobid", { Text = "Join Job ID", Placeholder = "Job ID...", Callback = function(v) pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, v, LocalPlayer) end) end })
    
    local MiscTab = Tabs.Misc
    local MiscBox = MiscTab:AddLeftGroupbox("Tools", "tool")
    
    -- Auto Clicker & SetPoint
    MiscBox:AddLabel("Auto Clicker")
    local AutoClickToggle = MiscBox:AddToggle("bxw_autoclick", { Text = "Enable", Default = false })
    local AutoClickDelay = MiscBox:AddSlider("bxw_ac_delay", { Text = "Delay", Default = 0.1, Min = 0, Max = 2, Rounding = 2 })
    
    local clickPos = nil
    local PosLabel = MiscBox:AddLabel("Pos: Default")
    local SetPointBtn = AddSmartButton(MiscBox, "Set Point (Mobile)", function()
        if not isMobile then Library:Notify("Mobile Only", 2) return end
        Library:Notify("Tap screen...", 2)
        local c; c=UserInputService.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then clickPos=i.Position; PosLabel.TextLabel.Text=string.format("%d,%d",clickPos.X,clickPos.Y); c:Disconnect() end end)
    end)
    -- Safe Text Update
    if isPC then pcall(function() SetPointBtn.TextLabel.Text = "Set Point (Mobile Only)" end) end
    
    local acConn
    AutoClickToggle:OnChanged(function(state)
        if state then
             local last=0
             acConn = AddConnection(RunService.RenderStepped:Connect(function()
                 if tick()-last > AutoClickDelay.Value then
                     last=tick()
                     if isMobile and clickPos then pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton1(clickPos) end)
                     else pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton1(Vector2.new()) end) end
                 end
             end))
        else if acConn then acConn:Disconnect() end end
    end)

    MiscBox:AddDivider()
    MiscBox:AddSlider("bxw_fps", { Text = "FPS Cap", Default = 60, Min = 30, Max = 360, Rounding = 0, Callback = function(v) if setfpscap then setfpscap(v) end end })
    
    local EmoteDropdown = MiscBox:AddDropdown("bxw_emotes", { Text = "Emotes", Values = {"Sit", "Zombie", "Ninja", "Dab"}, Default = "" })
    AddSmartButton(MiscBox, "Play Emote", function()
        local ids = { Sit="rbxassetid://2506281703", Zombie="rbxassetid://616164442", Ninja="rbxassetid://656117878", Dab="rbxassetid://248263260" }
        local h = getHumanoid(); if h then local t = h:LoadAnimation(Instance.new("Animation", {AnimationId=ids[EmoteDropdown.Value]})); t:Play() end
    end)
    
    local GfxBox = MiscTab:AddRightGroupbox("Graphics", "monitor")
    AddSmartButton(GfxBox, "Potato Mode", function()
        Lighting.GlobalShadows=false; Lighting.FogEnd=9e9; Lighting.Brightness=0
        for _,v in pairs(workspace:GetDescendants()) do if v:IsA("BasePart") then v.Material=Enum.Material.SmoothPlastic end end
    end)
    GfxBox:AddToggle("bxw_fullbright", { Text = "Fullbright", Default = false }):OnChanged(function(s) if s then Lighting.Brightness=2; Lighting.ClockTime=14; Lighting.FogEnd=1e10 else Lighting.Brightness=1 end end)
    GfxBox:AddToggle("bxw_xray", { Text = "X-Ray", Default = false }):OnChanged(function(s) for _,v in pairs(workspace:GetDescendants()) do if v:IsA("BasePart") then v.LocalTransparencyModifier = s and 0.5 or 0 end end end)

    ------------------------------------------------
    -- Settings
    ------------------------------------------------
    local SettingsTab = Tabs.Settings
    local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
    MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
    MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
    Library.ToggleKeybind = Options.MenuKeybind
    ThemeManager:SetLibrary(Library) SaveManager:SetLibrary(Library)
    ThemeManager:SetFolder("BxB.Ware_Setting") SaveManager:SetFolder("BxB.Ware_Setting")
    SaveManager:BuildConfigSection(SettingsTab) ThemeManager:ApplyToTab(SettingsTab)

    ------------------------------------------------
    -- Cleanup
    ------------------------------------------------
    Library:OnUnload(function()
        for _, c in ipairs(Connections) do c:Disconnect() end
        if AimbotFOVCircle then AimbotFOVCircle:Remove() end
        if AimbotSnapLine then AimbotSnapLine:Remove() end
        for p in pairs(espDrawings) do removePlayerESP(p) end
        if radarDrawings.bg then radarDrawings.bg:Remove(); radarDrawings.outline:Remove(); radarDrawings.line:Remove() end
        if crosshairLines.h then crosshairLines.h:Remove(); crosshairLines.v:Remove() end
    end)
end

return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then warn("[MainHub] Error:", err) end
end
