----------------------------------------------------------------------
-- BRutus Guild Manager - Feature Panels UI
-- UI panels for: Raids, Loot, Trials
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L

-- Session filter state: true = 25-man only, false = all raids
local _raidFilter25 = true

----------------------------------------------------------------------
-- RAID ATTENDANCE PANEL
----------------------------------------------------------------------
function BRutus:CreateRaidsPanel(parent, _mainFrame)
    local scrollParent = CreateFrame("Frame", nil, parent)
    scrollParent:SetPoint("TOPLEFT", 10, -10)
    scrollParent:SetPoint("BOTTOMRIGHT", -10, 10)

    -- Title
    local title = UI:CreateTitle(scrollParent, L["Raid Attendance"], 14)
    title:SetPoint("TOPLEFT", 0, 0)

    -- Status text
    local statusText = UI:CreateText(scrollParent, "", 10, C.silver.r, C.silver.g, C.silver.b)
    statusText:SetPoint("TOPLEFT", 200, -4)

    ----------------------------------------------------------------
    -- Sessions section (top ~40%)
    ----------------------------------------------------------------
    local sessionsLabel = UI:CreateHeaderText(scrollParent, L["Sessions"], 11)
    sessionsLabel:SetPoint("TOPLEFT", 0, -28)

    -- Filter toggle buttons
    local filterAllBtn  = UI:CreateButton(scrollParent, L["All"], 58, 18)
    local filter25Btn   = UI:CreateButton(scrollParent, L["25-man"], 62, 18)
    filterAllBtn:SetPoint("LEFT", sessionsLabel, "RIGHT", 10, 0)
    filter25Btn:SetPoint("LEFT", filterAllBtn,   "RIGHT",  4, 0)

    local sessionScroll = CreateFrame("ScrollFrame", "BRutusRaidSessionScroll", scrollParent, "UIPanelScrollFrameTemplate")
    sessionScroll:SetPoint("TOPLEFT",     0,   -50)
    sessionScroll:SetPoint("BOTTOMRIGHT", -10, 250)
    UI:SkinScrollBar(sessionScroll, "BRutusRaidSessionScroll")

    local sessionContent = CreateFrame("Frame", nil, sessionScroll)
    sessionContent:SetSize(800, 1)
    sessionScroll:SetScrollChild(sessionContent)

    ----------------------------------------------------------------
    -- Attendance section (bottom ~50%)
    ----------------------------------------------------------------
    local attLabel = UI:CreateHeaderText(scrollParent, L["Member Attendance — 25-man only"], 11)
    attLabel:SetPoint("BOTTOMLEFT", 0, 236)

    local attScroll = CreateFrame("ScrollFrame", "BRutusAttendanceScroll", scrollParent, "UIPanelScrollFrameTemplate")
    attScroll:SetPoint("BOTTOMLEFT",  0,   10)
    attScroll:SetPoint("BOTTOMRIGHT", -10, 10)
    attScroll:SetHeight(220)
    UI:SkinScrollBar(attScroll, "BRutusAttendanceScroll")

    local attContent = CreateFrame("Frame", nil, attScroll)
    attContent:SetSize(800, 1)
    attScroll:SetScrollChild(attContent)

    ----------------------------------------------------------------
    -- Filter button wiring
    ----------------------------------------------------------------
    local function SetFilterActive(only25)
        _raidFilter25 = only25
        if only25 then
            filter25Btn:LockHighlight()
            filterAllBtn:UnlockHighlight()
        else
            filterAllBtn:LockHighlight()
            filter25Btn:UnlockHighlight()
        end
        BRutus:RefreshRaidsPanel(sessionContent, attContent, statusText)
    end

    filterAllBtn:SetScript("OnClick", function() SetFilterActive(false) end)
    filter25Btn:SetScript("OnClick",  function() SetFilterActive(true)  end)

    parent:SetScript("OnShow", function()
        -- Store refs so remote deletions can refresh the panel
        BRutus.RaidsPanelOpen = {
            sessionContent = sessionContent,
            attContent     = attContent,
            statusText     = statusText,
        }
        SetFilterActive(_raidFilter25)
    end)
    parent:SetScript("OnHide", function()
        BRutus.RaidsPanelOpen = nil
    end)
end

-- Session expand state (persists while panel is shown)
local _sessionExpanded = {}
local _groupExpanded   = {}

function BRutus:RefreshRaidsPanel(sessionContent, attContent, statusText)
    if not BRutus.RaidTracker then return end

    -- Clear existing children
    for _, child in pairs({ sessionContent:GetChildren() }) do child:Hide() end
    for _, child in pairs({ attContent:GetChildren()     }) do child:Hide() end

    local totalAll  = BRutus.RaidTracker:GetTotalSessions()
    local total25   = BRutus.RaidTracker:GetTotal25ManSessions()
    local curGroup  = BRutus.RaidTracker:GetCurrentGroup()
    local groupStr  = curGroup ~= "" and ("|cffFFD700" .. curGroup .. "|r  ·  ") or ""
    local trackStr  = BRutus.RaidTracker.trackingActive
                      and "|cff00ff00" .. L["Tracking"] .. "|r" or "|cff888888" .. L["Idle"] .. "|r"
    statusText:SetText(groupStr .. totalAll .. L[" lockouts ("] .. total25 .. L[" 25-man)  |  "] .. trackStr)

    ----------------------------------------------------------------
    -- Sessions grouped by instance + TBC reset week (Tuesday reset)
    ----------------------------------------------------------------
    local sessions = BRutus.RaidTracker:GetRecentSessions(200, _raidFilter25, true)

    -- TBC weekly reset epoch: 2006-01-03 00:00 UTC (a known Tuesday)
    local TUESDAY_EPOCH = 1136246400
    local WEEK_SECS     = 7 * 86400

    -- Build groups keyed by "instanceID_weekNum"
    local groups     = {}
    local groupOrder = {}

    for _, s in ipairs(sessions) do
        local sd        = s.data
        local startTime = sd.startTime or s.id
        local weekNum   = math.floor((startTime - TUESDAY_EPOCH) / WEEK_SECS)
        local sgTag     = sd.groupTag or ""
        local groupKey  = (sd.instanceID or 0) .. "_" .. weekNum .. "|" .. sgTag

        if not groups[groupKey] then
            local wStart = TUESDAY_EPOCH + weekNum * WEEK_SECS
            groups[groupKey] = {
                key        = groupKey,
                instanceID = sd.instanceID,
                name       = sd.name or L["Unknown"],
                groupTag   = sgTag,
                weekNum    = weekNum,
                weekStart  = wStart,
                sessions   = {},
                allPlayers = {},
                kills      = 0,
                wipes      = 0,
            }
            table.insert(groupOrder, groupKey)
        end

        local g = groups[groupKey]
        table.insert(g.sessions, s)

        for k in pairs(sd.players or {}) do g.allPlayers[k] = true end
        for _, enc in ipairs(sd.encounters or {}) do
            if enc.success then g.kills = g.kills + 1
            else                g.wipes = g.wipes + 1 end
        end
    end

    -- Sort groups: most recent week first; within same week, raid name A-Z
    table.sort(groupOrder, function(a, b)
        local ga, gb = groups[a], groups[b]
        if ga.weekNum ~= gb.weekNum then return ga.weekNum > gb.weekNum end
        return ga.name < gb.name
    end)

    local yOff = 0

    for _, groupKey in ipairs(groupOrder) do
        local g          = groups[groupKey]
        local isGroupExp = _groupExpanded[groupKey]
        local is25       = BRutus.RaidTracker:Is25Man(g.instanceID)
        local gRowH      = 26

        -- Count unique players
        local uPlayers = 0
        for _ in pairs(g.allPlayers) do uPlayers = uPlayers + 1 end

        -- Group header row
        local gRow = CreateFrame("Button", nil, sessionContent, "BackdropTemplate")
        gRow:SetSize(sessionContent:GetWidth() - 10, gRowH)
        gRow:SetPoint("TOPLEFT", 0, -yOff)
        gRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        gRow:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

        -- Expand arrow
        UI:CreateText(gRow, isGroupExp and "▼" or "▶", 9, C.accent.r, C.accent.g, C.accent.b)
            :SetPoint("LEFT", 4, 0)

        -- Raid name (gold for 25-man, silver for 10-man)
        local nameClr = is25 and C.gold or C.silver
        local nameLabel = g.name
        if g.groupTag and g.groupTag ~= "" then
            nameLabel = "|cff9966FF[" .. g.groupTag .. "]|r " .. nameLabel
        end
        UI:CreateText(gRow, nameLabel, 11, nameClr.r, nameClr.g, nameClr.b)
            :SetPoint("LEFT", 18, 0)

        -- Week range label  e.g.  "22/04 – 28/04"
        local weekLabel = date("%d/%m", g.weekStart) .. " – " .. date("%d/%m", g.weekStart + 6 * 86400)
        UI:CreateText(gRow, weekLabel, 10, C.silver.r, C.silver.g, C.silver.b)
            :SetPoint("LEFT", 170, 0)

        -- Session count
        UI:CreateText(gRow, #g.sessions .. L[" sess."], 9, C.accentDim.r, C.accentDim.g, C.accentDim.b)
            :SetPoint("LEFT", 280, 0)

        -- Unique player count
        UI:CreateText(gRow, uPlayers .. L[" players"], 9, C.white.r, C.white.g, C.white.b)
            :SetPoint("LEFT", 340, 0)

        -- Kills / wipes summary
        local encStr = g.kills .. L[" kills"]
        if g.wipes > 0 then encStr = encStr .. " / " .. g.wipes .. L[" wipes"] end
        local encClr = g.kills > 0 and C.green or C.silver
        UI:CreateText(gRow, encStr, 9, encClr.r, encClr.g, encClr.b)
            :SetPoint("LEFT", 420, 0)

        local capturedGKey = groupKey
        gRow:SetScript("OnClick", function()
            _groupExpanded[capturedGKey] = not _groupExpanded[capturedGKey]
            BRutus:RefreshRaidsPanel(sessionContent, attContent, statusText)
        end)
        gRow:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
        end)
        gRow:SetScript("OnLeave", function(self)
            self:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)
        end)

        yOff = yOff + gRowH + 2

        -- If expanded, show individual sessions inside this group (indented)
        if isGroupExp then
            for idx, s in ipairs(g.sessions) do
                local sd    = s.data
                local isExp = _sessionExpanded[s.id]
                local rowH  = 22

                local row = CreateFrame("Button", nil, sessionContent, "BackdropTemplate")
                row:SetSize(sessionContent:GetWidth() - 30, rowH)
                row:SetPoint("TOPLEFT", 20, -yOff)
                row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                local bg = (idx % 2 == 1) and C.row1 or C.row2
                row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)

                -- Expand arrow
                UI:CreateText(row, isExp and "▼" or "▶", 8, C.accent.r, C.accent.g, C.accent.b)
                    :SetPoint("LEFT", 4, 0)

                -- Date + time
                local dateStr = date("%a %d/%m  %H:%M", sd.startTime or 0)
                UI:CreateText(row, dateStr, 9, C.silver.r, C.silver.g, C.silver.b)
                    :SetPoint("LEFT", 16, 0)

                -- Duration
                local dur = sd.duration or (sd.endTime and sd.startTime and (sd.endTime - sd.startTime))
                if dur then
                    local durStr = format("%dh%02dm", floor(dur / 3600), floor((dur % 3600) / 60))
                    UI:CreateText(row, durStr, 9, C.silver.r, C.silver.g, C.silver.b)
                        :SetPoint("LEFT", 165, 0)
                end

                -- Player count
                local pCount = BRutus.RaidTracker:CountTable(sd.players or {})
                UI:CreateText(row, pCount .. L[" players"], 9, C.white.r, C.white.g, C.white.b)
                    :SetPoint("LEFT", 215, 0)

                -- Boss kills / wipes
                local sk, sw = 0, 0
                for _, enc in ipairs(sd.encounters or {}) do
                    if enc.success then sk = sk + 1 else sw = sw + 1 end
                end
                local sEncStr = sk .. L[" kills"]
                if sw > 0 then sEncStr = sEncStr .. " / " .. sw .. L[" wipes"] end
                local sEncClr = sk > 0 and C.green or C.silver
                UI:CreateText(row, sEncStr, 9, sEncClr.r, sEncClr.g, sEncClr.b)
                    :SetPoint("LEFT", 300, 0)

                -- Delete button (officer only)
                if BRutus:IsOfficer() then
                    local delBtn = UI:CreateButton(row, L["X"], 20, 16)
                    delBtn:SetPoint("RIGHT", -2, 0)
                    local capturedSID = s.id
                    delBtn:SetScript("OnClick", function()
                        BRutus.RaidTracker:DeleteSession(capturedSID)
                        _sessionExpanded[capturedSID] = nil
                        BRutus:RefreshRaidsPanel(sessionContent, attContent, statusText)
                    end)
                end

                local capturedID = s.id
                row:SetScript("OnClick", function()
                    _sessionExpanded[capturedID] = not _sessionExpanded[capturedID]
                    BRutus:RefreshRaidsPanel(sessionContent, attContent, statusText)
                end)
                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
                end)
                row:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
                end)

                yOff = yOff + rowH + 2

                -- Expanded: per-player breakdown (same as before)
                if isExp then
                    local snapshots = sd.snapshots or {}
                    local firstSnap = snapshots[1]
                    local lastSnap  = snapshots[#snapshots]

                    local playerList = {}
                    for key in pairs(sd.players or {}) do
                        local shortName  = key:match("^([^-]+)") or key
                        local memberData = BRutus.db.members and BRutus.db.members[key]
                        local class      = memberData and memberData.class or nil

                        local wasLate   = firstSnap and firstSnap.members and not firstSnap.members[key]
                        local leftEarly = lastSnap  and lastSnap.members  and not lastSnap.members[key]

                        local consumeChecks, consumeHits = 0, 0
                        for _, snap in ipairs(snapshots) do
                            if snap.members and snap.members[key] then
                                consumeChecks = consumeChecks + 1
                                if snap.members[key].hasConsumes then consumeHits = consumeHits + 1 end
                            end
                        end
                        local noConsumes = consumeChecks > 0 and (consumeHits / consumeChecks) < 0.5

                        local score = 100
                        if wasLate    then score = score - (BRutus.RaidTracker.PENALTIES.LATE       or 10) end
                        if leftEarly  then score = score - (BRutus.RaidTracker.PENALTIES.LEFT_EARLY or 10) end
                        if noConsumes then score = score - (BRutus.RaidTracker.PENALTIES.NO_CONSUMES or 10) end
                        score = math.max(0, math.min(100, score))

                        table.insert(playerList, {
                            key = key, name = shortName, class = class,
                            score = score, wasLate = wasLate, leftEarly = leftEarly,
                            noConsumes = noConsumes, consumeHits = consumeHits, consumeChecks = consumeChecks,
                        })
                    end

                    table.sort(playerList, function(a, b)
                        if a.score ~= b.score then return a.score > b.score end
                        local ca = a.class or "ZZZZ"; local cb2 = b.class or "ZZZZ"
                        if ca ~= cb2 then return ca < cb2 end
                        return a.name < b.name
                    end)

                    local hdrFrame = CreateFrame("Frame", nil, sessionContent, "BackdropTemplate")
                    hdrFrame:SetSize(sessionContent:GetWidth() - 50, 16)
                    hdrFrame:SetPoint("TOPLEFT", 40, -yOff)
                    hdrFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                    hdrFrame:SetBackdropColor(0.040, 0.040, 0.055, 1)
                    local function Hdr(txt, x)
                        UI:CreateText(hdrFrame, txt, 8, C.accent.r, C.accent.g, C.accent.b):SetPoint("LEFT", x, 0)
                    end
                    Hdr(L["PLAYER"], 6); Hdr(L["SCORE"], 120); Hdr(L["LATE"], 170); Hdr(L["LEFT EARLY"], 210); Hdr(L["NO CONS"], 290)
                    yOff = yOff + 18

                    for pIdx, p in ipairs(playerList) do
                        local pRow = CreateFrame("Frame", nil, sessionContent, "BackdropTemplate")
                        pRow:SetSize(sessionContent:GetWidth() - 50, 18)
                        pRow:SetPoint("TOPLEFT", 40, -yOff)
                        pRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                        local pbg = (pIdx % 2 == 1) and { r=0.05, g=0.04, b=0.09 } or { r=0.07, g=0.06, b=0.12 }
                        pRow:SetBackdropColor(pbg.r, pbg.g, pbg.b, 0.9)

                        local cr, cg, cb = BRutus:GetClassColor(p.class)
                        local nameT = UI:CreateText(pRow, p.name, 9, cr, cg, cb)
                        nameT:SetPoint("LEFT", 6, 0); nameT:SetWidth(110)

                        local sr, sg, sb = C.green.r, C.green.g, C.green.b
                        if p.score < 75 then sr, sg, sb = C.gold.r, C.gold.g, C.gold.b end
                        if p.score < 50 then sr, sg, sb = C.red.r,  C.red.g,  C.red.b  end
                        UI:CreateText(pRow, p.score .. "%", 9, sr, sg, sb):SetPoint("LEFT", 120, 0)

                        local function Flag(x, val, redTxt, greenTxt)
                            local fr, fg, fb = val and C.red.r or C.green.r, val and C.red.g or C.green.g, val and C.red.b or C.green.b
                            UI:CreateText(pRow, val and redTxt or greenTxt, 8, fr, fg, fb):SetPoint("LEFT", x, 0)
                        end
                        Flag(170, p.wasLate,   L["LATE"], L["OK"])
                        Flag(210, p.leftEarly, L["LEFT"], L["OK"])

                        local consStr = p.consumeChecks > 0 and format("%d/%d", p.consumeHits, p.consumeChecks) or "-"
                        local cr2 = not p.noConsumes and C.green or C.red
                        UI:CreateText(pRow, consStr, 8, cr2.r, cr2.g, cr2.b):SetPoint("LEFT", 290, 0)

                        yOff = yOff + 20
                    end
                    yOff = yOff + 6
                end
            end -- for sessions in group
        end -- if isGroupExp
    end -- for groups
    sessionContent:SetHeight(math.max(1, yOff))

    ----------------------------------------------------------------
    -- Attendance list — always 25-man stats regardless of filter
    -- Nested structure: attendance[groupTag][playerKey]
    ----------------------------------------------------------------
    local attData = BRutus.db.raidTracker and BRutus.db.raidTracker.attendance or {}
    local attList = {}
    for groupTag, groupAtt in pairs(attData) do
        if type(groupAtt) == "table" then
            for key, att in pairs(groupAtt) do
                if (att.raids25 or 0) > 0 then
                    table.insert(attList, { key = key, data = att, groupTag = groupTag })
                end
            end
        end
    end
    table.sort(attList, function(a, b)
        -- Sort by group first, then by attendance % descending
        if a.groupTag ~= b.groupTag then return a.groupTag < b.groupTag end
        local pa = BRutus.RaidTracker:GetAttendance25ManPercent(a.key, a.groupTag)
        local pb = BRutus.RaidTracker:GetAttendance25ManPercent(b.key, b.groupTag)
        if pa == pb then
            return (a.data.raids25 or 0) > (b.data.raids25 or 0)
        end
        return pa > pb
    end)

    -- Column headers
    local attHdr = CreateFrame("Frame", nil, attContent, "BackdropTemplate")
    attHdr:SetSize(attContent:GetWidth() - 10, 16)
    attHdr:SetPoint("TOPLEFT", 0, 0)
    attHdr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    attHdr:SetBackdropColor(0.040, 0.040, 0.055, 1)
    local function AHdr(txt, x)
        local t = UI:CreateText(attHdr, txt, 8, C.accent.r, C.accent.g, C.accent.b)
        t:SetPoint("LEFT", x, 0)
    end
    AHdr(L["PLAYER"], 6); AHdr(L["GROUP"], 145); AHdr(L["ATT%"], 240); AHdr(L["RAIDS"], 295); AHdr(L["AVG SCORE"], 355); AHdr(L["LAST RAID"], 450)

    yOff = 20
    local lastGroupTag = nil
    for idx, entry in ipairs(attList) do
        -- Group separator header when the group changes
        if entry.groupTag ~= lastGroupTag then
            lastGroupTag = entry.groupTag
            local ghRow = CreateFrame("Frame", nil, attContent, "BackdropTemplate")
            ghRow:SetSize(attContent:GetWidth() - 10, 16)
            ghRow:SetPoint("TOPLEFT", 0, -yOff)
            ghRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            ghRow:SetBackdropColor(0.100, 0.100, 0.130, 1)
            local groupLabel = entry.groupTag ~= "" and entry.groupTag or L["(no group)"]
            local total25g = BRutus.RaidTracker:GetTotal25ManSessions(entry.groupTag)
            local ghText = UI:CreateText(ghRow,
                "|cff9966FF" .. groupLabel .. "|r  —  " .. total25g .. L[" 25-man raids"],
                9, C.white.r, C.white.g, C.white.b)
            ghText:SetPoint("LEFT", 6, 0)
            yOff = yOff + 18
        end

        local row = CreateFrame("Frame", nil, attContent, "BackdropTemplate")
        row:SetSize(attContent:GetWidth() - 10, 20)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local bg = (idx % 2 == 1) and C.row1 or C.row2
        row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)

        local shortName = entry.key:match("^([^-]+)") or entry.key
        local memberData = BRutus.db.members and BRutus.db.members[entry.key]
        local class = memberData and memberData.class
        local cr, cg, cb = BRutus:GetClassColor(class)
        local nameText = UI:CreateText(row, shortName, 10, cr, cg, cb)
        nameText:SetPoint("LEFT", 6, 0)

        -- Group tag column
        local gtLabel = entry.groupTag ~= "" and entry.groupTag or "-"
        UI:CreateText(row, gtLabel, 9, 0.56, 0.48, 0.82):SetPoint("LEFT", 145, 0)

        local total25g = BRutus.RaidTracker:GetTotal25ManSessions(entry.groupTag)
        local pct      = BRutus.RaidTracker:GetAttendance25ManPercent(entry.key, entry.groupTag)
        local pctClr   = pct >= 75 and C.green or (pct >= 50 and C.gold or C.red)
        local pctText  = UI:CreateText(row, pct .. "%", 10, pctClr.r, pctClr.g, pctClr.b)
        pctText:SetPoint("LEFT", 240, 0)

        local raids25  = entry.data.raids25 or 0
        local fracText = UI:CreateText(row, raids25 .. "/" .. total25g, 10, C.silver.r, C.silver.g, C.silver.b)
        fracText:SetPoint("LEFT", 295, 0)

        local avgScore = 0
        if raids25 > 0 and entry.data.totalScore25 then
            avgScore = math.floor(entry.data.totalScore25 / raids25 + 0.5)
        end
        local asr, asg, asb = C.green.r, C.green.g, C.green.b
        if avgScore < 80 then asr, asg, asb = C.gold.r, C.gold.g, C.gold.b end
        if avgScore < 60 then asr, asg, asb = C.red.r,  C.red.g,  C.red.b  end
        local avgScoreText = UI:CreateText(row, avgScore .. " pts", 9, asr, asg, asb)
        avgScoreText:SetPoint("LEFT", 355, 0)

        local lastStr = entry.data.lastRaid and entry.data.lastRaid > 0
            and date("%m/%d/%Y", entry.data.lastRaid) or "-"
        local lastText = UI:CreateText(row, lastStr, 9, C.silver.r, C.silver.g, C.silver.b)
        lastText:SetPoint("LEFT", 450, 0)

        -- Recent form: flag members who missed the latest guild raid(s).
        local missed = BRutus.RaidTracker:GetMissedStreak(entry.key, entry.groupTag, 5)
        if missed >= 2 then
            local f = UI:CreateText(row, string.format(L["missed last %d"], missed), 9, C.red.r, C.red.g, C.red.b)
            f:SetPoint("LEFT", 540, 0)
        elseif missed == 1 then
            local f = UI:CreateText(row, L["missed last raid"], 9, C.gold.r, C.gold.g, C.gold.b)
            f:SetPoint("LEFT", 540, 0)
        end

        local capturedEntry = entry
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(shortName, cr, cg, cb)
            local gLabel = capturedEntry.groupTag ~= "" and capturedEntry.groupTag or L["(no group)"]
            GameTooltip:AddLine(L["Group: "] .. gLabel, 0.56, 0.48, 0.82)
            GameTooltip:AddLine(L["25-man Attendance"], C.gold.r, C.gold.g, C.gold.b)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(L["Raids:"], raids25 .. "/" .. total25g, 1,1,1, C.silver.r,C.silver.g,C.silver.b)
            GameTooltip:AddDoubleLine(L["Attendance %:"], pct .. "%", 1,1,1, pctClr.r,pctClr.g,pctClr.b)
            if avgScore > 0 then
                GameTooltip:AddDoubleLine(L["Avg score/raid:"], avgScore .. L[" pts"], 1,1,1, asr,asg,asb)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Score starts at 100 per raid."], 0.6,0.6,0.6)
            GameTooltip:AddLine("-" .. (BRutus.RaidTracker.PENALTIES.LATE or 10) .. L[" Arrived late"], 0.7,0.5,0.5)
            GameTooltip:AddLine("-" .. (BRutus.RaidTracker.PENALTIES.LEFT_EARLY or 10) .. L[" Left early"], 0.7,0.5,0.5)
            GameTooltip:AddLine("-" .. (BRutus.RaidTracker.PENALTIES.NO_CONSUMES or 10) .. L[" No consumables"], 0.7,0.5,0.5)
            GameTooltip:Show()
            local _ = capturedEntry
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            GameTooltip:Hide()
        end)

        yOff = yOff + 22
    end

    if #attList == 0 then
        local emptyText = UI:CreateText(attContent, L["No 25-man attendance data yet."], 10, C.silver.r, C.silver.g, C.silver.b)
        emptyText:SetPoint("TOPLEFT", 6, -yOff)
        yOff = yOff + 22
    end

    attContent:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- LOOT HISTORY PANEL
