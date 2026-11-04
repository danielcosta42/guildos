----------------------------------------------------------------------
-- Guild OS - Activation (issue #217, guildos.me #244)
--
-- The five steps that take a guild to where Guild OS holds, for its GM and officers while it is not
-- there yet. Two the client knows by itself: whether it publishes, and who runs the addon. The rest
-- only guildos.me knows, and it says so through the inbox (GOSGILD1). Nothing here is ever stored
-- about a step: only who hid the card, when the reminder last went and that it was celebrated.
--
-- WoW: Forever only.
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

local Activation = {}
GuildOS.Activation = Activation
local L = GuildOS.L

local DAY = 86400
local HIDE_S = 30 * DAY
local REMIND_S = 3 * DAY
local STALE_S = 3 * DAY
local ACTIVE_S = 30 * DAY
local MEMBERS_NEEDED = 5
local CELEBRATE_DELAY = 15   -- seconds after login: the chat is up by then

Activation.STEPS = { "publish", "bot", "account", "members", "run" }

function Activation:Initialize()
    GuildOS.db.activation = GuildOS.db.activation or {}
    GuildOS.Compat.After(CELEBRATE_DELAY, function() Activation:Celebrate() end)
end

local function fromSite()
    local block = GuildOS.CompanionImport and GuildOS.CompanionImport:GuildBlock()
    local a = block and block.activation
    return type(a) == "table" and a or nil
end

local function addonMembers(now)
    local n = 0
    for _, m in pairs(GuildOS.db.members or {}) do
        if type(m) == "table" and (tonumber(m.lastUpdate) or 0) > now - ACTIVE_S then n = n + 1 end
    end
    return n
end

-- Where the guild stands: { steps, done, activated, staleDays }. `staleDays` when what the site said
-- is over three days old, for the card to say so.
function Activation:Read(now)
    local a = fromSite()
    local site = a and type(a.steps) == "table" and a.steps or {}
    local steps = {
        publish = site.publish == true or (GuildOSDB and GuildOSDB.__companionAt) ~= nil,
        bot = site.bot == true,
        account = site.account == true,
        members = site.members == true or addonMembers(now) >= MEMBERS_NEEDED,
        run = site.run == true,
    }
    local done = 0
    for _, id in ipairs(self.STEPS) do
        if steps[id] then done = done + 1 end
    end
    local at = GuildOS.CompanionImport:Ack()
    local stale = at and now - at > STALE_S and math.floor((now - at) / DAY) or nil
    -- Once said it stays: a block gone old, or the companion off, does not un-activate a guild.
    local activated = (a and tonumber(a.activatedAt) ~= nil) or (GuildOS.db.activation and GuildOS.db.activation.celebrated == true) or false
    return { steps = steps, done = done, activated = activated, staleDays = stale }
end

-- For the GM and the officers, while the guild is not there and they did not put it away.
function Activation:ShouldShow(now)
    if not GuildOS:IsOfficer() or not GuildOS.db.activation then return false end
    return not self:Read(now).activated and now >= (GuildOS.db.activation.hiddenUntil or 0)
end

function Activation:Hide(now)
    GuildOS.db.activation.hiddenUntil = now + HIDE_S
end

-- One line in the login digest, every three days at most.
function Activation:GetDigestLine(now)
    if not self:ShouldShow(now) or now - (GuildOS.db.activation.remindedAt or 0) < REMIND_S then return nil end
    return string.format(L["Set up Guild OS for your guild: %d of %d steps done"], self:Read(now).done, #self.STEPS)
end

function Activation:Reminded(now)
    if GuildOS.db.activation then GuildOS.db.activation.remindedAt = now end
end

-- Once, when the site says the guild got there.
function Activation:Celebrate()
    local db = GuildOS.db.activation
    if not db or db.celebrated or not GuildOS:IsOfficer() then return end
    local a = fromSite()
    if a and tonumber(a.activatedAt) then
        db.celebrated = true
        GuildOS:Print(L["Guild OS is set up for your guild. Well done!"])
    end
end
