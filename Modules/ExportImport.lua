----------------------------------------------------------------------
-- Guild OS - Export / Import
-- Turns guild datasets (roster, attendance, loot, readiness, DKP
-- standings) into CSV (spreadsheets), TSV, or a Discord-ready fenced
-- code block; and parses CSV/TSV back into rows for import.
-- Business logic only — UI calls ShowExportPopup with the result.
----------------------------------------------------------------------
local Exporter = {}
BRutus.Exporter = Exporter
local Importer = {}
BRutus.Importer = Importer

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------
local function csvCell(v)
    v = tostring(v == nil and "" or v)
    if v:find('[",\n]') then
        v = '"' .. v:gsub('"', '""') .. '"'
    end
    return v
end

local function joinRow(cells, sep, esc)
    local out = {}
    for i = 1, #cells do
        out[i] = esc and esc(cells[i]) or tostring(cells[i])
    end
    return table.concat(out, sep)
end

-- Render (headers, rows) in the requested format: "csv" | "tsv" | "discord".
local function render(headers, rows, format, title)
    format = format or "csv"
    if format == "discord" then
        -- Fenced code block with tab-separated columns pastes cleanly into Discord.
        local lines = {}
        if title then lines[#lines + 1] = "**" .. title .. "**" end
        lines[#lines + 1] = "```"
        lines[#lines + 1] = table.concat(headers, "\t")
        for _, r in ipairs(rows) do lines[#lines + 1] = joinRow(r, "\t") end
        lines[#lines + 1] = "```"
        return table.concat(lines, "\n")
    elseif format == "tsv" then
        local lines = { table.concat(headers, "\t") }
        for _, r in ipairs(rows) do lines[#lines + 1] = joinRow(r, "\t") end
        return table.concat(lines, "\n")
    end
    -- csv (default)
    local lines = { joinRow(headers, ",", csvCell) }
    for _, r in ipairs(rows) do lines[#lines + 1] = joinRow(r, ",", csvCell) end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- Dataset builders → (headers, rows)
----------------------------------------------------------------------
function Exporter:RosterData()
    local headers = { "Name", "Class", "Level", "Rank", "iLvl", "Attendance%", "Attunements", "LastSeen" }
    local rows = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local d = BRutus.db.members[key] or {}
            local att = BRutus.RaidTracker and BRutus.RaidTracker:GetAttendance25ManPercent(key) or 0
            local attDone, attTotal = 0, 0
            if BRutus.AttunementTracker then
                attTotal = #BRutus.AttunementTracker:GetGuildColumns()
                for _, a in ipairs(BRutus.AttunementTracker:GetEffectiveAttunements(key)) do
                    if a.complete and a.questsTotal and a.questsTotal > 0 then attDone = attDone + 1 end
                end
            end
            local lastSeen = (d.lastUpdate and d.lastUpdate > 0) and date("%Y-%m-%d", d.lastUpdate) or ""
            rows[#rows + 1] = {
                short, classFile or "", level or 0, rankName or "",
                d.avgIlvl or 0, att, attDone .. "/" .. attTotal, lastSeen,
            }
        end
    end
    return headers, rows
end

function Exporter:AttendanceData()
    local headers = { "Name", "Class", "Attendance25%", "MissedStreak" }
    local rows = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local att, streak = 0, 0
            if BRutus.RaidTracker then
                att = BRutus.RaidTracker:GetAttendance25ManPercent(key) or 0
                streak = BRutus.RaidTracker:GetMissedStreak(key, nil, 99) or 0
            end
            rows[#rows + 1] = { short, classFile or "", att, streak }
        end
    end
    return headers, rows
end

function Exporter:LootData()
    local headers = { "Date", "Item", "Player", "Raid" }
    local rows = {}
    for _, e in ipairs(BRutus.db.lootHistory or {}) do
        local itemName = (e.itemLink and GetItemInfo(e.itemLink)) or e.itemName or "?"
        local dateStr = e.timestamp and date("%Y-%m-%d %H:%M", e.timestamp) or ""
        rows[#rows + 1] = { dateStr, itemName, e.player or "?", e.raid or "" }
    end
    return headers, rows
end

function Exporter:ReadinessData()
    local headers = { "Name", "Status", "iLvl", "Attune", "MissingEnchants", "MissingConsumes" }
    local rows = {}
    if BRutus.Readiness then
        for _, r in ipairs(BRutus.Readiness:GetReport()) do
            rows[#rows + 1] = {
                r.name, r.status, r.ilvl,
                (r.attTotal > 0) and (r.attDone .. "/" .. r.attTotal) or "",
                r.missEnch or 0,
                r.missCons == nil and "" or r.missCons,
            }
        end
    end
    return headers, rows
end

function Exporter:StandingsData()
    -- DKP / EPGP standings. Works once the Points module exists; until
    -- then it simply exports an empty table with the right header.
    local headers = { "Name", "Points", "Earned", "Spent" }
    local rows = {}
    if BRutus.Points and BRutus.Points.GetStandings then
        for _, s in ipairs(BRutus.Points:GetStandings()) do
            rows[#rows + 1] = { s.name, s.current or 0, s.earned or 0, s.spent or 0 }
        end
    end
    return headers, rows
end

function Exporter:EquityData()
    local headers = { "Player", "Items", "Epics", "Share%", "LastLoot" }
    local rows = {}
    if BRutus.LootEquity then
        for _, r in ipairs(BRutus.LootEquity:GetReport()) do
            rows[#rows + 1] = {
                r.name, r.total, r.epics, string.format("%.0f", r.share),
                r.last > 0 and date("%Y-%m-%d", r.last) or "",
            }
        end
    end
    return headers, rows
end

Exporter.DATASETS = {
    roster     = { fn = "RosterData",     title = "Roster" },
    attendance = { fn = "AttendanceData", title = "Attendance" },
    loot       = { fn = "LootData",       title = "Loot History" },
    readiness  = { fn = "ReadinessData",  title = "Readiness" },
    standings  = { fn = "StandingsData",  title = "DKP Standings" },
    equity     = { fn = "EquityData",     title = "Loot Equity" },
}

-- Build an export string. Returns (text, title) or nil for an unknown dataset.
function Exporter:Build(dataset, format)
    local def = self.DATASETS[dataset]
    if not def then return nil end
    local headers, rows = self[def.fn](self)
    return render(headers, rows, format, def.title), def.title
end

----------------------------------------------------------------------
-- Import: parse CSV/TSV text back into rows keyed by header.
----------------------------------------------------------------------
local function splitCSV(line)
    local cells, cur, inQ = {}, {}, false
    local i, n = 1, #line
    while i <= n do
        local ch = line:sub(i, i)
        if inQ then
            if ch == '"' then
                if line:sub(i + 1, i + 1) == '"' then cur[#cur + 1] = '"'; i = i + 1
                else inQ = false end
            else
                cur[#cur + 1] = ch
            end
        else
            if ch == '"' then inQ = true
            elseif ch == ',' then cells[#cells + 1] = table.concat(cur); cur = {}
            else cur[#cur + 1] = ch end
        end
        i = i + 1
    end
    cells[#cells + 1] = table.concat(cur)
    return cells
end

local function splitTSV(line)
    local cells = {}
    for c in (line .. "\t"):gmatch("([^\t]*)\t") do cells[#cells + 1] = c end
    return cells
end

-- Returns { headers = {...}, rows = { { [header]=value, ... }, ... } } or nil.
function Importer:Parse(text)
    if not text or text == "" then return nil end
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line:gsub("%s", "") ~= "" then lines[#lines + 1] = line end
    end
    if #lines == 0 then return nil end

    local split = lines[1]:find("\t") and splitTSV or splitCSV
    local headers = split(lines[1])
    for h = 1, #headers do headers[h] = strtrim(headers[h]) end

    local rows = {}
    for i = 2, #lines do
        local cells = split(lines[i])
        local row = {}
        for j = 1, #headers do row[headers[j]] = cells[j] and strtrim(cells[j]) or "" end
        rows[#rows + 1] = row
    end
    return { headers = headers, rows = rows }
end
