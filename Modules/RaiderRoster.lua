----------------------------------------------------------------------
-- Guild OS - Raider Roster
-- An officer-curated pool of the guild's raiders, independent of any one
-- raid. Officers hand-manage columns (which roles each person can fill —
-- multi-role, a gear-readiness status, and a free note) so the data does
-- NOT require the listed player to run the addon. When a player DOES run
-- it, the UI enriches the row read-only with their synced iLvl + spec.
--
-- Officer-authored, synced between clients like OfficerNotes/TrialTracker:
-- the whole (small) table is broadcast on edit / on request, merged
-- per-player by updatedAt (newest wins) so concurrent edits don't clobber.
----------------------------------------------------------------------
local RaiderRoster = {}
BRutus.RaiderRoster = RaiderRoster
local LibSerialize = LibStub("LibSerialize")

RaiderRoster.ROLES = { "TANK", "HEALER", "DPS" }
-- Gear-readiness cycle (officer-set); "" = unset.
RaiderRoster.GEAR_CYCLE = { "", "ready", "gearing", "missing" }

function RaiderRoster:Initialize()
    BRutus.db.raiders = BRutus.db.raiders or {}
end

function RaiderRoster:GetAll() return BRutus.db.raiders or {} end
function RaiderRoster:Get(key) return BRutus.db.raiders and BRutus.db.raiders[key] or nil end

local function getOrNew(key)
    BRutus.db.raiders = BRutus.db.raiders or {}
    local r = BRutus.db.raiders[key]
    if not r then
        r = { roles = {}, gear = "", note = "" }
        BRutus.db.raiders[key] = r
    end
    r.roles = r.roles or {}
    return r
end

local function touch(r)
    r.updatedBy = UnitName("player")
    r.updatedAt = GetServerTime()
end

----------------------------------------------------------------------
-- Officer edits (each refreshes the UI + queues a sync broadcast).
----------------------------------------------------------------------
function RaiderRoster:ToggleRole(key, role)
    if not BRutus:IsOfficer() then return end
    local r = getOrNew(key)
    r.roles[role] = (not r.roles[role]) and true or nil
    touch(r)
    self:Refresh(); self:Broadcast()
end

function RaiderRoster:CycleGear(key)
    if not BRutus:IsOfficer() then return end
    local r = getOrNew(key)
    local cur, idx = r.gear or "", 1
    for i, v in ipairs(self.GEAR_CYCLE) do if v == cur then idx = i break end end
    r.gear = self.GEAR_CYCLE[(idx % #self.GEAR_CYCLE) + 1]
    touch(r)
    self:Refresh(); self:Broadcast()
end

function RaiderRoster:SetNote(key, text)
    if not BRutus:IsOfficer() then return end
    local r = getOrNew(key)
    r.note = strtrim(text or "")
    touch(r)
    self:Refresh(); self:Broadcast()
end

function RaiderRoster:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Sync (officer -> guild). The table is small, so we broadcast it whole
-- (debounced); receivers merge per-player by updatedAt.
----------------------------------------------------------------------
function RaiderRoster:Broadcast()
    if not BRutus.CommSystem or not IsInGuild() then return end
    if not BRutus:IsOfficer() then return end
    if self._bcastPending then return end
    self._bcastPending = true
    C_Timer.After(1.5, function()
        self._bcastPending = nil
        local payload = LibSerialize:Serialize(self:GetAll())
        BRutus.CommSystem:SendMessage("RR", payload)
    end)
end

-- Officers answer a sync REQUEST with the current table (login backfill).
function RaiderRoster:RespondToSync()
    if BRutus:IsOfficer() then self:Broadcast() end
end

-- Apply an incoming table (only trusted from a verified officer). Merge
-- per-player: keep whichever record has the newer updatedAt.
function RaiderRoster:HandleIncoming(sender, data)
    if not (BRutus.IsOfficerByName and BRutus:IsOfficerByName(sender)) then return end
    local ok, tbl = LibSerialize:Deserialize(data)
    if not ok or type(tbl) ~= "table" then return end
    BRutus.db.raiders = BRutus.db.raiders or {}
    local changed = false
    for key, rec in pairs(tbl) do
        if type(rec) == "table" then
            local cur = BRutus.db.raiders[key]
            if not cur or (rec.updatedAt or 0) >= (cur.updatedAt or 0) then
                rec.roles = rec.roles or {}
                BRutus.db.raiders[key] = rec
                changed = true
            end
        end
    end
    if changed then self:Refresh() end
end
