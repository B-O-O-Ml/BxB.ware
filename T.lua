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
local isPC = not isMobile -- Simple logic check for primary platform

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
-- 1. Secret + Token Verify (SECURITY UPGRADED)
--====================================================

-- Obfuscated Secret Construction
local _s1 = "BxB.ware"
local _s2 = "-Universal"
local _s3 = "@#$)_%@#^"
local _s4 = "()$@%_)+%(@"
local SECRET_PEPPER = _s1 .. _s2 .. _s3 .. _s4

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

-- Anti-Tamper: Basic Integrity Check
local function IntegrityCheck()
    if iscclosure and not iscclosure(game.HttpGet) then
        return false -- HttpGet was hooked
    end
    return true
end

--====================================================
-- 2. Role System & Device Helpers
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
    -- supportedPlatforms: table e.g. {PC=true, Mobile=false}
    -- Default to PC=true if not specified
    local isSupported = true
    local tag = ""

    if isMobile then
        if supportedPlatforms and supportedPlatforms.Mobile == false then
            isSupported = false
            tag = ' <font color="#FF5555" size="11">[PC Only]</font>'
        end
    end
    
    -- If PC and feature is Mobile only (rare)
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
-- 3. Helper format เวลา/ข้อความ
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

-- Helper Parsers for Updates Tab
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

-- [UPGRADE] Improved Script Info Parser
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
    
    add("<b>Script Information (Full Fetch)</b>")
    add("________________________")
    recurse(decoded, 0)
    
    return table.concat(lines, "\n")
end

