--[[
    Diablo Universal Hub (Final Resurrection v7)
    - FULLY RESTORED 1600+ Lines Codebase
    - All Features from v4 + Upgrades from v6
    - Fixed ESP Data (Health/Weapon/Team)
    - Advanced Graphics Manager (RTX/Potato)
    - Smart UI Interaction (Disabled Logic)
    - Force Notify System
    
    Supports: Wave, Potassium, Volt, Delta, Fluxus, Hydrogen, and all modern executors.
]]

--====================================================
-- 0. Services & Universal Utility
--====================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")
local GuiService         = game:GetService("GuiService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local Lighting           = game:GetService("Lighting")
local CoreGui            = game:GetService("CoreGui")
local Workspace          = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Debris             = game:GetService("Debris")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterGui         = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- Force Notify Flag
getgenv().DiabloForceNotify = false

local function NotifyAction(msg)
    if getgenv().DiabloForceNotify and getgenv().DiabloLibrary and getgenv().DiabloLibrary.Notify then
        getgenv().DiabloLibrary:Notify("Action: " .. msg, 2)
    end
end

-- Universal Input Function
local function ClickMouse()
    if getgenv and getgenv().mouse1click then
        getgenv().mouse1click()
    elseif getgenv and getgenv().mouse1press and getgenv().mouse1release then
        getgenv().mouse1press()
        task.wait()
        getgenv().mouse1release()
    else
        VirtualUser:Button1Down(Vector2.new())
        VirtualUser:Button1Up(Vector2.new())
    end
end

-- Universal HttpGet
local function SafeHttpGet(url)
    if typeof(syn) == "table" and syn.request then
        local response = syn.request({Url = url, Method = "GET"})
        return response.Body
    elseif typeof(request) == "function" then
        local response = request({Url = url, Method = "GET"})
        return response.Body
    else
        return game:HttpGet(url)
    end
end

-- Drawing API Check
local DrawingApiAvailable = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")
local function SafeDrawingNew(type)
    if DrawingApiAvailable then
        return Drawing.new(type)
    else
        return setmetatable({}, {
            __index = function(_, k) return function() end end,
            __newindex = function(_, k, v) end
        })
    end
end

-- Cleanup System
local Connections = {}
local function AddConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

local function getCharacter(plr)
    plr = plr or LocalPlayer
    if not plr then return end
    return plr.Character
end

local function getHumanoid(plr)
    local char = getCharacter(plr)
    if not char then return end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(plr)
    local char = getCharacter(plr)
    if not char then return end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

-- [SYSTEM] Link Toggle Logic (Smart Disabled)
local function LinkToggle(toggle, elements)
    -- Initial state check
    local function updateState(val)
        for _, el in ipairs(elements) do
            if el.SetDisabled then 
                el:SetDisabled(not val)
            elseif type(el) == "table" and el.Disabled ~= nil then
                el.Disabled = not val
                if getgenv().DiabloLibrary and getgenv().DiabloLibrary.UpdateUI then
                     getgenv().DiabloLibrary:UpdateUI() 
                end
            end
        end
    end
    
    -- Apply initial
    updateState(toggle.Value)
    
    -- On Change
    toggle:OnChanged(function(val)
        updateState(val)
        if toggle.Text and getgenv().DiabloForceNotify then 
            NotifyAction(toggle.Text .. ": " .. tostring(val)) 
        end
    end)
end

--====================================================
-- 1. Secret + Token Verify
--====================================================
local SECRET_PEPPER = "BxB.ware-Universal@#$)_%@#^()$@%_)+%(@"
local bit = bit32 or require(script.Parent.bit)

local function fnv1a32(str)
    local hash = 0x811C9DC5
    for i = 1, #str do
        hash = bit.bxor(hash, str:byte(i))
        hash = (hash * 0x01000193) % 0x100000000
    end
    return hash
end

local function buildExpectedToken(keydata)
    if not keydata then return "" end
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
local RolePriority = { free = 0, user = 1, premium = 2, vip = 3, staff = 4, owner = 5 }

local function NormalizeRole(role)
    role = tostring(role or ""):lower()
    if RolePriority[role] then return role end
    return "free"
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
    if lbl and lbl.TextLabel then lbl.TextLabel.RichText = true end
    return lbl
end

--====================================================
-- 4. MainHub Logic (Full Ultimate v7)
--====================================================

local function MainHub(Exec, keydata, authToken)
    if not keydata then
        keydata = { key = "DEV_MODE", role = "owner", status = "Developer" }
        authToken = buildExpectedToken(keydata)
    end
    
    local expected = buildExpectedToken(keydata)
    if authToken ~= expected then 
        warn("[MainHub] Auth token mismatch (Safe Mode).") 
    end

    -- Global Storage
    local espDrawings = {}
    local crosshairLines = nil
    local AimbotFOVCircle = nil
    local AimbotFOVSquare = nil
    local AimbotSnapLine = nil
    local CurrentTarget = nil

    keydata.role = NormalizeRole(keydata.role)

    -- Load Library
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local success, Library = pcall(function() return loadstring(SafeHttpGet(repo .. "Library.lua"))() end)
    
    if not success or not Library then
        warn("Failed to load Obsidian, falling back to LinoriaLib...")
        repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
        Library = loadstring(SafeHttpGet(repo .. "Library.lua"))()
    end
    
    getgenv().DiabloLibrary = Library
    
    local ThemeManager = loadstring(SafeHttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(SafeHttpGet(repo .. "addons/SaveManager.lua"))()

    local Options = Library.Options
    local Toggles = Library.Toggles

    local Window = Library:CreateWindow({
        Title  = "BxB | Diablo Universal v7",
        Footer = '<b><font color="#B563FF">BxB.ware | Universal | Game Module</font></b>',
        Icon = "84528813312016",
        Center   = true,
        Size     = UDim2.fromOffset(850, 650),
        AutoShow         = true,
        Resizable        = true,
        NotifySide       = "Right",
        ShowCustomCursor = false,
        CornerRadius = 4,
        MobileButtonsSide = "Left",
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
    
    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))
    
    local ExpireLabel = safeRichLabel(KeyBox, "<b>Expire:</b> Loading...")
    local TimeLeftLabel = safeRichLabel(KeyBox, "<b>Time left:</b> Loading...")

    local nextUpdate = 0
    AddConnection(RunService.Heartbeat:Connect(function(dt)
        if tick() >= nextUpdate then
            nextUpdate = tick() + 1
            local nowExpire = tonumber(keydata.expire) or 0
            if ExpireLabel.TextLabel then ExpireLabel.TextLabel.Text = string.format("<b>Expire:</b> %s", formatUnixTime(nowExpire)) end
            if TimeLeftLabel.TextLabel then TimeLeftLabel.TextLabel.Text = string.format("<b>Time left:</b> %s", formatTimeLeft(nowExpire)) end
        end
    end))

    KeyBox:AddDivider()
    KeyBox:AddButton("Copy Key Info", function()
        if setclipboard then
            setclipboard(string.format("Key: %s", rawKey))
            Library:Notify("Copied", 2)
        end
    end)
    
    local GameBox = safeAddRightGroupbox(InfoTab, "Game Info", "info")
    safeRichLabel(GameBox, '<font size="14"><b>Game / Server Information</b></font>')
    local GameNameLabel = safeRichLabel(GameBox, "<b>Game:</b> Loading...")
    safeRichLabel(GameBox, string.format("<b>PlaceId:</b> %d", game.PlaceId))
    safeRichLabel(GameBox, string.format("<b>JobId:</b> %s", game.JobId))
    local PlayersLabel = safeRichLabel(GameBox, "<b>Players:</b> -/-")
    local PerfLabel = safeRichLabel(GameBox, "<b>Perf:</b> FPS: - | Ping: -")
    local ServerTimeLabel = safeRichLabel(GameBox, "<b>Server Time:</b> -")
    
    task.spawn(function()
        local n = "Unknown"
        pcall(function() n = MarketplaceService:GetProductInfo(game.PlaceId).Name end)
        if GameNameLabel.TextLabel then GameNameLabel.TextLabel.Text = string.format("<b>Game:</b> %s", n) end
    end)

    local function updatePlayersLabel()
        local cur = #Players:GetPlayers()
        local max = Players.MaxPlayers or "-"
        if PlayersLabel.TextLabel then PlayersLabel.TextLabel.Text = string.format("<b>Players:</b> %d / %s", cur, tostring(max)) end
    end
    updatePlayersLabel()
    AddConnection(Players.PlayerAdded:Connect(updatePlayersLabel))
    AddConnection(Players.PlayerRemoving:Connect(updatePlayersLabel))

    AddConnection(RunService.Heartbeat:Connect(function(dt)
        local fps = math.floor(1/math.max(dt, 1/240))
        local ping = 0
        pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
        if PerfLabel.TextLabel then PerfLabel.TextLabel.Text = string.format("<b>Perf:</b> FPS: %d | Ping: %d ms", fps, ping) end
        if ServerTimeLabel.TextLabel then ServerTimeLabel.TextLabel.Text = string.format("<b>Server Time:</b> %s", os.date("%H:%M:%S")) end
    end))

    ------------------------------------------------
    -- TAB 2: Player
    ------------------------------------------------
    local PlayerTab = Tabs.Player
    local MoveBox = PlayerTab:AddLeftGroupbox("Player Movement", "user")

    local WalkSpeedToggle = MoveBox:AddToggle("bxw_walkspeed_toggle", { Text = "Enable WalkSpeed", Default = false })
    local WalkSpeedSlider = MoveBox:AddSlider("bxw_walkspeed", { Text = "WalkSpeed", Default = 16, Min = 0, Max = 300, Rounding = 0 })
    local WalkMethodDropdown = MoveBox:AddDropdown("bxw_walk_method", { Text = "Walk Method", Values = { "Direct", "Incremental" }, Default = "Direct" })
    LinkToggle(WalkSpeedToggle, {WalkSpeedSlider, WalkMethodDropdown})

    local JumpPowerToggle = MoveBox:AddToggle("bxw_jumppower_toggle", { Text = "Enable JumpPower", Default = false })
    local JumpPowerSlider = MoveBox:AddSlider("bxw_jumppower", { Text = "JumpPower", Default = 50, Min = 0, Max = 500, Rounding = 0 })
    LinkToggle(JumpPowerToggle, {JumpPowerSlider})

    AddConnection(RunService.RenderStepped:Connect(function()
        local hum = getHumanoid()
        if hum then
            if WalkSpeedToggle.Value then hum.WalkSpeed = WalkSpeedSlider.Value end
            if JumpPowerToggle.Value then hum.UseJumpPower = true hum.JumpPower = JumpPowerSlider.Value end
        end
    end))

    MoveBox:AddLabel("Presets")
    local MovePresetDropdown = MoveBox:AddDropdown("bxw_move_preset", { Text = "Speed Preset", Values = { "Default", "Fast", "Flash" }, Default = "Default" })
    MovePresetDropdown:OnChanged(function(v)
        if v=="Default" then WalkSpeedSlider:SetValue(16)
        elseif v=="Fast" then WalkSpeedSlider:SetValue(50)
        elseif v=="Flash" then WalkSpeedSlider:SetValue(100) end
    end)

    MoveBox:AddDivider()
    local InfJumpToggle = MoveBox:AddToggle("bxw_infjump", { Text = "Infinite Jump", Default = false })
    local infJumpConn
    InfJumpToggle:OnChanged(function(state)
        if state then
            infJumpConn = AddConnection(UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid() if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end))
        elseif infJumpConn then infJumpConn:Disconnect() infJumpConn = nil end
    end)

    local MultiJumpToggle = MoveBox:AddToggle("bxw_multijump", { Text = "Multi-Jump (Air Jump)", Default = false })
    AddConnection(UserInputService.JumpRequest:Connect(function()
        if MultiJumpToggle.Value then
            local hum = getHumanoid() if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end))

    local SpiderToggle = MoveBox:AddToggle("bxw_spider", { Text = "Spider Mode (Wall Climb)", Default = false })
    AddConnection(RunService.Heartbeat:Connect(function()
        if SpiderToggle.Value then
            local root = getRootPart()
            local char = getCharacter()
            if root and char then
                local vec = root.CFrame.LookVector
                local rc = RaycastParams.new() rc.FilterDescendantsInstances = {char} rc.FilterType = Enum.RaycastFilterType.Blacklist
                local hit = Workspace:Raycast(root.Position, vec * 2, rc)
                if hit then
                    local vel = root:FindFirstChild("SpiderVel") or Instance.new("BodyVelocity", root)
                    vel.Name = "SpiderVel" vel.MaxForce = Vector3.new(0, 1e5, 0) vel.Velocity = Vector3.new(0, 20, 0)
                else
                    local vel = root:FindFirstChild("SpiderVel") if vel then vel:Destroy() end
                end
            end
        else
            local root = getRootPart() if root then local vel = root:FindFirstChild("SpiderVel") if vel then vel:Destroy() end end
        end
    end))

    local FlyToggle = MoveBox:AddToggle("bxw_fly", { Text = MarkRisky("Fly (Universal)"), Default = false })
    local FlySpeedSlider = MoveBox:AddSlider("bxw_fly_speed", { Text = "Fly Speed", Default = 60, Min = 1, Max = 300, Rounding = 0 })
    LinkToggle(FlyToggle, {FlySpeedSlider})
    
    local flyEnabled, flyBV, flyBG = false, nil, nil
    local function cleanupFly() if flyBV then flyBV:Destroy() flyBV=nil end if flyBG then flyBG:Destroy() flyBG=nil end local h=getHumanoid() if h then h.PlatformStand=false end end
    local function setupFly(r) cleanupFly() flyBV=Instance.new("BodyVelocity",r) flyBV.MaxForce=Vector3.new(9e9,9e9,9e9) flyBG=Instance.new("BodyGyro",r) flyBG.MaxTorque=Vector3.new(9e9,9e9,9e9) flyBG.P=9000 local h=getHumanoid() if h then h.PlatformStand=true end end
    FlyToggle:OnChanged(function(s) flyEnabled=s if s then setupFly(getRootPart()) else cleanupFly() end end)
    AddConnection(RunService.RenderStepped:Connect(function()
        if flyEnabled and flyBV and flyBG then
            local cam, hum, root = Workspace.CurrentCamera, getHumanoid(), getRootPart()
            if hum and root and cam then
                hum.PlatformStand = true
                local md = hum.MoveDirection
                local lv, rv = cam.CFrame.LookVector, cam.CFrame.RightVector
                local fl, fr = Vector3.new(lv.X,0,lv.Z).Unit, Vector3.new(rv.X,0,rv.Z).Unit
                local dv = (fl * md:Dot(fl)) + (fr * md:Dot(fr))
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dv = dv + Vector3.new(0,1,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dv = dv - Vector3.new(0,1,0) end
                flyBV.Velocity = dv.Unit * FlySpeedSlider.Value
                if dv.Magnitude == 0 then flyBV.Velocity = Vector3.zero end
                flyBG.CFrame = cam.CFrame
            end
        end
    end))
    
    local NoclipToggle = MoveBox:AddToggle("bxw_noclip", { Text = MarkRisky("Noclip"), Default = false })
    AddConnection(RunService.Stepped:Connect(function()
        if NoclipToggle.Value then
            local char = getCharacter()
            if char then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end end end
        end
    end))

    local SafetyBox = PlayerTab:AddLeftGroupbox("Safety & Rescue", "shield")
    local AntiVoidToggle = SafetyBox:AddToggle("bxw_antivoid", { Text = "Anti-Void", Default = false })
    local VoidDepth = SafetyBox:AddSlider("bxw_void_depth", { Text = "Void Depth (Y)", Default = -100, Min = -500, Max = -50 })
    LinkToggle(AntiVoidToggle, {VoidDepth})

    AddConnection(RunService.Heartbeat:Connect(function()
        if AntiVoidToggle.Value then
            local r = getRootPart()
            if r and r.Position.Y < VoidDepth.Value then
                r.Velocity = Vector3.zero
                r.CFrame = r.CFrame + Vector3.new(0, 100, 0)
                NotifyAction("Anti-Void Rescue")
            end
        end
    end))

    SafetyBox:AddButton("Create Safe Platform", function()
        local r = getRootPart()
        if r then
            local p = Instance.new("Part", Workspace) p.Anchored = true p.Size = Vector3.new(20, 2, 20) p.Position = r.Position + Vector3.new(0, 500, 0)
            r.CFrame = p.CFrame + Vector3.new(0, 3, 0)
            NotifyAction("Safe Platform Created")
        end
    end)

    local UtilBox = safeAddRightGroupbox(PlayerTab, "Teleport / Utility", "map")
    local TeleportDropdown = UtilBox:AddDropdown("bxw_tpplayer", { Text = "Teleport to Player", Values = {}, Default = "", AllowNull = true })
    
    local function UpdatePlayerLists()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(list, p.Name) end
        end
        table.sort(list)
        if TeleportDropdown then TeleportDropdown:SetValues(list) end
    end
    AddConnection(Players.PlayerAdded:Connect(UpdatePlayerLists))
    AddConnection(Players.PlayerRemoving:Connect(UpdatePlayerLists))
    
    UtilBox:AddButton("Teleport", function()
        local t = Players:FindFirstChild(TeleportDropdown.Value)
        local r = getRootPart()
        if t and t.Character and t.Character:FindFirstChild("HumanoidRootPart") and r then
            r.CFrame = t.Character.HumanoidRootPart.CFrame + Vector3.new(0,3,0)
            NotifyAction("Teleported to player")
        end
    end)
    
    UtilBox:AddDivider()
    local SpectateDropdown = UtilBox:AddDropdown("bxw_spectate_target", { Text = "Spectate Target", Values = {}, Default = "", AllowNull = true })
    local SpectateToggle = UtilBox:AddToggle("bxw_spectate_toggle", { Text = "Spectate Player", Default = false })
    local spectateConn
    LinkToggle(SpectateToggle, {SpectateDropdown})
    
    SpectateToggle:OnChanged(function(state)
        if state then
            local targetName = SpectateDropdown.Value
            if not targetName or targetName == "" then 
                Library:Notify("Select a player first", 2) SpectateToggle:SetValue(false) return 
            end
            spectateConn = AddConnection(RunService.Stepped:Connect(function()
                local target = Players:FindFirstChild(targetName)
                local cam = Workspace.CurrentCamera
                if target and target.Character then
                    local hum = target.Character:FindFirstChild("Humanoid")
                    if hum then cam.CameraSubject = hum end
                else
                    if not target then SpectateToggle:SetValue(false) end
                end
            end))
        else
            if spectateConn then spectateConn:Disconnect() spectateConn = nil end
            local cam = Workspace.CurrentCamera
            local hum = getHumanoid()
            if hum then cam.CameraSubject = hum end
        end
    end)

    UtilBox:AddDivider()
    local savedWaypoints, savedNames = {}, {}
    local WaypointNameInput = UtilBox:AddInput("bxw_waypoint_name", { Text = "Waypoint Name", Default = "Point1" })
    local WaypointDropdown = UtilBox:AddDropdown("bxw_waypoint_list", { Text = "Waypoint List", Values = savedNames, Default = "", AllowNull = true })
    
    UtilBox:AddButton("Set Waypoint", function()
        local r = getRootPart()
        if r then
            local n = WaypointNameInput.Value
            if n == "" then n = "WP" .. (#savedNames+1) end
            savedWaypoints[n] = r.CFrame 
            if not table.find(savedNames, n) then table.insert(savedNames, n) end
            WaypointDropdown:SetValues(savedNames)
            Library:Notify("Saved " .. n, 2)
        end
    end)
    
    UtilBox:AddButton("Teleport to Waypoint", function()
        local s = WaypointDropdown.Value
        local r = getRootPart()
        if s and savedWaypoints[s] and r then r.CFrame = savedWaypoints[s] + Vector3.new(0,3,0) end
    end)
    UtilBox:AddButton("Delete Waypoint", function()
        local s = WaypointDropdown.Value
        if s and savedWaypoints[s] then
            savedWaypoints[s] = nil
            for i,v in ipairs(savedNames) do if v == s then table.remove(savedNames, i) break end end
            WaypointDropdown:SetValues(savedNames)
            WaypointDropdown:SetValue(nil)
        end
    end)

    local CamBox = safeAddRightGroupbox(PlayerTab, "Camera & World", "sun")
    local FreecamToggle = CamBox:AddToggle("bxw_freecam", { Text = "Freecam (Explore)", Default = false })
    local freecamPart, freecamConn = nil, nil
    FreecamToggle:OnChanged(function(state)
        local cam = Workspace.CurrentCamera
        local hum = getHumanoid()
        if state and getRootPart() then
            if hum then hum.PlatformStand = true end
            if freecamPart then freecamPart:Destroy() end
            freecamPart = Instance.new("Part") freecamPart.Anchored = true freecamPart.Transparency = 1 freecamPart.CanCollide = false freecamPart.CFrame = cam.CFrame freecamPart.Parent = Workspace
            cam.CameraSubject = freecamPart
            freecamConn = AddConnection(RunService.RenderStepped:Connect(function()
                if not FreecamToggle.Value or not freecamPart then return end
                local speed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
                local cf = freecamPart.CFrame
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then cf = cf * CFrame.new(0,0,-speed) end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then cf = cf * CFrame.new(0,0,speed) end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then cf = cf * CFrame.new(-speed,0,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then cf = cf * CFrame.new(speed,0,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.Q) then cf = cf * CFrame.new(0,speed,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.E) then cf = cf * CFrame.new(0,-speed,0) end
                freecamPart.CFrame = cf cam.CFrame = cf
            end))
        else
            if freecamConn then freecamConn:Disconnect() freecamConn = nil end
            if freecamPart then freecamPart:Destroy() freecamPart = nil end
            if hum then hum.PlatformStand = false cam.CameraSubject = hum end
        end
    end)

    CamBox:AddDivider()
    CamBox:AddSlider("bxw_cam_fov", { Text = "Camera FOV", Default = 70, Min = 40, Max = 120, Callback = function(v) Workspace.CurrentCamera.FieldOfView = v end })
    CamBox:AddSlider("bxw_cam_maxzoom", { Text = "Max Zoom", Default = 400, Min = 10, Max = 1000, Callback = function(v) LocalPlayer.CameraMaxZoomDistance = v end })
    
    CamBox:AddDropdown("bxw_cam_skybox", { Text = "Skybox Theme", Values = { "Default", "Space", "Sunset", "Midnight" }, Default = "Default", Callback = function(v)
        local l = Lighting
        for _, obj in ipairs(l:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local ids = { Space="rbxassetid://11755937810", Sunset="rbxassetid://9393701400", Midnight="rbxassetid://11755930464" }
        if ids[v] then
            local s = Instance.new("Sky") s.Name = "BxBSky" s.SkyboxBk, s.SkyboxDn, s.SkyboxFt = ids[v], ids[v], ids[v] s.SkyboxLf, s.SkyboxRt, s.SkyboxUp = ids[v], ids[v], ids[v] s.Parent = l
        end
    end})

    ------------------------------------------------
    -- TAB 3: ESP & Visuals (Fixed Data & Linked)
    ------------------------------------------------
    local ESPTab = Tabs.ESP
    local ESPFeatureBox = ESPTab:AddLeftGroupbox("ESP Features", "eye")
    local ESPSettingBox = safeAddRightGroupbox(ESPTab, "ESP Settings", "palette")
    local VisualsBox = safeAddRightGroupbox(ESPTab, "2D Radar & Arrows", "compass")
    local TracerBox = ESPTab:AddLeftGroupbox("Bullet Tracers", "crosshair")

    local ESPEnabledToggle = ESPFeatureBox:AddToggle("bxw_esp_enable", { Text = "Enable ESP Master", Default = false })
    
    local BoxToggle = ESPFeatureBox:AddToggle("bxw_esp_box", { Text = "Box", Default = true })
    local BoxColor = BoxToggle:AddColorPicker("bxw_esp_box_color", { Default = Color3.fromRGB(255, 255, 255) })
    local BoxStyleDropdown = ESPFeatureBox:AddDropdown("bxw_esp_box_style", { Text = "Box Style", Values = { "Box", "Corner" }, Default = "Box" })
    LinkToggle(BoxToggle, {BoxStyleDropdown})

    local NameToggle = ESPFeatureBox:AddToggle("bxw_esp_name", { Text = "Name Tag", Default = true })
    NameToggle:AddColorPicker("bxw_esp_name_color", { Default = Color3.fromRGB(255, 255, 255) })
    
    local HealthToggle = ESPFeatureBox:AddToggle("bxw_esp_health", { Text = "Health Bar", Default = false })
    HealthToggle:AddColorPicker("bxw_esp_health_color", { Default = Color3.fromRGB(0, 255, 0) })
    
    local ToolEspToggle = ESPFeatureBox:AddToggle("bxw_esp_tool", { Text = "Tool / Weapon", Default = false })
    ToolEspToggle:AddColorPicker("bxw_esp_tool_color", { Default = Color3.fromRGB(255, 255, 0) })

    local DistToggle = ESPFeatureBox:AddToggle("bxw_esp_distance", { Text = "Distance", Default = false })
    DistToggle:AddColorPicker("bxw_esp_dist_color", { Default = Color3.fromRGB(255, 255, 255) })
    
    local InfoToggle = ESPFeatureBox:AddToggle("bxw_esp_info", { Text = "Target Info (HP/Team)", Default = false })
    InfoToggle:AddColorPicker("bxw_esp_info_color", { Default = Color3.fromRGB(255, 255, 255) })

    local TracerToggle = ESPFeatureBox:AddToggle("bxw_esp_tracer", { Text = "Tracer Lines", Default = false })
    TracerToggle:AddColorPicker("bxw_esp_tracer_color", { Default = Color3.fromRGB(255, 255, 255) })
    
    local ViewTracerToggle = ESPFeatureBox:AddToggle("bxw_view_tracer", { Text = "View Tracers", Default = false })
    ViewTracerToggle:AddColorPicker("bxw_view_tracer_color", { Default = Color3.fromRGB(255, 100, 100) })

    local ChamsToggle = ESPFeatureBox:AddToggle("bxw_esp_chams", { Text = "Chams", Default = false })
    ChamsToggle:AddColorPicker("bxw_esp_chams_color", { Default = Color3.fromRGB(0, 255, 0) })

    local SkeletonToggle = ESPFeatureBox:AddToggle("bxw_esp_skeleton", { Text = "Skeleton", Default = false })
    SkeletonToggle:AddColorPicker("bxw_esp_skeleton_color", { Default = Color3.fromRGB(0, 255, 255) })
    
    local HeadDotToggle = ESPFeatureBox:AddToggle("bxw_esp_headdot", { Text = "Head Dot", Default = false })
    HeadDotToggle:AddColorPicker("bxw_esp_headdot_color", { Default = Color3.fromRGB(255, 0, 0) })

    local TeamToggle = ESPFeatureBox:AddToggle("bxw_esp_team", { Text = "Team Check", Default = true })
    local WallToggle = ESPFeatureBox:AddToggle("bxw_esp_wall", { Text = "Wall Check", Default = false })
    
    LinkToggle(ESPEnabledToggle, {
        BoxToggle, BoxStyleDropdown, NameToggle, HealthToggle, ToolEspToggle, DistToggle, 
        InfoToggle, TracerToggle, ViewTracerToggle, ChamsToggle, SkeletonToggle, HeadDotToggle, 
        TeamToggle, WallToggle
    })

    local RadarToggle = VisualsBox:AddToggle("bxw_radar_enable", { Text = "Enable 2D Radar", Default = false })
    local RadarX = VisualsBox:AddSlider("bxw_radar_x", { Text = "Position X", Default = 150, Min = 0, Max = 2000, Rounding = 0 })
    local RadarY = VisualsBox:AddSlider("bxw_radar_y", { Text = "Position Y", Default = 150, Min = 0, Max = 2000, Rounding = 0 })
    local RadarScale = VisualsBox:AddSlider("bxw_radar_scale", { Text = "Scale (Zoom)", Default = 10, Min = 1, Max = 50, Rounding = 1 })
    local RadarSize = VisualsBox:AddSlider("bxw_radar_size", { Text = "Radar Size", Default = 150, Min = 100, Max = 400, Rounding = 0 })
    LinkToggle(RadarToggle, {RadarX, RadarY, RadarScale, RadarSize})
    
    VisualsBox:AddDivider()
    local ArrowsToggle = VisualsBox:AddToggle("bxw_arrow_enable", { Text = "Off-Screen Arrows", Default = false })
    ArrowsToggle:AddColorPicker("bxw_arrow_color", { Default = Color3.fromRGB(255, 0, 0) })
    local ArrowRadius = VisualsBox:AddSlider("bxw_arrow_radius", { Text = "Arrow Radius", Default = 200, Min = 100, Max = 500 })
    LinkToggle(ArrowsToggle, {ArrowRadius})

    local WhitelistDropdown = ESPSettingBox:AddDropdown("bxw_esp_whitelist", { Text = "Whitelist Player", Values = {}, Default = "", Multi = true, AllowNull = true })
    local NameSizeSlider = ESPSettingBox:AddSlider("bxw_esp_name_size", { Text = "Name Size", Default = 14, Min = 10, Max = 30 })
    
    ESPSettingBox:AddLabel("Chams Settings")
    local ChamsTransSlider = ESPSettingBox:AddSlider("bxw_esp_chams_trans", { Text = "Chams Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
    local ChamsVisibleToggle = ESPSettingBox:AddToggle("bxw_esp_visibleonly", { Text = "Visible Only", Default = false })
    LinkToggle(ChamsToggle, {ChamsTransSlider, ChamsVisibleToggle})

    local CrosshairToggle = ESPSettingBox:AddToggle("bxw_crosshair_enable", { Text = "Crosshair", Default = false })
    CrosshairToggle:AddColorPicker("bxw_crosshair_color", { Default = Color3.fromRGB(255, 255, 255) })
    local CrossSizeSlider = ESPSettingBox:AddSlider("bxw_crosshair_size", { Text = "Crosshair Size", Default = 5, Min = 1, Max = 20 })
    local CrossThickSlider = ESPSettingBox:AddSlider("bxw_crosshair_thick", { Text = "Crosshair Thickness", Default = 1, Min = 1, Max = 5 })
    local CrossGapSlider = ESPSettingBox:AddSlider("bxw_crosshair_gap", { Text = "Crosshair Gap", Default = 0, Min = 0, Max = 10 })
    LinkToggle(CrosshairToggle, {CrossSizeSlider, CrossThickSlider, CrossGapSlider})

    local BulletTracerToggle = TracerBox:AddToggle("bxw_bullet_tracer", { Text = "Enable Bullet Tracers", Default = false })
        :AddColorPicker("bxw_bullet_color", { Default = Color3.fromRGB(255, 0, 0) })
    UserInputService.InputBegan:Connect(function(input, gpe)
        if not gpe and BulletTracerToggle.Value and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            local char, root = getCharacter(), getRootPart()
            if char and root then
                local mp = UserInputService:GetMouseLocation()
                local r = Camera:ViewportPointToRay(mp.X, mp.Y)
                local hit, pos = Workspace:FindPartOnRay(Ray.new(r.Origin, r.Direction * 1000), char)
                local a0, a1 = Instance.new("Attachment", root), Instance.new("Attachment", Instance.new("Part", Workspace))
                a1.Parent.Transparency=1 a1.Parent.CanCollide=false a1.Parent.Anchored=true a1.Parent.Position=pos a1.Parent.Size=Vector3.new(0.1,0.1,0.1)
                local b = Instance.new("Beam", root) b.Attachment0=a0 b.Attachment1=a1 b.Color=ColorSequence.new(Options.bxw_bullet_color.Value) b.Width0=0.1 b.Width1=0.1 b.FaceCamera=true
                Debris:AddItem(b, 1) Debris:AddItem(a0, 1) Debris:AddItem(a1.Parent, 1)
            end
        end
    end)

    local RadarCircle = SafeDrawingNew("Circle") RadarCircle.Thickness = 2 RadarCircle.NumSides = 30 RadarCircle.Filled = true RadarCircle.Transparency = 0.5 RadarCircle.Visible = false RadarCircle.Color = Color3.fromRGB(20,20,20)
    local RadarBorder = SafeDrawingNew("Circle") RadarBorder.Thickness = 2 RadarBorder.NumSides = 30 RadarBorder.Filled = false RadarBorder.Visible = false RadarBorder.Color = Color3.fromRGB(255,255,255)
    local RadarCenter = SafeDrawingNew("Circle") RadarCenter.Thickness = 1 RadarCenter.NumSides = 10 RadarCenter.Filled = true RadarCenter.Visible = false RadarCenter.Radius = 3 RadarCenter.Color = Color3.fromRGB(255,255,255)
    local skeletonJoints = {{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","HumanoidRootPart"},{"LeftUpperArm","UpperTorso"},{"LeftLowerArm","LeftUpperArm"},{"LeftHand","LeftLowerArm"},{"RightUpperArm","UpperTorso"},{"RightLowerArm","RightUpperArm"},{"RightHand","RightLowerArm"},{"LeftUpperLeg","LowerTorso"},{"LeftLowerLeg","LeftUpperLeg"},{"LeftFoot","LeftLowerLeg"},{"RightUpperLeg","LowerTorso"},{"RightLowerLeg","RightUpperLeg"},{"RightFoot","RightLowerLeg"}}

    local function cleanupESP(plr)
        if espDrawings[plr] then
            for _,v in pairs(espDrawings[plr]) do
                if type(v)=="table" then for _,d in pairs(v) do pcall(function() d:Remove() end) end
                elseif typeof(v)=="Instance" then pcall(function() v:Destroy() end)
                else pcall(function() v:Remove() end) end
            end
            espDrawings[plr] = nil
        end
    end
    AddConnection(Players.PlayerRemoving:Connect(cleanupESP))

    AddConnection(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        
        if RadarToggle.Value and DrawingApiAvailable then
            local rx, ry, rsize = RadarX.Value, RadarY.Value, RadarSize.Value
            RadarCircle.Position = Vector2.new(rx, ry) RadarCircle.Radius = rsize RadarCircle.Visible = true
            RadarBorder.Position = Vector2.new(rx, ry) RadarBorder.Radius = rsize RadarBorder.Visible = true
            RadarCenter.Position = Vector2.new(rx, ry) RadarCenter.Visible = true
        else
            RadarCircle.Visible = false RadarBorder.Visible = false RadarCenter.Visible = false
        end

        if not ESPEnabledToggle.Value then 
            for _, plr in ipairs(Players:GetPlayers()) do cleanupESP(plr) end
        else
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local hum = char and char:FindFirstChild("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local head = char and char:FindFirstChild("Head")
                    
                    if char and hum and hum.Health > 0 and root then
                        local skip = false
                        if TeamToggle.Value and plr.Team == LocalPlayer.Team then skip = true end
                        if skip then cleanupESP(plr) else
                            if not espDrawings[plr] then espDrawings[plr] = {} end
                            local data = espDrawings[plr]
                            
                            local vec, onScreen = cam:WorldToViewportPoint(root.Position)
                            local dist = (root.Position - cam.CFrame.Position).Magnitude

                            if RadarToggle.Value and DrawingApiAvailable then
                                if not data.RadarDot then data.RadarDot = SafeDrawingNew("Circle") data.RadarDot.Filled = true data.RadarDot.Radius = 4 end
                                local myRoot = getRootPart()
                                if myRoot then
                                    local rPos = root.Position
                                    local mPos = myRoot.Position
                                    local distVec = rPos - mPos
                                    local distR = distVec.Magnitude
                                    local scale = RadarScale.Value
                                    local look = cam.CFrame.LookVector
                                    local angle = math.atan2(look.Z, look.X) - math.atan2(distVec.Z, distVec.X)
                                    local x = (math.sin(angle) * distR) / scale
                                    local y = (math.cos(angle) * distR) / scale
                                    local rad = math.sqrt(x^2 + y^2)
                                    if rad > RadarSize.Value then x = (x/rad)*RadarSize.Value y = (y/rad)*RadarSize.Value end
                                    data.RadarDot.Visible = true data.RadarDot.Position = Vector2.new(RadarX.Value + x, RadarY.Value + y) data.RadarDot.Color = Color3.fromRGB(255, 0, 0)
                                end
                            else if data.RadarDot then data.RadarDot.Visible = false end end
                            
                            if onScreen then
                                local scale = 1000 / dist
                                local width, height = 3 * scale, 4.5 * scale
                                local x, y = vec.X - width/2, vec.Y - height/2

                                if BoxToggle.Value and DrawingApiAvailable then
                                    if BoxStyleDropdown.Value == "Box" then
                                        if not data.Box then data.Box = SafeDrawingNew("Square") data.Box.Thickness = 1 data.Box.Filled = false end
                                        data.Box.Visible=true data.Box.Size=Vector2.new(width, height) data.Box.Position=Vector2.new(x, y) data.Box.Color=Options.bxw_esp_box_color.Value
                                        if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                                    else
                                        if not data.Corners then data.Corners = {} for i=1,8 do data.Corners[i] = SafeDrawingNew("Line") data.Corners[i].Thickness = 1 end end
                                        if data.Box then data.Box.Visible=false end
                                        local cw, ch = width*0.25, height*0.25
                                        local function dLine(i, f, t) data.Corners[i].Visible=true data.Corners[i].Color=Options.bxw_esp_box_color.Value data.Corners[i].From=f data.Corners[i].To=t end
                                        dLine(1, Vector2.new(x,y), Vector2.new(x+cw,y)) dLine(2, Vector2.new(x,y), Vector2.new(x,y+ch))
                                        dLine(3, Vector2.new(x+width,y), Vector2.new(x+width-cw,y)) dLine(4, Vector2.new(x+width,y), Vector2.new(x+width,y+ch))
                                        dLine(5, Vector2.new(x,y+height), Vector2.new(x+cw,y+height)) dLine(6, Vector2.new(x,y+height), Vector2.new(x,y+height-ch))
                                        dLine(7, Vector2.new(x+width,y+height), Vector2.new(x+width-cw,y+height)) dLine(8, Vector2.new(x+width,y+height), Vector2.new(x+width,y+height-ch))
                                    end
                                else
                                    if data.Box then data.Box.Visible=false end
                                    if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                                end

                                if NameToggle.Value and DrawingApiAvailable then
                                    if not data.Name then data.Name = SafeDrawingNew("Text") data.Name.Center=true data.Name.Outline=true end
                                    data.Name.Visible=true data.Name.Text=plr.DisplayName data.Name.Size=NameSizeSlider.Value data.Name.Color=Options.bxw_esp_name_color.Value data.Name.Position=Vector2.new(vec.X, y - 16)
                                else if data.Name then data.Name.Visible=false end end

                                if HealthToggle.Value and DrawingApiAvailable then
                                    if not data.HealthBar then data.HealthBar = SafeDrawingNew("Line") data.HealthBar.Thickness = 2 end
                                    if not data.HealthOutline then data.HealthOutline = SafeDrawingNew("Line") data.HealthOutline.Thickness = 4 end
                                    local hpPercent = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                                    local barHeight = height * hpPercent
                                    data.HealthOutline.Visible=true data.HealthOutline.Color=Color3.new(0,0,0) data.HealthOutline.From=Vector2.new(x-6, y) data.HealthOutline.To=Vector2.new(x-6, y+height)
                                    data.HealthBar.Visible=true data.HealthBar.Color=Options.bxw_esp_health_color.Value:Lerp(Color3.new(1,0,0), 1-hpPercent) data.HealthBar.From=Vector2.new(x-6, y+height) data.HealthBar.To=Vector2.new(x-6, y+height-barHeight)
                                else if data.HealthBar then data.HealthBar.Visible=false data.HealthOutline.Visible=false end end

                                if ToolEspToggle.Value and DrawingApiAvailable then
                                    if not data.Tool then data.Tool = SafeDrawingNew("Text") data.Tool.Center=true data.Tool.Outline=true end
                                    local tool = char:FindFirstChildOfClass("Tool")
                                    data.Tool.Visible=true data.Tool.Text=tool and tool.Name or "[None]" data.Tool.Size=12 data.Tool.Color=Options.bxw_esp_tool_color.Value data.Tool.Position=Vector2.new(vec.X, y+height+2)
                                else if data.Tool then data.Tool.Visible=false end end

                                if InfoToggle.Value and DrawingApiAvailable then
                                    if not data.Info then data.Info = SafeDrawingNew("Text") data.Info.Center=true data.Info.Outline=true end
                                    local teamName = plr.Team and plr.Team.Name or "Neutral"
                                    data.Info.Visible=true data.Info.Text=string.format("HP:%.0f | %s", hum.Health, teamName) data.Info.Size=12 data.Info.Color=Options.bxw_esp_info_color.Value data.Info.Position=Vector2.new(vec.X, y+height+14)
                                else if data.Info then data.Info.Visible=false end end
                                
                                if TracerToggle.Value and DrawingApiAvailable then
                                    if not data.Tracer then data.Tracer = SafeDrawingNew("Line") data.Tracer.Thickness = 1 end
                                    data.Tracer.Visible=true data.Tracer.Color=Options.bxw_esp_tracer_color.Value data.Tracer.From=Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y) data.Tracer.To=Vector2.new(vec.X, vec.Y)
                                else if data.Tracer then data.Tracer.Visible=false end end

                                if ViewTracerToggle.Value and head and DrawingApiAvailable then
                                    if not data.ViewTracer then data.ViewTracer = SafeDrawingNew("Line") data.ViewTracer.Thickness = 1 end
                                    local lookEnd = head.Position + (head.CFrame.LookVector * 10)
                                    local endPos, endOnScreen = cam:WorldToViewportPoint(lookEnd)
                                    local headPos, headOnScreen = cam:WorldToViewportPoint(head.Position)
                                    if headOnScreen then
                                        data.ViewTracer.Visible=true data.ViewTracer.Color=Options.bxw_view_tracer_color.Value data.ViewTracer.From=Vector2.new(headPos.X, headPos.Y) data.ViewTracer.To=Vector2.new(endPos.X, endPos.Y)
                                    else data.ViewTracer.Visible=false end
                                else if data.ViewTracer then data.ViewTracer.Visible=false end end

                                if SkeletonToggle.Value and DrawingApiAvailable then
                                    if not data.Skeleton then data.Skeleton = {} end
                                    local skCol = Options.bxw_esp_skeleton_color.Value
                                    for i, joint in ipairs(skeletonJoints) do
                                        local p1, p2 = char:FindFirstChild(joint[1]), char:FindFirstChild(joint[2])
                                        local ln = data.Skeleton[i]
                                        if not ln then ln = SafeDrawingNew("Line") ln.Thickness = 1 data.Skeleton[i] = ln end
                                        if p1 and p2 then
                                            local v1, on1 = cam:WorldToViewportPoint(p1.Position)
                                            local v2, on2 = cam:WorldToViewportPoint(p2.Position)
                                            if on1 or on2 then ln.Visible=true ln.Color=skCol ln.From=Vector2.new(v1.X, v1.Y) ln.To=Vector2.new(v2.X, v2.Y) else ln.Visible=false end
                                        else ln.Visible=false end
                                    end
                                else if data.Skeleton then for _,l in pairs(data.Skeleton) do l.Visible=false end end end

                                if HeadDotToggle.Value and head and DrawingApiAvailable then
                                    local hv, hon = cam:WorldToViewportPoint(head.Position)
                                    if hon then
                                        if not data.HeadDot then data.HeadDot = SafeDrawingNew("Circle") data.HeadDot.Filled=true end
                                        data.HeadDot.Visible=true data.HeadDot.Radius=3 data.HeadDot.Color=Options.bxw_esp_headdot_color.Value data.HeadDot.Position=Vector2.new(hv.X, hv.Y)
                                    else if data.HeadDot then data.HeadDot.Visible=false end end
                                else if data.HeadDot then data.HeadDot.Visible=false end end

                                if ChamsToggle.Value then
                                    if not data.Highlight then data.Highlight = Instance.new("Highlight", char) end
                                    data.Highlight.Enabled=true data.Highlight.FillColor=Options.bxw_esp_chams_color.Value data.Highlight.OutlineColor=data.Highlight.FillColor data.Highlight.FillTransparency=ChamsTransSlider.Value data.Highlight.DepthMode=ChamsVisibleToggle.Value and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                                else if data.Highlight then data.Highlight.Enabled=false end end
                                
                                if data.Arrow then data.Arrow.Visible=false end

                            else 
                                if data.Box then data.Box.Visible=false end
                                if data.Corners then for _,l in pairs(data.Corners) do l.Visible=false end end
                                if data.Name then data.Name.Visible=false end
                                if data.HealthBar then data.HealthBar.Visible=false data.HealthOutline.Visible=false end
                                if data.Tool then data.Tool.Visible=false end
                                if data.Info then data.Info.Visible=false end
                                if data.Tracer then data.Tracer.Visible=false end
                                if data.ViewTracer then data.ViewTracer.Visible=false end
                                if data.Skeleton then for _,l in pairs(data.Skeleton) do l.Visible=false end end
                                if data.HeadDot then data.HeadDot.Visible=false end
                                
                                if ArrowsToggle.Value and DrawingApiAvailable then
                                    if not data.Arrow then data.Arrow = SafeDrawingNew("Triangle") data.Arrow.Filled = true end
                                    local center = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                                    local rel = cam.CFrame:PointToObjectSpace(root.Position)
                                    local angle = math.atan2(rel.Y, rel.X)
                                    if rel.Z > 0 then angle = math.atan2(-rel.Y, -rel.X) end
                                    local radius = ArrowRadius.Value
                                    local arrowPos = center + Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
                                    local size = 15
                                    local p1 = arrowPos + Vector2.new(math.cos(angle) * size, math.sin(angle) * size)
                                    local p2 = arrowPos + Vector2.new(math.cos(angle + 2.5) * (size/2), math.sin(angle + 2.5) * (size/2))
                                    local p3 = arrowPos + Vector2.new(math.cos(angle - 2.5) * (size/2), math.sin(angle - 2.5) * (size/2))
                                    data.Arrow.Visible=true data.Arrow.PointA=p1 data.Arrow.PointB=p2 data.Arrow.PointC=p3 data.Arrow.Color=Options.bxw_arrow_color.Value
                                else if data.Arrow then data.Arrow.Visible=false end end
                            end
                        end
                    else cleanupESP(plr) end
                end
            end
        end
        
        if not crosshairLines then crosshairLines = {h=SafeDrawingNew("Line"),v=SafeDrawingNew("Line")} end
        if CrosshairToggle.Value and DrawingApiAvailable then
            local cx, cy = cam.ViewportSize.X/2, cam.ViewportSize.Y/2
            local sz, th = CrossSizeSlider.Value, CrossThickSlider.Value
            local gap = CrossGapSlider.Value
            local col = Options.bxw_crosshair_color.Value
            crosshairLines.h.Visible=true crosshairLines.h.From=Vector2.new(cx-sz-gap,cy) crosshairLines.h.To=Vector2.new(cx+sz+gap,cy) crosshairLines.h.Thickness=th crosshairLines.h.Color=col
            crosshairLines.v.Visible=true crosshairLines.v.From=Vector2.new(cx,cy-sz-gap) crosshairLines.v.To=Vector2.new(cx,cy+sz+gap) crosshairLines.v.Thickness=th crosshairLines.v.Color=col
        else crosshairLines.h.Visible=false crosshairLines.v.Visible=false end
    end))

    ------------------------------------------------
    -- TAB 4: Combat
    ------------------------------------------------
    local CombatTab = Tabs.Combat
    local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
    local HitboxSettings = CombatTab:AddRightGroupbox("Hitbox Expander", "expand")
    local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")
    local AntiAimBox = CombatTab:AddRightGroupbox("Anti-Aim / Spinbot", "shield")

    local HitboxToggle = HitboxSettings:AddToggle("bxw_hitbox_enable", { Text = "Enable Hitbox", Default = false })
    local HitboxSize = HitboxSettings:AddSlider("bxw_hitbox_size", { Text = "Size", Default = 2, Min = 2, Max = 30, Rounding = 1 })
    local HitboxTrans = HitboxSettings:AddSlider("bxw_hitbox_trans", { Text = "Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 1 })
    local HitboxPart = HitboxSettings:AddDropdown("bxw_hitbox_part", { Text = "Target Part", Values = {"Head", "HumanoidRootPart"}, Default = "Head" })
    local HitboxTeamCheck = HitboxSettings:AddToggle("bxw_hitbox_team", { Text = "Team Check", Default = true })
    LinkToggle(HitboxToggle, {HitboxSize, HitboxTrans, HitboxPart, HitboxTeamCheck})

    AddConnection(RunService.Heartbeat:Connect(function()
        if HitboxToggle.Value then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local hum, root = plr.Character:FindFirstChild("Humanoid"), plr.Character:FindFirstChild("HumanoidRootPart")
                    if hum and hum.Health > 0 and root then
                        if not HitboxTeamCheck.Value or plr.Team ~= LocalPlayer.Team then
                            local part = plr.Character:FindFirstChild(HitboxPart.Value)
                            if part then
                                part.Size = Vector3.new(HitboxSize.Value, HitboxSize.Value, HitboxSize.Value)
                                part.Transparency = HitboxTrans.Value
                                part.CanCollide = false
                            end
                        end
                    end
                end
            end
        end
    end))

    local AimbotToggle = AimBox:AddToggle("bxw_aimbot_enable", { Text = "Enable Aimbot", Default = false })
    local SilentToggle = AimBox:AddToggle("bxw_silent_enable", { Text = "Silent Aim (Visual)", Default = false }) 
    local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", { Text = "Aim Part", Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest", "Random", "Custom" }, Default = "Head" })
    local AimActivationDropdown = AimBox:AddDropdown("bxw_aim_activation", { Text = "Aim Activation", Values = { "Hold Right Click", "Always On" }, Default = "Hold Right Click" })
    local TargetModeDropdown = AimBox:AddDropdown("bxw_aim_targetmode", { Text = "Target Mode", Values = { "Closest To Crosshair", "Closest Distance", "Lowest Health" }, Default = "Closest To Crosshair" })
    local UseSmartAimLogic = AimBox:AddToggle("bxw_aim_smart_logic", { Text = "Smart Aim Logic", Default = true })
    
    UseSmartAimLogic:OnChanged(function() LinkToggle(UseSmartAimLogic, {TargetModeDropdown}) end)
    LinkToggle(UseSmartAimLogic, {TargetModeDropdown})

    local FOVSlider = AimBox:AddSlider("bxw_aim_fov", { Text = "Aim FOV", Default = 10, Min = 1, Max = 50 })
    local ShowFovToggle = AimBox:AddToggle("bxw_aim_showfov", { Text = "Show FOV Circle", Default = false })
    ShowFovToggle:AddColorPicker("bxw_aim_fovcolor", { Default = Color3.fromRGB(255, 255, 255) })
    local FOVStyleDropdown = AimBox:AddDropdown("bxw_fov_style", { Text = "FOV Style", Values = { "Circle", "Square" }, Default = "Circle" })
    local RainbowToggle = AimBox:AddToggle("bxw_aim_rainbow", { Text = "Rainbow FOV", Default = false })
    local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", { Text = "Smoothness", Default = 0.5, Min = 0.01, Max = 1 }) 
    local AimTeamCheck = AimBox:AddToggle("bxw_aim_teamcheck", { Text = "Team Check", Default = true })
    
    LinkToggle(AimbotToggle, {
        SilentToggle, AimPartDropdown, AimActivationDropdown, TargetModeDropdown, UseSmartAimLogic,
        FOVSlider, ShowFovToggle, FOVStyleDropdown, RainbowToggle, SmoothSlider, AimTeamCheck
    })

    local HeadChance = ExtraBox:AddSlider("bxw_hit_head_chance", { Text = "Head Chance", Default = 100, Min = 0, Max = 100 })
    local TorsoChance = ExtraBox:AddSlider("bxw_hit_torso_chance", { Text = "Torso Chance", Default = 100, Min = 0, Max = 100 })
    local LimbChance = ExtraBox:AddSlider("bxw_hit_limb_chance", { Text = "Limbs Chance", Default = 100, Min = 0, Max = 100 })

    local TriggerbotToggle = ExtraBox:AddToggle("bxw_triggerbot", { Text = "Triggerbot", Default = false })
    local TriggerMode = ExtraBox:AddDropdown("bxw_trigger_method", { Text = "Trigger Mode", Values = {"Always On", "Hold Key"}, Default = "Always On" })
    LinkToggle(TriggerbotToggle, {TriggerMode})

    local TargetInfoToggle = AimBox:AddToggle("bxw_target_info", { Text = "Show Target Info Panel", Default = true })
    local TargetInfoDraw = SafeDrawingNew("Text") TargetInfoDraw.Visible=false TargetInfoDraw.Size=18 TargetInfoDraw.Center=true TargetInfoDraw.Outline=true

    local AntiAimToggle = AntiAimBox:AddToggle("bxw_antiaim", { Text = "Enable Anti-Aim", Default = false })
    local AntiAimType = AntiAimBox:AddDropdown("bxw_antiaim_type", { Text = "Type", Values = { "Spin", "Jitter", "Random" }, Default = "Spin" })
    local SpinSpeed = AntiAimBox:AddSlider("bxw_spin_speed", { Text = "Spin Speed", Default = 10, Min = 1, Max = 50 })
    LinkToggle(AntiAimToggle, {AntiAimType, SpinSpeed})

    AddConnection(RunService.RenderStepped:Connect(function(dt)
        if AntiAimToggle.Value then
            local r = getRootPart()
            if r then
                local angle = 0
                if AntiAimType.Value == "Spin" then angle = SpinSpeed.Value * dt * 10
                elseif AntiAimType.Value == "Jitter" then angle = math.random(-SpinSpeed.Value, SpinSpeed.Value) * dt
                elseif AntiAimType.Value == "Random" then angle = math.random(0, 360) end
                r.CFrame = r.CFrame * CFrame.Angles(0, angle, 0)
            end
        end
    end))

    AimbotFOVCircle = SafeDrawingNew("Circle") AimbotFOVCircle.Thickness = 1 AimbotFOVCircle.Filled = false
    AimbotFOVSquare = SafeDrawingNew("Square") AimbotFOVSquare.Thickness = 1 AimbotFOVSquare.Filled = false
    local rainbowHue = 0

    RunService:BindToRenderStep("BxBAimbot", Enum.RenderPriority.Camera.Value + 1, function()
        local ms = UserInputService:GetMouseLocation()
        
        if ShowFovToggle.Value and AimbotToggle.Value and DrawingApiAvailable then
            local radius = FOVSlider.Value * 15
            local color = Options.bxw_aim_fovcolor.Value
            if RainbowToggle.Value then
                rainbowHue = (rainbowHue + 0.01) % 1
                color = Color3.fromHSV(rainbowHue, 1, 1)
            end
            if FOVStyleDropdown.Value == "Circle" then
                AimbotFOVCircle.Visible=true AimbotFOVSquare.Visible=false AimbotFOVCircle.Radius=radius AimbotFOVCircle.Position=ms AimbotFOVCircle.Color=color
            else
                AimbotFOVCircle.Visible=false AimbotFOVSquare.Visible=true AimbotFOVSquare.Size=Vector2.new(radius*2, radius*2) AimbotFOVSquare.Position=ms-Vector2.new(radius,radius) AimbotFOVSquare.Color=color
            end
        else AimbotFOVCircle.Visible=false AimbotFOVSquare.Visible=false end
        TargetInfoDraw.Visible = false

        if AimbotToggle.Value then
            local active = (AimActivationDropdown.Value == "Always On") or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            if not active then CurrentTarget = nil end

            if not CurrentTarget or not CurrentTarget.Parent or not CurrentTarget.Parent:FindFirstChild("Humanoid") or CurrentTarget.Parent.Humanoid.Health <= 0 then
                local best, bestScore = nil, math.huge
                for _,p in ipairs(Players:GetPlayers()) do
                    if p~=LocalPlayer and p.Character then
                        local hum, head = p.Character:FindFirstChild("Humanoid"), p.Character:FindFirstChild("Head")
                        if hum and head and hum.Health > 0 and (not AimTeamCheck.Value or p.Team ~= LocalPlayer.Team) then
                            local partName = AimPartDropdown.Value
                            if partName == "Custom" then
                                local wHead, wTorso = HeadChance.Value, TorsoChance.Value
                                local total = wHead + wTorso + LimbChance.Value
                                if total > 0 then
                                    local r = math.random(1, total)
                                    if r <= wHead then partName = "Head"
                                    elseif r <= wHead+wTorso then partName = "HumanoidRootPart"
                                    else partName = "Right Arm" end
                                end
                            elseif partName == "Random" then partName = (math.random()>0.5 and "Head" or "HumanoidRootPart")
                            elseif partName == "Closest" then partName = "Head" end
                            local part = p.Character:FindFirstChild(partName) or head
                            
                            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                            if onScreen then
                                local dist = (Vector2.new(pos.X, pos.Y) - ms).Magnitude
                                local fovR = (FOVStyleDropdown.Value=="Circle" and AimbotFOVCircle.Radius or AimbotFOVSquare.Size.X/2) or 300
                                if dist <= fovR and dist < bestScore then bestScore = dist best = part end
                            end
                        end
                    end
                end
                CurrentTarget = best
            end

            if CurrentTarget and active then
                local cam = Workspace.CurrentCamera
                cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, CurrentTarget.Position), SmoothSlider.Value)
                
                if TargetInfoToggle.Value and DrawingApiAvailable then
                    TargetInfoDraw.Visible=true TargetInfoDraw.Position=ms+Vector2.new(0,40)
                    local tChar, tHum = CurrentTarget.Parent, CurrentTarget.Parent:FindFirstChild("Humanoid")
                    local tTool = tChar:FindFirstChildOfClass("Tool")
                    TargetInfoDraw.Text = string.format("Target: %s\nHP: %.0f | Weapon: %s", tChar.Name, tHum.Health, (tTool and tTool.Name or "None"))
                end
                
                if TriggerbotToggle.Value then
                    local pos = Camera:WorldToViewportPoint(CurrentTarget.Position)
                    if (Vector2.new(pos.X, pos.Y) - ms).Magnitude < 20 then
                        local tActive = true
                        if TriggerMode.Value == "Hold Key" and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then tActive = false end
                        if tActive then
                            task.spawn(function() task.wait(0.1) ClickMouse() task.wait(0.1) end)
                        end
                    end
                end
            end
        end
    end)

    ------------------------------------------------
    -- TAB 5: Misc
    ------------------------------------------------
    local MiscTab = Tabs.Misc
    
    local GfxBox = MiscTab:AddLeftGroupbox("Graphics Manager", "monitor")
    local RtxToggle = GfxBox:AddToggle("bxw_gfx_rtx", { Text = "Beautiful Mode (RTX)", Default = false })
    RtxToggle:OnChanged(function(v)
        if v then
            local bloom = Instance.new("BloomEffect", Lighting) bloom.Name = "BxBBloom" bloom.Intensity = 0.5 bloom.Size = 24
            local sun = Instance.new("SunRaysEffect", Lighting) sun.Name = "BxBSun"
            local color = Instance.new("ColorCorrectionEffect", Lighting) color.Name = "BxBColor" color.Saturation = 0.2 color.Contrast = 0.1
            Lighting.GlobalShadows = true Lighting.Technology = Enum.Technology.Future
        else
            for _, e in ipairs(Lighting:GetChildren()) do if e.Name:find("BxB") then e:Destroy() end end
        end
    end)

    GfxBox:AddDivider()
    local NoTexToggle = GfxBox:AddToggle("bxw_gfx_notex", { Text = "Remove Textures", Default = false })
    NoTexToggle:OnChanged(function(v) for _, obj in pairs(Workspace:GetDescendants()) do if obj:IsA("Texture") or obj:IsA("Decal") then obj.Transparency = v and 1 or 0 end end end)
    local NoShadowToggle = GfxBox:AddToggle("bxw_gfx_noshadow", { Text = "Remove Shadows", Default = false })
    NoShadowToggle:OnChanged(function(v) Lighting.GlobalShadows = not v for _, obj in pairs(Workspace:GetDescendants()) do if obj:IsA("BasePart") then obj.CastShadow = not v end end end)
    local PlasticToggle = GfxBox:AddToggle("bxw_gfx_plastic", { Text = "Smooth Plastic Mode", Default = false })
    PlasticToggle:OnChanged(function(v) if v then for _, obj in pairs(Workspace:GetDescendants()) do if obj:IsA("BasePart") then obj.Material = Enum.Material.SmoothPlastic end end end end)

    local FunBox = safeAddRightGroupbox(MiscTab, "Fun & Tools", "smile")
    local InstaPromptToggle = FunBox:AddToggle("bxw_instaprompt", { Text = "Instant Interact (E)", Default = false })
    AddConnection(ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt) if InstaPromptToggle.Value then prompt.HoldDuration = 0 end end))
    
    local ClickerToggle = FunBox:AddToggle("bxw_autoclicker", { Text = "Auto Clicker", Default = false })
    task.spawn(function() while true do if ClickerToggle.Value then ClickMouse() end task.wait(0.1) end end)
    
    FunBox:AddButton("BTools (Client)", function()
        local bp = LocalPlayer.Backpack for _,v in ipairs({Enum.BinType.Clone, Enum.BinType.Hammer, Enum.BinType.Grab}) do local b = Instance.new("HopperBin", bp) b.BinType = v end Library:Notify("BTools added", 2)
    end)
    FunBox:AddButton("Teleport Tool", function()
        local t = Instance.new("Tool", LocalPlayer.Backpack) t.Name = "TeleportTool" t.RequiresHandle = false
        t.Activated:Connect(function() local m = LocalPlayer:GetMouse() if m.Hit then getRootPart().CFrame = CFrame.new(m.Hit.Position + Vector3.new(0,3,0)) end end) Library:Notify("TP Tool added", 2)
    end)
    FunBox:AddButton("F3X (Loadstring)", function() 
        pcall(function() loadstring(game:GetObjects("rbxassetid://6695644299")[1].Source)() end) Library:Notify("F3X Loaded", 2) 
    end)
    
    local FlingToggle = FunBox:AddToggle("bxw_fling", { Text = "Fling Player (Spin)", Default = false })
    AddConnection(RunService.Heartbeat:Connect(function()
        if FlingToggle.Value then
            local root = getRootPart()
            if root then
                local bav = root:FindFirstChild("FlingAngVel") or Instance.new("BodyAngularVelocity", root)
                bav.Name = "FlingAngVel" bav.AngularVelocity = Vector3.new(0, 10000, 0) bav.MaxTorque = Vector3.new(0, math.huge, 0) bav.P = 10000
            end
        else
            local root = getRootPart() if root then local b = root:FindFirstChild("FlingAngVel") if b then b:Destroy() end end
        end
    end))
    
    local AntiFlingToggle = FunBox:AddToggle("bxw_antifling", { Text = "Anti Fling", Default = false })
    AddConnection(RunService.Stepped:Connect(function()
        if AntiFlingToggle.Value then
            local r = getRootPart()
            if r then
                if r.AssemblyLinearVelocity.Magnitude > 100 then r.AssemblyLinearVelocity = Vector3.zero end
                if r.AssemblyAngularVelocity.Magnitude > 100 then r.AssemblyAngularVelocity = Vector3.zero end
            end
        end
    end))

    local ServerBox = safeAddRightGroupbox(MiscTab, "Server", "server")
    ServerBox:AddButton("Rejoin Server", function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
    local HopDropdown = ServerBox:AddDropdown("bxw_hop_mode", { Text = "Hop Mode", Values = { "Normal", "Low Users", "High Users" }, Default = "Normal" })
    ServerBox:AddButton("Server Hop", function()
        pcall(function()
            local mode = HopDropdown.Value
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
            local data = HttpService:JSONDecode(SafeHttpGet(url))
            if data and data.data then
                local servers = {}
                for _, s in ipairs(data.data) do if s.playing < s.maxPlayers and s.id ~= game.JobId then table.insert(servers, s) end end
                if #servers > 0 then
                    if mode == "Low Users" then table.sort(servers, function(a,b) return a.playing < b.playing end)
                    elseif mode == "High Users" then table.sort(servers, function(a,b) return a.playing > b.playing end)
                    else for i = #servers, 2, -1 do local j = math.random(i) servers[i], servers[j] = servers[j], servers[i] end end
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LocalPlayer)
                else Library:Notify("No server found", 3) end
            end
        end)
    end)
    local JobIdInput = ServerBox:AddInput("bxw_jobid", { Text = "Join JobId", Default = "", Placeholder = "JobId here..." })
    ServerBox:AddButton("Join JobId", function() local id = JobIdInput.Value if id and id ~= "" then TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer) end end)

    local EnvBox = safeAddRightGroupbox(MiscTab, "Environment", "sun")
    EnvBox:AddSlider("bxw_gravity", { Text = "Gravity", Default = Workspace.Gravity, Min = 0, Max = 300, Callback = function(v) Workspace.Gravity = v end })
    EnvBox:AddToggle("bxw_nofog", { Text = "No Fog", Default = false, Callback = function(v) if v then Lighting.FogEnd = 1e9 else Lighting.FogEnd = 1000 end end })
    EnvBox:AddSlider("bxw_brightness", { Text = "Brightness", Default = Lighting.Brightness, Min = 0, Max = 10, Callback = function(v) Lighting.Brightness = v end })
    EnvBox:AddLabel("Ambient"):AddColorPicker("bxw_ambient", { Default = Lighting.Ambient, Callback = function(v) Lighting.Ambient = v end })
    EnvBox:AddSlider("bxw_time", { Text = "Time", Default = 14, Min = 0, Max = 24, Callback = function(v) Lighting.ClockTime = v end })

    local GameToolBox = MiscTab:AddLeftGroupbox("Game Tool", "tool")
    local AntiRejoinToggle = GameToolBox:AddToggle("bxw_antirejoin", { Text = "Auto Rejoin on Kick", Default = false })
    local AntiAfkToggle = GameToolBox:AddToggle("bxw_anti_afk", { Text = "Anti-AFK", Default = true })
    
    local errorGui = CoreGui:FindFirstChild("RobloxPromptGui")
    if errorGui then errorGui.DescendantAdded:Connect(function(v) if AntiRejoinToggle.Value and v.Name == "ErrorTitle" then TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end end) end
    LocalPlayer.Idled:Connect(function() if AntiAfkToggle.Value then VirtualUser:Button2Down(Vector2.new(0,0)) VirtualUser:Button2Up(Vector2.new(0,0)) end end)

    GameToolBox:AddDivider()
    GameToolBox:AddLabel("Admin Detector")
    local AdminKickToggle = GameToolBox:AddToggle("bxw_admin_kick", { Text = "Auto Kick if Admin", Default = false })
    local AdminDetectToggle = GameToolBox:AddToggle("bxw_admin_detect", { Text = "Enable Detection", Default = false })
    task.spawn(function()
        while true do
            task.wait(3)
            if AdminDetectToggle.Value then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer then
                        local detected = false
                        if game.CreatorType == Enum.CreatorType.User and p.UserId == game.CreatorId then detected = true end
                        if not detected and game.CreatorType == Enum.CreatorType.Group then
                            local s, rank = pcall(function() return p:GetRankInGroup(game.CreatorId) end)
                            if s and rank and rank >= 254 then detected = true end
                        end
                        if detected then
                            Library:Notify("⚠️ ADMIN: " .. p.Name, 5)
                            if AdminKickToggle.Value then LocalPlayer:Kick("Admin Detected") end
                        end
                    end
                end
            end
        end
    end)

    ------------------------------------------------
    -- TAB 6: Settings
    ------------------------------------------------
    local SettingsTab = Tabs.Settings
    local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")
    
    MenuGroup:AddToggle("bxw_force_notify", { Text = "Force Notify Actions", Default = false, Callback = function(v) getgenv().DiabloForceNotify = v end })
    MenuGroup:AddButton("Unload UI", function() Library:Unload() end)
    MenuGroup:AddButton("Reload UI", function() Library:Unload() warn("UI Reloaded") end)
    
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:BuildConfigSection(SettingsTab)
    ThemeManager:ApplyToTab(SettingsTab)
    SaveManager:LoadAutoloadConfig()

    Library:OnUnload(function()
        RunService:UnbindFromRenderStep("BxBAimbot")
        for _,c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        for _,p in pairs(espDrawings) do
            for _,o in pairs(p) do
                if type(o)=="table" then for _,i in pairs(o) do pcall(function() i:Remove() end) end
                elseif typeof(o)=="Instance" then pcall(function() o:Destroy() end)
                else pcall(function() o:Remove() end) end
            end
        end
        if AimbotFOVCircle then AimbotFOVCircle:Remove() end
        if AimbotFOVSquare then AimbotFOVSquare:Remove() end
        if TargetInfoDraw then TargetInfoDraw:Remove() end
        if crosshairLines then crosshairLines.h:Remove() crosshairLines.v:Remove() end
        if RadarCircle then RadarCircle:Remove() RadarBorder:Remove() RadarCenter:Remove() end
    end)
end

return function(Exec, keydata, authToken)
    local ok, err = pcall(MainHub, Exec, keydata, authToken)
    if not ok then warn("[MainHub] Error:", err) end
end