----------------------------------------------------------------------
function BRutus:CreateLootPanel(parent, _mainFrame)
    local scrollParent = CreateFrame("Frame", nil, parent)
    scrollParent:SetPoint("TOPLEFT", 10, -10)
    scrollParent:SetPoint("BOTTOMRIGHT", -10, 10)

    local title = UI:CreateTitle(scrollParent, L["Loot History"], 14)
    title:SetPoint("TOPLEFT", 0, 0)

    local countText = UI:CreateText(scrollParent, "", 10, C.silver.r, C.silver.g, C.silver.b)
    countText:SetPoint("TOPRIGHT", 0, -2)

    -- View toggle: History | Equity
    local histBtn = UI:CreateButton(scrollParent, L["History"], 90, 20)
    histBtn:SetPoint("TOPLEFT", 0, -24)
    local eqBtn = UI:CreateButton(scrollParent, L["Equity"], 90, 20)
    eqBtn:SetPoint("LEFT", histBtn, "RIGHT", 6, 0)

    local exportBtn = UI:CreateButton(scrollParent, L["Export"], 90, 20)
    exportBtn:SetPoint("LEFT", eqBtn, "RIGHT", 6, 0)
    exportBtn:SetScript("OnClick", function()
        BRutus:ShowExportPopup(L["Loot Export"], BRutus:ExportLoot())
    end)

    local VIEW_TOP = 50  -- space reserved for title + toggle row

    ----------------------------------------------------------------
    -- History view
    ----------------------------------------------------------------
    local historyView = CreateFrame("Frame", nil, scrollParent)
    historyView:SetPoint("TOPLEFT", 0, -VIEW_TOP)
    historyView:SetPoint("BOTTOMRIGHT", 0, 0)

    local colHeader = CreateFrame("Frame", nil, historyView)
    colHeader:SetPoint("TOPLEFT", 0, 0)
    colHeader:SetPoint("TOPRIGHT", 0, 0)
    colHeader:SetHeight(20)

    local hItem = UI:CreateHeaderText(colHeader, L["ITEM"], 10)
    hItem:SetPoint("LEFT", 6, 0)
    local hPlayer = UI:CreateHeaderText(colHeader, L["PLAYER"], 10)
    hPlayer:SetPoint("LEFT", 300, 0)
    local hRaid = UI:CreateHeaderText(colHeader, L["RAID"], 10)
    hRaid:SetPoint("LEFT", 450, 0)
    local hDate = UI:CreateHeaderText(colHeader, L["DATE"], 10)
    hDate:SetPoint("LEFT", 600, 0)

    local sep = UI:CreateSeparator(historyView)
    sep:SetPoint("TOPLEFT", 0, -20)
    sep:SetPoint("TOPRIGHT", 0, -20)

    local lootScroll = CreateFrame("ScrollFrame", "BRutusLootScroll", historyView, "UIPanelScrollFrameTemplate")
    lootScroll:SetPoint("TOPLEFT", 0, -22)
    lootScroll:SetPoint("BOTTOMRIGHT", -10, 0)
    UI:SkinScrollBar(lootScroll, "BRutusLootScroll")

    local lootContent = CreateFrame("Frame", nil, lootScroll)
    lootContent:SetSize(800, 1)
    lootScroll:SetScrollChild(lootContent)

    ----------------------------------------------------------------
    -- Equity view
    ----------------------------------------------------------------
    local equityView = CreateFrame("Frame", nil, scrollParent)
    equityView:SetPoint("TOPLEFT", 0, -VIEW_TOP)
    equityView:SetPoint("BOTTOMRIGHT", 0, 0)
    equityView:Hide()

    local eqHeader = CreateFrame("Frame", nil, equityView)
    eqHeader:SetPoint("TOPLEFT", 0, 0)
    eqHeader:SetPoint("TOPRIGHT", 0, 0)
    eqHeader:SetHeight(20)
    local ehName = UI:CreateHeaderText(eqHeader, L["MEMBER"], 10)
    ehName:SetPoint("LEFT", 6, 0)
    local ehItems = UI:CreateHeaderText(eqHeader, L["ITEMS"], 10)
    ehItems:SetPoint("LEFT", 200, 0)
    local ehAtt = UI:CreateHeaderText(eqHeader, L["ATT%"], 10)
    ehAtt:SetPoint("LEFT", 300, 0)
    local ehRaids = UI:CreateHeaderText(eqHeader, L["RAIDS"], 10)
    ehRaids:SetPoint("LEFT", 400, 0)
    local ehPer = UI:CreateHeaderText(eqHeader, L["ITEMS/RAID"], 10)
    ehPer:SetPoint("LEFT", 500, 0)

    local eqSep = UI:CreateSeparator(equityView)
    eqSep:SetPoint("TOPLEFT", 0, -20)
    eqSep:SetPoint("TOPRIGHT", 0, -20)

    local eqScroll = CreateFrame("ScrollFrame", "BRutusLootEquityScroll", equityView, "UIPanelScrollFrameTemplate")
    eqScroll:SetPoint("TOPLEFT", 0, -22)
    eqScroll:SetPoint("BOTTOMRIGHT", -10, 0)
    UI:SkinScrollBar(eqScroll, "BRutusLootEquityScroll")

    local eqContent = CreateFrame("Frame", nil, eqScroll)
    eqContent:SetSize(800, 1)
    eqScroll:SetScrollChild(eqContent)

    ----------------------------------------------------------------
    -- Toggle logic
    ----------------------------------------------------------------
    local function showView(which)
        local hist = (which == "history")
        historyView:SetShown(hist)
        equityView:SetShown(not hist)
        title:SetText(hist and L["Loot History"] or L["Loot Equity"])
        histBtn:SetBaseColor(hist and C.accent.r * 0.32 or C.bg2.r, hist and C.accent.g * 0.32 or C.bg2.g, hist and C.accent.b * 0.32 or C.bg2.b, 0.92)
        eqBtn:SetBaseColor(not hist and C.accent.r * 0.32 or C.bg2.r, not hist and C.accent.g * 0.32 or C.bg2.g, not hist and C.accent.b * 0.32 or C.bg2.b, 0.92)
        if hist then
            BRutus:RefreshLootPanel(lootContent, countText)
        else
            BRutus:RefreshLootEquity(eqContent, countText)
        end
    end
    histBtn:SetScript("OnClick", function() showView("history") end)
    eqBtn:SetScript("OnClick", function() showView("equity") end)

    parent:SetScript("OnShow", function()
        showView("history")
    end)
