--[[========================================================
    Obsidian UI Library - Example_Full.lua
    - ใช้ Library.lua / ThemeManager.lua / SaveManager.lua จาก repo เดียวกับ Obsidian
    - ครอบคลุม: Window + Tabs + Groupboxes + Tabboxes + Controls
      (Toggle / Checkbox / Button / Label / Divider / Slider /
       Input / Dropdown (+Multi/Search/DisabledValue/Player/Team) /
       ColorPicker / KeyPicker / KeyTab / UI Settings / DPI / Managers)
========================================================]]--

--// 1) โหลด Library + ThemeManager + SaveManager
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- ชื่อสั้น ๆ สำหรับ registry
local Options = Library.Options   -- สำหรับ controls ที่เก็บค่า (Slider, Input, Dropdown, ColorPicker, KeyPicker ฯลฯ)
local Toggles = Library.Toggles   -- สำหรับ Toggle / Checkbox ทั้งหมด

-- ปรับ behaviour ทั่วไปของ Library
Library.ForceCheckbox = false -- true = ทุก AddToggle จะกลายเป็น checkbox-style บังคับ (ใช้ถ้าชอบ style checkbox)
Library.ShowToggleFrameInKeybinds = true -- แสดง toggle ใน Keybinds UI ด้วย (ดีมากสำหรับ mobile เพราะควบคุมได้จาก keybind menu)

--[[========================================================
    2) สร้าง Window หลัก (ส่วนนี้สำคัญเรื่อง mobile-friendly + options)
========================================================]]--

local Window = Library:CreateWindow({
    -- NOTE: option หลัก ๆ (จาก template Window ของ Library)
    -- Center = true  -> จัด Window ไว้กลางจอ (มัก override Position)
    -- AutoShow = true -> เปิด Window ทันทีหลังสร้าง
    -- Resizable = true -> ให้ผู้ใช้ลากปรับขนาด Window ได้ในเกม
    -- MobileButtonsSide = "Left" / "Right"
    --     -> ปุ่มสำหรับเปิด/ล็อก UI บนขอบจอ (สำคัญบนมือถือ)
    -- ShowCustomCursor = true/false -> ใช้ cursor แบบ Obsidian หรือใช้ cursor Roblox ปกติ
    -- NotifySide = "Left" / "Right" -> ตำแหน่ง notifications
    -- Position / Size -> override ค่า default ถ้าต้องการ
    -- Compact = true/false -> layout กระชับสำหรับจอเล็ก
    -- EnableSidebarResize = true/false -> ลาก sidebar ปรับความกว้างได้

    Title = "Obsidian Example",
    Footer = "version: example_full",
    Icon = 95816097006870,       -- Icon ID (ใช้สไตล์ Lucide icon)
    NotifySide = "Right",        -- ตั้ง default ด้านขวา
    ShowCustomCursor = true,     -- ใช้ cursor ของ Obsidian
    --Center = true,
    --AutoShow = true,
    --Resizable = true,
    --MobileButtonsSide = "Left",
    --Compact = false,
    --EnableSidebarResize = false,
})

-- CALLBACK NOTE:
-- การใส่ Callback ที่ options ตอนสร้าง control (Callback = function(Value) ... end) ใช้ได้
-- แต่การใช้ Options.xxx:OnChanged(...) / Toggles.xxx:OnChanged(...) เป็นวิธีที่ “แยก logic ออกจาก UI” ได้ดีและ maintain ง่ายกว่า

--[[========================================================
    3) สร้าง Tabs หลัก (Main / Key / UI Settings)
========================================================]]--

-- คุณไม่จำเป็นต้องจัดแบบนี้ก็ได้ แค่นี่เป็น pattern ที่อ่านง่าย
-- Icon name = ชื่อ icon จาก https://lucide.dev/ (ใน Obsidian จะ map เป็น image id)
local Tabs = {
    Main        = Window:AddTab("Main", "user"),       -- Tab เนื้อหาหลัก
    Key         = Window:AddKeyTab("Key System"),      -- Tab พิเศษสำหรับ key system
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"), -- Tab ตั้งค่า UI/Theme/Config
}

