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

    -- Moderation. Kick and ban do not remove what was already said, which is
    -- impossible on a server-delivered channel; they stop the person carrying
    -- on. Only shown to ambassadors, and never for our own guildmates.
    f.kick = UI:CreateButton(f, L["Kick from channel"], 118, 22)
    f.kick:SetPoint("BOTTOMLEFT", 12, 38)
    f.ban = UI:CreateButton(f, L["Ban from channel"], 118, 22)
    f.ban:SetPoint("LEFT", f.kick, "RIGHT", 6, 0)

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

    -- Moderating your own guildmates through a channel kick is the wrong tool:
    -- that is a guild matter, not an alliance one.
    local chat = BRutus.AllianceChat
    local canModerate = ally and ally:CanAdminister() and info.own ~= true
        and chat and chat:CanModerate()
    setShown(f.kick, canModerate)
    setShown(f.ban, canModerate)
    if canModerate then
        f.kick:SetScript("OnClick", function()
            if chat:Kick(name) then
                BRutus:Print(string.format(L["Asked the server to kick %s from the channel."], name))
            end
        end)
        f.ban:SetScript("OnClick", function()
            StaticPopup_Show("GUILDOS_ALLY_BAN",
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
    ------------------------------------------------------------------
    -- Identity band. This board is the face of the alliance, so it opens
    -- with who the alliance IS: name, size, and one colour chip per member
    -- guild. The chips are the same colours the notices use, so the legend
    -- and the content teach each other.
    ------------------------------------------------------------------
    local title = UI:CreateText(panel, "", 14, C.gold.r, C.gold.g, C.gold.b)
    title:SetPoint("TOPLEFT", 8, -6)
    local count = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    count:SetPoint("TOPRIGHT", -8, -9)

    local chips = {}
    local function getChip(i)
        if chips[i] then return chips[i] end
        chips[i] = panel:CreateTexture(nil, "ARTWORK")
        chips[i]:SetSize(14, 4)
        return chips[i]
    end

    local rule = UI:CreateSeparator(panel)
    rule:SetPoint("TOPLEFT", 0, -38)
    rule:SetPoint("TOPRIGHT", 0, -38)

    local box = makeInput(panel, 100)
    box:SetPoint("TOPLEFT", 8, -48)
    box:SetPoint("RIGHT", panel, "RIGHT", -104, 0)
    box:SetHeight(26)
    local placeholder = UI:CreateText(box, L["Write a notice for the alliance"], 11,
        C.textDim.r, C.textDim.g, C.textDim.b)
    placeholder:SetPoint("LEFT", 8, 0)
    box:SetScript("OnTextChanged", function(self)
        setShown(placeholder, (self:GetText() or "") == "")
    end)

    local postBtn = UI:CreateButton(panel, L["Post"], 88, 26)
    postBtn:SetPoint("TOPRIGHT", -8, -48)

    local hint = UI:CreateText(panel, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", 8, -78)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -94)
    holder:SetPoint("BOTTOMRIGHT", 0, 4)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceBoardScroll")
    scroll:SetAllPoints()

    local empty = UI:CreateText(content, "", 12, C.textDim.r, C.textDim.g, C.textDim.b)
    empty:Hide()

    local refresh

    -- Notice cards, pooled: WoW never frees a frame.
    local cards = {}
    local function getCard(i)
        if cards[i] then return cards[i] end
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
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
        del.fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
        del.fs:SetPoint("CENTER")
        del.fs:SetText("\195\151")
        del.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        del:SetScript("OnEnter", function() del.fs:SetTextColor(C.red.r, C.red.g, C.red.b) end)
        del:SetScript("OnLeave", function() del.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b) end)
        del:SetScript("OnClick", function(self)
            local ok, err = ALLY():RemoveBoardPost(self.postId)
            if not ok and err then BRutus:Print(err) end
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
            BRutus:Print(err)
        end
        refresh()
    end)
    box:SetScript("OnEnterPressed", function() postBtn:Click() end)

    refresh = function()
        local ally = ALLY()
        local Ally = GuildOS.Alliance
        content:SetWidth(math.max(holder:GetWidth() - 12, 1))

        local summary = ally and ally:Summary()
        title:SetText((summary and summary.name) or "")
        count:SetText(summary
            and string.format(L["%d guilds, %d members"], #summary.guilds, summary.members) or "")

        local shown = 0
        if summary then
            for i, g in ipairs(summary.guilds) do
                local chip = getChip(i)
                local r, gg, b = Ally.GuildColor(g.name)
                chip:SetColorTexture(r, gg, b, 0.95)
                chip:SetPoint("TOPLEFT", 8 + (i - 1) * 18, -28)
                chip:Show()
                shown = i
            end
        end
        for i = shown + 1, #chips do chips[i]:Hide() end

        local canPost = ally and ally:CanAdminister()
        setShown(box, canPost)
        setShown(postBtn, canPost)
        setShown(placeholder, canPost and (box:GetText() or "") == "")
        hint:SetText(canPost and L["Ambassadors can post. Everyone in the alliance sees it."]
            or L["Only alliance ambassadors can post here."])

        local posts = (ally and ally.BoardPosts and ally:BoardPosts()) or {}
        local mine = ally and ally:MyGuildName()
        local width = math.max(content:GetWidth() - 8, 200)
        local y = 0

        for i, p in ipairs(posts) do
            local c = getCard(i)
            local r, g, b = Ally.GuildColor(p.guild)

            c.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.5)
            c.rail:SetColorTexture(r, g, b, 0.95)

            c.who:SetText(string.format("|cff%s%s|r  |cff666666\194\183|r  %s",
                Ally.GuildColorHex(p.guild), (p.guild or "?"):upper(), p.by or "?"))
            c.when:SetText(p.ts and BRutus:TimeAgo(p.ts) or "")

            c.body:SetWidth(width - 40)
            c.body:SetText(p.text or "")

            -- Only your own guild's notices can be pulled, and only by an
            -- ambassador: the same independence rule as the rest of the pact.
            c.del.postId = p.id
            setShown(c.del, canPost and p.guild == mine)

            local h = math.max(46, (c.body:GetStringHeight() or 12) + 34)
            c.card:SetPoint("TOPLEFT", 4, -y)
            c.card:SetSize(width, h)
            c.card:Show()
            y = y + h + 6
        end

        for i = #posts + 1, #cards do cards[i].card:Hide() end

        if #posts == 0 then
            -- An empty board is an invitation, not a status report.
            empty:SetText(canPost and L["Nothing here yet. Welcome the allied guilds."]
                or L["Nothing here yet."])
            empty:SetPoint("TOPLEFT", 8, -4)
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

    -- Join code. Shown ONLY to ambassadors: it is stored on every member's
    -- client (they all have to validate it) so this is a deterrent against
    -- casual sharing rather than real secrecy, and the hint says as much.
    local codeHdr = UI:CreateHeaderText(body, L["Join code"], 11)
    local codeBox = makeInput(body, 140)
    codeBox:SetAutoFocus(false)
    codeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local codeNewBtn = UI:CreateButton(body, L["New code"], 100, 24)
    codeNewBtn:SetPoint("LEFT", codeBox, "RIGHT", 8, 0)
    local codeHint = UI:CreateText(body,
        L["A guild with this code joins without anyone having to approve. Anyone in the alliance can be the contact."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    codeHint:SetWidth(460)
    codeHint:SetJustifyH("LEFT")
    codeHint:SetWordWrap(true)

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

    -- Channel ownership goes to whoever joined first, which is usually not an
    -- ambassador, so the people who need to moderate cannot. This hands it over
    -- in one action. Only the owner can, so it hides for everyone else.
    local modBtn = UI:CreateButton(body, L["Give ambassadors channel moderation"], 250, 24)
    modBtn:SetScript("OnClick", function()
        local n = BRutus.AllianceChat and BRutus.AllianceChat:PromoteAmbassadors() or 0
        if n > 0 then
            BRutus:Print(string.format(L["Asked the server to promote %d ambassador(s)."], n))
        else
            BRutus:Print(L["Only the channel owner can do that."])
        end
    end)

    local leaveBtn = UI:CreateButton(body, L["Leave the alliance"], 170, 24)

    local foundGroup  = { foundHdr, tagBox, nameBox, foundBtn, foundHint }
    local memberGroup = { inviteHdr, inviteBox, inviteBtn, inviteHint, ambHdr,
                          blockHdr, blockBox, blockBtn, unblockBtn, blockHint,
                          removeHdr, removeBox, removeBtn, removeHint,
                          chatBtn, chatHint, modBtn, leaveBtn,
                          codeHdr, codeBox, codeNewBtn, codeHint }

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

        codeHdr:SetPoint("TOPLEFT", 6, -y);     y = y + 20
        codeBox:SetPoint("TOPLEFT", 6, -y);     y = y + 28
        codeHint:SetPoint("TOPLEFT", 6, -y);    y = y + 30
        blockHdr:SetPoint("TOPLEFT", 6, -y);    y = y + 20
        blockBox:SetPoint("TOPLEFT", 6, -y);    y = y + 28
        blockHint:SetPoint("TOPLEFT", 6, -y);   y = y + 24
        removeHdr:SetPoint("TOPLEFT", 6, -y);   y = y + 20
        removeBox:SetPoint("TOPLEFT", 6, -y);   y = y + 28
        removeHint:SetPoint("TOPLEFT", 6, -y);  y = y + 26
        chatBtn:SetPoint("TOPLEFT", 6, -y);     y = y + 28
        chatHint:SetPoint("TOPLEFT", 6, -y);    y = y + 30
        modBtn:SetPoint("TOPLEFT", 6, -y);      y = y + 30
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

    codeNewBtn:SetScript("OnClick", function()
        local ok, res = ALLY():RegenerateCode()
        if ok then
            BRutus:Print(string.format(L["New join code: %s"], res))
        elseif res then
            BRutus:Print(res)
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

        -- Ambassadors only. A plain officer manages the pact but does not
        -- get the code to hand around.
        local isAmb = ally:CanAdminister()
        for _, w in ipairs({ codeHdr, codeBox, codeNewBtn, codeHint }) do
            setShown(w, isAmb)
        end
        if isAmb then
            codeBox:SetText(ally:Get().code or "")
            if ally:Get().owner == ally:MyGuildName() then
                codeNewBtn:Enable()
            else
                codeNewBtn:Disable()
            end
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

    StaticPopupDialogs["GUILDOS_ALLY_BAN"] = {
        text = "%s", button1 = L["Ban"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if d and d.name and BRutus.AllianceChat:Ban(d.name) then
                BRutus:Print(string.format(L["Asked the server to ban %s from the channel."], d.name))
            end
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
-- Bulletin first: it is the alliance's front page, the thing an allied leader
-- should land on. Bulletin and Chat need a pact to mean anything, so they hide
-- until there is one, and the panel opens on whichever tab is first VISIBLE.
local SUBTABS = {
    { key = "bulletin", label = L["Bulletin"], needsPact = true },
    { key = "chat",     label = L["Chat"],     needsPact = true },
    { key = "overview", label = L["Overview"] },
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
        -- Falling out of a pact must not strand the panel on a hidden tab, and
        -- the landing tab is simply the first visible one, so reordering
        -- SUBTABS is the only thing anyone has to change.
        if not want or not btns[want] or not btns[want]:IsShown() then
            want = first or "overview"
        end
        selectSub(want)
        paintUnread()
    end)
end
