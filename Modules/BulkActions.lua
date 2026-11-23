----------------------------------------------------------------------
-- Guild OS - Bulk actions (issue #420; Leadership > Bulk actions)
-- Promote, demote or remove the members a set of rules picks (offline for
-- days, current rank, level, raid attendance, without GuildOS), one member
-- per click of the officer.
--
-- GuildPromote / GuildDemote / GuildUninvite are protected: the addon never
-- calls them (ADR-0010). Each click of the Next button (a secure action
-- button, UI/BulkPanel.lua) or of a `/click GuildOSBulkNext` macro runs the
-- game's own /gpromote, /gdemote or /gremove for ONE member, the line this
-- module wrote for that click only (ADR-0038). Nothing here loops or runs
-- from a timer. Where a client refuses that (WoW: Forever, or a block seen
-- after a click), the click prints the line for the officer to type.
--
-- Before each click the member is read again from the roster: who left or
-- whose rank changed since the list was made is skipped. A change the roster
-- then shows goes to the Roster Log. Session state only (GuildOS.State).
----------------------------------------------------------------------
local BulkActions = {}
GuildOS.BulkActions = BulkActions
local L = GuildOS.L

BulkActions.ACTIONS = { "promote", "demote", "remove" }
-- The secure button's global name: what `/click` presses.
BulkActions.BUTTON = "GuildOSBulkNext"

-- The Roster Log's word for each action (RosterLog:_ParseSystem files a removal as "kick").
local LOG_ACTION = { promote = "promote", demote = "demote", remove = "kick" }
local UNCONFIRMED_AFTER = 15  -- seconds after a click with no change in the roster before the member reads "not confirmed"
local ROSTER_ASK_DELAY = 1.5  -- seconds after a click before asking the server for the roster again
local LOGGED_SLACK = 10       -- seconds before a click within which a Roster Log line already counts as it
local MAX_LEVEL_RULE = 200    -- a level rule above any game's cap is taken as no rule
local MAX_DAYS_RULE = 3650    -- ten years offline: anything above is taken as no rule

local function state()
    GuildOS.State.bulk = GuildOS.State.bulk or {}
    return GuildOS.State.bulk
end

local function short(name)
    return name and (name:match("^([^-]+)") or name) or "?"
end

function BulkActions:Initialize()
    state()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    GuildOS.Compat.RegisterEvent(f, "ADDON_ACTION_BLOCKED")
    GuildOS.Compat.RegisterEvent(f, "ADDON_ACTION_FORBIDDEN")
    GuildOS.Compat.RegisterEvent(f, "MACRO_ACTION_BLOCKED")
    GuildOS.Compat.RegisterEvent(f, "MACRO_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "GUILD_ROSTER_UPDATE" then
            GuildOS:SafeCall(BulkActions.Confirm, BulkActions)
        else
            GuildOS:SafeCall(BulkActions.OnBlocked, BulkActions, event, arg1, arg2)
        end
    end)
end

----------------------------------------------------------------------
-- Rules (pure; tools/bulk-actions.lua)
----------------------------------------------------------------------
local function num(v, lo, hi)
    v = GuildOS.Finite(v)
    if not v or v < lo or v > hi then return nil end
    return math.floor(v)
end

--- The rules from what the screen holds: { days, rank, levelMin, levelMax, attMin, attMax, noAddon }, each nil
--- when not set. days: offline at least that many days (1+); rank: the current 0-based rank (any when nil or
--- negative); level and attendance (%) bounds, inclusive; noAddon: only members whose GuildOS this client never heard.
function BulkActions.Rules(raw)
    raw = type(raw) == "table" and raw or {}
    local rank = GuildOS.Finite(raw.rank)
    return {
        days = num(raw.days, 1, MAX_DAYS_RULE),
        rank = (rank and rank >= 0) and math.floor(rank) or nil,
        levelMin = num(raw.levelMin, 1, MAX_LEVEL_RULE), levelMax = num(raw.levelMax, 1, MAX_LEVEL_RULE),
        attMin = num(raw.attMin, 0, 100), attMax = num(raw.attMax, 0, 100),
        noAddon = raw.noAddon and true or nil,
    }
end

--- Whether `rules` set anything: with none, nothing is picked (never the whole guild by accident).
function BulkActions.HasRule(rules)
    return rules ~= nil and (rules.days or rules.rank or rules.levelMin or rules.levelMax
        or rules.attMin or rules.attMax or rules.noAddon) ~= nil
end

--- Whether this rank may do `action` to member `m` at all, whatever the rules: never oneself, never someone at or
--- above one's own rank, a promotion never up to one's own rank, a demotion never below the lowest one, and a member
--- on the safe list (`m.safe`, issue #429) never removed or demoted. ctx: { myRank, lowestRank, meKey }.
function BulkActions.Eligible(m, action, ctx)
    local r = m and m.rankIndex
    if not r or not ctx or not ctx.myRank or m.key == ctx.meKey then return false end
    if m.safe and action ~= "promote" then return false end
    if r <= ctx.myRank then return false end
    if action == "promote" then return r - 1 > ctx.myRank end
    if action == "demote" then return ctx.lowestRank ~= nil and r < ctx.lowestRank end
    return action == "remove"
end

--- Whether member `m` meets every rule set. An unknown attendance meets no attendance rule.
function BulkActions.Meets(m, rules)
    if rules.days and not (m.daysOffline and m.daysOffline >= rules.days) then return false end
    if rules.rank and m.rankIndex ~= rules.rank then return false end
    local lvl = m.level or 0
    if rules.levelMin and lvl < rules.levelMin then return false end
    if rules.levelMax and lvl > rules.levelMax then return false end
    if (rules.attMin or rules.attMax) and m.attendance == nil then return false end
    if rules.attMin and m.attendance < rules.attMin then return false end
    if rules.attMax and m.attendance > rules.attMax then return false end
    if rules.noAddon and m.hasAddon then return false end
    return true
end

--- Whether a member at `rank` still has a step to go toward `target` (0-based ranks: a promotion lowers the index).
function BulkActions.Toward(rank, action, target)
    if not rank or not target then return false end
    if action == "promote" then return rank > target end
    if action == "demote" then return rank < target end
    return false
end

--- The alts of a group (issue #424) that `action` moves toward rank `target`: every key of `group` but `mainKey`,
--- on the roster, still short of the target and that Eligible lets this rank touch. By name.
function BulkActions.GroupMatch(members, group, mainKey, action, target, ctx)
    local want = {}
    for _, k in ipairs(group or {}) do if k ~= mainKey then want[k] = true end end
    local out = {}
    for _, m in ipairs(members or {}) do
        if want[m.key] and BulkActions.Toward(m.rankIndex, action, target) and BulkActions.Eligible(m, action, ctx) then
            out[#out + 1] = m
        end
    end
    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

--- The members of `members` that `action` would touch under `rules`: longest offline first, then by name.
--- Returns the list, and "rule" when no rule is set (then the list is empty).
function BulkActions.Match(members, rules, action, ctx)
    local out = {}
    if not BulkActions.HasRule(rules) then return out, "rule" end
    for _, m in ipairs(members or {}) do
        if BulkActions.Eligible(m, action, ctx) and BulkActions.Meets(m, rules) then out[#out + 1] = m end
    end
    table.sort(out, function(a, b)
        local da, db = a.daysOffline or -1, b.daysOffline or -1
        if da ~= db then return da > db end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

----------------------------------------------------------------------
-- The live roster
----------------------------------------------------------------------
--- Whether raid attendance is known on this client (the raid tracker runs).
function BulkActions:HasAttendance()
    local RT = GuildOS.RaidTracker
    return RT ~= nil and RT.GetAttendance25ManPercent ~= nil and RT.GetTotal25ManSessions ~= nil
        and RT.GetPlayerGroup ~= nil
end

-- A member's 25-man attendance, or nil when no raid of their group was ever tracked (0% would then be a lie).
local function attendanceOf(key)
    local RT = GuildOS.RaidTracker
    local group = RT:GetPlayerGroup(key, "raids25")
    if (RT:GetTotal25ManSessions(group) or 0) == 0 then return nil end
    return RT:GetAttendance25ManPercent(key, group)
end

--- What Eligible needs about this character: { myRank, lowestRank, meKey }.
function BulkActions:Context()
    local ranks = GuildOS.GuildManager and GuildOS.GuildManager:GetRanks() or {}
    return {
        myRank = GuildOS.Compat.MyGuildRankIndex(),
        lowestRank = #ranks > 0 and (#ranks - 1) or nil,
        meKey = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()),
    }
end

-- Roster line `i` as Match reads it, or nil. Attendance only when `att`.
local function memberAt(i, att)
    local name, rankName, rankIndex, level, _, _, note, onote, online, _, classFile = GetGuildRosterInfo(i)
    if not name then return nil end
    local GM = GuildOS.GuildManager
    local members = GuildOS.db and GuildOS.db.members or {}
    local key = GuildOS:KeyOfRosterName(name)
    local d = members[key]
    local off = (not online and GM) and GM:GetDaysOffline(i) or nil
    return {
        fullName = name, name = short(name), key = key,
        rankIndex = rankIndex, rankName = rankName or "?", level = level or 0,
        online = online and true or false, class = classFile or "",
        daysOffline = off and math.floor(off) or nil,
        hasAddon = (d and (d.lastUpdate or 0) > 0) and true or false,
        attendance = att and attendanceOf(key) or nil,
        safe = (GuildOS.MemberMarks and GuildOS.MemberMarks:IsSafe(key, note, onote)) or nil,   -- issue #429
    }
end

-- Whether the rules read the raid attendance.
local function usesAttendance(rules)
    return rules ~= nil and (rules.attMin ~= nil or rules.attMax ~= nil)
end

--- The guild roster as Match reads it. Attendance is read only when `withAttendance`.
function BulkActions:Collect(withAttendance)
    local out = {}
    local att = withAttendance and self:HasAttendance()
    for i = 1, GetNumGuildMembers() or 0 do
        out[#out + 1] = memberAt(i, att)
    end
    return out
end

--- Whether this character's rank may do `action` in the game.
function BulkActions:Allowed(action)
    local C = GuildOS.Compat
    if action == "promote" then return C.CanGuildPromote() end
    if action == "demote" then return C.CanGuildDemote() end
    if action == "remove" then return C.CanGuildRemove() end
    return false
end

--- Who `action` would touch under the raw rules, from the live roster. Returns the list and why it is empty:
--- "action", "permission", "rule" or nil.
function BulkActions:Preview(raw, action)
    if not LOG_ACTION[action] then return {}, "action" end
    if not self:Allowed(action) then return {}, "permission" end
    local rules = self.Rules(raw)
    return self.Match(self:Collect(usesAttendance(rules)), rules, action, self:Context())
end

----------------------------------------------------------------------
-- The queue
----------------------------------------------------------------------
--- The queue running, or nil: { action, items = { { fullName, name, key, rankIndex, rankName, status, why } }, pos }.
--- status: "pending", "sent" (clicked, the roster has not shown it yet), "unconfirmed" (clicked, and the roster
--- showed no change in UNCONFIRMED_AFTER seconds: never sent again, the officer checks it), "done" or "skipped"
--- (why: "left", "rank", "rules", "name" or "you").
function BulkActions:Queue()
    return state().queue
end

--- Start a queue from the rules. A removal starts only `confirmed` (the screen asks first). `shown`, optional: the
--- exact list the confirmation showed, queued as it is (each member is still checked again before their click).
--- Returns true, or false and why: "action", "permission", "rule", "confirm", "empty" or "combat".
function BulkActions:Start(raw, action, confirmed, shown)
    if not LOG_ACTION[action] then return false, "action" end
    if GuildOS.Compat.InCombat() then return false, "combat" end
    if action == "remove" and not confirmed then return false, "confirm" end
    if not self:Allowed(action) then return false, "permission" end
    local rules = self.Rules(raw)
    if not self.HasRule(rules) then return false, "rule" end
    local list, why = shown, nil
    if type(list) ~= "table" then list, why = self:Preview(raw, action) end
    if why then return false, why end
    if #list == 0 then return false, "empty" end
    self:_Queue({ action = action, rules = rules }, list)
    return true
end

local function itemOf(m)
    return { fullName = m.fullName, name = m.name, key = m.key, rankIndex = m.rankIndex,
             rankName = m.rankName, class = m.class, level = m.level, daysOffline = m.daysOffline,
             attendance = m.attendance, hasAddon = m.hasAddon, status = "pending" }
end

-- The queue `q` ({ action, rules } or { action, target }) of the members of `list`, from its first.
function BulkActions:_Queue(q, list)
    local items = {}
    for i, m in ipairs(list) do items[i] = itemOf(m) end
    q.items, q.pos = items, 1
    local s = state()
    s.queue, s.armed, s.blocked = q, nil, nil
    GuildOS:Print(string.format(L["%s: %d member(s) in the queue, one per click of Next."], self:ActionText(q.action), #items))
    self:Refresh()
end

--- Start a queue that takes the alts of `key`'s group (issue #424) to rank `target` (0-based), by default the main's
--- own: a promotion for the alts below it, a demotion for those above, one step per click; a member done with a step
--- still short of the target is queued again. The main is never in it. Returns true, or false and why: "action",
--- "combat", "permission", "group" (no alts linked), "main" (the main is not on the roster) or "empty".
function BulkActions:StartGroup(key, action, target)
    if action ~= "promote" and action ~= "demote" then return false, "action" end
    if GuildOS.Compat.InCombat() then return false, "combat" end
    if not self:Allowed(action) then return false, "permission" end
    local group = key and GuildOS:GetLinkedChars(key) or {}
    if #group < 2 then return false, "group" end
    local mainKey = group[1]
    local members = self:Collect(false)
    if target == nil then
        for _, m in ipairs(members) do
            if m.key == mainKey then target = m.rankIndex break end
        end
        if target == nil then return false, "main" end
    end
    local list = self.GroupMatch(members, group, mainKey, action, target, self:Context())
    if #list == 0 then return false, "empty" end
    self:_Queue({ action = action, target = target }, list)
    return true
end

local WHY = {
    action = L["Not available on this client."],
    permission = L["Your guild rank may not do this."],
    rule = L["Set at least one rule."],
    empty = L["No members match these rules."],
    combat = L["Not during combat."],
    confirm = L["Confirm the removal first."],
    group = L["No alts are linked to this character."],
    main = L["The main is not in the guild roster."],
    groupEmpty = L["No alt of this group needs that change."],
}

--- What a refusal of Start or Preview says to the player.
function BulkActions:WhyText(why)
    return WHY[why] or WHY.empty
end

--- StartGroup, and say why not when it does not; started, the Bulk actions tab opens on the queue.
function BulkActions:StartGroupAndSay(key, action, target)
    local ok, why = self:StartGroup(key, action, target)
    if not ok then
        GuildOS:Print(self:WhyText(why == "empty" and "groupEmpty" or why))
    elseif GuildOS.UI and GuildOS.UI.OpenWindow then
        GuildOS.UI:OpenWindow("management", "bulk")
    end
    return ok
end

--- `/gos altgroup <promote | demote> <name> [rank]`: the rank by its name or its number in the game's list (1 is the
--- guild master's); none is the main's.
function BulkActions:CommandGroup(rest)
    local action, tail = strtrim(rest or ""):match("^(%S+)%s+(.+)$")
    action = action and action:lower()
    if (action ~= "promote" and action ~= "demote") or not tail then
        GuildOS:Print(L["Usage: /gos altgroup <promote | demote> <name> [rank]"])
        return
    end
    -- The whole rest as a roster name first: a WoW: Forever surname has a space ("Chehul Druida").
    local key, rank = GuildOS:RosterKey(tail), ""
    if not key then
        local who, r = tail:match("^(.-)%s+(%S+)$")
        if not who then who = tail end
        rank = r or ""
        key = GuildOS:RosterKey(who) or GuildOS:GetPlayerKey(who)
    end
    local target
    if rank ~= "" then
        local ranks = GuildOS.GuildManager and GuildOS.GuildManager:GetRanks() or {}
        local n = GuildOS.Finite(rank)
        for i, r in ipairs(ranks) do
            if (n and n == i) or r.name:lower() == rank:lower() then target = r.index break end
        end
        if target == nil then
            GuildOS:Print(string.format(L["No guild rank called %s."], rank))
            return
        end
    end
    self:StartGroupAndSay(key, action, target)
end

--- Start, and say why not when it does not.
function BulkActions:StartAndSay(raw, action, confirmed, shown)
    local ok, why = self:Start(raw, action, confirmed, shown)
    if not ok then GuildOS:Print(self:WhyText(why)) end
    return ok
end

--- Drop the queue.
function BulkActions:Stop()
    local s = state()
    s.queue, s.armed, s.blocked = nil, nil, nil
    self:Refresh()
end

-- The member's roster line now: its index and rank, or nil when they are not in the guild. By the whole name the
-- roster gave, never a short one: on retail Bob-A gone while Bob-B stays must read as gone.
local function live(item)
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name == item.fullName then return i, rankIndex end
    end
    return nil
end

--- The member the next click acts on, read again from the roster, or nil when the queue is through. Who left, whose
--- rank moved, or who no longer meets the rules (logged in since, say) is skipped on the way.
function BulkActions:Current()
    local q = self:Queue()
    if not q then return nil end
    local ctx
    while q.items[q.pos] do
        local item = q.items[q.pos]
        if item.status == "pending" then
            local idx, rank = live(item)
            local m = idx and (q.rules or q.target) and memberAt(idx, q.rules and usesAttendance(q.rules) and self:HasAttendance())
            ctx = ctx or self:Context()
            -- A queue from rules checks them again; one for a group of alts, that the target is still ahead (#424).
            local still = m and (q.rules and self.Meets(m, q.rules) or (not q.rules and self.Toward(m.rankIndex, q.action, q.target)))
            if not idx then
                item.status, item.why = "skipped", "left"
            elseif rank ~= item.rankIndex then
                item.status, item.why = "skipped", "rank"
            elseif m and not (self.Eligible(m, q.action, ctx) and still) then
                item.status, item.why = "skipped", "rules"
            else
                return item
            end
        end
        q.pos = q.pos + 1
    end
    return nil
end

--- Counts of the queue's items by status: { pending, sent, unconfirmed, done, skipped, total }.
function BulkActions:Counts()
    local c = { pending = 0, sent = 0, unconfirmed = 0, done = 0, skipped = 0, total = 0 }
    local q = self:Queue()
    for _, item in ipairs(q and q.items or {}) do
        c[item.status] = (c[item.status] or 0) + 1
        c.total = c.total + 1
    end
    return c
end

function BulkActions:ActionText(action)
    if action == "promote" then return L["Promote"] end
    if action == "demote" then return L["Demote"] end
    return L["Remove"]
end

--- What the Next button says: the action and the member it is for, or why there is nothing to click.
function BulkActions:NextLabel()
    local q = self:Queue()
    if not q then return L["Next"] end
    local item = self:Current()
    if not item then return L["Done"] end
    return self:ActionText(q.action) .. " " .. item.name
end

-- Whether the click prints the line instead of the button running it.
function BulkActions:Typed()
    return state().typed == true or not GuildOS.Compat.SecureGuildMacro()
end

local function finishLine()
    local c = BulkActions:Counts()
    GuildOS:Print(string.format(L["Bulk actions done: %d done, %d waiting for the roster, %d skipped."],
        c.done, c.sent, c.skipped))
    if c.unconfirmed > 0 then
        GuildOS:Print(string.format(L["%d not confirmed: check them in the guild roster."], c.unconfirmed))
    end
end

-- The line for the current member, after the checks every click makes; nil (and why, printed) otherwise.
function BulkActions:_Line()
    local q = self:Queue()
    if not q then
        GuildOS:Print(L["No bulk action is running. Set one up in Leadership > Bulk actions."])
        return nil
    end
    if GuildOS.Compat.InCombat() then GuildOS:Print(L["Not during combat."]) return nil end
    if not self:Allowed(q.action) then
        GuildOS:Print(L["Your guild rank may not do this."])
        return nil
    end
    local item = self:Current()
    if not item then finishLine() return nil end
    local line = GuildOS.Compat.GuildRankCommand(q.action, item.fullName)
    if not line then
        item.status, item.why = "skipped", "name"
        q.pos = q.pos + 1
        self:Refresh()
        return nil
    end
    return line, item
end

--- The secure button's PreClick: the line this click runs, or nil (the button then runs nothing). Only on the click
--- event the button acts on (Compat.SecureClickActs). Where the click cannot run it, prints it to type instead.
function BulkActions:Arm(down)
    if not GuildOS.Compat.SecureClickActs(down) then return nil end
    local s = state()
    s.armed, s.blocked = nil, nil
    if self:Typed() then return self:_TypedNext() end
    local line, item = self:_Line()
    if not line then return nil end
    -- This click's member, from now until PostClick: a block the game raises while it runs the line is about them.
    s.armed, s.armedLine = item, line
    return line
end

-- Where the click cannot run the line: print it for the officer to type, and go on to the next member.
function BulkActions:_TypedNext()
    local line, item = self:_Line()
    if not line then return nil end
    GuildOS:Print(string.format(L["Type %s in chat, then click Next for the one after."], line))
    self:_Sent(item, line)
    return nil
end

--- The secure button's PostClick: the click ran the armed line, unless the game blocked it while it ran. Then the
--- member was never sent: they stay next, and the next click prints their line to type.
function BulkActions:AfterClick(down)
    if not GuildOS.Compat.SecureClickActs(down) then return end
    local s = state()
    local item, line, blocked = s.armed, s.armedLine, s.blocked
    s.armed, s.armedLine, s.blocked = nil, nil, nil
    if not item then return end
    if blocked then
        -- Still next, never sent: the next click prints this member's line to type (typed mode is on now).
        GuildOS:Print(L["The game blocked the click. Click Next again: it shows the line to type."])
        self:Refresh()
        return
    end
    self:_Sent(item, line)
end

--- `/gos bulk next`. A typed command is the addon's code, which may not run the game's protected command: it says who
--- is next and how to act (where the line is typed anyway, it is the click's twin).
function BulkActions:CommandNext()
    if self:Typed() then return self:_TypedNext() end
    local line, item = self:_Line()
    if not line then return nil end
    GuildOS:Print(string.format(L["Next: %s (%s). Click Next in Leadership > Bulk actions, or a macro with %s."],
        item.name, item.rankName or "?", GuildOS.Compat.ClickMacro(self.BUTTON)))
    return nil
end

--- Skip the current member.
function BulkActions:Skip()
    local q = self:Queue()
    local item = self:Current()
    if not (q and item) then return false end
    item.status, item.why = "skipped", "you"
    q.pos = q.pos + 1
    self:Refresh()
    return true
end

function BulkActions:_Sent(item, line)
    local q = self:Queue()
    item.status, item.sentAt, item.sentClock = "sent", GetServerTime(), GetTime()
    if q then
        for i, it in ipairs(q.items) do if it == item then q.pos = i + 1 break end end
    end
    local nextItem = self:Current()
    if not self:Typed() then
        GuildOS:Print(nextItem and string.format(L["Sent %s. Next: %s."], line or "?", nextItem.name)
            or string.format(L["Sent %s. That was the last one."], line or "?"))
    end
    -- Timers only ask and look: the roster again, then whether it showed the change. Never another action.
    GuildOS.Compat.After(ROSTER_ASK_DELAY, function() GuildOS.Compat.GuildRoster() end)
    GuildOS.Compat.After(UNCONFIRMED_AFTER, function() GuildOS:SafeCall(BulkActions.Confirm, BulkActions) end)
    self:Refresh()
end

----------------------------------------------------------------------
-- What the roster then shows
----------------------------------------------------------------------
-- Whether the Roster Log already holds this change, from the game's own guild message (RosterLog's detection).
local function alreadyLogged(act, item)
    local RL = GuildOS.RosterLog
    local events = GuildOS.db and GuildOS.db.rosterLog and GuildOS.db.rosterLog.events or {}
    local target = RL and RL:_NormShort(item.fullName) or short(item.fullName)
    for i = #events, 1, -1 do
        local e = events[i]
        if (e.timestamp or 0) < (item.sentAt or 0) - LOGGED_SLACK then break end
        if e.action == act and e.target == target then return true end
    end
    return false
end

--- On a roster update: each clicked member whose rank moved the asked way (or who is gone, for a removal) is done,
--- and goes to the Roster Log unless the game's own guild message already put it there.
function BulkActions:Confirm()
    local q = self:Queue()
    if not q then return end
    local changed = false
    local now = GetTime()
    for _, item in ipairs(q.items) do
        if item.status == "sent" or item.status == "unconfirmed" then
            local idx, rank = live(item)
            local done = (q.action == "remove" and not idx)
                or (idx and q.action == "promote" and rank and rank < item.rankIndex)
                or (idx and q.action == "demote" and rank and rank > item.rankIndex)
            if done then
                item.status, changed = "done", true
                local act = LOG_ACTION[q.action]
                if GuildOS.RosterLog and not alreadyLogged(act, item) then
                    local detail = rank and GuildOS.GuildManager and GuildOS.GuildManager:GetRankName(rank) or nil
                    GuildOS.RosterLog:Record(act, item.fullName, GuildOS.Compat.PlayerName(), detail)
                end
                -- A group's alt one step on and still short of the main's rank: queued again for its next step (#424).
                if q.target and idx and self.Toward(rank, q.action, q.target) then
                    local again = {}
                    for f, v in pairs(item) do again[f] = v end
                    again.status, again.why, again.sentAt, again.sentClock = "pending", nil, nil, nil
                    again.rankIndex = rank
                    again.rankName = GuildOS.GuildManager and GuildOS.GuildManager:GetRankName(rank) or item.rankName
                    q.items[#q.items + 1] = again
                end
            elseif item.status == "sent" and now - (item.sentClock or now) >= UNCONFIRMED_AFTER then
                item.status, changed = "unconfirmed", true
            end
        end
    end
    if changed then self:Refresh() end
end

-- A guild rank function's name, as a blocked-action event names it ("GuildPromote", "C_GuildInfo.Demote", ...).
local function rankFunction(fn)
    return type(fn) == "string" and (fn:find("Promote") or fn:find("Demote") or fn:find("Uninvite")
        or fn:find("Remove")) ~= nil
end

--- A blocked-action event. It counts only while a click of Next runs its line (between PreClick and PostClick: the
--- game raises it there), only for GuildOS (ADDON_*: arg1 is the addon) and only for a rank function. Then that
--- click's member is not marked sent by a click that did nothing, and from now on the click prints the line to type.
--- A member already sent is never put back.
function BulkActions:OnBlocked(event, arg1, arg2)
    local s = state()
    if not s.armed then return end
    local fn = arg1
    if event:find("^ADDON_") then
        if arg1 ~= "GuildOS" then return end
        fn = arg2
    end
    if not rankFunction(fn) then return end
    s.blocked, s.typed = true, true
end

function BulkActions:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

--- `/gos bulk [next | skip | stop]`.
function BulkActions:Command(rest)
    rest = strtrim(rest or ""):lower()
    if rest == "" then
        GuildOS.UI:OpenWindow("management", "bulk")
    elseif rest == "next" then
        self:CommandNext()
    elseif rest == "skip" then
        if not self:Skip() then GuildOS:Print(L["No bulk action is running. Set one up in Leadership > Bulk actions."]) end
    elseif rest == "stop" then
        self:Stop()
        GuildOS:Print(L["Bulk action stopped."])
    else
        GuildOS:Print(L["Usage: /gos bulk [next | skip | stop]"])
    end
end