--[[
-- ตัวอย่าง warning box สำหรับ Tab (Title + Text รองรับ RichText)
local UISettingsTab = Tabs["UI Settings"]

UISettingsTab:UpdateWarningBox({
    Visible = true,
    Title = "Warning",
    Text = "This is a warning box!",
})
]]--

--[[========================================================
    4) Groupbox / Tabbox + Controls พื้นฐาน (Main Tab)
========================================================]]--

-- Groupbox และ Tabbox มี method เหมือนกัน (AddToggle, AddSlider ฯลฯ)
-- ต่างกันที่ Tabbox ต้องเรียกผ่าน TabBox:AddTab("ชื่อ tab ย่อย")
local LeftGroupBox = Tabs.Main:AddLeftGroupbox("Groupbox", "boxes")   -- ฝั่งซ้าย
-- local LeftGroupBox = Window.Tabs.Main:AddLeftGroupbox("Groupbox", "boxes") -- เข้าผ่าน Window.Tabs ก็ได้

--[[ ตัวอย่าง Tabbox (comment ไว้ ถ้าอยากใช้ค่อย uncomment)
local LeftTabBox = Tabs.Main:AddLeftTabbox()
local Tab1 = LeftTabBox:AddTab("Tab 1")
local Tab2 = LeftTabBox:AddTab("Tab 2")
-- Tab1:AddToggle(...), Tab2:AddSlider(...) ฯลฯ
]]--

--[[--------------------------------------------------------
    4.1 Toggle + ColorPickers ที่ chain จาก Toggle
----------------------------------------------------------]]--

LeftGroupBox:AddToggle("MyToggle", {
    Text = "This is a toggle",
    Tooltip = "This is a tooltip",             -- hover ปกติ
    DisabledTooltip = "I am disabled!",        -- hover ตอน Disabled

    Default = true,                            -- ค่าเริ่มต้น
    Disabled = false,                          -- ตัดการใช้งาน control
    Visible = true,                            -- ซ่อน/แสดง
    Risky = false,                             -- true = สีแดง (ใช้เน้นว่าค่าเสี่ยง)

    Callback = function(Value)
        print("[cb] MyToggle changed to:", Value)
    end,
})
    -- chain AddColorPicker จาก toggle ตัวเดิม
    :AddColorPicker("ColorPicker1", {
        Default = Color3.new(1, 0, 0),
        Title = "Some color1",                 -- ชื่อใน popup
        Transparency = 0,                      -- nil หรือ 0..1 (เปิดใช้ปรับความโปร่งใส)

        Callback = function(Value)
            print("[cb] Color changed!", Value)
        end,
    })
    :AddColorPicker("ColorPicker2", {
        Default = Color3.new(0, 1, 0),
        Title = "Some color2",

        Callback = function(Value)
            print("[cb] Color changed!", Value)
        end,
    })

-- ใช้งาน Toggle ผ่าน registry
-- Toggles.MyToggle.Value = ค่า true/false ปัจจุบัน
Toggles.MyToggle:OnChanged(function()
    print("MyToggle changed to:", Toggles.MyToggle.Value)
end)

-- set ค่า toggle ผ่านโค้ด
Toggles.MyToggle:SetValue(false)

-- Checkbox = toggle แบบ checkbox-styled โดยไม่สน Library.ForceCheckbox
LeftGroupBox:AddCheckbox("MyCheckbox", {
    Text = "This is a checkbox",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    Default = true,
    Disabled = false,
    Visible = true,
    Risky = false,

    Callback = function(Value)
        print("[cb] MyCheckbox changed to:", Value)
    end,
})

Toggles.MyCheckbox:OnChanged(function()
    print("MyCheckbox changed to:", Toggles.MyCheckbox.Value)
end)

