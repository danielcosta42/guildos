-- The Former members screen (Officers' Room > Members > Former members; specs/salao/manutencao-roster.md §6), run
-- against the whole addon (every file the TOC loads) under the Officers' Room harness's stub client (the prelude of
-- tools/officer-cards.lua, read from that file and run here, so the two never drift apart). TBC Anniversary.
--
--   * The list, from the member history (who left and has not come back), the ban list, the officers' notes and
--     the alt links: each row's departure, how, passages, days in the guild, ban, notes and alts; officers only.
--   * The filters and their counts, the search over the name and the notes, the three sorts, the cache.
--   * The actions call the module that owns each: Ban... (BanList:AddGroup on the whole alt group, with the reason
--     typed in the question), Unban (the group's bans lifted), Invite back (BanList:HoldInvite first; the game's
--     invite on this click; on WoW: Forever the /ginvite line to copy), Forget (the question says local only; yes
--     deletes the history and the permanent note from this client and from its outbox).
--   * The member window opens for a key that is not in the roster, with no error: its history, permanent note,
--     alts and ban, and none of what only a present member has.
--   * The screen: built, its chips and search filter the rows, a row's click opens the member, its buttons act.
--
--   luajit -e 'ADDON="."' tools/former-members.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── The harness: tools/officer-cards.lua's stub client and the whole addon, loaded ─────────────────────────────
do
  local fh = assert(io.open(ADDON .. "/tools/officer-cards.lua", "rb"))
  local src = fh:read("*a")
  fh:close()
  local cut = src:find("\n-- ── Boot, with a guild of fourteen", 1, true)
  check(cut ~= nil, "the officer-cards harness has its boot marker")
  local chunk, err = loadstring(src:sub(1, cut), "=officer-cards prelude")
  check(chunk ~= nil, "the harness prelude compiles: " .. tostring(err))
  chunk()
end

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
local function said(fragment)
  for _, m in ipairs(printed) do if m:find(fragment, 1, true) then return true end end
  return false
end
local invited = {}
GuildInvite = function(name) invited[#invited + 1] = name end
local officer = true
GetGuildInfo = function() return "Chama", officer and "Mestre" or "Social", officer and 0 or 4 end

PEOPLE = {
  { "Chehul", "PALADIN", "Shattrath", true, "Mestre", 0 }, { "Thrandor", "HUNTER", "Shattrath", true },
  { "Lunara", "DRUID", "Karazhan", true, "Oficial", 1 }, { "Kaelis", "MAGE", "Quel'Danas", true },
}
local okBoot, errBoot = pcall(function() GuildOS:Initialize(); GuildOS:ResolveGuildDB(); GuildOS:InitModules() end)
check(okBoot, "the addon boots under the stub: " .. tostring(errBoot))
for _ = 1, 3 do pcall(FLUSH) end

local L = GuildOS.L   -- the harness client speaks ptBR: every text is read through it
local FM, MH, BL, AQ = GuildOS.FormerMembers, GuildOS.MemberHistory, GuildOS.BanList, GuildOS.ActionQueue
check(FM and MH and BL and AQ, "the modules are loaded")
check(GuildOS:IsOfficer(), "the player is an officer")

-- ── The guild's past ────────────────────────────────────────────────────
local NOW = GetServerTime()
local DAY = 86400
local function ago(d) return NOW - d * DAY end
local function K(n) return GuildOS:KeyOfRosterName(n .. "-MundodeForever") end
local db = GuildOS.db
local h = db.memberHistory
for k in pairs(h) do h[k] = nil end
db.altLinks = db.altLinks or {}
h[K("Aelwyn")] = { cls = "MAGE", ranks = {}, stints = {
  { joinAt = ago(400), leftAt = ago(300), how = "leave" }, { joinAt = ago(200), leftAt = ago(5), how = "leave" } },
  note = { text = "Came back twice; good raider", author = "Chehul", ts = NOW, rev = NOW } }
h[K("Miraelle")] = { cls = "DRUID", ranks = {}, stints = { { joinAt = ago(30), leftAt = ago(12), how = "leave" } } }
db.altLinks[K("Miraelle")] = K("Aelwyn")
h[K("Borrin")] = { cls = "PRIEST", ranks = {}, stints = { { joinAt = ago(60), leftAt = ago(2), leftEst = true, how = "gone" } } }
h[K("Torvald")] = { cls = "HUNTER", ranks = {}, stints = { { leftAt = ago(45), how = "kick", by = "Chehul" } } }
h[K("Grimlock")] = { cls = "WARRIOR", ranks = {}, stints = { { joinAt = ago(90), leftAt = ago(30), how = "kick", by = "Lunara" } } }
h[K("Selwyn")] = { cls = "ROGUE", ranks = {}, stints = { { joinAt = ago(500), leftAt = ago(120), how = "leave" } } }
-- A present member with a history: never a former one.
h[K("Kaelis")] = { cls = "MAGE", ranks = {}, stints = { { joinAt = ago(300) } } }
-- A key whose last passage is open again (came back): never a former one either.
h[K("Thrandor")] = { cls = "HUNTER", ranks = {}, stints = { { joinAt = ago(300), leftAt = ago(200), how = "leave" }, { joinAt = ago(100) } } }
BL:Add("Grimlock", "Ninja de loot")
BL:Add("Selwyn", "Roubou o banco", 14 * DAY)
db.officerNotes = db.officerNotes or {}
db.officerNotes[K("Borrin")] = { notes = { { text = "Asked to come back in December", author = "Chehul", timestamp = ago(1) } }, tags = {} }
db.memberHistoryOut = { { k = K("Borrin"), a = "l", t = ago(2) }, { k = K("Kaelis"), a = "j", t = ago(300) } }

-- ── 1. The pure parts ───────────────────────────────────────────────────
check(FM.BanState(nil, NOW) == nil and FM.BanState({ removed = true }, NOW) == nil, "no ban, or a lifted one: none")
check(FM.BanState({ expiry = NOW - 1 }, NOW) == nil and FM.BanState({ expiry = NOW + 60 }, NOW) == "suspended"
  and FM.BanState({ reason = "x" }, NOW) == "banned", "a running term is a suspension, none a ban, one run out nothing")
check(FM.KindOf("kick", nil) == "removed" and FM.KindOf("leave", nil) == "left" and FM.KindOf("gone", nil) == "left"
  and FM.KindOf("leave", "suspended") == "banned", "the three exclusive filters: a ban first, then a removal, else left")
check(FM.AgoText(0) == L["Today"] and FM.AgoText(1) == L["1 day ago"] and FM.AgoText(9) == string.format(L["%d days ago"], 9), "how long ago")

-- ── 2. The list ─────────────────────────────────────────────────────────
local data = FM:Rows(true)
local byName = {}
for _, r in ipairs(data.rows) do byName[r.name] = r end
check(#data.rows == 6, "six former members (not the present one, not the one who came back): " .. #data.rows)
check(byName.Kaelis == nil and byName.Thrandor == nil, "a present member is not listed")
local a = byName.Aelwyn
check(a and a.class == "MAGE" and a.stints == 2 and a.days == 295 and a.ago == 5 and a.how == "leave" and a.kind == "left",
  "a row: the class the history kept, the passages, the days over all of them, how long ago, how")
check(a.hasNotes and a.note == "Came back twice; good raider" and a.hasAlts and not a.ban, "the permanent note and the alts")
check(byName.Miraelle.hasAlts and not byName.Miraelle.hasNotes, "an alt has alts too")
check(byName.Borrin.hasNotes and byName.Borrin.note == nil and byName.Borrin.leftEst, "a dated officer note counts as notes")
check(byName.Torvald.kind == "removed" and byName.Torvald.by == "Chehul" and byName.Torvald.days == nil, "a removal; no known start")
check(byName.Grimlock.kind == "banned" and byName.Grimlock.ban == "banned" and byName.Grimlock.banReason == "Ninja de loot",
  "a ban in force: banned, with the reason")
check(byName.Selwyn.ban == "suspended" and byName.Selwyn.banUntil == NOW + 14 * DAY, "a temporary ban: suspended until")
local c = data.counts
check(c.all == 6 and c.left == 3 and c.removed == 1 and c.banned == 2 and c.notes == 2,
  string.format("the counts: all %d, left %d, removed %d, banned %d, notes %d", c.all, c.left, c.removed, c.banned, c.notes))
check(FM.HowText(byName.Torvald) == string.format(L["removed by %s"], "Chehul") and FM.HowText(a) == L["left"]
  and FM.HowText(byName.Grimlock) == L["banned"] and FM.HowText(byName.Borrin) == L["left or was removed"]
  and FM.HowText(byName.Selwyn) == string.format(L["suspended until %s"], GuildOS:DateText(NOW + 14 * DAY, "/%Y")),
  "how each went, as the row says it")

-- Filters and search.
local function names(rows) local t = {} for _, r in ipairs(rows) do t[#t + 1] = r.name end return table.concat(t, ",") end
check(#FM.Filter(data.rows, "left") == 3 and #FM.Filter(data.rows, "removed") == 1 and #FM.Filter(data.rows, "banned") == 2
  and #FM.Filter(data.rows, "notes") == 2 and #FM.Filter(data.rows, "all") == 6, "each filter holds its count")
check(names(FM.Filter(data.rows, "all", "grim")) == "Grimlock", "the search finds a name, any case")
check(names(FM.Filter(data.rows, "all", "GOOD RAIDER")) == "Aelwyn", "the search finds the permanent note")
check(names(FM.Filter(data.rows, "all", "december")) == "Borrin", "and an officer's dated note")
check(#FM.Filter(data.rows, "banned", "aelwyn") == 0, "the filter and the search together")

-- Sorts.
check(names(FM.Sort(FM.Filter(data.rows), "left", false)) == "Borrin,Aelwyn,Miraelle,Grimlock,Torvald,Selwyn",
  "by the last departure, newest first (the default)")
check(names(FM.Sort(FM.Filter(data.rows), "name", true)) == "Aelwyn,Borrin,Grimlock,Miraelle,Selwyn,Torvald", "by name")
check(names(FM.Sort(FM.Filter(data.rows), "days", false)) == "Selwyn,Aelwyn,Grimlock,Borrin,Miraelle,Torvald",
  "by days in the guild, most first, unknown last")
check(names(FM.Sort(FM.Filter(data.rows), "days", true)):sub(-7) == "Torvald", "unknown days last the other way too")

-- Cache, and officers only.
check(FM:Rows() == data, "cached")
FM:Invalidate()
check(FM:Rows() ~= data, "Invalidate reads the stores again")
officer = false
check(#FM:Rows(true).rows == 0, "a member sees no former member")
officer = true
data = FM:Rows(true)
byName = {}
for _, r in ipairs(data.rows) do byName[r.name] = r end

-- ── 3. The actions ──────────────────────────────────────────────────────
local function dialog(which)
  for i = 1, 6 do
    local f = _G["GuildOSDialog" .. i]
    if f and f.shown and f.which == which then return f end
  end
end
local function accept(f) f.button1.scripts.OnClick(f.button1) end

-- Ban...: asks with a reason; yes bans the whole alt group.
check(FM:Ban(byName.Miraelle), "Ban... asks")
local f = dialog("GUILDOS_FORMER_BAN")
check(f and f.editBox.shown and tostring(f.text.text):find(string.format(L["%s and their %d other character(s)"], "Miraelle", 1), 1, true), "the question names the group")
f.editBox:SetText("Drama no raid")
accept(f)
check(BL:IsBanned("Miraelle") and BL:IsBanned("Aelwyn"), "both characters of the group are banned")
check(BL:Get("Aelwyn").reason == "Drama no raid" and BL:Get("Aelwyn").expiry == nil and BL:Get("Miraelle").group == "Aelwyn",
  "for good, with the reason, marked as the group's")
data = FM:Rows()
byName = {}
for _, r in ipairs(data.rows) do byName[r.name] = r end
check(byName.Aelwyn.ban == "banned" and data.counts.banned == 4, "the list reads the ban at once (the cache went)")

-- Unban: asks; yes lifts the group's bans.
check(FM:Unban(byName.Aelwyn), "Unban asks")
f = dialog("GUILDOS_FORMER_UNBAN")
check(f and tostring(f.text.text):find("Aelwyn", 1, true), "the question names them")
accept(f)
check(not BL:IsBanned("Aelwyn") and not BL:IsBanned("Miraelle"), "the group's bans are lifted")
check(BL:IsBanned("Grimlock"), "nobody else's")

-- Invite back. WoW: Forever (the harness's client) lets no addon invite: the /ginvite line to copy.
printed = {}
data = FM:Rows()
byName = {}
for _, r in ipairs(data.rows) do byName[r.name] = r end
local client = GuildOS.Client
check(client.game == "FOREVER" and not GuildOS.Compat.AddonMayInvite(), "the harness's client is WoW: Forever")
local before = #invited
check(FM:InviteBack(byName.Torvald) == "typed" and #invited == before, "Forever: nothing invited by the addon")
check(AQ:NextTyped() == "Torvald" and AQ.TypedLine("Torvald") == "/ginvite Torvald", "Forever: the line to copy is offered")
AQ:DoneTyped()
check(said(MH:Describe("Torvald", K("Torvald"))), "and the officer reads, in chat, when they were a member")
-- TBC Anniversary: the game's invite, on this click.
client.isAnniversary = true
local got = FM:InviteBack(byName.Borrin)
check(got == "ran" and invited[#invited] == "Borrin", "Invite back invites at once: " .. tostring(got))
-- A banned one: held with "Invite anyway".
before = #invited
check(FM:InviteBack(byName.Grimlock) == "held" and #invited == before, "a ban holds the invite")
f = dialog("GUILDOS_ALLIANCE_BAN_INVITE")
check(f and tostring(f.text.text):find("Ninja de loot", 1, true), "the question says why")
accept(f)
check(invited[#invited] == "Grimlock", "Invite anyway invites")
client.isAnniversary = false   -- back to the harness's Forever (its member keys depend on it)
officer = false
check(FM:InviteBack(byName.Borrin) == false and FM:Ban(byName.Borrin) == false and FM:Forget(byName.Borrin) == false
  and FM:ForgetNow(K("Borrin")) == false, "a member does none of it")
officer = true

-- Forget: asks, saying it is this client's only; yes deletes the history and the note, and the outbox's records.
check(FM:Forget(byName.Aelwyn), "Forget asks")
f = dialog("GUILDOS_FORMER_FORGET")
check(f and tostring(f.text.text) == string.format(L["Forget %s? Their membership history and permanent note are deleted from this client only. The history syncs between officers as records that are never deleted: the other officers keep theirs, and a sync may bring part of it back. Bans, officer notes and alt links stay."], "Aelwyn")
  and (GetLocale() ~= "enUS" or tostring(f.text.text):find("this client only", 1, true)),
  "the question says it is local only")
check(h[K("Aelwyn")] ~= nil, "nothing deleted before the answer")
accept(f)
check(h[K("Aelwyn")] == nil and MH:GetNote(K("Aelwyn")) == nil, "the history and the permanent note are gone")
check(db.altLinks[K("Miraelle")] == K("Aelwyn"), "the alt links stay")
check(FM:ForgetNow(K("Borrin")) and #db.memberHistoryOut == 1 and db.memberHistoryOut[1].k == K("Kaelis"),
  "the outbox's records of them go too (the login backfill does not send them again)")
check(GuildOS.OfficerNotes:GetNotes(K("Borrin"))[1] ~= nil, "the officer notes stay")
check(not FM:ForgetNow(K("Kaelis")) and h[K("Kaelis")] ~= nil, "a present member is never forgotten")
check(#FM:Rows().rows == 4, "the list reads it at once")

-- ── 4. The member window, for a key not in the roster ───────────────────
local function texts(fr, out)
  out = out or {}
  if not fr.shown then return out end
  if fr.kind == "FontString" and fr.text and fr.text ~= "" then out[#out + 1] = tostring(fr.text) end
  for _, ch in ipairs(fr.children) do texts(ch, out) end
  return out
end
local function has(list, s) for _, t in ipairs(list) do if t:find(s, 1, true) then return true end end return false end
check(GuildOS:GetMemberRecord("Grimlock") == nil, "Grimlock is not in the roster")
data = FM:Rows(true)
byName = {}
for _, r in ipairs(data.rows) do byName[r.name] = r end
local errs = #(GuildOS.errorLog or {})
local okOpen, errOpen = pcall(function() return FM:Open(byName.Grimlock) end)
check(okOpen and errOpen == true, "the member window opens for a former member: " .. tostring(errOpen))
local frame = GuildOS.DetailFrame
check(frame and frame.shown, "the window is shown")
local all = texts(frame)
check(has(all, L["Ex-member"]) and has(all, string.format(L["Left the guild on %s"], "")), "its line says Ex-member and when they left")
check(has(all, string.format(L["Banned: %s"], "Ninja de loot")), "and the ban")
check(has(all, string.format(L["removed by %s"], "Lunara")), "the history's passage")
check(not has(all, L["Equipment"]) and not has(all, L["Talent spec"]) and not has(all, L["Professions"]),
  "none of what only a present member has")
check(not has(all, L["Discipline rules"]), "nor the guild's discipline rules")
check(#(GuildOS.errorLog or {}) == errs, "no error recorded")
-- With notes and alts: Miraelle's card shows its group.
check(FM:Open(byName.Miraelle), "an alt's card opens")
all = texts(frame)
check(has(all, L["Linked characters"]) and has(all, "Aelwyn"), "the alt group")
-- A present member's card still has its sections.
if GuildOS.Mesh then GuildOS.Mesh.PresenceSuffix = function() return "" end end   -- the stub has no mesh peers
local rec = GuildOS:GetMemberRecord("Kaelis")
check(rec ~= nil, "a present member's record")
GuildOS:ShowMemberDetail(rec)
all = texts(frame)
check(has(all, L["Equipment"]) and has(all, L["Talent spec"]) and not has(all, L["Ex-member"]), "a present member's card is as before")
frame:Hide()

-- ── 5. The screen ───────────────────────────────────────────────────────
local host = newFrame_("Frame", UIParent)
host:SetSize(1000, 600)
local okBuild, refresh = pcall(GuildOS.BuildFormerMembersSub, GuildOS, host)
check(okBuild and type(refresh) == "function", "the screen builds: " .. tostring(refresh))
local function find(fr, test)
  if not fr.shown then return nil end
  if test(fr) then return fr end
  for _, ch in ipairs(fr.children) do local x = find(ch, test) if x then return x end end
end
local function findAll(fr, test, out)
  out = out or {}
  if not fr.shown then return out end
  if test(fr) then out[#out + 1] = fr end
  for _, ch in ipairs(fr.children) do findAll(ch, test, out) end
  return out
end
local holder = find(host, function(x) return x.kind == "ScrollFrame" end)
check(holder ~= nil, "the screen has its list")
holder.parent:SetSize(900, 400)
refresh()
pcall(FLUSH)
local rows = findAll(host, function(x) return x.kind == "Button" and rawget(x, "item") ~= nil end)
check(#rows == 4, "a row for each former member: " .. #rows)
check(has(texts(host), L["All"] .. " (4)") and has(texts(host), L["Banned"] .. " (2)") and has(texts(host), L["With notes"] .. " (0)"),
  "the chips count")
local chip = find(host, function(x) return rawget(x, "kind") == "banned" and rawget(x, "base") ~= nil end)
chip.scripts.OnClick(chip)
rows = findAll(host, function(x) return x.kind == "Button" and rawget(x, "item") ~= nil end)
check(#rows == 2 and rows[1].item.ban and rows[2].item.ban, "the Banned chip shows the banned")
local unban = rows[1].buttons.unban
check(unban.shown and not rows[1].buttons.ban.shown, "a banned row offers Unban, not Ban")
local all2 = find(host, function(x) return rawget(x, "kind") == "all" and rawget(x, "base") ~= nil end)
all2.scripts.OnClick(all2)
local search = find(host, function(x) return x.kind == "EditBox" end)
search:SetText("torv")
search.scripts.OnTextChanged(search)
rows = findAll(host, function(x) return x.kind == "Button" and rawget(x, "item") ~= nil end)
check(#rows == 1 and rows[1].item.name == "Torvald", "the search filters the rows")
rows[1].scripts.OnClick(rows[1])
check(GuildOS.DetailFrame.shown and has(texts(GuildOS.DetailFrame), "Torvald"), "a click on a row opens the member")
GuildOS.DetailFrame:Hide()
local inviteBtn = rows[1].buttons.invite
before = #invited
client.isAnniversary = true
inviteBtn.scripts.OnClick(inviteBtn)
client.isAnniversary = false
check(invited[#invited] == "Torvald" and #invited == before + 1, "the row's Invite back invites")
rows[1].buttons.forget.scripts.OnClick(rows[1].buttons.forget)
check(dialog("GUILDOS_FORMER_FORGET") ~= nil, "the row's Forget asks")
dialog("GUILDOS_FORMER_FORGET"):Hide()
check(h[K("Torvald")] ~= nil, "closing the question forgets nothing")
search:SetText("zzz")
search.scripts.OnTextChanged(search)
check(has(texts(host), L["Nobody here: the filter or the search hides them."]), "the empty state when the search hides everyone")
-- Nobody ever left: the empty state says so.
for k in pairs(h) do h[k] = nil end
search:SetText("")
FM:Invalidate()
refresh()
check(has(texts(host), L["No former members yet: Guild OS writes down who leaves from when an officer's client sees it."]), "the empty state when nobody left")
host:Hide()

print(("former-members: %d checks passed"):format(checks))
