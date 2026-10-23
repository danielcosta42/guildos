----------------------------------------------------------------------
-- Guild OS - Mythic+ and the Great Vault (issue #187)
-- Retail only (ADR-0026). Each member's own client reads its keystone, its Mythic+ rating and its
-- weekly vault (the raid, dungeon and world rows; a delve fills the world row), and the member data
-- sync carries them as `mplus` and `vault`: absent from an older addon, never null. A guildmate without
-- Guild OS has neither. Compat reads; this module turns the reading into what is stored, and a stored
-- record (a guildmate's, so untrusted) into what the member sheet and the roster show.
----------------------------------------------------------------------
if not GuildOS.Client.isRetail then return end

local MythicPlus = {}
GuildOS.MythicPlus = MythicPlus
local L = GuildOS.L

local SEND_DELAY = 2   -- seconds after a run or a vault change before my data goes out
local SLOTS = 3        -- a vault row's slots
-- A raid row's level is a difficulty id, and the ids are not in the difficulties' order.
local RAID_RANK = { [17] = 1, [14] = 2, [15] = 3, [16] = 4 }
local RAID_LETTER = { [17] = "LFR", [14] = "N", [15] = "H", [16] = "M" }
local ROWS = { "raid", "dungeon", "world" }
local ROW_LABEL = { raid = L["Raid"], dungeon = L["Dungeons"], world = L["World"] }

-- Session state (Rule 6): whether the season's data and the vault's have arrived, and a send already
-- waiting.
local function state()
    local s = GuildOS.State
    if not s then return {} end
    s.mythicPlus = s.mythicPlus or {}
    return s.mythicPlus
end

function MythicPlus:Initialize()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(self.frame, "CHALLENGE_MODE_MAPS_UPDATE")
    GuildOS.Compat.RegisterEvent(self.frame, "CHALLENGE_MODE_COMPLETED")
    GuildOS.Compat.RegisterEvent(self.frame, "WEEKLY_REWARDS_UPDATE")
    self.frame:SetScript("OnEvent", function(_, event) MythicPlus:OnEvent(event) end)
    GuildOS.Compat.RequestMythicPlus()
end

-- The season's data has arrived, a run ended or the vault moved: my record goes out once, a moment
-- later, through the member broadcast, which reads it again (its throttle holds; the periodic one
-- carries it otherwise).
function MythicPlus:OnEvent(event)
    local s = state()
    if event == "CHALLENGE_MODE_MAPS_UPDATE" then s.ready = true end
    if event == "WEEKLY_REWARDS_UPDATE" then s.vaultReady = true end
    if s.pending then return end
    s.pending = true
    GuildOS.Compat.After(SEND_DELAY, function()
        s.pending = false
        if GuildOS.CommSystem then GuildOS.CommSystem:BroadcastMyData() end
    end)
end

-- What my client says now, for my own record: my Mythic+ once the season's data has arrived, and my
-- vault, summed up and stamped, once the vault's has (WEEKLY_REWARDS_UPDATE). Before either, the
-- client may answer 0 rating or empty rows, which would overwrite the real ones guildmates hold. Nil
-- for either the client cannot give yet.
function MythicPlus:Collect()
    local s = state()
    local mplus = s.ready and GuildOS.Compat.MythicPlus() or nil
    local vault = s.vaultReady and self:SumVault(GuildOS.Compat.WeeklyActivities(), GetServerTime()) or nil
    return mplus, vault
end

-- Whether `level` beats `best` in a row: a raid by its difficulty's rank, the others by number.
local function better(row, level, best)
    if not best then return true end
    if row == "raid" then return (RAID_RANK[level] or 0) > (RAID_RANK[best] or 0) end
    return level > best
end

-- The vault from Compat's slots: { at, raid = { n, best }, dungeon = { n, best }, world = { n, best } },
-- n the slots open (progress at its threshold), best the highest level among them. Nil without slots.
function MythicPlus:SumVault(slots, at)
    if type(slots) ~= "table" or #slots == 0 then return nil end
    local out = { at = at }
    for _, r in ipairs(slots) do
        local v = out[r.row] or { n = 0 }
        out[r.row] = v
        if r.threshold > 0 and r.progress >= r.threshold then
            v.n = v.n + 1
            if r.level > 0 and better(r.row, r.level, v.best) then v.best = r.level end
        end
    end
    return out
end

-- A member's rating, or nil when they sent none.
function MythicPlus:Rating(mplus)
    local r = type(mplus) == "table" and tonumber(mplus.rating)
    if not r or r < 0 then return nil end
    return math.floor(r)
end

-- A member's keystone level, or nil when they hold none.
function MythicPlus:KeyLevel(mplus)
    local key = type(mplus) == "table" and type(mplus.key) == "table" and mplus.key
    local level = key and tonumber(key.level)
    if not level or level <= 0 then return nil end
    return math.floor(level)
end

-- A member's keystone as the reader says it: "<dungeon> +12", the dungeon in the reader's language.
function MythicPlus:KeystoneText(mplus)
    local level = self:KeyLevel(mplus)
    if not level then return nil end
    return (GuildOS.Compat.ChallengeMapName(mplus.key.map) or L["Unknown dungeon"]) .. " +" .. level
end

-- A vault row's best level as words: N, H or M for a raid, +level for a dungeon, a delve's tier.
local function bestText(row, best)
    best = tonumber(best)
    if not best or best <= 0 then return nil end
    if row == "raid" then return RAID_LETTER[best] end
    if row == "dungeon" then return "+" .. math.floor(best) end
    return string.format(L["Tier %d"], math.floor(best))
end

-- The vault as the member sheet shows it: one { label, text } per row ("2/3 · H"). Nil and "old" when
-- it was read before this week's reset (`weekStart`, the reader's), nil when there is none.
function MythicPlus:VaultCells(vault, weekStart)
    if type(vault) ~= "table" then return nil end
    local at = tonumber(vault.at)
    if weekStart and (not at or at < weekStart) then return nil, "old" end
    local cells = {}
    for _, row in ipairs(ROWS) do
        local v = type(vault[row]) == "table" and vault[row] or {}
        local n = math.max(0, math.min(SLOTS, math.floor(tonumber(v.n) or 0)))
        local best = n > 0 and bestText(row, v.best) or nil
        cells[#cells + 1] = { label = ROW_LABEL[row], text = n .. "/" .. SLOTS .. (best and (" \194\183 " .. best) or "") }
    end
    return cells
end
