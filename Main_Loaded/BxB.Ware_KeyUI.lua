-- Key_Loaded.lua
-- ใช้เป็น Loader + Key UI + Status + Auto-login
-- เรียกจาก executor:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/you/yourrepo/main/Key_Loaded.lua"))()

do
    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local HttpService = game:GetService("HttpService")
    local Players = game:GetService("Players")
    local AnalyticsService = game:GetService("RbxAnalyticsService")

    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- Exec Abstraction (multi-executor)
    ----------------------------------------------------------------
    local Exec = {}

    do
        ----------------------------------------------------------------
        -- HTTP
        ----------------------------------------------------------------
        local httpRequest

        if typeof(syn) == "table" and type(syn.request) == "function" then
            httpRequest = syn.request
        elseif type(http_request) == "function" then
            httpRequest = http_request
        elseif type(request) == "function" then
            httpRequest = request
        elseif typeof(http) == "table" and type(http.request) == "function" then
            httpRequest = http.request
        end

        local function fallbackHttpGet(url)
            local ok, result = pcall(game.HttpGet, game, url)
            if ok and type(result) == "string" then
                return result
            end

            error("[Exec.HttpGet] game:HttpGet failed: " .. tostring(result))
        end

        function Exec.HttpGet(url)
            assert(type(url) == "string", "[Exec.HttpGet] url must be string")

            if httpRequest then
                local ok, response = pcall(httpRequest, {
                    Url = url,
                    Method = "GET"
                })

                if ok and response then
                    local body = response.Body or response.body
                    if type(body) == "string" then
                        return body
                    end
                end
            end

            return fallbackHttpGet(url)
        end

        ----------------------------------------------------------------
        -- Files
        ----------------------------------------------------------------
        local writeFile = type(writefile) == "function" and writefile or nil
        local readFile  = type(readfile)  == "function" and readfile  or nil
        local isFile    = type(isfile)    == "function" and isfile    or nil

        function Exec.WriteFile(path, data)
            if not writeFile then
                return false, "writefile not available"
            end

            local ok, err = pcall(writeFile, path, data)
            if not ok then
                return false, tostring(err)
            end

            return true
        end

        function Exec.ReadFile(path)
            if not readFile then
                return nil, "readfile not available"
            end

            local ok, result = pcall(readFile, path)
            if not ok then
                return nil, tostring(result)
            end

            return result
        end

        function Exec.IsFile(path)
            if isFile then
                local ok, result = pcall(isFile, path)
                return ok and result == true
            end

            local content = select(1, Exec.ReadFile(path))
            return content ~= nil
        end

        ----------------------------------------------------------------
        -- Clipboard
        ----------------------------------------------------------------
        local setClipboard = type(setclipboard) == "function" and setclipboard
            or type(toclipboard) == "function" and toclipboard
            or nil

        local getClipboard = type(getclipboard) == "function" and getclipboard or nil

        function Exec.SetClipboard(text)
            if not setClipboard then
                return false, "clipboard api not available"
            end

            local ok, err = pcall(setClipboard, text)
            if not ok then
                return false, tostring(err)
            end

            return true
        end

        function Exec.GetClipboard()
            if not getClipboard then
                return nil, "getclipboard not available"
            end

            local ok, result = pcall(getClipboard)
            if not ok then
                return nil, tostring(result)
            end

            return result
        end
    end

    ----------------------------------------------------------------
    -- Config (แก้ให้ตรงกับโปรเจกต์ของคุณ)
    ----------------------------------------------------------------
    local Config = {
        -- TODO: ปรับเป็น repo ของคุณเอง
        LIBRARY_URL     = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/Library.lua",
        THEME_URL       = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/addons/ThemeManager.lua",
        SAVE_URL        = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/UI_System/addons/SaveManager.lua",

        KEYDATA_URL     = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/data.json",
        SCRIPTINFO_URL  = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/scriptinfo.json",
        CHANGELOG_URL   = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Key_System/changelog.json",
        MAINHUB_URL     = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Rewrite.lua",

        KEYDATA_FILE    = "BxB.ware/obsidian_keydata.json"
    }
    ----------------------------------------------------------------
    -- HWID + Secure Hash (128-bit)
    ----------------------------------------------------------------
    local function getHWID()
        local hwid

        do
            local ok, clientId = pcall(AnalyticsService.GetClientId, AnalyticsService)
            if ok and type(clientId) == "string" and clientId ~= "" then
                hwid = clientId
            end
        end

        if not hwid and LocalPlayer then
            hwid = tostring(LocalPlayer.UserId) .. "_" .. (LocalPlayer.Name or "")
        end

        if not hwid then
            hwid = "unknown_hwid"
        end

        return hwid
    end

    local bit = bit32
    if not bit then
        error("[HWID] bit32 library is required for secure HWID hash")
    end

    local function rotl32(x, n)
        n = n % 32
        if n == 0 then
            return x
        end
        return bit.bor(bit.lshift(x, n), bit.rshift(x, 32 - n))
    end

    local function secureHWIDHash(str)
        local salt = "BxB.ware-Universal@#$)_%@#^()$@%_)+%(@"
        local s = salt .. "\0" .. str .. "\0" .. tostring(#str)

        local h1 = 0x6A09E667
        local h2 = 0xBB67AE85
        local h3 = 0x3C6EF372
        local h4 = 0xA54FF53A

        for i = 1, #s do
            local c = string.byte(s, i)

            h1 = bit.bxor(h1, c)
            h1 = rotl32(h1, 5)

            h2 = bit.bxor(h2, h1 + c)
            h2 = rotl32(h2, 7)

            h3 = bit.bxor(h3, h2 + (c * 2))
            h3 = rotl32(h3, 11)

            h4 = bit.bxor(h4, h3 + (c * 3))
            h4 = rotl32(h4, 13)
        end

        local function fmix(x)
            x = bit.bxor(x, bit.rshift(x, 16))
            x = bit.bxor(x, 0x9E3779B9)
            x = rotl32(x, 11)
            x = bit.bxor(x, bit.rshift(x, 7))
            return x
        end

        h1 = fmix(h1)
        h2 = fmix(h2)
        h3 = fmix(h3)
        h4 = fmix(h4)

        return string.format("%08x%08x%08x%08x", h1, h2, h3, h4)
    end

    local function getHWIDHash()
        return secureHWIDHash(getHWID())
    end

    ----------------------------------------------------------------
    -- แปลงค่า timestamp / expire จาก JSON ให้เป็น Unix timestamp (number)
    ----------------------------------------------------------------
    local function parseTimeField(raw)
        if raw == nil then
            return nil
        end

        local t = typeof(raw)
        if t == "number" then
            return raw
        end

        if t ~= "string" then
            return nil
        end

        raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")

        local year, month, day
        local hour, min, sec

        local a, b, c, hh, mm, ss = raw:match("^(%d+)[%/:](%d+)[%/:](%d+)%s+(%d+):(%d+):(%d+)$")
        if a then
            a = tonumber(a)
            b = tonumber(b)
            c = tonumber(c)
            hour = tonumber(hh) or 0
            min  = tonumber(mm) or 0
            sec  = tonumber(ss) or 0

            if not (a and b and c) then
                return nil
            end

            if c < 100 then
                year = 2000 + c
            else
                year = c
            end

            if a > 12 and b <= 12 then
                day   = a
                month = b
            elseif b > 12 and a <= 12 then
                day   = b
                month = a
            else
                month = a
                day   = b
            end
        else
            local y, m, d, hh2, mm2, ss2 = raw:match("^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)$")
            if not y then
                return nil
            end

            year = tonumber(y)
            month = tonumber(m)
            day   = tonumber(d)
            hour  = tonumber(hh2) or 0
            min   = tonumber(mm2) or 0
            sec   = tonumber(ss2) or 0

            if not (year and month and day) then
                return nil
            end
        end

        local ok, dt = pcall(function()
            return DateTime.fromUniversalTime(year, month, day, hour, min, sec)
        end)

        if not ok or not dt then
            return nil
        end

        return dt.UnixTimestamp
    end

    ----------------------------------------------------------------
    -- Helper: แปลง scriptinfo JSON -> Text
    ----------------------------------------------------------------
    local function parseScriptInfoBody(body)
        if type(body) ~= "string" or body == "" then
            return "unknown", "No script info data."
        end

        local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok or type(decoded) ~= "table" then
            return "online", body -- Return raw if not JSON
        end

        -- Helper to clean strings for RichText
        local function esc(s)
            return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        end

        local status = decoded.status or "online"
        local lines = {}
        local function add(s) table.insert(lines, s) end

        -- Header
        local head = string.format("<b>%s</b>", esc(decoded.hub_name or "Hub"))
        if decoded.version then head = head .. string.format(" <font color='#aaaaaa'>v%s</font>", esc(decoded.version)) end
        if decoded.channel then head = head .. string.format(" <font color='#cccccc'>[%s]</font>", esc(decoded.channel)) end
        add(head)
        
        if decoded.last_update then add("Last Update: " .. esc(decoded.last_update)) end
        
        -- Description
        if decoded.description then
            add("")
            if type(decoded.description) == "table" then
                add(esc(decoded.description.long or decoded.description.short))
            else
                add(esc(decoded.description))
            end
        end

        -- Features
        if type(decoded.features) == "table" then
            add("")
            add("<b>Features:</b>")
            for k, v in pairs(decoded.features) do
                if type(v) == "table" then
                    local fStatus = v.status or "active"
                    local statusColor = fStatus == "online" and "#55ff55" or (fStatus == "maintenance" and "#ffcc66" or "#cccccc")
                    add(string.format("• <b>%s</b> <font color='%s'>[%s]</font>: %s", esc(k:upper()), statusColor, esc(fStatus), esc(v.description)))
                end
            end
        end

        -- Game Support
        if type(decoded.game_support) == "table" then
            add("")
            add("<b>Supported Games:</b>")
            for _, g in ipairs(decoded.game_support) do
                local gStatus = g.status or "online"
                local statusIcon = gStatus == "online" and "🟢" or "🔴"
                add(string.format("%s %s (ID: %s)", statusIcon, esc(g.name), tostring(g.place_id)))
            end
        end
        
        -- Executors
        if type(decoded.executors_support) == "table" then
            add("")
            add("<b>Executors:</b>")
            local ex = decoded.executors_support
            if ex.stable then add("Stable: " .. table.concat(ex.stable, ", ")) end
            if ex.mobile then add("Mobile: " .. table.concat(ex.mobile, ", ")) end
        end

        return status, table.concat(lines, "\n")
    end

    ----------------------------------------------------------------
    -- Helper: แปลง changelog JSON -> Text
    ----------------------------------------------------------------
    local function parseChangelogBody(body)
        if type(body) ~= "string" or body == "" then
            return "unknown", "No changelog data."
        end

        local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok or type(decoded) ~= "table" then
            return "online", body
        end

        local function esc(s)
            return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        end

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
                
                -- Highlights
                if type(entry.highlights) == "table" then
                    for _, h in ipairs(entry.highlights) do
                        add("• " .. esc(h))
                    end
                end

                -- Detailed Changes
                if type(entry.changes) == "table" then
                    local function addChangeGroup(label, color, items)
                        if type(items) == "table" and #items > 0 then
                            add(string.format("<font color='%s'>%s</font>", color, label))
                            for _, item in ipairs(items) do
                                add(" - " .. esc(item))
                            end
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


    ----------------------------------------------------------------
    -- Local keyfile helpers (เก็บเฉพาะ key)
    ----------------------------------------------------------------
    local function loadLocalKeydata()
        if not Exec.IsFile(Config.KEYDATA_FILE) then
            return nil
        end

        local raw = select(1, Exec.ReadFile(Config.KEYDATA_FILE))
        if not raw or raw == "" then
            return nil
        end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(decoded) ~= "table" then
            return nil
        end

        if type(decoded.key) ~= "string" or decoded.key == "" then
            return nil
        end

        return decoded.key
    end

    local function saveLocalKeydata(key)
        local data = { key = key }
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not ok then
            return false, tostring(encoded)
        end

        return Exec.WriteFile(Config.KEYDATA_FILE, encoded)
    end

    ----------------------------------------------------------------
    -- Remote keydata helpers
    ----------------------------------------------------------------
    local function fetchRemoteKeyTable()
        local body

        local ok = pcall(function()
            body = Exec.HttpGet(Config.KEYDATA_URL)
        end)

        if not ok or type(body) ~= "string" then
            return nil
        end

        local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok2 or type(decoded) ~= "table" then
            return nil
        end

        local list = decoded.keys or decoded
        if type(list) ~= "table" then
            return nil
        end

        return list, decoded
    end

    local function findRemoteRecord(list, key)
        if type(list) ~= "table" then
            return nil
        end

        for _, item in ipairs(list) do
            if type(item) == "table" and item.key == key then
                return item
            end
        end

        return nil
    end

    ----------------------------------------------------------------
    -- Expire + Status helpers
    ----------------------------------------------------------------
    local function getUnixNow()
        local ok, dt = pcall(DateTime.now)
        if ok and dt then
            return dt.UnixTimestamp
        end

        return nil
    end

    local function getExpireTimestamp(remoteRecord)
        if not remoteRecord then
            return nil
        end

        local raw =
            remoteRecord.expire
            or remoteRecord.expire_at
            or remoteRecord.expire_unix
            or remoteRecord.expires_at

        if typeof(raw) == "number" then
            return raw
        end

        local ts = parseTimeField(raw)
        return ts
    end

    local function isKeyExpired(remoteRecord)
        local expireTs = getExpireTimestamp(remoteRecord)
        if not expireTs then
            return false
        end

        local nowTs = getUnixNow()
        if not nowTs then
            return false
        end

        return nowTs >= expireTs
    end

    local function getKeyStatus(remoteRecord)
        local status = tostring(remoteRecord.status or "active")
        local note = remoteRecord.note
        return status, note
    end

    local function isStatusBlocked(status)
        status = tostring(status or "active")

        if status == "active" then
            return false
        end

        if status == "trial" then
            return false
        end

        return true
    end

    ----------------------------------------------------------------
    -- KeySystem core (Edited Logic for Free/HWID)
    ----------------------------------------------------------------
    local KeySystem = {}

    function KeySystem.TryAutoLogin()
        local localKey = loadLocalKeydata()
        if not localKey then
            return false
        end

        local list = fetchRemoteKeyTable()
        if not list then
            return false
        end

        local remoteRecord = findRemoteRecord(list, localKey)
        if not remoteRecord then
            return false
        end

        local hwidHash = getHWIDHash()

        -- Fixed Logic: Check bind_hwid
        local shouldBind = remoteRecord.bind_hwid
        if shouldBind == nil then shouldBind = true end -- Default to secure if missing

        if shouldBind then
            if type(remoteRecord.hwid_hash) ~= "string" or remoteRecord.hwid_hash ~= hwidHash then
                return false
            end
        end

        if isKeyExpired(remoteRecord) then
            return false
        end

        local status, note = getKeyStatus(remoteRecord)
        if isStatusBlocked(status) then
            return false
        end

        local keydata = {
            key       = localKey,
            hwid_hash = hwidHash,
            timestamp = parseTimeField(remoteRecord.timestamp or remoteRecord.created_at),
            role      = remoteRecord.role or "user",
            expire    = getExpireTimestamp(remoteRecord),
            status    = status,
            note      = note,
            bind_hwid = shouldBind
        }

        return true, keydata
    end

    function KeySystem.AttemptLogin(inputKey)
        local key = tostring(inputKey or "")
        key = key:gsub("^%s+", ""):gsub("%s+$", "")

        if key == "" then
            return false, "Key is empty"
        end

        local list = fetchRemoteKeyTable()
        if not list then
            return false, "Cannot fetch keydata (offline?)"
        end

        local remoteRecord = findRemoteRecord(list, key)
        if not remoteRecord then
            return false, "Invalid key"
        end

        local hwidHash = getHWIDHash()

        -- Fixed Logic: Check bind_hwid
        local shouldBind = remoteRecord.bind_hwid
        if shouldBind == nil then shouldBind = true end -- Default to secure if missing

        if shouldBind then
            if type(remoteRecord.hwid_hash) ~= "string" or remoteRecord.hwid_hash == "" then
                -- Optional: If key is meant to be bound but has no hash yet, you might want to bind it here via POST (not implemented)
                -- For now, fail if hash is missing on a bound key
                return false, "Key is unused but requires HWID binding (Contact Admin)"
            elseif remoteRecord.hwid_hash ~= hwidHash then
                return false, "HWID mismatch (Key is bound to another device)"
            end
        end

        if isKeyExpired(remoteRecord) then
            return false, "Key expired"
        end

        local status, note = getKeyStatus(remoteRecord)
        if isStatusBlocked(status) then
            local reason = note or status
            return false, "Key blocked: " .. tostring(reason)
        end

        local keydata = {
            key       = key,
            hwid_hash = hwidHash,
            bind_hwid = shouldBind,
            timestamp = parseTimeField(remoteRecord.timestamp or remoteRecord.created_at),
            role      = remoteRecord.role or "user",
            expire    = getExpireTimestamp(remoteRecord),
            status    = status,
            note      = note
        }

        saveLocalKeydata(key)

        return true, keydata
    end


 ----------------------------------------------------------------
    -- Main Hub Loader (Updated with Dynamic Token)
    ----------------------------------------------------------------
    local function fnv1a32(str)
        -- Compute a 32-bit FNV-1a hash for the given string. This matches the
        -- implementation in MainHub so that tokens align.
        local hash = 0x811C9DC5
        for i = 1, #str do
            hash = bit.bxor(hash, str:byte(i))
            hash = (hash * 0x01000193) % 0x100000000
        end
        return hash
    end

    local function buildExpectedToken(keydata)
        -- Build the auth token in the same way MainHub does. Concatenate the
        -- secret pepper, the key, hwid hash, role, datePart, and key length,
        -- then hash with FNV-1a and format as 8‑digit uppercase hex.
        local SECRET_PEPPER = "BxB.ware-Universal@#$)_%@#^()$@%_)+%(@"
        local k    = tostring(keydata.key or keydata.Key or "")
        local hw   = tostring(keydata.hwid_hash or keydata.HWID or "no-hwid")
        local role = tostring(keydata.role or "user")
        local datePart = os.date("%Y%m%d")
        local raw = table.concat({ SECRET_PEPPER, k, hw, role, datePart, tostring(#k) }, "|")
        local h = fnv1a32(raw)
        return ("%08X"):format(h)
    end

    local function startMainHub(keydata, Library)
        local src = Exec.HttpGet(Config.MAINHUB_URL)
        local chunk, err = loadstring(src)
        if not chunk then
            warn("[Obsidian] Failed to load MainHub: " .. tostring(err))
            return
        end
        local ok, startFn = pcall(chunk)
        if not ok or type(startFn) ~= "function" then
            warn("[Obsidian] MainHub must return a function!")
            return
        end
        -- Generate an auth token that matches MainHub's expected format
        local token = buildExpectedToken(keydata)
        local success, err2 = pcall(startFn, Exec, keydata, token)
        if not success then
            warn("[Obsidian] Runtime error: " .. tostring(err2))
        end
        -- Close the UI after starting the hub
        if Library and type(Library.Unload) == "function" then
            Library:Unload()
        end
    end
    ----------------------------------------------------------------
    -- Key UI (Obsidian)
    ----------------------------------------------------------------
    local function createKeyUI(Library)
        local HttpService = game:GetService("HttpService")
        local Options = Library.Options

        local function notify(msg, dur)
            if Library and type(Library.Notify) == "function" then
                Library:Notify(tostring(msg), dur or 3)
            else
                warn("[Obsidian] " .. tostring(msg))
            end
        end

        local Window = Library:CreateWindow({
            Title = "",
            Center = true,
            AutoShow = true,
            Icon = "84528813312016",
            Footer = '<b><font color="#B563FF">BxB.ware | Universal | Game Module/Client</font></b>',
            CornerRadius = 6,
            ShowCustomCursor = true,
            Resizable = false, 
            Size = UDim2.fromOffset(600, 300),
            DisableSearch = true,   
            Compact = true,
        })

        local Tabs = {
            Key = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>',Icon = "key", Description = "<b>Key System & Security</b>"}),
            Info = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>',Icon = "info", Description = "<b>Script info & Changlog</b>"})
        }

        local KeyLeft   = Tabs.Key:AddLeftGroupbox("Key System", "key-round")
        local KeyRight  = Tabs.Key:AddRightGroupbox("Data Base", "database-zap")

        local InfoLeft  = Tabs.Info:AddLeftGroupbox("Script Info", "badge-info")
        local InfoRight = Tabs.Info:AddRightGroupbox("Changlog", "rss")

        ----------------------------------------------------------------
        -- WarningBox: Typewriter effect
        ----------------------------------------------------------------
        Tabs.Key:UpdateWarningBox({
                Title = '<b><font color="#8370FF">BxB.ware</font> | Announcement </b>',
                Text = 'Free <font color="#FF0000">Premium</font> Key 1 Month!! (1/08/26 00:00:00) \nKEY : <b>BxB-Ware-PremiumFree</b>', 
                IsNormal = true,
                Visible = true,
                LockSize = true,
            })
        Tabs.Info:UpdateWarningBox({
            Title = "",
            Text = "",
            IsNormal = true,
            Visible = true,
            LockSize = true,
        })

        local WarningMessages = {
            "BxB.ware | Multi-game script  ",
            "Support Executor: \n[PC] Wave, Potassium, Volt, Seliware, Volcano, Xeno \n[MAC] Maxsploit \n[MB-AD] Delta, Codex  |  [MB-IOS] Delta",
            "Support: (ตัวอย่าง) Blox Fruits, Anime, FPS",
            "Credits: Hub by BXMQZ, UI by Obsidian",
            "Discord: discord.gg/yourdiscord"
        }

        local function setWarningText(text)
            Tabs.Info:UpdateWarningBox({
                Title = '<b><font color="#8370FF">BxB.ware</font> | Universal </b>',
                Text = text,
                IsNormal = true,
                Visible = true,
                LockSize = true,
            })
        end

        local function typeWrite(text, delayPerChar)
            delayPerChar = delayPerChar or 0.04
            for i = 1, #text do
                local current = string.sub(text, 1, i)
                setWarningText(current)
                task.wait(delayPerChar)
            end
        end

        local function typeDelete(text, delayPerChar)
            delayPerChar = delayPerChar or 0.02
            for i = #text, 0, -1 do
                local current = string.sub(text, 1, i)
                setWarningText(current)
                task.wait(delayPerChar)
            end
        end

        task.spawn(function()
            while true do
                for _, msg in ipairs(WarningMessages) do
                    typeWrite(msg, 0.035)
                    task.wait(4)
                    typeDelete(msg, 0.02)
                    task.wait(0.4)
                end
            end
        end)


        ----------------------------------------------------------------
        -- 1) Login Cooldown Guard
        ----------------------------------------------------------------
        local LoginGuard = { FailCount = 0, CooldownUntil = 0 }

        local function canAttemptLogin()
            local now = tick()
            if now < LoginGuard.CooldownUntil then
                return false, math.max(0, LoginGuard.CooldownUntil - now)
            end
            return true, 0
        end

        local function registerLoginFail()
            local now = tick()
            LoginGuard.FailCount = LoginGuard.FailCount + 1
            if LoginGuard.FailCount >= 3 then
                LoginGuard.CooldownUntil = now + 15
                LoginGuard.FailCount = 0
            end
        end

        local function registerLoginSuccess()
            LoginGuard.FailCount = 0
            LoginGuard.CooldownUntil = 0
        end

        ----------------------------------------------------------------
        -- 2) Tab "Key" ฝั่งซ้าย: Key System
        ----------------------------------------------------------------
        KeyLeft:AddLabel('<font color="#ff6666">Do not share your key with others.</font>', true)

        KeyLeft:AddInput("Obsidian_KeyInput", {
            Text = "",
            Default = "",
            Placeholder = "Paste your key here",
            Numeric = false,
        })
        KeyLeft:AddDivider()

        local function getKeyFromInput()
            local obj = Options and Options.Obsidian_KeyInput
            local val = obj and obj.Value
            if type(val) ~= "string" then val = val and tostring(val) or "" end
            return val
        end

        KeyLeft:AddButton("Login / Check Key", function()
            local allowed, remain = canAttemptLogin()
            if not allowed then
                notify("Too many attempts. Please wait " .. tostring(math.ceil(remain)) .. "s.", 4)
                return
            end

            local key = getKeyFromInput()
            key = key:gsub("^%s+", ""):gsub("%s+$", "")

            if key == "" then
                registerLoginFail()
                notify("Key is empty", 3)
                return
            end

            local ok, result = KeySystem.AttemptLogin(key)

            if not ok then
                registerLoginFail()
                notify("Key failed: " .. tostring(result), 4)
                return
            end

            registerLoginSuccess()
            notify("Key success. Loading Main Hub...", 3)
            startMainHub(result, Library)
        end)

        KeyLeft:AddButton("Get Key", function()
            local ok, err = Exec.SetClipboard("https://your-key-system-url-here/")
            if ok then
                notify("Copied key URL to clipboard", 3)
            else
                notify("Cannot access clipboard: " .. tostring(err), 4)
            end
        end)

        ----------------------------------------------------------------
        -- 3) Tab "Key": Status Monitor
        ----------------------------------------------------------------
        KeyRight:AddLabel("<b>Remote Status</b>", true)
        KeyRight:AddDivider()

        local StatusEntries = {}
        local StatusOrder = {}

        local function addStatusLine(name, url, kind)
            local label = KeyRight:AddLabel(
                string.format("<b>%s</b>: <font color=\"#aaaaaa\">Unknown</font>", name),
                true
            )
            if label and label.TextLabel then
                label.TextLabel.RichText = true
                label.TextLabel.TextWrapped = false
                label.TextLabel.AutomaticSize = Enum.AutomaticSize.None
                label.TextLabel.TextXAlignment = Enum.TextXAlignment.Left
            end
            StatusEntries[name] = { Name = name, Url = url, Kind = kind or "json", Label = label }
            table.insert(StatusOrder, name)
        end

        local function colorForStatusFlag(flag)
            flag = flag and string.lower(flag) or ""
            if flag == "online" or flag == "active" then return "#55ff55" end
            if flag == "maintenance" or flag == "degraded" then return "#ffcc66" end
            if flag == "offline" or flag == "disabled" then return "#ff5555" end
            return "#aaaaaa"
        end

        local function setStatus(name, networkOk, statusFlag, statusMsg)
            local entry = StatusEntries[name]
            if not entry then return end
            local lbl = entry.Label
            if not (lbl and lbl.TextLabel) then return end

            local flag = statusFlag
            if not flag or flag == "" then flag = networkOk and "online" or "offline" end
            local color = colorForStatusFlag(flag)
            local prettyFlag = tostring(flag)
            prettyFlag = prettyFlag:sub(1, 1):upper() .. prettyFlag:sub(2):lower()

            local text = string.format("<b>%s</b>: <font color=\"%s\">%s</font>", name, color, prettyFlag)
            lbl.TextLabel.RichText = true
            lbl.TextLabel.TextWrapped = false
            lbl.TextLabel.Text = text
        end

        local function parseJsonStatus(body)
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
            if not ok or type(decoded) ~= "table" then return nil, "Invalid JSON" end
            local status = decoded.status
            local msg    = decoded.status_message
            local meta = decoded.meta
            if type(meta) == "table" then
                status = status or meta.status
                msg    = msg or meta.status_message
            end
            return { status = status, message = msg }, nil
        end

        local function parseLuaStatus(body)
            local status = body:match("STATUS%s*:%s*([%w_-]+)")
            local msg    = body:match("STATUS_MSG%s*:%s*([^\r\n]+)")
            if status then return { status = status, message = msg }, nil end
            return nil, nil
        end

        addStatusLine("Key",      Config.KEYDATA_URL,    "json")
        addStatusLine("MainHub",  Config.MAINHUB_URL,    "lua")
        addStatusLine("Script",   Config.SCRIPTINFO_URL, "json")
        addStatusLine("Changelog",Config.CHANGELOG_URL,  "json")

        local STATUS_REFRESH_INTERVAL = 180

        local function refreshStatus()
            for _, name in ipairs(StatusOrder) do
                local entry = StatusEntries[name]
                task.spawn(function()
                    local ok, result = pcall(Exec.HttpGet, entry.Url)
                    if not ok or type(result) ~= "string" or result == "" then
                        setStatus(name, false, "offline", "No response")
                        return
                    end
                    local networkOk = true
                    local statusFlag
                    local statusMsg
                    if entry.Kind == "json" then
                        local info, jsonErr = parseJsonStatus(result)
                        if info then statusFlag, statusMsg = info.status, info.message end
                    elseif entry.Kind == "lua" then
                        local info = select(1, parseLuaStatus(result))
                        if info then statusFlag, statusMsg = info.status, info.message end
                    end
                    setStatus(name, networkOk, statusFlag, statusMsg)
                end)
            end
        end

        refreshStatus()
        task.spawn(function()
            while true do
                task.wait(STATUS_REFRESH_INTERVAL)
                refreshStatus()
            end
        end)

        ----------------------------------------------------------------
        -- 4) Tab "Info": ScriptInfo + Changelog (Use New Parsers)
        ----------------------------------------------------------------
        local function addRichLabel(group, text)
            local lbl = group:AddLabel(text, true)
            if lbl and lbl.TextLabel then lbl.TextLabel.RichText = true end
            return lbl
        end

        local function fetchText(url)
            local ok, body = pcall(Exec.HttpGet, url)
            if not ok or type(body) ~= "string" then return nil, body end
            return body
        end

        -- Render ScriptInfo using new parser
        task.spawn(function()
            local body, err = fetchText(Config.SCRIPTINFO_URL)
            if not body then
                addRichLabel(InfoLeft, "<font color=\"#ff5555\">Failed to load scriptinfo</font>")
                return
            end
            local _, formattedText = parseScriptInfoBody(body)
            
            -- Split newlines to create separate labels for better spacing in Obsidian
            for line in string.gmatch(formattedText, "[^\r\n]+") do
                 addRichLabel(InfoLeft, line)
            end
        end)

        -- Render Changelog using new parser
        task.spawn(function()
            local body, err = fetchText(Config.CHANGELOG_URL)
            if not body then
                addRichLabel(InfoRight, "<font color=\"#ff5555\">Failed to load changelog</font>")
                return
            end
            local _, formattedText = parseChangelogBody(body)

             -- Split newlines to create separate labels
            for line in string.gmatch(formattedText, "[^\r\n]+") do
                 addRichLabel(InfoRight, line)
            end
        end)
    end

    ----------------------------------------------------------------
    -- Entry: โหลด Library / Theme / Save + Auto-login + Key UI
    ----------------------------------------------------------------
    local Library = loadstring(Exec.HttpGet(Config.LIBRARY_URL))()
    local ThemeManager = loadstring(Exec.HttpGet(Config.THEME_URL))()
    local SaveManager  = loadstring(Exec.HttpGet(Config.SAVE_URL))()

    if ThemeManager and type(ThemeManager.SetLibrary) == "function" then
        ThemeManager:SetLibrary(Library)
        -- Ensure the theme manager uses the same settings folder as MainHub.
        -- This unifies theme files across both Key UI and Main Hub.
        if type(ThemeManager.SetFolder) == "function" then
            ThemeManager:SetFolder("BxB.Ware_Setting")
        end
    end

    if SaveManager and type(SaveManager.SetLibrary) == "function" then
        SaveManager:SetLibrary(Library)
        -- Ensure the save manager uses the same settings folder as MainHub.
        -- This unifies config files across both Key UI and Main Hub.
        if type(SaveManager.SetFolder) == "function" then
            SaveManager:SetFolder("BxB.Ware_Setting")
        end
    end

    local autoOk, keydata = KeySystem.TryAutoLogin()
    if autoOk and keydata then
        startMainHub(keydata, Library)
    else
        createKeyUI(Library)
    end
end