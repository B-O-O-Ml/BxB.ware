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
        MAINHUB_URL     = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Loaded/Main_Hub.lua",

        KEYDATA_FILE    = "BxB.ware/obsidian_keydata.json",

        KEYCHECK_TOKEN  = "BxB.ware-universal-private-*&^%$#$*#%&@#"
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
        local salt = "OBSIDIAN_HWID_PEPPER_1"
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
        if type(remoteRecord) ~= "table" then
            return nil
        end

        local ts = tonumber(
            remoteRecord.expire
            or remoteRecord.expire_at
            or remoteRecord.expire_unix
            or remoteRecord.expires_at
        )

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
    -- KeySystem core
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

        if type(remoteRecord.hwid_hash) == "string" and remoteRecord.hwid_hash ~= "" then
            if remoteRecord.hwid_hash ~= hwidHash then
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
            timestamp = tonumber(remoteRecord.timestamp) or 0,
            role      = remoteRecord.role or "user",
            expire    = getExpireTimestamp(remoteRecord),
            status    = status,
            note      = note
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

        if type(remoteRecord.hwid_hash) == "string" and remoteRecord.hwid_hash ~= "" then
            if remoteRecord.hwid_hash ~= hwidHash then
                return false, "HWID mismatch"
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
            timestamp = tonumber(remoteRecord.timestamp) or 0,
            role      = remoteRecord.role or "user",
            expire    = getExpireTimestamp(remoteRecord),
            status    = status,
            note      = note
        }

        saveLocalKeydata(key)

        return true, keydata
    end

    ----------------------------------------------------------------
    -- Main Hub Loader
    ----------------------------------------------------------------
    local function startMainHub(keydata, Library)
        local src = Exec.HttpGet(Config.MAINHUB_URL)

        local chunk, err = loadstring(src)
        if not chunk then
            warn("[Obsidian] Failed to load MainHub.lua: " .. tostring(err))
            return
        end

        local ok, startFn = pcall(chunk)
        if not ok then
            warn("[Obsidian] Error while executing MainHub chunk: " .. tostring(startFn))
            return
        end

        if type(startFn) ~= "function" then
            warn("[Obsidian] MainHub.lua must return a function(Exec, keydata, keycheck)")
            return
        end

        local success, err2 = pcall(startFn, Exec, keydata, Config.KEYCHECK_TOKEN)
        if not success then
            warn("[Obsidian] MainHub runtime error: " .. tostring(err2))
        end

        if Library and type(Library.Unload) == "function" then
            pcall(function()
                Library:Unload()
            end)
        end
    end

    ----------------------------------------------------------------
    -- Key UI (Obsidian)
    ----------------------------------------------------------------
 -- แทนที่ฟังก์ชันเดิมทั้งหมดใน Key_Loaded.lua ด้วยฟังก์ชันนี้
local function createKeyUI(Library)
    local HttpService = game:GetService("HttpService")

    -- เอา reference ของ Options ตามสไตล์ Obsidian
    local Options = Library.Options

    local function notify(msg, dur)
        if Library and type(Library.Notify) == "function" then
            Library:Notify(tostring(msg), dur or 3)
        else
            warn("[Obsidian] " .. tostring(msg))
        end
    end


        local Window = Library:CreateWindow({
            Title = "","GTTT",
            Center = true,
                AutoShow = true,
                Icon = "icon-rss",
                CornerRadius = 6,
                ShowCustomCursor = true,
                Resizable = false, 
                Size = UDim2.fromOffset(550, 300),
            DisableSearch = true,   
            Compact = true,
        })

        local Tabs = {
            Key = Window:AddTab("", "key"),
            Info = Window:AddTab("", "info")
        }

        local KeyLeft   = Tabs.Key:AddLeftGroupbox("Key System", "key-round")
        local KeyRight  = Tabs.Key:AddRightGroupbox("", "database-zap")

        local InfoLeft  = Tabs.Info:AddLeftGroupbox("", "badge-info")
        local InfoRight = Tabs.Info:AddRightGroupbox("", "rss")

        ----------------------------------------------------------------
        -- Login cooldown guard
        ----------------------------------------------------------------
