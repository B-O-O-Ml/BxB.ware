-- Main_Hub.lua
-- แนะนำ: เซฟไฟล์นี้บน GitHub raw แล้วชี้ Config.MAINHUB_URL มาที่ไฟล์นี้

----------------------------------------------------------------
-- Services / Locals
----------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")

----------------------------------------------------------------
-- Config (ใส่ URL จริงตาม Key UI ของคุณ)
----------------------------------------------------------------
local Config = {
    LIBRARY_URL      = "https://raw.githubusercontent.com/....../Library.lua",      -- TODO: แก้เป็นของจริง
    THEME_URL        = "https://raw.githubusercontent.com/....../ThemeManager.lua", -- TODO
    SAVEMANAGER_URL  = "https://raw.githubusercontent.com/....../SaveManager.lua",  -- TODO

    CONFIG_FOLDER    = "BxB.ware",
    CONFIG_FILE      = "BxB_Universal_Config.json"
}

----------------------------------------------------------------
-- HWID / Hash (ให้คุณ copy มาจาก Key UI เพื่อให้ hash ตรงกัน)
----------------------------------------------------------------

-- TODO: copy ฟังก์ชัน secureHWIDHash, rotl32 และส่วนที่ใช้ bit32 จาก Key UI มาวางตรงนี้
-- ตัวอย่าง placeholder (ห้ามใช้จริง เพราะจะ hash ไม่ตรง keydata.hwid_hash)
local function secureHWIDHash(str)
    -- ใส่โค้ดเดียวกับ Key UI ตรงนี้
    return str  -- placeholder เฉย ๆ
end

local function getCurrentHWID()
    local ok, clientId = pcall(function()
        return RbxAnalyticsService:GetClientId()
    end)

    if not ok or not clientId then
        warn("[MainHub] Failed to get HWID:", clientId)
        return nil
    end

    return clientId
end

----------------------------------------------------------------
-- Dynamic Token (ต้องตรงกับ Key UI)
----------------------------------------------------------------

local SECRET_SALT = "BxB_SUPER_SECRET_SALT_CHANGE_THIS"  -- ต้อง = secretSalt ฝั่ง Key UI

local function buildExpectedToken()
    -- ใช้ pattern เดียวกับ Key UI
    local datePart = os.date("%Y%m%d")
    return SECRET_SALT .. "_" .. datePart
end

----------------------------------------------------------------
-- Obsidian Loader สำหรับ Main Hub
----------------------------------------------------------------

local function loadObsidian(Exec)
    -- Load Library
    local libSrc = Exec.HttpGet(Config.LIBRARY_URL)
    local libChunk, err = loadstring(libSrc)
    if not libChunk then
        warn("[MainHub] Failed to load Library:", err)
        return nil
    end

    local Library = libChunk()

    -- Load ThemeManager
    local themeSrc = Exec.HttpGet(Config.THEME_URL)
    local themeChunk, err2 = loadstring(themeSrc)
    if not themeChunk then
        warn("[MainHub] Failed to load ThemeManager:", err2)
        return nil
    end

    local ThemeManager = themeChunk()

    -- Load SaveManager
    local saveSrc = Exec.HttpGet(Config.SAVEMANAGER_URL)
    local saveChunk, err3 = loadstring(saveSrc)
    if not saveChunk then
        warn("[MainHub] Failed to load SaveManager:", err3)
        return nil
    end

    local SaveManager = saveChunk()

    return Library, ThemeManager, SaveManager
end

