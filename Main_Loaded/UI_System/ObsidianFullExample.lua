-- Example_All.lua
-- ตัวอย่าง Obsidian Library แบบ “ครบทุกอย่าง” สำหรับศึกษาโครงสร้าง
-- ใช้กับ Library.lua / ThemeManager.lua / SaveManager.lua ตัวจริงจาก Obsidian

--[[
อ่านสรุปเมธอด / options ด้านบนไฟล์นี้ (ถูกย่อไว้แล้ว)
--]]

--========================================================
-- 1. โหลด Library + Addons (จาก raw GitHub)
--========================================================

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- shorthand lookup
local Options = Library.Options   -- เก็บ references ของทุก Option (Input, Slider, Dropdown ฯลฯ)
local Toggles = Library.Toggles   -- เก็บ references ของทุก Toggle

--========================================================
-- 2. ปรับ DPI / MinSize เพื่อ mobile-friendly
--========================================================

-- Library.IsMobile ถูก set จากภายใน Library แล้ว (ตาม UserInputService platform)
if Library.IsMobile then
    Library.DPIScale = 1.1      -- ขยายทุกอย่าง ~110% ให้กดง่ายขึ้นบนมือถือ
    Library.MinSize = Vector2.new(480, 260) -- สูงสุดต่ำสุดเตี้ยลงหน่อยสำหรับจอเล็ก
else
    Library.DPIScale = 1        -- desktop ปกติ
    Library.MinSize = Vector2.new(480, 360)
end

-- ปรับ corner radius ทั่ว UI ให้โค้งกำลังดี
Library.CornerRadius = 4

--========================================================
-- 3. สร้าง Window หลัก (ใส่ options ครบ พร้อมคอมเมนต์)
--========================================================

local Window = Library:CreateWindow({
    -- แสดงบน title bar
    Title = "My Universal Hub",         -- ชื่อสคริปต์ของคุณ
    Footer = "Example_All.lua v1.0",    -- ข้อความเล็กด้านล่าง

    -- Icon / Background
    Icon = "user",                      -- ชื่อ icon จาก lucide หรือ asset id ก็ได้
    -- BackgroundImage = "rbxassetid://1234567890", -- ถ้าอยากใช้ภาพพื้นหลัง (ปล่อย nil ถ้าไม่ใช้)

    -- ตำแหน่ง / ขนาด
    Position = UDim2.fromOffset(50, 50),-- ใช้เฉพาะถ้า Center = false
    Size = UDim2.fromOffset(720, 600),  -- ขนาดเริ่มต้น (จะถูก scale ตาม DPIScale ภายใน)
    Center = true,                      -- true = ละ Position, ไปกลางจอแทน

    -- การเปิด / ปิด
    AutoShow = true,                    -- true = แสดงทันทีที่สร้าง
    Resizable = true,                   -- true = มี handle resize ขวาล่าง
    ToggleKeybind = Enum.KeyCode.RightControl, -- ปุ่มสำหรับเปิด/ปิดเมนู

    -- การแจ้งเตือน / cursor
    NotifySide = "Right",               -- "Left" หรือ "Right"
    ShowCustomCursor = false,           -- true = ใช้ cursor ของ Obsidian

    -- ฟอนต์หลักของ UI
    Font = Enum.Font.Code,              -- ใช้ code font (Mono) ให้ UI ดูเป็น dev

    -- UI shape
    CornerRadius = 4,                   -- มุมโค้งของทุก element (Library.CornerRadius ก็ถูก sync)

    -- ปุ่มบนมือถือ
    MobileButtonsSide = "Left",         -- วางปุ่ม keybind menu / close ฯลฯ ด้านซ้ายบนมือถือ

    -- Searchbar (ด้านบน window)
    DisableSearch = false,              -- true = ซ่อน searchbar ไปเลย
    SearchbarSize = UDim2.fromScale(1, 1), -- ขนาด searchbar (ใช้เมื่อ DisableSearch = false)
    GlobalSearch = true,                -- true = ค้นทุก tab, false = เฉพาะ tab ปัจจุบัน
    -- NOTE: ถ้า DisableSearch = true → SearchbarSize / GlobalSearch จะไม่มีผล

    -- เมนูเปิดอยู่แล้วยังคลิกเกมได้ไหม
    UnlockMouseWhileOpen = false,       -- true = ไม่ lock mouse (เหมาะกับ key UI บางแบบ)

    -- Sidebar layout / compact
    Compact = Library.IsMobile,         -- ถ้าเป็น mobile ให้เริ่มแบบ compact icon-only
    EnableSidebarResize = true,         -- true = sidebar ลากปรับความกว้างด้วย mouse/ทัชได้
    SidebarMinWidth = 200,              -- กว้างต่ำสุดของ sidebar (ตอนไม่ compact)
    SidebarCompactWidth = 56,           -- กว้างตอน compact (icon-only)
    SidebarCollapseThreshold = 0.45,    -- ถ้าลากต่ำกว่า 45% ของ MinWidth จะ auto compact

    SidebarHighlightCallback = function(Divider, isActive)
        -- callback ตอนลาก hover ที่ divider เพื่อให้เราเปลี่ยนสี/animate เอง
        Divider.BackgroundColor3 = isActive and Library.Scheme.AccentColor or Library.Scheme.OutlineColor
        Divider.BackgroundTransparency = isActive and 0 or 0.4
    end,
})

