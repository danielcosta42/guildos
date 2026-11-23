# Without GuildOS: in-game test (issue #422)

Automated: `luajit -e 'ADDON="."' tools/addon-reminder.lua` (the list and its filter, the settings, one
whisper per click, the days per member, the gap, the game's "too fast" and its undo, the record when asked,
the officers' sync, a member refused). In game, an officer and a test guild with an alt without GuildOS:

1. **List.** Leadership > Without GuildOS: the alt is listed with "no GuildOS for N days"; guildmates with
   GuildOS and yourself are not. Name, rank and "Online only" narrow it.
2. **Remind.** Click Remind on the online alt: the alt gets the default text with its name and the guild's;
   the row says "reminded today"; its button stays off; "Hide the ones reminded recently" hides it.
3. **Gap.** Click Remind on a second member at once: "One reminder at a time: wait N s."; the buttons come
   back by themselves.
4. **Other officer.** On a second officer's client the alt reads "reminded today" too, and Remind says
   "Reminded recently".
5. **Text.** Write a text with `{name}`, Save, remind: the whisper is that text. Default puts the
   translated default back.
6. **Record.** Tick "Also file it on the disciplinary record", remind: the alt's record (member card) has
   a warning "Other" with the note; with the box off nothing is filed.
7. **WoW: Forever, busy evening.** Remind several members 10 s apart while the realm is busy: no
   "You are doing that too fast". If it comes right after a reminder, the chat says it did not count and
   the panel holds the next for a minute.
