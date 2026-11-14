----------------------------------------------------------------------
-- Guild OS - LFG Board
-- Members mark themselves available for a group (roles + activities + note + TTL).
-- Everyone sees a live board. An entry is always keyed by the comm
-- envelope sender, so nobody can publish availability for someone else.
-- The board is drawn by the Groups tab (UI/GroupsPanel.lua, issue #341); the groups being
-- formed are Modules/Groups.lua.
----------------------------------------------------------------------
local LFGBoard = {}
GuildOS.LFGBoard = LFGBoard
local L = GuildOS.L
local LibSerialize = LibStub("GuildOS-LibSerialize")

local DEFAULT_TTL = 5400   -- 90 minutes
local TTL_MIN     = 1800   -- 30 minutes, the shortest duration the UI offers
local TTL_MAX     = 7200   -- 120 minutes, the longest duration the UI offers
local NOTE_MAX    = 60
local ACTS_MAX    = 6      -- activities one listing names
local ACT_ID_MAX  = 32     -- bytes of an activity id
local ENTRY_COOLDOWN = 5   -- accept at most one entry per sender per 5s
local GUILD_LINE_COOLDOWN = 300   -- at most one line in guild chat per 5 minutes

LFGBoard.DEFAULTS = { notify = true, postToGuild = true, lastRole = "ANY", lastNote = "",
                      lastTtl = DEFAULT_TTL, allianceScope = false, roles = "", lastMode = "seek" }
LFGBoard.ROLES    = { "ANY", "TANK", "HEALER", "DPS" }
-- The roles of a listing since issue #341: a subset of these letters, in this order. `role` above
-- still goes out beside it, which is all a client before #341 reads.
LFGBoard.ROLE_LETTERS = { "T", "H", "D" }
LFGBoard.DURATIONS = { TTL_MIN, 3600, DEFAULT_TTL, TTL_MAX }
local LETTER_OF = { TANK = "T", HEALER = "H", DPS = "D" }
local ROLE_OF   = { T = "TANK", H = "HEALER", D = "DPS" }

function LFGBoard:Initialize()
    GuildOS.db.lfgBoard = GuildOS.db.lfgBoard or {}
    GuildOS.db.lfgPrefs = GuildOS.db.lfgPrefs or {}
    for k, v in pairs(self.DEFAULTS) do
        if GuildOS.db.lfgPrefs[k] == nil then GuildOS.db.lfgPrefs[k] = v end
    end
    -- Off was the default until #243, and a default is saved, so changing it above reaches nobody
    -- who has ever logged in. Once, for everybody: off by choice and off by default look the same.
    if not GuildOS.db.lfgPrefs.notifyMigrated then
        GuildOS.db.lfgPrefs.notify, GuildOS.db.lfgPrefs.notifyMigrated = true, true
    end
    self._cd = self._cd or {}
    self:Prune()
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:Register("lfg", {
            priority = "NORMAL",
            cap = 100,
            build = function()
                return LFGBoard._BuildAllianceLfg(GuildOS.db.lfgBoard, GetServerTime(), 100)
            end,
        })
    end
    self:_RegisterTests()
    self:_RegisterAllianceTests()
end

function LFGBoard:_RegisterAllianceTests()
    if not GuildOS.SelfTest then return end
    GuildOS.SelfTest:Register("lfgboard.alliance_build_prunes", function()
        local store = {
            ["Ann-R"] = { role = "TANK", note = "MC", ts = 1000, ttl = 600 },   -- alive at 1200
            ["Bob-R"] = { role = "DPS",  note = "any", ts = 100,  ttl = 300 },  -- expired at 1200
            ["Cid-R"] = { role = "HEALER", note = "", ts = 1100, ttl = 600 },   -- alive
        }
        local out = LFGBoard._BuildAllianceLfg(store, 1200, 100)
        if #out ~= 2 then return false, "expired entry crossed the wire: " .. #out end
        if out[1].n ~= "Ann" or out[2].n ~= "Cid" then return false, "not sorted by key" end
        if out[1].r ~= "TANK" then return false, "role lost" end
        if #LFGBoard._BuildAllianceLfg(store, 1200, 1) ~= 1 then return false, "cap not enforced" end
        if #LFGBoard._BuildAllianceLfg(nil, 1200, 100) ~= 0 then return false, "nil must not error" end
        if #LFGBoard._BuildAllianceLfg(store, 99999, 100) ~= 0 then return false, "all expired" end
        return true
    end)
end

----------------------------------------------------------------------
-- Pure helpers (unit tested)
----------------------------------------------------------------------
function LFGBoard:_IsActive(entry, now)
    if not entry or not entry.ts then return false end
    return (entry.ts + (entry.ttl or DEFAULT_TTL)) > (now or 0)
end

-- Minutes left on an entry, as shown in the board's FOR column. Rounds UP so
-- an entry that is still active never renders "0m": flooring made the last 59
-- seconds of every listing read as expired while the row was still on screen.
-- An inactive entry is still 0 (the row is gone by then anyway).
function LFGBoard:_Remaining(entry, now)
    if not self:_IsActive(entry, now) then return 0 end
    return math.max(1, math.ceil(((entry.ts + (entry.ttl or DEFAULT_TTL)) - (now or 0)) / 60))
end

-- onlineSet (optional): { [key] = true } of members currently online.
function LFGBoard:ActiveList(store, now, onlineSet)
    local out = {}
    for key, e in pairs(store or {}) do
        if self:_IsActive(e, now) and (not onlineSet or onlineSet[key]) then
            out[#out + 1] = {
                key = key, name = key:match("^([^-]+)") or key,
                role = e.role or "ANY", note = e.note or "", ts = e.ts, ttl = e.ttl,
                roles = e.roles or LETTER_OF[e.role or "ANY"] or "", acts = e.acts or {},
            }
        end
    end
    -- Newest first, then by key. Without the key tie-break two members who
    -- posted in the same second fall back to pairs() order, so the rows swap
    -- places on every repaint and an Invite click can land on a row that just
    -- moved. Keys are table keys, so they are unique and the order is total.
    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return a.key < b.key
    end)
    return out
