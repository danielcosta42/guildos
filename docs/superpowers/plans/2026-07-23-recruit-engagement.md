# Recruitment engagement dashboard (Leadership sub-tab)

Branch `feat/tier3`. Officer-facing analytics: who is actively recruiting, how many invites they sent,
how many joins came from their own invites, plus guild totals and a week-over-week trend so leadership
can see when recruitment is saturating and stop. Design approved by the user: attribution =
confirmed-direct-invite; scope = full (per-member table + guild totals + trend).

## Honesty constraint (drives the whole design)
WoW exposes no who-invited-whom attribution. Everything is what a client can observe about ITSELF and
self-report. "Joined" therefore means: a name THIS client invited (a GuildInvite it issued) that then
appeared in a "has joined the guild" system message within a short window. A member who only POSTS in a
channel gets no join credit (the officer who issued the invite does). That is why Posts and Joined are
separate columns; the UI must label them so nobody reads Joined as total attribution.

## Data model

### Layer 1: local self-tracking (`db.myRecruitStats`, per client)
Raw, pruned to 14 days so both the current week and the prior week are derivable:
```
db.myRecruitStats = {
  posts   = { <ts>, ... },        -- one ts per successful recruitment send
  invites = { <ts>, ... },        -- one ts per GuildInvite this client issued
  joins   = { <ts>, ... },        -- one ts per confirmed join from this client's own invite
  pending = { [shortName] = ts },  -- invited names awaiting a join match
}
```
Hooks (all in code this client runs):
- **post**: call `RecruitEngagement:RecordPost()` from `Recruitment:DoSendRecruitmentMessage` on a
  successful send (after the security-hardened sanitized send). Append `time()` to `posts`.
- **invite**: call `RecruitEngagement:RecordInvite(name)` from every GuildInvite site this addon owns:
  `Recruitment:_DoInvite` (auto-invite), the scout whisper invite (`RecruitmentSystem.lua` ~line 777),
  and the right-click chat invite hook (`HookChatInvite`). Append `time()` to `invites` and set
  `pending[short] = time()`. NOTE in the report: invites issued purely through Blizzard's own guild UI
  (not through GuildOS) are not counted; this is a known, stated limitation.
- **join**: extend the existing join detector in `Recruitment:RegisterWelcomeEvent` (the CHAT_MSG_SYSTEM
  "has joined the guild" parse). On a detected join, if `pending[short]` exists and is within
  `JOIN_WINDOW = 1800` s (30 min), append `time()` to `joins` and clear `pending[short]`.
- **prune**: drop `posts`/`invites`/`joins` entries older than 14 days and `pending` entries older than
  `JOIN_WINDOW`, on each record and on init.

Pure helpers (unit-tested, no db/time side effects, take an explicit `now` and list):
- `_CountSince(list, now, fromSecAgo, toSecAgo)` -> count of ts in the half-open window.
- `_Bucketize(list, now)` -> `{d0..d6}` daily counts for the last 7 days (index 0 = today).
- `_MatchJoin(pending, short, now, window)` -> boolean (in-window match) so the join credit rule is pinned.

### Layer 2: sync (`CommSystem` MSG type "RS")
Each client derives and broadcasts a compact self-report; officers aggregate. Identity is the ENVELOPE
sender, never the payload (same rule as RI). Accept only over GUILD.
- Packet (LibSerialize): `{ daily = { posts={d0..d6}, invites={d0..d6}, joins={d0..d6} },
  prev = { posts, invites, joins }, part = <bool>, last = <ts> }` where `prev` is the 7-14d totals for
  the week-over-week trend and `part` is the opt-out participation state.
- Send: from `CommSystem:HandleRequest` (the login + periodic pull path, alongside the other domains),
  and on the 300s periodic push. Small; no throttle concerns.
