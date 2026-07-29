----------------------------------------------------------------------
-- Guild OS - Alliance (cross-guild federation)
--
-- Lets 5 to 12 guilds federate WITHOUT merging: they share a chat channel, a
-- calendar, an LFG pool and a crafter directory while staying independent.
-- Design: docs/superpowers/specs/2026-07-29-alliance-design.md
--
-- WHY IT LOOKS LIKE THIS: there is no reliable cross-guild addon bus on this
-- client. CHANNEL addon sends are gated for timer traffic (see LibChehulMesh
-- header), YELL is zone- AND layer-local, GUILD only reaches your own guild.
-- The only reliable directed cross-guild bus is WHISPER. So the whole feature
-- is an EMBASSY model: one elected "bridge" client per guild whispers the other
-- guilds, and republishes what it learns inside its own guild over SyncService.
-- A regular member never sends anything cross-guild.
--
-- TRUST: the root of trust is a signed list of CHARACTER NAMES (ambassadors).
-- A whisper sender cannot be forged in WoW, so that is enough: no crypto, no
-- server. A change claimed on behalf of guild X is only accepted when it was
-- whispered by a name currently listed under X in the pact.
--
-- This file owns the pact, the trust checks, bridge election and the
-- INV/ACK/PACT/LEAVE wire ops. Domain data sync lives in AllianceSync.lua.
----------------------------------------------------------------------
local Alliance = {}
GuildOS.Alliance = Alliance

-- Open protocol on the shared mesh transport, same family style as CraftNet
-- ("ChehulCraft"/CC1) and RecruitBeacon ("ChehulRecruit"/CR2).
Alliance.PREFIX = "ChehulAlly"
Alliance.PROTO  = "AL1"

-- Caps. Headroom over the expected 5 to 12 guilds, not a target.
Alliance.TAG_MAX         = 12
Alliance.NAME_MAX        = 32
Alliance.GUILD_NAME_MAX  = 24
Alliance.MAX_GUILDS      = 16
Alliance.MAX_AMBASSADORS = 8

-- Seconds the current bridge is held before a new winner may take over. Stops
-- the role from flapping while the guild roster churns on login.
Alliance.BRIDGE_HOLD = 30

local function shortName(name)
    return (Ambiguate and Ambiguate(name or "", "short")) or name
end

----------------------------------------------------------------------
-- Pure helpers. Everything below this line is deterministic and pinned by
-- /gos selftest, because several of these MUST agree across clients.
----------------------------------------------------------------------

-- "brcore" -> "BRCORE". Returns "" when nothing usable is left, which every
-- caller treats as "not a valid tag".
function Alliance.NormalizeTag(tag)
    local s = tostring(tag or ""):upper():gsub("[^A-Z0-9]", "")
    if #s > Alliance.TAG_MAX then
        s = s:sub(1, Alliance.TAG_MAX)
    end
    return s
end

-- The custom chat channel the alliance auto-joins. nil when the tag is unusable.
function Alliance.ChannelName(tag)
    local t = Alliance.NormalizeTag(tag)
    if t == "" then
        return nil
    end
    return "GOS" .. t
end

-- djb2. PART OF THE PROTOCOL: every client must compute the same number, or two
-- clients disagree about who the bridge is and the guild syncs twice (or never).
-- Do NOT replace this with anything that varies by client, locale or table order.
function Alliance.Hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483648
    end
    return h
end

-- Pure. Given every online GuildOS client of this guild as "Name-Realm" keys,
-- return the one that acts as the bridge. Lowest hash wins; a collision is
-- broken by the key itself, so the answer never depends on table order.
function Alliance.ElectBridge(onlineKeys)
    if type(onlineKeys) ~= "table" then
        return nil
    end
    local best, bestHash
    for _, key in ipairs(onlineKeys) do
        if type(key) == "string" and key ~= "" then
            local h = Alliance.Hash(key)
            if not best or h < bestHash or (h == bestHash and key < best) then
                best, bestHash = key, h
            end
        end
    end
    return best
end

