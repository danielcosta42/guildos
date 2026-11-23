----------------------------------------------------------------------
-- Guild OS - Alliance panel
-- The Alliance tab: who is federated with us, how fresh their data is, and the
-- officer controls for the pact. Two sub-tabs: Overview and Manage.
--
-- Rule 10: no business logic here. Everything is rendered from
-- Alliance:Summary() / Alliance:CanAdminister(); actions call module methods.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local ROW_H = 22
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 80    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab

-- Wrapped hint texts whose width has to follow the panel rather than the
-- fixed 460px they used to assume. Collected per CreateAlliancePanel call
-- (the builder runs once per container), so the expanded-mode tab and the
-- floating window never fight over one shared list.
local flexHints = nil
local function addFlexHint(fs)
    if flexHints then flexHints[#flexHints + 1] = fs end
end

local function ALLY() return GuildOS.Alliance end

-- Explicit Show/Hide instead of SetShown: everywhere else in this codebase
-- SetShown is only ever called on Frames, and these groups mix in FontStrings
-- and Textures. Show/Hide is defined on every region, so this cannot surprise.
local function setShown(widget, cond)
    if cond then widget:Show() else widget:Hide() end
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

-- The shared field (#371). Its own Escape, focus and hint handlers are hooks, so callers may set
-- OnEnterPressed but hook anything else.
local function makeInput(parent, width, opts)
    return UI:CreateInput(parent, width, 24, opts)
end

-- A colour token as the hex an inline |c code takes: secondary text inside a line keeps the palette
-- instead of a hard-coded grey (#371).
local function hex(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- Room over a later section title for the rule UI:CreateSectionTitle draws 12px above it, and the
-- height a title takes with the gap under it (#371).
local SECTION_ABOVE, TITLE_H = 20, 24

-- A scroll frame filling `holder` and reaching UI.SCROLL_GUTTER past its right edge: the child stops
-- that gutter short (BindScrollChildWidth), so the content ends where the screen's other lines do and
-- the bar sits in the margin, not over the content (#371).
local function fillScroll(scroll, content)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", UI.SCROLL_GUTTER, 0)
    UI:BindScrollChildWidth(scroll, content)
end

----------------------------------------------------------------------
-- Overview: the header band, the allied guild table, the blocked list.
----------------------------------------------------------------------
local function BuildOverview(panel)
    local empty = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, 0)
    empty:SetPoint("RIGHT", 0, 0)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)

    -- The alliance is the screen's first section (#371): the shared title, no gold and no gold rule.
    local title = UI:CreateSectionTitle(panel, "", true)
    title:SetPoint("TOPLEFT", 0, 0)

    local status = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    status:SetPoint("TOPLEFT", 0, -22)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -36 - UI.GAP)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    -- CreateScrollFrame does NOT anchor the scroll frame; without this the
    -- content is clipped to 0x0 and renders as nothing, with no error.
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceOverviewScroll")
    fillScroll(scroll, content)

    -- A later section's title inside the list, with the room its rule needs above it.
    local function sectionTitle(text, y)
        y = y + SECTION_ABOVE
        local fs = UI:CreateSectionTitle(content, text)
        fs:SetPoint("TOPLEFT", 0, -y)
        return y + TITLE_H
    end

    local function refresh()
        local ally = ALLY()
        local summary = ally and ally:Summary()

        clear(content)

        if not summary then
            title:Hide()
            status:Hide()
            empty:Show()
            empty:SetText(GuildOS:IsOfficer()
                and L["This guild is not in an alliance yet. Use the Manage tab to join or found one."]
                or L["This guild is not in an alliance yet."])
            return
        end

        empty:Hide()
        title:Show()
        status:Show()

        -- The name takes the width it needs; the tag and the size follow it as secondary text (#371).
        title:SetText(string.format("%s  |cff%s[%s]  %s|r",
            summary.name, hex(C.label), summary.tag,
            string.format(L["%d guilds, %d members"], #summary.guilds, summary.members)))

        local bridgeText = summary.bridge or L["nobody online"]
        if summary.amBridge then
            bridgeText = bridgeText .. " " .. L["(you)"]
        end
        local chanText = summary.connected and L["connected"] or L["not connected"]
        status:SetText(string.format("%s  \194\183  %s %s",
            string.format(L["Bridge: %s"], bridgeText),
            summary.channel or "?", chanText))

        local y = 0

        ------------------------------------------------------------------
        -- Schedule conflicts. Only rendered when there is something to say,
        -- so a healthy week costs no vertical space at all.
        ------------------------------------------------------------------
        local cal = GuildOS.Calendar
        local conflicts = (cal and cal.AllianceConflicts and cal:AllianceConflicts()) or {}
        if #conflicts > 0 then
            y = sectionTitle(string.format(L["SCHEDULE CONFLICTS (%d)"], #conflicts), y)

            for i = 1, math.min(#conflicts, 6) do
                local c = conflicts[i]
                local mins = math.floor((c.gap or 0) / 60)
                local gapText = mins >= 60
                    and string.format(L["%dh%02d apart"], math.floor(mins / 60), mins % 60)
                    or string.format(L["%dmin apart"], mins)
                local head = UI:CreateText(content, string.format(
                    "%s  %s  |cff%sx|r  %s  |cff%s%s  %s|r",
                    GuildOS:LocalDate("%a %H:%M", c.mine.when), c.mine.title or "?",
                    hex(C.label), c.theirs.title or "?", hex(C.label), c.theirs.guild or "?", gapText),
                    11, C.text.r, C.text.g, C.text.b)
                -- Held by both sides of the list, not sized from its width (#371).
                head:SetPoint("TOPLEFT", 0, -y)
                head:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                head:SetJustifyH("LEFT")
                head:SetWordWrap(false)
                y = y + 15

                local detail
                if c.sharedCount > 0 then
                    detail = string.format(L["%d signed up for both: %s"],
                        c.sharedCount, table.concat(c.shared, ", "))
                else
                    detail = L["nobody in common"]
                end
                local sub = UI:CreateText(content, detail, 10,
                    c.sharedCount > 0 and C.red.r or C.textDim.r,
                    c.sharedCount > 0 and C.red.g or C.textDim.g,
                    c.sharedCount > 0 and C.red.b or C.textDim.b)
                sub:SetPoint("TOPLEFT", 8, -y)
                sub:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                sub:SetJustifyH("LEFT")
                sub:SetWordWrap(false)
                y = y + 17
            end
            y = y + UI.GAP
        end

        ------------------------------------------------------------------
        -- Allied guilds: the shared table header (#371), its labels flush with the rows' text.
        ------------------------------------------------------------------
        local COLS = {
            { label = L["GUILD"],       x = 0 },
            { label = L["SEEN"],        x = 200 },
            { label = L["AMBASSADORS"], x = 274 },
            { label = L["LAST SYNC"],   x = 478 },
        }
        local header = UI:CreateTableHeader(content)
        header:SetPoint("TOPLEFT", 0, -y)
        header:SetPoint("TOPRIGHT", 0, -y)
        for _, col in ipairs(COLS) do
            local fs = UI:CreateHeaderText(header, col.label, 10)
            fs:SetPoint("LEFT", col.x, 0)
            fs:SetJustifyH("LEFT")
        end
        y = y + 22

        for i, g in ipairs(summary.guilds) do
            local row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local rc = (i % 2 == 0) and C.row2 or C.row1
            bg:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)

            -- Filled marker when the mesh can see somebody from that guild,
            -- hollow when it cannot. Data never vanishes; it just ages.
            local live = g.seen > 0
            local mark = UI:CreateText(row, live and "*" or "o", 12,
                live and C.online.r or C.offline.r,
                live and C.online.g or C.offline.g,
                live and C.online.b or C.offline.b)
            mark:SetPoint("LEFT", 0, 0)

            local label = g.name
            if g.isOwner then label = label .. " " .. L["(owner)"] end
            if g.isMine then label = label .. " " .. L["(you)"] end
            local nameFs = UI:CreateText(row, label, 11, C.text.r, C.text.g, C.text.b)
            nameFs:SetPoint("LEFT", 12, 0)
            nameFs:SetWidth(184)
            nameFs:SetJustifyH("LEFT")

            local seenFs = UI:CreateText(row, string.format("%d/%d", g.seen, g.members), 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            seenFs:SetPoint("LEFT", 200, 0)

            local amb = table.concat(g.ambassadors, ", ")
            local ambFs = UI:CreateText(row, amb, 11, C.textDim.r, C.textDim.g, C.textDim.b)
            ambFs:SetPoint("LEFT", 274, 0)
            ambFs:SetWidth(200)
            ambFs:SetJustifyH("LEFT")
            ambFs:SetWordWrap(false)

            local age = g.ts and GuildOS:TimeAgo(g.ts) or L["never"]
            local ageFs = UI:CreateText(row, age, 11, C.textDim.r, C.textDim.g, C.textDim.b)
            ageFs:SetPoint("LEFT", 478, 0)

            row:EnableMouse(true)
            row:SetScript("OnEnter", function()
                bg:SetColorTexture(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(g.name)
                GameTooltip:AddLine(string.format(
                    L["Seen: %d of %d known members are visible on the presence mesh."],
                    g.seen, g.members), 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(L["Only players running Guild OS are counted, so this is a floor, not the real online count."],
                    0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                bg:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)
                GameTooltip:Hide()
            end)

            y = y + ROW_H
        end

        -- Upcoming events published by allied guilds, with a slot request.
        local events = (cal and cal.AllianceEvents and cal:AllianceEvents()) or {}
        if #events > 0 then
            y = sectionTitle(L["UPCOMING ALLIANCE EVENTS"], y)

            for i = 1, math.min(#events, 8) do
                local ev = events[i]
                local size = tonumber(ev.size) or GuildOS.Client.defaultRaidSize   -- from another guild
                local full = (ev.yes or 0) >= size
                local when = GuildOS:LocalDate("%a %H:%M", ev.when)
                local fs = UI:CreateText(content, string.format("%s  %s  |cff%s%s  %d/%d|r",
                    when, ev.title or "?", hex(C.label), ev.guild or "?", ev.yes or 0, size),
                    11, C.text.r, C.text.g, C.text.b)
                fs:SetPoint("TOPLEFT", 0, -y)
                fs:SetPoint("RIGHT", content, "RIGHT", -190, 0)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(false)

                if full then
                    local fullFs = UI:CreateText(content, L["full"], 10,
                        C.textDim.r, C.textDim.g, C.textDim.b)
                    fullFs:SetPoint("TOPRIGHT", 0, -y)
                else
                    local roleBtn = UI:CreateButton(content, L["DPS"], 56, 18)
                    roleBtn.role = "DPS"
                    local askBtn = UI:CreateButton(content, L["Request slot"], 100, 18)
                    askBtn:SetPoint("TOPRIGHT", 0, -y + 2)
                    roleBtn:SetPoint("RIGHT", askBtn, "LEFT", -6, 0)
                    roleBtn:SetScript("OnClick", function()
                        local order = { TANK = "HEALER", HEALER = "DPS", DPS = "TANK" }
                        roleBtn.role = order[roleBtn.role] or "DPS"
                        roleBtn.label:SetText(({ TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] })[roleBtn.role])
                    end)
                    askBtn:SetScript("OnClick", function()
                        local ok, err = GuildOS.Calendar:RequestAllianceSlot(
                            ev.id, ev.guild, roleBtn.role, "")
                        if ok then
                            GuildOS:Print(string.format(L["Slot requested from %s."], ev.guild))
                        elseif err then
                            GuildOS:Print(err)
                        end
                    end)
                end
                y = y + ROW_H
            end
        end

        if #summary.blocked > 0 then
            y = y + UI.GAP
            local fs = UI:CreateText(content,
                string.format(L["Blocked: %s"], table.concat(summary.blocked, ", ")),
                11, C.red.r, C.red.g, C.red.b)
            fs:SetPoint("TOPLEFT", 0, -y)
            y = y + ROW_H
        end

        content:SetHeight(math.max(y, 1))
    end

    return refresh
end

----------------------------------------------------------------------
-- Ally card: everything the alliance already knows about one character.
-- One reusable frame, re-anchored per click. Reads Alliance:SpeakerInfo, which
-- normalises allied and own-guild data into a single shape.
----------------------------------------------------------------------
local allyCard

local function ensureAllyCard()
    if allyCard then return allyCard end

    local f = CreateFrame("Frame", "GuildOSAllyCard", UIParent, "BackdropTemplate")
    f:SetSize(260, 200)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f),
    })
    -- A floating card is elevation 4: popup surface, lineHi border.
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetPoint("TOPLEFT")
    f.accent:SetPoint("TOPRIGHT")
    f.accent:SetHeight(2)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("TOPLEFT", 12, -12)

    f.name = UI:CreateText(f, "", 14, C.text.r, C.text.g, C.text.b)
    f.name:SetPoint("TOPLEFT", 50, -12)
    f.guild = UI:CreateText(f, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    f.guild:SetPoint("TOPLEFT", 50, -28)
    f.sub = UI:CreateText(f, "", 11, C.silver.r, C.silver.g, C.silver.b)
    f.sub:SetPoint("TOPLEFT", 12, -50)

    f.close = UI:CreateCloseButton(f)
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.body = UI:CreateText(f, "", 11, C.text.r, C.text.g, C.text.b)
    f.body:SetPoint("TOPLEFT", 12, -70)
    f.body:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetWordWrap(true)

    f.whisper = UI:CreateButton(f, L["Whisper"], 76, 22)
    f.whisper:SetPoint("BOTTOMLEFT", 12, 10)
    f.invite = UI:CreateButton(f, L["Invite"], 76, 22)
    f.invite:SetPoint("LEFT", f.whisper, "RIGHT", 6, 0)
    f.sheet = UI:CreateButton(f, L["Full sheet"], 82, 22)
    f.sheet:SetPoint("LEFT", f.invite, "RIGHT", 6, 0)

    -- Ban only. Kick was pointless here: the join watchdog puts the player
    -- back inside 20 seconds, so it promised something it could not deliver.
    -- A ban is refused by the server on rejoin, which is what actually holds.
    f.ban = UI:CreateButton(f, L["Ban from channel"], 118, 22)
    f.ban:SetPoint("BOTTOMLEFT", 12, 38)

    tinsert(UISpecialFrames, "GuildOSAllyCard")   -- ESC closes it
    allyCard = f
    return f
end

function GuildOS:ShowAllyCard(name, guild, anchor)
    local f = ensureAllyCard()
    local ally = GuildOS.Alliance
    local info = (ally and ally:SpeakerInfo(name)) or {}
    local cr, cg, cb = GuildOS:GetClassColor(info.class)

    f.accent:SetColorTexture(cr, cg, cb, 0.9)
    f.name:SetText(name or "?")
    f.name:SetTextColor(cr, cg, cb)
    f.guild:SetText(info.guild or guild or "")

    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[info.class]
    if coords then
        f.icon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
        f.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        f.icon:Show()
    else
        f.icon:Hide()
    end

    local bits = {}
    if info.level then bits[#bits + 1] = tostring(info.level) end
    if info.class then bits[#bits + 1] = info.class end
    if info.spec then bits[#bits + 1] = info.spec end
    f.sub:SetText(table.concat(bits, "  \194\183  "))

    local lines = {}
    if info.main then
        lines[#lines + 1] = string.format(L["Alt of %s"], info.main)
    end
    if info.professions and #info.professions > 0 then
        local profs = {}
        for _, p in ipairs(info.professions) do
            profs[#profs + 1] = string.format("%s %d", L[p.n or "?"], p.r or 0)
        end
        -- A block's name in `label`, not a gold of its own (#371).
        lines[#lines + 1] = "|cff" .. hex(C.label) .. L["Professions"] .. "|r\n  " .. table.concat(profs, "\n  ")
    end
    if info.attunements and #info.attunements > 0 then
        lines[#lines + 1] = "|cff" .. hex(C.label) .. L["Attunements"] .. "|r\n  " ..
            table.concat(info.attunements, ", ")
    end
    if #lines == 0 then
        -- Be explicit rather than showing an empty card: for an ally we only
        -- ever know what their guild published.
        lines[#lines + 1] = "|cff" .. hex(C.textSoft) .. L["Nothing synced for this character yet."] .. "|r"
    end
    f.body:SetText(table.concat(lines, "\n\n"))

    f.whisper:SetScript("OnClick", function() ChatFrame_SendTell(name) end)
    f.invite:SetScript("OnClick", function() GuildOS.Compat.InviteUnit(name) end)

    -- The full member sheet only exists for our OWN guild: an ally's gear and
    -- history are simply not data we hold.
    setShown(f.sheet, info.own == true)
    if info.own then
        f.sheet:SetScript("OnClick", function()
            -- MemberDetail needs the merged roster view, not the raw synced
            -- entry: rank and classDisplay only exist on the live roster.
            local record = GuildOS:GetMemberRecord(name)
            if record and GuildOS.ShowMemberDetail then
                f:Hide()
                GuildOS:ShowMemberDetail(record)
            else
                GuildOS:Print(L["Could not load that character's sheet."])
            end
        end)
    end

    -- Moderating your own guildmates through a channel kick is the wrong tool:
    -- that is a guild matter, not an alliance one.
    local chat = GuildOS.AllianceChat
    local canModerate = ally and ally:CanAdminister() and info.own ~= true
        and chat and chat:CanModerate()
    setShown(f.ban, canModerate)
    if canModerate then
        f.ban:SetScript("OnClick", function()
            GuildOS:ShowDialog("GUILDOS_ALLY_BAN",
                string.format(L["Ban %s from the alliance channel? They cannot rejoin until unbanned."], name),
                nil, { name = name })
        end)
    end

    local extra = canModerate and 30 or 0
    f:SetHeight(math.max(150, 96 + (f.body:GetStringHeight() or 0) + 44 + extra))
    f:ClearAllPoints()
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 8)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
end

----------------------------------------------------------------------
-- Chat: the alliance feed. Conversation and alliance events on one timeline,
-- which is the one thing a default chat tab cannot do.
----------------------------------------------------------------------
local function BuildChat(panel)
    local CHAT = function() return GuildOS.AllianceChat end

    -- The status and the toggles share the screen's first line, flush with its edges (#371).
    local status = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("LEFT", panel, "TOPLEFT", 0, -10)

    local sysBtn = UI:CreateButton(panel, L["Events"], 90, 20)
    sysBtn:SetPoint("TOPRIGHT", 0, 0)
    local hideBtn = UI:CreateButton(panel, L["Default chat"], 120, 20)
    hideBtn:SetPoint("RIGHT", sysBtn, "LEFT", -6, 0)
    local clearBtn = UI:CreateButton(panel, L["Clear"], 70, 20)
    clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -6, 0)
    -- The allied guilds' /g in our guild chat (issue #344).
    local gchatBtn = UI:CreateButton(panel, L["Allied /g"], 120, 20)
    gchatBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(20 + UI.GAP))
    holder:SetPoint("BOTTOMRIGHT", 0, 24 + UI.GAP)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceChatScroll")
    fillScroll(scroll, content)

    local input = makeInput(panel, 100)
    input:SetPoint("BOTTOMLEFT", 0, 0)
    input:SetPoint("BOTTOMRIGHT", -(62 + UI.GAP), 0)
    local sendBtn = UI:CreateButton(panel, L["Send"], 62, 24)
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 0)

    local empty = UI:CreateText(content, L["Nothing here yet. Say hello."], 11,
        C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:Hide()

    -- Blocks are POOLED. Refresh runs on every incoming message and WoW never
    -- frees a frame, so building widgets per refresh leaked for the whole
    -- session. Created on demand, parked when the log shrinks.
    local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
    local blocks = {}
    -- Declared BEFORE getBlock: the hide button closes over it, and a later
    -- declaration would leave that closure pointing at a nil global.
    local refresh

    local function getBlock(i)
        if blocks[i] then return blocks[i] end

        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card),
        })

        -- Left accent bar in the speaker's class colour. This is the "bubble":
        -- WHITE8x8 cannot round a corner without shipping an art asset, so the
        -- card reads as a card through the bar and the hairline border instead.
        local accent = card:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT", 0, 0)
        accent:SetPoint("BOTTOMLEFT", 0, 0)
        accent:SetWidth(3)

        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 10, -7)

        local nameFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        nameFS:SetPoint("TOPLEFT", 38, -7)
        nameFS:SetJustifyH("LEFT")

        local timeFS = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        timeFS:SetPoint("TOPRIGHT", -8, -8)

        local bodyFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", 38, -22)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)

        -- Only the icon and the name open the card: clicking the message text
        -- itself would fire every time somebody tries to select text.
        local hit = CreateFrame("Button", nil, card)
        hit:SetPoint("TOPLEFT", 8, -5)
        hit:SetSize(200, 22)
        -- Hovered, the name lights to `text` (#371): gold marks selection, not a link.
        hit:SetScript("OnEnter", function(self)
            if self.name then
                nameFS:SetTextColor(C.text.r, C.text.g, C.text.b)
            end
        end)
        hit:SetScript("OnLeave", function()
            local col = blocks[i] and blocks[i].nameColor
            if col then nameFS:SetTextColor(col[1], col[2], col[3]) end
        end)
        hit:SetScript("OnClick", function(self)
            if self.name and GuildOS.ShowAllyCard then
                GuildOS:ShowAllyCard(self.name, self.guild, self)
            end
        end)

        local hide = CreateFrame("Button", nil, card)
        hide:SetSize(16, 16)
        hide:SetPoint("TOPRIGHT", -4, -4)
        hide.fs = hide:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(hide.fs, 12)
        hide.fs:SetPoint("CENTER")
        hide.fs:SetText("\195\151")
        hide.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        hide:SetScript("OnEnter", function(self)
            self.fs:SetTextColor(C.red.r, C.red.g, C.red.b)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Hide from the alliance feed"])
            GameTooltip:AddLine(L["The message was already delivered; this only clears it from the Guild OS feed."],
                0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        hide:SetScript("OnLeave", function(self)
            self.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
            GameTooltip:Hide()
        end)
        hide:SetScript("OnClick", function(self)
            local ok, err = GuildOS.AllianceChat:HideMessage(self.who, self.text)
            if not ok and err then GuildOS:Print(err) end
            refresh()
        end)

        blocks[i] = {
            card = card, accent = accent, icon = icon,
            nameFS = nameFS, timeFS = timeFS, bodyFS = bodyFS, hit = hit,
            hide = hide, classTex = CLASS_TEX,
        }
        return blocks[i]
    end

    -- refresh is declared above, next to the block pool.

    local function doSend()
        local chat = CHAT()
        if not chat then return end
        -- Enter and click are hardware events, which is what makes a channel
        -- send legal here at all (see Modules/RecruitmentSystem.lua).
        if chat:Send(input:GetText()) then
            input:SetText("")
        else
            GuildOS:Print(L["Not connected to the alliance channel."])
        end
        refresh()
    end
    sendBtn:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", doSend)

    clearBtn:SetScript("OnClick", function()
        if CHAT() then CHAT():Clear() end
        refresh()
    end)
    sysBtn:SetScript("OnClick", function()
        local p = CHAT() and CHAT():Prefs()
        if p then p.system = not p.system end
        refresh()
    end)
    hideBtn:SetScript("OnClick", function()
        local p = CHAT() and CHAT():Prefs()
        if p then p.hideDefault = not p.hideDefault end
        refresh()
    end)
    gchatBtn:SetScript("OnClick", function()
        local p = CHAT() and CHAT():Prefs()
        if p then p.guildBridge = not p.guildBridge end
        refresh()
    end)

    refresh = function()
        local chat = CHAT()
        if not chat then return end
        chat:MarkRead()
        -- The child's width is kept by BindScrollChildWidth (fillScroll), gutter included (#371).
        -- No clear() here: the rows are pooled, so this refresh shows exactly
        -- the ones it needs and parks the rest at the end.

        local prefs = chat:Prefs()
        sysBtn.label:SetText(prefs.system and L["Events: on"] or L["Events: off"])
        hideBtn.label:SetText(prefs.hideDefault and L["Default chat: hidden"] or L["Default chat: shown"])
        gchatBtn.label:SetText(prefs.guildBridge and L["Allied /g: shown"] or L["Allied /g: hidden"])
        status:SetText(chat:IsConnected()
            and string.format(L["%s connected"], chat:ChannelName() or "?")
            or (chat:Prefs().chat and L["connecting..."] or L["not connected"]))

        local rawLog = chat:Log()
        local hidden = chat:HiddenSet()
        local log = {}
        for _, e in ipairs(rawLog) do
            if e.sys or not hidden[GuildOS.AllianceChat.HiddenKey(e.n, e.m)] then
                log[#log + 1] = e
            end
        end
        local groups = GuildOS.AllianceChat.GroupLog(log, GuildOS.AllianceChat.GROUP_WINDOW)
        local canHide = GuildOS.Alliance and GuildOS.Alliance:CanAdminister()
        local myGuild = GuildOS.Alliance and GuildOS.Alliance:MyGuildName()
        -- The wrap width of a message: refresh runs only while the tab is shown, so the child's
        -- width is real; the cards themselves hang by both sides (#371).
        local width = math.max(content:GetWidth(), 200)
        local y = 0

        for i, g in ipairs(groups) do
            local b = getBlock(i)
            local stamp = g.t and date("%H:%M", g.t) or ""

            if g.sys then
                -- Events stand apart: no card, no speaker, a line in `label`, or `warn` for a warning.
                -- No marker in front of it (#371).
                local col = hex((g.sys == "warn") and C.warn or C.label)
                b.card:SetBackdropColor(0, 0, 0, 0)
                b.card:SetBackdropBorderColor(0, 0, 0, 0)
                b.accent:Hide()
                b.icon:Hide()
                b.nameFS:Hide()
                b.hit:Hide()
                b.hide:Hide()
                b.timeFS:SetText(stamp)
                b.bodyFS:SetPoint("TOPLEFT", 0, -4)
                b.bodyFS:SetWidth(width - 60)
                b.bodyFS:SetText(string.format("|cff%s%s|r", col, g.lines[1] or ""))
                local h = math.max(18, (b.bodyFS:GetStringHeight() or 12) + 8)
                b.card:ClearAllPoints()
                b.card:SetPoint("TOPLEFT", 0, -y)
                b.card:SetPoint("TOPRIGHT", 0, -y)
                b.card:SetHeight(h)
                b.card:Show()
                y = y + h + 2
            else
                local info = GuildOS.Alliance and GuildOS.Alliance:SpeakerInfo(g.name)
                local cr, cg, cb = GuildOS:GetClassColor(info and info.class)
                local own = (g.guild == myGuild)

                b.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, own and 0.35 or 0.55)
                b.card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)
                -- The rail is the GUILD's colour, matching the bulletin, so one
                -- colour means one guild everywhere in this panel. Class still
                -- reads off the icon and the name, which is where you look for
                -- it anyway.
                local gr, gg, gb = GuildOS.Alliance.GuildColor(g.guild)
                b.accent:SetColorTexture(gr, gg, gb, 0.95)
                b.accent:Show()

                local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[info and info.class]
                if coords then
                    b.icon:SetTexture(b.classTex)
                    b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    b.icon:Show()
                else
                    b.icon:Hide()
                end

                -- The guild tag stays dim for our own guild: in an alliance
                -- channel the signal worth reading is WHICH ALLY is speaking.
                b.nameFS:SetText(string.format("%s  |cff%s[%s]|r",
                    g.name or "?", hex(own and C.labelDim or C.info), g.guild or "?"))
                b.nameFS:SetTextColor(cr, cg, cb)
                b.nameColor = { cr, cg, cb }
                b.nameFS:Show()

                b.timeFS:SetText(stamp)
                b.bodyFS:SetPoint("TOPLEFT", 38, -22)
                b.bodyFS:SetWidth(width - 46)
                b.bodyFS:SetText(table.concat(g.lines, "\n"))

                local h = math.max(34, (b.bodyFS:GetStringHeight() or 12) + 28)
                b.card:ClearAllPoints()
                b.card:SetPoint("TOPLEFT", 0, -y)
                b.card:SetPoint("TOPRIGHT", 0, -y)
                b.card:SetHeight(h)
                b.card:Show()

                b.hit.name = g.name
                b.hit.guild = g.guild
                b.hit:Show()

                -- Hides the whole block's text, which is what the ambassador
                -- clicked on: a run of lines from one speaker reads as one
                -- message and pulling half of it would look like a glitch.
                b.hide.who = g.name
                b.hide.text = table.concat(g.lines, "\n")
                setShown(b.hide, canHide)
                y = y + h + 3
            end
        end

        -- Park every pooled block the log no longer needs.
        for i = #groups + 1, #blocks do
            blocks[i].card:Hide()
        end

        if #log == 0 then
            empty:SetPoint("TOPLEFT", 0, 0)
            empty:Show()
            y = 20
        else
            empty:Hide()
        end
        content:SetHeight(math.max(y, 1))
        -- Deferred one frame: the scroll range is recomputed after the content
        -- height lands, so scrolling to the bottom in this frame would clamp
        -- against the OLD range and leave the newest line off screen.
        local target = math.max(0, y - holder:GetHeight())
        GuildOS.Compat.After(0, function()
            if panel:IsVisible() then scroll:SetVerticalScroll(target) end
        end)
    end

    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:OnRefresh(function()
            if panel:IsVisible() then refresh() end
        end)
    end

    return refresh
end

----------------------------------------------------------------------
-- Bulletin: notices posted by any ambassador in the alliance.
----------------------------------------------------------------------
local function BuildBulletin(panel)
    ------------------------------------------------------------------
    -- Identity band. This board is the face of the alliance, so it opens
    -- with who the alliance IS: its name, as the screen's first section
    -- title, and its size. The name is held across the line up to the
    -- size, so a long one is never cut short by a width of its own, and it
    -- is the shared title in `text`, not gold caps (#371). The colour chips
    -- that stood under it went: unlabelled, they named nobody; each
    -- notice still carries its guild's colour.
    ------------------------------------------------------------------
    local count = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    count:SetPoint("TOPRIGHT", 0, -3)
    local title = UI:CreateSectionTitle(panel, "", true)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("RIGHT", count, "LEFT", -UI.GAP, 0)
    title:SetWordWrap(false)

    local box = makeInput(panel, 100, { placeholder = L["Write a notice for the alliance"] })
    box:SetPoint("TOPLEFT", 0, -(18 + UI.GAP))
    box:SetPoint("RIGHT", panel, "RIGHT", -(88 + UI.GAP), 0)
    box:SetHeight(26)

    local postBtn = UI:CreateButton(panel, L["Post"], 88, 26)
    postBtn:SetPoint("TOPRIGHT", 0, -(18 + UI.GAP))

    local hint = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", 0, -(18 + UI.GAP + 26 + 4))

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(18 + UI.GAP + 26 + 4 + 14 + UI.GAP))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceBoardScroll")
    fillScroll(scroll, content)

    local empty = UI:CreateText(content, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:Hide()

    local refresh

    -- Notice cards, pooled: WoW never frees a frame.
    local cards = {}
    local function getCard(i)
        if cards[i] then return cards[i] end
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card),
        })
        card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)

        local rail = card:CreateTexture(nil, "ARTWORK")
        rail:SetPoint("TOPLEFT", 0, 0)
        rail:SetPoint("BOTTOMLEFT", 0, 0)
        rail:SetWidth(3)

        -- Eyebrow: who said it, institutionally. Small and uppercase in the
        -- guild colour, so it reads as a stamp rather than as body text.
        local who = UI:CreateText(card, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        who:SetPoint("TOPLEFT", 14, -8)
        who:SetJustifyH("LEFT")

        local when = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        when:SetPoint("TOPRIGHT", -26, -9)

        -- The notice is the biggest thing on the card. It is the only part
        -- anyone opened this tab to read.
        local body = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        body:SetPoint("TOPLEFT", 14, -24)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)

        local del = CreateFrame("Button", nil, card)
        del:SetSize(18, 18)
        del:SetPoint("TOPRIGHT", -5, -5)
        del.fs = del:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(del.fs, 13)
        del.fs:SetPoint("CENTER")
        del.fs:SetText("\195\151")
        del.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        del:SetScript("OnEnter", function() del.fs:SetTextColor(C.red.r, C.red.g, C.red.b) end)
        del:SetScript("OnLeave", function() del.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b) end)
        del:SetScript("OnClick", function(self)
            local ok, err = ALLY():RemoveBoardPost(self.postId)
            if not ok and err then GuildOS:Print(err) end
            refresh()
        end)

        cards[i] = { card = card, rail = rail, who = who, when = when, body = body, del = del }
        return cards[i]
    end

    postBtn:SetScript("OnClick", function()
        local ok, err = ALLY():PostBoard(box:GetText())
        if ok then
            box:SetText("")
        elseif err then
            GuildOS:Print(err)
        end
        refresh()
    end)
    box:SetScript("OnEnterPressed", function() postBtn:Click() end)

    refresh = function()
        local ally = ALLY()
        local Ally = GuildOS.Alliance

        local summary = ally and ally:Summary()
        title:SetText((summary and summary.name) or "")
        count:SetText(summary
            and string.format(L["%d guilds, %d members"], #summary.guilds, summary.members) or "")

        local canPost = ally and ally:CanAdminister()
        setShown(box, canPost)
        setShown(postBtn, canPost)
        hint:SetText(canPost and L["Ambassadors can post. Everyone in the alliance sees it."]
            or L["Only alliance ambassadors can post here."])

        local posts = (ally and ally.BoardPosts and ally:BoardPosts()) or {}
        local mine = ally and ally:MyGuildName()
        -- The wrap width of a notice; the cards hang by both sides of the list (#371).
        local width = math.max(content:GetWidth(), 200)
        local y = 0

        for i, p in ipairs(posts) do
            local c = getCard(i)
            local r, g, b = Ally.GuildColor(p.guild)

            c.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.5)
            c.rail:SetColorTexture(r, g, b, 0.95)

            c.who:SetText(string.format("|cff%s%s|r  \194\183  %s",
                Ally.GuildColorHex(p.guild), (p.guild or "?"):upper(), p.by or "?"))
            c.when:SetText(p.ts and GuildOS:TimeAgo(p.ts) or "")

            c.body:SetWidth(width - 40)
            c.body:SetText(p.text or "")

            -- Only your own guild's notices can be pulled, and only by an
            -- ambassador: the same independence rule as the rest of the pact.
            c.del.postId = p.id
            setShown(c.del, canPost and p.guild == mine)

            local h = math.max(46, (c.body:GetStringHeight() or 12) + 34)
            c.card:ClearAllPoints()
            c.card:SetPoint("TOPLEFT", 0, -y)
            c.card:SetPoint("TOPRIGHT", 0, -y)
            c.card:SetHeight(h)
            c.card:Show()
            y = y + h + UI.GAP
        end

        for i = #posts + 1, #cards do cards[i].card:Hide() end

        if #posts == 0 then
            -- An empty board is an invitation, not a status report.
            empty:SetText(canPost and L["Nothing here yet. Welcome the allied guilds."]
                or L["Nothing here yet."])
            empty:SetPoint("TOPLEFT", 0, 0)
            empty:Show()
            y = 24
        else
            empty:Hide()
        end
        content:SetHeight(math.max(y, 1))
    end

    return refresh
end

----------------------------------------------------------------------
-- Manage: found, invite, block, remove, leave, and the channel toggle.
----------------------------------------------------------------------
local function BuildManage(panel)
    local notOfficer = UI:CreateText(panel, L["Only officers can manage the alliance."],
        12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    notOfficer:SetPoint("TOPLEFT", 0, 0)

    -- A scrolling body: with the section titles' spacing (#371) an ambassador's view runs past a
    -- 620px window, and the window clips what does not fit. The layouts below set its height.
    local bodyScroll, body = UI:CreateScrollFrame(panel, nil)
    bodyScroll:SetPoint("TOPLEFT", 0, 0)
    bodyScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:BindScrollChildWidth(bodyScroll, body)

    -- Each block opens with the shared section title (#371): the first of a view has no rule, every
    -- later one a 1px rule above it, which is a region of `body`, shown and hidden with its title.
    local function sectionTitle(text, first)
        return UI:CreateSectionTitle(body, text, first)
    end

    ------------------------------------------------------------------
    -- No pact yet. JOINING comes first and is one field: almost every guild
    -- joins, exactly one founds.
    ------------------------------------------------------------------
    local joinHdr = sectionTitle(L["Join an alliance"], true)
    local joinBox = makeInput(body, 100)
    local joinBtn = UI:CreateButton(body, L["Join"], 90, 24)
    local joinHint = UI:CreateText(body, L["Paste the invite an ambassador gave you."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- Fallback, shown ONLY after a join failed to find anybody. The mesh
    -- normally supplies the contact, so asking up front would be friction
    -- charged to everyone to cover a minority case. A warning, so `warn`.
    local joinWarn = UI:CreateText(body, "", 10, C.warn.r, C.warn.g, C.warn.b)
    addFlexHint(joinWarn)
    joinWarn:SetJustifyH("LEFT")
    joinWarn:SetWordWrap(true)
    local contactBox = makeInput(body, 200)
    local contactBtn = UI:CreateButton(body, L["Try with this name"], 140, 24)
    contactBtn:SetPoint("LEFT", contactBox, "RIGHT", 8, 0)

    -- /gos ally request: no invite in hand, ask an officer of a guild already in the alliance (#142).
    local reqHdr = sectionTitle(L["Ask to join an alliance"])
    local reqTagBox = makeInput(body, 110)
    local reqWhoBox = makeInput(body, 200)
    reqWhoBox:SetPoint("LEFT", reqTagBox, "RIGHT", 8, 0)
    local reqBtn = UI:CreateButton(body, L["Send request"], 120, 24)
    reqBtn:SetPoint("LEFT", reqWhoBox, "RIGHT", 8, 0)
    local reqHint = UI:CreateText(body, L["Alliance tag and an officer of a guild already in it. They approve the request."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- The rule over this title is the line that used to stand alone between joining and founding.
    local foundHdr = sectionTitle(L["Found an alliance"])
    local tagBox = makeInput(body, 110)
    local nameBox = makeInput(body, 240)
    nameBox:SetPoint("LEFT", tagBox, "RIGHT", 8, 0)
    local foundBtn = UI:CreateButton(body, L["Create"], 90, 24)
    foundBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    local foundHint = UI:CreateText(body, L["Tag (letters and numbers) and a display name."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- Invite / block, shown once a pact exists.
    local inviteHdr = sectionTitle(L["Invite a guild"], true)
    inviteHdr:SetPoint("TOPLEFT", 0, 0)
    local inviteBox = makeInput(body, 200)
    inviteBox:SetPoint("TOPLEFT", 0, -TITLE_H)
    local inviteBtn = UI:CreateButton(body, L["Invite"], 90, 24)
    inviteBtn:SetPoint("LEFT", inviteBox, "RIGHT", UI.GAP, 0)
    local inviteHint = UI:CreateText(body,
        L["Name any officer of that guild. They get a prompt and must accept."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    inviteHint:SetPoint("TOPLEFT", 0, -(TITLE_H + 24 + 6))

    ------------------------------------------------------------------
    -- Ambassadors. Rows are POOLED (created once, shown/hidden), because
    -- WoW never frees a frame: rebuilding them per refresh would leak.
    ------------------------------------------------------------------
    local ambHdr = sectionTitle(L["Ambassadors of this guild"])
    local ambRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(360, 20)
        row.name = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
        row.name:SetPoint("LEFT", 0, 0)
        row.name:SetWidth(250)
        row.name:SetJustifyH("LEFT")
        row.del = UI:CreateButton(row, L["Remove"], 80, 18)
        row.del:SetPoint("LEFT", 264, 0)
        row:Hide()
        ambRows[i] = row
    end
    local ambBox = makeInput(body, 200)
    local ambAddBtn = UI:CreateButton(body, L["Add"], 90, 24)
    ambAddBtn:SetPoint("LEFT", ambBox, "RIGHT", 8, 0)
    local ambHint = UI:CreateText(body,
        L["Ambassadors speak for the guild: they invite, approve slots and post."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    -- Vacancy state: shown instead of the list when the guild lost them all.
    local ambWarn = UI:CreateText(body, "", 11, C.red.r, C.red.g, C.red.b)
    addFlexHint(ambWarn)
    ambWarn:SetJustifyH("LEFT")
    ambWarn:SetWordWrap(true)
    local ambClaimBtn = UI:CreateButton(body, L["Claim ambassador"], 170, 24)

    -- Join code. Shown ONLY to ambassadors: it is stored on every member's
    -- client (they all have to validate it) so this is a deterrent against
    -- casual sharing rather than real secrecy, and the hint says as much.
    local codeHdr = sectionTitle(L["Join code"])
    local codeBox = makeInput(body, 140)
    codeBox:SetAutoFocus(false)
    codeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local codeNewBtn = UI:CreateButton(body, L["New code"], 100, 24)
    codeNewBtn:SetPoint("LEFT", codeBox, "RIGHT", 8, 0)
    local codeHint = UI:CreateText(body,
        L["A guild with this code joins without anyone having to approve. Anyone in the alliance can be the contact."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    addFlexHint(codeHint)
    codeHint:SetJustifyH("LEFT")
    codeHint:SetWordWrap(true)

    local blockHdr = sectionTitle(L["Ignore a guild locally"])
    local blockBox = makeInput(body, 200)
    local blockBtn = UI:CreateButton(body, L["Block"], 90, 24)
    blockBtn:SetPoint("LEFT", blockBox, "RIGHT", 8, 0)
    local unblockBtn = UI:CreateButton(body, L["Unblock"], 90, 24)
    unblockBtn:SetPoint("LEFT", blockBtn, "RIGHT", 6, 0)
    local blockHint = UI:CreateText(body,
        L["Only affects you. The pact is untouched and nobody is told."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    local removeHdr = sectionTitle(L["Remove a guild from the pact"])
    local removeBox = makeInput(body, 200)
    local removeBtn = UI:CreateButton(body, L["Remove"], 90, 24)
    removeBtn:SetPoint("LEFT", removeBox, "RIGHT", 8, 0)
    local removeHint = UI:CreateText(body, L["Only the founding guild can do this."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- The channel and leaving have no title of their own: a rule closes the block above them.
    local chatRule = UI:CreateSeparator(body)
    local chatBtn = UI:CreateButton(body, L["Alliance chat"], 150, 24)
    local chatHint = UI:CreateText(body,
        L["A custom channel is public: anyone who guesses the name can join. Keep secrets out of it."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    addFlexHint(chatHint)
    chatHint:SetJustifyH("LEFT")
    chatHint:SetWordWrap(true)

    -- Channel ownership goes to whoever joined first, which is usually not an
    -- ambassador, so the people who need to moderate cannot. This hands it over
    -- in one action. Only the owner can, so it hides for everyone else.
    local modBtn = UI:CreateButton(body, L["Give ambassadors channel moderation"], 250, 24)
    modBtn:SetScript("OnClick", function()
        local n = GuildOS.AllianceChat and GuildOS.AllianceChat:PromoteAmbassadors() or 0
        if n > 0 then
            GuildOS:Print(string.format(L["Asked the server to promote %d ambassador(s)."], n))
        else
            GuildOS:Print(L["Only the channel owner can do that."])
        end
    end)

    local leaveBtn = UI:CreateButton(body, L["Leave the alliance"], 170, 24)

    -- A later section title's rule is its own region: it goes in the group with its title.
    local foundGroup  = { joinHdr, joinBox, joinBtn, joinHint,
                          foundHdr, foundHdr.rule, tagBox, nameBox, foundBtn, foundHint,
                          reqHdr, reqHdr.rule, reqTagBox, reqWhoBox, reqBtn, reqHint }
    -- Set by a join that could not find anybody on the mesh.
    local needContact = false
    local memberGroup = { inviteHdr, inviteBox, inviteBtn, inviteHint, ambHdr, ambHdr.rule,
                          blockHdr, blockHdr.rule, blockBox, blockBtn, unblockBtn, blockHint,
                          removeHdr, removeHdr.rule, removeBox, removeBtn, removeHint,
                          chatRule, chatBtn, chatHint, modBtn, leaveBtn,
                          codeHdr, codeHdr.rule, codeBox, codeNewBtn, codeHint }

    local function say(ok, err)
        if not ok and err then GuildOS:Print(err) end
    end

    local refresh   -- forward declaration so handlers can re-render

    -- The no-pact side also runs on an offset, because the contact fallback
    -- appears and disappears between renders.
    -- Flush with the screen's left edge, a title's field TITLE_H under it, and SECTION_ABOVE over every
    -- later title for its rule (#371). HINT_H: a one-line hint and the gap under it.
    local HINT_H = 14
    local function layoutJoin()
        local y = 0
        joinHdr:SetPoint("TOPLEFT", 0, -y);   y = y + TITLE_H
        joinBox:SetPoint("TOPLEFT", 0, -y)
        joinBox:SetPoint("RIGHT", body, "RIGHT", -(90 + UI.GAP), 0)
        joinBtn:SetPoint("TOPRIGHT", 0, -y);  y = y + 30
        joinHint:SetPoint("TOPLEFT", 0, -y);  y = y + HINT_H
        if needContact then
            y = y + UI.GAP
            joinWarn:SetPoint("TOPLEFT", 0, -y);   y = y + 30
            contactBox:SetPoint("TOPLEFT", 0, -y); y = y + 24
        end
        y = y + SECTION_ABOVE
        reqHdr:SetPoint("TOPLEFT", 0, -y);     y = y + TITLE_H
        reqTagBox:SetPoint("TOPLEFT", 0, -y);  y = y + 30
        reqHint:SetPoint("TOPLEFT", 0, -y);    y = y + HINT_H + SECTION_ABOVE
        foundHdr:SetPoint("TOPLEFT", 0, -y);   y = y + TITLE_H
        tagBox:SetPoint("TOPLEFT", 0, -y);     y = y + 30
        foundHint:SetPoint("TOPLEFT", 0, -y);  y = y + HINT_H
        body:SetHeight(y + UI.GAP)
    end

    -- Everything under the invite block is laid out with a running offset,
    -- because the ambassador list grows and shrinks. Fixed offsets would either
    -- overlap or leave a hole.
    local function layout(ambCount, vacancy, showCode)
        local y = TITLE_H + 30 + HINT_H + SECTION_ABOVE
        ambHdr:SetPoint("TOPLEFT", 0, -y)
        y = y + TITLE_H
        for i, row in ipairs(ambRows) do
            if i <= ambCount then
                row:SetPoint("TOPLEFT", 0, -y)
                y = y + 20
            end
        end
        if vacancy then
            ambWarn:SetPoint("TOPLEFT", 0, -y)
            y = y + 32
            ambClaimBtn:SetPoint("TOPLEFT", 0, -y)
            y = y + 24
        else
            ambBox:SetPoint("TOPLEFT", 0, -(y + 4))
            y = y + 34
            ambHint:SetPoint("TOPLEFT", 0, -y)
            y = y + HINT_H
        end

        -- The join code is for ambassadors only: hidden, it leaves no hole.
        if showCode then
            y = y + SECTION_ABOVE
            codeHdr:SetPoint("TOPLEFT", 0, -y);     y = y + TITLE_H
            codeBox:SetPoint("TOPLEFT", 0, -y);     y = y + 28
            codeHint:SetPoint("TOPLEFT", 0, -y);    y = y + 26
        end
        y = y + SECTION_ABOVE
        blockHdr:SetPoint("TOPLEFT", 0, -y);    y = y + TITLE_H
        blockBox:SetPoint("TOPLEFT", 0, -y);    y = y + 28
        blockHint:SetPoint("TOPLEFT", 0, -y);   y = y + HINT_H + SECTION_ABOVE
        removeHdr:SetPoint("TOPLEFT", 0, -y);   y = y + TITLE_H
        removeBox:SetPoint("TOPLEFT", 0, -y);   y = y + 28
        removeHint:SetPoint("TOPLEFT", 0, -y);  y = y + HINT_H + SECTION_ABOVE
        chatRule:SetPoint("TOPLEFT", 0, -(y - 12))
        chatRule:SetPoint("TOPRIGHT", 0, -(y - 12))
        chatBtn:SetPoint("TOPLEFT", 0, -y);     y = y + 28
        chatHint:SetPoint("TOPLEFT", 0, -y);    y = y + 30
        modBtn:SetPoint("TOPLEFT", 0, -y);      y = y + 30
        leaveBtn:SetPoint("TOPLEFT", 0, -y);    y = y + 24
        body:SetHeight(y + UI.GAP)
    end

    ambAddBtn:SetScript("OnClick", function()
        local who = ambBox:GetText()
        local ok, err = ALLY():AddAmbassador(who)
        say(ok, err)
        if ok then
            GuildOS:Print(string.format(L["%s is now an ambassador."], who))
            ambBox:SetText("")
        end
        refresh()
    end)

    codeNewBtn:SetScript("OnClick", function()
        local ok, res = ALLY():RegenerateCode()
        if ok then
            GuildOS:Print(string.format(L["New join code: %s"], res))
        elseif res then
            GuildOS:Print(res)
        end
        refresh()
    end)

    ambClaimBtn:SetScript("OnClick", function()
        local ok, err = ALLY():ClaimAmbassador()
        say(ok, err)
        if ok then GuildOS:Print(L["You are now an ambassador of this guild."]) end
        refresh()
    end)

    local function tryJoin(contact)
        local ok, err, marker = ALLY():JoinWithToken(joinBox:GetText(), contact)
        if ok then
            GuildOS:Print(L["Join sent. If somebody from that alliance is online you are in."])
            joinBox:SetText("")
            contactBox:SetText("")
            needContact = false
        else
            needContact = (marker == "needContact")
            if needContact then
                joinWarn:SetText(L["Nobody from that alliance is visible right now. Name anyone in it and try again."])
            end
            if err then GuildOS:Print(err) end
        end
        refresh()
    end

    joinBtn:SetScript("OnClick", function() tryJoin(nil) end)
    joinBox:SetScript("OnEnterPressed", function() joinBtn:Click() end)
    contactBtn:SetScript("OnClick", function() tryJoin(contactBox:GetText()) end)
    reqBtn:SetScript("OnClick", function()
        local who = strtrim(reqWhoBox:GetText() or "")
        local ok, err = ALLY():RequestJoin(reqTagBox:GetText(), who)
        say(ok, err)
        if ok then GuildOS:Print(string.format(L["Join request sent to %s."], who)) end
    end)
    contactBox:SetScript("OnEnterPressed", function() contactBtn:Click() end)

    foundBtn:SetScript("OnClick", function()
        local ok, err = ALLY():Create(tagBox:GetText(), nameBox:GetText())
        say(ok, err)
        if ok then
            tagBox:SetText("")
            nameBox:SetText("")
            if GuildOS.AllianceChat then GuildOS.AllianceChat:Join() end
        end
        refresh()
    end)

    inviteBtn:SetScript("OnClick", function()
        local target = inviteBox:GetText()
        local ok, err = ALLY():Invite(target)
        say(ok, err)
        if ok then
            GuildOS:Print(string.format(L["Invite sent to %s."], target))
            inviteBox:SetText("")
        end
        refresh()
    end)

    blockBtn:SetScript("OnClick", function()
        say(ALLY():Block(blockBox:GetText()))
        blockBox:SetText("")
        refresh()
    end)

    unblockBtn:SetScript("OnClick", function()
        say(ALLY():Unblock(blockBox:GetText()))
        blockBox:SetText("")
        refresh()
    end)

    removeBtn:SetScript("OnClick", function()
        local guild = removeBox:GetText()
        GuildOS:ShowDialog("GUILDOS_ALLY_REMOVE",
            string.format(L["Remove %s from the alliance?"], guild), nil,
            { guild = guild, after = function() removeBox:SetText(""); refresh() end })
    end)

    chatBtn:SetScript("OnClick", function()
        local chat = GuildOS.AllianceChat
        if not chat then return end
        chat:SetEnabled(not chat:Prefs().chat)
        refresh()
    end)

    leaveBtn:SetScript("OnClick", function()
        GuildOS:ShowDialog("GUILDOS_ALLY_LEAVE",
            L["Leave the alliance? Your guild stops sharing and stops receiving."], nil,
            { after = function() refresh() end })
    end)

    refresh = function()
        local ally = ALLY()
        local isOfficer = GuildOS:IsOfficer()
        setShown(notOfficer, not isOfficer)
        setShown(body, isOfficer)
        if not isOfficer then return end

        local hasPact = ally and ally:Get() ~= nil
        for _, w in ipairs(foundGroup) do setShown(w, not hasPact) end
        for _, w in ipairs(memberGroup) do setShown(w, hasPact) end
        if not hasPact then
            for _, row in ipairs(ambRows) do row:Hide() end
            ambBox:Hide(); ambAddBtn:Hide(); ambHint:Hide()
            ambWarn:Hide(); ambClaimBtn:Hide()
            setShown(joinWarn, needContact)
            setShown(contactBox, needContact)
            setShown(contactBtn, needContact)
            layoutJoin()
            return
        end
        joinWarn:Hide(); contactBox:Hide(); contactBtn:Hide()

        ------------------------------------------------------------------
        -- Ambassadors
        ------------------------------------------------------------------
        local entry = ally:_MyEntry()
        local list = (entry and entry.ambassadors) or {}
        local me = (Ambiguate and Ambiguate(GuildOS.Compat.PlayerName() or "", "short")) or GuildOS.Compat.PlayerName()
        local vacancy = GuildOS.Alliance._CanClaimAmbassador(list, ally:_GuildRosterShortSet())
        local canEdit = ally:CanAdminister()

        for i, row in ipairs(ambRows) do
            local amb = list[i]
            if amb and not vacancy then
                local label = amb
                if amb:lower() == tostring(me):lower() then
                    label = label .. "  " .. L["(you)"]
                end
                row.name:SetText(label)
                -- Never offer to remove the last one: that would lock the guild
                -- out of its own pact, and the module refuses it anyway.
                setShown(row.del, canEdit and #list > 1)
                row.del:SetScript("OnClick", function()
                    local ok, err = ALLY():RemoveAmbassador(amb)
                    say(ok, err)
                    if ok then
                        GuildOS:Print(string.format(L["%s is no longer an ambassador."], amb))
                    end
                    refresh()
                end)
                row:Show()
            else
                row:Hide()
            end
        end

        setShown(ambWarn, vacancy)
        setShown(ambClaimBtn, vacancy)
        setShown(ambBox, not vacancy and canEdit)
        setShown(ambAddBtn, not vacancy and canEdit)
        setShown(ambHint, not vacancy)
        if vacancy then
            ambWarn:SetText(L["No ambassador of this guild is on the roster any more. Without one this guild cannot invite, approve slots or post."])
        end
        -- Ambassadors only. A plain officer manages the pact but does not
        -- get the code to hand around.
        local isAmb = ally:CanAdminister()
        layout(vacancy and 0 or #list, vacancy, isAmb)
        if not vacancy then
            ambAddBtn:SetPoint("LEFT", ambBox, "RIGHT", 8, 0)
        end

        -- Enable/Disable rather than SetEnabled: both exist on Button and
        -- EditBox in this client, these two are the ones guaranteed to.
        local isOwner = ally:Get().owner == ally:MyGuildName()
        if isOwner then
            removeBtn:Enable()
            removeBox:Enable()
        else
            removeBtn:Disable()
            removeBox:Disable()
        end

        for _, w in ipairs({ codeHdr, codeHdr.rule, codeBox, codeNewBtn, codeHint }) do
            setShown(w, isAmb)
        end
        if isAmb then
            codeBox:SetText(ally:JoinToken() or "")
            if ally:Get().owner == ally:MyGuildName() then
                codeNewBtn:Enable()
            else
                codeNewBtn:Disable()
            end
        end

        local chat = GuildOS.AllianceChat
        local on = chat and chat:Prefs().chat
        -- UI:CreateButton has no SetText; the label is a child FontString.
        chatBtn.label:SetText(on and L["Alliance chat: on"] or L["Alliance chat: off"])
    end

    return refresh
end

----------------------------------------------------------------------
-- Setup: the alliance code, the GreenWall way (issue #348). One code, the same
-- in every guild; an officer saves it and the guild hands it to every member.
----------------------------------------------------------------------
local function BuildSetup(panel)
    local LINK = function() return GuildOS.AllianceLink end

    -- The screen's first section title, then form labels in `text` over their fields (#371).
    local hdr = UI:CreateSectionTitle(panel, L["Alliance code"], true)
    hdr:SetPoint("TOPLEFT", 0, 0)
    local status = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    status:SetPoint("TOPLEFT", 0, -TITLE_H)
    status:SetJustifyH("LEFT")

    local tagLbl = UI:CreateText(panel, L["Tag (letters and numbers)"], 11)
    tagLbl:SetPoint("TOPLEFT", 0, -50)
    local tagBox = makeInput(panel, 110)
    tagBox:SetPoint("TOPLEFT", 0, -68)
    -- No list of guilds (issue #431): who holds the key is the alliance, and
    -- the guilds are learned by themselves.
    local genBtn = UI:CreateButton(panel, L["Generate"], 110, 24)
    genBtn:SetPoint("LEFT", tagBox, "RIGHT", UI.GAP, 0)

    local lineBox = makeInput(panel, 540)
    lineBox:SetPoint("TOPLEFT", 0, -(68 + 24 + UI.GAP + 4))
    lineBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local writeBtn = UI:CreateButton(panel, L["Save for the guild"], 170, 24)
    writeBtn:SetPoint("TOPLEFT", lineBox, "BOTTOMLEFT", 0, -UI.GAP)
    local removeBtn = UI:CreateButton(panel, L["Turn off for the guild"], 170, 24)
    removeBtn:SetPoint("LEFT", writeBtn, "RIGHT", UI.GAP, 0)

    local hint = UI:CreateText(panel, L["Paste this same code in Alliance > Setup in every guild of the alliance and save, once. It goes in the guild master's public note where the game allows it, and every member hands it on at login: no ambassadors, nobody in particular has to be online. The guilds find each other by themselves."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", writeBtn, "BOTTOMLEFT", 0, -UI.GAP)
    hint:SetWidth(540)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    addFlexHint(hint)

    local refresh
    local function say(ok, err)
        if not ok and err then GuildOS:Print(err) end
    end

    genBtn:SetScript("OnClick", function()
        local link = LINK()
        if not link then return end
        local tag = GuildOS.Alliance.NormalizeTag(tagBox:GetText())
        if tag == "" then
            GuildOS:Print(L["Name the alliance with a tag."])
            return
        end
        -- The same tag keeps its key, so the guilds already set need nothing new.
        local cfg = link:Config()
        local key = (cfg and cfg.tag == tag) and cfg.key or link.NewKey()
        lineBox:SetText(link.Build(tag, key))
        lineBox:HighlightText()
    end)
    writeBtn:SetScript("OnClick", function()
        local link = LINK()
        if not link then return end
        local ok, err = link:SetCode(strtrim(lineBox:GetText() or ""))
        say(ok, err)
        -- `err` is true when it went in the guild info too (issue #431).
        if ok and err == true then
            GuildOS:Print(L["Saved in the guild master's public note. Every member gets it at login, with nobody online."])
        elseif ok then
            GuildOS:Print(L["Saved. The guild gets it now."])
        end
        refresh()
    end)
    removeBtn:SetScript("OnClick", function()
        local link = LINK()
        if not link then return end
        say(link:SetCode(nil))
        refresh()
    end)

    refresh = function()
        local link = LINK()
        if not link then return end
        local cfg = link:Config()
        local mine = ALLY() and ALLY():MyGuildName()
        local pact = link:Pact()
        if pact and cfg and cfg.open then
            local n = 0
            for _ in pairs(pact.guilds) do n = n + 1 end
            status:SetText(string.format(L["Active: %s, %d guilds."], cfg.tag, n))
        elseif cfg and mine and cfg.guilds[mine] then
            status:SetText(string.format(L["Active: %s, %d guilds."], cfg.tag, #cfg.order))
        elseif cfg then
            status:SetText(L["The code does not name this guild."])
        else
            status:SetText(L["No alliance set up for this guild."])
        end
        local officer = GuildOS:IsOfficer()
        for _, w in ipairs({ tagLbl, tagBox, genBtn, lineBox, writeBtn, removeBtn, hint }) do
            setShown(w, officer)
        end
        if not officer then return end
        if not lineBox:HasFocus() then
            local line = link:Suggest()
            local parsed = line and link.Parse(line)
            lineBox:SetText(line or "")
            if parsed and tagBox:GetText() == "" then
                tagBox:SetText(parsed.tag)
            end
        end
        if link:Config() then removeBtn:Enable() else removeBtn:Disable() end
    end
    return refresh
end

----------------------------------------------------------------------
-- Confirmations
----------------------------------------------------------------------
local function registerPopups()
    if GuildOS.Dialogs["GUILDOS_ALLY_REMOVE"] then return end

    GuildOS.Dialogs["GUILDOS_ALLY_REMOVE"] = {
        text = "%s", button1 = L["Remove"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if not d then return end
            local ok, err = GuildOS.Alliance:RemoveGuild(d.guild)
            if not ok and err then GuildOS:Print(err) end
            if d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    GuildOS.Dialogs["GUILDOS_ALLY_BAN"] = {
        text = "%s", button1 = L["Ban"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if d and d.name and GuildOS.AllianceChat:Ban(d.name) then
                GuildOS:Print(string.format(L["Asked the server to ban %s from the channel."], d.name))
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    GuildOS.Dialogs["GUILDOS_ALLY_LEAVE"] = {
        text = "%s", button1 = L["Leave"], button2 = L["Cancel"],
        OnAccept = function(self)
            local ok, err = GuildOS.Alliance:Leave()
            if not ok and err then GuildOS:Print(err) end
            local d = self and self.data
            if d and d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

----------------------------------------------------------------------
-- Entry point, called from UI/RosterFrame.lua
----------------------------------------------------------------------
-- Bulletin first: it is the alliance's front page, the thing an allied leader
-- should land on. Bulletin and Chat need a pact to mean anything, so they hide
-- until there is one, and the panel opens on whichever tab is first VISIBLE.
local SUBTABS = {
    { key = "bulletin", label = L["Bulletin"], needsPact = true },
    { key = "chat",     label = L["Chat"],     needsPact = true },
    { key = "overview", label = L["Overview"] },
    { key = "setup",    label = L["Setup"] },
    { key = "manage",   label = L["Manage"] },
}

function GuildOS:CreateAlliancePanel(parent, _mainFrame)
    registerPopups()
    parent.subPanels = {}
    parent.activeSub = nil

    -- Left-anchored: UI:FlowBar reads GetWidth, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized.
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, 28)
    UI:StyleSubTabBar(bar)

    local btns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(btns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub

    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        btns[t.key] = btn
    end

    -- Flow the VISIBLE tabs only, so hiding Chat and Bulletin without a
    -- pact leaves no gap in the bar. UI:FlowBar wraps to a second row when
    -- the window is too narrow, and its returned height is what pushes the
    -- sub-panels down.
    local hasPactNow = false
    local function layoutTabs(hasPact)
        hasPactNow = hasPact
        local visible, first = {}, nil
        for _, t in ipairs(SUBTABS) do
            local btn = btns[t.key]
            local show = hasPact or not t.needsPact
            setShown(btn, show)
            if show then
                visible[#visible + 1] = btn
                first = first or t.key
            end
        end
        UI:FlowBar(bar, visible, { gap = 4, rowGap = 4, rowH = TAB_H })
        return first
    end

    -- Anchored to the bar, not a fixed offset, so a wrapped two-row tab
    -- bar pushes the content down instead of hiding behind it. Flush with the
    -- bar's left edge, UI.GAP under it, ending UI.GAP short of its right edge
    -- (the bar spans the parent less 10px a side), as every screen does (#371).
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -UI.GAP)
        p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(10 + UI.GAP), 10)
        p:Hide()
        return p
    end

    local builders = {
        chat = BuildChat, overview = BuildOverview,
        bulletin = BuildBulletin, manage = BuildManage, setup = BuildSetup,
    }
    flexHints = {}
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end
    -- Take this instance's list and close the collector, so a second
    -- container starts a fresh one.
    local myHints = flexHints
    flexHints = nil

    -- Unread count on the Chat tab, so a message that lands while you are on
    -- another tab is not silently missed.
    local function paintUnread()
        local chat = GuildOS.AllianceChat
        local n = (chat and chat.unread) or 0
        local btn = btns["chat"]
        if not btn then return end
        btn.label:SetText(n > 0 and string.format("%s (%d)", L["Chat"], n) or L["Chat"])
    end
    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:OnRefresh(function()
            if parent:IsVisible() then paintUnread() end
        end)
    end

    parent:SetScript("OnShow", function()
        local hasPact = GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil
        local first = layoutTabs(hasPact)
        local want = parent.activeSub
        -- Falling out of a pact must not strand the panel on a hidden tab, and
        -- the landing tab is simply the first visible one, so reordering
        -- SUBTABS is the only thing anyone has to change.
        if not want or not btns[want] or not btns[want]:IsShown() then
            want = first or "overview"
        end
        selectSub(want)
        paintUnread()
    end)

    ----------------------------------------------------------------
    -- Layout: the tab bar rewraps and the wrapped hint texts follow the
    -- panel instead of the fixed 460px they used to assume.
    ----------------------------------------------------------------
    UI:MakeResponsive(parent, function(_, w, _)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs(hasPactNow)
        local hintW = math.max(220, w - 90)
        for _, fs in ipairs(myHints) do fs:SetWidth(hintW) end
    end)
end
