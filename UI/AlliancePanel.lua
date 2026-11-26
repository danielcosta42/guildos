----------------------------------------------------------------------
-- Guild OS - Alliance panel (specs/salao/alianca.md §3.5)
-- Two screens, each a room's entry (UI/Rooms.lua):
--   * hall, the Salão's Alliance: the alliance's name and its guilds as far as the code and the
--     channel tell, who of them is on now (a best effort, and it says so), the raids open to the
--     alliance (guildos.me's, Alliance:OpenRaids), and the alliance room with the shared /g's switch;
--   * setup, the Officers' Room's Alliance: "From guildos.me" with the alliance's name while the site's
--     code is in force (managed there: nothing to paste), else the alliance code pasted by hand, which
--     gives the chat only; the guilds blocked on this account; and the alliance's bans (guildos.me's,
--     BanList), shown only while there is an alliance.
-- The ambassador pact's Manage tab, its bulletin and its overview are gone (§3.4).
--
-- Rule 10: no business logic here. Everything is read from Alliance, AllianceLink, AllianceChat and
-- BanList; actions call their methods.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local TAB_MIN_W = 80    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab
local MAX_ONLINE = 24   -- names listed under "Online now"
local MAX_RAIDS = 5     -- open raids listed
local BAN_ROW_H = 18

