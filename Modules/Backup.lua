----------------------------------------------------------------------
-- Guild OS - Backup / Restore
-- Export the current guild's saved data to a copyable string, and
-- restore it back (replaces the guild DB and reloads). Useful before a
-- risky change or to move a config between accounts.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Backup = {}
GuildOS.Backup = Backup
local L = GuildOS.L

local LibSerialize = LibStub("GuildOS-LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local PREFIX = "GOSBKP1:"   -- format/version tag

----------------------------------------------------------------------
-- Serialize the current guild DB to a print-safe string.
----------------------------------------------------------------------
function Backup:Export()
    if not GuildOS.db then return nil end
    local ok, ser = pcall(function() return LibSerialize:Serialize(GuildOS.db) end)
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
    if not GuildOS.guildKey or not GuildOSDB then return false, "no_guild" end
    GuildOSDB[GuildOS.guildKey] = data
    GuildOS:Print(L["Backup restored. Reloading..."])
    ReloadUI()
    return true
end

-- The restore button: the string is checked first, then a confirmation, since the whole guild database is
-- replaced and there is no undo (audit D11).
function Backup:AskImport(text)
    local _, err = self:Decode(text)
    if err then
        GuildOS:Print(L["|cffFF4444Restore failed:|r "] .. tostring(err))
        return
    end
    GuildOS.Dialogs["GUILDOS_RESTORE_BACKUP"] = GuildOS.Dialogs["GUILDOS_RESTORE_BACKUP"] or {
        text = L["Replace this guild's whole Guild OS database with the backup and reload? This cannot be undone."],
        button1 = L["Restore & Reload"], button2 = L["Cancel"],
        OnAccept = function(dialog)
            local ok, why = Backup:Import(dialog and dialog.data and dialog.data.text)
            if not ok then GuildOS:Print(L["|cffFF4444Restore failed:|r "] .. tostring(why)) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    GuildOS:ShowDialog("GUILDOS_RESTORE_BACKUP", nil, nil, { text = text })
end

----------------------------------------------------------------------
-- The previous version's data (release safety S2). The first load of the compact format (db.schema: recipes,
-- gear, history) converts what an older version saved. Right before it, what the conversion replaces is kept as it
-- was, in one slot per guild database at the account's root (GuildOSDB._prevVersion[guildKey]): the old recipe
-- lists (db.recipes), each member row's old gear table, the member history when the conversion trims it, and the
-- old db.schema. Nothing is copied: the conversion builds new tables and leaves the old ones to the slot. A full
-- backup in the SavedVariables would double their size for good, so the slot is the "previous version" one: it goes
-- by itself after PREV_DAYS, or at /gos backup forget, and is never added to (a newer one replaces it).
-- /gos backup previous hands it over as an ordinary backup string, the data in the previous version's shape, for an
-- older version's /gos restore.
----------------------------------------------------------------------
Backup.PREV_DAYS = 7

local function slots()
    if type(GuildOSDB) ~= "table" then return nil end
    if type(GuildOSDB._prevVersion) ~= "table" then return nil end
    return GuildOSDB._prevVersion
end

local function historyCap()
    local MH = GuildOS.MemberHistory
    return MH and tonumber(MH.MAX_KEYS) or nil, MH and tonumber(MH.SCHEMA) or 1
end

-- What the conversion of `db` would replace, by reference: { recipes, gear = { [key] = old table }, history }, or
-- nil when it replaces nothing (a database already compact, or empty).
function Backup.Replaced(db)
    if type(db) ~= "table" then return nil end
    local schema = type(db.schema) == "table" and db.schema or {}
    local out, any = { gear = {} }, false
    if type(db.recipes) == "table" and next(db.recipes) ~= nil then out.recipes, any = db.recipes, true end
    for key, row in pairs(type(db.members) == "table" and db.members or {}) do
        if type(row) == "table" and type(row.gear) == "table" then out.gear[key], any = row.gear, true end
    end
    local cap, hs = historyCap()
    if cap and type(db.memberHistory) == "table" and (tonumber(schema.history) or 0) < hs then
        local n = 0
        for _ in pairs(db.memberHistory) do n = n + 1 end
        if n > cap then
            local copy = {}
            for k, v in pairs(db.memberHistory) do copy[k] = v end
            out.history, any = copy, true
        end
    end
    if not any then return nil end
    if next(out.gear) == nil then out.gear = nil end
    return out
end

-- Called on a guild database right after it is resolved and before any module converts it (Core/Core.lua's
-- ResolveGuildDB): keeps the previous version's shape of it, once, and says so in one line. Also drops the slots
-- past PREV_DAYS. True when one was kept now.
function Backup:KeepBeforeUpgrade(db, key, now)
    now = now or time()
    self:PrunePrevious(now)
    if type(GuildOSDB) ~= "table" or type(key) ~= "string" then return false end
    local replaced = Backup.Replaced(db)
    if not replaced then return false end
    local schema = {}
    for k, v in pairs(type(db.schema) == "table" and db.schema or {}) do schema[k] = v end
    replaced.schema, replaced.at, replaced.version = schema, now, GuildOS.VERSION
    GuildOSDB._prevVersion = type(GuildOSDB._prevVersion) == "table" and GuildOSDB._prevVersion or {}
    GuildOSDB._prevVersion[key] = replaced
    GuildOS:Print(L["Guild OS updated its saved data format. A backup was kept: /gos backup to manage it."])
    return true
end

-- Drops every previous-version slot older than PREV_DAYS. How many went.
function Backup:PrunePrevious(now)
    local s = slots()
    if not s then return 0 end
    now = now or time()
    local n = 0
    for k, slot in pairs(s) do
        local at = type(slot) == "table" and tonumber(slot.at) or nil
        if not at or now - at >= self.PREV_DAYS * 86400 then s[k] = nil; n = n + 1 end
    end
    if next(s) == nil then GuildOSDB._prevVersion = nil end
    return n
end

-- This guild's slot, or nil.
function Backup:Previous(key)
    local s = slots()
    key = key or GuildOS.guildKey
    return s and key and s[key] or nil
end

function Backup:ForgetPrevious(key)
    local s = slots()
    key = key or GuildOS.guildKey
    if not (s and key and s[key]) then return false end
    s[key] = nil
    if next(s) == nil then GuildOSDB._prevVersion = nil end
    return true
end

-- The guild's database as the previous version had it: today's, with the slot's old tables back in their places
-- (the rows copied, never the live ones changed). Nil without a slot.
function Backup:PreviousDB(key)
    key = key or GuildOS.guildKey
    local slot = self:Previous(key)
    local db = key and type(GuildOSDB) == "table" and GuildOSDB[key]
    if not (slot and type(db) == "table") then return nil end
    local out = {}
    for k, v in pairs(db) do out[k] = v end
    if slot.recipes then out.recipes = slot.recipes end
    if slot.gear then
        local members = {}
        for mk, row in pairs(type(db.members) == "table" and db.members or {}) do
            local old = slot.gear[mk]
            if old and type(row) == "table" then
                local r = {}
                for f, v in pairs(row) do r[f] = v end
                r.gear, r.gc = old, nil
                members[mk] = r
            else
                members[mk] = row
            end
        end
        out.members = members
    end
    if slot.history then out.memberHistory = slot.history end
    out.schema = slot.schema
    return out
end

-- The previous version's data as a backup string (Export's format), or nil.
function Backup:PreviousString(key)
    local db = self:PreviousDB(key)
    if not db then return nil end
    local ok, ser = pcall(function() return LibSerialize:Serialize(db) end)
    if not ok or type(ser) ~= "string" then return nil end
    return PREFIX .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(ser))
