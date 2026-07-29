----------------------------------------------------------------------
-- Guild OS - Alliance panel
-- The Alliance tab: who is federated with us, how fresh their data is, and the
-- officer controls for the pact. Two sub-tabs: Overview and Manage.
--
-- Rule 10: no business logic here. Everything is rendered from
-- Alliance:Summary() / Alliance:CanAdminister(); actions call module methods.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local ROW_H = 22

local function ALLY() return BRutus.Alliance end

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

local function makeInput(parent, width)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(width, 24)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 1)
    b:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    b:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    b:SetTextColor(C.text.r, C.text.g, C.text.b)
    b:SetTextInsets(6, 6, 0, 0)
    b:SetAutoFocus(false)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return b
end

----------------------------------------------------------------------
-- Overview: the header band, the allied guild table, the blocked list.
----------------------------------------------------------------------
local function BuildOverview(panel)
    local empty = UI:CreateText(panel, "", 12, C.textDim.r, C.textDim.g, C.textDim.b)
    empty:SetPoint("TOPLEFT", 4, -6)
    empty:SetPoint("RIGHT", -4, 0)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)

    local title = UI:CreateText(panel, "", 13, C.gold.r, C.gold.g, C.gold.b)
    title:SetPoint("TOPLEFT", 4, -6)

    local status = UI:CreateText(panel, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("TOPLEFT", 4, -26)

    local line = UI:CreateAccentLine(panel, 1)
    line:SetPoint("TOPLEFT", 0, -44)
    line:SetPoint("TOPRIGHT", 0, -44)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -50)
    holder:SetPoint("BOTTOMRIGHT", 0, 4)
    -- CreateScrollFrame does NOT anchor the scroll frame; without this the
    -- content is clipped to 0x0 and renders as nothing, with no error.
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceOverviewScroll")
    scroll:SetAllPoints()

    local function refresh()
        local ally = ALLY()
        local summary = ally and ally:Summary()

        content:SetWidth(math.max(holder:GetWidth() - 12, 1))
        clear(content)

        if not summary then
            title:Hide()
            status:Hide()
            line:Hide()
            empty:Show()
            empty:SetText(BRutus:IsOfficer()
                and L["This guild is not in an alliance yet. Use the Manage tab to found one."]
                or L["This guild is not in an alliance yet."])
            return
        end

        empty:Hide()
        title:Show()
        status:Show()
        line:Show()

        title:SetText(string.format("%s  |cff888888[%s]|r  %s",
            summary.name, summary.tag,
            string.format(L["%d guilds, %d members"], #summary.guilds, summary.members)))

        local bridgeText = summary.bridge or L["nobody online"]
        if summary.amBridge then
            bridgeText = bridgeText .. " " .. L["(you)"]
        end
        local chanText = summary.connected and L["connected"] or L["not connected"]
        status:SetText(string.format("%s  |cff555555.|r  %s %s",
            string.format(L["Bridge: %s"], bridgeText),
            summary.channel or "?", chanText))

        local y = 0

        ------------------------------------------------------------------
        -- Schedule conflicts. Only rendered when there is something to say,
        -- so a healthy week costs no vertical space at all.
        ------------------------------------------------------------------
        local cal = BRutus.Calendar
        local conflicts = (cal and cal.AllianceConflicts and cal:AllianceConflicts()) or {}
        if #conflicts > 0 then
            local hdr = UI:CreateText(content,
                string.format(L["SCHEDULE CONFLICTS (%d)"], #conflicts),
                10, C.gold.r, C.gold.g, C.gold.b)
            hdr:SetPoint("TOPLEFT", 6, -y)
            y = y + 16

            for i = 1, math.min(#conflicts, 6) do
                local c = conflicts[i]
                local mins = math.floor((c.gap or 0) / 60)
                local gapText = mins >= 60
                    and string.format(L["%dh%02d apart"], math.floor(mins / 60), mins % 60)
                    or string.format(L["%dmin apart"], mins)
                local head = UI:CreateText(content, string.format(
                    "%s  %s  |cff888888x|r  %s  |cff8888aa%s|r  |cff666666%s|r",
                    date("%a %H:%M", c.mine.when), c.mine.title or "?",
                    c.theirs.title or "?", c.theirs.guild or "?", gapText),
                    11, C.text.r, C.text.g, C.text.b)
                head:SetPoint("TOPLEFT", 10, -y)
                head:SetWidth(math.max(content:GetWidth() - 20, 200))
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
                sub:SetPoint("TOPLEFT", 18, -y)
                sub:SetWidth(math.max(content:GetWidth() - 28, 200))
                sub:SetJustifyH("LEFT")
                sub:SetWordWrap(false)
                y = y + 17
            end
            y = y + 10
        end

        ------------------------------------------------------------------
        -- Allied guilds
        ------------------------------------------------------------------
        local COLS = {
            { label = L["GUILD"],       x = 6 },
            { label = L["SEEN"],        x = 200 },
            { label = L["AMBASSADORS"], x = 274 },
            { label = L["LAST SYNC"],   x = 478 },
        }
        for _, col in ipairs(COLS) do
            local fs = UI:CreateHeaderText(content, col.label, 10)
            fs:SetPoint("TOPLEFT", col.x, -y)
            fs:SetJustifyH("LEFT")
        end
        y = y + 18

        for i, g in ipairs(summary.guilds) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(content:GetWidth() > 0 and content:GetWidth() or 600, ROW_H)
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
            mark:SetPoint("LEFT", 6, 0)

            local label = g.name
            if g.isOwner then label = label .. " " .. L["(owner)"] end
            if g.isMine then label = label .. " " .. L["(you)"] end
            local nameFs = UI:CreateText(row, label, 11, C.text.r, C.text.g, C.text.b)
            nameFs:SetPoint("LEFT", 18, 0)
            nameFs:SetWidth(178)
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

            local age = g.ts and BRutus:TimeAgo(g.ts) or L["never"]
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
            y = y + 10
            local hdr = UI:CreateText(content, L["UPCOMING ALLIANCE EVENTS"], 10,
                C.gold.r, C.gold.g, C.gold.b)
            hdr:SetPoint("TOPLEFT", 6, -y)
            y = y + 18

            for i = 1, math.min(#events, 8) do
                local ev = events[i]
                local full = (ev.yes or 0) >= (ev.size or 25)
                local when = date("%a %H:%M", ev.when)
                local fs = UI:CreateText(content, string.format("%s  %s  |cff888888%s  %d/%d|r",
                    when, ev.title or "?", ev.guild or "?", ev.yes or 0, ev.size or 25),
                    11, C.text.r, C.text.g, C.text.b)
                fs:SetPoint("TOPLEFT", 10, -y)
                fs:SetWidth(math.max(content:GetWidth() - 200, 200))
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(false)

                if full then
                    local fullFs = UI:CreateText(content, L["full"], 10,
                        C.textDim.r, C.textDim.g, C.textDim.b)
                    fullFs:SetPoint("TOPRIGHT", -6, -y)
                else
                    local roleBtn = UI:CreateButton(content, L["DPS"], 56, 18)
                    roleBtn.role = "DPS"
                    local askBtn = UI:CreateButton(content, L["Request slot"], 100, 18)
                    askBtn:SetPoint("TOPRIGHT", -6, -y + 2)
                    roleBtn:SetPoint("RIGHT", askBtn, "LEFT", -6, 0)
                    roleBtn:SetScript("OnClick", function()
                        local order = { TANK = "HEALER", HEALER = "DPS", DPS = "TANK" }
                        roleBtn.role = order[roleBtn.role] or "DPS"
                        roleBtn.label:SetText(L[roleBtn.role])
                    end)
                    askBtn:SetScript("OnClick", function()
                        local ok, err = BRutus.Calendar:RequestAllianceSlot(
                            ev.id, ev.guild, roleBtn.role, "")
                        if ok then
                            BRutus:Print(string.format(L["Slot requested from %s."], ev.guild))
                        elseif err then
                            BRutus:Print(err)
                        end
                    end)
                end
                y = y + ROW_H
            end
        end

        if #summary.blocked > 0 then
            y = y + 8
            local fs = UI:CreateText(content,
                string.format(L["Blocked: %s"], table.concat(summary.blocked, ", ")),
                11, C.red.r, C.red.g, C.red.b)
            fs:SetPoint("TOPLEFT", 6, -y)
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
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    })
    f:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.8)
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

    tinsert(UISpecialFrames, "GuildOSAllyCard")   -- ESC closes it
    allyCard = f
    return f
end

function BRutus:ShowAllyCard(name, guild, anchor)
    local f = ensureAllyCard()
    local ally = BRutus.Alliance
    local info = (ally and ally:SpeakerInfo(name)) or {}
    local cr, cg, cb = BRutus:GetClassColor(info.class)

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
            profs[#profs + 1] = string.format("%s %d", p.n or "?", p.r or 0)
        end
        lines[#lines + 1] = "|cffEDCC7B" .. L["Professions"] .. "|r\n  " .. table.concat(profs, "\n  ")
    end
    if info.attunements and #info.attunements > 0 then
        lines[#lines + 1] = "|cffEDCC7B" .. L["Attunements"] .. "|r\n  " ..
            table.concat(info.attunements, ", ")
    end
    if #lines == 0 then
        -- Be explicit rather than showing an empty card: for an ally we only
        -- ever know what their guild published.
        lines[#lines + 1] = "|cff888888" .. L["Nothing synced for this character yet."] .. "|r"
    end
    f.body:SetText(table.concat(lines, "\n\n"))

    f.whisper:SetScript("OnClick", function() ChatFrame_SendTell(name) end)
    f.invite:SetScript("OnClick", function() InviteUnit(name) end)

    -- The full member sheet only exists for our OWN guild: an ally's gear and
    -- history are simply not data we hold.
    setShown(f.sheet, info.own == true)
    if info.own then
        f.sheet:SetScript("OnClick", function()
            -- MemberDetail needs the merged roster view, not the raw synced
            -- entry: rank and classDisplay only exist on the live roster.
            local record = BRutus:GetMemberRecord(name)
            if record and BRutus.ShowMemberDetail then
                f:Hide()
                BRutus:ShowMemberDetail(record)
            else
                BRutus:Print(L["Could not load that character's sheet."])
            end
        end)
    end

    f:SetHeight(math.max(150, 96 + (f.body:GetStringHeight() or 0) + 44))
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
    local CHAT = function() return BRutus.AllianceChat end

    local status = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("TOPLEFT", 6, -6)

    local sysBtn = UI:CreateButton(panel, L["Events"], 90, 20)
    sysBtn:SetPoint("TOPRIGHT", -6, -2)
    local hideBtn = UI:CreateButton(panel, L["Default chat"], 120, 20)
    hideBtn:SetPoint("RIGHT", sysBtn, "LEFT", -6, 0)
    local clearBtn = UI:CreateButton(panel, L["Clear"], 70, 20)
    clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -6, 0)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -28)
    holder:SetPoint("BOTTOMRIGHT", 0, 32)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceChatScroll")
    scroll:SetAllPoints()

    local input = makeInput(panel, 100)
    input:SetPoint("BOTTOMLEFT", 6, 4)
    input:SetPoint("BOTTOMRIGHT", -74, 4)
    local sendBtn = UI:CreateButton(panel, L["Send"], 62, 24)
    sendBtn:SetPoint("BOTTOMRIGHT", -6, 4)

    local empty = UI:CreateText(content, L["Nothing here yet. Say hello."], 11,
        C.textDim.r, C.textDim.g, C.textDim.b)
    empty:Hide()

    -- Blocks are POOLED. Refresh runs on every incoming message and WoW never
    -- frees a frame, so building widgets per refresh leaked for the whole
    -- session. Created on demand, parked when the log shrinks.
    local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
    local blocks = {}

    local function getBlock(i)
        if blocks[i] then return blocks[i] end

        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
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
        hit:SetScript("OnEnter", function(self)
            if self.name then
                nameFS:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            end
        end)
        hit:SetScript("OnLeave", function()
            local col = blocks[i] and blocks[i].nameColor
            if col then nameFS:SetTextColor(col[1], col[2], col[3]) end
        end)
        hit:SetScript("OnClick", function(self)
            if self.name and BRutus.ShowAllyCard then
                BRutus:ShowAllyCard(self.name, self.guild, self)
            end
        end)

        blocks[i] = {
            card = card, accent = accent, icon = icon,
            nameFS = nameFS, timeFS = timeFS, bodyFS = bodyFS, hit = hit,
            classTex = CLASS_TEX,
        }
        return blocks[i]
    end

    local refresh

    local function doSend()
        local chat = CHAT()
        if not chat then return end
        -- Enter and click are hardware events, which is what makes a channel
        -- send legal here at all (see Modules/RecruitmentSystem.lua).
        if chat:Send(input:GetText()) then
            input:SetText("")
        else
            BRutus:Print(L["Not connected to the alliance channel."])
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

    refresh = function()
        local chat = CHAT()
        if not chat then return end
        chat:MarkRead()
        -- CreateScrollFrame sizes the child from the scroll frame AT CREATION,
        -- when nothing has been laid out yet, so it is born 0 wide and stays
        -- that way. Every working panel in this addon re-sets it here.
        content:SetWidth(math.max(holder:GetWidth() - 12, 1))
        -- No clear() here: the rows are pooled, so this refresh shows exactly
        -- the ones it needs and parks the rest at the end.

        local prefs = chat:Prefs()
        sysBtn.label:SetText(prefs.system and L["Events: on"] or L["Events: off"])
        hideBtn.label:SetText(prefs.hideDefault and L["Default chat: hidden"] or L["Default chat: shown"])
        status:SetText(chat:IsConnected()
            and string.format(L["%s connected"], chat:ChannelName() or "?")
            or L["not connected"])

        local log = chat:Log()
        local groups = BRutus.AllianceChat.GroupLog(log, BRutus.AllianceChat.GROUP_WINDOW)
        local myGuild = BRutus.Alliance and BRutus.Alliance:MyGuildName()
        local width = math.max(content:GetWidth() - 12, 200)
        local y = 0

        for i, g in ipairs(groups) do
            local b = getBlock(i)
            local stamp = g.t and date("%H:%M", g.t) or ""

            if g.sys then
                -- Events stand apart: no card, no speaker, just a marked line.
                local col = (g.sys == "warn") and "E0B040" or "8F7BD1"
                b.card:SetBackdropColor(0, 0, 0, 0)
                b.card:SetBackdropBorderColor(0, 0, 0, 0)
                b.accent:Hide()
                b.icon:Hide()
                b.nameFS:Hide()
                b.hit:Hide()
                b.timeFS:SetText(stamp)
                b.bodyFS:SetPoint("TOPLEFT", 12, -4)
                b.bodyFS:SetWidth(width - 60)
                b.bodyFS:SetText(string.format("|cff%s\194\187 %s|r", col, g.lines[1] or ""))
                local h = math.max(18, (b.bodyFS:GetStringHeight() or 12) + 8)
                b.card:SetPoint("TOPLEFT", 4, -y)
                b.card:SetSize(width, h)
                b.card:Show()
                y = y + h + 2
            else
                local info = BRutus.Alliance and BRutus.Alliance:SpeakerInfo(g.name)
                local cr, cg, cb = BRutus:GetClassColor(info and info.class)
                local own = (g.guild == myGuild)

                b.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, own and 0.35 or 0.55)
                b.card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)
                b.accent:SetColorTexture(cr, cg, cb, 0.9)
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
                    g.name or "?", own and "555566" or "8FA8C8", g.guild or "?"))
                b.nameFS:SetTextColor(cr, cg, cb)
                b.nameColor = { cr, cg, cb }
                b.nameFS:Show()

                b.timeFS:SetText(stamp)
                b.bodyFS:SetPoint("TOPLEFT", 38, -22)
                b.bodyFS:SetWidth(width - 46)
                b.bodyFS:SetText(table.concat(g.lines, "\n"))

                local h = math.max(34, (b.bodyFS:GetStringHeight() or 12) + 28)
                b.card:SetPoint("TOPLEFT", 4, -y)
                b.card:SetSize(width, h)
                b.card:Show()

                b.hit.name = g.name
                b.hit.guild = g.guild
                b.hit:Show()
                y = y + h + 3
            end
        end

        -- Park every pooled block the log no longer needs.
        for i = #groups + 1, #blocks do
            blocks[i].card:Hide()
        end

        if #log == 0 then
            empty:SetPoint("TOPLEFT", 6, 0)
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
        BRutus.Compat.After(0, function()
            if panel:IsVisible() then scroll:SetVerticalScroll(target) end
        end)
    end

    if BRutus.AllianceChat then
        BRutus.AllianceChat:OnRefresh(function()
            if panel:IsVisible() then refresh() end
        end)
    end

    return refresh
end

----------------------------------------------------------------------
-- Bulletin: notices posted by any ambassador in the alliance.
----------------------------------------------------------------------
local function BuildBulletin(panel)
    local box = makeInput(panel, 380)
    box:SetPoint("TOPLEFT", 6, -8)
    local postBtn = UI:CreateButton(panel, L["Post"], 80, 24)
    postBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
    local hint = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", 6, -36)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -54)
    holder:SetPoint("BOTTOMRIGHT", 0, 4)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceBoardScroll")
    scroll:SetAllPoints()

    local refresh

    postBtn:SetScript("OnClick", function()
        local ok, err = ALLY():PostBoard(box:GetText())
        if ok then
            box:SetText("")
        elseif err then
            BRutus:Print(err)
        end
        refresh()
    end)
    box:SetScript("OnEnterPressed", function() postBtn:Click() end)

    refresh = function()
        local ally = ALLY()
        content:SetWidth(math.max(holder:GetWidth() - 12, 1))
        clear(content)

        local canPost = ally and ally:CanAdminister()
        setShown(box, canPost)
        setShown(postBtn, canPost)
        hint:SetText(canPost and L["Ambassadors can post. Everyone in the alliance sees it."]
            or L["Only alliance ambassadors can post here."])

        local posts = (ally and ally.BoardPosts and ally:BoardPosts()) or {}
        local y = 0
        for _, p in ipairs(posts) do
            local head = UI:CreateText(content, string.format("|cff8888aa[%s]|r %s  |cff666666%s|r",
                p.guild or "?", p.by or "?", p.ts and BRutus:TimeAgo(p.ts) or ""),
                10, C.textDim.r, C.textDim.g, C.textDim.b)
            head:SetPoint("TOPLEFT", 6, -y)
            y = y + 14

            local body = UI:CreateText(content, p.text or "", 11, C.text.r, C.text.g, C.text.b)
            body:SetPoint("TOPLEFT", 10, -y)
            body:SetWidth(math.max(content:GetWidth() - 20, 200))
            body:SetJustifyH("LEFT")
            body:SetWordWrap(true)
            y = y + math.max(16, (body:GetStringHeight() or 12) + 8)
        end

        if #posts == 0 then
            local none = UI:CreateText(content, L["No alliance notices yet."], 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            none:SetPoint("TOPLEFT", 6, 0)
            y = 20
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
        12, C.textDim.r, C.textDim.g, C.textDim.b)
    notOfficer:SetPoint("TOPLEFT", 6, -8)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Found a new alliance (only shown when there is no pact).
    local foundHdr = UI:CreateHeaderText(body, L["Found an alliance"], 11)
    foundHdr:SetPoint("TOPLEFT", 6, -10)
    local tagBox = makeInput(body, 110)
    tagBox:SetPoint("TOPLEFT", 6, -30)
    local nameBox = makeInput(body, 240)
    nameBox:SetPoint("LEFT", tagBox, "RIGHT", 8, 0)
    local foundBtn = UI:CreateButton(body, L["Create"], 90, 24)
    foundBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    local foundHint = UI:CreateText(body, L["Tag (letters and numbers) and a display name."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    foundHint:SetPoint("TOPLEFT", 6, -58)

    -- Invite / block, shown once a pact exists.
    local inviteHdr = UI:CreateHeaderText(body, L["Invite a guild"], 11)
    inviteHdr:SetPoint("TOPLEFT", 6, -10)
    local inviteBox = makeInput(body, 200)
    inviteBox:SetPoint("TOPLEFT", 6, -30)
    local inviteBtn = UI:CreateButton(body, L["Invite"], 90, 24)
    inviteBtn:SetPoint("LEFT", inviteBox, "RIGHT", 8, 0)
    local inviteHint = UI:CreateText(body,
        L["Name any officer of that guild. They get a prompt and must accept."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    inviteHint:SetPoint("TOPLEFT", 6, -58)

    ------------------------------------------------------------------
    -- Ambassadors. Rows are POOLED (created once, shown/hidden), because
    -- WoW never frees a frame: rebuilding them per refresh would leak.
    ------------------------------------------------------------------
    local ambHdr = UI:CreateHeaderText(body, L["Ambassadors of this guild"], 11)
    local ambRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(360, 20)
        row.name = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
        row.name:SetPoint("LEFT", 6, 0)
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
    ambWarn:SetWidth(460)
    ambWarn:SetJustifyH("LEFT")
    ambWarn:SetWordWrap(true)
    local ambClaimBtn = UI:CreateButton(body, L["Claim ambassador"], 170, 24)

    local blockHdr = UI:CreateHeaderText(body, L["Ignore a guild locally"], 11)
    local blockBox = makeInput(body, 200)
    local blockBtn = UI:CreateButton(body, L["Block"], 90, 24)
    blockBtn:SetPoint("LEFT", blockBox, "RIGHT", 8, 0)
    local unblockBtn = UI:CreateButton(body, L["Unblock"], 90, 24)
    unblockBtn:SetPoint("LEFT", blockBtn, "RIGHT", 6, 0)
    local blockHint = UI:CreateText(body,
        L["Only affects you. The pact is untouched and nobody is told."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    local removeHdr = UI:CreateHeaderText(body, L["Remove a guild from the pact"], 11)
    local removeBox = makeInput(body, 200)
    local removeBtn = UI:CreateButton(body, L["Remove"], 90, 24)
    removeBtn:SetPoint("LEFT", removeBox, "RIGHT", 8, 0)
    local removeHint = UI:CreateText(body, L["Only the founding guild can do this."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    local chatBtn = UI:CreateButton(body, L["Alliance chat"], 150, 24)
    local chatHint = UI:CreateText(body,
        L["A custom channel is public: anyone who guesses the name can join. Keep secrets out of it."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    chatHint:SetWidth(460)
    chatHint:SetJustifyH("LEFT")
    chatHint:SetWordWrap(true)

    local leaveBtn = UI:CreateButton(body, L["Leave the alliance"], 170, 24)

    local foundGroup  = { foundHdr, tagBox, nameBox, foundBtn, foundHint }
    local memberGroup = { inviteHdr, inviteBox, inviteBtn, inviteHint, ambHdr,
                          blockHdr, blockBox, blockBtn, unblockBtn, blockHint,
                          removeHdr, removeBox, removeBtn, removeHint,
                          chatBtn, chatHint, leaveBtn }

    local function say(ok, err)
        if not ok and err then BRutus:Print(err) end
    end

    local refresh   -- forward declaration so handlers can re-render

    -- Everything under the invite block is laid out with a running offset,
    -- because the ambassador list grows and shrinks. Fixed offsets would either
    -- overlap or leave a hole.
    local function layout(ambCount, vacancy)
        local y = 86
        ambHdr:SetPoint("TOPLEFT", 6, -y)
        y = y + 20
        for i, row in ipairs(ambRows) do
            if i <= ambCount then
                row:SetPoint("TOPLEFT", 6, -y)
                y = y + 20
            end
        end
        if vacancy then
            ambWarn:SetPoint("TOPLEFT", 6, -y)
            y = y + 32
            ambClaimBtn:SetPoint("TOPLEFT", 6, -y)
            y = y + 30
        else
            ambBox:SetPoint("TOPLEFT", 6, -(y + 4))
            y = y + 34
            ambHint:SetPoint("TOPLEFT", 6, -y)
            y = y + 24
        end

        blockHdr:SetPoint("TOPLEFT", 6, -y);    y = y + 20
        blockBox:SetPoint("TOPLEFT", 6, -y);    y = y + 28
        blockHint:SetPoint("TOPLEFT", 6, -y);   y = y + 24
        removeHdr:SetPoint("TOPLEFT", 6, -y);   y = y + 20
        removeBox:SetPoint("TOPLEFT", 6, -y);   y = y + 28
        removeHint:SetPoint("TOPLEFT", 6, -y);  y = y + 26
        chatBtn:SetPoint("TOPLEFT", 6, -y);     y = y + 28
        chatHint:SetPoint("TOPLEFT", 6, -y);    y = y + 30
        leaveBtn:SetPoint("TOPLEFT", 6, -y)
    end

    ambAddBtn:SetScript("OnClick", function()
        local who = ambBox:GetText()
        local ok, err = ALLY():AddAmbassador(who)
        say(ok, err)
        if ok then
            BRutus:Print(string.format(L["%s is now an ambassador."], who))
            ambBox:SetText("")
        end
        refresh()
    end)

    ambClaimBtn:SetScript("OnClick", function()
        local ok, err = ALLY():ClaimAmbassador()
        say(ok, err)
        if ok then BRutus:Print(L["You are now an ambassador of this guild."]) end
        refresh()
    end)

    foundBtn:SetScript("OnClick", function()
        local ok, err = ALLY():Create(tagBox:GetText(), nameBox:GetText())
        say(ok, err)
        if ok then
            tagBox:SetText("")
            nameBox:SetText("")
            if BRutus.AllianceChat then BRutus.AllianceChat:Join() end
        end
        refresh()
    end)

    inviteBtn:SetScript("OnClick", function()
        local target = inviteBox:GetText()
        local ok, err = ALLY():Invite(target)
        say(ok, err)
        if ok then
            BRutus:Print(string.format(L["Invite sent to %s."], target))
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
        StaticPopup_Show("GUILDOS_ALLY_REMOVE",
            string.format(L["Remove %s from the alliance?"], guild), nil,
            { guild = guild, after = function() removeBox:SetText(""); refresh() end })
    end)

    chatBtn:SetScript("OnClick", function()
        local chat = BRutus.AllianceChat
        if not chat then return end
        chat:SetEnabled(not chat:Prefs().chat)
        refresh()
    end)

    leaveBtn:SetScript("OnClick", function()
        StaticPopup_Show("GUILDOS_ALLY_LEAVE",
            L["Leave the alliance? Your guild stops sharing and stops receiving."], nil,
            { after = function() refresh() end })
    end)

    refresh = function()
        local ally = ALLY()
        local isOfficer = BRutus:IsOfficer()
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
            return
        end

        ------------------------------------------------------------------
        -- Ambassadors
        ------------------------------------------------------------------
        local entry = ally:_MyEntry()
        local list = (entry and entry.ambassadors) or {}
        local me = (Ambiguate and Ambiguate(UnitName("player") or "", "short")) or UnitName("player")
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
                        BRutus:Print(string.format(L["%s is no longer an ambassador."], amb))
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
        layout(vacancy and 0 or #list, vacancy)
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

        local chat = BRutus.AllianceChat
        local on = chat and chat:Prefs().chat
        -- UI:CreateButton has no SetText; the label is a child FontString.
        chatBtn.label:SetText(on and L["Alliance chat: on"] or L["Alliance chat: off"])
    end

    return refresh
end

----------------------------------------------------------------------
-- Confirmations
----------------------------------------------------------------------
local function registerPopups()
    if StaticPopupDialogs["GUILDOS_ALLY_REMOVE"] then return end

    StaticPopupDialogs["GUILDOS_ALLY_REMOVE"] = {
        text = "%s", button1 = L["Remove"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if not d then return end
            local ok, err = BRutus.Alliance:RemoveGuild(d.guild)
            if not ok and err then BRutus:Print(err) end
            if d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["GUILDOS_ALLY_LEAVE"] = {
        text = "%s", button1 = L["Leave"], button2 = L["Cancel"],
        OnAccept = function(self)
            local ok, err = BRutus.Alliance:Leave()
            if not ok and err then BRutus:Print(err) end
            local d = self and self.data
            if d and d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

----------------------------------------------------------------------
-- Entry point, called from UI/RosterFrame.lua
----------------------------------------------------------------------
-- Chat first: it is the reason to open this panel day to day. Chat and
-- Bulletin need a pact to mean anything, so they hide until there is one.
local SUBTABS = {
    { key = "chat",     label = L["Chat"],     needsPact = true },
    { key = "overview", label = L["Overview"] },
    { key = "bulletin", label = L["Bulletin"], needsPact = true },
    { key = "manage",   label = L["Manage"] },
}

function BRutus:CreateAlliancePanel(parent, _mainFrame)
    registerPopups()
    parent.subPanels = {}
    parent.activeSub = nil

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetPoint("TOPRIGHT", -10, -8)
    bar:SetHeight(26)

    local btns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(btns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub

    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 120)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        btns[t.key] = btn
    end

    -- Re-anchor left to right over the VISIBLE tabs only, so hiding Chat and
    -- Bulletin without a pact leaves no gap in the bar.
    local function layoutTabs(hasPact)
        local x, first = 0, nil
        for _, t in ipairs(SUBTABS) do
            local btn = btns[t.key]
            local show = hasPact or not t.needsPact
            setShown(btn, show)
            if show then
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", x, 0)
                x = x + 124
                first = first or t.key
            end
        end
        return first
    end

    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 12, -42)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = {
        chat = BuildChat, overview = BuildOverview,
        bulletin = BuildBulletin, manage = BuildManage,
    }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    -- Unread count on the Chat tab, so a message that lands while you are on
    -- another tab is not silently missed.
    local function paintUnread()
        local chat = BRutus.AllianceChat
        local n = (chat and chat.unread) or 0
        local btn = btns["chat"]
        if not btn then return end
        btn.label:SetText(n > 0 and string.format("%s (%d)", L["Chat"], n) or L["Chat"])
    end
    if BRutus.AllianceChat then
        BRutus.AllianceChat:OnRefresh(function()
            if parent:IsVisible() then paintUnread() end
        end)
    end

    parent:SetScript("OnShow", function()
        local hasPact = BRutus.Alliance and BRutus.Alliance:Get() ~= nil
        local first = layoutTabs(hasPact)
        local want = parent.activeSub
        -- Falling out of a pact must not strand the panel on a hidden tab.
        if not want or not btns[want] or not btns[want]:IsShown() then
            want = hasPact and "chat" or (first or "overview")
        end
        selectSub(want)
        paintUnread()
    end)
end
