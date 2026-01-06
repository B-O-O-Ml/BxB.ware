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

--====================================================
-- 0.1 Device & Compatibility Check System
--====================================================
local DeviceType = "PC"
if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
    local screenSize = workspace.CurrentCamera.ViewportSize
    if screenSize.X > 800 and screenSize.Y > 600 then
        DeviceType = "Tablet"
    else
        DeviceType = "Mobile"
    end
elseif UserInputService.TouchEnabled and UserInputService.MouseEnabled then
    DeviceType = "Hybrid/Tablet"
else
    DeviceType = "PC"
end

-- Helper to check feature support
local function IsFeatureSupported(featureName)
    local unsupportedOnMobile = {
        ["ProximityPrompt"] = false, -- Example
        ["Keybinds"] = false,
    }
    
    if (DeviceType == "Mobile" or DeviceType == "Tablet") and unsupportedOnMobile[featureName] ~= nil then
        return false
    end
    return true
end

-- Helper to format text based on device support
local function FormatFeatureName(name, featureType)
    local text = name
    if not IsFeatureSupported(featureType) then
        text = string.format('<font color="#888888">%s [PC Only]</font>', name)
    end
    return text
end

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

-- [SEC-SYNC] Updated to match KeyMain.lua 100%
local SECURITY_PREFIX = "BxB.Ware"
local SECURITY_SALT   = SECURITY_PREFIX .. "_{SECURE}_" .. "9981-Universal-V2"

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
    
    -- [SEC-FIX] Use UTC Date (!%Y%m%d) to match KeyMain logic strictly
    -- This fixes "Invalid Handshake" caused by timezone diffs
    local datePart = os.date("!%Y%m%d") 

    local raw = table.concat({
        SECURITY_PREFIX,
        SECURITY_SALT,
        k,
        hw,
        role,
        datePart,
        tostring(#k),
    }, "||") -- [SEC-FIX] Delimiter changed to || match KeyMain

    local h = fnv1a32(raw)
    return ("%08X"):format(h)
end

-- Anti-Tamper: Basic Integrity Check
local function IntegrityCheck()
    -- เช็คก่อนว่าฟังก์ชัน iscclosure มีอยู่จริงไหม ค่อยเรียกใช้
    if iscclosure then 
        if not iscclosure(game.HttpGet) then
            return false
        end
    end
    return true
end
--[[
local function IntegrityCheck()
    if iscclosure and not iscclosure(game.HttpGet) then
        return false -- HttpGet was hooked
    end
    return true
end 
]]
--====================================================
-- 2. Role System & RichText Helpers
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

-- Function เช็คว่ามีสิทธิ์พอไหม
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

local function GetFeatureTag(reqRole)
    reqRole = NormalizeRole(reqRole)
    if reqRole == "free" then return "" end
    if reqRole == "user" then return ' <font color="#FFFFFF" size="11">[User]</font>' end
    if reqRole == "premium" then return ' <font color="#FFD700" size="11">[Premium]</font>' end
    if reqRole == "vip" then return ' <font color="#FF00FF" size="11">[VIP]</font>' end
    if reqRole == "staff" then return ' <font color="#00FFFF" size="11">[Staff]</font>' end
    return ""
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
        -- [FIX] Text Wrapping & AutoSizing
        lbl.TextLabel.TextWrapped = true
        lbl.TextLabel.AutomaticSize = Enum.AutomaticSize.Y
        lbl.TextLabel.Size = UDim2.new(1, 0, 0, 0)
        lbl.TextLabel.TextYAlignment = Enum.TextYAlignment.Top
        lbl.TextLabel.TextXAlignment = Enum.TextXAlignment.Left
    end
    return lbl
end

-- Helper Parsers for Updates Tab (Copied from KeyMain for independence)
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

--====================================================
-- 4. ฟังก์ชันหลักของ MainHub
--     (เรียกจาก KeyUI: startFn(Exec, keydata, authToken))
--====================================================

local function MainHub(Exec, keydata, authToken)
    ---------------------------------------------
    -- 4.1 ตรวจ Security: Exec + keydata + token + Flag
    ---------------------------------------------
    
    -- 1. Anti-Tamper Check
    if not IntegrityCheck() then
        LocalPlayer:Kick("Security Error: Environment Tampered.")
        return
    end

    if type(Exec) ~= "table" or type(Exec.HttpGet) ~= "function" then
        warn("[MainHub] Exec invalid")
        return
    end

    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then
        warn("[MainHub] keydata invalid")
        return
    end

    -- 2. Token Check
    local expected = buildExpectedToken(keydata)
    if authToken ~= expected then
        warn("[MainHub] Invalid auth token, abort")
        LocalPlayer:Kick("Security Error: Invalid Handshake.")
        return
    end

    -- 3. Environment Flag Check (Dual-Layer Handshake)
    if getgenv then
        local flagName = keydata._auth_flag
        if not flagName or not getgenv()[flagName] then
            warn("[MainHub] Missing auth flag. Direct execution detected.")
            LocalPlayer:Kick("Security Error: Direct execution is not allowed. Use KeyUI.")
            return
        end
        -- Clear the flag to prevent reuse (One-time handshake)
        getgenv()[flagName] = nil
    end

    -- Crosshair & Aimbot Drawings storage (Defined here for cleanup access)
    local crosshairLines = nil
    local AimbotFOVCircle = nil
    local AimbotSnapLine = nil

    -- ESP Drawings Storage moved to MainHub scope so OnUnload can access it
    local espDrawings = {}

    -- Radar storage
    local radarDrawings = { points = {}, outline = nil, line = nil, bg = nil }

    -- normalize role
    keydata.role = NormalizeRole(keydata.role)
    local MyRole = keydata.role -- Cache current role

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

    -- [FEATURE] Helper Functions for Locked UI and Tooltips
    
    local function IsLocked(reqRole)
        return not RoleAtLeast(MyRole, reqRole)
    end

    local function GetLockTooltip(reqRole)
        return "Requires " .. string.upper(reqRole) .. " rank or higher"
    end
    
    -- Helper to generate Tooltip with Status and Role
    local function GenTooltip(desc, reqRole)
        local tt = desc or ""
        if reqRole and reqRole ~= "free" then
            tt = tt .. " [" .. reqRole:upper() .. "]"
        end
        return tt
    end

    -- Wrapper for AddToggle with Device Check & Locking
    local function AddLockedToggle(groupbox, id, config)
        local reqRole = config.Role or "free"
        local featureName = config.Text or id
        config.Role = nil -- Clean up before passing to lib
        
        -- Add RichText Tag
        config.Text = featureName .. GetFeatureTag(reqRole)
        
        -- Append Tooltip
        local baseTooltip = config.Tooltip or ""
        
        if IsLocked(reqRole) then
            config.Disabled = true
            config.Default = false
            config.Text = config.Text .. " <font color='#FF0000'>[LOCKED]</font>"
            config.Tooltip = (baseTooltip ~= "" and baseTooltip .. "\n" or "") .. GetLockTooltip(reqRole)
        else
            config.Tooltip = GenTooltip(baseTooltip, reqRole)
        end
        
        return groupbox:AddToggle(id, config)
    end

    -- Wrapper for AddButton
    local function AddLockedButton(groupbox, text, callback, reqRole, tooltip)
        local displayText = text .. GetFeatureTag(reqRole)
        
        if IsLocked(reqRole) then
            return groupbox:AddButton(displayText .. " [LOCKED]", function()
                Library:Notify(GetLockTooltip(reqRole), 3)
            end)
        else
            local btn = groupbox:AddButton(displayText, callback)
            if tooltip then 
                -- Library 'AddButton' might not support Tooltip natively in arguments depending on version, 
                -- but if it returns an object we can try to set it if supported.
                -- For Obsidian, usually buttons don't have hover tooltips in same way as toggles.
            end
            return btn
        end
    end

    -- 1) สร้าง Window
    local Window = Library:CreateWindow({
        Title  = "BxB.ware [" .. DeviceType .. "]",
        Footer = '<b><font color="#B563FF">BxB.ware | Universal | ' .. DeviceType .. ' Client</font></b>',

        Icon = "84528813312016",

        Center   = true,
        Size     = UDim2.fromOffset(720, 600),

        AutoShow         = true,
        Resizable        = true,
        NotifySide       = "Right",
        ShowCustomCursor = (DeviceType == "PC"), -- Custom cursor only on PC

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
        -- [NEW TAB] Updates
        Updates = Window:AddTab({
            Name        = "Updates",
            Icon        = "rss",
            Description = "Changelogs & News",
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

        Server = Window:AddTab({
            Name        = "Server",
            Icon        = "server",
            Description = "Hop / Rejoin / Anti-AFK",
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
    -- 4.3 TAB 1: Info [Modified Layout & Upgraded]
    ------------------------------------------------
    local InfoTab = Tabs.Info
    local startSessionTime = tick()

    local KeyBox = InfoTab:AddLeftGroupbox("Key Information", "key-round")

    safeRichLabel(KeyBox, '<font size="14"><b>Key Information</b></font>')
    KeyBox:AddDivider()

    local rawKey = tostring(keydata.key or "N/A")
    local maskedKey
    if #rawKey > 4 then
        maskedKey = string.format("%s-****%s", rawKey:sub(1, 4), rawKey:sub(-3))
    else
        maskedKey = rawKey
    end

    -- Create Labels immediately
    local KeyLabel = safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    local RoleLabel = safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", GetRoleLabel(keydata.role)))
    local StatusLabel = safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", tostring(keydata.status or "active")))
    local HWIDLabel = safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))
    local NoteLabel = safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", tostring(keydata.note or "-")))
    local CreatedLabel = safeRichLabel(KeyBox, "<b>Created at:</b> Loading...")
    local ExpireLabel = safeRichLabel(KeyBox, "<b>Expire:</b> Loading...")
    local TimeLeftLabel = safeRichLabel(KeyBox, "<b>Time left:</b> Loading...")

    -- [MODIFIED] Moved User Profile & Stats here (Replaces Announcements)
    local StatsBox = InfoTab:AddRightGroupbox("User Profile & Stats", "bar-chart")
    local UserThumb = "rbxthumb://type=AvatarHeadShot&id="..LocalPlayer.UserId.."&w=150&h=150"
    local ProfileLabel = safeRichLabel(StatsBox, string.format("<b>Welcome, %s</b>", LocalPlayer.DisplayName))
    safeRichLabel(StatsBox, string.format("User ID: %d", LocalPlayer.UserId))
    safeRichLabel(StatsBox, string.format("Account Age: %d days", LocalPlayer.AccountAge))
    safeRichLabel(StatsBox, string.format("Premium: %s", LocalPlayer.MembershipType.Name))
    safeRichLabel(StatsBox, string.format("Device: %s", DeviceType))
    
    StatsBox:AddDivider()
    local SessionLabel = safeRichLabel(StatsBox, "Session Time: 00:00:00")
    local TeamLabel = safeRichLabel(StatsBox, "Team: None")
    local PositionLabel = safeRichLabel(StatsBox, "Pos: (0, 0, 0)")
    local ServerRegionLabel = safeRichLabel(StatsBox, "Server Region: Unknown")
    
    -- [UPGRADE] Diagnostics Groupbox
    local DiagBox = InfoTab:AddLeftGroupbox("System Diagnostics", "activity")
    local function getCheckColor(bool) return bool and '<font color="#55ff55">PASS</font>' or '<font color="#ff5555">FAIL</font>' end
    
    safeRichLabel(DiagBox, string.format("Drawing API: %s", getCheckColor(Drawing)))
    safeRichLabel(DiagBox, string.format("Hook Metamethod: %s", getCheckColor(hookmetamethod)))
    safeRichLabel(DiagBox, string.format("GetGenv: %s", getCheckColor(getgenv)))
    safeRichLabel(DiagBox, string.format("Request/HttpGet: %s", getCheckColor(request or http_request or (syn and syn.request) or Exec.HttpGet)))
    safeRichLabel(DiagBox, string.format("Websocket: %s", getCheckColor(WebSocket or (syn and syn.websocket))))

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
            
            -- Update Position & Team
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
    
    -- Server Region Mockup
    task.spawn(function()
        pcall(function()
            local region = game:GetService("LocalizationService").RobloxLocaleId
            if ServerRegionLabel and ServerRegionLabel.TextLabel then
                ServerRegionLabel.TextLabel.Text = "Client Locale: " .. tostring(region)
            end
        end)
    end)
    
    -- [FIXED] Updates Tab Content - Fetch Full Script Information
    task.spawn(function()
         local UpdatesTab = Tabs.Updates
         local ChangelogBox = UpdatesTab:AddLeftGroupbox("Latest Changes", "rss")
         local ScriptInfoBox = UpdatesTab:AddRightGroupbox("Script Information", "file-text")
         
         local ChangeLogUrl = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/changelog.json"
         local ScriptInfoUrl = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/scriptinfo.json"
         
         -- Fetch Changelog
         local okCL, bodyCL = pcall(function() return Exec.HttpGet(ChangeLogUrl) end)
         if okCL then
             local _, txt = parseChangelogBody(bodyCL, HttpService)
             for line in string.gmatch(txt, "[^\r\n]+") do
                 safeRichLabel(ChangelogBox, line)
             end
         else
             safeRichLabel(ChangelogBox, "<font color='#ff5555'>Failed to fetch changelog</font>")
         end
         
         -- Fetch Script Info (Use Raw Text Fetch + Manual Parse simulation if possible, or just dump rich text)
         local okSI, bodySI = pcall(function() return Exec.HttpGet(ScriptInfoUrl) end)
         if okSI and bodySI then
             -- Try to decode to verify it's valid, but display all info more comprehensively
            local decoded = HttpService:JSONDecode(bodySI)
            if decoded then
                safeRichLabel(ScriptInfoBox, "<b>Hub Name:</b> " .. tostring(decoded.hub_name))
                safeRichLabel(ScriptInfoBox, "<b>Version:</b> " .. tostring(decoded.version))
                safeRichLabel(ScriptInfoBox, "<b>Channel:</b> " .. tostring(decoded.channel or "Release"))
                safeRichLabel(ScriptInfoBox, "<b>Last Update:</b> " .. tostring(decoded.last_update))
                safeRichLabel(ScriptInfoBox, " ")
                if decoded.description then
                    safeRichLabel(ScriptInfoBox, "<b>Description:</b>")
                    local desc = decoded.description.long or decoded.description
                    if type(desc) == "string" then
                        -- Wrap long text manually if needed
                         safeRichLabel(ScriptInfoBox, desc)
                    end
                end
                
                if decoded.features then
                     safeRichLabel(ScriptInfoBox, " ")
                     safeRichLabel(ScriptInfoBox, "<b>Main Features:</b>")
                     for k, v in pairs(decoded.features) do
                         if type(v) == "table" then
                             safeRichLabel(ScriptInfoBox, string.format("• %s: %s", k, v.description or ""))
                         end
                     end
                end
            end
         else
             safeRichLabel(ScriptInfoBox, "<font color='#ff5555'>Failed to fetch script info</font>")
         end
    end)

    -- [OPTIMIZATION] Fetch Key Data Asynchronously
    task.spawn(function()
        local remoteKeyData = nil
        pcall(function()
            local url = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/main/Key_System/data.json"
            local dataStr = Exec.HttpGet(url)
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
                if TimeLeftLabel and TimeLeftLabel.TextLabel then 
                    TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", leftStr) 
                end
            else
                 if TimeLeftLabel and TimeLeftLabel.TextLabel then 
                    TimeLeftLabel.TextLabel.Text = "<b>Time left:</b> Lifetime" 
                 end
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
    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false, Tooltip = "Modifies Humanoid WalkSpeed" })
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
    
    MoveBox:AddButton("Reset WalkSpeed", function()
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = defaultWalkSpeed end
        WalkSpeedSlider:SetValue(defaultWalkSpeed)
        WalkSpeedToggle:SetValue(false)
    end)
    
    -- Auto Run
    local AutoRunToggle = MoveBox:AddToggle("bxw_autorun", { Text = "Auto Run (Circle)", Default = false, Tooltip = "Runs in a circle automatically" })
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
    local VehicleModeToggle = MoveBox:AddToggle("bxw_vehicle_mode", { Text = "Vehicle Speed Mode", Default = false, Tooltip = "Apply speed to Seat instead of Humanoid" })
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
    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false, Tooltip = "Modifies Humanoid JumpPower" })
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
    MoveBox:AddButton("Reset JumpPower", function()
        local hum = getHumanoid()
        if hum then pcall(function() hum.UseJumpPower = true end) hum.JumpPower = defaultJumpPower end
        JumpPowerSlider:SetValue(defaultJumpPower)
        JumpPowerToggle:SetValue(false)
    end)

    -- Hip Height
    local HipHeightToggle = MoveBox:AddToggle("bxw_hipheight_toggle", { Text = "Enable Hip Height", Default = false, Tooltip = "Levitate above ground" })
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
    local MovePresetDropdown = MoveBox:AddDropdown("bxw_move_preset", { Text = "Movement Preset", Values = { "Default", "Normal", "Fast", "Ultra" }, Default = "Default", Multi = false, Tooltip = "Quick speed settings" })
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
    local InfJumpToggle = MoveBox:AddToggle("bxw_infjump", { Text = "Infinite Jump", Default = false, Tooltip = "Jump in air indefinitely" })
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
    
    local FlyToggle = AddLockedToggle(MoveBox, "bxw_fly", { Text = MarkRisky("Fly (Smooth)"), Default = false, Role = "premium", Tooltip = "Fly smoothly using camera direction" })
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
                if dot > 0.5 then
                    moveDir = camLook * hum.MoveDirection.Magnitude
                else
                    moveDir = hum.MoveDirection
                end
            else
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            end

            if moveDir.Magnitude > 0 then 
                flyBV.Velocity = moveDir.Unit * flySpeed 
            else 
                flyBV.Velocity = Vector3.zero 
            end
            
            flyBG.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
        end))
        NotifyAction("Fly", true)
    end)
    
    -- Sky Walk
    local SkyWalkToggle = MoveBox:AddToggle("bxw_skywalk", { Text = "Sky Walk", Default = false, Tooltip = "Creates a platform under you" })
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
    local NoclipToggle = AddLockedToggle(MoveBox, "bxw_noclip", { Text = MarkRisky("Noclip"), Default = false, Role = "user", Tooltip = "Walk through walls" })
    
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
    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = playerNames, Default = "", Multi = false, AllowNull = true, Tooltip = "Select a player to TP" })
    UtilBox:AddButton("Refresh Player List", function() refreshPlayerList() TeleportDropdown:SetValues(playerNames) end)
    
    -- TP
    AddLockedButton(UtilBox, "Teleport", function()
        local targetName = TeleportDropdown.Value
        if not targetName or targetName == "" then Library:Notify("Select player first", 2) return end
        local target = Players:FindFirstChild(targetName)
        local root = getRootPart()
        if not target or not root then Library:Notify("Target/Your character not found", 2) return end
        local tChar = target.Character
        local tRoot = tChar and (tChar:FindFirstChild("HumanoidRootPart") or tChar:FindFirstChild("Torso"))
        if not tRoot then Library:Notify("Target has no root part", 2) return end
        root.CFrame = tRoot.CFrame + Vector3.new(0, 3, 0)
    end, "premium", "Teleport to selected player")
    
    -- [UPGRADE] Click Teleport (Mobile Support Added)
    local ClickTPToggle = UtilBox:AddToggle("bxw_clicktp", { Text = "Ctrl + Click TP (Mobile: Tap)", Default = false, Tooltip = "Teleport to mouse/tap position" })
    local clickTpConn
    ClickTPToggle:OnChanged(function(state)
        if state then
            clickTpConn = AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                
                local doTP = false
                local targetPos = nil
                
                -- Mobile Logic: Touch
                if isMobile then
                    if input.UserInputType == Enum.UserInputType.Touch then
                        doTP = true
                        -- Need to find 3D position from touch
                        local cam = workspace.CurrentCamera
                        if cam then
                            local touchPos = input.Position
                            local ray = cam:ViewportPointToRay(touchPos.X, touchPos.Y)
                            local res = workspace:Raycast(ray.Origin, ray.Direction * 1000)
                            if res then
                                targetPos = res.Position
                            end
                        end
                    end
                else
                    -- PC Logic: Ctrl + Click
                    if input.UserInputType == Enum.UserInputType.MouseButton1 and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
                         local mouse = LocalPlayer:GetMouse()
                         if mouse.Hit then
                             doTP = true
                             targetPos = mouse.Hit.Position
                         end
                    end
                end

                if doTP and targetPos then
                     local root = getRootPart()
                     if root then
                         root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                     end
                end
            end))
        else
            if clickTpConn then clickTpConn:Disconnect() clickTpConn = nil end
        end
        NotifyAction("Click TP", state)
    end)
    
    -- Safe Zone
    UtilBox:AddButton("Safe Zone (Sky)", function()
        local root = getRootPart()
        if root then
            root.CFrame = CFrame.new(root.Position.X, 10000, root.Position.Z)
        end
    end)

    UtilBox:AddDivider()
    -- [FIXED] Spectate Feature
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = playerNames, Default = "", Multi = false, AllowNull = true, Tooltip = "Select player to watch" })
    
    -- Update list constantly for dropdown
    task.spawn(function()
        while true do
            task.wait(5)
            pcall(function()
                refreshPlayerList()
                SpectateDropdown:SetValues(playerNames)
            end)
        end
    end)

    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", { Text = "Spectate Player", Default = false, Tooltip = "Switch camera to target" })
    local spectateLoop
    SpectateToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        if not cam then return end
        
        if state then
            local name = SpectateDropdown.Value
            if not name or name == "" then 
                Library:Notify("Select player to spectate", 2) 
                SpectateToggle:SetValue(false) 
                return 
            end
            
            local target = Players:FindFirstChild(name)
            if not target then
                Library:Notify("Target player not found", 2)
                SpectateToggle:SetValue(false)
                return
            end

            -- Loop to ensure camera stays on target if they respawn
            spectateLoop = AddConnection(RunService.RenderStepped:Connect(function()
                if target and target.Character then
                    local hum = target.Character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        cam.CameraSubject = hum
                    end
                end
            end))
            NotifyAction("Spectate", true)
        else
            if spectateLoop then spectateLoop:Disconnect() spectateLoop = nil end
            local hum = getHumanoid()
            if hum then 
                cam.CameraSubject = hum 
            end
            NotifyAction("Spectate", false)
        end
    end)

    -- Sit Button
    UtilBox:AddButton("Sit", function()
        local hum = getHumanoid()
        if hum then hum.Sit = true end
    end)

    UtilBox:AddDivider()
    UtilBox:AddLabel("Waypoints")
    local savedWaypoints = {}
    local savedNames = {}
    
    -- [UPGRADE] Waypoint Name Input
    local WaypointInputStr = "Point"
    UtilBox:AddInput("bxw_waypoint_name_in", {
        Default = "Point",
        Text = "Waypoint Name",
        Placeholder = "Enter name...",
        Callback = function(val) WaypointInputStr = val end
    })

    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", Multi = false, AllowNull = true, Tooltip = "Saved Locations" })
    UtilBox:AddButton("Set Waypoint", function()
        local root = getRootPart()
        if not root then Library:Notify("Character not loaded", 2) return end
        
        local name = WaypointInputStr
        if not name or name == "" then name = "WP" .. tostring(#savedNames + 1) end
        
        -- Avoid duplicates
        local count = 0
        for _, n in ipairs(savedNames) do if n == name then count = count + 1 end end
        if count > 0 then name = name .. "_" .. tostring(count) end

        savedWaypoints[name] = root.CFrame
        table.insert(savedNames, name)
        WaypointDropdown:SetValues(savedNames)
        Library:Notify("Saved: " .. name, 2)
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
        
        -- [UPGRADE] Free Camera
        local FreeCamToggle = AddLockedToggle(CamBox, "bxw_freecam", { Text = "Free Camera", Default = false, Role = "user", Tooltip = "Detach camera from character (WASD/QE)" })
        local FreeCamSpeed = CamBox:AddSlider("bxw_freecam_speed", { Text = "FreeCam Speed", Default = 2, Min = 0.1, Max = 10, Rounding = 1 })
        
        local fcState = {
            active = false,
            cf = CFrame.new(),
            moving = false,
            input = Vector3.zero
        }
        
        FreeCamToggle:OnChanged(function(state)
            fcState.active = state
            local cam = workspace.CurrentCamera
            if state then
                fcState.cf = cam.CFrame
                cam.CameraType = Enum.CameraType.Scriptable
                
                -- Bind inputs
                RunService:BindToRenderStep("BxB_FreeCam", Enum.RenderPriority.Camera.Value + 1, function(dt)
                    if not fcState.active then return end
                    
                    local speed = FreeCamSpeed.Value * 60 * dt
                    local moveVector = Vector3.new()
                    
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + Vector3.new(0, 0, -1) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector + Vector3.new(0, 0, 1) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector + Vector3.new(-1, 0, 0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + Vector3.new(1, 0, 0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveVector = moveVector + Vector3.new(0, -1, 0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveVector = moveVector + Vector3.new(0, 1, 0) end
                    
                    -- Mobile input simulation (Two finger drag for move? Complex to implement fully, stick to basic)
                    
                    fcState.cf = fcState.cf * CFrame.new(moveVector * speed)
                    cam.CFrame = fcState.cf
                end)
            else
                RunService:UnbindFromRenderStep("BxB_FreeCam")
                cam.CameraType = Enum.CameraType.Custom
                if LocalPlayer.Character then
                    cam.CameraSubject = LocalPlayer.Character:FindFirstChild("Humanoid")
                end
            end
        end)


        -- [FIXED] Skybox Logic
        local SkyboxThemes = { ["Default"] = "", ["Space"] = "rbxassetid://11755937810", ["Sunset"] = "rbxassetid://9393701400", ["Midnight"] = "rbxassetid://11755930464" }
        local SkyboxDropdown = CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default", Multi = false, Tooltip = "Change sky texture" })
        local originalSkyCam = nil
        
        -- Save original sky
        pcall(function() originalSkyCam = game.Lighting:FindFirstChildOfClass("Sky") if originalSkyCam then originalSkyCam = originalSkyCam:Clone() end end)

        local function applySkyCam(name)
            local lighting = game:GetService("Lighting")
            
            -- Clear existing custom or default skies to ensure new one shows
            for _, v in pairs(lighting:GetChildren()) do
                if v:IsA("Sky") then v:Destroy() end
            end

            if name == "Default" then
                 if originalSkyCam then 
                     originalSkyCam:Clone().Parent = lighting 
                 end
            else
                local id = SkyboxThemes[name]
                if id and id ~= "" then 
                    local sky = Instance.new("Sky") 
                    sky.SkyboxBk = id sky.SkyboxDn = id sky.SkyboxFt = id 
                    sky.SkyboxLf = id sky.SkyboxRt = id sky.SkyboxUp = id 
                    sky.Parent = lighting 
                end
            end
        end
        SkyboxDropdown:OnChanged(function(value) applySkyCam(value) end)
    end

    ------------------------------------------------
    -- 4.3 ESP & Visuals Tab
    ------------------------------------------------
    do
        local ESPTab = Tabs.ESP
        local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
        local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")
        
        -- [UPGRADE] Radar & Extras Groupbox
        local ExtraVisualBox = safeAddRightGroupbox(ESPTab, "Radar", "radar")

        local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP", Default = false, Tooltip = "Master switch for ESP" })
        
        local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box", Multi = false })
        
        local BoxToggle = ESPFeatureBox:AddToggle("bxw_esp_box", { Text = "Box", Default = true })
            :AddColorPicker("bxw_esp_box_color", { Default = Color3.fromRGB(255, 255, 255), Title = "Box Color" })
        
        local ChamsToggle = ESPFeatureBox:AddToggle("bxw_esp_chams", { Text = FormatFeatureName("Chams", "Highlight"), Default = false, Tooltip = "Highlight Character" })
            :AddColorPicker("bxw_esp_chams_color", { Default = Color3.fromRGB(0, 255, 0), Title = "Chams Color" })

        local SkeletonToggle = ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = FormatFeatureName("Skeleton", "Drawing"), Default = false })
            :AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.fromRGB(0, 255, 255), Title = "Skeleton Color" })

        local HealthToggle = ESPFeatureBox:AddToggle("bxw_esp_health", { Text = "Health Bar", Default = false })
            :AddColorPicker("bxw_esp_health_color", { Default = Color3.fromRGB(0, 255, 0), Title = "Health Bar Color" })

        local NameToggle = ESPFeatureBox:AddToggle("bxw_esp_name", { Text = "Name Tag", Default = true })
            :AddColorPicker("bxw_esp_name_color", { Default = Color3.fromRGB(255, 255, 255), Title = "Name Color" })

        local DistToggle = ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance", Default = false })
            :AddColorPicker("bxw_esp_dist_color", { Default = Color3.fromRGB(255, 255, 255), Title = "Distance Color" })

        local TracerToggle = ESPFeatureBox:AddToggle("bxw_esp_tracer", { Text = "Tracer", Default = false })
            :AddColorPicker("bxw_esp_tracer_color", { Default = Color3.fromRGB(255, 255, 255), Title = "Tracer Color" })

        local TeamToggle = ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true })
        local WallToggle = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false, Tooltip = "Colors red if not visible" })

        local SelfToggle = ESPFeatureBox:AddToggle("bxw_esp_self", { Text = "Self ESP", Default = false })
        
        local InfoToggle = ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info", Default = false, Tooltip = "Shows HP, Weapon & Team" })
            :AddColorPicker("bxw_esp_info_color", { Default = Color3.fromRGB(255, 255, 255), Title = "Info Color" })
        
        local HeadDotToggle = ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false })
            :AddColorPicker("bxw_esp_headdot_color", { Default = Color3.fromRGB(255, 0, 0), Title = "Head Dot Color" })
        
        local ArrowToggle = ESPFeatureBox:AddToggle("bxw_esp_arrow", { Text = "Off-Screen Arrow", Default = false })
            :AddColorPicker("bxw_esp_arrow_color", { Default = Color3.fromRGB(255, 100, 0), Title = "Arrow Color" })

        local TargetIndToggle = ESPFeatureBox:AddToggle("bxw_esp_targetind", { Text = "Look/Aim Indicator", Default = false, Tooltip = "Warns when enemy looks at you" })
        
        local ViewDirToggle = ESPFeatureBox:AddToggle("bxw_esp_viewdir", { Text = "View Direction", Default = false, Tooltip = "Line showing where enemy is looking" })
             :AddColorPicker("bxw_esp_viewdir_color", { Default = Color3.fromRGB(255, 255, 0), Title = "View Dir Color" })

        ESPEnabledToggle:OnChanged(function(state) 
            NotifyAction("Global ESP", state) 
        end)
        
        -- [FIXED] Radar Settings (Visuals)
        local RadarToggle = ExtraVisualBox:AddToggle("bxw_radar_enable", { Text = "Enable 2D Radar", Default = false })
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

        local function getPlayerNames()
            local names = {}
            for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then table.insert(names, plr.Name) end end
            table.sort(names)
            return names
        end
        local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = getPlayerNames(), Default = "", Multi = true, AllowNull = true, Tooltip = "Ignore these players" })
        do
            local function refreshWhitelist() local names = getPlayerNames() WhitelistDropdown:SetValues(names) end
            refreshWhitelist()
            AddConnection(Players.PlayerAdded:Connect(refreshWhitelist))
            AddConnection(Players.PlayerRemoving:Connect(refreshWhitelist))
            task.spawn(function() while true do task.wait(10) refreshWhitelist() end end)
        end
        
        -- [FIXED] Re-added ESP Refresh Rate Slider
        local ESPRefreshSlider = ESPSettingBox:AddSlider("bxw_esp_refresh", { Text = "Refresh Rate (ms)", Default = 0, Min = 0, Max = 100, Rounding = 0, Tooltip = "0 = Max FPS" })

        local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local DistSizeSlider = ESPSettingBox:AddSlider("bxw_esp_dist_size", { Text = "Distance Size", Default = 14, Min = 10, Max = 30, Rounding = 0 })
        local DistUnitDropdown = ESPSettingBox:AddDropdown("bxw_esp_dist_unit", { Text = "Distance Unit", Values = { "Studs", "Meters" }, Default = "Studs", Multi = false })
        local HeadDotSizeSlider = ESPSettingBox:AddSlider("bxw_esp_headdot_size", { Text = "Head Dot Size", Default = 3, Min = 1, Max = 10, Rounding = 0 })
        local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2, Compact = false })
        local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Visible Only", Default = false })
        
        local DistColorToggle = ESPSettingBox:AddToggle("bxw_esp_distcolor", { Text = "Color by Distance", Default = false, Tooltip = "Red=Close, Green=Far" })
        
        local CrosshairToggle = ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
            :AddColorPicker("bxw_crosshair_color", { Default = Color3.fromRGB(255, 255, 255), Title = "Crosshair Color" })

        local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20, Rounding = 0, Compact = false })
        local CrossThickSlider = ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Crosshair Thickness", Default = 1, Min = 1, Max = 5, Rounding = 0 })
        
        CrosshairToggle:OnChanged(function(state) 
            NotifyAction("Crosshair", state) 
        end)

        local function removePlayerESP(plr)
            if espDrawings[plr] then
                local data = espDrawings[plr]
                if data.Box then pcall(function() data.Box:Remove() end) data.Box = nil end
                if data.Corners then for _, ln in pairs(data.Corners) do pcall(function() ln:Remove() end) end data.Corners = nil end
                if data.Health then 
                    if data.Health.Outline then pcall(function() data.Health.Outline:Remove() end) end 
                    if data.Health.Bar then pcall(function() data.Health.Bar:Remove() end) end 
                    data.Health = nil
                end
                if data.Name then pcall(function() data.Name:Remove() end) data.Name = nil end
                if data.Distance then pcall(function() data.Distance:Remove() end) data.Distance = nil end
                if data.Tracer then pcall(function() data.Tracer:Remove() end) data.Tracer = nil end
                if data.Highlight then pcall(function() data.Highlight:Destroy() end) data.Highlight = nil end
                if data.Skeleton then for _, ln in pairs(data.Skeleton) do pcall(function() ln:Remove() end) end data.Skeleton = nil end
                if data.HeadDot then pcall(function() data.HeadDot:Remove() end) data.HeadDot = nil end
                if data.Info then pcall(function() data.Info:Remove() end) data.Info = nil end
                if data.Arrow then pcall(function() data.Arrow:Remove() end) data.Arrow = nil end
                if data.ViewDir then pcall(function() data.ViewDir:Remove() end) data.ViewDir = nil end
                espDrawings[plr] = nil
            end
        end

        AddConnection(Players.PlayerRemoving:Connect(function(plr) removePlayerESP(plr) end))

        -- [FIXED] Skeleton Joints R15/R6
        local skeletonJointsR15 = {
            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"LowerTorso", "HumanoidRootPart"},
            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
        }
        
        local skeletonJointsR6 = {
            {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
            {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
        }

        local function IsTeammate(plr)
            if not TeamToggle.Value then return false end
            if not plr then return false end
            if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then return true end
            if LocalPlayer.TeamColor and plr.TeamColor and LocalPlayer.TeamColor == plr.TeamColor then return true end
            return false
        end

        -- [FIXED] Optimized ESP Loop for Smoothness & Refresh Rate
        local lastESPUpdate = 0
        local function updateESP()
            local rate = ESPRefreshSlider.Value
            if rate > 0 and (tick() - lastESPUpdate) < (rate / 1000) then return end
            lastESPUpdate = tick()

            if not ESPEnabledToggle.Value then
                for plr, _ in pairs(espDrawings) do removePlayerESP(plr) end
                return
            end
            
            -- Radar Background
            if RadarToggle.Value then
                 local rSize = RadarSizeSlider.Value
                 local rX = workspace.CurrentCamera.ViewportSize.X - rSize - 20
                 local rY = workspace.CurrentCamera.ViewportSize.Y - rSize - 20
                 
                 if not radarDrawings.bg then
                     radarDrawings.bg = Drawing.new("Square")
                     radarDrawings.bg.Filled = true
                     radarDrawings.bg.Transparency = 0.6
                     radarDrawings.bg.Color = Color3.new(0.1, 0.1, 0.1)
                     radarDrawings.bg.Visible = true
                 end
                 radarDrawings.bg.Size = Vector2.new(rSize, rSize)
                 radarDrawings.bg.Position = Vector2.new(rX, rY)

                 if not radarDrawings.outline then
                     radarDrawings.outline = Drawing.new("Square")
                     radarDrawings.outline.Visible = true
                     radarDrawings.outline.Filled = false
                     radarDrawings.outline.Transparency = 1
                     radarDrawings.outline.Color = Color3.new(1,1,1)
                     radarDrawings.outline.Thickness = 2
                 end
                 radarDrawings.outline.Size = Vector2.new(rSize, rSize)
                 radarDrawings.outline.Position = Vector2.new(rX, rY)
                 
                 if not radarDrawings.line then
                     radarDrawings.line = Drawing.new("Line")
                     radarDrawings.line.Color = Color3.new(1,1,1)
                     radarDrawings.line.Thickness = 1
                     radarDrawings.line.Visible = true
                 end
                 radarDrawings.line.From = Vector2.new(rX + rSize/2, rY + rSize/2)
                 radarDrawings.line.To = Vector2.new(rX + rSize/2, rY)
            else
                if radarDrawings.bg then radarDrawings.bg.Visible = false end
            end

            local cam = Workspace.CurrentCamera
            if not cam then return end
            local camPos = cam.CFrame.Position

            for _, plr in ipairs(Players:GetPlayers()) do
                -- Ghost/Leave Check
                if not plr or not plr.Parent then
                     removePlayerESP(plr)
                     if radarDrawings.points[plr] then radarDrawings.points[plr]:Remove() radarDrawings.points[plr] = nil end
                     continue
                end

                if plr == LocalPlayer and RadarToggle.Value and SelfToggle.Value then
                     local rSize = RadarSizeSlider.Value
                     local rX = workspace.CurrentCamera.ViewportSize.X - rSize - 20
                     local rY = workspace.CurrentCamera.ViewportSize.Y - rSize - 20
                     local center = Vector2.new(rX + rSize/2, rY + rSize/2)
                     
                     if not radarDrawings.points[plr] then
                         local d = Drawing.new("Circle")
                         d.Filled = true
                         d.Radius = 3
                         d.Color = Color3.new(0, 1, 0)
                         radarDrawings.points[plr] = d
                     end
                     radarDrawings.points[plr].Visible = true
                     radarDrawings.points[plr].Position = center
                end

                if plr ~= LocalPlayer or (SelfToggle and SelfToggle.Value) then
                    local char = plr.Character
                    if not char or not char.Parent then
                         removePlayerESP(plr)
                         if plr ~= LocalPlayer and radarDrawings.points[plr] then radarDrawings.points[plr].Visible = false end
                         continue
                    end

                    local hum  = char:FindFirstChildOfClass("Humanoid")
                    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                    
                    if not hum or hum.Health <= 0 or not root then
                        removePlayerESP(plr)
                        if plr ~= LocalPlayer and radarDrawings.points[plr] then radarDrawings.points[plr].Visible = false end
                    else
                        local skipPlayer = false
                        if plr ~= LocalPlayer and IsTeammate(plr) then skipPlayer = true end

                        if not skipPlayer then
                            local list = WhitelistDropdown.Value
                            if list and type(list) == "table" then
                                for _, name in ipairs(list) do if name == plr.Name then skipPlayer = true break end end
                            end
                        end

                        if skipPlayer then
                            removePlayerESP(plr)
                            if plr ~= LocalPlayer and radarDrawings.points[plr] then radarDrawings.points[plr].Visible = false end
                        else
                            local data = espDrawings[plr]
                            if not data then data = {} espDrawings[plr] = data end
                            
                            -- Radar Dot
                            if RadarToggle.Value and plr ~= LocalPlayer then
                                local rRange = RadarRangeSlider.Value
                                local rSize = RadarSizeSlider.Value
                                local rX = workspace.CurrentCamera.ViewportSize.X - rSize - 20
                                local rY = workspace.CurrentCamera.ViewportSize.Y - rSize - 20
                                local rCenter = Vector2.new(rX + rSize/2, rY + rSize/2)
                                
                                local relPos = root.Position - (getRootPart() and getRootPart().Position or Vector3.zero)
                                local angle = math.atan2(relPos.Z, relPos.X) - math.atan2(cam.CFrame.LookVector.Z, cam.CFrame.LookVector.X)
                                local dist = relPos.Magnitude
                                local distScale = math.clamp(dist, 0, rRange) / rRange
                                
                                local dotX = rCenter.X + math.cos(angle + math.pi/2) * (distScale * rSize/2)
                                local dotY = rCenter.Y + math.sin(angle + math.pi/2) * (distScale * rSize/2)
                                
                                if not radarDrawings.points[plr] then
                                    local d = Drawing.new("Circle")
                                    d.Filled = true
                                    d.Radius = 3
                                    d.Color = Color3.new(1,0,0)
                                    radarDrawings.points[plr] = d
                                end
                                radarDrawings.points[plr].Visible = true
                                radarDrawings.points[plr].Position = Vector2.new(dotX, dotY)
                            end

                            local boxCFrame = root.CFrame
                            local cornersWorld = {
                                boxCFrame * CFrame.new(-2, 3, 0),
                                boxCFrame * CFrame.new(2, 3, 0),
                                boxCFrame * CFrame.new(-2, -3, 0),
                                boxCFrame * CFrame.new(2, -3, 0),
                            }
                            
                            local isVisible = true
                            if WallToggle.Value then
                                local rayDir = (root.Position - camPos)
                                local rayParams = RaycastParams.new()
                                rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                rayParams.IgnoreWater = true
                                local rayResult = Workspace:Raycast(camPos, rayDir, rayParams)
                                if rayResult then isVisible = false end
                            end

                            local function getVisColor(optionColor)
                                if WallToggle.Value and not isVisible then return Color3.fromRGB(255, 0, 0) end
                                if DistColorToggle.Value then
                                    local dist = (root.Position - camPos).Magnitude
                                    local t = math.clamp(dist / 300, 0, 1)
                                    return Color3.fromHSV(t * 0.33, 1, 1) 
                                end
                                return optionColor or Color3.fromRGB(255, 255, 255)
                            end

                            -- [FIXED] Chams Logic: Handle Limit 31 Highlights
                            if ChamsToggle.Value and IsFeatureSupported("Highlight") then
                                local baseColor = (Options.bxw_esp_chams_color and Options.bxw_esp_chams_color.Value) or Color3.fromRGB(0, 255, 0)
                                local finalChamColor = getVisColor(baseColor)
                                local chamsTrans = ChamsTransSlider and ChamsTransSlider.Value or 0.5
                                local visibleOnly = ChamsVisibleToggle and ChamsVisibleToggle.Value or false
                                
                                if not data.Highlight then
                                    local hl = Instance.new("Highlight")
                                    hl.Parent = CoreGui -- Try parent to CoreGui for better persistence
                                    if not hl.Parent then hl.Parent = char end -- Fallback
                                    data.Highlight = hl
                                end
                                local hl = data.Highlight
                                hl.Adornee = char -- Ensure Adornee is set every frame to prevent ghosting
                                hl.Enabled = true
                                hl.DepthMode = visibleOnly and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                                hl.FillColor = finalChamColor
                                hl.OutlineColor = finalChamColor
                                hl.FillTransparency = chamsTrans
                            else
                                if data.Highlight then data.Highlight.Enabled = false end
                            end

                            local minX, minY = math.huge, math.huge
                            local maxX, maxY = -math.huge, -math.huge
                            local onScreen = false

                            for i, worldPos in ipairs(cornersWorld) do
                                local screenPos, vis = cam:WorldToViewportPoint(worldPos.Position)
                                if vis then onScreen = true end
                                minX = math.min(minX, screenPos.X)
                                minY = math.min(minY, screenPos.Y)
                                maxX = math.max(maxX, screenPos.X)
                                maxY = math.max(maxY, screenPos.Y)
                            end
                            
                            -- Off Screen Arrow
                            if not onScreen and ArrowToggle.Value then
                                if not data.Arrow then data.Arrow = Drawing.new("Triangle") data.Arrow.Filled = true end
                                local relative = cam.CFrame:PointToObjectSpace(root.Position)
                                local angle = math.atan2(relative.Y, relative.X)
                                local dist = 300 
                                local center = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                                local pos = center + Vector2.new(math.cos(angle)*dist, math.sin(angle)*dist)
                                local size = 15
                                data.Arrow.Visible = true
                                data.Arrow.PointA = pos + Vector2.new(math.cos(angle)*size, math.sin(angle)*size)
                                data.Arrow.PointB = pos + Vector2.new(math.cos(angle + 2)*size, math.sin(angle + 2)*size)
                                data.Arrow.PointC = pos + Vector2.new(math.cos(angle - 2)*size, math.sin(angle - 2)*size)
                                data.Arrow.Color = (Options.bxw_esp_arrow_color and Options.bxw_esp_arrow_color.Value) or Color3.new(1,0.5,0)
                            else
                                if data.Arrow then data.Arrow.Visible = false end
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
                                if data.ViewDir then data.ViewDir.Visible = false end
                                if data.Skeleton then for _, ln in pairs(data.Skeleton) do ln.Visible = false end end
                            else
                                local boxW, boxH = maxX - minX, maxY - minY
                                
                                -- [FIXED] Box Style Visibility
                                if BoxToggle.Value then
                                    local baseBoxCol = (Options.bxw_esp_box_color and Options.bxw_esp_box_color.Value)
                                    local finalBoxCol = getVisColor(baseBoxCol)

                                    if BoxStyleDropdown.Value == "Box" then
                                        if not data.Box then 
                                            local sq = Drawing.new("Square") 
                                            sq.Thickness = 1 
                                            sq.Filled = false 
                                            data.Box = sq 
                                        end
                                        data.Box.Visible = true
                                        data.Box.Transparency = 1 -- Usually 1 is visible for Outline
                                        data.Box.Color = finalBoxCol
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
                                    local baseHpCol = (Options.bxw_esp_health_color and Options.bxw_esp_health_color.Value)
                                    if not data.Health then 
                                        data.Health = { Outline = Drawing.new("Line"), Bar = Drawing.new("Line") } 
                                        data.Health.Outline.Thickness = 3 
                                        data.Health.Bar.Thickness = 1 
                                        data.Health.Bar.ZIndex = 2
                                        data.Health.Outline.ZIndex = 1
                                    end
                                    local hbX = minX - 6
                                    local hp = math.clamp(hum.Health, 0, hum.MaxHealth)
                                    local maxHp = math.max(hum.MaxHealth, 1)
                                    local barY2 = minY + (maxY - minY) * (1 - (hp / maxHp))
                                    data.Health.Outline.Visible = true 
                                    data.Health.Outline.Color = Color3.new(0,0,0) 
                                    data.Health.Outline.From = Vector2.new(hbX, minY) 
                                    data.Health.Outline.To = Vector2.new(hbX, maxY)
                                    data.Health.Bar.Visible = true 
                                    data.Health.Bar.Color = baseHpCol or Color3.fromRGB(0, 255, 0)
                                    data.Health.Bar.From = Vector2.new(hbX, maxY)
                                    data.Health.Bar.To = Vector2.new(hbX, barY2)
                                else
                                    if data.Health then data.Health.Outline.Visible = false data.Health.Bar.Visible = false end
                                end

                                if NameToggle.Value then
                                    local baseNameCol = (Options.bxw_esp_name_color and Options.bxw_esp_name_color.Value)
                                    if not data.Name then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Name = txt end
                                    data.Name.Visible = true
                                    data.Name.Color = getVisColor(baseNameCol)
                                    data.Name.Size = NameSizeSlider.Value
                                    data.Name.Text = plr.DisplayName or plr.Name
                                    data.Name.Position = Vector2.new((minX + maxX) / 2, minY - 14)
                                else
                                    if data.Name then data.Name.Visible = false end
                                end

                                if DistToggle.Value then
                                    local baseDistCol = (Options.bxw_esp_dist_color and Options.bxw_esp_dist_color.Value)
                                    if not data.Distance then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Distance = txt end
                                    local distStud = (root.Position - camPos).Magnitude
                                    local unit = DistUnitDropdown and DistUnitDropdown.Value or "Studs"
                                    local distNum = distStud
                                    local suffix = " studs"
                                    if unit == "Meters" then distNum = distStud * 0.28 suffix = " m" end
                                    data.Distance.Visible = true
                                    data.Distance.Color = getVisColor(baseDistCol)
                                    data.Distance.Size = DistSizeSlider.Value
                                    data.Distance.Text = string.format("%.1f", distNum) .. suffix
                                    data.Distance.Position = Vector2.new((minX + maxX) / 2, maxY + 2)
                                else
                                    if data.Distance then data.Distance.Visible = false end
                                end
                                
                                -- [FIXED] Info (Weapons/Team)
                                if InfoToggle.Value then
                                    local baseInfoCol = (Options.bxw_esp_info_color and Options.bxw_esp_info_color.Value) or Color3.fromRGB(255,255,255)
                                    if not data.Info then local txt = Drawing.new("Text") txt.Center = true txt.Outline = true data.Info = txt end
                                    local tool = char:FindFirstChildOfClass("Tool")
                                    local item = tool and tool.Name or "None"
                                    local infoTxt = item
                                    data.Info.Visible = true
                                    data.Info.Color = baseInfoCol
                                    data.Info.Size = 13
                                    data.Info.Text = infoTxt
                                    data.Info.Position = Vector2.new((minX + maxX) / 2, maxY + 15)
                                else
                                    if data.Info then data.Info.Visible = false end
                                end

                                -- [FIXED] Skeleton Logic
                                if SkeletonToggle.Value and IsFeatureSupported("Drawing") then
                                    local color = (Options.bxw_esp_skeleton_color and Options.bxw_esp_skeleton_color.Value) or Color3.fromRGB(255,255,255)
                                    local joints = (hum.RigType == Enum.HumanoidRigType.R15) and skeletonJointsR15 or skeletonJointsR6
                                    
                                    if not data.Skeleton then data.Skeleton = {} end
                                    -- Ensure lines exist
                                    for idx, _ in ipairs(joints) do
                                        if not data.Skeleton[idx] then
                                            local line = Drawing.new("Line")
                                            line.Thickness = 1
                                            line.Transparency = 1
                                            data.Skeleton[idx] = line
                                        end
                                    end
                                    
                                    for idx, joint in ipairs(joints) do
                                        local line = data.Skeleton[idx]
                                        local p1 = char:FindFirstChild(joint[1])
                                        local p2 = char:FindFirstChild(joint[2])
                                        
                                        if p1 and p2 then
                                            local v1, vis1 = cam:WorldToViewportPoint(p1.Position)
                                            local v2, vis2 = cam:WorldToViewportPoint(p2.Position)
                                            
                                            if vis1 and vis2 then
                                                line.Visible = true
                                                line.Color = color
                                                line.From = Vector2.new(v1.X, v1.Y)
                                                line.To = Vector2.new(v2.X, v2.Y)
                                            else
                                                line.Visible = false
                                            end
                                        else
                                            line.Visible = false
                                        end
                                    end
                                else
                                    if data.Skeleton then for _, ln in pairs(data.Skeleton) do ln.Visible = false end end
                                end
                                
                                -- [FIXED] View Direction
                                if ViewDirToggle.Value and IsFeatureSupported("Drawing") then
                                    if not data.ViewDir then data.ViewDir = Drawing.new("Line") data.ViewDir.Thickness = 1 end
                                    local head = char:FindFirstChild("Head")
                                    if head then
                                        local fromPos, vis1 = cam:WorldToViewportPoint(head.Position)
                                        local dir = head.CFrame.LookVector * 5
                                        local toPos, vis2 = cam:WorldToViewportPoint(head.Position + dir)
                                        if vis1 and vis2 then
                                            data.ViewDir.Visible = true
                                            data.ViewDir.Color = (Options.bxw_esp_viewdir_color and Options.bxw_esp_viewdir_color.Value) or Color3.fromRGB(255,255,0)
                                            data.ViewDir.From = Vector2.new(fromPos.X, fromPos.Y)
                                            data.ViewDir.To = Vector2.new(toPos.X, toPos.Y)
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

        -- [OPTIMIZED] Use RenderStepped without interval check for smoothest movement
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
    -- 4.4 Combat & Aimbot Tab (OPTIMIZED BY DIABLO)
    ------------------------------------------------
    do
        local CombatTab = Tabs.Combat
        local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
        local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

        AimBox:AddLabel("Core Settings")
        -- [LOCKED: Premium] Aimbot
        local AimbotToggle = AddLockedToggle(AimBox, "bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false, Role = "premium", Tooltip = "Main Aim Assist Switch" })
        local SilentToggle = AddLockedToggle(AimBox, "bxw_silent_enable", { Text = "Silent Aim", Default = false, Role = "vip", Tooltip = "Shoot without moving camera" })

        AimBox:AddLabel("Aim & Target Settings")
        local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest", "Random", "Custom" }, Default = "Head", Multi = false })
        
        -- Smart Aim Logic Toggle
        local UseSmartAimLogic = AimBox:AddToggle("bxw_aim_smart_logic", { Text = "Smart Aim Logic", Default = true, Tooltip = "Auto-calculate best target based on Distance, HP and Mouse Proximity" })

        AimBox:AddLabel("FOV Settings")
        local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50, Rounding = 1 })
        local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
        -- Deadzone
        local DeadzoneSlider = AimBox:AddSlider("bxw_aim_deadzone", { Text = "Deadzone (Pixels)", Default = 0, Min = 0, Max = 50, Rounding = 1, Tooltip = "Aimbot won't snap if mouse is close enough" })
        
        -- [UPDATED] Smoothness 0-5
        local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Aimbot Smoothness", Default = 0.5, Min = 0, Max = 5, Rounding = 2, Tooltip = "Lower = Faster snap" })
        local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
        
        local TriggerbotToggle = AimBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false, Tooltip = "Auto shoot when aiming at enemy" })
        
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
        
        -- [FIXED] Prediction Logic
        local PredToggle = AimBox:AddToggle("bxw_aim_pred", { Text = "Prediction Aim", Default = false, Tooltip = "Compensate for enemy movement" })
        local PredSlider = AimBox:AddSlider("bxw_aim_predfactor", { Text = "Prediction Factor", Default = 0.1, Min = 0, Max = 1, Rounding = 2 })
        
        -- RCS & Strafe
        local RCSToggle = AimBox:AddToggle("bxw_aim_rcs", { Text = "Recoil Control (RCS)", Default = false })
        local RCSStrength = AimBox:AddSlider("bxw_rcs_strength", { Text = "RCS Strength", Default = 5, Min = 1, Max = 20, Rounding = 0 })
        local StrafeToggle = AimBox:AddToggle("bxw_aim_strafe", { Text = "Target Strafe (Orbit)", Default = false, Tooltip = "Circle around target" })

        AimbotToggle:OnChanged(function(state)
            NotifyAction("Aimbot", state)
        end)

        local TriggerTeamToggle = ExtraBox:AddToggle("bxw_trigger_teamcheck", { Text = "Trigger Team Check", Default = true })
        local TriggerWallToggle = ExtraBox:AddToggle("bxw_trigger_wallcheck", { Text = "Trigger Wall Check", Default = false })
        local TriggerMethodDropdown = ExtraBox:AddDropdown("bxw_trigger_method", { Text = "Trigger Method", Values = { "Always On", "Hold Key" }, Default = "Always On", Multi = false })
        local TriggerFiringDropdown = ExtraBox:AddDropdown("bxw_trigger_firemode", { Text = "Firing Mode", Values = { "Single", "Burst", "Auto" }, Default = "Single", Multi = false })
        local TriggerDelaySlider = ExtraBox:AddSlider("bxw_trigger_delay", { Text = "Trigger Delay (s)", Default = 0.05, Min = 0, Max = 1, Rounding = 2 })
        
        TriggerbotToggle:OnChanged(function(state)
            NotifyAction("Triggerbot", state)
        end)

        -- Hitbox Expander [LOCKED: User+]
        ExtraBox:AddDivider()
        ExtraBox:AddLabel("Hitbox Expander")
        local HitboxSizeSlider = ExtraBox:AddSlider("bxw_hitbox_size", { Text = "Expand Size", Default = 0, Min = 0, Max = 10, Rounding = 1 })
        local HitboxTransSlider = ExtraBox:AddSlider("bxw_hitbox_trans", { Text = "Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 1 })
        local HitboxToggle = AddLockedToggle(ExtraBox, "bxw_hitbox_enable", { Text = "Enable Expander", Default = false, Role = "user", Tooltip = "Makes hitboxes bigger" })
        
        task.spawn(function()
            while true do
                task.wait(1)
                if HitboxToggle.Value then
                    local size = HitboxSizeSlider.Value
                    local trans = HitboxTransSlider.Value
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("Head") then
                             local isTeam = false
                             if AimTeamCheck.Value and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then isTeam = true end
                             if not isTeam then
                                 local head = plr.Character.Head
                                 if head then
                                     head.Size = Vector3.new(2 + size, 1 + size, 1 + size) 
                                     head.Transparency = trans
                                     head.CanCollide = false
                                 end
                             end
                        end
                    end
                end
            end
        end)

        AimbotFOVCircle = Drawing.new("Circle") AimbotFOVCircle.Transparency = 0.5 AimbotFOVCircle.Filled = false AimbotFOVCircle.Thickness = 1 AimbotFOVCircle.Color = Color3.fromRGB(255, 255, 255)
        AimbotSnapLine = Drawing.new("Line") AimbotSnapLine.Transparency = 0.7 AimbotSnapLine.Visible = false
        local rainbowHue = 0

        local function performClick() pcall(function() mouse1click() end) pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(Vector2.new()) end) end

        -- [OPTIMIZATION] Shared Target Variable
        local CurrentAimbotTarget = nil -- { player, part, root, char, hum, screenPos }

        -- [OPTIMIZATION] Target Selector Loop (Runs slower than RenderStepped)
        task.spawn(function()
            while true do
                task.wait(0.05) -- Run 20 times per second instead of 60-144
                
                if Toggles.bxw_aimbot_enable and Toggles.bxw_aimbot_enable.Value then
                    local cam = Workspace.CurrentCamera
                    local mouseLoc = UserInputService:GetMouseLocation()
                    local myRoot = getRootPart()
                    local bestPlr = nil
                    local bestScore = math.huge

                    if myRoot and cam then
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer then
                                local char = plr.Character
                                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    local rootCandidate = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                                    if rootCandidate then
                                        -- Team Check
                                        local skip = false
                                        if Toggles.bxw_aim_teamcheck and Toggles.bxw_aim_teamcheck.Value then
                                            if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then skip = true end
                                            if LocalPlayer.TeamColor and plr.TeamColor and LocalPlayer.TeamColor == plr.TeamColor then skip = true end
                                        end

                                        if not skip then
                                            local aimPartName = (Options.bxw_aim_part and Options.bxw_aim_part.Value) or "Head"
                                            local selectedPart = nil
                                            if aimPartName == "Head" then selectedPart = char:FindFirstChild("Head")
                                            elseif aimPartName == "UpperTorso" then selectedPart = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
                                            elseif aimPartName == "Torso" then selectedPart = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                                            elseif aimPartName == "HumanoidRootPart" then selectedPart = rootCandidate
                                            elseif aimPartName == "Closest" then
                                                local closestDist = math.huge
                                                for _, pName in ipairs({"Head", "UpperTorso", "Torso", "HumanoidRootPart"}) do
                                                    local p = char:FindFirstChild(pName)
                                                    if p then
                                                        local sp, onScreen = cam:WorldToViewportPoint(p.Position)
                                                        if onScreen then
                                                            local dist = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                                                            if dist < closestDist then closestDist = dist selectedPart = p end
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
                                                        -- Visibility Check
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
                                                            if UseSmartAimLogic.Value then
                                                                local distSelf = (rootCandidate.Position - myRoot.Position).Magnitude
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
                    CurrentAimbotTarget = bestPlr
                else
                    CurrentAimbotTarget = nil
                end
            end
        end)

        -- Triggerbot Logic (Independent Loop)
        task.spawn(function()
            local lastTrigger = 0
            while true do
                task.wait()
                if TriggerbotToggle.Value then
                    local delayTime = (Options.bxw_trigger_delay and Options.bxw_trigger_delay.Value) or 0
                    if tick() - lastTrigger > delayTime then
                        local cam = Workspace.CurrentCamera
                        if cam then
                            local rayParams = RaycastParams.new()
                            rayParams.FilterDescendantsInstances = { LocalPlayer.Character, cam }
                            rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                            
                            local rayOrigin = cam.CFrame.Position
                            local rayDirection = cam.CFrame.LookVector * 1000
                            local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
                            
                            if rayResult and rayResult.Instance then
                                local hitModel = rayResult.Instance:FindFirstAncestorOfClass("Model")
                                if hitModel then
                                    local hitPlr = Players:GetPlayerFromCharacter(hitModel)
                                    if hitPlr and hitPlr ~= LocalPlayer then
                                        local isEnemy = true
                                        if TriggerTeamToggle.Value then
                                            if LocalPlayer.Team and hitPlr.Team and LocalPlayer.Team == hitPlr.Team then isEnemy = false end
                                            if LocalPlayer.TeamColor and hitPlr.TeamColor and LocalPlayer.TeamColor == hitPlr.TeamColor then isEnemy = false end
                                        end

                                        local hum = hitModel:FindFirstChildOfClass("Humanoid")
                                        if hum and hum.Health > 0 and isEnemy then
                                            lastTrigger = tick()
                                            local fireMode = (Options.bxw_trigger_firemode and Options.bxw_trigger_firemode.Value) or "Single"
                                            if fireMode == "Single" then performClick()
                                            elseif fireMode == "Burst" then for i=1, 3 do performClick() task.wait(0.05) end
                                            elseif fireMode == "Auto" then performClick() end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        
        local strafeAngle = 0

        -- [OPTIMIZED] RenderStepped Loop - Handles only Visuals & Camera Movement
        AddConnection(RunService.RenderStepped:Connect(function(dt)
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local mouseLoc = UserInputService:GetMouseLocation()

            -- Draw FOV Circle
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

            -- Aimbot Movement
            if Toggles.bxw_aimbot_enable and Toggles.bxw_aimbot_enable.Value and CurrentAimbotTarget then
                local activation = (Options.bxw_aim_activation and Options.bxw_aim_activation.Value) or "Hold Right Click"
                local isActive = false
                
                if activation == "Always On" then
                    isActive = true
                elseif activation == "Hold Right Click" then
                    if isMobile then
                        isActive = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or UserInputService:IsMouseButtonPressed(Enum.UserInputType.Touch)
                    else
                        isActive = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                    end
                end
                
                if isActive then
                    local bestPlr = CurrentAimbotTarget
                    local aimPart = bestPlr.part

                    -- Smart BodyAim Override Check (Real-time)
                    if Toggles.bxw_aim_smart and Toggles.bxw_aim_smart.Value then
                        local camPos = cam.CFrame.Position
                        local rp = RaycastParams.new() 
                        rp.FilterDescendantsInstances = { bestPlr.char, LocalPlayer.Character } 
                        rp.FilterType = Enum.RaycastFilterType.Blacklist
                        
                        local hitRoot = Workspace:Raycast(camPos, bestPlr.root.Position - camPos, rp)
                        local headP = bestPlr.char:FindFirstChild("Head")
                        local hitHead = headP and Workspace:Raycast(camPos, headP.Position - camPos, rp)
                        
                        if hitRoot and not hitHead then aimPart = headP or aimPart end
                    end

                    local predictedPos = aimPart.Position
                    
                    -- Prediction
                    if Toggles.bxw_aim_pred and Toggles.bxw_aim_pred.Value then
                        local velocity = bestPlr.root.AssemblyLinearVelocity
                        if velocity.Magnitude > 0.1 then
                            local factor = (Options.bxw_aim_predfactor and Options.bxw_aim_predfactor.Value) or 0.1
                            predictedPos = predictedPos + (velocity * factor)
                        end
                    end
                    
                    -- RCS
                    if RCSToggle.Value and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                        local rcsY = RCSStrength.Value
                        mousemoverel(0, rcsY * 0.1)
                    end
                    
                    -- Strafe
                    if StrafeToggle.Value then
                        strafeAngle = strafeAngle + dt * 2
                        local radius = 5
                        local targetRoot = bestPlr.root
                        local myRoot = getRootPart()
                        if targetRoot and myRoot then
                            local offset = Vector3.new(math.sin(strafeAngle)*radius, 0, math.cos(strafeAngle)*radius)
                            myRoot.CFrame = CFrame.new(targetRoot.Position + offset, targetRoot.Position)
                        end
                    end

                    -- Apply Camera Move
                    if Options.bxw_aim_method and Options.bxw_aim_method.Value == "MouseDelta" then
                        local pos, vis = cam:WorldToViewportPoint(predictedPos)
                        if vis then
                            local delta = (Vector2.new(pos.X, pos.Y) - mouseLoc)
                            local smooth = (Options.bxw_aim_smooth and Options.bxw_aim_smooth.Value) or 0.5
                            local factor = (smooth > 0) and smooth or 1
                            delta = delta / factor
                            pcall(function() mousemoverel(delta.X, delta.Y) end)
                        end
                    else
                        local newCFrame = CFrame.new(cam.CFrame.Position, predictedPos)
                        local smooth = (Options.bxw_aim_smooth and Options.bxw_aim_smooth.Value) or 0.5
                        local alpha = (smooth > 0) and (0.1 / smooth) or 1
                        if alpha > 1 then alpha = 1 end
                        cam.CFrame = cam.CFrame:Lerp(newCFrame, alpha)
                    end

                    -- Draw Snapline
                    if Toggles.bxw_aim_snapline and Toggles.bxw_aim_snapline.Value then
                        AimbotSnapLine.Visible = true
                        AimbotSnapLine.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                        -- Update screen pos for visual accuracy
                        local sp, _ = cam:WorldToViewportPoint(bestPlr.part.Position) 
                        AimbotSnapLine.To = Vector2.new(sp.X, sp.Y)
                        AimbotSnapLine.Color = (Options.bxw_aim_snapcolor and Options.bxw_aim_snapcolor.Value) or Color3.fromRGB(255,0,0)
                        AimbotSnapLine.Thickness = (Options.bxw_aim_snapthick and Options.bxw_aim_snapthick.Value) or 1
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
        -- Game Info Groupbox
        local GameInfoBox = safeAddRightGroupbox(ServerTab, "Game Info", "info")

        -- Server Hop
        ServerLeft:AddButton("Server Hop", function()
            pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
            NotifyAction("Server Hop", true)
        end)

        -- Low Server Hop
        ServerLeft:AddButton("Low Server Hop", function()
             Library:Notify("Searching low server...", 3)
             pcall(function()
                local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
                local list = HttpService:JSONDecode(game:HttpGet(url))
                if list and list.data then
                    for _, s in ipairs(list.data) do
                        if s.playing < s.maxPlayers and s.id ~= game.JobId then
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                            NotifyAction("Low Server Hop", true)
                            return
                        end
                    end
                end
                Library:Notify("No low server found", 2)
             end)
        end)

        ServerLeft:AddButton("Rejoin Server", function()
             pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
             NotifyAction("Rejoin", true)
        end)
        
        -- Instant Leave
        ServerLeft:AddButton("Instant Leave", function()
            game:Shutdown()
        end)
        
        -- Find Best Server
        ServerLeft:AddButton("Find Best Server", function()
            Library:Notify("Scanning for best ping...", 2)
            -- Note: Real ping check requires hopping. We just list status here.
            local s = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            Library:Notify(string.format("Current Ping: %d ms", s), 3)
        end)

        ServerLeft:AddDivider()

        -- Join Job ID Feature
        local jobInput = ""
        local JoinJobInput = ServerLeft:AddInput("bxw_join_jobid_input", {
            Default = "",
            Numeric = false,
            Finished = false,
            Text = "Input Job ID",
            Tooltip = "Paste the Job ID here",
            Placeholder = "Job ID...",
            Callback = function(Value)
                jobInput = Value
            end
        })

        local JoinBtn = ServerLeft:AddButton("Join Job ID", function()
            if jobInput and jobInput ~= "" then
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobInput, LocalPlayer)
                end)
                NotifyAction("Join Job ID", true)
            else
                Library:Notify("Please input a valid Job ID", 2)
            end
        end)

        -- Anti-AFK
        local antiAfkConn
        local AntiAfkToggle = ServerRight:AddToggle("bxw_anti_afk", { Text = "Anti-AFK", Default = true })
        AntiAfkToggle:OnChanged(function(state)
            if state then
                if antiAfkConn then antiAfkConn:Disconnect() end
                antiAfkConn = AddConnection(LocalPlayer.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end))
            else
                if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
            end
            NotifyAction("Anti-AFK", state)
        end)

        -- Anti Rejoin
        local AntiRejoinToggle = ServerRight:AddToggle("bxw_antirejoin", { Text = "Auto Rejoin on Kick", Default = false })
        local lastKick = 0
        AddConnection(GuiService.ErrorMessageChanged:Connect(function()
            if AntiRejoinToggle.Value then
                local t = tick()
                if t - lastKick > 5 then
                    lastKick = t
                    warn("Kick detected. Rejoining...")
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end
            end
        end))
        AntiRejoinToggle:OnChanged(function(state) NotifyAction("Anti-Rejoin", state) end)
        
        -- Auto Re-Execute
        ServerRight:AddToggle("bxw_autorexec", { Text = "Auto Re-Execute", Default = false, Tooltip = "Queue script on teleport" }):OnChanged(function(state)
            if state and queue_on_teleport then
                queue_on_teleport('loadstring(game:HttpGet("https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/main/KeyMain.lua"))()')
            end
        end)
        
        -- Friend Join Alert
        local FriendAlertToggle = ServerRight:AddToggle("bxw_friend_alert", { Text = "Friend Join Alert", Default = false })
        AddConnection(Players.PlayerAdded:Connect(function(plr)
            if FriendAlertToggle.Value and LocalPlayer:IsFriendsWith(plr.UserId) then
                Library:Notify("Friend Joined: " .. plr.Name, 5)
            end
        end))
        
        -- Chat Logger
        local ChatLogToggle = ServerRight:AddToggle("bxw_chatlog", { Text = "Chat Logger (Console)", Default = false })
        AddConnection(TextChatService.MessageReceived:Connect(function(msg)
            if ChatLogToggle.Value then
                print("[CHAT] " .. msg.TextSource.Name .. ": " .. msg.Text)
            end
        end))


        ServerRight:AddDivider()
        
        ServerRight:AddButton("Copy Job ID", function()
            if setclipboard then
                setclipboard(game.JobId)
                Library:Notify("Copied Job ID", 2)
            else
                Library:Notify("Clipboard not supported", 2)
            end
        end)

        ServerRight:AddButton("Copy Place ID", function()
            if setclipboard then
                setclipboard(tostring(game.PlaceId))
                Library:Notify("Copied Place ID", 2)
            else
                 Library:Notify("Clipboard not supported", 2)
            end
        end)

        -- Game Info Logic
        local placeId = game.PlaceId or 0
        local jobId   = tostring(game.JobId or "N/A")

        local GameNameLabel   = safeRichLabel(GameInfoBox, "<b>Game:</b> Loading...")
        local PlaceIdLabel    = safeRichLabel(GameInfoBox, string.format("<b>PlaceId:</b> %d", placeId))
        local JobIdLabel      = safeRichLabel(GameInfoBox, string.format("<b>JobId:</b> %s", jobId))
        local PlayersLabel    = safeRichLabel(GameInfoBox, "<b>Players:</b> -/-")
        local ServerTimeLabel = safeRichLabel(GameInfoBox, "<b>Server Time:</b> -")

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
                if ServerTimeLabel and ServerTimeLabel.TextLabel then ServerTimeLabel.TextLabel.Text = string.format("<b>Server Time:</b> %s", os.date("%H:%M:%S")) end
            end))
        end
    end

    ------------------------------------------------
    -- 4.5 Misc & System Tab (Graphics & Visuals)
    ------------------------------------------------
    do
        local MiscTab = Tabs.Misc
        local MiscLeft  = MiscTab:AddLeftGroupbox("Game Tools", "tool")
        local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")

        -- Auto Clicker
        MiscLeft:AddLabel("Auto Clicker")
        
        local AutoClickerToggle = MiscLeft:AddToggle("bxw_autoclicker", { Text = "Enable Auto Click", Default = false, Tooltip = "Clicks mouse automatically" })
        
        AutoClickerToggle:AddKeyPicker("AutoClickKey", { Default = "V", NoUI = false, Text = "Auto Click Toggle" })

        local AutoClickDelaySlider = MiscLeft:AddSlider("bxw_autoclick_delay", { Text = "Click Delay (s)", Default = 0.1, Min = 0, Max = 2, Rounding = 2 })
        
        -- Mobile Specific UI
        local clickPosition = nil -- Vector2
        local PositionLabel = MiscLeft:AddLabel("Pos: Default (Center/Mouse)")
        
        local SetPointBtn = MiscLeft:AddButton("Set Click Point (Mobile)", function()
             if not isMobile then 
                 Library:Notify("This feature is for Mobile devices only.", 2)
                 return 
             end
             
             Library:Notify("Tap anywhere on screen to set point...", 3)
             
             local connection
             connection = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    clickPosition = Vector2.new(input.Position.X, input.Position.Y)
                    PositionLabel.TextLabel.Text = string.format("Pos: %d, %d", clickPosition.X, clickPosition.Y)
                    Library:Notify("Click Point Set!", 2)
                    connection:Disconnect()
                end
             end)
        end)
        
        -- [FIXED] Error attemp to index nil with 'Text'
        if not isMobile then
             if SetPointBtn and SetPointBtn.TextLabel then
                SetPointBtn.TextLabel.Text = "Set Point (Mobile Only)"
             end
        end
        
        local AutoClickerConn
        AutoClickerToggle:OnChanged(function(state)
            if state then
                if AutoClickerConn then AutoClickerConn:Disconnect() end
                local lastClick = 0
                
                AutoClickerConn = AddConnection(RunService.RenderStepped:Connect(function()
                     if not Toggles.bxw_autoclicker.Value then return end
                     
                     local delayTime = AutoClickDelaySlider.Value or 0.1
                     
                     if tick() - lastClick > delayTime then
                         lastClick = tick()
                         
                         if isMobile and clickPosition then
                             pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(clickPosition) end)
                         else
                             pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton1(Vector2.new()) end)
                         end
                     end
                end))
            else
                 if AutoClickerConn then AutoClickerConn:Disconnect() AutoClickerConn = nil end
            end
            NotifyAction("Auto Clicker", state)
        end)
        
        MiscLeft:AddDivider()
        MiscLeft:AddSlider("bxw_fps_cap", { Text = "FPS Cap", Default = 60, Min = 30, Max = 360, Rounding = 0, Callback = function(v) if setfpscap then setfpscap(v) end end })
        
        MiscLeft:AddToggle("bxw_spoof_mobile", { Text = "Mock Mobile Input", Default = false, Tooltip = "Fakes touches for some game UIs" }):OnChanged(function(s)
            Library:Notify(s and "Mobile Input Simulation Active" or "Disabled", 2)
        end)
        
        MiscLeft:AddLabel("Universal Emotes")
        local EmoteDropdown = MiscLeft:AddDropdown("bxw_emote_list", { Text = "Play Emote", Values = {"Sit", "Zombie", "Ninja", "Dab"}, Default = "", Multi = false })
        local emoteAnims = {
            Sit = "rbxassetid://2506281703",
            Zombie = "rbxassetid://616164442",
            Ninja = "rbxassetid://656117878",
            Dab = "rbxassetid://248263260"
        }
        MiscLeft:AddButton("Play Selected Emote", function()
             local id = emoteAnims[EmoteDropdown.Value]
             local hum = getHumanoid()
             if hum and id then
                 local anim = Instance.new("Animation")
                 anim.AnimationId = id
                 local track = hum:LoadAnimation(anim)
                 track:Play()
             end
        end)

        MiscLeft:AddDivider()

        -- [FEATURE] Graphics & Visuals Section
        local GfxBox = MiscTab:AddRightGroupbox("Graphics & Visuals", "monitor")
        
        GfxBox:AddButton("Potato Mode (FPS Boost)", function()
            pcall(function()
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 9e9
                Lighting.Brightness = 0
                for _, v in pairs(Workspace:GetDescendants()) do
                    if v:IsA("BasePart") and not v:IsA("MeshPart") then
                        v.Material = Enum.Material.SmoothPlastic
                        v.CastShadow = false
                    end
                end
            end)
            Library:Notify("Potato Mode Enabled", 2)
        end)

        -- [FIXED] Beautiful Mode Toggle
        local OriginalLighting = {}
        local BeautifulToggle = GfxBox:AddToggle("bxw_beautiful_mode", { Text = "Beautiful Mode", Default = false })
        
        BeautifulToggle:OnChanged(function(state)
            if state then
                -- Save current
                OriginalLighting.Technology = Lighting.Technology
                OriginalLighting.Shadows = Lighting.GlobalShadows
                OriginalLighting.Ambient = Lighting.OutdoorAmbient
                
                -- Apply Beautiful
                Lighting.GlobalShadows = true
                Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 100)
                pcall(function() sethiddenproperty(Lighting, "Technology", Enum.Technology.Future) end)
                
                if not Lighting:FindFirstChild("ColorCorrection") then Instance.new("ColorCorrectionEffect", Lighting) end
                if not Lighting:FindFirstChild("Bloom") then Instance.new("BloomEffect", Lighting) end
                NotifyAction("Beautiful Mode", true)
            else
                -- Restore
                Lighting.GlobalShadows = OriginalLighting.Shadows or false
                Lighting.OutdoorAmbient = OriginalLighting.Ambient or Color3.fromRGB(128,128,128)
                pcall(function() sethiddenproperty(Lighting, "Technology", OriginalLighting.Technology or Enum.Technology.ShadowMap) end)
                NotifyAction("Beautiful Mode", false)
            end
        end)
        
        GfxBox:AddSlider("bxw_gfx_bright", { Text = "Brightness", Default = 2, Min = 0, Max = 10, Rounding = 1, Callback = function(v) Lighting.Brightness = v end })
        GfxBox:AddSlider("bxw_gfx_sat", { Text = "Saturation", Default = 0.2, Min = 0, Max = 2, Rounding = 1, Callback = function(v) 
             local cc = Lighting:FindFirstChild("ColorCorrection")
             if cc then cc.Saturation = v end
        end })
        GfxBox:AddSlider("bxw_gfx_contrast", { Text = "Contrast", Default = 0.1, Min = 0, Max = 1, Rounding = 1, Callback = function(v) 
             local cc = Lighting:FindFirstChild("ColorCorrection")
             if cc then cc.Contrast = v end
        end })
         GfxBox:AddSlider("bxw_gfx_bloom", { Text = "Bloom Intensity", Default = 0.1, Min = 0, Max = 2, Rounding = 1, Callback = function(v) 
             local bl = Lighting:FindFirstChild("Bloom")
             if bl then bl.Intensity = v end
        end })
        
        -- [FIXED] 3D Rendering (Logic Inverted for Clarity)
        GfxBox:AddToggle("bxw_3d_render", { Text = "Disable 3D Rendering (Boost)", Default = false }):OnChanged(function(v)
             -- If True (Checked) -> Disable 3D (Set Enabled to False)
             RunService:Set3dRenderingEnabled(not v)
        end)
        
        GfxBox:AddButton("Clean Memory", function()
             for i=1,5 do garbagecollect() end
             Library:Notify("Memory Cleaned", 2)
        end)

        local ShadowToggle = GfxBox:AddToggle("bxw_shadows", { Text = "Shadows", Default = Lighting.GlobalShadows })
        ShadowToggle:OnChanged(function(state) Lighting.GlobalShadows = state NotifyAction("Shadows", state) end)

        local TimeSlider = GfxBox:AddSlider("bxw_time", { Text = "Time of Day", Default = 12, Min = 0, Max = 24, Rounding = 1, Callback = function(v) Lighting.ClockTime = v end })
        
        -- Fullbright
        local FullbrightToggle = GfxBox:AddToggle("bxw_fullbright", { Text = "Fullbright", Default = false })
        local fbLoop
        FullbrightToggle:OnChanged(function(state)
            if state then
                if fbLoop then fbLoop:Disconnect() end
                fbLoop = AddConnection(RunService.LightingChanged:Connect(function()
                    Lighting.Brightness = 2
                    Lighting.ClockTime = 14
                    Lighting.FogEnd = 1e10
                    Lighting.GlobalShadows = false
                    Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                end))
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
            else
                if fbLoop then fbLoop:Disconnect() fbLoop = nil end
            end
            NotifyAction("Fullbright", state)
        end)
        
        -- [UPGRADE] X-Ray Slider
        local XrayTransSlider = GfxBox:AddSlider("bxw_xray_val", { Text = "X-Ray Transparency", Default = 0.5, Min = 0.1, Max = 0.9, Rounding = 1 })
        local XrayToggle = GfxBox:AddToggle("bxw_xray", { Text = "X-Ray (Wall Trans)", Default = false })
        
        XrayToggle:OnChanged(function(state)
             if state then
                local val = XrayTransSlider.Value
                for _, v in pairs(workspace:GetDescendants()) do
                    if v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then
                        v.LocalTransparencyModifier = val
                    end
                end
             else
                 for _, v in pairs(workspace:GetDescendants()) do
                    if v:IsA("BasePart") then
                        v.LocalTransparencyModifier = 0
                    end
                end
             end
             NotifyAction("X-Ray", state)
        end)
        
        -- Update Xray dynamically if slider changes while enabled
        XrayTransSlider:OnChanged(function(v)
            if XrayToggle.Value then
                for _, p in pairs(workspace:GetDescendants()) do
                    if p:IsA("BasePart") and not p.Parent:FindFirstChild("Humanoid") then
                        p.LocalTransparencyModifier = v
                    end
                end
            end
        end)


        local defaultGravity = Workspace.Gravity
        local GravitySlider = MiscRight:AddSlider("bxw_gravity", { Text = "Gravity", Default = defaultGravity, Min = 0, Max = 300, Rounding = 0, Compact = false, Callback = function(value) Workspace.Gravity = value end })
        MiscRight:AddButton("Reset Gravity", function() Workspace.Gravity = defaultGravity GravitySlider:SetValue(defaultGravity) end)
        local fogDefaults = { FogStart = game.Lighting.FogStart, FogEnd = game.Lighting.FogEnd }
        local NoFogToggle = MiscRight:AddToggle("bxw_nofog", { Text = "No Fog", Default = false })
        NoFogToggle:OnChanged(function(state)
            if state then fogDefaults.FogStart = game.Lighting.FogStart fogDefaults.FogEnd = game.Lighting.FogEnd game.Lighting.FogStart = 0 game.Lighting.FogEnd = 1e10
            else game.Lighting.FogStart = fogDefaults.FogStart or 0 game.Lighting.FogEnd = fogDefaults.FogEnd or 1e10 end
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
        
        SpinToggle:OnChanged(function(state)
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
        MiscLeft:AddButton("Respawn Character", function() pcall(function() LocalPlayer:LoadCharacter() end) end)
    end

    ------------------------------------------------
    -- 4.6 Settings Tab
    ------------------------------------------------
    do
        local SettingsTab = Tabs.Settings
        local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
        
        MenuGroup:AddToggle("ForceNotify", { Text = "Force Notification", Default = true, Tooltip = "Notify when features are toggled" })

        MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end })
        MenuGroup:AddToggle("ShowCustomCursor", { Text = FormatFeatureName("Custom Cursor", "Mouse"), Default = true, Callback = function(Value) Library.ShowCustomCursor = Value end })
        MenuGroup:AddDropdown("NotificationSide", { Values = { "Left", "Right" }, Default = "Right", Text = "Notification Side", Callback = function(Value) Library:SetNotifySide(Value) end })
        MenuGroup:AddDropdown("DPIDropdown", { Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" }, Default = "100%", Text = "DPI Scale", Callback = function(Value) Value = tostring(Value):gsub("%%", "") local DPI = tonumber(Value) if DPI then Library:SetDPIScale(DPI) end end })
        MenuGroup:AddDivider()
        MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = false, Text = "Menu keybind" })
        
        MenuGroup:AddLabel("Panic Bind"):AddKeyPicker("PanicKeybind", { Default = "End", NoUI = false, Text = "Panic (Unload)", Callback = function() Library:Unload() end })

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
        -- Update Watermark loop - OPTIMIZED
        local lastUpdate = 0
        AddConnection(RunService.RenderStepped:Connect(function()
            if tick() - lastUpdate >= 1 then
                lastUpdate = tick()
                local ping = 0
                pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                local fps = math.floor(1 / math.max(RunService.RenderStepped:Wait(), 0.001))
                local timeStr = os.date("%H:%M:%S")
                Library:SetWatermark(string.format("BxB.ware | Universal | FPS: %d | Ping: %d ms | %s | %s", fps, ping, timeStr, DeviceType))
            end
        end))
    end)


    ------------------------------------------------
    -- 4.7 Clean Up
    ------------------------------------------------
    if Library and type(Library.OnUnload) == "function" then
        Library:OnUnload(function()
            -- 1. Disconnect Connections
            for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
            RunService:UnbindFromRenderStep("BxB_FreeCam")
            
            -- 2. Clear Drawings
            if espDrawings then
                for _, plrData in pairs(espDrawings) do
                    for _, item in pairs(plrData) do
                        if type(item) == "table" then for _, d in pairs(item) do pcall(function() d:Remove() end) end
                        elseif typeof(item) == "Instance" then pcall(function() item:Destroy() end)
                        elseif item.Remove then pcall(function() item:Remove() end) end
                    end
                end
            end
            
            -- 3. Clear Radar
            if radarDrawings then
                if radarDrawings.outline then radarDrawings.outline:Remove() end
                if radarDrawings.line then radarDrawings.line:Remove() end
                if radarDrawings.bg then radarDrawings.bg:Remove() end
                for _, p in pairs(radarDrawings.points) do p:Remove() end
            end
            
            -- 4. Clear Crosshair & FOV
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
