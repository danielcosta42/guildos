----------------------------------------------------------------------
-- Guild OS - Roster Frame
-- Premium guild roster UI with modern visual design
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

-- An officer note from the roster's right-click menu (issue #49). data = { key, name }: the
-- key is the roster's own, the one the member sheet reads notes by.
local function SaveOfficerNote(data, text)
    text = text and strtrim(text) or ""
    if not data or text == "" or not GuildOS.OfficerNotes then return end
    if GuildOS.OfficerNotes:AddNote(data.key, text) then
        GuildOS:Print(L["Note added for "] .. data.name)
        GuildOS:RefreshRosterUI()   -- the GOS NOTE column (#178)
    end
end

GuildOS.Dialogs["GUILDOS_OFFICER_NOTE"] = {
    text = L["Officer note for %s"],
    button1 = L["Save"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 200,
    -- The box through Compat: WoW: Forever's popup has no `editBox`.
    OnShow = function(self)
        local box = GuildOS.Compat.PopupEditBox(self)
        if box then box:SetText(""); box:SetFocus() end
    end,
    OnAccept = function(self, data)
        local box = GuildOS.Compat.PopupEditBox(self)
        SaveOfficerNote(data, box and box:GetText())
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        local dialog = editBox:GetParent()
        SaveOfficerNote(data or dialog.data, editBox:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- The public note everybody sees, from the same menu (issue #162). data = { name, realm }; the
-- module writes it, and an empty box clears it. No text at all is a box that could not be read, not
-- an empty one: the member's note stays.
local function SavePublicNote(data, text)
    if not data or text == nil or not GuildOS.NoteCommand then return end
    GuildOS.NoteCommand:Set(data.name, data.realm, strtrim(text))
end

GuildOS.Dialogs["GUILDOS_PUBLIC_NOTE"] = {
    text = L["Note for %s, which everyone in the guild sees"],
    button1 = L["Save"], button2 = CANCEL,
    -- The game's cap on a public note. Letters here; the bytes are capped when it opens, below.
    hasEditBox = true, maxLetters = 31,
    -- The box is the popup's own and other dialogs share it: the byte cap leaves with this one.
    OnHide = function(self)
        local box = GuildOS.Compat.PopupEditBox(self)
        if box then box:SetMaxBytes(0) end
    end,
    OnAccept = function(self, data)
        local box = GuildOS.Compat.PopupEditBox(self)
        SavePublicNote(data, box and box:GetText())
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        local dialog = editBox:GetParent()
        SavePublicNote(data or dialog.data, editBox:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Opens the public note's box with the note as it reads now, filled in after the popup is up: when
-- `data` reaches OnShow differs between clients, and the box should never open empty over a note.
local function ShowPublicNote(data)
    local dialog = GuildOS:ShowDialog("GUILDOS_PUBLIC_NOTE", data.name, nil, { name = data.name, realm = data.realm })
    local box = dialog and GuildOS.Compat.PopupEditBox(dialog)
    if box then
        -- The write cuts at 31 bytes; a box that takes 31 letters would let an accented or Cyrillic
        -- note be cut short without a word. +1: the cap counts the terminator.
        box:SetMaxBytes(GuildOS.NoteCommand.NOTE_MAX + 1)
        box:SetText(GuildOS.NoteCommand:Current(data.name, data.realm))
        box:SetFocus()
        box:HighlightText()
    end
end

-- Returns -1 if a < b, 0 if equal, 1 if a > b (semver major.minor.patch)
local function CompareVersions(a, b)
    local function parts(v)
        local maj, min, pat = strsplit(".", v or "0")
        return tonumber(maj) or 0, tonumber(min) or 0, tonumber(pat) or 0
    end
    local a1, a2, a3 = parts(a)
    local b1, b2, b3 = parts(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end

----------------------------------------------------------------------
-- Guild OS on each member, and the founders (#449, membros-mockup): the marks beside a name, the Guild OS
-- column, the rail's filters, the tiles and the legend all read one scan of the guild per refresh.
--   status   "cur": runs the newest version seen in the guild; "old": an older one; "none": this client never
--            heard Guild OS from them (no lastUpdate in db.members: the test Without GuildOS and the bulk
--            actions use)
--   version  the live one the mesh hears, else the one their last sync stored
--   latest   the newest plain x.y.z among this client's own version, the newest CommSystem heard on the guild
--            channel and every member's. The addon cannot see CurseForge: "latest" is the newest seen in the
--            guild, and the tooltip says so.
-- Founders are Modules/Founding.lua's (WoW: Forever only): everyone else has no founder mark or filter.
----------------------------------------------------------------------
local PLAIN_VERSION = "^%d+%.%d+%.%d+$"
local Marks = {}
UI.RosterMarks = Marks
Marks.SIZE = 18
Marks.ART = { cur = "mark-crest", old = "mark-warn", founder = "mark-banner" }
-- The mockup's amber (an older version): the mark's glyph, the Guild OS column's "· update".
Marks.AMBER = { r = 0.941, g = 0.722, b = 0.314 }

-- The newer plain version of a and b; either may be nil or not plain (a beta, a dev build): ignored.
function Marks.Newer(a, b)
    local okA = type(a) == "string" and a:match(PLAIN_VERSION) ~= nil
    local okB = type(b) == "string" and b:match(PLAIN_VERSION) ~= nil
    if not okA then return okB and b or nil end
    if not okB then return a end
    return CompareVersions(a, b) >= 0 and a or b
end

-- "cur", "old" or "none". A version that is not plain is never called old.
function Marks.Status(installed, version, latest)
    if not installed then return "none" end
    if type(version) == "string" and version:match(PLAIN_VERSION) and latest and CompareVersions(version, latest) < 0 then
        return "old"
    end
    return "cur"
end

-- The member's version as the roster reads it.
function Marks.VersionOf(shortName, addonData)
    local M = GuildOS.Mesh
    return (M and M.GetPeerVersion and M:GetPeerVersion(shortName)) or (addonData and addonData.addonVersion)
end

-- The guild roster once: byKey[key] = { status, version }, count.cur/old/none, latest, and `oldest` (the oldest
-- version anyone runs, for the legend's tooltip).
function Marks.Scan()
    local members = GuildOS.db.members or {}
    local rows = {}
    local latest = Marks.Newer(GuildOS.VERSION, GuildOS.CommSystem and GuildOS.CommSystem.newestSeen)
    for i = 1, GetNumGuildMembers() or 0 do
        local name = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local key = GuildOS:GetPlayerKey(short, name:match("-(.+)$") or GetRealmName())
            local d = members[key]
            local r = { installed = (d and d.lastUpdate and d.lastUpdate > 0) and true or false, version = Marks.VersionOf(short, d) }
            rows[key] = r
            if r.installed then latest = Marks.Newer(latest, r.version) end
        end
    end
    local scan = { byKey = {}, latest = latest, count = { cur = 0, old = 0, none = 0 } }
    for key, r in pairs(rows) do
        local s = Marks.Status(r.installed, r.version, latest)
        scan.byKey[key] = { status = s, version = r.version }
        scan.count[s] = scan.count[s] + 1
        if s == "old" and (not scan.oldest or CompareVersions(r.version, scan.oldest) < 0) then scan.oldest = r.version end
    end
    return scan
end

-- A mark's tooltip: its title and its lines, each { text, colour }.
function Marks.Tooltip(kind, version, latest)
    if kind == "cur" then
        return L["Guild OS up to date"], {
            { string.format(L["Version %s. Syncs everything: attendance, loot, professions, alerts."], version or "?"), C.text },
        }
    elseif kind == "old" then
        return L["Guild OS out of date"], {
            { string.format(L["Version %s; the latest seen in the guild is %s. Some things may not sync until they update."],
                version or "?", latest or "?"), C.text },
            { string.format(L["Officers can send a reminder from %s."], L["Officers' Room"] .. " › " .. L["Without GuildOS"]), C.textSoft },
        }
    elseif kind == "founder" then
        return L["Founder"], { { L["One of the people who founded the guild."], C.text } }
    end
end

function Marks.ShowTooltip(owner, kind, version, latest)
    local title, lines = Marks.Tooltip(kind, version, latest)
    if not title or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, C.gold2.r, C.gold2.g, C.gold2.b)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l[1], l[2].r, l[2].g, l[2].b, true) end
    GameTooltip:Show()
end

-- A mark: the 18px round chip of its art (Media/Salao/mark-*.tga), its tooltip under the cursor. `onClick`, if
-- given, takes its clicks (a row's mark clicks the row).
function Marks.Create(parent, onClick)
    local m = CreateFrame("Button", nil, parent)
    m:SetSize(Marks.SIZE, Marks.SIZE)
    m.tex = GuildOS.Style:Texture(m, "mark-crest", "ARTWORK")
    m.tex:SetAllPoints()
    function m:SetKind(kind, version, latest)
        self.kind, self.version, self.latest = kind, version, latest
        self.tex:SetTexture(GuildOS.Style.ART[Marks.ART[kind] or "mark-crest"])
    end
    m:SetScript("OnEnter", function(self) Marks.ShowTooltip(self, self.kind, self.version, self.latest) end)
    m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if onClick then
        m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        m:SetScript("OnClick", onClick)
    end
    return m
end

-- The width a FontString's text takes, whatever width it was given.
local function textW(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    return math.ceil(w or 0)
end

-- Every column the table can draw (issue #178). Which of them show, and in what order, is each
-- account's (Modules/RosterColumns.lua); Member is always first.
--   label     the header; `name`, the line in the Columns panel
--   min       narrowest the column may be drawn
--   weight    share of any leftover width (0 = never grows past min)
--   align     of the header and the cell
--   asc       the first click sorts A to Z (otherwise highest first)
--   offered   whether this reader may show it here (nil = always)
--   value     (data, ctx) -> the sort value, filled into data.cols only for the columns shown or
--             sorted by; nil sorts last. The first eight draw themselves in UpdateRosterRow, the
--             rest through
--   text      (value, data) -> the cell's text and, optionally, its colour
--   num       the cell holds a number: drawn through the tableNum role (#363)
--   prepare   (ctx) once per refresh, before any value: an index where a per-row read would scan
-- Resolved per resize by UI:ResolveColumns (UI/Layout.lua): the rightmost shown column goes first
-- as the window narrows, and only Member is never dropped.
--
-- The former unlabelled 20px "status" column folded into `name`: the
-- online dot is drawn inside the name cell, so it is not something the
-- user can lose to a narrow window.
local DASH = "|cff666666-|r"
local function textOr(s) return (s and s ~= "") and s or nil end
local function officer() return GuildOS:IsOfficer() end
local function enabled(feature) return GuildOS:IsFeatureEnabled(feature) end
local ROLE_TINT = { TANK = C.blue, HEALER = C.green, DPS = C.red }
local ROLE_LETTER = { TANK = "T", HEALER = "H", DPS = "D" }
local ROLE_ORDER = { "TANK", "HEALER", "DPS" }
local function versionNumber(v)
    local a, b, c = strsplit(".", v or "")
    return (tonumber(a) or 0) * 1e6 + (tonumber(b) or 0) * 1e3 + (tonumber(c) or 0)
end

local COLUMNS = {
    { key = "name",        label = L["MEMBER"],      name = L["Member"],      min = 170, weight = 3, align = "LEFT", asc = true },
    { key = "level",       label = L["LVL"],         name = L["Level"],       min = 34,  weight = 0, align = "CENTER" },
    { key = "class",       label = L["CLASS"],       name = L["Class"],       min = 74,  weight = 1, align = "LEFT" },
    { key = "avgIlvl",     label = L["iLVL"],        name = L["Item level"],  min = 46,  weight = 0, align = "CENTER",
      value = function(d) return d.avgIlvl > 0 and d.avgIlvl or nil end },
    { key = "race",        label = L["RACE"],        name = L["Race"],        min = 70,  weight = 1, align = "LEFT",
      value = function(d) return textOr(d.race) end },
    { key = "lastSeen",    label = L["LAST SEEN"],   name = L["Last seen"],   min = 78,  weight = 1, align = "RIGHT",
      value = function(d) return d.lastUpdate > 0 and d.lastUpdate or nil end },
    { key = "professions", label = L["PROFESSIONS"], name = L["Professions"], min = 160, weight = 2, align = "LEFT", asc = true,
      value = function(d)
          local names = {}
          for _, p in ipairs(d.professions or {}) do
              if p.isPrimary then names[#names + 1] = L[p.name] end
          end
          return textOr(table.concat(names, " "))
      end },
    { key = "zone",        label = L["ZONE"],        name = L["Zone"],        min = 120, weight = 2, align = "LEFT", asc = true,
      value = function(d) return d.isOnline and textOr(d.zone) or nil end },

    -- The game's own, for every member.
    { key = "note",        label = L["NOTE"],         name = L["Public note"],  min = 120, weight = 2, align = "LEFT", asc = true,
      value = function(d) return textOr(d.note) end,
      text = function(v) return v, C.silver end },
    { key = "officerNote", label = L["OFFICER NOTE"], name = L["Officer note"], min = 120, weight = 2, align = "LEFT", asc = true,
      offered = function() return GuildOS.Compat.CanViewOfficerNote() end,
      value = function(d) return textOr(d.officerNote) end,
      text = function(v) return v, C.silver end },
    { key = "rank",        label = L["RANK"],         name = L["Rank"],         min = 80,  weight = 1, align = "LEFT", asc = true,
      value = function(d) return d.rankIndex end,
      text = function(_, d) return d.rank, C.silver end },
    -- The game's last login, so it answers for members without the addon too; Last seen is the
    -- addon's last snapshot of them.
    { key = "offline",     label = L["OFFLINE"],      name = L["Offline for"],  min = 84,  weight = 0, align = "RIGHT",
      offered = function() return GuildOS.GuildManager ~= nil end,
      value = function(d)
          if d.isOnline then return 0 end
          return GuildOS.GuildManager:GetDaysOffline(d.index)
      end,
      text = function(v, d)
          if d.isOnline then return L["|cff4CFF4CNow|r"] end
          return GuildOS:TimeAgo(time() - math.floor(v * 86400)), C.silver
      end },

    -- What Guild OS syncs: only members who run it.
    { key = "spec",        label = L["SPEC"],         name = L["Spec"],         min = 90,  weight = 1, align = "LEFT", asc = true,
      offered = function() return GuildOS.SpecChecker ~= nil end,
      -- By the tree, so a spec groups together; the points follow it, where a narrow cell cuts.
      -- The points ride on the row: a scroll redraws it without a refresh, after a sync may have
      -- taken the spec away.
      value = function(d)
          local m = GuildOS.db.members[d.key]
          local spec = m and m.spec
          d.specPoints = spec and type(spec.points) == "table" and #spec.points > 0 and table.concat(spec.points, "/") or nil
          return spec and textOr(GuildOS.SpecChecker:SpecName(spec)) or nil
      end,
      text = function(v, d)
          return d.specPoints and (v .. " " .. d.specPoints) or v, C.silver
      end },
    { key = "roles",       label = L["ROLES"],        name = L["Roles"],        min = 50,  weight = 0, align = "CENTER", asc = true,
      offered = function() return GuildOS.RaiderRoster ~= nil end,
      value = function(d)
          local roles, s = GuildOS.RaiderRoster:EffectiveRoles(d.key), ""
          for _, r in ipairs(ROLE_ORDER) do
              if roles[r] then s = s .. ROLE_LETTER[r] end
          end
          return textOr(s)
      end,
      text = function(v, d)
          if not d.isOnline then return v end   -- greyed like the rest of an offline row
          local out = ""
          for _, r in ipairs(ROLE_ORDER) do
              local t = ROLE_TINT[r]
              if v:find(ROLE_LETTER[r], 1, true) then out = out .. GuildOS:ColorText(ROLE_LETTER[r], t.r, t.g, t.b) end
          end
          return out
      end },
    { key = "main",        label = L["MAIN"],         name = L["Main or alt"],  min = 90,  weight = 1, align = "LEFT", asc = true,
      offered = function() return GuildOS.AltRoster ~= nil end,
      prepare = function(ctx)
          ctx.links = GuildOS.db.altLinks or {}
          ctx.hasAlts = {}
          for _, main in pairs(ctx.links) do ctx.hasAlts[main] = true end
      end,
      value = function(d, ctx)
          local main = ctx.links[d.key]
          if main then return main:match("^([^-]+)") or main end
          return ctx.hasAlts[d.key] and L["Main"] or nil
      end,
      text = function(v) return v, C.silver end },
    -- The member's own (issue #428), the same on every character of the group; by the date in the year.
    { key = "birthday",    label = L["BIRTHDAY"],     name = L["Birthday"],     min = 64,  weight = 0, align = "CENTER", asc = true, num = true,
      offered = function() return GuildOS.Birthdays ~= nil end,
      value = function(d)
          local b = GuildOS.Birthdays:For(d.key)
          d.birthday = b
          return b and (b.month * 100 + b.day) or nil
      end,
      text = function(_, d) return GuildOS.Birthdays:Text(d.birthday), C.silver end },
    -- Guild OS on the member (#449): the version in green, an older one in amber with "· update", or "not
    -- installed" in the dim ink (`empty`: what a member with no value reads). By the version; on by default for
    -- officers (Modules/RosterColumns.lua).
    { key = "version",     label = L["GUILD OS"],    name = L["Guild OS"],    min = 84,  weight = 0, align = "LEFT",
      value = function(d)
          if d.addonStatus ~= "cur" and d.addonStatus ~= "old" then return nil end
          return d.addonVersion and versionNumber(d.addonVersion) or 0
      end,
      text = function(_, d)
          if d.addonStatus == "old" then return string.format(L["%s · update"], d.addonVersion or "?"), Marks.AMBER end
          return d.addonVersion or "?", C.ok
      end,
      empty = function(d) if not d.allied then return L["not installed"], C.labelDim end end },   -- an ally's: unknown
    { key = "enchants",    label = L["ENCHANTS"],     name = L["Missing enchants"], min = 84, weight = 0, align = "CENTER", num = true,
      offered = function() return GuildOS.GearAudit ~= nil end,
      value = function(d) return d.gear and #GuildOS.GearAudit:MissingEnchants(d.gear) or nil end,
      text = function(v) return v, v > 0 and C.red or C.green end },
    -- Retail (issue #187): the rating in the game's colour, then the keystone's level. By the rating.
    { key = "mplus",       label = L["M+"],           name = L["Mythic+ rating and keystone"], min = 70, weight = 0, align = "CENTER", num = true,
      offered = function() return GuildOS.MythicPlus ~= nil end,
      value = function(d)
          d.keyLevel = GuildOS.MythicPlus:KeyLevel(d.mplus)
          return GuildOS.MythicPlus:Rating(d.mplus)
      end,
      text = function(v, d)
          local r, g, b = GuildOS.Compat.RatingColor(v)
          local text = d.keyLevel and (v .. " |cff999999+" .. d.keyLevel .. "|r") or tostring(v)
          return text, r and { r = r, g = g, b = b } or C.text
      end },

    -- The modules'.
    { key = "attendance",  label = L["ATT."],         name = L["Attendance"],   min = 50,  weight = 0, align = "CENTER", num = true,
      offered = function() return GuildOS.RaidTracker ~= nil and enabled("raidTracker") end,
      prepare = function(ctx) ctx.totals = {} end,
      value = function(d, ctx) return GuildOS.RaidTracker:GetAttendance25ManPercent(d.key, nil, ctx.totals) end,
      text = function(v)
          if v == 0 then return DASH end
          return v .. "%", v >= 75 and C.green or (v >= 50 and C.warn or C.red)
      end },
    { key = "core",        label = L["CORE"],         name = L["Core"],         min = 90,  weight = 1, align = "LEFT", asc = true,
      offered = function() return GuildOS.CoreManager ~= nil end,
      prepare = function(ctx)
          ctx.cores = {}
          for _, coreName in ipairs(GuildOS.CoreManager:GetSortedNames()) do
              for key in pairs(GuildOS.CoreManager:GetMembers(coreName)) do
                  local list = ctx.cores[key] or {}
                  list[#list + 1] = coreName
                  ctx.cores[key] = list
              end
          end
      end,
      value = function(d, ctx) return ctx.cores[d.key] and table.concat(ctx.cores[d.key], " / ") or nil end,
      text = function(v) return v, C.text end },
    { key = "dkp",         label = L["DKP"],          name = L["DKP"],          min = 50,  weight = 0, align = "CENTER", num = true,
      offered = function() return GuildOS.Points ~= nil and GuildOS:LootSystemShowsDKP() end,   -- off with the DKP switch (B25)
      value = function(d) return GuildOS.Points:Get(d.key) end,
      text = function(v) return v, C.text end },
    { key = "loot",        label = L["LOOT"],         name = L["Loot received"], min = 46, weight = 0, align = "CENTER", num = true,
      offered = function() return GuildOS.LootTracker ~= nil and enabled("lootTracker") end,
      prepare = function(ctx)
          ctx.loot = {}
          for _, e in ipairs(GuildOS.db.lootHistory or {}) do
              if e.playerKey then ctx.loot[e.playerKey] = (ctx.loot[e.playerKey] or 0) + 1 end
          end
      end,
      value = function(d, ctx) return ctx.loot[d.key] or 0 end,
      text = function(v) return v, C.silver end },

    -- Officers only.
    { key = "trial",       label = L["TRIAL"],        name = L["Trial days left"], min = 64, weight = 0, align = "CENTER", num = true,
      offered = function() return GuildOS.TrialTracker ~= nil and enabled("trialTracker") and officer() end,
      value = function(d) return GuildOS.TrialTracker:GetDaysRemaining(d.key) end,
      text = function(v) return v .. "d", v > 14 and C.green or (v > 7 and C.warn or C.red) end },
    -- When the member's current passage started (issue #427, from the member history of #425): "~" when
    -- it is only when Guild OS saw them join.
    { key = "joined",      label = L["JOINED"],       name = L["Joined the guild"], min = 70, weight = 0, align = "RIGHT", num = true,
      offered = function() return GuildOS.MemberHistory ~= nil and officer() end,
      value = function(d) return (GuildOS.MemberHistory:JoinedAt(d.key)) end,
      text = function(v, d)
          local _, est = GuildOS.MemberHistory:JoinedAt(d.key)
          return (est and "~" or "") .. GuildOS:DateText(v, "/%y"), C.silver
      end },
    { key = "gosNote",     label = L["GOS NOTE"],     name = L["Guild OS officer note"], min = 140, weight = 2, align = "LEFT", asc = true,
      offered = function() return GuildOS.OfficerNotes ~= nil and enabled("officerNotes") and officer() end,
      value = function(d)
          local newest = GuildOS.OfficerNotes:GetNotes(d.key)[1]   -- AddNote inserts at the front
          return newest and textOr(newest.text) or nil
      end,
      text = function(v) return v, C.silver end },
}
local COLUMN_BY_KEY = {}
for _, c in ipairs(COLUMNS) do COLUMN_BY_KEY[c.key] = c end

-- Whether this reader may choose a column here. Member is not a choice.
local function offered(key)
    local c = COLUMN_BY_KEY[key]
    if not c or key == "name" then return false end
    return not c.offered or c.offered()
end

-- What UI:ResolveColumns lays out: Member, then the reader's columns, each worth one less than the
-- one on its left so the rightmost goes first. Also the keys in one string, to tell when it changed.
local function ChosenColumns()
    local spec = { { key = "name", min = COLUMN_BY_KEY.name.min, weight = COLUMN_BY_KEY.name.weight, priority = 100, required = true } }
    local keys = GuildOS.RosterColumns:Visible(offered)
    for i, key in ipairs(keys) do
        local c = COLUMN_BY_KEY[key]
        spec[#spec + 1] = { key = key, min = c.min, weight = c.weight, priority = 100 - i }
    end
    return spec, table.concat(keys, ",")
end

local SP = UI.SP
local ROW_HEIGHT = SP.ROW_AV   -- a row with its avatar (the standard's 32; the mockup's td)
local HEADER_HEIGHT = 24
-- The Members screen (#449, membros-mockup, the chosen variant): the six tiles across the top (two rows of three
-- under SP.TWO_COLS), then the filters in a dark rail on the left and the list card beside it. Under RAIL_STACK
-- the rail goes above the list, each group a title and its lines as pills, wrapping.
local TILE_H = 56
local KPI_GAP = 8
local RAIL_W = 210
local RAIL_STACK = 820
local RAIL_PAD_X = 10           -- the rail's side padding (the mockup's .rail: 14px 10px)
local ITEM_H = SP.HIT           -- a rail line: a click target
local ITEM_GAP = 2
local GROUP_GAP = 10            -- above a group's title
local HEAD_H = 14               -- a group's title
local FLOW_HEAD_W = 78          -- stacked: the column of the groups' titles
local RAIL_TOP_MAX = 0.45       -- stacked: the rail takes at most this share of the height, and scrolls past it
local TOOL_H = 28               -- the card's tools, on its title's line
local CHIP_H = 22
local CHIP_GAP = 6
local COL_GAP = 10              -- space between two table columns
local ROW_INSET = 10            -- x of the first column inside a row
local SCROLL_GUTTER = 18        -- rows stop short of the scrollbar
local LEGEND_H = 18             -- the marks' legend under the table
local LEGEND_GAP = 10           -- its rule, above it
-- Global frame names must stay unique if a builder ever runs twice. The
-- first instance keeps the historical names so nothing that hardcodes them breaks.
local rosterInstances = 0
-- Every roster panel built, so a change of columns lays them all out again (#178).
local rosterPanels = {}
-- And the frame each one keeps its state on, so the member sheet closing clears every selection (#377).
local rosterHosts = {}

local function ClearSelection()
    for _, h in ipairs(rosterHosts) do
        if h.selectedKey then
            h.selectedKey = nil
            h:UpdateRows()
        end
    end
end

-- The invite field (#377): it left the window's footer for the Members bar. The host's
-- LayoutToolbar shows it to who may invite.
local function InviteField(parent)
    local holder = CreateFrame("Frame", nil, parent)
    local box = UI:CreateInput(holder, 130, 22, { max = 50, placeholder = L["Player name..."] })
    box:SetPoint("LEFT", 0, 0)
    local btn = UI:SetButtonVariant(UI:CreateButton(holder, L["Invite"], 64, 22), "primary")
    btn:SetPoint("LEFT", box, "RIGHT", 4, 0)

    local function invite()
        local target = strtrim(box:GetText() or "")
        if target == "" then
            GuildOS:Print(L["Enter a player name to invite."])
            return
        end
        local function send()
            if GuildOS.Compat.GuildInvite(target) then GuildOS:Print(string.format(L["Guild invite sent to %s."], target)) end
        end
        -- The alliance has banned them: the officer reads why first (#408).
        local BL = GuildOS.BanList
        if not (BL and BL.HoldInvite and BL:HoldInvite(target, send)) then send() end
        box:SetText("")
    end
    btn:SetScript("OnClick", function() invite(); box:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) invite(); self:ClearFocus() end)

    holder:SetSize(130 + 4 + btn:GetWidth(), 22)   -- the invite label may have grown its button (issue #28)
    holder.box, holder.button = box, btn
    return holder
end
-- Same reason as rosterInstances: the recruitment builder also runs once
-- per container, and its scroll frame needs a globally unique name.
local recruitInstances = 0

----------------------------------------------------------------------
-- Re-apply loot-system-dependent visibility (the DKP and wishlist tabs)
-- without a reload. Called when the loot system changes.
----------------------------------------------------------------------
function GuildOS:UpdateLootSystemUI()
    local f = self.RosterFrame
    if f then f:UpdateTabVisibility() end
end

----------------------------------------------------------------------
----------------------------------------------------------------------
-- Raid Hub: single container with a sub-tab bar that hosts the four
-- raid-related panels (Sessions, Cores, Audit, Raid Tools).
----------------------------------------------------------------------
function GuildOS:CreateRaidHubPanel(container, mainFrame)
    local SUB_H = 28  -- sub-tab bar height

    ----------------------------------------------------------------
    -- Sub-tab bar
    ----------------------------------------------------------------
    local subBar = CreateFrame("Frame", nil, container)
    subBar:SetPoint("TOPLEFT", 0, 0)
    subBar:SetPoint("TOPRIGHT", 0, 0)
    subBar:SetHeight(SUB_H)

    UI:StyleSubTabBar(subBar)

    ----------------------------------------------------------------
    -- Sub-panels (all fill the area below the sub-tab bar)
    ----------------------------------------------------------------
    local function MakeSubPanel()
        local p = CreateFrame("Frame", nil, container)
        p:SetPoint("TOPLEFT", 0, -SUB_H)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        p:Hide()
        return p
    end

    local sessPanel    = MakeSubPanel()
    local raidersPanel = MakeSubPanel()
    local coresPanel   = MakeSubPanel()
    local auditPanel   = MakeSubPanel()
    local rtPanel      = MakeSubPanel()

    -- Populate each sub-panel using the existing builders
    GuildOS:CreateRaidsPanel(sessPanel, mainFrame)
    if GuildOS.CreateRaiderPanel then GuildOS:CreateRaiderPanel(raidersPanel, mainFrame) end
    GuildOS:CreateCoresPanel(coresPanel)           -- new signature (no contentTop)
    GuildOS:CreateAuditPanel(auditPanel, mainFrame)
    GuildOS:CreateRaidToolsPanel(rtPanel, mainFrame)

    ----------------------------------------------------------------
    -- Sub-tab definitions (Cores is officer-only)
    ----------------------------------------------------------------
    local SUBTABS = {
        { key = "sessions",  label = L["Sessions"],   panel = sessPanel,    officerOnly = false },
        { key = "raiders",   label = L["Raiders"],    panel = raidersPanel, officerOnly = false },
        { key = "cores",     label = L["Cores"],      panel = coresPanel,   officerOnly = true  },
        { key = "audit",     label = L["Audit"],      panel = auditPanel,   officerOnly = false },
        { key = "raidtools", label = L["Raid Tools"], panel = rtPanel,      officerOnly = false },
    }

    local activeSubTab = nil
    local subTabBtns   = {}

    local function SetSubTab(key)
        -- Defence at the selection point: the button for an officer-only
        -- sub-tab is simply never drawn for non-officers, but SelectSub is
        -- also reachable directly (deep link from /gos open raids <sub>),
        -- so a non-officer key must be refused here too.
        for _, st in ipairs(SUBTABS) do
            if st.key == key and st.officerOnly and not GuildOS:IsOfficer() then return end
        end
        activeSubTab = key
        for _, t in ipairs(subTabBtns) do t:SetActive(t.key == key) end
        for _, st in ipairs(SUBTABS) do
            if st.key == key then st.panel:Show() else st.panel:Hide() end
        end
    end

    local prevBtn = nil
    for _, st in ipairs(SUBTABS) do
        -- Skip officer-only sub-tabs for non-officers
        local visible = not st.officerOnly or GuildOS:IsOfficer()
        if visible then
            local btn = UI:CreateTab(subBar, st.label, 110, true)
            if prevBtn then
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
            else
                btn:SetPoint("LEFT", 4, 0)
            end
            btn.key = st.key
            btn:SetScript("OnClick", function() SetSubTab(st.key) end)

            subTabBtns[#subTabBtns + 1] = btn
            prevBtn = btn
        end
    end

    -- Core Sign-up (#377): it left the window's footer for the screen it belongs to, at the right of
    -- the sub-tab bar so every Raids sub-tab has it. Any member signs up, so no rank gate. Where the
    -- window is too narrow for it beside the tabs it stands down; /gos signup still opens it.
    local signup = UI:CreateButton(subBar, L["Core Sign-up"], 110, 22)
    signup:SetPoint("RIGHT", subBar, "RIGHT", -UI.GAP, 0)
    signup:SetScript("OnClick", function()
        if GuildOS.ShowCoreSignupFrame then GuildOS:ShowCoreSignupFrame() end
    end)
    container.signupButton = signup
    UI:MakeResponsive(subBar, function(_, w)
        local used = 4
        for _, t in ipairs(subTabBtns) do used = used + t:GetWidth() + 2 end
        signup:SetShown(used + UI.GAP + signup:GetWidth() + UI.GAP <= w)
    end)

    -- Default to Sessions sub-tab
    container:SetScript("OnShow", function()
        if not activeSubTab then
            SetSubTab("sessions")
        end
    end)

    SetSubTab("sessions")

    -- Exposed so the hub and /gos can deep-link a sub-tab (same contract as
    -- CommunityPanel / AlliancePanel).
    container.SelectSub = SetSubTab
    -- Raids' entries open these sub-tabs themselves (#445): the bar goes, Core Sign-up is the room's entry.
    UI:CollapsibleSubBar(container, subBar, function()
        local t = {}
        for _, st in ipairs(SUBTABS) do t[st.key] = st.panel end
        return t
    end)
end

----------------------------------------------------------------------
-- Roster panel: KPI band + left rail + member table.
-- `parent` is the container to fill; `host` is the frame that owns the
-- roster's state and methods (the main window in expanded mode, the
-- floating window otherwise). Both containers expose the same
-- navigation interface, so nothing in here needs to know which it got.
----------------------------------------------------------------------
function GuildOS:CreateRosterPanel(parent, host)
    host = host or parent
    rosterInstances = rosterInstances + 1
    local uid = rosterInstances > 1 and tostring(rosterInstances) or ""
    rosterPanels[#rosterPanels + 1] = parent
    rosterHosts[#rosterHosts + 1] = host
    parent:HookScript("OnHide", function() GuildOS:HideColumnsPanel() end)

    ----------------------------------------------------------------
    -- The tiles (the mockup's .tiles): six across the whole width, two rows of three on a narrow window
    ----------------------------------------------------------------
    local kpiBand = CreateFrame("Frame", nil, parent)
    kpiBand:SetPoint("TOPLEFT", 0, 0)
    kpiBand:SetPoint("TOPRIGHT", 0, 0)
    kpiBand:SetHeight(TILE_H)
    host.kpiBand = kpiBand
    host.kpiCards = {}

    -- A small dark tile: the number in the title serif and the soft gold, its caption under it in the soft
    -- ink. subLabelText: optional, beside the caption in the dim ink ("of 62 chars" beside "players"). Returns
    -- the value FontString, and the sub-label FontString if requested. Placed by the layout pass.
    local function MakeKpiCard(key, labelText, valueColor, subLabelText)
        local card = UI:CreatePanel(kpiBand)
        -- CreatePanel pins level to 1; raise it above the main window's
        -- backdrop (level ~10) so the card and its text are actually visible.
        card:SetFrameLevel((kpiBand:GetFrameLevel() or 1) + 1)
        card:SetHeight(TILE_H)
        host.kpiCards[key] = card

        local value = card:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(value, nil, "metricValue")
        value:SetShadowOffset(0, 0)
        value:SetTextColor(valueColor.r, valueColor.g, valueColor.b)
        value:SetText("—")
        value:SetPoint("TOPLEFT", 12, -8)

        local lbl = UI:CreateText(card, labelText, SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        lbl:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -3)
        lbl:SetWordWrap(false)
        card.label = lbl

        local sub
        if subLabelText ~= nil then
            sub = UI:CreateText(card, subLabelText, SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            sub:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
            sub:SetWordWrap(false)
        end
        return value, sub
    end

    host.kpiMembers = MakeKpiCard("members", L["members"],            C.gold2)
    host.kpiPlayers, host.kpiPlayersSub =
                      MakeKpiCard("players", L["players"],            C.gold2, "—")
    host.kpiOnline  = MakeKpiCard("online",  L["online"],             C.online)
    host.kpiIlvl    = MakeKpiCard("ilvl",    L["average iLvl"],       C.gold2)
    host.kpiAtt     = MakeKpiCard("att",     L["average attendance"], C.gold2)
    host.kpiAddon, host.kpiAddonSub =
                      MakeKpiCard("addon",   L["with Guild OS"],      C.gold2, "")
    local KPI_ORDER = { "members", "players", "online", "ilvl", "att", "addon" }

    -- Lays the tiles out in `w`; returns the band's height with the gap under it.
    function host:LayoutTiles(w)
        local cols = w >= SP.TWO_COLS and 6 or 3
        local rows = math.ceil(#KPI_ORDER / cols)
        local tw = (w - (cols - 1) * KPI_GAP) / cols
        for i, key in ipairs(KPI_ORDER) do
            local card = self.kpiCards[key]
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", kpiBand, "TOPLEFT", math.floor(col * (tw + KPI_GAP) + 0.5), -row * (TILE_H + KPI_GAP))
            card:SetWidth(math.floor(tw + 0.5))
            card:Show()
        end
        local h = rows * TILE_H + (rows - 1) * KPI_GAP
        kpiBand:SetHeight(h)
        return h + SP.GAP
    end

    ----------------------------------------------------------------
    -- The filters: a dark rail card with the metal line (the mockup's .rail), its groups in a scroll frame
    -- (a guild with many ranks is taller than the window). `rail` is the scroll child.
    ----------------------------------------------------------------
    local railCard = UI:CreateCard(parent, "", { dark = true })
    railCard.title:Hide()
    railCard:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    railCard:SetPoint("TOPLEFT", 0, -(TILE_H + SP.GAP))
    railCard:SetSize(RAIL_W, 200)
    host.railCard = railCard
    local railScroll, rail = UI:CreateScrollFrame(railCard, "GuildOSRosterRail" .. uid)
    railScroll:SetPoint("TOPLEFT", RAIL_PAD_X, -SP.PAD)
    railScroll:SetPoint("BOTTOMRIGHT", -RAIL_PAD_X, SP.PAD)
    host.railScroll, host.rail = railScroll, rail

    -- A group's title: the serif, small, in the soft gold.
    local function head(text)
        local fs = UI:CreateHeaderText(rail, text, SP.META)
        fs:SetTextColor(C.gold2.r, C.gold2.g, C.gold2.b)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    local heads = { view = head(L["View"]), addon = head(L["Guild OS"]), ranks = head(L["Ranks"]), classes = head(L["Classes"]) }
    host.railHeads = heads

    -- A line of the rail (the mockup's .ri): its label on the left, its count on the right, nothing behind it at
    -- rest; the chosen one is the gold pill. b:Natural() is the width it asks for, b:Fit(w) gives it one.
    local function railItem(text, onClick)
        local b = UI:SetButtonVariant(UI:CreateButton(rail, text, 60, ITEM_H), "chip")
        b.baseBorder = nil
        b:SetBaseColor(0, 0, 0, 0)
        GuildOS:ApplyFont(b.label, SP.BODY)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 9, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        b.count = UI:CreateText(b, "", SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b)
        b.count:SetPoint("RIGHT", -9, 0)
        b.count:SetJustifyH("RIGHT")
        b.padL, b.padR = 9, 9
        function b:Natural() return self.padL + textW(self.label) + 8 + textW(self.count) + self.padR end
        function b:Fit(w)
            self:SetWidth(w)
            self.label:SetWidth(math.max(10, math.min(textW(self.label), w - self.padL - 8 - textW(self.count) - self.padR)))
        end
        function b:SetActive(active)
            self.active = active and true or false
            UI:SetSelected(self, active)
            local c = active and C.onGold or C.labelDim
            self.count:SetTextColor(c.r, c.g, c.b)
        end
        b:SetScript("OnClick", onClick)
        return b
    end

    host.segment = "all"     -- the view: "all" | "online" | "allied"
    host.foundersOnly = false
    host.addonFilter = nil   -- "cur" | "old" | "none" | nil
    host.rankFilter = nil    -- a rank's index or nil
    host.classFilter = nil   -- classFile or nil

    host.segBtns = {
        all = railItem(L["All"], function() host:SetSegment("all") end),
        online = railItem(L["Online"], function() host:SetSegment("online") end),
        allied = railItem(L["From the alliance"], function() host:SetSegment("allied") end),
    }
    host.segBtns.allied:Hide()
    host.foundersBtn = railItem(L["Founders"], function() host:SetFounders(not host.foundersOnly) end)
    host.addonBtns = {
        cur = railItem(L["Up to date"], function() host:SetAddonFilter("cur") end),
        old = railItem(L["Out of date"], function() host:SetAddonFilter("old") end),
        none = railItem(L["Not installed"], function() host:SetAddonFilter("none") end),
    }
    host.rankBtns = {}       -- pooled, filled in UpdateRail
    host.classChips = {}

    -- Show offline (the toolbar's toggle before): a box in the View group, saved between sessions.
    local offlineBtn = UI:CreateCheckbox(rail, L["Show Offline"], ITEM_H)
    offlineBtn.checkbox:SetChecked(GuildOS.db.settings.showOffline ~= false)
    offlineBtn.checkbox.onChanged = function(_, checked)
        GuildOS.db.settings.showOffline = checked and true or false
        host:RefreshRoster()
    end
    function offlineBtn:Natural() return ITEM_H + 6 + textW(self.label) + 4 end
    function offlineBtn:Fit(w) self:SetWidth(w) end
    host.offlineBtn = offlineBtn

    -- A class (the mockup's .cl): its icon, its name and how many.
    local CLASS_ORDER = GuildOS.Client.classes   -- thirteen on retail
    local function className(classFile)
        return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
    end
    for _, classFile in ipairs(CLASS_ORDER) do
        local b = railItem(className(classFile), function() host:SetClassFilter(classFile) end)
        GuildOS:ApplyFont(b.label, SP.BODY - 1)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 7, 0)
        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
            icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFile]))
        end
        b.icon = icon
        b.padL, b.padR = 7 + 16 + 6, 7
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", b.padL, 0)
        b.count:ClearAllPoints()
        b.count:SetPoint("RIGHT", -b.padR, 0)
        host.classChips[classFile] = b
    end

    -- Clear filters: every filter the rail and the search hold.
    local clearBtn = UI:SetButtonVariant(UI:CreateButton(rail, L["Clear filters"], 80, 18), "ghost")
    clearBtn:SetScript("OnClick", function() host:ClearFilters() end)
    function clearBtn:Natural() return textW(self.label) + 4 end
    function clearBtn:Fit() self:SetWidth(self:Natural()) end
    host.clearBtn = clearBtn

    -- The groups in order, each its title and the lines this guild and client have.
    function host:RailGroups()
        local view = { self.segBtns.all, self.segBtns.online }
        if self.alliedShown then view[#view + 1] = self.segBtns.allied end
        if GuildOS.Founding then view[#view + 1] = self.foundersBtn end
        view[#view + 1] = self.offlineBtn
        local ranks = {}
        for _, b in ipairs(self.rankBtns) do if b.inUse then ranks[#ranks + 1] = b end end
        local classes = {}
        for _, classFile in ipairs(CLASS_ORDER) do classes[#classes + 1] = self.classChips[classFile] end
        return {
            { head = heads.view, items = view },
            { head = heads.addon, items = { self.addonBtns.cur, self.addonBtns.old, self.addonBtns.none } },
            { head = heads.ranks, items = ranks },
            { head = heads.classes, items = classes, grid = true },
        }
    end

    -- Places the rail's groups in railInnerW: one column on the side (the classes two to a line), or, stacked
    -- above the list, a title column and the lines as pills wrapping after it. Returns the content's height.
    function host:LayoutRail()
        local w = self.railInnerW or (RAIL_W - 2 * RAIL_PAD_X)
        local placed = {}
        local function place(fr, x, y)
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", rail, "TOPLEFT", x, -y)
            placed[fr] = true
        end
        local y = 0
        local groups = self:RailGroups()
        if self.railMode ~= "top" then
            for _, g in ipairs(groups) do
                if #g.items > 0 then
                    if y > 0 then y = y + GROUP_GAP end
                    place(g.head, 8, y)
                    g.head:SetWidth(w - 8)
                    y = y + HEAD_H + 4
                    if g.grid then
                        local cw = math.floor((w - 4) / 2)
                        for i, b in ipairs(g.items) do
                            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
                            b:Fit(cw)
                            place(b, col * (cw + 4), y + row * (ITEM_H + ITEM_GAP))
                        end
                        y = y + math.ceil(#g.items / 2) * (ITEM_H + ITEM_GAP) - ITEM_GAP
                    else
                        for _, b in ipairs(g.items) do
                            b:Fit(w)
                            place(b, 0, y)
                            y = y + ITEM_H + ITEM_GAP
                        end
                        y = y - ITEM_GAP
                    end
                end
            end
            y = y + 8
            clearBtn:Fit()
            place(clearBtn, 8, y)
            y = y + 18
        else
            local last
            for _, g in ipairs(groups) do
                if #g.items > 0 then last = g end
            end
            for _, g in ipairs(groups) do
                if #g.items > 0 then
                    if y > 0 then y = y + 6 end
                    place(g.head, 0, y + (ITEM_H - HEAD_H) / 2)
                    g.head:SetWidth(FLOW_HEAD_W - 8)
                    local items = {}
                    for _, b in ipairs(g.items) do items[#items + 1] = b end
                    if g == last then items[#items + 1] = clearBtn end
                    local x, line = FLOW_HEAD_W, 0
                    for _, b in ipairs(items) do
                        local bw = math.min(b:Natural(), w - FLOW_HEAD_W)
                        if x > FLOW_HEAD_W and x + bw > w then x, line = FLOW_HEAD_W, line + 1 end
                        b:Fit(bw)
                        place(b, x, y + line * (ITEM_H + ITEM_GAP) + (b == clearBtn and (ITEM_H - 18) / 2 or 0))
                        x = x + bw + 4
                    end
                    y = y + (line + 1) * (ITEM_H + ITEM_GAP) - ITEM_GAP
                end
            end
        end
        -- Everything else the rail holds stays out of sight: a rank no longer used, From the alliance without
        -- the site's directory, Founders off WoW: Forever, an empty group's title.
        local all = { self.segBtns.all, self.segBtns.online, self.segBtns.allied, self.foundersBtn, self.offlineBtn,
                      self.addonBtns.cur, self.addonBtns.old, self.addonBtns.none, clearBtn,
                      heads.view, heads.addon, heads.ranks, heads.classes }
        for _, b in ipairs(self.rankBtns) do all[#all + 1] = b end
        for _, b in pairs(self.classChips) do all[#all + 1] = b end
        for _, fr in ipairs(all) do fr:SetShown(placed[fr] == true) end
        rail:SetSize(w, math.max(1, y))
        return y
    end

    ----------------------------------------------------------------
    -- The list: a dark card beside the rail (the mockup's .list): its title, "N of M", the tools on the same
    -- line; the active filters as chips; the table; the marks' legend under it.
    ----------------------------------------------------------------
    local listCard = UI:CreateCard(parent, L["Members"], { dark = true })
    listCard:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    listCard:SetPoint("TOPLEFT", RAIL_W + SP.GAP, -(TILE_H + SP.GAP))
    listCard:SetPoint("BOTTOMRIGHT", 0, 0)
    host.listCard = listCard
    -- The title keeps its own width: the tools share its line.
    listCard.title:ClearAllPoints()
    listCard.title:SetPoint("TOPLEFT", SP.PAD, -SP.PAD)

    local tableArea = CreateFrame("Frame", nil, listCard)
    tableArea:SetPoint("TOPLEFT", SP.PAD, -SP.TOP)
    tableArea:SetPoint("BOTTOMRIGHT", -SP.PAD, SP.PAD)
    host.tableArea = tableArea

    -- The tools, on the title's line (the mockup's .head): "N of M", the search, Columns, Analytics and, for who
    -- may invite, the invite field.
    local statsBar = CreateFrame("Frame", nil, listCard)
    statsBar:SetHeight(TOOL_H)
    host.statsBar = statsBar

    local resultText = UI:CreateText(statsBar, "", SP.BODY, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    resultText:SetJustifyH("LEFT")
    resultText:SetWordWrap(false)
    host.resultText = resultText

    -- Which columns, in what order (#178). A right click on the header opens the same panel.
    local columnsBtn = UI:CreateButton(statsBar, L["Columns"], 80, CHIP_H)
    columnsBtn:SetScript("OnClick", function(self) GuildOS:ToggleColumnsPanel(self) end)
    host.columnsBtn = columnsBtn

    -- Search box: the shared field (#371). Its placeholder, its gold border while typing and its
    -- Escape are the component's; the filter hooks the text.
    local searchBox = UI:CreateInput(statsBar, 190, 24, { max = 30, placeholder = L["Search / 60-70 / >=60"] })
    searchBox:HookScript("OnTextChanged", function(self)
        host.searchFilter = self:GetText()
        host:RefreshRoster()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    host.searchBox = searchBox

    -- The guild's make-up by class, level, rank and zone (`/gos analytics`): every command has a
    -- way in here too (#137).
    local analyticsBtn = UI:CreateButton(statsBar, L["Analytics"], 90, CHIP_H)
    analyticsBtn:SetScript("OnClick", function()
        if GuildOS.GuildAnalytics then GuildOS.GuildAnalytics:Show() end
    end)
    host.analyticsBtn = analyticsBtn

    local invite = InviteField(statsBar)
    host.inviteField = invite

    -- The tools left to right, placed by width as the table's columns are (#377): "N of M" takes what is left
    -- over and pushes the rest right; a narrow line drops it first, then Columns (a right click on the header
    -- opens it too), Analytics, the invite field and the search box. The invite field is only for who may
    -- invite: Anniversary and retail (#256, #449), at a rank that invites; read again on every refresh.
    local TOOLBAR_GAP = 8
    local TOOLBAR = {
        { key = "result",    frame = resultText,   priority = 20, weight = 1, min = 50 },
        { key = "search",    frame = searchBox,    priority = 90 },
        { key = "columns",   frame = columnsBtn,   priority = 30 },
        { key = "analytics", frame = analyticsBtn, priority = 50 },
        { key = "invite",    frame = invite,       priority = 70, invite = true },
    }
    function host:LayoutToolbar(cardW)
        cardW = cardW or self.listW
        if not cardW then return end   -- laid out on the first resize pass
        local titleW = textW(listCard.title)
        local x0 = SP.PAD + titleW + 12
        local w = math.max(0, cardW - SP.PAD - x0)
        statsBar:ClearAllPoints()
        statsBar:SetPoint("TOPLEFT", listCard, "TOPLEFT", x0, -(SP.PAD + SP.TITLE_H / 2 - TOOL_H / 2))
        statsBar:SetSize(w, TOOL_H)
        local spec, items = {}, {}
        for _, item in ipairs(TOOLBAR) do
            if not item.invite or GuildOS.Compat.AddonMayInvite() then
                items[#items + 1] = item
                spec[#spec + 1] = { key = item.key, min = item.min or item.frame:GetWidth(), weight = item.weight or 0,
                                    priority = item.priority }
            else
                item.frame:Hide()
            end
        end
        -- Each part shown or not, never hidden and shown again: this runs on every keystroke in the search and
        -- every roster update, and a hidden EditBox loses the keyboard (#377).
        local cols = UI:ResolveColumns(spec, w, TOOLBAR_GAP)
        local right = 0
        for _, col in ipairs(cols) do if col.shown then right = math.max(right, col.x + col.w) end end
        local shift = math.max(0, w - right)   -- with "N of M" gone, the tools still sit on the right
        for i, col in ipairs(cols) do
            local item = items[i]
            item.frame:SetShown(col.shown)
            if col.shown then
                item.frame:ClearAllPoints()
                item.frame:SetPoint("LEFT", statsBar, "LEFT", col.x + shift, 0)
                if item.weight then item.frame:SetWidth(col.w) end
            end
        end
    end

    -- The active filters as chips over the table (the mockup's .chips); a click takes that filter off.
    local activeBar = CreateFrame("Frame", nil, tableArea)
    activeBar:SetPoint("TOPLEFT", 0, 0)
    activeBar:SetPoint("TOPRIGHT", 0, 0)
    activeBar:SetHeight(CHIP_H)
    host.activeBar = activeBar
    host.activeChips = {}

    -- Column Headers (the mockup's th: the title serif, small, gold, a metal rule under them).
    local headerFrame = CreateFrame("Frame", nil, tableArea)
    headerFrame:SetHeight(HEADER_HEIGHT)
    host.headerFrame = headerFrame

    -- A right click anywhere on the header opens the Columns panel, between the labels too.
    headerFrame:EnableMouse(true)
    headerFrame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then GuildOS:ToggleColumnsPanel(self) end
    end)

    -- Header buttons are built once, one per column there is, and placed or hidden by the layout
    -- pass; x and width come from ResolveColumns, never from a constant.
    host.headerButtons = {}
    for _, col in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, headerFrame)
        btn:SetHeight(HEADER_HEIGHT)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local text = UI:CreateHeaderText(btn, col.label, SP.META)
        if col.align == "CENTER" then
            text:SetPoint("CENTER")
        elseif col.align == "RIGHT" then
            text:SetPoint("RIGHT")
        else
            text:SetPoint("LEFT")
        end
        btn.text = text

        -- Sort indicator
        local sortArrow = btn:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(sortArrow, SP.META)
        sortArrow:SetPoint("LEFT", text, "RIGHT", 3, 0)
        sortArrow:SetTextColor(C.text.r, C.text.g, C.text.b)
        sortArrow:Hide()
        btn.sortArrow = sortArrow

        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                GuildOS:ToggleColumnsPanel(self)
                return
            end
            local db = GuildOS.db.settings
            if db.sortBy == col.key then
                db.sortAsc = not db.sortAsc
            else
                db.sortBy = col.key
                db.sortAsc = col.asc or false
            end
            host:RefreshRoster()
        end)

        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(C.white.r, C.white.g, C.white.b)
        end)
        btn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        end)

        host.headerButtons[col.key] = btn
    end

    -- Header bottom line: the metal.
    local headerLine = UI:CreateSeparator(tableArea)
    headerLine:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)

    -- The legend under the table (the mockup's .legend): "Marks", each mark and what it says, and the hint; a
    -- line above it. What does not fit goes from the end.
    local legend = CreateFrame("Frame", nil, tableArea)
    legend:SetPoint("BOTTOMLEFT", 0, 0)
    legend:SetPoint("BOTTOMRIGHT", 0, 0)
    legend:SetHeight(LEGEND_H)
    host.legend = legend
    local legendRule = UI:CreateSeparator(tableArea)
    legendRule:SetPoint("BOTTOMLEFT", legend, "TOPLEFT", 0, LEGEND_GAP / 2)
    legendRule:SetPoint("BOTTOMRIGHT", legend, "TOPRIGHT", 0, LEGEND_GAP / 2)
    local legendTitle = UI:CreateHeaderText(legend, L["Marks"], SP.META)
    legendTitle:SetTextColor(C.gold2.r, C.gold2.g, C.gold2.b)
    local function legendText(text, colour)
        local fs = UI:CreateText(legend, text, SP.META, colour.r, colour.g, colour.b)
        fs:SetWordWrap(false)
        return fs
    end
    local noMark = CreateFrame("Frame", nil, legend)
    noMark:SetSize(Marks.SIZE, Marks.SIZE)
    local noMarkRing = GuildOS.Style:Texture(noMark, "ring", "ARTWORK")
    noMarkRing:SetAllPoints()
    noMarkRing:SetVertexColor(C.labelDim.r, C.labelDim.g, C.labelDim.b, 1)
    host.legendItems = {
        { key = "cur", mark = Marks.Create(legend), text = legendText(L["Guild OS up to date"], C.textSoft) },
        { key = "old", mark = Marks.Create(legend), text = legendText(L["Guild OS out of date"], C.textSoft) },
        { key = "none", mark = noMark, text = legendText(L["No mark: no Guild OS"], C.textSoft) },
        { key = "founder", mark = Marks.Create(legend), text = legendText(L["Founder"], C.textSoft), founder = true },
        { key = "hint", text = legendText(L["Hover a mark for details"], C.labelDim) },
    }
    host.legendTitle = legendTitle

    -- Lays the legend out in `w`, from the left; an item that does not fit hides, and every one after it.
    function host:LayoutLegend(w)
        w = w or self.legendW
        if not w then return end
        self.legendW = w
        local scan = self.scan or {}
        legendTitle:ClearAllPoints()
        legendTitle:SetPoint("LEFT", legend, "LEFT", 0, 0)
        local x, full = textW(legendTitle) + 14, false
        for _, it in ipairs(self.legendItems) do
            local on = not it.founder or GuildOS.Founding ~= nil
            local iw = textW(it.text) + (it.mark and (Marks.SIZE + 6) or 0)
            local fits = on and not full and x + iw <= w
            if on and not fits then full = true end
            if it.mark then it.mark:SetShown(fits) end
            it.text:SetShown(fits)
            if fits then
                if it.mark then
                    it.mark:ClearAllPoints()
                    it.mark:SetPoint("LEFT", legend, "LEFT", x, 0)
                    it.text:ClearAllPoints()
                    it.text:SetPoint("LEFT", it.mark, "RIGHT", 6, 0)
                    if it.mark.SetKind then
                        local version = (it.key == "cur" and scan.latest) or (it.key == "old" and (scan.oldest or "?")) or nil
                        it.mark:SetKind(it.key, version, scan.latest)
                    end
                else
                    it.text:ClearAllPoints()
                    it.text:SetPoint("LEFT", legend, "LEFT", x, 0)
                end
                x = x + iw + 18
            end
        end
    end

    -- Scroll Frame for roster rows
    local rosterContainer = CreateFrame("Frame", "GuildOSRosterContainer" .. uid, tableArea)

    -- The chips (when a filter is on), the header, its rule, the rows and the legend; as many rows as fit.
    function host:PlaceTable()
        local top = self.chipsShown and (CHIP_H + 8) or 0
        activeBar:SetShown(self.chipsShown == true)
        headerFrame:ClearAllPoints()
        headerFrame:SetPoint("TOPLEFT", 0, -top)
        headerFrame:SetPoint("TOPRIGHT", 0, -top)
        headerLine:ClearAllPoints()
        headerLine:SetPoint("TOPLEFT", 0, -(top + HEADER_HEIGHT))
        headerLine:SetPoint("TOPRIGHT", 0, -(top + HEADER_HEIGHT))
        rosterContainer:ClearAllPoints()
        rosterContainer:SetPoint("TOPLEFT", 0, -(top + HEADER_HEIGHT + 1))
        rosterContainer:SetPoint("BOTTOMRIGHT", 0, LEGEND_H + LEGEND_GAP)
        if self.listH and self.AcquireRows then
            local rowsH = self.listH - SP.TOP - top - HEADER_HEIGHT - 1 - LEGEND_H - LEGEND_GAP - SP.PAD
            self.AcquireRows(UI:ResolveRows(rowsH, ROW_HEIGHT, 0))
        end
    end

    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSRosterScroll" .. uid, rosterContainer, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(scrollFrame, "GuildOSRosterScroll" .. uid)

    host.scrollFrame = scrollFrame
    host.rows = {}
    host.visibleRows = 0

    -- Rows are pooled and grown on demand: how many exist depends on how
    -- tall the window is right now, which changes while the grip is dragged.
    -- A row is created once and reused for the rest of the session.
    host.AcquireRows = function(n)
        for i = #host.rows + 1, n do
            local row = CreateRosterRow(rosterContainer, i, uid, host)
            if host.colLayout then row:ApplyColumns(host.colLayout) end
            host.rows[i] = row
        end
        for i = 1, #host.rows do
            host.rows[i]:SetShown(i <= n)
        end
        host.visibleRows = n
    end
    host:PlaceTable()

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            host:UpdateRows()
        end)
    end)

    -- Where the rail and the list go in the body under the tiles (bodyW x bodyH, the band bandH tall): side by
    -- side, or the rail above the list on a narrow window. Returns whether the list's height changed.
    function host:LayoutBody()
        local w, h, band = self.bodyW, self.bodyH, self.bandH
        if not w then return false end
        local stacked = w < RAIL_STACK
        self.railMode = stacked and "top" or "side"
        local railW = stacked and w or RAIL_W
        local inner = railW - 2 * RAIL_PAD_X
        self.railInnerW = inner
        local contentH = self:LayoutRail()
        local avail = math.max(0, h - band)
        local maxH = stacked and math.floor(avail * RAIL_TOP_MAX) or avail
        if contentH + 2 * SP.PAD > maxH then
            -- It scrolls: its lines keep clear of the scroll bar.
            self.railInnerW = inner - UI.SCROLL_GUTTER
            contentH = self:LayoutRail()
        end
        local railH = math.max(2 * SP.PAD + ITEM_H, math.min(contentH + 2 * SP.PAD, maxH))
        railCard:ClearAllPoints()
        railCard:SetPoint("TOPLEFT", 0, -band)
        railCard:SetSize(railW, railH)
        railScroll:SetSize(railW - 2 * RAIL_PAD_X, railH - 2 * SP.PAD)
        local listTop = stacked and (band + railH + SP.GAP) or band
        listCard:ClearAllPoints()
        listCard:SetPoint("TOPLEFT", stacked and 0 or (RAIL_W + SP.GAP), -listTop)
        listCard:SetPoint("BOTTOMRIGHT", 0, 0)
        self.listW = stacked and w or (w - RAIL_W - SP.GAP)
        local listH = h - listTop
        local changed = listH ~= self.listH
        self.listH = listH
        return changed
    end

    ----------------------------------------------------------------
    -- The filters' state. A view is one of All, Online, From the alliance; Founders, a Guild OS state, a rank
    -- and a class each narrow it, all together. The chosen one is the gold pill; chosen again, it goes.
    ----------------------------------------------------------------
    function host:UpdateRailActive()
        self.segBtns.all:SetActive(self.segment == "all")
        self.segBtns.online:SetActive(self.segment == "online")
        self.segBtns.allied:SetActive(self.segment == "allied")
        self.foundersBtn:SetActive(self.foundersOnly == true)
        for k, b in pairs(self.addonBtns) do b:SetActive(self.addonFilter == k) end
        for _, b in ipairs(self.rankBtns) do b:SetActive(b.inUse and self.rankFilter == b.rankIndex) end
        for classFile, chip in pairs(self.classChips) do chip:SetActive(self.classFilter == classFile) end
        self.offlineBtn.checkbox:SetChecked(GuildOS.db.settings.showOffline ~= false)
    end

    function host:SetSegment(id)
        if id ~= "all" and self.segment == id then id = "all" end
        self.segment = id
        self:UpdateRailActive()
        self:RefreshRoster()
    end

    function host:SetFounders(on)
        self.foundersOnly = on and true or false
        self:UpdateRailActive()
        self:RefreshRoster()
    end

    function host:SetAddonFilter(status)
        if self.addonFilter == status then status = nil end
        self.addonFilter = status
        self:UpdateRailActive()
        self:RefreshRoster()
    end

    function host:SetRankFilter(index)
        if self.rankFilter == index then index = nil end
        self.rankFilter = index
        self:UpdateRailActive()
        self:RefreshRoster()
    end

    function host:SetClassFilter(classFile)
        -- Toggle: clicking the active class clears it. NOTE: do not use the
        -- "cond and nil or x" idiom here — `and nil` short-circuits so it can
        -- never return nil, which made the filter impossible to clear.
        if self.classFilter == classFile then
            self.classFilter = nil
        else
            self.classFilter = classFile
        end
        self:UpdateRailActive()
        self:RefreshRoster()
    end

    function host:ClearFilters()
        self.segment, self.foundersOnly, self.addonFilter, self.rankFilter, self.classFilter = "all", false, nil, nil, nil
        GuildOS.db.settings.showOffline = true
        self:UpdateRailActive()
        if (self.searchBox:GetText() or "") ~= "" then
            self.searchBox:SetText("")   -- its OnTextChanged refreshes
            self.searchFilter = ""
        end
        self:RefreshRoster()
    end

    -- The filters on now, each with its label and what takes it off.
    function host:ActiveFilters()
        local out = {}
        local function add(label, off) out[#out + 1] = { label = label, off = off } end
        if self.segment == "online" then add(L["Online"], function() self.segment = "all" end) end
        if self.segment == "allied" then add(L["From the alliance"], function() self.segment = "all" end) end
        if GuildOS.db.settings.showOffline == false then
            add(L["Online Only"], function() GuildOS.db.settings.showOffline = true end)
        end
        if self.foundersOnly and GuildOS.Founding then add(L["Founders"], function() self.foundersOnly = false end) end
        if self.addonFilter then
            add(self.addonBtns[self.addonFilter].label:GetText(), function() self.addonFilter = nil end)
        end
        if self.rankFilter then
            local name = string.format(L["Rank %d"], self.rankFilter)
            for _, b in ipairs(self.rankBtns) do
                if b.inUse and b.rankIndex == self.rankFilter then name = b.label:GetText() end
            end
            add(name, function() self.rankFilter = nil end)
        end
        if self.classFilter then add(className(self.classFilter), function() self.classFilter = nil end) end
        return out
    end

    -- The chips over the table; the table moves under them when they come or go.
    function host:UpdateChips()
        local list = self:ActiveFilters()
        local w = self.legendW or 400
        local x = 0
        for i, f in ipairs(list) do
            local chip = self.activeChips[i]
            if not chip then
                chip = UI:SetButtonVariant(UI:CreateButton(activeBar, "", 60, CHIP_H), "chip")
                self.activeChips[i] = chip
            end
            chip.label:SetText(f.label .. "  ×")
            local cw = textW(chip.label) + 20
            chip:SetWidth(cw)
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", activeBar, "LEFT", x, 0)
            chip:SetShown(x + cw <= w)
            chip:SetScript("OnClick", function()
                f.off()
                self:UpdateRailActive()
                self:RefreshRoster()
            end)
            x = x + cw + CHIP_GAP
        end
        for i = #list + 1, #self.activeChips do self.activeChips[i]:Hide() end
        local shown = #list > 0
        if shown ~= (self.chipsShown == true) then
            self.chipsShown = shown
            self:PlaceTable()
        end
    end

    function host:UpdateRail()
        local total, online = 0, 0
        local rankCount, rankName = {}, {}
        local classCount = {}
        local n = GetNumGuildMembers()
        for i = 1, n do
            local name, rName, rIdx, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
            if name then
                total = total + 1
                if isOnline then online = online + 1 end
                if rIdx then
                    rankCount[rIdx] = (rankCount[rIdx] or 0) + 1
                    rankName[rIdx] = rName
                end
                if classFile and classFile ~= "" then
                    classCount[classFile] = (classCount[classFile] or 0) + 1
                end
            end
        end

        self.segBtns.all.count:SetText(tostring(total))
        self.segBtns.online.count:SetText(tostring(online))
        local alliedN = 0
        for _, g in ipairs(GuildOS.Alliance and GuildOS.Alliance:Directory() or {}) do alliedN = alliedN + #g.members end
        self.segBtns.allied.count:SetText(tostring(alliedN))
        self.alliedShown = alliedN > 0
        if alliedN == 0 and self.segment == "allied" then self.segment = "all" end   -- the directory went

        local founders = 0
        if GuildOS.Founding then
            local set = GuildOS.Founding:Founders() or {}
            for key in pairs(set) do
                if self.scan and self.scan.byKey[key] then founders = founders + 1 end
            end
        end
        self.foundersBtn.count:SetText(tostring(founders))

        local count = self.scan and self.scan.count or {}
        for k, b in pairs(self.addonBtns) do b.count:SetText(tostring(count[k] or 0)) end

        -- One line per populated rank, sorted by rank index; a click on the open one clears it.
        local indices = {}
        for idx in pairs(rankCount) do indices[#indices + 1] = idx end
        table.sort(indices)
        for slot, idx in ipairs(indices) do
            local b = self.rankBtns[slot]
            if not b then
                b = railItem("", nil)
                self.rankBtns[slot] = b
            end
            b.rankIndex = idx
            b.inUse = true
            b.label:SetText(rankName[idx] or string.format(L["Rank %d"], idx))
            b.count:SetText(tostring(rankCount[idx] or 0))
            b:SetScript("OnClick", function() host:SetRankFilter(idx) end)
        end
        for slot = #indices + 1, #self.rankBtns do
            self.rankBtns[slot].inUse = nil
        end
        if self.rankFilter and not rankCount[self.rankFilter] then self.rankFilter = nil end   -- the rank emptied

        for classFile, chip in pairs(self.classChips) do
            local c = classCount[classFile] or 0
            chip.count:SetText(tostring(c))
            chip:SetAlpha(c == 0 and 0.35 or 1)
        end

        self:UpdateRailActive()
        -- More or fewer lines (a rank came or went): the rail and the list are laid out again, and the rows.
        if self:LayoutBody() then
            self:LayoutToolbar()
            self:PlaceTable()
            self:UpdateRows()
        end
    end

    ----------------------------------------------------------------
    -- Data & Methods
    ----------------------------------------------------------------
    host.sortedMembers = {}
    host.searchFilter = ""

    function host:RefreshRoster()
        -- What this reader may see changes under an open window (the loot system, a feature, the
        -- officer rank): the table is laid out again when it would choose other columns now (#178).
        if self.colSig and select(2, ChosenColumns()) ~= self.colSig then
            UI:Relayout(parent)
            GuildOS:RefreshColumnsPanel()
        end
        self:LayoutToolbar()   -- who may invite can change under an open window (#377)
        self:UpdateChips()
        self:BuildMemberList()
        self:UpdateSortIndicators()
        self:UpdateRows()
        self:UpdateStats()
        self:LayoutLegend()
    end

    -- The selected row is the member whose sheet a click opened (#377), and the mark goes when the
    -- sheet closes. Hooked once, on the sheet UI/MemberDetail.lua builds on its first show.
    function host:SelectMember(key)
        self.selectedKey = key
        local sheet = GuildOS.DetailFrame
        if sheet and not sheet.__rosterSelection then
            sheet.__rosterSelection = true
            sheet:HookScript("OnHide", ClearSelection)
        end
        self:UpdateRows()
    end

    function host:BuildMemberList()
        -- Reuse the existing table to avoid allocating a new one on every refresh.
        wipe(self.sortedMembers)
        local members = self.sortedMembers
        local showOffline = GuildOS.db.settings.showOffline ~= false
        local filter = self.searchFilter and strlower(strtrim(self.searchFilter)) or ""
        local levelMatch = (filter ~= "" and GuildOS.LevelQuery) and GuildOS.LevelQuery:Parse(filter) or nil

        -- Guild OS on every member and who founded the guild, once per refresh (#449).
        local scan = Marks.Scan()
        self.scan = scan
        local founders = GuildOS.Founding and GuildOS.Founding:Founders() or {}

        -- Only the values a cell draws, and the one sorted by, are worth reading (#178).
        local sortBy = GuildOS.db.settings.sortBy or "level"
        local wanted, ctx, sortCol = {}, {}, nil
        for _, col in ipairs(COLUMNS) do
            if col.value and ((col.text and self.colKeys and self.colKeys[col.key]) or (col.key == sortBy and offered(col.key))) then
                wanted[#wanted + 1] = col
                if col.prepare then col.prepare(ctx) end
                if col.key == sortBy then sortCol = col end
            end
        end

        -- The hover card's index (issue #427): every member, shown or not, so the card names an alt
        -- in its class colour without walking the roster on each hover.
        local tipIndex = GuildOS.RosterCard and GuildOS.RosterCard.NewIndex(GuildOS.db.altLinks)
        self.tipIndex = tipIndex

        -- From the alliance: the directory's rows instead of the guild's, read-only (AlliedEntries). Only the
        -- search and the class filter them: the rest are the guild's.
        local allied = self.segment == "allied"
        if allied then
            for _, entry in ipairs(UI.AlliedEntries(filter, levelMatch, self.classFilter)) do
                members[#members + 1] = entry
            end
        end

        -- Get guild roster info
        local numMembers = allied and 0 or GetNumGuildMembers()
        for i = 1, numMembers do
            local name, rankName, rankIndex, level, classLoc, zone, note,
                  officerNote, isOnline, status, classFile = GetGuildRosterInfo(i)

            if name then
                -- Strip realm from name for display
                local displayName = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$") or GetRealmName()
                local key = GuildOS:GetPlayerKey(displayName, realm)
                if tipIndex then GuildOS.RosterCard.IndexRow(tipIndex, key, displayName, classFile, isOnline) end
                local gos = scan.byKey[key] or { status = "none" }

                -- Apply filters: all of them together.
                local passFilter = true
                if not showOffline and not isOnline then
                    passFilter = false
                end
                if filter ~= "" then
                    if levelMatch then
                        if not levelMatch(level or 0) then passFilter = false end
                    else
                        local searchTarget = strlower(displayName .. " " .. (classLoc or "") .. " " .. (zone or "") .. " " .. (rankName or ""))
                        if not searchTarget:find(filter, 1, true) then
                            passFilter = false
                        end
                    end
                end
                if self.segment == "online" and not isOnline then passFilter = false end
                if self.foundersOnly and GuildOS.Founding and not founders[key] then passFilter = false end
                if self.addonFilter and gos.status ~= self.addonFilter then passFilter = false end
                if self.rankFilter and rankIndex ~= self.rankFilter then passFilter = false end
                if self.classFilter and classFile ~= self.classFilter then passFilter = false end

                if passFilter then
                    -- Merge with stored addon data
                    local addonData = GuildOS.db.members[key] or {}

                    local entry = {
                        index = i,
                        key = key,
                        name = displayName,
                        fullName = name,
                        realm = realm,
                        rank = rankName,
                        rankIndex = rankIndex,
                        level = level or 0,
                        class = classFile or "",
                        classDisplay = classLoc or "",
                        zone = zone or "",
                        note = note or "",
                        officerNote = officerNote or "",
                        isOnline = isOnline,
                        status = status or "",
                        -- Addon data
                        avgIlvl = addonData.avgIlvl or 0,
                        gear = addonData.gear,
                        -- On WoW: Forever a member without the addon (or on a version that sends none)
                        -- still has the professions the guild roster names (issue #31).
                        professions = addonData.professions
                            or (GuildOS.Professions and GuildOS.Professions:LegacyList(key)),
                        attunements = addonData.attunements,
                        stats = addonData.stats,
                        mplus = addonData.mplus,   -- retail (issue #187)
                        vault = addonData.vault,
                        race = addonData.race or "",
                        lastUpdate = addonData.lastUpdate or 0,
                        lastSync = addonData.lastSync or 0,
                        -- Prefer the live version a member is broadcasting on the mesh
                        -- (realm-wide, fresher than the last guild sync) over the stored
                        -- one, so an update shows up before CommSystem re-syncs.
                        addonVersion = gos.version,
                        hasAddonData = (addonData.lastUpdate ~= nil and addonData.lastUpdate ~= 0),
                        -- Guild OS on them and the newest seen in the guild (the marks, the column), and
                        -- whether they founded the guild (#449).
                        addonStatus = gos.status,
                        latest = scan.latest,
                        founder = founders[key] ~= nil,
                        cols = {},
                    }
                    for _, col in ipairs(wanted) do entry.cols[col.key] = col.value(entry, ctx) end
                    members[#members + 1] = entry
                end
            end
        end

        -- Sort
        local sortAsc = GuildOS.db.settings.sortAsc

        -- A column's sort keys, once: lower-cased text, and all of it text when synced data mixed
        -- numbers in, since comparing a number with a string raises.
        if sortCol then
            local anyText = false
            for _, m in ipairs(members) do
                if type(m.cols[sortBy]) == "string" then anyText = true break end
            end
            for _, m in ipairs(members) do
                local v = m.cols[sortBy]
                m.sortKey = (anyText and v ~= nil) and tostring(v):lower() or v
            end
        end

        table.sort(members, function(a, b)
            -- Online always first
            if a.isOnline ~= b.isOnline then
                return a.isOnline
            end

            local va, vb
            if sortCol then
                va, vb = a.sortKey, b.sortKey
                -- An empty cell goes last, whichever way the column is sorted.
                if va == nil or vb == nil then
                    if va == vb then return a.name:lower() < b.name:lower() end
                    return va ~= nil
                end
            elseif sortBy == "name" then
                va, vb = a.name:lower(), b.name:lower()
            elseif sortBy == "level" then
                va, vb = a.level, b.level
            elseif sortBy == "class" then
                va, vb = a.classDisplay:lower(), b.classDisplay:lower()
            else
                va, vb = a.level, b.level
            end

            if va == vb then
                return a.name:lower() < b.name:lower()
            end

            if sortAsc then
                return va < vb
            else
                return va > vb
            end
        end)
    end

    function host:UpdateSortIndicators()
        local sortBy = GuildOS.db.settings.sortBy
        local sortAsc = GuildOS.db.settings.sortAsc

        for key, btn in pairs(self.headerButtons) do
            if key == sortBy then
                btn.sortArrow:SetText(sortAsc and "|TInterface\\BUTTONS\\Arrow-Up-Up:12:12|t" or "|TInterface\\BUTTONS\\Arrow-Down-Up:12:12|t")
                btn.sortArrow:Show()
            else
                btn.sortArrow:Hide()
            end
        end
    end

    function host:UpdateRows()
        local members = self.sortedMembers
        local numMembers = #members
        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)
        -- How many rows exist is decided by the layout pass, not a
        -- constant: a window dragged short has fewer, and one dragged
        -- tall has more.
        local visible = self.visibleRows or 0
        if visible < 1 then return end

        FauxScrollFrame_Update(self.scrollFrame, numMembers, visible, ROW_HEIGHT)

        for i = 1, visible do
            local row = self.rows[i]
            local dataIndex = offset + i

            if dataIndex <= numMembers then
                local data = members[dataIndex]
                UpdateRosterRow(row, data)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    function host:UpdateStats()
        local numTotal = GetNumGuildMembers()
        local numOnline = 0

        for i = 1, numTotal do
            local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline then numOnline = numOnline + 1 end
        end

        -- Average item level (members with stored addon data)
        local ilvlSum, ilvlCount = 0, 0
        for _, data in pairs(GuildOS.db.members) do
            if data.lastUpdate and data.lastUpdate > 0 and data.avgIlvl and data.avgIlvl > 0 then
                ilvlSum = ilvlSum + data.avgIlvl
                ilvlCount = ilvlCount + 1
            end
        end
        local avgIlvl = ilvlCount > 0 and math.floor(ilvlSum / ilvlCount + 0.5) or 0

        -- Average 25-man raid attendance across known members
        local attSum, attCount = 0, 0
        if GuildOS.RaidTracker and GuildOS.RaidTracker.GetAttendance25ManPercent then
            local totals = {}   -- each core's count once, not once per member
            for key in pairs(GuildOS.db.members) do
                local p = GuildOS.RaidTracker:GetAttendance25ManPercent(key, nil, totals)
                if p and p > 0 then
                    attSum = attSum + p
                    attCount = attCount + 1
                end
            end
        end
        local avgAtt = attCount > 0 and math.floor(attSum / attCount + 0.5) or 0

        -- True Roster: unique players behind the guild's alt/main links.
        if self.kpiPlayers and GuildOS.GetTrueRoster then
            local tr = GuildOS:GetTrueRoster()
            self.kpiPlayers:SetText(tr.uniqueCount)
            if self.kpiPlayersSub then
                self.kpiPlayersSub:SetText(string.format(L["of %d chars"], tr.totalChars))
            end
        end

        -- KPI cards. With Guild OS: the guild's members this client heard it from, the same scan as the marks.
        local count = self.scan and self.scan.count or { cur = 0, old = 0 }
        if self.kpiMembers then self.kpiMembers:SetText(numTotal) end
        if self.kpiOnline then self.kpiOnline:SetText(numOnline) end
        if self.kpiIlvl then self.kpiIlvl:SetText(avgIlvl > 0 and avgIlvl or "—") end
        if self.kpiAtt then self.kpiAtt:SetText(avgAtt > 0 and (avgAtt .. "%") or "—") end
        if self.kpiAddon then self.kpiAddon:SetText(count.cur + count.old) end
        if self.kpiAddonSub then self.kpiAddonSub:SetText(string.format(L["· %d out of date"], count.old)) end

        -- "N of M": how many the filters leave, of the whole guild.
        if self.resultText then
            local shown = self.sortedMembers and #self.sortedMembers or 0
            self.resultText:SetText(string.format(L["%s of %d"], "|cfff6e9cf" .. shown .. "|r", numTotal))
        end

        -- Rail counts + active highlight
        if self.UpdateRail then self:UpdateRail() end
    end

    ----------------------------------------------------------------
    -- Layout: everything that depends on how big the container is right
    -- now. Runs once on first show and once per frame while the grip is
    -- dragged (UI:MakeResponsive coalesces the burst).
    ----------------------------------------------------------------
    UI:MakeResponsive(parent, function(_, w, h)
        host.bandH = host:LayoutTiles(w)
        host.bodyW, host.bodyH = w, h
        host:LayoutBody()
        host:LayoutToolbar()
        local inner = host.listW - 2 * SP.PAD
        host.legendW = inner
        host:LayoutLegend(inner)

        -- Table columns.
        local tableW = inner - ROW_INSET - SCROLL_GUTTER
        local spec
        spec, host.colSig = ChosenColumns()
        local layout = UI:ResolveColumns(spec, tableW, COL_GAP)
        host.colLayout = layout
        host.colKeys = {}
        for _, btn in pairs(host.headerButtons) do btn:Hide() end
        for _, col in ipairs(layout) do
            local btn = host.headerButtons[col.key]
            if btn and col.shown then
                host.colKeys[col.key] = true
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", ROW_INSET + col.x, 0)
                btn:SetWidth(col.w)
            end
        end

        -- Rows: how many fit, and where their cells sit.
        host:PlaceTable()
        for i = 1, host.visibleRows do
            host.rows[i]:ApplyColumns(layout)
        end

        GuildOS:RefreshRosterUI()
    end)

    return parent
end

----------------------------------------------------------------------
-- Create a single roster row
----------------------------------------------------------------------

-- The mockup's rows (.t): nothing behind a row at rest, a faint gold wash under the cursor, and the selected
-- member's a gold wash that fades to the right, with the gold edge on its left.
local function PaintRow(row)
    if row.hovered and not row.selected then
        row:SetBackdropColor(1, 0.843, 0.471, 0.07)
    else
        row:SetBackdropColor(0, 0, 0, 0)
    end
    row.selMark:SetShown(row.selected == true)
    if row.selFade then row.selFade:SetShown(row.selected == true) end
end

function CreateRosterRow(parent, rowIndex, uid, host)
    local row = CreateFrame("Button", "GuildOSRow" .. (uid or "") .. rowIndex, parent, "BackdropTemplate")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((rowIndex - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    row.host = host

    -- No zebra (#377): a 1px line parts the rows. The selected one has a 2px gold edge on its
    -- left, through UI:Px so a scaled-down interface does not round it away.
    local rule = UI:CreateSeparator(row)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    row.rule = rule
    row.selFade = UI:CreateRowSelection(row)
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\WHITE8x8")
    mark:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    mark:SetPoint("TOPLEFT", 0, 0)
    mark:SetPoint("BOTTOMLEFT", 0, 0)
    mark:SetWidth(UI:Px(mark, 2))
    row.selMark = mark
    PaintRow(row)

    -- Row elements. None of them is positioned here: ApplyColumns below
    -- places every cell from a resolved layout, so the same row works at
    -- any window width.

    -- Status indicator (online dot) — rides inside the name cell
    local statusDot = row:CreateTexture(nil, "OVERLAY")
    statusDot:SetSize(8, 8)
    statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
    row.statusDot = statusDot

    -- The class's round avatar with the name's initial (the mockup's .av.s), then the name in the class's
    -- colour. row.classIcon is the avatar's disc, so what read the icon reads the avatar.
    local avatar = UI:CreateAvatar(row, 20, false)
    avatar:EnableMouse(false)
    row.avatar = avatar
    local classIcon = avatar.disc
    row.classIcon = classIcon

    local nameText = row:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(nameText, nil, "memberName")
    nameText:SetPoint("LEFT", avatar, "RIGHT", 6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    -- The marks after the name (#449): Guild OS (green crest up to date, amber with "!" out of date, none when it
    -- is not installed) and the founder's banner. A mark's click is the row's.
    local function clickRow(_, button)
        local fn = row:GetScript("OnClick")
        if fn then fn(row, button) end
    end
    row.marks = { Marks.Create(row, clickRow), Marks.Create(row, clickRow) }
    row.marks[1]:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    row.marks[2]:SetPoint("LEFT", row.marks[1], "RIGHT", 4, 0)
    for _, m in ipairs(row.marks) do m:Hide() end
    row.markKinds = {}

    -- The name takes what the marks leave of its cell.
    function row:FitName()
        local max = self.nameMax or 100
        local n = #self.markKinds
        local room = math.max(20, max - n * (Marks.SIZE + 4))
        if not self.nameText.GetUnboundedStringWidth then self.nameText:SetWidth(max) end
        self.nameText:SetWidth(math.max(1, math.min(textW(self.nameText), room)))
        for i, m in ipairs(self.marks) do m:SetShown(self.nameShown ~= false and self.markKinds[i] ~= nil) end
    end

    local function cell(size, justify, colour, role)
        local fs = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(fs, size, role)
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        if colour then fs:SetTextColor(colour.r, colour.g, colour.b) end
        return fs
    end

    row.levelText    = cell(nil, "CENTER", nil, "tableNum")
    row.classText    = cell(11, "LEFT")
    row.raceText     = cell(11, "LEFT", C.silver)
    row.ilvlText     = cell(nil, "CENTER", nil, "tableNum")
    row.profText     = cell(10, "LEFT")
    row.zoneText     = cell(10, "LEFT")
    row.lastSeenText = cell(10, "RIGHT", C.silver)

    -- Which elements belong to which column, so a dropped column takes
    -- everything it owns with it.
    row.cells = {
        name        = { nameText, avatar, statusDot },
        level       = { row.levelText },
        class       = { row.classText },
        avgIlvl     = { row.ilvlText },
        race        = { row.raceText },
        lastSeen    = { row.lastSeenText },
        professions = { row.profText },
        zone        = { row.zoneText },
    }
    -- One plain cell per column that draws through its `text` (#178); a `num` column draws through the tableNum role.
    row.textCells = {}
    for _, col in ipairs(COLUMNS) do
        if col.text then
            local fs = cell(11, col.align, nil, col.num and "tableNum" or nil)
            row.textCells[col.key] = fs
            row.cells[col.key] = { fs }
        end
    end

    -- Reposition every cell from a resolved layout. Runs once per row per
    -- resize, never per data update. A column the layout does not name is
    -- one the reader has not chosen, so everything starts hidden.
    function row:ApplyColumns(layout)
        for _, group in pairs(self.cells) do
            for _, el in ipairs(group) do el:Hide() end
        end
        for _, col in ipairs(layout) do
            local group = self.cells[col.key]
            if group and col.shown then
                for _, el in ipairs(group) do el:Show() end
            end
        end
        local byKey = layout.byKey
        local nameCol = byKey.name
        self.nameShown = nameCol ~= nil and nameCol.shown
        if self.nameShown then
            self.statusDot:ClearAllPoints()
            self.statusDot:SetPoint("LEFT", ROW_INSET + nameCol.x + 6, 0)
            self.avatar:ClearAllPoints()
            self.avatar:SetPoint("LEFT", ROW_INSET + nameCol.x + 16, 0)
            self.nameMax = math.max(20, nameCol.w - 52)
        end
        -- The marks have their own rule (the member's); the layout only gives the name its room.
        self:FitName()

        local function place(key, fs)
            local col = byKey[key]
            if not col or not col.shown then return end
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", ROW_INSET + col.x, 0)
            fs:SetWidth(col.w)
        end
        place("level",       self.levelText)
        place("class",       self.classText)
        place("avgIlvl",     self.ilvlText)
        place("race",        self.raceText)
        place("lastSeen",    self.lastSeenText)
        place("professions", self.profText)
        place("zone",        self.zoneText)
        for key, fs in pairs(self.textCells) do place(key, fs) end
    end

    -- Hover effects
    row:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintRow(self)
        if self.memberData then
            ShowRowTooltip(self)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = nil
        PaintRow(self)
        GameTooltip:Hide()
    end)

    -- Click: left = detail, right = context menu
    row:SetScript("OnClick", function(self, button)
        if not self.memberData then return end
        -- An ally's row is read-only: no sheet, no menu, no rank action. A click whispers them.
        if self.memberData.allied then
            if button ~= "RightButton" and ChatFrame_SendTell then
                ChatFrame_SendTell(GuildOS:WhisperTarget(self.memberData.whisper or self.memberData.name))
            end
            return
        end
        if button == "RightButton" then
            GuildOS:ShowMemberContextMenu(self, self.memberData)
        elseif GuildOS.RosterCard and IsShiftKeyDown and IsShiftKeyDown() then
            -- Shift+click keeps the card open; Escape lets it go (issue #427).
            GuildOS.RosterCard:Toggle(self, ShowRowTooltip)
        else
            GuildOS:ShowMemberDetail(self.memberData)
            if self.host and self.host.SelectMember then self.host:SelectMember(self.memberData.key) end
        end
    end)

    return row
end

----------------------------------------------------------------------
-- From the alliance (alianca.md §3.2): the allied guilds' members as rows of the Members table, read-only.
-- `rank` is the member's guild, `isOnline` the best effort of the channel and the mesh (Alliance:OnlineNow).
-- The search, a level query and the class chip filter them as they do the guild's.
----------------------------------------------------------------------
local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DPS = "DPS" }
function UI.AlliedEntries(filter, levelMatch, classFilter)
    local out = {}
    local A = GuildOS.Alliance
    if not A then return out end
    local onNow = {}
    for _, p in ipairs(A:OnlineNow()) do onNow[tostring(p.name):lower()] = true end
    for _, g in ipairs(A:Directory()) do
        for _, m in ipairs(g.members) do
            local classDisplay = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]) or m.class
            local short = m.name:match("^([^-]+)") or m.name
            local pass = not classFilter or m.class == classFilter
            if pass and filter ~= "" then
                if levelMatch then
                    pass = levelMatch(m.level or 0)
                else
                    pass = strlower(short .. " " .. classDisplay .. " " .. g.guild):find(filter, 1, true) ~= nil
                end
            end
            if pass then
                local profs = {}
                for _, prof in ipairs(m.profs or {}) do profs[#profs + 1] = { name = prof, isPrimary = true } end
                local profNames = {}
                for _, prof in ipairs(m.profs or {}) do profNames[#profNames + 1] = L[prof] end
                out[#out + 1] = {
                    allied = true, key = "ally:" .. g.guild .. ":" .. m.key, whisper = m.key, guild = g.guild,
                    name = short, fullName = m.key, rank = g.guild, rankIndex = 99, level = m.level or 0,
                    class = m.class, classDisplay = classDisplay, zone = "", note = "", officerNote = "",
                    isOnline = onNow[short:lower()] == true, status = "", avgIlvl = 0, race = "", lastUpdate = 0,
                    lastSync = 0, professions = #profs > 0 and profs or nil, hasAddonData = false, cols = {},
                    main = m.main and (m.main:match("^([^-]+)") or m.main) or nil,
                    roleLabel = m.role and L[ROLE_LABEL[m.role]] or nil,
                    profLine = #profNames > 0 and table.concat(profNames, ", ") or nil,
                }
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Update a roster row with member data
----------------------------------------------------------------------
function UpdateRosterRow(row, data)
    row.memberData = data

    -- The list is virtual (#377): a row shows another member on every scroll, so whether it is the
    -- selected one is read from the member each time, never left on the row.
    local host = row.host
    row.selected = host ~= nil and host.selectedKey ~= nil and host.selectedKey == data.key
    PaintRow(row)

    -- Grayscale helper for offline members
    local function textColor(r, g, b)
        if data.isOnline then
            return r, g, b
        else
            local gray = r * 0.299 + g * 0.587 + b * 0.114
            return gray, gray, gray
        end
    end

    -- Online status
    if data.isOnline then
        row.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
        row.statusDot:SetVertexColor(C.online.r, C.online.g, C.online.b)
    else
        row.statusDot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        row.statusDot:SetVertexColor(C.offline.r, C.offline.g, C.offline.b)
    end

    -- The class's avatar, greyed while away.
    row.avatar:SetMember(data.name, data.class, not data.isOnline)

    -- Name (class-colored, grayscale if offline)
    local cr, cg, cb = GuildOS:GetClassColor(data.class)
    local nr, ng, nb = textColor(cr, cg, cb)
    row.nameText:SetText(data.name)
    row.nameText:SetTextColor(nr, ng, nb)

    -- The marks (#449): Guild OS up to date or out of date (none when it is not installed), then a founder's
    -- banner (WoW: Forever, issue #209; it was a scroll in the name). An ally's row has none.
    local kinds = {}
    if data.addonStatus == "cur" or data.addonStatus == "old" then kinds[#kinds + 1] = data.addonStatus end
    if data.founder then kinds[#kinds + 1] = "founder" end
    row.markKinds = kinds
    for i, m in ipairs(row.marks) do
        if kinds[i] then m:SetKind(kinds[i], data.addonVersion, data.latest) end
    end
    row:FitName()

    -- Level with color coding: paper at the cap, green within ten of it
    local level = data.level
    local lr, lg, lb
    if level >= GuildOS.Client.maxLevel then
        lr, lg, lb = C.text.r, C.text.g, C.text.b
    elseif level >= GuildOS.Client.maxLevel - 10 then
        lr, lg, lb = C.green.r, C.green.g, C.green.b
    else
        lr, lg, lb = C.white.r, C.white.g, C.white.b
    end
    row.levelText:SetTextColor(textColor(lr, lg, lb))
    row.levelText:SetText(level)

    -- Class display
    row.classText:SetText(data.classDisplay)
    row.classText:SetTextColor(textColor(cr, cg, cb))

    -- Race
    row.raceText:SetText(data.race ~= "" and data.race or "-")
    row.raceText:SetTextColor(textColor(C.silver.r, C.silver.g, C.silver.b))

    -- Average iLvl
    if data.avgIlvl and data.avgIlvl > 0 then
        row.ilvlText:SetText(GuildOS:FormatItemLevel(data.avgIlvl))
    else
        row.ilvlText:SetText("|cff666666-|r")
    end

    -- Professions
    if data.professions and #data.professions > 0 then
        local parts = {}
        for _, prof in ipairs(data.professions) do
            if prof.isPrimary then
                local pr, pg, pb = textColor(C.text.r, C.text.g, C.text.b)
                -- A profession known from the guild roster only has no rank (issue #31).
                local label = GuildOS:Utf8Head(L[prof.name], 5) .. (prof.rank and (" " .. prof.rank) or "")
                table.insert(parts, GuildOS:ColorText(label, pr, pg, pb))
            end
        end
        row.profText:SetText(table.concat(parts, " / "))
    else
        row.profText:SetText(L["|cff666666No data|r"])
    end

    -- Zone (only shown for online members)
    if data.isOnline and data.zone and data.zone ~= "" then
        row.zoneText:SetTextColor(textColor(C.silver.r, C.silver.g, C.silver.b))
        row.zoneText:SetText(data.zone)
    else
        row.zoneText:SetText("|cff666666-|r")
    end

    -- Last seen
    if data.isOnline then
        row.lastSeenText:SetText(L["|cff4CFF4CNow|r"])
    elseif data.lastUpdate > 0 then
        row.lastSeenText:SetText(GuildOS:TimeAgo(data.lastUpdate))
    else
        row.lastSeenText:SetText("-")
    end

    -- The columns that draw through `text` (#178); a cell the reader has not chosen has no value.
    for key, fs in pairs(row.textCells) do
        if fs:IsShown() then
            local v = data.cols[key]
            local col = COLUMN_BY_KEY[key]
            local blank, blankColour
            if v == nil and col.empty then blank, blankColour = col.empty(data) end
            if blank then
                fs:SetText(blank)
                fs:SetTextColor(textColor(blankColour.r, blankColour.g, blankColour.b))
            elseif v == nil then
                fs:SetText(DASH)
            else
                local s, colour = COLUMN_BY_KEY[key].text(v, data)
                colour = colour or C.white
                fs:SetText(s)
                fs:SetTextColor(textColor(colour.r, colour.g, colour.b))
            end
        end
    end
end

----------------------------------------------------------------------
-- Columns panel (#178): a box per column this reader may show, the shown ones first and in their
-- order with ▲▼, then the rest. Opened from the toolbar's Columns button and by a right click on
-- the header. The choice is the account's (Modules/RosterColumns.lua).
----------------------------------------------------------------------
local columnsPanel
local PANEL_TOP, PANEL_ROW, PANEL_BOTTOM = 58, 22, 46

local function RelayoutRosters()
    for _, p in ipairs(rosterPanels) do UI:Relayout(p) end
end

local function BuildColumnsPanel()
    local f = CreateFrame("Frame", "GuildOSColumnsPanel", UIParent, "BackdropTemplate")
    f:SetWidth(280)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    tinsert(UISpecialFrames, "GuildOSColumnsPanel")

    UI:CreateTitle(f, L["Columns"], 14):SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)
    local hint = UI:CreateText(f, L["Saved for every character on this account."], UI.SP.META, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", 14, -34)

    local rows = {}
    local function arrow(row, texture, x, delta)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(18, 18)
        b:SetPoint("RIGHT", x, 0)
        b:SetNormalTexture(texture)
        b:SetHighlightTexture(texture)
        b:SetScript("OnClick", function()
            GuildOS.RosterColumns:Move(row.key, delta, offered)
            f:Refresh()
            RelayoutRosters()
        end)
        return b
    end
    local function rowAt(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(252, PANEL_ROW)
        row:SetPoint("TOPLEFT", 14, -(PANEL_TOP + (i - 1) * PANEL_ROW))
        row.box = UI:CreateCheckbox(row, "", 18)
        row.box:SetPoint("LEFT", 0, 0)
        row.box.checkbox.onChanged = function(_, checked)
            GuildOS.RosterColumns:SetShown(row.key, checked and true or false)
            f:Refresh()
            RelayoutRosters()
        end
        row.up = arrow(row, "Interface\\BUTTONS\\Arrow-Up-Up", -20, -1)
        row.down = arrow(row, "Interface\\BUTTONS\\Arrow-Down-Up", 0, 1)
        rows[i] = row
        return row
    end

    local reset = UI:CreateButton(f, L["Restore defaults"], 140, 22)
    reset:SetPoint("BOTTOMLEFT", 14, 12)
    reset:SetScript("OnClick", function()
        GuildOS.RosterColumns:Reset()
        f:Refresh()
        RelayoutRosters()
    end)

    -- Member first and fixed, then the shown columns in order, then everything else on offer.
    function f:Refresh()
        local shown = GuildOS.RosterColumns:Visible(offered)
        local list, isShown = { "name" }, { name = true }
        for _, k in ipairs(shown) do list[#list + 1] = k; isShown[k] = true end
        for _, c in ipairs(COLUMNS) do
            if not isShown[c.key] and offered(c.key) then list[#list + 1] = c.key end
        end
        for i, key in ipairs(list) do
            local row = rowAt(i)
            row.key = key
            row.box.label:SetText(COLUMN_BY_KEY[key].name)
            row.box.checkbox:SetChecked(isShown[key])
            row.box.checkbox:SetEnabled(key ~= "name")
            -- Member is the first place, so the first column after it has nowhere up to go.
            row.up:SetShown(isShown[key] and i > 2)
            row.down:SetShown(isShown[key] and key ~= "name" and i <= #shown)
            row:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        self:SetHeight(PANEL_TOP + #list * PANEL_ROW + PANEL_BOTTOM)
    end

    f:Hide()
    return f
end

function GuildOS:ToggleColumnsPanel(anchor)
    columnsPanel = columnsPanel or BuildColumnsPanel()
    if columnsPanel:IsShown() and columnsPanel.anchor == anchor then
        columnsPanel:Hide()
        return
    end
    columnsPanel.anchor = anchor
    columnsPanel:ClearAllPoints()
    columnsPanel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    columnsPanel:Refresh()
    columnsPanel:Show()
end

function GuildOS:HideColumnsPanel()
    if columnsPanel then columnsPanel:Hide() end
end

-- An open panel follows what the reader may see, as the table does.
function GuildOS:RefreshColumnsPanel()
    if columnsPanel and columnsPanel:IsShown() then columnsPanel:Refresh() end
end

----------------------------------------------------------------------
-- Right-click context menu (mimics default guild roster menu)
----------------------------------------------------------------------
local memberDropdown = CreateFrame("Frame", "GuildOSMemberDropdown", UIParent, "UIDropDownMenuTemplate")

local function MemberDropdown_Initialize(self, level)
    local data = self.memberData
    if not data then return end

    local info = UIDropDownMenu_CreateInfo()
    local myName = GuildOS.Compat.PlayerName()
    local isMe = (data.name == myName)

    -- Header: player name
    info.text = data.name
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true

    -- Whisper
    if not isMe and data.isOnline then
        info.text = WHISPER_MESSAGE or L["Whisper"]
        info.func = function()
            ChatFrame_SendTell(data.name)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Invite to group
    if not isMe and data.isOnline then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = PARTY_INVITE or L["Invite"]
        info.func = function() GuildOS.Compat.InviteUnit(data.name) end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Inspect (target must be nearby)
    if not isMe and data.isOnline then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = INSPECT or L["Inspect"]
        info.func = function()
            InspectUnit(data.name)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Rank management (gated on actual guild permission, not just GM)
    if not isMe and GuildOS.GuildManager then
        local GM = GuildOS.GuildManager
        local canPromote, canDemote = GM:CanPromote(), GM:CanDemote()

        if canPromote then
            info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = "|cff66FF66" .. (GUILD_PROMOTE or L["Promote"]) .. "|r"
            -- Queued in Bulk actions, one click of Next (audit M11): the game takes it from no other button.
            info.func = function()
                GuildOS.GuildManager:Promote(data.fullName or data.name, data.key)
                GuildOS.GuildManager:RefreshUI()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        if canDemote then
            info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = "|cffFFCC66" .. (GUILD_DEMOTE or L["Demote"]) .. "|r"
            info.func = function()
                GuildOS.GuildManager:Demote(data.fullName or data.name, data.key)
                GuildOS.GuildManager:RefreshUI()
            end
            UIDropDownMenu_AddButton(info, level)
        end

    end

    -- Guild remove (with confirmation + action logging)
    if not isMe and GuildOS.GuildManager and GuildOS.GuildManager:CanKick() then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = "|cffFF6666" .. (GUILD_UNINVITE or L["Remove from guild"]) .. "|r"
        info.func = function()
            GuildOS.GuildManager:ConfirmKick(data.fullName or data.name, data.key)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Who
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = WHO or L["Who"]
    info.func = function()
        GuildOS.Compat.SendWho(GuildOS.Compat.WhoExact(data.name))
    end
    UIDropDownMenu_AddButton(info, level)

    -- View detail
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = L["Guild OS Detail"]
    info.func = function()
        GuildOS:ShowMemberDetail(data)
    end
    UIDropDownMenu_AddButton(info, level)

    -- The public note everybody sees (issue #162): for whoever the rank lets edit it, officer or
    -- not, their own included.
    if GuildOS.NoteCommand and GuildOS.Compat.CanEditPublicNote() then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = L["Add note"]
        info.func = function() ShowPublicNote(data) end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Officer actions
    if not isMe and GuildOS:IsOfficer() then
        -- Mark as trial
        if GuildOS.TrialTracker then
            local key = data.key or GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
            if not GuildOS.TrialTracker:IsTrial(key) then
                info = UIDropDownMenu_CreateInfo()
                info.notCheckable = true
                info.text = L["|cffFFAA00Mark as Trial|r"]
                info.func = function()
                    GuildOS.TrialTracker:AddTrial(key)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- Add officer note: Guild OS's own, private to officers — said in its name, beside the public one.
        if GuildOS.OfficerNotes then
            info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = L["|cff8888FFAdd officer note|r"]
            info.func = function()
                -- A box to type it in (issue #49): only printing the slash command left a Forever
                -- officer with a command that read "Lethaniel" for "Lethaniel Blightwood".
                GuildOS:ShowDialog("GUILDOS_OFFICER_NOTE", data.name, nil, { key = data.key, name = data.name })
            end
            UIDropDownMenu_AddButton(info, level)

            -- The member's sheet, the long text (issue #427).
            info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = L["|cff8888FFEdit officer sheet|r"]
            info.func = function() GuildOS:ShowOfficerSheetEditor(data.key, data.name) end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    -- Cancel
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = CANCEL or L["Cancel"]
    UIDropDownMenu_AddButton(info, level)
end

function GuildOS:ShowMemberContextMenu(_anchor, memberData)
    memberDropdown.memberData = memberData
    UIDropDownMenu_Initialize(memberDropdown, MemberDropdown_Initialize, "MENU")
    ToggleDropDownMenu(1, nil, memberDropdown, "cursor", 3, -3)
end

----------------------------------------------------------------------
-- Row tooltip (rich info on hover)
----------------------------------------------------------------------
-- `tip` is the GameTooltip by default, or the card kept open (RosterCard:Toggle, issue #427).
function ShowRowTooltip(row, tip, locked)
    tip = tip or GameTooltip
    local data = row.memberData
    if not data then return end

    if not locked then tip:SetOwner(row, "ANCHOR_BOTTOM", 0, -5) end

    -- Header: Name colored by class
    local cr, cg, cb = GuildOS:GetClassColor(data.class)
    if data.allied then
        -- What guildos.me says of an ally, and nothing of the guild's own.
        tip:AddLine(data.name, cr, cg, cb)
        tip:AddLine(string.format(L["Level %d %s %s"], data.level, "", data.classDisplay), 0.8, 0.8, 0.8)
        tip:AddLine(data.rank, C.text.r, C.text.g, C.text.b)
        if data.roleLabel then tip:AddLine(data.roleLabel, C.silver.r, C.silver.g, C.silver.b) end
        if data.main then tip:AddLine(string.format(L["Alt of %s"], data.main), C.silver.r, C.silver.g, C.silver.b) end
        if data.profLine then tip:AddLine(data.profLine, C.silver.r, C.silver.g, C.silver.b, true) end
        local asOf = GuildOS.Alliance and GuildOS.Alliance:AsOf()
        tip:AddLine(asOf and string.format(L["From guildos.me %s"], string.format(L["(as of %s)"], GuildOS:LocalDate("%a %H:%M", asOf)))
            or L["From guildos.me"], C.textDim.r, C.textDim.g, C.textDim.b)
        if not locked then tip:Show() end
        return
    end
    tip:AddLine(data.name, cr, cg, cb)
    tip:AddLine(string.format(L["Level %d %s %s"], data.level, data.race, data.classDisplay), 0.8, 0.8, 0.8)
    tip:AddLine(data.rank, C.text.r, C.text.g, C.text.b)
    -- The officers' nickname and the safe list (issue #429).
    if GuildOS.MemberMarks then GuildOS.MemberMarks:TooltipLines(tip, data.key, data.note, data.officerNote) end

    -- What this member earned for the guild (issue #216).
    for _, title in ipairs(GuildOS.Achievements and GuildOS.Achievements:Of(data.key) or {}) do
        tip:AddLine(title, C.text.r, C.text.g, C.text.b)
    end

    -- Alts and main, the rating and, to officers, the join, the sheet and the notes (issue #427).
    if GuildOS.RosterCard then GuildOS.RosterCard:AddLines(tip, data, row.host and row.host.tipIndex) end

    -- First seen by Guild OS (approximate "member since")
    local firstSeen = GuildOS.GetFirstSeen and GuildOS:GetFirstSeen(data.key)
    if firstSeen then
        tip:AddLine(string.format(L["Tracked since %s"], date("%Y-%m-%d", firstSeen)), C.silver.r, C.silver.g, C.silver.b)
    end

    -- Talent spec
    if GuildOS.SpecChecker then
        local memberKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        local specLabel = GuildOS.SpecChecker:GetSpecLabel(memberKey)
        if specLabel then
            tip:AddLine(" ")
            tip:AddLine(string.format(L["Spec: %s"], specLabel), cr, cg, cb)
        end
    end

    if data.zone and data.zone ~= "" then
        tip:AddLine(" ")
        tip:AddLine(string.format(L["Zone: %s"], data.zone), C.silver.r, C.silver.g, C.silver.b)
    end

    if data.note and data.note ~= "" then
        tip:AddLine(string.format(L["Note: %s"], data.note), 0.6, 0.6, 0.6, true)
    end

    -- Gear summary
    if data.avgIlvl and data.avgIlvl > 0 then
        tip:AddLine(" ")
        tip:AddLine(string.format(L["Average Item Level: %s"], data.avgIlvl), C.text.r, C.text.g, C.text.b)
    end

    -- Professions detail
    if data.professions and #data.professions > 0 then
        tip:AddLine(" ")
        tip:AddLine(L["Professions:"], C.text.r, C.text.g, C.text.b)
        for _, prof in ipairs(data.professions) do
            local profColor = prof.isPrimary and C.text or C.silver
            local line = prof.rank and string.format("  %s  %d / %d", L[prof.name], prof.rank, prof.maxRank or 0)
                or ("  " .. L[prof.name])   -- known from the guild roster only: no rank (issue #31)
            tip:AddLine(line, profColor.r, profColor.g, profColor.b)
        end
    end

    -- Attunement detail
    -- Uses GetEffectiveAttunements so only game-API-verified data is shown
    -- (no alt-propagation that could produce false "Done" for cross-account alts).
    local effAtts = GuildOS.AttunementTracker and GuildOS.AttunementTracker:GetEffectiveAttunements(data.key)
    if effAtts and #effAtts > 0 then
        local done, inProg, pending = {}, {}, {}
        for _, att in ipairs(effAtts) do
            if att.complete then
                tinsert(done, att)
            elseif att.progress and att.progress > 0 then
                tinsert(inProg, att)
            else
                tinsert(pending, att)
            end
        end

        tip:AddLine(" ")
        tip:AddLine(
            string.format(L["Attunements: (%d/%d)"], #done, #effAtts),
            C.text.r, C.text.g, C.text.b)

        for _, att in ipairs(done) do
            tip:AddLine(
                string.format("  [%s] %s", att.tier, att.name) .. "  " .. L["Done"],
                C.green.r, C.green.g, C.green.b)
        end
        for _, att in ipairs(inProg) do
            tip:AddLine(
                string.format("  [%s] %s  %d%%", att.tier, att.name,
                    math.floor((att.progress or 0) * 100)),
                C.textSoft.r, C.textSoft.g, C.textSoft.b)
        end
        for _, att in ipairs(pending) do
            tip:AddLine(
                string.format(L["  [%s] %s  Not started"], att.tier, att.name),
                C.red.r, C.red.g, C.red.b)
        end
    end

    if not data.hasAddonData then
        tip:AddLine(" ")
        tip:AddLine(L["Player does not have Guild OS installed"], C.red.r, C.red.g, C.red.b)
    elseif data.addonVersion and data.addonVersion ~= GuildOS.VERSION then
        tip:AddLine(" ")
        if CompareVersions(data.addonVersion, GuildOS.VERSION) < 0 then
            tip:AddLine(string.format(L["Guild OS v%s (outdated)"], data.addonVersion), C.red.r, C.red.g, C.red.b)
        else
            tip:AddLine(string.format("Guild OS v%s", data.addonVersion), C.label.r, C.label.g, C.label.b)
        end
    end

    -- Wishlist info (native)
    if GuildOS.db.guildWishlists and GuildOS.Wishlist then
        local wData = GuildOS.Wishlist:ListFor(data.key, data.name)   -- by the whole key on retail (#185)
        if wData and wData.wishlist and #wData.wishlist > 0 then
            local wColor = GuildOS.Wishlist and GuildOS.Wishlist.TypeColors.wishlist or { r=0.3, g=0.7, b=1.0 }
            tip:AddLine(" ")
            tip:AddLine(L["Wishlist:"], C.text.r, C.text.g, C.text.b)
            local shown = math.min(#wData.wishlist, 5)
            for j = 1, shown do
                local item = wData.wishlist[j]
                local iName = GuildOS.Wishlist and GuildOS.Wishlist:GetItemName(item.itemId) or string.format(L["Item #%s"], item.itemId or "?")
                local os = item.isOffspec and (" (" .. L["OS"] .. ")") or ""
                tip:AddLine("  #" .. (item.order or j) .. ": " .. iName .. os,
                    wColor.r, wColor.g, wColor.b)
            end
            if #wData.wishlist > 5 then
                tip:AddLine(string.format(L["  +%d more..."], #wData.wishlist - 5), 0.5, 0.5, 0.5)
            end
        end
    end

    tip:AddLine(" ")
    tip:AddLine(L["Left-click: detailed view"], 0.5, 0.5, 0.5)
    tip:AddLine(L["Right-click: whisper, invite, etc."], 0.5, 0.5, 0.5)
    if not locked then tip:AddLine(L["Shift-click: keep this card open (Esc closes it)"], 0.5, 0.5, 0.5) end

    tip:Show()
end

----------------------------------------------------------------------
-- Lista de Desejos (Wishlist) Guild Panel UI
----------------------------------------------------------------------
function GuildOS:CreateWishlistGuildPanel(parent, _mainFrame)
    local expandedChar = nil  -- key of currently expanded character
    local GAP = UI.GAP

    ----------------------------------------------------------------
    -- Top bar: status text. Flush with the Lists view's buttons above it, at x = 0 (#371): the
    -- whole panel sat 15px in.
    ----------------------------------------------------------------
    local topBar = CreateFrame("Frame", nil, parent)
    topBar:SetPoint("TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", 0, 0)
    topBar:SetHeight(26)

    local statusText = UI:CreateText(topBar, "", 11, C.text.r, C.text.g, C.text.b)
    statusText:SetPoint("LEFT", 0, 0)
    statusText:SetWidth(280)
    statusText:SetJustifyH("LEFT")

    -- "Minha Wishlist" button: open personal wishlist manager
    local myWishBtn = UI:CreateButton(topBar, L["My Wishlist"], 120, 24)
    myWishBtn:SetPoint("RIGHT", -134, 0)
    myWishBtn:SetScript("OnClick", function() GuildOS:ShowWishlistFrame() end)

    -- "Gerenciar Prios" button: officer only, opens prio modal
    local managePrioBtn = UI:CreateButton(topBar, L["Manage Prios"], 120, 24)
    managePrioBtn:SetPoint("RIGHT", 0, 0)
    managePrioBtn:SetScript("OnClick", function() GuildOS:ShowPrioModal() end)

    -- Hide officer button for non-officers; refresh on show
    parent:HookScript("OnShow", function()
        if GuildOS:IsOfficer() then
            managePrioBtn:Show()
        else
            managePrioBtn:Hide()
        end
    end)

    ----------------------------------------------------------------
    -- Search bar: a form label in the text colour and the shared field (#371), the count it
    -- filters right after it instead of floating at the far right.
    ----------------------------------------------------------------
    local SEARCH_Y = -26 - GAP
    local searchBar = CreateFrame("Frame", nil, parent)
    searchBar:SetPoint("TOPLEFT", 0, SEARCH_Y)
    searchBar:SetPoint("TOPRIGHT", 0, SEARCH_Y)
    searchBar:SetHeight(22)

    local searchIcon = UI:CreateText(searchBar, L["Search:"], 11, C.text.r, C.text.g, C.text.b)
    searchIcon:SetPoint("LEFT", 0, 0)

    local wishSearch = UI:CreateInput(searchBar, 200, 22, { max = 30, placeholder = L["Player name..."] })
    wishSearch:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)

    local charCountText = UI:CreateText(searchBar, "", UI.SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    charCountText:SetPoint("LEFT", wishSearch, "RIGHT", 12, 0)

    ----------------------------------------------------------------
    -- Column header: the shared header, no band, a 1px rule under it (#371)
    ----------------------------------------------------------------
    local HEADER_Y = SEARCH_Y - 22 - GAP
    local colHeader = UI:CreateTableHeader(parent)
    colHeader:SetPoint("TOPLEFT", 0, HEADER_Y)
    colHeader:SetPoint("TOPRIGHT", 0, HEADER_Y)

    local hName = UI:CreateHeaderText(colHeader, L["Character"], UI.SP.META)
    hName:SetPoint("LEFT", 28, 0)
    local hClass = UI:CreateHeaderText(colHeader, L["Class"], UI.SP.META)
    hClass:SetPoint("LEFT", 180, 0)
    local hWish = UI:CreateHeaderText(colHeader, L["Wishlist"], UI.SP.META)
    hWish:SetPoint("LEFT", 310, 0)
    local hAtt = UI:CreateHeaderText(colHeader, L["Att%"], UI.SP.META)
    hAtt:SetPoint("LEFT", 400, 0)

    ----------------------------------------------------------------
    -- Scrollable character list. The child keeps the scroll frame's width less the bar's gutter, and
    -- every row hangs from its two top corners (#371): the width was read once, as 720 while the tab
    -- was hidden, and the rows ran under the bar.
    ----------------------------------------------------------------
    local listScroll = CreateFrame("ScrollFrame", "GuildOSWishlistGuildScroll", parent, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
    listScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(listScroll, "GuildOSWishlistGuildScroll")

    local listChild = CreateFrame("Frame", "GuildOSWishlistGuildChild", listScroll)
    listChild:SetSize(1, 1)
    listScroll:SetScrollChild(listChild)
    UI:BindScrollChildWidth(listScroll, listChild)

    -- A row of the list, hung by both top corners from `left` in.
    local function hang(frame, left, y, h)
        frame:SetPoint("TOPLEFT", left, y)
        frame:SetPoint("TOPRIGHT", 0, y)
        frame:SetHeight(h)
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame:Show()
    end

    ----------------------------------------------------------------
    -- Populate character list
    ----------------------------------------------------------------
    local function PopulateWishlistPanel(filter)
        -- Clear previous
        local children = { listChild:GetChildren() }
        for _, ch in ipairs(children) do ch:Hide() end
        local regions = { listChild:GetRegions() }
        for _, rg in ipairs(regions) do rg:Hide() end

        local guildWl = GuildOS.Wishlist and GuildOS.Wishlist:AllLists() or GuildOS.db.guildWishlists
        -- Once per refresh. Retail has no LootMaster (personal loot, ADR-0026): the game's own table, as before.
        local allPrios, prioFromSite = GuildOS.db.lootPrios or {}, false
        if GuildOS.LootMaster then allPrios, prioFromSite = GuildOS.LootMaster:AllPrios() end
        local ly = -2
        local count = 0
        local totalCount = 0

        local sorted = {}
        if guildWl then
            for key, charData in pairs(guildWl) do
                totalCount = totalCount + 1
                if not filter or filter == "" or strlower(charData.name or key):find(strlower(filter), 1, true) then
                    table.insert(sorted, { key = key, data = charData })
                end
            end
        end
        table.sort(sorted, function(a, b)
            return (a.data.name or a.key) < (b.data.name or b.key)
        end)

        for _, entry in ipairs(sorted) do
            local charData = entry.data
            local charKey = entry.key
            local isExpanded = expandedChar == charKey
            count = count + 1

            local rowBg = (count % 2 == 0) and C.row2 or C.row1

            -- Character row (clickable)
            local charRow = CreateFrame("Button", nil, listChild, "BackdropTemplate")
            hang(charRow, 0, ly, 24)
            charRow:SetBackdropColor(rowBg.r, rowBg.g, rowBg.b, rowBg.a)

            -- Expand indicator
            local arrow = charRow:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(arrow, UI.SP.META)
            arrow:SetPoint("LEFT", 8, 0)
            arrow:SetTextColor(C.label.r, C.label.g, C.label.b)
            arrow:SetText(isExpanded and "v" or ">")

            -- Character name
            local cc = GuildOS.ClassColors and GuildOS.ClassColors[(charData.class or ""):upper()] or C.text
            local nameStr = charRow:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(nameStr, 11)
            nameStr:SetPoint("LEFT", 24, 0)
            nameStr:SetTextColor(cc.r, cc.g, cc.b)
            nameStr:SetText(charData.name or charKey)

            -- Class
            local classStr = charRow:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(classStr, UI.SP.META)
            classStr:SetPoint("LEFT", 180, 0)
            classStr:SetTextColor(cc.r, cc.g, cc.b, 0.7)
            classStr:SetText(charData.class or "")

            -- Wishlist count, in the text colours: no blue of its own (#371)
            local wishItems = charData.wishlist or {}
            local wishCount = charRow:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(wishCount, UI.SP.META)
            wishCount:SetPoint("LEFT", 310, 0)
            wishCount:SetWidth(60)
            if #wishItems > 0 then
                wishCount:SetTextColor(C.text.r, C.text.g, C.text.b)
                wishCount:SetText(string.format(L["%d items"], #wishItems))
            else
                wishCount:SetTextColor(C.labelDim.r, C.labelDim.g, C.labelDim.b)
                wishCount:SetText("-")
            end

            -- ATT%, in the status colours (#371: they were hand-mixed greens and reds)
            local attStr = "-"
            local attInk = C.labelDim
            if GuildOS.RaidTracker then
                -- On retail a list's name is its owner's whole key already (issue #185).
                local pKey = GuildOS.Client.isRetail and charData.name
                    or GuildOS:GetPlayerKey(charData.name or charKey, GetRealmName())
                local attVal = GuildOS.RaidTracker:GetAttendance25ManPercent(pKey) or 0
                if attVal > 0 then
                    attStr = attVal .. "%"
                    attInk = (attVal >= 60 and C.ok) or (attVal >= 40 and C.warn) or C.danger
                end
            end
            local attPct = charRow:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(attPct, nil, "tableNum")
            attPct:SetPoint("LEFT", 400, 0)
            attPct:SetWidth(50)
            attPct:SetTextColor(attInk.r, attInk.g, attInk.b)
            attPct:SetText(attStr)

            -- Officer prio indicator: a star if this character has any prios
            local hasPrio = false
            for _, prioList in pairs(allPrios) do
                for _, prioEntry in ipairs(prioList) do
                    if strlower(prioEntry.name or "") == charKey then
                        hasPrio = true
                        break
                    end
                end
                if hasPrio then break end
            end
            if hasPrio then
                local prioStar = charRow:CreateFontString(nil, "OVERLAY")
                GuildOS:ApplyFont(prioStar, 12)
                prioStar:SetPoint("LEFT", 460, 0)
                prioStar:SetTextColor(C.text.r, C.text.g, C.text.b)
                prioStar:SetText("*")
            end

            -- Hover
            charRow:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            end)
            charRow:SetScript("OnLeave", function(self)
                self:SetBackdropColor(rowBg.r, rowBg.g, rowBg.b, rowBg.a)
            end)

            -- Click to expand/collapse
            charRow:SetScript("OnClick", function()
                if expandedChar == charKey then
                    expandedChar = nil
                else
                    expandedChar = charKey
                end
                PopulateWishlistPanel(wishSearch:GetText())
            end)

            ly = ly - 26

            ----------------------------------------------------
            -- Expanded: wishlist items, on the table's own surfaces: no blue or gold bars, no gold
            -- wash, its captions the column headers' (#371)
            ----------------------------------------------------
            if isExpanded and (#wishItems > 0 or hasPrio) then
                local detailBg = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
                hang(detailBg, 0, ly, 1)
                detailBg:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)

                local detailLy = -4

                -- Section label
                local secLabel = listChild:CreateFontString(nil, "OVERLAY")
                GuildOS:ApplyFont(secLabel, nil, "colHeader")
                secLabel:SetPoint("TOPLEFT", 10, ly + detailLy)
                secLabel:SetTextColor(C.label.r, C.label.g, C.label.b)
                secLabel:SetText(string.format(L["WISHLIST  (%d)"], #wishItems))
                secLabel:Show()
                detailLy = detailLy - 16

                for _, item in ipairs(wishItems) do
                    local iRow = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
                    hang(iRow, 20, ly + detailLy, 18)
                    iRow:SetBackdropColor(C.row1.r, C.row1.g, C.row1.b, C.row1.a)

                    -- Order
                    local orderStr = iRow:CreateFontString(nil, "OVERLAY")
                    GuildOS:ApplyFont(orderStr, nil, "tableNum")
                    orderStr:SetPoint("LEFT", 8, 0)
                    orderStr:SetWidth(22)
                    orderStr:SetJustifyH("RIGHT")
                    orderStr:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
                    orderStr:SetText("#" .. (item.order or "?"))

                    -- Item name, up to the badges on the right
                    local qColor = C.text
                    if GuildOS.Wishlist and GuildOS.QualityColors then
                        local q = GuildOS.Wishlist:GetItemQuality(item.itemId)
                        qColor = GuildOS.QualityColors[q] or C.text
                    end
                    local itemName = GuildOS.Wishlist and GuildOS.Wishlist:GetItemName(item.itemId) or string.format(L["Item #%s"], item.itemId or "?")
                    local itemStr = iRow:CreateFontString(nil, "OVERLAY")
                    GuildOS:ApplyFont(itemStr, UI.SP.META)
                    itemStr:SetPoint("LEFT", 34, 0)
                    itemStr:SetPoint("RIGHT", -76, 0)
                    itemStr:SetJustifyH("LEFT")
                    itemStr:SetWordWrap(false)
                    itemStr:SetTextColor(qColor.r, qColor.g, qColor.b)
                    itemStr:SetText(itemName)

                    -- OS badge
                    if item.isOffspec then
                        local osBadge = iRow:CreateFontString(nil, "OVERLAY")
                        GuildOS:ApplyFont(osBadge, 8)
                        osBadge:SetPoint("RIGHT", -8, 0)
                        osBadge:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
                        osBadge:SetText(L["OS"])
                    end

                    -- Officer prio badge for this item + this character
                    local itemPrios = allPrios[item.itemId]
                    if itemPrios then
                        for prioIdx, prioEntry in ipairs(itemPrios) do
                            if strlower(prioEntry.name or "") == charKey then
                                local prioBadge = iRow:CreateFontString(nil, "OVERLAY")
                                GuildOS:ApplyFont(prioBadge, nil, "tableNum")
                                local rightOff = item.isOffspec and -28 or -8
                                prioBadge:SetPoint("RIGHT", rightOff, 0)
                                prioBadge:SetTextColor(C.text.r, C.text.g, C.text.b)
                                prioBadge:SetText("* #" .. (prioFromSite and prioEntry.order or prioIdx))
                                break
                            end
                        end
                    end

                    -- Tooltip
                    iRow:EnableMouse(true)
                    iRow:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink("item:" .. (item.itemId or 0))
                        GameTooltip:Show()
                    end)
                    iRow:SetScript("OnLeave", function(self)
                        self:SetBackdropColor(C.row1.r, C.row1.g, C.row1.b, C.row1.a)
                        GameTooltip:Hide()
                    end)

                    detailLy = detailLy - 20
                end

                -- Officer prio section: items where this character has prio but may not be on wishlist
                local prioBadges = {}
                for itemId, prioList in pairs(allPrios) do
                    for prioIdx, prioEntry in ipairs(prioList) do
                        if strlower(prioEntry.name or "") == charKey then
                            table.insert(prioBadges, { itemId = itemId, order = prioFromSite and prioEntry.order or prioIdx })
                            break
                        end
                    end
                end
                if #prioBadges > 0 then
                    table.sort(prioBadges, function(a, b) return a.order < b.order end)

                    -- Section separator: a 1px line, not gold (#371)
                    detailLy = detailLy - 4
                    local prioSep = UI:CreateSeparator(listChild)
                    prioSep:SetPoint("TOPLEFT", 20, ly + detailLy)
                    prioSep:SetPoint("TOPRIGHT", -20, ly + detailLy)
                    prioSep:Show()
                    detailLy = detailLy - 5

                    local prioLabel = listChild:CreateFontString(nil, "OVERLAY")
                    GuildOS:ApplyFont(prioLabel, nil, "colHeader")
                    prioLabel:SetPoint("TOPLEFT", 10, ly + detailLy)
                    prioLabel:SetTextColor(C.label.r, C.label.g, C.label.b)
                    prioLabel:SetText(string.format(L["OFFICIAL PRIORITY  (%d)"], #prioBadges))
                    prioLabel:Show()
                    detailLy = detailLy - 16

                    for _, badge in ipairs(prioBadges) do
                        local pRow = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
                        hang(pRow, 20, ly + detailLy, 18)
                        pRow:SetBackdropColor(C.row1.r, C.row1.g, C.row1.b, C.row1.a)

                        local starStr = pRow:CreateFontString(nil, "OVERLAY")
                        GuildOS:ApplyFont(starStr, UI.SP.META, "tableNum")
                        starStr:SetPoint("LEFT", 8, 0)
                        starStr:SetWidth(32)  -- "* #12" at 10px mono needs 30px
                        starStr:SetJustifyH("RIGHT")
                        starStr:SetTextColor(C.text.r, C.text.g, C.text.b)
                        starStr:SetText("* #" .. badge.order)

                        local pName = GuildOS.Wishlist and GuildOS.Wishlist:GetItemName(badge.itemId) or string.format(L["Item #%s"], badge.itemId)
                        local pqColor = C.text
                        if GuildOS.QualityColors and GuildOS.Wishlist then
                            local q = GuildOS.Wishlist:GetItemQuality(badge.itemId)
                            pqColor = GuildOS.QualityColors[q] or C.text
                        end
                        local pItemStr = pRow:CreateFontString(nil, "OVERLAY")
                        GuildOS:ApplyFont(pItemStr, UI.SP.META)
                        pItemStr:SetPoint("LEFT", 40, 0)
                        pItemStr:SetPoint("RIGHT", -80, 0)
                        pItemStr:SetJustifyH("LEFT")
                        pItemStr:SetWordWrap(false)
                        pItemStr:SetTextColor(pqColor.r, pqColor.g, pqColor.b)
                        pItemStr:SetText(pName)

                        pRow:EnableMouse(true)
                        pRow:SetScript("OnEnter", function(self)
                            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetHyperlink("item:" .. (badge.itemId or 0))
                            GameTooltip:Show()
                        end)
                        pRow:SetScript("OnLeave", function(self)
                            self:SetBackdropColor(C.row1.r, C.row1.g, C.row1.b, C.row1.a)
                            GameTooltip:Hide()
                        end)

                        detailLy = detailLy - 20
                    end
                end

                local detailHeight = math.abs(detailLy) + 4
                detailBg:SetHeight(detailHeight)
                ly = ly - detailHeight - 2
            end
        end

        -- An empty list says so, left-aligned under the header (#371): it was centred.
        if count == 0 and totalCount == 0 then
            local noData = listChild:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(noData, 11)
            noData:SetPoint("TOPLEFT", listChild, "TOPLEFT", 6, ly - 6)
            noData:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
            noData:SetText(L["No member has synced their wishlist yet.\nUse the Sync button in the My Wishlist window to send your data."])
            noData:SetJustifyH("LEFT")
            noData:Show()
            ly = ly - 40
        elseif count == 0 then
            local noMatch = listChild:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(noMatch, 11)
            noMatch:SetPoint("TOPLEFT", listChild, "TOPLEFT", 6, ly - 6)
            noMatch:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
            noMatch:SetText(L["No character found."])
            noMatch:SetJustifyH("LEFT")
            noMatch:Show()
            ly = ly - 26
        end

        local total = 0
        for _ in pairs(guildWl or {}) do total = total + 1 end
        charCountText:SetText(string.format(L["%d / %d members"], count, total))
        listChild:SetHeight(math.abs(ly) + 20)

        -- Update status text
        if total > 0 then
            statusText:SetText(string.format(L["|cff4CFF4C%d|r members synced their wishlist"], total))
        else
            statusText:SetText(L["|cffAAAAAANo wishlist data received|r"])
        end
    end

    -- Hooked: the field shows and hides its own placeholder (#371).
    wishSearch:HookScript("OnTextChanged", function(self)
        PopulateWishlistPanel(self:GetText())
    end)

    -- Re-render when the client finishes loading a queued item (async cache population).
    -- Debounce: batch rapid arrivals into a single repopulate 0.3 s later.
    GuildOS.Compat.RegisterEvent(parent, "GET_ITEM_INFO_RECEIVED")
    parent:SetScript("OnEvent", function(self, event)
        if event == "GET_ITEM_INFO_RECEIVED" and self:IsVisible() then
            if not self._itemInfoTimer then
                self._itemInfoTimer = true
                C_Timer.After(0.3, function()
                    self._itemInfoTimer = nil
                    if parent:IsVisible() then
                        PopulateWishlistPanel(wishSearch:GetText())
                    end
                end)
            end
        end
    end)

    parent:SetScript("OnShow", function()
        PopulateWishlistPanel(wishSearch:GetText())
    end)
end

----------------------------------------------------------------------
-- Recruitment Panel UI
----------------------------------------------------------------------
function GuildOS:CreateRecruitmentPanel(parent, _mainFrame)
    recruitInstances = recruitInstances + 1
    local uid = recruitInstances > 1 and tostring(recruitInstances) or ""

    ----------------------------------------------------------------
    -- Member view (non-officer): read-only recruitment status. Also an officer whose recruitment
    -- never started: the db and the officer modules are settled at login, so somebody who joined,
    -- founded or was promoted after it has no db.recruitment until a /reload (#255).
    ----------------------------------------------------------------
    local lateOfficer = GuildOS:IsOfficer() and not GuildOS.db.recruitment
    if lateOfficer or not GuildOS:IsOfficer() then
        -- Trials lives in the officers' view (issue #367): a deep link to it here says what to do.
        if lateOfficer then
            parent.SelectSub = function(key)
                if key == "trials" then
                    GuildOS:Print(L["You became an officer after logging in. Type /reload to manage recruiting."])
                end
            end
        end
        -- The Salão's Recruitment for a member (#449 phase 3): one parchment card titled as the entry, the guild's
        -- status in the title face, who updated it, the Discord and the guild's message in the reading face, and
        -- the two ways to help spread it.
        local INSET = 14
        local sheet = UI:CreateCard(parent, L["Recruitment"])
        sheet:SetPoint("TOPLEFT", 10, -8)
        sheet:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
        sheet:SetHeight(220)
        local ink, soft = C.paperInk, C.paperSoft

        -- Status badge
        local statusLabel = UI:CreateTitle(sheet, "", 15)
        statusLabel:SetPoint("TOPLEFT", INSET, -40)

        local updatedLabel = UI:CreateText(sheet, "", 11, soft.r, soft.g, soft.b)
        updatedLabel:SetPoint("TOPLEFT", INSET, -62)

        -- Discord: a form label in the card's ink (#371)
        local discordHeader = UI:CreateText(sheet, L["Discord:"], 12, ink.r, ink.g, ink.b)
        discordHeader:SetPoint("TOPLEFT", INSET, -86)
        local discordText = UI:CreateText(sheet, "—", 12, ink.r, ink.g, ink.b)
        discordText:SetPoint("LEFT", discordHeader, "RIGHT", 8, 0)

        -- Recruitment message preview, as a quote in the reading face
        local msgText = UI:CreateText(sheet, "", 13, ink.r, ink.g, ink.b)
        GuildOS:ApplyFont(msgText, 13, "reading")
        msgText:SetPoint("TOPLEFT", INSET, -110)
        msgText:SetJustifyH("LEFT")

        -- Both were fixed at 400/700, which is wider than the window this
        -- panel now opens in.
        UI:MakeResponsive(parent, function(_, w)
            discordText:SetWidth(math.max(120, w - 200))
            msgText:SetWidth(math.max(160, w - 20 - 2 * INSET))
            sheet:SetHeight(150 + math.max(14, msgText:GetStringHeight() or 14) + 36)
        end)

        -- Action row separator
        local actionSep = UI:CreateSeparator(sheet)
        actionSep:SetPoint("BOTTOMLEFT", INSET, 50)
        actionSep:SetPoint("BOTTOMRIGHT", -INSET, 50)
        actionSep:Hide()

        -- Send Now button (one-shot manual send)
        local sendNowBtn = UI:SetButtonVariant(UI:CreateButton(sheet, L["Send Now"], 130, 28), "primary")
        sendNowBtn:SetPoint("BOTTOMLEFT", INSET, 14)
        sendNowBtn:SetScript("OnClick", function()
            if GuildOS.Recruitment then GuildOS.Recruitment:ShowSendPopup() end
        end)

        -- Auto-Send toggle
        local autoBtn = UI:CreateButton(sheet, L["Auto-Send: OFF"], 140, 28)
        autoBtn:SetPoint("LEFT", sendNowBtn, "RIGHT", 8, 0)

        local autoStatusText = UI:CreateText(sheet, "", 11, soft.r, soft.g, soft.b)
        autoStatusText:SetPoint("LEFT", autoBtn, "RIGHT", 10, 0)

        -- The label says ON or OFF; no red or green fill of its own (#371).
        local function updateAutoBtn()
            -- Opt-in (#150): only an explicit choice helps.
            local participating = GuildOS.db.recruitParticipate == true
            if participating then
                autoBtn.label:SetText(L["Auto-Send: ON"])
                local interval = GuildOS.db.guildRecruitment and GuildOS.db.guildRecruitment.interval or 120
                local R = GuildOS.Recruitment
                local blocked = R and GuildOS:IsOnGuildDB() and not R:MemberMayPost()
                autoStatusText:SetText(blocked and L["Your rank does not post the guild's message."]
                    or string.format(L["(popup every %ds)"], interval))
            else
                autoBtn.label:SetText(L["Auto-Send: OFF"])
                autoStatusText:SetText("")
            end
        end

        autoBtn:SetScript("OnClick", function()
            if not GuildOS.Recruitment then return end
            local participating = GuildOS.db.recruitParticipate == true
            GuildOS.Recruitment:SetParticipation(not participating)
            updateAutoBtn()
        end)

        -- Refresh function — reads from guildRecruitment (synced) or officer's own DB
        local function refresh()
            local info = GuildOS.db.guildRecruitment
            -- Officers can also see their own configured data before any broadcast
            if not info and GuildOS:IsOfficer() then
                info = GuildOS.db.recruitment
            end

            if not info or info.enabled == nil then
                statusLabel:SetText("|cff6f5a3c" .. (lateOfficer and L["You became an officer after logging in. Type /reload to manage recruiting."]
                    or L["No recruitment data received yet."]) .. "|r")
                updatedLabel:SetText("")
                discordText:SetText("—")
                msgText:SetText("")
                return
            end

            if info.enabled then
                statusLabel:SetText("|TInterface\\COMMON\\Indicator-Green:14|t |cff2f6e33" .. L["Guild is actively recruiting!"] .. "|r")
            else
                statusLabel:SetText("|TInterface\\COMMON\\Indicator-Red:14|t |cff8f1b0b" .. L["Not currently recruiting"] .. "|r")
            end

            if info.updatedBy then
                updatedLabel:SetText(string.format(L["Last updated by %s"], info.updatedBy))
            else
                updatedLabel:SetText("")
            end

            discordText:SetText(info.discord ~= "" and info.discord or "—")
            msgText:SetText(info.message or "")
            updateAutoBtn()
        end

        GuildOS.recruitmentPanelRefresh = refresh
        parent:SetScript("OnShow", refresh)
        return
    end

    ----------------------------------------------------------------
    -- Officer view: sub-tabs. "Recruiting" (config, unchanged below),
    -- "Scanner" (the Recruit Scanner, embedded inline) and "Trials" (the
    -- trial tracker, the Trials tab until issue #367). Mirrors the
    -- sub-tab idiom in UI/ManagementPanel.lua:CreateManagementPanel.
    ----------------------------------------------------------------
    local root = parent
    -- The Officers' Room draws these screens as parchment cards on the wood (specs/salao/fase3.md, #449):
    -- UI/Forms.lua lays them out. P is the paper's inks (UI/Kit.lua); the chat line's preview stays on the
    -- wood's dark (C).
    local Kit = rawget(GuildOS, "Kit")
    local P = Kit and Kit.PAPER or C
    local Forms = GuildOS.Forms

    -- Left-anchored: UI:FlowBar reads GetWidth, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized.
    local BAR_INSET = 10   -- the bar's left inset, and the room it leaves on the right
    local bar = CreateFrame("Frame", nil, root)
    bar:SetPoint("TOPLEFT", BAR_INSET, -8)
    bar:SetSize(300, 28)
    UI:StyleSubTabBar(bar)

    -- Each sub-tab is an area on the wood under the bar, where its screen lays its cards (UI/Forms.lua): the
    -- area is what shows and hides and what the room moves when it hides the bar.
    local areas = {}
    local function makeSubPanel(key)
        local p = CreateFrame("Frame", nil, root)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        p:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -BAR_INSET, 10)
        p:Hide()
        areas[key] = p
        return p
    end

    local recruitingSub = makeSubPanel("recruiting")
    local scannerSub = makeSubPanel("scanner")
    local trialsSub = makeSubPanel("trials")

    -- root.subPanels[key] = { panel, refresh } — same shape as
    -- UI/ManagementPanel.lua. selectSub() below both flips visibility AND
    -- runs the active sub's refresh, so fields are always repopulated
    -- fresh, not left over from whatever they last held.
    root.subPanels = {}
    root.activeSub = "recruiting"

    local scannerRefresh
    if GuildOS.RecruitScanner then scannerRefresh = GuildOS.RecruitScanner:BuildInto(scannerSub) end
    root.subPanels.scanner = { panel = scannerSub, refresh = scannerRefresh }
    -- Built the first time it opens. CreateTrialsPanel redraws it on its own OnShow, so no refresh here.
    root.subPanels.trials = { panel = trialsSub, build = function(p) GuildOS:CreateTrialsPanel(p) end }

    -- `feature`: offered only while that feature may open (UI:IsFeatureAllowed: switched on,
    -- started, and Trials is officerOnly), as the registry's own entry says (issue #367).
    local RECRUIT_SUBTABS = {
        { key = "recruiting", label = L["Recruiting"] },
        { key = "scanner",    label = L["Scanner"] },
        { key = "trials",     label = L["Trials"], feature = "trials" },
    }
    local function subOffered(key)
        if root.subPanels[key] and root.subPanels[key].failed then return false end
        for _, t in ipairs(RECRUIT_SUBTABS) do
            if t.key == key then return not t.feature or UI:IsFeatureAllowed(UI:GetFeature(t.feature)) end
        end
        return false
    end

    local subTabBtns = {}

    -- A sub-tab not offered (Trials switched off, or a rank that lost the officers' view) falls
    -- back to Recruiting, deep links included.
    local function selectSub(key)
        if not subOffered(key) then key = "recruiting" end
        local info = root.subPanels[key]
        if info and info.build then
            local build = info.build
            info.build = nil
            -- A builder that errors is recorded and refused, not left half built (issue #367).
            local ok, err = pcall(build, info.panel)
            if not ok then
                info.failed = true
                GuildOS:RecordError("Recruitment " .. key .. ": " .. tostring(err))
                GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], L["Trials"]))
                key = "recruiting"
                info = root.subPanels[key]
            end
        end
        root.activeSub = key
        for k, i in pairs(root.subPanels) do
            i.panel:SetShown(k == key)
        end
        for k, btn in pairs(subTabBtns) do
            btn:SetActive(k == key)
        end
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    -- The Officers' Room lists these sub-tabs itself (#445): its side bar is the only one.
    UI:CollapsibleSubBar(root, bar, function() return areas end)
    root.SelectSub = selectSub   -- deep links: the Now tab, /gos open recruitment <sub>, /gos open trials

    for _, t in ipairs(RECRUIT_SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 90, true)
        btn:SetWidth(math.max(90, math.ceil(btn.label:GetStringWidth()) + 20))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
    end

    -- Flow the offered tabs only, so a sub-tab switched off leaves no gap in the bar.
    local function layoutTabs()
        local shown = {}
        for _, t in ipairs(RECRUIT_SUBTABS) do
            local btn = subTabBtns[t.key]
            local show = subOffered(t.key)
            btn:SetShown(show)
            if show then shown[#shown + 1] = btn end
        end
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = 28 })
    end

    ----------------------------------------------------------------
    -- The Recruiting sub-tab (#373, #449 the mockup's "Recruitment ad"): cards on the wood, two columns
    -- from Forms.TWO_W. On the left how the ad goes out: posting (on or off, the interval, Send now), the
    -- message beside the chat line it makes, the channels as pills, and which members help. On the right
    -- what greets and invites: the welcome, the auto-invite, the beacon and, where its module runs, the
    -- join requests. Each card saves on its own: a switch or a pill at once, a card's fields with its one
    -- Save (Enter in a field does the same).
    ----------------------------------------------------------------
    local WHITE = "Interface\\Buttons\\WHITE8x8"
    local R = GuildOS.Recruitment
    local board = UI:CreateBoard(recruitingSub, { name = "GuildOSRecruitScroll" .. uid })
    local function relayout() board:Layout() end
    local resetCursors

    -- A label above its field takes no colon: the one the form beside it had ("Interval (sec):", "Interval (s) :").
    local function noColon(s) return (tostring(s or ""):gsub("%s*:%s*$", "")) end
    -- The words the tab always showed, in the identity's ok and danger rather than the colour codes
    -- their keys carry (#373), so no string is added.
    local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local ON, OFF = plain(L["|cff4CFF4CON|r"]), plain(L["|cffFF4444OFF|r"])
    local function paint(fs, text, col)
        fs:SetText(text)
        fs:SetTextColor(col.r, col.g, col.b)
    end
    local function paintOnOff(fs, on) paint(fs, on and ON or OFF, on and P.ok or P.danger) end
    local function hex(c)
        return string.format("%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
            math.floor(c.b * 255 + 0.5))
    end
    -- A line on a card: a status word (its dot, `dot`) and a soft note after it, one line.
    local function StatusLine(card, withDot)
        local line = CreateFrame("Frame", nil, card)
        line:SetSize(1, 18)
        local dot
        if withDot then
            dot = line:CreateTexture(nil, "ARTWORK")
            dot:SetTexture(WHITE)
            dot:SetSize(8, 8)
            dot:SetPoint("LEFT", 0, 0)
        end
        local word = UI:CreateText(line, "", 12, P.text.r, P.text.g, P.text.b)
        word:SetPoint("LEFT", line, "LEFT", withDot and 14 or 0, 0)
        word:SetWordWrap(false)
        local after = Forms:Soft(line, "", 11)
        after:SetPoint("LEFT", word, "RIGHT", 10, 0)
        after:SetPoint("RIGHT", line, "RIGHT", 0, 0)
        after:SetWordWrap(false)
        line.dot, line.word, line.after = dot, word, after
        card:Add(line, { h = 18, wide = true })
        return line
    end
    -- Enter, and the field letting go, commit a field that saves on its own (the interval).
    local function commitOnLeave(box, commit)
        box:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
        box:HookScript("OnEditFocusLost", function(self) commit(self) end)
    end
    local GAP_PILL = 6

    ----------------------------------------------------------------
    -- Post in the channels: ON or OFF and its switch, the interval, Send now. There is no "next post in":
    -- the module's ticker (C_Timer.NewTicker) keeps no time of its next popup, and the tab keeps no clock.
    ----------------------------------------------------------------
    local postCard = board:Card(L["Post in the channels"], { col = 1 })
    local stateLine = StatusLine(postCard, true)
    local statusText, dot = stateLine.word, stateLine.dot
    local intervalBox = UI:CreateInput(postCard, 100, Forms.FIELD_H, { numeric = true, max = 5 })
    local function commitInterval(box)
        local val = tonumber(box:GetText())
        if val and val >= 60 then
            if val ~= GuildOS.db.recruitment.interval then
                GuildOS.db.recruitment.interval = val
                GuildOS:Print(string.format(L["Interval set to %ds."], val))
            end
        else
            box:SetText(tostring(GuildOS.db.recruitment.interval))
        end
    end
    commitOnLeave(intervalBox, commitInterval)
    postCard:Field(noColon(L["Interval (sec):"]), intervalBox, { w = 120 })
    -- What the interval does: the click Blizzard requires is the popup it opens.
    postCard:Note(L["Note: Blizzard requires a click to send channel messages. A popup will appear on interval."])
    local sendNowBtn = Forms:Button(postCard, L["Send Now"])
    sendNowBtn:SetScript("OnClick", function()
        if GuildOS.Recruitment then GuildOS.Recruitment:DoSendRecruitmentMessage() end
    end)
    local toggleBtn = Forms:Button(postCard, L["Enable"], "primary")
    postCard:Actions({ sendNowBtn, toggleBtn })

    -- ON or OFF, the words the Welcome card and /gos recruit status use (#371), and the dot in the same
    -- colour (#373). The switch says what a click does.
    local function UpdateRecruitStatus()
        local on = GuildOS.db.recruitment.enabled and true or false
        paintOnOff(statusText, on)
        local c = on and P.ok or P.danger
        dot:SetVertexColor(c.r, c.g, c.b, 1)
        stateLine.after:SetText(on and string.format(L["(popup every %ds)"], GuildOS.db.recruitment.interval or 120) or "")
        toggleBtn.label:SetText(on and L["Disable"] or L["Enable"])
        Forms:FitPill(toggleBtn)
    end
    toggleBtn:SetScript("OnClick", function()
        if GuildOS.Recruitment then
            GuildOS.Recruitment:Toggle()
            UpdateRecruitStatus()
            relayout()   -- "Désactiver" is wider than "Activer": the buttons flow again
        end
    end)

    ----------------------------------------------------------------
    -- The message and how it appears (#373): the field on the left, five lines tall, and beside it the line
    -- it makes in the first channel it goes to, cleaned as DoSendRecruitmentMessage cleans it, under this
    -- character's name, with its length against the game's 255. Under each other on a narrow card.
    ----------------------------------------------------------------
    local AREA_H, BESIDE_W, COUNT_WARN = 72, 420, 230
    local msgCard = board:Card(L["Recruitment message"], { col = 1 })
    local adBlock = CreateFrame("Frame", nil, msgCard)
    adBlock:SetSize(1, AREA_H)
    local msgArea = UI:CreateTextArea(adBlock, 200, AREA_H, { max = 255 })
    local msgBox = msgArea.edit
    local function commitMsg(box)
        local txt = box:GetText()
        if txt and txt ~= "" then
            -- Same as the welcome's (#270): the game refuses the text, the ad never goes out.
            local problem = GuildOS.Recruitment.ChatTextProblem(txt)
            if problem then return GuildOS:Print(problem) end
            GuildOS.db.recruitment.message = txt
            GuildOS:Print(L["Recruitment message updated."])
        end
    end
    -- A chat message has one line (ChatTextProblem): Enter saves the ad, and a line break pasted into
    -- the field becomes a space, as the send's SanitizeUserText does, not glued words. Enter typed is
    -- one line break right before the cursor: it simply goes, so a word it lands in is not split (#373).
    msgBox:SetScript("OnEnterPressed", function(self) commitMsg(self); self:ClearFocus() end)
    msgBox:HookScript("OnTextChanged", function(self, typed)
        local t = self:GetText() or ""
        if not (typed and t:find("[\r\n]")) then return end
        local cur = self.GetCursorPosition and self:GetCursorPosition() or 0
        local _, breaks = t:gsub("[\r\n]", "")
        if breaks == 1 and cur > 0 and t:sub(cur, cur):find("[\r\n]") then
            self:SetText(t:sub(1, cur - 1) .. t:sub(cur + 1))
            self:SetCursorPosition(cur - 1)
        else
            self:SetText((t:gsub("[\r\n]+", " ")))
        end
    end)

    local previewCap = Forms:Soft(adBlock, L["Preview"], 11)
    previewCap:SetWordWrap(false)
    local previewBox = UI:CreateDarkPanel(adBlock, nil, adBlock:GetFrameLevel() + 1)
    local previewText = UI:CreateText(previewBox, "", 12, C.text.r, C.text.g, C.text.b)   -- the chat's, on its dark
    previewText:SetPoint("TOPLEFT", 6, -6)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    previewText:SetWordWrap(true)
    local countText = UI:CreateText(adBlock, "", 11, P.textSoft.r, P.textSoft.g, P.textSoft.b)
    GuildOS:ApplyFont(countText, 11, "tableNum")
    countText:SetJustifyH("RIGHT")

    -- The line as it goes out: the first saved channel this character is in (the send skips the others),
    -- labelled as chat labels it ("2. Trade - City"), this character's name as chat writes it
    -- (Compat.PlayerName: WoW: Forever's has the surname), and the text cleaned and cut as the send
    -- does, raid icons dropped where the channel hides them. Nil where the ad would go nowhere.
    local function previewLine(text)
        local name, num, label
        for _, ch in ipairs(GuildOS.db.recruitment.channels or {}) do
            local n = R:ChannelName(ch)
            local id, full = GetChannelName(n)
            if (tonumber(id) or 0) > 0 then name, num, label = n, tonumber(id), full; break end
        end
        if not name then return nil end
        local msg = GuildOS:SanitizeUserText(text, R.MSG_MAX)
        if GuildOS.Compat.ChannelHidesRaidIcons(name, num) then msg = R:_StripRaidIcons(msg) end
        local where = string.format("[%d. %s]", num, type(label) == "string" and label ~= "" and label or name)
        return where .. " " .. (GuildOS.Compat.PlayerName() or "") .. ":", msg
    end
    local function previewHeight()
        return math.max(AREA_H, math.ceil(previewText:GetStringHeight() or 0) + 12)
    end
    local previewH = AREA_H
    local function updatePreview()
        local text = msgBox:GetText() or ""
        local head, msg = previewLine(text)
        local soft = "|cff" .. hex(C.textSoft)
        if head then
            previewText:SetText(soft .. head .. "|r " .. msg)
        else
            previewText:SetText(soft .. L["Join a channel to post the recruitment message."] .. "|r")
        end
        local n = #text
        countText:SetText(string.format("%d/%d", n, R.MSG_MAX))
        local col = (n > R.MSG_MAX and P.danger) or (n >= COUNT_WARN and P.warn) or P.textSoft
        countText:SetTextColor(col.r, col.g, col.b)
        -- A longer line wraps onto more lines: the preview grows, and everything under it moves.
        if previewHeight() ~= previewH then relayout() end
    end
    msgBox:HookScript("OnTextChanged", function() updatePreview() end)

    -- The field and the chat line beside it on a card wide enough, the line under the field otherwise.
    msgCard:Add(adBlock, { place = function(_, w)
        local beside = w >= BESIDE_W
        local colW = beside and math.floor((w - 12) / 2) or w
        msgArea:ClearAllPoints()
        msgArea:SetPoint("TOPLEFT", adBlock, "TOPLEFT", 0, -17)
        msgArea:SetWidth(colW)
        local x, top = beside and (colW + 12) or 0, beside and 0 or -(17 + AREA_H + 8)
        previewCap:ClearAllPoints()
        previewCap:SetPoint("TOPLEFT", adBlock, "TOPLEFT", x, top)
        previewCap:SetWidth(colW)
        previewText:SetWidth(colW - 12)
        previewH = previewHeight()
        previewBox:ClearAllPoints()
        previewBox:SetPoint("TOPLEFT", adBlock, "TOPLEFT", x, top - 17)
        previewBox:SetSize(colW, previewH)
        countText:ClearAllPoints()
        countText:SetPoint("TOPRIGHT", previewBox, "BOTTOMRIGHT", 0, -3)
        local rightH = 17 + previewH + 3 + 14
        local h = beside and math.max(17 + AREA_H, rightH) or (17 + AREA_H + 8 + rightH)
        adBlock:SetSize(math.max(1, w), h)
        return h
    end })
    local msgSave = Forms:Button(msgCard, L["Save"], "primary")
    msgSave:SetScript("OnClick", function() commitMsg(msgBox); msgBox:ClearFocus() end)
    msgCard:Actions({ msgSave })
    -- The ad's caption, above its field as the preview's is above it.
    local msgCap = Forms:Soft(adBlock, noColon(L["Message:"]), 11)
    msgCap:SetPoint("TOPLEFT", adBlock, "TOPLEFT", 0, 0)
    msgCap:SetPoint("RIGHT", msgArea, "RIGHT", 0, 0)
    msgCap:SetWordWrap(false)

    ----------------------------------------------------------------
    -- Channels: a pill for each the client names (issue #112: an English name is no channel on a French
    -- client), on while it posts there; a channel of one's own added by name, its pill under the field
    -- (issue #59), a click taking it off.
    ----------------------------------------------------------------
    local chanCard = board:Card(noColon(L["Channels:"]), { col = 1 })
    local CHAN_LIST = GuildOS.Recruitment:PresetChannels()
    local chanBtns = {}
    local function refreshChanBtns()
        local chs = GuildOS.db.recruitment.channels
        for _, b in ipairs(chanBtns) do
            Forms:SetOn(b, GuildOS.Recruitment:HasChannel(chs, b._ch))
        end
    end
    for i, ch in ipairs(CHAN_LIST) do
        local btn = Forms:Pill(chanCard, ch)
        btn._ch = ch
        btn:SetScript("OnClick", function()
            local chs = GuildOS.db.recruitment.channels
            if not GuildOS.Recruitment:RemoveChannel(chs, ch) then GuildOS.Recruitment:AddChannel(chs, ch) end
            refreshChanBtns()
            updatePreview()   -- the first channel may be another now
        end)
        chanBtns[i] = btn
    end
    chanCard:Flow(chanBtns, { gapX = GAP_PILL })

    local CUSTOM_MAX, CHIP_MAXW = 6, 180
    local chanBox = UI:CreateInput(chanCard, 130, Forms.FIELD_H, { max = 31 })
    local addChan = Forms:Button(chanCard, L["Add"])
    local customBtns = {}
    local customShown, customOver = 0, false
    local refreshCustomChans
    local function isPreset(name)
        return GuildOS.Recruitment:HasChannel(CHAN_LIST, name)
    end
    local function addChannel()
        if GuildOS.Recruitment:AddChannel(GuildOS.db.recruitment.channels, chanBox:GetText()) then
            chanBox:SetText("")
            refreshCustomChans()
            refreshChanBtns()
            updatePreview()
        elseif strtrim(chanBox:GetText()) ~= "" then
            GuildOS:Print(L["Already posting to: |cffFFFFFF"] .. strtrim(chanBox:GetText()) .. "|r")
        end
        chanBox:ClearFocus()
    end
    addChan:SetScript("OnClick", addChannel)
    chanBox:SetScript("OnEnterPressed", addChannel)
    chanBox.saveButton = addChan
    chanCard:Field(noColon(L["Other channel:"]), chanBox, { button = addChan })
    -- Over the pills it explains, only while there is one (#265).
    chanCard:Note(L["Click a channel below to stop posting to it."], { size = UI.SP.META, shown = function() return customShown > 0 end })
    -- A channel of one's own is on, so its pill is on like an on preset's, and keeps its x: a click takes it
    -- off the list (#371).
    for i = 1, CUSTOM_MAX do
        local b = Forms:Pill(chanCard, "", true)
        b:SetScript("OnClick", function(self)
            GuildOS.Recruitment:RemoveChannel(GuildOS.db.recruitment.channels, self._ch)
            refreshCustomChans()
            refreshChanBtns()
            updatePreview()
        end)
        b:Hide()
        customBtns[i] = b
    end
    chanCard:Flow(customBtns, { gapX = GAP_PILL, gap = 4, shown = function() return customShown > 0 end })
    local customMore = chanCard:Note("", { size = UI.SP.META, shown = function() return customOver end })
    refreshCustomChans = function()
        local shown = 0
        for _, ch in ipairs(GuildOS.db.recruitment.channels) do
            if not isPreset(ch) and shown < CUSTOM_MAX then
                shown = shown + 1
                local b = customBtns[shown]
                b._ch = ch
                b.label:SetText(GuildOS:ChipLabel(ch))
                Forms:FitPill(b, CHIP_MAXW)
                b:Show()
            end
        end
        for i = shown + 1, CUSTOM_MAX do customBtns[i]:Hide() end
        local custom = 0
        for _, ch in ipairs(GuildOS.db.recruitment.channels) do
            if not isPreset(ch) then custom = custom + 1 end
        end
        customMore:SetText(custom > CUSTOM_MAX and string.format(L["+%d more (/gos recruit channel list)"], custom - CUSTOM_MAX) or "")
        customShown, customOver = shown, custom > CUSTOM_MAX
        relayout()
    end

    ----------------------------------------------------------------
    -- Who helps: which members post the guild's message, every rank or up to one. It travels with the ad,
    -- and a member past it is never asked (#150). Then the broadcast that sends them the settings.
    ----------------------------------------------------------------
    local helpCard = board:Card(noColon(L["Members who help:"]), { col = 1 })
    local rankDrop = UI:CreateDropdown(helpCard, 200, Forms.FIELD_H)
    local ANY = -1
    local function rankText(limit)
        if limit == nil or limit == false or limit == ANY then return L["Any rank"] end
        local name = GuildControlGetRankName and GuildControlGetRankName(limit + 1)
        return string.format(L["Up to %s"], (name and name ~= "") and name or tostring(limit))
    end
    local function refreshRankDrop()
        local opts = {}
        for _, limit in ipairs(R:PostMaxRankChoices()) do
            opts[#opts + 1] = { value = limit or ANY, text = rankText(limit) }
        end
        rankDrop:SetOptions(opts)
        local cur = GuildOS.db.recruitment.postMaxRank
        rankDrop:SetValue(cur == nil and ANY or cur)
        -- A limit no longer on the list (the ranks changed) still shows what it is.
        if cur ~= nil and rankDrop.label:GetText() == "" then rankDrop.label:SetText(rankText(cur)) end
    end
    rankDrop.onSelect = function(_, value)
        R:SetPostMaxRank(value ~= ANY and value or nil)
    end
    helpCard:Field(L["Rank"], rankDrop, { w = 260 })
    local broadcastBtn = Forms:Button(helpCard, L["Broadcast to Members"], "primary")
    broadcastBtn:SetScript("OnClick", function()
        if GuildOS.Recruitment then GuildOS.Recruitment:BroadcastStatus() end
    end)
    helpCard:Actions({ broadcastBtn })

    ----------------------------------------------------------------
    -- Welcome message: the switch, the Discord, the messages (several, one drawn for each welcome, #419)
    -- with Add and a Remove at each row's right, and the rules' ending (#407). The switch and the ending
    -- save at once; the Discord and the messages with the card's Save.
    ----------------------------------------------------------------
    local welcomeCard = board:Card(L["Welcome Message (New Members)"], { col = 2 })
    local welcomeChk = welcomeCard:Check(noColon(L["Auto-Welcome:"]))
    local function UpdateWelcomeStatus()
        welcomeChk.checkbox:SetChecked(GuildOS.db.recruitment.welcomeEnabled and true or false)
    end
    welcomeChk.checkbox.onChanged = function(_, checked)
        GuildOS.db.recruitment.welcomeEnabled = checked and true or false
        local state = GuildOS.db.recruitment.welcomeEnabled and L["enabled"] or L["disabled"]
        GuildOS:Print(string.format(L["Welcome message %s."], state))
    end
    local discordBox = UI:CreateInput(welcomeCard, 200, Forms.FIELD_H, { max = 100 })
    welcomeCard:Field(noColon(L["Discord:"]), discordBox)

    local WELCOME_MAX = R.WELCOME_MAX
    local welcomeRows = {}
    local welcomeShown = 1          -- rows on show: the saved messages, and one just added and not saved
    local refreshWelcomes
    local welcomeList = CreateFrame("Frame", nil, welcomeCard)
    welcomeList:SetSize(1, 1)
    local welcomeCap = Forms:Soft(welcomeList, noColon(L["Welcome Msg:"]), UI.SP.META)
    welcomeCap:SetPoint("TOPLEFT", 0, 0)
    welcomeCap:SetWordWrap(false)
    for i = 1, WELCOME_MAX do
        local box = UI:CreateInput(welcomeList, 200, Forms.FIELD_H, { max = 255 })
        local remove = UI:SetButtonVariant(UI:CreateButton(welcomeList, L["Remove"], 40, UI.SP.HIT), "ghost")
        remove:SetWidth(math.ceil(remove.label:GetStringWidth() or 30) + 6)
        remove:SetScript("OnClick", function()
            for _, row in ipairs(welcomeRows) do row.box:ClearFocus() end
            if i <= #R.WelcomeList(GuildOS.db.recruitment) and not R:RemoveWelcome(i) then return end
            welcomeShown = math.max(1, welcomeShown - 1)
            refreshWelcomes()
        end)
        welcomeRows[i] = { box = box, remove = remove }
    end
    welcomeCard:Add(welcomeList, { place = function(_, w)
        welcomeCap:SetWidth(math.max(1, w))
        local y = 14 + Forms.LABEL_GAP   -- under the label, as a field's (Forms:MakeField)
        local saved = #R.WelcomeList(GuildOS.db.recruitment)
        local rw = 0
        for _, row in ipairs(welcomeRows) do rw = math.max(rw, row.remove:GetWidth()) end
        for i = 1, WELCOME_MAX do
            local row = welcomeRows[i]
            local on = i <= welcomeShown
            row.box:SetShown(on)
            -- The last saved message stays: only a row not saved yet, or one of several, goes.
            row.remove:SetShown(on and (i > saved or saved > 1))
            if on then
                row.box:ClearAllPoints()
                row.box:SetPoint("TOPLEFT", welcomeList, "TOPLEFT", 0, -y)
                row.box:SetWidth(math.max(40, w - rw - UI.SP.CELL))
                row.remove:ClearAllPoints()
                row.remove:SetPoint("RIGHT", welcomeList, "TOPRIGHT", 0, -(y + Forms.FIELD_H / 2))
                y = y + Forms.FIELD_H + Forms.ROW_GAP
            end
        end
        local h = y - Forms.ROW_GAP
        welcomeList:SetSize(math.max(1, w), h)
        return h
    end })
    local welcomeAdd = Forms:Button(welcomeCard, L["Add message"])
    welcomeCard:Flow({ welcomeAdd }, { shown = function() return welcomeShown < WELCOME_MAX end })
    welcomeCard:Note(L["Several messages: one is drawn at random for each welcome, never the same one twice in a row."])
    welcomeAdd:SetScript("OnClick", function()
        welcomeShown = math.min(WELCOME_MAX, #R.WelcomeList(GuildOS.db.recruitment) + 1)
        refreshWelcomes()
        welcomeRows[welcomeShown].box:SetFocus()
    end)
    -- And, the officer's choice, the invitation to read the guild's rules (#407): only while the guild has
    -- rules and the whole fits the game's 255 bytes; the popup's preview shows the text as it goes.
    local welcomeRules = welcomeCard:Check(L["End it with \"Type /gos rules\" when the guild has rules"])
    welcomeRules.checkbox:SetChecked(GuildOS.db.recruitment.welcomeRules == true)
    welcomeRules.checkbox.onChanged = function(_, checked) GuildOS.db.recruitment.welcomeRules = checked and true or false end

    -- The card's Save: the Discord (left alone while empty, as it always was) and every message shown.
    local function commitDiscord()
        local txt = discordBox:GetText()
        if txt and txt ~= "" and txt ~= GuildOS.db.recruitment.discord then
            GuildOS.db.recruitment.discord = txt
            GuildOS:Print(L["Discord link updated."])
        end
    end
    local function commitWelcome(i)
        local txt = welcomeRows[i].box:GetText()
        if not txt or txt == "" then return true end
        if R.WelcomeList(GuildOS.db.recruitment)[i] == txt then return true end
        -- A text the game would refuse is not kept: the welcome would just never come (#270).
        local ok, problem = R:SetWelcome(i, txt)
        if problem then GuildOS:Print(problem); return false end
        if ok then GuildOS:Print(L["Welcome message updated."]) end
        return true
    end
    local function saveWelcomeCard()
        commitDiscord()
        for i = 1, welcomeShown do
            if not commitWelcome(i) then break end
        end
        for _, row in ipairs(welcomeRows) do row.box:ClearFocus() end
        discordBox:ClearFocus()
        refreshWelcomes()
    end
    discordBox:SetScript("OnEnterPressed", function() saveWelcomeCard() end)
    for _, row in ipairs(welcomeRows) do row.box:SetScript("OnEnterPressed", function() saveWelcomeCard() end) end
    local welcomeSave = Forms:Button(welcomeCard, L["Save"], "primary")
    welcomeSave:SetScript("OnClick", saveWelcomeCard)
    welcomeCard:Actions({ welcomeSave })
    discordBox.saveButton = welcomeSave
    -- The rows from the saved list; a row added and not saved yet stays open, empty.
    refreshWelcomes = function()
        local list = R.WelcomeList(GuildOS.db.recruitment)
        welcomeShown = math.max(1, #list, math.min(welcomeShown, #list + 1))
        for i = 1, WELCOME_MAX do
            local box = welcomeRows[i].box
            if not box:HasFocus() then box:SetText(list[i] or "") end
        end
        relayout()
    end

    ----------------------------------------------------------------
    -- Auto-invite (issue #59): everything /gos autoinvite sets, through the same Recruitment setters the
    -- command uses. The switch, the class pills and the fallback save at once; the keyword and the level
    -- with the card's Save.
    ----------------------------------------------------------------
    local aiCard = board:Card(L["Auto-Invite (whisper keyword)"], { col = 2 })
    local function aiCfg() return GuildOS.db.recruitment and GuildOS.db.recruitment.autoInvite end
    -- A game that lets no addon invite (WoW: Forever, #256) says so first: there the keyword brings up the
    -- /ginvite line to copy, and the filters, which need the invite's /who, are greyed out below (#371, #373, #449).
    -- Where each invite wants a key press (C_GuildInfo.Invite is #hwevent), the card says which key.
    local canInvite = GuildOS.Client.isAnniversary or GuildOS.Client.isRetail
    if not canInvite then
        aiCard:Note(L["This game does not let an addon invite: when someone whispers the keyword, Guild OS shows the /ginvite line for you to copy and send."],
            { ink = P.warn })
    elseif GuildOS.Compat.NeedsHardware("guildInvite") and GuildOS.ActionQueue then
        local key = GuildOS.ActionQueue:KeyText()
        aiCard:Note(key and string.format(L["Each invite waits for a key press: %s, or a click on the queue's window."], key)
            or L["Each invite waits for a key press: bind Guild OS: next in the queue under Key Bindings, AddOns, or click the queue's window."])
    end
    local aiChk = aiCard:Check(L["Invite players who whisper the keyword"])
    aiChk.checkbox.onChanged = function(_, checked)
        local cfg = aiCfg()
        if cfg then cfg.enabled = checked and true or false end
    end
    local kwBox = UI:CreateInput(aiCard, 120, Forms.FIELD_H, { max = R.KEYWORD_MAX })
    local lvlBox = UI:CreateInput(aiCard, 60, Forms.FIELD_H, { numeric = true, max = 2 })
    local function commitKeyword()
        local cfg = aiCfg()
        if not cfg then return end
        local txt = kwBox:GetText()
        if txt ~= cfg.keyword then
            if R:SetAutoInviteKeyword(cfg, txt) then
                GuildOS:Print(L["Auto-invite keyword set to |cffFFFFFF"] .. cfg.keyword .. "|r.")
            end
        end
        kwBox:SetText(cfg.keyword)
    end
    local function commitLevel()
        local cfg = aiCfg()
        if not cfg then return end
        if tostring(cfg.minLevel) ~= lvlBox:GetText() then R:SetAutoInviteMinLevel(cfg, lvlBox:GetText()) end
        lvlBox:SetText(tostring(cfg.minLevel))
    end
    local function saveInvite()
        commitKeyword()
        commitLevel()
        kwBox:ClearFocus()
        lvlBox:ClearFocus()
    end
    kwBox:SetScript("OnEnterPressed", saveInvite)
    lvlBox:SetScript("OnEnterPressed", saveInvite)
    aiCard:Pair(Forms:MakeField(aiCard, noColon(L["Keyword:"]), kwBox),
                Forms:MakeField(aiCard, noColon(L["Min level:"]), lvlBox, { w = 90, hint = L["0 = any level"] }))

    aiCard:Note(noColon(L["Classes:"]), { gap = 10 })
    local classBtns = {}
    -- A class the invite takes is an on pill (#371), not a fill in its colour.
    local function refreshClassBtns()
        local cfg = aiCfg()
        for _, b in ipairs(classBtns) do
            Forms:SetOn(b, cfg and cfg.classes[b._class] and true or false)
        end
    end
    for i, class in ipairs(R.CLASSES) do
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
        local b = Forms:Pill(aiCard, name)
        b._class = class
        b:SetScript("OnClick", function(self)
            local cfg = aiCfg()
            if not cfg then return end
            R:SetAutoInviteClass(cfg, self._class, not cfg.classes[self._class])
            refreshClassBtns()
        end)
        classBtns[i] = b
    end
    aiCard:Flow(classBtns, { gapX = GAP_PILL, gap = Forms.LABEL_GAP })
    aiCard:Note(L["None selected = any class."], { size = UI.SP.META, gap = 3 })

    local fbDrop = UI:CreateDropdown(aiCard, 160, Forms.FIELD_H)
    fbDrop:SetOptions({ { value = "skip", text = L["Skip them"] }, { value = "invite", text = L["Invite them"] } })
    fbDrop.onSelect = function(_, value)
        local cfg = aiCfg()
        if cfg then R:SetAutoInviteFallback(cfg, value) end
    end
    local function refreshFallback()
        local cfg = aiCfg()
        fbDrop:SetValue((cfg and cfg.whoFallback == "invite") and "invite" or "skip")
    end
    aiCard:Field(noColon(L["Not confirmed:"]), fbDrop, { w = 220, hint = L["When /who can't confirm the level or class."] })
    -- How the invite decides, under what it explains.
    if canInvite then
        aiCard:Note(L["Banned players are never invited. Level and class filters are checked with /who."])
    end
    local aiSave = Forms:Button(aiCard, L["Save"], "primary")
    aiSave:SetScript("OnClick", saveInvite)
    aiCard:Actions({ aiSave })
    kwBox.saveButton, lvlBox.saveButton = aiSave, aiSave
    if not canInvite then
        -- The filters greyed out and kept, under the sentence that says why (#371): the copied line has no /who.
        lvlBox:EnableMouse(false)
        lvlBox:SetTextColor(P.disabled.r, P.disabled.g, P.disabled.b)
        for _, b in ipairs(classBtns) do b:SetEnabled(false) end
        fbDrop:SetEnabled(false)
    end

    local function refreshAutoInvite()
        local cfg = aiCfg()
        aiChk.checkbox:SetChecked(cfg and cfg.enabled or false)
        if not kwBox:HasFocus() then kwBox:SetText(cfg and cfg.keyword or "") end
        if not lvlBox:HasFocus() then lvlBox:SetText(cfg and tostring(cfg.minLevel or 0) or "") end
        refreshClassBtns()
        refreshFallback()
    end

    ----------------------------------------------------------------
    -- Recruitment Beacon (Chehul mesh): realm/city-wide ad, officer-only
    ----------------------------------------------------------------
    local beaconCard = board:Card(L["Recruitment Beacon (mesh)"])
    local beaconLine = StatusLine(beaconCard, false)
    local beaconStatus = beaconLine.word
    beaconCard:Note(L["Lives in the mesh and keeps circulating even when you're offline."])
    local editBeaconBtn = Forms:Button(beaconCard, L["Edit Beacon"])
    editBeaconBtn:SetScript("OnClick", function()
        if GuildOS.ShowRecruitBeacon then GuildOS:ShowRecruitBeacon() end
    end)
    beaconCard:Actions({ editBeaconBtn })
    local BROADCASTING, BEACON_OFF = plain(L["|cff4CFF4CBroadcasting|r"]), plain(L["|cff888888Off|r"])
    local function UpdateBeaconStatus()
        local ad = GuildOS.RecruitBeacon and GuildOS.RecruitBeacon:GetAd()
        local on = ad and ad.enabled
        paint(beaconStatus, on and BROADCASTING or BEACON_OFF, on and P.ok or P.textSoft)
    end
    UpdateBeaconStatus()

    ----------------------------------------------------------------
    -- Join requests: people with no guild who asked this one to take them
    ----------------------------------------------------------------
    -- Not where the module never starts (Anniversary): a card with nothing behind it.
    local UpdateRequestsStatus = function() end
    if GuildOS.JoinRequests and not GuildOS.Client.isAnniversary then
        local reqCard = board:Card(L["Join requests"])
        local reqLine = StatusLine(reqCard, false)
        local requestsStatus = reqLine.word
        reqCard:Note(L["Players who asked your guild to take them, from the game or from guildos.me."])
        local requestsBtn = Forms:Button(reqCard, L["Open the list"])
        requestsBtn:SetScript("OnClick", function()
            if GuildOS.ShowJoinRequests then GuildOS:ShowJoinRequests() end
        end)
        reqCard:Actions({ requestsBtn })
        local NONE = plain(L["|cff888888None|r"])
        UpdateRequestsStatus = function()
            -- A damaged row must not take the whole tab down with it.
            local ok, n = pcall(GuildOS.JoinRequests.OpenCount, GuildOS.JoinRequests)
            n = ok and n or 0
            if n > 0 then paint(requestsStatus, GuildOS:JoinRequestsOpenText(n), P.text) else paint(requestsStatus, NONE, P.textSoft) end
        end
        UpdateRequestsStatus()
    end

    -- The tab's OnShow fills every box before the tab is laid out, and an edit box filled before it is
    -- laid out shows nothing until its cursor moves (#158).
    local editBoxes = { intervalBox, msgBox, chanBox, kwBox, lvlBox, discordBox }
    for _, row in ipairs(welcomeRows) do editBoxes[#editBoxes + 1] = row.box end
    resetCursors = function()
        for _, box in ipairs(editBoxes) do
            if not box:HasFocus() then box:SetCursorPosition(0) end
        end
    end
    board.onLayout = resetCursors

    ----------------------------------------------------------------
    -- Refresh function for the "Recruiting" sub-tab. Registered into
    -- root.subPanels so selectSub() runs it whenever this sub-tab becomes
    -- active (and root's OnShow below re-runs it every time the officer
    -- opens the Recruitment tab).
    ----------------------------------------------------------------
    local function recruitingRefresh()
        local s = GuildOS.db.recruitment
        if not intervalBox:HasFocus() then intervalBox:SetText(tostring(s.interval or 120)) end
        refreshChanBtns()
        refreshAutoInvite()
        if not msgBox:HasFocus() then msgBox:SetText(s.message or "") end
        if not discordBox:HasFocus() then discordBox:SetText(s.discord or "") end
        refreshWelcomes()
        welcomeRules.checkbox:SetChecked(s.welcomeRules == true)
        refreshRankDrop()
        UpdateRecruitStatus()
        UpdateWelcomeStatus()
        UpdateBeaconStatus()
        UpdateRequestsStatus()
        updatePreview()
        refreshCustomChans()   -- last: it lays the tab out again
    end
    root.subPanels.recruiting = { panel = recruitingSub, refresh = recruitingRefresh }
    -- What the tests read.
    root.recruitBoard = board
    root.recruitCards = { post = postCard, message = msgCard, channels = chanCard, help = helpCard,
        welcome = welcomeCard, invite = aiCard, beacon = beaconCard }

    root:SetScript("OnShow", function()
        layoutTabs()
        selectSub(root.activeSub or "recruiting")
    end)

    ----------------------------------------------------------------
    -- Layout: the sub-tab bar wraps, and the screens lay their cards at the area's width.
    ----------------------------------------------------------------
    UI:MakeResponsive(root, function(_, w, h)
        bar:SetWidth(math.max(180, w - 2 * BAR_INSET))
        layoutTabs()
        local areaH = h - 8 - (bar:IsShown() and (bar:GetHeight() or 28) or 0) - 10
        local areaW = w - 2 * BAR_INSET
        for _, area in pairs(areas) do
            local b = rawget(area, "board")
            if b then b:Layout(areaW - UI.SCROLL_GUTTER, areaH) end
        end
    end)
end
