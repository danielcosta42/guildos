# The alliance, the GreenWall way (issues #344, #348)

Every line of `/g` in a guild of the alliance shows in the guild chat of every other guild, drawn by
the chat frame itself as a line of `/g`, with the speaker's guild as a coloured tag:

```
[Guild] [Guilda B] [Fulano]: alguém pra kara?
```

## Why it was redone

1.24 (#344) relayed `/g` through an elected bridge that whispered one peer of each guild, on top of
a pact built by whisper between ambassadors (INV/ACK/PACT). Every link in that chain needed a
particular person online and a list of names in sync; when one failed, the alliance went quiet
without a word. The ambassador gate even dropped the sync ops of any bridge that was not an
ambassador.

The model now is GreenWall's (AIE-Guild/GreenWall, the base of Greenwall Forever), which needs
nobody in particular.

## Configuration: one line in the guild info

```
GOS=TAG:key:Guilda A;Guilda B;Guilda C
```

- The same line in the guild info of every guild. Every member reads it when the roster loads
  (`GetGuildInfoText`). Nothing is sent, nobody is an ambassador, and only who may edit the guild
  info (the guild's officers) changes it.
- The pact is in force for a client only when the line names its guild. It takes precedence over a
  pact made by invitation, which keeps working where there is no line.
- Alliance > Setup makes the line (the same tag keeps its key), writes it into this guild's info and
  shows it to paste in the others. From an old pact it offers a line with the same tag and guilds.
- Under the line the ops that built the old pact (invite, join, leave, ambassadors, codes) refuse
  with "set in the guild info".

## Chat: a hidden channel, every member carries their own words

- Channel `GOSA<TAG>`, password = the key, joined with `JoinTemporaryChannel`, taken out of every
  chat frame, and its lines and notices filtered from all of them. The old public `GOS<TAG>` is left.
- When the player presses Enter on `/g`, a post-hook of the chat box's `ParseText`
  (`Compat.HookChatSend`) says the line on the channel too, inside the same key press: the only
  moment the game lets an addon speak on a channel. The Guild tab's Send does the same.
- Wire: `<kind><code> <text>`, kind `G` (`/g`) or `A` (the alliance room), code = three base-36
  characters of `Alliance.Hash(guild)`. A line that would pass 255 bytes is cut on a codepoint.
- Received: the speaker is the channel's sender (unforgeable). Dropped when the code is unknown, is
  our guild's, is blocked, when the rosters place the speaker in another guild, when the speaker is
  ignored or the line hidden. `G` is replayed as `CHAT_MSG_GUILD` through the frame's own handler
  (`Compat.ReplayChatEvent`) in every frame that shows `/g`, with the channel's sender, line id and
  GUID, so name link, class colour and timestamp are the game's own. `A` goes to the alliance feed.
- Officer chat and the guild's other channels are never read.

## Data: whisper, trusted by the key

Rosters, calendars and crafters still go by whisper between bridges (timers cannot speak on a
channel). Under the line, `Alliance:Send` adds `_g` (our guild) and `_k` = `Proof(key, sender)`;
`Alliance:OnMessage` runs a data op only for a guild in the line, not ours, not blocked, whose proof
matches the envelope sender. Who never read the key cannot make one; a proof seen is good only for
its own sender.

## Honest limits (GreenWall's too)

- Who does not run Guild OS does not see the other guilds.
- The key is readable by every member of every guild in the line.
- A line sent by a macro does not cross: no key was pressed.
- In a chat lockdown (retail encounters) nothing is said on the channel.

Tested offline by `tools/alliance-link.lua`.