end

----------------------------------------------------------------------
-- Alliance pool
----------------------------------------------------------------------

-- Snapshot for the alliance `lfg` domain. Expired entries are pruned HERE, so
-- a dead listing never crosses the wire and never costs a revision on the
-- other side. Sorted by key so the change fingerprint is stable.
function LFGBoard._BuildAllianceLfg(store, now, cap)
    local out = {}
    if type(store) ~= "table" then
        return out
    end
    cap = tonumber(cap) or 100
    local keys = {}
    for key in pairs(store) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if #out >= cap then
            break
        end
        local e = store[key]
        if LFGBoard:_IsActive(e, now) then
            out[#out + 1] = {
                n = key:match("^([^-]+)") or key,
                r = e.role or "ANY",
                t = e.note or "",
                ts = e.ts,
                ttl = e.ttl,
            }
        end
    end
    return out
end

-- Allied listings, in the same row shape the board renderer already consumes.
-- The guild is folded into the note so no renderer change is needed; allied
-- rows carry no `key`, which is what makes them read-only in the board.
function LFGBoard:AllianceList(now)
    local ally, sync = GuildOS.Alliance, GuildOS.AllianceSync
    local pact = ally and ally:Get()
    local out = {}
    if not pact or not sync then
        return out
    end
    local mine = ally:MyGuildName()
    for guildName in pairs(pact.guilds) do
        if guildName ~= mine and not ally:IsBlocked(guildName) then
            local entry = sync:Remote(guildName, "lfg")
            if entry and type(entry.data) == "table" then
                for _, row in ipairs(entry.data) do
                    local e = { role = row.r, note = row.t, ts = row.ts, ttl = row.ttl }
                    if self:_IsActive(e, now) then
                        out[#out + 1] = {
                            key   = nil,
                            name  = row.n,
                            role  = row.r or "ANY",
                            note  = "|cff8888aa[" .. guildName .. "]|r " .. (row.t or ""),
                            ts    = row.ts,
                            ttl   = row.ttl,
                            guild = guildName,
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

function LFGBoard:Prune(now, store)
    store = store or GuildOS.db.lfgBoard
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for k, e in pairs(store) do
        if not self:_IsActive(e, now) then store[k] = nil; removed = removed + 1 end
    end
    return removed
end

-- Whitelist an incoming role against the known set. Anything that is not a
-- string, or not one of LFGBoard.ROLES (a forged length, a color/texture
-- escape sequence, a number/boolean/table that survived LibSerialize), falls
-- back to "ANY". Shared by HandleEntry and the self test so the rule cannot
-- drift between production and the test that pins it.
function LFGBoard:_SanitizeRole(role)
    return (type(role) == "string" and tContains(self.ROLES, role) and role) or "ANY"
end

-- The roles of a listing: the letters of ROLE_LETTERS it names, each once and in that order, so two
-- clients write the same set the same way. Anything else (a number, a table, a colour escape) is no
-- role at all, which reads as "any".
function LFGBoard:_SanitizeRoles(roles)
    if type(roles) ~= "string" then return "" end
    local out = ""
    for _, letter in ipairs(self.ROLE_LETTERS) do
        if roles:find(letter, 1, true) then out = out .. letter end
    end
    return out
end

-- One activity id off the wire, or nil: lowercase letters, digits and hyphens, as the catalogue
-- writes them. An id this client's catalogue does not have is kept (a newer version's), and shown
-- as some other activity.
function LFGBoard:_SanitizeAct(id)
    if type(id) ~= "string" or #id == 0 or #id > ACT_ID_MAX or id:find("[^%l%d%-]") then return nil end
    return id