- Receive (`RecruitEngagement:HandleStats(sender, data, channel)`): reject non-GUILD; deserialize;
  **sanitize/clamp every number** to a sane ceiling (e.g. each daily <= 500, prev <= 5000) so a hostile
  or corrupt packet cannot break the UI; store keyed by the envelope sender short-Realm key:
  `db.recruitStats[key] = { daily, prev, part, last, receivedAt = time() }`. Only officers need to store
  (guard on `IsOfficer()`), members can drop it.
- Prune `db.recruitStats` entries with `receivedAt` older than 14 days (member went quiet / left).
- Trust note: stats are self-reported, so a member can inflate their OWN numbers (vanity only, no
  permission rides on this). Keying by envelope sender prevents reporting for someone else. Document it.

### Layer 3: aggregate for the UI
`RecruitEngagement:GetAggregate(now)` returns, from `db.recruitStats`:
- `rows`: one per member `{ name, part, posts7, invites7, joins7, dailyInvites={d0..d6}, last, stale }`
  where `posts7 = sum(daily.posts)` etc., `stale = (now - receivedAt) > 86400`. Sorted posts7 desc then
  joins7 desc.
- `totals`: `{ posts7, invites7, joins7, conv = joins7/invites7, postsPrev, invitesPrev, joinsPrev }`
  (Prev = sum of each member's `prev`), so the UI shows conversion and week-vs-week deltas.
Pure, testable against a fake `db.recruitStats` and an explicit `now`.

## Task split

### B1: data + sync (`Modules/RecruitEngagement.lua` new, `Modules/RecruitmentSystem.lua`,
`Modules/CommSystem.lua`, `GuildOS.toc`, `Core/Core.lua`)
- New module with Layer-1 storage + hooks, Layer-2 sync, Layer-3 aggregate, and self tests for the pure
  helpers (`_CountSince`, `_Bucketize`, `_MatchJoin`, `GetAggregate` sums/sort/conv, number clamp).
- Add `RS` to `CommSystem.MSG_TYPES`, a dispatch branch passing `(sender, data, channel)`, and a
  `HandleRequest` send. Do NOT alter other message types.
- One-line record calls inserted into the existing RecruitmentSystem hook points listed above.
- `.toc` + `InitModules` wiring. luacheck 0/0. No UI.

### B2: Leadership sub-tab (`UI/ManagementPanel.lua`, `Locales/*`)
- Add `{ key = "recruiting", label = L["Recruiting"] }` to the SUBTABS list and a `BuildRecruiting`
  section following the existing sub-tab idiom (scroll frame with `SetAllPoints`, row reset each refresh,
  per-container refresh, no `self.uiRefresh` singleton hijack).
- Render the approved mockup: guild totals (Posts / Convites / Entraram / Conversao), a week-over-week
  trend line (this week vs prev as +/- deltas) and a small text-bar sparkline of `dailyInvites`, then the
  per-member table (Membro / Status / Posts / Convites / Entrou / Ultimo). Status: `off` when not
  participating, `paused` when participating but no activity in 48h, else `active`. Grey stale rows.
- Officer-only (the whole management tab already is). Locale keys in all 5 files, grep-first, specifiers
  matched, real translations, no em dashes.

## Constraints
luacheck 0/0. Rule 4 (version APIs via Compat), rule 10 (no business logic in UI callbacks: the UI reads
`GetAggregate`, computes nothing of consequence). Conventional Commits, no AI attribution, no em dashes.
Each task its own commit; B2 depends on B1's `db.recruitStats` shape and `GetAggregate`.

## Self review
- Attribution honesty preserved: Joined = own-invite confirmed only, labelled as such. ✓
- Identity bound to envelope sender; GUILD-only; numbers clamped on receipt. ✓
- Alive without an officer is irrelevant here (officer-only view), but stats still relay via HandleRequest
  so an officer logging in gets a fresh picture. ✓
- Pure helpers tested; UI is a thin renderer over GetAggregate. ✓