end

function BRutus:RefreshLootPanel(content, countText)
    if not BRutus.LootTracker then return end

    for _, child in pairs({ content:GetChildren() }) do child:Hide() end

    local history = BRutus.LootTracker:GetHistory(100)
    countText:SetText(#BRutus.db.lootHistory .. L[" items tracked"])

    local yOff = 0
    for _, entry in ipairs(history) do
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetSize(content:GetWidth() - 10, 22)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        local altIdx = (math.floor(yOff / 22) % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)

        -- Item name with quality color (always resolve via GetItemInfo for correct locale).
        -- GetItemInfo accepts itemLink directly, so no need to parse the ID.
        local qColor = BRutus.QualityColors[entry.quality] or BRutus.QualityColors[1]
        local localItemName, _, _, _, _, _, _, _, _, _, localItemQuality = GetItemInfo(entry.itemLink or entry.itemId or 0)
        if localItemQuality then
            qColor = BRutus.QualityColors[localItemQuality] or qColor
        end
        local displayName = localItemName or entry.itemName or "?"
        local itemText = UI:CreateText(row, displayName, 10, qColor.r, qColor.g, qColor.b)
        itemText:SetPoint("LEFT", 6, 0)
        itemText:SetWidth(280)

        -- Hover tooltip for item
        if entry.itemLink then
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(entry.itemLink)
                GameTooltip:Show()
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            end)
            row:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)
            end)
        end

        -- Player
        local memberData = BRutus.db.members[entry.playerKey]
        local pClass = memberData and memberData.class
        local pr, pg, pb = 1, 1, 1
        if pClass then
            pr, pg, pb = BRutus:GetClassColor(pClass)
        end
        local playerText = UI:CreateText(row, entry.player or "?", 10, pr, pg, pb)
        playerText:SetPoint("LEFT", 300, 0)

        -- Raid
        local raidText = UI:CreateText(row, entry.raid or "", 10, C.silver.r, C.silver.g, C.silver.b)
        raidText:SetPoint("LEFT", 450, 0)

        -- Date
        local dateStr = date("%m/%d %H:%M", entry.timestamp or 0)
        local dateText = UI:CreateText(row, dateStr, 10, C.silver.r, C.silver.g, C.silver.b)
        dateText:SetPoint("LEFT", 600, 0)

        yOff = yOff + 22
    end
    content:SetHeight(math.max(1, yOff))
end

function BRutus:RefreshLootEquity(content, countText)
    if not BRutus.LootTracker then return end
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end

    local rows = BRutus.LootTracker:GetGuildLootEquity()
    countText:SetText(string.format(L["%d members with loot/raid history"], #rows))

    local yOff = 0
    for _, r in ipairs(rows) do
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetSize(content:GetWidth() - 10, 22)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local altIdx = (math.floor(yOff / 22) % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)

        local cr, cg, cb = BRutus:GetClassColor(r.class)
        local nameText = UI:CreateText(row, r.name, 10, cr, cg, cb)
        nameText:SetPoint("LEFT", 6, 0)

        local itemsText = UI:CreateText(row, tostring(r.items), 10, C.white.r, C.white.g, C.white.b)
        itemsText:SetPoint("LEFT", 200, 0)

        -- Attendance: green when high, gold mid, red low.
        local attColor = r.attendance >= 70 and C.green or (r.attendance >= 40 and C.gold or C.red)
        local attText = UI:CreateText(row, r.attendance .. "%", 10, attColor.r, attColor.g, attColor.b)
        attText:SetPoint("LEFT", 300, 0)

        local raidsText = UI:CreateText(row, tostring(r.raids), 10, C.silver.r, C.silver.g, C.silver.b)
        raidsText:SetPoint("LEFT", 400, 0)

        local perText = UI:CreateText(row, string.format("%.2f", r.perRaid), 10, C.silver.r, C.silver.g, C.silver.b)
        perText:SetPoint("LEFT", 500, 0)

        -- Flag: dry (deserves loot) vs over-fed, for quick scanning.
        if r.attendance >= 70 and r.items == 0 then
            local flag = UI:CreateText(row, L["dry"], 10, C.green.r, C.green.g, C.green.b)
            flag:SetPoint("LEFT", 600, 0)
        elseif r.raids > 0 and r.perRaid >= 1.0 then
            local flag = UI:CreateText(row, L["well-fed"], 10, C.red.r, C.red.g, C.red.b)
            flag:SetPoint("LEFT", 600, 0)
        end

        yOff = yOff + 22
    end

    if #rows == 0 then
        local empty = UI:CreateText(content, L["No loot or attendance data yet."], 11, C.silver.r, C.silver.g, C.silver.b)
        empty:SetPoint("TOPLEFT", 6, -4)
    end
    content:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- TRIAL TRACKER PANEL
----------------------------------------------------------------------
function BRutus:CreateTrialsPanel(parent, _mainFrame)
    local scrollParent = CreateFrame("Frame", nil, parent)
    scrollParent:SetPoint("TOPLEFT", 10, -10)
    scrollParent:SetPoint("BOTTOMRIGHT", -10, 10)

    local title = UI:CreateTitle(scrollParent, L["Trial Members"], 14)
    title:SetPoint("TOPLEFT", 0, 0)

    local statusText = UI:CreateText(scrollParent, "", 10, C.silver.r, C.silver.g, C.silver.b)
    statusText:SetPoint("TOPRIGHT", 0, -2)

    -- Column headers
    local colHeader = CreateFrame("Frame", nil, scrollParent)
    colHeader:SetPoint("TOPLEFT", 0, -28)
    colHeader:SetPoint("TOPRIGHT", 0, -28)
    colHeader:SetHeight(20)

    local hName = UI:CreateHeaderText(colHeader, L["MEMBER"], 10)
    hName:SetPoint("LEFT", 6, 0)
    local hIlvl = UI:CreateHeaderText(colHeader, L["iLVL"], 10)
    hIlvl:SetPoint("LEFT", 140, 0)
    local hAtt = UI:CreateHeaderText(colHeader, L["ATTUNE"], 10)
    hAtt:SetPoint("LEFT", 210, 0)
    local hSponsor = UI:CreateHeaderText(colHeader, L["SPONSOR"], 10)
    hSponsor:SetPoint("LEFT", 290, 0)
    local hDays = UI:CreateHeaderText(colHeader, L["REMAINING"], 10)
    hDays:SetPoint("LEFT", 400, 0)
    local hStatus = UI:CreateHeaderText(colHeader, L["STATUS"], 10)
    hStatus:SetPoint("LEFT", 500, 0)

    local sep = UI:CreateSeparator(scrollParent)
    sep:SetPoint("TOPLEFT", 0, -50)
    sep:SetPoint("TOPRIGHT", 0, -50)

    local trialScroll = CreateFrame("ScrollFrame", "BRutusTrialScroll", scrollParent, "UIPanelScrollFrameTemplate")
    trialScroll:SetPoint("TOPLEFT", 0, -52)
    trialScroll:SetPoint("BOTTOMRIGHT", -10, 0)
    UI:SkinScrollBar(trialScroll, "BRutusTrialScroll")

    local trialContent = CreateFrame("Frame", nil, trialScroll)
    trialContent:SetSize(800, 1)
    trialScroll:SetScrollChild(trialContent)

    parent.trialContent = trialContent
    parent.statusText = statusText
    parent.expandedTrials = {}

    parent:SetScript("OnShow", function()
        BRutus:RefreshTrialsPanel(parent)
    end)
end

function BRutus:RefreshTrialsPanel(parent)
    local content = parent.trialContent
    local statusText = parent.statusText
    if not content or not BRutus.TrialTracker then return end

    for _, child in pairs({ content:GetChildren() }) do child:Hide() end

    local trials = BRutus.TrialTracker:GetAllTrials()
    local activeCount = 0
    for _, t in ipairs(trials) do
        if t.data.status == BRutus.TrialTracker.STATUS.TRIAL then
            activeCount = activeCount + 1
        end
    end
    statusText:SetText(activeCount .. L[" active trials"])

    local expanded = parent.expandedTrials or {}
    local yOff = 0

    for _, trial in ipairs(trials) do
        local data = trial.data
        local isExpanded = expanded[trial.key]
        local memberData = BRutus.db.members[trial.key]
        local progress = BRutus.TrialTracker:GetProgress(trial.key)

        -- Main row
        local row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetSize(content:GetWidth() - 10, 26)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        local rowIdx = math.floor(yOff / 26) % 2
        local altIdx = (rowIdx == 0) and C.row1 or C.row2
        row:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)

        -- Expand arrow
        local arrow = UI:CreateText(row, isExpanded and "v" or ">", 10, C.accent.r, C.accent.g, C.accent.b)
        arrow:SetPoint("LEFT", 2, 0)

        -- Name with class color
        local shortName = trial.key:match("^([^-]+)") or trial.key
        local pClass = memberData and memberData.class
        local pr, pg, pb = 1, 1, 1
        if pClass then pr, pg, pb = BRutus:GetClassColor(pClass) end

        local nameText = UI:CreateText(row, shortName, 10, pr, pg, pb)
        nameText:SetPoint("LEFT", 14, 0)

        -- iLvl with delta
        if progress then
            local ilvlSign = progress.ilvlDelta > 0 and "+" or ""
            local ilvlColor = progress.ilvlDelta > 0 and C.green or (progress.ilvlDelta < 0 and C.red or C.silver)
            local ilvlStr = format("%d (%s%d)", progress.currentIlvl, ilvlSign, progress.ilvlDelta)
            local ilvlText = UI:CreateText(row, ilvlStr, 9, ilvlColor.r, ilvlColor.g, ilvlColor.b)
            ilvlText:SetPoint("LEFT", 140, 0)

            -- Attunement progress
            local attColor = progress.attDelta > 0 and C.green or C.silver
            local attStr = format("%d/%d (+%d)", progress.currentAttDone, progress.attTotal, progress.attDelta)
            local attText = UI:CreateText(row, attStr, 9, attColor.r, attColor.g, attColor.b)
            attText:SetPoint("LEFT", 210, 0)
        else
            local ilvlVal = memberData and memberData.avgIlvl or 0
            if ilvlVal > 0 then
                local ilvlText = UI:CreateText(row, tostring(ilvlVal), 9, C.silver.r, C.silver.g, C.silver.b)
                ilvlText:SetPoint("LEFT", 140, 0)
            end
            local noProgText = UI:CreateText(row, "-", 9, C.silver.r, C.silver.g, C.silver.b)
            noProgText:SetPoint("LEFT", 210, 0)
        end

        local sponsorText = UI:CreateText(row, data.sponsor or "?", 10, C.silver.r, C.silver.g, C.silver.b)
        sponsorText:SetPoint("LEFT", 290, 0)

        local daysRem = BRutus.TrialTracker:GetDaysRemaining(trial.key)
        local daysStr = daysRem and (daysRem .. "d") or "-"
        local daysColor = C.white
        if daysRem then
            daysColor = daysRem > 14 and C.green or (daysRem > 7 and C.gold or C.red)
        end
        local daysText = UI:CreateText(row, daysStr, 10, daysColor.r, daysColor.g, daysColor.b)
        daysText:SetPoint("LEFT", 400, 0)

        -- Status badge
        local statusColor = C.silver
        local statusStr = data.status or "?"
        if data.status == "trial" then
            statusColor = C.gold; statusStr = L["TRIAL"]
        elseif data.status == "approved" then
            statusColor = C.green; statusStr = L["APPROVED"]
        elseif data.status == "denied" then
            statusColor = C.red; statusStr = L["DENIED"]
        elseif data.status == "expired" then
            statusColor = C.red; statusStr = L["EXPIRED"]
        end
        local sText = UI:CreateText(row, statusStr, 10, statusColor.r, statusColor.g, statusColor.b)
        sText:SetPoint("LEFT", 500, 0)

        -- Action buttons for active trials
        if data.status == "trial" then
            local approveBtn = UI:CreateButton(row, L["OK"], 30, 18)
            approveBtn:SetPoint("LEFT", 580, 0)
            approveBtn:SetScript("OnClick", function()
                BRutus.TrialTracker:UpdateStatus(trial.key, BRutus.TrialTracker.STATUS.APPROVED)
                BRutus:RefreshTrialsPanel(parent)
            end)

            local denyBtn = UI:CreateButton(row, L["X"], 24, 18)
            denyBtn:SetPoint("LEFT", approveBtn, "RIGHT", 4, 0)
            denyBtn:SetScript("OnClick", function()
                BRutus.TrialTracker:UpdateStatus(trial.key, BRutus.TrialTracker.STATUS.DENIED)
                BRutus:RefreshTrialsPanel(parent)
            end)
        end

        -- Click to expand/collapse
        row:SetScript("OnClick", function()
            expanded[trial.key] = not expanded[trial.key]
            parent.expandedTrials = expanded
            BRutus:RefreshTrialsPanel(parent)
        end)

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)
        end)

        yOff = yOff + 28

        -- Expanded detail section
        if isExpanded then
            local detailFrame = CreateFrame("Frame", nil, content, "BackdropTemplate")
            detailFrame:SetPoint("TOPLEFT", 10, -yOff)
            detailFrame:SetPoint("TOPRIGHT", -10, -yOff)
            detailFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            detailFrame:SetBackdropColor(0.066, 0.066, 0.084, 0.8)

            local dY = -6

            -- Start date
            local startStr = date("%m/%d/%y", data.startDate or 0)
            local daysSince = BRutus.TrialTracker:GetDaysSinceStart(trial.key)
            local infoFS = detailFrame:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            infoFS:SetPoint("TOPLEFT", 10, dY)
            infoFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            infoFS:SetText(format(L["Started: %s  |  Day %d  |  Sponsor: %s"], startStr, daysSince or 0, data.sponsor or "?"))
            infoFS:Show()
            dY = dY - 16

            -- Officer comments
            if data.notes and #data.notes > 0 then
                local notesLabel = detailFrame:CreateFontString(nil, "OVERLAY")
                notesLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                notesLabel:SetPoint("TOPLEFT", 10, dY)
                notesLabel:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                notesLabel:SetText(L["Comments:"])
                notesLabel:Show()
                dY = dY - 14

                for _, note in ipairs(data.notes) do
                    local noteFS = detailFrame:CreateFontString(nil, "OVERLAY")
                    noteFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
                    noteFS:SetPoint("TOPLEFT", 14, dY)
                    noteFS:SetWidth(content:GetWidth() - 60)
                    noteFS:SetJustifyH("LEFT")
                    noteFS:SetWordWrap(true)
                    local dateStr = note.timestamp and date("%m/%d %H:%M", note.timestamp) or ""
                    noteFS:SetText(format("|cffAAAAAA[%s %s]|r %s", note.author or "?", dateStr, note.text or ""))
                    noteFS:Show()
                    dY = dY - (noteFS:GetStringHeight() + 3)
                end
            end

            -- Inline add note
            local addBox = CreateFrame("EditBox", nil, detailFrame, "BackdropTemplate")
            addBox:SetSize(content:GetWidth() - 120, 20)
            addBox:SetPoint("TOPLEFT", 10, dY - 4)
            addBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            addBox:SetBackdropColor(0.038, 0.038, 0.052, 1)
            addBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)
            addBox:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            addBox:SetTextColor(C.white.r, C.white.g, C.white.b)
            addBox:SetTextInsets(4, 4, 2, 2)
            addBox:SetAutoFocus(false)
            addBox:SetMaxLetters(200)
            addBox:Show()

            local ph = addBox:CreateFontString(nil, "OVERLAY")
            ph:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            ph:SetPoint("LEFT", 4, 0)
            ph:SetTextColor(0.3, 0.3, 0.3)
            ph:SetText(L["Add comment..."])
            addBox:SetScript("OnTextChanged", function(self)
                if self:GetText() ~= "" then ph:Hide() else ph:Show() end
            end)
            addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            local addBtn = UI:CreateButton(detailFrame, L["Add"], 50, 20)
            addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
            addBtn:SetScript("OnClick", function()
                local text = addBox:GetText()
                if text and strtrim(text) ~= "" then
                    BRutus.TrialTracker:AddTrialNote(trial.key, strtrim(text))
                    addBox:SetText("")
                    addBox:ClearFocus()
                    BRutus:RefreshTrialsPanel(parent)
                end
            end)
            addBox:SetScript("OnEnterPressed", function(self)
                local text = self:GetText()
                if text and strtrim(text) ~= "" then
                    BRutus.TrialTracker:AddTrialNote(trial.key, strtrim(text))
                    self:SetText("")
                    self:ClearFocus()
                    BRutus:RefreshTrialsPanel(parent)
                end
            end)

            dY = dY - 30
            detailFrame:SetHeight(math.abs(dY) + 6)
            yOff = yOff + math.abs(dY) + 8
        end
    end

    if #trials == 0 then
        local emptyText = UI:CreateText(content, L["No trial members tracked."], 11, C.silver.r, C.silver.g, C.silver.b)
        emptyText:SetPoint("TOPLEFT", 0, 0)
        yOff = 30
    end

    content:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- EXPORT CHOOSER — pick a dataset and format from the UI (not just chat)