end

-- The activities of a listing: up to ACTS_MAX ids, each once, in the order they came.
function LFGBoard:_SanitizeActs(acts)
    local out, seen = {}, {}
    if type(acts) ~= "table" then return out end
    for i = 1, ACTS_MAX * 2 do
        local id = self:_SanitizeAct(acts[i])
        if id and not seen[id] and #out < ACTS_MAX then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

-- The one role a client before #341 shows for these roles: the only one, or any.
function LFGBoard:_LegacyRole(roles)
    return ROLE_OF[roles or ""] or "ANY"
end

-- Clamp a lifetime to the range the UI actually offers (30m to 120m). An
-- unclamped ttl is a permanent entry: ttl = 1e12 keeps _IsActive true forever,
-- so Prune can never drop it and it survives in SavedVariables long after the
-- sender left the guild. Applied on BOTH the local post path and the receive
-- path so the two can never disagree. Anything unparseable (nil, a table, a
-- string, NaN) falls back to the default.
function LFGBoard:_ClampTtl(ttl)
    local n = tonumber(ttl)
    if not n or n ~= n then return DEFAULT_TTL end   -- nil / not a number / NaN
    if n < TTL_MIN then return TTL_MIN end
    if n > TTL_MAX then return TTL_MAX end
    return math.floor(n)
end

-- Turns a received payload into the entry we store, plus the age it claimed.
-- Pure (injectable `now`) so the self test can pin it without comm state.
--
-- `age` is how many seconds ago the sender originally posted. A fresh post
-- omits it (age 0, ts = now, exactly the old behavior); a Rebroadcast sends
-- the real elapsed time so the entry keeps its ORIGINAL deadline instead of
-- restarting the clock on every relog. Age is clamped to [0, ttl]: it can
-- only ever move ts backwards, never into the future, so the entry always
-- expires at or before now + clamped ttl and cannot be stretched.
function LFGBoard:_BuildEntry(p, now)
    now = now or 0
    local ttl = self:_ClampTtl(p and p.ttl)
    local age = tonumber(p and p.age) or 0
    if age ~= age or age < 0 then age = 0 end
    if age > ttl then age = ttl end
    -- A listing from before #341 has only `role`: its roles are that one.
    local role = self:_SanitizeRole(p and p.role)
    local roles = self:_SanitizeRoles(p and p.roles)
    if roles == "" then roles = LETTER_OF[role] or "" end
    return {
        role = role,
        roles = roles,
        acts = self:_SanitizeActs(p and p.acts),
        note = GuildOS:SanitizeUserText(p and p.note, NOTE_MAX),
        ts = now - age,
        ttl = ttl,
    }, age
end

-- Per-sender cooldown for incoming entries. Every accepted entry repaints the
-- board, and a repaint allocates a fresh Button per row (WoW never frees
-- frames), so an unthrottled peer looping LFG messages leaks frames in every
-- viewer's session. Returns true when the message must be dropped silently.
-- Same self-clearing _cd table pattern as Modules/NoteCommand.lua, so the
-- table can never grow past the senders currently on cooldown.
-- store/schedule are injectable for the self test; production passes neither.
function LFGBoard:_RateLimited(sender, store, schedule)
    if not sender then return true end
    store = store or self._cd
    if not store then
        self._cd = {}
        store = self._cd
    end
    if store[sender] then return true end
    store[sender] = true
    local after = schedule or GuildOS.Compat.After
    after(ENTRY_COOLDOWN, function() store[sender] = nil end)
    return false
end

