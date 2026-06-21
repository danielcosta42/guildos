----------------------------------------------------------------------
-- Guild OS - Backup / Restore
-- Export the current guild's saved data to a copyable string, and
-- restore it back (replaces the guild DB and reloads). Useful before a
-- risky change or to move a config between accounts.
----------------------------------------------------------------------
local Backup = {}
BRutus.Backup = Backup
local L = BRutus.L

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local PREFIX = "GOSBKP1:"   -- format/version tag

----------------------------------------------------------------------
-- Serialize the current guild DB to a print-safe string.
----------------------------------------------------------------------
function Backup:Export()
    if not BRutus.db then return nil end
    local ok, ser = pcall(function() return LibSerialize:Serialize(BRutus.db) end)
    if not ok or type(ser) ~= "string" then return nil end
    local compressed = LibDeflate:CompressDeflate(ser)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return PREFIX .. encoded
end

----------------------------------------------------------------------
-- Decode a backup string into a table (without applying it).
-- Returns (table, nil) on success or (nil, reason) on failure.
----------------------------------------------------------------------
function Backup:Decode(text)
    if not text or text == "" then return nil, "empty" end
    local payload = strtrim(text):match("^" .. PREFIX .. "(.+)$")
    if not payload then return nil, "bad_format" end
    local compressed = LibDeflate:DecodeForPrint(payload)
    if not compressed then return nil, "decode" end
    local ser = LibDeflate:DecompressDeflate(compressed)
    if not ser then return nil, "decompress" end
    local ok, data = LibSerialize:Deserialize(ser)
    if not ok or type(data) ~= "table" then return nil, "deserialize" end
    return data, nil
end

----------------------------------------------------------------------
-- Replace the current guild's saved table and reload to rebind it.
----------------------------------------------------------------------
function Backup:Import(text)
    local data, err = self:Decode(text)
    if not data then return false, err end
    if not BRutus.guildKey or not GuildOSDB then return false, "no_guild" end
    GuildOSDB[BRutus.guildKey] = data
    BRutus:Print(L["Backup restored. Reloading..."])
    ReloadUI()
    return true
end

----------------------------------------------------------------------
-- UI: export popup + restore paste window.
----------------------------------------------------------------------
function Backup:ShowExport()
    local str = self:Export()
    if not str then
        BRutus:Print(L["|cffFF4444Backup failed.|r"])
        return
    end
    BRutus:ShowExportPopup(L["Guild OS Backup"], str)
end

function Backup:ShowRestore()
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.restoreFrame
    if not f then
        f = CreateFrame("Frame", "GuildOSRestoreFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 280)
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

        local title = UI:CreateTitle(f, L["Restore Backup"], 15)
        title:SetPoint("TOPLEFT", 16, -14)

        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        local warn = UI:CreateText(f,
            L["|cffFF8800Warning:|r this replaces ALL of this guild's Guild OS data and reloads. Paste a backup string below."],
            10, C.silver.r, C.silver.g, C.silver.b)
        warn:SetPoint("TOPLEFT", 16, -40)
        warn:SetPoint("TOPRIGHT", -16, -40)
        warn:SetJustifyH("LEFT")

        local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        box:SetPoint("TOPLEFT", 16, -80)
        box:SetPoint("BOTTOMRIGHT", -16, 52)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0.03, 0.03, 0.04, 1)
        box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.5)
        box:SetMultiLine(true)
        box:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        box:SetTextColor(C.text.r, C.text.g, C.text.b)
        box:SetTextInsets(6, 6, 6, 6)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
        f.box = box

        local restoreBtn = UI:CreateButton(f, L["Restore & Reload"], 160, 26)
        restoreBtn:SetPoint("BOTTOM", 0, 14)
        restoreBtn:SetBaseColor(C.red.r * 0.30, C.red.g * 0.30, C.red.b * 0.30, 0.9)
        restoreBtn:SetScript("OnClick", function()
            local ok, err = BRutus.Backup:Import(box:GetText())
            if not ok then
                BRutus:Print(L["|cffFF4444Restore failed:|r "] .. tostring(err))
            end
        end)

        self.restoreFrame = f
    end
    f.box:SetText("")
    f:Show()
end