----------------------------------------------------------------------
function BRutus:ShowExportChooser()
    if self.exportChooser then self.exportChooser:Show(); return end

    local f = CreateFrame("Frame", "GuildOSExportChooser", UIParent, "BackdropTemplate")
    f:SetSize(390, 300)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
    f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing() end)
    self.exportChooser = f

    local title = UI:CreateTitle(f, L["Export Data"], 16)
    title:SetPoint("TOP", 0, -12)
    local hint = UI:CreateText(f, L["Pick a dataset and format. CSV = spreadsheets, Discord = pastebox."], 9, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local datasets = {
        { key = "roster",     label = L["Roster"] },
        { key = "attendance", label = L["Attendance"] },
        { key = "loot",       label = L["Loot History"] },
        { key = "readiness",  label = L["Readiness"] },
        { key = "equity",     label = L["Loot Equity"] },
        { key = "standings",  label = L["DKP Standings"] },
    }
    local y = -56
    for _, d in ipairs(datasets) do
        local lbl = UI:CreateText(f, d.label, 11, C.text.r, C.text.g, C.text.b)
        lbl:SetPoint("TOPLEFT", 16, y)
        local fx = 150
        for _, fmt in ipairs({ "csv", "tsv", "discord" }) do
            local b = UI:CreateButton(f, fmt:upper(), 66, 20)
            b:SetPoint("TOPLEFT", fx, y + 3)
            b:SetScript("OnClick", function()
                if not BRutus.Exporter then return end
                local text, t = BRutus.Exporter:Build(d.key, fmt)
                if text then BRutus:ShowExportPopup(string.format("%s (%s)", t or d.label, fmt), text) end
            end)
            fx = fx + 70
        end
        y = y - 32
    end
end

----------------------------------------------------------------------
-- EXPORT POPUP (copyable text box)
----------------------------------------------------------------------
function BRutus:ShowExportPopup(titleStr, text)
    if self.exportPopup then self.exportPopup:Hide() end

    local f = CreateFrame("Frame", "BRutusExportPopup", UIParent, "BackdropTemplate")
    f:SetSize(500, 350)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    titleText:SetPoint("TOP", 0, -10)
    titleText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleText:SetText(titleStr or L["Export"])

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    hint:SetPoint("TOP", 0, -28)
    hint:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    hint:SetText(L["Press Ctrl+A to select all, then Ctrl+C to copy"])

    -- Scroll frame for the edit box
    local scrollFrame = CreateFrame("ScrollFrame", "BRutusExportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -48)
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 40)
    UI:SkinScrollBar(scrollFrame, "BRutusExportScroll")

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    editBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(true)
    editBox:SetText(text or "")
    editBox:HighlightText()
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local closeTextBtn = UI:CreateButton(f, L["Close"], 80, 24)
    closeTextBtn:SetPoint("BOTTOM", 0, 10)
    closeTextBtn:SetScript("OnClick", function() f:Hide() end)

    f:Show()
    self.exportPopup = f
end

----------------------------------------------------------------------
-- SETTINGS PANEL
----------------------------------------------------------------------
function BRutus:CreateSettingsPanel(parent, _mainFrame)
    local scrollFrame, content = UI:CreateScrollFrame(parent, "BRutusSettingsScroll")
    scrollFrame:SetPoint("TOPLEFT", 12, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 10)
    content:SetWidth(scrollFrame:GetWidth() - 20)

    parent:SetScript("OnShow", function()
        BRutus:RefreshSettingsPanel(content)
    end)
end

function BRutus:RefreshSettingsPanel(content)
    -- Clear existing
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end

    local yOff = 0

    -- Title
    local title = UI:CreateTitle(content, L["Settings"], 16)
    title:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 28

    local subtitle = UI:CreateText(content, L["Enable or disable modules and adjust settings. Changes take effect immediately."], 10, C.silver.r, C.silver.g, C.silver.b)
    subtitle:SetPoint("TOPLEFT", 0, -yOff)
    subtitle:SetWidth(content:GetWidth() - 20)
    yOff = yOff + 24

    -- Separator
    local sep1 = UI:CreateSeparator(content)
    sep1:SetPoint("TOPLEFT", 0, -yOff)
    sep1:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    --------------------------------------------------------------------
    -- MODULE TOGGLES
    --------------------------------------------------------------------
    local sectionTitle = UI:CreateHeaderText(content, L["MODULES"], 12)
    sectionTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    -- Ensure modules table exists
    if not BRutus.db.settings.modules then
        BRutus.db.settings.modules = {
            raidTracker = true, lootTracker = true, lootMaster = true,
            consumableChecker = true, recruitment = true, trialTracker = true,
            officerNotes = true, commSystem = true,
            raidHUD = true,
        }
    end
    local mods = BRutus.db.settings.modules
    local isOfficer = BRutus:IsOfficer()

    local modules = {
        { key = "raidTracker",       label = L["Raid Tracker"],         desc = L["Track raid attendance, penalties, and sessions"], officerOnly = true },
        { key = "lootTracker",       label = L["Loot Tracker"],         desc = L["Record loot drops from boss kills"] },
        { key = "lootMaster",        label = L["Loot Master"],          desc = L["Master Loot with wishlist auto-council"] },
        { key = "consumableChecker", label = L["Consumable Checker"],   desc = L["Scan raid for missing flasks/food/elixirs"] },
        { key = "raidHUD",           label = L["Raid CD Tracker"],      desc = L["Floating tracker for raid cooldowns and consumable check"] },

        { key = "trialTracker",      label = L["Trial Tracker"],        desc = L["Track trial member progress (officer)"], officerOnly = true },
        { key = "officerNotes",      label = L["Officer Notes"],        desc = L["Private notes on guild members (officer)"], officerOnly = true },
        { key = "recruitment",       label = L["Recruitment"],          desc = L["Auto-post recruitment messages (officer)"], officerOnly = true },
        { key = "commSystem",        label = L["Comm System"],          desc = L["Sync member data between addon users"] },
    }

    for _, mod in ipairs(modules) do
        if not mod.officerOnly or isOfficer then
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetSize(content:GetWidth() - 10, 36)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0.082, 0.082, 0.105, 0.5)

        local cb = UI:CreateCheckbox(row, mod.label, 18)
        cb:SetPoint("LEFT", 8, 0)
        cb.checkbox:SetChecked(mods[mod.key] ~= false)
        cb.checkbox.onChanged = function(_, checked)
            -- GetChecked() returns true or nil (never false) in WoW TBC.
            -- Explicitly store false so modEnabled() sees ~= false correctly.
            mods[mod.key] = checked and true or false
            if checked then
                BRutus:Print(mod.label .. L[" |cff00ff00enabled|r. Reload UI to apply."])
            else
                BRutus:Print(mod.label .. L[" |cffFF4444disabled|r. Reload UI to apply."])
            end
        end

        local desc = UI:CreateText(row, mod.desc, 9, C.silver.r, C.silver.g, C.silver.b)
        desc:SetPoint("LEFT", 240, 0)
        desc:SetWidth(400)

        yOff = yOff + 38
        end
    end

    yOff = yOff + 8

    -- Separator
    local sep2 = UI:CreateSeparator(content)
    sep2:SetPoint("TOPLEFT", 0, -yOff)
    sep2:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    --------------------------------------------------------------------
    -- QUICK ACCESS — open feature windows from the UI (not just chat)
    --------------------------------------------------------------------
    local qaTitle = UI:CreateHeaderText(content, L["QUICK ACCESS"], 12)
    qaTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    local quickButtons = {
        { label = L["Loot & DKP"],  fn = function() BRutus:ShowPointsFrame() end },
        { label = L["My Wishlist"], fn = function() BRutus:ShowWishlistFrame() end },
        { label = L["Loot Equity"], fn = function()
            local txt = BRutus.Exporter and BRutus.Exporter:Build("equity", "tsv") or ""
            BRutus:ShowExportPopup(L["Loot Equity"], txt)
        end },
        { label = L["Export Data"], fn = function()
            if BRutus.ShowExportChooser then BRutus:ShowExportChooser() end
        end },
    }
    local qx = 0
    for _, qb in ipairs(quickButtons) do
        local b = UI:CreateButton(content, qb.label, 130, 24)
        b:SetPoint("TOPLEFT", qx, -yOff)
        b:SetScript("OnClick", qb.fn)
        qx = qx + 136
    end
    yOff = yOff + 34

    local sepQA = UI:CreateSeparator(content)
    sepQA:SetPoint("TOPLEFT", 0, -yOff)
    sepQA:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    if isOfficer then
    --------------------------------------------------------------------
    -- LOOT SYSTEM (officer) — how the guild distributes loot
    --------------------------------------------------------------------
    local lsTitle = UI:CreateHeaderText(content, L["LOOT SYSTEM"], 12)
    lsTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 20

    local lsDesc = UI:CreateText(content, L["Choose how your guild distributes loot. Sets the default Loot Master flow."], 9, C.silver.r, C.silver.g, C.silver.b)
    lsDesc:SetPoint("TOPLEFT", 8, -yOff)
    lsDesc:SetWidth(content:GetWidth() - 20)
    yOff = yOff + 18

    local curSys = BRutus:GetLootSystem()
    local lx = 8
    for _, sys in ipairs(BRutus.LOOT_SYSTEMS) do
        local b = UI:CreateButton(content, sys.label, 130, 24)
        b:SetPoint("TOPLEFT", lx, -yOff)
        if sys.key == curSys then
            b:SetBaseColor(C.accent.r * 0.34, C.accent.g * 0.34, C.accent.b * 0.34, 0.95)
            b.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        end
        b:SetScript("OnClick", function()
            BRutus:SetLootSystem(sys.key)
            BRutus:Print(string.format(L["Loot system set to %s."], sys.label))
            BRutus:RefreshSettingsPanel(content)
        end)
        lx = lx + 136
    end
    yOff = yOff + 34

    -- DKP/Points configuration appears when the DKP system is selected
    if curSys == "dkp" and BRutus.Points and BRutus.db.points then
        local pcfg = BRutus.db.points.config
        local function numRow(labelText, key, hint)
            local lbl = UI:CreateText(content, labelText, 11, C.white.r, C.white.g, C.white.b)
            lbl:SetPoint("TOPLEFT", 16, -yOff)
            local box = CreateFrame("EditBox", nil, content, "BackdropTemplate")
            box:SetSize(60, 22)
            box:SetPoint("TOPLEFT", 220, -yOff + 2)
            box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            box:SetBackdropColor(0.05, 0.05, 0.066, 1)
            box:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
            box:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            box:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            box:SetAutoFocus(false)
            box:SetNumeric(true)
            box:SetMaxLetters(6)
            box:SetText(tostring(pcfg[key] or 0))
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            UI:AttachSaveButton(box, function(b2)
                pcfg[key] = tonumber(b2:GetText()) or pcfg[key] or 0
                BRutus.Points:BroadcastSnapshot()
            end)
            if hint then
                local h = UI:CreateText(content, hint, 9, C.silver.r, C.silver.g, C.silver.b)
                h:SetPoint("TOPLEFT", 360, -yOff)
                h:SetWidth(280)
            end
            yOff = yOff + 28
        end
        numRow(L["Points per boss:"], "bossAward", L["Awarded to raiders on each boss kill"])
        numRow(L["Weekly decay (%):"], "decayPct", L["Use the DKP window's Decay button to apply"])
        numRow(L["Starting points:"], "startingPoints", L["Default for a player's first entry"])

        local autoCb = UI:CreateCheckbox(content, L["Auto-award on boss kill (raid leader only)"], 18)
        autoCb:SetPoint("TOPLEFT", 12, -yOff)
        autoCb.checkbox:SetChecked(pcfg.autoAward and true or false)
        autoCb.checkbox.onChanged = function(_, checked)
            pcfg.autoAward = checked and true or false
            BRutus.Points:BroadcastSnapshot()
        end
        yOff = yOff + 28

        local openDkp = UI:CreateButton(content, L["Open DKP Window"], 150, 22)
        openDkp:SetPoint("TOPLEFT", 12, -yOff)
        openDkp:SetScript("OnClick", function() BRutus:ShowPointsFrame() end)
        yOff = yOff + 30
    end

    local sepLS = UI:CreateSeparator(content)
    sepLS:SetPoint("TOPLEFT", 0, -yOff)
    sepLS:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    --------------------------------------------------------------------
    -- LOOT MASTER SETTINGS (officer only)
    --------------------------------------------------------------------
    local lmTitle = UI:CreateHeaderText(content, L["LOOT MASTER"], 12)
    lmTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    -- Roll duration
    local durLabel = UI:CreateText(content, L["Roll Duration (seconds):"], 11, C.white.r, C.white.g, C.white.b)
    durLabel:SetPoint("TOPLEFT", 8, -yOff)

    local durBox = CreateFrame("EditBox", nil, content, "BackdropTemplate")
    durBox:SetSize(60, 22)
    durBox:SetPoint("LEFT", durLabel, "RIGHT", 10, 0)
    durBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    durBox:SetBackdropColor(0.058, 0.058, 0.075, 0.9)
    durBox:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
    durBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    durBox:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    durBox:SetNumeric(true)
    durBox:SetMaxLetters(3)
    durBox:SetAutoFocus(false)
    durBox:SetText(tostring(BRutus.db.lootMaster.rollDuration or 30))
    local function commitDur(box)
        local val = tonumber(box:GetText())
        if val and val >= 5 and val <= 120 then
            BRutus.db.lootMaster.rollDuration = val
            if BRutus.LootMaster then BRutus.LootMaster.ROLL_DURATION = val end
            BRutus:Print(L["Roll duration set to "] .. val .. "s")
        else
            BRutus:Print(L["Duration must be between 5 and 120 seconds."])
            box:SetText(tostring(BRutus.db.lootMaster.rollDuration or 30))
        end
    end
    durBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI:AttachSaveButton(durBox, commitDur)
    yOff = yOff + 30

    -- Auto announce
    local autoAnn = UI:CreateCheckbox(content, L["Auto-announce loot when ML opens loot window"], 18)
    autoAnn:SetPoint("TOPLEFT", 8, -yOff)
    autoAnn.checkbox:SetChecked(BRutus.db.lootMaster.autoAnnounce ~= false)
    autoAnn.checkbox.onChanged = function(_, checked)
        BRutus.db.lootMaster.autoAnnounce = checked
        if BRutus.LootMaster then BRutus.LootMaster.AUTO_ANNOUNCE = checked end
    end
    yOff = yOff + 28

    -- Wishlist auto-council
    local tmbCouncil = UI:CreateCheckbox(content, L["Wishlist Auto-Council (check wishlist before rolling)"], 18)
    tmbCouncil:SetPoint("TOPLEFT", 8, -yOff)
    tmbCouncil.checkbox:SetChecked(BRutus.db.lootMaster.wishlistOnlyMode or false)
    tmbCouncil.checkbox.onChanged = function(_, checked)
        BRutus.db.lootMaster.wishlistOnlyMode = checked
        if BRutus.LootMaster then BRutus.LootMaster.WISHLIST_ONLY_MODE = checked end
    end
    yOff = yOff + 28

    --------------------------------------------------------------------
    -- LOOT DISTRIBUTION SETTINGS (officer only)
    --------------------------------------------------------------------
    local ldSep = UI:CreateSeparator(content)
    ldSep:SetPoint("TOPLEFT", 0, -yOff)
    ldSep:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    local ldTitle = UI:CreateHeaderText(content, L["LOOT DISTRIBUTION"], 12)
    ldTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    -- Min attendance for MS roll
    local minAttLabel = UI:CreateText(content, L["Min. Attendance for MS Roll (%):"], 11, C.white.r, C.white.g, C.white.b)
    minAttLabel:SetPoint("TOPLEFT", 8, -yOff)

    local minAttBox = CreateFrame("EditBox", nil, content, "BackdropTemplate")
    minAttBox:SetSize(50, 22)
    minAttBox:SetPoint("LEFT", minAttLabel, "RIGHT", 10, 0)
    minAttBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    minAttBox:SetBackdropColor(0.058, 0.058, 0.075, 0.9)
    minAttBox:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
    minAttBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    minAttBox:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    minAttBox:SetNumeric(true)
    minAttBox:SetMaxLetters(3)
    minAttBox:SetAutoFocus(false)
    minAttBox:SetText(tostring(BRutus.db.lootMaster.minAttendancePct or 0))
    local function commitMinAtt(box)
        local val = math.max(0, math.min(100, tonumber(box:GetText()) or 0))
        BRutus.db.lootMaster.minAttendancePct = val
        BRutus:Print(L["Min. MS attendance set to "] .. val .. "%" .. (val == 0 and L[" (disabled)"] or ""))
    end
    minAttBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI:AttachSaveButton(minAttBox, commitMinAtt)

    local minAttHint = UI:CreateText(content, L["0 = disabled. Below this % MS is auto-downgraded to OS."], 9, C.silver.r, C.silver.g, C.silver.b)
    minAttHint:SetPoint("LEFT", minAttBox.saveButton, "RIGHT", 8, 0)
    minAttHint:SetWidth(280)
    yOff = yOff + 30

    -- Attendance as roll tiebreaker
    local attTie = UI:CreateCheckbox(content, L["Use 25-man Attendance as Roll Tiebreaker"], 18)
    attTie:SetPoint("TOPLEFT", 8, -yOff)
    attTie.checkbox:SetChecked(BRutus.db.lootMaster.attTiebreaker ~= false)
    attTie.checkbox.onChanged = function(_, checked)
        BRutus.db.lootMaster.attTiebreaker = checked
        if BRutus.LootMaster then BRutus.LootMaster.ATT_TIEBREAKER = checked end
    end
    yOff = yOff + 28

    -- Penalize recent receivers
    local recvPen = UI:CreateCheckbox(content, L["Penalize Players Who Received Items This Lockout"], 18)
    recvPen:SetPoint("TOPLEFT", 8, -yOff)
    recvPen.checkbox:SetChecked(BRutus.db.lootMaster.recvPenalty ~= false)
    recvPen.checkbox.onChanged = function(_, checked)
        BRutus.db.lootMaster.recvPenalty = checked
        if BRutus.LootMaster then BRutus.LootMaster.RECV_PENALTY = checked end
    end
    yOff = yOff + 28

    -- Disenchanter name
    local deLabel = UI:CreateText(content, L["Disenchanter:"], 11, C.white.r, C.white.g, C.white.b)
    deLabel:SetPoint("TOPLEFT", 8, -yOff)

    local deBox = CreateFrame("EditBox", nil, content, "BackdropTemplate")
    deBox:SetSize(160, 22)
    deBox:SetPoint("LEFT", deLabel, "RIGHT", 10, 0)
    deBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deBox:SetBackdropColor(0.058, 0.058, 0.075, 0.9)
    deBox:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
    deBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    deBox:SetTextColor(0.56, 0.48, 0.82)
    deBox:SetMaxLetters(64)
    deBox:SetAutoFocus(false)
    deBox:SetText((BRutus.LootMaster and BRutus.LootMaster:GetDisenchanter()) or "")
    local function commitDE(box)
        local name = strtrim(box:GetText())
        if BRutus.LootMaster then BRutus.LootMaster:SetDisenchanter(name) end
        if name ~= "" then
            BRutus:Print(L["Disenchanter set: "] .. "|cff00ff00" .. name .. "|r")
        else
            BRutus:Print(L["Disenchanter removed."])
        end
    end
    deBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI:AttachSaveButton(deBox, commitDE)

    local deHint = UI:CreateText(content, L["Name of the player who receives items for DE"], 9, C.silver.r, C.silver.g, C.silver.b)
    deHint:SetPoint("LEFT", deBox.saveButton, "RIGHT", 8, 0)
    deHint:SetWidth(180)
    yOff = yOff + 30

    -- Rarity threshold: which item quality opens the ML loot window.
    -- Click to cycle Uncommon -> Rare -> Epic -> Legendary.
    local thrLabel = UI:CreateText(content, L["Rarity threshold:"], 11, C.white.r, C.white.g, C.white.b)
    thrLabel:SetPoint("TOPLEFT", 8, -yOff)

    local thrBtn = UI:CreateButton(content, "", 150, 22)
    thrBtn:SetPoint("LEFT", thrLabel, "RIGHT", 10, 0)
    local function thrName(q)
        return (BRutus.LootMaster and BRutus.LootMaster.THRESHOLD_NAMES and BRutus.LootMaster.THRESHOLD_NAMES[q])
            or tostring(q)
    end
    local function refreshThr()
        local q = (BRutus.LootMaster and BRutus.LootMaster:GetLootThreshold()) or 3
        local qc = BRutus.QualityColors[q] or C.gold
        thrBtn.label:SetText(thrName(q))
        thrBtn.baseLabelColor = { qc.r, qc.g, qc.b }
        thrBtn.label:SetTextColor(qc.r, qc.g, qc.b)
    end
    thrBtn:SetScript("OnClick", function()
        if not BRutus.LootMaster then return end
        local q = BRutus.LootMaster:GetLootThreshold() + 1
        if q > 5 then q = 2 end
        BRutus.LootMaster:SetLootThreshold(q)
        refreshThr()
        BRutus:Print(L["Loot threshold: "] .. "|cffffd700" .. thrName(q) .. "|r")
    end)
    refreshThr()

    local thrHint = UI:CreateText(content, L["Items of this rarity (or higher) open the ML panel"], 9, C.silver.r, C.silver.g, C.silver.b)
    thrHint:SetPoint("LEFT", thrBtn, "RIGHT", 8, 0)
    thrHint:SetWidth(200)
    yOff = yOff + 30

    yOff = yOff + 8
    local sep3 = UI:CreateSeparator(content)
    sep3:SetPoint("TOPLEFT", 0, -yOff)
    sep3:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    end -- isOfficer (Loot Master settings)

    --------------------------------------------------------------------
    -- RAID TRACKER SETTINGS
    --------------------------------------------------------------------
    local rtTitle = UI:CreateHeaderText(content, L["RAID TRACKER"], 12)
    rtTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    -- Officer-only: Raid Group Tag
    if isOfficer then
        local groupLabel = UI:CreateText(content, L["Raid Group:"], 11, C.white.r, C.white.g, C.white.b)
        groupLabel:SetPoint("TOPLEFT", 8, -yOff)

        local groupBox = CreateFrame("EditBox", nil, content, "BackdropTemplate")
        groupBox:SetSize(160, 22)
        groupBox:SetPoint("LEFT", groupLabel, "RIGHT", 10, 0)
        groupBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        groupBox:SetBackdropColor(0.058, 0.058, 0.075, 0.9)
        groupBox:SetBackdropBorderColor(0.56, 0.48, 0.82, 0.5)
        groupBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        groupBox:SetTextColor(0.56, 0.48, 0.82)
        groupBox:SetMaxLetters(64)
        groupBox:SetAutoFocus(false)
        groupBox:SetText(BRutus.db.raidTracker and BRutus.db.raidTracker.currentGroupTag or "")
        local function commitGroup(box)
            local name = strtrim(box:GetText())
            if BRutus.RaidTracker then BRutus.RaidTracker:SetGroupTag(name) end
            if name ~= "" then
                BRutus:Print(L["Raid group set: "] .. "|cff9966FF" .. name .. "|r")
            else
                BRutus:Print(L["Raid group removed."])
            end
        end
        groupBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        UI:AttachSaveButton(groupBox, commitGroup)

        local groupHint = UI:CreateText(content, L["Ex: Core 1, Core 2"], 9, C.silver.r, C.silver.g, C.silver.b)
        groupHint:SetPoint("LEFT", groupBox.saveButton, "RIGHT", 8, 0)
        groupHint:SetWidth(180)
        yOff = yOff + 30
    end -- isOfficer (Raid group tag)

    local penaltyInfo = UI:CreateText(content, L["Penalties per session (base score = 100):"], 11, C.white.r, C.white.g, C.white.b)
    penaltyInfo:SetPoint("TOPLEFT", 8, -yOff)
    yOff = yOff + 20

    local penalties = {
        { label = L["Late (missed first snapshot)"], val = BRutus.RaidTracker and BRutus.RaidTracker.PENALTIES.LATE or 10 },
        { label = L["Left Early (missed last snapshot)"], val = BRutus.RaidTracker and BRutus.RaidTracker.PENALTIES.LEFT_EARLY or 10 },
        { label = L["No Consumables (<50% snapshots)"], val = BRutus.RaidTracker and BRutus.RaidTracker.PENALTIES.NO_CONSUMES or 10 },
    }
    for _, p in ipairs(penalties) do
        local pt = UI:CreateText(content, "  -" .. p.val .. "  " .. p.label, 10, C.silver.r, C.silver.g, C.silver.b)
        pt:SetPoint("TOPLEFT", 16, -yOff)
        yOff = yOff + 16
    end

    yOff = yOff + 8
    local sep4 = UI:CreateSeparator(content)
    sep4:SetPoint("TOPLEFT", 0, -yOff)
    sep4:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    if isOfficer then
    --------------------------------------------------------------------
    -- TEST FUNCTIONS (officer only)
    --------------------------------------------------------------------
    local testTitle = UI:CreateHeaderText(content, L["TEST FUNCTIONS"], 12)
    testTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 6

    local testNote = UI:CreateText(content, L["Simulate features to preview how they work. No data is sent to raid or guild chat."], 10, C.silver.r, C.silver.g, C.silver.b)
    testNote:SetPoint("TOPLEFT", 0, -yOff)
    testNote:SetWidth(content:GetWidth() - 20)
    yOff = yOff + 22

    -- Test: Consumable Check
    local testCons = UI:CreateButton(content, L["Test Consumable Check"], 200, 26)
    testCons:SetPoint("TOPLEFT", 8, -yOff)
    testCons:SetScript("OnClick", function()
        if BRutus.ConsumableChecker then
            local results = BRutus.ConsumableChecker:CheckRaid()
            if results then
                local missing = BRutus.ConsumableChecker:GetMissingCount(results)
                BRutus:Print(L["Consumable Check Test: "] .. missing .. L[" players missing buffs."])
                BRutus:Print(L["Use |cffFFD700/guildos consreport|r to see details in raid chat."])
            else
                BRutus:Print(L["Consumable check returned no results (not in a raid?)."])
            end
        else
            BRutus:Print(L["|cffFF4444Consumable Checker module is disabled.|r"])
        end
    end)
    local testConsDesc = UI:CreateText(content, L["Scans your current raid for missing consumables"], 9, C.silver.r, C.silver.g, C.silver.b)
    testConsDesc:SetPoint("LEFT", testCons, "RIGHT", 10, 0)
    yOff = yOff + 32

    -- Test: Loot Master Roll Popup
    local testLM = UI:CreateButton(content, L["Test Roll Popup"], 200, 26)
    testLM:SetPoint("TOPLEFT", 8, -yOff)
    testLM:SetScript("OnClick", function()
        if BRutus.LootMaster then
            BRutus.LootMaster.testMode = true
            -- Simulate a roll popup with a fake item
            BRutus.LootMaster:ShowRollPopup(
                "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r",
                15,
                32837
            )
            BRutus:Print(L["Test roll popup shown (15s timer). Try MS/OS/Pass buttons."])
        else
            BRutus:Print(L["|cffFF4444Loot Master module is disabled.|r"])
        end
    end)
    local testLMDesc = UI:CreateText(content, L["Shows the raider roll popup with a sample item"], 9, C.silver.r, C.silver.g, C.silver.b)
    testLMDesc:SetPoint("LEFT", testLM, "RIGHT", 10, 0)
    yOff = yOff + 32

    -- Test: Wishlist Council Preview
    local testCouncil = UI:CreateButton(content, L["Test Wishlist Council"], 200, 26)
    testCouncil:SetPoint("TOPLEFT", 8, -yOff)
    testCouncil:SetScript("OnClick", function()
        if BRutus.LootMaster then
            BRutus.LootMaster.testMode = true
            -- Show council frame with fake data
            local fakeWinner = { name = UnitName("player"), class = select(2, UnitClass("player")), wishlistType = "wishlist", order = 1 }
            local fakeCandidates = {
                fakeWinner,
                { name = "TestPlayer", class = "WARRIOR", wishlistType = "wishlist", order = 2 },
                { name = "AnotherOne", class = "MAGE", wishlistType = "wishlist", order = 3 },
            }
            BRutus.LootMaster.activeLoot = {
                link = "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r",
                slot = nil,
                itemId = 32837,
            }
            BRutus.LootMaster:ShowCouncilResultFrame(
                fakeWinner,
                "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r",
                nil,
                fakeCandidates
            )
            BRutus:Print(L["Test council frame shown. Award button won't work (no loot slot)."])
        else
            BRutus:Print(L["|cffFF4444Loot Master module is disabled.|r"])
        end
    end)
    local testCouncilDesc = UI:CreateText(content, L["Shows the ML council result frame with sample data"], 9, C.silver.r, C.silver.g, C.silver.b)
    testCouncilDesc:SetPoint("LEFT", testCouncil, "RIGHT", 10, 0)
    yOff = yOff + 32

    -- Test: ML Roll Tracker
    local testRollFrame = UI:CreateButton(content, L["Test Roll Tracker"], 200, 26)
    testRollFrame:SetPoint("TOPLEFT", 8, -yOff)
    testRollFrame:SetScript("OnClick", function()
        if BRutus.LootMaster then
            BRutus.LootMaster.testMode = true
            BRutus.LootMaster.activeLoot = {
                link = "|cffa335ee|Hitem:30110::::::::70:::::|h[Tsunami Talisman]|h|r",
                slot = nil,
                itemId = 30110,
                startTime = GetServerTime(),
                endTime = GetServerTime() + 30,
            }
            BRutus.LootMaster.rolls = {
                ["TestWarrior-Realm"] = { name = "TestWarrior", class = "WARRIOR", rollType = "MS", roll = 87, prioOrder = 1 },
                ["TestMage-Realm"] = { name = "TestMage", class = "MAGE", rollType = "MS", roll = 54, wishlist = { order = 2 } },
                ["TestPriest-Realm"] = { name = "TestPriest", class = "PRIEST", rollType = "OS", roll = 92 },
                ["TestRogue-Realm"] = { name = "TestRogue", class = "ROGUE", rollType = "PASS", roll = 0 },
            }
            BRutus.LootMaster:ShowRollFrame()
            BRutus:Print(L["Test roll tracker shown with sample rolls."])
        else
            BRutus:Print(L["|cffFF4444Loot Master module is disabled.|r"])
        end
    end)
    local testRFDesc = UI:CreateText(content, L["Shows the ML roll tracker with sample roll data"], 9, C.silver.r, C.silver.g, C.silver.b)
    testRFDesc:SetPoint("LEFT", testRollFrame, "RIGHT", 10, 0)
    yOff = yOff + 32

    -- Test: Raid Tracker Status
    local testRT = UI:CreateButton(content, L["Test Raid Status"], 200, 26)
    testRT:SetPoint("TOPLEFT", 8, -yOff)
    testRT:SetScript("OnClick", function()
        if BRutus.RaidTracker then
            local total = BRutus.RaidTracker:GetTotalSessions()
            local tracking = BRutus.RaidTracker.trackingActive
            BRutus:Print(string.format(L["Raid Tracker: %d sessions recorded. Currently %s."],
                total, tracking and "|cff00ff00" .. L["tracking"] .. "|r" or "|cffFF4444" .. L["not tracking"] .. "|r"))
            if BRutus.RaidTracker.currentRaid then
                BRutus:Print(L["Active raid: "] .. (BRutus.RaidTracker.currentRaid.name or L["Unknown"]))
            end
        else
            BRutus:Print(L["|cffFF4444Raid Tracker module is disabled.|r"])
        end
    end)
    local testRTDesc = UI:CreateText(content, L["Shows current raid tracking status and session count"], 9, C.silver.r, C.silver.g, C.silver.b)
    testRTDesc:SetPoint("LEFT", testRT, "RIGHT", 10, 0)
    yOff = yOff + 32

    -- Test: ML Loot Frame
    local testLootFrame = UI:CreateButton(content, L["Test Loot Frame"], 200, 26)
    testLootFrame:SetPoint("TOPLEFT", 8, -yOff)
    testLootFrame:SetScript("OnClick", function()
        if BRutus.LootMaster then
            BRutus.LootMaster.testMode = true
            local fakeItems = {
                { slot = 1, link = "|cffa335ee|Hitem:30110::::::::70:::::|h[Tsunami Talisman]|h|r",   name = "Tsunami Talisman",    quality = 4 },
                { slot = 2, link = "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r", name = "Warglaive of Azzinoth", quality = 5 },
                { slot = 3, link = "|cffa335ee|Hitem:30019::::::::70:::::|h[Ring of Endless Coils]|h|r", name = "Ring of Endless Coils", quality = 4 },
            }
            BRutus.LootMaster:ShowLootFrame(fakeItems)
            BRutus:Print(L["Test loot frame shown with 3 sample items."])
        else
            BRutus:Print(L["|cffFF4444Loot Master module is disabled.|r"])
        end
    end)
    local testLFDesc = UI:CreateText(content, L["Opens the ML loot frame with sample items"], 9, C.silver.r, C.silver.g, C.silver.b)
    testLFDesc:SetPoint("LEFT", testLootFrame, "RIGHT", 10, 0)
    yOff = yOff + 32

    -- Test: Export Attendance
    local testExport = UI:CreateButton(content, L["Test Attendance Export"], 200, 26)
    testExport:SetPoint("TOPLEFT", 8, -yOff)
    testExport:SetScript("OnClick", function()
        if BRutus.RaidTracker then
            local json, err = BRutus.RaidTracker:ExportForTMB()
            if json then
                BRutus:ShowExportPopup(L["Attendance Export"], json)
            else
                BRutus:Print(L["|cffFF4444Export failed:|r "] .. (err or L["No attendance data"]))
            end
        else
            BRutus:Print(L["|cffFF4444Raid Tracker module is disabled.|r"])
        end
    end)
    local testExpDesc = UI:CreateText(content, L["Opens the attendance export window"], 9, C.silver.r, C.silver.g, C.silver.b)
    testExpDesc:SetPoint("LEFT", testExport, "RIGHT", 10, 0)
    yOff = yOff + 32

    end -- isOfficer (Test Functions)

    yOff = yOff + 8
    local sep5 = UI:CreateSeparator(content)
    sep5:SetPoint("TOPLEFT", 0, -yOff)
    sep5:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    if isOfficer then
    --------------------------------------------------------------------
    -- OFFICER RANK CONFIGURATION (officer only)
    --------------------------------------------------------------------
    local rankTitle = UI:CreateHeaderText(content, L["OFFICER RANKS"], 12)
    rankTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    local rankDesc = UI:CreateText(content,
        L["Checked ranks will have access to officer features in Guild OS."],
        10, C.silver.r, C.silver.g, C.silver.b)
    rankDesc:SetPoint("TOPLEFT", 8, -yOff)
    rankDesc:SetWidth(content:GetWidth() - 20)
    yOff = yOff + 18

    -- Read current max rank setting
    local currentMaxRank = BRutus.db.settings.officerMaxRank or 2

    -- Get rank names from the WoW guild control API (1-based, rank 1 = GM)
    local numRanks = 0
    if GuildControlGetNumRanks then
        numRanks = GuildControlGetNumRanks() or 0
    end

    if numRanks == 0 then
        local noRankText = UI:CreateText(content, L["Guild rank info not available. Open the Guild panel first."], 10, C.silver.r, C.silver.g, C.silver.b)
        noRankText:SetPoint("TOPLEFT", 8, -yOff)
        yOff = yOff + 18
    else
        -- Checkboxes: one per rank (rank 0 = index 1 in GuildControl = GM, always checked)
        -- We store officerMaxRank as 0-based WoW rankIndex
        for i = 1, numRanks do
            local rankWoWIndex = i - 1  -- convert to 0-based WoW rankIndex
            local rankName = GuildControlGetRankName and GuildControlGetRankName(i) or (L["Rank "] .. rankWoWIndex)
            if not rankName or rankName == "" then rankName = L["Rank "] .. rankWoWIndex end

            local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(content:GetWidth() - 10, 26)
            row:SetPoint("TOPLEFT", 0, -yOff)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            row:SetBackdropColor(0.082, 0.082, 0.105, 0.5)

            local isGM = (rankWoWIndex == 0)
            local isChecked = (rankWoWIndex <= currentMaxRank)

            local cb = UI:CreateCheckbox(row, rankName, 18)
            cb:SetPoint("LEFT", 8, 0)
            cb.checkbox:SetChecked(isChecked)

            -- Rank label showing 0-based index
            local idxLabel = UI:CreateText(row, L["(rank "] .. rankWoWIndex .. ")", 9, C.silver.r, C.silver.g, C.silver.b)
            idxLabel:SetPoint("LEFT", 220, 0)

            if isGM then
                -- GM is always an officer, cannot be unchecked
                cb.checkbox:Disable()
                local lockNote = UI:CreateText(row, L["|cff666666always officer|r"], 9, 0.4, 0.4, 0.4)
                lockNote:SetPoint("LEFT", 280, 0)
            else
            local capturedRankIndex = rankWoWIndex
            cb.checkbox.onChanged = function(_, checked)
                -- officerMaxRank = highest rank that is checked.
                -- Checking a rank implicitly checks all ranks above it (lower index).
                -- Unchecking a rank implicitly unchecks all ranks below it (higher index).
                local newMax
                if checked then
                    -- Expand threshold to include this rank if it's higher
                    newMax = math.max(capturedRankIndex, BRutus.db.settings.officerMaxRank or 0)
                else
                    -- Shrink threshold to exclude this rank and all below it
                    newMax = capturedRankIndex - 1
                    if newMax < 0 then newMax = 0 end
                end
                BRutus.db.settings.officerMaxRank = newMax
                local newRankName = GuildControlGetRankName and GuildControlGetRankName(newMax + 1) or (L["Rank "] .. newMax)
                BRutus:Print(L["Officer threshold: ranks 0-"] .. newMax .. " (" .. newRankName .. L[" and above are officers)."])
            end
            end

            yOff = yOff + 28
        end
    end

    yOff = yOff + 4
    local rankNote = UI:CreateText(content,
        L["Change takes effect immediately. Reload UI required to reload officer modules."],
        9, C.silver.r, C.silver.g, C.silver.b)
    rankNote:SetPoint("TOPLEFT", 8, -yOff)
    rankNote:SetWidth(content:GetWidth() - 20)
    yOff = yOff + 20

    end -- isOfficer (Rank config)

    yOff = yOff + 8
    local sep6 = UI:CreateSeparator(content)
    sep6:SetPoint("TOPLEFT", 0, -yOff)
    sep6:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    -- Reload UI button
    local reloadBtn = UI:CreateButton(content, L["Reload UI"], 120, 28)
    reloadBtn:SetPoint("TOPLEFT", 8, -yOff)
    reloadBtn:SetBackdropColor(0.4, 0.15, 0.0, 0.6)
    reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    reloadBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.2, 0.0, 0.8)
        self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.8)
    end)
    reloadBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.15, 0.0, 0.6)
        self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
    end)
    local reloadNote = UI:CreateText(content, L["Required after enabling/disabling modules"], 9, C.silver.r, C.silver.g, C.silver.b)
    reloadNote:SetPoint("LEFT", reloadBtn, "RIGHT", 10, 0)
    yOff = yOff + 36

    --------------------------------------------------------------------
    -- ABOUT & SUPPORT
    --------------------------------------------------------------------
    yOff = yOff + 8
    local sepAbout = UI:CreateSeparator(content)
    sepAbout:SetPoint("TOPLEFT", 0, -yOff)
    sepAbout:SetPoint("TOPRIGHT", -10, -yOff)
    yOff = yOff + 12

    local aboutTitle = UI:CreateHeaderText(content, L["ABOUT & SUPPORT"], 12)
    aboutTitle:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 22

    local verText = UI:CreateText(content, "Guild OS v" .. (BRutus.VERSION or "?"), 11, C.gold.r, C.gold.g, C.gold.b)
    verText:SetPoint("TOPLEFT", 8, -yOff)
    yOff = yOff + 20

    local privacy = UI:CreateText(content,
        L["Guild OS syncs your gear, professions, attunements, spec and wishlist with guildmates running the addon. Officer notes and trials stay officer-only."],
        10, C.silver.r, C.silver.g, C.silver.b)
    privacy:SetPoint("TOPLEFT", 8, -yOff)
    privacy:SetWidth(content:GetWidth() - 20)
    privacy:SetJustifyH("LEFT")
    yOff = yOff + 42

    local cmds = UI:CreateText(content,
        "/guildos  |  /guildos sync  |  /guildos prune  |  /guildos minimap  |  /guildos debug",
        9, C.textDim.r, C.textDim.g, C.textDim.b)
    cmds:SetPoint("TOPLEFT", 8, -yOff)
    yOff = yOff + 22

    local linksBtn = UI:CreateButton(content, L["Links"], 120, 24)
    linksBtn:SetPoint("TOPLEFT", 8, -yOff)
    linksBtn:SetScript("OnClick", function()
        BRutus:ShowExportPopup(L["Guild OS Links"],
            "GitHub:  https://github.com/danielcosta42/GuildOS\n"
            .. "CurseForge:  https://www.curseforge.com/projects/1549177\n"
            .. "Wago:  https://addons.wago.io/addons/b6XeDxKp")
    end)
    local linksNote = UI:CreateText(content, L["Project page, bug reports and updates"], 9, C.silver.r, C.silver.g, C.silver.b)
    linksNote:SetPoint("LEFT", linksBtn, "RIGHT", 10, 0)
    yOff = yOff + 34

    content:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- WISHLIST FRAME — standalone frame for each member's own wishlist