-- Default role for a fresh Role cycle button. The player's own last pick
-- wins whenever it is anything other than the untouched default "ANY". If
-- it is still "ANY", fall back to their self-service raid role profile
-- (GuildOS:GetMyRoles(), a { [ROLE] = true } set, see Core/Core.lua) but
-- ONLY when exactly one role is configured there -- with two or more (or
-- zero) we cannot guess which one they mean for this LFG post, so it stays
-- "ANY". Always sanitized on the way out, so this can never return a value
-- outside LFGBoard.ROLES.
-- rolesOverride / lastRoleOverride are injectable so the self test can pin
-- every branch without touching live db/profile state; production calls
-- this with no arguments.
function LFGBoard:_DefaultRole(rolesOverride, lastRoleOverride)
    local lastRole = lastRoleOverride or (GuildOS.db.lfgPrefs and GuildOS.db.lfgPrefs.lastRole) or "ANY"
    if lastRole ~= "ANY" then return self:_SanitizeRole(lastRole) end

    local roles = rolesOverride
    if roles == nil and GuildOS.GetMyRoles then roles = GuildOS:GetMyRoles() end
    roles = roles or {}

    local only
    for role, on in pairs(roles) do
        if on then
            if only then return "ANY" end -- more than one role configured, don't guess
            only = role
        end
    end
    return self:_SanitizeRole(only)
end

----------------------------------------------------------------------
-- Self declare (publishes only your OWN entry)
----------------------------------------------------------------------
local function myKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
end

-- Returns the stored entry so callers print exactly what was published
-- (sanitized note, clamped ttl) instead of what they passed in. `toGuild` is the board's box: the
-- slash command never speaks in guild chat, where nobody who typed it agreed to be heard.
-- `roles` and `acts` are the Groups tab's (issue #341): given roles decide `role`, the one a client
-- before #341 reads.
function LFGBoard:SetAvailable(role, note, ttl, toGuild, roles, acts)
    note = GuildOS:SanitizeUserText(note, NOTE_MAX)
    ttl = self:_ClampTtl(ttl or GuildOS.db.lfgPrefs.lastTtl or DEFAULT_TTL)
    if roles ~= nil then
        roles = self:_SanitizeRoles(roles)
        role = self:_LegacyRole(roles)
    else
        role = self:_SanitizeRole(role or GuildOS.db.lfgPrefs.lastRole or "ANY")
        roles = LETTER_OF[role] or ""
    end
    acts = self:_SanitizeActs(acts)
    local entry = { role = role, roles = roles, acts = acts, note = note, ts = GetServerTime(), ttl = ttl }
    GuildOS.db.lfgBoard[myKey()] = entry
    local prefs = GuildOS.db.lfgPrefs
    prefs.lastRole, prefs.lastNote, prefs.lastTtl, prefs.roles = role, note, ttl, roles
    if toGuild then self:_SayInGuild(role, note, acts) end
    if GuildOS.CommSystem then
        GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ role = role, roles = roles, acts = acts, note = note, ttl = ttl }))
    end
    self:Refresh()
    return entry
end

-- My own live listing, or nil.
function LFGBoard:Mine()
    local store = GuildOS.db and GuildOS.db.lfgBoard
    local entry = store and store[myKey()]
    return self:_IsActive(entry, GetServerTime()) and entry or nil
end

function LFGBoard:MyKey() return myKey() end

function LFGBoard:ClearAvailable()
    GuildOS.db.lfgBoard[myKey()] = nil
    if GuildOS.CommSystem then
        GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ clear = true }))
    end
    self:Refresh()
end

function LFGBoard:AmAvailable()
    local store = GuildOS.db and GuildOS.db.lfgBoard
    return self:_IsActive(store and store[myKey()], GetServerTime())
end

-- Re-publish our own live entry. Availability was only ever sent once, so a
-- guildmate who logged in after the post saw an empty board until we posted
-- again. CommSystem:HandleRequest calls this, which is the pull every other
-- synced domain already answers on. The original deadline is carried across
-- as `age` (seconds since the post) rather than as a timestamp, so answering
-- requests or relogging can never extend the listing.
function LFGBoard:Rebroadcast()
    if not GuildOS.CommSystem then return false end
    local store = GuildOS.db and GuildOS.db.lfgBoard
    local entry = store and store[myKey()]
    local now = GetServerTime()
    if not self:_IsActive(entry, now) then return false end
    local age = now - entry.ts
    if age < 0 then age = 0 end
    GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.LFG,
        LibSerialize:Serialize({ role = entry.role, roles = entry.roles, acts = entry.acts, note = entry.note,
            ttl = entry.ttl, age = age }))
    return true
end

