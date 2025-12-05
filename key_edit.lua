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
        MAINHUB_URL     = "https://raw.githubusercontent.com/B-O-O-Ml/BxB.ware/refs/heads/main/Main_Edit",

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
-- แปลงค่า timestamp / expire จาก JSON ให้เป็น Unix timestamp (number)
-- รองรับ:
-- 1) number (Unix อยู่แล้ว) -> คืนค่าเดิม
-- 2) string แบบ "12/31/2025 00:00:00" หรือ "31/12/25 00:00:00"
--    ใช้ตัวคั่น / หรือ : ระหว่างวัน/เดือน/ปี ได้ เช่น "12:31:2025 00:00:00"
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

    -- ตัดช่องว่างหัวท้าย + normalize space
    raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")

    local year, month, day
    local hour, min, sec

    -- รูปแบบหลัก:  MM/DD/YY HH:MM:SS หรือ DD/MM/YY HH:MM:SS
    -- ใช้ / หรือ : เป็นตัวคั่นระหว่างวัน/เดือน/ปี ได้
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
        -- เผื่ออนาคต ถ้าอยากใช้ YYYY-MM-DD HH:MM:SS
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
-- Helper: แปลง scriptinfo JSON/raw -> status, text
----------------------------------------------------------------
local function parseScriptInfoBody(body)
    if type(body) ~= "string" or body == "" then
        return "unknown", "No script info data."
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not ok or type(decoded) ~= "table" then
        -- ไม่ใช่ JSON → ใช้ทั้งก้อนเป็นข้อความดิบ
        return "online", body
    end

    local status = decoded.status or decoded.state or "online"
    local lines = {}

    -- header / title / version
    if decoded.title or decoded.name then
        table.insert(lines, string.format("<b>%s</b>", decoded.title or decoded.name))
    end
    if decoded.version then
        table.insert(lines, string.format("Version: %s", tostring(decoded.version)))
    end
    if decoded.author then
        table.insert(lines, string.format("Author: %s", tostring(decoded.author)))
    end
    if decoded.updated_at or decoded.last_update then
        table.insert(lines, string.format("Updated at: %s", tostring(decoded.updated_at or decoded.last_update)))
    end

    -- executors / games / tags ฯลฯ
    local function appendList(label, arr)
        if type(arr) ~= "table" or #arr == 0 then
            return
        end
        local buf = {}
        for _, v in ipairs(arr) do
            table.insert(buf, tostring(v))
        end
        table.insert(lines, string.format("%s: %s", label, table.concat(buf, ", ")))
    end

    appendList("Supported executors", decoded.executors or decoded.supported_executors)
    appendList("Supported games", decoded.games or decoded.supported_games)
    appendList("Tags", decoded.tags)

    -- description / info / notes (ใช้ครบทุกบรรทัด)
    local function appendLines(arr)
        if type(arr) ~= "table" then
            return
        end
        for _, v in ipairs(arr) do
            table.insert(lines, tostring(v))
        end
    end

    if type(decoded.description) == "string" then
        table.insert(lines, "")
        table.insert(lines, decoded.description)
    end

    appendLines(decoded.lines)
    appendLines(decoded.info)
    appendLines(decoded.notes)

    if #lines == 0 then
        -- ไม่เจอ field อะไรที่ใช้ได้ → แสดง JSON ทั้งก้อน
        return status, body
    end

    return status, table.concat(lines, "\n")
end

----------------------------------------------------------------
-- Helper: แปลง changelog JSON/raw -> status, text
----------------------------------------------------------------
local function parseChangelogBody(body)
    if type(body) ~= "string" or body == "" then
        return "unknown", "No changelog data."
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not ok or type(decoded) ~= "table" then
        -- ไม่ใช่ JSON → ใช้ข้อความดิบ
        return "online", body
    end

    local status = decoded.status or decoded.state or "online"
    local lines = {}

    local entries = decoded.entries or decoded.changelog or decoded.logs
    if type(entries) ~= "table" then
        -- ไม่มี entries → แสดง JSON ดิบ
        return status, body
    end

    -- วนทุกเวอร์ชัน ไม่ตัดจำนวน
    for _, ent in ipairs(entries) do
        local ver   = ent.version or ent.tag or "Unknown"
        local date  = ent.date or ent.released_at or "Unknown date"
        local title = ent.title or ""

        table.insert(lines, string.format("<b>Version %s</b> (%s)", tostring(ver), tostring(date)))
        if title ~= "" then
            table.insert(lines, "  " .. tostring(title))
        end

        local function addSection(label, arr)
            if type(arr) ~= "table" or #arr == 0 then
                return
            end
            table.insert(lines, "  " .. label .. ":")
            for _, v in ipairs(arr) do
                table.insert(lines, "    - " .. tostring(v))
            end
        end

        addSection("Added",   ent.added)
        addSection("Changed", ent.changed)
        addSection("Fixed",   ent.fixed)
        addSection("Removed", ent.removed)

        table.insert(lines, "") -- เว้นบรรทัดก่อน version ถัดไป
    end

    if #lines == 0 then
        return status, body
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

