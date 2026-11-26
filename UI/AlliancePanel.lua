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

-- Room over a later section title for the rule UI:CreateSectionTitle draws 12px above it, and the
-- height a title takes with the gap under it (#371).
local SECTION_ABOVE, TITLE_H = 20, 24

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
    local status = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
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
-- Salão › Alliance
----------------------------------------------------------------------
local function BuildHall(panel)
    local title = UI:CreateSectionTitle(panel, "", true)
    title:SetPoint("TOPLEFT", 0, 0)
    local empty = wrapText(panel, 12, C.textSoft)
    empty:SetPoint("TOPLEFT", 0, -TITLE_H)
    addFlexHint(empty)

    local guildsFS = wrapText(panel, 11, C.text)
    addFlexHint(guildsFS)
    local onlineHdr = UI:CreateText(panel, L["Online now"], 11, C.label.r, C.label.g, C.label.b)
    local onlineFS = wrapText(panel, 11, C.text)
    addFlexHint(onlineFS)
    local onlineHint = wrapText(panel, 9, C.textDim)
    onlineHint:SetText(L["Best effort: only who spoke on the alliance channel or runs GuildOS is seen."])
    addFlexHint(onlineHint)
    local raidsHdr = UI:CreateText(panel, L["Open raids"], 11, C.label.r, C.label.g, C.label.b)
    local raidsFS = wrapText(panel, 11, C.text)
    addFlexHint(raidsFS)
    local roomHdr = UI:CreateSectionTitle(panel, L["Alliance room"])

    -- The room fills what is left, under the lines above (placed on refresh: their height varies).
    local room = CreateFrame("Frame", nil, panel)
    room:SetPoint("BOTTOMRIGHT", 0, 0)
    local refreshRoom = BuildChat(room)

    local function place(fs, y)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:Show()
        return y + math.max(14, fs:GetStringHeight() or 12) + 4
    end

    local function refresh()
        local ally = ALLY()
        local pact = ally and ally:Get()
        local inPact = pact ~= nil
        for _, w in ipairs({ guildsFS, onlineHdr, onlineFS, onlineHint, raidsHdr, raidsFS, roomHdr, room }) do
            w:Hide()
        end
        setShown(empty, not inPact)
        if not inPact then
            title:SetText(L["Alliance"])
            local lines = { L["This guild is not in an alliance yet."], ALLY() and ALLY().MOVED or "" }
            empty:SetText(table.concat(lines, "\n"))
            return
        end
        local name = ally:Name() or pact.tag
        title:SetText(name == pact.tag and name or string.format("%s [%s]", name, pact.tag))

        -- The guilds, in their colours, ours marked, the others with how many are seen on now.
        local parts = {}
        -- How many the site lists of each allied guild (GOSALLY1's directory), when it sent one.
        local counts = {}
        for _, d in ipairs(ally:Directory()) do counts[d.guild] = #d.members end
        for _, g in ipairs(ally:Guilds()) do
            local label = "|cff" .. ally.GuildColorHex(g.name) .. g.name .. "|r"
            if counts[g.name] and counts[g.name] > 0 then
                label = label .. " |cff" .. hex(C.textDim) .. string.format(L["(%d in the directory)"], counts[g.name]) .. "|r"
            end
            if g.mine then
                label = label .. " " .. L["(you)"]
            elseif (g.online or 0) > 0 then
                label = label .. " |cff" .. hex(C.ok) .. string.format(L["%d online"], g.online) .. "|r"
            end
            parts[#parts + 1] = label
        end
        guildsFS:SetText(table.concat(parts, "   "))
        local y = place(guildsFS, TITLE_H)

        y = place(onlineHdr, y + UI.GAP)
        local online, names = ally:OnlineNow(), {}
        for i = 1, math.min(#online, MAX_ONLINE) do
            local p = online[i]
            names[#names + 1] = p.name .. " |cff" .. ally.GuildColorHex(p.guild) .. "[" .. p.guild .. "]|r"
        end
        if #online > MAX_ONLINE then names[#names + 1] = "+" .. (#online - MAX_ONLINE) end
        onlineFS:SetText(#names > 0 and table.concat(names, ", ") or L["nobody online"])
        y = place(onlineFS, y)
        y = place(onlineHint, y)

        -- Raids open to the alliance, from guildos.me (GOSALLY1): nothing until the site sends them.
        local raids = ally:OpenRaids()
        if #raids > 0 then
            local asOf = ally:AsOf()
            raidsHdr:SetText(L["Open raids"] .. (asOf and ("  |cff" .. hex(C.textDim)
                .. string.format(L["(as of %s)"], GuildOS:LocalDate("%a %H:%M", asOf)) .. "|r") or ""))
            y = place(raidsHdr, y + UI.GAP)
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
            lines[#lines + 1] = "|cff" .. hex(C.textDim) .. L["Sign up in Discord or on the website."] .. "|r"
            raidsFS:SetText(table.concat(lines, "\n"))
            y = place(raidsFS, y)
        end

        y = place(roomHdr, y + SECTION_ABOVE)
        room:ClearAllPoints()
        room:SetPoint("TOPLEFT", 0, -(y + UI.GAP))
        room:SetPoint("BOTTOMRIGHT", 0, 0)
        room:Show()
        refreshRoom()
    end

    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:OnRefresh(function()
            if panel:IsVisible() then refresh() end
        end)
    end
    return refresh
end

----------------------------------------------------------------------
-- Officers' Room › Alliance
----------------------------------------------------------------------
local function BuildSetup(panel)
    local LINK = function() return GuildOS.AllianceLink end

    -- The screen's first section title, then form labels in `text` over their fields (#371).
    local hdr = UI:CreateSectionTitle(panel, L["Alliance code"], true)
    hdr:SetPoint("TOPLEFT", 0, 0)
    local status = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    status:SetPoint("TOPLEFT", 0, -TITLE_H)
    status:SetJustifyH("LEFT")
    -- Pasted by hand the code gives the chat only (alianca.md §3.3).
    local chatOnly = wrapText(panel, 10, C.textSoft)
    chatOnly:SetPoint("TOPLEFT", 0, -(TITLE_H + 18))
    chatOnly:SetText(L["Chat only: the shared /g and the alliance room. Members, crafters, raids and bans come from guildos.me."])
    addFlexHint(chatOnly)

    local tagLbl = UI:CreateText(panel, L["Tag (letters and numbers)"], 11)
    tagLbl:SetPoint("TOPLEFT", chatOnly, "BOTTOMLEFT", 0, -UI.GAP)
    local tagBox = makeInput(panel, 110)
    tagBox:SetPoint("TOPLEFT", tagLbl, "BOTTOMLEFT", 0, -4)
    local genBtn = UI:CreateButton(panel, L["Generate"], 110, 24)
    genBtn:SetPoint("LEFT", tagBox, "RIGHT", UI.GAP, 0)

    local lineBox = makeInput(panel, 540)
    lineBox:SetPoint("TOPLEFT", tagBox, "BOTTOMLEFT", 0, -(UI.GAP + 4))
    lineBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local writeBtn = UI:CreateButton(panel, L["Save for the guild"], 170, 24)
    writeBtn:SetPoint("TOPLEFT", lineBox, "BOTTOMLEFT", 0, -UI.GAP)
    local removeBtn = UI:CreateButton(panel, L["Turn off for the guild"], 170, 24)
    removeBtn:SetPoint("LEFT", writeBtn, "RIGHT", UI.GAP, 0)

    local hint = wrapText(panel, 10, C.textDim)
    hint:SetText(L["Paste this same code here in every guild of the alliance and save, once. It goes in the guild master's public note where the game allows it, and every member hands it on at login: nobody in particular has to be online."])
    hint:SetPoint("TOPLEFT", writeBtn, "BOTTOMLEFT", 0, -UI.GAP)
    addFlexHint(hint)

    -- An allied guild blocked on this account: its lines on the channel are not shown, and nobody is told.
    local blockHdr = UI:CreateSectionTitle(panel, L["Ignore a guild locally"])
    local blockBox = makeInput(panel, 200)
    blockBox:SetPoint("TOPLEFT", blockHdr, "BOTTOMLEFT", 0, -UI.GAP)
    local blockBtn = UI:CreateButton(panel, L["Block"], 90, 24)
    blockBtn:SetPoint("LEFT", blockBox, "RIGHT", UI.GAP, 0)
    local unblockBtn = UI:CreateButton(panel, L["Unblock"], 90, 24)
    unblockBtn:SetPoint("LEFT", blockBtn, "RIGHT", 6, 0)
    local blockedFS = wrapText(panel, 10, C.textDim)
    blockedFS:SetPoint("TOPLEFT", blockBox, "BOTTOMLEFT", 0, -UI.GAP)
    addFlexHint(blockedFS)

    -- The alliance's bans, guildos.me's (BanList, #408): read-only, an alert for the officers. Hidden while
    -- this guild has no alliance on the site (audit B7).
    local bansHdr = UI:CreateSectionTitle(panel, L["The alliance's bans"])
    bansHdr:SetPoint("TOPLEFT", blockedFS, "BOTTOMLEFT", 0, -SECTION_ABOVE - UI.GAP)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", bansHdr, "BOTTOMLEFT", 0, -UI.GAP)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceBansScroll")
    fillScroll(scroll, content)
    local bansEmpty = wrapText(content, 11, C.textSoft)
    bansEmpty:SetPoint("TOPLEFT", 0, 0)
    bansEmpty:SetText(L["No bans from the alliance. The site sends them with the companion when other guilds share theirs."])
    addFlexHint(bansEmpty)
    local rows = {}
    local function row(i)
        if rows[i] then return rows[i] end
        local fs = UI:CreateText(content, "", 11, C.text.r, C.text.g, C.text.b)
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
        setShown(bansHdr, shown)
        setShown(holder, shown)
        for _, fs in ipairs(rows) do fs:Hide() end
        if not shown then return end
        local n = 0
        for _, b in ipairs(list or {}) do
            n = n + 1
            local fs = row(n)
            fs:SetText(string.format("|cff%s%s|r  %s", hex(C.red), tostring(b.name or "?"), BL.AllianceLine(b))
                .. (b.note and ("  |cff" .. hex(C.textDim) .. b.note .. "|r") or ""))
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
        for _, w in ipairs({ tagLbl, tagBox, genBtn, lineBox, writeBtn, removeBtn, hint }) do
            setShown(w, officer and not site)
        end
        -- The block list under whatever the code section shows.
        blockHdr:ClearAllPoints()
        blockHdr:SetPoint("TOPLEFT", (officer and not site) and hint or chatOnly, "BOTTOMLEFT", 0, -SECTION_ABOVE - UI.GAP)
        local blocking = officer and pact ~= nil
        for _, w in ipairs({ blockHdr, blockBox, blockBtn, unblockBtn, blockedFS }) do setShown(w, blocking) end
        if blocking then
            local list = ALLY():Blocked()
            blockedFS:SetText(#list > 0 and string.format(L["Blocked: %s"], table.concat(list, ", "))
                or L["Lines from a blocked guild are not shown on this account. Nobody is told."])
        end
        bansHdr:ClearAllPoints()
        bansHdr:SetPoint("TOPLEFT", blocking and blockedFS or ((officer and not site) and hint or chatOnly), "BOTTOMLEFT",
            0, -SECTION_ABOVE - UI.GAP)
        refreshBans(officer)
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

    -- Flush with the bar's left edge, UI.GAP under it, ending UI.GAP short of its right edge (#371).
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
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end
    local myHints = flexHints
    flexHints = nil
    -- Opened from a room entry that names a sub-tab, the room's row is the only row of tabs (#445).
    UI:CollapsibleSubBar(parent, bar, function() return parent.subPanels end, { 0, -UI.GAP })

    parent:SetScript("OnShow", function()
        layoutTabs()
        local want = parent.activeSub
        if not want or not btns[want]:IsShown() then want = "hall" end
        selectSub(want)
    end)

    UI:MakeResponsive(parent, function(_, w, _)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs()
        local hintW = math.max(220, w - 40)
        for _, fs in ipairs(myHints) do fs:SetWidth(hintW) end
    end)
end