-- Incoming: the key ALWAYS comes from the envelope sender, never the payload.
function LFGBoard:HandleEntry(sender, data)
    if not sender then return end
    -- Cooldown first, before the deserialize and before any repaint, so a
    -- flooding peer costs us nothing. Keyed on the short name so "Bob" and
    -- "Bob-Realm" share one bucket.
    if self:_RateLimited(sender:match("^([^-]+)") or sender) then return end
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local short = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = GuildOS:GetPlayerKey(short, realm)
    GuildOS.db.lfgBoard = GuildOS.db.lfgBoard or {}
    if p.clear then
        GuildOS.db.lfgBoard[key] = nil
    else
        local now = GetServerTime()
        local wasActive = self:_IsActive(GuildOS.db.lfgBoard[key], now)
        local entry, age = self:_BuildEntry(p, now)
        GuildOS.db.lfgBoard[key] = entry
        -- Print the SANITIZED note, never the raw payload: string.format("%s")
        -- does not call tostring in Lua 5.1, so a peer sending a boolean or a
        -- table would raise inside this (unprotected) CHAT_MSG_ADDON handler,
        -- and an oversized note would bypass the cap and flood the chat frame.
        -- age > 0 means this is a rebroadcast of an older post, not news.
        local prefs = GuildOS.db.lfgPrefs
        if age == 0 and not wasActive and prefs and prefs.notify and key ~= myKey() then
            local what = self:Describe(entry)
            GuildOS:Print(string.format(L["%s is available: %s"], short, what ~= "" and what or L["(no note)"]))
        end
    end
    self:Refresh()
end

function LFGBoard:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- What the Groups tab and the chat lines read
----------------------------------------------------------------------
local function roleDisplay(role)
    if role == "TANK" then return L["Tank"] end
    if role == "HEALER" then return L["Healer"] end
    if role == "DPS" then return L["DPS"] end
    return L["Any"]
end
function LFGBoard:RoleName(role) return roleDisplay(role) end

-- An activity's name: the game's own for an instance this client knows, the catalogue's otherwise,
-- and "another activity" for an id only a newer version has.
function LFGBoard:ActivityName(id)
    local cat = GuildOS.GroupActivities
    local it = cat and cat.byId[id]
    if not it then return L["Another activity"] end
    local own = it.map and GuildOS.Compat.InstanceName(it.map)
    return own or it.name
end

