----------------------------------------------------------------------
-- Guild OS - Raid Tools Panel (Raids › Raid Tools; #449, specs/salao/raidtools.md)
--
-- The raid leader's night on one screen. A header card on top: whose people it reads (the group as it is,
-- the site's raid, the guild online), which raid, and the four parts as pills:
--   Build   the roles against what the raid needs ("x of target", the danger ink when short), who signed
--           up and where they stand, "Invite all missing" (one click a step; one person a click on WoW:
--           Forever), who is missing said in raid chat;
--   Groups  the parties as boxes of names with what each brings (totems, aura), a suggestion, a click to
--           move a name, Apply (leader or assistant, out of combat) and Announce;
--   Ready   each person's checks (consumables, enchants, attunement, the fight's resistance, the addon),
--           the ready and role checks, the missing said in raid chat;
--   Fight   who does what on each boss (saved per raid, pre-filled from the site's plan), the pull timer,
--           the marks, and the cooldown HUD's switch with a preview of it.
-- Cards in two columns on the wood under the header (one under the other when narrow). Data and actions are
-- GuildOS.RaidTools (Rule 3 / Rule 10); the HUD is Modules/RaidHUD.lua.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local SUBTABS = {
    { key = "build",  label = L["Build"] },
    { key = "groups", label = L["Groups"] },
    { key = "ready",  label = L["Ready"] },
    { key = "fight",  label = L["Fight"] },
}

local GAP = UI.GAP
local SCROLL_R = UI.SCROLL_GUTTER - UI.GAP
local PAD = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
local CARD_TOP = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
local ROW_H = 24
local HEAD_H = 102          -- the header card: title, the pickers, the pills
local TWO_COLS = 620        -- the content's width from which the cards stand in two columns
local DASH = "\226\128\148"
local ICON_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t"
local ICON_NONE = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:12:12|t"

local ROLE_WORD = { TANK = L["Tanks"], HEALER = L["Healers"], DPS = L["Damage"] }
local ROLE_ONE = { TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] }
local STATUS_WORD = {
    signed = L["signed"], standby = L["standby"], tentative = L["tentative"], pending = L["no answer"],
    extra = L["not signed"],
}
local STATUS_COLOR = { signed = "ok", standby = "info", tentative = "warn", pending = "label", extra = "warn" }
local SOURCE_WORD = { group = L["Current group"], site = L["The site's raid"], guild = L["Online guild members"] }

local function RT() return GuildOS.RaidTools end

----------------------------------------------------------------------
-- Drawing helpers: a pool of regions per card, handed out again by id on every refresh (no frame leaks)
----------------------------------------------------------------------
local function Pool(host)
    local pool = { host = host, items = {} }
    function pool:Begin()
        for _, it in pairs(self.items) do it:Hide() end
    end
    function pool:Take(id, make)
        local it = self.items[id]
        if not it then
            it = make(self.host)
            self.items[id] = it
        end
        it:ClearAllPoints()
        it:Show()
        return it
    end
    return pool
end

-- The colour `c` as the frame's surface prints it (the paper's inks on a card).
local function ink(fs, c)
    local col = UI:Ink(fs, c)
    fs:SetTextColor(col.r, col.g, col.b)
end

local function Text(pool, id, text, size, color)
    local fs = pool:Take(id, function(h) return UI:CreateText(h, "", size or 12) end)
    GuildOS:ApplyFont(fs, size or 12)
    fs:SetText(text or "")
    ink(fs, color or C.text)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetJustifyH("LEFT")
    fs:SetWidth(0)
    return fs
end

local function ClassText(pool, id, text, class, size)
    local fs = Text(pool, id, text, size)
    local r, g, b = UI:InkFor(fs, "class", class)
    fs:SetTextColor(r, g, b)
    return fs
end

local function Button(pool, id, label, variant, onClick, h)
    local btn = pool:Take(id, function(host) return UI:CreateButton(host, "", 60, h or 22) end)
    UI:SetButtonVariant(btn, variant or "secondary")
    btn.label:SetText(label)
    btn:SetWidth(math.ceil(btn.label:GetStringWidth() or 40) + (variant == "ghost" and 4 or 22))
    btn:SetScript("OnClick", onClick)
    btn:Enable()
    UI:SetDisabledReason(btn, nil)
    return btn
end

local function Badge(pool, id, text, color)
    local b = pool:Take(id, function(host) return UI:CreateBadge(host, "", color) end)
    b:SetText(text, color)
    return b
end

-- A row's 1px rule along its bottom, in the surface's line colour.
local function Rule(pool, id, y, x0, x1)
    local t = pool:Take(id, function(h)
        local tex = h:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        tex:SetHeight(1)
        return tex
    end)
    local lc = pool.host.lineColor or C.line
    t:SetVertexColor(lc.r, lc.g, lc.b, 1)
    t:SetPoint("TOPLEFT", pool.host, "TOPLEFT", x0, -y)
    t:SetPoint("TOPRIGHT", pool.host, "TOPLEFT", x1, -y)
    return t
end

-- A card on the part's content, its pool on it, placed and sized by Lay.
local function Card(content, title, dark)
    local card = UI:CreateCard(content, title, { dark = dark })
    card.pool = Pool(card)
    return card
end

local function Lay(card, x, y, w, h)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", x, -y)
    card:SetSize(w, h)
end

-- The two columns of a part: the left card's x and width, the right card's, and whether they stack.
local function Columns(W, leftShare)
    if W < TWO_COLS then return 0, W, 0, W, true end
    local lw = math.floor((W - GAP) * (leftShare or 0.6))
    return 0, lw, lw + GAP, W - lw - GAP, false
end

-- The line under a button bar that says what the last click did, or why a button is off.
local function Note(pool, id, text, color, x, y, w)
    local fs = Text(pool, id, text, 11, color or C.textSoft)
    fs:SetPoint("TOPLEFT", x, -y)
    if w then
        fs:SetWidth(w)
        if fs.SetWordWrap then fs:SetWordWrap(true) end
    end
    return fs
end

local function NoteHeight(fs, w)
    if not fs or (fs:GetText() or "") == "" then return 0 end
    -- The lines the text wraps to, from its one-line width: the same answer before and after the client lays it.
    local width = fs:GetStringWidth() or 0
    local lines = (w and w > 0) and math.max(1, math.ceil(width * 1.08 / w)) or 1
    return lines * 15
end