----------------------------------------------------------------
    -- 1) Login Cooldown Guard
    ----------------------------------------------------------------
    local LoginGuard = {
        FailCount = 0,
        CooldownUntil = 0
    }

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
    KeyLeft:AddLabel("<b>Key System</b>", true)
    KeyLeft:AddLabel('<font color="#ff6666">ห้ามแชร์คีย์ของคุณกับผู้อื่น</font>', true)
    KeyLeft:AddDivider()

    -- Input กล่อง key (ตัวนี้คือจุดสำคัญที่ต้องอ่านจาก Library.Options)
    KeyLeft:AddInput("Obsidian_KeyInput", {
        Text = "Key",
        Default = "",
        Placeholder = "Paste your key here",
        Numeric = false,
        Finished = false,         -- ไม่จำเป็นต้องใช้ Finished
        ClearTextOnFocus = false, -- ไม่ล้างอัตโนมัติ
    })

    -- helper ใช้ Options ตาม pattern ของ Obsidian
    local function getKeyFromInput()
        local obj = Options and Options.Obsidian_KeyInput
        local val = obj and obj.Value

        if type(val) ~= "string" then
            val = val and tostring(val) or ""
        end

        -- debug ถ้าอยากเช็ค
        -- print("[KeyUI] getKeyFromInput =", val)

        return val
    end

    local function setKeyInput(text)
        local obj = Options and Options.Obsidian_KeyInput
        if obj and type(obj.SetValue) == "function" then
            obj:SetValue(tostring(text or ""))
        end
    end

    -- ปุ่ม Get Key
    KeyLeft:AddButton("Get Key", function()
        local ok, err = Exec.SetClipboard("https://your-key-system-url-here/")
        if ok then
            notify("Copied key URL to clipboard", 3)
        else
            notify("Cannot access clipboard: " .. tostring(err), 4)
        end
    end)

    -- ปุ่ม Paste from clipboard
    KeyLeft:AddButton("Paste from clipboard", function()
        local clip = select(1, Exec.GetClipboard())
        if type(clip) == "string" and clip ~= "" then
            setKeyInput(clip)
            notify("Pasted key from clipboard", 3)
        else
            notify("Clipboard is empty / not available", 3)
        end
    end)

    -- ปุ่ม Logout / เคลียร์ key ในไฟล์ (เก็บแค่ key ตามที่แก้ล่าสุด)
    KeyLeft:AddButton("Logout / Clear Local Key", function()
        local ok, err = Exec.WriteFile(Config.KEYDATA_FILE, "")
        if ok then
            notify("Cleared local key. You can enter a new key now.", 4)
        else
            notify("Failed to clear local key: " .. tostring(err), 4)
        end
    end)

    -- ปุ่ม Login
    KeyLeft:AddButton("Login / Check Key", function()
        local allowed, remain = canAttemptLogin()
        if not allowed then
            notify("Too many attempts. Please wait " .. tostring(math.ceil(remain)) .. "s.", 4)
            return
        end

        local key = getKeyFromInput()
        -- trim หน้าหลัง
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

    ----------------------------------------------------------------
    -- 3) Tab "Key" ฝั่งขวา: Status Monitor (อ่าน config จากไฟล์จริง)
    --    แก้ให้ใช้ label สั้น ๆ แยกบรรทัด ไม่ใช้ label ยักษ์ทีเดียว
    ----------------------------------------------------------------
    KeyRight:AddLabel("<b>Remote Status</b>", true)
    KeyRight:AddDivider()

    local StatusEntries = {}
    local StatusOrder = {}

    local function addStatusLine(name, url, kind)
        -- label หนึ่งแถวสั้น ๆ (ไม่ใช้หลายบรรทัดแบบยาว)
        local label = KeyRight:AddLabel(
            string.format("<b>%s</b>: <font color=\"#aaaaaa\">checking...</font>", name),
            true
        )

        StatusEntries[name] = {
            Name  = name,
            Url   = url,
            Kind  = kind or "json",
            Label = label
        }
        table.insert(StatusOrder, name)
    end

    local function colorForStatusFlag(flag)
        flag = flag and string.lower(flag) or ""

        if flag == "online" or flag == "active" then
            return "#55ff55"
        end
        if flag == "maintenance" or flag == "degraded" then
            return "#ffcc66"
        end
        if flag == "offline" or flag == "disabled" then
            return "#ff5555"
        end

        return "#aaaaaa"
    end

    local function setStatus(name, networkOk, statusFlag, statusMsg)
        local entry = StatusEntries[name]
        if not entry then
            return
        end

        local lbl = entry.Label
        if not (lbl and lbl.TextLabel) then
            return
        end

        local netColor = networkOk and "#55ff55" or "#ff5555"
        local netText  = networkOk and "Online" or "HTTP error"

        local statusText  = statusFlag or "unknown"
        local statusColor = colorForStatusFlag(statusFlag)

        -- แก้ให้ข้อความสั้น ๆ บรรทัดเดียว (max 2: status + msg)
        local text = string.format(
            "<b>%s</b>: <font color=\"%s\">%s</font> | Status: <font color=\"%s\">%s</font>",
            name,
            netColor,
            netText,
            statusColor,
            statusText
        )

        if statusMsg and statusMsg ~= "" then
            text = text .. string.format(" | <font color=\"#888888\">%s</font>", statusMsg)
        end

        lbl.TextLabel.RichText = true
        lbl.TextLabel.Text = text
    end

    local function parseJsonStatus(body)
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok or type(decoded) ~= "table" then
            return nil, "Invalid JSON"
        end

        local status = decoded.status
        local msg    = decoded.status_message

        local meta = decoded.meta
        if type(meta) == "table" then
            status = status or meta.status
            msg    = msg or meta.status_message
        end

        if type(status) ~= "string" then status = nil end
        if type(msg)    ~= "string" then msg    = nil end

        return { status = status, message = msg }, nil
    end

    local function parseLuaStatus(body)
        local status = body:match("STATUS%s*:%s*([%w_-]+)")
        local msg    = body:match("STATUS_MSG%s*:%s*([^\r\n]+)")
        if status then
            return { status = status, message = msg }, nil
        end
        return nil, nil
    end

    -- เพิ่ม 4 รายการเหมือนเดิม
    addStatusLine("Keydata",    Config.KEYDATA_URL,    "json")
    addStatusLine("MainHub",    Config.MAINHUB_URL,    "lua")
    addStatusLine("ScriptInfo", Config.SCRIPTINFO_URL, "json")
    addStatusLine("Changelog",  Config.CHANGELOG_URL,  "json")

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
                    if info then
                        statusFlag = info.status or statusFlag
                        statusMsg  = info.message or statusMsg
                    elseif jsonErr then
                        statusMsg = "JSON error: " .. tostring(jsonErr)
                    end
                elseif entry.Kind == "lua" then
                    local info = select(1, parseLuaStatus(result))
                    if info then
                        statusFlag = info.status or statusFlag
                        statusMsg  = info.message or statusMsg
                    end
                end

                if not statusFlag then
                    statusFlag = "online"
                end

                setStatus(name, networkOk, statusFlag, statusMsg)
            end)
        end
    end

    KeyRight:AddButton("Refresh Status", function()
        refreshStatus()
    end)

    refreshStatus() -- auto ครั้งแรก

    ----------------------------------------------------------------
    -- 4) Tab "Info": ScriptInfo + Changelog
    --    เปลี่ยนจาก label ยาวหนึ่งอัน → แตกเป็นหลาย label ไม่ซ้อน
    ----------------------------------------------------------------
    local function addRichLabel(group, text)
        local lbl = group:AddLabel(text, true)
        if lbl and lbl.TextLabel then
            lbl.TextLabel.RichText = true
        end
        return lbl
    end

    addRichLabel(InfoLeft, "<i>Loading script info...</i>")
    addRichLabel(InfoRight, "<i>Loading changelog...</i>")

    local function fetchText(url)
        local ok, body = pcall(Exec.HttpGet, url)
        if not ok or type(body) ~= "string" then
            return nil, body
        end
        return body
    end

    -- render scriptinfo: แตกเป็น label ย่อย ๆ
    local function renderScriptInfo(data)
        InfoLeft:AddDivider()
        addRichLabel(InfoLeft, string.format("<b>Name</b>: %s", data.name or "N/A"))
        addRichLabel(InfoLeft, string.format("<b>Version</b>: %s", data.version or "N/A"))
        addRichLabel(InfoLeft, string.format("<b>Author</b>: %s", data.author or "N/A"))

        if data.status then
            addRichLabel(InfoLeft, string.format("<b>Status</b>: %s", data.status))
        end
        if data.last_update then
            addRichLabel(InfoLeft, string.format("<b>Last Update</b>: %s", data.last_update))
        end

        if type(data.executors) == "table" and #data.executors > 0 then
            InfoLeft:AddDivider()
            addRichLabel(InfoLeft, "<b>Supported executors</b>:")
            addRichLabel(InfoLeft, table.concat(data.executors, ", "))
        end

        if data.discord then
            InfoLeft:AddDivider()
            addRichLabel(InfoLeft, string.format("<b>Discord</b>: %s", data.discord))
        end
        if data.website then
            addRichLabel(InfoLeft, string.format("<b>Website</b>: %s", data.website))
        end

        if data.description then
            InfoLeft:AddDivider()
            addRichLabel(InfoLeft, "<b>Description</b>:")
            addRichLabel(InfoLeft, data.description)
        end

        if data.notice then
            InfoLeft:AddDivider()
            addRichLabel(
                InfoLeft,
                string.format('<font color="#ffcc66"><b>Notice</b>:</font> %s', data.notice)
            )
        end
    end

    -- render changelog: แต่ละ entry แยก block, มี label ซ้อนกันเป็นลิสต์
    local function renderChangelog(data)
        local entries = data.entries
        if type(entries) ~= "table" or #entries == 0 then
            addRichLabel(InfoRight, "<i>No changelog entries.</i>")
            return
        end

        for _, entry in ipairs(entries) do
            if type(entry) == "table" then
                InfoRight:AddDivider()

                local version = entry.version or "unknown"
                local date    = entry.date or "unknown"
                local tag     = entry.tag and (" [" .. entry.tag .. "]") or ""

                addRichLabel(InfoRight, string.format("<b>%s</b> - %s%s", version, date, tag))

                local changes = entry.changes
                if type(changes) == "table" then
                    local function addSection(title, list)
                        if type(list) == "table" and #list > 0 then
                            addRichLabel(InfoRight, "  • " .. title .. ":")
                            for _, line in ipairs(list) do
                                addRichLabel(InfoRight, "    - " .. tostring(line))
                            end
                        end
                    end

                    addSection("Added",   changes.Added)
                    addSection("Changed", changes.Changed)
                    addSection("Fixed",   changes.Fixed)
                    addSection("Removed", changes.Removed)
                end
            end
        end
    end

    -- async โหลด scriptinfo
    task.spawn(function()
        local body, err = fetchText(Config.SCRIPTINFO_URL)
        if not body then
            addRichLabel(InfoLeft, "<font color=\"#ff5555\">Failed to load scriptinfo.json</font>")
            warn("[Obsidian] scriptinfo error: " .. tostring(err))
            return
        end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok or type(decoded) ~= "table" then
            addRichLabel(InfoLeft, "<font color=\"#ff5555\">Invalid scriptinfo.json</font>")
            warn("[Obsidian] scriptinfo decode error: " .. tostring(decoded))
            return
        end

        renderScriptInfo(decoded)
    end)

    -- async โหลด changelog
    task.spawn(function()
        local body, err = fetchText(Config.CHANGELOG_URL)
        if not body then
            addRichLabel(InfoRight, "<font color=\"#ff5555\">Failed to load changelog.json</font>")
            warn("[Obsidian] changelog error: " .. tostring(err))
            return
        end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok or type(decoded) ~= "table" then
            addRichLabel(InfoRight, "<font color=\"#ff5555\">Invalid changelog.json</font>")
            warn("[Obsidian] changelog decode error: " .. tostring(decoded))
            return
        end

        renderChangelog(decoded)
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
    end

    if SaveManager and type(SaveManager.SetLibrary) == "function" then
        SaveManager:SetLibrary(Library)
    end

    local autoOk, keydata = KeySystem.TryAutoLogin()
    if autoOk and keydata then
        startMainHub(keydata, Library)
    else
        createKeyUI(Library)
    end
end
