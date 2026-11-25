----------------------------------------------------------------------
-- Guild OS - Winter Veil panel (issue #437; the site's specs/119)
-- Layouts from the approved canvas (Addon-Embrulhar, Addon-Abrir, Addon-Perfil, Addon-Revelacao, Addon-Oficial):
--   Mine        whom I drew, the scene and the note I wrap with, and, from the opening on, the globe I got
--   Collection  every globe the account opened; a globe is an image rendered per scene x rarity (Media/Globes)
--   Chain       after the opening, who gave whom what, of the globes already opened
--   Organize    officers: who is in and who wrapped, never a pair
-- Visual layout only: the data, the rules and the requests are GuildOS.WinterVeil's (Rule 10). The rarity is the
-- site's, drawn when the receiver opens: this panel only asks and shows.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local ROW_H = 26
local SITE = "guildos.me"
local GLOBES = "Interface\\AddOns\\GuildOS\\Media\\Globes\\"
local QUALITY = { common = 1, rare = 3, epic = 4, legendary = 5 }

local function rarityColor(r)
    return GuildOS.QualityColors[QUALITY[r] or 1]
end

local function rarityName(r)
    if r == "rare" then return L["Rare"] end
    if r == "epic" then return L["Epic"] end
    if r == "legendary" then return L["Legendary"] end
    return L["Common"]
end

local function sceneName(s)
    if s == "cabin" then return L["Cabin"] end
    if s == "snowman" then return L["Snowman"] end
    if s == "fire" then return L["Campfire"] end
    if s == "mountain" then return L["Mountain"] end
    return L["Tree"]
end

local function colored(text, c)
    return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
end

local function nameOf(key)
    local short = type(key) == "string" and (key:match("^([^-]+)") or key) or "?"
    local rec = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    local cc = rec and rec.class and GuildOS.ClassColors and GuildOS.ClassColors[rec.class]
    return cc and colored(short, cc) or short
end

local function dayOf(t) return date("%d/%m", t) end

-- A globe's image: the scene in its rarity, or the wrapped one. Always square.
local function setGlobe(tex, scene, rarity)
    -- <scene>-<rarity>.tga, or closed.tga: a file name, not a member key.
    local name = (scene and rarity) and string.format("%s\45%s", scene, rarity) or "closed"
    tex:SetTexture(GLOBES .. name .. ".tga")
end

-- A pool of rows under `parent`, each a button with a name on the left and a value on the right.
local function rowPool(parent)
    local rows = {}
    return function(i)
        local r = rows[i]
        if not r then
            r = CreateFrame("Button", nil, parent)
            r:SetHeight(ROW_H)
            r.text = UI:CreateText(r, "", 12, C.text.r, C.text.g, C.text.b)
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetJustifyH("LEFT")
            r.value = UI:CreateText(r, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            r.value:SetPoint("RIGHT", -8, 0)
            r.text:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
            r.sel = r:CreateTexture(nil, "BACKGROUND")
            r.sel:SetAllPoints()
            r.sel:SetColorTexture(C.popup.r, C.popup.g, C.popup.b, 1)
            rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        r.sel:Hide()
        r:SetScript("OnClick", nil)
        r:Show()
        return r
    end, function(from)
        for i = from, #rows do rows[i]:Hide() end
    end
end

-- The page of this guild's event on the site: the key comes with the event (the guild's key is the site's to say), and
-- is encoded as the site encodes it. Without one, the public page, which at least exists.
local function siteLink()
    local e = GuildOS.WinterVeil and GuildOS.WinterVeil:Event()
    local key = e and e.guildKey
    if not key then return SITE .. "/winter-veil" end
    return string.format("%s/guild/%s/winter-veil", SITE, (key:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end)))
end

local function whyText(why)
    return L["Winter Veil: "] .. (
        why == "note" and L["that note is not allowed: up to 80 characters, no links, no @, no markdown."]
        or why == "phase" and L["the wrapping is closed."]
        or why == "companion" and L["wrap it on the site: this needs the companion."]
        or tostring(why))
end

function GuildOS:CreateWinterVeilPanel(container)
    local WV = GuildOS.WinterVeil
    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()
    local view = "mine"
    local scene, pickedTo, selected, seenScene = "tree", nil, 1, false

    -- Head: the event, the Chimney and the guild's counts.
    local title = UI:CreateTitle(panel, L["Winter Veil Secret Santa"], 18)
    title:SetPoint("TOPLEFT", 0, -4)
    local sub = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local chipWrapped = UI:CreateMetricChip(panel, "0", L["wrapped"])
    chipWrapped:SetPoint("TOPRIGHT", 0, -2)
    local chipIn = UI:CreateMetricChip(panel, "0", L["taking part"])
    chipIn:SetPoint("TOPRIGHT", chipWrapped, "TOPLEFT", -12, 0)
    local chimneyText = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    chimneyText:SetPoint("TOPLEFT", 0, -52)
    local chimneyBar = UI:CreateProgressBar(panel, 200, 6)
    chimneyBar:SetPoint("TOPLEFT", 0, -68)
    chimneyBar:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

    local tabs = {}
    local function addTab(id, text, anchor)
        local t = UI:CreateTab(panel, text, 130, true)
        if anchor then t:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else t:SetPoint("TOPLEFT", 0, -82) end
        t:SetScript("OnClick", function() view = id; GuildOS:SafeCall(panel.Draw) end)
        tabs[id] = t
        return t
    end
    local tMine = addTab("mine", L["My secret friend"])
    local tColl = addTab("collection", L["Collection"], tMine)
    local tChain = addTab("chain", L["The guild's chain"], tColl)
    addTab("board", L["Organize"], tChain)

    local none = UI:CreateText(panel, L["The guild has not opened this year's Secret Santa yet. Officers open it on guildos.me."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    none:SetPoint("TOPLEFT", 0, -120)
    none:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    none:SetJustifyH("LEFT")

    local function body()
        local f = UI:CreatePanel(panel)
        f:SetPoint("TOPLEFT", 0, -116)
        f:SetPoint("BOTTOMRIGHT", 0, 0)
        return f
    end

    ------------------------------------------------------------------
    -- Mine
    ------------------------------------------------------------------
    local mine = body()
    local mKicker = UI:CreateSectionTitle(mine, "", true)
    mKicker:SetPoint("TOPLEFT", 12, -10)
    local mLine = UI:CreateText(mine, "", 14, C.text.r, C.text.g, C.text.b)
    mLine:SetPoint("TOPLEFT", 12, -34)
    mLine:SetPoint("RIGHT", mine, "RIGHT", -12, 0)
    mLine:SetJustifyH("LEFT")
    local mNote = UI:CreateText(mine, "", 11, C.label.r, C.label.g, C.label.b)
    mNote:SetPoint("TOPLEFT", 12, -56)
    mNote:SetPoint("RIGHT", mine, "RIGHT", -12, 0)
    mNote:SetJustifyH("LEFT")

    -- In-game participation (a quest of the event turned in): counts for the Chimney, kept by the addon or the site's block.
    local mPlay = UI:CreateText(mine, "", 11, C.label.r, C.label.g, C.label.b)
    mPlay:SetPoint("BOTTOMLEFT", 12, 12)
    mPlay:SetPoint("RIGHT", mine, "RIGHT", -12, 0)
    mPlay:SetJustifyH("LEFT")

    local globe = mine:CreateTexture(nil, "ARTWORK")
    globe:SetSize(128, 128)
    globe:SetPoint("TOPLEFT", 12, -84)
    local globeCaption = UI:CreateText(mine, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    globeCaption:SetPoint("TOPLEFT", globe, "BOTTOMLEFT", 0, -6)
    globeCaption:SetWidth(200)
    globeCaption:SetJustifyH("LEFT")

    -- The wrapping form: one button per scene, the note and what it does.
    local form = CreateFrame("Frame", nil, mine)
    form:SetPoint("TOPLEFT", 232, -84)
    form:SetPoint("BOTTOMRIGHT", -12, 12)
    local sceneBtns = {}
    local prev
    for _, id in ipairs(WV.SCENES) do
        local b = UI:CreateButton(form, sceneName(id), 92, 26)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 0, 0) end
        b:SetScript("OnClick", function() scene = id; GuildOS:SafeCall(panel.Draw) end)
        sceneBtns[id], prev = b, b
    end
    local noteLabel = UI:CreateText(form, L["Note (up to 80)"], 11, C.label.r, C.label.g, C.label.b)
    noteLabel:SetPoint("TOPLEFT", 0, -40)
    local noteBox = UI:CreateTextArea(form, 400, 56, { max = WV.NOTE_MAX, placeholder = L["A few words for them."] })
    noteBox:SetPoint("TOPLEFT", 0, -58)
    noteBox:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    local noteCount = UI:CreateText(form, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    noteCount:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", 0, -6)
    local wrapBtn = UI:CreateButton(form, L["Wrap"], 110, 28)
    wrapBtn:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", 0, -30)
    UI:SetButtonVariant(wrapBtn, "primary")
    local formNote = UI:CreateText(form, "", 11, C.label.r, C.label.g, C.label.b)
    formNote:SetPoint("TOPLEFT", wrapBtn, "BOTTOMLEFT", 0, -10)
    formNote:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    formNote:SetJustifyH("LEFT")
    local giveRow = CreateFrame("Frame", nil, form)
    giveRow:SetPoint("TOPLEFT", formNote, "BOTTOMLEFT", 0, -8)
    giveRow:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    giveRow:SetHeight(ROW_H * 3)
    local giveRowAt, giveHide = rowPool(giveRow)

    -- Joining (before the draw) and the opening button share the action slot.
    local actBtn = UI:CreateButton(mine, "", 160, 28)
    actBtn:SetPoint("TOPLEFT", globeCaption, "BOTTOMLEFT", 0, -10)
    UI:SetButtonVariant(actBtn, "primary")
    local volCheck = UI:CreateCheckbox(mine, L["I can give one more globe if somebody does not wrap"], 18)
    volCheck:SetPoint("TOPLEFT", 12, -84)
    local leaveBtn = UI:CreateButton(mine, L["Leave"], 100, 26)
    leaveBtn:SetPoint("TOPLEFT", 12, -112)

    ------------------------------------------------------------------
    -- Collection
    ------------------------------------------------------------------
    local coll = body()
    local cTitle = UI:CreateSectionTitle(coll, "", true)
    cTitle:SetPoint("TOPLEFT", 12, -10)
    local cList = CreateFrame("Frame", nil, coll)
    cList:SetPoint("TOPLEFT", 12, -34)
    cList:SetPoint("BOTTOMRIGHT", coll, "BOTTOM", -12, 12)
    local cRow, cHide = rowPool(cList)
    local cGlobe = coll:CreateTexture(nil, "ARTWORK")
    cGlobe:SetSize(128, 128)
    cGlobe:SetPoint("TOPLEFT", coll, "TOP", 12, -34)
    local cName = UI:CreateText(coll, "", 14, C.text.r, C.text.g, C.text.b)
    cName:SetPoint("TOPLEFT", cGlobe, "TOPRIGHT", 12, -4)
    local cFrom = UI:CreateText(coll, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    cFrom:SetPoint("TOPLEFT", cName, "BOTTOMLEFT", 0, -6)
    local cNote = UI:CreateText(coll, "", 12, C.text.r, C.text.g, C.text.b)
    cNote:SetPoint("TOPLEFT", cGlobe, "BOTTOMLEFT", 0, -12)
    cNote:SetPoint("RIGHT", coll, "RIGHT", -12, 0)
    cNote:SetJustifyH("LEFT")
    local cHint = UI:CreateText(coll, L["The globe and the year are public on your character's page; the note and who gave it are for your guild only."], 11, C.label.r, C.label.g, C.label.b)
    cHint:SetPoint("BOTTOMLEFT", 12, 12)
    cHint:SetPoint("RIGHT", coll, "RIGHT", -12, 0)
    cHint:SetJustifyH("LEFT")
    cHint:Hide()

    ------------------------------------------------------------------
    -- Chain and officers' table
    ------------------------------------------------------------------
    local chain = body()
    local chTitle = UI:CreateSectionTitle(chain, "", true)
    chTitle:SetPoint("TOPLEFT", 12, -10)
    local chNote = UI:CreateText(chain, "", 11, C.label.r, C.label.g, C.label.b)
    chNote:SetPoint("TOPLEFT", 12, -32)
    chNote:SetPoint("RIGHT", chain, "RIGHT", -12, 0)
    chNote:SetJustifyH("LEFT")
    local chList = CreateFrame("Frame", nil, chain)
    chList:SetPoint("TOPLEFT", 12, -56)
    chList:SetPoint("BOTTOMRIGHT", -12, 12)
    local chRow, chHide = rowPool(chList)

    local function show(which)
        mine:SetShown(which == "mine")
        coll:SetShown(which == "collection")
        chain:SetShown(which == "chain" or which == "board")
    end

    local function draw()
        local e = WV:Event()
        local t = GetServerTime()
        local phase = WV.PhaseOf(e, t)
        none:SetShown(not e)
        for _, tab in pairs(tabs) do tab:SetShown(e ~= nil) end
        chipWrapped:SetShown(e ~= nil)
        chipIn:SetShown(e ~= nil)
        chimneyText:SetShown(e ~= nil)
        chimneyBar:SetShown(e ~= nil)
        if not e then
            sub:SetText("")
            show(nil)
            return
        end
        tabs.board:SetShown(GuildOS:IsOfficer())
        if view == "board" and not GuildOS:IsOfficer() then view = "mine" end
        for id, tab in pairs(tabs) do tab:SetActive(id == view) end

        -- Head.
        local days = math.max(0, math.ceil((e.openAt - t) / 86400))
        sub:SetText(phase == "open" and L["The globes can be opened."]
            or phase == "wrapping" and string.format(L["Wrap until %s · opens in %d day(s)"], dayOf(e.wrapUntil), days)
            or phase == "joining" and string.format(L["Joining until %s"], dayOf(e.joinUntil))
            or string.format(L["Opens in %d day(s)"], days))
        chipIn:SetValue(tostring(e.counts.entrants))
        chipWrapped:SetValue(string.format("%d/%d", e.counts.wrapped, math.max(e.counts.pairs, e.counts.entrants)))
        if e.chimney then
            chimneyText:SetText(string.format(L["The Chimney: %d%% of the players already wrapped"], e.chimney)
                .. (e.chimney >= 100 and ("  " .. colored(L["full: better odds"], C.ok)) or ""))
            chimneyBar:SetProgress(e.chimney / 100)
        else
            chimneyText:SetText(L["The Chimney fills as players wrap, after the draw."])
            chimneyBar:SetProgress(0)
        end
        show(view)

        --------------------------------------------------------------
        if view == "mine" then
            local joined = WV:Joined()
            local gives = WV:MyGives()
            local got = WV:Got()
            for _, b in pairs(sceneBtns) do b:Hide() end
            form:Hide(); volCheck:Hide(); leaveBtn:Hide(); actBtn:Hide(); globe:Hide(); globeCaption:SetText("")
            giveHide(1)
            mNote:SetText("")
            if joined then
                mPlay:SetText((WV:Played() or WV:PlaySeen()) and L["In-game participation: registered"]
                    or L["In-game participation: not yet, complete a Winter Veil quest"])
            else
                mPlay:SetText("")
            end

            -- The opening: the globe I received.
            if phase == "open" then
                mKicker:SetText(L["YOUR GLOBE"])
                globe:Show()
                if got and got.ornament then
                    local o = got.ornament
                    setGlobe(globe, o.scene, o.rarity)
                    mLine:SetText(colored(rarityName(o.rarity), rarityColor(o.rarity)) .. "  ·  " .. sceneName(o.scene) .. "  ·  Winter Veil " .. o.year)
                    local from = o.host and L["Frimm, the host"] or (o.from and nameOf(o.from) or "?")
                    mNote:SetText(string.format(L["From %s"], from) .. (o.note and o.note ~= "" and ("  \"" .. o.note .. "\"") or ""))
                elseif got and got.ready then
                    setGlobe(globe)
                    mLine:SetText(L["Somebody in the guild wrapped a globe for you."])
                    globeCaption:SetText(L["The rarity is drawn by the site when you open it."])
                    actBtn:Show()
                    if WV:OpenRequested() then
                        actBtn:SetText(L["Asked: waiting for the site"])
                        actBtn:SetEnabled(false)
                        mNote:SetText(L["Sync the companion to see it here, or open it on the site."])
                    else
                        actBtn:SetText(L["Open the globe"])
                        actBtn:SetEnabled(WV:HasCompanion())
                        mNote:SetText(WV:HasCompanion() and "" or string.format(L["Open it on the site: %s"], siteLink()))
                        actBtn:SetScript("OnClick", function()
                            local ok, why = WV:RequestOpen()
                            if not ok then GuildOS:Print(whyText(why)) end
                            GuildOS:SafeCall(draw)
                        end)
                    end
                else
                    mLine:SetText(L["There is no globe for you to open yet."])
                    mNote:SetText(string.format(L["Open it on the site: %s"], siteLink()))
                end
                -- What I gave, and its rarity once they opened it.
                local g = gives[1]
                if g and g.rarity then
                    globeCaption:SetText(string.format(L["Yours for %s was %s."], nameOf(g.to), colored(rarityName(g.rarity), rarityColor(g.rarity))))
                end
                return
            end

            if not joined then
                mKicker:SetText(L["SECRET SANTA"])
                if phase == "joining" then
                    mLine:SetText(L["Join the Secret Santa: wrap a snow globe for whoever you draw."])
                    volCheck:Show()
                    actBtn:ClearAllPoints()
                    actBtn:SetPoint("TOPLEFT", 12, -112)
                    actBtn:Show()
                    actBtn:SetText(L["Join"])
                    actBtn:SetEnabled(true)
                    actBtn:SetScript("OnClick", function()
                        WV:Join(volCheck.checkbox:GetChecked())
                        GuildOS:SafeCall(draw)
                    end)
                else
                    mLine:SetText(L["Joining has closed."])
                end
                return
            end

            if not e.drawn then
                mKicker:SetText(L["SECRET SANTA"])
                mLine:SetText(L["You are in. The draw happens after joining closes."])
                if phase == "joining" then
                    leaveBtn:Show()
                    leaveBtn:SetScript("OnClick", function() WV:Leave(); GuildOS:SafeCall(draw) end)
                end
                return
            end

            -- Drawn: whom I drew, and the wrapping.
            mKicker:SetText(L["YOU DREW"])
            if #gives == 0 then
                mLine:SetText(L["Your pair has not reached this client yet."])
                mNote:SetText(L["It comes with the companion, or from a guildmate who has it. You can also wrap on the site."] .. "  " .. siteLink())
                return
            end
            local g = gives[1]
            for _, x in ipairs(gives) do if x.to == pickedTo then g = x end end
            pickedTo = g.to
            mLine:SetText(nameOf(g.to) .. (g.wrapped and ("   " .. colored(L["wrapped"], C.ok)) or ""))
            globe:Show()
            if g.wrapped and g.scene then
                setGlobe(globe, g.scene, "common")
                globeCaption:SetText(L["Preview: the rarity is drawn when they open it."])
            else
                setGlobe(globe, scene, "common")
                globeCaption:SetText(L["Preview: the front plate is fixed, \"Winter Veil\"."])
            end
            if phase ~= "wrapping" then
                mNote:SetText(L["The wrapping is closed. If you did not wrap, Frimm sends it for you."])
                return
            end
            form:Show()
            if g.wrapped and g.scene and not seenScene then scene = g.scene; seenScene = true end
            for id, b in pairs(sceneBtns) do
                b:Show()
                UI:SetButtonVariant(b, id == scene and "primary" or "secondary")
            end
            local note = noteBox.edit and noteBox.edit:GetText() or ""
            -- Fill the box from a note kept here once. SetText fires OnTextChanged, which draws again: mark it first, and only
            -- when there is a note to put, or an empty one would loop through its own handler.
            if note == "" and g.note and g.note ~= "" and not noteBox._seen then noteBox._seen = true; noteBox.edit:SetText(g.note); note = g.note end
            local n = WV.CharCount(note)
            local clean = WV.CleanNote(note)
            noteCount:SetText(string.format("%d/%d", n, WV.NOTE_MAX)
                .. (clean and n >= WV.CAPRICE_MIN and ("  " .. colored(L["a longer note lifts the rarity one level"], C.ok)) or "")
                .. (not clean and ("  " .. colored(L["not allowed"], C.danger)) or ""))
            wrapBtn:SetText(g.wrapped and L["Wrap again"] or L["Wrap"])
            wrapBtn:SetEnabled(clean ~= nil and WV:HasCompanion())
            wrapBtn:SetScript("OnClick", function()
                local ok, why = WV:Wrap(g.to, scene, noteBox.edit:GetText())
                if not ok then GuildOS:Print(whyText(why)) end
                GuildOS:SafeCall(draw)
            end)
            formNote:SetText(WV:HasCompanion() and L["The newest between the site and the game wins."]
                or string.format(L["Wrap it on the site: this needs the companion. %s"], siteLink()))
            -- Two pairs (one taken over): pick which one the form is for.
            local i = 0
            if #gives > 1 then
                for _, x in ipairs(gives) do
                    i = i + 1
                    local row = giveRowAt(i)
                    row.text:SetText(nameOf(x.to))
                    row.value:SetText(x.wrapped and L["wrapped"] or L["not wrapped yet"])
                    if x.to == g.to then row.sel:Show() end
                    row:SetScript("OnClick", function() pickedTo = x.to; GuildOS:SafeCall(draw) end)
                end
            end
            giveHide(i + 1)
            return
        end

        --------------------------------------------------------------
        if view == "collection" then
            local list = WV:Collection()
            cTitle:SetText(string.format(L["COLLECTION · %d"], #list))
            selected = math.min(math.max(1, selected), math.max(1, #list))
            local i = 0
            for idx, o in ipairs(list) do
                i = i + 1
                local row = cRow(i)
                row.text:SetText(colored(rarityName(o.rarity), rarityColor(o.rarity)) .. "  " .. sceneName(o.scene))
                row.value:SetText(tostring(o.year))
                if idx == selected then row.sel:Show() end
                row:SetScript("OnClick", function() selected = idx; GuildOS:SafeCall(draw) end)
            end
            cHide(i + 1)
            local o = list[selected]
            cGlobe:SetShown(o ~= nil)
            cHint:SetShown(true)
            if o then
                setGlobe(cGlobe, o.scene, o.rarity)
                cName:SetText(sceneName(o.scene) .. " · " .. colored(rarityName(o.rarity), rarityColor(o.rarity)))
                cFrom:SetText(string.format(L["From %s"], o.host and L["Frimm, the host"] or (o.from and nameOf(o.from) or "?"))
                    .. "  ·  " .. dayOf(o.openedAt) .. "/" .. o.year)
                cNote:SetText(o.note and o.note ~= "" and ("\"" .. o.note .. "\"") or "")
            else
                cName:SetText(L["No globe yet. The ones you open appear here, on the site and in the game."])
                cFrom:SetText("")
                cNote:SetText("")
            end
            return
        end

        --------------------------------------------------------------
        local i = 0
        if view == "chain" then
            chTitle:SetText(L["THE GUILD'S CHAIN"])
            if phase ~= "open" or not e.reveal then
                chNote:SetText(L["After the opening, the globes already opened show here: who gave whom, the scene and the rarity."])
            else
                chNote:SetText(L["Only the globes already opened. A closed one stays a secret."])
                for _, r in ipairs(e.reveal) do
                    i = i + 1
                    local row = chRow(i)
                    row.text:SetText((r.host and L["Frimm"] or nameOf(r.giver)) .. "  >  " .. nameOf(r.to))
                    row.value:SetText(sceneName(r.scene) .. "  " .. colored(rarityName(r.rarity), rarityColor(r.rarity)))
                end
            end
        else
            chTitle:SetText(L["PARTICIPANTS"])
            chNote:SetText(string.format(L["Nobody sees the pairs, officers included. The rules and the draw are on the site: %s"], siteLink()))
            for _, r in ipairs(e.entrants or {}) do
                i = i + 1
                local row = chRow(i)
                row.text:SetText(nameOf(r.key))
                row.value:SetText(r.wrapped and colored(L["wrapped"], C.ok) or L["not wrapped yet"])
            end
        end
        chHide(i + 1)
    end

    noteBox.edit:HookScript("OnTextChanged", function() GuildOS:SafeCall(draw) end)
    panel.Draw = draw
    panel:SetScript("OnShow", function() GuildOS:SafeCall(draw) end)
    return panel
end