-- Pure. Hold `prev` until the hold window has passed, so the role does not
-- flap while people are still loading in.
function Alliance._DebouncedBridge(prev, candidate, prevAt, now, hold)
    if candidate == nil then
        return nil
    end
    if prev == nil then
        return candidate
    end
    if candidate == prev then
        return prev
    end
    if (now or 0) - (prevAt or 0) >= (hold or Alliance.BRIDGE_HOLD) then
        return candidate
    end
    return prev
end

local function countGuilds(pact)
    local n = 0
    if pact and type(pact.guilds) == "table" then
        for _ in pairs(pact.guilds) do
            n = n + 1
        end
    end
    return n
end

-- The wire copy of a pact. `blocked` is a LOCAL ignore list and must never
-- travel: leaking it would tell guild C that guild A blocked it.
function Alliance.SerializePact(pact)
    if type(pact) ~= "table" then
        return nil
    end
    local out = BRutus:DeepCopy(pact)
    out.blocked = nil
    return out
end

-- Validate + clamp a pact that arrived from the wire. Returns nil when the
-- shape is unusable. Always drops `blocked` on the way in too, so a hostile
-- sender cannot plant entries in our local ignore list.
function Alliance.SanitizePact(raw)
    if type(raw) ~= "table" or type(raw.guilds) ~= "table" then
        return nil
    end
    local tag = Alliance.NormalizeTag(raw.tag)
    if tag == "" then
        return nil
    end

    -- Deterministic truncation: sort the keys, then keep the owner first so a
    -- pact never loses the one guild that is allowed to remove others.
    local owner = BRutus:SanitizeUserText(raw.owner, Alliance.GUILD_NAME_MAX)
    local keys = {}
    for name in pairs(raw.guilds) do
        if type(name) == "string" then
            keys[#keys + 1] = name
        end
    end
    table.sort(keys)
    if owner ~= "" then
        for i, name in ipairs(keys) do
            if name == owner and i > 1 then
                table.remove(keys, i)
                table.insert(keys, 1, name)
                break
            end
        end
    end

    local out = {
        tag      = tag,
        name     = BRutus:SanitizeUserText(raw.name, Alliance.NAME_MAX),
        owner    = owner,
        revision = tonumber(raw.revision) or 0,
        guilds   = {},
    }

    local kept = 0
    for _, name in ipairs(keys) do
        if kept >= Alliance.MAX_GUILDS then
            break
        end
        local clean = BRutus:SanitizeUserText(name, Alliance.GUILD_NAME_MAX)
        local entry = raw.guilds[name]
        if clean ~= "" and type(entry) == "table" and not out.guilds[clean] then
            local ambassadors = {}
            if type(entry.ambassadors) == "table" then
                for _, amb in ipairs(entry.ambassadors) do
                    if #ambassadors >= Alliance.MAX_AMBASSADORS then
                        break
                    end
                    local a = BRutus:SanitizeUserText(shortName(amb), Alliance.GUILD_NAME_MAX)
                    if a ~= "" then
                        ambassadors[#ambassadors + 1] = a
                    end
                end
            end
            out.guilds[clean] = {
                ambassadors = ambassadors,
                joinedAt    = tonumber(entry.joinedAt) or 0,
                addedBy     = BRutus:SanitizeUserText(entry.addedBy, Alliance.GUILD_NAME_MAX),
            }
            kept = kept + 1
        end
    end

    if kept == 0 then
        return nil
    end
    return out
end

-- Which of two pacts wins. Highest revision, then (to guarantee two clients
-- that tie still CONVERGE instead of each keeping its own copy forever) the
-- one with more guilds, then the lower owner name. Ties at second granularity
-- are already vanishingly rare since revision is GetServerTime() of the edit.
function Alliance.ResolvePact(current, incoming)
    if type(incoming) ~= "table" then
        return current
    end
    if type(current) ~= "table" then
        return incoming
    end
    local cr, ir = tonumber(current.revision) or 0, tonumber(incoming.revision) or 0
    if ir > cr then
        return incoming
    end
    if ir < cr then
        return current
    end
    local cn, inn = countGuilds(current), countGuilds(incoming)
    if inn > cn then
        return incoming
    end
    if inn < cn then
        return current
    end
    if tostring(incoming.owner or "") < tostring(current.owner or "") then
        return incoming
    end
    return current
end

-- Is `playerName` allowed to speak for `guildName`? This is the whole trust
-- model: the caller must have taken `playerName` from the comm envelope sender,
-- never from a field inside the payload.
function Alliance.IsAmbassador(pact, guildName, playerName)
    if type(pact) ~= "table" or type(pact.guilds) ~= "table" then
        return false
    end
    local entry = pact.guilds[guildName or ""]
    if type(entry) ~= "table" or type(entry.ambassadors) ~= "table" then
        return false
    end
    local who = shortName(playerName):lower()
    if who == "" then
        return false
    end
    for _, amb in ipairs(entry.ambassadors) do
        if shortName(amb):lower() == who then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Self tests (run with /gos selftest)
----------------------------------------------------------------------
local function samplePact()
    return {
        tag = "BRCORE", name = "Nucleo BR", owner = "Guild A", revision = 100,
        guilds = {
            ["Guild A"] = { ambassadors = { "Chehul" } },
            ["Guild B"] = { ambassadors = { "Beltrano" } },
        },
        blocked = { ["Guild C"] = true },
    }
end

function Alliance:_RegisterTests()
    if not BRutus.SelfTest then
        return
    end

    BRutus.SelfTest:Register("alliance.normalize_tag", function()
        if Alliance.NormalizeTag("brcore") ~= "BRCORE" then return false, "not uppercased" end
        if Alliance.NormalizeTag(" br-core! ") ~= "BRCORE" then return false, "punctuation kept" end
        if Alliance.NormalizeTag("abcdefghijklmno") ~= "ABCDEFGHIJKL" then return false, "not capped at 12" end
        if Alliance.NormalizeTag("...") ~= "" then return false, "empty result expected" end
        if Alliance.NormalizeTag(nil) ~= "" then return false, "nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.channel_name", function()
        if Alliance.ChannelName("brcore") ~= "GOSBRCORE" then return false, "bad channel name" end
        if Alliance.ChannelName("...") ~= nil then return false, "empty tag must yield nil" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.hash_is_stable", function()
        local a = Alliance.Hash("Chehul-Nefarian")
        if a ~= Alliance.Hash("Chehul-Nefarian") then return false, "not deterministic" end
        if a < 0 then return false, "must be non-negative" end
        if Alliance.Hash("Chehul-Nefarian") == Alliance.Hash("Chehul-Ragnaros") then
            return false, "realm must affect the hash"
        end
        if Alliance.Hash("") ~= 5381 then return false, "djb2 seed changed" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.elect_bridge", function()
        local keys = { "Ann-R", "Bob-R", "Cid-R" }
        local first = Alliance.ElectBridge(keys)
        if not first then return false, "no bridge elected" end
        if Alliance.ElectBridge({ "Cid-R", "Ann-R", "Bob-R" }) ~= first then
            return false, "election depends on input order"
        end
        for _, k in ipairs(keys) do
            if Alliance.Hash(k) < Alliance.Hash(first) then return false, "not the lowest hash" end
        end
        if Alliance.ElectBridge({}) ~= nil then return false, "empty list must yield nil" end
        if Alliance.ElectBridge(nil) ~= nil then return false, "nil must not error" end
        if Alliance.ElectBridge({ "Solo-R" }) ~= "Solo-R" then return false, "single candidate" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.bridge_debounce", function()
        local r = Alliance._DebouncedBridge(nil, "Ann-R", 0, 100, 30)
        if r ~= "Ann-R" then return false, "first election must apply immediately" end
        r = Alliance._DebouncedBridge("Ann-R", "Bob-R", 100, 110, 30)
        if r ~= "Ann-R" then return false, "must hold the previous bridge inside the window" end
        r = Alliance._DebouncedBridge("Ann-R", "Bob-R", 100, 140, 30)
        if r ~= "Bob-R" then return false, "must switch after the hold window" end
        r = Alliance._DebouncedBridge("Ann-R", nil, 100, 140, 30)
        if r ~= nil then return false, "no candidates means no bridge" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.serialize_strips_blocked", function()
        local out = Alliance.SerializePact(samplePact())
        if out.blocked ~= nil then return false, "blocked leaked onto the wire" end
        if out.guilds["Guild A"] == nil then return false, "guilds lost" end
        local src = samplePact()
        out.guilds["Guild A"].ambassadors[1] = "Tampered"
        if src.guilds["Guild A"].ambassadors[1] ~= "Chehul" then return false, "not a deep copy" end
        if Alliance.SerializePact(nil) ~= nil then return false, "nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.sanitize_drops_blocked", function()
        local out = Alliance.SanitizePact(samplePact())
        if not out then return false, "valid pact rejected" end
        if out.blocked ~= nil then return false, "incoming blocked was kept" end
        if out.guilds["Guild A"].ambassadors[1] ~= "Chehul" then return false, "ambassador lost" end
        if Alliance.SanitizePact(nil) ~= nil then return false, "nil must be rejected" end
        if Alliance.SanitizePact({ tag = "" }) ~= nil then return false, "tagless pact must be rejected" end
        if Alliance.SanitizePact({ tag = "X", guilds = {} }) ~= nil then return false, "empty pact must be rejected" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.sanitize_clamps", function()
        local p = samplePact()
        for i = 1, 40 do p.guilds["Filler " .. i] = { ambassadors = { "Amb" .. i } } end
        for i = 1, 30 do p.guilds["Guild A"].ambassadors[i] = "Amb" .. i end
        local out = Alliance.SanitizePact(p)
        if not out then return false, "clamped pact rejected outright" end
        local n = 0
        for _ in pairs(out.guilds) do n = n + 1 end
        if n > Alliance.MAX_GUILDS then return false, "guild cap not enforced: " .. n end
        if not out.guilds["Guild A"] then return false, "owner guild was truncated away" end
        if #out.guilds["Guild A"].ambassadors > Alliance.MAX_AMBASSADORS then
            return false, "ambassador cap not enforced"
        end
        return true
    end)

    BRutus.SelfTest:Register("alliance.resolve_pact", function()
        local cur = samplePact()
        local newer = samplePact(); newer.revision = 200
        if Alliance.ResolvePact(cur, newer).revision ~= 200 then return false, "newer must win" end
        local older = samplePact(); older.revision = 50
        if Alliance.ResolvePact(cur, older).revision ~= 100 then return false, "older must lose" end
        local tie = samplePact(); tie.owner = "Guild B"
        if Alliance.ResolvePact(cur, tie).owner ~= "Guild A" then
            return false, "tie must keep the lower owner name"
        end
        local bigger = samplePact(); bigger.guilds["Guild C"] = { ambassadors = { "Zeca" } }
        if Alliance.ResolvePact(cur, bigger).guilds["Guild C"] == nil then
            return false, "tie must prefer the fuller pact"
        end
        if Alliance.ResolvePact(nil, newer).revision ~= 200 then return false, "no current pact" end
        if Alliance.ResolvePact(cur, nil).revision ~= 100 then return false, "no incoming pact" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.is_ambassador", function()
        local p = samplePact()
        if not Alliance.IsAmbassador(p, "Guild A", "Chehul") then return false, "known ambassador rejected" end
        if not Alliance.IsAmbassador(p, "Guild A", "Chehul-Nefarian") then return false, "realm suffix broke it" end
        if Alliance.IsAmbassador(p, "Guild B", "Chehul") then return false, "wrong guild accepted" end
        if Alliance.IsAmbassador(p, "Guild Z", "Chehul") then return false, "unknown guild accepted" end
        if Alliance.IsAmbassador(nil, "Guild A", "Chehul") then return false, "nil pact accepted" end
        if Alliance.IsAmbassador(p, "Guild A", "") then return false, "empty name accepted" end
        return true
    end)
end
