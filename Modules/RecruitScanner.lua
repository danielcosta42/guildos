----------------------------------------------------------------------
-- Guild OS - Recruit Scanner
-- Active recruiting: /who-scan unguilded candidates, mass-whisper a
-- template, capture replies. Officer-gated, OFF by default, fail-safe.
----------------------------------------------------------------------
local RecruitScanner = {}
BRutus.RecruitScanner = RecruitScanner

RecruitScanner.DEFAULTS = {
    template    = "Hi [player], we're recruiting — whisper me if interested!",
    minLevel    = 0,
    maxLevel    = 70,
    classes     = {},     -- set { WARRIOR=true }; empty = any
    batchMax    = 10,
    cooldownSec = 1800,
}

function RecruitScanner:Initialize()
    BRutus.db.recruitScanner = BRutus.db.recruitScanner or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.recruitScanner[k] == nil then
            BRutus.db.recruitScanner[k] = (type(v) == "table") and BRutus:DeepCopy(v) or v
        end
    end
    BRutus.db.recruitScanner.inbox = BRutus.db.recruitScanner.inbox or {}
    self._results = {}
    self._contactCd = {}
    self._RegisterEvents = self._RegisterEvents or function() end
    self:_RegisterEvents()      -- real body in Task 2 (until then, a stub below)
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure logic (unit-tested)
----------------------------------------------------------------------
function RecruitScanner:_ExpandTemplate(tmpl, cand)
    tmpl = tmpl or ""
    cand = cand or {}
    local out = tmpl
    out = out:gsub("%[player%]", cand.name or "")
    out = out:gsub("%[class%]", cand.class or "")
    out = out:gsub("%[level%]", tostring(cand.level or ""))
    return out
end

function RecruitScanner:_CandidateOK(cand, filters, isBannedFn)
    if not cand or not cand.name then return false end
    if cand.guilded then return false end                       -- unguilded only
    filters = filters or {}
    if (filters.minLevel or 0) > 0 and (cand.level or 0) < filters.minLevel then return false end
    if filters.maxLevel and (cand.level or 0) > filters.maxLevel then return false end
    if filters.classes and next(filters.classes) ~= nil and not filters.classes[cand.class] then return false end
    if isBannedFn and isBannedFn(cand.name) then return false end
    return true
end

----------------------------------------------------------------------
-- /who scan (fail-safe)
----------------------------------------------------------------------
function RecruitScanner:Scan(onDone)
    if not BRutus:IsOfficer() then return end
    if self._scanBusy then return end
    self._scanBusy = true
    self._results = {}
    local cfg = BRutus.db.recruitScanner
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() RecruitScanner:_OnWhoResult() end)
    end
    self._whoFrame:RegisterEvent("WHO_LIST_UPDATE")
    self._onScanDone = onDone
    if SetWhoToUI then SetWhoToUI(1) end
    -- level-range query; Blizzard caps results (~50). classes filtered post-hoc.
    local q = string.format("%d-%d", (cfg.minLevel or 1) > 0 and cfg.minLevel or 1, cfg.maxLevel or 70)
    SendWho(q)
    BRutus.Compat.After(6, function()
        if RecruitScanner._scanBusy then RecruitScanner:_FinishScan() end
    end)
end

function RecruitScanner:_OnWhoResult()
    local cfg = BRutus.db.recruitScanner
    local isBanned = function(n) return BRutus.BanList and BRutus.BanList:IsBanned(n) end
    local out = {}
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local n = C_FriendList.GetNumWhoResults() or 0
        for i = 1, n do
            local w = C_FriendList.GetWhoInfo(i)
            if w and w.fullName then
                local short = w.fullName:match("^([^-]+)") or w.fullName
                local cand = {
                    name = short, level = w.level, class = w.filename,
                    zone = w.area, guilded = (w.fullGuildName ~= nil and w.fullGuildName ~= ""),
                }
                if self:_CandidateOK(cand, cfg, isBanned) then out[#out + 1] = cand end
            end
        end
    end
    self._results = out
    self:_FinishScan()
end

function RecruitScanner:_FinishScan()
    if self._whoFrame then self._whoFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    if SetWhoToUI then SetWhoToUI(0) end
    self._scanBusy = nil
    if self._onScanDone then BRutus:SafeCall(self._onScanDone) end
end

function RecruitScanner:GetResults() return self._results or {} end

----------------------------------------------------------------------
-- Mass-whisper (throttled, cooldown, batch-capped)
----------------------------------------------------------------------
function RecruitScanner:WhisperSelected(names)
    if not BRutus:IsOfficer() then return end
    local cfg = BRutus.db.recruitScanner
    local now = GetServerTime()
    local sent, delay = 0, 0
    for _, name in ipairs(names or {}) do
        if sent >= (cfg.batchMax or 10) then break end
        local cd = self._contactCd[name]
        if not (cd and cd > now) then
            local cand
            for _, r in ipairs(self._results) do if r.name == name then cand = r; break end end
            local msg = self:_ExpandTemplate(cfg.template, cand or { name = name })
            self._contactCd[name] = now + (cfg.cooldownSec or 1800)
            sent = sent + 1
            delay = delay + 1.5    -- throttle: 1.5s between whispers
            BRutus.Compat.After(delay, function()
                SendChatMessage(msg, "WHISPER", nil, name)
            end)
        end
    end
    if sent > 0 then
        BRutus:Print(string.format(BRutus.L["Whispering %d candidate(s)…"], sent))
    end
end

----------------------------------------------------------------------
-- Reply inbox
----------------------------------------------------------------------
function RecruitScanner:_RegisterEvents()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        local short = author and (author:match("^([^-]+)") or author)
        if short and RecruitScanner._contactCd[short] then
            local inbox = BRutus.db.recruitScanner.inbox
            table.insert(inbox, 1, { name = short, msg = msg, ts = GetServerTime() })
            while #inbox > 200 do table.remove(inbox) end
        end
    end)
end

function RecruitScanner:GetInbox() return (BRutus.db.recruitScanner and BRutus.db.recruitScanner.inbox) or {} end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function RecruitScanner:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("scanner.template", function()
        local s = RecruitScanner:_ExpandTemplate("Hi [player] ([level] [class])",
            { name = "Bob", level = 68, class = "MAGE" })
        if s ~= "Hi Bob (68 MAGE)" then return false, s end
        return true
    end)
    S:Register("scanner.candidate_ok", function()
        local f = { minLevel = 60, maxLevel = 70, classes = { MAGE = true } }
        local ok = RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = false }, f)
        if not ok then return false, "should pass" end
        return true
    end)
    S:Register("scanner.reject_guilded", function()
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = true }, {}) then
            return false, "guilded must be rejected"
        end
        return true
    end)
    S:Register("scanner.reject_banned", function()
        local banned = function(n) return n == "Bob" end
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, guilded = false }, {}, banned) then
            return false, "banned must be rejected"
        end
        return true
    end)
end
