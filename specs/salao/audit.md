# Systems audit (#448, epic #444)

The maintainer asked that, alongside the redesign, every system be "functional, simple and direct". Six
read-only passes covered every module:
- raids and loot;
- leadership and moderation;
- the remaining member modules;
- community and the alliance;
- crafts, the bank, data and sync.

Each finding cites the code: an id, the file and line, and the proposal. The maintainer's priorities were:
- the alliance (redrawn on its own in `alianca.md`);
- moderation, which is badly calibrated;
- bans, which were never tested;
- bulk actions and invites on WoW: Forever.

Nothing here has been run in the game. A finding read from code is checked again before it is changed.

**How to approve:** say "A ok" for all of list A, and for list B one by one ("B3 yes, B7 no").

---

## A. Defects to fix: no product choice, the player sees it working

| Id | Where | What is wrong | Fix |
|---|---|---|---|
| M1 | BanList.lua:46, RosterLog.lua:36 | On Forever a name from chat ("Chehul-Costa") is cut at the hyphen: a ban never alerts on a whisper or rejoin, and one first name matches every namesake | Read the hyphen as the surname's space on surname clients |
| N1 | Core.lua:1173 `IsOfficerByName` | Same cut: on Forever every officer sync from an officer with a surname is dropped (alts, marks, sheet, reminders, trials) | Match whole names, space and hyphen alike |
| N2 / N12 | AltAutoDetect.lua:410, RecruitEngagement.lua:348 | Same cut: alt self-claims always refused; recruiting stats filed under wrong keys | The same tolerant match |
| M2 | BanList.lua:500 `HoldInvite` | Manual invites check only alliance bans, never the guild's own list | Check the guild's own bans first, with "Invite anyway" |
| M11 | GuildManager.lua:371 | The roster menu's Set Rank, Promote, Demote and Remove, plus Ranks, Inactivity, Suggestions and Presets, only print "protected" and open Blizzard's panel. Set Rank throws away the rank picked | Every single-member rank action goes through the working one-per-click queue (BulkActions); Set Rank leaves |
| M13 | BulkActions.lua:559 | On Forever a member is marked "sent" as soon as the line prints, and can never be retried | Add Retry for unconfirmed members |
| M14 | RecruitmentSystem.lua:1546 | `/gos recruit invite Chehul Costa` takes only "Chehul" | Parse the whole name |
| C1 | AllianceLink.lua:328, Calendar.lua:1481 | Alliance slot requests always fail (they go to ambassadors, and there are none) | Covered by the alliance redesign |
| C15 | Commands.lua:423 | `/gos reset` erases the guild's whole database with no confirmation | Confirm dialog |
| D11 | Backup.lua:48 | Restore replaces the guild's whole database with no confirmation, and sits under "Your data" | Confirm dialog, labelled "Whole guild database" |
| C16 | Commands.lua:214 | Commands are case-sensitive, and an unknown one opens the roster | Lowercase the verb; an unknown command opens nothing |
| R1 | Core.lua:1424 | On Anniversary and Forever the guild's loot system is each player's own: a raider set to "external" never gets the master looter's popups | Publish and accept the officer's choice on every client, as retail does |
| R2 | SpecChecker.lua:351 | Inspecting a pug writes them as a guild member, and a pug raid can then count for attendance | Update only real members; `IsGuildRaid` reads the roster |
| R3 | WishlistSystem.lua:493 | Outside retail anyone can post a wishlist in another player's name | The list is always its sender's, over GUILD |
| R4 | LootMaster.lua:672 (#48) | A /roll goes to the first raider sharing the first name | Only an exact single match counts |
| R12 | SpecChecker.lua:315 | The spec scan stalls for good if an inspect never answers | 3 s timeout |
| R15 | Points.lua:363 | The points de-dupe set is wiped at 2,000 entries, so a resent op applies twice | Drop the oldest ops instead |
| R19 | CoreManager.lua:581 | Reading a core's settings creates the core | Create only on purpose |
| R20 | SettingsPanel.lua:979 | Settings' loot test overwrites a real roll in progress | Refuse while a roll is open |
| N4 | TrialTracker.lua:657 | A late note from one officer undoes another's approval | A decided trial always beats an undecided one; notes merge |
| N6 | MemberMarks.lua:161 | A removed mark comes back after 90 days | Keep the last revision per key, as AltSync does |
| N11 | RecruitBeacon.lua:422 | "Broadcast while I'm online" is ignored when the site's ad exists; every officer re-sends it every minute | Honour the switch; one sender |
| D5 | CommSystem.lua:212 | With "Comm System" off, the client still sends but never receives, and says nothing | Gate sending too, and say "sync off" |
| M3 | ManagementPanel.lua:840 | The ban list builds new frames on every refresh and keystroke | Pool the rows |
| C7 | Alliance.lua:1496 | The alliance overview shows the wrong channel name | Covered by the alliance redesign |
| R5 | RaidTracker.lua:570 | Raid sessions and their 5-minute snapshots are kept forever and re-sent whole after each raid | Drop snapshots once attendance is built; send recent sessions only |
| N5 | TrialTracker.lua:598 | The whole trials table, evaluation notes included, goes to every member over GUILD; nothing is pruned | Over OFFICER, per trial, with a cap and pruning |

### Performance (#285: the addon allocates memory while idle)

| Id | What | Fix |
|---|---|---|
| D1 | Every client asks the whole guild for its data every 10 min and answers any ask after 2 min. With a few people online, everybody re-sends everything every ~2 min | Keep only the login ask and the manual Sync; skip a send whose data did not change |
| D2 | Every General/Trade line allocates a table and a closure; every roster update scans the roster for the guild master; `DropDeparted` runs every 5 s | Filter by channel before allocating; coalesce; run at most once a minute |
| D3 | On Anniversary the recipes go out three ways and print a chat line on every profession window | Send only when they change; print only when the count changes |
| D4 | On Forever and Retail recipes are saved twice | Build the second view at run time |
| D9 / D10 | Own data collected three times at login; an equipment swap triggers ~32 collections | One path; coalesce 1 s |

### Dead code (nothing visible)

- **R8:** the TMB import has no callers; the "TMB" system is the "Wishlist" system.
- **R9:** the Points "Loot Council" mode does nothing.
- **R16:** `AUTO_ANNOUNCE` is set and never read.
- **R17:** the attendance score is computed in two places.
- **R10:** a second loot-equity report counts stacks wrong.
- **M16:** `_DoInvite`'s dropped argument and the dead `managementLog` fallback.
- **N9:** note tags nothing can set, `DeleteNote` and the Portuguese `QUICK_TAGS`.
- **N10:** `MemberHistory:Warn` has no caller.
- **D13:** `db.lastSync` is never written.
- **C11:** the alliance board is rebuilt on every client.
- **D8:** the officers' publish list is copied twice.
- **N14:** roster-key parsing is written four times.

---

## B. Changes that need a decision

### Moderation (the "badly calibrated" report)

| Id | Proposal |
|---|---|
| B1 (M6) | **Links:** one link fires two popups (the word rule and the flood). Delete the default "link" words and leave links to the flood check, at 3 links in 120 s |
| B2 (M7) | **Default phrases:** remove the ones that flag the guild's own recruiting ("recrutando para guilda", 招人, 길드원 모집) and ordinary banter ("burro"); poaching at medium, offence at low |
| B3 (M8) | **Flood limits:** <ul><li>capitals: 20 letters and 85% (newcomers 14);</li><li>repeats: 4 in 60 s, ignoring lines under 4 letters (so "gz gz gz" passes);</li><li>bursts: 6 in 10 s (newcomers 4);</li><li>"me", "co" and "de" no longer count as domains</li></ul> |
| B4 (M9) | **Combat:** in combat or an instance, alerts go to the panel only, with one summary when combat ends. No window over the raid frames and no raid-warning sound |
| B5 (M10) | **Rules:** severity editable per rule, and one shared list for every officer (today each officer matches the defaults in their own language) |

### Bans

| Id | Proposal |
|---|---|
| B6 (M4) | Confirm before lifting a ban; an expired temporary ban cannot be shared |
| B7 (C13) | "Share with the alliance" means the site's alliance: label it so, and hide it when there is no alliance |

### Leadership

| Id | Proposal |
|---|---|
| B8 (M12) | **Presets become saved Bulk rules**, and Suggestions read the same rules. Today presets treat unknown attendance as 0 (a trial with no raids becomes a kick candidate), ignore the safe list, and use 90% where Suggestions use 80% |
| B9 (N15) | Approving a trial offers to queue the promotion |
| B10 (N8) | **Officer text about a member lives in five places:** <ul><li>the game's note;</li><li>dated notes;</li><li>the sheet;</li><li>trial notes;</li><li>the nickname.</li></ul> Fold the dated notes and trial notes into one timeline, keep the sheet as the long text, and keep one of the three "trials ready" alerts |
| B11 (N3, N7) | `!note` only works on Anniversary: hide it elsewhere. On Forever, officer notes, sheets and marks stay on the client (the game has no officer channel there): say so on screen |
| B12 (N13) | Alt detection's "Not now" is a permanent no: rename it "Don't ask again", or make it last one session |
| B13 (M15) | On Forever, a /who that returns nothing says it may be blocked on this client (#45) |

### Raids and loot

| Id | Proposal |
|---|---|
| B14 (R6) | An imported soft-reserve sheet stops counting once its raid night is over |
| B15 (R7) | Readiness ignores a consumables check older than 12 h |
| B16 (R8, R9) | The "TMB" system becomes "Wishlist", and the Points "Loot Council" mode becomes DKP. One fewer choice each, no other change |
| B17 (R11) | Awards are always recorded. The Loot Tracker switch only hides the screen; today, off, it silently stops the "already received" rules |
| B18 (R14) | The raid prompt's "Later" really asks again later, instead of meaning "never" |
| B19 (R18) | One cooldown list for Raid Tools and the HUD; the HUD logs only raid members |
| B20 (R13) | Resistances are scanned only on Anniversary, where their tab exists |

### Community, sync and commands

| Id | Proposal |
|---|---|
| B21 (C14) | **One login queue:** onboarding, the founding letter, the digest and the raid prompt show one at a time, never stacked |
| B22 (C17) | **Slash commands:** ~121 patterns, 62 documented. Keep help, open, find and a few more; diagnostics go under `/gos debug …`; prefix matches that swallow their neighbours are fixed |
| B23 (C18, #286) | Remove the guild map (the guild uses another addon for it) |
| B24 (C19) | Polls become a kind of post in Notices; Milestones feed from the Journal |
| B25 (D6) | **Module switches follow one rule:** a switch stops its module and its sync, or it goes. "Crafts" off also stops the recipe sync; Points follows the DKP switch |
| B26 (D7) | **"Sync" means one thing:** the two buttons that only send are renamed "Send to guild", and the bar's Sync also refreshes professions and the bank |
| B27 (D12) | The "who crafts this?" window becomes a "Search the realm" action inside the Workshop |
| B28 (D14) | On Anniversary the Workshop says "open each profession once to share it" |

### The alliance

| Id | Proposal |
|---|---|
| B29 | The alliance redrawn as `alianca.md` describes: one alliance on the site (by invite or as a federation); the chat code and its data delivered by the companion; the pact, the bridge sync and the Manage tab removed |

---

## Decisions (the maintainer, 2026-11-26)

- **List A:** all approved, including the performance and dead-code items.
- **List B, approved:** B1 to B19 and B21 to B29.
- **List B, refused:** B20. Resistances keep being scanned on every client, as today.
- **Added by the maintainer: nothing drawn over the screen opens in combat**, not only the moderation
  alerts (B4).
  - That covers the login popups, the raid prompt, calls to arms, group notices, join-request notices and
    any other window an event opens.
  - Each waits until combat ends and shows then, one at a time (B21).
- **B16:** the loot rule should already come from the site. Before changing the loot systems, check how the
  site's loot rule (guildos-web specs 078, 083, 084) reaches the addon and what is left of the addon's own
  choice. The plan comes back to the maintainer.
- **B29:** the site first, then the addon.

### Order of the work

1. List A (defects).
2. The approved B items, by area.
3. The B16 investigation, back to the maintainer.
4. The alliance on the site (an issue in guildos-web), then in the addon.
