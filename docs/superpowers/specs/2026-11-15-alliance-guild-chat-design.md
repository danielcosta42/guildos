# The alliance's guild chat (issue #344)

Every line of `/g` in a guild of the alliance shows in the guild chat of every other guild, in the
frames that already show `/g`, in `/g`'s colour, with the speaker's guild as a coloured tag and the
name as a link that whispers them:

```
[Guild] [Guilda B] [Fulano]: alguém pra kara?
```

The alliance reads like one guild, with nothing to join and nothing to switch to. The `GOS<TAG>`
channel stays for the people who want a separate room.

## Options weighed

| Option | Reach | Why / why not |
| --- | --- | --- |
| Addon messages on a hidden custom channel | All addon users | **Refused** on Forever and retail (InvalidChatType), measured in `Libs/LibChehulMesh.lua` v5. |
| Bridge reposts into the real `/g` (`SendChatMessage`) | Everybody, addon or not | Every line is said by the bridge, under its name. Noise, loops to guard, and it puts words in a player's mouth. Left for later, opt-in at best. |
| Point everyone at the custom channel | Everybody | What existed. Nobody reads two places: the channel is not the guild chat. |
| **Bridge relay over WHISPER + GUILD (chosen)** | All addon users | Uses the only two buses that work on every client. Invisible: the lines land where `/g` already is. |

## Flow

1. The guild's bridge (`Alliance:CurrentBridge`, the election `AllianceSync` already uses) reads
   every `CHAT_MSG_GUILD`, batches lines for `BATCH_DELAY` (0.4 s, up to 10) and whispers one `L`
   frame to one client of each allied guild (`ChehulAllyChat`, `AC1|L|<blob>`).
2. That client checks the envelope sender speaks for the guild it claims, shows the lines and says
   them once on GUILD as an `F` frame.
3. Everybody else only receives. Nothing a client receives is ever sent on: only `CHAT_MSG_GUILD`
   is relayed, and the module never makes one. Officer chat and the guild's other channels are not
   read.

Lines are shown once per `DEDUP_WINDOW` (120 s) by guild, speaker and text, so an election overlap,
two receivers in one guild or our own GUILD echo never double a line.

## Routes

Whom to whisper in guild X, in order:

1. Whoever sent us X's chat (or was named as the route in an `F` frame) in the last `ROUTE_TTL`
   (15 min): they are online and run this. Forgotten at once on a "No player named".
2. A presence peer of X advertising `gosc=1` in its HELLO caps (`Mesh:BuildCaps`), freshest first.

Never blind: a guild with no route gets nothing, which is right, since nobody there could show it.

## Trust

- `L` counts only as a WHISPER; its sender (the envelope) must be an ambassador of the guild it
  claims or on that guild's synced roster. Our own guild, a guild outside the pact or a blocked one
  is refused.
- `F` counts only on GUILD, from a guildmate, who could already type anything in `/g`.
- Lines are cleaned: control characters go, item/spell/achievement/quest/… and player links are kept
  whole, every other pipe is made literal, so a peer cannot draw textures or colours of its own.
- `/ignore` and the ambassadors' hide list (`AllianceChat:HiddenSet`) apply.

## Fix carried with it

`Alliance:OnMessage` took HEAD/PULL/PUSH/EVT only from ambassadors, while the bridge that sends them
is any member: guilds synced only while ambassadors happened to be at both ends. Now the data ops
also take a sender on a member guild's synced roster (`Alliance:GuildOfRosterMember`). The pact's
own ops (PACT, LEAVE, EJECT) stay with the ambassadors. A first sync still needs an ambassador at one
end, as the roster that vouches for everyone else comes from one.

## Preference

`AllianceChat` prefs `guildBridge` (on by default): show the allied `/g`. Off only hides it on this
client; it still hands the lines to the rest of its guild. Button **Allied /g** on the Alliance chat
panel; `/gos ally gchat [on|off]` toggles and prints the counters.

## Honest limits

- Who does not run Guild OS does not see the other guilds.
- A line said while the bridge is in a chat lockdown (retail encounters) is unreadable and not sent.
- A line is lost for a guild with no known route at that moment.

Tested offline by `tools/alliance-guild-chat.lua`.