-- Wrapped hint texts whose width has to follow the panel. Collected per CreateAlliancePanel call.
local flexHints = nil
local function addFlexHint(fs)
    if flexHints then flexHints[#flexHints + 1] = fs end
end

local function ALLY() return GuildOS.Alliance end

-- Explicit Show/Hide: these groups mix Frames, FontStrings and Textures.
local function setShown(widget, cond)
    if cond then widget:Show() else widget:Hide() end
end

-- The shared field (#371).
local function makeInput(parent, width, opts)
    return UI:CreateInput(parent, width, 24, opts)
end

-- A colour token as the hex an inline |c code takes (#371).
local function hex(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- A scroll frame filling `holder` and reaching UI.SCROLL_GUTTER past its right edge (#371).
local function fillScroll(scroll, content)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", UI.SCROLL_GUTTER, 0)
    UI:BindScrollChildWidth(scroll, content)
end

local function wrapText(parent, size, col)
    local fs = UI:CreateText(parent, "", size, col.r, col.g, col.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetWidth(540)   -- until the panel's size is known (MakeResponsive)
    return fs
end

----------------------------------------------------------------------
-- The alliance room: the feed, the composer and the player's switches.
----------------------------------------------------------------------
local function BuildChat(panel)
    local CHAT = function() return GuildOS.AllianceChat end

    -- The status and the toggles share the screen's first line, flush with its edges (#371).
    local status = UI:CreateText(panel, "", UI.SP.META, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("LEFT", panel, "TOPLEFT", 0, -10)

    local sysBtn = UI:CreateButton(panel, L["Events"], 90, 20)
    sysBtn:SetPoint("TOPRIGHT", 0, 0)
    local clearBtn = UI:CreateButton(panel, L["Clear"], 70, 20)
    clearBtn:SetPoint("RIGHT", sysBtn, "LEFT", -6, 0)
    -- The shared /g: the allied guilds' /g in our guild chat (issue #344), each player's switch.
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

        -- The mockup's chat line (.chat .ln): a small round avatar in the speaker's class, the name and the time
        -- beside it, the lines under it; the guild's colour on a thin rail at the left.
        local icon = UI:CreateAvatar(card, 22, false)
        icon:SetPoint("TOPLEFT", 8, -4)
        icon:EnableMouse(false)

        local nameFS = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        nameFS:SetPoint("TOPLEFT", 38, -5)
        nameFS:SetJustifyH("LEFT")

        local timeFS = UI:CreateText(card, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        timeFS:SetPoint("TOPRIGHT", -24, -6)

        local bodyFS = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", 38, -22)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)

        -- Only the icon and the name start a whisper: clicking the message text
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
            if self.name and ChatFrame_SendTell then ChatFrame_SendTell(self.name) end
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
            hide = hide,
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

                -- No box: the dark card is the room's; our own guild's lines sit a shade lighter.
                b.card:SetBackdropColor(1, 1, 1, own and 0.03 or 0)
                b.card:SetBackdropBorderColor(0, 0, 0, 0)
                -- The rail is the GUILD's colour, matching the bulletin, so one
                -- colour means one guild everywhere in this panel. Class still
                -- reads off the icon and the name, which is where you look for
                -- it anyway.
                local gr, gg, gb = GuildOS.Alliance.GuildColor(g.guild)
                b.accent:SetColorTexture(gr, gg, gb, 0.95)
                b.accent:Show()

                b.icon:SetMember(g.name, info and info.class and tostring(info.class):upper() or nil)
                b.icon:Show()

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
                b.hit:Show()

                -- Hides the whole block's text, which is what the officer
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

    -- Repainted by the hall (BuildHall), which listens to the room for both.
    return refresh
end

----------------------------------------------------------------------
-- Salão › Alliance, as the mockup's (#449 phase 3): dark cards on the wood, in two columns from 700px and one
-- under the other below. On the left the alliance (its name, its guilds in their colours, the raids open to it);
-- on the right who is on now, and the alliance room as tall as what is left of the screen.
----------------------------------------------------------------------
local HALL_TWO, HALL_SHARE, HALL_GUTTER = 700, 0.535, 12
local HALL_PAD, HALL_TOP = 14, 16
local ROOM_MIN = 240

local function BuildHall(panel)
    local info = UI:CreateCard(panel, "", { dark = true })
    local onlineCard = UI:CreateCard(panel, "", { dark = true })
    local roomCard = UI:CreateCard(panel, "", { dark = true })

    -- Each card's title, its own line in the title face (the soft gold on the dark card).
    local title = UI:CreateSectionTitle(info, "", true)
    local empty = wrapText(info, 12, C.textSoft)
    local guildsFS = wrapText(info, 12, C.text)
    local raidsHdr = UI:CreateSectionTitle(info, L["Open raids"], true)
    local raidsFS = wrapText(info, 12, C.text)
    local onlineHdr = UI:CreateSectionTitle(onlineCard, L["Online now"], true)
    local onlineFS = wrapText(onlineCard, 12, C.text)
    local onlineHint = wrapText(onlineCard, 11, C.textSoft)
    onlineHint:SetText(L["Best effort: only who spoke on the alliance channel or runs GuildOS is seen."])
    local roomHdr = UI:CreateSectionTitle(roomCard, L["Alliance room"], true)
    roomHdr:SetPoint("TOPLEFT", HALL_PAD, -HALL_TOP)

    -- The room fills its card under the title.
    local room = CreateFrame("Frame", nil, roomCard)
    room:SetPoint("TOPLEFT", HALL_PAD, -(HALL_TOP + 24))
    room:SetPoint("BOTTOMRIGHT", -HALL_PAD, HALL_PAD - 4)
    local refreshRoom = BuildChat(room)

    -- A line of text in a card, at `y` from its top, `w` wide; the next line's y.
    local function place(fs, y, w)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", HALL_PAD, -y)
        if w then fs:SetWidth(w) end
        fs:Show()
        return y + math.max(14, fs:GetStringHeight() or 12) + 6
    end
    local function put(card, x, y, w, h)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", x, -y)
        card:SetSize(w, h)
        card:Show()
        return y + h + HALL_GUTTER
    end

    local function refresh()
        local ally = ALLY()
        local pact = ally and ally:Get()
        local inPact = pact ~= nil
        local W = math.max(260, (panel:GetWidth() or 0))
        local two = W >= HALL_TWO
        local lw = two and math.floor((W - HALL_GUTTER) * HALL_SHARE) or W
        local rw = two and (W - HALL_GUTTER - lw) or W
        for _, w in ipairs({ guildsFS, raidsHdr, raidsFS, onlineCard, roomCard, room }) do
            w:Hide()
        end
        setShown(empty, not inPact)
        if not inPact then
            title:SetText(L["Alliance"])
            local lines = { L["This guild is not in an alliance yet."], ALLY() and ALLY().MOVED or "" }
            empty:SetText(table.concat(lines, "\n"))
            local y = place(title, HALL_TOP)
            y = place(empty, y + 2, lw - 2 * HALL_PAD)
            put(info, 0, 2, lw, y + HALL_PAD - 6)
            return
        end
        local name = ally:Name() or pact.tag
        GuildOS:SetTitleText(title, name == pact.tag and name or string.format("%s [%s]", name, pact.tag))
        local y = place(title, HALL_TOP)

        -- The guilds, in their colours, ours marked, the others with how many are seen on now.
        local parts = {}
        -- How many the site lists of each allied guild (GOSALLY1's directory), when it sent one.
        local counts = {}
        for _, d in ipairs(ally:Directory()) do counts[d.guild] = #d.members end
        for _, g in ipairs(ally:Guilds()) do
            local label = "|cff" .. ally.GuildColorHex(g.name) .. g.name .. "|r"
            if counts[g.name] and counts[g.name] > 0 then
                label = label .. " |cff" .. hex(C.textSoft) .. string.format(L["(%d in the directory)"], counts[g.name]) .. "|r"
            end
            if g.mine then
                label = label .. " " .. L["(you)"]
            elseif (g.online or 0) > 0 then
                label = label .. " |cff" .. hex(C.ok) .. string.format(L["%d online"], g.online) .. "|r"
            end
            parts[#parts + 1] = label
        end
        guildsFS:SetText(table.concat(parts, "\n"))
        y = place(guildsFS, y + 2, lw - 2 * HALL_PAD)

        -- Raids open to the alliance, from guildos.me (GOSALLY1): nothing until the site sends them.
        local raids = ally:OpenRaids()
        if #raids > 0 then
            local asOf = ally:AsOf()
            raidsHdr:SetText(L["Open raids"] .. (asOf and ("  |cff" .. hex(C.textSoft)
                .. string.format(L["(as of %s)"], GuildOS:LocalDate("%a %H:%M", asOf)) .. "|r") or ""))
            y = place(raidsHdr, y + 10)
            local lines = {}
            for i = 1, math.min(#raids, MAX_RAIDS) do
                local r = raids[i]
                local when = r.when and GuildOS:LocalDate("%d/%m %H:%M", r.when) or "?"
                local count = r.size and string.format(" (%d/%d)", r.going or 0, r.size)
                    or (r.going and string.format(" (%d)", r.going) or "")
                local extra = (r.where and ("  " .. GuildOS:SanitizeUserText(r.where, 80)) or "")
                    .. (r.leader and ("  " .. string.format(L["led by %s"], GuildOS:SanitizeUserText(r.leader, 48))) or "")
                lines[#lines + 1] = when .. "  " .. GuildOS:SanitizeUserText(r.title or "?", 60) .. count
                    .. "  |cff" .. ally.GuildColorHex(r.guild) .. "[" .. tostring(r.guild or "?") .. "]|r"
                    .. "|cff" .. hex(C.textSoft) .. extra .. "|r"
            end
            -- Nothing here signs anybody up (alianca.md §3.2): the site and Discord do.
            lines[#lines + 1] = "|cff" .. hex(C.textSoft) .. L["Sign up in Discord or on the website."] .. "|r"
            raidsFS:SetText(table.concat(lines, "\n"))
            y = place(raidsFS, y, lw - 2 * HALL_PAD)
        end
        local yl = put(info, 0, 2, lw, y + HALL_PAD - 6)

        -- Who of the alliance is on now, by guild.
        local online, names = ally:OnlineNow(), {}
        for i = 1, math.min(#online, MAX_ONLINE) do
            local p = online[i]
            names[#names + 1] = p.name .. " |cff" .. ally.GuildColorHex(p.guild) .. "[" .. p.guild .. "]|r"
        end
        if #online > MAX_ONLINE then names[#names + 1] = "+" .. (#online - MAX_ONLINE) end
        onlineFS:SetText(#names > 0 and table.concat(names, ", ") or L["nobody online"])
        local oy = place(onlineHdr, HALL_TOP)
        oy = place(onlineFS, oy + 2, rw - 2 * HALL_PAD)
        oy = place(onlineHint, oy, rw - 2 * HALL_PAD)
        local xr, yr = two and (lw + HALL_GUTTER) or 0, two and 2 or yl
        yr = put(onlineCard, xr, yr, rw, oy + HALL_PAD - 6)

        -- The alliance room, as tall as what is left under the cards on its side.
        local roomH = math.max(ROOM_MIN, (panel:GetHeight() or 0) - yr - 2)
        put(roomCard, xr, yr, rw, roomH)
        room:Show()
        refreshRoom()
    end

    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:OnRefresh(function()
            if panel:IsVisible() then refresh() end
        end)
    end
    -- Laid out again at the screen's new width.
    if panel.HookScript then
        panel:HookScript("OnSizeChanged", function() if panel:IsVisible() then GuildOS:SafeCall(refresh) end end)
    end
    return refresh
end

----------------------------------------------------------------------
-- Officers' Room › Alliance
----------------------------------------------------------------------
-- The Officers' Room's Alliance is drawn on a parchment card (specs/salao/fase3.md): the paper's inks
-- (UI/Kit.lua), the shared colours where the kit is absent.
local P = setmetatable({}, { __index = function(_, k)
    local Kit = rawget(GuildOS, "Kit")
    return (Kit and Kit.PAPER or C)[k]
end })

local function BuildSetup(panel)
    local LINK = function() return GuildOS.AllianceLink end
    local board = UI:CreateBoard(panel, { name = "GuildOSAllianceSetupBoard" })
    local state = { officer = false, site = false, blocking = false, bans = false }

    -- The code (the mockup's "Alliance code"): where it stands, the tag and Generate, the code, and Save for
    -- the guild at the card's bottom right. Pasted by hand the code gives the chat only (alianca.md §3.3).
    local codeCard = board:Card(L["Alliance code"], { col = 1 })
    local status = UI:CreateText(codeCard, "", 12, P.text.r, P.text.g, P.text.b)
    status:SetJustifyH("LEFT")
    codeCard:Add(status, { place = function(fs, w) fs:SetWidth(w); return math.ceil(tonumber(fs:GetStringHeight()) or 14) end })
    local chatOnly = wrapText(codeCard, UI.SP.META, P.textSoft)
    chatOnly:SetText(L["Chat only: the shared /g and the alliance room. Members, crafters, raids and bans come from guildos.me."])
    codeCard:Add(chatOnly, { gap = 4, place = function(fs, w) fs:SetWidth(w); return math.ceil(tonumber(fs:GetStringHeight()) or 12) end })
    local editing = function() return state.officer and not state.site end

    local tagBox = makeInput(codeCard, 110)
    local genBtn = UI:CreateButton(codeCard, L["Generate"], 110, 24)
    genBtn:SetWidth(math.ceil(tonumber(genBtn.label:GetStringWidth()) or 60) + 24)
    local tagField = codeCard:Field(L["Tag (letters and numbers)"], tagBox, { w = 160, button = genBtn, gap = 10, shown = editing })
    local lineBox = makeInput(codeCard, 300)
    lineBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    codeCard:Field(L["Alliance code"], lineBox, { shown = editing })
    local hint = wrapText(codeCard, UI.SP.META, P.textDim)
    hint:SetText(L["Paste this same code here in every guild of the alliance and save, once. It goes in the guild master's public note where the game allows it, and every member hands it on at login: nobody in particular has to be online."])
    codeCard:Add(hint, { shown = editing, place = function(fs, w) fs:SetWidth(w); return math.ceil(tonumber(fs:GetStringHeight()) or 12) end })
    local removeBtn = UI:CreateButton(codeCard, L["Turn off for the guild"], 170, 24)
    removeBtn:SetWidth(math.ceil(tonumber(removeBtn.label:GetStringWidth()) or 120) + 24)
    local writeBtn = UI:CreateButton(codeCard, L["Save for the guild"], 170, 24)
    UI:SetButtonVariant(writeBtn, "primary")
    writeBtn:SetWidth(math.ceil(tonumber(writeBtn.label:GetStringWidth()) or 120) + 24)
    codeCard:Actions({ removeBtn, writeBtn }, { shown = editing })
    local tagLbl = tagField.label

    -- An allied guild blocked on this account: its lines on the channel are not shown, and nobody is told.
    local blockCard = board:Card(L["Ignore a guild locally"], { col = 2, shown = function() return state.blocking end })
    local blockBox = makeInput(blockCard, 200)
    local blockBtn = UI:CreateButton(blockCard, L["Block"], 90, 24)
    blockCard:Field(L["Guild"], blockBox, { button = blockBtn })
    local blockedFS = wrapText(blockCard, UI.SP.META, P.textDim)
    blockCard:Add(blockedFS, { place = function(fs, w) fs:SetWidth(w); return math.ceil(tonumber(fs:GetStringHeight()) or 12) end })
    local unblockBtn = UI:CreateButton(blockCard, L["Unblock"], 90, 24)
    blockCard:Actions({ unblockBtn })

    -- The alliance's bans, guildos.me's (BanList, #408): read-only, an alert for the officers. Hidden while
    -- this guild has no alliance on the site (audit B7).
    local bansCard = board:Card(L["The alliance's bans"], { col = 2, fill = true, minH = 160,
        shown = function() return state.bans end })
    local bansHdr = bansCard
    local holder = bansCard:Body(BAN_ROW_H * 4)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceBansScroll")
    fillScroll(scroll, content)
    local bansEmpty = wrapText(content, 11, P.textSoft)
    bansEmpty:SetPoint("TOPLEFT", 0, 0)
    bansEmpty:SetText(L["No bans from the alliance. The site sends them with the companion when other guilds share theirs."])
    addFlexHint(bansEmpty)
    local rows = {}
    local function row(i)
        if rows[i] then return rows[i] end
        local fs = UI:CreateText(content, "", 11, P.text.r, P.text.g, P.text.b)
        fs:SetPoint("TOPLEFT", 0, -(i - 1) * BAN_ROW_H)
        fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        rows[i] = fs
        return fs
    end

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
        -- `err` is true when it went in the guild master's note too (issue #431).
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

    local function refreshBans(officer)
        local BL = GuildOS.BanList
        local list = (officer and BL) and BL:AllianceBans() or nil
        local shown = officer and BL and ((list and #list > 0) or BL:HasSiteAlliance()) or false
        state.bans = shown and true or false
        setShown(bansHdr, shown)
        for _, fs in ipairs(rows) do fs:Hide() end
        if not shown then return end
        local n = 0
        for _, b in ipairs(list or {}) do
            n = n + 1
            local fs = row(n)
            fs:SetText(string.format("|cff%s%s|r  %s", hex(P.red), tostring(b.name or "?"), BL.AllianceLine(b))
                .. (b.note and ("  |cff" .. hex(P.textDim) .. b.note .. "|r") or ""))
            fs:Show()
        end
        setShown(bansEmpty, n == 0)
        content:SetHeight(math.max(1, n * BAN_ROW_H, n == 0 and 30 or 0))
    end

    refresh = function()
        local link = LINK()
        if not link then return end
        local cfg = link:Config()
        local mine = ALLY() and ALLY():MyGuildName()
        local pact = link:Pact()
        local site = cfg ~= nil and cfg.site == true
        chatOnly:SetText(site
            and L["This alliance is managed on guildos.me: its guilds, its key and who sees what. The companion brings it here; there is nothing to paste."]
            or L["Chat only: the shared /g and the alliance room. Members, crafters, raids and bans come from guildos.me."])
        if site then
            -- The site's code is in force (alianca.md §3.2): managed there, nothing to paste here.
            status:SetText(string.format(L["From guildos.me: %s [%s]"], cfg.name or cfg.tag, cfg.tag))
        elseif pact and cfg and cfg.open then
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
        state.officer, state.site = officer and true or false, site and true or false
        for _, w in ipairs({ tagLbl, tagBox, genBtn, lineBox, writeBtn, removeBtn, hint }) do
            setShown(w, officer and not site)
        end
        local blocking = officer and pact ~= nil
        state.blocking = blocking and true or false
        setShown(blockCard, blocking)
        if blocking then
            local list = ALLY():Blocked()
            blockedFS:SetText(#list > 0 and string.format(L["Blocked: %s"], table.concat(list, ", "))
                or L["Lines from a blocked guild are not shown on this account. Nobody is told."])
        end
        refreshBans(officer)
        if board.Layout then board:Layout() end
        if not officer or site then return end
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
-- Entry point (UI/Features.lua)
----------------------------------------------------------------------
local SUBTABS = {
    { key = "hall",  label = L["Overview"] },
    { key = "setup", label = L["Setup"], officer = true },
}

function GuildOS:CreateAlliancePanel(parent, _mainFrame)
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
        if not btns[key] then key = "hall" end
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do
            info.panel:SetShown(k == key)
        end
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

    -- The officers' screen only for an officer; the bar flows what is shown.
    local function layoutTabs()
        local visible = {}
        for _, t in ipairs(SUBTABS) do
            local show = not t.officer or GuildOS:IsOfficer()
            setShown(btns[t.key], show)
            if show then visible[#visible + 1] = btns[t.key] end
        end
        UI:FlowBar(bar, visible, { gap = 4, rowGap = 4, rowH = 28 })
    end

    -- Flush with the bar's left edge, UI.GAP under it, ending UI.GAP short of its right edge (#371). The Officers'
    -- Room's setup lays its parchment cards on the wood there (UI/Forms.lua, the mockup's "Alliance code").
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -UI.GAP)
        p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(10 + UI.GAP), 10)
        p:Hide()
        return p
    end

    local builders = { hall = BuildHall, setup = BuildSetup }
    flexHints = {}
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel(t.key)
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end
    local myHints = flexHints
    flexHints = nil
    -- Opened from a room entry that names a sub-tab, the room's row is the only row of tabs (#445).
    UI:CollapsibleSubBar(parent, bar, function()
        local frames = {}
        for k, info in pairs(parent.subPanels) do frames[k] = info.panel end
        return frames
    end, { 0, -UI.GAP })

    parent:SetScript("OnShow", function()
        layoutTabs()
        local want = parent.activeSub
        if not want or not btns[want]:IsShown() then want = "hall" end
        selectSub(want)
    end)

    UI:MakeResponsive(parent, function(_, w, h)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs()
        -- The setup's cards at its area's width and height (its anchors say so; the game says so a frame later).
        local setupBoard = rawget(parent.subPanels.setup.panel, "board")
        if type(setupBoard) == "table" and setupBoard.Layout then
            local areaH = h - 8 - 10 - (bar:IsShown() and ((tonumber(bar:GetHeight()) or 28) + UI.GAP) or 0)
            setupBoard:Layout(w - 20 - UI.GAP - (tonumber(UI.SCROLL_GUTTER) or 12), areaH)
        end
        local hintW = math.max(220, w - 40)
        for _, fs in ipairs(myHints) do fs:SetWidth((UI.OnPaper and UI:OnPaper(fs)) and (hintW - 28) or hintW) end
    end)
end
