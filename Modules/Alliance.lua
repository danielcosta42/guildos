----------------------------------------------------------------------
-- Guild OS - The alliance, what the addon keeps of it (specs/salao/alianca.md, audit #448)
--
-- The alliance lives on guildos.me (alianca.md §3.1). In the game it is:
--   * the alliance code the GreenWall way (Modules/AllianceLink.lua): GOS=TAG:key, the hidden
--     channel, the shared /g mirrored with the speaker's guild tag;
--   * the alliance room (Modules/AllianceChat.lua), on that same channel;
--   * what the site sends through the companion: the alliance code itself (GOSGILD1 `alliance`, which
--     wins over a pasted one: AllianceLink), the shared bans (GOSGILD1, Modules/BanList.lua), and the
--     directory and the open raids (GOSALLY1, CompanionImport:AllianceBlock), in memory only.
--
-- The ambassador pact that used to live here (invites, the join code, ambassadors, the whisper ops,
-- the bridge, the allied data sync, the alliance board and LFG pool) is gone (§3.4). This file is
-- the read-only face the rest of the addon asks: which alliance, which guilds, who is on now, which
-- guild a character is from, who crafts an item. It decides nothing and sends nothing.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Alliance = {}
GuildOS.Alliance = Alliance
local L = GuildOS.L

Alliance.TAG_MAX        = 12
-- Bytes of a guild's name: the game's 24 letters, in UTF-8 (a Cyrillic or accented name cut at 24 bytes was another
-- guild to every comparison, #449).
Alliance.GUILD_NAME_MAX = 48
-- Seconds a speaker heard on the alliance channel counts as online now.
Alliance.ONLINE_FOR     = 15 * 60
-- What `/gos ally create|invite|leave` (and the pact's other verbs) answer now.
Alliance.MOVED          = L["Alliances now live on guildos.me."]

local function shortName(name)
    local s = tostring(name or "")
    return (Ambiguate and Ambiguate(s, "short")) or s:match("^([^-]+)") or s
end

local function now() return (GetServerTime and GetServerTime()) or time() end

-- A spec as the reader says it: on retail by its id, in this client's language, the sender's tree
-- name otherwise (SpecChecker:SpecName; issue #184).
local function specLabel(spec)
    if GuildOS.SpecChecker then return GuildOS.SpecChecker:SpecName(spec) end
    return spec.tree
end

----------------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------------
-- "brcore" -> "BRCORE". "" when nothing usable is left.
function Alliance.NormalizeTag(tag)
    local s = tostring(tag or ""):upper():gsub("[^A-Z0-9]", "")
    if #s > Alliance.TAG_MAX then
        s = s:sub(1, Alliance.TAG_MAX)
    end
    return s
end

-- djb2: the same number on every client, so a guild is the same colour on everyone's screen.
function Alliance.Hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483648
    end
    return h
end

-- A guild's identity colour. WoW draws no other guild's tabard, so colour is the identity we can
-- give them: the hue from the hash, saturation and value fixed and low, the red band skipped (red is
-- error and ban everywhere else in this UI).
local function hsvToRgb(h, s, v)
    local c = v * s
    local hp = h / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local r, g, b
    if hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    local m = v - c
    return r + m, g + m, b + m
end

Alliance.HUE_MIN  = 20
Alliance.HUE_SPAN = 320

function Alliance.GuildColor(guildName)
    if type(guildName) ~= "string" or guildName == "" then
        local c = GuildOS.Colors.label   -- a neutral label colour for "guild unknown"
        return c.r, c.g, c.b
    end
    local hue = Alliance.HUE_MIN + (Alliance.Hash(guildName) % Alliance.HUE_SPAN)
    return hsvToRgb(hue, 0.42, 0.86)
end

function Alliance.GuildColorHex(guildName)
    local r, g, b = Alliance.GuildColor(guildName)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

----------------------------------------------------------------------
-- The alliance in force: the code's (Modules/AllianceLink.lua), or nil
----------------------------------------------------------------------
function Alliance:Get()
    local link = GuildOS.AllianceLink
    return (link and GuildOS.db and link:Pact()) or nil
end

function Alliance:MyGuildName()
    local name = GetGuildInfo("player")
    if not name or name == "" then
        return nil
    end
    return name
end

function Alliance:Name()
    local pact = self:Get()
    return pact and (pact.name or pact.tag) or nil
end

function Alliance:IsMemberGuild(guildName)
    local pact = self:Get()
    if not pact or type(guildName) ~= "string" then return false end
    if pact.guilds and pact.guilds[guildName] then return true end
    for _, name in ipairs(self:SiteGuildNames()) do
        if GuildOS.SameGuildName(name, guildName) then return true end
    end
    return false
end

-- Whether the alliance in force is managed on guildos.me (its code came in the companion's block).
function Alliance:FromSite()
    local pact = self:Get()
    return pact ~= nil and pact.site == true
end

-- A guild an officer blocked: its lines on the alliance channel (the shared /g and the room) are not shown
-- on this account. Nothing is sent: the other guild is never told. Kept in the guild's db, through any key change.
function Alliance:IsBlocked(guildName)
    local pact = self:Get()
    if not (pact and pact.blocked and type(guildName) == "string") then return false end
    if pact.blocked[guildName] == true then return true end
    -- Capitals aside, as the site compares guilds: an officer types the name as they read it (#449).
    for name, on in pairs(pact.blocked) do
        if on == true and GuildOS.SameGuildName(name, guildName) then return true end
    end
    return false
end

function Alliance:Blocked()
    local out = {}
    local pact = self:Get()
    for name, on in pairs(pact and pact.blocked or {}) do
        if on == true then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function Alliance:Block(guildName)
    if not GuildOS:IsOfficer() then return false, L["Only officers can do that."] end
    local pact = self:Get()
    if not pact then return false, L["This guild is not in an alliance yet."] end
    local clean = GuildOS:SanitizeUserText(guildName, Alliance.GUILD_NAME_MAX)
    if clean == "" then return false, L["Name the guild to block."] end
    if clean == self:MyGuildName() then return false, L["Name the guild to block."] end
    pact.blocked[clean] = true
    self._dirOf = nil
    if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
    return true
end

function Alliance:Unblock(guildName)
    if not GuildOS:IsOfficer() then return false, L["Only officers can do that."] end
    local pact = self:Get()
    if not pact then return false, L["This guild is not in an alliance yet."] end
    pact.blocked[GuildOS:SanitizeUserText(guildName, Alliance.GUILD_NAME_MAX)] = nil
    self._dirOf = nil
    if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
    return true
end

-- An officer of a guild in the alliance: hides a line from the room for the guild.
function Alliance:CanAdminister()
    return self:Get() ~= nil and GuildOS:IsOfficer() and true or false
end

----------------------------------------------------------------------
-- GOSALLY1 (alianca.md §3.2): the site's directory and its open raids, read by CompanionImport
-- (AllianceBlock, every field checked there) and kept in memory only. A block counts only for the
-- alliance in force, and only when that alliance is the site's: same tag, same key version as the
-- GOSGILD1's code. A pasted code gets the chat only (§3.3): nothing here.
----------------------------------------------------------------------
Alliance.RAID_GRACE = 3 * 3600   -- an open raid that began up to three hours ago is still shown
Alliance.MAP_TTL    = 60         -- seconds the recipe → item map built from the guild's own scans holds

function Alliance:SiteBlock()
    local pact = self:Get()
    local I = GuildOS.CompanionImport
    if not pact or not pact.site or not (I and I.AllianceBlock) then return nil end
    local block = I:AllianceBlock()
    local a = block and block.alliance
    if not a or a.tag ~= pact.tag or (pact.version and a.version ~= pact.version) then return nil end
    return block
end

-- When the site built the block in force (Unix seconds), for "as of": nil without one.
function Alliance:AsOf()
    local block = self:SiteBlock()
    return block and block.at or nil
end

-- Every guild the site names in the alliance, this one included, founder first as the site sends them.
function Alliance:SiteGuildNames()
    local out = {}
    local block = self:SiteBlock()
    for _, g in ipairs(block and block.guilds or {}) do out[#out + 1] = g.name end
    return out
end

-- A recipe spell id → (the item it makes, the profession's English name). The site sends recipe SPELL ids
-- (gosally1.md, Crafter.recipes) and "who crafts this?" asks by ITEM. WoW: Forever and retail read the static
-- catalog (Data/ProfCatalog*.lua, recipes[id][F.out] and F.line); TBC Anniversary has none, and maps what the
-- guild's own scans recorded (db.recipes: spellId with itemId), rebuilt at most every MAP_TTL seconds. A recipe
-- that makes no item (an enchant) or one nobody here has scanned maps to nothing and is not searchable by item.
function Alliance:_RecipeMap()
    local cat = GuildOS.ProfCatalog
    if type(cat) == "table" and type(cat.recipes) == "table" and type(cat.F) == "table" then
        if self._mapOf ~= cat then
            self._mapOf, self._mapAt = cat, nil
            self._map = function(id)
                local r = cat.recipes[id]
                if type(r) ~= "table" then return nil end
                local out, line = r[cat.F.out], r[cat.F.line]
                local prof = line and cat.professions and cat.professions[line]
                return (type(out) == "number" and out > 0) and out or nil, prof and prof.en or nil
            end
            self._mapRev = (self._mapRev or 0) + 1
        end
        return self._map, self._mapRev
    end
    local t = (GetTime and GetTime()) or 0
    if self._mapOf == "scans" and self._mapAt and t - self._mapAt < Alliance.MAP_TTL then
        return self._map, self._mapRev
    end
    local byId = {}
    local DC = GuildOS.DataCollector
    for _, profs in pairs(GuildOS.db and GuildOS.db.recipes or {}) do
        for profName, list in pairs(type(profs) == "table" and profs or {}) do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            for _, r in ipairs(type(list) == "table" and list or {}) do
                if type(r) == "table" and type(r.spellId) == "number" and not byId[r.spellId] then
                    byId[r.spellId] = { item = type(r.itemId) == "number" and r.itemId or nil, prof = canonical }
                end
            end
        end
    end
    self._mapOf, self._mapAt = "scans", t
    self._map = function(id)
        local hit = byId[id]
        if hit then return hit.item, hit.prof end
        return nil
    end
    self._mapRev = (self._mapRev or 0) + 1
    return self._map, self._mapRev
end

-- The allied guilds' members: { { guild = "Name", realm?, members = { { key, name, class, level, role, main,
-- prof, profs, recipes = { [itemId] = profession } } } } }, as the site sent them. `recipes` is keyed by the
-- ITEM a recipe makes (mapped by _RecipeMap from the site's recipe spell ids), its value the profession's
-- English name; `prof` is the member's first. Never our own guild, never a blocked one; opted-out members are
-- never in the site's block. Rebuilt only when the block or the recipe map changes.
function Alliance:Directory()
    local block = self:SiteBlock()
    if not block then return {} end
    local map, rev = self:_RecipeMap()
    if self._dirOf == block and self._dirRev == rev then return self._dir end
    local mine = self:MyGuildName()
    local out = {}
    for _, g in ipairs(block.guilds) do
        if not g.self and not (mine and GuildOS.SameGuildName(g.name, mine)) and not self:IsBlocked(g.name) then
            local members = {}
            for _, m in ipairs(g.members) do
                local recipes, profs, seen = {}, {}, {}
                for _, id in ipairs(m.spells or {}) do
                    local item, prof = map(id)
                    if item and not recipes[item] then recipes[item] = prof or true end
                    if prof and not seen[prof] then
                        seen[prof] = true
                        profs[#profs + 1] = prof
                    end
                end
                members[#members + 1] = { key = m.key, name = m.name, class = m.class, level = m.level, role = m.role,
                                          main = m.main, prof = profs[1], profs = profs, recipes = recipes }
            end
            out[#out + 1] = { guild = g.name, realm = g.realm, via = g.via, members = members }
        end
    end
    self._dirOf, self._dirRev, self._dir = block, rev, out
    return out
end

-- The allied guilds' raids open to the alliance, soonest first: { { id, guild, title, when, where, leader, going,
-- size } }, from three hours ago on. Signing up is on the site or in Discord: nothing here acts on them.
function Alliance:OpenRaids(at)
    local block = self:SiteBlock()
    local out = {}
    if not block then return out end
    at = at or now()
    for _, r in ipairs(block.raids) do
        if r.startsAt >= at - Alliance.RAID_GRACE and not self:IsBlocked(r.guild) then
            out[#out + 1] = { id = r.id, guild = r.guild, title = r.title, when = r.startsAt, where = r.where,
                              leader = r.lead and shortName(r.lead) or nil, going = r.going, size = r.size }
        end
    end
    return out
end

-- The directory's row for a character of an allied guild, or nil.
function Alliance:_DirectoryRow(name)
    local short = shortName(name):lower()
    if short == "" then return nil end
    -- Indexed once per directory: the room asks for every line it draws.
    local dir = self:Directory()
    if self._rowsOf ~= dir then
        local idx = {}
        for _, g in ipairs(dir) do
            for _, m in ipairs(type(g.members) == "table" and g.members or {}) do
                local k = type(m) == "table" and shortName(m.name):lower()
                if k and not idx[k] then idx[k] = { m, g.guild } end
            end
        end
        self._rowsOf, self._rows = dir, idx
    end
    local hit = self._rows[short]
    if hit then return hit[1], hit[2] end
    return nil
end

----------------------------------------------------------------------
-- Who is on now: a best effort, and the screen says so. A speaker heard on the alliance channel
-- (AllianceLink calls Heard), and a GuildOS client of an allied guild on the presence mesh.
----------------------------------------------------------------------
Alliance._heard = {}

-- `author` as AllianceLink names a speaker (Link.Speaker): WoW: Forever's "First Surname", a cross-realm "Bob-Other".
function Alliance:Heard(author, guild)
    local short = shortName(author)
    if short == "" or type(guild) ~= "string" or guild == "" then return end
    self._heard[short:lower()] = { name = tostring(author), guild = guild, t = now() }
end

-- Somebody who left the alliance channel (logged off): not on now any more.
function Alliance:Gone(author)
    local short = shortName(author)
    if short ~= "" then self._heard[short:lower()] = nil end
end

-- { { name, guild } } of the allied guilds' players seen now, by guild then name. Never ours.
function Alliance:OnlineNow(at)
    local out, seen = {}, {}
    local pact = self:Get()
    if not pact then return out end
    local mine = self:MyGuildName()
    at = at or now()
    for key, h in pairs(self._heard) do
        if at - (h.t or 0) <= Alliance.ONLINE_FOR and h.guild ~= mine and not self:IsBlocked(h.guild) then
            out[#out + 1] = { name = h.name, guild = h.guild }
            seen[key] = true
        end
    end
    local net, mesh = _G.ChehulNet, GuildOS.Mesh
    if net and net.Peers and mesh and mesh.GetPeerGuild then
        for short in pairs(net:Peers()) do
            local guild = mesh:GetPeerGuild(short)
            if guild and guild ~= mine and self:IsMemberGuild(guild) and not self:IsBlocked(guild)
               and not seen[tostring(short):lower()] then
                out[#out + 1] = { name = short, guild = guild }
                seen[tostring(short):lower()] = true
            end
        end
    end
    table.sort(out, function(a, b)
        if a.guild ~= b.guild then return a.guild < b.guild end
        return a.name < b.name
    end)
    return out
end

-- The alliance's guilds as far as the code and the channel tell: { { name, mine, online } }, ours
-- first, then by name. `online` counts OnlineNow's (nil for ours: the roster says that).
function Alliance:Guilds(at)
    local out = {}
    local pact = self:Get()
    if not pact then return out end
    local mine = self:MyGuildName()
    local online = {}
    for _, p in ipairs(self:OnlineNow(at)) do online[p.guild] = (online[p.guild] or 0) + 1 end
    local seen = {}
    local function add(name)
        local isMine = mine ~= nil and GuildOS.SameGuildName(name, mine)
        local k = GuildOS.FoldCase(name)
        if seen[k] then return end
        seen[k] = true
        out[#out + 1] = { name = isMine and mine or name, mine = isMine,
                          online = (not isMine) and (online[name] or 0) or nil, blocked = self:IsBlocked(name) or nil }
    end
    -- The site's list when it sent one (every guild, whether heard or not), then any guild heard on the channel.
    for _, name in ipairs(self:SiteGuildNames()) do add(name) end
    for name in pairs(pact.guilds) do add(name) end
    table.sort(out, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.name < b.name
    end)
    return out
end

----------------------------------------------------------------------
-- A character's guild and what is known of them
----------------------------------------------------------------------
-- Which ALLIED guild a character is from: the directory, else the channel this session. nil for
-- our own guildmates and for strangers. Feeds the whisper tag and the pug inspector.
function Alliance:GuildOfMember(name)
    if not self:Get() then return nil end
    local short = shortName(name):lower()
    if short == "" then return nil end
    local _, guild = self:_DirectoryRow(short)
    if not guild then
        local h = self._heard[short]
        guild = h and h.guild
    end
    if not guild or guild == self:MyGuildName() then return nil end
    return guild
end

-- What the directory says of an allied character: guild, class, level, role, main. nil otherwise.
function Alliance:MemberInfo(name)
    local row, guild = self:_DirectoryRow(name)
    if not row or guild == self:MyGuildName() then return nil end
    return { guild = guild, class = row.class, level = row.level, role = row.role, main = row.main }
end

-- Class and level of our OWN guildmates, cached and rebuilt on roster change: the room colours a
-- speaker by class, and a scan per line would be O(roster) per message.
function Alliance:_GuildInfoMap()
    if self._rosterInfo then
        return self._rosterInfo
    end
    local map = {}
    local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, total do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            map[(name:match("^([^-]+)") or name):lower()] = { class = classFile, level = level }
        end
    end
    self._rosterInfo = map
    return map
end

-- A speaker in the alliance room, an ally's (the directory) or one of ours (the synced record, else
-- the roster): { guild, class, level, spec, own }.
function Alliance:SpeakerInfo(name)
    local short = shortName(name)
    if short == "" then
        return nil
    end
    local allied = self:MemberInfo(short)
    if allied then
        allied.own = false
        return allied
    end
    local myGuild = self:MyGuildName()
    local key = GuildOS:GetPlayerKey(short, GetRealmName())
    local m = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    if m then
        return {
            guild = myGuild, class = m.class, level = m.level,
            spec  = type(m.spec) == "table" and specLabel(m.spec) or nil,
            own   = true,
        }
    end
    local hit = self:_GuildInfoMap()[short:lower()]
    if hit then
        return { guild = myGuild, class = hit.class, level = hit.level, own = true }
    end
    return nil
end

-- Everyone of an ALLIED guild who can craft `itemId`, from the directory: { name, guild, prof, class,
-- whisper, online }, the ones on now first. `recipes` in a directory row is keyed by the item it makes.
function Alliance:FindCrafters(itemId)
    local out = {}
    if not self:Get() or not itemId then return out end
    local mine = self:MyGuildName()
    local onNow = {}
    for _, p in ipairs(self:OnlineNow()) do onNow[p.name:lower()] = true end
    for _, g in ipairs(self:Directory()) do
        if g.guild ~= mine then
            for _, m in ipairs(type(g.members) == "table" and g.members or {}) do
                local recipes = type(m) == "table" and m.recipes
                if type(recipes) == "table" and recipes[itemId] then
                    local name = shortName(m.name)
                    local prof = type(recipes[itemId]) == "string" and recipes[itemId] or m.prof
                    out[#out + 1] = { name = name, guild = g.guild, prof = prof, class = m.class,
                                      whisper = m.key or name, online = onNow[name:lower()] == true }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.guild ~= b.guild then return a.guild < b.guild end
        return a.name < b.name
    end)
    return out
end

----------------------------------------------------------------------
-- /gos ally
----------------------------------------------------------------------
function Alliance:PrintStatus()
    local pact = self:Get()
    if not pact then
        GuildOS:Print(L["This guild is not in an alliance yet."])
        GuildOS:Print(Alliance.MOVED)
        return
    end
    local guilds = self:Guilds()
    GuildOS:Print(string.format(L["Alliance %s [%s] - %d guilds"], pact.name or pact.tag, pact.tag, #guilds))
    if pact.site then GuildOS:Print(L["From guildos.me: the alliance is managed there."]) end
    for _, g in ipairs(guilds) do
        local suffix = g.mine and (" " .. L["(you)"]) or (" - " .. string.format(L["%d online"], g.online or 0))
        GuildOS:Print("  " .. g.name .. suffix .. (g.blocked and (" " .. L["(blocked)"]) or ""))
    end
end

function Alliance:HandleCommand(args)
    local input = strtrim(args or "")
    local verb, rest = input:match("^(%S+)%s*(.*)$")
    verb = (verb and verb:lower()) or ""
    rest = strtrim(rest or "")
    if verb == "" then
        return self:PrintStatus()
    end
    if verb == "gchat" then
        -- The shared /g (issue #344): on, off, or how it is doing.
        local chat, link = GuildOS.AllianceChat, GuildOS.AllianceLink
        if not chat or not link then return end
        local sub = rest:lower()
        if sub == "on" or sub == "off" then
            chat:Prefs().guildBridge = (sub == "on")
            chat:_Notify()
        end
        GuildOS:Print((chat:Prefs().guildBridge and L["Allied /g: shown"] or L["Allied /g: hidden"])
            .. " · " .. link:StatusLine())
        return
    end
    if verb == "status" then
        -- What to send the maintainer when the alliance fails (#449): never the key.
        local link = GuildOS.AllianceLink
        if not link then return end
        for _, line in ipairs(link:StatusReport()) do GuildOS:Print(line) end
        return
    end
    if (verb == "join" and rest == "") or verb == "rejoin" then
        -- The hidden channel again, past a refusal the watchdog no longer retries on its own. With an argument
        -- it is the old pact's verb (join X-1), which says where alliances live now.
        local link, chat = GuildOS.AllianceLink, GuildOS.AllianceChat
        if not (link and chat) then return end
        if not link:Active() then return self:PrintStatus() end
        link:Rejoin()
        chat:Prefs().chat = true
        chat:EnsureJoined()
        GuildOS:Print(L["Joining the alliance channel..."])
        return
    end
    if verb == "block" or verb == "unblock" then
        -- An allied guild's lines hidden on this account (officers): nobody is told.
        local ok, err = self[verb == "block" and "Block" or "Unblock"](self, rest)
        if ok then
            GuildOS:Print(string.format(verb == "block" and L["Blocked: %s"] or L["Unblocked: %s"],
                GuildOS:SanitizeUserText(rest, Alliance.GUILD_NAME_MAX)))
        elseif err then
            GuildOS:Print(err)
        end
        return
    end
    -- create, invite, leave, join X, code, amb... : the pact's verbs, gone with it (alianca.md §3.4).
    GuildOS:Print(Alliance.MOVED)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function Alliance:Initialize()
    self:_RegisterTests()
    -- The roster class/level cache is only valid until the roster changes.
    local rf = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(rf, "GUILD_ROSTER_UPDATE")
    rf:SetScript("OnEvent", function() GuildOS.Alliance._rosterInfo = nil end)
end

function Alliance:_RegisterTests()
    if not GuildOS.SelfTest then
        return
    end
    GuildOS.SelfTest:Register("alliance.normalize_tag", function()
        if Alliance.NormalizeTag("brcore") ~= "BRCORE" then return false, "not uppercased" end
        if Alliance.NormalizeTag(" br-core! ") ~= "BRCORE" then return false, "punctuation kept" end
        if Alliance.NormalizeTag("abcdefghijklmno") ~= "ABCDEFGHIJKL" then return false, "not capped at 12" end
        if Alliance.NormalizeTag("...") ~= "" then return false, "empty result expected" end
        if Alliance.NormalizeTag(nil) ~= "" then return false, "nil must not error" end
        return true
    end)
    GuildOS.SelfTest:Register("alliance.guild_color", function()
        local r, g, b = Alliance.GuildColor("Guild A")
        local r2, g2, b2 = Alliance.GuildColor("Guild A")
        if r ~= r2 or g ~= g2 or b ~= b2 then return false, "not deterministic" end
        for _, v in ipairs({ r, g, b }) do
            if v < 0 or v > 1 then return false, "component out of range: " .. v end
        end
        local ar, ag, ab = Alliance.GuildColor("Guild B")
        if r == ar and g == ag and b == ab then return false, "two guilds got one colour" end
        if r > 0.8 and g < 0.25 and b < 0.25 then return false, "landed in the red band" end
        local nr = Alliance.GuildColor(nil)
        if nr == 0 then return false, "nil must not produce black" end
        if select(1, Alliance.GuildColor("")) ~= nr then return false, "empty must match nil" end
        return true
    end)
end