-- แปลง expire จากหลายรูปแบบให้เป็น unix timestamp
local function getExpireTimestamp(remoteRecord)
    if not remoteRecord then
        return nil
    end

    -- รองรับทั้ง numeric / string field หลายชื่อ
    local raw =
        remoteRecord.expire
        or remoteRecord.expire_at
        or remoteRecord.expire_unix
        or remoteRecord.expires_at

    -- ถ้าเลขอยู่แล้วก็ใช้เลย
    if typeof(raw) == "number" then
        return raw
    end

    -- ถ้า string ให้ใช้ parseTimeField (รองรับ "MM/DD/YY HH:MM:SS" และรูปแบบอื่น ๆ ที่คุณรองรับใน parseTimeField)
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
    timestamp = parseTimeField(remoteRecord.timestamp or remoteRecord.created_at),
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

--[[ 
    HWID check แบบใหม่: รองรับ free key (ไม่ bind HWID)

    เงื่อนไขที่ถือว่า "ไม่ผูก HWID" (free key):
    - remoteRecord.bind_hwid == false
    - หรือ remoteRecord.hwid_mode == "none"
    - หรือไม่มี hwid_hash / เป็น "" 

    กรณีอื่น ๆ -> ถือว่ายังผูก HWID ตามปกติ
--]]

local bindHWID = true

if remoteRecord.bind_hwid == false
    or remoteRecord.hwid_mode == "none"
    or remoteRecord.hwid_hash == nil
    or remoteRecord.hwid_hash == "" then

    bindHWID = false
end

if bindHWID 
    and type(remoteRecord.hwid_hash) == "string" 
    and remoteRecord.hwid_hash ~= "" 
    and remoteRecord.hwid_hash ~= hwidHash then

    return false, "HWID mismatch"
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
            bind_hwid = remoteRecord.bind_hwid,  -- อาจเป็น true/false หรือ nil
            timestamp = parseTimeField(remoteRecord.timestamp or remoteRecord.created_at),
            role      = remoteRecord.role or "user",
            expire    = getExpireTimestamp(remoteRecord),
            status    = status,
            note      = note
        }

        -- บันทึกไฟล์ local เก็บเฉพาะ key ตามที่คุณต้องการ
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
            Title = "",
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
            Key = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>',Icon = "key", Description = "<b>Key System & Security</b>"}),
            Info = Window:AddTab({Name = '<b><font color="#FF0000">BxB.ware</font></b>',Icon = "info", Description = "<b>Script info & Changlog</b>"})
        }

        local KeyLeft   = Tabs.Key:AddLeftGroupbox("Key System", "key-round")
        local KeyRight  = Tabs.Key:AddRightGroupbox("Data Base", "database-zap")

        local InfoLeft  = Tabs.Info:AddLeftGroupbox("Script Info", "badge-info")
        local InfoRight = Tabs.Info:AddRightGroupbox("Changlog", "rss")

    ----------------------------------------------------------------
    -- WarningBox: Typewriter effect (ข้อความแนะนำ hub / support / credit)
    ----------------------------------------------------------------

    -- ตั้งค่ากล่อง WarningBox เริ่มต้น
    Tabs.Info:UpdateWarningBox({
        Title = "",
        Text = "",
        IsNormal = true,   -- true = warning style ปกติ, false = error style
        Visible = true,
        LockSize = true,   -- ล็อกขนาด, ไม่ขยายยุบตามข้อความ
    })

    -- ข้อความที่จะวนแสดง (แก้ชื่อเกม/เครดิตได้ตามจริง)
    local WarningMessages = {
        "BxB.ware | Multi-game script  ",
        "Support Executor: \n[PC] Wave, Potassium, Volt, Seliware, Volcano, Xeno \n[MAC] Maxsploit \n[MB-AD] Delta, Codex  |  [MB-IOS] Delta",
        "Support: (ตัวอย่าง) Blox Fruits, Anime, FPS",
        "Credits: Hub by BXMQZ, UI by Obsidian",
        "Discord: discord.gg/yourdiscord"
    }

    -- helper: อัปเดตข้อความใน WarningBox
    local function setWarningText(text)
        Tabs.Info:UpdateWarningBox({
            Title = '<b><font color="#8370FF">BxB.ware</font> | Universal </b>',
            Text = text,
            IsNormal = true,
            Visible = true,
            LockSize = true,
        })
    end

    -- effect: พิมพ์ทีละตัว
    local function typeWrite(text, delayPerChar)
        delayPerChar = delayPerChar or 0.04
        for i = 1, #text do
            local current = string.sub(text, 1, i)
            setWarningText(current)
            task.wait(delayPerChar)
        end
    end

    -- effect: ลบทีละตัว (ย้อนกลับ)
    local function typeDelete(text, delayPerChar)
        delayPerChar = delayPerChar or 0.02
        for i = #text, 0, -1 do
            local current = string.sub(text, 1, i)
            setWarningText(current)
            task.wait(delayPerChar)
        end
    end

    -- เริ่ม loop แบบเบา ๆ ใน thread แยก
    task.spawn(function()
        while true do
            for _, msg in ipairs(WarningMessages) do
                typeWrite(msg, 0.035)   -- พิมพ์ทีละตัว
                task.wait(4)          -- ค้างข้อความเต็ม 1.5 วิ
                typeDelete(msg, 0.02)   -- ลบทีละตัว
                task.wait(0.4)          -- พักก่อนขึ้นข้อความถัดไป
            end
        end
    end)


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
    --KeyLeft:AddLabel("<b>Key System</b>", true)
    KeyLeft:AddLabel('<font color="#ff6666">Do not share your key with others.</font>', true)

    -- Input กล่อง key (ตัวนี้คือจุดสำคัญที่ต้องอ่านจาก Library.Options)
    KeyLeft:AddInput("Obsidian_KeyInput", {
        Text = "",
        Default = "",
        Placeholder = "Paste your key here",
        Numeric = false,
    })
