----------------------------------------------------------------------
-- Guild OS - !note command
-- A member types "!note <text>" in guild chat; any online client with
-- public-note-edit permission (officers) applies it to that member's
-- public note. Useful on Classic/TBC where members can't self-edit notes.
----------------------------------------------------------------------
local NoteCommand = {}
BRutus.NoteCommand = NoteCommand
local L = BRutus.L

function NoteCommand:Initialize()
    BRutus.db.noteCommand = BRutus.db.noteCommand or {}
    if BRutus.db.noteCommand.enabled == nil then BRutus.db.noteCommand.enabled = true end
    self._cd = {}
    self:_SetupHook()
    self:_RegisterTests()
end

-- Pure: returns the note text (<=31, "" to clear) or nil if not a !note command.
function NoteCommand:_Parse(msg)
    if not msg then return nil end
    if msg:match("^!note%s*$") then return "" end
    local rest = msg:match("^!note%s+(.+)$")
    if not rest then return nil end
    rest = strtrim(rest)
    if rest:lower() == "clear" then return "" end
    return rest:sub(1, 31)
end

function NoteCommand:_SetupHook()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_GUILD")
    f:SetScript("OnEvent", function(_, _, msg, author)
        local cfg = BRutus.db.noteCommand
        if not cfg or not cfg.enabled then return end
        local text = NoteCommand:_Parse(msg)
        if text == nil then return end
        if not BRutus.Compat.CanEditPublicNote() then return end
        local sender = author and (author:match("^([^-]+)") or author)
        if not sender then return end
        if NoteCommand._cd[sender] then return end
        NoteCommand._cd[sender] = true
        BRutus.Compat.After(15, function() NoteCommand._cd[sender] = nil end)
        if BRutus.Compat.SetGuildPublicNote(sender, text) then
            BRutus:Print(string.format(L["Set %s's note: |cffFFFFFF%s|r"], sender, text ~= "" and text or L["(cleared)"]))
        end
    end)
end

function NoteCommand:HandleCommand(args)
    local cfg = BRutus.db.noteCommand
    if not cfg then return end
    local sub = args[1]
    if sub == "on" then cfg.enabled = true; BRutus:Print(L["!note command |cff4CFF4Con|r."])
    elseif sub == "off" then cfg.enabled = false; BRutus:Print(L["!note command |cffFF4444off|r."])
    else
        local st = cfg.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        BRutus:Print(L["!note command: "] .. st .. L[" — members type !note <text> in guild chat; officers apply it."])
    end
end

function NoteCommand:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("notecmd.parse_text", function()
        if NoteCommand:_Parse("!note LFG Kara") ~= "LFG Kara" then return false, "text" end
        return true
    end)
    S:Register("notecmd.parse_clear", function()
        if NoteCommand:_Parse("!note") ~= "" then return false, "bare" end
        if NoteCommand:_Parse("!note clear") ~= "" then return false, "clear" end
        return true
    end)
    S:Register("notecmd.not_a_command", function()
        if NoteCommand:_Parse("hello world") ~= nil then return false, "plain" end
        if NoteCommand:_Parse("!notepad rocks") ~= nil then return false, "!notepad must not match" end
        return true
    end)
    S:Register("notecmd.cap31", function()
        local long = "!note " .. string.rep("x", 50)
        if #NoteCommand:_Parse(long) ~= 31 then return false, "cap" end
        return true
    end)
end