end

-- /gos backup [previous | forget]: the backup string, and what the previous-version slot holds and until when.
function Backup:Command(arg)
    arg = strtrim(arg or "")
    local slot = self:Previous()
    if arg == "previous" then
        local str = slot and self:PreviousString()
        if not str then GuildOS:Print(L["No previous version's data is kept for this guild."]); return end
        GuildOS:ShowExportPopup(L["Guild OS Backup (previous version)"], str)
        return
    elseif arg == "forget" then
        GuildOS:Print(self:ForgetPrevious() and L["The previous version's data was deleted."]
            or L["No previous version's data is kept for this guild."])
        return
    end
    self:ShowExport()
    if slot then
        GuildOS:Print(string.format(L["The data as the previous version saved it is kept until %s: /gos backup previous to copy it (an older version's /gos restore takes it), /gos backup forget to delete it now."],
            GuildOS:DateText((tonumber(slot.at) or time()) + self.PREV_DAYS * 86400, "/%Y")))
    end
end

----------------------------------------------------------------------
-- UI: export popup + restore paste window.
----------------------------------------------------------------------
function Backup:ShowExport()
    local str = self:Export()
    if not str then
        GuildOS:Print(L["|cffFF4444Backup failed.|r"])
        return
    end
    GuildOS:ShowExportPopup(L["Guild OS Backup"], str)
end

function Backup:ShowRestore()
    local UI = GuildOS.UI
    local C = GuildOS.Colors

    local f = self.restoreFrame
    if not f then
        f = CreateFrame("Frame", "GuildOSRestoreFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 280)
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

        local title = UI:CreateTitle(f, L["Whole guild database"], 15)
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
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(box) })
        box:SetBackdropColor(0.03, 0.03, 0.04, 1)
        box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.5)
        box:SetMultiLine(true)
        GuildOS:ApplyFont(box, 10)
        box:SetTextColor(C.text.r, C.text.g, C.text.b)
        box:SetTextInsets(6, 6, 6, 6)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
        f.box = box

        local restoreBtn = UI:CreateButton(f, L["Restore & Reload"], 160, 26)
        restoreBtn:SetPoint("BOTTOM", 0, 14)
        restoreBtn:SetBaseColor(C.red.r * 0.30, C.red.g * 0.30, C.red.b * 0.30, 0.9)
        restoreBtn:SetScript("OnClick", function() GuildOS.Backup:AskImport(box:GetText()) end)

        self.restoreFrame = f
    end
    f.box:SetText("")
    f:Show()
end