-- Accessible via /brutus wish  or the "My Wishlist" button in roster.
----------------------------------------------------------------------
-- WISH_VISIBLE × WISH_ROW_HEIGHT must fit within the scroll area.
-- Frame=520, title+header=66, bottom bar=50 → scroll area=404px → max rows=floor(404/28)=14
local WISH_ROW_HEIGHT = 28
local WISH_VISIBLE    = 14

local function BuildWishlistFrame()
    local f = CreateFrame("Frame", "BRutusWishlistFrame", UIParent, "BackdropTemplate")
    f:SetSize(500, 520)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:Hide()

    table.insert(UISpecialFrames, "BRutusWishlistFrame")

    -- Refresh rows whenever a queued item arrives from the server
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(self, event)
        if event == "GET_ITEM_INFO_RECEIVED" and self:IsShown() then
            if not self._itemInfoTimer then
                self._itemInfoTimer = true
                C_Timer.After(0.3, function()
                    self._itemInfoTimer = nil
                    if f:IsShown() then
                        BRutus:RefreshWishlistFrame()
                    end
                end)
            end
        end
    end)

    -- Title bar
    local titleBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    titleBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleBg:SetPoint("TOPLEFT",  1, -1)
    titleBg:SetPoint("TOPRIGHT", -1, -1)
    titleBg:SetHeight(39)
    titleBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    titleText:SetPoint("LEFT", 14, 0)
    titleText:SetPoint("TOP", 0, -12)
    titleText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleText:SetText(L["MY WISHLIST"])
    f.titleText = titleText

    -- Counter (N/50)
    local counterText = f:CreateFontString(nil, "OVERLAY")
    counterText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    counterText:SetPoint("RIGHT", -42, 0)
    counterText:SetPoint("TOP",    0, -14)
    counterText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    counterText:SetText("0/50")
    f.counterText = counterText

    -- Accent line under title
    local titleLine = UI:CreateAccentLine(f, 2)
    titleLine:SetPoint("TOPLEFT",  0, -40)
    titleLine:SetPoint("TOPRIGHT", 0, -40)

    -- Close button
    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Column headers background
    local hdrBg = f:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    hdrBg:SetPoint("TOPLEFT",  1, -42)
    hdrBg:SetPoint("TOPRIGHT", -1, -42)
    hdrBg:SetHeight(22)
    hdrBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.9)

    local function Hdr(lbl, x, w, justify)
        local t = f:CreateFontString(nil, "OVERLAY")
        t:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        t:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        t:SetPoint("TOPLEFT", x, -44)
        t:SetWidth(w)
        t:SetJustifyH(justify or "LEFT")
        t:SetText(lbl)
        return t
    end
    Hdr("#",      10,  24, "CENTER")
    Hdr(L["ITEM"],   38, 262, "LEFT")
    Hdr(L["TYPE"],  308,  50, "CENTER")
    Hdr(L["ORDER"], 366,  60, "CENTER")

    -- Thin separator between headers and rows
    local hdrLine = UI:CreateAccentLine(f, 1)
    hdrLine:SetPoint("TOPLEFT",  1, -64)
    hdrLine:SetPoint("TOPRIGHT", -1, -64)

    -- Scroll area: TOPLEFT at y=-65, BOTTOMRIGHT at y=+50 (50px bottom bar)
    -- Available height: 520 - 65 - 50 = 405px; 14 rows × 28px = 392px ✓
    local scrollContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    scrollContainer:SetPoint("TOPLEFT",     1, -65)
    scrollContainer:SetPoint("BOTTOMRIGHT", -1, 50)
    scrollContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    scrollContainer:SetBackdropColor(0.035, 0.035, 0.050, 1.0)

    local scrollFrame = CreateFrame("ScrollFrame", "BRutusWishlistScroll", scrollContainer, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -16, 0)
    UI:SkinScrollBar(scrollFrame, "BRutusWishlistScroll")
    f.scrollFrame = scrollFrame

    -- Rows (parented to scrollContainer, clipped by it)
    f.rows = {}
    for i = 1, WISH_VISIBLE do
        local row = CreateFrame("Button", "BRutusWishRow" .. i, scrollContainer, "BackdropTemplate")
        row:SetHeight(WISH_ROW_HEIGHT)
        row:SetPoint("TOPLEFT",  0, -((i - 1) * WISH_ROW_HEIGHT))
        row:SetPoint("RIGHT",  scrollContainer, "RIGHT", -18, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        local bgColor = (i % 2 == 0) and C.row2 or C.row1
        row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        row.defaultBg = bgColor

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            if self.itemLink and self.itemLink ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            local bg = self.defaultBg
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            GameTooltip:Hide()
        end)

        -- Order number
        local numText = row:CreateFontString(nil, "OVERLAY")
        numText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        numText:SetPoint("LEFT", 10, 0)
        numText:SetWidth(24)
        numText:SetJustifyH("CENTER")
        numText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        row.numText = numText

        -- Item link text
        local itemText = row:CreateFontString(nil, "OVERLAY")
        itemText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        itemText:SetPoint("LEFT", 38, 0)
        itemText:SetWidth(262)
        itemText:SetJustifyH("LEFT")
        itemText:SetWordWrap(false)
        row.itemText = itemText

        -- MS/OS badge
        local typeText = row:CreateFontString(nil, "OVERLAY")
        typeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        typeText:SetPoint("LEFT", 308, 0)
        typeText:SetWidth(50)
        typeText:SetJustifyH("CENTER")
        row.typeText = typeText

        -- ↑ button
        local upBtn = CreateFrame("Button", nil, row)
        upBtn:SetSize(18, 18)
        upBtn:SetPoint("LEFT", 366, 0)
        upBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        upBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        upBtn:SetScript("OnClick", function()
            if row.itemId and BRutus.Wishlist then
                BRutus.Wishlist:ReorderWishlist(row.itemId, -1)
            end
        end)
        upBtn:SetScript("OnLeave", function()
            local bg = row.defaultBg
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end)

        -- ↓ button
        local downBtn = CreateFrame("Button", nil, row)
        downBtn:SetSize(18, 18)
        downBtn:SetPoint("LEFT", 386, 0)
        downBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        downBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        downBtn:SetScript("OnClick", function()
            if row.itemId and BRutus.Wishlist then
                BRutus.Wishlist:ReorderWishlist(row.itemId, 1)
            end
        end)
        downBtn:SetScript("OnLeave", function()
            local bg = row.defaultBg
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end)

        -- × remove button
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(18, 18)
        removeBtn:SetPoint("LEFT", 410, 0)
        local removeTex = removeBtn:CreateFontString(nil, "OVERLAY")
        removeTex:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        removeTex:SetPoint("CENTER")
        removeTex:SetTextColor(0.7, 0.2, 0.2)
        removeTex:SetText("×")
        removeBtn:SetScript("OnClick", function()
            if row.itemId and BRutus.Wishlist then
                BRutus.Wishlist:RemoveFromWishlist(row.itemId)
            end
        end)
        removeBtn:SetScript("OnLeave", function()
            local bg = row.defaultBg
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end)
        removeBtn:SetScript("OnEnter", function()
            removeTex:SetTextColor(1, 0.3, 0.3)
        end)

        row:Hide()
        f.rows[i] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, WISH_ROW_HEIGHT, function()
            BRutus:RefreshWishlistFrame()
        end)
    end)

    -- Bottom bar (50px): separator line + dark background
    local bottomLine = UI:CreateAccentLine(f, 1)
    bottomLine:SetPoint("BOTTOMLEFT",  0, 50)
    bottomLine:SetPoint("BOTTOMRIGHT", 0, 50)

    local bottomBg = f:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottomBg:SetPoint("BOTTOMLEFT",  1, 1)
    bottomBg:SetPoint("BOTTOMRIGHT", -1, 1)
    bottomBg:SetHeight(49)
    bottomBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    -- MS/OS radio buttons
    -- Layout (500px frame): [10] [msBtn 56] [4] [osBtn 56] [6] [addBox 162] [6] [addBtn 88] [8] [syncBtn 80] [8]
    -- Total: 10+56+4+56+6+162+6+88+8+80+8 = 484, centred with margins ✓
    f.isOS = false   -- false = Main Spec, true = Off Spec

    local msBtn = UI:CreateButton(f, L["MS"], 56, 28)
    msBtn:SetPoint("BOTTOMLEFT", 10, 11)
    -- Small dot indicator (6x6 texture, left of label)
    local msDot = msBtn:CreateTexture(nil, "OVERLAY")
    msDot:SetTexture("Interface\\Buttons\\WHITE8x8")
    msDot:SetSize(6, 6)
    msDot:SetPoint("RIGHT", msBtn.label, "LEFT", -4, 0)
    msBtn.dot = msDot
    f.msBtn = msBtn

    local osBtn = UI:CreateButton(f, L["OS"], 56, 28)
    osBtn:SetPoint("BOTTOMLEFT", msBtn, "BOTTOMRIGHT", 4, 0)
    local osDot = osBtn:CreateTexture(nil, "OVERLAY")
    osDot:SetTexture("Interface\\Buttons\\WHITE8x8")
    osDot:SetSize(6, 6)
    osDot:SetPoint("RIGHT", osBtn.label, "LEFT", -4, 0)
    osBtn.dot = osDot
    f.osBtn = osBtn

    local function SetSpecType(isOS)
        f.isOS = isOS
        if isOS then
            -- OS selected
            msBtn.label:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            msBtn.dot:SetVertexColor(0.3, 0.3, 0.3, 0.6)
            msBtn:SetBackdropColor(0.045, 0.045, 0.060, 0.5)
            msBtn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)
            osBtn.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            osBtn.dot:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1.0)
            osBtn:SetBackdropColor(0.22, 0.16, 0.02, 0.9)
            osBtn:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1.0)
        else
            -- MS selected
            msBtn.label:SetTextColor(1.0, 1.0, 1.0)
            msBtn.dot:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 1.0)
            msBtn:SetBackdropColor(C.accentDim.r, C.accentDim.g, C.accentDim.b, 0.9)
            msBtn:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1.0)
            osBtn.label:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            osBtn.dot:SetVertexColor(0.3, 0.3, 0.3, 0.6)
            osBtn:SetBackdropColor(0.045, 0.045, 0.060, 0.5)
            osBtn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)
        end
    end

    msBtn:SetScript("OnClick", function() SetSpecType(false) end)
    osBtn:SetScript("OnClick", function() SetSpecType(true)  end)

    -- Override hover to preserve radio state visually
    msBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Main Spec"], C.gold.r, C.gold.g, C.gold.b)
        GameTooltip:AddLine(L["Item and priority for your main spec."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    msBtn:SetScript("OnLeave", function()
        SetSpecType(f.isOS)
        GameTooltip:Hide()
    end)
    osBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Off Spec"], C.gold.r, C.gold.g, C.gold.b)
        GameTooltip:AddLine(L["Item for a secondary spec."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    osBtn:SetScript("OnLeave", function()
        SetSpecType(f.isOS)
        GameTooltip:Hide()
    end)

    SetSpecType(false)   -- initialise with MS selected

    -- Add item edit box
    local addBox = CreateFrame("EditBox", "BRutusWishAddBox", f, "BackdropTemplate")
    addBox:SetSize(162, 28)
    addBox:SetPoint("BOTTOMLEFT", osBtn, "BOTTOMRIGHT", 6, 0)
    addBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    addBox:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    addBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.5)
    addBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    addBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    addBox:SetTextInsets(6, 6, 0, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(200)

    local addPlaceholder = addBox:CreateFontString(nil, "OVERLAY")
    addPlaceholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    addPlaceholder:SetPoint("LEFT", 6, 0)
    addPlaceholder:SetTextColor(0.4, 0.4, 0.4)
    addPlaceholder:SetText(L["Search item or paste link..."])

    -- Search dropdown — appears above the addBox
    local DROP_ROWS  = 6
    local DROP_ROW_H = 22

    local dropdown = CreateFrame("Frame", nil, f, "BackdropTemplate")
    dropdown:SetWidth(280)
    dropdown:SetHeight(DROP_ROWS * DROP_ROW_H + 2)
    dropdown:SetPoint("BOTTOMLEFT", addBox, "TOPLEFT", 0, 2)
    dropdown:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.98)
    dropdown:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(dropdown, { shadowSize = 10 })
    dropdown:SetFrameLevel(f:GetFrameLevel() + 20)
    dropdown:Hide()
    f.dropdown = dropdown

    dropdown.rows = {}
    for i = 1, DROP_ROWS do
        local dr = CreateFrame("Button", nil, dropdown)
        dr:SetHeight(DROP_ROW_H)
        dr:SetPoint("TOPLEFT",  1, -((i - 1) * DROP_ROW_H) - 1)
        dr:SetPoint("TOPRIGHT", -1, -((i - 1) * DROP_ROW_H) - 1)
        dr:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        dr:GetHighlightTexture():SetVertexColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 0.3)
        local drText = dr:CreateFontString(nil, "OVERLAY")
        drText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        drText:SetPoint("LEFT", 6, 0)
        drText:SetPoint("RIGHT", -6, 0)
        drText:SetJustifyH("LEFT")
        drText:SetWordWrap(false)
        dr.label = drText
        dr:SetScript("OnClick", function()
            f.selectedItemId   = dr.itemId
            f.selectedItemLink = dr.itemLink
            f.selectedItemName = dr.itemName
            f.suppressSearch   = true
            addBox:SetText(dr.itemName or "")
            f.suppressSearch   = nil
            addPlaceholder:Hide()
            dropdown:Hide()
        end)
        dropdown.rows[i] = dr
        dr:Hide()
    end

    local function UpdateDropdown(query)
        query = strlower(strtrim(query or ""))
        -- Skip search for empty input, pasted links, or raw IDs — handled directly in DoAdd
        if query == "" or query:find("item:", 1, true) or tonumber(query) then
            dropdown:Hide()
            return
        end
        local results = {}
        if BRutus.Wishlist and BRutus.Wishlist.itemIndex then
            for itemId in pairs(BRutus.Wishlist.itemIndex) do
                local name, link, quality = GetItemInfo(itemId)
                if name and strlower(name):find(query, 1, true) then
                    tinsert(results, { itemId = itemId, name = name, link = link, quality = quality or 1 })
                end
            end
        end
        table.sort(results, function(a, b) return a.name < b.name end)
        if #results == 0 then
            dropdown:Hide()
            return
        end
        local shown = math.min(#results, DROP_ROWS)
        dropdown:SetHeight(shown * DROP_ROW_H + 2)
        for i = 1, DROP_ROWS do
            local dr = dropdown.rows[i]
            if i <= shown then
                local entry = results[i]
                local r, g, b = GetItemQualityColor(entry.quality)
                dr.label:SetText(entry.name)
                dr.label:SetTextColor(r, g, b)
                dr.itemId   = entry.itemId
                dr.itemLink = entry.link
                dr.itemName = entry.name
                dr:Show()
            else
                dr:Hide()
            end
        end
        dropdown:Show()
    end

    addBox:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        if t and t ~= "" then addPlaceholder:Hide() else addPlaceholder:Show() end
        if f.suppressSearch then return end
        -- Guard: WoW may fire OnTextChanged twice after SetText; don't clear
        -- the selection if the text still matches what was just selected.
        if f.selectedItemId and t == f.selectedItemName then return end
        f.selectedItemId   = nil
        f.selectedItemLink = nil
        f.selectedItemName = nil
        UpdateDropdown(t)
    end)

    local function DoAdd()
        local text = strtrim(addBox:GetText() or "")
        if text == "" then return end
        local itemId, itemLink
        if f.selectedItemId then
            -- Came from dropdown click
            itemId   = f.selectedItemId
            itemLink = f.selectedItemLink or ""
        elseif text:find("item:") then
            -- Pasted a full item hyperlink
            itemId   = tonumber(text:match("item:(%d+)"))
            itemLink = text
        elseif tonumber(text) then
            -- Typed a raw item ID
            itemId = tonumber(text)
            local _, lnk = GetItemInfo(itemId)
            itemLink = lnk or ""
        end
        if not itemId then
            BRutus:Print(L["[Wishlist] Select from the list, paste an item link, or type the item ID."])
            return
        end
        if BRutus.Wishlist then
            BRutus.Wishlist:AddToWishlist(itemId, itemLink, f.isOS)
        end
        addBox:SetText("")
        addBox:ClearFocus()
        f.selectedItemId   = nil
        f.selectedItemLink = nil
        f.selectedItemName = nil
        dropdown:Hide()
    end

    addBox:SetScript("OnEnterPressed", function(self) DoAdd(); self:ClearFocus() end)
    addBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        dropdown:Hide()
    end)
    f.addBox = addBox

    local addBtn = UI:CreateButton(f, L["+ Add"], 88, 28)
    addBtn:SetPoint("BOTTOMLEFT", addBox, "BOTTOMRIGHT", 6, 0)
    addBtn:SetScript("OnClick", DoAdd)

    -- Sync button — anchored to the right, with guaranteed gap from addBtn
    local syncBtn = UI:CreateButton(f, L["Sync"], 80, 28)
    syncBtn:SetPoint("BOTTOMRIGHT", -8, 11)
    syncBtn:SetScript("OnClick", function()
        if BRutus.Wishlist then BRutus.Wishlist:BroadcastMyWishlist() end
        BRutus:Print(L["[Wishlist] Sent to the guild."])
    end)

    BRutus.WishlistFrame = f
    return f
end

function BRutus:ShowWishlistFrame()
    if not self.WishlistFrame then
        BuildWishlistFrame()
    end
    -- Pre-request item info for all wishlist entries so the client
    -- fetches any uncached items before (or just after) we display them.
    local list = (BRutus.Wishlist and BRutus.Wishlist:GetMyList()) or {}
    for _, entry in ipairs(list) do
        GetItemInfo(entry.itemId)
    end
    self:RefreshWishlistFrame()
    self.WishlistFrame:Show()
end

function BRutus:RefreshWishlistFrame()
    local f = self.WishlistFrame
    if not f then return end

    local rawList = (BRutus.Wishlist and BRutus.Wishlist:GetMyList()) or {}

    -- Split into active and delivered; delivered entries appear at the bottom.
    local active    = {}
    local delivered = {}
    for _, entry in ipairs(rawList) do
        local isDelivered = BRutus.Wishlist and BRutus.Wishlist:IsItemDelivered(entry.itemId)
        if isDelivered then
            table.insert(delivered, entry)
        else
            table.insert(active, entry)
        end
    end
    local list = {}
    for _, e in ipairs(active)    do table.insert(list, { entry = e, delivered = false }) end
    for _, e in ipairs(delivered) do table.insert(list, { entry = e, delivered = true  }) end

    local total = #list
    f.counterText:SetText(#rawList .. "/50")

    local offset = FauxScrollFrame_GetOffset(f.scrollFrame)
    FauxScrollFrame_Update(f.scrollFrame, total, WISH_VISIBLE, WISH_ROW_HEIGHT)

    for i = 1, WISH_VISIBLE do
        local row     = f.rows[i]
        local dataIdx = offset + i

        if dataIdx <= total then
            local item        = list[dataIdx]
            local entry       = item.entry
            local isDelivered = item.delivered

            -- Background: delivered rows use a darker, muted colour
            local bgColor
            if isDelivered then
                bgColor = { r=0.08, g=0.08, b=0.08, a=0.9 }
            else
                bgColor = (i % 2 == 0) and C.row2 or C.row1
            end
            row.defaultBg = bgColor
            row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

            row.itemId   = entry.itemId
            row.itemLink = entry.itemLink or ""

            -- Order number: show "✓" for delivered items
            if isDelivered then
                row.numText:SetText("|cff44FF44✓|r")
            else
                row.numText:SetText(entry.order or dataIdx)
            end

            -- Item display
            local localName, localLink = GetItemInfo(entry.itemId)
            local displayText
            if localLink then
                displayText = localLink
            elseif localName then
                displayText = localName
            elseif entry.itemLink and entry.itemLink ~= "" then
                displayText = entry.itemLink
            else
                displayText = L["Item #"] .. entry.itemId
            end
            row.itemText:SetText(displayText)

            -- Dim delivered item text
            if isDelivered then
                row.itemText:SetTextColor(0.45, 0.45, 0.45)
            else
                row.itemText:SetTextColor(C.white.r, C.white.g, C.white.b)
            end

            if entry.isOffspec then
                row.typeText:SetText("|cffAAAAAA  " .. L["OS"] .. "|r")
            else
                row.typeText:SetText("|cff4CB5FF  " .. L["MS"] .. "|r")
            end

            -- Show/hide action buttons based on delivered state
            for _, child in pairs({ row:GetChildren() }) do
                local childType = child:GetObjectType()
                if childType == "Button" or childType == "Frame" then
                    if isDelivered then
                        child:Hide()
                    else
                        child:Show()
                    end
                end
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

----------------------------------------------------------------------
-- OFFICER PRIO MODAL — manage item priorities (officer-only)
-- Accessible via the Wishlist panel "Gerenciar Prios" button.
----------------------------------------------------------------------
local PRIO_ROW_HEIGHT = 28
local PRIO_VISIBLE    = 14

local function BuildPrioModal()
    local f = CreateFrame("Frame", "BRutusPrioModal", UIParent, "BackdropTemplate")
    f:SetSize(560, 500)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.8)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(60)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:Hide()

    table.insert(UISpecialFrames, "BRutusPrioModal")

    -- Title bar
    local titleBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    titleBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleBg:SetPoint("TOPLEFT"); titleBg:SetPoint("TOPRIGHT"); titleBg:SetHeight(40)
    titleBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    titleText:SetPoint("LEFT", 14, 0); titleText:SetPoint("TOP", 0, -12)
    titleText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleText:SetText(L["MANAGE PRIORITIES"])
    f.titleText = titleText

    local titleLine = UI:CreateAccentLine(f, 2)
    titleLine:SetPoint("TOPLEFT", 0, -40); titleLine:SetPoint("TOPRIGHT", 0, -40)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Subtitle: shows currently loaded item
    local subtitleText = f:CreateFontString(nil, "OVERLAY")
    subtitleText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    subtitleText:SetPoint("LEFT", 14, 0); subtitleText:SetPoint("TOP", 0, -28)
    subtitleText:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 0.7)
    subtitleText:SetText(L["Search for an item to manage priorities"])

    -- Item search bar
    local searchBg = f:CreateTexture(nil, "BACKGROUND")
    searchBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    searchBg:SetPoint("TOPLEFT", 1, -42); searchBg:SetPoint("TOPRIGHT", -1, -42)
    searchBg:SetHeight(36)
    searchBg:SetVertexColor(0.08, 0.08, 0.12, 1.0)

    local LoadItem  -- forward declaration

    local searchBox = CreateFrame("EditBox", "BRutusPrioSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(320, 26)
    searchBox:SetPoint("LEFT", 10, 0); searchBox:SetPoint("TOP", 0, -52)
    searchBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    searchBox:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    searchBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(200)

    local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
    placeholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    placeholder:SetText(L["Search item, paste link or ID..."])

    -- Search dropdown
    local PDROP_ROWS  = 6
    local PDROP_ROW_H = 22

    local prioDropdown = CreateFrame("Frame", nil, f, "BackdropTemplate")
    prioDropdown:SetWidth(320)
    prioDropdown:SetHeight(PDROP_ROWS * PDROP_ROW_H + 2)
    prioDropdown:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -2)
    prioDropdown:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    prioDropdown:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.98)
    prioDropdown:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(prioDropdown, { shadowSize = 10 })
    prioDropdown:SetFrameLevel(f:GetFrameLevel() + 20)
    prioDropdown:Hide()

    prioDropdown.rows = {}
    for i = 1, PDROP_ROWS do
        local dr = CreateFrame("Button", nil, prioDropdown)
        dr:SetHeight(PDROP_ROW_H)
        dr:SetPoint("TOPLEFT",  1, -((i - 1) * PDROP_ROW_H) - 1)
        dr:SetPoint("TOPRIGHT", -1, -((i - 1) * PDROP_ROW_H) - 1)
        dr:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        dr:GetHighlightTexture():SetVertexColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 0.3)
        local drText = dr:CreateFontString(nil, "OVERLAY")
        drText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        drText:SetPoint("LEFT", 6, 0)
        drText:SetPoint("RIGHT", -6, 0)
        drText:SetJustifyH("LEFT")
        drText:SetWordWrap(false)
        dr.label = drText
        dr:SetScript("OnClick", function()
            f.prioSearchItemId   = dr.itemId
            f.prioSearchItemName = dr.itemName
            f.suppressPrioSearch = true
            searchBox:SetText(dr.itemName or "")
            f.suppressPrioSearch = nil
            placeholder:Hide()
            prioDropdown:Hide()
            if LoadItem then LoadItem() end
        end)
        prioDropdown.rows[i] = dr
        dr:Hide()
    end

    local function UpdatePrioDropdown(query)
        query = strlower(strtrim(query or ""))
        if query == "" or query:find("item:", 1, true) or tonumber(query) then
            prioDropdown:Hide()
            return
        end
        local results = {}
        if BRutus.Wishlist and BRutus.Wishlist.itemIndex then
            for itemId in pairs(BRutus.Wishlist.itemIndex) do
                local name, _, quality = GetItemInfo(itemId)
                if name and strlower(name):find(query, 1, true) then
                    tinsert(results, { itemId = itemId, name = name, quality = quality or 1 })
                end
            end
        end
        table.sort(results, function(a, b) return a.name < b.name end)
        if #results == 0 then
            prioDropdown:Hide()
            return
        end
        local shown = math.min(#results, PDROP_ROWS)
        prioDropdown:SetHeight(shown * PDROP_ROW_H + 2)
        for i = 1, PDROP_ROWS do
            local dr = prioDropdown.rows[i]
            if i <= shown then
                local entry = results[i]
                local r, g, b = GetItemQualityColor(entry.quality)
                dr.label:SetText(entry.name)
                dr.label:SetTextColor(r, g, b)
                dr.itemId   = entry.itemId
                dr.itemName = entry.name
                dr:Show()
            else
                dr:Hide()
            end
        end
        prioDropdown:Show()
    end

    searchBox:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        if t and t ~= "" then placeholder:Hide() else placeholder:Show() end
        if f.suppressPrioSearch then return end
        if f.prioSearchItemName and t == f.prioSearchItemName then return end
        f.prioSearchItemId   = nil
        f.prioSearchItemName = nil
        UpdatePrioDropdown(t)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        prioDropdown:Hide()
    end)

    local loadBtn = UI:CreateButton(f, L["Load"], 90, 26)
    loadBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

    -- Status line
    local statusText = f:CreateFontString(nil, "OVERLAY")
    statusText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    statusText:SetPoint("LEFT", loadBtn, "RIGHT", 10, 0)
    statusText:SetWidth(120)
    statusText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    statusText:SetText("")
    f.statusText = statusText

    -- Column headers: #PRIO | NOME | WL# | ACOES
    local hdrBg = f:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    hdrBg:SetPoint("TOPLEFT", 1, -78); hdrBg:SetPoint("TOPRIGHT", -1, -78)
    hdrBg:SetHeight(22)
    hdrBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.9)

    local function PrioHdr(lbl, x, w, justify)
        local t = f:CreateFontString(nil, "OVERLAY")
        t:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        t:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        t:SetPoint("TOPLEFT", x, -82)
        t:SetWidth(w); t:SetJustifyH(justify or "LEFT")
        t:SetText(lbl)
    end
    PrioHdr(L["#PRIO"],  10,  40, "CENTER")
    PrioHdr(L["NAME"],   56, 170, "LEFT")
    PrioHdr(L["WL #"],  230,  50, "CENTER")
    PrioHdr(L["ACTIONS"], 290,  80, "CENTER")

    -- Scroll area
    local scrollCont = CreateFrame("Frame", nil, f)
    scrollCont:SetPoint("TOPLEFT",     1, -100)
    scrollCont:SetPoint("BOTTOMRIGHT", -1,  44)

    local scrollFrame = CreateFrame("ScrollFrame", "BRutusPrioScroll", scrollCont, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0); scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(scrollFrame, "BRutusPrioScroll")
    f.scrollFrame = scrollFrame

    f.rows = {}
    for i = 1, PRIO_VISIBLE do
        local row = CreateFrame("Frame", "BRutusPrioRow" .. i, scrollCont, "BackdropTemplate")
        row:SetHeight(PRIO_ROW_HEIGHT)
        row:SetPoint("TOPLEFT",  0, -((i - 1) * PRIO_ROW_HEIGHT))
        row:SetPoint("RIGHT", scrollCont, "RIGHT", -18, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local bgColor = (i % 2 == 0) and C.row2 or C.row1
        row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        row.defaultBg = bgColor

        -- #PRIO number
        local prioOrderText = row:CreateFontString(nil, "OVERLAY")
        prioOrderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        prioOrderText:SetPoint("LEFT", 10, 0); prioOrderText:SetWidth(40); prioOrderText:SetJustifyH("CENTER")
        prioOrderText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        row.prioOrderText = prioOrderText

        -- Character name (class-colored)
        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        nameText:SetPoint("LEFT", 56, 0); nameText:SetWidth(170); nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- WL order
        local wlOrderText = row:CreateFontString(nil, "OVERLAY")
        wlOrderText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        wlOrderText:SetPoint("LEFT", 230, 0); wlOrderText:SetWidth(50); wlOrderText:SetJustifyH("CENTER")
        row.wlOrderText = wlOrderText

        -- ↑ reorder up
        local upBtn = CreateFrame("Button", nil, row)
        upBtn:SetSize(18, 18); upBtn:SetPoint("LEFT", 292, 0)
        upBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        upBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        row.upBtn = upBtn

        -- ↓ reorder down
        local downBtn = CreateFrame("Button", nil, row)
        downBtn:SetSize(18, 18); downBtn:SetPoint("LEFT", 313, 0)
        downBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        downBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        row.downBtn = downBtn

        -- × remove
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(18, 18); removeBtn:SetPoint("LEFT", 338, 0)
        local removeTex = removeBtn:CreateFontString(nil, "OVERLAY")
        removeTex:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        removeTex:SetPoint("CENTER")
        removeTex:SetTextColor(0.7, 0.2, 0.2)
        removeTex:SetText("x")
        removeBtn:SetScript("OnEnter", function() removeTex:SetTextColor(1, 0.3, 0.3) end)
        removeBtn:SetScript("OnLeave", function() removeTex:SetTextColor(0.7, 0.2, 0.2) end)
        row.removeBtn = removeBtn

        row:Hide()
        f.rows[i] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PRIO_ROW_HEIGHT, function()
            BRutus:RefreshPrioModal()
        end)
    end)

    -- Bottom bar
    local bottomBg = f:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottomBg:SetPoint("BOTTOMLEFT"); bottomBg:SetPoint("BOTTOMRIGHT"); bottomBg:SetHeight(44)
    bottomBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
    local bottomLine = UI:CreateAccentLine(f, 1)
    bottomLine:SetPoint("BOTTOMLEFT", 0, 44); bottomLine:SetPoint("BOTTOMRIGHT", 0, 44)

    local saveBtn = UI:CreateButton(f, L["Save and Sync"], 130, 26)
    saveBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    saveBtn:SetScript("OnClick", function()
        if not f.prioData or not f.currentItemId then
            f.statusText:SetText(L["|cffFF4444No item loaded.|r"])
            return
        end
        if not BRutus.db.lootPrios then BRutus.db.lootPrios = {} end
        local prioList = {}
        for order, entry in ipairs(f.prioData) do
            table.insert(prioList, {
                name  = entry.name,
                class = entry.class,
                order = order,
            })
        end
        BRutus.db.lootPrios[f.currentItemId] = prioList
        if BRutus.Wishlist then
            BRutus.Wishlist:BroadcastLootPrios()
        end
        f.statusText:SetText(L["|cff4CFF4CSaved and sent!|r"])
        BRutus:Print(L["[Prio] Priorities saved and synced."])
    end)

    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", saveBtn, "BOTTOMLEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    -- Help text in bottom bar
    local bottomHelp = UI:CreateText(f, L["Reorder with the arrows. Only you see this before saving."], 9, 0.4, 0.4, 0.5)
    bottomHelp:SetPoint("BOTTOMLEFT", 10, 14)

    -- Wire up LoadItem
    LoadItem = function()
        local itemId = f.prioSearchItemId
        f.prioSearchItemId = nil
        if not itemId then
            local text = strtrim(searchBox:GetText() or "")
            if text == "" then return end
            itemId = tonumber(text:match("item:(%d+)")) or tonumber(text)
        end
        if not itemId then
            f.statusText:SetText(L["|cffFF4444Invalid item.|r"])
            return
        end

        f.currentItemId = itemId
        f.prioData = {}

        -- Collect who has this item on their wishlist
        local wishEntries = {}
        if BRutus.db.guildWishlists then
            for _, charData in pairs(BRutus.db.guildWishlists) do
                for _, wItem in ipairs(charData.wishlist or {}) do
                    if wItem.itemId == itemId then
                        table.insert(wishEntries, {
                            name         = charData.name or "",
                            class        = charData.class or "",
                            wishlistOrder = wItem.order or 999,
                        })
                        break
                    end
                end
            end
        end

        -- Start from saved prios (if any), then append remaining wishlist members
        local savedPrios = BRutus.db.lootPrios and BRutus.db.lootPrios[itemId]
        if savedPrios and #savedPrios > 0 then
            local inPrio = {}
            for _, pEntry in ipairs(savedPrios) do
                local wlOrd = 999
                for _, we in ipairs(wishEntries) do
                    if strlower(we.name) == strlower(pEntry.name or "") then
                        wlOrd = we.wishlistOrder
                        break
                    end
                end
                table.insert(f.prioData, {
                    name         = pEntry.name or "",
                    class        = pEntry.class or "",
                    wishlistOrder = wlOrd,
                })
                inPrio[strlower(pEntry.name or "")] = true
            end
            table.sort(wishEntries, function(a, b) return a.wishlistOrder < b.wishlistOrder end)
            for _, we in ipairs(wishEntries) do
                if not inPrio[strlower(we.name)] then
                    table.insert(f.prioData, we)
                end
            end
        else
            table.sort(wishEntries, function(a, b) return a.wishlistOrder < b.wishlistOrder end)
            f.prioData = wishEntries
        end

        local itemName = GetItemInfo(itemId) or (L["Item #"] .. itemId)
        f.statusText:SetText("|cffFFD700" .. itemName .. "|r  " .. format(L["%d interested"], #f.prioData))
        subtitleText:SetText(itemName)
        BRutus:RefreshPrioModal()
    end

    loadBtn:SetScript("OnClick", function()
        prioDropdown:Hide()
        LoadItem()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        prioDropdown:Hide()
        LoadItem()
        self:ClearFocus()
    end)

    BRutus.PrioModal = f
    return f
end

function BRutus:ShowPrioModal()
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Only officers can manage priorities.|r"])
        return
    end
    if not self.PrioModal then BuildPrioModal() end
    self:RefreshPrioModal()
    self.PrioModal:Show()
end

function BRutus:RefreshPrioModal()
    local f = self.PrioModal
    if not f or not f.prioData then return end

    local data   = f.prioData
    local total  = #data
    local offset = FauxScrollFrame_GetOffset(f.scrollFrame)
    FauxScrollFrame_Update(f.scrollFrame, total, PRIO_VISIBLE, PRIO_ROW_HEIGHT)

    for i = 1, PRIO_VISIBLE do
        local row     = f.rows[i]
        local dataIdx = offset + i

        if dataIdx <= total then
            local entry = data[dataIdx]
            local bgColor = (i % 2 == 0) and C.row2 or C.row1
            row.defaultBg = bgColor
            row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

            -- Prio position number
            row.prioOrderText:SetText("#" .. dataIdx)

            -- Character name (class-colored)
            local cr, cg, cb = BRutus:GetClassColor(entry.class or "")
            row.nameText:SetText(entry.name or "?")
            row.nameText:SetTextColor(cr, cg, cb)

            -- Wishlist order
            if entry.wishlistOrder and entry.wishlistOrder < 999 then
                row.wlOrderText:SetText("#" .. entry.wishlistOrder)
                row.wlOrderText:SetTextColor(0.3, 0.7, 1.0)
            else
                row.wlOrderText:SetText("-")
                row.wlOrderText:SetTextColor(0.4, 0.4, 0.4)
            end

            -- Wire ↑/↓
            row.upBtn:SetScript("OnClick", function()
                if dataIdx > 1 then
                    data[dataIdx], data[dataIdx - 1] = data[dataIdx - 1], data[dataIdx]
                    BRutus:RefreshPrioModal()
                end
            end)
            row.downBtn:SetScript("OnClick", function()
                if dataIdx < total then
                    data[dataIdx], data[dataIdx + 1] = data[dataIdx + 1], data[dataIdx]
                    BRutus:RefreshPrioModal()
                end
            end)

            -- Remove
            row.removeBtn:SetScript("OnClick", function()
                table.remove(data, dataIdx)
                BRutus:RefreshPrioModal()
            end)

            row:Show()
        else
            row:Hide()
        end
    end
end