-- The activities of a listing and its note, as one line: "Deadmines, Gnomeregan: until 23h".
function LFGBoard:Describe(entry)
    local names = {}
    for _, id in ipairs(entry.acts or {}) do names[#names + 1] = self:ActivityName(id) end
    local what, note = table.concat(names, ", "), entry.note or ""
    if what ~= "" and note ~= "" then return what .. ": " .. note end
    return what ~= "" and what or note
end

-- The post in guild chat, which is what reaches somebody with the board closed, or with no addon
-- at all (#243). At most one every five minutes, saved so a /reload does not skip it, because taking
-- a post down and putting it back is one click each. The addon's notice goes out regardless, even if
-- it says the same thing: a line can be dropped with no error (a rank that may not speak), and not
-- everybody shows guild chat, so nothing here can know the line reached anyone. `line` is the whole
-- line when Modules/Groups.lua speaks for a group: one cooldown for both, so a leader cannot say two.
function LFGBoard:_SayInGuild(role, note, acts, line)
    local prefs, now = GuildOS.db.lfgPrefs, GetServerTime()
    if not IsInGuild() or now - (prefs.lastGuildLine or 0) < GUILD_LINE_COOLDOWN then return end
    if not line then
        line = role == "ANY" and L["[Guild OS] LFG"] or string.format(L["[Guild OS] LFG as %s"], roleDisplay(role))
        local what = self:Describe({ acts = acts, note = note })
        if what ~= "" then line = line .. ": " .. what end
    end
    if GuildOS.Compat.SendChatMessage(line, "GUILD") then prefs.lastGuildLine = now end
end

local function durationDisplay(seconds)
    return string.format(L["%dm"], math.floor((seconds or 0) / 60))
end
function LFGBoard:DurationName(seconds) return durationDisplay(seconds) end

-- Online guild roster snapshot for the board's online-only filter: an
-- { [key] = true } set plus a { [key] = classFile } lookup for row colors.
-- Keys are normalized exactly like HandleEntry (short name + realm through
-- GuildOS:GetPlayerKey) -- the recurring key-form gotcha in this codebase.
function LFGBoard:_BuildOnlineRoster()
    local onlineSet, classByKey = {}, {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and isOnline then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = GuildOS:GetPlayerKey(short, realm)
            onlineSet[key] = true
            classByKey[key] = classFile
        end
    end
    return onlineSet, classByKey
end

-- The few choices the Groups tab keeps between sessions. The panel asks and tells through these two:
-- it never writes the saved table itself.
local PREFS = { postToGuild = "boolean", allianceScope = "boolean", roles = "string", lastMode = "string" }
function LFGBoard:Pref(key)
    local prefs = GuildOS.db and GuildOS.db.lfgPrefs
    return prefs and PREFS[key] and prefs[key]
end
function LFGBoard:SetPref(key, value)
    local prefs = GuildOS.db and GuildOS.db.lfgPrefs
    if not prefs or type(value) ~= PREFS[key] then return false end
    if key == "roles" then value = self:_SanitizeRoles(value) end
    prefs[key] = value
    return true
end

-- The board is the Groups tab's Active view since issue #341. With the tab switched off in Settings
-- the opener says so itself.
function LFGBoard:Show()
    return GuildOS.UI:OpenWindow("groups", "active")
end

----------------------------------------------------------------------
-- Chat command: /gos avail [off | notify [on|off] | [role] <text>]
----------------------------------------------------------------------

-- Role tokens accepted as an optional LEADING word of "/gos avail ...".
-- Lowercased on the way in, mapped to the canonical LFGBoard.ROLES spelling.
local ROLE_TOKENS = { tank = "TANK", healer = "HEALER", dps = "DPS", any = "ANY" }

-- Pure: turns the /gos avail argument list into an action plus its data.
-- Reads no db, sends no comm, touches no frame, so the self test can pin
-- every branch. Inputs:
--   args         token array built from rest
--   rest         raw remainder, internal spacing intact
--   defaultRole  role to use when no leading role token is given. The caller
--                passes self:_DefaultRole(); nil sanitizes to "ANY".
-- Returns action, role, note, value:
--   "show"                      -> open the board
--   "clear"                     -> stop being available
--   "notify", nil, nil, value   -> value true/false sets it, nil = report only
--   "set", role, note           -> post availability (note already capped)
function LFGBoard:_ParseAvailArgs(args, rest, defaultRole)
    args = args or {}
    rest = strtrim(rest or "")
    local first = args[1] and args[1]:lower()
    if not first or first == "" then return "show" end
    -- Delisting only when the token stands alone, otherwise "/gos avail stop
    -- by if you need a healer" would delist instead of post. notify keeps
    -- taking its on/off value.
    if (first == "off" or first == "stop") and #args == 1 then return "clear" end
    if first == "notify" then
        local v = args[2] and args[2]:lower()
        if v == "on" then return "notify", nil, nil, true end
        if v == "off" then return "notify", nil, nil, false end
        return "notify"
    end
    -- Only a leading token counts as a role, so "need 2 dps" stays all note.
    local role, note = ROLE_TOKENS[first], rest
    if role then note = strtrim(rest:match("^%S+%s*(.*)$") or "") end
    return "set", self:_SanitizeRole(role or defaultRole), GuildOS:SanitizeUserText(note, NOTE_MAX)
end

function LFGBoard:HandleCommand(args, rest)
    local prefs = GuildOS.db and GuildOS.db.lfgPrefs
    if not prefs then return end
    local action, role, note, value = self:_ParseAvailArgs(args, rest, self:_DefaultRole())
    if action == "clear" then
        self:ClearAvailable()
        GuildOS:Print(L["You are no longer listed as available."])
    elseif action == "notify" then
        if value ~= nil then prefs.notify = value end
        GuildOS:Print(prefs.notify and L["LFG notify |cff4CFF4Con|r."] or L["LFG notify |cffFF4444off|r."])
    elseif action == "set" then
        -- Print the stored entry, so the confirmation shows the sanitized note
        -- and the clamped duration that guildmates will actually see.
        local entry = self:SetAvailable(role, note, prefs.lastTtl or DEFAULT_TTL)
        GuildOS:Print(string.format(L["You are available as %s for %s: %s"],
            roleDisplay(entry.role), durationDisplay(entry.ttl),
            (entry.note ~= "" and entry.note) or L["(no note)"]))
    else
        self:Show()
    end
end

----------------------------------------------------------------------
-- Self tests
----------------------------------------------------------------------
function LFGBoard:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    S:Register("lfg.active", function()
        if not LFGBoard:_IsActive({ ts = 100, ttl = 60 }, 130) then return false, "should be active" end
        if LFGBoard:_IsActive({ ts = 100, ttl = 60 }, 200) then return false, "should be expired" end
        return true
    end)
    S:Register("lfg.remaining", function()
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 300) ~= 5 then return false, "5 min left" end
        -- Rounds up: a part minute is still time on the board.
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 305) ~= 5 then return false, "part minute rounds up" end
        -- The old floor made the last 59 seconds of every listing render "0m".
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 541) ~= 1 then return false, "sub minute => 1m" end
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 599) ~= 1 then return false, "last second => 1m" end
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 999) ~= 0 then return false, "expired => 0" end
        return true
    end)
    S:Register("lfg.ttl_clamp", function()
        if LFGBoard:_ClampTtl(3600) ~= 3600 then return false, "in range kept" end
        if LFGBoard:_ClampTtl(TTL_MIN) ~= TTL_MIN then return false, "lower bound kept" end
        if LFGBoard:_ClampTtl(TTL_MAX) ~= TTL_MAX then return false, "upper bound kept" end
        if LFGBoard:_ClampTtl(1e12) ~= TTL_MAX then return false, "forged huge ttl clamped" end
        if LFGBoard:_ClampTtl(0) ~= TTL_MIN then return false, "zero clamped up" end
        if LFGBoard:_ClampTtl(-1) ~= TTL_MIN then return false, "negative clamped up" end
        if LFGBoard:_ClampTtl("nope") ~= DEFAULT_TTL then return false, "garbage defaults" end
        if LFGBoard:_ClampTtl(nil) ~= DEFAULT_TTL then return false, "nil defaults" end
        if LFGBoard:_ClampTtl({}) ~= DEFAULT_TTL then return false, "table defaults" end
        -- The clamp is what keeps Prune able to do its job: without it a forged
        -- ttl pins the entry on the board (and in SavedVariables) forever.
        local e = LFGBoard:_BuildEntry({ ttl = 1e12 }, 100)
        if LFGBoard:_IsActive(e, 100 + TTL_MAX) then return false, "entry must still expire" end
        return true
    end)
    S:Register("lfg.entry_age", function()
        local fresh, freshAge = LFGBoard:_BuildEntry({ role = "TANK", note = "heroic", ttl = 3600 }, 1000)
        if fresh.ts ~= 1000 or fresh.ttl ~= 3600 or freshAge ~= 0 then return false, "fresh post starts now" end
        -- A rebroadcast keeps its original deadline instead of restarting it.
        local old, age = LFGBoard:_BuildEntry({ ttl = 3600, age = 600 }, 1000)
        if old.ts ~= 400 or age ~= 600 then return false, "rebroadcast keeps its deadline" end
        -- Age only ever moves ts backwards, so relogging cannot stretch a listing.
        local far = LFGBoard:_BuildEntry({ ttl = 3600, age = 99999 }, 1000)
        if far.ts ~= (1000 - 3600) then return false, "age capped at ttl" end
        if LFGBoard:_IsActive(far, 1000) then return false, "over aged entry is dead on arrival" end
        local future = LFGBoard:_BuildEntry({ ttl = 3600, age = -5000 }, 1000)
        if future.ts ~= 1000 then return false, "negative age cannot post date an entry" end
        -- Payload text is sanitized, so a texture escape never reaches a row.
        local evil = LFGBoard:_BuildEntry({ note = "|TInterface\\Icons\\X:64|t", role = 7 }, 0)
        if evil.note:find("|", 1, true) then return false, "note escape survived" end
        if evil.role ~= "ANY" then return false, "forged role rejected" end
        return true
    end)
    S:Register("lfg.rate_limit", function()
        local cd, pending = {}, {}
        local function fakeAfter(_, fn) pending[#pending + 1] = fn end
        if LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "first entry accepted" end
        if not LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "flood dropped" end
        if not LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "still dropped" end
        if LFGBoard:_RateLimited("Bob", cd, fakeAfter) then return false, "other senders unaffected" end
        if #pending ~= 2 then return false, "one self clear per accepted entry" end
        for _, fn in ipairs(pending) do fn() end
        if next(cd) ~= nil then return false, "cooldown table must self clear" end
        if LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "accepted again after cooldown" end
        return true
    end)
    S:Register("lfg.activelist_sorted_and_filtered", function()
        local store = {
            ["A-R"] = { ts = 100, ttl = 600, note = "a" },
            ["B-R"] = { ts = 200, ttl = 600, note = "b" },
            ["C-R"] = { ts = 1,   ttl = 5,   note = "expired" },
        }
        local out = LFGBoard:ActiveList(store, 300)
        if #out ~= 2 or out[1].key ~= "B-R" then return false, "newest first, expired dropped" end
        local only = LFGBoard:ActiveList(store, 300, { ["A-R"] = true })
        if #only ~= 1 or only[1].key ~= "A-R" then return false, "online filter" end
        return true
    end)
    S:Register("lfg.activelist_tiebreak", function()
        -- Two members posting in the same second must not swap rows between
        -- repaints, or an Invite click can land on a row that just moved.
        local store = {
            ["Cara-R"] = { ts = 100, ttl = 600 },
            ["Ann-R"]  = { ts = 100, ttl = 600 },
            ["Bob-R"]  = { ts = 200, ttl = 600 },
        }
        local out = LFGBoard:ActiveList(store, 300)
        if #out ~= 3 then return false, "all three active" end
        if out[1].key ~= "Bob-R" then return false, "newest first" end
        if out[2].key ~= "Ann-R" or out[3].key ~= "Cara-R" then return false, "equal ts sorts by key" end
        return true
    end)
    S:Register("lfg.prune", function()
        local store = { ["X-R"] = { ts = 1, ttl = 5 }, ["Y-R"] = { ts = 100, ttl = 600 } }
        local n = LFGBoard:Prune(300, store)
        if n ~= 1 or store["X-R"] ~= nil or store["Y-R"] == nil then return false, "prune" end
        return true
    end)
    S:Register("lfg.role_whitelist", function()
        if LFGBoard:_SanitizeRole("TANK") ~= "TANK" then return false, "valid role kept" end
        if LFGBoard:_SanitizeRole("|cffff0000EVIL|r") ~= "ANY" then return false, "escape string rejected" end
        if LFGBoard:_SanitizeRole(42) ~= "ANY" then return false, "non string rejected" end
        if LFGBoard:_SanitizeRole(nil) ~= "ANY" then return false, "nil defaults" end
        return true
    end)
    S:Register("lfg.default_role", function()
        if LFGBoard:_DefaultRole({ HEALER = true }, "ANY") ~= "HEALER" then return false, "single role maps" end
        if LFGBoard:_DefaultRole({ TANK = true, DPS = true }, "ANY") ~= "ANY" then return false, "multiple roles -> ANY" end
        if LFGBoard:_DefaultRole({}, "ANY") ~= "ANY" then return false, "no roles -> ANY" end
        if LFGBoard:_DefaultRole({ TANK = true }, "HEALER") ~= "HEALER" then return false, "lastRole wins over roles" end
        return true
    end)
    S:Register("lfg.avail_parse_show_clear", function()
        if LFGBoard:_ParseAvailArgs({}, "") ~= "show" then return false, "bare -> show" end
        if LFGBoard:_ParseAvailArgs(nil, nil) ~= "show" then return false, "nil args -> show" end
        if LFGBoard:_ParseAvailArgs({ "off" }, "off") ~= "clear" then return false, "off -> clear" end
        if LFGBoard:_ParseAvailArgs({ "stop" }, "stop") ~= "clear" then return false, "stop -> clear" end
        -- Only the bare token delists. "/gos avail stop by if you need a
        -- healer" is a post, not a delist.
        local action, role, note = LFGBoard:_ParseAvailArgs(
            { "stop", "by", "if", "you", "need", "a", "healer" }, "stop by if you need a healer", "DPS")
        if action ~= "set" then return false, "stop plus text must post" end
        if role ~= "DPS" or note ~= "stop by if you need a healer" then return false, "whole line is the note" end
        if LFGBoard:_ParseAvailArgs({ "off", "for", "now" }, "off for now", "ANY") ~= "set" then
            return false, "off plus text must post"
        end
        return true
    end)
    S:Register("lfg.avail_parse_notify", function()
        local action, _, _, value = LFGBoard:_ParseAvailArgs({ "notify" }, "notify")
        if action ~= "notify" or value ~= nil then return false, "bare notify reports only" end
        action, _, _, value = LFGBoard:_ParseAvailArgs({ "notify", "on" }, "notify on")
        if action ~= "notify" or value ~= true then return false, "notify on -> true" end
        action, _, _, value = LFGBoard:_ParseAvailArgs({ "notify", "off" }, "notify off")
        if action ~= "notify" or value ~= false then return false, "notify off -> false" end
        return true
    end)
    S:Register("lfg.avail_parse_role_token", function()
        local action, role, note = LFGBoard:_ParseAvailArgs({ "tank", "heroic", "SP" }, "tank heroic SP", "DPS")
        if action ~= "set" or role ~= "TANK" or note ~= "heroic SP" then return false, "leading role consumed" end
        action, role, note = LFGBoard:_ParseAvailArgs({ "need", "2", "dps" }, "need 2 dps", "HEALER")
        if action ~= "set" or role ~= "HEALER" or note ~= "need 2 dps" then return false, "trailing dps is note" end
        action, role, note = LFGBoard:_ParseAvailArgs({ "tankk", "lol" }, "tankk lol", "ANY")
        if action ~= "set" or role ~= "ANY" or note ~= "tankk lol" then return false, "tankk is not a role" end
        return true
    end)
    S:Register("lfg.avail_parse_note_cap", function()
        local long = string.rep("x", NOTE_MAX + 30)
        local action, _, note = LFGBoard:_ParseAvailArgs({ long }, long, "ANY")
        if action ~= "set" or #note ~= NOTE_MAX then return false, "note capped at NOTE_MAX" end
        return true
    end)
end