--[[--------------------------------------------------------
    4.2 Buttons (ปุ่มหลัก + sub button + disabled)
----------------------------------------------------------]]--

-- รูปแบบใหม่: รับ table options
local MyButton = LeftGroupBox:AddButton({
    Text = "Button",
    Func = function()
        print("You clicked a button!")
    end,
    DoubleClick = false,      -- true = ต้องคลิกสองครั้งถึงจะยิง callback

    Tooltip = "This is the main button",
    DisabledTooltip = "I am disabled!",

    Disabled = false,
    Visible = true,
    Risky = false,
})

-- ปุ่มย่อย (sub button) chain จากปุ่มหลัก
local MyButton2 = MyButton:AddButton({
    Text = "Sub button",
    Func = function()
        print("You clicked a sub button!")
    end,
    DoubleClick = true,
    Tooltip = "This is the sub button",
    DisabledTooltip = "I am disabled!",
})

-- ปุ่มที่ disable ตั้งแต่แรก
local MyDisabledButton = LeftGroupBox:AddButton({
    Text = "Disabled Button",
    Func = function()
        print("You somehow clicked a disabled button!")
    end,
    DoubleClick = false,
    Tooltip = "This is a disabled button",
    DisabledTooltip = "I am disabled!",
    Disabled = true,
})

-- NOTE: คุณสามารถ chain Button ได้เช่นกัน
-- LeftGroupBox:AddButton({ Text = "Kill all", Func = ... }):AddButton({ Text = "Kick all", Func = ... })

--[[--------------------------------------------------------
    4.3 Labels / Divider
----------------------------------------------------------]]--

LeftGroupBox:AddLabel("This is a label")

LeftGroupBox:AddLabel("This is a label\n\nwhich wraps its text!", true)

LeftGroupBox:AddLabel("This is a label exposed to Labels", true, "TestLabel")

LeftGroupBox:AddLabel("SecondTestLabel", {
    Text = "This is a label made with table options and an index",
    DoesWrap = true,
})

LeftGroupBox:AddLabel("SecondTestLabel", {
    Text = "This is a label that doesn't wrap it's own text",
    DoesWrap = false,
})

-- Options.TestLabel:SetText("new text")
-- Options.SecondTestLabel:SetText("new text")

-- Divider = เส้นแบ่ง section
LeftGroupBox:AddDivider()

--[[--------------------------------------------------------
    4.4 Slider (ปกติ + custom display)
----------------------------------------------------------]]--

LeftGroupBox:AddSlider("MySlider", {
    Text = "This is my slider!",
    Default = 0,
    Min = 0,
    Max = 5,
    Rounding = 1,         -- ทศนิยมกี่ตำแหน่ง
    Compact = false,      -- true = ซ่อน label title

    Callback = function(Value)
        print("[cb] MySlider was changed! New value:", Value)
    end,

    Tooltip = "I am a slider!",
    DisabledTooltip = "I am disabled!",

    Disabled = false,
    Visible = true,
})

-- อ่านค่า: Options.MySlider.Value
Options.MySlider:OnChanged(function()
    print("MySlider was changed! New value:", Options.MySlider.Value)
end)

Options.MySlider:SetValue(3)

-- Slider แบบมี FormatDisplayValue (custom แสดงข้อความ)
LeftGroupBox:AddSlider("MySlider2", {
    Text = "This is my custom display slider!",
    Default = 0,
    Min = 0,
    Max = 5,
    Rounding = 0,
    Compact = false,

    FormatDisplayValue = function(slider, value)
        if value == slider.Max then
            return "Everything"
        end
        if value == slider.Min then
            return "Nothing"
        end
        -- return nil = ใช้ format default
    end,

    Tooltip = "I am a slider!",
    DisabledTooltip = "I am disabled!",
    Disabled = false,
    Visible = true,
})

