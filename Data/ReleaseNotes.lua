----------------------------------------------------------------------
-- Guild OS - this release's notes, written by the release workflow (tools/release_notes_lua.py).
-- What's new opens with them at the first login with this version (Modules/Onboarding.lua).
----------------------------------------------------------------------
GuildOS.RELEASE_NOTES = {
    version = "2.0.0",
    lines = {
        "Guild OS 2.0, the Hall: Guild OS redrawn from top to bottom in a look of its own, closer to WoW: Forever, with the Hall, rooms and a parchment-and-wood style on every screen, a game-wide search and a compact bar.",
        "A welcome to 2.0: What's new, a guided tour for members, raid leaders, officers and the Guild Master on the real screens, and a Help hub under \"?\" and in Settings; /gos tour and /gos whatsnew bring them back at any time.",
        "What's new opens by itself at the first login with every new version, with that version's notes.",
        "The Officers' Room, redesigned: recruitment that posts to every channel in one click, roster maintenance (Data audit, time in rank, alt-aware inactivity, note search, Former members), moderation with a plain-language rule helper, bans, an audit log backfilled from the game's guild event log, and detection of renamed members.",
        "Members, redesigned: full-width figures, filters on the side, class crests, Guild OS and founder marks with a legend; the member window with clear equipment, history and alts.",
        "Raids: Raid Tools for raid leaders (invite the site's list, announce in /raid, fight assignments, a minimal combat HUD you can hide), and Groups with activity cards and the people who fit.",
        "The guild's group finder has a \"My quests\" category: look for or form a group for quests in your quest log, and see who else is on the same quest.",
        "The guild map shows guildmates live, works alongside OpenMap, and shows the guild's campfires on WoW: Forever.",
        "The guild bank, redrawn: the bar, the Cleanup drawer, the ledger and the vendor window that sells only what came out of the bank, laid out so every language fits (thanks to the German players who reported the overlaps).",
        "Settings: two-column cards, a Credits page with the Chehul family, and the game's font back as an option.",
        "Lighter: no frame leaks, far less garbage per minute, compact saved data, and /gos debug mem to see it.",
        "The Hall's Notice board shows the three newest bulletin notices again, as 1.39.0 promised (thanks Ley, Max Hammerschlag (Tarok)).",
        "Closed the loot table by mistake? /gos lm reopens it while an item is still to give, and the chat line that says the loot window closed carries a link that reopens it (thanks Baz).",
        "\"Use the game's font\" is back in Settings › Interface: every Guild OS text in the game's own font after a reload (thanks Gedeon).",
        "DKP: \"Back to whoever loses (%)\" sits right under \"Cost to enter a roll\", says it only works with an entry cost, and is greyed out while that cost is 0 (thanks Devuthios).",
        "The Hall's \"By the fire\" card says how many guildmates are online now, and its title explains the card on hover (thanks Ley).",
        "The search finds settings and screens by what they do: \"flood\" or \"spam\" finds the anti-flood card of Alert rules, \"welcome\", \"invite\", \"whisper\", \"font\", \"backup\" and more find their place (thanks Talex).",
        "Add alt lists up to six guild characters that start with what you type, in their class colours: Up and Down to choose, Tab, Enter or a click to take one (thanks Blendomino).",
        "An alt whose main (or another alt) runs Guild OS counts as having it on the account: it leaves Officers' Room › Without GuildOS and its reminder (a setting there turns this off), the member window says \"GuildOS on <character>\", and the companion export marks it for the site (thanks Max Hammerschlag (Tarok)).",
        "Officers' Room › Former members, and filters for the audit log, to see who left and why (thanks Savagegirli).",
        "A popup when a member leaves or is removed, with the note, the ban and their alts in one place, and a \"welcome back\" note when a former member returns (thanks DamnDude).",
        "Several welcome messages, one drawn at random for each newcomer (thanks Ley).",
        "A legend and filters for the Members screen (thanks Ley).",
        "WoW: Forever: every dungeon is known by its instance and its bosses, the five new ones added since launch and the classic ones, so their clears reach the guild's journal; /gos debug probe shows a report of the dungeons and bosses the game sent, to paste in Discord, so the ones still unconfirmed get confirmed (thanks Einstorm).",
        "WoW: Forever: Onyxia's attunement, from the Horde and Alliance quest chains or the Drakefire Amulet in bags or bank, in Readiness, the Members screen, the member window, Raid Tools and the companion export (thanks Ricki).",
        "Guild bank tax: the Guild Master can set a share of each item withdrawn that the member owes the guild until they deposit gold; the ledger shows each withdrawal's tax and who owes what, and the member is told gently what they owe. Off by default (thanks Ley).",
        "Points for bank donations: an officer can have deposits to the guild bank earn points under one of the guild's named reasons and its weekly cap, granted once by a single officer's client, each grant naming its ledger line (thanks Snuchyboochy).",
        "WoW: Forever: the guild's events in the game's calendar, and who answered each, go to guildos.me with the companion export (thanks Excsuze, Volo, Paisley).",
        "The alt link prompt no longer asks again and again about the same characters (thanks Volo, Nachoman).",
        "Guild OS no longer makes the server answer \"You are doing that too fast\", and stops its own chat spam (thanks S4ro).",
        "WoW: Forever: the game lets no addon invite to the guild, so Guild OS hands the officer the /ginvite line to copy and send, the only way the game allows (thanks firehead94).",
        "The first login with this version keeps the previous version's saved data for 7 days before converting it to the compact format, and says so once; /gos backup shows it, copies it for an older version, or deletes it now.",
        "Settings › Data and support never offers to delete this guild's data, including a copy of it saved under another realm name on WoW: Forever, and the login digest never counts those as old databases.",
        "Older changelog entries are now in English."
    },
}
