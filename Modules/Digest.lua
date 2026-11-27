----------------------------------------------------------------------
-- Guild OS - Login Digest
-- "Since your last login: N new members, X items looted, ..." — a quick
-- catch-up shown once on login (and on demand via /guildos digest).
-- Build() is pure data; the popup uses the UI factories at runtime.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Digest = {}
GuildOS.Digest = Digest
local L = GuildOS.L

local FEED_LINES = 5             -- lines from guildos.me in one digest
local FEED_SEEN_S = 14 * 86400   -- how long a line shown is remembered: the site sends a week of them

function Digest:Initialize()
    GuildOS.db.digest = GuildOS.db.digest or {}
    if GuildOS.db.digest.enabled == nil then GuildOS.db.digest.enabled = true end
    if GuildOS.db.digest.lastSeen == nil then GuildOS.db.digest.lastSeen = 0 end
    GuildOS.db.digest.feedSeen = GuildOS.db.digest.feedSeen or {}
end

-- What guildos.me said that this client has not shown yet (guildos-web #259), the newest first, and
-- what the block as a whole tells: an event the site says is not said again by this client's own lines.
local function fromSite()
    local seen = GuildOS.db.digest and GuildOS.db.digest.feedSeen or {}
    local unseen, told = {}, {}
    for _, item in ipairs(GuildOS.CompanionImport and GuildOS.CompanionImport:FeedLines() or {}) do
        told[item.type] = true
        told[item.type .. "|" .. item.at] = true
        if item.key then told[item.type .. "|" .. item.key] = true end
        if not seen[item.id] and #unseen < FEED_LINES then unseen[#unseen + 1] = item end
    end
    return unseen, told
end

local function myKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
end

-- The categories a digest's news falls in (#449), in the order they are told: the Chronicle's Activity draws
-- each as a card, the login digest as a small header over its lines. id, title, glyph (the round mark of its
-- rows) and its colour, the same wherever it is drawn.
Digest.CATEGORIES = {
    { id = "members",  title = L["Members"],               glyph = "M", color = "3e8e41" },
    { id = "levels",   title = L["Levels and milestones"], glyph = "L", color = "b38a1a" },
    { id = "dungeons", title = L["Dungeons and raids"],    glyph = "D", color = "1d4f99" },
    { id = "loot",     title = L["Loot"],                  glyph = "$", color = "7a3d9a" },
    { id = "renown",   title = L["Achievements and renown"], glyph = "A", color = "b0261b" },
    { id = "guild",    title = L["Guild life"],            glyph = "G", color = "6f5a3c" },
    { id = "site",     title = L["From guildos.me"],       glyph = "W", color = "8a6a2a" },
}

-- A category's colour ("rrggbb") as { r, g, b }.
function Digest.Color(h)
    return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 }
end

local function shortOf(key) return tostring(key):match("^([^-]+)") or tostring(key) end