--====================================================
-- 4. ฟังก์ชันหลักของ MainHub
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
        LocalPlayer:Kick("Security Error: Invalid Handshake.")
        return
    end

    if getgenv then
        local flagName = keydata._auth_flag
        if not flagName or not getgenv()[flagName] then
            LocalPlayer:Kick("Security Error: Direct execution is not allowed.")
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

    -- [UPGRADE] Enhanced Wrapper for Toggle
    local function AddSmartToggle(groupbox, id, config)
        -- Config Params: Role (string), Platforms (table: {PC=true, Mobile=false}), Tooltip (string)
        local reqRole = config.Role or "free"
        local platforms = config.Platforms
        local baseText = config.Text or id
        local baseTooltip = config.Tooltip or ""
        
        -- Role Logic
        local isLocked = IsLocked(reqRole)
        local roleTag = GetRoleTag(reqRole)
        
        -- Device Logic
        local devTag, isDevSupported = GetDeviceTag(platforms)
        
        -- Combine Text
        config.Text = baseText .. roleTag .. devTag
        
        if isLocked then
            config.Disabled = true
            config.Default = false
            config.Text = baseText .. " <font color='#FF0000'>[LOCKED]</font>" .. devTag
            config.Tooltip = GetLockTooltip(reqRole)
        elseif not isDevSupported then
             -- Warn only, don't strictly disable unless critical
             config.Tooltip = (baseTooltip ~= "" and baseTooltip .. "\n" or "") .. "Feature may not work on your device."
        else
             config.Tooltip = baseTooltip
        end
        
        -- Cleanup custom fields
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
            return groupbox:AddButton(text .. " [LOCKED]", function()
                Library:Notify(GetLockTooltip(reqRole), 3)
            end)
        else
            local btn = groupbox:AddButton(finalText, function()
                if not isDevSupported then
                    Library:Notify("This feature is not supported on your device.", 2)
                end
                callback()
            end)
            if config.Tooltip then
                -- Note: Obsidian AddButton might not natively support tooltips in all versions, 
                -- checking if SetTooltip exists or AddTooltip
                pcall(function() btn:SetTooltip(config.Tooltip) end) 
            end
            return btn
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
            if type(tab.AddRightGroupbox) == "function" then
                return tab:AddRightGroupbox(name, icon)
            elseif type(tab.AddGroupbox) == "function" then
                return tab:AddGroupbox({ Side = 2, Name = name, IconName = icon })
            end
        end
        return nil
    end

    ------------------------------------------------
    -- 4.3 TAB 1: Info (Refactored)
    ------------------------------------------------
    local InfoTab = Tabs.Info
    local startSessionTime = tick()

    local KeyBox = InfoTab:AddLeftGroupbox("Key Info", "key-round")
    local StatsBox = safeAddRightGroupbox(InfoTab, "User Profile & Stats", "bar-chart") -- Moved to Right

    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()

    local rawKey = tostring(keydata.key or "N/A")
    local maskedKey = #rawKey > 4 and string.format("%s-****%s", rawKey:sub(1, 4), rawKey:sub(-3)) or rawKey

    local KeyLabel = safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    local RoleLabel = safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", GetRoleLabel(keydata.role)))
    local StatusLabel = safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", tostring(keydata.status or "active")))
    local HWIDLabel = safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    local NoteLabel = safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", tostring(keydata.note or "-")))
    local CreatedLabel = safeRichLabel(KeyBox, "<b>Created at:</b> Loading...")
    local ExpireLabel = safeRichLabel(KeyBox, "<b>Expire:</b> Loading...")
    local TimeLeftLabel = safeRichLabel(KeyBox, "<b>Time left:</b> Loading...")

    -- User Profile Stats (Moved here from Left)
    local ProfileLabel = safeRichLabel(StatsBox, string.format("<b>Welcome, %s</b>", LocalPlayer.DisplayName))
    safeRichLabel(StatsBox, string.format("User ID: %d", LocalPlayer.UserId))
    safeRichLabel(StatsBox, string.format("Account Age: %d days", LocalPlayer.AccountAge))
    safeRichLabel(StatsBox, string.format("Premium: %s", LocalPlayer.MembershipType.Name))
    
    StatsBox:AddDivider()
    local SessionLabel = safeRichLabel(StatsBox, "Session Time: 00:00:00")
    local TeamLabel = safeRichLabel(StatsBox, "Team: None")
    local PositionLabel = safeRichLabel(StatsBox, "Pos: (0, 0, 0)")
    local ServerRegionLabel = safeRichLabel(StatsBox, "Server Region: Unknown")
    
    -- Diagnostics Groupbox
    local DiagBox = InfoTab:AddLeftGroupbox("System Diagnostics", "activity")
    local function getCheckColor(bool) return bool and '<font color="#55ff55">PASS</font>' or '<font color="#ff5555">FAIL</font>' end
    safeRichLabel(DiagBox, string.format("Drawing API: %s", getCheckColor(Drawing)))
    safeRichLabel(DiagBox, string.format("Hook Metamethod: %s", getCheckColor(hookmetamethod)))
    safeRichLabel(DiagBox, string.format("GetGenv: %s", getCheckColor(getgenv)))
    safeRichLabel(DiagBox, string.format("Request/HttpGet: %s", getCheckColor(request or http_request or (syn and syn.request) or Exec.HttpGet)))
    safeRichLabel(DiagBox, string.format("Websocket: %s", getCheckColor(WebSocket or (syn and syn.websocket))))

    -- Removed Announcements Box

    -- Real-time Stats Loop
    task.spawn(function()
        while true do
            local elapsed = tick() - startSessionTime
            local h = math.floor(elapsed / 3600)
            local m = math.floor((elapsed % 3600) / 60)
            local s = elapsed % 60
            if SessionLabel and SessionLabel.TextLabel then
                SessionLabel.TextLabel.Text = string.format("Session Time: %02d:%02d:%02d", h, m, s)
            end
            
            local root = getRootPart()
            if root and PositionLabel and PositionLabel.TextLabel then
                 local p = root.Position
                 PositionLabel.TextLabel.Text = string.format("Pos: (%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
            end
            
            if TeamLabel and TeamLabel.TextLabel then
                 local team = LocalPlayer.Team
                 local tName = team and team.Name or "Neutral"
                 local tColor = team and team.TeamColor.Color or Color3.new(1,1,1)
                 local hex = tColor:ToHex()
                 TeamLabel.TextLabel.Text = string.format("Team: <font color='#%s'>%s</font>", hex, tName)
            end
            task.wait(1)
        end
    end)
    
    -- Region & Updates logic
    task.spawn(function()
        pcall(function()
            local region = game:GetService("LocalizationService").RobloxLocaleId
            if ServerRegionLabel and ServerRegionLabel.TextLabel then
                ServerRegionLabel.TextLabel.Text = "Client Locale: " .. tostring(region)
            end
        end)
    end)
    
    task.spawn(function()
         -- Updates Tab Content
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
         
         -- [UPGRADE] Full Fetch Script Info
         local okSI, bodySI = pcall(function() return Exec.HttpGet(ScriptInfoUrl) end)
         if okSI and bodySI then
            local fullText = parseScriptInfo(bodySI, HttpService)
             for line in string.gmatch(fullText, "[^\r\n]+") do safeRichLabel(ScriptInfoBox, line) end
         else
             safeRichLabel(ScriptInfoBox, "<font color='#ff5555'>Failed to fetch script info</font>")
         end
    end)

    -- Fetch Key Data Async
    task.spawn(function()
        local remoteKeyData = nil
        pcall(function()
            local url = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/main/Key_System/data.json"
            local dataStr = Exec.HttpGet(url)
            if type(dataStr) == "string" and #dataStr > 0 then
                local ok, decoded = pcall(function() return HttpService:JSONDecode(dataStr) end)
                if ok and decoded and decoded.keys then
                    for _, entry in ipairs(decoded.keys) do
                        if tostring(entry.key) == rawKey or tostring(entry.key) == tostring(keydata.key) then
                            remoteKeyData = entry break
                        end
                    end
                end
            end
        end)

        if remoteKeyData then
            if remoteKeyData.role then RoleLabel.TextLabel.Text = string.format("<b>Role:</b> %s", GetRoleLabel(remoteKeyData.role)) end
            if remoteKeyData.status then StatusLabel.TextLabel.Text = string.format("<b>Status:</b> %s", tostring(remoteKeyData.status)) end
            if remoteKeyData.note and remoteKeyData.note ~= "" then NoteLabel.TextLabel.Text = string.format("<b>Note:</b> %s", tostring(remoteKeyData.note)) end
            if remoteKeyData.hwid_hash then HWIDLabel.TextLabel.Text = string.format("<b>HWID Hash:</b> %s", tostring(remoteKeyData.hwid_hash)) end
        end

        local createdAtText
        if remoteKeyData and remoteKeyData.timestamp then createdAtText = tostring(remoteKeyData.timestamp)
        elseif keydata.timestamp and keydata.timestamp > 0 then createdAtText = formatUnixTime(keydata.timestamp)
        elseif keydata.created_at then createdAtText = tostring(keydata.created_at)
        else createdAtText = "Unknown" end

        local expireTs = tonumber(keydata.expire) or 0
        local expireDisplay = (remoteKeyData and remoteKeyData.expire) and tostring(remoteKeyData.expire) or formatUnixTime(expireTs)
        local timeLeftDisplay = formatTimeLeft(expireTs)

        CreatedLabel.TextLabel.Text = string.format("<b>Created at:</b> %s", createdAtText)
        ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", expireDisplay)
        TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", timeLeftDisplay)

        while true do
            task.wait(1)
            local nowExpire = tonumber(keydata.expire) or expireTs
            if nowExpire and nowExpire > 0 then
                local leftStr = formatTimeLeft(nowExpire)
                if TimeLeftLabel and TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", leftStr) end
            else
                 if TimeLeftLabel and TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = "<b>Time left:</b> Lifetime" end
                 break 
            end
        end
    end)


    --------------------------------------------------------
    -- 2. PLAYER TAB
    --------------------------------------------------------
   local PlayerTab = Tabs.Player
   local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    -- WalkSpeed
    local defaultWalkSpeed = 16
    local walkSpeedEnabled = false
    local WalkSpeedToggle = AddSmartToggle(MoveBox, "bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false, Tooltip = "Modifies Humanoid WalkSpeed" })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = defaultWalkSpeed, Min = 0, Max = 120, Rounding = 0, Compact = false,
        Callback = function(value)
            if not walkSpeedEnabled then return end
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = value end
        end,
    })

    WalkSpeedToggle:OnChanged(function(state)
        walkSpeedEnabled = state
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = state and WalkSpeedSlider.Value or defaultWalkSpeed end
        NotifyAction("WalkSpeed", state)
    end)
    
    AddSmartButton(MoveBox, "Reset WalkSpeed", function()
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = defaultWalkSpeed end
        WalkSpeedSlider:SetValue(defaultWalkSpeed)
        WalkSpeedToggle:SetValue(false)
    end)
    
    -- Auto Run
    local AutoRunToggle = AddSmartToggle(MoveBox, "bxw_autorun", { Text = "Auto Run (Circle)", Default = false, Tooltip = "Makes character walk in circles" })
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

    -- Vehicle Mode
    local VehicleModeToggle = AddSmartToggle(MoveBox, "bxw_vehicle_mode", { Text = "Vehicle Speed Mode", Default = false, Tooltip = "Apply speed to Seat instead of Humanoid" })
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
    -- JumpPower
    local defaultJumpPower = 50
    local jumpPowerEnabled = false
    local JumpPowerToggle = AddSmartToggle(MoveBox, "bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false, Tooltip = "Modifies Humanoid JumpPower" })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = defaultJumpPower, Min = 0, Max = 200, Rounding = 0, Compact = false,
        Callback = function(value)
            if not jumpPowerEnabled then return end
            local hum = getHumanoid()
            if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = value end
        end,
    })

    JumpPowerToggle:OnChanged(function(state)
        jumpPowerEnabled = state
        local hum = getHumanoid()
        if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = state and JumpPowerSlider.Value or defaultJumpPower end
        NotifyAction("JumpPower", state)
    end)
    AddSmartButton(MoveBox, "Reset JumpPower", function()
        local hum = getHumanoid()
        if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = defaultJumpPower end
        JumpPowerSlider:SetValue(defaultJumpPower)
        JumpPowerToggle:SetValue(false)
    end)

    -- Hip Height
    local HipHeightToggle = AddSmartToggle(MoveBox, "bxw_hipheight_toggle", { Text = "Enable Hip Height", Default = false, Tooltip = "Makes character float above ground" })
    local HipHeightSlider = MoveBox:AddSlider("bxw_hipheight", { Text = "Hip Height", Default = 0, Min = 0, Max = 50, Rounding = 1, Compact = false,
        Callback = function(value)
            if not HipHeightToggle.Value then return end
            local hum = getHumanoid()
            if hum then hum.HipHeight = value end
        end
    })
    
    HipHeightToggle:OnChanged(function(state)
        local hum = getHumanoid()
        if hum then hum.HipHeight = state and HipHeightSlider.Value or 0 end
        NotifyAction("Hip Height", state)
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
    local InfJumpToggle = AddSmartToggle(MoveBox, "bxw_infjump", { Text = "Infinite Jump", Default = false, Tooltip = "Allows jumping in mid-air" })
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
    
    local FlyToggle = AddSmartToggle(MoveBox, "bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false, Role = "premium", Tooltip = "Flight using BodyVelocity" })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = flySpeed, Min = 1, Max = 300, Rounding = 0, Compact = false, Callback = function(value) flySpeed = value end })
    
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
            if hum.MoveDirection.Magnitude > 0 then
                local camLook = cam.CFrame.LookVector
                local dot = camLook:Dot(hum.MoveDirection.Unit)
                if dot > 0.5 then moveDir = camLook * hum.MoveDirection.Magnitude
                else moveDir = hum.MoveDirection end
            else
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            end
            if moveDir.Magnitude > 0 then flyBV.Velocity = moveDir.Unit * flySpeed 
            else flyBV.Velocity = Vector3.zero end
            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
        NotifyAction("Fly", true)
    end)
    
    -- Sky Walk
    local SkyWalkToggle = AddSmartToggle(MoveBox, "bxw_skywalk", { Text = "Sky Walk", Default = false, Tooltip = "Walk on invisible platform" })
    local skyWalkPart
    local skyWalkConn
    SkyWalkToggle:OnChanged(function(state)
        if state then
             skyWalkConn = AddConnection(RunService.Heartbeat:Connect(function()
                 local root = getRootPart()
                 if root then
                     if not skyWalkPart then
                         skyWalkPart = Instance.new("Part", workspace)
                         skyWalkPart.Anchored = true
                         skyWalkPart.Size = Vector3.new(10, 1, 10)
                         skyWalkPart.Transparency = 0.5
                         skyWalkPart.Name = "BxB_SkyWalk"
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

    -- Noclip
    local noclipConn
    local NoclipToggle = AddSmartToggle(MoveBox, "bxw_noclip", { Text = MarkRisky("Noclip"), Default = false, Role = "user", Tooltip = "Walk through walls" })
    
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
    AddSmartButton(UtilBox, "Refresh Player List", function() refreshPlayerList() TeleportDropdown:SetValues(playerNames) end)
    
    -- TP
    AddSmartButton(UtilBox, "Teleport", function()
        local targetName = TeleportDropdown.Value
        if not targetName or targetName == "" then Library:Notify("Select player first", 2) return end
        local target = Players:FindFirstChild(targetName)
        local root = getRootPart()
        if not target or not root then Library:Notify("Target/Your character not found", 2) return end
        local tChar = target.Character
        local tRoot = tChar and (tChar:FindFirstChild("HumanoidRootPart") or tChar:FindFirstChild("Torso"))
        if not tRoot then Library:Notify("Target has no root part", 2) return end
        root.CFrame = tRoot.CFrame + Vector3.new(0, 3, 0)
    end, { Role = "premium" })
    
    -- Click Teleport
    local ClickTPToggle = AddSmartToggle(UtilBox, "bxw_clicktp", { Text = "Ctrl + Click TP (Mobile: Tap)", Default = false, Tooltip = "Teleport to mouse/touch position" })
    local clickTpConn
    ClickTPToggle:OnChanged(function(state)
        if state then
            clickTpConn = AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                local doTP = false
                local targetPos = nil
                
                if isMobile then
                    if input.UserInputType == Enum.UserInputType.Touch then
                        doTP = true
                        local cam = workspace.CurrentCamera
                        if cam then
                            local touchPos = input.Position
                            local ray = cam:ViewportPointToRay(touchPos.X, touchPos.Y)
                            local res = workspace:Raycast(ray.Origin, ray.Direction * 1000)
                            if res then targetPos = res.Position end
                        end
                    end
                else
                    if input.UserInputType == Enum.UserInputType.MouseButton1 and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
                         local mouse = LocalPlayer:GetMouse()
                         if mouse.Hit then doTP = true targetPos = mouse.Hit.Position end
                    end
                end

                if doTP and targetPos then
                     local root = getRootPart()
                     if root then root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0)) end
                end
            end))
        else
            if clickTpConn then clickTpConn:Disconnect() clickTpConn = nil end
        end
        NotifyAction("Click TP", state)
    end)
    
    -- Safe Zone
    AddSmartButton(UtilBox, "Safe Zone (Sky)", function()
        local root = getRootPart()
        if root then root.CFrame = CFrame.new(root.Position.X, 10000, root.Position.Z) end
    end)

    UtilBox:AddDivider()
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = playerNames, Default = "", Multi = false, AllowNull = true })
    
    task.spawn(function()
        while true do
            task.wait(5)
            pcall(function() refreshPlayerList() SpectateDropdown:SetValues(playerNames) end)
        end
    end)

    local SpectateToggle = AddSmartToggle(UtilBox, "bxw_spectate_toggle", { Text = "Spectate Player", Default = false, Tooltip = "View another player's camera" })
    local spectateLoop
    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if not cam then return end
        
        if state then
            local name = SpectateDropdown.Value
            if not name or name == "" then Library:Notify("Select player to spectate", 2) SpectateToggle:SetValue(false) return end
            local target = Players:FindFirstChild(name)
            if not target then Library:Notify("Target player not found", 2) SpectateToggle:SetValue(false) return end

            spectateLoop = AddConnection(RunService.RenderStepped:Connect(function()
                if target and target.Character then
                    local hum = target.Character:FindFirstChildOfClass("Humanoid")
                    if hum then cam.CameraSubject = hum end
                end
            end))
            NotifyAction("Spectate", true)
        else
            if spectateLoop then spectateLoop:Disconnect() spectateLoop = nil end
            local hum = getHumanoid()
            if hum then cam.CameraSubject = hum end
            NotifyAction("Spectate", false)
        end
    end)

    -- Sit Button
    AddSmartButton(UtilBox, "Sit", function()
        local hum = getHumanoid()
        if hum then hum.Sit = true end
    end)

    UtilBox:AddDivider()
    UtilBox:AddLabel("Waypoints")
    
    -- [UPGRADE] Waypoint Naming
    local savedWaypoints = {}
    local savedNames = {}
    local WaypointInput = UtilBox:AddInput("bxw_waypoint_name", { Default = "", Text = "Waypoint Name", Placeholder = "Enter name..." })
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", Multi = false, AllowNull = true })
    
    AddSmartButton(UtilBox, "Set Waypoint", function()
        local root = getRootPart()
        if not root then Library:Notify("Character not loaded", 2) return end
        
        local customName = WaypointInput.Value
        if not customName or customName == "" then customName = "WP" .. tostring(#savedNames + 1) end
        
        savedWaypoints[customName] = root.CFrame
        table.insert(savedNames, customName)
        WaypointDropdown:SetValues(savedNames)
        Library:Notify("Saved: " .. customName, 2)
    end)
    AddSmartButton(UtilBox, "Teleport to Waypoint", function()
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
        AddSmartButton(CamBox, "Reset Max Zoom", function() pcall(function() LocalPlayer.CameraMaxZoomDistance = defaultMaxZoom end) MaxZoomSlider:SetValue(defaultMaxZoom) end)
        
        -- [UPGRADE] Free Camera
        local FreeCamToggle = AddSmartToggle(CamBox, "bxw_freecam", { Text = "Free Camera", Default = false, Platforms = {PC=true, Mobile=false}, Tooltip = "Move camera freely with WASD/QE" })
        local freeCamConn
        local freeCamSpeed = 1
        local fcState = { x=0, y=0, z=0 }
        
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
        
        local SkyboxThemes = { ["Default"] = "", ["Space"] = "rbxassetid://11755937810", ["Sunset"] = "rbxassetid://9393701400", ["Midnight"] = "rbxassetid://11755930464" }
        local SkyboxDropdown = CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default", Multi = false })
        local originalSkyCam = nil
        pcall(function() originalSkyCam = game.Lighting:FindFirstChildOfClass("Sky") if originalSkyCam then originalSkyCam = originalSkyCam:Clone() end end)
        local function applySkyCam(name)
            local lighting = game:GetService("Lighting")
            for _, v in pairs(lighting:GetChildren()) do if v:IsA("Sky") then v:Destroy() end end
            if name == "Default" then
                 if originalSkyCam then originalSkyCam:Clone().Parent = lighting end
            else
                local id = SkyboxThemes[name]
                if id and id ~= "" then 
                    local sky = Instance.new("Sky") sky.SkyboxBk = id sky.SkyboxDn = id sky.SkyboxFt = id sky.SkyboxLf = id sky.SkyboxRt = id sky.SkyboxUp = id sky.Parent = lighting 
                end
            end
        end
        SkyboxDropdown:OnChanged(function(value) applySkyCam(value) end)
    end

    ------------------------------------------------
    -- 4.3 ESP & Visuals Tab (Revised & Fixed)
    ------------------------------------------------
    do
        local ESPTab = Tabs.ESP
        local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
        local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")
        local ExtraVisualBox = safeAddRightGroupbox(ESPTab, "Radar", "radar")

        local ESPEnabledToggle = AddSmartToggle(ESPFeatureBox, "bxw_esp_enable", { Text = "Enable ESP", Default = false, Tooltip = "Master Switch" })
        local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box", Multi = false })
        
        -- Individual Features
        local function AddColorToggle(id, text, def, col, tt)
             return ESPFeatureBox:AddToggle(id, { Text = text, Default = def, Tooltip = tt }):AddColorPicker(id.."_color", { Default = col })
        end

        local BoxToggle = AddColorToggle("bxw_esp_box", "Box", true, Color3.fromRGB(255, 255, 255), "Draws 2D box")
        local ChamsToggle = AddColorToggle("bxw_esp_chams", "Chams (Highlight)", false, Color3.fromRGB(0, 255, 0), "See through walls")
        local SkeletonToggle = AddColorToggle("bxw_esp_skeleton", "Skeleton", false, Color3.fromRGB(0, 255, 255), "Draws bone structure")
        local HealthToggle = AddColorToggle("bxw_esp_health", "Health Bar", false, Color3.fromRGB(0, 255, 0), "Shows HP bar")
        local NameToggle = AddColorToggle("bxw_esp_name", "Name Tag", true, Color3.fromRGB(255, 255, 255), "Shows display name")
        local DistToggle = AddColorToggle("bxw_esp_distance", "Distance", false, Color3.fromRGB(255, 255, 255), "Shows distance")
        local TracerToggle = AddColorToggle("bxw_esp_tracer", "Tracer", false, Color3.fromRGB(255, 255, 255), "Line from bottom to player")
        
        local TeamToggle = ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true, Tooltip = "Hide teammates" })
        local WallToggle = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false, Tooltip = "Colors red if not visible" })
        local SelfToggle = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false, Tooltip = "Draw ESP on self" })
        
        local InfoToggle = AddColorToggle("bxw_esp_info", "Target Info", false, Color3.fromRGB(255, 255, 255), "Shows HP, Weapon text")
        local HeadDotToggle = AddColorToggle("bxw_esp_headdot", "Head Dot", false, Color3.fromRGB(255, 0, 0), "Dot on head")
        local ArrowToggle = AddColorToggle("bxw_esp_arrow", "Off-Screen Arrow", false, Color3.fromRGB(255, 100, 0), "Direction indicator")
        local ViewDirToggle = AddColorToggle("bxw_esp_viewdir", "View Direction", false, Color3.fromRGB(255, 255, 0), "Line showing where enemy looks")

        ESPEnabledToggle:OnChanged(function(state) NotifyAction("Global ESP", state) end)
        
        -- Radar
        local RadarToggle = AddSmartToggle(ExtraVisualBox, "bxw_radar_enable", { Text = "Enable 2D Radar", Default = false, Platforms = {PC=true, Mobile=true}, Tooltip = "Minimap" })
        local RadarRangeSlider = ExtraVisualBox:AddSlider("bxw_radar_range", { Text = "Radar Range", Default = 200, Min = 50, Max = 1000, Rounding = 0 })
        local RadarSizeSlider = ExtraVisualBox:AddSlider("bxw_radar_size", { Text = "Radar Scale", Default = 150, Min = 100, Max = 300, Rounding = 0 })
        
        RadarToggle:OnChanged(function(state)
            if not state then
                if radarDrawings.outline then radarDrawings.outline.Visible = false end
                if radarDrawings.line then radarDrawings.line.Visible = false end
                if radarDrawings.bg then radarDrawings.bg.Visible = false end
                for _, p in pairs(radarDrawings.points) do p:Remove() end
                radarDrawings.points = {}
            end
        end)

        -- ESP Settings
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
        end
        
        local RefreshRateSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "ESP Refresh Rate (ms)", Default = 0, Min = 0, Max = 1000, Rounding = 0, Tooltip = "Delay between updates (0=Realtime)" })
        local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Distance Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
        local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Visible Only", Default = false })
        local DistColorToggle = ESPSettingBox:AddToggle("bxw_esp_distcolor", { Text = "Color by Distance", Default = false })

        local CrosshairToggle = AddColorToggle("bxw_crosshair_enable", "Crosshair", false, Color3.fromRGB(255, 255, 255), "Center screen crosshair")
        local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20, Rounding = 0 })
        local CrossThickSlider = ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Crosshair Thickness", Default = 1, Min = 1, Max = 5, Rounding = 0 })
        
        CrosshairToggle:OnChanged(function(state) NotifyAction("Crosshair", state) end)

        local function removePlayerESP(plr)
            if espDrawings[plr] then
                local data = espDrawings[plr]
                -- Clean Drawing Objects
                for k, v in pairs(data) do
                    if k == "Skeleton" and type(v) == "table" then for _, l in pairs(v) do l:Remove() end
                    elseif k == "Highlight" and v then v:Destroy()
                    elseif k == "Health" and type(v) == "table" then if v.Outline then v.Outline:Remove() end if v.Bar then v.Bar:Remove() end
                    elseif v.Remove then v:Remove() end
                end
                espDrawings[plr] = nil
            end
        end

        AddConnection(Players.PlayerRemoving:Connect(function(plr) removePlayerESP(plr) end))

        local function IsTeammate(plr)
            if not TeamToggle.Value then return false end
            if not plr then return false end
            if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then return true end
            if LocalPlayer.TeamColor and plr.TeamColor and LocalPlayer.TeamColor == plr.TeamColor then return true end
            return false
        end

        -- [FIXED] Skeleton Logic for R6/R15
        local function UpdateSkeleton(plr, data, color)
             local char = plr.Character
             if not char then return end
             local hum = char:FindFirstChildOfClass("Humanoid")
             local rigType = hum and hum.RigType
             
             local joints = {}
             if rigType == Enum.HumanoidRigType.R15 then
                 joints = {
                    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"LowerTorso", "HumanoidRootPart"},
                    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
                    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
                    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
                    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
                 }
             else -- R6
                 joints = {
                    {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
                    {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
                 }
             end

             if not data.Skeleton then data.Skeleton = {} end
             
             -- Ensure enough lines
             for i = 1, #joints do
                 if not data.Skeleton[i] then
                     local l = Drawing.new("Line")
                     l.Thickness = 1
                     l.Transparency = 1
                     data.Skeleton[i] = l
                 end
                 
                 local line = data.Skeleton[i]
                 local p1 = char:FindFirstChild(joints[i][1])
                 local p2 = char:FindFirstChild(joints[i][2])
                 
                 if p1 and p2 then
                     local v1, vis1 = workspace.CurrentCamera:WorldToViewportPoint(p1.Position)
                     local v2, vis2 = workspace.CurrentCamera:WorldToViewportPoint(p2.Position)
                     
                     if vis1 and vis2 then
                         line.Visible = true
                         line.From = Vector2.new(v1.X, v1.Y)
                         line.To = Vector2.new(v2.X, v2.Y)
                         line.Color = color
                     else
                         line.Visible = false
                     end
                 else
                     line.Visible = false
                 end
             end
             -- Hide unused lines
             for i = #joints + 1, #data.Skeleton do
                 data.Skeleton[i].Visible = false
             end
        end

        local lastUpdate = 0
        local function updateESP()
            -- [FIX] Refresh Rate Check
            local delayTime = (RefreshRateSlider.Value or 0) / 1000
            if tick() - lastUpdate < delayTime then return end
            lastUpdate = tick()

            if not ESPEnabledToggle.Value then
                for plr, _ in pairs(espDrawings) do removePlayerESP(plr) end
                return
            end

            -- Radar BG
             if RadarToggle.Value then
                 local rSize = RadarSizeSlider.Value
                 local rX, rY = workspace.CurrentCamera.ViewportSize.X - rSize - 20, workspace.CurrentCamera.ViewportSize.Y - rSize - 20
                 if not radarDrawings.bg then
                     radarDrawings.bg = Drawing.new("Square") radarDrawings.bg.Filled = true radarDrawings.bg.Transparency = 0.6 radarDrawings.bg.Color = Color3.new(0.1, 0.1, 0.1) radarDrawings.bg.Visible = true
                 end
                 radarDrawings.bg.Size = Vector2.new(rSize, rSize) radarDrawings.bg.Position = Vector2.new(rX, rY)
                 if not radarDrawings.outline then
                     radarDrawings.outline = Drawing.new("Square") radarDrawings.outline.Visible = true radarDrawings.outline.Filled = false radarDrawings.outline.Transparency = 1 radarDrawings.outline.Color = Color3.new(1,1,1) radarDrawings.outline.Thickness = 2
                 end
                 radarDrawings.outline.Size = Vector2.new(rSize, rSize) radarDrawings.outline.Position = Vector2.new(rX, rY)
            else
                if radarDrawings.bg then radarDrawings.bg.Visible = false radarDrawings.outline.Visible = false end
            end

            local cam = Workspace.CurrentCamera
            if not cam then return end

            for _, plr in ipairs(Players:GetPlayers()) do
                if not plr or not plr.Parent then
                     removePlayerESP(plr)
                     if radarDrawings.points[plr] then radarDrawings.points[plr]:Remove() radarDrawings.points[plr] = nil end
                     continue
                end

                if plr ~= LocalPlayer or (SelfToggle and SelfToggle.Value) then
                    local char = plr.Character
                    if not char or not char.Parent then
                         removePlayerESP(plr)
                         if radarDrawings.points[plr] then radarDrawings.points[plr].Visible = false end
                         continue
                    end

                    local hum  = char:FindFirstChildOfClass("Humanoid")
                    local root = getRootPart()
                    
                    if not hum or hum.Health <= 0 or not root then
                        removePlayerESP(plr)
                        if radarDrawings.points[plr] then radarDrawings.points[plr].Visible = false end
                    else
                        local skipPlayer = false
                        if plr ~= LocalPlayer and IsTeammate(plr) then skipPlayer = true end
                        if not skipPlayer then
                            -- [FIX] Whitelist Logic
                            local list = WhitelistDropdown.Value
                            if list and type(list) == "table" then
                                if table.find(list, plr.Name) then skipPlayer = true end
                            end
                        end

                        if skipPlayer then
                            removePlayerESP(plr)
                            if radarDrawings.points[plr] then radarDrawings.points[plr].Visible = false end
                        else
                            local data = espDrawings[plr]
                            if not data then data = {} espDrawings[plr] = data end

                            -- Radar Update
                            if RadarToggle.Value then
                                local rRange = RadarRangeSlider.Value
                                local rSize = RadarSizeSlider.Value
                                local rCenter = Vector2.new(workspace.CurrentCamera.ViewportSize.X - rSize - 20 + rSize/2, workspace.CurrentCamera.ViewportSize.Y - rSize - 20 + rSize/2)
                                local myRoot = getRootPart()
                                if myRoot then
                                    local relPos = root.Position - myRoot.Position
                                    local angle = math.atan2(relPos.Z, relPos.X) - math.atan2(cam.CFrame.LookVector.Z, cam.CFrame.LookVector.X)
                                    local dist = relPos.Magnitude
                                    local distScale = math.clamp(dist, 0, rRange) / rRange
                                    local dotX = rCenter.X + math.cos(angle + math.pi/2) * (distScale * rSize/2)
                                    local dotY = rCenter.Y + math.sin(angle + math.pi/2) * (distScale * rSize/2)
                                    
                                    if not radarDrawings.points[plr] then
                                        local d = Drawing.new("Circle") d.Filled = true d.Radius = 3 d.Color = Color3.new(1,0,0) radarDrawings.points[plr] = d
                                    end
                                    radarDrawings.points[plr].Visible = true radarDrawings.points[plr].Position = Vector2.new(dotX, dotY)
                                end
                            end

                            local boxCFrame = root.CFrame
                            local cornersWorld = {
                                boxCFrame * CFrame.new(-2, 3, 0), boxCFrame * CFrame.new(2, 3, 0),
                                boxCFrame * CFrame.new(-2, -3, 0), boxCFrame * CFrame.new(2, -3, 0),
                            }
                            local isVisible = true
                            if WallToggle.Value then
                                local rayDir = (root.Position - cam.CFrame.Position)
                                local rayParams = RaycastParams.new()
                                rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                local rayResult = Workspace:Raycast(cam.CFrame.Position, rayDir, rayParams)
                                if rayResult then isVisible = false end
                            end
                            local function getVisColor(optionColor)
                                if WallToggle.Value and not isVisible then return Color3.fromRGB(255, 0, 0) end
                                return optionColor or Color3.fromRGB(255, 255, 255)
                            end

                            if ChamsToggle.Value then
                                local finalChamColor = getVisColor(Options.bxw_esp_chams_color.Value)
                                if not data.Highlight then
                                    local hl = Instance.new("Highlight")
                                    hl.Parent = CoreGui -- [FIX] Parent to CoreGui for safety
                                    data.Highlight = hl
                                end
                                local hl = data.Highlight
                                hl.Adornee = char
                                hl.Enabled = true
                                hl.DepthMode = ChamsVisibleToggle.Value and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                                hl.FillColor = finalChamColor
                                hl.OutlineColor = finalChamColor
                                hl.FillTransparency = ChamsTransSlider.Value
                            else
                                if data.Highlight then data.Highlight.Enabled = false end
                            end
                            
                            -- Skeleton
                            if SkeletonToggle.Value then
                                UpdateSkeleton(plr, data, Options.bxw_esp_skeleton_color.Value)
                            else
                                if data.Skeleton then for _, l in pairs(data.Skeleton) do l.Visible = false end end
                            end

                            local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                            local onScreen = false
                            for i, worldPos in ipairs(cornersWorld) do
                                local screenPos, vis = cam:WorldToViewportPoint(worldPos.Position)
                                if vis then onScreen = true end
                                minX = math.min(minX, screenPos.X)
                                minY = math.min(minY, screenPos.Y)
                                maxX = math.max(maxX, screenPos.X)
                                maxY = math.max(maxY, screenPos.Y)
                            end

                            if not onScreen then
                                -- Hide main elements
                                if data.Box then data.Box.Visible = false end
                                if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end
                                if data.Name then data.Name.Visible = false end
                                if data.Distance then data.Distance.Visible = false end
                                if data.Info then data.Info.Visible = false end
                                if data.ViewDir then data.ViewDir.Visible = false end
                                
                                -- Arrow
                                if ArrowToggle.Value then
                                    if not data.Arrow then data.Arrow = Drawing.new("Triangle") data.Arrow.Filled = true end
                                    local relative = cam.CFrame:PointToObjectSpace(root.Position)
                                    local angle = math.atan2(relative.Y, relative.X)
                                    local center = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                                    local pos = center + Vector2.new(math.cos(angle)*300, math.sin(angle)*300)
                                    data.Arrow.Visible = true
                                    data.Arrow.PointA = pos
                                    data.Arrow.PointB = pos + Vector2.new(math.cos(angle+2.5)*15, math.sin(angle+2.5)*15)
                                    data.Arrow.PointC = pos + Vector2.new(math.cos(angle-2.5)*15, math.sin(angle-2.5)*15)
                                    data.Arrow.Color = Options.bxw_esp_arrow_color.Value
                                else
                                    if data.Arrow then data.Arrow.Visible = false end
                                end
                            else
                                if data.Arrow then data.Arrow.Visible = false end
                                
                                local boxW, boxH = maxX - minX, maxY - minY
                                local finalBoxCol = getVisColor(Options.bxw_esp_box_color.Value)

                                if BoxToggle.Value then
                                    if BoxStyleDropdown.Value == "Box" then
                                        if not data.Box then local sq = Drawing.new("Square") sq.Thickness = 1 sq.Filled = false data.Box = sq end
                                        data.Box.Visible = true data.Box.Transparency = 1 data.Box.Color = finalBoxCol data.Box.Position = Vector2.new(minX, minY) data.Box.Size = Vector2.new(boxW, boxH)
                                        if data.Corners then for _, ln in pairs(data.Corners) do ln.Visible = false end end
                                    else
                                        if not data.Corners then data.Corners = {} for i=1,8 do local ln = Drawing.new("Line") ln.Thickness = 1 ln.Transparency = 1 data.Corners[i] = ln end end
                                        if data.Box then data.Box.Visible = false end
                                        local cw, ch = boxW * 0.25, boxH * 0.25
                                        local tl, tr, bl, br = Vector2.new(minX, minY), Vector2.new(maxX, minY), Vector2.new(minX, maxY), Vector2.new(maxX, maxY)
                                        local lines = data.Corners
                                        local function setL(idx, f, t) lines[idx].Visible = true lines[idx].Color = finalBoxCol lines[idx].From = f lines[idx].To = t end
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
                                    local hp, maxHp = math.clamp(hum.Health, 0, hum.MaxHealth), math.max(hum.MaxHealth, 1)
                                    local barY2 = minY + (maxY - minY) * (1 - (hp / maxHp))
                                    data.Health.Outline.Visible = true data.Health.Outline.Color = Color3.new(0,0,0) data.Health.Outline.From = Vector2.new(hbX, minY) data.Health.Outline.To = Vector2.new(hbX, maxY)
                                    data.Health.Bar.Visible = true data.Health.Bar.Color = Options.bxw_esp_health_color.Value data.Health.Bar.From = Vector2.new(hbX, maxY) data.Health.Bar.To = Vector2.new(hbX, barY2)
                                else
                                    if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end
                                end
                                
                                -- Name
                                if NameToggle.Value then
                                    if not data.Name then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Name = txt end
                                    data.Name.Visible = true data.Name.Color = getVisColor(Options.bxw_esp_name_color.Value) data.Name.Size = NameSizeSlider.Value
                                    data.Name.Text = plr.DisplayName or plr.Name data.Name.Position = Vector2.new((minX + maxX) / 2, minY - 14)
                                else
                                    if data.Name then data.Name.Visible = false end
                                end
                                
                                -- Info (Weapon/HP text)
                                if InfoToggle.Value then
                                    if not data.Info then local txt = Drawing.new("Text") txt.Center = false txt.Outline = true data.Info = txt end
                                    local equipped = "None"
                                    local tool = char:FindFirstChildOfClass("Tool")
                                    if tool then equipped = tool.Name end
                                    data.Info.Visible = true data.Info.Color = Options.bxw_esp_info_color.Value data.Info.Size = 13
                                    data.Info.Text = string.format("HP: %.0f\n%s", hum.Health, equipped)
                                    data.Info.Position = Vector2.new(maxX + 4, minY)
                                else
                                    if data.Info then data.Info.Visible = false end
                                end

                                -- Distance
                                if DistToggle.Value then
                                    if not data.Distance then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Distance = txt end
                                    local dist = (root.Position - cam.CFrame.Position).Magnitude
                                    data.Distance.Visible = true data.Distance.Color = getVisColor(Options.bxw_esp_dist_color.Value) data.Distance.Size = DistSizeSlider.Value
                                    data.Distance.Text = string.format("%.0f Studs", dist) data.Distance.Position = Vector2.new((minX + maxX) / 2, maxY + 2)
                                else
                                    if data.Distance then data.Distance.Visible = false end
                                end
                                
                                -- View Direction
                                if ViewDirToggle.Value then
                                    if not data.ViewDir then data.ViewDir = Drawing.new("Line") data.ViewDir.Thickness = 1 end
                                    local head = char:FindFirstChild("Head")
                                    if head then
                                        local look = head.CFrame.LookVector * 5
                                        local v1, v1v = cam:WorldToViewportPoint(head.Position)
                                        local v2, v2v = cam:WorldToViewportPoint(head.Position + look)
                                        if v1v and v2v then
                                            data.ViewDir.Visible = true data.ViewDir.From = Vector2.new(v1.X, v1.Y) data.ViewDir.To = Vector2.new(v2.X, v2.Y) data.ViewDir.Color = Options.bxw_esp_viewdir_color.Value
                                        else
                                            data.ViewDir.Visible = false
                                        end
                                    end
                                else
                                    if data.ViewDir then data.ViewDir.Visible = false end
                                end
                            end
                        end
                    end
                else
                    removePlayerESP(plr)
                end
            end
        end
        AddConnection(RunService.RenderStepped:Connect(updateESP))
        
        crosshairLines = { h = Drawing.new("Line"), v = Drawing.new("Line") }
        crosshairLines.h.Transparency = 1 crosshairLines.v.Transparency = 1
        crosshairLines.h.Visible = false crosshairLines.v.Visible = false
        AddConnection(RunService.RenderStepped:Connect(function()
            local toggle = Toggles.bxw_crosshair_enable and Toggles.bxw_crosshair_enable.Value
            if toggle then
                local cam = workspace.CurrentCamera
                local cx, cy = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
                local size, thick, col = CrossSizeSlider.Value, CrossThickSlider.Value, Options.bxw_crosshair_color.Value
                crosshairLines.h.Visible = true crosshairLines.h.From = Vector2.new(cx - size, cy) crosshairLines.h.To = Vector2.new(cx + size, cy) crosshairLines.h.Color = col crosshairLines.h.Thickness= thick
                crosshairLines.v.Visible = true crosshairLines.v.From = Vector2.new(cx, cy - size) crosshairLines.v.To = Vector2.new(cx, cy + size) crosshairLines.v.Color = col crosshairLines.v.Thickness= thick
            else
                crosshairLines.h.Visible = false crosshairLines.v.Visible = false
            end
        end))
    end

    ------------------------------------------------
    -- 4.4 Combat & Aimbot Tab (Revised)
    ------------------------------------------------
    do
        local CombatTab = Tabs.Combat
        local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
        local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

        AimBox:AddLabel("Core Settings")
        local AimbotToggle = AddSmartToggle(AimBox, "bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false, Role = "premium", Tooltip = "Auto aim at enemies" })
        local SilentToggle = AddSmartToggle(AimBox, "bxw_silent_enable", { Text = "Silent Aim", Default = false, Role = "vip", Tooltip = "Shoot without moving camera" })

        AimBox:AddLabel("Aim & Target Settings")
        local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest", "Random" }, Default = "Head", Multi = false })
        local UseSmartAimLogic = AimBox:AddToggle("bxw_aim_smart_logic", { Text = "Smart Aim Logic", Default = true, Tooltip = "Calculates best target based on multiple factors" })

        AimBox:AddLabel("FOV Settings")
        local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
        local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
        local DeadzoneSlider = AimBox:AddSlider("bxw_aim_deadzone", { Text = "Deadzone (Pixels)", Default = 0, Min = 0, Max = 50, Rounding = 1 })
        
        -- [UPGRADE] Smoothness 0-5
        local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Aimbot Smoothness", Default = 0.5, Min = 0, Max = 5, Rounding = 2, Tooltip = "Lower is faster" })
        local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
        
        local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false, Tooltip = "Auto shoot when aiming at enemy" })
        local VisibilityToggle = AimBox:AddToggle("bxw_aim_visibility", { Text = "Visibility Check", Default = false })
        local HitChanceSlider = AimBox:AddSlider("bxw_aim_hitchance", { Text = "Hit Chance %", Default = 100, Min = 1, Max = 100, Rounding = 0 })
        
        local FOVColorLabel = AimBox:AddLabel("FOV Color")
        FOVColorLabel:AddColorPicker("bxw_aim_fovcolor", { Default = Color3.fromRGB(255, 255, 255) })
        AimBox:AddDivider()
        
        local AimMethodDropdown = AimBox:AddDropdown("bxw_aim_method", { Text = "Aim Method", Values = { "CameraLock", "MouseDelta" }, Default = "CameraLock", Multi = false })
        local ShowSnapToggle = AimBox:AddToggle("bxw_aim_snapline", { Text = "Show SnapLine", Default = false })
        
        AimBox:AddDivider()
        AimBox:AddLabel("Activation & Extras")
        local AimActivationDropdown = AimBox:AddDropdown("bxw_aim_activation", { Text = "Aim Activation", Values = { "Hold Right Click", "Always On" }, Default = "Hold Right Click", Multi = false })
        
        -- [UPGRADE] Prediction Logic
        local PredToggle = AimBox:AddToggle("bxw_aim_pred", { Text = "Prediction Aim", Default = false, Tooltip = "Predicts movement" })
        local PredSlider = AimBox:AddSlider("bxw_aim_predfactor", { Text = "Prediction Factor", Default = 0.1, Min = 0, Max = 1, Rounding = 2 })

        -- Removed Auto Equip
        
        AimbotToggle:OnChanged(function(state) NotifyAction("Aimbot", state) end)
        
        AimbotFOVCircle = Drawing.new("Circle") AimbotFOVCircle.Transparency = 0.5 AimbotFOVCircle.Filled = false AimbotFOVCircle.Thickness = 1 AimbotFOVCircle.Color = Color3.fromRGB(255, 255, 255)
        AimbotSnapLine = Drawing.new("Line") AimbotSnapLine.Transparency = 0.7 AimbotSnapLine.Visible = false

        AddConnection(RunService.RenderStepped:Connect(function(dt)
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local mouseLoc = UserInputService:GetMouseLocation()

            if ShowFovToggle.Value and AimbotToggle.Value then
                AimbotFOVCircle.Visible = true
                AimbotFOVCircle.Radius = (FOVSlider.Value * 15)
                AimbotFOVCircle.Position = mouseLoc
                AimbotFOVCircle.Color = Options.bxw_aim_fovcolor.Value
            else
                AimbotFOVCircle.Visible = false
            end
            AimbotSnapLine.Visible = false

            if AimbotToggle.Value then
                local activation = AimActivationDropdown.Value
                local isActive = false
                if activation == "Always On" then isActive = true
                elseif activation == "Hold Right Click" then isActive = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                end
                
                if isActive then
                    local bestPlr, bestScore = nil, math.huge
                    local myRoot = getRootPart()
                    
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer then
                            local char = plr.Character
                            local hum = char and char:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Health > 0 then
                                local rootCandidate = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                                if rootCandidate then
                                    local skip = false
                                    if AimTeamCheck.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then skip = true end
                                    if not skip then
                                        local partName = AimPartDropdown.Value
                                        local targetPart = char:FindFirstChild(partName) or rootCandidate
                                        if partName == "Closest" then targetPart = rootCandidate end -- Simplify closest for perf

                                        local screenPos, onScreen = cam:WorldToViewportPoint(targetPart.Position)
                                        if onScreen then
                                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mouseLoc).Magnitude
                                            if dist <= (FOVSlider.Value * 15) then
                                                if VisibilityToggle.Value then
                                                    local rp = RaycastParams.new() rp.FilterDescendantsInstances = { char, LocalPlayer.Character } rp.FilterType = Enum.RaycastFilterType.Blacklist
                                                    local hit = Workspace:Raycast(cam.CFrame.Position, targetPart.Position - cam.CFrame.Position, rp)
                                                    if hit then skip = true end
                                                end

                                                if not skip then
                                                    if dist < bestScore then bestScore = dist bestPlr = { part = targetPart, root = rootCandidate, screenPos = screenPos } end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if bestPlr then
                        local distMouse = (Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y) - mouseLoc).Magnitude
                        if distMouse < DeadzoneSlider.Value then return end

                        if math.random(0, 100) <= HitChanceSlider.Value then
                            local aimPos = bestPlr.part.Position
                            
                            -- [FIXED] Prediction Logic
                            if PredToggle.Value then
                                local vel = bestPlr.root.AssemblyLinearVelocity
                                if vel.Magnitude > 0 then
                                    aimPos = aimPos + (vel * PredSlider.Value)
                                end
                            end
                            
                            if AimMethodDropdown.Value == "MouseDelta" then
                                local targetScreen = cam:WorldToViewportPoint(aimPos)
                                local delta = Vector2.new(targetScreen.X, targetScreen.Y) - mouseLoc
                                local smooth = SmoothSlider.Value
                                -- MouseDelta Smoothness: Lower slider = Stronger smoothing in this library usually, but user asked 0-5
                                -- We'll implement 0 = instant, 5 = very slow
                                local factor = math.clamp(1 - (smooth / 5), 0.1, 1) 
                                mousemoverel(delta.X * factor, delta.Y * factor)
                            else
                                local newCF = CFrame.new(cam.CFrame.Position, aimPos)
                                local smooth = SmoothSlider.Value
                                -- CamLock Smooth: 0 = Instant, 5 = Very Slow
                                if smooth == 0 then
                                    cam.CFrame = newCF
                                else
                                    cam.CFrame = cam.CFrame:Lerp(newCF, 1 / (smooth * 10))
                                end
                            end
                        end
                    end
                end
            end
        end))
    end

    ------------------------------------------------
    -- Server Tab
    ------------------------------------------------
    do
        local ServerTab = Tabs.Server
        local ServerLeft = ServerTab:AddLeftGroupbox("Server Actions", "server")
        local ServerRight = safeAddRightGroupbox(ServerTab, "Connection & Config", "wifi")
        local GameInfoBox = safeAddRightGroupbox(ServerTab, "Game Info", "info")

        AddSmartButton(ServerLeft, "Server Hop", function()
            pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
            NotifyAction("Server Hop", true)
        end)

        AddSmartButton(ServerLeft, "Low Server Hop", function()
             Library:Notify("Searching low server...", 3)
             pcall(function()
                local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
                local list = HttpService:JSONDecode(game:HttpGet(url))
                if list and list.data then
                    for _, s in ipairs(list.data) do
                        if s.playing < s.maxPlayers and s.id ~= game.JobId then
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                            return
                        end
                    end
                end
                Library:Notify("No low server found", 2)
             end)
        end)

        AddSmartButton(ServerLeft, "Rejoin Server", function()
             pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
        end)
        
        ServerLeft:AddButton("Instant Leave", function() game:Shutdown() end)

        local jobInput = ""
        ServerLeft:AddInput("bxw_join_jobid_input", { Default = "", Text = "Input Job ID", Placeholder = "Job ID...", Callback = function(Value) jobInput = Value end })
        AddSmartButton(ServerLeft, "Join Job ID", function()
            if jobInput ~= "" then pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, jobInput, LocalPlayer) end) end
        end)

        local AntiAfkToggle = AddSmartToggle(ServerRight, "bxw_anti_afk", { Text = "Anti-AFK", Default = true, Tooltip = "Prevent idle kick" })
        local antiAfkConn
        AntiAfkToggle:OnChanged(function(state)
            if state then
                if antiAfkConn then antiAfkConn:Disconnect() end
                antiAfkConn = AddConnection(LocalPlayer.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end))
            else
                if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
            end
        end)
        
        ServerRight:AddButton("Copy Job ID", function() if setclipboard then setclipboard(game.JobId) Library:Notify("Copied Job ID", 2) end end)

        local GameNameLabel   = safeRichLabel(GameInfoBox, "<b>Game:</b> Loading...")
        local PlaceIdLabel    = safeRichLabel(GameInfoBox, string.format("<b>PlaceId:</b> %d", game.PlaceId))
        local JobIdLabel      = safeRichLabel(GameInfoBox, string.format("<b>JobId:</b> %s", game.JobId))
        local PlayersLabel    = safeRichLabel(GameInfoBox, "<b>Players:</b> -/-")

        task.spawn(function()
            local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
            if ok and info and info.Name then GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", info.Name) end
        end)
        
        local function updateP() PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d", #Players:GetPlayers()) end
        updateP() Players.PlayerAdded:Connect(updateP) Players.PlayerRemoving:Connect(updateP)
    end

    ------------------------------------------------
    -- 4.5 Misc & System Tab
    ------------------------------------------------
    do
        local MiscTab = Tabs.Misc
        local MiscLeft  = MiscTab:AddLeftGroupbox("Game Tools", "tool")
        local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")

        MiscLeft:AddLabel("Auto Clicker")
        local AutoClickerToggle = AddSmartToggle(MiscLeft, "bxw_autoclicker", { Text = "Enable Auto Click", Default = false, Tooltip = "Simulate clicks" })
        AutoClickerToggle:AddKeyPicker("AutoClickKey", { Default = "V", Text = "Toggle" })
        local AutoClickDelaySlider = MiscLeft:AddSlider("bxw_autoclick_delay", { Text = "Click Delay (s)", Default = 0.1, Min = 0, Max = 2, Rounding = 2 })
        
        -- [FIXED] Mobile Set Point Error
        local clickPosition = nil
        local PositionLabel = MiscLeft:AddLabel("Pos: Default")
        local SetPointBtn = AddSmartButton(MiscLeft, "Set Click Point (Mobile)", function()
             if not isMobile then Library:Notify("Mobile only feature.", 2) return end
             Library:Notify("Tap screen to set point.", 3)
             local con
             con = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    clickPosition = Vector2.new(input.Position.X, input.Position.Y)
                    PositionLabel.TextLabel.Text = string.format("Pos: %d, %d", clickPosition.X, clickPosition.Y)
                    Library:Notify("Point Set!", 2)
                    con:Disconnect()
                end
             end)
        end)
        
        -- [ERROR FIX] Check if SetPointBtn has TextLabel property or use Library method
        if not isMobile then
             if SetPointBtn.TextLabel then SetPointBtn.TextLabel.Text = "Set Point (Mobile Only)" 
             elseif SetPointBtn.SetText then SetPointBtn:SetText("Set Point (Mobile Only)") end
        end
        
        local autoClickConn
        AutoClickerToggle:OnChanged(function(state)
            if state then
                 local lastClick = 0
                 autoClickConn = AddConnection(RunService.RenderStepped:Connect(function()
                     if not Toggles.bxw_autoclicker.Value then return end
                     if tick() - lastClick > AutoClickDelaySlider.Value then
                         lastClick = tick()
                         if isMobile and clickPosition then
                             pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(clickPosition) end)
                         else
                             pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(Vector2.new()) end)
                         end
                     end
                 end))
            else
                 if autoClickConn then autoClickConn:Disconnect() end
            end
            NotifyAction("Auto Clicker", state)
        end)
        
        MiscLeft:AddDivider()
        MiscLeft:AddSlider("bxw_fps_cap", { Text = "FPS Cap", Default = 60, Min = 30, Max = 360, Rounding = 0, Callback = function(v) if setfpscap then setfpscap(v) end end })
        
        local GfxBox = MiscTab:AddRightGroupbox("Graphics & Visuals", "monitor")
        AddSmartButton(GfxBox, "Potato Mode", function()
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
            Lighting.Brightness = 0
            for _, v in pairs(Workspace:GetDescendants()) do
                if v:IsA("BasePart") and not v:IsA("MeshPart") then v.Material = Enum.Material.SmoothPlastic v.CastShadow = false end
            end
        end)

        local FullbrightToggle = AddSmartToggle(GfxBox, "bxw_fullbright", { Text = "Fullbright", Default = false, Tooltip = "Max brightness" })
        local fbLoop
        FullbrightToggle:OnChanged(function(state)
            if state then
                fbLoop = AddConnection(RunService.LightingChanged:Connect(function()
                    Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e10 Lighting.GlobalShadows = false Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                end))
                Lighting.Brightness = 2 Lighting.ClockTime = 14
            else
                if fbLoop then fbLoop:Disconnect() fbLoop = nil end
            end
        end)

        local XrayTransSlider = GfxBox:AddSlider("bxw_xray_val", { Text = "X-Ray Transparency", Default = 0.5, Min = 0.1, Max = 0.9, Rounding = 1 })
        local XrayToggle = GfxBox:AddToggle("bxw_xray", { Text = "X-Ray", Default = false })
        XrayToggle:OnChanged(function(state)
             for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then
                    v.LocalTransparencyModifier = state and XrayTransSlider.Value or 0
                end
            end
        end)
    end

    ------------------------------------------------
    -- 4.6 Settings Tab
    ------------------------------------------------
    do
        local SettingsTab = Tabs.Settings
        local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
        
        MenuGroup:AddToggle("ForceNotify", { Text = "Force Notification", Default = true })
        MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end })
        MenuGroup:AddToggle("ShowCustomCursor", { Text = "Custom Cursor", Default = true, Callback = function(Value) Library.ShowCustomCursor = Value end })
        MenuGroup:AddDropdown("NotificationSide", { Values = { "Left", "Right" }, Default = "Right", Text = "Notification Side", Callback = function(Value) Library:SetNotifySide(Value) end })
        MenuGroup:AddDivider()
        MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = false, Text = "Menu keybind" })
        MenuGroup:AddLabel("Panic Bind"):AddKeyPicker("PanicKeybind", { Default = "End", NoUI = false, Text = "Panic (Unload)", Callback = function() Library:Unload() end })

        MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
        Library.ToggleKeybind = Options.MenuKeybind
        ThemeManager:SetLibrary(Library) SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings() SaveManager:SetIgnoreIndexes({ "MenuKeybind", "Key Info", "Game Info" })
        ThemeManager:SetFolder("BxB.Ware_Setting") SaveManager:SetFolder("BxB.Ware_Setting")
        SaveManager:BuildConfigSection(SettingsTab) ThemeManager:ApplyToTab(SettingsTab)
        SaveManager:LoadAutoloadConfig()
    end

    ------------------------------------------------
    -- Watermark
    ------------------------------------------------
    pcall(function()
        Library:SetWatermarkVisibility(true)
        local lastUpdate = 0
        AddConnection(RunService.RenderStepped:Connect(function()
            if tick() - lastUpdate >= 1 then
                lastUpdate = tick()
                local ping = 0
                pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                local fps = math.floor(1 / math.max(RunService.RenderStepped:Wait(), 0.001))
                Library:SetWatermark(string.format("BxB.ware | Universal | FPS: %d | Ping: %d ms | %s", fps, ping, os.date("%H:%M:%S")))
            end
        end))
    end)


    ------------------------------------------------
    -- 4.7 Clean Up
    ------------------------------------------------
    if Library and type(Library.OnUnload) == "function" then
        Library:OnUnload(function()
            for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
            if espDrawings then
                for _, plrData in pairs(espDrawings) do
                    for _, item in pairs(plrData) do
                        if type(item) == "table" then for _, d in pairs(item) do pcall(function() d:Remove() end) end
                        elseif typeof(item) == "Instance" then pcall(function() item:Destroy() end)
                        elseif item.Remove then pcall(function() item:Remove() end) end
                    end
                end
            end
            if radarDrawings then
                if radarDrawings.outline then radarDrawings.outline:Remove() end
                if radarDrawings.line then radarDrawings.line:Remove() end
                if radarDrawings.bg then radarDrawings.bg:Remove() end
                for _, p in pairs(radarDrawings.points) do p:Remove() end
            end
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