----------------------------------------------------------------
-- Entry Point: จะถูกเรียกจาก Key UI
--   pcall(startFn, Exec, keydata, dynamicToken)
----------------------------------------------------------------
return function(Exec, keydata, dynamicToken)
    ----------------------------------------------------------------
    -- 1) ตรวจ dynamicToken ให้ตรงรูปแบบที่คาดหวัง
    ----------------------------------------------------------------
    local expectedToken = buildExpectedToken()
    if dynamicToken ~= expectedToken then
        warn("[MainHub] Invalid dynamic token! Loader mismatch or wrong date.")
        return
    end

    ----------------------------------------------------------------
    -- 2) ตรวจรูปแบบ keydata เบื้องต้น
    ----------------------------------------------------------------
    if type(keydata) ~= "table" or type(keydata.key) ~= "string" then
        warn("[MainHub] Invalid keydata structure")
        return
    end

    -- ตัวอย่าง field ที่คาดหวัง (แล้วแต่ที่คุณใช้ใน Key UI)
    -- keydata.key        : string
    -- keydata.hwid_hash  : string
    -- keydata.role       : "user"/"premium"/"staff"/"owner"
    -- keydata.expire_ts  : timestamp หมดอายุ (optional)
    -- keydata.status     : "active"/"banned"/ฯลฯ (optional)

    ----------------------------------------------------------------
    -- 3) (ตัวเลือก) Re-check HWID จากเครื่องจริง
    --    ตรงนี้จะทำงานได้ต้อง copy secureHWIDHash จาก Key UI มาแทน placeholder ด้านบน
    ----------------------------------------------------------------
    local hwid = getCurrentHWID()
    if not hwid then
        warn("[MainHub] Cannot verify HWID")
        return
    end

    local currentHash = secureHWIDHash(hwid)

    if keydata.hwid_hash and currentHash and keydata.hwid_hash ~= currentHash then
        warn("[MainHub] HWID mismatch: key is not bound to this device")
        return
    end

    ----------------------------------------------------------------
    -- 4) (ตัวเลือก) ตรวจ role / expire / status เพิ่มเติม
    ----------------------------------------------------------------
    -- ตัวอย่าง: ถ้ามี expire_ts เป็น timestamp วินาที
    -- local now = os.time()
    -- if keydata.expire_ts and now > keydata.expire_ts then
    --     warn("[MainHub] Key expired")
    --     return
    -- end
    --
    -- if keydata.status and keydata.status ~= "active" then
    --     warn("[MainHub] Key status is not active:", keydata.status)
    --     return
    -- end

    ----------------------------------------------------------------
    -- 5) โหลด Obsidian Library สำหรับ Main Hub UI
    ----------------------------------------------------------------
    local Library, ThemeManager, SaveManager = loadObsidian(Exec)
    if not Library then
        return
    end

    -- ตั้งค่าเบื้องต้น (ตัวอย่าง)
    local window = Library:CreateWindow({
        Title = "BxB.ware | Universal Hub",
        Center = true,
        AutoShow = true,
        TabPadding = 8,
        MenuFadeTime = 0.2,
        Size = UDim2.fromOffset(650, 400),
        NoResize = false,
        ShowSideBar = true
    })

    -- คุณสามารถใช้ keydata.role มาคุมสิทธิ์ตรงนี้ได้
    -- ตัวอย่าง: Tab หลัก ๆ
    local tabHome      = window:AddTab("Home")
    local tabUniversal = window:AddTab("Universal")
    local tabSettings  = window:AddTab("Settings")

    -- แค่ตัวอย่าง groupbox/label เปิดหัว
    local gbInfo = tabHome:AddLeftGroupbox("Key Info")
    gbInfo:AddLabel(("Key: %s"):format(keydata.key or "N/A"))
    gbInfo:AddLabel(("Role: %s"):format(keydata.role or "user"))
    gbInfo:AddLabel(("HWID Hash: %s"):format(keydata.hwid_hash or "N/A"))

    -- TODO: เพิ่มฟังก์ชัน Universal ต่าง ๆ ใน tabUniversal
    -- TODO: ใส่ ThemeManager/SaveManager ใน tabSettings

    -- ตัวอย่าง hook Theme/Save (ตาม pattern เดิมของ Obsidian/Example)
    if ThemeManager then
        ThemeManager:SetLibrary(Library)
        ThemeManager:LoadDefault() -- หรือ ThemeManager:ApplyToTab(...)
    end

    if SaveManager then
        SaveManager:SetLibrary(Library)
        SaveManager:BuildConfigSection(tabSettings)
    end

    -- จากตรงนี้ไป คุณค่อยเติมฟังก์ชัน Universal / ESP / Tools ตามที่ต้องการ
end
