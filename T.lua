--====================================================
-- 0. Services
--====================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")
local LocalPlayer        = Players.LocalPlayer
local Workspace          = game:GetService("Workspace")
local Mouse              = LocalPlayer:GetMouse()

--====================================================
-- 1. Utility Functions & Variables
--====================================================

-- Helper: get current character if loaded
local function getCharacter()
    -- Some games store character differently; use Player.Character
    return LocalPlayer.Character
end

-- Helper: get root part (HumanoidRootPart or Torso/UpperTorso)
local function getRootPart()
    local char = getCharacter()
    if not char then return end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

-- Team name normalizer (for future use if needed)
local function NormalizeTeamName(team)
    return team and tostring(team) or ""
end

-- Normalize role string; map any unrecognized to 'free'
local function NormalizeRole(role)
    if not role then return "free" end
    role = tostring(role):lower()
    local validRoles = { free = true, user = true, premium = true, vip = true, staff = true, owner = true }
    if validRoles[role] then
        return role
    end
    return "free"
end

-- Label maker for role strings
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
-- 2. Key System configuration
--====================================================

-- (Configure to match your game or system)
local KeySettings = {
    MaskSize = 4,       -- how many characters to show before masking rest
    MaskSymbol = "*",   -- symbol to use for mask
}

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
    -- 4.2 สร้าง Window/Tab หลัก
    ---------------------------------------------
    local Library = loadstring(Exec:HttpGet("https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/main/UI_Library/WavesAndBacon.lua"))()
    if not Library or type(Library.CreateWindow) ~= "function" then
        warn("[MainHub] UI library failed to load")
        return
    end
    local Window = Library:CreateWindow("BxB.ware", "v1.0.0", 12612059748)

    local Tabs = {
        Info   = Window:AddTab({
            Name        = "Info [Key / Game]",
            Icon        = "info-circle",
            Description = "Key status and game info",
        }),
        Combat = Window:AddTab({
            Name        = "Combat & Aimbot",
            Icon        = "target",
            Description = "Aimbot / target selection",
        }),
        ESP    = Window:AddTab({
            Name        = "ESP & Visuals",
            Icon        = "eye",
            Description = "Player ESP / Visual settings",
        }),
        Player = Window:AddTab({
            Name        = "Player",
            Icon        = "user",
            Description = "Player settings",
        }),
        Misc   = Window:AddTab({
            Name        = "Misc & System",
            Icon        = "cpu",
            Description = "Miscellaneous and system",
        }),
    }

    -- Helper function to safely add a right-hand groupbox. Some versions of the
    -- underlying UI library may not expose AddRightGroupbox directly on a
    -- Tab. In that case, fall back to AddGroupbox with Side = 2. This helper
    -- accepts a tab object, a title and icon name, and returns the created
    -- groupbox. If neither method is available, it will return nil.
    local function safeAddRightGroupbox(tab, name, icon)
        if tab and typeof(tab) == "table" then
            if type(tab.AddRightGroupbox) == "function" then
                -- Preferred API exists
                return tab:AddRightGroupbox(name, icon)
            elseif type(tab.AddGroupbox) == "function" then
                -- Fall back to generic AddGroupbox with Side flag
                return tab:AddGroupbox({ Side = 2, Name = name, IconName = icon })
            end
        end
        -- If we cannot add a right groupbox, return nil
        return nil
    end

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

    -- Attempt to fetch additional key details from the remote key server JSON.
    -- The file is stored in this repository at "Key_System/data.json" on the main branch.  If found, it
    -- contains a list of keys with role, status, timestamp, expire, note and hwid_hash.  We
    -- match the current key and override or supplement our local values.  If the fetch or
    -- parse fails, the local values remain unchanged.
    local HttpService = game:GetService("HttpService")
    local remoteKeyData = nil
    -- storage for remote-created date and expire display
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
                    -- compare by full key string
                    if tostring(entry.key) == rawKey or tostring(entry.key) == tostring(keydata.key) then
                        remoteKeyData = entry
                        break
                    end
                end
            end
        end
    end)

    if remoteKeyData then
        -- Override display variables with remote values when available
        if remoteKeyData.role then
            roleHtml = GetRoleLabel(remoteKeyData.role)
        end
        if remoteKeyData.status then
            statusText = tostring(remoteKeyData.status)
        end
        if remoteKeyData.note and remoteKeyData.note ~= "" then
            noteText = tostring(remoteKeyData.note)
        end
        -- use remote hwid hash if present
        if remoteKeyData.hwid_hash then
            keydata.hwid_hash = remoteKeyData.hwid_hash
        end
        -- capture remote created and expire strings if present
        if remoteKeyData.timestamp then
            remoteCreatedAtStr = tostring(remoteKeyData.timestamp)
        end
        if remoteKeyData.expire and remoteKeyData.expire ~= nil then
            remoteExpireStr = tostring(remoteKeyData.expire)
        end
    end

    -- Determine created date: prefer remote timestamp string, then formatted local timestamp, then unknown
    local createdAtText
    if remoteCreatedAtStr then
        createdAtText = remoteCreatedAtStr
    elseif keydata.timestamp and keydata.timestamp > 0 then
        createdAtText = formatUnixTime(keydata.timestamp)
    elseif keydata.created_at then
        createdAtText = tostring(keydata.created_at)
    else
        createdAtText = "Unknown"
    end
    local expireTs      = tonumber(keydata.expire) or 0

    safeRichLabel(KeyBox, string.format("<b>Key:</b> %s", maskedKey))
    safeRichLabel(KeyBox, string.format("<b>Role:</b> %s", roleHtml))
    safeRichLabel(KeyBox, string.format("<b>Status:</b> %s", statusText))

    -- Show HWID hash for transparency
    safeRichLabel(KeyBox, string.format("<b>HWID Hash:</b> %s", tostring(keydata.hwid_hash or "-")))

    -- Tier: ตอนนี้ยังไม่มีใน keydata, ใช้ role แทน (คุณจะมา map เพิ่มทีหลังก็ได้)
    local tierText = string.upper(keydata.role or "free")
    safeRichLabel(KeyBox, string.format("<b>Tier:</b> %s", tierText))

    safeRichLabel(KeyBox, string.format("<b>Note:</b> %s", noteText))
    safeRichLabel(KeyBox, string.format("<b>Created at:</b> %s", createdAtText))

    -- Display expire and time left; if remote expire string is provided, use it instead of numeric timestamp
    local expireDisplay = remoteExpireStr or formatUnixTime(expireTs)
    local timeLeftDisplay = remoteExpireStr and remoteExpireStr or formatTimeLeft(expireTs)
    local ExpireLabel   = safeRichLabel(KeyBox, string.format("<b>Expire:</b> %s", expireDisplay))
    local TimeLeftLabel = safeRichLabel(KeyBox, string.format("<b>Time left:</b> %s", timeLeftDisplay))

    -- Update Expire / Time left in real time. Refresh more frequently (~0.25s)
    do
        local acc = 0
        AddConnection(RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 0.25 then
                return
            end
            acc = 0

            local nowExpire = tonumber(keydata.expire) or expireTs
            -- Use remote expire string if available, else format the timestamp
            local expireStr = remoteExpireStr or formatUnixTime(nowExpire)
            local leftStr   = remoteExpireStr and remoteExpireStr or formatTimeLeft(nowExpire)
            if ExpireLabel.Text then ExpireLabel.Text = string.format("<b>Expire:</b> %s", expireStr) end
            if TimeLeftLabel.Text then TimeLeftLabel.Text = string.format("<b>Time left:</b> %s", leftStr) end
        end))
    end

    --=== 4.3.2 Game Info (Right Groupbox) =========================
    local GameBox = safeAddRightGroupbox(InfoTab, "Game Info", "game")
    if GameBox then
        safeRichLabel(GameBox, '<font size="14"><b>Game Information</b></font>')
        GameBox:AddDivider()
        local placeId = game.PlaceId
        safeRichLabel(GameBox, string.format("<b>Place ID:</b> %d", placeId))
        local jobId = game.JobId or ""
        if jobId == "" then jobId = "N/A" end
        safeRichLabel(GameBox, string.format("<b>Server ID:</b> %s", tostring(jobId)))
        local owner = "N/A"
        pcall(function()
            local info = game:GetService("MarketplaceService"):GetProductInfo(placeId)
            if info and info.Creator then
                owner = tostring(info.Creator.Name)
            end
        end)
        safeRichLabel(GameBox, string.format("<b>Game Owner:</b> %s", owner))
        safeRichLabel(GameBox, string.format("<b>Players:</b> %d/%d", #Players:GetPlayers(), Players.MaxPlayers or 0))
        local verId = game.GameId or "N/A"
        safeRichLabel(GameBox, string.format("<b>Game ID:</b> %s", tostring(verId)))
    end

    ------------------------------------------------
    -- 4.4 Combat & Aimbot Tab
    ------------------------------------------------
    do
        local CombatTab = Tabs.Combat

        local AimBox = CombatTab:AddLeftGroupbox("Aimbot Settings", "target")
        local ExtraBox = safeAddRightGroupbox(CombatTab, "Extra Settings", "adjust")

        -- Aimbot toggles and settings
        -- Section: Core Settings
        AimBox:AddLabel("Core Settings")
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
        -- Section: Aim & Target Settings
        AimBox:AddLabel("Aim & Target Settings")
        local AimPartDropdown = AimBox:AddDropdown("bxw_aim_part", {
            Text = "Aim Part",
            Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Closest", "Random", "Custom" },
            Default = "Head",
            Multi = false,
            Tooltip = "Part to aim at (supports random and custom weighted selection)",
        })
        -- FOV settings section
        AimBox:AddLabel("FOV Settings")
        local FOVSlider = AimBox:AddSlider("bxw_aim_fov", {
            Text = "Aim FOV",
            Default = 10,
            Min = 1,
            Max = 50,
            Rounding = 1,
        })
        local ShowFOVToggle = AimBox:AddToggle("bxw_aim_showfov", {
            Text = "Show FOV Circle",
            Default = true,
        })
        local RainbowToggle = AimBox:AddToggle("bxw_aim_rainbow", {
            Text = "Rainbow FOV",
            Default = false,
        })
        local RainbowSpeedSlider = AimBox:AddSlider("bxw_aim_rainbowspeed", {
            Text = "Rainbow Speed",
            Default = 1,
            Min = 0,
            Max = 5,
            Rounding = 2,
        })
        -- Divider before smoothing
        AimBox:AddDivider()
        AimBox:AddLabel("Aiming Smoothness")
        local SmoothSlider = AimBox:AddSlider("bxw_aim_smooth", {
            Text = "Aimbot Smoothness",
            Default = 0.1,
            Min = 0.01,
            Max = 1,
            Rounding = 2,
            Compact = false,
            Tooltip = "Larger values = slower, more smooth aim",
        })
        -- Hit chance slider
        local HitChanceSlider = AimBox:AddSlider("bxw_aim_hitchance", {
            Text = "Global Hit Chance %",
            Default = 100,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Tooltip = "Overall chance for aimbot to fire (0-100%)",
        })
        -- Divider before activation and extra settings
        AimBox:AddDivider()
        AimBox:AddLabel("Activation & Extras")
        local AimActivationDropdown = AimBox:AddDropdown("bxw_aim_activation", {
            Text = "Aim Activation",
            Values = { "Hold Right Click", "Always On" },
            Default = "Hold Right Click",
            Multi = false,
            Tooltip = "How to activate the aimbot",
        })
        -- Smart Aim toggle: automatically aim head when only head is visible
        local SmartAimToggle = AimBox:AddToggle("bxw_aim_smart", {
            Text = "Smart Aim",
            Default = false,
            Tooltip = "Aim at the head if body is obstructed and head is visible",
        })
        -- Prediction aim toggle and factor
        local PredToggle = AimBox:AddToggle("bxw_aim_pred", {
            Text = "Prediction Aim",
            Default = false,
            Tooltip = "Lead targets based on their velocity",
        })
        local PredSlider = AimBox:AddSlider("bxw_aim_predfactor", {
            Text = "Prediction Factor",
            Default = 0.1,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Compact = false,
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

        -- Divider and label for per-part hit chance
        ExtraBox:AddDivider()
        ExtraBox:AddLabel("Hit Chance per Part")

        -- Hit chance per body part sliders
        local HeadChanceSlider = ExtraBox:AddSlider("bxw_hit_head_chance", {
            Text = "Head Hit Chance %",
            Default = 100,
            Min = 0,
            Max = 100,
            Rounding = 0,
        })
        local UpTorsoChanceSlider = ExtraBox:AddSlider("bxw_hit_uptorso_chance", {
            Text = "Upper Torso Hit Chance %",
            Default = 100,
            Min = 0,
            Max = 100,
            Rounding = 0,
        })
        local TorsoChanceSlider = ExtraBox:AddSlider("bxw_hit_torso_chance", {
            Text = "Torso Hit Chance %",
            Default = 100,
            Min = 0,
            Max = 100,
            Rounding = 0,
        })
        local HandChanceSlider = ExtraBox:AddSlider("bxw_hit_hand_chance", {
            Text = "Hand/Arm Hit Chance %",
            Default = 100,
            Min = 0,
            Max = 100,
            Rounding = 0,
        })
        local LegChanceSlider = ExtraBox:AddSlider("bxw_hit_leg_chance", {
            Text = "Leg Hit Chance %",
            Default = 100,
            Min = 0,
            Max = 100,
            Rounding = 0,
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
            if Toggles.bxw_aim_showfov and Toggles.bxw_aim_showfov.Value and Toggles.bxw_aimbot_enable and Toggles.bxw_aimbot_enable.Value then
                AimbotFOVCircle.Visible = true
                AimbotFOVCircle.Radius = (((Options.bxw_aim_fov and Options.bxw_aim_fov.Value) or 10) * 15)
                AimbotFOVCircle.Position = mouseLoc
                if Toggles.bxw_aim_rainbow and Toggles.bxw_aim_rainbow.Value then
                    rainbowHue = (rainbowHue or 0) + (((Options.bxw_aim_rainbowspeed and Options.bxw_aim_rainbowspeed.Value) or 0) / 360)
                    if rainbowHue > 1 then rainbowHue = rainbowHue - 1 end
                    AimbotFOVCircle.Color = Color3.fromHSV(rainbowHue, 1, 1)
                else
                    -- Use Options table to get FOV color
                    AimbotFOVCircle.Color = (Options.bxw_aim_fovcolor and Options.bxw_aim_fovcolor.Value) or Color3.fromRGB(255,255,255)
                end
            else
                AimbotFOVCircle.Visible = false
            end

            -- hide snap line by default
            AimbotSnapLine.Visible = false

            -- Only run aimbot logic if enabled
            if Toggles.bxw_aimbot_enable and Toggles.bxw_aimbot_enable.Value then
                local function findTarget()
                    local best = nil
                    local bestScore = math.huge
                    local myRoot = getRootPart()
                    if myRoot then
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer then
                                local char = plr.Character
                                local hum = char and char:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    local rootCandidate = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                                    if rootCandidate then
                                        local skip = false
                                        if Toggles.bxw_aim_teamcheck and Toggles.bxw_aim_teamcheck.Value then
                                            if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then
                                                skip = true
                                            end
                                        end
                                        if not skip then
                                            local aimPartName = (Options.bxw_aim_part and Options.bxw_aim_part.Value) or "Head"
                                            local selectedPart = nil
                                            if aimPartName == "Head" then
                                                selectedPart = char:FindFirstChild("Head")
                                            elseif aimPartName == "UpperTorso" then
                                                selectedPart = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
                                            elseif aimPartName == "Torso" then
                                                selectedPart = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("LowerTorso")
                                            elseif aimPartName == "HumanoidRootPart" then
                                                selectedPart = rootCandidate
                                            elseif aimPartName == "Closest" then
                                                local candidatesClosest = {}
                                                local function addClosest(name)
                                                    local p = char:FindFirstChild(name)
                                                    if p then table.insert(candidatesClosest, p) end
                                                end
                                                -- consider various body parts for proximity
                                                addClosest("Head")
                                                addClosest("UpperTorso")
                                                addClosest("Torso")
                                                addClosest("LowerTorso")
                                                addClosest("HumanoidRootPart")
                                                addClosest("RightFoot")
                                                addClosest("LeftFoot")
                                                addClosest("RightHand")
                                                addClosest("LeftHand")
                                                if #candidatesClosest > 0 then
                                                    local bestDist = math.huge
                                                    local bestPartClosest = nil
                                                    for _, p in ipairs(candidatesClosest) do
                                                        local sp, onScreen = cam:WorldToViewportPoint(p.Position)
                                                        if onScreen then
                                                            local dist = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                                                            if dist < bestDist then
                                                                bestDist = dist
                                                                bestPartClosest = p
                                                            end
                                                        end
                                                    end
                                                    selectedPart = bestPartClosest or rootCandidate
                                                else
                                                    selectedPart = rootCandidate
                                                end
                                            elseif aimPartName == "Custom" then
                                                -- custom weighted selection based on per-part hit chance sliders
                                                local partsWeighted = {}
                                                -- helper: add candidate parts with weight if available
                                                local function addChoices(chance, names)
                                                    if chance and chance > 0 then
                                                        for _, nm in ipairs(names) do
                                                            local p = char:FindFirstChild(nm)
                                                            if p then
                                                                table.insert(partsWeighted, { part = p, weight = chance })
                                                            end
                                                        end
                                                    end
                                                end
                                                local headChance  = Options.bxw_hit_head_chance and Options.bxw_hit_head_chance.Value or 0
                                                local upChance    = Options.bxw_hit_uptorso_chance and Options.bxw_hit_uptorso_chance.Value or 0
                                                local torsoChance = Options.bxw_hit_torso_chance and Options.bxw_hit_torso_chance.Value or 0
                                                local handChance  = Options.bxw_hit_hand_chance and Options.bxw_hit_hand_chance.Value or 0
                                                local legChance   = Options.bxw_hit_leg_chance and Options.bxw_hit_leg_chance.Value or 0
                                                addChoices(headChance, { "Head" })
                                                addChoices(upChance, { "UpperTorso", "Torso" })
                                                addChoices(torsoChance, { "LowerTorso", "Torso", "HumanoidRootPart" })
                                                addChoices(handChance, { "RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm" })
                                                addChoices(legChance, { "RightFoot", "LeftFoot", "RightLowerLeg", "LeftLowerLeg", "RightUpperLeg", "LeftUpperLeg" })
                                                if #partsWeighted > 0 then
                                                    -- weighted random selection
                                                    local sumWeight = 0
                                                    for _, c in ipairs(partsWeighted) do
                                                        sumWeight = sumWeight + c.weight
                                                    end
                                                    local r = math.random() * sumWeight
                                                    local accWeight = 0
                                                    for _, c in ipairs(partsWeighted) do
                                                        accWeight = accWeight + c.weight
                                                        if r <= accWeight then
                                                            selectedPart = c.part
                                                            break
                                                        end
                                                    end
                                                end
                                                if not selectedPart then
                                                    selectedPart = rootCandidate
                                                end
                                            elseif aimPartName == "Random" then
                                                local candidates = {}
                                                local function addPart(name)
                                                    local p = char:FindFirstChild(name)
                                                    if p then table.insert(candidates, p) end
                                                end
                                                addPart("Head")
                                                addPart("UpperTorso")
                                                addPart("Torso")
                                                addPart("HumanoidRootPart")
                                                addPart("RightFoot")
                                                addPart("LeftFoot")
                                                addPart("RightHand")
                                                addPart("LeftHand")
                                                if #candidates > 0 then
                                                    selectedPart = candidates[math.random(1, #candidates)]
                                                else
                                                    selectedPart = rootCandidate
                                                end
                                            else
                                                selectedPart = rootCandidate
                                            end
                                            if selectedPart then
                                                local screenPos, onScreen = cam:WorldToViewportPoint(selectedPart.Position)
                                                if onScreen then
                                                    local fovLimit = ((Options.bxw_aim_fov and Options.bxw_aim_fov.Value) or 10) * 15
                                                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mouseLoc).Magnitude
                                                    if screenDist <= fovLimit then
                                                        -- check visibility if enabled
                                                        local skipVis = false
                                                        if Toggles.bxw_aim_visibility and Toggles.bxw_aim_visibility.Value then
                                                            local rp = RaycastParams.new()
                                                            rp.FilterDescendantsInstances = { char, LocalPlayer.Character }
                                                            rp.FilterType = Enum.RaycastFilterType.Blacklist
                                                            local dir = (selectedPart.Position - cam.CFrame.Position)
                                                            local hit = Workspace:Raycast(cam.CFrame.Position, dir, rp)
                                                            -- consider visible if no hit or the hit is part of target or very transparent
                                                            local visible = false
                                                            if not hit then
                                                                visible = true
                                                            elseif hit.Instance then
                                                                if hit.Instance:IsDescendantOf(char) then
                                                                    visible = true
                                                                elseif hit.Instance.Transparency and hit.Instance.Transparency >= 0.5 then
                                                                    visible = true
                                                                end
                                                            end
                                                            skipVis = not visible
                                                        end
                                                        if not skipVis then
                                                            -- compute score based on target mode
                                                            local score = screenDist
                                                            local mode = (Options.bxw_aim_targetmode and Options.bxw_aim_targetmode.Value) or "Closest To Crosshair"
                                                            if mode == "Closest Distance" then
                                                                score = (rootCandidate.Position - myRoot.Position).Magnitude
                                                            elseif mode == "Lowest Health" then
                                                                score = hum.Health
                                                            end
                                                            if score < bestScore then
                                                                bestScore = score
                                                                best = {
                                                                    player   = plr,
                                                                    part     = selectedPart,
                                                                    root     = rootCandidate,
                                                                    char     = char,
                                                                    hum      = hum,
                                                                    screenPos = screenPos
                                                                }
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
                    return best
                end
                -- determine activation mode: hold right click or always
                local activation = (Options.bxw_aim_activation and Options.bxw_aim_activation.Value) or "Hold Right Click"
                if activation == "Always On" or (activation == "Hold Right Click" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
                    local bestPlr = nil
                    if activation == "Hold Right Click" then
                        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                            if lockedTarget and isTargetValid(lockedTarget, cam) then
                                bestPlr = lockedTarget
                                if bestPlr and bestPlr.part then
                                    local sp, onScreen = cam:WorldToViewportPoint(bestPlr.part.Position)
                                    bestPlr.screenPos = sp
                                end
                            else
                                lockedTarget = nil
                                bestPlr = findTarget()
                                if bestPlr then
                                    lockedTarget = bestPlr
                                end
                            end
                        else
                            lockedTarget = nil
                        end
                    else
                        lockedTarget = nil
                        bestPlr = findTarget()
                    end
                    if bestPlr then
                        -- apply global and per-part hit chance
                        local globalChance = (Options.bxw_aim_hitchance and Options.bxw_aim_hitchance.Value) or 100
                        -- determine part category for hit chance sliders using Options table
                        local pName = bestPlr.part.Name
                        local partChance = 100
                        local lowerName = string.lower(pName)
                        if string.find(lowerName, "head") then
                            partChance = (Options.bxw_hit_head_chance and Options.bxw_hit_head_chance.Value) or 100
                        elseif string.find(lowerName, "upper") or string.find(lowerName, "torso") then
                            partChance = (Options.bxw_hit_uptorso_chance and Options.bxw_hit_uptorso_chance.Value) or 100
                        elseif string.find(lowerName, "torso") or string.find(lowerName, "humanoidrootpart") or string.find(lowerName, "lower") then
                            partChance = (Options.bxw_hit_torso_chance and Options.bxw_hit_torso_chance.Value) or 100
                        elseif string.find(lowerName, "hand") or string.find(lowerName, "arm") then
                            partChance = (Options.bxw_hit_hand_chance and Options.bxw_hit_hand_chance.Value) or 100
                        elseif string.find(lowerName, "leg") or string.find(lowerName, "foot") then
                            partChance = (Options.bxw_hit_leg_chance and Options.bxw_hit_leg_chance.Value) or 100
                        end
                        if math.random(0, 100) <= globalChance and math.random(0, 100) <= partChance then
                            local aimPart = bestPlr.part
                            local camPos = cam.CFrame.Position

                            -- Smart aim: if root obstructed but head visible, aim at head
                            if Toggles.bxw_aim_smart and Toggles.bxw_aim_smart.Value then
                                local rootPart = bestPlr.root
                                local headPart = bestPlr.char and bestPlr.char:FindFirstChild("Head")
                                if rootPart and headPart then
                                    local rp = RaycastParams.new()
                                    rp.FilterDescendantsInstances = { bestPlr.char, LocalPlayer.Character }
                                    rp.FilterType = Enum.RaycastFilterType.Blacklist
                                    local dirRoot = (rootPart.Position - camPos)
                                    local hitRoot = Workspace:Raycast(camPos, dirRoot, rp)
                                    local rootBlocked = hitRoot and hitRoot.Instance and not hitRoot.Instance:IsDescendantOf(bestPlr.char)
                                    local dirHead = (headPart.Position - camPos)
                                    local hitHead = Workspace:Raycast(camPos, dirHead, rp)
                                    local headBlocked = hitHead and hitHead.Instance and not hitHead.Instance:IsDescendantOf(bestPlr.char)
                                    if rootBlocked and not headBlocked then
                                        aimPart = headPart
                                    end
                                end
                            end

                            -- prediction aim
                            local predictedPos = aimPart.Position
                            if Toggles.bxw_aim_pred and Toggles.bxw_aim_pred.Value then
                                local vel = aimPart.AssemblyLinearVelocity or aimPart.Velocity or Vector3.zero
                                local factor = (Options.bxw_aim_predfactor and Options.bxw_aim_predfactor.Value) or 0
                                predictedPos = predictedPos + vel * factor
                            end
                            local aimDir = (predictedPos - camPos).Unit

                            -- apply aim method
                            if Options.bxw_aim_method and Options.bxw_aim_method.Value == "MouseDelta" then
                                local delta = (Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y) - mouseLoc)
                                local smooth = (Options.bxw_aim_smooth and Options.bxw_aim_smooth.Value) or 0.1
                                -- apply stronger smoothing: divide factor to reduce jitter
                                delta = delta * ((smooth or 0) / 10)
                                pcall(function()
                                    mousemoverel(delta.X, delta.Y)
                                end)
                            else
                                local newCFrame = CFrame.new(camPos, camPos + aimDir)
                                local smooth = (Options.bxw_aim_smooth and Options.bxw_aim_smooth.Value) or 0.1
                                -- apply stronger smoothing to camera lerp
                                cam.CFrame = cam.CFrame:Lerp(newCFrame, ((smooth or 0) / 10))
                            end

                            -- snap line drawing
                            if Toggles.bxw_aim_snapline and Toggles.bxw_aim_snapline.Value then
                                AimbotSnapLine.Visible = true
                                AimbotSnapLine.From = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                                AimbotSnapLine.To = Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y)
                                AimbotSnapLine.Color = (Options.bxw_aim_snapcolor and Options.bxw_aim_snapcolor.Value) or Color3.fromRGB(255,0,0)
                                AimbotSnapLine.Thickness = (Options.bxw_aim_snapthick and Options.bxw_aim_snapthick.Value) or 1
                            end

                            -- Triggerbot logic
                            if Toggles.bxw_triggerbot and Toggles.bxw_triggerbot.Value then
                                local tFov = ((Options.bxw_trigger_fov and Options.bxw_trigger_fov.Value) or 10) * 15
                                local tDist = (Vector2.new(bestPlr.screenPos.X, bestPlr.screenPos.Y) - mouseLoc).Magnitude
                                if tDist <= tFov then
                                    local tSkip = false
                                    if Toggles.bxw_trigger_teamcheck and Toggles.bxw_trigger_teamcheck.Value then
                                        if bestPlr.player ~= LocalPlayer and LocalPlayer.Team and bestPlr.player.Team and LocalPlayer.Team == bestPlr.player.Team then
                                            tSkip = true
                                        end
                                    end
                                    if not tSkip and Toggles.bxw_trigger_wallcheck and Toggles.bxw_trigger_wallcheck.Value then
                                        local rp2 = RaycastParams.new()
                                        rp2.FilterDescendantsInstances = { bestPlr.char, LocalPlayer.Character }
                                        rp2.FilterType = Enum.RaycastFilterType.Blacklist
                                        local dir2 = (aimPart.Position - camPos)
                                        local hit2 = Workspace:Raycast(camPos, dir2, rp2)
                                        if hit2 and hit2.Instance and not hit2.Instance:IsDescendantOf(bestPlr.char) then
                                            tSkip = true
                                        end
                                    end
                                    if not tSkip then
                                        local fireMode = (Options.bxw_trigger_firing and Options.bxw_trigger_firing.Value) or "Single"
                                        local method = (Options.bxw_trigger_method and Options.bxw_trigger_method.Value) or "Always On"
                                        local holdAllowed = true
                                        if method == "Hold Key" then
                                            holdAllowed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                                        end
                                        if holdAllowed then
                                            local delayTime   = (Options.bxw_trigger_delay and Options.bxw_trigger_delay.Value) or 0
                                            local holdTime    = (Options.bxw_trigger_hold and Options.bxw_trigger_hold.Value) or 0.05
                                            local releaseTime = (Options.bxw_trigger_release and Options.bxw_trigger_release.Value) or 0.05
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
        local MiscRight = safeAddRightGroupbox(MiscTab, "Environment", "sun")

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

        -- Ambient color picker hosted on a label
        local AmbientColorLabel = MiscRight:AddLabel("Ambient Color")
        -- Create the ambient color picker. AddColorPicker returns the label object, so use Options to get the ColorPicker control.
        AmbientColorLabel:AddColorPicker("bxw_ambient_color", {
            Default = game.Lighting.Ambient,
        })
        -- Register a callback on the actual ColorPicker object via Library.Options
        local AmbientOpt = Options.bxw_ambient_color
        if AmbientOpt and typeof(AmbientOpt.OnChanged) == "function" then
            AmbientOpt:OnChanged(function(col)
                game.Lighting.Ambient = col
            end)
        end

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
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Health = 0 end
            end
        end)

    end

    ---------------------------------------------
    -- 4.6 Cleanup & Return
    ---------------------------------------------

    -- Finalize UI and make visible
    Library:Finalize()

    -- Auto-disable UI on character added if option is set (to prevent interfering with gameplay)
    if Toggles and Toggles.bxw_disable_on_respawn then
        AddConnection(LocalPlayer.CharacterAdded:Connect(function()
            if Toggles.bxw_disable_on_respawn.Value then
                Library:Close()
            end
        end))
    end

    -- output success to console
    warn("[MainHub] Loaded successfully")

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
