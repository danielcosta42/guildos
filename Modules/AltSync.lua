----------------------------------------------------------------------
-- Guild OS - Alt links, synced per link (issue #424)
--
-- Which character is whose alt is the officers' word, and every client keeps it. Before #424 it
-- travelled as one table ("AL") that replaced the receiver's whole table: no time, no merge, no
-- tombstone. Any officer with an old or empty table (a new install, an officer offline when another
-- linked, a database the game recreated) answered every sync request with it and wiped everybody's
-- links, other officers' included, and an unlink came back when an old table was sent again.
--
-- Now each alt is one entry `{ main, author, ts }` with its own revision, `{ removed = true }` when
-- unlinked, synced like the ban list (domain "alt" on the SyncService, officer writes over GUILD):
--   * a write takes revision max(server time, last + 1), so the newer edit wins on every client and
--     two officers linking different alts at once both stand;
--   * an officer re-sends every entry at its STORED revision on a sync request (Backfill), in batches
--     spaced out so a big guild's channel stays quiet (#324); a stale re-send never rolls anything back;
--   * an unlink is a tombstone, kept a year; its revision is kept for good, so an older link for that
--     alt is refused even after the tombstone is gone;
--   * a backfill goes at most once per BACKFILL_GAP on the answer to a sync request (a /gos sync forces it).
--
-- `db.altLinks` ([altKey] = mainKey) stays what every reader reads (AltRoster, ChatTweaks,
-- MemberDetail, CoreManager, AllianceSync, CompanionExport...): it is now rebuilt from the entries,
-- flat (an alt never points at an alt), plus, on a member's client, the member's own claims still
-- waiting for an officer (AltAutoDetect:Overlay).
--
-- The links from before #424 are "unconfirmed": revision 0, `legacy = true`. Each client migrates its own
-- old table, and those tables differ where an officer was offline for a change. A union of them would bring
-- back every unlink one late officer missed, so a client that had a table of its own never takes another
-- client's unconfirmed link: only a client that had nothing (a new install) does, and an officer's tombstone or
-- link (revision 1 or more) beats them all. An officer confirms one by linking it again (LinkAlt, a claim).
-- There is no way to tell a new install from an officer whose old table was empty because every link was
-- unlinked: that one takes the others' unconfirmed links too.
--
-- A client before #424 still sends and reads "AL" (and replaces its table with it). This one sends it only
-- after hearing such a client recently (CommSystem:LegacyHeard), with a mark old clients ignore, and ignores
-- the "AL" of clients that carry the mark. An old client's "AL" is taken in only as a merge: an alt this client
-- has never heard of at all (no entry, no revision, so never a tombstone) is added unconfirmed, nothing is
-- removed or changed, an empty one is nothing. An unconfirmed link the old officer's newest table lacks (an
-- unlink made there, or a stale table: no way to tell) stays on this client's view but is left out of what this
-- client sends old clients and of its backfill, so it does not undo that unlink on them.
----------------------------------------------------------------------
local AltSync = {}
GuildOS.AltSync = AltSync