-- แสดงตัวอย่างการใช้เมธอดของ Window ที่เกี่ยวกับ sidebar
-- (ตรงนี้ทำแค่ demo เฉย ๆ)
task.delay(5, function()
    if not Window then return end

    -- บังคับตั้ง sidebar กว้าง 220 px (จะโดน clamp ด้วย SidebarMinWidth ถ้าต่ำเกิน)
    Window:SetSidebarWidth(220)

    -- สลับ compact mode ผ่านเมธอด
    Window:SetCompact(false) -- ยกเลิก compact ที่เราตั้งจาก config ข้างบน
    Window:ApplyLayout()     -- ให้ window re-layout ใหม่หลังเปลี่ยน
end)

--========================================================
-- 4. สร้าง Tabs + KeyTab
--========================================================

local Tabs = {
    Main = Window:AddTab({
        Name = "Main",
        Icon = "home",
        Description = "Main controls & examples",
    }),

    Visuals = Window:AddTab("Visuals", "eye"),      -- ใช้รูปแบบสั้น (Name, Icon)
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- KeyTab (สำหรับ Key System / หน้าเมนูกลาง)
local KeyTab = Window:AddKeyTab("Key System", "key")

-- ใช้เมธอดของ Tab เป็นตัวอย่าง
Tabs.Main:SetDescription("Main controls, movement, misc examples")
Tabs.Main:SetOrder(1)
Tabs.Visuals:SetOrder(2)
Tabs["UI Settings"]:SetOrder(99) -- เอาไปไว้ท้ายสุด

Tabs.Main:UpdateWarningBox({
    Title = "Demo Warning Box",
    Text = "คุณสามารถใช้ WarningBox นี้สำหรับแจ้งเตือน, errors ฯลฯ",
    IsNormal = true,     -- true = สีแบบ warning ปกติ, false = error style
    Visible = false,     -- เริ่มต้นซ่อน
    LockSize = true,     -- ขนาดไม่ auto เปลี่ยนตามข้อความ (ลองได้)
})

--========================================================
-- 5. กล่องใน Tab: Groupboxes (Left / Right)
--========================================================

-- Tab Main
local MainLeftGroupbox = Tabs.Main:AddLeftGroupbox("Player / Movement", "user")
local MainRightGroupbox = Tabs.Main:AddRightGroupbox("Utilities / Misc", "wrench")

-- Tab Visuals
local VisualsLeftGroupbox = Tabs.Visuals:AddLeftGroupbox("ESP / Visuals", "eye")
local VisualsRightGroupbox = Tabs.Visuals:AddRightGroupbox("View / Media", "monitor")

--========================================================
-- 6. ตัวอย่าง KeyTab (ยังไม่ทำ logic key จริง แค่ UI)
--========================================================

KeyTab:AddLabel({
    Text = "<b>My Script Hub</b> Key System",
    DoesWrap = true,
    Size = 20,
})

KeyTab:AddLabel({
    Text = "โปรดกรอกคีย์ที่ได้รับจากเว็บไซต์ของเรา\n<font color='#ff6666'><b>ห้ามแชร์คีย์กับผู้อื่น</b></font>",
    DoesWrap = true,
})

-- KeyBox แบบ Dynamic: ให้ callback เป็นคนตัดสินว่า success หรือไม่
KeyTab:AddKeyBox(function(success, receivedKey)
    print("[KeyTab Dynamic] Success:", success, "Key:", receivedKey)
    Library:Notify("Dynamic Key Check: " .. tostring(success), 4)
end)

-- KeyBox แบบ Static: ใส่ expected key ตรง ๆ
KeyTab:AddKeyBox("Banana", function(success, receivedKey)
    print("[KeyTab Static] Expected: Banana | Success:", success, "| Got:", receivedKey)
    Library:Notify("Static Key Check: " .. tostring(success), 4)
end)

--========================================================
-- 7. Controls ใน MainLeftGroupbox (Player / Movement)
--========================================================

-- 7.1 Label (RichText on, Size ปรับได้)
local PlayerLabel = MainLeftGroupbox:AddLabel({
    Text = "<b>Player Controls</b>\n<font color='#aaaaaa'>ตัวอย่าง Toggle / Slider / Input</font>",
    DoesWrap = true,
    Size = 18,
})

-- 7.2 Toggle: Enable WalkSpeed
local WalkSpeedToggle = MainLeftGroupbox:AddToggle("WalkSpeedToggle", {
    Text = "Enable WalkSpeed override",
    Default = false,
    Tooltip = "เปิดแล้วใช้ค่า WalkSpeed จาก slider ด้านล่าง",
    Risky = false,       -- true = แสดงสีแดงเตือน risky
})

-- Keybind ที่ห้อยกับ Toggle
local WalkSpeedKeybind = WalkSpeedToggle:AddKeyPicker("WalkSpeedKeybind", {
    Text = "WalkSpeed Key",
    Default = "F",
    Mode = "Toggle",     -- "Toggle" | "Hold" | "Always" หรือ custom
    SyncToggleState = true, -- กด key แล้ว sync กับ toggle state
})

-- ColorPicker ที่ห้อยกับ Toggle (ตัวอย่าง)
local WalkSpeedColorPicker = WalkSpeedToggle:AddColorPicker("WalkSpeedColor", {
    Default = Color3.fromRGB(0, 170, 255),
    Title = "WalkSpeed highlight color",
})

-- Slider สำหรับ WalkSpeed
local WalkSpeedSlider = MainLeftGroupbox:AddSlider("WalkSpeedValue", {
    Text = "WalkSpeed",
    Default = 16,
    Min = 8,
    Max = 60,
    Rounding = 0,
    Suffix = " stud/s",
    Tooltip = "ค่าความเร็วเดินของ player",
})

-- Input: ใช้กรอก JumpPower
local JumpPowerInput = MainLeftGroupbox:AddInput("JumpPowerValue", {
    Text = "JumpPower",
    Default = "50",
    Numeric = true,          -- true = รับแต่ตัวเลข
    Finished = true,         -- เรียก callback ตอนกด Enter หรือ focus ออก
    ClearTextOnFocus = false,
    Placeholder = "50",
    Tooltip = "กำหนด JumpPower ของ player",
})

-- Toggle: Infinite Jump
local InfiniteJumpToggle = MainLeftGroupbox:AddToggle("InfiniteJump", {
    Text = "Infinite Jump",
    Default = false,
    Tooltip = "ให้กระโดดได้เรื่อย ๆ",
})

MainLeftGroupbox:AddDivider() -- เส้นแบ่ง (ไม่มี options)

-- Callback ผ่าน registry (แนะนำของ Obsidian)
Toggles.WalkSpeedToggle:OnChanged(function(state)
    print("[WalkSpeedToggle] ->", state)
end)

Options.WalkSpeedValue:OnChanged(function(value)
    print("[WalkSpeedSlider] ->", value)
end)

Options.JumpPowerValue:OnChanged(function(value)
    print("[JumpPower Input] ->", value)
end)

Toggles.InfiniteJump:OnChanged(function(state)
    print("[InfiniteJump] ->", state)
end)

Options.WalkSpeedKeybind:OnChanged(function()
    print("[WalkSpeed Keybind changed]", Options.WalkSpeedKeybind.Value, Options.WalkSpeedKeybind.Mode)
end)

--========================================================
-- 8. Controls ใน MainRightGroupbox (Utilities / Misc)
--========================================================

MainRightGroupbox:AddLabel({
    Text = "<b>Utilities</b>",
    Size = 18,
})

-- Button พื้นฐาน
local MainButton = MainRightGroupbox:AddButton({
    Text = "Print Hello",
    Func = function()
        print("[MainButton] Hello from Obsidian!")
        Library:Notify("Hello from Obsidian!", 3)
    end,
    Tooltip = "ปุ่มตัวอย่างธรรมดา",
})

-- Sub Button
MainButton:AddButton({
    Text = "Sub Button",
    Func = function()
        print("[SubButton] Clicked")
        Library:Notify("Sub Button Clicked", 3)
    end,
})

-- Dropdown ตัวอย่าง
local ModeDropdown = MainRightGroupbox:AddDropdown("DemoMode", {
    Text = "Demo Mode",
    Values = { "Legit", "Rage", "AFK" },
    Default = "Legit",
    Multi = false,
    Searchable = true,
    Tooltip = "โหมดตัวอย่าง",
})

Options.DemoMode:OnChanged(function()
    print("[DemoMode] Selected:", Options.DemoMode.Value)
end)

-- Input + Notify Sound example
local SoundInput = MainRightGroupbox:AddInput("NotifySound", {
    Text = "Notification Sound ID",
    Placeholder = "rbxassetid://",
    Default = "",
    Tooltip = "ใส่ sound id ถ้าคุณจะใช้ sound กับ Library:Notify",
})

Options.NotifySound:OnChanged(function(text)
    print("[NotifySound] ->", text)
end)

--========================================================
-- 9. Visuals Tab (ESP / Viewport / Media)
--========================================================

VisualsLeftGroupbox:AddLabel({
    Text = "<b>ESP Settings</b>",
    Size = 18,
})

local ESPEnabled = VisualsLeftGroupbox:AddToggle("ESPEnabled", {
    Text = "Enable ESP",
    Default = false,
    Tooltip = "เปิด / ปิด ระบบ ESP (logic คุณเขียนเอง)",
})

local ESPDistance = VisualsLeftGroupbox:AddSlider("ESPDistance", {
    Text = "ESP Distance",
    Default = 200,
    Min = 50,
    Max = 500,
    Rounding = 0,
    Suffix = " studs",
})

local ESPColorPicker = ESPEnabled:AddColorPicker("ESPColor", {
    Title = "ESP Color",
    Default = Color3.fromRGB(255, 255, 0),
})

Options.ESPEnabled:OnChanged(function(state)
    print("[ESPEnabled] ->", state)
end)

Options.ESPDistance:OnChanged(function(value)
    print("[ESPDistance] ->", value)
end)

Options.ESPColor:OnChanged(function()
    print("[ESPColor] ->", Options.ESPColor.Value)
end)

-- Viewport example (แสดง object 3D)
local dummyPart = Instance.new("Part")
dummyPart.Color = Color3.fromRGB(255, 0, 0)
dummyPart.Size = Vector3.new(4, 4, 4)

local cam = Instance.new("Camera")

local Viewport = VisualsRightGroupbox:AddViewport("DemoViewport", {
    Object = dummyPart,
    Camera = cam,
    Interactive = true,
    AutoFocus = true,
    Height = 200,
    Clone = true, -- true = clone object เข้า viewport
})

-- Image example
VisualsRightGroupbox:AddImage("DemoImage", {
    Image = "rbxassetid://135666356081915",
    Height = 140,
    BackgroundTransparency = 1,
})

-- Video example
VisualsRightGroupbox:AddVideo("DemoVideo", {
    Video = "rbxassetid://1234567890",
    Looped = true,
    Playing = false,
    Volume = 0.5,
    Height = 180,
})

-- UIPassthrough (ถ้าคุณมี Frame custom ของตัวเอง)
-- local customFrame = Instance.new("Frame")
-- customFrame.Size = UDim2.fromOffset(200, 50)
-- customFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
-- VisualsRightGroupbox:AddUIPassthrough("CustomUI", {
--     Instance = customFrame,
--     Height = 60,
-- })

--========================================================
-- 10. UI Settings Tab: ThemeManager + SaveManager
--========================================================

-- ThemeManager setup
ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("MyScriptHub") -- โฟลเดอร์สำหรับ themes

-- ให้ ThemeManager เติม groupbox เองใน Tab "UI Settings"
ThemeManager:ApplyToTab(Tabs["UI Settings"])

-- SaveManager setup
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()            -- ไม่บันทึก theme ลง config
SaveManager:SetIgnoreIndexes({ "MenuKeybind" }) -- ตัวอย่าง ignore index สมมุติ

-- โฟลเดอร์โครงสร้าง config:
SaveManager:SetFolder("MyScriptHub/specific-game")
SaveManager:SetSubFolder("Lobby")     -- ถ้าเกมมีหลาย place

-- ให้ SaveManager สร้าง UI Config (load/save/delete/autoload) ใน Tab UI Settings
SaveManager:BuildConfigSection(Tabs["UI Settings"])

-- โหลด autoload config ถ้ามี
SaveManager:LoadAutoloadConfig()

--========================================================
-- 11. Notifications + Watermark + Keybind Menu demo
--========================================================

-- Watermark
Library:SetWatermarkVisibility(true)
Library:SetWatermark("My Universal Hub | Loading...")

-- ให้ watermark อัปเดต FPS / Ping แบบง่าย ๆ
do
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")

    local frameTimer = tick()
    local frameCount = 0
    local fps = 60

    RunService.RenderStepped:Connect(function()
        frameCount += 1
        if tick() - frameTimer >= 1 then
            fps = frameCount
            frameTimer = tick()
            frameCount = 0
        end

        local ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
        Library:SetWatermark(("My Universal Hub | %s fps | %s ms"):format(fps, ping))
    end)
end

-- Notify ตัวอย่าง (short call)
Library:Notify("Obsidian Example loaded!", 4)

-- Notify แบบ object + methods
local notif = Library:Notify({
    Title = "Example_All",
    Description = "This is a persistent notification",
    Time = 0,          -- 0 = persist จนกว่าจะ Destroy
    Persist = true,
})

task.delay(3, function()
    if notif then
        notif:ChangeTitle("Updated Title")
        notif:ChangeDescription("Description has been updated")
        notif:ChangeStep(1)     -- ใช้ตอนเป็น progress-based
        task.delay(2, function()
            notif:Destroy()
        end)
    end
end)

-- Keybinds menu: ดู keybind ทั้งหมด
Library.ShowToggleFrameInKeybinds = true  -- แสดงกรอบ toggle ใน keybind menu

--========================================================
-- 12. การจัดการ unload (optional)
--========================================================

Library:OnUnload(function()
    print("Unloaded My Universal Hub")
end)

-- (ตามดีฟอลต์ RightControl จะเป็นปุ่ม toggle menu; SaveManager/ThemeManager จะอยู่ใน UI Settings Tab)