--[[--------------------------------------------------------
    4.5 Input / TextBox
----------------------------------------------------------]]--

LeftGroupBox:AddInput("MyTextbox", {
    Default = "My textbox!",
    Numeric = false,          -- true = รับตัวเลขเท่านั้น
    Finished = false,         -- true = callback เฉพาะตอนกด Enter
    ClearTextOnFocus = true,  -- true = เคลียร์ข้อความเวลา focus

    Text = "This is a textbox",
    Tooltip = "This is a tooltip",

    Placeholder = "Placeholder text",

    Callback = function(Value)
        print("[cb] Text updated. New text:", Value)
    end,
})

Options.MyTextbox:OnChanged(function()
    print("Text updated. New text:", Options.MyTextbox.Value)
end)

--[[========================================================
    5) Dropdowns (Right Groupbox บน Main Tab)
========================================================]]--

local DropdownGroupBox = Tabs.Main:AddRightGroupbox("Dropdowns")

-- Dropdown ปกติ
DropdownGroupBox:AddDropdown("MyDropdown", {
    Values = { "This", "is", "a", "dropdown" },
    Default = 1,
    Multi = false,

    Text = "A dropdown",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    Searchable = false,

    Callback = function(Value)
        print("[cb] Dropdown got changed. New value:", Value)
    end,

    Disabled = false,
    Visible = true,
})

Options.MyDropdown:OnChanged(function()
    print("Dropdown got changed. New value:", Options.MyDropdown.Value)
end)

Options.MyDropdown:SetValue("This")

-- Dropdown แบบ Searchable
DropdownGroupBox:AddDropdown("MySearchableDropdown", {
    Values = { "This", "is", "a", "searchable", "dropdown" },
    Default = 1,
    Multi = false,

    Text = "A searchable dropdown",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    Searchable = true,

    Callback = function(Value)
        print("[cb] Dropdown got changed. New value:", Value)
    end,

    Disabled = false,
    Visible = true,
})

-- Dropdown ที่เปลี่ยน display value บางค่าพิเศษ
DropdownGroupBox:AddDropdown("MyDisplayFormattedDropdown", {
    Values = { "This", "is", "a", "formatted", "dropdown" },
    Default = 1,
    Multi = false,

    Text = "A display formatted dropdown",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    FormatDisplayValue = function(Value)
        if Value == "formatted" then
            return "display formatted"
        end
        return Value
    end,

    Searchable = false,

    Callback = function(Value)
        print("[cb] Display formatted dropdown got changed. New value:", Value)
    end,

    Disabled = false,
    Visible = true,
})

-- Multi dropdown
DropdownGroupBox:AddDropdown("MyMultiDropdown", {
    Values = { "This", "is", "a", "dropdown" },
    Default = 1,
    Multi = true,

    Text = "A multi dropdown",
    Tooltip = "This is a tooltip",

    Callback = function(Value)
        print("[cb] Multi dropdown got changed:")
        for key, value in next, Options.MyMultiDropdown.Value do
            print(key, value)
        end
    end,
})

Options.MyMultiDropdown:SetValue({
    This = true,
    is = true,
})

-- Dropdown disabled ทั้ง control
DropdownGroupBox:AddDropdown("MyDisabledDropdown", {
    Values = { "This", "is", "a", "dropdown" },
    Default = 1,
    Multi = false,

    Text = "A disabled dropdown",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    Callback = function(Value)
        print("[cb] Disabled dropdown got changed. New value:", Value)
    end,

    Disabled = true,
    Visible = true,
})

-- Dropdown ที่มีค่า value บางตัวกดไม่ได้ (DisabledValues)
DropdownGroupBox:AddDropdown("MyDisabledValueDropdown", {
    Values = { "This", "is", "a", "dropdown", "with", "disabled", "value" },
    DisabledValues = { "disabled" },

    Default = 1,
    Multi = false,

    Text = "A dropdown with disabled value",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    Callback = function(Value)
        print("[cb] Dropdown with disabled value got changed. New value:", Value)
    end,

    Disabled = false,
    Visible = true,
})

