----------------------------------------------------------------------
-- Guild OS - !note command
-- A member types "!note <text>" in guild chat; any online client with
-- public-note-edit permission applies it to that member's public note.
-- Useful on Classic/TBC where members can't self-edit notes. Every such
-- client sees the same line, so the write is jittered and skipped when the
-- note already matches (see _SetupHook) instead of N clients writing at once.
----------------------------------------------------------------------
local NoteCommand = {}
BRutus.NoteCommand = NoteCommand
local L = BRutus.L

local NOTE_MAX   = 31   -- server cap on a guild public note
local SENDER_CD  = 15   -- per-sender cooldown

function NoteCommand:Initialize()
    BRutus.db.noteCommand = BRutus.db.noteCommand or {}
    if BRutus.db.noteCommand.enabled == nil then BRutus.db.noteCommand.enabled = true end
    self._cd = {}
    self:_SetupHook()
    self:_RegisterTests()
end

-- Pure: returns the note text (<=31 bytes, "" to clear) or nil if not a !note
-- command. The text is member-authored and every OTHER client renders it, so it
-- goes through the shared sanitizer: UI escapes stripped (a bare "|T...|t" would
-- otherwise inflate every roster row with a 99px texture, and a cut "|cff..."
-- would bleed colour), and the cap backs off a split UTF-8 codepoint.
function NoteCommand:_Parse(msg)
    if not msg then return nil end
    if msg:match("^!note%s*$") then return "" end
    local rest = msg:match("^!note%s+(.+)$")
    if not rest then return nil end
    rest = BRutus:SanitizeUserText(rest, NOTE_MAX)
    if rest:lower() == "clear" then return "" end
    return rest
end

-- Why a write this client tried did not happen (issue #5). Only clients that
-- had the permission when the line arrived get this far.
local REFUSED = {
    absent            = "Could not set %s's note: not found in the guild roster.",
    ambiguous         = "Could not set %s's note: more than one guild member has that name.",
    ["no-guid"]       = "Could not set %s's note: the guild roster did not return the member's GUID.",
    ["no-api"]        = "Could not set %s's note: this client has no public note API.",
    ["no-permission"] = "Could not set %s's note: this character can no longer edit public notes.",
}

function NoteCommand:_Refused(sender, why)
    if REFUSED[why] then BRutus:Print(string.format(L[REFUSED[why]], sender)) end
end

-- Applies the note after the jitter window. Everything is re-checked here
-- because several seconds have passed since the chat line arrived.
function NoteCommand:_Apply(sender, realm, text)
    local Compat = BRutus.Compat
    -- It had the permission when the line arrived; a rank change in the jitter window takes it away.
    if not Compat.CanEditPublicNote() then return self:_Refused(sender, "no-permission") end
    local want = BRutus:SanitizeUserText(text, NOTE_MAX)
    local current, why = Compat.GetGuildPublicNote(sender, realm)
    if current == nil then
        -- An empty roster has not loaded yet: "not found" would be wrong, and another officer can apply it.
        if why == "absent" and (GetNumGuildMembers() or 0) == 0 then return end
        return self:_Refused(sender, why)
    end
    if current == want then return end      -- somebody else already applied it
    local ok, failure = Compat.SetGuildPublicNote(sender, want, realm)
    if not ok then return self:_Refused(sender, failure) end
    local who = realm and (sender .. "-" .. realm) or sender
    if BRutus.GuildManager and BRutus.GuildManager.LogAction then
        BRutus.GuildManager:LogAction("note", who, want ~= "" and want or L["(cleared)"])
    end
    BRutus:Print(string.format(L["Set %s's note: |cffFFFFFF%s|r"], sender, want ~= "" and want or L["(cleared)"]))
end

function NoteCommand:_SetupHook()
    local f = CreateFrame("Frame")
    BRutus.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    f:SetScript("OnEvent", function(_, _, msg, author)
        if BRutus.Compat.IsSecret(msg, author) then return end  -- chat in lockdown: nothing readable
        local cfg = BRutus.db.noteCommand
        if not cfg or not cfg.enabled then return end
        local text = NoteCommand:_Parse(msg)
        if text == nil then return end
        if not author then return end
        local sender = author:match("^([^-]+)") or author
        local realm  = author:match("^[^-]+%-(.+)$")
        if not sender or sender == "" then return end
        if not BRutus.Compat.CanEditPublicNote() then
            -- Every member's client sees the line; only the sender's own client says why
            -- nothing happens here, so the member who typed it is told and nobody else is.
            -- ponytail: short-name match; a same-named member on another realm would see the
            -- hint too, which is local and harmless. Compare the realm if that ever matters.
            if sender == UnitName("player") then
                BRutus:Print(L["You cannot edit public notes. Only an officer who is online now and running Guild OS can apply !note; if none is, type it again later."])
            end
            return
        end
        -- Per-sender only, deliberately. A module-wide gate would silently
        -- discard a second member's legitimate !note typed moments after the
        -- first, and the write volume is already bounded: one command converges
        -- on one write (below), and one member can only issue four a minute.
        if NoteCommand._cd[sender] then return end
        NoteCommand._cd[sender] = true
        BRutus.Compat.After(SENDER_CD, function() NoteCommand._cd[sender] = nil end)
        -- Guilds commonly grant "Edit Public Note" to every rank, so one !note
        -- would otherwise fire N simultaneous server writes (one per online
        -- holder of the permission), each broadcasting GUILD_ROSTER_UPDATE.
        -- There is no leader election here: wait a random beat, refresh the
        -- roster meanwhile, and skip the write if the note already reads the
        -- way we would have set it. That converges on roughly one write.
        BRutus.Compat.GuildRoster()
        BRutus.Compat.After(1 + math.random() * 4, function()
            NoteCommand:_Apply(sender, realm, text)
        end)
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
    S:Register("notecmd.sanitize", function()
        -- UI escapes must not reach the note write (C_GuildInfo.SetNote or the old global).
        if NoteCommand:_Parse("!note |cffFF0000LFG|r Kara") ~= "cffFF0000LFGr Kara" then
            return false, "colour escape survived"
        end
        if NoteCommand:_Parse("!note a\tb") ~= "a b" then return false, "control char" end
        -- The 31-byte cap must not leave half of a two-byte codepoint behind:
        -- byte 31 here is the \195 lead byte, so it is dropped whole.
        local out = NoteCommand:_Parse("!note " .. string.rep("x", 30) .. "\195\167ao")
        if out ~= string.rep("x", 30) then return false, "split codepoint kept" end
        return true
    end)
end