AltSync.DOMAIN = "alt"
AltSync.BATCH = 40              -- entries per envelope
AltSync.BATCH_GAP = 2           -- seconds between the envelopes of one backfill (#324)
AltSync.BACKFILL_GAP = 600      -- a backfill on a sync request's answer at most once per 10 minutes (#324)
AltSync.TOMBSTONE_TTL = 365 * 86400
AltSync.LEGACY_REV = 0          -- unconfirmed: a link from the table a client before #424 kept or sent
AltSync.KEY_MAX = 80            -- bytes of a key off the network

local function db() return GuildOS.db end

-- The store: { links = { [altKey] = entry }, rev = { [altKey] = n } }. Built from the old table the first
-- time it is asked for (Migrate), so a client that never ran Initialize still reads the same links.
function AltSync:_Store()
    local d = db()
    if type(d) ~= "table" then return { links = {}, rev = {} } end
    if type(d.altSync) ~= "table" then self:Migrate(d) end
    local s = d.altSync
    if type(s.links) ~= "table" then s.links = {} end
    if type(s.rev) ~= "table" then s.rev = {} end
    return s
end

function AltSync:Initialize()
    if GuildOS.SyncService then
        GuildOS.SyncService:On(self.DOMAIN, function(env, sender) AltSync:OnSync(env, sender) end)
    end
    self:_Store()
    self:Normalize()
    self:Prune()
    self:Rebuild()
end

----------------------------------------------------------------------
-- Migration and keys
----------------------------------------------------------------------
--- The links of the table a version before #424 kept, as unconfirmed entries (revision 0, no author): any
--- officer's entry for the same alt replaces them. `fresh` when there was nothing: the only client that takes
--- other clients' unconfirmed links. Once per database.
function AltSync:Migrate(d)
    local links, rev = {}, {}
    for alt, main in pairs(type(d.altLinks) == "table" and d.altLinks or {}) do
        if type(alt) == "string" and type(main) == "string" then
            local la, lm = GuildOS:LocalMemberKey(alt), GuildOS:LocalMemberKey(main)
            if la ~= "" and lm ~= "" and la ~= lm then
                links[la] = { main = lm, ts = 0, legacy = true }
            end
        end
    end
    d.altSync = { v = 1, links = links, rev = rev, fresh = next(links) == nil or nil }
end

--- WoW: Forever keys a member by the client's realm, which can change (#97, #394): every key and main
--- this client's way, two entries for one alt settled by the higher revision. Elsewhere a realm is a player.
function AltSync:Normalize()
    if GuildOS:RealmBound() then return end
    local s = self:_Store()
    local links, rev = {}, {}
    for k, e in pairs(s.links) do
        local lk = GuildOS:LocalMemberKey(k)
        local r = s.rev[k] or 0
        if type(e) == "table" and type(lk) == "string" and lk ~= "" then
            if e.main then e.main = GuildOS:LocalMemberKey(e.main) end
            if not (e.main and e.main == lk) and (rev[lk] == nil or r > rev[lk]) then
                links[lk], rev[lk] = e, r
            end
        end
    end
    for k, r in pairs(s.rev) do   -- a revision with no entry left (a tombstone gone) still counts
        local lk = GuildOS:LocalMemberKey(k)
        if type(lk) == "string" and lk ~= "" and (rev[lk] or 0) < r then rev[lk] = r end
    end
    s.links, s.rev = links, rev
end

--- Drop the tombstones older than TOMBSTONE_TTL. Their revision stays.
function AltSync:Prune(now)
    now = now or GetServerTime()
    local s = self:_Store()
    for k, e in pairs(s.links) do
        if type(e) ~= "table" or (e.removed and (e.ts or 0) < now - self.TOMBSTONE_TTL) then s.links[k] = nil end
    end
end

----------------------------------------------------------------------
-- The view (pure helpers, tools/alt-sync.lua)
----------------------------------------------------------------------
--- [altKey] = mainKey from the entries: the standing links only.
function AltSync.Base(entries)
    local out = {}
    for k, e in pairs(entries or {}) do
        if type(e) == "table" and not e.removed and type(e.main) == "string" and e.main ~= k then out[k] = e.main end
    end
    return out
end

--- The links flat: each alt points at the main at the end of its chain, never at another alt. Two edits made at
--- once on two clients can leave a loop (A links X to Y while B links Y to X): the loop's lowest key is its main.
function AltSync.Flatten(links)
    local out = {}
    for k in pairs(links or {}) do
        local path, at, node = {}, {}, k
        while links[node] ~= nil and not at[node] do
            path[#path + 1] = node
            at[node] = #path
            node = links[node]
        end
        local root = node
        if at[node] then   -- a loop, from where `node` first was on the path
            root = node
            for i = at[node], #path do if path[i] < root then root = path[i] end end
        end
        if root ~= k then out[k] = root end
    end
    return out
end

--- The links as the officers have them, without a member's own claims.
function AltSync:BaseView()
    return self.Flatten(self.Base(self:_Store().links))
end

--- The links an officer said: without the ones this client only migrated from its own old table, which on a
--- member's client held the member's own claims too. What tells a member a claim was applied.
function AltSync:HeardView()
    local heard = {}
    for k, e in pairs(self:_Store().links) do
        if type(e) == "table" and e.author ~= nil then heard[k] = e end
    end
    return self.Flatten(self.Base(heard))
end

--- The links for a client before #424, which replaces its whole table with it: the view, without an unconfirmed
--- link an old officer's newest table lacks (OnLegacyList). Nil when this client knows no entry at all (a new
--- install has nothing to tell them); an empty table when every link it knows is unlinked.
function AltSync:LegacyView()
    local s = self:_Store()
    if next(s.links) == nil then return nil end
    local keep = {}
    for k, e in pairs(s.links) do
        if type(e) == "table" and not e.legacyGone then keep[k] = e end
    end
    return self.Flatten(self.Base(keep))
end

--- The entries, read only: AltAutoDetect asks whether an officer answered a claim.
function AltSync:Entries()
    return self:_Store().links
end

--- Rebuild `db.altLinks` from the entries (and, on a member's client, the member's own waiting claims).
function AltSync:Rebuild()
    local d = db()
    if type(d) ~= "table" then return end
    local view = self:BaseView()
    if GuildOS.AltAutoDetect and GuildOS.AltAutoDetect.Overlay then
        view = self.Flatten(GuildOS.AltAutoDetect:Overlay(view))
    end
    d.altLinks = view
end

----------------------------------------------------------------------
-- Which entry wins
----------------------------------------------------------------------
local function tie(e)
    return (e.removed and "" or (e.main or "")) .. "\0" .. (e.author or "")
end

--- Whether `entry` at `rev` replaces `held` at `cur`. The higher revision wins. At the same revision: nothing the
--- client has seen and dropped comes back; an entry this client only migrated yields to any officer's; else the
--- same answer on every client (by main, then author), so two officers' migrations settle on one.
function AltSync.Wins(rev, entry, cur, held)
    cur = cur or 0
    if rev > cur then return true end
    if rev < cur or not held then return false end
    if held.author == nil then return entry.author ~= nil end
    return tie(entry) > tie(held)
end

----------------------------------------------------------------------
-- Writing (officers)
----------------------------------------------------------------------
local function wire(k, e, rev)
    return { k = k, m = (not e.removed) and e.main or nil, x = e.removed and true or nil,
             a = e.author, t = e.ts, r = rev }
end

local function publish(items)
    local SS = GuildOS.SyncService
    if not SS or #items == 0 then return end
    for i = 1, #items, AltSync.BATCH do
        local batch = {}
        for j = i, math.min(i + AltSync.BATCH - 1, #items) do batch[#batch + 1] = items[j] end
        SS:Publish(AltSync.DOMAIN, "set", { links = batch }, { priority = "BULK" })
    end
end

--- Write `changes` ([altKey] = mainKey, or false to unlink) as this officer's, publish them and rebuild the view.
--- Returns how many entries were written.
function AltSync:Write(changes)
    if not GuildOS:IsOfficer() then return 0 end
    local s = self:_Store()
    local now = GetServerTime()
    local me = GuildOS.Compat.PlayerName()
    local items, keys = {}, {}
    for k in pairs(changes) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local main = changes[k]
        local rev = math.max(now, (s.rev[k] or 0) + 1)
        local e
        if main then
            e = { main = main, author = me, ts = now }
        else
            e = { removed = true, author = me, ts = now }
        end
        s.links[k], s.rev[k] = e, rev
        items[#items + 1] = wire(k, e, rev)
    end
    if #items == 0 then return 0 end
    publish(items)
    self:Rebuild()
    -- And the whole view to the clients before #424, which still replace their table with it.
    if GuildOS.CommSystem then GuildOS.CommSystem:BroadcastAltLinks() end
    self:Refresh()
    return #items
end

--- Make the officers' links equal `links` ([altKey] = mainKey, as LinkAlt, SetMain and a member's claim plan
--- them from `db.altLinks`): every alt whose entry says otherwise is written, linked or unlinked. An alt in
--- `confirm` (a set: the alts the officer named) is written too when its link is only unconfirmed, which makes
--- it an officer's. Officers only. Returns how many entries were written.
function AltSync:Commit(links, confirm)
    if not GuildOS:IsOfficer() or type(links) ~= "table" then return 0 end
    local entries = self:_Store().links
    local held = self.Base(entries)
    local changes = {}
    for k, m in pairs(links) do
        local e = entries[k]
        if m ~= k and (held[k] ~= m or (confirm and confirm[k] and type(e) == "table" and e.legacy)) then
            changes[k] = m
        end
    end
    for k in pairs(held) do
        if links[k] == nil then changes[k] = false end
    end
    return self:Write(changes)
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
local function key(v)
    if type(v) ~= "string" or v == "" or #v > AltSync.KEY_MAX or v:find("|", 1, true) then return nil end
    return GuildOS:LocalMemberKey(v)
end

--- Apply officer entries off the network ({ k, m, x, a, t, r } each). `sender` is the officer SyncService checked;
--- an entry names its own author, else the sender. An unconfirmed link (r = 0) is taken only by a `fresh` client,
--- for an alt it knows nothing of. Returns how many were applied.
function AltSync:Apply(list, sender)
    if type(list) ~= "table" then return 0 end
    local s = self:_Store()
    local applied = 0
    for _, it in ipairs(list) do
        local k = type(it) == "table" and key(it.k)
        local rev = k and GuildOS.Finite(it.r)
        local removed = k and it.x == true
        local main = k and not removed and key(it.m)
        local author = (type(it) == "table" and type(it.a) == "string" and it.a ~= "" and #it.a <= self.KEY_MAX)
            and it.a or sender
        if k and rev == 0 and s.fresh and main and main ~= k and s.links[k] == nil and (s.rev[k] or 0) == 0 then
            s.links[k] = { main = main, author = author, ts = 0, legacy = true }
            applied = applied + 1
        elseif k and rev and rev >= 1 and (removed or (main and main ~= k)) then
            local e = {
                main = main or nil, removed = removed or nil, author = author,
                ts = GuildOS.Finite(it.t) or 0,
            }
            if self.Wins(rev, e, s.rev[k], s.links[k]) then
                s.links[k] = e
                if rev > (s.rev[k] or 0) then s.rev[k] = rev end
                applied = applied + 1
            end
        end
    end
    return applied
end

-- What follows an officer's word on the links: a member's claims it answered go, the view is rebuilt.
function AltSync:_AfterRemote()
    if GuildOS.AltAutoDetect then GuildOS.AltAutoDetect:OnOfficerLinks() end
    self:Rebuild()
    self:Refresh()
end

function AltSync:OnSync(env, sender)
    if env.act ~= "set" or type(env.data) ~= "table" then return end
    if self:Apply(env.data.links, sender) > 0 then
        self:_AfterRemote()
    elseif GuildOS.AltAutoDetect then
        GuildOS.AltAutoDetect:OnOfficerLinks()   -- an officer is online: a claim waiting goes to them
    end
end

--- The table "AL" a client before #424 sends ([altKey] = mainKey): an alt this client has never heard of at all
--- (no entry, no revision: never a tombstone, even a pruned one) is added unconfirmed, and a link this client only
--- migrated from its own old table and the list says too counts as an officer's word from now on. Nothing is
--- removed or changed by it; an empty table is nothing. An unconfirmed link it lacks (or gives another main) is
--- marked `legacyGone`: kept on this view, left out of LegacyView and of the backfill, until an old table has it
--- again. `sender` is the officer CommSystem checked.
function AltSync:OnLegacyList(links, sender)
    if type(links) ~= "table" then return end
    local s = self:_Store()
    local added, said = 0, {}
    for alt, main in pairs(links) do
        local la, lm = key(alt), key(main)
        local held = la and s.links[la]
        if la and lm and la ~= lm then said[la] = lm end
        if la and lm and la ~= lm and held == nil and (s.rev[la] or 0) == 0 then
            s.links[la] = { main = lm, author = sender, ts = 0, legacy = true }
            added = added + 1
        elseif type(held) == "table" and held.author == nil and not held.removed and held.main == lm then
            held.author = sender
            added = added + 1
        end
    end
    if next(said) ~= nil then   -- an empty table says nothing, not "everything unlinked"
        for k, e in pairs(s.links) do
            if type(e) == "table" and e.legacy then e.legacyGone = (said[k] ~= e.main) or nil end
        end
    end
    if added > 0 then
        self:_AfterRemote()
    elseif GuildOS.AltAutoDetect then
        GuildOS.AltAutoDetect:OnOfficerLinks()
    end
end

----------------------------------------------------------------------
-- Cold sync
----------------------------------------------------------------------
--- Every entry, tombstones included, at its stored revision (an unconfirmed link at 0, but not one an old officer's
--- table lacks), in batches BATCH_GAP seconds apart. On the answer to a sync request (CommSystem:_Answer) at most
--- once per BACKFILL_GAP, and on a /gos sync (`force`). Officers only; one backfill at a time.
function AltSync:Backfill(force)
    if not GuildOS:IsOfficer() or not GuildOS.SyncService or self._backfilling then return end
    local now = GetTime()
    if not force and self._backfillAt and now - self._backfillAt < self.BACKFILL_GAP then return end
    local s = self:_Store()
    local keys = {}
    for k, e in pairs(s.links) do
        if (s.rev[k] or 0) >= 1 or (type(e) == "table" and e.legacy and not e.legacyGone) then keys[#keys + 1] = k end
    end
    if #keys == 0 then return end
    table.sort(keys)
    self._backfillAt = now
    local items = {}
    for _, k in ipairs(keys) do items[#items + 1] = wire(k, s.links[k], s.rev[k] or self.LEGACY_REV) end
    local batches = {}
    for i = 1, #items, self.BATCH do
        local b = {}
        for j = i, math.min(i + self.BATCH - 1, #items) do b[#b + 1] = items[j] end
        batches[#batches + 1] = b
    end
    self._backfilling = true
    local function send(i)
        if not batches[i] then self._backfilling = nil return end
        GuildOS.SyncService:Publish(self.DOMAIN, "set", { links = batches[i] }, { priority = "BULK" })
        if batches[i + 1] then
            GuildOS.Compat.After(self.BATCH_GAP, function() send(i + 1) end)
        else
            self._backfilling = nil
        end
    end
    send(1)
end

----------------------------------------------------------------------
-- The alt limit (/gos altlimit N)
----------------------------------------------------------------------
--- Pure: the groups with more than `n` alts, most first: { { main, alts = { keys } } }.
function AltSync.OverLimit(links, n)
    local groups = {}
    for alt, main in pairs(links or {}) do
        groups[main] = groups[main] or {}
        table.insert(groups[main], alt)
    end
    local out = {}
    for main, alts in pairs(groups) do
        if #alts > n then
            table.sort(alts)
            out[#out + 1] = { main = main, alts = alts }
        end
    end
    table.sort(out, function(a, b)
        if #a.alts ~= #b.alts then return #a.alts > #b.alts end
        return a.main < b.main
    end)
    return out
end

local function short(k) return (k:match("^([^-]+)") or k) end

--- `/gos altlimit N`: says which groups have more than N alts.
function AltSync:CommandLimit(rest)
    local L = GuildOS.L
    local n = GuildOS.Finite(strtrim(rest or ""))
    if not n or n < 0 or n ~= math.floor(n) then
        GuildOS:Print(L["Usage: /gos altlimit <number>"])
        return
    end
    local over = self.OverLimit(db() and db().altLinks, n)
    if #over == 0 then
        GuildOS:Print(string.format(L["No group has more than %d alt(s)."], n))
        return
    end
    GuildOS:Print(string.format(L["%d group(s) with more than %d alt(s):"], #over, n))
    for _, g in ipairs(over) do
        local names = {}
        for i, k in ipairs(g.alts) do names[i] = short(k) end
        GuildOS:Print(string.format("  %s (%d): %s", short(g.main), #g.alts, table.concat(names, ", ")))
    end
end

function AltSync:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end
