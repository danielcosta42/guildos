# Settings in six sub-tabs, and three fewer top-level tabs

Issue: danielcosta42/guildos#367. Approved by the maintainer on 2026-11-17, with mockups.

## 1. Problem

Settings had five categories as buttons:
- General held nearly everything: profile, scale, 20+ module switches, nine shortcuts, options, chat, mentions and the LFG notice. That came to about 1,850px of scroll in a 620px window.
- Loot was a single pointer.
- Raid mixed a group tag with penalties each core already has.
- About held backup, diagnostics and "Erase guild data" above its own title.

Other problems:
- "View Errors" appeared twice.
- There were four ways to reload.
- Every row sat at a fixed pixel offset, and each category click rebuilt the page with new frames.

At the top of the window, an officer on WoW: Forever had 15 tabs. At 1000px the last one, Settings itself, fell into the "»" menu.

## 2. Settings

Six sub-tabs, in the hub pattern the other tabs use (`UI:CreateTab` sub-tabs and `UI:FlowBar`), fixed above the scroll. The code lives in `UI/SettingsPanel.lua`.

| Page | Holds | Who |
|---|---|---|
| Profile | raid roles, login digest (and "show it now"), Discord opt-out (Forever), welcome again | everyone |
| Interface | scale, style (Forever), game font, minimap button, minimap dots, guild button, item tooltips | everyone |
| Chat and alerts | chat annotations, mentions and watch-words, LFG notice | everyone; officer chat options for officers |
| Modules | window tabs and background modules, each with what it does and a "reload" badge where it needs one | everyone |
| Guild rules | who is an officer, who creates events and of which kinds, attendance penalties, raid group, minimum item level (Forever), !note, founding letter (Forever) | officers change, members read |
| Data and support | backup, restore, export, diagnostics, debug logging, tests (officers), about, links; "Erase guild data" last, as the danger button | everyone |

How the pages behave:
- **Built once.** A page is built the first time it opens. After that it only re-reads its values, and on a resize it lays itself out again. It is rebuilt only when its shape changes: the player's rank, the guild's ranks, the features listed, or the chat modules' data appearing.
- **Rows.** Each row is a control with its explanation under it. Sections have a Sans SemiBold 14 title and a 1px rule. The page is one column up to 640px; the module lists split into two columns from a 900px window.
  A field's label column is 260px, or 40% of a narrow page, so a box and its Save button still fit at 380px.
- **Reload strip.** One strip at the bottom appears while a change waits for a reload, with a single Reload button. A change switched back is no longer counted.
  It counts background modules, the game font and an officer unticking their own rank. The style picker keeps its own
  reload prompt, as it did.
- **Deep links.** `/gos open settings <page>` opens a page directly. The old category names still land on their page.

What left Settings:
- **The nine quick-access buttons.** Each is already a tab, a footer button or a command. Two needed a new home:
  - the login digest went to Profile;
  - the data export went to Data and support.
- **The Loot category.** The Loot window's Rule tab is the only place for loot settings.
- **Two leftovers.** The auto-invite pointer (it lives in Recruitment) and the second View Errors.
- **The retail Loot Council** gets a button in the Loot window.

## 3. Top-level tabs

- **Trials** becomes a sub-tab of Recruitment, for officers.
- **Journal and Achievements** become sub-tabs of Guild, on WoW: Forever.

The three keep their registry entries as `tab = false` with `opens`, so their switches and `/gos open` keep working.

Details:
- **A sub-tab goes with its host.** `UI:IsFeatureAllowed` refuses one whose host tab is refused, so with Recruitment
  off, Trials is offered nowhere (and the Now tab's "trials ready" row goes with it).
- **`/gos open` says why.** For these entries it refuses a disabled, failed or officer-only feature with the tab's own
  messages. DKP and Wishlist take the same path, so `/gos open dkp` with DKP switched off now says so.
- **A builder that errors** is recorded and its sub-tab refused for the session, never left half built.
- **Like DKP and Wishlist,** the three leave the minimap menu, which lists tabs only.
- **The login line** for trials ready to review names Recruitment > Trials.

The result:
- An officer on Forever goes from 15 to 12 tabs.
- On Anniversary and retail, an officer goes from 13 to 12.

## 4. Checks

- `tools/settings-panel.lua` checks:
  - the six pages and the old names;
  - that switching pages and resizing build no frame (a mutation that rebuilds on every switch fails it);
  - the module columns;
  - the reload strip;
  - sub-options greying out with their parent;
  - members reading the rules while officers change them;
  - that every setting the old panel had is still on a page.
- `tools/settings-panel-forever.lua` runs the same checks under the WoW: Forever style, plus what only Forever
  does: the sub-tabs wear the game's tab art, the game's font is locked on with its reason, the style picker
  offers the other style, and the reload strip's button is the game's red one.
- `tools/commands-in-ui.lua` keeps every slash command reachable from the interface.