----------------------------------------------------------------------
-- What changed since `since` (a server timestamp), as data: one table per category of Digest.CATEGORIES, each
-- with its `lines` (what the login digest says) and what the Activity screen draws:
--   members   joined { key, name, at } newest first; left, kick { name, at }; promote, demote { name, detail, at };
--             anniversaries (Milestones:Collect's)
--   levels    dings, attunes, levels (Milestones:Collect's)
--   dungeons  clears (Milestones:Collect's), raids { name, at } newest first
--   loot      items { link, quality, player, at } newest first
-- opts.login: the login's digest, where the bulletin tells only the notices not told yet (#418); elsewhere (the
-- Activity sub-tab, /gos digest) it lists the notices posted since `since`, as it always did.
----------------------------------------------------------------------
function Digest:Collect(since, opts)
    since = since or GuildOS.db.digest.lastSeen or 0
    local m = {}
    for _, c in ipairs(self.CATEGORIES) do m[c.id] = { lines = {} } end
    local function add(cat, line) local l = m[cat].lines; l[#l + 1] = line end
    local feed, told = fromSite()
    local mem = m.members

    -- New members (first observed by Guild OS since `since`, after its first look at the guild)
    mem.joined = {}
    local newSince = math.max(since, GuildOS.db.firstSeenSince or 0)
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
        if ts and ts > newSince then mem.joined[#mem.joined + 1] = { key = key, name = shortOf(key), at = ts } end
    end
    table.sort(mem.joined, function(x, y)
        if x.at ~= y.at then return x.at > y.at end
        return x.name < y.name
    end)
    if #mem.joined > 0 then
        local named = {}
        for i = 1, math.min(3, #mem.joined) do named[i] = mem.joined[i].name end
        local names = table.concat(named, ", ")
        if #mem.joined > #named then names = names .. " +" .. (#mem.joined - #named) end
        add("members", string.format(L["%d new member(s): %s"], #mem.joined, names))
    end

    -- Roster changes (from the audit log): who left, was removed, promoted or demoted
    mem.left, mem.kick, mem.promote, mem.demote = {}, {}, {}, {}
    local AS = { leave = mem.left, kick = mem.kick, promote = mem.promote, demote = mem.demote }
    for _, e in ipairs((GuildOS.RosterLog and GuildOS.RosterLog:EventsSince(since)) or {}) do
        local list = AS[e.action]
        if list then list[#list + 1] = { name = e.target or "?", detail = e.detail, at = e.timestamp or 0 } end
    end
    for _, list in pairs(AS) do table.sort(list, function(x, y) return x.at > y.at end) end
    if #mem.kick > 0 then add("members", string.format(L["%d member(s) removed"], #mem.kick)) end
    if #mem.left > 0 then add("members", string.format(L["%d member(s) left"], #mem.left)) end

    -- Raid sessions tracked
    m.dungeons.raids = {}
    if GuildOS.db.raidTracker and GuildOS.db.raidTracker.sessions then
        for id, s in pairs(GuildOS.db.raidTracker.sessions) do
            if s.startTime and s.startTime > since then
                m.dungeons.raids[#m.dungeons.raids + 1] = { id = id, name = s.name or s.raidName or L["Unknown"], at = s.startTime }
            end
        end
        table.sort(m.dungeons.raids, function(x, y) return x.at > y.at end)
    end
    if #m.dungeons.raids > 0 then
        add("dungeons", string.format(L["%d raid session(s) tracked"], #m.dungeons.raids))
    end

    -- Loot recorded
    m.loot.items = {}
    for _, e in ipairs(GuildOS.db.lootHistory or {}) do
        if (e.timestamp or 0) > since then
            m.loot.items[#m.loot.items + 1] = { link = e.itemLink or e.item or e.itemName or "?", quality = e.quality,
                player = e.player or e.playerKey, at = e.timestamp }
        end
    end
    table.sort(m.loot.items, function(x, y) return x.at > y.at end)
    if #m.loot.items > 0 then
        add("loot", string.format(L["%d item(s) looted"], #m.loot.items))
    end

    -- Your own points change
    if GuildOS.Points and GuildOS.db.points and GuildOS.db.points.log then
        local mk = myKey()
        local delta = 0
        for _, e in ipairs(GuildOS.db.points.log) do
            if e.key == mk and (e.ts or 0) > since then delta = delta + (e.delta or 0) end
        end
        if delta ~= 0 then
            add("renown", string.format(L["Your points changed by %+d (now %d)"], delta, GuildOS.Points:Get(mk)))
        end
    end

    -- Milestones (the cap, attunements, every ten levels, dungeon clears) and guild anniversaries
    if GuildOS.Milestones then
        local ms = GuildOS.Milestones:Collect(since, told)
        m.levels.dings, m.levels.attunes, m.levels.levels = ms.dings, ms.attunes, ms.levels
        m.dungeons.clears, mem.anniversaries = ms.clears, ms.anniversaries
        local by = GuildOS.Milestones:Lines(ms)
        for _, cat in ipairs({ "levels", "dungeons", "members" }) do
            for _, line in ipairs(by[cat]) do add(cat, line) end
        end
    end
    -- WoW: Forever's founding: who joined as a founder, the window, the guild's anniversaries (#209)
    if GuildOS.Founding then
        for _, line in ipairs(GuildOS.Founding:GetDigestLines(since, GetServerTime(), told)) do add("guild", line) end
    end

    -- Today's birthdays and join anniversaries (#428): at the first login of the day, and on demand.
    if GuildOS.Birthdays and not (opts and opts.login and GuildOS.Birthdays:ToldToday(GetServerTime())) then
        for _, line in ipairs(GuildOS.Birthdays:GetDigestLines(GetServerTime())) do
            add("guild", "|cffEDCC7B" .. line .. "|r")
        end
    end

    -- Upcoming raid reminder (event within the next 24h)
    if GuildOS.Calendar and GuildOS.Calendar.GetDigestLines then
        for _, line in ipairs(GuildOS.Calendar:GetDigestLines() or {}) do
            add("guild", "|cff4CB8FF" .. line .. "|r")
        end
    end

    -- Alliance: how many raids open to the alliance are coming up in the next week (guildos.me's,
    -- Alliance:OpenRaids). One line, and only when something is actually scheduled.
    if GuildOS.Alliance and GuildOS.Alliance:Get() then
        local horizon = GetServerTime() + (7 * 86400)
        local count = 0
        for _, e in ipairs(GuildOS.Alliance:OpenRaids()) do
            if (tonumber(e.when) or 0) <= horizon then
                count = count + 1
            end
        end
        if count > 0 then
            local gold = GuildOS.Colors.gold
            add("guild", string.format("|cff%02x%02x%02x", gold.r * 255, gold.g * 255, gold.b * 255) ..
                string.format(L["%d allied event(s) this week"], count) .. "|r")
        end
    end

    -- Bulletin notices. At login, the active ones this player has not been told about (issue #418), the newest
    -- few: each once, whenever it was posted, never one that has ended; ShowOnLogin marks them told. Anywhere
    -- else, the most recent few posted since `since`.
    if GuildOS.Bulletin then
        if opts and opts.login then
            for _, msg in ipairs(GuildOS.Bulletin:Unseen(GetServerTime(), 3)) do
                add("guild", GuildOS.Bulletin.Line(msg))
            end
        else
            local shown = 0
            for _, msg in ipairs(GuildOS.Bulletin:GetMessages()) do
                if type(msg) == "table" and (tonumber(msg.ts) or 0) > since and shown < 3 then
                    add("guild", GuildOS.Bulletin.Line(msg))
                    shown = shown + 1
                end
            end
        end
    end

    -- New polls opened
    if GuildOS.Polls then
        local newPolls = 0
        for _, p in pairs(GuildOS.Polls:GetList()) do
            if not p.closed and (p.ts or 0) > since then newPolls = newPolls + 1 end
        end
        if newPolls > 0 then
            add("guild", string.format(L["%d new poll(s) — cast your vote"], newPolls))
        end
    end

    -- Officer-only catch-up
    if GuildOS:IsOfficer() then
        -- Trials ready to review are not repeated here: the panel's badge and the login line say it (audit B10).
        if GuildOS.GuildManager and GuildOS.GuildManager.GetInactiveMembers then
            local inactive = GuildOS.GuildManager:GetInactiveMembers(GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS)
            if inactive and #inactive > 0 then
                mem.inactive = #inactive
                add("members", string.format(L["%d inactive member(s)"], #inactive))
            end
        end
    end

    -- WoW: Forever: what the guild earned (#216), and the officers' reminder of its setup (#217)
    if GuildOS.Achievements then
        for _, line in ipairs(GuildOS.Achievements:GetDigestLines(told)) do add("renown", line) end
    end
    local setup = GuildOS.Activation and GuildOS.Activation:GetDigestLine(GetServerTime())
    if setup then add("guild", setup) end
    -- Beside other news, never a reason to open the digest on its own at every login.
    local nearest = GuildOS.Achievements and GuildOS.Achievements:NextLine()
    if nearest then
        local any = #feed > 0
        for _, c in ipairs(self.CATEGORIES) do any = any or #m[c.id].lines > 0 end
        if any then add("renown", nearest) end
    end

    for _, item in ipairs(feed) do add("site", item.text) end
    return m
end

-- The categories that have something to say: { id, title (translated), glyph, color, lines }, in order.
function Digest:Groups(model)
    local out = {}
    for _, c in ipairs(self.CATEGORIES) do
        local lines = model[c.id] and model[c.id].lines or {}
        if #lines > 0 then
            out[#out + 1] = { id = c.id, title = c.title, glyph = c.glyph, color = c.color, lines = lines }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Build the digest lines for everything that changed since `since`
-- (a server timestamp). Returns an array of strings, category by category.
----------------------------------------------------------------------
-- lines.groups: the same lines by category (Digest:Groups), which the popup draws under small headers.
function Digest:Build(since, opts)
    local lines = {}
    lines.groups = self:Groups(self:Collect(since, opts))
    for _, g in ipairs(lines.groups) do
        if g.id == "site" then lines[#lines + 1] = "|cffEDCC7B" .. L["From guildos.me"] .. "|r" end
        for _, line in ipairs(g.lines) do lines[#lines + 1] = line end
    end
    return lines
end

-- The login digest showed these: they are not shown again, and what is too old to come back is forgotten.
function Digest:MarkFeedSeen(now)
    local seen = GuildOS.db.digest.feedSeen
    for _, item in ipairs((fromSite())) do seen[item.id] = now end
    for id, at in pairs(seen) do
        if now - at > FEED_SEEN_S then seen[id] = nil end
    end
end

-- Widgets reused across redraws (memory audit): a frame, texture or text the client makes is never freed,
-- so a redraw takes the ones the last one made, by the part each plays (`key`), makes only what is missing
-- and hides what is left over. Take returns the widget and whether it was reused. Kept local to the file:
-- the tools load screens one at a time, under a stubbed UI.
local function NewPool()
    local made, used, pool = {}, {}, {}
    function pool.Begin() for k in pairs(used) do used[k] = 0 end end
    function pool.Take(key, make)
        local n = (used[key] or 0) + 1
        used[key] = n
        local list = made[key]
        if not list then list = {}; made[key] = list end
        local w = list[n]
        if w then
            w:ClearAllPoints()
            w:Show()
            return w, true
        end
        w = make()
        list[n] = w
        return w, false
    end
    function pool.End()
        for key, list in pairs(made) do
            for i = (used[key] or 0) + 1, #list do list[i]:Hide() end
        end
    end
    return pool
end


----------------------------------------------------------------------
-- The popup window.
----------------------------------------------------------------------
function Digest:Show(lines)
    local UI = GuildOS.UI
    local C = GuildOS.Colors
    lines = lines or self:Build()

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSDigestFrame", UIParent, "BackdropTemplate")
        f:SetSize(380, 280)
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        -- A floating window (the mockup's .fw "digest"): its title in the header, a glyph and a line for each
        -- thing that changed (the mockup's .mural), the way into the window in the footer.
        local Kit = rawget(GuildOS, "Kit")
        if Kit then
            Kit:Dress(f, L["Since your last login"])
            Kit:Footer(f)
            f.title, f.close = f.titleText, f.closeBtn
            f.top, f.bottom = Kit.HEADER_H + 10, Kit.FOOT_H + 8
        else
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
            f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
            f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
            UI:StylePopup(f, { shadowSize = 16 })
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
            f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing() end)
            f.title = UI:CreateTitle(f, L["Since your last login"], 15)
            f.title:SetPoint("TOPLEFT", 16, -14)
            f.close = UI:CreateCloseButton(f)
            f.close:SetPoint("TOPRIGHT", -8, -8)
            f.close:SetScript("OnClick", function() f:Hide() end)
            f.top, f.bottom = 44, 48
        end

        f.body = CreateFrame("Frame", nil, f)
        f.body:SetPoint("TOPLEFT", 16, -f.top)
        f.body:SetPoint("BOTTOMRIGHT", -16, f.bottom)

        f.openBtn = UI:CreateButton(f.foot or f, L["Open Guild OS"], 140, 24)
        UI:SetButtonVariant(f.openBtn, "primary")
        if f.foot then f.foot:Lay(f.openBtn) else f.openBtn:SetPoint("BOTTOM", 0, 14) end
        f.openBtn:SetScript("OnClick", function()
            f:Hide()
            GuildOS:ToggleRoster()
        end)
        self.frame = f
    end

    -- (Re)populate the body, on the parts the last showing made (memory audit): /gos digest shows it again.
    self._bodyPool = self._bodyPool or NewPool()
    local pool = self._bodyPool
    pool.Begin()
    local function text(key, size, col)
        return pool.Take(key, function()
            local t = UI:CreateText(f.body, "", size, col.r, col.g, col.b)
            t:SetJustifyH("LEFT")
            return t
        end)
    end

    local y = 0
    if #lines == 0 then
        local empty = text("empty", 11, C.silver)
        empty:SetText(L["Nothing new since your last login."])
        empty:SetPoint("TOPLEFT", 2, -y)
        empty:SetWidth(UI:TextWidth(f.body, 4))
    else
        -- Each line on a round glyph (the mockup's mural: a glyph, then the line). Built by Build, the lines come
        -- by category (#449): a small header over each, its rows on its glyph in its colour. Lines from elsewhere
        -- take their first letter on the metal.
        local glyphs = UI.CreateGlyph ~= nil
        local x = glyphs and 30 or 18
        local groups = lines.groups
        if not groups then groups = { { lines = lines } } end
        for gi, grp in ipairs(groups) do
            local color = grp.color and Digest.Color(grp.color) or (C.metal2 or C.gold)
            if grp.title and #groups > 1 then
                if gi > 1 then y = y + 4 end
                local hc = C.gold2 or C.gold
                local hd = text("heading", 11, hc)
                hd:SetText(grp.title)
                hd:SetPoint("TOPLEFT", 0, -y)
                hd:SetWidth(UI:TextWidth(f.body, 4))
                y = y + 18
            end
            for _, line in ipairs(grp.lines) do
                if glyphs then
                    local g = pool.Take("glyph", function() return UI:CreateGlyph(f.body, 22) end)
                    g:SetPoint("TOPLEFT", 0, -y + 3)
                    local plain = tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    g:Set(grp.glyph or (plain:match("^[%z\1-\127\194-\244][\128-\191]*") or ""):upper(), color)
                else
                    local dot = text("dot", 12, C.label)
                    dot:SetText("*")
                    dot:SetPoint("TOPLEFT", 2, -y)
                end
                local fs = text("line", 11, C.text)
                fs:SetText(line)
                fs:SetPoint("TOPLEFT", x, -y)
                -- Not f.body:GetWidth(): the body is placed by its anchors and reads 0 until the game lays it out, and
                -- a text 34px less than that drew nothing (#449). TextWidth reads the anchors.
                fs:SetWidth(UI:TextWidth(f.body, x + 4))
                y = y + math.max(26, (fs:GetStringHeight() or 14) + 10)
            end
        end
    end
    pool.End()
    -- The title above and the button below: a long digest grows, never runs under the button.
    f:SetHeight(math.max(240, f.top + y + f.bottom))

    f:Show()
    return f
end

----------------------------------------------------------------------
-- Auto-show once on login (skipped on first run and when disabled).
----------------------------------------------------------------------
function Digest:ShowOnLogin()
    local B = GuildOS.Bulletin
    -- From now on a notice that arrives is told in the chat (issue #418).
    if B then B:LoginDone() end
    if not GuildOS.db.digest or not GuildOS.db.digest.enabled then
        -- No digest: the notices not told yet get a chat line each, and so do today's birthdays (#428).
        if B then B:TellInChat(GetServerTime()) end
        if GuildOS.Birthdays then GuildOS.Birthdays:TellInChat(GetServerTime()) end
        return
    end
    if self.shownThisSession then return end
    -- A raid owner's prompt took this login (issue #400): one popup at a time, and the raid about to start is the
    -- one that cannot wait. Nothing is marked seen: the digest shows once the prompt is put off (Later or its close,
    -- RaidStart:PromptDismissed), and after Raid ready waits for the next login, or /gos digest.
    if GuildOS.RaidStart and GuildOS.RaidStart:PromptedAtLogin() then
        self.deferred = true
        return
    end

    local since = GuildOS.db.digest.lastSeen or 0
    -- First ever run: nothing to compare against — just start the clock.
    if since == 0 then
        GuildOS.db.digest.lastSeen = GetServerTime()
        -- The board is not part of that clock: what is on it now is told in the chat.
        if B then B:TellInChat(GetServerTime()) end
        return
    end

    local lines = self:Build(since, { login = true })
    self:MarkFeedSeen(GetServerTime())
    if B then B:MarkSeen(GetServerTime()) end
    if GuildOS.Achievements then GuildOS.Achievements:MarkSeen() end
    if GuildOS.Birthdays then GuildOS.Birthdays:MarkTold(GetServerTime()) end
    if GuildOS.Activation then
        if GuildOS.Activation:GetDigestLine(GetServerTime()) then GuildOS.Activation:Reminded(GetServerTime()) end
    end
    GuildOS.db.digest.lastSeen = GetServerTime()
    self.shownThisSession = true
    if #lines > 0 then
        -- Never in combat, one login popup at a time (audit B21).
        GuildOS:ShowWhenClear("digest", function() return self:Show(lines) end)
    end
end
