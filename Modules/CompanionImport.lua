----------------------------------------------------------------------
-- Guild OS - Companion Import (GOSROST1)
--
-- The other direction. CompanionExport sends what the game knows to the
-- website; this brings a finished roster back, so a raid leader stops
-- retyping twenty-five names into invite macros at 21:58.
--
--   "GOSROST1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json))
--
-- Same transport as GOSCOMP1, for the same reason: the string has to
-- survive being copied out of a browser and pasted into an edit box.
--
-- Everything here goes through Companion:IsEnabled(). The gate lives in
-- the export module so a new entry point cannot forget to ask.
----------------------------------------------------------------------
local Import = {}
GuildOS.CompanionImport = Import

--- The name to invite, and to match a raid slot or a guild roster row by.
--- On TBC Anniversary a name that arrives with its realm ("Chehul-Mankrik") is cut back
--- to the plain name the invite API wants for a same-realm player. WoW: Forever has no
--- realms and writes the surname with a hyphen ("Chehul-Costa"): cutting at the first
--- hyphen would invite somebody else. What comes off there is exactly the client's own
--- realm, if it reports one ("Chehul-Costa-70") — as it writes it, or without spaces the
--- way a roster row does — compared as plain text, never as a pattern. The site does the
--- same with the keys it receives (the site's specs/036). Retail takes the same path: a
--- "Name-Realm" on this character's realm comes back plain, one on another connected realm
--- keeps its realm, which is what an invite there needs (issue #182).
function Import.PlainName(name)
    if GuildOS.Client.isAnniversary then return name:match("^([^-]+)") or name end
    local realm = GuildOS:GetClientRealm()
    if realm and realm ~= "" then
        local compact = (realm:gsub("%s", ""))
        for _, suffix in ipairs({ "-" .. realm, "-" .. compact }) do
            if #name > #suffix and name:sub(-#suffix) == suffix then
                return name:sub(1, #name - #suffix)
            end
        end
    end
    return name
end

local L = GuildOS.L
local WIRE_PREFIX = "GOSROST1:"
local CORES_PREFIX = "GOSCORE1:"
local GUILD_PREFIX = "GOSGILD1:"
local RECRUIT_PREFIX = "GOSRECR1:"
local VEIL_PREFIX = "GOSVEIL1:"
local ALLY_PREFIX = "GOSALLY1:"
local RECRUIT_MAX_AGE = 3 * 86400   -- the list is public and asked for every 15 minutes: three days of silence is a companion that stopped
local BLOCK_MAX_AGE = 7 * 86400   -- the feed is a week long: an older block is a companion that stopped

-- The name somebody from the site is kept, shown and matched by. On retail it is their key,
-- "Name-Realm" with their own realm: the name alone would invite a namesake on this character's
-- realm, and a name cut against the importer's realm would differ between officers on two
-- connected realms, so the calendar's list would never match across them. It is cut only to
-- invite (inviteName). Elsewhere the plain name, as it always was (issue #182).
local function nameOf(entry)
    if GuildOS.Client.isRetail and type(entry.key) == "string" and entry.key ~= "" then return entry.key end
    return Import.PlainName(entry.name)
end

-- The name the invite API gets: on retail the kept name cut to the plain one on this
-- character's realm; elsewhere it is plain already.
local function inviteName(name)
    return GuildOS.Client.isRetail and Import.PlainName(name) or name
end

----------------------------------------------------------------------
-- Reading the string
----------------------------------------------------------------------

-- The table inside a wire string's body (what follows its prefix), when it is the `fmt` asked
-- for; nil when it is damaged or another kind.
-- `maxJson`, when given, is how many bytes the inflated text may take: the inflating itself stops there
-- (LibDeflate:DecompressDeflateLimited), so a small string made to inflate a thousandfold costs no more than the cap.
local function unwrap(body, fmt, maxJson)
    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:DecodeForPrint(body)
    local json
    if compressed and maxJson and LibDeflate.DecompressDeflateLimited then
        json = LibDeflate:DecompressDeflateLimited(compressed, maxJson)
    elseif compressed then
        json = LibDeflate:DecompressDeflate(compressed)
    end
    if not json or (maxJson and #json > maxJson) then return nil end
    local ok, data = pcall(GuildOS.JsonDecode, json)
    if ok and type(data) == "table" and data.fmt == fmt then return data end
    return nil
end

-- The plan as the site sends it (GOSROST1 v4, the site's specs/009): every field checked and cut
-- again here, since the inbox is untrusted input whatever wrote it. nil when the block says nothing
-- of it, which is every block from a site before v4 (issue #296).
local PLAN_MAX = { tasks = 150, taskNote = 120, note = 500, notes = 40, rules = 500 }
local function clipped(v, max)
    if type(v) ~= "string" or v == "" then return nil end
    return #v > max and v:sub(1, max) or v
end
function Import.ReadPlan(data)
    local plan, any = { assignments = {}, notes = {} }, false
    for _, a in ipairs(type(data.assignments) == "table" and data.assignments or {}) do
        if #plan.assignments >= PLAN_MAX.tasks then break end
        local boss, name = type(a) == "table" and clipped(a.boss, 100), type(a) == "table" and clipped(a.name, 64)
        if boss and name then
            plan.assignments[#plan.assignments + 1] = {
                boss = boss, key = clipped(a.key, 100), name = name,
                kind = clipped(a.kind, 20) or "other", target = clipped(a.target, 40), note = clipped(a.note, PLAN_MAX.taskNote) or "",
            }
            any = true
        end
    end
    for _, n in ipairs(type(data.notes) == "table" and data.notes or {}) do
        if #plan.notes >= PLAN_MAX.notes then break end
        local boss, body = type(n) == "table" and clipped(n.boss, 100), type(n) == "table" and clipped(n.text, PLAN_MAX.note)
        if boss and body then
            plan.notes[#plan.notes + 1] = { boss = boss, text = body }
            any = true
        end
    end
    if type(data.loot) == "table" and (clipped(data.loot.system, 20) or clipped(data.loot.rules, PLAN_MAX.rules)) then
        plan.loot = { system = clipped(data.loot.system, 20), rules = clipped(data.loot.rules, PLAN_MAX.rules), version = tonumber(data.loot.version) or 1 }
        any = true
    end
    return any and plan or nil
end

-- The loot rule the raid plays by, as the site sends it (GOSROST1 v5, guildos-web#516). The inbox is
-- untrusted input: what is kept is a copy held to a size no rule of the contract reaches (its depth,
-- its number of fields, the length of a text), and whether it is a rule this client reads is
-- LootRule's to say. nil when the block carries none; false when it carries something that is no rule
-- at all, so the plan window can say the raid's rule was not read.
local RULE_MAX = { depth = 8, nodes = 1500, text = 200 }
local function boundedCopy(v, depth, budget)
    local t = type(v)
    if t == "string" then
        if #v > RULE_MAX.text then error("text") end
        return v
    elseif t == "number" or t == "boolean" then
        return v
    elseif t ~= "table" then
        error("type")
    end
    if depth > RULE_MAX.depth then error("depth") end
    local out = {}
    for k, x in pairs(v) do
        budget.n = budget.n + 1
        if budget.n > RULE_MAX.nodes then error("size") end
        if type(k) ~= "string" and type(k) ~= "number" then error("key") end
        if type(k) == "string" and #k > 32 then error("key") end
        out[k] = boundedCopy(x, depth + 1, budget)
    end
    return out
end
-- L5: the loot systems the site may name for a raid night (GOSROST1 `lootSystem`).
Import.NIGHT_SYSTEMS = { rolls = true, wishlist = true, dkp = true, council = true }

function Import.ReadLootRule(rule)
    if rule == nil then return nil end
    if type(rule) ~= "table" then return false end
    local ok, copy = pcall(boundedCopy, rule, 1, { n = 0 })
    return ok and copy or false
end

-- The raid's soft reserves, priorities and wishlists, as the site sends them (GOSROST1 v6, guildos-web
-- #556; this repo's #385). The inbox is untrusted input, so every field is bounded and cleaned here and
-- converted to the addon's own shapes, which lets a reader swap one of its tables for one of these:
--   softres     = { items = { [itemId] = { {name, class, note, plusOnes, hard?} } }, hidden = true|nil }
--   prios       = { [itemId] = { {name, class, order} } }   (names as the game's own: Name-Realm on retail)
--   priosHidden = true|nil, only beside prios: no raid-chat line may name a place of them (R21)
--   wishlists   = { [lowerKey] = { name, class, wishlist = { {itemId, order, isOffspec} } } }
-- A field that fails its bounds is refused whole and becomes nil; the roster and the other fields go on. A
-- person whose name does not read (empty, or over 64 bytes) is passed over alone.
-- Nothing here writes a table of the game's own (db.softRes, db.lootPrios, db.guildWishlists).
local SITE_LOOT = {
    softEntries = 1500, softItems = 20, hardEntries = 200,
    prioItems = 600, prioPeople = 40, prioRank = 100,
    wishItems = 60, wishPeople = 1000,
    id = 2147483647, name = 64, class = 20, note = 140,
}
local function siteInt(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then error("int") end
    return v
end
local function siteList(v, max)
    if type(v) ~= "table" or #v > max then error("list") end
    return v
end
-- The GOSGILD1's discordWarnings (the site's specs/116): warnings given on Discord, the site's to own.
-- Cleaned here as the game's own are (Discipline.Clean, with Discord's "d:" ids), the text made inert,
-- the key made this client's. Nil with no block; never stored.
function Import:DiscordWarnings()
    local block = self:GuildBlock()
    local raw = block and block.discordWarnings
    local D = GuildOS.Discipline
    if type(raw) ~= "table" or not D then return nil end
    local out = {}
    for i = 1, math.min(#raw, 200) do
        local r = raw[i]
        if type(r) == "table" and type(r.id) == "string" and r.id:find("^d:") then
            local w = D.Clean({ id = "x" .. r.id:sub(3), subject = r.subject, by = type(r.by) == "string" and Import.Inert(r.by) or nil,
                reason = r.reason, at = r.at, changedAt = r.revokedAt or r.at, level = r.level,
                note = type(r.note) == "string" and Import.Inert(r.note) or nil, revokedAt = r.revokedAt })
            if w then
                w.id, w.subject, w.discord = r.id, GuildOS:LocalMemberKey(w.subject), true
                out[#out + 1] = w
            end
        end
    end
    return out
end

-- Text off the network, for a line of ours: inert, no control character, trimmed, cut to `max` bytes
-- without splitting a UTF-8 character. nil when nothing is left.
local function siteText(v, max)
    if type(v) ~= "string" then return nil end
    local s = strtrim((Import.Inert(v):gsub("%c", " ")))
    if #s > max then
        local cut = max
        while cut > 0 do
            local b = s:byte(cut + 1)
            if not (b and b >= 0x80 and b <= 0xBF) then break end
            cut = cut - 1
        end
        s = s:sub(1, cut)
    end
    return s ~= "" and s or nil
end
-- A name is a bound, not a note: one too long, or empty, is not a person's, so that person is passed over
-- (nil) and the rest of the field still reads. The site cuts names to the same 64 bytes before it sends.
local function siteName(v)
    if type(v) ~= "string" or #v > SITE_LOOT.name then return nil end
    return siteText(v, SITE_LOOT.name)
end
-- A key the same way: never cut, since a cut key is somebody else's.
local function siteKey(v)
    if type(v) ~= "string" or #v > SITE_LOOT.name then return nil end
    return siteText(v, SITE_LOOT.name)
end
local function siteClass(v)
    return siteText(v, SITE_LOOT.class) or ""
end

local function readSoftres(sr)
    local items, any = {}, false
    for _, e in ipairs(siteList(sr.soft or {}, SITE_LOOT.softEntries)) do
        if type(e) ~= "table" then error("entry") end
        local name, class, note = siteName(e.name), siteClass(e.class), siteText(e.note, SITE_LOOT.note) or ""
        local ids = siteList(e.items or {}, SITE_LOOT.softItems)
        for _, id in ipairs(ids) do siteInt(id, 1, SITE_LOOT.id) end
        for _, id in ipairs(name and ids or {}) do
            items[id] = items[id] or {}
            table.insert(items[id], { name = name, class = class, note = note, plusOnes = 0 })
            any = true
        end
    end
    -- A fixed reserve is what SoftRes:LoadFromParsed makes of Gargul's hardreserves: named by `for`,
    -- no class, no +1, `hard`. One for nobody says nothing and is passed over, as it is there.
    for _, h in ipairs(siteList(sr.hard or {}, SITE_LOOT.hardEntries)) do
        if type(h) ~= "table" then error("entry") end
        local id = siteInt(h.id, 1, SITE_LOOT.id)
        local who = siteName(h["for"])
        if who then
            items[id] = items[id] or {}
            table.insert(items[id], { name = Import.PlainName(who), class = "", note = siteText(h.note, SITE_LOOT.note) or "",
                plusOnes = 0, hard = true })
            any = true
        end
    end
    return any and { items = items, hidden = sr.hidden == true or nil } or nil
end

local function readPrios(list)
    local prios, any = {}, false
    for _, p in ipairs(siteList(list, SITE_LOOT.prioItems)) do
        if type(p) ~= "table" then error("entry") end
        local id = siteInt(p.id, 1, SITE_LOOT.id)
        local order = {}
        for _, o in ipairs(siteList(p.order or {}, SITE_LOOT.prioPeople)) do
            if type(o) ~= "table" then error("entry") end
            local rank = siteInt(o.rank, 1, SITE_LOOT.prioRank)
            local name = siteName(o.name)
            -- Named as the game's own priorities and the panels name them: on retail by the whole Name-Realm.
            if name then
                order[#order + 1] = { name = nameOf({ key = siteKey(o.key), name = name }), class = siteClass(o.class), order = rank }
            end
        end
        if #order > 0 then
            prios[id] = order
            any = true
        end
    end
    return any and prios or nil
end

local function readWishlists(list)
    local out, any = {}, false
    for _, w in ipairs(siteList(list, SITE_LOOT.wishPeople)) do
        if type(w) ~= "table" then error("entry") end
        local entry = { key = siteKey(w.key), name = siteName(w.name) }
        local wishlist = {}
        for _, it in ipairs(siteList(w.items or {}, SITE_LOOT.wishItems)) do
            if type(it) ~= "table" then error("entry") end
            wishlist[#wishlist + 1] = { itemId = siteInt(it.id, 1, SITE_LOOT.id), order = siteInt(it.o, 1, SITE_LOOT.wishItems),
                isOffspec = it.x == true }
        end
        -- A person with no readable name is passed over; the others' lists still read.
        if #wishlist > 0 and entry.name then
            -- The key the game's own guild wishlists are kept by: the lowercased name, whole on retail.
            out[strlower(nameOf(entry))] = { name = nameOf(entry), class = siteClass(w.class), wishlist = wishlist }
            any = true
        end
    end
    return any and out or nil
end

-- { softres, prios, priosHidden, wishlists } of a decoded GOSROST1, or nil when none of them reads.
function Import.ReadSiteLoot(data)
    local loot, any = {}, false
    local fields = { softres = readSoftres, prios = readPrios, wishlists = readWishlists }
    for field, read in pairs(fields) do
        local raw = data[field]
        if type(raw) == "table" then
            local ok, got = pcall(read, raw)
            if ok and got then
                loot[field] = got
                any = true
            end
        end
    end
    if loot.prios and data.priosHidden == true then loot.priosHidden = true end
    return any and loot or nil
end

-- The places of a night of more than one (GOSROST1 v6 `instanceKeys`, the site's #556): catalogue keys,
-- at most eight, each a short string, the same one never twice. nil with none that reads.
local PLACES_MAX, PLACE_LEN = 8, 64
function Import.ReadPlaces(v)
    if type(v) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, k in ipairs(v) do
        if #out >= PLACES_MAX then break end
        if type(k) == "string" and k ~= "" and #k <= PLACE_LEN and not k:find("[%c|]") and not seen[k] then
            seen[k] = true
            out[#out + 1] = k
        end
    end
    return #out > 0 and out or nil
end

-- The window around a planned raid's start that counts as that raid's night (RaidFor, and how long a
-- raid's site loot is kept). Written on both sides on purpose; see the note at RaidFor.
local MATCH_EARLY = 2 * 3600
local MATCH_LATE = 8 * 3600

local ROSTER_MAX = 524288   -- characters of a GOSROST1 body: ten raids with full lists stay well under it
local GUILD_NAME_MAX = 96   -- bytes of a roster's guild name: the game's are 24 characters at most, four bytes each at worst

--- Returns (roster, err). roster = { title, instance, startsAt, members = {...} }
function Import:Parse(raw)
    if not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then
        return nil, L["The web companion is off. Turn it on with /gos web on."]
    end

    raw = strtrim(raw or "")
    if not raw:find(WIRE_PREFIX, 1, true) then
        return nil, L["That doesn't look like a roster from the website."]
    end
    -- People paste with a stray newline or a leading space; find the marker
    -- rather than insisting the string starts with it.
    raw = raw:sub(raw:find(WIRE_PREFIX, 1, true) + #WIRE_PREFIX)
    -- Over the cap is refused before the whitespace strip copies the body.
    if #raw > ROSTER_MAX then return nil, L["The roster string is damaged. Copy it again."] end

    if not (LibStub and LibStub("LibDeflate", true)) then return nil, L["LibDeflate not available."] end
    -- The same gate a GOSCORE1 body passes (ReadCores): the alphabet the companion lets into Inbox.lua
    -- and a length no roster reaches, before anything is decoded. A pasted code may carry breaks.
    raw = raw:gsub("%s+", "")
    if raw == "" or #raw > ROSTER_MAX or raw:find("[^A-Za-z0-9()]") then
        return nil, L["The roster string is damaged. Copy it again."]
    end
    local data = unwrap(raw, "GOSROST1")
    if not data then return nil, L["The roster string is damaged. Copy it again."] end

    local members = {}
    for _, m in ipairs(data.members or {}) do
        if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
            members[#members + 1] = {
                key = m.key or m.name,
                -- The invite API wants the plain name for a same-realm player.
                name = nameOf(m),
                class = m.class or "",
                spec = m.spec or "",
                slot = m.slot or "RANGED",
                group = tonumber(m.group) or 0,
            }
        end
    end
    -- v2 and up. Absent on an older site, which is not the same as nobody signing up:
    -- the panel shows what it was given and stays quiet about the rest.
    --
    -- `members` above is frozen at "who can be invited". This is everyone who answered,
    -- including the ones who said no, the ones on standby, and the ones whose character
    -- no export has ever confirmed. None of them are invitable and all of them are
    -- things a raid leader is trying to find out at 21:58.
    local signups
    if type(data.signups) == "table" then
        signups = {}
        for _, s in ipairs(data.signups) do
            if type(s) == "table" and type(s.name) == "string" and s.name ~= "" then
                signups[#signups + 1] = {
                    key = type(s.key) == "string" and s.key or nil,
                    name = nameOf(s),
                    class = s.class or "",
                    spec = s.spec or "",
                    slot = s.slot or "RANGED",
                    status = s.status or "yes",
                    wait = tonumber(s.wait),
                    group = tonumber(s.group) or 0,
                    invite = s.invite == true,
                    why = type(s.why) == "string" and s.why or nil,
                }
            end
        end
    end

    return {
        raidId = data.raidId,
        -- v4 (the site's #463): the night's plan, nil from an older site (issue #296).
        plan = Import.ReadPlan(data),
        -- v5 (the site's #516): the rule the raid plays by, nil when the site sent none.
        lootRule = Import.ReadLootRule(data.lootRule),
        -- The raid's loot is outside GuildOS (audit L5): no GuildOS loot that night. The site never sends it
        -- with a rule; were both there, this one wins (LootRule:Night), as no rule plays a night whose loot is elsewhere.
        lootExternal = data.lootExternal == true or nil,
        -- L5: a raid whose rule is only a loot system's (never with lootRule or lootExternal): one of these four.
        lootSystem = (data.lootRule == nil and data.lootExternal ~= true and Import.NIGHT_SYSTEMS[data.lootSystem])
            and data.lootSystem or nil,
        title = data.title or "",
        instance = data.instance,
        instanceKey = type(data.instanceKey) == "string" and data.instanceKey or nil,
        -- v6 (the site's #556): every place of a night of more than one, instanceKey first; nil otherwise.
        instanceKeys = Import.ReadPlaces(data.instanceKeys),
        size = tonumber(data.size) or 0,
        -- v3, retail: 14 Normal, 15 Heroic, 16 Mythic; nil elsewhere and from an older site (issue #182).
        difficulty = tonumber(data.difficulty),
        startsAt = tonumber(data.startsAt) or 0,
        -- The raid's time on the clock it was created on (guildos-web #411), checked where it is kept.
        clock = type(data.clock) == "table" and data.clock or nil,
        members = members,
        signups = signups,
        -- v7 (the site's #603): the in-game names of who owns the raid, nil from an older site.
        owners = Import.ReadOwners(data.owners),
        -- v7 (the site's #603): the guild the raid is for, as the game shows its name; nil from an older site.
        guild = clipped(data.guild, GUILD_NAME_MAX),
        -- v6 (the site's #556): the raid's reserves, priorities and wishlists, nil when none is sent or read.
        loot = Import.ReadSiteLoot(data),
    }
end

-- Who owns the raid (GOSROST1 v7, the site's #603; this repo's #400): a list of in-game names, written
-- the way a member's key is (Name-Realm, or the whole name with its surname on WoW: Forever). The inbox
-- is untrusted: only strings count, each cut to 64 bytes, at most 12 of them. nil when none reads.
local OWNERS_MAX = 12
function Import.ReadOwners(list)
    if type(list) ~= "table" then return nil end
    local owners = {}
    for _, v in ipairs(list) do
        if #owners >= OWNERS_MAX then break end
        local name = clipped(v, 64)
        if name then owners[#owners + 1] = name end
    end
    return #owners > 0 and owners or nil
end

--- Whether a roster is for the guild this character is in (GOSROST1 v7 `guild`, the site's #603; spec 115). The
--- owner's own list can hold raids of more than one guild, and the inbox is the game folder's, read by every
--- character of it: a roster that names its guild is this one's only when that is GetGuildInfo's name the way the
--- site compares them (GuildOS.SameGuildName: the brackets and capitals aside, accented and Cyrillic ones too), as
--- the GOSGILD1's `guild` is read (GuildBlock). One that names none, from a site before v7, is, as it always was.
--- The addon acts on no other: no prompt, no button, nothing on the calendar. Never accepted on a doubt.
function Import.OfThisGuild(roster)
    local guild = type(roster) == "table" and roster.guild
    if type(guild) ~= "string" then return true end
    local mine = GetGuildInfo("player")
    return type(mine) == "string" and mine ~= "" and GuildOS.SameGuildName(mine, guild)
end

-- A GOSCORE1 the site gives as a code to copy, read the way the inbox's is (CoresFromInbox): the same
-- alphabet the companion lets into Inbox.lua, a body no longer than CORES_MAX, the `fmt` inside. Pasted
-- text may come with spaces, line breaks or words around the code; the marker is looked for anywhere.
-- Returns the decoded table, or nil when it is not one (issue #347).
local CORES_MAX = 262144   -- characters of a GOSCORE1 body: a guild's cores are a few kilobytes
function Import.ReadCores(raw)
    if type(raw) ~= "string" then return nil end
    local at = raw:find(CORES_PREFIX, 1, true)
    if not at then return nil end
    local body = raw:sub(at + #CORES_PREFIX):gsub("%s+", "")
    if body == "" or #body > CORES_MAX or body:find("[^A-Za-z0-9()]") then return nil end
    local data = unwrap(body, "GOSCORE1")
    if type(data) ~= "table" or type(data.cores) ~= "table" then return nil end
    return data
end

-- Whether a pasted text is a GOSCORE1 rather than a raid's roster (issue #347).
function Import.IsCoresCode(raw)
    return type(raw) == "string" and raw:find(CORES_PREFIX, 1, true) ~= nil and not raw:find(WIRE_PREFIX, 1, true)
end

--- Parse and keep. Returns (count, err). A GOSCORE1 pasted into the same box is the guild's cores, imported
--- as the inbox's are (CoreManager:ImportPasted): then (count of cores, nil, the line to show) (issue #347).
function Import:Load(raw)
    if Import.IsCoresCode(raw) and GuildOS.CoreManager then
        if not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then
            return nil, L["The web companion is off. Turn it on with /gos web on."]
        end
        return GuildOS.CoreManager:ImportPasted(raw)
    end
    local roster, err = self:Parse(raw)
    if not roster then return nil, err end
    -- Pasted by hand, a roster with nobody in it is a copy of the wrong thing. Nobody to invite is
    -- not an empty envelope once v2 exists, though: a night where everyone declined is a real
    -- answer. From the inbox an empty one is a raid nobody has answered yet, and it still belongs
    -- on the calendar (#146), so the refusal lives here and not in Parse.
    if #roster.members == 0 and not (roster.signups and #roster.signups > 0) then
        return nil, L["That roster has nobody in it."]
    end
    -- Pasted by hand, the roster is the leader's to act on whatever guild it is: a federation core's leader can be in
    -- guild B while the core's raid is guild A's (the site's spec 089; ruling R9). Another guild's is taken with a
    -- line that says whose it is, and never reaches what is the guild's own: the calendar, the owner's prompt and the
    -- raid tracker's nights read the inbox's raids (_webRaids, db.companionRaids), never this one.
    if not Import.OfThisGuild(roster) then
        GuildOS:Print(string.format(L["That roster is a raid of the guild %s: the raid buttons act on it, and it stays off this guild's calendar."],
            Import.Inert(roster.guild)))
    end

    -- The site's loot data reaches the night only from the inbox (db.siteLoot); the kept roster never holds it.
    roster.loot = nil
    -- Pasted: the newest word on its raid, over the inbox's copy (ButtonRaid).
    roster.pasted = true
    GuildOS.db.companionRoster = roster
    return #roster.members
end

function Import:Current()
    return GuildOS.db and GuildOS.db.companionRoster
end

--- What the site last confirmed. Returns (unixTime, members) or nil.
---
--- Publishing used to be blind in this direction: the addon wrote the file, the
--- companion sent it, and nothing ever came back, so the panel could only ever say
--- "written". The companion knows the answer and already writes this file, so it
--- says so.
---
--- Numbers only, and that is a contract rather than a preference: the companion
--- formats these with %d, so the property that nothing off the network reaches a
--- file the client executes survives intact.
function Import:Ack()
    local a = _G.GuildOSInboxAck
    if type(a) ~= "table" then return nil end
    local at = tonumber(a.at)
    if not at or at <= 0 then return nil end
    return at, tonumber(a.members) or 0
end

--- Whether Inbox.lua carries any block. A current companion leaves the ack out where no guild
--- link of it owns this client's folder and still writes the recruiting list, so an inbox with
--- blocks and no ack is a working companion, not an old one; an empty one is the file the addon
--- package ships, which the companion has not written over yet.
function Import:InboxHasBlocks()
    local inbox = _G.GuildOSInbox
    if type(inbox) == "string" then return inbox ~= "" end
    if type(inbox) == "table" then
        for _, v in ipairs(inbox) do
            if type(v) == "string" and v ~= "" then return true end
        end
    end
    return type(_G.GuildOSInboxFirst) == "string" and _G.GuildOSInboxFirst ~= ""
end

----------------------------------------------------------------------
-- Inviting
----------------------------------------------------------------------

----------------------------------------------------------------------
-- The inbox: what the companion left for us.
--
-- The companion writes Interface/AddOns/GuildOS/Inbox.lua, which the client
-- executes at load, setting the GuildOSInbox global. That makes it untrusted
-- input even though our own tool produced it, so it goes through the same
-- Parse a hand-pasted string does and a bad one is dropped on the floor.
--
-- Silent on failure on purpose: a damaged inbox is the companion's problem to
-- report in its own panel, and a chat error at every login about a file the
-- player cannot see or fix is just noise.
--
-- The site is where raids are planned, so a valid inbox wins over whatever was
-- stored. Pasting by hand stays the fallback for when the companion is not
-- running. See specs/009-a-volta-para-o-jogo/spec.md in guildos-web.
----------------------------------------------------------------------
function Import:ConsumeInbox()
    -- A table of strings from a current companion, a bare string from one that
    -- has not been updated. The two halves ship separately, so both shapes have
    -- to work rather than the older one silently importing nothing.
    local inbox = _G.GuildOSInbox
    local raws = {}
    if type(inbox) == "table" then
        for _, v in ipairs(inbox) do
            if type(v) == "string" and v ~= "" then raws[#raws + 1] = v end
        end
    elseif type(inbox) == "string" and inbox ~= "" then
        raws[1] = inbox
    elseif type(_G.GuildOSInboxFirst) == "string" and _G.GuildOSInboxFirst ~= "" then
        raws[1] = _G.GuildOSInboxFirst
    end
    if #raws == 0 then return false end

    -- The whole set is the unit: a raid added or dropped changes it even when
    -- the first one did not move.
    local key = table.concat(raws, "|")
    if key == self._lastInbox then return false end

    -- Every raid goes on the calendar, once the rank is known (CalendarFromInbox). The soonest
    -- somebody answered is the one the Web panel's invite and group buttons act on: an unanswered
    -- leftover on an earlier night would otherwise take it over (#146); with none answered, the
    -- soonest of all.
    local soonest, soonestAny, imported, raids = nil, nil, 0, {}
    -- And all of them, stripped to the fields that answer "which planned raid is this
    -- night": where, when and, on retail, on which difficulty (issue #182). The full
    -- rosters are not kept: the soonest is the one anybody acts on, and holding ten of
    -- them in SavedVariables to answer one question later is ten rosters of churn at
    -- every logout.
    local planned, foreign = {}, nil
    for _, raw in ipairs(raws) do
        local roster = self:Parse(raw)
        -- Another guild's raid (the owner's own list, read on a character of another guild) is not read at all: not
        -- kept, not matched to a night, not on the calendar, no button and no prompt (OfThisGuild, issue #400). An
        -- inbox of nothing else is, to this character, an inbox with no raid, and that is said (SayForeign).
        if roster and not Import.OfThisGuild(roster) then
            foreign = foreign or roster.guild
        elseif roster then
            imported = imported + 1
            raids[#raids + 1] = roster
            if roster.raidId and roster.instanceKey then
                planned[#planned + 1] = {
                    raidId = roster.raidId,
                    instanceKey = roster.instanceKey,
                    -- A night of two places is the same raid in both (the site's #556): RaidFor matches any.
                    instanceKeys = roster.instanceKeys,
                    startsAt = roster.startsAt or 0,
                    difficulty = roster.difficulty,
                }
            end
            local answered = #roster.members > 0 or (roster.signups and #roster.signups > 0)
            if answered and (not soonest or (roster.startsAt or 0) < (soonest.startsAt or 0)) then
                soonest = roster
            end
            if not soonestAny or (roster.startsAt or 0) < (soonestAny.startsAt or 0) then
                soonestAny = roster
            end
        end
    end
    if imported == 0 then
        if foreign then self:SayForeign(foreign) end
        return false
    end
    self._foreignLine = nil
    soonest = soonest or soonestAny

    self._lastInbox = key
    self._webRaids = raids
    GuildOS.db.companionRaids = planned
    -- What the site holds for each raid's night, already in the addon's own shapes. Kept apart from
    -- db.softRes, db.lootPrios and db.guildWishlists, which are the game's and are never written from here:
    -- the readers choose between the two, and a night without the site's data leaves nothing behind.
    -- One entry per raid, from every roster of the inbox (two groups of a guild can raid in one window),
    -- replaced by raidId. Every entry lives in memory (SiteRaids), rebuilt from Inbox.lua at each login;
    -- only the ones whose night has begun are saved (db.siteLoot), because the site stops serving a started
    -- raid after a few hours and a /reload in the middle must not take the night's reserves away. Ten raids
    -- of full lists would weigh megabytes in SavedVariables, for nights days away.
    local now, mem, listed = GetServerTime(), {}, {}
    for _, roster in ipairs(raids) do
        if type(roster.raidId) == "string" then
            listed[roster.raidId] = true
            local loot = roster.loot
            if loot then
                mem[roster.raidId] = {
                    startsAt = roster.startsAt, instanceKey = roster.instanceKey, instanceKeys = roster.instanceKeys,
                    difficulty = roster.difficulty,
                    softres = loot.softres, prios = loot.prios, priosHidden = loot.priosHidden, wishlists = loot.wishlists,
                }
            end
        end
        -- Read into the entries above: no roster this module keeps carries it (db.companionRoster included).
        roster.loot = nil
    end
    self._siteRaids = mem
    -- A saved entry the inbox no longer lists stays while its night lasts; one it lists again is the inbox's.
    local kept = {}
    local old = GuildOS.db.siteLoot
    for id, e in pairs(type(old) == "table" and type(old.raids) == "table" and old.raids or {}) do
        if not listed[id] and Import.UnderWay(e, now) then kept[id] = e end
    end
    for id, e in pairs(mem) do
        if Import.UnderWay(e, now) then kept[id] = e end
    end
    GuildOS.db.siteLoot = next(kept) and { raids = kept } or nil
    GuildOS.db.companionRoster = soonest
    return true, #soonest.members
end

--- Says, once a session, that the inbox's raids were all another guild's (issue #400): in chat (not to a character
--- with no guild), and kept for the Web tab's reason line (ForeignLine). A guild the site names otherwise than the game does reads its name here, rather
--- than losing the site's raids without a word. `guild` is the first roster's; both names are made inert.
function Import:SayForeign(guild)
    local mine = GetGuildInfo("player")
    local site = Import.Inert(tostring(guild))
    if type(mine) == "string" and mine ~= "" then
        self._foreignLine = string.format(L["The website's raids are for the guild %s, not %s."], site, Import.Inert(mine))
    else
        -- A character with no guild has nothing the site's raids could be: the Web tab says so, chat stays quiet at
        -- every login of every guildless alt.
        self._foreignLine = string.format(L["The website's raids are for the guild %s, and this character is in none."], site)
        return
    end
    if not self._foreignSaid then
        self._foreignSaid = true
        GuildOS:Print(self._foreignLine)
    end
end

--- The line SayForeign said, while the inbox's raids are all another guild's; nil otherwise.
function Import:ForeignLine()
    return self._foreignLine
end

-- The raid the buttons act on: the nearest to `now` among the rosters of this session's inbox and the one
-- kept from the last, while `now` is from an hour before its start to three hours after it (spec 115: "de 1
-- hora antes a 3 horas depois do começo"), so its start is from three hours ago to an hour ahead; nil when none
-- is. A raid that began five hours ago is over for the buttons, and the soonest one in the inbox is no longer
-- "the one" (the issue's #400). Rosters without a start time (0) are never inside the window. Two as near, one
-- begun and one ahead, go to the one under way: its leader is the one at the keyboard.
--
-- The kept roster comes first, and the inbox's copy of the same raid gives way to it: pasted by hand, it is the
-- newest word on that raid (the inbox is read at login only), new groups or a start the site moved included. A
-- roster pasted by hand counts whatever guild it is (a federation core's raid, the site's spec 089; ruling R9);
-- the inbox's count only when they are this guild's (OfThisGuild).
local BUTTON_BEFORE = 3 * 3600   -- seconds a start may lie behind now: three hours into the raid
local BUTTON_AHEAD = 3600        -- seconds a start may lie ahead of now: an hour before the raid
function Import:ButtonRaid(now)
    now = now or GetServerTime()
    local best, bestGap, bestBegun
    local function consider(roster)
        local startsAt = type(roster) == "table" and tonumber(roster.startsAt)
        if not startsAt or startsAt <= 0 then return end
        if not roster.pasted and not Import.OfThisGuild(roster) then return end
        local gap = startsAt - now
        if gap < -BUTTON_BEFORE or gap > BUTTON_AHEAD then return end
        local away, begun = math.abs(gap), gap <= 0
        if not best or away < bestGap or (away == bestGap and begun and not bestBegun) then
            best, bestGap, bestBegun = roster, away, begun
        end
    end
    local kept = self:Current()
    consider(kept)
    local keptId = type(kept) == "table" and kept.raidId or nil
    for _, roster in ipairs(self._webRaids or {}) do
        if not (keptId ~= nil and roster.raidId == keptId) then consider(roster) end
    end
    return best
end

--- The newest copy of `roster`'s raid: the kept roster when it is the same raid (pasted after the inbox was read,
--- ButtonRaid), else `roster` itself. The owner's prompt reads its raid through it.
function Import:Freshest(roster)
    local kept = self:Current()
    if type(roster) == "table" and type(kept) == "table" and roster.raidId ~= nil and kept.raidId == roster.raidId then
        return kept
    end
    return roster
end

--- The roster of the raid `raidId`, the kept one first (the newest word on its raid, as in ButtonRaid), else this
--- session's inbox copy; nil when neither holds it. The loot rule of the raid in progress is read through it
--- (audit L3): with two raids in one night, the one the session was stamped with at zone-in, not the nearest start.
function Import:RosterOf(raidId)
    if raidId == nil then return nil end
    local kept = self:Current()
    if type(kept) == "table" and kept.raidId == raidId then return kept end
    for _, roster in ipairs(self._webRaids or {}) do
        if type(roster) == "table" and roster.raidId == raidId then return roster end
    end
    return nil
end

-- Whether this character owns `roster`: its name, in the form the client's members are keyed by, is one of
-- the roster's owners (case does not matter). WoW: Forever keys a person by the whole name with its surname,
-- no realm (UnitName gives only the first name there: Compat.PlayerName, issue #26); Anniversary and retail
-- by Name-Realm.
function Import:IsMine(roster)
    local owners = type(roster) == "table" and roster.owners
    if type(owners) ~= "table" or #owners == 0 then return false end
    local name = GuildOS.Compat.PlayerName()
    -- A secret is never compared, not even with "".
    if type(name) ~= "string" or GuildOS.Compat.IsSecret(name) or name == "" then return false end
    local me = GuildOS:RealmBound() and GuildOS:GetPlayerKey(name) or name
    if not me then return false end
    me = me:lower()
    for _, owner in ipairs(owners) do
        if type(owner) == "string" and owner:lower() == me then return true end
    end
    return false
end

-- Whether a site loot entry's night has begun and is not over: from two hours before its start to eight
-- after (the same window as RaidFor). A raid the site stopped listing before that was taken down.
function Import.UnderWay(e, now)
    local startsAt = type(e) == "table" and tonumber(e.startsAt)
    return startsAt ~= nil and now >= startsAt - MATCH_EARLY and now <= startsAt + MATCH_LATE
end

-- Every raid entry the last inbox read built, in memory only: { [raidId] = entry }, or nil before one.
function Import:SiteRaids()
    return self._siteRaids
end

-- Saves the entries whose night is under way at `now` (the saved ones and the ones in memory), and drops
-- the rest from SavedVariables. At logout too, so a raid that began during the session survives a /reload
-- past the site's few hours of grace.
function Import:KeepSiteLoot(now)
    local db = GuildOS.db
    if type(db) ~= "table" then return end
    now = now or GetServerTime()
    local kept = {}
    local old = db.siteLoot
    for id, e in pairs(type(old) == "table" and type(old.raids) == "table" and old.raids or {}) do
        if Import.UnderWay(e, now) then kept[id] = e end
    end
    for id, e in pairs(self._siteRaids or {}) do
        if Import.UnderWay(e, now) then kept[id] = e end
    end
    db.siteLoot = next(kept) and { raids = kept } or nil
end

-- One frame, at load, as CompanionExport's writer: PLAYER_LOGOUT exists on every client.
local keeper = CreateFrame("Frame")
keeper:RegisterEvent("PLAYER_LOGOUT")
keeper:SetScript("OnEvent", function()
    -- Its own pcall: nothing here may stand between the client and its logout.
    pcall(Import.KeepSiteLoot, Import)
end)

-- The guild's Discord cores in the inbox (a GOSCORE1, specs/041 in guildos-web), decoded, whether the
-- companion is on in game, and when the inbox was written (its ack line, #138): nil when there are
-- none or the string is damaged. CoreManager imports them once the guild's db is known (#135), and
-- says why when it does not; the roster reader above passes over them.
function Import:CoresFromInbox()
    local inbox = _G.GuildOSInbox
    if type(inbox) ~= "table" then return nil end
    for _, v in ipairs(inbox) do
        if type(v) == "string" and v:sub(1, #CORES_PREFIX) == CORES_PREFIX then
            local ack = _G.GuildOSInboxAck
            local at = type(ack) == "table" and tonumber(ack.at) or nil
            local on = GuildOS.Companion and GuildOS.Companion:IsEnabled() or false
            return Import.ReadCores(v), on, at
        end
    end
    return nil
end

-- The inbox's GOSGILD1 (guildos-web #259): what only the site knows, decoded, or nil when there is
-- none, it is damaged, it is another guild's or more than a week old, or the companion is off.
-- It is shown and never run. Forever's: no other game's site sends one.
function Import:GuildBlock()
    local inbox = _G.GuildOSInbox
    if type(inbox) ~= "table" or not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then return nil end
    for _, v in ipairs(inbox) do
        if type(v) == "string" and v:sub(1, #GUILD_PREFIX) == GUILD_PREFIX then
            -- Decoded once: the window's title asks every few seconds, and the file only changes on a reload.
            if self._blockRaw ~= v then
                self._blockRaw, self._blockData = v, unwrap(v:sub(#GUILD_PREFIX + 1), "GOSGILD1")
            end
            local data = self._blockData
            local mine = GetGuildInfo("player")
            -- The site's comparison, capitals aside past ASCII (GuildOS.SameGuildName, issue #400).
            if not data or not mine or mine == "" or not GuildOS.SameGuildName(data.guild, mine) then return nil end
            -- As what must hold: a date that is NaN or inf is too old to believe, never good for ever.
            local at = GuildOS.Finite(data.at)
            if not (at and GetServerTime() - at <= BLOCK_MAX_AGE) then return nil end
            return data
        end
    end
    return nil
end

-- The inbox's GOSRECR1 (specs/071 in guildos-web): every guild recruiting in this client's game, public
-- and written with or without a token, so it is read whether the companion is on in game or not. Decoded
-- once per string, as the block is. Nil with none, a damaged one, one for the other game (a client folder
-- can hold the list another install left) or one more than three days old. Raw ads: GuildFinder cleans them.
function Import:RecruitDirectory()
    local inbox = _G.GuildOSInbox
    if type(inbox) ~= "table" then return nil end
    local game = GuildOS.Client.isRetail and "RETAIL" or "FOREVER"
    self._recruit = self._recruit or {}
    for _, v in ipairs(inbox) do
        if type(v) == "string" and v:sub(1, #RECRUIT_PREFIX) == RECRUIT_PREFIX then
            if self._recruit[v] == nil then self._recruit[v] = unwrap(v:sub(#RECRUIT_PREFIX + 1), "GOSRECR1") or false end
            local data = self._recruit[v]
            local at = data and GuildOS.Finite(data.at)
            if data and type(data.ads) == "table" and data.game == game
               and at and GetServerTime() - at <= RECRUIT_MAX_AGE then
                return data
            end
        end
    end
    return nil
end

-- The guild's own recruiting ad out of its GOSGILD1, for the officers' addon to spread: cleaned, and nil
-- once its own `x` has passed even though the block is good for a week.
function Import:OwnRecruitAd()
    local block = self:GuildBlock()
    local GF = GuildOS.GuildFinder
    local raw = block and block.recruitAd
    if type(raw) ~= "table" or not GF then return nil end
    local ad = GF:Normalize(raw)
    if not ad or ad.x <= GetServerTime() then return nil end
    ad.heard, ad.verified = nil, nil
    return ad
end

-- The GOSGILD1's joinRequests (specs/071, guildos#245): who asked the guild to take them, on the site or
-- in the game, and what was decided. The strings are cleaned here; the class, level and role are
-- checked where they are used. Nil with no block, and an empty list when it holds none.
function Import:SiteJoinRequests()
    local block = self:GuildBlock()
    local GF = GuildOS.GuildFinder
    local raw = block and block.joinRequests
    if type(raw) ~= "table" or not GF then return nil end
    local out = {}
    for _, r in ipairs(raw) do
        local character = type(r) == "table" and GF.Text(r.character, 48)
        local at = type(r) == "table" and GuildOS.Finite(r.at)
        if character and type(r.id) == "string" and #r.id <= 40 and r.id:match("^[%w_%-]+$")
           and type(r.status) == "string" and at then
            out[#out + 1] = { id = r.id, character = character, class = r.class, level = r.level, role = r.role,
                note = GF.Text(r.note, 120), source = r.source == "addon" and "addon" or "site", status = r.status, at = at }
        end
    end
    return out
end

-- The GOSGILD1's allianceBans (#408, the site's guildos-web#616): the bans the OTHER guilds of this
-- guild's alliance shared, for the officers' alerts. Every field checked, the text made inert, the key
-- made this client's, at most BanList.ALLIANCE_MAX read; one that fails is passed over alone, and one
-- filed by this very guild is not another guild's. Never stored: BanList holds the list in memory.
-- Nil with no block or none in it.
--   { id, key, name, guild, reason = BanList.SHARE_REASONS, note?, at, appeal? }
function Import:AllianceBans()
    local block = self:GuildBlock()
    local raw = block and block.allianceBans
    local BL = GuildOS.BanList
    if type(raw) ~= "table" or not BL then return nil end
    local mine = (GetGuildInfo("player") or ""):lower()
    local out = {}
    for i = 1, math.min(#raw, BL.ALLIANCE_MAX) do
        local r = raw[i]
        if type(r) == "table" then
            local id = type(r.id) == "string" and #r.id <= 64 and r.id:match("^[%w_:%-]+$") and r.id or nil
            local key = siteKey(r.key)
            local guild = siteText(r.guild, SITE_LOOT.name)
            local reason = BL.ShareReason(r.reason)
            local at = GuildOS.Finite(r.at)
            if id and key and guild and reason and at and guild:lower() ~= mine then
                key = GuildOS:LocalMemberKey(key)
                out[#out + 1] = {
                    id = id, key = key, name = siteName(r.name) or key:match("^([^-]+)") or key,
                    guild = guild, reason = reason, note = type(r.note) == "string" and BL.CleanNote(Import.Inert(r.note)) or nil,
                    at = math.floor(at), appeal = r.appeal == true or nil,
                }
            end
        end
    end
    return out
end

-- The inbox's GOSALLY1 (alianca.md §3.2, the site's specs/123): the alliance's directory and its open raids.
-- Display only, and untrusted whatever wrote it: the string held to the print alphabet and ALLY_MAX characters,
-- the inflated text to ALLY_JSON_MAX bytes, then every field checked and cut by ReadAlliance below; a part that
-- fails is passed over alone, a block that is not v1 or names no alliance is nothing. In memory only, never in
-- the guild's member DB nor in SavedVariables (as the GOSGILD1 it rides with: the inbox is read again at every
-- login). Nil with no inbox, the companion off, a damaged block, another guild's or realm's, or one over a week
-- old. Which alliance it must be (the code in force, from the site) is Alliance's to check.
Import.ALLY_MAX = 262144          -- characters of the encoded body (the site's cap, 256 KiB)
Import.ALLY_JSON_MAX = 4194304    -- bytes of the inflated text: a full block is about a megabyte
Import.ALLY = { guilds = 16, members = 1000, recipes = 2000, recipeTotal = 200000, raids = 30,
                name = 48, key = 64, guildName = 64, title = 192, where = 240, allianceName = 144,
                level = 1000, size = 80, going = 1000, id = 2147483647, time = 4102444800 }
local ALLY_ROLE = { TANK = true, HEALER = true, DPS = true }
local ALLY_VIA = { founder = true, invite = true, federation = true }

-- A key or a name of the block: a string within `max` bytes, one line, no bar; refused (nil), never cut.
local function allyWord(v, max)
    if type(v) ~= "string" or v == "" or #v > max or v:find("[|%c]") then return nil end
    local s = strtrim(v)
    return s ~= "" and s or nil
end
local function allyInt(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end
local function allyList(v, max)
    if type(v) ~= "table" then return {} end
    local n = #v
    return v, math.min(n, max)
end

-- A decoded GOSALLY1 held to its shape (pure, for the harness), or nil.
--   { guild, realm?, at, cut?, alliance = { name, tag, version },
--     guilds = { { name, realm?, self?, via?, members = { { key, name, class, level, role?, main?, spells? } } } },
--     raids = { { id, guild, title, where?, startsAt, size, lead?, going } } }
-- `spells` is the member's recipe spell ids, as the site sends them; Alliance maps them to what they make.
function Import.ReadAlliance(data)
    local A = Import.ALLY
    if type(data) ~= "table" or data.fmt ~= "GOSALLY1" or data.v ~= 1 then return nil end
    local guild = allyWord(data.guild, A.guildName)
    local at = allyInt(data.at, 1, A.time)
    local a = type(data.alliance) == "table" and data.alliance or nil
    local tag = a and type(a.tag) == "string" and a.tag:match("^[A-Z0-9]+$") and #a.tag <= 12 and a.tag or nil
    local version = a and allyInt(a.version, 1, A.id)
    local name = a and type(a.name) == "string" and siteText(a.name, A.allianceName) or nil
    if not (guild and at and tag and version and name) then return nil end
    local out = { guild = guild, realm = allyWord(data.realm, A.guildName), at = at, cut = data.cut == true or nil,
                  alliance = { name = name, tag = tag, version = version }, guilds = {}, raids = {} }
    local names, budget = {}, A.recipeTotal
    local list, n = allyList(data.guilds, A.guilds)
    for i = 1, n or 0 do
        local g = list[i]
        local gname = type(g) == "table" and allyWord(g.name, A.guildName)
        if gname and not names[gname:lower()] then
            names[gname:lower()] = true
            local og = { name = gname, realm = allyWord(g.realm, A.guildName), self = g.self == true or nil,
                         via = type(g.via) == "string" and ALLY_VIA[g.via] and g.via or nil, members = {} }
            -- This block's own guild never carries members (the site's rule, held here too).
            if not og.self and not GuildOS.SameGuildName(gname, guild) then
                local byKey = {}
                local ms, mn = allyList(g.members, A.members)
                for j = 1, mn or 0 do
                    local m = ms[j]
                    local key = type(m) == "table" and allyWord(m.key, A.key)
                    local mname = key and allyWord(m.name, A.name)
                    local class = mname and type(m.class) == "string" and m.class:match("^[A-Z_]+$")
                        and #m.class >= 2 and #m.class <= 16 and m.class or nil
                    local level = class and allyInt(m.level, 0, A.level)
                    if level and not byKey[key] then
                        local main = allyWord(m.main, A.key)
                        local om = { key = key, name = mname, class = class, level = level,
                                     role = type(m.role) == "string" and ALLY_ROLE[m.role] and m.role or nil,
                                     main = (main and main ~= key) and main or nil }
                        byKey[key] = om
                        og.members[#og.members + 1] = om
                    end
                end
                local cs, cn = allyList(g.crafters, A.members)
                for j = 1, cn or 0 do
                    local c = cs[j]
                    local om = type(c) == "table" and type(c.key) == "string" and byKey[c.key] or nil
                    if om and not om.spells and type(c.recipes) == "table" and budget > 0 then
                        local spells, seen = {}, {}
                        for k = 1, math.min(#c.recipes, A.recipes, budget) do
                            local id = allyInt(c.recipes[k], 1, A.id)
                            if id and not seen[id] then
                                seen[id] = true
                                spells[#spells + 1] = id
                            end
                        end
                        budget = budget - #spells
                        if #spells > 0 then om.spells = spells end
                    end
                end
            end
            out.guilds[#out.guilds + 1] = og
        end
    end
    local rl, rn = allyList(data.raids, A.raids)
    for i = 1, rn or 0 do
        local r = rl[i]
        if type(r) == "table" then
            local id = type(r.id) == "string" and #r.id <= 64 and r.id:match("^[%w_%-]+$") and r.id or nil
            local owner = allyWord(r.guild, A.guildName)
            local title = siteText(r.title, A.title)
            local startsAt = allyInt(r.startsAt, 1, A.time)
            local size = allyInt(r.size, 1, A.size)
            local going = allyInt(r.going, 0, A.going)
            -- Never this block's own guild, and only a guild the block names.
            if id and owner and title and startsAt and size and going and names[owner:lower()]
               and not GuildOS.SameGuildName(owner, guild) then
                out.raids[#out.raids + 1] = { id = id, guild = owner, title = title, where = siteText(r.where, A.where),
                    startsAt = startsAt, size = size, lead = allyWord(r.lead, A.key), going = going }
            end
        end
    end
    table.sort(out.raids, function(x, y)
        if x.startsAt ~= y.startsAt then return x.startsAt < y.startsAt end
        return x.id < y.id
    end)
    return out
end

-- Whether a block's realm is this guild's: WoW: Forever has none, so a block naming one there is another game's;
-- elsewhere one naming another realm is another region's or realm's (a client folder can hold what another install
-- left), and one naming none cannot be told apart and stands. Spaces, hyphens and capitals aside.
local function sameRealm(realm)
    local forever = not (GuildOS.Client.isAnniversary or GuildOS.Client.isRetail)
    if forever then return realm == nil end
    if not realm then return true end
    local function bare(s) return tostring(s or ""):gsub("[%s%-']", ""):lower() end
    local _, _, _, guildRealm = GetGuildInfo("player")
    local mine = guildRealm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    return bare(realm) == bare(mine) or bare(realm) == bare(GetRealmName())
end

function Import:AllianceBlock()
    local inbox = _G.GuildOSInbox
    if type(inbox) ~= "table" or not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then return nil end
    for _, v in ipairs(inbox) do
        if type(v) == "string" and v:sub(1, #ALLY_PREFIX) == ALLY_PREFIX then
            -- Decoded and cleaned once per string: the file only changes on a reload.
            if self._allyRaw ~= v then
                local body = v:sub(#ALLY_PREFIX + 1)
                local ok = body ~= "" and #body <= Import.ALLY_MAX and not body:find("[^A-Za-z0-9()]")
                self._allyRaw = v
                self._allyData = ok and Import.ReadAlliance(unwrap(body, "GOSALLY1", Import.ALLY_JSON_MAX)) or false
            end
            local data = self._allyData
            local mine = GetGuildInfo("player")
            if not data or not mine or mine == "" or not GuildOS.SameGuildName(data.guild, mine)
               or not sameRealm(data.realm) then
                return nil
            end
            if GetServerTime() - data.at > BLOCK_MAX_AGE then return nil end
            return data
        end
    end
    return nil
end

-- The GOSGILD1's discordLinked (#422, the site's specs/009): the keys of the guild's characters whose
-- player linked their Discord on guildos.me, sent only on an officer's code. Read as a whole or not at
-- all: a list that is not one, longer than DISCORD_LINKED_MAX, or with an entry that is not a key (not a
-- string, over 64 bytes, a bar or a control character) is refused and this is nil, since a cut or patched
-- list would call a linked member "without Discord". Kept in memory only, per block, as a set of this
-- client's keys in lower case. Nil with no block or no field (an older site): the game does not know.
Import.DISCORD_LINKED_MAX = 1000
function Import:DiscordLinked()
    local block = self:GuildBlock()
    local raw = block and block.discordLinked
    if type(raw) ~= "table" then return nil end
    if self._linkedOf == raw then return self._linked end
    local set
    local n = #raw
    if n <= Import.DISCORD_LINKED_MAX then
        local count = 0
        for _ in pairs(raw) do
            count = count + 1
            if count > n then break end
        end
        set = count == n and {} or nil
        for i = 1, set and n or 0 do
            local k = raw[i]
            if type(k) ~= "string" or k == "" or #k > SITE_LOOT.name or k:find("[|%c]") then
                set = nil
                break
            end
            set[GuildOS:LocalMemberKey(k):lower()] = true
        end
    end
    self._linkedOf, self._linked = raw, set
    return set
end

-- The GOSGILD1's events (the site's #652, specs/118): the guild's events that are not raids — a social
-- night, PvP, a meetup, anything else — for the calendar to show as an event of that type, from the site,
-- with nobody to invite. The inbox is untrusted: at most SITE_EVENTS_MAX read; an id of the site's alphabet
-- ([%w_-], 64 bytes at most), a kind of the four, a title and a place made inert and held to their bytes, a
-- whole positive start and whole counts, or the entry is passed over alone. A meetup is a SOCIAL event in the
-- game: a guild gathering is social, and OTHER would say less.
--   { id, kind = "SOCIAL"|"PVP"|"OTHER", title, startsAt, clock?, where?, going, maybe }
-- Nil with no block, or a block that says nothing of events (a site before #652): the calendar then changes
-- nothing. An empty list is the site saying it has none in the window.
Import.SITE_EVENTS_MAX = 10
local SITE_EVENT_KIND = { social = "SOCIAL", pvp = "PVP", meetup = "SOCIAL", other = "OTHER" }
local SITE_EVENT_TEXT = { title = 192, where = 240 }   -- bytes: the site's 64 and 80 characters, at up to three each
local SITE_EVENT_COUNT = 100000
function Import:SiteEvents()
    local block = self:GuildBlock()
    local raw = block and block.events
    if type(raw) ~= "table" then return nil end
    local out = {}
    for i = 1, math.min(#raw, Import.SITE_EVENTS_MAX) do
        local r = raw[i]
        if type(r) == "table" then
            local id = type(r.id) == "string" and #r.id <= 64 and r.id:match("^[%w_%-]+$") and r.id or nil
            local kind = type(r.kind) == "string" and SITE_EVENT_KIND[r.kind] or nil
            local title = siteText(r.title, SITE_EVENT_TEXT.title)
            local ok, startsAt, going, maybe = pcall(function()
                return siteInt(r.startsAt, 1, 4102444800), siteInt(r.going, 0, SITE_EVENT_COUNT), siteInt(r.maybe, 0, SITE_EVENT_COUNT)
            end)
            if id and kind and title and ok then
                out[#out + 1] = {
                    id = id, kind = kind, title = title, startsAt = startsAt,
                    -- Checked where it is kept (Calendar's cleanClock), as a roster's.
                    clock = type(r.clock) == "table" and r.clock or nil,
                    where = siteText(r.where, SITE_EVENT_TEXT.where), going = going, maybe = maybe,
                }
            end
        end
    end
    return out
end

-- Winter Veil's snow globe (the site's specs/119, guildos#437) ------------------------------------------------------
-- Everything here is off the network: each number whole and bounded, each key one line with no `|`, each list capped.
-- The game only shows what the site says and tells it what the player asked; nothing here decides a rarity.
Import.VEIL_LIST_MAX = 1000
Import.VEIL_NOTE_MAX = 80
local VEIL_TIME = 4102444800
Import.VEIL_SCENES = { "tree", "cabin", "snowman", "fire", "mountain" }
Import.VEIL_RARITIES = { "common", "rare", "epic", "legendary" }
local VEIL_SCENE, VEIL_RARITY = {}, {}
for _, s in ipairs(Import.VEIL_SCENES) do VEIL_SCENE[s] = true end
for _, r in ipairs(Import.VEIL_RARITIES) do VEIL_RARITY[r] = true end

local function veilKey(k)
    if type(k) ~= "string" or k == "" or #k > 96 or k:find("[|\r\n]") then return nil end
    return GuildOS:LocalMemberKey(k)
end
Import.VeilKey = veilKey

-- A note off the network: at most 80 characters, and nothing in it opens a colour, a link or a texture.
local function utf8len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
local function veilNote(n)
    if type(n) ~= "string" or #n > 4 * Import.VEIL_NOTE_MAX or utf8len(n) > Import.VEIL_NOTE_MAX then return nil end
    return (Import.Inert(n):gsub("%c", " "))
end
Import.VeilNote = veilNote

-- A globe somebody opened, as the owner sees it. Nil when it is not one.
local function veilOrnament(o)
    if type(o) ~= "table" or type(o.id) ~= "string" or o.id == "" or #o.id > 64 or o.id:find("[|\r\n]") then return nil end
    if not (VEIL_SCENE[o.scene] and VEIL_RARITY[o.rarity]) then return nil end
    local ok, year, at = pcall(function() return siteInt(o.year, 2020, 2100), siteInt(o.openedAt, 1, VEIL_TIME) end)
    if not ok then return nil end
    return { id = o.id, year = year, scene = o.scene, rarity = o.rarity, openedAt = at,
             from = veilKey(o.from), host = o.host == true or nil, note = o.note ~= nil and veilNote(o.note) or nil }
end

-- An event as either block carries it (the guild's `veil`, or a person's `event`), held to its shape; nil when not one.
--   { year, joinUntil, wrapUntil, openAt, reassignDays, drawn, salt?, chimney?, counts = { entrants, wrapped, pairs, opened },
--     entrants? = { { key, wrapped } }, carriers? = { [giverKey] = carrierKey },
--     reveal? = { { giver, to, scene, rarity, host? } } }
local function veilEvent(v)
    if type(v) ~= "table" then return nil end
    local ok, out = pcall(function()
        local c = type(v.counts) == "table" and v.counts or {}
        return {
            year = siteInt(v.year, 2020, 2100),
            joinUntil = siteInt(v.joinUntil, 1, VEIL_TIME), wrapUntil = siteInt(v.wrapUntil, 1, VEIL_TIME), openAt = siteInt(v.openAt, 1, VEIL_TIME),
            reassignDays = siteInt(v.reassignDays, 1, 7), drawn = v.drawn == true,
            salt = type(v.salt) == "string" and v.salt:match("^%x+$") and #v.salt <= 64 and v.salt or nil,
            -- the guild's key on the site, for the link to its page: one line, nothing that could open a colour or a link
            guildKey = type(v.guildKey) == "string" and #v.guildKey >= 1 and #v.guildKey <= 96 and not v.guildKey:find("[|%c]") and v.guildKey or nil,
            chimney = v.chimney ~= nil and siteInt(v.chimney, 0, 100) or nil,
            counts = { entrants = siteInt(c.entrants or 0, 0, 100000), wrapped = siteInt(c.wrapped or 0, 0, 100000),
                       pairs = siteInt(c.pairs or 0, 0, 100000), opened = siteInt(c.opened or 0, 0, 100000) },
        }
    end)
    if not ok then return nil end
    if type(v.entrants) == "table" then
        out.entrants = {}
        for i = 1, math.min(#v.entrants, Import.VEIL_LIST_MAX) do
            local r = v.entrants[i]
            local key = type(r) == "table" and veilKey(r.key)
            if key then out.entrants[#out.entrants + 1] = { key = key, wrapped = r.wrapped == true } end
        end
    end
    -- Who carries the pair of each guildmate without the companion: a whispered pair is believed only from them.
    if type(v.carriers) == "table" then
        out.carriers = {}
        for i = 1, math.min(#v.carriers, Import.VEIL_LIST_MAX) do
            local r = v.carriers[i]
            local giver, carrier = type(r) == "table" and veilKey(r.giver), type(r) == "table" and veilKey(r.carrier)
            if giver and carrier then out.carriers[giver] = carrier end
        end
    end
    -- The chain: only globes already opened, after `openAt`. No note. The host's globes name Frimm, not a character.
    if type(v.reveal) == "table" then
        out.reveal = {}
        for i = 1, math.min(#v.reveal, Import.VEIL_LIST_MAX) do
            local r = v.reveal[i]
            if type(r) == "table" and VEIL_SCENE[r.scene] and VEIL_RARITY[r.rarity] then
                local host = r.host == true
                local giver = host and type(r.giver) == "string" and #r.giver <= 32 and Import.Inert(r.giver) or veilKey(r.giver)
                local to = veilKey(r.to)
                if giver and giver ~= "" and to then
                    out.reveal[#out.reveal + 1] = { giver = giver, to = to, scene = r.scene, rarity = r.rarity, host = host or nil }
                end
            end
        end
    end
    return out
end

-- The guild's block first; before the site opens the event to everybody, a tester's own GOSVEIL1 carries it alone
-- (the guild's block says nothing yet, so no guildmate's addon shows the tab).
function Import:WinterVeil()
    local block = self:GuildBlock()
    local e = veilEvent(block and block.veil)
    if e then return e end
    local mine = self:VeilBlock()
    return mine and mine.event or nil
end

-- The inbox's GOSVEIL1: this person's own Winter Veil, written by their companion (the site's specs/119 §13) — whom
-- each of their characters drew and the globe they wrapped for them, the one they received, the pairs they carry sealed
-- for guildmates without the companion, and the account's Collection. Decoded once per string. Nil with none, a
-- damaged one, one of another guild or older than a week.
function Import:VeilBlock()
    local inbox = _G.GuildOSInbox
    if type(inbox) ~= "table" then return nil end
    for _, v in ipairs(inbox) do
        if type(v) == "string" and v:sub(1, #VEIL_PREFIX) == VEIL_PREFIX then
            if self._veilRaw ~= v then
                self._veilRaw, self._veilData = v, self:CleanVeil(unwrap(v:sub(#VEIL_PREFIX + 1), "GOSVEIL1"))
            end
            local data = self._veilData
            local mine = GetGuildInfo("player")
            if not data or not mine or mine == "" or not GuildOS.SameGuildName(data.guild, mine) then return nil end
            if not (data.at and GetServerTime() - data.at <= BLOCK_MAX_AGE) then return nil end
            return data
        end
    end
    return nil
end

-- A decoded GOSVEIL1 (v2) held to its shape (pure, for the harness). Nil when it is not one.
--   { guild, year, at, event?, played (the site holds my in-game participation; absent = false), mine = { { key, volunteer, gives = { { to, toClass?, scene?, note?, wrapped, extra?, hosted?,
--     rarity? } }, got? = { ready, ornament? } } }, relay = { { giver, seal } }, collection = { ornament } }
function Import:CleanVeil(data)
    if type(data) ~= "table" or data.fmt ~= "GOSVEIL1" or data.v ~= 2 or type(data.guild) ~= "string" then return nil end
    local ok, year, at = pcall(function() return siteInt(data.year, 2020, 2100), siteInt(data.at, 1, VEIL_TIME) end)
    if not ok then return nil end
    local out = { guild = data.guild, year = year, at = at, mine = {}, relay = {}, collection = {}, event = veilEvent(data.event),
                 played = data.played == true }
    for i = 1, math.min(type(data.mine) == "table" and #data.mine or 0, 10) do
        local m = data.mine[i]
        local key = type(m) == "table" and veilKey(m.key)
        if key then
            local gives = {}
            for j = 1, math.min(type(m.gives) == "table" and #m.gives or 0, 4) do
                local g = m.gives[j]
                local to = type(g) == "table" and veilKey(g.to)
                if to then
                    gives[#gives + 1] = {
                        to = to, toClass = type(g.toClass) == "string" and GuildOS.ClassColors and GuildOS.ClassColors[g.toClass] and g.toClass or nil,
                        scene = VEIL_SCENE[g.scene] and g.scene or nil, note = g.note ~= nil and veilNote(g.note) or nil,
                        wrapped = g.wrapped == true, extra = g.extra == true or nil, hosted = g.hosted == true or nil,
                        rarity = VEIL_RARITY[g.rarity] and g.rarity or nil,
                    }
                end
            end
            local got
            if type(m.got) == "table" then got = { ready = m.got.ready == true, ornament = veilOrnament(m.got.ornament) } end
            out.mine[#out.mine + 1] = { key = key, volunteer = m.volunteer == true, gives = gives, got = got }
        end
    end
    for i = 1, math.min(type(data.relay) == "table" and #data.relay or 0, 200) do
        local r = data.relay[i]
        local giver = type(r) == "table" and veilKey(r.giver)
        if giver and type(r.seal) == "string" and #r.seal <= 8192 and r.seal:match("^%x*$") and #r.seal % 2 == 0 then
            out.relay[#out.relay + 1] = { giver = giver, seal = r.seal }
        end
    end
    for i = 1, math.min(type(data.collection) == "table" and #data.collection or 0, 500) do
        local o = veilOrnament(data.collection[i])
        if o then out.collection[#out.collection + 1] = o end
    end
    return out
end

-- Text off the network, for a line of ours: nothing in it may open a colour, a link or a texture, and
-- one line stays one line.
function Import.Inert(text)
    return (text:gsub("|", ""):gsub("[\r\n]+", " "))
end

-- The block's feed, cleaned again.
function Import:FeedLines()
    local block = self:GuildBlock()
    local out = {}
    for _, item in ipairs(block and type(block.feed) == "table" and block.feed or {}) do
        if type(item) == "table" and type(item.id) == "string" and type(item.text) == "string" and item.text ~= "" then
            out[#out + 1] = {
                id = item.id,
                type = tostring(item.type),
                key = type(item.key) == "string" and GuildOS:LocalMemberKey(item.key) or nil,
                at = tonumber(item.at) or 0,
                text = Import.Inert(item.text),
            }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Which planned raid is happening now
--
-- The same window the website uses, from the same two numbers: two hours before
-- covers a raid that pulled early, eight hours after covers a long night and a
-- start that slipped. They are written on both sides on purpose — two halves that
-- disagree about which night is which produce an accusation on the wrong evening,
-- and nothing anywhere would show that it happened.
--
-- Keys, never names. Matching "Magtheridon" against "Magtheridon's Lair" across two
-- codebases is what lost every Magtheridon night the site ever received.
----------------------------------------------------------------------
--- Returns the raidId of the planned raid covering `when` in `instanceKey`, or nil. On retail
--- `difficulty` is the night's (14, 15, 16): a raid planned on another one is another lockout,
--- so when both say one they must agree (issue #182). A night of more than one place matches in
--- any of them (`instanceKeys`, the site's #556): Magtheridon's Lair after Gruul is the same raid.
local function goesTo(r, instanceKey)
    if r.instanceKey == instanceKey then return true end
    for _, k in ipairs(type(r.instanceKeys) == "table" and r.instanceKeys or {}) do
        if k == instanceKey then return true end
    end
    return false
end
function Import:RaidFor(instanceKey, when, difficulty, list)
    if type(instanceKey) ~= "string" or instanceKey == "" then return nil end
    when = tonumber(when) or 0
    difficulty = tonumber(difficulty)

    local best, bestGap
    for _, r in ipairs(list or (GuildOS.db and GuildOS.db.companionRaids) or {}) do
        if type(r) == "table" and goesTo(r, instanceKey) and not (difficulty and r.difficulty and r.difficulty ~= difficulty) then
            local gap = when - (r.startsAt or 0)
            if gap >= -MATCH_EARLY and gap <= MATCH_LATE then
                gap = math.abs(gap)
                -- Nearest start wins. Two candidates only happen when a guild books the
                -- same instance twice inside one window, and then the closer is the one.
                if not bestGap or gap < bestGap then
                    best, bestGap = r.raidId, gap
                end
            end
        end
    end
    return best
end

----------------------------------------------------------------------
-- Can this action run right now, and if not, why?
--
-- The Web panel greys a button and prints the reason beside it; the
-- slash command refuses with the same words. Both ask these, so a change
-- to the rule reaches the button and the command together instead of
-- drifting into two versions of the truth.
--
-- Each takes the roster to act on, the active one when none is given.
-- The leader and assistant reads go through Compat, past the client's
-- secret values (issue #400).
----------------------------------------------------------------------

--- The roster the Web panel and `/gos roster` act on (issue #400): the raid of the button (ButtonRaid, the nearest
--- while now is from an hour before its start to three hours after it) when there is one, else the roster kept,
--- pasted or the inbox's soonest, as before. Without this session's inbox the kept roster is the only candidate.
function Import:ActiveRoster(now)
    if self._webRaids then
        local raid = self:ButtonRaid(now)
        if raid then return raid end
    end
    return self:Current()
end

function Import:CanInvite(roster)
    roster = roster or self:ActiveRoster()
    if not roster then return false, L["Import a roster first."] end
    if not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then
        return false, L["The web companion is off. Turn it on with /gos web on."]
    end
    if not GuildOS.Compat.IsLeaderOrAssist() then return false, L["Only the group's leader or an assistant can invite."] end
    return true
end

-- Taking people out of the raid is the raid leader's alone: an assistant can invite and move,
-- the game lets only the leader remove (issue #292).
function Import:CanTrim(roster)
    roster = roster or self:ActiveRoster()
    if not roster then return false, L["Import a roster first."] end
    if not IsInRaid() and (GetNumGroupMembers() or 0) == 0 then return false, L["You are not in a group."] end
    if not GuildOS.Compat.IsGroupLeader() then return false, L["Only the raid leader can remove people from the raid."] end
    return true
end

-- The game moves nobody between groups in combat, so the button waits for it to end.
function Import:CanOrganize(roster)
    roster = roster or self:ActiveRoster()
    if not roster then return false, L["Import a roster first."] end
    if not IsInRaid() then return false, L["You need to be in a raid to organise groups."] end
    if not GuildOS.Compat.IsLeaderOrAssist() then
        return false, L["Only the raid leader or an assistant can organise groups."]
    end
    if GuildOS.Compat.InCombat() then return false, L["Not during combat."] end
    return true
end

-- Who a name stands for in the group: on retail the name with its realm, so a guildmate already
-- here from another connected realm is not invited again, and a namesake from another realm is
-- not taken for them (issue #182). Elsewhere the name.
local function presence(name, realm)
    if not GuildOS.Client.isRetail then return name end
    return GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, realm or name:match("^[^-]+%-(.+)$"))
end

--- Everyone on the live guild roster, by the name the site would send: the name they are kept by.
--- On retail the site sends a name it never confirmed without a realm, and that is a guildmate
--- only when one connected realm has it, kept as "Name-Realm": two namesakes are nobody to guess
--- between (issue #182).
---
--- And beside it, who the roster shows offline, by who they are (presence): the raid's invites pass
--- them over and name them (issue #400). Only a plain `false` is offline: a line that says nothing,
--- or says it secret, is somebody who may be online, and an invite to them costs nothing.
local function guildNames()
    local names, offline, retail = {}, {}, GuildOS.Client.isRetail
    for i = 1, (GetNumGuildMembers() or 0) do
        local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if full then
            local key
            if retail then
                local short = full:match("^([^-]+)") or full
                key = GuildOS:KeyOfRosterName(full)
                if names[short] == nil then names[short] = key else names[short] = false end
            else
                key = Import.PlainName(full)
                names[key] = key
            end
            if not GuildOS.Compat.IsSecret(online) and online == false and key then offline[key] = true end
        end
    end
    return names, offline
end

--- The people the site could not vouch for but the game can, by short name.
---
--- The site only calls a character confirmed once an ingested roster has carried the
--- same "Name-Realm". A guild that has never published has confirmed nobody, and on its
--- first night that is everyone who signed up — the leader pastes a roster and invites
--- one person. The roster is standing right here in the client, so ask it.
---
--- Only "unknown" is rescued. Somebody on standby, refused, or waiting for approval is
--- not missing a confirmation; they are missing a decision, and that one is not ours.
---
--- The panel and the invite button both read this, for the reason every predicate in
--- this file is shared: a button that says "the game has never seen this character"
--- beside somebody it just invited is two versions of the truth.
---
--- Keyed by the signup's name; the value is the name the guildmate is kept by, "Name-Realm"
--- on retail (issue #182). `guild` is guildNames()'s first answer when the caller has read it already.
function Import:Rescued(roster, guild)
    local out = {}
    for _, p in ipairs((roster and roster.signups) or {}) do
        if p.why == "unknown" and not p.invite and type(p.name) == "string" then
            guild = guild or guildNames()
            if guild[p.name] then out[p.name] = guild[p.name] end
        end
    end
    return out
end

----------------------------------------------------------------------
-- The plan against the group (issue #400)
--
-- What the invite, the groups and the Iniciar raide stepper all read, so
-- the button's label and what its click does cannot disagree. Read fresh
-- on every call, from the group as the client shows it now.
--
-- The one thing kept between clicks is who was just asked. The game says
-- nothing of an invite until it is answered, and without this a no-show
-- held the button on "invite the rest" for good, asked again on every
-- click. Somebody asked less than INVITE_WAIT ago is waiting: not asked
-- again, and holding a seat of the party they were asked into. After that
-- the next click asks them again, which is the retry.
----------------------------------------------------------------------
local PARTY_MAX = 5                -- a party holds five, its leader among them
local FIRST_WAVE = PARTY_MAX - 1   -- invited before the raid exists: what a party holds besides me
local RAID_GROUPS = 8              -- a raid's groups
local GROUP_MAX = 5                -- people in one raid group
local RAID_MAX = 40                -- GetRaidRosterInfo's indexes (MAX_RAID_MEMBERS)
local INVITE_WAIT = 60             -- seconds an invite is left to its answer: the game's invite popup lasts a minute

-- Who the invites asked, by who they are (presence), and when (GetTime). Session only.
Import._asked = {}

-- Everyone the roster plans, in its order: the site's members, then the guildmates the game vouches for
-- (Rescued), each once. { name = the name to invite, key = who they are (presence), group = 1..8 or nil }.
local function planned(roster, guild)
    local out, seen = {}, {}
    local function add(name, group)
        if type(name) ~= "string" or name == "" then return end
        local key = presence(name)
        if not key or seen[key] then return end
        seen[key] = true
        group = tonumber(group)
        out[#out + 1] = { name = name, key = key, group = (group and group >= 1 and group <= RAID_GROUPS) and group or nil }
    end
    for _, m in ipairs(roster.members or {}) do add(m.name, m.group) end
    local rescued = Import:Rescued(roster, guild)
    for _, s in ipairs(roster.signups or {}) do add(rescued[s.name], s.group) end
    return out
end

-- The planned person a name read off the group stands for, or nil. The name as presence keys it, first. On a
-- client with surnames nobody has yet read whether a raid unit or a raid roster line carries the surname
-- (issue #48, docs/forever): a name without a space is also tried with its hyphen as the space, the way the
-- game's folders write it, and a bare first name stands for the one planned person of that first name, never two.
-- The second answer is true for a bare first name two planned people share: it could be either of them.
local function planMatcher(list)
    local byKey, byFirst = {}, {}
    for _, p in ipairs(list) do
        byKey[p.key] = p
        local first = p.name:match("^(%S+) ")
        if first then byFirst[first] = (byFirst[first] == nil) and p or false end
    end
    local surnames = GuildOS.Client.has.surnames
    return function(key)
        if type(key) ~= "string" then return nil end
        if byKey[key] then return byKey[key] end
        if not surnames or key:find(" ", 1, true) then return nil end
        local spaced = key:gsub("%-", " ", 1)
        if byKey[spaced] then return byKey[spaced] end
        if key:find("-", 1, true) then return nil end
        local p = byFirst[key]
        return p or nil, p == false
    end
end

-- Who a group unit is, in the plan's terms. On a client with surnames the unit's second answer is the surname,
-- not a realm (UnitFullName answers the player so, issue #26): joined, as Compat.GroupRoster joins it.
local function unitKey(name, second)
    if GuildOS.Client.has.surnames then
        if type(second) == "string" and second ~= "" and not name:find(" ", 1, true) then name = name .. " " .. second end
        return name
    end
    return presence(name, second)
end

-- The group as it is, against the plan: how many we are, whether it is a raid, how many of the plan are here, who
-- is left to invite (the planned entries), who was asked moments ago and is waiting (names), and who the guild
-- roster shows offline (names). Never me, nobody already here, no offline guildmate; somebody outside the guild
-- cannot be known offline, and is invited.
local function survey(roster)
    local Compat = GuildOS.Compat
    local guild, offline = guildNames()
    local list = planned(roster, guild)
    local match = planMatcher(list)
    local inRaid = IsInRaid() and true or false
    local n = GetNumGroupMembers() or 0
    local here = {}
    local me = Compat.PlayerName()
    if not Compat.IsSecret(me) and type(me) == "string" then
        local p = match(presence(me))
        if p then here[p] = true end
    end
    for i = 1, n do
        local name, second = Compat.UnitIdentity((inRaid and "raid" or "party") .. i)
        if type(name) == "string" and name ~= "" then
            local p = match(unitKey(name, second))
            if p then here[p] = true end
        end
    end
    local asked, now = Import._asked, GetTime()
    local s = { n = n, inRaid = inRaid, here = 0, invite = {}, waiting = {}, offline = {}, match = match }
    for _, p in ipairs(list) do
        local at = asked[p.key]
        if at and now - at >= INVITE_WAIT then asked[p.key], at = nil, nil end
        if here[p] then
            s.here = s.here + 1
            asked[p.key] = nil
        elseif offline[p.key] then
            s.offline[#s.offline + 1] = p.name
        elseif at then
            s.waiting[#s.waiting + 1] = p.name
        else
            s.invite[#s.invite + 1] = p
        end
    end
    return s
end

-- The seats an invite may fill now: everyone left in a raid; alone, the first wave; in a party, its free seats.
-- Who is waiting on an answer holds a seat already.
local function inviteRoom(s)
    if s.inRaid then return #s.invite end
    local free = (s.n <= 1) and FIRST_WAVE or (PARTY_MAX - s.n)
    return math.max(0, free - #s.waiting)
end

--- Invite who the plan still needs, as many as the group has room for (issue #400): four alone, a party's free
--- seats, everyone once it is a raid. Never me, nobody already here, nobody asked less than a minute ago, and no
--- guildmate the guild roster shows offline (returned, to be named). The Iniciar raide stepper's invite steps are
--- this, on the raid of its button. Returns (invited, here, err, offline): `here` is how many of the plan are
--- already in the group.
function Import:InviteAll(roster)
    roster = roster or self:ActiveRoster()
    local allowed, reason = self:CanInvite(roster)
    if not allowed then return nil, nil, reason end
    local s = survey(roster)
    local room = inviteRoom(s)
    if room == 0 and #s.invite > 0 then
        local why = s.n >= PARTY_MAX and L["The party is full. Turn it into a raid first."] or L["Waiting for the invited to answer."]
        return nil, nil, why, s.offline
    end
    -- Compat knows which invite the client has: WoW: Forever only has C_PartyInfo's (issue #43). Each person is
    -- asked once a minute at most: a second invite to a name already asked is an error in their chat.
    local now, invited = GetTime(), 0
    for i = 1, math.min(room, #s.invite) do
        local p = s.invite[i]
        GuildOS.Compat.InviteUnit(inviteName(p.name))
        self._asked[p.key] = now
        invited = invited + 1
    end
    return invited, s.here, nil, s.offline
end

--- The line that names who was left out for being offline, or nil with nobody: names off the network, made inert.
function Import.OfflineLine(offline)
    if type(offline) ~= "table" or #offline == 0 then return nil end
    local names = {}
    for i, name in ipairs(offline) do names[i] = Import.Inert(name) end
    return string.format(L["Offline, not invited: %s"], table.concat(names, ", "))
end

--- Who is in the group and not in the plan (issue #292): a pug who joined, somebody who left the raid
--- on the site, somebody on its waitlist. Never the leader, and never somebody the site has on the
--- bench (`why = "bench"`): the raid leader benched them on purpose and may want them standing by in
--- the raid — taking them out is the raid leader's own hand, not this button's. Returns names, the
--- way the group shows them, and beside them the unit each one is, which is what removal asks for.
---
--- Read the way the Iniciar raide stepper reads the group (planned, planMatcher, unitKey; issue #400), so
--- the two never disagree: on WoW: Forever a unit that answers its surname apart, or a first name alone
--- that one planned person has, is that person, and is not taken out of a raid the button calls ready. A
--- bare first name two planned people share could be either, so it stays. Neither am I, by unit, whatever
--- shape my name comes back in.
function Import:OutsideThePlan(roster)
    roster = roster or self:ActiveRoster()
    if not roster then return {} end
    local Compat = GuildOS.Compat
    local list, seen = planned(roster), {}
    for _, p in ipairs(list) do seen[p.key] = true end
    for _, s in ipairs(roster.signups or {}) do
        local key = s.why == "bench" and type(s.name) == "string" and s.name ~= "" and presence(s.name)
        if key and not seen[key] then
            seen[key] = true
            list[#list + 1] = { name = s.name, key = key }
        end
    end
    local match = planMatcher(list)
    local me = Compat.PlayerName()
    me = (type(me) == "string" and not Compat.IsSecret(me)) and presence(me) or nil
    local inRaid, n = IsInRaid(), GetNumGroupMembers() or 0
    local out, units = {}, {}
    -- A party's units are the others; a raid's are all of us.
    for i = 1, inRaid and n or (n - 1) do
        local unit = (inRaid and "raid" or "party") .. i
        local name, second = Compat.UnitIdentity(unit)
        if type(name) == "string" and name ~= "" and not Compat.IsPlayer(unit) then
            local key = unitKey(name, second)
            local p, either = match(key)
            if not p and not either and key ~= me then
                local shown = GuildOS.Client.has.surnames and key or name
                out[#out + 1] = shown
                units[shown] = unit
            end
        end
    end
    table.sort(out)
    return out, units
end

--- Ask, naming them, then take out of the group whoever is outside the plan (issue #292): what the Web
--- panel's button and `/gos roster trim` both call. Nothing to take out, or nobody allowed to, is said.
function Import:AskTrim()
    local allowed, reason = self:CanTrim()
    if not allowed then return GuildOS:Print(reason) end
    local out = self:OutsideThePlan()
    if #out == 0 then return GuildOS:Print(L["Everyone in the group is in the plan."]) end
    if not GuildOS.Dialogs["GUILDOS_TRIM_PLAN"] then
        GuildOS.Dialogs["GUILDOS_TRIM_PLAN"] = {
            text = "%s", button1 = L["Remove"], button2 = L["Cancel"],
            OnAccept = function()
                local n, err = Import:TrimToPlan()
                GuildOS:Print(err or string.format(L["Removed %d from the group."], n))
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    GuildOS:ShowDialog("GUILDOS_TRIM_PLAN", string.format(L["Remove %d who are not in the plan?\n%s"], #out, table.concat(out, ", ")))
end

--- Take out of the group whoever is outside the plan. The panel asks first, naming them; this only
--- does it. Returns (removed, err).
function Import:TrimToPlan()
    local allowed, reason = self:CanTrim()
    if not allowed then return nil, reason end
    -- By unit, as the group knows them: a name would need its realm put back together by hand.
    local out, units = self:OutsideThePlan()
    for _, name in ipairs(out) do GuildOS.Compat.UninviteUnit(units[name]) end
    return #out, nil
end

----------------------------------------------------------------------
-- Groups
----------------------------------------------------------------------

-- The raid as the game lists it, against the plan: each line it lets us read, with its index, its group and the
-- group the site planned for that person (nil for somebody outside the plan or planned without one), and how many
-- each group holds. A line the client keeps secret is never read (issue #182), but still fills a seat of its group
-- when the group itself reads. Two lines that stand for one planned person (two first names alike, read without
-- the surname) are neither known to be them: neither has a planned group, so neither moves.
local function raidLayout(match)
    local Compat = GuildOS.Compat
    local people, count, claimed = {}, {}, {}
    for g = 1, RAID_GROUPS do count[g] = 0 end
    for i = 1, RAID_MAX do
        local name, _, subgroup = GetRaidRosterInfo(i)
        local hidden = Compat.IsSecret(name)
        local group = not Compat.IsSecret(subgroup) and tonumber(subgroup) or nil
        if group and count[group] and (hidden or name ~= nil) then count[group] = count[group] + 1 end
        if not hidden and type(name) == "string" and name ~= "" and group and count[group] then
            local p = match(presence(Import.PlainName(name)))
            local line = { index = i, group = group, want = p and p.group or nil }
            if p then
                local first = claimed[p]
                if first == nil then
                    claimed[p] = line
                else
                    line.want = nil
                    if first then first.want = nil end
                    claimed[p] = false
                end
            end
            people[#people + 1] = line
        end
    end
    return people, count
end

-- How many of the plan's people the moves put in their group.
local function placedBy(moves)
    local n = 0
    for _, m in ipairs(moves) do n = n + m.placed end
    return n
end

-- The moves that put the plan's people into their groups, worked out on the layout (which it changes as it goes).
-- Only somebody in the wrong place moves: setting a group already right still costs a server call. Into a group
-- with a seat, a move; into a full one, a swap with somebody there who does not belong there, the one whose own
-- planned group is the mover's first (both land), then somebody with no planned group, then anybody planned
-- elsewhere. Somebody outside the plan only ever moves as a swap's other half. A group full of people who belong
-- there takes nobody more, and neither does a full group on a client that cannot swap (so the stepper never offers
-- an arrange that would move nobody). Each move: { index, group } or { index, swap = other index }, and how many
-- it places.
local function planMoves(people, count)
    local moves, canSwap = {}, GuildOS.Compat.CanSwapRaidSubgroup()
    for _, p in ipairs(people) do
        local target = p.want
        if target and p.group ~= target then
            if count[target] < GROUP_MAX then
                count[p.group] = count[p.group] - 1
                count[target] = count[target] + 1
                p.group = target
                moves[#moves + 1] = { index = p.index, group = target, placed = 1 }
            elseif canSwap then
                local best, bestRank
                for _, q in ipairs(people) do
                    if q.group == target and q.want ~= target then
                        local rank = (q.want == p.group and 1) or (q.want == nil and 2) or 3
                        if not bestRank or rank < bestRank then best, bestRank = q, rank end
                    end
                end
                if best then
                    best.group, p.group = p.group, target
                    moves[#moves + 1] = { index = p.index, swap = best.index, placed = bestRank == 1 and 2 or 1 }
                end
            end
        end
    end
    return moves
end

--- Move the raid's people into the groups the site planned (issue #400): a move where the group has a seat, a
--- swap where it is full, never leaving somebody out of a group they fit into. Only in a raid, as its leader or an
--- assistant, out of combat (CanOrganize). Returns (placed, err): how many of the plan it put in their group.
function Import:OrganizeGroups(roster)
    roster = roster or self:ActiveRoster()
    local allowed, reason = self:CanOrganize(roster)
    if not allowed then return nil, reason end
    local Compat = GuildOS.Compat
    local placed = 0
    for _, m in ipairs(planMoves(raidLayout(planMatcher(planned(roster))))) do
        local ok
        if m.swap then ok = Compat.SwapRaidSubgroup(m.index, m.swap) else ok = Compat.SetRaidSubgroup(m.index, m.group) end
        if ok then placed = placed + m.placed end
    end
    return placed, nil
end

----------------------------------------------------------------------
-- Iniciar raide (issue #400; specs/115 in guildos-web)
--
-- One button that walks the raid's leader through the night, one click a
-- step, since on WoW: Forever an invite goes out from a click only:
-- invite the first four, turn the party into a raid, invite the rest,
-- arrange the groups. Next decides the step from the group as it is every
-- time it is asked, never from a step it remembers: a leader already in a
-- raid of ten goes straight to the rest, or to the groups. Its label says
-- what the next click does. The owner's prompt, the Now tab and the Web
-- tab show it (UI/WebPanel.lua); Click is what their click and
-- `/gos raid start` call.
----------------------------------------------------------------------
local RaidStart = {}
GuildOS.RaidStart = RaidStart

local function blocked(reason, count)
    return { kind = "blocked", count = count or 0, reason = reason }
end

--- The next step for `roster` (the raid of the button): { kind, count, reason, offline, waiting, label }.
--- kind: "invite4" (alone or in a party the plan fits: count = who that click invites), "convert" (a party the
--- plan outgrows: count = who is left to invite once it is a raid), "inviteRest" (a raid: count = who is left),
--- "arrange" (nobody left to invite, count = how many the click can put in their group), "done", or "blocked"
--- with the reason (the player's language): no roster, the companion off, in a group and neither its leader nor an
--- assistant, in combat with groups to arrange, or the party's seats all held by invites awaiting their answer.
--- offline: the guildmates passed over for being offline; waiting: who was asked less than a minute ago. In a raid
--- the waiting never hold the button: it goes on to the groups, and asks them again once their minute is out.
function RaidStart:Next(roster)
    if type(roster) ~= "table" then return self:Labelled(blocked(L["No raid from the site starts around this time."])) end
    local ok, why = Import:CanInvite(roster)
    if not ok then return self:Labelled(blocked(why)) end
    local s = survey(roster)
    local left, waiting, step = #s.invite, #s.waiting, nil
    if s.inRaid then
        if left > 0 then
            step = { kind = "inviteRest", count = left }
        else
            local placeable = placedBy(planMoves(raidLayout(s.match)))
            if placeable > 0 then
                step = GuildOS.Compat.InCombat() and blocked(L["Not during combat."], placeable)
                    or { kind = "arrange", count = placeable }
            end
        end
    elseif s.n > 1 and s.n + left + waiting > PARTY_MAX then
        -- More than a party holds: everyone in a party the plan fits never converts.
        step = { kind = "convert", count = left }
    elseif left > 0 and inviteRoom(s) > 0 then
        step = { kind = "invite4", count = math.min(inviteRoom(s), left) }
    elseif waiting > 0 then
        step = blocked(L["Waiting for the invited to answer."], waiting)
    end
    step = step or { kind = "done", count = 0 }
    step.offline, step.waiting = s.offline, s.waiting
    return self:Labelled(step)
end

-- The step with its label.
function RaidStart:Labelled(step)
    step.label = self:Label(step)
    return step
end

--- What the button says for a step: what the next click does, and its count.
function RaidStart:Label(step)
    local kind, n = step and step.kind, (step and tonumber(step.count)) or 0
    if kind == "invite4" then return string.format(L["Invite (%d)"], n) end
    if kind == "convert" then return string.format(L["Convert to raid (%d to invite)"], n) end
    if kind == "inviteRest" then return string.format(L["Invite the rest (%d)"], n) end
    if kind == "arrange" then return string.format(L["Arrange groups (%d out of place)"], n) end
    if kind == "done" then return L["Raid ready"] end
    return L["Start raid"]
end

--- The click: does what Next says, from a click only (an invite needs one on WoW: Forever). Converting does only
--- that, and the rest are invited by the next click, once the raid exists. Returns what it did:
--- { kind, count = invited or placed (left to invite after a convert), here, converted, reason, offline }.
function RaidStart:Run(roster)
    local step = self:Next(roster)
    local out = { kind = step.kind, count = 0, reason = step.reason, offline = step.offline }
    if step.kind == "invite4" or step.kind == "inviteRest" then
        local invited, here, err = Import:InviteAll(roster)
        out.count, out.here, out.reason = invited or 0, here or 0, err
    elseif step.kind == "convert" then
        out.converted = GuildOS.Compat.ConvertToRaid()
        out.count = step.count
    elseif step.kind == "arrange" then
        local placed, err = Import:OrganizeGroups(roster)
        out.count, out.reason = placed or 0, err
    end
    return out
end

--- The lines a click's result prints: what happened, and who was left out for being offline (nil with nobody).
function RaidStart:Say(result)
    local kind = result.kind
    local line
    if result.reason then
        line = result.reason
    elseif kind == "invite4" or kind == "inviteRest" then
        line = string.format(L["Invited %d, already here %d."], result.count or 0, result.here or 0)
    elseif kind == "convert" then
        line = result.converted and L["The group is a raid now. Click again to invite the rest."]
            or L["The game did not turn the group into a raid."]
    elseif kind == "arrange" then
        line = string.format(L["Moved %d into their groups."], result.count or 0)
    else
        line = L["Raid ready"]
    end
    return line, Import.OfflineLine(result.offline)
end

--- One click of the button, wherever it is: the owner's prompt, the Now and Web tabs, `/gos raid start`. Does the
--- step (Run), says it in chat (`titled`: after the raid's name), and has every button on screen read the group
--- again. Returns Run's result.
function RaidStart:Click(roster, titled)
    local result = self:Run(roster)
    local line, off = self:Say(result)
    -- Typed, nothing on screen says which raid it acted on: the line starts with its name.
    if line and titled and type(roster) == "table" then
        local title = roster.title
        if type(title) ~= "string" or title == "" then title = roster.instance or "?" end
        line = Import.Inert(tostring(title)) .. " · " .. line
    end
    if line then GuildOS:Print(line) end
    if off then GuildOS:Print(off) end
    if GuildOS.RefreshRaidSteppers then GuildOS:RefreshRaidSteppers() end
    return result
end

-- The button passes over a guildmate the guild roster shows offline, and the client's copy of that roster is only as
-- fresh as its last update: somebody who logged in a minute ago would be skipped. While a button is on screen it
-- asks the server for the roster again, at most this often (seconds); the server's answer repaints the buttons.
local ROSTER_ASK_GAP = 30

--- Asks the server for a fresh guild roster (Compat.GuildRoster), at most once every ROSTER_ASK_GAP seconds; the
--- prompt and the tabs call it while their button shows. Returns whether it asked.
function RaidStart:AskGuildRoster()
    if not IsInGuild() then return false end
    local now = GetTime()
    if self._rosterAskedAt and now - self._rosterAskedAt < ROSTER_ASK_GAP then return false end
    self._rosterAskedAt = now
    GuildOS.Compat.GuildRoster()
    return true
end

----------------------------------------------------------------------
-- The owner's prompt (issue #400; specs/115 in guildos-web)
--
-- The site sends who owns each raid (`owners`), and the owner, and only
-- the owner, is asked shortly before it starts: at login or /reload from
-- half an hour before the start to an hour after it, and, already in the
-- game, a quarter of an hour before it. Once per raid and start, kept in
-- the guild's SavedVariables, so a /reload, another login or another
-- character of the owner's asks nothing again; a raid moved to another
-- time asks again. Only the inbox's raids are asked about: the owner's
-- prompt comes from the site, not from a roster pasted by hand.
--
-- This decides; GuildOS:ShowRaidPrompt (UI/WebPanel.lua) shows it.
----------------------------------------------------------------------
local PROMPT_BEFORE = 30 * 60    -- seconds before the start from which a login asks
local PROMPT_AFTER = 60 * 60     -- seconds after the start until which a login still asks
local PROMPT_AHEAD = 15 * 60     -- seconds before the start at which a session already in the game is asked
local PROMPT_KEEP = 7 * 86400    -- seconds a prompt shown is remembered: a week, then forgotten

-- What a prompt is remembered by: the raid and its start (spec 115: "uma vez por raide e por horário"). Nil for a
-- roster without an id or a start, which is never asked about.
local function promptKey(roster)
    local id, at = type(roster) == "table" and roster.raidId, type(roster) == "table" and tonumber(roster.startsAt)
    if (type(id) ~= "string" and type(id) ~= "number") or id == "" or not at or at <= 0 then return nil end
    return tostring(id) .. ":" .. tostring(at)
end
RaidStart.PromptKey = promptKey

--- The prompts shown, in the guild's SavedVariables: { [raidId .. ":" .. startsAt] = when it was shown }. Read with
--- what is over a week old dropped. Nil before the guild's db exists.
function RaidStart:PromptedSet(now)
    local db = GuildOS.db
    if type(db) ~= "table" then return nil end
    if type(db.raidPrompted) ~= "table" then db.raidPrompted = {} end
    local set = db.raidPrompted
    now = now or GetServerTime()
    for key, at in pairs(set) do
        if type(at) ~= "number" or now - at > PROMPT_KEEP then set[key] = nil end
    end
    return set
end

--- The raids of this session's inbox this character owns (IsMine), of the guild it is in (OfThisGuild), each with an
--- id and a start.
function RaidStart:Owned()
    local out = {}
    for _, roster in ipairs(Import._webRaids or {}) do
        if promptKey(roster) and Import.OfThisGuild(roster) and Import:IsMine(roster) then out[#out + 1] = roster end
    end
    return out
end

--- Shows the prompt for `roster` and remembers it was shown (before showing it: a prompt that fails to show is not
--- tried again at every login). False when there is nothing to show it with.
function RaidStart:Prompt(roster, now)
    local key, set = promptKey(roster), self:PromptedSet(now)
    if not (key and set and GuildOS.ShowRaidPrompt) then return false end
    set[key] = now or GetServerTime()
    -- Never in combat, one popup at a time (audit B21): it waits for combat to end.
    GuildOS:ShowWhenClear("raidprompt", function() return GuildOS:ShowRaidPrompt(roster) end)
    return true
end

--- At login or /reload, once the inbox is read (Core's InitModules): the prompt for the owned raid from half an hour
--- before its start to an hour after it, the nearest if two are, unless it was shown already; and, for each owned raid
--- still more than a quarter of an hour away, a timer that asks then. Returns the roster prompted, or nil.
function RaidStart:OnLogin(now)
    now = now or GetServerTime()
    self._loginPrompt = nil
    local set = self:PromptedSet(now)
    if not set then return nil end
    local best, bestGap
    for _, roster in ipairs(self:Owned()) do
        local gap = roster.startsAt - now
        if gap > PROMPT_AHEAD then self:Arm(roster, gap - PROMPT_AHEAD) end
        if gap <= PROMPT_BEFORE and gap >= -PROMPT_AFTER and not set[promptKey(roster)]
           and (not best or math.abs(gap) < bestGap) then
            best, bestGap = roster, math.abs(gap)
        end
    end
    if best and self:Prompt(best, now) then
        self._loginPrompt = best
        return best
    end
    return nil
end

--- Whether this login's prompt was shown. The login digest gives way to it (Digest:ShowOnLogin): one popup at a time.
function RaidStart:PromptedAtLogin()
    return self._loginPrompt ~= nil
end

local PROMPT_RETRY = 2 * 60      -- seconds a raid's prompt waits while another raid's prompt is still being worked
local PROMPT_LATER = 10 * 60     -- seconds after Later before the prompt asks again (audit B18)

-- The timer that calls Due for `roster` after `delay` seconds.
local function schedule(roster, delay)
    GuildOS.Compat.After(delay, function()
        GuildOS:SafeCall(function() RaidStart:Due(roster) end)
    end)
end

--- The quarter-hour timer of an owned raid, armed once a session. It only shows the prompt: nothing is invited from a
--- timer (WoW: Forever drops an invite that is not a click's), the prompt's button does that.
function RaidStart:Arm(roster, delay)
    local key = promptKey(roster)
    if not key then return end
    self._armed = self._armed or {}
    if self._armed[key] then return end
    self._armed[key] = true
    schedule(roster, delay)
end

--- A timer's moment for `roster`: its prompt, unless it was shown already (at login, or on another character of the
--- owner's) or the roster is no longer this character's to start. While the prompt is up for another raid whose step
--- is not done, that one is not taken from under the leader's hand: this one asks again in PROMPT_RETRY seconds.
--- Returns whether it was shown.
function RaidStart:Due(roster, now)
    now = now or GetServerTime()
    local key, set = promptKey(roster), self:PromptedSet(now)
    if not (key and set) or set[key] then return false end
    -- Past the login's window (an hour after the start), a retry that waited all that time asks nothing: late, the
    -- prompt would be news of a raid long under way.
    if tonumber(roster.startsAt) + PROMPT_AFTER < now then return false end
    if not (Import.OfThisGuild(roster) and Import:IsMine(roster)) then return false end
    local showing = GuildOS.RaidPromptShowing and GuildOS:RaidPromptShowing()
    if showing and showing ~= roster and self:Next(Import:Freshest(showing)).kind ~= "done" then
        schedule(roster, PROMPT_RETRY)
        return false
    end
    return self:Prompt(roster, now)
end

--- The prompt for `roster` was closed with Later or its close button, not by Raid ready: the login's digest, which
--- gave way to it (Digest:ShowOnLogin), has its turn now, or at its own time if that has not come. Closed by Raid
--- ready, the raid is under way and the digest waits for the next login.
--- `later`: it was Later (audit B18), which asks again in PROMPT_LATER seconds, until an hour after the start (Due);
--- the close button puts it off for good, as before.
function RaidStart:PromptDismissed(roster, later)
    local key = later and promptKey(roster)
    local set = key and self:PromptedSet()
    if set then
        set[key] = nil
        schedule(roster, PROMPT_LATER)
    end
    if not (self._loginPrompt and self._loginPrompt == roster) then return end
    self._loginPrompt = nil
    local D = GuildOS.Digest
    if D and D.deferred then
        D.deferred = nil
        D:ShowOnLogin()
    end
end

----------------------------------------------------------------------
-- Read the companion's drop box once the database exists.
--
-- Read in two halves (#146). The roster as soon as the guild's db is known
-- (Core's InitModules): at PLAYER_LOGIN, where it used to be read, a db not
-- resolved yet read the companion as off, and the raid tracker stamps
-- tonight's raid from it when the session starts. The calendar once the rank
-- is known (Core's officer start-up): only an officer's client publishes the
-- site's raids, and a rank not loaded yet read an officer as not one, so the
-- raids stayed off the calendar for the whole session.
--
-- Errors are swallowed by SafeCall. A roster that fails to arrive must
-- never be the reason someone cannot log in.
----------------------------------------------------------------------
function Import:ReadInbox()
    GuildOS:SafeCall(function()
        local ok, count = Import:ConsumeInbox()
        if ok then
            GuildOS:Print(string.format(L["Roster from the website: %d signed up."], count))
        end
    end)
end

local INBOX_TRUST = 86400   -- the companion rewrites the inbox every hour: a day older is one that stopped

function Import:CalendarFromInbox()
    local Cal = GuildOS.Calendar
    if not Cal then return end
    -- When the site gave these, so an old inbox takes back nobody's answer.
    local answeredAt = self:Ack()
    local raids = self._webRaids
    if raids and Cal.UpsertWebRaid then
        for _, roster in ipairs(raids) do
            GuildOS:SafeCall(function() Cal:UpsertWebRaid(roster, answeredAt) end)
        end
    end
    -- The site's events that are not raids (#652): with or without a raid in the inbox. One the site no longer
    -- sends leaves the calendar only where the inbox can tell (SiteEventsInfo, GameCalendar.SiteEventGone).
    local events = self:SiteEvents()
    if events and Cal.UpsertSiteEvent then
        for _, ev in ipairs(events) do
            GuildOS:SafeCall(function() Cal:UpsertSiteEvent(ev, answeredAt) end)
        end
        local info = self:SiteEventsInfo(events)
        if info and Cal.DropSiteEvents then
            GuildOS:SafeCall(function() Cal:DropSiteEvents(info) end)
        end
    end
end

--- What the inbox says of the site's events, for taking one the site no longer sends off the calendar (#652):
--- { ids, count, at, last }, as InboxInfo says it of the raids. Nil when the block says nothing of events, the
--- companion is off, there is no ack or the inbox is a day old: a stopped companion's leftover never takes an
--- event away.
function Import:SiteEventsInfo(events)
    events = events or self:SiteEvents()
    if type(events) ~= "table" or not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then return nil end
    local at = self:Ack()
    if not at then return nil end
    local now = GetServerTime()
    at = math.min(at, now)
    if now - at > INBOX_TRUST then return nil end
    local ids, last = {}, nil
    for _, ev in ipairs(events) do
        ids[ev.id] = true
        if not last or ev.startsAt > last then last = ev.startsAt end
    end
    return { ids = ids, count = #events, at = at, last = last }
end

--- The site raids the inbox holds, by id, how many, and when the site gave them (its ack, held to now):
--- { ids = { [raidId] = true }, count = n, at = epoch, last = latest startsAt }. Nil when no inbox with a raid was read this
--- session, the companion is off, or the inbox is a day old: the game's calendar infers "no longer on the
--- website" from it, and a stopped companion's leftover must never offer to take a live raid out of the
--- game (guildos-web specs/075, #263).
function Import:InboxInfo()
    local raids = self._webRaids
    if type(raids) ~= "table" or not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then return nil end
    local at = self:Ack()
    if not at then return nil end
    local now = GetServerTime()
    at = math.min(at, now)
    if now - at > INBOX_TRUST then return nil end
    local ids, last = {}, nil
    for _, roster in ipairs(raids) do
        if roster.raidId ~= nil then ids[tostring(roster.raidId)] = true end
        local when = tonumber(roster.startsAt)
        if when and (not last or when > last) then last = when end
    end
    return { ids = ids, count = #raids, at = at, last = last }
end