KeyLeft:AddDivider()
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

    -- ปุ่ม Get Key
    KeyLeft:AddButton("Get Key", function()
        local ok, err = Exec.SetClipboard("https://your-key-system-url-here/")
        if ok then
            notify("Copied key URL to clipboard", 3)
        else
            notify("Cannot access clipboard: " .. tostring(err), 4)
        end
    end)
--[[
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
]]

    ----------------------------------------------------------------
    -- 3) Tab "Key": Status Monitor (สั้นแค่ "ชื่อ : สถานะ")
    ----------------------------------------------------------------
    KeyRight:AddLabel("<b>Remote Status</b>", true)
    KeyRight:AddDivider()

    local StatusEntries = {}
    local StatusOrder = {}

    -- สร้าง 1 Label ต่อ 1 แหล่ง (Keydata / MainHub / Script / Changelog)
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

    -- แสดงผลแบบ "Script : Online" สั้น ๆ
    local function setStatus(name, networkOk, statusFlag, statusMsg)
        local entry = StatusEntries[name]
        if not entry then
            return
        end

        local lbl = entry.Label
        if not (lbl and lbl.TextLabel) then
            return
        end

        -- ถ้าไฟล์ไม่มี status ให้ fallback = online/offline ตาม network
        local flag = statusFlag
        if not flag or flag == "" then
            flag = networkOk and "online" or "offline"
        end

        local color = colorForStatusFlag(flag)

        -- ทำให้ตัวแรกเป็นตัวใหญ่ (Online / Offline / Maintenance)
        local prettyFlag = tostring(flag)
        prettyFlag = prettyFlag:sub(1, 1):upper() .. prettyFlag:sub(2):lower()

        local text = string.format(
            "<b>%s</b>: <font color=\"%s\">%s</font>",
            name,
            color,
            prettyFlag
        )

        lbl.TextLabel.RichText = true
        lbl.TextLabel.TextWrapped = false
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

    -- ชื่อที่จะแสดงใน UI (ซ้ายคือ label, ขวาคือ URL/ประเภท)
    addStatusLine("Key",      Config.KEYDATA_URL,    "json")
    addStatusLine("MainHub",  Config.MAINHUB_URL,    "lua")
    addStatusLine("Script",   Config.SCRIPTINFO_URL, "json")
    addStatusLine("Changelog",Config.CHANGELOG_URL,  "json")

    -- ตั้งช่วง auto refresh (วินาที): 60–300 ได้ตามที่คุณชอบ
    local STATUS_REFRESH_INTERVAL = 180 -- 3 นาที

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

                -- statusMsg ไม่ถูกใช้ใน UI แล้ว แต่ยังส่งเข้ามาเผื่ออยากเอาไปใช้ทีหลัง
                setStatus(name, networkOk, statusFlag, statusMsg)
            end)
        end
    end
--[[
    KeyRight:AddButton("Refresh Status", function()
        refreshStatus()
    end)
]]
    -- เรียกครั้งแรก
    refreshStatus()

    -- Auto-refresh ทุก STATUS_REFRESH_INTERVAL วินาที
    task.spawn(function()
        while true do
            task.wait(STATUS_REFRESH_INTERVAL)
            refreshStatus()
        end
    end)

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
--[[
    addRichLabel(InfoLeft, "<i>Loading script info...</i>")
    addRichLabel(InfoRight, "<i>Loading changelog...</i>")
]]
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
            notify("[Obsidian] scriptinfo error: " .. tostring(err), 3)
            return
        end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok or type(decoded) ~= "table" then
            addRichLabel(InfoLeft, "<font color=\"#ff5555\">Invalid scriptinfo.json</font>")
            warn("[Obsidian] scriptinfo decode error: " .. tostring(decoded))
            notify("[Obsidian] scriptinfo decode error: " .. tostring(decoded), 3)
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
            notify("[Obsidian] changelog error: " .. tostring(err), 3)
            return
        end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok or type(decoded) ~= "table" then
            addRichLabel(InfoRight, "<font color=\"#ff5555\">Invalid changelog.json</font>")
            warn("[Obsidian] changelog decode error: " .. tostring(decoded))
            notify("[Obsidian] changelog decode error: " .. tostring(decoded), 3)
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
