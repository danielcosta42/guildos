----------------------------------------------------------------------
-- Guild OS - The officer action queue (#449; specs/salao/convites.md)
-- One queue for what the game lets an addon do only behind a key press or a
-- click (a hardware event): a guild invite (C_GuildInfo.Invite is #hwevent),
-- a /who (C_FriendList.SendWho), and where the game drops them from a timer
-- (Compat.NeedsClick) a whisper, a guild chat line or a group invite. Every
-- feature that would do one of those from an event or a timer hands it here:
-- the keyword auto-invite, its /who check, the scanner's whispers, the
-- welcome, Raid Tools' invites, the Groups board's "inv" whisper, and the
-- recruitment ad's channels after the first where one key press carries one
-- channel line (Recruitment:PostRound).
--
-- Compat.NeedsHardware(kind) says per client (and per the probe, /gos probe
-- invite) whether an action needs one; when it does not, the action runs at
-- once, as it always did. When it does, it waits here, and ONE action runs
-- per key press of the "Guild OS: next in the queue" binding (a CLICK binding
-- on the GuildOSQueueNext button, UI/ActionQueue.lua) or per click of the
-- toast that says "Press [key] (or click) to invite Fulano · N more". With
-- nothing of its own waiting, the key press takes the bulk actions' next step
-- (the secure button runs BulkActions:Arm's line) or releases a whisper the
-- WhisperQueue holds for a click.
--
-- On WoW: Forever the game lets no addon invite at all (#256): a guild invite
-- there is offered as the "/ginvite Name" line to copy (:OfferTyped), never
-- typed into the chat box.
--
-- Session only. Frame-free: the UI file listens through onChange / onTyped.
----------------------------------------------------------------------
local AQ = {}
GuildOS.ActionQueue = AQ
local L = GuildOS.L

AQ.BUTTON = "GuildOSQueueNext"                    -- the button the binding clicks
AQ.BINDING = "CLICK GuildOSQueueNext:LeftButton"  -- the binding's command (Bindings.xml)
AQ.MAX = 40                                       -- actions waiting at most; the oldest goes first
AQ.TYPED_MAX = 10                                 -- /ginvite lines waiting at most (Forever)

local S = { items = {}, typed = {}, armed = nil }
AQ._state = S

local function Compat() return GuildOS.Compat end

local function changed()
    if AQ.onChange then
        local ok, err = pcall(AQ.onChange)
        if not ok and GuildOS.RecordError then GuildOS:RecordError("ActionQueue: " .. tostring(err)) end
    end
end

local function indexOf(key)
    for i, item in ipairs(S.items) do
        if item.key == key then return i end
    end
    return nil
end

-- What runs one action: false (or an error) when it did nothing.
local function runItem(item)
    local ok, went = pcall(item.run)
    if not ok then
        if GuildOS.RecordError then GuildOS:RecordError("ActionQueue " .. tostring(item.kind) .. ": " .. tostring(went)) end
        return false
    end
    return went ~= false
end

-- The verb a kind's action says on the toast.
local VERBS = {
    guildInvite = function() return L["invite"] end,
    groupInvite = function() return L["invite to the group"] end,
    who = function() return L["check with /who"] end,
    whisper = function() return L["whisper"] end,
    chat = function() return L["send"] end,
    channel = function() return L["post in"] end,
}

--- Adds one action. item: { kind ("guildInvite", "groupInvite", "who", "whisper", "chat", "channel": a line in a
--- chat channel, the recruitment ad's channels after the first, #449), key (one per person
--- and purpose: a second Add with it replaces the first in its place), name (who it is for), run (does it;
--- returns false when nothing went), valid (optional: false when it no longer applies; then it is skipped),
--- verb (optional: what the toast says), ownWindow (optional: a window of its own asks for it, the toast stays
--- out) }. `fromClick`: the caller runs inside a key press or click already, and the action goes now.
--- Returns "ran", "queued" or false (malformed, or it did nothing).
function AQ:Add(item, fromClick)
    if type(item) ~= "table" or type(item.run) ~= "function" or type(item.kind) ~= "string" then return false end
    item.key = item.key or (item.kind .. ":" .. tostring(item.name))
    if fromClick or not Compat().NeedsHardware(item.kind) then
        if item.valid and item.valid() == false then return false end
        return runItem(item) and "ran" or false
    end
    local at = indexOf(item.key)
    if at then
        S.items[at] = item
    else
        if #S.items >= self.MAX then table.remove(S.items, 1) end
        S.items[#S.items + 1] = item
    end
    changed()
    return "queued"
end

--- Takes an action off the queue (it was done another way, or it no longer applies). Whether one was there.
function AQ:Remove(key)
    local at = indexOf(key)
    if not at then return false end
    table.remove(S.items, at)
    changed()
    return true
end

function AQ:Clear()
    S.items = {}
    changed()
end

--- How many actions wait; with `shown`, only those the toast shows.
function AQ:Pending(shown)
    if not shown then return #S.items end
    local n = 0
    for _, item in ipairs(S.items) do
        if not item.ownWindow and not (item.valid and item.valid() == false) then n = n + 1 end
    end
    return n
end

--- The next action, and the next one the toast shows.
function AQ:Peek(shown)
    for _, item in ipairs(S.items) do
        if not (shown and item.ownWindow) and not (shown and item.valid and item.valid() == false) then return item end
    end
    return nil
end

--- From a key press or a click (a hardware event): runs ONE waiting action, the first that still applies; one that no
--- longer does is dropped on the way and costs nothing. With nothing of its own, a whisper the WhisperQueue holds for
--- a click goes. Returns the action that ran, "whisper", or nil. Never in combat.
function AQ:Next(shown)
    if Compat().InCombat() then
        GuildOS:Print(L["Not during combat."])
        return nil
    end
    local i = 1
    while S.items[i] do
        local item = S.items[i]
        if shown and item.ownWindow then
            i = i + 1
        else
            table.remove(S.items, i)
            if not (item.valid and item.valid() == false) then
                runItem(item)
                changed()
                return item
            end
        end
    end
    changed()
    local WQ = GuildOS.WhisperQueue
    if WQ and WQ.Active and WQ.Active() and WQ:Pending() > 0 then
        WQ:Release()
        return "whisper"
    end
    return nil
end

----------------------------------------------------------------------
-- The binding's button (UI/ActionQueue.lua): a secure action button, so the same key press can run the bulk
-- actions' /gpromote, /gdemote or /gremove line where nothing of the queue's own waits.
----------------------------------------------------------------------

-- Whether the bulk actions have a member for the next press.
local function bulkNext()
    local BA = GuildOS.BulkActions
    return BA and BA.Queue and BA:Queue() and BA:Current() and BA or nil
end

--- The button's PreClick: the macro line this press runs ("" for none). One action per press: the queue's own first,
--- else the bulk actions' step, else a held whisper.
function AQ:Arm(down)
    S.armed = nil
    if not Compat().SecureClickActs(down) then return "" end
    if Compat().InCombat() then
        GuildOS:Print(L["Not during combat."])
        return ""
    end
    if #S.items > 0 then
        self:Next()
        return ""
    end
    local BA = bulkNext()
    if BA then
        local line = BA:Arm(down)
        if line and line ~= "" then S.armed = "bulk" end
        return line or ""
    end
    if not self:Next() then GuildOS:Print(L["Nothing waits in the queue."]) end
    return ""
end

--- The button's PostClick: the bulk step's bookkeeping, when this press ran one.
function AQ:AfterClick(down)
    if not Compat().SecureClickActs(down) then return end
    local armed = S.armed
    S.armed = nil
    if armed == "bulk" and GuildOS.BulkActions then GuildOS.BulkActions:AfterClick(down) end
end

--- The bound key as the player reads it, or nil when nothing is bound.
function AQ:KeyText()
    local key = Compat().BindingKey(self.BINDING)
    return key and Compat().BindingKeyText(key) or nil
end

--- `/gos queue bind <key>`: binds the key here (SetBindingClick), never in combat. Whether it was set.
function AQ:BindKey(key)
    key = type(key) == "string" and key:upper():gsub("%s+", "") or ""
    if key == "" then return false end
    if Compat().InCombat() then
        GuildOS:Print(L["Not during combat."])
        return false
    end
    local ok = Compat().SetBindingClick(key, self.BUTTON)
    if ok then GuildOS:Print(string.format(L["%s is now Guild OS: next in the queue."], key)) end
    changed()
    return ok
end

--- What the toast says about the next action: "Press [key] (or click) to invite Fulano · 2 more".
function AQ:PromptText(item)
    item = item or self:Peek(true)
    if not item then return nil end
    local verb = item.verb or (VERBS[item.kind] and VERBS[item.kind]()) or L["do it"]
    local what = item.name and (verb .. " " .. item.name) or verb
    local key = self:KeyText()
    local line = key and string.format(L["Press %s (or click) to %s"], key, what)
        or string.format(L["Click to %s"], what)
    local more = self:Pending(true) - 1
    if more > 0 then line = line .. " \194\183 " .. string.format(L["%d more"], more) end
    return line
end

----------------------------------------------------------------------
-- WoW: Forever: the guild invite as a line to copy (#256). Never put in the chat box: a line the addon writes
-- there taints the box until a /reload, and the game then refuses the invite anyway.
----------------------------------------------------------------------

--- The /ginvite line for `name`, as the officer pastes it.
function AQ.TypedLine(name)
    return "/ginvite " .. tostring(name)
end

--- Offers `name`'s invite as a line to copy; the UI shows it (onTyped). Whether it was offered.
function AQ:OfferTyped(name)
    if type(name) ~= "string" or name == "" then return false end
    for _, n in ipairs(S.typed) do
        if n == name then return false end
    end
    if #S.typed >= self.TYPED_MAX then table.remove(S.typed, 1) end
    S.typed[#S.typed + 1] = name
    if self.onTyped then pcall(self.onTyped) end
    return true
end

--- The next name waiting to be copied, and how many wait in all.
function AQ:NextTyped()
    return S.typed[1], #S.typed
end

--- The line was copied (or dismissed): the next one, if any.
function AQ:DoneTyped()
    table.remove(S.typed, 1)
    return S.typed[1]
end

--- `/gos queue [next | clear | bind <key>]`.
function AQ:Command(rest)
    rest = strtrim(rest or "")
    local verb, arg = rest:match("^(%S*)%s*(.*)$")
    verb = (verb or ""):lower()
    if verb == "clear" then
        self:Clear()
        GuildOS:Print(L["The queue is empty."])
    elseif verb == "bind" then
        if not self:BindKey(arg) then GuildOS:Print(L["Usage: /gos queue bind <key>, out of combat."]) end
    elseif verb == "next" then
        -- A typed command is a key press (the Enter that sent it).
        if not self:Next() then GuildOS:Print(L["Nothing waits in the queue."]) end
    else
        local item = self:Peek()
        GuildOS:Print(item and self:PromptText(item) or L["Nothing waits in the queue."])
        if not self:KeyText() then
            GuildOS:Print(L["Bind a key under Key Bindings, AddOns, Guild OS: next in the queue, or type /gos queue bind <key>."])
        end
    end
end