-- Dropdown ที่มีรายการยาว + ตั้ง MaxVisibleDropdownItems
DropdownGroupBox:AddDropdown("MyVeryLongDropdown", {
    Values = {
        "This","is","a","very","long","dropdown","with","a","lot","of","values",
        "but","you","can","see","more","than","8","values",
    },
    Default = 1,
    Multi = false,

    MaxVisibleDropdownItems = 12,

    Text = "A very long dropdown",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",

    Searchable = false,

    Callback = function(Value)
        print("[cb] Very long dropdown got changed. New value:", Value)
    end,

    Disabled = false,
    Visible = true,
})

-- Dropdown แบบพิเศษ: Player / Team
DropdownGroupBox:AddDropdown("MyPlayerDropdown", {
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Text = "A player dropdown",
    Tooltip = "This is a tooltip",

    Callback = function(Value)
        print("[cb] Player dropdown got changed:", Value)
    end,
})

DropdownGroupBox:AddDropdown("MyTeamDropdown", {
    SpecialType = "Team",
    Text = "A team dropdown",
    Tooltip = "This is a tooltip",

    Callback = function(Value)
        print("[cb] Team dropdown got changed:", Value)
    end,
})

--[[========================================================
    6) ColorPicker + KeyPicker (ผูกกับ Label)
========================================================]]--

-- ColorPicker บน Label
LeftGroupBox:AddLabel("Color")
    :AddColorPicker("ColorPicker", {
        Default = Color3.new(0, 1, 0),
        Title = "Some color",
        Transparency = 0,

        Callback = function(Value)
            print("[cb] Color changed!", Value)
        end,
    })

Options.ColorPicker:OnChanged(function()
    print("Color changed!", Options.ColorPicker.Value)
    print("Transparency changed!", Options.ColorPicker.Transparency)
end)

Options.ColorPicker:SetValueRGB(Color3.fromRGB(0, 255, 140))

-- KeyPicker บน Label
LeftGroupBox:AddLabel("Keybind")
    :AddKeyPicker("KeyPicker", {
        Default = "MB2",
        SyncToggleState = false,
        Mode = "Toggle",          -- "Always", "Toggle", "Hold", "Press"
        Text = "Auto lockpick safes",
        NoUI = false,

        Callback = function(Value)
            print("[cb] Keybind clicked!", Value)
        end,

        ChangedCallback = function(NewKey, NewModifiers)
            print("[cb] Keybind changed!", NewKey, table.unpack(NewModifiers or {}))
        end,
    })

Options.KeyPicker:OnClick(function()
    print("Keybind clicked!", Options.KeyPicker:GetState())
end)

Options.KeyPicker:OnChanged(function()
    print("Keybind changed!", Options.KeyPicker.Value, table.unpack(Options.KeyPicker.Modifiers or {}))
end)

task.spawn(function()
    while task.wait(1) do
        local state = Options.KeyPicker:GetState()
        if state then
            print("KeyPicker is being held down")
        end
        if Library.Unloaded then
            break
        end
    end
end)

Options.KeyPicker:SetValue({ "MB2", "Hold" })

-- KeyPicker (Press mode) ตัวอย่าง callback แบบ Press
local KeybindNumber = 0

LeftGroupBox:AddLabel("Press Keybind")
    :AddKeyPicker("KeyPicker2", {
        Default = "X",
        Mode = "Press",
        WaitForCallback = false,

        Text = "Increase Number",

        Callback = function()
            KeybindNumber += 1
            print("[cb] Keybind clicked! Number increased to:", KeybindNumber)
        end,
    })

