----------------------------------------------------------------------
-- Guild OS - Raid Plan (issue #296)
--
-- The night's plan as the site sent it in GOSROST1 v4 (the site's #463): each boss's note, who does
-- what on it, and the loot rules. Shown out of combat only — on WoW: Forever the addon cannot read the
-- fight (Midnight's restrictions), so this is text and never a timer:
--
--   * the plan panel (UI/RaidPlanPanel.lua), from the Web panel and /gos roster plan;
--   * a small window with my own task when I target a boss of the plan out of combat, once per boss
--     per raid, and never for somebody with no task there;
--   * the raid leader (or an assistant) can say a boss's note in raid chat with one click, out of
--     combat and outside chat lockdown.
--
-- Business logic only; the frames are UI/RaidPlanPanel.lua.
----------------------------------------------------------------------
local Plan = {}
GuildOS.RaidPlan = Plan
local L = GuildOS.L

-- What each kind of task is called, as the site's kinds are (the site's #462).
Plan.KINDS = {
    tank = L["Tank"], heal = L["Healer"], interrupt = L["Interrupt"], kite = L["Kite"], position = L["Position"],
}
-- The loot systems the site knows (the site's #459).
Plan.LOOT = {
    rolls = L["Rolls"], wishlist = L["Wishlist"], dkp = L["DKP"], softres = L["Soft reserve"],
    council = L["Loot council"], external = L["Outside GuildOS"],
}

-- A chat line is 255 bytes; the note is cut on spaces below that.
local CHAT_LINE = 240

local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() and true or false end

--- The plan of the roster in hand, or nil.
function Plan:Current()
    local roster = GuildOS.CompanionImport and GuildOS.CompanionImport:Current()
    return roster and roster.plan or nil, roster
end

--- The plan's bosses: those with a note in the site's order (the catalogue's), then any boss only a
--- task names, in the order the tasks came.
function Plan:Bosses()
    local plan = self:Current()
    local out, seen = {}, {}
    if not plan then return out end
    local function add(b)
        if b and not seen[b] then seen[b] = true; out[#out + 1] = b end
    end
    for _, n in ipairs(plan.notes or {}) do add(n.boss) end
    for _, a in ipairs(plan.assignments or {}) do add(a.boss) end
    return out
end

function Plan:NoteFor(boss)
    local plan = self:Current()
    for _, n in ipairs(plan and plan.notes or {}) do
        if n.boss == boss then return n.text end
    end
    return nil
end

function Plan:TasksFor(boss)
    local plan, out = self:Current(), {}
    for _, a in ipairs(plan and plan.assignments or {}) do
        if a.boss == boss then out[#out + 1] = a end
    end
    return out
end

--- Whether a task is mine: by the key when the site sent one, else by the character's name.
function Plan:IsMine(a)
    local name = GuildOS.Compat.PlayerName()
    -- On WoW: Forever the site's key is the whole name (keyInGame), which is this client's key there.
    if a.key then return a.key == GuildOS:GetPlayerKey(name) or a.key == name end
    return name ~= nil and a.name:lower() == name:lower()
end

function Plan:MyTasks(boss)
    local out = {}
    for _, a in ipairs(self:TasksFor(boss)) do
        if self:IsMine(a) then out[#out + 1] = a end
    end
    return out
end

--- The plan's boss with this name, whatever the capitals; nil for a name that is secret or no boss.
function Plan:BossNamed(name)
    if type(name) ~= "string" or GuildOS.Compat.IsSecret(name) or name == "" then return nil end
    local want = name:lower()
    for _, b in ipairs(self:Bosses()) do
        if b:lower() == want then return b end
    end
    return nil
end

--- One task as a line: the kind, the target and the text the raid leader wrote.
function Plan:TaskLine(a)
    local parts = {}
    if a.kind and a.kind ~= "other" then parts[#parts + 1] = Plan.KINDS[a.kind] or a.kind end
    if a.target then parts[#parts + 1] = "{" .. a.target .. "}" end
    if a.note and a.note ~= "" then parts[#parts + 1] = a.note end
    return table.concat(parts, " · ")
end

----------------------------------------------------------------------
-- My task when I target a boss (out of combat)
----------------------------------------------------------------------

--- The boss to show my task for now, or nil: out of combat, a boss of the plan, a task of mine on
--- it, and not already shown in this raid.
function Plan:TaskToShow(targetName)
    if inCombat() then return nil end
    local plan, roster = self:Current()
    if not plan then return nil end
    local boss = self:BossNamed(targetName)
    if not boss or #self:MyTasks(boss) == 0 then return nil end
    self.shown = self.shown or {}
    local key = tostring(roster and roster.raidId) .. "|" .. boss
    if self.shown[key] then return nil end
    self.shown[key] = true
    return boss
end

function Plan:OnTargetChanged()
    if not (UnitExists and UnitExists("target")) then return end
    local ok, name = pcall(UnitName, "target")
    local boss = ok and self:TaskToShow(name)
    if boss and self.ShowTask then self:ShowTask(boss) end
end

function Plan:Initialize()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function() GuildOS:SafeCall(Plan.OnTargetChanged, Plan) end)
    self.frame = f
end

----------------------------------------------------------------------
-- The raid leader says a boss's note in raid chat
----------------------------------------------------------------------

function Plan:CanAnnounce()
    if inCombat() then return false, L["Not during combat."] end
    if not IsInRaid() then return false, L["You are not in a raid."] end
    if not (UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
        return false, L["Only the raid leader or an assistant can say it in raid chat."]
    end
    return true
end

--- The note cut into chat lines on spaces, the boss's name first.
function Plan:AnnounceLines(boss)
    local note = self:NoteFor(boss)
    if not note then return {} end
    local lines, cur = {}, boss .. ": "
    for word in note:gsub("%s+", " "):gmatch("%S+") do
        if #cur + #word + 1 > CHAT_LINE then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = (cur:sub(-2) == ": " or cur == "") and (cur .. word) or (cur .. " " .. word)
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

--- Say the note in raid chat. Returns (lines said, err).
function Plan:Announce(boss)
    local ok, why = self:CanAnnounce()
    if not ok then return nil, why end
    local lines = self:AnnounceLines(boss)
    if #lines == 0 then return nil, L["This boss has no note."] end
    local said = 0
    for _, line in ipairs(lines) do
        if GuildOS.Compat.SendChatMessage(line, "RAID") then said = said + 1 end
    end
    return said
end
