# Alliance chat: every line crosses, nobody has to be online (issue #431)

## Why

Under the alliance code (`GOS=TAG:key:Guilda A;Guilda B`, #348) there are no ambassadors: everyone who
runs Guild OS in an allied guild must see everyone else. Reported: some lines did not cross, and the code
only reached the guild when an officer pressed "send to the guild" while people were online.

## What

### The lines (Modules/AllianceLink.lua)

1. **Trust is the channel, not a roster.** The sender of a channel line is the server's, and only who read
   the key is on the channel. A line is drawn under the guild its code names. The synced rosters are no
   longer asked: they can be days old (a member changed guild, a namesake on another realm, the index is
   by short name) and used to drop real lines in silence.
2. **Our own guild's code** is dropped for `/g` (the game already shows it) and **taken for the room**
   ("A"), which reaches a guildmate only through the channel.
3. **A line that does not fit** with its 5-byte frame goes in up to 3 channel lines, cut on a space and a
   UTF-8 boundary, in the same key press (`Link.Split`). Nothing is cut off.
4. **Sending** (Core/Compat.lua `HookChatSend`) covers every chat box, the temporary windows' too
   (`FCF_OpenTemporaryWindow`), and a client that calls `ParseText(true)`.

### The code (Modules/AllianceLink.lua)

5. **Short, no list of guilds.** The code is `GOS=TAG:key` (27 bytes at most). Who holds the key is the
   alliance. The listed form (`GOS=TAG:key:Guilda A;Guilda B`) is still read, for codes already pasted.
6. **The guilds find each other.** A guild is learned when it proves the key: a line on the passworded
   channel (its name from the speaker's mesh presence, `gosg`), or a data op whose `_k` is the key's proof
   for its sender. The mesh's peers advertising our tag (`gosa`) are only candidates: AllianceSync sends
   them a HEAD, and their proved answer makes them ours. A line of a guild not met yet is shown all the
   same, tagged "Allied guild". A guild silent for 30 days is forgotten.
7. **In the guild master's public note.** Every member reads it whenever the roster comes in: the server
   sends it with nobody else online. The officer's save writes it there (the note's other words kept while
   they fit 31 bytes) where the game lets an addon write notes (TBC Anniversary); a new guild master's empty
   note gets it from any officer's client by itself. WoW: Forever and retail forbid it: no one pastes
   anything, the guild hands it on (8).
   * When the note **changes**, its code wins over the addon's copy.
   * A code taken out of the same guild master's note is a removal; a new guild master without one is not.
   * Another code in a note this client cannot change: the save is refused with a reason.
8. **Everybody hands it on.** Any member answers an `ask` (`have`), a holder from the note too. An `ask`
   from somebody holding a newer revision makes the others ask back (at most once every 30 s), so a holder
   logging in hands it on, not only a newcomer asking. The origin is what is checked, not the relay: a copy
   counts when the officer it names is one on the roster, or when it says it came from the guild master's
   note and our own copy of that note says the same. A relayed copy before the roster loads waits for it.

## Limits (the game's)

* A line in a chat lockdown (secret values) neither goes nor is read.
* A line sent by a macro does not cross: no key was pressed.
* Who does not run Guild OS does not see the other guilds.

## Tests

`luajit -e 'ADDON="."' tools/alliance-link.lua` (sections 5, 8 and 9).