-- Groupbox ที่ 2 แสดง label ยาว (ทดสอบ scroll)
local LeftGroupBox2 = Tabs.Main:AddLeftGroupbox("Groupbox #2")
LeftGroupBox2:AddLabel(
    "This label spans multiple lines! We're gonna run out of UI space...\n" ..
    "Just kidding! Scroll down!\n\n\nHello from below!",
    true
)

--[[========================================================
    7) Tabbox ฝั่งขวา (Main Tab)
========================================================]]--

local TabBox = Tabs.Main:AddRightTabbox()

-- ทุกอย่างที่ทำใน Groupbox ทำใน Tabbox Tab ได้เหมือนกัน
local Tab1 = TabBox:AddTab("Tab 1")
Tab1:AddToggle("Tab1Toggle", { Text = "Tab1 Toggle" })

local Tab2 = TabBox:AddTab("Tab 2")
Tab2:AddToggle("Tab2Toggle", { Text = "Tab2 Toggle" })

-- Callback ตอน Library ถูก Unload
Library:OnUnload(function()
    print("Unloaded!")
end)

--[[========================================================
    8) KeyTab (Key System UI) แบบง่าย
========================================================]]--

-- NOTE: Tabs.Key เป็น Tab แบบพิเศษที่มาพร้อม AddKeyBox
-- เหมาะใช้เป็น base ของ Key UI ในโปรเจกต์จริง (เฟส B/C)

Tabs.Key:AddLabel({
    Text = "Key: Banana",
    DoesWrap = true,
    Size = 16,
})

Tabs.Key:AddKeyBox("Banana", function(Success, ReceivedKey)
    print("Expected Key: Banana - Received Key:", ReceivedKey, "| Success:", Success)

    Library:Notify({
        Title = "Expected Key: Banana",
        Description = "Received Key: " .. ReceivedKey .. "\nSuccess: " .. tostring(Success),
        Time = 4,
    })
end)

Tabs.Key:AddLabel({
    Text = "No Key",
    DoesWrap = true,
    Size = 16,
})

Tabs.Key:AddKeyBox(function(Success, ReceivedKey)
    print("Expected Key: None | Success:", Success) -- true
    Library:Notify("Success: " .. tostring(Success), 4)
end)

--[[========================================================
    9) UI Settings Tab (Keybind menu, cursor, Notify side, DPI, Managers)
========================================================]]--

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")

-- เปิด/ปิด Keybind menu frame
MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})

-- เปิด/ปิด custom cursor
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})

-- เปลี่ยนด้านของ Notification
MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})

-- DPI Scale (mobile-friendly สำคัญ)
MenuGroup:AddDropdown("DPIDropdown", {
    Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "DPI Scale",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})

MenuGroup:AddDivider()

-- Menu toggle keybind (ไม่แสดงใน Keybind menu)
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI = true,
        Text = "Menu keybind",
    })

MenuGroup:AddButton("Unload", function()
    Library:Unload()
end)

-- ตั้ง keybind เปิด/ปิด UI จาก Options.MenuKeybind
Library.ToggleKeybind = Options.MenuKeybind

--[[========================================================
    10) ThemeManager + SaveManager (config + themes)
========================================================]]--

-- ส่ง Library ให้ managers
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

-- ไม่ให้ config เซฟ theme (ThemeManager จัดการเอง)
SaveManager:IgnoreThemeSettings()

-- ไม่ให้ MenuKeybind ถูกเซฟใน config แต่ละอัน
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

-- จัด folder โครงสร้าง config / theme
ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub/specific-game")
SaveManager:SetSubFolder("specific-place") -- กรณีเกมมีหลาย place (เช่น DOORS)

-- สร้าง section config (ด้านขวาของ Tab UI Settings)
SaveManager:BuildConfigSection(Tabs["UI Settings"])

-- สร้างเมนู Theme (built-in theme หลายแบบ) ใน Tab UI Settings
ThemeManager:ApplyToTab(Tabs["UI Settings"])

-- auto-load config ที่ถูก marked ว่า autoload
SaveManager:LoadAutoloadConfig()