-- A row of buttons from x, wrapping at w. Returns the y under them.
local function ButtonRow(buttons, x, y, w)
    local cx, cy = x, y
    for _, b in ipairs(buttons) do
        local bw = b:GetWidth()
        if cx > x and cx + bw > x + w then cx, cy = x, cy + 28 end
        b:SetPoint("TOPLEFT", cx, -cy)
        cx = cx + bw + 6
    end
    return cy + 28
end

local function setOff(btn, reason)
    if reason then
        btn:Disable()
        UI:SetDisabledReason(btn, reason)
    end
end

local function className(class)
    local t = LOCALIZED_CLASS_NAMES_MALE
    return (t and t[class]) or class or ""
end

----------------------------------------------------------------------
-- The state shared by the parts: the people of the source, the raid, its targets
----------------------------------------------------------------------
local function Snapshot()
    local R = RT()
    local kind = R:SourceKind()
    local roster = kind == "site" and R:SiteRoster() or nil
    local people, label = R:People(kind, roster)
    local key, size = R:CurrentInstance(kind, roster)
    local targets = R:Targets(key, size)
    return { kind = kind, roster = roster, people = people, label = label, inst = key, targets = targets }
end

----------------------------------------------------------------------
-- BUILD: the roles against the targets, who signed up, the invites
----------------------------------------------------------------------
local function BuildBuild(panel, content)
    local roles = Card(content, L["Roles"], true)
    local roster = Card(content, L["Who's coming"], false)
    local buffs = Card(content, L["Buffs and cooldowns"], true)
    local status = { text = "", color = C.textSoft }

    -- What a click of "Invite all missing" did, and who it passed over.
    local function names(list)
        local out = {}
        for i, p in ipairs(list) do out[i] = RT().ShortName(p.name) end
        return table.concat(out, ", ")
    end
    local function inviteSaid(res)
        local text, color
        if res.kind == "blocked" then return { text = res.reason, color = C.warn } end
        if res.kind == "invite" then
            text = string.format(L["Invited: %s."], table.concat(res.names, ", "))
            if (res.left or 0) > 0 then text = text .. " " .. string.format(L["%d left: click again."], res.left) end
            color = C.ok
        elseif res.kind == "convert" then
            text, color = L["The party is a raid now: click again to invite the rest."], C.ok
        elseif res.kind == "wait" then
            text, color = L["Waiting for the invited to answer."], C.textSoft
        else
            text, color = L["Everyone signed up is here or invited."], C.ok
        end
        local sk = res.skipped or {}
        if sk.banned and #sk.banned > 0 then text = text .. " " .. string.format(L["Banned, not invited: %s."], names(sk.banned)) end
        if sk.offline and #sk.offline > 0 then text = text .. " " .. string.format(L["Offline, not invited: %s"], names(sk.offline)) end
        return { text = text, color = color }
    end

    return function(snap, W)
        local R = RT()
        local lx, lw, rx, rw, stacked = Columns(W, 0.6)

        -- Right: the roles, the targets, the invite.
        local p = roles.pool
        p:Begin()
        local counts = R.CountRoles(snap.people)
        local gaps = R.RoleGaps(counts, snap.targets)
        local inner = rw - 2 * PAD
        local boxW = math.floor((inner - 2 * 6) / 3)
        local y = CARD_TOP
        for i, g in ipairs(gaps) do
            local chip = p:Take("box" .. i, function(h) return UI:CreateMetricChip(h, "", "") end)
            chip:SetSize(boxW, 54)
            chip:SetPoint("TOPLEFT", PAD + (i - 1) * (boxW + 6), -y)
            chip:SetValue(string.format(L["%d of %d"], g.have, g.want))
            local col = g.short > 0 and C.danger or C.ok
            chip.value:SetTextColor(col.r, col.g, col.b)
            chip.label:SetText(ROLE_WORD[g.role])
        end
        y = y + 54 + 10
        -- The targets, the raid leader's for this raid: − and + by tanks and healers.
        local tx = PAD
        local tl = Text(p, "tLabel", L["Targets:"], 11, C.textSoft)
        tl:SetPoint("TOPLEFT", tx, -(y + 4))
        tx = tx + math.ceil(tl:GetStringWidth() or 40) + 8
        for _, role in ipairs({ "tank", "healer" }) do
            local word = Text(p, "tw" .. role, role == "tank" and L["Tanks"] or L["Healers"], 11, C.text)
            word:SetPoint("TOPLEFT", tx, -(y + 4))
            tx = tx + math.ceil(word:GetStringWidth() or 30) + 4
            local minus = Button(p, "tm" .. role, "\226\136\146", "chip", function()
                R:SetTarget(snap.inst, role, (snap.targets[role] or 0) - 1); panel.Refresh()
            end, 18)
            minus:SetWidth(20)
            minus:SetPoint("TOPLEFT", tx, -(y + 2))
            local num = Text(p, "tn" .. role, tostring(snap.targets[role] or 0), 12, C.text)
            num:SetPoint("LEFT", minus, "RIGHT", 4, 0)
            local plus = Button(p, "tp" .. role, "+", "chip", function()
                R:SetTarget(snap.inst, role, (snap.targets[role] or 0) + 1); panel.Refresh()
            end, 18)
            plus:SetWidth(20)
            plus:SetPoint("LEFT", minus, "RIGHT", 22, 0)
            if not snap.inst then setOff(minus, L["Pick a raid first."]); setOff(plus, L["Pick a raid first."]) end
            tx = tx + 20 + 22 + 20 + 12
        end
        y = y + 26
        local extra = {}
        extra[#extra + 1] = string.format(L["%d players for %d seats"], counts.total, snap.targets.size)
        if counts.UNKNOWN > 0 then extra[#extra + 1] = string.format(L["%d without a known role"], counts.UNKNOWN) end
        if snap.targets.edited then extra[#extra + 1] = L["your targets"] end
        local ex = Note(p, "extra", table.concat(extra, "  \194\183  "), C.textSoft, PAD, y, inner)
        y = y + NoteHeight(ex, inner) + 10

        -- The invite and the announcement.
        local missing = R.Missing(snap.people)
        local invite = Button(p, "invite", missing[1] and string.format(L["Invite all missing (%d)"], #missing) or L["Invite all missing"],
            "primary", function()
                status = inviteSaid(R:InviteStep(snap.people))
                panel.Refresh()
            end)
        if snap.kind ~= "site" then setOff(invite, L["Invites go from the site's raid: pick it above."])
        elseif #missing == 0 then setOff(invite, L["Everyone signed up is here."])
        elseif GuildOS.Compat.InCombat() then setOff(invite, L["Not during combat."]) end
        local say = Button(p, "say", L["Announce missing"], "secondary", function()
            local lines = R.MissingLines(gaps, missing)
            local n, err = R:Say("missing", lines)
            status = { text = err or string.format(L["Said in %d line(s)."], n), color = err and C.warn or C.ok }
            panel.Refresh()
        end)
        y = ButtonRow({ invite, say }, PAD, y, inner)
        local st = Note(p, "status", status.text, status.color, PAD, y, inner)
        y = y + NoteHeight(st, inner) + PAD
        local rolesH = y

        -- Under the roles: what the raid's classes bring (the buffs and the cooldowns), compact.
        local b = buffs.pool
        b:Begin()
        local classCounts = {}
        for _, person in ipairs(snap.people) do
            if person.status ~= "standby" and person.status ~= "pending" and person.status ~= "tentative" and person.class ~= "" then
                classCounts[person.class] = (classCounts[person.class] or 0) + 1
            end
        end
        local by = CARD_TOP
        local half = math.floor(inner / 2)
        local function list(defs, x, idp)
            local yy = by
            for i, d in ipairs(R:ResolveCoverage(defs, classCounts)) do
                local mark = Text(b, idp .. "m" .. i, d.covered and ICON_DONE or ICON_NONE, 11, C.text)
                mark:SetPoint("TOPLEFT", x, -yy)
                local nm = Text(b, idp .. "n" .. i, d.name, 11, d.covered and C.text or C.label)
                nm:SetPoint("TOPLEFT", x + 14, -yy)
                nm:SetWidth(half - 18)
                yy = yy + 16
            end
            return yy
        end
        local bh = math.max(list(R.BUFFS, PAD, "b"), list(R.COOLDOWNS, PAD + half, "c"))
        local buffsH = bh + PAD - 6

        -- Left: the roster.
        local q = roster.pool
        q:Begin()
        local iw = lw - 2 * PAD
        local cRole, cStatus, cGroup = math.floor(iw * 0.36), math.floor(iw * 0.55), math.floor(iw * 0.78)
        local head = q:Take("head", function(h) return UI:CreateTableHeader(h, 20) end)
        head:SetPoint("TOPLEFT", PAD, -CARD_TOP)
        head:SetWidth(iw)
        local hy = CARD_TOP
        local cols = { { L["Name"], 0 }, { L["Role"], cRole }, { snap.kind == "site" and L["Sign-up"] or L["Class"], cStatus },
                       { L["Group"], cGroup } }
        for i, c in ipairs(cols) do
            local h = q:Take("h" .. i, function(host) return UI:CreateHeaderText(host, "", 10) end)
            h:SetText(c[1])
            h:SetPoint("TOPLEFT", PAD + c[2] + 4, -(hy + 5))
        end
        local ry = hy + 22
        if #snap.people == 0 then
            local empty = snap.kind == "site" and not snap.roster and L["No raid from the site yet. Bring the roster in from Web (/gos web)."]
                or (snap.kind == "group" and L["You are not in a group."]) or L["Nobody here."]
            local e = Note(q, "empty", empty, C.textSoft, PAD, ry + 4, iw)
            ry = ry + 8 + NoteHeight(e, iw)
        end
        for i, person in ipairs(snap.people) do
            local name = ClassText(q, "n" .. i, R.ShortName(person.name), person.class, 12)
            name:SetPoint("TOPLEFT", PAD + 4, -(ry + 6))
            name:SetWidth(cRole - 8)
            local roleText = person.role and ROLE_ONE[person.role] or "?"
            local role = Text(q, "r" .. i, roleText .. (person.guessed and "*" or ""), 12, person.role and C.text or C.label)
            role:SetPoint("TOPLEFT", PAD + cRole + 4, -(ry + 6))
            if snap.kind == "site" then
                local word = STATUS_WORD[person.status]
                if word then
                    local badge = Badge(q, "s" .. i, word, C[STATUS_COLOR[person.status]] or C.label)
                    badge:SetPoint("TOPLEFT", PAD + cStatus + 4, -(ry + 4))
                end
            else
                local cl = Text(q, "s" .. i, className(person.class), 12, C.textSoft)
                cl:SetPoint("TOPLEFT", PAD + cStatus + 4, -(ry + 6))
            end
            if person.inGroup then
                local g = Text(q, "g" .. i, (person.group and person.group > 0) and string.format(L["G%d"], person.group) or L["yes"], 12, C.text)
                g:SetPoint("TOPLEFT", PAD + cGroup + 4, -(ry + 6))
            elseif person.status == "signed" then
                local inv = Button(q, "i" .. i, L["Invite"], "ghost", function()
                    local ok, why = R:InviteOne(person)
                    if not ok then GuildOS:Print(why) end
                    panel.Refresh()
                end, 18)
                inv:SetPoint("TOPLEFT", PAD + cGroup + 2, -(ry + 3))
                local miss = Text(q, "g" .. i, L["missing"], 11, C.danger)
                miss:SetPoint("LEFT", inv, "RIGHT", 6, 0)
            else
                local g = Text(q, "g" .. i, DASH, 12, C.label)
                g:SetPoint("TOPLEFT", PAD + cGroup + 4, -(ry + 6))
            end
            Rule(q, "l" .. i, ry + ROW_H, PAD, PAD + iw)
            ry = ry + ROW_H
        end
        local foot = Note(q, "foot", L["* a guess from the class"], C.label, PAD, ry + 6)
        foot:SetShown(false)
        for _, person in ipairs(snap.people) do if person.guessed then foot:SetShown(true) break end end
        local rosterH = ry + (foot:IsShown() and 26 or 10)

        if stacked then
            Lay(roles, 0, 0, W, rolesH)
            Lay(buffs, 0, rolesH + GAP, W, buffsH)
            Lay(roster, 0, rolesH + GAP + buffsH + GAP, W, rosterH)
            return rolesH + buffsH + rosterH + 2 * GAP
        end
        Lay(roster, lx, 0, lw, rosterH)
        Lay(roles, rx, 0, rw, rolesH)
        Lay(buffs, rx, rolesH + GAP, rw, buffsH)
        return math.max(rosterH, rolesH + GAP + buffsH)
    end
end

----------------------------------------------------------------------
-- GROUPS: the parties, a suggestion, a click to move, Apply and Announce
----------------------------------------------------------------------
local function BuildGroups(panel, content)
    local box = Card(content, L["Parties"], false)
    local side = Card(content, L["Arrange"], true)
    local status = { text = "", color = C.textSoft }
    local draft, draftOf, picked
    local edited = false   -- moved or suggested by hand: the live raid no longer redraws it

    -- The parties the screen starts from: the raid as it is for the group; the site's planned groups, else
    -- a suggestion, for the site's raid and the guild.
    local function fresh(snap)
        local R = RT()
        local groups = math.max(1, math.ceil((snap.targets.size or 25) / 5))
        if snap.kind == "group" then
            local parties = R.PartiesOf(snap.people)
            local any = false
            for _, list in ipairs(parties) do if #list > 0 then any = true end end
            if any then return parties end
        end
        local coming = {}
        for _, p in ipairs(snap.people) do
            if p.status == "signed" or p.status == "here" or p.status == "extra" then coming[#coming + 1] = p end
        end
        if snap.kind == "site" then
            local planned, any = {}, false
            for g = 1, 8 do planned[g] = {} end
            for _, p in ipairs(coming) do
                local g = tonumber(p.plannedGroup)
                if g and g >= 1 and g <= 8 and #planned[g] < 5 then table.insert(planned[g], p); any = true end
            end
            if any then return planned end
        end
        return R.SuggestGroups(coming, groups)
    end

    local function findPerson(key)
        for g, list in ipairs(draft or {}) do
            for i, p in ipairs(list) do if p.key == key then return g, i end end
        end
    end

    local function move(key, toGroup, swapKey)
        local g, i = findPerson(key)
        if not g then return end
        if swapKey then
            local g2, i2 = findPerson(swapKey)
            if not g2 or g2 == g then return end
            draft[g][i], draft[g2][i2] = draft[g2][i2], draft[g][i]
            edited = true
            return
        end
        if g == toGroup then return end
        edited = true
        if #draft[toGroup] >= 5 then
            status = { text = string.format(L["Group %d is full: click a name in it to swap."], toGroup), color = C.warn }
            return
        end
        table.insert(draft[toGroup], table.remove(draft[g], i))
    end

    return function(snap, W)
        local R = RT()
        local sig = snap.kind .. "|" .. tostring(snap.roster and snap.roster.raidId)
        if not draft or draftOf ~= sig or not edited then
            if draftOf ~= sig then picked, edited = nil, false end
            draft, draftOf = fresh(snap), sig
        end
        local lx, lw, rx, rw, stacked = Columns(W, 0.66)
        if stacked then lw, rw = W, W end

        -- Left: the party boxes.
        local p = box.pool
        p:Begin()
        local iw = lw - 2 * PAD
        local cols = iw >= 600 and 3 or (iw >= 380 and 2 or 1)
        local bw = math.floor((iw - (cols - 1) * 8) / cols)
        local shown = math.max(1, math.ceil((snap.targets.size or 25) / 5))
        for g = shown + 1, 8 do if draft[g] and #draft[g] > 0 then shown = g end end
        local CH = 22
        local boxH = 24 + 5 * (CH + 4) + 20
        for g = 1, shown do
            draft[g] = draft[g] or {}
            local col, rowN = (g - 1) % cols, math.floor((g - 1) / cols)
            local bx, by = PAD + col * (bw + 8), CARD_TOP + rowN * (boxH + 8)
            local frame = p:Take("box" .. g, function(h)
                return CreateFrame("Button", nil, h)
            end)
            frame:SetPoint("TOPLEFT", bx, -by)
            frame:SetSize(bw, boxH)
            local fill = p:Take("fill" .. g, function(h) return h:CreateTexture(nil, "BACKGROUND") end)
            fill:SetTexture("Interface\\Buttons\\WHITE8x8")
            fill:SetPoint("TOPLEFT", frame, "TOPLEFT")
            fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
            local lc = C.paperRule or C.paperLine
            fill:SetVertexColor(lc.r, lc.g, lc.b, 0.35)
            frame:SetScript("OnClick", function()
                if picked then move(picked, g); picked = nil; panel.Refresh() end
            end)
            local title = Text(p, "t" .. g, string.format(L["Group %d"], g), 12, C.paperTitle)
            GuildOS:ApplyFont(title, 12, "button")
            title:SetPoint("TOPLEFT", bx + 8, -(by + 6))
            local count = Text(p, "c" .. g, #draft[g] .. "/5", 11, C.textSoft)
            count:SetPoint("TOPRIGHT", p.host, "TOPLEFT", bx + bw - 8, -(by + 7))
            for i = 1, 5 do
                local person = draft[g][i]
                if person then
                    local chip = Button(p, "m" .. g .. "." .. i, R.ShortName(person.name), "chip", function()
                        if picked == person.key then picked = nil
                        elseif picked then
                            local pg = findPerson(picked)
                            if pg == g then picked = person.key else move(picked, nil, person.key); picked = nil end
                        else picked = person.key end
                        panel.Refresh()
                    end, CH)
                    chip:SetWidth(bw - 16)
                    chip:SetFrameLevel(frame:GetFrameLevel() + 2)   -- over its party's box, which takes the drop
                    chip:SetPoint("TOPLEFT", bx + 8, -(by + 24 + (i - 1) * (CH + 4)))
                    local r, gg, b = UI:InkFor(chip, "class", person.class)
                    chip.baseLabelColor = { r, gg, b }
                    UI:SetSelected(chip, picked == person.key)
                end
            end
            -- What the party brings: totems, aura; what it lacks in the danger ink.
            local words = R.CoverageWords(draft[g])
            local parts = {}
            for _, w in ipairs(words) do
                local c = UI:Ink(box, w.ok and C.ok or C.danger)
                parts[#parts + 1] = GuildOS:ColorText(w.ok and w.text or string.format(L["no %s"], w.text:lower()), c.r, c.g, c.b)
            end
            local cov = Text(p, "v" .. g, table.concat(parts, " \194\183 "), 11, C.textSoft)
            cov:SetPoint("TOPLEFT", bx + 8, -(by + boxH - 17))
            cov:SetWidth(bw - 16)
        end
        local rowsN = math.ceil(shown / cols)
        local help = Note(p, "help", L["Click a name, then the party it goes to; click two names to swap them."], C.textSoft,
            PAD, CARD_TOP + rowsN * (boxH + 8) + 2, iw)
        local boxCardH = CARD_TOP + rowsN * (boxH + 8) + NoteHeight(help, iw) + PAD

        -- Right: the actions.
        local s = side.pool
        s:Begin()
        local inner = rw - 2 * PAD
        local y = CARD_TOP
        local suggest = Button(s, "suggest", L["Suggest"], "secondary", function()
            local everyone = {}
            for _, list in ipairs(draft) do for _, person in ipairs(list) do everyone[#everyone + 1] = person end end
            draft = R.SuggestGroups(everyone, math.max(1, math.ceil(#everyone / 5)))
            picked, edited = nil, true
            status = { text = L["A suggestion: shamans and paladins spread, tanks together. Apply it, or move names first."], color = C.textSoft }
            panel.Refresh()
        end)
        local apply = Button(s, "apply", L["Apply"], "primary", function()
            local n, err = R:ApplyGroups(draft)
            if not err then edited = false end
            status = { text = err or string.format(L["%d move(s) sent to the raid."], n), color = err and C.warn or C.ok }
            panel.Refresh()
        end)
        local okArrange, why = R:CanArrange()
        if not okArrange then setOff(apply, why) end
        local say = Button(s, "say", L["Announce"], "secondary", function()
            local n, err = R:Say("groups", R.GroupLines(draft))
            status = { text = err or string.format(L["Said in %d line(s)."], n), color = err and C.warn or C.ok }
            panel.Refresh()
        end)
        local reset = Button(s, "reset", L["As it is"], "ghost", function()
            draft, picked, edited = fresh(snap), nil, false
            status = { text = "", color = C.textSoft }
            panel.Refresh()
        end)
        y = ButtonRow({ apply, suggest, say, reset }, PAD, y, inner)
        if not okArrange then
            local w = Note(s, "why", why, C.label, PAD, y, inner)
            y = y + NoteHeight(w, inner) + 4
        end
        local st = Note(s, "status", status.text, status.color, PAD, y, inner)
        y = y + NoteHeight(st, inner) + 8
        local about = Note(s, "about", L["Each party shows what it brings: a shaman's totems, a paladin's aura. Moves go through the game only for the raid leader or an assistant, out of combat."],
            C.textSoft, PAD, y, inner)
        y = y + NoteHeight(about, inner) + PAD
        local sideH = y

        if stacked then
            Lay(side, 0, 0, W, sideH)
            Lay(box, 0, sideH + GAP, W, boxCardH)
            return sideH + GAP + boxCardH
        end
        Lay(box, lx, 0, lw, boxCardH)
        Lay(side, rx, 0, rw, sideH)
        return math.max(boxCardH, sideH)
    end
end

----------------------------------------------------------------------
-- READY: each person's checks, the ready and role checks
----------------------------------------------------------------------
local READY_WORD = { ready = L["ready"], warn = L["check"], notready = L["not ready"], nodata = L["no data"] }
local READY_COLOR = { ready = "ok", warn = "warn", notready = "danger", nodata = "label" }

local function BuildReady(panel, content)
    local tbl = Card(content, L["Readiness"], false)
    local side = Card(content, L["Checks"], true)
    local status = { text = "", color = C.textSoft }

    return function(snap, W)
        local R = RT()
        local rows, school = R:ReadyRows(snap.people, snap.inst)
        local def = snap.inst and R:Instance(snap.inst)
        local lx, lw, rx, rw, stacked = Columns(W, 0.66)
        if stacked then lw, rw = W, W end

        -- Left: the table.
        local p = tbl.pool
        p:Begin()
        local iw = lw - 2 * PAD
        local cols = { { L["Name"], 0 }, { L["Status"], 0.27 }, { L["Consum."], 0.45 }, { L["Enchants"], 0.59 } }
        if def and def.attune then cols[#cols + 1] = { L["Attuned"], 0.73 } end
        if school then cols[#cols + 1] = { school.label, def.attune and 0.83 or 0.73 } end
        cols[#cols + 1] = { L["Addon"], 0.92 }
        local head = p:Take("head", function(h) return UI:CreateTableHeader(h, 20) end)
        head:SetPoint("TOPLEFT", PAD, -CARD_TOP)
        head:SetWidth(iw)
        for i, c in ipairs(cols) do
            local h = p:Take("h" .. i, function(host) return UI:CreateHeaderText(host, "", 10) end)
            h:SetText(c[1])
            h:SetPoint("TOPLEFT", PAD + math.floor(iw * c[2]) + 4, -(CARD_TOP + 5))
        end
        for i = #cols + 1, 7 do local h = p.items["h" .. i]; if h then h:Hide() end end
        local x = {}
        for i, c in ipairs(cols) do x[i] = PAD + math.floor(iw * c[2]) + 4 end
        local ry = CARD_TOP + 22
        if #rows == 0 then
            local e = Note(p, "empty", L["Nobody to check: pick who above."], C.textSoft, PAD, ry + 4, iw)
            ry = ry + 8 + NoteHeight(e, iw)
        end
        local function cell(id, i, text, color, y)
            local fs = Text(p, id, text, 12, color)
            fs:SetPoint("TOPLEFT", x[i], -(y + 6))
            return fs
        end
        for n, r in ipairs(rows) do
            local nm = ClassText(p, "n" .. n, R.ShortName(r.name), r.class, 12)
            nm:SetPoint("TOPLEFT", x[1], -(ry + 6))
            nm:SetWidth(math.floor(iw * 0.26))
            local b = Badge(p, "b" .. n, READY_WORD[r.status], C[READY_COLOR[r.status]])
            b:SetPoint("TOPLEFT", x[2], -(ry + 4))
            cell("c" .. n, 3, r.cons == nil and DASH or (r.cons == 0 and L["ok"] or string.format(L["%d missing"], r.cons)),
                r.cons == nil and C.label or (r.cons == 0 and C.text or C.danger), ry)
            cell("e" .. n, 4, r.ench == nil and DASH or (r.ench == 0 and L["ok"] or string.format(L["%d missing"], r.ench)),
                r.ench == nil and C.label or (r.ench == 0 and C.text or C.danger), ry)
            local ci = 5
            if def and def.attune then
                cell("a" .. n, ci, r.attuned == nil and DASH or (r.attuned and L["yes"] or L["no"]),
                    r.attuned == nil and C.label or (r.attuned and C.text or C.danger), ry)
                ci = ci + 1
            else
                local old = p.items["a" .. n]; if old then old:Hide() end
            end
            if school then
                cell("r" .. n, ci, r.resist == nil and DASH or tostring(r.resist),
                    r.resist == nil and C.label or (r.resistOk and C.text or C.warn), ry)
                ci = ci + 1
            else
                local old = p.items["r" .. n]; if old then old:Hide() end
            end
            cell("d" .. n, ci, r.addon and L["yes"] or L["no"], r.addon and C.text or C.warn, ry)
            Rule(p, "l" .. n, ry + ROW_H, PAD, PAD + iw)
            ry = ry + ROW_H
        end
        local tblH = ry + 10

        -- Right: the summary and the buttons.
        local s = side.pool
        s:Begin()
        local inner = rw - 2 * PAD
        local c = R.ReadySummary(rows)
        local sum = Note(s, "sum", string.format(L["%d ready · %d to check · %d not ready · %d no data"],
            c.ready, c.warn, c.notready, c.nodata), C.text, PAD, CARD_TOP, inner)
        local y = CARD_TOP + NoteHeight(sum, inner) + 8
        local function said(okv, err)
            status = { text = okv and L["Sent."] or (err or L["The game refused it."]), color = okv and C.ok or C.warn }
            panel.Refresh()
        end
        local rc = Button(s, "rc", L["Ready check"], "primary", function() said(R:ReadyCheck()) end)
        local role = Button(s, "role", L["Role check"], "secondary", function() said(R:RoleCheck()) end)
        if not GuildOS.Compat.CanRolePoll() then setOff(role, L["Not available on this client."]) end
        local cons = Button(s, "cons", L["Check Consumables"], "secondary", function()
            if GuildOS.ShowConsumablePopup and GuildOS.ConsumableChecker then GuildOS:ShowConsumablePopup() end
            panel.Refresh()
        end)
        if not GuildOS.ConsumableChecker then setOff(cons, L["Not available on this client."]) end
        local say = Button(s, "say", L["Announce missing"], "secondary", function()
            local n, err = R:Say("ready", R.ReadyLines(rows))
            status = { text = err or string.format(L["Said in %d line(s)."], n), color = err and C.warn or C.ok }
            panel.Refresh()
        end)
        y = ButtonRow({ rc, role, cons, say }, PAD, y, inner)
        local st = Note(s, "status", status.text, status.color, PAD, y, inner)
        y = y + NoteHeight(st, inner) + 8
        local about = Note(s, "about", L["Consumables count from the last check (12 hours); enchants, attunements and resistances from what each member's addon synced."],
            C.textSoft, PAD, y, inner)
        y = y + NoteHeight(about, inner) + PAD
        local sideH = y

        if stacked then
            Lay(side, 0, 0, W, sideH)
            Lay(tbl, 0, sideH + GAP, W, tblH)
            return sideH + GAP + tblH
        end
        Lay(tbl, lx, 0, lw, tblH)
        Lay(side, rx, 0, rw, sideH)
        return math.max(tblH, sideH)
    end
end

----------------------------------------------------------------------
-- FIGHT: assignments per boss, the pull timer, the marks, the HUD
----------------------------------------------------------------------
local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local function BuildFight(panel, content)
    local plan = Card(content, L["Assignments"], false)
    local side = Card(content, L["In combat"], true)
    local status = { text = "", color = C.textSoft }
    local boss
    local rows, from

    return function(snap, W)
        local R = RT()
        local lx, lw, rx, rw, stacked = Columns(W, 0.6)
        if stacked then lw, rw = W, W end
        local bosses = R:Bosses(snap.inst, snap.roster)
        local found = false
        for _, b in ipairs(bosses) do if b == boss then found = true end end
        if not found then boss, rows = bosses[1], nil end
        local sig = tostring(snap.inst) .. "|" .. tostring(boss)
        if not rows or rows.sig ~= sig then
            rows, from = R:Assignments(snap.inst, boss, snap.roster)
            rows.sig = sig
        end
        local function save()
            R:SaveAssignments(snap.inst, boss, rows)
            from = "saved"
        end

        -- Left: the boss and who does what.
        local p = plan.pool
        p:Begin()
        local iw = lw - 2 * PAD
        local y = CARD_TOP
        local dd = p:Take("boss", function(h)
            local d = UI:CreateDropdown(h, 220, 22)
            return d
        end)
        local opts = {}
        for _, b in ipairs(bosses) do opts[#opts + 1] = { value = b, text = b } end
        dd:SetOptions(opts)
        dd:SetPlaceholder(#bosses == 0 and L["No bosses for this raid"] or L["Pick a boss"])
        dd:SetValue(boss)
        dd:SetWidth(math.min(260, iw))
        dd:SetPoint("TOPLEFT", PAD, -y)
        dd.onSelect = function(_, v) boss, rows = v, nil; panel.Refresh() end
        local src = from == "plan" and L["from the site's plan"] or (from == "saved" and L["saved for this raid"] or L["not set yet"])
        local fromFS = Text(p, "from", src, 11, from == "plan" and C.info or C.textSoft)
        fromFS:SetPoint("LEFT", dd, "RIGHT", 10, 0)
        y = y + 32
        local people = {}
        for _, person in ipairs(snap.people) do
            if person.status ~= "pending" and person.status ~= "tentative" then
                people[#people + 1] = { value = person.name, text = R.ShortName(person.name) }
            end
        end
        table.sort(people, function(a, b) return a.text:lower() < b.text:lower() end)
        table.insert(people, 1, { value = "", text = DASH })
        local marks = { { value = "", text = DASH } }
        for i, m in ipairs(R.MARKS) do marks[#marks + 1] = { value = m, text = string.format("|T" .. MARK_ICON .. ":14:14|t", i) } end
        local markW, delW = 52, 22
        local whoW = math.floor((iw - markW - delW - 12) * 0.45)
        local taskW = iw - markW - delW - whoW - 12
        for i, r in ipairs(rows) do
            local md = p:Take("mk" .. i, function(h) return UI:CreateDropdown(h, markW, 22) end)
            md:SetOptions(marks)
            md:SetValue(r.mark or "")
            md:SetPoint("TOPLEFT", PAD, -y)
            md.onSelect = function(_, v) r.mark = v ~= "" and v or nil; save(); panel.Refresh() end
            local box = p:Take("tk" .. i, function(h)
                local b = UI:CreateInput(h, 100, 22, { max = 60, placeholder = L["Task"] })
                b:HookScript("OnEditFocusLost", function(self) if self.onCommit then self.onCommit(self:GetText()) end end)
                b:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
                return b
            end)
            box:SetWidth(taskW)
            box:SetPoint("TOPLEFT", PAD + markW + 4, -y)
            if not box:HasFocus() then box:SetText(r.task or "") end
            box.onCommit = function(text)
                if text ~= (r.task or "") then r.task = text; save() end
            end
            local wd = p:Take("wh" .. i, function(h) return UI:CreateDropdown(h, 100, 22) end)
            local opt = people
            if r.who and r.who ~= "" then
                local known = false
                for _, o in ipairs(people) do if o.value == r.who then known = true end end
                if not known then
                    opt = { unpack(people) }
                    opt[#opt + 1] = { value = r.who, text = R.ShortName(r.who) }
                end
            end
            wd:SetOptions(opt)
            wd:SetValue(r.who or "")
            wd:SetWidth(whoW)
            wd:SetPoint("TOPLEFT", PAD + markW + 4 + taskW + 4, -y)
            wd.onSelect = function(_, v) r.who = v ~= "" and v or nil; save(); panel.Refresh() end
            local del = Button(p, "dl" .. i, "\195\151", "ghost", function()
                table.remove(rows, i); save(); panel.Refresh()
            end, 22)
            del:SetPoint("TOPLEFT", PAD + iw - delW + 4, -(y + 1))
            y = y + 28
        end
        for i = #rows + 1, 16 do
            for _, id in ipairs({ "mk", "tk", "wh" }) do local it = p.items[id .. i]; if it then it:Hide() end end
        end
        local add = Button(p, "add", L["Add a row"], "ghost", function()
            rows[#rows + 1] = { task = "" }; panel.Refresh()
        end)
        if #rows >= 12 or not boss then setOff(add, L["Twelve rows at most."]) end
        local announce = Button(p, "say", L["Announce"], "primary", function()
            local n, err = R:Say("fight", R.AssignmentLines(boss, rows))
            status = { text = err or string.format(L["Said in %d line(s)."], n), color = err and C.warn or C.ok }
            panel.Refresh()
        end)
        if not boss then setOff(announce, L["Pick a boss"]) end
        local forget = Button(p, "forget", L["Back to the plan"], "ghost", function()
            R:SaveAssignments(snap.inst, boss, nil); rows = nil; panel.Refresh()
        end)
        if from ~= "saved" then setOff(forget, L["Nothing saved for this boss."]) end
        y = ButtonRow({ announce, add, forget }, PAD, y + 4, iw)
        local st = Note(p, "status", status.text, status.color, PAD, y, iw)
        y = y + NoteHeight(st, iw) + PAD
        local planH = y

        -- Right: the pull, the marks, the HUD.
        local s = side.pool
        s:Begin()
        local inner = rw - 2 * PAD
        local sy = CARD_TOP
        local pt = Text(s, "pullT", L["Pull timer"], 12, C.textSoft)
        GuildOS:ApplyFont(pt, 12, "button")
        pt:SetPoint("TOPLEFT", PAD, -sy)
        sy = sy + 18
        local pulls = {}
        for _, sec in ipairs({ 10, 15 }) do
            local b = Button(s, "pull" .. sec, string.format(L["Pull %ds"], sec), "secondary", function()
                local okv, err = R:Pull(sec)
                status = { text = okv and L["Sent."] or err, color = okv and C.ok or C.warn }
                panel.Refresh()
            end)
            pulls[#pulls + 1] = b
        end
        sy = ButtonRow(pulls, PAD, sy, inner)
        local mt = Text(s, "markT", L["Mark my target"], 12, C.textSoft)
        GuildOS:ApplyFont(mt, 12, "button")
        mt:SetPoint("TOPLEFT", PAD, -sy)
        sy = sy + 18
        local mx = PAD
        for i = 8, 0, -1 do
            local b = Button(s, "mark" .. i, i == 0 and DASH or string.format("|T" .. MARK_ICON .. ":16:16|t", i), "chip", function()
                local okv, err = R:MarkTarget(i)
                if not okv and err then status = { text = err, color = C.warn }; panel.Refresh() end
            end, 22)
            b:SetWidth(28)
            if mx + 28 > PAD + inner then mx, sy = PAD, sy + 26 end
            b:SetPoint("TOPLEFT", mx, -sy)
            mx = mx + 30
        end
        sy = sy + 34

        local HUD = GuildOS.RaidHUD
        local ht = Text(s, "hudT", L["Cooldown HUD"], 12, C.textSoft)
        GuildOS:ApplyFont(ht, 12, "button")
        ht:SetPoint("TOPLEFT", PAD, -sy)
        sy = sy + 20
        if HUD and GuildOS.Client.isAnniversary then
            local cb = s:Take("hudOn", function(h) return UI:CreateCheckbox(h, L["Show it in raids (leader and assistants)"]) end)
            cb:SetPoint("TOPLEFT", PAD - 2, -sy)
            cb.checkbox:SetChecked(HUD:IsEnabled())
            cb.checkbox.onChanged = function(_, on) HUD:SetEnabled(on); panel.Refresh() end
            sy = sy + 26
            if HUD:IsEnabled() and HUD:IsHidden() then
                local back = Button(s, "hudBack", L["Hidden until the next raid: show it again"], "ghost", function()
                    HUD:SetHidden(false); panel.Refresh()
                end)
                back:SetPoint("TOPLEFT", PAD, -sy)
                sy = sy + 24
            end
            -- The preview: the HUD's own rows, read off the people on screen.
            local frame = s:Take("prev", function(h)
                local f = CreateFrame("Frame", nil, h, "BackdropTemplate")
                f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(f) })
                f:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 0.82)
                f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
                f.title = UI:CreateText(f, L["Cooldowns"], 11, C.gold2.r, C.gold2.g, C.gold2.b)
                f.title:SetPoint("TOPLEFT", 6, -3)
                f.body = CreateFrame("Frame", nil, f)
                f.body:SetPoint("TOPLEFT", 0, -HUD.HEADER_H)
                f.body:SetPoint("TOPRIGHT", 0, -HUD.HEADER_H)
                return f
            end)
            local members = {}
            for _, person in ipairs(snap.people) do
                if person.class ~= "" and (person.status == "signed" or person.status == "here" or person.status == "extra") then
                    members[person.name] = person.class
                end
            end
            local hrows = HUD.Rows(HUD:Tracked(), members, HUD.state, GetTime())
            local h = HUD:FillBody(frame.body, hrows)
            frame.body:SetHeight(math.max(1, h))
            frame:SetSize(HUD.WIDTH, HUD.HEADER_H + math.max(h, 16) + 4)
            frame:SetPoint("TOPLEFT", PAD, -sy)
            sy = sy + HUD.HEADER_H + math.max(h, 16) + 12
            local about = Note(s, "hudAbout", L["The only thing on screen in combat: each cooldown, how many are ready, when the next is back. Drag it, fold it, × hides it until the next raid."],
                C.textSoft, PAD, sy, inner)
            sy = sy + NoteHeight(about, inner) + PAD
        else
            local about = Note(s, "hudAbout", L["The cooldown HUD reads the combat log, which only TBC Anniversary gives to addons."],
                C.textSoft, PAD, sy, inner)
            sy = sy + NoteHeight(about, inner) + PAD
        end
        local sideH = sy

        if stacked then
            Lay(plan, 0, 0, W, planH)
            Lay(side, 0, planH + GAP, W, sideH)
            return planH + GAP + sideH
        end
        Lay(plan, lx, 0, lw, planH)
        Lay(side, rx, 0, rw, sideH)
        return math.max(planH, sideH)
    end
end

----------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------
function GuildOS:CreateRaidToolsPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = (RT() and RT():Store().part) or "build"

    -- The header card on the wood (the mockup's "Ferramentas de raide"): its title and whose raid it reads,
    -- the source and the raid pickers, Refresh, the parts as pills.
    local card = UI:CreateCard(parent, L["Raid Tools"], { dark = true })
    card:SetPoint("TOPLEFT", 0, -GAP)
    card:SetPoint("TOPRIGHT", -GAP, -GAP)
    card:SetHeight(HEAD_H)
    parent.card = card
    card.title:ClearAllPoints()
    card.title:SetPoint("TOPLEFT", PAD, -12)
    local summary = UI:CreateText(card, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    GuildOS:ApplyFont(summary, 12, "button")
    summary:SetPoint("LEFT", card.title, "RIGHT", 8, 0)
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(false) end
    parent.summary = summary

    local source = UI:CreateDropdown(card, 180, 22)
    source:SetPoint("TOPLEFT", PAD, -CARD_TOP)
    local sopts = {}
    for _, k in ipairs(RT().SOURCES) do sopts[#sopts + 1] = { value = k, text = SOURCE_WORD[k] } end
    source:SetOptions(sopts)
    parent.source = source
    local raid = UI:CreateDropdown(card, 240, 22)
    raid:SetPoint("LEFT", source, "RIGHT", 8, 0)
    parent.raid = raid
    local refreshBtn = UI:CreateButton(card, L["Refresh"], 70, 22)
    refreshBtn:SetPoint("TOPRIGHT", -PAD, -CARD_TOP)
    parent.refreshBtn = refreshBtn

    local bar = CreateFrame("Frame", nil, card)
    bar:SetPoint("TOPLEFT", PAD, -(CARD_TOP + 30))
    bar:SetPoint("TOPRIGHT", -PAD, -(CARD_TOP + 30))
    bar:SetHeight(22)

    local subTabBtns = {}
    local function refreshSub(info)
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    local function selectSub(key)
        if not parent.subPanels[key] then key = "build" end
        parent.activeSub = key
        if RT() then RT():Store().part = key end
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do UI:SetSelected(btn, k == key) end
        refreshSub(parent.subPanels[key])
    end
    parent.SelectSub = selectSub
    parent.RefreshActive = function()
        refreshSub(parent.subPanels[parent.activeSub])
    end
    refreshBtn:SetScript("OnClick", function() parent.RefreshActive() end)

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:SetButtonVariant(UI:CreateButton(bar, t.label, 40, 22), "chip")
        btn:SetWidth(math.ceil(btn.label:GetStringWidth() or 40) + 22)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + btn:GetWidth() + 6  -- a pill its label grew pushes the next one (issue #28)
    end

    -- The pickers: the source, and the raid (the site's raids for the site, this game's raids otherwise).
    local function fillPickers(snap)
        source:SetValue(snap.kind)
        local R = RT()
        local opts = {}
        if snap.kind == "site" then
            for _, r in ipairs(R:SiteRaids()) do
                local when = (tonumber(r.startsAt) or 0) > 0 and date("%d/%m %H:%M", r.startsAt) or ""
                opts[#opts + 1] = { value = r.raidId or r, text = ((r.title ~= "" and r.title) or r.instance or L["Raid"]) .. (when ~= "" and ("  \194\183  " .. when) or "") }
            end
            raid:SetOptions(opts)
            raid:SetPlaceholder(L["No raid from the site"])
            raid:SetValue(snap.roster and (snap.roster.raidId or snap.roster) or nil)
        else
            for _, def in ipairs(R:InstanceList()) do
                opts[#opts + 1] = { value = def.key, text = string.format("%s (%d)", R:InstanceName(def), def.size) }
            end
            raid:SetOptions(opts)
            raid:SetPlaceholder(L["Pick a raid"])
            raid:SetValue(snap.inst)
        end
        raid:SetShown(#opts > 0 or snap.kind == "site")
        local bits = { snap.label, string.format(L["%d players"], #snap.people) }
        summary:SetText("\194\183  " .. table.concat(bits, "  \194\183  "))
    end
    source.onSelect = function(_, v) RT():SetSourceKind(v); parent.RefreshActive() end
    raid.onSelect = function(_, v)
        if RT():SourceKind() == "site" then RT():ChooseSiteRaid(v) else RT():PickInstance(v) end
        parent.RefreshActive()
    end

    -- A part: a scroll frame under the header card, its cards laid by the part's function.
    local builders = { build = BuildBuild, groups = BuildGroups, ready = BuildReady, fight = BuildFight }
    for _, t in ipairs(SUBTABS) do
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -GAP)
        p:SetPoint("BOTTOMRIGHT", 0, GAP)
        p:Hide()
        local scroll, content = UI:CreateScrollFrame(p, "GuildOSRaidTools_" .. t.key)
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
        UI:BindScrollChildWidth(scroll, content)
        local info = { panel = p }
        p.Refresh = function() parent.RefreshActive() end
        local draw = builders[t.key](p, content)
        info.refresh = function()
            local snap = Snapshot()
            fillPickers(snap)
            local W = UI:LaidWidth(content)
            if not W or W < 200 then W = math.max(200, UI:LaidWidth(parent) - GAP - UI.SCROLL_GUTTER) end
            local h = draw(snap, W)
            content:SetHeight(math.max(1, h + GAP))
        end
        parent.subPanels[t.key] = info
    end

    -- The group changes under the raid leader: redrawn at most twice a second while the screen shows.
    local ev = CreateFrame("Frame", nil, parent)
    local pending = false
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "READY_CHECK_FINISHED" }) do GuildOS.Compat.RegisterEvent(ev, e) end
    ev:SetScript("OnEvent", function()
        if pending or not parent:IsVisible() then return end
        pending = true
        GuildOS.Compat.After(0.5, function()
            pending = false
            if parent:IsVisible() then parent.RefreshActive() end
        end)
    end)

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "build")
    end)
end
