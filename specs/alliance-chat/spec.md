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

5. **In the guild info, as GreenWall.** An officer's save also writes the `GOS=` line in the guild info
   (the rest of the text kept, the old line replaced; not written when it would pass 500 bytes or the
   officer cannot edit it). Every member reads the guild info at login and at each roster update: the
   server sends it with nobody else online.
   * When the info's text **changes**, its code wins over the addon's copy.
   * A code read from the info and gone from it is a removal, but an empty info (not sent yet) is not.
   * A code that does not name this guild is ignored.
   * An officer who cannot edit the info, facing **another** code there, is refused with a reason: that
     code would win at every login. With no code there, the save goes by sync alone, as before.
6. **The sync relay works both ways.** An `ask` from somebody holding a newer revision makes the others ask
   back (at most once every 30 s), so a holder logging in hands the code on, not only a newcomer asking.
7. **A relayed copy before the roster loads** (nobody reads as an officer yet) waits and is checked again
   when the roster comes in, instead of being lost.

## Limits (the game's)

* A line in a chat lockdown (secret values) neither goes nor is read.
* A line sent by a macro does not cross: no key was pressed.
* Who does not run Guild OS does not see the other guilds.

## Tests

`luajit -e 'ADDON="."' tools/alliance-link.lua` (sections 5, 8 and 9).
