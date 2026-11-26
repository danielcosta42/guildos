----------------------------------------------------------------------
-- Guild OS - The alliance, what the addon keeps of it (specs/salao/alianca.md, audit #448)
--
-- The alliance lives on guildos.me (alianca.md §3.1). In the game it is:
--   * the alliance code the GreenWall way (Modules/AllianceLink.lua): GOS=TAG:key, the hidden
--     channel, the shared /g mirrored with the speaker's guild tag;
--   * the alliance room (Modules/AllianceChat.lua), on that same channel;
--   * what the site sends through the companion: the shared bans (GOSGILD1, Modules/BanList.lua)
--     and, in a later step, the directory and the open raids (GOSALLY1).
--
-- The ambassador pact that used to live here (invites, the join code, ambassadors, the whisper ops,
-- the bridge, the allied data sync, the alliance board and LFG pool) is gone (§3.4). This file is
-- the read-only face the rest of the addon asks: which alliance, which guilds, who is on now, which
-- guild a character is from, who crafts an item. It decides nothing and sends nothing.
----------------------------------------------------------------------
local Alliance = {}
GuildOS.Alliance = Alliance
local L = GuildOS.L

Alliance.TAG_MAX        = 12
Alliance.GUILD_NAME_MAX = 24
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
    return (pact and pact.guilds and pact.guilds[guildName or ""]) ~= nil
end

-- An officer of a guild in the alliance: hides a line from the room for the guild.
function Alliance:CanAdminister()
    return self:Get() ~= nil and GuildOS:IsOfficer() and true or false
end

----------------------------------------------------------------------
-- HOOKS FOR GOSALLY1 (alianca.md §3.2). The site's directory and its open raids reach the game in
-- a new companion block, read in a later step. Until then both answer an empty list, and everything
-- below that reads them (GuildOfMember, MemberInfo, FindCrafters, the Salão, the digest) works the
-- same with nothing in them.
----------------------------------------------------------------------
-- The allied guilds' members: { { guild = "Name", members = { { name, class, level, role, main,
-- recipes = { [recipeId] = true } } } } }. Never our own guild; opted-out members never in it.
function Alliance:Directory()
    return {}
end

-- The allied guilds' raids open to the alliance, soonest first: { { guild, title, when, where,
-- leader, going, size } }. Signing up is on the site or in Discord.
function Alliance:OpenRaids()
    return {}
end

-- The directory's row for a character of an allied guild, or nil.
function Alliance:_DirectoryRow(name)
    local short = shortName(name):lower()
    if short == "" then return nil end
    for _, g in ipairs(self:Directory()) do
        for _, m in ipairs(type(g.members) == "table" and g.members or {}) do
            if type(m) == "table" and shortName(m.name):lower() == short then
                return m, g.guild
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Who is on now: a best effort, and the screen says so. A speaker heard on the alliance channel
-- (AllianceLink calls Heard), and a GuildOS client of an allied guild on the presence mesh.
----------------------------------------------------------------------
Alliance._heard = {}

function Alliance:Heard(author, guild)
    local short = shortName(author)
    if short == "" or type(guild) ~= "string" or guild == "" then return end
    self._heard[short:lower()] = { name = short, guild = guild, t = now() }
end

-- { { name, guild } } of the allied guilds' players seen now, by guild then name. Never ours.
function Alliance:OnlineNow(at)
    local out, seen = {}, {}
    local pact = self:Get()
    if not pact then return out end
    local mine = self:MyGuildName()
    at = at or now()
    for key, h in pairs(self._heard) do
        if at - (h.t or 0) <= Alliance.ONLINE_FOR and h.guild ~= mine then
            out[#out + 1] = { name = h.name, guild = h.guild }
            seen[key] = true
        end
    end
    local net, mesh = _G.ChehulNet, GuildOS.Mesh
    if net and net.Peers and mesh and mesh.GetPeerGuild then
        for short in pairs(net:Peers()) do
            local guild = mesh:GetPeerGuild(short)
            if guild and guild ~= mine and pact.guilds[guild] and not seen[tostring(short):lower()] then
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
    for name in pairs(pact.guilds) do
        out[#out + 1] = { name = name, mine = (name == mine), online = (name ~= mine) and (online[name] or 0) or nil }
    end
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

-- Everyone of an ALLIED guild who can craft `itemId`, from the directory: { name, guild, prof,
-- online }, the ones on now first. `recipes` in a directory row is keyed by the item it makes.
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
                    out[#out + 1] = { name = name, guild = g.guild, prof = m.prof,
                                      online = onNow[name:lower()] == true }
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
    for _, g in ipairs(guilds) do
        local suffix = g.mine and (" " .. L["(you)"]) or (" - " .. string.format(L["%d online"], g.online or 0))
        GuildOS:Print("  " .. g.name .. suffix)
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
    -- create, invite, leave, join, code, amb... : the pact's verbs, gone with it (alianca.md §3.4).
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
