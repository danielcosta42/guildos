----------------------------------------------------------------------
-- Guild OS - Settings › Help (specs/salao/onboarding.md)
--
-- The help hub, behind the title bar's "?" and Settings' Help entry: the tours with how far each got
-- (Start, Resume or Replay, and each chapter on its own), getting started (the member's list in full; the
-- officers' card lives in the Hall), the guides (a picture and a few lines each, "Show me" running the tour's
-- chapter), and more help: the site, the manual and the Discord as copy boxes (the game opens no browser),
-- /gos help, and "Show tips again". Built on Settings' page (UI/SettingsPanel.lua's form) once per shape and
-- refreshed in place; the guide window is built once and reused.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local L = GuildOS.L

local Help = {}
UI.HelpPanel = Help

local SP = UI.SP
local ROW_H = 46
local CHIP_H = 20
local TILE_W, TILE_PIC = 150, 62

local function O() return GuildOS.Onboarding end
local function P()
    local Kit = rawget(GuildOS, "Kit")
    return Kit and Kit.PAPER or GuildOS.Colors
end

local function text(parent, size, color, role)
    local f = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f, size, role)
    f:SetShadowOffset(0, 0)
    f:SetTextColor(color.r, color.g, color.b)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
end

local function fitButton(b, min)
    b:SetWidth(math.max(min or 50, math.ceil(tonumber(b.label:GetStringWidth()) or 40) + 20))
    return b
end

local function openHelpEntry()
    local f = UI.GetMainWindow and UI:GetMainWindow()
    if not f then return end
    for _, e in ipairs(UI:RoomEntries("settings")) do if e.id == "help" then return f:SelectEntry("settings", e, true) end end
end
Help.OpenHub = openHelpEntry

----------------------------------------------------------------------
-- A copy box: the address in a read-only field, Copy selecting it (Ctrl+C then copies it).
----------------------------------------------------------------------
function Help:CopyRow(parent, url)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(200, SP.FIELD)
    local box = UI:CreateInput(row, 160, SP.FIELD)
    box:SetText(url)
    box:SetPoint("LEFT", 0, 0)
    box:SetScript("OnTextChanged", function(self) if self:GetText() ~= url then self:SetText(url); self:HighlightText() end end)
    box:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local copy = fitButton(UI:CreateButton(row, L["Copy"], 60, SP.FIELD), 56)
    copy:SetPoint("RIGHT", 0, 0)
    copy:SetScript("OnClick", function()
        box:SetFocus()
        box:HighlightText()
        GuildOS:Print(L["The address is selected: Ctrl+C copies it."])
    end)
    box:SetPoint("RIGHT", copy, "LEFT", -6, 0)
    row.box, row.copy, row.url = box, copy, url
    return row
end

----------------------------------------------------------------------
-- The guide window
----------------------------------------------------------------------
function Help:GuideWindow()
    if self.guide then return self.guide end
    local Kit = GuildOS.Kit
    local g = Kit:Float(L["Guide"], { name = "GuildOSGuide", width = 460, height = 380, foot = true, sub = L["guide"] })
    g:SetFrameLevel(60)
    g.pic = CreateFrame("Frame", nil, g.body)
    g.pic:SetPoint("TOPLEFT", 0, 0)
    g.pic:SetPoint("TOPRIGHT", 0, 0)
    g.pic:SetHeight(130)
    local C = GuildOS.Colors
    g.text = text(g.body, SP.BODY, C.text, "reading")
    g.text:SetWordWrap(true)
    g.text:SetJustifyV("TOP")
    g.text:SetPoint("TOPLEFT", g.pic, "BOTTOMLEFT", 0, -12)
    g.text:SetPoint("TOPRIGHT", g.pic, "BOTTOMRIGHT", 0, -12)
    g.more = text(g.body, SP.META, C.textSoft)
    g.more:SetText(L["Read on guildos.me (copy the link):"])
    g.link = self:CopyRow(g.body, O().URLS.manual)
    g.link:SetPoint("BOTTOMLEFT", g.body, "BOTTOMLEFT", 0, 2)
    g.link:SetPoint("BOTTOMRIGHT", g.body, "BOTTOMRIGHT", 0, 2)
    g.more:SetPoint("BOTTOMLEFT", g.link, "TOPLEFT", 0, 4)
    g.close = UI:CreateButton(g.foot, L["Close"], 80, SP.FIELD)
    g.close:SetScript("OnClick", function() g:Hide() end)
    g.show = UI:SetButtonVariant(UI:CreateButton(g.foot, L["Show me"], 90, SP.FIELD), "primary")
    g.show:SetScript("OnClick", function()
        g:Hide()
        if g.item and UI.Tour then UI.Tour:Start(g.item.track, g.item.ch) end
    end)
    self.guide = g
    return g
end

function Help:OpenGuide(id)
    local item = O():Guide(id)
    if not item then return nil end
    local g = self:GuideWindow()
    g.item = item
    g:SetTitle(item.title, L["guide"])
    local w = (g:GetWidth() or 460) - 2 * GuildOS.Kit.PAD
    UI.Picture:Draw(g.pic, item.ill, w, 130)
    g.text:SetWidth(w)
    g.text:SetText(item.body)
    fitButton(g.close, 70); fitButton(g.show, 80)
    g.foot:Lay(g.show, g.close)
    g:Show()
    return g
end

----------------------------------------------------------------------
-- The page (Settings' form `F`)
----------------------------------------------------------------------
local function trackRow(F, id)
    local Ob = O()
    local C = P()
    local row = CreateFrame("Frame", nil, F.content)
    row:SetSize(1, ROW_H)
    row.ring = GuildOS.Style:Texture(row, "ring", "ARTWORK", 0)
    row.ring:SetSize(34, 34)
    row.ring:SetPoint("TOPLEFT", 0, -4)
    row.fillDisc = GuildOS.Style:Texture(row, "circle", "BACKGROUND", 1)
    row.fillDisc:SetSize(30, 30)
    row.fillDisc:SetPoint("CENTER", row.ring, "CENTER", 0, 0)
    row.pct = text(row, 9, C.text, "tableNum")
    row.pct:SetJustifyH("CENTER")
    row.pct:SetPoint("CENTER", row.ring, "CENTER", 0, 0)
    row.name = text(row, SP.BODY, C.text, "button")
    row.name:SetPoint("TOPLEFT", 46, -4)
    row.sub = text(row, SP.META, C.textSoft)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.go = fitButton(UI:CreateButton(row, L["Start"], 70, SP.HIT), 64)
    row.go:SetPoint("TOPRIGHT", 0, -6)
    row.name:SetPoint("RIGHT", row.go, "LEFT", -8, 0)
    row.sub:SetPoint("RIGHT", row.go, "LEFT", -8, 0)
    row.chips = {}
    row.id = id
    if id == "whatsnew" then
        row.go:SetScript("OnClick", function() GuildOS:ShowWhatsNew(true) end)
    else
        row.go:SetScript("OnClick", function() if UI.Tour then UI.Tour:Start(id) end end)
        for i, ch in ipairs(Ob.TRACKS[id].chapters) do
            local b = UI:SetButtonVariant(UI:CreateButton(row, ch.label, 60, CHIP_H), "chip")
            b.ch = ch.id
            b:SetScript("OnClick", function() if UI.Tour then UI.Tour:Start(id, ch.id) end end)
            row.chips[i] = b
        end
    end
    -- The chips wrap under the name.
    function row:Lay(w)
        local x, y = 46, ROW_H - 4
        for _, b in ipairs(self.chips) do
            if b:IsShown() then
                local bw = b:GetWidth()
                if x > 46 and x + bw > w then x, y = 46, y + CHIP_H + 4 end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
                x = x + bw + 4
            end
        end
        local h = (#self.chips > 0) and (y + CHIP_H + 2) or ROW_H
        self:SetHeight(h)
        return h
    end
    function row:Sync()
        local CC = P()
        local pct, sub, label
        if self.id == "whatsnew" then
            pct = Ob:Pending() and 0 or 100
            local n = #Ob:Cards(Ob:Arrival())
            sub = string.format(L["%d cards"], n)
            self.name:SetText(string.format(L["What's new in %s"], Ob.WHATS_NEW_ID))
            label = pct == 100 and L["Replay"] or L["Open"]
        else
            local steps = Ob:Steps(self.id)
            local chapters = Ob:Chapters(self.id, steps)
            pct = Ob:Percent(self.id, steps)
            sub = string.format(L["%d chapters \194\183 %d steps"], #chapters, #steps)
            self.name:SetText(Ob.TRACKS[self.id].label)
            label = (pct == 0 and L["Start"]) or (pct >= 100 and L["Replay"]) or L["Resume"]
            local done = Ob:Progress(self.id).chapters
            local present = {}
            for _, c in ipairs(chapters) do present[c.id] = true end
            for _, b in ipairs(self.chips) do
                b:SetShown(present[b.ch] == true)
                local lab
                for _, c in ipairs(Ob.TRACKS[self.id].chapters) do if c.id == b.ch then lab = c.label end end
                b.label:SetText((done[b.ch] and "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t " or "") .. (lab or b.ch))
                fitButton(b, 40)
                UI:SetSelected(b, done[b.ch] == true)
            end
        end
        self.sub:SetText(sub)
        self.pct:SetText(pct >= 100 and "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t" or (pct .. "%"))
        local ring = pct >= 100 and CC.ok or (pct > 0 and (CC.paperTitle or CC.gold) or CC.paperLine or CC.line)
        self.ring:SetVertexColor(ring.r, ring.g, ring.b, 1)
        local disc = CC.paperLight or CC.paper or CC.popup
        self.fillDisc:SetVertexColor(disc.r, disc.g, disc.b, 1)
        self.go.label:SetText(label)
        fitButton(self.go, 64)
    end
    return row
end

-- A checklist row (the member's list): a tick, the item and when it counts, Show me or Done.
local function checkRow(F, i)
    local C = P()
    local row = CreateFrame("Frame", nil, F.content)
    row:SetSize(1, 40)
    if GuildOS.Kit then GuildOS.Kit:Rule(row) end
    row.tick = GuildOS.Style:Texture(row, "circle", "ARTWORK", 0)
    row.tick:SetSize(16, 16)
    row.tick:SetPoint("TOPLEFT", 0, -4)
    row.ring = GuildOS.Style:Texture(row, "ring", "ARTWORK", 1)
    row.ring:SetSize(18, 18)
    row.ring:SetPoint("CENTER", row.tick, "CENTER", 0, 0)
    row.title = text(row, SP.BODY, C.text, "button")
    row.title:SetPoint("TOPLEFT", 26, -3)
    row.desc = text(row, SP.META, C.textSoft)
    row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.show = fitButton(UI:CreateButton(row, L["Show me"], 70, SP.HIT), 64)
    row.show:SetPoint("RIGHT", 0, 0)
    row.done = UI:CreateBadge(row, L["Done"], GuildOS.Colors.ok)
    row.done:SetPoint("RIGHT", 0, 0)
    row.title:SetPoint("RIGHT", row.show, "LEFT", -8, 0)
    row.desc:SetPoint("RIGHT", row.show, "LEFT", -8, 0)
    row.show:SetScript("OnClick", function()
        local it = row.item
        if it and UI.Tour then UI.Tour:ShowMe(it.go, it.title, it.desc) end
    end)
    row.index = i
    function row:Fill(it)
        self.item = it
        local CC = P()
        self:SetShown(it ~= nil)
        if not it then return end
        self.title:SetText(it.title)
        self.desc:SetText(it.desc)
        self.show:SetShown(not it.done)
        self.done:SetShown(it.done)
        local c = it.done and CC.ok or (CC.paperLine or CC.line)
        self.tick:SetVertexColor(c.r, c.g, c.b, it.done and 1 or 0.35)
        self.ring:SetVertexColor(c.r, c.g, c.b, 1)
    end
    return row
end

-- A guide's tile: its picture and its title; a click opens the guide.
local function tile(holder, g)
    local C = P()
    local b = CreateFrame("Button", nil, holder)
    b:SetSize(TILE_W, TILE_PIC + 26)
    b.pic = CreateFrame("Frame", nil, b)
    b.pic:SetPoint("TOPLEFT", 0, 0)
    b.pic:SetSize(TILE_W, TILE_PIC)
    b.name = text(b, SP.META + 1, C.text, "button")
    b.name:SetPoint("TOPLEFT", b.pic, "BOTTOMLEFT", 2, -5)
    b.name:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.name:SetText(g.title)
    b:SetScript("OnClick", function() Help:OpenGuide(g.id) end)
    b:SetScript("OnEnter", function(self) local c = P().paperTitle or C.gold; self.name:SetTextColor(c.r, c.g, c.b) end)
    b:SetScript("OnLeave", function(self) local c = P().text; self.name:SetTextColor(c.r, c.g, c.b) end)
    b.guide = g
    function b:Relayout(w)
        self:SetWidth(w)
        self.pic:SetWidth(w)
        UI.Picture:Draw(self.pic, g.ill, w, TILE_PIC)
    end
    b:Relayout(TILE_W)
    return b
end

function Help:Build(F, isOfficer)
    local Ob = O()
    if not Ob then return end
    local role = Ob.Role()
    local C = P()
    F.help = {}

    -- Tours
    F:Section(L["Tours"])
    local rows = {}
    for _, id in ipairs({ "whatsnew", "member", "officer", "gm" }) do
        local r = trackRow(F, id)
        rows[#rows + 1] = r
        F:Row(r, { gap = 6, wide = true,
            shown = function() return id == "whatsnew" or Ob:TrackAllowed(id) end,
            place = function(obj, w) return obj:Lay(w) end })
    end
    F:Sync(function() for _, r in ipairs(rows) do r:Sync() end end)
    F.help.tours = rows

    -- Getting started
    F:Section(L["Get started"])
    if role == "member" then
        local list = {}
        for i = 1, 6 do
            local r = checkRow(F, i)
            list[i] = r
            F:Row(r, { gap = 2, wide = true, h = 40, shown = function() return r.item ~= nil end })
        end
        local hide = UI:SetButtonVariant(UI:CreateButton(F.content, L["Hide for 30 days"], 120, 20), "ghost")
        fitButton(hide, 60)
        hide:SetScript("OnClick", function() Ob:HideMemberList(); F:Refresh() end)
        local summary = text(F.content, SP.META, C.textSoft)
        summary:SetWordWrap(true)
        F:Row(summary, { gap = 8, wide = true })
        F:Row(hide, { gap = 4, h = 20 })
        F:Sync(function()
            local items = Ob:Checklist("member")
            for i, r in ipairs(list) do r:Fill(items[i]) end
            local done = Ob.DoneCount(items)
            summary:SetText(done == #items and L["You're all set!"]
                or string.format(L["%d of %d done. Each one ticks itself once it is true."], done, #items))
        end)
        F.help.check = list
    else
        local note = text(F.content, SP.META + 1, C.textSoft)
        note:SetWordWrap(true)
        F:Row(note, { gap = 2, wide = true })
        local open = fitButton(UI:CreateButton(F.content, L["Open the Hall"], 110, SP.HIT), 90)
        open:SetScript("OnClick", function()
            local gs = Ob.GuildStore()
            if gs then gs.hidden = nil end
            local f = UI.GetMainWindow and UI:GetMainWindow()
            if f then f:OpenRoom("salao", true) end
        end)
        F:Row(open, { gap = 8, h = SP.HIT })
        F:Sync(function()
            local items = Ob:Checklist("officer")
            note:SetText(string.format(L["The officers' card lives in the Hall: %d of %d done."], Ob.DoneCount(items), #items))
        end)
    end

    -- Guides
    F:Section(L["Guides"])
    local sub = text(F.content, SP.META, C.textSoft)
    sub:SetText(L["Short, with a picture. Show me runs the tour's chapter."])
    F:Row(sub, { gap = 2, wide = true, h = 14 })
    F.help.tiles = F:Grid(tile, Ob:Guides(role), TILE_PIC + 26, { colW = TILE_W, gap = 10 })

    -- More help
    F:Section(L["More help"])
    local why = text(F.content, SP.META, C.textSoft)
    why:SetWordWrap(true)
    why:SetText(L["The game can't open a browser: copy the link."])
    F:Row(why, { gap = 2, wide = true })
    local links = {}
    for _, spec in ipairs({ { L["The site"], Ob.URLS.site }, { L["The manual"], Ob.URLS.manual }, { "Discord", Ob.URLS.discord } }) do
        local lab = text(F.content, SP.META, C.textSoft)
        lab:SetText(spec[1])
        F:Row(lab, { gap = 8, h = 14 })
        local r = self:CopyRow(F.content, spec[2])
        links[#links + 1] = r
        F:Row(r, { gap = 3, wide = true, h = SP.FIELD })
    end
    F.help.links = links
    local cmd = CreateFrame("Frame", nil, F.content)
    cmd:SetSize(1, SP.HIT)
    cmd.text = text(cmd, SP.META + 1, C.text, "tableNum")
    cmd.text:SetPoint("LEFT", 0, 0)
    cmd.text:SetText("/gos help")
    cmd.hint = text(cmd, SP.META, C.textSoft)
    cmd.hint:SetPoint("LEFT", cmd.text, "RIGHT", 8, 0)
    cmd.hint:SetText(L["every command in chat"])
    cmd.reset = fitButton(UI:SetButtonVariant(UI:CreateButton(cmd, L["Show tips again"], 110, SP.HIT), "ghost"), 60)
    cmd.reset:SetPoint("RIGHT", 0, 0)
    cmd.reset:SetScript("OnClick", function()
        GuildOS:ShowDialog("GUILDOS_ONBOARD_RESET",
            L["Forget the tours and tips seen on this account, and show What's new again?"])
    end)
    cmd.hint:SetPoint("RIGHT", cmd.reset, "LEFT", -8, 0)
    cmd.hint:SetWordWrap(false)
    F:Row(cmd, { gap = 12, wide = true, h = SP.HIT })
    F.help.reset = cmd.reset
    local _ = isOfficer
end

-- Opened: the red dot on "?" goes, and the page says where each tour stands.
function Help:Opened()
    local Ob = O()
    if Ob then Ob:HelpOpened() end
    local f = GuildOS.RosterFrame
    if f and f.RefreshHelpDot then GuildOS:SafeCall(f.RefreshHelpDot, f) end
end
